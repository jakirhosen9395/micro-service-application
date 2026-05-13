FROM node:24-bookworm-slim AS deps
WORKDIR /app
COPY package*.json ./
RUN if [ -f package-lock.json ]; then \
      npm ci --include=optional --no-audit --no-fund; \
    else \
      npm install --include=optional --no-audit --no-fund; \
    fi

FROM deps AS build
WORKDIR /app
COPY tsconfig.json tsup.config.ts ./
COPY src ./src
RUN npm run check
RUN npm run build
RUN npm prune --omit=dev

FROM node:24-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
RUN groupadd --system appuser \
    && useradd --system --gid appuser --create-home --home-dir /app --shell /usr/sbin/nologin appuser
COPY --from=build --chown=appuser:appuser /app/node_modules ./node_modules
COPY --from=build --chown=appuser:appuser /app/dist ./dist
COPY --chown=appuser:appuser migrations ./migrations
COPY --chown=appuser:appuser apm-preload.cjs ./apm-preload.cjs
COPY --chown=appuser:appuser package.json ./package.json
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD node -e "fetch('http://127.0.0.1:8080/hello').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
ENTRYPOINT ["node", "-r", "./apm-preload.cjs", "dist/main.js"]
CMD ["api"]
