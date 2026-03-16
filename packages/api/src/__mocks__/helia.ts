import * as crypto from 'crypto';
import { CID } from 'multiformats/cid';

/** Minimal Helia mock for Jest — no real IPFS node needed. */
export const createHelia = jest.fn(async () => ({
  stop: jest.fn(async () => {}),
  pins: {
    rm: jest.fn(async () => {}),
  },
}));
