# BPX Robonix 适配安全边界

当前可运行交付只包含模型、fake、状态回放和 SDK 只读状态链路。没有任何
profile 被批准向真机发送运动命令。

## Profile 安全等级

| Profile | 连接真机 | 运动接口 | 用途 |
| --- | --- | --- | --- |
| `robonix_manifest.yaml` | 否 | 无 | 安全默认；Atlas + Soma + 本体模型 |
| `robonix_manifest.no-motion.yaml` | 否 | 无 | 显式模型检查 |
| `robonix_manifest.fake-state.yaml` | 否 | 独立 `motion_dev` 身份；仅 fake，且默认未 arm | 离线控制器和 ROS 数据面测试；不得作为发布依赖 |
| `robonix_manifest.replay-state.yaml` | 否 | 无 | 录制状态回放、生命周期和 ROS 数据面测试 |
| `robonix_manifest.sdk-read-only.yaml` | 是 | 无 | 有界真机遥测采集；只构造 `RequestRobotState` |

Primitive 默认、x86 Docker 和 SDK 专用发布清单均只声明 `odom`，不声明
`twist_in`；SDK runtime 也没有 `apply()`、arm 或运动控制对象。外置 wheel 必须
通过固定 SHA-256 校验，且只读挂载。

## 真机前禁止事项

- 不得自行创建 `MotionLevelControl`、`JointLevelControl` 或调用
  `setZeroPositionsFlag()`。
- 不得把 fake profile 的 `allow_motion` 打开后用于真机。
- 不得声明 posture、move、低层关节、建图或导航能力。
- 不得用未确认的 IMU 外参、LegOdom 坐标约定或全零 covariance 作为正式数据。
- 再分发 SDK wheel 或厂商二进制时必须随附其 Apache-2.0 LICENSE、NOTICE、
  适用的第三方声明和发布 SBOM。

## 未来运动测试的最低条件

必须先完成 [HARDWARE_CHECKLIST.md](HARDWARE_CHECKLIST.md)，并由现场操作员
掌握物理急停。测试区需要架高或留有足够安全空间；首次测试只允许白名单姿态
和极低速度，且必须记录拔网线、超时、SIGTERM、机器人重启等故障下的停止时间。

软件 arm 不能替代物理急停，也不能覆盖遥控器/App/机器人固件的控制优先级。
任何断连或状态 stale 都必须锁存 fault；恢复连接后仍保持 DISARMED，不得重放
断连前的命令。

BPX 不支持建图、定位或自主导航，本项目不会把 odom 描述成导航能力。
