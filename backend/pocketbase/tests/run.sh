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
IMAGE="federfall-pocketbase:0.39.4"
PORT="${FED_TEST_PORT:-8097}"
NAME="fed_test_$$"
DATA="$(mktemp -d)"
ADMIN_EMAIL="admin@federfall.local"
ADMIN_PASS="Admin12345!"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$DATA"
}
trap cleanup EXIT

echo "==> Ensuring image $IMAGE exists"
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build -t "$IMAGE" "$PB_DIR"

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
docker run -d --name "$NAME" -p "$PORT:8090" \
  -v "$PB_DIR/pb_migrations:/pb/pb_migrations:ro" \
  -v "$PB_DIR/pb_hooks:/pb/pb_hooks:ro" \
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
