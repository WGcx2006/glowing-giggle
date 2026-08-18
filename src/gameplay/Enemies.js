import * as THREE from 'three';

const _v1 = new THREE.Vector3();
const _v2 = new THREE.Vector3();
const _v3 = new THREE.Vector3();
const _fwd = new THREE.Vector3();
const _right = new THREE.Vector3();

export class EnemySystem {
  constructor(scene, physics, player, events, environment, terrain, quality = {}, capture = null) {
    this.scene = scene;
    this.physics = physics;
    this.player = player;
    this.events = events;
    this.environment = environment;
    this.terrain = terrain;
    this.quality = quality;
    this.capture = capture;
    this.enemies = [];
    this.aliveCount = 0;
    this.teamAlive = { blue: 0, red: 0 };
    this.wave = 0;
    this._nextId = 1;

    this._onDamageTarget = (payload) => this.#handleDamageTarget(payload);
    this._onExplosion = (payload) => this.#handleExplosion(payload);
    this.events.on('damage:target', this._onDamageTarget);
    this.events.on('explosion:detonated', this._onExplosion);
  }

  spawnWave(count = 5) {
    const spawnPoints = this.environment?.getSpawnPoints?.() ?? [];
    const navPoints = this.environment?.getNavPoints?.() ?? [];
    const baseSpawns = spawnPoints.length > 0
      ? spawnPoints
      : [new THREE.Vector3(18, 1.5, 22), new THREE.Vector3(-22, 1.5, 18), new THREE.Vector3(26, 1.5, -18)];

    for (let i = 0; i < count; i++) {
      const base = baseSpawns[i % baseSpawns.length];
      const position = new THREE.Vector3(
        base.x + (Math.random() - 0.5) * 12,
        0,
        base.z + (Math.random() - 0.5) * 12
      );
      const ground = this.terrain?.heightAt?.(position.x, position.z) ?? 0;
      position.y = ground + 0.1;
      const playerPos = this.player.getPosition();
      if (position.distanceTo(playerPos) < 7) {
        position.x += 9;
        position.z += 6;
      }
      const type = (i % 4 === 3) || (count >= 5 && i >= 4) ? 'drone' : 'soldier';
      this.#spawnEnemy(position, type, navPoints, 'red');
    }
    this.wave++;
    this.events.emit('game:wave', { wave: this.wave });
  }

  spawnTeams(blueCount = 6, redCount = 6) {
    const navPoints = this.environment?.getNavPoints?.() ?? [];
    this.#spawnTeam('blue', blueCount, navPoints);
    this.#spawnTeam('red', redCount, navPoints);
    this.wave++;
    this.events.emit('game:wave', { wave: this.wave });
  }

  getAliveCount() {
    return this.aliveCount;
  }

  getTeamAliveCount(team) {
    return this.teamAlive[team] ?? 0;
  }

  getTeamPositions(team) {
    const positions = [];
    for (const enemy of this.enemies) {
      if (enemy.alive && enemy.team === team) {
        positions.push(enemy.group.position.clone());
      }
    }
    return positions;
  }

  reset() {
    for (const enemy of this.enemies) {
      if (enemy.physicsSphere) this.physics.removeSphere(enemy.physicsSphere);
      if (enemy.removed) continue;
      this.scene.remove(enemy.group);
      this.#disposeGroup(enemy.group);
    }
    this.enemies = [];
    this.aliveCount = 0;
    this.teamAlive = { blue: 0, red: 0 };
    this.wave = 0;
    this._nextId = 1;
  }

  #spawnTeam(team, count, navPoints) {
    const spawnPoints = this.capture?.getSpawnPositions?.(team) ?? [];
    const fallback = spawnPoints.length > 0
      ? spawnPoints
      : [new THREE.Vector3(0, 1, 0)];
    for (let i = 0; i < count; i++) {
      const base = fallback[i % fallback.length];
      const position = new THREE.Vector3(
        base.x + (Math.random() - 0.5) * 16,
        0,
        base.z + (Math.random() - 0.5) * 16
      );
      if (team === 'red' && position.distanceTo(this.player.getPosition()) < 8) {
        position.x += 10;
        position.z += 7;
      }
      const ground = this.terrain?.heightAt?.(position.x, position.z) ?? 0;
      position.y = ground + 0.1;
      const type = i % 4 === 3 ? 'drone' : 'soldier';
      this.#spawnEnemy(position, type, navPoints, team);
    }
  }

  update(dt = 0) {
    const t = Math.max(0, Math.min(dt, 0.05));
    const playerPos = this.player.getPosition();
    const playerAlive = this.player.getState()?.alive ?? true;

    for (const enemy of this.enemies) {
      if (!enemy.alive) {
        this.#updateDeath(enemy, t);
        continue;
      }
      if (enemy.type === 'drone') this.#updateDrone(enemy, t, playerPos, playerAlive);
      else this.#updateSoldier(enemy, t, playerPos, playerAlive);
      this.#updateParts(enemy, t);
    }

    this.enemies = this.enemies.filter((enemy) => !enemy.removed);
  }

  #spawnEnemy(position, type, navPoints, team = 'red') {
    const built = type === 'drone' ? this.#buildDrone(team) : this.#buildSoldier(team);
    if (type === 'drone') position.y += 2.8;
    const enemy = {
      id: `enemy-${this._nextId++}`,
      type,
      team,
      group: built.group,
      parts: built.parts,
      rotors: built.rotors ?? [],
      health: type === 'drone' ? 55 : 100,
      maxHealth: type === 'drone' ? 55 : 100,
      speed: type === 'drone' ? 6.5 : 3.1 + Math.random() * 0.9,
      detectionRange: type === 'drone' ? 62 : 48,
      fireRange: type === 'drone' ? 56 : 42,
      damage: type === 'drone' ? 7 + Math.random() * 3 : 9 + Math.random() * 4,
      tracerColor: type === 'drone'
        ? (team === 'blue' ? '#7fd4ff' : '#7fe7ff')
        : (team === 'blue' ? '#7fc6ff' : '#ffb76b'),
      fireCooldown: 0.7 + Math.random() * 0.9,
      state: 'patrol',
      navTarget: null,
      walkPhase: Math.random() * Math.PI * 2,
      yaw: Math.random() * Math.PI * 2,
      reactionT: 0,
      hitFlash: 0,
      flashDirty: false,
      knockback: new THREE.Vector3(),
      recoilT: 0,
      deathT: 0,
      alive: true,
      removed: false,
      moving: false,
      orbitAngle: Math.random() * Math.PI * 2,
      hoverPhase: Math.random() * Math.PI * 2,
      aimTarget: new THREE.Vector3(position.x, position.y + 1, position.z + 1),
    };

    enemy.group.position.copy(position);
    enemy.group.rotation.y = enemy.yaw;
    const sphereCenter = position.clone();
    sphereCenter.y += type === 'drone' ? 0 : 0.85;
    enemy.physicsSphere = this.physics.addSphere(
      enemy.id,
      sphereCenter,
      type === 'drone' ? 0.65 : 0.5,
      { static: false, userData: { entity: enemy } }
    );
    this.scene.add(enemy.group);
    this.enemies.push(enemy);
    this.aliveCount++;
    this.teamAlive[team] = (this.teamAlive[team] ?? 0) + 1;
    return enemy;
  }

  #handleDamageTarget(payload) {
    if (!payload || !payload.target) return;
    for (const enemy of this.enemies) {
      if (enemy.alive && payload.target === enemy) {
        const source = payload.source ?? null;
        if (source === 'player' && enemy.team === 'blue') return;
        if (source && enemy.team === source) return;
        const direction = payload.point
          ? _v1.copy(payload.point).sub(enemy.group.position).normalize()
          : _v2.set(0, 0, 1);
        this.#applyDamage(enemy, payload.amount, direction, payload.source);
        return;
      }
    }
  }

  #handleExplosion(payload) {
    if (!payload || !payload.position || !payload.radius || payload.power <= 0) return;
    const source = payload.source ?? payload.type ?? null;
    for (const enemy of this.enemies) {
      if (!enemy.alive) continue;
      if (source === 'player' && enemy.team === 'blue') continue;
      if (source && enemy.team === source) continue;
      const center = enemy.type === 'drone'
        ? _v1.copy(enemy.group.position)
        : _v1.copy(enemy.group.position).add(_v2.set(0, 0.85, 0));
      const distance = center.distanceTo(payload.position);
      if (distance > payload.radius) continue;
      const falloff = 1 - Math.max(0, distance / payload.radius);
      const amount = payload.power * falloff * (payload.type === 'grenade' ? 0.9 : 1);
      const direction = distance > 0.001
        ? _v3.copy(center).sub(payload.position).normalize()
        : _v2.set(0, 1, 0);
      this.#applyDamage(enemy, amount, direction, source ?? payload.type);
      enemy.knockback.addScaledVector(direction, Math.min(6, payload.power * falloff * 0.06));
    }
  }

  #applyDamage(enemy, amount, direction, source) {
    if (!enemy.alive || amount <= 0) return;
    enemy.health -= amount;
    enemy.reactionT = 0.16;
    enemy.hitFlash = 0.3;
    enemy.flashDirty = true;
    enemy.knockback.addScaledVector(direction, Math.min(4, amount * 0.06));
    enemy.killerSource = source ?? null;
    if (enemy.health <= 0) this.#killEnemy(enemy, source);
  }

  #killEnemy(enemy, source = null) {
    if (!enemy.alive) return;
    enemy.alive = false;
    this.aliveCount = Math.max(0, this.aliveCount - 1);
    this.teamAlive[enemy.team] = Math.max(0, (this.teamAlive[enemy.team] ?? 0) - 1);
    this.physics.removeSphere(enemy.physicsSphere);
    enemy.deathT = 0;
    const isRed = enemy.team === 'red';
    const name = enemy.type === 'drone'
      ? (isRed ? '无人机' : '友方无人机')
      : (isRed ? '敌方士兵' : '友方士兵');
    // Game.js already renders enemy:kill into the killfeed; HUD.js also subscribes
    // to killfeed directly, so emitting killfeed here would create duplicate rows.
    this.events.emit('enemy:kill', { name, team: enemy.team, source: source ?? null });
  }

  #selectTarget(enemy, playerPos, playerAlive) {
    if (enemy.team === 'red' && playerAlive) {
      return { isPlayer: true, ref: 'player', position: playerPos };
    }
    let best = null;
    let bestDistance = Infinity;
    for (const other of this.enemies) {
      if (!other.alive || other === enemy || other.team === enemy.team) continue;
      const distance = enemy.group.position.distanceTo(other.group.position);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = { isPlayer: false, ref: other, position: other.group.position };
      }
    }
    return best;
  }

  #updateSoldier(enemy, dt, playerPos, playerAlive) {
    const target = this.#selectTarget(enemy, playerPos, playerAlive);
    const targetPos = target?.position ?? null;
    _v1.copy(targetPos ?? enemy.group.position).sub(enemy.group.position);
    const distance = _v1.length();
    const distanceXZ = Math.hypot(_v1.x, _v1.z);
    const targetYaw = Math.atan2(_v1.x, _v1.z);
    const canSee = targetPos
      ? this.#hasLineOfSight(enemy, targetPos, distance, target.ref)
      : false;
    const engaged = Boolean(targetPos) && distance < enemy.detectionRange && canSee;
    enemy.state = engaged ? 'engage' : 'patrol';

    enemy.yaw += this.#angleDelta(enemy.yaw, targetYaw) * Math.min(1, dt * 7);
    enemy.group.rotation.y = enemy.yaw;

    const move = _v2.set(0, 0, 0);
    if (engaged) {
      enemy.aimTarget.copy(targetPos);
      const advance = distanceXZ > 16 ? 1 : distanceXZ < 7 ? -1 : 0.25;
      const strafeSign = Math.sin(enemy.walkPhase + enemy.id.length) > 0 ? 1 : -1;
      _fwd.set(Math.sin(enemy.yaw), 0, Math.cos(enemy.yaw));
      _right.set(Math.cos(enemy.yaw), 0, -Math.sin(enemy.yaw));
      move.addScaledVector(_fwd, advance).addScaledVector(_right, strafeSign * 0.55);
      if (move.lengthSq() > 0.001) move.normalize();
      enemy.moving = true;
    } else {
      if (enemy.team === 'red' && playerAlive) {
        enemy.aimTarget.copy(playerPos);
      } else {
        enemy.aimTarget.set(
          enemy.group.position.x + Math.sin(enemy.yaw) * 8,
          enemy.group.position.y + 1,
          enemy.group.position.z + Math.cos(enemy.yaw) * 8
        );
      }
      this.#pickNavTarget(enemy);
      _v3.copy(enemy.navTarget).sub(enemy.group.position);
      _v3.y = 0;
      if (_v3.length() > 1.2) {
        const navYaw = Math.atan2(_v3.x, _v3.z);
        enemy.yaw += this.#angleDelta(enemy.yaw, navYaw) * Math.min(1, dt * 5);
        enemy.group.rotation.y = enemy.yaw;
        move.copy(_v3).normalize();
        enemy.moving = true;
      } else {
        enemy.moving = false;
      }
    }

    enemy.knockback.multiplyScalar(Math.max(0, 1 - dt * 4));
    _v3.copy(move).multiplyScalar(enemy.speed * dt).addScaledVector(enemy.knockback, dt);
    this.physics.moveSphere(enemy.physicsSphere, _v3);

    const sphereFloor = enemy.physicsSphere.center.y - 0.85;
    const ground = this.terrain?.heightAt?.(
      enemy.physicsSphere.center.x,
      enemy.physicsSphere.center.z
    ) ?? 0;
    enemy.group.position.set(
      enemy.physicsSphere.center.x,
      Math.max(sphereFloor, ground + 0.05),
      enemy.physicsSphere.center.z
    );
    enemy.physicsSphere.center.y = enemy.group.position.y + 0.85;
    enemy.walkPhase += dt * (enemy.moving ? 7 : 0);
    enemy.fireCooldown -= dt;

    if (engaged && distance < enemy.fireRange && enemy.fireCooldown <= 0) {
      this.#enemyFire(enemy, targetPos);
      enemy.fireCooldown = 0.75 + Math.random() * 0.75;
    }
  }

  #updateDrone(enemy, dt, playerPos, playerAlive) {
    const ground = this.terrain?.heightAt?.(
      enemy.group.position.x,
      enemy.group.position.z
    ) ?? 0;
    const baseAltitude = ground + 3.1;
    const target = this.#selectTarget(enemy, playerPos, playerAlive);
    const targetPos = target?.position ?? null;
    const distance = targetPos ? targetPos.distanceTo(enemy.group.position) : 0;
    const canSee = targetPos
      ? this.#hasLineOfSight(enemy, targetPos, distance, target.ref)
      : false;
    const engaged = Boolean(targetPos) && distance < enemy.detectionRange && canSee;
    enemy.state = engaged ? 'engage' : 'patrol';
    enemy.hoverPhase += dt * 1.4;

    let moveTarget;
    if (engaged) {
      enemy.aimTarget.copy(targetPos);
      enemy.orbitAngle += dt * 0.85;
      const orbitRadius = 13 + Math.sin(enemy.hoverPhase) * 4;
      moveTarget = _v2.set(
        targetPos.x + Math.cos(enemy.orbitAngle) * orbitRadius,
        baseAltitude + Math.sin(enemy.hoverPhase * 1.3) * 0.7,
        targetPos.z + Math.sin(enemy.orbitAngle) * orbitRadius
      );
      enemy.moving = true;
    } else {
      this.#pickNavTarget(enemy);
      moveTarget = _v3.copy(enemy.navTarget);
      moveTarget.y = baseAltitude + Math.sin(enemy.hoverPhase) * 0.6;
      enemy.moving = true;
    }

    _v3.copy(moveTarget).sub(enemy.group.position);
    const step = Math.min(enemy.speed * dt, _v3.length());
    if (_v3.lengthSq() > 0.001) _v3.normalize().multiplyScalar(step);
    enemy.knockback.multiplyScalar(Math.max(0, 1 - dt * 3));
    _v3.addScaledVector(enemy.knockback, dt);
    this.physics.moveSphere(enemy.physicsSphere, _v3);
    enemy.group.position.copy(enemy.physicsSphere.center);
    enemy.group.position.y += Math.sin(enemy.hoverPhase * 0.7) * 0.02;

    const faceX = engaged ? targetPos.x : (enemy.navTarget?.x ?? enemy.group.position.x);
    const faceZ = engaged ? targetPos.z : (enemy.navTarget?.z ?? enemy.group.position.z);
    const faceYaw = Math.atan2(
      faceX - enemy.group.position.x,
      faceZ - enemy.group.position.z
    );
    enemy.yaw += this.#angleDelta(enemy.yaw, faceYaw) * Math.min(1, dt * 6);
    enemy.group.rotation.y = enemy.yaw;
    for (const rotor of enemy.rotors) rotor.rotation.y += dt * 42;

    enemy.fireCooldown -= dt;
    if (engaged && distance < enemy.fireRange && enemy.fireCooldown <= 0) {
      this.#enemyFire(enemy, targetPos);
      enemy.fireCooldown = 0.9 + Math.random() * 0.8;
    }
  }

  #enemyFire(enemy, targetPos) {
    const origin = _v1.copy(enemy.parts.muzzle.getWorldPosition(new THREE.Vector3()));
    const direction = _v2.copy(targetPos).sub(origin).normalize();
    const spread = 0.012 + (enemy.type === 'drone' ? 0.006 : 0.004);
    direction.x += (Math.random() - 0.5) * spread;
    direction.y += (Math.random() - 0.5) * spread;
    direction.z += (Math.random() - 0.5) * spread;
    direction.normalize();

    this.events.emit('enemy:fire', {
      origin: origin.clone(),
      direction: direction.clone(),
      damage: enemy.damage,
      tracerColor: enemy.tracerColor,
      source: enemy.team,
    });
    enemy.recoilT = 1;
  }

  #hasLineOfSight(enemy, targetPos, maxDistance, targetRef) {
    const eye = _v1.copy(enemy.group.position);
    eye.y += enemy.type === 'drone' ? 0 : 1.38;
    const direction = _v2.copy(targetPos).sub(eye);
    const distance = direction.length();
    if (distance <= 0.05) return true;
    direction.normalize();
    const rayDistance = Math.max(0.01, Math.min(maxDistance, distance - 0.05));
    const terrainHit = typeof this.terrain?.raycast === 'function'
      ? this.terrain.raycast(eye, direction, rayDistance)
      : this.#raycastTerrain(eye, direction, rayDistance);
    if (terrainHit && terrainHit.distance < distance) return false;
    const hit = this.physics.raycast(
      eye,
      direction,
      rayDistance,
      (candidate) => {
        if (candidate.type !== 'sphere') return false;
        const entity = candidate.object?.userData?.entity;
        if (entity === enemy) return true;
        if (entity?.team === enemy.team && entity !== targetRef) return true;
        return false;
      }
    );
    if (!hit) return true;
    return hit.object?.userData?.entity === targetRef;
  }

  #raycastTerrain(origin, direction, maxDistance) {
    const terrain = this.terrain;
    if (!terrain || typeof terrain.heightAt !== 'function' || maxDistance <= 0.01) return null;
    const dir = _v3.copy(direction).normalize();
    const step = Math.min(1.5, Math.max(0.5, maxDistance / 64));
    let t = 0;
    let prevT = 0;
    let prevGroundY = terrain.heightAt(origin.x, origin.z);
    let prevRayY = origin.y;
    while (t < maxDistance) {
      const nextT = Math.min(t + step, maxDistance);
      const x = origin.x + dir.x * nextT;
      const z = origin.z + dir.z * nextT;
      const groundY = terrain.heightAt(x, z);
      const rayY = origin.y + dir.y * nextT;
      const prevDelta = prevGroundY - prevRayY;
      const nextDelta = groundY - rayY;
      if (prevDelta > 0) {
        const point = new THREE.Vector3(origin.x, origin.y, origin.z);
        const normal = this.#terrainNormal(terrain, point);
        return { point, normal, distance: 0 };
      }
      if (nextDelta >= 0) {
        const denom = nextDelta - prevDelta;
        const local = denom > 1e-6 ? Math.max(0, Math.min(1, -prevDelta / denom)) : 1;
        const hitT = Math.max(0, prevT + (nextT - prevT) * local);
        const point = new THREE.Vector3(
          origin.x + dir.x * hitT,
          origin.y + dir.y * hitT,
          origin.z + dir.z * hitT
        );
        const normal = this.#terrainNormal(terrain, point);
        return { point, normal, distance: hitT };
      }
      prevGroundY = groundY;
      prevRayY = rayY;
      prevT = nextT;
      t = nextT;
    }
    return null;
  }

  #terrainNormal(terrain, point) {
    const e = 0.6;
    const hL = terrain.heightAt(point.x - e, point.z);
    const hR = terrain.heightAt(point.x + e, point.z);
    const hD = terrain.heightAt(point.x, point.z - e);
    const hU = terrain.heightAt(point.x, point.z + e);
    return new THREE.Vector3(hL - hR, 2 * e, hD - hU).normalize();
  }

  #pickNavTarget(enemy) {
    if (enemy.navTarget && enemy.group.position.distanceTo(enemy.navTarget) > 2.5) return;
    const navPoints = this.environment?.getNavPoints?.() ?? [];
    if (navPoints.length === 0) {
      enemy.navTarget = new THREE.Vector3(20, 0, 20);
      return;
    }
    const index = Math.floor(Math.random() * navPoints.length);
    enemy.navTarget = navPoints[index].clone();
  }

  #angleDelta(from, to) {
    let delta = to - from;
    while (delta > Math.PI) delta -= Math.PI * 2;
    while (delta < -Math.PI) delta += Math.PI * 2;
    return delta;
  }

  #updateParts(enemy, dt) {
    if (enemy.type === 'soldier') {
      const swing = Math.sin(enemy.walkPhase) * 0.55 * (enemy.moving ? 1 : 0);
      enemy.parts.leftLegPivot.rotation.x = swing;
      enemy.parts.rightLegPivot.rotation.x = -swing;
      enemy.parts.leftArmPivot.rotation.x = -swing * 0.6 + 0.15;
      enemy.parts.rightArmPivot.rotation.x = swing * 0.6 - 0.25;

      const eye = _v1.copy(enemy.group.position);
      eye.y += 1.3;
      const target = _v2.copy(enemy.aimTarget ?? this.player.getPosition());
      const toTarget = _v3.copy(target).sub(eye);
      const pitch = Math.atan2(toTarget.y, Math.hypot(toTarget.x, toTarget.z));
      enemy.parts.weapon.rotation.x = Math.max(-0.6, Math.min(1, pitch * 0.55 + 0.1))
        + enemy.recoilT * 0.18;
      enemy.recoilT *= Math.exp(-7 * dt);
      enemy.group.rotation.z = Math.sin(enemy.reactionT * 45) * 0.06 * Math.min(1, enemy.reactionT * 8);
      enemy.reactionT = Math.max(0, enemy.reactionT - dt);
    }

    if (enemy.hitFlash > 0) {
      enemy.hitFlash = Math.max(0, enemy.hitFlash - dt);
      enemy.group.traverse((object) => {
        if (object.isMesh && object.material) {
          object.material.emissive?.setRGB(1, 0.16, 0.08);
          object.material.emissiveIntensity = Math.min(1, enemy.hitFlash * 3.5);
        }
      });
    } else if (enemy.flashDirty) {
      enemy.flashDirty = false;
      enemy.group.traverse((object) => {
        if (object.isMesh && object.material) {
          object.material.emissive?.setRGB(0, 0, 0);
          object.material.emissiveIntensity = 0;
        }
      });
    }
  }

  #updateDeath(enemy, dt) {
    enemy.deathT += dt;
    const t = enemy.deathT;
    if (enemy.type === 'soldier') {
      enemy.group.rotation.x = Math.min(-1.2, -t * 2.2);
      enemy.group.rotation.z = Math.sin(t * 4) * 0.08;
      enemy.group.position.y = Math.max(0.08, enemy.group.position.y - t * 1.1);
    } else {
      enemy.group.rotation.z += dt * 5;
      enemy.group.rotation.x += dt * 1.8;
      enemy.group.position.y -= dt * 2.4;
    }

    if (t > 0.45) {
      const alpha = Math.max(0, 1 - (t - 0.45) * 0.32);
      enemy.group.traverse((object) => {
        if (object.isMesh && object.material) {
          object.material.transparent = true;
          object.material.opacity = alpha;
        }
      });
    }

    if (t > 3.4) {
      this.scene.remove(enemy.group);
      this.#disposeGroup(enemy.group);
      enemy.removed = true;
    }
  }

  #disposeGroup(group) {
    group.traverse((object) => {
      if (object.geometry) object.geometry.dispose();
      if (!object.material) return;
      const materials = Array.isArray(object.material) ? object.material : [object.material];
      for (const material of materials) material.dispose();
    });
  }

  #buildSoldier(team = 'red') {
    const isBlue = team === 'blue';
    const group = new THREE.Group();
    const uniform = new THREE.MeshStandardMaterial({
      color: isBlue ? 0x3f5f7f : 0x7a3d35,
      roughness: 0.82,
      metalness: 0.05,
    });
    const dark = new THREE.MeshStandardMaterial({
      color: isBlue ? 0x283642 : 0x3b2420,
      roughness: 0.75,
      metalness: 0.05,
    });
    const skin = new THREE.MeshStandardMaterial({ color: 0xc39b7b, roughness: 0.8, metalness: 0.02 });
    const helmet = new THREE.MeshStandardMaterial({
      color: isBlue ? 0x26333f : 0x2b201d,
      roughness: 0.55,
      metalness: 0.35,
    });
    const weaponMat = new THREE.MeshStandardMaterial({ color: 0x191d22, roughness: 0.45, metalness: 0.65 });

    const torso = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.58, 0.28), uniform);
    torso.position.y = 1.05;
    const pelvis = new THREE.Mesh(new THREE.BoxGeometry(0.4, 0.28, 0.24), dark);
    pelvis.position.y = 0.72;
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.15, 10, 8), skin);
    head.position.y = 1.46;
    const cap = new THREE.Mesh(
      new THREE.SphereGeometry(0.17, 10, 8, 0, Math.PI * 2, 0, Math.PI * 0.52),
      helmet
    );
    cap.position.y = 1.49;

    const leftArmPivot = new THREE.Object3D();
    leftArmPivot.position.set(-0.34, 1.28, 0);
    const leftArm = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.42, 0.14), uniform);
    leftArm.position.y = -0.22;
    leftArmPivot.add(leftArm);

    const rightArmPivot = new THREE.Object3D();
    rightArmPivot.position.set(0.34, 1.28, 0);
    const rightArm = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.42, 0.14), uniform);
    rightArm.position.y = -0.22;
    rightArmPivot.add(rightArm);

    const leftLegPivot = new THREE.Object3D();
    leftLegPivot.position.set(-0.13, 0.72, 0);
    const leftLeg = new THREE.Mesh(new THREE.BoxGeometry(0.17, 0.62, 0.17), dark);
    leftLeg.position.y = -0.3;
    leftLegPivot.add(leftLeg);

    const rightLegPivot = new THREE.Object3D();
    rightLegPivot.position.set(0.13, 0.72, 0);
    const rightLeg = new THREE.Mesh(new THREE.BoxGeometry(0.17, 0.62, 0.17), dark);
    rightLeg.position.y = -0.3;
    rightLegPivot.add(rightLeg);

    const weapon = new THREE.Group();
    const rifle = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.12, 0.58), weaponMat);
    rifle.position.z = 0.1;
    const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.018, 0.018, 0.36, 6), weaponMat);
    barrel.rotation.x = Math.PI / 2;
    barrel.position.z = 0.46;
    const magazine = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.18, 0.09), dark);
    magazine.position.set(0, -0.13, 0.14);
    const stock = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.1, 0.2), dark);
    stock.position.set(0, 0, -0.24);
    const muzzle = new THREE.Object3D();
    muzzle.position.set(0, 0.02, 0.64);
    weapon.add(rifle, barrel, magazine, stock, muzzle);
    weapon.position.set(0.16, 1.08, -0.1);
    weapon.rotation.x = -0.15;

    group.add(torso, pelvis, head, cap, leftArmPivot, rightArmPivot, leftLegPivot, rightLegPivot, weapon);
    return {
      group,
      parts: { leftArmPivot, rightArmPivot, leftLegPivot, rightLegPivot, weapon, muzzle },
    };
  }

  #buildDrone(team = 'red') {
    const isBlue = team === 'blue';
    const group = new THREE.Group();
    const dark = new THREE.MeshStandardMaterial({
      color: isBlue ? 0x26323d : 0x24292e,
      roughness: 0.5,
      metalness: 0.6,
    });
    const bodyMat = new THREE.MeshStandardMaterial({
      color: isBlue ? 0x354a5c : 0x30363c,
      roughness: 0.45,
      metalness: 0.7,
    });
    const light = new THREE.MeshBasicMaterial({ color: isBlue ? 0x4d9fff : 0xff5a3c });

    const body = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.2, 0.62), bodyMat);
    const core = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.16, 0.26, 8), dark);
    const sensor = new THREE.Mesh(new THREE.SphereGeometry(0.08, 8, 6), light);
    sensor.position.set(0, 0, 0.36);
    const gunPod = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.1, 0.32), dark);
    gunPod.position.set(0, -0.18, 0.1);
    const muzzle = new THREE.Object3D();
    muzzle.position.set(0, -0.18, 0.28);
    group.add(body, core, sensor, gunPod, muzzle);

    const rotors = [];
    for (let i = 0; i < 4; i++) {
      const sx = (i % 2 === 0 ? -1 : 1) * 0.55;
      const sz = (i < 2 ? -1 : 1) * 0.5;
      const boom = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, 0.38, 6), dark);
      boom.rotation.z = Math.PI / 2;
      boom.position.set(sx * 0.72, 0.04, sz * 0.62);
      const rotorPivot = new THREE.Object3D();
      rotorPivot.position.set(sx * 0.92, 0.08, sz * 0.72);
      const blade = new THREE.Mesh(new THREE.BoxGeometry(0.52, 0.015, 0.06), dark);
      rotorPivot.add(blade);
      group.add(boom, rotorPivot);
      rotors.push(rotorPivot);
    }

    return { group, parts: { muzzle }, rotors };
  }
}
