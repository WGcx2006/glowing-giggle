import * as THREE from 'three';

const _origin = new THREE.Vector3();
const _dir = new THREE.Vector3();
const _muzzleWorld = new THREE.Vector3();
const _right = new THREE.Vector3();
const _up = new THREE.Vector3();

const WEAPON_DEFS = [
  {
    id: 'assault',
    name: '突击步枪',
    damage: 26,
    rpm: 640,
    spread: 0.012,
    magSize: 30,
    reserve: 120,
    reloadTime: 2.0,
    tracerColor: '#ffd27a',
    adsFov: 55,
    basePos: new THREE.Vector3(0.26, -0.23, -0.58),
    adsPos: new THREE.Vector3(0, -0.14, -0.36),
    recoilKick: 0.34,
    cameraRecoil: 0.013,
  },
  {
    id: 'smg',
    name: '冲锋枪',
    damage: 17,
    rpm: 900,
    spread: 0.02,
    magSize: 40,
    reserve: 160,
    reloadTime: 1.7,
    tracerColor: '#ffb347',
    adsFov: 60,
    basePos: new THREE.Vector3(0.25, -0.22, -0.54),
    adsPos: new THREE.Vector3(0, -0.13, -0.34),
    recoilKick: 0.27,
    cameraRecoil: 0.009,
  },
  {
    id: 'marksman',
    name: '精确射手步枪',
    damage: 55,
    rpm: 260,
    spread: 0.003,
    magSize: 12,
    reserve: 48,
    reloadTime: 2.6,
    tracerColor: '#ffe9a8',
    adsFov: 42,
    basePos: new THREE.Vector3(0.28, -0.24, -0.62),
    adsPos: new THREE.Vector3(0, -0.15, -0.38),
    recoilKick: 0.52,
    cameraRecoil: 0.024,
  },
  {
    id: 'rocket_launcher',
    name: '火箭筒',
    damage: 45,
    rpm: 60,
    spread: 0.01,
    magSize: 1,
    reserve: 4,
    reloadTime: 3.0,
    projectileType: 'rocket',
    tracerColor: '#e8e4d0',
    adsFov: 50,
    basePos: new THREE.Vector3(0.3, -0.28, -0.62),
    adsPos: new THREE.Vector3(0, -0.16, -0.4),
    recoilKick: 0.95,
    cameraRecoil: 0.04,
  },
  {
    id: 'grenade',
    name: '手雷',
    damage: 12,
    rpm: 75,
    spread: 0.02,
    magSize: 1,
    reserve: 4,
    reloadTime: 2.2,
    projectileType: 'grenade',
    tracerColor: '#d8f0c0',
    adsFov: 64,
    basePos: new THREE.Vector3(0.2, -0.2, -0.5),
    adsPos: new THREE.Vector3(0, -0.12, -0.32),
    recoilKick: 0.22,
    cameraRecoil: 0.008,
  },
];

export class WeaponSystem {
  constructor(scene, camera, player, physics, events, quality = {}) {
    this.scene = scene;
    this.camera = camera;
    this.player = player;
    this.physics = physics;
    this.events = events;
    this.quality = quality;

    if (camera.parent !== scene) scene.add(camera);

    this.weaponDefs = WEAPON_DEFS.map((def) => {
      const built = this.#buildViewmodel(def);
      return { ...def, ...built };
    });

    this.root = new THREE.Group();
    this.root.position.copy(WEAPON_DEFS[0].basePos);
    camera.add(this.root);

    this.ammo = WEAPON_DEFS.map((def) => ({ current: def.magSize, reserve: def.reserve }));
    this.currentIndex = 0;
    this.weapon = this.weaponDefs[0];
    this.current = this.ammo[0].current;
    this.reserve = this.ammo[0].reserve;
    this.fireTimer = 0;
    this.reloading = false;
    this.reloadProgress = 0;
    this.reloadT = 0;
    this.adsAmount = 0;
    this.recoil = 0;
    this.muzzleFlashT = 0;

    this.weaponDefs.forEach((def, index) => {
      this.root.add(def.group);
      def.group.visible = index === 0;
    });

    this.events.emit('weapon:switch', { name: this.weapon.name });
    this.events.emit('weapon:ammo', { current: this.current, reserve: this.reserve });
  }

  update(dt = 0, input = {}) {
    const t = Math.max(0.0001, Math.min(dt, 0.05));
    const state = this.player.getState();
    const alive = state.alive;

    if (!alive && this.reloading) {
      this.reloading = false;
      this.reloadProgress = 0;
      this.reloadT = 0;
    }

    this.adsAmount += ((input.zoom && alive ? 1 : 0) - this.adsAmount) * Math.min(1, t * 11);
    this.player.setZooming(this.adsAmount > 0.5);

    const targetFov = this.adsAmount > 0.01
      ? this.weapon.adsFov
      : state.sprinting ? 78 : 70;
    if (Math.abs(this.camera.fov - targetFov) > 0.01) {
      this.camera.fov += (targetFov - this.camera.fov) * Math.min(1, t * 12);
      this.camera.updateProjectionMatrix();
    }

    this.fireTimer += t;
    if (input.mouseDown && this.fireTimer >= 60 / this.weapon.rpm && alive) {
      this.#fire();
    }

    if (this.reloading) {
      this.reloadT += t;
      this.reloadProgress = Math.min(1, this.reloadT / this.weapon.reloadTime);
      if (this.reloadProgress >= 1) {
        const ammo = this.ammo[this.currentIndex];
        const need = this.weapon.magSize - ammo.current;
        const taken = Math.min(need, ammo.reserve);
        ammo.current += taken;
        ammo.reserve -= taken;
        this.current = ammo.current;
        this.reserve = ammo.reserve;
        this.reloading = false;
        this.events.emit('weapon:ammo', { current: this.current, reserve: this.reserve });
      }
    }

    this.recoil *= Math.exp(-11 * t);
    this.muzzleFlashT = Math.max(0, this.muzzleFlashT - t);
    this.#applyViewmodelPose(t, state);
  }

  #fire() {
    if (this.reloading || !this.player.getState().alive) return;
    const ammo = this.ammo[this.currentIndex];
    if (ammo.current <= 0) {
      if (ammo.reserve > 0) this.reload();
      return;
    }

    ammo.current--;
    this.current = ammo.current;
    this.reserve = ammo.reserve;
    this.events.emit('weapon:ammo', { current: this.current, reserve: this.reserve });

    this.camera.getWorldPosition(_origin);
    this.camera.getWorldDirection(_dir).normalize();
    const spread = this.weapon.spread * (this.adsAmount > 0.5 ? 0.3 : 1)
      + (this.player.getState().moving ? 0.007 : 0);
    if (spread > 0) {
      _right.crossVectors(_dir, this.camera.up).normalize();
      _up.crossVectors(_right, _dir).normalize();
      _dir.addScaledVector(_right, (Math.random() * 2 - 1) * spread)
        .addScaledVector(_up, (Math.random() * 2 - 1) * spread)
        .normalize();
    }
    _origin.addScaledVector(_dir, 0.25);
    this.weapon.muzzle.getWorldPosition(_muzzleWorld);

    const payload = {
      origin: _origin.clone(),
      direction: _dir.clone(),
      damage: this.weapon.damage,
      tracerColor: this.weapon.tracerColor,
      weaponType: this.weapon.id,
    };
    if (this.weapon.projectileType) payload.projectileType = this.weapon.projectileType;
    this.events.emit('weapon:fire', payload);
    this.events.emit('weapon:muzzle', {
      position: _muzzleWorld.clone(),
      direction: _dir.clone(),
      weaponType: this.weapon.id,
    });

    this.fireTimer = 0;
    this.recoil = Math.min(1.4, this.recoil + this.weapon.recoilKick * (this.adsAmount > 0.5 ? 0.72 : 1));
    this.muzzleFlashT = 0.055;
    this.player.applyRecoil(
      this.weapon.cameraRecoil * (this.adsAmount > 0.5 ? 0.72 : 1),
      (Math.random() - 0.5) * this.weapon.cameraRecoil * 0.4
    );
  }

  reload() {
    const ammo = this.ammo[this.currentIndex];
    if (
      this.reloading
      || ammo.current >= this.weapon.magSize
      || ammo.reserve <= 0
      || !this.player.getState().alive
    ) return;
    this.reloading = true;
    this.reloadT = 0;
    this.reloadProgress = 0;
    this.events.emit('weapon:reload', {});
  }

  switchWeapon(index) {
    if (
      index === this.currentIndex
      || index < 0
      || index >= this.weaponDefs.length
    ) return;
    this.weaponDefs.forEach((def, i) => {
      def.group.visible = i === index;
    });
    this.currentIndex = index;
    this.weapon = this.weaponDefs[index];
    this.reloading = false;
    this.reloadProgress = 0;
    this.reloadT = 0;
    const ammo = this.ammo[index];
    this.current = ammo.current;
    this.reserve = ammo.reserve;
    this.fireTimer = Math.min(this.fireTimer, 0.12);
    this.events.emit('weapon:switch', { name: this.weapon.name });
    this.events.emit('weapon:ammo', { current: this.current, reserve: this.reserve });
  }

  getState() {
    return {
      name: this.weapon.name,
      weaponType: this.weapon.id,
      current: this.current,
      reserve: this.reserve,
      reloading: this.reloading,
      reloadProgress: this.reloadProgress,
      ads: this.adsAmount,
      fireCooldown: Math.max(0, 60 / this.weapon.rpm - this.fireTimer),
    };
  }

  #applyViewmodelPose(dt, state) {
    const base = this.weapon.basePos;
    const ads = this.weapon.adsPos;
    const x = base.x + (ads.x - base.x) * this.adsAmount;
    const y = base.y + (ads.y - base.y) * this.adsAmount + (state.crouching ? -0.04 : 0);
    const z = base.z + (ads.z - base.z) * this.adsAmount;
    const reloadDip = this.reloading
      ? -Math.sin(Math.min(1, this.reloadProgress) * Math.PI) * 0.12
      : 0;
    const adsBobScale = 1 - this.adsAmount * 0.7;
    const adsSwayScale = 1 - this.adsAmount * 0.82;
    const bobX = state.bobX * 0.55 * adsBobScale;
    const bobY = state.bobY * 0.5 * adsBobScale;
    const recoilZ = -this.recoil * 0.055;
    const recoilX = this.recoil * 0.012;
    const recoilY = this.recoil * 0.01;
    const sprintDip = state.sprinting ? -0.06 : 0;

    this.root.position.set(
      x + bobX + state.swayX * 0.6 * adsSwayScale + recoilX,
      y + bobY + state.swayY * 0.55 * adsSwayScale + reloadDip + recoilY + sprintDip,
      z + recoilZ
    );
    this.root.rotation.set(
      this.recoil * 0.13 + (state.crouching ? 0.06 : 0) + (state.sprinting ? 0.08 : 0),
      state.swayX * 0.7 * adsSwayScale,
      -state.swayX * 0.35 * adsSwayScale - this.recoil * 0.035 + (state.sprinting ? 0.12 : 0)
    );

    if (this.weapon.magPivot) {
      this.weapon.magPivot.rotation.x = this.reloading
        ? -Math.sin(this.reloadProgress * Math.PI) * 1.1
        : 0;
    }
    this.weapon.flash.visible = this.muzzleFlashT > 0;
    if (this.weapon.flash.visible) {
      const scale = 0.85 + Math.random() * 0.5;
      this.weapon.flash.scale.set(scale, scale, scale);
      this.weapon.flash.material.opacity = this.muzzleFlashT / 0.055;
    }
  }

  #buildViewmodel(def) {
    const group = new THREE.Group();
    const gun = new THREE.Group();
    const isSmg = def.id === 'smg';
    const isMarksman = def.id === 'marksman';
    const isRocket = def.id === 'rocket_launcher';
    const isGrenade = def.id === 'grenade';
    const receiverLength = isSmg ? 0.3 : 0.42;
    const barrelLength = isMarksman ? 0.58 : isSmg ? 0.28 : 0.46;

    const steel = new THREE.MeshStandardMaterial({ color: 0x252b33, roughness: 0.42, metalness: 0.78 });
    const dark = new THREE.MeshStandardMaterial({ color: 0x14181d, roughness: 0.62, metalness: 0.4 });
    const gripMat = new THREE.MeshStandardMaterial({ color: 0x2a211d, roughness: 0.88, metalness: 0.04 });
    const accent = new THREE.MeshStandardMaterial({ color: 0xb9542c, roughness: 0.5, metalness: 0.32 });
    const lensMat = new THREE.MeshStandardMaterial({ color: 0x102030, roughness: 0.12, metalness: 0.9, emissive: 0x1d4b70, emissiveIntensity: 0.5 });
    const flashMat = new THREE.MeshBasicMaterial({
      color: 0xffd27a,
      transparent: true,
      opacity: 0.9,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    const skinMat = new THREE.MeshStandardMaterial({ color: 0xc49a76, roughness: 0.8, metalness: 0.02 });
    const sleeveMat = new THREE.MeshStandardMaterial({ color: 0x2c3236, roughness: 0.85, metalness: 0.02 });
    const gloveMat = new THREE.MeshStandardMaterial({ color: 0x1d2125, roughness: 0.75, metalness: 0.05 });

    const add = (geometry, material, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0, parent = gun) => {
      const mesh = new THREE.Mesh(geometry, material);
      mesh.position.set(x, y, z);
      mesh.rotation.set(rx, ry, rz);
      mesh.castShadow = true;
      parent.add(mesh);
      return mesh;
    };
    const addToGroup = (geometry, material, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0) => {
      const mesh = new THREE.Mesh(geometry, material);
      mesh.position.set(x, y, z);
      mesh.rotation.set(rx, ry, rz);
      mesh.castShadow = true;
      group.add(mesh);
      return mesh;
    };

    if (isRocket) {
      const built = this.#buildRocketLauncherViewmodel(
        gun,
        add,
        addToGroup,
        steel,
        dark,
        accent,
        gripMat,
        flashMat,
        skinMat,
        sleeveMat,
        gloveMat
      );
      group.add(gun);
      return { group, ...built };
    }
    if (isGrenade) {
      const built = this.#buildGrenadeViewmodel(
        gun,
        add,
        addToGroup,
        steel,
        dark,
        accent,
        flashMat,
        skinMat,
        sleeveMat,
        gloveMat
      );
      group.add(gun);
      return { group, ...built };
    }

    add(new THREE.BoxGeometry(0.075, 0.115, receiverLength), steel, 0, 0.015, 0);
    add(new THREE.BoxGeometry(0.045, 0.02, receiverLength * 0.72), dark, 0, 0.075, -0.02);
    add(new THREE.CylinderGeometry(0.018, 0.021, barrelLength, 8), steel, 0, 0.028, -0.08 - barrelLength * 0.5, Math.PI / 2);
    add(new THREE.BoxGeometry(0.06, 0.075, 0.18), dark, 0, 0.025, -0.12);
    add(new THREE.CylinderGeometry(0.026, 0.029, 0.08, 8), dark, 0, 0.028, -0.08 - barrelLength, Math.PI / 2);

    if (isMarksman) {
      add(new THREE.BoxGeometry(0.06, 0.11, 0.26), dark, 0, 0.015, receiverLength * 0.5 + 0.08);
    } else if (isSmg) {
      add(new THREE.BoxGeometry(0.055, 0.09, 0.12), dark, 0, 0.02, receiverLength * 0.5 + 0.02);
    } else {
      add(new THREE.BoxGeometry(0.065, 0.115, 0.24), dark, 0, 0.015, receiverLength * 0.5 + 0.08);
    }
    add(new THREE.BoxGeometry(0.055, 0.16, 0.075), gripMat, 0, -0.1, receiverLength * 0.5 - 0.07, 0.2);

    const magPivot = new THREE.Group();
    magPivot.position.set(0, -0.045, isSmg ? 0.02 : 0.04);
    const magHeight = isSmg ? 0.3 : 0.24;
    const magazine = new THREE.Mesh(
      new THREE.BoxGeometry(0.05, magHeight, 0.09),
      isSmg ? steel : gripMat
    );
    magazine.position.y = -magHeight * 0.45;
    magPivot.add(magazine);
    gun.add(magPivot);

    if (isMarksman) {
      const scope = new THREE.Group();
      add(new THREE.CylinderGeometry(0.032, 0.032, 0.24, 10), steel, 0, 0.11, -0.03, Math.PI / 2, 0, 0, scope);
      const lens = new THREE.Mesh(new THREE.CircleGeometry(0.028, 10), lensMat);
      lens.position.set(0, 0.11, -0.15);
      lens.rotation.y = Math.PI / 2;
      scope.add(lens);
      gun.add(scope);
    } else {
      add(new THREE.BoxGeometry(0.035, 0.08, 0.03), dark, 0, 0.08, -0.2);
      add(new THREE.BoxGeometry(0.04, 0.075, 0.03), dark, 0, 0.08, 0.08);
    }
    add(new THREE.CylinderGeometry(0.008, 0.008, 0.3, 6), accent, 0, -0.02, -0.18, Math.PI / 2);

    const muzzle = new THREE.Object3D();
    muzzle.position.set(0, 0.028, -0.08 - barrelLength - 0.05);
    gun.add(muzzle);
    const flash = new THREE.Mesh(new THREE.SphereGeometry(0.05, 8, 6), flashMat);
    flash.position.copy(muzzle.position);
    flash.visible = false;
    gun.add(flash);
    group.add(gun);

    addToGroup(new THREE.BoxGeometry(0.07, 0.05, 0.12), skinMat, 0.2, -0.22, 0.28, 0.3, 0.06, -0.2);
    addToGroup(new THREE.BoxGeometry(0.07, 0.05, 0.12), gloveMat, -0.28, -0.21, 0.24, 0.25, -0.06, 0.2);
    addToGroup(new THREE.BoxGeometry(0.085, 0.32, 0.11), sleeveMat, 0.34, -0.46, 0.38, 0.55, 0, -0.32);
    addToGroup(new THREE.BoxGeometry(0.085, 0.32, 0.11), sleeveMat, -0.38, -0.46, 0.34, 0.55, 0, 0.32);

    return { group, muzzle, magPivot, flash };
  }

  #buildRocketLauncherViewmodel(gun, add, addToGroup, steel, dark, accent, gripMat, flashMat, skinMat, sleeveMat, gloveMat) {
    add(new THREE.CylinderGeometry(0.045, 0.045, 0.76, 10), dark, 0, 0.02, -0.38, Math.PI / 2);
    add(new THREE.CylinderGeometry(0.052, 0.052, 0.1, 10), steel, 0, 0.02, -0.79, Math.PI / 2);
    add(new THREE.CylinderGeometry(0.048, 0.048, 0.18, 10), accent, 0, 0.02, -0.9, Math.PI / 2);
    add(new THREE.BoxGeometry(0.09, 0.12, 0.26), steel, 0, -0.015, 0.24);
    add(new THREE.BoxGeometry(0.08, 0.16, 0.1), gripMat, 0, -0.11, 0.1, 0.22);
    add(new THREE.BoxGeometry(0.02, 0.06, 0.12), accent, 0, 0.1, -0.22);
    add(new THREE.BoxGeometry(0.02, 0.06, 0.12), accent, 0, 0.1, 0.16);
    addToGroup(new THREE.BoxGeometry(0.08, 0.06, 0.14), skinMat, 0.22, -0.22, 0.3, 0.28, 0.06, -0.2);
    addToGroup(new THREE.BoxGeometry(0.08, 0.06, 0.14), gloveMat, -0.3, -0.2, 0.26, 0.25, -0.06, 0.2);
    addToGroup(new THREE.BoxGeometry(0.09, 0.34, 0.12), sleeveMat, 0.38, -0.48, 0.4, 0.55, 0, -0.32);
    addToGroup(new THREE.BoxGeometry(0.09, 0.34, 0.12), sleeveMat, -0.42, -0.48, 0.36, 0.55, 0, 0.32);
    const muzzle = new THREE.Object3D();
    muzzle.position.set(0, 0.02, -0.96);
    gun.add(muzzle);
    const flash = new THREE.Mesh(new THREE.SphereGeometry(0.09, 8, 6), flashMat);
    flash.position.copy(muzzle.position);
    flash.visible = false;
    gun.add(flash);
    return { muzzle, magPivot: null, flash };
  }

  #buildGrenadeViewmodel(gun, add, addToGroup, steel, dark, accent, flashMat, skinMat, sleeveMat, gloveMat) {
    add(new THREE.SphereGeometry(0.085, 10, 8), dark, 0, -0.02, -0.3);
    add(new THREE.BoxGeometry(0.05, 0.1, 0.05), steel, 0, 0.08, -0.3);
    add(new THREE.CylinderGeometry(0.012, 0.012, 0.08, 6), accent, 0, 0.14, -0.3);
    add(new THREE.TorusGeometry(0.035, 0.006, 6, 10), accent, 0, 0.09, -0.3, Math.PI / 2, 0, 0);
    addToGroup(new THREE.BoxGeometry(0.08, 0.06, 0.14), skinMat, 0.22, -0.22, 0.32, 0.28, 0.06, -0.2);
    addToGroup(new THREE.BoxGeometry(0.08, 0.06, 0.14), gloveMat, -0.28, -0.21, 0.28, 0.25, -0.06, 0.2);
    addToGroup(new THREE.BoxGeometry(0.09, 0.34, 0.12), sleeveMat, 0.38, -0.48, 0.4, 0.55, 0, -0.32);
    addToGroup(new THREE.BoxGeometry(0.09, 0.34, 0.12), sleeveMat, -0.42, -0.48, 0.36, 0.55, 0, 0.32);
    const muzzle = new THREE.Object3D();
    muzzle.position.set(0, -0.02, -0.42);
    gun.add(muzzle);
    const flash = new THREE.Mesh(new THREE.SphereGeometry(0.045, 8, 6), flashMat);
    flash.position.copy(muzzle.position);
    flash.visible = false;
    gun.add(flash);
    return { muzzle, magPivot: null, flash };
  }
}
