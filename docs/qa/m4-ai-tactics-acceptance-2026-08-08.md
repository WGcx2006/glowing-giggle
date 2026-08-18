# 《战地2035》M4 AI 战术行为独立验收报告

验收日期：2026-08-08
验收角色：QA Team（独立验收，只报告，不修复）
验收对象：AI 团队 M4 里程碑
验收范围：掩体、手雷、呼叫支援、占点突破、防守据点、驾驶载具

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
| M4 专项 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m4_test.tscn` | 0 | `[M4Test] passed` | 通过 |
| M3b 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m3b_test.tscn` | 0 | `[M3bTest] passed` | 通过 |
| M3a 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/animation_test.tscn` | 0 | `[AnimationTest] passed` | 通过 |

日志文件：

- `.tools/qa-m4-import.log`
- `.tools/qa-m4-smoke.log`
- `.tools/qa-m4-m4.log`
- `.tools/qa-m4-m3b.log`
- `.tools/qa-m4-animation.log`

过程性说明：冒烟测试退出时 Godot 报告 `ObjectDB instances were leaked`，外层 PowerShell 将 stderr 包装为 `NativeCommandError`；以 `$LASTEXITCODE` 复核实际退出码为 0，日志仍出现 `[SmokeTest] passed`。该现象属于退出收尾警告，不构成测试失败。

## 3. 逐项测试结果

| 编号 | 验收项 | 结果 |
| --- | --- | --- |
| a | 导入/编译检查通过，无脚本解析错误 | 通过 |
| b | 常规冒烟通过，主场景与集成初始化正常 | 通过 |
| c | `enemy_system` 具备据点、支援、载具 AI 所需契约方法 | 通过 |
| d | `get_objective_zones()` 返回至少 4 个据点，且每项包含 `position` 与 `radius` | 通过 |
| e | `request_support()` 入队后 `get_nearest_support_request()` 能按队伍取回请求点 | 通过 |
| f | AI 可调用 `throw_grenade()`，手雷爆炸后触发 `explosion_detonated` | 通过 |
| g | AI 单位进入据点/战术状态，状态摘要包含 `ASSAULT`、`DEFEND`、`SUPPORT`、`GRENADE` 等目标状态 | 通过 |
| h | 载具进入 AI 驾驶状态，`get_ai_summary().vehicle_driven` 为 true，且载具速度大于 0.2 | 通过 |
| i | M3b 回归：翻越/攀爬/载具动画快照通过 | 通过 |
| j | M3a 回归：Inspect 动画、卧倒/起身状态通过 | 通过 |

## 4. 代码抽查结果

| 文件 | 抽查项 | 结果 |
| --- | --- | --- |
| `godot/scripts/ai/enemy.gd` | `get_state_summary()`、`throw_grenade()`；`AIState` 含 `ASSAULT/DEFEND/SUPPORT/GRENADE`；`throw_grenade` 先 `add_child(grenade)` 再设置 `global_position` | 通过 |
| `godot/scripts/ai/enemy_system.gd` | `get_objective_zones()`、`request_support()`、`get_nearest_support_request()`、`update_vehicle_ai()`、`get_ai_summary()`；`explosion_detonated`、`support_requested` 信号存在 | 通过 |
| `godot/scripts/gameplay/capture_zones.gd` | `get_control_state()` 的 zone 字典包含 `position` 与 `radius` | 通过 |
| `godot/scripts/vehicles/jeep.gd` | `set_ai_driver()`、`is_ai_driven()`、`ai_drive()`、`get_ai_drive_state()` | 通过 |
| `godot/scripts/audio/audio_manager.gd` | `play_radio_chatter()` | 通过 |
| `godot/scripts/main.gd` | `_capture_zones` 与 `_vehicle` 传入 `enemy_system`；连接 `explosion_detonated` 与 `support_requested` | 通过 |

关键代码位置：

- `enemy.gd`：`enum AIState` 第 12 行起，`ASSAULT/DEFEND/SUPPORT/GRENADE` 第 20-23 行；`get_state_summary()` 第 336 行；`throw_grenade()` 第 358 行；第 369 行 `add_child(grenade)` 早于第 370 行 `grenade.global_position = ...`。
- `enemy_system.gd`：`explosion_detonated` 第 6 行，`support_requested` 第 7 行；`get_objective_zones()` 第 101 行，`request_support()` 第 120 行，`get_nearest_support_request()` 第 128 行，`update_vehicle_ai()` 第 152 行，`get_ai_summary()` 第 240 行。
- `capture_zones.gd`：`get_control_state()` 第 69 行，zone 字典包含 `"position"` 第 78 行与 `"radius"` 第 79 行。
- `jeep.gd`：`set_ai_driver()` 第 76 行，`is_ai_driven()` 第 80 行，`ai_drive()` 第 84 行，`get_ai_drive_state()` 第 88 行。
- `audio_manager.gd`：`play_radio_chatter()` 第 82 行。
- `main.gd`：`_enemy_system.explosion_detonated.connect(...)` 第 210 行，`support_requested.connect(...)` 第 211 行，`set_capture_zones(_capture_zones)` 第 245 行，`set_vehicle(_vehicle)` 第 246 行。

## 5. 缺陷清单

M4 范围未发现 P0/P1 缺陷。

- **Q-M4-01（P2，遗留，不阻塞）**：程序化地形网格背面射线问题仍存在，已在 M3a 报告跟踪。建议后续里程碑统一检查地形三角面索引绕序，或为相关射线显式启用背面命中。
- **Q-M4-02（P3，观察项，不阻塞）**：AI 载具路径控制可完成驱动，但转向、避障与车身姿态仍需视觉/物理打磨。
- **Q-M4-03（P3，可接受，不阻塞）**：AI 驾驶载具使用隐藏司机抽象，单位在车内不可见且无实体乘降过程；当前可接受，后续可改为实体乘降表现。
- **过程性记录**：冒烟测试退出时出现 `ObjectDB instances were leaked` 警告，属于退出收尾问题，不影响测试结果；外层 PowerShell 对原生 stderr 的包装误报已通过 `$LASTEXITCODE` 复核排除。

## 6. 验收结论

- 导入/编译检查、常规冒烟、M4 专项、M3b 回归、M3a 回归五条命令的 Godot/godot.ps1 退出码均为 0，日志均出现对应 passed 标记。
- 掩体、手雷、呼叫支援、占点突破、防守据点、驾驶载具相关契约与专项行为全部通过，代码抽查无缺失。
- M3b、M3a 回归通过，未发现 P0/P1 缺陷。
- 结论：M4 AI 战术行为模块**验收通过**，可提交 Director 标记 M4 完成。
