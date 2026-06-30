// AudioManager.js — procedural SFX via the Web Audio API (no asset files).
// Every combat/UI sound is synthesized so the project ships with zero binaries.
// Listens on the EventBus so any system can trigger audio by emitting events.
// Includes a lightweight spatial panner for enemy footsteps / directional cues.

import Events from './EventBus.js';

class AudioManager {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.volume = 0.7;
    this._wired = false;
  }

  // Must be called from a user gesture (browser autoplay policy).
  init() {
    if (this.ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    this.ctx = new AC();
    this.master = this.ctx.createGain();
    this.master.gain.value = this.volume;
    this.master.connect(this.ctx.destination);
    if (!this._wired) this._wire();
  }

  setVolume(v) {
    this.volume = v;
    if (this.master) this.master.gain.value = v;
  }

  resume() {
    if (this.ctx && this.ctx.state === 'suspended') this.ctx.resume();
  }

  _wire() {
    this._wired = true;
    Events.on('ui:hover', () => this.uiHover());
    Events.on('ui:click', () => this.uiClick());
    Events.on('combat:swing', () => this.swing());
    Events.on('combat:hit', () => this.hit());
    Events.on('combat:heavy', () => this.heavy());
    Events.on('combat:parry', () => this.parry());
    Events.on('combat:block', () => this.block());
    Events.on('player:dash', () => this.dash());
    Events.on('player:levelup', () => this.levelUp());
    Events.on('player:aura', () => this.aura());
    Events.on('player:hurt', () => this.hurt());
  }

  // --- Synthesis helpers -------------------------------------------------
  _env(node, gainNode, { attack = 0.005, decay = 0.12, peak = 1, sustain = 0 } = {}) {
    const t = this.ctx.currentTime;
    gainNode.gain.cancelScheduledValues(t);
    gainNode.gain.setValueAtTime(0.0001, t);
    gainNode.gain.exponentialRampToValueAtTime(peak, t + attack);
    gainNode.gain.exponentialRampToValueAtTime(Math.max(sustain, 0.0001), t + attack + decay);
    node.start(t);
    node.stop(t + attack + decay + 0.05);
  }

  _tone(freq, type, opts = {}, pan = 0) {
    if (!this.ctx) return;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = type;
    osc.frequency.value = freq;
    if (opts.glideTo) {
      osc.frequency.exponentialRampToValueAtTime(
        opts.glideTo, this.ctx.currentTime + (opts.attack || 0.005) + (opts.decay || 0.12));
    }
    const panner = this.ctx.createStereoPanner();
    panner.pan.value = Math.max(-1, Math.min(1, pan));
    osc.connect(gain).connect(panner).connect(this.master);
    this._env(osc, gain, opts);
  }

  _noise(duration = 0.15, { lpf = 4000, peak = 0.6 } = {}, pan = 0) {
    if (!this.ctx) return;
    const buffer = this.ctx.createBuffer(1, this.ctx.sampleRate * duration, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / data.length);
    const src = this.ctx.createBufferSource();
    src.buffer = buffer;
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = lpf;
    const gain = this.ctx.createGain();
    const panner = this.ctx.createStereoPanner();
    panner.pan.value = Math.max(-1, Math.min(1, pan));
    gain.gain.value = peak;
    src.connect(filter).connect(gain).connect(panner).connect(this.master);
    src.start();
    src.stop(this.ctx.currentTime + duration);
  }

  // --- Named sounds ------------------------------------------------------
  uiHover() { this._tone(660, 'sine', { attack: 0.004, decay: 0.08, peak: 0.25 }); }
  uiClick() { this._tone(880, 'triangle', { attack: 0.003, decay: 0.16, peak: 0.4, glideTo: 1320 }); }
  swing()   { this._noise(0.12, { lpf: 2600, peak: 0.35 }); }
  hit()     { this._tone(140, 'square', { attack: 0.003, decay: 0.16, peak: 0.5, glideTo: 70 }); this._noise(0.1, { lpf: 1800, peak: 0.4 }); }
  heavy()   { this._tone(90, 'sawtooth', { attack: 0.01, decay: 0.3, peak: 0.6, glideTo: 50 }); }
  block()   { this._tone(220, 'square', { attack: 0.002, decay: 0.1, peak: 0.3 }); }
  // Bright metallic clash for the perfect parry.
  parry() {
    this._tone(2400, 'sawtooth', { attack: 0.002, decay: 0.25, peak: 0.5, glideTo: 1200 });
    this._tone(3200, 'square', { attack: 0.002, decay: 0.18, peak: 0.3 });
    this._noise(0.18, { lpf: 9000, peak: 0.5 });
  }
  dash()    { this._noise(0.2, { lpf: 5000, peak: 0.4 }); this._tone(520, 'sine', { attack: 0.005, decay: 0.18, peak: 0.25, glideTo: 220 }); }
  levelUp() { [523, 659, 784, 1047].forEach((f, i) => setTimeout(() => this._tone(f, 'triangle', { attack: 0.01, decay: 0.22, peak: 0.4 }), i * 90)); }
  aura()    { this._tone(70, 'sawtooth', { attack: 0.4, decay: 0.8, peak: 0.4, sustain: 0.2 }); }
  hurt()    { this._tone(180, 'square', { attack: 0.002, decay: 0.18, peak: 0.4, glideTo: 90 }); }

  // Spatialized blip for enemy footsteps; pan/-volume derived by caller.
  footstep(pan = 0, distance = 1) {
    const vol = Math.max(0.05, 0.4 / (1 + distance));
    this._noise(0.08, { lpf: 1200, peak: vol }, pan);
  }
}

export const Audio = new AudioManager();
export default Audio;
