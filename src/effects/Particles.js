import * as THREE from 'three';

const VERTEX_SHADER = `
attribute vec3 aColor;
attribute float aSize;
attribute float aAlpha;
uniform float uPixelRatio;
uniform float uScale;
varying vec3 vColor;
varying float vAlpha;
void main() {
  vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
  gl_Position = projectionMatrix * mvPosition;
  float perspective = 280.0 / max(1.0, -mvPosition.z);
  gl_PointSize = clamp(aSize * uScale * uPixelRatio * perspective, 0.0, 96.0);
  vColor = aColor;
  vAlpha = aAlpha;
}
`;

const FRAGMENT_SHADER = `
precision highp float;
varying vec3 vColor;
varying float vAlpha;
void main() {
  vec2 uv = gl_PointCoord - 0.5;
  float d = length(uv);
  float falloff = smoothstep(0.5, 0.12, d);
  gl_FragColor = vec4(vColor, vAlpha * falloff);
}
`;

const POINT_TYPES = {
  smoke: { blend: THREE.NormalBlending, count: 240, gravity: 0.45, drag: 1.1 },
  fire: { blend: THREE.AdditiveBlending, count: 190, gravity: 0.85, drag: 1.45 },
  sparks: { blend: THREE.AdditiveBlending, count: 340, gravity: 10.5, drag: 0.45 },
  dust: { blend: THREE.NormalBlending, count: 180, gravity: 0.65, drag: 2.0 },
  muzzle: { blend: THREE.AdditiveBlending, count: 90, gravity: 0.0, drag: 3.5 },
  blood: { blend: THREE.NormalBlending, count: 130, gravity: 9.8, drag: 0.8 },
  rain: { blend: THREE.NormalBlending, count: 170, gravity: 0.0, drag: 0.0 },
};

const MESH_TYPES = {
  shell: {
    count: 110,
    geometry: new THREE.CylinderGeometry(0.016, 0.02, 0.055, 6),
    material: new THREE.MeshStandardMaterial({ color: 0xffd27a, roughness: 0.35, metalness: 0.8 }),
    gravity: 14,
    drag: 0.45,
    bounce: 0.32,
  },
  debris: {
    count: 90,
    geometry: new THREE.BoxGeometry(0.09, 0.09, 0.09),
    material: new THREE.MeshStandardMaterial({ color: 0x665c50, roughness: 0.85, metalness: 0.08, flatShading: true }),
    gravity: 16.5,
    drag: 0.55,
    bounce: 0.24,
  },
};

const rand = (min = 0, max = 1) => min + Math.random() * (max - min);

export class ParticleSystem {
  constructor(scene, quality = {}) {
    this.scene = scene;
    this.quality = quality;
    this.particleScale = Math.max(0.2, quality.particleScale ?? 1);
    this.points = Object.create(null);
    this.meshPools = Object.create(null);
    this._scratchColor = new THREE.Color();
    this._scratchPos = new THREE.Vector3();
    this._scratchVel = new THREE.Vector3();
    this._scratchDir = new THREE.Vector3();
    this._dummy = new THREE.Object3D();
    this._pixelRatio = Math.min(window.devicePixelRatio || 1, 2);

    for (const key of Object.keys(POINT_TYPES)) this.#createPointPool(key, POINT_TYPES[key]);
    for (const key of Object.keys(MESH_TYPES)) this.#createMeshPool(key, MESH_TYPES[key]);
  }

  #createPointPool(key, config) {
    const max = Math.max(24, Math.round(config.count * this.particleScale));
    const positions = new Float32Array(max * 3);
    const velocities = new Float32Array(max * 3);
    const colors = new Float32Array(max * 3);
    const sizes = new Float32Array(max);
    const baseSizes = new Float32Array(max);
    const alphas = new Float32Array(max);
    const life = new Float32Array(max);
    const maxLife = new Float32Array(max);
    const gravity = new Float32Array(max);
    const drag = new Float32Array(max);

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3).setUsage(THREE.DynamicDrawUsage));
    geometry.setAttribute('aColor', new THREE.BufferAttribute(colors, 3).setUsage(THREE.DynamicDrawUsage));
    geometry.setAttribute('aSize', new THREE.BufferAttribute(sizes, 1).setUsage(THREE.DynamicDrawUsage));
    geometry.setAttribute('aAlpha', new THREE.BufferAttribute(alphas, 1).setUsage(THREE.DynamicDrawUsage));
    geometry.setDrawRange(0, 0);

    const material = new THREE.ShaderMaterial({
      vertexShader: VERTEX_SHADER,
      fragmentShader: FRAGMENT_SHADER,
      uniforms: {
        uPixelRatio: { value: this._pixelRatio },
        uScale: { value: this.particleScale },
      },
      transparent: true,
      depthWrite: false,
      blending: config.blend,
    });

    const points = new THREE.Points(geometry, material);
    points.frustumCulled = false;
    points.name = `ParticlePool_${key}`;
    this.scene.add(points);
    this.points[key] = {
      key,
      max,
      count: 0,
      positions,
      velocities,
      colors,
      sizes,
      baseSizes,
      alphas,
      life,
      maxLife,
      gravity,
      drag,
      defaultGravity: config.gravity,
      defaultDrag: config.drag,
      geometry,
      material,
      points,
    };
  }

  #createMeshPool(key, config) {
    const max = Math.max(8, Math.round(config.count * this.particleScale));
    const geometry = config.geometry.clone();
    const material = config.material.clone();
    const mesh = new THREE.InstancedMesh(geometry, material, max);
    mesh.count = 0;
    mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    mesh.frustumCulled = false;
    mesh.name = `ParticleMesh_${key}`;
    this.scene.add(mesh);

    this.meshPools[key] = {
      key,
      max,
      count: 0,
      mesh,
      geometry,
      material,
      bounce: config.bounce,
      defaultGravity: config.gravity,
      defaultDrag: config.drag,
      positions: new Float32Array(max * 3),
      velocities: new Float32Array(max * 3),
      rotations: new Float32Array(max * 3),
      angular: new Float32Array(max * 3),
      sizes: new Float32Array(max),
      baseSizes: new Float32Array(max),
      life: new Float32Array(max),
      maxLife: new Float32Array(max),
      gravity: new Float32Array(max),
      drag: new Float32Array(max),
      colors: Array.from({ length: max }, () => new THREE.Color(0xffffff)),
    };
  }

  burst(options = {}) {
    const {
      position,
      velocity,
      count = 16,
      color = 0xffffff,
      size = 1,
      life = 1,
      gravity,
      drag,
      type = 'sparks',
    } = options;
    if (!position) return;

    const poolKey = type === 'rainPuff' ? 'rain' : type;
    if (this.meshPools[poolKey]) {
      this.#spawnMeshBurst(poolKey, options);
      return;
    }

    const pool = this.points[poolKey] || this.points.sparks;
    const amount = Math.min(Math.max(0, Math.round(count)), pool.max);
    const colors = Array.isArray(color) ? color : [color];
    const spread = Math.max(0.12, size * 0.16);

    for (let i = 0; i < amount; i++) {
      this.#randomDir(this._scratchDir);
      this.#copyVec(this._scratchPos, position);
      this._scratchPos.x += this._scratchDir.x * spread * rand(0.4, 1);
      this._scratchPos.y += this._scratchDir.y * spread * rand(0.4, 1);
      this._scratchPos.z += this._scratchDir.z * spread * rand(0.4, 1);

      this.#copyVec(this._scratchVel, velocity);
      this._scratchVel.x += this._scratchDir.x * size * rand(0.6, 2.2);
      this._scratchVel.y += this._scratchDir.y * size * rand(0.6, 2.2) + rand(0, 0.9);
      this._scratchVel.z += this._scratchDir.z * size * rand(0.6, 2.2);

      this.#spawnPoint(
        pool,
        this._scratchPos,
        this._scratchVel,
        colors[(Math.random() * colors.length) | 0],
        size * rand(0.65, 1.35),
        life * rand(0.65, 1.35),
        gravity,
        drag
      );
    }
  }

  #spawnPoint(pool, position, velocity, color, size, life, gravity, drag) {
    if (!pool || pool.count >= pool.max) return;
    const i = pool.count++;
    const ix = i * 3;

    pool.positions[ix] = position.x;
    pool.positions[ix + 1] = position.y;
    pool.positions[ix + 2] = position.z;
    pool.velocities[ix] = velocity.x;
    pool.velocities[ix + 1] = velocity.y;
    pool.velocities[ix + 2] = velocity.z;

    this._scratchColor.set(color);
    pool.colors[ix] = this._scratchColor.r;
    pool.colors[ix + 1] = this._scratchColor.g;
    pool.colors[ix + 2] = this._scratchColor.b;

    pool.baseSizes[i] = size;
    pool.sizes[i] = size;
    pool.alphas[i] = 1;
    pool.life[i] = life;
    pool.maxLife[i] = life;
    pool.gravity[i] = gravity ?? pool.defaultGravity;
    pool.drag[i] = drag ?? pool.defaultDrag;
  }

  muzzleFlash(position, direction) {
    if (!position) return;
    const dir = this._scratchDir;
    if (direction) this.#copyVec(dir, direction).normalize();
    else dir.set(0, 0, -1);

    const origin = this.#copyVec(this._scratchPos, position);
    const tip = this._scratchVel.copy(origin).addScaledVector(dir, 0.26);
    this.burst({
      position: tip,
      velocity: dir,
      count: Math.round(16 * this.particleScale) + 8,
      color: ['#fff2b0', '#ffd27a', '#ffb347'],
      size: 0.85,
      life: 0.12,
      type: 'muzzle',
      gravity: 0,
      drag: 3.5,
    });
    this.burst({
      position: origin,
      velocity: dir,
      count: Math.round(8 * this.particleScale) + 4,
      color: ['#ff9a3c', '#ff7b2d'],
      size: 0.42,
      life: 0.16,
      type: 'fire',
      gravity: 0.2,
      drag: 2.2,
    });
  }

  smoke(position, color = '#6f7473') {
    if (!position) return;
    this.burst({
      position,
      count: Math.round(10 * this.particleScale) + 4,
      color: [color, '#565b5c', '#7d8282'],
      size: 2.0,
      life: 2.6,
      velocity: { x: 0, y: 1.4, z: 0 },
      type: 'smoke',
      gravity: 0.18,
      drag: 0.9,
    });
  }

  sparks(position) {
    if (!position) return;
    this.burst({
      position,
      count: Math.round(22 * this.particleScale) + 10,
      color: ['#ffd166', '#ff9f43', '#ff6b35'],
      size: 0.2,
      life: 1.1,
      velocity: { x: 0, y: 2.2, z: 0 },
      type: 'sparks',
      gravity: 12,
      drag: 0.4,
    });
  }

  dust(position) {
    if (!position) return;
    this.burst({
      position,
      count: Math.round(10 * this.particleScale) + 4,
      color: ['#9a8d78', '#8b8172', '#a99c85'],
      size: 1.15,
      life: 1.6,
      velocity: { x: rand(-1.2, 1.2), y: 0.7, z: rand(-1.2, 1.2) },
      type: 'dust',
      gravity: 0.35,
      drag: 1.8,
    });
  }

  blood(position) {
    if (!position) return;
    this.burst({
      position,
      count: Math.round(14 * this.particleScale) + 6,
      color: ['#8f1d1d', '#c22f2f', '#a12525'],
      size: 0.18,
      life: 0.85,
      velocity: { x: rand(-1, 1), y: 1.6, z: rand(-1, 1) },
      type: 'blood',
      gravity: 10.5,
      drag: 0.8,
    });
  }

  rainPuff(position) {
    if (!position) return;
    this.burst({
      position,
      count: Math.round(8 * this.particleScale) + 3,
      color: '#d7e6f0',
      size: 0.34,
      life: 0.65,
      velocity: { x: rand(-0.5, 0.5), y: rand(-0.6, -0.2), z: rand(-0.5, 0.5) },
      type: 'rainPuff',
      gravity: 0,
      drag: 0,
    });
  }

  shellCasing(position, direction) {
    if (!position) return;
    this.burst({
      position,
      velocity: direction || { x: rand(-0.7, 0.7), y: 2.2, z: rand(-1.6, -0.8) },
      count: 1,
      color: ['#ffd27a', '#e8b65e'],
      size: 0.8,
      life: 2.4,
      type: 'shell',
      gravity: 14,
      drag: 0.45,
    });
  }

  #spawnMeshBurst(key, options = {}) {
    const pool = this.meshPools[key];
    if (!pool) return;
    const {
      position,
      velocity,
      count = 8,
      color = 0x6b6b6b,
      size = 0.1,
      life = 1.4,
      gravity,
      drag,
    } = options;
    if (!position) return;

    const amount = Math.min(Math.max(0, Math.round(count)), pool.max);
    const colors = Array.isArray(color) ? color : [color];
    for (let i = 0; i < amount; i++) {
      this.#randomDir(this._scratchDir);
      this.#copyVec(this._scratchPos, position);
      this._scratchPos.x += this._scratchDir.x * size * rand(0.3, 1);
      this._scratchPos.y += rand(-0.1, 0.4);
      this._scratchPos.z += this._scratchDir.z * size * rand(0.3, 1);

      this.#copyVec(this._scratchVel, velocity);
      this._scratchVel.x += this._scratchDir.x * size * rand(3, 8);
      this._scratchVel.y += rand(1.5, 5.5);
      this._scratchVel.z += this._scratchDir.z * size * rand(3, 8);

      this.#spawnMesh(
        pool,
        this._scratchPos,
        this._scratchVel,
        colors[(Math.random() * colors.length) | 0],
        size * rand(0.7, 1.3),
        life * rand(0.7, 1.4),
        gravity,
        drag
      );
    }
  }

  #spawnMesh(pool, position, velocity, color, size, life, gravity, drag) {
    if (!pool || pool.count >= pool.max) return;
    const i = pool.count++;
    const ix = i * 3;

    pool.positions[ix] = position.x;
    pool.positions[ix + 1] = position.y;
    pool.positions[ix + 2] = position.z;
    pool.velocities[ix] = velocity.x;
    pool.velocities[ix + 1] = velocity.y;
    pool.velocities[ix + 2] = velocity.z;
    pool.rotations[ix] = rand(0, Math.PI * 2);
    pool.rotations[ix + 1] = rand(0, Math.PI * 2);
    pool.rotations[ix + 2] = rand(0, Math.PI * 2);
    pool.angular[ix] = rand(-9, 9);
    pool.angular[ix + 1] = rand(-9, 9);
    pool.angular[ix + 2] = rand(-9, 9);
    pool.baseSizes[i] = size;
    pool.sizes[i] = size;
    pool.life[i] = life;
    pool.maxLife[i] = life;
    pool.gravity[i] = gravity ?? pool.defaultGravity;
    pool.drag[i] = drag ?? pool.defaultDrag;
    pool.colors[i].set(color);

    this._dummy.position.set(position.x, position.y, position.z);
    this._dummy.rotation.set(pool.rotations[ix], pool.rotations[ix + 1], pool.rotations[ix + 2]);
    this._dummy.scale.setScalar(Math.max(0.01, size));
    this._dummy.updateMatrix();
    pool.mesh.setMatrixAt(i, this._dummy.matrix);
    pool.mesh.setColorAt(i, pool.colors[i]);
    pool.mesh.instanceMatrix.needsUpdate = true;
    pool.mesh.instanceColor.needsUpdate = true;
  }

  update(dt = 0) {
    const delta = Math.min(Math.max(0, dt), 0.05);
    if (delta <= 0) return;
    for (const key of Object.keys(this.points)) this.#updatePointPool(this.points[key], delta);
    for (const key of Object.keys(this.meshPools)) this.#updateMeshPool(this.meshPools[key], delta);
  }

  #updatePointPool(pool, dt) {
    let count = pool.count;
    for (let i = count - 1; i >= 0; i--) {
      pool.life[i] -= dt;
      if (pool.life[i] <= 0) {
        this.#killPoint(pool, i, count);
        count--;
        continue;
      }

      const ix = i * 3;
      const damp = Math.max(0, 1 - pool.drag[i] * dt);
      pool.velocities[ix] *= damp;
      pool.velocities[ix + 1] = pool.velocities[ix + 1] * damp - pool.gravity[i] * dt;
      pool.velocities[ix + 2] *= damp;
      pool.positions[ix] += pool.velocities[ix] * dt;
      pool.positions[ix + 1] += pool.velocities[ix + 1] * dt;
      pool.positions[ix + 2] += pool.velocities[ix + 2] * dt;

      const t = Math.max(0, pool.life[i] / pool.maxLife[i]);
      const visual = this.#visual(pool.key, t);
      pool.sizes[i] = pool.baseSizes[i] * visual.size;
      pool.alphas[i] = visual.alpha;
    }
    pool.count = count;
    pool.geometry.setDrawRange(0, count);
    pool.geometry.attributes.position.needsUpdate = true;
    pool.geometry.attributes.aColor.needsUpdate = true;
    pool.geometry.attributes.aSize.needsUpdate = true;
    pool.geometry.attributes.aAlpha.needsUpdate = true;
  }

  #killPoint(pool, index, count) {
    if (index === count - 1) return;
    const cur = index * 3;
    const last = (count - 1) * 3;
    pool.positions[cur] = pool.positions[last];
    pool.positions[cur + 1] = pool.positions[last + 1];
    pool.positions[cur + 2] = pool.positions[last + 2];
    pool.velocities[cur] = pool.velocities[last];
    pool.velocities[cur + 1] = pool.velocities[last + 1];
    pool.velocities[cur + 2] = pool.velocities[last + 2];
    pool.colors[cur] = pool.colors[last];
    pool.colors[cur + 1] = pool.colors[last + 1];
    pool.colors[cur + 2] = pool.colors[last + 2];
    pool.sizes[index] = pool.sizes[count - 1];
    pool.baseSizes[index] = pool.baseSizes[count - 1];
    pool.alphas[index] = pool.alphas[count - 1];
    pool.life[index] = pool.life[count - 1];
    pool.maxLife[index] = pool.maxLife[count - 1];
    pool.gravity[index] = pool.gravity[count - 1];
    pool.drag[index] = pool.drag[count - 1];
  }

  #updateMeshPool(pool, dt) {
    let count = pool.count;
    for (let i = count - 1; i >= 0; i--) {
      pool.life[i] -= dt;
      if (pool.life[i] <= 0) {
        this.#killMesh(pool, i, count);
        count--;
        continue;
      }

      const ix = i * 3;
      const damp = Math.max(0, 1 - pool.drag[i] * dt);
      pool.velocities[ix] *= damp;
      pool.velocities[ix + 1] = pool.velocities[ix + 1] * damp - pool.gravity[i] * dt;
      pool.velocities[ix + 2] *= damp;
      pool.positions[ix] += pool.velocities[ix] * dt;
      pool.positions[ix + 1] += pool.velocities[ix + 1] * dt;
      pool.positions[ix + 2] += pool.velocities[ix + 2] * dt;
      pool.rotations[ix] += pool.angular[ix] * dt;
      pool.rotations[ix + 1] += pool.angular[ix + 1] * dt;
      pool.rotations[ix + 2] += pool.angular[ix + 2] * dt;

      if (pool.positions[ix + 1] < 0.025) {
        pool.positions[ix + 1] = 0.025;
        pool.velocities[ix + 1] = -pool.velocities[ix + 1] * pool.bounce;
        pool.velocities[ix] *= 0.72;
        pool.velocities[ix + 2] *= 0.72;
        pool.angular[ix] *= 0.72;
        pool.angular[ix + 1] *= 0.72;
        pool.angular[ix + 2] *= 0.72;
      }

      const t = Math.max(0, pool.life[i] / pool.maxLife[i]);
      const scale = pool.baseSizes[i] * Math.max(0.08, 0.4 + 0.6 * t) * this.particleScale;
      this._dummy.position.set(pool.positions[ix], pool.positions[ix + 1], pool.positions[ix + 2]);
      this._dummy.rotation.set(pool.rotations[ix], pool.rotations[ix + 1], pool.rotations[ix + 2]);
      this._dummy.scale.set(scale, scale, scale);
      this._dummy.updateMatrix();
      pool.mesh.setMatrixAt(i, this._dummy.matrix);
    }

    pool.count = count;
    pool.mesh.count = count;
    pool.mesh.instanceMatrix.needsUpdate = true;
    if (pool.mesh.instanceColor) pool.mesh.instanceColor.needsUpdate = true;
  }

  #killMesh(pool, index, count) {
    if (index === count - 1) return;
    const cur = index * 3;
    const last = (count - 1) * 3;
    pool.positions[cur] = pool.positions[last];
    pool.positions[cur + 1] = pool.positions[last + 1];
    pool.positions[cur + 2] = pool.positions[last + 2];
    pool.velocities[cur] = pool.velocities[last];
    pool.velocities[cur + 1] = pool.velocities[last + 1];
    pool.velocities[cur + 2] = pool.velocities[last + 2];
    pool.rotations[cur] = pool.rotations[last];
    pool.rotations[cur + 1] = pool.rotations[last + 1];
    pool.rotations[cur + 2] = pool.rotations[last + 2];
    pool.angular[cur] = pool.angular[last];
    pool.angular[cur + 1] = pool.angular[last + 1];
    pool.angular[cur + 2] = pool.angular[last + 2];
    pool.sizes[index] = pool.sizes[count - 1];
    pool.baseSizes[index] = pool.baseSizes[count - 1];
    pool.life[index] = pool.life[count - 1];
    pool.maxLife[index] = pool.maxLife[count - 1];
    pool.gravity[index] = pool.gravity[count - 1];
    pool.drag[index] = pool.drag[count - 1];
    pool.colors[index].copy(pool.colors[count - 1]);

    this._dummy.position.set(pool.positions[cur], pool.positions[cur + 1], pool.positions[cur + 2]);
    this._dummy.rotation.set(pool.rotations[cur], pool.rotations[cur + 1], pool.rotations[cur + 2]);
    this._dummy.scale.setScalar(Math.max(0.01, pool.sizes[index] * this.particleScale));
    this._dummy.updateMatrix();
    pool.mesh.setMatrixAt(index, this._dummy.matrix);
    pool.mesh.setColorAt(index, pool.colors[index]);
  }

  #visual(key, t) {
    switch (key) {
      case 'smoke':
        return { size: 0.5 + 1.5 * (1 - t), alpha: t * (0.82 + 0.18 * t) };
      case 'fire':
        return { size: 0.35 + 0.65 * t, alpha: t * (0.55 + 0.45 * t) };
      case 'sparks':
        return { size: 0.35 + 0.65 * t, alpha: t };
      case 'dust':
        return { size: 0.8 + 0.7 * t, alpha: Math.min(1, t * 1.6) };
      case 'muzzle':
        return { size: 0.5 + 0.5 * t, alpha: t * t };
      case 'blood':
        return { size: 0.4 + 0.6 * t, alpha: t };
      default:
        return { size: 0.75 + 0.25 * t, alpha: Math.min(1, t * 2) };
    }
  }

  #copyVec(target, source) {
    if (Array.isArray(source)) {
      target.set(source[0] ?? 0, source[1] ?? 0, source[2] ?? 0);
    } else if (source && typeof source === 'object') {
      target.set(source.x ?? 0, source.y ?? 0, source.z ?? 0);
    } else {
      target.set(0, 0, 0);
    }
    return target;
  }

  #randomDir(target) {
    return target.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize();
  }

  dispose() {
    for (const key of Object.keys(this.points)) {
      const pool = this.points[key];
      this.scene.remove(pool.points);
      pool.geometry.dispose();
      pool.material.dispose();
    }
    for (const key of Object.keys(this.meshPools)) {
      const pool = this.meshPools[key];
      this.scene.remove(pool.mesh);
      pool.geometry.dispose();
      pool.material.dispose();
    }
    this.points = Object.create(null);
    this.meshPools = Object.create(null);
  }
}
