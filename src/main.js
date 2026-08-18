import { Game } from './core/Game.js';
import { quality } from './config/Quality.js';

const params = new URLSearchParams(window.location.search);
if (params.get('quality')) quality.set(params.get('quality'));
const game = new Game(document.getElementById('app'));

window.__BF2035 = game;

const sensitivitySlider = document.getElementById('sensitivity-slider');
if (sensitivitySlider) {
  const saved = Number(localStorage.getItem('bf2035-sensitivity') || 1);
  sensitivitySlider.value = String(saved);
  game.player.setSensitivity(saved);
  sensitivitySlider.addEventListener('input', () => {
    const value = parseFloat(sensitivitySlider.value) || 1;
    game.player.setSensitivity(value);
    localStorage.setItem('bf2035-sensitivity', String(value));
  });
}

if (params.get('autostart') === '1') {
  game.start();
  if (params.get('hidehud') === '1') {
    document.getElementById('hud')?.classList.add('hidden');
    document.getElementById('menu')?.classList.add('hidden');
  }
}

const CAMERA_PRESETS = {
  hero: { position: [12, 2.6, 20], rotation: [-0.12, -2.35, 0] },
  combat: { position: [6.5, 1.9, 7], rotation: [-0.08, -2.35, 0] },
  aerial: { position: [38, 42, 62], rotation: [-0.62, -2.45, 0] },
  sunset: { position: [-18, 3.2, 14], rotation: [-0.08, -1.7, 0] },
};
const cam = params.get('cam');
if (cam && CAMERA_PRESETS[cam]) {
  const preset = CAMERA_PRESETS[cam];
  game.camera.position.set(...preset.position);
  game.camera.rotation.set(...preset.rotation);
  game.player.position.set(...preset.position);
  game.player.yaw = preset.rotation[1];
  game.player.pitch = preset.rotation[0];
  if (game.player.velocity) game.player.velocity.set(0, 0, 0);
}

document.getElementById('start-btn').addEventListener('click', () => {
  if (!game.started) game.start();
  else game.resume();
  game.canvas.requestPointerLock();
});

document.getElementById('respawn-btn').addEventListener('click', () => {
  game.respawn();
  game.canvas.requestPointerLock();
});

game.canvas.addEventListener('click', () => {
  if (!document.pointerLockElement) {
    if (game.started && !game.running && !game.over) game.resume();
    game.canvas.requestPointerLock();
  }
});

window.addEventListener('click', (event) => {
  if (event.target?.closest?.('#restart-btn')) {
    game.restart();
    game.canvas.requestPointerLock();
  }
});

document.addEventListener('pointerlockchange', () => {
  if (!document.pointerLockElement && game.running) {
    game.pause();
    game.hud.showMenu();
  }
});

window.addEventListener('resize', () => game.resize());
