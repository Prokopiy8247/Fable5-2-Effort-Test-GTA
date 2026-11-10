class_name VehicleBase
extends RigidBody3D
## Shared base of every drivable / flyable / floatable vehicle in Halcyon Bay.
##
## Owns everything that is NOT class-specific force integration: model indexing, collision hull,
## paint, mods, seats / occupants / doors, lights, audio, health / damage / wreck state, crime
## hooks, character strikes, self-righting, water stall, save data.
## Subclasses (Car now; Bike, Boat, Helicopter, Plane next) override the `_build_drive`,
## `_integrate_vehicle`, `_update_visuals` and `_read_player_input` hooks. See docs/VEHICLES.md.
##
## Instances are created by VehicleManager.spawn_vehicle() (Game.spawn_vehicle) - never by hand.

const LOD_DISTANCE := 75.0
const WHEEL_VIS_DISTANCE := 260.0
const EXIT_PROBE_MASK := Layers.WORLD | Layers.VEHICLE | Layers.PROP
const SWEEP_MASK := Layers.PLAYER | Layers.NPC | Layers.PROP | Layers.GLASS | Layers.WORLD
const STRIKE_MIN_SPEED := 3.0
const COLLISION_DV_MIN := 1.5
const FLIP_RECOVER_SECONDS := 3.0
const LID_NAMES: Array[String] = ["hood", "trunk", "roof"]
const LID_PARTS: Array[String] = ["Hood", "Trunk", "Roof_Convertible"]
const LID_SPEED: Array[float] = [2.6, 2.6, 0.85]     ## open / close speed (1 / seconds)
const HOOD_ANGLE := 0.9          ## rad about the lid's local X (docs/VEHICLE_KIT.md: hood opens with +x)
const TRUNK_ANGLE := -1.0        ## trunk opens with -x
const TAILGATE_ANGLE := 1.5      ## pickup Tailgate (bottom hinge) folds flat with +x; it serves as the "trunk" lid
const RECOVER_DURATION := 0.9

# --- contract members (docs/ARCHITECTURE.md 6.5) ---------------------------------------------
var spec_id: String = ""
var vehicle_class: String = "car"      ## "car","bike","bicycle","boat","heli","plane"
var health: float = 1000.0
var max_health: float = 1000.0
var destroyed: bool = false
var driver: Node = null
var is_player_driven: bool = false
var owner_tag: String = "civilian"     ## "civilian","player","police","parked","emergency","taxi"
var is_police: bool = false
var is_emergency: bool = false
var engine_on: bool = false
var siren_on: bool = false
var speed_kmh: float = 0.0
var paint_primary: Color = Color(0.8, 0.8, 0.8)
var paint_secondary: Color = Color(0, 0, 0, 0)
var mods: Dictionary = {}              ## slot -> mod id (Registry kind "vehicle_mods")

# --- additional public state ------------------------------------------------------------------
var spec: VehicleSpec = null
var model: Node3D = null               ## instantiated GLB (file root)
var is_taxi: bool = false
var taxi_for_hire: bool = true         ## taxis: roof sign lit while true, the engine runs and no fare is aboard
var headlight_mode: int = 0            ## 0 off, 1 low, 2 high
var horn_on: bool = false
var indicator: int = 0                 ## 0 off, -1 left, 1 right, 2 hazards
var locked: bool = false               ## can_enter() refuses while true
var personal: bool = false             ## the player's saved personal vehicle
var detail_level: int = 0              ## 0 near, 1 mid, 2 far (set by VehicleManager)
var audio_active: bool = true          ## false = too far for loops (set by VehicleManager)
var in_water: bool = false
var stalled: bool = false              ## engine killed by water; repair() clears it
var on_fire: bool = false
var last_instigator: Node = null       ## who damaged this vehicle last
var body_aabb: AABB = AABB(Vector3(-0.9, 0.2, -2.2), Vector3(1.8, 1.2, 4.4))   ## body space
var paint_finish: String = ""          ## "", "gloss", "matte", "metallic"
var mod_stats: Dictionary = {}         ## accumulated mod effects (see VehicleMods.DEFAULT_STATS)
var self_righting: bool = true
var spawn_time_msec: int = 0
var wreck_time_msec: int = 0

# --- inputs -----------------------------------------------------------------------------------
var in_throttle: float = 0.0           ## -1 (reverse) .. 1
var in_steer: float = 0.0              ## -1 left .. 1 right
var in_brake: float = 0.0              ## 0 .. 1
var in_handbrake: bool = false
var in_pitch: float = 0.0              ## aircraft
var in_roll: float = 0.0
var in_yaw: float = 0.0
var in_power: float = 0.0

# --- helpers ----------------------------------------------------------------------------------
var lights: VehicleLights = null
var audio: VehicleAudio = null
var damage: VehicleDamage = null

# --- internals --------------------------------------------------------------------------------
var _nodes: Dictionary = {}            ## part name -> Node3D
var _surf_mi: Array[MeshInstance3D] = []
var _surf_idx: PackedInt32Array = PackedInt32Array()
var _surf_name: PackedStringArray = PackedStringArray()
var _surf_orig: Array[Material] = []
var _inst_mats: Dictionary = {}        ## material name -> per-instance Material
var _seat_nodes: Array[Node3D] = []
var _seat_exits: Array[Node3D] = []
var _seat_occupants: Array = []
var _seat_doors: Array[Node3D] = []
var _doors: Array[Node3D] = []
var _door_rest: Array[Transform3D] = []
var _door_open: PackedFloat32Array = PackedFloat32Array()
var _door_timer: PackedFloat32Array = PackedFloat32Array()
var _doors_active: bool = false
var _lid_node: Array[Node3D] = [null, null, null]       ## hood, trunk, convertible roof
var _lid_rest: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY, Transform3D.IDENTITY]
var _lid_angle: PackedFloat32Array = PackedFloat32Array([0.9, -1.0, 3.35])
var _lid_open: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
var _lid_target: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
var _exhaust_local: PackedVector3Array = PackedVector3Array()   ## body-space tail-pipe points (Exhaust_L/R or Exhaust)
var _lids_active: bool = false
var _scripted: bool = false            ## set_inputs() has been used
var _prev_owner_tag: String = ""
var _fwd_speed: float = 0.0
var _prev_lin: Vector3 = Vector3.ZERO
var _collision_cd: float = 0.0
var _pending_hits: Array = []          ## [other, dv, position, normal, pre_speed]
var _flip_t: float = 0.0
var _recover_t: float = -1.0
var _recover_from: Transform3D
var _recover_to: Transform3D
var _struck: Dictionary = {}           ## instance id -> [Node, expire_msec]
var _sweep_shape: BoxShape3D = null
var _sweep_q: PhysicsShapeQueryParameters3D = null
var _exit_q: PhysicsShapeQueryParameters3D = null
var _ray_q: PhysicsRayQueryParameters3D = null
var _water_t: float = 0.0
var _sweep_flip: bool = false
var _xp_t: float = 0.0
var _steering_wheel: Node3D = null
var _steering_rest: Transform3D
var _steering_axis: Vector3 = Vector3.BACK
var _built: bool = false

static var _shape_cache: Dictionary = {}     ## model path -> Array of [Shape3D, Transform3D]
static var _burnt_cache: Dictionary = {}     ## original material instance id -> burnt Material
## Game-time clock shared by every vehicle. VehicleManager advances it once per physics frame, so
## cooldowns and lifetimes respect pause, Engine.time_scale and --fixed-fps (never wall time).
static var _clock: float = 0.0


static func clear_static_caches() -> void:
	_shape_cache.clear()
	_burnt_cache.clear()


static func advance_clock(delta: float) -> void:
	_clock += delta


## Milliseconds of simulated vehicle time (use instead of Time.get_ticks_msec()).
static func now_msec() -> int:
	return int(_clock * 1000.0)


# ==============================================================================================
# construction
# ==============================================================================================

## Assemble the vehicle from its spec and an instantiated model (GLB file root).
## Called by VehicleManager before the node enters the tree. Returns false if the model is unusable.
func build(p_spec: VehicleSpec, p_model: Node3D, opts: Dictionary = {}) -> bool:
	if p_spec == null or p_model == null:
		return false
	spec = p_spec
	spec_id = spec.id
	vehicle_class = spec.vehicle_class
	is_police = spec.is_police
	is_emergency = spec.is_emergency
	is_taxi = spec.is_taxi
	max_health = spec.max_health
	health = max_health
	owner_tag = "police" if is_police else ("emergency" if is_emergency else ("taxi" if is_taxi else "civilian"))
	mod_stats = VehicleMods.DEFAULT_STATS.duplicate()
	spawn_time_msec = VehicleBase.now_msec()

	mass = spec.mass
	collision_layer = Layers.VEHICLE
	collision_mask = Layers.VEHICLE_MASK
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.05
	contact_monitor = true
	max_contacts_reported = 6
	continuous_cd = true
	can_sleep = true
	var pm := PhysicsMaterial.new()
	pm.friction = spec.hull_friction
	pm.bounce = 0.0
	physics_material_override = pm
	add_to_group("vehicle")
	add_to_group("damageable")

	model = p_model
	model.name = "Model"
	add_child(model)
	_index_nodes()
	_measure_body()
	_build_collision()
	_index_surfaces(model)
	_setup_parts()
	_build_seats()
	_build_drive(opts)
	_apply_mass_properties()

	lights = VehicleLights.new()
	lights.setup(self)
	audio = VehicleAudio.new()
	audio.setup(self)
	damage = VehicleDamage.new()
	damage.setup(self)

	_ray_q = PhysicsRayQueryParameters3D.new()
	_ray_q.exclude = [get_rid()]
	_ray_q.collision_mask = Layers.GROUND_MASK

	var authored := get_original_material("M_Paint_Primary") as BaseMaterial3D
	if authored != null:
		paint_primary = authored.albedo_color
	var authored2 := get_original_material("M_Paint_Secondary") as BaseMaterial3D
	if authored2 != null:
		paint_secondary = authored2.albedo_color
	_built = true
	return true


## Hook: build wheels / rotors / hull data. `opts` are the spawn options.
func _build_drive(_opts: Dictionary) -> void:
	pass


func _index_nodes() -> void:
	_nodes.clear()
	for n: Node in model.find_children("*", "Node3D", true, false):
		var key := String(n.name)
		if not _nodes.has(key):
			_nodes[key] = n


## Named part of the model ("Body", "Wheel_FL", "Seat_Driver" ...) or null.
func get_part(part_name: String) -> Node3D:
	var n: Variant = _nodes.get(part_name, null)
	if n != null and is_instance_valid(n):
		return n as Node3D
	return null


func has_part(part_name: String) -> bool:
	return get_part(part_name) != null


## Transform of a descendant relative to this body (valid before entering the tree).
func xform_in_body(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != self:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Merged AABB (body space) of every mesh at / below `n`.
func aabb_in_body(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var list: Array[Node] = [n]
	list.append_array(n.find_children("*", "MeshInstance3D", true, false))
	for c: Node in list:
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a := xform_in_body(mi) * mi.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _measure_body() -> void:
	var body := get_part("Body")
	if body != null:
		var a := aabb_in_body(body)
		if a.size.length() > 0.5:
			body_aabb = a
			return
	var merged := AABB()
	var first := true
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var nm := String(n.name)
		if nm.begins_with("Col_") or nm.begins_with("Wheel") or nm.begins_with("Mod_"):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var a := xform_in_body(mi) * mi.get_aabb()
		if first:
			merged = a
			first = false
		else:
			merged = merged.merge(a)
	if not first:
		body_aabb = merged


func _build_collision() -> void:
	var key := model.scene_file_path
	var shapes: Array = []
	if key != "" and _shape_cache.has(key):
		shapes = _shape_cache[key]
	else:
		for part_name: String in _nodes:
			if not part_name.begins_with("Col_"):
				continue
			var mi := _nodes[part_name] as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var pts := _convex_points(mi)
			if pts.size() >= 4:
				var sh := ConvexPolygonShape3D.new()
				sh.points = pts
				shapes.append([sh, Transform3D.IDENTITY])
		if shapes.is_empty():
			shapes = _fallback_shapes()
		if key != "":
			_shape_cache[key] = shapes
	var i := 0
	for entry: Array in shapes:
		var cs := CollisionShape3D.new()
		cs.name = "Hull%d" % i
		cs.shape = entry[0]
		cs.transform = entry[1]
		add_child(cs)
		i += 1


func _convex_points(mi: MeshInstance3D) -> PackedVector3Array:
	var xf := xform_in_body(mi)
	var seen := {}
	var out := PackedVector3Array()
	var floor_y := spec.hull_clearance
	for p: Vector3 in mi.mesh.get_faces():
		var q := xf * p
		if q.y < floor_y:
			q.y = floor_y
		var k := Vector3i(roundi(q.x * 200.0), roundi(q.y * 200.0), roundi(q.z * 200.0))
		if not seen.has(k):
			seen[k] = true
			out.append(q)
	return out


## Used when the model has no Col_* helpers: a lower hull box and a narrower cabin box.
func _fallback_shapes() -> Array:
	var a := body_aabb
	var bottom := maxf(a.position.y, spec.hull_clearance)
	var top := a.position.y + a.size.y
	var mid := lerpf(bottom, top, 0.52)
	var lower := BoxShape3D.new()
	lower.size = Vector3(a.size.x, maxf(mid - bottom, 0.2), a.size.z)
	var cabin := BoxShape3D.new()
	cabin.size = Vector3(a.size.x * 0.82, maxf(top - mid, 0.2), a.size.z * 0.5)
	var c := a.get_center()
	return [
		[lower, Transform3D(Basis.IDENTITY, Vector3(c.x, (bottom + mid) * 0.5, c.z))],
		[cabin, Transform3D(Basis.IDENTITY, Vector3(c.x, (mid + top) * 0.5, c.z + a.size.z * 0.04))],
	]


func _index_surfaces(root: Node) -> void:
	var list: Array[Node] = [root]
	list.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for n: Node in list:
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or String(mi.name).begins_with("Col_"):
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			_surf_mi.append(mi)
			_surf_idx.append(s)
			_surf_name.append(m.resource_name if m != null else "")
			_surf_orig.append(m)


func _unindex_surfaces(root: Node) -> void:
	for i in range(_surf_mi.size() - 1, -1, -1):
		var mi := _surf_mi[i]
		if not is_instance_valid(mi) or mi == root or root.is_ancestor_of(mi):
			_surf_mi.remove_at(i)
			_surf_idx.remove_at(i)
			_surf_name.remove_at(i)
			_surf_orig.remove_at(i)


func _setup_parts() -> void:
	var lod1 := get_part("Body_LOD1")
	for part_name: String in _nodes:
		var n := _nodes[part_name] as Node3D
		if n == null:
			continue
		if part_name.begins_with("Col_"):
			n.visible = false
			continue
		if part_name.begins_with("Mod_"):
			n.visible = false
		if part_name.begins_with("Wheel"):
			_set_vis_range(n, 0.0, WHEEL_VIS_DISTANCE)
		elif lod1 != null and n != lod1 and not lod1.is_ancestor_of(n) and n is MeshInstance3D:
			_set_vis_range(n, 0.0, LOD_DISTANCE)
	if lod1 != null:
		_set_vis_range(lod1, LOD_DISTANCE, 0.0)
	# the four seat doors first (fixed order), then any other Door_* part (van / ambulance rear doors)
	var door_names: Array[String] = ["Door_FL", "Door_FR", "Door_RL", "Door_RR"]
	var extra_doors: Array[String] = []
	for part_name: String in _nodes:
		if part_name.begins_with("Door_") and not door_names.has(part_name):
			extra_doors.append(part_name)
	extra_doors.sort()
	door_names.append_array(extra_doors)
	for part_name: String in door_names:
		var d := get_part(part_name)
		if d != null:
			_doors.append(d)
			_door_rest.append(d.transform)
			_door_open.append(0.0)
			_door_timer.append(0.0)
	_steering_wheel = get_part("SteeringWheel")
	if _steering_wheel != null:
		_steering_rest = _steering_wheel.transform
		_steering_axis = _fit_disc_axis(_steering_wheel)
	# hinged lids (hood / trunk / convertible roof) and the mod parts that sit on them
	_lid_angle = PackedFloat32Array([HOOD_ANGLE, TRUNK_ANGLE, spec.roof_fold_angle])
	for i in LID_PARTS.size():
		var lid := get_part(LID_PARTS[i])
		if lid == null and LID_PARTS[i] == "Trunk" and has_part("Tailgate"):
			lid = get_part("Tailgate")
			_lid_angle[i] = TAILGATE_ANGLE
		_lid_node[i] = lid
		if lid != null:
			_lid_rest[i] = lid.transform
	_attach_if_on("Mod_Hood_A", "Hood")
	_attach_if_on("Mod_Spoiler_A", "Trunk")
	_attach_if_on("Mod_Spoiler_B", "Trunk")
	# tail pipes: the L / R pair when the model has both, else the single Exhaust marker, else the
	# lower rear corner of the body on the driver's side
	_exhaust_local = PackedVector3Array()
	if has_part("Exhaust_L") and has_part("Exhaust_R"):
		_exhaust_local.append(marker_local("Exhaust_L", Vector3.ZERO))
		_exhaust_local.append(marker_local("Exhaust_R", Vector3.ZERO))
	else:
		var bc := body_aabb.get_center()
		_exhaust_local.append(marker_local("Exhaust", Vector3(bc.x - body_aabb.size.x * 0.3, body_aabb.position.y + 0.12, body_aabb.end.z)))


## Re-parent a part under a hinged lid when it sits on that lid (a hood scoop on the hood, a boot
## spoiler on the trunk) so it moves with the lid. Roof spoilers etc. stay where they are.
func _attach_if_on(child_name: String, lid_name: String) -> void:
	var c := get_part(child_name)
	var lid := get_part(lid_name)
	if c == null or lid == null or c.get_parent() == lid or c.get_parent() == null:
		return
	var ca := aabb_in_body(c)
	var la := aabb_in_body(lid)
	if ca.size.length() < 0.01 or la.size.length() < 0.01:
		return
	var cc := ca.get_center()
	var grown := la.grow(0.2)
	if cc.x < grown.position.x or cc.x > grown.end.x or cc.z < grown.position.z or cc.z > grown.end.z or ca.end.y < la.position.y:
		return
	var local := xform_in_body(lid).affine_inverse() * xform_in_body(c)
	c.owner = null                      # runtime instance: scene ownership is irrelevant from here on
	c.get_parent().remove_child(c)
	lid.add_child(c)
	c.transform = local


func _set_vis_range(n: Node3D, begin: float, end: float) -> void:
	var list: Array[Node] = [n]
	list.append_array(n.find_children("*", "GeometryInstance3D", true, false))
	for c: Node in list:
		var g := c as GeometryInstance3D
		if g == null:
			continue
		g.visibility_range_begin = begin
		g.visibility_range_end = end
		g.visibility_range_begin_margin = 4.0 if begin > 0.0 else 0.0
		g.visibility_range_end_margin = 4.0 if end > 0.0 else 0.0


## Axis (node-local) a flat disc-like mesh spins about: direction of least vertex spread.
func _fit_disc_axis(n: Node3D) -> Vector3:
	var mi := n as MeshInstance3D
	if mi == null:
		for c: Node in n.find_children("*", "MeshInstance3D", true, false):
			mi = c as MeshInstance3D
			break
	if mi == null or mi.mesh == null:
		return Vector3.BACK
	var pts := mi.mesh.get_faces()
	if pts.size() < 3:
		return Vector3.BACK
	var c := Vector3.ZERO
	for p: Vector3 in pts:
		c += p
	c /= float(pts.size())
	var xx := 0.0; var yy := 0.0; var zz := 0.0; var xy := 0.0; var xz := 0.0; var yz := 0.0
	for p: Vector3 in pts:
		var d := p - c
		xx += d.x * d.x; yy += d.y * d.y; zz += d.z * d.z
		xy += d.x * d.y; xz += d.x * d.z; yz += d.y * d.z
	var tr := xx + yy + zz
	if tr < 1e-9:
		return Vector3.BACK
	# power iteration on (tr * I - C): its dominant eigenvector is C's smallest one
	var r0 := Vector3(tr - xx, -xy, -xz)
	var r1 := Vector3(-xy, tr - yy, -yz)
	var r2 := Vector3(-xz, -yz, tr - zz)
	var best := Vector3.BACK
	var best_spread := INF
	for start: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var v := start
		for it in 24:
			v = Vector3(r0.dot(v), r1.dot(v), r2.dot(v))
			var l := v.length()
			if l < 1e-12:
				break
			v /= l
		var spread := v.x * v.x * xx + v.y * v.y * yy + v.z * v.z * zz + 2.0 * (v.x * v.y * xy + v.x * v.z * xz + v.y * v.z * yz)
		if spread < best_spread:
			best_spread = spread
			best = v
	return best.normalized()


func _build_seats() -> void:
	var names: Array[String] = ["Driver"]
	for i in range(1, 8):
		names.append("Passenger_%d" % i)
	for nm: String in names:
		if _seat_nodes.size() >= maxi(spec.seats, 1):
			break
		var seat := get_part("Seat_" + nm)
		if seat == null:
			continue
		_seat_nodes.append(seat)
		_seat_exits.append(get_part("Exit_" + nm))
		_seat_occupants.append(null)
	if _seat_nodes.is_empty():
		# Model without markers: synthesise a left-hand-drive seat from the body bounds.
		var c := body_aabb.get_center()
		var seat := Node3D.new()
		seat.name = "Seat_Driver"
		model.add_child(seat)
		seat.position = model.transform.affine_inverse() * Vector3(c.x - body_aabb.size.x * 0.22, body_aabb.position.y + body_aabb.size.y * 0.42, c.z - body_aabb.size.z * 0.05)
		_nodes["Seat_Driver"] = seat
		_seat_nodes.append(seat)
		_seat_exits.append(null)
		_seat_occupants.append(null)
	var door_names: Array[String] = ["Door_FL", "Door_FR", "Door_RL", "Door_RR"]
	for i in _seat_nodes.size():
		var want := door_names[mini(i, 3)]
		var d := get_part(want)
		if d == null and i >= 2:
			d = get_part(door_names[i - 2])
		_seat_doors.append(d)


## Reference z (body space) the centre of mass is measured from. Cars: middle of the wheelbase.
func _get_reference_z() -> float:
	return body_aabb.get_center().z


func _apply_mass_properties() -> void:
	mass = spec.mass + float(mod_stats.get("mass_add", 0.0))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(spec.com_offset.x, spec.com_height + spec.com_offset.y, _get_reference_z() + spec.com_offset.z)
	var s := body_aabb.size
	var k := mass / 12.0
	inertia = Vector3(
		k * (s.y * s.y + s.z * s.z) * spec.inertia_scale.x,
		k * (s.x * s.x + s.z * s.z) * spec.inertia_scale.y,
		k * (s.x * s.x + s.y * s.y) * spec.inertia_scale.z)


func _ready() -> void:
	_prev_lin = linear_velocity


# ==============================================================================================
# materials / paint
# ==============================================================================================

## First authored (shared) material with this name, or null.
func get_original_material(mat_name: String) -> Material:
	var i := _surf_name.find(mat_name)
	return _surf_orig[i] if i >= 0 else null


func has_material(mat_name: String) -> bool:
	return _surf_name.find(mat_name) >= 0


## Per-instance copy of an authored material (created on first use and applied as a surface
## override on every surface that uses it). Null if the model has no such material.
func get_instance_material(mat_name: String) -> Material:
	if _inst_mats.has(mat_name):
		return _inst_mats[mat_name]
	var orig := get_original_material(mat_name)
	if orig == null:
		return null
	var inst: Material = orig.duplicate()
	inst.resource_name = mat_name
	_inst_mats[mat_name] = inst
	set_material_override(mat_name, inst)
	return inst


## Replace the per-instance material used for `mat_name` (e.g. a ShaderMaterial for indicators).
func set_instance_material(mat_name: String, mat: Material) -> void:
	_inst_mats[mat_name] = mat
	set_material_override(mat_name, mat)


func set_material_override(mat_name: String, mat: Material) -> void:
	for i in _surf_name.size():
		if _surf_name[i] == mat_name and is_instance_valid(_surf_mi[i]):
			_surf_mi[i].set_surface_override_material(_surf_idx[i], mat)


func set_paint(primary: Color, secondary: Color = Color(0, 0, 0, 0)) -> void:
	paint_primary = Color(primary.r, primary.g, primary.b, 1.0)
	if secondary.a > 0.0:
		paint_secondary = Color(secondary.r, secondary.g, secondary.b, 1.0)
	_apply_paint()


func _apply_paint() -> void:
	if destroyed:
		return
	var m1 := get_instance_material("M_Paint_Primary") as BaseMaterial3D
	if m1 != null:
		m1.albedo_color = paint_primary
		_apply_finish(m1, get_original_material("M_Paint_Primary") as BaseMaterial3D)
	if paint_secondary.a > 0.0 and has_material("M_Paint_Secondary"):
		var m2 := get_instance_material("M_Paint_Secondary") as BaseMaterial3D
		if m2 != null:
			m2.albedo_color = paint_secondary
			_apply_finish(m2, get_original_material("M_Paint_Secondary") as BaseMaterial3D)


func _apply_finish(m: BaseMaterial3D, orig: BaseMaterial3D) -> void:
	match paint_finish:
		"gloss":
			m.roughness = 0.18
			m.metallic = 0.1
			m.clearcoat_enabled = true
			m.clearcoat = 0.8
			m.clearcoat_roughness = 0.08
		"matte":
			m.roughness = 0.92
			m.metallic = 0.0
			m.clearcoat_enabled = false
		"metallic":
			m.roughness = 0.3
			m.metallic = 0.72
			m.clearcoat_enabled = true
			m.clearcoat = 0.5
			m.clearcoat_roughness = 0.15
		_:
			if orig != null:
				m.roughness = orig.roughness
				m.metallic = orig.metallic
				m.clearcoat_enabled = orig.clearcoat_enabled


## Shared darkened copy of a material for wrecks.
static func burnt_material(orig: Material) -> Material:
	var key := orig.get_instance_id() if orig != null else 0
	if _burnt_cache.has(key):
		return _burnt_cache[key]
	var m := StandardMaterial3D.new()
	var base := Color(0.3, 0.3, 0.3)
	var src := orig as BaseMaterial3D
	if src != null:
		base = src.albedo_color
	m.albedo_color = Color(0.035 + base.r * 0.07, 0.033 + base.g * 0.06, 0.03 + base.b * 0.05)
	m.roughness = 1.0
	m.metallic = 0.0
	m.resource_name = "Burnt"
	_burnt_cache[key] = m
	return m


func _apply_burnt_look() -> void:
	for i in _surf_mi.size():
		var mi := _surf_mi[i]
		if is_instance_valid(mi):
			mi.set_surface_override_material(_surf_idx[i], burnt_material(_surf_orig[i]))


func _restore_materials() -> void:
	for i in _surf_mi.size():
		var mi := _surf_mi[i]
		if not is_instance_valid(mi):
			continue
		var nm := _surf_name[i]
		mi.set_surface_override_material(_surf_idx[i], _inst_mats.get(nm, null))


# ==============================================================================================
# mods
# ==============================================================================================

## Replace the installed mods (slot -> mod id). Slots that are absent are stock.
func apply_mods(new_mods: Dictionary) -> void:
	mods = VehicleMods.sanitize(self, new_mods)
	VehicleMods.apply(self)
	_apply_mass_properties()
	_on_mods_changed()
	_apply_paint()
	if is_inside_tree():
		EventBus.vehicle_modified.emit(self)


## slot -> Array of mod ids this vehicle can install.
func get_mod_options() -> Dictionary:
	return VehicleMods.options_for(self)


## Hook: recompute tuning derived from spec + mod_stats.
func _on_mods_changed() -> void:
	pass


# ==============================================================================================
# occupants
# ==============================================================================================

func get_seat_count() -> int:
	return _seat_nodes.size()


func get_free_seat() -> int:
	for i in _seat_occupants.size():
		var o: Variant = _seat_occupants[i]
		if o == null or not is_instance_valid(o):
			return i
	return -1


func get_occupant(seat: int) -> Node:
	if seat < 0 or seat >= _seat_occupants.size():
		return null
	var o: Variant = _seat_occupants[seat]
	if o != null and is_instance_valid(o):
		return o as Node
	return null


func get_occupants() -> Array:
	var out: Array = []
	for i in _seat_occupants.size():
		var o := get_occupant(i)
		if o != null:
			out.append(o)
	return out


## True when somebody sits in a passenger seat (seat >= 1) - a taxi fare.
func has_fare() -> bool:
	for i in range(1, _seat_occupants.size()):
		if get_occupant(i) != null:
			return true
	return false


## Taxi system hook: switch the roof sign (for hire / off duty).
func set_taxi_sign(on: bool) -> void:
	taxi_for_hire = on
	if lights != null:
		lights.refresh()


func get_seat_of(who: Node) -> int:
	for i in _seat_occupants.size():
		if get_occupant(i) == who:
			return i
	return -1


## True if `who` could get in now (a free seat, or an NPC driver that can be pulled out).
func can_enter(_who: Node) -> bool:
	if destroyed or locked or not _built:
		return false
	if in_water and stalled:
		return false
	if is_inside_tree() and global_transform.basis.y.y < 0.35:
		return false
	if absf(_fwd_speed) > 14.0:
		return false
	if get_free_seat() >= 0:
		return true
	return driver != null and not is_player_driven


func occupant_enter(who: Node, seat: int = 0) -> void:
	if who == null or seat < 0 or seat >= _seat_nodes.size():
		return
	var prev := get_occupant(seat)
	if prev != null and prev != who:
		_evict(seat, Vector3.ZERO)
	_seat_occupants[seat] = who
	swing_door(seat)
	if seat == 0:
		driver = who
		is_player_driven = who.is_in_group("player")
		_scripted = false
		_clear_inputs()
		if is_player_driven:
			if owner_tag != "player":
				_prev_owner_tag = owner_tag
			owner_tag = "player"
			if headlight_mode == 0 and WorldClock.get_daylight() < 0.3:
				set_headlights(1)
		start_engine()
	sleeping = false
	if audio != null:
		audio.play_door(true)


## Frees the seat and returns a safe world transform for the occupant to stand at.
func occupant_exit(seat: int = 0) -> Transform3D:
	var xf := get_exit_transform(seat)
	if seat < 0 or seat >= _seat_nodes.size():
		return xf
	var who := get_occupant(seat)
	_seat_occupants[seat] = null
	if who != null:
		swing_door(seat)
		if audio != null:
			audio.play_door(false)
	if seat == 0 or who == driver:
		_driver_left()
	return xf


func _driver_left() -> void:
	driver = null
	if is_player_driven and _prev_owner_tag == "parked":
		owner_tag = "parked"
	is_player_driven = false
	_scripted = false
	_clear_inputs()
	honk(false)
	engine_on = false


func _evict(seat: int, impulse: Vector3) -> void:
	var who := get_occupant(seat)
	if who == null:
		return
	var xf := get_exit_transform(seat)
	_seat_occupants[seat] = null
	if who == driver:
		_driver_left()
	if who.has_method("on_vehicle_ejected"):
		who.call("on_vehicle_ejected", self, xf, impulse)
	elif who.has_method("exit_vehicle") and who.get("current_vehicle") == self:
		who.call("exit_vehicle")
	elif who is Node3D and is_ancestor_of(who):
		var n3 := who as Node3D
		n3.reparent(Game.get_entities_root(), false)
		n3.global_transform = xf
		if n3.has_method("knock_down"):
			n3.call("knock_down", impulse)


## Throw everybody out (explosion, admin, wreck). Occupants are notified through
## `on_vehicle_ejected(vehicle, exit_transform, impulse)` if they implement it, else through
## their own `exit_vehicle()`.
func eject_occupants(impulse: Vector3 = Vector3.ZERO) -> void:
	for i in _seat_occupants.size():
		_evict(i, impulse)


func get_seat_node(seat: int = 0) -> Node3D:
	if seat < 0 or seat >= _seat_nodes.size():
		return null
	return _seat_nodes[seat]


## World position of the door a character should walk to for this seat (not collision-tested).
func get_door_position(seat: int = 0) -> Vector3:
	return global_transform * _exit_local(seat)


func _exit_local(seat: int) -> Vector3:
	var s := clampi(seat, 0, maxi(_seat_nodes.size() - 1, 0))
	if s < _seat_exits.size() and _seat_exits[s] != null and is_instance_valid(_seat_exits[s]):
		var p := xform_in_body(_seat_exits[s]).origin
		return Vector3(p.x, 0.0, p.z)
	var side := -1.0 if (s % 2) == 0 else 1.0
	var z := body_aabb.get_center().z
	if s < _seat_nodes.size():
		var sp := xform_in_body(_seat_nodes[s]).origin
		z = sp.z
		if absf(sp.x) > 0.05:
			side = signf(sp.x)
	return Vector3(side * (body_aabb.size.x * 0.5 + 0.75), 0.0, z)


## Safe place to stand after leaving `seat`: beside the door if free, else the other side,
## behind / in front, and as a last resort on the roof.
func get_exit_transform(seat: int = 0) -> Transform3D:
	if not is_inside_tree():
		return Transform3D.IDENTITY
	var gt := global_transform
	var f := -gt.basis.z
	f.y = 0.0
	if f.length() < 0.05:
		f = gt.basis.y
		f.y = 0.0
	var facing := Basis(Vector3.UP, atan2(-f.x, -f.z)) if f.length() > 0.01 else Basis.IDENTITY
	var base := _exit_local(seat)
	var half_w := body_aabb.size.x * 0.5
	var zc := body_aabb.get_center().z
	var half_l := body_aabb.size.z * 0.5
	var cands: Array[Vector3] = [
		base,
		Vector3(-base.x, 0.0, base.z),
		Vector3(signf(base.x) * (half_w + 1.4), 0.0, base.z),
		Vector3(-signf(base.x) * (half_w + 1.4), 0.0, base.z),
		Vector3(base.x, 0.0, zc + half_l * 0.6),
		Vector3(-base.x, 0.0, zc + half_l * 0.6),
		Vector3(0.0, 0.0, zc + half_l + 1.1),
		Vector3(0.0, 0.0, zc - half_l - 1.1),
	]
	var space := get_world_3d().direct_space_state
	for c: Vector3 in cands:
		var w := gt * c
		var res := _probe_exit(space, w, gt.origin.y)
		if res.x != INF:
			return Transform3D(facing, res)
	return Transform3D(facing, gt.origin + Vector3.UP * (body_aabb.position.y + body_aabb.size.y + 0.25))


func _probe_exit(space: PhysicsDirectSpaceState3D, world_pos: Vector3, ref_y: float) -> Vector3:
	if _exit_q == null:
		_exit_q = PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.33
		cap.height = 1.6
		_exit_q.shape = cap
		_exit_q.collision_mask = EXIT_PROBE_MASK
		_exit_q.exclude = [get_rid()]
	var top := Vector3(world_pos.x, maxf(world_pos.y, ref_y) + 1.6, world_pos.z)
	_ray_q.from = top
	_ray_q.to = top - Vector3.UP * 5.0
	_ray_q.collision_mask = Layers.WORLD | Layers.PROP
	var hit := space.intersect_ray(_ray_q)
	_ray_q.collision_mask = Layers.GROUND_MASK
	if hit.is_empty():
		return Vector3.INF
	var ground: Vector3 = hit["position"]
	if Game.is_in_water(ground + Vector3.UP * 0.2) and not in_water:
		return Vector3.INF
	_exit_q.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * 0.98)
	if space.intersect_shape(_exit_q, 1).is_empty():
		return ground
	return Vector3.INF


## Briefly swing the door that belongs to `seat` (enter / exit feedback).
func swing_door(seat: int) -> void:
	if seat < 0 or seat >= _seat_doors.size():
		return
	var d := _seat_doors[seat]
	if d == null or not is_instance_valid(d) or not d.visible:
		return
	var i := _doors.find(d)
	if i >= 0:
		_door_timer[i] = 0.75
		_doors_active = true


# --- hinged lids: hood, trunk, convertible roof ---------------------------------------------------

## which: "hood", "trunk" or "roof".
func has_lid(which: String) -> bool:
	var i := LID_NAMES.find(which)
	return i >= 0 and _lid_node[i] != null and is_instance_valid(_lid_node[i])


## Open (1) / close (0) a lid; values in between leave it ajar (crash damage). Animated unless instant.
func set_lid_open(which: String, amount: float, instant: bool = false) -> void:
	var i := LID_NAMES.find(which)
	if i < 0 or _lid_node[i] == null or not is_instance_valid(_lid_node[i]):
		return
	_lid_target[i] = clampf(amount, 0.0, 1.0)
	if instant:
		_lid_open[i] = _lid_target[i]
		_pose_lid(i)
	else:
		_lids_active = true


func get_lid_open(which: String) -> float:
	var i := LID_NAMES.find(which)
	return _lid_target[i] if i >= 0 else 0.0


func has_convertible_roof() -> bool:
	return has_lid("roof")


func is_roof_open() -> bool:
	return _lid_target[2] > 0.5


## Fold the convertible roof away / put it back (no effect on cars without a Roof_Convertible part).
func set_roof_open(open: bool, instant: bool = false) -> void:
	if not has_convertible_roof() or open == is_roof_open():
		return
	set_lid_open("roof", 1.0 if open else 0.0, instant)
	if not instant and audio != null:
		audio.play_door(open)


func toggle_roof() -> void:
	set_roof_open(not is_roof_open())


func _pose_lid(i: int) -> void:
	var n := _lid_node[i]
	if n == null or not is_instance_valid(n):
		return
	var e := _lid_open[i] * _lid_open[i] * (3.0 - 2.0 * _lid_open[i])
	n.transform = _lid_rest[i] * Transform3D(Basis(Vector3.RIGHT, e * _lid_angle[i]), Vector3.ZERO)


func _update_lids(delta: float) -> void:
	var any := false
	for i in _lid_node.size():
		if _lid_node[i] == null or is_equal_approx(_lid_open[i], _lid_target[i]):
			continue
		_lid_open[i] = move_toward(_lid_open[i], _lid_target[i], delta * LID_SPEED[i])
		_pose_lid(i)
		if not is_equal_approx(_lid_open[i], _lid_target[i]):
			any = true
	_lids_active = any


## Hold any door open for a while by part name ("Door_RL" / "Door_RR" are the rear doors of
## the ambulance and the vans). Returns false if the model has no such door.
func open_door(part_name: String, seconds: float = 2.5) -> bool:
	var d := get_part(part_name)
	var i := _doors.find(d) if d != null else -1
	if i < 0 or not d.visible:
		return false
	_door_timer[i] = maxf(seconds, 0.1)
	_doors_active = true
	return true


func _update_doors(delta: float) -> void:
	var any := false
	for i in _doors.size():
		var d := _doors[i]
		if not is_instance_valid(d):
			continue
		_door_timer[i] = maxf(_door_timer[i] - delta, 0.0)
		var target := 1.0 if _door_timer[i] > 0.0 else 0.0
		_door_open[i] = move_toward(_door_open[i], target, delta * 4.5)
		if _door_open[i] > 0.001 or target > 0.0:
			any = true
		var side := -1.0 if xform_in_body(d).origin.x < 0.0 else 1.0
		var e := _door_open[i] * _door_open[i] * (3.0 - 2.0 * _door_open[i])
		d.transform = _door_rest[i] * Transform3D(Basis(Vector3.UP, side * e * 0.95), Vector3.ZERO)
	_doors_active = any


# ==============================================================================================
# inputs
# ==============================================================================================

## AI / scripted driving. throttle -1 (reverse) .. 1, steer -1 left .. +1 right, brake 0..1.
## Ignored while the player drives.
func set_inputs(throttle: float, steer: float, brake: float, handbrake: bool = false) -> void:
	if is_player_driven or destroyed:
		return
	in_throttle = clampf(throttle, -1.0, 1.0)
	in_steer = clampf(steer, -1.0, 1.0)
	in_brake = clampf(brake, 0.0, 1.0)
	in_handbrake = handbrake
	_scripted = true
	if absf(in_throttle) > 0.01:
		if not engine_on:
			start_engine()
		if sleeping:
			sleeping = false


## Aircraft AI / scripted flight: all -1..1, power 0..1 (collective / throttle).
func set_flight_inputs(pitch: float, roll: float, yaw: float, power: float) -> void:
	if is_player_driven or destroyed:
		return
	in_pitch = clampf(pitch, -1.0, 1.0)
	in_roll = clampf(roll, -1.0, 1.0)
	in_yaw = clampf(yaw, -1.0, 1.0)
	in_power = clampf(power, -1.0, 1.0)
	_scripted = true
	if absf(in_power) > 0.01:
		if not engine_on:
			start_engine()
		if sleeping:
			sleeping = false


## Stop scripted control (inputs return to neutral, the vehicle coasts to a halt).
func release_inputs() -> void:
	_scripted = false
	_clear_inputs()


func _clear_inputs() -> void:
	in_throttle = 0.0
	in_steer = 0.0
	in_brake = 0.0
	in_handbrake = false
	in_pitch = 0.0
	in_roll = 0.0
	in_yaw = 0.0
	in_power = 0.0


## Hook: map the player's actions to in_* (called every physics frame while player driven).
func _read_player_input(_delta: float) -> void:
	in_throttle = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	in_steer = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	in_brake = 0.0
	in_handbrake = Input.is_action_pressed("handbrake")


func _read_player_toggles() -> void:
	if Input.is_action_just_pressed("headlights"):
		set_headlights((headlight_mode + 1) % 3)
	if Input.is_action_just_pressed("siren") and has_siren():
		set_siren(not siren_on)
	if Input.is_action_just_pressed("vehicle_roof") and has_convertible_roof():
		toggle_roof()
	var want_horn := Input.is_action_pressed("horn")
	if want_horn != horn_on:
		honk(want_horn)


func start_engine() -> bool:
	if destroyed or stalled:
		return false
	if not engine_on:
		engine_on = true
		if audio != null:
			audio.play_start()
		exhaust_puff("light", 0.45)
	return true


func stop_engine() -> void:
	engine_on = false


func has_siren() -> bool:
	return (is_emergency or is_police) and spec != null and spec.sound_siren != ""


# ==============================================================================================
# lights / horn / siren
# ==============================================================================================

func set_headlights(mode: int) -> void:
	headlight_mode = clampi(mode, 0, 2)
	if lights != null:
		lights.refresh()


func set_siren(on: bool) -> void:
	var was := siren_on
	siren_on = on and has_siren() and not destroyed
	if siren_on and not was and is_inside_tree():
		EventBus.noise_emitted.emit(global_position, 70.0, "siren", driver if driver != null else self)
	if lights != null:
		lights.refresh()


func honk(on: bool) -> void:
	var want := on and not destroyed
	if want == horn_on:
		return
	horn_on = want
	if horn_on and is_inside_tree():
		EventBus.noise_emitted.emit(global_position, 30.0, "horn", driver if driver != null else self)


## dir: 0 off, -1 left, 1 right, 2 hazards.
func set_indicator(dir: int) -> void:
	indicator = clampi(dir, -1, 2)
	if lights != null:
		lights.refresh()


func is_braking() -> bool:
	return in_brake > 0.1 or in_handbrake


func is_reversing() -> bool:
	return false


# ==============================================================================================
# damage facade
# ==============================================================================================

func apply_damage(info: Dictionary) -> void:
	if damage != null:
		damage.apply(info)


func repair() -> void:
	if damage != null:
		damage.repair()


func explode(instigator: Node = null) -> void:
	if damage != null:
		damage.explode(instigator)


## Whoever damaged this vehicle last, or null (never a freed object).
func get_last_instigator() -> Node:
	if last_instigator != null and is_instance_valid(last_instigator):
		return last_instigator
	last_instigator = null
	return null


func get_health_ratio() -> float:
	return clampf(health / maxf(max_health, 1.0), 0.0, 1.0)


## Engine output multiplier from damage (1 healthy .. 0.45 about to burn).
func get_power_factor() -> float:
	var r := get_health_ratio()
	if r >= 0.6:
		return 1.0
	return lerpf(0.45, 1.0, clampf((r - 0.12) / 0.48, 0.0, 1.0))


func pop_tire(_index: int) -> void:
	pass


## Hook: called once when the vehicle turns into a wreck.
func _on_destroyed() -> void:
	pass


## Hook: called by repair() so subclasses can restore wheels etc.
func _on_repaired() -> void:
	pass


# ==============================================================================================
# queries for helpers / other modules
# ==============================================================================================

func get_forward_speed() -> float:
	if sleeping:
		return 0.0
	return linear_velocity.dot(-global_transform.basis.z) if is_inside_tree() else 0.0


func get_camera_params() -> Dictionary:
	if spec == null:
		return {"distance": 5.6, "height": 1.9, "fov": 72.0, "look_height": 1.0}
	return spec.get_camera_params()


## 0..1 engine speed for audio.
func get_rpm_factor() -> float:
	return 0.0


## 0..1 how hard the engine works (audio volume / timbre).
func get_engine_load() -> float:
	return absf(in_throttle)


## 0..1 tyre slip loudness.
func get_skid_amount() -> float:
	return 0.0


func get_wheel_count() -> int:
	return 0


func get_wheel_position(_index: int) -> Vector3:
	return global_position


func get_wheel_radius(_index: int) -> float:
	return 0.33


func get_wheel_node(_index: int) -> Node3D:
	return null


func is_tire_flat(_index: int) -> bool:
	return false


## Visual basis of a wheel in body space at rest (used to orient swapped wheel models).
func get_wheel_rest_basis(_index: int) -> Basis:
	return Basis.IDENTITY


## Body-space position of a marker, or `fallback` if the model lacks it.
func marker_local(marker_name: String, fallback: Vector3) -> Vector3:
	var n := get_part(marker_name)
	if n != null:
		return xform_in_body(n).origin
	return fallback


## World positions of the tail pipes (Exhaust_L + Exhaust_R when both exist, else Exhaust).
func get_exhaust_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for p: Vector3 in _exhaust_local:
		out.append(global_transform * p)
	return out


## Small exhaust puff from every tail pipe (engine start, hard upshifts, launches). Cosmetic only:
## near vehicles (detail level 0), Fx present, running engine.
func exhaust_puff(kind: String = "light", scale: float = 0.35) -> void:
	if detail_level != 0 or destroyed or not is_inside_tree() or Fx == null or not Fx.has_method("smoke_puff"):
		return
	if in_water:
		return
	var back := global_transform.basis.z * 0.15
	for p: Vector3 in get_exhaust_positions():
		Fx.smoke_puff(p + back, kind, scale)


func get_engine_position() -> Vector3:
	var c := body_aabb.get_center()
	var local := marker_local("Engine", Vector3(c.x, body_aabb.position.y + body_aabb.size.y * 0.55, c.z - body_aabb.size.z * 0.32))
	return global_transform * local


func get_center_position() -> Vector3:
	return global_transform * body_aabb.get_center()


## Move the vehicle instantly (garage, admin, tests). Velocities are cleared.
func teleport(xform: Transform3D) -> void:
	_recover_t = -1.0
	_flip_t = 0.0
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_lin = Vector3.ZERO
	_fwd_speed = 0.0
	speed_kmh = 0.0
	sleeping = false
	_on_teleported()


func _on_teleported() -> void:
	pass


# ==============================================================================================
# save data (personal vehicle)
# ==============================================================================================

func get_save_data() -> Dictionary:
	var t := global_transform if is_inside_tree() else transform
	return {
		"spec_id": spec_id,
		"primary": SaveSystem.color_to_array(paint_primary),
		"secondary": SaveSystem.color_to_array(paint_secondary),
		"mods": mods.duplicate(),
		"health": health,
		"position": SaveSystem.vec3_to_array(t.origin),
		"yaw": t.basis.get_euler().y,
		"roof_open": is_roof_open(),
	}


func apply_save_data(d: Dictionary) -> void:
	var m: Variant = d.get("mods", {})
	if m is Dictionary and not (m as Dictionary).is_empty():
		apply_mods(m)
	var p := SaveSystem.array_to_color(d.get("primary", null), paint_primary)
	var s := SaveSystem.array_to_color(d.get("secondary", null), paint_secondary)
	set_paint(p, s)
	health = clampf(float(d.get("health", max_health)), 1.0, max_health)
	set_roof_open(bool(d.get("roof_open", false)), true)


# ==============================================================================================
# frame updates
# ==============================================================================================

func _process(delta: float) -> void:
	if not _built:
		return
	if _doors_active:
		_update_doors(delta)
	if _lids_active:
		_update_lids(delta)
	damage.update(delta)
	if detail_level >= 2 and not is_player_driven:
		audio.update(delta)
		return
	_update_visuals(delta)
	lights.update(delta)
	audio.update(delta)


## Hook: wheel / rotor / steering-wheel visuals.
func _update_visuals(_delta: float) -> void:
	pass


func _update_steering_wheel(steer_norm: float) -> void:
	if _steering_wheel == null or not is_instance_valid(_steering_wheel):
		return
	_steering_wheel.transform = _steering_rest * Transform3D(Basis(_steering_axis, -steer_norm * 2.1), Vector3.ZERO)


func _physics_process(delta: float) -> void:
	if not _built:
		return
	if not _pending_hits.is_empty():
		_flush_collisions()
	if destroyed:
		return
	if is_player_driven:
		if Game.is_input_locked():
			_clear_inputs()
		else:
			_read_player_input(delta)
			_read_player_toggles()
		_xp_t += delta
		if _xp_t >= 1.0:
			_xp_t = 0.0
			if absf(_fwd_speed) > 5.0:
				Skills.add_xp("driving", 0.012 * clampf(absf(_fwd_speed) / 25.0, 0.2, 1.0))
	elif driver == null and not _scripted:
		in_throttle = 0.0
		in_steer = 0.0
	# stuck on the roof / side (checked here because a sleeping body gets no _integrate_forces)
	if self_righting and _recover_t < 0.0 and global_transform.basis.y.y < 0.3 			and (sleeping or (linear_velocity.length_squared() < 1.5 and angular_velocity.length_squared() < 1.5)):
		_flip_t += delta
		if _flip_t > FLIP_RECOVER_SECONDS and not in_water:
			_flip_t = 0.0
			_begin_self_right()
	else:
		_flip_t = 0.0
	if sleeping:
		if _wants_wake():
			sleeping = false
		else:
			return
	_water_t -= delta
	if _water_t <= 0.0:
		_water_t = 0.3
		_check_water()
		_expire_struck()
	var sp := linear_velocity.length()
	if sp > STRIKE_MIN_SPEED:
		_sweep_flip = not _sweep_flip
		if is_player_driven or _sweep_flip:
			_sweep_ahead(sp, delta * (1.0 if is_player_driven else 2.0))


func _wants_wake() -> bool:
	return absf(in_throttle) > 0.01 or absf(in_power) > 0.01


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _built:
		return
	if _recover_t >= 0.0:
		_integrate_recovery(state)
		return
	if destroyed:
		_prev_lin = state.linear_velocity
		if in_water:
			_integrate_water(state)
		return
	_integrate_vehicle(state)
	_integrate_common(state)


## Hook: class-specific forces (suspension, tyres, lift, buoyancy ...).
func _integrate_vehicle(_state: PhysicsDirectBodyState3D) -> void:
	pass


func _integrate_common(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	var lin := state.linear_velocity
	var xf := state.transform
	_fwd_speed = lin.dot(-xf.basis.z)
	speed_kmh = absf(_fwd_speed) * 3.6

	# --- impacts: sudden velocity change while something touches the hull
	var dvv := lin - _prev_lin
	var dv := dvv.length()
	_collision_cd -= dt
	if dv > COLLISION_DV_MIN and _collision_cd <= 0.0:
		var n := state.get_contact_count()
		if n > 0:
			var best := 0
			var best_imp := -1.0
			for i in n:
				var imp := state.get_contact_impulse(i).length_squared()
				if imp > best_imp:
					best_imp = imp
					best = i
			_collision_cd = 0.18
			_pending_hits.append([state.get_contact_collider_object(best), dv,
					state.get_contact_local_position(best), state.get_contact_local_normal(best), _prev_lin.length()])
	_prev_lin = lin

	if in_water:
		_integrate_water(state)



func _integrate_water(state: PhysicsDirectBodyState3D) -> void:
	var depth := Game.WATER_LEVEL - (state.transform.origin.y + body_aabb.position.y + body_aabb.size.y * 0.5)
	if depth <= -0.6:
		return
	var sub := clampf((depth + 0.6) / 1.2, 0.0, 1.0)
	state.apply_central_force(Vector3.UP * mass * 9.81 * 0.72 * sub)
	state.apply_central_force(-state.linear_velocity * mass * 1.6 * sub)
	state.apply_torque(-state.angular_velocity * mass * 1.2 * sub)


func _check_water() -> void:
	var was := in_water
	var p := get_engine_position()
	in_water = Game.is_in_water(p + Vector3.DOWN * 0.25)
	if in_water and not was:
		Fx.splash(Vector3(p.x, Game.WATER_LEVEL, p.z), clampf(linear_velocity.length() / 8.0, 0.8, 2.5))
		Audio.play_at("splash_large", p, 0.0, 1.0, 90.0)
	if in_water and not stalled and not destroyed:
		stalled = true
		engine_on = false
		set_siren(false)
		if is_player_driven:
			UI.notify("Engine flooded", "warn")


# --- collisions --------------------------------------------------------------------------------

func _flush_collisions() -> void:
	var hits := _pending_hits
	_pending_hits = []
	for h: Array in hits:
		var other: Variant = h[0]
		var node: Node = null
		if other != null and is_instance_valid(other) and other is Node:
			node = other as Node
		_on_collision(node, float(h[1]), h[2], h[3], float(h[4]))


func _on_collision(other: Node, dv: float, pos: Vector3, normal: Vector3, pre_speed: float) -> void:
	if not is_inside_tree():
		return
	EventBus.vehicle_collision.emit(self, other, dv * mass, pos)
	if audio != null:
		audio.play_crash(dv, pos)
	EventBus.noise_emitted.emit(pos, clampf(12.0 + dv * 3.0, 15.0, 45.0), "crash", driver if driver != null else self)
	if dv > 3.0 and detail_level <= 1:
		Fx.sparks(pos, normal, clampf(dv / 10.0, 0.3, 2.0))
	if is_player_driven and dv > 2.5:
		Fx.shake_camera(clampf(dv / 22.0, 0.1, 0.8))
	if damage != null and not destroyed:
		damage.on_collision(other, dv, pos, normal)
	# pass some of the hit on to breakable things that are not vehicles / characters
	if other != null and not other.is_in_group("vehicle") and not _is_character(other):
		var d := Dmg.find_damageable(other)
		if d != null and d != self:
			var dir := -normal
			d.apply_damage(Dmg.make(dv * 14.0, "vehicle", driver if driver != null else self, pos, dir, {"impulse": dv * minf(mass, 2000.0) * 0.4}))
	VehicleCrime.collision(self, other, dv, pos, pre_speed)


static func _is_character(n: Node) -> bool:
	return n.is_in_group("npc") or n.is_in_group("player") or n.is_in_group("animal") or n is CharacterBody3D


# --- running people / breakables over -------------------------------------------------------------

func _sweep_ahead(speed: float, look_dt: float) -> void:
	if _sweep_q == null:
		_sweep_shape = BoxShape3D.new()
		_sweep_q = PhysicsShapeQueryParameters3D.new()
		_sweep_q.shape = _sweep_shape
		_sweep_q.collision_mask = SWEEP_MASK
		_sweep_q.exclude = [get_rid()]
	var gt := global_transform
	var dir := linear_velocity / speed
	var local_dir := gt.basis.inverse() * dir
	var hx := body_aabb.size.x * 0.5
	var hz := body_aabb.size.z * 0.5
	var along := absf(local_dir.x) * hx + absf(local_dir.z) * hz
	var across := absf(local_dir.x) * hz + absf(local_dir.z) * hx
	var depth := speed * look_dt * 2.2 + 0.45
	_sweep_shape.size = Vector3(across * 2.0 * 0.92, maxf(body_aabb.size.y * 0.7, 0.8), depth)
	var center := gt * body_aabb.get_center() + dir * (along + depth * 0.5 - 0.1)
	center.y += 0.12
	var up := gt.basis.y
	if absf(dir.dot(up)) > 0.95:
		up = gt.basis.x
	_sweep_q.transform = Transform3D(Basis.looking_at(dir, up), center)
	var hits := get_world_3d().direct_space_state.intersect_shape(_sweep_q, 8)
	if hits.is_empty():
		return
	var now := VehicleBase.now_msec()
	for h: Dictionary in hits:
		var c: Variant = h.get("collider", null)
		if c == null or not is_instance_valid(c) or not (c is Node):
			continue
		var node := c as Node
		var id := node.get_instance_id()
		if _struck.has(id):
			continue
		if _is_character(node):
			if get_seat_of(node) >= 0:
				continue
			_strike_character(node as Node3D, speed, dir, now)
		elif not node.is_in_group("vehicle"):
			var d := Dmg.find_damageable(node)
			if d != null and d != self and not d.is_in_group("vehicle"):
				_struck[id] = [node, now + 600, false]
				var pos := (d as Node3D).global_position if d is Node3D else center
				d.apply_damage(Dmg.make(speed * 12.0, "vehicle", driver if driver != null else self, pos, dir,
						{"impulse": speed * minf(mass, 2000.0) * 0.5}))


func _strike_character(who: Node3D, speed: float, dir: Vector3, now: int) -> void:
	if who == null:
		return
	var their_vel := Vector3.ZERO
	if who is CharacterBody3D:
		their_vel = (who as CharacterBody3D).velocity
	var rel := (linear_velocity - their_vel).length()
	if rel < STRIKE_MIN_SPEED:
		return
	_struck[who.get_instance_id()] = [who, now + 1500, true]
	if who is PhysicsBody3D:
		add_collision_exception_with(who)
	var amount := clampf((rel - 2.5) * 9.0, 4.0, 400.0)
	var pos := who.global_position + Vector3.UP * 0.9
	var push := (dir + Vector3.UP * 0.35).normalized()
	var impulse := push * clampf(rel * 55.0, 150.0, 1400.0)
	var info := Dmg.make(amount, "vehicle", driver if driver != null else self, pos, push, {"impulse": impulse.length()})
	Dmg.apply(who, info)
	if is_instance_valid(who):
		if who.has_method("knock_down"):
			who.call("knock_down", impulse)
		elif who.has_method("ragdoll"):
			who.call("ragdoll", impulse, 2.2)
	Audio.play_at("impact_flesh", pos, -2.0, randf_range(0.85, 1.1), 40.0)
	apply_central_impulse(-dir * minf(70.0 * rel * 0.5, mass * 1.2))
	if is_player_driven:
		Fx.shake_camera(clampf(rel / 40.0, 0.08, 0.4))
	VehicleCrime.character_hit(self, who, rel, amount)


func _expire_struck() -> void:
	if _struck.is_empty():
		return
	var now := VehicleBase.now_msec()
	for id: int in _struck.keys():
		var e: Array = _struck[id]
		if now < int(e[1]):
			continue
		var n: Variant = e[0]
		if n == null or not is_instance_valid(n):
			_struck.erase(id)
			continue
		if bool(e[2]) and n is Node3D:
			# keep ignoring the body while it is still inside / under the car
			var local := global_transform.affine_inverse() * (n as Node3D).global_position
			if body_aabb.grow(0.45).has_point(Vector3(local.x, clampf(local.y, body_aabb.position.y, body_aabb.end.y), local.z)):
				e[1] = now + 400
				continue
			if n is PhysicsBody3D:
				remove_collision_exception_with(n)
		_struck.erase(id)


# --- self righting ---------------------------------------------------------------------------------

func _begin_self_right() -> void:
	if destroyed or not is_inside_tree():
		return
	_recover_from = global_transform
	var f := -_recover_from.basis.z
	f.y = 0.0
	if f.length() < 0.15:
		f = _recover_from.basis.y
		f.y = 0.0
	if f.length() < 0.01:
		f = Vector3.FORWARD
	var yaw := atan2(-f.x, -f.z)
	var center := get_center_position()
	var ground_y := center.y - 0.6
	_ray_q.from = center + Vector3.UP * 1.0
	_ray_q.to = center - Vector3.UP * 6.0
	_ray_q.collision_mask = Layers.WORLD
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray_q)
	_ray_q.collision_mask = Layers.GROUND_MASK
	if not hit.is_empty():
		ground_y = (hit["position"] as Vector3).y
	_recover_to = Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, ground_y + 0.12, center.z))
	_recover_t = 0.0
	can_sleep = false
	sleeping = false


func _integrate_recovery(state: PhysicsDirectBodyState3D) -> void:
	_recover_t += state.step
	var t := clampf(_recover_t / RECOVER_DURATION, 0.0, 1.0)
	var s := t * t * (3.0 - 2.0 * t)
	var q0 := _recover_from.basis.orthonormalized().get_rotation_quaternion()
	var q1 := _recover_to.basis.get_rotation_quaternion()
	var origin := _recover_from.origin.lerp(_recover_to.origin, s) + Vector3.UP * sin(PI * s) * 0.8
	state.transform = Transform3D(Basis(q0.slerp(q1, s)), origin)
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
	_prev_lin = Vector3.ZERO
	if t >= 1.0:
		_recover_t = -1.0
		_flip_t = 0.0
		can_sleep = true
		_on_teleported()
