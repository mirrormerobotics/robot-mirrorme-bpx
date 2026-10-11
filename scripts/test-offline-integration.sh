#!/usr/bin/env bash
set -euo pipefail

ROBOT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(cd "$ROBOT_ROOT/.." && pwd)"
PRIMITIVE_ROOT="$WORKSPACE/primitive-mirrorme-bpx-quadruped-rbnx"
ROBONIX_SOURCE=""
PROFILE=""
EXPECTED_COMMIT="f6cacfc4b402eb57c75b553d375c6cfaba11dce7"
TOOL_IMAGE="mirrorme-bpx-rbnx-codegen:dev"
RUNTIME_IMAGE="primitive-mirrorme-bpx-quadruped-rbnx:dev"
OUTER_CONTAINER="rbnx_mirrorme_bpx_offline_test"
PRIMITIVE_CONTAINER="rbnx_mirrorme_bpx_quadruped"
TARGET_CACHE="$PRIMITIVE_ROOT/.artifacts/rbnx-tool/target"
CARGO_CACHE="$PRIMITIVE_ROOT/.artifacts/rbnx-tool/cargo"
CONFIG_CACHE="$PRIMITIVE_ROOT/.artifacts/rbnx-tool/config"
source "$(dirname "${BASH_SOURCE[0]}")/lib/cli.sh"
cli_init 'bash scripts/test-offline-integration.sh [SOURCE [replay|fake]] [options]'
cli_option --robonix-source ROBONIX_SOURCE 'Fixed Robonix checkout'
cli_option --profile PROFILE 'replay (default) or fake'
cli_option --expected-commit EXPECTED_COMMIT 'Expected full Robonix commit'
cli_option --tool-image TOOL_IMAGE 'Robonix tool image'
cli_option --runtime-image RUNTIME_IMAGE 'Primitive runtime image'
cli_option --container-name OUTER_CONTAINER 'Outer test container'
cli_option --primitive-container PRIMITIVE_CONTAINER 'Primitive container'
cli_option --target-cache TARGET_CACHE 'Rust target cache'
cli_option --cargo-cache CARGO_CACHE 'Cargo cache'
cli_option --config-cache CONFIG_CACHE 'Robonix config cache'
cli_parse "$@"
((${#CLI_ARGS[@]} <= 2)) || cli_die 'too many positional arguments'
if ((${#CLI_ARGS[@]} >= 1)); then
  [[ -z "$ROBONIX_SOURCE" ]] || cli_die 'source specified twice'
  ROBONIX_SOURCE="${CLI_ARGS[0]}"
fi
if ((${#CLI_ARGS[@]} == 2)); then
  [[ -z "$PROFILE" ]] || cli_die 'profile specified twice'
  PROFILE="${CLI_ARGS[1]}"
fi
ROBONIX_SOURCE="${ROBONIX_SOURCE:-/tmp/robonix_dev_next}"
PROFILE="${PROFILE:-replay}"

case "$PROFILE" in
  replay)
    MANIFEST="$ROBOT_ROOT/robonix_manifest.replay-state.yaml"
    PROVIDER_ID="mirrorme_bpx_replay"
    ROS_DOMAIN_ID_VALUE="224"
    ;;
  fake)
    MANIFEST="$ROBOT_ROOT/robonix_manifest.fake-state.yaml"
    PROVIDER_ID="mirrorme_bpx_quadruped"
    ROS_DOMAIN_ID_VALUE="222"
    ;;
  *)
    echo "profile must be replay or fake" >&2
    exit 2
    ;;
esac

command -v docker >/dev/null 2>&1 || {
  echo "docker is required" >&2
  exit 1
}
[[ -d "$ROBONIX_SOURCE/.git" ]] || {
  echo "fixed Robonix source is missing: $ROBONIX_SOURCE" >&2
  exit 2
}
actual_commit="$(git -C "$ROBONIX_SOURCE" rev-parse HEAD)"
[[ "$actual_commit" == "$EXPECTED_COMMIT" ]] || {
  echo "unexpected Robonix commit: $actual_commit" >&2
  exit 1
}
mkdir -p "$TARGET_CACHE" "$CARGO_CACHE" "$CONFIG_CACHE"
TARGET_CACHE="$(realpath "$TARGET_CACHE")"
CARGO_CACHE="$(realpath "$CARGO_CACHE")"
CONFIG_CACHE="$(realpath "$CONFIG_CACHE")"
[[ -x "$TARGET_CACHE/release/rbnx" ]] || {
  echo "fixed rbnx binary is missing; run Primitive scripts/verify-rbnx.sh first" >&2
  exit 2
}
docker image inspect "$TOOL_IMAGE" >/dev/null
docker image inspect "$RUNTIME_IMAGE" >/dev/null
if docker inspect "$OUTER_CONTAINER" >/dev/null 2>&1; then
  echo "refusing to replace existing container: $OUTER_CONTAINER" >&2
  exit 1
fi

DOCKER_BIN="$(realpath "$(command -v docker)")"

cleanup() {
  docker stop -t 30 "$OUTER_CONTAINER" >/dev/null 2>&1 || true
  docker rm -f "$OUTER_CONTAINER" >/dev/null 2>&1 || true
  bash "$PRIMITIVE_ROOT/scripts/stop.sh" --container-name "$PRIMITIVE_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker run --detach \
  --name "$OUTER_CONTAINER" \
  --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$DOCKER_BIN:/usr/local/bin/docker:ro" \
  -v "$WORKSPACE:$WORKSPACE" \
  -v "$ROBONIX_SOURCE:$ROBONIX_SOURCE:ro" \
  -v "$TARGET_CACHE:/target" \
  -v "$CARGO_CACHE:/cargo" \
  -v "$CONFIG_CACHE:/root/.robonix" \
  -e "BPX_RBNX_IMAGE=$RUNTIME_IMAGE" \
  -e "BPX_RBNX_CONTAINER=$PRIMITIVE_CONTAINER" \
  -e CARGO_HOME=/cargo \
  -e CARGO_TARGET_DIR=/target \
  -e "ROBONIX_SOURCE=$ROBONIX_SOURCE" \
  -e "MANIFEST=$MANIFEST" \
  -e "ROS_DOMAIN_ID=$ROS_DOMAIN_ID_VALUE" \
  -e RBNX_INVOCATION_CWD="$ROBOT_ROOT" \
  -e ROBONIX_CODEGEN_BIN=/target/release/robonix-codegen \
  -w "$ROBOT_ROOT" \
  "$TOOL_IMAGE" \
  bash -lc 'export PATH="/target/release:$PATH"; /target/release/rbnx setup "$ROBONIX_SOURCE" >/dev/null && exec /target/release/rbnx boot -f "$MANIFEST" --no-update-check -v' \
  >/dev/null

caps_output=""
for _ in $(seq 1 120); do
  if [[ "$(docker inspect --format '{{.State.Running}}' "$OUTER_CONTAINER")" != "true" ]]; then
    docker logs "$OUTER_CONTAINER" >&2
    echo "offline boot container exited before readiness" >&2
    exit 1
  fi
  caps_output="$(docker exec "$OUTER_CONTAINER" /target/release/rbnx caps -v 2>&1 || true)"
  if grep -q "$PROVIDER_ID" <<<"$caps_output" && grep -q "quadruped/odom" <<<"$caps_output"; then
    break
  fi
  sleep 1
done
grep -q "$PROVIDER_ID" <<<"$caps_output" || {
  docker logs "$OUTER_CONTAINER" >&2
  echo "provider did not become discoverable" >&2
  exit 1
}
grep -q "quadruped/odom" <<<"$caps_output"
if [[ "$PROFILE" == "replay" ]] && grep -q "quadruped/twist_in" <<<"$caps_output"; then
  echo "read-only replay profile unexpectedly declared twist_in" >&2
  exit 1
fi

DRIVER_DOCKER_ARGS=(
  --rm
  --network host
  -e ROBONIX_ATLAS=127.0.0.1:50051
  -e PYTHONPATH=/pkg/rbnx-build/codegen/proto_gen
  -v "$PRIMITIVE_ROOT:/pkg"
  -v "$ROBOT_ROOT:/robot:ro"
  -v "$ROBONIX_SOURCE/pylib/robonix-api:/robonix-api:ro"
  "$RUNTIME_IMAGE"
  python3
  /robot/scripts/call_driver.py
  "$PROVIDER_ID"
)

docker run "${DRIVER_DOCKER_ARGS[@]}" deactivate
docker run "${DRIVER_DOCKER_ARGS[@]}" activate

docker run --rm --network host --ipc host \
  -e ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" \
  "$RUNTIME_IMAGE" \
  timeout 15 ros2 topic echo /odom --once --qos-reliability best_effort \
  >/dev/null

odom_info="$(docker run --rm --network host --ipc host \
  -e ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" \
  "$RUNTIME_IMAGE" \
  timeout 15 ros2 topic info /odom --verbose)"
grep -q "Publisher count: 1" <<<"$odom_info" || {
  echo "expected exactly one /odom publisher" >&2
  echo "$odom_info" >&2
  exit 1
}

docker run --rm --network host --ipc host \
  -e ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" \
  "$RUNTIME_IMAGE" \
  timeout 15 ros2 topic echo /tf --once --qos-reliability best_effort \
  >/dev/null

docker run --rm --network host --ipc host \
  -e ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" \
  "$RUNTIME_IMAGE" \
  timeout 40 ros2 topic echo /joint_states --once --qos-reliability best_effort \
  >/dev/null

if [[ "$PROFILE" == "fake" ]]; then
  cmd_info="$(docker run --rm --network host --ipc host \
    -e ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" \
    "$RUNTIME_IMAGE" \
    timeout 15 ros2 topic info /cmd_vel --verbose)"
  grep -q "Subscription count: 1" <<<"$cmd_info" || {
    echo "expected exactly one /cmd_vel subscriber" >&2
    echo "$cmd_info" >&2
    exit 1
  }
  docker run --rm --network host --ipc host \
    -e ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" \
    "$RUNTIME_IMAGE" \
    timeout 15 ros2 topic pub --once /cmd_vel geometry_msgs/msg/Twist \
      '{linear: {x: 0.0, y: 0.0, z: 1.0}, angular: {x: 0.0, y: 0.0, z: 0.0}}' \
    >/dev/null
  for _ in $(seq 1 10); do
    if grep -q "rejected non-planar Twist" \
      "$ROBOT_ROOT/rbnx-boot/logs/$PROVIDER_ID.log"; then
      break
    fi
    sleep 1
  done
  grep -q "rejected non-planar Twist" \
    "$ROBOT_ROOT/rbnx-boot/logs/$PROVIDER_ID.log" || {
      echo "provider did not log rejection of non-planar Twist" >&2
      exit 1
    }
fi

docker stop -t 30 "$OUTER_CONTAINER" >/dev/null
docker rm "$OUTER_CONTAINER" >/dev/null
for _ in $(seq 1 30); do
  if ! docker ps -a --filter label=ai.robonix.package=robonix.primitive.mirrorme.bpx.quadruped --format '{{.ID}}' | grep -q .; then
    break
  fi
  sleep 1
done
if docker ps -a --filter label=ai.robonix.package=robonix.primitive.mirrorme.bpx.quadruped --format '{{.ID}}' | grep -q .; then
  echo "Primitive container remained after shutdown" >&2
  exit 1
fi

trap - EXIT INT TERM
echo "offline $PROFILE integration: PASS"
