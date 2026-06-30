// World.js — builds the starting map (the "Soul Society" training grounds):
// ground, lighting, skybox tint, scattered pillars, and an enemy spawner used
// to test combat & progression. Keeps the active enemy list and updates AI.

import * as THREE from 'three';
import Events from '../core/EventBus.js';
import { Enemy } from './Enemy.js';

export class World {
  constructor(scene, raceAccent = '#6fd3ff') {
    this.scene = scene;
    this.enemies = [];
    this.maxEnemies = 6;
    this.spawnTimer = 2;
    this._build(raceAccent);

    Events.on('enemy:defeated', ({ enemy }) => {
      const idx = this.enemies.indexOf(enemy);
      if (idx >= 0) this.enemies.splice(idx, 1);
      Events.emit('world:enemyDown', { remaining: this.enemies.length });
    });
  }

  _build(accent) {
    // Atmospheric fog + tinted background.
    this.scene.background = new THREE.Color(0x0b1020);
    this.scene.fog = new THREE.Fog(0x0b1020, 30, 110);

    // Ground
    const ground = new THREE.Mesh(
      new THREE.PlaneGeometry(120, 120, 1, 1),
      new THREE.MeshStandardMaterial({ color: 0x1a2236, roughness: 0.95 })
    );
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    this.scene.add(ground);

    // Subtle grid to convey scale/speed.
    const grid = new THREE.GridHelper(120, 60, new THREE.Color(accent), 0x223046);
    grid.material.opacity = 0.25;
    grid.material.transparent = true;
    this.scene.add(grid);

    // Lighting: cool ambient + key light + accent rim.
    this.scene.add(new THREE.HemisphereLight(0x9fb8ff, 0x0a0a12, 0.6));
    const key = new THREE.DirectionalLight(0xffffff, 0.9);
    key.position.set(10, 20, 6);
    key.castShadow = true;
    key.shadow.mapSize.set(1024, 1024);
    this.scene.add(key);
    const rim = new THREE.PointLight(new THREE.Color(accent), 1.2, 60);
    rim.position.set(-8, 8, -10);
    this.scene.add(rim);

    // Pillars for cover / spatial reference.
    const pillarMat = new THREE.MeshStandardMaterial({ color: 0x2a3450, roughness: 0.8 });
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * Math.PI * 2;
      const r = 22 + (i % 3) * 6;
      const pillar = new THREE.Mesh(new THREE.CylinderGeometry(1.2, 1.4, 9, 8), pillarMat);
      pillar.position.set(Math.cos(a) * r, 4.5, Math.sin(a) * r);
      pillar.castShadow = true;
      this.scene.add(pillar);
    }
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
  }
}

export default World;
