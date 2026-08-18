import * as THREE from 'three';
import { events } from './Events.js';
import { quality } from '../config/Quality.js';
import { PhysicsWorld } from './Physics.js';
import { createPBRTextures } from './Textures.js';
import { SkySystem } from '../render/Sky.js';
import { TerrainSystem } from '../render/Terrain.js';
import { EnvironmentSystem } from '../render/Environment.js';
import { WeatherSystem } from '../render/Weather.js';
import { PostFX } from '../render/PostFX.js';
import { PlayerController } from '../gameplay/Player.js';
import { WeaponSystem } from '../gameplay/Weapons.js';
import { ProjectileSystem } from '../gameplay/Projectiles.js';
import { CaptureSystem } from '../gameplay/CaptureSystem.js';
import { EnemySystem } from '../gameplay/Enemies.js';
import { ParticleSystem } from '../effects/Particles.js';
import { ExplosionSystem } from '../effects/Explosions.js';
import { AudioManager } from '../audio/AudioManager.js';
import { HUD } from '../ui/HUD.js';

export class Game {
  constructor(container) {
    this.container = container;
    this.running = false;
    this.started = false;
    this.over = false;
    this.clock = new THREE.Clock();

    this.renderer = new THREE.WebGLRenderer({
      antialias: true,
      powerPreference: 'high-performance',
      stencil: false,
    });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, quality.pixelRatio || 2));
    this.renderer.setSize(container.clientWidth || window.innerWidth, container.clientHeight || window.innerHeight);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.12;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    container.appendChild(this.renderer.domElement);
    this.canvas = this.renderer.domElement;

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(70, this.aspect(), 0.05, 1200);
    this.camera.position.set(0, 1.7, 0);

    this.input = this.#createInput();
    this.events = events;
    this.physics = new PhysicsWorld();
    this.textures = createPBRTextures({ seed: 2035, baseColor: '#5b6258', roughness: 0.88, metalness: 0.04, size: 1024, repeat: 8 });

    this.sky = new SkySystem(this.scene, quality);
    this.terrain = new TerrainSystem(this.scene, quality);
    this.environment = new EnvironmentSystem(this.scene, this.physics, this.terrain, quality);
    this.weather = new WeatherSystem(this.scene, this.camera, quality);
    this.particles = new ParticleSystem(this.scene, quality);
    this.explosions = new ExplosionSystem(this.scene, this.physics, events, this.particles, quality, this.terrain);
    this.audio = new AudioManager();
    this.player = new PlayerController(this.camera, this.scene, this.physics, events, this.terrain, quality);
    this.weapons = new WeaponSystem(this.scene, this.camera, this.player, this.physics, events, quality);
    this.projectiles = new ProjectileSystem(this.scene, this.physics, events, this.particles, this.explosions, quality, { terrain: this.terrain });
    this.capture = new CaptureSystem(this.scene, this.physics, this.terrain, this.environment, events, quality);
    this.enemies = new EnemySystem(this.scene, this.physics, this.player, events, this.environment, this.terrain, quality, this.capture);
    this.hud = new HUD(events);

    this.#wireEvents();
    this.#bindInput();
  }

  aspect() {
    const w = this.container.clientWidth || window.innerWidth;
    const h = this.container.clientHeight || window.innerHeight;
    return w / h;
  }

  #wireEvents() {
    events.on('weapon:fire', (payload) => {
      if (payload.projectileType === 'rocket') {
        this.projectiles.spawnRocket(payload.origin, payload.direction, payload.source ?? 'player');
      } else if (payload.projectileType === 'grenade') {
        this.projectiles.spawnGrenade(payload.origin, payload.direction, payload.source ?? 'player');
      } else {
        this.projectiles.fireHitScan(
          payload.origin,
          payload.direction,
          payload.damage,
          payload.tracerColor,
          payload.weaponType
        );
      }
      this.particles.muzzleFlash?.(payload.origin, payload.direction);
      this.audio.playShot(payload.weaponType);
    });
    events.on('enemy:fire', (payload) => {
      this.projectiles.fireHitScan(
        payload.origin,
        payload.direction,
        payload.damage,
        payload.tracerColor,
        'enemy',
        payload.source ?? 'red'
      );
      this.particles.muzzleFlash?.(payload.origin, payload.direction);
      this.audio.playShot('enemy', payload.origin?.distanceTo?.(this.player.getPosition?.()) ?? 0);
    });
    events.on('explosion:detonated', (payload) => {
      this.explosions.explode(payload.position, payload.radius, payload.power, payload.type);
    });
    events.on('player:damage', () => {
      this.hud.damageFlash();
      this.audio.playHit();
    });
    events.on('camera:shake', ({ amount }) => {
      if (this.player && Number.isFinite(amount)) {
        this.player.shake = Math.max(this.player.shake || 0, Math.min(0.65, amount));
      }
    });
    events.on('sfx:explosion', ({ distance }) => {
      this.audio.playExplosion(distance ?? 0);
    });
    events.on('player:death', () => {
      this.audio.playDeath();
    });
    events.on('enemy:kill', ({ name, team, source }) => {
      if (!team || (team === 'red' && (source === 'player' || source === 'blue'))) {
        this.hud.addKillFeed(`击杀 ${name}`);
      }
    });
    events.on('killfeed', ({ text }) => {
      this.hud.addKillFeed(text);
    });
    events.on('objective', ({ text }) => {
      this.hud.setObjective(text);
    });
    events.on('capture:state', () => {
      if (!this.running || this.over) return;
      const blueAlive = this.enemies.getTeamAliveCount('blue') + (this.player.getState().alive ? 1 : 0);
      const redAlive = this.enemies.getTeamAliveCount('red');
      this.#checkVictory(blueAlive, redAlive);
    });
  }

  #createInput() {
    return {
      keys: new Set(),
      mouseDX: 0,
      mouseDY: 0,
      mouseDown: false,
      zoom: false,
      resetMouse() {
        this.mouseDX = 0;
        this.mouseDY = 0;
      },
    };
  }

  #bindInput() {
    window.addEventListener('keydown', (e) => {
      if (!this.running) return;
      this.input.keys.add(e.code);
      if (e.code === 'KeyR') this.weapons.reload?.();
      if (e.code === 'Digit1') this.weapons.switchWeapon?.(0);
      if (e.code === 'Digit2') this.weapons.switchWeapon?.(1);
      if (e.code === 'Digit3') this.weapons.switchWeapon?.(2);
      if (e.code === 'Digit4') this.weapons.switchWeapon?.(3);
      if (e.code === 'Digit5') this.weapons.switchWeapon?.(4);
      if (e.code === 'KeyF') this.enemies.spawnWave?.(3);
    });
    window.addEventListener('keyup', (e) => this.input.keys.delete(e.code));
    this.canvas.addEventListener('mousedown', (e) => {
      if (!this.running) return;
      if (e.button === 0) this.input.mouseDown = true;
      if (e.button === 2) this.input.zoom = true;
    });
    window.addEventListener('mouseup', (e) => {
      if (e.button === 0) this.input.mouseDown = false;
      if (e.button === 2) this.input.zoom = false;
    });
    document.addEventListener('mousemove', (e) => {
      if (!this.running || !document.pointerLockElement) return;
      this.input.mouseDX += e.movementX;
      this.input.mouseDY += e.movementY;
    });
    this.canvas.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  start() {
    if (this.running) return;
    this.running = true;
    this.started = true;
    this.clock.start();
    this.audio.init();
    this.audio.setListener(this.camera);
    this.hud.hideMenu();
    this.enemies.spawnTeams(6, 6);
    events.emit('objective', { text: '占领全部阵地，或消灭全部敌军' });
    this.loop();
  }

  pause() {
    this.running = false;
  }

  resume() {
    if (this.running) return;
    this.running = true;
    this.clock.getDelta();
    this.loop();
  }

  respawn() {
    if (this.over) return;
    this.player.respawn();
    this.hud.hideDeath();
    this.resume();
  }

  restart() {
    this.running = false;
    this.over = false;
    this.capture.reset();
    this.enemies.reset();
    this.player.respawn();
    this.hud.hideGameOver();
    this.hud.hideDeath();
    this.start();
  }

  update(dt) {
    const time = this.clock.elapsedTime;
    this.sky.update(time, dt);
    this.terrain.update(dt);
    this.environment.update(dt, time, this.camera);
    this.weather.update(dt);
    this.player.update(dt, this.input);
    this.weapons.update(dt, this.input);
    this.projectiles.update(dt);
    this.enemies.update(dt);

    const bluePositions = this.enemies.getTeamPositions('blue');
    bluePositions.push(this.player.getPosition());
    const redPositions = this.enemies.getTeamPositions('red');
    const captureState = this.capture.update(dt, { blue: bluePositions, red: redPositions });
    const blueAlive = this.enemies.getTeamAliveCount('blue') + (this.player.getState().alive ? 1 : 0);
    const redAlive = this.enemies.getTeamAliveCount('red');
    events.emit('team:state', {
      blueSoldiers: blueAlive,
      redSoldiers: redAlive,
      bluePoints: captureState.bluePoints,
      redPoints: captureState.redPoints,
    });
    this.#checkVictory(blueAlive, redAlive);

    this.particles.update(dt);
    this.explosions.update(dt);
    this.audio.update(dt);
    this.input.resetMouse();
    this.postFX = this.postFX || this.#createPostFX();
    this.postFX.render(dt);
  }

  #createPostFX() {
    return new PostFX(this.renderer, this.scene, this.camera, quality);
  }

  #checkVictory(blueAlive, redAlive) {
    if (this.over) return;
    const result = this.capture.checkVictory(blueAlive, redAlive);
    if (!result.winner) return;
    this.over = true;
    this.running = false;
    events.emit('game:over', result);
  }

  loop = () => {
    if (!this.running) return;
    requestAnimationFrame(this.loop);
    const dt = Math.min(this.clock.getDelta(), 0.05);
    this.update(dt);
  };

  resize() {
    const w = this.container.clientWidth || window.innerWidth;
    const h = this.container.clientHeight || window.innerHeight;
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h);
    this.postFX?.resize(w, h);
  }

  dispose() {
    this.running = false;
    this.renderer.dispose();
  }
}
