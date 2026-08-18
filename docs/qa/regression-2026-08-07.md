# 《战地2035》修复轮回归验收报告

验收日期：2026-08-07
验收角色：QA Team（独立回归，只报告，不修复）
回归对象：`docs/qa/baseline-2026-08-07.md` 中 13 项缺陷（P1-1 至 P2-9）及上轮新增的 2 项 P2 风险
验收范围：Godot 移植版 + Three.js Web 原型

## 1. 测试环境

- 工作目录：`C:\Users\13081\Desktop\战地风云2035`
- Godot：`Godot_v4.7.1-stable_win64.exe`
- Node.js：v24.14.0，pnpm：11.16.0，Vite：6.4.3
- Playwright 未安装，本次不执行浏览器冒烟

## 2. 测试命令与结果

| 测试项 | 命令 | 退出码 | 关键结果 | 结论 |
| --- | --- | --- | --- | --- |
| Godot 冒烟测试 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --path .\godot res://tools/smoke_test.tscn` | 0 | `[Battlefield 2035] Godot integration ready`、`[SmokeTest] passed`；另有根证书与 ObjectDB 警告 | 通过 |
| Godot 脚本编译检查 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\godot.ps1 --headless --editor --path .\godot --import` | 0 | 项目扫描完成，未发现 `SCRIPT ERROR`、`Parse Error` 或脚本相关错误 | 通过 |
| Web 原型构建验证 | `CI=true pnpm build`（沙箱 EPERM，非沙箱重跑） | 0 | 39 个模块转换成功，`dist/` 生成；主包 706.04 kB，仍有 Vite 500 kB 阈值警告 | 通过 |

### Godot 冒烟测试关键输出

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

[Battlefield 2035] Godot integration ready
[SmokeTest] passed
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
WARNING: 12 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2536)
```

根证书错误仍为本机环境问题，ObjectDB 泄漏仍为退出收尾警告，均不判定为功能阻断。

最终复核于 2026-08-07 独立重跑上述三项命令，退出码均为 0；`pnpm build` 首次在沙箱内因 `node_modules/.pnpm` 硬链接 EPERM 失败，随后按约定以 `CI=true` 非沙箱权限重跑成功。

## 3. 缺陷逐条状态表

| 编号 | 回归要点 | 证据 | 状态 |
| --- | --- | --- | --- |
| P1-1 | Web 地形射线接入 PhysicsWorld、Projectiles、Enemies | `src/core/Physics.js:77` 支持 `{ ignore, terrain }`；`src/render/Terrain.js:230` 新增 `raycast()`；`src/gameplay/Projectiles.js:50`、`src/gameplay/Enemies.js:438` 均传入地形 | Fixed |
| P1-2 | Web 近点忽略只排除射手 | `src/gameplay/Projectiles.js:49` 改为 `#isShooterSphere`，`src/gameplay/Projectiles.js:389` 仅比较 source 实体 | Fixed |
| P1-3 | Web 手雷按地形高度反弹 | `src/gameplay/Projectiles.js:236` 读取 `#terrainHeight()`，并配合地形射线 | Fixed |
| P1-4 | Web/Godot 火箭与手雷发射、输入、爆炸链路 | Web：`src/gameplay/Weapons.js:59-91` 新弹种、`src/core/Game.js:79-90` 分发、`src/core/Game.js:166-167` 5/6 键；Godot：`godot/scripts/gameplay/weapons.gd:69-108`、`godot/scripts/gameplay/projectiles.gd:19`、新增 `godot/scripts/gameplay/projectile_body.gd`、`godot/scripts/gameplay/player.gd:234-237`、`godot/scripts/main.gd:131,228-242` | Fixed |
| P2-1 | Web `game:wave` 有发送方 | `src/gameplay/Enemies.js:56,64` emit `game:wave`；HUD 与音频监听已存在 | Fixed |
| P2-2 | 玩家受伤不再误显命中标记 | `src/ui/HUD.js:478` 增加 `target === 'player'` 判断 | Fixed |
| P2-3 | Web 弹道热路径复用对象 | `src/gameplay/Projectiles.js:15,31-36,287-345,347-387` 使用 tracer/decal 池；`src/core/Physics.js:7-13` 复用 Ray/Box3/Sphere 临时对象 | Fixed |
| P2-4 | Godot 敌方子弹只做一次命中结算 | `godot/scripts/ai/enemy.gd:416-443` 单条 `_apply_shot` 完成敌人/玩家结算，`godot/scripts/main.gd:213-220` 仅取 tracer 端点，不再重复伤害结算 | Fixed |
| P2-5 | Godot HUD 状态不再每帧重建 | `godot/scripts/main.gd:34,60-63` 使用 `_hud_dirty`；`godot/scripts/main.gd:66-71` 仅在变化时构建 HUD 状态 | Fixed |
| P2-6 | Godot 友军曳光按队伍区分 | `godot/scripts/main.gd:216` 按 `team == "blue"` 选择蓝色曳光 | Fixed |
| P2-7 | Godot 命中特效使用真实法线 | `godot/scripts/gameplay/projectiles.gd:4,48` 增加 normal；`godot/scripts/main.gd:205-210` 使用 normal；敌方命中经 `enemy_hit_player(point, normal)` | Fixed |
| P2-8 | Godot 目标文案统一中文 | `godot/scripts/game/game_mode.gd:68-69,73-94` 全部改为中文 | Fixed |
| P2-9 | Godot DMR 独立枪声 | `godot/scripts/audio/audio_manager.gd:35-36,142` 增加 dmr/marksman 音色变体，`_make_dmr_stream()` 已定义 | Fixed |

状态汇总：Fixed 13 / Open 0。

### 3.1 新增 P2 项复核

| 编号 | 复核要点 | 证据 | 状态 |
| --- | --- | --- | --- |
| R1 | Godot 爆炸范围伤害按 source/队伍过滤友军 | `godot/scripts/main.gd:236-249`：`player`/`blue` 不伤蓝方，`red` 不伤红方，与 Web `EnemySystem.#handleExplosion` 规则一致 | Fixed |
| R2 | Web/Godot 新弹种音频映射 | `src/audio/AudioManager.js:79-108` 新增 `rocket_launcher` 与 `grenade` 配置；`godot/scripts/audio/audio_manager.gd:39-50` 映射 `rocket_launcher` 到发射器音色、`grenade` 到独立短促音色，`_make_grenade_stream()` 已定义 | Fixed |

新增项状态汇总：Fixed 2 / Open 0。

## 4. 剩余风险

- 已修复并验证：Godot 爆炸范围伤害已在 `godot/scripts/main.gd:236-249` 按 `source`/队伍过滤，不再误伤友军。
- 已修复并验证：Web `AudioManager` 已新增 `rocket_launcher`/`grenade` 音色；Godot `audio_manager.gd` 已映射两类新弹种音色。
- P2-4 残留：敌方 tracer 端点仍额外执行一次射线，但不再重复命中结算，可接受。
- P2-5 残留：`game_mode.gd` 与 `capture_zones.get_control_state()` 仍存在少量每帧字典分配，HUD 已改为脏标记，性能影响显著降低。
- P2-3 残留：Web 火箭/手雷网格仍按发射次数新建，属低频操作，可接受。
- ObjectDB 泄漏警告由基线 8 个增至 12 个，仍为退出收尾问题，建议后续排查。
- 未执行浏览器动态验证；Web 侧结论基于构建成功与静态核对，建议在最终验收前补充一次浏览器冒烟/性能采样。

## 5. 结论

- 最终回归结论：原 13 项全部 Fixed，新增 2 项 P2 风险已修复并验证，总计 Fixed 15 / Open 0。
- 验收标准：P0 为 0、P1 全部关闭，且未发现阻断性回归，本次回归验收**通过**。
- 基线结论：可进入 Director 最终验收阶段；剩余项仅为性能与浏览器动态验证建议，不阻断本次回归验收。
