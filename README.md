# MirrorMe BPX Robonix Robot Deployment

Safety-first Robot Deployment skeleton for the MirrorMe BPX quadruped.

`robonix_manifest.yaml` is the pre-release Catalog/default deployment. It
starts Atlas + Soma and fetches the odom-only Primitive from immutable tag
`v0.1.0-dev.1`. The external BPX SDK wheel and reachable hardware are required
for activation; no actuator command capability is present.

The default manifest contains the complete pre-release Catalog metadata under
`catalog:` (`robonix.robot.mirrorme.bpx`, version `0.1.0-dev.1`,
BSD-3-Clause, and the public maintainer contact). Its dependency uses the public
MirrorMe repository plus the matching pre-release tag; local-path profiles are
retained only for development and replay validation.

The primary profile is deliberately **no-motion**. It starts no hardware
Primitive and contains no SDK session, velocity command path, or guessed sensor
extrinsics. Its purpose is to make the vendor body model
auditable and available to Soma before hardware control is introduced.

BPX does not support mapping, localization, or autonomous navigation. This
deployment intentionally contains no Mapping/Nav2/RTAB-Map packages, lidar or
camera navigation primitives, costmaps, behavior trees, or navigation claims.
Odometry remains a body-state and bounded-motion feedback signal only.

## Pinned model baseline

- Repository: <https://github.com/mirrormerobotics/BPX>
- Commit: `ea4f0013518dc7fe488a32706652a1d66a4d8bdd`
- License: BSD-3-Clause
- Imported files: the upstream `bpx/urdf/` and `bpx/meshes/` trees plus its
  repository-level license

See [`description/bpx/SOURCE.md`](description/bpx/SOURCE.md) and
[`description/bpx/SHA256SUMS`](description/bpx/SHA256SUMS) for provenance and
per-file integrity data.

## Verify the model

The verifier checks every imported checksum, rejects unexpected mesh URI
shapes, confirms both the vendor and deployment topology, and runs ROS 2 Humble
`check_urdf` for both URDFs inside an immutable Docker image:

```bash
bash scripts/verify-model.sh
bash scripts/verify-tf-smoke.sh
```

The TF smoke test starts `robot_state_publisher` in Docker, publishes a bounded
synthetic 12-joint pose, and resolves `base_link` to all four toe links. It does
not load the BPX SDK or send a robot command.

## No-motion profile

`robonix_manifest.no-motion.yaml` contains only the built-in Atlas and Soma
systems. Its primitive, service, and skill lists are empty. `soma.yaml` exposes
the pinned body description but intentionally does not claim a motion provider,
overall dimensions, or sensor frames that have not yet been measured.

With `rbnx` configured against the fixed Robonix source baseline:

```bash
rbnx boot -f robonix_manifest.no-motion.yaml --no-update-check -v
```

The verified result contains exactly two running components, Atlas and Soma.
`rbnx caps -v` reports only Soma's lifecycle, body-description, and health
contracts; no BPX Primitive or motion capability is registered. See
[`VALIDATION.md`](VALIDATION.md) for the recorded evidence.

Soma's live `get_urdf` contract has also been checked to return the 18-link
deployment model rooted at `base_link`.

## Fake-state profile

`robonix_manifest.fake-state.yaml` starts Atlas, Soma, and the BPX Primitive
with `backend=fake`, `allow_motion=false`, and automatic arm disabled. It
explicitly selects the distinct
`robonix.primitive.mirrorme.bpx.quadruped.motion_dev` package identity. It is an
offline development profile, not a Catalog release dependency: it never loads
the vendor SDK or connects to a robot.

```bash
rbnx boot -f robonix_manifest.fake-state.yaml --no-update-check -v
```

The verified profile publishes `/joint_states` with all 12 official BPX joint
names. ROS 2 `robot_state_publisher` consumed that stream and resolved
`base_link` to all four toe links. The topic remains internal and does not add
an unsupported Robonix capability to Atlas.

The deployment URDF is deterministically generated from the byte-exact vendor
URDF. It adds `base_link` as a zero-offset fixed parent of `torso` and rewrites
only mesh paths for the deployment layout. Regenerate and verify it with:

```bash
python3 scripts/generate_deployment_urdf.py
python3 scripts/generate_deployment_urdf.py --check
```

## Replay-state profile

`robonix_manifest.replay-state.yaml` uses a versioned normalized JSONL fixture
behind the same `BpxStateSource` interface as the SDK adapter. It is read-only,
requires no wheel, and declares only `odom` to Atlas.

The automated integration harness boots the fixed Robonix baseline through
Docker, checks capabilities, sends Driver DEACTIVATE then ACTIVATE, receives
`/odom`, `/joint_states` and `odom -> base_link`, checks publisher/subscriber
uniqueness, and verifies no Primitive container remains:

```bash
bash scripts/test-offline-integration.sh /path/to/fixed/robonix replay
```

## SDK read-only profile

The default `robonix_manifest.yaml` is the publishable, URL-and-tag-pinned form
of the read-only deployment. `robonix_manifest.sdk-read-only.yaml` is the local
workspace equivalent used while developing both sibling repositories. Both
start the BPX Primitive with `backend=sdk` and `allow_motion=false`. The default
selects `package_manifest.x86-docker.yaml`; the local profile selects
`package_manifest.sdk-read-only.yaml`. Both manifests expose the same `odom`-only
package identity, so no `twist_in` subscription, motion controller, joint
controller, or arm path is created. The manifest/backend pairing is enforced at
runtime and fails initialization if it is misconfigured.

The SDK wheel remains an external host artifact. Supply the pinned v1.0.8 wheel
by absolute path before booting:

```bash
export BPX_SDK_WHEEL=/absolute/path/to/bpx_sdk_open-1.0.8-cp310-cp310-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl
rbnx boot -f robonix_manifest.yaml --no-update-check -v
```

The Primitive start wrapper verifies SHA-256
`6a0bcb708c55605dfbfeead6c84141f474505f1c01efbdb564e3dfa4549889c7`,
mounts the wheel read-only into the runtime container, and installs it without
network access. Update `robot_ip` and the state connection settings in the
profile for the target robot. Activation waits at most 10 seconds for a fresh
odometry frame and fails closed otherwise.

The packaging and SDK import path have been validated without a robot. With the
default IP unreachable, a full boot declared only `odom`, timed out after the
configured 10 seconds, transitioned through `ERROR` to `TERMINATED`, and left
no container behind. The profile has not yet produced telemetry from BPX
hardware; that step requires a safe test area, confirmed robot IP/firmware, and
hardware-team approval.

The next model milestone is limited to measured body dimensions and, if the IMU
ROS stream is retained, its physical frame/extrinsic. Navigation footprint and
external perception frames are out of scope.

Safety gates and future hardware evidence are tracked in [SAFETY.md](SAFETY.md),
[HARDWARE_CHECKLIST.md](HARDWARE_CHECKLIST.md),
[ACCEPTANCE.md](ACCEPTANCE.md), and [THIRD_PARTY.md](THIRD_PARTY.md).

## License

This Robot Deployment is licensed under the BSD 3-Clause License. See
[LICENSE](LICENSE). The vendored BPX model retains its own copy of the same
license and provenance under `description/bpx/`; the separately distributed
BPX SDK is licensed under Apache-2.0.
