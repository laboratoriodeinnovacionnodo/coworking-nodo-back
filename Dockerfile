FROM node:20-alpine AS builder

WORKDIR /app

RUN corepack enable

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --no-frozen-lockfile

# Copiamos el schema ANTES de generar el cliente
COPY prisma ./prisma

# Generamos el cliente de Prisma
RUN pnpm prisma generate

# Ahora copiamos el resto del código y compilamos
COPY . .
RUN pnpm build

FROM node:20-alpine AS runner

WORKDIR /app
ENV NODE_ENV=production

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/package.json ./package.json

EXPOSE 3550

CMD ["sh", "-c", "npx prisma migrate deploy && node dist/src/main.js"]