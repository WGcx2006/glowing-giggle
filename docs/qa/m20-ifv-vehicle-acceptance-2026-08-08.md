# 《战地2035》M20 IFV 步兵战车验收报告

验收日期：2026-08-08
验收角色：独立 QA 审核子智能体
验收范围：IFV 步兵战车初始化、驱动、动画快照、网络快照、主炮冷却、伤害与主场景集成

## 1. 交付对象

- `godot/tools/m20_test.gd`：M20 IFV 专项 QA 脚本。
- `godot/tools/m20_test.tscn`：M20 专项测试场景，根节点名为 `M20Test`。
- `docs/qa/m20-ifv-vehicle-acceptance-2026-08-08.md`：本次验收报告。

QA 角色仅创建上述测试与报告文件，未修改 IFV 功能代码。

## 2. 测试命令

以下命令均在项目根目录 `C:\Users\13081\Desktop\战地风云2035` 下以 Godot 授权模式运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --editor --path .\godot --import *> .\.tools\import-m20-qa.log; exit $LASTEXITCODE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m20_test.tscn *> .\.tools\m20-qa.log; exit $LASTEXITCODE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/smoke_test.tscn *> .\.tools\smoke-m20-qa.log; exit $LASTEXITCODE
```

## 3. 退出码与关键结果

| 测试项 | 退出码 | 关键结果 |
| --- | --- | --- |
| Godot 导入 | 0 | 无 `SCRIPT ERROR` / `Parse Error`，导入完成 |
| M20 专项 | 0 | `[M20Test] passed`，全部断言通过 |
| 常规冒烟 | 0 | `[SmokeTest] passed`，主场景回归通过 |

M20 专项关键断言：

- 实例化 `ifv.tscn` 并等待 2 帧后，`setup(Vector3(0, 2, 0), 0.5)` 成功，`is_alive()` 为 `true`，`health == 350.0`。
- `drive(1.0, 0.0, false, 1.0)` 无崩溃，动画快照包含 `speed`、`throttle`、`steer`、`turret_yaw`、`barrel_pitch`、`wheel_spin`。
- 网络快照包含 `position`、`yaw`、`health`、`max_health`、`alive`、`animation`。
- `apply_network_snapshot({"position": Vector3(5, 1, 6), "yaw": 1.0, "health": 120})` 后位置近似通过，`health == 120.0`。
- `can_fire_cannon()` 首次为 `true`，`try_fire_cannon()` 返回 `true`，随后 `can_fire_cannon()` 为 `false`。
- `take_damage(50.0)` 后 `health == 70.0`。
- 主场景加载后 `get_ifv()` 非空且存活，`entity_sync.get_entity_node("ifv")` 非空，`entity_broadcaster.get_entity_ids()` 包含 `"ifv"`，`get_ifv_engine()` 非空。

## 4. 全量回归

| 回归项 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- |
| M19 会话实体自动接入 | 0 | `[M19Test] passed` | `m20-m19_test.log` |
| M18 远端实体生成 | 0 | `[M18Test] passed` | `m20-m18_test.log` |
| M17 实时广播 | 0 | `[M17Test] passed` | `m20-m17_test.log` |
| M16 实体同步 | 0 | `[M16Test] passed` | `m20-m16_test.log` |
| M15 ENet 会话层 | 0 | `[M15Test] passed` | `m20-m15_test.log` |
| M14 征服模式 | 0 | `[M14Test] passed` | `m20-m14_test.log` |
| M13 伤害数字 | 0 | `[M13Test] passed` | `m20-m13_test.log` |
| M12 天气 | 0 | `[M12Test] passed` | `m20-m12_test.log` |
| M11 音频环境 | 0 | `[M11Test] passed` | `m20-m11_test.log` |
| M10 小地图 | 0 | `[M10Test] passed` | `m20-m10_test.log` |
| M9 坦克载具 | 0 | `[M9Test] passed` | `m20-m9_test.log` |
| M8 AI 载具可靠性 | 0 | `[M8Test] passed` | `m20-m8_test.log` |
| M7 性能发布 | 0 | `[M7Test] passed` | `m20-m7_test.log` |
| M6 网络存档 | 0 | `[M6Test] passed` | `m20-m6_test.log` |
| M5 部署菜单 | 0 | `[M5Test] passed` | `m20-m5_test.log` |
| M4 AI 战术 | 0 | `[M4Test] passed` | `m20-m4_test.log` |
| M3b 动画 | 0 | `[M3bTest] passed` | `m20-m3b_test.log` |
| 动画专项 | 0 | `[AnimationTest] passed` | `m20-animation_test.log` |
| 地形射线 | 0 | `[TerrainRayTest] passed` | `m20-terrain_ray_test.log` |
| 常规冒烟 | 0 | `[SmokeTest] passed` | `m20-smoke_test.log` |

## 5. 缺陷清单

- 未发现 M20 IFV 功能缺陷，未修改任何功能代码。
- 备注：M20 专项与常规冒烟退出时均出现 `WARNING: 8 ObjectDB instances were leaked at exit`。该警告在两个测试中表现一致，非 M20 新增或阻塞项，未影响退出码。

## 6. 结论

M20 IFV 步兵战车通过专项验收与常规冒烟回归。载具初始化、驱动接口、动画/网络快照、主炮冷却、伤害扣减及主场景实体/广播/引擎集成均符合验收要求。
