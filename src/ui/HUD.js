const HUD_CSS = `
#hud { -webkit-font-smoothing: antialiased; }
#team-panel { position: absolute; top: 18px; left: 24px; display: flex; flex-direction: column; gap: 6px; padding: 8px 12px; background: rgba(8, 14, 12, .58); border-left: 3px solid rgba(255, 255, 255, .25); backdrop-filter: blur(4px); pointer-events: none; }
.team-score { font-size: 13px; font-weight: 700; letter-spacing: 0; color: rgba(235, 245, 240, .92); text-shadow: 0 1px 3px #000; white-space: nowrap; }
.team-score.blue { color: #9fd0ff; }
.team-score.red { color: #ff9a8f; }
#capture-points { position: absolute; top: 56px; left: 50%; transform: translateX(-50%); display: flex; flex-wrap: wrap; justify-content: center; gap: 8px; max-width: min(720px, 92vw); padding: 6px 10px; background: rgba(8, 14, 12, .5); border-bottom: 1px solid rgba(255, 255, 255, .22); backdrop-filter: blur(4px); pointer-events: none; white-space: nowrap; }
.capture-point { font-size: 12px; font-weight: 700; letter-spacing: 0; padding: 2px 8px; border-left: 3px solid #9aa6a3; color: rgba(235, 245, 240, .92); text-shadow: 0 1px 2px #000; }
.capture-point[data-owner='blue'] { border-left-color: #4d9fff; }
.capture-point[data-owner='red'] { border-left-color: #ff5f52; }
#gameover-screen { position: fixed; inset: 0; z-index: 40; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 18px; background: rgba(5, 8, 7, .72); backdrop-filter: blur(6px); pointer-events: auto; }
#gameover-screen h2 { margin: 0; font-size: 56px; letter-spacing: 0; color: #d8ffe9; text-shadow: 0 0 28px rgba(80, 255, 180, .45), 0 4px 14px #000; }
#gameover-screen p { margin: 0; font-size: 20px; letter-spacing: 0; color: rgba(230, 240, 235, .85); text-shadow: 0 2px 5px #000; }
#restart-btn { padding: 12px 34px; font-size: 17px; letter-spacing: 0; background: linear-gradient(180deg, #e8b45a, #b9792e); color: #14100a; border: 1px solid rgba(255, 220, 150, .8); cursor: pointer; box-shadow: 0 6px 22px rgba(0, 0, 0, .45); }
#restart-btn:hover { filter: brightness(1.12); }
#health-bar { transition: width .16s ease-out, background .3s; }
#health-bar.critical { background: linear-gradient(90deg, #e02020, #ff8a5c); box-shadow: 0 0 16px rgba(255, 40, 40, .75); }
#armor-wrap { position: absolute; left: 28px; bottom: 64px; width: 240px; }
#armor-bar { height: 5px; border: 1px solid rgba(255, 255, 255, .4); background: linear-gradient(90deg, #4d9fff, #9bd4ff); box-shadow: 0 0 8px rgba(80, 160, 255, .35); transition: width .2s; }
#armor-text { position: absolute; right: 0; top: -16px; font-size: 12px; font-weight: 700; color: #cde9ff; text-shadow: 0 1px 2px #000; }
#low-health-vignette { position: absolute; inset: 0; pointer-events: none; background: radial-gradient(ellipse at center, transparent 40%, rgba(150, 10, 10, .58) 100%); opacity: 0; transition: opacity .4s; }
#hud.low-health #low-health-vignette { opacity: 1; }
#hit-marker { position: absolute; left: 50%; top: 50%; width: 40px; height: 40px; margin: -20px 0 0 -20px; opacity: 0; pointer-events: none; }
#hit-marker::before, #hit-marker::after { content: ''; position: absolute; left: 50%; top: 50%; width: 14px; height: 2px; background: #fff; box-shadow: 0 0 7px rgba(255, 154, 60, .9); }
#hit-marker::before { transform: translate(-50%, -50%) rotate(45deg); }
#hit-marker::after { transform: translate(-50%, -50%) rotate(-45deg); }
#hit-marker.show { animation: hit-mark .2s ease-out; }
@keyframes hit-mark { 0% { opacity: 1; transform: scale(1.25); } 100% { opacity: 0; transform: scale(.85); } }
#damage-direction { position: absolute; inset: 0; pointer-events: none; }
.ddir { position: absolute; opacity: 0; font-size: 34px; font-weight: 700; color: #ff4f4f; text-shadow: 0 0 12px rgba(255, 60, 60, .8), 0 2px 5px #000; }
.ddir.left { left: calc(50% - 118px); top: calc(50% - 24px); }
.ddir.right { left: calc(50% + 84px); top: calc(50% - 24px); }
.ddir.front { left: calc(50% - 18px); top: calc(50% - 100px); }
.ddir.back { left: calc(50% - 18px); top: calc(50% + 66px); }
.ddir.show { animation: dir-flash .55s ease-out; }
@keyframes dir-flash { 0% { opacity: 1; transform: scale(1.2); } 100% { opacity: 0; transform: scale(.85); } }
#damage-numbers { position: absolute; left: 50%; top: 50%; width: 0; height: 0; pointer-events: none; }
.damage-number { position: absolute; transform: translate(-50%, -50%); color: #ff5f52; font-size: 19px; font-weight: 800; text-shadow: 0 2px 5px #000; animation: damage-num .85s ease-out forwards; }
@keyframes damage-num { 0% { opacity: 1; transform: translate(-50%, -50%) translateY(0); } 100% { opacity: 0; transform: translate(-50%, -50%) translateY(-36px); } }
#reload-prompt { position: absolute; right: 28px; bottom: 82px; font-size: 14px; letter-spacing: 2px; color: #ffd27a; text-shadow: 0 1px 3px #000; opacity: 0; transform: translateY(4px); transition: opacity .15s, transform .15s; }
#reload-prompt.show { opacity: 1; transform: translateY(0); animation: reload-pulse .6s ease-out; }
@keyframes reload-pulse { 0% { transform: translateY(0) scale(1.04); } 100% { transform: translateY(0) scale(1); } }
#weapon-switch { position: absolute; right: 28px; top: 48%; transform: translateY(-50%); padding: 6px 12px; background: rgba(8, 14, 12, .62); border-right: 3px solid var(--hud-orange, #ff9a3c); font-size: 13px; letter-spacing: 1px; opacity: 0; backdrop-filter: blur(3px); }
#weapon-switch.show { animation: switch-in .6s ease-out; }
@keyframes switch-in { 0% { opacity: 1; transform: translateX(14px); } 100% { opacity: 0; transform: translateX(0); } }
#wave-banner { position: absolute; top: 62px; left: 50%; transform: translateX(-50%); padding: 5px 16px; background: rgba(12, 18, 16, .62); border-bottom: 1px solid var(--hud-orange, #ff9a3c); font-size: 15px; letter-spacing: 3px; opacity: 0; backdrop-filter: blur(4px); }
#wave-banner.show { animation: wave-pop .9s ease-out; }
@keyframes wave-pop { 0% { opacity: 1; transform: translateX(-50%) scale(1.05); } 100% { opacity: 0; transform: translateX(-50%) scale(.97); } }
#kill-confirm { position: absolute; left: 50%; top: 41%; transform: translateX(-50%); font-size: 17px; letter-spacing: 3px; color: #8dffc0; text-shadow: 0 0 12px rgba(80, 255, 160, .55), 0 2px 5px #000; opacity: 0; }
#kill-confirm.show { animation: kill-confirm .65s ease-out; }
@keyframes kill-confirm { 0% { opacity: 1; transform: translateX(-50%) scale(1.08); } 100% { opacity: 0; transform: translateX(-50%) scale(.96); } }
#ammo-text.low { color: #ffc06a; }
#ammo-text.empty { color: #ff5a5a; }
#objective { transition: border-color .2s, background .2s; }
#objective.updated { animation: objective-pulse .45s ease-out; }
@keyframes objective-pulse { 0% { border-left-color: #fff; background: rgba(24, 32, 28, .78); } 100% { border-left-color: var(--hud-orange, #ff9a3c); } }
#compass { position: absolute; left: 50%; transform: translateX(-50%); bottom: 72px; width: 320px; height: 22px; background: linear-gradient(90deg, rgba(0, 0, 0, .12), rgba(0, 0, 0, .38), rgba(0, 0, 0, .12)); }
.compass-strip { position: absolute; top: 0; left: 0; height: 100%; width: 1600px; will-change: transform; }
.compass-tick { position: absolute; top: 0; width: 1px; height: 8px; background: rgba(255, 255, 255, .55); }
.compass-tick.major { top: -1px; width: 2px; height: 13px; background: rgba(255, 255, 255, .95); }
#compass .compass-label { position: absolute; top: -3px; transform: translateX(-50%); font-size: 10px; font-weight: 700; color: rgba(255, 255, 255, .9); text-shadow: 0 1px 2px #000; }
#compass-marker { position: absolute; left: 50%; top: 0; width: 2px; height: 100%; background: var(--hud-orange, #ff9a3c); box-shadow: 0 0 7px rgba(255, 154, 60, .85); }
`;

const COMPASS_LABELS = { 0: 'N', 90: 'E', 180: 'S', 270: 'W' };

export class HUD {
  constructor(events) {
    this.events = events;
    this.hud = document.getElementById('hud');
    this.menu = document.getElementById('menu');
    this.deathScreen = document.getElementById('death-screen');
    this.healthBar = document.getElementById('health-bar');
    this.healthText = document.getElementById('health-text');
    this.ammoText = document.getElementById('ammo-text');
    this.weaponName = document.getElementById('weapon-name');
    this.objective = document.getElementById('objective');
    this.killfeed = document.getElementById('killfeed');
    this.damageOverlay = document.getElementById('damage-overlay');
    this.compass = document.getElementById('compass');
    this.cameraYaw = 0;
    this._flashTimers = new Map();
    this._damageTimer = 0;

    this.#injectStyles();
    this.#buildCompass();
    this.#buildDynamicElements();
    this.#wireEvents();
  }

  update(state) {
    if (!state) return;
    if (state.health !== undefined) this.#setHealth(state.health, state.maxHealth ?? 100);
    if (state.armor !== undefined) this.#setArmor(state.armor, state.maxArmor ?? 100);
    if (state.ammo !== undefined) {
      if (typeof state.ammo === 'string') this.ammoText.textContent = state.ammo;
      else if (state.ammo && typeof state.ammo === 'object' && 'current' in state.ammo) {
        this.#setAmmo(state.ammo.current, state.ammo.reserve ?? 0);
      } else {
        this.#setAmmo(state.ammo, state.reserve ?? 0);
      }
    }
    if (state.weaponName !== undefined) this.#setWeapon(state.weaponName);
    if (state.objective !== undefined) this.setObjective(state.objective);
    if (state.wave !== undefined) this.#showWave(state.wave);
    const angle = state.compassAngle ?? state.cameraYaw ?? state.yaw;
    if (angle !== undefined) this.setCompass(angle);
    if (state.cameraYaw !== undefined) this.cameraYaw = state.cameraYaw;
    else if (state.yaw !== undefined) this.cameraYaw = state.yaw;
    if (state.lowHealth !== undefined) this.hud?.classList.toggle('low-health', Boolean(state.lowHealth));
  }

  showMenu() {
    this.menu?.classList.remove('hidden');
  }

  hideMenu() {
    this.menu?.classList.add('hidden');
    this.hud?.classList.remove('hidden');
  }

  showDeath() {
    if (this.gameOverScreen && !this.gameOverScreen.classList.contains('hidden')) return;
    this.deathScreen?.classList.remove('hidden');
  }

  hideDeath() {
    this.deathScreen?.classList.add('hidden');
    this.#resetCombatIndicators();
  }

  showGameOver(winner, reason) {
    if (!this.gameOverScreen) return;
    this.hideDeath();
    const isBlueWin = winner === 'blue';
    const title = this.gameOverScreen.querySelector('h2');
    const reasonEl = this.gameOverScreen.querySelector('p');
    if (title) title.textContent = isBlueWin ? '胜利' : '失败';
    if (reasonEl) {
      reasonEl.textContent = reason === 'capture'
        ? (isBlueWin ? '已占领全部阵地' : '敌军占领全部阵地')
        : (isBlueWin ? '已消灭全部敌军' : '我方全部阵亡');
    }
    this.gameOverScreen.classList.remove('hidden');
  }

  hideGameOver() {
    this.gameOverScreen?.classList.add('hidden');
  }

  addKillFeed(text) {
    if (!this.killfeed) return;
    const el = document.createElement('div');
    el.textContent = text || '未知事件';
    this.killfeed.appendChild(el);
    setTimeout(() => el.remove(), 3800);
    while (this.killfeed.children.length > 6) this.killfeed.firstChild.remove();
  }

  damageFlash() {
    if (!this.damageOverlay) return;
    this.damageOverlay.style.opacity = '1';
    clearTimeout(this._damageTimer);
    this._damageTimer = setTimeout(() => {
      if (this.damageOverlay) this.damageOverlay.style.opacity = '0';
    }, 160);
  }

  setObjective(text) {
    if (!this.objective) return;
    this.objective.textContent = text ?? '';
    this.#flashElement(this.objective, 'updated', 600);
  }

  setCompass(angle) {
    if (angle === undefined || angle === null || !this.compassStrip) return;
    const abs = Math.abs(angle);
    const deg = abs > Math.PI * 2.1 ? Number(angle) : (Number(angle) * 180) / Math.PI;
    const normalized = ((deg % 360) + 360) % 360;
    const offset = -normalized * (this._compassStripWidth / 360) + this._compassCenter;
    this.compassStrip.style.transform = `translateX(${offset.toFixed(1)}px)`;
  }

  showHitMarker() {
    this.#flashElement(this.hitMarker, 'show', 220);
  }

  showReloadPrompt() {
    this.#flashElement(this.reloadPrompt, 'show', 1200);
  }

  #injectStyles() {
    if (document.getElementById('bf2035-hud-styles')) return;
    const style = document.createElement('style');
    style.id = 'bf2035-hud-styles';
    style.textContent = HUD_CSS;
    document.head.appendChild(style);
  }

  #buildCompass() {
    if (!this.compass) return;
    this.compass.innerHTML = '';
    this.compassStrip = document.createElement('div');
    this.compassStrip.className = 'compass-strip';
    this._compassStripWidth = 1600;
    for (let deg = 0; deg < 360; deg += 15) {
      const tick = document.createElement('div');
      tick.className = deg % 90 === 0 ? 'compass-tick major' : 'compass-tick';
      tick.style.left = `${(deg / 360) * this._compassStripWidth}px`;
      this.compassStrip.appendChild(tick);
      if (deg % 90 === 0) {
        const label = document.createElement('span');
        label.className = 'compass-label';
        label.textContent = COMPASS_LABELS[deg];
        label.style.left = `${(deg / 360) * this._compassStripWidth}px`;
        this.compassStrip.appendChild(label);
      }
    }
    this.compass.appendChild(this.compassStrip);
    const marker = document.createElement('div');
    marker.id = 'compass-marker';
    this.compass.appendChild(marker);
    this._compassCenter = Math.max(140, this.compass.clientWidth / 2 || 140);
  }

  #buildDynamicElements() {
    this.hitMarker = this.#ensure('hit-marker');
    const directionLayer = this.#ensure('damage-direction');
    this.damageDirections = {};
    const directions = [
      ['left', '←'],
      ['right', '→'],
      ['front', '↑'],
      ['back', '↓'],
    ];
    for (const [key, glyph] of directions) {
      const el = document.createElement('div');
      el.className = `ddir ${key}`;
      el.textContent = glyph;
      directionLayer.appendChild(el);
      this.damageDirections[key] = el;
    }

    this.lowHealthVignette = this.#ensure('low-health-vignette');
    this.damageNumbers = this.#ensure('damage-numbers');
    this.reloadPrompt = this.#ensure('reload-prompt');
    this.reloadPrompt.textContent = '重新装填';
    this.weaponSwitch = this.#ensure('weapon-switch');
    this.waveBanner = this.#ensure('wave-banner');
    this.killConfirm = this.#ensure('kill-confirm');

    const armorWrap = this.#ensure('armor-wrap');
    armorWrap.innerHTML = '';
    this.armorBar = document.createElement('div');
    this.armorBar.id = 'armor-bar';
    this.armorText = document.createElement('span');
    this.armorText.id = 'armor-text';
    this.armorText.textContent = '100';
    armorWrap.append(this.armorBar, this.armorText);

    this.teamPanel = this.#ensure('team-panel');
    this.blueScore = document.createElement('div');
    this.blueScore.className = 'team-score blue';
    this.blueScore.textContent = '蓝方 0 士兵 · 0 阵地';
    this.redScore = document.createElement('div');
    this.redScore.className = 'team-score red';
    this.redScore.textContent = '红方 0 士兵 · 0 阵地';
    this.teamPanel.append(this.blueScore, this.redScore);

    this.capturePoints = this.#ensure('capture-points');
    this.capturePoints.innerHTML = '';
    this._captureEls = {};
    for (const point of ['A', 'B', 'C', 'D']) {
      const el = document.createElement('div');
      el.className = 'capture-point';
      el.dataset.point = point;
      el.dataset.owner = 'neutral';
      el.textContent = `${point} 中立 0%`;
      this.capturePoints.appendChild(el);
      this._captureEls[point] = el;
    }

    this.gameOverScreen = document.getElementById('gameover-screen');
    if (!this.gameOverScreen) {
      this.gameOverScreen = document.createElement('div');
      this.gameOverScreen.id = 'gameover-screen';
      document.body.appendChild(this.gameOverScreen);
    }
    this.gameOverScreen.classList.add('hidden');
    this.gameOverScreen.innerHTML = '';
    const gameOverTitle = document.createElement('h2');
    const gameOverReason = document.createElement('p');
    const restartButton = document.createElement('button');
    restartButton.id = 'restart-btn';
    restartButton.textContent = '重新开局';
    this.gameOverScreen.append(gameOverTitle, gameOverReason, restartButton);
  }

  #ensure(id) {
    let el = document.getElementById(id);
    if (!el) {
      el = document.createElement('div');
      el.id = id;
      this.hud?.appendChild(el);
    }
    return el;
  }

  #wireEvents() {
    this.events?.on('player:health', ({ health, maxHealth }) => this.#setHealth(health, maxHealth));
    this.events?.on('player:armor', ({ armor, maxArmor }) => this.#setArmor(armor, maxArmor));
    this.events?.on('player:damage', ({ amount, direction }) => {
      this.damageFlash();
      if (direction) this.#showDamageDirection(direction);
      if (Number.isFinite(amount)) this.#addDamageNumber(amount);
    });
    this.events?.on('player:death', () => this.showDeath());
    this.events?.on('player:respawn', () => this.hideDeath());
    this.events?.on('weapon:ammo', ({ current, reserve }) => this.#setAmmo(current, reserve));
    this.events?.on('weapon:switch', ({ name }) => this.#setWeapon(name));
    this.events?.on('weapon:reload', () => this.showReloadPrompt());
    this.events?.on('enemy:kill', ({ name, team, source }) => {
      if (!team || (team === 'red' && (source === 'player' || source === 'blue'))) {
        this.#showKillConfirm(name);
      }
    });
    this.events?.on('killfeed', ({ text }) => this.addKillFeed(text));
    this.events?.on('objective', ({ text }) => this.setObjective(text));
    this.events?.on('game:wave', ({ wave }) => this.#showWave(wave));
    this.events?.on('capture:state', (state) => this.#updateCapture(state));
    this.events?.on('team:state', (state) => this.#updateTeamState(state));
    this.events?.on('game:over', ({ winner, reason }) => this.showGameOver(winner, reason));
    this.events?.on('player:lowhealth', ({ active }) => this.hud?.classList.toggle('low-health', Boolean(active)));
    this.events?.on('damage:target', (payload) => {
      if (!this.#isPlayerTarget(payload)) this.showHitMarker();
    });
  }

  #setHealth(health, maxHealth) {
    if (!this.healthBar || !this.healthText) return;
    const max = Math.max(1, maxHealth || 100);
    const value = Math.max(0, Number(health) || 0);
    const pct = Math.min(100, (value / max) * 100);
    this.healthBar.style.width = `${pct}%`;
    this.healthText.textContent = `${Math.ceil(value)}`;
    this.hud?.classList.toggle('low-health', pct <= 30);
    this.healthBar.classList.toggle('critical', pct <= 20);
  }

  #setArmor(armor, maxArmor) {
    if (!this.armorBar || !this.armorText) return;
    const max = Math.max(1, maxArmor || 100);
    const value = Math.max(0, Number(armor) || 0);
    this.armorBar.style.width = `${Math.min(100, (value / max) * 100)}%`;
    this.armorText.textContent = `${Math.ceil(value)}`;
  }

  #setAmmo(current, reserve) {
    if (!this.ammoText) return;
    if (typeof current === 'string') {
      this.ammoText.textContent = current;
      return;
    }
    const c = Math.max(0, Number(current) || 0);
    const r = Math.max(0, Number(reserve) || 0);
    this.ammoText.textContent = `${c} / ${r}`;
    this.ammoText.classList.toggle('low', c > 0 && c <= 6);
    this.ammoText.classList.toggle('empty', c <= 0);
  }

  #setWeapon(name) {
    if (!this.weaponName) return;
    const label = name || '未知武器';
    this.weaponName.textContent = label;
    if (this.weaponSwitch) {
      this.weaponSwitch.textContent = `武器切换  ${label}`;
      this.#flashElement(this.weaponSwitch, 'show', 900);
    }
  }

  #showWave(wave) {
    const label = `第 ${wave ?? 1} 波敌军来袭`;
    if (this.waveBanner) {
      this.waveBanner.textContent = label;
      this.#flashElement(this.waveBanner, 'show', 1600);
    }
    this.setObjective(`守住前哨阵地 · 第 ${wave ?? 1} 波`);
  }

  #updateCapture(state) {
    if (!state || !this.capturePoints) return;
    const points = state.points || [];
    for (const point of points) {
      const el = this._captureEls?.[point.id];
      if (!el) continue;
      const ownerLabel = point.owner === 'blue' ? '蓝方' : point.owner === 'red' ? '红方' : '中立';
      el.dataset.owner = point.owner || 'neutral';
      el.textContent = `${point.id} ${ownerLabel} ${Math.round(point.progress)}%`;
    }
  }

  #updateTeamState(state) {
    if (!state) return;
    if (this.blueScore) {
      this.blueScore.textContent = `蓝方 ${state.blueSoldiers ?? 0} 士兵 · ${state.bluePoints ?? 0} 阵地`;
    }
    if (this.redScore) {
      this.redScore.textContent = `红方 ${state.redSoldiers ?? 0} 士兵 · ${state.redPoints ?? 0} 阵地`;
    }
  }

  #showKillConfirm(name) {
    if (!this.killConfirm) return;
    this.killConfirm.textContent = `已消灭 ${name || '目标'}`;
    this.#flashElement(this.killConfirm, 'show', 650);
  }

  #showDamageDirection(direction) {
    const dx = direction?.x ?? direction?.[0] ?? 0;
    const dz = direction?.z ?? direction?.[2] ?? 0;
    if (!dx && !dz) return;
    let worldAngle = Math.atan2(dx, dz);
    let rel = worldAngle - (this.cameraYaw || 0);
    while (rel > Math.PI) rel -= Math.PI * 2;
    while (rel < -Math.PI) rel += Math.PI * 2;
    let key = 'front';
    if (rel >= -2.35 && rel < -0.75) key = 'right';
    else if (rel > 0.75 && rel <= 2.35) key = 'left';
    else if (rel < -2.35 || rel > 2.35) key = 'back';
    const el = this.damageDirections?.[key];
    if (el) this.#flashElement(el, 'show', 600);
  }

  #addDamageNumber(amount) {
    if (!this.damageNumbers || !Number.isFinite(amount)) return;
    const el = document.createElement('div');
    el.className = 'damage-number';
    el.textContent = `-${Math.ceil(Math.abs(amount))}`;
    el.style.left = `${Math.round(Math.random() * 140 - 70)}px`;
    el.style.top = `${Math.round(Math.random() * 56 - 28)}px`;
    this.damageNumbers.appendChild(el);
    while (this.damageNumbers.children.length > 8) this.damageNumbers.firstChild.remove();
    setTimeout(() => el.remove(), 900);
  }

  #flashElement(el, className, duration) {
    if (!el) return;
    const previous = this._flashTimers.get(el);
    if (previous) clearTimeout(previous);
    el.classList.remove(className);
    void el.offsetWidth;
    el.classList.add(className);
    this._flashTimers.set(
      el,
      setTimeout(() => {
        el.classList.remove(className);
        this._flashTimers.delete(el);
      }, duration)
    );
  }

  #resetCombatIndicators() {
    for (const key of Object.keys(this.damageDirections || {})) {
      this.damageDirections[key]?.classList.remove('show');
    }
    this.hitMarker?.classList.remove('show');
    this.lowHealthVignette?.classList.remove('show');
    this.hud?.classList.remove('low-health');
    if (this.damageNumbers) while (this.damageNumbers.firstChild) this.damageNumbers.firstChild.remove();
    clearTimeout(this._damageTimer);
    if (this.damageOverlay) this.damageOverlay.style.opacity = '0';
  }

  #isPlayerTarget(payload) {
    const target = payload?.target;
    const entity = target?.userData?.entity;
    return Boolean(
      target === 'player' ||
        entity === 'player' ||
        target?.isPlayer ||
        target?.userData?.isPlayer ||
        target?.userData?.kind === 'player' ||
        entity?.isPlayer ||
        (typeof target?.getHealth === 'function' && typeof target?.respawn === 'function') ||
        (typeof entity?.getHealth === 'function' && typeof entity?.respawn === 'function')
    );
  }
}
