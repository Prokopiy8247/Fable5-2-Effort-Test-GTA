class_name TrafficParking
extends RefCounted
## Parked cars on the world's `parking` spawn points (kerb-side bays + parking lots) near the focus.
##
## A parked car is a real VehicleBase spawned asleep ({"asleep": true}, owner_tag "parked", engine
## off): a sleeping Jolt body costs no physics and no script work. It wakes when something touches
## it (Jolt contact), when somebody gets in (occupant_enter) or when it is damaged (TrafficSystem
## listens to EventBus.vehicle_damaged and wakes it). A bay is filled deterministically (stable
## per-bay roll against the fill ratio), so the same street looks the same when you come back.
## Cars that were moved, entered or driven leave the parking list and become ordinary world
## vehicles (the traffic system cleans them up later when they are far and unseen).

const CAP := 40
const SPAWN_RADIUS := 115.0
const DESPAWN_RADIUS := 165.0
const MIN_UNSEEN_SPAWN := 85.0      ## inside the camera view bays only fill beyond this distance
const CELL := 40.0
const SPAWNS_PER_TICK := 4
const JUNCTION_CLEAR := 14.0        ## no parked cars this close to a junction box (turning cars swing wide)

var sys: Node = null                ## TrafficSystem
var bays: Array[Transform3D] = []
var bay_vehicle: Array = []         ## per bay: the parked vehicle or null
var bay_roll := PackedFloat32Array()
var bay_district := PackedStringArray()
var parked: Array = []              ## [bay index, vehicle, origin Vector3]
var spawned_total: int = 0
var released_total: int = 0
var skipped_near_junction: int = 0
var _grid: Dictionary = {}          ## Vector2i -> PackedInt32Array
var _query: PhysicsShapeQueryParameters3D = null
var _ray: PhysicsRayQueryParameters3D = null


func setup(p_sys: Node, world: Node) -> void:
	sys = p_sys
	bays.clear()
	if world == null or not world.has_method("get_spawn_points"):
		return
	var pts: Variant = world.call("get_spawn_points", "parking")
	if not (pts is Array):
		return
	var lanes: TrafficLanes = sys.get("lanes") if sys != null else null
	for p: Variant in pts:
		if not (p is Transform3D):
			continue
		var o := (p as Transform3D).origin
		var near_junction := false
		if lanes != null:
			for k in lanes.node_count:
				if lanes.node_legs[k] >= 3 and Vector2(o.x - lanes.node_pos[k].x, o.z - lanes.node_pos[k].z).length() < lanes.node_radius[k] + JUNCTION_CLEAR:
					near_junction = true
					break
		if near_junction:
			skipped_near_junction += 1
			continue
		bays.append(p)
	bay_vehicle.resize(bays.size())
	bay_roll.resize(bays.size())
	bay_district.resize(bays.size())
	for i in bays.size():
		var o := bays[i].origin
		# stable pseudo random roll per bay (independent of Game.rng so it never changes)
		var h := hash(Vector2i(roundi(o.x * 10.0), roundi(o.z * 10.0)))
		bay_roll[i] = float(h & 0xFFFF) / 65535.0
		bay_district[i] = str(world.call("get_district", o)) if world.has_method("get_district") else "midtown"
		var c := Vector2i(floori(o.x / CELL), floori(o.z / CELL))
		var arr: PackedInt32Array = _grid.get(c, PackedInt32Array())
		arr.append(i)
		_grid[c] = arr
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.4, 5.2)
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = box
	_query.collision_mask = Layers.VEHICLE | Layers.PLAYER | Layers.NPC
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = Layers.WORLD


func count() -> int:
	return parked.size()


func asleep_count() -> int:
	var n := 0
	for e: Array in parked:
		var v: Variant = e[1]
		if v != null and is_instance_valid(v) and (v as RigidBody3D).sleeping:
			n += 1
	return n


func is_parked(v: Node) -> bool:
	for e: Array in parked:
		if e[1] == v:
			return true
	return false


func fill_ratio() -> float:
	var dens := 1.0
	if sys != null and sys.has_method("get_density_factor"):
		dens = float(sys.call("get_density_factor"))
	var night := 0.0
	if WorldClock.has_method("get_daylight"):
		night = 1.0 - clampf(WorldClock.get_daylight() * 1.6, 0.0, 1.0)
	return clampf((0.5 + 0.14 * night) * clampf(dens, 0.0, 1.4), 0.0, 0.85)


## 1 Hz: drop moved / entered cars, despawn far untouched ones, fill free bays near the focus.
## `initial`: fill in view too (boot, set_enabled, teleport cut), `budget` cars at most (-1 = CAP).
func tick(focus: Vector3, space: PhysicsDirectSpaceState3D, initial: bool, budget_override: int = -1) -> void:
	if bays.is_empty():
		return
	# ---------------------------------------------------------------- bookkeeping
	for i in range(parked.size() - 1, -1, -1):
		var e: Array = parked[i]
		var bi: int = e[0]
		var v: Variant = e[1]
		if v == null or not is_instance_valid(v) or (v as Node).is_queued_for_deletion():
			bay_vehicle[bi] = null
			parked.remove_at(i)
			continue
		var body := v as RigidBody3D
		var moved := body.global_position.distance_to(e[2]) > 0.6 or body.global_transform.basis.y.y < 0.9
		var used: bool = v.get("driver") != null or bool(v.get("is_player_driven")) or str(v.get("owner_tag")) != "parked" \
				or bool(v.get("destroyed"))
		if moved or used:
			# no longer a parked prop: an ordinary world vehicle from now on
			bay_vehicle[bi] = null
			parked.remove_at(i)
			released_total += 1
			if sys != null and sys.has_method("adopt_orphan"):
				sys.call("adopt_orphan", v)
			continue
		var d := Vector2(body.global_position.x - focus.x, body.global_position.z - focus.z).length()
		if d > DESPAWN_RADIUS and not bool(sys.call("is_seen", body.global_position)):
			bay_vehicle[bi] = null
			parked.remove_at(i)
			sys.call("despawn_vehicle_node", v)
	# ---------------------------------------------------------------- fill
	if parked.size() >= CAP or space == null:
		return
	var ratio := fill_ratio()
	if ratio <= 0.0:
		return
	var cands: Array = []
	var c0 := Vector2i(floori((focus.x - SPAWN_RADIUS) / CELL), floori((focus.z - SPAWN_RADIUS) / CELL))
	var c1 := Vector2i(floori((focus.x + SPAWN_RADIUS) / CELL), floori((focus.z + SPAWN_RADIUS) / CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var arr: Variant = _grid.get(Vector2i(cx, cz), null)
			if arr == null:
				continue
			for bi: int in (arr as PackedInt32Array):
				if bay_vehicle[bi] != null or bay_roll[bi] > ratio:
					continue
				var o := bays[bi].origin
				var d := Vector2(o.x - focus.x, o.z - focus.z).length()
				if d > SPAWN_RADIUS:
					continue
				cands.append([d, bi])
	if cands.is_empty():
		return
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var spawned := 0
	var budget := CAP if initial else SPAWNS_PER_TICK
	if budget_override >= 0:
		budget = budget_override
	for c: Array in cands:
		if parked.size() >= CAP or spawned >= budget:
			break
		var bi: int = c[1]
		var o := bays[bi].origin
		if not initial and float(c[0]) < MIN_UNSEEN_SPAWN and bool(sys.call("is_seen", o)):
			continue
		if _spawn_at(bi, space):
			spawned += 1


func _spawn_at(bi: int, space: PhysicsDirectSpaceState3D) -> bool:
	var xf := bays[bi]
	var o := xf.origin
	# exact ground height (road / lot surface)
	_ray.from = Vector3(o.x, o.y + 4.0, o.z)
	_ray.to = Vector3(o.x, o.y - 4.0, o.z)
	var hit := space.intersect_ray(_ray)
	var y := o.y
	if not hit.is_empty():
		y = (hit["position"] as Vector3).y
	var f := -xf.basis.z
	f.y = 0.0
	var yaw := atan2(-f.x, -f.z) if f.length() > 0.01 else 0.0
	var place := Transform3D(Basis(Vector3.UP, yaw), Vector3(o.x, y, o.z))
	# something already stands there (the player's own car, a pedestrian, a woken parked car)
	_query.transform = Transform3D(place.basis, place.origin + Vector3.UP * 0.95)
	if not space.intersect_shape(_query, 1).is_empty():
		bay_vehicle[bi] = null
		return false
	var spec := str(sys.call("pick_spec", bay_district[bi], true))
	if spec == "":
		return false
	var v := Game.spawn_vehicle(spec, place, {"owner_tag": "parked", "asleep": true, "engine_on": false})
	if v == null:
		return false
	v.set_meta("traffic_parked", true)
	bay_vehicle[bi] = v
	parked.append([bi, v, v.global_position])
	spawned_total += 1
	return true


## Wake a parked car (damage). It stays in the list until it actually moves.
func wake(v: Node) -> void:
	var rb := v as RigidBody3D
	if rb != null and rb.sleeping:
		rb.sleeping = false


func clear_all() -> void:
	for e: Array in parked:
		var v: Variant = e[1]
		if v != null and is_instance_valid(v):
			sys.call("despawn_vehicle_node", v)
	parked.clear()
	for i in bay_vehicle.size():
		bay_vehicle[i] = null
