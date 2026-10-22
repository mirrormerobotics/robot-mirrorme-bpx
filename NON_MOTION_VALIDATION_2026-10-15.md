# 非运控收尾（2026-10-15 晚间）

范围：本地离线检查、机器人 SSH 只读资产采集、最后关闭当前开发板。
未调用 arm、stand/sit、速度、转向、move、遥控或 SDK 运动接口。

## 完成

- RViz 2 实际渲染：无网络容器、ROS_DOMAIN_ID=229，仅合成 JointState 与本地模型。
  首次发现话题中的相对 mesh URI 无法解析，新增 `scripts/prepare_rviz_model.py`，
  生成绝对 file URI 的可视化副本；原始便携 URDF 和物理模型保持不变。再次渲染后
  四腿/机身 mesh 完整、Global Status OK、无资源加载错误。
  图：`.artifacts/non-motion/20261015/rviz-model.png`；同目录保存 RViz、RSP、安装日志。
- 生成 SDK wheel 全文件哈希及两份 ELF 的 DT_NEEDED 清单，未导入 SDK、未运行 ldd。
  本地 cp310 x86_64 wheel 与固定 SHA-256 一致；两个 ELF 依赖 libbpx_sdk、libstdc++、
  libc、libm、libgcc_s、libpthread 和动态加载器（具体每库清单见 inventory.json）。
- 记录运行镜像和工具镜像的不可变 image ID、架构、OS 包和 Python 包清单。
  运行镜像 580 个 OS 包、71 个 Python 包；工具镜像 417/8。
  `.artifacts/non-motion/20261015/inventory/inventory.json` 及 SHA256SUMS。
  这是二进制依赖清单，不是完整源码级许可证审计，也不能发现所有静态链接组件。
- 当前板卡 SN、系统版本、五个组件 build_info 和 bin 文件哈希已下载并校验：
  `.artifacts/non-motion/20261015/board-inventory.json`，SHA-256：
  `95aa09cb7d770f1bd9e7e27eb4a82ab7156cf2c4dc3d8401696559f9753b8ad2`。
- 复核 10 月 12 日新 x86_64 开发机的完整离线复现报告，确认全流程通过，更新原 TODO
  遗留未勾选状态；这是 WSL2/Docker 开发变体，不冒充原生生产主机验收。
- 本轮单测 177 + 46 通过，模型生成检查通过：
  `.artifacts/offline/20261015T131131946535Z/report.json`。

## 当前板卡资产（不得与下午运动测试设备混用）

| 字段 | 实读结果 |
| --- | --- |
| SSH / SN | 10.21.40.1:60000 / C201JS260715S00014 |
| 架构 / CPU / 内存 | aarch64 / 8 核 Cortex-A55 / 1962 MiB |
| OS / 内核 / 文件系统 | Ubuntu 20.04.6 / BPX Kernel 1.0.13 / BPX FileSystem 1.0.21 |
| app_client | 0.1.6-r3-C2，6b17e9a17d90 |
| bpx_motion | 1.0.15-r24，d0e6eee9c3f6 |
| bpx-stride | 1.0.6-r15，b11af04b984a |
| mcu_agent | 0.1.2-r2，59b9548ca13a |
| infra | 1.0.7-r28，b3b383472dba |

组件 build_info 的平台为 C2，不等于正式整机型号；mcu_agent 版本也不等于 MCU 内部
固件版本。下午日志设备为 C201XC260926S00002，本次不覆盖它的现场验收资产记录。

## 复用方法

在运行 RViz/RSP 的同一环境内生成可视化副本（路径必须能被 RViz 访问）：

```bash
python3 scripts/prepare_rviz_model.py urdf/mirrorme_bpx.urdf /tmp/bpx-rviz.urdf
ros2 run robot_state_publisher robot_state_publisher /tmp/bpx-rviz.urdf
```

副本拒绝覆盖现有文件；需重新生成时使用新文件名。随后由合成 JointState 发布器和
RViz 加载 `/robot_description`，固定坐标设为 base_link；不需要机器人连接。
本轮渲染用本地专用镜像 `mirrorme-bpx-rviz-audit:20261015`，未改变运行镜像依赖。

二进制清单复用 `scripts/inventory_artifacts.py --help`；输出目录须为新目录。

## 保留外部待办

实测 IMU 外参、关节符号/零位、协方差、实际尺寸、时间戳 epoch/wrap、本体重启原点
语义，以及 SDK 所有平台 wheel/内部静态依赖许可证审计，均不能由当前文件与静态
资产读取完成。原生 Ubuntu 22.04 最终生产主机也未提供。这些条目继续保留，不打假勾。

## 关机

采集和离线验收完成后，按用户要求对上述当前板卡执行操作系统关机；结果另行记录。
