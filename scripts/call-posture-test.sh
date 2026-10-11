#!/usr/bin/env bash
set -euo pipefail

ROBOT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(cd "$ROBOT_ROOT/.." && pwd)"
PRIMITIVE_ROOT="$WORKSPACE/primitive-mirrorme-bpx-quadruped-rbnx"
ROBONIX_SOURCE="/tmp/robonix_dev_next"
OUTER_CONTAINER="rbnx_mirrorme_bpx_sdk"
source "$(dirname "${BASH_SOURCE[0]}")/lib/cli.sh"
cli_init 'bash scripts/call-posture-test.sh stand|sit [provider-id] [options]'
cli_option --container-name OUTER_CONTAINER 'Running Deployment container'
cli_option --robonix-source ROBONIX_SOURCE 'Robonix source path inside Deployment'
cli_option --primitive-root PRIMITIVE_ROOT 'Primitive path inside Deployment'
cli_parse "$@"
set -- "${CLI_ARGS[@]}"
(($# >= 1 && $# <= 2)) || cli_die 'expected stand|sit and optional provider-id'
POSTURE="${1:-}"
PROVIDER_ID="${2:-mirrorme_bpx}"

[[ "$POSTURE" == "stand" || "$POSTURE" == "sit" ]] || {
  echo "usage: $0 stand|sit [provider-id]" >&2
  exit 2
}
docker inspect "$OUTER_CONTAINER" >/dev/null 2>&1 || {
  echo "BPX Deployment container is not running: $OUTER_CONTAINER" >&2
  exit 2
}

docker exec \
  -e ROBONIX_ATLAS=127.0.0.1:50051 \
  -e "BPX_POSTURE=$POSTURE" \
  -e "BPX_POSTURE_PROVIDER_ID=$PROVIDER_ID" \
  -e "BPX_PRIMITIVE_ROOT=$PRIMITIVE_ROOT" \
  -e "BPX_ROBONIX_SOURCE=$ROBONIX_SOURCE" \
  "$OUTER_CONTAINER" \
  bash -lc 'export PYTHONPATH="$BPX_PRIMITIVE_ROOT:$BPX_PRIMITIVE_ROOT/rbnx-build/codegen/proto_gen:$BPX_ROBONIX_SOURCE/pylib/robonix-api:${PYTHONPATH:-}"; exec python3 -m bpx_quadruped.posture_client "$BPX_POSTURE" --provider-id "$BPX_POSTURE_PROVIDER_ID" --timeout-s 20'
