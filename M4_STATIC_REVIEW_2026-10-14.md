# M4 静态复核（2026-10-14）

## 修复完成补录

用户授权后已修改 Primitive `main.py`，下文发现保留为修复前记录。

- 四个生命周期入口共享 RLock，INIT/ACTIVATE/DEACTIVATE/SHUTDOWN 串行处理。
- INIT 仅允许首次执行；后续调用返回 Deferred，保持现有 Atlas 状态，不覆盖 runtime。
  配置、runtime、socket 和 TF 全部成功后才提交全局引用。失败时清理候选 socket、
  runtime 和 ROS 资源并锁定失败状态，要求重启，避免沿用部分初始化的实例。
- ACTIVE 时重复 ACTIVATE 幂等返回，不再次启动 runtime 或发布线程。
- DEACTIVATE 确认发布线程已退出才允许重新激活；超时仍尝试停止 backend，随后禁止
  重激活。SHUTDOWN 幂等，资源清理串行且 ROS 清理置于 finally。

离线回归：新增 6 项 provider 入口测试通过，覆盖 24 次并发 INIT、24 次并发
ACTIVATE、ACTIVE 时 INIT、activate/deactivate 竞争、初始化失败资源清理、线程
退出超时拒绝重启，以及激活失败清理。Primitive 原 167 项和 Robot 42 项也通过。
证据：`.artifacts/m4/20261014T025542-124793.log`。
复验入口：`bash scripts/verify-provider-lifecycle.sh`，隔离网络、模拟 runtime，无 SDK。

M3 真实 ROS 隔离传输回归通过，证据 `.artifacts/m3/20261014T025543-124910.log`。
该次进程退出另有 ROS `cannot use Destroyable because destruction was requested`
异步提示，退出码仍为 0；不将其隐去或声称底层 ROS 退出完全无警告。本次没有修改
固定上游 RosBackend。未启动真机服务、未切换现场生命周期、未提交或推送改动。

本次两项缺陷已修复并完成离线回归；最新代码的完整 Atlas/build 全套复验未在本轮执行。

## 修复前静态检查记录

范围：本地两个仓库当前工作区、固定 Robonix Python Driver 源码与已有构建/验收记录。
只读检查，没有连接开发板、启动服务、调用 Driver 或发送运动命令；没有修改运行程序。
结论：能力与部署隔离基本一致，生命周期重复/并发调用存在未覆盖缺口，不能认定 M4 全部通过。

## 发现

1. **P1：重复 INIT 会覆盖仍在使用的 runtime，可能遗留 SDK 会话。**
   `bpx_quadruped/main.py:249` 的 on_init 没有状态检查或互斥锁，263 行直接赋值
   `_runtime = build_runtime(...)`，既不拒绝 ACTIVE 时 INIT，也不关闭旧 runtime。
   motion 身份旧 watchdog 线程仍引用旧实例，后续 socket 创建又可能因旧 socket
   存在失败；这会使新旧资源混杂。固定 Robonix `lifecycle.py:408` 直接调用 INIT
   handler，没有提前拦截；gRPC 使用 8 个工作线程，不能依赖上游自动串行化。
   建议明确 INIT 可接受状态，拒绝运行中重初始化，串行化入口；初始化失败必须清理
   本次创建的资源，成功后再替换全局引用。

2. **P2：重复 ACTIVATE 会启动多个发布线程。**
   `main.py:309` 每次调用都会执行 323 行的 Thread 创建，底层 runtime 的幂等
   activate 并不能保护外层线程。重复调用后旧线程引用被覆盖，Odom/TF/健康消息重复
   发送，共享 IMU/关节去重器发生竞争；停止时只 join 最后一个线程。建议同一实例
   ACTIVE 时幂等返回，入口加生命周期锁，停止时确认发布线程退出后才能重新激活。
   这可能不增加 DDS publisher 数量，因此既有“唯一发布者”测试不足以覆盖此问题。

以上为源码路径确认的缺陷，本轮没有在真机触发复现。

## 原 M4 条目核对

| 项目 | 结果 |
| --- | --- |
| 固定 Robonix commit | 本地 HEAD 为 f6cacfc4b402eb57c75b553d375c6cfaba11dce7，与脚本一致 |
| provider 实例命名 | start.sh 传入 RBNX_INSTANCE_NAME，固定 robonix-api 优先采用该值 |
| 发布能力 | 默认/x86 声明 odom + posture；posture 精确白名单 stand/sit |
| 只读与 replay | 仅 odom，未注册运动 RPC，不创建 twist 订阅 |
| fake motion-dev | 独立身份、fake backend，odom + twist_in |
| motion-test/fake | 独立非发布身份，odom + twist_in + move；本地解锁门禁保留 |
| move 类型复用 | 使用 chassis protobuf 消息，但注册 quadruped/move，不是导航/chassis 能力声明 |
| 配置校验 | 未知字段、有限值/限幅、backend 与运动模式组合、能力环境门禁均有校验 |
| M3 新话题 | IMU、JointState、diagnostics 与 motion_status 为内部 ROS topic，declare=False |
| 生命周期 | 正常顺序有既有证据；重复 INIT/ACTIVATE 和并发入口未通过本次静态复核 |
| 文档与发布边界 | CAPABILITY 保留禁止导航/低层关节及 motion 非发布约束；本地新增代码尚未推送 |
| validate/codegen/build | 20261013T063029311652Z 报告相关阶段通过；不能视为本轮最新代码重新构建通过 |
| fake/replay/motion | 历史 fake/replay 通过；motion 初次旧消息断言失败，修复后单项通过，证据保留 |

下一步应先修复以上生命周期入口缺口并增加离线重复/并发及 INIT 失败清理回归，
再更新 M4 完成状态。不需要发真机运动命令。
