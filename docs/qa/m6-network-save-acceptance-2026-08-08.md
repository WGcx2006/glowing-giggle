# 《战地2035》M6 网络接口预留与保存系统独立验收报告

验收日期：2026-08-08
验收角色：QA Team（独立验收，只报告，不修复）
验收对象：Gameplay/Infrastructure 团队 M6 里程碑
验收范围：网络接口预留（状态机与信号契约）、本地档案保存系统、启动加载与部署/设置变更保存、既有里程碑回归

## 1. 测试环境

- 工作目录：`C:\Users\13081\Desktop\战地风云2035`
- Godot：`Godot_v4.7.1-stable_win64.exe`（经 `scripts/godot.ps1` 调用）
- 运行模式：`--headless`
- 过程说明：当前沙盒只读会导致 Godot 无法写 `.godot` 缓存与日志并触发原生崩溃，因此全部实际运行命令在沙盒外以已授权方式执行，日志写入 `.tools` 目录。
- 本报告仅记录与验收，未修改任何源码。

## 2. 测试命令与结果

| 测试项 | 命令 | 退出码 | 关键结果 | 结论 |
| --- | --- | --- | --- | --- |
| 导入/编译检查 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --editor --path .\godot --import` | 0 | 项目扫描与编辑器加载完成，未发现 `SCRIPT ERROR`、`Parse Error`、`Cannot infer` | 通过 |
| 常规冒烟 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/smoke_test.tscn` | 0 | `[Battlefield 2035] Godot integration ready`、`[SmokeTest] passed` | 通过 |
| M6 专项 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m6_test.tscn` | 0 | `[M6Test] passed` | 通过 |
| M5 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m5_test.tscn` | 0 | `[M5Test] passed` | 通过 |
| M4 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m4_test.tscn` | 0 | `[M4Test] passed` | 通过 |
| M3b 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m3b_test.tscn` | 0 | `[M3bTest] passed` | 通过 |
| M3a 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/animation_test.tscn` | 0 | `[AnimationTest] passed` | 通过 |

日志文件：

- `.tools/qa-m6-import.log`
- `.tools/qa-m6-smoke.log`
- `.tools/qa-m6-m6.log`
- `.tools/qa-m6-m5.log`
- `.tools/qa-m6-m4.log`
- `.tools/qa-m6-m3b.log`
- `.tools/qa-m6-animation.log`

过程性说明：M5 回归测试退出时 Godot 报告 `WARNING: 8 ObjectDB instances were leaked at exit`，外层 PowerShell 将 stderr 包装为 `NativeCommandError`；以 `QA_EXIT_CODE` 复核实际退出码为 0，日志仍出现 `[M5Test] passed`。该现象与 M5 验收记录一致，属于退出收尾警告，不构成测试失败。

## 3. 逐项测试结果

| 编号 | 验收项 | 结果 |
| --- | --- | --- |
| a | 导入/编译检查通过，无脚本解析或类型推断错误 | 通过 |
| b | 常规冒烟通过，主场景与集成初始化正常 | 通过 |
| c | 网络状态机支持 `host_session` 后进入 host，`join_session` 后进入 client，`leave_session` 后回到 offline | 通过 |
| d | `get_network_state()` 返回 mode/session_name/address/max_players/connected_peers/reserved | 通过 |
| e | 档案保存、读取、清除契约通过，JSON 内容读写一致 | 通过 |
| f | 部署请求后保存玩家配装，且游戏解除暂停 | 通过 |
| g | M5 回归：部署界面与完整主菜单专项通过 | 通过 |
| h | M4 回归：AI 战术行为专项通过 | 通过 |
| i | M3b 回归：翻越/攀爬/载具动画专项通过 | 通过 |
| j | M3a 回归：Inspect 动画、卧倒/起身状态专项通过 | 通过 |

## 4. 代码抽查结果

| 文件 | 抽查项 | 结果 |
| --- | --- | --- |
| `godot/scripts/network/network_manager.gd` | `host_session/join_session/leave_session/get_network_state/get_mode_name`；信号 `session_started/session_joined/session_left/peer_connected/peer_disconnected`；`DEFAULT_PORT`、`MAX_PLAYERS`、`Mode` 枚举；状态机仅 offline/host/client，不创建真实 socket | 通过 |
| `godot/scripts/save/save_manager.gd` | `get_save_path/save_profile/load_profile/clear_profile`；信号 `save_completed/load_completed`；保存路径 `user://battlefield2035_profile.json` | 通过 |
| `godot/scripts/main.gd` | `get_network_manager/get_save_manager`；启动时加载档案并应用 quality/sensitivity/loadout；部署与设置变更时保存档案 | 通过 |

关键代码位置：

- `network_manager.gd`：信号第 7-11 行；`DEFAULT_PORT` 第 13 行、`MAX_PLAYERS` 第 14 行、`Mode` 第 16 行；`host_session()` 第 24 行、`join_session()` 第 33 行、`leave_session()` 第 42 行、`get_network_state()` 第 50 行、`get_mode_name()` 第 61 行；状态转换仅使用 `Mode.HOST`（第 27 行）、`Mode.CLIENT`（第 36 行）、`Mode.OFFLINE`（第 44 行），代码中无 ENet/socket/流式传输实现，仅第 5 行注释说明真实传输将在后续里程碑接入。
- `save_manager.gd`：信号第 6-7 行；`SAVE_FILENAME` 第 9 行、`user://` 路径拼接第 15 行；`get_save_path()` 第 18 行、`save_profile()` 第 22 行、`load_profile()` 第 36 行、`clear_profile()` 第 48 行。
- `main.gd`：预加载网络/存档脚本第 15-16 行，实例化 `NetworkManager`/`SaveManager` 第 184-189 行；`get_network_manager()` 第 543 行、`get_save_manager()` 第 547 行；进入主菜单时调用 `_apply_saved_profile()`（第 562 行），其中应用 quality 第 573-575 行、sensitivity 第 577-579 行、loadout 第 580-583 行；`_save_profile()` 第 586 行写入 quality/sensitivity/loadout（第 590-592 行）；质量变更保存第 530-533 行、灵敏度变更保存第 536-540 行、部署请求保存第 604-610 行。

## 5. 缺陷清单

M6 范围未发现 P0/P1 缺陷。

- **Q-M6-01（P3，符合预留范围，不阻塞）**：网络层目前仅为状态机与信号契约预留，尚未接入真实 ENet 传输；`host_session/join_session` 不建立实际连接，`connected_peers` 固定为 0。该实现符合 M6“网络接口预留”里程碑范围，后续里程碑接入 `ENetMultiplayerPeer` 时需补充联机专项测试。
- **Q-M6-02（P2，遗留，不阻塞）**：程序化地形网格背面射线问题仍存在，已在 M3a 报告跟踪。建议后续里程碑统一检查地形三角面索引绕序，或为相关射线显式启用背面命中。
- **Q-M6-03（P3，可接受，不阻塞）**：存档为本地 JSON 单文件（`user://battlefield2035_profile.json`），无云同步、多档案槽或版本迁移；当前里程碑可接受，后续可扩展。
- **过程性记录**：M5 回归测试退出时出现 `ObjectDB instances were leaked` 警告，属于退出收尾问题，不影响测试结果；外层 PowerShell 对原生 stderr 的包装误报已通过 `QA_EXIT_CODE` 复核排除。

## 6. 验收结论

- 导入/编译检查、常规冒烟、M6 专项、M5 回归、M4 回归、M3b 回归、M3a 回归七条命令的 Godot/godot.ps1 退出码均为 0，日志均出现对应 passed 标记；导入日志未发现 `SCRIPT ERROR`、`Parse Error`、`Cannot infer`。
- 网络接口预留（状态机、信号、常量与枚举）、存档保存/读取/清除、启动加载与应用、部署与设置变更保存相关契约及专项行为全部通过，代码抽查无缺失。
- M5、M4、M3b、M3a 回归全部通过，仅存在 M3a 已跟踪的 P2 遗留风险及两项符合里程碑范围的 P3 项，未发现 P0/P1 缺陷。
- 结论：M6 网络接口预留与保存系统**验收通过**，可提交 Director 标记 M6 完成。
