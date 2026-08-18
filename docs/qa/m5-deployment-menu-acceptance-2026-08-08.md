# 《战地2035》M5 部署界面与完整主菜单独立验收报告

验收日期：2026-08-08
验收角色：QA Team（独立验收，只报告，不修复）
验收对象：UI/流程团队 M5 里程碑
验收范围：部署界面、兵种与武器选择、完整主菜单与设置、启动暂停与部署恢复

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
| M5 专项 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m5_test.tscn` | 0 | `[M5Test] passed` | 通过 |
| M4 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m4_test.tscn` | 0 | `[M4Test] passed` | 通过 |
| M3b 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m3b_test.tscn` | 0 | `[M3bTest] passed` | 通过 |
| M3a 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/animation_test.tscn` | 0 | `[AnimationTest] passed` | 通过 |

日志文件：

- `.tools/qa-m5-import.log`
- `.tools/qa-m5-smoke.log`
- `.tools/qa-m5-m5.log`
- `.tools/qa-m5-m4.log`
- `.tools/qa-m5-m3b.log`
- `.tools/qa-m5-animation.log`

过程性说明：M5 专项测试退出时 Godot 报告 `8 ObjectDB instances were leaked`，外层 PowerShell 将 stderr 包装为 `NativeCommandError`；以 `$LASTEXITCODE` 复核实际退出码为 0，日志仍出现 `[M5Test] passed`。该现象属于退出收尾警告，不构成测试失败。

## 3. 逐项测试结果

| 编号 | 验收项 | 结果 |
| --- | --- | --- |
| a | 导入/编译检查通过，无脚本解析错误 | 通过 |
| b | 常规冒烟通过，主场景与集成初始化正常 | 通过 |
| c | 游戏启动后主菜单打开，且场景树处于暂停状态 | 通过 |
| d | 点击开始游戏后主菜单关闭、部署界面打开 | 通过 |
| e | 兵种、武器、出生点选择会同步到 `get_selected_loadout()` 与 `get_selected_spawn()` | 通过 |
| f | 部署后恢复场景运行、启用玩家输入，并将选中的侦察兵配装应用到玩家 | 通过 |
| g | 部署后当前武器为侦察兵主武器（DMR） | 通过 |
| h | M4 回归：AI 战术行为专项通过 | 通过 |
| i | M3b 回归：翻越/攀爬/载具动画快照通过 | 通过 |
| j | M3a 回归：Inspect 动画、卧倒/起身状态通过 | 通过 |

## 4. 代码抽查结果

| 文件 | 抽查项 | 结果 |
| --- | --- | --- |
| `godot/scripts/gameplay/loadout.gd` | `get_classes()`、`get_class_data()`、`get_default_loadout()`、`get_available_indices()`；`assault/recon/support/engineer` 4 个兵种 id | 通过 |
| `godot/scripts/gameplay/weapons.gd` | `set_available_indices()`、`get_available_indices()`、`get_weapon_list()`；`switch_weapon()` 对不在可用列表中的索引返回 false | 通过 |
| `godot/scripts/gameplay/player.gd` | `apply_loadout()`、`get_loadout()`；`get_state()` 包含 `class_id` 与 `loadout` | 通过 |
| `godot/scripts/ui/hud.gd` | 主菜单/部署菜单的显示、隐藏与状态查询方法；部署选项、选择与读取方法；三个需求信号；`PROCESS_MODE_ALWAYS` | 通过 |
| `godot/scripts/main.gd` | 启动进入主菜单并暂停；`deploy_requested` 时应用配装、选择出生点、恢复暂停并启用 AI/输入；`quit_requested` 退出 | 通过 |

关键代码位置：

- `loadout.gd`：`get_classes()` 第 39 行，`get_class_data()` 第 43 行，`get_default_loadout()` 第 50 行，`get_available_indices()` 第 58 行；`assault` 第 5 行、`recon` 第 13 行、`support` 第 21 行、`engineer` 第 29 行。
- `weapons.gd`：`switch_weapon()` 第 228 行，第 232-233 行拒绝非可用索引；`set_available_indices()` 第 251 行，`get_available_indices()` 第 279 行，`get_weapon_list()` 第 283 行。
- `player.gd`：`get_state()` 第 182 行，`class_id` 第 210 行、`loadout` 第 211 行；`apply_loadout()` 第 227 行，`get_loadout()` 第 235 行。
- `hud.gd`：`start_game_requested` 第 8 行、`deploy_requested` 第 9 行、`quit_requested` 第 10 行；`process_mode` 第 123 行；主菜单方法第 806/816/824 行；部署菜单方法第 828/838/846 行；`set_deployment_options()` 第 850 行；`select_class()` 第 867 行、`select_weapon()` 第 881 行、`select_spawn()` 第 894 行；`get_selected_loadout()` 第 901 行、`get_selected_spawn()` 第 914 行。
- `main.gd`：`_ready()` 第 47 行调用 `_enter_main_menu()` 第 52 行；信号连接第 224-226 行；`_enter_main_menu()` 第 534 行，第 535 行暂停场景树，第 536 行禁用玩家输入，第 537 行停用 AI，第 538-540 行注入部署选项；`_on_deploy_requested()` 第 551 行，第 555 行应用配装，第 556 行选择出生点，第 557 行启用 AI，第 558 行启用输入，第 562 行恢复运行；`_on_quit_requested()` 第 566 行。

## 5. 缺陷清单

M5 范围未发现 P0/P1 缺陷。

- **Q-M5-01（P2，遗留，不阻塞）**：程序化地形网格背面射线问题仍存在，已在 M3a 报告跟踪。建议后续里程碑统一检查地形三角面索引绕序，或为相关射线显式启用背面命中。
- **Q-M5-02（P3，可接受，不阻塞）**：主菜单的“设置”复用现有暂停设置面板，面板标题仍为“暂停”；当前验收可接受，后续如需更完整的设置页可拆分为独立界面。
- **Q-M5-03（P3，观察项，不阻塞）**：主菜单启动时世界已完成预生成（出生点、队伍、载具、据点均已初始化），部署前存在额外初始化开销；本次专项测试未受影响，后续可作为启动性能观察项。
- **过程性记录**：M5 专项测试退出时出现 `ObjectDB instances were leaked` 警告，属于退出收尾问题，不影响测试结果；外层 PowerShell 对原生 stderr 的包装误报已通过 `$LASTEXITCODE` 复核排除。

## 6. 验收结论

- 导入/编译检查、常规冒烟、M5 专项、M4 回归、M3b 回归、M3a 回归六条命令的 Godot/godot.ps1 退出码均为 0，日志均出现对应 passed 标记。
- 部署界面、兵种与武器选择、完整主菜单与设置、启动暂停与部署恢复相关契约与专项行为全部通过，代码抽查无缺失。
- M4、M3b、M3a 回归全部通过，仅存在 M3a 已跟踪的 P2 遗留风险及两项 P3 可接受/观察项，未发现 P0/P1 缺陷。
- 结论：M5 部署界面与完整主菜单模块**验收通过**，可提交 Director 标记 M5 完成。
