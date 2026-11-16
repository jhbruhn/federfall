#!/bin/sh
# Runner entrypoint. Starts as root only to do two things a non-root process
# cannot do portably:
#
#   - hand results to the mounted /out with the ownership of whoever owns that
#     directory on the host (rootless podman maps container root to the host
#     user; rootful docker does not, so `chown` to the directory's owner is the
#     one rule that is right for both), and
#   - probe whether this engine lets an unprivileged process create a user
#     namespace, which Chromium's and Electron's sandboxes need. Rootless podman
#     does; docker's default seccomp profile does not. Where it cannot, the
#     sandbox is switched off (FFDEMO_NO_SANDBOX=1) and the run says so —
#     everything rendered here is our own app and our own project file.
#
# Everything else runs as uid 1000 in /work, and only the harness decides what
# reaches /out: a finished clip under its final name, or a failure record.
set -eu

OUT=/out
WORK=/work
mkdir -p "$WORK"
chown rec:rec "$WORK"
if [ -d "$OUT/.cache" ]; then
  cp -a "$OUT/.cache" "$WORK/.cache"
  chown -R rec:rec "$WORK/.cache"
fi

# `export` re-renders earlier captures, so it needs them back.
if [ "${1:-}" = export ] && [ -d "$OUT/work" ]; then
  mkdir -p "$WORK/out"
  cp -a "$OUT/work" "$WORK/out/work"
  chown -R rec:rec "$WORK/out"
fi

as_rec() { setpriv --reuid=1000 --regid=1000 --init-groups env HOME=/home/rec "$@"; }

if [ "${FFDEMO_NO_SANDBOX:-}" != 1 ] && ! as_rec unshare --user --map-root-user true 2>/dev/null; then
  echo "ffdemo: this engine forbids unprivileged user namespaces; running Chromium and OpenScreen with --no-sandbox" >&2
  export FFDEMO_NO_SANDBOX=1
fi

# Clips are copied under a temporary name and renamed, so a final name never
# names a half-copied file. A run that failed lists its clip in .unpublish: an
# older clip under that name is removed, so nothing in /out looks like the
# result of a run that did not produce it.
publish() {
  owner="$(stat -c %u:%g "$OUT")"
  if [ -f "$WORK/out/.unpublish" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] && rm -f "$OUT/$name"
    done <"$WORK/out/.unpublish"
    rm -f "$WORK/out/.unpublish"
  fi
  if [ -d "$WORK/out" ]; then
    for clip in "$WORK"/out/*.mp4; do
      [ -f "$clip" ] || continue
      name="$(basename "$clip")"
      cp "$clip" "$OUT/.$name.partial"
      mv -f "$OUT/.$name.partial" "$OUT/$name"
      rm -f "$clip"
    done
    # A run's work directory replaces the previous one of the same video and
    # language, so it never mixes files from two runs.
    for d in "$WORK"/out/work/*/; do
      [ -d "$d" ] && rm -rf "$OUT/work/$(basename "$d")"
    done
    cp -r "$WORK/out/." "$OUT/"
  fi
  if [ -d "$WORK/.cache" ]; then
    mkdir -p "$OUT/.cache"
    cp -r "$WORK/.cache/." "$OUT/.cache/"
  fi
  chown -R "$owner" "$OUT" 2>/dev/null || true
}

set +e
as_rec node /demo/harness/cli.mjs "$@"
rc=$?
set -e
publish
exit "$rc"
