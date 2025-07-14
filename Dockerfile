# syntax=docker/dockerfile:1

# 1. Installer Stage: Install dependencies
FROM node:20-alpine AS deps
WORKDIR /app

# Install OS-level dependencies
RUN apk add --no-cache libc6-compat

# Copy dependency definition files
COPY --chown=node:node package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./

# --- RAILWAY CACHE FIX ---
# Use Railway's cache key to cache npm packages
ARG RAILWAY_CACHE_KEY
RUN --mount=type=cache,id=${RAILWAY_CACHE_KEY}-npm,target=/usr/src/app/.npm \
    npm ci --no-audit --no-fund --prefer-offline

# 2. Builder Stage: Build the Next.js application
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# --- RAILWAY CACHE FIX ---
# Also use cache for the build process itself
ARG RAILWAY_CACHE_KEY
ENV NEXT_TELEMETRY_DISABLED 1
RUN --mount=type=cache,id=${RAILWAY_CACHE_KEY}-npm,target=/usr/src/app/.npm \
    --mount=type=cache,id=${RAILWAY_CACHE_KEY}-nextjs,target=.next/cache \
    npm run build

# 3. Runner Stage: Create the final, small production image
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

# Create a non-root user for security
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy files from the builder stage, respecting the standalone output structure
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Set the user and expose the port
USER nextjs
EXPOSE 3000
ENV PORT 3000

# Start the application
CMD ["node", "server.js"]