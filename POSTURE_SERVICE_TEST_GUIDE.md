# BPX Robonix posture 服务真机测试

本文验证 `v0.1.0-dev.2` 正式发布身份中的
`robonix/primitive/quadruped/posture` 服务。发布面只增加精确的 `stand`、`sit`
白名单；仍明确排除 `twist_in`、`move`、步态、阻尼、zero-position 和
`JointLevelControl`。该 profile 只创建一个 `MotionLevelControl` owner，且明确
不创建 `JointLevelControl`。

该流程会让真机运动。必须由现场操作员手动执行，不得作为无人值守测试或 CI。

## 1. 前置条件

- 机器人为 `LyingDown(0)` 或已经稳定处于 `Motion(6)`；
- 测试区无人员、线缆、台阶或其他障碍，机器狗四周留出意外移动空间；
- 现场操作员全程掌握物理急停；
- App、遥控器及其他 SDK 客户端均已退出；
- 没有 stand/sit probe、yaw-circle probe 或另一个 BPX Deployment；
- 使用固定 SHA-256 的 BPX SDK v1.0.8 x86_64 wheel。

## 2. 预览正式发布身份

```bash
cd /root/workspace/c2/robonix_adapt/robot-mirrorme-bpx

BPX_WHEEL=/absolute/path/to/bpx_sdk_open-1.0.8-cp310-cp310-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl

bash scripts/start-sdk-read-only-docker.sh \
  --sdk-wheel "$BPX_WHEEL" \
  --robot-ip 192.168.1.237 \
  --network-mode bridge \
  --release-posture \
  --confirm-physical-posture-service \
  --dry-run
```

生成内容必须同时满足：

- `manifest: package_manifest.x86-docker.yaml`；
- `allow_motion: true`；
- `enable_posture_service: true`；
- Primitive 实例名为 `mirrorme_bpx`；
- 没有 `twist_in` 或 `move`。

`--dry-run` 只校验输入并打印临时 YAML，不启动 Atlas、Primitive 或 SDK session。

## 3. 启动正式发布身份

在终端 A 执行：

```bash
cd /root/workspace/c2/robonix_adapt/robot-mirrorme-bpx

bash scripts/start-sdk-read-only-docker.sh \
  --sdk-wheel "$BPX_WHEEL" \
  --robot-ip 192.168.1.237 \
  --robot-state-port 9873 \
  --network-mode bridge \
  --release-posture \
  --confirm-physical-posture-service
```

`--network-mode bridge` 用于当前 Docker Desktop 环境；原生 Ubuntu Linux 可改为
`--network-mode host`。启动器会把固定的本地确认值传给 Primitive；缺少任一姿态
参数时都会在启动前拒绝。

机器人连接成功、首帧 odom 新鲜且 motion state 为 `LyingDown(0)` 或 `Motion(6)`
时，Primitive 才能达到 `ACTIVE`。激活本身不发送站立或趴下命令；其他 motion
state 会导致激活失败并断开 SDK。

## 4. 查看能力

保持终端 A 运行，在终端 B 执行：

```bash
docker exec rbnx_mirrorme_bpx_sdk \
  /target/release/rbnx caps -v --server 127.0.0.1:50051
```

`mirrorme_bpx` 应处于 `ACTIVE`，并且只包含：

- `robonix/primitive/quadruped/odom`；
- `robonix/primitive/quadruped/posture`；
- lifecycle Driver。

不得看到 `quadruped/twist_in`、`quadruped/move` 或关节控制能力。

## 5. 手动调用 stand 和 sit

操作员确认急停和现场状态后，在终端 B 执行：

```bash
bash scripts/call-posture-test.sh stand
bash scripts/call-posture-test.sh sit
```

成功结果应分别包含 `standing confirmed: Motion(6)` 和
`sitting confirmed: LyingDown(0)`，provider 为 `mirrorme_bpx`。客户端和服务端都只
接受小写 `stand`、`sit`。同时到达的第二个 RPC 会返回
`another posture operation is in progress`。重复请求已经到达的姿态会成功返回，
但不会再次发送动作命令。

## 6. 停止和异常行为

应先明确调用 `sit` 并确认回到 `LyingDown(0)`，再在终端 A 按 `Ctrl-C`。Driver
deactivate/shutdown 不会隐式改变机器人姿态；它只关闭 velocity flag、停止状态会话
并断开唯一的 `MotionLevelControl` owner。这样生命周期操作不会偷偷触发身体运动。

随后检查：

```bash
docker ps -a --filter name=rbnx_mirrorme_bpx_sdk
docker ps -a --filter name=rbnx_mirrorme_bpx_quadruped
ss -lunp | rg ':9873\\b' || true
```

不得遗留上述容器或 UDP 9873 占用。保存终端 A/B 日志、现场观察和急停/异常结果。

## 7. 保留的诊断身份

需要复现旧的隔离测试身份时，可把 `--release-posture` 改为 `--posture-test`，并用：

```bash
bash scripts/call-posture-test.sh stand mirrorme_bpx_posture
bash scripts/call-posture-test.sh sit mirrorme_bpx_posture
```

该身份使用 `package_manifest.posture-test.yaml` 和 provider
`mirrorme_bpx_posture`。测试身份不得提交 Catalog；Catalog 只引用
`v0.1.0-dev.2` 的正式发布身份 `mirrorme_bpx`。

首次顺序 stand/sit RPC 真机结果见
[POSTURE_SERVICE_VALIDATION.md](POSTURE_SERVICE_VALIDATION.md)。
