# 《战地2035》M9 主战坦克载具验收报告

验收日期：2026-08-08
验收角色：QA / Director 回退验收
验收对象：Vehicle 团队 M9 里程碑
验收范围：主战坦克程序化建模、驾驶物理、主炮、伤害、进出与双载具集成

## 1. 交付内容

- Vehicle 子智能体：新建 `godot/scripts/vehicles/tank.gd` 与 `godot/scenes/vehicles/tank.tscn`。
  - 程序化建模：履带、车体、炮塔、主炮管、舱盖与军事配色，无外部资源依赖。
  - 坦克式驾驶：低速、高横向阻尼、慢转向，`drive()` 与 `_integrate_forces()`。
  - 主炮：`try_fire_cannon()`、冷却 2 秒、`cannon_fired` 信号、炮口世界坐标。
  - 伤害与摧毁：450 血量、`take_damage()`、`destroyed` 信号、冻结与禁用碰撞。
- Director 集成：`main.gd` 支持双载具（吉普 + 坦克）进出、驾驶、相机切换与坦克主炮射击。

## 2. 验证结果

| 测试项 | 命令 | 退出码 | 关键结果 |
| --- | --- | --- | --- |
| 脚本编译 | `--import` | 0 | 无 `SCRIPT ERROR` / `Parse Error` / `Cannot infer` |
| M9 专项 | `res://tools/m9_test.tscn` | 0 | `[M9Test] passed`：驱动、主炮冷却与弹体、进出、伤害、摧毁信号 |
| 常规冒烟 | `res://tools/smoke_test.tscn` | 0 | `[SmokeTest] passed` |
| 地形射线 | `res://tools/terrain_ray_test.tscn` | 0 | `[TerrainRayTest] passed` |
| M8 回归 | `res://tools/m8_test.tscn` | 0 | `[M8Test] passed` |
| M7 回归 | `res://tools/m7_test.tscn` | 0 | `[M7Test] passed` |
| M6 回归 | `res://tools/m6_test.tscn` | 0 | `[M6Test] passed` |
| M5 回归 | `res://tools/m5_test.tscn` | 0 | `[M5Test] passed` |
| M4 回归 | `res://tools/m4_test.tscn` | 0 | `[M4Test] passed` |
| M3b 回归 | `res://tools/m3b_test.tscn` | 0 | `[M3bTest] passed` |
| M3a 回归 | `res://tools/animation_test.tscn` | 0 | `[AnimationTest] passed` |

## 3. 结论

M9 主战坦克载具通过全量回归，未发现新 P0/P1 缺陷。坦克已具备可驾驶、可进出、可开火、可摧毁的完整模块；后续可在实体 GPU 验收中检查模型比例与视觉表现。
