// QuincyPath.js — Quincy progression logic.
// Passive Reishi absorption: defeating enemies fills the Reishi meter, which is
// spent on a skill tree to unlock arrow types (Explosive, Tracking). The
// Vollständig ultimate unlocks after surviving a wave-defense trial.

import Events from '../../core/EventBus.js';
import { MILESTONES } from '../../config/Progression.js';

export class QuincyPath {
  constructor(pm) {
    this.pm = pm;
    this.cfg = MILESTONES.quincy;
    this.unlockedArrows = ['standard'];
    this.selectedArrow = 'standard';
    this.vollstandig = false;
    this.wavesSurvived = 0;
  }

  onInit() {}

  currentTierLabel() {
    return this.vollstandig ? 'Vollständig' : 'Letzt Stil';
  }

  // Spend Reishi to unlock an arrow type from the tree.
  unlockArrow(id) {
    const node = this.cfg.arrowTree.find((n) => n.id === id);
    if (!node || this.unlockedArrows.includes(id)) return false;
    if (!this.pm.spendResource(node.cost)) return false;
    this.unlockedArrows.push(id);
    Events.emit('progression:tier', { race: 'quincy', unlocked: id });
    this.pm._broadcast();
    return true;
  }

  // Called by the wave-defense trial each time a wave is cleared.
  reportWaveCleared() {
    this.wavesSurvived += 1;
    if (!this.vollstandig && this.wavesSurvived >= this.cfg.vollstandig.waves) {
      this.vollstandig = true;
      Events.emit('progression:tier', { race: 'quincy', tier: 'vollstandig' });
      this.pm._broadcast();
    }
  }

  onLevelUp() {}

  onKill(enemy) {
    this.pm.addXp(enemy?.xp ?? 22);
    this.pm.addResource(12); // Reishi absorption on kill
  }

  onResourceGain() {}

  onDeath() {}

  serialize() {
    return { arrows: this.unlockedArrows, voll: this.vollstandig, waves: this.wavesSurvived };
  }

  deserialize(d) {
    this.unlockedArrows = d.arrows ?? ['standard'];
    this.vollstandig = !!d.voll;
    this.wavesSurvived = d.waves ?? 0;
  }
}

export default QuincyPath;
