# syntax=docker/dockerfile:1
#
# Federfall — single-container image. PocketBase serves the REST/Realtime API,
# the Admin UI (/_/) AND the built Flutter web SPA (from /pb/pb_public, with SPA
# index-fallback) on ONE origin. No separate web server.
#
# Build context MUST be the repo root — this is a pub workspace and the web build
# depends on packages/federfall_{models,data}.
#
# Two targets:
#   --target backend  → lean PB image (binary + migrations + hooks, NO web).
#                       Used by the rule tests (backend/pocketbase/tests/run.sh).
#   (default = full)  → backend + the production Flutter web bundle baked in.
#                       This is what the compose stack ships.
#
# Bump PB_VERSION here and in the root docker-compose.yml to upgrade PocketBase.
ARG PB_VERSION=0.39.4

# ── Flutter web build stage ────────────────────────────────────────────────────
# Self-installed, version-pinned Flutter SDK (mirrors the pinned-fetch pattern —
# no third-party prebuilt image). The fat build stage is discarded.
FROM debian:bookworm-slim AS flutterbuild

# Keep in sync with the repo's pinned Flutter (apps/federfall: flutter ^3.44.0).
ARG FLUTTER_VERSION=3.44.3

ENV DEBIAN_FRONTEND=noninteractive \
    PUB_CACHE=/pub-cache \
    PATH="/flutter/bin:/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Pinned Flutter SDK (shallow clone of the release tag), web enabled, artifacts
# pre-cached so the build itself does no extra downloads.
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
        https://github.com/flutter/flutter.git /flutter \
    && git config --global --add safe.directory /flutter \
    && flutter --version \
    && flutter config --no-analytics --enable-web \
    && flutter precache --web

WORKDIR /src

# 1) Resolve dependencies first (cached unless a pubspec/lock changes): copy only
#    the workspace + member manifests and the lockfile, then `pub get`.
COPY pubspec.yaml pubspec.lock ./
COPY apps/federfall/pubspec.yaml             apps/federfall/
COPY packages/federfall_models/pubspec.yaml  packages/federfall_models/
COPY packages/federfall_data/pubspec.yaml    packages/federfall_data/
RUN flutter pub get

# 2) Full sources.
COPY . .

# 3) Codegen (freezed/json/riverpod) for the models package then the app, then
#    l10n. federfall_data is pure Dart — no codegen.
RUN set -eux; \
    cd /src/packages/federfall_models && dart run build_runner build; \
    cd /src/apps/federfall && dart run build_runner build && flutter gen-l10n

# 4) Production web bundle, compiled to WebAssembly (dart2wasm + skwasm, with the
#    JS/CanvasKit fallback the build emits automatically). POCKETBASE_URL is empty
#    in production.json so the app resolves the API from its own serving origin
#    (Uri.base.origin) — which, in the single-container stack, is the very
#    PocketBase that serves this bundle.
#    NOTE: the skwasm renderer wants cross-origin isolation (COOP/COEP headers) to
#    use threads; PocketBase doesn't send those, so it falls back gracefully — set
#    them at a reverse proxy if you want the threaded fast path.
#    --no-web-resources-cdn keeps the engine assets (canvaskit/skwasm) in the
#    bundle instead of Google's gstatic CDN, so the SPA stays fully same-origin
#    — required by the Content-Security-Policy web_headers.pb.js sends
#    (script-src 'self') and self-contained for self-hosted instances anyway.
RUN cd /src/apps/federfall && flutter build web --wasm --release \
        --no-web-resources-cdn \
        --target lib/main_production.dart \
        --dart-define-from-file=dart_defines/production.json

# ── PocketBase fetch stage ─────────────────────────────────────────────────────
# PocketBase ships a single static Go binary; fetch + verify the pinned release.
FROM alpine:3.20 AS pbfetch
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

# ── Backend runtime (lean: PB + migrations + hooks, NO web) ─────────────────────
# This stage IS the rule-test image (built via `--target backend`).
FROM alpine:3.20 AS backend
RUN apk add --no-cache ca-certificates tzdata wget
COPY --from=pbfetch /pb/pocketbase /usr/local/bin/pocketbase
WORKDIR /pb
RUN mkdir -p /pb/pb_data
# Bake the committed migrations + hooks INTO the image so it is self-contained
# and reproducible — production runs them from here with no host bind mounts.
# (Local dev shadows these with bind mounts via docker-compose.override.yml so
# automigrate + hot-reload still work.)
COPY backend/pocketbase/pb_migrations/ /pb/pb_migrations/
COPY backend/pocketbase/pb_hooks/      /pb/pb_hooks/
EXPOSE 8090
# Production default: automigrate OFF — schema only ever changes via the committed
# migration files baked above, never drifts from the Admin UI. The dev override
# re-enables it and bind-mounts the dirs.
ENTRYPOINT ["pocketbase"]
CMD ["serve", "--http=0.0.0.0:8090", \
     "--dir=/pb/pb_data", \
     "--migrationsDir=/pb/pb_migrations", \
     "--hooksDir=/pb/pb_hooks", \
     "--automigrate=0"]

# ── Full app image (backend + Flutter web SPA) ─────────────────────────────────
FROM backend AS full
# Bake the built SPA where PocketBase serves static files. --indexFallback (on by
# default) sends unknown non-/api, non-/_ paths to index.html so client-side
# (usePathUrlStrategy) deep links resolve. API + Admin routes take precedence.
COPY --from=flutterbuild /src/apps/federfall/build/web /pb/pb_public
CMD ["serve", "--http=0.0.0.0:8090", \
     "--dir=/pb/pb_data", \
     "--migrationsDir=/pb/pb_migrations", \
     "--hooksDir=/pb/pb_hooks", \
     "--publicDir=/pb/pb_public", \
     "--automigrate=0"]
