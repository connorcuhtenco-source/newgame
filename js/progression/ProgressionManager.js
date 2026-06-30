// ProgressionManager.js — singleton owning the player's persistent progression:
// level, XP, race resource meter, and the active race "path" module. It is the
// single source of truth that the HUD reads and that CombatSystem/World feed.
// Saves to localStorage so progress survives reloads (and death keeps tiers).

import Events from '../core/EventBus.js';
import Settings from '../config/Settings.js';
import { xpToNext, MAX_LEVEL, DEATH_XP_PENALTY } from '../config/Progression.js';
import { getRace } from '../config/Races.js';
import { SoulReaperPath } from './paths/SoulReaperPath.js';
import { QuincyPath } from './paths/QuincyPath.js';
import { HollowPath } from './paths/HollowPath.js';

const PATHS = {
  soulReaper: SoulReaperPath,
  quincy: QuincyPath,
  hollow: HollowPath,
};

class ProgressionManager {
  constructor() {
    this.race = null;       // race config object
    this.path = null;       // active path instance
    this.level = 1;
    this.xp = 0;
    this.resource = 0;      // race meter (reiryoku/reishi/biomass)
    this.resourceMax = 100;
    this.stats = null;      // derived current stats
  }

  // Called once a race is chosen on the landing page.
  selectRace(raceId) {
    this.race = getRace(raceId);
    if (!this.race) throw new Error(`Unknown race "${raceId}"`);
    this.resourceMax = this.race.resource.max;
    const PathCls = PATHS[this.race.progressionPath];
    this.path = new PathCls(this);
    this.stats = { ...this.race.baseStats };
    this.path.onInit();
    Events.emit('progression:race', { race: this.race });
    this._broadcast();
    return this.race;
  }

  // --- XP / leveling -----------------------------------------------------
  addXp(amount) {
    if (!this.race || this.level >= MAX_LEVEL) return;
    this.xp += amount;
    let leveled = false;
    while (this.level < MAX_LEVEL && this.xp >= xpToNext(this.level)) {
      this.xp -= xpToNext(this.level);
      this.level += 1;
      leveled = true;
      Events.emit('player:levelup', { level: this.level });
      this.path.onLevelUp(this.level);
    }
    if (leveled) this._save();
    this._broadcast();
  }

  // --- Race resource meter ----------------------------------------------
  addResource(amount) {
    if (!this.race) return;
    this.resource = Math.min(this.resourceMax, this.resource + amount);
    this.path.onResourceGain(this.resource, amount);
    this._broadcast();
  }

  spendResource(amount) {
    if (this.resource < amount) return false;
    this.resource -= amount;
    this._broadcast();
    return true;
  }

  // Called when an enemy is defeated; routes rewards through the path so each
  // race converts a kill into its own currency (xp, reishi, biomass...).
  onEnemyDefeated(enemy) {
    this.path.onKill(enemy);
    this._save();
  }

  // Milestone-based, anti-grind death: keep level/tier, lose a sliver of XP.
  onDeath() {
    const penalty = Math.round(xpToNext(this.level) * DEATH_XP_PENALTY);
    this.xp = Math.max(0, this.xp - penalty);
    this.path.onDeath();
    Events.emit('player:death', { keptLevel: this.level });
    this._broadcast();
    this._save();
  }

  get xpForNext() { return xpToNext(this.level); }

  _broadcast() {
    Events.emit('progression:update', this.snapshot());
  }

  snapshot() {
    return {
      race: this.race,
      level: this.level,
      xp: this.xp,
      xpForNext: this.xpForNext,
      resource: this.resource,
      resourceMax: this.resourceMax,
      tier: this.path ? this.path.currentTierLabel() : '',
      stats: this.stats,
    };
  }

  // --- Persistence -------------------------------------------------------
  _save() {
    try {
      const data = {
        raceId: this.race?.id,
        level: this.level,
        xp: this.xp,
        resource: this.resource,
        path: this.path?.serialize?.() ?? {},
      };
      localStorage.setItem(Settings.saveKey, JSON.stringify(data));
    } catch (_) { /* storage may be unavailable */ }
  }

  loadSaved() {
    try {
      const raw = localStorage.getItem(Settings.saveKey);
      if (!raw) return null;
      return JSON.parse(raw);
    } catch (_) { return null; }
  }

  applySaved(data) {
    if (!data || !data.raceId) return;
    this.selectRace(data.raceId);
    this.level = data.level ?? 1;
    this.xp = data.xp ?? 0;
    this.resource = data.resource ?? 0;
    this.path?.deserialize?.(data.path || {});
    this._broadcast();
  }
}

export const Progression = new ProgressionManager();
export default Progression;
