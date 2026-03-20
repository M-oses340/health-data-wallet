FROM node:20-slim AS builder
WORKDIR /app

# Install build tools for native modules (better-sqlite3)
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ cmake && rm -rf /var/lib/apt/lists/*

# Copy all package manifests so npm workspaces resolves correctly
COPY package.json package-lock.json tsconfig.base.json ./
COPY packages/sdk/package.json ./packages/sdk/package.json
COPY packages/api/package.json ./packages/api/package.json
RUN npm ci

# Copy source and build
COPY packages/sdk ./packages/sdk
COPY packages/api ./packages/api

# Rebuild better-sqlite3 native binding for this platform
RUN npm rebuild better-sqlite3

RUN npm run build --workspace=packages/sdk
RUN npm run build --workspace=packages/api

FROM node:20-slim
WORKDIR /app

# wget needed for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends wget && rm -rf /var/lib/apt/lists/*

# Copy node_modules and compiled output from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages/api/dist ./packages/api/dist
COPY --from=builder /app/packages/sdk/dist ./packages/sdk/dist
COPY --from=builder /app/packages/sdk/package.json ./packages/sdk/package.json

# Repoint the sdk symlink to the dist we copied
RUN rm -rf /app/node_modules/@health-data/sdk \
 && ln -s /app/packages/sdk /app/node_modules/@health-data/sdk

EXPOSE 3000
CMD ["node", "packages/api/dist/server.js"]
