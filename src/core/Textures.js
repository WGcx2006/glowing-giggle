import * as THREE from 'three';
import { seededRandom } from './Noise.js';

const STYLES = {
  concrete: {
    base: '#707476',
    rough: 0.9,
    metal: 0.04,
    normal: 1.15,
    ao: 1.25,
    patches: ['#7c8082', '#65696b', '#85898b', '#5d6163'],
    stains: ['#4a4c4e', '#3e4042', '#57595b'],
  },
  sand: {
    base: '#b6a276',
    rough: 0.98,
    metal: 0,
    normal: 0.55,
    ao: 0.7,
    patches: ['#bda87d', '#a89167', '#c2ad82', '#9c8a62'],
    stains: ['#8f7b54', '#a48e62'],
  },
  metal: {
    base: '#70757a',
    rough: 0.42,
    metal: 0.9,
    normal: 1,
    ao: 1,
    patches: ['#7c8186', '#62676c', '#8b9094'],
    stains: ['#4f4540', '#5a514a'],
  },
  wood: {
    base: '#77553a',
    rough: 0.78,
    metal: 0.02,
    normal: 0.9,
    ao: 1,
    patches: ['#835f40', '#6d4d34', '#8d6a48'],
    stains: ['#4a3424', '#5c4230'],
  },
  camo: {
    base: '#4f5545',
    rough: 0.85,
    metal: 0.02,
    normal: 0.55,
    ao: 0.9,
    patches: ['#3f4c34', '#6b6440', '#8a7a4b', '#33372b'],
    stains: ['#2d3026', '#564b33'],
  },
  asphalt: {
    base: '#3d3e40',
    rough: 0.96,
    metal: 0.02,
    normal: 0.9,
    ao: 1.15,
    patches: ['#484a4c', '#333436', '#434548', '#2c2d2f'],
    stains: ['#262729', '#2f3032'],
  },
  ground: {
    base: '#5a5f52',
    rough: 0.92,
    metal: 0.02,
    normal: 0.8,
    ao: 1,
    patches: ['#60664f', '#4d5244', '#6c7059', '#6a5c46', '#53604a'],
    stains: ['#3f4438', '#4e4a3b'],
  },
};

function makeCanvas(size) {
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  return canvas;
}

function canvasTexture(canvas, repeat = 1, srgb = true) {
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = THREE.RepeatWrapping;
  texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(repeat, repeat);
  texture.anisotropy = 8;
  texture.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
  return texture;
}

function drawCircle(ctx, x, y, r, color, alpha) {
  ctx.fillStyle = color;
  ctx.globalAlpha = alpha;
  ctx.beginPath();
  ctx.arc(x, y, Math.max(1, r), 0, Math.PI * 2);
  ctx.fill();
  ctx.globalAlpha = 1;
}

function shadePair(cctx, hctx, size, rand, colors, hColors, count, minA, maxA, hMinA, hMaxA, minR = 0.04, maxR = 0.16) {
  for (let i = 0; i < count; i += 1) {
    const x = rand() * size;
    const y = rand() * size;
    const r = (minR + rand() * (maxR - minR)) * size;
    const c = colors[Math.floor(rand() * colors.length)];
    const hc = hColors[Math.floor(rand() * hColors.length)];
    drawCircle(cctx, x, y, r, c, minA + rand() * (maxA - minA));
    drawCircle(hctx, x, y, r, hc, hMinA + rand() * (hMaxA - hMinA));
  }
}

function crackPair(cctx, hctx, size, rand, cColor, hColor, count, minW = 0.8, maxW = 2.2) {
  for (let i = 0; i < count; i += 1) {
    let x = rand() * size;
    let y = rand() * size;
    const segments = 2 + Math.floor(rand() * 4);
    let angle = rand() * Math.PI * 2;
    const points = [[x, y]];
    for (let s = 0; s < segments; s += 1) {
      angle += (rand() - 0.5) * 1.4;
      const len = (0.04 + rand() * 0.1) * size;
      x += Math.cos(angle) * len;
      y += Math.sin(angle) * len;
      points.push([x, y]);
    }
    const width = minW + rand() * (maxW - minW);
    cctx.strokeStyle = cColor;
    cctx.lineWidth = width;
    cctx.lineCap = 'round';
    cctx.globalAlpha = 0.12 + rand() * 0.2;
    hctx.strokeStyle = hColor;
    hctx.lineWidth = width + 0.8;
    hctx.lineCap = 'round';
    hctx.globalAlpha = 0.22 + rand() * 0.28;
    for (const target of [cctx, hctx]) {
      target.beginPath();
      target.moveTo(points[0][0], points[0][1]);
      for (let p = 1; p < points.length; p += 1) {
        const prev = points[p - 1];
        const cur = points[p];
        const mx = (prev[0] + cur[0]) * 0.5;
        const my = (prev[1] + cur[1]) * 0.5;
        target.quadraticCurveTo(prev[0], prev[1], mx, my);
      }
      target.stroke();
    }
    cctx.globalAlpha = 1;
    hctx.globalAlpha = 1;
  }
}

function specklePair(cctx, hctx, size, rand, count, minA = 0.02, maxA = 0.07) {
  for (let i = 0; i < count; i += 1) {
    const x = rand() * size;
    const y = rand() * size;
    const w = 1 + rand() * 2.2;
    const h = 1 + rand() * 2.2;
    const light = rand() > 0.5;
    cctx.fillStyle = light ? '#ffffff' : '#000000';
    cctx.globalAlpha = minA + rand() * (maxA - minA);
    cctx.fillRect(x, y, w, h);
    hctx.fillStyle = light ? '#ffffff' : '#000000';
    hctx.globalAlpha = (minA + rand() * (maxA - minA)) * 0.75;
    hctx.fillRect(x, y, w, h);
  }
  cctx.globalAlpha = 1;
  hctx.globalAlpha = 1;
}

function linePair(cctx, hctx, size, rand, color, hColor, count, alpha, hAlpha, amp, freq, width) {
  for (let i = 0; i < count; i += 1) {
    const y0 = rand() * size;
    const phase = rand() * Math.PI * 2;
    const f = freq * (0.7 + rand() * 0.6);
    for (const target of [cctx, hctx]) {
      target.strokeStyle = target === cctx ? color : hColor;
      target.lineWidth = width * (0.6 + rand() * 0.8);
      target.globalAlpha = target === cctx ? alpha : hAlpha;
      target.beginPath();
      target.moveTo(0, y0);
      for (let x = 0; x <= size; x += size / 42) {
        target.lineTo(x, y0 + Math.sin((x / size) * Math.PI * 2 * f + phase) * amp * size);
      }
      target.stroke();
      target.globalAlpha = 1;
    }
  }
}

function blobPair(cctx, hctx, size, rand, color, hColor, alpha, hAlpha, r) {
  const x = rand() * size;
  const y = rand() * size;
  const points = [];
  const sides = 6 + Math.floor(rand() * 5);
  for (let i = 0; i < sides; i += 1) {
    const a = (i / sides) * Math.PI * 2 + rand() * 0.7;
    const rad = r * (0.55 + rand() * 0.55);
    points.push([x + Math.cos(a) * rad, y + Math.sin(a) * rad]);
  }
  for (const target of [cctx, hctx]) {
    target.fillStyle = target === cctx ? color : hColor;
    target.globalAlpha = target === cctx ? alpha : hAlpha;
    target.beginPath();
    target.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i += 1) target.lineTo(points[i][0], points[i][1]);
    target.closePath();
    target.fill();
    target.globalAlpha = 1;
  }
}

function drawSurfacePair(cctx, hctx, size, rand, type, style) {
  const patchColors = style.patches || [style.base];
  const hPatches = ['#d6d6d6', '#c6c6c6', '#bcbcbc', '#d0d0d0'];
  const stainColors = style.stains || ['#333333'];
  const hStains = ['#787878', '#6a6a6a', '#828282'];
  const count = Math.max(6, Math.floor(size / 34));

  shadePair(cctx, hctx, size, rand, patchColors, hPatches, count, 0.05, 0.12, 0.035, 0.08);
  shadePair(cctx, hctx, size, rand, patchColors, hPatches, Math.max(3, Math.floor(size / 110)), 0.06, 0.12, 0.04, 0.09, 0.22, 0.48);

  if (type === 'concrete' || type === 'asphalt' || type === 'ground') {
    crackPair(cctx, hctx, size, rand, '#232527', '#171717', Math.max(5, Math.floor(size / 44)));
    shadePair(cctx, hctx, size, rand, stainColors, hStains, Math.max(4, Math.floor(size / 48)), 0.07, 0.18, 0.05, 0.12);
  }

  if (type === 'concrete') {
    const seamCount = Math.max(2, Math.floor(size / 180));
    for (let i = 0; i < seamCount; i += 1) {
      const y = Math.floor(rand() * size);
      const w = 1 + rand() * 2;
      cctx.strokeStyle = '#45484a';
      cctx.globalAlpha = 0.18 + rand() * 0.14;
      cctx.lineWidth = w;
      hctx.strokeStyle = '#606060';
      hctx.globalAlpha = 0.16 + rand() * 0.14;
      hctx.lineWidth = w;
      for (const target of [cctx, hctx]) {
        target.beginPath();
        target.moveTo(0, y);
        target.lineTo(size, y + (rand() - 0.5) * size * 0.015);
        target.stroke();
        target.globalAlpha = 1;
      }
    }
    const spall = Math.floor(size / 70);
    for (let i = 0; i < spall; i += 1) {
      const x = rand() * size;
      const y = rand() * size;
      const r = (0.03 + rand() * 0.05) * size;
      drawCircle(cctx, x, y, r, '#8a8d8e', 0.12 + rand() * 0.16);
      drawCircle(cctx, x, y, r * 0.72, '#626568', 0.16 + rand() * 0.18);
      drawCircle(hctx, x, y, r, '#d8d8d8', 0.12);
      drawCircle(hctx, x, y, r * 0.72, '#9a9a9a', 0.18);
    }
  }

  if (type === 'sand') {
    linePair(cctx, hctx, size, rand, '#9c875b', '#a8a8a8', Math.floor(size / 46), 0.12, 0.08, 0.035, 9, 1.4);
    shadePair(cctx, hctx, size, rand, ['#cdbb90', '#a39168'], ['#e2e2e2', '#bdbdbd'], Math.floor(size / 55), 0.08, 0.14, 0.05, 0.09, 0.12, 0.3);
  }

  if (type === 'metal') {
    const cells = Math.max(2, Math.floor(size / 96));
    for (let i = 1; i < cells; i += 1) {
      const x = i * (size / cells);
      const y = i * (size / cells);
      for (const target of [cctx, hctx]) {
        target.strokeStyle = target === cctx ? '#3e4246' : '#444444';
        target.lineWidth = 1.2;
        target.globalAlpha = 0.28;
        target.beginPath();
        target.moveTo(x, 0);
        target.lineTo(x, size);
        target.moveTo(0, y);
        target.lineTo(size, y);
        target.stroke();
        target.globalAlpha = 1;
      }
    }
    const scratchCount = Math.floor(size / 9);
    for (let i = 0; i < scratchCount; i += 1) {
      const x = rand() * size;
      const y = rand() * size;
      const len = size * (0.02 + rand() * 0.06);
      const a = rand() * Math.PI;
      const ex = x + Math.cos(a) * len;
      const ey = y + Math.sin(a) * len;
      for (const target of [cctx, hctx]) {
        target.strokeStyle = target === cctx ? '#aeb4b8' : '#ffffff';
        target.globalAlpha = 0.1 + rand() * 0.12;
        target.lineWidth = 0.7;
        target.beginPath();
        target.moveTo(x, y);
        target.lineTo(ex, ey);
        target.stroke();
        target.globalAlpha = 1;
      }
    }
    shadePair(cctx, hctx, size, rand, ['#6a3f2f', '#593a2c'], ['#707070'], Math.floor(size / 40), 0.08, 0.2, 0.06, 0.12, 0.03, 0.12);
    const rivetCount = cells * cells;
    for (let i = 0; i < rivetCount; i += 1) {
      const x = (i % cells + 0.5) * (size / cells);
      const y = (Math.floor(i / cells) + 0.5) * (size / cells);
      drawCircle(cctx, x + 1, y + 1, size / cells * 0.055, '#2c2f31', 0.7);
      drawCircle(cctx, x, y, size / cells * 0.055, '#9aa0a4', 0.8);
      drawCircle(hctx, x, y, size / cells * 0.055, '#ffffff', 0.7);
      drawCircle(hctx, x, y + 2, size / cells * 0.045, '#3a3a3a', 0.7);
    }
  }

  if (type === 'wood') {
    linePair(cctx, hctx, size, rand, '#4a3424', '#4a4a4a', Math.floor(size / 14), 0.1, 0.09, 0.018, 14, 2);
    linePair(cctx, hctx, size, rand, '#8f6a48', '#d0d0d0', Math.floor(size / 26), 0.08, 0.07, 0.012, 11, 1.2);
    const knots = Math.floor(size / 80);
    for (let i = 0; i < knots; i += 1) {
      const x = rand() * size;
      const y = rand() * size;
      for (let r = 0.04; r < 0.1; r += 0.015) {
        cctx.strokeStyle = '#3c2a1c';
        cctx.globalAlpha = 0.35;
        cctx.lineWidth = 1.2;
        cctx.beginPath();
        cctx.ellipse(x, y, size * r, size * r * 0.45, rand() * 0.5, 0, Math.PI * 2);
        cctx.stroke();
        hctx.strokeStyle = '#202020';
        hctx.globalAlpha = 0.25;
        hctx.lineWidth = 1.5;
        hctx.beginPath();
        hctx.ellipse(x, y, size * r, size * r * 0.45, rand() * 0.5, 0, Math.PI * 2);
        hctx.stroke();
        cctx.globalAlpha = 1;
        hctx.globalAlpha = 1;
      }
    }
  }

  if (type === 'camo') {
    const blobs = Math.floor(size / 30);
    for (let i = 0; i < blobs; i += 1) {
      const c = style.patches[Math.floor(rand() * style.patches.length)];
      blobPair(cctx, hctx, size, rand, c, '#8c8c8c', 0.35 + rand() * 0.25, 0.18 + rand() * 0.2, size * (0.05 + rand() * 0.1));
    }
    shadePair(cctx, hctx, size, rand, ['#26291f', '#3f452f'], ['#6e6e6e'], Math.floor(size / 55), 0.08, 0.16, 0.06, 0.1, 0.04, 0.14);
  }

  if (type === 'asphalt') {
    linePair(cctx, hctx, size, rand, '#141516', '#242424', Math.floor(size / 120), 0.16, 0.12, 0.02, 7, 4);
    for (let i = 0; i < Math.floor(size / 80); i += 1) {
      const y = rand() * size;
      const len = size * (0.12 + rand() * 0.2);
      for (const target of [cctx, hctx]) {
        target.strokeStyle = target === cctx ? '#171819' : '#333333';
        target.lineWidth = 4 + rand() * 5;
        target.globalAlpha = 0.12 + rand() * 0.12;
        target.beginPath();
        target.moveTo(rand() * size * 0.2, y);
        target.lineTo(rand() * size * 0.2 + len, y + (rand() - 0.5) * size * 0.01);
        target.stroke();
        target.globalAlpha = 1;
      }
    }
  }

  if (type === 'ground') {
    const grassCount = Math.floor(size / 52);
    for (let i = 0; i < grassCount; i += 1) {
      const x = rand() * size;
      const y = rand() * size;
      const r = (0.015 + rand() * 0.03) * size;
      drawCircle(cctx, x, y, r, '#6d7a4a', 0.25 + rand() * 0.25);
      drawCircle(cctx, x + r * 0.4, y + r * 0.3, r * 0.6, '#58663e', 0.25);
      drawCircle(hctx, x, y, r, '#b8b8b8', 0.12);
      drawCircle(hctx, x + r * 0.4, y + r * 0.3, r * 0.6, '#9c9c9c', 0.1);
    }
    const stoneCount = Math.floor(size / 24);
    for (let i = 0; i < stoneCount; i += 1) {
      const x = rand() * size;
      const y = rand() * size;
      const r = (0.008 + rand() * 0.02) * size;
      drawCircle(cctx, x, y, r, '#7d7d6e', 0.22 + rand() * 0.24);
      drawCircle(hctx, x, y, r, '#d8d8d8', 0.2);
    }
  }

  specklePair(cctx, hctx, size, rand, Math.floor(size * size / 150), 0.02, 0.07);
}

function heightToNormal(heightCanvas, strength) {
  const size = heightCanvas.width;
  const src = heightCanvas.getContext('2d').getImageData(0, 0, size, size).data;
  const out = makeCanvas(size);
  const octx = out.getContext('2d');
  const data = octx.createImageData(size, size);
  const idx = (x, y) => (((y + size) % size) * size + ((x + size) % size)) * 4;
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const i = (y * size + x) * 4;
      const l = src[idx(x - 1, y)];
      const r = src[idx(x + 1, y)];
      const u = src[idx(x, y - 1)];
      const d = src[idx(x, y + 1)];
      const dx = (r - l) / 255 * strength;
      const dy = (u - d) / 255 * strength;
      const len = Math.sqrt(dx * dx + dy * dy + 1);
      data.data[i] = (dx / len * 0.5 + 0.5) * 255;
      data.data[i + 1] = (dy / len * 0.5 + 0.5) * 255;
      data.data[i + 2] = (1 / len * 0.5 + 0.5) * 255;
      data.data[i + 3] = 255;
    }
  }
  octx.putImageData(data, 0, 0);
  return out;
}

function heightToAO(heightCanvas, amount) {
  const size = heightCanvas.width;
  const src = heightCanvas.getContext('2d').getImageData(0, 0, size, size).data;
  const out = makeCanvas(size);
  const octx = out.getContext('2d');
  const data = octx.createImageData(size, size);
  for (let i = 0; i < src.length; i += 4) {
    const h = (src[i] + src[i + 1] + src[i + 2]) / 3;
    const ao = Math.max(0, Math.min(255, 255 - (210 - h) * amount));
    data.data[i] = ao;
    data.data[i + 1] = ao;
    data.data[i + 2] = ao;
    data.data[i + 3] = 255;
  }
  octx.putImageData(data, 0, 0);
  return out;
}

function makeRoughness(size, rand, rough, style, type) {
  const canvas = makeCanvas(size);
  const ctx = canvas.getContext('2d');
  const base = Math.round(rough * 255);
  ctx.fillStyle = `rgb(${base},${base},${base})`;
  ctx.fillRect(0, 0, size, size);
  const count = Math.floor(size * size / 160);
  for (let i = 0; i < count; i += 1) {
    const shade = Math.max(0, Math.min(255, base + Math.round((rand() - 0.5) * 90)));
    ctx.fillStyle = `rgb(${shade},${shade},${shade})`;
    ctx.globalAlpha = 0.05 + rand() * 0.1;
    ctx.fillRect(rand() * size, rand() * size, 1 + rand() * 3, 1 + rand() * 3);
  }
  if (type === 'metal') {
    for (let i = 0; i < Math.floor(size / 36); i += 1) {
      const x = rand() * size;
      const y = rand() * size;
      const r = size * (0.04 + rand() * 0.08);
      ctx.fillStyle = '#2b2b2b';
      ctx.globalAlpha = 0.12 + rand() * 0.15;
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  if (type === 'sand' || type === 'asphalt' || type === 'ground') {
    const lines = Math.floor(size / 60);
    for (let i = 0; i < lines; i += 1) {
      ctx.strokeStyle = '#ffffff';
      ctx.globalAlpha = 0.04 + rand() * 0.06;
      ctx.lineWidth = 1 + rand() * 2;
      ctx.beginPath();
      ctx.moveTo(0, rand() * size);
      ctx.lineTo(size, rand() * size);
      ctx.stroke();
    }
  }
  ctx.globalAlpha = 1;
  return canvas;
}

function makeMetalness(size, rand, metal, style, type) {
  const canvas = makeCanvas(size);
  const ctx = canvas.getContext('2d');
  const base = Math.round(metal * 255);
  ctx.fillStyle = `rgb(${base},${base},${base})`;
  ctx.fillRect(0, 0, size, size);
  if (type === 'metal') {
    const rust = Math.floor(size / 34);
    for (let i = 0; i < rust; i += 1) {
      const x = rand() * size;
      const y = rand() * size;
      const r = size * (0.03 + rand() * 0.07);
      ctx.fillStyle = '#202020';
      ctx.globalAlpha = 0.18 + rand() * 0.2;
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fill();
    }
    for (let i = 0; i < Math.floor(size / 8); i += 1) {
      ctx.fillStyle = '#ffffff';
      ctx.globalAlpha = 0.06 + rand() * 0.1;
      ctx.fillRect(rand() * size, rand() * size, 2 + rand() * 8, 0.8);
    }
  } else {
    const count = Math.floor(size * size / 420);
    for (let i = 0; i < count; i += 1) {
      const v = Math.max(0, Math.min(255, base + Math.round((rand() - 0.5) * 36)));
      ctx.fillStyle = `rgb(${v},${v},${v})`;
      ctx.globalAlpha = 0.06;
      ctx.fillRect(rand() * size, rand() * size, 1 + rand() * 2, 1 + rand() * 2);
    }
  }
  ctx.globalAlpha = 1;
  return canvas;
}

function buildSurface(type, opts = {}) {
  const size = Math.max(64, opts.size || 1024);
  const repeat = Math.max(1, opts.repeat || 4);
  const seed = opts.seed ?? 1337;
  const rand = seededRandom(seed);
  const style = STYLES[type] || STYLES.ground;
  const baseColor = opts.baseColor || style.base;
  const roughness = opts.roughness ?? style.rough;
  const metalness = opts.metalness ?? style.metal;

  const colorCanvas = makeCanvas(size);
  const cctx = colorCanvas.getContext('2d');
  cctx.fillStyle = baseColor;
  cctx.fillRect(0, 0, size, size);

  const heightCanvas = makeCanvas(size);
  const hctx = heightCanvas.getContext('2d');
  hctx.fillStyle = '#d2d2d2';
  hctx.fillRect(0, 0, size, size);

  drawSurfacePair(cctx, hctx, size, rand, type, style);

  const emissiveCanvas = makeCanvas(size);
  const ectx = emissiveCanvas.getContext('2d');
  ectx.fillStyle = '#000000';
  ectx.fillRect(0, 0, size, size);

  return {
    map: canvasTexture(colorCanvas, repeat, true),
    normalMap: canvasTexture(heightToNormal(heightCanvas, style.normal || 1), repeat, false),
    roughnessMap: canvasTexture(makeRoughness(size, rand, roughness, style, type), repeat, false),
    metalnessMap: canvasTexture(makeMetalness(size, rand, metalness, style, type), repeat, false),
    aoMap: canvasTexture(heightToAO(heightCanvas, style.ao ?? 1), repeat, false),
    emissiveMap: canvasTexture(emissiveCanvas, repeat, false),
    repeat,
    size,
  };
}

export function createTextureSet(type, opts = {}) {
  const safeType = STYLES[type] ? type : 'ground';
  return buildSurface(safeType, opts);
}

export function createPBRTextures(opts = {}) {
  return buildSurface('ground', opts);
}
