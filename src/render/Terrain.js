import * as THREE from 'three';
import { fbm2D, seededRandom } from '../core/Noise.js';
import { createTextureSet } from '../core/Textures.js';

const SIZE = 400;
const LAKE = { x: 105, z: -195, w: 90, d: 90 };

function smoothstep(edge0, edge1, value) {
  const t = Math.max(0, Math.min(1, (value - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

function distToSegment(x, z, ax, az, bx, bz) {
  const dx = bx - ax;
  const dz = bz - az;
  const lenSq = dx * dx + dz * dz;
  let t = lenSq > 0 ? ((x - ax) * dx + (z - az) * dz) / lenSq : 0;
  t = Math.max(0, Math.min(1, t));
  const px = ax + dx * t;
  const pz = az + dz * t;
  return Math.hypot(x - px, z - pz);
}

const WATER_VERTEX = `
  varying vec2 vUv;
  varying vec3 vWorld;
  void main() {
    vUv = uv;
    vec4 worldPosition = modelMatrix * vec4(position, 1.0);
    vWorld = worldPosition.xyz;
    gl_Position = projectionMatrix * viewMatrix * worldPosition;
  }
`;

const WATER_FRAGMENT = `
  varying vec2 vUv;
  varying vec3 vWorld;
  uniform float uTime;
  uniform vec3 uSunDir;
  uniform vec3 uSunColor;
  uniform vec3 uSkyColor;
  uniform vec3 uColor;
  uniform vec2 uLakeMin;
  uniform vec2 uLakeMax;

  void main() {
    vec2 p = vUv * 64.0;
    float t = uTime;
    float w1 = sin(p.x * 0.9 + t * 1.2) * 0.22 + sin(p.y * 1.1 - t * 0.9) * 0.16;
    float w2 = sin(p.x * 1.9 + p.y * 1.3 + t * 1.7) * 0.09;
    float w3 = sin(p.x * 0.5 - t * 0.6) * 0.06 + sin(p.y * 0.7 + t * 0.8) * 0.06;
    vec3 normal = normalize(vec3(w1 + w3, 1.0, w2 + w3));
    vec3 viewDir = normalize(cameraPosition - vWorld);
    vec3 sunDir = normalize(uSunDir);
    float fres = pow(1.0 - max(dot(normal, viewDir), 0.0), 3.0);

    vec3 reflectDir = reflect(-viewDir, normal);
    float sunDot = max(dot(reflectDir, sunDir), 0.0);
    float sunGlint = pow(sunDot, 220.0) * 1.6;
    vec3 hSun = normalize(vec3(sunDir.x, 0.0, sunDir.z));
    vec3 hView = normalize(vec3(viewDir.x, 0.0, viewDir.z));
    float streak = pow(max(dot(hView, hSun), 0.0), 28.0);

    vec3 skyReflect = mix(uSkyColor, uSunColor, smoothstep(0.0, 0.8, sunDot) * 0.65);
    vec3 col = uColor * 0.78;

    vec2 wp = vWorld.xz;
    float ex = min(wp.x - uLakeMin.x, uLakeMax.x - wp.x);
    float ez = min(wp.y - uLakeMin.y, uLakeMax.y - wp.y);
    float edgeDist = min(ex, ez);
    float shallow = smoothstep(0.0, 7.0, edgeDist);
    vec3 shallowColor = mix(uColor * 1.22, vec3(0.6, 0.76, 0.72), 0.35);
    col = mix(shallowColor, col, shallow);

    col += skyReflect * fres * 0.42;
    col += uSunColor * sunGlint * 0.85;
    col += uSunColor * streak * 0.18;

    float foamWave = sin(p.x * 1.4 + p.y * 1.1 - t * 2.0) * 0.5 + 0.5;
    float foamMask = smoothstep(3.0, 0.4, edgeDist);
    float foam = foamMask * (0.55 + 0.45 * foamWave);
    col = mix(col, vec3(0.93, 0.97, 0.99), foam * 0.6);
    gl_FragColor = vec4(col, 0.9);
  }
`;

export class TerrainSystem {
  constructor(scene, quality = {}) {
    this.scene = scene;
    this.quality = quality;
    scene.userData = scene.userData || {};
    scene.userData.terrain = this;
    this.group = new THREE.Group();
    scene.add(this.group);
    this.lake = LAKE;
    this.waterTime = 0;

    this.roads = [
      { ax: -SIZE / 2, az: -6, bx: SIZE / 2, bz: -6, half: 7 },
      { ax: 6, az: -SIZE / 2, bx: 6, bz: SIZE / 2, half: 7 },
    ];
    this.craters = this._generateCraters();

    const presetSegments = quality.preset === 'medium' ? 128 : quality.preset === 'high' ? 192 : 256;
    const segments = quality.terrainSegments || presetSegments;
    const geometry = new THREE.PlaneGeometry(SIZE, SIZE, segments, segments);
    geometry.rotateX(-Math.PI / 2);

    const position = geometry.attributes.position;
    for (let i = 0; i < position.count; i += 1) {
      const x = position.getX(i);
      const z = position.getZ(i);
      position.setY(i, this.heightAt(x, z));
    }
    position.needsUpdate = true;
    geometry.computeVertexNormals();

    const uv = geometry.attributes.uv;
    geometry.setAttribute('uv2', new THREE.BufferAttribute(new Float32Array(uv.array), 2));
    geometry.setAttribute('color', new THREE.BufferAttribute(this._buildVertexColors(position), 3));

    const textures = createTextureSet('ground', { seed: 2035, size: 1024, repeat: 10 });
    const material = new THREE.MeshStandardMaterial({
      map: textures.map,
      normalMap: textures.normalMap,
      roughnessMap: textures.roughnessMap,
      metalnessMap: textures.metalnessMap,
      aoMap: textures.aoMap,
      vertexColors: true,
      roughness: 0.92,
      metalness: 0.02,
      envMapIntensity: 0.55,
    });

    this.terrainMesh = new THREE.Mesh(geometry, material);
    this.terrainMesh.receiveShadow = true;
    this.group.add(this.terrainMesh);

    const waterGeometry = new THREE.PlaneGeometry(LAKE.w + 14, LAKE.d + 14, 48, 48);
    waterGeometry.rotateX(-Math.PI / 2);
    this.waterMaterial = new THREE.ShaderMaterial({
      uniforms: {
        uTime: { value: 0 },
        uSunDir: { value: new THREE.Vector3(-0.45, 0.3, -0.82).normalize() },
        uSunColor: { value: new THREE.Color('#ffe0a8') },
        uSkyColor: { value: new THREE.Color('#3f6d8f') },
        uColor: { value: new THREE.Color('#2f5d5f') },
        uLakeMin: { value: new THREE.Vector2(LAKE.x, LAKE.z) },
        uLakeMax: { value: new THREE.Vector2(LAKE.x + LAKE.w, LAKE.z + LAKE.d) },
      },
      vertexShader: WATER_VERTEX,
      fragmentShader: WATER_FRAGMENT,
      transparent: true,
      side: THREE.DoubleSide,
      depthWrite: false,
      fog: false,
    });
    this.water = new THREE.Mesh(waterGeometry, this.waterMaterial);
    this.water.position.set(LAKE.x + LAKE.w / 2, -0.72, LAKE.z + LAKE.d / 2);
    this.group.add(this.water);
  }

  _generateCraters() {
    const rand = seededRandom(2035);
    const craters = [];
    const count = 34;
    for (let i = 0; i < count; i += 1) {
      const angle = rand() * Math.PI * 2;
      const radius = 38 + rand() * 152;
      let x = Math.cos(angle) * radius;
      let z = Math.sin(angle) * radius;
      if (Math.hypot(x, z) < 28) {
        x *= 1.6;
        z *= 1.6;
      }
      craters.push({
        x,
        z,
        r: 3 + rand() * 8,
        depth: 0.7 + rand() * 1.8,
        rim: 0.15 + rand() * 0.38,
      });
    }
    return craters;
  }

  _roadInfluence(x, z) {
    let influence = 0;
    for (const road of this.roads) {
      const d = distToSegment(x, z, road.ax, road.az, road.bx, road.bz);
      influence = Math.max(influence, 1 - smoothstep(road.half - 2.5, road.half + 5, d));
    }
    return influence;
  }

  heightAt(x, z) {
    let h = (fbm2D(x * 0.018, z * 0.018, 5, 2035) - 0.5) * 7.5;
    h += Math.sin(x * 0.007 + z * 0.004) * 0.6;
    h += Math.cos(z * 0.009 - x * 0.003) * 0.45;

    const road = this._roadInfluence(x, z);
    h = h * (1 - road) + road * 0.05;

    for (const crater of this.craters) {
      const d = Math.hypot(x - crater.x, z - crater.z);
      if (d < crater.r) {
        const t = d / crater.r;
        h -= crater.depth * Math.pow(1 - t, 1.8);
        h += crater.rim * Math.exp(-Math.pow((t - 0.82) * 6, 2));
      }
    }

    const lake = this.lake;
    if (x > lake.x && x < lake.x + lake.w && z > lake.z && z < lake.z + lake.d) {
      const edge = Math.min(
        x - lake.x,
        lake.x + lake.w - x,
        z - lake.z,
        lake.z + lake.d - z
      ) / 6;
      h = Math.min(h, -0.85 + Math.max(0, edge) * 0.16);
    }
    return h;
  }

  sampleHeight(x, z) {
    return this.heightAt(x, z);
  }

  raycast(origin, direction, maxDistance = 500) {
    const dir = direction.clone().normalize();
    if (dir.lengthSq() < 1e-8) return null;

    const half = SIZE / 2;
    const ox = origin.x;
    const oy = origin.y;
    const oz = origin.z;
    if (ox < -half || ox > half || oz < -half || oz > half) return null;

    const maxDist = Number.isFinite(maxDistance) ? Math.max(0, maxDistance) : 500;
    if (maxDist <= 0) return null;

    let exit = maxDist;
    if (dir.x > 0) exit = Math.min(exit, (half - ox) / dir.x);
    else if (dir.x < 0) exit = Math.min(exit, (-half - ox) / dir.x);
    if (dir.z > 0) exit = Math.min(exit, (half - oz) / dir.z);
    else if (dir.z < 0) exit = Math.min(exit, (-half - oz) / dir.z);
    if (exit <= 0) return null;

    const h0 = this.heightAt(ox, oz);
    if (oy <= h0) return this.#buildTerrainHit(ox, oz, 0);

    const stepSize = 2;
    let t0 = 0;
    let t1 = Math.min(stepSize, exit);
    for (let i = 0; i < 200; i += 1) {
      const x = ox + dir.x * t1;
      const z = oz + dir.z * t1;
      const y = oy + dir.y * t1;
      if (y <= this.heightAt(x, z)) {
        const hitT = this.#refineTerrainHit(origin, dir, t0, t1);
        return this.#buildTerrainHit(origin.x + dir.x * hitT, origin.z + dir.z * hitT, hitT);
      }
      if (t1 >= exit) return null;
      t0 = t1;
      t1 = Math.min(t1 + stepSize, exit);
    }
    return null;
  }

  #refineTerrainHit(origin, dir, lo, hi) {
    for (let i = 0; i < 12; i += 1) {
      const mid = (lo + hi) * 0.5;
      const x = origin.x + dir.x * mid;
      const z = origin.z + dir.z * mid;
      const y = origin.y + dir.y * mid;
      if (y > this.heightAt(x, z)) lo = mid;
      else hi = mid;
    }
    return (lo + hi) * 0.5;
  }

  #buildTerrainHit(x, z, distance) {
    const point = new THREE.Vector3(x, this.heightAt(x, z), z);
    const normal = this.#terrainNormal(x, z);
    return { point, normal, distance };
  }

  #terrainNormal(x, z) {
    const e = 0.5;
    const left = this.heightAt(x - e, z);
    const right = this.heightAt(x + e, z);
    const down = this.heightAt(x, z - e);
    const up = this.heightAt(x, z + e);
    return new THREE.Vector3(
      -(right - left) / (2 * e),
      1,
      -(up - down) / (2 * e)
    ).normalize();
  }

  _buildVertexColors(position) {
    const colors = new Float32Array(position.count * 3);
    const base = new THREE.Color();
    const sand = new THREE.Color('#b6a276');
    const dirt = new THREE.Color('#5b4b33');
    const grass = new THREE.Color('#4f5f3a');
    const pale = new THREE.Color('#6c6f4f');
    const charred = new THREE.Color('#26221f');

    for (let i = 0; i < position.count; i += 1) {
      const x = position.getX(i);
      const z = position.getZ(i);
      const n = fbm2D(x * 0.012 + 100, z * 0.012 - 50, 3, 77);
      base.copy(grass).lerp(pale, n);

      const road = this._roadInfluence(x, z);
      if (road > 0.02) base.lerp(sand, road * 0.9);

      for (const crater of this.craters) {
        const d = Math.hypot(x - crater.x, z - crater.z);
        if (d < crater.r + 6) {
          const t = Math.max(0, 1 - d / (crater.r + 6));
          base.lerp(dirt, t * 0.75);
          if (d < crater.r * 0.45) base.lerp(charred, t * 0.7);
        }
      }

      const lake = this.lake;
      if (x > lake.x - 4 && x < lake.x + lake.w + 4 && z > lake.z - 4 && z < lake.z + lake.d + 4) {
        const edge = Math.min(
          x - lake.x + 4,
          lake.x + lake.w + 4 - x,
          z - lake.z + 4,
          lake.z + lake.d + 4 - z
        ) / 8;
        base.lerp(sand, Math.max(0, Math.min(1, edge)) * 0.85);
      }

      colors[i * 3] = base.r;
      colors[i * 3 + 1] = base.g;
      colors[i * 3 + 2] = base.b;
    }
    return colors;
  }

  update(dt = 0.016) {
    this.waterTime += Math.min(dt, 0.05);
    this.waterMaterial.uniforms.uTime.value = this.waterTime;
  }
}
