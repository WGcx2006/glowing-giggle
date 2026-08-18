function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hash2i(x, y, seed) {
  let h = (seed ^ Math.imul(x, 374761393) ^ Math.imul(y, 668265263)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return h >>> 0;
}

const GRAD2 = [
  [1, 1], [-1, 1], [1, -1], [-1, -1],
  [1, 0], [-1, 0], [0, 1], [0, -1],
];

const PERM_CACHE = new Map();

function getPermutation(seed) {
  let perm = PERM_CACHE.get(seed);
  if (perm) return perm;
  const rand = mulberry32((seed ^ 0x9e3779b9) >>> 0);
  const table = new Uint8Array(256);
  for (let i = 0; i < 256; i += 1) table[i] = i;
  for (let i = 255; i > 0; i -= 1) {
    const j = Math.floor(rand() * (i + 1));
    const tmp = table[i];
    table[i] = table[j];
    table[j] = tmp;
  }
  perm = new Uint8Array(512);
  for (let i = 0; i < 512; i += 1) perm[i] = table[i & 255];
  PERM_CACHE.set(seed, perm);
  return perm;
}

export function smoothNoise2D(x, y, seed = 1337) {
  const xi = Math.floor(x);
  const yi = Math.floor(y);
  const xf = x - xi;
  const yf = y - yi;
  const u = xf * xf * (3 - 2 * xf);
  const v = yf * yf * (3 - 2 * yf);
  const a = hash2i(xi, yi, seed) / 4294967296;
  const b = hash2i(xi + 1, yi, seed) / 4294967296;
  const c = hash2i(xi, yi + 1, seed) / 4294967296;
  const d = hash2i(xi + 1, yi + 1, seed) / 4294967296;
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

export function simplexNoise2D(xin, yin, seed = 1337) {
  const seedKey = seed >>> 0;
  const perm = getPermutation(seedKey);
  const F2 = 0.5 * (Math.sqrt(3) - 1);
  const G2 = (3 - Math.sqrt(3)) / 6;
  const s = (xin + yin) * F2;
  const i = Math.floor(xin + s);
  const j = Math.floor(yin + s);
  const t = (i + j) * G2;
  const x0 = xin - (i - t);
  const y0 = yin - (j - t);

  let i1;
  let j1;
  if (x0 > y0) {
    i1 = 1;
    j1 = 0;
  } else {
    i1 = 0;
    j1 = 1;
  }

  const x1 = x0 - i1 + G2;
  const y1 = y0 - j1 + G2;
  const x2 = x0 - 1 + 2 * G2;
  const y2 = y0 - 1 + 2 * G2;
  const ii = i & 255;
  const jj = j & 255;

  const g0 = GRAD2[perm[ii + perm[jj]] & 7];
  const g1 = GRAD2[perm[ii + i1 + perm[jj + j1]] & 7];
  const g2 = GRAD2[perm[ii + 1 + perm[jj + 1]] & 7];

  let n0 = 0;
  let n1 = 0;
  let n2 = 0;
  let t0 = 0.5 - x0 * x0 - y0 * y0;
  if (t0 >= 0) {
    t0 *= t0;
    n0 = t0 * t0 * (g0[0] * x0 + g0[1] * y0);
  }
  let t1 = 0.5 - x1 * x1 - y1 * y1;
  if (t1 >= 0) {
    t1 *= t1;
    n1 = t1 * t1 * (g1[0] * x1 + g1[1] * y1);
  }
  let t2 = 0.5 - x2 * x2 - y2 * y2;
  if (t2 >= 0) {
    t2 *= t2;
    n2 = t2 * t2 * (g2[0] * x2 + g2[1] * y2);
  }
  return 70 * (n0 + n1 + n2);
}

export function fbm2D(x, y, octaves = 4, seed = 1337) {
  let value = 0;
  let amp = 0.5;
  let freq = 1;
  let sum = 0;
  for (let i = 0; i < octaves; i += 1) {
    value += simplexNoise2D(x * freq, y * freq, seed + i * 101) * amp;
    sum += amp;
    amp *= 0.5;
    freq *= 2;
  }
  return value / sum * 0.5 + 0.5;
}

export function seededRandom(seed) {
  return mulberry32(seed);
}
