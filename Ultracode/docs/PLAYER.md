# PLAYER module — player controller, gameplay camera, humanoid animator, ragdoll, respawn

Owner: player programmers. Contract: `docs/ARCHITECTURE.md` §6.3 (animator, ragdoll) and §6.4
(player, camera), `docs/ARCHITECTURE_WAVE2.md` W2.1 (carjacking), W2.4 (ladders, cover without
markers), W2.5 (death / arrest); spec §10A (cover, stealth, takedowns), §17A (suppressors), §46A
(Stealth skill). Everything here is plain GDScript, no scenes to edit by hand, and every neighbour (world,
city, UI, vehicles, weapons, police / Wanted, audio, FX, skills, save) is a soft dependency.

| File | Class | What it is |
|---|---|---|
| `gta/code/player/player.gd` | `Player` | CharacterBody3D, health / armor / stamina / breath, state machine host |
| `gta/code/player/states/player_state.gd` | `PlayerState` | base class of a state (+ `modify_damage` hook) |
| `gta/code/player/states/player_state_on_foot.gd` | `PlayerStateOnFoot` | idle / walk / run / sprint / crouch / sneak / aim-strafe, context jump, staggers; **hookable base of ground states** |
| `gta/code/player/states/player_state_melee.gd` | `PlayerStateMelee` | melee stance (extends on_foot): combo, heavy, block, lock-on, finisher |
| `gta/code/player/states/player_state_roll.gd` | `PlayerStateRoll` | combat roll (aiming) and melee dodge step |
| `gta/code/player/states/player_state_vault.gd` | `PlayerStateVault` | vault over low obstacles, mantle onto ledges (+ the probe) |
| `gta/code/player/states/player_state_ladder.gd` | `PlayerStateLadder` | ladder climbing (W2.4) |
| `gta/code/player/states/player_state_air.gd` | `PlayerStateAir` | jump, fall, landing, fall damage, ledge grab from a jump |
| `gta/code/player/states/player_state_swim.gd` | `PlayerStateSwim` | surface swimming, diving, breath, drowning, harbour ladders |
| `gta/code/player/states/player_state_vehicle.gd` | `PlayerStateVehicle` | approach → (jack) → enter → seated (drive-by) → exit / bail / eject |
| `gta/code/player/states/player_state_ragdoll.gd` | `PlayerStateRagdoll` | knocked down, then gets up |
| `gta/code/player/states/player_state_dead.gd` | `PlayerStateDead` | death ragdoll + built-in fallback respawn |
| `gta/code/player/states/player_state_busted.gd` | `PlayerStateBusted` | arrested: hands up, no control |
| `gta/code/player/states/player_state_cover.gd` | `PlayerStateCover` | cover (extends on_foot): glide, move along, edges, peek / rise, blind fire, corner swing, leave (§12) |
| `gta/code/player/states/player_state_takedown.gd` | `PlayerStateTakedown` | silent stealth takedown from behind (§13) + the shared takedown rules |
| `gta/code/player/player_cover.gd` | *(none, preloaded)* | geometric cover probe: faces, low / high class, edges, outside corners |
| `gta/code/player/player_stealth.gd` | *(none, preloaded)* | child "Stealth": visibility_factor, takedown target scan, Stealth XP, loud gunfire ends stealth |
| `gta/code/player/player_vehicle_interaction.gd` | *(none, preloaded)* | tap / hold entry, carjacking, theft reports, drive-by arcs |
| `gta/code/player/respawn_system.gd` | *(system "respawn")* | death / arrest flows, out-of-world rescue |
| `gta/code/player/player_camera.gd` | `PlayerCamera` | camera rig, registered as `Game.camera_rig` |
| `gta/code/player/player_interaction.gd` | `PlayerInteraction` | Interactable / ladder / vehicle prompts, action key |
| `gta/code/characters/humanoid_animator.gd` | `HumanoidAnimator` | procedural animation for player AND every NPC |
| `gta/code/characters/ragdoll.gd` | `Ragdoll` | rigid-segment ragdoll helper |
| `gta/scenes/characters/player.tscn` | | Player + CollisionShape3D + CameraRig/Camera3D |

Scene tree at run time: `Player` → `CollisionShape3D`, `CameraRig` (top-level) → `Camera3D`,
`Visual` (humanoid.tscn, `CharacterVisual`), `Animator`, `States/*`, `VehicleSensor` (Area3D),
`Interaction`, `VehicleInteraction`, `Stealth`, `Inventory` (WeaponInventory, only when
`gta/code/weapons/weapon_inventory.gd` exists).

---------------------------------------------------------------------------------------------------

## 1. Controls (input actions from `InputSetup`)

| Action | Key | Effect |
|---|---|---|
| `move_*` | WASD / left stick | camera-relative movement; a partly tilted stick walks. On a ladder: forward = up, back = down |
| *(raw)* Left Alt | hold | walk (keyboard). Used only until InputSetup has a `walk` action (see requests) |
| `sprint` | Shift | sprint while stamina lasts; fast swim; faster ladder climb |
| `jump` | Space | **context**: climb a ladder in front → vault (≤ 1.1 m) / mantle (≤ 2.0 m) an obstacle in front → dodge roll while aiming + direction → dodge step in the melee guard + direction → jump. Swim up; push off a ladder. In cover: vault / mantle over the cover (or swing round the corner at an edge with the stick towards it) |
| `crouch` | C | crouch toggle; dive / swim down; slide down a ladder (hold) |
| `stealth` | Ctrl | stealth toggle (sneak: quiet, slower, harder to see, takedowns from behind); also in cover |
| `cover` | Q | take cover at the wall / barrier / low object / vehicle in front (stick, else camera direction, glide up to 3 m); in cover: leave, or at an edge with the stick towards it: swing round an outside corner |
| `aim` | RMB | shoulder aim + strafe; with fists / a melee weapon = **block** (melee stance); in a vehicle = **drive-by** free aim; in cover = **rise over** low cover / **lean out** past a nearby corner of high cover |
| `fire` | LMB | weapon; with fists / a melee weapon = light strike (combo) or **finisher** next to a downed target, or a **stealth takedown** behind an unaware NPC while sneaking; in a vehicle = drive-by (thrown weapon without aim = drop out of the window); in cover without aim = **blind fire** |
| `melee_heavy` | X | heavy strike (wind-up, knock-down chance) / weapon bash with a firearm; **stealth takedown** (any weapon) when the "Takedown" prompt shows |
| `reload`, `weapon_next/prev`, `weapon_slot_1..9`, `throw_grenade`, `holster` | | forwarded to the WeaponInventory |
| `enter_vehicle` | F | **tap**: enter / steal (pull the driver out, shove a rider off) / leave; **hold** (0.35 s) next to a driven vehicle with a free passenger seat: ride along |
| `interact` | E | use the focused Interactable; **climb a ladder** at its foot or top; let go of a ladder |
| `camera_toggle` | V | third ↔ first person (also inside vehicles) |
| `look_back` | C (in vehicle) | look behind the vehicle (not while drive-by aiming) |
| `siren` T, `vehicle_roof` K, `horn` H, `headlights` L | | read by the vehicle itself while the player drives (VEHICLES.md §17) — no player-side code needed |
| `look_*` | right stick | camera |

All gameplay input is ignored while `Game.is_input_locked()` or after
`player.set_control_enabled(false)`.

---------------------------------------------------------------------------------------------------

## 2. States

`Player.change_state(id, args)`; `Player.state_id` is the internal id, `EventBus.player_state_changed`
reports the public name.

| id | public name | Notes |
|---|---|---|
| `on_foot` | `on_foot` | walk 1.9, run 4.4, sprint 7.0, crouch 2.1, sneak 2.4, aim-strafe 2.6 m/s. Kerbs and stairs up to 0.32 m are stepped up (`_try_step_up`), no sliding on walkable slopes (≤ 46°), wading slows down, deep water → `swim`. Hard landing at a run (> 9 m/s impact, > 2.5 m/s planar) = forward **stumble**; `stagger(push, seconds)` for heavy blows / blasts |
| `melee` | `melee` | melee stance, see §6 |
| `roll` | `roll` | `kind` `roll` (0.62 s, 3.2 m, animator `roll`) or `step` (0.30 s, 1.45 m, crouched). Melee blows in the first 75 % miss; bullets still hit |
| `vault` | `vault` | `kind` `vault` (0.62 s + 0.1 s/m) or `mantle` (0.78 s + 0.22 s/m), collision off, procedural curve, animator `vault` (`motion_style` 0 / 1) |
| `ladder` | `ladder` | climb 1.6 m/s (sprint 2.5, crouch slide 4.5), top-out 0.85 s, mount from the top 0.7 s |
| `air` | `on_foot` | jump 1.1 m, air steering, landing: > 9 m/s hard landing (short lock, squat, dust, shake), > 12.5 m/s fall damage (7.5 hp per m/s), > 17 m/s knock-down ragdoll; into water → `swim`; below y −80 → recovered. A jump that carries the player against a ledge ≤ 1.5 m above the feet **grabs it** (mantle) |
| `swim` | `swimming` | floats with the origin 1.42 m under the surface (`environment.get_wave_height`, fallback `Game.WATER_LEVEL`); crouch dives, jump surfaces, forward follows the camera pitch under water; breath 28 s × lung skill, then 10 hp/s drowning; `player_entered_water / exited_water / submerged`. Jump / interact at a harbour ladder climbs out |
| `vehicle` | `in_vehicle` | phases APPROACH (walk to the door, no collision) → JACK (seat taken: `jack` / `shove`, the occupant is pulled out) → ENTER (0.55 s slide to the seat, `enter_car`) → SEATED (child of the seat node, collision off, seated pose, drive-by) → EXIT (0.5 s); > 8 m/s = bail out and tumble; high above ground = step out into `air`. A door farther than `VEHICLE_WALK_MAX` (8 m) = instant entry |
| `ragdoll` | `ragdoll` | physical ragdoll for `duration`, then blends out of the ragdoll pose and gets up (0.95 s) |
| `dead` | `dead` | death ragdoll; the `respawn` system does the rest. Without it **or while it is disabled** (admin): "DOWN" banner, fade, respawn at `Game.get_location("hospital")` after 5 s, `Wanted.clear("died")` |
| `busted` | `busted` | arrested (`Player.arrest()`): out of the vehicle, hands up (`surrender`), no control until the `respawn` system releases the player. Fallback after 6 s (police station) whenever the respawn system is not running its `"busted"` flow (missing, disabled, or `arrest()` called without `EventBus.player_busted`) |
| `cover` | `cover` | see §12. Back to the surface; low cover crouched (rise to aim), high cover standing (lean out at an edge); move 1.6 / 2.0 m/s along it; animator `cover_low` / `cover_high` |
| `takedown` | `takedown` | see §13. 0.85 - 1.25 s scripted grab behind the victim, collision off, animator `takedown` |

### Adding a state (cover, stealth takedown, parachute …) — extension points

**Ground states that walk, aim and shoot extend `PlayerStateOnFoot`** and override only the hooks
that differ (this is how `PlayerStateMelee` is built; the cover / stealth state of the next wave
should do the same). Hooks, called once per physics tick in this order:

| hook | base behaviour |
|---|---|
| `_wants_other_state() -> bool` | switch before anything moves (true = switched). Base: fists / melee weapon + fire / melee_heavy / aim → `melee` |
| `_handle_combat(delta) -> bool` | aim + weapon input; returns "face the camera". Base: `set_aiming(aim)`, `process_weapon_input()` |
| `_sprint_allowed() -> bool` | base true (melee: false) |
| `_target_speed(mag, combat) -> float` | walk / run / sprint / crouch / aim / sneak, wading |
| `_target_velocity(wish, mag, max_speed) -> Vector3` | planar velocity to accelerate towards (melee lunges override it) |
| `_update_facing(delta, wish, mag, combat)` | camera yaw in combat / first person, else the move direction |
| `_try_jump_actions(wish, mag) -> bool` | ladder → vault / mantle → roll; true = consumed (state changed) |
| `_update_anim(speed)` | land / crouch / locomotion / idle |
| `stagger(push, seconds)`, `is_staggering()` | lose control and slide (heavy hits, blasts, hard landings) |

Every state also has (base `PlayerState`): `enter`, `exit`, `physics_update`, `frame_update`,
`allows_weapons()`, `allows_vehicle_entry()`, `get_focus_position()`, `on_damage(info, amount)` and
**`modify_damage(info, amount) -> float`** — called by `Player.apply_damage` *before* armor /
health with a private copy of `info`: return the amount that lands (0 = avoided) and set flags
(`blocked`, `dodged`, `no_ragdoll`, `knockdown = false` …). The melee block and the dodge use it;
cover damage reduction belongs there too.

A brand-new state (not ground based):
```gdscript
class_name PlayerStateCover          # reserved prefix PlayerState*
extends PlayerStateOnFoot            # or PlayerState for non-ground states
func _init() -> void: public_name = "cover"
func enter(previous: String, args: Dictionary) -> void: super.enter(previous, {}); player.in_cover = true
func exit(next: String) -> void: player.in_cover = false; super.exit(next)
```
and once: `player.register_state("cover", PlayerStateCover.new())` (in `Player._setup_states`).
Player helpers a state can use: `get_move_input()`, `get_wish_dir(input)`, `pressed(action)` /
`just_pressed(action)` (respect the input lock), `accelerate_planar(target, rate, delta)`,
`turn_toward(yaw, rate, delta)`, `move_body(delta, with_steps)`, `grounded`, `set_crouching(on)`,
`can_stand()`, `set_collision_enabled(on)`, `update_stamina(delta, draining)`,
`hold_stamina_regen(seconds)`, `set_aiming(on)`, `process_weapon_input(delta)` =
`process_fire_input(delta, blocked)` + `process_weapon_select_input(with_heavy)`,
`set_anim_state(name, blend)`, `play_action(name, duration)`, `play_hit_react(from_local, strength)`,
`emit_noise(radius, kind)`, `shake_camera(amount)`, `get_view_yaw()`, `get_view_pitch()`,
`try_traversal(dir, from_air)`, `find_ladder()`, `start_ladder(ladder, from_top)`,
`process_vehicle_entry_input(delta, allowed)`.
The PlayerInteraction scanner offers nothing while the state is `ladder`, `vault`, `roll`,
`busted`, `ragdoll` or `takedown` (`_player_busy`); add new busy states there. A takedown in reach
(`Player.takedown_target`) is offered before everything else ("Takedown", `melee_heavy`).

Two more `PlayerState` hooks (Wave 2, cover / stealth programmer):

| hook | use |
|---|---|
| `get_camera_hint() -> Dictionary` | read by `PlayerCamera` every frame in the third / aim modes. Keys (optional): `side`, `height`, `distance` (replace the mode's shoulder offset, pivot height, arm length), `pivot_offset` (Vector3 added to the pivot), `mask` (extra collision layers for the camera probe). `{}` = defaults |
| `update_animator(a: HumanoidAnimator)` | called at the end of `Player._update_animator` (on foot) after the shared parameters were set; a state may refine them |

`PlayerStateOnFoot.STEALTH_KEEP_STATES` lists the next states that keep stealth on (`on_foot, air,
melee, roll, vault, cover, takedown`); every other state change ends it. `PlayerStateOnFoot._try_takedown()`
runs before `_wants_other_state()` (so also in the melee stance); the cover key is read right after it.

---------------------------------------------------------------------------------------------------

## 3. Public API of `Player` (ARCHITECTURE §6.4 + additions)

Contract members: `health, max_health, armor, max_armor, is_dead, current_vehicle, is_aiming,
is_sprinting, is_crouching, in_stealth, in_cover, is_swimming, is_underwater, has_parachute,
breath, stamina, noise_radius, visual, inventory` and
`apply_damage(info)`, `heal(amount)`, `add_armor(amount)`, `teleport(pos, yaw)`,
`set_control_enabled(on)`, `enter_vehicle(vehicle, seat)`, `exit_vehicle()`, `get_aim_ray()`,
`get_aim_point()`, `get_target_position()`, `add_recoil(pitch_deg, yaw_deg)`, `is_armed()`,
`kill(cause)`, `respawn(xform)`, `ragdoll(impulse, duration)`, `get_save_data()`,
`load_save_data(d)`.

Additions other modules may use:

| Member | Purpose |
|---|---|
| `animator: HumanoidAnimator`, `camera: PlayerCamera`, `interaction: PlayerInteraction`, `vehicle_ix` | sub-objects |
| `state_id`, `get_state_name()`, `register_state()`, `change_state()` | state machine |
| `enter_vehicle(vehicle, seat, instant := false)` | third argument skips the transition (taxi, respawn in a car, admin) |
| `on_vehicle_ejected(vehicle, exit_xform, impulse)` | called by `VehicleBase.eject_occupants` / carjack |
| `find_enterable_vehicle()`, `can_enter_vehicles()`, `is_in_vehicle()` | vehicle prompts |
| `play_action(name, duration)`, `play_weapon_action(name, duration)` | one-shot animation |
| `play_hit_react(from_local: Vector2, strength)` | directional flinch (x right, y front) |
| `set_stealth(on)` | sneak mode |
| `set_visual_hidden(reason, hidden)`, `set_head_hidden(hidden)`, `is_head_hidden()` | visibility (first person, scope, ragdoll stand-in) |
| `get_appearance()`, `set_appearance(dict)` | wardrobe / barber; emits `player_appearance_changed` |
| `get_camera_focus()` | feet-level point the camera follows (vehicle / ragdoll aware) |
| `has_control()` | false while dead, locked or control disabled |
| `knock_down(impulse)` | NpcBase-compatible knock-down (= `ragdoll(impulse, 1.8)`) |
| `is_same_impact()` | true for `SAME_IMPACT_FRAMES` (15 physics frames) after a ragdoll spawned |
| `give_parachute()`, `give_scuba()`, `has_scuba` | pickup hooks; scuba = air lasts `SCUBA_BREATH_MULT` (12) × longer |
| `arrest()`, `is_busted()` | W2.5 arrest (the respawn system calls it on `EventBus.player_busted`) |
| `has_melee_weapon()` | fists or a melee weapon in hand |
| `is_blocking`, `melee_target` | melee guard up / soft lock-on target |
| `on_ladder`, `find_ladder()`, `start_ladder(ladder, from_top := -1)`, `climb_ladder(ladder)` | ladders; `climb_ladder` is the alias for other modules' "Climb" interactables |
| `try_traversal(dir, from_air)` | vault / mantle if an obstacle allows it |
| `last_safe_position` | last grounded, dry on-foot position at / above the terrain (respawn rescue) |
| `drive_by_window`, `anim_aim_yaw`, `anim_aim_pitch`, `aim_dir_override` | drive-by internals (read-only for others) |
| `water_depth`, `water_surface_y`, `grounded`, `last_damage_info`, `seat_index` | read-only state |
| `visibility_factor` | 0.1..1, how easy the player is to spot (posture x light), refreshed every 0.2 s; **AiSenses multiplies its awareness rate by it** |
| `takedown_target` | NPC a stealth takedown would hit right now (or null), refreshed every 0.1 s while sneaking |
| `try_takedown()`, `try_take_cover()` | start a takedown on `takedown_target` / take cover in front (true = started) |
| `get_stealth_noise_radius()` | sneak / crouch footstep radius: 1.5 m at the starting Stealth level, 0.9 m at 100 |
| `set_stealth(on)` | also emits `EventBus.player_state_changed("stealth")` (off: the active state's public name) |
| `stealth` | the Stealth helper (`light_level`, `xp_awarded`, `update_visibility()`, `refresh_lamps()`) |
| `aim_spread_extra_deg` | extra random cone on `get_aim_ray()` (blind fire sets it) |
| `fire_pressed_edge` | true in the first physics tick `fire` is held (the trigger's own edge) |

### Damage rules (`apply_damage(info)`, `Dmg` contract)

- ignored while dead or `Game.invulnerable`;
- the active state's `modify_damage(info, amount)` runs first (block, dodge …);
- armor absorbs `bullet` and `explosion` first, everything else goes straight to health;
- emits `EventBus.player_damaged(total, info)` and `player_health_changed(health, armor)`;
- `vehicle` / `collision` ≥ 8 hp, `explosion` ≥ 20 hp **or impulse ≥ 260**, or
  `info.knockdown == true` → ragdoll (`info.no_ragdoll = true` suppresses it);
- otherwise a **directional** `hit_react` (from `info.direction`, else `info.position`); strength by
  type (heavy melee 1.5, melee 1.1, blast 1.4, bullet 0.8, blocked 0.5); heavy melee blows and
  blasts that do not knock down also **stagger** (0.32 s, pushed along the blow);
- a vehicle hit throws the ragdoll with the hitter's own `info.impulse` (clamped 150–1100 N·s);
  a second impulse within the same impact is ignored;
- health ≤ 0 → dead state, `EventBus.player_died(type)`;
- being hit by a vehicle is detected by the player itself (`VehicleSensor`, closing speed ≥ 4.5 m/s);
- slow regeneration up to 50 % health after 8 s without damage.

### Save data (`SaveSystem.register_provider("player", player)`)

`{"position": [x,y,z], "yaw", "health", "armor", "has_parachute", "has_scuba", "appearance": {...}}`
(position of the vehicle when driving, hospital when dead). `load_save_data` reads every value type-safely
(`Player._save_num`: numbers or digit strings, finite only; bools only when they are real bools; an unusable
position keeps the current one) - a hand-edited or corrupt save never raises a script error.

### Tunables (constants at the top of `player.gd` and the state files)

Speeds `WALK_SPEED 1.9`, `RUN_SPEED 4.4`, `SPRINT_SPEED 7.0`, `CROUCH_SPEED 2.1`, `STEALTH_SPEED 2.4`,
`AIM_SPEED 2.6`; `JUMP_HEIGHT 1.1`, `GRAVITY 20`, `ACCEL_GROUND 18`, `DECEL_GROUND 24`,
`TURN_RATE 11` (sprint 6.5, aim 16), `STEP_HEIGHT 0.32`, `FLOOR_ANGLE_DEG 46`;
`STAMINA_SPRINT_SECONDS 13` (× `Skills.get_multiplier("stamina", 0.75, 1.9)`),
`STAMINA_REGEN_SECONDS 7`; `FALL_SAFE_SPEED 12.5`, `FALL_DAMAGE_PER_MS 7.5`, `HARD_LAND_SPEED 9`,
`RAGDOLL_LAND_SPEED 17`; `SWIM_SPEED 2.1`, `SWIM_FAST_SPEED 3.3`, `DIVE_SPEED 2.4`,
`DIVE_VERTICAL_SPEED 1.8` (`SURFACE_SPEED_MULT 1.4` upwards), `FLOAT_DEPTH 1.42`,
`BREATH_SECONDS 28` (× lung skill), `DROWN_DAMAGE 10`/s; `VEHICLE_REACH 3.0`, `VEHICLE_WALK_MAX 8`,
`VEHICLE_ENTER_TIME 0.55`, `VEHICLE_EXIT_TIME 0.5`, `BAIL_SPEED 8`, `WRECK_DAMAGE 120`;
`RESPAWN_DELAY 5`; `HEAVY_HIT_STAGGER 0.32`; noise radii `NOISE_WALK 5`, `NOISE_RUN 7`,
`NOISE_SPRINT 9`, `NOISE_STEALTH 1.5` (x down to `STEALTH_SKILL_NOISE` 0.6 at Stealth 100).
Vault: `VAULT_MIN_HEIGHT 0.45`, `VAULT_MAX_HEIGHT 1.1`, `MANTLE_MAX_HEIGHT 2.0`, `AIR_MAX_RISE 1.5`,
`VAULT_MAX_DEPTH 1.25`, `REACH 0.85`. Ladder: `CLIMB_SPEED 1.6`, `CLIMB_FAST 2.5`, `SLIDE_SPEED 4.5`,
`STAND_OFF 0.36`, `TOP_HANG 1.05`, `TOP_EXIT_FORWARD 0.55`. Roll: `ROLL_TIME 0.62`,
`ROLL_DISTANCE 3.2`, `STEP_TIME 0.30`, `STEP_DISTANCE 1.45`, `DODGE_WINDOW 0.75`.
Melee: `LOCK_RANGE 3.6`, `LUNGE_MAX 1.2`, `BLOCK_DAMAGE_MULT 0.2`, `BLOCK_STAMINA_PER_HP 0.006`
(min 0.05, × 1.6 heavy), `BLOCK_DRAIN 0.03`/s, `FINISHER_RANGE 2.4`, `FINISHER_MIN_DAMAGE 40`.
Cover (`player_state_cover.gd` / `player_cover.gd`): `STAND_OFF 0.41`, `SEARCH_REACH 3`, `RING_REACH 1.3`,
`LOW_MIN 0.85`, `HIGH_PROBE_Y 1.55`, `GLIDE_SPEED 5.5`, `MOVE_SPEED_LOW 1.6` / `HIGH 2.0`, `EDGE_STOP 0.18`,
`EDGE_NEAR 0.62`, `PEEK_PAST 0.45`, `BLIND_PAST 0.12`, `BLIND_SPREAD_DEG 6.5`, `BLIND_READY 0.14`,
`PULL_AWAY_TIME 0.18`, `SWING_TIME 0.5`, `VEHICLE_MOVE_SPEED 1.2`, `DAMAGE_MULT_HIDDEN 0.3` / `EXPOSED 0.8`,
`SLIDE_GIVE_UP 0.8` (a blocked slide back from a lean / out to blind fire ends where it is).
Takedown: `RANGE 1.6`, `REAR_ARC_COS -0.34` (rear 140°), `AWARE_LIMIT 0.6`, `KILL_DAMAGE 400`, `KO_DAMAGE 25`,
`KO_SECONDS 30`, `XP 0.4`. Stealth helper: `XP_PER_SEC 0.035` per unaware NPC within 14 m (max 2),
`LAMP_RANGE 11`, `DARK_VISIBILITY 0.5`, `CROUCH_MULT 0.78`, `STEALTH_MULT 0.72 -> 0.58`, `COVER_MULT 0.7`.

Skills: sprinting / swimming / climbing give `stamina` XP, diving gives `lung` XP, melee hits give
`strength` XP (Combat 0.08 per hit; finisher 0.25 and blocked blow 0.03 here); strength scales melee
damage inside the inventory (× 0.9 → × 1.35) and the finisher. Sneaking near unaware NPCs (0.035 / s
each, max 2) and takedowns (0.4) give `stealth` XP; Stealth lowers the sneak noise radius (1.5 -> 0.9 m
from the starting level to 100) and the sneaking posture factor of `visibility_factor` (0.72 -> 0.58).
Noise: every footstep emits `EventBus.noise_emitted(pos, noise_radius, "footstep", player)`; vault,
roll, ladder rungs, carjacks and finishers emit their own small noises.

---------------------------------------------------------------------------------------------------

## 4. Hooks for neighbours

### Vehicle seat contract (what the player calls on a vehicle)

1. `enter_vehicle` key → `find_enterable_vehicle()`: nodes in group `vehicle` within 12 m with
   `can_enter(player) == true` whose door (`get_exit_transform(seat).origin`) is within 3 m.
   Tap = seat 0; hold (≥ 0.35 s) next to a vehicle whose driver is somebody else and that has a free
   passenger seat = the free passenger seat with the nearest door (`get_seat_count`,
   `get_occupant`, `get_door_position`).
2. APPROACH: the body walks to `get_exit_transform(seat)`; JACK when `get_occupant(seat)` (or
   `driver`) is somebody else; ENTER: slides to `get_seat_node(seat)`.
3. `vehicle.occupant_enter(player, seat)` → the player becomes a **child of
   `vehicle.get_seat_node(seat)`** with identity local transform (the seat node = hip point of the
   seated character, −Z forward), collision off, `current_vehicle = vehicle`,
   `EventBus.player_entered_vehicle(vehicle, seat)`.
4. Seated pose: `seated_bike` for `vehicle_class` "bike"/"bicycle", else `seated_car`. Hands go to a
   child node named `SteeringWheel` / `Handlebar` when the vehicle has one near the seat.
5. Exit: `vehicle.occupant_exit(seat)` → world Transform3D to stand at (must be within 12 m).
   `EventBus.player_exited_vehicle(vehicle)`.
6. The vehicle may throw the player out with `player.on_vehicle_ejected(vehicle, exit_xform, impulse)`
   (seat already freed). `vehicle.destroyed == true` with the player inside = 120 explosion damage.
   A vehicle that is freed while the player sits in it does not take the player with it (also at
   quit: the deferred re-homing no longer passes a freed node — Wave 1 shutdown error fixed).
7. Weapons in a vehicle only when `inventory.can_use_in_vehicle(current_id)` and the seat allows
   drive-by (aircraft pilots do not).

### Carjacking (W2.1) — what AI / traffic / police must provide

- `vehicle.set_meta("ai_controller", controller)`, `vehicle.driver = npc` (and the NPC in seat 0).
- `controller.release_vehicle(vehicle, "carjacked") -> Node3D`: the driver leaves as a real NPC
  beside the driver door (returned), meta removed, `driver == null` (the player removes a stale
  meta as a safety net). The player then calls `npc.knock_down(impulse)` (130 N·s for cars,
  190 N·s for bikes; `panic(pos)` when there is no `knock_down`). Reaction / fight-back after
  getting up is the NPC brain's job (it knows the reason "carjacked").
- Without a controller the vehicle's own `occupant_enter` evicts the occupant (`_evict` →
  `on_vehicle_ejected` / `knock_down`).
- The pulled-out occupant lands on the door point, i.e. where the player stands: the player module moves
  it 0.45 m further out and 0.4 m towards the rear (when nothing solid is in the way) before the throw, so
  the two bodies do not overlap on screen (`ROOM_DISTANCE`).
- The entry is abandoned (back to `on_foot`) when the vehicle gets `destroyed` or `locked` while the player
  walks to it / pulls the driver out / slides in; a tap / hold decision is dropped on `teleport()` and when
  the car is more than 7 m away when the key is released.
- Reports: `EventBus.vehicle_stolen(vehicle, player, true)` + `Wanted.report_crime("vehicle_theft"`
  or `"police_vehicle_theft", pos, {"instigator": player, "victim": npc, "vehicle": vehicle})`.
  An empty vehicle that is not already the player's: `vehicle_stolen(vehicle, player, false)` once;
  only police vehicles are a crime. Riding along as a passenger is never theft.
- Prompts: "Steal <name>  (hold: ride along)", "Shove off the rider of <name>", "Enter / Ride /
  Board / Fly <name>" (name from `display_name` or `spec.display_name`).

### Drive-by

- Weapons: whatever `inventory.can_use_in_vehicle(id)` allows (pistol, heavy pistol, SMG, grenade,
  fire bottle). Aim with empty hands draws the best one (`vehicle_ix.pick_drive_by_weapon()`).
- `aim` (or `fire` with a firearm) → `is_aiming`; the camera switches to drive-by free aim (no
  auto-centring, aim FOV + 8°, pitch −0.75…0.55); `PlayerCamera.is_drive_by_aiming()`. The HUD shows the
  crosshair because `is_aiming` is true. **Cars whose cabin was checked from inside** (`DRIVE_BY_CABIN_SPECS`:
  sedan, police_cruiser, taxi, compact, suv, muscle, pickup - `qa/screenshots/plr4_dbcam_<spec>.png`): the camera sits inside
  the cabin over the shooter's far shoulder (0.8 m behind the eyes against the view, 0.34 m to the side that
  faces the middle of the cabin, 0.07 m up) and looks out of the window the gun points through
  (`PlayerCamera.is_drive_by_cabin()`). From above the roof (the Wave 2 implementation) the shooter, the arm
  and the gun were all hidden under the roof edge. Every other vehicle (open ones - bike, bicycle, boat, heli,
  plane - and the van / box truck, where the point lands in the cab's back wall, the low sports car, the
  unchecked ambulance / firetruck / swat_van), aims more than 120° back from the bonnet, or another occupant's
  head at the camera point (riding along next to an AI driver) use the orbit above the shooter's head instead;
  the switch is smoothed.
- Arcs (yaw relative to the vehicle forward, + = left): left seats −28°…+165°, right seats
  −165°…+28°, bikes ±115°, pitch −43°…+36°; outside → the trigger stays up
  (`PlayerStateVehicle.drive_by_in_arc`). Shots leave from the window on the aim side
  (`get_target_position()` returns `drive_by_window − 0.3 m`, the inventory fires from +0.3 m).
  Spread: the inventory's ×1.6 in vehicles plus its speed factor.
- Thrown weapons: aiming = lobbed along the crosshair; not aiming = dropped out of the window
  (`aim_dir_override` points down / back / out of the seat side).
- Steering keeps working (the vehicle reads its own input). Animator: `aim_weight` 1, `aim_yaw`
  (seat frame) and `aim_pitch`; one-handed (the other hand stays on the wheel / bar) with a lean
  towards the window; the gun hand is raised `SEATED_GUN_RAISE` (0.10 m) above the shoulder line so it is
  in the window opening, not on the sill.

### Inventory contract (what the player calls on `Inventory`)

`setup(player)`, `trigger_pressed()`, `trigger_released()`, `reload()`, `set_aiming(on)`,
`next_weapon()`, `prev_weapon()`, `equip_slot(1..9)`, `throw_grenade()`, `melee_attack(heavy)`,
`holster()`, `equip(id)`, `get_weapons()`, `get_ammo(id)`; signal `melee_started(id, heavy, step)`
(the melee stance lunges / turns on it); reads `current_id`, `is_armed()`, `is_busy()`,
`get_weapon_pose()` (or `get_current_spec().weapon_pose`), `get_current_spec()`, `get_aim_fov()`,
`is_scoped()` (→ camera mode `scope`), `can_use_in_vehicle(id)`.
The inventory asks the player for `get_aim_ray()` (ray along the camera, origin pushed forward to
the player so nothing behind the character is hit), `add_recoil(pitch_deg, yaw_deg)`,
`visual.get_bone_attachment("Hand_R")`, `play_weapon_action(name, duration)`.
The grip a weapon model has to sit in: `HumanoidAnimator.get_grip_transform(skeleton, "Hand_R")`
(barrel = −Z of the weapon node, up = +Y).

### Ladders (W2.4)

Any `Node3D` in group `ladder`, origin at the foot, climber facing local −Z, `get_meta("height")`
(default 3 m). Mount: at the foot (within 0.95 m of the stand point 0.36 m behind the ladder line,
feet ≤ 0.7 m below / ≤ 1.2 m above the foot), at the top (within 1 m of the top exit 0.55 m beyond
the ladder line, feet within 0.75 m of the top) or from the water (harbour ladders). The top-out
needs room for a standing capsule at the top exit, otherwise the player waits at the top.
Other modules may also create an Interactable that calls `player.climb_ladder(ladder)`.

### Interactables

`PlayerInteraction` scans group `interactable` every 0.15 s: `can_interact(player)` → highest
`use_priority` → nearest. Prompt through `UI.show_prompt(prompt, action)`, key press →
`interact(player)`. Without an interactable in reach: a ladder ("Climb ladder" / "Climb down",
interact) and then the enter-vehicle prompt. An Interactable bound to `enter_vehicle` wins over
vehicles. `EventBus.interactable_focus_changed(node)`.

### Respawn system (`Game.get_system("respawn")`, W2.5)

| flow | what happens |
|---|---|
| death (`EventBus.player_died`) | banner "DOWN" + an original sub-line (coral), slow motion 0.3 for 1.3 s (real), 2.2 s hold, fade out 0.7 s, respawn at the city's hospital `Respawn` marker (fallback `Game.get_location("hospital")`, snapped to the ground), medical fee $200 (never below $0), `Wanted.clear("died")`, `WorldClock.advance_hours(4)`, `reset_for_respawn()` on every system + Wanted + `inventory.reset_for_respawn(true)` (weapons and ammo kept), fade in, "Hospital bill" notification |
| arrest (`EventBus.player_busted`, i.e. `Wanted.bust()`) | `player.arrest()` (hands up), banner "ARRESTED" (teal), 2.4 s, fade out, fine $500, **every round confiscated** (magazines + pools, weapons kept, empty-handed), `Wanted.clear("busted")`, 6 h pass, resets, release at the police station `Respawn` marker, fade in, notification |
| rescue | every 0.25 s: the player (or the vehicle he drives) more than 4 m under the terrain / seabed and not standing (12 m even when standing; 6 m for vehicles) or below y −80, twice in a row → 0.25 s fade, back to `last_safe_position` (vehicles to their own last safe spot through `teleport()`), fade in |

Both flows stand down if somebody else revives / releases the player in the meantime (load game,
admin, tests). **Watchdog**: whenever the player has been dead for 0.5 s (`DEAD_WATCHDOG`) while no flow
runs - killed during the arrest hold or the rescue fade, or the system re-enabled while the player lay dead -
the death flow starts (with the last `player_died` cause). The game-time holds (`DEATH_HOLD`, `ARREST_HOLD`)
wait while the game is paused; only the slow-motion part uses real time. Public: `busy`, `flow`, `respawn_transform(landmark)`, counters `respawn_count`,
`arrest_count`, `rescue_count`, `last_fee`, `last_confiscated`, `set_enabled(on)`,
`reset_for_respawn()`. `Player.respawn()` restores health, clears armor, breath, stamina, the
ragdoll, the melee / ladder / drive-by flags and emits `player_health_changed` + `player_respawned`.

---------------------------------------------------------------------------------------------------

## 5. Traversal details

- **Probe** (`PlayerStateVault.probe(dir, max_rise)`, rays + shape tests on `WORLD | VEHICLE | PROP`,
  member query objects, only on jump presses / every 0.06 s while a jump pushes into a wall):
  front face at 0.42 m (or 0.85 m) within 0.85 m of the capsule, roughly facing us; top found by two
  down rays 0.12 / 0.30 m behind the face (must be walkable); a free box above the edge; depth
  scanned in 0.15 m steps. Vault = top 0.45–1.1 m and depth ≤ 1.25 m with a free landing; mantle =
  top ≤ 2.0 m (≤ 1.5 m above the feet from a jump) with standing room. Moving rigid bodies
  (> 1 m/s) are never vaulted.
- **Motion**: vault = rise to 0.28 m under the top at the face → over (tucked feet clear the edge) →
  drop to the landing (keeps the run speed ≥ 3 m/s; a long drop ends in `air`); mantle = to the wall
  → pull up to the top → step 0.45 m in. The animator gets `motion_t`, `motion_style` and
  `motion_height` (hands planted on the top: left hand for the vault, both for the mantle).
- **Ladder**, **roll / step**, **hard landing**, **blasts**: see §2.

## 6. Melee details (`PlayerStateMelee`)

Entered with fists / a melee weapon on `fire`, `melee_heavy` or `aim`; left after 0.7 s without
fighting (no aim, no fire), on sprinting, when a firearm is drawn, or by jumping / entering a vehicle.

- Light strikes = `inventory.trigger_pressed()` → the inventory's 3-step combo (fists: right, left,
  kick; finisher × 1.4 with its knock-down chance), presses inside a swing are queued, the chain
  resets 0.55 s after a swing.
- Heavy = `inventory.melee_attack(true)`: × 1.7 duration, hit at 50 % (wind-up), × heavy mult,
  knock-down chance + 0.3 (fists 85 %, bat 100 %).
- Soft lock-on every 0.1 s: living nodes in groups `npc` / `animal` within 3.6 m and a 140° cone
  around the stick (else camera) direction; hostiles preferred (`is_hostile_to(player)`, `hostile`,
  meta `hostile`, police while wanted); sticky. The body turns to the target; every swing lunges
  (light: during the first 40 %, heavy: 30–55 %) up to 1.2 m so the inventory's sweep connects.
- Block: aim held, not attacking → `is_blocking`, animator `guard`; frontal (≤ ~78°) melee / bite
  damage × 0.2, no knock-down, stamina per blow; drains 0.03/s while held, no regeneration; out of
  stamina = guard break (full damage, 0.6 s stagger). Heavy blocked blows push back a little.
- Dodge step: guard + jump + direction (`roll` kind `step`).
- Finisher: fire / melee_heavy with a downed target within 2.4 m (NPC `is_knocked_down()`, or
  `state_tag` "knocked_down" / "down" / "ragdoll", or meta `knocked_down`): stomp (fists) or heavy
  downward blow (weapons), max(damage × heavy mult × 1.6, 40) × strength, applied straight to that
  target with `info.finisher = true`, `EventBus.hit_confirmed`, strength XP 0.25.
- Hit reactions on the player are directional (see damage rules).

---------------------------------------------------------------------------------------------------

## 7. Camera (`PlayerCamera`, `Game.camera_rig`)

Modes: `third`, `aim`, `first`, `vehicle`, `aircraft`, `scope`, `photo` — picked automatically from
the player state; `set_mode(name)` forces one, `set_mode("")` returns to automatic.
Public: `yaw`, `pitch` (radians; yaw 0 looks at −Z, + = left; pitch + = up), `mode`, `camera`,
`first_person`, `trauma`, `add_trauma(amount)`, `add_recoil(pitch_deg, yaw_deg)`,
`set_fov_override(fov, weight)`, `cycle_view()`, `snap_to(yaw)`, `apply_look(d_yaw, d_pitch)`,
`get_aim_origin()`, `get_aim_direction()`, `is_drive_by_aiming()`. Emits `EventBus.camera_mode_changed(mode)`.

- Collision: sphere cast (r 0.2) on `Layers.CAMERA_MASK` from the pivot; pulls in at once, eases out.
- Follow position is advanced in the physics tick, orientation in the render frame. The rig node moves to
  the follow point **before** the Camera3D (its child) is placed, so the rendered camera is exactly at
  `get_aim_origin()` (review fix: it used to be shifted by one frame of follow motion - ~0.2 m at 12 m/s,
  more at low frame rates, varying with the physics ticks per frame).
- Shake: trauma² · noise, never moves the aim ray. Connected to `Fx.camera_shake_requested`;
  scaled by `Settings.camera_shake` when the player triggers it.
- FOV: `Settings.fov`; aim = `inventory.get_aim_fov()` (fallback 52); sprint +4; vehicle =
  `get_camera_params().fov` + up to 13° with speed; first person +6; drive-by = aim FOV + 8.
- Mouse: `Settings.mouse_sensitivity`, `invert_y`; uses `InputEventMouseMotion.screen_relative`;
  ignored while `Game.is_input_locked()` (except photo mode).
- Vehicle: distance / look height from `vehicle.get_camera_params()`; mouse look-around that
  re-centres behind a moving vehicle after 1.3 s; `look_back`; aircraft ×1.45 distance and follows
  the pitch of the aircraft; drive-by aim (see §4).
- First person: at the eyes (animator eye point), head parts hidden through
  `CharacterVisual.set_head_visible(false)`.
- **Mouse capture** belongs to the UI module (fallback only when the UI does not manage it).
- **State hint** (`PlayerState.get_camera_hint()`): in cover the shoulder goes to the open side (the
  edge / the way the player looks), the pivot is pushed 0.3 m out of the wall while hunkered, and the
  collision probe also tests `VEHICLE | PROP`, so the camera never ends up inside the cover (also a car).

Tunables: `THIRD_DISTANCE 3.1`, `THIRD_HEIGHT 1.55`, `THIRD_SIDE 0.34`, `AIM_DISTANCE 1.75`,
`AIM_HEIGHT 1.66`, `AIM_SIDE 0.62`, `AIM_FOV 52`, `PITCH_MIN −1.25`, `PITCH_MAX 1.10`,
`FOLLOW_RATE 24`, `FOLLOW_RATE_Y 9`, `AIRCRAFT_DISTANCE_MULT 1.45`, `SPEED_FOV 13`, `TRAUMA_DECAY 1.4`,
`DRIVE_BY_DISTANCE_MULT 0.5` (max 2.4 m), `DRIVE_BY_HEAD 1.3`, `DRIVE_BY_LEAD 1.5`, `DRIVE_BY_FOV_BONUS 8`,
`DRIVE_BY_CABIN_BACK 0.8`, `DRIVE_BY_CABIN_SIDE 0.34`, `DRIVE_BY_CABIN_UP 0.07`, `DRIVE_BY_CABIN_CLEAR 0.55`,
`DRIVE_BY_CABIN_MAX_COS -0.5`, `DRIVE_BY_CABIN_SPECS`.

---------------------------------------------------------------------------------------------------

## 8. `HumanoidAnimator` — parameters

One node per character; no dependency on Player. `setup(skeleton)` binds it to the contract
skeleton (ARCHITECTURE §6.3). Everything is computed in model space over the rest pose: spine by
forward kinematics, arms and legs by analytic two-bone IK with pole vectors (knees / elbows cannot
flip), planted feet lower the pelvis automatically, stride length follows the speed. No allocations
per evaluation; one evaluation ≈ 0.03 ms.

| Parameter | Meaning |
|---|---|
| `state: String` | `idle, locomotion, crouch, jump, fall, land, swim, dive, tread, seated_car, seated_bike, aim, melee, cover_low, cover_high, climb_ladder, vault, roll, parachute, freefall, dead, surrender, cower, takedown, carried`. Assigning cross-fades; `set_state(name, seconds)` for an explicit time |
| `speed` | planar speed m/s (gait cadence, stride, arm swing, lean; swim stroke rate) |
| `move_dir_local: Vector2` | travel direction relative to the facing (x right, y forward) — strafing / backwards |
| `aim_weight`, `aim_pitch` | upper-body aim layer 0..1 and its pitch (rad, + up); also body pitch of `dive` / `freefall` |
| `aim_yaw` | aim yaw relative to the body (rad, + left): torso twist + gun arm swing (drive-by). In the seated states the aim layer runs while `aim_weight > 0`, one-handed, with a lean towards the window |
| `weapon_pose` | `none` (fists up when aiming), `pistol`, `rifle`, `melee`, `rpg`, `throw`; long guns get a low-ready carry when not aiming |
| `guard` | 0..1 raised block over the unarmed / melee aim pose |
| `hit_dir: Vector2`, `hit_strength` | where the last blow came from (x right, y front) and how hard: read by `hit_react` (front = rock back, behind = stumble forward, side = lean away) |
| `motion_t`, `motion_style`, `motion_height` | progress 0..1 of `vault` / `roll` / `takedown` (< 0 = state time); `MOTION_VAULT` / `MOTION_MANTLE`, `MOTION_TD_KNIFE` / `MOTION_TD_CHOKE` / `MOTION_TD_BLUNT` (attacker `TAKEDOWN_GRAB` 0.38 / 0.32 / 0.62 m behind the victim); obstacle top above the origin (hand plant) |
| `cover_side`, `cover_peek`, `cover_blind`, `cover_height` | states `cover_low` / `cover_high` (back to the surface): look / lean side (-1 its left, +1 its right); 0 hunkered (weapon high-ready, `cover_low` crouched) .. 1 risen / leaned out (plain ground + aim pose); blind-fire overlay (gun over the top behind the head / round the corner, barrel along `aim_yaw` / `aim_pitch`); top of the cover |
| `lean` | −1..1 turn / bike lean (+ right); `accel_lean` −1..1 torso pitch into acceleration |
| `vertical_speed` | m/s for jump / fall / ladder; `turn_rate` rad/s (feet shuffle when turning on the spot) |
| `steer` | −1..1 wheel / handlebar; `wheel_pos`, `wheel_radius`, `bar_pos`, `bar_half_width`, `peg_pos`, `pedal_pos` place the hands and feet in the seated states (model space, origin = seat hip point) |
| `sneak` | 0..1 sneaking on the ground states: crouch 0.46, torso bent forward, head up, hands carried in front, short arm swing |
| `look_yaw`, `look_pitch` | head look |
| `swim_depth` | water surface above the character origin while swimming at the surface |
| `hand_target_l/r`, `hand_target_weight_l/r` | optional hand IK override (model space) |
| `update_rate_hz` | 0 = every frame, e.g. 15 / 8 for distant NPCs (LOD). Invisible skeletons are skipped |
| `phase`, `time_scale`, `auto_process` | gait phase 0..1 (0 = left heel strike), freeze, manual `advance(delta)` |
| `hide_head` | collapses the head bone (fallback for visuals without `set_head_visible`) |

Methods: `play_action(name, duration := default)` with `reload, punch_l, punch_r, heavy, kick,
hit_react, throw, pickup, enter_car, exit_car, fire, jack` (reach into a car, grab, yank),
`shove` (two-hand push), `stomp` (finisher on somebody on the ground); `stop_action()`,
`get_action()`, `is_action_playing()`; `snap()`, `crossfade_from_current(seconds)`,
`get_eye_position()`, `get_hand_position(right)`, `get_chest_position()`,
static `get_grip_transform(skeleton, bone)`. Signals: `footstep(foot, intensity)`,
`action_finished(name)`. All new parameters default to the Wave 1 behaviour, so NPCs are unaffected
unless they set them (an NPC hit from behind can set `hit_dir = Vector2(0, -1)` before `hit_react`).

Minimal NPC use:
```gdscript
var anim := HumanoidAnimator.new()
add_child(anim)
anim.setup(visual.get_skeleton())
anim.update_rate_hz = 15.0          # LOD
anim.state = "locomotion"; anim.speed = velocity.length()   # every frame / AI tick
```

## 9. `Ragdoll`

`Ragdoll.spawn_from(visual, impulse := Vector3.ZERO, position := Vector3.INF, initial_velocity := Vector3.ZERO) -> Node3D`
builds 11 rigid segments (pelvis, torso, head, upper / lower arms, thighs, shins) on
`Layers.RAGDOLL` with cone-twist / hinge joints, in the pose `visual` has right now, driving a
fresh copy of the visual (same appearance). The caller hides or frees the source visual.
Auto clean-up after `lifetime` (16 s), at most `Ragdoll.MAX_ACTIVE` (8) exist; `persistent = true`
= the owner calls `dismiss()`. Also: `apply_impulse_at(impulse, position)`, `get_pelvis_position()`,
`get_stand_yaw()`, `is_settled()`, `copy_pose_to(skeleton)`, `Ragdoll.get_active_count()`,
`Ragdoll.clear_all()`. Returns null when the visual has no contract skeleton.

---------------------------------------------------------------------------------------------------

## 10. Tests

```powershell
tools\godot.ps1 -Mode headless -Frames 5600 -TimeoutSec 300 -UserArgs '--test=plr_move','--disable=traffic,peds,police','--test-timeout=240'
tools\godot.ps1 -Mode headless -Frames 2600 -TimeoutSec 240 -UserArgs '--test=plr_camera','--disable=traffic,peds,police','--test-timeout=200'
tools\godot.ps1 -Mode headless -Frames 4200 -TimeoutSec 240 -UserArgs '--test=plr_interact','--disable=traffic,peds,police','--test-timeout=200'
tools\godot.ps1 -Mode headless -Frames 4200 -TimeoutSec 300 -UserArgs '--test=plr_world','--disable=traffic,peds,police','--test-timeout=240'
tools\godot.ps1 -Mode headless -Frames 2400 -TimeoutSec 240 -UserArgs '--test=plr_leak','--disable=traffic,peds,police','--test-timeout=200'
tools\godot.ps1 -Mode headless -Frames 5400 -TimeoutSec 300 -UserArgs '--test=plr2_traversal','--disable=traffic,peds,police','--test-timeout=240'
tools\godot.ps1 -Mode headless -Frames 4200 -TimeoutSec 300 -UserArgs '--test=plr2_melee','--disable=traffic,peds,police','--test-timeout=240'
tools\godot.ps1 -Mode headless -Frames 4800 -TimeoutSec 300 -UserArgs '--test=plr2_carjack','--disable=traffic,peds,police','--test-timeout=240'
tools\godot.ps1 -Mode headless -Frames 3600 -TimeoutSec 300 -UserArgs '--test=plr2_driveby','--disable=traffic,peds,police','--test-timeout=240'
tools\godot.ps1 -Mode headless -Frames 3600 -TimeoutSec 300 -UserArgs '--test=plr2_respawn','--disable=traffic,peds,police','--test-timeout=240'
tools\godot.ps1 -Mode window   -Frames 600  -TimeoutSec 150 -UserArgs '--test=plr2_shots','--disable=traffic,peds,police'
tools\godot.ps1 -Mode headless -Frames 11000 -TimeoutSec 300 -UserArgs '--test=plr3_cover','--disable=traffic,peds,police','--test-timeout=260'
tools\godot.ps1 -Mode headless -Frames 7000 -TimeoutSec 300 -UserArgs '--test=plr3_stealth','--disable=traffic,police','--test-timeout=240'
tools\godot.ps1 -Mode window   -Frames 560  -TimeoutSec 150 -UserArgs '--test=plr3_shots','--disable=traffic,peds,police','--only=cover'
tools\godot.ps1 -Mode window   -Frames 420  -TimeoutSec 150 -UserArgs '--test=plr3_shots','--disable=traffic,peds,police','--only=stealth'
tools\godot.ps1 -Mode headless -Frames 7000 -TimeoutSec 300 -UserArgs '--test=plr4_review','--only=respawn,save,pending,driveby','--disable=traffic,peds,police','--test-timeout=280'
tools\godot.ps1 -Mode headless -Frames 3000 -TimeoutSec 300 -UserArgs '--test=plr4_review','--only=traffic','--disable=police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,debug,pickups,interactions','--test-timeout=240'
tools\godot.ps1 -Mode window   -Frames 600  -TimeoutSec 150 -UserArgs '--test=plr4_review','--only=traffic','--disable=police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,debug,pickups,interactions','--test-timeout=140'
tools\godot.ps1 -Mode headless -Frames 7200 -TimeoutSec 400 -UserArgs '--test=plr4_review','--only=police','--seed=21','--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,debug','--test-timeout=380'
tools\godot.ps1 -Mode headless -Frames 600  -UserArgs '--test=plr_anim_shots','--disable=traffic,peds,police','--shots=idle'
tools\godot.ps1 -Mode window   -Frames 420  -UserArgs '--test=plr_anim_shots','--disable=traffic,peds,police','--set=all'
tools\godot.ps1 -Mode window   -Frames 720  -UserArgs '--test=plr_game_shots','--disable=traffic,peds,police','--part=1'
```

| Test | Covers |
|---|---|
| `plr_move` | API surface, teleport, walk / run / sprint speeds, camera-relative movement, stamina, jump height, crouch, sneak, kerb step-up, slope, damage / armor / invulnerability, ragdoll + get up, same-impact dedupe, knock_down, fall damage, swim / dive / breath / scuba / drowning, death, respawn, fallback respawn, save / load, input lock |
| `plr_camera` | modes, orbit distance, wall collision, aim ray = camera view, aim point, mouse look + lock + invert, FOV, trauma, recoil, vehicle / aircraft chase, look_back, first person, photo mode |
| `plr_interact` | Interactable focus / prompt / priority / key, vehicle enter / exit transition, bail-out, eject, wreck, freed vehicle, being hit by a moving vehicle, inventory forwarding; soft `REAL_*` runs against the real sedan, inventory and pickups |
| `plr2_traversal` | vault (1 m wall), mantle (1.8 m ledge), nothing on 2.6 m, running-jump ledge grab, 5 m ladder (prompt, climb, top-out, mount from the top, climb down, step off, jump off), dodge roll while aiming, hard-landing stagger, blast ragdoll + get-up, blast stagger + directional reaction |
| `plr2_melee` | real inventory + Combat: combo 1-2-3 + finisher damage + window reset, lock-on turn + lunge, heavy wind-up + knock-down (bat), finisher on the downed target, block (front only, stamina, guard break), dodge step (blow misses), directional hit reaction, heavy-hit stagger, strength XP, leaving the stance |
| `plr2_carjack` | real sedan + dummy AI controller: carjack (jack phase, `release_vehicle("carjacked")`, knock-down, `vehicle_stolen`, `vehicle_theft`, player drives, owner_tag), hold = passenger (driver stays, no theft), motorcycle shove, empty police cruiser (`police_vehicle_theft`), empty civilian car (no crime, one announcement), threshold bug |
| `plr2_driveby` | real sedan + inventory: pistol from the driver's seat hits a target on the left (free aim, window origin, seated aim pose), steering while aiming, right side outside the driver's arc (no shot), fire bottle dropped / lobbed, motorcycle arcs |
| `plr2_respawn` | death flow (banner, slow motion, fade, hospital, fee, wanted cleared, +4 h, system resets, weapons kept), arrest flow (hands up, banner, police station, fine, ammo confiscated, weapons kept, +6 h), out-of-world rescue |
| `plr2_shots` | windowed: `qa/screenshots/plr2_{vault,mantle,ladder,punch,block,driveby,driveby_side,down}.png` (the drive-by pair aims at a stand-in figure; `plr2_driveby.png` = the in-cabin drive-by camera) |
| `plr3_cover` | real inventory + Combat + sedan: no cover in the open / behind a 0.6 m box; low wall (glide, back to the wall, crouched, class + height, move along, edge stop, shot line blocked hunkered / clear risen, aimed hits, blind fire over the top: no aim, no zoom, spread far above aimed, leave by key / pull-away / sprint / vault); 2.5 m block (high class, edge, blocked at the corner, lean out + camera on the open side + hits, back, blind fire round the corner, mid-wall aim keeps the trigger up, corner swing onto the end face); damage reduction; camera sweeps (no view inside a collider) at the wall, the block, its edge and the car; car = low cover, leave when it moves; soft REAL check on city building facades |
| `plr3_stealth` | noise radii (Stealth 0 / 100, run, sprint, sneak, footsteps, standing), sneak speed, `player_state_changed("stealth")`, sprint / loud shot end stealth, suppressed pistol keeps it (`suppressed_gunshot` 11 m), visibility_factor (crouch, sneak, night, street lamp), Stealth XP, takedowns (fists = silent knock-out, knife = silent kill, pistol: fire shoots / melee_heavy whips), prompt, no noise, victim held; refused from the front / side / 2.1 m / alerted / aware / not sneaking; soft: a real NpcBase civilian killed unseen gives no wanted level |
| `plr3_shots` | windowed: `qa/screenshots/plr3_{cover_low,cover_low_out,blind_low,cover_high_out,blind_corner,peek,peek_out,stealth_walk,takedown,takedown_knife}.png` |
| `plr4_review` | review test (`--only=` any of `respawn,save,pending,driveby,traffic,police`; windowed review tooling `dbcam`, `dbcars` + `--specs=a,b`): drive-by camera inside the sedan's cabin (point inside the body, crosshair on the target, rendered camera = aim origin also while driving at 12 m/s), motorcycle keeps the orbit; death during the arrest hold still respawns (watchdog), the death hold waits while paused, disabled respawn system -> dead-state fallback, `arrest()` without the flow -> busted fallback, control + walking + camera "third" after every flow; garbage save data; tap / hold decision + teleport; **REAL traffic + peds** carjack (prompt "Steal ...", JACK phase, the driver comes out as a real NPC and is knocked down, the player drives, traffic lets go; windowed: `qa/screenshots/plr4_carjack_{reach,pull,seated}.png`); **REAL police + respawn**: an officer arrests the idle 1-star player -> hands up -> released at the police station with control; `dbcam` (windowed) = drive-by camera framing study |
| `plr_anim_shots`, `plr_game_shots`, `plr_world`, `plr_leak` | see Wave 1 (pose sheet, real camera shots, real world walk, ragdoll leak / cap) |

`gta/tests/plr_arena.gd` is the shared scaffold (a concrete slab 400 m above the island, mock
vehicle / inventory, stand-in sea); `gta/tests/plr2_stage.gd` adds the traversal obstacles and a
test ladder, `gta/tests/plr3_stage.gd` the cover lanes (1.1 m wall, 2.5 m block with outside corners,
a car spot, a 0.6 m box, shooting targets + backstop). All are test equipment, not game content.

## 11. Known limits

- Vault / mantle / roll / ladder / jack / stomp are procedural poses driven by curves, not authored
  clips; hands have no finger bones (fists are open hands).
- The get-up after a ragdoll is a cross-fade from the ragdoll pose through a crouch.
- Keyboard walking uses the raw Left-Alt key until `InputSetup` gets a `walk` action.
- Drive-by from aircraft passenger seats uses the car arcs; pilots cannot shoot.
- Drive-by inside a cabin: the shooter's head and the seat back usually hide the gun hand itself (the target,
  the window and the shooter are in view; muzzle flash and tracers come from the window). The cabin view is a
  whitelist of checked bodies (`PlayerCamera.DRIVE_BY_CABIN_SPECS`); the van, box truck and sports car failed the
  check and the ambulance / firetruck / swat_van were not looked at, so they keep the orbit view whose roof hides
  the shooter (the original limitation). A new body needs a look from inside (`plr4_review --only=dbcars
  --specs=<id>`, windowed) before it is added.
- Ladders need nodes in group `ladder` (the city builder creates them from `Ladder_Bottom` /
  `Ladder_Top` markers); there is no visual ladder of the player module.
- The NPC reaction to being carjacked (panic / fight back) belongs to the AI brains; the player
  only knocks the pulled-out driver down.
- Cover, blind fire and takedowns are procedural poses too (no authored clips). The takedown victim
  is not animated by the player module: it is held still (`stop_moving`) and then goes down through
  its own `apply_damage` / `knock_down` (NpcBase ragdoll).
- Blind fire over low cover works by presenting `is_crouching = false` to the WeaponInventory while
  the trigger is up (its shots start at the standing eye height, 1.55 m; the capsule stays crouched).
  A holder hook `get_shoot_origin()` in the inventory would make this exact (requested).
- Mid-wall in high cover the aim key raises the crosshair but keeps the trigger up (nothing to shoot
  round); move to an edge to lean out. Cover on a corner of a thin wall (< 0.9 m deep end face) does
  not offer the corner swing.
- Cover tops between 0.85 m and the 1.55 m standing shoot height count as LOW: a 1.45 m wall is
  low cover whose risen shots clear it by only 10 cm.

### Wave 2 review fixes (independent reviewer, `plr4_review`)

- Respawn: death during the arrest hold / rescue fade no longer leaves the player dead for good (watchdog);
  the death / arrest holds respect the pause; the dead state falls back to its own respawn while the respawn
  system is disabled; a busted player is released by the busted fallback unless the respawn flow runs.
- Save data: `load_save_data` is type-safe (a `"yes" == true` comparison was a SCRIPT ERROR in Godot 4.7).
- Vehicles: an entry is abandoned when the car blows up / gets locked on the way; a pending tap / hold decision
  is dropped on teleport or when the car left; the pulled-out driver is moved aside before the throw.
- Camera: the rig is moved before the Camera3D is placed (the rendered camera trailed / led the aim origin by
  one frame of follow motion); drive-by from inside the cabin for the checked car bodies; the seated gun hand
  sits in the window opening (`SEATED_GUN_RAISE`).
- Cover: blocked slides give up after `SLIDE_GIVE_UP` instead of locking the stick.
- `PlayerState.NO_HINT`: no per-frame Dictionary from `get_camera_hint()`.

---------------------------------------------------------------------------------------------------

## 12. Cover details (`PlayerStateCover`, `player_cover.gd`)

**Finding cover** (`cover` key on foot / in the melee stance, `Player.try_take_cover()`): horizontal rays
at knee height (0.55 m) on `Layers.WORLD | VEHICLE | PROP` - a fan of 5 along the stick (else the camera)
direction up to 3 m beyond the capsule, plus a ring of 12 within 1.3 m; the best scores distance + angle.
A face qualifies when it is a wall (|n.y| < 0.4), faces the ray, is not a moving rigid body (> 0.8 m/s),
has floor at the stand point (0.41 m in front, within 0.6 m of the feet height), continues at least 0.3 m
to one side (posts are no cover) and leaves room for a crouched capsule. **Class**: a face at the
standing shoot height (1.55 m) = HIGH; otherwise the top (down rays 0.08 / 0.22 / 0.40 m behind the face)
must be at least 0.85 m = LOW (a sedan body measures ~0.97 m). Re-classified every 0.15 s while moving
(walls that step down).

**In cover**: the body glides there (5.5 m/s, turning its back to the face) and stands 0.41 m in front
of it, facing away (s = UP x n runs along the wall: camera-right when the camera looks at the wall,
the character's left). Stick left / right moves along the face (the face is re-traced every tick, so
curved / angled walls and car flanks work), stopping 0.18 m before an edge (`edge_neg` / `edge_pos`;
`near_*` = within 0.62 m). The `stealth` key works in cover; `noise_radius` is the sneak radius when
crouched / sneaking, else 3.5 m.

**Aim**: LOW = stand up (rise) and face the crosshair; HIGH near an edge = slide out so the centre is
0.45 m past the corner (edge found by bisection) and face the crosshair; HIGH mid-wall = aim held, trigger
up. The trigger opens at 80 % exposure. Releasing aim slides back to the stand point. **Blind fire**
(fire without aim, firearms / thrown weapons): LOW = gun over the top behind the head; HIGH only near an
edge: the body slides 0.12 m past the corner and the arm goes round it. Shots: hip spread + a 6.5 deg
random cone (`aim_spread_extra_deg`), no zoom, `is_aiming` stays false; the pose stays 0.45 s after the
trigger is released. **Corner swing**: at an edge with the stick towards it, the cover (or jump) key
swings 0.5 s round an outside corner whose end face is at least ~0.9 m deep, onto that face.

**Leaving**: cover key, pulling away from the face for 0.18 s, sprint + stick, jump (vault / mantle over
it via `Player.try_traversal`), entering a vehicle, falling (> 0.2 s airborne), deep water, the face
disappearing for 4 ticks, the covering vehicle moving (> 1.2 m/s or 0.35 m: thrown off with a short
stagger). `leave_reason` records why. Damage from the covered side: bullets / fire x 0.3 hunkered, x 0.8
exposed (explosions at least x 0.5), `info.cover = true`. Camera: see §7 "State hint".

## 13. Stealth and takedowns (`player_stealth.gd`, `PlayerStateTakedown`)

- **Stealth mode** (`stealth` key on foot or in cover): `in_stealth`, sneak speed 2.4 m/s, sneak pose,
  footstep `noise_radius` = `get_stealth_noise_radius()` (1.5 m; 1.2 m when walking; down to 0.9 m with the
  Stealth skill), `EventBus.player_state_changed("stealth")` for the HUD. Ends on sprinting, on the
  player's own `noise_emitted` of kind `gunshot` / `explosion` (a suppressed shot, kind
  `suppressed_gunshot`, radius 65 x 0.17 = 11 m from WEAPONS.md, keeps it), and on any state outside
  `STEALTH_KEEP_STATES` (vehicle, swim, ladder, ragdoll, dead ...).
- **visibility_factor** (every 0.2 s): posture (crouched x 0.78, sneaking x 0.72 -> 0.58 with the skill,
  hunkered in cover x 0.7, sprinting / in a vehicle = 1) x light (`lerp(0.5, 1, light)`; light =
  daylight, at night the nearest street lamp within 11 m - group `street_light` nodes + the world's
  `street_light` spawn points, refreshed every 4 s - or the weapon flashlight). Measured: day standing
  1.00, crouched 0.78, sneaking 0.69, sneaking at night 0.35, under a lamp at night 0.69.
- **Stealth XP**: 0.035 / s per unaware NPC (max 2) within 14 m while sneaking and moving; 0.4 per takedown.
- **Takedown target** (every 0.1 s while sneaking on foot / in the melee stance): a node in group `npc`
  within 1.6 m (planar, |dy| <= 0.7), the player inside its rear 140 deg (`-basis.z` is its facing), not
  dead / down / in a vehicle, not aware (`is_alerted != true` and `get_awareness() < 0.6`). Prompt
  "Takedown" (`melee_heavy`). Keys: `melee_heavy` with anything, or `fire` with fists / a melee weapon
  (not while aiming; a firearm's fire key still shoots).
- **The takedown**: the player slides 0.16 s into the grab position behind the victim and holds it still;
  knife = grab the head + stab (0.95 s) -> `KILL_DAMAGE` 400 (kill); fists = rear choke (1.25 s) ->
  knock-out; bat / crowbar / firearm = blow to the back of the head (0.85 s) -> knock-out. Damage:
  `Dmg.make(amount, "melee", player, chest, dir, {silent: true, takedown: true, stealth: true, knockout,
  knockout_seconds: 30, knockdown: <knock-out>, weapon_id})`, applied straight to the victim;
  `EventBus.hit_confirmed`; a quiet local sound only - **no `noise_emitted`**. Crime: NpcBase reports the
  harm itself (`assault` / `murder`); Wanted keeps it pending until a witness calls it in or police see
  the player within 1.1 s - verified: a civilian killed unseen gives no wanted level.

### Integration notes (cover / stealth)

- **AI**: `AiSenses` multiplies its awareness rate by `visibility_factor` AND by its own `in_stealth`
  (x 0.45) / `is_crouching` (x 0.6) / daylight factors, which `visibility_factor` already contains: sneaking
  at night is counted twice (0.35 x 0.45 x 0.6 x 0.45). Drop one side (see requests). Knocked-out NPCs
  should honour `info.knockout` / `knockout_seconds` (stay down, no panic on waking) - today NpcBase gets up
  after its normal 2.2 - 3.4 s knock-down. The witness hearing radius for `murder` (22 m) also applies to
  silent takedowns; `info.silent` could limit it to line of sight.
- **Police / Wanted**: `cop_assault` / `cop_murder` are `auto_known` (officer down on the radio), so a
  silent takedown of an officer always counts. That is the Wanted owner's call.
- **HUD**: show a stealth indicator (and optionally the noise ring) on `player_state_changed("stealth")`
  / `Player.in_stealth`; the "Takedown" prompt already goes through `UI.show_prompt`.
