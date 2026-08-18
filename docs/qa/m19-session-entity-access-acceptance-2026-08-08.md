# 《战地2035》M19 会话实体自动接入 QA 独立验收报告

验收日期：2026-08-08
验收角色：QA（独立审核子智能体）实际执行
验收对象：M19 会话实体自动接入层
验收范围：SessionEntityAccess 自动生成远端玩家与吉普实体、RemoteVehicle 本地快照应用、Main 场景会话接入集成

## 1. 交付对象

- `godot/tools/m19_test.gd/tscn`：host 两进程测试，负责创建 7795 端口会话、启用 SessionEntityAccess、启动 client、等待 `[95, 1]` ack，并验证本地 RemoteVehicle 与 Main 集成。
- `godot/tools/m19_client_test.gd/tscn`：client 测试，负责加入 7795 端口会话，统计并校验远端玩家与吉普实体快照，校验通过后回传 ack。
- 本 QA 验收报告。

备注：Godot `--import` 自动生成了 `godot/tools/m19_test.gd.uid` 与 `godot/tools/m19_client_test.gd.uid`，作为测试脚本的标准 UID 伴随文件。

## 2. 测试命令与退出码

| 测试项 | 命令/场景 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- | --- |
| 资源导入 | `--headless --editor --path .\godot --import` | 0 | 无 `SCRIPT ERROR` / `Parse Error` | `import-m19-qa.log` |
| M19 两进程会话实体自动接入 | `res://tools/m19_test.tscn` | 0 | `[M19Test] passed` | `m19-qa.log` |
| 常规冒烟 | `res://tools/smoke_test.tscn` | 0 | `[SmokeTest] passed` | `smoke-m19-qa.log` |

## 3. M19 关键结果

- host 成功执行 `host_session("M19Test", 7795)`，随后 `SessionEntityAccess.enable()` 生效。
- host 在约 10 帧后通过 `OS.create_process` 启动 client，client 成功执行 `join_session("127.0.0.1", 7795)`。
- client 共收到 2 次 `remote_entity_spawned`，其中：
  - 存在 `entity_id` 以 `remote_player_` 开头的节点，快照 `health == 100`，`display_name` 以 `Player` 开头。
  - 存在 `entity_id` 以 `remote_jeep_` 开头的节点，快照 `vehicle_type == "jeep"`，`health == 220.0`。
- client 全部校验通过后回传 ack `PackedByteArray([95, 1])`；host 在超时窗口内收到 ack，执行 `access.disable()` 与 `leave_session()`。
- 本地 RemoteVehicle 快照应用验证通过：`global_position` 近似 `Vector3(4, 1, 2)`，`health == 120.0`，`get_network_snapshot()["display_name"] == "LocalVehicle"`。
- Main 场景集成验证通过：`get_session_entity_access()`、`get_remote_entity_factory()`、`get_entity_sync()` 均可用；调用 `_on_host_session_requested("MainM19")` 后 `access.is_enabled()` 为 true；调用 `_on_leave_session_requested()` 后为 false。
- host 日志记录 `[M19Test] passed`，冒烟日志记录 `[SmokeTest] passed`。

## 4. 全量回归

| 回归项 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- |
| M18 远端实体生成 | 0 | `[M18Test] passed` | `m19-m18_test.log` |
| M17 实时广播 | 0 | `[M17Test] passed` | `m19-m17_test.log` |
| M16 实体同步 | 0 | `[M16Test] passed` | `m19-m16_test.log` |
| M15 ENet 会话层 | 0 | `[M15Test] passed` | `m19-m15_test.log` |
| M14 征服模式 | 0 | `[M14Test] passed` | `m19-m14_test.log` |
| M13 伤害数字 | 0 | `[M13Test] passed` | `m19-m13_test.log` |
| M12 天气 | 0 | `[M12Test] passed` | `m19-m12_test.log` |
| M11 音频环境 | 0 | `[M11Test] passed` | `m19-m11_test.log` |
| M10 小地图 | 0 | `[M10Test] passed` | `m19-m10_test.log` |
| M9 坦克载具 | 0 | `[M9Test] passed` | `m19-m9_test.log` |
| M8 AI 载具可靠性 | 0 | `[M8Test] passed` | `m19-m8_test.log` |
| M7 性能发布 | 0 | `[M7Test] passed` | `m19-m7_test.log` |
| M6 网络存档 | 0 | `[M6Test] passed` | `m19-m6_test.log` |
| M5 部署菜单 | 0 | `[M5Test] passed` | `m19-m5_test.log` |
| M4 AI 战术 | 0 | `[M4Test] passed` | `m19-m4_test.log` |
| M3b 动画 | 0 | `[M3bTest] passed` | `m19-m3b_test.log` |
| 动画专项 | 0 | `[AnimationTest] passed` | `m19-animation_test.log` |
| 地形射线 | 0 | `[TerrainRayTest] passed` | `m19-terrain_ray_test.log` |
| 常规冒烟 | 0 | `[SmokeTest] passed` | `m19-smoke_test.log` |

## 5. 缺陷清单

- 未发现 M19 范围内 P0/P1 功能缺陷。
- 无阻塞性问题。
- `ObjectDB instances were leaked` 为 Godot headless 已知退出噪音，不影响测试结论。

## 6. 结论

M19 会话实体自动接入通过 QA 独立验收。SessionEntityAccess 可在两进程 ENet 会话中自动生成远端玩家与吉普实体，client 快照校验与 ack 闭环通过；本地 RemoteVehicle 快照应用和 Main 场景接入开关行为满足本轮验收标准。本轮仅创建 QA 测试文件，未修改任何功能代码。
