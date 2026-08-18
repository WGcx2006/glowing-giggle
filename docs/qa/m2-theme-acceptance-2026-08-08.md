# 《战地2035》M2 六地图主题框架独立验收报告

验收日期：2026-08-08
验收角色：QA Team（独立验收，只报告，不修复）
验收对象：Visual Art + Gameplay 团队六地图主题框架与 Director 集成
验收范围：Godot 4.7 六主题定义、初始主题、切换同步、视觉签名差异化

## 1. 测试环境

- 工作目录：`C:\Users\13081\Desktop\战地风云2035`
- Godot：`Godot_v4.7.1-stable_win64.exe`（经 `scripts/godot.ps1` 调用）
- 运行模式：`--headless`

## 2. 测试命令与结果

| 测试项 | 命令 | 退出码 | 关键结果 | 结论 |
| --- | --- | --- | --- | --- |
| 常规冒烟 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/smoke_test.tscn` | 0 | `[Battlefield 2035] Godot integration ready`、`[SmokeTest] passed`；根证书读取错误与本机环境有关，ObjectDB 泄漏为退出收尾警告 | 通过 |
| 脚本编译检查 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --editor --path .\godot --import` | 0 | 项目扫描与编辑器加载完成，未发现 `SCRIPT ERROR`、`Parse Error` 或脚本相关错误 | 通过 |
| 主题专项 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/theme_test.tscn` | 0 | `[ThemeTest] passed`，6 个主题切换与视觉签名检查全部通过 | 通过 |

### 主题专项测试关键输出

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

[Battlefield 2035] Godot integration ready
[ThemeTest] arctic signature=sky_top=1e395b sun_energy=0.5620 fog_light=88929c
[ThemeTest] desert signature=sky_top=2b5277 sun_energy=1.1042 fog_light=b59871
[ThemeTest] jungle signature=sky_top=214e73 sun_energy=0.9724 fog_light=89a491
[ThemeTest] urban signature=sky_top=475766 sun_energy=0.8500 fog_light=a8adad
[ThemeTest] coast signature=sky_top=1d5aa2 sun_energy=1.3813 fog_light=becad1
[ThemeTest] night_ops signature=sky_top=020307 sun_energy=0.1080 fog_light=07090d
[ThemeTest] passed
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
```

## 3. 逐项测试结果

| 编号 | 验收项 | 结果 |
| --- | --- | --- |
| a | `get_environment()` 非空且节点有效 | 通过 |
| b | `env.get_map_themes()` 返回 6 个主题，id 集合为 `arctic/desert/jungle/urban/coast/night_ops` | 通过 |
| c | 初始 `game.get_map_theme()` 与 `env.get_current_map_theme()` 均为 `arctic` | 通过 |
| d | 对 6 个主题调用 `game.set_map_theme(id)` 后，`game.get_map_theme()` 与 `env.get_current_map_theme()` 均同步为该 id，且每次切换后运行至少 2 帧 | 通过 |
| e | 每个主题采集 `Sky.sky_material.sky_top_color`、`Sky.sun.light_energy`、`PostFX.environment.fog_light_color` 视觉签名 | 通过 |
| f | 6 个主题视觉签名唯一数为 6，满足至少 5 个唯一签名要求 | 通过 |

### 六主题切换状态

| 主题 | `game.get_map_theme()` | `env.get_current_map_theme()` | 视觉签名（sky_top / sun_energy / fog_light） | 状态 |
| --- | --- | --- | --- | --- |
| arctic | arctic | arctic | `1e395b` / `0.5620` / `88929c` | 通过 |
| desert | desert | desert | `2b5277` / `1.1042` / `b59871` | 通过 |
| jungle | jungle | jungle | `214e73` / `0.9724` / `89a491` | 通过 |
| urban | urban | urban | `475766` / `0.8500` / `a8adad` | 通过 |
| coast | coast | coast | `1d5aa2` / `1.3813` / `becad1` | 通过 |
| night_ops | night_ops | night_ops | `020307` / `0.1080` / `07090d` | 通过 |

## 4. 缺陷清单

未发现产品级 P0/P1/P2 缺陷。

过程性记录：
- 根证书读取错误为本机系统证书环境问题，不属于项目代码缺陷。
- 冒烟测试退出时出现 `ObjectDB instances were leaked` 警告，属于退出收尾问题，未影响测试结果。
- 主题专项测试工具中的 `_game`/节点属性为 Variant 来源，相关局部变量均显式声明为 `float`、`String`、`Color` 等类型，避免 GDScript `:=` 类型推断解析失败。

## 5. 验收结论

- 常规冒烟、脚本编译检查、主题专项三条命令全部以退出码 0 结束。
- 六地图主题 id 集合、初始 `arctic` 状态、六次切换同步、每次切换至少 2 帧运行、六主题视觉签名差异化全部通过。
- 结论：M2 六地图主题框架**验收通过**，可提交 Director 标记 M2 完成。
