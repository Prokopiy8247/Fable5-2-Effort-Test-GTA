# MISC_PROPS - set pieces and gameplay props

Author module: **SET-PIECE ARTIST** (`art:misc`). Everything here was authored in the live master
`.blend` through the Blender MCP by `tools/blender/assets/misc_props.py` (no external assets, no image
textures; shared palette materials only).

| What | Where |
|---|---|
| Builder (reproducible pipeline) | `tools/blender/assets/misc_props.py` |
| Exports | `res://gta/generated/models/misc/<id>.glb` (45 files, 45984 tris in total) |
| Manifest | `res://gta/generated/models/misc/manifest_misc.json` |
| Blender collections | `GTA_GODOT/Misc` (slot region `misc`), VFX helpers in `GTA_GODOT/VFX_HelperMeshes` |
| Blender previews | `qa/blender_previews/misc_*.png` |
| In-engine screenshots | `qa/screenshots/misc_*.png` (from `gta/tests/misc_showcase.gd`) |
| Godot verification tool | `gta/code/editor/misc_check_glbs.gd` |

No gameplay code lives in this module: these are models + data. World / transit / activities /
police / player modules place and drive them.

---------------------------------------------------------------------------------------------------

## 1. Conventions

- 1 unit = 1 m. Blender assets face **+Y**, so in Godot the front is **-Z**, right is +X, up is +Y.
  Every position below and in the manifest is already in **Godot axes**.
- Origin = bottom centre on the ground, except where a note says otherwise:
  `buoy` and `fishing_boat_static` (waterline), `boat_ramp` (sea level), `shipwreck` (seabed level),
  `parachute_canopy` (harness point), `parachute_pack` (centre of the wearer's back),
  `vfx_light_cone` (apex).
- Imported structure: `FileRoot (Node3D) -> <id> (Node3D) -> parts`. Find parts with
  `inst.find_child("Target", true, false)`. Inside the `.blend` the same objects are called
  `<id>.<Part>` (object names are global in Blender); the export step strips that prefix.
  The Blender root of `parachute_pack` is `misc_parachute_pack` (the plain name belongs to the weapon
  artist's pickup); the GLB root node is still `parachute_pack`.
- Markers are plain `Node3D` children of the asset root (also listed in the manifest, so you do not
  have to instantiate the scene to read them). A marker's -Z is its facing direction.
- Materials: shared palette materials `P_<Key>` plus the contract materials `M_Glass` (alpha 0.45,
  imported as transparent), `M_Headlight`, `M_Taillight`, `M_Indicator`, `M_Siren_Red`,
  `M_Siren_Blue`. Emissive: `P_LampWarm`, `P_HeadlightWhite`, `P_Neon*`, `P_SirenRed`, `P_IndicatorAmber`
  and the `M_*` lights. No per-object duplicate materials.
- `collision` in the manifest is a recommendation for whoever spawns the asset:
  `box` = one box from `aabb_min` / `aabb_max` is good enough, `trimesh` = walk-in / drive-on /
  irregular (build a concave shape from the meshes), `none` = decorative or driven by game logic.

## 2. Manifest schema (`manifest_misc.json`)

```json
{"author": "misc_props", "axes": "...", "misc": [
  {"id": "tram", "file": "tram.glb", "category": "transit", "family": "transit",
   "size": [2.87, 4.59, 18.38], "aabb_min": [x, y, z], "aabb_max": [x, y, z],
   "collision": "trimesh", "tris": 6500,
   "markers": {"Door_1": [1.45, 0.35, -3.8]}, "marker_yaw_deg": {"Door_1": 90.0},
   "nodes": ["Body", "..."], "groups": ["Doors_L", "Doors_R"],
   "note": "...", "...extra per-asset keys...": 0}]}
```

`size` = `[x, y, z]` extents in Godot axes (exact vertex bounds, markers excluded). `nodes` = mesh
nodes, `groups` = plain Node3D groups with mesh children. Extra keys are asset specific
(`floor_height`, `lip_height`, `opening_width`, `collision_boxes` ...).
Categories: `transit, set_piece, harbour, beach, park, airport, activities, police, parachute,
service, vfx`.

## 3. Asset list

Size is x (width) x y (height) x z (length) in Godot axes, in metres.

| id | category | size x*y*z | tris | collision | mesh nodes | markers | Blender preview (`qa/blender_previews/`) |
|---|---|---|---|---|---|---|---|
| `tram` | transit | 2.87 x 4.59 x 18.38 | 6500 | trimesh | `Body`, `Door_L1_A`, `Door_L1_B`, `Door_L2_A`, `Door_L2_B`, `Door_R1_A`, `Door_R1_B`, `Door_R2_A`, `Door_R2_B`, `Glass_Front`, `Glass_L`, `Glass_R`, `Glass_Rear`, `Pantograph` (groups: `Doors_L`, `Doors_R`) | `Door_1`, `Door_2`, `Light_Head_L`, `Light_Head_R`, `Light_Tail_L`, `Light_Tail_R`, `Pantograph_Top`, `Seat_1`, `Seat_2`, `Seat_3`, `Seat_4`, `Stand_1`, `Stand_2`, `Stand_3`, `Stand_4` | misc_tram.png (+ misc_tram_nose / _tail / _mid / _inside) |
| `rail_straight` | transit | 2.50 x 0.05 x 4.00 | 152 | none | `Track` | - | misc_rail_straight.png |
| `rail_post` | transit | 3.03 x 6.88 x 0.56 | 352 | box | `Post` | `Wire` | misc_rail_post.png |
| `shipwreck` | set_piece | 10.69 x 10.99 x 25.05 | 5878 | trimesh | `Debris`, `Hull_Bow`, `Hull_Stern`, `Seaweed`, `Treasure_Chest` | `Treasure` | misc_shipwreck.png (+ misc_shipwreck_bow / _stern / _break) |
| `container_a` | harbour | 2.47 x 2.60 x 6.13 | 850 | box | `Container` | `Top` | misc_harbour_containers.png |
| `container_b` | harbour | 2.47 x 2.60 x 6.13 | 850 | box | `Container` | `Top` | misc_harbour_containers.png |
| `container_c` | harbour | 2.47 x 2.60 x 6.13 | 850 | box | `Container` | `Top` | misc_harbour_containers.png |
| `container_open` | harbour | 2.97 x 2.60 x 7.14 | 904 | trimesh | `Container` | `Inside`, `Top` | misc_container_open.png |
| `cargo_stack` | harbour | 7.77 x 7.77 x 6.32 | 2436 | trimesh | `Stack` | `Top_1`, `Top_2`, `Top_3` | misc_harbour_containers.png |
| `dock_crane` | harbour | 12.84 x 18.42 x 22.23 | 2390 | trimesh | `Crane` | `Boom_Tip`, `Cab`, `Hook` | misc_dock_crane.png |
| `buoy` | harbour | 1.84 x 5.21 x 1.94 | 588 | box | `Buoy` | `Light` | misc_harbour_small.png |
| `mooring_bollard` | harbour | 0.68 x 0.72 x 1.30 | 488 | box | `Bollard` | - | misc_harbour_small.png |
| `boat_ramp` | harbour | 6.82 x 5.06 x 14.04 | 744 | trimesh | `Ramp` | `Top`, `Water_End` | misc_harbour_small.png |
| `lifebuoy_stand` | harbour | 1.00 x 2.20 x 0.39 | 388 | box | `Stand` | - | misc_harbour_small.png |
| `fishing_boat_static` | harbour | 3.38 x 4.90 x 8.49 | 1750 | trimesh | `Boat` | `Deck`, `Mooring_Bow`, `Mooring_Stern` | misc_fishing_boat.png |
| `beach_umbrella` | beach | 2.65 x 2.39 x 2.63 | 284 | none | `Umbrella` | `Shade` | misc_park_a.png |
| `lounger` | beach | 0.67 x 0.86 x 1.89 | 328 | box | `Lounger` | `Lie` | misc_park_a.png |
| `lifeguard_tower` | beach | 4.01 x 6.87 x 7.62 | 1244 | trimesh | `Tower` | `Lookout`, `Platform`, `Ramp_Bottom` | misc_park_b.png |
| `volleyball_net` | beach | 12.28 x 3.25 x 2.65 | 780 | none | `Net` | `Court_A`, `Court_B` | misc_park_a.png |
| `picnic_table` | park | 1.85 x 0.80 x 2.02 | 428 | box | `Table` | `Seat_1`, `Seat_2`, `Seat_3`, `Seat_4` | misc_park_a.png |
| `fountain` | park | 6.80 x 3.32 x 6.80 | 2052 | trimesh | `Fountain`, `Water` | `Jet_Top`, `Seat_1`, `Seat_2` | misc_park_b.png (+ misc_fountain_close) |
| `playground_slide` | park | 1.70 x 3.40 x 6.09 | 584 | trimesh | `Slide` | `Exit`, `Top` | misc_park_a.png |
| `gazebo` | park | 6.05 x 5.42 x 6.37 | 1580 | trimesh | `Gazebo` | `Center`, `Entrance` | misc_park_b.png (+ misc_gazebo_close) |
| `viewpoint_binoculars` | park | 0.60 x 1.55 x 1.04 | 762 | box | `Viewer` | `Eye`, `Use` | misc_park_a.png |
| `park_statue` | park | 4.20 x 4.40 x 2.44 | 636 | box | `Statue` | - | misc_park_b.png |
| `windsock` | airport | 0.96 x 6.37 x 3.20 | 538 | box | `Mast`, `Sock` | `Light` | misc_airport.png |
| `runway_light` | airport | 0.32 x 0.47 x 0.32 | 192 | none | `Body` | `Light` | misc_airport.png, misc_vfx_helpers.png |
| `runway_sign` | airport | 1.96 x 1.02 x 0.30 | 296 | box | `Sign` | - | misc_airport.png |
| `helipad_beacon` | airport | 0.64 x 2.02 x 0.71 | 440 | box | `Base`, `Lamp` | `Light` | misc_airport.png |
| `aircraft_stairs` | airport | 1.77 x 3.65 x 6.20 | 1244 | trimesh | `Stairs` | `Platform`, `Stairs_Bottom`, `Stairs_Top` | misc_airport.png |
| `fuel_truck_static` | airport | 2.94 x 3.44 x 7.93 | 2078 | box | `Truck` | `Driver_Door`, `Hose` | misc_airport.png |
| `radar_dish` | airport | 4.64 x 7.86 x 3.28 | 1030 | box | `Dish`, `Tower` | `Light` | misc_airport.png |
| `target_round` | activities | 0.97 x 1.97 x 1.14 | 396 | box | `Stand`, `Target` | `Bullseye` | misc_activities.png |
| `target_silhouette` | activities | 0.90 x 1.66 x 0.60 | 228 | box | `Base`, `Target` | `Hit_Center` | misc_activities.png |
| `stunt_ramp_small` | activities | 2.40 x 1.03 x 3.09 | 240 | trimesh | `Ramp` | `Entry`, `Lip` | misc_activities.png |
| `stunt_ramp_big` | activities | 5.09 x 2.97 x 7.78 | 1140 | trimesh | `Ramp` | `Entry`, `Lip` | misc_activities.png |
| `checkpoint_arch` | activities | 13.30 x 5.56 x 5.30 | 1008 | trimesh | `Arch` | `Gate`, `Post_L`, `Post_R` | misc_activities.png |
| `race_flag` | activities | 1.41 x 2.85 x 0.72 | 394 | none | `Flag` | - | misc_activities.png |
| `spike_strip` | police | 5.41 x 0.14 x 0.40 | 940 | none | `Strip` | - | misc_police_para_service.png |
| `police_light_stand` | police | 1.58 x 2.80 x 1.40 | 460 | box | `Stand` | `Light_Blue`, `Light_Flood`, `Light_Red` | misc_police_para_service.png |
| `parachute_canopy` | parachute | 7.42 x 5.21 x 2.92 | 556 | none | `Canopy`, `Lines` | `Canopy_Center`, `Harness`, `Toggle_L`, `Toggle_R` | misc_police_para_service.png |
| `parachute_pack` | parachute | 0.45 x 0.73 x 0.46 | 440 | none | `Pack`, `Straps` | `Deploy` | misc_parachute_pack.png |
| `traffic_barrier_arm` | service | 5.06 x 1.28 x 0.75 | 486 | box | `Arm`, `Housing` | `Lane` | misc_police_para_service.png |
| `vfx_checkpoint_ring` | vfx | 2.00 x 1.00 x 2.00 | 48 | none | `Ring` | - | misc_vfx_helpers.png |
| `vfx_light_cone` | vfx | 0.70 x 0.70 x 1.00 | 32 | none | `Cone` | - | misc_vfx_helpers.png |

Every asset stays inside its budget (tram <= 7 k, shipwreck <= 6 k, others 50-2500; the two VFX
helper meshes are deliberately tiny).

## 4. Per-asset notes (from the manifest)

- **`tram`** - front = -Z. Doors_R / Doors_L are Node3D groups, each with four sliding leaf meshes Door_<side><n>_<A|B> (slide a leaf 0.7 m along Z away from its partner, or hide the group). Door_1 / Door_2 = boarding points on the right side at floor level (marker -Z looks into the tram). Seat_n = hip points facing forward, Stand_n = floor points
- **`rail_post`** - pole stands 2.4 m left of the track centre; the arm reaches toward +X
- **`shipwreck`** - origin = seabed level at the centre; the two hull halves are sunk up to ~1 m into the seabed by design
- **`container_open`** - walk-in: doors open at the front (-Z), interior 2.28 x 5.9 x 2.34 m, floor 0.17 m above the ground, reached over a 0.8 m steel ramp plate (12 deg) at the doorway
- **`cargo_stack`** - stepped 3-2-1 stack of six containers: climbable cover
- **`dock_crane`** - rail gantry crane; rails run along X (quay direction), the boom reaches forward (-Z) over the water; trucks pass under it along X (clear 4.4 m under the sill ties, 6.4 m wide)
- **`buoy`** - origin at the WATERLINE (float body spans y -0.65..0.75, tail down to -1.9): place it at the wave height
- **`boat_ramp`** - origin = centre at SEA LEVEL; flat landing at +1.5 m at the back (z +5.5..+7), slopes down to -1.5 m at the front (z -7 = water end); solid body down to -2.6 m
- **`fishing_boat_static`** - origin at the WATERLINE; draft 0.6 m, deck 0.55 m above the water
- **`beach_umbrella`** - decorative; add a thin pole collider (r 0.04) if needed
- **`lounger`** - head end at the back (+Z), feet toward the front (-Z)
- **`lifeguard_tower`** - walk-up ramp (32 deg) at the front (-Z), hollow hut with a door on the platform
- **`volleyball_net`** - net spans X (9.5 m), top tape at 2.43 m; posts at x = +-5.0
- **`picnic_table`** - table runs along X, benches on the +Z and -Z sides
- **`fountain`** - child 'Water' (P_Sky) holds every water surface / stream so the game can swap in a water material or hide it
- **`playground_slide`** - ladder at the back (+Z), chute runs toward the front (-Z)
- **`gazebo`** - octagonal, entrance (steps) at the front (-Z), floor 0.3 m high, clear height 2.4 m
- **`viewpoint_binoculars`** - looks toward the front (-Z); the user stands behind it (marker 'Use')
- **`park_statue`** - original abstract sculpture 'Sun over the Bay': brass ring, teal wave ribbon, coral sun
- **`windsock`** - child 'Sock' has its origin on the mast axis and points toward -Z (downwind) at rest: rotate it around Y with the wind
- **`runway_light`** - lens material P_LampWarm (emissive); the game may tint it per use (edge white, threshold green/red, taxiway blue)
- **`runway_sign`** - taxiway guidance board, readable from both sides (+Z / -Z); glyphs are abstract (arrow / bars), no lettering
- **`helipad_beacon`** - child 'Lamp' (origin on the vertical axis) carries a green and a white lens on opposite sides: spin it around the vertical axis
- **`aircraft_stairs`** - mobile airstairs; climb from the back (+Z) up to the platform at the front (-Z, aircraft side, 2.6 m). Steps: rise 0.2 m / run 0.3 m - use markers Stairs_Bottom / Stairs_Top for a ramp collider if the character controller cannot step
- **`fuel_truck_static`** - decorative aviation fuel bowser (not a driveable vehicle)
- **`radar_dish`** - child 'Dish' (origin on the vertical axis at the turntable) is the rotating antenna: spin it around the vertical axis
- **`target_round`** - child 'Target' = ring face (origin at the bullseye, faces the front (-Z), radius 0.45, leans back 6 deg); child 'Stand' = easel
- **`target_silhouette`** - knock-down steel target shaped like a BOTTLE (abstract, not a figure). Child 'Target' has its origin on the hinge axis (local X) and faces the front (-Z): set rotation.x = +PI/2 to lay it down backward.
- **`stunt_ramp_small`** - kicker: drive toward the model's front (-Z); 3 m long, 1 m lip, 2.4 m wide
- **`stunt_ramp_big`** - scaffold stunt ramp: drive toward the model's front (-Z); 8 m long, 5 m wide, lip 2.6 m
- **`checkpoint_arch`** - inflatable start/finish arch; drive through along Z. Clear opening 8.1 m wide (between the feet) x 3.65 m (under the banner)
- **`race_flag`** - chequered marker flag in a weighted tyre base; flag flies toward +X
- **`spike_strip`** - lies across the road along X (4 m); vehicles cross it along Z. Spikes 14 cm high
- **`police_light_stand`** - portable scene light: red / blue lamps use M_Siren_Red / M_Siren_Blue, floods P_HeadlightWhite
- **`parachute_canopy`** - ram-air canopy, 7 m span; ORIGIN = harness point (pilot's shoulders), canopy 4.6 m above; leading edge toward the front (-Z)
- **`parachute_pack`** - worn rig: ORIGIN = centre of the wearer's back (pack surface that touches the back); the pack extends backward (+Z). Child 'Straps' (harness webbing sized for the 1.8 m humanoid) can be hidden if it clips an outfit
- **`traffic_barrier_arm`** - boom gate across X; child 'Arm' pivots at the housing (origin on the hinge, hinge axis = local Y / Godot Z): rotate it by +80 deg around Godot Z to open. Origin = lane centre
- **`vfx_checkpoint_ring`** - open cylinder wall, radius 1, height 1, origin at the base centre. UV: u = around (0..1), v = height (0..1). Single-sided (outside): scale it in game (e.g. 4 x 6 x 4) and give it an additive fading shader with cull_disabled
- **`vfx_light_cone`** - search-light / beacon beam cone: apex at the origin, axis toward +Y in Blender (= -Z in Godot, like SpotLight3D), length 1, end radius 0.35. UV: u = around, v = 0 at the apex .. 1 at the far end. Single-sided (outside): scale in game, use an additive unshaded shader with cull_disabled

## 5. Hook-in guide

### Tram (`tram`, `rail_straight`, `rail_post`) - TRANSIT
- One rigid two-car model, 18.4 m long, body 2.5 m wide (2.87 m over the mirrors), floor at
  **y = 0.35** (low floor: build the stop platform 0.35 m high and the player walks straight in),
  interior clear height 2.21 m, the gangway between the cars is open (1.97 m high x 1.16 m wide).
- `Body` contains shell, interior (floor, 16 podium seats, grab poles, cab bulkheads + consoles),
  roof kit, bellows and the bogies / wheels. Windows are separate `Glass_Front`, `Glass_Rear`,
  `Glass_L`, `Glass_R` (`M_Glass`), `Pantograph` is separate (origin on the roof, contact strip at
  `Pantograph_Top`, y = 4.62 = wire height of `rail_post`).
- Doors: two double doors per side at z = -3.8 and z = +3.8. `Doors_R` / `Doors_L` are groups with
  four leaves each: `Door_R1_A`, `Door_R1_B` (front door), `Door_R2_A`, `Door_R2_B` (rear door). Leaf
  origin = its own centre at floor level on the outer face. `_A` is always the leaf nearer to the
  tram's front (-Z), `_B` the one nearer to the rear. To open a door: `A.position.z -= 0.7` and
  `B.position.z += 0.7` (they slide along the outside of the body), or simply hide a group.
  Door opening: 1.4 m wide x 1.95 m high.
- Markers: `Door_1` (front) / `Door_2` (rear) = boarding points just outside the right-hand doors at
  floor height, -Z looking into the tram; `Seat_1..4` = hip points of four forward-facing seats in
  the front car (y = 0.82); `Stand_1..4` = floor points in the two door vestibules;
  `Light_Head_L/R`, `Light_Tail_L/R` for optional light nodes.
- Collision: `trimesh` over `Body` works for walking inside. A cheaper compound of 12 boxes is given
  in the manifest as `collision_boxes` (`[cx, cy, cz, sx, sy, sz]`, door openings left free).
- Track: `rail_straight` is a 4 m tile (2.5 m wide, 5 cm high, standard gauge 1.435 m) - tile it
  along the transit path; for curves place it at the sampled path transform every 4 m (it is flush
  enough to overlap). `rail_post`: put it 2.4 m to the LEFT of the track centre line (its arm
  reaches +X, marker `Wire` hangs over the track centre at 4.62 m), one every 25-30 m.

### Shipwreck (`shipwreck`) - WORLD / underwater exploration
- 22 m trawler broken in two (`Hull_Bow`, `Hull_Stern`, each tilted and sunk up to ~1 m into the
  seabed), `Debris`, `Seaweed` and `Treasure_Chest` are separate meshes. Place the origin on the
  seabed (`world.get_height(x, z)`); footprint about 10.7 x 25 m, highest point (mast) 9.5 m above
  the seabed - at the planned -14 m site nothing breaks the surface.
- Hull plates have real holes and the break is open, so `trimesh` collision lets the player swim
  into the hold. Marker `Treasure` sits on the chest between the two halves (pickup / interaction
  point). Hide `Seaweed` if the environment module adds its own animated kelp.

### Harbour
- `container_a/b/c` are solid (box collision); `container_open` is the walk-in variant (front doors
  open, plywood floor 0.17 m up, steel ramp plate at the doorway). `cargo_stack` is a stepped
  3-2-1 stack (cover + climbing, markers `Top_1..3` on the three levels).
- `dock_crane`: rails along X, boom toward -Z. Put it on the quay edge with -Z over the water.
  `Hook` = spreader position (a container can be hung there), `Cab` = operator cab.
- Waterline assets: spawn `buoy` and `fishing_boat_static` at the wave height
  (`environment.get_wave_height`), optionally bobbing. `boat_ramp`: origin at sea level, the high
  landing (+1.5 m) is at +Z, the wet end at -Z.

### Beach / park
- `lifeguard_tower`: platform at 2.5 m reached by a walk-up ramp at the front (trimesh), marker
  `Lookout` = standing point for a lifeguard NPC.
- `fountain`: child `Water` is one mesh with all water surfaces and jets (material `P_Sky`) - swap
  its material for the water shader or animate / hide it. Markers `Seat_1/2` = sitting points on the rim.
- `gazebo`, `playground_slide`, `aircraft_stairs` need trimesh collision to be walked on.
  `picnic_table` (`Seat_1..4`), `lounger` (`Lie`), `viewpoint_binoculars` (`Use`, `Eye`) carry
  interaction markers for sit / lie / look-through points.

### Airport
- Animated children (origin on their spin axis, rotate around Godot Y): `windsock/Sock`,
  `radar_dish/Dish`, `helipad_beacon/Lamp`. `Light` markers are positions for a pooled light.
- `runway_light`: tint the emissive lens (`P_LampWarm` surface of `Body`) per use if wanted.

### Activities
- `target_round`: child `Target` = ring face, origin at the bullseye (`Bullseye` marker), radius
  0.45, ring radii in the manifest (`ring_radii`) for scoring by hit distance.
- `target_silhouette`: bottle-shaped steel plate (deliberately not a human figure). Child `Target`
  has its origin on the hinge: `rotation.x = PI / 2` lays it down backward, 0 stands it up.
- `stunt_ramp_small` (3 m long, 1 m lip, 26 deg) and `stunt_ramp_big` (8 x 5 m, 2.6 m lip,
  31 deg): drive toward the model's -Z; markers `Entry` and `Lip`. Use trimesh collision (the deck
  is curved) and surface meta `wood` / `metal`.
- `checkpoint_arch`: clear opening 8.1 x 3.65 m, drive through along Z; markers `Gate` (centre on
  the ground), `Post_L`, `Post_R`. `race_flag`: small marker flag.
- `vfx_checkpoint_ring` / `vfx_light_cone`: unit helper meshes with clean UVs for additive shaders
  (checkpoint cylinder, search-light / beacon beam). Single-sided: use `cull_disabled`.

### Police / service
- `spike_strip`: 4 m strip across X (5.4 m with the pull cord), no collision - the police module
  should test wheel positions against a 4 x 0.4 m rectangle and call `pop_tire()`.
- `police_light_stand`: markers `Light_Red`, `Light_Blue`, `Light_Flood` for blinking lights.
- `traffic_barrier_arm`: child `Arm` pivots at the housing; `rotation.z = deg_to_rad(80)` opens it.
  Origin = lane centre (marker `Lane`), the arm closes a 4.2 m lane.

### Parachute - PLAYER
- `parachute_canopy`: attach at the player's shoulder / chest height (origin = harness point); the
  canopy is 4.6 m above, 7 m span, leading edge toward -Z. Children `Canopy` and `Lines` are
  separate (scale `Canopy` from 0 for a deploy animation). `Toggle_L/R` = hand positions.
- `parachute_pack`: attach to the `Chest` bone attachment with the origin on the back surface; the
  pack points backward (+Z). Child `Straps` can be hidden when it clips an outfit.

## 6. Rebuilding / changing an asset

Inside one `execute_blender_code` call (see ARCHITECTURE.md 8.1 for the header):

```python
import misc_props as M; importlib.reload(M)
M.build("tram")                 # rebuilds the asset at its own slot (only objects under its root)
M.preview("tram", "misc_tram")  # contact sheet with back-face culling -> qa/blender_previews/
M.export("tram")                # G.validate + GLB export + name-prefix strip
M.write_manifest(); G.save()
# everything: M.build_all(); M.export_all(); M.write_manifest(); G.save()
```

`build()` refuses to touch a root that was not created by this module and raises if two children
of one asset ask for the same name (Blender would silently append `.001`).

## 7. Verification

- `tools\godot.ps1 -Mode script -Script res://gta/code/editor/misc_check_glbs.gd`
  checks every manifest entry against the imported GLB: root node, mesh nodes, marker names and
  positions, size, tri count, missing materials, `M_Glass` transparency.
  Last result: `MISC_CHECK_SUMMARY ok=45 bad=0 total_tris=45984`.
- `tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/misc_showcase.tscn -Frames 300`
  renders the family line-ups plus two tram shots to `qa/screenshots/misc_*.png`
  (`TEST_RESULT: PASS misc_showcase shots=10 failures=0`).
- `print_scene_tree.gd` was run on `tram.glb`, `shipwreck.glb` and `target_silhouette.glb`: contract
  node and material names arrive intact.

## 8. Known limits (honest list)

- Nothing here is placed in the world by this module; no in-game path was tested (models, manifest
  and the look-dev scene only).
- The tram is one rigid mesh set: no bending at the articulation, wheels do not spin (they are part
  of `Body` as the brief asked).
- Door leaves have no animation clips - the transit code slides or hides them.
- Stair assets (`aircraft_stairs`, `gazebo` steps) use real 0.15-0.2 m steps; a character controller
  without step-up needs a ramp collider between the provided markers.
- No LOD meshes; all assets are small enough for `visibility_range_end` culling by the placer.
- Lettering is avoided on purpose (signs use abstract glyphs), so there is no text to localise.
