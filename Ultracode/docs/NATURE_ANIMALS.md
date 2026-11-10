# Nature and wildlife assets (NATURE_ANIMALS)

Author: nature and wildlife artist (Blender MCP). Everything here is authored by project code in
Blender 5.2 - no external, downloaded or AI-generated assets, no image textures.

| what | where |
|---|---|
| builder module (reproducible pipeline) | `tools/blender/assets/nature_animals.py` |
| Blender collections / slot regions | `GTA_GODOT/Nature` (region `nature`, slots 0-37, tree LOD1s at 40-48), `GTA_GODOT/Animals` (region `animals`, slots 0-10) |
| nature exports + manifest | `res://gta/generated/models/nature/<id>.glb`, `manifest_nature.json` |
| animal exports + manifest | `res://gta/generated/models/animals/<id>.glb`, `manifest_animals.json` |
| Godot contract test + look-dev showcase | `gta/tests/na_showcase.gd`, `gta/tests/scenes/na_showcase.tscn` |
| Blender previews | `qa/blender_previews/nature_*.png`, `animal_*.png`, groups `nature_group_*.png`, `animals_group_*.png` |
| Godot screenshots | `qa/screenshots/na_trees.png`, `na_trees_lod1.png`, `na_shrubs_groundcover.png`, `na_rocks_cliffs.png`, `na_underwater.png`, `na_animals.png`, `na_animals_posed.png` |

Totals: 36 nature assets (12586 tris) + 9 tree LOD1 meshes (1554 tris), 11 animals (5790 tris).

## 1. Rebuilding / re-exporting

Inside one `execute_blender_code` call (atomic, see ARCHITECTURE.md 8.1):

```python
import sys, importlib
P = r"G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode\tools\blender"
for p in (P, P + r"\assets"):
    if p not in sys.path: sys.path.append(p)
import gta_bl as G; importlib.reload(G); G.assert_master()
import nature_animals as NA; importlib.reload(NA)
NA.build_all()                 # all 56 roots, < 1 s; every builder replaces its old version
NA.export_all()                # GLBs + both manifests
G.save()
# single assets:  NA.build_nature("palm_a"); NA.build_nature("palm_a", lod=1); NA.build_animal("deer")
#                 NA.export_all(nature_ids=["palm_a"], animal_ids=[])   (also rewrites the manifests)
```

**Always export through `NA.export_asset()` / `NA.export_all()`, never plain `G.export_glb()`.**
Blender object names must be unique per file, so parts are called `<id>_Mesh`, `<id>_Body`, ... in
the .blend; `NA.export_asset()` rewrites the node names inside the written GLB to the contract
names (`Mesh`, `Body`, `Head`, `Leg_FL`, ...).

QA helpers in the module: `NA.group_preview(names, out_name, ...)` (line-up next to a 1.8 m
reference box), `NA.closeup(...)` (detail render), plus `G.preview` / `G.validate`.

## 2. Nature

Imported structure: `FileRoot (Node3D) -> <id> (Node3D) -> Mesh (MeshInstance3D)`. Exactly one mesh
per asset, at the asset origin, several surfaces (one per palette colour).

- Origin on the ground at the base. Every asset continues a little **below** y = 0 (manifest
  `sink`, trees 0.3-0.5 m, cliffs 0.7-0.8 m) so it can stand on slopes without a gap: place the
  origin on the terrain height, do not lift it.
- All geometry is closed and outward facing (no single-sided leaf cards): correct with back-face
  culling, with shadows and with any replacement material. Verified: 669 mesh islands, none open,
  none inside-out.
- Flat shaded, palette materials only (`P_*`). Foliage = `P_Leaf`, `P_LeafLight`, `P_LeafDark`,
  `P_Palm` (ground cover also `P_Grass`, `P_GrassDark`, `P_Olive`); bark = `P_Trunk`,
  `P_TrunkLight` (the birch `tree_broadleaf_c` uses `P_Cream` with thin `P_HairBlack` bands;
  palm coconuts are `P_Trunk` / `P_WoodDark`). A wind-sway shader can therefore pick the leaf
  surfaces by material name (`mesh.surface_get_material(i).resource_name`). The manifest lists
  the material names of every asset.
- The light / mid / dark leaf and rock tones are assigned per facet from its orientation (a baked
  "sunlit" look), so crowns read as faceted volumes even in flat light.
- Cliff chunks: the cliff face looks toward **-Z in Godot** (Blender +Y); the back is a flat wall
  meant to be pushed into the hillside. Top faces are grass.

Manifest entry (`manifest_nature.json` -> `"nature": [...]`):

```json
{"id": "palm_a", "file": "palm_a.glb", "category": "tree", "size": [6.219, 10.65, 5.922],
 "collision_radius": 0.26, "collision": "trunk", "height": 10.25, "sink": 0.4,
 "aabb_min": [x, y, z], "aabb_max": [x, y, z], "tris": 856, "multimesh": false,
 "tags": ["palm", "coast", "beach"], "materials": ["P_TrunkLight", "..."],
 "visibility_end": 0.0, "lod1": "palm_a_lod1.glb", "lod1_tris": 264, "lod1_distance": 55.0}
```

- `size` = full AABB size [x, y, z] in Godot axes (y = height **including** the sunk part);
  `height` = top above the origin; `aabb_min/max` in Godot axes.
- `category`: `tree`, `shrub`, `groundcover`, `rock`, `cliff`, `log`, `underwater`.
- `collision`: `"trunk"` = vertical cylinder of `collision_radius` (trees, cactus), `"blob"` =
  sphere / short cylinder of `collision_radius` (rocks, hedge ball), `"box"` = AABB box (log,
  anchor, crate), `"trimesh"` = use the mesh (cliffs), `"none"` = walk-through (`collision_radius`
  0: bushes, ground cover, corals, shells).
- `multimesh: true` = designed for `MultiMeshInstance3D` scattering (60-390 tris).
- `visibility_end` = suggested `visibility_range_end` in metres (0 = never cull);
  `lod1` / `lod1_distance` = lower-detail twin of every tree and the suggested switch distance
  (same origin, same silhouette, 23-47 % of the tris; pines 63 %).
- `tags` say where an asset belongs (`beach`, `hill`, `park`, `street`, `reef`, `wreck`, ...).

| id | category | size x,y,z (m) | height | tris | LOD1 (tris) | collision | multimesh | preview |
|---|---|---|---|---|---|---|---|---|
| `palm_a` | tree | 6.22 x 10.65 x 5.92 | 10.25 | 856 | palm_a_lod1.glb (264) | trunk r=0.26 | - | `qa/blender_previews/nature_palm_a.png` |
| `palm_b` | tree | 4.85 x 8.19 x 4.91 | 7.79 | 810 | palm_b_lod1.glb (242) | trunk r=0.24 | - | `qa/blender_previews/nature_palm_b.png` |
| `tree_broadleaf_a` | tree | 6.05 x 8.54 x 5.64 | 8.13 | 558 | tree_broadleaf_a_lod1.glb (144) | trunk r=0.3 | - | `qa/blender_previews/nature_tree_broadleaf_a.png` |
| `tree_broadleaf_b` | tree | 10.85 x 11.67 x 9.44 | 11.17 | 788 | tree_broadleaf_b_lod1.glb (282) | trunk r=0.45 | - | `qa/blender_previews/nature_tree_broadleaf_b.png` |
| `tree_broadleaf_c` | tree | 3.59 x 7.37 x 3.07 | 7.01 | 416 | tree_broadleaf_c_lod1.glb (196) | trunk r=0.2 | - | `qa/blender_previews/nature_tree_broadleaf_c.png` |
| `tree_pine_a` | tree | 5.43 x 13.00 x 5.31 | 12.6 | 204 | tree_pine_a_lod1.glb (128) | trunk r=0.3 | - | `qa/blender_previews/nature_tree_pine_a.png` |
| `tree_pine_b` | tree | 4.54 x 9.00 x 4.61 | 8.6 | 172 | tree_pine_b_lod1.glb (108) | trunk r=0.26 | - | `qa/blender_previews/nature_tree_pine_b.png` |
| `tree_small_a` | tree | 3.01 x 5.10 x 2.57 | 4.8 | 356 | tree_small_a_lod1.glb (96) | trunk r=0.14 | - | `qa/blender_previews/nature_tree_small_a.png` |
| `tree_dead` | tree | 4.38 x 7.91 x 3.94 | 7.51 | 416 | tree_dead_lod1.glb (94) | trunk r=0.24 | - | `qa/blender_previews/nature_tree_dead.png` |
| `cactus_a` | shrub | 1.85 x 3.55 x 0.51 | 3.25 | 354 | - | trunk r=0.3 | - | `qa/blender_previews/nature_cactus_a.png` |
| `bush_a` | shrub | 1.84 x 0.96 x 1.54 | 0.9 | 260 | - | none | - | `qa/blender_previews/nature_bush_a.png` |
| `bush_b` | shrub | 2.93 x 1.61 x 2.36 | 1.55 | 428 | - | none | - | `qa/blender_previews/nature_bush_b.png` |
| `bush_c` | shrub | 1.83 x 0.91 x 1.15 | 0.85 | 320 | - | none | - | `qa/blender_previews/nature_bush_c.png` |
| `hedge_ball` | shrub | 1.17 x 1.45 x 1.23 | 1.25 | 106 | - | blob r=0.45 | - | `qa/blender_previews/nature_hedge_ball.png` |
| `fern` | groundcover | 1.32 x 0.39 x 1.46 | 0.39 | 300 | - | none | yes | `qa/blender_previews/nature_fern.png` |
| `grass_tuft_a` | groundcover | 0.36 x 0.47 x 0.28 | 0.42 | 60 | - | none | yes | `qa/blender_previews/nature_grass_tuft_a.png` |
| `grass_tuft_b` | groundcover | 0.39 x 0.33 x 0.31 | 0.28 | 100 | - | none | yes | `qa/blender_previews/nature_grass_tuft_b.png` |
| `flower_patch_a` | groundcover | 0.70 x 0.49 x 0.79 | 0.45 | 266 | - | none | yes | `qa/blender_previews/nature_flower_patch_a.png` |
| `flower_patch_b` | groundcover | 0.73 x 0.50 x 0.64 | 0.45 | 352 | - | none | yes | `qa/blender_previews/nature_flower_patch_b.png` |
| `reeds` | groundcover | 1.23 x 1.81 x 1.10 | 1.72 | 390 | - | none | yes | `qa/blender_previews/nature_reeds.png` |
| `rock_a` | rock | 0.47 x 0.33 x 0.37 | 0.3 | 20 | - | none | - | `qa/blender_previews/nature_rock_a.png` |
| `rock_b` | rock | 0.95 x 0.57 x 0.71 | 0.53 | 42 | - | blob r=0.36 | - | `qa/blender_previews/nature_rock_b.png` |
| `rock_c` | rock | 1.60 x 0.92 x 1.11 | 0.85 | 50 | - | blob r=0.58 | - | `qa/blender_previews/nature_rock_c.png` |
| `rock_d` | rock | 2.56 x 1.39 x 1.67 | 1.27 | 80 | - | blob r=0.85 | - | `qa/blender_previews/nature_rock_d.png` |
| `rock_e` | rock | 3.99 x 2.33 x 3.19 | 2.18 | 112 | - | blob r=1.3 | - | `qa/blender_previews/nature_rock_e.png` |
| `cliff_chunk_a` | cliff | 6.60 x 6.22 x 4.55 | 5.52 | 390 | - | trimesh | - | `qa/blender_previews/nature_cliff_chunk_a.png` |
| `cliff_chunk_b` | cliff | 8.69 x 8.45 x 5.62 | 7.65 | 684 | - | trimesh | - | `qa/blender_previews/nature_cliff_chunk_b.png` |
| `log` | log | 2.63 x 0.83 x 0.69 | 0.8 | 204 | - | box | - | `qa/blender_previews/nature_log.png` |
| `coral_a` | underwater | 1.28 x 1.07 x 1.18 | 1.05 | 620 | - | none | - | `qa/blender_previews/nature_coral_a.png` |
| `coral_b` | underwater | 1.23 x 0.86 x 0.97 | 0.84 | 364 | - | none | - | `qa/blender_previews/nature_coral_b.png` |
| `coral_c` | underwater | 1.36 x 0.70 x 1.13 | 0.68 | 392 | - | none | - | `qa/blender_previews/nature_coral_c.png` |
| `kelp_a` | underwater | 1.62 x 5.30 x 1.66 | 5.28 | 712 | - | none | - | `qa/blender_previews/nature_kelp_a.png` |
| `seashell` | underwater | 0.34 x 0.08 x 0.18 | 0.08 | 148 | - | none | - | `qa/blender_previews/nature_seashell.png` |
| `starfish` | underwater | 0.40 x 0.06 x 0.37 | 0.06 | 80 | - | none | - | `qa/blender_previews/nature_starfish.png` |
| `anchor` | underwater | 2.27 x 1.51 x 1.00 | 1.35 | 568 | - | box | - | `qa/blender_previews/nature_anchor.png` |
| `sunken_crate` | underwater | 1.51 x 1.34 x 1.41 | 1.14 | 608 | - | box | - | `qa/blender_previews/nature_sunken_crate.png` |

Export path of every row: `gta/generated/models/nature/<id>.glb` (LOD1: `<id>_lod1.glb`, group
previews `qa/blender_previews/nature_group_trees.png` and `nature_group_trees_lod1.png`).

Loading snippet (soft dependency, no class names):

```gdscript
var f := FileAccess.open("res://gta/generated/models/nature/manifest_nature.json", FileAccess.READ)
var entries: Array = (JSON.parse_string(f.get_as_text()) as Dictionary)["nature"]
var scene := load("res://gta/generated/models/nature/" + entry["file"]) as PackedScene
var mesh: Mesh = (scene.instantiate().find_child("Mesh", true, false) as MeshInstance3D).mesh  # for MultiMesh
```

## 3. Animals

No armature. Every animal is a root with **rigid part meshes whose origins are at their joints**,
ready for procedural animation (rotate the part nodes). Facing **-Z in Godot** (Blender +Y), real
world scale, feet on y = 0 (fish: centred on the origin). `_L` = animal's left = -X.

| kind | part nodes (exact names) |
|---|---|
| land | `Body`, `Head` (origin at the neck base; includes neck, ears, antlers / horns / tusks, collar), `Leg_FL`, `Leg_FR`, `Leg_RL`, `Leg_RR` (origin at shoulder / hip, leg hangs along -Y), `Tail` (origin at its base) |
| bird | `Body`, `Head` (origin at the neck base), `Wing_L`, `Wing_R` (origin at the wing root, authored **spread**), `Tail`, plus extra `Legs` (both legs, origin at the hip) |
| fish | `Body` (incl. dorsal / pelvic fins), `Tail` (origin at the tail root), `Fin_L`, `Fin_R` (pectorals, origin at the root) |

Rotation conventions in Godot (`node.rotation_degrees`, default YXZ order), all verified in
`qa/screenshots/na_animals_posed.png`:

- legs: swing about **X** (`+x` = foot forward). Walk cycle = diagonal pairs in phase
  (`Leg_FL` with `Leg_RR`), amplitude about 25 deg walking, 40-45 deg running.
- head: pitch about X (`graze_head_pitch_deg` = -65 puts the muzzle on the ground for deer / cow /
  rabbit), look left / right about Y.
- tail: wag about Y, lift about X. Fish: swim by oscillating `Tail` about **Y** (+-25 deg) and
  the pectoral `Fin_*` about Z.
- birds: flap = `Wing_R.rotation_degrees.z = +a`, `Wing_L ... = -a` (the body axis). Standing
  pose = manifest `poses.folded` (rotation + scale per wing, wings swung back along the flanks);
  flight = wings at rest pose, `poses.flight` tucks `Legs` back.

Manifest entry (`manifest_animals.json` -> `"animals": [...]`):

```json
{"id": "deer", "file": "deer.glb", "kind": "land", "size": [0.66, 2.011, 1.714],
 "parts": ["Body", "Head", "Leg_FL", "Leg_FR", "Leg_RL", "Leg_RR", "Tail"], "shoulder_height": 1.02,
 "length": 1.714, "pivots": {"Body": [x, y, z], "...": []}, "tris": 742, "tags": ["hill", "grazer", "flees"],
 "materials": ["P_TrunkLight", "..."], "walk_speed": 1.4, "run_speed": 11.0, "body_radius": 0.428,
 "leg_length": 0.78, "graze_head_pitch_deg": -65.0}
```

- `size` [x, y, z] Godot axes (deer height includes the antlers); `pivots` = rest position of
  every part node (Godot axes) - reset a part by restoring its pivot and zero rotation.
- `kind`: `land`, `bird`, `fish`. `tags` hint at habitat and temperament (`flees`, `predator`,
  `dangerous`, `pet`, `flock`, `school`, ...).
- `walk_speed` / `run_speed` (m/s; birds: run = flight cruise, fish: cruise / burst) and
  `body_radius` are optional hints for the wildlife AI, not a contract.
- birds additionally: `wing_span`, `poses`, `flap_axis`.

| id | kind | size x,y,z (m) | shoulder | tris | parts | walk / run (m/s) | preview |
|---|---|---|---|---|---|---|---|
| `deer` | land | 0.66 x 2.01 x 1.71 | 1.02 | 742 | Body, Head, Leg_FL, Leg_FR, Leg_RL, Leg_RR, Tail | 1.4 / 11 | `qa/blender_previews/animal_deer.png` |
| `boar` | land | 0.45 x 0.94 x 1.80 | 0.84 | 638 | Body, Head, Leg_FL, Leg_FR, Leg_RL, Leg_RR, Tail | 1.2 / 8 | `qa/blender_previews/animal_boar.png` |
| `coyote` | land | 0.28 x 0.98 x 1.37 | 0.62 | 600 | Body, Head, Leg_FL, Leg_FR, Leg_RL, Leg_RR, Tail | 1.6 / 10 | `qa/blender_previews/animal_coyote.png` |
| `dog` | land | 0.29 x 0.87 x 1.09 | 0.57 | 660 | Body, Head, Leg_FL, Leg_FR, Leg_RL, Leg_RR, Tail | 1.5 / 8.5 | `qa/blender_previews/animal_dog.png` |
| `cat` | land | 0.17 x 0.44 x 0.64 | 0.27 | 510 | Body, Head, Leg_FL, Leg_FR, Leg_RL, Leg_RR, Tail | 1 / 7 | `qa/blender_previews/animal_cat.png` |
| `rabbit` | land | 0.19 x 0.34 x 0.44 | 0.17 | 408 | Body, Head, Leg_FL, Leg_FR, Leg_RL, Leg_RR, Tail | 0.8 / 8 | `qa/blender_previews/animal_rabbit.png` |
| `cow` | land | 0.77 x 1.73 x 2.76 | 1.45 | 836 | Body, Head, Leg_FL, Leg_FR, Leg_RL, Leg_RR, Tail | 1 / 4.5 | `qa/blender_previews/animal_cow.png` |
| `seagull` | bird | 1.31 x 0.36 x 0.60 | 0.27 | 338 | Body, Head, Wing_L, Wing_R, Tail, Legs | 0.5 / 9 | `qa/blender_previews/animal_seagull.png` |
| `pigeon` | bird | 0.66 x 0.23 x 0.33 | 0.17 | 346 | Body, Head, Wing_L, Wing_R, Tail, Legs | 0.4 / 8 | `qa/blender_previews/animal_pigeon.png` |
| `fish_small` | fish | 0.15 x 0.23 x 0.40 | 0 | 204 | Body, Fin_L, Fin_R, Tail | 0.8 / 3 | `qa/blender_previews/animal_fish_small.png` |
| `shark` | fish | 1.72 x 1.06 x 3.28 | 0 | 508 | Body, Fin_L, Fin_R, Tail | 1.5 / 7 | `qa/blender_previews/animal_shark.png` |

Export path of every row: `gta/generated/models/animals/<id>.glb`. Group previews:
`qa/blender_previews/animals_group_all.png`, `animals_group_small.png`, `animals_group_side.png`.

Suggested sounds (ARCHITECTURE.md 6.11): deer `animal_deer`, dog `animal_dog_bark`, pigeon
`animal_bird`, seagull `animal_gull`, boar / coyote / shark `animal_growl`.

## 4. Verification

- Blender: `G.validate` on all 56 roots: 0 issues (no placeholder names, no unapplied scale, no
  missing materials); every asset previewed (individual + group sheets); signed-volume audit of
  all mesh islands (no flipped / open shells).
- Godot contract test (reads both manifests, instantiates every GLB incl. LOD1s, checks node
  names, pivots, AABB vs manifest, feet on the ground, facing, left/right sides, palette
  materials):

  ```powershell
  & tools/godot.ps1 -Mode headless -Scene res://gta/tests/scenes/na_showcase.tscn -Frames 300
  # TEST_RESULT: PASS na_showcase checks=712 shots=0 failures=0
  & tools/godot.ps1 -Mode window -Scene res://gta/tests/scenes/na_showcase.tscn -Frames 400
  # TEST_RESULT: PASS na_showcase checks=824 shots=7 failures=0  (writes qa/screenshots/na_*.png)
  ```
- `print_scene_tree.gd` on `animals/deer.glb`, `animals/seagull.glb`, `nature/palm_a.glb`: node
  names and `P_*` material names arrive intact.

## 5. Decisions and limits (honest notes)

- Animals are rigid-part models by design (brief): limbs do not bend at the knee. The leg shapes
  are authored with the knee / hock silhouette baked in so a simple hip swing reads well.
- Birds are authored with spread wings (best for flight); the folded standing pose is a
  rotation + scale of the same rigid wing (see `poses.folded`), not a separate mesh.
- `Legs` on birds is one extra part beyond the brief so legs can be tucked in flight.
- No collision meshes are exported; the manifest carries the collision hints instead.
- The stage (floor / sky / light) in `na_showcase.gd` is test scaffolding from engine primitives
  and is never used as game content.
- `P_OliveDrab` (kelp stems, algae) and `P_SteelDark` (anchor) are shared palette materials
  created by hard-surface authors with a little metallic value; everything else is metallic 0.
- These assets are not placed in the world by this module: the WORLD / city builder (vegetation,
  rocks, underwater dressing) and the AI wildlife system consume them through the manifests.
