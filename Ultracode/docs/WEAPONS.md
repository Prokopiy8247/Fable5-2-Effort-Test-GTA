# Weapons, combat and pickups (WEAPONS module)

Owner: weapons programmer. Everything here is data driven: all balance numbers live in
`gta/resources/registries/weapons_registry.gd`, all behaviour in `gta/code/weapons/` and
`gta/code/combat/combat.gd`. Visual effects and sounds are only *called* (autoloads `Fx`, `Audio`);
the VFX and audio modules own them. Weapon / pickup models are Blender assets of the weapon artist
(`docs/WEAPON_ASSETS.md`); a missing GLB never gets a primitive stand-in, the weapon simply works
without a model.

| file | class | role |
|---|---|---|
| `gta/code/weapons/weapon_spec.gd` | `WeaponSpec` (Resource) | one weapon definition, Registry kind `weapons` |
| `gta/code/weapons/attachment_spec.gd` | `AttachmentSpec` (Resource) | one attachment / finish, Registry kind `attachments` |
| `gta/resources/registries/weapons_registry.gd` | registrar | the 17 weapons + 10 attachments (all numbers) |
| `gta/code/weapons/weapon_inventory.gd` | `WeaponInventory` (Node) | what a character carries + trigger logic |
| `gta/code/weapons/weapon_model.gd` | `WeaponModel` (Node3D) | GLB instance, markers, attachment meshes, finish, hand socket |
| `gta/code/combat/combat.gd` | `Combat` (static) | hitscan, melee sweep, projectiles, line of sight, `npc_fire` |
| `gta/code/weapons/projectile.gd` | `Projectile` (RigidBody3D) | grenade, rocket, launcher grenade, fire bottle |
| `gta/code/weapons/pickup.gd` | `Pickup` (Area3D) | one collectable (data + visuals) |
| `gta/code/weapons/pickup_system.gd` | `PickupSystem` | world system `pickups` |
| `gta/tests/wpn_core.gd`, `wpn_pickups.gd`, `wpn_player.gd`, `wpn_shots.gd`, `wpn_player_shots.gd` | tests | see "Tests" |

---------------------------------------------------------------------------------------------------

## 1. Data model

### WeaponSpec

Units: metres, seconds, **degrees** (spread = half-angle of the cone, recoil = kick per shot),
hit points (characters 100 hp, cars about 1000 hp).

| group | fields |
|---|---|
| identity | `id`, `display_name`, `description`, `slot` (one of `WeaponSpec.SLOTS`), `fire_mode` (`semi, auto, pump, bolt, melee, thrown, launcher`) |
| damage / cadence | `damage` (per pellet / melee hit / blast centre), `rpm`, `pellets`, `headshot_mult`, `limb_mult`, `vehicle_damage_mult`, `impulse` |
| ammunition | `mag_size` (0 = no magazine), `ammo_type`, `default_ammo` (rounds granted by `give_weapon(id, -1)`), `reload_time`, `equip_time` |
| spread | `spread_base`, `spread_moving` (added at full run), `spread_bloom` (added per shot), `spread_max` (cap of base + bloom), `spread_recovery` (deg/s), `spread_aim_mult` |
| recoil | `recoil_pitch`, `recoil_yaw`, `recoil_recovery` |
| range | `max_range`, `falloff_start`, `falloff_end`, `falloff_min`, `penetration` (> 0 passes glass, light props, colliders tagged `thin`; >= 0.4 also passes a body) |
| projectile | `projectile_kind` (`grenade, rocket, grenade_round, molotov`), `projectile_speed`, `blast_radius` |
| melee | `melee_range`, `melee_heavy_mult`, `melee_knockdown` (chance on a heavy hit / combo finisher), `melee_sound_hit` |
| presentation | `noise_radius`, `suppressed`, `weapon_pose` (`none, pistol, rifle, melee, rpg, throw` for the HumanoidAnimator), `aim_fov`, `scoped`, `scope_overlay_with_scope`, `drive_by`, `shake`, `tracer`, `sound_fire`, `sound_reload` |
| economy | `price`, `ammo_price` (one pack), `ammo_pack` (rounds per pack) |
| model / hand | `model_path`, `attachments` (compatible ids), `builtin_nodes` (always-visible `Att_*` meshes), `optic_strength`, `hide_mag_when_empty`, `hold_offset`, `hold_rotation` |

Helpers: `WeaponSpec.resolve(spec_or_id)`, `get_fire_interval()`, `falloff_at(distance)`,
`get_shot_damage()`, `get_dps()`, `get_sustained_dps()`, `get_time_to_kill(hp)`,
`get_shots_to_kill(hp)`, `is_melee() / is_thrown() / is_launcher() / is_hitscan() / is_firearm()`,
`uses_magazine()`, `get_slot_index()`, `with_attachments(ids)` (returns a modified copy).

Wheel slots (1..8): `melee, handgun, smg, shotgun, rifle, sniper, heavy, thrown`.

Ammo types and reserve caps (`WeaponSpec.AMMO_MAX`): pistol 240, smg 480, shotgun 96, rifle 480,
sniper 60, rocket 12, grenade_round 24, grenade 10, molotov 10. Weapons of one type share the pool
(pistol + heavy pistol, both shotguns, the three rifles). Thrown weapons have no magazine: the pool
*is* the count in hand.

### AttachmentSpec

One attachment per `kind` per weapon (a new finish replaces the old one). Stat effects are
multipliers applied by `AttachmentSpec.apply_to(spec)` onto a copy of the weapon spec; the mesh
named `node_name` inside the weapon GLB is shown while the attachment is installed.

| id | kind | price | mesh | gameplay effect |
|---|---|---|---|---|
| `suppressor` | suppressor | 450 | `Att_Suppressor` | noise radius x0.17 (65 m -> 11 m), `suppressed_shot` sound, noise kind `suppressed_gunshot`, no gunfire crime unless somebody is hit; damage x0.94, range x0.9, recoil x0.95 |
| `scope` | scope | 600 | `Att_Scope` | aim FOV x0.62 scaled by the weapon's `optic_strength`, aimed spread x0.8, draw time x1.1; on the marksman rifle it also turns the full scope overlay on |
| `flashlight` | flashlight | 200 | `Att_Flashlight` | `SpotLight3D` on the weapon (no shadows), toggled with the `weapon_flashlight` action, brighter while aiming |
| `grip` | grip | 380 | `Att_Grip` | recoil x0.75, bloom x0.8, moving spread x0.8 |
| `ext_mag` | ext_mag | 420 | `Att_ExtMag` (replaces `Mag`) | magazine x1.5 (at least +1), reload x1.1 |
| `finish_sand / olive / teal / coral / gold` | finish | 150 - 900 | - | tints every surface that uses `M_Weapon_Finish` (gold is also metallic); cosmetic |

Compatibility per weapon is the spec's `attachments` list (e.g. the heavy pistol takes scope and
flashlight only, the sniper rifle suppressor and extended magazine, launchers only what fits).
`AttachmentSpec.effect_text()` gives a short summary for shop UIs.

---------------------------------------------------------------------------------------------------

## 2. Balance table

Printed by `wpn_core` (lines starting with `BALANCE|`); DPS = torso hits, point blank, every shot
lands. "sustained" includes reloads. TTK = time to bring down 100 hp.

| id | name | slot | mode | damage | rpm | mag | reload s | DPS | sustained DPS | shots to kill | TTK 100 hp (s) | range m (falloff) | head x | noise m | price |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| fists | Fists | melee | melee | 14 (heavy x2.0) | 115 | - | - | 27 | 27 | 8 | 3.65 | 1.5 | - | 5 | 0 |
| knife | Dockside Knife | melee | melee | 36 (heavy x1.7) | 125 | - | - | 75 | 75 | 3 | 0.96 | 1.6 | - | 3 | 180 |
| bat | Ballpark Bat | melee | melee | 30 (heavy x1.9) | 85 | - | - | 43 | 43 | 4 | 2.12 | 2.0 | - | 7 | 240 |
| crowbar | Wrecking Bar | melee | melee | 34 (heavy x1.8) | 78 | - | - | 44 | 44 | 3 | 1.54 | 1.9 | - | 7 | 300 |
| pistol | Kestrel 9 | handgun | semi | 24 | 400 | 12 | 1.35 | 160 | 96 | 5 | 0.60 | 70 (18-50, x0.55) | 2.20 | 65 | 550 |
| heavy_pistol | Brimstone .50 | handgun | semi | 48 | 165 | 7 | 1.75 | 132 | 85 | 3 | 0.73 | 85 (25-65, x0.60) | 2.40 | 78 | 1450 |
| smg | Wasp Compact | smg | auto | 16 | 840 | 30 | 1.90 | 224 | 121 | 7 | 0.43 | 60 (14-42, x0.50) | 1.80 | 62 | 1900 |
| pump_shotgun | Harbor 12 Pump | shotgun | pump | 13.0 x 8 | 64 | 6 | 2.80 | 111 | 83 | 1 | 0.00 | 32 (7-24, x0.25) | 1.35 | 82 | 1600 |
| auto_shotgun | Riptide Auto 12 | shotgun | semi | 9.5 x 8 | 220 | 8 | 2.60 | 279 | 135 | 2 | 0.27 | 26 (6-20, x0.25) | 1.35 | 82 | 3300 |
| assault_rifle | Vanguard AR | rifle | auto | 28 | 580 | 30 | 2.30 | 271 | 158 | 4 | 0.31 | 130 (40-100, x0.65) | 2.00 | 82 | 3600 |
| carbine | Courier Carbine | rifle | auto | 21 | 720 | 25 | 1.95 | 252 | 133 | 5 | 0.33 | 100 (30-80, x0.60) | 2.00 | 76 | 2900 |
| marksman_rifle | Longview DMR | rifle | semi | 62 | 150 | 10 | 2.60 | 155 | 100 | 2 | 0.40 | 240 (90-200, x0.80) | 2.50 | 88 | 5200 |
| sniper_rifle | Pinnacle 700 | sniper | bolt | 135 | 42 | 5 | 3.30 | 95 | 75 | 1 | 0.00 | 450 (220-420, x0.85) | 3.00 | 95 | 7500 |
| grenade | Frag Grenade | thrown | thrown | 220 blast, r 7.0 m | 50 | - | - | - | - | 1 (in blast) | - | 17 m/s | - | 8 | 300 |
| rocket_launcher | Hammerhead RL | heavy | launcher | 480 blast, r 8.5 m | 30 | 1 | 3.0 | - | - | 1 (in blast) | - | 48 m/s | - | 95 | 9500 |
| grenade_launcher | Thumper GL | heavy | launcher | 230 blast, r 6.0 m | 75 | 6 | 3.6 | - | - | 1 (in blast) | - | 38 m/s | - | 70 | 7200 |
| molotov | Fire Bottle | thrown | thrown | 12 blast, r 3.0 m | 45 | - | - | - | - | 1 (in blast) | - | 15 m/s | - | 8 | 200 |

Design intent (why the numbers look like this):

- **Handguns**: the pistol is the forgiving all-rounder (fast follow-up shots, cheap, drive-by);
  the heavy pistol trades cadence and bloom for a three-shot kill and light penetration.
- **SMG**: best close-range DPS that can be used from a vehicle seat, but the widest cone and the
  earliest falloff (14 m).
- **Shotguns**: the pump is a one-shot kill inside 7 m and nearly useless beyond 24 m (x0.25);
  the semi-automatic one halves the wait and needs two shells.
- **Rifles**: assault rifle = damage and reach, carbine = handling (faster reload / draw, less
  recoil, tighter while moving), marksman rifle = two-shot kills out to 200 m, optional scope
  overlay.
- **Sniper**: one-shot body kill, scoped, pin-point only while aiming (hip spread 3.2 deg,
  aimed x0.012), slowest cycle.
- **Explosives**: grenade (cookable, 3.2 s fuse, bounces), rocket (fast, direct), launcher grenade
  (arc, arms after 4 m, dud + short fuse before that), fire bottle (area denial: 9 s pool, 24 hp/s).
- **Melee**: knife = fast and quiet, bat = reach + knock-down, crowbar = vehicles and glass
  (x2.5), fists = 3-hit combo whose finisher (x1.4) can knock down.
- Survivability knobs: NPC bullets against the player are scaled by `Combat.npc_damage_scale`
  (0.55) and head shots against the player never exceed x1.5 (`Combat.PLAYER_HEADSHOT_CAP`).
- Skills: `shooting` shortens reloads (x1.08 at 0 -> x0.8 at 100) and softens recoil
  (x1.1 -> x0.75); `strength` scales melee damage (x0.9 -> x1.35). Hits award XP.

---------------------------------------------------------------------------------------------------

## 3. Runtime API

### WeaponInventory (`Player/Inventory`)

Owner-agnostic and input-agnostic. The holder adds the node as a child named `Inventory` and calls
`setup(holder)` (the Player does this itself). The inventory only asks its holder for (all
optional, checked defensively): `get_aim_ray() -> {origin, direction}`, `add_recoil(pitch, yaw)`
(**degrees**, pitch > 0 = muzzle up), `get_target_position()`, members `visual`,
`current_vehicle`, `is_crouching`, `velocity`, and `play_weapon_action(name, duration)` (or
`animator.play_action`) for `reload, punch_l, punch_r, kick, heavy, throw, fire`.

```gdscript
# ownership / ammo
give_weapon(id, ammo := -1) -> bool        remove_weapon(id) -> bool        has_weapon(id) -> bool
get_weapons() -> Array                     get_slot_weapons(slot) -> Array  get_wheel_data() -> Array  # 8 x {slot, index, weapons, selected}
add_ammo(ammo_type_or_weapon_id, n) -> int get_ammo(id) -> {in_mag, reserve, mag_size, ammo_type}
get_reserve(ammo_type) -> int              is_ammo_full(type) -> bool       refill_all()
give_all_weapons()                         give_default_loadout()           clear(keep_ammo := false)
# selection
current_id: String                         get_current_spec() -> WeaponSpec get_spec(id) -> WeaponSpec  # attachments applied
equip(id) -> bool                          equip_slot(slot_index_or_name)   next_weapon() / prev_weapon()
holster() -> bool                          is_armed() -> bool               get_weapon_pose() -> String
can_use_in_vehicle(id) -> bool
# use
trigger_pressed() / trigger_released()     reload() -> bool                 set_aiming(on)
melee_attack(heavy: bool) -> bool          throw_grenade() -> bool          toggle_flashlight() / set_flashlight(on)
can_fire() -> bool                         is_busy() -> bool                is_cooking() -> bool
get_aim_fov() -> float                     is_scoped() -> bool              get_current_spread() -> float  # crosshair size, degrees
get_reload_progress() -> float             get_combo_step() -> int
# attachments
add_attachment(weapon_id, att_id) -> bool  remove_attachment(...)           has_attachment(...)
get_attachments(weapon_id) -> Array        get_compatible_attachments(id)   can_attach(weapon_id, att_id)
# persistence / lifecycle
get_save_data() -> Dictionary              load_save_data(d)                reset_for_respawn(keep_weapons := true)
# members
model: WeaponModel   is_aiming   is_reloading   trigger_held   flashlight_on   infinite_ammo (admin)
```

Node signals: `fired(weapon_id, result)`, `dry_fired`, `reload_started / reload_finished`,
`melee_started(weapon_id, heavy, combo_step)`, `melee_landed(weapon_id, hits)`, `throw_started`,
`thrown(weapon_id, projectile)`, `equipped`, `aiming_changed`, `recoil_kicked(pitch, yaw)`,
`changed`. For the player it also emits the EventBus signals `weapon_equipped`, `ammo_changed`,
`weapon_reload_started`, `weapon_inventory_changed` (`weapon_fired` and `hit_confirmed` come from
`Combat`).

Behaviour notes:

- **Trigger**: `semi / pump / bolt / launcher` fire once per press (a press up to 0.14 s early is
  buffered), `auto` fires while held, `melee` = light attack, `thrown` = hold to cook, release to
  throw (a grenade leaves the hand after 2.6 s at the latest). An empty magazine clicks
  (`dry_fire`) and reloads on its own when there is reserve ammo.
- **Spread** = `(base + bloom + moving * run_factor) * aim_mult * 0.8 if crouched * 1.6 in a
  vehicle`; bloom grows per shot and recovers after a short hold.
- **Recoil** climbs slightly over a burst (+5 % per shot, max +40 %), wanders left / right, is
  softer while aiming or crouched.
- **Aim solution** (third person): the point under the crosshair is found along the holder's aim
  ray, the bullet then leaves from the holder's head height towards that point, so cover between
  the camera and the character never eats the shot.
- **Melee**: 3-step combo inside a 0.55 s window (`punch_r, punch_l, kick` for fists), heavy
  attack = slower, `melee_heavy_mult`, up to two targets, knock-down chance +0.3. With a firearm
  in hand `melee_attack` is a weapon bash (18 damage).
- **Drive-by**: only `drive_by` weapons (pistol, heavy pistol, SMG, grenade, fire bottle) can be
  drawn or used in a seat. Entering a vehicle with anything else swaps to the best drive-by
  firearm that has ammo (or puts the weapon away) and restores the previous weapon on exit.
  Bullets ignore the shooter's own vehicle.
- **Default loadout** (holder in group `player`): fists + pistol with 48 rounds.
- **Save**: the player's inventory registers itself as SaveSystem provider `"weapons"`
  (weapons, magazines, attachments, ammo pools, drawn weapon; loading sanitises unknown ids).

### Combat (static)

```gdscript
Combat.fire_hitscan(origin, direction, spec_or_id, instigator := null, opts := {}) -> Dictionary
Combat.launch(spec_or_id, origin, direction, instigator := null, opts := {}) -> Node3D       # projectile weapons, with shot side effects
Combat.spawn_projectile(kind, origin, velocity, instigator := null, opts := {}) -> Node3D    # bare projectile
Combat.melee_sweep(attacker, origin, direction, reach, damage, opts := {}) -> Array
Combat.has_line_of_sight(from, to, exclude := []) -> bool                                    # Layers.SIGHT_MASK
Combat.raycast(from, to, mask := Layers.BULLET_MASK, exclude := []) -> Dictionary
Combat.npc_fire(npc, weapon_id, target_position, accuracy := 0.6) -> Dictionary              # one trigger pull for AI
Combat.ballistic_velocity(origin, target, speed, gravity := 9.8) -> Vector3
Combat.spread_direction(dir, spread_deg) -> Vector3
Combat.emit_noise(position, radius, kind, instigator := null)                                # rate limited
Combat.npc_damage_scale (static var, 0.55)    Combat.gunfire_reports (debug counter)
```

`fire_hitscan` does everything a shot causes, exactly once: one ray per pellet on
`Layers.BULLET_MASK` (shooter and shooter's vehicle excluded), sea surface (`Fx.splash`), damage
zones for humanoids (`Dmg.zone_for_humanoid`: head x `headshot_mult`, limb x `limb_mult`), range
falloff, vehicle multiplier, tyre hits (`pop_tire(index)` through the vehicle's wheel query API,
respecting bullet-resistant tyres), thin-surface penetration (max 2 per pellet), `Fx.impact` by
`Fx.surface_of(collider)`, up to 4 tracers, muzzle flash / shell eject on the given nodes, the
shot sound, camera shake for the player, `EventBus.weapon_fired`, `EventBus.noise_emitted`
(`gunshot` / `suppressed_gunshot` with the weapon's noise radius), the player's
`Wanted.report_crime("gunfire")` (at most once per 1.5 s; suppressed weapons only when a
character was hit) and `EventBus.hit_confirmed(target, info)` + shooting XP for player hits.
Damage is delivered as **one** `apply_damage(info)` per target and shot (pellets accumulated);
`info` follows the `Dmg` contract plus `collider`, `shape`, `distance`, `pellets`, `killed`.

Options: `spread_deg`, `pellets`, `max_range`, `damage_mult`, `exclude` (Nodes / RIDs), `muzzle`
(Vector3 for tracers and sound), `muzzle_node`, `eject_node`, `suppressed`, `no_fx`, `no_sound`,
`no_noise`, `no_crime`. Result: `{hit, position, normal, collider, target, damage, zone,
headshot, distance, killed, end, hits: [...]}`.

Opt-in metadata on colliders: `set_meta("surface", name)` (impact FX), `set_meta("thin", true)`
(penetrable), `set_meta("humanoid", true / false)` (zone damage on / off).

**AI usage**: `Combat.npc_fire(self, weapon_id, target.get_target_position(), accuracy)` once per
`WeaponSpec.resolve(id).get_fire_interval()`; the NPC keeps its own magazine count. Optional NPC
methods `get_muzzle_position()` / `get_muzzle_node()` improve tracers and flashes. To show the gun:
`var m := WeaponModel.create(weapon_id); m.attach_to_holder(npc)` (uses `npc.visual`).

### Projectile

| kind | flight | fuse / trigger | effect |
|---|---|---|---|
| `grenade` | real rigid body, bounces (0.38) | 3.2 s (shortened by cooking) | `Fx.explosion(220, r 7)` |
| `rocket` | swept ray, accelerates 48 -> 85 m/s, exhaust trail (`Fx.attach_trail(self, "rocket")`; `Fx.smoke_puff` if the Fx module has no trails) | contact; 6 s lifetime | `Fx.explosion(480, r 8.5)` |
| `grenade_round` | swept ballistic arc | impact after 4 m of travel; earlier = dud with a 2.2 s fuse | `Fx.explosion(230, r 6)` |
| `molotov` | swept ballistic arc | breaks on impact | `Fx.glass_shatter`, `Fx.spawn_fire` (9 s), `EventBus.fire_started`, 24 hp/s "fire" damage within 3 m: the Fx fire handle burns (the projectile sets its `radius`, `damage_per_second`, `instigator`, `weapon_id`); with an Fx whose fires do not burn the projectile ticks 12 hp every 0.5 s itself |

Models come from `weapons/<kind>.glb`. At most `Projectile.MAX_ACTIVE` (24) are alive; the oldest
goes off early. `Projectile.get_active_count()`, `Projectile.clear_all()`. Explosion damage,
impulse, noise and the "explosion" crime report are the job of `Fx.explosion` (called with
`{"weapon_id", "ignore": [projectile]}`); the thrower is not exempt from the own blast.

### WeaponModel

`WeaponModel.create(spec_or_id, installed_attachments := [])` instances the GLB and exposes
`muzzle`, `eject`, `grip_l`, `mag`, `light`; `set_attachments(ids)`, `set_finish(color)`,
`set_mag_loaded(bool)`, `set_light_on(on, energy_scale)`, `get_muzzle_position()`,
`get_support_hand_position()`, `attach_to_holder(holder) -> bool`, `has_model()`.
With a suppressor fitted `muzzle` is the `Muzzle_Suppressed` marker; the weapon light sits at the
`Flashlight` lens marker.

### Pickups (`Game.get_system("pickups")`)

```gdscript
spawn_pickup(kind, id, amount, position, opts := {}) -> Node3D           # one-shot / dropped (150 s lifetime, max 40)
spawn_world_pickup(kind, id, amount, position, respawn_time := -1.0)     # permanent, respawns
drop_from_npc(npc) -> Array                                              # cash by faction + 65 % the carried weapon; idempotent
collect(pickup, collector) -> bool        get_pickups() / get_pickup_count() / get_world_pickup_count()
clear_dropped()   clear_all()   respawn_all()   set_enabled(on)          signal pickup_collected(pickup, collector)
```

Kinds: `weapon` (id = weapon id, amount = rounds, <= 0 = default), `ammo` (id = ammo type or
weapon id), `health`, `armor` (points), `cash` (dollars; >= 400 shows the bag model), `parachute`,
`scuba`. Area3D on `Layers.PICKUP`, mask `PLAYER | VEHICLE`; touching it as the player (or in a
vehicle the player drives) collects it. Rules: an owned weapon gives its ammo; a new weapon is drawn
only when the hands are empty; nothing is wasted (full health / armor / ammo leaves the pickup and it
is taken as soon as it becomes useful). Feedback: `Audio.play("pickup_*")`, `Fx.pickup_sparkle`,
`UI.notify`. Models: weapon GLB for weapons, `props/pickups/<name>.glb` otherwise
(`ammo_box, medkit, armor_vest, cash_stack, cash_bag, parachute_pack, scuba_tank`), hovering,
spinning, with a kind-coloured ground halo (one `_process` for all pickups).

World placement in `setup()`: `Game.world.get_spawn_points("pickup_weapon" | "pickup_health" |
"pickup_armor" | "pickup_cash" | "parachute")`; weapons rotate through
`PickupSystem.WORLD_WEAPONS`; respawn times `PickupSystem.RESPAWN` (weapon 180 s, health 90 s,
armor 150 s, cash 240 s, parachute 45 s, scuba 60 s); scuba sets at `marina_dock` and `beach`. A
kind for which the world returns no point falls back to a few named locations
(`FALLBACK_LOCATIONS`). `EventBus.npc_died` drops loot automatically; NPC members read
defensively: `faction`, `weapon_id`, optional `cash_carried`.

---------------------------------------------------------------------------------------------------

## 4. Integration notes

- **Player**: creates the inventory itself and forwards input (`fire, aim, reload, weapon_next,
  weapon_prev, weapon_slot_1..8, throw_grenade, melee_heavy, holster`). The inventory handles
  `weapon_flashlight` on its own (`handle_flashlight_input`). `add_recoil` receives degrees.
- **Camera**: `inventory.get_aim_fov()` and `inventory.is_scoped()`.
- **HUD / weapon wheel**: EventBus `weapon_equipped`, `ammo_changed`, `weapon_reload_started`,
  `weapon_inventory_changed`, `hit_confirmed`; `get_wheel_data()`, `get_current_spread()` for the
  crosshair, `get_reload_progress()`. Melee weapons report `in_mag = reserve = -1` (hide counter).
- **Shops**: `spec.price`, `spec.ammo_price` for `spec.ammo_pack` rounds (`add_ammo(spec.ammo_type,
  spec.ammo_pack)`), `AttachmentSpec.price`, `get_compatible_attachments(id)`, `effect_text()`.
- **Vehicles**: bullets call `pop_tire(i)` using `get_wheel_count / get_wheel_position /
  get_wheel_radius`; the damage info carries `collider`, `shape` and `position` for glass.
- **Admin menu**: `give_all_weapons()`, `refill_all()`, `infinite_ammo`, `give_weapon`,
  `add_attachment`, `Projectile.clear_all()`, pickups `spawn_pickup / clear_dropped / respawn_all`.
- **Respawn**: `inventory.reset_for_respawn(keep_weapons)`.

---------------------------------------------------------------------------------------------------

## 5. How to add a weapon

1. Model: `gta/generated/models/weapons/<id>.glb` following `docs/ARCHITECTURE.md` 8.3 (origin at
   the right-hand grip, barrel along +Y in Blender = -Z in Godot, markers `Muzzle`, `Eject`,
   `Grip_L`, optional `Mag` and `Att_*` meshes, finish material `M_Weapon_Finish`).
2. Data: add one `_weapon("<id>", "<Name>", "<slot>", "<fire_mode>", "<description>", {...})` block
   in `weapons_registry.gd` (copy the closest existing weapon; `model_path` is derived from the id).
3. Order: append the id to `WeaponInventory.ORDER` (position inside its wheel slot); add it to
   `PickupSystem.WORLD_WEAPONS` if it should appear as a world pickup.
4. Sounds: `sound_fire` must be one of the audio module's ids (unknown ids are silent).
5. Run `wpn_core` (the balance table prints the new row) and `wpn_shots` (look at the PNGs).

A new attachment = one `_att(...)` line + its id in the `attachments` list of every compatible
weapon + an `Att_*` mesh in those GLBs when it is visible. New projectile kinds go into
`Projectile.KINDS` (and need a branch in `Projectile._on_swept_contact` if they are swept).

---------------------------------------------------------------------------------------------------

## 6. Hold-offset tuning (weapon in the hand)

`WeaponModel.attach_to_holder(holder)` parents the model under
`holder.visual.get_bone_attachment("Hand_R")` with the local transform

    canonical grip  *  per-weapon tuning

- **Canonical grip** = `HumanoidAnimator.get_grip_transform(skeleton, "Hand_R")` (static; the same
  frame the animator aims with: barrel along the hand, top of the weapon towards the thumb, grip
  7.5 cm in front of the wrist and 3 cm into the palm). If that function is missing, WeaponModel
  derives the same thing from the bone's rest pose (`WeaponModel.rest_basis`,
  `DEFAULT_GRIP_OFFSET`); the two paths are compared in `wpn_shots`.
- **Per-weapon tuning** = `WeaponSpec.hold_offset` (metres) and `WeaponSpec.hold_rotation`
  (degrees: pitch x, yaw y, roll z), both in the weapon's own frame: **x right, y up, -z along the
  barrel**. All 17 weapons currently use zero: the GLB origins already sit at the grip.
- **Global knobs** for integration: `WeaponModel.global_hold_offset` /
  `WeaponModel.global_hold_rotation` (static, added to every weapon).

How to tune: run `wpn_player_shots` and look at `qa/screenshots/wpn_player_side_*.png` (the real
player with the real animator), or `wpn_shots` for `wpn_shots_hand.png` / `wpn_shots_hand_side.png`
(T-pose and the animator's pistol / rifle / rpg / melee poses on a bare skeleton). Weapon
sits too far forward in the fist: raise `hold_offset.z`; too low in the palm: raise
`hold_offset.y`; barrel points up or down against the forearm: change `hold_rotation.x`; a rifle
that should cant across the chest: `hold_rotation.z`. Write the values into the weapon's block in
`weapons_registry.gd` (`"hold_offset": Vector3(...)`, `"hold_rotation": Vector3(...)`); a holder
without a `visual` (test dummies) gets the model at a fixed hip offset instead.

---------------------------------------------------------------------------------------------------

## 7. Tests

`$d` = `--disable=world,environment,city,interactions,vehicles,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug`

```powershell
tools\godot.ps1 -Mode check -Dirs 'gta/code/weapons,gta/code/combat,gta/resources/registries,gta/tests'
tools\godot.ps1 -Mode headless -Frames 5000 -UserArgs '--test=wpn_core','--no_player',$d
tools\godot.ps1 -Mode headless -Frames 2800 -UserArgs '--test=wpn_pickups','--no_player','--seed=7',$d
tools\godot.ps1 -Mode headless -Frames 4200 -UserArgs '--test=wpn_player','--seed=5','--disable=world,environment,city,interactions,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
tools\godot.ps1 -Mode window   -Frames 220  -UserArgs '--test=wpn_shots','--no_player',$d
tools\godot.ps1 -Mode window   -Frames 230  -UserArgs '--test=wpn_player_shots',$d
```

- `wpn_core` (dummy owner, dummy wall / humanoid / vehicle / glass): damage numbers, zones,
  pellets, falloff, penetration, tyres, ammo, reload, cadence of every fire mode, spread and
  recoil, every attachment, wheel selection, drive-by rule, save / load, melee combo + heavy +
  sweep, grenade arc / cook / fuse, rocket, launcher grenade arming, fire bottle, projectile cap,
  `npc_fire`, player-only signals, crime and noise reporting; prints the balance table.
- `wpn_pickups` (dummy body in group `player`): every pickup kind, "not wasted" rules, vehicle
  collection, respawn, lifetime, cap, NPC drops, world placement against a fake world (spawn
  points + named-location fallbacks).
- `wpn_player`: the **real** player scene and (when available) a real car: input actions ->
  shots / reload / wheel / scope / flashlight / quick throw / melee, camera kick, weapon model in
  the real hand socket, pickups on the real body, SaveSystem round trip, drive-by from the seat.
- `wpn_shots` (windowed, about 7 s): GLB data checks (markers, attachment meshes, finish material,
  sizes, barrel along -Z) and screenshots `qa/screenshots/wpn_shots_*.png` (the mannequin there is
  the raw humanoid GLB with every wardrobe part visible at once - it only carries the skeleton).
- `wpn_player_shots` (windowed, about 7 s): the real player aiming pistol / rifle / launcher and
  carrying the bat, through the gameplay camera and a side camera:
  `qa/screenshots/wpn_player_*.png`. This is the reference picture for hold-offset tuning.

---------------------------------------------------------------------------------------------------

## 8. Known limits

- Explosion damage, fire, muzzle flashes, tracers, decals and all sounds belong to the VFX and
  audio modules. The tests ran against the real `Fx` module (blast and burn damage verified);
  the audio manager was still the contract stub, so no weapon sound has been heard yet.
- Drive-by aiming uses whatever direction the camera rig reports; in the vehicle camera's default
  pitch the crosshair (and therefore the bullets) points at the road a few metres ahead.
- No Blender-authored reload / fire animation clips: the inventory only asks the animator for the
  procedural one-shot actions.
- Shell casings are an `Fx.shell_eject(node)` hook only; magazines are not dropped on reload.
- The left hand is not IK-locked to `Grip_L` by this module (`get_support_hand_position()` is
  there for the animator).
- Dropped pickups are not saved; world pickups reset on load.
