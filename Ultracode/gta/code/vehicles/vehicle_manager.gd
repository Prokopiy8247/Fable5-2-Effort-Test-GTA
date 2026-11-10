class_name VehicleManager
extends Node3D
## World system "vehicles" (BootManifest): builds vehicles from spec + Blender GLB, keeps the
## list of live vehicles, enforces caps, removes wrecks, drives distance-based detail levels,
## and owns the pooled real light sources (headlight SpotLight3Ds, siren OmniLight3Ds).
##
## Everybody spawns through Game.spawn_vehicle(spec_id, xform, opts) which lands here.
## opts (all optional):
##   owner_tag: String          "civilian" (default by spec flags), "player", "police", "parked", "emergency", "taxi"
##   color: Color               primary paint (default: random from spec.default_colors for civilians)
##   color2: Color              secondary paint
##   mods: Dictionary           slot -> mod id
##   engine_on: bool            start with the engine running
##   health: float
##   asleep: bool               spawn sleeping at ride height (parked cars; wakes when touched)
##   locked: bool               can_enter() refuses
##   personal: bool             mark as the player's personal vehicle (saved)
##   headlights: int            0 / 1 / 2
##   siren: bool
##   velocity: Vector3          initial linear velocity (traffic spawned at speed)
##   with_driver: String        npc archetype id - stored as meta "with_driver" for the AI / traffic module
##   parent: Node               default Game.get_entities_root()
##   model_instance: Node3D     TEST ONLY: use this node tree instead of the spec's GLB
##   wheel_rays: int            cars: force 1 or 3 suspension rays per wheel
##   roof_open: bool            convertibles: start with the roof folded (default: random in dry weather)

const CLASS_SCRIPTS := {
	"car": "res://gta/code/vehicles/car.gd",
	"bike": "res://gta/code/vehicles/bike.gd",
	"bicycle": "res://gta/code/vehicles/bike.gd",
	"boat": "res://gta/code/vehicles/boat.gd",
	"heli": "res://gta/code/vehicles/helicopter.gd",
	"plane": "res://gta/code/vehicles/plane.gd",
}
const TICK_SECONDS := 0.2
const NEAR_DISTANCE := 45.0
const MID_DISTANCE := 110.0
const AUDIO_DISTANCE := 80.0
const HEADLIGHT_DISTANCE := 70.0
const OTHER_HEADLIGHTS := 4          ## real headlights for vehicles other than the player's
const SIREN_LIGHT_DISTANCE := 90.0

var vehicles: Array[VehicleBase] = []
var max_vehicles: int = 90
var max_wrecks: int = 6
var wreck_lifetime: float = 55.0
var enabled: bool = true
var personal_vehicle: VehicleBase = null
## -1 = detail level by distance to the camera (normal). 0 / 1 / 2 pins that level for every
## vehicle (photo mode, showrooms, tests that measure wheel visuals far from the camera).
var detail_override: int = -1

var _scene_cache: Dictionary = {}
var _script_cache: Dictionary = {}
var _warned: Dictionary = {}
var _serial: int = 0
var _tick_t: float = 0.0
var _head_lights: Array[SpotLight3D] = []
var _head_owner: Array = []
var _head_side: PackedInt32Array = PackedInt32Array()
var _siren_lights: Array[OmniLight3D] = []
var _siren_vehicle: VehicleBase = null


func setup() -> void:
	_build_light_pool()
	SaveSystem.register_provider("vehicles", self)


func _ready() -> void:
	if _head_lights.is_empty():
		_build_light_pool()


func _exit_tree() -> void:
	# static caches hold shapes / materials / scenes: release them with the system
	VehicleBase.clear_static_caches()
	VehicleMods.clear_static_caches()
	VehicleLights.clear_static_caches()
	_scene_cache.clear()


func _build_light_pool() -> void:
	if not _head_lights.is_empty():
		return
	for i in 2 + OTHER_HEADLIGHTS:
		var l := SpotLight3D.new()
		l.name = "Headlight%d" % i
		l.light_color = Color(1.0, 0.95, 0.84)
		l.shadow_enabled = false
		l.spot_range = 34.0
		l.spot_angle = 36.0
		l.spot_angle_attenuation = 1.6
		l.spot_attenuation = 0.9
		l.light_energy = 6.0
		l.light_specular = 0.3
		l.visible = false
		add_child(l)
		_head_lights.append(l)
		_head_owner.append(null)
		_head_side.append(2)
	for i in 2:
		var o := OmniLight3D.new()
		o.name = "SirenLight%d" % i
		o.light_color = Color(1.0, 0.12, 0.1) if i == 0 else Color(0.15, 0.35, 1.0)
		o.omni_range = 14.0
		o.omni_attenuation = 1.2
		o.light_energy = 5.0
		o.shadow_enabled = false
		o.visible = false
		add_child(o)
		_siren_lights.append(o)


# ==============================================================================================
# spawning
# ==============================================================================================

## Build and add a vehicle. Returns null (with one warning per spec) if the spec is unknown,
## its GLB has not been exported yet, or its vehicle class is not implemented.
func spawn_vehicle(spec_id: String, xform: Transform3D, opts: Dictionary = {}) -> Node3D:
	var spec := Registry.get_def("vehicles", spec_id) as VehicleSpec
	if spec == null:
		_warn_once("spec:" + spec_id, "VehicleManager: unknown vehicle spec '%s'" % spec_id)
		return null
	var cls := _class_script(spec.vehicle_class)
	if cls == null:
		_warn_once("class:" + spec.vehicle_class, "VehicleManager: vehicle class '%s' (spec %s) is not implemented yet" % [spec.vehicle_class, spec_id])
		return null
	var model: Node3D = null
	var injected: Variant = opts.get("model_instance", null)
	if injected != null and is_instance_valid(injected) and injected is Node3D:
		model = injected
	else:
		var scene := _model_scene(spec)
		if scene == null:
			_warn_once("model:" + spec_id, "VehicleManager: model missing for '%s' (%s) - not spawned" % [spec_id, spec.get_model_path()])
			return null
		model = scene.instantiate() as Node3D
	if model == null:
		return null
	var v := cls.new() as VehicleBase
	if v == null:
		model.free()
		return null
	_serial += 1
	v.name = "Veh_%s_%d" % [spec_id, _serial]
	if opts.has("wheel_rays"):
		v.set("wheel_rays", int(opts["wheel_rays"]))
	if not v.build(spec, model, opts):
		v.free()
		return null

	var parent: Node = opts.get("parent", null)
	if parent == null or not is_instance_valid(parent):
		parent = Game.get_entities_root()
	if parent == null:
		parent = self
	var world_xf := Transform3D(xform.basis.orthonormalized(), xform.origin + xform.basis.y.normalized() * 0.015)
	var p3 := parent as Node3D
	v.transform = (p3.global_transform.affine_inverse() * world_xf) if (p3 != null and p3.is_inside_tree()) else world_xf
	parent.add_child(v)

	# appearance
	if opts.has("owner_tag"):
		v.owner_tag = str(opts["owner_tag"])
	if bool(opts.get("asleep", false)) and not opts.has("owner_tag"):
		v.owner_tag = "parked"
	var mods: Variant = opts.get("mods", null)
	if mods is Dictionary and not (mods as Dictionary).is_empty():
		v.apply_mods(mods)
	if opts.has("color"):
		var c2: Color = opts.get("color2", Color(0, 0, 0, 0))
		v.set_paint(opts["color"], c2)
	elif not spec.fixed_livery and not spec.default_colors.is_empty():
		var primary := spec.default_colors[Game.rng.randi() % spec.default_colors.size()]
		var secondary := Color(0, 0, 0, 0)
		if not spec.secondary_colors.is_empty():
			secondary = spec.secondary_colors[Game.rng.randi() % spec.secondary_colors.size()]
		v.set_paint(primary, secondary)

	# state
	if opts.has("health"):
		v.health = clampf(float(opts["health"]), 1.0, v.max_health)
	v.locked = bool(opts.get("locked", false))
	if opts.has("with_driver"):
		v.set_meta("with_driver", str(opts["with_driver"]))
	if bool(opts.get("engine_on", false)):
		v.start_engine()
	if v.has_convertible_roof():
		var open_roof := false
		if opts.has("roof_open"):
			open_roof = bool(opts["roof_open"])
		elif v.owner_tag == "civilian" or v.owner_tag == "parked":
			open_roof = not Weather.is_raining() and Game.rng.randf() < 0.4
		v.set_roof_open(open_roof, true)
	if opts.has("headlights"):
		v.set_headlights(int(opts["headlights"]))
	if bool(opts.get("siren", false)):
		v.set_siren(true)
	if opts.has("velocity"):
		v.linear_velocity = opts["velocity"]
	elif bool(opts.get("asleep", false)):
		v.sleeping = true
	if bool(opts.get("personal", false)):
		set_personal_vehicle(v)

	vehicles.append(v)
	v.tree_exiting.connect(_on_vehicle_exiting.bind(v))
	if not enabled:
		v.process_mode = Node.PROCESS_MODE_DISABLED
	_enforce_caps(v)
	EventBus.vehicle_spawned.emit(v)
	return v


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)


func _class_script(vehicle_class: String) -> GDScript:
	if _script_cache.has(vehicle_class):
		return _script_cache[vehicle_class]
	var s: GDScript = null
	var path := str(CLASS_SCRIPTS.get(vehicle_class, ""))
	if path != "" and ResourceLoader.exists(path):
		s = load(path) as GDScript
		if s != null and not s.can_instantiate():
			s = null
	_script_cache[vehicle_class] = s
	return s


func _model_scene(spec: VehicleSpec) -> PackedScene:
	var path := spec.get_model_path()
	if _scene_cache.has(path) and _scene_cache[path] != null:
		return _scene_cache[path]
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	if ps != null:
		_scene_cache[path] = ps      # misses are not cached: the GLB may be exported later
	return ps


func _on_vehicle_exiting(v: VehicleBase) -> void:
	vehicles.erase(v)
	if v == personal_vehicle:
		personal_vehicle = null
	if v == _siren_vehicle:
		_siren_vehicle = null
	for i in _head_owner.size():
		if _head_owner[i] == v:
			_head_owner[i] = null


# ==============================================================================================
# queries
# ==============================================================================================

func get_vehicles() -> Array:
	return vehicles.duplicate()


func get_vehicle_count() -> int:
	return vehicles.size()


func get_spec(spec_id: String) -> VehicleSpec:
	return Registry.get_def("vehicles", spec_id) as VehicleSpec


## True if spawn_vehicle(spec_id) can succeed right now (spec, class script and GLB exist).
func can_spawn(spec_id: String) -> bool:
	var spec := get_spec(spec_id)
	return spec != null and _class_script(spec.vehicle_class) != null and spec.has_model()


## Spec ids that can be spawned right now. filter: "" all, "civilian", "police", "emergency", "taxi".
func get_spawnable_ids(filter: String = "") -> Array[String]:
	var out: Array[String] = []
	for id: Variant in Registry.ids("vehicles"):
		var spec := get_spec(str(id))
		if spec == null or not can_spawn(spec.id):
			continue
		match filter:
			"civilian":
				if spec.is_police or spec.is_emergency or spec.is_taxi:
					continue
			"police":
				if not spec.is_police:
					continue
			"emergency":
				if not spec.is_emergency:
					continue
			"taxi":
				if not spec.is_taxi:
					continue
		out.append(spec.id)
	return out


## Weighted random civilian spec id for ambient traffic / parked cars ("" if nothing can spawn).
func get_random_civilian_id(vehicle_class: String = "car") -> String:
	var ids: Array[String] = []
	var weights: Array[float] = []
	var total := 0.0
	for id: String in get_spawnable_ids("civilian"):
		var spec := get_spec(id)
		if spec.vehicle_class != vehicle_class or spec.traffic_weight <= 0.0:
			continue
		ids.append(id)
		weights.append(spec.traffic_weight)
		total += spec.traffic_weight
	if ids.is_empty():
		return ""
	var roll := Game.rng.randf() * total
	for i in ids.size():
		roll -= weights[i]
		if roll <= 0.0:
			return ids[i]
	return ids[ids.size() - 1]


## Nearest vehicle to `pos` within max_dist (optionally only ones `who` can enter), or null.
func get_nearest_vehicle(pos: Vector3, max_dist: float = 6.0, who: Node = null) -> Node3D:
	var best: VehicleBase = null
	var best_d := max_dist
	for v: VehicleBase in vehicles:
		if not is_instance_valid(v):
			continue
		if who != null and not v.can_enter(who):
			continue
		var d := v.get_center_position().distance_to(pos) - v.body_aabb.size.x * 0.5
		if d < best_d:
			best_d = d
			best = v
	return best


func get_debug_info() -> Dictionary:
	var awake := 0
	var wrecks := 0
	for v: VehicleBase in vehicles:
		if is_instance_valid(v):
			if v.destroyed:
				wrecks += 1
			elif not v.sleeping:
				awake += 1
	return {"count": vehicles.size(), "awake": awake, "wrecks": wrecks, "max": max_vehicles}


# ==============================================================================================
# removal / caps
# ==============================================================================================

func despawn_vehicle(v: Node) -> void:
	var vb := v as VehicleBase
	if vb == null or not is_instance_valid(vb):
		return
	if not vb.get_occupants().is_empty():
		vb.eject_occupants()
	vehicles.erase(vb)
	if vb == personal_vehicle:
		personal_vehicle = null
	vb.queue_free()


## Remove every vehicle (the one the player sits in survives unless include_player_vehicle).
func clear_all(include_player_vehicle: bool = false) -> void:
	var pv := Game.get_player_vehicle()
	for v: VehicleBase in vehicles.duplicate():
		if not is_instance_valid(v):
			continue
		if v == pv and not include_player_vehicle:
			continue
		despawn_vehicle(v)


func set_enabled(on: bool) -> void:
	enabled = on
	for v: VehicleBase in vehicles:
		if is_instance_valid(v) and not v.is_player_driven:
			v.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func repair_all() -> void:
	for v: VehicleBase in vehicles:
		if is_instance_valid(v):
			v.repair()


func reset_for_respawn() -> void:
	pass


func _is_protected(v: VehicleBase) -> bool:
	return v.is_player_driven or v.personal or v == Game.get_player_vehicle()


func _enforce_caps(keep: VehicleBase) -> void:
	var guard := 0
	while vehicles.size() > max_vehicles and guard < 8:
		guard += 1
		var ref := _reference_position()
		var best: VehicleBase = null
		var best_score := -INF
		for v: VehicleBase in vehicles:
			if v == keep or not is_instance_valid(v) or _is_protected(v):
				continue
			if not v.destroyed and v.driver != null:
				continue
			var score := v.global_position.distance_to(ref)
			if v.destroyed:
				score += 2000.0
			elif v.owner_tag == "parked":
				score += 150.0
			if score > best_score:
				best_score = score
				best = v
		if best == null:
			return
		despawn_vehicle(best)


# ==============================================================================================
# tick: detail levels, lights, wrecks
# ==============================================================================================

func _reference_position() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_position
	return Game.get_player_position()


func _physics_process(delta: float) -> void:
	VehicleBase.advance_clock(delta)


func _process(delta: float) -> void:
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = TICK_SECONDS
		_tick()
	_update_lights()


func _tick() -> void:
	var ref := _reference_position()
	var pv := Game.get_player_vehicle() as VehicleBase
	var night := WorldClock.get_daylight() < 0.3
	var now := VehicleBase.now_msec()
	var cands: Array = []
	var wrecks: Array[VehicleBase] = []
	var siren_best: VehicleBase = null
	var siren_d := SIREN_LIGHT_DISTANCE
	for i in range(vehicles.size() - 1, -1, -1):
		var v := vehicles[i]
		if not is_instance_valid(v):
			vehicles.remove_at(i)
			continue
		var d := v.global_position.distance_to(ref)
		if detail_override >= 0:
			v.detail_level = mini(detail_override, 2)
		else:
			v.detail_level = 0 if (d < NEAR_DISTANCE or v.is_player_driven) else (1 if d < MID_DISTANCE else 2)
		v.audio_active = d < AUDIO_DISTANCE or v.is_player_driven
		if v.destroyed:
			wrecks.append(v)
			continue
		if v.global_position.y < -150.0 and not _is_protected(v):
			despawn_vehicle(v)
			continue
		if v.in_water and v.stalled and not _is_protected(v) and v.get_occupants().is_empty():
			var since := int(v.get_meta("sunk_msec", 0))
			if since == 0:
				v.set_meta("sunk_msec", now)
			elif now - since > 45000 and d > 40.0:
				despawn_vehicle(v)
				continue
		if v.driver != null and not v.is_player_driven:
			if night and v.headlight_mode == 0:
				v.set_headlights(1)
			elif not night and v.headlight_mode > 0:
				v.set_headlights(0)
		if v != pv and d < HEADLIGHT_DISTANCE and v.lights != null and v.lights.is_headlight_on():
			cands.append([d, v])
		if v.siren_on and d < siren_d:
			siren_d = d
			siren_best = v
	_siren_vehicle = siren_best

	# real headlights: two for the player's vehicle, one each for the nearest others
	for i in _head_owner.size():
		_head_owner[i] = null
	if pv != null and is_instance_valid(pv) and pv.lights != null and pv.lights.is_headlight_on():
		_head_owner[0] = pv
		_head_side[0] = 0
		_head_owner[1] = pv
		_head_side[1] = 1
	if not cands.is_empty():
		cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for k in mini(cands.size(), OTHER_HEADLIGHTS):
			_head_owner[2 + k] = cands[k][1]
			_head_side[2 + k] = 2

	_cleanup_wrecks(wrecks, ref, now)


func _cleanup_wrecks(wrecks: Array[VehicleBase], ref: Vector3, now: int) -> void:
	if wrecks.is_empty():
		return
	var oldest: VehicleBase = null
	var oldest_age := -1.0
	for w: VehicleBase in wrecks:
		var age := float(now - w.wreck_time_msec) / 1000.0
		var d := w.global_position.distance_to(ref)
		if (age > wreck_lifetime and d > 40.0) or age > wreck_lifetime * 2.5:
			despawn_vehicle(w)
			continue
		if age > oldest_age:
			oldest_age = age
			oldest = w
	if wrecks.size() > max_wrecks and oldest != null and is_instance_valid(oldest) and not oldest.is_queued_for_deletion():
		despawn_vehicle(oldest)


func _update_lights() -> void:
	for i in _head_lights.size():
		var l := _head_lights[i]
		var o: Variant = _head_owner[i]
		if o == null or not is_instance_valid(o):
			if l.visible:
				l.visible = false
			continue
		var v := o as VehicleBase
		if v.lights == null or not v.lights.is_headlight_on():
			if l.visible:
				l.visible = false
			continue
		var high := v.headlight_mode >= 2
		var solo := _head_side[i] == 2
		l.global_transform = v.lights.get_headlight_transform(_head_side[i])
		l.light_color = v.lights.head_color
		l.spot_range = (48.0 if high else 30.0) if not solo else 26.0
		l.spot_angle = 30.0 if high else 38.0
		l.light_energy = (9.0 if high else 5.5) if not solo else 5.0
		if not l.visible:
			l.visible = true
	var sv := _siren_vehicle
	var on := sv != null and is_instance_valid(sv) and sv.siren_on and sv.lights != null
	for i in _siren_lights.size():
		var s := _siren_lights[i]
		var lit := on and sv.lights.siren_phase == i
		if lit:
			s.global_position = sv.lights.get_siren_light_position(i)
		if s.visible != lit:
			s.visible = lit


# ==============================================================================================
# personal vehicle + save hooks
# ==============================================================================================

func set_personal_vehicle(v: Node) -> void:
	if personal_vehicle != null and is_instance_valid(personal_vehicle) and personal_vehicle != v:
		personal_vehicle.personal = false
	personal_vehicle = v as VehicleBase
	if personal_vehicle != null:
		personal_vehicle.personal = true


func get_personal_vehicle() -> Node3D:
	if personal_vehicle != null and is_instance_valid(personal_vehicle):
		return personal_vehicle
	return null


func get_save_data() -> Dictionary:
	var d := {}
	var pv := get_personal_vehicle() as VehicleBase
	if pv != null and not pv.destroyed:
		d["personal"] = pv.get_save_data()
	return d


func load_save_data(d: Dictionary) -> void:
	var p: Variant = d.get("personal", null)
	if p is Dictionary and not (p as Dictionary).is_empty():
		spawn_from_save(p, true)


## Recreate a vehicle from VehicleBase.get_save_data() (spec id, colours, mods, transform).
func spawn_from_save(data: Dictionary, as_personal: bool = true) -> Node3D:
	var spec_id := str(data.get("spec_id", ""))
	if spec_id == "":
		return null
	if as_personal:
		var old := get_personal_vehicle() as VehicleBase
		if old != null and not old.is_player_driven:
			despawn_vehicle(old)
	var pos := SaveSystem.array_to_vec3(data.get("position", null), Vector3.ZERO)
	var xf := Transform3D(Basis(Vector3.UP, float(data.get("yaw", 0.0))), pos)
	var v := spawn_vehicle(spec_id, xf, {"owner_tag": "player", "personal": as_personal, "asleep": true}) as VehicleBase
	if v != null:
		v.apply_save_data(data)
	return v
