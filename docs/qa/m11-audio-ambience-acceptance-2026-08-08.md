# 《战地2035》M11 环境与载具引擎音频验收报告

验收日期：2026-08-08
验收角色：QA / Director 回退验收
验收对象：Audio 团队 M11 里程碑
验收范围：程序化载具引擎声、环境风噪、主场景挂接

## 1. 交付内容

- Audio 子智能体：新建 `godot/scripts/audio/vehicle_engine.gd` 与 `godot/scripts/audio/ambient_audio.gd`。
  - 引擎声：22050Hz 16 位单声道循环流，音高/音量随车辆速度变化，车辆失效时衰减停止。
  - 风噪：2 秒低通噪声循环 + LFO 音量起伏，环境强度 0.6~1.0。
- Director 集成：在 `main.gd` 为吉普与坦克各挂接一个引擎节点，并为主场景挂接环境风噪。

## 2. 验证结果

| 测试项 | 命令 | 退出码 | 关键结果 |
| --- | --- | --- | --- |
| 脚本编译 | `--import` | 0 | 无 `SCRIPT ERROR` / `Parse Error` / `Cannot infer` |
| M11 专项 | `res://tools/m11_test.tscn` | 0 | `[M11Test] passed`：引擎激活、RPM/音高随速度变化、环境风噪激活与强度 |
| 常规冒烟 | `res://tools/smoke_test.tscn` | 0 | `[SmokeTest] passed` |
| 地形射线 | `res://tools/terrain_ray_test.tscn` | 0 | `[TerrainRayTest] passed` |
| M10/M9/M8/M7/M6/M5/M4/M3b/M3a 回归 | 对应测试场景 | 0 | 全部 passed |

## 3. 结论

M11 环境与载具引擎音频通过全量回归，未发现新 P0/P1 缺陷。实际听感与空间混响仍需实体设备/GPU 验收中复核。
