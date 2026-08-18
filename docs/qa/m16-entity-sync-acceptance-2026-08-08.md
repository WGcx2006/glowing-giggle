# 《战地2035》M16 多人实体同步层 QA 独立验收报告

验收日期：2026-08-08
验收角色：QA（独立审核子智能体）发现缺陷 / Director 回退复测
验收对象：M16 多人实体同步层
验收范围：NetworkEntitySync、玩家/吉普/坦克网络快照、主流程实体注册、两进程实体状态传输

## 1. 交付对象

- `godot/scripts/network/entity_sync.gd`：通用实体同步组件，支持注册、定向/广播发送、接收应用与 `entity_state_received` 事件，并带 `PACKET_PREFIX` 前缀校验。
- `godot/scripts/gameplay/player.gd`：新增 `get_network_snapshot()` 与 `apply_network_snapshot()`。
- `godot/scripts/vehicles/jeep.gd`、`godot/scripts/vehicles/tank.gd`：新增相同网络快照 API。
- `godot/scripts/main.gd`：实例化 EntitySync 并注册 `player`、`jeep`、`tank`。
- QA 测试：`godot/tools/m16_test.gd/tscn`、`godot/tools/m16_client_test.gd/tscn`。

## 2. 测试命令与退出码

| 测试项 | 命令/场景 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- | --- |
| 资源导入 | `--headless --editor --path .\godot --import` | 0 | 无 `SCRIPT ERROR` / `Parse Error` | `import-m16-director.log` |
| M16 两进程实体同步 | `res://tools/m16_test.tscn` | 0 | `[M16Test] passed` | `m16-director-test.log` |
| 常规冒烟 | `res://tools/smoke_test.tscn` | 0 | `[SmokeTest] passed` | `m16-director-smoke.log` |

## 3. M16 关键结果

- host 通过 EntitySync 广播 `player_1` 状态，client 收到 `marker == 7`、`position` 近似 `Vector3(12.5, 0.0, -8.0)`，并回传 ack `[99, 1]`。
- 吉普与坦克的 `get_network_snapshot()` / `apply_network_snapshot()` 验证通过，位置、yaw、生命值均可应用。
- Main 场景 EntitySync 已注册 `player`、`jeep`、`tank`；玩家快照应用 `health == 77` 通过。
- 修复后日志无 `decode_variant`、`Condition "len < 4"`、`SCRIPT ERROR` 或 `Parse Error`。

## 4. 全量回归

| 回归项 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- |
| M15 ENet 会话层 | 0 | `[M15Test] passed` | `m16-m15_test.log` |
| M14 征服模式 | 0 | `[M14Test] passed` | `m16-m14_test.log` |
| M13 伤害数字 | 0 | `[M13Test] passed` | `m16-m13_test.log` |
| M12 天气 | 0 | `[M12Test] passed` | `m16-m12_test.log` |
| M11 音频环境 | 0 | `[M11Test] passed` | `m16-m11_test.log` |
| M10 小地图 | 0 | `[M10Test] passed` | `m16-m10_test.log` |
| M9 坦克载具 | 0 | `[M9Test] passed` | `m16-m9_test.log` |
| M8 AI 载具可靠性 | 0 | `[M8Test] passed` | `m16-m8_test.log` |
| M7 性能发布 | 0 | `[M7Test] passed` | `m16-m7_test.log` |
| M6 网络存档 | 0 | `[M6Test] passed` | `m16-m6_test.log` |
| M5 部署菜单 | 0 | `[M5Test] passed` | `m16-m5_test.log` |
| M4 AI 战术 | 0 | `[M4Test] passed` | `m16-m4_test.log` |
| M3b 动画 | 0 | `[M3bTest] passed` | `m16-m3b_test.log` |
| 动画专项 | 0 | `[AnimationTest] passed` | `m16-animation_test.log` |
| 地形射线 | 0 | `[TerrainRayTest] passed` | `m16-terrain_ray_test.log` |
| 常规冒烟 | 0 | `[SmokeTest] passed` | `m16-smoke_test.log` |

## 5. 缺陷清单

- P2：EntitySync 对非 EntitySync 原始 ack 包直接调用 `bytes_to_var`，触发 `decode_variant` 的 `len < 4` 错误；已由 Network 子智能体修复为 `PACKET_PREFIX` 前缀校验，非同步包直接忽略。
- 修复期间 `const PACKET_PREFIX := PackedByteArray(...)` 非常量表达式编译错误也已修正为 `var`。
- 复测后无剩余 P0/P1 缺陷；`ObjectDB instances were leaked` 为 Godot headless 已知退出噪音。

## 6. 结论

M16 多人实体同步层通过 QA 验收与全量回归。EntitySync 可在两进程间可靠传输并应用实体状态，玩家与吉普/坦克快照 API、主流程实体注册均满足本轮验收标准，可作为后续远端玩家/载具生成与同步的基础。
