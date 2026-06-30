// World.js — builds the "Soul Society" map: a nocturnal indigo training ground
// with a stone path, a great torii gate, glowing paper lanterns (flickering
// point lights), a low moon, layered platforms, and drifting blue Reishi flakes.
// Keeps the active enemy list and updates AI + ambient motion.

import * as THREE from 'three';
import Events from './EventBus.js';
import { Enemy } from './Enemy.js';

export class World {
  constructor(scene, raceAccent = '#6fd3ff') {
    this.scene = scene;
    this.accent = new THREE.Color(raceAccent);
    this.enemies = [];
    this.maxEnemies = 6;
    this.spawnTimer = 2;
    this.lanterns = [];     // { light, mesh, base, phase, speed }
    this.flakeT = 0;
    this._build(raceAccent);

    Events.on('enemy:defeated', ({ enemy }) => {
      const idx = this.enemies.indexOf(enemy);
      if (idx >= 0) this.enemies.splice(idx, 1);
      Events.emit('world:enemyDown', { remaining: this.enemies.length });
    });
  }

  _build(accent) {
    // Deep indigo night + atmospheric fog.
    this.scene.background = new THREE.Color(0x070612);
    this.scene.fog = new THREE.Fog(0x0a0a1c, 26, 120);

    this._buildGround(accent);
    this._buildLighting(accent);
    this._buildMoon();
    this._buildTorii();
    this._buildPlatforms();
    this._buildLanterns(accent);
    this._buildReishi(accent);
  }

  _buildGround(accent) {
    // Stone courtyard: dark slate with a faint tile grid.
    const ground = new THREE.Mesh(
      new THREE.PlaneGeometry(160, 160, 1, 1),
      new THREE.MeshStandardMaterial({ color: 0x141a2c, roughness: 0.9, metalness: 0.05 })
    );
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    this.scene.add(ground);

    const grid = new THREE.GridHelper(160, 64, new THREE.Color(accent), 0x1a2238);
    grid.material.opacity = 0.18;
    grid.material.transparent = true;
    grid.position.y = 0.02;
    this.scene.add(grid);

    // A lighter central stone path leading to the torii.
    const path = new THREE.Mesh(
      new THREE.PlaneGeometry(6, 70),
      new THREE.MeshStandardMaterial({ color: 0x2a3148, roughness: 0.85 })
    );
    path.rotation.x = -Math.PI / 2;
    path.position.set(0, 0.03, -10);
    this.scene.add(path);
  }

  _buildLighting(accent) {
    this.scene.add(new THREE.HemisphereLight(0x3a4a8a, 0x05060f, 0.5));
    // Cool moonlight key.
    const moonlight = new THREE.DirectionalLight(0x9fb0ff, 0.7);
    moonlight.position.set(-18, 30, -22);
    moonlight.castShadow = true;
    moonlight.shadow.mapSize.set(1024, 1024);
    moonlight.shadow.camera.far = 120;
    this.scene.add(moonlight);
    // Accent rim from the player's spiritual color.
    const rim = new THREE.PointLight(accent, 1.0, 70);
    rim.position.set(8, 10, 12);
    this.scene.add(rim);
  }

  _buildMoon() {
    // Bright crescent-ish moon that ignores fog so it stays in the sky.
    const moon = new THREE.Mesh(
      new THREE.SphereGeometry(7, 24, 24),
      new THREE.MeshBasicMaterial({ color: 0xeaf0ff, fog: false })
    );
    moon.position.set(-40, 48, -90);
    this.scene.add(moon);
    const glow = new THREE.Mesh(
      new THREE.SphereGeometry(10, 20, 20),
      new THREE.MeshBasicMaterial({ color: 0x88a0ff, transparent: true, opacity: 0.18, fog: false, blending: THREE.AdditiveBlending, depthWrite: false })
    );
    glow.position.copy(moon.position);
    this.scene.add(glow);
  }

  _buildTorii() {
    const wood = new THREE.MeshStandardMaterial({ color: 0x8a2b2b, roughness: 0.7 });
    const dark = new THREE.MeshStandardMaterial({ color: 0x401414, roughness: 0.7 });
    const g = new THREE.Group();
    const colGeo = new THREE.CylinderGeometry(0.6, 0.7, 12, 10);
    for (const x of [-5, 5]) {
      const col = new THREE.Mesh(colGeo, wood);
      col.position.set(x, 6, 0);
      col.castShadow = true;
      g.add(col);
    }
    const top = new THREE.Mesh(new THREE.BoxGeometry(15, 1.1, 1.4), dark);
    top.position.set(0, 12.2, 0);
    const top2 = new THREE.Mesh(new THREE.BoxGeometry(13, 0.7, 1.0), wood);
    top2.position.set(0, 10.6, 0);
    g.add(top, top2);
    g.position.set(0, 0, -34);
    this.scene.add(g);
  }

  _buildPlatforms() {
    // Tiered stone platforms flanking the courtyard for layered structure.
    const mat = new THREE.MeshStandardMaterial({ color: 0x222a40, roughness: 0.85 });
    for (const side of [-1, 1]) {
      for (let i = 0; i < 3; i++) {
        const w = 10 - i * 2;
        const step = new THREE.Mesh(new THREE.BoxGeometry(w, 1.2, 26), mat);
        step.position.set(side * (22 + i * 3), 0.6 + i * 1.2, -6);
        step.castShadow = true; step.receiveShadow = true;
        this.scene.add(step);
      }
    }
  }

  _buildLanterns(accent) {
    const postMat = new THREE.MeshStandardMaterial({ color: 0x1a120c, roughness: 0.8 });
    const paperMat = new THREE.MeshStandardMaterial({
      color: 0xffb060, emissive: 0xff8a30, emissiveIntensity: 1.2, roughness: 0.5,
    });
    const positions = [];
    for (let i = 0; i < 8; i++) {
      const z = -2 - i * 4;
      positions.push([-3.6, z], [3.6, z]);
    }
    for (const [x, z] of positions) {
      const post = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.1, 3.0, 6), postMat);
      post.position.set(x, 1.5, z);
      const lantern = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.55, 10), paperMat.clone());
      lantern.position.set(x, 3.1, z);
      const light = new THREE.PointLight(0xffa64d, 1.0, 14);
      light.position.copy(lantern.position);
      this.scene.add(post, lantern, light);
      this.lanterns.push({
        light, mesh: lantern, base: 1.0,
        phase: Math.random() * Math.PI * 2, speed: 4 + Math.random() * 3,
      });
    }
  }

  _buildReishi(accent) {
    // Drifting blue spiritual-energy flakes.
    this.flakeCount = 260;
    const positions = new Float32Array(this.flakeCount * 3);
    this.flakeVel = [];
    for (let i = 0; i < this.flakeCount; i++) {
      positions[i * 3] = (Math.random() - 0.5) * 120;
      positions[i * 3 + 1] = Math.random() * 26;
      positions[i * 3 + 2] = (Math.random() - 0.5) * 120;
      this.flakeVel.push(0.3 + Math.random() * 0.6);
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    const mat = new THREE.PointsMaterial({
      color: new THREE.Color(0x8fd0ff).lerp(this.accent, 0.4),
      size: 0.16, transparent: true, opacity: 0.7,
      depthWrite: false, blending: THREE.AdditiveBlending,
    });
    this.flakes = new THREE.Points(geo, mat);
    this.flakes.frustumCulled = false;
    this.scene.add(this.flakes);
  }

  spawnEnemy() {
    if (this.enemies.length >= this.maxEnemies) return;
    const a = Math.random() * Math.PI * 2;
    const r = 18 + Math.random() * 16;
    const pos = new THREE.Vector3(Math.cos(a) * r, 0, Math.sin(a) * r);
    const enemy = new Enemy(this.scene, pos, {
      health: 50 + Math.random() * 30,
      speed: 2.2 + Math.random() * 1.4,
      damage: 7 + Math.random() * 4,
      xp: 22, biomass: 35,
    });
    this.enemies.push(enemy);
  }

  getEnemies() { return this.enemies; }

  update(dt, player, combat, camera) {
    this.spawnTimer -= dt;
    if (this.spawnTimer <= 0) {
      this.spawnTimer = 3.5;
      this.spawnEnemy();
    }
    for (const e of this.enemies) e.update(dt, player, combat, camera);

    // Lantern flicker.
    for (const l of this.lanterns) {
      l.phase += dt * l.speed;
      const n = Math.sin(l.phase) * 0.5 + Math.sin(l.phase * 2.3) * 0.5;
      l.light.intensity = l.base + n * 0.4;
      l.mesh.material.emissiveIntensity = 1.0 + n * 0.5;
    }

    // Reishi flakes drift upward + gentle sway, recycled at the top.
    if (this.flakes) {
      this.flakeT += dt;
      const pos = this.flakes.geometry.attributes.position.array;
      for (let i = 0; i < this.flakeCount; i++) {
        pos[i * 3 + 1] += this.flakeVel[i] * dt;
        pos[i * 3] += Math.sin(this.flakeT + i) * dt * 0.15;
        if (pos[i * 3 + 1] > 26) {
          pos[i * 3 + 1] = 0;
          pos[i * 3] = (Math.random() - 0.5) * 120;
          pos[i * 3 + 2] = (Math.random() - 0.5) * 120;
        }
      }
      this.flakes.geometry.attributes.position.needsUpdate = true;
    }
  }
}

export default World;
