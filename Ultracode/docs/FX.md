# FX — the `Fx` autoload (VFX, decals, tracers, fire, explosions)

Owner: VFX programmer. Files:

| file | what |
|---|---|
| `gta/code/combat/fx.gd` | the autoload: public API, pools, per-frame update, explosion / fire orchestration |
| `gta/code/combat/fx_assets.gd` | procedural meshes, sprites, decal images, curves, ramps, materials, process materials |
| `gta/code/combat/fx_blast.gd` | explosion damage + force resolution (shape query, falloff, line of sight, impulses) |
| `gta/code/combat/fx_handle.gd` | the handle node returned by `spawn_fire` / `attach_smoke` / `attach_trail` |
| `gta/code/combat/shaders/fx_mesh_lit.gdshader` | lit faceted mesh particle (smoke, dust, chips, debris, shells) |
| `gta/code/combat/shaders/fx_mesh_glow.gdshader` | unshaded emissive faceted mesh particle (fireball, flames, sparks) |
| `gta/code/combat/shaders/fx_glow_add.gdshader` | additive mesh glow (tracer streak, muzzle star) |
| `gta/code/combat/shaders/fx_sprite_add.gdshader` | soft additive billboard (explosion flash, muzzle glow) |
| `gta/code/combat/shaders/fx_ring.gdshader` | faceted expanding ring (shockwave, water ripple) |
| `gta/tests/fx_api.gd` | headless logic test (74 checks) |
| `gta/tests/fx_shots.gd` | windowed screenshot stage (`qa/screenshots/fx_shots_*.png`) |

Nothing is loaded from disk except the five shaders: every mesh, texture, decal image and
material is generated in code (`gta/generated/vfx/` stays empty on purpose — the decal images are
built at runtime, ~25 k pixels in total, at `EventBus.game_ready` or on first use).

## Style

"Sunlit Low-Poly": effects are made of **chunky faceted mesh particles** — lumpy 80-facet blobs for
smoke / dust / fire, irregular chips, shards, splinters, streak-shaped sparks, diamond flames. They
pop in fast and **shrink out** (scale curves) instead of fading, so they stay in the opaque pass:
no alpha fog, no sorting, no overdraw. Smoke and dust are lit by the real scene lights (dark at
night, warm next to a fire); fire and sparks are unshaded with a fake facet term so the facets stay
readable. Soft sprites are used only for the explosion flash and the muzzle glow (a procedural
radial `GradientTexture2D`). Rings (shockwave, water ripple) are 14-gons drawn by a shader.

## Public API

Contract methods (frozen names / signatures):

| method | effect |
|---|---|
| `surface_of(collider) -> String` | meta `"surface"` on the collider or an ancestor (aliases such as `road`, `stone`, `leaves` are normalised), group `vehicle` → `metal`, `npc` / `player` / `animal` → `flesh`, group `water_surface` → `water`, a body on `Layers.GLASS` only → `glass`, else `concrete`; `null` is safe |
| `impact(position, normal, surface, scale)` | per-surface burst + sound (+ bullet decal on concrete / asphalt / wood), see table below |
| `muzzle_flash(at, scale)` | faceted star + glow that follow the Muzzle marker for 55 ms (marker −Z = firing direction), pooled light |
| `tracer(from, to)` | additive streak travelling at 300 m/s |
| `shell_eject(at)` | brass casing hopping out along the Eject marker's +X |
| `explosion(position, radius, damage, instigator, opts)` | visuals, sound, damage, force, shake, noise, crime, scorch, optional fire — see "Explosions" |
| `spawn_fire(position, duration, parent, scale) -> Node3D` | burning fire (flames + smoke + flicker light + damage); returns the fire handle |
| `smoke_puff(position, kind, scale)` | one puff: `light`, `heavy`, `black`, `steam` |
| `sparks(position, normal, amount)` | spark burst (collisions, scraping) |
| `dust(position, scale)` | dust puff (landing, tyres on dirt); rate limited |
| `splash(position, scale)` | droplets + foam + ripple + `splash_small` / `splash_large` / `impact_water` |
| `tire_smoke(position, amount)` | tyre smoke puff; rate limited (14 puffs/s over all callers) |
| `glass_shatter(position, normal, scale)` | shards only — **no sound** (both existing callers play `glass_break` themselves) |
| `blood(position, direction)` | small stylised red puff + a few drops, 40 % chance of a splat decal below |
| `decal(position, normal, kind, size)` | pooled decal: `bullet`, `scorch`, `blood`, `skid`, `oil`; random roll |
| `money_burst(position)` | bank notes + gold sparkle |
| `pickup_sparkle(position, color)` | rising sparkle in the pickup colour |
| `shake_camera(amount, position, radius)` | emits `camera_shake_requested(amount * Settings.camera_shake)`, distance falloff to the player |

Additions:

| method | effect |
|---|---|
| `attach_smoke(parent, kind) -> Node3D` | looping smoke for a damaged vehicle: `light` / `heavy` / `black`. Returns a handle parented to `parent` at its origin: set `handle.position` (engine), `queue_free()` it to stop. `null` if the parent is not in the tree |
| `attach_trail(parent, kind) -> Node3D` | looping trail: `rocket`, `tyre` (alias `tire`), `wake`, `dust`, `exhaust`. Same handle rules; `handle.set_strength(0..1)` scales the emission live (tyre slip, boat speed) |
| `rotor_wash(position, strength)` | ring of dust (white spray over water) on the ground under a helicopter; call it repeatedly, it is rate limited |
| `water_ring(position, scale)` | expanding faceted ripple |
| `set_quality(level)` | 0 low (55 % particles, 24 decals, no Fx lights, 70 m range), 1 medium (80 %, 48 decals, 110 m), 2 high (default; 64 decals, 160 m, muzzle light). Read from `Settings` key `fx_quality` at boot if that key exists |
| `decal_oriented(position, normal, forward, kind, size, length, parent)` | decal with an explicit length axis (skid marks) and an optional parent (pins the decal to a moving body) |
| `clear_decals()` | hides every decal |
| `get_stats() -> Dictionary` | `active_systems`, `live_particles` (upper bound), `decals_visible`, `fires`, `handles`, lights, … |
| `explosion_falloff(dist, radius) -> float` | the damage curve used by explosions |

Constants that are safe to read: `SURFACES`, `SMOKE_KINDS`, `TRAIL_KINDS`, `DECAL_KINDS`,
`MAX_ACTIVE_SYSTEMS`, `MAX_DECALS`, `MAX_FIRES`, `MAX_LIT_FIRES`, `MAX_EXPLOSION_LIGHTS`.

Every method is safe in `--headless`, before `Game.is_ready`, with `null` / freed / out-of-tree
nodes, with unknown kinds and when pools are exhausted. Effects further than the quality range
from the **active camera** are skipped (explosions: 400 m), so a test needs a camera near its stage.

### Impacts per surface

| surface | particles | sound | decal |
|---|---|---|---|
| concrete / asphalt | dust puff + stone chips | `impact_concrete` | bullet hole |
| metal | sparks + small grey puff | `impact_metal` (+ `ricochet` 20 %) | none — metal is mostly vehicles; use `decal_oriented(..., parent)` to pin one |
| glass | glinting shards | `impact_glass` | none |
| wood | splinters + tan puff | `impact_wood` | bullet hole |
| dirt | brown puff + clods | `impact_dirt` | none |
| grass | puff + green blades | `impact_dirt` | none |
| sand | big pale puff + grains | `impact_dirt` | none |
| water | droplets + ripple | `impact_water` | none |
| flesh | small red puff | `impact_flesh` | none (`blood()` may leave a splat) |
| rubber | dark puff + bits | `impact_dirt` (low) | none |
| foliage | leaves + small puff | `impact_dirt` (high) | none |

At most 8 impacts per frame get particles (shotgun volleys), impact sounds are limited to one per
35 ms.

### Handles (`fx_handle.gd`)

`spawn_fire`, `attach_smoke` and `attach_trail` return a small `Node3D` the **caller owns**.
The pooled emitters are not its children — they follow it every frame — so `queue_free()` on the
handle, or freeing the vehicle it is parented to, never destroys pool nodes; Fx gets the slot back
through `NOTIFICATION_EXIT_TREE` (taking the handle out of the tree also ends the effect).
Fields a caller may set right after spawning a fire:

```gdscript
var fire := Fx.spawn_fire(pos, 9.0, null, 1.6)
if fire != null:
    fire.instigator = thrower            # who is blamed for burn damage (default null)
    fire.weapon_id = "molotov"
    fire.radius = 3.0                    # default 0.9 + 0.9 * scale
    fire.damage_per_second = 24.0        # characters / props (default 20)
    fire.vehicle_damage_per_second = 30.0
    fire.ignore.append(some_node)        # damageables that never burn in it
```
`fire.deals_damage` is `true` (also as meta `deals_damage`), so callers must not run their own
burn loop next to it. Damage is applied every 0.5 s (type `"fire"`, through the Dmg contract) to
every damageable inside the radius on `PLAYER | NPC | VEHICLE | PROP`; a fire that is parented to
something never burns that thing's own damageable owner (a burning car does not shorten its own
fuse, but it does burn bystanders and neighbouring cars — vehicles decide themselves when they
catch fire). `duration <= 0` burns until the handle is freed. At most 6 fires exist (the oldest is
put out); up to 3 of them carry a flickering `OmniLight3D` and a crackle loop.

## Explosions

`Fx.explosion(position, radius = 6, damage = 160, instigator = null, opts = {})`

1. **Visuals** (`visual_scale` default `radius / 6`, clamped 0.4 – 2.2): flash sprite, 16 emissive
   fireball blobs, 14 dark smoke blobs that rise as a column, 16 sparks, 10 debris chunks, a
   10-puff dust ring on the ground, a shockwave ring that expands to exactly the damage `radius`,
   and a pooled light (max 2). Over water: splash instead of debris / dust / scorch / fire.
2. **Sound**: `explosion_large` (radius ≥ 4.5 m) or `explosion_small`, audible to 300 m.
3. **Damage** (`fx_blast.gd`): one sphere `PhysicsShapeQueryParameters3D` over
   `PLAYER | NPC | VEHICLE | PROP | RAGDOLL | GLASS`; **one** `apply_damage` per damageable owner
   (`Dmg.find_damageable`, de-duplicated over all of its colliders). Distance is measured to the
   closest point of the owner's shapes (vehicles: their `body_aabb`). Falloff: full damage inside
   the inner 15 % of the radius, then `t * (0.5 + 0.5 t)` (linear blended into quadratic), 0 at
   the radius. A ray on `Layers.WORLD` towards the target (chest via `get_target_position()`,
   vehicle centre via `get_center_position()`) multiplies damage and push by 0.25 when blocked.
   The info is `Dmg.make(amount, "explosion", instigator, closest_point, direction, {...})` with
   `impulse` 140 – 650 (scaled by falloff), `direction` away from the blast with an upward bias,
   `weapon_id`, `radius`, `falloff` and `knockdown` — characters use `impulse` / `direction` for
   their own knock-down / ragdoll; the player's own code respects `Game.invulnerable`.
4. **Force**: radial `apply_impulse` on every `RigidBody3D` / `PhysicalBone3D` in the sphere
   (frozen bodies are skipped): Δv ≈ 11 m/s × falloff for light props, less for heavy bodies
   (`mass / (1 + mass / 350)`), scaled with `damage / 160`.
5. `EventBus.explosion(position, radius, instigator)`,
   `EventBus.noise_emitted(position, 120, "explosion", instigator)`, and
   `Wanted.report_crime("explosion", position, {"instigator": ...})` when
   `Dmg.caused_by_player` says so.
6. Camera shake by distance (`shake_camera`), scorch decal on the ground below, optional fire.

`opts`: `visual_scale: float`, `no_damage: bool` (cosmetic: no blast, no crime), `fire: bool`
(6 s ground fire blamed on the instigator), `ignore: Array[Node]` (never damaged or pushed, their
children included), `weapon_id: String`, `los: bool` (default true), `force: float` (impulse
multiplier), `no_crime: bool`, `no_scorch: bool`, `silent: bool`.

An explosion requested **from inside another blast's `apply_damage`** (explosive barrels, chain
reactions) is queued and goes off on a following physics frame, one per frame (max 16 queued):
no recursion, and chain reactions are staggered.

## Pools and budgets

Everything is created once in `Fx._ready()` (≈ 230 nodes under `Fx/FxPool`) and recycled round
robin; nothing is allocated per shot. The only runtime allocations are the handle nodes (one small
`Node3D` per fire / attached smoke / trail).

| pool | nodes | particles each | lifetime | used by |
|---|---|---|---|---|
| burst `puff` | 12 | 6 | 0.8 s | impact dust, blood, splash foam |
| burst `smoke` | 14 | 5 | 1.1 s | `smoke_puff`, `tire_smoke`, `dust` |
| burst `chips` | 10 | 8 | 0.75 s | chips, shards, splinters, bank notes |
| burst `sparks` | 8 | 16 | 0.55 s | metal impacts, `sparks`, explosions |
| burst `droplets` | 6 | 16 | 0.9 s | splashes |
| burst `fireball` | 4 | 16 | 0.85 s | explosions |
| burst `blast_smoke` | 4 | 14 | 2.6 s | explosions |
| burst `debris` | 4 | 10 | 1.4 s | explosions, big glass |
| burst `dust_ring` | 4 | 10 | 1.0 s | explosions, `rotor_wash` |
| burst `sparkle` | 4 | 8 | 0.8 s | pickups, money |
| loop `flames` | 6 | 24 | 0.65 s | fires |
| loop `fire_smoke` | 6 | 10 | 1.7 s | fires |
| loop `smoke` | 8 | 20 | 2.0 s | `attach_smoke` (light / heavy / black) |
| loop `rocket` | 3 | 30 | 0.9 s | `attach_trail("rocket")` |
| loop `puffs` | 6 | 12 | 1.0 s | `attach_trail` tyre / dust / exhaust |
| loop `wake` | 3 | 20 | 1.5 s | `attach_trail("wake")` |

102 `GPUParticles3D` nodes exist, but **at most 48 are active at once** (`MAX_ACTIVE_SYSTEMS`):
before a system starts, the oldest running burst is cut if the cap is reached (loops are never
cut for a burst). A looping pool that is exhausted hands the emitter of its oldest handle to the
new one (the old handle simply stops emitting). Other pools: 64 decals, 4 explosion slots (flash
quad + ring quad), 2 explosion lights, 3 fire lights, 3 looping `fire_loop` players (created at
the first fire), 1 muzzle light, 6 muzzle flashes (star +
glow), 12 tracers, 12 shell casings, 6 water rings. Lights never cast shadows and have a distance
fade (80 – 105 m), so Fx adds at most 6 positional lights to the 16-light budget.

Measured by `fx_api` (upper bounds from `get_stats()`):

| case | live particles | systems |
|---|---|---|
| one explosion with `fire: true` | 100 (66 without fire; budget ≈ 150) | 7 |
| steady gunfight, 10 shots/s with flash + shell + tracer + impact | ≈ 100 (budget ≈ 300) | ≈ 19 |
| everything spammed every frame for 1 s | — | 48 (cap) |

## GPU cost notes

- All particles are **opaque meshes** of 20 – 80 triangles: an explosion is < 6 k triangles and
  zero transparent overdraw; the only blended surfaces are the flash / glow quads, the ring quads,
  tracers and the muzzle star (a handful of small additive quads for a few frames).
- No particle collision, no trails, no sub-emitters, no turbulence; `fixed_fps = 0`; shadows off
  on every Fx node; generous but finite visibility AABBs (5 – 20 m).
- Decals: 64 max, 64 – 96 px textures with mipmaps, distance fade 45 – 57 m, thin projection boxes
  (bullets 0.22 m) with a normal fade so holes do not smear around corners.
- Materials are cached by (shader, tint, parameters): typically 25 – 40 `ShaderMaterial`s, hard
  cap 96. Per-effect size goes through the instance uniform `size_mul`, so sizes never create
  materials.
- Per frame on the CPU: nothing while idle; otherwise a few short loops over the transient pools
  (≤ 12 entries each) and the handles.

## How to add an effect

1. **Reuse a burst pool** if the motion fits: call
   `_emit(&"<pool>", position, basis, mesh, material, ratio, size)` — the basis orients the burst
   (+Y = main direction, use `_basis_up(normal, s)`) and its scale multiplies emission radius and
   velocity; `ratio` (0 – 1) thins the particle count; `size` multiplies the particle size
   (default: the basis scale). Pick the look with `_assets.lit(tint)` / `_assets.glow(tint, …)`
   and one of the meshes in `fx_assets.gd` (`blob`, `pebble`, `chunk`, `shard`, `splinter`,
   `spark`, `flame`, `bill`).
2. **New motion** → one line in `_build_bursts()`:
   `_add_burst(&"name", pool_size, amount, lifetime, reach, _assets.proc({...}))` (see
   `FxAssets.proc` for the compact keys). Keep `amount` ≤ 32 and the pool small.
3. **New looping look** → `_add_loop("id", pool, ratio, mesh, material, size, offset)` in
   `_build_loops()` and route a kind to it in `attach_smoke` / `attach_trail`. A different motion
   needs its own `_add_loop_pool(...)`.
4. Add the public method to `fx.gd` (start with `if not _built: _build()` and a `_too_far` check),
   document it here, and add a call to `gta/tests/fx_api.gd` (`_test_pools`) and, if it is
   visible, a station to `gta/tests/fx_shots.gd`.

Gotchas (learned the hard way):

- **Never change `process_material` on a pooled `GPUParticles3D`** — the renderer prints
  `Parameter "uniform_set" is null` for the next frame. That is why loops are split into
  fixed-material pools.
- `ParticleProcessMaterial` rebuilds the particle basis every frame: the emitter's node scale
  scales emission and velocity but **not** particle size → use `size_mul`.
- Colours that reach the draw shader from ramp textures are raw sRGB numbers → the mesh shaders
  decode them (`pow(COLOR, 2.2)`); tints are `source_color` uniforms.
- Decals blend in linear space: a dark stain needs alpha ≈ 0.98, otherwise it turns grey.
- `x as T` on a freed object is an error in Godot 4: check `is_instance_valid()` on the Variant
  first (handles notify Fx on exit, so the lists stay clean, but the guards are there).

## Tests

```powershell
# logic (74 checks): surfaces, safe arguments, explosion damage / LOS / force / chain, fire damage
# over time, pool exhaustion, no node growth, particle budgets
tools\godot.ps1 -Mode headless -Frames 2600 -UserArgs '--test=fx_api','--no_player','--disable=world,environment,city,interactions,vehicles,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'

# pictures: qa/screenshots/fx_shots_{decals,impacts,impacts_marks,muzzle,smoke,splash,explosion_1,explosion_2,explosion_3,fire_night}.png
tools\godot.ps1 -Mode window -Frames 640 -UserArgs '--test=fx_shots','--no_player','--disable=world,environment,city,interactions,vehicles,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
# one station only: add '--flag=fx_only_explosion' (decals, impacts, muzzle, smoke, splash, explosion, fire)
```

## Integration notes

- **Weapons**: `Combat.fire_hitscan` already calls `impact`, `tracer`, `muzzle_flash`,
  `shell_eject`, `splash`. Molotov: use the fire handle fields above instead of a private burn
  loop. Rockets: `Fx.attach_trail(rocket, "rocket")` gives a denser trail than repeated
  `smoke_puff` calls (and costs one emitter instead of ~20).
- **Vehicles**: `attach_smoke(vehicle, kind)` + `handle.position = <engine, local>` replaces timed
  `smoke_puff` calls; `attach_trail(wheel_or_marker, "tyre")` with `set_strength(slip)` for
  burnouts, `"wake"` on the boat's `Wake_L/R` markers, `rotor_wash(ground_point, strength)` under
  helicopters, `decal_oriented(pos, normal, velocity_dir, "skid", width, length)` for skid marks
  and `decal(pos, normal, "oil", 1.0)` under wrecks. A vehicle's explosion that also spawns its
  own wreck fire does not need `opts.fire`.
- **Player camera**: keep listening to `Fx.camera_shake_requested(amount)`.
- **Audio ids used**: `impact_concrete`, `impact_metal`, `impact_glass`, `impact_flesh`,
  `impact_wood`, `impact_dirt`, `impact_water`, `ricochet`, `explosion_small`, `explosion_large`,
  `splash_small`, `splash_large`, `fire_loop` (3 pooled loop players from `Audio.make_loop_player`).
  Missing files are silent.
- **Environment**: Fx writes no global shader uniforms and adds no shadowed lights.
