# 战地风云 2035

基于 Three.js 的中型战术射击游戏：4 个阵地争夺、双方 AI 阵营、程序化 PBR 场景、WebAudio 音效与完整 HUD。仓库同时包含一个可独立运行的 Godot 4 移植版，位于 `godot/`。

## 开发体系

项目采用多智能体工业级开发流程：由 Project Director 统一调度 Gameplay Programming、AI、Visual Art、Audio、Animation、Vehicle、UI/UX 与 QA 八个专业团队。团队章程、模块所有权与验收流程见 `docs/全流程执行提示词.md`，各团队角色文档位于 `.agents/roles/`。

## 团队规则

- 双方各有 6 名 AI 士兵，玩家属于蓝方，合计蓝方 7 名单位、红方 6 名单位。
- 地图上有 4 个阵地：A 东侧仓库、B 西侧断桥、C 北侧哨塔、D 南侧海岸。蓝方与红方各控制 2 个。
- 站在无人防守的阵地内会持续占领；双方同时在场时阵地进入争夺状态。
- 胜利条件：占领全部 4 个阵地，或消灭对方全部士兵。蓝方胜利/红方胜利时显示胜负结算，可重新开局。

## 操作

- `WASD` 移动，`Shift` 冲刺，`Ctrl` 下蹲，`Space` 跳跃，靠近低墙按 `Space` 翻越/攀爬。
- 鼠标左键开火，右键机瞄，`R` 换弹，`1/2/3/4/5` 切换武器（4 火箭筒、5 手雷）。
- `E` 靠近吉普后进入/退出驾驶，驾驶时 `W/S` 油门/刹车、`A/D` 转向。
- `X` 卧倒/起身，`G` 检视武器。
- 视角与武器视模型已优化：更快的加速/减速、鼠标平滑、奔跑 FOV、低幅镜头晃动，出生点不再被掩体卡住。
- 默认鼠标灵敏度已降低，主菜单提供灵敏度滑杆（0.4x-1.6x）；跳跃高度降低、重力加大，起跳与落地更跟手。

## 运行

需要 Node.js 18+ 与 pnpm：

```bash
pnpm install
pnpm dev
```

浏览器打开 `http://localhost:5199`。

Windows 用户也可以直接双击 `start-game.bat` 一键启动：自动检测依赖、启动服务器并打开浏览器。

## 截图与盲测

```bash
pnpm add -D playwright   # 仅截图工具需要，首次执行一次
pnpm build
node scripts/visual-review.mjs
```

截图输出到 `public/screenshots/`（已 gitignore，不入库），随后打开 `http://localhost:5199/blindtest.html` 或 `godot-blindtest.html` 进行 A/B 盲测。默认使用 Playwright 自带的 Chromium；如需指定系统 Chrome，设置环境变量 `CHROME_PATH`。

## Godot 移植版

`godot/` 是同一玩法的 Godot 4.7 参考实现，场景、贴图与音效全部运行时生成，无外部资源依赖。用 Godot 4.7 打开 `godot/project.godot` 即可运行。

Windows 用户也可以直接双击 `启动游戏.bat` 一键启动 Godot 版本：脚本会自动定位项目与引擎，不依赖 Node.js、npm 或网页服务器。英文文件名版本为 `start-godot.bat`。

## 项目结构

- `src/`：Three.js 版本源码（渲染、玩法、AI、HUD、程序化素材）
- `scripts/`：开发辅助脚本（截图、视觉审查、冒烟/性能测试）
- `docs/`：架构契约与验收文档
- `godot/`：Godot 4 移植版
- `public/screenshots/`：本地生成的截图（不入库）

## 性能说明

开发环境中的无头截图使用软件光栅化（SwiftShader），帧时间不能代表真实 GPU 表现。请在实体 GPU 上以 `?quality=ultra` 运行并检查帧率；当前超画质包含 SSAO、Bloom、两套阴影贴图与大量实例化场景物件。

## 许可

本项目以 MIT 协议开源，详见 [LICENSE](LICENSE)。
