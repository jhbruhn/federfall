#!/bin/sh
# The compose stack, without a compose provider: the same two images, the same
# mounts and environment, with plain `podman` or `docker`. Use this where no
# compose provider is installed; compose.yaml is the reference and wins if the
# two ever disagree.
#
#   tools/demo-videos/nocompose.sh A3 --locale de
#   ENGINE=docker tools/demo-videos/nocompose.sh all
#
# Builds both images (cached after the first time), starts the backend, runs
# the recorder in the backend's network namespace, removes both containers and
# the control volume again, and exits with the recorder's status.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ENGINE="${ENGINE:-podman}"
P="ffdemo-$$"
BACKEND_IMAGE=localhost/ffdemo-federfall:local
STUDIO_IMAGE=localhost/ffdemo-studio:local

if [ "${FFDEMO_SKIP_BUILD:-0}" != 1 ]; then
  "$ENGINE" build -t "$BACKEND_IMAGE" -f "$ROOT/Dockerfile" "$ROOT"
  "$ENGINE" build --target studio -t "$STUDIO_IMAGE" -f "$HERE/runner/Containerfile" "$HERE/runner"
fi

cleanup() {
  "$ENGINE" rm -f "$P-record" "$P-backend" >/dev/null 2>&1 || true
  "$ENGINE" volume rm -f "$P-ctl" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

mkdir -p "$HERE/out"
"$ENGINE" volume create "$P-ctl" >/dev/null

# Keep in step with compose.yaml.
"$ENGINE" run -d --name "$P-backend" \
  -e TZ=Europe/Berlin \
  -e FFDEMO_SUPERUSER_EMAIL=superuser@ffdemo.example \
  -e FFDEMO_SUPERUSER_PASSWORD=ffdemo-superuser \
  -e FEDERFALL_SUPERVISOR_EMAIL=leitung@wildvogelhilfe.example \
  -e FEDERFALL_SUPERVISOR_PASSWORD=demo-video-1 \
  -e FEDERFALL_SUPERVISOR_NAME="Johanna Brandt" \
  -e FEDERFALL_NOMINATIM_URL=http://127.0.0.1:8091 \
  -e FEDERFALL_USER_AGENT="federfall-demo-videos" \
  -e FEDERFALL_MAP_MODE=raster \
  -e "FEDERFALL_MAP_TILE_URL=http://127.0.0.1:8092/{z}/{x}/{y}.png" \
  -e "FEDERFALL_MAP_ATTRIBUTION=© OpenStreetMap contributors" \
  -e FEDERFALL_MAP_ATTRIBUTION_URL=https://www.openstreetmap.org/copyright \
  -v "$HERE/backend/serve.sh:/ffdemo/serve.sh:ro,z" \
  -v "$P-ctl:/ffdemo/ctl" \
  --entrypoint /bin/sh \
  "$BACKEND_IMAGE" /ffdemo/serve.sh >/dev/null

set +e
"$ENGINE" run --rm --name "$P-record" \
  --network "container:$P-backend" \
  --shm-size=1g \
  -e TZ=Europe/Berlin \
  -e DO_NOT_TRACK=1 \
  -e FFDEMO_SUPERUSER_EMAIL=superuser@ffdemo.example \
  -e FFDEMO_SUPERUSER_PASSWORD=ffdemo-superuser \
  ${FFDEMO_TILES:+-e FFDEMO_TILES="$FFDEMO_TILES"} \
  ${FFDEMO_NO_SANDBOX:+-e FFDEMO_NO_SANDBOX="$FFDEMO_NO_SANDBOX"} \
  -v "$HERE:/demo:ro,z" \
  -v "$ROOT/apps/federfall/lib/l10n/arb:/arb:ro,z" \
  -v "$HERE/out:/out:z" \
  -v "$P-ctl:/ffdemo/ctl" \
  "$STUDIO_IMAGE" "$@"
rc=$?
set -e
if [ "$rc" != 0 ]; then
  "$ENGINE" logs "$P-backend" >"$HERE/out/backend.log" 2>&1 || true
fi
exit "$rc"
