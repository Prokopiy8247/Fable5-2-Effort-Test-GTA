class_name Vehicle
extends RigidBody3D
## Base class of every drivable thing: model setup from the Blender GLB, seats/doors, health & damage,
## fire/explosion, lights, siren, paint and modular customisation. Subclasses add the physics.

const LOD_DIST := 46.0

var vid := ""
var def := {}
var kind := "car"
var model: Node3D
var parts := {}
var health := 1000.0
var max_health := 1000.0
var dead := false
var burning := -1.0
var flooded := false
var seats: Array = []
var driver: Node = null
var ai: Node = null
var throttle := 0.0
var steer := 0.0
var brake := 0.0
var handbrake := false
var in_up := 0.0
var in_pitch := 0.0
var in_roll := 0.0
var in_yaw := 0.0
var engine_on := false
var headlights := false
var siren := false
var horn_t := 0.0
var mods := {}
var perf := {"accel": 1.0, "top": 1.0, "brake": 1.0, "grip": 1.0, "armor": 1.0, "downforce": 0.0, "bulletproof": false, "drop": 0.0, "rollk": 1.0}
var paint_color := Color.WHITE
var paint2_color := Color("1b1d21")
var finish := "Gloss"
var paint: StandardMaterial3D
var paint2: StandardMaterial3D
var glass: StandardMaterial3D
var half := Vector3(0.9, 0.7, 2.2)
var owned := false
var is_emergency := false
var last_attacker: Node = null
var tires_popped := [false, false, false, false]
var doors := {}
var door_open := {}
var roof_down := false
var spot_l: SpotLight3D
var spot_r: SpotLight3D
var siren_lights: Array = []
var smoke: Node3D = null
var fire: Node3D = null
var light_nodes: Array = []
var _light_state := ""
var _siren_phase := 0.0
var speed := 0.0
var fwd_speed := 0.0
var wreck_timer := 0.0
var locked_ai := false
var radio_station := 0
var no_despawn := false
var engine_snd: AudioStreamPlayer3D
var siren_snd: AudioStreamPlayer3D
var water_depth := 0.0
var last_driver_was_player := false
var crash_cd := 0.0
var crash_scale := 1.0

static var _lm := {}


static func light_mat(key: String) -> StandardMaterial3D:
	if _lm.is_empty():
		var defs := {"head_off": [Color("8a8674"), 0.0], "head_on": [Color("fff3d6"), 5.0], "tail_off": [Color("5a0d0d"), 0.0], "tail_run": [Color("b01010"), 1.2],
			"tail_brake": [Color("ff2a1a"), 5.0], "rev_off": [Color("b8b8b8"), 0.0], "rev_on": [Color("ffffff"), 3.5], "red_off": [Color("7a1010"), 0.0],
			"red_on": [Color("ff2010"), 7.0], "blue_off": [Color("101e7a"), 0.0], "blue_on": [Color("2050ff"), 7.0], "ind_off": [Color("a8640f"), 0.0], "burnt": [Color("161514"), 0.0]}
		for k in defs:
			var m := StandardMaterial3D.new()
			m.albedo_color = defs[k][0]
			m.roughness = 0.35 if k != "burnt" else 0.95
			if defs[k][1] > 0.0:
				m.emission_enabled = true
				m.emission = defs[k][0]
				m.emission_energy_multiplier = defs[k][1]
			_lm[k] = m
	return _lm[key]


func setup(id: String) -> void:
	vid = id
	def = Defs.VEHICLES[id]
	kind = def.kind
	name = id
	mass = def.mass
	max_health = def.health
	health = max_health
	is_emergency = def.has("emergency")
	add_to_group("vehicles")
	collision_layer = G.L_VEHICLE
	collision_mask = G.L_WORLD | G.L_VEHICLE | G.L_DEBRIS
	contact_monitor = true
	max_contacts_reported = 6
	continuous_cd = false
	can_sleep = true
	model = Assets.inst("vehicles/" + id, id + "_")
	model.name = "Model"
	add_child(model)
	_index(model)
	# collision helpers (imported with a StaticBody3D child because of the COL suffix)
	var aabb := AABB()
	var first := true
	for nm in parts.keys():
		var n: Node = parts[nm]
		if n is MeshInstance3D and n.get_child_count() > 0 and n.get_child(0) is StaticBody3D:
			var cs := CollisionShape3D.new()
			cs.shape = n.mesh.create_convex_shape(true, true)
			cs.transform = n.transform
			add_child(cs)
			var a: AABB = n.transform * n.mesh.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
			n.queue_free()
			parts.erase(nm)
	parts.erase("StaticBody3D")
	parts.erase("CollisionShape3D")
	half = aabb.size * 0.5
	half.y = aabb.end.y * 0.5
	# materials
	var cols: Array = def.get("colors", [])
	if not cols.is_empty():
		paint_color = Color(cols[G.rng.randi() % cols.size()])
	paint = StandardMaterial3D.new()
	paint2 = StandardMaterial3D.new()
	glass = (Assets.mats["Glass"] as StandardMaterial3D) if Assets.mats.has("Glass") else StandardMaterial3D.new()
	_apply_paint()
	for nm in parts.keys():
		var mi := parts[nm] as MeshInstance3D
		if mi == null:
			continue
		var is_lod: bool = nm == "LOD1"
		if is_lod:
			mi.visibility_range_begin = LOD_DIST
			mi.visibility_range_end = 420.0
		else:
			mi.visibility_range_end = LOD_DIST
		var has_light := false
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m == null:
				continue
			var mn := m.resource_name
			if mn.begins_with("CarPaint_"):
				mi.set_surface_override_material(i, paint)
			elif mn.begins_with("CarPaint2_"):
				mi.set_surface_override_material(i, paint2)
			elif mn in ["LightHead", "LightTail", "LightReverse", "LightBarRed", "LightBarBlue"]:
				has_light = true
		if has_light:
			light_nodes.append(mi)
		if nm.begins_with("Mod_"):
			mi.visible = false
		if nm.begins_with("Door_"):
			doors[nm] = mi
			door_open[nm] = 0.0
	var i := 0
	while parts.has("Seat_%d" % i):
		var sn: Node3D = parts["Seat_%d" % i]
		var side := -1.0 if sn.position.x < -0.05 else (1.0 if sn.position.x > 0.05 else (-1.0 if i % 2 == 0 else 1.0))
		var dn := ""
		if kind == "car":
			var front := "F" if i < 2 else "R"
			dn = "Door_%s%s" % [front, "L" if side < 0 else "R"]
			if not doors.has(dn):
				dn = "Door_F%s" % ("L" if side < 0 else "R")
		seats.append({"node": sn, "occ": null, "vis": null, "door": dn if doors.has(dn) else "", "side": side})
		i += 1
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, half.y * 0.55, 0)
	_set_lights()
	if parts.has("Roof"):
		pass


func _index(n: Node) -> void:
	for c in n.get_children():
		parts[String(c.name)] = c
		_index(c)


func part(nm: String) -> Node3D:
	return parts.get(nm)


func _apply_paint() -> void:
	var f: Dictionary = Defs.FINISHES.get(finish, Defs.FINISHES["Gloss"])
	paint.albedo_color = paint_color
	paint.roughness = f.rough
	paint.metallic = f.metal
	paint.clearcoat_enabled = finish != "Matte"
	paint.clearcoat = 0.6
	paint.clearcoat_roughness = 0.12
	paint2.albedo_color = paint2_color
	paint2.roughness = 0.4
	paint2.metallic = 0.3


func set_paint(c: Color, c2 = null, fin: String = "") -> void:
	paint_color = c
	if c2 != null:
		paint2_color = c2
	if fin != "":
		finish = fin
	_apply_paint()


# ------------------------------------------------------------------ lights / siren
func _set_lights() -> void:
	var night: bool = G.timew != null and G.timew.night > 0.4
	var on: bool = (headlights or (night and (driver != null))) and not dead
	var braking := brake > 0.1 and not dead
	var rev := fwd_speed < -0.5 and throttle < -0.1
	var sp := int(_siren_phase * 6.0) % 2 if siren else -1
	var st := "%s%s%s%d%s" % [on, braking, rev, sp, dead]
	if st == _light_state:
		return
	_light_state = st
	for mi in light_nodes:
		var m: MeshInstance3D = mi
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			if mat == null:
				continue
			match mat.resource_name:
				"LightHead": m.set_surface_override_material(i, light_mat("burnt" if dead else ("head_on" if on else "head_off")))
				"LightTail": m.set_surface_override_material(i, light_mat("burnt" if dead else ("tail_brake" if braking else ("tail_run" if on else "tail_off"))))
				"LightReverse": m.set_surface_override_material(i, light_mat("rev_on" if rev else "rev_off"))
				"LightBarRed": m.set_surface_override_material(i, light_mat("red_on" if sp == 0 else "red_off"))
				"LightBarBlue": m.set_surface_override_material(i, light_mat("blue_on" if sp == 1 else "blue_off"))
	var want_spots: bool = on and (driver != null and G.is_player(driver))
	if want_spots and spot_l == null and parts.has("P_Head_L"):
		for key in ["P_Head_L", "P_Head_R"]:
			if not parts.has(key):
				continue
			var s := SpotLight3D.new()
			s.spot_range = 48.0
			s.spot_angle = 34.0
			s.light_energy = 9.0
			s.light_color = Color(mod_opt("lights").get("color", "fff0cc"))
			s.shadow_enabled = key == "P_Head_L"
			s.position = (parts[key] as Node3D).position + Vector3(0, 0, -0.1)
			s.rotation = Vector3(-0.06, 0, 0)
			add_child(s)
			if key == "P_Head_L":
				spot_l = s
			else:
				spot_r = s
	if spot_l:
		spot_l.visible = want_spots
	if spot_r:
		spot_r.visible = want_spots


func set_siren(on: bool) -> void:
	if not def.get("siren", false) and not def.has("emergency"):
		return
	siren = on and not dead
	if siren and siren_lights.is_empty():
		for c in [Color(1, 0.1, 0.05), Color(0.1, 0.25, 1)]:
			var l := OmniLight3D.new()
			l.omni_range = 16.0
			l.light_color = c
			l.light_energy = 0.0
			l.shadow_enabled = false
			l.position = Vector3(-0.4 if siren_lights.is_empty() else 0.4, half.y * 2.0 + 0.3, 0)
			add_child(l)
			siren_lights.append(l)
	if not siren:
		for l in siren_lights:
			l.light_energy = 0.0
	if Sfx.has_method("siren"):
		Sfx.siren(self, siren)


func honk() -> void:
	if dead:
		return
	horn_t = 0.5
	Sfx.play(mod_opt("horn").get("snd", "horn"), global_position, 0.0, 1.0 if mass < 3000 else 0.75)
	G.make_noise(global_position, 30.0, "horn", driver)


# ------------------------------------------------------------------ seats
func free_seat(prefer_driver: bool = true) -> int:
	if prefer_driver and seats.size() > 0 and seats[0].occ == null:
		return 0
	for i in seats.size():
		if seats[i].occ == null:
			return i
	return -1


func seat_global(i: int) -> Transform3D:
	return (seats[i].node as Node3D).global_transform


func door_point(i: int) -> Vector3:
	## World position next to the door of seat i (where a character stands to get in / ends up when getting out).
	var sn: Node3D = seats[i].node
	var side: float = seats[i].side
	var lp := Vector3(side * (half.x + 0.75), 0.0, sn.position.z + 0.2)
	if kind in ["bike", "boat"]:
		lp = Vector3(side * (half.x + 0.7), 0.0, sn.position.z)
	if kind in ["heli", "plane"]:
		lp = Vector3(side * (minf(half.x, 1.4) + 0.9), 0.0, sn.position.z)
	return global_transform * lp


func set_door(i: int, open: bool) -> void:
	var dn: String = seats[i].door
	if dn != "":
		door_open[dn + "_t"] = 1.0 if open else 0.0


func occupy(i: int, who: Node) -> void:
	seats[i].occ = who
	if i == 0:
		driver = who
		engine_on = not dead and not flooded
		sleeping = false
		if G.is_player(who):
			last_driver_was_player = true
	_light_state = ""


func vacate(who: Node) -> void:
	for s in seats:
		if s.occ == who:
			s.occ = null
	if driver == who:
		driver = null
		throttle = 0.0
		steer = 0.0
		brake = 1.0 if kind != "heli" and kind != "plane" else 0.0
		handbrake = kind in ["car", "bike"]
		in_up = 0.0
		in_pitch = 0.0
		in_roll = 0.0
		in_yaw = 0.0
		if siren and ai == null:
			pass
	_light_state = ""


func occupants() -> Array:
	var out: Array = []
	for s in seats:
		if s.occ != null and is_instance_valid(s.occ):
			out.append(s.occ)
	return out


func has_player() -> bool:
	for s in seats:
		if s.occ != null and G.is_player(s.occ):
			return true
	return false


# ------------------------------------------------------------------ damage
func take_damage(amount: float, instigator: Node = null, pos: Vector3 = Vector3.ZERO, dkind: String = "") -> void:
	rest_wake()
	if dead:
		return
	if instigator != null:
		last_attacker = instigator
	var a := amount * float(perf.armor)
	if dkind == "bullet":
		a *= 0.32 if not def.get("armored", false) else 0.12
		if not perf.bulletproof and kind in ["car", "bike"] and pos != Vector3.ZERO:
			_maybe_pop_tire(pos)
		if has_player() and instigator != null and not G.is_player(instigator) and G.rng.randf() < 0.22 and G.player.has_method("take_damage"):
			G.player.take_damage(amount * 0.45, instigator, pos, "bullet")
	elif dkind == "melee":
		a *= 0.25
	if G.flags.god and has_player():
		a = 0.0
	health -= a
	if G.is_player(instigator) and not has_player() and (driver != null or is_emergency) and dkind != "crash":
		G.report_crime("vehicle_attack", global_position, 1.0 if not is_emergency else 2.0, instigator)
	if health <= 0.0:
		explode(instigator)
	elif health < max_health * 0.12 and burning < 0.0:
		burning = 5.5 + G.rng.randf() * 2.0


func _maybe_pop_tire(_pos: Vector3) -> void:
	pass


func repair() -> void:
	if dead:
		return
	health = max_health
	burning = -1.0
	tires_popped = [false, false, false, false]
	if smoke:
		smoke.queue_free()
		smoke = null
	if fire:
		fire.queue_free()
		fire = null


func explode(instigator: Node = null) -> void:
	if dead:
		return
	dead = true
	health = 0.0
	burning = -1.0
	engine_on = false
	siren = false
	wreck_timer = 45.0
	var pos := global_position + Vector3(0, 0.6, 0)
	for s in seats:
		var o: Node = s.occ
		if o != null and is_instance_valid(o) and o.has_method("on_vehicle_destroyed"):
			o.on_vehicle_destroyed(self)
	if G.fx:
		G.fx.explosion(pos, 1.3 if mass < 3000 else 1.8)
	G.damage_radius(pos, 8.0, 260.0, instigator if instigator != null else last_attacker)
	apply_central_impulse(Vector3(G.rng.randf_range(-1, 1), 5.5, G.rng.randf_range(-1, 1)) * mass)
	apply_torque_impulse(Vector3(G.rng.randf_range(-1, 1), 0, G.rng.randf_range(-1, 1)) * mass * 1.5)
	paint.albedo_color = Color(0.07, 0.065, 0.06)
	paint.roughness = 0.95
	paint.metallic = 0.1
	paint.clearcoat_enabled = false
	paint2.albedo_color = Color(0.05, 0.05, 0.05)
	_light_state = ""
	_set_lights()
	for l in siren_lights:
		l.light_energy = 0.0
	if G.fx:
		fire = G.fx.attach_fire(self, Vector3(0, half.y, 0), 1.6, 22.0)
	if is_emergency and instigator != null and G.is_player(instigator):
		G.report_crime("destroy_police", global_position, 3.0, instigator)
	if Sfx.has_method("stop_engine"):
		Sfx.stop_engine(self)


func _process(delta: float) -> void:
	speed = linear_velocity.length()
	fwd_speed = -linear_velocity.dot(global_transform.basis.z)
	if siren:
		_siren_phase += delta
		var ph := int(_siren_phase * 6.0) % 2
		if siren_lights.size() == 2:
			siren_lights[0].light_energy = 5.0 if ph == 0 else 0.0
			siren_lights[1].light_energy = 5.0 if ph == 1 else 0.0
	_set_lights()
	# doors
	for dn in doors.keys():
		var tgt: float = door_open.get(dn + "_t", 0.0)
		var cur: float = door_open[dn]
		if absf(cur - tgt) > 0.001:
			cur = move_toward(cur, tgt, delta * 4.5)
			door_open[dn] = cur
			var d: Node3D = doors[dn]
			var sgn := -1.0 if dn.ends_with("L") else 1.0
			d.rotation.y = sgn * cur * 1.15
	# damage smoke / fire
	if not dead:
		var hp := health / max_health
		if hp < 0.45 and smoke == null and G.fx:
			var ep: Node3D = parts.get("P_Engine")
			smoke = G.fx.attach_smoke(self, ep.position if ep else Vector3(0, half.y, -half.z * 0.6))
		if smoke and smoke.has_method("set_level"):
			smoke.set_level(clampf(1.0 - hp / 0.45, 0.1, 1.0))
		if burning >= 0.0:
			if fire == null and G.fx:
				var ep2: Node3D = parts.get("P_Engine")
				fire = G.fx.attach_fire(self, ep2.position if ep2 else Vector3(0, half.y, -half.z * 0.6), 0.8, 99.0)
			burning -= delta
			if burning <= 0.0:
				explode(last_attacker)
	else:
		wreck_timer -= delta
	if horn_t > 0.0:
		horn_t -= delta


func rest_wake() -> void:
	pass


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	crash_cd -= state.step
	var worst := 0.0
	var idx := -1
	for i in state.get_contact_count():
		var iv := state.get_contact_impulse(i)
		var imp := iv.length()
		if imp > worst:
			worst = imp
			idx = i
		# a resting (frozen) car that gets hit wakes up and receives the opposite impulse
		var o := state.get_contact_collider_object(i)
		if o is Car and (o as Car).resting:
			var oc := o as Car
			oc.rest_wake()
			oc.apply_impulse(-iv * 0.85, state.get_contact_collider_position(i) - oc.global_position)
	if crash_cd > 0.0 or idx < 0:
		return
	var dv := worst / mass
	if dv < 2.2:
		return
	crash_cd = 0.25
	_on_crash(dv, state.get_contact_collider_object(idx), state.get_contact_collider_position(idx), state.get_contact_collider_shape(idx))


func _on_crash(dv: float, _other: Object, pos: Vector3, _shape_idx: int) -> void:
	var dmg := pow(dv - 2.2, 1.25) * 13.0 * crash_scale
	take_damage(dmg, null, pos, "crash")
	Sfx.play("crash", pos, clampf(dv * 1.5 - 12.0, -12.0, 3.0), randf_range(0.8, 1.15))
	if G.fx:
		G.fx.sparks(pos, 6 + int(dv))
	if has_player():
		if G.cam:
			G.cam.shake(clampf(dv * 0.05, 0.1, 0.7))
		if dv > 9.0 and G.player.has_method("take_damage"):
			G.player.take_damage((dv - 9.0) * 4.0, null, pos, "crash")


# ------------------------------------------------------------------ customisation
func mod_opt(slot: String) -> Dictionary:
	if not Defs.CAR_MODS.has(slot):
		return {}
	var opts: Array = Defs.CAR_MODS[slot].options
	return opts[clampi(int(mods.get(slot, 0)), 0, opts.size() - 1)]


func can_mod(slot: String) -> bool:
	if kind != "car" or def.has("emergency") or vid == "taxi":
		return slot in ["engine", "brakes", "armor", "tires", "horn", "tint"] and kind == "car"
	var opts: Array = Defs.CAR_MODS[slot].options
	for o in opts:
		if o.has("node") and not parts.has(o.node):
			return false
	return true


func set_mod(slot: String, idx: int) -> void:
	mods[slot] = idx
	apply_mods()


func apply_mods() -> void:
	perf = {"accel": 1.0, "top": 1.0, "brake": 1.0, "grip": 1.0, "armor": 1.0, "downforce": 0.0, "bulletproof": false, "drop": 0.0, "rollk": 1.0}
	var m := float(def.mass)
	for slot in Defs.CAR_MODS.keys():
		var opts: Array = Defs.CAR_MODS[slot].options
		var sel := clampi(int(mods.get(slot, 0)), 0, opts.size() - 1)
		for i in opts.size():
			var o: Dictionary = opts[i]
			if o.has("node") and parts.has(o.node):
				(parts[o.node] as Node3D).visible = i == sel
		var hide_stock := ""
		for o2 in opts:
			if o2.has("hide"):
				hide_stock = o2.hide
		if hide_stock != "" and parts.has(hide_stock):
			(parts[hide_stock] as Node3D).visible = not opts[sel].has("hide")
		var o3: Dictionary = opts[sel]
		for k in ["accel", "top", "brake", "grip", "armor"]:
			if o3.has(k):
				perf[k] *= float(o3[k])
		if o3.has("downforce"):
			perf.downforce += float(o3.downforce)
		if o3.has("bulletproof"):
			perf.bulletproof = true
		if o3.has("drop"):
			perf.drop = float(o3.drop)
			perf.rollk = float(o3.rollk)
		if o3.has("mass"):
			m *= float(o3.mass)
		if slot == "tint" and Assets.mats.has("Glass"):
			if sel == 0:
				glass = Assets.mats["Glass"]
			else:
				glass = (Assets.mats["Glass"] as StandardMaterial3D).duplicate()
				glass.albedo_color = Color(0.05, 0.07, 0.09, float(o3.alpha))
			_override_named("Glass", glass)
		if slot == "plate":
			_override_named("Plate", Assets.color_mat(Color(o3.get("color", "e9e6da")), 0.6))
		if slot == "wheels":
			_apply_rims(o3)
		if slot == "lights" and spot_l:
			spot_l.light_color = Color(o3.get("color", "fff0cc"))
			if spot_r:
				spot_r.light_color = spot_l.light_color
	mass = m
	if G.flags.all_mods:
		pass


func _override_named(mat_name: String, m: Material) -> void:
	for nm in parts.keys():
		var mi := parts[nm] as MeshInstance3D
		if mi == null:
			continue
		for i in mi.mesh.get_surface_count():
			var sm := mi.mesh.surface_get_material(i)
			if sm and sm.resource_name == mat_name:
				mi.set_surface_override_material(i, m)


func _apply_rims(_opt: Dictionary) -> void:
	pass


func set_roof(down: bool) -> void:
	if parts.has("Roof"):
		roof_down = down
		(parts["Roof"] as Node3D).visible = not down


func export_state() -> Dictionary:
	return {"vid": vid, "paint": paint_color.to_html(), "paint2": paint2_color.to_html(), "finish": finish, "mods": mods.duplicate(), "health": health, "roof": roof_down}


func import_state(d: Dictionary) -> void:
	paint_color = Color(d.get("paint", paint_color.to_html()))
	paint2_color = Color(d.get("paint2", paint2_color.to_html()))
	finish = d.get("finish", "Gloss")
	_apply_paint()
	mods = d.get("mods", {}).duplicate()
	for k in mods.keys():
		mods[k] = int(mods[k])
	apply_mods()
	health = clampf(float(d.get("health", max_health)), 50.0, max_health)
	set_roof(bool(d.get("roof", false)))
