FROM node:20-alpine AS builder
WORKDIR /app

# Install build tools for native modules (better-sqlite3)
RUN apk add --no-cache python3 make g++

# Copy monorepo root configs and pre-installed node_modules
COPY package.json package-lock.json tsconfig.base.json ./
COPY node_modules ./node_modules
COPY packages/sdk ./packages/sdk
COPY packages/api ./packages/api

# Rebuild better-sqlite3 native binding for this platform
RUN npm rebuild better-sqlite3

RUN npm run build --workspace=packages/sdk
RUN npm run build --workspace=packages/api

FROM node:20-alpine
WORKDIR /app

# Runtime deps for better-sqlite3
RUN apk add --no-cache libstdc++

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
