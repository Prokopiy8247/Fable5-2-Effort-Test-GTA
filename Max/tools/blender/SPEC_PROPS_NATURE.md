# SPEC — Street props, yard/industrial props, beach/pier/underwater props, nature, VFX helper meshes

Read `tools/blender/SPEC_COMMON.md` first. Manifest: `gta/resources/data/manifests/props.json`.
Suggested module files: `tools/blender/props_street.py`, `props_yard.py`, `props_coast.py`, `nature.py`, `vfx_meshes.py`.

Unless stated: single mesh part `mesh`, origin at ground centre, front toward +Y.
Extra manifest fields REQUIRED for every prop (Godot builds colliders and physics from them):

```json
"col": "bbox"                                   // default: one box = bounding box
"col": {"shape": "cyl", "r": 0.12, "h": 7.0, "center": [0, 0, 3.5]}     // Blender coords
"col": {"shape": "box", "size": [0.3, 0.3, 2.4], "center": [0, 0, 1.2]}
"col": "none" | "mesh"                          // "mesh" = Godot uses your `col` part as a triangle mesh
"dynamic": true, "mass": 12                     // dynamic = can be knocked over / pushed by vehicles
```

Two ad-hoc test props already exist in the scene (`prop_cone`, `prop_bench`) — rebuild them properly inside your module
(`K.begin_asset` replaces them in place).

## P1 — Traffic, lighting, signage  (category `StreetProps`, path `props/<id>`)

Orientation rule for roadside props: **+Y points toward the road / toward the approaching viewer.**

| id | size hint | description |
|---|---|---|
| `traffic_light` | pole 6.2 m | Pole ⌀0.18 at origin; mast arm 5.5 m toward **+X** at z 5.8; one 3-lens head on the pole (z≈3.3) and one at the mast end, both facing **+Y**. Lenses ⌀0.2 discs with visors: `@SignalR` top, `@SignalA`, `@SignalG` bottom. `hazard_yellow` back-plates, `charcoal` housings. Static. col = pole cylinder. |
| `street_lamp` | 7.5 m | Tapered pole, arm reaching +Y by 1.8 m, LED head with `emis_lamp` underside. Marker `light` under the head. dynamic, mass 90. col = pole cyl. |
| `street_lamp_double` | 7.5 m | Two arms (±Y). Markers `light_a`, `light_b`. |
| `lamp_park` | 3.5 m | Post-top globe lamp (`emis_lamp` sphere). Marker `light`. dynamic, 40. |
| `sign_stop` | 2.5 m | Red octagon, white 3D "STOP", steel pole. Faces +Y. dynamic, 15. |
| `sign_speed` | 2.5 m | White rectangle "35". |
| `sign_oneway` | 2.5 m | Black/white arrow plate. |
| `sign_parking` | 2.5 m | Blue square "P". |
| `sign_street` | 3.0 m | Two crossed green blades with small white text ("BAYLINE AVE", "MERIDIAN ST"). |
| `sign_hospital` | 2.5 m | Blue square, white "H". |
| `sign_airport` | 2.5 m | Green plate with a simple plane pictogram. |
| `barrier_jersey` | 3.0 × 0.6 × 0.9 | Concrete jersey barrier (wide-base profile, use `mb.prism`). Static. |
| `barrier_plastic` | 1.6 × 0.5 × 0.9 | Red/white water-filled barrier. dynamic, 30. |
| `barrier_police` | 2.0 × 0.6 × 1.1 | A-frame sawhorse, blue/white striped board, small 3D "POLICE". dynamic, 12. |
| `barrier_construction` | 1.5 × 0.5 × 1.0 | Orange/white striped boards, amber lamp (`emis_always_amber`). dynamic, 10. |
| `spike_strip` | 3.6 × 0.3 × 0.06 | Flat strip with rows of small spikes. col none. |
| `prop_cone` | 0.36 × 0.66 | Traffic cone. dynamic, 2. |
| `prop_bollard` | ⌀0.2 × 0.9 | Steel bollard with reflective band. Static. |
| `prop_bollard_light` | ⌀0.2 × 0.9 | Lit bollard (`emis_lamp` slot). Static. |
| `prop_boom_gate` | arm 4.5 m | Parts: `mesh` (post + housing), `arm` (red/white arm extending toward +X, origin at the pivot). |

## P1 — Street furniture

`prop_bench` (1.7 wide), `prop_bin` (⌀0.5 × 0.95, hood; dynamic 15), `prop_dumpster` (2.0 × 1.2 × 1.3, `tint_a` body,
black lids; dynamic 120), `prop_hydrant` (0.35 × 0.8, `red` + caps; marker `spray` on top; dynamic 60),
`prop_bus_stop` (shelter 4.0 × 1.6 × 2.6: roof, `@Glass` back, lit ad panel (`emis_window_cool`), bench, pole sign with
bus pictogram; static; col = "mesh" with a simple `col` part), `prop_mailbox` (dynamic 25), `prop_newsbox`
(`tint_a`; dynamic 15), `prop_vending` (1.0 × 0.8 × 1.9, glowing front, 3D text "ZAP!"; dynamic 80),
`prop_parking_meter` (dynamic 8), `prop_bike_rack`, `prop_planter` (concrete 1.6 × 0.6 × 0.6 with `@F:leaf_green` hedge
+ flowers; static), `prop_planter_round`, `prop_utility_box` (0.7 × 0.5 × 1.3; static), `prop_transformer`
(1.6 × 1.2 × 1.4 green, hazard sticker; static), `prop_manhole` (⌀0.7 × 0.02; col none), `prop_atm` (screen
`screen_blue`; static), `prop_flagpole` (8 m; parts `mesh` + `flag` (`tint_a`, origin at the pole)), `prop_picnic_table`.

## P1 — Fences and walls (length along X, origin at base centre; they tile end to end)

`fence_wood` (2.0 × 1.8, boards + rails; dynamic 25), `fence_picket` (2.0 × 1.0 white; dynamic 12),
`fence_chain` (3.0 × 2.2: steel posts/frame + sparse diamond mesh of thin bars, ≤ 300 tris; static),
`fence_metal` (2.0 × 1.1 railing; static), `wall_brick` (2.0 × 0.3 × 1.0 with cap; static),
`wall_concrete` (2.0 × 0.25 × 2.2; static), `gate_chain` (4 m double gate: parts `leaf_l`, `leaf_r`, origins at hinges).

## P1 — Nature (category `Nature`, path `nature/<id>`; foliage with `"@F:<palette>"`, trunks `bark`/`bark_dark`/`bark_palm`)

Trees MUST be a single mesh part `mesh` (they are instanced by MultiMesh). col = trunk cylinder.

| id | size | description |
|---|---|---|
| `tree_oak_a` | h 9, canopy ⌀6 | Slightly bent trunk with 2 branch stubs + 3–4 jittered ico blobs (`mb.ico(..., jitter=0.18)`), mix `leaf_green`/`leaf_dark`. |
| `tree_oak_b` | h 11, ⌀7 | Bigger, different silhouette, some `leaf_light`. |
| `tree_round` | h 6, ⌀3.2 | Tidy street tree. |
| `tree_pine_a` | h 12 | Trunk + 4–5 stacked tapered cones (`leaf_dark`), hexagonal. |
| `tree_pine_b` | h 8 | Shorter pine. |
| `tree_palm_a` | h 9 | Curved segmented trunk (loft with rings) + 9–11 drooping fronds (bent double-sided strips of 3–4 quads, `palm_green`) + a few coconuts. |
| `tree_palm_b` | h 6.5 | Shorter palm, different bend. |
| `tree_dead` | h 6 | Bare branching tree (tubes). |
| `bush_a`, `bush_b` | ⌀1.6 | Blob bushes (b has flowers). col none. |
| `hedge` | 2.0 × 0.8 × 1.2 | Clipped box hedge with slight irregular top. Static box. |
| `rock_a`, `rock_b`, `rock_c` | 1 m, 2 m, flat 2.5 m slab | Jittered faceted rocks (flat shaded), `rock`/`rock_dark`. Static. |
| `rock_cliff` | 8 × 4 × 5 | Big faceted outcrop for the hill. Static, col "mesh" (use the mesh itself, no separate part needed). |
| `grass_tuft` | 0.35 high | 6–8 tapered double-sided blades, ≤ 24 tris, `@F:grass` / `@F:grass_dark`. col none. |
| `grass_tall` | 0.8 high | ≤ 32 tris, some `@F:grass_dry`. |
| `flower_patch` | 0.6 | Leaves + 5–6 flower heads in mixed colours. |
| `reeds` | 1.4 | Waterside reeds. |
| `fern` | 0.7 | Radiating fronds. |
| `log` | 3 m | Fallen trunk. Static. |
| `stump` | 0.6 | Tree stump. Static. |
| `driftwood` | 1.8 | Bleached branch (`plank_gray`). |

## P2 — Yard / industrial props (category `StreetProps`, path `props/<id>`)

`prop_pallet` (1.2 × 1.0 × 0.15; dynamic 15), `prop_crate` (1.0 cube, framed planks; dynamic 30), `prop_crate_small`
(0.6; dynamic 12), `prop_barrel` (⌀0.6 × 0.9 drum, `tint_a_metal`; dynamic 20), `prop_barrel_explosive` (red, hazard
band, flame diamond; dynamic 25), `prop_gas_tank` (propane bottle ⌀0.4 × 1.2; dynamic 18),
`prop_gas_tank_large` (horizontal tank 3.5 long on saddles; static), `prop_container` (6.06 × 2.44 × 2.59 shipping
container, corrugated sides, doors with lock rods on the +Y end, corner castings, `tint_a_metal`, ≤ 500 tris, plus
`lod1` part ≤ 12 tris; static), `prop_container_open` (same, +Y end open and hollow with an interior floor/walls;
col "mesh" with `col` part), `prop_cable_spool` (⌀1.6), `prop_tire` (single; dynamic 9), `prop_tire_stack`,
`prop_pipe_stack` (pyramid of 6 concrete pipes), `prop_scaffold` (2.5 × 1.2 × 4.0 two levels with planks; static),
`prop_generator`, `prop_floodlight` (tripod, `emis_lamp`, marker `light`), `prop_ac_wall`,
`prop_ladder` (wall ladder module 0.5 × 3.0 high, rungs every 0.3, origin bottom centre, stackable; col none),
`prop_stairs_metal` (fire-escape flight: 3.2 m rise over 4.0 m run toward +Y, 1.0 wide, railings, 1 × 1 top landing;
col "mesh" with a sloped-box `col` part),
`prop_ramp_stunt` (4.0 wide × 7.0 long × 1.8 high curved kicker, planks on steel frame, rises toward +Y; col "mesh"
with a `col` wedge part of 4–5 segments), `prop_ramp_small` (2.5 × 3.5 × 0.8; same idea), `prop_ramp_dirt`
(6 × 8 × 1.6 dirt mound, `dirt`; col "mesh" = itself).

## P2 — Beach, park, pier (path `props/<id>`)

`prop_umbrella` (⌀2.2, `tint_a`/white panels), `prop_beach_chair`, `prop_towel` (`tint_a`, col none),
`prop_surfboard` (stuck upright in sand, `tint_a`), `prop_volleyball_net`, `prop_lifebuoy_stand`,
`prop_lifeguard_tower` (3 × 3 × 4.5 raised hut, ramp, `tint_b` trim, flag; col "mesh" + `col`),
`prop_buoy` (⌀1.0 × 2.2 channel buoy, `tint_a`, `emis_always_white` lamp; origin at the WATERLINE),
`prop_dock_cleat`, `prop_pier_deck` (4 × 4 plank deck 0.25 thick, top at z = 0, four pilings going 4.5 m down, cross
braces; `plank_gray`/`wood_dark`), `prop_pier_rail` (4 m wooden railing 1.1 high), `prop_dock_float` (6 × 2 × 0.5
pontoon, top at z = 0.35, origin at the waterline), `prop_dock_ladder`, `prop_kayak` (`tint_a`),
`prop_windsock` (6 m pole; parts `mesh` + `sock` (orange/white cone, origin at the pole top)),
`prop_runway_light` (0.25 high, `emis_always_white` dome; col none), `prop_helipad_light` (`led_green`).

## P3 — Underwater, activities, VFX

Underwater (path `props/<id>`): `coral_a` (branching tubes, `coral_pink`), `coral_b` (fan/brain shapes,
`coral_orange`), `seaweed_a` (2.5 m kelp strands, `@F:seaweed`), `prop_anchor` (1.6 m, `rust`),
`prop_treasure_chest` (parts `mesh` + `lid` hinged at the back; `gold` coins inside), `wreck_boat` (sunken fishing
boat ≈ 12 m broken in two, tilted mast, holes; col "mesh" + `col`), `wreck_car` (rusted car shell; col bbox).

Activities: `prop_target_round` (parts `mesh` = stand, `target` = ⌀0.6 bullseye disc red/white rings facing +Y, origin
at its bottom edge so it can flip down), `prop_target_man` (parts `mesh` + `target`: abstract rounded torso board with
rings — not a realistic person), `prop_checkpoint_ring` (⌀6 glowing arch, `neon_yellow`; col none),
`prop_start_banner` (10 m wide gantry, checkered band; static, col = two post boxes).

VFX helper meshes (category `VFX`, path `vfx/<id>`, tiny, origin at centre, col none): `fx_debris_a`, `fx_debris_b`,
`fx_debris_c` (jagged concrete shards 0.15–0.3), `fx_debris_metal`, `fx_glass_shard` (`ice_blue`),
`fx_shell_casing` (`brass`, 0.03 × 0.01), `fx_rock_chunk`, `fx_plank`.

Work P1 → P2 → P3; export + update the manifest after each group.
