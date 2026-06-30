// Viewmodel.js — the first-person weapon model parented to the camera so it
// always renders in front of the player. Built procedurally per race (katana /
// energy bow / claws) to avoid external assets.
//
// Presentation systems (all in here, all browser-side):
//   * Spring-mass-damper SWAY: the weapon lags behind camera rotation and
//     springs back, plus a figure-8 walk bob.
//   * Cubic-Bezier SWING: anticipation -> active -> recovery with an elastic
//     settle, instead of a single linear arc.
//   * Blade MOTION TRAIL: an emissive ribbon swept between the blade's base and
//     tip during the active frames, fading out additively.
//   * Camera-impact COUPLING: each swing kicks a camera roll (via VFX) into the
//     direction of the cut.

import * as THREE from 'three';
import VFX from './VFX.js';

// ---- small math helpers ----------------------------------------------------

// CSS-style cubic-bezier(x1,y1,x2,y2) easing: solve Bx(u)=t, return By(u).
function bezierEase(t, x1, y1, x2, y2) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  let u = t;
  for (let i = 0; i < 6; i++) {
    const mu = 1 - u;
    const x = 3 * mu * mu * u * x1 + 3 * mu * u * u * x2 + u * u * u;
    const dx = 3 * mu * mu * x1 + 6 * mu * u * (x2 - x1) + 3 * u * u * (1 - x2);
    if (Math.abs(dx) < 1e-6) break;
    u = THREE.MathUtils.clamp(u - (x - t) / dx, 0, 1);
  }
  const mu = 1 - u;
  return 3 * mu * mu * u * y1 + 3 * mu * u * u * y2 + u * u * u;
}

function easeOutElastic(t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  const c4 = (2 * Math.PI) / 3;
  return Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * c4) + 1;
}

// A damped 1-D spring (semi-implicit Euler), used for the look-sway axes.
class Spring1D {
  constructor(stiffness, damping) {
    this.x = 0; this.v = 0; this.k = stiffness; this.c = damping;
  }
  impulse(j) { this.v += j; }
  update(dt) {
    const a = -this.k * this.x - this.c * this.v;
    this.v += a * dt;
    this.x += this.v * dt;
    return this.x;
  }
}

// ---- blade motion trail ----------------------------------------------------

class BladeTrail {
  constructor(scene, color) {
    this.scene = scene;
    this.maxFrames = 14;
    this.frames = [];            // { base:Vector3, tip:Vector3 }
    this.active = false;
    this.fade = 0;

    const verts = new Float32Array(this.maxFrames * 2 * 3);
    const colors = new Float32Array(this.maxFrames * 2 * 3);
    const indices = [];
    for (let i = 0; i < this.maxFrames - 1; i++) {
      const a = i * 2, b = i * 2 + 1, c = (i + 1) * 2, d = (i + 1) * 2 + 1;
      indices.push(a, b, c, b, d, c);
    }
    this.geo = new THREE.BufferGeometry();
    this.geo.setAttribute('position', new THREE.BufferAttribute(verts, 3));
    this.geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    this.geo.setIndex(indices);
    this.mat = new THREE.MeshBasicMaterial({
      vertexColors: true, transparent: true, opacity: 0.9,
      blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
    });
    this.mesh = new THREE.Mesh(this.geo, this.mat);
    this.mesh.frustumCulled = false;
    this.mesh.visible = false;
    this.color = new THREE.Color(color);
    if (scene) scene.add(this.mesh);
  }

  begin() { this.active = true; this.fade = 1; this.frames.length = 0; this.mesh.visible = true; }
  end() { this.active = false; }

  push(base, tip) {
    if (!this.active) return;
    this.frames.unshift({ base: base.clone(), tip: tip.clone() });
    if (this.frames.length > this.maxFrames) this.frames.pop();
    this._rebuild();
  }

  _rebuild() {
    const pos = this.geo.attributes.position.array;
    const col = this.geo.attributes.color.array;
    const n = this.frames.length;
    for (let i = 0; i < this.maxFrames; i++) {
      const f = this.frames[Math.min(i, n - 1)] || this.frames[0];
      if (!f) continue;
      const ageT = n > 1 ? i / (n - 1) : 0;       // 0 newest -> 1 oldest
      const k = i * 6;
      pos[k] = f.base.x; pos[k + 1] = f.base.y; pos[k + 2] = f.base.z;
      pos[k + 3] = f.tip.x; pos[k + 4] = f.tip.y; pos[k + 5] = f.tip.z;
      // Additive blending: fade to black = invisible.
      const b = (1 - ageT) * this.fade;
      const r = this.color.r * b, g = this.color.g * b, bl = this.color.b * b;
      col[k] = r; col[k + 1] = g; col[k + 2] = bl;
      col[k + 3] = r; col[k + 4] = g; col[k + 5] = bl;
    }
    this.geo.attributes.position.needsUpdate = true;
    this.geo.attributes.color.needsUpdate = true;
  }

  update(dt) {
    if (this.active) return;
    if (this.fade > 0) {
      this.fade = Math.max(0, this.fade - dt * 4);
      this._rebuild();
      if (this.fade <= 0) this.mesh.visible = false;
    }
  }

  dispose() {
    if (this.mesh.parent) this.mesh.parent.remove(this.mesh);
    this.geo.dispose(); this.mat.dispose();
  }
}

// ---------------------------------------------------------------------------

export class Viewmodel {
  constructor(camera, race) {
    this.camera = camera;
    this.race = race;
    this.group = new THREE.Group();
    this.restPos = new THREE.Vector3(0.32, -0.34, -0.7);
    this.baseRotX = 0.15; this.baseRotY = 0.2; this.baseRotZ = -0.1;
    this.swingT = 0;
    this.swinging = false;
    this.swingDir = 1;
    this.swingCombo = 0;
    this.swingHeavy = false;
    this.charge = 0;
    this.bobT = 0;

    // Sway springs (rotation lag).
    this.swayYaw = new Spring1D(90, 14);
    this.swayPitch = new Spring1D(90, 14);
    this.swayPosX = new Spring1D(70, 12);
    this.swayPosY = new Spring1D(70, 12);
    this._lastYaw = null; this._lastPitch = null;

    this.accent = new THREE.Color(this.race?.accent || '#ffffff');
    this._build();
    this.group.position.copy(this.restPos);
    camera.add(this.group);

    this.trail = new BladeTrail(camera.parent, this.accent.getHex());
  }

  _build() {
    if (this.race?.weapon === 'bow') this._buildBow(this.accent);
    else if (this.race?.weapon === 'claws') this._buildClaws(this.accent);
    else this._buildKatana(this.accent);
  }

  _buildKatana(accent) {
    // Wrapped hilt (Tsuka) — segmented for a diamond-wrap read.
    const hiltMat = new THREE.MeshStandardMaterial({ color: 0x14141c, roughness: 0.85 });
    const wrapMat = new THREE.MeshStandardMaterial({ color: 0x2a1d3a, roughness: 0.6, metalness: 0.1 });
    const handle = new THREE.Mesh(new THREE.CylinderGeometry(0.028, 0.03, 0.3, 10), hiltMat);
    for (let i = 0; i < 6; i++) {
      const wrap = new THREE.Mesh(new THREE.TorusGeometry(0.03, 0.008, 6, 8), wrapMat);
      wrap.rotation.x = Math.PI / 2;
      wrap.position.y = -0.12 + i * 0.045;
      handle.add(wrap);
    }
    // Pommel.
    const pommel = new THREE.Mesh(new THREE.SphereGeometry(0.034, 10, 8),
      new THREE.MeshStandardMaterial({ color: 0x3a3340, metalness: 0.7, roughness: 0.4 }));
    pommel.position.y = -0.16;
    handle.add(pommel);

    // Guard (Tsuba) — round disc + small rim.
    const tsuba = new THREE.Mesh(new THREE.CylinderGeometry(0.075, 0.075, 0.018, 16),
      new THREE.MeshStandardMaterial({ color: 0x5a5048, metalness: 0.85, roughness: 0.35 }));
    tsuba.position.y = 0.16;

    // Blade — reflective steel with a subtle fuller and emissive edge tint.
    const bladeMat = new THREE.MeshStandardMaterial({
      color: 0xeaf1ff, metalness: 0.95, roughness: 0.12,
      emissive: accent, emissiveIntensity: 0.18,
    });
    const blade = new THREE.Mesh(new THREE.BoxGeometry(0.034, 0.98, 0.012), bladeMat);
    blade.position.y = 0.66;
    const fuller = new THREE.Mesh(new THREE.BoxGeometry(0.008, 0.9, 0.014),
      new THREE.MeshStandardMaterial({ color: 0x9fb4d8, metalness: 0.9, roughness: 0.25 }));
    fuller.position.y = 0.66;
    const tipMesh = new THREE.Mesh(new THREE.ConeGeometry(0.02, 0.12, 4),
      bladeMat);
    tipMesh.position.y = 1.16; tipMesh.rotation.y = Math.PI / 4;

    this.group.add(handle, tsuba, blade, fuller, tipMesh);
    this.group.rotation.set(this.baseRotX, this.baseRotY, this.baseRotZ);

    // Trail anchors: base (just above guard) and tip.
    this.base = new THREE.Object3D(); this.base.position.set(0, 0.22, 0); this.group.add(this.base);
    this.tip = new THREE.Object3D(); this.tip.position.set(0, 1.18, 0); this.group.add(this.tip);
  }

  _buildBow(accent) {
    const mat = new THREE.MeshStandardMaterial({ color: accent, emissive: accent, emissiveIntensity: 0.9, transparent: true, opacity: 0.85 });
    const arc = new THREE.Mesh(new THREE.TorusGeometry(0.35, 0.014, 10, 28, Math.PI * 1.3), mat);
    arc.rotation.z = Math.PI / 2;
    const string = new THREE.Mesh(new THREE.CylinderGeometry(0.003, 0.003, 0.62, 4),
      new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.6 }));
    this.group.add(arc, string);
    this.baseRotX = 0.1; this.baseRotY = -0.3; this.baseRotZ = 0;
    this.group.rotation.set(this.baseRotX, this.baseRotY, this.baseRotZ);
    this.restPos.set(0.2, -0.3, -0.6);
    this.base = new THREE.Object3D(); this.base.position.set(0, -0.2, 0); this.group.add(this.base);
    this.tip = new THREE.Object3D(); this.tip.position.set(0, 0.2, 0); this.group.add(this.tip);
  }

  _buildClaws(accent) {
    const mat = new THREE.MeshStandardMaterial({ color: 0xf2e9e4, roughness: 0.45, metalness: 0.2, emissive: accent, emissiveIntensity: 0.25 });
    for (let i = 0; i < 3; i++) {
      const claw = new THREE.Mesh(new THREE.ConeGeometry(0.018, 0.24, 6), mat);
      claw.position.set((i - 1) * 0.06, 0, 0);
      claw.rotation.x = -Math.PI / 2.6;
      this.group.add(claw);
    }
    this.baseRotX = 0.1; this.baseRotY = 0; this.baseRotZ = 0;
    this.group.rotation.set(this.baseRotX, this.baseRotY, this.baseRotZ);
    this.restPos.set(0.28, -0.3, -0.55);
    this.base = new THREE.Object3D(); this.base.position.set(0, 0, 0); this.group.add(this.base);
    this.tip = new THREE.Object3D(); this.tip.position.set(0, 0, -0.24); this.group.add(this.tip);
  }

  startSwing(heavy = false) {
    this.swinging = true;
    this.swingT = 0;
    this.swingHeavy = heavy;
    this.swingDir *= -1;
    this.swingCombo = (this.swingCombo % 4) + 1;
    this.trail?.begin();
    // Camera tilts INTO the cut.
    VFX.addRoll?.(-this.swingDir * (heavy ? 0.05 : 0.03));
  }

  setCharge(v) { this.charge = THREE.MathUtils.clamp(v, 0, 1); }

  // --- Swing pose (cubic bezier, 3 phases) -------------------------------
  _swingPose(t) {
    const dir = this.swingDir;
    const heavy = this.swingHeavy;
    // Pose offsets relative to rest.
    const antiRot = new THREE.Vector3(-0.35 * (heavy ? 1.4 : 1), 0.5 * dir, 0.7 * dir);
    const strikeRot = new THREE.Vector3(0.5 * (heavy ? 1.3 : 1), -0.8 * dir, -0.9 * dir);
    const antiPos = new THREE.Vector3(0.05 * dir, 0.06, 0.16);
    const strikePos = new THREE.Vector3(-0.08 * dir, -0.05, -0.1);

    const ANT = 0.18, ACT = 0.60; // recovery = 0.22
    const out = { pos: new THREE.Vector3(), rot: new THREE.Vector3(), env: 0 };

    if (t <= ANT) {
      const e = bezierEase(t / ANT, 0.3, 0.0, 0.4, 1.0);
      out.pos.lerpVectors(new THREE.Vector3(), antiPos, e);
      out.rot.lerpVectors(new THREE.Vector3(), antiRot, e);
    } else if (t <= ANT + ACT) {
      const lt = (t - ANT) / ACT;
      const e = bezierEase(lt, 0.9, 0.0, 0.95, 0.3); // slow -> snap
      out.pos.lerpVectors(antiPos, strikePos, e);
      out.rot.lerpVectors(antiRot, strikeRot, e);
      out.env = Math.sin(lt * Math.PI);
    } else {
      const lt = (t - ANT - ACT) / (1 - ANT - ACT);
      const e = bezierEase(lt, 0.2, 0.0, 0.2, 1.0);
      const el = easeOutElastic(lt);
      const a = e * 0.65 + el * 0.35; // blend in an elastic settle
      out.pos.lerpVectors(strikePos, new THREE.Vector3(), a);
      out.rot.lerpVectors(strikeRot, new THREE.Vector3(), a);
    }
    return out;
  }

  update(dt, speed01 = 0) {
    // ---- Spring sway from camera rotation delta ----
    const yaw = this.camera.rotation.y;
    const pitch = this.camera.rotation.x;
    if (this._lastYaw === null) { this._lastYaw = yaw; this._lastPitch = pitch; }
    let dYaw = yaw - this._lastYaw;
    let dPitch = pitch - this._lastPitch;
    dYaw = Math.atan2(Math.sin(dYaw), Math.cos(dYaw));
    this._lastYaw = yaw; this._lastPitch = pitch;

    this.swayYaw.impulse(-dYaw * 0.9);
    this.swayPitch.impulse(-dPitch * 0.9);
    this.swayPosX.impulse(dYaw * 0.5);
    this.swayPosY.impulse(dPitch * 0.5);
    const sYaw = THREE.MathUtils.clamp(this.swayYaw.update(dt), -0.16, 0.16);
    const sPitch = THREE.MathUtils.clamp(this.swayPitch.update(dt), -0.16, 0.16);
    const sPosX = THREE.MathUtils.clamp(this.swayPosX.update(dt), -0.1, 0.1);
    const sPosY = THREE.MathUtils.clamp(this.swayPosY.update(dt), -0.1, 0.1);

    // ---- Figure-8 walk bob + idle breathe ----
    this.bobT += dt * (4 + speed01 * 9);
    const bobX = Math.sin(this.bobT) * 0.012 * speed01;
    const bobY = Math.sin(this.bobT * 2) * 0.006 * speed01;
    const breathe = Math.sin(performance.now() * 0.0012) * 0.004 * (1 - speed01);

    const posOffset = new THREE.Vector3(bobX + sPosX, bobY + breathe + sPosY, 0);
    let rotX = 0, rotY = 0, rotZ = 0;

    // ---- Cubic-bezier swing ----
    if (this.swinging) {
      const dur = this.swingHeavy ? 0.5 : 0.32;
      this.swingT += dt / dur;
      const t = THREE.MathUtils.clamp(this.swingT, 0, 1);
      const pose = this._swingPose(t);
      posOffset.add(pose.pos);
      rotX += pose.rot.x; rotY += pose.rot.y; rotZ += pose.rot.z;
      if (this.trail && pose.env >= 0) {
        this.tip.updateWorldMatrix(true, false);
        this.base.updateWorldMatrix(true, false);
        const tipW = new THREE.Vector3().setFromMatrixPosition(this.tip.matrixWorld);
        const baseW = new THREE.Vector3().setFromMatrixPosition(this.base.matrixWorld);
        this.trail.push(baseW, tipW);
      }
      if (t >= 1) { this.swinging = false; this.trail?.end(); }
    }

    // Bow draw / heavy charge pulls the model back.
    if (this.charge > 0) {
      posOffset.z += this.charge * 0.12;
      posOffset.x -= this.charge * 0.05;
    }

    this.group.position.copy(this.restPos).add(posOffset);
    this.group.rotation.set(
      this.baseRotX + rotX + sPitch,
      this.baseRotY + rotY + sYaw,
      this.baseRotZ + rotZ
    );

    this.trail?.update(dt);
  }

  dispose() {
    this.trail?.dispose();
    if (this.group.parent) this.group.parent.remove(this.group);
    this.group.traverse((o) => {
      if (o.geometry) o.geometry.dispose();
      if (o.material) o.material.dispose();
    });
  }
}

export default Viewmodel;
