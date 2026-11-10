class_name TransitTram
extends AnimatableBody3D
## One "Bay Tram" (misc/tram.glb, 18.4 m, two cars). A PASSIVE kinematic body: TransitSystem's
## manager loop owns the motion (offset `s`, speed `v`, phase, doors) and calls place() /
## update_doors() / update_audio(); this node has no _process of its own.
##
## * Kinematic (AnimatableBody3D, sync_to_physics) on Layers.VEHICLE: it is never pushed or
##   derailed, traffic sees it in its obstacle boxes, vehicles that hit it take collision damage.
##   It is NOT in group "vehicle": the player's enter-vehicle key and carjacking ignore it.
## * Collision: the manifest's compound of 12 boxes (floor, roof, walls, cab ends, door
##   openings left free) + one box per door opening, switched off while that door is open, so a
##   standing rider walks inside the moving car and cannot fall out between stops.
## * Riders: STANDING riders are ordinary on-foot players on the moving floor (the player's
##   CharacterBody3D platform motion carries them). SEATED riders use the PLAYER vehicle-seat
##   contract (seats 1..4 = markers Seat_1..4, see docs/PLAYER.md section 4): occupant_enter /
##   occupant_exit / get_seat_node / get_exit_transform / get_occupant(s) and the vehicle-like
##   read-only fields the HUD / camera use (vehicle_class "tram", speed_kmh, health ...).
## * Interactables (children, move with the car): Board (outside each right door, while open),
##   Get off (inside each door, while open), Sit down (each seat), Stand up (seated rider, on the
##   enter_vehicle key so the player's own exit handling stands back).

enum Phase { RUN, DWELL }

const MODEL_PATH := "res://gta/generated/models/misc/tram.glb"
const HUMANOID_SCENE := "res://gta/scenes/characters/humanoid.tscn"
const ANIMATOR_SCRIPT := "res://gta/code/characters/humanoid_animator.gd"
const DRIVER_POS := Vector3(0.0, 0.82, -7.95)    ## hip point of the motorman in the front cab
const HALF_LEN := 9.19
const HALF_W := 1.25
const FLOOR_Y := 0.35
const DOOR_Z: Array[float] = [-3.8, 3.8]       ## right-hand double doors (front, rear)
const DOOR_SLIDE := 0.7
const SEAT_COUNT := 5                           ## seat 0 = the cab (never offered), 1..4 = Seat_1..4
## Manifest "collision_boxes" (Godot axes, [cx, cy, cz, sx, sy, sz]); door openings left free.
const BOXES: Array = [
	[0.0, 0.3, 0.0, 2.36, 0.1, 17.6], [0.0, 2.7, 0.0, 2.44, 0.2, 17.2],
	[1.215, 1.475, -6.2, 0.07, 2.25, 3.4], [-1.215, 1.475, -6.2, 0.07, 2.25, 3.4],
	[1.215, 1.475, 0.0, 0.07, 2.25, 6.2], [-1.215, 1.475, 0.0, 0.07, 2.25, 6.2],
	[1.215, 1.475, 6.2, 0.07, 2.25, 3.4], [-1.215, 1.475, 6.2, 0.07, 2.25, 3.4],
	[0.0, 1.45, -7.28, 2.36, 2.2, 0.06], [0.0, 1.45, 7.28, 2.36, 2.2, 0.06],
	[0.0, 1.4, -8.2, 1.9, 2.4, 1.7], [0.0, 1.4, 8.2, 1.9, 2.4, 1.7],
]
const SEAT_POS: Array[Vector3] = [Vector3(0.0, 0.82, -8.3), Vector3(0.83, 0.82, -6.625), Vector3(-0.83, 0.82, -6.625),
		Vector3(0.83, 0.82, -2.525), Vector3(-0.83, 0.82, -2.525)]
const STAND_POS: Array[Vector3] = [Vector3(0.0, 0.35, -3.45), Vector3(0.0, 0.35, -4.15), Vector3(0.0, 0.35, 3.45),
		Vector3(0.0, 0.35, 4.15)]

# --- vehicle-like read-only fields (HUD / camera / player vehicle state) ---------------------------
var vehicle_class: String = "tram"
var spec_id: String = "tram"
var display_name: String = "Bay Tram"
var health: float = 1000.0
var max_health: float = 1000.0
var destroyed: bool = false
var driver: Node = null
var is_player_driven: bool = false
var owner_tag: String = "transit"
var is_police: bool = false
var is_emergency: bool = false
var engine_on: bool = true
var siren_on: bool = false
var speed_kmh: float = 0.0

# --- motion state (written by TransitSystem) -----------------------------------------------------
var system: Node = null
var tram_index: int = 0
var s: float = 0.0                      ## path offset of the centre
var v: float = 0.0                      ## m/s along the path
var phase: int = Phase.RUN
var next_stop: int = 0                  ## index into TransitSystem.stops
var dwell_t: float = 0.0
var dwell_len: float = 12.0
var door: float = 0.0                   ## 0 closed .. 1 open (right side)
var door_target: float = 0.0
var line_idx: int = 0                   ## next junction stop line (TransitSystem.lines)
var committed_line: int = -1            ## line we decided to pass (signal changed after that)
var obs_gap: float = INF                ## free metres ahead of the nose
var obs_v: float = 0.0
var obs_kind: int = 0                   ## 0 none, 1 person, 2 vehicle, 3 tram, 4 other
var obs_node: Node = null
var obs_t: float = 0.0
var blocked_t: float = 0.0
var bell_cd: float = 0.0
var hold: String = ""                   ## why the tram is held (debug): "stop", "signal", "obstacle", "yield" ...
var last_hold: String = ""
var braking_hard: bool = false
var loops: int = 0
var visits: PackedInt32Array = PackedInt32Array()
var odometer: float = 0.0
var last_stop: int = -1

var model: Node3D = null
var interior_light: OmniLight3D = null
var driver_visual: Node3D = null

var _seat_nodes: Array[Node3D] = []
var _seat_occ: Array = []
var _leaves: Array = []                  ## [[leaf_a, leaf_b], ...] right doors
var _leaf_rest: Array = []               ## [[pos_a, pos_b], ...]
var _leaf_dir: Array = []                ## slide axis (leaf parent space) per door
var _door_shapes: Array[CollisionShape3D] = []
var _door_shapes_on: bool = true
var _loop: AudioStreamPlayer3D = null
var _board_its: Array = []
var _off_its: Array = []
var _sit_its: Array = []
var _stand_it: Node = null
var _lamp_surfaces: Array = []           ## [MeshInstance3D, surface, lit material, unlit material]
var _lamps_lit: bool = false


func setup(p_system: Node, index: int) -> bool:
	system = p_system
	tram_index = index
	name = "Tram%d" % (index + 1)
	collision_layer = Layers.VEHICLE
	collision_mask = 0
	sync_to_physics = true
	set_meta("surface", "metal")
	add_to_group("tram")
	add_to_group("minimap_blip")
	set_meta("blip_icon", &"tram")
	set_meta("blip_color", Color(0.98, 0.78, 0.25))
	set_meta("blip_clamp", false)
	if not ResourceLoader.exists(MODEL_PATH):
		push_error("TransitTram: missing model " + MODEL_PATH)
		return false
	var ps := load(MODEL_PATH) as PackedScene
	if ps == null:
		push_error("TransitTram: cannot load " + MODEL_PATH)
		return false
	model = ps.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	_build_collision()
	_build_seats()
	_find_doors()
	_find_lamps()
	_build_interactables()
	_build_light()
	_build_driver()
	_loop = Audio.make_loop_player("tram_loop", self, 60.0, "SFX") if Audio.has_method("make_loop_player") else null
	if _loop != null:
		_loop.position = Vector3(0.0, 0.6, 0.0)
		_loop.volume_db = -14.0
	return true


# =================================================================================================
# building
# =================================================================================================

func _build_collision() -> void:
	for b: Array in BOXES:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(b[3]), float(b[4]), float(b[5]))
		cs.shape = box
		cs.position = Vector3(float(b[0]), float(b[1]), float(b[2]))
		add_child(cs)
	# door openings: right side (switched with the doors), left side always closed
	for side: float in [1.0, -1.0]:
		for z: float in DOOR_Z:
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.07, 2.0, 1.42)
			cs.shape = box
			cs.position = Vector3(1.215 * side, 1.35, z)
			add_child(cs)
			if side > 0.0:
				_door_shapes.append(cs)


func _build_seats() -> void:
	_seat_nodes.clear()
	_seat_occ.clear()
	for i in SEAT_COUNT:
		var n := Node3D.new()
		n.name = "Seat%d" % i
		var p: Vector3 = SEAT_POS[i]
		if i >= 1 and model != null:
			var m := model.find_child("Seat_%d" % i, true, false) as Node3D
			if m != null:
				p = _local_of(m)
		n.position = p
		add_child(n)
		_seat_nodes.append(n)
		_seat_occ.append(null)


func _find_doors() -> void:
	_leaves.clear()
	_leaf_rest.clear()
	_leaf_dir.clear()
	if model == null:
		return
	for d in 2:
		var a := model.find_child("Door_R%d_A" % (d + 1), true, false) as Node3D
		var b := model.find_child("Door_R%d_B" % (d + 1), true, false) as Node3D
		_leaves.append([a, b])
		_leaf_rest.append([a.position if a != null else Vector3.ZERO, b.position if b != null else Vector3.ZERO])
		var axis := Vector3.BACK
		if a != null:
			# the tram's +Z expressed in the leaf parent's space
			var pb := model.transform.basis
			var chain: Array[Basis] = []
			var par := a.get_parent()
			while par != null and par != model:
				if par is Node3D:
					chain.push_front((par as Node3D).transform.basis)
				par = par.get_parent()
			for cb: Basis in chain:
				pb = pb * cb
			axis = (pb.inverse() * Vector3.BACK).normalized()
		_leaf_dir.append(axis)


func _find_lamps() -> void:
	_lamp_surfaces.clear()
	if model == null:
		return
	var head_lit := _lamp_material(Color(1.0, 0.95, 0.8), 3.2)
	var tail_lit := _lamp_material(Color(1.0, 0.12, 0.08), 2.4)
	for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(si)
			if mat == null:
				continue
			var nm := mat.resource_name
			if nm.begins_with("M_Headlight"):
				_lamp_surfaces.append([m, si, head_lit])
			elif nm.begins_with("M_Taillight"):
				_lamp_surfaces.append([m, si, tail_lit])


static func _lamp_material(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _build_light() -> void:
	interior_light = OmniLight3D.new()
	interior_light.name = "InteriorLight"
	interior_light.position = Vector3(0.0, 2.25, 0.0)
	interior_light.omni_range = 9.5
	interior_light.light_energy = 0.9
	interior_light.light_color = Color(1.0, 0.86, 0.62)
	interior_light.shadow_enabled = false
	interior_light.visible = false
	add_child(interior_light)


## The motorman in the front cab: the shared humanoid in the seated pose (soft dependency on the
## CHARACTER module, loaded like the traffic drivers). Purely visual.
func _build_driver() -> void:
	if not ResourceLoader.exists(HUMANOID_SCENE):
		return
	var ps := load(HUMANOID_SCENE) as PackedScene
	if ps == null:
		return
	var vis := ps.instantiate() as Node3D
	if vis == null:
		return
	vis.name = "Motorman"
	if "default_archetype" in vis:
		vis.set("default_archetype", "")
	add_child(vis)
	vis.position = DRIVER_POS
	if vis.has_method("randomize_appearance"):
		vis.call("randomize_appearance", "civilian_m" if tram_index % 2 == 0 else "civilian_f", 7100 + tram_index)
	if vis.has_method("get_appearance") and vis.has_method("apply_appearance"):
		var a: Variant = vis.call("get_appearance")
		if a is Dictionary:
			(a as Dictionary)["outfit"] = "staff"
			(a as Dictionary)["hat"] = ""
			vis.call("apply_appearance", a)
	if vis.has_method("set_lod"):
		vis.call("set_lod", 1)
	if ResourceLoader.exists(ANIMATOR_SCRIPT) and vis.has_method("get_skeleton"):
		var scr := load(ANIMATOR_SCRIPT) as Script
		var anim: Node = scr.new() as Node if scr != null else null
		if anim != null:
			anim.name = "SeatedAnimator"
			vis.add_child(anim)
			anim.call("setup", vis.call("get_skeleton"))
			anim.set("update_rate_hz", 6.0)
			anim.set("speed", 0.0)
			if anim.has_method("set_state"):
				anim.call("set_state", "seated_car", 0.0)
			else:
				anim.set("state", "seated_car")
			if anim.has_method("snap"):
				anim.call("snap")
	driver_visual = vis


func _build_interactables() -> void:
	for d in 2:
		var z: float = DOOR_Z[d]
		var board := Interactable.create("Board the tram", 2.4, "interact")
		board.name = "Board%d" % (d + 1)
		board.position = Vector3(2.35, 1.0, z)
		board.use_priority = 3
		board.condition = _can_board.bind(d)
		board.interacted.connect(_on_board.bind(d))
		add_child(board)
		_board_its.append(board)
		var off := Interactable.create("Get off", 1.5, "interact")
		off.name = "GetOff%d" % (d + 1)
		off.position = Vector3(0.45, 1.0, z)
		off.use_priority = 4
		off.condition = _can_get_off.bind(d)
		off.interacted.connect(_on_get_off.bind(d))
		add_child(off)
		_off_its.append(off)
	for i in range(1, SEAT_COUNT):
		var it := Interactable.create("Sit down", 1.3, "interact")
		it.name = "Sit%d" % i
		it.position = _seat_nodes[i].position + Vector3(0.0, 0.25, 0.0)
		it.use_priority = 2
		it.condition = _can_sit.bind(i)
		it.interacted.connect(_on_sit.bind(i))
		add_child(it)
		_sit_its.append(it)
	var up := Interactable.create("Stand up", 4.0, "enter_vehicle")
	up.name = "StandUp"
	up.position = Vector3(0.0, 1.0, 0.0)
	up.on_foot_only = false
	up.in_vehicle_only = true
	up.use_priority = 20
	up.condition = _can_stand_up
	up.interacted.connect(_on_stand_up)
	add_child(up)
	_stand_it = up


static func _local_of_static(root: Node3D, n: Node3D) -> Vector3:
	var p := n.position
	var par := n.get_parent()
	while par != null and par != root:
		if par is Node3D:
			p = (par as Node3D).transform * p
		par = par.get_parent()
	return p


func _local_of(n: Node3D) -> Vector3:
	# marker position in tram space (works before the node is inside the tree)
	return model.transform * _local_of_static(model, n)


# =================================================================================================
# driven by TransitSystem
# =================================================================================================

## Puts the car on the loop: bogie points `bogie` metres ahead / behind the centre offset.
func place(path: TransitPath, bogie: float) -> void:
	var pf := path.sample(s + bogie)
	var pr := path.sample(s - bogie)
	var c := (pf + pr) * 0.5
	var f := pf - pr
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return
	f = f.normalized()
	global_transform = Transform3D(Basis.looking_at(f, Vector3.UP), c)
	speed_kmh = absf(v) * 3.6


## Door leaves follow `door` (0..1); the door-opening collision boxes go away while open.
func update_doors(delta: float, door_time: float) -> void:
	var before := door
	door = move_toward(door, door_target, delta / maxf(door_time, 0.05))
	if door != before or door == 0.0 or door == 1.0:
		var e := door * door * (3.0 - 2.0 * door)
		for d in _leaves.size():
			var pair: Array = _leaves[d]
			var rest: Array = _leaf_rest[d]
			var axis: Vector3 = _leaf_dir[d]
			var a: Node3D = pair[0]
			var b: Node3D = pair[1]
			if a != null:
				a.position = (rest[0] as Vector3) - axis * DOOR_SLIDE * e
			if b != null:
				b.position = (rest[1] as Vector3) + axis * DOOR_SLIDE * e
	var want_shapes := door < 0.3
	if want_shapes != _door_shapes_on:
		_door_shapes_on = want_shapes
		for cs: CollisionShape3D in _door_shapes:
			cs.set_deferred("disabled", not want_shapes)


func update_audio(delta: float, near: bool) -> void:
	if _loop == null:
		return
	if not near:
		if _loop.playing:
			_loop.stop()
		return
	if not _loop.playing:
		_loop.play()
	var k := clampf(absf(v) / 11.0, 0.0, 1.0)
	_loop.pitch_scale = lerpf(_loop.pitch_scale, 0.75 + 0.45 * k, minf(delta * 3.0, 1.0))
	_loop.volume_db = lerpf(_loop.volume_db, lerpf(-22.0, -6.0, k), minf(delta * 3.0, 1.0))


func set_lamps(lit: bool, interior: bool) -> void:
	if interior_light != null:
		interior_light.visible = interior
	if lit == _lamps_lit:
		return
	_lamps_lit = lit
	for e: Array in _lamp_surfaces:
		var m: MeshInstance3D = e[0]
		if is_instance_valid(m):
			m.set_surface_override_material(int(e[1]), e[2] if lit else null)


## Far away the motorman is hidden (the animator stops with it).
func set_detail(near: bool) -> void:
	if driver_visual != null and is_instance_valid(driver_visual) and driver_visual.visible != near:
		driver_visual.visible = near
		var anim := driver_visual.get_node_or_null("SeatedAnimator")
		if anim != null:
			anim.process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED


func ring_bell() -> void:
	Audio.play_at("tram_bell", global_position + global_basis * Vector3(0.0, 2.6, -7.0), -2.0, 1.0, 90.0)


## World transform of a right-hand door marker (outside, floor height, -Z into the car).
func door_point(d: int, outward: float = 0.0) -> Vector3:
	return global_transform * Vector3(1.45 + outward, FLOOR_Y, DOOR_Z[clampi(d, 0, 1)])


func stand_point(i: int) -> Vector3:
	return global_transform * STAND_POS[clampi(i, 0, STAND_POS.size() - 1)]


## Player position in car space.
func to_local_point(p: Vector3) -> Vector3:
	return global_transform.affine_inverse() * p


## Is `p` (feet) inside the passenger saloon?
func contains_point(p: Vector3, margin: float = 0.0) -> bool:
	var l := to_local_point(p)
	return absf(l.x) < HALF_W - 0.05 + margin and absf(l.z) < 7.25 + margin and l.y > FLOOR_Y - 0.6 and l.y < 2.5


func is_door_open() -> bool:
	return door >= 0.9 and phase == Phase.DWELL


# =================================================================================================
# vehicle seat contract (seated riders) - see docs/PLAYER.md section 4
# =================================================================================================

func can_enter(_who: Node) -> bool:
	return false                            # never offered on the enter-vehicle key (not stealable)


func get_seat_count() -> int:
	return SEAT_COUNT


func get_free_seat() -> int:
	for i in range(1, SEAT_COUNT):
		if get_occupant(i) == null:
			return i
	return -1


func get_occupant(seat: int) -> Node:
	if seat < 0 or seat >= _seat_occ.size():
		return null
	var o: Variant = _seat_occ[seat]
	if o != null and is_instance_valid(o):
		return o as Node
	return null


func get_occupants() -> Array:
	var out: Array = []
	for i in _seat_occ.size():
		var o := get_occupant(i)
		if o != null:
			out.append(o)
	return out


func get_seat_of(who: Node) -> int:
	for i in _seat_occ.size():
		if get_occupant(i) == who:
			return i
	return -1


func get_seat_node(seat: int = 1) -> Node3D:
	if seat < 1 or seat >= _seat_nodes.size():
		return null
	return _seat_nodes[seat]


## Aisle point beside the seat (inside the car, floor level, facing forward).
func get_exit_transform(seat: int = 1) -> Transform3D:
	var sp: Vector3 = SEAT_POS[clampi(seat, 1, SEAT_COUNT - 1)]
	if seat >= 1 and seat < _seat_nodes.size():
		sp = _seat_nodes[seat].position
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, FLOOR_Y + 0.02, sp.z + 0.45))


func get_door_position(seat: int = 1) -> Vector3:
	return get_exit_transform(seat).origin


func occupant_enter(who: Node, seat: int = 1) -> void:
	if who == null or seat < 1 or seat >= _seat_occ.size():
		return
	_seat_occ[seat] = who
	if system != null and is_instance_valid(system) and system.has_method("_on_rider_seated"):
		system.call("_on_rider_seated", self, who, seat)


func occupant_exit(seat: int = 1) -> Transform3D:
	var xf := get_exit_transform(seat)
	if seat >= 0 and seat < _seat_occ.size():
		_seat_occ[seat] = null
	return xf


func eject_occupants(_impulse: Vector3 = Vector3.ZERO) -> void:
	for i in _seat_occ.size():
		var who := get_occupant(i)
		if who == null:
			continue
		var xf := get_exit_transform(i)
		_seat_occ[i] = null
		if who.has_method("on_vehicle_ejected"):
			who.call("on_vehicle_ejected", self, xf, Vector3.ZERO)


func get_forward_speed() -> float:
	return v


func get_camera_params() -> Dictionary:
	return {"distance": 13.5, "height": 4.6, "fov": 70.0, "look_height": 2.2}


func get_health_ratio() -> float:
	return 1.0


## Bullets / blasts: the tram is armoured scenery (no damage model); impacts are the FX module's.
func apply_damage(_info: Dictionary) -> void:
	pass


# =================================================================================================
# interactables
# =================================================================================================

func _player_ok(p: Node3D) -> bool:
	return p != null and is_instance_valid(p) and p.get("is_dead") != true


func _can_board(p: Node3D, d: int) -> bool:
	if not _player_ok(p) or not is_door_open() or p.get("current_vehicle") != null:
		return false
	var l := to_local_point(p.global_position)
	return l.x > HALF_W - 0.1 and l.x < 4.2 and absf(l.z - DOOR_Z[d]) < 2.4


func _on_board(p: Node3D, d: int) -> void:
	if system != null and is_instance_valid(system) and system.has_method("board"):
		system.call("board", self, d)


func _can_get_off(p: Node3D, d: int) -> bool:
	if not _player_ok(p) or not is_door_open() or p.get("current_vehicle") != null:
		return false
	var l := to_local_point(p.global_position)
	return l.x > -0.5 and l.x < HALF_W + 0.2 and absf(l.z - DOOR_Z[d]) < 1.3 and contains_point(p.global_position, 0.3)


func _on_get_off(p: Node3D, d: int) -> void:
	if system != null and is_instance_valid(system) and system.has_method("alight"):
		system.call("alight", self, d)


func _can_sit(p: Node3D, seat: int) -> bool:
	if not _player_ok(p) or p.get("current_vehicle") != null or get_occupant(seat) != null:
		return false
	return contains_point(p.global_position)


func _on_sit(_p: Node3D, seat: int) -> void:
	if system != null and is_instance_valid(system) and system.has_method("sit"):
		system.call("sit", self, seat)


func _can_stand_up(p: Node3D) -> bool:
	return _player_ok(p) and p.get("current_vehicle") == self and get_seat_of(p) >= 1


func _on_stand_up(_p: Node3D) -> void:
	if system != null and is_instance_valid(system) and system.has_method("stand_up"):
		system.call("stand_up", self)
