# 用户脚本命令行参数

所有用户操作脚本均支持 `--help`，不需要手动设置 BPX 配置环境变量。
选项可写为 `--name value` 或 `--name=value`，带空格的路径需加引号。
文档中的普通 Shell 变量只是用于把相同参数值重复传给命令，不需要 `export`。

## 完整 Deployment

```bash
bash scripts/start-sdk-read-only-docker.sh \
  --sdk-wheel /absolute/path/to/bpx_sdk_open-1.0.8-cp310-cp310-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl \
  --robot-ip 192.168.1.237 \
  --network-mode bridge \
  --runtime-image primitive-mirrorme-bpx-quadruped-rbnx:dev \
  --container-name rbnx_mirrorme_bpx_sdk \
  --primitive-container rbnx_mirrorme_bpx_quadruped
```

仅 `--sdk-wheel`、`--robot-ip` 必填。其余省略时使用默认值：网络 `auto`、
UDP 9873、状态频率 50 Hz、连接超时 10 秒、ROS domain 223。
可用 `--dry-run` 校验并查看生成的清单而不启动 Deployment。

| 参数 | 用途 | 默认值 |
| --- | --- | --- |
| `--robonix-source PATH` | Robonix 源码目录 | `/tmp/robonix_dev_next` |
| `--expected-commit SHA` | 校验 Robonix 源码版本 | `f6cacfc4b402eb57c75b553d375c6cfaba11dce7` |
| `--tool-image IMAGE` | Robonix 工具镜像 | `mirrorme-bpx-rbnx-codegen:dev` |
| `--runtime-image IMAGE` | Primitive 运行镜像 | `primitive-mirrorme-bpx-quadruped-rbnx:dev` |
| `--container-name NAME` | 外层 Deployment 容器名 | `rbnx_mirrorme_bpx_sdk` |
| `--primitive-container NAME` | Primitive 容器名 | `rbnx_mirrorme_bpx_quadruped` |
| `--target-cache PATH` | Rust 构建产物缓存 | Primitive 仓库下 `.artifacts/rbnx-tool/target` |
| `--cargo-cache PATH` | Cargo 缓存 | Primitive 仓库下 `.artifacts/rbnx-tool/cargo` |
| `--config-cache PATH` | Robonix 配置缓存 | Primitive 仓库下 `.artifacts/rbnx-tool/config` |

指定的工具镜像、commit 和缓存会传给自动准备工具的 `verify-rbnx.sh`。
缓存路径相对于调用命令时的工作目录解析；脚本创建目录后，将路径及符号链接
统一解析为绝对路径，再传给工具准备步骤和 Docker 挂载。

`--robot-state-port`、`--state-rate-hz`、`--connect-timeout-s`、`--ros-domain-id`、
`--docker-host-address`、`--keep-manifest` 等选项可通过 `--help` 查看用途。
默认只读；`--posture-test` 和 `--release-posture` 都必须搭配
`--confirm-physical-posture-service`，不暴露通用速度／关节控制。

## 其他脚本

| 脚本 | 参数 |
| --- | --- |
| `call-posture-test.sh stand\|sit [provider-id]` | `--container-name`、`--robonix-source`、`--primitive-root` |
| `verify-model.sh` | `--image`，默认为固定 ROS 镜像 digest |
| `verify-tf-smoke.sh` | `--image`、`--ros-domain-id`（默认 221）、`--container-name` |
| `test-offline-integration.sh [SOURCE [replay\|fake]]` | `--robonix-source`、`--profile`、`--expected-commit`、`--tool-image`、`--runtime-image`、`--container-name`、`--primitive-container`、`--target-cache`、`--cargo-cache`、`--config-cache` |

调用 posture 时，`--container-name` 必须与启动 Deployment 时一致，provider-id
应匹配所选 profile。该命令会触发真实站立／趴下，只有现场准备妥当才执行。

独立 Odom、录制和运动探针属于相邻 Primitive 仓库，统一使用 `--image`、
`--network-mode`；详见其 `SCRIPT_CLI.md`。世界坐标验收步骤见
[HARDWARE_TEST_GUIDE.md 第 15 节](HARDWARE_TEST_GUIDE.md#15-世界坐标原点sdk-重连与整机重启验收)。

Robonix 内部环境变量传值机制不变。
