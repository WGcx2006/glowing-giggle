# 《战地2035》P2 地形背面射线缺陷闭环报告

验收日期：2026-08-08
验收角色：QA / Director 回退验收
缺陷编号：Q-M3-01 / Q-M4-01 / Q-M5-01 / Q-M6-01 / Q-M7-01（同一根因）
缺陷级别：P2（遗留，影响 AI 视线、高空射击与地形探针）

## 1. 根因

程序化地形使用 `ConcavePolygonShape3D` 构建碰撞体，但网格三角形绕序反向，导致表面法线朝下。`intersect_ray` 在默认 `hit_back_faces=false` 时从高处向下无法命中地形，AI 视线与部分玩法射线可能穿透地形。

## 2. 修复方案

- Visual Art 子智能体：修改 `godot/scripts/render/terrain.gd` 的三角形索引绕序，使地形正面朝上（保留此修复，射线专项验证默认射线可命中）。
- AI 子智能体：为 `godot/scripts/ai/enemy.gd` 的视线、弹道、障碍检测与手雷落地射线启用 `hit_back_faces = true`。
- Gameplay 子智能体：为 `godot/scripts/gameplay/player.gd` 翻越/攀爬检测射线与 `godot/scripts/gameplay/projectiles.gd` hitscan 射线启用 `hit_back_faces = true`。
- Director 集成修复：吉普出生点改用背面射线探测真实碰撞高度（`main.gd`），避免解析高度与碰撞面不一致导致物理弹飞；吉普前向探测距离改为手动计算（`jeep.gd`）。

## 3. 验证结果

| 测试项 | 命令 | 退出码 | 关键结果 |
| --- | --- | --- | --- |
| 脚本编译 | `--import` | 0 | 无 `SCRIPT ERROR` / `Parse Error` / `Cannot infer` |
| 地形射线专项 | `res://tools/terrain_ray_test.tscn` | 0 | `[TerrainRayTest] passed`，默认射线与背面射线均命中 5 个探针点 |
| 常规冒烟 | `res://tools/smoke_test.tscn` | 0 | `[SmokeTest] passed` |
| M7 性能回归 | `res://tools/m7_test.tscn` | 0 | `[M7Test] passed` |
| M6 回归 | `res://tools/m6_test.tscn` | 0 | `[M6Test] passed` |
| M5 回归 | `res://tools/m5_test.tscn` | 0 | `[M5Test] passed` |
| M4 回归 | `res://tools/m4_test.tscn` | 0 | `[M4Test] passed`（手雷多方向视线探测、载具指令断言） |
| M3b 回归 | `res://tools/m3b_test.tscn` | 0 | `[M3bTest] passed` |
| M3a 回归 | `res://tools/animation_test.tscn` | 0 | `[AnimationTest] passed` |

## 4. 测试适配说明

- 地形射线修复后 AI 视线判定更正确，M4 手雷测试改为对多个方向探测可视点后投掷，避免把“正确遮挡”误判为缺陷。
- M8 已为 AI 载具增加前向障碍检测与倒车脱困，并验证载具可移动；物理速度仍建议在实体 GPU 验收中复核。

## 5. 结论

P2 地形背面射线缺陷已修复，9 条验证命令全部通过，未发现新 P0/P1 缺陷。遗留事项仅为实体 GPU 人工验收清单与 AI 载具路径打磨（P3）。
