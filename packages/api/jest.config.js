/** @type {import('jest').Config} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  // Run suites serially to avoid SQLite contention (all suites share the same DB file)
  maxWorkers: 1,
  roots: ['<rootDir>/src'],
  testMatch: ['**/*.test.ts'],
  moduleNameMapper: {
    '^@health-data/sdk$': '<rootDir>/../sdk/src/index.ts',
    // Helia and related ESM-only packages — stub them out for Jest
    '^helia$': '<rootDir>/src/__mocks__/helia.ts',
    '^@helia/unixfs$': '<rootDir>/src/__mocks__/@helia/unixfs.ts',
    '^multiformats/cid$': '<rootDir>/src/__mocks__/multiformats/cid.ts',
    '^@noble/secp256k1$': '<rootDir>/src/__mocks__/@noble/secp256k1.ts',
  },
};
