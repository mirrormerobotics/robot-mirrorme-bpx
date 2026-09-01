# BPX Robonix 验收矩阵

## 已完成的离线验收

- [x] 固定 Robonix、SDK contract、模型和 ROS 基础镜像基线
- [x] Primitive 单元测试覆盖 lifecycle、安全状态机、SDK 只读 adapter、
  telemetry 校验、回放、录制/audit、关节映射和 packaging
- [x] runtime Docker 镜像仅在容器测试通过后标记为 `:dev`
- [x] 默认 `robonix_manifest.yaml` 通过公开 URL 和 `v0.1.0-dev.1` 固定只读 Primitive，且不声明运动能力
- [x] `robonix_manifest.no-motion.yaml` 不启动 Primitive 或 SDK session
- [x] 默认 Robot manifest 包含完整的 `catalog:` 预发布元数据
- [x] Primitive 默认/x86 Docker/SDK/replay 发布身份均只声明 `odom`
- [x] fake Twist 仅存在于独立、非发布且强制 fake backend 的 `motion_dev` 身份
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

## 待真机验收

- [ ] SDK read-only 连接、首帧时延、连续运行和正常断开
- [ ] 实测状态频率、最大间隔、估算丢帧和 vendor timestamp 单调性
- [ ] Odom 坐标系、四元数、速度、关节方向/零位、温度和电池单位
- [ ] IMU frame/外参及 covariance；未确认前不发布正式 IMU 数据
- [ ] 拔网线、机器人重启和进程退出时的只读 session 清理
- [ ] 物理尺寸与官方 URDF 对目标型号的一致性
- [x] SDK 和预编译制品已确定采用 Apache-2.0
- [ ] SDK 原生库和全部 wheel 的第三方依赖/SBOM 审计

## 运动验收（尚未授权实现）

- [ ] 机器人端 watchdog 上界、急停及多控制端仲裁已确认
- [ ] 独立的单一 SDK motion owner 和本地人工 arm
- [ ] stand/sit/damping 白名单、完成条件和超时
- [ ] 有界 move 的闭环、取消、超时及 finally 归零
- [ ] NaN、超限、命令 stale、状态 stale、断网、SIGTERM/SIGKILL 和重启测试
- [ ] 每个故障场景有停止时间、日志和视频证据

在全部运动项通过前，不创建 `chassis-test`/full-motion profile，不声明 posture、
move 或真实 `twist_in` 能力。
