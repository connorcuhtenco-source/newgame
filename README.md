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

```
index.html              # entry: race-select landing + game layer + HUD
css/soulrift.css        # the single stylesheet
js/
  main.js               # bootstrap (the only <script> referenced)
  core/                 # EventBus, Input, AudioManager, VFX, StateMachine, Game
  config/               # Races + Progression + Settings
  player/               # PlayerController, CombatSystem, Viewmodel
  progression/          # ProgressionManager + paths/{SoulReaper,Quincy,Hollow}
  world/                # World (arena) + Enemy (chase AI)
  ui/                   # RaceSelect (landing) + HUD
```
