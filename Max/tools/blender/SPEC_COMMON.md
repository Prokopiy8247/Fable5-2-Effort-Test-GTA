# NEON TIDE asset production — common rules (read first)

You are a technical artist producing original low-poly 3D assets for **NEON TIDE: Vesper Bay**, an original
GTA-style sandbox built in Godot 4.7. Assets are authored **in the user's live Blender through the Blender MCP**
(`mcp__blender-gta-max__*` tools, endpoint localhost:9881, master file
`G:\YouTube\Fable 5.2 Effort Test GTA\Max\GodotFable5.2GTAMax.blend`) and exported as GLB into the Godot project.

## Hard rules

1. Use ONLY these MCP tools: `execute_blender_code`, `look`, `get_scene_info`. **Never** call `search_assets`,
   `import_asset`, `generate_3d` (no downloaded / AI-generated models — everything is modelled by your code).
2. First Blender call: verify `bpy.data.filepath` ends with `Max\GodotFable5.2GTAMax.blend`. If not, STOP and report.
3. Other agents work in the same Blender at the same time on other assets. Therefore:
   - touch ONLY the assets listed in your spec; never delete/rename/move other objects, collections, materials;
   - never call `bpy.ops.wm.read_*`, `open_mainfile`, `revert`, orphan purge, undo, or anything that resets the file;
   - never enter Edit Mode / use `bpy.ops.mesh.*` / change selection-dependent global state outside one call
     (use `bmesh` + the kit; every `execute_blender_code` call must leave Blender in Object Mode);
   - do not edit `tools/blender/gta_kit.py` or `gta/resources/data/palette.json` (shared). Put your own helpers in
     your own module file(s). If the kit has a bug, work around it in your module and mention it in the report.
4. Do NOT launch Godot, do NOT edit `project.godot` or anything under `gta/code`, do NOT run git.
5. GPU is shared with other agents: use `look` with `shading: "material"` (or "solid"), `max_size` ≤ 640 (512 is
   usually enough), never Cycles, never renders larger than that, no animation renders.
6. No copyrighted designs, logos, brand names or real product replicas. Generic/original shapes and names only.
7. Keep working until every asset of your spec is built, visually checked, exported and listed in your manifest.
   Do not stop early to ask questions; make sensible decisions and note them in the report.

## How code is executed

Write your generator code into module files under `tools/blender/` (e.g. `tools/blender/props_street.py`) with the
Write tool, then execute through the MCP:

```python
import sys, importlib
p = r"G:\YouTube\Fable 5.2 Effort Test GTA\Max\tools\blender"
if p not in sys.path: sys.path.append(p)
import gta_kit as K; importlib.reload(K)
import props_street as M; importlib.reload(M)
print(M.build_all())          # or build one asset while iterating
```

Modules must be **re-runnable** (`K.begin_asset` recreates an asset in place). Keep scripts on disk — they are the
reproducible pipeline. Pass `user_prompt="Build the NEON TIDE asset kit per tools/blender/SPEC_*.md"` on MCP calls.

## Conventions (contract with the Godot code — do not deviate)

- Units metres, Blender Z up. **Asset front faces +Y** (this becomes −Z = forward in Godot). The character's /
  vehicle's left side is −X, right side is +X.
- Asset origin: on the ground (z=0) at the centre of the footprint unless the spec says otherwise.
- Every asset = a root Empty named `<asset_id>` (created by `K.begin_asset(asset_id, category)`), children named
  `<asset_id>__<part>` (created by `mb.to_object(root, "<part>")`, `K.marker(root, "<name>", pos)`).
  Part and marker names in the specs are exact.
- Colour = palette cell. `color` arguments are palette names from `gta/resources/data/palette.json`
  (read that file for the list). Special materials via `"@Name"`:
  `@Glass` (transparent glass), `@Window` (building window pane, lit at night — use on flat quads),
  `@Paint1`/`@Paint2` (vehicle paint channels), `@LightHead`, `@LightTail`, `@LightReverse`, `@LightIndL`,
  `@LightIndR`, `@LightSirenA` (red), `@LightSirenB` (blue), `@LightAux` (roof sign / misc lamp),
  `@SignalR`/`@SignalA`/`@SignalG` (traffic signal lenses), `"@F:<palette>"` (foliage, sways in wind),
  `"@D:<palette>"` (interior surfaces that never get rain-wet), `"@C<n>"` (character region n).
  Palette flags: `tint_a`, `tint_b` (+ `_gloss`, `_metal` variants) are white cells multiplied by a per-instance
  colour in Godot — use them wherever the game should be able to recolour (building walls, awnings, containers,
  umbrellas...). `emis_lamp`, `emis_window_*` glow only at night; `neon_*` glow always (stronger at night);
  `emis_always_*`, `led_*` always glow.
- Shading: flat by default (crisp low-poly). For round forms use `smooth=True` primitives or
  `mb.to_object(root, part, sharp_angle=35)` (smooth with hard edges above the angle).
- Style: **stylised low-poly, chunky readable silhouettes, chamfered hard edges (`bevel=`), flat palette colours,
  no textures.** Think high-quality "POLYGON-style" game kit. Detail comes from secondary shapes (frames, sills,
  handles, vents, trims), not from texture. Avoid paper-thin or coplanar overlapping faces (z-fighting): offset
  layered details by ≥ 5 mm and give thin things real thickness.
- Budgets (triangles, guide): tiny prop ≤ 150, street prop ≤ 400, large prop ≤ 900, building module ≤ 350
  (lod1 ≤ 12), landmark ≤ 6000, weapon ≤ 900, car ≤ 4500 (+ lod1 ≤ 350), aircraft ≤ 6000, character ≤ 2500.
  `K.asset_stats(root)` prints tris and bounding box — check every asset against the spec size.
- No n-gons with holes, no zero-area faces, normals must point outward (the kit primitives guarantee this;
  for `mb.poly`/`mb.quad` list points counter-clockwise as seen from the visible side).

## Kit cheat-sheet (`tools/blender/gta_kit.py` — read it once)

```python
root = K.begin_asset("prop_bench", "StreetProps")        # categories: K.CATEGORIES keys
mb = K.MB()                                               # one MB = one mesh object
mb.box((sx,sy,sz), (x,y,z), "wood_mid", rot=(rx,ry,rz), bevel=0.01, taper=(tx,ty), shear=(dx,dy),
       base=True, colors={"+y": "white", "-z": "black"})  # centred box; base=True -> sits on z
mb.cyl(r, h, (x,y,z), "steel", axis="Z"|"X"|"Y", segs=12, r2=None, base=False, caps=True, cap_color=None, smooth=True)
mb.sphere(r, pos, color, segs=10, rings=6, scale=(1,1,1));  mb.ico(r, pos, color, subdiv=1, jitter=0.15, seed=1)
mb.prism(pts2d, depth, color, plane="YZ"|"XZ"|"XY", pos=(0,0,0), center=True, side_colors=[...], cap_colors=(c0,c1))
mb.loft(rings, color, closed=True, cap_start=True, cap_end=True, smooth=False, ring_colors=[...])
mb.tube(points3d, radius, color, segs=6)                  # pipes, rails, handlebars
mb.quad(a,b,c,d, color, double=False);  mb.poly(pts, color)      # CCW seen from the front
with mb.at(pos, rot=(..), scale=(..)):  ...               # nested local transform (mirror with scale=(-1,1,1))
mb.mirror_x()                                             # duplicate everything mirrored across X
K.add_text(mb, "HOTEL", size=0.8, depth=0.08, color="neon_pink", pos=(0,0.02,3.0))   # 3D lettering readable from +Y
obj = mb.to_object(root, "mesh", origin=None, sharp_angle=None)   # origin=(x,y,z) sets the pivot (wheels, doors)
K.link_copy(obj, root, "wheel_fr", pos, rot)              # linked duplicate sharing mesh data
K.marker(root, "seat_driver", (x,y,z), rot=(0,0,0))       # Empty -> Node3D in Godot (+Y of the marker = forward)
K.arc(cx, cy, r, a0_deg, a1_deg, n) -> 2D points
K.asset_stats(root) -> {'objects','tris','size','min','max'}
K.export_asset(root, "props/prop_bench")                  # -> gta/generated/models/props/prop_bench.glb
K.save_master()                                           # save the .blend (do it after every batch)
```

## Workflow per batch (the visual QA loop is mandatory)

1. Write/extend your module; build a handful of assets through MCP; print `K.asset_stats` for each.
2. `look` at them (`mode: "angles"`, `target: [root names]`, `views` like `["three_quarter", [0.4, 1, 0.3]]`,
   `shading: "material"`, `max_size` ≤ 640). Judge silhouette, proportions vs spec size, colours, missing faces,
   inverted normals (dark/see-through faces), z-fighting, floating parts.
3. Fix anything that looks broken, incoherent or placeholder-like, and look again. An asset is not done because a
   file exists — it must look like a deliberate, finished game asset.
4. Export each asset (`K.export_asset`), then `K.save_master()`.
5. Append the assets to your manifest (see below). Continue with the next batch.

## Manifest + report

Write `gta/resources/data/manifests/<your_manifest_name>.json`:

```json
{ "assets": [ { "id": "prop_bench", "glb": "props/prop_bench", "category": "StreetProps",
                "size": [1.7, 0.57, 0.9], "tris": 380, "parts": ["mesh"], "markers": [], "notes": "" } ] }
```

`size` is the Blender bbox (x, y, z). List every part and marker. Finish with a short report: what was built,
anything skipped or deviating from the spec, kit problems, and how to re-run your modules.
