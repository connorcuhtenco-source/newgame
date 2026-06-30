// main.js — bootstrap. Wires the landing-page race selector to the Game, then
// hands control over once a race is chosen. This is the only script referenced
// by index.html (everything else is pulled in via ES module imports).

import game from './core/Game.js';
import Audio from './core/AudioManager.js';
import { RaceSelect } from './ui/RaceSelect.js';

window.addEventListener('DOMContentLoaded', () => {
  const canvas = document.getElementById('gl');
  const hudRoot = document.getElementById('hud');
  const screenEl = document.getElementById('screenfx');
  const landing = document.getElementById('landing');

  game.init({ canvas, hudRoot, screenEl });

  const raceSelect = new RaceSelect(landing, (raceId) => {
    Audio.init();
    Audio.resume();
    document.getElementById('gameLayer').classList.remove('hidden');
    document.getElementById('lockHint').classList.remove('hidden');
    game.startWithRace(raceId);
  });

  // Hide the "click to play" hint once pointer lock engages.
  game && document.addEventListener('pointerlockchange', () => {
    const hint = document.getElementById('lockHint');
    if (!hint) return;
    hint.classList.toggle('hidden', document.pointerLockElement != null);
  });

  raceSelect.show();
});
