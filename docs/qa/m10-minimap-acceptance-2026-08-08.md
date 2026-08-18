# 《战地2035》M10 小地图验收报告

验收日期：2026-08-08
验收角色：QA / Director 回退验收
验收对象：UI/UX 团队 M10 里程碑
验收范围：程序化小地图控件、HUD 接入、主流程数据汇入

## 1. 交付内容

- UI/UX 子智能体：新建 `godot/scripts/ui/minimap.gd`，在 `godot/scripts/ui/hud.gd` 接入右上角小地图。
  - 绘制网格、地图边界、据点（蓝/红/中立/争夺）、敌军圆点、载具方块、玩家朝向箭头与 N 指北标记。
  - 公开 API：`set_state/get_state/set_enabled/is_enabled`，HUD 新增 `get_minimap()`。
  - 小地图位于弹药面板下方，避免 UI 重叠。
- Director 集成：`main.gd` 的 `_build_hud_state()` 汇入玩家位置/朝向、敌军摘要、吉普/坦克位置与据点状态。

## 2. 验证结果

| 测试项 | 命令 | 退出码 | 关键结果 |
| --- | --- | --- | --- |
| 脚本编译 | `--import` | 0 | 无 `SCRIPT ERROR` / `Parse Error` / `Cannot infer` |
| M10 专项 | `res://tools/m10_test.tscn` | 0 | `[M10Test] passed`：HUD 状态含 minimap、据点/敌军数据、控件状态往返 |
| 常规冒烟 | `res://tools/smoke_test.tscn` | 0 | `[SmokeTest] passed` |
| 地形射线 | `res://tools/terrain_ray_test.tscn` | 0 | `[TerrainRayTest] passed` |
| M9/M8/M7/M6/M5/M4/M3b/M3a 回归 | 对应测试场景 | 0 | 全部 passed |

## 3. 结论

M10 小地图通过全量回归，未发现新 P0/P1 缺陷。小地图已具备战斗 HUD 所需的数据与绘制能力，视觉细节可在实体 GPU 验收中继续打磨。
