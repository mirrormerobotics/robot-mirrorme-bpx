# MirrorMe BPX Robonix Robot Deployment

当前统一入口为 **0.1.0-dev.3**：一个 SDK 会话提供 odom、posture、move、twist_in，
无需 arm。启动、标准 RPC 验证和故障恢复步骤见 [UNIFIED_TEST_GUIDE.md](UNIFIED_TEST_GUIDE.md)。
默认远端清单固定引用 Primitive v0.1.0-dev.3；`start-unified` 用于相邻本地源码部署。
版本范围及验收记录见 [RELEASE_NOTES.md](RELEASE_NOTES.md)。
下文 dev.2/`--release-posture` 的操作保留为旧姿态专用模式；不代表新版能力范围。


Safety-first Robot Deployment skeleton for the MirrorMe BPX quadruped.

Soma descriptions are selected per deployment profile. See
[M6_VALIDATION_2026-10-15.md](M6_VALIDATION_2026-10-15.md) for provider exports,
capability limits, and regeneration of the shared body descriptions.

For a fresh development machine without hardware, start with
[OFFLINE_DEVELOPMENT.md](OFFLINE_DEVELOPMENT.md). The offline verification
entry point records source versions, logs, and results for unit tests or the
complete fake/replay Docker workflow.

## 开发分支接手说明

当前两个仓库使用 `master` 或配套 `v0.1.0-dev.3` tag。请将
`primitive-mirrorme-bpx-quadruped-rbnx` 和 `robot-mirrorme-bpx` 放在相邻目录，
并同时检出配套版本。分支包含脚本命令行配置、分阶段 Odom 只读采集与离线比较，
以及默认 TF 容器名、缓存路径和同版本 SDK wheel 替换的修复。

先在 Primitive 仓库运行 `bash scripts/test.sh`，再按其 `SCRIPT_CLI.md` 准备
固定版本的 Robonix 工具、SDK wheel 和运行镜像。在 Robot 仓库运行
`python3 -m unittest discover -s tests -v`，准备完成后按下文进行 Docker 集成验证。
开发分支的完整真机部署使用 `scripts/start-sdk-read-only-docker.sh`，它引用相邻
Primitive 仓库的本地源码；默认 `robonix_manifest.yaml` 使用 `v0.1.0-dev.3`。

本次修复通过本地单元测试和隔离的命令行为验证。接手后需要复验真实 Docker
集成，并按 [HARDWARE_TEST_GUIDE.md 第 15 节](HARDWARE_TEST_GUIDE.md#15-世界坐标原点sdk-重连与整机重启验收)
补齐 Odom 启动原点、初始朝向、新 SDK 会话重连与整机断电重启的分阶段真机证据。
[HARDWARE_CHECKLIST.md](HARDWARE_CHECKLIST.md) 和 [ACCEPTANCE.md](ACCEPTANCE.md)
中的未完成项目继续待验收；历史验证记录不能代替本分支的复验结果。完成验收后
再更新发布版本、创建新的不可变 tag，并调整默认 Deployment 依赖。

`robonix_manifest.yaml` is the pre-release Catalog/default deployment. It
starts Atlas + Soma and fetches the unified odom/posture/move/twist Primitive from
immutable tag `v0.1.0-dev.3`. The external BPX SDK wheel and reachable hardware are required
for activation. Startup stays idle; explicit posture, move and Twist requests
control the robot, without a manual arm prerequisite.

The default manifest contains the complete pre-release Catalog metadata under
`catalog:` (`robonix.robot.mirrorme.bpx`, version `0.1.0-dev.3`,
BSD-3-Clause, and the public maintainer contact). Its dependency uses the public
MirrorMe repository plus the matching pre-release tag; local-path profiles are
retained only for development and replay validation.

The separate no-motion profile starts no hardware
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
systems. Its primitive, service, and skill lists are empty. `soma.no-motion.yaml` exposes
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

## SDK release and read-only profiles

The default `robonix_manifest.yaml` is the publishable, URL-and-tag-pinned
deployment. It selects `package_manifest.x86-docker.yaml`, publishes odom and
the exact `stand`/`sit` posture RPC, and uses one `MotionLevelControl` owner with
velocity mode disabled. `robonix_manifest.sdk-read-only.yaml` remains the local
state-only alternative and constructs `RequestRobotState` only. Neither profile
creates `twist_in`, gait, damping, joint control, or autonomous navigation.

The SDK wheel remains an external host artifact. Download the fixed CPython
3.10 Linux x86_64 artifact from the
[`v1.0.8` release](https://github.com/mirrormerobotics/bpx_sdk_open/releases/tag/v1.0.8),
verify its published SHA-256, and supply it by absolute path before booting:

```bash
bash scripts/start-sdk-read-only-docker.sh \
  --sdk-wheel /absolute/path/to/bpx_sdk_open-1.0.8-cp310-cp310-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl \
  --robot-ip 192.168.1.237 --release-posture \
  --confirm-physical-posture-service
```

For the local Docker workflow, the repository provides a single launcher that
generates an ephemeral hardware-specific manifest and starts Atlas, Soma and a
BPX SDK Primitive. It remains read-only unless posture mode is explicitly
selected; only the wheel and robot IP are required:

```bash
bash scripts/start-sdk-read-only-docker.sh \
  --sdk-wheel /absolute/path/to/bpx_sdk_open-1.0.8-cp310-cp310-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl \
  --robot-ip 192.168.1.237
```

`--network-mode auto` selects bridge mode on Docker Desktop and host mode on
native Linux. Bridge mode automatically publishes the configured state UDP
port and discovers the Docker bridge gateway used to reach Atlas. Use
`--dry-run` to validate the inputs and inspect the generated manifest without
starting any component. Run `--help` for optional port, rate, timeout, ROS
domain, image, container-name and fixed-Robonix-source overrides.

The launcher verifies the pinned wheel checksum and fixed Robonix commit. By
default it writes `backend=sdk`, `allow_motion=false` and the SDK read-only
package manifest. `--release-posture` plus
`--confirm-physical-posture-service` selects the production odom + posture
manifest; `--posture-test` selects the separate diagnostic identity. Neither
mode can select the fake motion-development identity or create `twist_in`.

The complete Chinese operator procedure, including preflight, optional raw SDK
capture, capability checks, `/odom`, `/joint_states`, Driver lifecycle and
shutdown cleanup, is in [HARDWARE_TEST_GUIDE.md](HARDWARE_TEST_GUIDE.md).
The separately authorized stand/hold/sit MotionLevelControl debug procedure is
in [POSTURE_TEST_GUIDE.md](POSTURE_TEST_GUIDE.md). The first hardware
state-loop result is in
[POSTURE_VALIDATION.md](POSTURE_VALIDATION.md).
The follow-up Robonix gRPC lifecycle/concurrency procedure is in
[POSTURE_SERVICE_TEST_GUIDE.md](POSTURE_SERVICE_TEST_GUIDE.md). It uses a
distinct hardware-test identity while also documenting the production option.
The first sequential hardware stand/sit RPC result is recorded in
[POSTURE_SERVICE_VALIDATION.md](POSTURE_SERVICE_VALIDATION.md); live lifecycle
interruption, concurrency, failure, and onsite evidence remain open.
The next operator-run, odometry-closed-loop in-place yaw test is documented in
[YAW_CIRCLE_TEST_GUIDE.md](YAW_CIRCLE_TEST_GUIDE.md). It is also standalone and
does not add `twist_in` to the Deployment.

The Primitive start wrapper verifies SHA-256
`23dec27cd4c90cfe5531fbccf5db15e44c5ec4d4b6d2a76941e61def957db115`,
mounts the wheel read-only into the runtime container, and installs it without
network access. Update `robot_ip` and the state connection settings in the
profile for the target robot. Activation waits at most 10 seconds for a fresh
odometry frame and fails closed otherwise.

The earlier dev.1 packaging and SDK import path were first validated without a
robot. With the default IP unreachable, that full boot declared only `odom`, timed out after the
configured 10 seconds, transitioned through `ERROR` to `TERMINATED`, and left
no container behind. The same check was repeated from a fresh public Robot clone
and fresh Robonix package cache: the then-default URL/tag dependency resolved
`v0.1.0-dev.1` to Primitive commit `0bba6e5` before following the same
fail-closed path.

The local SDK read-only profile has now also reached `ACTIVE` against a BPX at
temporary address `192.168.1.237`. Atlas exposed `odom` only, and independent
ROS 2 consumers received live `/odom` and 12-joint `/joint_states`. Driver
DEACTIVATE/ACTIVATE restored telemetry, and normal `rbnx shutdown` left no
Primitive container. See [HARDWARE_VALIDATION.md](HARDWARE_VALIDATION.md) for
the exact platform, rates, lifecycle evidence, and remaining physical checks.

On this Docker Desktop development host, robot UDP telemetry required bridge
mode with an explicit `9873:9873/udp` mapping. The test topology also exposed
Atlas to the local Docker bridge and set `BPX_DOCKER_HOST_ADDRESS` to that
bridge gateway. These are local development overrides; native Linux Docker
continues to use the normal host-network profile.

The next model milestone is limited to measured body dimensions and, if the IMU
ROS stream is retained, its physical frame/extrinsic. Navigation footprint and
external perception frames are out of scope.

Safety gates and future hardware evidence are tracked in [SAFETY.md](SAFETY.md),
[HARDWARE_CHECKLIST.md](HARDWARE_CHECKLIST.md),
[POSTURE_TEST_GUIDE.md](POSTURE_TEST_GUIDE.md),
[POSTURE_VALIDATION.md](POSTURE_VALIDATION.md),
[POSTURE_SERVICE_TEST_GUIDE.md](POSTURE_SERVICE_TEST_GUIDE.md),
[POSTURE_SERVICE_VALIDATION.md](POSTURE_SERVICE_VALIDATION.md),
[YAW_CIRCLE_TEST_GUIDE.md](YAW_CIRCLE_TEST_GUIDE.md),
[ACCEPTANCE.md](ACCEPTANCE.md), and [THIRD_PARTY.md](THIRD_PARTY.md).

## License

This Robot Deployment is licensed under the BSD 3-Clause License. See
[LICENSE](LICENSE). The vendored BPX model retains its own copy of the same
license and provenance under `description/bpx/`; the separately distributed
BPX SDK is licensed under Apache-2.0.

## 命令行参数

所有用户操作脚本均可用 `--help` 查看选项。
镜像、网络模式、容器名、缓存目录等参数见 [SCRIPT_CLI.md](SCRIPT_CLI.md)。
文档中的普通 Shell 变量仅用于复用路径，再显式传入命令；它们不是脚本的隐式配置。
## Unreleased motion development

Continuous velocity and bounded standard `move` are available in separate,
lifecycle-gated test profiles (no manual arm required). See [MOTION_TEST_GUIDE.md](MOTION_TEST_GUIDE.md)
for offline regression, operator commands, limits and pending hardware checks.
