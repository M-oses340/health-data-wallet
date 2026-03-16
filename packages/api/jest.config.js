/** @type {import('jest').Config} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/*.test.ts'],
  moduleNameMapper: {
    '^@health-data/sdk$': '<rootDir>/../sdk/src/index.ts',
    // Helia and related ESM-only packages — stub them out for Jest
    '^helia$': '<rootDir>/src/__mocks__/helia.ts',
    '^@helia/unixfs$': '<rootDir>/src/__mocks__/@helia/unixfs.ts',
    '^multiformats/cid$': '<rootDir>/src/__mocks__/multiformats/cid.ts',
  },
};
