extends Node
## Headless systems test for the vehicle framework (uses the real sedan GLB, or the first car
## whose GLB exists): spawn rules, occupant API, player input path, lights, paint, damage ->
## smoke -> fire -> explosion -> wreck -> repair, glass, tyres, mods (measured), pop_tire pull,
## self-righting, pedestrian strike + crime hook, save data, caps, builder fallbacks, hinged lids
## (hood / trunk / convertible roof), game-time clock.
##
## Run: tools\godot.ps1 -Mode headless -Frames 9000 -UserArgs '--test=veh_systems','--no_player',
##      '--disable=world,environment,city,interactions,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'

const Bed := preload("res://gta/tests/veh_testbed.gd")

const OCCUPANT_SRC := "extends Node3D
var damage_taken := 0.0
var last_type := \"\"
var ejected := false
var eject_y := -999.0
func apply_damage(info: Dictionary) -> void:
	damage_taken += float(info.get(\"amount\", 0.0))
	last_type = str(info.get(\"type\", \"\"))
func on_vehicle_ejected(_v: Node, xf: Transform3D, _impulse: Vector3) -> void:
	ejected = true
	eject_y = xf.origin.y
"

const PED_SRC := "extends CharacterBody3D
var damage_taken := 0.0
var last_type := \"\"
var knocked := false
func apply_damage(info: Dictionary) -> void:
	damage_taken += float(info.get(\"amount\", 0.0))
	last_type = str(info.get(\"type\", \"\"))
func knock_down(_impulse: Vector3) -> void:
	knocked = true
"

var mgr: Node = null
var car_id: String = "sedan"
var cam: Camera3D = null
var _orphans0: int = 0
var ev := {"collisions": 0, "max_impulse": 0.0, "damaged": 0, "destroyed": 0, "explosions": 0, "spawned": 0,
		"modified": 0, "crimes": [], "noises": {}}


func _ready() -> void:
	await _run()


func _on_collision(_v: Node3D, _o: Node, impulse: float, _p: Vector3) -> void:
	ev["collisions"] = int(ev["collisions"]) + 1
	ev["max_impulse"] = maxf(float(ev["max_impulse"]), impulse)


func _on_damaged(_v: Node3D, _a: float, _i: Dictionary) -> void:
	ev["damaged"] = int(ev["damaged"]) + 1


func _on_destroyed(_v: Node3D, _i: Node) -> void:
	ev["destroyed"] = int(ev["destroyed"]) + 1


func _on_explosion(_p: Vector3, _r: float, _i: Node) -> void:
	ev["explosions"] = int(ev["explosions"]) + 1


func _on_spawned(_v: Node3D) -> void:
	ev["spawned"] = int(ev["spawned"]) + 1


func _on_modified(_v: Node3D) -> void:
	ev["modified"] = int(ev["modified"]) + 1


func _on_crime(id: String, _p: Vector3, _i: Node) -> void:
	(ev["crimes"] as Array).append(id)


func _on_noise(_p: Vector3, _r: float, kind: String, _i: Node) -> void:
	(ev["noises"] as Dictionary)[kind] = true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _spawn(pos: Vector3, opts: Dictionary = {}, id: String = "") -> Variant:
	return Game.spawn_vehicle(car_id if id == "" else id, Transform3D(Basis.IDENTITY, pos), opts)


func _look_at_car(v: Node3D) -> void:
	cam.global_position = v.global_position + Vector3(4.0, 3.0, 7.0)


func _run() -> void:
	mgr = Game.get_system("vehicles")
	if not TestHarness.check(mgr != null, "vehicles system is registered"):
		TestHarness.finish(false, "no vehicles system")
		return
	Bed.build_proving_ground(self)
	cam = Bed.make_camera(self)
	cam.global_position = Vector3(4.0, 3.0, 8.0)
	var avail := Bed.ids_with_models()
	if not avail.has(car_id) and not avail.is_empty():
		car_id = avail[0]
	if not TestHarness.check(avail.has(car_id), "a car GLB is available (%s)" % car_id):
		TestHarness.finish(false, "no models")
		return
	EventBus.vehicle_collision.connect(_on_collision)
	EventBus.vehicle_damaged.connect(_on_damaged)
	EventBus.vehicle_destroyed.connect(_on_destroyed)
	EventBus.explosion.connect(_on_explosion)
	EventBus.vehicle_spawned.connect(_on_spawned)
	EventBus.vehicle_modified.connect(_on_modified)
	EventBus.crime_committed.connect(_on_crime)
	EventBus.noise_emitted.connect(_on_noise)
	await _frames(2)
	_orphans0 = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	await _test_spawn_rules()
	await _test_occupants()
	await _test_player_input()
	await _test_lights()
	await _test_lids()
	await _test_paint()
	await _test_mods()
	await _test_damage()
	await _test_pop_tire()
	await _test_self_right()
	await _test_water_stall()
	await _test_ped_strike()
	await _test_save()
	await _test_fallback_and_caps()
	await _frames(20)
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("VEH_SYSTEMS: orphan nodes at the end = %d (start %d), live vehicles = %d" % [orphans, _orphans0, mgr.get_vehicle_count()])
	if orphans > _orphans0:
		Node.print_orphan_nodes()
	TestHarness.finish()


# ---------------------------------------------------------------------------------------------
func _test_spawn_rules() -> void:
	var bad: Variant = Game.spawn_vehicle("no_such_vehicle", Transform3D.IDENTITY)
	TestHarness.check(bad == null, "unknown spec id returns null")
	var missing := ""
	for id: Variant in Registry.ids("vehicles"):
		if not mgr.can_spawn(str(id)):
			missing = str(id)
			break
	if missing != "":
		var m: Variant = Game.spawn_vehicle(missing, Transform3D.IDENTITY)
		TestHarness.check(m == null, "spec without a GLB (%s) does not spawn" % missing)
	else:
		TestHarness.log_line("every registered spec has a GLB - missing-model path not exercised here")
	TestHarness.check(Registry.ids("vehicles").size() >= 13, "13+ vehicle specs registered (%d)" % Registry.ids("vehicles").size())
	TestHarness.check(Registry.count("vehicle_mods") >= 40, "vehicle mods registered (%d)" % Registry.count("vehicle_mods"))
	var before := int(ev["spawned"])
	var v: Variant = _spawn(Vector3(0, 0, 0))
	TestHarness.check(v != null and v is RigidBody3D, "%s spawns as a RigidBody3D" % car_id)
	if v == null:
		return
	TestHarness.check(int(ev["spawned"]) == before + 1, "EventBus.vehicle_spawned emitted")
	TestHarness.check(v.is_in_group("vehicle"), "in group 'vehicle'")
	TestHarness.check(v.collision_layer == Layers.VEHICLE and v.collision_mask == Layers.VEHICLE_MASK, "collision layer / mask from Layers")
	TestHarness.check(v.get_wheel_count() == 4, "4 wheels found")
	var col_hidden := true
	var mod_hidden := true
	for part_name: String in v._nodes:
		if part_name.begins_with("Col_") and v.get_part(part_name).visible:
			col_hidden = false
		if part_name.begins_with("Mod_") and v.get_part(part_name).visible:
			mod_hidden = false
	TestHarness.check(col_hidden and mod_hidden, "Col_* and Mod_* helper meshes are hidden")
	var hulls := 0
	for c: Node in v.get_children():
		if c is CollisionShape3D:
			hulls += 1
	TestHarness.check(hulls >= 1, "collision hull built (%d shapes)" % hulls)
	if v.has_part("Body_LOD1"):
		var lod := v.get_part("Body_LOD1") as GeometryInstance3D
		var body := v.get_part("Body") as GeometryInstance3D
		TestHarness.check(lod.visibility_range_begin > 10.0 and body.visibility_range_end > 10.0, "LOD swap distances set (Body <-> Body_LOD1 at %.0f m)" % lod.visibility_range_begin)
	var cp: Dictionary = v.get_camera_params()
	TestHarness.check(cp.has("distance") and cp.has("height") and cp.has("fov") and cp.has("look_height"), "camera params exposed")
	mgr.despawn_vehicle(v)
	await _frames(2)


# ---------------------------------------------------------------------------------------------
func _test_occupants() -> void:
	var v: Variant = _spawn(Vector3(0, 0, 0))
	_look_at_car(v)
	await _frames(30)
	var occ: Node3D = _script(OCCUPANT_SRC).new()
	occ.name = "DummyOccupant"
	add_child(occ)
	TestHarness.check(v.get_seat_count() >= 1 and v.get_free_seat() == 0, "seats from Seat_* markers (%d), driver seat free" % v.get_seat_count())
	TestHarness.check(v.can_enter(occ), "can_enter() for an empty vehicle")
	v.occupant_enter(occ, 0)
	TestHarness.check(v.driver == occ and not v.is_player_driven and v.engine_on, "occupant_enter(0): driver set, engine started")
	TestHarness.check(v.get_occupants().size() == 1 and v.get_free_seat() == (1 if v.get_seat_count() > 1 else -1), "occupant list / next free seat")
	TestHarness.check(v.get_seat_node(0) != null and String(v.get_seat_node(0).name) == "Seat_Driver", "get_seat_node(0) is Seat_Driver")
	await _frames(12)
	if v.has_part("Door_FL"):
		TestHarness.check(float(v._door_open[0]) > 0.2, "driver door swings open on enter (%.2f)" % float(v._door_open[0]))
	var xf: Transform3D = v.occupant_exit(0)
	var local: Vector3 = v.global_transform.affine_inverse() * xf.origin
	TestHarness.check(v.driver == null and v.get_occupants().is_empty() and not v.engine_on, "occupant_exit(0): seat freed, engine off")
	TestHarness.check(local.x < -1.0 and absf(xf.origin.y) < 0.2, "exit transform is on the ground beside the driver door (local x %.2f, y %.2f)" % [local.x, xf.origin.y])
	# block the driver's side: the exit must move to the other side
	var wall := Bed.add_static_box(self, Vector3(1.2, 2.4, 6.0), Transform3D(Basis.IDENTITY, v.global_position + Vector3(-1.9, 1.2, 0.0)), Color.GRAY)
	await _frames(3)
	var xf2: Transform3D = v.get_exit_transform(0)
	var local2: Vector3 = v.global_transform.affine_inverse() * xf2.origin
	TestHarness.check(local2.x > 1.0, "blocked door -> exit on the passenger side (local x %.2f)" % local2.x)
	var wall2 := Bed.add_static_box(self, Vector3(1.2, 2.4, 6.0), Transform3D(Basis.IDENTITY, v.global_position + Vector3(1.9, 1.2, 0.0)), Color.GRAY)
	var wall3 := Bed.add_static_box(self, Vector3(6.0, 2.4, 1.2), Transform3D(Basis.IDENTITY, v.global_position + Vector3(0.0, 1.2, 3.6)), Color.GRAY)
	var wall4 := Bed.add_static_box(self, Vector3(6.0, 2.4, 1.2), Transform3D(Basis.IDENTITY, v.global_position + Vector3(0.0, 1.2, -3.6)), Color.GRAY)
	await _frames(3)
	var xf3: Transform3D = v.get_exit_transform(0)
	TestHarness.check(xf3.origin.y > 1.0, "boxed in on all sides -> fallback exit on the roof (y %.2f)" % xf3.origin.y)
	for w: Node in [wall, wall2, wall3, wall4]:
		w.queue_free()
	await _frames(3)
	# eject with notification
	v.occupant_enter(occ, 1 if v.get_seat_count() > 1 else 0)
	v.eject_occupants(Vector3.UP * 100.0)
	TestHarness.check(v.get_occupants().is_empty() and bool(occ.ejected), "eject_occupants() clears seats and notifies the occupant")
	occ.queue_free()
	mgr.despawn_vehicle(v)
	await _frames(2)


# ---------------------------------------------------------------------------------------------
func _test_player_input() -> void:
	var v: Variant = _spawn(Vector3(0, 0, 0))
	_look_at_car(v)
	await _frames(30)
	var p: Node3D = _script(OCCUPANT_SRC).new()
	p.name = "DummyPlayerDriver"
	p.add_to_group("player")
	add_child(p)
	v.occupant_enter(p, 0)
	TestHarness.check(v.is_player_driven and v.owner_tag == "player", "a driver in group 'player' makes the vehicle player driven")
	v.set_inputs(-1.0, 1.0, 0.0)
	TestHarness.check(is_zero_approx(v.in_steer), "set_inputs() is ignored while the player drives")
	Input.action_press("move_forward")
	await _frames(150)
	var sp1: float = v.get_forward_speed()
	TestHarness.check(sp1 > 6.0, "move_forward accelerates (%.1f m/s after 2.5 s)" % sp1)
	Input.action_press("move_right")
	var h0 := Bed.heading(v)
	await _frames(45)
	Input.action_release("move_right")
	TestHarness.check(wrapf(Bed.heading(v) - h0, -PI, PI) > 0.05, "move_right steers right")
	Game.lock_input()
	await _frames(3)
	TestHarness.check(is_zero_approx(v.in_throttle), "Game.lock_input() blocks driving input")
	Game.unlock_input()
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await _frames(8)
	TestHarness.check(v.in_brake > 0.5 and v.in_throttle <= 0.0 and v.is_braking(), "move_back brakes while rolling forward")
	await _frames(330)
	var sp2: float = v.get_forward_speed()
	TestHarness.check(sp2 < -1.5 and v.is_reversing(), "... then reverses (%.1f m/s)" % sp2)
	Input.action_release("move_back")
	Input.action_press("handbrake")
	await _frames(60)
	TestHarness.check(v.in_handbrake, "handbrake action sets the handbrake")
	Input.action_release("handbrake")
	var mode0: int = v.headlight_mode
	Input.action_press("headlights")
	await _frames(2)
	Input.action_release("headlights")
	await _frames(2)
	TestHarness.check(v.headlight_mode == (mode0 + 1) % 3, "headlights action cycles the lights")
	Input.action_press("horn")
	await _frames(3)
	TestHarness.check(v.horn_on and ev["noises"].has("horn"), "horn action honks and emits a noise event")
	Input.action_release("horn")
	Input.action_press("siren")
	await _frames(3)
	Input.action_release("siren")
	TestHarness.check(not v.siren_on, "civilian car has no siren")
	v.occupant_exit(0)
	TestHarness.check(not v.is_player_driven, "player flag cleared on exit")
	p.remove_from_group("player")
	p.queue_free()
	mgr.despawn_vehicle(v)
	await _frames(2)


# ---------------------------------------------------------------------------------------------
func _test_lights() -> void:
	var v: Variant = _spawn(Vector3(0, 0, 0))
	_look_at_car(v)
	await _frames(20)
	await get_tree().process_frame
	var L: Variant = v.lights
	TestHarness.check(L.head_mat != null and L.tail_mat != null, "head / tail light materials are per-instance copies")
	if L.head_mat == null or L.tail_mat == null:
		mgr.despawn_vehicle(v)
		return
	TestHarness.check(L.head_mat != v.get_original_material("M_Headlight"), "light material is not the shared authored one")
	TestHarness.check(is_zero_approx(L.head_mat.emission_energy_multiplier), "headlights start off")
	v.set_headlights(1)
	await _frames(3)
	var low: float = L.head_mat.emission_energy_multiplier
	v.set_headlights(2)
	await _frames(3)
	var high: float = L.head_mat.emission_energy_multiplier
	TestHarness.check(low > 1.0 and high > low, "set_headlights(1/2) raises emission (%.1f / %.1f)" % [low, high])
	TestHarness.check(L.tail_mat.emission_energy_multiplier > 0.5, "tail lights run with the headlights")
	v.set_inputs(0.0, 0.0, 1.0)
	await _frames(3)
	TestHarness.check(L.tail_mat.emission_energy_multiplier > 3.0, "brake lights on while braking (%.1f)" % L.tail_mat.emission_energy_multiplier)
	v.set_inputs(-1.0, 0.0, 0.0)
	await _frames(30)
	if L.reverse_mat != null:
		TestHarness.check(L.reverse_mat.emission_energy_multiplier > 1.0, "reverse lights on in reverse")
	v.set_inputs(0.0, 0.0, 1.0)
	await _frames(60)
	v.set_inputs(0.0, 0.0, 0.0)
	if L.indicator_mat != null:
		v.set_indicator(-1)
		await _frames(4)
		var l_on := float(L.indicator_mat.get_shader_parameter("left_on"))
		var r_on := float(L.indicator_mat.get_shader_parameter("right_on"))
		TestHarness.check(l_on > 0.5 and r_on < 0.5, "left indicator blinks on the left side only")
		v.set_indicator(0)
	# pooled real lights (player vehicle gets two; others the nearest four)
	await _frames(20)
	var lit := 0
	for c: Node in mgr.get_children():
		if c is SpotLight3D and (c as SpotLight3D).visible:
			lit += 1
	TestHarness.check(lit == 1, "one pooled SpotLight3D follows a nearby AI vehicle with headlights (%d visible)" % lit)
	v.set_headlights(0)
	await _frames(20)
	lit = 0
	for c: Node in mgr.get_children():
		if c is SpotLight3D and (c as SpotLight3D).visible:
			lit += 1
	TestHarness.check(lit == 0, "pooled light released when the headlights go off")
	v.set_siren(true)
	TestHarness.check(not v.siren_on, "set_siren() refused on a non-emergency vehicle")
	mgr.despawn_vehicle(v)
	# emergency vehicle siren (only if a police cruiser GLB exists yet)
	if mgr.can_spawn("police_cruiser"):
		var pc: Variant = _spawn(Vector3(8, 0, 0), {}, "police_cruiser")
		await _frames(10)
		pc.set_siren(true)
		TestHarness.check(pc.siren_on, "police cruiser siren switches on")
		var saw_red := false
		var saw_blue := false
		var omni := false
		for i in 60:
			await get_tree().physics_frame
			if pc.lights.siren_red_mat != null and pc.lights.siren_red_mat.emission_energy_multiplier > 1.0:
				saw_red = true
			if pc.lights.siren_blue_mat != null and pc.lights.siren_blue_mat.emission_energy_multiplier > 1.0:
				saw_blue = true
			for c: Node in mgr.get_children():
				if c is OmniLight3D and (c as OmniLight3D).visible:
					omni = true
		TestHarness.check(saw_red and saw_blue, "siren light bar alternates red / blue emissive")
		TestHarness.check(omni, "pooled siren OmniLight flashes for the nearest emergency vehicle")
		TestHarness.check(ev["noises"].has("siren"), "siren emits noise events")
		mgr.despawn_vehicle(pc)
	else:
		TestHarness.log_line("police_cruiser GLB not present yet - siren light bar not exercised")
	await _frames(2)
	# taxi roof sign (TaxiSign part, P_NeonYellow): lit while for hire, off with a fare / off duty
	if mgr.can_spawn("taxi"):
		var tx: Variant = _spawn(Vector3(8, 0, 0), {}, "taxi")
		_look_at_car(tx)
		await _frames(10)
		await get_tree().process_frame
		var tl: Variant = tx.lights
		if TestHarness.check(tl.taxi_mat != null, "taxi: TaxiSign neon is a per-instance material"):
			TestHarness.check(tl.taxi_mat != tx.get_original_material("P_NeonYellow"), "taxi sign material is not the shared palette one")
			TestHarness.check(tl.taxi_mat.emission_energy_multiplier > 1.0, "taxi sign lit on the rank (owner '%s', %.1f)" % [tx.owner_tag, tl.taxi_mat.emission_energy_multiplier])
			var fare := Node3D.new()
			fare.set_script(_script(OCCUPANT_SRC))
			add_child(fare)
			tx.occupant_enter(fare, 1)
			await _frames(4)
			await get_tree().process_frame
			TestHarness.check(tx.has_fare() and is_zero_approx(tl.taxi_mat.emission_energy_multiplier), "taxi sign goes dark with a fare in the back")
			tx.occupant_exit(1)
			await _frames(4)
			await get_tree().process_frame
			TestHarness.check(tl.taxi_mat.emission_energy_multiplier > 1.0, "taxi sign lights again when the fare gets out")
			tx.set_taxi_sign(false)
			await _frames(4)
			await get_tree().process_frame
			TestHarness.check(is_zero_approx(tl.taxi_mat.emission_energy_multiplier), "set_taxi_sign(false) = off duty")
			fare.queue_free()
		mgr.despawn_vehicle(tx)
		await _frames(2)
	else:
		TestHarness.log_line("taxi GLB not present - roof sign not exercised")


# ---------------------------------------------------------------------------------------------
func _test_lids() -> void:
	var v: Variant = _spawn(Vector3(0, 0, 0))
	_look_at_car(v)
	await _frames(20)
	for which: String in ["hood", "trunk"]:
		if not v.has_lid(which):
			TestHarness.log_line("%s has no %s part" % [car_id, which])
			continue
		var part: Node3D = v.get_part("Hood" if which == "hood" else "Trunk")
		var rest: Transform3D = part.transform
		v.set_lid_open(which, 1.0)
		await _frames(50)
		var tip0: Vector3 = v.aabb_in_body(part).end
		TestHarness.check(not part.transform.is_equal_approx(rest) and tip0.y > v.body_aabb.position.y + v.body_aabb.size.y * 0.75,
				"set_lid_open('%s') swings the lid up on its hinge (top at %.2f m)" % [which, tip0.y])
		v.set_lid_open(which, 0.0)
		await _frames(50)
		TestHarness.check(part.transform.is_equal_approx(rest), "%s closes back to its authored pose" % which)
	# mod parts that sit on a lid ride with it
	if v.has_lid("hood") and v.has_part("Mod_Hood_A"):
		TestHarness.check(v.get_part("Mod_Hood_A").get_parent() == v.get_part("Hood"), "Mod_Hood_A is attached to the hood")
	if v.has_lid("trunk") and v.has_part("Mod_Spoiler_B"):
		var on_trunk: bool = v.get_part("Mod_Spoiler_B").get_parent() == v.get_part("Trunk")
		TestHarness.log_line("Mod_Spoiler_B rides on the trunk lid: %s" % str(on_trunk))
	mgr.despawn_vehicle(v)
	await _frames(2)
	# pickup: the bottom-hinged Tailgate serves as its "trunk" lid and folds down flat
	if mgr.can_spawn("pickup"):
		var pk: Variant = _spawn(Vector3(20, 0, 0), {}, "pickup")
		await _frames(20)
		var tg: Node3D = pk.get_part("Tailgate")
		if TestHarness.check(tg != null and pk.has_lid("trunk"), "pickup: Tailgate is driven as the trunk lid"):
			var tg_rest: Transform3D = tg.transform
			var a0: AABB = pk.aabb_in_body(tg)
			pk.set_lid_open("trunk", 1.0)
			await _frames(50)
			var a1: AABB = pk.aabb_in_body(tg)
			TestHarness.check(a1.end.y < a0.end.y - 0.25 and a1.end.z > a0.end.z + 0.25,
					"tailgate folds down and back (top %.2f -> %.2f m, rear %.2f -> %.2f m)" % [a0.end.y, a1.end.y, a0.end.z, a1.end.z])
			pk.set_lid_open("trunk", 0.0)
			await _frames(50)
			TestHarness.check(tg.transform.is_equal_approx(tg_rest), "tailgate closes back to its authored pose")
		mgr.despawn_vehicle(pk)
		await _frames(2)
	# convertible roof (only cars with a Roof_Convertible part, e.g. the sports car)
	var roof_id := ""
	for id: String in Bed.ids_with_models():
		var probe: Variant = Game.spawn_vehicle(id, Transform3D(Basis.IDENTITY, Vector3(40.0, 0.0, 0.0)), {"roof_open": false})
		if probe == null:
			continue
		if probe.has_convertible_roof():
			roof_id = id
			var roof: Node3D = probe.get_part("Roof_Convertible")
			var closed: Transform3D = roof.transform
			TestHarness.check(not probe.is_roof_open(), "%s spawns with the roof closed when asked" % id)
			probe.toggle_roof()
			await _frames(100)
			TestHarness.check(probe.is_roof_open() and not roof.transform.is_equal_approx(closed), "%s convertible roof folds away" % id)
			var saved: Dictionary = probe.get_save_data()
			TestHarness.check(bool(saved.get("roof_open", false)), "roof state is part of the save data")
			probe.set_roof_open(false)
			await _frames(100)
			TestHarness.check(roof.transform.is_equal_approx(closed), "%s roof closes again" % id)
		mgr.despawn_vehicle(probe)
		await _frames(2)
		if roof_id != "":
			break
	if roof_id == "":
		TestHarness.log_line("no GLB with a Roof_Convertible part yet - convertible roof not exercised")


# ---------------------------------------------------------------------------------------------
func _test_paint() -> void:
	var a: Variant = _spawn(Vector3(0, 0, 0), {"color": Color(0.1, 0.8, 0.2)})
	var b: Variant = _spawn(Vector3(6, 0, 0), {"color": Color(0.1, 0.2, 0.9)})
	await _frames(5)
	var ma := a.get_instance_material("M_Paint_Primary") as BaseMaterial3D
	var mb := b.get_instance_material("M_Paint_Primary") as BaseMaterial3D
	TestHarness.check(ma != null and ma.albedo_color.is_equal_approx(Color(0.1, 0.8, 0.2)), "spawn opts colour applied to M_Paint_Primary")
	TestHarness.check(ma != mb and mb.albedo_color.is_equal_approx(Color(0.1, 0.2, 0.9)), "paint is per instance (two cars, two colours)")
	a.set_paint(Color(0.9, 0.1, 0.1), Color(0.05, 0.05, 0.05))
	TestHarness.check(ma.albedo_color.is_equal_approx(Color(0.9, 0.1, 0.1)) and a.paint_primary.is_equal_approx(Color(0.9, 0.1, 0.1)), "set_paint() recolours")
	# only paint surfaces may be overridden by the paint material
	var body := a.get_part("Body") as MeshInstance3D
	var ok := true
	var painted := 0
	for s in body.mesh.get_surface_count():
		var nm := body.mesh.surface_get_material(s).resource_name
		var ov := body.get_surface_override_material(s)
		if nm == "M_Paint_Primary":
			painted += 1
			if ov != ma:
				ok = false
		elif ov == ma:
			ok = false
	TestHarness.check(ok and painted >= 1, "paint override sits only on the M_Paint_Primary surface(s)")
	var c: Variant = _spawn(Vector3(12, 0, 0))
	var spec: VehicleSpec = c.spec
	var found := spec.fixed_livery or spec.default_colors.is_empty()
	for col: Color in spec.default_colors:
		if col.is_equal_approx(c.paint_primary):
			found = true
	TestHarness.check(found, "civilian spawn picks a default colour from the spec")
	for v: Variant in [a, b, c]:
		mgr.despawn_vehicle(v)
	await _frames(2)


# ---------------------------------------------------------------------------------------------
func _time_to_speed(v: Variant, target: float) -> float:
	v.release_inputs()
	v.teleport(Transform3D(Basis.IDENTITY, Vector3(v.global_position.x, 0.02, 0.0)))
	await _frames(40)
	v.set_inputs(1.0, 0.0, 0.0)
	var t := 0.0
	for f in 900:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if v.get_forward_speed() >= target:
			break
	return t


func _brake_distance(v: Variant, from_speed: float) -> float:
	v.release_inputs()
	v.teleport(Transform3D(Basis.IDENTITY, Vector3(v.global_position.x, 0.02, 0.0)))
	await _frames(40)
	v.set_inputs(1.0, 0.0, 0.0)
	for f in 1200:
		await get_tree().physics_frame
		if v.get_forward_speed() >= from_speed:
			break
	var p0: Vector3 = v.global_position
	v.set_inputs(0.0, 0.0, 1.0)
	for f in 900:
		await get_tree().physics_frame
		if v.get_forward_speed() < 0.2:
			break
	var d: float = v.global_position.distance_to(p0)
	v.set_inputs(0.0, 0.0, 0.0)
	return d


func _test_mods() -> void:
	var v: Variant = _spawn(Vector3(0, 0, 0))
	_look_at_car(v)
	await _frames(30)
	var opts: Dictionary = v.get_mod_options()
	TestHarness.check(opts.has("engine") and (opts["engine"] as Array).size() == 4, "get_mod_options(): 4 engine levels")
	for slot: String in ["brakes", "suspension", "transmission", "turbo", "armor", "tires", "paint_finish", "horn"]:
		TestHarness.check(opts.has(slot) and (opts[slot] as Array).size() >= 3, "mod slot '%s' offered (%d options)" % [slot, (opts.get(slot, []) as Array).size()])
	print("VEH_MODS: options for %s = %s" % [car_id, str(opts)])
	var t_stock: float = await _time_to_speed(v, 22.0)
	var d_stock: float = await _brake_distance(v, 26.0)
	var before := int(ev["modified"])
	v.apply_mods({"engine": "engine_4", "turbo": "turbo_3", "transmission": "transmission_3", "bogus": "nope", "brakes": "engine_1"})
	TestHarness.check(v.mods.size() == 3 and not v.mods.has("bogus") and not v.mods.has("brakes"), "apply_mods() drops unknown / mismatched entries")
	TestHarness.check(int(ev["modified"]) == before + 1, "EventBus.vehicle_modified emitted")
	var t_mod: float = await _time_to_speed(v, 22.0)
	TestHarness.check(t_mod < t_stock * 0.9, "engine + turbo + transmission mods accelerate measurably faster (0-79 km/h %.2f s -> %.2f s)" % [t_stock, t_mod])
	v.apply_mods({"brakes": "brakes_3"})
	var d_mod: float = await _brake_distance(v, 26.0)
	TestHarness.check(d_mod < d_stock * 0.95, "brake mod shortens the stopping distance (%.1f m -> %.1f m from 94 km/h)" % [d_stock, d_mod])
	v.release_inputs()
	v.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.02, 0.0)))
	_look_at_car(v)
	await _frames(60)
	var y_stock: float = v.global_position.y
	v.apply_mods({"suspension": "suspension_4"})
	await _frames(120)
	TestHarness.check(v.global_position.y < y_stock - 0.03, "suspension mod lowers the ride height (%.3f -> %.3f m)" % [y_stock, v.global_position.y])
	# visual parts
	if opts.has("spoiler"):
		var ids: Array = opts["spoiler"]
		v.apply_mods({"spoiler": ids[ids.size() - 1]})
		var node_name := str(Registry.get_def("vehicle_mods", str(ids[ids.size() - 1]))["node"])
		TestHarness.check(v.get_part(node_name).visible, "spoiler mod shows %s" % node_name)
		var others_hidden := true
		for part_name: String in v._nodes:
			if part_name.begins_with("Mod_") and part_name != node_name and v.get_part(part_name).visible:
				others_hidden = false
		TestHarness.check(others_hidden, "other Mod_* parts stay hidden")
		v.apply_mods({})
		TestHarness.check(not v.get_part(node_name).visible, "removing the mod hides the part again")
	else:
		TestHarness.log_line("%s has no spoiler parts" % car_id)
	v.apply_mods({"paint_finish": "finish_matte", "tint": "tint_limo", "wheel_color": "wheelcol_gold", "armor": "armor_4", "tires": "tires_3"})
	var pm := v.get_instance_material("M_Paint_Primary") as BaseMaterial3D
	TestHarness.check(pm.roughness > 0.85, "matte finish changes the paint roughness (%.2f)" % pm.roughness)
	if v.has_material("M_Glass"):
		var gm := v.get_instance_material("M_Glass") as BaseMaterial3D
		var go := v.get_original_material("M_Glass") as BaseMaterial3D
		TestHarness.check(gm.albedo_color.a > go.albedo_color.a + 0.2, "window tint darkens the glass (alpha %.2f -> %.2f)" % [go.albedo_color.a, gm.albedo_color.a])
	if v.has_material("M_Rim"):
		var rm := v.get_instance_material("M_Rim") as BaseMaterial3D
		TestHarness.check(rm.albedo_color.is_equal_approx(Color("#D9B34A")), "wheel colour mod recolours the rims")
	if opts.has("lights"):
		var warm: Color = v.lights.head_color
		v.apply_mods({"lights": "lights_ice"})
		var cold: Color = v.lights.head_color
		TestHarness.check(cold.b > cold.r + 0.2 and not cold.is_equal_approx(warm) and v.lights.head_mat.emission.is_equal_approx(cold),
				"headlight mod recolours lamp emission and the pooled light colour (%s -> %s)" % [str(warm), str(cold)])
		v.apply_mods({})
		TestHarness.check(v.lights.head_color.is_equal_approx(warm), "removing the headlight mod restores the stock colour")
		v.apply_mods({"paint_finish": "finish_matte", "tint": "tint_limo", "wheel_color": "wheelcol_gold", "armor": "armor_4", "tires": "tires_3"})
	var h0: float = v.health
	v.apply_damage(Dmg.make(100.0, "bullet", null, v.global_position + Vector3(0, 0.6, 2.2)))
	TestHarness.check(absf((h0 - v.health) - 100.0 * 0.35 * 0.4) < 0.5, "armor mod reduces damage taken (lost %.1f of a 100 hp bullet hit)" % (h0 - v.health))
	v.apply_damage(Dmg.make(10.0, "bullet", null, v.get_wheel_position(0)))
	TestHarness.check(not v.is_tire_flat(0), "bullet-resistant tyres cannot be shot out")
	if opts.has("wheels"):
		var wid := str((opts["wheels"] as Array)[0])
		v.apply_mods({"wheels": wid})
		var wn: Node3D = v.get_wheel_node(0)
		TestHarness.check(wn.get_node_or_null("ModWheel") != null, "wheel mod '%s' swaps in the shared wheel model" % wid)
		v.apply_mods({})
		await _frames(2)
		TestHarness.check(wn.get_node_or_null("ModWheel") == null, "stock wheels restored")
	else:
		TestHarness.log_line("shared wheel GLBs (models/vehicles/parts) not present yet - wheel swap not exercised")
	TestHarness.check(VehicleMods.price_of({"engine": "engine_4", "brakes": "brakes_3"}) == 15000 + 5200, "VehicleMods.price_of() sums prices")
	mgr.despawn_vehicle(v)
	await _frames(2)


# ---------------------------------------------------------------------------------------------
func _test_damage() -> void:
	var v: Variant = _spawn(Vector3(0, 0, 0))
	_look_at_car(v)
	await _frames(40)
	var h0: float = v.health
	var d0 := int(ev["damaged"])
	v.apply_damage(Dmg.make(100.0, "bullet", null, v.global_position + Vector3(0, 0.5, 2.25)))
	TestHarness.check(absf((h0 - v.health) - 35.0) < 0.5, "bullets do reduced damage (100 -> %.1f)" % (h0 - v.health))
	TestHarness.check(int(ev["damaged"]) == d0 + 1, "EventBus.vehicle_damaged emitted")
	if v.has_part("Glass_Windshield"):
		var pane: Node3D = v.get_part("Glass_Windshield")
		var gp: Vector3 = v.global_transform * v.aabb_in_body(pane).get_center()
		v.apply_damage(Dmg.make(20.0, "bullet", null, gp))
		TestHarness.check(not pane.visible and v.damage.get_broken_glass_count() == 1, "a bullet breaks exactly the pane it hits")
	v.apply_damage(Dmg.make(20.0, "bullet", null, v.get_wheel_position(1)))
	TestHarness.check(v.is_tire_flat(1) and not v.is_tire_flat(0), "a bullet pops the tyre it hits")
	v.repair()
	TestHarness.check(is_equal_approx(v.health, v.max_health) and not v.is_tire_flat(1) and v.damage.get_broken_glass_count() == 0, "repair() restores health, tyres and glass")
	# gameplay timers run on simulated time, never on the wall clock (headless runs are faster than real time)
	var clock0: int = VehicleBase.now_msec()
	await _frames(60)
	var clock_dt: int = VehicleBase.now_msec() - clock0
	TestHarness.check(clock_dt >= 950 and clock_dt <= 1050, "vehicle clock advances with simulated time (60 physics frames = %d ms)" % clock_dt)

	# collision damage: drive into a wall at speed
	var wall := Bed.add_static_box(self, Vector3(14.0, 3.0, 1.0), Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, -70.0)), Color.DIM_GRAY, "concrete")
	var c0 := int(ev["collisions"])
	v.set_inputs(1.0, 0.0, 0.0)
	var v_hit := 0.0
	for f in 600:
		await get_tree().physics_frame
		if v.global_position.z > -66.0 + 0.0 and v.linear_velocity.length() > v_hit and int(ev["collisions"]) == c0:
			v_hit = v.linear_velocity.length()
		if int(ev["collisions"]) > c0:
			break
	v.set_inputs(0.0, 0.0, 1.0)
	await _frames(30)
	TestHarness.check(int(ev["collisions"]) > c0 and float(ev["max_impulse"]) > 1000.0, "EventBus.vehicle_collision on impact (impulse %.0f N s at %.1f m/s)" % [float(ev["max_impulse"]), v_hit])
	TestHarness.check(v.health < v.max_health - 40.0, "collision damage scales with the impact (health %.0f / %.0f)" % [v.health, v.max_health])
	TestHarness.check(ev["noises"].has("crash"), "crash emits a noise event")
	if v.has_lid("hood"):
		TestHarness.check(v.get_lid_open("hood") > 0.1, "a heavy frontal crash springs the hood ajar (%.2f)" % v.get_lid_open("hood"))
	wall.queue_free()
	v.set_inputs(0.0, 0.0, 0.0)
	v.repair()
	v.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.02, 0.0)))
	_look_at_car(v)
	await _frames(30)

	# smoke -> fire -> explosion
	var occ: Node3D = _script(OCCUPANT_SRC).new()
	add_child(occ)
	v.occupant_enter(occ, 0)
	v.apply_damage(Dmg.make(v.max_health * 0.6, "collision", null, v.global_position))
	await _frames(10)
	TestHarness.check(v.damage.smoking and not v.damage.burning, "below 45 %% health the engine smokes (%.0f %%)" % (v.get_health_ratio() * 100.0))
	if Fx.has_method("attach_smoke"):
		TestHarness.check(v.damage.smoke_node != null and is_instance_valid(v.damage.smoke_node) and v.damage.smoke_node.get_parent() == v,
				"engine smoke is one looping Fx emitter attached to the vehicle (%s)" % str(v.damage._smoke_kind))
	TestHarness.check(v.get_power_factor() < 0.95 and absf(v.damage.steer_pull) > 0.0, "damaged handling: power %.2f, steering pull %.3f" % [v.get_power_factor(), v.damage.steer_pull])
	v.apply_damage(Dmg.make(v.max_health * 0.28, "collision", null, v.global_position))
	await _frames(10)
	TestHarness.check(v.damage.burning and v.on_fire and not v.destroyed, "below 15 %% health the vehicle catches fire (fuse %.1f s)" % v.damage.fuse)
	var x0 := int(ev["explosions"])
	var k0 := int(ev["destroyed"])
	var waited := 0
	while not v.destroyed and waited < 600:
		await get_tree().physics_frame
		waited += 1
	TestHarness.check(v.destroyed, "the burning vehicle explodes after %.1f s" % (float(waited) / 60.0))
	TestHarness.check(int(ev["explosions"]) == x0 + 1 and int(ev["destroyed"]) == k0 + 1, "Fx.explosion + EventBus.vehicle_destroyed fired once")
	TestHarness.check(float(occ.damage_taken) >= 500.0 and str(occ.last_type) == "explosion" and bool(occ.ejected), "occupant takes lethal blast damage and is ejected")
	TestHarness.check(v.get_occupants().is_empty() and not v.engine_on and not v.can_enter(occ), "wreck: no occupants, engine dead, cannot be entered")
	var body := v.get_part("Body") as MeshInstance3D
	var burnt := body.get_surface_override_material(0)
	TestHarness.check(burnt != null and burnt.resource_name == "Burnt", "burnt look applied to the wreck")
	v.set_inputs(1.0, 0.0, 0.0)
	await _frames(int(9.0 * 60.0))
	TestHarness.check(v.freeze, "wreck is frozen after it settled")
	TestHarness.check(get_tree().get_nodes_in_group("vehicle_debris").size() <= 12, "debris is bounded (%d pieces live)" % get_tree().get_nodes_in_group("vehicle_debris").size())
	# wreck removal by the manager (far from the camera, short lifetime for the test)
	var keep_life: float = mgr.wreck_lifetime
	mgr.wreck_lifetime = 1.0
	cam.global_position = v.global_position + Vector3(0.0, 5.0, 90.0)
	var gone := false
	for f in 240:
		await get_tree().physics_frame
		if not is_instance_valid(v):
			gone = true
			break
	mgr.wreck_lifetime = keep_life
	TestHarness.check(gone, "VehicleManager removes old wrecks")
	occ.queue_free()

	# explode() API + repair of a wreck
	var w: Variant = _spawn(Vector3(20, 0, 0))
	_look_at_car(w)
	await _frames(20)
	w.explode(null)
	TestHarness.check(w.destroyed and is_zero_approx(w.health), "explode() destroys immediately")
	await _frames(30)
	w.repair()
	await _frames(5)
	TestHarness.check(not w.destroyed and is_equal_approx(w.health, w.max_health) and not w.freeze, "repair() revives a wreck (admin / garage)")
	var body2 := w.get_part("Body") as MeshInstance3D
	var ov := body2.get_surface_override_material(0)
	TestHarness.check(ov == null or ov.resource_name != "Burnt", "burnt look removed by repair()")
	mgr.despawn_vehicle(w)
	await _frames(2)


# ---------------------------------------------------------------------------------------------
func _test_pop_tire() -> void:
	var a: Variant = _spawn(Vector3(-20, 0, 0))
	var b: Variant = _spawn(Vector3(20, 0, 0))
	_look_at_car(a)
	await _frames(40)
	b.pop_tire(0)       # front left
	TestHarness.check(b.is_tire_flat(0), "pop_tire(0) flattens the front-left tyre")
	a.set_inputs(0.7, 0.0, 0.0)
	b.set_inputs(0.7, 0.0, 0.0)
	await _frames(int(4.5 * 60.0))
	var dev_a: float = a.global_position.x - (-20.0)
	var dev_b: float = b.global_position.x - 20.0
	TestHarness.check(absf(dev_a) < 0.4, "healthy car tracks straight (%.2f m)" % dev_a)
	TestHarness.check(dev_b < -0.5, "flat front-left tyre pulls the car to the left (%.2f m)" % dev_b)
	# grip: full-lock turn radius / lateral acceleration is lower with the flat
	a.set_inputs(0.0, 0.0, 1.0)
	b.set_inputs(0.0, 0.0, 1.0)
	await _frames(240)
	mgr.despawn_vehicle(a)
	mgr.despawn_vehicle(b)
	await _frames(2)


# ---------------------------------------------------------------------------------------------
func _test_self_right() -> void:
	var v: Variant = _spawn(Vector3(0, 0, 0))
	_look_at_car(v)
	await _frames(30)
	v.teleport(Transform3D(Basis(Vector3.FORWARD, PI), Vector3(0.0, 1.8, 0.0)))
	await _frames(90)
	TestHarness.check(v.global_transform.basis.y.y < -0.5, "test setup: car lies on its roof (up.y %.2f)" % v.global_transform.basis.y.y)
	await _frames(int(6.5 * 60.0))
	TestHarness.check(v.global_transform.basis.y.y > 0.95, "car self-rights after ~3 s on its roof (up.y %.2f)" % v.global_transform.basis.y.y)
	TestHarness.check(v.global_position.y < 0.3 and v.global_position.y > -0.1, "... and stands on its wheels (y %.2f)" % v.global_position.y)
	mgr.despawn_vehicle(v)
	await _frames(2)


# ---------------------------------------------------------------------------------------------
## TEST ONLY stand-in for the World system's is_water_at(): the strip x < -100 m of the proving
## ground counts as deep sea. In the game the real World answers this query.
class WaterWorldStub extends Node3D:
	func is_water_at(pos: Vector3) -> bool:
		return pos.x < -100.0


func _test_water_stall() -> void:
	if Game.world != null:
		print("VEH_SYSTEMS: a real world is loaded - water stall test skipped")
		return
	var stub := WaterWorldStub.new()
	stub.name = "WaterWorldStub"
	add_child(stub)
	Game.world = stub
	var dry: Variant = _spawn(Vector3(-80, 0, 0))
	var wet: Variant = _spawn(Vector3(-110, 0, 0))
	_look_at_car(wet)
	await _frames(20)
	dry.set_inputs(0.3, 0.0, 0.0)
	wet.set_inputs(0.3, 0.0, 0.0)
	await _frames(40)
	TestHarness.check(dry.engine_on and not dry.stalled and not dry.in_water, "dry car: the engine keeps running")
	TestHarness.check(wet.in_water and wet.stalled and not wet.engine_on, "a car in deep water stalls (engine off)")
	TestHarness.check(not wet.start_engine(), "a flooded engine cannot be restarted")
	TestHarness.check(not wet.can_enter(null), "a flooded car cannot be entered")
	var v0: float = absf(wet.get_forward_speed())
	wet.set_inputs(1.0, 0.0, 0.0)
	await _frames(60)
	var v1: float = absf(wet.get_forward_speed())
	TestHarness.check(v1 <= v0 + 0.05, "full throttle does not move a flooded car (%.2f -> %.2f m/s)" % [v0, v1])
	Game.world = null
	wet.release_inputs()
	await _frames(30)
	wet.repair()
	TestHarness.check(not wet.stalled and wet.start_engine(), "out of the water, repair() clears the flooded engine")
	mgr.despawn_vehicle(dry)
	mgr.despawn_vehicle(wet)
	stub.queue_free()
	await _frames(2)


# ---------------------------------------------------------------------------------------------
func _make_ped(pos: Vector3) -> CharacterBody3D:
	var ped: CharacterBody3D = _script(PED_SRC).new()
	ped.collision_layer = Layers.NPC
	ped.collision_mask = 0
	ped.add_to_group("npc")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0.0, 0.9, 0.0)
	ped.add_child(cs)
	add_child(ped)
	ped.global_position = pos
	return ped


func _test_ped_strike() -> void:
	# AI-driven car: damage + knock-down, no crime
	var v: Variant = _spawn(Vector3(0, 0, 0))
	_look_at_car(v)
	await _frames(30)
	var ped := _make_ped(Vector3(0.0, 0.0, -45.0))
	var crimes0 := (ev["crimes"] as Array).size()
	v.set_inputs(1.0, 0.0, 0.0)
	var v_before := 0.0
	for f in 420:
		await get_tree().physics_frame
		if v.global_position.z > -42.0:
			v_before = v.linear_velocity.length()
		if v.global_position.z < -52.0:
			break
	var v_after: float = v.linear_velocity.length()
	TestHarness.check(float(ped.damage_taken) > 20.0 and str(ped.last_type) == "vehicle", "running a pedestrian over deals 'vehicle' damage (%.0f at %.1f m/s)" % [float(ped.damage_taken), v_before])
	TestHarness.check(bool(ped.knocked), "... and knocks the pedestrian down")
	TestHarness.check(v_after > v_before * 0.8, "the car is not stopped dead by the character body (%.1f -> %.1f m/s)" % [v_before, v_after])
	TestHarness.check((ev["crimes"] as Array).size() == crimes0, "an AI driver's accident is not reported as a player crime")
	ped.queue_free()
	v.set_inputs(0.0, 0.0, 1.0)
	await _frames(120)
	# player-driven: hit_and_run reported once through VehicleCrime
	v.release_inputs()
	v.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.02, 0.0)))
	var p: Node3D = _script(OCCUPANT_SRC).new()
	p.add_to_group("player")
	add_child(p)
	v.occupant_enter(p, 0)
	var ped2 := _make_ped(Vector3(0.0, 0.0, -45.0))
	Input.action_press("move_forward")
	for f in 420:
		await get_tree().physics_frame
		if v.global_position.z < -52.0:
			break
	Input.action_release("move_forward")
	TestHarness.check((ev["crimes"] as Array).has("hit_and_run"), "player-driven hit reports 'hit_and_run' to Wanted (crimes: %s)" % str(ev["crimes"]))
	# major collision with an occupied vehicle
	var target: Variant = _spawn(Vector3(0.0, 0.0, v.global_position.z - 60.0))
	var occ: Node3D = _script(OCCUPANT_SRC).new()
	add_child(occ)
	target.occupant_enter(occ, 0)
	target.set_inputs(0.0, 0.0, 1.0)
	Input.action_press("move_forward")
	var c0 := int(ev["collisions"])
	for f in 600:
		await get_tree().physics_frame
		if int(ev["collisions"]) > c0:
			break
	Input.action_release("move_forward")
	await _frames(20)
	TestHarness.check((ev["crimes"] as Array).has("collision_major"), "ramming an occupied vehicle reports 'collision_major' (crimes: %s)" % str(ev["crimes"]))
	v.occupant_exit(0)
	p.remove_from_group("player")
	p.queue_free()
	ped2.queue_free()
	occ.queue_free()
	mgr.despawn_vehicle(target)
	mgr.despawn_vehicle(v)
	await _frames(2)


# ---------------------------------------------------------------------------------------------
func _test_save() -> void:
	var v: Variant = _spawn(Vector3(30.0, 0.0, 10.0), {"color": Color(0.2, 0.6, 0.9), "personal": true})
	await _frames(20)
	v.apply_mods({"engine": "engine_2", "paint_finish": "finish_metallic"})
	TestHarness.check(mgr.get_personal_vehicle() == v and v.personal, "personal vehicle registered")
	var data: Dictionary = mgr.get_save_data()
	var json := JSON.stringify(data)
	var back: Variant = JSON.parse_string(json)
	TestHarness.check(back is Dictionary and (back as Dictionary).has("personal"), "manager save data is JSON-safe (%d bytes)" % json.length())
	mgr.despawn_vehicle(v)
	await _frames(3)
	TestHarness.check(mgr.get_personal_vehicle() == null, "personal vehicle cleared on despawn")
	mgr.load_save_data(back)
	await _frames(5)
	var r: Variant = mgr.get_personal_vehicle()
	TestHarness.check(r != null, "load_save_data() respawns the personal vehicle")
	if r != null:
		TestHarness.check(r.spec_id == car_id and r.paint_primary.is_equal_approx(Color(0.2, 0.6, 0.9)), "... same spec and paint")
		TestHarness.check(str(r.mods.get("engine", "")) == "engine_2" and r.paint_finish == "metallic", "... same mods")
		TestHarness.check(r.global_position.distance_to(Vector3(30.0, 0.0, 10.0)) < 0.5, "... same place")
		mgr.despawn_vehicle(r)
	await _frames(2)


# ---------------------------------------------------------------------------------------------
func _test_fallback_and_caps() -> void:
	# model without Col_* helpers, seats or markers -> box hull, synthetic seat, still drives
	var bare: Variant = Game.spawn_vehicle(car_id, Transform3D(Basis.IDENTITY, Vector3(-30.0, 0.0, 0.0)), {"model_instance": Bed.make_bare_model()})
	TestHarness.check(bare != null, "builder accepts a model without collision helpers / markers")
	if bare != null:
		_look_at_car(bare)
		await _frames(120)
		TestHarness.check(bare.global_transform.basis.y.y > 0.999 and absf(bare.global_position.y) < 0.05, "fallback-built car rests level at ride height (y %.3f)" % bare.global_position.y)
		TestHarness.check(bare.get_seat_count() == 1 and bare.get_seat_node(0) != null, "synthetic driver seat")
		bare.set_inputs(1.0, 0.0, 0.0)
		await _frames(180)
		TestHarness.check(bare.get_forward_speed() > 8.0, "fallback-built car drives (%.1f m/s)" % bare.get_forward_speed())
		mgr.despawn_vehicle(bare)
	await _frames(2)
	# caps
	var keep_max: int = mgr.max_vehicles
	mgr.clear_all(true)
	await _frames(3)
	mgr.max_vehicles = 3
	for i in 6:
		_spawn(Vector3(-40.0 + float(i) * 8.0, 0.0, 40.0), {"asleep": true})
	await _frames(5)
	TestHarness.check(mgr.get_vehicle_count() <= 3, "vehicle cap enforced (%d / 3)" % mgr.get_vehicle_count())
	var parked: Variant = mgr.get_vehicles()[0]
	TestHarness.check(parked.owner_tag == "parked", "asleep spawn is tagged 'parked'")
	await _frames(60)
	TestHarness.check(parked.sleeping and absf(parked.global_position.y) < 0.05, "parked car sleeps at ride height (y %.3f)" % parked.global_position.y)
	mgr.max_vehicles = keep_max
	mgr.clear_all(true)
	await _frames(3)
	TestHarness.check(mgr.get_vehicle_count() == 0, "clear_all() removes everything")
	var info: Dictionary = mgr.get_debug_info()
	TestHarness.check(info.has("count") and info.has("awake"), "debug info available")
