import { launchChromium } from './browser.mjs';

const base = process.env.BF_URL || 'http://127.0.0.1:5199';
const browser = await launchChromium({
  headless: true,
  args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
page.on('pageerror', (err) => errors.push(err.message));

await page.goto(`${base}/?autostart=1&hidehud=1`, { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForFunction(() => window.__BF2035?.running === true, { timeout: 30000 });
await page.waitForTimeout(2000);

const result = await page.evaluate(async () => {
  const g = window.__BF2035;
  const out = { beforeHealth: g.player.getHealth() };
  g.enemies.spawnWave(4);
  await new Promise((r) => setTimeout(r, 400));
  out.aliveAfterSpawn = g.enemies.getAliveCount();
  g.player.damage(15);
  out.afterDamage = g.player.getHealth();
  g.weapons.switchWeapon(1);
  out.weaponState = g.weapons.getState();
  const cam = g.camera;
  const dir = new (cam.position.constructor)(0, 0, -1).applyQuaternion(cam.quaternion);
  g.projectiles.spawnRocket(cam.position.clone(), dir);
  await new Promise((r) => setTimeout(r, 2200));
  out.sceneChildren = g.scene.children.length;
  out.postFxActive = !!g.postFX;
  return out;
});

console.log(JSON.stringify({ result, pageErrors: errors }, null, 2));
await browser.close();
