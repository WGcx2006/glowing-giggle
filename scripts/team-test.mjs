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
await page.waitForTimeout(1500);

const result = await page.evaluate(async () => {
  const g = window.__BF2035;
  const out = {};

  const captureState = g.capture.getState();
  out.capture = {
    points: captureState.points.map((p) => `${p.id}:${p.owner}`).join(','),
    bluePoints: captureState.bluePoints,
    redPoints: captureState.redPoints,
  };
  out.teamCounts = {
    blue: g.enemies.getTeamAliveCount('blue'),
    red: g.enemies.getTeamAliveCount('red'),
    total: g.enemies.getAliveCount(),
  };
  out.blueAliveWithPlayer = out.teamCounts.blue + (g.player.getState().alive ? 1 : 0);

  // Elimination victory: kill every red unit through the damage event.
  for (const enemy of g.enemies.enemies.filter((e) => e.team === 'red' && e.alive)) {
    g.events.emit('damage:target', {
      target: enemy,
      amount: 9999,
      point: enemy.group.position,
      source: 'player',
    });
  }
  await new Promise((r) => setTimeout(r, 500));
  out.elimination = {
    over: g.over,
    running: g.running,
    redAlive: g.enemies.getTeamAliveCount('red'),
  };

  // Capture victory after restart: force all points to blue.
  if (g.restart) g.restart();
  await new Promise((r) => setTimeout(r, 400));
  for (const point of g.capture.points) {
    point.owner = 'blue';
    point.progress = 100;
  }
  g.events.emit('capture:state', g.capture.getState());
  await new Promise((r) => setTimeout(r, 500));
  out.captureVictory = {
    over: g.over,
    running: g.running,
    allBlue: g.capture.points.every((p) => p.owner === 'blue'),
  };

  // Actual capture progress: neutralize D, stand on it, and let blue capture it.
  if (g.restart) g.restart();
  await new Promise((r) => setTimeout(r, 300));
  const pointD = g.capture.points.find((p) => p.id === 'D');
  pointD.owner = 'neutral';
  pointD.progress = 0;
  const dPos = new (g.player.getPosition().constructor)(
    pointD.position.x,
    pointD.position.y,
    pointD.position.z
  );
  for (let i = 0; i < 400; i++) {
    g.capture.update(0.05, { blue: [dPos], red: [] });
  }
  out.captureProgress = {
    owner: pointD.owner,
    progress: Number(pointD.progress.toFixed(1)),
    bluePointsAfter: g.capture.getState().bluePoints,
  };

  out.gameOverText = document.querySelector('#gameover-screen h2')?.textContent ?? null;
  out.restartButton = !!document.querySelector('#restart-btn');
  out.teamPanel = !!document.querySelector('#team-panel');
  out.captureList = !!document.querySelector('#capture-points');
  out.teamPanelText = document.querySelector('#team-panel')?.textContent?.replace(/\s+/g, ' ').trim() ?? null;
  out.captureListText = document.querySelector('#capture-points')?.textContent?.replace(/\s+/g, ' ').trim() ?? null;
  out.gameOverScreenText = document.querySelector('#gameover-screen')?.textContent?.replace(/\s+/g, ' ').trim() ?? null;
  return out;
});

console.log(JSON.stringify({ result, pageErrors: errors }, null, 2));
await browser.close();
