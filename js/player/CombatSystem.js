// CombatSystem.js — first-person melee & ranged combat plus player defense.
//  M1 (LMB)  : light attack, 4-hit combo (resets after a pause).
//  M2 (RMB)  : heavy attack / guard-break — slower wind-up, staggers blockers.
//  F (hold)  : block, reduces incoming damage by 80%.
//  F (timed) : tap to open a brief perfect-parry window — stuns the attacker,
//              triggers a screen flash + metallic clash SFX.
// Hit detection uses a forward cone test against world enemies (acts as a
// weapon hitbox for melee and a hitscan for the Quincy bow's long range).
// Also owns the player's health and resolves block/parry on incoming hits.

import * as THREE from 'three';
import Input from '../core/Input.js';
import Events from '../core/EventBus.js';
import Settings from '../config/Settings.js';

export class CombatSystem {
  constructor({ player, world, viewmodel, stats }) {
    this.player = player;
    this.world = world;
    this.viewmodel = viewmodel;
    this.stats = stats;

    this.maxHealth = stats.maxHealth;
    this.health = stats.maxHealth;
    this.dead = false;

    // Combo
    this.comboIndex = 0;
    this.comboTimer = 0;
    this.attackCooldown = 0;

    // Heavy
    this.heavyWindup = 0;
    this.heavyCharging = false;

    // Defense
    this.blocking = false;
    this.parryTimer = 0;   // >0 means inside perfect-parry window

    Events.on('input:keyup', ({ code }) => { if (code === 'KeyF') this._endGuard(); });
  }

  // --- Per-frame ---------------------------------------------------------
  update(dt) {
    if (this.dead) return;
    if (this.attackCooldown > 0) this.attackCooldown -= dt;
    if (this.comboTimer > 0) {
      this.comboTimer -= dt;
      if (this.comboTimer <= 0) this.comboIndex = 0;
    }
    if (this.parryTimer > 0) this.parryTimer -= dt;

    this._handleGuard();
    this._handleLight();
    this._handleHeavy(dt);
  }

  // --- Light attack: 4-hit combo ----------------------------------------
  _handleLight() {
    if (Input.mousePressed.left && this.attackCooldown <= 0 && !this.heavyCharging && !this.blocking) {
      const step = this.comboIndex % 4; // 0..3
      this.comboIndex += 1;
      this.comboTimer = Settings.comboResetMs / 1000;
      // Final hit of the combo swings a touch slower but hits harder.
      const finisher = step === 3;
      this.attackCooldown = finisher ? 0.42 : 0.26;
      this.viewmodel?.startSwing(false);
      Events.emit('combat:swing', { combo: step + 1 });
      const dmg = this.stats.lightDamage * (finisher ? 1.6 : 1);
      this._meleeHit(dmg, { finisher, comboStep: step + 1 });
      Events.emit('combat:combo', { step: step + 1, finisher });
    }
  }

  // --- Heavy attack: charge then release --------------------------------
  _handleHeavy(dt) {
    if (Input.mouse.right && !this.blocking && this.attackCooldown <= 0) {
      this.heavyCharging = true;
      this.heavyWindup += dt;
      this.viewmodel?.setCharge(Math.min(1, this.heavyWindup / 0.5));
    }
    if (this.heavyCharging && !Input.mouse.right) {
      // Released — fire the heavy if it was wound up enough.
      const charged = this.heavyWindup >= 0.18;
      this.heavyCharging = false;
      this.heavyWindup = 0;
      this.viewmodel?.setCharge(0);
      if (charged) {
        this.attackCooldown = 0.6;
        this.viewmodel?.startSwing(true);
        Events.emit('combat:heavy', {});
        this._meleeHit(this.stats.heavyDamage, { heavy: true, guardBreak: true });
      }
    }
  }

  // --- Guard: block + perfect parry -------------------------------------
  _handleGuard() {
    if (Input.pressed('KeyF')) {
      // Tapping F opens the perfect-parry window; holding becomes a block.
      this.parryTimer = Settings.parryWindowMs / 1000;
      Events.emit('combat:guard', { state: 'raise' });
    }
    this.blocking = Input.isDown('KeyF');
  }

  _endGuard() {
    this.blocking = false;
    Events.emit('combat:guard', { state: 'lower' });
  }

  // --- Hit detection (forward cone = weapon hitbox / hitscan) ------------
  _meleeHit(damage, opts = {}) {
    const enemies = this.world?.getEnemies?.() ?? [];
    const origin = this.player.position.clone();
    const look = this.player.getLookDirection();
    const range = this.stats.attackRange;
    const ranged = range > 10;
    const cosHalf = Math.cos((ranged ? 6 : 42) * Math.PI / 180);

    let hitAny = false;
    for (const enemy of enemies) {
      if (!enemy.alive) continue;
      const toE = enemy.position.clone().sub(origin);
      const dist = toE.length();
      if (dist > range + (enemy.radius || 0.6)) continue;
      toE.normalize();
      if (toE.dot(look) < cosHalf) continue;

      const point = enemy.position.clone();
      point.y = origin.y; // spark near contact height
      enemy.takeDamage(damage, { ...opts, fromDir: look.clone() });
      Events.emit('combat:hit', { point, damage, enemy, ...opts });
      if (opts.heavy) Events.emit('combat:heavyHitLanded', {});
      hitAny = true;
      if (!ranged && !opts.heavy) break; // melee light hits one target
    }
    return hitAny;
  }

  // --- Incoming damage resolution (called by enemy AI) ------------------
  // dirToAttacker: world-space unit vector from player to the attacker.
  tryHitPlayer(amount, dirToAttacker, attacker) {
    if (this.dead) return { result: 'dead' };

    // Is the attacker roughly in front of the player's facing?
    const look = this.player.getLookDirection();
    const facing = dirToAttacker ? look.dot(dirToAttacker.clone().normalize()) > 0.2 : true;

    if (this.parryTimer > 0 && facing) {
      // Perfect parry — no damage, stun the attacker, flashy feedback.
      this.parryTimer = 0;
      attacker?.stun?.(1.4);
      Events.emit('combat:parry', { point: attacker?.position?.clone(), attacker });
      return { result: 'parry' };
    }

    let dmg = amount;
    if (this.blocking && facing) {
      dmg *= (1 - Settings.blockDamageReduction);
      Events.emit('combat:block', {});
    }

    this.health = Math.max(0, this.health - dmg);
    // Angle of the hit relative to where the player looks (for the indicator).
    const rel = dirToAttacker ? this._relativeAngle(dirToAttacker) : 0;
    Events.emit('player:hurt', { amount: dmg, dir: rel, health: this.health });
    Events.emit('hud:health', { health: this.health, max: this.maxHealth });

    if (this.health <= 0) this._die();
    return { result: this.blocking ? 'blocked' : 'hit', damage: dmg };
  }

  _relativeAngle(dirToAttacker) {
    // Returns angle on the XZ plane between facing and attacker (signed).
    const look = this.player.getLookDirection();
    const a = Math.atan2(look.x, look.z);
    const b = Math.atan2(dirToAttacker.x, dirToAttacker.z);
    return b - a;
  }

  heal(amount) {
    this.health = Math.min(this.maxHealth, this.health + amount);
    Events.emit('hud:health', { health: this.health, max: this.maxHealth });
  }

  _die() {
    this.dead = true;
    Events.emit('player:death', {});
  }

  // Respawn keeps progression (handled by ProgressionManager.onDeath).
  respawn() {
    this.dead = false;
    this.health = this.maxHealth;
    this.player.position.set(0, 1.6, 6);
    this.player.velocity.set(0, 0, 0);
    Events.emit('hud:health', { health: this.health, max: this.maxHealth });
  }
}

export default CombatSystem;
