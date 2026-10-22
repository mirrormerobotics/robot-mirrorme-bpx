# 无真机开发与交接

当前发布能力仍为 `odom` 与精确的 `stand`/`sit`。离线开发从两仓库的
`feature/operator-cli-odom-handoff` 继续，不把该分支或本地测试误认为新版已发布。
本文入口只运行 fake/replay，不调用 SDK，也不启动默认的真机 Deployment。

本次接手验证结果见 [OFFLINE_VALIDATION.md](OFFLINE_VALIDATION.md)。

## 目录与基线

两个仓库必须是同级目录：

```text
robonix/
  primitive-mirrorme-bpx-quadruped-rbnx/
  robot-mirrorme-bpx/
  .deps/robonix/                # 固定的上游源码，不提交到两个成果仓库
  .deps/sdk/                    # 可选，外置发布 wheel
```

新机器克隆时用 `git -c core.autocrlf=false clone URL`，避免 Windows 改写 Shell
或带 SHA-256 记录的模型文件。仓库的 `.gitattributes` 固定文本 LF，并保留厂商
模型的原始字节。不要用批量格式化工具修改 `description/bpx/`。

固定 Robonix 为 `f6cacfc4b402eb57c75b553d375c6cfaba11dce7`：

```bash
mkdir -p .deps/robonix
git -C .deps/robonix init
git -C .deps/robonix remote add origin https://github.com/syswonder/robonix.git
git -C .deps/robonix fetch --depth 1 origin f6cacfc4b402eb57c75b553d375c6cfaba11dce7
git -C .deps/robonix checkout --detach FETCH_HEAD
git -C .deps/robonix submodule update --init --depth 1 \
  capabilities/lib/common_interfaces capabilities/lib/rcl_interfaces \
  capabilities/lib/unique_identifier_msgs
```

## Windows / WSL2 环境

开发需要 Git、Bash、Python 3.8+、ripgrep、Docker Engine 和 Buildx。
ROS 2 Humble/Python 3.10 在固定 Ubuntu 22.04 镜像中运行，不要求安装 Windows ROS。
Rust 工具链由固定 Rust 1.91.0 镜像提供。

本次接手机器使用已有的 `Ubuntu-20.04` WSL2，在其中安装 Docker Engine 26.1.3
和 Buildx 0.14.1，未安装 Docker Desktop。常用检查：

```powershell
wsl -d Ubuntu-20.04 -- docker version
wsl -d Ubuntu-20.04 -- docker buildx version
wsl -d Ubuntu-20.04 -- systemctl is-active docker
```

对新的 Ubuntu WSL（启用 systemd 后），可使用发行版软件源安装：

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-buildx git python3 python3-venv python3-yaml ripgrep
sudo systemctl enable --now docker
sudo usermod -aG docker "$(id -un)"
# 新开一个 WSL 会话，使 docker 组生效，再执行 docker version。
```

编译缓存默认放在 Linux 的 `~/.cache/robonix-bpx`，避免在 `/mnt/c` 编译大量
Rust 依赖。源码仍可在 Windows 工作区编辑。

## 网络代理

如果 GitHub / Docker Hub 直连失败，需要分别配置 Git、Docker daemon、
Docker 客户端/构建容器。不要关闭 TLS 校验或更换已经固定的镜像 digest。

本机 Windows 现有代理端口为 7897。WSL 到 Windows 的当前地址可用
`ip route show default` 查看；本次为 `172.29.32.1`。它不是可移植的固定地址，
WSL 网络重建后需重新核对。确认代理允许来自 WSL 的访问后，可测试：

```bash
curl -I -x http://WINDOWS_HOST:7897 https://github.com
```

本机 daemon 配置位于
`/etc/systemd/system/docker.service.d/robonix-proxy.conf`，用户容器/构建代理位于
`~/.docker/config.json` 的 `proxies.default`。更改 daemon 配置后执行
`sudo systemctl daemon-reload && sudo systemctl restart docker`；先确保没有运行中的
开发容器。代理地址变化时，两处配置都需更新。保留已有 Docker 配置的其他字段。

BuildKit 获取 registry token 还可能依赖发起命令的进程环境，完整验收可在
PowerShell 用 `-ProxyUrl` 传入；它不会将代理写入仓库或修改系统设置。

## 统一离线验收

在 Robot 仓库根目录，PowerShell：

```powershell
.\scripts\dev.ps1 -Mode unit
.\scripts\dev.ps1 -Mode full -ProxyUrl http://172.29.32.1:7897
```

也可直接在 WSL/Linux 的 Robot 仓库根目录执行：

```bash
python3 scripts/verify_offline.py --mode unit
python3 scripts/verify_offline.py --mode full
```

`unit` 执行两仓库测试和确定性 URDF 检查，不需要 Docker 或 SDK。
`full` 进一步构建 runtime（含容器内测试）、校验模型和 TF、构建固定 Robonix CLI
与 codegen、执行 validate/codegen，最后顺序运行 replay 和 fake 整机集成。
工具链步骤同时构建 Atlas 和 Soma，避免新机器只有 CLI 却无法启动整机。
全新机器需要联网下载固定镜像、系统包和 Rust/Python 依赖；这里的“离线”指无真机。

输出在 `.artifacts/offline/<UTC时间>/`。`report.json` 保存源码 commit、工作区状态、
源码文件 SHA-256、每阶段命令、退出码、日志哈希和镜像身份。任何阶段失败立即停止，
保留日志且返回非零；`--output-dir` 必须是新目录，不覆盖先前证据。
`hardware_tested` 始终为 `false`。默认每阶段超时 3600 秒，可用 `--timeout-s` 调整。

集成测试使用固定本地 Atlas 端口 50051 以及独立 ROS domain。执行前结束自己先前的
BPX 测试，不要与其他整机启动并行运行。工具不会清理其他项目的容器。

## 外置 SDK 的离线检查

从 SDK 官方 `v1.0.8` Release 获取 CPython 3.10 Linux x86_64 wheel，放入
`.deps/sdk/`。校验值应为
`23dec27cd4c90cfe5531fbccf5db15e44c5ec4d4b6d2a76941e61def957db115`。
Primitive 根目录运行：

```bash
bash scripts/verify-sdk-wheel.sh /absolute/path/to/the-release.whl
```

该工具在 `--network none` 容器中校验、安装、导入并检查 API；不连接机器人。
它不代表真机、固件兼容或第三方依赖审计已经通过。

## 有真机后接续

按 `HARDWARE_TEST_GUIDE.md` 第 15 节采集启动原点、初始朝向、SDK 重连、整机重启
数据，再用 Primitive 的 `odom_acceptance compare` 分析。缺少 SDK/机器人版本、
冻结/断连数据或采集未完成时，报告为证据不足，不给出连续/重置候选结论。

其他开放项保留在 `ACCEPTANCE.md`：IMU 外参、关节方向/零位、机器人 watchdog、
急停与控制权仲裁、真机故障注入、原生生产主机复验和 SDK 内部 SBOM 审计。
通用速度与 move 已加入独立测试配置，操作与现场清单见 `MOTION_TEST_GUIDE.md`。
离线测试通过不扩大发布能力，也不代表物理停止或运动精度已验收。
