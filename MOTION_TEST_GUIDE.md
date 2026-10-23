# 未发布运动能力：离线联调与真机验收

剩余项目的逐项方法、自动证据采集与分析见 [REMAINING_TESTS.md](REMAINING_TESTS.md)。

新增 `twist_in` 连续平面速度和标准 `move` RPC，独立于已发布的 odom/stand/sit。
`robonix_manifest.motion-test-fake.yaml` 完全离线；`robonix_manifest.chassis-test.yaml`
才加载 SDK。启动均保持静止；ACTIVE 后运动请求无需手动 arm。测试身份不得提交 Catalog。

## 离线回归

Windows 项目根目录运行：

```powershell
.\robot-mirrorme-bpx\scripts\dev.ps1 -Mode full -ProxyUrl http://172.29.32.1:7897
```

代理地址按本机 WSL 网关调整。报告存于 `.artifacts/offline/<时间>/report.json`。
motion 阶段使用 fake backend，实际经过 Atlas 发现、gRPC、ROS 和容器进程，
检查无需 arm 的连续调用、距离/角度/定时命令、RPC deadline 取消和速度停发归零。
核心单测另覆盖 ±360° 跨角度边界、断连/旧状态、里程计跳变/时间倒退、生命周期和并发。

## WSL 快速操作（推荐）

Windows 终端输入 `wsl -d Ubuntu-20.04`，进入 WSL 后，每个窗口先执行：

```bash
cd /mnt/c/Users/Administrator/Desktop/robonix/robot-mirrorme-bpx
```

窗口 1（状态回传，保持运行；已经运行转发时不要重复启动）：

```bash
bash scripts/motion-test.sh relay 10.21.40.1 10.21.40.68
```

此命令从 WSL 调用 Windows 的转发程序并为该进程指定执行策略，不必手动配置
PowerShell。WSL NAT 的回传仍需经过 Windows，不能仅靠切换终端消除它。

窗口 2（先预览，再由操作员启动并保持运行）：

```bash
bash scripts/motion-test.sh preview
bash scripts/motion-test.sh start --confirm-physical-motion-test
```

等待 `mirrorme_bpx_motion` ACTIVE 后，在窗口 3 逐条执行、观察：

```bash
bash scripts/motion-test.sh status
bash scripts/motion-test.sh stand --confirm-physical-motion-test
bash scripts/motion-test.sh forward --forward-m 0.1 --duration-sec 10
```

每次 move 结束会停止，下一条无需 arm；可选小角度测试：

```bash
bash scripts/motion-test.sh rotate --rotate-deg 15 --duration-sec 10
```

随时从另一窗口执行 `bash scripts/motion-test.sh stop`。正常结束时：

```bash
bash scripts/motion-test.sh stop
bash scripts/motion-test.sh sit --confirm-physical-motion-test
bash scripts/motion-test.sh shutdown
```

确认坐下完成再 shutdown，最后在转发窗口 Ctrl+C。物理急停始终保持可用。
`No such container` 表示服务未启动、已退出或启动失败；先查看窗口 2 的报错，
不要继续发送动作命令。WSL 脚本会在这种情况下给出明确的启动提示。

## 本机 Windows PowerShell 操作（可选）

以下在 PowerShell 中操作。先进入 Robot 仓库：

```powershell
cd C:\Users\Administrator\Desktop\robonix\robot-mirrorme-bpx
.\scripts\motion-test.ps1 -Action preview
```

`preview` 只渲染配置，不连接机器人。脚本自动使用本机 WSL、固定 SDK wheel 和缓存，
机器人默认 `10.21.40.1`；地址改变时在 start/preview 传 `-RobotIp`。

终端 1：启动状态回传（本机 WSL NAT 需要）。`ListenIp` 是 Windows Wi-Fi 地址，
可以用 `Get-NetIPAddress -InterfaceAlias WLAN -AddressFamily IPv4` 核对；WSL 地址自动获取。

```powershell
.\scripts\state-relay.ps1 -RobotIp 10.21.40.1 -ListenIp 10.21.40.68
```

默认最多运行 30 分钟；在运动测试结束前保持运行。它仅转发指定机器人发来的状态
UDP，不向机器人发送控制数据。Ctrl+C 关闭，端口被占用时拒绝启动。

终端 2：启动测试服务并保持窗口运行。首次运动测试确保有人监护、空间足够、物理急停可用：

```powershell
.\scripts\motion-test.ps1 -Action start -ConfirmPhysicalMotion
```

启动后保持 DISARMED，不自动站立或解锁。终端 3：**逐条执行并观察**，不要整段粘贴：

```powershell
.\scripts\motion-test.ps1 -Action status
.\scripts\motion-test.ps1 -Action stand -ConfirmPhysicalMotion
.\scripts\motion-test.ps1 -Action forward -Distance 0.1 -Duration 10
.\scripts\motion-test.ps1 -Action status
```

确认前移测试结果后，其他可选命令（无需 arm；负距离后退、负角度顺时针）：

```powershell
.\scripts\motion-test.ps1 -Action rotate -Degrees 15 -Duration 10

.\scripts\motion-test.ps1 -Action velocity -X 0.1 -Y 0 -Yaw 0 -Duration 1
```

`velocity` 是标准 move RPC 的定时速度模式，不是无限持续发送；这方便首次手动验收。
单次命令完成即撤销解锁；若低速死区导致未移动/超时，先保存结果，勿盲目加速。
初次不要直接测试整圈；后续整圈可用 `-Degrees 360 -Duration 30`，该时限从运动请求开始计算，不受本地 arm 租期限制。

任何时候，可在另一个终端停止；此软件停止不能替代物理急停：

```powershell
.\scripts\motion-test.ps1 -Action stop
```

结束测试依次执行，确认坐下完成后再退出服务，最后在转发窗口 Ctrl+C：

```powershell
.\scripts\motion-test.ps1 -Action stop
.\scripts\motion-test.ps1 -Action sit -ConfirmPhysicalMotion
.\scripts\motion-test.ps1 -Action shutdown
```

`shutdown` 不自动坐下。故障原因排除后用 `-Action clear-fault` 清除锁存，再检查 status，
需要运动时发送新请求即可。脚本没有自动动作序列，也不自动清故障。

## 手动启动（Linux/WSL 终端）

先按 `OFFLINE_DEVELOPMENT.md` 配置固定 Robonix、runtime 镜像和 SDK wheel。
确认机器人地址（默认 `10.21.20.1`）并修改测试 manifest。WSL 网络能否连接机器人
需现场确认；生产验收优先原生 Ubuntu 22.04 host-network。
操作员必须在场，准备物理急停并留出空间。确认机器人端 watchdog 和控制权仲裁后：

```bash
export PATH="$HOME/.cache/robonix-bpx/target/release:$PATH"
export BPX_SDK_WHEEL="$(realpath ../.deps/sdk/bpx_sdk_open-1.0.8-cp310-cp310-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl)"
export BPX_CONFIRM_PHYSICAL_MOTION_TEST=I_UNDERSTAND_MOTION_TEST_CAN_MOVE_BPX
rbnx boot -f robonix_manifest.chassis-test.yaml --no-update-check -v
```

以上在 Robot 仓库运行。另开终端定义本地操作函数（不开放网络解锁接口）：

```bash
bpx_local() {
  docker exec rbnx_mirrorme_bpx_quadruped python3 -m bpx_quadruped.local_control "$@"
}
bpx_move() {
  docker exec -e PYTHONPATH=/pkg:/robonix-api:/pkg/rbnx-build/codegen/proto_gen \
    rbnx_mirrorme_bpx_quadruped python3 -m bpx_quadruped.move_client "$@"
}
bpx_local status
bpx_local stand
bpx_move --forward-m 0.1 --duration-sec 10
bpx_local status
```

每个 move 结束（含失败/取消）都会归零并撤销解锁；下一次请求会重新准备 SDK，无需 `arm`。
`bpx_local cancel`/`disarm` 可中止；故障恢复后先 `clear_fault`，再发送新请求；不会恢复旧指令。
`sit` 先停止速度再请求坐下。客户端 `--timeout-s` 默认 35 秒；RPC deadline 到期
服务端取消动作，客户端得到失败，需检查 status 和现场状态。

## 接口与限制

- 标准 `MoveCommand` 优先级：`forward_m` > `rotate_deg` > 定时速度。
- 距离按开始时机体朝向投影；旋转累计有符号 yaw，支持 ±360°。
- 单次距离 ≤1m、角度 ≤360°、时长 ≤30s；距离/角度默认超时 30s，速度默认 1s。
- x/y/yaw 硬上限 0.3m/s、0.2m/s、0.5rad/s；闭环内部最高 0.2m/s、0.4rad/s。
- 距离容差 0.02m，角度容差 0.03rad；偏航、横移、反向及里程计跳变会中止。
- 已取消本地 arm 和租期前置约束；运动请求仍受生命周期、反馈与单次时限检查。
- `/cmd_vel` 使用 ROS `geometry_msgs/Twist`；默认 0.25s 未收命令归零。
  停发后可接收新命令；`stop`/`disarm` 中止当前动作，彻底禁用使用 DEACTIVATE 或 shutdown。
- move/本地姿态执行期间拒绝其他运动请求，生命周期重启不复用旧命令或解锁。

这些软件阈值不是已标定的物理精度。Walk 小速度死区、里程计尺度、停止距离、固件
ack 含义仍需真机测量，不通过提高最低速度来掩盖误差。
停止时先排入零速度，保留至少三个 SDK 发送周期（不低于 0.1s），再关闭速度标志；
这不构成机器人已经停下的确认，仍需测量现场停止时间。
主机 watchdog 不能保证 SIGKILL、主机掉电或 SDK 原生线程卡死后的物理停止；
必须验收机器人端 watchdog 和物理急停。

## 现场证据清单

逐项记录机器人/固件/SDK/代码版本、命令、odom、日志、停止时间和视频：

- [ ] stand -> 0.1m 前/后移；逐步扩大至计划范围。
- [ ] 左/右小角度、±360° 原地旋转；横移和转角误差。
- [ ] 连续速度停发、显式 cancel、RPC 超时、生命周期禁用。
- [ ] 断网、旧状态、机器人重启、SIGTERM/SIGKILL、主机失联及多控制端抢占。
- [ ] 故障清除和生命周期重启后不自行运动。
- [ ] Walk 死区、停止距离、机器人 watchdog 上界和急停有效性。

真机失败项据证据修复并重新验收，通过后才讨论发布清单扩展。
