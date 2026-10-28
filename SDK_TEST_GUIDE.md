# SDK 1.0.9：简洁测试步骤

dev.4 默认 SDK 1.0.9，保留 1.0.8 回退；本发布不支持 1.0.10/1.0.11。
仅测试现有 Robonix 接口。离线兼容已验证，真机结果待操作者确认。

## 1. 构建与启动

先在 WSL 构建新版镜像（旧镜像内仍可能限制 SDK 1.0.8）：

```bash
cd /mnt/c/Users/Administrator/Desktop/robonix/primitive-mirrorme-bpx-quadruped-rbnx
bash scripts/build-container.sh
```

确认机器人静止，关闭旧测试部署。每个操作窗口先进入 Robot 仓库：

```bash
cd /mnt/c/Users/Administrator/Desktop/robonix/robot-mirrorme-bpx
export BPX_PROVIDER_ID=mirrorme_bpx
```

窗口 A 保持 relay（替换为 Windows 当前网卡 IP；已有 relay 不重复启动）：

```bash
bash scripts/motion-test.sh relay 10.21.40.1 <Windows当前IPv4>
```

窗口 B 保持服务运行，默认选择本地 `.deps/sdk/` 中的固定 1.0.9 wheel：

```bash
bash scripts/motion-test.sh start-unified --confirm-physical-motion-test --robot-ip 10.21.40.1
```

窗口 C 核对版本和反馈：

```bash
docker exec rbnx_mirrorme_bpx_quadruped python3 -c 'import bpx_sdk; print(bpx_sdk.__version__)'
bash scripts/motion-test.sh status
bash scripts/acceptance.sh observe --seconds 40
```

预期版本 1.0.9、ACTIVE、fault 为空、feedback_ready=true、输出零。
启动不自动站立。默认 relay 30 分钟到期，测试前确认仍在转发。

## 2. 逐项人工测试

有现场监护和停止手段，逐条执行并观察，无需 arm：

```bash
# posture：站立
bash scripts/motion-test.sh posture stand
# move：前进 0.1m
bash scripts/motion-test.sh forward --forward-m 0.1 --duration-sec 10
# move：正反向各 15 度
bash scripts/motion-test.sh rotate --rotate-deg 15 --duration-sec 10
bash scripts/motion-test.sh rotate --rotate-deg -15 --duration-sec 10
# move：限时速度
bash scripts/motion-test.sh velocity --linear-x 0.25 --duration-sec 1
bash scripts/motion-test.sh status
```

预期 RPC 成功、动作正确、结束后停止。超时不能只因实际动了就判成功。
可另开窗口 `bash scripts/acceptance.sh observe --seconds 120` 留存运动反馈。

## 3. Twist 停发归零

已站立、反馈健康时执行：

```bash
docker exec -e ROS_DOMAIN_ID=225 rbnx_mirrorme_bpx_quadruped bash -c 'source /opt/ros/humble/setup.bash; timeout 2 ros2 topic pub --rate 20 /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.1}, angular: {z: 0.0}}"'
sleep 1
bash scripts/motion-test.sh status
```

确认消息实际发布/接收，停发后输出归零、机器人停止。timeout 退出码 124 正常；
0.1m/s 可能处于低速死区。异常时使用另一个窗口的 `bash scripts/motion-test.sh stop`；
通讯异常时使用现场物理停止手段。

## 4. 趴下、生命周期、释放与退出

```bash
bash scripts/motion-test.sh posture sit
bash scripts/motion-test.sh deactivate
bash scripts/motion-test.sh activate
bash scripts/motion-test.sh status
bash scripts/motion-test.sh release
bash scripts/motion-test.sh status
docker logs --timestamps rbnx_mirrorme_bpx_quadruped > sdk-1.0.9-provider.log 2>&1
bash scripts/motion-test.sh shutdown
```

预期重新激活不重放动作；release 后 released=true，人工确认 App 控制恢复。
shutdown 不自动趴下；最后关闭 relay。保留 `.artifacts/acceptance/` 和 provider 日志。
SDK 1.0.8 回退：重新启动时用 `--sdk-wheel /绝对路径/1.0.8的固定wheel` 指定。
