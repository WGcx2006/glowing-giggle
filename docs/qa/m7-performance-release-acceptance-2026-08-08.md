# 《战地2035》M7 性能优化与发布前回归独立验收报告

验收日期：2026-08-08
验收角色：QA Team（独立验收，只报告，不修复）
验收对象：Performance/Release 团队 M7 里程碑
验收范围：性能监控契约、采样稳定性、质量档切换、M6 及此前里程碑全量回归、代码抽查、发布前性能验收清单

## 1. 测试环境

- 工作目录：`C:\Users\13081\Desktop\战地风云2035`
- Godot：`Godot_v4.7.1-stable_win64.exe`（经 `scripts/godot.ps1` 调用）
- 运行模式：`--headless`
- 过程说明：当前沙盒只读会导致 Godot 无法写 `.godot` 缓存与日志并触发原生崩溃，因此全部实际运行命令在沙盒外以已授权方式执行，日志写入 `.tools` 目录。
- 性能边界：本环境为无头模式，`[M7Test]` 验证的是性能监控契约、采样稳定性与质量切换逻辑，不代表实体 GPU 帧率；实体 GPU 帧率验收必须在发布前按第 6 节清单人工执行。
- 本报告仅记录与验收，未修改任何源码。

## 2. 测试命令与结果

| 测试项 | 命令 | 退出码 | 关键结果 | 结论 |
| --- | --- | --- | --- | --- |
| 导入/编译检查 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --editor --path .\godot --import` | 0 | 项目扫描与编辑器加载完成，未发现 `SCRIPT ERROR`、`Parse Error`、`Cannot infer` | 通过 |
| 常规冒烟 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/smoke_test.tscn` | 0 | `[Battlefield 2035] Godot integration ready`、`[SmokeTest] passed` | 通过 |
| M7 专项 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m7_test.tscn` | 0 | `[M7Test] passed` | 通过 |
| M6 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m6_test.tscn` | 0 | `[M6Test] passed` | 通过 |
| M5 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m5_test.tscn` | 0 | `[M5Test] passed` | 通过 |
| M4 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m4_test.tscn` | 0 | `[M4Test] passed` | 通过 |
| M3b 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/m3b_test.tscn` | 0 | `[M3bTest] passed` | 通过 |
| M3a 回归 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/animation_test.tscn` | 0 | `[AnimationTest] passed` | 通过 |

日志文件：

- `.tools/qa-m7-import.log`
- `.tools/qa-m7-smoke.log`
- `.tools/qa-m7-m7.log`
- `.tools/qa-m7-m6.log`
- `.tools/qa-m7-m5.log`
- `.tools/qa-m7-m4.log`
- `.tools/qa-m7-m3b.log`
- `.tools/qa-m7-animation.log`

过程性说明：M7 专项与 M5 回归退出时 Godot 报告 `3` 与 `8` 个 `ObjectDB instances were leaked at exit` 警告，外层 PowerShell 将原生 stderr 包装为 `NativeCommandError`；以 `QA_EXIT_CODE` 复核实际退出码均为 0，日志仍出现对应 passed 标记。该现象与此前里程碑验收记录一致，属于退出收尾警告，不构成测试失败。

## 3. 逐项测试结果

| 编号 | 验收项 | 结果 |
| --- | --- | --- |
| a | 导入/编译检查通过，无脚本解析或类型推断错误 | 通过 |
| b | 常规冒烟通过，主场景与集成初始化正常 | 通过 |
| c | 性能监控器可在 `_process` 中持续采样 | 通过 |
| d | 连续两次采样（各 120 帧）快照键齐全，`avg_fps` 有效 | 通过 |
| e | 两次采样间未出现明显性能劣化（第二次不低于第一次 50%） | 通过 |
| f | 对象计数正常，`object_count` 大于 0 | 通过 |
| g | 切换 low 档后性能快照仍有效，`quality_recommendation` 非空 | 通过 |
| h | M6 回归：网络接口预留与保存系统专项通过 | 通过 |
| i | M5 回归：部署界面与完整主菜单专项通过 | 通过 |
| j | M4 回归：AI 战术行为专项通过 | 通过 |
| k | M3b 回归：翻越/攀爬/载具动画专项通过 | 通过 |
| l | M3a 回归：Inspect 动画、卧倒/起身状态专项通过 | 通过 |

## 4. 代码抽查结果

| 文件 | 抽查项 | 结果 |
| --- | --- | --- |
| `godot/scripts/performance/performance_monitor.gd` | 包含 `sample/reset/get_avg_fps/get_quality_recommendation/get_performance_snapshot`；快照键包含 `fps/avg_fps/min_fps/frame_time_ms/process_time_ms/physics_time_ms/object_count/node_count/physics_active_objects/memory_static_mb/memory_dynamic_mb/quality_recommendation` | 通过 |
| `godot/scripts/main.gd` | 包含 `get_performance_monitor()`，并在 `_process` 中调用 `_performance_monitor.sample(delta)` | 通过 |

关键代码位置：

- `performance_monitor.gd`：`sample(delta)` 第 20 行、`reset()` 第 30 行、`get_avg_fps()` 第 36 行、`get_quality_recommendation()` 第 45 行、`get_performance_snapshot()` 第 56 行；快照键 `fps` 第 58 行、`avg_fps` 第 59 行、`min_fps` 第 60 行、`frame_time_ms` 第 61 行、`process_time_ms` 第 62 行、`physics_time_ms` 第 63 行、`object_count` 第 64 行、`node_count` 第 65 行、`physics_active_objects` 第 66 行、`memory_static_mb` 第 67 行、`memory_dynamic_mb` 第 68 行、`quality_recommendation` 第 69 行。
- `main.gd`：`_performance_monitor.sample(delta)` 第 67 行；`get_performance_monitor()` 第 559 行。

## 5. 缺陷清单

M7 范围未发现 P0/P1 缺陷。

- **Q-M7-01（P2，遗留，不阻塞）**：程序化地形网格背面射线问题仍存在，已在 M3a 报告跟踪；建议在发布前检查地形三角面索引绕序，或为相关射线显式启用背面命中。
- **Q-M7-02（P3，流程项，不阻塞）**：无头性能指标不能代表实体 GPU 帧率；本次 `[M7Test]` 只验证监控契约、采样稳定性与质量切换，实体 GPU 验收按第 6 节清单执行。
- **Q-M7-03（P3，遗留打磨，不阻塞）**：AI 载具路径控制仍为打磨项，需在后续版本继续调优。
- **Q-M7-04（P3，兼容性说明，不阻塞）**：Godot 4.7.1 已移除 `MEMORY_DYNAMIC` 与 `PHYSICS_ACTIVE_OBJECTS` 监控，`memory_dynamic_mb` 当前取自 `MEMORY_MESSAGE_BUFFER_MAX`、`physics_active_objects` 当前取自 `PHYSICS_3D_ACTIVE_OBJECTS`；快照契约键完整，但字段语义为替代监控，实体 GPU 验收时应结合帧率与画面完整性判断有效性。
- **过程性记录**：M7 专项与 M5 回归退出时出现 `ObjectDB instances were leaked` 警告，属于退出收尾问题，不影响测试结果；外层 PowerShell 对原生 stderr 的包装误报已通过 `QA_EXIT_CODE` 复核排除。

## 6. 实体 GPU 发布前人工验收清单

以下项目必须在真实图形环境中完成，作为发布前人工验收项，不可由本次无头结果替代：

| 编号 | 验收项 | 结果 |
| --- | --- | --- |
| G1 | 使用 Godot 4.7 启动主场景（非 headless），确认窗口、HUD、地形与载具正常显示 | 待人工执行 |
| G2 | low 档运行并连续采样 60 秒，记录平均 FPS 与最低 FPS | 待人工执行 |
| G3 | medium 档运行并连续采样 60 秒，记录平均 FPS 与最低 FPS | 待人工执行 |
| G4 | high 档运行并连续采样 60 秒，记录平均 FPS 与最低 FPS | 待人工执行 |
| G5 | ultra 档运行并连续采样 60 秒，记录平均 FPS 与最低 FPS | 待人工执行 |
| G6 | 四档各截取画面，检查画面完整性（无黑屏、无缺失地形、无 HUD 重叠/截断） | 待人工执行 |
| G7 | 确认性能监控快照中的 `quality_recommendation` 与当前画质档位一致 | 待人工执行 |

## 7. 验收结论

- 导入/编译检查、常规冒烟、M7 专项、M6/M5/M4/M3b/M3a 回归共八条命令的 Godot/godot.ps1 退出码均为 0，日志均出现对应 passed 标记；导入日志未发现 `SCRIPT ERROR`、`Parse Error`、`Cannot infer`。
- 性能监控契约、采样稳定性与质量切换专项通过，代码抽查无缺失；实体 GPU 帧率验收清单已列入发布前人工验收项。
- 未发现 P0/P1 缺陷，仅存在 M3a 已跟踪的 P2 遗留风险及 P3 级兼容性/流程/打磨项。
- 结论：M7 性能优化与发布前回归**验收通过（发布前回归）**，可提交 Director 标记 M7 完成；实体 GPU 清单（G1-G7）完成后可进行最终发布。
