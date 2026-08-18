import { launchChromium } from './browser.mjs';

const base = process.env.BF_URL || 'http://127.0.0.1:5199';
const browser = await launchChromium({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const errors = [];
page.on('pageerror', (err) => errors.push(err.message));
await page.goto(`${base}/blindtest.html`, { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForSelector('.option');
const result = await page.evaluate(() => ({
  options: document.querySelectorAll('.option').length,
  firstLabel: document.querySelector('.option .label')?.textContent,
  tally: document.getElementById('tally')?.textContent,
}));
console.log(JSON.stringify({ result, errors }, null, 2));
await browser.close();
