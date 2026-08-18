import * as THREE from 'three';

const TUNING = {
  generic: { fire: '#ffb347', ember: '#ffd166', smoke: '#717574', ring: '#fff0c0', debris: '#5c5147', scale: 1, shake: 1 },
  rocket: { fire: '#ffd27a', ember: '#ffe08a', smoke: '#555b5e', ring: '#ffe9b0', debris: '#4f4740', scale: 1.35, shake: 1.25 },
  grenade: { fire: '#ff8a3c', ember: '#ffb347', smoke: '#6b6f70', ring: '#ffd9a0', debris: '#57504a', scale: 0.85, shake: 0.9 },
  barrel: { fire: '#ff9a3c', ember: '#ffc36b', smoke: '#33383b', ring: '#ffdf9e', debris: '#3f3a35', scale: 1.1, shake: 1.15 },
  explosive: { fire: '#ffb347', ember: '#ffd27a', smoke: '#4c5052', ring: '#fff0b8', debris: '#4b443d', scale: 1.25, shake: 1.2 },
};

const rand = (min = 0, max = 1) => min + Math.random() * (max - min);

export class ExplosionSystem {
  constructor(scene, physics, events, particles, quality = {}, terrain = null) {
    this.scene = scene;
    this.physics = physics;
    this.events = events;
    this.particles = particles;
    this.quality = quality;
    this.terrain = terrain?.heightAt ? terrain : quality?.heightAt ? quality : scene?.userData?.terrain || null;
    this.particleScale = Math.max(0.2, quality.particleScale ?? 1);
    this.decalLimit = Math.max(8, quality.decalLimit ?? 80);
    this._maxExplosions = Math.max(4, Math.round((quality.explosionLimit ?? 16) * Math.max(0.6, Math.min(1.2, this.particleScale))));
    this._explosions = [];
    this._scorches = [];
    this._ringGeometry = new THREE.RingGeometry(0.86, 1, 64);
    this._scorchGeometry = new THREE.CircleGeometry(1, 32);
    this._up = new THREE.Vector3(0, 1, 0);
    this._surfaceNormal = new THREE.Vector3(0, 1, 0);
  }

  explode(position, radius = 5, power = 10, type = 'generic') {
    const pos = this.#toVector3(position);
    const tuning = TUNING[type] || TUNING.generic;
    const effRadius = Math.max(0.5, radius * tuning.scale);
    const effPower = Math.max(0.5, power * tuning.scale);
    const intensity = Math.max(0, Math.min(1, effPower / Math.max(1, effRadius * 2.2)));
    const scale = this.particleScale;

    this.particles.burst({
      position: pos,
      count: Math.round((34 + 78 * intensity) * scale),
      color: ['#ffe08a', tuning.fire, '#ff7b2d'],
      size: effRadius * 0.42,
      life: 0.55 + 0.45 * intensity,
      velocity: { x: 0, y: 2.4, z: 0 },
      type: 'fire',
      gravity: 0.9,
      drag: 1.7,
    });

    this.particles.burst({
      position: pos,
      count: Math.round((22 + 34 * intensity) * scale),
      color: [tuning.ember, '#ff9f43', '#ff6b35'],
      size: 0.2,
      life: 1.35,
      velocity: { x: 0, y: 4.2, z: 0 },
      type: 'sparks',
      gravity: 5.5,
      drag: 0.5,
    });

    this.particles.burst({
      position: pos,
      count: Math.round((14 + 26 * intensity) * scale),
      color: tuning.smoke,
      size: effRadius * 0.62,
      life: 2.5,
      velocity: { x: 0, y: 2.2, z: 0 },
      type: 'smoke',
      gravity: 0.3,
      drag: 1.35,
    });

    this.particles.burst({
      position: pos,
      count: Math.round((8 + 16 * intensity) * scale),
      color: [tuning.debris, '#6d6255', '#3f3831'],
      size: 0.1,
      life: 1.9,
      velocity: { x: 0, y: 6.5, z: 0 },
      type: 'debris',
      gravity: 16.5,
      drag: 0.4,
    });

    const smokeRing = this.#makeRing(
      pos,
      '#777c7d',
      effRadius * 0.55,
      effRadius * (1.75 + intensity * 0.8),
      2.4,
      0.34,
      false,
      0.38
    );
    const shockwave = this.#makeRing(
      pos,
      tuning.ring,
      effRadius * 0.42,
      effRadius * (1.5 + intensity * 0.7),
      0.62,
      0.85,
      true,
      0.16
    );

    const light = new THREE.PointLight(tuning.fire, Math.min(30, effPower * (2.2 + intensity * 2)), effRadius * 6, 2);
    light.position.copy(pos);
    light.position.y += Math.max(0.5, effRadius * 0.24);
    this.scene.add(light);

    const record = {
      elapsed: 0,
      duration: 2.7,
      pos,
      radius: effRadius,
      power: effPower,
      light,
      lightBase: light.intensity,
      rings: [smokeRing, shockwave],
    };
    record.scorch = this.#addScorch(pos, effRadius);
    this._explosions.push(record);
    if (this._explosions.length > this._maxExplosions) {
      const oldest = this._explosions.shift();
      this.#disposeExplosion(oldest);
    }

    const camera = this.#findCamera();
    const distance = camera?.position ? camera.position.distanceTo(pos) : 0;
    let shake = 0;
    if (camera) {
      shake = Math.max(0, 1 - distance / Math.max(effRadius * 8, 1)) * Math.min(1, effPower / 22) * tuning.shake;
    } else {
      shake = Math.min(0.75, 0.2 + intensity * 0.5) * tuning.shake;
    }
    if (shake > 0.01) this.events.emit('camera:shake', { amount: shake });
    this.events.emit('sfx:explosion', { distance, radius: effRadius, power: effPower, type });
  }

  update(dt = 0) {
    const delta = Math.min(Math.max(0, dt), 0.05);
    if (delta <= 0) return;

    for (let i = this._explosions.length - 1; i >= 0; i--) {
      const record = this._explosions[i];
      record.elapsed += delta;
      const p = Math.min(1, record.elapsed / record.duration);
      record.light.intensity = Math.max(0, record.lightBase * (1 - p) * (1 - p));

      for (let r = record.rings.length - 1; r >= 0; r--) {
        const ring = record.rings[r];
        ring.elapsed += delta;
        const ringP = Math.min(1, ring.elapsed / ring.duration);
        const ease = 1 - Math.pow(1 - ringP, 3);
        const ringScale = ring.startScale + (ring.endScale - ring.startScale) * ease;
        ring.mesh.scale.set(ringScale, ringScale, ringScale);
        const fade = ringP < 0.18 ? ringP / 0.18 : Math.max(0, 1 - (ringP - 0.18) / 0.82);
        ring.material.opacity = ring.peakOpacity * fade;
        if (ring.elapsed >= ring.duration + 0.08) {
          this.#disposeRing(ring);
          record.rings.splice(r, 1);
        }
      }

      if (record.elapsed >= record.duration + 0.1) {
        this.#disposeExplosion(record);
        this._explosions.splice(i, 1);
      }
    }

    for (let i = this._scorches.length - 1; i >= 0; i--) {
      const scorch = this._scorches[i];
      scorch.elapsed += delta;
      if (scorch.elapsed < 0.25) {
        scorch.material.opacity = scorch.opacity * (scorch.elapsed / 0.25);
      } else if (scorch.life - scorch.elapsed < 1.4) {
        scorch.material.opacity = scorch.opacity * Math.max(0, (scorch.life - scorch.elapsed) / 1.4);
      } else {
        scorch.material.opacity = scorch.opacity;
      }
      if (scorch.elapsed >= scorch.life) {
        this.#removeScorch(scorch);
        this._scorches.splice(i, 1);
      }
    }
  }

  #surfaceAt(position) {
    const normal = this._surfaceNormal.set(0, 1, 0);
    let y = position.y;
    const terrain = this.terrain;
    if (terrain && typeof terrain.heightAt === 'function') {
      const x = position.x;
      const z = position.z;
      const centerHeight = terrain.heightAt(x, z);
      if (Number.isFinite(centerHeight)) y = centerHeight;

      if (typeof terrain.normalAt === 'function') {
        const sampled = terrain.normalAt(x, z);
        if (sampled && Number.isFinite(sampled.x) && Number.isFinite(sampled.y) && Number.isFinite(sampled.z)) {
          normal.copy(sampled).normalize();
        }
      } else {
        const e = 0.45;
        const left = terrain.heightAt(x - e, z);
        const right = terrain.heightAt(x + e, z);
        const down = terrain.heightAt(x, z - e);
        const up = terrain.heightAt(x, z + e);
        if ([left, right, down, up].every(Number.isFinite)) {
          normal.set(-(right - left) / (2 * e), 1, -(up - down) / (2 * e)).normalize();
        }
      }
    }
    return { y, normal };
  }

  #makeRing(position, color, startScale, endScale, duration, peakOpacity, additive, yOffset) {
    const material = new THREE.MeshBasicMaterial({
      color,
      transparent: true,
      opacity: 0,
      side: THREE.DoubleSide,
      depthWrite: false,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    const mesh = new THREE.Mesh(this._ringGeometry, material);
    const surface = this.#surfaceAt(position);
    mesh.position.set(position.x, surface.y + yOffset, position.z);
    mesh.quaternion.setFromUnitVectors(this._up, surface.normal);
    mesh.scale.setScalar(Math.max(0.01, startScale));
    this.scene.add(mesh);
    return {
      mesh,
      material,
      elapsed: 0,
      duration,
      startScale,
      endScale,
      peakOpacity,
    };
  }

  #addScorch(position, radius) {
    if (this._scorches.length >= this.decalLimit) {
      const oldest = this._scorches.shift();
      this.#removeScorch(oldest);
    }
    const material = new THREE.MeshBasicMaterial({
      color: 0x070707,
      transparent: true,
      opacity: 0,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -2,
      polygonOffsetUnits: -2,
    });
    const mesh = new THREE.Mesh(this._scorchGeometry, material);
    const surface = this.#surfaceAt(position);
    mesh.position.set(position.x, surface.y + 0.03, position.z);
    mesh.quaternion.setFromUnitVectors(this._up, surface.normal);
    mesh.scale.setScalar(radius * 1.18);
    this.scene.add(mesh);
    const scorch = {
      mesh,
      material,
      elapsed: 0,
      life: 8 + rand(0, 3),
      opacity: Math.min(0.72, 0.38 + radius * 0.05),
    };
    this._scorches.push(scorch);
    return scorch;
  }

  #disposeRing(ring) {
    this.scene.remove(ring.mesh);
    ring.material.dispose();
  }

  #disposeExplosion(record) {
    for (const ring of record.rings) this.#disposeRing(ring);
    this.scene.remove(record.light);
  }

  #removeScorch(scorch) {
    this.scene.remove(scorch.mesh);
    scorch.material.dispose();
  }

  #findCamera() {
    return this.scene?.userData?.camera || this.scene?.userData?.mainCamera || this.scene?.camera || null;
  }

  #toVector3(value) {
    if (value instanceof THREE.Vector3) return value;
    if (Array.isArray(value)) return new THREE.Vector3(value[0] ?? 0, value[1] ?? 0, value[2] ?? 0);
    return new THREE.Vector3(value?.x ?? 0, value?.y ?? 0, value?.z ?? 0);
  }

  dispose() {
    for (const record of this._explosions) this.#disposeExplosion(record);
    for (const scorch of this._scorches) this.#removeScorch(scorch);
    this._explosions.length = 0;
    this._scorches.length = 0;
    this._ringGeometry.dispose();
    this._scorchGeometry.dispose();
  }
}
