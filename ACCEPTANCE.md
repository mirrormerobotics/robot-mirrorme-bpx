# BPX Robonix 验收矩阵

2026-10-13 软件收尾：新增运动健康/进度采集、停滞提前终止和 SDK 会话 release。
单测 161 + 42 通过；完整离线运行的 motion 旧消息断言修复后，motion 单项复测通过，
其余集成阶段已通过。操作及尚未完成的现场项目见
[FIXES_AND_RETEST_2026-10-13.md](FIXES_AND_RETEST_2026-10-13.md)。

2026-10-13 补录：20cm目标反馈约7.58cm后超时；15°目标因反馈健康故障取消，
详见 [MOTION_VALIDATION_2026-10-13.md](MOTION_VALIDATION_2026-10-13.md)。

最新核验见 [TASK_STATUS_2026-10-12.md](TASK_STATUS_2026-10-12.md)：基础接入已验证，
基本运动执行已现场验证；距离/角度闭环仍待标定，新增控制权释放路径待真机验收。

2026-10-12 新开发机的完整离线复验见 [OFFLINE_VALIDATION.md](OFFLINE_VALIDATION.md)。
这次结果不改变下文任何尚待真机/现场确认的勾选状态。

## 已完成的离线验收

- [x] 固定 Robonix、SDK contract、模型和 ROS 基础镜像基线
- [x] Primitive 单元测试覆盖 lifecycle、安全状态机、SDK 只读 adapter、
  telemetry 校验、回放、录制/audit、关节映射和 packaging
- [x] runtime Docker 镜像仅在容器测试通过后标记为 `:dev`
- [x] 默认 `robonix_manifest.yaml` 通过公开 URL 和 `v0.1.0-dev.2` 固定 Primitive，
  只声明 `odom` 与精确的 `stand`/`sit` posture
- [x] `robonix_manifest.no-motion.yaml` 不启动 Primitive 或 SDK session
- [x] 默认 Robot manifest 包含完整的 `catalog:` 预发布元数据
- [x] Primitive 默认/x86 Docker 发布身份声明 `odom` 与 `posture`；SDK read-only/
  replay 诊断身份只声明 `odom`
- [x] `motion_dev` 强制 fake backend；新增 `motion_test`/`motion_test_fake` 均为非发布身份
- [x] replay package 只声明 `robonix/primitive/quadruped/odom`
- [x] replay deployment 达到 ACTIVE，并接收到 `/odom`、`/joint_states` 和同 stamp Odom TF
- [x] 当前 profile 只有一个 Odom publisher；fake 只有一个 Twist consumer 并拒绝非平面 Twist
- [x] Driver `DEACTIVATE` 返回 INACTIVE，重新 `ACTIVATE` 返回 ACTIVE
- [x] replay deployment 停止后无 BPX Primitive 容器遗留
- [x] 断连 fault 清除后仍为 DISARMED，重新 arm 也不重放旧 Twist
- [x] SDK 默认不可达地址在有界超时后失败并完成清理
- [x] 产品范围不包含建图、定位或自主导航，所有 manifest 均无相关声明

可重复执行：

```bash
cd primitive-mirrorme-bpx-quadruped-rbnx
bash scripts/test.sh
bash scripts/build-container.sh

cd ../robot-mirrorme-bpx
python3 -m unittest discover -s tests -v
bash scripts/test-offline-integration.sh /path/to/fixed/robonix replay
```

## 已完成的真机只读验收

- [x] `RequestRobotState` 连接、首帧时延、30 秒连续采集和正常断开
- [x] 50 Hz 与 10 Hz 请求下记录各状态字段实测频率、最大间隔、估算丢帧和 timestamp 回退
- [x] 完整 SDK read-only Deployment 达到 ACTIVE，Atlas 仅暴露 `odom`，无 `twist_in`
- [x] 真机 `/odom` 与 12 关节 `/joint_states` 可由独立 ROS 2 consumer 接收
- [x] 真机 Driver `ACTIVE -> INACTIVE -> ACTIVE` 后遥测恢复
- [x] `rbnx shutdown` 到达 TERMINATED，外层退出码 0 且无 Primitive 容器残留
- [x] Docker Desktop 使用 bridge + UDP 9873 显式映射的兼容路径已验证

详细证据见 [HARDWARE_VALIDATION.md](HARDWARE_VALIDATION.md)。
2026-10-12 本机复验见 [READ_ONLY_VALIDATION_2026-10-12.md](READ_ONLY_VALIDATION_2026-10-12.md)，
不代表历史列表中的全部项目已在本机重新执行。

## 尚待真机/现场确认

- [x] 2026-09-08 操作者对照真机运动与 Odom 实际输出确认：+x 向前、+y 向左、+yaw 左转
- [x] Odom 原点验收的分阶段只读采集与离线对比工具已准备，见 [操作指南第 15 节](HARDWARE_TEST_GUIDE.md#15-世界坐标原点sdk-重连与整机重启验收)
- [ ] Odom 启动原点及初始朝向（待实际分阶段证据）
- [ ] Odom SDK 新会话重连后的坐标行为（待实际分阶段证据）
- [ ] Odom 整机断电重启后的坐标行为（待实际分阶段证据）
- [ ] 关节方向/零位、温度和电池电流单位
- [ ] vendor timestamp 的单位、epoch、wrap/reset 和实测速率偏差
- [ ] IMU frame/外参及 covariance；未确认前不发布正式 IMU 数据
- [ ] 拔网线、机器人重启、长时间 soak 和异常进程退出时的只读 session 清理
- [ ] 物理尺寸与官方 URDF 对目标型号的一致性
- [ ] 原生 Ubuntu 22.04 + Docker host-network 的独立复验
- [x] SDK 和预编译制品已确定采用 Apache-2.0
- [ ] SDK 原生库和全部 wheel 的第三方依赖/SBOM 审计

## 姿态/运动验收

- [ ] 机器人端 watchdog 上界、急停及多控制端仲裁已确认
- [x] 产品决策明确不接入 `JointLevelControl`
- [x] 独立探针由单一 SDK `MotionLevelControl` 同时拥有状态和姿态命令
- [x] stand/sit 白名单、状态新鲜度、完成条件、超时、并发拒绝和 session 清理已有
  fake-clock 测试
- [x] 当前探针不提供 `setVelocity`、zero-position、gait、damping 或低层关节入口
- [x] 2026-09-03 真机 SDK 状态闭环完成一次“`LyingDown(0)` -> `Motion(6)` -> 保持 3 秒 -> `LyingDown(0)`”，退出码 0 且无容器/UDP 端口残留
- [x] 现场操作员确认动作正常，未观察到意外平移、不稳定或异响（未归档视频）
- [x] stand/sit 已接入 Robonix `posture`；2026-09-03 真机顺序
  stand/sit RPC 分别由 `Motion(6)`/`LyingDown(0)` 状态闭环确认成功；RPC 白名单、
  单 owner、生命周期无隐式姿态命令、session 清理和并发拒绝已离线验证，停止后无
  容器/UDP 9873 残留；该能力纳入 `v0.1.0-dev.2`，真机故障注入仍待补
- [x] 独立手动 yaw-circle 探针实现 `setVelocity(0,0,yaw)`，含命令方向一致的 odom 一圈闭环、零速度 flush、超时、状态、最大平移和反方向门禁
- [ ] 按 [YAW_CIRCLE_TEST_GUIDE.md](YAW_CIRCLE_TEST_GUIDE.md) 由操作者完成一次真机原地一圈并记录现场证据
- [x] 通用 `setVelocity(x, y, yaw)` 到 Robonix `twist_in` 的非发布测试实现
- [x] 有界 move 的闭环、取消、超时及 finally 归零实现和离线测试
- [x] 本次本地 stand/sit confirmed；0.2m/s、1s 定时速度 RPC 成功，动作结束后 DISARMED、无锁存故障
- [x] 操作者确认 15°/50°目标均实际发生旋转；未重新 arm 时请求被拒绝，正常 shutdown 后无运行容器
- [ ] 15°/50°旋转的实际角度与完成条件核验（当前返回 timeout，不代表没有执行）
- [ ] 上述新增能力的真机验收，见 [MOTION_TEST_GUIDE.md](MOTION_TEST_GUIDE.md)
- [ ] 修复距离 move 超时：0.1m 不动、1m 可移动但未成功完成；需要动作遥测证据
- [ ] 修复/明确 SDK 与 App 控制权交还：用户确认 shutdown 后 App 前进/转向恢复
- [ ] 向使用者明确暴露内部 motion FAULT，避免误读生命周期 ACTIVE
- [ ] NaN、超限、命令 stale、状态 stale、断网、SIGTERM/SIGKILL 和重启测试
- [ ] 每个故障场景有停止时间、日志和视频证据

已创建独立、默认未解锁的 `chassis-test` 非发布测试 profile；发布身份仅声明
`stand`/`sit` posture，不声明 move 或真实 `twist_in` 能力。独立 posture-test
诊断身份不得提交 Catalog。

首次姿态状态闭环证据见 [POSTURE_VALIDATION.md](POSTURE_VALIDATION.md)。
首次 Robonix posture RPC 真机证据见
[POSTURE_SERVICE_VALIDATION.md](POSTURE_SERVICE_VALIDATION.md)。
