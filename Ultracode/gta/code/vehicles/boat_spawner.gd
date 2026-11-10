extends Node
## Marina moorings: puts a few boats at the world's "boat" spawn points at boot (owner_tag
## "parked", on a soft damped mooring line) and keeps the slips stocked: a slip whose boat was
## taken far away, sunk or destroyed gets a fresh boat once the player is out of sight.
##
## Created by the registrar hook in vehicles_bikeboat_registry.gd at EventBus.game_ready (added
## under Game.get_entities_root()), or usable as a BootManifest world system "boats" (setup()).
## Command line: --flag=no_moorings (or --no_moorings) disables it. Docs: docs/BIKES_BOATS.md.

## Boats per slip, in order. The first slip is the named location "boat_spawn".
const LAYOUT: Array[String] = ["speedboat", "jetski", "speedboat", "dinghy", "jetski"]
const MAX_SLIPS := 5
const PIER_GAP := 0.4            ## m between the hull side and the pier face
const REFILL_SECONDS := 20.0
const REFILL_PLAYER_DIST := 120.0
const GONE_DIST := 60.0          ## a boat further than this from its slip counts as taken

var slips: Array[Dictionary] = []    ## {spec_id, xform, vehicle}
var _spawned: bool = false
var _refill_t: float = REFILL_SECONDS


func setup() -> void:
	_spawn_all()


func _ready() -> void:
	if not _spawned:
		_spawn_all.call_deferred()


func _spawn_all() -> void:
	if _spawned or not is_inside_tree():
		return
	_spawned = true
	var vm := Game.get_system("vehicles")
	if vm == null or not vm.has_method("spawn_vehicle") or Game.world == null:
		return
	var points: Array[Transform3D] = []
	if Game.world.has_method("get_locations") and (Game.world.call("get_locations") as Dictionary).has("boat_spawn"):
		points.append(Game.get_location("boat_spawn"))
	if Game.world.has_method("get_spawn_points"):
		var list: Variant = Game.world.call("get_spawn_points", "boat")
		if list is Array:
			for t: Variant in list:
				if t is Transform3D and _far_from_all(points, (t as Transform3D).origin, 9.0):
					points.append(t)
	var used := 0
	for i in points.size():
		if used >= MAX_SLIPS:
			break
		# spread the slips over the piers instead of filling the first one
		var idx := (i * 5) % points.size() if i > 0 else 0
		var xf := points[idx]
		if not _far_from_all(_slip_points(), xf.origin, 9.0):
			continue
		var spec_id := _pick_spec(used)
		if spec_id == "":
			break
		slips.append({"spec_id": spec_id, "xform": xf, "vehicle": null, "placed": Transform3D()})
		_fill(slips.size() - 1)
		used += 1
	print("[BoatMoorings] %d boats moored" % _count_alive())


func _slip_points() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for s: Dictionary in slips:
		out.append(s["xform"])
	return out


func _far_from_all(list: Array[Transform3D], p: Vector3, d: float) -> bool:
	for t: Transform3D in list:
		if Vector2(t.origin.x - p.x, t.origin.z - p.z).length() < d:
			return false
	return true


func _pick_spec(index: int) -> String:
	var vm := Game.get_system("vehicles")
	for k in LAYOUT.size():
		var id := LAYOUT[(index + k) % LAYOUT.size()]
		if not vm.has_method("can_spawn") or bool(vm.call("can_spawn", id)):
			return id
	return ""


func _count_alive() -> int:
	var n := 0
	for s: Dictionary in slips:
		var v: Variant = s["vehicle"]
		if v != null and is_instance_valid(v):
			n += 1
	return n


func _fill(i: int) -> void:
	var s := slips[i]
	var xf: Transform3D = s["xform"]
	var v := Game.spawn_vehicle(str(s["spec_id"]), xf, {"owner_tag": "parked"}) as Node3D
	if v == null:
		return
	var placed := _berth(v, xf)
	if v.has_method("teleport"):
		v.call("teleport", placed)
	else:
		v.global_transform = placed
	if v.has_method("set_moored"):
		v.call("set_moored", placed)
	v.set_meta("mooring_slip", i)
	s["vehicle"] = v
	s["placed"] = placed


## Slide the boat sideways towards the nearest pier face so it lies alongside with a small gap
## (the spawn points sit in the middle of the slips). The water surface sets the height.
func _berth(v: Node3D, xf: Transform3D) -> Transform3D:
	var half := 1.0
	var aabb: Variant = v.get("body_aabb")
	if aabb is AABB:
		half = (aabb as AABB).size.x * 0.5
	var space := v.get_world_3d().direct_space_state
	var right := xf.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT
	var best := INF
	var best_dir := Vector3.ZERO
	for dir: Vector3 in [right, -right]:
		for h: float in [0.95, 0.6]:
			var from := Vector3(xf.origin.x, h, xf.origin.z)
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * 7.0, Layers.WORLD)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var d := from.distance_to(hit["position"] as Vector3)
			if d < best:
				best = d
				best_dir = dir
	var out := xf
	if best < INF:
		var shift := best - half - PIER_GAP
		if shift > 0.05:
			out.origin += best_dir * shift
	var y := Game.WATER_LEVEL
	var env := Game.get_system("environment")
	if env != null and env.has_method("get_wave_height"):
		y = float(env.call("get_wave_height", out.origin.x, out.origin.z))
	out.origin.y = y
	return out


func _process(delta: float) -> void:
	_refill_t -= delta
	if _refill_t > 0.0:
		return
	_refill_t = REFILL_SECONDS
	var pp := Game.get_player_position()
	for i in slips.size():
		var s := slips[i]
		var xf: Transform3D = s["xform"]
		if pp.distance_to(xf.origin) < REFILL_PLAYER_DIST:
			continue
		var v: Variant = s["vehicle"]
		var gone := v == null or not is_instance_valid(v)
		if not gone:
			var n3 := v as Node3D
			gone = bool(n3.get("destroyed")) or n3.global_position.distance_to(xf.origin) > GONE_DIST
			if gone and (n3 == Game.get_player_vehicle() or bool(n3.get("personal"))):
				gone = false
		if gone:
			s["vehicle"] = null
			_fill(i)


## Debug / tests: the moored boat of slip `i` (null if none).
func get_slip_vehicle(i: int) -> Node3D:
	if i < 0 or i >= slips.size():
		return null
	var v: Variant = slips[i]["vehicle"]
	if v != null and is_instance_valid(v):
		return v as Node3D
	return null
