// Game.js — top-level orchestrator (singleton). Owns the Three.js renderer,
// scene, camera and the main loop, and wires together the player controller,
// combat, world, HUD and progression. Also handles pointer-lock, the reiatsu
// aura charge (G), milestone "instances", and death/respawn flow.

import * as THREE from 'three';
import Input from './Input.js';
import Events from './EventBus.js';
import Audio from './AudioManager.js';
import VFX from './VFX.js';
import Settings from '../config/Settings.js';
import Progression from '../progression/ProgressionManager.js';
import { World } from '../world/World.js';
import { PlayerController } from '../player/PlayerController.js';
import { CombatSystem } from '../player/CombatSystem.js';
import { Viewmodel } from '../player/Viewmodel.js';
import { HUD } from '../ui/HUD.js';

class Game {
  constructor() {
    this.running = false;
    this.last = 0;
    this.locked = false;
    this.reiatsu = 0;        // 0..1 aura charge
    this.auraSparkT = 0;
  }

  init({ canvas, hudRoot, screenEl }) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(Settings.baseFov, window.innerWidth / window.innerHeight, 0.1, 500);
    this.scene.add(this.camera);

    VFX.init({ scene: this.scene, camera: this.camera, screenEl });
    this.hud = new HUD(hudRoot);
    Input.attach(canvas);

    window.addEventListener('resize', () => this._onResize());
    this._setupPointerLock();
    this._wireEvents();
  }

  _setupPointerLock() {
    this.canvas.addEventListener('click', () => {
      if (!this.running || this.locked) return;
      this.canvas.requestPointerLock?.();
      Audio.init();
      Audio.resume();
    });
    document.addEventListener('pointerlockchange', () => {
      this.locked = document.pointerLockElement === this.canvas;
      Input.setEnabled(this.locked);
      Events.emit('game:lock', { locked: this.locked });
    });
  }

  _wireEvents() {
    Events.on('enemy:defeated', ({ enemy }) => Progression.onEnemyDefeated(enemy));
    Events.on('progression:tier', (d) => {
      if (d.skills) this.hud.setSkills(d.skills);
    });
    Events.on('milestone:instance', (m) => this._openInstance(m));
    Events.on('player:death', () => this._onDeath());
  }

  startWithRace(raceId) {
    const race = Progression.selectRace(raceId);
    this.stats = { ...Progression.stats, accent: new THREE.Color(race.accent).getHex() };

    this.world = new World(this.scene, race.accent);
    this.player = new PlayerController(this.camera, this.scene, this.stats);
    this.viewmodel = new Viewmodel(this.camera, race);
    this.combat = new CombatSystem({ player: this.player, world: this.world, viewmodel: this.viewmodel, stats: this.stats });

    this.hud.initHealth(this.stats.maxHealth);
    Progression._broadcast();
    this.accentColor = race.accent;

    this.running = true;
    this.last = performance.now();
    requestAnimationFrame((t) => this._loop(t));
  }

  // --- Reiatsu aura (hold G) --------------------------------------------
  _updateAura(dt) {
    const charging = this.locked && Input.isDown('KeyG');
    if (charging && this.reiatsu === 0) Events.emit('player:aura', { active: true });
    if (charging) {
      this.reiatsu = Math.min(1, this.reiatsu + dt * 0.8);
      this.auraSparkT -= dt;
      if (this.auraSparkT <= 0) {
        this.auraSparkT = 0.06;
        const base = this.player.position.clone();
        base.y -= 1.2 + Math.random();
        VFX.sparks3D(base, new THREE.Color(this.accentColor).getHex(), 6);
      }
    } else {
      this.reiatsu = Math.max(0, this.reiatsu - dt * 1.5);
    }
    this.hud.setAura(this.reiatsu > 0.02, this.accentColor, this.reiatsu * 0.7);
    VFX.setReiatsuVignette(this.reiatsu * 0.7, this.accentColor);
    if (this.reiatsu > 0.02) this.player.bumpFov((Settings.baseFov + 6) - Settings.baseFov, 0.1);
  }

  // --- Milestone instances (Inner World / boss / trial) -----------------
  _openInstance(m) {
    // Foundation behavior: pause control, present a prompt overlay, and resolve
    // the milestone when the player confirms. A full build would load a
    // dedicated map instance and mini-game/boss here.
    this.paused = true;
    document.exitPointerLock?.();
    const overlay = document.getElementById('instanceOverlay');
    if (!overlay) { m.onComplete?.(); this.paused = false; return; }
    overlay.querySelector('#instanceTitle').textContent = m.title;
    overlay.querySelector('#instanceDesc').textContent = m.desc;
    overlay.classList.add('show');
    const btn = overlay.querySelector('#instanceConfirm');
    const done = () => {
      overlay.classList.remove('show');
      btn.removeEventListener('click', done);
      this.paused = false;
      m.onComplete?.();
    };
    btn.addEventListener('click', done);
  }

  _onDeath() {
    Progression.onDeath();
    document.exitPointerLock?.();
    this.paused = true;
    setTimeout(() => {
      this.combat.respawn();
      this.paused = false;
      Events.emit('player:respawn', {});
    }, 2200);
  }

  _onResize() {
    if (!this.renderer) return;
    this.camera.aspect = window.innerWidth / window.innerHeight;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(window.innerWidth, window.innerHeight);
  }

  _loop(now) {
    if (!this.running) return;
    const dt = Math.min(0.05, (now - this.last) / 1000);
    this.last = now;

    if (this.locked && !this.paused) {
      this.player.update(dt);
      this.combat.update(dt);
      this.world.update(dt, this.player, this.combat, this.camera);
      this.viewmodel.update(dt, this.player.speed01());
      this._updateAura(dt);
    }
    VFX.update(dt);
    Input.endFrame();

    this.renderer.render(this.scene, this.camera);
    requestAnimationFrame((t) => this._loop(t));
  }
}

export const game = new Game();
export default game;
