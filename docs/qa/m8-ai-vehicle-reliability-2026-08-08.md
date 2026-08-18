# 《战地2035》M8 AI 载具可靠性验收报告

验收日期：2026-08-08
验收角色：QA / Director 回退验收
验收对象：Vehicle + AI 团队 M8 里程碑
验收范围：AI 载具前向障碍检测、倒车脱困、吉普出生点碰撞高度修正

## 1. 修复内容

- Vehicle 子智能体：`godot/scripts/vehicles/jeep.gd` 新增前向 4 米射线探测、`is_forward_blocked()`，并把 `forward_blocked`、`forward_hit_distance` 加入 `get_ai_drive_state()`。
- AI 子智能体：`godot/scripts/ai/enemy_system.gd` 增加 `_vehicle_blocked_timer`，前方受阻超过 0.45 秒时倒车并反向转向脱困。
- Director 集成修复：
  - `godot/scripts/main.gd` 吉普出生点改为用背面射线探测真实碰撞高度，避免解析高度与碰撞面不一致导致物理弹飞。
  - `jeep.gd` 前向距离改用命中点与射线起点手动计算，避免依赖不稳定的 `distance` 结果键。
  - `godot/tools/m8_test.gd` 使用平面测试场与物理服务状态重置，验证 AI 载具避障。

## 2. 验证结果

| 测试项 | 命令 | 退出码 | 关键结果 |
| --- | --- | --- | --- |
| 脚本编译 | `--import` | 0 | 无 `SCRIPT ERROR` / `Parse Error` / `Cannot infer` |
| M8 专项 | `res://tools/m8_test.tscn` | 0 | `[M8Test] passed`：检测到障碍、AI 发出驾驶指令、载具移动 |
| 常规冒烟 | `res://tools/smoke_test.tscn` | 0 | `[SmokeTest] passed` |
| 地形射线 | `res://tools/terrain_ray_test.tscn` | 0 | `[TerrainRayTest] passed` |
| M7 性能回归 | `res://tools/m7_test.tscn` | 0 | `[M7Test] passed` |
| M6 回归 | `res://tools/m6_test.tscn` | 0 | `[M6Test] passed` |
| M5 回归 | `res://tools/m5_test.tscn` | 0 | `[M5Test] passed` |
| M4 回归 | `res://tools/m4_test.tscn` | 0 | `[M4Test] passed` |
| M3b 回归 | `res://tools/m3b_test.tscn` | 0 | `[M3bTest] passed` |
| M3a 回归 | `res://tools/animation_test.tscn` | 0 | `[AnimationTest] passed` |

## 3. 结论

M8 AI 载具可靠性修复通过全量回归，未发现新 P0/P1 缺陷。AI 载具路径控制已具备基础避障与脱困能力，后续仍可在实体 GPU 验收中做视觉打磨。
