// SoulReaperPath.js — Soul Reaper milestone logic.
// Trainee → Shikai (Inner World instance @ lvl 5, unlocks Z/X/C elemental
// skills) → Bankai (1v1 weapon-spirit boss fight @ lvl 15). Kills grant XP and
// a little Reiryoku. Milestones emit events the world/UI react to (open the
// instance, queue the boss fight, etc.).

import Events from '../../core/EventBus.js';
import { MILESTONES } from '../../config/Progression.js';

export class SoulReaperPath {
  constructor(pm) {
    this.pm = pm;
    this.cfg = MILESTONES.soulReaper;
    this.tierId = 'trainee';
    this.unlockedSkills = [];
    this.shikaiTriggered = false;
    this.bankaiTriggered = false;
  }

  onInit() {}

  currentTierLabel() {
    const t = this.cfg.tiers.find((x) => x.id === this.tierId);
    return t ? t.name : 'Trainee';
  }

  onLevelUp(level) {
    if (!this.shikaiTriggered && level >= this.cfg.shikaiLevel) {
      this.shikaiTriggered = true;
      // Defer the actual unlock until the player clears the Inner World content.
      Events.emit('milestone:instance', {
        race: 'soulReaper',
        type: 'innerWorld',
        title: 'Shikai Awakening',
        desc: 'Enter your Inner World to commune with your Zanpakutō spirit.',
        onComplete: () => this._unlockShikai(),
      });
    }
    if (!this.bankaiTriggered && level >= this.cfg.bankaiLevel) {
      this.bankaiTriggered = true;
      Events.emit('milestone:instance', {
        race: 'soulReaper',
        type: 'bossFight',
        title: 'Bankai Trial',
        desc: 'Defeat your weapon spirit in single combat to claim your Bankai.',
        onComplete: () => this._unlockBankai(),
      });
    }
  }

  _unlockShikai() {
    this.tierId = 'shikai';
    this.unlockedSkills = ['Z', 'X', 'C'];
    Events.emit('progression:tier', { race: 'soulReaper', tier: 'shikai', skills: this.unlockedSkills });
    this.pm._broadcast();
  }

  _unlockBankai() {
    this.tierId = 'bankai';
    this.unlockedSkills = ['Z', 'X', 'C', 'V'];
    Events.emit('progression:tier', { race: 'soulReaper', tier: 'bankai', skills: this.unlockedSkills });
    this.pm._broadcast();
  }

  onKill(enemy) {
    this.pm.addXp(enemy?.xp ?? 25);
    this.pm.addResource(8); // Reiryoku trickle
  }

  onResourceGain() {}

  onDeath() { /* keeps tier + skills (anti-grind rule) */ }

  serialize() {
    return { tierId: this.tierId, skills: this.unlockedSkills, shikai: this.shikaiTriggered, bankai: this.bankaiTriggered };
  }

  deserialize(d) {
    this.tierId = d.tierId ?? 'trainee';
    this.unlockedSkills = d.skills ?? [];
    this.shikaiTriggered = !!d.shikai;
    this.bankaiTriggered = !!d.bankai;
  }
}

export default SoulReaperPath;
