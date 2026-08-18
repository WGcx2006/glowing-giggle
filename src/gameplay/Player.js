import * as THREE from 'three';

const _forward = new THREE.Vector3();
const _right = new THREE.Vector3();
const _wish = new THREE.Vector3();
const _dir = new THREE.Vector3();
const _delta = new THREE.Vector3();
const _fallbackDir = new THREE.Vector3(0, 0, 1);

export class PlayerController {
  constructor(camera, scene, physics, events, terrain, quality = {}) {
    this.camera = camera;
    this.scene = scene;
    this.physics = physics;
    this.events = events;
    this.terrain = terrain;
    this.quality = quality;

    this.position = new THREE.Vector3(0, 1.7, 8);
    this.velocity = new THREE.Vector3();
    this.yaw = 0;
    this.pitch = 0;
    this.health = 100;
    this.maxHealth = 100;
    this.armor = 50;
    this.maxArmor = 50;
    this.alive = true;
    this.grounded = false;
    this.crouching = false;
    this.sprinting = false;
    this.zooming = false;
    this.sensitivityScale = 1;
    this.gravity = 12;
    this.eyeHeight = 1.7;
    this.radius = 0.45;
    this.spawnPoint = new THREE.Vector3(0, 1.7, 8);

    this.bobPhase = 0;
    this.bobX = 0;
    this.bobY = 0;
    this.swayX = 0;
    this.swayY = 0;
    this.mouseSmoothX = 0;
    this.mouseSmoothY = 0;
    this.recoilPitch = 0;
    this.recoilYaw = 0;
    this.landKick = 0;
    this.shake = 0;
    this.damagePulse = 0;
    this.damageKick = new THREE.Vector3();
    this.lastFallSpeed = 0;

    this.physicsSphere = this.physics.addSphere('player', this.#bodyPosition(), this.radius, {
      static: false,
      userData: { entity: 'player' },
    });

    this._onDamageTarget = (payload) => {
      if (payload?.target === 'player' && this.alive) {
        let direction = null;
        if (payload.point) {
          _dir.copy(payload.point).sub(this.position);
          if (_dir.lengthSq() > 1e-6) direction = _dir;
        }
        this.damage(payload.amount, direction);
      }
    };
    this._onExplosion = (payload) => this.#applyExplosion(payload);
    this.events.on('damage:target', this._onDamageTarget);
    this.events.on('explosion:detonated', this._onExplosion);

    this.events.emit('player:health', { health: this.health, maxHealth: this.maxHealth });
  }

  update(dt = 0, input = {}) {
    const t = Math.max(0.0001, Math.min(dt, 0.05));
    const keys = input.keys || new Set();
    const mouseDX = input.mouseDX ?? 0;
    const mouseDY = input.mouseDY ?? 0;

    if (this.alive) {
      this.crouching = keys.has('ControlLeft') || keys.has('ControlRight');
      const targetEye = this.crouching ? 1.2 : 1.7;
      this.eyeHeight += (targetEye - this.eyeHeight) * Math.min(1, t * 10);

      const sensitivity = 0.0013 * this.sensitivityScale * (this.zooming ? 0.55 : 1);
      const mouseSmoothing = 1 - Math.exp(-14 * t);
      this.mouseSmoothX += mouseDX;
      this.mouseSmoothY += mouseDY;
      const appliedX = this.mouseSmoothX * mouseSmoothing;
      const appliedY = this.mouseSmoothY * mouseSmoothing;
      this.yaw -= appliedX * sensitivity;
      this.pitch -= appliedY * sensitivity;
      this.mouseSmoothX -= appliedX;
      this.mouseSmoothY -= appliedY;
      this.pitch = Math.max(-1.5, Math.min(1.5, this.pitch));
    } else {
      this.velocity.x *= Math.max(0, 1 - t * 8);
      this.velocity.z *= Math.max(0, 1 - t * 8);
      this.pitch += t * 0.9;
    }

    const moving = this.#updateMovement(t, keys);
    this.#updateBobAndSway(t, moving, mouseDX, mouseDY);
    this.#updateCamera(t);
  }

  #updateMovement(dt, keys) {
    if (!this.alive) {
      this.velocity.y -= this.gravity * dt;
      this.velocity.y = Math.max(this.velocity.y, -40);
      this.#integrate(dt);
      return false;
    }

    const forward = (keys.has('KeyW') ? 1 : 0) - (keys.has('KeyS') ? 1 : 0);
    const strafe = (keys.has('KeyD') ? 1 : 0) - (keys.has('KeyA') ? 1 : 0);
    _forward.set(-Math.sin(this.yaw), 0, -Math.cos(this.yaw));
    _right.set(Math.cos(this.yaw), 0, -Math.sin(this.yaw));
    _wish.set(0, 0, 0).addScaledVector(_forward, forward).addScaledVector(_right, strafe);
    const inputMagnitude = _wish.length();
    if (inputMagnitude > 0.001) _wish.divideScalar(inputMagnitude);

    this.sprinting = keys.has('ShiftLeft') && forward > 0 && !this.crouching;
    const speed = this.crouching ? 2.4 : this.sprinting ? 8.2 : 5.6;
    _wish.multiplyScalar(speed);
    const hasInput = inputMagnitude > 0.001;
    const controlRate = this.grounded ? (hasInput ? 14 : 16) : 6;
    const blend = Math.min(1, controlRate * dt);
    this.velocity.x += (_wish.x - this.velocity.x) * blend;
    this.velocity.z += (_wish.z - this.velocity.z) * blend;

    this.velocity.y -= this.gravity * dt;
    this.velocity.y = Math.max(this.velocity.y, -40);

    if (keys.has('Space') && this.grounded) {
      this.velocity.y = 6.0;
      this.grounded = false;
    }

    this.#integrate(dt);
    return inputMagnitude > 0.01;
  }

  #integrate(dt) {
    const fallSpeedBefore = this.velocity.y;
    const wasAirborne = !this.grounded;
    _delta.copy(this.velocity).multiplyScalar(dt);
    const result = this.physics.moveSphere(this.physicsSphere, _delta);

    const groundY = this.terrain?.heightAt?.(
      this.physicsSphere.center.x,
      this.physicsSphere.center.z
    ) ?? 0;
    const minBodyY = groundY + this.radius;
    let landed = false;

    if (this.physicsSphere.center.y <= minBodyY + 1e-3) {
      this.physicsSphere.center.y = minBodyY;
      this.grounded = true;
      if (this.velocity.y < 0) {
        this.lastFallSpeed = Math.max(this.lastFallSpeed, -this.velocity.y);
        landed = true;
      }
    } else {
      this.grounded = result.grounded;
    }

    if (this.grounded && this.velocity.y < 0) {
      if (wasAirborne) this.lastFallSpeed = Math.max(this.lastFallSpeed, -fallSpeedBefore);
      this.velocity.y = 0;
    }

    if (wasAirborne && landed && this.lastFallSpeed > 7) {
      this.landKick = Math.min(0.7, this.lastFallSpeed * 0.05);
      this.shake = Math.max(this.shake, Math.min(0.4, this.lastFallSpeed * 0.025));
    }
    if (this.grounded) this.lastFallSpeed = Math.max(0, this.lastFallSpeed - this.lastFallSpeed * dt * 4);
    else this.lastFallSpeed = 0;

    this.position.set(
      this.physicsSphere.center.x,
      this.physicsSphere.center.y + (this.eyeHeight - this.radius),
      this.physicsSphere.center.z
    );
  }

  #updateBobAndSway(dt, moving, mouseDX, mouseDY) {
    const horizontalSpeed = Math.hypot(this.velocity.x, this.velocity.z);
    const bobAmp = (this.crouching ? 0.010 : this.sprinting ? 0.036 : 0.024)
      * (this.zooming ? 0.3 : 1);

    if (this.alive && this.grounded && horizontalSpeed > 0.5) {
      this.bobPhase += dt * (this.sprinting ? 12.5 : 8.5);
      this.bobX = Math.sin(this.bobPhase) * bobAmp * 0.55;
      this.bobY = Math.abs(Math.cos(this.bobPhase)) * bobAmp;
    } else {
      this.bobX *= Math.max(0, 1 - dt * 8);
      this.bobY *= Math.max(0, 1 - dt * 8);
    }

    const swayTargetX = Math.max(-0.03, Math.min(0.03, mouseDX * 0.00009))
      + (moving ? Math.sin(this.bobPhase) * 0.006 : 0);
    const swayTargetY = Math.max(-0.03, Math.min(0.03, mouseDY * 0.00009));
    this.swayX += (swayTargetX - this.swayX) * Math.min(1, dt * 9);
    this.swayY += (swayTargetY - this.swayY) * Math.min(1, dt * 9);
  }

  #updateCamera(dt) {
    const adsScale = this.zooming ? 0.5 : 1;
    const roll = (Math.sin(this.bobPhase * 0.5) * this.bobX * 0.18
      + this.damagePulse * 0.03
      + this.landKick * 0.08) * adsScale;
    this.camera.rotation.set(
      this.pitch + this.recoilPitch,
      this.yaw + this.recoilYaw,
      roll
    );

    const shakeX = (Math.random() - 0.5) * this.shake * 0.04 * adsScale;
    const shakeY = (Math.random() - 0.5) * this.shake * 0.04 * adsScale;
    const kickX = this.damageKick.x * this.damagePulse * 0.1;
    const kickY = this.damageKick.y * this.damagePulse * 0.1;
    this.camera.position.set(
      this.position.x + this.bobX + kickX + shakeX,
      this.position.y + this.bobY + kickY + shakeY,
      this.position.z
    );

    this.recoilPitch *= Math.exp(-10 * dt);
    this.recoilYaw *= Math.exp(-10 * dt);
    this.shake *= Math.max(0, 1 - dt * 6.5);
    this.damagePulse *= Math.max(0, 1 - dt * 4);
    this.landKick *= Math.max(0, 1 - dt * 7);
  }

  #applyExplosion(payload) {
    if (!this.alive || !payload || !payload.position || !payload.radius || payload.power <= 0) return;
    _dir.copy(this.position).sub(payload.position);
    const distance = _dir.length();
    if (distance > payload.radius) return;
    const falloff = 1 - Math.max(0, distance / payload.radius);
    const damage = payload.power * falloff * (payload.type === 'grenade' ? 0.9 : 1);
    const direction = distance > 0.001 ? _dir.normalize() : _fallbackDir;
    this.damage(damage, direction);
    this.velocity.addScaledVector(direction, Math.min(9, payload.power * falloff * 0.09));
  }

  damage(amount, direction = null) {
    if (!this.alive || amount <= 0) return;
    const dir = direction ? direction.clone().normalize() : _fallbackDir.clone();
    const absorbed = Math.min(this.armor, amount * 0.5);
    this.armor -= absorbed;
    const actual = Math.max(0, amount - absorbed);
    this.health = Math.max(0, this.health - actual);

    this.damagePulse = Math.min(1, actual / 45);
    this.shake = Math.max(this.shake, this.damagePulse * 0.55);
    this.damageKick.copy(dir).multiplyScalar(this.damagePulse);

    this.events.emit('player:health', { health: this.health, maxHealth: this.maxHealth });
    this.events.emit('player:damage', { amount: actual, direction: dir });

    if (this.health <= 0 && this.alive) {
      this.alive = false;
      this.velocity.set(0, 0, 0);
      this.events.emit('player:death', {});
    }
  }

  respawn() {
    this.health = this.maxHealth;
    this.armor = this.maxArmor;
    this.alive = true;
    this.velocity.set(0, 0, 0);
    this.position.copy(this.spawnPoint);
    this.eyeHeight = 1.7;
    this.pitch = 0;
    this.yaw = 0;
    this.bobPhase = 0;
    this.bobX = 0;
    this.bobY = 0;
    this.swayX = 0;
    this.swayY = 0;
    this.mouseSmoothX = 0;
    this.mouseSmoothY = 0;
    this.recoilPitch = 0;
    this.recoilYaw = 0;
    this.landKick = 0;
    this.shake = 0;
    this.damagePulse = 0;

    const groundY = this.terrain?.heightAt?.(this.position.x, this.position.z) ?? 0;
    this.position.y = groundY + 1.7;
    this.physicsSphere.center.copy(this.#bodyPosition());
    this.camera.position.copy(this.position);
    this.camera.rotation.set(0, 0, 0);

    this.events.emit('player:health', { health: this.health, maxHealth: this.maxHealth });
    this.events.emit('player:respawn', {});
  }

  getPosition() {
    return this.position;
  }

  getCamera() {
    return this.camera;
  }

  getHealth() {
    return this.health;
  }

  getState() {
    return {
      position: this.position.clone(),
      velocity: this.velocity.clone(),
      health: this.health,
      maxHealth: this.maxHealth,
      armor: this.armor,
      maxArmor: this.maxArmor,
      alive: this.alive,
      grounded: this.grounded,
      crouching: this.crouching,
      sprinting: this.sprinting,
      moving: Math.hypot(this.velocity.x, this.velocity.z) > 0.4,
      eyeHeight: this.eyeHeight,
      bobPhase: this.bobPhase,
      bobX: this.bobX,
      bobY: this.bobY,
      swayX: this.swayX,
      swayY: this.swayY,
      zooming: this.zooming,
    };
  }

  setZooming(active) {
    this.zooming = active;
  }

  setSensitivity(scale) {
    this.sensitivityScale = Math.max(0.2, Math.min(2.5, Number(scale) || 1));
  }

  applyRecoil(pitch = 0, yaw = 0) {
    this.recoilPitch += pitch;
    this.recoilYaw += yaw;
  }

  dispose() {
    this.events.off('damage:target', this._onDamageTarget);
    this.events.off('explosion:detonated', this._onExplosion);
  }

  #bodyPosition() {
    return new THREE.Vector3(
      this.position.x,
      this.position.y - (this.eyeHeight - this.radius),
      this.position.z
    );
  }
}
