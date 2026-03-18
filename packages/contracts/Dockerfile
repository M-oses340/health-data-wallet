FROM node:20-alpine
WORKDIR /app

RUN apk add --no-cache curl python3 make g++ netcat-openbsd

COPY package.json package-lock.json tsconfig.base.json ./
COPY node_modules ./node_modules
COPY packages/sdk ./packages/sdk
COPY packages/contracts ./packages/contracts

# Reinstall stacktrace-parser to fix broken local copy
RUN npm install stacktrace-parser --no-save

# Pre-seed the hardhat compiler cache — wasm only (native solc won't run on Alpine/musl)
RUN mkdir -p /root/.cache/hardhat-nodejs/compilers-v3/wasm
COPY .hardhat-cache/compilers-v3/wasm/ /root/.cache/hardhat-nodejs/compilers-v3/wasm/

# Compile contracts at build time so runtime needs no internet
RUN cd /app/packages/contracts && npx hardhat compile --config hardhat.config.js

WORKDIR /app/packages/contracts

EXPOSE 8545
CMD ["npx", "hardhat", "node", "--hostname", "0.0.0.0", "--config", "hardhat.config.js"]
