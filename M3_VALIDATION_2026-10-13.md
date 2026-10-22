# M3 ROS 数据面实现与验证

## 真机加载新版与只读复验（本日追加）

经用户授权启动新版 SDK read-only 服务：原现场容器已停止，无需终止运动服务。
Atlas/Soma/`mirrorme_bpx_state` 已 ACTIVE，仅声明 odom 和 lifecycle，没有站趴、
速度或 move 接口。启用 IMU 原始 frame `bpx_imu_raw`、Odom TF 和 diagnostics。
未向机器人发送姿态/速度/角速度命令，也未重启机器人本体。

| 30 秒窗口 | Odom | IMU | JointState | TF | diagnostics |
| --- | --- | --- | --- | --- | --- |
| 加载新版后 | 1429 | 1378 | 1379 | 1429 | 286 |
| SDK 会话 deactivate/activate 后 | 1436 | 1371 | 1370 | 1434 | 287 |

两个窗口所有诊断均为 OK/feedback fresh，所有话题均为单一发布者。两轮 TF 分别
1429/1429、1434/1434 与 Odom stamp 匹配。两条 joint 数据均有 12 个关节。
IMU 加速度均值约 [0.0269,-0.0342,9.758]；这是原始测量，不作为安装外参证明。
Driver deactivate 返回 inactive、activate 返回 active，重连后数据恢复。

原始证据在 Primitive `.artifacts/m3/live-20261013-01.jsonl` 与
`live-20261013-02-reconnect.jsonl`，各有 `.report.json`。第一份诊断等级中的
`\u0000` 是 ROS byte 类型的 JSON 表示，即 OK=0；采集器已改为输出可读数字。
离线对比在 Robot `.artifacts/m3/live-reconnect-analysis.json`，含输入 SHA-256。

时间戳两个窗口内均无回退，观察斜率约 1000 和 1029 tick/host-second，仅支持
毫秒量级，不能据此确定精确时基、epoch 或 wrap。重连前后采集端点相差约 2.57cm，
窗口之间有时间间隔且未确认物理静止，不能将其解释为坐标重置或测量精度。
Odom z 约 -3.5m，是 SDK 世界坐标输出，不可直接当成机器人机身离地高度。

目前服务保持只读 ACTIVE，ROS_DOMAIN_ID=223；Windows relay 默认 30 分钟后停止。
操作者需要继续长时采集时应确认 relay 存活，不能把转发结束误判为机器人传感器损坏。

### 可重复的被动采集

```bash
docker exec -w /pkg rbnx_mirrorme_bpx_quadruped bash -c \
  'source /opt/ros/humble/setup.bash && python3 -m bpx_quadruped.m3_capture --seconds 30 --output /pkg/.artifacts/m3/新的唯一文件名.jsonl'
```

该工具只创建订阅，不包含 SDK 或控制接口，拒绝覆盖已有输出文件。

## 先前离线实现与测试

本轮完成可离线验证的程序和真实 ROS 传输测试，未发送机器人控制命令，未重启现场
SDK 容器。测试使用隔离网络容器、合成状态和实际 provider 发布循环；只跳过 Atlas
元数据注册，不以此测试声称新增 Atlas 全链路验收。既有 replay/Atlas 验收见历史报告。

## 数据接口

| Topic | 消息 | QoS | frame / stamp | 发布频率 |
| --- | --- | --- | --- | --- |
| /odom（可配） | nav_msgs/Odometry | best_effort | odom / base_link；本机 ROS clock | odom_rate_hz，默认 50Hz；可含重复厂商帧 |
| /joint_states（可配） | sensor_msgs/JointState | best_effort | 关节名映射固定 URDF；与本次 Odom 同 stamp | 上限 odom_rate_hz；按 joint_ms 去重 |
| /imu/data（可配） | sensor_msgs/Imu | best_effort | 必须显式指定 imu_frame；本机观察时刻 | 上限 odom_rate_hz；按 imu_ms 去重 |
| /tf（可选） | tf2_msgs/TFMessage | tf2 默认 reliable/volatile | odom 到 base_link，严格复用 Odom 样本和 stamp | 与 Odom 相同 |
| /diagnostics | diagnostic_msgs/DiagnosticArray | reliable | provider 名称区分来源；本机 ROS clock | 约 10Hz，上限 odom_rate_hz |

IMU 默认关闭，配置方式见 Primitive 的 IMU_PUBLICATION.md。不猜测 IMU 到 base_link
的变换。IMU 缺失测量以 covariance[0]=-1 表示，存在测量的全零 covariance 按该消息
规范表示未知。Odom 新增 odom_pose_variance/odom_twist_variance 六维正数对角配置，
顺序 x/y/z/roll/pitch/yaw，单位为相应 SI 单位的平方；默认各 1.0 是未校准占位值，
不是测得的误差上界，不应用于未经校准的融合。diagnostics 明确包含该说明。

所有身份均发布反馈健康，断连、过期、未来时间戳、非法状态或读取错误时报告 ERROR，
且不发布对应 Odom/IMU/JointState/TF。motion 身份另包含控制故障与释放状态；
只读身份反馈 OK 仅表示数据新鲜，不意味着已获得控制权或已完成物理校准。

## 验证

- 167 项 Primitive 单测通过。
- 隔离 ROS 容器实测接收 Odom 135、IMU 34、JointState 34、TF 135、诊断 46 条。
- 五个 topic 均只有一个发布者；IMU 缓存帧不重复发布；Odom 与 TF stamp 匹配。
- 注入 stale/非法四元数/disconnected 后，测量发布停止，健康为 ERROR；恢复后为 OK。
- 检查 Odom 非零对角协方差，IMU 缺失/非法字段与规范化；测试不加载 SDK。

WSL 复验（无需启动/停止现有服务，不连接机器人）：

```bash
cd /mnt/c/Users/Administrator/Desktop/robonix/robot-mirrorme-bpx
bash scripts/verify-m3.sh
```

## 不可仅靠程序关闭的原 TODO 项

LegOdom 原点、重连/重启、时间戳 wrap/epoch，真实关节零位/符号、IMU 外参和实测
covariance 仍需物理参照或厂商定义。此前操作员确认 +x 前/+y 左/+yaw 左转可作为
已有证据，但不能代替所有坐标/重启验收。没有为关闭 TODO 而填入虚构实测值。
因此 M3 软件数据面已完成本轮验证，整个物理语义验收仍进行中。
