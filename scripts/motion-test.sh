#!/usr/bin/env bash
# Manual WSL/Linux operator entry. Never chains stand, arm and movement.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(dirname "$ROOT")"
CONTAINER="${BPX_RBNX_CONTAINER:-rbnx_mirrorme_bpx_quadruped}"
PROVIDER="${BPX_PROVIDER_ID:-mirrorme_bpx_motion}"
action="${1:-help}"
(($# == 0)) || shift
case "$action" in
  help|--help|-h)
    cat <<'EOF'
Usage: bash scripts/motion-test.sh ACTION [options]
  preview|preview-unified [--robot-ip IP] [--sdk-wheel PATH]                 Render only; no robot connection
  relay ROBOT_IP WINDOWS_WIFI_IP          Start Windows UDP relay from WSL
  start|start-unified --confirm-physical-motion-test [--robot-ip IP] [--sdk-wheel PATH]
                                         Foreground service; no automatic stand/arm
  status | stop | clear-fault | release | shutdown
  posture stand|sit        Standard remote posture RPC (set BPX_PROVIDER_ID=mirrorme_bpx)
  deactivate | activate    Standard Driver RPC; never automatically sends movement
  release closes the SDK session; restart the provider before further SDK control.
  stand|sit|arm --confirm-physical-motion-test
  forward --forward-m 0.1 --duration-sec 10
  rotate --rotate-deg 15 --duration-sec 10
  velocity --linear-x 0.1 --duration-sec 1
Movement uses the standard bounded move RPC. Each move stops; the next command needs no arm. stop cancels current motion; shutdown disables the service.
Bounded distance/angle moves default to minimum targets 0.25 m/s / 0.25 rad/s.
Timed velocity and Twist are not boosted. See M5_VALIDATION_2026-10-14.md.
Start the service in one terminal; operate from another. WSL NAT still needs
the Windows state-relay.ps1 process. See MOTION_TEST_GUIDE.md.
EOF
    exit 0 ;;
  relay)
    [[ $# == 2 ]] || { echo 'relay requires ROBOT_IP WINDOWS_WIFI_IP' >&2; exit 2; }
    if [[ ! -r /proc/sys/fs/binfmt_misc/WSLInterop ]] ||
       ! grep -qx enabled /proc/sys/fs/binfmt_misc/WSLInterop; then
      echo 'WSL Windows interop is unavailable; the UDP relay has not started.' >&2
      echo 'Run the relay directly in a Windows terminal instead:' >&2
      echo "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"$(wslpath -w "$ROOT/scripts/state-relay.ps1")\" -RobotIp $1 -ListenIp $2" >&2
      exit 2
    fi
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File \
      "$(wslpath -w "$ROOT/scripts/state-relay.ps1")" -RobotIp "$1" -ListenIp "$2"
    ;;
  preview|start|preview-unified|start-unified)
    confirm=0
    robot_ip=10.21.40.1
    sdk_wheel="${BPX_SDK_WHEEL:-$WORKSPACE/.deps/sdk/bpx_sdk_open-1.0.9-cp310-cp310-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl}"
    while (($#)); do
      case "$1" in
        --confirm-physical-motion-test) confirm=1; shift ;;
        --sdk-wheel) [[ $# -ge 2 ]] || { echo "missing SDK wheel" >&2; exit 2; }; sdk_wheel="$2"; shift 2 ;;
        --robot-ip) [[ $# -ge 2 ]] || { echo 'missing robot IP' >&2; exit 2; }; robot_ip="$2"; shift 2 ;;
        *) echo "unknown startup option: $1" >&2; exit 2 ;;
      esac
    done
    [[ "$action" == preview* || "$confirm" == 1 ]] || {
      echo 'start requires --confirm-physical-motion-test' >&2; exit 2;
    }
    extra=()
    [[ "$action" != preview* ]] || extra+=(--dry-run)
    profile=--motion-test
    [[ "$action" != *-unified ]] || profile=--release-motion
    exec bash "$ROOT/scripts/start-sdk-read-only-docker.sh" \
      "$profile" --confirm-physical-motion-test --robot-ip "$robot_ip" \
      --sdk-wheel "$sdk_wheel" \
      --robonix-source "$WORKSPACE/.deps/robonix" \
      --target-cache "$HOME/.cache/robonix-bpx/target" \
      --cargo-cache "$HOME/.cache/robonix-bpx/cargo" \
      --config-cache "$HOME/.cache/robonix-bpx/config" \
      --network-mode host --ros-domain-id 225 --keep-manifest "${extra[@]}"
    ;;
  posture)
    [[ $# == 1 && ( "$1" == stand || "$1" == sit ) ]] || { echo "posture requires stand or sit" >&2; exit 2; } ;;
  deactivate|activate)
    [[ $# == 0 ]] || exit 2 ;;
  stand|sit|arm)
    [[ $# == 1 && "$1" == --confirm-physical-motion-test ]] || {
      echo "$action requires --confirm-physical-motion-test" >&2; exit 2;
    }
    shift ;;
  status|stop|clear-fault|release|shutdown)
    [[ $# == 0 ]] || { echo 'unexpected arguments' >&2; exit 2; } ;;
  forward|rotate|velocity) ;;
  *) echo "unknown action: $action (use help)" >&2; exit 2 ;;
esac
if [[ "$action" == shutdown ]]; then
  exec docker stop -t 30 rbnx_mirrorme_bpx_sdk
fi
[[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" == true ]] || {
  echo 'Motion provider is not running. First run in another terminal:' >&2
  echo '  bash scripts/motion-test.sh start --confirm-physical-motion-test' >&2
  echo 'Keep that terminal open; if startup fails, inspect its error before issuing commands.' >&2
  exit 2
}
case "$action" in
  posture)
    exec docker exec -w /pkg -e PYTHONPATH=/pkg:/robonix-api:/pkg/rbnx-build/codegen/proto_gen \
      "$CONTAINER" python3 -m bpx_quadruped.posture_client "$1" --provider-id "$PROVIDER" ;;
  deactivate|activate)
    # Feed the helper through stdin; the provider container mounts only Primitive.
    exec docker exec -i -w /pkg -e PYTHONPATH=/pkg:/robonix-api:/pkg/rbnx-build/codegen/proto_gen \
      "$CONTAINER" python3 - "$PROVIDER" "$action" < "$ROOT/scripts/call_driver.py" ;;
  forward|rotate|velocity)
    exec docker exec -w /pkg -e PYTHONPATH=/pkg:/robonix-api:/pkg/rbnx-build/codegen/proto_gen \
      "$CONTAINER" python3 -m bpx_quadruped.move_client --provider-id "$PROVIDER" "$@" ;;
  *)
    [[ "$action" != stop ]] || action=disarm
    [[ "$action" != clear-fault ]] || action=clear_fault
    exec docker exec -w /pkg "$CONTAINER" python3 -m bpx_quadruped.local_control "$action" ;;
esac
