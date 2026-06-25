# syntax=docker/dockerfile:1
#
# Federfall web frontend — Flutter SPA served by nginx.
#
# Multi-stage: build the web bundle with a self-installed, version-pinned Flutter
# SDK (mirrors the backend's pinned-fetch pattern — no third-party prebuilt
# image), then ship ONLY the static output on a tiny nginx runtime. The fat build
# stage is discarded.
#
# Build context MUST be the repo root — this is a pub workspace and the app
# depends on packages/federfall_{models,data}. See docker-compose.yml at the root.

# ── build stage ───────────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS build

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

# 4) Production web bundle. POCKETBASE_URL is empty in production.json so the app
#    resolves the API from its own serving origin (Uri.base.origin) — same domain
#    as this nginx, which proxies /api and /_/ to the backend.
RUN cd /src/apps/federfall && flutter build web --release \
        --target lib/main_production.dart \
        --dart-define-from-file=dart_defines/production.json

# ── runtime stage ─────────────────────────────────────────────────────────────
FROM nginx:1.27-alpine

RUN rm -rf /usr/share/nginx/html/*
COPY apps/federfall/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/apps/federfall/build/web /usr/share/nginx/html

EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
    CMD wget -qO- http://127.0.0.1/ >/dev/null 2>&1 || exit 1
