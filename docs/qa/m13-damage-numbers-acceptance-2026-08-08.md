# 《战地2035》M13 HUD 伤害数字验收报告

验收日期：2026-08-08
验收角色：QA / Director 集成验收
验收对象：UI/UX 子智能体（Gibbs）M13 里程碑
验收范围：伤害数字对象池、命中世界坐标转屏幕坐标、生命周期回收

## 1. 交付内容

- UI/UX 子智能体在 `godot/scripts/ui/hud.gd` 实现伤害数字对象池：
  - `show_damage_number(value, screen_position)`：从 16 个预建 Label 中分配空闲项，显示整数伤害并启动 1 秒生命周期；全部占用时复用最早一项。
  - `get_active_damage_numbers()`：返回当前活跃伤害数字数量，供专项测试断言。
  - `_build_damage_numbers()`：程序化创建 DamageNumber Label，无外部资源依赖。
- Director 在 `godot/scripts/main.gd` 完成集成：
  - `_on_hit_target` 在敌兵与载具受击时调用 `_show_damage_number`。
  - `_show_damage_number` 使用玩家相机 `unproject_position` 将命中世界坐标转为屏幕坐标后交给 HUD。
- `godot/tools/m13_test.tscn` 专项测试验证数字显示、淡出回收与集成入口。

## 2. 验证结果

| 测试项 | 命令 | 退出码 | 关键结果 |
| --- | --- | --- | --- |
| 脚本编译 | `--import` | 0 | 无 `SCRIPT ERROR` / `Parse Error` |
| M13 专项 | `res://tools/m13_test.tscn` | 0 | `[M13Test] passed`：显示 2 个数字并在 150 帧后回收 |
| 常规冒烟 | `res://tools/smoke_test.tscn` | 0 | `[SmokeTest] passed` |
| 地形射线 | `res://tools/terrain_ray_test.tscn` | 0 | `[TerrainRayTest] passed` |
| M12/M11/M10 回归 | 对应测试场景 | 0 | 全部 passed |
| M9/M8/M7/M6/M5/M4/M3b/动画回归 | 对应测试场景 | 0 | 全部 passed |

注：测试进程退出时的 `ObjectDB instances were leaked` 为 Godot headless 测试已知噪音，不影响结果。

## 3. 代码 API 检查

- `godot/scripts/ui/hud.gd`：`show_damage_number`、`get_active_damage_numbers`、`_build_damage_numbers` 与 `_update_damage_numbers` 已存在。
- `godot/scripts/main.gd`：敌兵/载具受击路径均调用 `_show_damage_number`，世界坐标转屏逻辑已接入。
- `godot/tools/m13_test.gd`：覆盖活跃数量 >= 2、150 帧后归零、`main.gd` 集成入口存在。

## 4. 结论

M13 HUD 伤害数字通过专项与全量回归，未发现新 P0/P1 缺陷。伤害数字的颜色、位置与命中反馈细节保留给后续 UI polish。
