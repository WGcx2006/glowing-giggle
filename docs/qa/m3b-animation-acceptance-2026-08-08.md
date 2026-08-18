# 《战地2035》M3b 翻越/攀爬/载具动画独立验收报告

验收日期：2026-08-08
验收角色：QA Team（独立验收，只报告，不修复）
验收对象：Gameplay + Animation + Vehicles 团队 M3b 里程碑
验收范围：翻越、攀爬状态与动画快照、载具动画快照、M3a 动画回归

## 1. 测试环境

- 工作目录：`C:\Users\13081\Desktop\战地风云2035`
- Godot：`Godot_v4.7.1-stable_win64.exe`（经 `scripts/godot.ps1` 调用）
- 运行模式：`--headless`
- 过程说明：当前沙盒只读会导致 Godot 无法写 `.godot` 缓存与日志并触发原生崩溃，因此全部实际运行命令在沙盒外以已授权方式执行，日志写入 `.tools` 目录。
- 本报告仅记录与验收，未修改任何源码。

## 2. 测试命令与结果

| 测试项 | 命令 | 退出码 | 关键结果 | 结论 |
| --- | --- | --- | --- | --- |
| 脚本编译检查 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --editor --path .\godot --import` | 0 | 项目扫描与编辑器加载完成，未发现 `SCRIPT ERROR`、`Parse Error`、`Cannot infer` | 通过 |
| 常规冒烟 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/smoke_test.tscn` | 0（Godot 侧） | `[Battlefield 2035] Godot integration ready`、`[SmokeTest] passed` | 通过 |
| M3b 专项 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m3b_test.tscn` | 0 | `[M3bTest] passed` | 通过 |
| M3a 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/animation_test.tscn` | 0 | `[AnimationTest] passed` | 通过 |

日志文件：

- `.tools/qa-m3b-import.log`
- `.tools/qa-m3b-smoke-rerun.log`
- `.tools/qa-m3b-m3b-exact.log`
- `.tools/qa-m3b-animation-exact.log`

说明：冒烟测试原样命令在本次外层 PowerShell 中因 Godot 退出时的 `ObjectDB instances were leaked` stderr 警告被包装为 `NativeCommandError`，外层工具曾返回 1；同一命令以 `$LASTEXITCODE` 复核为 `SMOKE_EXIT=0`，且日志出现 `[SmokeTest] passed`。本报告以 Godot/godot.ps1 的实际退出码和日志为通过依据。

### 专项测试关键输出

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

[Battlefield 2035] Godot integration ready
[SmokeTest] passed
```

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

[Battlefield 2035] Godot integration ready
[M3bTest] passed
```

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

[Battlefield 2035] Godot integration ready
[AnimationTest] passed
```

## 3. 逐项测试结果

| 编号 | 验收项 | 结果 |
| --- | --- | --- |
| a | 导入/编译检查通过，无脚本解析错误 | 通过 |
| b | 常规冒烟通过，主场景与集成初始化正常 | 通过 |
| c | `try_start_vault()` 返回 true，翻越期间 `is_vaulting()` 为 true | 通过 |
| d | 翻越在 80 帧窗口内结束，玩家越过障碍物 | 通过 |
| e | 翻越期间动画快照体现 `pose_name=vault` 或 `vault_progress > 0` | 通过 |
| f | `try_start_climb()` 返回 true，攀爬期间 `is_climbing()` 为 true | 通过 |
| g | 攀爬在 100 帧窗口内结束，玩家登上墙顶（y > 2.0） | 通过 |
| h | 攀爬期间动画快照体现 `pose_name=climb` 或 `climb_progress > 0` | 通过 |
| i | 载具动画快照包含 `speed/throttle/steer/wheel_spin/body_pitch/body_roll/camera_dip` 全部键 | 通过 |
| j | 载具动画快照数值有效，速度、轮速、俯仰、侧倾无缺失或异常 | 通过 |
| k | M3a 回归：Inspect 动画启动与回位通过 | 通过 |
| l | M3a 回归：卧倒/起身的状态、相机高度、胶囊高度切换通过 | 通过 |

## 4. 代码抽查结果

| 文件 | 抽查项 | 结果 |
| --- | --- | --- |
| `godot/scripts/gameplay/player.gd` | 公开方法 `try_start_vault`、`try_start_climb`、`is_vaulting`、`is_climbing`、`get_vault_progress`、`get_climb_progress` | 通过 |
| `godot/scripts/gameplay/player.gd` | `get_state()` 输出 `vaulting`、`climbing`、`vault_progress`、`climb_progress` | 通过 |
| `godot/scripts/animation/weapon_animator.gd` | `get_pose_snapshot()` 包含 `vault_progress`、`climb_progress` | 通过 |
| `godot/scripts/vehicles/jeep.gd` | `get_animation_snapshot()` 包含 `speed`、`throttle`、`steer`、`wheel_spin`、`body_pitch`、`body_roll`、`camera_dip` | 通过 |

## 5. 缺陷清单

M3b 范围未发现 P0/P1 缺陷。

- **Q-M3-01（P2，遗留，不阻塞）**：程序化地形网格背面射线问题仍存在，已在 M3a 报告记录。建议后续里程碑统一检查地形三角面索引绕序，或为相关射线显式启用背面命中。
- **Q-M3B-01（P3/观察项，不阻塞）**：翻越/攀爬当前使用“插值位置 + 零速度 move_and_slide”的位移方式，运动曲线与脚步/手部动画仍需视觉团队打磨。
- **过程性记录**：冒烟测试退出时出现 `ObjectDB instances were leaked` 警告，属于退出收尾问题，不影响测试结果；外层 PowerShell 对原生 stderr 的包装误报已通过 `$LASTEXITCODE` 复核排除。

## 6. 验收结论

- 脚本编译检查、常规冒烟、M3b 专项、M3a 回归四条命令的 Godot 退出码均为 0，日志均出现对应 passed 标记。
- 翻越、攀爬状态与动画快照、载具动画快照、M3a 回归全部通过。
- 结论：M3b 翻越/攀爬/载具动画模块**验收通过**，可提交 Director 标记 M3b 完成。
