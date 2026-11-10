extends Node
## Parks the free-roam aircraft (owner_tag "parked") at the world's spawn points and brings them
## back after they were wrecked or flown away. Created at boot by vehicles_air_registry.gd as a
## child of the Registry autoload (named "AircraftSpawner"); it waits for EventBus.game_ready.
##
## Slots (built from World.get_spawn_points("heli" / "plane") + named locations):
##   heli  point nearest `airport_helipad`      -> heli_police (the police air unit is based at the airfield)
##   heli  every other point (harbour, roofs)   -> heli_civil
##   rooftop_helipad (only if a roof is really there and no heli point already covers it) -> heli_civil
##   plane points on the apron (the runway-start point is skipped: the runway stays clear) -> plane_prop, plane_jet, ...
##   inside / in front of the airport_hangar (only if the space is free)                    -> plane_prop
## Every placement is ground-checked (ray) and clearance-checked (box query); blocked slots are skipped.
##
## Command line: --flag=no_parked_aircraft (or --no_parked_aircraft) or --disable=aircraft skips it all.

const TICK_SECONDS := 4.0
const RESPAWN_WRECK_SEC := 45.0      ## a wrecked / removed slot vehicle comes back after this
const RESPAWN_TAKEN_SEC := 120.0     ## a slot vehicle that was flown away comes back after this
const TAKEN_DISTANCE := 80.0
const PLAYER_CLEAR_DISTANCE := 120.0 ## never pop an aircraft in while the player is this close
const RUNWAY_KEEP_CLEAR := 30.0
const HANGAR_DEPTH := 12.0           ## metres from the hangar door location into the hangar

var enabled: bool = true
var slots: Array[Dictionary] = []    ## {spec, xform, vehicle, vacant_since, label}
var spawned_total: int = 0

var _tick_t: float = TICK_SECONDS
var _box_q: PhysicsShapeQueryParameters3D = null
var _ray_q: PhysicsRayQueryParameters3D = null
var _clock: float = 0.0


func _ready() -> void:
	if not EventBus.game_ready.is_connected(_on_game_ready):
		EventBus.game_ready.connect(_on_game_ready)


func _on_game_ready() -> void:
	if Game.flags.has("no_parked_aircraft") or Game.is_disabled("aircraft"):
		enabled = false
		return
	# static world colliders become queryable after a physics step
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_build_slots()
	for i in slots.size():
		_spawn_slot(i)
	print("[AircraftSpawner] parked %d aircraft in %d slots" % [get_parked().size(), slots.size()])


## Aircraft currently standing in their slots (still tagged "parked").
func get_parked() -> Array:
	var out: Array = []
	for s: Dictionary in slots:
		var v: Variant = s.get("vehicle", null)
		if v != null and is_instance_valid(v) and str((v as Node).get("owner_tag")) == "parked":
			out.append(v)
	return out


func get_slots() -> Array[Dictionary]:
	return slots


func set_enabled(on: bool) -> void:
	enabled = on


## Admin: put a fresh aircraft into every empty slot now (player distance rules ignored).
func respawn_all() -> void:
	for i in slots.size():
		var v: Variant = slots[i].get("vehicle", null)
		if v == null or not is_instance_valid(v) or bool((v as Node).get("destroyed")):
			_spawn_slot(i)


# ==============================================================================================

func _build_slots() -> void:
	slots.clear()
	var world := Game.world
	if world == null or not world.has_method("get_spawn_points"):
		return
	var helipad := Game.get_location("airport_helipad").origin
	var runway := Game.get_location("airport_runway_start").origin
	var heli_pts: Array = world.get_spawn_points("heli")
	var police_i := -1
	var best := 30.0
	for i in heli_pts.size():
		var d := (heli_pts[i] as Transform3D).origin.distance_to(helipad)
		if d < best:
			best = d
			police_i = i
	for i in heli_pts.size():
		var xf: Transform3D = heli_pts[i]
		_add_slot("heli_police" if i == police_i else "heli_civil", xf, "heli point %d" % i)
	# rooftop helipad (provisional in WORLD until the city builder confirms it)
	var roof := Game.get_location("rooftop_helipad")
	var covered := false
	for s: Dictionary in slots:
		if (s["xform"] as Transform3D).origin.distance_to(roof.origin) < 8.0:
			covered = true
	if not covered and roof.origin.y > 4.0:
		_add_slot("heli_civil", roof, "rooftop helipad")
	# planes on the apron; the runway stays clear
	var plane_pts: Array = world.get_spawn_points("plane")
	var plane_specs: Array[String] = ["plane_prop", "plane_jet"]
	var k := 0
	for i in plane_pts.size():
		var xf: Transform3D = plane_pts[i]
		if Vector2(xf.origin.x - runway.x, xf.origin.z - runway.z).length() < RUNWAY_KEEP_CLEAR:
			continue
		_add_slot(plane_specs[k % plane_specs.size()], xf, "plane point %d" % i)
		k += 1
	# hangar: nose toward the door, a few metres inside
	var hangar := Game.get_location("airport_hangar")
	if hangar.origin.length() > 1.0:
		var into := -hangar.basis.z
		into.y = 0.0
		if into.length() > 0.1:
			into = into.normalized()
			var pos := hangar.origin + into * HANGAR_DEPTH
			var face_out := Basis(Vector3.UP, atan2(into.x, into.z))     # -Z (nose) points back out of the door
			_add_slot("plane_prop", Transform3D(face_out, pos), "hangar")


func _add_slot(spec_id: String, xf: Transform3D, label: String) -> void:
	slots.append({"spec": spec_id, "xform": xf, "vehicle": null, "vacant_since": -1.0, "label": label})


func _spawn_slot(i: int) -> Node3D:
	if i < 0 or i >= slots.size() or not enabled:
		return null
	var s := slots[i]
	var vm := Game.get_system("vehicles")
	if vm == null or not vm.has_method("spawn_vehicle"):
		return null
	if vm.has_method("can_spawn") and not bool(vm.call("can_spawn", s["spec"])):
		return null
	var xf := _placement(s["spec"], s["xform"])
	if xf.origin == Vector3.INF:
		return null
	var v: Node3D = vm.call("spawn_vehicle", s["spec"], xf, {"owner_tag": "parked", "asleep": true})
	if v == null:
		return null
	v.set_meta("air_slot", i)
	s["vehicle"] = v
	s["vacant_since"] = -1.0
	spawned_total += 1
	return v


## Ground-checked, clearance-checked transform for the slot; origin INF when the place is unusable.
func _placement(spec_id: String, xf: Transform3D) -> Transform3D:
	var bad := Transform3D(Basis.IDENTITY, Vector3.INF)
	if not is_inside_tree():
		return bad
	var space := get_viewport().world_3d.direct_space_state if get_viewport() != null else null
	if space == null:
		return bad
	if _ray_q == null:
		_ray_q = PhysicsRayQueryParameters3D.new()
		_ray_q.collision_mask = Layers.WORLD
		_box_q = PhysicsShapeQueryParameters3D.new()
		_box_q.collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.PROP
		_box_q.shape = BoxShape3D.new()
	var o := xf.origin
	_ray_q.from = o + Vector3.UP * 3.0
	_ray_q.to = o + Vector3.DOWN * 4.0
	var hit := space.intersect_ray(_ray_q)
	if hit.is_empty():
		return bad
	var gy := (hit["position"] as Vector3).y
	if absf(gy - o.y) > 1.6 or (hit["normal"] as Vector3).y < 0.9:
		return bad
	var heli := spec_id.begins_with("heli")
	var size := Vector3(9.0, 2.6, 9.0) if heli else Vector3(10.0, 2.4, 9.0)
	(_box_q.shape as BoxShape3D).size = size
	var basis := Basis(Vector3.UP, xf.basis.get_euler().y)
	_box_q.transform = Transform3D(basis, Vector3(o.x, gy + 0.35 + size.y * 0.5, o.z))
	if not space.intersect_shape(_box_q, 1).is_empty():
		return bad
	return Transform3D(basis, Vector3(o.x, gy, o.z))


func _process(delta: float) -> void:
	if not enabled or slots.is_empty():
		return
	_clock += delta
	_tick_t -= delta
	if _tick_t > 0.0:
		return
	_tick_t = TICK_SECONDS
	var ppos := Game.get_player_position()
	for i in slots.size():
		var s := slots[i]
		var origin := (s["xform"] as Transform3D).origin
		var v: Variant = s.get("vehicle", null)
		var vacant := false
		var wait := RESPAWN_WRECK_SEC
		if v == null or not is_instance_valid(v):
			vacant = true
		else:
			var n := v as Node3D
			if bool(n.get("destroyed")):
				vacant = true
			elif n.global_position.distance_to(origin) > TAKEN_DISTANCE:
				vacant = true
				wait = RESPAWN_TAKEN_SEC
		if not vacant:
			s["vacant_since"] = -1.0
			continue
		if float(s["vacant_since"]) < 0.0:
			s["vacant_since"] = _clock
			continue
		if _clock - float(s["vacant_since"]) < wait or ppos.distance_to(origin) < PLAYER_CLEAR_DISTANCE:
			continue
		_spawn_slot(i)
