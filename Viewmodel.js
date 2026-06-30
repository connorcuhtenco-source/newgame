// Viewmodel.js — the first-person weapon model parented to the camera so it
// always renders in front of the player. Built procedurally per race (katana /
// energy bow / claws) to avoid external assets. Exposes swing/charge animation
// hooks the CombatSystem drives, plus a muzzle/tip point used for hit origins.

import * as THREE from 'three';

export class Viewmodel {
  constructor(camera, race) {
    this.camera = camera;
    this.race = race;
    this.group = new THREE.Group();
    this.restPos = new THREE.Vector3(0.32, -0.34, -0.7);
    this.restRot = new THREE.Euler(0, 0, 0);
    this.swingT = 0;       // 0..1 animation progress
    this.swinging = false;
    this.swingDir = 1;     // alternate left/right slashes
    this.charge = 0;       // 0..1 (heavy windup / bow draw)
    this.bobT = 0;
    this._build();
    this.group.position.copy(this.restPos);
    camera.add(this.group);
  }

  _build() {
    const accent = new THREE.Color(this.race?.accent || '#ffffff');
    if (this.race?.weapon === 'bow') this._buildBow(accent);
    else if (this.race?.weapon === 'claws') this._buildClaws(accent);
    else this._buildKatana(accent);
  }

  _buildKatana(accent) {
    const handle = new THREE.Mesh(
      new THREE.CylinderGeometry(0.025, 0.025, 0.28, 8),
      new THREE.MeshStandardMaterial({ color: 0x1a1a22, roughness: 0.8 })
    );
    const guard = new THREE.Mesh(
      new THREE.BoxGeometry(0.12, 0.02, 0.12),
      new THREE.MeshStandardMaterial({ color: 0x2b2b33, metalness: 0.6 })
    );
    guard.position.y = 0.16;
    const blade = new THREE.Mesh(
      new THREE.BoxGeometry(0.03, 0.95, 0.01),
      new THREE.MeshStandardMaterial({ color: 0xdfe8ff, metalness: 0.9, roughness: 0.15, emissive: accent, emissiveIntensity: 0.25 })
    );
    blade.position.y = 0.64;
    this.group.add(handle, guard, blade);
    this.group.rotation.set(0.15, 0.2, -0.1);
    this.tip = new THREE.Object3D();
    this.tip.position.set(0, 1.1, 0);
    this.group.add(this.tip);
  }

  _buildBow(accent) {
    const mat = new THREE.MeshStandardMaterial({ color: accent, emissive: accent, emissiveIntensity: 0.8, transparent: true, opacity: 0.85 });
    const arc = new THREE.Mesh(new THREE.TorusGeometry(0.35, 0.012, 8, 24, Math.PI * 1.3), mat);
    arc.rotation.z = Math.PI / 2;
    const string = new THREE.Mesh(new THREE.CylinderGeometry(0.003, 0.003, 0.62, 4),
      new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.6 }));
    this.group.add(arc, string);
    this.group.rotation.set(0, -0.3, 0);
    this.restPos.set(0.2, -0.3, -0.6);
    this.tip = new THREE.Object3D();
    this.tip.position.set(0, 0, 0);
    this.group.add(this.tip);
  }

  _buildClaws(accent) {
    const mat = new THREE.MeshStandardMaterial({ color: 0xf2e9e4, roughness: 0.5, emissive: accent, emissiveIntensity: 0.2 });
    for (let i = 0; i < 3; i++) {
      const claw = new THREE.Mesh(new THREE.ConeGeometry(0.018, 0.22, 6), mat);
      claw.position.set((i - 1) * 0.06, 0, 0);
      claw.rotation.x = -Math.PI / 2.6;
      this.group.add(claw);
    }
    this.group.rotation.set(0.1, 0, 0);
    this.restPos.set(0.28, -0.3, -0.55);
    this.tip = new THREE.Object3D();
    this.tip.position.set(0, 0, -0.2);
    this.group.add(this.tip);
  }

  startSwing(heavy = false) {
    this.swinging = true;
    this.swingT = 0;
    this.swingHeavy = heavy;
    this.swingDir *= -1;
  }

  setCharge(v) { this.charge = THREE.MathUtils.clamp(v, 0, 1); }

  update(dt, speed01 = 0) {
    // View bob proportional to movement speed.
    this.bobT += dt * (6 + speed01 * 8);
    const bobY = Math.sin(this.bobT) * 0.012 * (0.3 + speed01);
    const bobX = Math.cos(this.bobT * 0.5) * 0.01 * (0.3 + speed01);

    let posOffset = new THREE.Vector3(bobX, bobY, 0);
    let extraRotZ = 0, extraRotX = 0;

    if (this.swinging) {
      const dur = this.swingHeavy ? 0.45 : 0.25;
      this.swingT += dt / dur;
      const t = this.swingT;
      // Ease-out arc: quick wind then snap.
      const arc = Math.sin(Math.min(t, 1) * Math.PI);
      extraRotZ = this.swingDir * arc * (this.swingHeavy ? 1.4 : 1.0);
      extraRotX = -arc * (this.swingHeavy ? 0.9 : 0.6);
      posOffset.z += arc * 0.18;
      if (t >= 1) this.swinging = false;
    }

    // Bow draw / heavy charge pulls the model back.
    if (this.charge > 0) {
      posOffset.z += this.charge * 0.12;
      posOffset.x -= this.charge * 0.05;
    }

    this.group.position.copy(this.restPos).add(posOffset);
    this.group.rotation.z = (this.race?.weapon === 'katana' ? -0.1 : 0) + extraRotZ;
    this.group.rotation.x = (this.race?.weapon === 'katana' ? 0.15 : 0.1) + extraRotX;
  }

  dispose() {
    if (this.group.parent) this.group.parent.remove(this.group);
    this.group.traverse((o) => {
      if (o.geometry) o.geometry.dispose();
      if (o.material) o.material.dispose();
    });
  }
}

export default Viewmodel;
