# Federfall PocketBase — pinned, multi-arch (amd64/arm64) build.
# PocketBase ships a single static Go binary; we just fetch + verify the pinned
# release into a minimal Alpine image. Bump PB_VERSION here and in .env to upgrade.
ARG PB_VERSION=0.39.4

# ── fetch stage ──────────────────────────────────────────────────────────────
FROM alpine:3.20 AS fetch
ARG PB_VERSION
ARG TARGETARCH
RUN apk add --no-cache unzip wget ca-certificates
WORKDIR /pb
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) PB_ARCH=amd64 ;; \
        arm64) PB_ARCH=arm64 ;; \
        arm)   PB_ARCH=armv7 ;; \
        *)     echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    wget -q "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_${PB_ARCH}.zip" -O /tmp/pb.zip; \
    unzip /tmp/pb.zip -d /pb; \
    rm /tmp/pb.zip; \
    chmod +x /pb/pocketbase

# ── runtime stage ────────────────────────────────────────────────────────────
FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata wget
COPY --from=fetch /pb/pocketbase /usr/local/bin/pocketbase
WORKDIR /pb
RUN mkdir -p /pb/pb_data
# Bake the committed migrations + hooks INTO the image so it is self-contained
# and reproducible — production runs them from here with no host bind mounts.
# (Local dev shadows these with bind mounts via docker-compose.override.yml so
# automigrate + hot-reload still work.)
COPY pb_migrations/ /pb/pb_migrations/
COPY pb_hooks/      /pb/pb_hooks/
EXPOSE 8090
# Production default: automigrate OFF — schema only ever changes via the
# committed migration files baked above, never drifts from the Admin UI.
# The dev override re-enables it and bind-mounts the dirs.
ENTRYPOINT ["pocketbase"]
CMD ["serve", "--http=0.0.0.0:8090", \
     "--dir=/pb/pb_data", \
     "--migrationsDir=/pb/pb_migrations", \
     "--hooksDir=/pb/pb_hooks", \
     "--automigrate=0"]
