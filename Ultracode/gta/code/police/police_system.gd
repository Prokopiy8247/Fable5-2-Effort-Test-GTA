class_name PoliceSystem
extends Node3D
## World system "police" (ARCHITECTURE 6.9, ARCHITECTURE_WAVE2 W2.1 / W2.2 / W2.3, spec 18 / 18A / 19).
## The dispatcher and the ONE manager loop of the police module:
##   * keeps the number of foot officers, cruisers (police_cruiser + two police_officer NPCs) and SWAT
##     vans (swat_van + four police_swat) that Wanted.get_level_config(level) asks for, within the
##     caps of ARCHITECTURE section 10 (<= 16 police NPCs, <= 8 driven police vehicles);
##   * spawns them out of the player's view (lanes 80-160 m away, outside the camera frustum or behind
##     buildings, no vehicle in the way) so they arrive by road with sirens;
##   * ambient presence at 0 stars: patrol cruisers around the player, beat officers near the police
##     station / downtown plaza, parked cruisers in front of the station;
##   * the police helicopter (PoliceHeli, 3 stars+, config "heli"): spawned out of view at altitude,
##     orbits / tracks the player, sweeps the search area with its searchlight, marksman at 4-5 stars;
##     replaced after a cool-down when shot down, flies off when the level clears;
##   * ticks every PoliceVehicleAi (15 Hz near, 6 Hz far), builds / cleans roadblocks (3 stars+) and
##     checks spike strips (4 stars+), spreads search points, arbitrates the arrest, throttles
##     sightings and "resisting" reports, stands units down when the level clears and despawns them
##     out of view.
## API: spawn_unit(kind, near), get_units(), clear_units(), set_enabled(on), adopt_patrol(vehicle),
## reset_for_respawn(), get_debug_info(). Units are in group "police" (NPCs, drawn by the minimap);
## police vehicles of this system are in group "police_vehicle".

const OFFICER_BRAIN := preload("res://gta/code/police/police_officer_brain.gd")
const SWAT_BRAIN := preload("res://gta/code/police/police_swat_brain.gd")

const MAX_OFFICERS := 16
const MAX_VEHICLES := 8
const MAX_ROADBLOCKS := 2
const SPAWN_MIN := 80.0
const SPAWN_MAX := 160.0
const RESPONSE_RANGE := 230.0        ## units farther than this do not count for the level's targets
const AMBIENT_CRUISERS := 2
const BEATS_PER_ANCHOR := 2
const BEAT_ANCHORS: Array[String] = ["police_station", "downtown_plaza"]
const BEAT_RADIUS := 190.0
const STATION_CARS := 2
const STATION_RADIUS := 170.0
const SIGHTING_THROTTLE := 0.15
const RESIST_COOLDOWN := 12.0
const BRANDISH_COOLDOWN := 10.0
const DEAD_FREE_TIME := 25.0
const ROADBLOCK_LIFETIME := 100.0
const NEAR_TICK_DIST := 90.0
const TRAIL_STEP := 2.5
const TRAIL_MAX := 90
const HELI_DELAY := 6.0              ## after the level first asks for air support (the call goes out)
const HELI_REPLACE := 70.0           ## after a helicopter was shot down
const HELI_SPAWN_MIN := 270.0
const HELI_SPAWN_MAX := 330.0
const HELI_TICK := 0.1

var enabled: bool = true
var roads: Object = null                  ## World.roads (RoadGraph), untyped
var walk: Object = null                   ## World.walk (WalkGraph), untyped
var sight_factor: float = 1.0             ## weather visibility x daylight (vehicle sight range)
var trail := PackedVector3Array()        ## the player's recent path while driving (oldest first)
var units: Array[PoliceVehicleAi] = []
var officers: Array[Node3D] = []          ## every police NPC this system spawned (until freed)
var roadblocks: Array[PoliceRoadblock] = []
var abandoned: Array[Node3D] = []         ## our police vehicles without a crew
var station_cars: Array[Node3D] = []
var heli: PoliceHeli = null               ## the police helicopter unit (at most one)
var ground_dispatch: bool = true          ## tests / admin: false = no new ground units or roadblocks (air only)
var stats := {"cruisers": 0, "vans": 0, "officers": 0, "roadblocks": 0, "sightings": 0, "busts": 0,
		"resisting": 0, "brandishing": 0, "despawned_units": 0, "despawned_officers": 0, "spawn_fail": 0,
		"spike_pops": 0, "relocated": 0, "npc_threats": 0, "helis": 0, "helis_down": 0, "tick_us": 0.0,
		"tick_us_max": 0.0}

var _clock: float = 0.0
var _episode_t: float = 0.0
var _spawn_cd: float = 0.0
var _ambient_cd: float = 3.0
var _beat_cd: float = 2.0
var _roadblock_cd: float = 0.0
var _dispatch_t: float = 0.0
var _slow_t: float = 0.0
var _spike_t: float = 0.0
var _sighting_cd: float = 0.0
var _resist_cd: float = 0.0
var _brandish_cd: float = 0.0
var _plan_tokens: int = 1
var _search_idx: int = 0
var _arrester: Node3D = null
var _arrest_claim_t: float = -100.0
var _dead_t: Dictionary = {}              ## npc instance id -> clock of death
var _rng := RandomNumberGenerator.new()
var _ray_q: PhysicsRayQueryParameters3D = null
var _shape_q: PhysicsShapeQueryParameters3D = null
var _view_q: PhysicsRayQueryParameters3D = null
var _static_q: PhysicsRayQueryParameters3D = null
var _sphere := SphereShape3D.new()
var _roadblock_points: Array[Transform3D] = []
var _prewarm_left: Array[String] = []
var _prewarmed: Array[Resource] = []      ## keeps the prewarmed GLBs cached
var _heli_cd: float = 0.0
var _heli_wrecks: Array[Node3D] = []
var _heli_wreck_t: Dictionary = {}        ## wreck instance id -> clock of the crash
var _warned_peds: bool = false


func _ready() -> void:
	name = "PoliceSystem"
	_rng.seed = int(Game.rng.randi()) ^ 0x9e3779b9


## Assets the first dispatch would otherwise load on the main thread (a visible hitch mid-chase).
const PREWARM: Array[String] = ["res://gta/generated/models/vehicles/police_cruiser.glb",
		"res://gta/generated/models/vehicles/swat_van.glb", "res://gta/generated/models/misc/spike_strip.glb",
		"res://gta/generated/models/vehicles/heli_police.glb",
		"res://gta/generated/models/props/roadblock_police.glb"]


func setup() -> void:
	for path in PREWARM:
		if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path) == OK:
			_prewarm_left.append(path)
	EventBus.wanted_level_changed.connect(_on_level_changed)
	EventBus.wanted_cleared.connect(_on_cleared)
	EventBus.vehicle_destroyed.connect(_on_vehicle_destroyed)
	EventBus.vehicle_stolen.connect(_on_vehicle_stolen)
	EventBus.player_entered_vehicle.connect(_on_player_entered_vehicle)


func _ensure_world() -> bool:
	if roads != null and walk != null:
		return true
	var w := Game.world
	if w == null or not is_instance_valid(w):
		return false
	var r: Variant = w.get("roads")
	if r is Object and r != null:
		roads = r as Object
	var wk: Variant = w.get("walk")
	if wk is Object and wk != null:
		walk = wk as Object
	if _roadblock_points.is_empty() and w.has_method("get_spawn_points"):
		_roadblock_points = w.call("get_spawn_points", "roadblock")
	return roads != null


# =================================================================================================
# public API
# =================================================================================================

## Spawns one unit near `near`: "officer" (foot, returns the NPC), "cruiser" / "swat" (returns the
## vehicle), "roadblock" (returns one of its cruisers), "heli" (returns the helicopter; the existing
## one when it is already up). Out of view when possible. Respects the caps; null when nothing could
## be placed.
func spawn_unit(kind: String, near: Vector3) -> Node3D:
	if not enabled or not _ensure_world():
		return null
	match kind:
		"officer":
			if _alive_officer_count() >= MAX_OFFICERS:
				return null
			var p := _hidden_walk_point(near, 30.0, 70.0)
			if p == Vector3.INF and walk != null:
				p = walk.call("random_point", near, 12.0, 45.0)
			if p == Vector3.INF:
				return null
			var o := spawn_officer("police_officer", p, "foot", null, 0)
			if o != null:
				EventBus.police_unit_spawned.emit(o, "officer")
			return o
		"cruiser", "swat":
			var v := _spawn_vehicle_unit(kind, near, 4 if kind == "swat" else 2, Wanted.level <= 0, true)
			if v == null:
				v = _spawn_vehicle_unit(kind, near, 4 if kind == "swat" else 2, Wanted.level <= 0, false)
			return v
		"roadblock":
			var rb := _place_roadblock_near(near)
			if rb != null and not rb.cars.is_empty():
				return rb.cars[0]
			return null
		"heli":
			if heli != null and heli.is_valid() and not heli.is_down():
				heli.resume()
				return heli.vehicle
			return _spawn_heli(near, Transform3D(), false)
	push_warning("PoliceSystem.spawn_unit: unknown kind '%s'" % kind)
	return null


## Admin / tests: spawns a unit exactly at `xf` (no view rules; caps still apply). kind: "officer",
## "cruiser", "swat", "heli" (in the air at xf, rotor at speed). Returns the NPC / vehicle or null.
func spawn_unit_at(kind: String, xf: Transform3D) -> Node3D:
	if not enabled or not _ensure_world():
		return null
	if kind == "officer":
		if _alive_officer_count() >= MAX_OFFICERS:
			return null
		var o := spawn_officer("police_officer", xf.origin, "foot", null, 0)
		if o != null:
			EventBus.police_unit_spawned.emit(o, "officer")
		return o
	if kind == "heli":
		if heli != null and heli.is_valid() and not heli.is_down():
			return null
		return _spawn_heli(xf.origin, xf, true)
	if kind != "cruiser" and kind != "swat":
		return null
	return _spawn_vehicle_unit_at(kind, xf, 4 if kind == "swat" else 2, Wanted.level <= 0)


## Every live police unit of this system: driven vehicles + officers not sitting in a vehicle.
func get_units() -> Array:
	var out: Array = []
	for u in units:
		if u.is_valid():
			out.append(u.vehicle)
	for o in officers:
		if is_instance_valid(o) and not bool(o.get("is_dead")) and o.get("current_vehicle") == null:
			out.append(o)
	if heli != null and heli.is_valid() and not heli.is_down():
		out.append(heli.vehicle)
	return out


## Removes every unit, roadblock and parked police car of this system (and its officers).
func clear_units() -> void:
	for u: PoliceVehicleAi in units.duplicate():
		_despawn_unit(u)
	units.clear()
	for rb in roadblocks:
		rb.cleanup()
	roadblocks.clear()
	for o: Node3D in officers.duplicate():
		_free_officer(o)
	officers.clear()
	for v: Node3D in abandoned + station_cars:
		_despawn_vehicle(v)
	abandoned.clear()
	station_cars.clear()
	_despawn_heli()
	for w: Node3D in _heli_wrecks:
		_despawn_vehicle(w)
	_heli_wrecks.clear()
	_heli_wreck_t.clear()
	_dead_t.clear()
	_arrester = null


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		clear_units()


## Turns an existing police vehicle (no driver, not the player's) into a patrol unit with a crew of
## two. Returns true on success.
func adopt_patrol(vehicle: Node3D) -> bool:
	if not enabled or vehicle == null or not is_instance_valid(vehicle) or not (vehicle is RigidBody3D):
		return false
	if bool(vehicle.get("destroyed")) or bool(vehicle.get("is_player_driven")) or vehicle == Game.get_player_vehicle():
		return false
	for u in units:
		if u.vehicle == vehicle:
			return true
	if vehicle.has_meta("ai_controller"):
		var ctrl: Variant = vehicle.get_meta("ai_controller")
		if ctrl is Object and is_instance_valid(ctrl) and (ctrl as Object).has_method("release_vehicle"):
			(ctrl as Object).call("release_vehicle", vehicle, "despawn")
	if vehicle.get("driver") != null:
		return false
	if _alive_officer_count() + 2 > MAX_OFFICERS or _driven_count() >= MAX_VEHICLES:
		return false
	abandoned.erase(vehicle)
	station_cars.erase(vehicle)
	var arch := "police_swat" if str(vehicle.get("spec_id")) == "swat_van" else "police_officer"
	var crew: Array = []
	for s in 2:
		var o := spawn_officer(arch, vehicle.global_position, "crew", vehicle, s)
		if o != null:
			crew.append(o)
	if crew.is_empty():
		return false
	vehicle.set("owner_tag", "police")
	return _make_unit(vehicle as RigidBody3D, "swat" if arch == "police_swat" else "cruiser", crew, Wanted.level <= 0) != null


func reset_for_respawn() -> void:
	clear_units()
	_episode_t = 0.0
	_spawn_cd = 0.0
	_ambient_cd = 4.0
	_beat_cd = 3.0
	_roadblock_cd = 0.0
	_resist_cd = 0.0
	_brandish_cd = 0.0
	_heli_cd = 0.0


func get_debug_info() -> Dictionary:
	var modes := {}
	for u in units:
		if u.is_valid():
			var m := u.get_mode_name()
			modes[m] = int(modes.get(m, 0)) + 1
	var omodes := {}
	for o in officers:
		if is_instance_valid(o) and not bool(o.get("is_dead")):
			var b: Variant = o.get("brain")
			if b is Node and is_instance_valid(b) and (b as Node).has_method("get_mode_name"):
				var m2 := str((b as Node).call("get_mode_name"))
				omodes[m2] = int(omodes.get(m2, 0)) + 1
	var spikes := 0
	for rb in roadblocks:
		spikes += rb.spikes.size()
	return {"enabled": enabled, "level": Wanted.level, "units": units.size(), "unit_modes": modes,
			"officers_alive": _alive_officer_count(), "officer_modes": omodes, "roadblocks": roadblocks.size(),
			"spike_strips": spikes, "abandoned": abandoned.size(), "station_cars": station_cars.size(),
			"episode_t": _episode_t, "ground_dispatch": ground_dispatch,
			"heli": heli.get_debug_info() if heli != null and heli.is_valid() else {}, "heli_cd": _heli_cd,
			"stats": stats.duplicate()}


# =================================================================================================
# services for brains / vehicle AIs
# =================================================================================================

## A police unit has the player in sight (after its recognition delay). Throttled.
func report_sighting(observer: Node, pos: Vector3, force: bool = false) -> void:
	if not enabled:
		return
	if _sighting_cd > 0.0 and not force:
		return
	_sighting_cd = SIGHTING_THROTTLE
	stats["sightings"] = int(stats["sightings"]) + 1
	Wanted.police_sighting(observer, pos)


func take_plan_token() -> bool:
	if _plan_tokens > 0:
		_plan_tokens -= 1
		return true
	return false


## One officer at a time cuffs the suspect; a clearly closer officer may take over.
func claim_arrest(npc: Node3D) -> bool:
	if _arrester == npc:
		_arrest_claim_t = _clock
		return true
	if _arrester != null and is_instance_valid(_arrester) and not bool(_arrester.get("is_dead")) \
			and _clock - _arrest_claim_t < 0.8:
		var pp := Game.get_player_position()
		if _flat(npc.global_position, pp) + 3.0 >= _flat(_arrester.global_position, pp):
			return false
	_arrester = npc
	_arrest_claim_t = _clock
	return true


func arrest_in_progress(npc: Node3D) -> bool:
	return _arrester != null and is_instance_valid(_arrester) and _arrester != npc and _clock - _arrest_claim_t < 0.6


func release_arrest(npc: Node3D) -> void:
	if _arrester == npc:
		_arrester = null


func complete_arrest(npc: Node3D) -> void:
	release_arrest(npc)
	if Wanted.level > 0 and Wanted.is_player_arrestable():
		stats["busts"] = int(stats["busts"]) + 1
		Wanted.bust()


## The suspect runs from an arrest: escalation through the Wanted crime path (rate-limited).
func report_resisting(npc: Node3D) -> void:
	if _resist_cd > 0.0 or Wanted.level <= 0:
		return
	_resist_cd = RESIST_COOLDOWN
	stats["resisting"] = int(stats["resisting"]) + 1
	Wanted.report_crime("resisting", npc.global_position, {"instigator": Game.player, "direct_police_witness": true})


## A firearm aimed at an officer at 0 stars.
func report_brandishing(npc: Node3D) -> void:
	if _brandish_cd > 0.0:
		return
	_brandish_cd = BRANDISH_COOLDOWN
	stats["brandishing"] = int(stats["brandishing"]) + 1
	Wanted.note_player_attack()
	Wanted.report_crime("disturbance", Game.get_player_position(),
			{"instigator": Game.player, "victim": npc, "direct_police_witness": true})


## An NPC (gang member ...) shot at an officer near `pos`: every officer on foot within `radius`
## fights back (officers only target the player otherwise).
func alert_npc_threat(attacker: Node3D, pos: Vector3, radius: float) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	stats["npc_threats"] = int(stats.get("npc_threats", 0)) + 1
	for o in officers:
		if not is_instance_valid(o) or bool(o.get("is_dead")) or o.get("current_vehicle") != null:
			continue
		if _flat(o.global_position, pos) > radius:
			continue
		var b: Variant = o.get("brain")
		if b is Node and is_instance_valid(b) and (b as Node).has_method("set_npc_threat"):
			(b as Node).call("set_npc_threat", attacker)


## Search point for a foot officer: spread around Wanted.search_center (golden-angle sectors),
## snapped to the walk network.
func get_search_point(_npc: Node3D) -> Vector3:
	var c: Vector3 = Wanted.search_center
	var r := maxf(float(Wanted.search_radius), 20.0)
	_search_idx += 1
	var ang := float(_search_idx) * 2.39996 + _rng.randf() * 0.5
	var rad := r * lerpf(0.12, 0.75, _rng.randf())
	var p := c + Vector3(sin(ang), 0.0, cos(ang)) * rad
	if walk != null:
		var q: Vector3 = walk.call("get_nearest_point", p)
		if q != Vector3.INF and _flat(q, p) < 30.0:
			p = q
	p.y = _ground(p)
	return p


## Lane point inside the search area for a cruiser.
func get_search_lane_point(_unit: PoliceVehicleAi) -> Vector3:
	var c: Vector3 = Wanted.search_center
	if roads == null:
		return c
	var r := maxf(float(Wanted.search_radius) * 0.85, 25.0)
	var res: Dictionary = roads.call("random_lane_point", c, 0.0, r)
	if res.is_empty():
		return c
	return (res["transform"] as Transform3D).origin


func random_walk_point(center: Vector3, dmin: float, dmax: float) -> Vector3:
	if walk != null:
		var p: Vector3 = walk.call("random_point", center, dmin, dmax)
		if p != Vector3.INF:
			return p
	var a := _rng.randf() * TAU
	var q := center + Vector3(sin(a), 0.0, cos(a)) * _rng.randf_range(dmin, maxf(dmax, dmin + 0.1))
	q.y = _ground(q)
	return q


## Line of sight on Layers.SIGHT_MASK. `exclude`: nodes (CollisionObject3D) that must not block.
func los(from: Vector3, to: Vector3, exclude: Array = []) -> bool:
	if not is_inside_tree():
		return false
	if _ray_q == null:
		_ray_q = PhysicsRayQueryParameters3D.new()
		_ray_q.collision_mask = Layers.SIGHT_MASK
	var ex: Array[RID] = []
	for e: Variant in exclude:
		if e != null and is_instance_valid(e) and e is CollisionObject3D:
			ex.append((e as CollisionObject3D).get_rid())
	_ray_q.exclude = ex
	_ray_q.from = from
	_ray_q.to = to
	return get_world_3d().direct_space_state.intersect_ray(_ray_q).is_empty()


## Line of sight against static geometry only (buildings, terrain, static props): can a car drive
## straight there?
func los_static(from: Vector3, to: Vector3) -> bool:
	if not is_inside_tree():
		return false
	if _static_q == null:
		_static_q = PhysicsRayQueryParameters3D.new()
		_static_q.collision_mask = Layers.WORLD
	_static_q.from = from
	_static_q.to = to
	var hit := get_world_3d().direct_space_state.intersect_ray(_static_q)
	if hit.is_empty():
		return true
	var nrm: Vector3 = hit.get("normal", Vector3.UP)
	return nrm.y > 0.75          # only ground in the way (a crest), not a wall


## Spawns one police NPC (seated in `vehicle` when given). role: "crew", "foot", "beat", "roadblock".
func spawn_officer(arch: String, pos: Vector3, role: String, vehicle: Node3D, seat: int) -> Node3D:
	if not Game.has_system("peds"):
		if not _warned_peds:
			_warned_peds = true
			push_warning("PoliceSystem: no peds system - officers cannot be spawned")
		return null
	var swat := arch == "police_swat"
	var opts := {"brain": SWAT_BRAIN if swat else OFFICER_BRAIN, "persistent": true,
			"yaw": _rng.randf() * TAU}
	if swat:
		opts["weapon"] = "carbine" if _rng.randf() < 0.55 else "smg"
	elif role == "beat":
		opts["weapon"] = ""
	if vehicle != null and is_instance_valid(vehicle):
		opts["vehicle"] = vehicle
		opts["seat"] = seat
	var npc := Game.spawn_npc(arch, pos, opts)
	if npc == null:
		return null
	var b: Variant = npc.get("brain")
	if b is Node and is_instance_valid(b):
		(b as Node).set("system", self)
		(b as Node).set("role", role)
		if role == "beat":
			(b as Node).set("post", pos)
	officers.append(npc)
	stats["officers"] = int(stats["officers"]) + 1
	return npc


# =================================================================================================
# loop
# =================================================================================================

func _physics_process(delta: float) -> void:
	if not enabled or not Game.is_ready:
		return
	if not _ensure_world():
		return
	var t0 := Time.get_ticks_usec()
	_clock += delta
	_plan_tokens = 1
	_sighting_cd -= delta
	_resist_cd -= delta
	_brandish_cd -= delta
	_ambient_cd -= delta
	_beat_cd -= delta
	_roadblock_cd -= delta
	if Wanted.level > 0:
		_episode_t += delta
	_update_trail()
	_tick_units(delta)
	_tick_heli(delta)
	_dispatch_t -= delta
	if _dispatch_t <= 0.0:
		_dispatch_t = 0.5
		_dispatch(0.5)
	_slow_t -= delta
	if _slow_t <= 0.0:
		_slow_t = 1.0
		_slow_step(1.0)
	_spike_t -= delta
	if _spike_t <= 0.0:
		_spike_t = 0.1
		_spike_step()
	var us := float(Time.get_ticks_usec() - t0)
	stats["tick_us"] = lerpf(float(stats["tick_us"]), us, 0.05)
	stats["tick_us_max"] = maxf(float(stats["tick_us_max"]) * 0.999, us)


## Breadcrumbs of the driving player (one per TRAIL_STEP metres, TRAIL_MAX kept) for the pursuit.
func _update_trail() -> void:
	if Game.get_player_vehicle() == null:
		if not trail.is_empty():
			trail.clear()
		return
	var pp := Game.get_player_position()
	var n := trail.size()
	if n == 0:
		trail.append(pp)
		return
	var d := _flat(trail[n - 1], pp)
	if d > 40.0:
		trail.clear()
		trail.append(pp)
	elif d >= TRAIL_STEP:
		trail.append(pp)
		if trail.size() > TRAIL_MAX:
			trail.remove_at(0)


func _tick_units(delta: float) -> void:
	var pp := Game.get_player_position()
	for i in range(units.size() - 1, -1, -1):
		var u := units[i]
		if not u.is_valid() or u.is_destroyed():
			_drop_unit(u)
			continue
		u.think_acc += delta
		var d := _flat(u.get_position(), pp)
		var interval := 1.0 / 15.0 if d < NEAR_TICK_DIST else 1.0 / 6.0
		if u.think_acc >= interval:
			var acc := u.think_acc
			u.think_acc = 0.0
			u.tick(acc)


func _dispatch(dt: float) -> void:
	_prune()
	_assign_slots()
	_heli_step(dt)
	var lvl := int(Wanted.level)
	if lvl <= 0:
		_ambient_step()
		return
	if not ground_dispatch:
		return
	_spawn_cd -= dt
	if _spawn_cd > 0.0:
		return
	var cfg: Dictionary = Wanted.get_level_config(lvl)
	var pp := _ref_point()
	var c := _counts(pp)
	var free_humans := MAX_OFFICERS - _alive_officer_count()
	var reserve := 2 if int(cfg.get("roadblocks", 0)) > 0 and roadblocks.is_empty() else 0
	var want_officers := mini(int(cfg.get("officers", 0)), MAX_OFFICERS)
	var want_vans := int(cfg.get("swat_vans", 0))
	var want_cruisers := mini(int(cfg.get("cruisers", 0)), MAX_VEHICLES - want_vans)
	var spawned: Node3D = null
	if int(c["vans"]) < want_vans and free_humans - reserve >= 2 and _driven_count() < MAX_VEHICLES:
		spawned = _spawn_vehicle_unit("swat", pp, mini(4, free_humans - reserve), false, true)
	elif int(c["cruisers"]) < want_cruisers and free_humans - reserve >= 1 and _driven_count() < MAX_VEHICLES:
		var crew := 2 if int(c["officers"]) + 2 <= want_officers and free_humans - reserve >= 2 else 1
		spawned = _spawn_vehicle_unit("cruiser", pp, crew, false, true)
	elif int(c["officers"]) < want_officers and free_humans - reserve >= 1:
		var p := _hidden_walk_point(pp, 45.0, 90.0)
		if p != Vector3.INF:
			spawned = spawn_officer("police_officer", p, "foot", null, 0)
			if spawned != null:
				EventBus.police_unit_spawned.emit(spawned, "officer")
	else:
		return
	if spawned != null:
		_spawn_cd = 1.0 if _episode_t < 25.0 else float(cfg.get("respawn_interval", 12.0))
	else:
		stats["spawn_fail"] = int(stats["spawn_fail"]) + 1
		_spawn_cd = 0.5


## Where the response is directed: what the police KNOW - the last known position during a pursuit
## (refreshed by every sighting), the search centre during a search. New units must never be sent to
## where an unseen player really is. At 0 stars (ambient presence) the player's surroundings.
func _ref_point() -> Vector3:
	if Wanted.level > 0:
		if Wanted.state == Wanted.State.SEARCH:
			return Wanted.search_center
		return Wanted.last_known_position
	return Game.get_player_position()


## Units / officers that count for the current level's targets (alive, not standing down, near).
func _counts(pp: Vector3) -> Dictionary:
	var cr := 0
	var vans := 0
	for u in units:
		# a hopelessly wedged car does not count: its replacement is sent right away (the wreck is
		# removed once nobody sees it)
		if not u.is_valid() or u.standing_down or u.is_hopeless() or u.living_crew().is_empty():
			continue
		if _flat(u.get_position(), pp) > RESPONSE_RANGE:
			continue
		if u.kind == "swat":
			vans += 1
		else:
			cr += 1
	var offs := 0
	for o in officers:
		if not is_instance_valid(o) or bool(o.get("is_dead")):
			continue
		var b: Variant = o.get("brain")
		if b is Node and is_instance_valid(b) and bool((b as Node).get("standing_down")):
			continue
		if _flat(o.global_position, pp) > RESPONSE_RANGE:
			continue
		offs += 1
	return {"cruisers": cr, "vans": vans, "officers": offs}


func _alive_officer_count() -> int:
	var n := 0
	for o in officers:
		if is_instance_valid(o) and not bool(o.get("is_dead")):
			n += 1
	return n


func _driven_count() -> int:
	var n := 0
	for u in units:
		if u.is_valid():
			n += 1
	return n


func _assign_slots() -> void:
	var pp := Game.get_player_position()
	var list: Array = []
	for u in units:
		if u.is_valid() and u.mode == PoliceVehicleAi.Mode.PURSUIT:
			list.append([_flat(u.get_position(), pp), u])
	list.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in list.size():
		(list[i][1] as PoliceVehicleAi).slot = i


# --- spawning ------------------------------------------------------------------------------------

func _spawn_vehicle_unit(kind: String, near: Vector3, crew_n: int, ambient: bool, hidden: bool) -> Node3D:
	if _driven_count() >= MAX_VEHICLES or crew_n <= 0:
		return null
	var spot := _find_lane_spawn(near, SPAWN_MIN if hidden else 35.0, SPAWN_MAX, hidden)
	if spot.is_empty():
		return null
	return _spawn_vehicle_unit_at(kind, spot["xf"], crew_n, ambient)


func _spawn_vehicle_unit_at(kind: String, at: Transform3D, crew_n: int, ambient: bool) -> Node3D:
	if _driven_count() >= MAX_VEHICLES or crew_n <= 0:
		return null
	var xf := at
	xf.origin.y += 0.35
	var spec := "swat_van" if kind == "swat" else "police_cruiser"
	var night := WorldClock.get_daylight() < 0.3
	var v := Game.spawn_vehicle(spec, xf, {"owner_tag": "police", "engine_on": true, "headlights": 1 if night else 0})
	if v == null or not (v is RigidBody3D):
		return null
	var arch := "police_swat" if kind == "swat" else "police_officer"
	var crew: Array = []
	var seats := 4
	if v.has_method("get_seat_count"):
		seats = maxi(int(v.call("get_seat_count")), 1)
	for s in mini(crew_n, seats):
		var o := spawn_officer(arch, xf.origin + Vector3.UP, "crew", v, s)
		if o != null:
			crew.append(o)
	if crew.is_empty() or v.get("driver") != crew[0]:
		for o: Variant in crew:
			_free_officer(o as Node3D)
		_despawn_vehicle(v)
		return null
	var u := _make_unit(v as RigidBody3D, kind, crew, ambient)
	if u == null:
		return null
	if not ambient and Wanted.level > 0 and v.has_method("set_siren"):
		v.call("set_siren", true)
	return v


func _make_unit(v: RigidBody3D, kind: String, crew: Array, ambient: bool) -> PoliceVehicleAi:
	var u := PoliceVehicleAi.new()
	u.setup(self, v, kind, crew, ambient)
	for o: Variant in crew:
		var b: Variant = (o as Node).get("brain")
		if b is Node and is_instance_valid(b):
			(b as Node).set("unit", u)
			(b as Node).set("role", "crew")
	if kind == "swat":
		for i in range(0, crew.size() - 1, 2):
			_pair(crew[i] as Node3D, crew[i + 1] as Node3D)
	v.set_meta("ai_controller", u)
	v.add_to_group("police_vehicle")
	units.append(u)
	stats["vans" if kind == "swat" else "cruisers"] = int(stats["vans" if kind == "swat" else "cruisers"]) + 1
	EventBus.police_unit_spawned.emit(v, "swat" if kind == "swat" else "cruiser")
	return u


func _pair(a: Node3D, b: Node3D) -> void:
	var ba: Variant = a.get("brain")
	var bb: Variant = b.get("brain")
	if ba is Node and bb is Node:
		(ba as Node).set("buddy", b)
		(bb as Node).set("buddy", a)
		(ba as Node).set("flank_side", 1.0)
		(bb as Node).set("flank_side", -1.0)


## A lane spot near `near` (distance in [dmin, dmax]) out of the camera's view and free of vehicles.
## {} when none was found in 10 tries. Prefers spots ahead of a moving player and lanes that head
## towards him.
func _find_lane_spawn(near: Vector3, dmin: float, dmax: float, hidden: bool) -> Dictionary:
	if roads == null:
		return {}
	var lanes: Array = roads.get("lanes")
	# intercept ahead of a moving player only while the police can see where he goes
	var vel := Game.get_player_velocity() if (Wanted.level <= 0 or Wanted.player_visible_to_police) else Vector3.ZERO
	var vdir := Vector3(vel.x, 0.0, vel.z)
	vdir = vdir.normalized() if vdir.length() > 3.0 else Vector3.ZERO
	var best := {}
	var best_score := -INF
	for attempt in 10:
		var r: Dictionary = roads.call("random_lane_point", near, dmin, dmax)
		if r.is_empty():
			continue
		var lane: Dictionary = lanes[int(r["lane_id"])]
		var k := str(lane.get("kind", ""))
		if k == "dirt" or k == "runway" or k == "taxiway":
			continue
		var xf: Transform3D = r["transform"]
		var p := xf.origin
		if Game.is_in_water(p):
			continue
		if hidden and _in_view(p + Vector3.UP * 1.2):
			continue
		if _vehicle_near(p, 7.5):
			continue
		var to := near - p
		to.y = 0.0
		var score := _rng.randf() * 0.6
		if to.length() > 0.1:
			score += (-xf.basis.z).dot(to.normalized()) * 0.5
			if vdir != Vector3.ZERO:
				score += (p - near).normalized().dot(vdir) * 0.8
		if score > best_score:
			best_score = score
			best = {"xf": xf, "lane": int(r["lane_id"])}
	return best


func _hidden_walk_point(near: Vector3, dmin: float, dmax: float) -> Vector3:
	if walk == null:
		return Vector3.INF
	for attempt in 8:
		var p: Vector3 = walk.call("random_point", near, dmin, dmax)
		if p == Vector3.INF:
			continue
		if Game.is_in_water(p):
			continue
		if _in_view(p + Vector3.UP * 1.2):
			continue
		return p
	return Vector3.INF


# --- ambient presence (0 stars) ------------------------------------------------------------------

func _ambient_step() -> void:
	var pp := Game.get_player_position()
	var patrols := 0
	for u: PoliceVehicleAi in units.duplicate():
		if not u.is_valid() or not u.ambient or u.standing_down:
			continue
		var d := _flat(u.get_position(), pp)
		if d > 320.0 or (d > 215.0 and not _in_view(u.get_position() + Vector3.UP)):
			_despawn_unit(u)
			continue
		patrols += 1
	if patrols < AMBIENT_CRUISERS and _ambient_cd <= 0.0 and _driven_count() < MAX_VEHICLES \
			and _alive_officer_count() + 2 <= MAX_OFFICERS:
		var v := _spawn_vehicle_unit("cruiser", pp, 2, true, true)
		_ambient_cd = 8.0 if v != null else 2.0
	_beat_step(pp)


func _beat_step(pp: Vector3) -> void:
	var w := Game.world
	if w == null or not w.has_method("has_location"):
		return
	for anchor in BEAT_ANCHORS:
		if not bool(w.call("has_location", anchor)):
			continue
		var a: Vector3 = (w.call("get_location", anchor) as Transform3D).origin
		var near := _flat(a, pp) < BEAT_RADIUS
		var beats: Array[Node3D] = []
		for o in officers:
			if not is_instance_valid(o) or bool(o.get("is_dead")):
				continue
			var b: Variant = o.get("brain")
			if not (b is Node) or not is_instance_valid(b) or str((b as Node).get("role")) != "beat":
				continue
			var post: Variant = (b as Node).get("post")
			if post is Vector3 and _flat(post as Vector3, a) < 70.0:
				beats.append(o)
		if near:
			if beats.size() < BEATS_PER_ANCHOR and _beat_cd <= 0.0 and _alive_officer_count() < MAX_OFFICERS - 2:
				_beat_cd = 1.5
				var p := _hidden_walk_point(a, 3.0, 40.0)
				if p == Vector3.INF and _flat(a, pp) > 70.0 and walk != null:
					p = walk.call("random_point", a, 3.0, 35.0)
				if p != Vector3.INF:
					var o := spawn_officer("police_officer", p, "beat", null, 0)
					if o != null:
						var b2: Variant = o.get("brain")
						if b2 is Node:
							(b2 as Node).set("post", a)
		else:
			for o in beats:
				if _flat(o.global_position, pp) > BEAT_RADIUS + 40.0 and not _in_view(o.global_position + Vector3.UP):
					_free_officer(o)


func _station_cars_step(pp: Vector3) -> void:
	for i in range(station_cars.size() - 1, -1, -1):
		var v := station_cars[i]
		if not is_instance_valid(v) or bool(v.get("destroyed")) or v.get("driver") != null:
			station_cars.remove_at(i)
	var w := Game.world
	if w == null or not w.has_method("get_spawn_points") or not w.has_method("has_location"):
		return
	if not bool(w.call("has_location", "police_station")):
		return
	var st: Vector3 = (w.call("get_location", "police_station") as Transform3D).origin
	var d := _flat(st, pp)
	if d > STATION_RADIUS + 60.0:
		for v: Node3D in station_cars.duplicate():
			if not _in_view(v.global_position + Vector3.UP):
				station_cars.erase(v)
				_despawn_vehicle(v)
		return
	if d > STATION_RADIUS or station_cars.size() >= STATION_CARS:
		return
	var pts: Array = w.call("get_spawn_points", "police_car")
	for xf: Transform3D in pts:
		if station_cars.size() >= STATION_CARS:
			break
		if _vehicle_near(xf.origin, 3.0) or _in_view(xf.origin + Vector3.UP):
			continue
		var v := Game.spawn_vehicle("police_cruiser", xf, {"owner_tag": "police", "asleep": true, "engine_on": false})
		if v != null:
			v.set("owner_tag", "police")
			v.add_to_group("police_vehicle")
			station_cars.append(v)


# --- slow housekeeping (1 Hz) ----------------------------------------------------------------------

func _slow_step(dt: float) -> void:
	_update_env()
	_collect_prewarm()
	var pp := Game.get_player_position()
	var ref := _ref_point()
	# officers: dead bodies, units sent home, strays
	for o: Node3D in officers.duplicate():
		if not is_instance_valid(o) or o.is_queued_for_deletion():
			officers.erase(o)
			continue
		var d := _flat(o.global_position, pp)
		if bool(o.get("is_dead")):
			var id := o.get_instance_id()
			if not _dead_t.has(id):
				_dead_t[id] = _clock
			if _clock - float(_dead_t[id]) > DEAD_FREE_TIME or (d > 60.0 and not _in_view(o.global_position + Vector3.UP)):
				_dead_t.erase(id)
				_free_officer(o)
			continue
		if o.get("current_vehicle") != null:
			continue
		var b: Variant = o.get("brain")
		var leaving := b is Node and is_instance_valid(b) and str((b as Node).call("get_mode_name")) == "leave"
		var role := str((b as Node).get("role")) if b is Node and is_instance_valid(b) else "foot"
		if leaving and ((d > 55.0 and not _in_view(o.global_position + Vector3.UP)) or d > 200.0):
			_free_officer(o)
		elif role != "beat" and minf(d, _flat(o.global_position, ref)) > 280.0 and not _in_view(o.global_position + Vector3.UP):
			_free_officer(o)
	# vehicle units
	for u: PoliceVehicleAi in units.duplicate():
		if not u.is_valid():
			_drop_unit(u)
			continue
		var up := u.get_position()
		var d := _flat(up, pp)
		var seen := _in_view(up + Vector3.UP)
		if u.mode == PoliceVehicleAi.Mode.LEAVE and ((d > 90.0 and not seen) or d > 240.0):
			_despawn_unit(u)
		elif u.mode == PoliceVehicleAi.Mode.HOLD and u.living_crew().is_empty():
			_abandon_unit(u)
		elif u.is_hopeless() and not seen:
			# wedged / on its roof out of sight: send a fresh unit instead
			stats["relocated"] = int(stats["relocated"]) + 1
			_despawn_unit(u)
		elif not u.ambient and minf(d, _flat(up, ref)) > 330.0 and not seen and u.mode != PoliceVehicleAi.Mode.DEPLOYED:
			_despawn_unit(u)
	for v: Node3D in abandoned.duplicate():
		if not is_instance_valid(v) or v.get("driver") != null or str(v.get("owner_tag")) == "player":
			abandoned.erase(v)
			continue
		var dv := _flat(v.global_position, pp)
		if (dv > 140.0 and not _in_view(v.global_position + Vector3.UP)) or dv > 300.0:
			abandoned.erase(v)
			_despawn_vehicle(v)
	_roadblock_step(dt, pp)
	_station_cars_step(pp)
	_heli_slow_step(pp)


func _collect_prewarm() -> void:
	if _prewarm_left.is_empty():
		return
	for path in _prewarm_left.duplicate():
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_prewarmed.append(ResourceLoader.load_threaded_get(path))
			_prewarm_left.erase(path)
		elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_prewarm_left.erase(path)


func _update_env() -> void:
	var vis := 160.0
	if Weather.has_method("get_visibility"):
		vis = float(Weather.get_visibility())
	var day := 1.0
	if WorldClock.has_method("get_daylight"):
		day = float(WorldClock.get_daylight())
	sight_factor = clampf(vis / 160.0, 0.35, 1.0) * lerpf(0.7, 1.0, clampf(day, 0.0, 1.0))


func _prune() -> void:
	if _arrester != null and (not is_instance_valid(_arrester) or bool(_arrester.get("is_dead"))):
		_arrester = null


# --- roadblocks ----------------------------------------------------------------------------------

func _roadblock_step(dt: float, pp: Vector3) -> void:
	var lvl := int(Wanted.level)
	for rb: PoliceRoadblock in roadblocks.duplicate():
		rb.update(dt)
		var d := _flat(rb.center, pp)
		var stale := lvl < 3 or rb.age > ROADBLOCK_LIFETIME or d > 230.0
		if not stale:
			continue
		var seen := false
		if d < 280.0:
			for n in rb.get_nodes():
				if _in_view(n.global_position + Vector3.UP):
					seen = true
					break
		if seen:
			continue
		for o in rb.living_officers():
			var b: Variant = o.get("brain")
			if b is Node and is_instance_valid(b):
				(b as Node).set("role", "foot")
				(b as Node).call("set_standing_down", true)
		rb.cleanup()
		roadblocks.erase(rb)
	if lvl < 3 or _roadblock_cd > 0.0 or not ground_dispatch:
		return
	var cfg: Dictionary = Wanted.get_level_config(lvl)
	var want := mini(int(cfg.get("roadblocks", 0)), MAX_ROADBLOCKS)
	if roadblocks.size() >= want:
		return
	var pv := Game.get_player_vehicle()
	if pv == null or Game.get_player_velocity().length() < 6.0:
		return
	var rb := _place_roadblock_ahead(cfg)
	_roadblock_cd = 12.0 if rb != null else 2.0


func _place_roadblock_ahead(cfg: Dictionary) -> PoliceRoadblock:
	if _roadblock_points.is_empty() or roads == null:
		return null
	var path := _predict_path(260.0)
	var pts: PackedVector3Array = path.get("pts", PackedVector3Array())
	var cum: PackedFloat32Array = path.get("cum", PackedFloat32Array())
	if pts.size() < 2:
		return null
	var best := -1
	var best_score := -INF
	var best_s := 0.0
	for i in _roadblock_points.size():
		var p := _roadblock_points[i].origin
		if _roadblock_used(p):
			continue
		var pr := _project_path(pts, cum, p)
		var s := pr.x
		if pr.y > 7.5 or s < 70.0 or s > 245.0:
			continue
		if s < 150.0 and _in_view(p + Vector3.UP * 1.5):
			continue
		var score := -absf(s - 125.0)
		if score > best_score:
			best_score = score
			best = i
			best_s = s
	if best < 0:
		return null
	var xf := _roadblock_points[best]
	var back := _path_point(pts, cum, maxf(best_s - 12.0, 0.0))
	return _build_roadblock(best, xf, back - xf.origin, cfg)


## Admin / test: the roadblock spawn point nearest to `near` (25-220 m, out of view preferred).
func _place_roadblock_near(near: Vector3) -> PoliceRoadblock:
	if _roadblock_points.is_empty() or roadblocks.size() >= MAX_ROADBLOCKS + 1:
		return null
	var best := -1
	var best_score := -INF
	for i in _roadblock_points.size():
		var p := _roadblock_points[i].origin
		if _roadblock_used(p):
			continue
		var d := _flat(p, near)
		if d < 25.0 or d > 220.0:
			continue
		var score := -d - (60.0 if _in_view(p + Vector3.UP * 1.5) else 0.0)
		if score > best_score:
			best_score = score
			best = i
	if best < 0:
		return null
	var xf := _roadblock_points[best]
	var lvl := maxi(int(Wanted.level), 3)
	return _build_roadblock(best, xf, near - xf.origin, Wanted.get_level_config(lvl))


func _build_roadblock(idx: int, xf: Transform3D, toward: Vector3, cfg: Dictionary) -> PoliceRoadblock:
	var hw := 5.5
	var seg := int(roads.call("get_segment_at", xf.origin))
	if seg >= 0:
		var segs: Array = roads.get("segments")
		hw = float((segs[seg] as Dictionary).get("hw", 5.5))
	var lvl := int(cfg.get("level", Wanted.level))
	var n_off := clampi(MAX_OFFICERS - _alive_officer_count(), 0, 3 if lvl >= 5 else 2)
	var rb := PoliceRoadblock.new()
	rb.point_index = idx
	if not rb.build(self, xf, toward, hw, bool(cfg.get("roadblock_spikes", false)), n_off):
		rb.cleanup()
		return null
	roadblocks.append(rb)
	stats["roadblocks"] = int(stats["roadblocks"]) + 1
	EventBus.police_unit_spawned.emit(rb.cars[0], "roadblock")
	return rb


func _roadblock_used(p: Vector3) -> bool:
	for rb in roadblocks:
		if _flat(rb.center, p) < 30.0:
			return true
	return false


## The player's likely route: the lane he drives on, continued straight-most for `length` metres.
## {"pts": PackedVector3Array, "cum": PackedFloat32Array} starting at the player.
func _predict_path(length: float) -> Dictionary:
	var pts := PackedVector3Array()
	var cum := PackedFloat32Array()
	var pp := Game.get_player_position()
	var vel := Game.get_player_velocity()
	var head := Vector3(vel.x, 0.0, vel.z)
	var pv := Game.get_player_vehicle()
	if head.length() < 2.0 and pv != null:
		head = -pv.global_basis.z
		head.y = 0.0
	head = head.normalized() if head.length() > 0.01 else Vector3.FORWARD
	var near: Dictionary = roads.call("get_nearest_lane", pp, 14.0)
	var acc := 0.0
	pts.append(pp)
	cum.append(0.0)
	if near.is_empty():
		pts.append(pp + head * length)
		cum.append(length)
		return {"pts": pts, "cum": cum}
	var lanes: Array = roads.get("lanes")
	var id := int(near["lane_id"])
	var off := float(near["offset"])
	var lxf: Transform3D = roads.call("sample_lane", id, off)
	if (-lxf.basis.z).dot(head) < -0.2:
		var lane0: Dictionary = lanes[id]
		var segs: Array = roads.get("segments")
		var seg: Dictionary = segs[int(lane0["segment_id"])]
		var others: PackedInt32Array = seg["lanes_back"] if int(lane0["direction"]) == 1 else seg["lanes_fwd"]
		if others.size() > 0:
			id = others[0]
			off = PoliceVehicleAi._project_on_lane(lanes[id], pp).x
	var guard := 0
	var prev_id := -1
	while acc < length and guard < 12:
		guard += 1
		var lane: Dictionary = lanes[id]
		if prev_id >= 0:
			var conn: PackedVector3Array = roads.call("get_connection", prev_id, id)
			for c in conn:
				acc += pts[pts.size() - 1].distance_to(c)
				pts.append(c)
				cum.append(acc)
		var lp: PackedVector3Array = lane["points"]
		var lc: PackedFloat32Array = lane["cum"]
		for k in lp.size():
			if lc[k] <= off + 0.5:
				continue
			acc += pts[pts.size() - 1].distance_to(lp[k])
			pts.append(lp[k])
			cum.append(acc)
		off = 0.0
		var nxt: PackedInt32Array = roads.call("get_next_lanes", id)
		if nxt.is_empty():
			break
		var dir_end := PoliceVehicleAi._lane_end_dir(lane)
		var best := nxt[0]
		var best_dot := -INF
		for n_id in nxt:
			var dd := dir_end.dot(PoliceVehicleAi._lane_start_dir(lanes[n_id]))
			if dd > best_dot:
				best_dot = dd
				best = n_id
		prev_id = id
		id = best
	return {"pts": pts, "cum": cum}


## Vector2(arc length, distance) of `p` projected on a polyline.
static func _project_path(pts: PackedVector3Array, cum: PackedFloat32Array, p: Vector3) -> Vector2:
	var best_d := INF
	var best_s := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var l2 := ab.length_squared()
		var t := 0.0
		if l2 > 0.0001:
			t = clampf(Vector2(p.x - a.x, p.z - a.z).dot(ab) / l2, 0.0, 1.0)
		var q := Vector2(a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t)
		var d := q.distance_to(Vector2(p.x, p.z))
		if d < best_d:
			best_d = d
			best_s = cum[i] + (cum[i + 1] - cum[i]) * t
	return Vector2(best_s, best_d)


static func _path_point(pts: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	for i in pts.size() - 1:
		if cum[i + 1] >= s:
			var seg := cum[i + 1] - cum[i]
			var t := 0.0 if seg < 0.0001 else (s - cum[i]) / seg
			return pts[i].lerp(pts[i + 1], t)
	return pts[pts.size() - 1]


func _spike_step() -> void:
	var any := false
	for rb in roadblocks:
		if not rb.spikes.is_empty():
			any = true
			break
	if not any:
		return
	var vm := Game.get_system("vehicles")
	var list: Array = []
	if vm != null and vm.has_method("get_vehicles"):
		list = vm.call("get_vehicles")
	for rb in roadblocks:
		var before := rb.spike_hits
		rb.check_spikes(list, 0.11)
		stats["spike_pops"] = int(stats["spike_pops"]) + (rb.spike_hits - before)


# --- air support (police helicopter) ------------------------------------------------------------

func _tick_heli(delta: float) -> void:
	if heli == null:
		return
	if not heli.is_valid():
		_forget_heli()
		return
	heli.think_acc += delta
	if heli.think_acc >= HELI_TICK:
		var acc := heli.think_acc
		heli.think_acc = 0.0
		heli.tick(acc)


## Dispatcher part for air support (every 0.5 s): one helicopter while the level's config asks for it.
func _heli_step(dt: float) -> void:
	_heli_cd -= dt
	if heli != null and not heli.is_valid():
		_forget_heli()
	if heli != null and heli.is_down():
		return
	var lvl := int(Wanted.level)
	if lvl <= 0 or heli != null or _heli_cd > 0.0:
		return
	if int(Wanted.get_level_config(lvl).get("heli", 0)) <= 0:
		return
	if _spawn_heli(_ref_point(), Transform3D(), false) == null:
		_heli_cd = 2.0


## Spawns the police helicopter: `exact` = at xf (admin / tests), otherwise out of view 270-330 m from
## `near` (behind the camera preferred) at transit altitude, already flying towards `near`.
func _spawn_heli(near: Vector3, xf: Transform3D, exact: bool) -> Node3D:
	if not enabled or not _ensure_world():
		return null
	if heli != null and heli.is_valid():
		if not heli.is_down():
			return heli.vehicle
		return null                       # the previous one is still coming down
	var at := xf
	if not exact:
		var spot := _find_air_spawn(near)
		if spot == Vector3.INF:
			return null
		var to := near - spot
		to.y = 0.0
		at = Transform3D(Basis(Vector3.UP, atan2(-to.x, -to.z)) if to.length() > 1.0 else Basis.IDENTITY, spot)
	var v := Game.spawn_vehicle("heli_police", at, {"owner_tag": "police", "engine_on": true,
			"headlights": 1 if WorldClock.get_daylight() < 0.3 else 0})
	if v == null or not (v is RigidBody3D):
		return null
	v.set("rotor_rpm", 1.0)               # it arrives flying: no spool-up in the air
	var pilot := spawn_officer("police_officer", at.origin, "air", v, 0)
	var marksman: Node3D = null
	if pilot != null and v.get("driver") == pilot:
		marksman = spawn_officer("police_officer", at.origin, "air", v, PoliceHeli.MARKSMAN_SEAT)
	if pilot == null or v.get("driver") != pilot:
		for o: Node3D in [pilot, marksman]:
			if o != null and is_instance_valid(o):
				_free_officer(o)
		_despawn_vehicle(v)
		return null
	# the air crew does not count towards the officer cap / the dispatch targets
	officers.erase(pilot)
	officers.erase(marksman)
	var h := PoliceHeli.new()
	h.setup(self, v as RigidBody3D, pilot, marksman)
	heli = h
	var fwd := -at.basis.z
	fwd.y = 0.0
	(v as RigidBody3D).linear_velocity = fwd.normalized() * (0.0 if exact else 20.0)
	h.tick(0.0)
	stats["helis"] = int(stats["helis"]) + 1
	EventBus.police_unit_spawned.emit(v, "heli")
	return v


## Out of view, HELI_SPAWN_MIN..MAX from `near`, behind the camera when possible; INF if none.
func _find_air_spawn(near: Vector3) -> Vector3:
	var base := _rng.randf() * TAU
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var cf := -cam.global_basis.z
		cf.y = 0.0
		if cf.length() > 0.1:
			base = atan2(-cf.x, -cf.z) + PI          # behind the camera
	for attempt in 10:
		var a := base + _rng.randf_range(-1.1, 1.1) * (1.0 + float(attempt) * 0.25)
		var d := _rng.randf_range(HELI_SPAWN_MIN, HELI_SPAWN_MAX)
		var p := near + Vector3(-sin(a), 0.0, -cos(a)) * d
		var g := maxf(_ground(p), 0.0)
		p.y = maxf(g + 60.0, PoliceHeli.TRANSIT_ALT)
		if _in_view(p):
			continue
		return p
	return Vector3.INF


func _despawn_heli() -> void:
	if heli == null:
		return
	var h := heli
	heli = null
	var v := h.vehicle
	if v != null and is_instance_valid(v) and not h.released:
		h.release_vehicle(v, "despawn")
	for c: Node3D in h.crew:
		if c != null and is_instance_valid(c) and not c.is_queued_for_deletion():
			_free_officer(c)
	h.crew.clear()
	if v != null and is_instance_valid(v) and v != Game.get_player_vehicle():
		_despawn_vehicle(v)


## The helicopter node is gone (freed by somebody else): forget it.
func _forget_heli() -> void:
	if heli == null:
		return
	for c: Node3D in heli.crew:
		if c != null and is_instance_valid(c) and not officers.has(c):
			officers.append(c)            # the system's clean-up takes care of them
	heli.released = true
	heli = null


## Shot down / crashed: the crew (dead or alive) goes to the normal officer clean-up, the wreck is
## removed later out of view, a replacement takes off after HELI_REPLACE.
func _heli_destroyed(v: Node3D) -> void:
	var h := heli
	heli = null
	stats["helis_down"] = int(stats["helis_down"]) + 1
	_heli_cd = HELI_REPLACE
	for c: Node3D in h.crew:
		if c != null and is_instance_valid(c) and not officers.has(c):
			officers.append(c)
	if not h.released:
		h.release_vehicle(v, "destroyed")
	h.crew.clear()
	_heli_wrecks.append(v)
	_heli_wreck_t[v.get_instance_id()] = _clock


## Called by PoliceHeli.release_vehicle.
func _on_heli_released(h: PoliceHeli, _reason: String) -> void:
	if heli == h:
		heli = null
		for c: Node3D in h.crew:
			if c != null and is_instance_valid(c) and not c.is_queued_for_deletion() and not officers.has(c):
				officers.append(c)


## 1 Hz: a leaving helicopter is despawned out of view; wrecks are removed when nobody sees them.
func _heli_slow_step(pp: Vector3) -> void:
	if heli != null and heli.is_valid():
		var hp := heli.get_position()
		var d := _flat(hp, pp)
		if heli.mode == PoliceHeli.Mode.LEAVE and ((d > 300.0 and not _in_view(hp)) or d > 450.0):
			_despawn_heli()
		elif d > 900.0 and not _in_view(hp):
			_despawn_heli()               # lost far away (should not happen): the dispatcher sends a new one
	for w: Node3D in _heli_wrecks.duplicate():
		if w == null or not is_instance_valid(w):
			_heli_wrecks.erase(w)
			continue
		var id := w.get_instance_id()
		var t := _clock - float(_heli_wreck_t.get(id, _clock))
		var dw := _flat(w.global_position, pp)
		if (t > 20.0 and dw > 120.0 and not _in_view(w.global_position + Vector3.UP)) or t > 240.0:
			_heli_wrecks.erase(w)
			_heli_wreck_t.erase(id)
			_despawn_vehicle(w)


# --- stand down / episode ------------------------------------------------------------------------

func _on_level_changed(level: int, previous: int) -> void:
	if level > 0 and previous <= 0:
		_episode_t = 0.0
		_spawn_cd = 0.0
		_roadblock_cd = 3.0
		if heli != null and heli.is_valid() and not heli.is_down():
			heli.resume()
		for u in units:
			u.standing_down = false
		for o in officers:
			if not is_instance_valid(o):
				continue
			var b: Variant = o.get("brain")
			if b is Node and is_instance_valid(b):
				(b as Node).call("set_standing_down", false)
	elif level > previous:
		_spawn_cd = minf(_spawn_cd, 0.5)
	elif level <= 0 and previous > 0:
		_stand_down()
	if level > 0 and heli == null and int(Wanted.get_level_config(level).get("heli", 0)) > 0 \
			and int(Wanted.get_level_config(maxi(previous, 0)).get("heli", 0)) <= 0:
		_heli_cd = maxf(_heli_cd, HELI_DELAY)       # air support takes off when the level first asks for it


func _on_cleared(_reason: String) -> void:
	_stand_down()


func _stand_down() -> void:
	_arrester = null
	_episode_t = 0.0
	if heli != null and heli.is_valid():
		heli.standing_down = true
	var ambient_left := AMBIENT_CRUISERS
	for u in units:
		if u.ambient and ambient_left > 0:
			ambient_left -= 1
			u.standing_down = false
		else:
			u.ambient = false
			u.standing_down = true
	for o in officers:
		if not is_instance_valid(o) or bool(o.get("is_dead")):
			continue
		var b: Variant = o.get("brain")
		if b is Node and is_instance_valid(b):
			var role := str((b as Node).get("role"))
			(b as Node).call("set_standing_down", role != "beat" and role != "crew")


# --- events --------------------------------------------------------------------------------------

func _on_vehicle_destroyed(vehicle: Node3D, instigator: Node) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var is_heli := heli != null and heli.vehicle == vehicle
	if bool(vehicle.get("is_police")) and _is_player(instigator):
		# the helicopter crew calls it in on the way down ("Air One is hit")
		Wanted.report_crime("police_vehicle_destroyed", vehicle.global_position,
				{"instigator": Game.player, "direct_police_witness": is_heli or _police_near(vehicle.global_position, 90.0)})
	if is_heli:
		_heli_destroyed(vehicle)
	for u: PoliceVehicleAi in units.duplicate():
		if u.vehicle == vehicle:
			_drop_unit(u)
	abandoned.erase(vehicle)
	station_cars.erase(vehicle)


func _on_vehicle_stolen(vehicle: Node3D, _thief: Node, _had_driver: bool) -> void:
	_release_ours(vehicle)


func _on_player_entered_vehicle(vehicle: Node3D, seat: int) -> void:
	if seat == 0:
		_release_ours(vehicle)


func _release_ours(vehicle: Node3D) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	for u: PoliceVehicleAi in units.duplicate():
		if u.vehicle == vehicle and u.is_valid():
			u.release_vehicle(vehicle, "abandon")
	abandoned.erase(vehicle)
	station_cars.erase(vehicle)
	if vehicle.is_in_group("police_vehicle"):
		vehicle.remove_from_group("police_vehicle")


## Called by PoliceVehicleAi.release_vehicle.
func _on_unit_released(u: PoliceVehicleAi, _reason: String) -> void:
	for c: Node3D in u.crew.duplicate():
		if is_instance_valid(c):
			var b: Variant = c.get("brain")
			if b is Node and is_instance_valid(b) and (b as Node).has_method("unlink"):
				(b as Node).call("unlink")
	u.crew.clear()
	units.erase(u)


func _on_officer_died(npc: Node3D) -> void:
	_dead_t[npc.get_instance_id()] = _clock
	release_arrest(npc)


# --- removal helpers -------------------------------------------------------------------------------

## The unit's car is unusable (destroyed / invalid): the crew goes on foot, the unit is forgotten.
func _drop_unit(u: PoliceVehicleAi) -> void:
	for c: Node3D in u.crew.duplicate():
		if is_instance_valid(c):
			var b: Variant = c.get("brain")
			if b is Node and is_instance_valid(b) and (b as Node).has_method("unlink"):
				(b as Node).call("unlink")
	u.crew.clear()
	if u.vehicle != null and is_instance_valid(u.vehicle) and u.vehicle.has_meta("ai_controller") \
			and u.vehicle.get_meta("ai_controller") == u:
		u.vehicle.remove_meta("ai_controller")
	u.released = true
	units.erase(u)


## Nobody of the crew is left: the car stays in the world as an abandoned police car.
func _abandon_unit(u: PoliceVehicleAi) -> void:
	var v := u.vehicle
	_drop_unit(u)
	if v != null and is_instance_valid(v) and not bool(v.get("destroyed")):
		if v.has_method("release_inputs"):
			v.call("release_inputs")
		abandoned.append(v)


func _despawn_unit(u: PoliceVehicleAi) -> void:
	for c: Node3D in u.crew.duplicate():
		if is_instance_valid(c):
			_free_officer(c)
	u.crew.clear()
	var v := u.vehicle
	units.erase(u)
	u.released = true
	stats["despawned_units"] = int(stats["despawned_units"]) + 1
	if v == null or not is_instance_valid(v):
		return
	if v.has_meta("ai_controller") and v.get_meta("ai_controller") == u:
		v.remove_meta("ai_controller")
	if bool(v.get("is_player_driven")) or v == Game.get_player_vehicle():
		return
	_despawn_vehicle(v)


func _despawn_vehicle(v: Node3D) -> void:
	if v == null or not is_instance_valid(v) or v == Game.get_player_vehicle():
		return
	var vm := Game.get_system("vehicles")
	if vm != null and vm.has_method("despawn_vehicle"):
		vm.call("despawn_vehicle", v)
	else:
		v.queue_free()


func _free_officer(o: Node3D) -> void:
	officers.erase(o)
	if o == null or not is_instance_valid(o):
		return
	release_arrest(o)
	_dead_t.erase(o.get_instance_id())
	for u in units:
		u.remove_crew(o)
	if o.get("current_vehicle") != null and o.has_method("exit_vehicle"):
		o.call("exit_vehicle")
	stats["despawned_officers"] = int(stats["despawned_officers"]) + 1
	o.queue_free()


# --- small helpers -------------------------------------------------------------------------------

## True when the camera could see `p` (frustum, < 260 m, nothing solid in between).
func _in_view(p: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	if not cam.is_position_in_frustum(p):
		return false
	var cp := cam.global_position
	if cp.distance_to(p) > 260.0:
		return false
	if _view_q == null:
		_view_q = PhysicsRayQueryParameters3D.new()
		_view_q.collision_mask = Layers.WORLD
	_view_q.from = cp
	_view_q.to = p
	return get_world_3d().direct_space_state.intersect_ray(_view_q).is_empty()


func _vehicle_near(p: Vector3, r: float) -> bool:
	if not is_inside_tree():
		return false
	if _shape_q == null:
		_shape_q = PhysicsShapeQueryParameters3D.new()
		_shape_q.collision_mask = Layers.VEHICLE
		_shape_q.collide_with_areas = false
	_sphere.radius = r
	_shape_q.shape = _sphere
	_shape_q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
	return not get_world_3d().direct_space_state.intersect_shape(_shape_q, 1).is_empty()


func _police_near(p: Vector3, r: float) -> bool:
	for o in officers:
		if is_instance_valid(o) and not bool(o.get("is_dead")) and _flat(o.global_position, p) < r:
			return true
	return false


func _is_player(who: Variant) -> bool:
	if who == null or not is_instance_valid(who):
		return false
	if who == Game.player:
		return true
	if who is Node and (who as Node).is_in_group("player"):
		return true
	return who == Game.get_player_vehicle()


func _ground(p: Vector3) -> float:
	if Game.world != null and Game.world.has_method("get_height"):
		return float(Game.world.call("get_height", p.x, p.z))
	return p.y


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
