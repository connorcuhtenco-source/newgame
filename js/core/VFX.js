// VFX.js — visual effects hub: 3D particles (sparks, auras, dash afterimages)
// plus screen-space DOM effects (parry flash, screen shake, reiatsu vignette,
// directional damage indicators). Driven by EventBus events where convenient,
// but also exposes direct methods for systems that already hold a reference.

import * as THREE from 'three';
import Events from './EventBus.js';

class VFXManager {
  init({ scene, camera, screenEl }) {
    this.scene = scene;
    this.camera = camera;
    this.screen = screenEl;       // overlay element for flashes/vignette
    this.sparks = [];             // active spark particle systems
    this.afterimages = [];        // dash afterimage meshes
    this.shake = { mag: 0, decay: 6 };
    this._wire();
  }

  _wire() {
    Events.on('combat:hit', (p) => this.sparks3D(p?.point, 0xfff1a8, 26));
    Events.on('combat:parry', (p) => { this.parryFlash(); this.sparks3D(p?.point, 0xbff4ff, 40); this.addShake(0.5); });
    Events.on('combat:heavy', () => this.addShake(0.35));
    Events.on('player:hurt', (p) => this.damageIndicator(p?.dir ?? 0));
  }

  addShake(mag) { this.shake.mag = Math.min(1.2, this.shake.mag + mag); }

  // Burst of GPU points at a world position.
  sparks3D(point, color = 0xffffff, count = 24) {
    if (!this.scene) return;
    const origin = point || new THREE.Vector3(0, 1.5, 0);
    const positions = new Float32Array(count * 3);
    const velocities = [];
    for (let i = 0; i < count; i++) {
      positions[i * 3] = origin.x;
      positions[i * 3 + 1] = origin.y;
      positions[i * 3 + 2] = origin.z;
      velocities.push(new THREE.Vector3(
        (Math.random() - 0.5) * 6,
        Math.random() * 5,
        (Math.random() - 0.5) * 6
      ));
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    const mat = new THREE.PointsMaterial({ color, size: 0.12, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending });
    const points = new THREE.Points(geo, mat);
    this.scene.add(points);
    this.sparks.push({ points, geo, mat, velocities, life: 0, ttl: 0.5 });
  }

  // Spawn a translucent clone of a mesh that fades out (dash afterimage).
  afterimage(sourceMesh, color = 0x8fd4ff) {
    if (!this.scene || !sourceMesh) return;
    const mat = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.5, blending: THREE.AdditiveBlending, depthWrite: false });
    const clone = new THREE.Mesh(sourceMesh.geometry || new THREE.CapsuleGeometry(0.4, 1, 4, 8), mat);
    clone.position.copy(sourceMesh.position);
    clone.quaternion.copy(sourceMesh.quaternion);
    this.scene.add(clone);
    this.afterimages.push({ mesh: clone, mat, life: 0, ttl: 0.4 });
  }

  // --- Screen-space DOM effects -----------------------------------------
  parryFlash() {
    if (!this.screen) return;
    this.screen.classList.remove('parry-flash');
    void this.screen.offsetWidth; // restart animation
    this.screen.classList.add('parry-flash');
  }

  // dir in radians relative to where the player faces (0 = front).
  damageIndicator(dir = 0) {
    if (!this.screen) return;
    const el = document.createElement('div');
    el.className = 'dmg-indicator';
    el.style.setProperty('--dmg-rot', `${dir}rad`);
    this.screen.appendChild(el);
    setTimeout(() => el.remove(), 700);
  }

  setReiatsuVignette(intensity, colorHex = '#7df9ff') {
    if (!this.screen) return;
    this.screen.style.setProperty('--reiatsu-intensity', intensity.toFixed(2));
    this.screen.style.setProperty('--reiatsu-color', colorHex);
  }

  update(dt) {
    // Sparks
    for (let i = this.sparks.length - 1; i >= 0; i--) {
      const s = this.sparks[i];
      s.life += dt;
      const pos = s.geo.attributes.position.array;
      for (let j = 0; j < s.velocities.length; j++) {
        s.velocities[j].y -= 14 * dt; // gravity
        pos[j * 3] += s.velocities[j].x * dt;
        pos[j * 3 + 1] += s.velocities[j].y * dt;
        pos[j * 3 + 2] += s.velocities[j].z * dt;
      }
      s.geo.attributes.position.needsUpdate = true;
      s.mat.opacity = Math.max(0, 1 - s.life / s.ttl);
      if (s.life >= s.ttl) {
        this.scene.remove(s.points);
        s.geo.dispose(); s.mat.dispose();
        this.sparks.splice(i, 1);
      }
    }
    // Afterimages
    for (let i = this.afterimages.length - 1; i >= 0; i--) {
      const a = this.afterimages[i];
      a.life += dt;
      a.mat.opacity = Math.max(0, 0.5 * (1 - a.life / a.ttl));
      if (a.life >= a.ttl) {
        this.scene.remove(a.mesh);
        a.mat.dispose();
        this.afterimages.splice(i, 1);
      }
    }
    // Camera shake (applied as additive offset by PlayerController via getShakeOffset)
    if (this.shake.mag > 0) {
      this.shake.mag = Math.max(0, this.shake.mag - this.shake.decay * dt);
    }
  }

  getShakeOffset() {
    const m = this.shake.mag;
    if (m <= 0) return { x: 0, y: 0, roll: 0 };
    return {
      x: (Math.random() - 0.5) * 0.12 * m,
      y: (Math.random() - 0.5) * 0.12 * m,
      roll: (Math.random() - 0.5) * 0.04 * m,
    };
  }
}

export const VFX = new VFXManager();
export default VFX;
