# 《战地2035》M14 征服模式 QA 独立验收报告

验收日期：2026-08-08
验收角色：QA（独立审核子智能体）
验收对象：M14 征服模式

## 1. 交付内容

- Gameplay：`godot/scripts/game/game_mode.gd` 实现 100/100 初始票数、600 秒对局计时、击杀/阵亡扣票、据点流血（`0.5` 票/区/秒）、胜负判定与 `restart()`。
- UI：`godot/scripts/ui/hud.gd` 实现比分文本（蓝方票数、红方票数、剩余时间）与结算摘要文本。
- Audio：`godot/scripts/audio/audio_manager.gd` 实现 `play_capture_announce` 与 `play_round_end`。
- Director：`godot/scripts/main.gd` 完成部署、击杀、玩家阵亡、HUD 状态构建与胜负流程集成。
- QA 测试：`godot/tools/m14_test.gd`、`godot/tools/m14_test.tscn`，仅新增测试，未修改功能代码。

## 2. 测试命令与结果

| 测试项 | 命令/场景 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- | --- |
| 资源导入 | `--headless --editor --path .\godot --import` | 0 | 无 `SCRIPT ERROR` / `Parse Error` | `import-m14.log` |
| M14 专项 | `res://tools/m14_test.tscn` | 0 | `[M14Test] passed` | `m14-qa.log` |
| 常规冒烟 | `res://tools/smoke_test.tscn` | 0 | `[SmokeTest] passed` | `smoke-m14-qa.log` |

## 3. M14 专项关键结果

- GameMode 单元测试（RefCounted stub，不依赖完整场景）：
  - 初始蓝/红票数均为 100，`active` 为 `true`。
  - `on_enemy_killed("red")` 后红方 99；`on_player_died()` 后蓝方 99。
  - `blue_captured=2, red_captured=0` 时 `update(1.0)` 后红方为 98。
  - 红方票数归零触发 `game_over("blue")`。
  - `restart()` 后同票数超时触发 `game_over("draw")`。
- HUD 测试：`update_state()` 后比分文本包含 `80`、`64`、`02:05`；`show_game_over()` 后结算文本包含 `80`、`64`。
- Audio 测试：`play_capture_announce` 与 `play_round_end` 均存在，实际调用无崩溃。
- 主流程集成：部署后票数为 100/100；击杀红方后红方 99；玩家阵亡后蓝方 99；`_build_hud_state()` 包含 `game_mode`。

## 4. 全量回归

| 回归项 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- |
| M13 伤害数字 | 0 | `[M13Test] passed` | `m14-m13_test.log` |
| M12 天气 | 0 | `[M12Test] passed` | `m14-m12_test.log` |
| M11 音频环境 | 0 | `[M11Test] passed` | `m14-m11_test.log` |
| M10 小地图 | 0 | `[M10Test] passed` | `m14-m10_test.log` |
| M9 坦克载具 | 0 | `[M9Test] passed` | `m14-m9_test.log` |
| M8 AI 载具可靠性 | 0 | `[M8Test] passed` | `m14-m8_test.log` |
| M7 性能发布 | 0 | `[M7Test] passed` | `m14-m7_test.log` |
| M6 网络存档 | 0 | `[M6Test] passed` | `m14-m6_test.log` |
| M5 部署菜单 | 0 | `[M5Test] passed` | `m14-m5_test.log` |
| M4 AI 战术 | 0 | `[M4Test] passed` | `m14-m4_test.log` |
| M3b 动画 | 0 | `[M3bTest] passed` | `m14-m3b_test.log` |
| 动画专项 | 0 | `[AnimationTest] passed` | `m14-animation_test.log` |
| 地形射线 | 0 | `[TerrainRayTest] passed` | `m14-terrain_ray_test.log` |

## 5. 缺陷清单

- 无 P0/P1 新缺陷，未发现需要回退或修复的功能缺陷。
- Godot headless 退出时的 `ObjectDB instances were leaked` 为已知退出噪音，不影响测试结论；专项日志中无 `FAILED`、`SCRIPT ERROR` 或 `Parse Error`。

## 6. 结论

M14 征服模式通过 QA 独立验收。GameMode、HUD、Audio 与主流程集成均满足本轮验收标准，全量回归 13 项全部通过。
