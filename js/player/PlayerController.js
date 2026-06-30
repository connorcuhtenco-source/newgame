// PlayerController.js — first-person controller built on a generic StateMachine.
// Movement states: Idle / Walk / Sprint / Air(jump) / Dash. Owns the camera,
// mouse-look (pitch/yaw), gravity + simple ground collision, the directional
// dash (Q + WASD) with cooldown and afterimage VFX, and dynamic FOV that widens
// while sprinting, dashing, or on heavy-hit feedback.

import * as THREE from 'three';
import Input from '../core/Input.js';
import Events from '../core/EventBus.js';
import Settings from '../config/Settings.js';
import VFX from '../core/VFX.js';
import { StateMachine, State } from '../core/StateMachine.js';

const EYE_HEIGHT = 1.6;

export class PlayerController {
  constructor(camera, scene, stats) {
    this.camera = camera;
    this.scene = scene;
    this.stats = stats;

    this.position = new THREE.Vector3(0, EYE_HEIGHT, 6);
    this.velocity = new THREE.Vector3();
    this.yaw = Math.PI;     // facing -Z toward the arena
    this.pitch = 0;
    this.onGround = true;

    this.dashCooldown = 0;
    this.dashTimer = 0;
    this.dashAfterimageT = 0;
    this.dashDir = new THREE.Vector3();

    // FOV state
    this.fovTarget = Settings.baseFov;
    this.fovBump = 0;       // transient additive (heavy hit etc.)
    this.fovBumpTimer = 0;

    // Invisible body proxy used for dash afterimages.
    this.bodyProxy = new THREE.Mesh(
      new THREE.CapsuleGeometry(0.4, 1.0, 4, 8),
      new THREE.MeshBasicMaterial({ visible: false })
    );
    scene.add(this.bodyProxy);

    this._buildStateMachine();
    Events.on('combat:heavyHitLanded', () => this.bumpFov(Settings.heavyHitFov - Settings.baseFov, 0.25));
  }

  _buildStateMachine() {
    this.fsm = new StateMachine(this);
    this.fsm.add(new State('idle', {
      update: (c) => { if (c._wishMagnitude() > 0) c.fsm.change(c._sprintWanted() ? 'sprint' : 'walk'); },
    }));
    this.fsm.add(new State('walk', {
      update: (c) => {
        if (c._wishMagnitude() === 0) c.fsm.change('idle');
        else if (c._sprintWanted()) c.fsm.change('sprint');
      },
    }));
    this.fsm.add(new State('sprint', {
      update: (c) => {
        if (c._wishMagnitude() === 0) c.fsm.change('idle');
        else if (!c._sprintWanted()) c.fsm.change('walk');
      },
    }));
    this.fsm.add(new State('air', {
      update: (c) => { if (c.onGround) c.fsm.change(c._wishMagnitude() > 0 ? 'walk' : 'idle'); },
    }));
    this.fsm.add(new State('dash', {
      canEnter: (c) => c.dashCooldown <= 0,
      enter: (c) => {
        c.dashTimer = 0.18;
        c.dashCooldown = c.stats.dashCooldown;
        c.dashAfterimageT = 0;
        // Dash toward current WASD direction, or forward if none held.
        const wish = c._wishDirWorld();
        if (wish.lengthSq() === 0) wish.set(-Math.sin(c.yaw), 0, -Math.cos(c.yaw));
        c.dashDir.copy(wish).normalize();
        c.velocity.x = c.dashDir.x * c.stats.dashForce;
        c.velocity.z = c.dashDir.z * c.stats.dashForce;
        c.bumpFov(Settings.dashFov - Settings.baseFov, 0.22);
        Events.emit('player:dash', {});
      },
      update: (c, dt) => {
        c.dashTimer -= dt;
        c.dashAfterimageT -= dt;
        if (c.dashAfterimageT <= 0) {
          c.bodyProxy.position.set(c.position.x, c.position.y - 0.4, c.position.z);
          VFX.afterimage(c.bodyProxy, c.stats?.accent || 0x8fd4ff);
          c.dashAfterimageT = 0.03;
        }
        if (c.dashTimer <= 0) c.fsm.change(c.onGround ? 'idle' : 'air', true);
      },
    }));
    this.fsm.change('idle');
  }

  // --- Input helpers -----------------------------------------------------
  _wishMagnitude() {
    const m = Input.moveVector();
    return Math.abs(m.x) + Math.abs(m.z);
  }

  _sprintWanted() {
    return (Input.isDown('ShiftLeft') || Input.isDown('ShiftRight')) && Input.isDown('KeyW');
  }

  // WASD direction rotated into world space (XZ plane).
  _wishDirWorld() {
    const m = Input.moveVector();
    const forward = new THREE.Vector3(-Math.sin(this.yaw), 0, -Math.cos(this.yaw));
    const right = new THREE.Vector3(Math.cos(this.yaw), 0, -Math.sin(this.yaw));
    const dir = new THREE.Vector3();
    dir.addScaledVector(forward, -m.z); // m.z is -1 for W
    dir.addScaledVector(right, m.x);
    return dir;
  }

  bumpFov(amount, time) {
    this.fovBump = amount;
    this.fovBumpTimer = time;
  }

  // --- Per-frame update --------------------------------------------------
  update(dt) {
    this._look();
    this._tryDash();
    this._tryJump();
    this.fsm.update(dt);
    this._move(dt);
    this._updateFov(dt);
    this._applyCameraTransform();
  }

  _look() {
    this.yaw -= Input.mouse.dx * Settings.lookSensitivity;
    this.pitch -= Input.mouse.dy * Settings.lookSensitivity;
    this.pitch = THREE.MathUtils.clamp(this.pitch, -Settings.pitchClamp, Settings.pitchClamp);
  }

  _tryDash() {
    if (Input.pressed('KeyQ') && this.dashCooldown <= 0 && !this.fsm.is('dash')) {
      this.fsm.change('dash');
    }
  }

  _tryJump() {
    if (Input.pressed('Space') && this.onGround && !this.fsm.is('dash')) {
      this.velocity.y = Settings.jumpForce;
      this.onGround = false;
      this.fsm.change('air', true);
    }
  }

  _move(dt) {
    if (this.dashCooldown > 0) this.dashCooldown -= dt;

    const dashing = this.fsm.is('dash');
    if (!dashing) {
      // Desired horizontal velocity from movement state.
      let speed = this.stats.moveSpeed;
      if (this.fsm.is('sprint')) speed *= this.stats.sprintMult;
      const wish = this._wishDirWorld();
      if (wish.lengthSq() > 0) wish.normalize().multiplyScalar(speed);

      const control = this.onGround ? 1 : Settings.airControl;
      this.velocity.x = THREE.MathUtils.lerp(this.velocity.x, wish.x, control * Math.min(1, Settings.groundFriction * dt));
      this.velocity.z = THREE.MathUtils.lerp(this.velocity.z, wish.z, control * Math.min(1, Settings.groundFriction * dt));
    }

    // Gravity
    this.velocity.y += Settings.gravity * dt;

    // Integrate
    this.position.addScaledVector(this.velocity, dt);

    // Ground collision (flat arena at y=0).
    if (this.position.y <= EYE_HEIGHT) {
      this.position.y = EYE_HEIGHT;
      this.velocity.y = 0;
      this.onGround = true;
    } else {
      this.onGround = false;
    }

    // Keep inside the arena bounds.
    const B = 48;
    this.position.x = THREE.MathUtils.clamp(this.position.x, -B, B);
    this.position.z = THREE.MathUtils.clamp(this.position.z, -B, B);
  }

  _updateFov(dt) {
    let target = Settings.baseFov;
    if (this.fsm.is('sprint')) target = Settings.sprintFov;
    if (this.fsm.is('dash')) target = Settings.dashFov;

    if (this.fovBumpTimer > 0) {
      this.fovBumpTimer -= dt;
      target = Math.max(target, Settings.baseFov + this.fovBump);
      if (this.fovBumpTimer <= 0) this.fovBump = 0;
    }

    this.camera.fov = THREE.MathUtils.lerp(this.camera.fov, target, Math.min(1, Settings.fovLerp * dt));
    this.camera.updateProjectionMatrix();
  }

  _applyCameraTransform() {
    const shake = VFX.getShakeOffset();
    this.camera.position.set(
      this.position.x + shake.x,
      this.position.y + shake.y,
      this.position.z
    );
    this.camera.rotation.set(this.pitch, this.yaw, shake.roll, 'YXZ');
  }

  // Normalized 0..1 speed for view bob / HUD.
  speed01() {
    const horiz = Math.hypot(this.velocity.x, this.velocity.z);
    const max = this.stats.moveSpeed * this.stats.sprintMult;
    return Math.min(1, horiz / max);
  }

  getLookDirection() {
    return new THREE.Vector3(
      -Math.sin(this.yaw) * Math.cos(this.pitch),
      Math.sin(this.pitch),
      -Math.cos(this.yaw) * Math.cos(this.pitch)
    ).normalize();
  }
}

export default PlayerController;
