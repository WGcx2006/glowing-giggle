import { launchChromium } from './browser.mjs';

const base = process.env.BF_URL || 'http://127.0.0.1:5199';
const browser = await launchChromium({
  headless: true,
  args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
await page.goto(`${base}/?autostart=1&hidehud=1&quality=ultra&cam=hero`, { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForFunction(() => window.__BF2035?.running === true, { timeout: 30000 });
await page.waitForTimeout(3000);

const result = await page.evaluate(async () => {
  const g = window.__BF2035;
  const samples = [];
  let last = performance.now();
  await new Promise((resolve) => {
    function frame(now) {
      const dt = now - last;
      last = now;
      samples.push(dt);
      if (samples.length < 120) requestAnimationFrame(frame);
      else resolve();
    }
    requestAnimationFrame(frame);
  });
  samples.sort((a, b) => a - b);
  const avg = samples.reduce((a, b) => a + b, 0) / samples.length;
  const p95 = samples[Math.floor(samples.length * 0.95)];
  const info = g.renderer.info.render;
  return {
    avgFrameMs: Number(avg.toFixed(2)),
    avgFps: Number((1000 / avg).toFixed(1)),
    p95FrameMs: Number(p95.toFixed(2)),
    calls: info.calls,
    triangles: info.triangles,
    points: info.points,
    lines: info.lines,
    sceneChildren: g.scene.children.length,
  };
});

console.log(JSON.stringify(result, null, 2));
await browser.close();
