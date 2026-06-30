# SOULRIFT — Advanced First-Person Melee & Combat Clashing (Roblox / Luau)

A modular, server-authoritative first-person melee system: a 4-hit M1 combo with
raycast hitboxes, blocking + perfect parry, and a player-vs-player **clash**
mechanic, complete with spark VFX, metallic SFX and spring-driven camera shake.

> Built for Roblox (Type Soul / Peroxide style). Sync it into Studio with
> [Rojo](https://rojo.space): `rojo serve` against `combat/default.project.json`.
>
> **Visual layer** (viewmodel hand-sway, slash trail, arc swings + camera tilt,
> hit reactions, stylized maps/lighting, Hollow VFX): see [`VISUALS.md`](VISUALS.md).

## Where everything lands in the DataModel

```
ReplicatedStorage/Combat            (src/shared)   -- shared, required by both sides
  CombatConfig    -- all tuning: frame timings, damage, ranges, parry window…
  Spring          -- damped spring (camera shake)
  Remotes         -- CombatAction / CombatEffect / CombatState RemoteEvents
  WeaponHitbox    -- RaycastHitbox-style swept blade detection
  Types           -- shared Luau type defs for the wire protocol

StarterPlayerScripts/CombatClient   (src/client)   -- feel + detection
  init.client         -- bootstrap / wiring
  InputController      -- raw input -> verbs (M1, F; mouse/touch/gamepad)
  CombatStateMachine   -- combo + windup/active/recovery + block + lockouts
  ViewmodelController  -- first-person arms/katana, swing arc, block pose
  CameraShaker         -- spring-based impact shake
  EffectsController     -- spark bursts + SFX

ServerScriptService/CombatServer    (src/server)   -- authority
  init.server          -- intent dispatch + outcome resolution
  PlayerCombatState    -- trusted per-player state (swings, block, stun)
  HitValidator         -- range / facing / timing / rate validation
  ParryResolver        -- parry vs. block vs. none
  ClashResolver        -- simultaneous-swing clash detection
```

## 1. Client input → animation state machine (the starting point)

Input is intentionally dumb. `InputController` maps `MouseButton1`/`R2` to an
**attack** verb and `F`/`L2` to a **block held** signal, and forwards them. It
makes no decisions, so the state machine stays the single source of truth:

```
M1 / R2  ──► onAttack()       ──► CombatStateMachine:requestAttack()
F  / L2  ──► onBlockChanged() ──► CombatStateMachine:setBlockHeld()
```

`CombatStateMachine` is a pure finite-state machine (no Instances, no
networking) ticked every `RenderStepped`. Each swing flows through three phases
so attacks have readable wind-up, a tight active window, and committed recovery:

```
            requestAttack()
 Idle ─────────────────────────► Windup ──(0.12s)──► Active ──(0.10s)──► Recovery ──► Idle
   ▲  setBlockHeld(true)                              (hitbox live)        │  (0.20s)
   │                                                                       │ buffered M1?
 Blocking ◄── setBlockHeld ──┐                                            └──► next combo hit
   │                          └──────────────────────────────────────────────┘
 Stunned / Recoil  ◄── server: applyStun() / applyRecoil()  (input locked out)
```

- **Combo**: each `requestAttack` advances `combo` 1→4; it resets after
  `Combo.ResetWindow` of idle or once the finisher (#4) lands.
- **Buffering**: pressing M1 during *Recovery* is buffered and chains the next
  hit the instant recovery ends, so the combo feels fluid.
- **Commitment**: *Windup/Active* can't be block-cancelled; attacking from a
  block drops the guard.
- **Decoupling**: the machine only fires callbacks (`onSwingStart`,
  `onActiveStart/End`, `onBlockChanged`, `onLockChanged`). The bootstrap wires
  those to the viewmodel, the hitbox and the network — nothing else needs to
  know about timing.

## 2. Hitboxes (client detect, server validate)

On `onActiveStart` the bootstrap starts a `WeaponHitbox` built from the
viewmodel's blade `DmgPoint` attachments. Every frame it raycasts from each
point's previous to current position, so a fast swing leaves a continuous swept
segment (no tunnelling). A detected humanoid is **reported** to the server as a
claim — it never applies damage locally.

The server (`HitValidator`) independently confirms the claim: the attacker isn't
stunned, a matching swing is still live, the victim is alive and within
`Reach (+fudge)` and inside the facing cone, and swings aren't arriving faster
than `Server.MinSwingInterval`. Only then does resolution proceed.

## 3. Blocking & perfect parry

Holding `F` raises the guard (`Block.WalkSpeedMultiplier` slows you) and is sent
to the server. When a validated hit reaches a guarding victim, `ParryResolver`
checks how long ago the guard went up:

- `≤ Block.ParryWindow` (0.25s) → **Perfect Parry**: attacker stunned 1.5s,
  their swing cancelled, bright sparks + loud metallic clash at the impact.
- otherwise → **Standard block**: `Block.Mitigation` (80%) of damage removed.

## 4. The clash

`ClashResolver` fires when two opposing M1s go active within `Clash.TimeMargin`
(both clients send their swing at wind-up; the server compares accepted start
times). On a clash, **both** swings cancel, both fighters get a backward impulse
and a brief recoil lock-out, a massive spark emitter fires between them, and both
clients get a sharp `CameraShaker` kick.

**Resolution priority on a validated hit:** `clash → parry → block → damage`.

## Networking contract

| Remote | Direction | Purpose |
| --- | --- | --- |
| `CombatAction` | client → server | `Swing` / `Hit` / `BlockStart` / `BlockEnd` intents |
| `CombatState`  | server → 1 client | authoritative `Stun` / `Recoil` / `Knockback` / `Cancel` / `ParrySuccess` |
| `CombatEffect` | server → all | cosmetic `Hit` / `Block` / `Parry` / `Clash` broadcasts |

Knockback is applied on the *victim's own* client (it owns its character's
physics) for non-fighting NPCs the server applies it directly.

## Hooking up assets

The system runs out of the box with a generated placeholder katana (neon blade +
`DmgPoint` attachments) and procedural swing arcs. To use your own:

1. Put a rigged first-person model at `ReplicatedStorage/Combat/Assets/Viewmodel`
   whose weapon contains `DmgPoint` attachments along the blade.
2. Fill in the `rbxassetid://` placeholders in `CombatConfig.Animations` and
   `CombatConfig.Sounds`.

All tuning lives in `CombatConfig.luau`.
