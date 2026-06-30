// Races.js — data-driven race definitions (think Unity ScriptableObjects).
// All balance/identity lives here so designers can tune without touching logic.
// PlayerController, CombatSystem, HUD and ProgressionManager all read from this.

export const RACES = {
  soulReaper: {
    id: 'soulReaper',
    name: 'Soul Reaper',
    role: 'Melee / Sword',
    blurb: 'Disciplined blade masters. Channel a Zanpakutō through Shikai and Bankai for devastating elemental sword arts.',
    accent: '#6fd3ff',
    weapon: 'katana',
    baseStats: {
      maxHealth: 120,
      moveSpeed: 7.0,
      sprintMult: 1.5,
      dashForce: 24,
      dashCooldown: 1.1,
      lightDamage: 12,
      heavyDamage: 30,
      attackRange: 3.2,
    },
    // Race-specific resource shown on the HUD.
    resource: { key: 'reiryoku', label: 'Reiryoku', color: '#6fd3ff', max: 100 },
    progressionPath: 'soulReaper',
  },

  quincy: {
    id: 'quincy',
    name: 'Quincy',
    role: 'Ranged / Bow',
    blurb: 'Reishi marksmen. Absorb ambient spirit particles to forge a Heilig Bogen and rain down specialized arrows.',
    accent: '#7dffa8',
    weapon: 'bow',
    baseStats: {
      maxHealth: 95,
      moveSpeed: 7.4,
      sprintMult: 1.55,
      dashForce: 22,
      dashCooldown: 1.0,
      lightDamage: 9,    // rapid arrow
      heavyDamage: 26,   // charged shot
      attackRange: 60,   // projectile reach
    },
    resource: { key: 'reishi', label: 'Reishi', color: '#7dffa8', max: 100 },
    progressionPath: 'quincy',
  },

  hollow: {
    id: 'hollow',
    name: 'Hollow',
    role: 'Brawler / Evolution',
    blurb: 'Ravenous masked souls. Devour the fallen to harvest Biomass and evolve from Fishbone to fearsome Arrancar.',
    accent: '#ff6f8b',
    weapon: 'claws',
    baseStats: {
      maxHealth: 150,
      moveSpeed: 7.8,
      sprintMult: 1.6,
      dashForce: 26,
      dashCooldown: 0.9,
      lightDamage: 14,
      heavyDamage: 34,
      attackRange: 2.8,
    },
    resource: { key: 'biomass', label: 'Biomass', color: '#ff6f8b', max: 100 },
    progressionPath: 'hollow',
  },
};

export function getRace(id) {
  return RACES[id] || null;
}

export default RACES;
