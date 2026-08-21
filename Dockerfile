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
# The shared PocketBase runtime: the binary, the zv_* hook libraries, the Typst
# report base and the migrate-before-serve entrypoint. Published from zugvogel.
#
# Pinned to a `sha-<commit>` tag for the same reason the Dart packages are
# pinned to a commit hash: it names one commit and nothing can re-point it. The
# two pins move independently — a change to zugvogel's Dart does not touch this,
# and a change to the shared hooks does not touch pubspec.yaml.
#
# This replaces a local pbfetch stage that carried the PocketBase version and its
# per-arch checksums. Those existed identically in eiermann's Dockerfile: two
# places to bump, and a JSVM whose behaviour differs between versions in ways
# that have cost real time.
ARG ZUGVOGEL_PB_BASE=ghcr.io/jhbruhn/zugvogel-pb-base:sha-98c011a36e43606db42b771ad7e791ade347e3b9

# ── Flutter web build stage ────────────────────────────────────────────────────
# Self-installed, version-pinned Flutter SDK (mirrors the pinned-fetch pattern —
# no third-party prebuilt image). The fat build stage is discarded.
FROM debian:bookworm-slim AS flutterbuild

# Keep in sync with the repo's pinned Flutter (apps/federfall: flutter ^3.47.0).
ARG FLUTTER_VERSION=3.47.1

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

# ── Typst fetch stage ───────────────────────────────────────────────────────────
# Typst ships a single static Rust binary; fetch + verify the pinned release.
# Same rigor as pbfetch above, EXCEPT Typst does not publish a checksums.txt —
# these SHA256s were computed by hand from the v0.15.0 release assets (there is
# no upstream file to diff a version bump against, so bumping TYPST_VERSION
# means re-downloading and re-hashing both arches yourself).
FROM alpine:3.20 AS typstfetch
ARG TYPST_VERSION=0.15.0
ARG TARGETARCH
RUN apk add --no-cache wget xz ca-certificates
WORKDIR /typst
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) TT_TARGET=x86_64-unknown-linux-musl; TT_SHA256=59b207df01be2dab9f13e80f73d04d7ff8273ffd46b3dd1b9eef5c60f3eeabea ;; \
        arm64) TT_TARGET=aarch64-unknown-linux-musl; TT_SHA256=cdf50ffc7b8ba759ed02200632eda3d78eb8b99aacb6611f4f75684990647620 ;; \
        *)     echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    wget -q "https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-${TT_TARGET}.tar.xz" -O /tmp/typst.tar.xz; \
    echo "${TT_SHA256}  /tmp/typst.tar.xz" | sha256sum -c -; \
    tar -xJf /tmp/typst.tar.xz -C /typst --strip-components=1; \
    rm /tmp/typst.tar.xz; \
    chmod +x /typst/typst

# ── Backend runtime (lean: PB + migrations + hooks, NO web) ─────────────────────
# This stage IS the rule-test image (built via `--target backend`), which is the
# point: the suite exercises the image that ships.
#
# The base brings PocketBase, the thirteen zv_* libraries, the Typst report base
# and the entrypoint. Everything added below is federfall's own — and the hooks
# COPYed further down land in the same /pb/pb_hooks directory, so a `require` of
# a zv_ library resolves without any of them living in this repo.
FROM ${ZUGVOGEL_PB_BASE} AS backend
# federfall-gdp8 — the per-case PDF report hook shells out to this. Bundled
# here (not fetched at runtime) so PDF generation works fully offline/
# reproducibly, same stance as the pinned Flutter SDK and the PB binary above.
COPY --from=typstfetch /typst/typst /usr/local/bin/typst
WORKDIR /pb
# Released images get this set to the release-please version (e.g. "1.4.2") via
# --build-arg in the release workflow. info.pb.js reads it at request time
# ($os.getenv) — the running image is the single source of truth for the
# version it reports, so no source file needs a release-time edit. Local/dev
# builds keep the "0.0.0-dev" default.
ARG FEDERFALL_VERSION=0.0.0-dev
ENV FEDERFALL_VERSION=${FEDERFALL_VERSION}
# Bake the committed migrations + hooks INTO the image so it is self-contained
# and reproducible.
#
# `pb_hooks/` may no longer be bind-mounted over: the zv_* libraries live in the
# base image and a mount replaces the whole directory, so every `require` of one
# would fail at request time as a generic 400. The rule suite therefore runs
# against the baked copies, which is the more honest arrangement anyway — it used
# to test host files laid over an image nothing exercised.
COPY backend/pocketbase/pb_migrations/ /pb/pb_migrations/
COPY backend/pocketbase/pb_hooks/      /pb/pb_hooks/
COPY backend/pocketbase/typst/         /pb/typst/
# Production default: automigrate OFF — schema only ever changes via the committed
# migration files baked above, never drifts from the Admin UI.
#
# ENTRYPOINT comes from the base and applies migrations before handing off to
# `serve`. That ordering is load-bearing rather than tidy: a hook running in
# onBootstrap is not guaranteed to see the schema, so on a fresh volume it does
# nothing on the first boot and works on the second.
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
