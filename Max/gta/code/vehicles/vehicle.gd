class_name Vehicle
extends RigidBody3D
## Base class of everything drivable: model + colliders from the Blender GLB, seats and
## doors, health / damage / fire / explosion, lamps, horn, siren, engine audio, running
## characters over and waking breakable props. Subclasses add the actual locomotion
## (Car, Boat, Heli, Airplane).

signal destroyed_signal(vehicle: Vehicle)
signal occupant_changed()

var vid := ""
var def: Dictionary = {}
var kind: StringName = &"car"
var model: Node3D
var meshes: Array[MeshInstance3D] = []
var seats: Array = []            # {node, occupant, door, side, name}
var doors: Dictionary = {}       # door part name -> {node, rest: Basis, open: float, target: float, sign: float}
var half_width := 0.9
var half_length := 2.3
var body_height := 1.4

# control inputs (-1..1), written by the player or an AI controller every physics frame
var in_throttle := 0.0
var in_steer := 0.0
var in_brake := 0.0
var in_handbrake := false
var in_pitch := 0.0
var in_roll := 0.0
var in_yaw := 0.0
var in_lift := 0.0

var max_health := 1000.0
var health := 1000.0
var engine_on := false
var destroyed := false
var on_fire := false
var lights_on := false
var siren_on := false
var owner_tag := ""              # "", "player", "police", "traffic", "parked", "taxi"
var personal := false            # owned by the player (garage / saved)
var locked := false
var last_driver: Character = null
var player_driven_time := -1000.0
var ai: Node = null              # AI controller node (traffic / police / taxi)
var spawn_time := 0.0
var paint_a := Color(0.6, 0.6, 0.62)
var paint_b := Color(0.1, 0.1, 0.1)
var finish := Vector4(0.32, 0.35, 0.6, 0.0)
var mods: Dictionary = {}
var dirt := 0.0
var glass_health := 100.0
var speed := 0.0                 # signed forward speed (m/s)
var water_level := 0.0           # how deep the body centre is under water (>0 = submerged)

var _engine_snd: AudioStreamPlayer3D
var _siren_snd: AudioStreamPlayer3D
var _horn_snd: AudioStreamPlayer3D
var _skid_snd: AudioStreamPlayer3D
var _fire_fx: Node3D
var _smoke_fx: Node3D
var _hit_area: Area3D
var _hit_shape: CollisionShape3D
var _headlights: Array[SpotLight3D] = []
var _siren_lights: Array[OmniLight3D] = []
var _lamp_a := Vector4.ZERO
var _lamp_b := Vector4.ZERO
var _blink := 0.0
var _burn := 0.0
var _crash_cd := 0.0
var _horn_on := false
var _prev_vel := Vector3.ZERO
var _dead_time := 0.0
var _settle := 0.0
var _indicator := 0               # -1 left, 1 right, 2 hazard
var rpm := 0.0                    # 0..1 for audio

# ---------------------------------------------------------------- construction
func setup(id: String) -> void:
	vid = id
	def = VehicleDB.get_v(id)
	kind = def.get("kind", &"car")
	name = id
	mass = float(def.get("mass", 1400.0))
	max_health = float(def.get("health", 1000.0))
	health = max_health
	collision_layer = Phys.VEHICLE
	collision_mask = Phys.WORLD | Phys.VEHICLE | Phys.PROP | Phys.RAGDOLL | Phys.BOUNDS
	if kind == &"heli" or kind == &"plane" or kind == &"boat":
		collision_mask = Phys.WORLD | Phys.VEHICLE | Phys.PROP
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = true
	continuous_cd = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.05
	physics_material_override = pm
	angular_damp = 0.4
	linear_damp = 0.02
	spawn_time = Game.clock
	_build_model()
	_build_seats()
	_build_sensors()
	_build_audio()
	_build_lights()
	var paints: Array = def.get("paint", [])
	if paints.size() >= 2:
		set_paint(Color.html(paints[0]), Color.html(paints[1]))
	else:
		set_paint(paint_a, paint_b)
	add_to_group(&"vehicles")
	_setup_kind()

func _setup_kind() -> void:
	pass

func _build_model() -> void:
	var rel := "vehicles/" + vid
	var dims: Vector3 = def.get("dims", Vector3(4.6, 1.9, 1.5))
	half_length = dims.x * 0.5
	half_width = dims.y * 0.5
	body_height = dims.z
	if kind == &"plane":
		half_width = 1.0
	if Assets.has_model(rel):
		model = Assets.instance(rel)
		add_child(model)
		for mi in Assets.find_meshes(model):
			var part := _part_name(mi)
			if part.begins_with("col_"):
				var shape := ConvexPolygonShape3D.new()
				shape.points = _rel_xform(mi) * mi.mesh.get_faces()
				var cs := CollisionShape3D.new()
				cs.shape = shape
				cs.name = "Col_" + part
				add_child(cs)
				mi.visible = false
			elif part == "lod1":
				mi.visibility_range_begin = 70.0
				mi.visibility_range_begin_margin = 4.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				meshes.append(mi)
			else:
				mi.visibility_range_end = 70.0
				mi.visibility_range_end_margin = 4.0
				meshes.append(mi)
			if part.begins_with("door_"):
				var side := -1.0 if part.ends_with("l") else 1.0
				doors[part] = {"node": mi, "rest": mi.transform.basis, "open": 0.0, "target": 0.0, "sign": side}
		var has_lod := PropFactory.part(model, "lod1") != null
		if not has_lod:
			for mi in meshes:
				mi.visibility_range_end = 0.0
		# real dimensions from the body mesh
		var body := PropFactory.part(model, "body")
		if body is MeshInstance3D:
			var box: AABB = _rel_xform(body) * (body as MeshInstance3D).get_aabb()
			half_width = maxf(absf(box.position.x), absf(box.end.x))
			half_length = maxf(absf(box.position.z), absf(box.end.z))
			body_height = box.end.y
			if kind == &"plane":
				half_width = minf(half_width, 1.1)
	else:
		_build_placeholder(dims)
	var has_shape := false
	for c in get_children():
		if c is CollisionShape3D:
			has_shape = true
	if not has_shape:
		var bs := BoxShape3D.new()
		var clear := 0.32
		bs.size = Vector3(half_width * 2.0, maxf(body_height - clear, 0.5), half_length * 2.0)
		var cs2 := CollisionShape3D.new()
		cs2.shape = bs
		cs2.position = Vector3(0, clear + bs.size.y * 0.5, 0)
		add_child(cs2)

func _build_placeholder(dims: Vector3) -> void:
	# stand-in used only while a vehicle model has not been exported (flagged in the feature matrix)
	model = Node3D.new()
	model.name = "Placeholder"
	add_child(model)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(dims.y, dims.z * 0.55, dims.x)
	body.mesh = bm
	body.position = Vector3(0, 0.3 + dims.z * 0.275, 0)
	body.material_override = Assets.mat("Paint1")
	model.add_child(body)
	meshes.append(body)
	var cab := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(dims.y * 0.85, dims.z * 0.4, dims.x * 0.5)
	cab.mesh = cm
	cab.position = Vector3(0, 0.3 + dims.z * 0.75, dims.x * 0.05)
	cab.material_override = Assets.mat("Window")
	model.add_child(cab)
	meshes.append(cab)

static func _part_name(n: Node) -> String:
	var nm := String(n.name)
	var i := nm.rfind("__")
	return nm.substr(i + 2) if i >= 0 else nm

func _rel_xform(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != self:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

func part(part_name: String) -> Node3D:
	return PropFactory.part(model, part_name) if model else null

func marker_pos(marker_name: String, fallback: Vector3) -> Vector3:
	var m := part(marker_name)
	return _rel_xform(m).origin if m != null else fallback

func _build_seats() -> void:
	var names := ["seat_driver", "seat_passenger", "seat_rl", "seat_rr"]
	var door_names := ["door_fl", "door_fr", "door_rl", "door_rr"]
	for i in names.size():
		var m := part(names[i])
		if m == null:
			if i == 0:
				m = Node3D.new()
				m.name = "seat_driver"
				add_child(m)
				m.position = Vector3(-half_width * 0.45 if kind == &"car" else 0.0, body_height * 0.45, 0.1)
			elif i == 1 and kind == &"car":
				m = Node3D.new()
				m.name = "seat_passenger"
				add_child(m)
				m.position = Vector3(half_width * 0.45, body_height * 0.45, 0.1)
			else:
				continue
		var local := _rel_xform(m).origin
		var side := -1.0 if local.x < -0.05 else (1.0 if local.x > 0.05 else (-1.0 if i % 2 == 0 else 1.0))
		seats.append({"node": m, "occupant": null, "door": door_names[i] if doors.has(door_names[i]) else "", "side": side, "name": names[i]})

func _build_sensors() -> void:
	_hit_area = Area3D.new()
	_hit_area.name = "HitArea"
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = Phys.CHARACTER | Phys.PROP
	_hit_area.monitorable = false
	var bs := BoxShape3D.new()
	bs.size = Vector3(half_width * 2.0 + 0.5, maxf(body_height, 1.2), half_length * 2.0 + 0.7)
	_hit_shape = CollisionShape3D.new()
	_hit_shape.shape = bs
	_hit_shape.position = Vector3(0, bs.size.y * 0.5 + 0.1, 0)
	_hit_area.add_child(_hit_shape)
	add_child(_hit_area)

func _build_audio() -> void:
	var snd: StringName = def.get("sound", &"")
	if snd != &"":
		_engine_snd = Audio.make_loop(snd, self, -80.0, 75.0, false)
	if def.has("siren"):
		_siren_snd = Audio.make_loop(def["siren"], self, -3.0, 220.0, false)

func _build_lights() -> void:
	for nm: String in ["light_head_l", "light_head_r"]:
		var m := part(nm)
		if m == null:
			continue
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.95, 0.85)
		sp.light_energy = 5.0
		sp.spot_range = 34.0
		sp.spot_angle = 30.0
		sp.spot_attenuation = 0.9
		sp.shadow_enabled = false
		sp.distance_fade_enabled = true
		sp.distance_fade_begin = 70.0
		sp.distance_fade_length = 20.0
		sp.visible = false
		sp.rotation_degrees = Vector3(-6, 0, 0)
		m.add_child(sp)
		_headlights.append(sp)
	if bool(def.get("emergency", false)):
		var sm := part("siren")
		var base := _rel_xform(sm).origin if sm != null else Vector3(0, body_height + 0.1, 0)
		for i in 2:
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.1, 0.1) if i == 0 else Color(0.15, 0.3, 1.0)
			ol.omni_range = 16.0
			ol.light_energy = 0.0
			ol.shadow_enabled = false
			ol.distance_fade_enabled = true
			ol.distance_fade_begin = 90.0
			ol.visible = false
			ol.position = base + Vector3(-0.4 + 0.8 * float(i), 0.25, 0)
			add_child(ol)
			_siren_lights.append(ol)

# ---------------------------------------------------------------- appearance
func set_paint(a: Color, b: Color, fin := Vector4(-1, 0, 0, 0)) -> void:
	paint_a = a
	paint_b = b
	if fin.x >= 0.0:
		finish = fin
	for mi in meshes:
		mi.set_instance_shader_parameter(&"paint_a", a.srgb_to_linear())
		mi.set_instance_shader_parameter(&"paint_b", b.srgb_to_linear())
		mi.set_instance_shader_parameter(&"finish_a", finish)
		mi.set_instance_shader_parameter(&"finish_b", finish)

func _apply_damage_look() -> void:
	var dmg := clampf(1.0 - health / max_health, 0.0, 1.0) * 0.8
	if destroyed:
		dmg = 1.0
	for mi in meshes:
		mi.set_instance_shader_parameter(&"damage", dmg)
		mi.set_instance_shader_parameter(&"dirt", dirt)

func set_glass_tint(c: Color) -> void:
	for mi in meshes:
		mi.set_instance_shader_parameter(&"glass_tint", Color(c.srgb_to_linear(), c.a))

# ---------------------------------------------------------------- seats / doors
func driver() -> Character:
	return seats[0]["occupant"] if seats.size() > 0 else null

func seat_count() -> int:
	return seats.size()

func free_seat(prefer_driver := true) -> int:
	if prefer_driver and seats.size() > 0 and seats[0]["occupant"] == null:
		return 0
	for i in range(1, seats.size()):
		if seats[i]["occupant"] == null:
			return i
	return -1

func is_empty() -> bool:
	for s in seats:
		if s["occupant"] != null:
			return false
	return true

func has_player() -> bool:
	for s in seats:
		if s["occupant"] != null and (s["occupant"] as Character).is_player:
			return true
	return false

## World position on the ground beside a seat's door.
func door_position(seat_index: int) -> Vector3:
	var s: Dictionary = seats[clampi(seat_index, 0, seats.size() - 1)]
	var local := _rel_xform(s["node"]).origin
	var out_x: float = float(s["side"]) * (half_width + 0.75)
	var p := global_transform * Vector3(out_x, 0.0, local.z + 0.15)
	return p

func sit_pose() -> StringName:
	return &"sit_bike" if kind == &"bike" else &"sit_car"

func seat_character(seat_index: int, c: Character) -> void:
	var s: Dictionary = seats[seat_index]
	s["occupant"] = c
	c.attach_to_seat(self, seat_index, s["node"], sit_pose() if seat_index == 0 else (&"sit_passenger" if kind != &"bike" else &"sit_bike"))
	add_collision_exception_with(c)
	if seat_index == 0:
		last_driver = c
		engine_on = true
		sleeping = false
		if c.is_player:
			player_driven_time = Game.clock
			Audio.play(&"engine_start", global_position, -6.0)
	occupant_changed.emit()

func unseat(seat_index: int, exit_pos: Variant = null) -> Character:
	var s: Dictionary = seats[seat_index]
	var c: Character = s["occupant"]
	if c == null:
		return null
	s["occupant"] = null
	var pos: Vector3 = exit_pos if exit_pos != null else find_exit(seat_index)
	var yaw := global_rotation.y
	c.detach_from_seat(pos, yaw)
	c.velocity = linear_velocity * 0.6
	remove_collision_exception_with(c)
	if seat_index == 0:
		in_throttle = 0.0
		in_steer = 0.0
		in_brake = 0.0
		in_handbrake = true
		in_lift = 0.0
		in_pitch = 0.0
		in_roll = 0.0
		in_yaw = 0.0
		_set_horn(false)
	occupant_changed.emit()
	return c

func eject(c: Character) -> void:
	for i in seats.size():
		if seats[i]["occupant"] == c:
			unseat(i)
			return

## A free spot to step out to: own door side, other side, behind, on top.
func find_exit(seat_index: int) -> Vector3:
	var s: Dictionary = seats[seat_index]
	var local := _rel_xform(s["node"]).origin
	var candidates := [
		Vector3(float(s["side"]) * (half_width + 0.8), 0.3, local.z + 0.1),
		Vector3(-float(s["side"]) * (half_width + 0.8), 0.3, local.z + 0.1),
		Vector3(float(s["side"]) * (half_width + 0.8), 0.3, local.z - 1.2),
		Vector3(0.0, 0.3, half_length + 0.9),
		Vector3(0.0, body_height + 0.3, 0.0),
	]
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = Phys.WORLD | Phys.VEHICLE | Phys.PROP
	q.exclude = [get_rid()]
	for cnd in candidates:
		var wp: Vector3 = global_transform * cnd
		# drop to the surface below (ground, pier, boat deck is excluded -> water handled by swimming)
		var hit := Game.ray(wp + Vector3(0, 1.2, 0), wp - Vector3(0, 3.0, 0), Phys.WORLD, [get_rid()])
		if not hit.is_empty():
			wp = hit["position"]
		q.transform = Transform3D(Basis.IDENTITY, wp + Vector3(0, 0.95, 0))
		if Game.space().intersect_shape(q, 1).is_empty():
			return wp
	return global_transform * Vector3(0.0, body_height + 0.3, 0.0)

func open_door(seat_index: int, open := true) -> void:
	if seat_index < 0 or seat_index >= seats.size():
		return
	var dn := String(seats[seat_index]["door"])
	if dn != "" and doors.has(dn):
		var was := float(doors[dn]["target"])
		doors[dn]["target"] = 1.0 if open else 0.0
		if was != float(doors[dn]["target"]):
			Audio.play(&"door_open" if open else &"door_close", global_position, -8.0)

func _update_doors(delta: float) -> void:
	for dn in doors.keys():
		var d: Dictionary = doors[dn]
		if absf(float(d["open"]) - float(d["target"])) < 0.001:
			continue
		d["open"] = move_toward(float(d["open"]), float(d["target"]), delta * 4.0)
		var ang := float(d["open"]) * deg_to_rad(62.0) * float(d["sign"])
		(d["node"] as Node3D).transform.basis = Basis(Vector3.UP, ang) * (d["rest"] as Basis)

# ---------------------------------------------------------------- lamps / horn / siren
func toggle_lights() -> void:
	lights_on = not lights_on

func set_siren(on: bool) -> void:
	if not def.has("siren"):
		return
	siren_on = on
	if _siren_snd:
		if on and not _siren_snd.playing:
			_siren_snd.play()
		elif not on:
			_siren_snd.stop()
	for l in _siren_lights:
		l.visible = on

func _set_horn(on: bool) -> void:
	if on == _horn_on:
		return
	_horn_on = on
	if on:
		var h: StringName = &"horn_car"
		if mass > 3000.0:
			h = &"horn_truck"
		elif kind == &"bike":
			h = &"horn_bike" if not def.get("pedal", false) else &"bicycle_bell"
		Audio.play(h, global_position, -2.0, 1.0, 0.02, 120.0)
		Events.noise.emit(global_position, 40.0, &"horn", self)

func horn(on: bool) -> void:
	_set_horn(on)

func _update_lamps(delta: float) -> void:
	_blink += delta
	var blink_on := fmod(_blink, 0.7) < 0.35
	var braking := in_brake > 0.1 or (in_throttle < -0.1 and speed > 1.0) or in_handbrake and absf(speed) > 1.0
	var head := 1.0 if lights_on and not destroyed else 0.0
	var tail := (1.0 if braking else (0.35 if lights_on else 0.0)) if not destroyed else 0.0
	var rev := 1.0 if (engine_on and speed < -0.5 and in_throttle < -0.1) else 0.0
	var ind_l := 1.0 if (blink_on and (_indicator == -1 or _indicator == 2)) else 0.0
	var ind_r := 1.0 if (blink_on and (_indicator == 1 or _indicator == 2)) else 0.0
	var sa := 0.0
	var sb := 0.0
	if siren_on:
		var ph := fmod(_blink * 3.2, 1.0)
		sa = 1.0 if ph < 0.5 else 0.0
		sb = 1.0 - sa
		if _siren_lights.size() == 2:
			_siren_lights[0].light_energy = 5.0 * sa
			_siren_lights[1].light_energy = 5.0 * sb
	var aux := 1.0 if (vid == "car_taxi" and engine_on) or (lights_on and kind != &"car") else 0.0
	var a := Vector4(head, tail, rev, ind_l)
	var b := Vector4(ind_r, sa, sb, aux)
	if a != _lamp_a or b != _lamp_b:
		_lamp_a = a
		_lamp_b = b
		for mi in meshes:
			mi.set_instance_shader_parameter(&"lights_a", a)
			mi.set_instance_shader_parameter(&"lights_b", b)
	for sp in _headlights:
		sp.visible = head > 0.5

# ---------------------------------------------------------------- damage
func apply_damage(amount: float, source: Node = null, hit_pos := Vector3.ZERO, dir := Vector3.ZERO, info: Dictionary = {}) -> void:
	if destroyed:
		return
	if has_player() and Game.cheats["invulnerable"]:
		return
	var kind_s := String(info.get("type", "bullet"))
	var armor := 1.0 - 0.14 * float(mods.get("armor", 0))
	var dmg := amount * armor
	if kind_s == "bullet":
		dmg *= 0.55
		_bullet_detail(hit_pos, dir, amount, source)
	elif kind_s == "explosion":
		dmg *= 3.4
	health -= dmg
	_apply_damage_look()
	if source != null and source == Game.player and ai != null and ai.has_method("on_attacked"):
		ai.on_attacked(source)
	if health <= 0.0:
		health = 0.0
		if kind_s == "explosion" or _burn > 0.0:
			explode(source)
		else:
			_start_fire(source)

func _bullet_detail(hit_pos: Vector3, dir: Vector3, amount: float, source: Node) -> void:
	# occupants can be hit through the glass; cabin hits also crack the glass
	var local := to_local(hit_pos)
	if local.y > body_height * 0.55:
		glass_health -= amount * 0.6
		for mi in meshes:
			mi.set_instance_shader_parameter(&"crack", clampf(1.0 - glass_health / 100.0, 0.0, 1.0))
		if glass_health <= 0.0 and glass_health + amount * 0.6 > 0.0:
			Audio.play(&"glass_break", hit_pos, -4.0)
			if Game.fx:
				Game.fx.burst(&"glass", hit_pos, -dir)
			for mi in meshes:
				mi.set_instance_shader_parameter(&"glass_tint", Color(0, 0, 0, 0))
		for s in seats:
			var c: Character = s["occupant"]
			if c != null and c.alive and randf() < (0.3 if glass_health > 0.0 else 0.55):
				var seat_local := _rel_xform(s["node"]).origin
				if absf(seat_local.z - local.z) < 0.9 and (absf(seat_local.x - local.x) < 0.7 or absf(dir.normalized().dot(global_transform.basis.x)) > 0.6):
					c.apply_damage(amount * 0.8, source, hit_pos, dir, {"type": "bullet", "zone": &"torso"})
					break
	_on_bullet(local, amount)

func _on_bullet(_local: Vector3, _amount: float) -> void:
	pass

func _start_fire(source: Node = null) -> void:
	if on_fire or destroyed:
		return
	on_fire = true
	_burn = 5.5
	set_meta("fire_source", source)
	if Game.fx:
		var e := marker_pos("engine", Vector3(0, body_height * 0.6, -half_length * 0.6))
		_fire_fx = Game.fx.make_fire(self, e, 1.0, true)
	Events.fire_started.emit(global_position, self)

## Put out a fire (firefighters). A burning vehicle survives with a little health left.
func extinguish() -> void:
	if on_fire and not destroyed:
		on_fire = false
		_burn = 0.0
		health = maxf(health, max_health * 0.16)
	if _fire_fx:
		_fire_fx.queue_free()
		_fire_fx = null
		if destroyed and _smoke_fx == null and Game.fx:
			_smoke_fx = Game.fx.make_fire(self, Vector3(0, body_height * 0.5, 0), 0.7, false)

func repair() -> void:
	if destroyed:
		return
	health = max_health
	on_fire = false
	_burn = 0.0
	glass_health = 100.0
	dirt = 0.0
	if _fire_fx:
		_fire_fx.queue_free()
		_fire_fx = null
	if _smoke_fx:
		_smoke_fx.queue_free()
		_smoke_fx = null
	for mi in meshes:
		mi.set_instance_shader_parameter(&"crack", 0.0)
	set_glass_tint(_tint_color())
	_apply_damage_look()
	_on_repair()

func _on_repair() -> void:
	pass

func _tint_color() -> Color:
	var lvl := int(mods.get("tint", 0))
	return [Color(0.25, 0.33, 0.38, 0.42), Color(0.16, 0.2, 0.24, 0.62), Color(0.08, 0.09, 0.11, 0.8), Color(0.02, 0.02, 0.03, 0.94)][clampi(lvl, 0, 3)]

func explode(source: Node = null) -> void:
	if destroyed:
		return
	destroyed = true
	health = 0.0
	engine_on = false
	on_fire = false
	set_siren(false)
	lights_on = false
	if source == null and has_meta("fire_source"):
		source = get_meta("fire_source")
	var pos := global_position + Vector3(0, 0.8, 0)
	# occupants do not survive
	for i in seats.size():
		var c: Character = seats[i]["occupant"]
		if c != null:
			unseat(i, global_position + Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1)))
			c.apply_damage(9999.0, source, pos, Vector3.UP, {"type": "explosion", "force": 6.0})
	if Game.fx:
		Game.fx.explosion(pos, 7.5, 150.0, source)
		if _fire_fx:
			_fire_fx.queue_free()
		_fire_fx = Game.fx.make_fire(self, Vector3(0, body_height * 0.5, 0), 1.6, true)
	apply_central_impulse(Vector3(randf_range(-1, 1), 5.5, randf_range(-1, 1)) * mass)
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * mass * 1.5)
	_apply_damage_look()
	for mi in meshes:
		mi.set_instance_shader_parameter(&"glass_tint", Color(0, 0, 0, 0))
		mi.set_instance_shader_parameter(&"emission_scale", 0.0)
	if _engine_snd:
		_engine_snd.stop()
	_dead_time = 0.0
	Game.stats["vehicles_destroyed"] += 1 if source == Game.player else 0
	Events.vehicle_destroyed.emit(self, source)
	destroyed_signal.emit(self)
	_on_destroyed()

func _on_destroyed() -> void:
	pass

# ---------------------------------------------------------------- per-frame
func _physics_process(delta: float) -> void:
	speed = -linear_velocity.dot(global_transform.basis.z)
	_crash_cd = maxf(0.0, _crash_cd - delta)
	if destroyed:
		_dead_time += delta
		if _dead_time > 22.0 and _fire_fx:
			_fire_fx.queue_free()
			_fire_fx = null
			_smoke_fx = Game.fx.make_fire(self, Vector3(0, body_height * 0.5, 0), 1.0, false) if Game.fx else null
		_prev_vel = linear_velocity
		return
	# parked / abandoned vehicles go to sleep (no ray casts, no forces) until something hits them
	if driver() == null and kind != &"boat":
		if sleeping:
			_update_doors(delta)
			_update_lamps(delta)
			_update_audio(delta)
			_prev_vel = linear_velocity
			return
		if linear_velocity.length_squared() < 0.01 and angular_velocity.length_squared() < 0.01:
			_settle += delta
			if _settle > 1.2:
				sleeping = true
		else:
			_settle = 0.0
	else:
		_settle = 0.0
	_drive(delta)
	_update_doors(delta)
	_update_lamps(delta)
	_update_audio(delta)
	_check_hits(delta)
	# smoke when badly damaged, then fire, then boom
	var hp := health / max_health
	if hp < 0.4 and _smoke_fx == null and not on_fire and Game.fx:
		_smoke_fx = Game.fx.make_fire(self, marker_pos("engine", Vector3(0, body_height * 0.6, -half_length * 0.6)), 0.6, false)
	if hp < 0.12 and not on_fire and health > 0.0:
		_start_fire(null)
	if on_fire:
		_burn -= delta
		health = maxf(0.0, health - max_health * 0.03 * delta)
		if _burn <= 0.0:
			explode(null)
	# drowned engines die
	if kind != &"boat" and water_level > 0.9 and engine_on:
		engine_on = false
		for i in seats.size():
			var c: Character = seats[i]["occupant"]
			if c != null and c.is_player and c.has_method("force_exit_vehicle"):
				c.force_exit_vehicle()
	_prev_vel = linear_velocity

func _drive(_delta: float) -> void:
	pass

func _update_audio(delta: float) -> void:
	if _engine_snd == null:
		return
	if engine_on and _engine_snd.stream != null:
		if not _engine_snd.playing:
			_engine_snd.play()
		var load_v := absf(in_throttle) if kind != &"heli" else 0.6
		_engine_snd.pitch_scale = lerpf(_engine_snd.pitch_scale, 0.62 + rpm * 1.25, clampf(delta * 8.0, 0.0, 1.0))
		_engine_snd.volume_db = lerpf(_engine_snd.volume_db, -13.0 + load_v * 7.0 + rpm * 3.0 + (3.0 if has_player() else 0.0), clampf(delta * 6.0, 0.0, 1.0))
	elif _engine_snd.playing:
		_engine_snd.volume_db = move_toward(_engine_snd.volume_db, -80.0, delta * 120.0)
		if _engine_snd.volume_db < -60.0:
			_engine_snd.stop()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# collision damage from contact impulses
	if destroyed or _crash_cd > 0.0:
		return
	var biggest := 0.0
	var where := Vector3.ZERO
	var other: Object = null
	for i in state.get_contact_count():
		var imp := state.get_contact_impulse(i).length()
		if imp > biggest:
			biggest = imp
			where = state.get_contact_collider_position(i)
			other = state.get_contact_collider_object(i)
	var dv := biggest / mass
	if dv > 2.2:
		_crash_cd = 0.25
		var dmg := (dv - 2.2) * 26.0 * (1.0 - 0.1 * float(mods.get("armor", 0)))
		_on_crash(dv, dmg, where, other)

func _on_crash(dv: float, dmg: float, where: Vector3, other: Object) -> void:
	if not (has_player() and Game.cheats["invulnerable"]):
		health -= dmg
		_apply_damage_look()
	var snd := &"crash_small"
	if dv > 9.0:
		snd = &"crash_big"
	elif dv > 5.0:
		snd = &"crash_medium"
	Audio.play(snd, where, -2.0, 1.0, 0.1, 110.0)
	if Game.fx:
		Game.fx.sparks(where, Vector3.UP)
	Events.noise.emit(where, 35.0 + dv * 4.0, &"impact", self)
	var player_in := has_player()
	if player_in:
		if Game.cam and Game.cam.has_method("shake"):
			Game.cam.shake(clampf(dv / 14.0, 0.1, 0.9))
		# hard crashes hurt the occupants
		if dv > 9.0:
			for s in seats:
				var c: Character = s["occupant"]
				if c != null:
					c.apply_damage((dv - 9.0) * 5.0, null, where, Vector3.ZERO, {"type": "vehicle_crash"})
		if other is Vehicle and dv > 3.5 and not (other as Vehicle).is_empty():
			Events.crime.emit(&"collision", where, {"vehicle": other})
	if health <= 0.0:
		health = 0.0
		_start_fire(last_driver)

## Characters and breakable props under the bumper.
func _check_hits(delta: float) -> void:
	var sp := linear_velocity.length()
	_hit_area.monitoring = sp > 1.2
	if sp <= 1.2:
		return
	# look slightly ahead so props wake up before the rigid contact happens
	_hit_shape.position = Vector3(0, _hit_shape.position.y, 0) + global_transform.basis.inverse() * (linear_velocity * 0.06)
	var vdir := linear_velocity / sp
	for b in _hit_area.get_overlapping_bodies():
		if b is Prop:
			var pr := b as Prop
			if not pr.awake and sp >= pr.wake_speed:
				pr.wake(linear_velocity * minf(pr.mass, 80.0) * 0.35 + Vector3(0, pr.mass * 1.2, 0), pr.global_position)
				if has_player() and Game.cam and Game.cam.has_method("shake"):
					Game.cam.shake(0.1)
			continue
		if b.has_method("hit_by_vehicle"):
			b.hit_by_vehicle(self, linear_velocity)
			continue
		if not (b is Character):
			continue
		var c := b as Character
		if not c.alive or c.vehicle == self or c.down:
			continue
		var to := c.global_position - global_position
		var approach := vdir.dot(to.normalized())
		var rel := (linear_velocity - c.velocity).length()
		if approach < 0.2 and rel < 6.0:
			continue
		if rel > 4.0:
			var dmg := (rel - 3.0) * 7.5
			var push := vdir * minf(rel, 16.0) * 0.8 + Vector3(0, 2.5 + rel * 0.12, 0)
			c.apply_damage(dmg, last_driver if driver() != null else null, c.global_position + Vector3(0, 0.8, 0), vdir,
				{"type": "vehicle", "force": 1.0})
			if c.alive:
				c.knockdown(push, 2.6)
			else:
				c.velocity = push
			apply_central_impulse(-vdir * minf(80.0 * rel * 0.6, mass * 1.5))
			Audio.play(&"melee_hit", c.global_position, -2.0, 0.8)
			if has_player():
				Events.crime.emit(&"hit_and_run", c.global_position, {"victim": c})
		else:
			# nudge slow pedestrians out of the way
			var side := to - vdir * to.dot(vdir)
			side.y = 0.0
			if side.length() < 0.05:
				side = global_transform.basis.x
			c.velocity += side.normalized() * 3.0 * delta * 20.0
