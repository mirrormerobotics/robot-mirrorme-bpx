# 新开发机离线验收：2026-10-12

结果：**离线验收通过；未连接真机。**

## 后续运动开发复验（2026-10-12）

最新证据：`.artifacts/offline/20261012T061136457002Z/report.json`。
全部 12 个阶段通过：Primitive **156** 项、Robot **37** 项测试，runtime 构建及
容器内单测、模型生成/URDF/TF、固定 Robonix 工具链、replay、fake、motion fake
端到端与镜像记录。测试启动的容器在结束时清理。

本次新增连续速度与有界 move、Unix socket 本地解锁租期、单命令通道、反馈故障
锁存、取消/超时/生命周期停止和 SDK 零速度 flush。修复真实时钟下读取状态前取时间
造成的 freshness 误判，并按发布 wheel 的类型声明处理 `setWalk() -> None`。
SDK 方法与声明的断网检查输出在同目录 `sdk-motion-api.json`，未构造或连接机器人。

真实 Atlas/gRPC/ROS 联调验证未解锁拒绝、距离/双向角度/定时移动、RPC deadline
取消和停发 Twist 后归零；完整 ±360°、断连/旧状态、里程计跳变、并发和停止失败
由核心模拟测试覆盖。这些结果不代表物理运动、网络故障或 SIGKILL 已完成真机验收。

新能力限于非发布测试 manifest；默认发布清单未扩展，修改尚未提交或推送。
现场接续见 [MOTION_TEST_GUIDE.md](MOTION_TEST_GUIDE.md)。以下保留首次新机验收记录。

## 基线与环境

- Primitive 起点：`c9a3611f168bf214cce87c446c74a1bb59fcd74c`
- Robot 起点：`84ef19836fb80221b05e7d228fafd688a9d1ab3b`
- 两仓库本地工作分支：`codex/offline-handoff`，包含本次未提交修改。
- Robonix：`f6cacfc4b402eb57c75b553d375c6cfaba11dce7`，三个接口 submodule 固定到记录版本。
- 宿主：Windows 10 build 19045，WSL2 Ubuntu 20.04.5，x86_64。
- Docker Engine：26.1.3；Buildx：0.14.1；WSL Python：3.8.10。
- Runtime：固定 Ubuntu 22.04 / ROS 2 Humble 镜像；工具镜像：固定 Rust 1.91.0。
- 编译与包缓存：`/home/michael/.cache/robonix-bpx`。

原生 Ubuntu 22.04 生产主机验收仍未完成；WSL 结果不能替代它。

## 本次完成的修复

1. `verify-rbnx.sh` 现在同时构建 Atlas/Soma。旧脚本在全新缓存下只构建 CLI/codegen，
   导致整机启动报缺少 `robonix-atlas`；已通过真实启动复验。
2. 两仓库增加换行约定，Robot 的厂商模型保持原始字节，避免 Windows checkout
   改变脚本行为或模型 SHA-256。
3. Odom 比较工具在两份采集都缺失 SDK/机器人版本时明确判为证据不足。
4. 增加 Linux/WSL 离线验收入口及 PowerShell 入口，保留失败日志、不覆盖历史结果，
   并记录源码哈希、命令、退出状态和镜像身份。

## 结果

| 检查 | 结果 |
| --- | --- |
| Primitive 单元/脚本测试 | 138 项通过 |
| Robot 单元/脚本测试 | 37 项通过 |
| Runtime Docker 构建及容器内测试 | 通过 |
| 模型原文件哈希、生成一致性、两份 URDF 的 check_urdf | 通过 |
| base_link 到四个 toe 的动态 TF | 通过 |
| 固定 CLI/codegen/Atlas/Soma 构建 | 通过 |
| rbnx validate 与 codegen | 通过，43 接口包、207 消息、109 服务 |
| replay 整机 | 通过：发现 odom、Driver 停用/恢复、Odom/JointState/TF、关闭清理 |
| fake 整机 | 通过：上述链路及非平面 Twist 拒绝 |
| 测试后 Docker 容器 | 无残留 |
| SDK 发布 wheel 断网安装/导入/API 检查 | 通过：1.0.8、15 个只读 API、无运动方法 |

SDK wheel SHA-256：
`23dec27cd4c90cfe5531fbccf5db15e44c5ec4d4b6d2a76941e61def957db115`。
wheel 保存在同级 `.deps/sdk/`，不加入成果仓库。

## 证据与复现

本机完整验收由 PowerShell 执行：

```powershell
.\scripts\dev.ps1 -Mode full -ProxyUrl http://172.29.32.1:7897
```

11 个阶段全部通过，证据位于
`.artifacts/offline/20261012T024829636676Z/report.json` 及同目录日志。
该报告保存执行时的源码文件哈希，因此即使尚未提交修改也可以核对具体测试内容。
SDK 的独立检查日志保存为 `.artifacts/offline/sdk-verification-20261012.log`。
这些本机证据目录被 Git 忽略；需要分享时单独打包，勿把它们当成已上传的仓库附件。

环境安装、代理变化后的处理及再次运行方法见 [OFFLINE_DEVELOPMENT.md](OFFLINE_DEVELOPMENT.md)。

## 仍待完成

真机相关项目继续以 [ACCEPTANCE.md](ACCEPTANCE.md) 为准：Odom 原点/初始朝向/重连/重启，
时间戳语义、IMU 外参、关节零位、watchdog、急停、控制权仲裁、故障注入与原地一圈。
SDK 内部第三方依赖/SBOM 需要厂商源码审计。通用速度和 move 仍未实现或开放。
本次没有修改发布 tag、推送代码或扩大公开能力。
