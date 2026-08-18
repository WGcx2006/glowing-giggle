# 盲测流程

## 生成截图

```bash
pnpm add -D playwright
pnpm build
node scripts/visual-review.mjs
```

脚本会启动 Vite，用 Chrome headless 截取 4 个镜头 × 3 个画质档位的画面，输出到 `public/screenshots/`。

## 盲测页面

打开 `http://localhost:5199/blindtest.html`。

页面随机展示 A/B 两张截图，观察者不知道哪张属于哪个画质档位；选择后才会揭示标签，并统计 Ultra/Medium 的得票。最终结果能明确分出哪一款视觉效果更优。

## 结论记录

盲测结束后将结果写入 `public/screenshots/manifest.json` 或 `docs/BLINDTEST_RESULT.md`，作为迭代验收依据。
