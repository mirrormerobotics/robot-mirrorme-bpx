# Safe offline and read-only hardware validation record

Validation date: 2026-09-04

This document preserves the dev.1 validation baseline below. The dev.2 release
candidate advances the SDK contract to
`cab478a5fd3dfce087e0774534bb87b51a3d69e1`, uses cp310 x86_64 wheel SHA-256
`23dec27cd4c90cfe5531fbccf5db15e44c5ec4d4b6d2a76941e61def957db115`, and
adds only the hardware-validated `stand`/`sit` posture RPC beside odom. The
historical hashes and results remain unchanged rather than being attributed to
an artifact that was not used in those runs.

## Fixed inputs

- Robonix: `f6cacfc4b402eb57c75b553d375c6cfaba11dce7`
- BPX SDK contract: `19cb373a8d2f8e19eaab6a1441167f3287cc95dd`
- BPX model: `ea4f0013518dc7fe488a32706652a1d66a4d8bdd`
- ROS image: `ros:humble-ros-base@sha256:75dd3aba34a3838dadbb31a9f7bef769bdfa8713e6cec686fc868db2981b0987`
- Offline-boot profiles: `robonix_manifest.no-motion.yaml` and
  `robonix_manifest.fake-state.yaml`
- Automated read-only data-plane profile:
  `robonix_manifest.replay-state.yaml`
- Hardware profile used for both no-hardware fail-closed and bounded BPX validation:
  `robonix_manifest.sdk-read-only.yaml`
- Public default dependency: `mirrormerobotics/primitive-mirrorme-bpx-quadruped-rbnx`
  tag `v0.1.0-dev.1`, resolved to
  `0bba6e5f5c1fa0163449fb93a36c94ca6532c381`
- Product scope: body state and guarded body motion only; mapping,
  localization, and autonomous navigation are explicitly unsupported.

## Model verification

`bash scripts/verify-model.sh` passed:

- all 14 imported files matched `description/bpx/SHA256SUMS`;
- all URDF mesh references resolved inside the read-only vendored bundle;
- the byte-exact vendor model remained at 17 links and 16 joints with root
  `torso`;
- the deterministic deployment model contained 18 links and 17 joints, with
  `base_link` as a zero-offset fixed parent of `torso`;
- all 9 deployment-model regression tests passed;
- ROS 2 Humble `check_urdf` successfully parsed both trees and their four
  complete leg chains.

`bash scripts/verify-tf-smoke.sh` also passed in Docker. ROS 2 Humble
`robot_state_publisher` loaded the deployment model, a current-clock synthetic
state publisher supplied all 12 revolute joints at values inside their declared
limits, and `tf2_echo` resolved every body-to-foot chain:

```text
base_link -> fl_toe_link: OK
base_link -> fr_toe_link: OK
base_link -> hl_toe_link: OK
base_link -> hr_toe_link: OK
```

This test loaded neither the BPX SDK nor any motion command path.

## Robonix boot verification

The fixed Robonix baseline built `robonix-soma` and booted the no-motion
manifest. Startup reported:

```text
[ OK ]  atlas :50051
[ OK ]  soma  :50091
no primitive/skill packages declared
2 component(s) up
```

`rbnx caps -v` contained only the active `soma` provider with these contracts:

- `robonix/lifecycle/driver`
- `robonix/system/soma/get_yaml`
- `robonix/system/soma/get_urdf`
- `robonix/system/soma/footprint`
- `robonix/system/soma/get_health`
- `robonix/system/soma/health`

There was no BPX Primitive, vendor SDK session, command input, odometry
provider, service, or skill. SIGTERM triggered the Robonix shutdown path for
Soma and Atlas, and no labeled test container remained.

A direct call to Soma's running `get_urdf` contract returned the deployment
model rather than the vendor source artifact:

```text
robot_id=mirrorme_bpx, model=mirrorme_bpx, links=18, base_link=yes
```

## Fake-state JointState verification

The fake-state profile selected the distinct, non-release `motion_dev` package
identity and reached `ACTIVE` with the fake backend, motion disabled, and no
vendor SDK loaded. A separate ROS 2 Humble container received a live
`sensor_msgs/JointState` sample from `/joint_states` with:

- all 12 names in the pinned SDK `JointIndex` order;
- the bounded fake pose `(0.0, 0.5, -1.0)` repeated for four legs;
- 12 zero velocities;
- an empty effort array because the SDK torque unit is not yet confirmed;
- a non-zero local ROS clock timestamp.

`robot_state_publisher` then consumed the Primitive stream directly and all
four dynamic chains resolved:

```text
Primitive /joint_states -> base_link -> fl_toe_link: OK
Primitive /joint_states -> base_link -> fr_toe_link: OK
Primitive /joint_states -> base_link -> hl_toe_link: OK
Primitive /joint_states -> base_link -> hr_toe_link: OK
```

`rbnx caps -v` listed the quadruped `twist_in` and `odom` contracts only for
that development identity; `/joint_states` was not falsely advertised as a
Robonix capability. The production identity now omits `twist_in`. Driver
`CMD_SHUTDOWN` transitioned the Primitive from `ACTIVE` to `TERMINATED`, and no
labeled container remained.

After the unified runtime refactor, this profile was booted again. A separate
ROS 2 container received both `/odom` (`odom` -> `base_link`) and the 12-joint
stream, and the final image again reached `ACTIVE` before clean Driver
shutdown.

## SDK read-only packaging verification

The dev.1 Primitive suite passed 102 tests, including the unified runtime seam,
strict `backend=sdk` configuration, stale/cached frame suppression, the then
common odom-only surface of every release manifest, and isolation of fake Twist under
the separate `motion_dev` identity. This count also includes the isolated
stand/hold/sit state machine and narrow MotionLevelControl API checks; those are
offline tests, not a physical posture result. The runtime image then installed the
externally supplied wheel from a read-only bind mount
using `--no-index --no-deps` and reported:

```text
bpx_sdk 1.0.8 runtime ReadOnlyRuntime supports_twist False
```

The mounted wheel matched the pinned SHA-256. It was not copied into the source
repository or Docker image. No robot connection or motion API was used for this
packaging-only phase.

The complete SDK read-only deployment was also booted while `10.21.20.1` was
unreachable. Before activation, both the selected package manifest and live
Atlas declarations exposed `odom` only; `twist_in` was absent. Activation then
failed closed with:

```text
BPX state connection did not produce an odometry frame before timeout
```

The provider moved from `INACTIVE` to `ERROR` and `TERMINATED` after about the
configured 10-second wait. Soma failed the deployment instead of accepting a
state-less provider, Atlas shut down, and no Primitive or tool container
remained. This proves the bounded failure path, not hardware telemetry.

## BPX hardware read-only verification

The SDK-only probe and complete Robonix deployment were then tested against a
BPX at temporary WLAN address `192.168.1.237`. The probe received the first
odometry frame in 0.064--0.120 seconds and recorded 30 seconds of connected
leg odometry, IMU, 12-joint, temperature, motion-state, and battery data with
no disconnect or timestamp regression.

The integrated deployment reached ACTIVE with only
`robonix/primitive/quadruped/odom` plus the shared Driver declared for the BPX
provider. Live `/odom` and `/joint_states` samples were consumed, Driver
DEACTIVATE/ACTIVATE restored telemetry, and `rbnx shutdown` transitioned the
provider to TERMINATED without leaving a child container. Docker Desktop
required bridge networking and explicit UDP 9873 publication; native Linux
host networking remains a separate release-host check.

See [HARDWARE_VALIDATION.md](HARDWARE_VALIDATION.md) for measured per-field
rates, platform/network details, timestamp caveats, and the remaining physical
acceptance items.

## Historical dev.1 public default dependency verification

The public Robot repository was cloned into a new directory and its default
`robonix_manifest.yaml` was booted with a fresh Robonix package cache. Robonix
cloned the Primitive from its public GitHub URL, checked out tag
`v0.1.0-dev.1` in detached-HEAD state at
`0bba6e5f5c1fa0163449fb93a36c94ca6532c381`, ran code generation and built the
Docker image from that checkout.

Soma reported only `robonix/primitive/quadruped/odom`. The provider registered,
reached `INACTIVE`, then failed activation after the bounded 10-second wait
because `10.21.20.1` produced no odometry frame. Atlas recorded
`INACTIVE -> ERROR -> TERMINATED`, the deployment failed closed, Atlas and Soma
shut down, and no labeled Primitive container remained. This validates the
public URL/tag dependency and failure path; it is not evidence of hardware
telemetry.

## Normalized replay integration verification

The version-1 JSONL fixture was loaded behind the same `BpxStateSource` seam as
the SDK adapter. Its package manifest forced `backend=replay`, declared `odom`
only, and exposed no `twist_in` capability. A complete Dockerized Robonix boot
reached ACTIVE without loading the SDK or connecting to a robot.

The automated harness then called the live shared Driver contract:

```text
DEACTIVATE -> {"ok": true, "state": "inactive"}
ACTIVATE   -> {"ok": true, "state": "active"}
```

After reactivation, independent ROS 2 containers received `/odom`, the
12-joint `/joint_states` stream, and `odom -> base_link` on `/tf`. The harness
confirmed exactly one Odom publisher; its fake-profile pass additionally
confirmed exactly one Twist subscriber and observed rejection of a published
non-planar Twist. Shutdown invoked Driver `CMD_SHUTDOWN`, ran the package stop
hook, and left no container with the BPX package label. The same fixture also
passes the offline audit for schema, event gaps, timestamp monotonicity,
disconnect count and telemetry-field coverage.

## Not yet validated

- RViz visual/collision rendering;
- physical body dimensions;
- hardware confirmation of odometry axes, joint angle signs/zero positions and
  torque units;
- IMU, lidar, and camera frames/extrinsics;
- long-duration, cable-loss, robot-reboot, and native Ubuntu 22.04 host tests;
- the chassis-test and full-motion deployment profiles.

The isolated yaw-circle probe has offline/fake-clock coverage for the vendor
C++ example's core command order, positive/negative commanded directions,
opposite-direction rejection, interruption cleanup, translation and timeout
gates, but has not been run on physical hardware. See
`YAW_CIRCLE_TEST_GUIDE.md`.
