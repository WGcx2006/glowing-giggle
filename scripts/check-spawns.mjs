import { launchChromium } from './browser.mjs';

const base = process.env.BF_URL || 'http://127.0.0.1:5199';
const browser = await launchChromium({
  headless: true,
  args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
await page.goto(`${base}/?autostart=1&hidehud=1`, { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForFunction(() => window.__BF2035?.running === true, { timeout: 30000 });
await page.waitForTimeout(800);

const candidates = [
  [0, 0],
  [0, 8],
  [0, 12],
  [8, 8],
  [-8, 8],
  [12, 0],
  [-12, 0],
  [16, 16],
  [28, -6],
  [-32, -6],
  [6, 30],
  [6, -38],
];
const result = await page.evaluate((points) => {
  const g = window.__BF2035;
  return points.map(([x, z]) => {
    const p = new (g.player.getPosition().constructor)(x, g.terrain.heightAt(x, z) + 1.7, z);
    const near = g.physics.boxes.filter((b) => b.center.distanceTo(p) < 5);
    return {
      x,
      z,
      ground: Number(g.terrain.heightAt(x, z).toFixed(2)),
      boxes: near.map((b) => `${b.id}@${b.center.toArray().map((v) => v.toFixed(0)).join(',')}`),
    };
  });
}, candidates);
console.log(JSON.stringify(result, null, 2));
await browser.close();
