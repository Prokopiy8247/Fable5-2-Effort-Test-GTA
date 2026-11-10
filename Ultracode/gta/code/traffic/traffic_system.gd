class_name TrafficSystem
extends Node3D
## World system "traffic" (ARCHITECTURE 6.8, WAVE2 W2.1): ambient civilian traffic and parked cars.
##
## * Real VehicleBase instances driven through set_inputs() by a lane follower on the RoadGraph:
##   pure-pursuit steering on a look-ahead point; target speed = min(lane limit, curve speed,
##   gap to the leader from a lane-occupancy table, junction control with stop lines, obstacle box
##   cast for pedestrians / the player / stopped vehicles, reactions).
## * Junctions: signals (stop line, yellow decision, no red running) and a right-of-way rule for
##   every 3+ leg junction - a strict total order (rank, eta, uid) among "ready" approaching cars,
##   committed cars (permit / inside the box) always respected, plus "don't block the box": a car
##   only enters when its exit lane has room. That cannot deadlock (see docs/TRAFFIC.md).
## * One manager loop, no node per decision: drivers think at 15 Hz near, 5 Hz mid; far cars are
##   frozen and despawned out of sight. Spawning 70-160 m from the focus and out of the camera view.
## * Visible drivers: a TrafficDummy in the seat (= vehicle.driver) gets a pooled humanoid visual
##   (seated_car, low update rate) only within ~60 m of the camera.
## * Parked cars: TrafficParking (sleeping bodies at the world's `parking` bays).
## * Reactions: bump -> brake + honk; heavy crash -> abandon on foot / drive off fast; gunfire,
##   explosions, shots at the car -> panic driving or abandoning; a gun aimed at the driver from
##   close range -> some surrender the car. release_vehicle() turns the driver into a real NPC.

const CAP := 22                     ## hard cap of simulated traffic vehicles
const BASE_TARGET := 16             ## vehicles at density 1.0 in daytime
const SPAWN_MIN := 70.0
const SPAWN_MAX := 160.0
const DESPAWN_DIST := 190.0         ## despawn beyond this when unseen
const DESPAWN_HARD := 260.0         ## despawn beyond this always
const NEAR_DIST := 60.0
const MID_DIST := 165.0
const FREEZE_DIST := 170.0
const UNFREEZE_DIST := 160.0
const VISUAL_DIST := 60.0
const VISUAL_DROP_DIST := 70.0
const MAX_VISUALS := 14
const VISUALS_PER_TICK := 2          ## driver visuals attached per 0.5 s tick (spreads the cost)
const NEAR_HZ := 15.0
const MID_HZ := 5.0
const FAR_HZ := 2.0
const TABLE_HZ := 15.0
const A_LAT := 3.2                  ## comfortable lateral acceleration in curves (m/s^2)
const B_COMF := 2.4                 ## comfortable braking (m/s^2)
const B_HARD := 6.0
const S0 := 2.3                     ## standstill gap bumper to bumper
const TURN_V_RIGHT := 5.5            ## m/s through a right turn (tight corner)
const TURN_V_LEFT := 7.0             ## m/s through a left turn (wide arc)
const STOP_BACK := 1.0              ## cars wait this far behind the stop line (turning cars sweep the junction mouth)
const PLAYER_CLEAR := 45.0          ## never spawn closer than this to the real player
const OBSTACLE_MASK := Layers.VEHICLE | Layers.PLAYER | Layers.NPC | Layers.PROP   ## obstacle boxes ahead of the bumper
const CUT_JUMP := 110.0             ## focus moved this far within one 0.5 s spawn tick: teleport / respawn cut
const CUT_FILL := 10                ## cars spawned at once after a cut (the boosted refill adds the rest)
const JACK_RADIUS := 4.5           ## the player getting in within this distance of a car's footprint (reach 3 m + door offset)
const MAX_ORPHANS := 24
const HUMANOID_SCENE := "res://gta/scenes/characters/humanoid.tscn"
const ANIMATOR_SCRIPT := "res://gta/code/characters/humanoid_animator.gd"

## Time of day -> traffic amount (hour, factor), piecewise linear.
const TOD_CURVE: Array = [[0.0, 0.32], [5.0, 0.32], [7.0, 1.0], [8.0, 1.15], [9.5, 1.0], [16.0, 1.0],
		[17.5, 1.15], [19.0, 1.0], [22.0, 0.55], [24.0, 0.32]]
## Base mix of ambient traffic (spec id -> weight). Specs that cannot spawn are skipped.
const MIX := {"sedan": 1.6, "compact": 1.3, "suv": 1.0, "pickup": 0.9, "van": 0.8, "taxi": 1.1,
		"muscle": 0.45, "sports": 0.22, "box_truck": 0.4, "motorcycle": 0.15}
const DISTRICT_MIX := {
	"downtown": {"taxi": 1.9, "box_truck": 0.6, "pickup": 0.6, "sports": 1.2},
	"midtown": {"taxi": 1.5, "van": 1.2},
	"industrial": {"van": 2.2, "box_truck": 3.2, "pickup": 1.7, "taxi": 0.35, "sports": 0.4, "muscle": 0.8},
	"residential": {"suv": 1.5, "compact": 1.3, "taxi": 0.6, "box_truck": 0.35},
	"waterfront": {"sports": 1.5, "muscle": 1.3, "van": 1.2},
	"beach": {"sports": 1.8, "muscle": 1.5, "suv": 1.2, "box_truck": 0.4, "taxi": 0.7},
	"hill": {"pickup": 1.6, "suv": 1.6, "taxi": 0.3, "box_truck": 0.2},
	"airport": {"taxi": 1.8, "van": 1.4},
}

var enabled: bool = true
var density_mult: float = 1.0
var lanes: TrafficLanes = null
var parking: TrafficParking = null
var drivers: Array[TrafficDriver] = []
var orphans: Array = []             ## vehicles we spawned whose driver left (cleaned up when far)
var stats: Dictionary = {"spawned": 0, "despawned": 0, "released": 0, "collisions": 0,
		"heavy_collisions": 0, "red_violations": 0, "lane_changes": 0, "bypasses": 0, "reverses": 0,
		"honks": 0, "stuck_despawns": 0, "npcs_spawned": 0, "panics": 0, "surrenders": 0,
		"frozen_blockers": 0, "jack_stops": 0, "jack_escapes": 0, "panic_red_runs": 0, "pushed_red_entries": 0, "reroutes": 0,
		"bypass_aborts": 0}

var _by_body: Dictionary = {}       ## vehicle instance id -> TrafficDriver
var _focus_override: Vector3 = Vector3.INF
var _focus: Vector3 = Vector3.ZERO
var _last_focus: Vector3 = Vector3.INF
var _uid: int = 0
var _ready_world: bool = false
var _started: bool = false
var _table_t: float = 0.0
var _spawn_t: float = 0.0
var _park_t: float = 0.0
var _visual_t: float = 0.0
var _aim_t: float = 0.0
var _siren_tick: float = 0.0
var _env_t: float = 0.0
var _refill_t: float = 0.0
var _night: bool = false
var _weather_k: float = 1.0
var _spawnable_cache: Dictionary = {}
var _spawnable_t: float = 0.0
var _verbose: bool = false
var _track_n: int = 0
var _track_sum: float = 0.0
var _track_max: float = 0.0
var _cost_avg: float = 0.0
var _cost_peak: float = 0.0

# lane occupancy table (rebuilt at TABLE_HZ, packed arrays reused)
var _occ_n: int = 0
var _occ_lane := PackedInt32Array()
var _occ_s := PackedFloat32Array()
var _occ_v := PackedFloat32Array()
var _occ_hl := PackedFloat32Array()
var _occ_uid := PackedInt32Array()
var _occ_legit := PackedByteArray()
var _foreign_in_box: Array = []     ## [node id, position, velocity]
var _sirens: Array = []
var _pending_despawn: Array[TrafficDriver] = []   ## frozen cars that hold up a driving car
var _sweep_hit: String = ""          ## what the last junction path sweep hit (log)
var _jack_uid: int = -1             ## traffic car the player is currently walking up to (entry / carjack)

# physics queries (reused)
var _cast_q: PhysicsShapeQueryParameters3D = null
var _cast_box: BoxShape3D = null
var _spawn_q: PhysicsShapeQueryParameters3D = null
var _place_q: PhysicsShapeQueryParameters3D = null
var _ray_q: PhysicsRayQueryParameters3D = null
var _excl: Array[RID] = []

# driver visuals
var _visual_pool: Array[Node3D] = []
var _visual_count: int = 0
var _humanoid_scene: PackedScene = null
var _animator_script: Script = null
var _visual_failed: bool = false


# ==============================================================================================
# lifecycle
# ==============================================================================================

func setup() -> void:
	_try_init()
	if not EventBus.vehicle_collision.is_connected(_on_vehicle_collision):
		EventBus.vehicle_collision.connect(_on_vehicle_collision)
		EventBus.vehicle_damaged.connect(_on_vehicle_damaged)
		EventBus.vehicle_destroyed.connect(_on_vehicle_destroyed)
		EventBus.noise_emitted.connect(_on_noise)
		EventBus.game_ready.connect(_on_game_ready)


func _log(msg: String) -> void:
	if _verbose:
		print("TRAFFIC: ", msg)


func _describe(d: TrafficDriver) -> String:
	return "uid %d %s lane %d s %.1f/%.0f conn %s next %d turn %d permit %s block %d v %.1f lat %.2f xt %.2f tier %d frozen %s since %.2f age %.0f" % [
			d.uid, d.spec_id, d.lane, d.s, lanes.length[d.lane] if d.lane >= 0 else 0.0, str(d.in_conn), d.next_lane,
			int(d.conn[3]) if not d.conn.is_empty() else 0, str(d.permit), d.block, d.speed, d.lateral,
			d.cross_track(lanes, d.body.global_position) if d.is_valid() else 0.0, d.tier, str(d.frozen), d.since, d.age]


func _try_init() -> bool:
	if _ready_world:
		return true
	var w: Node = Game.world
	if w == null or not is_instance_valid(w):
		return false
	var roads: Variant = w.get("roads")
	if roads == null:
		return false
	var l := TrafficLanes.new()
	if not l.build(roads):
		return false
	lanes = l
	parking = TrafficParking.new()
	parking.setup(self, w)
	_cast_box = BoxShape3D.new()
	_cast_q = PhysicsShapeQueryParameters3D.new()
	_cast_q.shape = _cast_box
	_cast_q.collision_mask = OBSTACLE_MASK
	var sbox := BoxShape3D.new()
	sbox.size = Vector3(2.8, 1.8, 9.0)
	_spawn_q = PhysicsShapeQueryParameters3D.new()
	_spawn_q.shape = sbox
	_spawn_q.collision_mask = Layers.VEHICLE | Layers.PLAYER | Layers.NPC
	_ray_q = PhysicsRayQueryParameters3D.new()
	_ray_q.collision_mask = Layers.WORLD
	var pbox := BoxShape3D.new()
	pbox.size = Vector3(2.2, 1.4, 5.4)
	_place_q = PhysicsShapeQueryParameters3D.new()
	_place_q.shape = pbox
	_place_q.collision_mask = Layers.VEHICLE | Layers.PLAYER | Layers.NPC
	_excl.resize(1)
	_ensure_table(96)
	_verbose = Game.flags.has("trf_log")
	_ready_world = true
	return true


func _on_game_ready() -> void:
	if not _try_init():
		push_warning("TrafficSystem: no world road graph - traffic stays empty")
		return
	_started = true
	_prewarm_visuals(2)
	if enabled:
		_initial_fill()


func _exit_tree() -> void:
	for v: Node3D in _visual_pool:
		if is_instance_valid(v):
			v.free()
	_visual_pool.clear()


# ==============================================================================================
# public API (ARCHITECTURE 6.8 + W2.1)
# ==============================================================================================

func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if not on:
		clear_all()
	elif _started:
		_initial_fill()


## Number of simulated traffic vehicles (cars with an AI driver; parked cars not included).
func get_vehicle_count() -> int:
	return drivers.size()


func get_parked_count() -> int:
	return parking.count() if parking != null else 0


## Spawns one traffic vehicle with a driver on `lane_id` at `offset` metres from the lane start
## (ignores view / distance rules, respects the cap). Returns the vehicle or null.
func spawn_traffic_vehicle(lane_id: int, offset: float, spec_id: String = "") -> Node3D:
	if not _try_init() or drivers.size() >= CAP:
		return null
	if lane_id < 0 or lane_id >= lanes.count:
		return null
	# never right on / past the stop line: the car could not stop before the junction any more
	var off := clampf(offset, 0.0, maxf(lanes.length[lane_id] - 6.0, 0.0))
	var p := lanes.lane_point(lane_id, off)
	var dir := lanes.lane_dir(lane_id, off)
	var y := _ground_y(p)
	var yaw := atan2(-dir.x, -dir.z)
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.z))
	# never inside another body (review fix: a car spawned onto an abandoned car blew both apart at dv 10)
	if is_inside_tree() and _place_q != null:
		_place_q.transform = Transform3D(xf.basis, xf.origin + Vector3.UP * 0.95)
		if not get_world_3d().direct_space_state.intersect_shape(_place_q, 1).is_empty():
			return null
	var district := _district(p)
	var spec := spec_id if spec_id != "" else pick_spec(district, false)
	if spec == "":
		return null
	var arch := _pick_archetype(spec, district)
	var v0 := minf(minf(lanes.limit[lane_id] * 0.7, 10.0), sqrt(2.0 * 2.0 * maxf(lanes.length[lane_id] - off - 8.0, 0.0)))
	# ... and never faster than it can stop behind whatever stands ahead on the lane (review fix: a car
	# spawned 12 m behind a waiting truck at 9.8 m/s ran into it)
	v0 = minf(v0, sqrt(2.0 * 3.0 * maxf(_free_ahead(lane_id, off) - 3.5 - S0 - 1.0, 0.0)))
	var v: Variant = Game.spawn_vehicle(spec, xf, {"owner_tag": "civilian", "engine_on": true,
			"velocity": dir * v0, "with_driver": arch[0]})
	if v == null or not is_instance_valid(v):
		return null
	_take_control(v, lane_id, off, arch)
	return v


## Distance from `off` on `lane` to the rear bumper of the nearest vehicle ahead on that lane (our
## drivers right now + the foreign vehicles of the last occupancy table); INF when the lane is free.
func _free_ahead(lane: int, off: float) -> float:
	var best := INF
	for d: TrafficDriver in drivers:
		if d.lane == lane and not d.in_conn and d.s > off and d.is_valid():
			best = minf(best, d.s - d.half_len - off)
	for i in _occ_n:
		if _occ_lane[i] == lane and _occ_uid[i] < 0 and _occ_s[i] > off:
			best = minf(best, _occ_s[i] - _occ_hl[i] - off)
	return best


## Removes every traffic vehicle, parked car and orphan we created.
func clear_all() -> void:
	for i in range(drivers.size() - 1, -1, -1):
		if i < drivers.size():
			_despawn(drivers[i])
	if parking != null:
		parking.clear_all()
	for v: Variant in orphans:
		if v != null and is_instance_valid(v) and not _is_player_owned(v):
			despawn_vehicle_node(v)
	orphans.clear()


## Extra multiplier on top of Settings "traffic_density" (admin / tests).
func set_density(mult: float) -> void:
	density_mult = clampf(mult, 0.0, 2.0)


func get_density_factor() -> float:
	var s := 1.0
	var sv: Variant = Settings.get_value("traffic_density")
	if sv != null:
		s = float(sv)
	return clampf(s, 0.0, 1.5) * density_mult


## Simulated vehicles wanted right now (density x time of day, capped).
func get_target_count() -> int:
	return clampi(roundi(float(BASE_TARGET) * get_density_factor() * _time_factor()), 0, CAP)


## Spawn / despawn around `pos` instead of the player (tests, cut-scenes). Vector3.INF clears it.
func set_focus_override(pos: Vector3) -> void:
	_focus_override = pos


func clear_focus_override() -> void:
	_focus_override = Vector3.INF


func get_focus() -> Vector3:
	return _focus


## W2.1: stop controlling `vehicle`. "carjacked" / "abandon" / "crash" (and the traffic-internal
## "surrender" / "flee") put the driver beside the driver door as a real NPC (returned; null when
## the peds system is missing). "despawn" / "destroyed" just clean up. Afterwards the vehicle has
## no ai_controller meta and driver == null.
func release_vehicle(vehicle: Node3D, reason: String) -> Node3D:
	if vehicle == null or not is_instance_valid(vehicle):
		return null
	var d: TrafficDriver = _by_body.get(vehicle.get_instance_id(), null)
	if d == null:
		if vehicle.has_meta("ai_controller") and vehicle.get_meta("ai_controller") == self:
			vehicle.remove_meta("ai_controller")
		return null
	var v: Variant = vehicle
	var dm := d.dummy
	var dm_ok := dm != null and is_instance_valid(dm)
	var make_npc := reason in ["carjacked", "abandon", "crash", "surrender", "flee"]
	var exit_xf := Transform3D.IDENTITY
	if make_npc and vehicle.is_inside_tree() and v.has_method("get_exit_transform"):
		exit_xf = v.get_exit_transform(0)
	var appearance: Dictionary = dm.get_appearance() if dm_ok else {}
	var lethal: Dictionary = dm.lethal_info if dm_ok else {}
	var had_visual := d.visible_driver
	# hand the seat back
	if v.has_method("release_inputs"):
		v.release_inputs()
	if v.has_method("honk"):
		v.honk(false)
	if v.has_method("set_indicator") and not bool(v.get("destroyed")):
		v.set_indicator(2 if reason in ["abandon", "crash", "surrender", "flee"] else 0)
	if dm_ok and v.has_method("get_occupant") and v.get_occupant(0) == dm:
		v.occupant_exit(0)
	elif v.get("driver") == dm:
		v.set("driver", null)
	_forget(d)
	var npc: Node3D = null
	if make_npc:
		npc = _spawn_driver_npc(d, exit_xf, appearance, reason)
	elif reason == "destroyed" and had_visual and not lethal.is_empty() and vehicle.is_inside_tree():
		npc = _spawn_corpse(d, v.get_exit_transform(0) if v.has_method("get_exit_transform") else vehicle.global_transform, appearance, lethal)
	if reason != "despawn":
		stats["released"] = int(stats["released"]) + 1
		if is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion() and not orphans.has(vehicle):
			orphans.append(vehicle)
	return npc


## Debug / admin overview.
func get_debug_info() -> Dictionary:
	var tiers := [0, 0, 0]
	var frozen := 0
	var moving := 0
	var waiting := 0
	var queue := 0
	var blocked := 0
	for d: TrafficDriver in drivers:
		if not d.is_valid():
			continue
		tiers[clampi(d.tier, 0, 2)] += 1
		if d.frozen:
			frozen += 1
		if absf(d.speed) > 1.0:
			moving += 1
		match d.block:
			TrafficDriver.Block.WAIT:
				waiting += 1
			TrafficDriver.Block.QUEUE:
				queue += 1
			TrafficDriver.Block.BLOCKED:
				blocked += 1
	var out := {"enabled": enabled, "count": drivers.size(), "active": drivers.size() - frozen,
			"target": get_target_count(), "cap": CAP,
			"parked": get_parked_count(), "parked_asleep": parking.asleep_count() if parking != null else 0,
			"orphans": orphans.size(), "tiers": tiers, "frozen": frozen, "moving": moving,
			"waiting": waiting, "queue": queue, "blocked": blocked, "visible_drivers": _visual_count,
			"density": get_density_factor(), "time_factor": _time_factor(), "focus": _focus,
			"focus_override": _focus_override != Vector3.INF}
	for k: String in stats:
		out[k] = stats[k]
	return out


## Respawn / busted: forget panic and pending reactions (the focus jump refills the city).
func reset_for_respawn() -> void:
	for d: TrafficDriver in drivers:
		d.panic_t = 0.0
		d.release_reason = ""
		d.brake_t = 0.0
		d.reacted_aim = false
		d.aimed_t = 0.0
		d.threat_node = null
	_refill_t = 6.0


func get_drivers() -> Array[TrafficDriver]:
	return drivers


func get_driver(vehicle: Node) -> TrafficDriver:
	if vehicle == null or not is_instance_valid(vehicle):
		return null
	return _by_body.get(vehicle.get_instance_id(), null)


## True when the car moves, waits at a junction line, or queues behind cars that do.
func is_flowing(d: TrafficDriver) -> bool:
	if absf(d.speed) > 1.0 or d.frozen:
		return true
	if d.block == TrafficDriver.Block.WAIT:
		return true
	if d.block == TrafficDriver.Block.QUEUE:
		return d.block_root != TrafficDriver.Block.BLOCKED
	return d.release_reason != "" or d.brake_t > 0.0


## Is a world point inside the gameplay camera view (and not too far to matter)?
func is_seen(pos: Vector3) -> bool:
	var cam := _camera()
	if cam == null:
		return false
	if cam.global_position.distance_to(pos) > 240.0:
		return false
	return cam.is_position_in_frustum(pos)


## District-aware random spec id for a traffic (parked = false) or parked car ("" if none can spawn).
func pick_spec(district: String, parked: bool) -> String:
	var mults: Dictionary = DISTRICT_MIX.get(district, {})
	var ids: Array[String] = []
	var weights := PackedFloat32Array()
	var total := 0.0
	for id: String in MIX:
		if not _can_spawn(id):
			continue
		var w := float(MIX[id]) * float(mults.get(id, 1.0))
		if parked:
			if id == "taxi":
				w *= 0.12
			elif id == "box_truck" and district != "industrial":
				w *= 0.4
		if w <= 0.0:
			continue
		ids.append(id)
		weights.append(w)
		total += w
	if ids.is_empty():
		return ""
	var roll := Game.rng.randf() * total
	for i in ids.size():
		roll -= weights[i]
		if roll <= 0.0:
			return ids[i]
	return ids[ids.size() - 1]


## A vehicle we created that is no longer driven by us (parked car that was moved, abandoned car):
## despawned later when far and unseen unless the player made it theirs.
func adopt_orphan(v: Node) -> void:
	if v != null and is_instance_valid(v) and not orphans.has(v):
		orphans.append(v)


func despawn_vehicle_node(v: Variant) -> void:
	if v == null or not is_instance_valid(v):
		return
	var vm := Game.get_system("vehicles")
	if vm != null and vm.has_method("despawn_vehicle"):
		vm.despawn_vehicle(v)
	else:
		(v as Node).queue_free()


# ==============================================================================================
# manager loop
# ==============================================================================================

func _physics_process(delta: float) -> void:
	if not enabled or not _started or lanes == null:
		return
	var t0 := Time.get_ticks_usec()
	_manager_step(delta)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_cost_avg = lerpf(_cost_avg, ms, 0.02)
	_cost_peak = maxf(_cost_peak * 0.999, ms)
	stats["think_ms_avg"] = snappedf(_cost_avg, 0.001)
	stats["think_ms_peak"] = snappedf(_cost_peak, 0.001)


func _manager_step(delta: float) -> void:
	_focus = _compute_focus()
	_env_t -= delta
	if _env_t <= 0.0:
		_env_t = 1.0
		_night = WorldClock.get_daylight() < 0.3
		_weather_k = clampf(float(Weather.get_grip_multiplier()), 0.6, 1.0) if Weather.has_method("get_grip_multiplier") else 1.0
	_table_t -= delta
	if _table_t <= 0.0:
		_table_t = maxf(_table_t + 1.0 / TABLE_HZ, 0.0)
		_rebuild_table()
	for i in range(drivers.size() - 1, -1, -1):
		if i >= drivers.size():
			continue
		var d := drivers[i]
		if not d.is_valid():
			_forget(d)
			continue
		d.since += delta
		d.age += delta
		d.think_t -= delta
		if d.think_t <= 0.0:
			d.think_t = _interval(d)
			var dt := d.since
			d.since = 0.0
			_think(d, dt)
	if not _pending_despawn.is_empty():
		for k: TrafficDriver in _pending_despawn:
			if drivers.has(k):
				_despawn(k)
		_pending_despawn.clear()
	_jack_watch()
	_spawn_t -= delta
	_refill_t = maxf(_refill_t - delta, 0.0)
	if _spawn_t <= 0.0:
		_spawn_t = 0.5
		_spawn_tick()
	_park_t -= delta
	if _park_t <= 0.0:
		_park_t = 1.0
		if parking != null:
			parking.tick(_focus, get_world_3d().direct_space_state, false)
	_visual_t -= delta
	if _visual_t <= 0.0:
		_visual_t = 0.5
		_update_visuals()
	_aim_t -= delta
	if _aim_t <= 0.0:
		_aim_t = 0.25
		_aim_tick(0.25)
	_siren_tick -= delta
	if _siren_tick <= 0.0:
		_siren_tick = 0.2
		_siren_scan()


func _interval(d: TrafficDriver) -> float:
	if d.frozen:
		return 1.0 / FAR_HZ          # only checks whether it should thaw
	if d.tier == 0 or absf(d.speed) > 13.0 or ((d.stop_dist < 28.0 or d.d_line < 30.0 or d.in_conn or d.lead_gap < 30.0) and absf(d.speed) > 0.3):
		return 1.0 / NEAR_HZ        # near, and precise stops / junction crossings in every tier that drives
	return 1.0 / MID_HZ


func _compute_focus() -> Vector3:
	if _focus_override != Vector3.INF:
		return _focus_override
	if Game.has_player():
		return Game.get_player_position()
	var cam := _camera()
	return cam.global_position if cam != null else Vector3.ZERO


func _camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


func _time_factor() -> float:
	var h := 12.0
	if "hour" in WorldClock:
		h = fposmod(float(WorldClock.hour), 24.0)
	for i in range(1, TOD_CURVE.size()):
		var a: Array = TOD_CURVE[i - 1]
		var b: Array = TOD_CURVE[i]
		if h <= float(b[0]):
			var t := (h - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return lerpf(float(a[1]), float(b[1]), clampf(t, 0.0, 1.0))
	return float((TOD_CURVE[TOD_CURVE.size() - 1] as Array)[1])


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ==============================================================================================
# occupancy table
# ==============================================================================================

func _ensure_table(n: int) -> void:
	if _occ_lane.size() >= n:
		return
	_occ_lane.resize(n)
	_occ_s.resize(n)
	_occ_v.resize(n)
	_occ_hl.resize(n)
	_occ_uid.resize(n)
	_occ_legit.resize(n)


func _occ_add(lane: int, s: float, v: float, hl: float, uid: int, legit: bool) -> void:
	if lane < 0:
		return
	if _occ_n >= _occ_lane.size():
		_ensure_table(_occ_lane.size() * 2)
	_occ_lane[_occ_n] = lane
	_occ_s[_occ_n] = s
	_occ_v[_occ_n] = v
	_occ_hl[_occ_n] = hl
	_occ_uid[_occ_n] = uid
	_occ_legit[_occ_n] = 1 if legit else 0
	_occ_n += 1


func _rebuild_table() -> void:
	_occ_n = 0
	for d: TrafficDriver in drivers:
		if not d.is_valid() or d.lane < 0:
			continue
		var legit := d.block == TrafficDriver.Block.WAIT or (d.block == TrafficDriver.Block.QUEUE and d.block_root != TrafficDriver.Block.BLOCKED)
		var v := 0.0 if d.frozen else maxf(d.speed, 0.0)
		if d.in_conn and d.next_lane >= 0:
			var clen := float(d.conn[2])
			_occ_add(d.lane, lanes.length[d.lane] + d.conn_s, v, d.half_len, d.uid, legit)
			_occ_add(d.next_lane, d.conn_s - clen, v, d.half_len, d.uid, legit)
		else:
			_occ_add(d.lane, d.s, v, d.half_len, d.uid, legit)
			if d.lc_t > 0.0 and d.lc_from >= 0:
				var ratio := d.s / maxf(lanes.length[d.lane], 0.1)
				_occ_add(d.lc_from, ratio * lanes.length[d.lc_from], v, d.half_len, d.uid, legit)
	# foreign vehicles (player, police, abandoned / crashed cars) on lanes and inside junction boxes
	_foreign_in_box.clear()
	var vm := Game.get_system("vehicles")
	if vm == null:
		return
	var list: Variant = vm.get("vehicles")
	if not (list is Array):
		return
	var roads: Variant = lanes.roads
	for vv: Variant in (list as Array):
		if vv == null or not is_instance_valid(vv):
			continue
		var body := vv as RigidBody3D
		if body == null or _by_body.has(body.get_instance_id()):
			continue
		var p := body.global_position
		if _flat(p, _focus) > 230.0:
			continue
		if body.sleeping and body.has_meta("traffic_parked"):
			continue       # kerb-side parked car: never in a lane
		var cls: Variant = body.get("vehicle_class")
		if cls != null and str(cls) in ["boat", "heli", "plane"]:
			continue
		var vel := body.linear_velocity
		var aabb: Variant = body.get("body_aabb")
		var hl := 2.3
		var hw := 0.9
		if aabb is AABB:
			hl = (aabb as AABB).size.z * 0.5
			hw = (aabb as AABB).size.x * 0.5
		var nl: Dictionary = roads.get_nearest_lane(p, 2.8)
		if not nl.is_empty():
			var lid := int(nl["lane_id"])
			var off := float(nl["offset"])
			var ld := lanes.lane_dir(lid, off)
			var f := -body.global_transform.basis.z
			f.y = 0.0
			var align := absf(ld.dot(f.normalized())) if f.length_squared() > 0.0001 else 1.0
			var along := vel.dot(ld)
			if align > 0.5 or vel.length() < 1.5:
				var ext := lerpf(hw, hl, align)
				var legit := absf(along) < 0.6 and lanes.signal_state(lid) != 0 and lanes.length[lid] - off < 30.0
				_occ_add(lid, off, maxf(along, 0.0), ext, -1, legit)
		for k in lanes.node_count:
			if lanes.node_legs[k] >= 3 and _flat(p, lanes.node_pos[k]) < lanes.node_radius[k]:
				_foreign_in_box.append([k, p, vel])
				break


# ==============================================================================================
# driving decision
# ==============================================================================================

func _think(d: TrafficDriver, dt: float) -> void:
	var body := d.body
	var veh: Variant = d.veh
	if bool(veh.get("destroyed")):
		release_vehicle(body, "destroyed")
		return
	var dm_ok := d.dummy != null and is_instance_valid(d.dummy)
	if bool(veh.get("is_player_driven")) or not dm_ok or veh.get("driver") != d.dummy:
		if not d.release_reason.begins_with("#"):
			# somebody else took the car (player carjack path, police) - stop controlling it
			_drop_control(d)
		return
	var xf := body.global_transform
	var pos := xf.origin
	var dist := _flat(pos, _focus)
	var seen := is_seen(pos)
	# ------------------------------------------------------------------ tiers
	if d.frozen:
		if dist < UNFREEZE_DIST or seen:
			_unfreeze(d)
		else:
			return
	# never freeze inside a junction or with right of way granted: a frozen car there would hold
	# every conflicting movement of that junction until it thaws (review fix)
	if dist > FREEZE_DIST and not seen and d.release_reason == "" and not d.in_conn and not d.permit \
			and not _player_aboard(body):
		_freeze(d)
		return
	d.tier = 0 if dist < NEAR_DIST else (1 if dist < MID_DIST else 2)
	_count_down(d, dt)
	var spd: float = veh.get_forward_speed()
	d.speed = spd
	d.track(lanes, pos, Game.rng)
	if d.red_violation:
		d.red_violation = false
		if d.panic_t > 0.0:
			stats["panic_red_runs"] = int(stats.get("panic_red_runs", 0)) + 1
		elif d.throttle <= 0.05 and d.brake > 0.0:
			# the driver was braking for the line: shoved into the junction (a police car / crash
			# behind it) - not a decision to run the light
			stats["pushed_red_entries"] = int(stats.get("pushed_red_entries", 0)) + 1
			_log("pushed over the line at red: uid %d %s lane %d speed %.1f brake %.2f" % [d.uid, d.spec_id, d.lane, spd, d.brake])
		else:
			stats["red_violations"] = int(stats["red_violations"]) + 1
			_log("red light entered: uid %d %s lane %d tier %d speed %.1f permit %s age %.1f throttle %.2f brake %.2f block %d obs %s %.1f lead %d %.1f siren %.1f brake_t %.1f" % [
					d.uid, d.spec_id, d.lane, d.tier, spd, str(d.permit), d.age, d.throttle, d.brake, d.block, d.obs_name, d.obs_gap,
					d.lead_uid, d.lead_gap, d.siren_t, d.brake_t])
	if _night and int(veh.get("headlight_mode")) == 0:
		veh.set_headlights(1)
	# ------------------------------------------------------------------ on its side / roof: wait for self-righting
	if xf.basis.y.y < 0.45:
		_set_inputs(d, 0.0, 0.0, 0.0)
		d.stuck_t += dt
		_check_hopeless(d, pos, seen, dt)
		return
	# ------------------------------------------------------------------ pending exit (abandon / surrender / crash)
	if d.release_reason != "":
		d.release_t -= dt
		_set_inputs(d, 0.0, 0.0, 1.0)
		_set_indicator(d, 2)
		if d.release_t <= 0.0 and absf(spd) < 1.5:
			release_vehicle(body, d.release_reason)
		return
	# ------------------------------------------------------------------ reversing out of a jam
	if d.reverse_t > 0.0:
		d.reverse_t -= dt
		_set_inputs(d, -0.55, d.reverse_steer, 0.0)
		if d.reverse_t <= 0.0:
			d.blocked_t = 4.0
		return
	# ------------------------------------------------------------------ steering (pure pursuit)
	d.lateral = move_toward(d.lateral, d.lateral_target, (3.0 if d.in_conn else 1.6) * dt)
	d.offset_now = d.cross_track(lanes, pos)
	var xt := d.offset_now - d.lateral
	var path_dir := d.point_ahead(lanes, 1.0) - d.point_ahead(lanes, 0.0)
	path_dir.y = 0.0
	var head_err := 0.0
	var fwd_h := -xf.basis.z
	fwd_h.y = 0.0
	if path_dir.length_squared() > 0.0001 and fwd_h.length_squared() > 0.0001:
		head_err = absf(fwd_h.normalized().angle_to(path_dir.normalized()))
	var ld := clampf(4.5 + 0.55 * absf(spd), 5.5, 17.0) * clampf(1.0 - 0.3 * absf(xt), 0.55, 1.0) \
			+ (5.0 if d.lc_t > 0.0 else 0.0)
	var tgt := d.point_ahead(lanes, ld)
	if absf(d.lateral) > 0.02:
		var tg := d.point_ahead(lanes, ld + 2.0) - tgt
		tg.y = 0.0
		if tg.length_squared() > 0.0001:
			tg = tg.normalized()
			tgt += Vector3(-tg.z, 0.0, tg.x) * d.lateral
	d.steer = _pursuit(d, xf, tgt, spd)
	if not d.in_conn and spd > 3.0 and d.lc_t <= 0.0 and d.age - d.lc_age > 5.0 and absf(d.lateral) < 0.05 and d.s > 15.0 \
			and d.s < lanes.length[d.lane] - 2.0:
		var e := absf(d.cross_track(lanes, pos))
		_track_n += 1
		_track_sum += e
		if e > _track_max:
			_track_max = e
			if e > 0.9:
				_log("track error %.2f m: %s pos %s head_err %.0f deg obs %s %.1f" % [e, _describe(d), str(pos.snapped(Vector3.ONE * 0.1)), rad_to_deg(head_err), d.obs_name, d.obs_gap])
		stats["track_err_avg"] = snappedf(_track_sum / float(_track_n), 0.01)
		stats["track_err_max"] = snappedf(_track_max, 0.01)
	# ------------------------------------------------------------------ target speed
	var src := 0
	var panic := d.panic_t > 0.0
	var drive_k := d.speed_factor * (1.3 if panic else 1.0) * (0.85 + 0.15 * _weather_k)
	var vfree := d.current_limit(lanes) * drive_k
	# a slower road follows (arterial -> street): be down to its limit at the junction
	if not d.in_conn and d.next_lane >= 0 and lanes.limit[d.next_lane] < lanes.limit[d.lane]:
		var nlim := lanes.limit[d.next_lane] * drive_k
		vfree = minf(vfree, sqrt(nlim * nlim + 2.0 * B_COMF * maxf(lanes.length[d.lane] - d.s - d.half_len, 0.0)))
	var vt := vfree
	var vc := _curve_speed(d, spd, panic)
	if vc < vt:
		vt = vc
		src = 1
	# turning at a junction: at most TURN_V (right turns are the tight ones in right-hand traffic); a car
	# that took a right turn at 9 m/s swung 1.2 m wide into the queue of the road it turned into
	if d.next_lane >= 0 and not d.conn.is_empty():
		var turn := int(d.conn[3])
		if turn == 1 or turn == -1:
			var vturn := (TURN_V_RIGHT if turn == 1 else TURN_V_LEFT) * (1.25 if panic else 1.0)
			var dl := 0.0 if d.in_conn else maxf(lanes.length[d.lane] - d.s - d.half_len, 0.0)
			var vcap := sqrt(vturn * vturn + 2.0 * B_COMF * dl)
			if vcap < vt:
				vt = vcap
				src = 1
	# off the path (e.g. swinging wide out of a turn): do not accelerate until back on line
	if d.lc_t <= 0.0 and d.bypass_t <= 0.0:
		var off_k := clampf(1.0 - (absf(xt) - 0.35) / 1.0, 0.0, 1.0) * clampf(1.0 - (rad_to_deg(head_err) - 10.0) / 30.0, 0.0, 1.0)
		var vtrack := 4.5 + 16.0 * off_k
		if vtrack < vt:
			vt = vtrack
			src = 1
	vfree = vt
	d.stop_dist = INF
	_find_leader(d)
	if d.lead_gap < INF and d.bypass_t <= 0.0:
		var vl := _follow_speed(d.lead_gap, d.lead_v, d, S0)
		if vl < vt:
			vt = vl
			src = 2
		if d.lead_v < 0.5:
			d.stop_dist = minf(d.stop_dist, d.lead_gap - S0)
	var vj := _junction_control(d, spd)
	if vj < vt:
		vt = vj
		src = 3
	if vj < INF:
		d.stop_dist = minf(d.stop_dist, d.d_line - STOP_BACK)
	d.obs_gap = INF
	if true:
		_cast_obstacle(d, xf, spd)
		if d.obs_gap < INF:
			var s0 := 3.0 if d.obs_kind == 1 else S0
			var vo := _follow_speed(d.obs_gap, d.obs_v, d, s0)
			if vo < vt:
				vt = vo
				src = 4
			if d.obs_v < 0.5:
				d.stop_dist = minf(d.stop_dist, d.obs_gap - s0)
	# a frozen car (far and unseen) never holds up a car that still drives: it makes room
	_frozen_blocker(d.lead_uid, d.lead_gap)
	_frozen_blocker(d.obs_uid, d.obs_gap)
	if d.siren_t > 0.0 and not d.in_conn:
		vt = minf(vt, 3.0)
		# pull over - but not right before a junction: the offset would carry into the turn (a van that
		# yielded at the line clipped a pedestrian on the corner while turning right)
		d.lateral_target = _pull_over_offset(d) if (d.d_line > 12.0 or d.next_lane < 0) else 0.0
	elif d.bypass_t <= 0.0:
		d.lateral_target = 0.0
	if d.brake_t > 0.0:
		vt = 0.0
		src = 5
	d.target_speed = vt
	_classify_block(d, src, vt, vfree, spd, dt)
	_recovery(d, dt, pos, seen)
	if not d.is_valid() or not _by_body.has(body.get_instance_id()):
		return
	_maybe_lane_change(d, dt, pos, spd, vfree)
	_pedals(d, vt, spd)
	_set_inputs(d, d.throttle, d.steer, d.brake)
	_update_indicator(d)
	if d.dummy.animator != null and is_instance_valid(d.dummy.animator):
		var sn: Variant = veh.get("steer_norm")
		d.dummy.animator.set("steer", float(sn) if sn != null else d.steer)


func _set_inputs(d: TrafficDriver, throttle: float, steer: float, brake: float) -> void:
	d.throttle = throttle
	d.brake = brake
	d.veh.set_inputs(throttle, steer, brake, false)


func _count_down(d: TrafficDriver, dt: float) -> void:
	if d.honk_t > 0.0:
		d.honk_t -= dt
		if d.honk_t <= 0.0:
			d.veh.honk(false)
	d.honk_cd = maxf(d.honk_cd - dt, 0.0)
	d.brake_t = maxf(d.brake_t - dt, 0.0)
	d.siren_t = maxf(d.siren_t - dt, 0.0)
	d.reroute_cd = maxf(d.reroute_cd - dt, 0.0)
	if d.panic_t > 0.0:
		d.panic_t -= dt
		if d.panic_t > 0.0 and d.honk_cd <= 0.0 and Game.rng.randf() < 1.2 * dt:     # ~1.2 per second, any tier
			_honk(d, 0.35)
			d.honk_cd = Game.rng.randf_range(2.0, 4.0)
	if d.bypass_t > 0.0 and absf(d.speed) > 1.0:
		d.bypass_t -= dt
		if d.bypass_t <= 0.0:
			d.lateral_target = 0.0
	if d.lc_t > 0.0:
		d.lc_t -= dt
		if d.lc_t <= 0.0:
			d.lc_from = -1


func _pursuit(d: TrafficDriver, xf: Transform3D, tgt: Vector3, spd: float) -> float:
	var lp := xf.affine_inverse() * tgt
	var fwd := -lp.z + d.pursuit_ref
	var side := lp.x
	var delta := 0.0
	if fwd < 0.3:
		delta = signf(side) * d.max_steer
	else:
		delta = atan(2.0 * d.wheelbase * side / maxf(fwd * fwd + side * side, 0.01))
	var limit := d.max_steer
	var sp := absf(spd)
	if sp > 4.0:
		limit = minf(d.max_steer, atan(d.wheelbase * d.grip * _weather_k * 9.81 / (sp * sp)) + d.steer_slip)
	return clampf(delta / maxf(limit, 0.05), -1.0, 1.0)


func _curve_speed(d: TrafficDriver, spd: float, panic: bool) -> float:
	var step := 5.0
	var horizon := clampf(spd * spd / (2.0 * B_COMF) + 14.0, 20.0, 45.0)
	var n := int(horizon / step) + 1
	var a_lat := A_LAT * _weather_k * (1.3 if panic else 1.0) * (0.7 if d.two_wheeler else 1.0)
	var prev := d.point_ahead(lanes, 0.0)
	var cur := d.point_ahead(lanes, step)
	var best := INF
	for k in range(1, n):
		var nxt := d.point_ahead(lanes, step * float(k + 1))
		var a := cur - prev
		var b := nxt - cur
		a.y = 0.0
		b.y = 0.0
		var la := a.length()
		var lb := b.length()
		if la > 0.05 and lb > 0.05:
			var ang := absf(atan2(a.x * b.z - a.z * b.x, a.dot(b)))
			if ang > 0.03:
				var kappa := ang / (0.5 * (la + lb))
				var vcurve := sqrt(a_lat / kappa)
				var dd := maxf(step * float(k) - 3.0, 0.0)
				best = minf(best, sqrt(vcurve * vcurve + 2.0 * B_COMF * dd))
		prev = cur
		cur = nxt
	return maxf(best, 3.0)


func _follow_speed(gap: float, v_lead: float, d: TrafficDriver, s0: float) -> float:
	var g := gap - s0
	if g <= 0.0:
		return 0.0
	var vl := maxf(v_lead, 0.0)
	var a := sqrt(vl * vl + 2.0 * B_COMF * 1.2 * g)
	var b := g / d.headway + vl * 0.3
	return minf(a, b)


func _stop_speed(dist: float) -> float:
	if dist <= 0.0:
		return 0.0
	return sqrt(2.0 * B_COMF * dist)


func _pedals(d: TrafficDriver, vt: float, spd: float) -> void:
	var err := vt - spd
	if d.stop_dist < INF and spd > 0.3:
		# decelerate to stand still exactly at the stop point (feed-forward, ~8 m/s^2 at full brake)
		var a_req := spd * spd / (2.0 * maxf(d.stop_dist, 0.15))
		if a_req > 1.2 or d.stop_dist < 0.3:
			d.throttle = 0.0
			d.brake = clampf(a_req / 8.0 + 0.06, 0.1, 1.0)
			return
	if vt < 0.3:
		d.throttle = 0.0
		d.brake = 1.0 if spd < 2.5 else clampf(0.3 + 0.1 * spd, 0.3, 1.0)
	elif err > 0.4:
		# civilians pull away gently (no full-throttle launches); panicking drivers floor it
		var top := 1.0 if d.panic_t > 0.0 else d.max_throttle
		d.throttle = clampf(0.3 + 0.16 * err, minf(0.45, top) if spd < 2.0 else 0.0, top)
		d.brake = 0.0
	elif err < -0.7:
		d.throttle = 0.0
		d.brake = clampf(0.05 + 0.09 * (-err), 0.0, 1.0)
	else:
		# hold: a stiffer P term (review: with 0.15 the cars sat ~0.9 m/s above the target on the slow
		# 7 m/s alleys, 1.2 x the limit for brisk drivers); below the target by 0.5 m/s it coasts
		d.throttle = clampf(0.06 + 0.012 * vt + 0.3 * err, 0.0, 0.6)
		d.brake = 0.0


func _find_leader(d: TrafficDriver) -> void:
	var la := d.lane
	var sa := d.s
	var lb := -1
	var sb := 0.0
	if d.in_conn:
		la = d.next_lane
		sa = d.conn_s - float(d.conn[2])
	elif d.next_lane >= 0:
		lb = d.next_lane
		var clen := float(d.conn[2]) if not d.conn.is_empty() else 0.0
		sb = d.s - lanes.length[d.lane] - clen
	# while a lane change blends over, the car is still (partly) in its old lane: whoever is ahead
	# there is a leader too (a car that drifted across behind a stopped car used to hit it). Lanes are
	# 3.5 m apart and cars ~1.8 m wide: beyond 1.6 m from the new lane centre the body has left the old lane.
	var lc := -1
	var sc := 0.0
	if d.lc_t > 0.0 and d.lc_from >= 0 and not d.in_conn and not d.lc_forced and absf(d.offset_now) > 1.6:
		lc = d.lc_from
		sc = d.s / maxf(lanes.length[d.lane], 0.1) * lanes.length[lc]
	var best := INF
	var bv := 0.0
	var buid := -1
	var blegit := false
	for i in _occ_n:
		if _occ_uid[i] == d.uid:
			continue
		var l := _occ_lane[i]
		var ds := 0.0
		if l == la:
			ds = _occ_s[i] - sa
		elif l == lb:
			ds = _occ_s[i] - sb
		elif l == lc:
			ds = _occ_s[i] - sc
		else:
			continue
		if ds <= 0.0:
			continue
		var gap := ds - _occ_hl[i] - d.half_len
		if gap < best:
			best = gap
			bv = _occ_v[i]
			buid = _occ_uid[i]
			blegit = _occ_legit[i] == 1
	d.lead_gap = best
	d.lead_v = bv
	d.lead_uid = buid
	d.lead_legit = blegit


# ------------------------------------------------------------------------------------------------
# junctions
# ------------------------------------------------------------------------------------------------

func _junction_control(d: TrafficDriver, spd: float) -> float:
	d.ready = false
	if d.in_conn:
		d.jn_node = lanes.end_node[d.lane]
		d.eta = 0.0
		d.d_line = -1.0
		return INF
	d.jn_node = -1
	d.d_line = lanes.length[d.lane] - d.s - d.half_len
	d.eta = INF
	if d.next_lane < 0:
		return _stop_speed(d.d_line - 0.5)
	var approach := maxf(14.0, spd * spd / (2.0 * B_COMF) + 8.0)
	if d.d_line > approach:
		d.permit = false
		return INF
	var node := lanes.end_node[d.lane]
	if not lanes.is_junction(node):
		d.permit = true
		return INF
	d.jn_node = node
	d.eta = maxf(d.d_line, 0.0) / maxf(spd, 1.5)
	var turn := int(d.conn[3]) if not d.conn.is_empty() else 0
	var signalled := lanes.sig[d.lane] >= 0
	var state := lanes.signal_state(d.lane) if signalled else 0
	var panic := d.panic_t > 0.0
	if signalled:
		d.rank = 1 if turn == -1 else 2
	else:
		d.rank = 0 if lanes.yields[d.lane] == 1 else (1 if turn == -1 else 2)
	if d.wait_t > 9.0:
		d.rank = 3
	var sig_ok := true
	if signalled:
		if state == 2:
			sig_ok = panic
		elif state == 1:
			# yellow: go only if stopping comfortably is no longer possible
			sig_ok = d.permit or spd * spd / (2.0 * 4.5) > d.d_line - 0.5
	var room := _room_ahead(d)
	d.ready = sig_ok and room
	if d.permit:
		var can_stop := d.d_line > spd * spd / (2.0 * B_HARD) + 1.0
		if can_stop and ((signalled and state == 2 and not panic) or not room or _box_conflict(d)):
			d.permit = false
	elif d.ready and _junction_clear(d):
		d.permit = true
		d.permit_signal = state
	elif d.ready and d.jn_foreign and absf(spd) < 0.5 and d.wait_t > 2.5 and d.reroute_cd <= 0.0:
		# a parked / abandoned / wrecked vehicle stands in the junction box near our path: check
		# whether the car really fits past it, else turn somewhere else, else honk and wait
		d.reroute_cd = 2.0
		if _conn_path_clear(d, d.lane, d.next_lane):
			d.path_clear_ok = true
		elif not _reroute_around_foreign(d):
			_log("junction %d blocked for uid %d (lane %d -> %d) by %s, no other exit" % [d.jn_node, d.uid, d.lane, d.next_lane, _sweep_hit])
			if d.honk_cd <= 0.0:
				_honk(d, 0.5)
				d.honk_cd = 5.0 + Game.rng.randf() * 3.0
	if d.permit:
		return INF
	return _stop_speed(d.d_line - STOP_BACK)


func _outranks(k: TrafficDriver, d: TrafficDriver) -> bool:
	if k.rank != d.rank:
		return k.rank > d.rank
	if absf(k.eta - d.eta) > 0.25:
		return k.eta < d.eta
	return k.uid < d.uid


func _junction_clear(d: TrafficDriver) -> bool:
	var node := d.jn_node
	for k: TrafficDriver in drivers:
		if k == d or k.jn_node != node or k.next_lane < 0 or not k.is_valid():
			continue
		if k.lane == d.lane and not k.in_conn:
			continue
		if not lanes.movements_conflict(d.lane, d.next_lane, k.lane, k.next_lane):
			continue
		if k.in_conn or k.permit:
			return false
		if not k.ready or k.eta > 5.0:
			continue
		if _outranks(k, d):
			return false
	d.jn_foreign = false
	for f: Array in _foreign_in_box:
		if int(f[0]) != node or lanes.distance_to_movement(d.lane, d.next_lane, f[1]) >= 3.2:
			continue
		var still := (f[2] as Vector3).length_squared() < 0.36
		if still and d.path_clear_ok:
			continue            # a physical sweep along our path found room past it
		d.jn_foreign = still
		return false
	return true


## Physical sweep along the junction path from_lane -> to_lane (+ the start of the exit lane): true when
## no vehicle other than our own moving traffic cars overlaps it (the permit logic handles those).
func _conn_path_clear(d: TrafficDriver, from_lane: int, to_lane: int) -> bool:
	if not is_inside_tree():
		return true
	var p3: PackedVector3Array = lanes.get_conn(from_lane, to_lane)[0]
	var n := p3.size()
	var space := get_world_3d().direct_space_state
	_excl[0] = d.body.get_rid()
	_cast_q.exclude = _excl
	_cast_q.collision_mask = Layers.VEHICLE
	var hw := d.half_w + 0.25
	var ok := true
	# segments of the junction curve, then the first car length of the exit lane
	for i in range(1, n + 1):
		var a: Vector3
		var b: Vector3
		if i < n:
			a = p3[i - 1]
			b = p3[i]
		else:
			a = lanes.lane_point(to_lane, 0.0)
			b = lanes.lane_point(to_lane, d.full_length() + 1.0)
		var dir := b - a
		dir.y = 0.0
		var seg_len := dir.length()
		if seg_len < 0.05:
			continue
		dir /= seg_len
		_cast_box.size = Vector3(hw * 2.0, 1.1, seg_len + 0.8)
		_cast_q.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), (a + b) * 0.5 + Vector3.UP * 0.95)
		for h: Dictionary in space.intersect_shape(_cast_q, 6):
			var node := h.get("collider") as Node3D
			if node == null or not is_instance_valid(node) or node == d.body:
				continue
			if _by_body.has(node.get_instance_id()):
				continue
			ok = false
			_sweep_hit = String(node.name)
			break
		if not ok:
			break
	_cast_q.collision_mask = OBSTACLE_MASK
	return ok


## Waiting behind a stationary foreign vehicle in the junction box: take another exit whose path
## is clear of it (dead ends / U-turns last). Returns success.
func _reroute_around_foreign(d: TrafficDriver) -> bool:
	var opts: PackedInt32Array = lanes.next[d.lane]
	var best := -1
	var best_w := -INF
	for o in opts:
		if o == d.next_lane:
			continue
		var blocked := false
		for f: Array in _foreign_in_box:
			if int(f[0]) == d.jn_node and lanes.distance_to_movement(d.lane, o, f[1]) < 3.2 \
					and not _conn_path_clear(d, d.lane, o):
				blocked = true
				break
		if blocked:
			continue
		var w := Game.rng.randf()
		if lanes.dead_end[o] == 1:
			w -= 2.0
		if lanes.conn_turn(d.lane, o) == 2:
			w -= 1.0
		if w > best_w:
			best_w = w
			best = o
	if best < 0:
		return false
	d.next_lane = best
	d.conn = lanes.get_conn(d.lane, best)
	d.permit = false
	d.path_clear_ok = false
	d.jn_foreign = false
	stats["reroutes"] = int(stats.get("reroutes", 0)) + 1
	_log("reroute around a vehicle in junction %d: uid %d -> lane %d" % [d.jn_node, d.uid, best])
	return true


## A conflicting car already crosses the junction (used to revoke a permit while we can stop).
func _box_conflict(d: TrafficDriver) -> bool:
	for k: TrafficDriver in drivers:
		if k == d or not k.in_conn or k.jn_node != d.jn_node or k.next_lane < 0 or not k.is_valid():
			continue
		if lanes.movements_conflict(d.lane, d.next_lane, k.lane, k.next_lane):
			return true
	return false


## "Don't block the box": the exit lane has room for this car behind any slow vehicle.
func _room_ahead(d: TrafficDriver) -> bool:
	var need := d.full_length() + 2.5
	var nl := d.next_lane
	for i in _occ_n:
		if _occ_lane[i] != nl or _occ_uid[i] == d.uid:
			continue
		var back := _occ_s[i] - _occ_hl[i]
		if back < need and _occ_v[i] < 2.5:
			return false
	return true


# ------------------------------------------------------------------------------------------------
# obstacles
# ------------------------------------------------------------------------------------------------

func _cast_obstacle(d: TrafficDriver, xf: Transform3D, spd: float) -> void:
	d.obs_v = 0.0
	d.obs_kind = 0
	d.obs_uid = -1
	d.obs_legit = false
	if spd < -0.5:
		return
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()
	var length := clampf(3.5 + absf(spd) * 1.5, 4.0, 22.0)
	if d.in_conn and int(d.conn[3]) != 0:
		length = minf(length, 12.0)
	var boxes := 1 if length <= 9.0 else 2
	var piece := length / float(boxes)
	var hw := d.half_w * 0.9 + 0.12
	var space := get_world_3d().direct_space_state
	_excl[0] = d.body.get_rid()
	_cast_q.exclude = _excl
	# the boxes follow the path (lane -> junction curve -> next lane), shifted by the current
	# lateral offset, so parked cars and pedestrians beside the lane never stop the car
	for b in boxes:
		var a := d.half_len + piece * float(b)
		var pa := d.point_ahead(lanes, a)
		var pc := d.point_ahead(lanes, a + piece)
		var dir := pc - pa
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 0.0001 else fwd
		var right := Vector3(-dir.z, 0.0, dir.x)
		var base := pa + right * d.lateral
		_cast_box.size = Vector3(hw * 2.0, 1.1, piece + 0.3)
		_cast_q.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), base + dir * (piece * 0.5) + Vector3.UP * 0.95)
		var hits := space.intersect_shape(_cast_q, 8)
		var found := false
		for h: Dictionary in hits:
			var node := h.get("collider") as Node3D
			if node == null or not is_instance_valid(node) or node == d.body:
				continue
			var along := piece * float(b) + (node.global_position - base).dot(dir)
			var extent := 0.45
			var ov := 0.0
			var kind := 3
			var uid := -1
			var legit := false
			if node.is_in_group("vehicle"):
				kind = 2
				var rb := node as RigidBody3D
				if rb != null:
					ov = rb.linear_velocity.dot(dir)
				var aabb: Variant = node.get("body_aabb")
				if aabb is AABB:
					var nb := node.global_transform.basis
					extent = absf(nb.z.dot(dir)) * (aabb as AABB).size.z * 0.5 + absf(nb.x.dot(dir)) * (aabb as AABB).size.x * 0.5
				else:
					extent = 1.5
				var od: TrafficDriver = _by_body.get(node.get_instance_id(), null)
				if od != null:
					uid = od.uid
					legit = od.block != TrafficDriver.Block.BLOCKED and od.release_reason == ""
			elif node.is_in_group("player") or node.is_in_group("npc") or node.is_in_group("animal") or node is CharacterBody3D:
				kind = 1
				var cb := node as CharacterBody3D
				if cb != null:
					ov = cb.velocity.dot(dir)
			else:
				extent = 0.5
			var gap := maxf(along - extent, 0.0)
			found = true
			if gap < d.obs_gap:
				d.obs_gap = gap
				d.obs_v = ov
				d.obs_kind = kind
				d.obs_uid = uid
				d.obs_legit = legit
				d.obs_name = String(node.name)
		if found:
			return


func _classify_block(d: TrafficDriver, src: int, vt: float, vfree: float, spd: float, dt: float) -> void:
	var stopped := absf(spd) < 0.6 and vt < 0.6
	if not stopped:
		d.block = TrafficDriver.Block.NONE
		d.block_root = TrafficDriver.Block.NONE
		d.blocked_t = maxf(d.blocked_t - dt * 2.0, 0.0)
		if absf(spd) > 2.0:
			d.wait_t = 0.0
	else:
		match src:
			3:
				d.block = TrafficDriver.Block.WAIT
				d.block_root = TrafficDriver.Block.WAIT
				d.wait_t += dt
			2:
				if d.lead_uid >= 0:
					var lead := _driver_by_uid(d.lead_uid)
					if lead != null and lead.block != TrafficDriver.Block.BLOCKED and lead.release_reason == "":
						d.block = TrafficDriver.Block.QUEUE
						d.block_root = lead.block_root if lead.block != TrafficDriver.Block.NONE else TrafficDriver.Block.NONE
					else:
						d.block = TrafficDriver.Block.BLOCKED
						d.block_root = TrafficDriver.Block.BLOCKED
				elif d.lead_legit:
					d.block = TrafficDriver.Block.QUEUE
					d.block_root = TrafficDriver.Block.WAIT
				else:
					d.block = TrafficDriver.Block.BLOCKED
					d.block_root = TrafficDriver.Block.BLOCKED
			4:
				if d.obs_kind == 2 and d.obs_legit:
					d.block = TrafficDriver.Block.QUEUE
					var od := _driver_by_uid(d.obs_uid)
					d.block_root = od.block_root if od != null else TrafficDriver.Block.WAIT
				elif d.obs_kind == 2 and absf(d.obs_v) > 1.0:
					d.block = TrafficDriver.Block.QUEUE      # crossing traffic
					d.block_root = TrafficDriver.Block.NONE
				else:
					d.block = TrafficDriver.Block.BLOCKED
					d.block_root = TrafficDriver.Block.BLOCKED
			_:
				d.block = TrafficDriver.Block.NONE
				d.block_root = TrafficDriver.Block.NONE
		if d.block == TrafficDriver.Block.BLOCKED:
			d.blocked_t += dt
		else:
			d.blocked_t = maxf(d.blocked_t - dt, 0.0)
	# "stuck": wants to move but does not (wedged, blocked for long)
	if (vfree > 2.0 and vt > 1.5 and absf(spd) < 0.3) or d.block == TrafficDriver.Block.BLOCKED:
		d.stuck_t += dt
	else:
		d.stuck_t = maxf(d.stuck_t - dt * 3.0, 0.0)


func _recovery(d: TrafficDriver, dt: float, pos: Vector3, seen: bool) -> void:
	# standing still in the middle of a bypass (oncoming traffic came, something stepped in): give the
	# pass up and tuck back in behind the obstacle, otherwise two cars could face each other forever
	if d.bypass_t > 0.0 and d.block != TrafficDriver.Block.NONE and absf(d.speed) < 0.5:
		d.bypass_stall_t += dt
		if d.bypass_stall_t > 2.5:
			d.bypass_t = 0.0
			d.bypass_stall_t = 0.0
			d.lateral_target = 0.0
			d.blocked_t = minf(d.blocked_t, 4.0)
			stats["bypass_aborts"] = int(stats.get("bypass_aborts", 0)) + 1
			_log("bypass given up: uid %d lane %d obstacle %s" % [d.uid, d.lane, d.obs_name])
	else:
		d.bypass_stall_t = 0.0
	if d.block == TrafficDriver.Block.BLOCKED:
		if d.blocked_t > 3.5 and d.honk_cd <= 0.0:
			_honk(d, 0.5 + Game.rng.randf() * 0.4)
			d.honk_cd = 5.0 + Game.rng.randf() * 4.0
		var patience := 16.0 if d.obs_kind == 1 else 8.0
		if d.blocked_t > patience and d.bypass_t <= 0.0 and d.lc_t <= 0.0:
			if not _try_go_around(d, pos):
				if d.blocked_t > patience + 8.0:
					d.reverse_t = 1.6
					d.reverse_steer = clampf(-d.steer * 0.7, -0.6, 0.6)
					d.blocked_t = patience * 0.5
					stats["reverses"] = int(stats["reverses"]) + 1
					_log("reverse (blocked): uid %d lane %d obstacle %s gap %.1f" % [d.uid, d.lane, d.obs_name, d.obs_gap])
	elif d.stuck_t > 6.0 and d.reverse_t <= 0.0 and d.block == TrafficDriver.Block.NONE:
		# wedged (kerb, wall, another car's corner): back off a little and try again
		d.reverse_t = 1.4
		d.reverse_steer = clampf(-d.steer, -0.8, 0.8)
		d.stuck_t = 3.0
		stats["reverses"] = int(stats["reverses"]) + 1
		_log("reverse (wedged): uid %d lane %d s %.1f pos %s" % [d.uid, d.lane, d.s, str(pos.snapped(Vector3.ONE * 0.1))])
	_check_hopeless(d, pos, seen, dt)


func _check_hopeless(d: TrafficDriver, pos: Vector3, seen: bool, dt: float) -> void:
	# no real progress for a long time (reversing back and forth does not count) while not
	# legitimately waiting at a junction / in a queue that flows
	if pos.distance_to(d.prog_pos) > 4.0:
		d.prog_pos = pos
		d.prog_t = 0.0
	elif (d.block == TrafficDriver.Block.WAIT and not d.jn_foreign) or (d.block == TrafficDriver.Block.QUEUE and d.block_root != TrafficDriver.Block.BLOCKED):
		# waiting at a junction is legitimate - unless a wreck / abandoned car in the box keeps us there
		d.prog_t = maxf(d.prog_t - dt, 0.0)
	else:
		d.prog_t += dt
	var cam := _camera()
	var cam_d := cam.global_position.distance_to(pos) if cam != null else 999.0
	var hopeless := maxf(d.stuck_t, d.prog_t)
	if ((hopeless > 30.0 and not seen) or (hopeless > 75.0 and cam_d > 40.0)) and not _player_aboard(d.body):
		stats["stuck_despawns"] = int(stats["stuck_despawns"]) + 1
		_log("stuck despawn: uid %d %s lane %d s %.1f block %d obs %s gap %.1f lead %.1f pos %s" % [d.uid, d.spec_id, d.lane, d.s, d.block, d.obs_name, d.obs_gap, d.lead_gap, str(pos.snapped(Vector3.ONE * 0.1))])
		_despawn(d)


func _try_go_around(d: TrafficDriver, pos: Vector3) -> bool:
	var adj := lanes.adjacent[d.lane]
	# (not in the last 15 m before the junction: the cursor could land past the neighbour lane's end)
	if adj >= 0 and not d.in_conn and lanes.length[d.lane] - d.s > 15.0 and _lane_gap_ok(d, adj):
		if d.change_lane(lanes, adj, pos, Game.rng, true):
			stats["lane_changes"] = int(stats["lane_changes"]) + 1
			d.lc_cd = 6.0
			d.blocked_t = 0.0
			return true
	if d.in_conn:
		return false
	var room_left := lanes.length[d.lane] - d.s
	var need := maxf(d.obs_gap, 0.0) + 14.0
	if room_left < need + 4.0:
		return false
	# the opposite lane must be free for a stretch
	for o in lanes.opposite[d.lane]:
		var so := lanes.length[o] - d.s
		for i in _occ_n:
			if _occ_lane[i] == o and _occ_s[i] > so - 25.0 and _occ_s[i] < so + 50.0:
				return false
	d.bypass_t = clampf(need / 4.0, 3.0, 7.0)
	_log("bypass: uid %d lane %d obstacle %s gap %.1f" % [d.uid, d.lane, d.obs_name, d.obs_gap])
	d.lateral_target = -3.2 if lanes.lanes_per_dir[d.lane] <= 1 else -3.6
	d.blocked_t = 0.0
	stats["bypasses"] = int(stats["bypasses"]) + 1
	return true


func _lane_gap_ok(d: TrafficDriver, adj: int) -> bool:
	var s_adj := d.s / maxf(lanes.length[d.lane], 0.1) * lanes.length[adj]
	for i in _occ_n:
		if _occ_lane[i] != adj or _occ_uid[i] == d.uid:
			continue
		var ds := _occ_s[i] - s_adj
		var behind := 9.0 + maxf(_occ_v[i] - d.speed, 0.0) * 1.5
		var ahead := 10.0 + maxf(d.speed - _occ_v[i], 0.0) * 1.2
		if ds > -behind and ds < ahead:
			return false
	return true


func _maybe_lane_change(d: TrafficDriver, dt: float, pos: Vector3, spd: float, vfree: float) -> void:
	d.lc_cd -= dt
	if d.lc_t > 0.0 or d.lc_cd > 0.0:
		return
	var adj := lanes.adjacent[d.lane]
	if adj < 0 or d.in_conn or d.bypass_t > 0.0 or d.siren_t > 0.0:
		return
	if d.s < 8.0 or lanes.length[d.lane] - d.s < 40.0 or spd < 4.0:
		return
	var want := false
	if d.lead_gap < 24.0 and d.lead_v < vfree - 3.0:
		# only with room to finish the move before reaching the slow car (else stay behind it)
		if d.lead_gap < 4.0 + maxf(spd - d.lead_v, 0.0) * 1.6:
			d.lc_cd = 0.5
			return
		want = Game.rng.randf() < 0.5
	else:
		want = Game.rng.randf() < (0.06 if d.panic_t > 0.0 else 0.02) * dt * 4.0
	if not want:
		d.lc_cd = 0.5
		return
	if not _lane_gap_ok(d, adj):
		d.lc_cd = 1.0
		return
	if d.change_lane(lanes, adj, pos, Game.rng):
		stats["lane_changes"] = int(stats["lane_changes"]) + 1
		d.lc_cd = 8.0 + Game.rng.randf() * 10.0


func _pull_over_offset(d: TrafficDriver) -> float:
	var lpd := lanes.lanes_per_dir[d.lane]
	if lpd >= 2:
		return 1.2 if lanes.index[d.lane] == lpd - 1 else 0.0
	return 0.5 if lanes.parking[d.lane] == 1 else 0.9


func _update_indicator(d: TrafficDriver) -> void:
	var want := 0
	if d.lc_t > 0.0 and d.lc_from >= 0:
		want = -1 if lanes.index[d.lane] < lanes.index[d.lc_from] else 1
	elif d.block == TrafficDriver.Block.BLOCKED and d.blocked_t > 6.0:
		want = 2
	elif d.next_lane >= 0 and not d.conn.is_empty() and (d.in_conn or d.d_line < 35.0):
		var turn := int(d.conn[3])
		if turn == -1 or turn == 1:
			want = turn
	_set_indicator(d, want)


func _set_indicator(d: TrafficDriver, dir: int) -> void:
	if d.indicator == dir:
		return
	d.indicator = dir
	if d.veh.has_method("set_indicator"):
		d.veh.set_indicator(dir)


func _honk(d: TrafficDriver, dur: float) -> void:
	if not d.is_valid():
		return
	d.honk_t = dur
	d.veh.honk(true)
	stats["honks"] = int(stats["honks"]) + 1


# ------------------------------------------------------------------------------------------------
# far tier
# ------------------------------------------------------------------------------------------------

func _freeze(d: TrafficDriver) -> void:
	if d.frozen:
		return
	d.frozen = true
	d.tier = 2
	d.frozen_speed = maxf(d.speed, 0.0)
	# a frozen car takes no part in the right-of-way negotiation (stale "ready" / eta values of a
	# car that no longer moves would outrank waiting cars)
	d.ready = false
	d.permit = false
	d.jn_node = -1
	d.eta = INF
	d.block = TrafficDriver.Block.NONE
	d.block_root = TrafficDriver.Block.NONE
	d.body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	d.body.freeze = true
	_detach_visual(d)


## `uid` (a leader / obstacle of a slow or stopped car) is a frozen car: despawn it after the
## manager loop (it is beyond FREEZE_DIST and unseen, so nobody notices), the queue behind it moves.
func _frozen_blocker(uid: int, gap: float) -> void:
	if uid < 0 or gap > 40.0:
		return
	var k := _driver_by_uid(uid)
	if k == null or not k.frozen or not k.is_valid() or _pending_despawn.has(k):
		return
	if is_seen(k.body.global_position) or _player_aboard(k.body):
		return
	_pending_despawn.append(k)
	stats["frozen_blockers"] = int(stats.get("frozen_blockers", 0)) + 1
	_log("frozen blocker despawned: uid %d lane %d (gap %.1f)" % [k.uid, k.lane, gap])


func _unfreeze(d: TrafficDriver) -> void:
	if not d.frozen:
		return
	d.frozen = false
	d.body.freeze = false
	d.body.sleeping = false
	var v := d.frozen_speed
	if d.lane >= 0 and not d.in_conn and lanes.is_junction(lanes.end_node[d.lane]):
		var dl := lanes.length[d.lane] - d.s - d.half_len
		v = minf(v, sqrt(2.0 * 2.0 * maxf(dl - 2.0, 0.0)))
	var f := -d.body.global_transform.basis.z
	d.body.linear_velocity = f * v


# ==============================================================================================
# spawning / despawning
# ==============================================================================================

func _initial_fill() -> void:
	if lanes == null:
		return
	_focus = _compute_focus()
	_last_focus = _focus
	var target := get_target_count()
	var guard := 0
	while get_active_count() < target and drivers.size() < CAP and guard < target * 6:
		guard += 1
		_try_spawn_ambient(true, 30.0)
	if parking != null and is_inside_tree():
		parking.tick(_focus, get_world_3d().direct_space_state, true)


func _spawn_tick() -> void:
	var cut := false
	if _last_focus != Vector3.INF and _flat(_focus, _last_focus) > 60.0:
		_refill_t = 6.0          # teleport / respawn / fast jump of the focus
		cut = _flat(_focus, _last_focus) > CUT_JUMP    # faster than any vehicle: a teleport / respawn cut
	_last_focus = _focus
	# despawn far / surplus cars
	var target := get_target_count()
	for i in range(drivers.size() - 1, -1, -1):
		if i >= drivers.size():
			continue
		var d := drivers[i]
		if not d.is_valid():
			_forget(d)
			continue
		var p := d.body.global_position
		var dist := _flat(p, _focus)
		if dist > DESPAWN_HARD or (dist > DESPAWN_DIST and not is_seen(p)):
			_despawn(d)
	if drivers.size() > target + 2:
		var far_d: TrafficDriver = null
		var far_dist := 100.0
		for d: TrafficDriver in drivers:
			var dd := _flat(d.body.global_position, _focus)
			if dd > far_dist and not is_seen(d.body.global_position):
				far_dist = dd
				far_d = d
		if far_d != null:
			_despawn(far_d)
	_orphan_tick()
	if cut:
		# the picture was cut (teleport, respawn fade): fill the new place at once like the boot
		# fill (30..160 m, in view allowed) instead of trickling cars in out of view for seconds
		# (at most CUT_FILL cars in this frame - each costs ~1-1.5 ms; the boosted refill does the rest)
		var guard := 0
		var made := 0
		while get_active_count() < target and guard < target * 4 and made < CUT_FILL:
			guard += 1
			if drivers.size() >= CAP and not _drop_farthest_frozen():
				break
			if _try_spawn_ambient(true, 30.0):
				made += 1
		if parking != null:
			parking.tick(_focus, get_world_3d().direct_space_state, true, CUT_FILL)   # the nearest bays
		return
	# spawn: frozen (far, unseen) cars do not count; they make room when the cap is reached
	var active := get_active_count()
	var missing := target - active
	if missing <= 0:
		return
	var boost := _refill_t > 0.0 or active < int(float(target) * 0.6)
	var per_tick := 3 if boost else 1
	for i in mini(missing, per_tick):
		if drivers.size() >= CAP and not _drop_farthest_frozen():
			break
		_try_spawn_ambient(false, 45.0 if boost else SPAWN_MIN)


func _drop_farthest_frozen() -> bool:
	var best: TrafficDriver = null
	var best_d := 0.0
	for d: TrafficDriver in drivers:
		if d.frozen and d.is_valid():
			var dd := _flat(d.body.global_position, _focus)
			if dd > best_d and not is_seen(d.body.global_position):
				best_d = dd
				best = d
	if best == null:
		return false
	_despawn(best)
	return true


## Simulated (not frozen) traffic vehicles.
func get_active_count() -> int:
	var n := 0
	for d: TrafficDriver in drivers:
		if not d.frozen:
			n += 1
	return n


func _try_spawn_ambient(initial: bool, min_d: float) -> bool:
	var roads: Variant = lanes.roads
	if roads == null:
		return false
	var player_pos := Game.player.global_position if Game.has_player() else Vector3.INF
	for attempt in 8:
		var pick: Dictionary = roads.random_lane_point(_focus, min_d, SPAWN_MAX)
		if pick.is_empty():
			continue
		var lane := int(pick["lane_id"])
		var off := float(pick["offset"])
		if lanes.spawnable[lane] == 0:
			continue
		var accept := 1.0
		match lanes.kind[lane]:
			TrafficLanes.KIND_STREET:
				accept = 0.85
			TrafficLanes.KIND_ALLEY:
				accept = 0.25
		if Game.rng.randf() > accept:
			continue
		if off < 6.0 or off > lanes.length[lane] - 12.0:
			continue
		var p := lanes.lane_point(lane, off)
		if player_pos != Vector3.INF and _flat(p, player_pos) < PLAYER_CLEAR:
			continue
		if not initial and is_seen(p):
			continue
		if not _spawn_space_free(lane, off, p):
			continue
		if spawn_traffic_vehicle(lane, off) != null:
			return true
	return false


func _spawn_space_free(lane: int, off: float, p: Vector3) -> bool:
	for i in _occ_n:
		if _occ_lane[i] == lane and absf(_occ_s[i] - off) < 16.0:
			return false
	for d: TrafficDriver in drivers:
		if d.is_valid() and _flat(d.body.global_position, p) < 9.0:
			return false
	if not is_inside_tree():
		return true
	var dir := lanes.lane_dir(lane, off)
	_spawn_q.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), p + Vector3.UP * 1.0)
	return get_world_3d().direct_space_state.intersect_shape(_spawn_q, 1).is_empty()


func _take_control(v: Variant, lane: int, off: float, arch: Array) -> TrafficDriver:
	var d := TrafficDriver.new()
	_uid += 1
	d.uid = _uid
	d.body = v as RigidBody3D
	d.veh = v
	d.spec_id = str(v.get("spec_id"))
	d.archetype = str(arch[0])
	var aabb: Variant = v.get("body_aabb")
	if aabb is AABB:
		d.half_len = (aabb as AABB).size.z * 0.5
		d.half_w = (aabb as AABB).size.x * 0.5
	var wb: Variant = v.get("wheelbase")
	d.wheelbase = float(wb) if wb != null else 2.6
	# long vehicles track the path with a point ahead of their centre, so the nose does not swing
	# into the opposite stop line when they turn (cars track with the rear axle)
	d.pursuit_ref = d.wheelbase * 0.5 if d.half_len <= 2.9 else -d.wheelbase * 0.25
	d.two_wheeler = str(v.get("vehicle_class")) in ["bike", "bicycle"]
	var spec: Variant = v.get("spec")
	if spec != null:
		d.max_steer = deg_to_rad(float(spec.get("max_steer_angle")))
		d.steer_slip = deg_to_rad(float(spec.get("high_speed_steer_slip")))
		d.grip = (float(spec.get("grip_front")) + float(spec.get("grip_rear"))) * 0.5
	# personality: mostly normal; tough drivers lean aggressive, some are timid
	var r := Game.rng.randf()
	if d.archetype == "civilian_tough":
		d.personality = 2 if r < 0.6 else 0
	else:
		d.personality = 1 if r < 0.2 else (2 if r > 0.9 else 0)
	match d.personality:
		1:
			d.speed_factor = Game.rng.randf_range(0.82, 0.92)
			d.headway = 1.6
			d.max_throttle = 0.55
		2:
			d.speed_factor = Game.rng.randf_range(1.02, 1.1)
			d.headway = 1.0
			d.max_throttle = 0.85
		_:
			d.speed_factor = Game.rng.randf_range(0.9, 1.02)
			d.headway = 1.3
			d.max_throttle = 0.68
	if d.spec_id in ["box_truck", "van"]:
		d.speed_factor *= 0.92
	# seated driver
	var dm := TrafficDummy.new()
	dm.system = self
	dm.driver_uid = d.uid
	dm.archetype = d.archetype
	dm.look_archetype = str(arch[1])
	dm.look_seed = Game.rng.randi()
	var seat: Variant = v.get_seat_node(0) if v.has_method("get_seat_node") else null
	var parent: Node3D = seat as Node3D if seat != null else d.body
	parent.add_child(dm)
	dm.transform = Transform3D.IDENTITY
	d.dummy = dm
	if v.has_method("occupant_enter"):
		v.occupant_enter(dm, 0)
	else:
		v.set("driver", dm)
	v.set_meta("ai_controller", self)
	v.set_meta("traffic_driver_uid", d.uid)
	d.place(lanes, lane, off, Game.rng)
	d.spawn_pos = d.body.global_position
	d.prog_pos = d.spawn_pos
	d.think_t = Game.rng.randf() / NEAR_HZ
	d.lc_cd = Game.rng.randf_range(3.0, 12.0)
	drivers.append(d)
	_by_body[d.body.get_instance_id()] = d
	stats["spawned"] = int(stats["spawned"]) + 1
	return d


func _pick_archetype(spec: String, district: String) -> Array:
	var r := Game.rng.randf()
	var npc := "civilian_m"
	match spec:
		"taxi":
			npc = "taxi_driver"
		"van", "box_truck", "pickup":
			npc = "civilian_tough" if r < 0.3 else ("civilian_m" if r < 0.85 else "civilian_f")
		"sports", "muscle":
			npc = "civilian_tough" if r < 0.3 else ("civilian_m" if r < 0.65 else "civilian_f")
		_:
			npc = "civilian_tough" if r < 0.12 else ("civilian_m" if r < 0.56 else "civilian_f")
	var r2 := Game.rng.randf()
	var look := "civilian_m"
	match npc:
		"civilian_f":
			look = "civilian_f"
			if spec in ["sedan", "suv", "sports"] and r2 < 0.2:
				look = "business"
			elif district in ["beach", "waterfront"] and r2 > 0.7:
				look = "beach"
		"taxi_driver":
			look = "civilian_m" if r2 < 0.75 else "civilian_f"
		_:
			if spec in ["sedan", "suv", "sports"] and r2 < 0.25:
				look = "business"
			elif district in ["beach", "waterfront"] and r2 > 0.75:
				look = "beach"
	return [npc, look]


func _despawn(d: TrafficDriver) -> void:
	var v: Variant = d.veh
	if d.body != null and is_instance_valid(d.body) and _player_aboard(d.body):
		# the player rides along as a passenger: never pull the car away under them - the driver
		# gets out instead and the car stays (clear_all / set_enabled(false) / admin)
		release_vehicle(d.body, "abandon")
		return
	if d.body != null and is_instance_valid(d.body):
		release_vehicle(d.body, "despawn")
		despawn_vehicle_node(v)
	else:
		_forget(d)
	stats["despawned"] = int(stats["despawned"]) + 1


func _orphan_tick() -> void:
	for i in range(orphans.size() - 1, -1, -1):
		var v: Variant = orphans[i]
		if v == null or not is_instance_valid(v) or (v as Node).is_queued_for_deletion():
			orphans.remove_at(i)
			continue
		if _is_player_owned(v) or v.get("driver") != null:
			orphans.remove_at(i)       # not ours to clean up any more
			continue
		var p := (v as Node3D).global_position
		var dist := _flat(p, _focus)
		if (dist > DESPAWN_DIST and not is_seen(p)) or (orphans.size() > MAX_ORPHANS and dist > 60.0 and not is_seen(p)):
			orphans.remove_at(i)
			despawn_vehicle_node(v)


## The player sits in `v` (any seat: riding along as a passenger keeps the AI driver).
func _player_aboard(v: Variant) -> bool:
	if v == null or not is_instance_valid(v):
		return false
	var pv := Game.get_player_vehicle()
	return pv != null and pv == v


func _is_player_owned(v: Variant) -> bool:
	return v.get("is_player_driven") == true or str(v.get("owner_tag")) == "player" or v.get("personal") == true \
			or v == Game.get_player_vehicle()


func _ground_y(p: Vector3) -> float:
	if not is_inside_tree():
		return p.y
	_ray_q.from = p + Vector3.UP * 3.0
	_ray_q.to = p - Vector3.UP * 3.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray_q)
	if hit.is_empty():
		return p.y
	return (hit["position"] as Vector3).y


func _district(p: Vector3) -> String:
	var w: Node = Game.world
	if w != null and is_instance_valid(w) and w.has_method("get_district"):
		return str(w.call("get_district", p))
	return "midtown"


func _can_spawn(id: String) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _spawnable_t > 10.0:
		_spawnable_cache.clear()
		_spawnable_t = now
	if _spawnable_cache.has(id):
		return bool(_spawnable_cache[id])
	var vm := Game.get_system("vehicles")
	var ok := vm != null and vm.has_method("can_spawn") and bool(vm.call("can_spawn", id))
	_spawnable_cache[id] = ok
	return ok


# ==============================================================================================
# bookkeeping
# ==============================================================================================

func _driver_by_uid(uid: int) -> TrafficDriver:
	if uid < 0:
		return null
	for d: TrafficDriver in drivers:
		if d.uid == uid:
			return d
	return null


## Remove a driver from every list, free its dummy (the vehicle itself is untouched).
func _forget(d: TrafficDriver) -> void:
	var idx := drivers.find(d)
	if idx >= 0:
		drivers.remove_at(idx)
	if d.body != null and is_instance_valid(d.body):
		_by_body.erase(d.body.get_instance_id())
		if d.frozen:
			d.body.freeze = false
			d.frozen = false
		if d.body.has_meta("ai_controller") and d.body.get_meta("ai_controller") == self:
			d.body.remove_meta("ai_controller")
		if d.body.has_meta("traffic_driver_uid"):
			d.body.remove_meta("traffic_driver_uid")
	else:
		for k: Variant in _by_body.keys():
			if _by_body[k] == d:
				_by_body.erase(k)
				break
	_detach_visual(d)
	if d.dummy != null and is_instance_valid(d.dummy):
		d.dummy.system = null
		d.dummy.queue_free()
	d.dummy = null


## Somebody else drives the car now (carjack without release_vehicle, police): let go quietly.
func _drop_control(d: TrafficDriver) -> void:
	if d.honk_t > 0.0 and d.veh != null and is_instance_valid(d.body):
		d.veh.honk(false)
	var v := d.body
	_forget(d)
	if v != null and is_instance_valid(v) and not orphans.has(v):
		orphans.append(v)


# ==============================================================================================
# driver visuals (pooled humanoid + HumanoidAnimator, near the camera only)
# ==============================================================================================

func _update_visuals() -> void:
	var cam := _camera()
	var ref := cam.global_position if cam != null else _focus
	var attached := 0
	for d: TrafficDriver in drivers:
		if not d.is_valid() or d.dummy == null or not is_instance_valid(d.dummy):
			continue
		var dist := d.body.global_position.distance_to(ref)
		if not d.visible_driver and dist < VISUAL_DIST and not d.frozen and _visual_count < MAX_VISUALS \
				and attached < VISUALS_PER_TICK:
			_attach_visual(d)
			attached += 1
		elif d.visible_driver and dist > VISUAL_DROP_DIST:
			_detach_visual(d)


## Builds a few pooled driver visuals at boot so the first cars that come near do not hitch
## (the first humanoid instance loads the character part library).
func _prewarm_visuals(n: int) -> void:
	for i in n:
		if _visual_pool.size() >= MAX_VISUALS:
			return
		var vis := _new_visual()
		if vis == null:
			return
		add_child(vis)
		if vis.has_method("randomize_appearance"):
			vis.call("randomize_appearance", "civilian_m", i)
		_ensure_animator(vis)
		remove_child(vis)
		_visual_pool.append(vis)


func _ensure_animator(vis: Node3D) -> Node:
	var anim: Node = vis.get_meta("traffic_anim") as Node if vis.has_meta("traffic_anim") else null
	if (anim == null or not is_instance_valid(anim)) and _animator_script != null and vis.has_method("get_skeleton"):
		anim = _animator_script.new() as Node
		if anim != null:
			anim.name = "SeatedAnimator"
			vis.add_child(anim)
			anim.call("setup", vis.call("get_skeleton"))
			vis.set_meta("traffic_anim", anim)
	return anim


func _new_visual() -> Node3D:
	if _visual_failed:
		return null
	if _humanoid_scene == null:
		if not ResourceLoader.exists(HUMANOID_SCENE):
			_visual_failed = true
			push_warning("TrafficSystem: %s missing - drivers are not drawn" % HUMANOID_SCENE)
			return null
		_humanoid_scene = load(HUMANOID_SCENE) as PackedScene
	if _animator_script == null and ResourceLoader.exists(ANIMATOR_SCRIPT):
		_animator_script = load(ANIMATOR_SCRIPT) as Script
	if _humanoid_scene == null:
		_visual_failed = true
		return null
	var vis := _humanoid_scene.instantiate() as Node3D
	if vis == null:
		_visual_failed = true
		return null
	vis.name = "DriverVisual"
	if "default_archetype" in vis:
		vis.set("default_archetype", "")
	return vis


func _attach_visual(d: TrafficDriver) -> void:
	var dm := d.dummy
	var vis: Node3D = null
	while not _visual_pool.is_empty() and vis == null:
		var c: Node3D = _visual_pool.pop_back()
		if is_instance_valid(c):
			vis = c
	if vis == null:
		vis = _new_visual()
	if vis == null:
		return
	dm.add_child(vis)
	vis.transform = Transform3D.IDENTITY
	if dm.appearance.is_empty():
		if vis.has_method("randomize_appearance"):
			vis.call("randomize_appearance", dm.look_archetype, dm.look_seed)
		if vis.has_method("get_appearance"):
			dm.appearance = vis.call("get_appearance")
	elif vis.has_method("apply_appearance"):
		vis.call("apply_appearance", dm.appearance)
	if vis.has_method("set_lod"):
		vis.call("set_lod", 1)
	var anim := _ensure_animator(vis)
	if anim != null and is_instance_valid(anim):
		var bike := str(d.veh.get("vehicle_class")) in ["bike", "bicycle"]
		anim.set("update_rate_hz", 8.0)
		anim.set("speed", 0.0)
		if anim.has_method("set_state"):
			anim.call("set_state", "seated_bike" if bike else "seated_car", 0.0)
		else:
			anim.set("state", "seated_bike" if bike else "seated_car")
		var wheel: Variant = d.veh.get_part("SteeringWheel") if d.veh.has_method("get_part") else null
		if wheel is Node3D and is_instance_valid(wheel):
			var local: Vector3 = dm.global_transform.affine_inverse() * (wheel as Node3D).global_position
			if local.length() < 1.2 and local.z < -0.15:
				anim.set("wheel_pos", local)
		if anim.has_method("snap"):
			anim.call("snap")
	dm.visual = vis
	dm.animator = anim
	d.visible_driver = true
	_visual_count += 1


func _detach_visual(d: TrafficDriver) -> void:
	if not d.visible_driver:
		return
	d.visible_driver = false
	_visual_count = maxi(_visual_count - 1, 0)
	var dm := d.dummy
	if dm == null or not is_instance_valid(dm):
		return
	var vis := dm.visual
	dm.visual = null
	dm.animator = null
	if vis == null or not is_instance_valid(vis):
		return
	if vis.has_method("get_appearance"):
		dm.appearance = vis.call("get_appearance")
	dm.remove_child(vis)
	if _visual_pool.size() < MAX_VISUALS:
		_visual_pool.append(vis)
	else:
		vis.queue_free()


# ==============================================================================================
# reactions
# ==============================================================================================

func _driver_of(vehicle: Node) -> TrafficDriver:
	if vehicle == null or not is_instance_valid(vehicle):
		return null
	return _by_body.get(vehicle.get_instance_id(), null)


func _on_vehicle_collision(vehicle: Node3D, other: Node, impulse: float, pos: Vector3) -> void:
	var d := _driver_of(vehicle)
	if d == null or not d.is_valid():
		return
	var dv := impulse / maxf(d.body.mass, 1.0)
	if dv >= 2.0:
		stats["collisions"] = int(stats["collisions"]) + 1
		if _verbose:
			var od := _driver_of(other)
			_log("collision: %s dv %.1f with %s [%s] at %s" % [_describe(d), dv, str(other.name) if other != null else "?",
					_describe(od) if od != null else ("parked" if other != null and other.has_meta("traffic_parked") else "foreign"),
					str(pos.snapped(Vector3.ONE * 0.1))])
	if dv < 1.6 or d.release_reason != "":
		return
	var hp := 1.0
	if d.veh.has_method("get_health_ratio"):
		hp = float(d.veh.get_health_ratio())
	var other_node := other as Node3D
	var other_pos := other_node.global_position if other_node != null and is_instance_valid(other_node) else pos
	if dv < 6.0 and hp > 0.45:
		# light bump: brake, honk at whoever it was
		d.brake_t = maxf(d.brake_t, 0.8 + Game.rng.randf() * 0.8)
		if other != null and (other.is_in_group("vehicle") or other.is_in_group("player") or other.is_in_group("npc")) and d.honk_cd <= 0.0:
			_honk(d, 0.6)
			d.honk_cd = 4.0
		return
	stats["heavy_collisions"] = int(stats["heavy_collisions"]) + 1
	_log("heavy collision: uid %d dv %.1f with %s" % [d.uid, dv, str(other.name) if other != null else "?"])
	if d.crash_reacted:
		return
	d.crash_reacted = true
	d.threat_pos = other_pos
	var p_abandon: float = [0.4, 0.7, 0.2][clampi(d.personality, 0, 2)]
	var upside := d.body.global_transform.basis.y.y < 0.5
	if hp < 0.3 or d.veh.get("on_fire") == true or upside:
		p_abandon = 1.0
	var r := Game.rng.randf()
	if r < p_abandon:
		d.release_reason = "crash"
		d.release_t = Game.rng.randf_range(0.6, 1.6)
	elif Game.rng.randf() < 0.7:
		# drive off fast
		d.brake_t = 0.8
		d.panic_t = Game.rng.randf_range(10.0, 16.0)
		d.panic_from = other_pos
		stats["panics"] = int(stats["panics"]) + 1
		_honk(d, 0.8)
	else:
		d.brake_t = 2.5          # shaken, then carries on


func _on_vehicle_damaged(vehicle: Node3D, _amount: float, info: Dictionary) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if vehicle.has_meta("traffic_parked") and parking != null:
		parking.wake(vehicle)
	var d := _driver_of(vehicle)
	if d == null or not d.is_valid():
		return
	var t := str(info.get("type", ""))
	if t in ["bullet", "melee", "explosion", "fire", "fists"]:
		var inst: Variant = info.get("instigator", null)
		var from: Vector3 = info.get("position", vehicle.global_position)
		if inst != null and is_instance_valid(inst) and inst is Node3D:
			from = (inst as Node3D).global_position
		_scare(d, from, 4.0, "shot", inst as Node if inst is Node else null)
	if d.veh.has_method("get_health_ratio") and float(d.veh.get_health_ratio()) < 0.2 and d.release_reason == "":
		d.release_reason = "abandon"
		d.release_t = 0.5


func _on_vehicle_destroyed(vehicle: Node3D, _instigator: Node) -> void:
	var d := _driver_of(vehicle)
	if d != null:
		release_vehicle(vehicle, "destroyed")


func _on_noise(pos: Vector3, radius: float, kind: String, instigator: Node) -> void:
	if kind != "gunshot" and kind != "explosion":
		return
	if drivers.is_empty():
		return
	if instigator is TrafficDummy:
		return
	var r := minf(45.0 if kind == "gunshot" else 75.0, radius * 0.85)
	for d: TrafficDriver in drivers:
		if not d.is_valid():
			continue
		var dist := d.body.global_position.distance_to(pos)
		if dist < r:
			_scare(d, pos, dist, kind, instigator)


func _scare(d: TrafficDriver, pos: Vector3, dist: float, kind: String, inst: Node) -> void:
	d.threat_pos = pos
	if inst != null and is_instance_valid(inst):
		d.threat_node = inst
	if d.release_reason != "" or d.frozen:
		return
	if d.panic_t > 0.0:
		d.panic_t = maxf(d.panic_t, 8.0)
		d.panic_from = pos
		return
	var p_abandon: float = [0.25, 0.5, 0.1][clampi(d.personality, 0, 2)]
	if d.archetype == "civilian_tough":
		p_abandon = 0.12
	if dist < 14.0 and absf(d.speed) < 5.0:
		p_abandon += 0.25
	if kind == "explosion" and dist < 20.0:
		p_abandon += 0.2
	if _player_aboard(d.body):
		p_abandon = 0.0      # the player rides along (drive-by from the passenger seat): getaway driving
	if Game.rng.randf() < p_abandon:
		d.release_reason = "abandon"
		d.release_t = Game.rng.randf_range(0.3, 1.0)
	else:
		d.panic_t = Game.rng.randf_range(12.0, 20.0)
		d.panic_from = pos
		d.brake_t = 0.0
		stats["panics"] = int(stats["panics"]) + 1
		if d.honk_cd <= 0.0:
			_honk(d, 0.5)
			d.honk_cd = 2.0


## 4 Hz: the player aims a gun at a driver from close range.
func _aim_tick(dt: float) -> void:
	if drivers.is_empty() or not Game.has_player():
		return
	var p: Node3D = Game.player
	var aiming: bool = p.get("is_aiming") == true      # (null-safe: stand-ins / other player scripts)
	if not aiming:
		return
	if p.has_method("is_armed") and not bool(p.call("is_armed")):
		return
	if not p.has_method("get_aim_ray"):
		return
	var ray: Variant = p.call("get_aim_ray")
	if not (ray is Dictionary) or not (ray as Dictionary).has("origin"):
		return
	var o: Vector3 = ray["origin"]
	var dir: Vector3 = (ray["direction"] as Vector3).normalized()
	var pp := p.global_position
	var ride := Game.get_player_vehicle()
	for d: TrafficDriver in drivers:
		if not d.is_valid() or d.reacted_aim or d.dummy == null or not is_instance_valid(d.dummy):
			continue
		if ride != null and d.body == ride:
			continue          # the player rides along: aiming out of the window is not a hold-up
		var head := d.dummy.global_position + Vector3.UP * 0.55
		if head.distance_to(pp) > 13.0:
			continue
		var w := head - o
		var t := w.dot(dir)
		if t < 0.5 or t > 18.0 or (w - dir * t).length() > 1.2:
			d.aimed_t = maxf(d.aimed_t - dt, 0.0)
			continue
		d.aimed_t += dt
		if d.aimed_t < 0.45:
			continue
		d.reacted_aim = true
		d.threat_node = p
		d.threat_pos = pp
		var p_surrender := 0.25 if (d.personality == 2 or d.archetype == "civilian_tough") else 0.6
		if absf(d.speed) < 3.5 and Game.rng.randf() < p_surrender:
			d.release_reason = "surrender"
			d.release_t = 0.6
			stats["surrenders"] = int(stats["surrenders"]) + 1
		else:
			d.panic_t = Game.rng.randf_range(12.0, 18.0)
			d.panic_from = pp
			d.brake_t = 0.0
			stats["panics"] = int(stats["panics"]) + 1
			_honk(d, 0.6)


## Every physics frame: the player walks up to a traffic car to get in (PLAYER state "vehicle", not
## seated yet: approach -> carjack, or riding along as a passenger). The driver stops so the entry
## can work (the player module aborts a carjack while the car moves faster than 3.5 m/s); a few
## aggressive drivers that are already rolling floor it instead and leave the player behind.
func _jack_watch() -> void:
	if drivers.is_empty() or not Game.has_player():
		_jack_uid = -1
		return
	var p: Node3D = Game.player
	if not p.has_method("get_state_name") or str(p.call("get_state_name")) != "vehicle" or Game.get_player_vehicle() != null:
		_jack_uid = -1
		return
	var pp := p.global_position
	var best: TrafficDriver = null
	var best_d := JACK_RADIUS
	for d: TrafficDriver in drivers:
		if not d.is_valid() or d.frozen:
			continue
		var bp := d.body.global_position
		if absf(bp.x - pp.x) > 10.0 or absf(bp.z - pp.z) > 10.0:
			continue
		# distance from the player to the car's footprint
		var lp := d.body.global_transform.affine_inverse() * pp
		var dd := Vector2(maxf(absf(lp.x) - d.half_w, 0.0), maxf(absf(lp.z) - d.half_len, 0.0)).length()
		if dd < best_d:
			best_d = dd
			best = d
	if best == null:
		return
	if best.uid != _jack_uid:
		_jack_uid = best.uid
		_on_jack_attempt(best)
	elif best.panic_t <= 0.0 and best.release_reason == "":
		best.brake_t = maxf(best.brake_t, 0.6)      # keep standing while the player gets in


func _on_jack_attempt(d: TrafficDriver) -> void:
	if d.release_reason != "":
		return
	var rolling := absf(d.speed) > 3.0
	var p_flee := 0.0
	if rolling:
		p_flee = 0.45 if (d.personality == 2 or d.archetype == "civilian_tough") else 0.12
	if d.panic_t > 0.0 or Game.rng.randf() < p_flee:
		d.panic_t = maxf(d.panic_t, Game.rng.randf_range(8.0, 12.0))
		d.panic_from = Game.player.global_position
		d.threat_node = Game.player
		d.brake_t = 0.0
		stats["jack_escapes"] = int(stats["jack_escapes"]) + 1
		_honk(d, 0.6)
		_log("jack attempt: uid %d floors it (v %.1f)" % [d.uid, d.speed])
	else:
		d.brake_t = maxf(d.brake_t, 2.0)
		stats["jack_stops"] = int(stats["jack_stops"]) + 1
		_log("jack attempt: uid %d stops (v %.1f)" % [d.uid, d.speed])
	d.think_t = 0.0                                 # decide on the next physics frame


## 5 Hz: emergency vehicles with sirens - cars ahead of them pull right and slow down.
func _siren_scan() -> void:
	_sirens.clear()
	var vm := Game.get_system("vehicles")
	if vm == null or drivers.is_empty():
		return
	var list: Variant = vm.get("vehicles")
	if not (list is Array):
		return
	for vv: Variant in (list as Array):
		if vv != null and is_instance_valid(vv) and vv.get("siren_on") == true and vv.get("destroyed") != true:
			_sirens.append(vv)
	if _sirens.is_empty():
		return
	for d: TrafficDriver in drivers:
		if not d.is_valid():
			continue
		var my := d.body.global_position
		var fwd := -d.body.global_transform.basis.z
		for sv: Variant in _sirens:
			var sp := (sv as Node3D).global_position
			var rel := sp - my
			rel.y = 0.0
			var dist := rel.length()
			if dist > 55.0 or dist < 0.1:
				continue
			var behind := rel.dot(fwd) < 2.0
			var approaching := (sv as RigidBody3D).linear_velocity.dot(-rel / dist) > 2.0
			if behind or approaching:
				d.siren_t = 2.5


# ==============================================================================================
# drivers leaving the car
# ==============================================================================================

## TrafficDummy hook: the vehicle evicted the dummy (explosion, carjack through occupant_enter,
## despawn by the vehicle manager). Handled deferred so a despawn can be told apart.
func _on_dummy_ejected(dm: Node, vehicle: Node, exit_xform: Transform3D, _impulse: Vector3) -> void:
	var d: TrafficDriver = null
	for k: TrafficDriver in drivers:
		if k.dummy == dm:
			d = k
			break
	if d == null:
		return
	d.release_reason = "#ejected"       # _think() leaves it alone until the deferred handler ran
	_handle_ejected.call_deferred(d, vehicle, exit_xform)


func _handle_ejected(d: TrafficDriver, vehicle: Node, exit_xform: Transform3D) -> void:
	if not drivers.has(d):
		return
	var dm := d.dummy
	var appearance: Dictionary = dm.get_appearance() if dm != null and is_instance_valid(dm) else {}
	var lethal: Dictionary = dm.lethal_info if dm != null and is_instance_valid(dm) else {}
	var had_visual := d.visible_driver
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion():
		_forget(d)
		return
	var reason := "abandon"
	var thief: Node = null
	if bool(vehicle.get("is_player_driven")):
		reason = "carjacked"
		thief = Game.player
	elif bool(vehicle.get("destroyed")):
		reason = "destroyed"
	_forget(d)
	if reason == "destroyed":
		if had_visual and not lethal.is_empty():
			_spawn_corpse(d, exit_xform, appearance, lethal)
	else:
		_spawn_driver_npc(d, exit_xform, appearance, reason, thief)
		if not orphans.has(vehicle):
			orphans.append(vehicle)
	stats["released"] = int(stats["released"]) + 1


func _spawn_driver_npc(d: TrafficDriver, xf: Transform3D, appearance: Dictionary, reason: String, thief: Node = null) -> Node3D:
	if Game.get_system("peds") == null:
		return null
	var f := -xf.basis.z
	var yaw := atan2(-f.x, -f.z) if Vector2(f.x, f.z).length() > 0.01 else 0.0
	var opts := {"yaw": yaw}
	if not appearance.is_empty():
		opts["appearance"] = appearance
	var npc: Node3D = Game.spawn_npc(d.archetype, xf.origin, opts)
	if npc == null or not is_instance_valid(npc):
		return null
	stats["npcs_spawned"] = int(stats["npcs_spawned"]) + 1
	npc.set_meta("left_vehicle_reason", reason)
	if thief == null and reason == "carjacked" and Game.has_player():
		thief = Game.player              # W2.1: the PLAYER module releases right before it pulls the driver out
	if thief == null and d.threat_node != null and is_instance_valid(d.threat_node):
		thief = d.threat_node
	var threat := d.threat_pos
	if thief != null and is_instance_valid(thief) and thief is Node3D:
		threat = (thief as Node3D).global_position
	if threat == Vector3.INF:
		threat = d.body.global_position if is_instance_valid(d.body) else xf.origin
	match reason:
		"carjacked":
			# being dragged out of the seat is a (zero-damage) melee assault for the brain: the
			# AI civilian brain makes civilian_tough fight back and everybody else scream and run
			var handled := false
			if thief != null and is_instance_valid(thief):
				handled = _brain_event(npc, "damaged", {"attacker": thief, "info": {"type": "melee", "amount": 0.0,
						"position": threat, "instigator": thief, "carjacked": true}})
			if not handled:
				if d.archetype == "civilian_tough" and thief != null and is_instance_valid(thief) and npc.has_method("melee"):
					npc.call("melee", thief)
				elif npc.has_method("panic"):
					npc.call("panic", threat)
		"surrender":
			if npc.has_method("surrender"):
				npc.call("surrender")
			if thief != null and is_instance_valid(thief):
				_brain_event(npc, "threatened", {"by": thief, "duration": 1.0})
			elif npc.has_method("panic"):
				npc.call("panic", threat)
		_:
			if npc.has_method("panic"):
				npc.call("panic", threat)
	return npc


## The driver died in the explosion of the car: a real NPC body that takes the lethal blast
## (its own module plays the death / ragdoll and reports any crime).
func _spawn_corpse(d: TrafficDriver, xf: Transform3D, appearance: Dictionary, lethal: Dictionary) -> Node3D:
	if Game.get_system("peds") == null:
		return null
	var opts := {"appearance": appearance} if not appearance.is_empty() else {}
	var npc: Node3D = Game.spawn_npc(d.archetype, xf.origin, opts)
	if npc == null or not is_instance_valid(npc):
		return null
	stats["npcs_spawned"] = int(stats["npcs_spawned"]) + 1
	npc.set_meta("left_vehicle_reason", "killed")
	if npc.has_method("apply_damage"):
		npc.call("apply_damage", lethal)
	return npc


func _brain_event(npc: Node, ev: String, data: Dictionary) -> bool:
	var b: Variant = npc.get("brain")
	if b != null and is_instance_valid(b) and (b as Object).has_method("on_event"):
		b.on_event(npc, ev, data)
		return true
	return false
