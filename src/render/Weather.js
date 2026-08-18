import * as THREE from 'three';
import { seededRandom } from '../core/Noise.js';

const WEATHERS = {
  clear: {
    fog: '#b9b6a8',
    fogDensity: 0.0038,
    exposure: 1.12,
    tint: [1, 1, 1],
    saturation: 1.04,
    contrast: 1.02,
    vignette: 0.3,
    grain: 0.01,
    rain: 0,
    dust: 0,
  },
  rain: {
    fog: '#707b81',
    fogDensity: 0.011,
    exposure: 0.92,
    tint: [0.85, 0.95, 1.08],
    saturation: 0.82,
    contrast: 1.05,
    vignette: 0.36,
    grain: 0.018,
    rain: 1,
    dust: 0,
  },
  dust: {
    fog: '#c2a374',
    fogDensity: 0.007,
    exposure: 1.02,
    tint: [1.12, 1, 0.78],
    saturation: 0.72,
    contrast: 0.94,
    vignette: 0.32,
    grain: 0.014,
    rain: 0,
    dust: 1,
  },
};

function makeState(type) {
  const src = WEATHERS[type] || WEATHERS.clear;
  return {
    fog: new THREE.Color(src.fog),
    fogDensity: src.fogDensity,
    exposure: src.exposure,
    tint: src.tint.slice(),
    saturation: src.saturation,
    contrast: src.contrast,
    vignette: src.vignette,
    grain: src.grain,
    rain: src.rain,
    dust: src.dust,
  };
}

function makeStreakTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = 8;
  canvas.height = 32;
  const ctx = canvas.getContext('2d');
  const gradient = ctx.createLinearGradient(0, 0, 8, 32);
  gradient.addColorStop(0, 'rgba(255,255,255,0)');
  gradient.addColorStop(0.28, 'rgba(255,255,255,0.85)');
  gradient.addColorStop(0.78, 'rgba(255,255,255,0.5)');
  gradient.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, 8, 32);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.NoColorSpace;
  texture.minFilter = THREE.LinearFilter;
  texture.magFilter = THREE.LinearFilter;
  return texture;
}

function makeSoftTexture() {
  const size = 64;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  const gradient = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  gradient.addColorStop(0, 'rgba(255,255,255,0.8)');
  gradient.addColorStop(0.35, 'rgba(255,255,255,0.32)');
  gradient.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, size, size);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.NoColorSpace;
  texture.minFilter = THREE.LinearFilter;
  texture.magFilter = THREE.LinearFilter;
  return texture;
}

export class WeatherSystem {
  constructor(scene, camera, quality = {}) {
    this.scene = scene;
    this.camera = camera;
    this.quality = quality;
    this.type = 'clear';
    this.state = makeState('clear');
    this.target = makeState('clear');
    scene.userData = scene.userData || {};
    scene.userData.camera = camera;
    scene.userData.weatherType = 'clear';
    scene.userData.post = {
      exposure: this.state.exposure,
      tint: this.state.tint.slice(),
      saturation: this.state.saturation,
      contrast: this.state.contrast,
      vignette: this.state.vignette,
      grain: this.state.grain,
      weatherType: this.type,
    };
    this._buildParticles();
    this._applyFog();
  }

  _buildParticles() {
    const scale = this.quality.particleScale ?? 1;
    const rainCount = Math.max(0, Math.floor(2200 * scale));
    const rand = seededRandom(2035);
    const rainPositions = new Float32Array(rainCount * 3);
    this.rainVelocities = new Float32Array(rainCount);
    this.rainDriftX = new Float32Array(rainCount);
    this.rainDriftZ = new Float32Array(rainCount);
    for (let i = 0; i < rainCount; i += 1) {
      rainPositions[i * 3] = (rand() * 2 - 1) * 48;
      rainPositions[i * 3 + 1] = rand() * 42;
      rainPositions[i * 3 + 2] = (rand() * 2 - 1) * 48;
      this.rainVelocities[i] = 26 + rand() * 15;
      this.rainDriftX[i] = (rand() - 0.5) * 3.2;
      this.rainDriftZ[i] = (rand() - 0.5) * 2.4;
    }
    this.rainGeometry = new THREE.BufferGeometry();
    this.rainGeometry.setAttribute('position', new THREE.BufferAttribute(rainPositions, 3));
    this.rainMaterial = new THREE.PointsMaterial({
      map: makeStreakTexture(),
      color: 0xa8bdd4,
      size: 0.26,
      sizeAttenuation: true,
      transparent: true,
      opacity: 0,
      depthWrite: false,
      alphaTest: 0.02,
    });
    this.rain = new THREE.Points(this.rainGeometry, this.rainMaterial);
    this.rain.frustumCulled = false;
    this.rainGroup = new THREE.Group();
    this.rainGroup.add(this.rain);
    this.rainGroup.visible = false;
    this.scene.add(this.rainGroup);

    const dustCount = Math.max(0, Math.floor(650 * scale));
    const dustPositions = new Float32Array(dustCount * 3);
    this.dustDriftX = new Float32Array(dustCount);
    this.dustDriftZ = new Float32Array(dustCount);
    this.dustRise = new Float32Array(dustCount);
    for (let i = 0; i < dustCount; i += 1) {
      dustPositions[i * 3] = (rand() * 2 - 1) * 100;
      dustPositions[i * 3 + 1] = rand() * 26;
      dustPositions[i * 3 + 2] = (rand() * 2 - 1) * 100;
      this.dustDriftX[i] = (rand() - 0.5) * 1.4;
      this.dustDriftZ[i] = (rand() - 0.5) * 1.4;
      this.dustRise[i] = 0.2 + rand() * 0.5;
    }
    this.dustGeometry = new THREE.BufferGeometry();
    this.dustGeometry.setAttribute('position', new THREE.BufferAttribute(dustPositions, 3));
    this.dustMaterial = new THREE.PointsMaterial({
      map: makeSoftTexture(),
      color: 0xc9a979,
      size: 3.6,
      sizeAttenuation: true,
      transparent: true,
      opacity: 0,
      depthWrite: false,
      depthTest: true,
    });
    this.dust = new THREE.Points(this.dustGeometry, this.dustMaterial);
    this.dust.frustumCulled = false;
    this.dustGroup = new THREE.Group();
    this.dustGroup.add(this.dust);
    this.dustGroup.visible = false;
    this.scene.add(this.dustGroup);
  }

  setWeather(type) {
    if (!WEATHERS[type]) return;
    this.type = type;
    this.target = makeState(type);
    if (this.scene.userData) this.scene.userData.weatherType = type;
  }

  _applyFog() {
    const s = this.state;
    if (!this.scene.fog) this.scene.fog = new THREE.FogExp2(s.fog.clone(), s.fogDensity);
    this.scene.fog.color.copy(s.fog);
    const volumetric = this.quality.volumetricFog !== false ? 1.08 : 1;
    this.scene.fog.density = s.fogDensity * volumetric;
    this.scene.userData.post = {
      exposure: s.exposure,
      tint: s.tint.slice(),
      saturation: s.saturation,
      contrast: s.contrast,
      vignette: s.vignette,
      grain: s.grain,
      weatherType: this.type,
    };
    this.rainMaterial.opacity = 0.55 * s.rain;
    this.rainGroup.visible = s.rain > 0.01;
    this.dustMaterial.opacity = 0.2 * s.dust;
    this.dustGroup.visible = s.dust > 0.01;
  }

  update(dt = 0.016) {
    const k = Math.min(1, (dt || 0.016) * 0.9);
    const s = this.state;
    const t = this.target;
    s.fog.lerp(t.fog, k);
    s.fogDensity += (t.fogDensity - s.fogDensity) * k;
    s.exposure += (t.exposure - s.exposure) * k;
    s.saturation += (t.saturation - s.saturation) * k;
    s.contrast += (t.contrast - s.contrast) * k;
    s.vignette += (t.vignette - s.vignette) * k;
    s.grain += (t.grain - s.grain) * k;
    s.rain += (t.rain - s.rain) * k;
    s.dust += (t.dust - s.dust) * k;
    for (let i = 0; i < 3; i += 1) s.tint[i] += (t.tint[i] - s.tint[i]) * k;

    this._applyFog();
    this._updateRain(dt);
    this._updateDust(dt);
  }

  _updateRain(dt) {
    if (!this.rainGroup.visible) return;
    const positions = this.rainGeometry.attributes.position.array;
    const half = 48;
    const top = 42;
    for (let i = 0; i < this.rainVelocities.length; i += 1) {
      const i3 = i * 3;
      positions[i3 + 1] -= this.rainVelocities[i] * dt;
      positions[i3] += this.rainDriftX[i] * dt;
      positions[i3 + 2] += this.rainDriftZ[i] * dt;
      if (positions[i3 + 1] < -3) {
        positions[i3 + 1] = top + Math.random() * 8;
        positions[i3] = (Math.random() * 2 - 1) * half;
        positions[i3 + 2] = (Math.random() * 2 - 1) * half;
      }
      if (positions[i3] > half) positions[i3] -= half * 2;
      if (positions[i3] < -half) positions[i3] += half * 2;
      if (positions[i3 + 2] > half) positions[i3 + 2] -= half * 2;
      if (positions[i3 + 2] < -half) positions[i3 + 2] += half * 2;
    }
    this.rainGeometry.attributes.position.needsUpdate = true;
    this.rainGroup.position.set(this.camera.position.x, this.camera.position.y - 2, this.camera.position.z);
  }

  _updateDust(dt) {
    if (!this.dustGroup.visible) return;
    const positions = this.dustGeometry.attributes.position.array;
    const half = 100;
    const top = 26;
    for (let i = 0; i < this.dustDriftX.length; i += 1) {
      const i3 = i * 3;
      positions[i3] += this.dustDriftX[i] * dt;
      positions[i3 + 2] += this.dustDriftZ[i] * dt;
      positions[i3 + 1] += this.dustRise[i] * dt;
      if (positions[i3 + 1] > top) positions[i3 + 1] -= top;
      if (positions[i3] > half) positions[i3] -= half * 2;
      if (positions[i3] < -half) positions[i3] += half * 2;
      if (positions[i3 + 2] > half) positions[i3 + 2] -= half * 2;
      if (positions[i3 + 2] < -half) positions[i3 + 2] += half * 2;
    }
    this.dustGeometry.attributes.position.needsUpdate = true;
    this.dustGroup.position.copy(this.camera.position);
  }
}
