# BPX 真机只读接入检查表

此表先用于 SDK 只读 profile。所有项目填写并复核前，不进入运动测试。

## 资产与版本

- [ ] BPX 正式型号、序列号：`__________`
- [ ] 机器人固件版本：`__________`
- [ ] 运动主机固件版本：`__________`
- [ ] SDK 固定提交：`19cb373a8d2f8e19eaab6a1441167f3287cc95dd`
- [ ] wheel SHA-256：`6a0bcb708c55605dfbfeead6c84141f474505f1c01efbdb564e3dfa4549889c7`
- [x] SDK LICENSE/NOTICE 和 wheel 再分发范围已确认为 Apache-2.0
- [ ] SDK 原生库和 wheel 的第三方依赖/SBOM 已完成内部源码审计
- [ ] 官方模型与目标硬件版本一致

## 主机与网络

- [ ] x86_64 主机型号、CPU、内存和宿主系统版本已记录
- [ ] Docker 版本、镜像 digest 和 ROS_DOMAIN_ID 已记录
- [ ] 独立有线网卡、主机 IP/掩码、机器人 IP、UDP 端口已记录
- [ ] 路由确认数据包直接走机器人网卡，不经默认网关/VPN
- [ ] 主机防火墙规则已确认，抓包不会包含业务敏感网络
- [ ] 机器人与测试主机时钟行为已记录；厂商毫秒计数不作为 ROS wall clock

## 现场安全

- [ ] 操作员可立即触发物理急停并验证其有效
- [ ] 遥控器、App、SDK、急停的控制优先级有书面说明
- [ ] 机器人电量、机械状态、地面、净空和人员隔离符合测试要求
- [ ] 首次只读测试不启动任何运动/关节控制 session
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

- [ ] LegOdom position、orientation、body velocity 的轴向和单位
- [ ] 四元数分量顺序为 XYZW，实际 norm 稳定
- [ ] 12 个关节的索引、角度正方向、零位和速度单位
- [ ] 力矩单位确认后再决定是否发布 JointState effort
- [ ] IMU 安装方向、frame、外参和协方差来源
- [ ] battery level/current 与 motor/driver temperature 的单位和异常值
- [ ] 各 vendor timestamp 的单位、epoch、wrap、reset 和跨字段同步关系

只读验收结果填入 [ACCEPTANCE.md](ACCEPTANCE.md)。任何意外运动立即停止测试，
保留日志并按安全事件处理。
