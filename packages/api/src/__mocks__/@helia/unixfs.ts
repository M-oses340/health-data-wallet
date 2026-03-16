import * as crypto from 'crypto';

/** In-memory store so addBytes/cat round-trip correctly in tests. */
const _store = new Map<string, Uint8Array>();

export const unixfs = jest.fn(() => ({
  addBytes: jest.fn(async (data: Uint8Array) => {
    const id = crypto.randomBytes(8).toString('hex');
    const cid = { toString: () => `bafk${id}`, toV1: () => ({ toString: () => `bafk${id}` }) };
    _store.set(cid.toString(), data);
    return cid;
  }),
  cat: jest.fn(async function* (cid: { toString(): string }) {
    const data = _store.get(cid.toString());
    if (data) yield data;
  }),
}));
