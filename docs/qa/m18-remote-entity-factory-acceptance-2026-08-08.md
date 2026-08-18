# 《战地2035》M18 远端实体生成 QA 独立验收报告

验收日期：2026-08-08
验收角色：QA（独立审核子智能体）实际执行 / Director 归档
验收对象：M18 远端实体生成层
验收范围：RemoteEntityFactory 两进程 spawn/despawn、RemotePlayer 快照应用、主流程 RemoteEntityFactory 集成

## 1. 交付对象

- `godot/tools/m18_test.gd/tscn`：host 两进程测试，负责创建 7794 端口会话、启动 client、请求生成与销毁 `remote_1`，并验证本地 RemotePlayer 与 Main 集成。
- `godot/tools/m18_client_test.gd/tscn`：client 测试，负责加入 7794 端口会话，校验远端实体快照并回传 spawn/despawn ack。
- 本 QA 验收报告。

备注：Godot `--import` 自动生成了 `godot/tools/m18_test.gd.uid` 与 `godot/tools/m18_client_test.gd.uid`，作为测试脚本的标准 UID 伴随文件。

## 2. 测试命令与退出码

| 测试项 | 命令/场景 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- | --- |
| 资源导入 | `--headless --editor --path .\godot --import` | 0 | 无 `SCRIPT ERROR` / `Parse Error` | `import-m18-qa.log` |
| M18 两进程远端实体生成 | `res://tools/m18_test.tscn` | 0 | `[M18Test] passed` | `m18-qa.log` |
| 常规冒烟 | `res://tools/smoke_test.tscn` | 0 | `[SmokeTest] passed` | `smoke-m18-qa.log` |

## 3. M18 关键结果

- host 成功执行 `host_session("M18Test", 7794)`，约 10 帧后通过 `OS.create_process` 启动 client。
- client 成功执行 `join_session("127.0.0.1", 7794)`，并实例化 NetworkManager、EntitySync、RemoteEntityFactory。
- host 在 `peer_connected` 中调用 `request_spawn` 返回 true，初始快照包含 `position=Vector3(20, 0, -10)`、`yaw=0.5`、`health=80`、`marker=3`、`display_name="HostPlayer"`。
- client 在 `remote_entity_spawned` 中确认 `entity_id == "remote_1"`、节点有效且具备 `get_network_snapshot()`，快照字段全部匹配后回传 ack `[97, 1]`。
- host 收到 `[97, 1]` 后调用 `request_despawn` 返回 true；client 在 `remote_entity_despawned` 中确认 `entity_id == "remote_1"` 并回传 ack `[97, 2]`。
- host 收到两个 ack 后执行 `leave_session()`。host 日志记录 `[M18Test] passed`，说明两进程 spawn/despawn 闭环通过。
- 本地 RemotePlayer 快照应用验证通过：`global_position` 近似 `Vector3(3, 4, 5)`、`health == 66`、`marker == 9`、`display_name == "LocalRemote"`。
- Main 场景验证通过：`get_remote_entity_factory()` 与 `get_entity_sync()` 可用，`factory.get_state()` 返回 Dictionary 且包含 `count`。

## 4. 全量回归

| 回归项 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- |
| M17 实时广播 | 0 | `[M17Test] passed` | `m18-m17_test.log` |
| M16 实体同步 | 0 | `[M16Test] passed` | `m18-m16_test.log` |
| M15 ENet 会话层 | 0 | `[M15Test] passed` | `m18-m15_test.log` |
| M14 征服模式 | 0 | `[M14Test] passed` | `m18-m14_test.log` |
| M13 伤害数字 | 0 | `[M13Test] passed` | `m18-m13_test.log` |
| M12 天气 | 0 | `[M12Test] passed` | `m18-m12_test.log` |
| M11 音频环境 | 0 | `[M11Test] passed` | `m18-m11_test.log` |
| M10 小地图 | 0 | `[M10Test] passed` | `m18-m10_test.log` |
| M9 坦克载具 | 0 | `[M9Test] passed` | `m18-m9_test.log` |
| M8 AI 载具可靠性 | 0 | `[M8Test] passed` | `m18-m8_test.log` |
| M7 性能发布 | 0 | `[M7Test] passed` | `m18-m7_test.log` |
| M6 网络存档 | 0 | `[M6Test] passed` | `m18-m6_test.log` |
| M5 部署菜单 | 0 | `[M5Test] passed` | `m18-m5_test.log` |
| M4 AI 战术 | 0 | `[M4Test] passed` | `m18-m4_test.log` |
| M3b 动画 | 0 | `[M3bTest] passed` | `m18-m3b_test.log` |
| 动画专项 | 0 | `[AnimationTest] passed` | `m18-animation_test.log` |
| 地形射线 | 0 | `[TerrainRayTest] passed` | `m18-terrain_ray_test.log` |
| 常规冒烟 | 0 | `[SmokeTest] passed` | `m18-smoke_test.log` |

## 5. 备注

- client 由 host 通过 `OS.create_process` 启动，其 stdout 未合并进 host 日志；client 只有在全部快照断言通过后才会发送 `[97, 1]`，因此 host 收到两个 ack 即证明 client 校验通过。
- 本轮仅创建 QA 测试文件，未修改任何功能代码。
- `ObjectDB instances were leaked` 为 Godot headless 已知退出噪音，部分运行出现，不影响测试结论。

## 6. 缺陷清单

- 未发现 M18 范围内 P0/P1 功能缺陷。
- 无阻塞性问题。

## 7. 结论

M18 远端实体生成通过 QA 独立验收。RemoteEntityFactory 可在两进程 ENet 会话中完成远端实体生成、快照应用、销毁与 ack 闭环；RemotePlayer 快照 API 与主流程集成满足本轮验收标准。
