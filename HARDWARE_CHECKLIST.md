# BPX 真机只读接入检查表

此表先用于 SDK 只读 profile。所有项目填写并复核前，不进入运动测试。

## 资产与版本

- [ ] BPX 正式型号、序列号：`__________`
- [x] SDK 上报机器人软件：`1.0.15`，commit `90561076`，构建时间 `2026-08-28 15:23:13`
- [ ] 正式机器人/运动控制器固件版本：`__________`
- [ ] 运动主机固件版本：`__________`
- [x] SDK 发布候选固定提交：`cab478a5fd3dfce087e0774534bb87b51a3d69e1`
- [x] cp310 x86_64 wheel SHA-256：`23dec27cd4c90cfe5531fbccf5db15e44c5ec4d4b6d2a76941e61def957db115`
- [x] SDK LICENSE/NOTICE 和 wheel 再分发范围已确认为 Apache-2.0
- [ ] SDK 原生库和 wheel 的第三方依赖/SBOM 已完成内部源码审计
- [ ] 官方模型与目标硬件版本一致

## 主机与网络

- [x] 当前 x86_64 开发主机 CPU、内存、WSL2/Ubuntu 版本已记录
- [x] Docker 29.7.2、运行镜像 digest 和 ROS_DOMAIN_ID 223 已记录
- [x] 开发主机 `192.168.1.63`、机器人 WLAN `192.168.1.237/24`、UDP 9873 已记录
- [ ] 正式部署使用独立有线机器人网卡并记录其 IP/掩码
- [x] 当前主机到机器人为直连路由，不经默认网关
- [ ] 主机防火墙规则已确认，抓包不会包含业务敏感网络
- [x] 机器人与测试主机时钟行为已记录；厂商计数单调但实测速率不匹配 ROS wall clock

## 现场安全

- [ ] 操作员可立即触发物理急停并验证其有效
- [ ] 遥控器、App、SDK、急停的控制优先级有书面说明
- [ ] 机器人电量、机械状态、地面、净空和人员隔离符合测试要求
- [x] 首次只读测试只构造 `RequestRobotState`，未启动运动/关节控制 session
- [ ] 现场负责人：`__________`，日期：`__________`

## 只读遥测步骤

1. 保持默认/无运动 deployment 停止，确认没有遗留 BPX Primitive 容器。
2. 先执行 `scripts/run-read-only-probe.sh`，只观察连接和原始字段。
3. 使用 `scripts/record-sdk-replay.sh` 录制短时 JSONL；输出文件不得覆盖已有记录。
4. 保存 audit JSON、原始抓包、固件信息和控制台日志。
5. 启动 `robonix_manifest.sdk-read-only.yaml`，确认 Atlas 只有 `odom`，没有
   `twist_in`。
6. 检查 `/odom` 与 `/joint_states` 的频率、丢帧、时间戳回退、断连和清理行为。

示例：

```bash
primitive-mirrorme-bpx-quadruped-rbnx/scripts/record-sdk-replay.sh \
  /absolute/path/to/bpx_sdk_open-1.0.8-...x86_64.whl \
  /absolute/path/to/bpx-read-only.jsonl \
  --robot-ip 10.21.20.1 --duration-s 30
```

## 坐标与单位确认

- [x] SDK 文档确认 LegOdom position 为 m、body velocity 为 m/s、angular velocity 为 rad/s
- [ ] LegOdom 的物理轴向、原点和正方向需要现场运动参考确认
- [x] SDK 文档确认四元数分量顺序为 XYZW，30 秒实测归一化 norm 稳定为 1.0
- [x] 12 个关节索引到官方 URDF 名称的映射已在真机消息中确认
- [ ] 12 个关节角度正方向、零位和速度单位需要物理姿态确认
- [ ] 力矩单位确认后再决定是否发布 JointState effort
- [ ] IMU 安装方向、frame、外参和协方差来源
- [ ] battery level/current 与 motor/driver temperature 的单位和异常值
- [ ] 各 vendor timestamp 的单位、epoch、wrap、reset 和跨字段同步关系

完整人工操作步骤见 [HARDWARE_TEST_GUIDE.md](HARDWARE_TEST_GUIDE.md)，本次结果见
[HARDWARE_VALIDATION.md](HARDWARE_VALIDATION.md) 和
[ACCEPTANCE.md](ACCEPTANCE.md)。任何意外运动立即停止测试，
保留日志并按安全事件处理。

## 首次站立/趴下调试

只有“现场安全”中的急停、控制优先级、净空/人员隔离和负责人均已填写后，才可按
[POSTURE_TEST_GUIDE.md](POSTURE_TEST_GUIDE.md) 执行。当前只允许：

- [x] 软件实现仅使用一个 `MotionLevelControl`，不接入 `JointLevelControl`
- [x] 只开放 `setStandUp()` 和 `setSitDown()`，速度、步态、阻尼和 zero-position 均无入口
- [x] 确认初始 `LyingDown(0)` 后站立到 `Motion(6)`
- [x] 稳定保持 3 秒，现场操作员确认没有意外平移、不稳定或异响
- [x] 趴下并由状态确认回到 `LyingDown(0)`
- [x] 关键控制台 trace、时间、IP、wheel checksum 和执行参数已写入 `POSTURE_VALIDATION.md`
- [~] 已补充现场操作员观察；正式型号/序列号、固件资产记录和现场视频仍待补

## Robonix posture 服务调试

按 [POSTURE_SERVICE_TEST_GUIDE.md](POSTURE_SERVICE_TEST_GUIDE.md) 启动 posture
Deployment 后：

- [x] `stand` RPC 返回成功，并由真机 `Motion(6)` 状态闭环确认
- [x] 后续 `sit` RPC 返回成功，并由真机 `LyingDown(0)` 状态闭环确认
- [x] 返回的 provider 为 `mirrorme_bpx_posture`
- [~] 已记录 RPC 结果和现场观察；终端 A 完整日志与现场视频仍待保存
- [ ] 真机验证并发 posture RPC 拒绝
- [x] 离线验证 deactivate/shutdown 不隐式发送 posture 命令并完成 session 清理
- [ ] 真机验证断网、状态过期和失败路径
- [x] 结果上报后复查，两个测试容器和 UDP 9873 均无残留

首次顺序 RPC 结果见
[POSTURE_SERVICE_VALIDATION.md](POSTURE_SERVICE_VALIDATION.md)。dev.2 正式发布身份包含
odom 与精确的 `stand`/`sit` posture；测试 provider 不提交 Catalog。

## 手动原地一圈调试

只有首次站立/趴下状态闭环已通过且现场重新完成安全确认后，才可按
[YAW_CIRCLE_TEST_GUIDE.md](YAW_CIRCLE_TEST_GUIDE.md) 执行：

- [x] 软件强制线速度 `x=0`、`y=0`，yaw 绝对值不超过 `1.0 rad/s`
- [x] 使用 LegOdom 累计 yaw 判断 `2*pi`，不是固定时长盲转
- [x] 具备 30 秒默认超时、0.15 m 默认最大平移和 2 秒零速度 flush
- [x] 只有沿命令方向的累计 yaw 才计入目标，反方向超过 0.2 rad 会停止并清理
- [x] 异常路径先发零 yaw、关闭 velocity flag，再有限时请求趴下
- [ ] 操作者手动执行一次默认 `0.5 rad/s` 原地一圈
- [ ] 确认实际旋转方向、角度、最大平移和动作稳定性并保存日志/视频
