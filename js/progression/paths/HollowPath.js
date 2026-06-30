// HollowPath.js — Hollow evolution logic.
// Kills grant Biomass (the race resource). Accumulated Biomass evolves the
// player through tiers: Fishbone → Gillian → Adjuchas → Arrancar. Hard rule:
// once a tier is reached the player can NEVER be downgraded.

import Events from '../../core/EventBus.js';
import { MILESTONES } from '../../config/Progression.js';

export class HollowPath {
  constructor(pm) {
    this.pm = pm;
    this.cfg = MILESTONES.hollow;
    this.totalBiomass = 0;       // lifetime biomass (never decreases)
    this.tierIndex = 0;          // index into cfg.tiers
  }

  onInit() {}

  currentTier() { return this.cfg.tiers[this.tierIndex]; }
  currentTierLabel() { return this.currentTier().name; }

  onKill(enemy) {
    this.pm.addXp(enemy?.xp ?? 20);
    const gained = enemy?.biomass ?? 35;
    this.totalBiomass += gained;
    this.pm.addResource(gained); // fills the visible Biomass meter
    this._checkEvolution();
  }

  // Resource gain also nudges evolution (e.g. absorbing biomass pickups).
  onResourceGain() { this._checkEvolution(); }

  _checkEvolution() {
    // Only ever step UP the tier ladder — never down.
    for (let i = this.cfg.tiers.length - 1; i > this.tierIndex; i--) {
      if (this.totalBiomass >= this.cfg.tiers[i].biomass) {
        const from = this.currentTier();
        this.tierIndex = i;
        const to = this.currentTier();
        // Evolving resets the visible meter toward the next threshold.
        this.pm.resource = 0;
        Events.emit('progression:tier', {
          race: 'hollow', from: from.id, tier: to.id, traits: to.traits,
        });
        Events.emit('player:levelup', { level: this.pm.level }); // celebratory cue
        this.pm._broadcast();
        break;
      }
    }
  }

  onLevelUp() {}

  onDeath() { /* tier is permanent — cannot downgrade */ }

  serialize() {
    return { totalBiomass: this.totalBiomass, tierIndex: this.tierIndex };
  }

  deserialize(d) {
    this.totalBiomass = d.totalBiomass ?? 0;
    this.tierIndex = d.tierIndex ?? 0;
  }
}

export default HollowPath;
