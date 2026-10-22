# M6：Soma 与部署能力对齐

原问题：所有现场启动模式共用 soma.yaml，但描述声称可站/趴且 exports 为空。
只读身份的自然语言能力与实际接口不符，Soma 无法通过 body exports 找到对应 provider。

现在默认 soma.yaml 只描述 dev.2 发布身份，body 导出 odom/posture；其他身份明确选择
各自的 soma.*.yaml。所有配置共用原有 URDF、base_link 和厂商模型质量，不填猜测尺寸。

| 身份 | Soma 文件 | provider_id | 导出 |
| --- | --- | --- | --- |
| 默认发布 | soma.yaml | mirrorme_bpx | odom、posture |
| 无运动 | soma.no-motion.yaml | 无 | 无 |
| SDK 只读 | soma.sdk-read-only.yaml | mirrorme_bpx_state | odom |
| 回放 | soma.replay-state.yaml | mirrorme_bpx_replay | odom |
| fake 状态 | soma.fake-state.yaml | mirrorme_bpx_quadruped | odom、twist_in（运动禁用） |
| 现场 motion-test | soma.motion-test.yaml | mirrorme_bpx_motion | odom、twist_in、move |
| fake motion-test | soma.motion-test-fake.yaml | mirrorme_bpx_motion | odom、twist_in、move |
| 现场 posture-test | soma.posture-test.yaml | mirrorme_bpx_posture | odom、posture |

能力路径前缀均为 robonix/primitive/quadruped/。motion-test 的站趴是本地操作者接口，
未虚构远程 posture capability；未加入导航、低层关节控制或新发布能力。

start-sdk-read-only-docker.sh 根据实际选择的身份传入 Soma 文件；固定 Robonix
会注入当前 deployment_manifest，保证临时现场清单不会被默认发布清单替代。
静态部署也显式选择对应配置。description.can_do/cannot_do 明确模拟、只读、发布和
未发布运动能力及其限制。生成文件由下列命令维护：

```bash
python3 scripts/generate_soma_profiles.py
python3 scripts/generate_soma_profiles.py --check
```

新增跨文件回归核对每个部署的 provider_id、完整能力集合、模型路径和生成文件一致性。
离线全流程报告：`.artifacts/offline/20261015T084945967445Z/report.json`。
本轮不连接真机 SDK，不启动真实运动身份。

M6 仍待外部输入：本体 IMU 实际 frame/外参、实际物理尺寸，以及 RViz 人工渲染检查。
这些项不以 YAML 校验或 fake TF 通过代替。M8 的厂商原生依赖审计和生产宿主机验证
也不因本次部署配置完成而自动关闭。
