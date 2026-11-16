#!/bin/sh
# Backend for the demo-video stack: the federfall image, unchanged, run with a
# throwaway data dir that the runner can ask to have WIPED between videos.
#
# Every video starts from a fresh backend, and the runner has no way to restart
# a container (no docker.sock, by design). So this loop owns PocketBase:
#
#   1. Once: apply the migrations into a template dir and add a superuser (the
#      seeding identity — it may write what access rules forbid a client).
#   2. Per generation: copy the template to a fresh data dir, serve it, and
#      publish the generation number in $CTL/generation once /api/health
#      answers.
#   3. When the runner writes that same number to $CTL/reset, stop PocketBase
#      and go to 2. The runner then waits for the next number.
#
# This replaces the image's entrypoint ("migrate up, then serve") with the same
# two steps, plus the loop. Nothing is mounted over /pb/pb_hooks or /pb/typst:
# both are assembled from the zugvogel base image and federfall's own files, and
# a mount would replace the whole directory (CLAUDE.md, rule 1).
set -eu

CTL=/ffdemo/ctl
TEMPLATE=/tmp/ffdemo-template
DATA=/tmp/ffdemo-data
pid=""

stop() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null || true
  exit 0
}
trap stop TERM INT

mkdir -p "$CTL"
chmod 0777 "$CTL"
rm -f "$CTL/generation" "$CTL/reset"

rm -rf "$TEMPLATE"
pocketbase migrate up --dir="$TEMPLATE" --migrationsDir=/pb/pb_migrations >/dev/null
pocketbase superuser upsert "$FFDEMO_SUPERUSER_EMAIL" "$FFDEMO_SUPERUSER_PASSWORD" \
  --dir="$TEMPLATE" >/dev/null

gen=0
while :; do
  gen=$((gen + 1))
  rm -rf "$DATA"
  cp -a "$TEMPLATE" "$DATA"
  pocketbase serve --http=0.0.0.0:8090 --dir="$DATA" \
    --migrationsDir=/pb/pb_migrations --hooksDir=/pb/pb_hooks \
    --publicDir=/pb/pb_public --automigrate=0 &
  pid=$!
  until wget -qO- http://127.0.0.1:8090/api/health >/dev/null 2>&1; do
    kill -0 "$pid" 2>/dev/null || { echo "ffdemo: PocketBase exited" >&2; exit 1; }
    sleep 0.2
  done
  echo "$gen" >"$CTL/generation.tmp"
  mv "$CTL/generation.tmp" "$CTL/generation"
  echo "ffdemo: backend generation $gen is up (fresh data dir)"
  while [ "$(cat "$CTL/reset" 2>/dev/null || true)" != "$gen" ]; do
    kill -0 "$pid" 2>/dev/null || { echo "ffdemo: PocketBase exited" >&2; exit 1; }
    sleep 0.2
  done
  kill "$pid"
  wait "$pid" 2>/dev/null || true
  pid=""
done
