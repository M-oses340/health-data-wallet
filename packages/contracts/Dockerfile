FROM node:20-alpine
WORKDIR /app

RUN apk add --no-cache curl

COPY package.json package-lock.json tsconfig.base.json ./
COPY packages/sdk ./packages/sdk
COPY packages/contracts ./packages/contracts

RUN npm ci

# Compile contracts from the contracts package directory
WORKDIR /app/packages/contracts
RUN npx hardhat compile

EXPOSE 8545
# Bind to 0.0.0.0 so it's reachable from other containers
CMD ["npx", "hardhat", "node", "--hostname", "0.0.0.0"]
