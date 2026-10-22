#!/usr/bin/env bash
# WSLg viewer only: no SDK, command publisher, or simulated JointState.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOMAIN=223
IMAGE=mirrorme-bpx-rviz-audit:20261015
while (($#)); do
  case "$1" in
    --help|-h) echo 'Usage: bash scripts/start-rviz.sh [--ros-domain-id 223] [--image IMAGE]'; exit 0 ;;
    --ros-domain-id) DOMAIN="${2:?missing domain}"; shift 2 ;;
    --image) IMAGE="${2:?missing image}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$DOMAIN" =~ ^[0-9]{1,3}$ ]] && ((10#$DOMAIN <= 232)) || { echo 'ROS domain must be 0..232' >&2; exit 2; }
[[ -n "${DISPLAY:-}" && -d /tmp/.X11-unix ]] || { echo 'Run inside a WSLg terminal with DISPLAY and /tmp/.X11-unix available.' >&2; exit 2; }
docker image inspect "$IMAGE" >/dev/null
exec docker run --rm --init --name bpx_rviz_viewer --network host --ipc host \
  -e DISPLAY -e ROS_DOMAIN_ID="$DOMAIN" -e LIBGL_ALWAYS_SOFTWARE=1 -e QT_X11_NO_MITSHM=1 \
  -v /tmp/.X11-unix:/tmp/.X11-unix:ro -v "$ROOT:/deploy:ro" \
  --entrypoint bash "$IMAGE" -c '
set -eo pipefail
source /opt/ros/humble/setup.bash
python3 /deploy/scripts/prepare_rviz_model.py /deploy/urdf/mirrorme_bpx.urdf /tmp/bpx-rviz.urdf
ros2 run robot_state_publisher robot_state_publisher /tmp/bpx-rviz.urdf &
publisher=$!
trap '\''kill "$publisher" 2>/dev/null || true; wait "$publisher" 2>/dev/null || true'\'' EXIT
rviz2 -d /deploy/rviz/bpx.rviz
'
