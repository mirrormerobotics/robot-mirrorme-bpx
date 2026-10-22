#!/usr/bin/env bash
set -euo pipefail

ROBOT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(cd "$ROBOT_ROOT/.." && pwd)"
PRIMITIVE_ROOT="$WORKSPACE/primitive-mirrorme-bpx-quadruped-rbnx"

SDK_WHEEL=""
ROBOT_IP=""
ROBOT_STATE_PORT=9873
STATE_RATE_HZ=50
IMU_FRAME=""
PUBLISH_ODOM_TF=false
CONNECT_TIMEOUT_S=10.0
ROS_DOMAIN_ID_VALUE=223
NETWORK_MODE=auto
DOCKER_HOST_ADDRESS=""
ROBONIX_SOURCE="/tmp/robonix_dev_next"
EXPECTED_ROBONIX_COMMIT="f6cacfc4b402eb57c75b553d375c6cfaba11dce7"
TOOL_IMAGE="mirrorme-bpx-rbnx-codegen:dev"
RUNTIME_IMAGE="primitive-mirrorme-bpx-quadruped-rbnx:dev"
OUTER_CONTAINER="rbnx_mirrorme_bpx_sdk"
PRIMITIVE_CONTAINER="rbnx_mirrorme_bpx_quadruped"
TARGET_CACHE=""
CARGO_CACHE=""
CONFIG_CACHE=""
DRY_RUN=0
KEEP_MANIFEST=0
OUTER_STARTED=0
POSTURE_TEST=0
RELEASE_POSTURE=0
MOTION_TEST=0
CONFIRM_MOTION_TEST=0
CONFIRM_POSTURE_TEST=0
POSTURE_CONFIRMATION="I_UNDERSTAND_POSTURE_RPC_CAN_MOVE_BPX"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/start-sdk-read-only-docker.sh \
    --sdk-wheel /absolute/path/to/bpx_sdk_open-1.0.8-...x86_64.whl \
    --robot-ip 192.168.1.237 [options]

Required:
  --sdk-wheel PATH             Pinned BPX SDK v1.0.8 x86_64 wheel
  --robot-ip IPV4              Reachable BPX IPv4 address

Options:
  --imu-frame FRAME           Enable raw IMU publication in this sensor frame
  --publish-odom-tf           Publish odom -> base_link (axes must be verified)
  --robot-state-port PORT      Robot state UDP receive port (default: 9873)
  --state-rate-hz HZ           Requested SDK state rate (default: 50)
  --connect-timeout-s SECONDS  First-odometry timeout (default: 10.0)
  --ros-domain-id ID           ROS 2 domain ID, 0..232 (default: 223)
  --network-mode MODE          auto, host, or bridge (default: auto)
  --docker-host-address IPV4   Atlas address from a bridge container;
                               auto-detected from Docker bridge by default
  --robonix-source PATH        Fixed Robonix checkout
                               (default: /tmp/robonix_dev_next)
  --expected-commit SHA        Expected full Robonix commit
  --target-cache PATH          Rust target cache
  --cargo-cache PATH           Cargo cache
  --config-cache PATH          Robonix config cache
  --tool-image IMAGE           Container image carrying the fixed rbnx tool
  --runtime-image IMAGE        BPX Primitive runtime image
  --container-name NAME        Outer Deployment container name
  --primitive-container NAME   BPX Primitive container name
  --dry-run                    Validate, render the generated YAML and exit
  --keep-manifest              Keep the generated YAML after exit
  --posture-test               Select the non-release stand/sit Robonix RPC
  --release-posture            Select the production odom + stand/sit package
  --motion-test               Select the unreleased locally armed motion profile
  --confirm-physical-motion-test
                              Required with --motion-test; never auto-arms
  --confirm-physical-posture-service
                               Acknowledge that posture RPCs move the robot;
                               required with either posture option
  -h, --help                   Show this help

The default launch is state-only: backend=sdk and allow_motion=false. Both
posture modes permit only exact stand/sit RPCs and still create no twist,
move, gait, damping, or joint-control interface.
EOF
}

die() {
  echo "error: $*" >&2
  exit 2
}

require_value() {
  [[ $# -ge 2 ]] || die "$1 requires a value"
  [[ -n "${2:-}" && "$2" != --* && "$2" != -h ]] || die "$1 requires a value"
}

is_ipv4() {
  local value="$1"
  local -a octets=()
  local octet
  IFS=. read -r -a octets <<<"$value"
  [[ ${#octets[@]} -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
    ((10#$octet <= 255)) || return 1
  done
}

while [[ $# -gt 0 ]]; do
  if [[ "$1" == --*=* ]]; then
    option="${1%%=*}"
    value="${1#*=}"
    shift
    set -- "$option" "$value" "$@"
  fi
  case "$1" in
    --imu-frame)
      require_value "$@"; IMU_FRAME="$2"; shift 2 ;;
    --publish-odom-tf)
      PUBLISH_ODOM_TF=true; shift ;;
    --expected-commit)
      require_value "$@"; EXPECTED_ROBONIX_COMMIT="$2"; shift 2 ;;
    --target-cache)
      require_value "$@"; TARGET_CACHE="$2"; shift 2 ;;
    --cargo-cache)
      require_value "$@"; CARGO_CACHE="$2"; shift 2 ;;
    --config-cache)
      require_value "$@"; CONFIG_CACHE="$2"; shift 2 ;;
    --sdk-wheel)
      require_value "$@"
      SDK_WHEEL="$2"
      shift 2
      ;;
    --robot-ip)
      require_value "$@"
      ROBOT_IP="$2"
      shift 2
      ;;
    --robot-state-port)
      require_value "$@"
      ROBOT_STATE_PORT="$2"
      shift 2
      ;;
    --state-rate-hz)
      require_value "$@"
      STATE_RATE_HZ="$2"
      shift 2
      ;;
    --connect-timeout-s)
      require_value "$@"
      CONNECT_TIMEOUT_S="$2"
      shift 2
      ;;
    --ros-domain-id)
      require_value "$@"
      ROS_DOMAIN_ID_VALUE="$2"
      shift 2
      ;;
    --network-mode)
      require_value "$@"
      NETWORK_MODE="$2"
      shift 2
      ;;
    --docker-host-address)
      require_value "$@"
      DOCKER_HOST_ADDRESS="$2"
      shift 2
      ;;
    --robonix-source)
      require_value "$@"
      ROBONIX_SOURCE="$2"
      shift 2
      ;;
    --tool-image)
      require_value "$@"
      TOOL_IMAGE="$2"
      shift 2
      ;;
    --runtime-image)
      require_value "$@"
      RUNTIME_IMAGE="$2"
      shift 2
      ;;
    --container-name)
      require_value "$@"
      OUTER_CONTAINER="$2"
      shift 2
      ;;
    --primitive-container)
      require_value "$@"
      PRIMITIVE_CONTAINER="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --keep-manifest)
      KEEP_MANIFEST=1
      shift
      ;;
    --posture-test)
      POSTURE_TEST=1
      shift
      ;;
    --release-posture)
      RELEASE_POSTURE=1
      shift
      ;;
    --motion-test)
      MOTION_TEST=1; shift ;;
    --confirm-physical-motion-test)
      CONFIRM_MOTION_TEST=1; shift ;;
    --confirm-physical-posture-service)
      CONFIRM_POSTURE_TEST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$SDK_WHEEL" ]] || die "--sdk-wheel is required"
[[ -n "$ROBOT_IP" ]] || die "--robot-ip is required"
((POSTURE_TEST + RELEASE_POSTURE + MOTION_TEST <= 1)) || die "deployment modes are mutually exclusive"
((MOTION_TEST == CONFIRM_MOTION_TEST)) || die "--motion-test requires --confirm-physical-motion-test (and vice versa)"
if ((POSTURE_TEST && RELEASE_POSTURE)); then
  die "--posture-test and --release-posture are mutually exclusive"
fi
if ((POSTURE_TEST || RELEASE_POSTURE)); then
  ((CONFIRM_POSTURE_TEST)) ||
    die "posture mode requires --confirm-physical-posture-service"
else
  ((!CONFIRM_POSTURE_TEST)) ||
    die "--confirm-physical-posture-service requires a posture mode"
fi
[[ -f "$SDK_WHEEL" ]] || die "SDK wheel is not a file: $SDK_WHEEL"
[[ -d "$ROBONIX_SOURCE/.git" ]] || die "Robonix checkout is missing: $ROBONIX_SOURCE"
[[ -d "$PRIMITIVE_ROOT" ]] || die "Primitive sibling repository is missing: $PRIMITIVE_ROOT"
is_ipv4 "$ROBOT_IP" || die "--robot-ip must be an IPv4 address: $ROBOT_IP"
[[ "$ROBOT_STATE_PORT" =~ ^[0-9]+$ ]] &&
  ((ROBOT_STATE_PORT >= 1024 && ROBOT_STATE_PORT <= 65535)) ||
  die "--robot-state-port must be in 1024..65535"
[[ "$STATE_RATE_HZ" =~ ^[0-9]+$ ]] &&
  ((STATE_RATE_HZ >= 1 && STATE_RATE_HZ <= 1000)) ||
  die "--state-rate-hz must be in 1..1000"
[[ "$CONNECT_TIMEOUT_S" =~ ^[0-9]+([.][0-9]+)?$ ]] &&
  [[ "$CONNECT_TIMEOUT_S" != "0" && "$CONNECT_TIMEOUT_S" != "0.0" ]] ||
  die "--connect-timeout-s must be positive"
[[ "$ROS_DOMAIN_ID_VALUE" =~ ^[0-9]+$ ]] &&
  ((ROS_DOMAIN_ID_VALUE >= 0 && ROS_DOMAIN_ID_VALUE <= 232)) ||
  die "--ros-domain-id must be in 0..232"
[[ "$OUTER_CONTAINER" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]+$ ]] ||
  die "invalid outer container name: $OUTER_CONTAINER"
[[ "$PRIMITIVE_CONTAINER" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]+$ ]] ||
  die "invalid Primitive container name: $PRIMITIVE_CONTAINER"

command -v docker >/dev/null 2>&1 || die "docker is required"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"

SDK_WHEEL="$(realpath "$SDK_WHEEL")"
ROBONIX_SOURCE="$(realpath "$ROBONIX_SOURCE")"
actual_robonix_commit="$(git -C "$ROBONIX_SOURCE" rev-parse HEAD)"
[[ "$actual_robonix_commit" == "$EXPECTED_ROBONIX_COMMIT" ]] ||
  die "unexpected Robonix commit: $actual_robonix_commit (expected $EXPECTED_ROBONIX_COMMIT)"

wheel_name="$(basename "$SDK_WHEEL")"
expected_wheel_sha="$(awk -v name="$wheel_name" '$2 == name {print $1}' \
  "$PRIMITIVE_ROOT/sdk/SHA256SUMS")"
[[ -n "$expected_wheel_sha" ]] || die "SDK wheel is not pinned: $wheel_name"
actual_wheel_sha="$(sha256sum "$SDK_WHEEL" | awk '{print $1}')"
[[ "$actual_wheel_sha" == "$expected_wheel_sha" ]] ||
  die "SDK wheel checksum mismatch: $actual_wheel_sha"

case "$NETWORK_MODE" in
  auto)
    docker_os="$(docker info --format '{{.OperatingSystem}}')"
    if [[ "${docker_os,,}" == *"docker desktop"* ]]; then
      NETWORK_MODE=bridge
    else
      NETWORK_MODE=host
    fi
    ;;
  host|bridge)
    ;;
  *)
    die "--network-mode must be auto, host, or bridge"
    ;;
esac

if [[ "$NETWORK_MODE" == "bridge" ]]; then
  if [[ -z "$DOCKER_HOST_ADDRESS" ]]; then
    DOCKER_HOST_ADDRESS="$(docker network inspect bridge \
      --format '{{(index .IPAM.Config 0).Gateway}}')"
  fi
  is_ipv4 "$DOCKER_HOST_ADDRESS" ||
    die "could not determine a valid Docker bridge gateway"
  ATLAS_LISTEN="0.0.0.0:50051"
else
  ATLAS_LISTEN="127.0.0.1:50051"
fi

TARGET_CACHE="${TARGET_CACHE:-$PRIMITIVE_ROOT/.artifacts/rbnx-tool/target}"
CARGO_CACHE="${CARGO_CACHE:-$PRIMITIVE_ROOT/.artifacts/rbnx-tool/cargo}"
CONFIG_CACHE="${CONFIG_CACHE:-$PRIMITIVE_ROOT/.artifacts/rbnx-tool/config}"
mkdir -p "$TARGET_CACHE" "$CARGO_CACHE" "$CONFIG_CACHE"
TARGET_CACHE="$(realpath "$TARGET_CACHE")"
CARGO_CACHE="$(realpath "$CARGO_CACHE")"
CONFIG_CACHE="$(realpath "$CONFIG_CACHE")"
RBNX_BIN="$TARGET_CACHE/release/rbnx"
CODEGEN_BIN="$TARGET_CACHE/release/robonix-codegen"

if [[ ! -x "$RBNX_BIN" || ! -x "$CODEGEN_BIN" ]] ||
  ! docker image inspect "$TOOL_IMAGE" >/dev/null 2>&1; then
  if ((DRY_RUN)); then
    die "fixed rbnx tools are missing; run Primitive scripts/verify-rbnx.sh first"
  fi
  echo "Preparing fixed Robonix CLI/tool image..."
  bash "$PRIMITIVE_ROOT/scripts/verify-rbnx.sh" "$ROBONIX_SOURCE" \
    --package-root "$PRIMITIVE_ROOT" \
    --expected-commit "$EXPECTED_ROBONIX_COMMIT" --tool-image "$TOOL_IMAGE" \
    --target-cache "$TARGET_CACHE" --cargo-cache "$CARGO_CACHE" --config-cache "$CONFIG_CACHE"
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mirrorme-bpx-sdk-deploy.XXXXXX")"
MANIFEST="$TEMP_DIR/robonix_manifest.yaml"
LOG_DIR="$ROBOT_ROOT/rbnx-boot/logs"
mkdir -p "$LOG_DIR"

ENABLE_MOTION_SERVICE=false
MOTION_CONFIRMATION_VALUE=""
if ((MOTION_TEST)); then
  DEPLOYMENT_NAME="robonix.robot.mirrorme.bpx.motion_test.live"
  PRIMITIVE_NAME="mirrorme_bpx_motion"
  PACKAGE_MANIFEST="package_manifest.motion-test.yaml"
  SOMA_FILE="soma.motion-test.yaml"
  ALLOW_MOTION=true
  ENABLE_POSTURE_SERVICE=false
  ENABLE_MOTION_SERVICE=true
  POSTURE_CONFIRMATION_VALUE=""
  MOTION_CONFIRMATION_VALUE="I_UNDERSTAND_MOTION_TEST_CAN_MOVE_BPX"
  PROFILE_DESCRIPTION="BPX unreleased supervised motion-test Deployment (initially DISARMED)"
  START_DESCRIPTION="Atlas + Soma + BPX motion-test Primitive"
elif ((RELEASE_POSTURE)); then
  DEPLOYMENT_NAME="robonix.robot.mirrorme.bpx.release.live"
  PRIMITIVE_NAME="mirrorme_bpx"
  PACKAGE_MANIFEST="package_manifest.x86-docker.yaml"
  SOMA_FILE="soma.yaml"
  ALLOW_MOTION="true"
  ENABLE_POSTURE_SERVICE="true"
  POSTURE_CONFIRMATION_VALUE="$POSTURE_CONFIRMATION"
  PROFILE_DESCRIPTION="BPX SDK production odom + posture Deployment"
  START_DESCRIPTION="Atlas + Soma + BPX odom + stand/sit Primitive"
elif ((POSTURE_TEST)); then
  DEPLOYMENT_NAME="robonix.robot.mirrorme.bpx.posture_test.live"
  PRIMITIVE_NAME="mirrorme_bpx_posture"
  PACKAGE_MANIFEST="package_manifest.posture-test.yaml"
  SOMA_FILE="soma.posture-test.yaml"
  ALLOW_MOTION="true"
  ENABLE_POSTURE_SERVICE="true"
  POSTURE_CONFIRMATION_VALUE="$POSTURE_CONFIRMATION"
  PROFILE_DESCRIPTION="BPX SDK posture-test Deployment"
  START_DESCRIPTION="Atlas + Soma + BPX stand/sit posture-test Primitive"
else
  DEPLOYMENT_NAME="robonix.robot.mirrorme.bpx.sdk_read_only.live"
  PRIMITIVE_NAME="mirrorme_bpx_state"
  PACKAGE_MANIFEST="package_manifest.sdk-read-only.yaml"
  SOMA_FILE="soma.sdk-read-only.yaml"
  ALLOW_MOTION="false"
  ENABLE_POSTURE_SERVICE="false"
  POSTURE_CONFIRMATION_VALUE=""
  PROFILE_DESCRIPTION="BPX SDK read-only Deployment"
  START_DESCRIPTION="Atlas + Soma + BPX state-only Primitive"
fi

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if ((OUTER_STARTED)) && docker inspect "$OUTER_CONTAINER" >/dev/null 2>&1; then
    docker stop -t 30 "$OUTER_CONTAINER" >/dev/null 2>&1 || true
  fi
  if ((KEEP_MANIFEST)); then
    echo "Generated manifest kept at: $MANIFEST"
  else
    case "$TEMP_DIR" in
      "${TMPDIR:-/tmp}"/mirrorme-bpx-sdk-deploy.*)
        rm -rf -- "$TEMP_DIR"
        ;;
      *)
        echo "warning: refusing to remove unexpected temporary path: $TEMP_DIR" >&2
        ;;
    esac
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

[[ -z "$IMU_FRAME" || "$IMU_FRAME" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || die 'invalid IMU frame'
PUBLISH_IMU=false
[[ -z "$IMU_FRAME" ]] || PUBLISH_IMU=true
cat >"$MANIFEST" <<EOF
manifestVersion: 1
name: $DEPLOYMENT_NAME

env:
  ROS_DOMAIN_ID: "$ROS_DOMAIN_ID_VALUE"
  BPX_SDK_WHEEL: "\${BPX_SDK_WHEEL}"
  BPX_CONFIRM_PHYSICAL_POSTURE_SERVICE: "\${BPX_CONFIRM_PHYSICAL_POSTURE_SERVICE}"
  BPX_CONFIRM_PHYSICAL_MOTION_TEST: "\${BPX_CONFIRM_PHYSICAL_MOTION_TEST}"

system:
  atlas:
    listen: $ATLAS_LISTEN
  soma:
    listen: 127.0.0.1:50091
    robot_yaml: "$ROBOT_ROOT/$SOMA_FILE"

primitive:
  - name: $PRIMITIVE_NAME
    path: "$PRIMITIVE_ROOT"
    manifest: $PACKAGE_MANIFEST
    config:
      backend: sdk
      allow_motion: $ALLOW_MOTION
      enable_posture_service: $ENABLE_POSTURE_SERVICE
      enable_motion_service: $ENABLE_MOTION_SERVICE
      auto_arm_fake: false
      robot_ip: $ROBOT_IP
      robot_state_port: $ROBOT_STATE_PORT
      state_rate_hz: $STATE_RATE_HZ
      sdk_tcp_local_port: 0
      sdk_connect_timeout_s: $CONNECT_TIMEOUT_S
      sdk_poll_period_s: 0.05
      odom_topic: /odom
      joint_states_topic: /joint_states
      odom_frame: odom
      base_frame: base_link
      odom_rate_hz: $STATE_RATE_HZ.0
      publish_odom_tf: $PUBLISH_ODOM_TF
      publish_imu: $PUBLISH_IMU
      imu_frame: "$IMU_FRAME"
      state_timeout_s: 0.5

service: []
skill: []
EOF

echo "$PROFILE_DESCRIPTION"
echo "  robot:        $ROBOT_IP"
echo "  state UDP:    $ROBOT_STATE_PORT"
echo "  network:      $NETWORK_MODE"
if [[ "$NETWORK_MODE" == "bridge" ]]; then
  echo "  Atlas bridge: $DOCKER_HOST_ADDRESS:50051"
fi
echo "  ROS domain:   $ROS_DOMAIN_ID_VALUE"
echo "  SDK wheel:    $SDK_WHEEL"
echo "  manifest:     $MANIFEST"

if ((DRY_RUN)); then
  echo
  echo "Generated manifest:"
  sed -n '1,220p' "$MANIFEST"
  exit 0
fi

if docker inspect "$OUTER_CONTAINER" >/dev/null 2>&1; then
  die "outer Deployment container already exists: $OUTER_CONTAINER"
fi
if docker inspect "$PRIMITIVE_CONTAINER" >/dev/null 2>&1; then
  die "Primitive container already exists: $PRIMITIVE_CONTAINER"
fi

DOCKER_CLIENT="$(realpath "$(command -v docker)")"
DOCKER_RUN=(docker run --rm --name "$OUTER_CONTAINER" --network host)
if [[ -t 0 && -t 1 ]]; then
  DOCKER_RUN+=(-it)
fi
DOCKER_RUN+=(
  -v /var/run/docker.sock:/var/run/docker.sock
  -v "$DOCKER_CLIENT:/usr/local/bin/docker:ro"
  -v "$WORKSPACE:$WORKSPACE"
  -v "$ROBONIX_SOURCE:$ROBONIX_SOURCE:ro"
  -v "$SDK_WHEEL:$SDK_WHEEL:ro"
  -v "$TEMP_DIR:$TEMP_DIR"
  -v "$TARGET_CACHE:/target"
  -v "$CARGO_CACHE:/cargo"
  -v "$CONFIG_CACHE:/root/.robonix"
  -e CARGO_HOME=/cargo
  -e CARGO_TARGET_DIR=/target
  -e "ROBONIX_SOURCE=$ROBONIX_SOURCE"
  -e "ROBONIX_SOURCE_PATH=$ROBONIX_SOURCE"
  -e "RBNX_INVOCATION_CWD=$ROBOT_ROOT"
  -e ROBONIX_CODEGEN_BIN=/target/release/robonix-codegen
  -e "BPX_SDK_WHEEL=$SDK_WHEEL"
  -e "BPX_CONFIRM_PHYSICAL_POSTURE_SERVICE=$POSTURE_CONFIRMATION_VALUE"
  -e "BPX_CONFIRM_PHYSICAL_MOTION_TEST=$MOTION_CONFIRMATION_VALUE"
  -e "BPX_DOCKER_NETWORK_MODE=$NETWORK_MODE"
  -e "BPX_DOCKER_STATE_UDP_PORT=$ROBOT_STATE_PORT"
  -e "BPX_RBNX_IMAGE=$RUNTIME_IMAGE"
  -e "BPX_RBNX_CONTAINER=$PRIMITIVE_CONTAINER"
  -e "BPX_DEPLOYMENT_MANIFEST=$MANIFEST"
  -e "BPX_DEPLOYMENT_LOG_DIR=$LOG_DIR"
)
if [[ "$NETWORK_MODE" == "bridge" ]]; then
  DOCKER_RUN+=(-e "BPX_DOCKER_HOST_ADDRESS=$DOCKER_HOST_ADDRESS")
fi
DOCKER_RUN+=(
  -w "$ROBOT_ROOT"
  "$TOOL_IMAGE"
  bash -lc
  'export PATH="/target/release:$PATH"; /target/release/rbnx setup "$ROBONIX_SOURCE" >/dev/null; exec /target/release/rbnx boot -f "$BPX_DEPLOYMENT_MANIFEST" --log-dir "$BPX_DEPLOYMENT_LOG_DIR" --no-update-check -v'
)

echo
echo "Starting $START_DESCRIPTION. Press Ctrl-C to stop."
OUTER_STARTED=1
"${DOCKER_RUN[@]}"
