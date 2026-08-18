import { events } from '../core/Events.js';

const SHOT_TYPES = {
  assault: {
    volume: 0.34,
    noiseFreq: 1900,
    noiseQ: 0.8,
    noisePeak: 0.7,
    noiseDecay: 0.075,
    oscType: 'sawtooth',
    oscFreq: 105,
    oscEnd: 62,
    oscPeak: 0.3,
    oscDecay: 0.09,
    crackFreq: 5200,
    crackDecay: 0.025,
    falloff: 0.025,
  },
  smg: {
    volume: 0.28,
    noiseFreq: 2600,
    noiseQ: 1.1,
    noisePeak: 0.55,
    noiseDecay: 0.05,
    oscType: 'square',
    oscFreq: 150,
    oscEnd: 96,
    oscPeak: 0.24,
    oscDecay: 0.05,
    crackFreq: 6800,
    crackDecay: 0.02,
    falloff: 0.028,
  },
  marksman: {
    volume: 0.46,
    noiseFreq: 1500,
    noiseQ: 0.55,
    noisePeak: 0.95,
    noiseDecay: 0.16,
    oscType: 'sine',
    oscFreq: 72,
    oscEnd: 38,
    oscPeak: 0.4,
    oscDecay: 0.16,
    crackFreq: 6800,
    crackDecay: 0.035,
    falloff: 0.02,
  },
  enemy: {
    volume: 0.24,
    noiseFreq: 1700,
    noiseQ: 0.7,
    noisePeak: 0.6,
    noiseDecay: 0.08,
    oscType: 'sawtooth',
    oscFreq: 118,
    oscEnd: 74,
    oscPeak: 0.2,
    oscDecay: 0.08,
    crackFreq: 4200,
    crackDecay: 0.025,
    falloff: 0.035,
  },
  rocket: {
    volume: 0.44,
    noiseFreq: 900,
    noiseQ: 0.5,
    noisePeak: 0.65,
    noiseDecay: 0.5,
    oscType: 'sawtooth',
    oscFreq: 220,
    oscEnd: 34,
    oscPeak: 0.42,
    oscDecay: 0.55,
    crackFreq: 4200,
    crackDecay: 0.08,
    falloff: 0.012,
  },
  rocket_launcher: {
    volume: 0.44,
    noiseFreq: 900,
    noiseQ: 0.5,
    noisePeak: 0.65,
    noiseDecay: 0.5,
    oscType: 'sawtooth',
    oscFreq: 220,
    oscEnd: 34,
    oscPeak: 0.42,
    oscDecay: 0.55,
    crackFreq: 4200,
    crackDecay: 0.08,
    falloff: 0.012,
  },
  grenade: {
    volume: 0.2,
    noiseFreq: 860,
    noiseQ: 1.1,
    noisePeak: 0.4,
    noiseDecay: 0.07,
    oscType: 'sine',
    oscFreq: 210,
    oscEnd: 82,
    oscPeak: 0.18,
    oscDecay: 0.08,
    crackFreq: 3400,
    crackDecay: 0.03,
    falloff: 0.04,
  },
};

const rand = (min = 0, max = 1) => min + Math.random() * (max - min);

export class AudioManager {
  constructor() {
    this.enabled = false;
    this.ctx = null;
    this.master = null;
    this.compressor = null;
    this._noiseBuffer = null;
    this._listener = null;
    this._ambienceTimer = 2.5;
    this._lowHealth = false;
    this._heartbeatTimer = 0;
    this._stepAlt = 0;
    this._heliState = 'idle';
    this._heliTimer = 8 + rand(0, 6);
    this._heliRemaining = 0;
    this._eventsBound = false;
  }

  init() {
    if (this.enabled && this.ctx) {
      this.ctx.resume?.();
      return;
    }
    const Ctor = window.AudioContext || window.webkitAudioContext;
    if (!Ctor) {
      this.enabled = false;
      return;
    }
    this.ctx = new Ctor();
    this.master = this.ctx.createGain();
    this.master.gain.value = 0.75;
    this.compressor = this.ctx.createDynamicsCompressor();
    this.compressor.threshold.value = -18;
    this.compressor.knee.value = 18;
    this.compressor.ratio.value = 6;
    this.compressor.attack.value = 0.004;
    this.compressor.release.value = 0.18;
    this.master.connect(this.compressor);
    this.compressor.connect(this.ctx.destination);
    this.enabled = true;
    this.#createNoiseBuffer();
    this.#startAmbience();
    this.#bindEvents();
  }

  #bindEvents() {
    if (this._eventsBound) return;
    this._eventsBound = true;
    events.on('player:health', ({ health, maxHealth }) => {
      const max = Math.max(1, maxHealth || 100);
      this.setLowHealth((Number(health) || 0) / max <= 0.3);
    });
    events.on('game:wave', () => this.playWave());
  }

  setListener(camera) {
    this._listener = camera;
    if (this.#ready()) this.#syncListener();
  }

  update(dt = 0) {
    if (!this.#ready()) return;
    const delta = Math.min(Math.max(0, dt), 0.1);
    if (this.ctx.state === 'suspended') this.ctx.resume?.();
    this.#syncListener();

    this._ambienceTimer -= delta;
    if (this._ambienceTimer <= 0) {
      this.#scheduleDistantEvent();
      this._ambienceTimer = 2.8 + rand(0, 5.5);
    }

    if (this._lowHealth) {
      this._heartbeatTimer -= delta;
      if (this._heartbeatTimer <= 0) {
        this.playHeartbeat();
        this._heartbeatTimer = 0.82 + rand(0, 0.24);
      }
    }

    this.#updateHelicopter(delta);
  }

  playShot(type = 'assault', distance = 0) {
    if (!this.#ready()) return;
    const config = SHOT_TYPES[type] || SHOT_TYPES.assault;
    const t = this.#now();
    const out = this.ctx.createGain();
    out.gain.value = config.volume * this.#distanceGain(distance, config.falloff);
    out.connect(this.master);
    this.#noiseBurst(config.noiseFreq, config.noiseQ, config.noisePeak, config.noiseDecay, t, out);
    if (config.oscType) {
      this.#tone({
        type: config.oscType,
        freq: config.oscFreq,
        endFreq: config.oscEnd,
        peak: config.oscPeak,
        attack: 0.001,
        decay: config.oscDecay,
        t,
        out,
      });
    }
    if (config.crackFreq) {
      this.#noiseBurst(config.crackFreq, 3.2, 0.42, config.crackDecay, t, out);
    }
  }

  playExplosion(distance = 0) {
    if (!this.#ready()) return;
    const d = Math.max(0, Number(distance) || 0);
    if (d > 450) return;
    const t = this.#now();
    const out = this.ctx.createGain();
    out.gain.value = 0.9 * this.#distanceGain(d, 0.012, 0.05);
    out.connect(this.master);
    this.#tone({ type: 'sine', freq: 58, endFreq: 26, peak: 0.9, attack: 0.004, decay: 0.9, t, out });
    this.#noiseBurst(140, 0.6, 0.85, 1.15, t, out);
    this.#noiseBurst(3600, 1.2, 0.35, 0.07, t, out);
    if (d < 120) {
      this.#tone({ type: 'triangle', freq: 120, endFreq: 30, peak: 0.28, attack: 0.002, decay: 0.5, t: t + 0.02, out });
    }
  }

  playFootstep() {
    if (!this.#ready()) return;
    const alt = (this._stepAlt ^= 1);
    const t = this.#now();
    const out = this.ctx.createGain();
    out.gain.value = 0.22;
    out.connect(this.master);
    this.#noiseBurst(alt ? 320 : 380, 0.9, 0.55, 0.09, t, out);
    this.#tone({ type: 'sine', freq: alt ? 88 : 74, endFreq: 48, peak: 0.26, attack: 0.002, decay: 0.1, t, out });
  }

  playReload() {
    if (!this.#ready()) return;
    const t = this.#now();
    const out = this.ctx.createGain();
    out.gain.value = 0.3;
    out.connect(this.master);
    const clicks = [
      [0, 2200],
      [0.15, 1500],
      [0.31, 2600],
    ];
    for (const [offset, freq] of clicks) {
      this.#noiseBurst(freq, 4, 0.34, 0.03, t + offset, out);
      this.#tone({ type: 'square', freq, endFreq: freq * 0.55, peak: 0.12, attack: 0.001, decay: 0.035, t: t + offset, out });
    }
  }

  playHit() {
    if (!this.#ready()) return;
    const t = this.#now();
    const out = this.ctx.createGain();
    out.gain.value = 0.3;
    out.connect(this.master);
    this.#noiseBurst(900, 0.9, 0.42, 0.06, t, out);
    this.#tone({ type: 'triangle', freq: 220, endFreq: 118, peak: 0.26, attack: 0.001, decay: 0.08, t, out });
    this.#noiseBurst(4200, 3, 0.16, 0.025, t, out);
  }

  playDeath() {
    if (!this.#ready()) return;
    const t = this.#now();
    const out = this.ctx.createGain();
    out.gain.value = 0.46;
    out.connect(this.master);
    this.#tone({ type: 'sawtooth', freq: 160, endFreq: 32, peak: 0.5, attack: 0.004, decay: 0.9, t, out });
    this.#noiseBurst(220, 0.7, 0.3, 1.1, t, out);
    this.#tone({ type: 'sine', freq: 64, endFreq: 24, peak: 0.34, attack: 0.01, decay: 0.8, t: t + 0.04, out });
  }

  playWave() {
    if (!this.#ready()) return;
    const t = this.#now();
    const out = this.ctx.createGain();
    out.gain.value = 0.36;
    out.connect(this.master);
    this.#tone({ type: 'sine', freq: 440, endFreq: 660, peak: 0.22, attack: 0.01, decay: 0.12, t, out });
    this.#tone({ type: 'sine', freq: 660, endFreq: 880, peak: 0.2, attack: 0.01, decay: 0.14, t: t + 0.18, out });
    this.#tone({ type: 'triangle', freq: 110, endFreq: 55, peak: 0.22, attack: 0.01, decay: 0.5, t: t + 0.05, out });
  }

  playHeartbeat() {
    if (!this.#ready()) return;
    const t = this.#now();
    const out = this.ctx.createGain();
    out.gain.value = 0.5;
    out.connect(this.master);
    this.#tone({ type: 'sine', freq: 58, endFreq: 42, peak: 0.5, attack: 0.008, decay: 0.12, t, out });
    this.#tone({ type: 'sine', freq: 52, endFreq: 38, peak: 0.36, attack: 0.008, decay: 0.1, t: t + 0.16, out });
    this.#noiseBurst(240, 1, 0.16, 0.1, t, out);
  }

  setLowHealth(active) {
    this._lowHealth = Boolean(active);
    if (active) this._heartbeatTimer = Math.min(this._heartbeatTimer, 0.35);
    else this._heartbeatTimer = 0;
  }

  #startAmbience() {
    if (!this.#ready()) return;
    const windSource = this.#noiseSource();
    const windFilter = this.ctx.createBiquadFilter();
    windFilter.type = 'lowpass';
    windFilter.frequency.value = 240;
    windFilter.Q.value = 0.4;
    const windGain = this.ctx.createGain();
    windGain.gain.value = 0.035;
    windSource.connect(windFilter);
    windFilter.connect(windGain);
    windGain.connect(this.master);
    windSource.start();

    const windLfo = this.ctx.createOscillator();
    windLfo.frequency.value = 0.07;
    const windLfoGain = this.ctx.createGain();
    windLfoGain.gain.value = 70;
    windLfo.connect(windLfoGain);
    windLfoGain.connect(windFilter.frequency);
    windLfo.start();

    const heliOsc = this.ctx.createOscillator();
    heliOsc.type = 'sawtooth';
    heliOsc.frequency.value = 27;
    const heliFilter = this.ctx.createBiquadFilter();
    heliFilter.type = 'bandpass';
    heliFilter.frequency.value = 70;
    heliFilter.Q.value = 4;
    const heliGain = this.ctx.createGain();
    heliGain.gain.value = 0.004;
    heliOsc.connect(heliFilter);
    heliFilter.connect(heliGain);
    heliGain.connect(this.master);
    heliOsc.start();

    const heliLfo = this.ctx.createOscillator();
    heliLfo.type = 'sine';
    heliLfo.frequency.value = 11;
    const heliLfoGain = this.ctx.createGain();
    heliLfoGain.gain.value = 16;
    heliLfo.connect(heliLfoGain);
    heliLfoGain.connect(heliOsc.frequency);
    heliLfo.start();

    this._heliGain = heliGain;
  }

  #updateHelicopter(dt) {
    if (!this._heliGain || !this.#ready()) return;
    const t = this.#now();
    this._heliTimer -= dt;
    if (this._heliState === 'idle' && this._heliTimer <= 0) {
      this._heliState = 'active';
      this._heliRemaining = 2.5 + rand(0, 3);
      this._heliGain.gain.setTargetAtTime(0.014, t, 0.4);
    } else if (this._heliState === 'active') {
      this._heliRemaining -= dt;
      if (this._heliRemaining <= 0) {
        this._heliState = 'idle';
        this._heliGain.gain.setTargetAtTime(0.004, t, 0.8);
        this._heliTimer = 14 + rand(0, 10);
      }
    }
  }

  #scheduleDistantEvent() {
    const roll = Math.random();
    if (roll < 0.45) {
      this.playShot('enemy', 130 + rand(0, 170));
    } else if (roll < 0.82) {
      this.playExplosion(190 + rand(0, 250));
    } else {
      this.playShot('enemy', 110 + rand(0, 140));
      this.playShot('smg', 260 + rand(0, 120));
    }
  }

  #createNoiseBuffer() {
    const length = Math.max(1, Math.floor(this.ctx.sampleRate * 1.5));
    const buffer = this.ctx.createBuffer(1, length, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < length; i++) data[i] = Math.random() * 2 - 1;
    this._noiseBuffer = buffer;
  }

  #noiseSource() {
    const source = this.ctx.createBufferSource();
    source.buffer = this._noiseBuffer;
    source.loop = true;
    return source;
  }

  #noiseBurst(freq, q, peak, decay, t, out) {
    const source = this.#noiseSource();
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.value = freq;
    filter.Q.value = q;
    const gain = this.ctx.createGain();
    this.#applyEnvelope(gain, t, peak, 0.001, decay);
    source.connect(filter);
    filter.connect(gain);
    gain.connect(out);
    source.start(t);
    source.stop(t + decay + 0.03);
  }

  #tone({ type, freq, endFreq, peak, attack, decay, t, out }) {
    const osc = this.ctx.createOscillator();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, t);
    if (endFreq && endFreq !== freq) {
      osc.frequency.exponentialRampToValueAtTime(Math.max(1, endFreq), t + decay);
    }
    const gain = this.ctx.createGain();
    this.#applyEnvelope(gain, t, peak, attack, decay);
    osc.connect(gain);
    gain.connect(out);
    osc.start(t);
    osc.stop(t + decay + 0.03);
  }

  #applyEnvelope(gain, t, peak, attack, decay) {
    const safePeak = Math.max(0.0002, peak);
    gain.gain.setValueAtTime(0.0001, t);
    gain.gain.exponentialRampToValueAtTime(safePeak, t + attack);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + attack + decay);
  }

  #distanceGain(distance, falloff = 0.025, floor = 0.08) {
    const d = Math.max(0, Number(distance) || 0);
    return Math.max(floor, Math.min(1, 1 / (1 + d * falloff)));
  }

  #syncListener() {
    const camera = this._listener;
    if (!camera?.position || !this.#ready()) return;
    const p = camera.position;
    try {
      const listener = this.ctx.listener;
      const t = this.#now();
      if ('positionX' in listener) {
        listener.positionX.setTargetAtTime(p.x, t, 0.05);
        listener.positionY.setTargetAtTime(p.y, t, 0.05);
        listener.positionZ.setTargetAtTime(p.z, t, 0.05);
      } else if (typeof listener.setPosition === 'function') {
        listener.setPosition(p.x, p.y, p.z);
      }
    } catch {
      // Listener API differences should not break the audio graph.
    }
  }

  #ready() {
    return Boolean(this.enabled && this.ctx);
  }

  #now() {
    return this.ctx.currentTime;
  }
}
