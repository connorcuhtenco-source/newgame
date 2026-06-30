// HUD.js — in-game heads-up display. Subscribes to EventBus signals and keeps
// the DOM in sync: health, level, XP bar, race resource meter, current tier,
// combo counter, crosshair feedback, reiatsu aura vignette, milestone toasts,
// and the death/respawn banner. Pure presentation — holds no game logic.

import Events from '../core/EventBus.js';

export class HUD {
  constructor(rootEl) {
    this.root = rootEl;
    this.el = {
      health: rootEl.querySelector('#hpFill'),
      healthText: rootEl.querySelector('#hpText'),
      level: rootEl.querySelector('#lvlValue'),
      xp: rootEl.querySelector('#xpFill'),
      resource: rootEl.querySelector('#resFill'),
      resourceLabel: rootEl.querySelector('#resLabel'),
      tier: rootEl.querySelector('#tierValue'),
      combo: rootEl.querySelector('#comboCounter'),
      crosshair: rootEl.querySelector('#crosshair'),
      toast: rootEl.querySelector('#milestoneToast'),
      skills: rootEl.querySelector('#skillBar'),
      death: rootEl.querySelector('#deathBanner'),
    };
    this._comboHideT = null;
    this._wire();
  }

  _wire() {
    Events.on('progression:update', (s) => this.renderProgress(s));
    Events.on('hud:health', ({ health, max }) => this.setHealth(health, max));
    Events.on('combat:combo', ({ step }) => this.showCombo(step));
    Events.on('combat:hit', () => this.hitMarker());
    Events.on('progression:tier', (d) => this.toast(`Unlocked: ${d.tier || d.unlocked || ''}`.toUpperCase()));
    Events.on('milestone:instance', (m) => this.toast(`${m.title} — ${m.desc}`, 4200));
    Events.on('player:death', () => this.showDeath());
    Events.on('player:respawn', () => this.hideDeath());
    Events.on('player:aura', ({ active, color, intensity }) => this.setAura(active, color, intensity));
  }

  setHealth(health, max) {
    this.curHealth = health;
    this.maxHealth = max;
    const pct = Math.max(0, health / max) * 100;
    if (this.el.health) this.el.health.style.width = `${pct}%`;
    if (this.el.healthText) this.el.healthText.textContent = `${Math.ceil(health)}/${max}`;
    if (this.el.health) this.el.health.classList.toggle('low', pct < 30);
  }

  renderProgress(s) {
    if (!s.race) return;
    this.el.level.textContent = s.level;
    this.el.tier.textContent = s.tier || '';
    const xpPct = Math.min(100, (s.xp / s.xpForNext) * 100);
    this.el.xp.style.width = `${xpPct}%`;
    const resPct = Math.min(100, (s.resource / s.resourceMax) * 100);
    this.el.resource.style.width = `${resPct}%`;
    this.el.resource.style.background = s.race.resource.color;
    this.el.resourceLabel.textContent = s.race.resource.label;
    // Preserve the live health value across progression refreshes.
    this.setHealth(this.curHealth ?? s.stats.maxHealth, s.stats.maxHealth);
  }

  initHealth(max) { this.curHealth = max; this.setHealth(max, max); }

  showCombo(step) {
    if (!this.el.combo) return;
    this.el.combo.textContent = `${step} HIT`;
    this.el.combo.classList.add('active');
    clearTimeout(this._comboHideT);
    this._comboHideT = setTimeout(() => this.el.combo.classList.remove('active'), 900);
  }

  hitMarker() {
    if (!this.el.crosshair) return;
    this.el.crosshair.classList.remove('hit');
    void this.el.crosshair.offsetWidth;
    this.el.crosshair.classList.add('hit');
  }

  toast(text, ms = 2600) {
    if (!this.el.toast) return;
    this.el.toast.textContent = text;
    this.el.toast.classList.add('show');
    clearTimeout(this._toastT);
    this._toastT = setTimeout(() => this.el.toast.classList.remove('show'), ms);
  }

  setAura(active, color = '#7df9ff', intensity = 0) {
    this.root.style.setProperty('--reiatsu-color', color);
    this.root.style.setProperty('--reiatsu-intensity', active ? intensity.toFixed(2) : '0');
    this.root.classList.toggle('reiatsu-active', active);
  }

  setSkills(skills = []) {
    if (!this.el.skills) return;
    this.el.skills.innerHTML = '';
    const map = { Z: 'Skill I', X: 'Skill II', C: 'Skill III', V: 'Ultimate' };
    for (const key of skills) {
      const slot = document.createElement('div');
      slot.className = 'skill-slot';
      slot.innerHTML = `<kbd>${key}</kbd><span>${map[key] || ''}</span>`;
      this.el.skills.appendChild(slot);
    }
  }

  showDeath() { this.el.death?.classList.add('show'); }
  hideDeath() { this.el.death?.classList.remove('show'); }
}

export default HUD;
