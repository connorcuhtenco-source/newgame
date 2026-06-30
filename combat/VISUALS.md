# SOULRIFT — Visual Overhaul (Models, Maps, Viewmodels, Combat Fluidity)

This layer sits on top of the combat system and upgrades **how everything looks
and feels**: spring-driven first-person hand-sway, an emissive slash trail,
arc-based swing animation with camera tilt, instant hit feedback, stylized
maps/lighting, and Hollow enemy VFX.

Code-able systems are shipped as modules; the parts that are genuinely *art*
(high-poly meshes, PBR textures, rigs, authored animations) can't be generated in
script — for those, this doc gives the exact mesh-handling / material parameters
to apply in-engine.

> Everything new lives under the same Rojo project (`combat/`). Shared visual
> modules are in `ReplicatedStorage/Combat` (incl. `Environment/`), client
> presentation in `StarterPlayerScripts/CombatClient`.

---

## What's wired up automatically

Requiring the existing client/server already activates:

- **Hand-sway** — `ViewmodelSway` (spring-mass-damper) is created by
  `ViewmodelController` and applied every frame.
- **Cubic-Bézier swings** — `BezierSwing` drives the anticipation/active/recovery
  curve with per-strike easing + elastic settle, and couples camera **roll + FOV**
  during the active phase.
- **Slash trail** — `MotionTrail` streaks off the blade during each strike.
- **Impact VFX** — clashes/parries trigger `ImpactVfx`: screen-flash vignette,
  stretched billboard sparks, and an expanding shockwave ring.
- **Reiatsu aura (hold G)** — `ReiatsuAura`: chromatic-aberration vignette +
  weapon aura particles.
- **Hit reactions** — on a server-validated hit, every client runs
  `EnemyVfx.hitReaction`: a **material-swap** 0.05s white self-illum flash
  (smooth transition back) + spark + flinch.
- **Hollow dressing** — any `Model` with the CollectionService tag `Hollow` is
  auto-given glowing eyes + shadow aura.

Environment passes are **opt-in** (they change global Lighting), so call them
from your own map loader — see below.

---

## 1. First-Person Viewmodel Spring System (hand-sway)

`src/client/ViewmodelSway.luau`. Two damped springs (shared `Spring`) produce a
CFrame offset applied as `camera.CFrame * REST * sway * swingArc`:

- **Look-lag**: kicked by the camera's angular velocity, so the weapon trails
  behind fast turns then springs back, with a little roll *into* the turn.
- **Walk bob** (figure-8, scaled by speed) + **idle breathing**.
- Output is clamped (`MaxLook`, `MaxPos`) so the weapon never leaves frame.

The bootstrap feeds it the player's planar speed each frame
(`viewmodel:setSpeed01(...)`). Tune everything in `VisualConfig.Sway`.

## 2. Motion Trail VFX (slash ribbon)

`src/client/MotionTrail.luau`. Wraps a Roblox `Trail` stretched between
`TrailBottom`→`TrailTop` attachments along the blade edge (auto-created from the
blade bounds if absent). `:slash(duration)` enables it for the strike then fades
it over `Trail.Lifetime`. Emissive blue-white by default (`VisualConfig.Trail`);
set `Trail.Texture` to a streak image for a textured ribbon.

## 3. Swing mechanics (arc + camera tilt)

`src/client/SwingArc.luau` is a pure function `evaluate(combo, t) -> {offset,
cameraRoll, cameraPitch}` with three eased phases:

| Phase | Easing | Feel |
| --- | --- | --- |
| Anticipation | ease-out | weapon pulls back/up off-center |
| Strike | ease-in | explosive whip across screen |
| Recovery | ease-in-out | smooth settle back to idle |

Slash handedness alternates per combo hit; the **finisher is a centered
overhead**. `cameraRoll` peaks mid-strike and tilts the view into the cut (e.g.
right→left cut rolls the camera ~2° right); the finisher adds a downward pitch
kick. Durations are pulled from `CombatConfig.Combo.Frames` so visuals and the
hitbox stay in lock-step. Tune in `VisualConfig.Swing`.

## 4. Hit reactions & enemy VFX

- `src/client/HitFlash.luau` — non-destructive solid-white `Highlight` flash for
  `VisualConfig.HitFlash.Duration` (0.05s).
- `src/client/EnemyVfx.luau` —
  - `setupHollow(model)`: neon red eyes + `PointLight` + ember trail, and a dark
    rising torso aura.
  - `hitReaction(model, pos)`: spark burst + white flash + flinch (authored
    `VisualConfig.Hollow.FlinchAnim` if set, otherwise a brief procedural
    stagger lean).

## 5. Environment passes (opt-in)

All under `ReplicatedStorage/Combat/Environment`. `ReishiDrift` and the
atmosphere passes touch `RenderStepped`, so **call them from a client script**.

```lua
local Env = game:GetService("ReplicatedStorage").Combat.Environment

-- Soul Society: stylized toon day, flickering paper lanterns, drifting Reishi.
-- Tag lantern parts with the CollectionService tag "Lantern" (or name them
-- "Lantern") so they get dynamic flickering point lights.
require(Env.SoulSocietyAtmosphere).apply(workspace:WaitForChild("SoulSocietyMap"))

-- Hueco Mundo: perpetual crescent moon, stark white desert, hard silhouettes.
local Hueco = require(Env.HuecoMundoSky)
Hueco.apply()
Hueco.buildDesert(1024)   -- optional flat white terrain
```

`ToonLighting.apply(daytime)` sets the high-contrast base (hard shadows + a
contrast `ColorCorrectionEffect`). `ToonLighting.addOutline(model)` adds a black
silhouette outline (a cheap cel stand-in). **Set `Lighting.Technology = Future`
in Studio** for the crispest shadows — it isn't reliably settable from script.

> **Honest limitation:** Roblox has no custom pixel shaders, so true cel-shading
> isn't possible. This is a faithful *approximation* via lighting, contrast
> grading, and `Highlight` outlines.

---

## Mesh-handling & material parameters (for authored art)

Author the meshes/textures in Blender (or similar) and import as `MeshPart`s with
`SurfaceAppearance` (PBR). Recommended in-engine settings — most are encoded in
`VisualConfig.Materials`:

### Zanpakuto (katana)
- **Budget:** ~3–6k tris for the whole weapon; the blade can be very low-poly.
- **Blade:** `Material = Metal`, `Color ≈ (214,224,235)`, `Reflectance ≈ 0.25`,
  or a `SurfaceAppearance` with a steel albedo + metalness=1 / low roughness.
- **Hilt (Tsuka-ito wrap):** `Material = Fabric`, dark color; bake the diamond
  wrap into the normal/albedo maps.
- **Guard (Tsuba):** `Material = Metal`, slightly rougher, `Reflectance ≈ 0.15`.
- **Scale:** keep the viewmodel weapon ~0.7–0.9 of world scale so it reads well
  at the first-person FOV; place `DmgPoint` attachments along the cutting edge.

### Quincy bow
- `Material = Neon` (or `ForceField`), `Transparency ≈ 0.35`, bright cyan;
  add a `Trail`/`Beam` for the energy string. Intense glow comes from Neon +
  high Lighting `Brightness`/`EnvironmentSpecularScale`.

### First-person hands
- Fully rigged stylized hands (soul-reaper sleeve / fingerless gloves) as a
  rigged `Model`/`R15`-style arms. Place it at
  `ReplicatedStorage/Combat/Assets/Viewmodel` with the weapon welded to the right
  hand and `DmgPoint` (+ optional `TrailTop`/`TrailBottom`) attachments on the
  blade — `ViewmodelController` will use it instead of the placeholder and load
  the animations from `CombatConfig.Animations`.

### Hollow enemies
- Segmented bone-armor plates as separate `MeshPart`s (`Material = Marble`/`Slate`
  bone-white). Name an eye part with "eye" (any case) so `EnemyVfx` finds it; the
  glow/aura/embers are added in script. Provide a flinch animation id in
  `VisualConfig.Hollow.FlinchAnim`.

### Maps
- **Soul Society:** modular layered Japanese buildings (weathered wood normal
  maps, curved roof-tile meshes). Tag lanterns "Lantern".
- **Hueco Mundo:** flat white sand (use `HuecoMundoSky.buildDesert` or a custom
  terrain) + your own white-void skybox ids swapped into `HuecoMundoSky`.

All visual tuning lives in `src/shared/VisualConfig.luau`.

---

# Output requirements (advanced pass)

## (1) Viewmodel Spring-Sway Controller — the math

`src/client/ViewmodelSway.luau`. Each axis is an independent **spring-mass-damper**
(unit mass) integrated with semi-implicit Euler (shared `Spring.luau`):

```
a = (-k * (x - target)) - (c * v)     -- F = -kx - cv, m = 1
v = v + a * dt                        -- update velocity first (semi-implicit)
x = x + v * dt                        -- then position
```

- `k` = stiffness, `c` = damping. Pick `c ≈ 2*sqrt(k)` (critical) for snappy,
  non-oscillatory settling — anything less wobbles, anything more feels mushy.
- **Sway** injects velocity each frame proportional to the camera's angular
  velocity: `Δv_rot ∝ -(dPitch,dYaw)/dt` (lag opposite the turn) plus a roll term
  `∝ +dYaw` (bank into the turn). Yaw deltas are wrapped to `[-π,π]` so a wrap
  never spikes the spring. Output is clamped to `MaxLook`/`MaxPos` so the weapon
  can't leave frame.
- **Bob** is a true figure-8 (Lissajous 1:2): `x = sin(φ)`, `y = sin(2φ)`, with
  `φ` advancing at `BobFrequency * speed01`. Idle adds a slow breathing sine.

Result each frame: `CFrame.new(pos + bob) * CFrame.Angles(rot.X, rot.Y, rot.Z)`,
multiplied into `camera.CFrame * REST * sway * swing`.

## (2) Cubic-Bézier Weapon Swing System — the logic

`src/client/BezierSwing.luau`. Phase split **15% / 60% / 25%** (anticipation /
active / recovery). Each phase remaps its local time `t∈[0,1]` through a CSS-style
**cubic-bezier(x1,y1,x2,y2)** timing function (per-strike handles in
`VisualConfig.Bezier.Curves`, so all four hits differ), then interpolates between
key poses:

```
rest --anticipation(ease-out)--> cocked-back --active(slow→snap)--> follow-through
     --recovery(ease + elastic settle)--> rest
```

- The bezier solve is Newton-Raphson: solve `Bx(u)=t` for the curve parameter `u`,
  then evaluate `By(u)` for the eased value.
- Recovery blends the eased return with `easeOutElastic` for a subtle bounce
  settle (`ElasticAmplitude` / `ElasticPeriod`).
- **Camera-impact coupling**: during Active, `cameraRoll`, `cameraPitch` (finisher)
  and `fovDelta` follow a `sin(πt)` envelope peaking mid-strike. The controller
  applies the FOV punch additively and removes it next frame so it composes with
  sprint/zoom FOV.
- Handedness alternates per combo; hit 4 is a centered overhead.

## (3) Asset directory structure

Rojo maps `combat/src` into the DataModel (`combat/default.project.json`):

```
combat/src/shared      -> ReplicatedStorage/Combat            (modules + config)
combat/src/shared/Assets -> ReplicatedStorage/Combat/Assets   (your art; see below)
combat/src/shared/Environment -> ReplicatedStorage/Combat/Environment
combat/src/client      -> StarterPlayerScripts/CombatClient
combat/src/server      -> ServerScriptService/CombatServer
```

Author content goes under **`ReplicatedStorage/Combat/Assets`** (commit `.rbxm`
files into `combat/src/shared/Assets/…` or build in Studio under that folder):

```
Assets/
  Viewmodel              rigged FP arms + welded weapon (DmgPoint + TrailTop/Bottom)
  Weapons/{Zanpakuto,QuincyBow,...}
  Enemies/{Hollow,Quincy,SoulReaper}   (name an eye part "*eye*")
  Maps/{SoulSocietyMap,HuecoMundoMap}  (tag lanterns "Lantern")
```

Import meshes as `MeshPart`s with a `SurfaceAppearance` (ColorMap / MetalnessMap /
NormalMap / RoughnessMap) for PBR; set the per-material engine properties from
`VisualConfig.Materials` (steel blade, Tsuka wrap, Tsuba, Quincy neon bow). If
`Assets/Viewmodel` exists, `ViewmodelController` clones it and loads the swing
animations from `CombatConfig.Animations`; otherwise it generates the placeholder
katana so everything still runs.
