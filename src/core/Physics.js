import * as THREE from 'three';

export const GRAVITY = 9.81;

const _push = new THREE.Vector3();
const _normal = new THREE.Vector3();
const _ray = new THREE.Ray();
const _rayDir = new THREE.Vector3();
const _boxBounds = new THREE.Box3();
const _sphere = new THREE.Sphere();
const _point = new THREE.Vector3();
const _bestPoint = new THREE.Vector3();
const _bestNormal = new THREE.Vector3();

export class PhysicsWorld {
  constructor() {
    this.boxes = [];
    this.spheres = [];
    this._nextId = 1;
  }

  addBox(id, center, halfExtents, options = {}) {
    const box = {
      id: id ?? `box-${this._nextId++}`,
      center: new THREE.Vector3().copy(center),
      half: new THREE.Vector3().copy(halfExtents),
      static: options.static ?? true,
      destructible: options.destructible ?? false,
      health: options.health ?? 100,
      destroyed: false,
      userData: options.userData ?? {},
    };
    this.boxes.push(box);
    return box;
  }

  addSphere(id, center, radius, options = {}) {
    const sphere = {
      id: id ?? `sphere-${this._nextId++}`,
      center: new THREE.Vector3().copy(center),
      radius,
      static: options.static ?? true,
      destroyed: false,
      userData: options.userData ?? {},
    };
    this.spheres.push(sphere);
    return sphere;
  }

  removeBox(target) {
    const index = typeof target === 'string' || typeof target === 'number'
      ? this.boxes.findIndex((box) => box.id === target)
      : this.boxes.indexOf(target);
    if (index >= 0) this.boxes.splice(index, 1);
  }

  removeSphere(target) {
    const index = typeof target === 'string' || typeof target === 'number'
      ? this.spheres.findIndex((sphere) => sphere.id === target)
      : this.spheres.indexOf(target);
    if (index >= 0) this.spheres.splice(index, 1);
  }

  damageBox(target, amount) {
    const box = typeof target === 'string' || typeof target === 'number'
      ? this.boxes.find((candidate) => candidate.id === target)
      : target;
    if (!box || box.destroyed) return false;
    box.health -= amount;
    if (box.health <= 0) {
      box.destroyed = true;
      box.userData.destroyed = true;
    }
    return box.destroyed;
  }

  raycast(origin, direction, maxDistance = 500, options = null) {
    let ignore = null;
    let terrain = null;
    if (typeof options === 'function') {
      ignore = options;
    } else if (options && typeof options === 'object') {
      ignore = options.ignore ?? null;
      terrain = options.terrain ?? null;
    }

    _rayDir.copy(direction);
    if (_rayDir.lengthSq() < 1e-8) return null;
    _rayDir.normalize();
    _ray.origin.copy(origin);
    _ray.direction.copy(_rayDir);
    let best = null;
    let bestDist = maxDistance;

    for (const box of this.boxes) {
      if (box.destroyed) continue;
      const candidate = { type: 'box', object: box };
      if (ignore?.(candidate)) continue;
      _boxBounds.min.set(
        box.center.x - box.half.x,
        box.center.y - box.half.y,
        box.center.z - box.half.z
      );
      _boxBounds.max.set(
        box.center.x + box.half.x,
        box.center.y + box.half.y,
        box.center.z + box.half.z
      );
      const hit = _ray.intersectBox(_boxBounds, _point);
      if (!hit) continue;
      const distance = origin.distanceTo(hit);
      if (distance < bestDist) {
        bestDist = distance;
        _bestPoint.copy(hit);
        _bestNormal.copy(this.#boxNormal(box, hit));
        best = {
          type: 'box',
          object: box,
          point: _bestPoint,
          distance,
          normal: _bestNormal,
        };
      }
    }

    for (const body of this.spheres) {
      if (body.destroyed) continue;
      const candidate = { type: 'sphere', object: body };
      if (ignore?.(candidate)) continue;
      _sphere.center.copy(body.center);
      _sphere.radius = body.radius;
      const hit = _ray.intersectSphere(_sphere, _point);
      if (!hit) continue;
      const distance = origin.distanceTo(hit);
      if (distance < bestDist) {
        bestDist = distance;
        _bestPoint.copy(hit);
        _bestNormal.copy(hit).sub(body.center).normalize();
        best = {
          type: 'sphere',
          object: body,
          point: _bestPoint,
          distance,
          normal: _bestNormal,
        };
      }
    }

    if (terrain && typeof terrain.raycast === 'function') {
      const terrainHit = terrain.raycast(origin, _rayDir, maxDistance);
      if (terrainHit && terrainHit.point) {
        const distance = Number.isFinite(terrainHit.distance)
          ? terrainHit.distance
          : origin.distanceTo(terrainHit.point);
        if (distance < bestDist) {
          bestDist = distance;
          _bestPoint.copy(terrainHit.point);
          _bestNormal.set(0, 1, 0);
          if (terrainHit.normal) _bestNormal.copy(terrainHit.normal);
          best = {
            type: 'terrain',
            object: terrain,
            point: _bestPoint,
            distance,
            normal: _bestNormal,
          };
        }
      }
    }

    if (!best) return null;
    return {
      type: best.type,
      object: best.object,
      point: best.point.clone(),
      distance: best.distance,
      normal: best.normal.clone(),
    };
  }

  moveSphere(sphere, delta) {
    sphere.center.add(delta);
    const contacts = [];

    for (let iteration = 0; iteration < 4; iteration++) {
      let resolved = false;

      for (const box of this.boxes) {
        if (box.destroyed) continue;
        const push = this.#sphereBoxPush(sphere, box);
        if (!push) continue;
        this.#applySphereBoxPush(sphere, box, push, contacts);
        resolved = true;
      }

      for (const other of this.spheres) {
        if (other === sphere || other.destroyed) continue;
        const push = this.#sphereSpherePush(sphere, other);
        if (!push) continue;
        this.#applySphereSpherePush(sphere, other, push, contacts);
        resolved = true;
      }

      if (!resolved) break;
    }

    return {
      contacts,
      grounded: contacts.some((contact) => contact.normal.y > 0.6 && contact.push.y > 0),
    };
  }

  #boxNormal(box, point) {
    const rx = Math.abs(point.x - box.center.x) / Math.max(box.half.x, 1e-5);
    const ry = Math.abs(point.y - box.center.y) / Math.max(box.half.y, 1e-5);
    const rz = Math.abs(point.z - box.center.z) / Math.max(box.half.z, 1e-5);
    if (rx >= ry && rx >= rz) return _normal.set(Math.sign(point.x - box.center.x) || 1, 0, 0);
    if (ry >= rz) return _normal.set(0, Math.sign(point.y - box.center.y) || 1, 0);
    return _normal.set(0, 0, Math.sign(point.z - box.center.z) || 1);
  }

  #sphereBoxPush(sphere, box) {
    const r = sphere.radius;
    const cx = sphere.center.x;
    const cy = sphere.center.y;
    const cz = sphere.center.z;
    const minX = box.center.x - box.half.x - r;
    const maxX = box.center.x + box.half.x + r;
    const minY = box.center.y - box.half.y - r;
    const maxY = box.center.y + box.half.y + r;
    const minZ = box.center.z - box.half.z - r;
    const maxZ = box.center.z + box.half.z + r;

    if (cx < minX || cx > maxX || cy < minY || cy > maxY || cz < minZ || cz > maxZ) return null;

    const px = this.#axisPenetration(cx, box.center.x - box.half.x, box.center.x + box.half.x, r);
    const py = this.#axisPenetration(cy, box.center.y - box.half.y, box.center.y + box.half.y, r);
    const pz = this.#axisPenetration(cz, box.center.z - box.half.z, box.center.z + box.half.z, r);
    const ax = Math.abs(px);
    const ay = Math.abs(py);
    const az = Math.abs(pz);

    if (ax <= ay && ax <= az) return _push.set(px, 0, 0);
    if (ay <= az) return _push.set(0, py, 0);
    return _push.set(0, 0, pz);
  }

  #axisPenetration(value, min, max, radius) {
    if (value < min) return (min - radius) - value;
    if (value > max) return (max + radius) - value;
    const left = (min - radius) - value;
    const right = (max + radius) - value;
    return Math.abs(left) < Math.abs(right) ? left : right;
  }

  #applySphereBoxPush(sphere, box, push, contacts) {
    const applied = push.clone();
    if (!box.static && !sphere.static) {
      sphere.center.addScaledVector(applied, 0.5);
      box.center.sub(applied.clone().multiplyScalar(0.5));
    } else if (!box.static && sphere.static) {
      box.center.sub(applied);
    } else {
      sphere.center.add(applied);
    }
    const normal = this.#pushNormal(applied);
    contacts.push({ axis: this.#pushAxis(applied), normal, push: applied, box, sphere });
  }

  #sphereSpherePush(a, b) {
    const dx = b.center.x - a.center.x;
    const dy = b.center.y - a.center.y;
    const dz = b.center.z - a.center.z;
    const minDist = a.radius + b.radius;
    const distSq = dx * dx + dy * dy + dz * dz;
    if (distSq >= minDist * minDist || distSq < 1e-8) return null;
    const dist = Math.sqrt(distSq);
    const overlap = minDist - dist;
    _normal.set(a.center.x - b.center.x, a.center.y - b.center.y, a.center.z - b.center.z).normalize();
    return _push.copy(_normal).multiplyScalar(overlap);
  }

  #applySphereSpherePush(a, b, push, contacts) {
    if (a.static && b.static) return;
    const normal = push.clone().normalize();
    const overlap = push.length();
    if (!a.static && !b.static) {
      a.center.addScaledVector(normal, overlap * 0.5);
      b.center.addScaledVector(normal, -overlap * 0.5);
    } else if (a.static) {
      b.center.addScaledVector(normal, -overlap);
    } else {
      a.center.addScaledVector(normal, overlap);
    }
    contacts.push({ axis: 'sphere', normal, push: push.clone(), sphere: a, other: b });
  }

  #pushNormal(push) {
    const ax = Math.abs(push.x);
    const ay = Math.abs(push.y);
    const az = Math.abs(push.z);
    if (ax >= ay && ax >= az) return new THREE.Vector3(Math.sign(push.x) || 1, 0, 0);
    if (ay >= az) return new THREE.Vector3(0, Math.sign(push.y) || 1, 0);
    return new THREE.Vector3(0, 0, Math.sign(push.z) || 1);
  }

  #pushAxis(push) {
    const ax = Math.abs(push.x);
    const ay = Math.abs(push.y);
    const az = Math.abs(push.z);
    if (ax >= ay && ax >= az) return 'x';
    if (ay >= az) return 'y';
    return 'z';
  }
}
