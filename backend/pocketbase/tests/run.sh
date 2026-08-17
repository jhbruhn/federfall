#!/usr/bin/env bash
# FED-1.13 — backend rule/hook tests against a throwaway PocketBase instance.
#
# Spins up a disposable container (fresh pb_data in a tempdir, migrations + hooks
# mounted, a known superuser), waits for health, runs the Python assertion suite
# against it, then tears everything down. Exit code propagates from the suite.
#
# Usage:  backend/pocketbase/tests/run.sh
# Env:    FED_TEST_PORT (default 8097)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PB_DIR="$(cd "$HERE/.." && pwd)" # backend/pocketbase
ROOT="$(cd "$PB_DIR/../.." && pwd)" # repo root (holds the unified Dockerfile)
IMAGE="federfall-pocketbase:0.39.8"
PORT="${FED_TEST_PORT:-8097}"
NAME="fed_test_$$"
DATA="$(mktemp -d)"
ADMIN_EMAIL="admin@federfall.local"
ADMIN_PASS="Admin12345!"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # Files under $DATA/storage are created by the container as root, so the host
  # user can't rm them directly — clear the contents from inside a container
  # (same image, already pulled/built) before removing the now-empty tempdir.
  docker run --rm -v "$DATA:/data" --entrypoint sh "$IMAGE" \
    -c 'rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null' >/dev/null 2>&1 || true
  rm -rf "$DATA"
}
trap cleanup EXIT

# The Typst templates are mounted alongside the hooks below, not taken from the
# baked image: the image is CACHED by tag (see the inspect-or-build below), so a
# report-template or shared_strings.json edit would otherwise be silently tested
# against whatever was in the image the day it was first built.
echo "==> Ensuring image $IMAGE exists"
# Lean PocketBase-only image (no Flutter web) — the `backend` target of the
# repo-root Dockerfile. Context is the repo root so the baked migrations/hooks
# resolve; BuildKit skips the Flutter stage since this target doesn't need it.
docker image inspect "$IMAGE" >/dev/null 2>&1 || \
  docker build --target backend -t "$IMAGE" -f "$ROOT/Dockerfile" "$ROOT"

# pb_hooks must be mounted here too, not only at serve: onBootstrap hooks run
# for EVERY command, and the image bakes a copy of them — so without the mount
# these steps execute whatever hooks were in the image the day it was built,
# and one that persists state (geocode.pb.js writes settings.rateLimits) can
# poison the fresh data dir before the hooks under test ever run.
echo "==> Applying migrations to throwaway data dir"
docker run --rm \
  -v "$PB_DIR/pb_migrations:/pb/pb_migrations:ro" \
  -v "$PB_DIR/pb_hooks:/pb/pb_hooks:ro" \
  -v "$DATA:/pb/pb_data" \
  "$IMAGE" migrate up

echo "==> Creating superuser"
docker run --rm \
  -v "$PB_DIR/pb_migrations:/pb/pb_migrations:ro" \
  -v "$PB_DIR/pb_hooks:/pb/pb_hooks:ro" \
  -v "$DATA:/pb/pb_data" \
  "$IMAGE" superuser upsert "$ADMIN_EMAIL" "$ADMIN_PASS"

echo "==> Starting server on :$PORT"
# A runtime map source is prescribed too (federfall-el1f): raster mode with an
# attribution and a provider API key, plus a style URL for the *other* mode that
# must therefore be ignored by /info while still contributing its origin to the
# CSP.
#
# The geocoder points at a closed local port on purpose (federfall-185w): no
# test may reach the real Nominatim, and a refused connection makes "the input
# was rejected" (400) distinguishable from "the input was accepted and the
# upstream then failed" — which is the only way to prove a coordinate check
# non-vacuous without standing up a stub geocoder.
#
# Two dummy OAuth2 providers are registered so /api/federfall/info has
# something to report scopes for (federfall-lnz3): a generic OIDC one, which
# must be told to ask for the groups scope because a group mapping is
# configured below, and a social one, which must NOT be (an unknown scope
# fails the whole authorization request there). Nothing ever signs in through
# either — the credentials are fake — this only exercises the settings + info
# hooks.
docker run -d --name "$NAME" -p "$PORT:8090" \
  -e FEDERFALL_OAUTH2_PROVIDERS=oidc,google \
  -e FEDERFALL_OAUTH2_OIDC_CLIENT_ID=test-client \
  -e FEDERFALL_OAUTH2_OIDC_CLIENT_SECRET=test-secret \
  -e FEDERFALL_OAUTH2_OIDC_AUTH_URL=https://id.invalid/authorize \
  -e FEDERFALL_OAUTH2_OIDC_TOKEN_URL=https://id.invalid/token \
  -e FEDERFALL_OAUTH2_OIDC_USERINFO_URL=https://id.invalid/userinfo \
  -e FEDERFALL_OAUTH2_GOOGLE_CLIENT_ID=test-client \
  -e FEDERFALL_OAUTH2_GOOGLE_CLIENT_SECRET=test-secret \
  -e FEDERFALL_OIDC_CARER_GROUP=federfall-carers \
  -e FEDERFALL_MAP_MODE=raster \
  -e FEDERFALL_MAP_TILE_URL='https://raster.invalid/{z}/{x}/{y}.png' \
  -e FEDERFALL_MAP_STYLE_URL=https://vector.invalid/style.json \
  -e FEDERFALL_MAP_ATTRIBUTION='© Test Tiles' \
  -e FEDERFALL_MAP_API_KEY=test-map-key \
  -e FEDERFALL_NOMINATIM_URL=http://127.0.0.1:1 \
  -v "$PB_DIR/pb_migrations:/pb/pb_migrations:ro" \
  -v "$PB_DIR/pb_hooks:/pb/pb_hooks:ro" \
  -v "$PB_DIR/typst:/pb/typst:ro" \
  -v "$DATA:/pb/pb_data" \
  "$IMAGE" >/dev/null

echo "==> Waiting for health"
for _ in $(seq 1 40); do
  curl -sf "http://localhost:$PORT/api/health" >/dev/null && break
  sleep 0.5
done
curl -sf "http://localhost:$PORT/api/health" >/dev/null || { echo "server never became healthy"; docker logs "$NAME"; exit 1; }

echo "==> Running assertion suite"
FED_TEST_URL="http://localhost:$PORT" \
FED_ADMIN_EMAIL="$ADMIN_EMAIL" \
FED_ADMIN_PASS="$ADMIN_PASS" \
  python3 "$HERE/test_rules.py"
