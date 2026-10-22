# M5 受控运动：实现与现场验收

## 2026-10-21 最终人工验收结论

操作者明确要求 REMAINING_TESTS.md 全部记为通过，本轮 M5 现场验收按人工确认关闭，
包括运动、停止/取消、控制权交还与故障恢复。历史章节中的待验标记保留作过程记录，
不再作为重复测试要求。独立 yaw-circle 探针不再另行重复验收，采用已接受的
motion-test 整圈验收替代。damping 未纳入当前交付，保持未开放。
原始 RPC 结果和软件分析不变；未提供的物理停止数值、视频或厂商书面文件不作虚构。
这不构成默认发布清单开放 twist/move 的代码变更，也不改变 arm 行为。

## 2026-10-21：release 与退出清理追加通过

操作者补充完整终端输出：release 前 ACTIVE/DISARMED、当前 fault 为空、motion_state=0；
release 返回 accepted=true、SDK session closed。随后 status 为 lifecycle=shutdown、
released=true、health=released、DISARMED、零租期及零输出。执行 shutdown 后
docker ps 输出为空，确认没有运行中的容器。SDK 会话释放和服务退出清理验收通过。

release 后 feedback 是停止采集前的缓存，age_s 约 11 秒，connected=true 不能解释为
SDK 仍保持连接；last_fault 与 last_move 也为历史记录，不是新故障或仍在执行动作。
本输出未包含 App 实际前进/转向恢复情况，控制权交还的 App 侧效果仍待操作者确认；
不将正常 shutdown 清理等同于运动中 SIGKILL/断网的物理停止测试。

## 2026-10-21：操作者报告第五点之前已测，日志复核

依据本次终端附件及当天 12 份 acceptance 记录，确认：

| 项目 | 证据 | 结论 |
| --- | --- | --- |
| 正向 0.2m、反向 0.2m 两次、15° | 084812Z-S6RGwF、084834Z-0sB0GU、084852Z-DDjnEj、084944Z-HxyW0i（均为 20261021T 前缀） | distance/angle reached，结束 DISARMED、零输出 |
| 定时 0.15/0.19m/s 各 1s | 085035Z-OVCIxK、085057Z-M2rnjp | duration completed；不等同于已测得起步阈值或实测精度 |
| 人工 stop 取消 | 085229Z-8dUGxf | move cancelled: local disarm，结束 DISARMED、零输出；接口行为通过 |
| RPC deadline | 085322Z-6n0QPA | 客户端 DEADLINE_EXCEEDED，服务端 RPC cancelled/deadline，结束 DISARMED、零输出；预期故障路径通过 |
| 连续 Twist 停发 | 附件中成功 arm 后发布 20 条 20Hz Twist，随后 status | ARMED、当前 fault 为空、输出三轴为零；停发归零行为有证据，精确 0.25s/物理停止上界未测得 |

四次 local arm required 为门禁拒绝，不能计为完成运动；状态中的 last_fault 是历史
“stand must be confirmed before local arm”，当前 fault 为空时不代表故障仍在持续。
附件最后误输入 stop3，脚本明确拒绝，不能当作执行了 stop。末次状态尚有约 18.4s
租期，因此当时 ARMED/零输出是停发 watchdog 的设计行为，仍需正确 stop 才立即撤销租期。

操作者表述“第五点前全部测试完”按原话保留；文档和聊天的序号不同，本次不将其
擅自扩展为破坏性故障测试已通过。当天记录未包含 release/App 交还及 relay 中断/
恢复的新完整证据，不将其他日期 clear-fault 或旧 last_move 冒充本次验收。
物理停止时间、视频、SIGTERM/SIGKILL、拔网、重启等保留对应待验状态。
本轮仅分析已有记录，未操作真机或更改运动程序。

## 2026-10-15 操作者最终验收决定

操作者明确要求本次正反整圈测试记为通过，故将 **motion-test 正反整圈现场动作
人工验收** 标记通过。证据：20261015T082416Z-PgH1cL、20261015T082507Z-ejLZu5。
这是操作者对实际动作的接受，不更改原始日志或 RPC 结果：软件分别在 -335.63°、
+327.33° 因租期到期结束，软件闭环到达目标判定仍未通过，外部实测精度未验证。
下面“不能标记整圈闭环通过”的历史分析继续适用于软件判定，不否定本次人工接受。
本决定不自动关闭独立 yaw-circle 探针/视频、故障物理停止上界及控制优先级等其他条目。

## 2026-10-15 16:24–16:25：取消平移保护后的复测

最新两份 capture 完整，但均未达到整圈完成条件：

| 目录 | 请求 | 最后服务端累计角 | 结束原因 |
| --- | --- | --- | --- |
| 20261015T082416Z-PgH1cL | -360° / 25s | -335.634327° | local lease expired or motion disarmed |
| 20261015T082507Z-ejLZu5 | +360° / 25s | +327.326710° | move cancelled: local arm lease expired |

服务端单调时钟显示 arm 到 move_start 分别约 6.668s、10.189s，30s 租期只剩
23.332s、19.811s；租期从人工 arm 开始，不从 move 请求开始。两次结束均
DISARMED、输出三轴为零、当前 fault 为空。正向最后进度样本租期仅剩 0.088s。
因此本批证明平移保护不再导致此次提前中止、租期撤销有效，不能标记整圈闭环通过。
先前 16:22 的两份记录分别是未 arm 拒绝与仍含旧平移保护的 rotation deviation。

下次人工测试应预先准备命令，arm 成功后立即调用 acceptance move，避免复制命令
消耗租期；如 25s 仍不够，保留结果再评估实际角速度和动作时间，不自动延长租期。
本轮仅核查日志、更新记录，没有改动程序、重启服务或发运动指令。核查时 Docker
无运行容器，服务日志最终为 ACTIVE -> TERMINATED；这不能代替 release/App 交还验收。

## 2026-10-15：按操作者要求取消 move 旋转平移保护

非发布 motion-test 的角度 move 不再因离起点超过 15cm 而停止，也不再受通用
1.15m 位移上限影响；正反整圈按累计 yaw 完成。直线和定时 move 的位移保护保留。
反向角度检测、反馈新鲜度/突变检查、超时、停滞、租期、取消和停止故障保护保留。
独立 yaw-circle 探针的规则未改变，本修改针对此次 acceptance.sh move 调用路径。
新增正反整圈模拟平移超过 1.15m 的回归，通过后结束 DISARMED/零输出。
旧日志的 rotation deviation 仍是当时版本的真实结果，不能回溯改为通过。
未重启现场服务，运行中的进程需由操作者 shutdown/start 后加载新代码。

## 2026-10-15 16:12–16:16：反向动作和整圈日志复核

新增六份 `.artifacts/acceptance/20261015T08*` 证据。两次请求因 local arm required
被拒绝（首次 -0.2m、首次 -360°），不能计为执行通过。

| 证据目录 | 请求 | 服务端结果 |
| --- | --- | --- |
| 20261015T081313Z-fY4b3B | -0.2m | success，完成时 -0.189643m，DISARMED、输出归零 |
| 20261015T081335Z-eRvSnh | -15° | success，完成时 -13.361089°，DISARMED、输出归零 |
| 20261015T081452Z-M2tjyw | +360° / 25s | rotation deviation，+110.449694° 时停止，FAULT |
| 20261015T081605Z-wtYZHq | -360° / 25s | rotation deviation，-82.640421° 时停止，FAULT |

两个整圈分别在开始后 6.978s / 6.066s 触发保护；故障时反馈 connected=true、
包龄约 20.5ms / 21.2ms。按原始 capture 中最接近 fault 的 odom 样本与服务端起点
计算，水平位移为 0.151124m / 0.153698m（采样时差分别 -0.843ms / +0.556ms），
超过 motion_runtime.py 的 0.15m 旋转平移门限。累计角方向正确，故本次触发的是
平移限制，不是反转、25s 超时、租期或 stale。停止后的适配层输出为零，故障锁存。
末帧位置离起点约 0.163623m / 0.169939m，仍仅是里程计估计，不能当作外部测量。

尚不能区分实际机身平移、里程计漂移或参考点偏置；需要结合现场视频/地面标记。
本次不放宽 15cm 门限、不改变速度，也不自动重试。整圈验收仍未通过。
本批六份采集没有取消、release、断网等新的独立证据，不能仅据“全部执行”关闭
这些项目；此前证据和用户现场观察仍分别保留。

## 2026-10-15：停止失败处理及剩余步骤

本轮修改的是 Primitive 适配程序 `bpx_quadruped/motion_runtime.py`，不是仅增加日志。
此前 disarm 即便 SDK 停止失败也可能只留下 DISARMED，且 move 已写入的成功结果
没有被最终停止异常覆盖。现在 SDK 零命令或关闭速度控制失败会锁存 FAULT，撤销
租期、尝试故障停止；完成动作后的停止失败也将 last_move 改为失败并向调用方抛出
异常。需恢复 SDK/反馈健康、显式 clear-fault 后才允许人工 arm。
这仍不能保证硬件已经停住，物理停止上界需现场或厂商证据。

验证：Primitive **176**、Robot **42** 项测试及模型生成检查通过。
报告：`.artifacts/offline/20261015T074250349971Z/report.json`。
新增测试覆盖最终停止被拒绝、速度控制关闭失败；原测试增加故障锁存和禁止重解锁断言。
未重启现场容器、未加载新代码到运行中的进程、未发送真实运动命令。
未重复运行共用 Atlas/容器名称的全链路 suite，以免与当前真机服务冲突；10 月 14 日
全链路结果是旧版本证据，本轮结果为离线单元回归，不混称新版本真机通过。

### 操作者后续顺序（每条人工执行）

WSL 进入本仓库。先确认机器人静止，然后加载新代码：

```bash
bash scripts/motion-test.sh shutdown
bash scripts/motion-test.sh start --confirm-physical-motion-test
```

start 在独立窗口保持运行；relay 沿用现有实例，无需重复启动。另一个窗口执行
`bash scripts/motion-test.sh status`，确认无当前 fault 且 disarmed。
如机器人未站立，再人工执行 stand。不要重复仅用于证明能动的 20cm/15° 正向测试。

剩余验收按原 TODO 分组：

1. **反向和整圈**：人工 arm 后分别用 `bash scripts/acceptance.sh move --forward-m -0.2 --duration-sec 10`
   和 `bash scripts/acceptance.sh move --rotate-deg -15 --duration-sec 10`。
   每次动作前分别执行 `bash scripts/motion-test.sh arm --confirm-physical-motion-test`，
   观察结束且记录后再进行下一次。方向和停止正常后，整圈用
   `bash scripts/acceptance.sh move --rotate-deg 360 --duration-sec 25`，反向改为 -360。
   保存每次 capture、视频、外部测量。该 move 验证不能自动替代 TODO 中独立
   `YAW_CIRCLE_TEST_GUIDE.md` 探针的指定流程验收，二者证据需明确标注。
2. **取消/超时/停发**：按 REMAINING_TESTS.md 第 5 节分别测试 stop、RPC deadline、
   租期和 Twist 停发，记录物理停止时间。适配层输出归零不能替代外部计时。
3. **控制权交还**：按第 6 节 stop → 可选 sit → release；确认 released/shutdown 后
   人工检查 App 前进/转向，再清理容器。遥控器/物理急停优先级需另有厂商或现场记录。
4. **状态中断/恢复**：按第 7 节在静止时停 relay、恢复、clear-fault，确认仍 DISARMED。
   运动中拔网、SIGKILL、整机重启须有机器人端 watchdog 上界和现场保护方案后实施；
   不能用静止断状态测试代替运动中的物理停止验收。
5. **低速迟滞及材料**：按第 4 节记录地面/负载/电量及定时低速响应，补齐站趴视频。
   damping 仍按原产品决策待定，不自行扩大姿态接口。

本轮已处理可离线复现的停止异常问题并同步 TODO。M5 原退出条件仍未全部满足；
以上现场证据到齐前不发布通用运动能力、不将 M5 标记为全部完成。

## 15:29 真机短动作复测结果

本次读取两份新证据：`20261014T072910Z-0rg6cB`（20cm）、
`20261014T072935Z-kfBDzE`（15°），位于 `.artifacts/acceptance/`。
两次均返回 success，采集完整；所有采样健康为 armed/disarmed，last_fault=null，
结束当前 fault 为空、DISARMED、adapter_output 三轴为零。最低目标参数为 0.25/0.25。

| 项目 | 服务端完成时 | RPC 时间窗口估计 | 返回后约 2 秒末帧（相对服务端起点） |
| --- | --- | --- | --- |
| 目标 0.2m | 0.19055m，剩余 0.00945m；约 1.61s | 0.20018m | 0.20800m，超出目标约 8.0mm |
| 目标 15° | 13.6697°，剩余 1.3303°；约 2.07s | 14.2427° | 13.8834°，不足目标约 1.1166° |

三个窗口参考起点/时刻不同，不能混称同一个最终误差。末帧仍是里程计估计，未提供
外部卷尺或量角结果。此次距离停滞问题未再出现，短距离与小角度达到当前软件容差；
不能外推为全部距离/负载/方向精度已通过。
本次日志只找到这两个新 move，没有新的反向、整圈、release 或故障注入证据。
SDK 仍打印 unknown upload head=0xf0，本次未伴随运动 FAULT，其含义仍待厂商解释。

本轮完整离线结果：**通过**。Primitive 174 项、Robot 42 项单测，以及镜像构建、
模型/TF、固定 Robonix validate/codegen、replay、fake、motion Atlas/gRPC/ROS
集成与退出清理全部通过。报告 `.artifacts/offline/20261014T060118714611Z/report.json`。
另跑 6 项生命周期入口回归通过，报告 `.artifacts/m4/20261014T060330-132942.log`。
运行镜像已构建，真机服务未启动，本轮没有下发真实控制命令。

## 本轮完成的程序工作

旧距离控制输出 remaining×1.5，最高 0.2m/s；目标 0.2m 时走约 7–8cm 后指令低于
Walk 约 0.2 的起步阈值，已在带死区、10Hz 反馈的模拟后端复现“先动后停”。
新版有界距离/角度 move 增加最低目标速度，默认分别 0.25m/s、0.25rad/s；
配置为 move_min_linear_mps（0.2–0.3）、move_min_angular_rps（0.2–0.4）。
配置超过 controller 对应限速会拒绝初始化，status 的 bounded_move_minimum 可核对。
直线默认目标从旧最高 0.2 提升到 0.25；属于实际控制策略变化，需重启并现场验收。

- 仅作用于非发布有界 move，连续 Twist/定时速度按原请求执行，不放大微小输入。
- 已在到达容差内的目标不产生非零速度；目标外沿原方向运动，保留加速度限制。
- 到达 2cm/0.03rad 容差时归零并 disarm；若越过目标且超出容差，则停止报 overshoot，
  不自动反向，不无限修正。返回成功表示停止前反馈达到容差，不代表实测最终停点。
- 保留 3 秒停滞、反馈故障、取消、deadline、30 秒本地解锁租期和位移界限保护。
- 最低速度是依据 SDK 文档选择的初始值，不是多地面/负载/电量标定结果。

新增离线回归覆盖旧策略失败复现、正反距离、正反 15°/360°、低速输入不被放大、
容差内不运动、取消归零、超调不反转及参数限幅。既有测试继续覆盖断连/过期、故障
锁存、clear 后不自动 arm、lease/watchdog、release 及 SDK 拒绝处理。

## 最小现场复测（人工逐条执行）

M5 不以离线通过替代真机安全验收。先完成下面短动作，再决定后续项目；保留视频及
卷尺/角度测量。以下脚本不自动连续执行运动，不自动重新 arm。

所有 WSL 窗口进入工作目录：

```bash
cd /mnt/c/Users/Administrator/Desktop/robonix/robot-mirrorme-bpx
```

若仍有旧服务，确认静止后先 `bash scripts/motion-test.sh shutdown`，无容器时跳过。
窗口 A 保持 relay（如已运行则不重复绑定）：

```bash
bash scripts/motion-test.sh relay 10.21.40.1 10.21.40.68
```

窗口 B 启动新版非发布 motion 身份；这会创建 SDK 控制会话，不能与 App 同时控制：

```bash
bash scripts/motion-test.sh start --confirm-physical-motion-test
```

窗口 C 确认 status 无当前 fault、disarmed、bounded_move_minimum 为 0.25/0.25。
站立后可作一次 20cm 复测（本版有界距离目标速度为 0.25m/s）：

```bash
bash scripts/motion-test.sh status
bash scripts/motion-test.sh stand --confirm-physical-motion-test
bash scripts/motion-test.sh arm --confirm-physical-motion-test
bash scripts/acceptance.sh move --forward-m 0.2 --duration-sec 10
bash scripts/motion-test.sh status
```

验收：RPC distance reached、结束 DISARMED/零输出；另用卷尺记录最终停点。
出现 fault/stalled/overshoot 时保留日志并停止本轮，不自动加速或重试。
确认短距离通过，再独立执行角度请求：

```bash
bash scripts/motion-test.sh arm --confirm-physical-motion-test
bash scripts/acceptance.sh move --rotate-deg 15 --duration-sec 10
```

反向用 -0.2m/-15°；每次单独 arm。正反小动作与停止通过后，再依现场空间执行
±360°、duration-sec 25（避免以 30 秒目标耗尽 30 秒解锁租期）。控制仍可能因实际响应
达不到目标，不能绕过保护。角度用外部方向参照测量。

## 原 M5 尚需现场或厂商证据的项目

| 项目 | 方法/完成条件 |
| --- | --- |
| 距离/角度/整圈 | 上述命令 + 原始 capture、最终外部位移/角度及视频 |
| Walk 死区/迟滞 | REMAINING_TESTS.md 第 4 节，定时速度路径不补偿，可测不同小速度的起步/停止响应 |
| SDK/App/遥控器优先级 | 第 6 节，stop/sit/release 后人工检查 App，再 shutdown；SDK release 不等于固件仲裁已验收 |
| 取消/deadline/lease/停发 watchdog | 第 5 节，记录请求时刻与物理停止时间；软件零输出不代替停止上界 |
| stale/断连恢复 | 第 7 节先静止断状态转发；故障应锁存，恢复且 clear 后仍 disarmed |
| 运动中断网、SIGKILL、本体重启 | 先取得机器人端 watchdog/急停说明与现场保护；按硬件团队方案执行，不提供盲目自动注入 |
| 物理急停及视频 | 操作者/厂商确认，程序不能替代 |
| damping | 原 TODO 明确待产品决策，本轮不新增姿态功能 |

原 M5 退出条件包含每类故障的物理停止时间和现场证据，因此不能仅凭代码完工勾选
“M5 全部完成”。本轮未下发真机运动指令，未修改默认发布版能力清单。
