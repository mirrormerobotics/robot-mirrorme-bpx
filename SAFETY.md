# BPX Robonix 适配安全边界

`v0.1.0-dev.2` 默认 Deployment 发布 odom 与精确的 `stand`/`sit` posture 白名单。
启动和生命周期切换本身不改变姿态，只有显式 posture RPC 才发送站立或趴下命令。
SDK read-only、模型、fake 和状态回放 profile 继续保留；另有必须由操作者手动启动
的姿态与原地 yaw 探针，它们不扩大 Catalog 发布能力面。

## Profile 安全等级

| Profile | 连接真机 | 运动接口 | 用途 |
| --- | --- | --- | --- |
| `robonix_manifest.yaml` | 是 | `posture`：仅 `stand`/`sit` | Catalog/预发布默认；固定 tag 的 SDK odom + guarded posture 部署 |
| `robonix_manifest.no-motion.yaml` | 否 | 无 | 显式模型检查 |
| `robonix_manifest.fake-state.yaml` | 否 | 独立 `motion_dev` 身份；仅 fake，且默认未 arm | 离线控制器和 ROS 数据面测试；不得作为发布依赖 |
| `robonix_manifest.replay-state.yaml` | 否 | 无 | 录制状态回放、生命周期和 ROS 数据面测试 |
| `robonix_manifest.sdk-read-only.yaml` | 是 | 无 | 有界真机遥测采集；只构造 `RequestRobotState` |
| Primitive `scripts/run-posture-cycle-probe.sh` | 是 | 仅 `setStandUp`/`setSitDown` | 独立人工真机调试；不是 Deployment profile |
| Primitive `package_manifest.posture-test.yaml` | 是 | Robonix `posture`，仅 `stand`/`sit` | 保留的独立诊断身份；需本地启动确认；不得发布到 Catalog |
| Primitive `scripts/run-yaw-circle-probe.sh` | 是 | stand/sit + `setVelocity(0,0,yaw)` | 独立人工原地旋转测试；不是 Deployment profile |

Primitive 默认和 x86 Docker 发布清单声明 `odom` 与 `posture`，不声明
`twist_in`；它们只创建一个 `MotionLevelControl` owner，并由本地配置门禁启用 posture。
SDK read-only/replay 清单仍只声明 `odom` 且不创建运动控制对象。外置 wheel 必须通过
固定 SHA-256 校验，并以只读方式挂载。

需要完全不连接真机时，必须显式使用 `robonix_manifest.no-motion.yaml`；需要连接
真机但完全不提供执行器命令入口时，使用 `robonix_manifest.sdk-read-only.yaml`。

这里的“只读”特指不具备执行器/运动命令接口。厂商
`RequestRobotState.connect()` 仍会配置状态上传参数，并由 SDK 执行其内置的机器人
时钟同步握手；这两项不产生运动，但并非协议层面的“完全不向机器人写任何值”。

## 真机运动限制

- 默认发布 runtime、显式人工调试脚本和独立 posture-test profile 均可能创建一个
  `MotionLevelControl`；任一时刻只能运行其中一个 owner。
- 不接入或创建 `JointLevelControl`，不得调用 `setZeroPositionsFlag()`。
- 姿态探针不得调用 `setVelocity()`；yaw-circle 探针只可调用
  `setVelocity(0,0,yaw)`，不得发送线速度。通用 `twist_in` 映射另行实现和验收。
- 不得把 fake profile 的 `allow_motion` 打开后用于真机。
- 发布 profile 只允许声明 odom 与精确的 `stand`/`sit` posture；不得声明
  `twist_in`、move、低层关节、建图或导航能力。
- 不得用未确认的 IMU 外参、LegOdom 坐标约定或全零 covariance 作为正式数据。
- 再分发 SDK wheel 或厂商二进制时必须随附其 Apache-2.0 LICENSE、NOTICE、
  适用的第三方声明和发布 SBOM。

## 姿态和未来运动测试的最低条件

必须先完成 [HARDWARE_CHECKLIST.md](HARDWARE_CHECKLIST.md)，并由现场操作员
掌握物理急停。测试区需要架高或留有足够安全空间；首次测试只允许白名单姿态
和极低速度，且必须记录拔网线、超时、SIGTERM、机器人重启等故障下的停止时间。

首个白名单姿态流程只允许“从已确认 `LyingDown(0)` 开始，站立，保持 3 秒，再
回到 `LyingDown(0)`”，具体步骤见
[POSTURE_TEST_GUIDE.md](POSTURE_TEST_GUIDE.md)。此阶段不测试速度。

正式 posture runtime 的激活只接受新鲜的 `LyingDown(0)` 或 `Motion(6)`，但不会
自动发送命令；停机前应由操作员显式调用 `sit`。deactivate/shutdown 仅关闭 velocity
flag 并断开，不会为“安全清理”而悄悄改变机器人姿态。

后续手动原地旋转测试见
[YAW_CIRCLE_TEST_GUIDE.md](YAW_CIRCLE_TEST_GUIDE.md)。它以 LegOdom 累计 yaw
沿命令方向达到一圈为完成条件，线速度固定为零，并设旋转超时、最大平移和
反方向累计门限。

软件 arm 不能替代物理急停，也不能覆盖遥控器/App/机器人固件的控制优先级。
任何断连或状态 stale 都必须锁存 fault；恢复连接后仍保持 DISARMED，不得重放
断连前的命令。

BPX 不支持建图、定位或自主导航，本项目不会把 odom 描述成导航能力。
