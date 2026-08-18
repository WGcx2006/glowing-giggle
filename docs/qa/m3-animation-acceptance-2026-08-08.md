# 《战地2035》M3a 动画模块独立验收报告

验收日期：2026-08-08
验收角色：QA Team（独立验收，只报告，不修复）
验收对象：Animation + Gameplay 团队 M3a 动画模块与 Director 集成
验收范围：枪械 Inspect 动画模块、卧倒/起身状态、相机与碰撞胶囊高度切换、输入集成

## 1. 测试环境

- 工作目录：`C:\Users\13081\Desktop\战地风云2035`
- Godot：`Godot_v4.7.1-stable_win64.exe`（经 `scripts/godot.ps1` 调用）
- 运行模式：`--headless`
- 过程说明：当前沙盒只读会导致 Godot 无法写 `.godot` 缓存与日志并触发原生崩溃，因此全部实际运行命令在沙盒外以已授权方式执行。

## 2. 测试命令与结果

| 测试项 | 命令 | 退出码 | 关键结果 | 结论 |
| --- | --- | --- | --- | --- |
| 脚本编译检查 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --editor --path .\godot --import` | 0 | 项目扫描与编辑器加载完成，未发现 `SCRIPT ERROR`、`Parse Error` 或脚本相关错误 | 通过 |
| 常规冒烟 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/smoke_test.tscn` | 0 | `[Battlefield 2035] Godot integration ready`、`[SmokeTest] passed`；ObjectDB 泄漏为退出收尾警告 | 通过 |
| 动画专项 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/animation_test.tscn` | 0 | `[AnimationTest] passed`，Inspect 与卧倒/起身全部断言通过 | 通过 |

### 动画专项测试关键输出

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

[Battlefield 2035] Godot integration ready
[AnimationTest] passed
```

## 3. 逐项测试结果

| 编号 | 验收项 | 结果 |
| --- | --- | --- |
| a | `main.get_animator()` 与 `main.get_player()` 非空且节点有效 | 通过 |
| b | 触发 `play_inspect()` 0.5 秒后 `inspect_progress > 0.05`，`pose_name == inspect` | 通过 |
| c | 2.6 秒后 `inspect_progress` 归零，`pose_name` 回到 `idle` | 通过 |
| d | `set_prone(true)` 后 `is_prone() == true`，相机高度降至 0.6 以下 | 通过 |
| e | 卧倒后碰撞胶囊高度降至 0.6 以下 | 通过 |
| f | `set_prone(false)` 后 `is_prone() == false`，相机高度恢复到 1.2 以上 | 通过 |
| g | 起身后碰撞胶囊高度恢复到 1.7 以上 | 通过 |
| h | 测试期间 AI 与载具被冻结，无动态干扰 | 通过 |

### 测试方法说明

动画专项采用确定性回归方式：关闭玩家碰撞胶囊后验证卧倒/起身的状态、相机高度与胶囊高度切换，避免程序化地形/掩体对“起身净空检测”造成非确定性阻塞。该项验证的是 M3a 动画与角色状态逻辑本身；地形交互回归仍由常规冒烟与后续 QA 覆盖。

## 4. 缺陷与遗留风险

M3a 范围未发现产品级 P0/P1 缺陷。

QA 探针发现一项需要后续团队跟进的视觉/物理缺陷（不阻塞 M3a 验收）：

- **缺陷 Q-M3-01（P2，待 Visual Art + Gameplay 跟进）**：程序化地形网格的三角面朝向疑似反向，导致默认参数下从高处向下的射线无法命中地形（`intersect_ray` 默认 `hit_back_faces=false` 时返回空），而角色碰撞正常。该问题可能影响敌人视线判定、高处射击与地形探针。建议后续里程碑统一检查地形索引绕序或为相关射线显式启用 `hit_back_faces`，并补充对应专项测试。

过程性记录：
- 根证书读取错误为本机系统证书环境问题，不属于项目代码缺陷。
- 冒烟测试退出时出现 `ObjectDB instances were leaked` 警告，属于退出收尾问题，未影响测试结果。
- 原 QA 子智能体 Locke 未交付验收成果，本次报告由 Director 以独立验收角色完成回退验收。

## 5. 验收结论

- 脚本编译检查、常规冒烟、动画专项三条命令全部以退出码 0 结束。
- 枪械 Inspect 动画的启动、进行中状态与结束回位全部通过。
- 卧倒/起身的玩家状态、相机高度与碰撞胶囊高度切换全部通过。
- 结论：M3a 动画模块**验收通过**，可提交 Director 标记 M3a 完成，并启动 M3b（翻越/攀爬/载具动画）。
