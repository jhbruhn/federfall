#!/bin/sh
# Backend for the demo-video stack: the federfall image, unchanged, run with a
# throwaway data dir that the runner can ask to have WIPED between videos.
#
# Every video starts from a fresh backend, and the runner has no way to restart
# a container (no docker.sock, by design). So this loop owns PocketBase:
#
#   1. Once: apply the migrations into a template dir and add a superuser (the
#      seeding identity — it may write what access rules forbid a client).
#   2. Per generation: copy a template to a fresh data dir, serve it, and
#      publish the generation number in $CTL/generation once /api/health
#      answers.
#   3. When the runner writes that same number to $CTL/reset, stop PocketBase
#      and go to 2. The runner then waits for the next number.
#
# Templates. "pristine" is the migrated dir from step 1. The runner can add
# more: writing "<gen> <name>" to $CTL/snapshot stops PocketBase, copies the
# CURRENT data dir (as seeded so far) to the template <name>, and goes to 2
# serving a fresh copy of it. A reset written as "<gen> <name>" then starts the
# next generation from that template instead of the pristine one. That is how
# the demo dataset is seeded once per run and language and handed to every
# video as a copy (harness/lib/dataset.mjs) instead of being re-seeded 54 times.
# Copies are made with PocketBase stopped, so the SQLite files are consistent.
#
# This replaces the image's entrypoint ("migrate up, then serve") with the same
# two steps, plus the loop. Nothing is mounted over /pb/pb_hooks or /pb/typst:
# both are assembled from the zugvogel base image and federfall's own files, and
# a mount would replace the whole directory (CLAUDE.md, rule 1).
set -eu

CTL=/ffdemo/ctl
TEMPLATES=/tmp/ffdemo-templates
DATA=/tmp/ffdemo-data
pid=""

stop() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null || true
  exit 0
}
trap stop TERM INT

mkdir -p "$CTL"
chmod 0777 "$CTL"
rm -f "$CTL/generation" "$CTL/reset" "$CTL/snapshot"

rm -rf "$TEMPLATES"
mkdir -p "$TEMPLATES"
pocketbase migrate up --dir="$TEMPLATES/pristine" --migrationsDir=/pb/pb_migrations >/dev/null
pocketbase superuser upsert "$FFDEMO_SUPERUSER_EMAIL" "$FFDEMO_SUPERUSER_PASSWORD" \
  --dir="$TEMPLATES/pristine" >/dev/null

# A template name is a plain word: it becomes a directory name.
valid_name() {
  case "$1" in
    "" | *[!A-Za-z0-9_-]*) return 1 ;;
    *) return 0 ;;
  esac
}

halt() {
  kill "$pid"
  wait "$pid" 2>/dev/null || true
  pid=""
}

gen=0
source=pristine
while :; do
  gen=$((gen + 1))
  if [ ! -d "$TEMPLATES/$source" ]; then
    echo "ffdemo: no template \"$source\", serving pristine" >&2
    source=pristine
  fi
  rm -rf "$DATA"
  cp -a "$TEMPLATES/$source" "$DATA"
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
  echo "ffdemo: backend generation $gen is up (fresh copy of template \"$source\")"
  while :; do
    kill -0 "$pid" 2>/dev/null || { echo "ffdemo: PocketBase exited" >&2; exit 1; }
    # "<gen>" or "<gen> <template>"
    set -- $(cat "$CTL/snapshot" 2>/dev/null || true)
    if [ "${1:-}" = "$gen" ] && valid_name "${2:-}" && [ "$2" != pristine ]; then
      rm -f "$CTL/snapshot"
      halt
      rm -rf "$TEMPLATES/$2"
      cp -a "$DATA" "$TEMPLATES/$2"
      echo "ffdemo: generation $gen saved as template \"$2\""
      source="$2"
      break
    fi
    set -- $(cat "$CTL/reset" 2>/dev/null || true)
    if [ "${1:-}" = "$gen" ]; then
      source="${2:-pristine}"
      valid_name "$source" || source=pristine
      halt
      break
    fi
    sleep 0.2
  done
done
