# 《战地2035》M17 实时实体状态广播 QA 独立验收报告

验收日期：2026-08-08
验收角色：QA（独立审核子智能体）实际执行 / Director 归档
验收对象：M17 实时实体状态广播层
验收范围：EntityBroadcaster 定时广播、主流程广播开关、两进程自动状态接收

## 1. 交付对象

- `godot/scripts/network/entity_broadcaster.gd`：定时广播器，支持启用/停用、广播间隔、实体 ID 管理、`broadcast_once()`、计数与状态查询。
- `godot/scripts/main.gd`：创建 EntityBroadcaster，注册 `player`、`jeep`、`tank`，主机创建房间时启用广播，离开房间时停用。
- QA 测试：`godot/tools/m17_test.gd/tscn`、`godot/tools/m17_client_test.gd/tscn`。

## 2. 测试命令与退出码

| 测试项 | 命令/场景 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- | --- |
| 资源导入 | `--headless --editor --path .\godot --import` | 0 | 无 `SCRIPT ERROR` / `Parse Error` | `import-m17-qa.log` |
| M17 两进程实时广播 | `res://tools/m17_test.tscn` | 0 | `[M17Test] passed` | `m17-qa.log` |
| 常规冒烟 | `res://tools/smoke_test.tscn` | 0 | `[SmokeTest] passed` | `smoke-m17-qa.log` |

## 3. M17 关键结果

- host 启用 EntityBroadcaster 后，不手动调用 `broadcast_entity_state`，`player_1` 状态由广播器自动定时发送。
- client 自动收到 `marker == 7`、`position` 近似 `Vector3(12.5, 0.0, -8.0)` 的状态，并回传 ack `[98, 1]`。
- host 收到 ack 时 `broadcaster.get_broadcast_count() > 0` 且 `is_enabled()` 为 true。
- Main 集成：创建房间后广播器启用且实体列表包含 `player`、`jeep`、`tank`；离开房间后广播器停用。

## 4. 全量回归

| 回归项 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- |
| M16 实体同步 | 0 | `[M16Test] passed` | `m17-m16_test.log` |
| M15 ENet 会话层 | 0 | `[M15Test] passed` | `m17-m15_test.log` |
| M14 征服模式 | 0 | `[M14Test] passed` | `m17-m14_test.log` |
| M13 伤害数字 | 0 | `[M13Test] passed` | `m17-m13_test.log` |
| M12 天气 | 0 | `[M12Test] passed` | `m17-m12_test.log` |
| M11 音频环境 | 0 | `[M11Test] passed` | `m17-m11_test.log` |
| M10 小地图 | 0 | `[M10Test] passed` | `m17-m10_test.log` |
| M9 坦克载具 | 0 | `[M9Test] passed` | `m17-m9_test.log` |
| M8 AI 载具可靠性 | 0 | `[M8Test] passed` | `m17-m8_test.log` |
| M7 性能发布 | 0 | `[M7Test] passed` | `m17-m7_test.log` |
| M6 网络存档 | 0 | `[M6Test] passed` | `m17-m6_test.log` |
| M5 部署菜单 | 0 | `[M5Test] passed` | `m17-m5_test.log` |
| M4 AI 战术 | 0 | `[M4Test] passed` | `m17-m4_test.log` |
| M3b 动画 | 0 | `[M3bTest] passed` | `m17-m3b_test.log` |
| 动画专项 | 0 | `[AnimationTest] passed` | `m17-animation_test.log` |
| 地形射线 | 0 | `[TerrainRayTest] passed` | `m17-terrain_ray_test.log` |
| 常规冒烟 | 0 | `[SmokeTest] passed` | `m17-smoke_test.log` |

## 5. 缺陷清单

- 未发现 M17 范围内 P0/P1 功能缺陷。
- Godot headless 退出时的 `ObjectDB instances were leaked` 为已知退出噪音，不影响测试结论。

## 6. 结论

M17 实时实体状态广播层通过 QA 独立验收与全量回归。EntityBroadcaster 可在两进程 ENet 会话中自动定时广播实体状态，主流程的房间生命周期开关满足本轮验收标准，可作为后续远端玩家/载具生成与实时同步的基础。
