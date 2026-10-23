#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" == --help || $# == 0 ]]; then
  echo 'Usage: bash scripts/acceptance.sh observe [--seconds 40]'
  echo '       bash scripts/acceptance.sh move --forward-m 0.2 --duration-sec 10'
  echo 'Records one move without manual arm, or passive odom only. Observe never issues motion.'
  echo 'Evidence: .artifacts/acceptance/<unique directory>/capture.jsonl and report.json'
  exit 0
fi
mode="$1"; shift
case "$mode" in
  observe) args=(--observe-only "$@") ;;
  move) args=("$@") ;;
  *) echo 'mode must be observe or move' >&2; exit 2 ;;
esac
container=rbnx_mirrorme_bpx_quadruped
[[ "$(docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null || true)" == true ]] || {
  echo 'Provider is not running. Start motion-test.sh in another terminal first.' >&2; exit 2;
}
mkdir -p "$ROOT/.artifacts/acceptance"
output="$(mktemp -d "$ROOT/.artifacts/acceptance/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
echo "Evidence: $output"
docker inspect --format '{{.Image}}' "$container" > "$output/image.txt"
git -C "$ROOT" rev-parse HEAD > "$output/robot-head.txt"
git -C "$ROOT/../primitive-mirrorme-bpx-quadruped-rbnx" rev-parse HEAD > "$output/primitive-head.txt"
docker exec -w /pkg "$container" python3 -m bpx_quadruped.local_control status > "$output/status-before.json"
set +e
docker exec -w /pkg -e PYTHONPATH=/pkg:/robonix-api:/pkg/rbnx-build/codegen/proto_gen "$container" \
  bash -c 'source /opt/ros/humble/setup.bash && exec python3 -u -m bpx_quadruped.motion_capture "$@"' \
  capture "${args[@]}" 2>&1 | tee "$output/capture.jsonl" | awk '!/"event": "odom"|"event": "motion_status"/ {print; fflush()}'
status=${PIPESTATUS[0]}
set -e
docker exec -w /pkg "$container" python3 -m bpx_quadruped.local_control status > "$output/status-after.json" || true
python3 "$ROOT/scripts/analyze_acceptance.py" "$output/capture.jsonl" --output "$output/report.json"
echo "Evidence saved: $output (capture exit: $status)"
exit "$status"
