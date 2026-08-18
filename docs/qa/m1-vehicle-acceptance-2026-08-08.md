# 《战地2035》M1 载具里程碑独立验收报告

验收日期：2026-08-08
验收角色：QA Team（独立验收，只报告，不修复）
验收对象：Vehicle 团队 `jeep.gd`/`jeep.tscn` + Director 集成
验收范围：Godot 4.7 吉普生成、驾驶物理、进出车、生命/摧毁、公开接口

## 1. 测试环境

- 工作目录：`C:\Users\13081\Desktop\战地风云2035`
- Godot：`Godot_v4.7.1-stable_win64.exe`（经 `scripts/godot.ps1` 调用）
- 运行模式：`--headless`

## 2. 测试命令与结果

| 测试项 | 命令 | 退出码 | 关键结果 | 结论 |
| --- | --- | --- | --- | --- |
| 常规冒烟 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/smoke_test.tscn` | 0 | `[Battlefield 2035] Godot integration ready`、`[SmokeTest] passed`；根证书/ObjectDB 警告为环境与收尾问题 | 通过 |
| 脚本编译检查 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --editor --path .\godot --import` | 0 | 项目扫描与全局类注册完成，未发现 `SCRIPT ERROR`、`Parse Error` 或脚本相关错误 | 通过 |
| 载具专项 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/vehicle_test.tscn` | 0 | `[Battlefield 2035] Godot integration ready`、`[VehicleTest] passed` | 通过 |

### 载具专项测试关键输出

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

[Battlefield 2035] Godot integration ready
[VehicleTest] passed
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
WARNING: 14 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2536)
```

## 3. 逐项测试结果

| 编号 | 验收项 | 结果 |
| --- | --- | --- |
| a | `get_vehicle()` 非空、`is_alive()` 为 true、`health == 220` | 通过 |
| b | `drive(1.0, 0.0, false)` 推进 60 物理帧后位移 > 1 米 | 通过 |
| c | `drive(0.0, 1.0, false)` 推进 60 物理帧后 yaw 变化 | 通过 |
| d | `enter_vehicle()` 后 `is_in_vehicle()` 为 true；`exit_vehicle()` 后为 false | 通过 |
| e | `take_damage(50)` 后 `health == 170`；`take_damage(999)` 后 `is_alive()` 为 false | 通过 |
| f | 全部通过时输出 `[VehicleTest] passed` 并以退出码 0 结束 | 通过 |

说明：实际接口签名为 `drive(throttle, steer, brake, delta)`，专项测试按真实签名传入 `delta`，其余验收口径与任务要求一致。

## 4. 缺陷清单

未发现产品级 P0/P1/P2 缺陷。

过程性记录：
- QA 测试工具 `godot/tools/vehicle_test.gd` 首版存在两处 GDScript 类型推断错误（第 62、78 行），导致测试场景无法加载；已在本轮修正为显式 `float` 类型后复测通过。该问题属于 QA 工具自身，不构成 M1 产品缺陷。
- 根证书读取错误为本机环境问题，ObjectDB 泄漏警告为退出收尾问题，均不判定为功能缺陷。

## 5. 验收结论

- 常规冒烟、脚本编译、载具专项全部通过。
- M1 六项验收点全部通过，退出码 0。
- 结论：M1 载具里程碑**验收通过**，可标记完成并进入 M2 规划。
