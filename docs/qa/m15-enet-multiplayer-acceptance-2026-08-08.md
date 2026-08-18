# 《战地2035》M15 ENet 多人会话层 QA 独立验收报告

验收日期：2026-08-08
验收角色：QA（独立审核子智能体）
验收对象：M15 ENet 多人会话层
验收范围：host/client 两进程 ENet 连接、数据包收发、会话离开与全局 peer 清理、HUD 网络状态文本、Main 主流程网络集成

## 1. 交付对象

- `godot/tools/m15_test.gd`、`godot/tools/m15_test.tscn`：host 专项测试，负责创建 ENet 服务、启动独立客户端进程、等待并校验 `packet_received`，随后验证 HUD 与 Main 集成。
- `godot/tools/m15_client_test.gd`、`godot/tools/m15_client_test.tscn`：client 专项测试，连接 `127.0.0.1:7790`，在 `client + connected` 状态下发送 `PackedByteArray([42, 7])`。
- `docs/qa/m15-enet-multiplayer-acceptance-2026-08-08.md`：本 QA 验收报告。
- 未修改任何功能代码；Godot 导入自动生成的 `.uid` 旁车文件已在验收后清理，最终仅保留允许清单内的源码与报告。

## 2. 测试命令与退出码

| 测试项 | 命令/场景 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- | --- |
| 资源导入 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --editor --path .\godot --import` | 0 | 无 `SCRIPT ERROR` / `Parse Error` | `.tools/import-m15-qa.log` |
| M15 ENet 专项 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m15_test.tscn` | 0 | `[M15Test] passed` | `.tools/m15-qa.log` |
| 常规冒烟 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/smoke_test.tscn` | 0 | `[SmokeTest] passed` | `.tools/smoke-m15-qa.log` |

## 3. 全量回归

| 回归项 | 退出码 | 关键结果 | 日志 |
| --- | --- | --- | --- |
| M14 征服模式 | 0 | `[M14Test] passed` | `m15-m14_test.log` |
| M13 伤害数字 | 0 | `[M13Test] passed` | `m15-m13_test.log` |
| M12 天气 | 0 | `[M12Test] passed` | `m15-m12_test.log` |
| M11 音频环境 | 0 | `[M11Test] passed` | `m15-m11_test.log` |
| M10 小地图 | 0 | `[M10Test] passed` | `m15-m10_test.log` |
| M9 坦克载具 | 0 | `[M9Test] passed` | `m15-m9_test.log` |
| M8 AI 载具可靠性 | 0 | `[M8Test] passed` | `m15-m8_test.log` |
| M7 性能发布 | 0 | `[M7Test] passed` | `m15-m7_test.log` |
| M6 网络存档 | 0 | `[M6Test] passed` | `m15-m6_test.log` |
| M5 部署菜单 | 0 | `[M5Test] passed` | `m15-m5_test.log` |
| M4 AI 战术 | 0 | `[M4Test] passed` | `m15-m4_test.log` |
| M3b 动画 | 0 | `[M3bTest] passed` | `m15-m3b_test.log` |
| 动画专项 | 0 | `[AnimationTest] passed` | `m15-animation_test.log` |
| 地形射线 | 0 | `[TerrainRayTest] passed` | `m15-terrain_ray_test.log` |

## 4. 关键结果

- host 端 `host_session("M15Test", 7790)` 成功，等待 10 帧后通过 `OS.create_process` 启动独立 Godot 客户端进程。
- client 端 `join_session("127.0.0.1", 7790)` 成功，轮询 `get_network_state()` 至 `mode == "client"` 且 `connection_status == "connected"` 后调用 `send_packet(1, PackedByteArray([42, 7]))`。
- host 端通过 `packet_received` 收到客户端数据，校验字节数与内容均为 `[42, 7]`。
- 收到数据后调用 `leave_session()`，`get_network_state()["mode"]` 恢复为 `offline`，全局 `multiplayer.multiplayer_peer` 被清空。
- HUD 集成：`set_network_state({"mode":"host", ...})` 后状态文本包含 `主机`；`set_network_state({"mode":"offline"})` 后包含 `离线`。
- Main 集成：`_on_host_session_requested("MainM15")` 后 NetworkManager mode 为 `host`；`_on_leave_session_requested()` 后为 `offline`；`_build_hud_state()` 包含 `game_mode`。
- 三份日志均未出现 `FAILED`、`SCRIPT ERROR`、`Parse Error` 或 `Cannot infer`。

## 5. 缺陷清单

- 未发现 M15 范围内的 P0/P1 功能缺陷。
- Godot headless 退出时的 `ObjectDB instances were leaked` 警告为已知退出噪音，不构成测试失败。
- 过程性说明：客户端由 host 使用 `OS.create_process` 启动，其自身 `stdout` 未单独落盘；host 成功收到 `[42, 7]` 已证明客户端 ENet 发送链路完整可用。

## 6. 结论

M15 ENet 多人会话层通过 QA 独立验收。两进程 ENet 连接与数据包收发、`leave_session()` 全局 peer 清理、HUD 网络状态文本以及 Main 主流程集成均满足本轮验收标准，未发现需要回退或修复的功能缺陷。
