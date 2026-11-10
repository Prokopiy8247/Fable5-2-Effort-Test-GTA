# Characters — the shared modular humanoid

One rigged, modular body is used by the player and by every human NPC.

| What | Where |
|---|---|
| Blender builder (reproducible) | `tools/blender/assets/characters.py` (asset root `humanoid`, slot `characters/0`, collections `Characters` / `NPCs`) |
| Exported model | `res://gta/generated/models/characters/humanoid.glb` |
| Wrapper scene | `res://gta/scenes/characters/humanoid.tscn` (root `Node3D` + `character_visual.gd`) |
| Visual code | `res://gta/code/characters/character_visual.gd` (`class_name CharacterVisual`) |
| Wardrobe / barber data | `res://gta/resources/registries/appearance_registry.gd` (Registry kinds `clothing`, `hair`) |
| Test | `res://gta/tests/chr_lineup.gd` |

`humanoid_animator.gd` and `ragdoll.gd` in the same folder belong to the PLAYER module.

---------------------------------------------------------------------------------------------------

## 1. Skeleton (frozen contract — bones are never renamed)

T-pose rest, 1.80 m tall, feet on the ground at the origin, facing **+Y in Blender = −Z in Godot**.
`_L` is the character's left (−X). Every bone points along its local +Y; arms lie on ±X with the
palms down. Shoulder bones are short clavicles. Armature object name: `Armature`.

| # | Bone | Parent | Head (Godot x, y, z) | Points to |
|---|---|---|---|---|
| 0 | Root | – | 0, 0, 0 | up |
| 1 | Hips | Root | 0, 0.94, 0 | up |
| 2 | Spine | Hips | 0, 1.06, 0 | up |
| 3 | Chest | Spine | 0, 1.22, 0 | up |
| 4 | Neck | Chest | 0, 1.455, 0 | up |
| 5 | Head | Neck | 0, 1.53, 0 | up (tip 1.80) |
| 6 / 10 | Shoulder_L / _R | Chest | ∓0.025, 1.405, 0 | outwards |
| 7 / 11 | UpperArm_L / _R | Shoulder | ∓0.185, 1.405, 0 | outwards |
| 8 / 12 | LowerArm_L / _R | UpperArm | ∓0.45, 1.405, 0 | outwards |
| 9 / 13 | Hand_L / _R | LowerArm | ∓0.69, 1.405, 0 | outwards (0.10 long) |
| 14 / 17 | UpperLeg_L / _R | Hips | ∓0.10, 0.92, 0 | down |
| 15 / 18 | LowerLeg_L / _R | UpperLeg | ∓0.10, 0.50, 0 | down |
| 16 / 19 | Foot_L / _R | LowerLeg | ∓0.10, 0.09, 0 | forward and down to the toe |

Bone roll: the local Z axis of every bone points to the character's back (Blender −Y, Godot +Z),
feet: local Z points down. Animate in model space over the rest pose (as `HumanoidAnimator` does)
and roll never matters. `CharacterVisual.pose_bone_model(bone, basis)` does exactly that for
hand-made poses.

Imported node tree of the GLB: `humanoid2 (Node3D) → humanoid (Node3D) → Armature (Node3D) →
Skeleton3D → 64 MeshInstance3D parts`, plus an `AnimationPlayer` with the optional clips.
All transforms are identity.

---------------------------------------------------------------------------------------------------

## 2. Parts

Object name = `<Slot>_<Id>[_M|_F|_Hat]`. Parts are **replacement** meshes, never layered shells: the
visible torso + arms *is* the top, the legs *are* the bottom, a full outfit *is* torso + arms + legs.
Limb segments are rigid "ball joint" solids (the child segment starts with a dome centred on the
joint), so elbows, knees, shoulders and hips stay closed at any angle; spine, neck, skirt, apron
and long hair use smooth weights. All 64 parts share one Skin.

| Slot | Ids (tris) | Notes |
|---|---|---|
| Head | `Head_M` (376), `Head_F` (412) | head + neck + ears, eyes, brows, nose, mouth |
| Hands | `Hands` (280) | mitten hands with thumbs, slightly curled; recoloured for gloves |
| Hair | `Short` 212, `Buzz` 188, `Long` 260, `Ponytail` 278, `Curly` 178, `Slick` 212 (+ `bald` = no part) | every style has a `_Hat` variant (only the hair below the hat rim) that is used automatically under a hat |
| Beard | `Full` 216, `Goatee` 116, `Mustache` 66 | |
| Top | `Tee` 600, `Shirt` 688, `Hoodie` 736, `Jacket` 844, `Tank` 460, `Suit` 804, `Vest` 840 | each as `_M` and `_F` |
| Bottom | `Jeans` 456, `Shorts` 592, `Cargo` 548, `Slacks` 444 (`_M`, `_F`), `Skirt_F` 592 | skirt exists for the F body only (M falls back to it) |
| Shoes | `Sneakers` 392, `Boots` 424, `Dress` 344 | include the sock / boot shaft |
| Hat | `Cap` 200, `Beanie` 244, `Brim` 204, `Bandana` 268; uniform: `Police` 216, `Helmet` 324, `FireHelmet` 296 | |
| Glasses | `Shades` 84, `Round` 132; uniform: `Goggles` 156 | |
| Outfit | `Police` 1428, `Tactical` 1508, `Medic` 1416, `Firefighter` 1484, `Staff` 1424 (`_M`, `_F`) | replaces top + bottom |

Outfits: **Police** = uniform shirt with pockets, name plate, badge, epaulettes, radio, trousers
with a gold stripe, duty belt with pouches, baton and holster (+ `Hat_Police`). **Tactical** =
black fatigues, plate carrier with magazine pouches and "HBPD-style" blank white panels, shoulder
and elbow pads, knee pads, thigh holster (+ `Hat_Helmet`, `Glasses_Goggles`). **Medic** = teal
shirt with white trim, original emblem (white octagon, coral diamond), stethoscope, belt bag.
**Firefighter** = khaki turnout coat and trousers with hazard-yellow / steel bands, knee pads
(+ `Hat_FireHelmet`). **Staff** = shirt + trousers + apron (apron = `M_Top_Accent`).
Gang accents: `Hat_Bandana`, `Top_Vest` (back emblem in the accent colour).

A dressed character is 2.5–3.1 k triangles (player default 2560, police 2824, tactical 3068);
the whole GLB (all 64 parts) is 35.9 k.

### Materials

Contract materials that the game recolours per character (surface override materials, cached and
shared between all characters with the same colour):

`M_Skin`, `M_Hair` (hair, beard, brows), `M_Top`, `M_Top_Accent` (trim, collar, inner shirt, apron,
skirt waistband), `M_Bottom`, `M_Shoes`, `M_Hat`, `M_Eyes`, `M_Mouth`.

Fixed palette materials: `P_White` (eye whites, buttons), `P_Black`, `P_Charcoal`, `P_Chrome`,
`P_Steel`, `P_Leather`, `P_BadgeGold`, `P_Trim`, `P_ShoeWhite`, `P_Coral`, `P_Terracotta`,
`P_WindowDark`, `P_Mustard`, `P_GunMetal`, uniforms: `P_PoliceBlue`, `P_UniformNavy`,
`P_TacticalBlack`, `P_PoliceWhite`, `P_Teal`, `P_SafetyOrange`, `P_Khaki`, `P_HazardYellow`,
`P_FireRed`.

---------------------------------------------------------------------------------------------------

## 3. `CharacterVisual`

```gdscript
var v := load("res://gta/scenes/characters/humanoid.tscn").instantiate()
add_child(v)
v.randomize_appearance("civilian_f", my_seed)      # or v.apply_appearance({...})
animator.setup(v.get_skeleton())
weapon.reparent(v.get_bone_attachment("Hand_R"))
```

Scene tree of a live character: `<visual> / Armature (Node3D) / Skeleton3D / <worn parts>`.
The GLB is instantiated **once** into a static part library; each character gets its own 20-bone
`Skeleton3D` and a `MeshInstance3D` only for the 5–8 parts it wears (about 15 surfaces). Parts that
are not worn do not exist for that character.

| Method | |
|---|---|
| `get_skeleton() -> Skeleton3D` | available immediately after `add_child` |
| `apply_appearance(a: Dictionary)` | whole look; missing keys = defaults |
| `update_appearance(partial: Dictionary)` | change some keys, keep the rest (wardrobe / barber) |
| `get_appearance() -> Dictionary` | JSON-friendly, colours as `"#rrggbb"` (safe to put in a save file) |
| `randomize_appearance(archetype: String, seed: int)` | deterministic per archetype + seed |
| `static make_appearance(archetype, seed) -> Dictionary` | same, without a node |
| `static resolve_archetype(id) -> String` | maps foreign ids (`swat`, `police_officer`, `shopkeeper`, `gang_b`, `taxi_driver` …) |
| `get_bone_attachment(bone) -> Node3D` | cached `BoneAttachment3D` |
| `set_lod(level)` | 0 full; 1 glasses / beard hidden, only big parts cast shadows; 2 no shadows |
| `get_part_options(include_uniform_parts := false) -> Dictionary` | slot → ids, plus colour palettes |
| `set_head_visible(on)` | first-person camera: head parts become shadow-only |
| `get_grip_transform(bone := "Hand_R")` | local transform for an item held in that hand |
| `set_static_pose("relaxed" / "tpose")`, `pose_bone_model(bone, basis)` | mannequins, previews, tests |
| `get_active_parts()`, `get_part_node(name)` | debugging / tests |
| `static get_clip_names()`, `get_animation_player()` | optional Blender clips (section 5) |
| signal `appearance_changed(appearance)` | |

Exported properties: `appearance` (applied in `_ready` when not empty) and `default_archetype`
(`"player_default"`; used at the end of the first frame if nobody dressed the character — spawners
that call `randomize_appearance()` right after `add_child()` never pay for a default look).

### Appearance dictionary

| Key | Values |
|---|---|
| `body` | `"m"`, `"f"` |
| `skin`, `hair_color`, `top_color`, `top_accent_color`, `bottom_color`, `shoes_color`, `hat_color`, `eye_color` | `"#rrggbb"` or `Color` (`top_accent_color` `""` = automatic) |
| `hair` | `short, buzz, long, ponytail, curly, slick, bald` |
| `beard` | `"", full, goatee, mustache` |
| `top` | `tee, shirt, hoodie, jacket, tank, suit, vest` |
| `bottom` | `jeans, shorts, cargo, slacks, skirt` |
| `shoes` | `sneakers, boots, dress` |
| `hat` | `"", cap, beanie, brim, bandana` (+ `police, helmet, firehelmet`) |
| `glasses` | `"", shades, round` (+ `goggles`) |
| `outfit` | `"", police, tactical, medic, firefighter, staff` — replaces top + bottom and supplies default hat / shoes / gloves unless those keys are passed explicitly |
| `gloves` | `""` = bare hands, else a glove colour |

Examples:

```gdscript
# the default player
{"body": "m", "skin": "#dda77b", "hair": "short", "hair_color": "#3a2a1e", "top": "jacket",
 "top_color": "#22a7a0", "top_accent_color": "#f5f3ee", "bottom": "jeans", "bottom_color": "#27405f",
 "shoes": "sneakers", "shoes_color": "#e9e7e1"}
# an officer without her cap, wearing shades
{"body": "f", "outfit": "police", "hat": "", "glasses": "shades", "hair": "ponytail"}
# beach goer
{"body": "f", "top": "tank", "top_color": "#ee7e64", "bottom": "skirt", "bottom_color": "#efede6",
 "hat": "brim", "hat_color": "#bfa77a", "glasses": "shades"}
```

Archetypes (`CharacterVisual.ARCHETYPES`): `player_default, civilian_m, civilian_f, police,
tactical, medic, firefighter, staff, gang` (pass `gang_b` for the second gang colour), `business`,
`beach`. Palettes: `SKIN_TONES` (7), `HAIR_COLORS` (8) + `HAIR_COLORS_FUN` (4), `TOP_COLORS` (18),
`BOTTOM_COLORS` (10), `SHOE_COLORS` (8), `HAT_COLORS` (10), `SUIT_COLORS`, `EYE_COLORS`.

### Registry

`appearance_registry.gd` registers 23 `clothing` and 11 `hair` definitions (Dictionaries):
`id, kind, slot, part, display_name, price, default_color, color_key, colors, body, tags`.
A shop applies an item with
`visual.update_appearance({def.slot: def.part, def.color_key: chosen_colour})`.

---------------------------------------------------------------------------------------------------

## 4. Rebuilding and adding parts (Blender)

```python
import sys, importlib
P = r"G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode\tools\blender"
for p in (P, P + r"\assets"):
    if p not in sys.path: sys.path.append(p)
import gta_bl as G; importlib.reload(G); G.assert_master()
import characters as C; importlib.reload(C)
C.build_all()                 # armature (only if missing) + all 64 parts
C.build(["Top_Tee_M"])        # or just some parts / C.build(prefix="Hat_")
C.build_clips()               # optional loops (section 5)
C.final_previews()            # QA contact sheets
C.export()                    # -> characters/humanoid.glb (with the clips when they exist)
G.save()
```

To add a part:

1. Add a branch to the matching builder (`build_top`, `build_bottom`, `build_hat`, `build_hair`,
   `build_glasses`, `build_beard`, `build_shoes`, `build_outfit`) and its id to the tuple next to
   `part_builders()` (`TOPS`, `HATS` …). Build geometry with the `Part` helper (`loft`, `tube`,
   `box`, `cyl`, `path_tube`, `arc_sweep`, `strip_x` / `strip_a` / `ring_band` on a garment) and
   give every piece a bone (rigid) or a weight function (`w_torso`, `w_spine`, `w_skirt` …).
   Use `M_*` names for anything that should be recoloured and `P_<PaletteKey>` otherwise.
2. `C.build(["<Slot>_<Id>..."])`, then `C.look_preview("name", [list of part names], pose="walk")`
   and look at the PNG (also in the `seated` and `aim` poses), `G.validate("humanoid")`.
3. `C.export()`, `G.save()`. `CharacterVisual` discovers parts by name, so the new id is usable
   immediately: `{"top": "<id>"}`. Add a row to `appearance_registry.gd` if shops should sell it,
   and to `UNIFORM_ONLY` in `character_visual.gd` if it must stay out of the wardrobe lists.

Naming rules the game relies on: `<Slot>_<Id>` with an optional third token `M` / `F` (body cut) or
`Hat` (hair under a hat). Slot names: `Head, Hands, Hair, Beard, Top, Bottom, Shoes, Hat, Glasses,
Outfit`.

---------------------------------------------------------------------------------------------------

## 5. Optional Blender clips

`C.build_clips()` keys three in-place loops with `pose_bone.keyframe_insert` (one key per frame on
every bone + the hips height): **Idle** (3.0 s), **Walk** (1.0 s), **Run** (0.67 s). The poses come
from `C.clip_pose()`; a small ground solver keeps the supporting foot planted (heel strike → flat →
toe-off). The actions are named `Humanoid_<Clip>` and stashed in muted NLA tracks of the armature,
so they never disturb the rest pose. `C.export()` writes them into the GLB.

In Godot they are extras — the game's main animation is the procedural `HumanoidAnimator`:

```gdscript
CharacterVisual.get_clip_names()            # ["Idle", "Run", "Walk"]
var ap := visual.get_animation_player()     # created on demand, clips loop
ap.play("Walk")
```

Do not run an `AnimationPlayer` clip and a `HumanoidAnimator` on the same visual at the same time.

---------------------------------------------------------------------------------------------------

## 6. QA

- Blender sheets (`qa/blender_previews/`): `chr_final_looks_a/b/c.png` (player, civilians, police,
  tactical, medic, firefighter, staff, gang, suit), `chr_final_pose_walk/seated/aim/crouch.png`
  (deformation at shoulders, elbows, hips, knees), `chr_clip_walk/run/idle.png`, plus the working
  sheets `chr_heads_*`, `chr_tops_*`, `chr_out_*`, `chr_mix_*`, `chr_pose_*`.
- Godot test:
  `tools\godot.ps1 -Mode headless -Frames 600 -UserArgs '--test=chr_lineup','--no_player','--disable=world,traffic,peds,police'`
  (structure, API, materials, registry and clip checks) and the same with `-Mode window -Frames 260`
  for `qa/screenshots/chr_lineup.png`, `_close`, `_close2`, `_back`, `_poses`, `_clips`.
- GLB structure:
  `tools\godot.ps1 -Mode script -Script res://gta/code/editor/print_scene_tree.gd -UserArgs '--scene=res://gta/generated/models/characters/humanoid.glb','--bones','--depth=6'`

Known limits: mitten hands (no finger bones); no facial animation; one body height (1.80 m) for both
body types; the M body wearing `skirt` uses the F cut; clips are simple in-place loops.
