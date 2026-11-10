class_name TrafficManager
extends Node
## Civilian traffic, parked cars and the life cycle of every non-player vehicle:
## spawns AI-driven cars on the lane graph around the player, streams parked cars in and
## out of the parking spots, hands out junction reservations to AI drivers, respawns the
## fixed service / special vehicles and removes wrecks and abandoned cars.

const SPAWN_MIN := 75.0
const SPAWN_MAX := 150.0
const DESPAWN := 190.0
const PARK_IN := 110.0
const PARK_OUT := 140.0
const CLAIM_TIMEOUT := 14.0

var graph: RoadGraph = null
var rng := RandomNumberGenerator.new()
var base_count := 15
var max_parked := 16
var park_fill := 0.55
var claims: Dictionary = {}          # node id -> Array of [connector id, AIDriver, time]
var pool: Array = []
var _expired: Dictionary = {}        # driver instance id -> time it may claim again
var _spots: Array = []               # {pos, yaw, kind, roll, veh, cool}
var _static: Array = []              # {spec, veh, cool}
var _signals: SignalController = null
var _spawn_cd := 0.6
var _clean_cd := 2.0
var _park_cd := 0.3
var _park_i := 0
var _static_cd := 20.0
var _initial := true
var debug_log := false

func _ready() -> void:
	rng.seed = 424242
	graph = Game.world.graph
	pool = VehicleDB.traffic_pool()
	_signals = Game.world.city.get_node_or_null("Signals") as SignalController
	for sp in Game.world.city.parking_spots:
		if String(sp["kind"]) == "police":
			continue
		_spots.append({"pos": sp["pos"], "yaw": float(sp["yaw"]), "kind": String(sp["kind"]), "roll": rng.randf(), "veh": null, "cool": 0.0})
	print("[Traffic] lanes=%d parking spots=%d pool=%d models" % [graph.lanes.size(), _spots.size(), _unique(pool)])

static func _unique(a: Array) -> int:
	var seen := {}
	for x in a:
		seen[x] = true
	return seen.size()

## Shared clock of the traffic signals.
func clock() -> float:
	return _signals.clock if _signals != null else Game.clock

# ---------------------------------------------------------------- junction reservations
func claim(node_id: String, conn: int, who: AIDriver, force := false) -> bool:
	var now := Game.clock
	var list: Array = claims.get(node_id, [])
	var i := list.size() - 1
	while i >= 0:
		var e: Array = list[i]
		if not is_instance_valid(e[1]):
			list.remove_at(i)
		elif now - float(e[2]) > CLAIM_TIMEOUT:
			_expired[(e[1] as Object).get_instance_id()] = now + 4.0
			list.remove_at(i)
		i -= 1
	claims[node_id] = list
	var mine := -1
	var c := graph.lanes[conn]
	for k in list.size():
		var e2: Array = list[k]
		if e2[1] == who:
			mine = k
		elif not force and c.conflicts.has(int(e2[0])):
			return false
	if mine >= 0:
		list[mine][0] = conn
		return true
	if not force and now < float(_expired.get(who.get_instance_id(), 0.0)):
		return false
	list.append([conn, who, now])
	return true

func release_claim(node_id: String, who: AIDriver) -> void:
	var list: Array = claims.get(node_id, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i][1] == who:
			list.remove_at(i)

# ---------------------------------------------------------------- queries
func ai_vehicles() -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for n in get_tree().get_nodes_in_group(&"vehicles"):
		var v := n as Vehicle
		if v.owner_tag == "traffic" and v.ai != null and not v.destroyed:
			out.append(v)
	return out

func target_count() -> int:
	if not Game.flags["traffic"]:
		return 0
	var f := float(Settings.get_v("traffic_density", 1.0))
	if Game.time != null:
		f *= lerpf(1.0, 0.5, Game.time.night)
	return int(round(base_count * f))

func _free_at(p: Vector3, radius: float) -> bool:
	var r2 := radius * radius
	for n in get_tree().get_nodes_in_group(&"vehicles"):
		if (n as Node3D).global_position.distance_squared_to(p) < r2:
			return false
	return true

func _visible(cam: Camera3D, p: Vector3) -> bool:
	return cam != null and cam.is_position_in_frustum(p + Vector3(0, 1.0, 0))

# ---------------------------------------------------------------- creation
## One AI-driven civilian car on the given lane. Returns null if the spot is blocked.
func spawn_on_lane(lane_id: int, s0: float, id := "") -> Car:
	var p := graph.sample(lane_id, s0)
	if not _free_at(p, 10.0):
		return null
	if id == "":
		id = pool[rng.randi() % pool.size()]
	var dirv := graph.direction(lane_id, s0)
	var v := VehicleFactory.spawn(id, p, atan2(-dirv.x, -dirv.z), {"tag": "traffic"}) as Car
	if v == null:
		return null
	var peds: PedManager = Game.peds
	if peds == null or peds.seat_in(v, 0, &"driver") == null:
		v.queue_free()
		return null
	if v.seat_count() > 1 and rng.randf() < 0.22:
		peds.seat_in(v, 1, &"civil")
	AIDriver.attach(v, self, lane_id, s0)
	if id == "car_taxi":
		v.set_meta("taxi", true)      # can be hailed: the player rides instead of hijacking
	v.linear_velocity = dirv * graph.lanes[lane_id].speed * 0.6
	v.lights_on = Game.time != null and (Game.time.is_night or Game.time.rain > 0.5)
	return v

func _try_spawn(centre: Vector3, cam: Camera3D) -> bool:
	var lo := 34.0 if _initial else SPAWN_MIN
	var heading := Vector3.ZERO
	var pt: Node3D = Game.player_target()
	if pt is RigidBody3D and (pt as RigidBody3D).linear_velocity.length() > 12.0:
		heading = (pt as RigidBody3D).linear_velocity.normalized()
	for attempt in (24 if _initial else 8):
		var lid := graph.random_lane(rng)
		var l := graph.lanes[lid]
		if l.length < 16.0:
			continue
		var s0 := rng.randf_range(6.0, l.length - 9.0)
		var p := graph.sample(lid, s0)
		var d := p.distance_to(centre)
		if d < lo or d > SPAWN_MAX:
			continue
		# when the player drives fast, populate the road ahead rather than behind
		if heading != Vector3.ZERO and (p - centre).normalized().dot(heading) < -0.2 and rng.randf() < 0.8:
			continue
		if not _initial and d < 115.0 and _visible(cam, p):
			continue
		if l.kind == "hill" and rng.randf() < 0.6:
			continue
		if spawn_on_lane(lid, s0) != null:
			return true
	return false

func _remove(v: Vehicle, why := "") -> void:
	if debug_log:
		print("[Traffic] remove ", v.name, " ", why, " d=", snappedf(v.global_position.distance_to(Game.player_pos()), 1.0), " y=", snappedf(v.global_position.y, 0.1))
	if v.ai != null and is_instance_valid(v.ai) and v.ai.has_method("release"):
		v.ai.release()
	v.queue_free()

# ---------------------------------------------------------------- fixed vehicles
## Service / special vehicles placed by the city generator (police lot, hospital, helipads,
## marina, airfield...). They come back after a while when taken or destroyed.
func spawn_static() -> void:
	for spec in Game.world.city.vehicle_spawns:
		var entry := {"spec": spec, "veh": null, "cool": 0.0}
		entry["veh"] = _spawn_static_one(spec)
		_static.append(entry)

func _spawn_static_one(spec: Dictionary) -> Vehicle:
	var id := String(spec["id"])
	if not VehicleDB.exists(id):
		return null
	# special vehicles only appear once their model exists (no stand-in boxes)
	if not VehicleDB.has_model(id):
		return null
	var tag := String(spec.get("tag", ""))
	var v := VehicleFactory.spawn(id, spec["pos"], float(spec["yaw"]), {"tag": "police" if tag.begins_with("police") or tag == "marina_police" else "parked"})
	if v != null:
		v.set_meta("static_spawn", true)
	return v

func _update_static(centre: Vector3) -> void:
	var now := Game.clock
	for e in _static:
		var spec: Dictionary = e["spec"]
		var pos: Vector3 = spec["pos"]
		var v: Vehicle = e["veh"] if e["veh"] != null and is_instance_valid(e["veh"]) else null
		var gone := v == null or v.destroyed or v.global_position.distance_to(pos) > 25.0
		if not gone:
			e["cool"] = 0.0
			continue
		if float(e["cool"]) == 0.0:
			e["cool"] = now + 90.0
			if v != null:
				v.remove_meta("static_spawn")
				if v.owner_tag == "parked":
					v.owner_tag = ""
		elif now > float(e["cool"]) and pos.distance_to(centre) > 120.0 and _free_at(pos, 7.0):
			e["veh"] = _spawn_static_one(spec)
			e["cool"] = 0.0

# ---------------------------------------------------------------- parked cars
func _parked_id(kind: String) -> String:
	var id: String = pool[rng.randi() % pool.size()]
	if kind == "driveway":
		for attempt in 4:
			if String(VehicleDB.get_v(id).get("cls", "")) in ["sedan", "compact", "suv", "pickup", "muscle", "sports"]:
				break
			id = pool[rng.randi() % pool.size()]
	if id == "car_taxi":
		id = "car_sedan"
	return id

func _update_parked(centre: Vector3, cam: Camera3D) -> void:
	var now := Game.clock
	var live := 0
	for sp in _spots:
		var v: Vehicle = sp["veh"] if sp["veh"] != null and is_instance_valid(sp["veh"]) else null
		if sp["veh"] != null and (v == null or v.destroyed or v.player_driven_time > 0.0 or not v.is_empty()):
			# taken, wrecked or occupied: the spot stays empty for a while
			if v != null and v.owner_tag == "parked":
				v.owner_tag = ""
			sp["veh"] = null
			sp["cool"] = now + 300.0
			continue
		if v != null:
			var pos: Vector3 = sp["pos"]
			var moved := v.global_position.distance_to(pos) > 6.0
			if moved:
				v.owner_tag = ""
				sp["veh"] = null
				sp["cool"] = now + 300.0
			elif pos.distance_to(centre) > PARK_OUT:
				v.queue_free()
				sp["veh"] = null
			else:
				live += 1
	if not Game.flags["traffic"]:
		return
	# stream in: a slice of the spots per tick, at most two new cars per tick (no frame spikes)
	var n := _spots.size()
	var made := 0
	for k in mini(n, 40):
		_park_i = (_park_i + 1) % n
		if live >= max_parked or (made >= 2 and not _initial):
			break
		var sp: Dictionary = _spots[_park_i]
		if sp["veh"] != null or float(sp["roll"]) > park_fill or now < float(sp["cool"]):
			continue
		var pos2: Vector3 = sp["pos"]
		var d := pos2.distance_to(centre)
		if d > PARK_IN or d < (8.0 if _initial else 30.0):
			continue
		if not _initial and d < 70.0 and _visible(cam, pos2):
			continue
		if not _free_at(pos2, 4.6):
			continue
		var v2 := VehicleFactory.spawn(_parked_id(String(sp["kind"])), pos2, float(sp["yaw"]), {"tag": "parked"})
		if v2 != null:
			v2.locked = rng.randf() < 0.25
			sp["veh"] = v2
			live += 1
			made += 1

# ---------------------------------------------------------------- housekeeping
func _cleanup(centre: Vector3, cam: Camera3D) -> void:
	var total := 0
	for n in get_tree().get_nodes_in_group(&"vehicles"):
		var v := n as Vehicle
		total += 1
		if v.personal or v.has_meta("home") or v.has_player() or v.is_queued_for_deletion():
			continue
		var d := v.global_position.distance_to(centre)
		var seen := d < 160.0 and _visible(cam, v.global_position)
		if v.destroyed:
			if v._dead_time > 45.0 and (d > 80.0 or not seen):
				_remove(v, "wreck")
			continue
		if v.owner_tag == "parked" or v.owner_tag == "police" or v.owner_tag == "service" or v.has_meta("static_spawn"):
			continue
		var ai := v.ai as AIDriver
		if ai != null and v.owner_tag == "traffic":
			if d > DESPAWN:
				_remove(v, "far")
			elif not seen and d > 55.0 and (ai.dead_end or ai.blocked > 22.0 or ai.stuck > 12.0):
				_remove(v, "stuck dead_end=%s blocked=%.0f stuck=%.0f" % [ai.dead_end, ai.blocked, ai.stuck])
			elif not Game.flags["traffic"] and not seen:
				_remove(v, "disabled")
			elif v.global_position.y < -3.0:
				_remove(v, "fell")
		elif v.ai == null:
			# abandoned (driver fled or was pulled out) or left behind by the player
			var used := v.player_driven_time > 0.0
			var age := Game.clock - maxf(v.player_driven_time, v.spawn_time)
			if (not used and d > 110.0 and not seen) or (used and d > 240.0 and age > 60.0) or total > 85:
				if d > 60.0 and not seen:
					_remove(v, "abandoned")

func _physics_process(delta: float) -> void:
	if Game.player == null:
		return
	var centre := Game.player_pos()
	var cam: Camera3D = Game.cam.cam if Game.cam != null else null
	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_spawn_cd = 0.1 if _initial else 0.5
		if ai_vehicles().size() < target_count():
			_try_spawn(centre, cam)
		else:
			_initial = false
	_park_cd -= delta
	if _park_cd <= 0.0:
		_park_cd = 0.2 if _initial else 0.7
		_update_parked(centre, cam)
	_clean_cd -= delta
	if _clean_cd <= 0.0:
		_clean_cd = 1.0
		_cleanup(centre, cam)
		# new car models may have been exported since boot (asset pipeline) - cheap to refresh
		for v in ai_vehicles():
			v.lights_on = Game.time != null and (Game.time.is_night or Game.time.rain > 0.5)
	_static_cd -= delta
	if _static_cd <= 0.0:
		_static_cd = 10.0
		_update_static(centre)

## Admin / benchmark helpers.
func clear_traffic() -> void:
	for v in ai_vehicles():
		_remove(v)

func vehicle_count() -> int:
	return get_tree().get_nodes_in_group(&"vehicles").size()
