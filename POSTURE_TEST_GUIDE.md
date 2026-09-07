# BPX 站立/等待/趴下真机调试指南

本指南只验证 BPX SDK v1.0.8 `MotionLevelControl` 的两个姿态接口：
`setStandUp()` 和 `setSitDown()`。流程为“确认机器人已完全趴下 -> 站立 ->
保持 3 秒 -> 趴下”。它不属于当前 Robonix 发布 profile，也不会向 Atlas 声明
`posture` 或 `twist_in`。

## 软件边界

- 只创建一个 `MotionLevelControl`；该对象继承 `RequestRobotState`，同时负责状态
  反馈和姿态命令，不再创建第二个 SDK 状态 session。
- 不创建 `JointLevelControl`。
- 不调用 `setVelocity()`、`setWalk()`、`setDamping()`、翻转、跳跃或其他 gait。
- 不调用 `setZeroPositionsFlag()`；该接口涉及零位标定和特殊落地姿态，不属于本测试。
- 连接前和断开前都显式设置 `setVelocityControlFlag(False)`。
- 初始 motion state 必须是 `LyingDown(0)`，否则在发送任何姿态命令前失败。
- 状态断连或 odom 超过 0.5 秒没有新帧时失败；站立阶段开始后的异常或信号中断会
  有限时重复请求 `setSitDown()`，然后断开连接。

## 每次执行前必须人工确认

- [ ] 机器人已完全趴下，四周和上方净空，地面平整、防滑且没有线缆牵绊。
- [ ] 现场有人看护，人员身体不在腿部和机构运动范围内。
- [ ] 物理急停可立即触达，并已确认其有效。
- [ ] 遥控器/App/其他 SDK 程序已停止，不存在第二个运动命令源。
- [ ] 机器人电量和机械状态适合完成一次站立与趴下。
- [ ] SDK read-only Deployment 和其他占用 UDP 9873 的进程已经停止。

`--confirm-physical-motion` 只是操作者对以上条件的显式确认，不能替代物理急停。

## 执行

先设置 wheel 的绝对路径：

```bash
export BPX_WHEEL=/root/workspace/c2/bpx_sdk_open/main/wheelhouse/bpx_sdk_open-1.0.8-cp310-cp310-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl
```

Docker Desktop/WSL2 使用 bridge 网络和显式 UDP 映射：

```bash
cd /root/workspace/c2/robonix_adapt/primitive-mirrorme-bpx-quadruped-rbnx
BPX_DOCKER_NETWORK_MODE=bridge \
  bash scripts/run-posture-cycle-probe.sh "$BPX_WHEEL" \
    --robot-ip 192.168.1.237 \
    --robot-state-port 9873 \
    --state-rate-hz 50 \
    --motion-command-rate-hz 50 \
    --hold-duration-s 3 \
    --confirm-physical-motion
```

原生 Linux Docker 使用默认的 host 网络，省略
`BPX_DOCKER_NETWORK_MODE=bridge` 即可。先运行以下安全命令可以查看参数，不会连接
机器人或发送动作：

```bash
python3 -m bpx_quadruped.posture_cycle_probe --help
```

遗漏 `--confirm-physical-motion` 时，外层脚本会在 wheel 校验、容器启动和机器人连接
之前直接拒绝执行。

## 正常输出与判定

正常流程应依次出现：

```text
initial state confirmed: LyingDown(0)
setStandUp accepted; waiting for Motion(6)
state confirmed: Motion(6)
standing confirmed; holding for 3.000s
setSitDown accepted; waiting for LyingDown(0)
state confirmed: LyingDown(0)
posture cycle complete: LyingDown(0)
```

同时人工确认机器人平稳站立、保持期间无位移，并最终完全趴下。保存完整控制台日志、
测试日期、操作员、机器人正式型号/序列号、固件版本及现场视频。

## 异常处理

若出现意外位移、抖动、跌倒趋势、异常声音或姿态与日志不一致，立即使用物理急停，
不要依赖终端信号。正常软件异常可按一次 `Ctrl-C`；程序会进入有限时趴下清理并断开。
急停后不要立即重试，应先保存日志并检查机器人、控制源和 SDK 状态。

完成本测试只证明这两个厂商接口和状态闭环在当前硬件上可用；在 Robonix `posture`
服务、生命周期互斥和完整故障测试完成前，仍不得把姿态能力加入发布清单。

2026-09-03 首次状态闭环结果见
[POSTURE_VALIDATION.md](POSTURE_VALIDATION.md)。
