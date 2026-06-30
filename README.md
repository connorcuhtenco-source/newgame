# SOULRIFT

A standalone web prototype for a first-person anime action RPG (Type Soul / Peroxide inspired).

Rendering uses [Three.js](https://threejs.org/) (loaded as an ES module via import map). All
gameplay logic is plain ES modules, with a single stylesheet.

## Run it

It's a static site — serve the folder and open `index.html`:

```bash
python3 -m http.server 8000
# then visit http://localhost:8000
```

(A server is needed because the game uses ES modules and an import map.)

## Controls

- Click to enter (pointer lock)
- `WASD` move · `Shift` sprint · `Q` + direction dash
- `LMB` light combo · `RMB` heavy · `F` block/parry · `G` reiatsu

## Structure

All files live flat at the repository root next to `index.html`:

```
index.html              # entry: race-select landing + game layer + HUD
soulrift.css            # the single stylesheet
main.js                 # bootstrap (the only <script> referenced)
EventBus.js, Input.js, AudioManager.js, VFX.js, StateMachine.js, Game.js   # core
Races.js, Progression.js, Settings.js                                      # config
PlayerController.js, CombatSystem.js, Viewmodel.js                         # player
ProgressionManager.js, SoulReaperPath.js, QuincyPath.js, HollowPath.js    # progression
World.js, Enemy.js                                                         # world
RaceSelect.js, HUD.js                                                      # ui
```
