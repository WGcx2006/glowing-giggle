import { createRequire } from 'module';

const require = createRequire(import.meta.url);

export function launchChromium(options = {}) {
  let playwright;
  try {
    playwright = require('playwright');
  } catch {
    console.error('Playwright is not installed. Run: pnpm add -D playwright');
    process.exit(1);
  }

  if (process.env.CHROME_PATH) {
    options.executablePath = process.env.CHROME_PATH;
  }
  options.args = ['--no-proxy-server', ...(options.args || [])];
  return playwright.chromium.launch(options);
}
