# 诊断与控制权释放修复：最小复测步骤

本次完成软件修复和离线验证，没有启动真机 SDK 或下发真实控制命令。
前进和小角度旋转已确认能执行，本轮只复测失败原因与新增释放路径。
距离精度、低速死区及物理故障停止时间仍需现场数据，不能标记为已解决。

验证证据：单测 Primitive 161、Robot 42；构建、模型/TF、工具链、replay/fake 通过。
初次完整离线报告 `.artifacts/offline/20261013T063029311652Z/report.json` 保留 motion
旧消息断言失败记录；修复后 motion 单项通过，见同目录 `motion-retest.log`。
模拟覆盖 move 距离/正反转/定时/取消、ROS watchdog、健康采集和 release。

## 软件变化

- status 和采集日志保留反馈包龄、原厂时间戳、首次故障原因、动作进度、剩余误差、
  目标速度及适配层输出。生命周期 ACTIVE 不代表运动健康，须同时看 safety/fault。
- 明确区分断连、反馈过期、非法反馈、RPC 取消、租期到期、目标超时。
- 距离/角度连续 3 秒没有足够里程计进展时提前报 `move stalled` 并撤销解锁；
  最小进展分别为 3mm/0.008rad。不自动提高速度、不放宽到达容差。
- 新增 release：停止并关闭 SDK 会话，禁止该实例重新取得控制，重启服务后才能再用 SDK。
- UDP relay 每 10 秒显示存活信息，并提示到期；默认仍为 30 分钟。
- 离线 ROS 验收过滤排队旧消息，避免把停止前速度误判为当前速度。

## 1. 加载新版并保持状态转发

每个 WSL 窗口先执行：

```bash
cd /mnt/c/Users/Administrator/Desktop/robonix/robot-mirrorme-bpx
```

若旧服务仍在运行，先确认机器人静止，再执行 `bash scripts/motion-test.sh shutdown`。
若无旧容器则跳过。窗口 A 启动转发；若已有一个转发器则先结束旧进程，避免端口占用：

```bash
bash scripts/motion-test.sh relay 10.21.40.1 10.21.40.68
```

核对 10.21.40.68 仍是 Windows Wi-Fi 地址，确认包计数持续增加。窗口 B：

```bash
bash scripts/motion-test.sh start --confirm-physical-motion-test
```

保持 A/B 开启。窗口 C 等服务 ACTIVE 后执行：

```bash
bash scripts/motion-test.sh status
bash scripts/acceptance.sh observe --seconds 15
```

确认 safety=disarmed、fault 为空、反馈持续更新。不要将历史 last_fault 单独当成当前故障。
若有 FAULT，先排除状态链路问题，再人工 clear-fault；不要直接尝试运动。

## 2. 一次短距离诊断

准备好物理急停、前方空间和卷尺；App 不同时发命令。逐条执行并观察：

```bash
bash scripts/motion-test.sh stand --confirm-physical-motion-test
bash scripts/motion-test.sh arm --confirm-physical-motion-test
bash scripts/acceptance.sh move --forward-m 0.2 --duration-sec 10
bash scripts/motion-test.sh status
```

失败退出码会保留证据，不会自动重试。记录本次终端打印的 `.artifacts/acceptance/...` 目录。
若再次停在目标前：看 report 的 server_last_move、last_fault，以及 capture 中的
motion_status。`stalled` 表示缺乏里程计进展，`feedback stale` 表示反馈过期，
`timeout` 表示时限内未达到容差；三者都不等于完全没运动。
若仍失败，先保留本次证据，不继续整圈或扩大速度。

用卷尺实测机体同一点沿初始方向的投影位移，然后替换以下两个占位值：

```bash
python3 scripts/analyze_acceptance.py .artifacts/acceptance/实际目录/capture.jsonl \
  --measured-distance-m 实测米数 --output .artifacts/acceptance/实际目录/measured-report.json
```

只有状态稳定且短距离结果已确认，才按需复测此前反馈故障的角度请求（非重复证明能转）：

```bash
bash scripts/motion-test.sh arm --confirm-physical-motion-test
bash scripts/acceptance.sh move --rotate-deg 15 --duration-sec 10
```

## 3. 验证 SDK 会话释放

机器人静止后逐条执行；sit 为按需操作，须在 release 之前：

```bash
bash scripts/motion-test.sh stop
bash scripts/motion-test.sh sit --confirm-physical-motion-test
bash scripts/motion-test.sh release
bash scripts/motion-test.sh status
```

预期 released=true、lifecycle=shutdown。由操作者切到 App 检查站起/前进/转向，记录
是否恢复与所需时间。如果没有恢复，停止测试并执行下方 shutdown，保留日志。
release 后 SDK 状态不再更新是预期行为，不能用旧 odom 推断 App 的动作。

```bash
bash scripts/motion-test.sh shutdown
docker ps --format '{{.Names}}'
```

需要继续 SDK 测试时重新执行窗口 B 的 start。release 只关闭 SDK 会话，不保证固件
仲裁已通过；实际 App 恢复必须人工确认。不要把 flag=true 当成交还控制权的方法。

## 4. 后续完整验收

上述复测无异常后，再依 [REMAINING_TESTS.md](REMAINING_TESTS.md) 完成低速响应标定、
外部距离/角度精度、正反向/整圈、横移、取消/租期/watchdog、原点/重连/重启验证。
运动中断网或进程强杀需先确认机器人端 watchdog 与现场防护；本页不自动触发。
原生生产主机、IMU/关节外部标定及 SDK SBOM 仍是独立交付项。
