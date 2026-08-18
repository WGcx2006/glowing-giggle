import * as THREE from 'three';

const POINT_COLORS = {
  blue: 0x4d9fff,
  red: 0xff5f52,
  neutral: 0x9aa6a3,
};

const POINT_DEFS = [
  { id: 'A', name: '东侧仓库', x: 28, z: -6, owner: 'blue' },
  { id: 'B', name: '西侧断桥', x: -32, z: -6, owner: 'red' },
  { id: 'C', name: '北侧哨塔', x: 6, z: 30, owner: 'blue' },
  { id: 'D', name: '南侧海岸', x: 6, z: -38, owner: 'red' },
];

const FALLBACK_SPAWN_COORDS = {
  blue: [[18, 12], [34, 18], [-4, 22], [14, 26]],
  red: [[-20, -18], [-30, 2], [2, -24], [-12, -32]],
};

const _ownerColor = new THREE.Color();
const _neutralColor = new THREE.Color();
const _blendColor = new THREE.Color();

export class CaptureSystem {
  constructor(scene, physics, terrain, environment, events, quality = {}) {
    this.scene = scene;
    this.physics = physics;
    this.terrain = terrain;
    this.environment = environment;
    this.events = events;
    this.quality = quality;
    this.group = new THREE.Group();
    this.scene.add(this.group);
    this.points = [];
    this._lastEmit = 0;

    for (const def of POINT_DEFS) {
      const y = this.terrain?.heightAt?.(def.x, def.z) ?? 0;
      const point = {
        id: def.id,
        name: def.name,
        position: new THREE.Vector3(def.x, y, def.z),
        owner: def.owner,
        progress: 100,
        initialOwner: def.owner,
        initialProgress: 100,
        visuals: this.#buildVisuals(def.id, y),
      };
      this.points.push(point);
      this.#updateVisuals(point);
    }

    this.#emitState(true);
  }

  update(dt, teams = { blue: [], red: [] }) {
    const t = Math.max(0, Math.min(dt, 0.05));
    for (const point of this.points) {
      const blueCount = this.#countNear(point, teams.blue);
      const redCount = this.#countNear(point, teams.red);
      let changed = false;

      if (blueCount > 0 && redCount > 0) {
        // Contested: neither side can make progress.
      } else if (blueCount > 0) {
        this.#applyCapture(point, 'blue', t * 6 * Math.min(3, blueCount));
        changed = true;
      } else if (redCount > 0) {
        this.#applyCapture(point, 'red', t * 6 * Math.min(3, redCount));
        changed = true;
      } else if (point.progress > 0) {
        point.progress = Math.max(0, point.progress - t * 4);
        if (point.progress <= 0) point.owner = 'neutral';
        changed = true;
      }

      if (changed) this.#updateVisuals(point);
    }
    this.#emitState();
    return this.getState();
  }

  getState() {
    const points = this.points.map((point) => ({
      id: point.id,
      name: point.name,
      owner: point.owner,
      progress: Math.round(point.progress * 10) / 10,
    }));
    return {
      points,
      bluePoints: points.filter((point) => point.owner === 'blue').length,
      redPoints: points.filter((point) => point.owner === 'red').length,
    };
  }

  getSpawnPositions(team) {
    const owned = this.points.filter((point) => point.owner === team);
    if (owned.length > 0) {
      return owned.map((point) => point.position.clone());
    }
    const envPoints = this.environment?.getSpawnPoints?.() ?? [];
    if (envPoints.length > 0) {
      return envPoints.slice(0, 4).map((point) => point.clone());
    }
    const coords = FALLBACK_SPAWN_COORDS[team] ?? [];
    return coords.map(([x, z]) => new THREE.Vector3(
      x,
      (this.terrain?.heightAt?.(x, z) ?? 0) + 0.2,
      z
    ));
  }

  checkVictory(blueAlive = 0, redAlive = 0) {
    if (redAlive <= 0) return { winner: 'blue', reason: 'elimination' };
    if (blueAlive <= 0) return { winner: 'red', reason: 'elimination' };
    const blueAll = this.points.every((point) => point.owner === 'blue');
    const redAll = this.points.every((point) => point.owner === 'red');
    if (blueAll) return { winner: 'blue', reason: 'capture' };
    if (redAll) return { winner: 'red', reason: 'capture' };
    return { winner: null, reason: null };
  }

  reset() {
    for (const point of this.points) {
      point.owner = point.initialOwner;
      point.progress = point.initialProgress;
      this.#updateVisuals(point);
    }
    this.#emitState(true);
  }

  #applyCapture(point, team, amount) {
    if (point.owner === team) {
      point.progress = Math.min(100, point.progress + amount);
      return;
    }
    if (point.owner === 'neutral') {
      point.progress = Math.min(100, point.progress + amount);
      if (point.progress >= 100) {
        point.progress = 100;
        point.owner = team;
      }
      return;
    }
    // Pull an enemy-held point back through neutral before claiming it.
    point.progress = Math.max(0, point.progress - amount);
    if (point.progress <= 0) {
      point.progress = 0;
      point.owner = 'neutral';
    }
  }

  #countNear(point, positions) {
    if (!Array.isArray(positions)) return 0;
    let count = 0;
    for (const pos of positions) {
      if (!pos) continue;
      const dx = pos.x - point.position.x;
      const dz = pos.z - point.position.z;
      if (dx * dx + dz * dz <= 81) count++;
    }
    return count;
  }

  #buildVisuals(id, y) {
    const group = new THREE.Group();
    const ringMaterial = new THREE.MeshStandardMaterial({
      color: POINT_COLORS.neutral,
      roughness: 0.6,
      metalness: 0.3,
      emissive: 0x000000,
      emissiveIntensity: 0,
    });
    const ring = new THREE.Mesh(new THREE.TorusGeometry(1.45, 0.09, 8, 40), ringMaterial);
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = y + 0.06;
    ring.receiveShadow = true;

    const poleMaterial = new THREE.MeshStandardMaterial({
      color: 0x343a3d,
      roughness: 0.55,
      metalness: 0.7,
      emissive: 0x000000,
      emissiveIntensity: 0,
    });
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.07, 3.3, 8), poleMaterial);
    pole.position.y = y + 1.65;

    const flagMaterial = new THREE.MeshStandardMaterial({
      color: POINT_COLORS.neutral,
      roughness: 0.8,
      metalness: 0.05,
      side: THREE.DoubleSide,
    });
    const flag = new THREE.Mesh(new THREE.PlaneGeometry(1.5, 0.86, 6, 3), flagMaterial);
    flag.position.set(0.78, y + 2.5, 0);

    group.add(ring, pole, flag);
    group.userData.capturePoint = id;
    this.group.add(group);
    return { group, ringMaterial, poleMaterial, flagMaterial };
  }

  #updateVisuals(point) {
    const visuals = point.visuals;
    const ownerHex = POINT_COLORS[point.owner] ?? POINT_COLORS.neutral;
    _ownerColor.setHex(ownerHex);
    _neutralColor.setHex(POINT_COLORS.neutral);
    const ratio = Math.max(0, Math.min(1, point.progress / 100));

    visuals.flagMaterial.color.copy(_ownerColor);
    visuals.poleMaterial.emissive.copy(_ownerColor);
    visuals.poleMaterial.emissiveIntensity = 0.18 + ratio * 0.55;
    visuals.ringMaterial.emissive.copy(_ownerColor);
    visuals.ringMaterial.emissiveIntensity = ratio * 0.35;
    if (point.owner === 'neutral') {
      visuals.ringMaterial.color.copy(_neutralColor);
    } else {
      _blendColor.copy(_neutralColor).lerp(_ownerColor, ratio);
      visuals.ringMaterial.color.copy(_blendColor);
    }
  }

  #emitState(force = false) {
    const now = performance.now ? performance.now() : Date.now();
    if (!force && now - this._lastEmit < 150) return;
    this._lastEmit = now;
    this.events?.emit?.('capture:state', this.getState());
  }
}
