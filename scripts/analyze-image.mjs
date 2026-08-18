import path from 'path';
import { readFileSync } from 'fs';

import { launchChromium } from './browser.mjs';

const file = process.argv[2];
if (!file) {
  console.error('usage: node scripts/analyze-image.mjs <image-path>');
  process.exit(1);
}
const abs = path.resolve(file);
const b64 = readFileSync(abs).toString('base64');
const dataUrl = `data:image/png;base64,${b64}`;

const browser = await launchChromium({ headless: true });
const page = await browser.newPage();
const metrics = await page.evaluate(async (src) => {
  const img = new Image();
  img.src = src;
  await img.decode();
  const w = img.naturalWidth;
  const h = img.naturalHeight;
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  ctx.drawImage(img, 0, 0);
  const data = ctx.getImageData(0, 0, w, h).data;

  let r = 0;
  let g = 0;
  let b = 0;
  let lumSum = 0;
  let lumSum2 = 0;
  let satSum = 0;
  let colorful = 0;
  let dark = 0;
  let bright = 0;
  let edges = 0;
  let bottomLum = 0;
  let bottomEdges = 0;
  let bottomN = 0;
  let bottomDark = 0;
  const n = w * h;
  const halfW = Math.floor(w / 2);
  const halfH = Math.floor(h / 2);
  const lum = new Float32Array(n);
  const rg = new Float32Array(n);
  const yb = new Float32Array(n);

  for (let y = 0; y < h; y += 2) {
    for (let x = 0; x < w; x += 2) {
      const i = (y * w + x) * 4;
      const rr = data[i];
      const gg = data[i + 1];
      const bb = data[i + 2];
      r += rr;
      g += gg;
      b += bb;
      const L = 0.2126 * rr + 0.7152 * gg + 0.0722 * bb;
      const j = (y / 2) * halfW + x / 2;
      lum[j] = L;
      const rgv = rr - gg;
      const ybv = 0.5 * (rr + gg) - bb;
      rg[j] = rgv;
      yb[j] = ybv;
      lumSum += L;
      lumSum2 += L * L;
      const max = Math.max(rr, gg, bb);
      const min = Math.min(rr, gg, bb);
      satSum += max === 0 ? 0 : (max - min) / max;
      colorful += Math.sqrt(rgv * rgv + ybv * ybv);
      if (L < 5) dark += 1;
      if (L > 250) bright += 1;
    }
  }

  for (let yy = 1; yy < halfH - 1; yy += 1) {
    for (let xx = 1; xx < halfW - 1; xx += 1) {
      const i = yy * halfW + xx;
      const gx =
        -lum[i - halfW - 1] - 2 * lum[i - 1] - lum[i + halfW - 1] +
        lum[i - halfW + 1] + 2 * lum[i + 1] + lum[i + halfW + 1];
      const gy =
        -lum[i - halfW - 1] - 2 * lum[i - halfW] - lum[i - halfW + 1] +
        lum[i + halfW - 1] + 2 * lum[i + halfW] + lum[i + halfW + 1];
      if (Math.sqrt(gx * gx + gy * gy) > 45) edges += 1;
    }
  }

  const bottomStart = Math.floor(halfH * 0.8);
  for (let yy = bottomStart; yy < halfH - 1; yy += 1) {
    for (let xx = 1; xx < halfW - 1; xx += 1) {
      const i = yy * halfW + xx;
      bottomLum += lum[i];
      bottomN += 1;
      if (lum[i] < 5) bottomDark += 1;
      const gx =
        -lum[i - halfW - 1] - 2 * lum[i - 1] - lum[i + halfW - 1] +
        lum[i - halfW + 1] + 2 * lum[i + 1] + lum[i + halfW + 1];
      const gy =
        -lum[i - halfW - 1] - 2 * lum[i - halfW] - lum[i - halfW + 1] +
        lum[i + halfW - 1] + 2 * lum[i + halfW] + lum[i + halfW + 1];
      if (Math.sqrt(gx * gx + gy * gy) > 45) bottomEdges += 1;
    }
  }

  const sample = n / 4;
  const avgR = r / sample;
  const avgG = g / sample;
  const avgB = b / sample;
  const avgLum = lumSum / sample;
  const stdLum = Math.sqrt(Math.max(0, lumSum2 / sample - avgLum * avgLum));
  const avgSat = satSum / sample;
  const colorfulScore = colorful / sample;

  return {
    width: w,
    height: h,
    avgRGB: [Math.round(avgR), Math.round(avgG), Math.round(avgB)],
    brightness: Number(avgLum.toFixed(2)),
    contrast: Number(stdLum.toFixed(2)),
    saturation: Number(avgSat.toFixed(3)),
    colorfulness: Number(colorfulScore.toFixed(2)),
    edgeDensity: Number((edges / (sample / 1)).toFixed(4)),
    bottomEdgeDensity: Number((bottomEdges / Math.max(1, bottomN)).toFixed(4)),
    bottomBrightness: Number((bottomLum / Math.max(1, bottomN)).toFixed(2)),
    bottomDarkRatio: Number((bottomDark / Math.max(1, bottomN)).toFixed(4)),
    darkRatio: Number((dark / sample).toFixed(4)),
    brightRatio: Number((bright / sample).toFixed(4)),
  };
}, dataUrl);

console.log(JSON.stringify({ file: abs, ...metrics }, null, 2));
await browser.close();
