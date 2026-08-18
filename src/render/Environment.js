import * as THREE from 'three';
import { seededRandom } from '../core/Noise.js';
import { createTextureSet } from '../core/Textures.js';

const UP = new THREE.Vector3(0, 1, 0);
const FRONT = new THREE.Vector3(0, 0, 1);

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

const FLAG_VERTEX = `
  varying vec2 vUv;
  uniform float uTime;
  uniform float uWind;
  void main() {
    vec3 pos = position;
    float anchor = smoothstep(0.0, 0.16, uv.x);
    pos.z += sin(uv.x * 9.0 - uTime * 5.0 + uv.y * 2.6) * 0.09 * uWind * anchor;
    pos.y += sin(uv.x * 6.0 - uTime * 3.1 + uv.y * 1.5) * 0.025 * uWind * anchor;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
  }
`;

const FLAG_FRAGMENT = `
  varying vec2 vUv;
  uniform vec3 uColor;
  void main() {
    gl_FragColor = vec4(uColor, 1.0);
  }
`;

export class EnvironmentSystem {
  constructor(scene, physics, terrain, quality = {}) {
    this.scene = scene;
    this.physics = physics;
    this.terrain = terrain;
    this.quality = quality;
    this.group = new THREE.Group();
    scene.add(this.group);
    this._shadows = quality.shadows !== false && (quality.shadowMapSize || 1024) > 0;
    this._physicsId = 0;
    this.occupiedSpaces = [];
    this.cullables = [];
    this.flags = [];
    this.fires = [];
    this.decalMeshes = [];
    this.buildings = [];
    this.dustSprites = [];
    this.foregroundCraters = [];
    this._dummy = new THREE.Object3D();
    this._sandbagMatrices = [];
    this._containerBodyMatrices = [];
    this._containerRibMatrices = [];
    this._vehicleWheelMatrices = [];
    this._towerLegMatrices = [];
    this._wirePostMatrices = [];
    this._wireMatrices = [];
    this._spikeMatrices = [];
    this._debrisMatrices = [];
    this._tireMatrices = [];
    this._lowWallMatrices = [];
    this._rimMatrices = [];
    this._fillDir = new THREE.Vector3();
    this.groundFillLight = new THREE.PointLight(0xd8b189, 1.3, 10, 2);
    this.group.add(this.groundFillLight);
    this._buildMaterials();
    this._build();
    this._buildVegetation();
    this._buildDecals();
  }

  _uv2(geometry) {
    const uv = geometry.getAttribute('uv');
    if (uv && !geometry.getAttribute('uv2')) {
      geometry.setAttribute('uv2', new THREE.BufferAttribute(new Float32Array(uv.array), 2));
    }
    return geometry;
  }

  _box(w, h, d, material) {
    const mesh = new THREE.Mesh(this._uv2(new THREE.BoxGeometry(w, h, d)), material);
    mesh.castShadow = this._shadows;
    mesh.receiveShadow = true;
    return mesh;
  }

  _cyl(rTop, rBottom, height, segments, material) {
    const mesh = new THREE.Mesh(this._uv2(new THREE.CylinderGeometry(rTop, rBottom, height, segments)), material);
    mesh.castShadow = this._shadows;
    mesh.receiveShadow = true;
    return mesh;
  }

  _mat(type, options = {}) {
    const textures = this.textures[type];
    return new THREE.MeshStandardMaterial({
      map: textures.map,
      normalMap: textures.normalMap,
      roughnessMap: textures.roughnessMap,
      metalnessMap: textures.metalnessMap,
      aoMap: textures.aoMap,
      roughness: options.roughness ?? 0.85,
      metalness: options.metalness ?? 0.05,
      color: options.color ?? 0xffffff,
    });
  }

  _buildMaterials() {
    this.textures = {
      concrete: createTextureSet('concrete', { seed: 101, size: 1024, repeat: 4 }),
      sand: createTextureSet('sand', { seed: 202, size: 1024, repeat: 6 }),
      metal: createTextureSet('metal', { seed: 303, size: 1024, repeat: 3 }),
      wood: createTextureSet('wood', { seed: 404, size: 1024, repeat: 3 }),
      camo: createTextureSet('camo', { seed: 505, size: 1024, repeat: 3 }),
      ground: createTextureSet('ground', { seed: 606, size: 1024, repeat: 6 }),
      asphalt: createTextureSet('asphalt', { seed: 707, size: 1024, repeat: 4 }),
    };
    this.mats = {
      concrete: this._mat('concrete', { roughness: 0.9, metalness: 0.04 }),
      concreteDark: this._mat('concrete', { color: 0x6f7375, roughness: 0.95 }),
      sand: this._mat('sand', { roughness: 0.97 }),
      metal: this._mat('metal', { roughness: 0.42, metalness: 0.9 }),
      metalRust: this._mat('metal', { color: 0x6c6155, roughness: 0.62, metalness: 0.55 }),
      wood: this._mat('wood', { roughness: 0.82 }),
      woodDark: this._mat('wood', { color: 0x4a3626, roughness: 0.85 }),
      camo: this._mat('camo', { roughness: 0.78, metalness: 0.3 }),
      ground: this._mat('ground', { roughness: 0.95, metalness: 0.02 }),
      asphalt: this._mat('asphalt', { roughness: 0.96, metalness: 0.02 }),
      dark: new THREE.MeshStandardMaterial({ color: 0x242424, roughness: 0.9 }),
    };
  }

  _place(obj, x, z, yOffset = 0) {
    obj.position.set(x, this.terrain.heightAt(x, z) + yOffset, z);
    return obj;
  }

  _placeRot(obj, x, z, yOffset = 0, rotY = 0) {
    this._place(obj, x, z, yOffset);
    obj.rotation.y = rotY;
    return obj;
  }

  _collision(x, z, yCenter, hw, hh, hd, options = {}) {
    const id = `env-${this._physicsId++}`;
    return this.physics.addBox(
      id,
      new THREE.Vector3(x, yCenter, z),
      new THREE.Vector3(hw, hh, hd),
      { static: true, userData: { type: options.type || 'static' }, ...options }
    );
  }

  _cull(object, range) {
    this.cullables.push({ object, range });
  }

  _inLake(x, z, margin = 0) {
    const lake = this.terrain.lake;
    return x > lake.x - margin && x < lake.x + lake.w + margin &&
      z > lake.z - margin && z < lake.z + lake.d + margin;
  }

  _insideOccupied(x, z, margin = 0) {
    for (const space of this.occupiedSpaces) {
      if (Math.abs(x - space.x) < space.w / 2 + margin &&
          Math.abs(z - space.z) < space.d / 2 + margin) {
        return true;
      }
    }
    return false;
  }

  _isClear(x, z, margin = 2) {
    if (Math.hypot(x, z) < 13) return false;
    if (this._inLake(x, z, margin)) return false;
    for (const road of this.terrain.roads) {
      if (distToSegment(x, z, road.ax, road.az, road.bx, road.bz) < road.half + 1.2) return false;
    }
    if (this._insideOccupied(x, z, margin)) return false;
    for (const crater of this.terrain.craters) {
      if (Math.hypot(x - crater.x, z - crater.z) < crater.r + 1.2) return false;
    }
    return true;
  }

  _build() {
    this._buildRuinedBuildings();
    this._buildOutpost();
    this._buildContainers();
    this._buildVehicles();
    this._buildWatchtowers();
    this._buildBarrels();
    this._buildFlags();
    this._buildBarbedWire();
    this._buildDunes();
    this._buildCraterDebris();
    this._buildForegroundDressing();
    this._finalizeBatchedStatics();
  }

  _buildRuinedBuildings() {
    const rand = seededRandom(77);
    const specs = [
      { x: 62, z: -62, w: 18, d: 14, h: 9, rot: 0.2 },
      { x: -78, z: -48, w: 14, d: 18, h: 7, rot: -0.3 },
      { x: 48, z: 88, w: 20, d: 12, h: 8, rot: 0.45 },
      { x: -86, z: 76, w: 16, d: 16, h: 10, rot: -0.15 },
      { x: 128, z: 42, w: 12, d: 22, h: 7, rot: 0.6 },
      { x: -44, z: 128, w: 22, d: 12, h: 8, rot: -0.5 },
    ];
    for (const spec of specs) this._buildRuinedBuilding(spec, rand);
  }

  _buildRuinedBuilding(spec, rand) {
    const { x, z, w, d, h, rot } = spec;
    const group = new THREE.Group();
    const baseY = this.terrain.heightAt(x, z);

    const body = this._box(w, h, d, this.mats.concrete);
    body.position.y = baseY + h / 2;
    group.add(body);

    const roof = this._box(w + 1.2, 0.45, d + 1.2, this.mats.concreteDark);
    roof.position.y = baseY + h + 0.22;
    group.add(roof);

    const cw = w * (0.42 + rand() * 0.16);
    const cd = d * (0.42 + rand() * 0.16);
    const ch = h * (0.55 + rand() * 0.2);
    const corner = this._box(cw, ch, cd, this.mats.concreteDark);
    const sx = rand() > 0.5 ? 1 : -1;
    const sz = rand() > 0.5 ? 1 : -1;
    corner.position.set(sx * w * 0.22, baseY + h * 0.55 + ch / 2, sz * d * 0.22);
    corner.rotation.y = rand() * 0.5 - 0.25;
    corner.rotation.z = rand() * 0.12 - 0.06;
    group.add(corner);

    for (let i = 0; i < 5; i += 1) {
      const mat = rand() > 0.5 ? this.mats.concrete : this.mats.wood;
      const debris = this._box(0.6 + rand() * 1.4, 0.3 + rand() * 0.5, 0.6 + rand() * 1.4, mat);
      debris.position.set(
        (rand() - 0.5) * w * 1.5,
        baseY + 0.15 + rand() * 0.4,
        (rand() - 0.5) * d * 1.5
      );
      debris.rotation.y = rand() * Math.PI;
      group.add(debris);
    }

    group.position.set(x, 0, z);
    group.rotation.y = rot;
    this.group.add(group);
    this._collision(x, z, baseY + h / 2, w / 2, h / 2, d / 2, { type: 'building' });
    this.occupiedSpaces.push({ x, z, w: w + 5, d: d + 5 });
    this.buildings.push({ x, z, w, d, h, rot });
    this._cull(group, 340);
  }

  _buildOutpost() {
    const rand = seededRandom(88);
    const sandbags = [
      { x: 10, z: 6, rot: 0.4 },
      { x: -10, z: -7, rot: -0.3 },
      { x: 9, z: -14, rot: 1.9 },
      { x: -15, z: 9, rot: -1.2 },
      { x: -5, z: 16, rot: 2.4 },
      { x: 17, z: -5, rot: 0.9 },
    ];
    for (const s of sandbags) this._makeSandbagEmplacement(s.x, s.z, s.rot, rand);

    const walls = [
      [18, 0, 0], [-18, 0, 0], [0, 18, Math.PI / 2], [0, -18, Math.PI / 2],
      [13, 13, Math.PI / 4], [-13, 13, -Math.PI / 4],
      [13, -13, -Math.PI / 4], [-13, -13, Math.PI / 4],
    ];
    for (const [wx, wz, wr] of walls) this._makeBlastWall(wx, wz, wr);
  }

  _makeSandbagEmplacement(x, z, rotY, rand) {
    const group = new THREE.Group();
    const bagGeo = this._uv2(new THREE.CylinderGeometry(0.3, 0.3, 0.62, 8));
    for (let row = 0; row < 2; row += 1) {
      const zOff = row === 0 ? -0.3 : 0.3;
      for (let i = 0; i < 8; i += 1) {
        const bag = new THREE.Mesh(bagGeo, this.mats.sand);
        bag.position.set((i - 3.5) * 0.56, 0.32, zOff);
        bag.rotation.set(Math.PI / 2, rand() * Math.PI, (rand() - 0.5) * 0.25);
        bag.scale.set(1, 1, 0.85 + rand() * 0.3);
        bag.castShadow = this._shadows;
        bag.receiveShadow = true;
        group.add(bag);
      }
    }
    this._placeRot(group, x, z, 0, rotY);
    group.updateMatrixWorld(true);
    group.traverse((child) => {
      if (child.isMesh) this._sandbagMatrices.push(child.matrixWorld.clone());
    });
    this._collision(x, z, this.terrain.heightAt(x, z) + 0.35, 2.6, 0.35, 1, { type: 'sandbag' });
    this.occupiedSpaces.push({ x, z, w: 5.5, d: 2 });
  }

  _makeBlastWall(x, z, rotY) {
    const wall = this._box(6, 3.4, 0.7, this.mats.concreteDark);
    wall.position.y = this.terrain.heightAt(x, z) + 1.7;
    wall.rotation.y = rotY;
    this.group.add(wall);
    this._collision(x, z, this.terrain.heightAt(x, z) + 1.7, 3, 1.7, 0.5, { type: 'wall' });
    this.occupiedSpaces.push({ x, z, w: 7, d: 2.5 });
    this._cull(wall, 300);
  }

  _buildContainers() {
    const rand = seededRandom(99);
    const specs = [
      { x: 22, z: 5, rot: 0.15, stack: 1 },
      { x: 26, z: -12, rot: -0.2, stack: 2 },
      { x: -20, z: -8, rot: 0.35, stack: 1 },
      { x: -27, z: 14, rot: -0.4, stack: 1 },
      { x: 12, z: -25, rot: 1.4, stack: 1 },
      { x: 42, z: 30, rot: 0.6, stack: 2 },
    ];
    for (const spec of specs) this._makeContainer(spec.x, spec.z, spec.rot, spec.stack, rand);
  }

  _makeContainer(x, z, rotY, stack, rand) {
    const group = new THREE.Group();
    for (let s = 0; s < stack; s += 1) {
      const body = this._box(6.1, 2.6, 2.4, this.mats.metal);
      body.position.y = 1.3 + s * 2.7;
      body.userData.batch = 'containerBody';
      group.add(body);
      for (let rib = 0; rib < 4; rib += 1) {
        const ribMesh = this._box(6.25, 0.14, 0.18, this.mats.dark);
        ribMesh.position.set(0, 2.65 + s * 2.7, -0.9 + rib * 0.6);
        ribMesh.userData.batch = 'containerRib';
        group.add(ribMesh);
      }
    }
    this._placeRot(group, x, z, 0, rotY);
    group.updateMatrixWorld(true);
    group.traverse((child) => {
      if (!child.isMesh) return;
      const matrix = child.matrixWorld.clone();
      if (child.userData.batch === 'containerBody') this._containerBodyMatrices.push(matrix);
      else if (child.userData.batch === 'containerRib') this._containerRibMatrices.push(matrix);
    });
    const baseY = this.terrain.heightAt(x, z);
    for (let s = 0; s < stack; s += 1) {
      this._collision(x, z, baseY + 1.3 + s * 2.7, 3.05, 1.3, 1.2, { type: 'container' });
    }
    this.occupiedSpaces.push({ x, z, w: 7, d: 4 });
  }

  _buildVehicles() {
    const rand = seededRandom(110);
    const specs = [
      { x: 34, z: -10, rot: 0.8 },
      { x: -30, z: -20, rot: -0.5 },
      { x: 26, z: 22, rot: 2 },
      { x: -40, z: 24, rot: 1.2 },
      { x: 64, z: -46, rot: 0.2 },
    ];
    for (const spec of specs) this._makeVehicle(spec.x, spec.z, spec.rot, rand);
  }

  _makeVehicle(x, z, rotY, rand) {
    const group = new THREE.Group();
    const body = this._box(4.6, 1.15, 2.3, this.mats.camo);
    body.position.y = 0.85;
    body.rotation.z = (rand() - 0.5) * 0.08;
    group.add(body);

    const cabin = this._box(1.5, 1, 2.3, this.mats.metalRust);
    cabin.position.set(-1.35, 1.5, 0);
    group.add(cabin);

    const wheelDummies = [];
    for (const [wx, wz] of [[-1.35, -1.15], [1.35, -1.15], [-1.35, 1.15], [1.35, 1.15]]) {
      const wheelDummy = new THREE.Object3D();
      wheelDummy.position.set(wx, 0.42, wz);
      group.add(wheelDummy);
      wheelDummies.push(wheelDummy);
    }

    if (rand() > 0.55) {
      const turret = this._box(1.2, 0.55, 1.6, this.mats.metalRust);
      turret.position.set(0.5, 1.7, 0);
      group.add(turret);
      const barrel = this._cyl(0.08, 0.1, 2.2, 8, this.mats.metal);
      barrel.rotation.z = -Math.PI / 2;
      barrel.position.set(1.7, 1.75, 0);
      group.add(barrel);
    }

    this._placeRot(group, x, z, 0, rotY);
    group.updateMatrixWorld(true);
    for (const wheelDummy of wheelDummies) {
      this._vehicleWheelMatrices.push(wheelDummy.matrixWorld.clone());
      group.remove(wheelDummy);
    }
    this.group.add(group);
    this._collision(x, z, this.terrain.heightAt(x, z) + 0.85, 2.3, 0.85, 1.15, { type: 'vehicle' });
    this.occupiedSpaces.push({ x, z, w: 5.5, d: 3.5 });
    this._cull(group, 260);
  }

  _buildWatchtowers() {
    const specs = [
      { x: -116, z: -148, rot: 0.7 },
      { x: -132, z: 116, rot: -0.6 },
    ];
    for (const spec of specs) this._makeWatchtower(spec.x, spec.z, spec.rot);
  }

  _makeWatchtower(x, z, rotY) {
    const group = new THREE.Group();
    const legDummies = [];
    for (const [lx, lz] of [[-1.7, -1.7], [1.7, -1.7], [-1.7, 1.7], [1.7, 1.7]]) {
      const legDummy = new THREE.Object3D();
      legDummy.position.set(lx, 2.7, lz);
      group.add(legDummy);
      legDummies.push(legDummy);
    }
    const platform = this._box(4.2, 0.25, 4.2, this.mats.wood);
    platform.position.y = 5.15;
    group.add(platform);
    for (const [rx, rz] of [[0, -2.1], [0, 2.1], [-2.1, 0], [2.1, 0]]) {
      const rail = this._box(4.4, 0.7, 0.12, this.mats.metalRust);
      rail.position.set(rx, 5.6, rz);
      if (rz === 0) rail.rotation.y = Math.PI / 2;
      group.add(rail);
    }
    const roof = this._box(3.4, 0.2, 3.4, this.mats.concreteDark);
    roof.position.y = 6.15;
    group.add(roof);

    this._placeRot(group, x, z, 0, rotY);
    group.updateMatrixWorld(true);
    for (const legDummy of legDummies) {
      this._towerLegMatrices.push(legDummy.matrixWorld.clone());
      group.remove(legDummy);
    }
    this.group.add(group);
    this._collision(x, z, this.terrain.heightAt(x, z) + 2.6, 1.8, 2.6, 1.8, { type: 'watchtower' });
    this.occupiedSpaces.push({ x, z, w: 4.5, d: 4.5 });
    this._cull(group, 320);
  }

  _buildBarrels() {
    const rand = seededRandom(120);
    const specs = [
      [-9, -4], [7, 11], [21, 15], [-21, -13],
      [0, 19], [-17, 17], [15, -19],
    ];
    for (const [x, z] of specs) this._makeBarrel(x, z, rand);
  }

  _radialTexture(size, stops) {
    const canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext('2d');
    const gradient = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
    stops.forEach((stop, i) => gradient.addColorStop(i / (stops.length - 1), stop));
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, size, size);
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.NoColorSpace;
    return texture;
  }

  _makeBarrel(x, z, rand) {
    const group = new THREE.Group();
    const barrel = this._cyl(0.38, 0.38, 0.95, 12, this.mats.metalRust);
    barrel.position.y = 0.48;
    group.add(barrel);
    const rim = this._cyl(0.4, 0.4, 0.1, 12, this.mats.dark);
    rim.position.y = 0.93;
    group.add(rim);

    const fireTex = this._radialTexture(64, [
      'rgba(255,240,190,0.95)', 'rgba(255,160,50,0.75)',
      'rgba(255,70,10,0.28)', 'rgba(255,40,5,0)',
    ]);
    const smokeTex = this._radialTexture(64, [
      'rgba(190,190,190,0.55)', 'rgba(130,130,130,0.3)',
      'rgba(70,70,70,0.12)', 'rgba(40,40,40,0)',
    ]);
    const fire = [];
    const smoke = [];
    for (let i = 0; i < 3; i += 1) {
      const sprite = new THREE.Sprite(new THREE.SpriteMaterial({
        map: fireTex,
        color: 0xffaa44,
        transparent: true,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
      }));
      sprite.position.set((i - 1) * 0.12, 1.05 + i * 0.12, 0);
      sprite.scale.set(0.7 + i * 0.1, 0.9 + i * 0.12, 1);
      group.add(sprite);
      fire.push(sprite);
    }
    for (let i = 0; i < 4; i += 1) {
      const sprite = new THREE.Sprite(new THREE.SpriteMaterial({
        map: smokeTex,
        color: 0x9a9a9a,
        transparent: true,
        opacity: 0.45,
        depthWrite: false,
      }));
      sprite.position.set(i % 2 === 0 ? -0.25 : 0.25, 1.3 + i * 0.5, 0);
      sprite.scale.set(0.8 + i * 0.45, 0.8 + i * 0.45, 1);
      group.add(sprite);
      smoke.push(sprite);
    }

    this._placeRot(group, x, z, 0, rand() * Math.PI);
    this.group.add(group);
    this._collision(x, z, this.terrain.heightAt(x, z) + 0.45, 0.42, 0.5, 0.42, { type: 'barrel' });
    this.occupiedSpaces.push({ x, z, w: 1.5, d: 1.5 });
    this.fires.push({
      group,
      fire,
      smoke,
      phase: rand() * 10,
      base: 0.8,
      smokeBase: 1.25,
      smokeHeight: 5.5,
    });
    this._cull(group, 180);
  }

  _buildFlags() {
    const rand = seededRandom(130);
    const specs = [
      [-3, 3, 0xd8b23a],
      [10, 6, 0x8a9a3a],
      [-15, 9, 0x3a5f8a],
    ];
    for (const [x, z, color] of specs) this._makeFlag(x, z, color, rand);
  }

  _makeFlag(x, z, color, rand) {
    const group = new THREE.Group();
    const pole = this._cyl(0.045, 0.06, 4.4, 6, this.mats.woodDark);
    pole.position.y = 2.2;
    group.add(pole);
    const material = new THREE.ShaderMaterial({
      uniforms: {
        uTime: { value: 0 },
        uColor: { value: new THREE.Color(color) },
        uWind: { value: 1 },
      },
      vertexShader: FLAG_VERTEX,
      fragmentShader: FLAG_FRAGMENT,
      side: THREE.DoubleSide,
    });
    const flag = new THREE.Mesh(this._uv2(new THREE.PlaneGeometry(1.5, 0.85, 14, 7)), material);
    flag.position.set(0.75, 3.45, 0);
    group.add(flag);
    this._placeRot(group, x, z, 0, rand() * Math.PI * 2);
    this.group.add(group);
    this.flags.push({ group, material, phase: rand() * 10 });
    this._cull(group, 320);
  }

  _buildBarbedWire() {
    const rand = seededRandom(140);
    const specs = [
      [-40, -6, 40, -6],
      [-40, -5.2, 40, -5.2],
      [6, -40, 6, 40],
      [6.8, -40, 6.8, 40],
    ];
    for (const spec of specs) this._makeBarbedWire(spec[0], spec[1], spec[2], spec[3], rand);
  }

  _makeBarbedWire(x1, z1, x2, z2, rand) {
    const group = new THREE.Group();
    const length = Math.hypot(x2 - x1, z2 - z1);
    const midX = (x1 + x2) / 2;
    const midZ = (z1 + z2) / 2;
    const angle = Math.atan2(z2 - z1, x2 - x1);

    const postGeo = this._uv2(new THREE.CylinderGeometry(0.06, 0.08, 1.3, 5));
    for (const sign of [-1, 1]) {
      const post = new THREE.Mesh(postGeo, this.mats.woodDark);
      post.position.set(sign * length / 2, 0.65, 0);
      post.userData.batch = 'wirePost';
      group.add(post);
    }

    const wireGeo = this._uv2(new THREE.CylinderGeometry(0.012, 0.012, length, 4));
    wireGeo.rotateZ(Math.PI / 2);
    for (const y of [0.55, 0.85, 1.12]) {
      const wire = new THREE.Mesh(wireGeo, this.mats.metal);
      wire.position.set(0, y, 0);
      wire.userData.batch = 'wire';
      group.add(wire);
    }

    const spikeGeo = this._uv2(new THREE.ConeGeometry(0.022, 0.1, 4));
    for (let i = 0; i < 7; i += 1) {
      const spike = new THREE.Mesh(spikeGeo, this.mats.metalRust);
      const t = (rand() * 2 - 1) * length * 0.42;
      spike.position.set(t, [0.55, 0.85, 1.12][Math.floor(rand() * 3)], rand() * 0.15 - 0.075);
      spike.rotation.set(rand() * 0.8 - 0.4, rand() * Math.PI, rand() * 0.8 - 0.4);
      spike.userData.batch = 'spike';
      group.add(spike);
    }

    this._placeRot(group, midX, midZ, 0, angle);
    group.updateMatrixWorld(true);
    group.traverse((child) => {
      if (!child.isMesh) return;
      const matrix = child.matrixWorld.clone();
      if (child.userData.batch === 'wirePost') this._wirePostMatrices.push(matrix);
      else if (child.userData.batch === 'wire') this._wireMatrices.push(matrix);
      else if (child.userData.batch === 'spike') this._spikeMatrices.push(matrix);
    });
  }

  _buildDunes() {
    const rand = seededRandom(150);
    const specs = [
      [-120, -140, 0.4], [150, 100, -0.3], [-30, 130, 0.9], [100, -80, -0.7],
    ];
    for (const [x, z, rot] of specs) this._makeDune(x, z, rot, rand);
  }

  _makeDune(x, z, rot, rand) {
    const dune = new THREE.Mesh(this._uv2(new THREE.SphereGeometry(10, 16, 10)), this.mats.sand);
    dune.scale.set(1, 0.35 + rand() * 0.12, 1.2);
    dune.position.set(x, this.terrain.heightAt(x, z) - 0.4, z);
    dune.rotation.y = rot;
    dune.receiveShadow = true;
    dune.castShadow = this._shadows;
    this.group.add(dune);
    this.occupiedSpaces.push({ x, z, w: 20, d: 22 });
    this._cull(dune, 320);
  }

  _buildCraterDebris() {
    const rand = seededRandom(909);
    for (const crater of this.terrain.craters) {
      if (this._inLake(crater.x, crater.z, 4) || rand() > 0.6) continue;
      const count = 2 + Math.floor(rand() * 3);
      for (let i = 0; i < count; i += 1) {
        const angle = rand() * Math.PI * 2;
        const radius = crater.r * (0.7 + rand() * 0.45);
        const px = crater.x + Math.cos(angle) * radius;
        const pz = crater.z + Math.sin(angle) * radius;
        const w = 0.5 + rand() * 1.2;
        const h = 0.25 + rand() * 0.5;
        const d = 0.5 + rand() * 1.2;
        this._dummy.position.set(px, this.terrain.heightAt(px, pz) + h * 0.5, pz);
        this._dummy.rotation.set(0, rand() * Math.PI, 0);
        this._dummy.scale.set(w, h, d);
        this._dummy.updateMatrix();
        this._debrisMatrices.push({
          matrix: this._dummy.matrix.clone(),
          color: rand() > 0.5 ? 0x8a8d8e : 0x77553a,
        });
      }
    }
  }

  _makePlantGeometry(planes = 4) {
    const key = `plant-${planes}`;
    if (!this._plantGeometries) this._plantGeometries = {};
    if (this._plantGeometries[key]) return this._plantGeometries[key];
    const positions = new Float32Array(planes * 4 * 3);
    const uvs = new Float32Array(planes * 4 * 2);
    const indices = [];
    for (let p = 0; p < planes; p += 1) {
      const angle = p * Math.PI / planes;
      const dx = Math.cos(angle);
      const dz = Math.sin(angle);
      const nx = -dz;
      const nz = dx;
      const offset = (p % 2 === 0 ? 1 : -1) * 0.0016;
      const base = p * 4;
      positions[base * 3] = -0.5 * dx + nx * offset;
      positions[base * 3 + 1] = 0;
      positions[base * 3 + 2] = -0.5 * dz + nz * offset;
      positions[(base + 1) * 3] = 0.5 * dx + nx * offset;
      positions[(base + 1) * 3 + 1] = 0;
      positions[(base + 1) * 3 + 2] = 0.5 * dz + nz * offset;
      positions[(base + 2) * 3] = 0.5 * dx + nx * offset;
      positions[(base + 2) * 3 + 1] = 1;
      positions[(base + 2) * 3 + 2] = 0.5 * dz + nz * offset;
      positions[(base + 3) * 3] = -0.5 * dx + nx * offset;
      positions[(base + 3) * 3 + 1] = 1;
      positions[(base + 3) * 3 + 2] = -0.5 * dz + nz * offset;
      for (let i = 0; i < 4; i += 1) {
        uvs[(base + i) * 2] = i === 1 || i === 2 ? 1 : 0;
        uvs[(base + i) * 2 + 1] = i < 2 ? 0 : 1;
      }
      indices.push(base, base + 1, base + 2, base, base + 2, base + 3);
    }
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute('uv', new THREE.BufferAttribute(uvs, 2));
    geometry.setIndex(indices);
    geometry.computeVertexNormals();
    this._plantGeometries[key] = this._uv2(geometry);
    return this._plantGeometries[key];
  }

  _vegetationNormalTexture(canvas, strength) {
    const size = canvas.width;
    const src = canvas.getContext('2d').getImageData(0, 0, size, size).data;
    const out = document.createElement('canvas');
    out.width = size;
    out.height = size;
    const octx = out.getContext('2d');
    const data = octx.createImageData(size, size);
    const idx = (x, y) => (((y + size) % size) * size + ((x + size) % size)) * 4;
    const lum = (i) => src[i] * 0.3 + src[i + 1] * 0.59 + src[i + 2] * 0.11;
    for (let y = 0; y < size; y += 1) {
      for (let x = 0; x < size; x += 1) {
        const i = (y * size + x) * 4;
        const l = lum(idx(x - 1, y));
        const r = lum(idx(x + 1, y));
        const u = lum(idx(x, y - 1));
        const d = lum(idx(x, y + 1));
        const dx = (r - l) / 255 * strength;
        const dy = (u - d) / 255 * strength;
        const len = Math.sqrt(dx * dx + dy * dy + 1);
        data.data[i] = (dx / len * 0.5 + 0.5) * 255;
        data.data[i + 1] = (dy / len * 0.5 + 0.5) * 255;
        data.data[i + 2] = (1 / len * 0.5 + 0.5) * 255;
        data.data[i + 3] = 255;
      }
    }
    octx.putImageData(data, 0, 0);
    const texture = new THREE.CanvasTexture(out);
    texture.colorSpace = THREE.NoColorSpace;
    return texture;
  }

  _nearSpot(spots, x, z, minDist) {
    for (const spot of spots) {
      if (Math.hypot(spot.x - x, spot.z - z) < minDist) return true;
    }
    return false;
  }

  _sampleSpots(count, rand, margin, minDist, reject) {
    const spots = [];
    let tries = 0;
    const maxTries = Math.max(6000, count * 60);
    while (spots.length < count && tries < maxTries) {
      tries += 1;
      const x = (rand() * 2 - 1) * 185;
      const z = (rand() * 2 - 1) * 185;
      if (!this._isClear(x, z, margin)) continue;
      if (this._nearSpot(spots, x, z, minDist)) continue;
      if (reject && reject(x, z)) continue;
      spots.push({ x, z, scale: 0.7 + rand() * 0.9, rot: rand() * Math.PI * 2 });
    }
    return spots;
  }

  _vegetationTexture(kind, seed) {
    const size = 1024;
    const canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext('2d');
    const rand = seededRandom(seed);
    if (kind === 'grass') {
      for (let i = 0; i < 170; i += 1) {
        const x = size * (0.08 + rand() * 0.84);
        const h = size * (0.42 + rand() * 0.38);
        const lean = (rand() - 0.5) * size * 0.12;
        const shade = 72 + Math.floor(rand() * 58);
        ctx.strokeStyle = `rgba(${Math.floor(shade * 0.72)},${shade},${Math.floor(shade * 0.5)},0.95)`;
        ctx.lineWidth = size * (0.018 + rand() * 0.024);
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(x, size);
        ctx.quadraticCurveTo(x + lean * 0.35, size - h * 0.62, x + lean, size - h);
        ctx.stroke();
      }
    } else if (kind === 'bush') {
      for (let i = 0; i < 64; i += 1) {
        const x = size * (0.16 + rand() * 0.68);
        const y = size * (0.26 + rand() * 0.5);
        const r = size * (0.12 + rand() * 0.2);
        const shade = 48 + Math.floor(rand() * 52);
        const gradient = ctx.createRadialGradient(x, y, r * 0.1, x, y, r);
        gradient.addColorStop(0, `rgba(${shade},${shade + 30},${Math.floor(shade * 0.7)},0.95)`);
        gradient.addColorStop(1, `rgba(${Math.floor(shade * 0.5)},${Math.floor(shade * 0.72)},${Math.floor(shade * 0.38)},0)`);
        ctx.fillStyle = gradient;
        ctx.beginPath();
        ctx.arc(x, y, r, 0, Math.PI * 2);
        ctx.fill();
      }
    } else {
      ctx.fillStyle = 'rgba(72,54,40,0.96)';
      ctx.fillRect(size * 0.46, size * 0.32, size * 0.08, size * 0.68);
      ctx.strokeStyle = 'rgba(72,54,40,0.95)';
      ctx.lineCap = 'round';
      for (let i = 0; i < 96; i += 1) {
        const startY = size * (0.24 + rand() * 0.38);
        const angle = -Math.PI * 0.45 - rand() * Math.PI * 0.55;
        const len = size * (0.12 + rand() * 0.24);
        ctx.lineWidth = size * (0.02 + rand() * 0.026);
        ctx.beginPath();
        ctx.moveTo(size * 0.5 + (rand() - 0.5) * size * 0.06, startY);
        ctx.quadraticCurveTo(
          size * 0.5 + Math.cos(angle) * len * 0.4,
          startY + Math.sin(angle) * len * 0.4,
          size * 0.5 + Math.cos(angle) * len,
          startY + Math.sin(angle) * len
        );
        ctx.stroke();
      }
    }
    ctx.globalCompositeOperation = 'destination-in';
    const fadeX = size * 0.5;
    const fadeY = size * 0.55;
    const fade = ctx.createRadialGradient(fadeX, fadeY, size * 0.05, fadeX, fadeY, size * 0.52);
    fade.addColorStop(0, 'rgba(0,0,0,1)');
    fade.addColorStop(0.78, 'rgba(0,0,0,0.9)');
    fade.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = fade;
    ctx.fillRect(0, 0, size, size);
    ctx.globalCompositeOperation = 'source-over';
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.wrapS = THREE.ClampToEdgeWrapping;
    texture.wrapT = THREE.ClampToEdgeWrapping;
    return { map: texture, normalMap: this._vegetationNormalTexture(canvas, 1.35) };
  }

  _splitSpots(spots, count) {
    const chunks = Array.from({ length: count }, () => []);
    for (let i = 0; i < spots.length; i += 1) chunks[i % count].push(spots[i]);
    return chunks;
  }

  _addVegetationInstances(kind, spots, planes, seed, castShadow, hue) {
    if (!spots.length) return;
    const atlas = this._vegetationTexture(kind, seed);
    const material = new THREE.MeshStandardMaterial({
      map: atlas.map,
      normalMap: atlas.normalMap,
      alphaTest: 0.32,
      side: THREE.DoubleSide,
      roughness: 0.9,
      metalness: 0,
      polygonOffset: true,
      polygonOffsetFactor: 1,
      polygonOffsetUnits: 1,
    });
    const mesh = new THREE.InstancedMesh(this._makePlantGeometry(planes), material, spots.length);
    const matrix = new THREE.Matrix4();
    const position = new THREE.Vector3();
    const quaternion = new THREE.Quaternion();
    const scale = new THREE.Vector3();
    const color = new THREE.Color();
    const rand = seededRandom(seed + 17);
    const scaleBase = kind === 'grass' ? 0.85 : kind === 'bush' ? 2.2 : 4.2;
    for (let i = 0; i < spots.length; i += 1) {
      const spot = spots[i];
      const s = spot.scale * scaleBase * (0.85 + rand() * 0.3);
      position.set(spot.x, this.terrain.heightAt(spot.x, spot.z) + 0.5 * s, spot.z);
      quaternion.setFromAxisAngle(UP, spot.rot + (rand() - 0.5) * 0.4);
      scale.set(s, s, s);
      matrix.compose(position, quaternion, scale);
      mesh.setMatrixAt(i, matrix);
      color.setHSL(hue + (rand() - 0.5) * 0.04, 0.3 + rand() * 0.22, 0.38 + rand() * 0.22);
      mesh.setColorAt(i, color);
    }
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    mesh.castShadow = this._shadows && castShadow;
    mesh.frustumCulled = false;
    this.group.add(mesh);
  }

  _buildVegetation() {
    const density = this.quality.vegetationDensity ?? 1;
    const rand = seededRandom(404);
    const treeCount = Math.floor(85 * density);
    const bushCount = Math.floor(360 * density);
    const grassCount = Math.floor(3200 * density);
    const treeSpots = this._sampleSpots(treeCount, rand, 3, 10, null);
    const bushSpots = this._sampleSpots(
      bushCount,
      rand,
      2,
      4.5,
      (x, z) => this._nearSpot(treeSpots, x, z, 4.5)
    );
    const grassSpots = this._sampleSpots(
      grassCount,
      rand,
      0.9,
      1.1,
      (x, z) => this._nearSpot(bushSpots, x, z, 1.6) || this._nearSpot(treeSpots, x, z, 2.4)
    );

    const grassChunks = this._splitSpots(grassSpots, 3);
    grassChunks.forEach((chunk, i) => this._addVegetationInstances('grass', chunk, 4, 501 + i * 7, false, 0.26));
    const bushChunks = this._splitSpots(bushSpots, 2);
    bushChunks.forEach((chunk, i) => this._addVegetationInstances('bush', chunk, 6, 510 + i * 11, true, 0.3));
    const treeChunks = this._splitSpots(treeSpots, 2);
    treeChunks.forEach((chunk, i) => this._addVegetationInstances('tree', chunk, 6, 520 + i * 13, true, 0.08));
  }

  _addInstancedFromMatrices(geometry, material, matrices, castShadow, receiveShadow) {
    if (!matrices.length) return;
    const mesh = new THREE.InstancedMesh(this._uv2(geometry), material, matrices.length);
    for (let i = 0; i < matrices.length; i += 1) mesh.setMatrixAt(i, matrices[i]);
    mesh.instanceMatrix.needsUpdate = true;
    mesh.castShadow = this._shadows && castShadow;
    mesh.receiveShadow = receiveShadow;
    mesh.frustumCulled = false;
    this.group.add(mesh);
  }

  _finalizeBatchedStatics() {
    this._addInstancedFromMatrices(
      new THREE.CylinderGeometry(0.3, 0.3, 0.62, 8),
      this.mats.sand,
      this._sandbagMatrices,
      true,
      true
    );
    this._addInstancedFromMatrices(
      new THREE.BoxGeometry(6.1, 2.6, 2.4),
      this.mats.metal,
      this._containerBodyMatrices,
      true,
      true
    );
    this._addInstancedFromMatrices(
      new THREE.BoxGeometry(6.25, 0.14, 0.18),
      this.mats.dark,
      this._containerRibMatrices,
      false,
      true
    );
    const wheelGeo = this._uv2(new THREE.CylinderGeometry(0.42, 0.42, 0.42, 10));
    wheelGeo.rotateZ(Math.PI / 2);
    this._addInstancedFromMatrices(wheelGeo, this.mats.dark, this._vehicleWheelMatrices, false, true);
    this._addInstancedFromMatrices(
      new THREE.CylinderGeometry(0.09, 0.13, 5.4, 6),
      this.mats.woodDark,
      this._towerLegMatrices,
      true,
      true
    );
    this._addInstancedFromMatrices(
      new THREE.CylinderGeometry(0.06, 0.08, 1.3, 5),
      this.mats.woodDark,
      this._wirePostMatrices,
      true,
      true
    );
    const wireGeo = this._uv2(new THREE.CylinderGeometry(0.012, 0.012, 80, 4));
    wireGeo.rotateZ(Math.PI / 2);
    this._addInstancedFromMatrices(wireGeo, this.mats.metal, this._wireMatrices, false, false);
    this._addInstancedFromMatrices(
      new THREE.ConeGeometry(0.022, 0.1, 4),
      this.mats.metalRust,
      this._spikeMatrices,
      false,
      false
    );
    this._addInstancedFromMatrices(
      new THREE.TorusGeometry(0.5, 0.18, 8, 14),
      this.mats.dark,
      this._tireMatrices,
      true,
      true
    );
    this._addInstancedFromMatrices(
      new THREE.BoxGeometry(2.4, 0.75, 0.4),
      this.mats.concreteDark,
      this._lowWallMatrices,
      true,
      true
    );
    this._addInstancedFromMatrices(
      new THREE.TorusGeometry(1, 0.14, 6, 28),
      this.mats.concreteDark,
      this._rimMatrices,
      true,
      true
    );

    if (this._debrisMatrices.length) {
      const mesh = new THREE.InstancedMesh(
        this._uv2(new THREE.BoxGeometry(1, 1, 1)),
        this.mats.concrete,
        this._debrisMatrices.length
      );
      const color = new THREE.Color();
      for (let i = 0; i < this._debrisMatrices.length; i += 1) {
        mesh.setMatrixAt(i, this._debrisMatrices[i].matrix);
        mesh.setColorAt(i, color.setHex(this._debrisMatrices[i].color));
      }
      mesh.instanceMatrix.needsUpdate = true;
      if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
      mesh.castShadow = this._shadows;
      mesh.receiveShadow = true;
      mesh.frustumCulled = false;
      this.group.add(mesh);
    }
  }

  _makeTireWall(x, z, rand) {
    const count = 3 + Math.floor(rand() * 3);
    const baseY = this.terrain.heightAt(x, z);
    for (let i = 0; i < count; i += 1) {
      this._dummy.position.set(x + (i - (count - 1) / 2) * 0.62, baseY + 0.32, z);
      this._dummy.rotation.set(Math.PI / 2, rand() * Math.PI, 0);
      this._dummy.scale.set(0.8 + rand() * 0.45, 0.8 + rand() * 0.45, 1);
      this._dummy.updateMatrix();
      this._tireMatrices.push(this._dummy.matrix.clone());
    }
  }

  _makeLowWall(x, z, rotY, rand) {
    this._dummy.position.set(x, this.terrain.heightAt(x, z) + 0.38, z);
    this._dummy.rotation.set((rand() - 0.5) * 0.08, rotY + (rand() - 0.5) * 0.2, 0);
    this._dummy.scale.set(1.1 + rand() * 1.2, 1, 1);
    this._dummy.updateMatrix();
    this._lowWallMatrices.push(this._dummy.matrix.clone());
  }

  _scatterDebris(x, z, count, rand) {
    const baseY = this.terrain.heightAt(x, z);
    for (let i = 0; i < count; i += 1) {
      const w = 0.35 + rand() * 0.9;
      const h = 0.18 + rand() * 0.4;
      const d = 0.35 + rand() * 0.9;
      this._dummy.position.set(x + (rand() - 0.5) * 2.4, baseY + h * 0.5, z + (rand() - 0.5) * 2.4);
      this._dummy.rotation.set((rand() - 0.5) * 0.3, rand() * Math.PI, (rand() - 0.5) * 0.3);
      this._dummy.scale.set(w, h, d);
      this._dummy.updateMatrix();
      this._debrisMatrices.push({
        matrix: this._dummy.matrix.clone(),
        color: rand() > 0.5 ? 0x8a8d8e : 0x77553a,
      });
    }
  }

  _makeDustSprite(x, z, rand) {
    const texture = this._radialTexture(64, [
      'rgba(190,170,130,0.5)', 'rgba(150,130,100,0.2)', 'rgba(100,85,65,0)',
    ]);
    const sprite = new THREE.Sprite(new THREE.SpriteMaterial({
      map: texture,
      color: 0xcbb189,
      transparent: true,
      opacity: 0.28,
      depthWrite: false,
    }));
    const baseY = this.terrain.heightAt(x, z) + 0.7 + rand() * 0.8;
    const base = 1.3 + rand() * 1.8;
    sprite.position.set(x, baseY, z);
    sprite.scale.set(base, base, 1);
    this.group.add(sprite);
    this.dustSprites.push({ sprite, phase: rand() * 10, baseY, base });
  }

  _addCraterRim(x, z, radius, rand) {
    const y = this.terrain.heightAt(x, z);
    for (const [ringScale, tubeScale, yOffset] of [[1, 1, 0.07], [0.74, 0.72, 0.025]]) {
      this._dummy.position.set(x, y + yOffset, z);
      this._dummy.rotation.set(Math.PI / 2, rand() * Math.PI, 0);
      this._dummy.scale.set(radius * ringScale, radius * ringScale, tubeScale * 0.5);
      this._dummy.updateMatrix();
      this._rimMatrices.push(this._dummy.matrix.clone());
    }
  }

  _buildForegroundDressing() {
    const rand = seededRandom(2026);
    const areas = [
      {
        sandbags: [[16, 26, 0.4], [20, 31, -0.2], [26, 38, 0.8]],
        tires: [[13, 23], [21, 32]],
        walls: [[17, 27, 0.3], [23, 34, -0.2]],
        debris: [[15, 25], [19, 30], [24, 36]],
        dust: [[15, 25], [19, 30], [25, 36], [13, 24]],
        craters: [[18, 30, 3.4]],
        occupied: { x: 20, z: 31, w: 24, d: 24 },
        near: {
          sandbags: [[13, 21], [14, 23], [11, 22]],
          tires: [[12, 22]],
          walls: [[13, 20]],
          debris: [[12, 21], [14, 22]],
          dust: [[12, 22], [14, 21]],
        },
      },
      {
        sandbags: [[-4, -8, 0.3], [4, -9, -0.3], [0, -12, 0.6], [-6, -14, -0.4], [7, -15, 0.2]],
        tires: [[-5, -10], [6, -12]],
        walls: [[-7, -13, 0.5], [5, -16, -0.4]],
        debris: [[-3, -8], [3, -11], [0, -14]],
        dust: [[-3, -8], [3, -11], [0, -14]],
        craters: [[-6, -16, 3], [6, -18, 2.6]],
        occupied: { x: 0, z: -12, w: 24, d: 22 },
        near: {
          sandbags: [[-2, -3], [2, -4], [0, -5]],
          tires: [[-3, -4]],
          walls: [[-4, -4]],
          debris: [[-2, -5], [3, -5]],
          dust: [[-2, -4], [2, -5]],
        },
      },
      {
        sandbags: [[-13, 18, -0.3], [-9, 23, 0.4], [-3, 29, -0.2]],
        tires: [[-11, 20], [-5, 26]],
        walls: [[-14, 22, 0.6], [-7, 28, -0.3]],
        debris: [[-10, 19], [-4, 25]],
        dust: [[-12, 21], [-6, 27], [-1, 32]],
        craters: [[-8, 28, 3.2]],
        occupied: { x: -8, z: 24, w: 22, d: 22 },
        near: {
          sandbags: [[-17, 16], [-16, 18], [-19, 17]],
          tires: [[-17, 17]],
          walls: [[-18, 15]],
          debris: [[-16, 16], [-18, 18]],
          dust: [[-17, 17], [-15, 16]],
        },
      },
    ];

    for (const area of areas) {
      for (const [x, z, rot] of area.sandbags) this._makeSandbagEmplacement(x, z, rot, rand);
      for (const [x, z] of area.tires) this._makeTireWall(x, z, rand);
      for (const [x, z, rot] of area.walls) this._makeLowWall(x, z, rot, rand);
      for (const [x, z] of area.debris) this._scatterDebris(x, z, 2 + Math.floor(rand() * 3), rand);
      for (const [x, z, radius] of area.craters) {
        this.foregroundCraters.push({ x, z, r: radius });
        this._addCraterRim(x, z, radius, rand);
      }
      for (const [x, z] of area.dust) this._makeDustSprite(x, z, rand);
      if (area.near) {
        for (const [x, z, rot] of area.near.sandbags) this._makeSandbagEmplacement(x, z, rot, rand);
        for (const [x, z] of area.near.tires) this._makeTireWall(x, z, rand);
        for (const [x, z, rot] of area.near.walls) this._makeLowWall(x, z, rot, rand);
        for (const [x, z] of area.near.debris) this._scatterDebris(x, z, 2 + Math.floor(rand() * 2), rand);
        for (const [x, z] of area.near.dust) this._makeDustSprite(x, z, rand);
      }
      if (area.occupied) this.occupiedSpaces.push(area.occupied);
    }
  }

  _decalTexture(kind, size, seed) {
    const canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext('2d');
    const rand = seededRandom(seed);
    const cx = size / 2;
    const cy = size / 2;
    if (kind === 'bullet') {
      const radius = size * 0.16;
      ctx.fillStyle = 'rgba(8,8,10,0.94)';
      ctx.beginPath();
      for (let i = 0; i <= 26; i += 1) {
        const a = i / 26 * Math.PI * 2;
        const r = radius * (0.78 + rand() * 0.42);
        const px = cx + Math.cos(a) * r;
        const py = cy + Math.sin(a) * r;
        if (i === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = 'rgba(190,190,190,0.35)';
      ctx.lineWidth = 1.2;
      ctx.stroke();
      ctx.fillStyle = 'rgba(255,255,255,0.18)';
      ctx.beginPath();
      ctx.arc(cx - radius * 0.3, cy - radius * 0.3, radius * 0.3, 0, Math.PI * 2);
      ctx.fill();
    } else if (kind === 'scorch') {
      const gradient = ctx.createRadialGradient(cx, cy, 0, cx, cy, size / 2);
      gradient.addColorStop(0, 'rgba(12,10,10,0.92)');
      gradient.addColorStop(0.42, 'rgba(28,22,18,0.7)');
      gradient.addColorStop(0.78, 'rgba(60,45,32,0.28)');
      gradient.addColorStop(1, 'rgba(60,45,32,0)');
      ctx.fillStyle = gradient;
      ctx.fillRect(0, 0, size, size);
      for (let i = 0; i < 8; i += 1) {
        const a = rand() * Math.PI * 2;
        const r = size * (0.12 + rand() * 0.28);
        ctx.fillStyle = `rgba(10,8,8,${0.25 + rand() * 0.3})`;
        ctx.beginPath();
        ctx.arc(cx + Math.cos(a) * r * 0.55, cy + Math.sin(a) * r * 0.55, r * 0.35, 0, Math.PI * 2);
        ctx.fill();
      }
    } else {
      ctx.strokeStyle = 'rgba(12,12,14,0.72)';
      ctx.lineWidth = 1.5;
      ctx.lineCap = 'round';
      const branches = 4 + Math.floor(rand() * 4);
      for (let i = 0; i < branches; i += 1) {
        const a = rand() * Math.PI * 2;
        const len = size * (0.15 + rand() * 0.28);
        let x = cx;
        let y = cy;
        ctx.beginPath();
        ctx.moveTo(x, y);
        let angle = a;
        for (let s = 0; s < 5; s += 1) {
          angle += (rand() - 0.5) * 1.1;
          const step = len * 0.24;
          x += Math.cos(angle) * step;
          y += Math.sin(angle) * step;
          ctx.lineTo(x, y);
        }
        ctx.stroke();
      }
    }
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.NoColorSpace;
    texture.wrapS = THREE.ClampToEdgeWrapping;
    texture.wrapT = THREE.ClampToEdgeWrapping;
    return texture;
  }

  _makeDecalMesh(kind, count) {
    const mesh = new THREE.InstancedMesh(
      this._uv2(new THREE.PlaneGeometry(1, 1)),
      new THREE.MeshBasicMaterial({
        map: this.decalTextures[kind],
        transparent: true,
        depthWrite: false,
        polygonOffset: true,
        polygonOffsetFactor: -2,
        polygonOffsetUnits: -2,
        side: THREE.DoubleSide,
      }),
      count
    );
    mesh.frustumCulled = false;
    mesh.renderOrder = 2;
    this.group.add(mesh);
    this.decalMeshes.push(mesh);
    return mesh;
  }

  _buildDecals() {
    const budget = Math.max(0, Math.floor((this.quality.decalLimit ?? 80) * 0.9));
    const bulletCount = Math.floor(budget * 0.4);
    const scorchCount = Math.floor(budget * 0.3);
    const crackCount = budget - bulletCount - scorchCount;
    const rand = seededRandom(717);
    this.decalTextures = {
      bullet: this._decalTexture('bullet', 64, 21),
      scorch: this._decalTexture('scorch', 128, 22),
      crack: this._decalTexture('crack', 128, 23),
    };

    const bullets = this._makeDecalMesh('bullet', bulletCount);
    const matrix = new THREE.Matrix4();
    const position = new THREE.Vector3();
    const quaternion = new THREE.Quaternion();
    const scale = new THREE.Vector3();
    const yaw = new THREE.Quaternion();
    let placed = 0;
    let tries = 0;
    const wallBulletCount = Math.floor(bulletCount * 0.32);
    const groundBulletBudget = bulletCount - wallBulletCount;
    while (placed < groundBulletBudget && tries < bulletCount * 40) {
      tries += 1;
      const x = (rand() * 2 - 1) * 180;
      const z = (rand() * 2 - 1) * 180;
      if (this._inLake(x, z, 2) || this._insideOccupied(x, z, 0.5)) continue;
      position.set(x, this.terrain.heightAt(x, z) + 0.035, z);
      quaternion.setFromUnitVectors(FRONT, UP);
      yaw.setFromAxisAngle(UP, rand() * Math.PI * 2);
      quaternion.multiply(yaw);
      const s = 0.28 + rand() * 0.3;
      scale.set(s, s, 1);
      matrix.compose(position, quaternion, scale);
      bullets.setMatrixAt(placed++, matrix);
    }

    let wallPlaced = 0;
    tries = 0;
    while (placed < bulletCount && wallPlaced < wallBulletCount && tries < wallBulletCount * 30 && this.buildings.length > 0) {
      tries += 1;
      const b = this.buildings[Math.floor(rand() * this.buildings.length)];
      const face = Math.floor(rand() * 4);
      const normal = new THREE.Vector3();
      let fx = 0;
      let fz = 0;
      if (face === 0) {
        normal.set(1, 0, 0);
        fx = b.x + b.w / 2 + 0.06;
        fz = b.z + (rand() - 0.5) * b.d * 0.8;
      } else if (face === 1) {
        normal.set(-1, 0, 0);
        fx = b.x - b.w / 2 - 0.06;
        fz = b.z + (rand() - 0.5) * b.d * 0.8;
      } else if (face === 2) {
        normal.set(0, 0, 1);
        fx = b.x + (rand() - 0.5) * b.w * 0.8;
        fz = b.z + b.d / 2 + 0.06;
      } else {
        normal.set(0, 0, -1);
        fx = b.x + (rand() - 0.5) * b.w * 0.8;
        fz = b.z - b.d / 2 - 0.06;
      }
      const y = this.terrain.heightAt(fx, fz) + 1.2 + rand() * Math.max(1, b.h - 2.6);
      position.set(fx, y, fz);
      quaternion.setFromUnitVectors(FRONT, normal);
      yaw.setFromAxisAngle(normal, rand() * Math.PI * 2);
      quaternion.multiply(yaw);
      const s = 0.22 + rand() * 0.22;
      scale.set(s, s, 1);
      matrix.compose(position, quaternion, scale);
      bullets.setMatrixAt(placed++, matrix);
      wallPlaced += 1;
    }
    bullets.count = Math.min(bulletCount, placed);

    const scorches = this._makeDecalMesh('scorch', scorchCount);
    placed = 0;
    const craterList = this.foregroundCraters.concat(this.terrain.craters);
    for (const crater of craterList) {
      if (placed >= scorchCount) break;
      if (this._inLake(crater.x, crater.z, 2)) continue;
      position.set(crater.x, this.terrain.heightAt(crater.x, crater.z) + 0.035, crater.z);
      quaternion.setFromUnitVectors(FRONT, UP);
      yaw.setFromAxisAngle(UP, rand() * Math.PI * 2);
      quaternion.multiply(yaw);
      const s = 2.4 + rand() * 2.2;
      scale.set(s, s, 1);
      matrix.compose(position, quaternion, scale);
      scorches.setMatrixAt(placed++, matrix);
    }
    tries = 0;
    while (placed < scorchCount && tries < scorchCount * 30) {
      tries += 1;
      const x = (rand() * 2 - 1) * 180;
      const z = (rand() * 2 - 1) * 180;
      if (this._inLake(x, z, 2) || this._insideOccupied(x, z, 0.5)) continue;
      position.set(x, this.terrain.heightAt(x, z) + 0.035, z);
      quaternion.setFromUnitVectors(FRONT, UP);
      yaw.setFromAxisAngle(UP, rand() * Math.PI * 2);
      quaternion.multiply(yaw);
      const s = 1.6 + rand() * 2.4;
      scale.set(s, s, 1);
      matrix.compose(position, quaternion, scale);
      scorches.setMatrixAt(placed++, matrix);
    }
    scorches.count = placed;

    const cracks = this._makeDecalMesh('crack', crackCount);
    placed = 0;
    tries = 0;
    while (placed < crackCount && tries < crackCount * 30) {
      tries += 1;
      const x = (rand() * 2 - 1) * 180;
      const z = (rand() * 2 - 1) * 180;
      if (this._inLake(x, z, 2) || this._insideOccupied(x, z, 0.5)) continue;
      position.set(x, this.terrain.heightAt(x, z) + 0.035, z);
      quaternion.setFromUnitVectors(FRONT, UP);
      yaw.setFromAxisAngle(UP, rand() * Math.PI * 2);
      quaternion.multiply(yaw);
      const s = 1.2 + rand() * 1.6;
      scale.set(s, s, 1);
      matrix.compose(position, quaternion, scale);
      cracks.setMatrixAt(placed++, matrix);
    }
    cracks.count = placed;
  }

  update(dt, time, camera) {
    if (camera) {
      const camX = camera.position.x;
      const camZ = camera.position.z;
      for (const c of this.cullables) {
        const dx = c.object.position.x - camX;
        const dz = c.object.position.z - camZ;
        c.object.visible = dx * dx + dz * dz < c.range * c.range;
      }
      camera.getWorldDirection(this._fillDir);
      this._fillDir.y = Math.max(0, this._fillDir.y);
      this.groundFillLight.position.set(
        camera.position.x + this._fillDir.x * 2.4,
        camera.position.y - 0.75,
        camera.position.z + this._fillDir.z * 2.4
      );
      this.groundFillLight.intensity = 1.3 + Math.sin(time * 0.8) * 0.08;
    }

    for (const flag of this.flags) {
      flag.material.uniforms.uTime.value = time;
      flag.material.uniforms.uWind.value = 0.8 + Math.sin(time * 0.7 + flag.phase) * 0.25;
    }

    for (const dust of this.dustSprites) {
      const t = time + dust.phase;
      dust.sprite.position.y = dust.baseY + Math.sin(t * 0.5) * 0.25;
      const pulse = 1 + Math.sin(t * 0.8) * 0.15;
      dust.sprite.scale.set(dust.base * pulse, dust.base * pulse, 1);
      dust.sprite.material.opacity = 0.18 + 0.12 * Math.sin(t * 0.6 + dust.phase);
    }

    for (const fire of this.fires) {
      const t = time + fire.phase;
      for (let i = 0; i < fire.fire.length; i += 1) {
        const sprite = fire.fire[i];
        const pulse = 0.75 + 0.25 * Math.sin(t * 11 + i * 1.9);
        sprite.scale.set(fire.base * (0.75 + pulse * 0.4), fire.base * (1.05 + pulse * 0.3), 1);
        sprite.material.opacity = 0.7 + 0.3 * Math.sin(t * 9 + i * 2.1);
        sprite.position.y = 1 + i * 0.12 + pulse * 0.08;
      }
      for (let i = 0; i < fire.smoke.length; i += 1) {
        const sprite = fire.smoke[i];
        const cycle = (t * 0.28 + i * 0.21) % 1;
        sprite.position.y = fire.smokeBase + cycle * fire.smokeHeight;
        const grow = 1 + cycle * 2.1;
        sprite.scale.set(fire.base * 1.25 * grow, fire.base * 1.25 * grow, 1);
        sprite.material.opacity = Math.max(0, 0.5 * (1 - cycle));
      }
    }
  }

  getSpawnPoints() {
    const candidates = [
      [0, 0], [34, 10], [-38, -14], [48, -32], [-34, 42],
      [16, -52], [-54, 36], [62, 26], [-70, -52], [80, 70],
    ];
    const points = [];
    for (const [x, z] of candidates) {
      if (this._isClear(x, z, 5)) {
        points.push(new THREE.Vector3(x, this.terrain.heightAt(x, z) + 1.2, z));
      }
    }
    while (points.length < 4) {
      points.push(new THREE.Vector3(0, this.terrain.heightAt(0, 0) + 1.2, 0));
    }
    return points;
  }

  getNavPoints() {
    const coords = [
      [0, 0], [28, -6], [-32, -6], [6, 30], [6, -38],
      [70, 20], [-60, 50], [40, -70],
    ];
    return coords.map(([x, z]) => new THREE.Vector3(x, this.terrain.heightAt(x, z) + 0.2, z));
  }
}
