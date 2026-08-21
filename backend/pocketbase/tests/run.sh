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

# ── Why nothing is mounted over the hooks or the Typst templates any more ────
#
# It used to mount both, and the reason was real: the image was only built when
# absent (`docker image inspect || docker build`), so a hook or template edit
# was otherwise tested against whatever was in the image the day it was first
# built. The mounts were a workaround for a stale image.
#
# They are no longer possible. The zv_* libraries come from zugvogel-pb-base, and
# a mount over /pb/pb_hooks replaces the whole directory with one that does not
# contain them — every `require` of a shared library would fail at request time
# as a generic 400. Same for /pb/typst and the shared report base.
#
# So the staleness is fixed at the root instead: BUILD UNCONDITIONALLY. It is a
# cached COPY layer near the end of the Dockerfile, so it costs seconds, and the
# suite now exercises exactly the image that ships rather than host files laid
# over one nothing tested.
echo "==> Building image $IMAGE"
# Lean PocketBase-only image (no Flutter web) — the `backend` target of the
# repo-root Dockerfile. Context is the repo root so the baked migrations/hooks
# resolve; BuildKit skips the Flutter stage since this target doesn't need it.
docker build --target backend -t "$IMAGE" -f "$ROOT/Dockerfile" "$ROOT"

# onBootstrap hooks run for EVERY command, including these, and one that
# persists state (geocode.pb.js writes settings.rateLimits) can poison the fresh
# data dir before the hooks under test ever run. That is why the image being
# current matters here and not only at serve — handled by the unconditional
# build above rather than by a mount.
echo "==> Applying migrations to throwaway data dir"
docker run --rm \
  -v "$PB_DIR/pb_migrations:/pb/pb_migrations:ro" \
  -v "$DATA:/pb/pb_data" \
  "$IMAGE" migrate up

echo "==> Creating superuser"
docker run --rm \
  -v "$PB_DIR/pb_migrations:/pb/pb_migrations:ro" \
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
  -v "$DATA:/pb/pb_data" \
  "$IMAGE" serve \
  --http=0.0.0.0:8090 \
  --dir=/pb/pb_data \
  --migrationsDir=/pb/pb_migrations \
  --hooksDir=/pb/pb_hooks \
  --automigrate=0 \
  --dev >/dev/null

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
  python3 "$HERE/test_rules.py" || {
    status=$?
    echo "==> Container log (errors and this app's lines)"
    # An uncaught error in a hook answers a generic 400 with an empty `data` and
    # is reported nowhere else — the container is the only place it exists, and
    # the trap removes the container. Without this the diagnosis is a guess.
    docker logs "$NAME" 2>&1 \
      | grep -viE 'SELECT|INSERT INTO|UPDATE .* SET|CREATE (TABLE|INDEX)' \
      | grep -A3 -iE 'federfall:|ERROR' | tail -30 || echo "  (none)"
    exit $status
  }
