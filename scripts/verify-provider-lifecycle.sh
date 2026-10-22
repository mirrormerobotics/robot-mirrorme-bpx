#!/usr/bin/env bash
# Isolated entry-point regression; mocked runtime, no SDK or hardware calls.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/cli.sh"
cli_init 'bash scripts/verify-provider-lifecycle.sh'
cli_parse "$@"
cli_no_args
root="$(cd "$(dirname "$0")/.." && pwd)"
workspace="$(dirname "$root")"
mkdir -p "$root/.artifacts/m4"
report="$root/.artifacts/m4/$(date -u +%Y%m%dT%H%M%S)-$$.log"
docker run --rm --network none \
  -e PYTHONPATH=/pkg:/robonix-api:/pkg/rbnx-build/codegen/proto_gen \
  -v "$workspace/primitive-mirrorme-bpx-quadruped-rbnx:/pkg:ro" \
  -v "$workspace/.deps/robonix/pylib/robonix-api:/robonix-api:ro" \
  -w /pkg primitive-mirrorme-bpx-quadruped-rbnx:dev \
  python3 tests/verify_provider_lifecycle.py 2>&1 | tee "$report"
echo "Evidence: $report"
