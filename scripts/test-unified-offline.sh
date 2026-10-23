#!/usr/bin/env bash
# No network, Docker socket, SDK wheel, host IPC or robot connection.
set -euo pipefail
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  echo 'Usage: bash scripts/test-unified-offline.sh (isolated fake Atlas/ROS/gRPC test; no SDK)'
  exit 0
fi
(($# == 0)) || { echo 'unexpected arguments' >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(dirname "$ROOT")"
TARGET="${BPX_TARGET_CACHE:-$HOME/.cache/robonix-bpx/target}"
mkdir -p "$ROOT/.artifacts/unified"
docker run --rm --network none \
  -v "$WORKSPACE/primitive-mirrorme-bpx-quadruped-rbnx:/pkg:ro" \
  -v "$WORKSPACE/.deps/robonix:/robonix:ro" \
  -v "$WORKSPACE/.deps/robonix/pylib/robonix-api:/robonix-api:ro" \
  -v "$TARGET:/target:ro" \
  -e PYTHONPATH=/pkg:/robonix-api:/pkg/rbnx-build/codegen/proto_gen \
  -e BPX_REQUIRED_BACKEND=fake -e BPX_REQUIRED_POSTURE_CAPABILITY=true \
  -e BPX_POSTURE_CAPABILITY=true -e BPX_MOTION_CAPABILITY=true \
  -e RBNX_INSTANCE_NAME=mirrorme_bpx -e RBNX_DEPLOY_MANAGED=1 \
  -e ROBONIX_ATLAS=127.0.0.1:50051 -e ROBONIX_ADVERTISE_HOST=127.0.0.1 \
  -e ROBONIX_PROVIDER_BIND_HOST=127.0.0.1 -e ROS_DOMAIN_ID=226 \
  "${BPX_RBNX_IMAGE:-primitive-mirrorme-bpx-quadruped-rbnx:dev}" \
  timeout 90 python3 /pkg/tests/verify_unified_rpc.py \
  2>&1 | tee "$ROOT/.artifacts/unified/rpc-$(date -u +%Y%m%dT%H%M%SZ).log"
