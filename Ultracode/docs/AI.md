# AI module — NPC body, senses, pedestrians, civilian / staff / gang brains, combat helper

Owner: AI programmer (Wave 2). Contracts: `docs/ARCHITECTURE.md` 6.7, `docs/ARCHITECTURE_WAVE2.md` W2.2.
Everything is GDScript; neighbours (character visual, animator, ragdoll, weapon model, pickups, vehicles,
Wanted) are soft dependencies looked up by path / system name.

| File | Class | What it is |
|---|---|---|
| `gta/code/ai/npc_base.gd` | `NpcBase` | the BODY (CharacterBody3D, group `npc`, layer `Layers.NPC`) |
| `gta/code/ai/ai_senses.gd` | `AiSenses` | sight / hearing / stealth awareness of one NPC (`npc.senses`) + the AI game clock |
| `gta/code/ai/npc_archetype.gd` | `NpcArchetype` | Resource, Registry kind `npc_archetypes` |
| `gta/resources/registries/npc_registry.gd` | registrar | the 10 required archetypes |
| `gta/code/ai/ped_system.gd` | `PedSystem` | world system `peds`: population, spawning, the one loop that drives every NPC, stimulus dispatch |
| `gta/code/ai/brains/ai_brain_civilian.gd` | `AiBrainCivilian` | pedestrians (+ passive fallback for service NPCs) |
| `gta/code/ai/brains/ai_brain_staff.gd` | `AiBrainStaff` | shop staff |
| `gta/code/ai/brains/ai_brain_gang.gd` | `AiBrainGang` | gang members |
| `gta/code/ai/brains/ai_brain_combat.gd` | `AiBrainCombat` | reusable combat helper for ANY armed NPC (police too) |
| `gta/tests/ai_api.gd`, `ai_population.gd`, `ai_shots.gd` | tests | see section 8 |

---------------------------------------------------------------------------------------------------

## 1. Spawning

```gdscript
var npc := Game.spawn_npc("police_officer", pos, {"yaw": y, "brain": MyBrain, "persistent": true})
```
`PedSystem.spawn_npc(archetype_id, position, opts)` (= `Game.spawn_npc`). Options (W2.2 + extras):

| key | meaning |
|---|---|
| `yaw` | facing (radians, 0 = −Z) |
| `brain` | `Script` (instanced) or `Node`; default = the archetype's `brain_path` |
| `weapon` | weapon id (`""` = unarmed); default = rolled from the archetype's `weapons` table |
| `hostile` | gang: attack the player once alerted. Other brains may read `npc.hostile` |
| `persistent` | never auto-despawned or freed when dead; **the caller frees it** |
| `vehicle`, `seat` | spawn seated (instant `enter_vehicle`) |
| `appearance` | full `CharacterVisual` appearance dictionary (skips the random look) |
| extras: `visual` | CharacterVisual archetype for the random look (`business`, `beach`, `gang_b` …) |
| `activity` | `"talk"` (+ `partner`), `"sit"` (+ `bench` Transform3D, `bench_key`), `"idle"`, `"hang"` |
| `home`, `group` | gang: hang-out point and group id |
| `parent` | parent node (default `Game.get_entities_root()`) |

Non-persistent NPCs that someone else spawned are despawned beyond 110 m from the focus and freed
6 s after death (the ragdoll lives on by itself for 20 s). NPCs sitting in a vehicle are never auto-despawned.

### Archetypes (`Registry.get_def("npc_archetypes", id)`, `NpcArchetype`)

| id | faction | look | brain | hp / armour | weapon | notes |
|---|---|---|---|---|---|---|
| `civilian_m` / `civilian_f` | civilian | civilian / business / beach | civilian | 100 | – | ambient population |
| `civilian_tough` | civilian | rough civilian (boots, tank / vest / hoodie) | civilian | 130 | fists | fights back |
| `gang_member` | gang | `gang` / `gang_b` colours | gang | 115 | pistol 75 % / smg 25 % / bat | tracks the player |
| `shop_staff` | staff | staff outfit | staff | 100 | – | |
| `taxi_driver` | civilian | civilian | civilian | 100 | – | for the taxi system |
| `police_officer` | police | police outfit | **none** (POLICE passes `brain`) | 100 + 50 | pistol | accuracy 0.58 |
| `police_swat` | police | tactical outfit | **none** | 100 + 100 | carbine / assault rifle | accuracy 0.7 |
| `medic` / `firefighter` | medic / fire | uniforms | civilian (duty mode) | 100 / 120 | – | emergency system (next wave) |

Fields: `faction, groups, visuals, visual_weights, body, appearance_overrides, appearance_choices,
brain_path, max_health, armor, accuracy, walk/run/sprint_speed, sight_range, sight_fov_deg,
hearing_mult, bravery, fights_back, weapons, cash_min/max, alertness, tracks_player, ambient_weight, tags`.
An archetype without `brain_path` falls back to the civilian brain (police then stand calmly, never flee).

---------------------------------------------------------------------------------------------------

## 2. NpcBase — the body (W2.2, exact names)

```gdscript
var faction; var archetype_id; var health; var is_dead; var weapon_id; var current_vehicle
var brain; var state_tag; var accuracy
signal died(npc, killer);  signal damaged(npc, info)
set_brain(node)  move_to(target, "walk"|"run"|"sprint")  stop_moving()  is_moving()  has_arrived(tol := 1.2)
face_position(pos)  set_crouched(on)  set_weapon(id)  aim_at(pos)  stop_aiming()  fire_at(pos, acc_mult := 1.0) -> bool
melee(target)  can_see(node)  can_see_point(pos)  find_cover_from(threat, radius := 14.0) -> Vector3
enter_vehicle(v, seat := 0, instant := false)  exit_vehicle()  play_action(name, duration := 0.6)
panic(from)  cower()  surrender()  knock_down(impulse)  apply_damage(info)  get_target_position()  set_sim_tier(t)
```

Additions other modules can use:

| member | |
|---|---|
| `max_health`, `armor` (absorbs 70 % of bullet / explosion damage), `archetype`, `visual`, `animator`, `senses` | |
| `get_awareness() -> float`, `is_alerted` | stealth meter towards the player (section 3) |
| `walk_to(target, mode)` | ambient walking on the **WalkGraph** (crosswalks + waiting for traffic); `move_to` uses the **navigation mesh** (free targets: cover, chase, doors) and falls back to a straight line |
| `follow_path(points, mode)`, `flee_from(from, distance := 35, mode := "sprint")`, `get_move_target()`, `get_planar_velocity()`, `is_waiting_to_cross()`, `set_speed_mode(mode)`, `clear_face()` | movement helpers |
| `sit_at(seat_xform)`, `stand_normal()`, `get_pose()` (`""`, `cower`, `surrender`, `sit`) | poses |
| `gesture` (0..1 talking hands), `phone_pose` (hand at the ear), `look_target` (head look) | procedural layers |
| signal `threatened(npc, by)` + `threatened_time`, `threatened_by` | a firearm points at the NPC (about 6 Hz while it lasts) — robbery hook for shops |
| signals `knocked_down(npc)`, `got_up(npc)`; `is_down` | |
| `get_weapon_spec()`, `has_firearm()`, `is_melee_weapon()`, `get_ammo_in_mag()`, `get_mag_size()`, `is_reloading()`, `reload()`, `get_weapon_range()`, `get_muzzle_node()`, `get_muzzle_position()` | weapon state (NPCs have infinite reserve ammo, real magazines + reload times) |
| `last_cover_info` `{position, low, peek, normal}`, `release_cover()` | filled by `find_cover_from` |
| `on_vehicle_ejected(vehicle, exit_xform, impulse)`, `seat_index` | vehicle contract (VehicleBase calls it) |
| `kill(cause)` (no crime report), `heal(amount)`, `persistent`, `hostile`, `home_position`, `home_yaw`, `cash_carried`, `sim_tier`, `last_attacker`, `last_damage_info` | |

Behaviour notes:

- **Body**: capsule r 0.32 h 1.8 (1.2 crouched), `humanoid.tscn` + `CharacterVisual.randomize_appearance`
  (archetype look, district variants), `HumanoidAnimator` with `auto_process = false` advanced by the
  PedSystem at 30 / 8 / 2 Hz by tier. Weapon models through `WeaponModel.create(id).attach_to_holder(npc)`.
- **Movement**: tier 0 = `move_and_slide` with gravity, local avoidance (written into `npc.avoid` by the
  PedSystem), stuck recovery (skip node → side-step → give up with brain event `stuck`); tier 1/2 = kinematic
  glide along the path points (y from the path, no collision).
- **Crosswalks**: a WalkGraph path that steps from a sidewalk onto a crossing chain (`kinds == 1`) stops at the
  kerb and asks `PedSystem.is_crossing_clear(a, b)` every 0.4 s (moving vehicles that reach the crossing within
  4.5 s, or a car standing on it, block it); it gives up waiting after 9 s.
- **fire_at**: refuses while reloading, before the weapon's fire interval, and when the body still faces more than
  ~37° away (it turns first); then `Combat.npc_fire(self, spec, pos, accuracy * mult)`; an empty magazine starts
  `reload()` (spec reload time × 1.15, `reload` action, reload sound). Melee weapons swing instead (`melee`).
- **find_cover_from**: 16 rays from the NPC (obstacle faces turned away from the threat) + 10 rays from the threat
  through points around the NPC (just behind the first obstacle); each candidate needs ground, room for a crouched
  capsule, a navmesh point within 0.9 m (when a mesh exists) and NO line of sight from the threat to the crouched
  chest. Score = distance (+6 when running towards the threat, +1.5 for high cover, +9 if a squad mate claimed the
  spot within 1.2 m). At most 3 searches per physics frame (returns INF when the budget is used up — retry next think).
- **Damage** (`apply_damage`): armour, hit reaction + pain grunt, knock-down when `info.knockdown`, `damaged`
  signal, `EventBus.npc_injured`, brain events `damaged` / `vehicle_hit`. **Crime reports happen here, once**:
  harm by the player (`Dmg.caused_by_player`) → `assault` / `cop_assault` (max one per victim per 3 s, so a
  burst is one assault) or `murder` / `cop_murder` on the killing blow (once). Vehicle hits do NOT add an
  assault: `VehicleCrime` already reported `hit_and_run`; a kill by a vehicle is still `murder`.
  `direct_police_witness = true` for police victims or when an officer (group `police`, `can_see`) sees the player.
- **Knock-down**: `Ragdoll.spawn_from(visual, impulse)` (persistent while down), visual hidden, collision off,
  2.2–3.4 s, then the ragdoll pose is copied onto the skeleton and cross-fades through a crouch (1 s). A second
  impulse within 15 physics frames belongs to the same impact. Seated NPCs ignore knock-downs.
- **Death**: ragdoll (impulse from the hit, auto clean-up 20 s), weapon model hidden, `pickups.drop_from_npc(self)`
  (cash by faction + 65 % the weapon; idempotent, the pickups system also listens to `npc_died`), `died`,
  `EventBus.npc_died`. A driver killed in a seat stays slumped in it until ejected.

---------------------------------------------------------------------------------------------------

## 3. Senses (`npc.senses`, `AiSenses`)

- Sight: cone (`sight_fov_deg`, 150–160°) + range = `sight_range × clamp(Weather.get_visibility() / 160, 0.35, 1)
  × lerp(0.55, 1, WorldClock.get_daylight())`, line of sight via `Combat.has_line_of_sight` (target and its vehicle
  excluded). Inside 2.6 m the cone does not matter.
- Hearing: the PedSystem dispatches `EventBus.noise_emitted` to NPCs in range (`hearing_mult`, ×0.85 in rain);
  brains get `on_event("noise", {position, radius, kind, instigator, distance})`.
- Awareness (only `tracks_player` archetypes: police, gang, staff): grows while the player is seen —
  `alertness × (0.3 + 2.4 × closeness²)`, × light (0.45 at night), × 0.45 `in_stealth`, × 0.6 `is_crouching`,
  × `visibility_factor` (optional player member), × 0.55 in peripheral vision, +1.5 inside 3 m; footsteps / melee /
  horn add, gunshots / explosions by the player fill it. `awareness ≥ 1` → `is_alerted` (held 7 s, cleared below 0.3).
  Decays 0.12/s. `seconds_since_seen()`, `last_seen_position`, `last_heard_position`, `last_heard_kind`.
- `AiSenses.now()` = AI game clock (advanced once per physics frame, pause / time-scale aware).

---------------------------------------------------------------------------------------------------

## 4. Brains

Brain = any Node with `think(npc, delta)` (called at the tier rate: 10 / 3.3 / 1 Hz) and optional
`on_event(npc, event, data)`. Events the body sends: `spawned` (data = spawn opts), `damaged` `{info, attacker,
amount}`, `noise`, `saw_crime` `{crime, position, instigator, may_call}`, `threatened` `{by, duration}`, `bumped`
`{by}`, `vehicle_hit` `{info, vehicle, attacker}`, plus `panic` `{from}`, `knocked_down`, `got_up`, `died`,
`stuck`, `reset` (respawn), `talk_with` `{partner, duration}`, `ally_attacked` `{attacker, ally}` (gang).
Brains must ignore unknown events.

**Civilian** (`AiBrainCivilian`, `mode` / `get_mode_name()`): wander to walk-graph destinations 20–75 m away,
idle and look around, sit on benches (`PedSystem.claim_bench`, only where a bench model really stands), talking
pairs (turn-taking gestures, head look). Reactions: bumped → annoyed (turns, gestures; a tough local fights after
3 bumps); a firearm aimed at them → hands up 45 % / cower 25 % / flee 30 % (tough: hands up or flee); gunfire,
explosions → scream (`scream_m/f`, global rate limit, `noise_emitted("scream")` spreads fear) and flee along the
walk graph, 20–40 % cower first; punched → flee (tough: fight back with fists for up to 25 s).
**Witness flow**: `saw_crime` → `EventBus.crime_witnessed(crime, pos, npc)` → run to ≥ 24 m from the crime → phone
call 4 s (hand at the ear, `phone_open` sound) → `PedSystem.submit_witness_report()` → `Wanted.report_witnessed(crime,
pos, npc)`. Cancelled when the witness dies, is knocked down, is threatened again or the player comes within
6.5 m (running at them / within 2.5 m) — `note_witness_cancelled`. At most 2 callers per crime id at a time.
Medics, firefighters and brain-less police use the civilian brain in `duty` mode (stand, look around, never call).

**Staff** (`AiBrainStaff`): holds its post (spawn position + yaw = facing the counter), glances at customers within
7 m, hands up while threatened (back to the post 3 s after), cowers 3–5 s when shots are fired within 40 m, then
flees (or is damaged → flees) and walks back to the post after ~25 s of calm.

**Gang** (`AiBrainGang`, `provoke(npc, who, spread)`, `target`, `last_status`): groups of 3–4 at the world's `gang`
spawn points (spawned when the focus is within 105 m, released beyond 150 m when not fighting, respawn 4 min after a
group was wiped out). Provoked by damage, a weapon aimed at them (0.4 s), shots within 28 m by a non-gang shooter,
or — with `hostile` — by being alerted to the player within 32 m. Provocation spreads to the same group / gang
members within 35 m. Combat = `AiBrainCombat` (aggression 0.45–0.8). Calms down and walks home when the target is
dead or lost.

---------------------------------------------------------------------------------------------------

## 5. AiBrainCombat — interface for the police programmer

```gdscript
var combat := AiBrainCombat.new()                  # one per NPC (it keeps state)
func think(npc, delta):
    var status := combat.tick(npc, target, delta, {"lethal": true, "aggression": 0.6, "accuracy": 1.0,
            "use_cover": true, "hold_fire": false})
```

| rule | default | effect |
|---|---|---|
| `lethal` | true | false → never fires a gun; closes in to `engage_distance` (3 m) and aims (arrest stance) |
| `aggression` | 0.5 | cover wait 2.4 → 0.8 s, burst pauses, how early it advances / flanks when the target hides |
| `accuracy` | 1.0 | multiplier on `npc.accuracy` (first shots of a sighting ×0.6 → 1 over 1.5 s, fast targets ×0.75, firing on the move ×0.7) |
| `use_cover` | true | `find_cover_from(last_known, cover_radius)` |
| `hold_fire` | false | aim and take cover, never shoot |
| `melee` | = lethal | fists / melee weapons at close range |
| `engage_distance` | min(range/2, 18) | preferred distance in the open |
| `retreat_health` | 0.3 | once, retreat to a farther cover below this health ratio |
| `flank` | true | flank (±50–80° around the target at 8–14 m) instead of a straight advance |
| `cover_radius` | 14 | |

States: `engage` (no cover: aim, burst fire, strafe, keep distance) → `move_to_cover` (may shoot on the move when
aggressive) → `cover` (crouched, reload below 40 % magazine, leaves when the target sees the crouched body 3 checks
in a row) ⇄ `peek` (low cover: stand up; high cover: step to `last_cover_info.peek`; reaction delay 0.3–0.9 s, bursts
3–6 auto / 1–3 semi) → `advance` / `flank` when the target stays hidden (4–10 s by aggression) → `search` around the
last known position → returns `"lost"` after 22 s unseen. Also returns `"no_target"` (target null / dead),
`"busy"` (down, or seated without a drive-by weapon — seated NPCs with pistol / SMG shoot from the seat), `"melee"`,
`"hold"`, `"retreat"`, `"reload"`. Readable state: `last_known`, `sees_target`, `unseen_time`, `get_state_name()`;
`reset()` for a fresh target (also releases the claimed cover spot on `no_target`).

Police brains should also: set `npc.set_weapon("")` / `"pistol"` to holster / draw, call `Wanted.police_sighting(npc,
pos)` when `npc.can_see(player)`, and use `npc.get_awareness()` / `is_alerted` for searches.

---------------------------------------------------------------------------------------------------

## 6. PedSystem (`Game.get_system("peds")`)

```gdscript
spawn_npc(archetype_id, position, opts) -> Node3D      set_enabled(on)        clear_all(include_persistent := false)
get_npc_count() -> int   (alive managed NPCs)           get_ambient_count()    get_npcs() -> Array
set_focus_override(pos) / clear_focus_override()        get_focus()            set_density(mult)
get_target_count()      reset_for_respawn()             get_debug_info() -> Dictionary   stats
is_crossing_clear(a, b) -> bool                          claim_bench(npc, near, radius) -> {transform, key}
release_bench(key)      add_bench_point(xform) -> key    submit_witness_report(crime, pos, witness)
count_near(pos, radius) -> int  (living civilians; Wanted uses it for indirect reports)
witness_call_chance (0.85)                               focus_override, enabled, density_mult
```

- Population target = `min(40, round(28 × Settings.ped_density × density_mult))` × district density (downtown /
  midtown 1.0, waterfront 0.85, beach 0.8, residential 0.6, industrial 0.42, airport 0.25, hill 0.22, ocean 0)
  × night (0.45; 0.3 between 01:00 and 05:00) × rain (down to 0.45).
- Spawning: one attempt every 0.2 s on `WalkGraph.random_point(focus, 35, 90)`, preferably out of view (frustum +
  line of sight from the camera), not in water, not crowded; 10 % sit on a real bench nearby, 16 % talking pairs.
  Archetype mix and looks by district (`DISTRICT_MIX`, `DISTRICT_VISUAL`: business suits downtown, beach wear at the
  beach, more tough locals in the industrial district). Bodies come from a pool (16; 6 pre-built at setup).
- Despawn: every non-persistent NPC that is not seated and not part of a gang group beyond 110 m (also the ones
  other modules spawned, e.g. carjacked drivers); above the target (night / rain) one unseen ambient pedestrian
  farther than 40 m every 0.25 s. A seated NPC that is despawned (clear_all) leaves its seat first.
- Tiers every 0.25 s: 0 < 45 m (full), 1 < 110 m (glide, 8 Hz animation, think 3.3 Hz), 2 beyond (visual hidden).
- Stimuli: `noise_emitted` → `hear_noise`; `crime_committed` by the player → `notify_crime` for NPCs that hear it
  (`CRIME_HEAR`: gunfire 70 m, explosion 110 m, murder 22 m, assault 14 m …) or see the spot / the player;
  6 Hz: the player's aimed firearm (ray within 0.75 m + 2.5 %/m of the chest, ≤ 32 m, line of sight) →
  `notify_threatened`; the player running into a tier-0 NPC → `notify_bumped`; avoidance slice (10 NPCs per frame).
- Benches: the `bench` / `bench_park` instances of the props system (`find_instances`, `get_instance_transform`;
  a knocked-over bench (`get_instance_state != "idle"`) is not used), else the world's `bench` spawn points where a
  collider whose node name (or meta `prop_id`) contains `bench` stands, plus `add_bench_point()`. The sitting spot
  is 0.12 m in front of the bench origin, facing the bench's −Z (prop convention "sitter faces +Y in Blender").

---------------------------------------------------------------------------------------------------

## 7. Integration notes

- **POLICE**: spawn officers with `Game.spawn_npc("police_officer" | "police_swat", pos, {"brain": YourBrain,
  "persistent": true})`; build the brain on `AiBrainCombat` (section 5). `npc.threatened` / `threatened_time`
  also exist on officers. `report_witnessed(crime, pos, witness)` is called by `PedSystem.submit_witness_report`
  (with the contract stub it falls back to `report_crime(crime, pos, {"force": true})` + `EventBus.crime_reported`).
  Please ignore a witnessed crime that police already saw directly (the same crime is reported by `report_crime`
  first and by a witness 5–10 s later).
- **SHOPS**: staff = `spawn_npc("shop_staff", marker.origin, {"yaw": marker yaw, "persistent": true})`; robbery hook =
  `npc.threatened` signal / `npc.threatened_time >= 3.0`; the staff brain raises the hands by itself.
- **TRAFFIC / TAXI**: drivers can be real NPCs: `spawn_npc("civilian_m" | "taxi_driver", pos, {"vehicle": v,
  "seat": 0, "persistent": true})`, `npc.exit_vehicle()` → standing NPC beside the door (then `npc.persistent =
  false` hands it to the population, or `ambient = true` to count it). Vehicles that throw people out call
  `on_vehicle_ejected`.
- **WORLD / props**: benches are read from `props.find_instances("bench" | "bench_park")` at setup (the props
  system must set up before `peds`, as in BootManifest); `add_bench_point` for benches placed later.
- **TRAFFIC** already uses the body: `Game.spawn_npc(archetype, pos, {"appearance": ...})` for drivers that leave
  a car, brain events `damaged` (zero-damage melee for a carjacking) and `threatened`; those NPCs are not
  persistent, so the PedSystem despawns them beyond 110 m.
- **Respawn**: `peds.reset_for_respawn()` clears the transient population.
- **Admin**: `set_enabled`, `clear_all`, `set_density`, `get_debug_info()`.

---------------------------------------------------------------------------------------------------

## 8. Tests

```powershell
tools\godot.ps1 -Mode headless -Frames 14000 -TimeoutSec 400 -UserArgs '--test=ai_api','--test-timeout=380','--seed=3','--disable=world,environment,city,interactions,props,traffic,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
tools\godot.ps1 -Mode headless -Frames 7000 -TimeoutSec 400 -UserArgs '--test=ai_population','--test-timeout=380','--seed=11','--disable=props,traffic,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
tools\godot.ps1 -Mode window -Frames 540 -TimeoutSec 200 -UserArgs '--test=ai_shots','--ai_part=1','--test-timeout=120','--seed=5','--disable=props,traffic,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,respawn,debug'
tools\godot.ps1 -Mode window -Frames 540 -TimeoutSec 200 -UserArgs '--test=ai_shots','--ai_part=2','--test-timeout=120','--seed=5','--disable=props,traffic,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,respawn,debug'
```
(`props` is disabled only because `prop_system.gd` of a neighbour did not parse while these tests were written.)

| Test | Covers |
|---|---|
| `ai_api` (stage 400 m above the island with walls + a runtime-baked navmesh) | all 10 archetypes (looks, groups, weapons), every W2.2 member, move_to around a wall, run speed, facing, fire_at cadence / magazine / reload / damage, melee, find_cover_from (hidden point, INF on open ground), enter / exit vehicle (instant + walking to the door), spawn opts (appearance, brain Script, vehicle + seat, eject), civilians flee from a gunshot noise, the full witness flow (crime_witnessed → safe distance → 4 s call → Wanted) and its cancellation (killed / knocked down), gang cover + peek + hits + calming down, knock-down + get up, death signal + npc_died + pickups drop + clean-up, harm reports (one assault per burst, murder, cop_assault, armour, no assault for vehicle hits), staff hands up / post / cower / flee, bench sitting, crossing check with a moving car, a real car knocking an NPC down, player stimuli (bump → annoyed, aimed pistol → threatened, hostile gang alerted → combat), tough locals fight back |
| `ai_population` (real world, focus override downtown → midtown) | ambient count in [10, cap], follows the focus, tiers by distance, everybody on the walk network / above ground, density 1.5 → 40, frame cost (`AI_FRAME_COST`, `AI_PATH_COST` lines), crosswalk checks, fewer at night / in rain |
| `ai_shots` (windowed) | `qa/screenshots/ai_shots_sidewalk(_b).png`, `_talk`, `_bench`, `_panic(_b)`, `_gang_cover`, `_gang_firefight` |

---------------------------------------------------------------------------------------------------

## 9. Known limits

- No handheld phone model exists: the witness call is a hand-to-ear pose without a prop (missing asset).
- Bench sitting reuses the animator's `seated_car` pose with tuned feet / hand targets; it needs real bench props
  with identifiable colliders (none were placed by the props system while this was built; tested with the real
  `bench.glb` placed by the test).
- Crosswalk waiting checks moving vehicles only (no pedestrian signal phases); tested with a moving car on the test
  stage, not with the traffic system (which did not exist yet).
- Tier 1/2 NPCs glide without collision along their path; they are 45 m+ from the focus.
- Spawning a new body costs ~0.6–2 ms (pooled bodies less); the part library, brains and NPC weapon GLBs are
  loaded at boot (`peds setup` ≈ 0.1–0.23 s).
- Measured (headless, `ai_population`, 40 ambient + gang + staff ≈ 47 NPCs): physics loop 0.4–0.9 ms + animation
  loop 0.4–0.6 ms per frame on average; walk-graph paths ≈ 70 µs, navmesh paths ≈ 0.1–0.25 ms.
- Police archetypes ship without a police brain (POLICE module); without one they behave as calm bystanders.
