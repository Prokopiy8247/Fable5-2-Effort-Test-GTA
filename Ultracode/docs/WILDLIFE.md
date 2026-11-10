# Wildlife (Wave 3) — `wildlife` world system

Owner: wildlife programmer. Spec 29A (wildlife), 49 (performance), 50 (AI tiers). Assets: `docs/NATURE_ANIMALS.md`
(11 rigid-part animals, parts with joint origins, manifest `gta/generated/models/animals/manifest_animals.json`).

| File | Class | What it is |
|---|---|---|
| `gta/code/ai/wildlife_system.gd` | — (system `wildlife`) | population manager: habitats, spawning, caps, tiers, the one loop that drives every animal, noise dispatch, perches, pet-crime reports |
| `gta/code/ai/animal_body.gd` | `AnimalBody` | one land animal / bird / shark: CharacterBody3D, group `animal`, layer `Layers.NPC`, mask 0; damage, death, corpse |
| `gta/code/ai/animal_rig.gd` | `AnimalRig` | procedural part animation (gaits, head, tail, wings, fins, death pose) |
| `gta/code/ai/animal_land_ai.gd` | `AnimalLandAi` | brain of deer / boar / coyote / dog / cat / rabbit / cow |
| `gta/code/ai/animal_bird_ai.gd` | `AnimalBirdAi` | brain of seagull / pigeon (perch, walk, peck, take off, fly, glide, circle, land) |
| `gta/code/ai/animal_shark_ai.gd` | `AnimalSharkAi` | brain of the shark (patrol, circle, charge, bite, retreat, flee) |
| `gta/code/ai/animal_fish_school.gd` | `AnimalFishSchool` | a school of reef fish = one node + one `MultiMeshInstance3D` (one draw call) |
| `gta/code/ai/animal_assets.gd` | `AnimalAssets` | cached manifest / GLB scenes / merged vertex-coloured fish mesh |
| `gta/resources/registries/animals_registry.gd` | registrar | Registry kind `animals`: gameplay tuning per species (Dictionaries) |
| `gta/tests/wld3_api.gd`, `wld3_shots.gd` | tests | section 7 |

## 1. Population (habitats, regions, caps)

Habitats are built once at setup from WORLD data (soft dependency on `Game.world`, `city` for roofs):

| habitat | source | species (weights) |
|---|---|---|
| `hill` | `wildlife_land` points in district `hill` (24) | deer 3, rabbit 2.5, boar 2, coyote 1.2 |
| `wild` | other `wildlife_land` (lighthouse knoll, east dunes; 7) | rabbit 3, deer 1.2, coyote 1 |
| `park` | `wildlife_land` within 45 m of `residential_park` (4) | pigeon 2.5, dog 2, rabbit 1.2, cat 1 |
| `beach` | `wildlife_land` on sand in district `beach` (4) | seagull |
| `coast` | 73 generated perches: docks quay deck, marina promenade edge, pier decks, boardwalk, beach, lighthouse pad | seagull |
| `urban` | `WalkGraph.random_point` near the focus, by district: residential (dog 2, cat 2, pigeon 2), midtown (pigeon, cat), downtown (pigeons, only around the plaza), waterfront (pigeon, cat) | |
| `reef` | `wildlife_water` + `reef` points at least 3 m deep (178) | fish schools |
| `deep` | wreck basin south of the beach, deeper than 9 m (40) | shark (separate rare roll) |
| `pasture` | spawn kind `pasture` if the world ever adds one | cows — **the island has no pasture, so cows never spawn by themselves** (the species works: `spawn_animal("cow", …)`) |

- Spawning: one attempt every 0.5 s around the focus (player, or `set_focus_override`): habitat chosen by the number
  of its points inside its ring (land 38–125 m, birds 30–140 m, town 30–100 m, reef 18–90 m), species by weight ×
  day / night factor (coyotes ×3 at night, pigeons none at night, gulls ×0.45) × rain (birds ×0.35), skipping full
  species / category caps; points in view of the camera (frustum + line of sight, < 75 m) are rejected. Groups:
  deer 1–3, boar / rabbit / coyote 1–2 (coyotes ≥ 2 at night), pigeons 3–5, gulls 2–4 (45 % already flying),
  strays: 15 % of dogs (×3 at night).
- Shark: every 12 s, when the focus is within 140 m of the deep basin, 30 % (70 % while the player swims) — at most
  one, 60 s cooldown after it despawns.
- **Caps**: ≤ 16 animal nodes in total (a fish school counts as one), land ≤ 9, birds ≤ 7, water ≤ 4; per species
  (registry `cap`): deer 5, rabbit 4, boar 3, coyote 3, dog 3, cat 2, cow 3, seagull 6, pigeon 6, fish schools 3,
  shark 1. `set_density(mult)` scales the total (0–1).
- Despawn beyond 165 m (birds 180, water 130) unless `persistent`; corpses after their `corpse_time` (25–60 s) when
  out of view (or 25 s later anyway). Despawned bodies go back to a pool (prewarmed at setup: 4 per bird species,
  1–2 per land species), so spawning a flock in game does not instance GLBs.

## 2. Behaviour

**Land** (`AnimalLandAi`, states `idle, wander, graze, alert, flee, chase, bark, stalk, sit`):
- calm cycle idle ↔ graze (head down; boar / dog / coyote sniff) ↔ wander inside `wander_radius` of home. Wild
  animals only pick targets on natural ground (not asphalt / concrete / wood); town dogs and cats follow WalkGraph
  paths. Ground following through `Game.world.get_height()`, body pitched to the slope, never into the sea (dry-land
  and step-height test per step), obstacle rays at tier 0 (walls, trunks, props, vehicles; ground-like hits ignored).
- threats: the player inside `flee_radius` (sprinting ×1.6, crouched / stealth ×0.5, moving vehicle ×1.8, swimming
  ×0.4) — timid species first stop and look (`alert`) inside 1.6×; moving vehicles within 16 m heading their way;
  noises from `EventBus.noise_emitted` within `radius × hearing` (gunshots, explosions, screams, crashes, horns,
  sirens → flee; footsteps / melee → alert or flee) — so sneaking up on deer works.
- temperaments: `timid` (deer, rabbit, cat) flee; `docile` (cow) only moves away from loud things / close cars;
  `charger` (boar) charges when the player comes within 5 m (45 %) or when provoked: up to 3 passes through the
  target (gore = bite damage 14), then leaves; `predator` (coyote) flees by day, at night stalks (head low) and
  attacks a person on foot within 20 m (12 m when crouched), retreats after 3 bites or when hurt; `pet` (dog):
  60 % friendly (comes over, sits next to the player, wags), the others bark (backing off when the player is closer
  than 3 m), strays bite at night, provoked dogs bite (55 %, strays always). A target in a vehicle ends an attack
  (dogs bark at the car). Bites: `Dmg.make(bite_damage, "bite", animal, …)` through `Dmg.apply()` (coyote 9,
  dog 8, boar 14, cooldown 1.1–1.6 s) — the player respects `Game.invulnerable`.
- damage: hurt sound + flinch + blood, then flee or (aggressive species, healthy) attack the attacker.

**Birds** (`AnimalBirdAi`, states `perch, walk, takeoff, fly, circle, land`): stand / peck / look around / hop on
the ground, roof edges or props (a downward ray puts them on containers, benches, shelters); take off from the
player (pigeon 5 m, gull 7 m; ×2.4 for a moving car; birds on roofs only from 4 m), moving vehicles, loud noises,
damage — the whole flock follows within 0.05–0.45 s — or out of boredom (18–60 s, ×2.5 at night). Flight: banked
turns, flapping bursts and glides (gulls glide 70 %), climb / descend towards a cruise altitude that clears the
buildings under the path (building tops from `city.get_buildings()`), gulls circle over the coast for 14–34 s, then
fly to a coast perch or roof; pigeons fly to a pavement / park point or a roof edge (40 %) 14–65 m away; the flock
lands next to each other; final approach flares and settles exactly on the perch.

**Shark** (`AnimalSharkAi`): patrols waypoints in water deeper than 7 m around its home; a swimmer / diver within
46 m in water deeper than 3 m → circles (14 → 7 m; around surface swimmers it cruises at −0.45 m so the dorsal fin
cuts the surface) for 8–14 s → charges (7 m/s) → one bite of 34 hp (strong but survivable) → retreats 6–10 s →
circles again; after two bites it leaves the player alone for 50 s. Never enters water shallower than ~3.3 m,
always stays ≥ 0.4 m below the surface. Below 40 % health it flees.

**Fish schools** (`AnimalFishSchool`): 12–18 fish wander around their reef anchor 1–3.5 m above the seabed and
below the surface (−1 m); per-fish offsets breathe, headings wobble; a diver within 4.5 m or a shot / explosion
nearby makes the school burst away and spread; an explosion within ~12 m kills fish (belly up, they drift to the
surface and vanish after 20 s). Fish have no collider (bullets stop at the water anyway).

**Death**: tip over onto one side around the body centre (no ragdoll), legs stiff, collision off; vehicle strikes
and explosions throw the corpse ballistically first; birds in flight fall; the shark rolls belly up and drifts up.
`animal_died(animal, killer)` signal on the system.

**Crime**: killing / hurting animals is not a crime, except dogs and cats (`crime_victim`) harmed by the player when a
civilian (or an officer) within 40 m sees it (within 8 m always counts, else `npc.can_see_point`) →
`Wanted.report_crime("assault", pos, {"instigator": player, "victim": animal, "direct_police_witness": officer
saw it})`, at most once per animal per 3 s. The PedSystem then runs its normal witness flow.

**Sounds** (Audio ids of ARCHITECTURE 6.11, positional, rate-limited per species): `animal_deer` (alarm / hurt),
`animal_dog_bark` (dog barks, coyote calls at night, yelps), `animal_growl` (boar, coyote attacks, shark bite, cat
hiss pitched up), `animal_gull` (gull calls / alarm), `animal_bird` (pigeon coos / alarm).

## 3. Animation (`AnimalRig`)

Part rotations only (+ the `Visual` root for bob / pitch / roll), computed every frame at tier 0 and at 10 Hz at
tier 1: walk = 4-beat lateral sequence, trot = diagonal pairs, gallop = rotary sequence with body pitch rocking and
bound, rabbit = hop (front pair / hind pair, body arc); gait weights blend by speed and stride lengths come from the
registry (leg swing 22° walk → 44° gallop, body lowered by the rigid-leg height loss so the feet stay on the
ground); head nods at twice the stride frequency, grazes (manifest `graze_head_pitch_deg`) and chews, looks at the
threat / player, bites and barks; tail sways, flicks, lifts when fleeing, wags (dogs); sitting (dogs, cats). Birds:
wings fold into the manifest `folded` pose when perched, flap (Wing_R +z / Wing_L −z), glide with a dihedral, legs
tuck in flight, landing flare, pecking and pigeon head bob. Shark: tail beat about Y with speed, counter-sway,
pectoral fins, bite jerk, banking. Fish: vertex-shader tail wave (`gta_time`, per-fish phase / beat in
`INSTANCE_CUSTOM`).

## 4. API (`Game.get_system("wildlife")`)

```gdscript
set_enabled(on: bool)                  # admin toggle: off removes every non-persistent animal
get_count() -> int                     # animal nodes (living + corpses; a fish school = 1)
reset_for_respawn()                    # attackers (chase / stalk / bark / shark encounter) calm down
spawn_animal(id, pos, opts := {}) -> Node3D        # opts: yaw, persistent, home, state ("wander"|"graze"),
                                                   # habitat, stray (dog), flying / roof / flock (birds); "fish_small" -> a school
spawn_flock(id, pos, n, opts := {}) -> Array       # birds; opts.flying, opts.persistent
spawn_fish_school(pos, opts := {}) -> Node3D       # opts: count, radius, persistent
get_animals() -> Array; get_schools() -> Array; get_counts() -> Dictionary   # {total, land, bird, water, alive, dead, <species>: n}
clear_all(include_persistent := false); set_focus_override(pos); clear_focus_override(); get_focus()
set_density(mult); get_debug_info() -> Dictionary; get_habitat_points(name) -> PackedVector3Array; get_species_def(id)
signal animal_spawned(animal); signal animal_died(animal, killer)
var auto_spawn := true; var corpse_time_mult := 1.0; var roof_chance_override := -1.0   # test knobs
```
`AnimalBody` (duck-type it, group `animal`): `species, kind, category, temperament, health, max_health, is_dead,
persistent, sim_tier, home`; `apply_damage(info)`, `knock_down(impulse)`, `kill(cause)`, `get_target_position()`,
`attack(target: Node3D)`, `provoke(by)`, `flee_from(pos)`, `calm()`, `get_state_name()`; signals `died`, `damaged`.

## 5. Integration notes

- **Vehicles** already handle animals: `VehicleBase._sweep_ahead` strikes colliders in group `animal`
  (`Dmg.apply` + `knock_down`), `VehicleCrime.character_hit` ignores animals (no hit-and-run). Idle (sleeping)
  vehicles skip that sweep.
- **Weapons / Fx**: bullets, melee sweeps and explosions find the animal collider on `Layers.NPC` and call
  `apply_damage` (`get_target_position()` is the aim point). Explosions also reach animals through the noise event.
- **Debug / admin**: the admin toggle `Game.set_system_enabled("wildlife", on)` → `set_enabled`; the debug overlay
  counts group `animal` (bodies only). Fish schools are in group `animal_school` (kept out of `animal` because melee
  lock-on and vehicle code treat that group as bodies with colliders); `get_count()` includes them.
- **AI / peds**: animals are not NPCs (no `npc` group, no `npc_died`), PedSystem ignores them; pedestrians can bump
  into an animal body (they collide with layer NPC).
- **Respawn**: `reset_for_respawn()` is public; the respawn system calls it on every system that has it.

## 6. Performance (ARCHITECTURE 10, spec 49 / 50)

One manager loop, no per-animal `_process`. Tiers by distance to the focus: **0** < 45 m (movement + animation
every frame, think 8 Hz, obstacle rays 5 Hz), **1** < 110 m (movement every frame, think 2.5 Hz, animation 10 Hz),
**2** beyond (movement and think 1–2 Hz, visual hidden). An animal standing still makes no height queries; moving
ones 1 height + 1 depth query per frame and a slope sample at 20 Hz. Fish: one seabed query per school per frame,
one draw call per school. Visibility ranges: land 150 m, birds 125 m, shark 90 m, fish 75 m; small animals and birds
cast no shadows. Measured in `wld3_api` (headless, ~15 animals): wildlife physics loop ≈ 150–200 µs per frame on
average, animation ≈ 40–60 µs, spawning from the pool ≈ 0.1 ms (a fresh body ≈ 0.6 ms; setup with prewarm ≈ 0.1 s).

## 7. Tests

```powershell
tools\godot.ps1 -Mode headless -Frames 12000 -TimeoutSec 420 -UserArgs '--test=wld3_api','--test-timeout=400','--seed=7','--disable=traffic,police,emergency,shops,garage,transit,taxi,activities,radio,ambience,respawn'
tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 200 -UserArgs '--test=wld3_shots','--wld3_part=1','--test-timeout=150','--seed=5','--disable=traffic,peds,police,emergency,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups'
tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 200 -UserArgs '--test=wld3_shots','--wld3_part=2','--test-timeout=150','--seed=5','--disable=traffic,peds,police,emergency,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups'
```
`wld3_api` (≈ 70 checks): habitats, region-correct automatic spawning at the hill / in town / at the docks / at the
wreck, ground following, flee from a gunshot noise / the player / an approaching car, a car strike damages an
animal, coyote bites a dummy (Dmg type `bite`), coyote hunts the player at night, friendly dog sits and wags, other
dog barks, provoked boar charges, tier 2 hidden / tier 1 visible, fish stay under water and above the seabed,
scatter, explosion kills fish, gulls take off / fly / flap, pigeons land again and on roofs, shark circles → bites
(34 hp) → retreats and stays under water, damage → death → side pose → corpse despawn, deer kill is no crime, dog
harm reported only with a civilian witness and once per burst, caps under auto spawning in three regions, admin
toggle, `reset_for_respawn`, frame cost line `WLD_COST`.
`wld3_shots` → `qa/screenshots/wld3_deer_hill.png` (deer + rabbit in a hill clearing), `wld3_gulls_docks.png`,
`wld3_pets.png` (dog, cat, pigeons at a residential crossing), `wld3_fish_reef.png` (two schools at the reef by the
wreck), `wld3_shark.png` (underwater), `wld3_shark_fin.png` (shark circling under the surface, seen from above).

## 8. Known limits (honest)

- No pasture exists on the island, so cows never appear by themselves (the code path is ready for a `pasture`
  spawn kind).
- Animals avoid obstacles with rays only at tier 0; at tier 1 / 2 (45 m+) they may clip through a tree trunk or a
  prop. Wild animals can cross roads when fleeing.
- Bird flight clearance considers buildings only (not trees); a gull circling low over the wooded hill could pass
  through a crown (gulls stay on the coast in practice).
- Fish cannot be shot (bullets stop at the water surface, Combat behaviour) and have no colliders; only explosions
  kill them.
- Pedestrians collide with animal bodies (layer NPC) and their local avoidance does not know animals.
- All sounds are the synthesized ids of the audio module; nobody has listened to them in game (headless runs).
- Animals do not swim; deer stop at the waterline.
