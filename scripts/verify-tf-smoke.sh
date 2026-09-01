#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${BPX_TF_TEST_IMAGE:-primitive-mirrorme-bpx-quadruped-rbnx:dev}"
ROS_DOMAIN_ID="${BPX_TF_ROS_DOMAIN_ID:-221}"
CONTAINER="${BPX_TF_TEST_CONTAINER:-rbnx_mirrorme_bpx_tf_test_$$}"

command -v docker >/dev/null 2>&1 || {
  echo "docker is required for the robot_state_publisher TF smoke test" >&2
  exit 1
}

docker run --rm \
  --name "$CONTAINER" \
  --label ai.robonix.test=mirrorme-bpx-model \
  --network host \
  --ipc host \
  -e ROS_DOMAIN_ID="$ROS_DOMAIN_ID" \
  -v "$ROOT:/deploy:ro" \
  --entrypoint /bin/bash \
  "$IMAGE" \
  -c '
set -eo pipefail
source /opt/ros/humble/setup.bash
set -u

cleanup() {
  kill "${publisher_pid:-}" "${rsp_pid:-}" >/dev/null 2>&1 || true
  wait "${publisher_pid:-}" "${rsp_pid:-}" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

ros2 run robot_state_publisher robot_state_publisher \
  /deploy/urdf/mirrorme_bpx.urdf \
  > /tmp/bpx-rsp.log 2>&1 &
rsp_pid=$!
sleep 1
kill -0 "$rsp_pid" 2>/dev/null || {
  cat /tmp/bpx-rsp.log >&2
  exit 1
}

python3 /deploy/tests/publish_joint_state.py \
  > /tmp/bpx-joint-publisher.log 2>&1 &
publisher_pid=$!
sleep 2

for target in fl_toe_link fr_toe_link hl_toe_link hr_toe_link; do
  : > /tmp/bpx-tf.log
  timeout --signal=INT 6s stdbuf -oL -eL \
    ros2 run tf2_ros tf2_echo base_link "$target" \
    > /tmp/bpx-tf.log 2>&1 || true
  grep -q "At time" /tmp/bpx-tf.log || {
    echo "no base_link -> $target transform observed" >&2
    cat /tmp/bpx-rsp.log >&2
    cat /tmp/bpx-joint-publisher.log >&2
    cat /tmp/bpx-tf.log >&2
    exit 1
  }
  echo "base_link -> $target: OK"
done
'
