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

  const result = await page.evaluate(async () => {
  const g = window.__BF2035;
  const start = g.player.getPosition().clone();
  const startYaw = g.player.yaw;
  g.input.keys.add('KeyW');
  g.input.keys.add('ShiftLeft');
  for (let i = 0; i < 10; i++) {
    g.player.update(0.05, g.input);
    g.weapons.update(0.05, g.input);
  }
  await new Promise((r) => setTimeout(r, 80));
  const sprintState = g.player.getState();
  const sprintMoved = g.player.getPosition().distanceTo(start) > 0.2;
  const endPos = g.player.getPosition().clone();
  const nearBoxes = g.physics.boxes
    .filter((b) => b.center.distanceTo(g.player.getPosition()) < 4)
    .slice(0, 8)
    .map((b) => ({ id: b.id, center: b.center.toArray(), half: b.half.toArray() }));
  const groundY = g.terrain.heightAt(endPos.x, endPos.z);
  const sprintFov = g.camera.fov;

  g.input.keys.delete('ShiftLeft');
  g.input.zoom = true;
  for (let i = 0; i < 12; i++) g.weapons.update(0.05, g.input);
  await new Promise((r) => setTimeout(r, 80));
  const adsState = g.weapons.getState();
  const adsFov = g.camera.fov;
  const adsDebug = {
    zoomFlag: g.input.zoom,
    adsAmount: g.weapons.adsAmount,
    alive: g.player.getState().alive,
  };
  g.input.zoom = false;

  // Sensitivity check: fixed mouse movement should produce a modest yaw change.
  const sensitivityScale = g.player.sensitivityScale;
  const yawBefore = g.player.yaw;
  g.input.mouseDX = 120;
  g.input.mouseDY = -60;
  g.player.update(0.016, g.input);
  const yawDelta = g.player.yaw - yawBefore;
  g.input.mouseDX = 0;
  g.input.mouseDY = 0;

  // Jump check: lower, shorter hop and stronger gravity.
  const jumpGroundY = g.terrain.heightAt(g.player.position.x, g.player.position.z);
  g.player.position.y = jumpGroundY + 1.7;
  g.player.velocity.set(0, 0, 0);
  g.player.grounded = true;
  g.input.keys.add('Space');
  g.player.update(0.016, g.input);
  const jumpVelocity = g.player.velocity.y;
  g.input.keys.delete('Space');
  let peakY = g.player.position.y;
  for (let i = 0; i < 60; i++) {
    g.player.update(0.016, g.input);
    peakY = Math.max(peakY, g.player.position.y);
  }

  const mouseSmoothing = g.player.mouseSmoothX !== undefined;
  return {
    sprinting: sprintState.sprinting,
    sprintMoved,
    startPos: start.toArray(),
    endPos: endPos.toArray(),
    startYaw: Number(startYaw.toFixed(2)),
    groundY: Number(groundY.toFixed(2)),
    velocity: sprintState.velocity.toArray(),
    nearBoxes,
    sprintFov: Number(sprintFov.toFixed(1)),
    ads: Number(adsState.ads.toFixed(2)),
    adsDebug,
    adsFov: Number(adsFov.toFixed(1)),
    mouseSmoothing,
    sensitivityScale,
    yawDelta: Number((yawDelta * 1000).toFixed(3)),
    jumpVelocity: Number(jumpVelocity.toFixed(2)),
    jumpRise: Number((peakY - (jumpGroundY + 1.7)).toFixed(2)),
    gravity: g.player.gravity,
    sliderExists: !!document.querySelector('#sensitivity-slider'),
    weaponName: g.weapons.getState().name,
  };
});

console.log(JSON.stringify({ result, pageErrors: errors }, null, 2));
await browser.close();
