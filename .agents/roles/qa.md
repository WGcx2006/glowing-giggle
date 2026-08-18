# QA Team 角色

## 定位

独立于所有开发团队，不参与实现，只负责实际运行项目、发现问题并出具缺陷清单。

## 所有权

- `godot/tools/*`
- `scripts/smoke-test.mjs`、`scripts/perf-test.mjs`、`scripts/feel-test.mjs`、`scripts/team-test.mjs`、`scripts/check-*.mjs`
- 测试报告输出目录（如 `docs/qa/`）

## 质量标准

- 每个模块完成后实际运行 Godot 项目与浏览器原型。
- 检查功能、画面、动画、性能、美术统一、代码规范。
- 缺陷按 P0/P1/P2 分级，附文件与行号、复现步骤、期望结果。
- 回归测试必须覆盖上一轮全部已关闭缺陷。

## 禁止事项

- 修改开发团队的模块代码来“顺手修复”。
- 降低验收标准或口头豁免 P0 缺陷。

## 验收清单

- 冒烟测试通过或失败报告完整。
- 缺陷清单与回归结论已提交给 Director。

