# 统一入口测试（2026-10-23，dev.3）

一个 provider `mirrorme_bpx`、一个 SDK MotionLevelControl 会话，提供
`odom + posture + twist_in + move`。posture 只接受 stand/sit；无需 arm。
启动不站立、不运动。只读配置仍不开放运动。新的正式启动脚本为
Primitive `scripts/start-sdk-unified.sh`；现场本地部署使用下述 start-unified。

## 已完成的离线验证

- Primitive 187 项、Robot 46 项单测，模型一致性检查通过。
- 网络隔离容器中启动真实 Atlas 和 provider，使用 fake backend：标准姿态站立、
  免 arm 连续距离/角度/定时 move、ROS Twist/odom、停发归零、姿态趴下通过。
- 非有限 Twist 注入 FAULT 后，通过标准 Driver DEACTIVATE → ACTIVATE 恢复，
  再执行新 move 成功。没有调用 arm 或 clear-fault；未加载 SDK。
- dev.3 默认四能力清单的 `rbnx validate` 和全新 gRPC/ROS 代码生成通过。
- 单测还覆盖姿态/移动互斥、姿态取消与超时、非站立拒绝、SDK 准备失败及停止异常。
- 单测报告 `.artifacts/offline/20261023T020240727290Z/report.json`；
  集成日志 `.artifacts/unified/rpc-20261023T015948Z.log`。

重新运行离线测试（WSL，Robot 仓库根目录）：

```bash
python3 scripts/verify_offline.py --mode unit
bash scripts/test-unified-offline.sh
```

第二条使用 `--network none`，无 Docker socket、无 SDK wheel、无 host IPC，
不会控制真机，也不占用现有部署的 Atlas 端口。依赖现有运行镜像、固定 Robonix
源码、生成的 protobuf 及 `$HOME/.cache/robonix-bpx/target`；可用 BPX_TARGET_CACHE
和 BPX_RBNX_IMAGE 指定已有缓存/镜像。缺少它们时先按 OFFLINE_DEVELOPMENT.md 准备。

## 真机切换到统一入口

以下由操作员执行；本轮开发没有执行真机命令或重启真机服务。
每个 WSL 终端先进入仓库：

```bash
cd /mnt/c/Users/Administrator/Desktop/robonix/robot-mirrorme-bpx
```

1. 在旧动作已停止后，结束旧部署，避免两个 SDK owner：

```bash
bash scripts/motion-test.sh shutdown
docker ps --format '{{.Names}}'
```

确认旧 `rbnx_mirrorme_bpx_sdk` 和 `rbnx_mirrorme_bpx_quadruped` 已退出。
没有部署时跳过 shutdown。已有状态 relay 可继续使用；若未运行，在另一个终端运行：

```bash
bash scripts/motion-test.sh relay 10.21.40.1 <Windows当前连接机器人网络的IPv4>
```

不要直接照抄历史 ListenIp，必须是 Windows 当前拥有的地址。若 WSLInterop 不可用，
按脚本输出在 Windows PowerShell 运行 state-relay.ps1。

2. 预览并启动统一服务（本机现有镜像已具备依赖；源码通过挂载加载，不要求重新打镜像）：

```bash
bash scripts/motion-test.sh preview-unified --robot-ip 10.21.40.1
bash scripts/motion-test.sh start-unified --confirm-physical-motion-test --robot-ip 10.21.40.1
```

保持启动终端打开。确认 provider `mirrorme_bpx` ACTIVE，Soma 导出四项能力。
预览应包含 package_manifest.x86-docker.yaml、enable_posture_service=true、
enable_motion_service=true、soma.yaml。启动许可只确认本地测试部署，不是 Robonix
上层每次任务需要的额外接口；正式 package 启动不要求本地 arm/确认 RPC。

## 用标准接口逐项测试

在操作终端设置 provider（旧测试身份是 mirrorme_bpx_motion，不要混用）：

```bash
export BPX_PROVIDER_ID=mirrorme_bpx
bash scripts/motion-test.sh status
```

启动后应 `lifecycle=active`、`fault=""`、`arm_required=false`、输出为零。
站立/移动要求健康反馈。状态中的 armed/disarmed 是内部 SDK 准备状态，不表示需手动 arm。

确保有现场监护和运动空间，下面命令逐条执行并观察，勿整段自动连续运行：

```bash
bash scripts/motion-test.sh posture stand
bash scripts/motion-test.sh forward --forward-m 0.1 --duration-sec 10
bash scripts/motion-test.sh rotate --rotate-deg 15 --duration-sec 10
bash scripts/motion-test.sh posture sit
bash scripts/motion-test.sh status
```

这两次 posture 都通过 **Atlas → 标准 posture gRPC**，不是本地 stand/sit socket。
forward/rotate 通过同一个 provider 的标准 move gRPC。每次应 `success=true`，
结束后输出零，最后 motion_state=0；不以“实际动了”替代本次接口返回成功的检查。
本次重点验收新入口和串接，不要求重复之前全部距离/整圈精度测试。
测试中若需要中断当前动作，在另一操作终端执行 `bash scripts/motion-test.sh stop`。
该命令为本地调试取消；上层可取消 move RPC，或以 DEACTIVATE 禁用整个 provider。

持续速度接口可选验证：先通过 posture stand 站立，再发送短时 Twist（ROS domain 225）：

```bash
docker exec -e ROS_DOMAIN_ID=225 rbnx_mirrorme_bpx_quadruped bash -c \
  'source /opt/ros/humble/setup.bash; timeout 1 ros2 topic pub --rate 20 /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.1}, angular: {z: 0.0}}"'
bash scripts/motion-test.sh status
```

timeout 返回 124 表示停止发布；超过 command_timeout_s（默认 0.25 秒）后输出应为零。
0.1 m/s 可能处于厂商 Walk 死区，本项检查接口/停发处理，不保证产生可见位移。

## 标准生命周期恢复

无需人为拔网制造故障。离线测试已覆盖 FAULT；现场可以在机器人静止时验证生命周期循环。
如实际出现 FAULT，先排除原因、确认反馈恢复，再执行：

```bash
export BPX_PROVIDER_ID=mirrorme_bpx
bash scripts/motion-test.sh deactivate
bash scripts/motion-test.sh activate
bash scripts/motion-test.sh status
```

前两条调用标准 `robonix/lifecycle/driver`。应恢复 ACTIVE、fault 为空、输出零，
不自动站立、不恢复旧动作。需要运动时重新 posture stand（已站立则确认当前状态），
再发新任务；无需 arm、无需 clear-fault。重复 ACTIVATE 不能清除 ACTIVE 中的故障。
如果 INIT/ACTIVATE 失败或已 release/shutdown，则应排查后重新启动 provider。

完成现场测试后，先确认无运动，再执行 posture sit，最后 shutdown；shutdown 本身不自动趴下。

## 发布状态

配套版本为 0.1.0-dev.3，Robot 默认远端清单固定引用 Primitive v0.1.0-dev.3。
发布记录见 RELEASE_NOTES.md；start-unified 始终加载相邻本地仓库，而非远端 tag。
2026-10-23 操作者确认以下统一入口真机串接测试全部通过：设置
BPX_PROVIDER_ID=mirrorme_bpx，查询 status，通过标准 posture RPC 站立，
免 arm 前进 0.1m（10s 时限），旋转 15°（10s 时限），通过标准 posture RPC 趴下。
本项记为操作者确认通过，依据本次聊天确认；未新增日志复核或实测精度数据。
本次确认对应上述命令序列，不额外推定发生过待命反馈间断或做过故障注入。


## 2026-10-23 待命反馈间断修复

待命（DISARMED、没有姿态任务）时的断连/旧反馈不再直接锁存 FAULT：
保持零输出、禁用速度控制，并显示 health=waiting_feedback、feedback_ready=false。
move、Twist、posture 和兼容 arm 均拒绝执行，也不排队保存请求。
反馈持续健康采样满 1 秒后显示 feedback_ready=true，允许新的请求；再次间断重新计时。
不能靠等待后单次读取一个新包绕过连续观察窗口。状态阈值仍是 0.5 秒，没有放宽。

准备了速度控制（ARMED）、执行 move 或姿态时发生反馈间断，仍停止并锁存 FAULT。
非法数据、里程计跳变/时间戳回退、SDK 失败等也不会自动清故障。
此前已锁存的故障不会因这次逻辑变化自动解除；需加载新代码后再验证。

回归：194 Primitive + 46 Robot 单测及隔离 Atlas/ROS/gRPC 联调通过。
报告：.artifacts/offline/20261023T023758120206Z/report.json。
覆盖待命恢复、不重放旧请求、恢复窗口重置、RPC 首次检测到超时、运动/姿态超时
继续锁存，以及异常数据/停止失败不自动恢复。本次没有向真机下发指令或重启服务。

操作员确认没有正在执行的动作后，shutdown 旧部署，再按本文 start-unified 重新启动。
单纯 DEACTIVATE/ACTIVATE 不会重载 Python 代码。启动后可用
`bash scripts/acceptance.sh observe --seconds 40` 只读采集，另开终端查看 status。
偶发待命间断应经历 waiting_feedback → disarmed，fault 保持空；不必人为拔网制造间断。
历史 last_fault 不是当前锁定状态，以 fault/safety/health 判断。
