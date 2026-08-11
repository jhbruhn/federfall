#!/usr/bin/env bash
# federfall-qt96.12 — the cron jobs, against a throwaway PocketBase.
#
# Separate from run.sh because `cronAdd` jobs are INVISIBLE to that suite:
# nothing in the API can trigger one, so the assertion suite can only ever test
# the guard a cron has to get past, never the cron itself. The only way to
# observe one is to make it due — so this copies pb_hooks to a tempdir, rewrites
# the schedule to every minute, and runs a container against that copy. The
# committed hooks are never modified.
#
# It is NOT part of run.sh or CI: it has to wait for a wall-clock minute
# boundary, which no other test does.
#
# Usage:  backend/pocketbase/tests/run_cron.sh
# Env:    FED_TEST_PORT (default 8098 — one above run.sh, so both can run)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PB_DIR="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$PB_DIR/../.." && pwd)"
IMAGE="federfall-pocketbase:0.39.8"
PORT="${FED_TEST_PORT:-8098}"
NAME="fed_cron_$$"
DATA="$(mktemp -d)"
HOOKS="$(mktemp -d)"
ADMIN_EMAIL="admin@federfall.local"
ADMIN_PASS="Admin12345!"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run --rm -v "$DATA:/data" --entrypoint sh "$IMAGE" \
    -c 'rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null' >/dev/null 2>&1 || true
  rm -rf "$DATA" "$HOOKS"
}
trap cleanup EXIT

echo "==> Ensuring image $IMAGE exists"
docker image inspect "$IMAGE" >/dev/null 2>&1 || \
  docker build --target backend -t "$IMAGE" -f "$ROOT/Dockerfile" "$ROOT"

echo "==> Copying hooks and making the retention jobs due every minute"
cp -r "$PB_DIR/pb_hooks/." "$HOOKS/"
# The three RETENTION jobs, which are the ones that read an org-configurable
# window out of a JSON field (federfall-jumi) and so cannot be trusted to a
# code review. The remaining crons (geocodeCachePurge, idempotencyKeyPurge)
# keep their real schedules so they cannot interfere — see federfall-ecpr.
# They work on disjoint collections, so all being due together is fine.
sed -i 's|cronAdd("auditRetention", "30 3 \* \* \*"|cronAdd("auditRetention", "* * * * *"|' \
  "$HOOKS/audit.pb.js"
grep -q 'cronAdd("auditRetention", "\* \* \* \* \*"' "$HOOKS/audit.pb.js" || {
  echo "the schedule rewrite did not apply — has the cron been renamed?"; exit 1; }
sed -i 's|cronAdd("finderPiiRetention", "0 3 \* \* \*"|cronAdd("finderPiiRetention", "* * * * *"|' \
  "$HOOKS/finder_retention.pb.js"
grep -q 'cronAdd("finderPiiRetention", "\* \* \* \* \*"' \
  "$HOOKS/finder_retention.pb.js" || {
  echo "the schedule rewrite did not apply — has the cron been renamed?"; exit 1; }
sed -i 's|cronAdd("sponsorshipRetention", "0 4 \* \* \*"|cronAdd("sponsorshipRetention", "* * * * *"|' \
  "$HOOKS/sponsorship_retention.pb.js"
grep -q 'cronAdd("sponsorshipRetention", "\* \* \* \* \*"' \
  "$HOOKS/sponsorship_retention.pb.js" || {
  echo "the schedule rewrite did not apply — has the cron been renamed?"; exit 1; }
# ...and, for this one only, the ORPHAN GRACE PERIOD as well. It is a fixed 24 h
# and it is measured from the row's own `created`, which is a server-owned
# autodate no client can backdate — so with it in place NO test could ever
# observe a deletion, and the whole cron would be asserted vacuously. Removed in
# the COPY so the org window is what discriminates; test_cron.py reads the
# committed file and fails if the real grace period has gone missing.
sed -i 's|const ORPHAN_GRACE_MS = 24 \* 60 \* 60 \* 1000;|const ORPHAN_GRACE_MS = 0;|' \
  "$HOOKS/sponsorship_retention.pb.js"
grep -q 'const ORPHAN_GRACE_MS = 0;' "$HOOKS/sponsorship_retention.pb.js" || {
  echo "the grace-period rewrite did not apply — has the constant changed?"
  exit 1; }

echo "==> Applying migrations to throwaway data dir"
docker run --rm \
  -v "$PB_DIR/pb_migrations:/pb/pb_migrations:ro" \
  -v "$DATA:/pb/pb_data" \
  "$IMAGE" migrate up >/dev/null

echo "==> Creating superuser"
docker run --rm \
  -v "$PB_DIR/pb_migrations:/pb/pb_migrations:ro" \
  -v "$DATA:/pb/pb_data" \
  "$IMAGE" superuser upsert "$ADMIN_EMAIL" "$ADMIN_PASS" >/dev/null

echo "==> Starting server on :$PORT"
docker run -d --name "$NAME" -p "$PORT:8090" \
  -v "$PB_DIR/pb_migrations:/pb/pb_migrations:ro" \
  -v "$HOOKS:/pb/pb_hooks:ro" \
  -v "$PB_DIR/typst:/pb/typst:ro" \
  -v "$DATA:/pb/pb_data" \
  "$IMAGE" >/dev/null

echo "==> Waiting for health"
for _ in $(seq 1 40); do
  curl -sf "http://localhost:$PORT/api/health" >/dev/null && break
  sleep 0.5
done
curl -sf "http://localhost:$PORT/api/health" >/dev/null || {
  echo "server never became healthy"; docker logs "$NAME"; exit 1; }

echo "==> Running cron assertions (waits for a minute boundary)"
set +e
FED_TEST_URL="http://localhost:$PORT" \
FED_ADMIN_EMAIL="$ADMIN_EMAIL" \
FED_ADMIN_PASS="$ADMIN_PASS" \
  python3 "$HERE/test_cron.py"
STATUS=$?
set -e

# The purge logs what it did; on a failure that is the first thing to look at.
if [ "$STATUS" -ne 0 ]; then
  echo "==> Container log (retention lines)"
  docker logs "$NAME" 2>&1 \
    | grep -iE "audit retention|finder retention|sponsorship retention" \
    || echo "  (none)"
fi
exit "$STATUS"
