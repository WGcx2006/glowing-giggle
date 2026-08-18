import * as THREE from 'three';
import { GRAVITY } from '../core/Physics.js';

const _UP = new THREE.Vector3(0, 1, 0);
const _Z = new THREE.Vector3(0, 0, 1);
const _origin = new THREE.Vector3();
const _dir = new THREE.Vector3();
const _step = new THREE.Vector3();
const _mid = new THREE.Vector3();
const _end = new THREE.Vector3();
const _hitNormal = new THREE.Vector3(0, 1, 0);
const _quat = new THREE.Quaternion();
const _euler = new THREE.Euler();

const TRACER_POOL_SIZE = 64;

export class ProjectileSystem {
  constructor(scene, physics, events, particles, explosions, quality = {}, options = {}) {
    this.scene = scene;
    this.physics = physics;
    this.events = events;
    this.particles = particles;
    this.explosions = explosions;
    this.quality = quality;
    this.terrain = options.terrain ?? scene?.userData?.terrain ?? null;
    this.tracers = [];
    this.projectiles = [];
    this.decals = [];
    this.decalLimit = quality.decalLimit ?? 80;
    this.impactTexture = this.#createImpactTexture();
    this.tracerPool = [];
    this.tracerFree = [];
    this.tracerGlowGeometry = new THREE.CylinderGeometry(0.014, 0.014, 1, 5, 1, true);
    this.decalGeometry = new THREE.PlaneGeometry(0.16, 0.16);
    this.decalPool = [];
    this.decalFree = [];
  }

  fireHitScan(origin, direction, damage = 20, tracerColor = '#ffd27a', weaponType = 'assault', source = null) {
    const resolvedSource = source ?? (
      weaponType === 'enemy' ? 'red'
        : weaponType === 'blue' ? 'blue'
          : 'player'
    );
    _origin.copy(origin);
    _dir.copy(direction).normalize();
    if (_dir.lengthSq() < 0.5) _dir.set(0, 0, -1);

    const ignoreNearOrigin = (candidate) => this.#isShooterSphere(candidate, resolvedSource);
    const hit = this.physics.raycast(_origin, _dir, 500, {
      ignore: ignoreNearOrigin,
      terrain: this.terrain,
    });
    let end;

    if (hit) {
      _end.copy(hit.point);
      _hitNormal.copy(hit.normal ?? _UP);
      const entity = hit.object?.userData?.entity;
      if (entity !== undefined && entity !== null) {
        this.events.emit('damage:target', {
          target: entity,
          amount: damage,
          point: hit.point.clone(),
          source: resolvedSource,
        });
      }
      if (hit.type === 'box' && hit.object.destructible) {
        this.physics.damageBox(hit.object, damage);
      }
      this.particles?.sparks?.(_end, _hitNormal);
      this.particles?.dust?.(_end);
      this.#spawnDecal(_end, _hitNormal);
    } else {
      _end.copy(_origin).addScaledVector(_dir, 500);
    }

    this.#spawnTracer(_origin, _end, tracerColor);
  }

  spawnRocket(origin, direction, source = 'player') {
    const dir = direction.clone().normalize();
    const mesh = this.#buildRocketMesh();
    mesh.position.copy(origin);
    mesh.quaternion.setFromUnitVectors(_UP, dir);
    this.scene.add(mesh);
    this.projectiles.push({
      kind: 'rocket',
      mesh,
      position: origin.clone(),
      velocity: dir.clone().multiplyScalar(32),
      gravity: 0.6,
      life: 0,
      alive: true,
      radius: 7,
      power: 95,
      type: 'rocket',
      source,
    });
  }

  spawnGrenade(origin, direction, source = 'player') {
    const dir = direction.clone().normalize();
    const mesh = this.#buildGrenadeMesh();
    mesh.position.copy(origin);
    this.scene.add(mesh);
    const velocity = dir.clone().multiplyScalar(13);
    velocity.y += 5;
    this.projectiles.push({
      kind: 'grenade',
      mesh,
      position: origin.clone(),
      velocity,
      fuse: 2.8,
      life: 0,
      alive: true,
      radius: 8,
      power: 80,
      type: 'grenade',
      source,
      entityHit: false,
      bounces: 0,
    });
  }

  update(dt = 0) {
    const t = Math.max(0, Math.min(dt, 0.05));

    for (let i = this.tracers.length - 1; i >= 0; i--) {
      const tracer = this.tracers[i];
      tracer.life -= t;
      const opacity = Math.max(0, tracer.life / tracer.maxLife);
      tracer.line.material.opacity = opacity;
      tracer.glow.material.opacity = opacity * 0.55;
      if (tracer.life <= 0) {
        this.scene.remove(tracer.line, tracer.glow);
        tracer.active = false;
        this.tracerFree.push(tracer);
        this.tracers.splice(i, 1);
      }
    }

    for (const projectile of this.projectiles) {
      if (!projectile.alive) continue;
      if (projectile.kind === 'rocket') this.#updateRocket(projectile, t);
      else this.#updateGrenade(projectile, t);
    }
    this.projectiles = this.projectiles.filter((projectile) => projectile.alive);

    for (let i = this.decals.length - 1; i >= 0; i--) {
      const decal = this.decals[i];
      decal.age += t;
      const fade = Math.max(0, Math.min(1, (decal.life - decal.age) / 2));
      decal.material.opacity = 0.72 * fade;
      if (decal.age >= decal.life) {
        this.scene.remove(decal.mesh);
        decal.active = false;
        this.decalFree.push(decal);
        this.decals.splice(i, 1);
      }
    }
  }

  #updateRocket(projectile, dt) {
    const prev = projectile.position.clone();
    projectile.position.addScaledVector(projectile.velocity, dt);
    projectile.velocity.y -= projectile.gravity * dt;
    _step.copy(projectile.position).sub(prev);
    const distance = _step.length();

    if (distance > 0.0001) {
      const ignoreNearOrigin = (candidate) => this.#isShooterSphere(candidate, projectile.source);
      const hit = this.physics.raycast(prev, _step.normalize(), distance + 0.02, {
        ignore: ignoreNearOrigin,
        terrain: this.terrain,
      });
      if (hit && hit.distance <= distance) {
        this.#detonate(projectile, hit.point.clone(), hit.object?.userData?.entity, 'rocket');
        return;
      }
    }

    projectile.mesh.position.copy(projectile.position);
    if (projectile.velocity.lengthSq() > 0.0001) {
      projectile.mesh.quaternion.setFromUnitVectors(_UP, projectile.velocity.clone().normalize());
    }
    projectile.life += dt;
    if (projectile.life > 7) {
      this.#detonate(projectile, projectile.position.clone(), null, 'rocket');
    }
  }

  #updateGrenade(projectile, dt) {
    projectile.life += dt;
    if (projectile.life >= projectile.fuse) {
      this.#detonate(projectile, projectile.position.clone(), null, 'grenade');
      return;
    }

    const substeps = 2;
    const subDt = dt / substeps;
    for (let i = 0; i < substeps; i++) {
      const prev = projectile.position.clone();
      projectile.velocity.y -= GRAVITY * subDt;
      projectile.position.addScaledVector(projectile.velocity, subDt);
      _step.copy(projectile.position).sub(prev);
      const distance = _step.length();

      if (distance > 0.0001) {
        const ignoreNearOrigin = (candidate) => this.#isShooterSphere(candidate, projectile.source);
        const hit = this.physics.raycast(prev, _step.normalize(), distance + 0.02, {
          ignore: ignoreNearOrigin,
          terrain: this.terrain,
        });
        if (hit && hit.distance <= distance + 0.001) {
          const entity = hit.object?.userData?.entity;
          if (entity !== undefined && entity !== null && !projectile.entityHit) {
            projectile.entityHit = true;
            this.events.emit('damage:target', {
              target: entity,
              amount: 8,
              point: hit.point.clone(),
              source: projectile.source ?? 'grenade',
            });
          }
          const normal = hit.normal ?? _UP;
          projectile.position.copy(hit.point).addScaledVector(normal, 0.02);
          projectile.velocity.reflect(normal).multiplyScalar(0.48);
          projectile.velocity.x *= 0.8;
          projectile.velocity.z *= 0.8;
          projectile.bounces++;
          if (projectile.velocity.lengthSq() < 0.4) projectile.velocity.set(0, 0, 0);
        }
      }

      const groundY = this.#terrainHeight(projectile.position.x, projectile.position.z);
      if (projectile.position.y < groundY + 0.02) {
        projectile.position.y = groundY + 0.02;
        if (projectile.velocity.y < 0) projectile.velocity.y *= -0.42;
        projectile.velocity.x *= 0.82;
        projectile.velocity.z *= 0.82;
      }
    }

    projectile.mesh.position.copy(projectile.position);
  }

  #detonate(projectile, point, directTarget, type) {
    if (!projectile.alive) return;
    projectile.alive = false;
    if (directTarget !== undefined && directTarget !== null) {
      this.events.emit('damage:target', {
        target: directTarget,
        amount: type === 'rocket' ? 45 : 12,
        point: point.clone(),
        source: projectile.source ?? type,
      });
    }
    this.events.emit('explosion:detonated', {
      position: point.clone(),
      radius: projectile.radius,
      power: projectile.power,
      type,
      source: projectile.source ?? type,
    });
    this.particles?.smoke?.(point, '#3a342c');
    this.particles?.sparks?.(point, _UP);
    this.#removeProjectile(projectile);
  }

  #removeProjectile(projectile) {
    this.scene.remove(projectile.mesh);
    projectile.mesh.traverse((object) => {
      if (object.geometry) object.geometry.dispose();
      if (!object.material) return;
      const materials = Array.isArray(object.material) ? object.material : [object.material];
      for (const material of materials) material.dispose();
    });
    projectile.alive = false;
  }

  #spawnTracer(start, end, color) {
    const length = Math.max(0.08, start.distanceTo(end));
    _dir.copy(end).sub(start).normalize();
    _mid.copy(start).add(end).multiplyScalar(0.5);

    let tracer = this.tracerFree.pop();
    if (!tracer) {
      if (this.tracerPool.length >= TRACER_POOL_SIZE) {
        tracer = this.tracers.shift();
        this.scene.remove(tracer.line, tracer.glow);
      } else {
        tracer = this.#createTracerEntry();
      }
    }
    if (!tracer) return;

    const positions = tracer.line.geometry.attributes.position.array;
    positions[0] = start.x;
    positions[1] = start.y;
    positions[2] = start.z;
    positions[3] = end.x;
    positions[4] = end.y;
    positions[5] = end.z;
    tracer.line.geometry.attributes.position.needsUpdate = true;
    tracer.line.material.color.set(color);
    tracer.line.material.opacity = 0.9;
    tracer.glow.material.color.set(color);
    tracer.glow.material.opacity = 0.45;
    tracer.glow.position.copy(_mid);
    tracer.glow.scale.set(1, length, 1);
    tracer.glow.quaternion.setFromUnitVectors(_UP, _dir);
    this.scene.add(tracer.line, tracer.glow);
    tracer.life = 0.085;
    tracer.maxLife = 0.085;
    tracer.active = true;
    this.tracers.push(tracer);
  }

  #createTracerEntry() {
    const lineGeometry = new THREE.BufferGeometry();
    lineGeometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(6), 3));
    const lineMaterial = new THREE.LineBasicMaterial({
      color: '#ffd27a',
      transparent: true,
      opacity: 0.9,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    const line = new THREE.Line(lineGeometry, lineMaterial);
    line.frustumCulled = false;
    const glowMaterial = new THREE.MeshBasicMaterial({
      color: '#ffd27a',
      transparent: true,
      opacity: 0.45,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      side: THREE.DoubleSide,
    });
    const glow = new THREE.Mesh(this.tracerGlowGeometry, glowMaterial);
    glow.frustumCulled = false;
    const tracer = { line, glow, life: 0, maxLife: 0, active: false };
    this.tracerPool.push(tracer);
    return tracer;
  }

  #spawnDecal(point, normal) {
    if (this.decalLimit <= 0) return;
    let entry;
    if (this.decals.length >= this.decalLimit) {
      entry = this.decals.shift();
      this.scene.remove(entry.mesh);
      entry.active = false;
    } else {
      entry = this.decalFree.pop();
      if (!entry) entry = this.#createDecalEntry();
    }
    if (!entry) return;

    entry.mesh.position.copy(point).addScaledVector(normal, 0.006);
    _quat.setFromUnitVectors(_Z, normal);
    _euler.setFromQuaternion(_quat);
    _euler.z += Math.random() * Math.PI * 2;
    entry.mesh.quaternion.setFromEuler(_euler);
    entry.material.opacity = 0.72;
    entry.age = 0;
    entry.life = 10;
    entry.active = true;
    this.scene.add(entry.mesh);
    this.decals.push(entry);
  }

  #createDecalEntry() {
    const material = new THREE.MeshBasicMaterial({
      color: 0x0b0d10,
      transparent: true,
      opacity: 0.72,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -2,
      map: this.impactTexture || null,
    });
    const mesh = new THREE.Mesh(this.decalGeometry, material);
    const entry = { mesh, material, age: 0, life: 10, active: false };
    this.decalPool.push(entry);
    return entry;
  }

  #isShooterSphere(candidate, source) {
    if (candidate.type !== 'sphere') return false;
    const entity = candidate.object?.userData?.entity;
    return entity === source || candidate.object === source;
  }

  #terrainHeight(x, z) {
    const terrain = this.terrain;
    if (typeof terrain?.heightAt === 'function') return terrain.heightAt(x, z);
    if (typeof terrain?.sampleHeight === 'function') return terrain.sampleHeight(x, z);
    return 0;
  }

  #createImpactTexture() {
    if (typeof document === 'undefined') return null;
    const size = 64;
    const canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;
    const context = canvas.getContext('2d');
    const gradient = context.createRadialGradient(size / 2, size / 2, 2, size / 2, size / 2, size / 2);
    gradient.addColorStop(0, 'rgba(18,22,26,1)');
    gradient.addColorStop(0.7, 'rgba(30,34,38,0.9)');
    gradient.addColorStop(1, 'rgba(30,34,38,0)');
    context.fillStyle = gradient;
    context.fillRect(0, 0, size, size);
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    return texture;
  }

  #buildRocketMesh() {
    const group = new THREE.Group();
    const bodyMaterial = new THREE.MeshStandardMaterial({ color: 0x343a31, roughness: 0.5, metalness: 0.6 });
    const noseMaterial = new THREE.MeshStandardMaterial({ color: 0x9a3f2b, roughness: 0.45, metalness: 0.25 });
    const finMaterial = new THREE.MeshStandardMaterial({ color: 0x1d2226, roughness: 0.6, metalness: 0.4 });
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.045, 0.6, 8), bodyMaterial);
    const nose = new THREE.Mesh(new THREE.ConeGeometry(0.045, 0.16, 8), noseMaterial);
    nose.position.y = 0.38;
    group.add(body, nose);
    for (let i = 0; i < 4; i++) {
      const fin = new THREE.Mesh(new THREE.BoxGeometry(0.018, 0.16, 0.12), finMaterial);
      const angle = (i / 4) * Math.PI * 2;
      fin.position.set(Math.cos(angle) * 0.055, -0.22, Math.sin(angle) * 0.055);
      fin.rotation.y = -angle;
      group.add(fin);
    }
    return group;
  }

  #buildGrenadeMesh() {
    const group = new THREE.Group();
    const bodyMaterial = new THREE.MeshStandardMaterial({ color: 0x35432f, roughness: 0.82, metalness: 0.05 });
    const handleMaterial = new THREE.MeshStandardMaterial({ color: 0x6b4b2a, roughness: 0.9, metalness: 0.05 });
    const body = new THREE.Mesh(new THREE.SphereGeometry(0.075, 10, 8), bodyMaterial);
    const handle = new THREE.Mesh(new THREE.BoxGeometry(0.035, 0.09, 0.035), handleMaterial);
    handle.position.y = 0.06;
    group.add(body, handle);
    return group;
  }
}
