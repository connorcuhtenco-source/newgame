// Progression.js — milestone-based progression config (anti-grind).
// XP curve is intentionally shallow so tier-ups feel like story beats, not a
// numbers treadmill. Each race has named milestones consumed by its path module.

// Gentle curve: xp needed to go from level L -> L+1.
export function xpToNext(level) {
  return Math.round(60 + level * 35 + Math.pow(level, 1.4) * 6);
}

export const MAX_LEVEL = 50;

// On death the player keeps levels/tiers and loses only a small XP slice.
export const DEATH_XP_PENALTY = 0.05; // 5% of current-level progress

export const MILESTONES = {
  soulReaper: {
    // Reaching these levels triggers instanced unlock content.
    shikaiLevel: 5,    // → Inner World instance, unlocks Z/X/C element skills
    bankaiLevel: 15,   // → 1v1 weapon-spirit boss fight
    tiers: [
      { id: 'trainee', name: 'Trainee', minLevel: 1, weapon: 'Asauchi Katana', skills: [] },
      { id: 'shikai', name: 'Shikai', minLevel: 5, weapon: 'Released Zanpakutō', skills: ['Z', 'X', 'C'] },
      { id: 'bankai', name: 'Bankai', minLevel: 15, weapon: 'Bankai', skills: ['Z', 'X', 'C', 'V'] },
    ],
  },

  quincy: {
    // Reishi (separate meter) is spent on a skill tree of arrow types.
    arrowTree: [
      { id: 'standard', name: 'Standard Arrow', cost: 0, unlockedByDefault: true },
      { id: 'explosive', name: 'Explosive Arrow', cost: 40 },
      { id: 'tracking', name: 'Tracking Arrow', cost: 70 },
    ],
    // Vollständig (ultimate) unlocked by surviving a wave-defense trial.
    vollstandig: { trial: 'waveDefense', waves: 5 },
  },

  hollow: {
    // Evolution tiers gated by accumulated Biomass. Never downgrade.
    tiers: [
      { id: 'fishbone', name: 'Fishbone', biomass: 0, traits: ['basic'] },
      { id: 'gillian', name: 'Gillian', biomass: 150, traits: ['giant', 'slow', 'cero'] },
      { id: 'adjuchas', name: 'Adjuchas', biomass: 400, traits: ['fast', 'wallRun'] },
      { id: 'arrancar', name: 'Arrancar', biomass: 800, traits: ['humanoid', 'resurreccion'] },
    ],
  },
};

export default MILESTONES;
