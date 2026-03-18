import * as crypto from 'crypto';

const JWT_SECRET = process.env.JWT_SECRET ?? 'dev-secret-change-in-prod';
const JWT_TTL_SECONDS = Number(process.env.JWT_TTL_SECONDS ?? 86400);

export function signJWT(payload: object): string {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify({ ...payload, iat: now, exp: now + JWT_TTL_SECONDS })).toString('base64url');
  const sig = crypto.createHmac('sha256', JWT_SECRET).update(`${header}.${body}`).digest('base64url');
  return `${header}.${body}.${sig}`;
}

export function verifyJWT(token: string): Record<string, unknown> {
  const [header, body, sig] = token.split('.');
  const expected = crypto.createHmac('sha256', JWT_SECRET).update(`${header}.${body}`).digest('base64url');
  if (sig !== expected) throw new Error('Invalid token');
  const payload = JSON.parse(Buffer.from(body, 'base64url').toString()) as Record<string, unknown>;
  if (typeof payload['exp'] === 'number' && Math.floor(Date.now() / 1000) > payload['exp']) {
    throw new Error('Token expired');
  }
  return payload;
}
