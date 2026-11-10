# HALCYON BAY — Wave 2 Contract Addendum

Read **after** `docs/ARCHITECTURE.md` (all of its rules still apply). This addendum defines the
cross-module contracts for the sandbox systems built in Wave 2. Module docs written in Wave 1
describe what already exists — read the ones you touch: `docs/WORLD.md`, `ENVIRONMENT.md`,
`PLAYER.md`, `CHARACTERS.md`, `VEHICLES.md`, `VEHICLE_KIT.md`, `WEAPONS.md`, `FX.md`, `UI.md`,
`AUDIO.md`, `BUILDING_KIT.md`, `LANDMARKS.md`, `PROPS_STREET.md`, `NATURE_ANIMALS.md`,
`MISC_PROPS.md`, `INTEGRATION_WAVE1.md`.

## W2.1 AI-driven vehicles — the `ai_controller` contract (TRAFFIC, POLICE, AI, PLAYER)

Any system that puts an AI driver into a vehicle must
`vehicle.set_meta("ai_controller", self)` and set `vehicle.driver` to the driver node (a real
NPC or a lightweight seated dummy), and must implement:

```gdscript
## Stop controlling `vehicle`. For reasons "carjacked" / "abandon" / "crash" the driver leaves the
## car as a real NPC beside the driver door (returned; may be null). "despawn" / "destroyed"
## just clean up. After the call the vehicle has no ai_controller meta and driver == null.
func release_vehicle(vehicle: Node3D, reason: String) -> Node3D
```

Carjacking is owned by PLAYER: entering a vehicle whose `driver` is someone else plays a short
pull-out transition, calls `controller.release_vehicle(vehicle, "carjacked")`, emits
`EventBus.vehicle_stolen(vehicle, player, true)` and reports
`Wanted.report_crime("vehicle_theft" | "police_vehicle_theft", pos, {"victim": npc})`.
Taking an empty civilian vehicle is not a crime; taking any police vehicle is
(`police_vehicle_theft`, serious). A vehicle the player has driven gets `owner_tag = "player"`.

## W2.2 NPC body / brain layering (AI ↔ POLICE ↔ TRAFFIC ↔ SHOPS)

`NpcBase` (AI module) is the BODY: movement, senses, weapon handling, animation, damage, death.
Decision logic lives in a BRAIN node: any `Node` with `func think(npc: Node, delta: float)`
(called at the NPC's simulation-tier rate) and optional
`func on_event(npc: Node, event: String, data: Dictionary)` (events: `"damaged"`, `"noise"`,
`"saw_crime"`, `"threatened"`, `"bumped"`, `"vehicle_hit"`, `"spawned"`). AI ships brains for
civilians, staff and gang members in `code/ai/brains/`; POLICE ships officer / SWAT brains in
`code/police/`. Exact body API (other modules call these — keep the names):

```gdscript
var faction: String; var archetype_id: String; var health: float; var is_dead: bool
var weapon_id: String; var current_vehicle: Node3D; var brain: Node; var state_tag: String
var accuracy: float          # 0..1 base aim quality
signal died(npc: Node3D, killer: Node)
signal damaged(npc: Node3D, info: Dictionary)
func set_brain(brain_node: Node) -> void
func move_to(target: Vector3, speed_mode: String = "walk") -> void   # "walk" | "run" | "sprint"
func stop_moving() -> void
func is_moving() -> bool
func has_arrived(tolerance: float = 1.2) -> bool
func face_position(pos: Vector3) -> void
func set_crouched(on: bool) -> void
func set_weapon(id: String) -> void                    # "" = unarmed; shows the model in hand
func aim_at(pos: Vector3) -> void
func stop_aiming() -> void
func fire_at(target_pos: Vector3, accuracy_mult: float = 1.0) -> bool   # obeys fire rate / magazine / reload; true if a shot left the barrel
func melee(target: Node3D) -> void
func can_see(target: Node3D) -> bool                   # cone + range + line of sight
func can_see_point(pos: Vector3) -> bool
func find_cover_from(threat_pos: Vector3, search_radius: float = 14.0) -> Vector3   # Vector3.INF if none
func enter_vehicle(vehicle: Node3D, seat: int = 0, instant: bool = false) -> void
func exit_vehicle() -> void
func play_action(action: String, duration: float = 0.6) -> void
func panic(from: Vector3) -> void;  func cower() -> void;  func surrender() -> void
func knock_down(impulse: Vector3) -> void
func apply_damage(info: Dictionary) -> void
func get_target_position() -> Vector3
func set_sim_tier(tier: int) -> void
```

`PedSystem.spawn_npc(archetype_id, position, opts)` (= `Game.spawn_npc`): opts
`{"yaw": float, "brain": Script | Node, "weapon": String, "hostile": bool, "persistent": bool
(never auto-despawned; the caller frees it), "vehicle": Node3D, "seat": int, "appearance": Dictionary}`.
Required archetype ids (Registry kind `npc_archetypes`): `civilian_m, civilian_f, civilian_tough,
gang_member, shop_staff, taxi_driver, police_officer, police_swat, medic, firefighter`.
NPCs killed or hurt by the player: the module that detects it reports the crime
(`assault`, `murder`, `cop_assault`, `cop_murder`) exactly once, in `NpcBase.apply_damage`.

## W2.3 Wanted system additions (POLICE owns `wanted_system.gd`)

```gdscript
func report_witnessed(crime_id: String, position: Vector3, witness: Node) -> void   # a civilian finished calling it in
func bust() -> void                    # arrest completed: emits EventBus.player_busted, then clear("busted")
func is_player_arrestable() -> bool    # on foot or stopped, not fired / attacked for a few seconds
func note_vehicle_change(vehicle: Node3D) -> void    # player swapped vehicle while unseen
func note_appearance_change() -> void                # wardrobe / clothing change while unseen
func force_pursuit(position: Vector3) -> void
func get_level_config(lvl: int) -> Dictionary        # {"officers", "cruisers", "swat_vans", "heli", "roadblocks", "lethal", "respawn_interval", "search_radius", "escape_seconds"}
var time_in_state: float; var time_since_last_crime: float
```
Level intent: 1★ nearby patrol investigates and tries to ARREST (non-lethal unless the player
is armed and aiming / attacks); 2★ armed officers, more cruisers, lethal force; 3★ roadblocks +
helicopter (Wave 3); 4★ SWAT; 5★ maximum sustained response. Escape only through real loss of
line of sight: PURSUIT → SEARCH (stars flash, search area around `last_known_position`) →
cleared after `escape_seconds` unseen; any sighting resumes PURSUIT.

## W2.4 City API (`Game.get_system("city")`, WORLD city builder)

```gdscript
func has_landmark(landmark: String) -> bool
func get_landmark_node(landmark: String) -> Node3D
func get_landmark_transform(landmark: String) -> Transform3D              # building origin, world space
func has_landmark_marker(landmark: String, marker: String) -> bool
func get_landmark_marker(landmark: String, marker: String) -> Transform3D # world space (from the manifests' "markers")
func get_landmark_markers(landmark: String) -> Dictionary                 # marker name -> Transform3D
func get_buildings() -> Array[Dictionary]                                 # {id, lot_id, category, transform, footprint: Vector2, height}
```
The dressing system (`props` system) adds: `spawn_prop(prop_id, xform) -> Node3D`,
`get_prop_def(prop_id) -> Dictionary`. Ladders: any `Node3D` in group `ladder` with its origin
at the foot of the ladder, the climber facing local −Z, and `get_meta("height")` in metres.
Cover needs no markers: PLAYER detects it geometrically (ray / shape casts against
`Layers.WORLD | VEHICLE | PROP`), low cover ≈ 0.9–1.3 m, high cover > 1.6 m.

## W2.5 Death and arrest flow (`respawn` system, PLAYER)

`EventBus.player_died` → original banner ("DOWN"), brief slow motion, fade, respawn at the
hospital `Respawn` marker (fallback `Game.get_location("hospital")`), small medical fee,
`Wanted.clear("died")`, a few in-game hours pass. `EventBus.player_busted` → banner
("ARRESTED"), fade, respawn at `police_station`, fine + ammunition confiscated (weapons kept).
Every system with transient chase state implements `reset_for_respawn()` (called by `respawn`).

## W2.6 Shops and economy (ECONOMY: `shops` system)

Registry kind `shops`: `{id, landmark, kind: "weapons"|"clothing"|"barber"|"general"|"mod_garage"|
"gas", display_name, screen, stock}`. A shop creates `Interactable`s at the landmark markers
(`Use_Counter` …), a staff NPC at `Staff` (archetype `shop_staff`, persistent), and opens its
UI screen with `{"shop_id": id}`. All purchases go through `Game.spend(price)` and emit
`EventBus.item_purchased(kind, id, price)`. Robbery hook: threatening staff with a firearm for
~3 s makes them hand over a cash pickup and reports `Wanted.report_crime("robbery", …)`.
Admin "unlock all" sets `Game.flags["free_shopping"] = true` (prices become 0).

## W2.7 Garages and personal vehicles (VEHICLE: `garage` system)

```gdscript
func store_vehicle(vehicle: Node3D) -> bool           # removes it from the world, keeps spec / colours / mods / health
func get_stored() -> Array[Dictionary]
func retrieve_vehicle(index: int, xform: Transform3D) -> Node3D
func get_capacity() -> int
func set_personal_vehicle(vehicle: Node3D) -> void;  func get_personal_vehicle() -> Node3D
func deliver_personal_vehicle(near: Vector3) -> Node3D   # phone service (Wave 3)
```
Persisted through SaveSystem (`register_provider("garage", self)`). Garage use points: the
`safehouse` landmark (`Garage_Spot` marker) and `parking_garage`.

## W2.8 Vehicle classes

`VehicleManager` instantiates the script by `VehicleSpec.vehicle_class`: `car` → `car.gd`,
`bike` / `bicycle` → `bike.gd`, `boat` → `boat.gd`, `heli` → `helicopter.gd`,
`plane` → `plane.gd` (fixed paths under `code/vehicles/`, looked up with `ResourceLoader.exists`).
Aircraft / boat inputs use the `air_*` actions in `InputSetup` (keyboard: W/S power, A/D yaw,
arrow keys or numpad 8/5/4/6 pitch / roll, G gear); mouse may add pitch / roll. Boats and
swimmers read the water surface from `Game.get_system("environment").get_wave_height(x, z)`.
