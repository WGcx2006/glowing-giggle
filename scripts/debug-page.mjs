import { launchChromium } from './browser.mjs';

const base = process.env.BF_URL || 'http://127.0.0.1:5199';

const browser = await launchChromium({
  headless: true,
  args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
page.on('console', (msg) => console.log(`[console:${msg.type()}]`, msg.text()));
page.on('pageerror', (err) => console.log('[pageerror]', err.message));
page.on('weberror', (err) => console.log('[weberror]', err.message));
page.on('crash', () => console.log('[crash] page crashed'));
page.on('requestfailed', (req) => console.log('[requestfailed]', req.url(), req.failure()?.errorText));
await page.addInitScript(() => {
  window.addEventListener('error', (e) => console.error('[window-error]', e.message, e.filename, e.lineno));
  window.addEventListener('unhandledrejection', (e) => console.error('[unhandledrejection]', e.reason));
});

await page.goto(`${base}/?autostart=1&hidehud=1&quality=ultra&cam=hero`, { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(10000);

  const state = await page.evaluate(() => {
  const g = window.__BF2035;
  const canvas = document.querySelector('canvas');
  const rect = canvas?.getBoundingClientRect();
  const resources = performance.getEntriesByType('resource').map((r) => r.name);
  return {
    hasGame: !!g,
    running: g?.running,
    started: g?.started,
    camera: g?.camera?.position?.toArray?.(),
    sceneChildren: g?.scene?.children?.length,
    canvasRect: rect ? { x: rect.x, y: rect.y, w: rect.width, h: rect.height } : null,
    viewport: { w: window.innerWidth, h: window.innerHeight },
    hasPostFX: !!g?.postFX,
    mainScriptLoaded: performance.getEntriesByType('resource').some((r) => r.name.includes('main.js')),
    resources: resources.slice(0, 40),
    scripts: Array.from(document.scripts).map((s) => s.src || s.textContent.slice(0, 80)),
    viteOverlay: !!document.querySelector('vite-error-overlay'),
    errorOverlays: document.querySelectorAll('[class*=error],[class*=overlay]').length,
    rendererInfo: g?.renderer?.info?.render?.calls ?? null,
    bodyHtml: document.body.innerHTML.slice(0, 300),
  };
});
console.log(JSON.stringify(state, null, 2));
await page.screenshot({ path: 'debug-shot.png' });
await browser.close();
