# BPX Robonix posture 服务真机验证记录

本文记录隔离的 `posture_test` Primitive 身份在真机上的首次顺序 stand/sit RPC
状态闭环。该结果随后作为 `v0.1.0-dev.2` 正式发布身份采用同一 posture runtime
的真机依据；测试身份本身仍不提交 Catalog。

## 测试基线

- 日期：`2026-09-03`
- 机器人临时地址：`192.168.1.237`
- Robonix provider：`mirrorme_bpx_posture`
- Primitive manifest：`package_manifest.posture-test.yaml`
- SDK：`bpx_sdk_open` v1.0.8 x86_64 wheel
- Wheel SHA-256：`6a0bcb708c55605dfbfeead6c84141f474505f1c01efbdb564e3dfa4549889c7`
- 调用客户端：`scripts/call-posture-test.sh`

该测试身份仅接入 `MotionLevelControl.setStandUp()` 和
`MotionLevelControl.setSitDown()`。它不创建 `JointLevelControl`，也不暴露
`twist_in`、`move`、速度、步态、阻尼或 zero-position 命令。

## 操作者报告的 RPC 结果

顺序执行：

```bash
bash scripts/call-posture-test.sh stand
bash scripts/call-posture-test.sh sit
```

stand 返回：

```json
{"message": "standing confirmed: Motion(6)", "posture_name": "stand", "provider_id": "mirrorme_bpx_posture", "success": true}
```

sit 返回：

```json
{"message": "sitting confirmed: LyingDown(0)", "posture_name": "sit", "provider_id": "mirrorme_bpx_posture", "success": true}
```

## 结论与边界

本次结果证明，在上述基线上，Robonix posture gRPC 调用能够到达指定 provider，
stand 请求在真机状态反馈到达 `Motion(6)` 后成功返回，随后 sit 请求在状态反馈
回到 `LyingDown(0)` 后成功返回。顺序 stand/sit 的 RPC、SDK 命令和 MotionState
反馈闭环通过。

现场操作员随后确认本次站立和趴下动作物理表现正常，没有观察到意外平移、不稳定
或异响。该人工结论没有配套视频，因而记录为操作者确认，而不是可独立复核的视频
证据。

两条 JSON 结果和操作者确认不能证明急停有效，也不能证明并发 RPC 拒绝、断网、
状态过期等故障路径已经在真机通过。结果上报后复查当前主机，两个 BPX 测试容器均
不存在，UDP 9873 也没有监听残留。并发 RPC 拒绝已由离线测试覆盖，真机故障注入仍
保留为后续增强项。

dev.2 正式发布身份 `mirrorme_bpx` 因此提供 `odom` 和严格白名单的
`stand`/`sit` posture；它不提供 `twist_in`、`move` 或关节控制。诊断 provider
`mirrorme_bpx_posture` 继续保留用于复现，但不得提交 Catalog。正式 runtime 的
activate/deactivate/shutdown 不隐式发送姿态命令，避免生命周期操作造成非预期运动。
