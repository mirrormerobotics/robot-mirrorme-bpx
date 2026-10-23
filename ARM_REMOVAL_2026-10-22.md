# 移除本地 arm 前置约束

按操作者要求，运动服务不再要求先调用本地 arm，也不再按 30 秒租期终止运动。
ACTIVE、allow_motion=true、反馈健康且已站立时，新的 move/Twist 请求准备 SDK 控制。
启动/恢复连接/清故障不会重放旧指令或自动站立。FAULT 仍需显式恢复。

move 结束仍归零并关闭 SDK 速度控制；下一次 move/Twist 可直接重新准备。
stop/disarm 取消当前动作，不是持久禁用开关；持久禁用使用 DEACTIVATE/shutdown。
release 关闭 SDK 会话，必须重启 provider 才能重新使用。
保留内部 ARMED 状态及旧 arm 兼容入口；上层不需要调用它。
旧 motion_lease_s 配置仅兼容解析，不再控制执行时间。单次请求时限和看门狗仍有效。

离线验证：

- Primitive 单测 181 项通过，Robot 单测 46 项通过，模型生成一致性通过。
- 网络隔离容器内 provider 生命周期回归 6 项通过，未加载 SDK。
- 覆盖连续免 arm 请求、旧租期不再中断动作、SDK 准备失败锁存、非站立拒绝、
  故障恢复、停发归零、取消及生命周期禁用。
- 报告：`.artifacts/offline/20261022T112811645989Z/report.json`。
- 已更新 fake RPC 集成测试为免 arm 调用，但本次没有运行完整 Atlas/ROS 集成测试，
  避免与运行中的真机服务共享端口及容器名称。

本次没有下发真机命令、重启现有服务或发布新镜像/tag；现场旧进程尚未加载本次修改。
默认 dev.2 发布能力仍是 odom/posture，运动能力清单及版本发布需另行处理。
此前人工验收记录保持历史含义，不作为本次修改的真机复测证据。
