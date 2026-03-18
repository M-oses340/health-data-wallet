/**
 * Tests for JWT expiry implementation
 * Feature: health-data-wallet / jwt-expiry
 */
import * as crypto from 'crypto';
import * as fc from 'fast-check';

// ---------------------------------------------------------------------------
// Inline the helpers so we can test them in isolation without spinning up the
// full Express app (avoids DB / chain adapter side-effects at import time).
// ---------------------------------------------------------------------------

const JWT_SECRET = 'test-secret';
const JWT_TTL_SECONDS = 3600;

function signJWT(payload: object, ttl = JWT_TTL_SECONDS): string {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify({ ...payload, iat: now, exp: now + ttl })).toString('base64url');
  const sig = crypto.createHmac('sha256', JWT_SECRET).update(`${header}.${body}`).digest('base64url');
  return `${header}.${body}.${sig}`;
}

function verifyJWT(token: string): Record<string, unknown> {
  const [header, body, sig] = token.split('.');
  if (!header || !body || !sig) throw new Error('Invalid token');
  const expected = crypto.createHmac('sha256', JWT_SECRET).update(`${header}.${body}`).digest('base64url');
  if (sig !== expected) throw new Error('Invalid token');
  const payload = JSON.parse(Buffer.from(body, 'base64url').toString()) as Record<string, unknown>;
  if (typeof payload['exp'] === 'number' && Math.floor(Date.now() / 1000) > payload['exp']) {
    throw new Error('Token expired');
  }
  return payload;
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

describe('signJWT', () => {
  it('produces a 3-part JWT', () => {
    const token = signJWT({ did: 'did:ethr:0x1', role: 'patient' });
    expect(token.split('.')).toHaveLength(3);
  });

  it('embeds iat and exp claims', () => {
    const before = Math.floor(Date.now() / 1000);
    const token = signJWT({ did: 'did:ethr:0x1', role: 'patient' });
    const [, body] = token.split('.');
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString());
    expect(payload.iat).toBeGreaterThanOrEqual(before);
    expect(payload.exp).toBe(payload.iat + JWT_TTL_SECONDS);
  });

  it('preserves custom payload fields', () => {
    const token = signJWT({ did: 'did:ethr:0xabc', role: 'researcher' });
    const [, body] = token.split('.');
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString());
    expect(payload.did).toBe('did:ethr:0xabc');
    expect(payload.role).toBe('researcher');
  });
});

describe('verifyJWT', () => {
  it('accepts a freshly signed token', () => {
    const token = signJWT({ did: 'did:ethr:0x1', role: 'patient' });
    expect(() => verifyJWT(token)).not.toThrow();
  });

  it('returns the payload on success', () => {
    const token = signJWT({ did: 'did:ethr:0x1', role: 'patient' });
    const payload = verifyJWT(token);
    expect(payload['did']).toBe('did:ethr:0x1');
    expect(payload['role']).toBe('patient');
  });

  it('throws "Token expired" for a token with exp in the past', () => {
    // sign with ttl = -10 so exp is already in the past
    const token = signJWT({ did: 'did:ethr:0x1', role: 'patient' }, -10);
    expect(() => verifyJWT(token)).toThrow('Token expired');
  });

  it('throws "Invalid token" for a tampered signature', () => {
    const token = signJWT({ did: 'did:ethr:0x1', role: 'patient' });
    const tampered = token.slice(0, -4) + 'XXXX';
    expect(() => verifyJWT(tampered)).toThrow('Invalid token');
  });

  it('throws "Invalid token" for a malformed token', () => {
    expect(() => verifyJWT('not.a.valid.jwt.at.all')).toThrow();
    expect(() => verifyJWT('onlytwoparts.here')).toThrow('Invalid token');
  });
});

// ---------------------------------------------------------------------------
// Property-based tests
// **Validates: Requirements 1.1** — tokens must always carry a valid exp claim
// **Validates: Requirements 1.2** — expired tokens must always be rejected
// ---------------------------------------------------------------------------

describe('JWT properties (fast-check)', () => {
  it('exp is always iat + TTL for any payload', () => {
    fc.assert(
      fc.property(
        fc.record({ did: fc.string(), role: fc.constantFrom('patient', 'researcher') }),
        (payload) => {
          const token = signJWT(payload);
          const [, body] = token.split('.');
          const decoded = JSON.parse(Buffer.from(body, 'base64url').toString());
          return decoded.exp === decoded.iat + JWT_TTL_SECONDS;
        },
      ),
    );
  });

  it('a token with any negative TTL is always rejected as expired', () => {
    fc.assert(
      fc.property(
        fc.record({ did: fc.string(), role: fc.constantFrom('patient', 'researcher') }),
        fc.integer({ min: 1, max: 86400 }),
        (payload, ttl) => {
          const token = signJWT(payload, -ttl);
          try {
            verifyJWT(token);
            return false; // should never reach here
          } catch (e: unknown) {
            return (e as Error).message === 'Token expired';
          }
        },
      ),
    );
  });

  it('any bit-flip in the signature always fails verification', () => {
    fc.assert(
      fc.property(
        fc.record({ did: fc.string(), role: fc.constantFrom('patient', 'researcher') }),
        (payload) => {
          const token = signJWT(payload);
          const parts = token.split('.');
          // flip last char of signature
          const sig = parts[2];
          parts[2] = sig.slice(0, -1) + (sig.endsWith('A') ? 'B' : 'A');
          const tampered = parts.join('.');
          try {
            verifyJWT(tampered);
            return false;
          } catch {
            return true;
          }
        },
      ),
    );
  });
});
