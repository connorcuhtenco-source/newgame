// Enemy.js — lightweight training-dummy / hollow enemy.
// Handles a simple chase-and-strike AI, health + stagger/stun, spatialized
// footstep audio (panned by screen position), and rewards on defeat that route
// through the ProgressionManager so each race converts kills into its currency.

import * as THREE from 'three';
import Events from './EventBus.js';
import Audio from './AudioManager.js';

export class Enemy {
  constructor(scene, spawn, opts = {}) {
    this.scene = scene;
    this.alive = true;
    this.maxHealth = opts.health ?? 60;
    this.health = this.maxHealth;
    this.radius = 0.6;
    this.speed = opts.speed ?? 2.4;
    this.damage = opts.damage ?? 8;
    this.attackRange = 2.6;
    this.attackCd = 0;
    this.stunTimer = 0;
    this.staggerTimer = 0;
    this.xp = opts.xp ?? 25;
    this.biomass = opts.biomass ?? 35;
    this.footstepT = 0;

    const color = opts.color ?? 0x3a2030;
    this.group = new THREE.Group();
    this.bodyMat = new THREE.MeshStandardMaterial({ color, roughness: 0.55, metalness: 0.2, emissive: 0x000000 });
    this.body = new THREE.Mesh(new THREE.CapsuleGeometry(0.4, 1.0, 6, 12), this.bodyMat);
    this.body.position.y = 1.0;
    this.body.castShadow = true;
    // Bone-white hollow mask.
    this.maskMat = new THREE.MeshStandardMaterial({ color: 0xf2ead6, roughness: 0.4, emissive: 0x000000 });
    const mask = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.42, 0.3), this.maskMat);
    mask.position.set(0, 1.65, 0.18);

    // Glowing red eyes + a faint red glow light.
    const eyeMat = new THREE.MeshBasicMaterial({ color: 0xff2a1a });
    for (const ex of [-0.12, 0.12]) {
      const eye = new THREE.Mesh(new THREE.SphereGeometry(0.05, 8, 8), eyeMat);
      eye.position.set(ex, 1.67, 0.34);
      this.group.add(eye);
    }
    const eyeGlow = new THREE.PointLight(0xff2a1a, 0.8, 6);
    eyeGlow.position.set(0, 1.67, 0.4);
    this.group.add(this.body, mask, eyeGlow);

    // Dark shadow aura wisps rising from the torso.
    const auraGeo = new THREE.BufferGeometry();
    const ap = new Float32Array(18 * 3);
    for (let i = 0; i < 18; i++) {
      ap[i * 3] = (Math.random() - 0.5) * 0.7;
      ap[i * 3 + 1] = 0.6 + Math.random() * 1.2;
      ap[i * 3 + 2] = (Math.random() - 0.5) * 0.7;
    }
    auraGeo.setAttribute('position', new THREE.BufferAttribute(ap, 3));
    this.aura = new THREE.Points(auraGeo, new THREE.PointsMaterial({
      color: 0x2a0a3a, size: 0.3, transparent: true, opacity: 0.5, depthWrite: false,
    }));
    this.group.add(this.aura);

    // Hit-flash bookkeeping (white self-illum pop on damage).
    this.flashTimer = 0;

    this.group.position.copy(spawn);
    this.spawn = spawn.clone();
    scene.add(this.group);

    // Floating health bar (billboarded sprite-ish plane).
    this.healthBar = new THREE.Mesh(
      new THREE.PlaneGeometry(1.0, 0.12),
      new THREE.MeshBasicMaterial({ color: 0xff3b3b, transparent: true })
    );
    this.healthBar.position.y = 2.3;
    this.group.add(this.healthBar);
  }

  get position() { return this.group.position; }

  stun(seconds) {
    this.stunTimer = Math.max(this.stunTimer, seconds);
    Events.emit('enemy:stun', { enemy: this });
  }

  takeDamage(amount, opts = {}) {
    if (!this.alive) return;
    this.health -= amount;
    if (opts.heavy || opts.guardBreak) this.staggerTimer = 0.6;
    // knockback
    if (opts.fromDir) {
      this.group.position.addScaledVector(opts.fromDir, opts.heavy ? 1.2 : 0.4);
    }
    this._flash();
    this._updateHealthBar();
    if (this.health <= 0) this._die();
  }

  // Solid-white self-illum flash for instant impact feedback.
  _flash() {
    this.flashTimer = 0.05;
    this.bodyMat.emissive.setRGB(1, 1, 1);
    this.bodyMat.emissiveIntensity = 2.4;
    this.maskMat.emissive.setRGB(1, 1, 1);
    this.maskMat.emissiveIntensity = 2.4;
  }

  _updateHealthBar() {
    const pct = Math.max(0, this.health / this.maxHealth);
    this.healthBar.scale.x = pct;
    this.healthBar.material.color.setHSL(pct * 0.33, 0.9, 0.5);
  }

  _die() {
    this.alive = false;
    this.scene.remove(this.group);
    this.body.geometry.dispose();
    Events.emit('enemy:defeated', { enemy: this });
  }

  update(dt, player, combat, camera) {
    if (!this.alive) return;
    this.healthBar.lookAt(camera.position);
    if (this.attackCd > 0) this.attackCd -= dt;

    // Restore material after the white hit-flash window.
    if (this.flashTimer > 0) {
      this.flashTimer -= dt;
      if (this.flashTimer <= 0) {
        this.bodyMat.emissive.setRGB(0, 0, 0);
        this.bodyMat.emissiveIntensity = 1;
        this.maskMat.emissive.setRGB(0, 0, 0);
        this.maskMat.emissiveIntensity = 1;
      }
    }
    // Gently rotate the shadow aura.
    if (this.aura) this.aura.rotation.y += dt * 1.5;

    if (this.stunTimer > 0) { this.stunTimer -= dt; return; }

    const toPlayer = player.position.clone().sub(this.group.position);
    toPlayer.y = 0;
    const dist = toPlayer.length();
    toPlayer.normalize();

    if (this.staggerTimer > 0) { this.staggerTimer -= dt; return; }

    // Face the player.
    this.group.rotation.y = Math.atan2(toPlayer.x, toPlayer.z);

    if (dist > this.attackRange) {
      this.group.position.addScaledVector(toPlayer, this.speed * dt);
      this._footsteps(dt, dist, player, camera);
    } else if (this.attackCd <= 0) {
      this.attackCd = 1.3;
      // Strike: hand resolution to the combat system (block/parry aware).
      const dirToAttacker = this.group.position.clone().sub(player.position).setY(0).normalize();
      combat.tryHitPlayer(this.damage, dirToAttacker, this);
    }
  }

  // Pan footstep SFX by the enemy's horizontal screen position for spatial cue.
  _footsteps(dt, dist, player, camera) {
    this.footstepT -= dt;
    if (this.footstepT > 0) return;
    this.footstepT = 0.45;
    const v = this.group.position.clone().project(camera);
    const pan = THREE.MathUtils.clamp(v.x, -1, 1) * (v.z < 1 ? 1 : -1);
    Audio.footstep(pan, dist / 8);
  }
}

export default Enemy;
