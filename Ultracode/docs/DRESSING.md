# HALCYON BAY - World dressing (`props` system)

Owner: WORLD DRESSING programmer (Wave 2). Street furniture, traffic and pedestrian signals, street lights,
vegetation, physics props, set pieces and ladders. Contract: `docs/ARCHITECTURE.md` 6.1 / 10 and
`docs/ARCHITECTURE_WAVE2.md` W2.4. Everything placed here is a Blender-authored GLB from
`gta/generated/models/{props,nature,misc}` (manifests merged at boot); the only procedural geometry is the
sagging power-line wires (thin tubes between the `Wire_*` markers of the power poles).

| file | what |
|---|---|
| `gta/code/world/prop_system.gd` | `PropSystem` = the `props` world system: instance store, MultiMesh buckets, batched colliders, activation / pools, damage, explosives, water jets, signal manager, respawn, animated set pieces, public API |
| `gta/code/world/world_prop.gd` | `WorldProp` (RigidBody3D): the pooled physical stand-in of a knocked-over / loose / spawned prop |
| `gta/code/world/dressing/prop_catalog.gd` | merges every `manifest*.json`; extracts meshes, parts, markers; builds idle and rigid collision shapes |
| `gta/code/world/dressing/prop_hit_proxy.gd` | damageable owner of the breakable colliders (forwards bullets / melee / vehicle hits) |
| `gta/code/world/dressing/prop_place_street.gd` | signals, ped signals, lamps, world furniture points, street trees, junction / kerb furniture, drains, manholes, guard rails, lot fences, alleys, billboards, power line |
| `gta/code/world/dressing/prop_place_sets.gd` | stunt ramps, docks, Foundry Yard, marina, beach, park, plaza, viewpoint, airport, shipwreck, buoys, moored boats, ladders, loose extras |
| `gta/code/world/dressing/prop_place_nature.gd` | Signal Hill wood (+ fill, undergrowth, logs), wild / palm / park trees, bushes, rocks + cliffs, ground cover, park lawn, reef |
| `gta/code/world/dressing/prp_signal_lens.gdshader` | signal lens: lit / dark from `INSTANCE_CUSTOM.r`, brighter at night (`gta_night`) |
| `gta/tests/prp_api.gd`, `prp_play.gd`, `prp_boot.gd`, `prp_traffic.gd`, `prp_shots.gd` | headless API test, gameplay test with the real player, boot profile, run with real traffic, windowed look test |

## 1. How it works

**Instances.** Placers call `place(id, xform, opts)` for every piece of dressing. An instance is one row in
parallel packed arrays (type, transform, state, class, hit points, render slots, collider owner, body).
Nothing per instance has a node or a script.

**Rendering.** Each instance owns one or more *slots* in MultiMesh *buckets*: one `MultiMeshInstance3D` per
asset (and LOD / lens variant) per cell. Cells: 150 m for props, 75 m for trees (LOD switch per cell) and small
props, 60 m for ground cover, 300 m for the reef and the signal lenses. Visibility ranges are measured by the
engine to the node's AABB centre, so `visibility_range_end` = manifest range (+ part of the cell half
diagonal for larger cells): the cell the camera stands in is never culled. Trees: LOD0 node until 85 m from
the cell centre, the manifest `lod1` GLB beyond (street trees: no LOD). Ground cover ends at 60 m.
Shadows only for things taller than 2.4 m (no shadows from small props, ground cover, reef, lenses).
Multi-part GLBs are merged into one ArrayMesh per asset (one surface per material); emissive hook materials
(`M_LampGlow`, `P_LampWarm`, `P_Neon*`, `M_Window`) are swapped by the environment's automatic night hook on
the mesh resources.

**Collision.** Shape owners on a few `StaticBody3D` per 150 m chunk and surface (`set_meta("surface")` per
body, so `Fx.surface_of` works):
- `Solid/` bodies, layer `WORLD`: static scenery (walls, hedges, trees = trunk cylinders, rocks = convex
  hulls, cliffs / set pieces / ramps / bus shelter = trimesh, signal poles, bollards ...).
- `Breakables/` bodies, layer `PROP`, meta `thin`: idle colliders of breakable and loose props. Their parent
  is `prop_hit_proxy.gd`, so bullets / melee / vehicle impacts reach `PropSystem` through the normal Dmg
  contract (with `collider` + `shape` the exact instance is resolved via `shape_find_owner`; otherwise the
  nearest instance to `info.position`). Solid scenery has no damageable owner: shooting a wall gives no
  hit marker.
Poles get a thin cylinder around the pole only (arms and sign plates are free); everything else a box from
the manifest `size` / `center` or the asset's own collision hint.

**Classes.**

| class | which assets | idle | when hit |
|---|---|---|---|
| STATIC | manifest `static` (incl. the 340 kg signal masts), all nature, all set pieces | MultiMesh + solid collider | never moves |
| BREAKABLE | manifest `breakable` (lamps, ped signals, signs, hydrants, mailboxes, meters, news boxes, benches, bus shelter, fences, gate) and `dynamic` heavier than 160 kg | MultiMesh + light collider | becomes a WorldProp (pool, cap 60); all its slots (lenses too) collapse |
| LOOSE | manifest `dynamic` up to 160 kg (cones, delineators, plastic / crowd barriers, crates, pallets, drums, explosive drums, gas canisters, tyres, bags, boxes, carts, bins, recycling bins) | MultiMesh + light collider; within 60 m of the player a sleeping WorldProp (cap 64) | already a body near the player; elsewhere like BREAKABLE |

**Activation** (`_activate`): the instance's MultiMesh slot is collapsed (zero basis), its collider owner
disabled, its pooled light (lamps) removed, and a pooled `WorldProp` takes its transform with the asset's
convex-hull collider (shrunk 6 % on tiling fences so a panel never starts inside its static neighbour),
mass from the manifest and a low custom centre of mass on poles / tall props (they topple instead of
sliding). Triggers:
- **Vehicles**: one manager loop per physics frame checks every moving body in group `vehicle` (list refreshed
  at 2 Hz) against the 8 m spatial hash: if an idle breakable / loose instance lies inside the vehicle's
  `body_aabb` (expanded by the prop's pole / body radius) now or within the next 0.12 s of travel, the
  speed exceeds `2.5 + mass / 45` m/s (3..14 m/s: signs ~3, hydrant 4, lamp post 6.5, bus shelter 12) and the
  vehicle's momentum `vehicle mass * speed` exceeds `25 * prop mass` (a 95 kg bicycle knocks signs and cones
  over but stops at a 180 kg lamp post), the prop is converted *before* contact and gets an impulse
  (`mass * speed * 0.55` forward + a little lift at 0.7 m height). The car passes through for 0.18 s
  (collision exception, removed by a serial-checked timer so a re-used pool body keeps its newer exception),
  then hits the body physically. Slower bumps hit the idle collider and go through the Dmg path
  (`type "vehicle"`): VehicleBase sends `amount = dv * 14`, `impulse = dv * mass * 0.4`; the props system
  multiplies the amount by `2.5 * clamp(vehicle mass / 1200, 0.08, 1.6)` (mass recovered from the two).
- **Bullets / melee**: hit points (`mass * 1.2`, 25..500); at 0 the prop is thrown along the shot direction.
- **Explosions**: `EventBus.explosion` (exact centre + radius): breakables whose hit points the blast beats
  and every loose prop in the radius are thrown away from the centre (mass-aware impulse with lift).
  Active / loose WorldProps also get Fx's own blast impulse and damage.

**Side effects of a breakage**: `EventBus.prop_broken(body, instigator)`, impact sound by surface
(`impact_metal / wood / concrete`, `crash_small / large` for vehicles), `noise_emitted` (25 m, "crash"),
hydrant -> water jet for 6 s (repeated `Fx.splash` + steam puffs), bus shelter -> glass shatter + `glass_break`,
first hard landing -> impact sound + dust. Player-caused breakage (player, or a vehicle with
`is_player_driven`) reports `Wanted.report_crime("property_damage", pos, {"instigator": ...})`, at most once
per 8 s.

**Explosives** (`barrel_explosive`, `gas_canister`): 15 hp; any bullet, blast or fire damage lights a 0.18-0.42 s
fuse (sparks + black puff), then `Fx.explosion` (drum: r 5.5, 170 dmg, ground fire; canister: r 3.8, 110).
Chain reactions run through `EventBus.explosion` (idle drums in range) and Fx's blast damage (live drums).

**Rigid hulls**: the WorldProp collider is a plain convex hull (quickhull) of the render mesh; the slow
simplified variant (`create_convex_shape(true, true)` = a V-HACD decomposition, tens of ms per asset) is only
used above 160 hull points. All hulls of breakable / loose types are built at boot (largest: 80 points), so
the first crash into a lamp post does not hitch.

**Cleanup / respawn**: knocked-over bodies are retired after 25 s when asleep and unseen / far (at the latest
90-180 s); the oldest is recycled when the pool is full. Broken or displaced instances come back after
`respawn_seconds` (150 s of game time, a public var) when the spot is > 70 m from the player and not on
screen, and nothing stands on it: a box query on `VEHICLE | PLAYER | NPC | RAGDOLL | PROP` bodies (the
batched static colliders of the neighbours do not count) postpones the respawn by 10 s while a parked car,
a person or another knocked-over prop occupies the spot. Loose bodies that drift > 78 m from the player go
back to their MultiMesh slot when untouched, or count as displaced (respawn rule) when moved.

**Signals** (one manager loop, 4 Hz): 86 `traffic_light` heads at `World.get_signal_heads()` (pole at the
right kerb at the stop line, arm over the approach). The red / yellow / green lenses are three extra
MultiMesh slots per head with `prp_signal_lens.gdshader`; the manager writes `INSTANCE_CUSTOM.r` only when
`RoadGraph.get_signal_state(lane)` changes. 166 `traffic_light_ped` posts at both ends of every crosswalk of
the signalised junctions show WALK while the crossed approach is red (STOP otherwise).

**Lamps**: `street_lamp_a` at the 166 world `street_light` points (+ `street_lamp_b` on the promenade, plaza
and park). Every lamp registers its `Light` marker as a pooled night light with
`environment.register_light_points()` through a small anchor Node3D (light energy 6 / range 21 m for the
8.8 m road lamps, 2.2-2.4 / 11-12 m for park lamps): when the lamp is knocked over the anchor is freed and its
light goes out; it is re-registered when the lamp respawns.

## 2. What is placed (boot of 2026-11-10, after the review)

Measured by `prp_api` / `prp_boot` (headless, full city): **8138 instances of 111 assets** (116 types incl.
LOD / lens variants), **878 MultiMesh nodes**, **90 batched static bodies**, 7 instanced set-piece scenes
(windsock, radar, helipad beacons), 187 lamps with pooled night lights, 86 signal heads, 166 ped
signals, 24 ladder nodes (12 quay / pier, 12 building walls). **1224 nodes** under `Props` (878 MultiMesh,
90 static bodies, 237 Node3D = light anchors / ladders / roots, 15 set-piece meshes, pool bodies on demand).
Setup **0.84-1.3 s** depending on machine load (catalogue 11 ms, street 270-330 ms, sets 200-260 ms, nature
370-510 ms, build incl. rigid hulls 35-50 ms; GLB loading inside the phases ~270-330 ms). Slowest phases
(`get_debug_report().stats.phase_ms`): ground cover ~110-140 ms, Signal Hill fill ~95-115, lot edges ~85-110,
building ladders ~45-60 (mesh check of the back walls).

By group (`get_counts().by_tag`): ground cover 4977, street furniture 488, fences / hedges / walls 410, road
plates + guard rails 393, reef 323, signals 252 (+ lenses), Signal Hill trees 249 (127 world points + 124
fill), lamps 187, signs 155, set pieces 121 (incl. the plaza sculpture and the beach volleyball net), street
trees 112, bushes 103, rocks 92, loose props 63, airport 54, ladder sections 46, wild trees 40, palms 29,
logs 16, park trees 12.

Frame cost (`prp_shots`, 1280x720, busiest downtown street view, whole frame with / without the dressing):
2851 / 1797 draw calls (incl. shadow passes), 0.90 M / 0.61 M primitives, GPU 0.9-1.2 ms / 0.74 ms on the
RTX 5070. Other views: hill wood 726 draw calls, beach 623, docks 956, park 2266 (whole frame).

| group | contents |
|---|---|
| street (all sidewalk roads) | 166 road lamps, 86 signal heads, 166 ped signals, hydrants (world points), bins at signal corners, 4 bus shelters, speed / parking signs (facing the traffic of their side), parking meters every second bay on parking streets, news boxes, mailboxes, planters and bike racks downtown / midtown, utility boxes, signal-controller cabinets and street-name signs at signal corners, stop / yield signs on minor approaches, drains in the gutters, manholes in the lanes, street trees in grates (palms on the waterfront and beach) |
| lots / alleys | hedges, timber fences and low walls round house yards (sides + back), chain-link round industrial yards (needs city building data), dumpsters / recycling bins / bags / boxes / pallets in the alleys |
| arterials / hill road | guard rails where the ground falls away beside the road (47 on the Signal Hill road) and on the outside of the ring road's bends next to open ground (16), billboards on open ground beside the ring road, a power line (poles + wires) up Signal Hill Road |
| Signal Hill | 127 world `tree_hill` points + ~120 fill trees (pine vs broadleaf patches from a noise field, glades, road / paths / viewpoint sight line kept free), ferns and bushes under the trees, 16 fallen logs, binoculars + railing at the viewpoint |
| nature elsewhere | wild trees, palms, park trees, bushes, rocks with small stones around, cliff chunks facing the sea on the rocky shore, grass / fern / flower clusters (3-7 per `ground_cover` point), reeds at the water's edge, park lawn tufts + flower beds |
| underwater | coral / kelp (kelp only deeper than 6.5 m and scaled to stay under water) / shells / starfish on the `reef` points, shipwreck (trimesh, swim-in), anchor and sunken crates round it |
| docks / yard | 2 gantry cranes straddling the quay deck, container rows (some stacked) leaving the ladders, the crane lanes and the ramp clear, mooring bollards, crates / drums / pallets; Foundry Yard containers + cargo stack along the north edge, loose cargo clusters, explosive drums, dumpster, cones lining the ramp run-up |
| marina / beach | park lamps, palms in grates, lifebuoy stands, bins, kiosk, vending machine, bike rack, quay bollards, buoys in the swim zone and the harbour mouth, moored fishing boats; umbrellas + loungers down to the waterline, 2 lifeguard towers (reached by their ramp), volleyball net (first free spot between the towers; posts and both courts reserved), beach car-park carts |
| park / plaza | gazebo, playground slide, picnic tables, park lamps, bins; fountain (14 m off the plaza's named location), the "Sun over the Bay" sculpture (first free quarter of the square, >= 9 m from the fountain), lamp / planter ring, benches facing the fountain, a planter / bench / lamp strip, trees in grates, bollards along the edges (gaps at the walk paths), ATM, phone kiosk, vending machine, bike rack. An 8 m lane ahead of the `downtown_plaza` location stays clear (teleport / spawn heading; the lead's `int_slice` drives a car out that way) |
| airport | runway edge + threshold lights, windsock (sock turns with `Weather.get_wind_vector()`), taxi signs, aircraft stairs, fuel bowser, radar (spinning dish), 4 rotating helipad beacons |
| ramps | `stunt_ramp_big` at `stunt_ramp_1` / `_3`, `stunt_ramp_small` at `stunt_ramp_2` (trimesh, drivable; run-up and landing reserved) |
| ladders | 12 quay / pier ladders at the world `ladder` points (sections from below the water to the deck), fire-escape ladders on 12 building back walls (needs city data; only where the mesh shows a plain wall: no cornice, roof overhang, canopy or plinth within 0.35 m of the ladder line), the radio mast climb node only if the city has not made one (it does now) |

**Placement rules** (all enforced in code, `prp_api` checks them):
- nothing taller than 12 cm stands on a carriageway / junction box / runway / taxiway / dirt track (flush
  plates allowed: drains, manholes, grates); `place()` refuses it (`rejected["carriageway"]`).
- an occupancy hash keeps every footprint apart and reserves named locations, pickups, ladders, gang /
  police / taxi points, parking bays, plane / heli stands, the stunt ramp run-ups.
- kerb-strip furniture lives at hw + 0.25..1.0 m; the walking strip hw + 1..3 m stays free (exceptions: the 4
  bus shelters - 1.84 m deep on a 3 m sidewalk, pulled to the kerb leaving ~1.1 m behind them - and bins /
  signal posts on the corner patches).
- nothing within 7 m of a junction box (crosswalk landings) along the kerb, and nothing along the frontage of
  landmark, parking, plaza and park lots (entrances, kerb ramps, driveways).

## 3. API (`Game.get_system("props")`)

```gdscript
func spawn_prop(prop_id: String, xform: Transform3D) -> Node3D   # W2.4: dynamic / breakable -> sleeping WorldProp, static -> Node3D + StaticBody3D (caller owns it)
func get_prop_def(prop_id: String) -> Dictionary                  # W2.4: merged manifest entry + source, path, size_v, center_v, class
func set_enabled(on: bool) -> void                                # hides everything, removes the colliders, stops the managers
func get_counts() -> Dictionary                                   # instances, by_category, by_tag, by_id, idle / active / broken / loose_live, multimesh_nodes, static_bodies, signal_heads, ped_signals, lamps, ladders ...
func get_debug_report() -> Dictionary                             # timings (stats.phase_ms per placer phase, glb_load_ms, rigid_hull_max_points), MultiMesh nodes per asset, refused placements, missing assets
func find_instances(prop_id, near := INF, radius := INF) -> PackedInt32Array
func get_instance_transform(i) / get_instance_state(i) ("idle","active","broken","live") / get_instance_body(i) / get_instance_tag(i)
func break_instance(i, impulse := Vector3.ZERO, instigator := null) -> WorldProp    # admin / tests
func respawn_all() -> int                                         # admin "repair the city"
func get_signal_heads_info() -> Array; func get_head_lit_state(k) -> int
func get_ped_signals_info() -> Array                              # {position, facing, lane_id, walk, instance}
func get_ladders() -> Array[Node3D]
var respawn_seconds: float                                        # game seconds before broken props may come back (150)
```

`WorldProp`: `prop_id`, `source_index`, `hp`, `explosive`, `role` ("active", "loose", "spawned"),
`instigator`, `apply_damage(info)`. Group `prop`, layer `Layers.PROP`, mask `Layers.PROP_MASK`.

## 4. Integration notes

- **Ladders** (W2.4): every ladder is a Node3D in group `ladder` under `Props/Ladders`: origin at the foot ON
  the rail line of the visible ladder (same convention as the city builder; `PlayerStateLadder` keeps the body
  `STAND_OFF` = 0.36 m behind that line), +Z = climb side, the climber faces local -Z (the wall), `meta height`
  (m, foot to the top exit level), `meta top_exit` (world point 0.9 m past the rail line at the top, on the
  deck / roof), quay ladders also `meta water = true` (the foot is 0.2 m below sea level). `prp_play` climbs a
  building ladder and a quay ladder (from the water) with the real player. Before adding one the placer skips
  spots where another `ladder` node already exists within 1.5 m.
- **Police / activities** may call `spawn_prop("roadblock_police" | "barrier_plastic" | "cone" |
  "spike_strip" | "checkpoint_arch" ...)`. The checkpoint arch is NOT placed at `race_start` permanently: an
  8.1 m clear opening between 2.6 m feet cannot sit on the 16 m Coral Ring without a foot in a lane or on a
  sidewalk; an activity should spawn it for the duration of a race (or place it off the road).
- **Vehicles**: anything in group `vehicle` that is a RigidBody3D is swept (uses `body_aabb` when present,
  otherwise a 1.8 x 1.2 x 4.4 m box) with the momentum rule above. Vehicles already pass impact damage to the
  breakable proxy (scaled by vehicle mass here).
- **Traffic AI** never sees the props (they stand off the carriageway); the light `PROP` colliders are in the
  vehicle masks, so a car that leaves the road meets them physically. `prp_traffic`: 18 AI cars for 60 s around
  Founders Plaza knock nothing over.
- **Pedestrians**: `PedSystem` seats NPCs on the props benches through `find_instances("bench" / "bench_park")`,
  `get_instance_transform` and `get_instance_state` (a knocked-over bench is not used).
- **Environment**: lamp lenses on the merged meshes get the lamp hook material automatically; pooled light
  points are registered through anchor nodes (ENVIRONMENT 4.2). The signal lens shader reads `gta_night`.
- **Cover**: walls, hedges, dumpsters, containers, barriers are real colliders (PLAYER cover detection uses
  `WORLD | VEHICLE | PROP`).

## 5. Tests

```powershell
tools\godot.ps1 -Mode headless -Frames 4700 -TimeoutSec 340 -UserArgs '--test=prp_api','--no_player','--disable=traffic,peds,police,wildlife,emergency,transit,taxi,activities,radio,ambience,shops,garage'
tools\godot.ps1 -Mode headless -Frames 6000 -TimeoutSec 450 -UserArgs '--test=prp_play','--disable=traffic,peds,police,wildlife,emergency,transit,taxi,activities,radio,ambience,shops,garage'
tools\godot.ps1 -Mode headless -Frames 400 -TimeoutSec 200 -UserArgs '--test=prp_boot','--no_player','--disable=traffic,peds,police,wildlife,emergency,transit,taxi,activities,radio,ambience,shops,garage'
tools\godot.ps1 -Mode headless -Frames 4200 -TimeoutSec 400 -UserArgs '--test=prp_traffic'
tools\godot.ps1 -Mode window -Frames 450 -TimeoutSec 200 -UserArgs '--test=prp_shots','--no_player','--disable=traffic,peds,police,wildlife,emergency,transit,taxi,activities,radio,ambience,garage','--prp_only=ladder,plaza,beach'
# window runs: keep each run to a subset (<= ~20 s) with '--prp_only=' (substring of the shot names)
```

`prp_api` (59 checks): counts per group, caps, setup budget, no solid prop on a carriageway / the runway,
walking strip, guard rails, `spawn_prop` / `get_prop_def`, ladder nodes (each on the rail line of its visible
ladder), set pieces present (sculpture, volleyball net, fountain, gazebo, lifeguard towers, cranes, wreck), a
20 m/s dummy body converts a lamp post (+ `prop_broken`), a real `sedan` at 15 m/s knocks a lamp over, a
player-driven dummy breaking two props reports exactly one `property_damage`, a 95 kg "bicycle" at 8 m/s
leaves a lamp post standing but knocks a speed sign over, four pistol-strength hits knock a sign over, a blast
pops a hydrant (+ water jet), a 4-drum chain reaction, every signal head's lit lens equals
`RoadGraph.get_signal_state` (3 samples), loose bodies appear near the focus and are released when it leaves,
the pooled night lights switch on, `set_enabled(false/true)` takes the dressing and its lights away and back,
a timed respawn waits while a vehicle stands on the spot, `respawn_all`.

`prp_play` (27 checks, real player, input through `Input.action_press`): climbs a 9.2 m building ladder (prompt,
interact, body 0.36 m behind the rungs, tops out on the roof) and a quay ladder out of the water; drives a
sedan into a lamp post (it topples, its night light anchor goes, one `property_damage`); rides a bicycle into
another lamp post (it stands); shoots a speed sign over with `Combat.fire_hitscan`; with `respawn_seconds`
shortened, the props stand again (lamp light back) once the player is far away.

`prp_boot`: setup time per placer phase, GLB load time, largest rigid hull, node count under `Props` (< 1500).
`prp_traffic`: every system running for 60 s, counts breakages by AI traffic (must be <= 2; measured 0).
The lead's `int_slice` still passes with the dressing in place (its car now stops at the city's tram stop,
not at dressing).

`prp_shots` -> `qa/screenshots/prp_*.png`: street day / midtown / night, signal close-up at night, signal head
from the driver's seat at night (`prp_signal_driver`), pedestrian signal showing WALK at night (`prp_ped_walk`),
hill wood (outside / inside), beach, docks, Foundry Yard, park, plaza, marina, airport, building ladder and the
top of the tallest building ladder (`prp_ladder_top`), hill-road guard rail, alley, hydrant before / broken. It
also logs whole-frame draw calls / objects / GPU time per shot (`TEST_LOG: FRAME ...`).

## 6. Known limits

- No roof AC units / extra rooftop dressing: the building kit already bakes `ac_unit`, `water_tank`, dishes,
  vents into the roofs (BUILDING_KIT.md); adding more would overlap them. No extra wall neon for the same
  reason (`Building_Neon` is part of the buildings).
- Fire-escape ladders only go on back walls without a cornice / overhang at the ladder line (mesh check);
  they may cross a window. The 2 lifeguard towers have no side ladder (their platform railing would block the
  top-out); the ramp is the way up.
- Fences round warehouses and the building ladders / alley clutter need `city.get_buildings()`; without the
  city system only house-yard hedges / fences / walls are placed.
- The water jet of a broken hydrant is a burst of pooled splash / steam effects at the base (no dedicated
  vertical jet effect in Fx).
- Visibility ranges are per MultiMesh cell, not per instance: a whole cell of small props appears / disappears
  together at the far end of its range.
- Kelp and buoys do not sway / bob (static MultiMesh entries).

## 7. Review fixes (independent review, 2026-11-10)

- Ladder group nodes stood 0.4 m out from the rail line; the player's ladder state hangs the body 0.36 m behind the
  node, so climbers floated 0.76 m off the rungs. The node now sits on the rail line (verified by `prp_play`).
- The lifeguard-tower side ladders could not be topped out (platform railing; seen in the player module's
  REAL_LADDER log): removed.
- Building ladders ran through cornices: the back wall is now read from the building mesh and cornice /
  overhang spots are skipped; the climb height is measured from the foot to the roof (`prp_ladder_top`).
- `park_statue` was never placed and `volleyball_net` was refused as "occupied" although both were documented:
  both now search for a free spot.
- A bicycle at 26 km/h toppled 9 m lamp posts: momentum rule in the vehicle sweep + mass-scaled bump damage.
- Convex hulls used the V-HACD path (~30 ms per asset; ~190 ms of boot for rocks, and a frame hitch on the
  first crash per prop type): plain hulls, all rigid hulls built at boot.
- Timed respawn was untested and could put a static collider inside a parked car: `respawn_seconds` + an
  occupancy query; both covered by tests. Smaller: pooled-body exception timer race, 30 Hz animation dt,
  packed junction boxes for `on_carriageway`.
