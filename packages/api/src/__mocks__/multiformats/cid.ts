/** Minimal multiformats/cid mock for Jest. */
export const CID = {
  parse: jest.fn((str: string) => ({ toString: () => str })),
  create: jest.fn((version: number, codec: number, digest: unknown) => ({
    toString: () => `bafkmock`,
  })),
};
