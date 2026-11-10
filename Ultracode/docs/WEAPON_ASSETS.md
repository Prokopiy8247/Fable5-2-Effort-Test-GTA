# Weapon, projectile and pickup models (weapon artist)

All 26 assets are authored in Blender 5.2 through the `blender-gta-ultracode` MCP server by the
builder code in `tools/blender/assets/weapons*.py` (no external or generated assets, no image
textures). Art direction: "Sunlit Low-Poly" - flat-shaded facets, chamfered main parts, palette
materials only, detail as geometry.

## Files

| what | where |
|---|---|
| toolkit + registry | `tools/blender/assets/weapons.py` |
| builders | `weapons_melee.py`, `weapons_handguns.py`, `weapons_long.py`, `weapons_heavy.py`, `weapons_pickups.py` (same folder, loaded by `weapons.py`) |
| weapon / projectile GLBs | `res://gta/generated/models/weapons/<id>.glb` + `manifest.json` |
| pickup prop GLBs | `res://gta/generated/models/props/pickups/<id>.glb` + `manifest_pickups.json` |
| Blender contact sheets | `qa/blender_previews/wpn_<id>.png`, `wpn_<id>_att.png`, `wpn_group_long.png`, `wpn_group_small.png`, `wpn_group_pickups.png` |
| in-engine screenshots | `qa/screenshots/wpnart_*.png` |
| Godot checks | `gta/code/editor/wpn_check_models.gd`, `gta/tests/scenes/wpnart_showcase.tscn` |

Blender: collection `Weapons`, slot region `weapons` (weapons 0-17, pickups 24-31), one root Empty
per asset named like the id (tagged with the custom property `gta_author = "weapons"`).

## Node contract (as imported by Godot)

`FileRoot (Node3D) -> <id> (Node3D) -> parts`. Find parts with `find_child("Body", true, false)`.
Godot space: **-Z = barrel / pointing direction, +Y = up, +X = right, origin = right-hand grip**
(thrown items: origin at the body centre, upright; projectiles: origin at the centre, flying
along -Z; pickup props: origin at the bottom centre, front faces -Z).

| node | type | meaning |
|---|---|---|
| `Body` | mesh | the weapon without removable parts |
| `Mag` | mesh | removable magazine (origin inside the magazine, so it can be animated / dropped). Revolver and grenade launcher: the cylinder / drum. Rocket launcher: the loaded warhead - hide it after firing |
| `Att_Suppressor`, `Att_Scope`, `Att_Flashlight`, `Att_Grip`, `Att_ExtMag` | mesh | attachments authored in place. **Hide all of them by default.** While `Att_ExtMag` is shown, hide `Mag` (the extended magazine is a complete magazine; on the pump shotgun it is a tube extension and nothing has to be hidden) |
| `Muzzle` | Node3D | barrel tip (melee: tip of the blade / head; molotov: wick tip = flame point) |
| `Muzzle_Suppressed` | Node3D | muzzle point while `Att_Suppressor` is fitted |
| `Eject` | Node3D | ejection port on the right side (rocket launcher: rear back-blast point; revolver / grenade launcher: beside the cylinder) |
| `Grip_L` | Node3D | support-hand position |
| `Flashlight` | Node3D | lens centre of `Att_Flashlight` (spot-light origin, shines along -Z) |
| `Exhaust` | Node3D | tail of the projectiles `rocket`, `grenade_round` (trail origin) |

All markers keep the weapon's orientation (identity rotation), so `-basis.z` of `Muzzle` is the
firing direction and `basis.x` of `Eject` points to the right (shell ejection side).

Materials: `M_Weapon_Finish` (contract, tintable - receiver / slide / frame; default colour =
palette SteelDark so it reads against the dark furniture) plus shared palette materials
`P_GunMetal, P_GunMetalDark, P_GunPolymer, P_GunWood, P_GunTan, P_Brass, P_Steel, ...`.
To tint a weapon, duplicate the `M_Weapon_Finish` surface material of `Body` and change its albedo.

## Roster

| id | length (m) | tris (whole GLB) | Mag | attachments | notes |
|---|---|---|---|---|---|
| knife | 0.32 | 380 | - | - | combat knife, clip point, saw-back |
| bat | 0.83 | 700 | - | - | wooden bat, taped handle |
| crowbar | 0.60 | 384 | - | - | red octagonal bar, steel claw + chisel |
| pistol | 0.19 | 1248 | yes | Suppressor, Scope (reflex), Flashlight, ExtMag | polymer frame, tintable slide |
| heavy_pistol | 0.28 | 1228 | cylinder | Scope, Flashlight | slab-barrel revolver, wooden grip |
| smg | 0.61 | 1588 | yes | Suppressor, Scope, Flashlight, Grip, ExtMag | skeleton folding stock (extended) |
| pump_shotgun | 1.02 | 1320 | - | Suppressor, Scope, Flashlight, ExtMag (tube) | wooden furniture, shell saddle |
| auto_shotgun | 1.05 | 1776 | yes | Suppressor, Scope, Flashlight, Grip, ExtMag (drum) | box-fed |
| assault_rifle | 0.93 | 1664 | yes | Suppressor, Scope (prism optic), Flashlight, Grip, ExtMag | tan furniture, curved magazine |
| carbine | 0.82 | 1792 | yes | Suppressor, Scope (tube dot), Flashlight, Grip (angled), ExtMag | octagonal rail handguard, collapsible stock |
| marksman_rifle | 1.12 | 1788 | yes | Suppressor, Scope (long), Flashlight, Grip (bipod), ExtMag | wooden stock, long scope rail |
| sniper_rifle | 1.25 | 1776 | yes | Suppressor, Scope (long-range kit that wraps the built-in optic), ExtMag | bolt action, scope is part of Body, folded bipod |
| grenade | 0.13 tall | 464 | - | - | fragmentation grenade, pin + lever |
| molotov | 0.30 tall | 408 | - | - | bottle + cloth wick |
| rocket_launcher | 1.07 (+ warhead) | 1088 | warhead | - | shoulder tube, side optic, carry handle |
| grenade_launcher | 0.72 | 1352 | drum | Scope, Flashlight | six-shot revolving launcher |
| rocket | 0.58 | 364 | - | - | projectile (same warhead as the launcher's `Mag`) |
| grenade_round | 0.11 | 276 | - | - | projectile |

Pickup props (single mesh `Body`): `ammo_box` (568), `medkit` (340, emblem = red heart on a white
disc), `armor_vest` (548), `cash_stack` (240), `cash_bag` (448), `parachute_pack` (380),
`scuba_tank` (632), `weapon_crate` (796). Real-world sizes are in `manifest_pickups.json`
(e.g. `cash_stack` is only 0.17 m wide - scale it up in the pickup system if it should read from far).

The manifests carry, per asset: triangle count, size / AABB (Godot space), mesh list, attachment
list, `has_mag`, `tintable`, material names and marker positions (Godot space). They are plain
JSON files (read with `FileAccess`); add `*.json` to the export filters if the game reads them at
runtime in an exported build.

## Rebuild

Inside one `execute_blender_code` call (atomic, never relies on selection):

```python
import sys, importlib
P = r"G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode\tools\blender"
for p in (P, P + r"\assets"):
    if p not in sys.path: sys.path.append(p)
import gta_bl as G; importlib.reload(G)
import weapons as W; importlib.reload(W)
G.assert_master()
W.build("pistol"); W.shots("pistol"); W.export("pistol")     # one asset
# W.build_all(); W.export_all(); W.write_manifests(); G.save()  # everything
```

`W.export()` runs `G.validate`, rejects inside-out mesh islands, calls `G.export_glb` and then
strips Blender's numeric name suffixes inside the GLB (object names are global in the shared
.blend, so a second asset's `Body` is stored as `Body.001`; without the fix Godot would import
`Body_001`).

## Verification

```powershell
tools\godot.ps1 -Mode script -Script res://gta/code/editor/wpn_check_models.gd          # 26 GLBs vs manifests
tools\godot.ps1 -Mode script -Script res://gta/code/editor/print_scene_tree.gd -UserArgs '--scene=res://gta/generated/models/weapons/pistol.glb'
tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/wpnart_showcase.tscn -Frames 300   # screenshots
```
