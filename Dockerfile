# syntax=docker/dockerfile:1

# --- Stage 1: Install dependencies ---
FROM node:20-alpine AS deps
WORKDIR /app

# Install OS-level dependencies needed for some packages
RUN apk add --no-cache libc6-compat

# Copy dependency manifests
COPY --chown=node:node package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./

# --- RAILWAY CACHE FIX ---
# This is the officially documented way to use cache on Railway.
RUN --mount=type=cache,id=s/b267c943-43ed-47a4-bf25-b90952ea9fee-/app/.npm,target=/app/.npm,uid=1000 \
    npm ci --no-audit --no-fund --prefer-offline --cache .npm

# --- Stage 2: Build the application ---
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Set build-time env vars
ENV NEXT_TELEMETRY_DISABLED 1

# --- RAILWAY CACHE FIX ---
# Also use cache for the build process itself.
RUN --mount=type=cache,id=s/b267c943-43ed-47a4-bf25-b90952ea9fee-/app/.npm,target=/app/.npm,uid=1000 \
    --mount=type=cache,id=s/b267c943-43ed-47a4-bf25-b90952ea9fee-.next/cache,target=.next/cache,uid=1000 \
    npm run build

# --- Stage 3: Production runner ---
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

# Create a non-root user for security
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy only necessary files from the builder stage for a small production image
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Set correct user and expose port
USER nextjs
EXPOSE 3000
ENV PORT 3000

# Start the application
CMD ["node", "server.js"]