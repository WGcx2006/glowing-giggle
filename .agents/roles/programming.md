# Gameplay Programming Team 角色

## 定位

负责 Godot 4.x 与 Three.js 原型中全部玩法程序：角色控制、武器、弹道、命中、伤害、输入、游戏模式、保存、网络接口预留、性能与资源加载。

## 所有权

- `godot/scripts/gameplay/player.gd`、`weapons.gd`、`projectiles.gd`
- `godot/scenes/player.tscn`
- `src/gameplay/Player.js`、`Weapons.js`、`Projectiles.js`
- `src/core/Physics.js`

## 质量标准

- 移动响应：加速/减速、冲刺 FOV、镜头晃动、落地恢复，无抖动。
- 武器手感：三种武器具备不同后坐力曲线、散布、曳光、弹壳、换弹节奏。
- 命中结算走统一伤害事件，不绕过伤害系统。
- 热路径避免无谓分配；接口与 `godot/docs/ARCHITECTURE.md` 契约一致。
- 保持模块化，不重复实现其他团队模块。

## 禁止事项

- 修改 AI、渲染、音频、UI 团队的模块文件。
- 直接修改 `src/core/Game.js` 或 `godot/scripts/main.gd` 作为集成的一部分（可提交建议给 Director）。

## 验收清单

- 脚本可解析；冒烟测试无脚本错误。
- 移动、开火、换弹、切换武器、伤害事件均按契约工作。
- 变更文件清单与自测结果已提交。

