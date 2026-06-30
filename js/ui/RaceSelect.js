// RaceSelect.js — landing-page race picker. Renders three large cards from the
// RACES config. Hovering plays a UI sound + reveals the description; clicking
// locks in the race (sets base stats via ProgressionManager) and signals the
// Game to spawn the player into the starting map.

import Events from '../core/EventBus.js';
import Audio from '../core/AudioManager.js';
import RACES from '../config/Races.js';

export class RaceSelect {
  constructor(rootEl, onSelect) {
    this.root = rootEl;
    this.onSelect = onSelect;
    this._render();
  }

  _render() {
    const grid = this.root.querySelector('#raceGrid');
    grid.innerHTML = '';
    for (const race of Object.values(RACES)) {
      const card = document.createElement('article');
      card.className = 'race-card';
      card.style.setProperty('--accent', race.accent);
      card.innerHTML = `
        <div class="race-card-glow"></div>
        <div class="race-icon" data-weapon="${race.weapon}"></div>
        <h3 class="race-name">${race.name}</h3>
        <p class="race-role">${race.role}</p>
        <p class="race-blurb">${race.blurb}</p>
        <ul class="race-stats">
          <li><span>HP</span><b>${race.baseStats.maxHealth}</b></li>
          <li><span>SPD</span><b>${race.baseStats.moveSpeed.toFixed(1)}</b></li>
          <li><span>${race.resource.label}</span><b>${race.resource.max}</b></li>
        </ul>
        <button class="race-pick-btn">Choose ${race.name}</button>
      `;

      card.addEventListener('mouseenter', () => {
        Audio.init();
        Events.emit('ui:hover');
        card.classList.add('hovered');
      });
      card.addEventListener('mouseleave', () => card.classList.remove('hovered'));

      const pick = () => {
        Audio.init();
        Events.emit('ui:click');
        this._lockIn(race.id);
      };
      card.querySelector('.race-pick-btn').addEventListener('click', pick);
      grid.appendChild(card);
    }
  }

  _lockIn(raceId) {
    this.root.classList.add('selecting');
    // Brief flourish before transitioning into the map.
    setTimeout(() => {
      this.root.classList.add('hidden');
      this.onSelect?.(raceId);
    }, 600);
  }

  show() {
    this.root.classList.remove('hidden', 'selecting');
  }
}

export default RaceSelect;
