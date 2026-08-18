import * as THREE from 'three';
import { seededRandom } from '../core/Noise.js';

const WEATHER = {
  clear: {
    zenith: '#2b4f8c',
    horizon: '#f2a05a',
    ground: '#7c6648',
    sunColor: '#ffe0a8',
    sun: 1,
    cloudColor: '#f2e7d8',
    cloudDensity: 0.5,
    cloudOpacity: 0.4,
    fogColor: '#b9b6a8',
    fogDensity: 0.0038,
    star: 0.12,
    weatherMix: 0,
    hemiSky: '#9cc4e8',
    hemiGround: '#6a563f',
  },
  rain: {
    zenith: '#39424d',
    horizon: '#7d878e',
    ground: '#4d555a',
    sunColor: '#cfd8dd',
    sun: 0.28,
    cloudColor: '#9aa3a8',
    cloudDensity: 1.15,
    cloudOpacity: 0.9,
    fogColor: '#707b81',
    fogDensity: 0.011,
    star: 0,
    weatherMix: 0.38,
    hemiSky: '#7c8c99',
    hemiGround: '#3f474c',
  },
  dust: {
    zenith: '#b18a5c',
    horizon: '#d6b184',
    ground: '#8c6d49',
    sunColor: '#f6d9a5',
    sun: 0.75,
    cloudColor: '#c9ab80',
    cloudDensity: 0.28,
    cloudOpacity: 0.42,
    fogColor: '#c2a374',
    fogDensity: 0.007,
    star: 0,
    weatherMix: 0.28,
    hemiSky: '#b59a77',
    hemiGround: '#6b5639',
  },
};

function cloneWeather(type) {
  const src = WEATHER[type] || WEATHER.clear;
  return {
    zenith: new THREE.Color(src.zenith),
    horizon: new THREE.Color(src.horizon),
    ground: new THREE.Color(src.ground),
    sunColor: new THREE.Color(src.sunColor),
    cloudColor: new THREE.Color(src.cloudColor),
    fogColor: new THREE.Color(src.fogColor),
    hemiSky: new THREE.Color(src.hemiSky),
    hemiGround: new THREE.Color(src.hemiGround),
    sun: src.sun,
    cloudDensity: src.cloudDensity,
    cloudOpacity: src.cloudOpacity,
    fogDensity: src.fogDensity,
    star: src.star,
    weatherMix: src.weatherMix,
  };
}

function makeCloudSpriteTexture() {
  const size = 128;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  const rand = seededRandom(99);
  for (let i = 0; i < 10; i += 1) {
    const x = size * (0.25 + rand() * 0.5);
    const y = size * (0.3 + rand() * 0.4);
    const r = size * (0.12 + rand() * 0.18);
    const gradient = ctx.createRadialGradient(x, y, 0, x, y, r);
    gradient.addColorStop(0, `rgba(255,255,255,${0.28 + rand() * 0.28})`);
    gradient.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, size, size);
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.NoColorSpace;
  texture.wrapS = THREE.ClampToEdgeWrapping;
  texture.wrapT = THREE.ClampToEdgeWrapping;
  return texture;
}

function makeDustTexture() {
  const size = 64;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  const gradient = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  gradient.addColorStop(0, 'rgba(190,175,150,0.8)');
  gradient.addColorStop(0.4, 'rgba(160,145,120,0.35)');
  gradient.addColorStop(1, 'rgba(120,105,85,0)');
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, size, size);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.NoColorSpace;
  texture.wrapS = THREE.ClampToEdgeWrapping;
  texture.wrapT = THREE.ClampToEdgeWrapping;
  return texture;
}

const ATMOSPHERE_VERTEX = `
  varying vec3 vWorldDirection;
  void main() {
    vec4 worldPosition = modelMatrix * vec4(position, 1.0);
    vWorldDirection = worldPosition.xyz;
    gl_Position = projectionMatrix * viewMatrix * worldPosition;
  }
`;

const ATMOSPHERE_FRAGMENT = `
  varying vec3 vWorldDirection;
  uniform vec3 uSunDirection;
  uniform vec3 uZenith;
  uniform vec3 uHorizon;
  uniform vec3 uGroundColor;
  uniform vec3 uSunColor;
  uniform vec3 uWeatherColor;
  uniform float uSunSize;
  uniform float uWeatherMix;
  uniform float uStarIntensity;
  uniform float uTime;
  uniform float uVolumetric;

  float hash3(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
  }

  void main() {
    vec3 dir = normalize(vWorldDirection);
    float h = clamp(dir.y, -1.0, 1.0);
    float sunDot = clamp(dot(dir, normalize(uSunDirection)), -1.0, 1.0);
    float ang = acos(sunDot);

    vec3 col = mix(uGroundColor, uHorizon, pow(1.0 - max(h, 0.0), 2.4));
    col = mix(col, uZenith, smoothstep(0.0, 0.5, h));
    col += uSunColor * (smoothstep(uSunSize * 1.7, uSunSize * 0.45, ang) * 3.2 + exp(-ang * 26.0) * 0.8);
    if (uVolumetric > 0.5) {
      float sunHaze = exp(-ang * 14.0) * 0.28;
      float horizonHaze = exp(-abs(h - 0.02) * 9.0) * 0.16;
      col += uSunColor * (sunHaze + horizonHaze);
    }

    vec3 cell = floor(dir * 140.0);
    float star = step(0.9915, hash3(cell));
    float twinkle = 0.6 + 0.4 * sin(uTime * 1.8 + hash3(cell) * 41.0);
    col += vec3(0.72, 0.85, 1.0) * star * uStarIntensity * twinkle;

    float haze = smoothstep(0.0, 0.24, 1.0 - abs(h - 0.12));
    col = mix(col, uWeatherColor, uWeatherMix * haze);
    gl_FragColor = vec4(col, 1.0);
  }
`;

const CLOUD_VERTEX = `
  varying vec3 vWorldDirection;
  void main() {
    vec4 worldPosition = modelMatrix * vec4(position, 1.0);
    vWorldDirection = worldPosition.xyz;
    gl_Position = projectionMatrix * viewMatrix * worldPosition;
  }
`;

const CLOUD_FRAGMENT = `
  varying vec3 vWorldDirection;
  uniform vec3 uCloudColor;
  uniform vec3 uSunDirection;
  uniform float uTime;
  uniform float uWind;
  uniform float uDensity;
  uniform float uOpacity;

  float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
  }

  float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
  }

  float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
      v += a * noise(p);
      p = p * 2.03 + vec2(13.7, 7.3);
      a *= 0.5;
    }
    return v;
  }

  void main() {
    vec3 dir = normalize(vWorldDirection);
    float h = dir.y;
    if (h < 0.005) discard;
    vec2 p = dir.xz / max(h, 0.03);
    vec2 wind = vec2(uTime * uWind * 0.018, uTime * uWind * 0.008);
    float n = fbm(p * 0.34 + wind);
    float detail = fbm(p * 1.1 - wind * 1.7 + 31.0);
    float cloud = smoothstep(0.46 - uDensity * 0.12, 0.64, n * 0.72 + detail * 0.34);
    float mask = smoothstep(0.015, 0.09, h) * (1.0 - smoothstep(0.30, 0.44, h));
    float alpha = cloud * uOpacity * mask;
    vec3 base = mix(uCloudColor, vec3(1.0), cloud * 0.32);
    float sun = max(dot(dir, normalize(uSunDirection)), 0.0);
    base += uCloudColor * sun * 0.35;
    gl_FragColor = vec4(base, alpha);
  }
`;

export class SkySystem {
  constructor(scene, quality = {}) {
    this.scene = scene;
    this.quality = quality;
    this.time = 0;
    this.weatherType = 'clear';
    this.group = new THREE.Group();
    scene.add(this.group);
    this.sunDir = new THREE.Vector3(-0.45, 0.3, -0.82).normalize();
    this.currentWeather = cloneWeather('clear');
    this.targetWeather = cloneWeather('clear');

    this.atmosphereUniforms = {
      uSunDirection: { value: this.sunDir.clone() },
      uZenith: { value: this.currentWeather.zenith.clone() },
      uHorizon: { value: this.currentWeather.horizon.clone() },
      uGroundColor: { value: this.currentWeather.ground.clone() },
      uSunColor: { value: this.currentWeather.sunColor.clone() },
      uWeatherColor: { value: this.currentWeather.fogColor.clone() },
      uSunSize: { value: 0.014 },
      uWeatherMix: { value: 0 },
      uStarIntensity: { value: 0 },
      uTime: { value: 0 },
      uVolumetric: { value: quality.volumetricFog !== false ? 1 : 0 },
    };

    this.atmosphere = new THREE.Mesh(
      new THREE.SphereGeometry(950, 48, 32),
      new THREE.ShaderMaterial({
        uniforms: this.atmosphereUniforms,
        vertexShader: ATMOSPHERE_VERTEX,
        fragmentShader: ATMOSPHERE_FRAGMENT,
        side: THREE.BackSide,
        depthWrite: false,
        fog: false,
      })
    );
    this.atmosphere.renderOrder = -10;
    this.group.add(this.atmosphere);

    this.cloudUniforms = {
      uCloudColor: { value: this.currentWeather.cloudColor.clone() },
      uSunDirection: { value: this.sunDir.clone() },
      uTime: { value: 0 },
      uWind: { value: 0.7 },
      uDensity: { value: this.currentWeather.cloudDensity },
      uOpacity: { value: this.currentWeather.cloudOpacity },
    };
    this.clouds = new THREE.Mesh(
      new THREE.SphereGeometry(910, 64, 36),
      new THREE.ShaderMaterial({
        uniforms: this.cloudUniforms,
        vertexShader: CLOUD_VERTEX,
        fragmentShader: CLOUD_FRAGMENT,
        transparent: true,
        side: THREE.BackSide,
        depthWrite: false,
        fog: false,
      })
    );
    this.clouds.renderOrder = 5;
    this.clouds.visible = quality.clouds !== false;
    this.group.add(this.clouds);

    const cloudSpriteCount = quality.clouds === false ? 0 : 84;
    const cloudSpritePositions = new Float32Array(cloudSpriteCount * 3);
    const cloudRand = seededRandom(2035);
    for (let i = 0; i < cloudSpriteCount; i += 1) {
      const angle = cloudRand() * Math.PI * 2;
      const elevation = 0.06 + cloudRand() * 0.2;
      const radius = 600;
      const cosElevation = Math.cos(elevation);
      cloudSpritePositions[i * 3] = Math.cos(angle) * cosElevation * radius;
      cloudSpritePositions[i * 3 + 1] = Math.sin(elevation) * radius;
      cloudSpritePositions[i * 3 + 2] = Math.sin(angle) * cosElevation * radius;
    }
    this.cloudSpriteGeometry = new THREE.BufferGeometry();
    this.cloudSpriteGeometry.setAttribute('position', new THREE.BufferAttribute(cloudSpritePositions, 3));
    this.cloudSpriteMaterial = new THREE.PointsMaterial({
      map: makeCloudSpriteTexture(),
      color: this.currentWeather.cloudColor.clone(),
      size: 110,
      sizeAttenuation: true,
      transparent: true,
      opacity: 0,
      depthWrite: false,
      depthTest: true,
      blending: THREE.NormalBlending,
    });
    this.cloudSprites = new THREE.Points(this.cloudSpriteGeometry, this.cloudSpriteMaterial);
    this.cloudSprites.frustumCulled = false;
    this.cloudSprites.renderOrder = 6;
    this.group.add(this.cloudSprites);

    this.sunLight = new THREE.DirectionalLight(0xffd6a0, 2.6);
    this.sunLight.position.copy(this.sunDir).multiplyScalar(220);
    this.sunLight.target.position.set(0, 0, 0);
    const shadowMapSize = quality.shadowMapSize || 2048;
    if (quality.shadows !== false) {
      this.sunLight.castShadow = true;
      this.sunLight.shadow.mapSize.set(shadowMapSize, shadowMapSize);
      const shadowCamera = this.sunLight.shadow.camera;
      shadowCamera.left = -230;
      shadowCamera.right = 230;
      shadowCamera.top = 230;
      shadowCamera.bottom = -230;
      shadowCamera.near = 10;
      shadowCamera.far = 650;
      this.sunLight.shadow.bias = -0.0004;
      this.sunLight.shadow.normalBias = 0.02;
      shadowCamera.updateProjectionMatrix();
    }
    this.group.add(this.sunLight);
    this.group.add(this.sunLight.target);

    this.nearSunLight = null;
    if ((quality.shadowCascades || 1) > 1 && quality.shadows !== false) {
      this.nearSunLight = new THREE.DirectionalLight(0xffd6a0, 0.85);
      this.nearSunLight.castShadow = true;
      this.nearSunLight.shadow.mapSize.set(shadowMapSize, shadowMapSize);
      const nearCamera = this.nearSunLight.shadow.camera;
      nearCamera.left = -70;
      nearCamera.right = 70;
      nearCamera.top = 70;
      nearCamera.bottom = -70;
      nearCamera.near = 10;
      nearCamera.far = 260;
      this.nearSunLight.shadow.bias = -0.0004;
      this.nearSunLight.shadow.normalBias = 0.02;
      nearCamera.updateProjectionMatrix();
      this.nearSunLight.target.position.set(0, 0, 0);
      this.group.add(this.nearSunLight);
      this.group.add(this.nearSunLight.target);
    }

    this.hemi = new THREE.HemisphereLight(0x9cc4e8, 0x6a563f, 1);
    this.group.add(this.hemi);
    this._buildHelicopters();

    this.scene.fog = this.scene.fog || new THREE.FogExp2(
      this.currentWeather.fogColor.clone(),
      this.currentWeather.fogDensity
    );
  }

  setWeather(type) {
    if (!WEATHER[type]) return;
    this.weatherType = type;
    this.targetWeather = cloneWeather(type);
    if (this.scene.userData) this.scene.userData.weatherType = type;
  }

  update(time = 0, dt = 0.016) {
    this.time = time;
    const userWeather = this.scene.userData?.weatherType;
    if (userWeather && userWeather !== this.weatherType) this.setWeather(userWeather);

    const t = Math.min(1, (dt || 0.016) * 1.1);
    const cur = this.currentWeather;
    const target = this.targetWeather;
    cur.zenith.lerp(target.zenith, t);
    cur.horizon.lerp(target.horizon, t);
    cur.ground.lerp(target.ground, t);
    cur.sunColor.lerp(target.sunColor, t);
    cur.cloudColor.lerp(target.cloudColor, t);
    cur.fogColor.lerp(target.fogColor, t);
    cur.hemiSky.lerp(target.hemiSky, t);
    cur.hemiGround.lerp(target.hemiGround, t);
    cur.sun += (target.sun - cur.sun) * t;
    cur.cloudDensity += (target.cloudDensity - cur.cloudDensity) * t;
    cur.cloudOpacity += (target.cloudOpacity - cur.cloudOpacity) * t;
    cur.fogDensity += (target.fogDensity - cur.fogDensity) * t;
    cur.star += (target.star - cur.star) * t;
    cur.weatherMix += (target.weatherMix - cur.weatherMix) * t;

    const cycle = this.time * 0.006;
    this.sunDir.set(
      Math.cos(cycle) * 0.55 - 0.15,
      0.26 + Math.sin(this.time * 0.015) * 0.07,
      -Math.sin(cycle) * 0.75 - 0.1
    ).normalize();

    const au = this.atmosphereUniforms;
    au.uSunDirection.value.copy(this.sunDir);
    au.uZenith.value.copy(cur.zenith);
    au.uHorizon.value.copy(cur.horizon);
    au.uGroundColor.value.copy(cur.ground);
    au.uSunColor.value.copy(cur.sunColor);
    au.uWeatherColor.value.copy(cur.fogColor);
    au.uWeatherMix.value = cur.weatherMix;
    au.uStarIntensity.value = cur.star * Math.max(0, Math.min(1, (0.08 - this.sunDir.y) * 12));
    au.uTime.value = this.time;
    au.uVolumetric.value = this.quality.volumetricFog !== false ? 1 : 0;

    const cu = this.cloudUniforms;
    cu.uCloudColor.value.copy(cur.cloudColor);
    cu.uSunDirection.value.copy(this.sunDir);
    cu.uTime.value = this.time;
    cu.uWind.value = 0.65 + Math.sin(this.time * 0.11) * 0.25;
    cu.uDensity.value = cur.cloudDensity;
    cu.uOpacity.value = cur.cloudOpacity;

    this.cloudSpriteMaterial.opacity = cur.cloudOpacity * 0.42;
    this.cloudSpriteMaterial.color.copy(cur.cloudColor).multiplyScalar(1.15);
    this.cloudSprites.rotation.y = this.time * 0.004;

    this.sunLight.position.copy(this.sunDir).multiplyScalar(220);
    this.sunLight.color.copy(cur.sunColor);
    this.sunLight.intensity = (this.nearSunLight ? 2.2 : 2.6) * cur.sun;
    if (this.nearSunLight) {
      const cam = this.scene.userData?.camera;
      if (cam) {
        this.nearSunLight.position.copy(cam.position).addScaledVector(this.sunDir, 70);
        this.nearSunLight.target.position.copy(cam.position);
        this.nearSunLight.target.updateMatrixWorld();
        this.nearSunLight.updateMatrixWorld();
      } else {
        this.nearSunLight.position.copy(this.sunDir).multiplyScalar(220);
      }
      this.nearSunLight.color.copy(cur.sunColor);
      this.nearSunLight.intensity = 0.5 * cur.sun;
    }
    this.hemi.color.copy(cur.hemiSky);
    this.hemi.groundColor.copy(cur.hemiGround);
    this.hemi.intensity = 0.62 + cur.sun * 0.38;

    if (this.scene.fog) {
      this.scene.fog.color.copy(cur.fogColor);
      this.scene.fog.density = cur.fogDensity;
    }
    this._updateHelicopters(dt);
  }

  _buildHelicopters() {
    this.helicopters = [];
    const dustTexture = makeDustTexture();
    const specs = [
      { radius: 95, zScale: 0.85, speed: 0.015, phase: 0.6, y: 28, color: 0x3f4a3a },
      { radius: 120, zScale: 0.8, speed: 0.011, phase: 1.2, y: 34, color: 0x4a4136 },
    ];
    for (const spec of specs) {
      this.helicopters.push(this._buildHelicopter(spec, dustTexture));
    }
  }

  _buildHelicopter(spec, dustTexture) {
    const group = new THREE.Group();
    const bodyMat = new THREE.MeshStandardMaterial({ color: spec.color, roughness: 0.65, metalness: 0.3 });
    const darkMat = new THREE.MeshStandardMaterial({ color: 0x20241f, roughness: 0.8, metalness: 0.2 });
    const glassMat = new THREE.MeshStandardMaterial({ color: 0x18303a, roughness: 0.15, metalness: 0.5 });
    const beamMat = new THREE.MeshBasicMaterial({
      color: 0xfff2cc,
      transparent: true,
      opacity: 0.13,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      side: THREE.DoubleSide,
    });

    const body = new THREE.Mesh(new THREE.BoxGeometry(2.6, 0.72, 1.05), bodyMat);
    body.position.y = 0.45;
    const cockpit = new THREE.Mesh(new THREE.SphereGeometry(0.48, 8, 6), glassMat);
    cockpit.position.set(0.75, 0.8, 0);
    cockpit.scale.set(0.75, 0.65, 0.75);
    const tail = new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.18, 0.2), bodyMat);
    tail.position.set(-1.8, 0.55, 0);
    const skidA = new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.08, 0.12), darkMat);
    skidA.position.set(0, -0.08, 0.5);
    const skidB = skidA.clone();
    skidB.position.z = -0.5;

    const tailRotor = new THREE.Group();
    tailRotor.position.set(-3, 0.9, 0);
    tailRotor.add(new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.02, 1), darkMat));

    const rotorPivot = new THREE.Group();
    rotorPivot.position.set(0, 1.05, 0);
    const blade1 = new THREE.Mesh(new THREE.BoxGeometry(3.8, 0.04, 0.14), darkMat);
    const blade2 = blade1.clone();
    blade2.rotation.y = Math.PI / 2;
    rotorPivot.add(blade1, blade2);

    const beam = new THREE.Mesh(new THREE.ConeGeometry(0.55, 7, 10, 1, true), beamMat);
    beam.position.y = -3.5;
    beam.rotation.x = Math.PI;

    const spot = new THREE.SpotLight(0xfff2cc, 3.5, 50, 0.55, 0.35, 1.2);
    spot.position.set(0, 0.2, 0);
    const spotTarget = new THREE.Object3D();
    spot.target = spotTarget;
    this.group.add(spotTarget);

    const dustCount = 20;
    const dustPositions = new Float32Array(dustCount * 3);
    for (let i = 0; i < dustCount; i += 1) {
      dustPositions[i * 3] = -5 - i * 1.45;
      dustPositions[i * 3 + 1] = -2 - (i % 3) * 0.5;
      dustPositions[i * 3 + 2] = (i % 2 === 0 ? -0.6 : 0.6) + Math.sin(i * 3.7) * 0.5;
    }
    const dustGeometry = new THREE.BufferGeometry();
    dustGeometry.setAttribute('position', new THREE.BufferAttribute(dustPositions, 3));
    const dustMat = new THREE.PointsMaterial({
      map: dustTexture,
      color: 0xa89a7f,
      size: 4.5,
      sizeAttenuation: true,
      transparent: true,
      opacity: 0.16,
      depthWrite: false,
      blending: THREE.NormalBlending,
    });
    const dust = new THREE.Points(dustGeometry, dustMat);
    dust.position.set(0, -2, 0);

    group.add(body, cockpit, tail, skidA, skidB, tailRotor, rotorPivot, beam, spot, dust);
    group.frustumCulled = false;
    this.group.add(group);
    return { group, rotorPivot, tailRotor, spot, spotTarget, dustMat, spec };
  }

  _updateHelicopters(dt) {
    if (!this.helicopters) return;
    const t = this.time;
    for (const heli of this.helicopters) {
      const spec = heli.spec;
      const angle = t * spec.speed + spec.phase;
      const x = Math.cos(angle) * spec.radius;
      const z = Math.sin(angle) * spec.radius * spec.zScale;
      const y = spec.y + Math.sin(t * 0.22 + spec.phase) * 4;
      const vx = -Math.sin(angle) * spec.radius;
      const vz = Math.cos(angle) * spec.radius * spec.zScale;
      heli.group.position.set(x, y, z);
      heli.group.rotation.y = Math.atan2(vx, vz) - Math.PI / 2;
      heli.group.rotation.z = Math.sin(t * 0.15 + spec.phase) * 0.08;
      heli.rotorPivot.rotation.y += dt * 18;
      heli.tailRotor.rotation.x += dt * 45;
      const groundY = this.scene.userData?.terrain?.heightAt?.(x, z) ?? 0;
      heli.spotTarget.position.set(x, groundY + 0.4, z);
      heli.dustMat.opacity = 0.14 + 0.05 * (0.5 + 0.5 * Math.sin(t * 2 + spec.phase));
    }
  }
}
