# BPX 站立/原地一圈/停止/趴下手动测试指南

本指南用于操作者手动验证 BPX SDK v1.0.8 `MotionLevelControl` 的 yaw 速度控制。
脚本不会由任何 Robonix manifest 自动启动，也不代表已经接入或发布 `twist_in`。
执行流程是：

```text
LyingDown(0) -> setStandUp -> Motion(6)
-> setVelocity(0, 0, yaw)，LegOdom 沿命令方向累计 yaw 达到 2*pi
-> setVelocity(0, 0, 0) -> 关闭 velocity flag -> 零速度 flush 2 秒
-> setSitDown -> LyingDown(0)
```

## 与厂商示例的关系

实现参考：
`/root/workspace/c2/bpx_sdk_open_out/master/example/motion_level_control_example.cpp`。
该示例当前使用 `yaw=1.0 rad/s` 持续 3 秒，理论角度约 3 rad，并非完整一圈。
本脚本保留其启用速度、周期发送、零速度、关闭速度模式和趴下顺序，但改为根据
LegOdom 四元数沿命令方向累计 yaw，达到 `2*pi` 后停止。离线回归测试另外使用
C++ 示例的 `1.0 rad/s`、`3 rad` 名义旋转阶段，锁定跨接口顺序：站立确认、开启
速度控制、非零 yaw、零 yaw、关闭速度控制、零值 flush、趴下确认和断开。

脚本不调用示例里的 `setZeroPositionsFlag()`，也不调用与本测试无关的 `setWalk()`
或其他 gait。它不创建 `JointLevelControl`。

## 每次执行前必须人工确认

- [ ] 机器人已完全趴下，地面平整、防滑。
- [ ] 按整机完整旋转包络留出安全余量，上方及四周没有人员、线缆和障碍物。
- [ ] 现场操作员全程观察，物理急停可立即触达且已验证有效。
- [ ] 遥控器、App、其他 SDK 程序和 SDK read-only Deployment 已停止。
- [ ] 主机 UDP 9873 未被其他进程或容器占用。
- [ ] 机器人电量和机械状态允许完成站立、旋转和趴下。

`--confirm-physical-yaw-circle` 只是对以上条件的显式确认，不能代替物理急停。

## 手动执行

确保最新测试镜像已经构建：

```bash
cd /root/workspace/c2/robonix_adapt/primitive-mirrorme-bpx-quadruped-rbnx
bash scripts/build-container.sh
```

Docker Desktop/WSL2 使用：

```bash
bash scripts/run-yaw-circle-probe.sh --network-mode bridge \
    /root/workspace/c2/bpx_sdk_open/main/wheelhouse/bpx_sdk_open-1.0.8-cp310-cp310-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl \
    --robot-ip 192.168.1.237 \
    --robot-state-port 9873 \
    --state-rate-hz 50 \
    --motion-command-rate-hz 50 \
    --yaw-rate-rps 0.5 \
    --turn-angle-rad 6.283185307179586 \
    --turn-timeout-s 30 \
    --max-translation-m 0.15 \
    --opposite-direction-tolerance-rad 0.2 \
    --zero-flush-s 2 \
    --confirm-physical-yaw-circle
```

原生 Linux Docker 省略 `--network-mode bridge`，使用默认 host 网络。
将 `--yaw-rate-rps` 改为负数可以反向旋转；适配层限制其绝对值为
`0.1..1.0 rad/s`。首次测试建议保留默认 `0.5 rad/s`。
`--opposite-direction-tolerance-rad` 默认是 `0.2 rad`；只用于容忍 odom 抖动，
不是允许机器人持续向错误方向运动。

遗漏确认参数时，外层脚本会在 wheel 校验、Docker 启动及机器人连接前退出。
以下命令只查看帮助，不连接机器人：

```bash
python3 -m bpx_quadruped.yaw_circle_probe --help
```

## 保护条件

- 初始状态不是 `LyingDown(0)`：不发送任何姿态或速度命令。
- 站立、旋转或趴下状态超时：发送零 yaw、关闭 velocity flag，然后有限时请求趴下。
- odom 断连或超过 0.5 秒无新帧：执行同样清理。
- 旋转期间离开 `Motion(6)`：执行同样清理。
- 水平位移超过 `--max-translation-m`：立即停止 yaw 并进入趴下清理。
- LegOdom 沿命令反方向累计超过 `--opposite-direction-tolerance-rad`：立即停止 yaw
  并进入趴下清理，反方向转满一圈不能再被误判成功。
- `Ctrl-C`/SIGTERM：发送零 yaw、关闭 velocity flag、请求趴下并断开。
- yaw 绝对值超过 `1.0 rad/s`、目标角超过一圈、反向容差不在
  `0.05..1.0 rad` 或超时短于理论旋转时间：启动前拒绝。

物理异常时不要等待软件清理。若出现明显平移、碰撞趋势、失稳、抖动或异响，立即
使用物理急停。

## 预期关键输出

```text
initial state confirmed: LyingDown(0)
setStandUp accepted; waiting for Motion(6)
state confirmed: Motion(6)
yaw control enabled: rate=0.500rad/s target=6.283185rad
yaw target reached: accumulated=...rad max_translation=...m
zero yaw accepted; velocity control disabled; flushing zero for 2.000s
setSitDown accepted; waiting for LyingDown(0)
state confirmed: LyingDown(0)
yaw-circle cycle complete: LyingDown(0)
```

完成后记录机器人是否实际转满一圈、方向、最大平移、动作稳定性、异常声音、操作员、
日期、正式型号/序列号、固件版本、完整控制台日志和现场视频。
