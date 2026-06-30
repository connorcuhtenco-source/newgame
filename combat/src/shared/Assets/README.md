# Combat / Visual Assets

This directory is mapped by Rojo to **`ReplicatedStorage/Combat/Assets`**. Drop
your authored, high-fidelity content here (as `.rbxm`/`.rbxmx` model files, or
author directly in Studio under this folder) and the runtime will pick it up
automatically. Files in this folder that Rojo does not recognize (like this
README) are ignored — the folder itself still becomes a `Folder` instance.

```
ReplicatedStorage/Combat/Assets/
  Viewmodel            -- rigged first-person arms + welded weapon Model
                          (weapon needs DmgPoint + optional TrailTop/TrailBottom
                           attachments). Used by ViewmodelController if present,
                           otherwise a placeholder katana is generated.
  Weapons/             -- per-Zanpakuto / Quincy-bow Models (high-poly MeshParts)
  Enemies/
    Hollow             -- bone-armor rig (name an eye part "*eye*" for the glow)
    Quincy
    SoulReaper
  Maps/
    SoulSocietyMap     -- modular Japanese architecture; tag lanterns "Lantern"
    HuecoMundoMap      -- white desert dressing (or use HuecoMundoSky.buildDesert)
```

See `combat/VISUALS.md` for the in-engine material/mesh parameters to apply to
each of these, and how the scripts consume them.
