# 剩余验收：WSL 操作与证据

## 最终状态：全部通过（2026-10-21 操作者确认）

按操作者本次明确要求，本页第 1–8 节统一记为人工验收通过，结束本轮验收，
不再要求重复执行。下面保留原操作步骤作为参考；其中“未验收/待确认”等措辞是
历史测试前说明，当前人工验收状态以本节为准。

| 范围 | 最终状态 |
| --- | --- |
| 1. 准备 | [x] 操作者确认通过 |
| 2. 距离闭环 | [x] 操作者确认通过 |
| 3. 角度闭环、正反向和整圈 | [x] 操作者确认通过 |
| 4. 低速响应与横移 | [x] 操作者确认通过 |
| 5. 取消、RPC deadline 和租期 | [x] 操作者确认通过 |
| 6. 控制权交还 | [x] 操作者确认通过 |
| 7. 状态链路中断、异常退出 | [x] 操作者确认通过 |
| 8. 原点、标定和其他交付项 | [x] 操作者确认接受本轮交付 |

此处记录人工接受结论，不伪造新的测试日志、视频、实测数值或厂商书面资料。
既有整圈 RPC 的租期失败记录仍保留。第 8 节的接受也不会自动产生外参/协方差参数、
源码许可证审计报告或原生生产主机测试记录；缺失交付材料仍在总 TODO 单列。
软件不会因本文勾选而自动启用 odom TF、IMU、发布运动能力或取消本地 arm。
整体链路及后续发布事项见 [INTEGRATION_CHAIN.md](INTEGRATION_CHAIN.md)。

2026-10-14：有界 move 已增加 Walk 最低目标速度补偿（默认 0.25m/s、0.25rad/s），
新行为、最小复测及原 M5 待验项以 [M5_VALIDATION_2026-10-14.md](M5_VALIDATION_2026-10-14.md)
为准。连续 Twist 和定时速度不补偿，下面的死区测量步骤仍适用。

本页用于人工测试，不是自动连续动作脚本。基本站/趴、定时前进和旋转执行已有现场
证据；剩余重点是闭环误差、控制权交还和故障行为。超时表示未满足程序完成条件，
不等于未运动；需要结合记录判断。不要在无结果依据时提高速度或扩大测试范围。

2026-10-13 软件更新后的最小复测顺序见
[FIXES_AND_RETEST_2026-10-13.md](FIXES_AND_RETEST_2026-10-13.md)。下面是完整待验清单，
不是要求立即重复所有动作。新代码需重启服务加载。

## 1. 准备（沿用已验证步骤）

所有 WSL 窗口：

```bash
cd /mnt/c/Users/Administrator/Desktop/robonix/robot-mirrorme-bpx
```

窗口 A 保持状态转发，若已运行不要重复启动：

```bash
bash scripts/motion-test.sh relay 10.21.40.1 10.21.40.68
```

默认转发 30 分钟；测试前核对 Windows Wi-Fi IP，观察转发窗口是否退出。
转发器每 10 秒显示包计数、最近包龄和剩余时间，最后一分钟提示即将退出。
窗口 B 保持服务运行：

```bash
bash scripts/motion-test.sh start --confirm-physical-motion-test
```

等 ACTIVE 后，窗口 C：

```bash
bash scripts/motion-test.sh status
bash scripts/motion-test.sh stand --confirm-physical-motion-test
```

确认物理急停可用，App 不同时发送动作。以下每个动作前单独 arm，观察完成后才进行下一项。

## 2. 距离闭环：先补证据，不先调参数

在地面标记起点和初始机体方向，用卷尺测机体同一点最终沿初始朝向的投影位移。
窗口 C 逐条执行：

```bash
bash scripts/motion-test.sh arm --confirm-physical-motion-test
bash scripts/acceptance.sh move --forward-m 0.2 --duration-sec 10
bash scripts/motion-test.sh status
```

0.2m 是本次建议的短距离采集目标，不保证当前闭环一定成功。超时也保留数据并返回
非零退出码，不会自动重试。每次输出独立目录 `.artifacts/acceptance/<时间>-<随机后缀>/`：

- `capture.jsonl`：请求参数、客户端时间、完整 ROS odom、RPC 返回和结束记录。
- `motion_status` 记录：反馈包龄/原厂时间戳、首次故障、目标速度和适配层输出快照。
- `report.json`：`projected_distance_m`、`distance_remaining_m`、横向偏移、转角和采样间隔。
- `status-before.json` / `status-after.json`：解锁及故障状态；另存运行镜像 ID 和 Git HEAD。

记录卷尺实测值，例如**确实测得**沿初始方向前移 0.18m 时才运行：

```bash
python3 scripts/analyze_acceptance.py .artifacts/acceptance/实际目录/capture.jsonl \
  --measured-distance-m 0.18 --output .artifacts/acceptance/实际目录/measured-report.json
```

分析为离线操作，不连接机器人；拒绝覆盖报告。对比三者：目标距离、odom 投影距离、
外部实测距离。重复至少 3 次记录重复性（人工逐次决定执行）；确认前进可控后再用
`--forward-m -0.2` 检查后退，后方要留出空间。不自动判定物理精度通过：当前 2cm
是软件容差，项目可接受的实测精度及测量方法仍需确定。

## 3. 角度闭环、正反向和整圈

20cm 和正向 15° 已在 2026-10-14 新版通过，无需仅为证明动作发生重复测试。
以下保留小角度命令作参考；下一项优先补反向角度及外部测量：

```bash
bash scripts/motion-test.sh arm --confirm-physical-motion-test
bash scripts/acceptance.sh move --rotate-deg 15 --duration-sec 10
```

查看 `rotation_deg`、`angle_remaining_deg`，用地面方向标记/外部视频量角核对。
反向将角度改为 `-15`，也必须重新 arm。外部角度记录方式：

```bash
python3 scripts/analyze_acceptance.py .artifacts/acceptance/实际目录/capture.jsonl \
  --measured-angle-deg 实际有符号角度 --output .artifacts/acceptance/实际目录/measured-report.json
```

2026-10-14 小角度已满足软件容差，最终实测精度仍待测量。小角度、方向、停止
验证通过后，再由现场人员决定整圈测试：目标 `--rotate-deg 360 --duration-sec 25`
或 `-360`。租期为 30 秒，arm 到请求之间的时间会消耗租期，应立即执行请求，不能为追求通过而
关闭租期保护。整圈仍需另行验收，不因小角度执行成功而勾选。

## 4. 低速响应与横移

已有 0.2m/s 能移动的证据；在相同地面、姿态条件下人工逐次采集 0.1、0.15、0.2m/s，
每次 1 秒，观察能否起步、odom 位移、停止情况。示例：

```bash
bash scripts/motion-test.sh arm --confirm-physical-motion-test
bash scripts/acceptance.sh move --linear-x 0.15 --duration-sec 1
```

不要把速度×时间当作精度目标，因为控制有加速过程。记录地面、固件、电量和负载。
横移未验收，确认侧方空间后可单独用 `--linear-y 0.1 --duration-sec 1` 采集，反向用
负号；未起步不代表接口未执行，也不应立即加速。定时模式 success 仅表示时长完成。

## 5. 取消、RPC deadline 和租期

物理急停准备好。窗口 C 开始一次有界定时速度，窗口 D 人工停止：

```bash
# C：先单独 arm，然后：
bash scripts/acceptance.sh move --linear-x 0.2 --duration-sec 5
# D：动作期间执行：
bash scripts/motion-test.sh stop
```

预期动作取消、status 为 DISARMED、机器人停止；需视频或外部计时确认停止上界，
本工具没有足够证据自动给出物理停止时间。

RPC deadline 测试（每次先单独 arm）：

```bash
bash scripts/acceptance.sh move --linear-x 0.2 --duration-sec 5 --timeout-s 1
```

预期客户端 deadline 失败、服务端取消，随后 status 为 DISARMED。异常时用 stop/物理急停。

租期先做不发速度的静止测试：

```bash
bash scripts/motion-test.sh arm --confirm-physical-motion-test
sleep 31
bash scripts/motion-test.sh status
```

应 DISARMED；不要自动重新 arm。此测试不证明运动中租期到期的停止性能。

连续 `twist_in` 的停发看门狗与定时 move 是两条不同路径。窗口 C 先运行纯观察
`bash scripts/acceptance.sh observe --seconds 20`；窗口 D 人工 arm 后发送 20 条
20Hz 的 ROS Twist（约 1 秒；首次发现可能有额外等待）：

```bash
docker exec rbnx_mirrorme_bpx_quadruped bash -lc \
  'source /opt/ros/humble/setup.bash && timeout 10 ros2 topic pub --rate 20 --times 20 /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.2}, angular: {z: 0.0}}"'
bash scripts/motion-test.sh status
bash scripts/motion-test.sh stop
```

发布停止后应由 0.25 秒命令看门狗归零，但租期未到时可能仍是 ARMED，这是设计行为；
随后显式 stop 撤销解锁。记录实际是否移动、停发后是否停止；若发现耗时超过租期导致
没有动作，记录为无效测试，不自动补发。不要把这项与 move 的“结束即 DISARMED”混淆。

## 6. 控制权交还

先静止，执行 stop，若需要趴下则先 sit，然后 release，确认 released=true 且
lifecycle=shutdown，再由操作者用 App 单独试前进/转向，记录恢复时间和现象。
release 显式关闭 SDK 会话；容器仍存在以便读取诊断，不能再 arm/站趴或远程 activate。
需要重新取得 SDK 控制时先 shutdown 再 start。不要同时向 SDK 和 App 发运动。
当前已知 App 在完整 shutdown 后恢复；新 release 路径的实际交还效果仍待现场确认。

```bash
bash scripts/motion-test.sh stop
bash scripts/motion-test.sh sit --confirm-physical-motion-test
bash scripts/motion-test.sh release
bash scripts/motion-test.sh status
# 此时人工检查 App；完成后清理服务：
bash scripts/motion-test.sh shutdown
docker ps --format '{{.Names}}'
```

## 7. 状态链路中断、异常退出

先在静止 DISARMED 状态验证状态中断：窗口 C 运行纯观察工具，窗口 A Ctrl+C 结束
状态转发（不要终止运动服务）；窗口 D 检查 status。

```bash
bash scripts/acceptance.sh observe --seconds 40
# 另一个窗口检查：
bash scripts/motion-test.sh status
```

预期状态过期、内部 FAULT，不自动恢复解锁；重新启动 relay 后记录状态。
确认反馈持续恢复、故障原因已排除再人工 `clear-fault`，应恢复 DISARMED。
断网时没有反馈，不能凭 odom 判断机器人已经物理停止。

运动中断网、SIGKILL、主机掉电与整机重启属于下一阶段破坏性/故障注入验收：先
确认机器人端 watchdog 上界、物理急停与现场防护，再编制现场步骤。这里不提供
自动杀进程或自动断网的动作序列；SDK 原生 sender 可在主机逻辑失效时继续工作，
离线 watchdog 通过不能替代它。正常 SIGTERM 退出已由 shutdown 路径覆盖，仍需
测量运动中退出的物理停止时间。

## 8. 原点、标定和其他交付项

- Odom 初始朝向、SDK 重连和整机重启：使用 `HARDWARE_TEST_GUIDE.md` 第 15 节的
  `odom_acceptance capture/compare`；先 shutdown 运动服务，避免两个 SDK 会话争用。
  整机重启由现场人员执行，记录机器人姿态是否变化、固件版本和采集阶段。
- IMU 外参、关节方向/零位、物理尺寸和单位：逐轴外部测量并记录对照值，不能仅凭
  JSON 字段有限或长度正确就验收通过；不调用 zero-position 校准命令。
- 原生 Ubuntu 22.04：复跑离线 suite 和只读真机指南，不能将 WSL 结果等同生产主机。
- SDK SBOM/第三方审计：依据 wheel 原生库、许可证和上游依赖清单单独审计，不是运动脚本验收项。

## 记录限制

新工具通过 ROS 订阅 `/odom` 并调用标准 move RPC，不启动第二个 SDK 会话，不自动 arm。
同时以约 10Hz 采集 `/bpx/motion_status`，服务端以约 5Hz 记录 move_progress。
`adapter_output` 是适配层接受的输出快照，不是实际测量速度、固件 ack 或每周期完整发送记录。
分析以客户端请求/返回时间窗口估算，存在 RPC 开销和 ROS 延迟；采样缺失、坐标跳变、
参考系变化会降低可信度。报告不自动给出“物理精度通过”，也不将所有 timeout 视为没运动。
