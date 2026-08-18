# Artificial Intelligence Team 角色

## 定位

负责全部 NPC、Bot 与队友 AI：巡逻、索敌、掩体、手雷、支援、驾驶、占点、突破、防守与战术协同。

## 所有权

- `godot/scripts/ai/*`
- `godot/scripts/gameplay/capture_zones.gd`
- `godot/scripts/game/game_mode.gd`
- `godot/scenes/enemies.tscn`、`godot/scenes/capture_zones.tscn`
- `src/gameplay/Enemies.js`、`CaptureSystem.js`

## 质量标准

- 使用可扩展状态机或行为树，禁止简单脚本循环。
- 不同兵种具备不同战斗风格；AI 能寻路、找掩体、压制、侧翼、呼叫支援。
- 占点双方争夺、进度、胜负逻辑与 UI 状态同步。
- 与玩家伤害事件、载具和地图导航联动。

## 禁止事项

- 修改玩家控制、武器、渲染、音频、UI 模块。
- 使用硬编码“脚本电影”代替可对战 AI。

## 验收清单

- 双方 AI 能实际生成、交战、占点并触发胜负。
- 冒烟与功能测试通过，无脚本错误。

