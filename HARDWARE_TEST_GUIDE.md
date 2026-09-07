# BPX SDK read-only 真机验证指南

本文用于在 x86_64 主机上人工验证 MirrorMe BPX 的 Robonix SDK read-only
Deployment。当前验证范围仅包含状态读取、ROS 2 数据、Robonix 能力声明、生命周期
和停机清理，不包含站立、行走、关节控制、建图或导航。

验证结果记录模板见 [HARDWARE_CHECKLIST.md](HARDWARE_CHECKLIST.md)，已有验证证据见
[HARDWARE_VALIDATION.md](HARDWARE_VALIDATION.md)，安全边界见
[SAFETY.md](SAFETY.md)。

## 1. 安全边界

SDK read-only profile：

- 只构造厂商 `RequestRobotState`；
- 不构造 `MotionLevelControl` 或 `JointLevelControl`；
- 不调用 `setZeroPositionsFlag()`；
- 不声明 `twist_in`、posture、move 或任何关节控制能力；
- 不提供 arm 或执行器命令入口。

这里的 read-only 是指没有执行器和运动命令接口，不表示网络协议完全没有出站
数据。`RequestRobotState.connect()` 仍会配置状态上传参数，并执行 SDK 内置的机器人
时间同步握手。

即使本 profile 不控制运动，测试前仍应确认机器人机械状态正常、周围无人、操作员
可接触物理急停，且没有其他 SDK/App 任务同时占用同一状态会话或 UDP 端口。若出现
任何意外运动，应立即停止测试并作为安全事件处理。

## 2. 前置条件

默认目录结构：

```text
/root/workspace/c2/robonix_adapt/
├── primitive-mirrorme-bpx-quadruped-rbnx/
└── robot-mirrorme-bpx/
```

需要：

- 可用的 Docker Engine；
- x86_64 BPX SDK v1.0.8 wheel；
- 固定 Robonix checkout，默认 `/tmp/robonix_dev_next`；
- 测试主机能够到达机器人 IP；
- UDP 状态端口可用，默认 `9873`。

本文示例使用：

```bash
export BPX_WHEEL=/root/workspace/c2/bpx_sdk_open/main/wheelhouse/bpx_sdk_open-1.0.8-cp310-cp310-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl
export BPX_ROBOT_IP=192.168.1.237
export BPX_STATE_PORT=9873
export BPX_ROBOT_ROOT=/root/workspace/c2/robonix_adapt/robot-mirrorme-bpx
export BPX_PRIMITIVE_ROOT=/root/workspace/c2/robonix_adapt/primitive-mirrorme-bpx-quadruped-rbnx
export BPX_ROBONIX_SOURCE=/tmp/robonix_dev_next
```

如果真机 IP、wheel 或 Robonix checkout 不同，应替换对应值。不要把临时 IP 或
本地 wheel 路径提交到发布清单。

## 3. 主机和网络预检

确认架构、Docker 和固定 Robonix 版本：

```bash
uname -m
docker info --format '{{.OperatingSystem}} / {{.Architecture}}'
git -C "$BPX_ROBONIX_SOURCE" rev-parse HEAD
sha256sum "$BPX_WHEEL"
```

当前固定值应为：

```text
Robonix: f6cacfc4b402eb57c75b553d375c6cfaba11dce7
wheel:   23dec27cd4c90cfe5531fbccf5db15e44c5ec4d4b6d2a76941e61def957db115
```

确认机器人可达、UDP 端口未被占用，并且没有遗留 Deployment：

```bash
ping -c 3 "$BPX_ROBOT_IP"
ss -lunp | rg ":${BPX_STATE_PORT}\\b" || true
docker ps -a --filter name=rbnx_mirrorme_bpx
```

`ss` 没有输出表示端口当前未被占用。若存在旧的 BPX Deployment 容器，应先确认
其用途并正常停止，不要启动第二个状态会话覆盖它。

## 4. 预览将要启动的 Deployment

进入 Robot 仓库后执行 dry-run：

```bash
cd "$BPX_ROBOT_ROOT"

bash scripts/start-sdk-read-only-docker.sh \
  --sdk-wheel "$BPX_WHEEL" \
  --robot-ip "$BPX_ROBOT_IP" \
  --robot-state-port "$BPX_STATE_PORT" \
  --dry-run
```

此命令不会连接机器人或启动容器。检查输出中至少包含：

```yaml
system:
  atlas:
    listen: 0.0.0.0:50051
  soma:
    listen: 127.0.0.1:50091
primitive:
  - name: mirrorme_bpx_state
    manifest: package_manifest.sdk-read-only.yaml
    config:
      backend: sdk
      allow_motion: false
      robot_ip: 192.168.1.237
```

上面的 Atlas listen 值是 Docker Desktop bridge 示例；原生 Linux host 模式会使用
`127.0.0.1:50051`。Docker Desktop 应自动选择 `network: bridge` 并显示 Docker
bridge gateway；原生 Linux Docker 应自动选择 `network: host`。如自动检测不适合
现场网络，可显式使用 `--network-mode bridge` 或 `--network-mode host`。

## 5. 可选：先做独立 SDK 只读探针

完整 Deployment 必须保持停止，否则会与探针争用 UDP 端口。

Docker Desktop：

```bash
cd "$BPX_PRIMITIVE_ROOT"

BPX_DOCKER_NETWORK_MODE=bridge \
  bash scripts/run-read-only-probe.sh "$BPX_WHEEL" \
    --robot-ip "$BPX_ROBOT_IP" \
    --robot-state-port "$BPX_STATE_PORT" \
    --state-rate-hz 10 \
    --duration-s 10 \
    --sample-period-s 0.1
```

原生 Linux Docker 将 `BPX_DOCKER_NETWORK_MODE` 改成 `host`，或直接省略该变量。

正常结果应满足：

- `connected` 为 `true`；
- 出现 `leg_odometry`；
- Odom timestamp 持续变化；
- 四元数均为有限值，norm 接近 1；
- 静止时速度接近 0，允许有少量传感器噪声；
- 进程在指定时长后自行退出并断开状态会话。

## 6. 可选：录制并审计 30 秒状态

输出文件不能已存在：

```bash
mkdir -p "$BPX_PRIMITIVE_ROOT/.artifacts/hardware/manual"

BPX_DOCKER_NETWORK_MODE=bridge \
  bash "$BPX_PRIMITIVE_ROOT/scripts/record-sdk-replay.sh" \
    "$BPX_WHEEL" \
    "$BPX_PRIMITIVE_ROOT/.artifacts/hardware/manual/bpx-odom-test-01.jsonl" \
    --robot-ip "$BPX_ROBOT_IP" \
    --robot-state-port "$BPX_STATE_PORT" \
    --state-rate-hz 10 \
    --duration-s 30 \
    --sample-period-s 0.01
```

脚本可能打印：

```text
recorded N state events to /capture/bpx-odom-test-01.jsonl
```

`/capture` 是容器内挂载点；实际宿主机文件仍是命令中传入的
`$BPX_PRIMITIVE_ROOT/.artifacts/hardware/manual/bpx-odom-test-01.jsonl`。
`N` 是连接状态、Odom timestamp 和关节 timestamp 变化组成的归一化状态事件数，
不是严格等于 Odom 帧数。

审计结果重点检查：

- `disconnect_event_count` 为 0；
- `odometry_timestamp_regression_count` 为 0；
- `estimated_missing_odometry_frames` 为 0 或有合理解释；
- Odom timestamp count 持续增加；
- 最大事件间隔没有异常长时间停顿。

## 7. 启动完整 SDK read-only Deployment

在第一个终端执行：

```bash
cd "$BPX_ROBOT_ROOT"

bash scripts/start-sdk-read-only-docker.sh \
  --sdk-wheel "$BPX_WHEEL" \
  --robot-ip "$BPX_ROBOT_IP" \
  --robot-state-port "$BPX_STATE_PORT"
```

该终端保持运行。脚本会自动：

- 校验 wheel SHA-256 和固定 Robonix commit；
- 生成临时、motion-disabled Deployment manifest；
- 启动 Atlas、Soma 和 BPX Primitive；
- 为 Docker Desktop 配置 bridge、UDP 映射和 Atlas gateway；
- 为原生 Linux Docker 使用 host 网络；
- 在退出时停止容器并删除临时 manifest。

正常启动应看到：

```text
[ OK ]  atlas
[ OK ]  soma
[ OK ]  mirrorme_bpx_state  ACTIVE
all components up — waiting for signal
```

如果 10 秒内没有新鲜 Odom，Primitive 应 fail-closed，而不是保持伪 ACTIVE。

## 8. 检查 Robonix 能力

在第二个终端执行：

```bash
docker exec rbnx_mirrorme_bpx_sdk \
  /target/release/rbnx caps -v
```

必须看到：

```text
mirrorme_bpx_state [ACTIVE]
robonix/lifecycle/driver
robonix/primitive/quadruped/odom
```

不得看到 `quadruped/twist_in`、posture、move、joint control、mapping 或 navigation。

## 9. 检查 `/odom`

读取一帧：

```bash
docker exec rbnx_mirrorme_bpx_quadruped bash -lc \
  'source /opt/ros/humble/setup.bash && \
   timeout 15 ros2 topic echo /odom nav_msgs/msg/Odometry \
     --once --qos-reliability best_effort'
```

持续查看，按 Ctrl-C 停止：

```bash
docker exec -it rbnx_mirrorme_bpx_quadruped bash -lc \
  'source /opt/ros/humble/setup.bash && \
   ros2 topic echo /odom nav_msgs/msg/Odometry \
     --qos-reliability best_effort'
```

查看频率：

```bash
docker exec -it rbnx_mirrorme_bpx_quadruped bash -lc \
  'source /opt/ros/humble/setup.bash && ros2 topic hz /odom'
```

检查发布者和 QoS：

```bash
docker exec rbnx_mirrorme_bpx_quadruped bash -lc \
  'source /opt/ros/humble/setup.bash && ros2 topic info /odom --verbose'
```

应确认：

- `Publisher count: 1`；
- `frame_id` 为 `odom`；
- `child_frame_id` 为 `base_link`；
- `header.stamp` 持续增加，没有回退；
- position、orientation、linear velocity 和 angular velocity 都是有限值；
- 四元数 norm 接近 1；
- 静止时速度接近 0，少量非零噪声正常。

当前 covariance 暂时为全零，属于待补数据来源的已知限制，不能解释为测量完全无
误差。仅观察静止数据也不能确认 Odom 的物理轴向、原点或精度。

## 10. 检查 `/joint_states`

```bash
docker exec rbnx_mirrorme_bpx_quadruped bash -lc \
  'source /opt/ros/humble/setup.bash && \
   timeout 15 ros2 topic echo /joint_states sensor_msgs/msg/JointState \
     --once --qos-reliability best_effort'
```

应确认：

- 共有 12 个官方 BPX 关节名；
- `position` 和 `velocity` 都有 12 项；
- 所有值为有限数；
- `effort` 当前有意保持为空。

仅靠消息维度不能确认实际关节零位和正方向；这些仍需对照真机姿态逐轴验证。

## 11. 可选：检查 Driver deactivate/activate

保持完整 Deployment 运行，在第二个终端重新设置第 2 节的路径变量，然后定义辅助
函数：

```bash
bpx_driver() {
  docker run --rm --network host \
    -e ROBONIX_ATLAS=127.0.0.1:50051 \
    -e PYTHONPATH=/pkg/rbnx-build/codegen/proto_gen \
    -v "$BPX_PRIMITIVE_ROOT:/pkg" \
    -v "$BPX_ROBOT_ROOT:/robot:ro" \
    -v "$BPX_ROBONIX_SOURCE/pylib/robonix-api:/robonix-api:ro" \
    primitive-mirrorme-bpx-quadruped-rbnx:dev \
    python3 /robot/scripts/call_driver.py \
      mirrorme_bpx_state "$1"
}
```

切换到 INACTIVE：

```bash
bpx_driver deactivate
```

期望输出包含：

```json
{"error": "", "ok": true, "state": "inactive"}
```

重新激活：

```bash
bpx_driver activate
```

期望 state 为 `active`，并再次执行第 9 节的一帧 `/odom` 命令，确认遥测恢复。
不要在此步骤调用 `shutdown`；完整 Deployment 统一按下一节正常停止。

## 12. 停止和清理检查

回到启动 Deployment 的第一个终端，按 Ctrl-C。正常日志应包含：

```text
shutdown signal received
Driver(CMD_SHUTDOWN)
StateActive -> StateTerminated
```

在第二个终端确认没有遗留容器：

```bash
docker ps -a --filter name=rbnx_mirrorme_bpx
```

正常情况下不应剩余：

- `rbnx_mirrorme_bpx_sdk`；
- `rbnx_mirrorme_bpx_quadruped`。

确认 UDP 端口已经释放：

```bash
ss -lunp | rg ":${BPX_STATE_PORT}\\b" || true
```

组件日志保存在：

```text
robot-mirrorme-bpx/rbnx-boot/logs/
```

## 13. 最小通过条件

本轮功能链路验证只有在以下条件全部满足时才算通过：

- SDK wheel 和 Robonix commit 校验通过；
- 机器人可达且能收到第一帧 Odom；
- Atlas、Soma 和 `mirrorme_bpx_state` 达到 ACTIVE；
- Robonix 只有 `odom`，没有任何运动能力；
- `/odom` 只有一个 publisher，frame 正确，时间戳递增；
- `/joint_states` 包含 12 个关节；
- deactivate/activate 后遥测可恢复（若执行生命周期检查）；
- 正常停止后没有遗留容器和 UDP 端口；
- 全程未出现运动控制对象、运动命令或意外动作。

这份通过结果只证明 read-only 软件数据链路可用，不代表以下事项已通过：Odom
物理坐标约定、里程计精度、关节零位/方向、IMU 外参、协方差、长时间稳定性、断网/
重启恢复、原生 Ubuntu 22.04 生产主机或任何运动能力。

## 14. 常见问题

### 一直收不到 Odom

依次检查机器人 IP、路由、UDP 端口、防火墙和是否存在第二个 SDK 状态客户端。
Docker Desktop 必须使用 bridge + 显式 UDP 映射；一键脚本的 `auto` 会自动选择。

### 打印路径是 `/capture/...`

这是 recorder 容器内路径，不是文件丢失。宿主机文件位于调用
`record-sdk-replay.sh` 时传入的第二个参数。

### 30 秒记录数不是 300

记录数是归一化状态事件数，不是严格 Odom 帧数。Odom、关节和连接状态可能异步
变化，应以 audit 中的 Odom timestamp、回退、估算丢帧和断连统计为准。

### `container already exists`

脚本会拒绝覆盖未知或正在使用的 Deployment。先使用 `docker ps -a` 查明容器来源，
再对属于本次测试的旧 Deployment 做正常停止。

### 宿主机 `rbnx` 缺少 `libssl.so.3`

不需要在宿主机直接运行 `rbnx`。`start-sdk-read-only-docker.sh` 使用固定工具镜像和
缓存中的 Robonix CLI。
