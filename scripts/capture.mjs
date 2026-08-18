import { mkdir, writeFile } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

import { launchChromium } from './browser.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outDir = path.join(root, 'public', 'screenshots');
const base = process.env.BF_URL || 'http://127.0.0.1:5199';

const CAMS = {
  hero: 'hero',
  combat: 'combat',
  aerial: 'aerial',
  sunset: 'sunset',
};
const QUALITIES = ['ultra', 'high', 'medium'];

async function main() {
  await mkdir(outDir, { recursive: true });
  const browser = await launchChromium({
    headless: true,
    args: ['--disable-gpu-sandbox', '--enable-unsafe-swiftshader', '--use-angle=swiftshader'],
  });

  const shots = [];
  const pairs = [];
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });

  for (const cam of Object.values(CAMS)) {
    for (const quality of QUALITIES) {
      const url = `${base}/?autostart=1&hidehud=1&quality=${quality}&cam=${cam}`;
      await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
      await page.waitForFunction(() => window.__BF2035?.running === true, { timeout: 30000 });
      await page.waitForTimeout(3200);
      await page.evaluate(({ cam }) => {
        const g = window.__BF2035;
        g.enemies.spawnWave(5);
        const explosions = {
          hero: [[18, 0, 30], [-10, 0, 12], [0, 0, 26]],
          combat: [[10, 0, 14], [0, 0, 22], [-7, 0, 8]],
          aerial: [[0, 0, 0], [22, 0, 12], [-18, 0, 28]],
          sunset: [[-12, 0, 20], [-4, 0, 26]],
        }[cam] || [];
        for (const [x, , z] of explosions) {
          g.explosions.explode({ x, y: 0.6, z }, 5.2 + Math.random() * 2.5, 12, 'rocket');
          g.particles.smoke({ x: x + 1.5, y: 1, z: z + 1 }, '#4d4f52');
        }
      }, { cam });
      await page.waitForTimeout(750);
      const file = `${cam}-${quality}.png`;
      await page.screenshot({ path: path.join(outDir, file) });
      shots.push({ cam, quality, file });
      console.log(`captured ${file}`);
    }
    pairs.push({
      id: cam,
      title: cam === 'hero' ? '主视觉' : cam === 'combat' ? '战斗视角' : cam === 'aerial' ? '空中俯瞰' : '黄昏战场',
      a: { file: `${cam}-ultra.png`, label: 'Ultra' },
      b: { file: `${cam}-medium.png`, label: 'Medium' },
    });
  }

  await browser.close();

  await writeFile(
    path.join(outDir, 'manifest.json'),
    JSON.stringify({ generatedAt: new Date().toISOString(), shots, pairs }, null, 2),
    'utf8'
  );
  console.log(`manifest written with ${pairs.length} blind-test pairs`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
