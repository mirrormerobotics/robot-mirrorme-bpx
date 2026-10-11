#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_DIR="$ROOT/description/bpx"
ROS_IMAGE="ros:humble-ros-base@sha256:75dd3aba34a3838dadbb31a9f7bef769bdfa8713e6cec686fc868db2981b0987"
source "$(dirname "${BASH_SOURCE[0]}")/lib/cli.sh"
cli_init 'bash scripts/verify-model.sh [options]'
cli_option --image ROS_IMAGE 'ROS check_urdf image'
cli_parse "$@"
cli_no_args
VENDOR_URDF="$MODEL_DIR/urdf/bpx.urdf"
DEPLOYMENT_URDF="$ROOT/urdf/mirrorme_bpx.urdf"

(
  cd "$MODEL_DIR"
  sha256sum --check SHA256SUMS
)

while IFS= read -r mesh_path; do
  [[ "$mesh_path" == ../meshes/* ]] || {
    echo "unexpected mesh URI in vendor URDF: $mesh_path" >&2
    exit 1
  }
  [[ -f "$MODEL_DIR/urdf/$mesh_path" ]] || {
    echo "missing mesh referenced by vendor URDF: $mesh_path" >&2
    exit 1
  }
done < <(sed -n 's/.*<mesh filename="\([^"]*\)".*/\1/p' "$VENDOR_URDF")

python3 "$ROOT/scripts/generate_deployment_urdf.py" --check
python3 -m unittest discover -s "$ROOT/tests" -v

while IFS= read -r mesh_path; do
  [[ "$mesh_path" == ../description/bpx/meshes/* ]] || {
    echo "unexpected mesh URI in deployment URDF: $mesh_path" >&2
    exit 1
  }
  [[ -f "$ROOT/urdf/$mesh_path" ]] || {
    echo "missing mesh referenced by deployment URDF: $mesh_path" >&2
    exit 1
  }
done < <(sed -n 's/.*<mesh filename="\([^"]*\)".*/\1/p' "$DEPLOYMENT_URDF")

vendor_link_count="$(grep -c '<link name=' "$VENDOR_URDF")"
vendor_joint_count="$(grep -c '<joint name=' "$VENDOR_URDF")"
deployment_link_count="$(grep -c '<link name=' "$DEPLOYMENT_URDF")"
deployment_joint_count="$(grep -c '<joint name=' "$DEPLOYMENT_URDF")"
[[ "$vendor_link_count" == "17" ]] || {
  echo "expected 17 vendor links, found $vendor_link_count" >&2
  exit 1
}
[[ "$vendor_joint_count" == "16" ]] || {
  echo "expected 16 vendor joints, found $vendor_joint_count" >&2
  exit 1
}
[[ "$deployment_link_count" == "18" ]] || {
  echo "expected 18 deployment links, found $deployment_link_count" >&2
  exit 1
}
[[ "$deployment_joint_count" == "17" ]] || {
  echo "expected 17 deployment joints, found $deployment_joint_count" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || {
  echo "docker is required for ROS check_urdf validation" >&2
  exit 1
}

docker run --rm \
  --entrypoint /bin/bash \
  -v "$ROOT:/deploy:ro" \
  "$ROS_IMAGE" \
  -c 'source /opt/ros/humble/setup.bash && check_urdf /deploy/description/bpx/urdf/bpx.urdf && check_urdf /deploy/urdf/mirrorme_bpx.urdf'
