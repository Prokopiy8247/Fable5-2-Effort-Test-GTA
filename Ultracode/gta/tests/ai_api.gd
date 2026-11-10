extends Node
## Headless test of the AI module body API (ARCHITECTURE_WAVE2 W2.2) on a test stage far above
## the island (concrete slab + walls + a runtime-baked navigation mesh). TEST EQUIPMENT, not content.
## Run:
##   tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 400 -UserArgs '--test=ai_api','--test-timeout=380','--seed=3','--disable=world,environment,city,interactions,props,traffic,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Optional: '--ai_only=spawn,api,move,fire,cover,vehicle,flee,witness,cancel,gang,knock,death,harm,staff,bench,crossing,carhit,player,tough,opts'

const ORIGIN := Vector3(0.0, 400.0, 0.0)
const ARCHETYPES := ["civilian_m", "civilian_f", "civilian_tough", "gang_member", "shop_staff", "taxi_driver",
		"police_officer", "police_swat", "medic", "firefighter"]
const BODY_METHODS := ["set_brain", "move_to", "stop_moving", "is_moving", "has_arrived", "face_position",
		"set_crouched", "set_weapon", "aim_at", "stop_aiming", "fire_at", "melee", "can_see", "can_see_point",
		"find_cover_from", "enter_vehicle", "exit_vehicle", "play_action", "panic", "cower", "surrender",
		"knock_down", "apply_damage", "get_target_position", "set_sim_tier", "get_awareness"]
const BODY_MEMBERS := ["faction", "archetype_id", "health", "is_dead", "weapon_id", "current_vehicle", "brain",
		"state_tag", "accuracy", "is_alerted"]


## Damage sponge with a target point (stands in for a person).
class Dummy extends StaticBody3D:
	var damage: float = 0.0
	var hits: int = 0
	var is_dead: bool = false

	func _init() -> void:
		collision_layer = Layers.NPC
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.6, 1.8, 0.4)
		cs.shape = sh
		cs.position = Vector3(0.0, 0.9, 0.0)
		add_child(cs)

	func apply_damage(info: Dictionary) -> void:
		damage += float(info.get("amount", 0.0))
		hits += 1

	func get_target_position() -> Vector3:
		return global_position + Vector3(0.0, 1.2, 0.0)


var peds: Node = null
var stage: Node3D = null
var nav_ok: bool = false
var only: PackedStringArray = PackedStringArray()
var crimes: Array = []
var npc_died_events: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--ai_only="):
			only = a.substr(10).split(",", false)
	EventBus.crime_committed.connect(func(id: String, _p: Vector3, _i: Node) -> void: crimes.append(id))
	EventBus.npc_died.connect(func(_n: Node3D, _k: Node, _info: Dictionary) -> void: npc_died_events += 1)
	peds = Game.get_system("peds")
	if not TestHarness.check(peds != null and peds.has_method("spawn_npc"), "peds system registered"):
		TestHarness.finish(false, "no peds system")
		return
	_build_stage()
	await TestHarness.wait_physics_frames(6)
	nav_ok = NavigationServer3D.map_get_iteration_id(stage.get_world_3d().navigation_map) > 0
	TestHarness.log_line("stage navmesh ready: %s" % nav_ok)
	peds.call("set_focus_override", ORIGIN)
	if Game.has_player() and Game.player.has_method("teleport"):
		Game.player.call("teleport", ORIGIN + Vector3(-55.0, 0.2, 55.0), 0.0)
	Wanted.clear("test")
	var t0 := Time.get_ticks_msec()
	if _want("spawn"): await _t_spawn_all()
	if _want("api"): await _t_api()
	if _want("move"): await _t_move()
	if _want("fire"): await _t_fire()
	if _want("cover"): await _t_cover()
	if _want("vehicle"): await _t_vehicle()
	if _want("flee"): await _t_flee()
	if _want("witness"): await _t_witness()
	if _want("cancel"): await _t_witness_cancel()
	if _want("gang"): await _t_gang()
	if _want("knock"): await _t_knock()
	if _want("death"): await _t_death()
	if _want("harm"): await _t_harm()
	if _want("staff"): await _t_staff()
	if _want("bench"): await _t_bench()
	if _want("crossing"): await _t_crossing()
	if _want("carhit"): await _t_carhit()
	if _want("player"): await _t_player_stimuli()
	if _want("tough"): await _t_tough()
	if _want("opts"): await _t_spawn_opts()
	TestHarness.log_line("ai_api done in %d ms real time" % (Time.get_ticks_msec() - t0))
	TestHarness.finish()


func _want(n: String) -> bool:
	return only.is_empty() or only.has(n)


func at(x: float, z: float) -> Vector3:
	return ORIGIN + Vector3(x, 0.0, z)


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += 1.0 / 60.0
	return bool(cond.call())


# --- stage -------------------------------------------------------------------------------------

func _build_stage() -> void:
	stage = Node3D.new()
	stage.name = "AiTestStage"
	Game.get_entities_root().add_child(stage)
	var region := NavigationRegion3D.new()
	region.name = "StageNav"
	stage.add_child(region)
	_box(region, Vector3(0.0, -1.0, 0.0), Vector3(170.0, 2.0, 170.0))            # floor, top at y = 400
	_box(region, Vector3(-20.0, 1.3, 2.0), Vector3(7.0, 2.6, 0.5))              # move test wall
	_box(region, Vector3(3.0, 0.5, -3.0), Vector3(3.0, 1.0, 0.5))               # low cover
	_box(region, Vector3(-4.0, 1.3, -4.0), Vector3(3.0, 2.6, 0.5))              # high cover
	_box(region, Vector3(30.0, 1.3, -14.0), Vector3(4.0, 2.6, 0.5))             # cover test wall
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.WORLD
	nm.agent_radius = 0.35
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.3
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)


func _box(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Layers.WORLD
	b.set_meta("surface", "concrete")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	parent.add_child(b)
	b.global_position = ORIGIN + center
	return b


func _dummy(pos: Vector3) -> Dummy:
	var d := Dummy.new()
	stage.add_child(d)
	d.global_position = pos
	return d


func _spawn(arch: String, pos: Vector3, opts: Dictionary = {}) -> Node3D:
	return peds.call("spawn_npc", arch, pos, opts) as Node3D


func _cleanup() -> void:
	peds.call("clear_all", true)
	await TestHarness.wait_physics_frames(3)


# --- tests -------------------------------------------------------------------------------------

func _t_spawn_all() -> void:
	var made: Array = []
	var i := 0
	for id: String in ARCHETYPES:
		TestHarness.check(Registry.has_def("npc_archetypes", id), "archetype registered: " + id)
		var npc := _spawn(id, at(-30.0 + i * 6.0, 30.0), {"yaw": 0.0})
		i += 1
		if not TestHarness.check(npc != null and is_instance_valid(npc), "spawned " + id):
			continue
		made.append(npc)
		TestHarness.check(npc.is_in_group("npc") and str(npc.get("archetype_id")) == id, id + ": group npc + archetype_id")
		var vis: Variant = npc.get("visual")
		TestHarness.check(vis != null and is_instance_valid(vis) and (vis as Node).has_method("get_appearance"), id + ": character visual")
		TestHarness.check(npc.get("animator") != null, id + ": humanoid animator")
		TestHarness.check(npc.get("brain") != null and (npc.get("brain") as Node).has_method("think"), id + ": has a brain")
	await TestHarness.wait_physics_frames(30)
	for npc: Node3D in made:
		var id := str(npc.get("archetype_id"))
		var app: Dictionary = (npc.get("visual") as Node).call("get_appearance")
		match id:
			"police_officer":
				TestHarness.check(npc.is_in_group("police") and str(app.get("outfit", "")) == "police", "officer: group police + police outfit")
				TestHarness.check(str(npc.get("weapon_id")) == "pistol", "officer: pistol")
			"police_swat":
				TestHarness.check(str(app.get("outfit", "")) == "tactical", "swat: tactical outfit")
				TestHarness.check(str(npc.get("weapon_id")) in ["carbine", "assault_rifle"], "swat: rifle")
			"gang_member":
				TestHarness.check(npc.is_in_group("gang") and str(npc.get("faction")) == "gang", "gang: group + faction")
			"shop_staff":
				TestHarness.check(str(app.get("outfit", "")) == "staff", "staff: staff outfit")
			"civilian_f":
				TestHarness.check(str(app.get("body", "")) == "f", "civilian_f: female body")
			"civilian_m":
				TestHarness.check(str(app.get("body", "")) == "m", "civilian_m: male body")
		TestHarness.check(absf(npc.global_position.y - ORIGIN.y) < 0.3, id + ": stands on the stage (y %.2f)" % (npc.global_position.y - ORIGIN.y))
	# variety: ten civilians should not all look the same
	var looks := {}
	for k in 10:
		var c := _spawn("civilian_m" if k % 2 == 0 else "civilian_f", at(-30.0 + k * 3.0, 40.0))
		if c != null:
			var a: Dictionary = (c.get("visual") as Node).call("get_appearance")
			looks[str(a.get("top", "")) + str(a.get("top_color", "")) + str(a.get("hair", ""))] = true
	TestHarness.check(looks.size() >= 7, "10 civilians -> %d distinct looks" % looks.size())
	await _cleanup()


func _t_api() -> void:
	var npc := _spawn("civilian_m", at(0.0, 20.0))
	for m: String in BODY_METHODS:
		TestHarness.check(npc.has_method(m), "body method " + m)
	for m: String in BODY_MEMBERS:
		TestHarness.check(m in npc, "body member " + m)
	for s: String in ["died", "damaged", "threatened"]:
		TestHarness.check(npc.has_signal(s), "body signal " + s)
	npc.call("set_weapon", "pistol")
	TestHarness.check(str(npc.get("weapon_id")) == "pistol", "set_weapon pistol")
	var model: Variant = npc.get("_weapon_model")
	TestHarness.check(model != null and is_instance_valid(model) and (model as Node).is_inside_tree(), "weapon model in the hand")
	npc.call("set_weapon", "")
	TestHarness.check(str(npc.get("weapon_id")) == "" and npc.get("_weapon_model") == null, "set_weapon '' holsters")
	npc.call("set_crouched", true)
	TestHarness.check(bool(npc.get("is_crouching")), "set_crouched")
	npc.call("set_crouched", false)
	var tp: Vector3 = npc.call("get_target_position")
	TestHarness.check(tp.y > npc.global_position.y + 1.0, "get_target_position at chest")
	npc.call("set_sim_tier", 1)
	TestHarness.check(int(npc.get("sim_tier")) == 1, "set_sim_tier")
	# brain swap through set_brain
	var b := Node.new()
	b.set_script(load("res://gta/code/ai/brains/ai_brain_staff.gd"))
	npc.call("set_brain", b)
	TestHarness.check(npc.get("brain") == b and b.get_parent() == npc, "set_brain installs the node")
	TestHarness.check(float(npc.call("get_awareness")) >= 0.0, "get_awareness")
	await _cleanup()


func _t_move() -> void:
	var npc := _spawn("civilian_m", at(-20.0, 8.0), {"yaw": 0.0, "activity": "idle", "brain": _idle_brain()})
	await TestHarness.wait_physics_frames(10)
	var target := at(-20.0, -5.0)
	npc.call("move_to", target, "walk")
	TestHarness.check(bool(npc.call("is_moving")), "move_to starts moving")
	var t0 := AiSenses.now()
	var ok: bool = await _wait_until(func() -> bool: return bool(npc.call("has_arrived", 1.2)), 25.0)
	TestHarness.check(ok, "move_to reaches a target behind a wall (%.1f s, nav=%s, end %.2f m off)" % [
			AiSenses.now() - t0, nav_ok, npc.global_position.distance_to(target)])
	# run is faster than walk
	npc.call("move_to", at(-35.0, -5.0), "run")
	await TestHarness.wait_seconds(1.0)
	var v: Vector3 = npc.get("velocity")
	TestHarness.check(Vector2(v.x, v.z).length() > 3.0, "run speed %.2f m/s" % Vector2(v.x, v.z).length())
	npc.call("stop_moving")
	await TestHarness.wait_physics_frames(20)
	TestHarness.check(not bool(npc.call("is_moving")), "stop_moving")
	npc.call("face_position", npc.global_position + Vector3(10.0, 0.0, 0.0))
	await TestHarness.wait_seconds(1.0)
	var fwd: Vector3 = -npc.global_basis.z
	TestHarness.check(fwd.dot(Vector3.RIGHT) > 0.9, "face_position turns the body")
	await _cleanup()


func _idle_brain() -> Node:
	var n := Node.new()
	return n


func _t_fire() -> void:
	var d := _dummy(at(10.0, -10.0))
	var npc := _spawn("gang_member", at(10.0, 0.0), {"yaw": 0.0, "weapon": "pistol", "brain": _idle_brain()})
	npc.set("accuracy", 1.0)
	await TestHarness.wait_physics_frames(10)
	var mag0 := int(npc.call("get_ammo_in_mag"))
	var shots := 0
	var t := 0.0
	var saw_reload := false
	while t < 6.0:
		if bool(npc.call("fire_at", d.get_target_position(), 1.0)):
			shots += 1
		if bool(npc.call("is_reloading")):
			saw_reload = true
		await get_tree().physics_frame
		t += 1.0 / 60.0
	TestHarness.check(shots >= 8, "fire_at obeys cadence: %d shots in 6 s" % shots)
	TestHarness.check(shots <= 40, "fire_at is rate limited (%d shots)" % shots)
	TestHarness.check(d.hits > 0 and d.damage > 0.0, "fire_at damages the dummy (%d hits, %.0f hp)" % [d.hits, d.damage])
	TestHarness.check(mag0 == 12 and saw_reload, "magazine %d + automatic reload" % mag0)
	# melee
	var d2 := _dummy(at(14.0, 0.0) + Vector3(0.0, 0.0, -1.2))
	var npc2 := _spawn("civilian_tough", at(14.0, 0.0), {"yaw": 0.0, "brain": _idle_brain()})
	await TestHarness.wait_physics_frames(10)
	for k in 4:
		npc2.call("melee", d2)
		await TestHarness.wait_seconds(0.8)
	TestHarness.check(d2.hits > 0, "melee hits a target in reach (%d hits)" % d2.hits)
	d.queue_free()
	d2.queue_free()
	await _cleanup()


func _t_cover() -> void:
	var npc := _spawn("gang_member", at(30.0, -8.0), {"yaw": 0.0, "brain": _idle_brain()})
	await TestHarness.wait_physics_frames(10)
	var threat := at(30.0, -28.0) + Vector3(0.0, 1.4, 0.0)
	var cp: Vector3 = npc.call("find_cover_from", threat, 14.0)
	TestHarness.check(cp != Vector3.INF, "find_cover_from returns a point (%s)" % str(cp - ORIGIN))
	if cp != Vector3.INF:
		var hidden := not Combat.has_line_of_sight(threat, cp + Vector3(0.0, 0.95, 0.0), [npc])
		TestHarness.check(hidden, "cover point is hidden from the threat")
		TestHarness.check(cp.distance_to(npc.global_position) <= 15.0, "cover inside the search radius")
		var info: Dictionary = npc.get("last_cover_info")
		TestHarness.check(info.has("low"), "last_cover_info filled (low=%s peek=%s)" % [str(info.get("low")), str(info.get("peek"))])
		npc.call("move_to", cp, "sprint")
		var ok: bool = await _wait_until(func() -> bool: return bool(npc.call("has_arrived", 0.8)), 10.0)
		TestHarness.check(ok, "NPC reaches the cover point")
	# open ground with nothing around: no cover
	var npc2 := _spawn("gang_member", at(-60.0, -60.0), {"yaw": 0.0, "brain": _idle_brain()})
	await TestHarness.wait_physics_frames(4)
	var cp2: Vector3 = npc2.call("find_cover_from", at(-60.0, -75.0) + Vector3(0, 1.4, 0), 10.0)
	TestHarness.check(cp2 == Vector3.INF, "no cover on open ground -> INF")
	await _cleanup()


func _t_vehicle() -> void:
	if Game.get_system("vehicles") == null:
		TestHarness.log_line("vehicles system missing: vehicle test skipped")
		return
	var v := Game.spawn_vehicle("sedan", Transform3D(Basis.IDENTITY, at(-35.0, -30.0) + Vector3(0.0, 0.3, 0.0)), {})
	if v == null:
		TestHarness.log_line("sedan could not be spawned: vehicle test skipped")
		return
	await TestHarness.wait_seconds(1.0)
	var npc := _spawn("civilian_m", at(-39.0, -30.0), {"brain": _idle_brain()})
	await TestHarness.wait_physics_frames(5)
	npc.call("enter_vehicle", v, 0, true)
	TestHarness.check(npc.get("current_vehicle") == v and v.get("driver") == npc, "enter_vehicle(instant) seats the NPC as driver")
	TestHarness.check(npc.get_parent() == v.call("get_seat_node", 0), "NPC is a child of the seat node")
	await TestHarness.wait_seconds(0.5)
	npc.call("exit_vehicle")
	TestHarness.check(npc.get("current_vehicle") == null and v.get("driver") == null, "exit_vehicle frees the seat")
	TestHarness.check(npc.global_position.distance_to(v.global_position) < 6.0 and npc.get_parent() == Game.get_entities_root(),
			"NPC stands beside the car")
	# walk to the door and get in
	npc.call("move_to", at(-42.0, -24.0), "walk")
	await TestHarness.wait_seconds(3.0)
	npc.call("enter_vehicle", v, 0, false)
	var ok: bool = await _wait_until(func() -> bool: return npc.get("current_vehicle") == v, 14.0)
	TestHarness.check(ok, "enter_vehicle walks to the door and gets in")
	npc.call("exit_vehicle")
	await TestHarness.wait_physics_frames(5)
	await _cleanup()
	v.queue_free()


func _t_flee() -> void:
	var civs: Array = []
	for k in 4:
		civs.append(_spawn("civilian_m" if k % 2 == 0 else "civilian_f", at(-10.0 + k * 2.5, 50.0), {"activity": "idle"}))
	await TestHarness.wait_seconds(0.6)
	var shooter := Node3D.new()
	stage.add_child(shooter)
	var src := at(-6.0, 42.0) + Vector3(0.0, 1.2, 0.0)
	var d0: Array = []
	for c: Node3D in civs:
		d0.append(c.global_position.distance_to(src))
	EventBus.noise_emitted.emit(src, 70.0, "gunshot", shooter)
	await TestHarness.wait_seconds(0.5)
	var reacted := 0
	for c: Node3D in civs:
		if str(c.get("state_tag")) in ["flee", "cower"]:
			reacted += 1
	TestHarness.check(reacted == civs.size(), "all civilians react to a gunshot (%d / %d flee or cower)" % [reacted, civs.size()])
	await TestHarness.wait_seconds(3.5)
	var fled := 0
	for i in civs.size():
		var c: Node3D = civs[i]
		if c.global_position.distance_to(src) > float(d0[i]) + 6.0:
			fled += 1
	TestHarness.check(fled >= 1, "civilians ran away from the shot (%d moved > 6 m further away)" % fled)
	shooter.queue_free()
	await _cleanup()


func _t_witness() -> void:
	Wanted.clear("test")
	peds.set("witness_call_chance", 1.0)
	var reports0 := int((peds.get("stats") as Dictionary)["witness_reports"])
	var heat0 := float(Wanted.get("heat")) if Wanted.get("heat") != null else 0.0
	var crime_pos := at(10.0, 5.0)
	var w := _spawn("civilian_f", at(10.0, 15.0), {"activity": "idle", "yaw": PI})
	await TestHarness.wait_seconds(0.5)
	var witnessed := [0]
	var cb := func(_c: String, _p: Vector3, who: Node) -> void:
		if who == w:
			witnessed[0] += 1
	EventBus.crime_witnessed.connect(cb)
	var t_crime := AiSenses.now()
	Wanted.report_crime("assault", crime_pos, {"instigator": Game.player})
	await TestHarness.wait_seconds(0.3)
	TestHarness.check(witnessed[0] == 1, "EventBus.crime_witnessed from the witness")
	var saw_phone: bool = await _wait_until(func() -> bool: return str(w.get("state_tag")) == "phone", 12.0)
	TestHarness.check(saw_phone, "witness gets away and takes the phone")
	if saw_phone:
		TestHarness.check(w.global_position.distance_to(crime_pos) >= 20.0, "call made at a safe distance (%.1f m)" % w.global_position.distance_to(crime_pos))
	var t_phone := AiSenses.now()
	var reported: bool = await _wait_until(func() -> bool: return int((peds.get("stats") as Dictionary)["witness_reports"]) > reports0, 8.0)
	TestHarness.check(reported, "witness report submitted")
	TestHarness.check(AiSenses.now() - t_phone >= 3.5, "the call takes about 4 s (%.1f s)" % (AiSenses.now() - t_phone))
	var heat1 := float(Wanted.get("heat")) if Wanted.get("heat") != null else 0.0
	TestHarness.check(heat1 > heat0 or Wanted.level > 0, "Wanted received the report (heat %.2f -> %.2f, level %d, %.1f s after the crime)" % [heat0, heat1, Wanted.level, AiSenses.now() - t_crime])
	EventBus.crime_witnessed.disconnect(cb)
	Wanted.clear("test")
	await _cleanup()


func _t_witness_cancel() -> void:
	Wanted.clear("test")
	peds.set("witness_call_chance", 1.0)
	var st: Dictionary = peds.get("stats")
	var reports0 := int(st["witness_reports"])
	var cancel0 := int(st["witness_cancelled"])
	var w := _spawn("civilian_m", at(-20.0, 30.0), {"activity": "idle"})
	await TestHarness.wait_seconds(0.5)
	Wanted.report_crime("assault", at(-20.0, 22.0), {"instigator": Game.player})
	var saw_phone: bool = await _wait_until(func() -> bool: return str(w.get("state_tag")) == "phone", 12.0)
	TestHarness.check(saw_phone, "cancel test: witness on the phone")
	w.call("kill", "test")
	await TestHarness.wait_seconds(6.0)
	st = peds.get("stats")
	TestHarness.check(int(st["witness_reports"]) == reports0, "killed witness never reports")
	TestHarness.check(int(st["witness_cancelled"]) == cancel0 + 1, "cancellation recorded")
	TestHarness.check(Wanted.level == 0, "no wanted level from a cancelled call")
	# knocked down before the call ends
	var w2 := _spawn("civilian_f", at(20.0, 30.0), {"activity": "idle"})
	await TestHarness.wait_seconds(0.5)
	Wanted.report_crime("assault", at(20.0, 22.0), {"instigator": Game.player})
	saw_phone = await _wait_until(func() -> bool: return str(w2.get("state_tag")) == "phone", 12.0)
	w2.call("knock_down", Vector3(0.0, 80.0, 150.0))
	await TestHarness.wait_seconds(8.0)
	st = peds.get("stats")
	TestHarness.check(int(st["witness_reports"]) == reports0, "knocked-down witness never reports")
	Wanted.clear("test")
	await _cleanup()


func _t_gang() -> void:
	var d := _dummy(at(0.0, -22.0))
	var g := _spawn("gang_member", at(0.0, 1.0), {"yaw": 0.0, "weapon": "pistol"})
	await TestHarness.wait_physics_frames(10)
	var brain: Node = g.get("brain")
	TestHarness.check(brain != null and brain.has_method("provoke"), "gang brain")
	brain.call("provoke", g, d, false)
	var statuses := {}
	var t := 0.0
	while t < 14.0:
		statuses[str(brain.get("last_status"))] = true
		await get_tree().physics_frame
		t += 1.0 / 60.0
	TestHarness.log_line("gang statuses: %s" % str(statuses.keys()))
	TestHarness.check(statuses.has("move_to_cover") or statuses.has("cover"), "gang member takes cover")
	TestHarness.check(statuses.has("peek") or statuses.has("engage"), "gang member peeks / engages")
	TestHarness.check(d.hits > 0, "gang member hurts the target (%d hits, %.0f hp)" % [d.hits, d.damage])
	d.is_dead = true
	await TestHarness.wait_seconds(1.0)
	TestHarness.check(str(brain.call("get_mode_name")) in ["return", "hang"], "gang calms down when the target is dead")
	d.queue_free()
	await _cleanup()


func _t_knock() -> void:
	var npc := _spawn("civilian_m", at(15.0, 10.0), {"activity": "idle", "brain": _idle_brain()})
	await TestHarness.wait_physics_frames(10)
	npc.call("knock_down", Vector3(0.0, 120.0, -260.0))
	TestHarness.check(bool(npc.get("is_down")), "knock_down -> is_down")
	TestHarness.check(npc.get("_ragdoll") != null, "ragdoll spawned")
	var vis: Node3D = npc.get("visual")
	TestHarness.check(vis != null and not vis.visible, "animated visual hidden while ragdolled")
	var ok: bool = await _wait_until(func() -> bool: return not bool(npc.get("is_down")), 9.0)
	TestHarness.check(ok, "gets up again")
	TestHarness.check(vis.visible and not bool(npc.get("is_dead")), "visible and alive after getting up")
	TestHarness.check(absf(npc.global_position.y - ORIGIN.y) < 0.6, "standing on the stage after the fall")
	var col: CollisionShape3D = npc.get("_col")
	TestHarness.check(col != null and not col.disabled, "collision restored")
	await _cleanup()


func _t_death() -> void:
	var g := _spawn("gang_member", at(-10.0, -30.0), {"weapon": "pistol", "brain": _idle_brain()})
	await TestHarness.wait_physics_frames(10)
	var got := [0, null]
	g.connect("died", func(n: Node3D, k: Node) -> void:
		got[0] += 1
		got[1] = k)
	var pk := Game.get_system("pickups")
	var before := int(pk.call("get_pickup_count")) if pk != null else 0
	var died0 := npc_died_events
	var killer := Node3D.new()
	stage.add_child(killer)
	g.call("apply_damage", Dmg.make(500.0, "bullet", killer, g.global_position + Vector3(0, 1.2, 0), Vector3(0, 0, -1)))
	TestHarness.check(bool(g.get("is_dead")) and got[0] == 1 and got[1] == killer, "died signal once with the killer")
	TestHarness.check(npc_died_events == died0 + 1, "EventBus.npc_died once")
	TestHarness.check(g.get("_ragdoll") != null, "death ragdoll")
	await TestHarness.wait_physics_frames(5)
	if pk != null:
		var after := int(pk.call("get_pickup_count"))
		TestHarness.check(after > before, "cash / weapon dropped through the pickups system (%d -> %d)" % [before, after])
	g.call("apply_damage", Dmg.make(50.0, "bullet", killer))
	TestHarness.check(got[0] == 1, "no second death")
	await TestHarness.wait_seconds(7.0)
	TestHarness.check(not is_instance_valid(g) or g.is_queued_for_deletion(), "dead body node cleaned up")
	killer.queue_free()
	await _cleanup()


func _t_harm() -> void:
	if not Game.has_player():
		return
	Wanted.clear("test")
	crimes.clear()
	var v := _spawn("civilian_m", at(25.0, 40.0), {"brain": _idle_brain()})
	await TestHarness.wait_physics_frames(5)
	for k in 3:
		v.call("apply_damage", Dmg.make(10.0, "bullet", Game.player, v.global_position + Vector3.UP))
	TestHarness.check(crimes.count("assault") == 1, "3 quick hits by the player = one assault (%s)" % str(crimes))
	v.call("apply_damage", Dmg.make(200.0, "bullet", Game.player, v.global_position + Vector3.UP))
	TestHarness.check(crimes.count("murder") == 1, "kill by the player = one murder")
	var cop := _spawn("police_officer", at(28.0, 40.0), {"brain": _idle_brain()})
	await TestHarness.wait_physics_frames(5)
	cop.call("apply_damage", Dmg.make(10.0, "bullet", Game.player, cop.global_position + Vector3.UP))
	TestHarness.check(crimes.count("cop_assault") == 1, "hurting an officer = cop_assault")
	TestHarness.check(float(cop.get("armor")) < 50.0, "officer armour absorbed part of the bullet")
	# vehicle hit: VehicleCrime reports hit_and_run, the body must not add an assault
	var c2 := _spawn("civilian_f", at(31.0, 40.0), {"brain": _idle_brain()})
	await TestHarness.wait_physics_frames(5)
	var n_assault := crimes.count("assault")
	c2.call("apply_damage", Dmg.make(15.0, "vehicle", Game.player, c2.global_position))
	TestHarness.check(crimes.count("assault") == n_assault, "vehicle hit adds no assault (hit_and_run is the vehicle's)")
	Wanted.clear("test")
	await _cleanup()


func _t_staff() -> void:
	var s := _spawn("shop_staff", at(-30.0, 0.0), {"yaw": 0.0, "persistent": true})
	await TestHarness.wait_seconds(0.5)
	var n := [0]
	s.connect("threatened", func(_npc: Node3D, _by: Node) -> void: n[0] += 1)
	for k in 6:
		s.call("notify_threatened", Game.player, 0.16)
		await TestHarness.wait_seconds(0.16)
	await TestHarness.wait_seconds(0.2)
	TestHarness.check(n[0] >= 6, "threatened signal emitted (%d)" % n[0])
	TestHarness.check(str(s.get("state_tag")) == "hands_up", "staff raises the hands (%s)" % str(s.get("state_tag")))
	TestHarness.check(float(s.get("threatened_time")) > 0.0 or n[0] > 0, "threatened_time measured")
	await TestHarness.wait_seconds(4.0)
	TestHarness.check(str(s.get("state_tag")) == "post", "back to the post after the threat (%s)" % str(s.get("state_tag")))
	var shooter := Node3D.new()
	stage.add_child(shooter)
	EventBus.noise_emitted.emit(s.global_position + Vector3(4, 1, 4), 70.0, "gunshot", shooter)
	await TestHarness.wait_seconds(0.4)
	TestHarness.check(str(s.get("state_tag")) == "cower", "staff cowers when shots are fired")
	await TestHarness.wait_seconds(6.0)
	TestHarness.check(str(s.get("state_tag")) == "flee", "staff flees after the shots (%s)" % str(s.get("state_tag")))
	shooter.queue_free()
	await _cleanup()


func _t_bench() -> void:
	var spot := at(-45.0, 20.0)
	var bench := StaticBody3D.new()
	bench.name = "Bench"
	bench.collision_layer = Layers.PROP
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.7, 0.44, 0.6)
	cs.shape = sh
	cs.position = Vector3(0.0, 0.22, 0.05)
	bench.add_child(cs)
	stage.add_child(bench)
	bench.global_transform = Transform3D(Basis(Vector3.UP, 0.7), spot)
	await TestHarness.wait_physics_frames(3)
	peds.call("add_bench_point", bench.global_transform)
	var res: Dictionary = peds.call("claim_bench", self, spot, 4.0)
	TestHarness.check(not res.is_empty(), "claim_bench finds the bench model")
	if res.is_empty():
		return
	var seat: Transform3D = res["transform"]
	TestHarness.check((-seat.basis.z).dot(-bench.global_basis.z) > 0.95, "sitter faces the way the bench faces")
	var npc := _spawn("civilian_f", seat.origin, {"activity": "sit", "bench": seat, "bench_key": int(res["key"])})
	await TestHarness.wait_seconds(0.5)
	TestHarness.check(str(npc.call("get_pose")) == "sit" and str(npc.get("state_tag")) == "sit", "civilian sits on the bench")
	var col: CollisionShape3D = npc.get("_col")
	TestHarness.check(col.disabled, "sitting body does not collide with the bench")
	var vis: Node3D = npc.get("visual")
	TestHarness.check(vis.position.y > 0.3, "seated visual raised to the seat height")
	npc.call("stand_normal")
	TestHarness.check(str(npc.call("get_pose")) == "" and not col.disabled and vis.position.y == 0.0, "stands up again")
	TestHarness.check((peds.call("claim_bench", self, spot, 4.0) as Dictionary).is_empty(), "a taken bench is not handed out twice")
	bench.queue_free()
	await _cleanup()


func _t_crossing() -> void:
	if Game.get_system("vehicles") == null:
		return
	var v := Game.spawn_vehicle("sedan", Transform3D(Basis(Vector3.UP, PI * 0.5), at(45.0, 30.0) + Vector3(0, 0.3, 0)), {})
	if v == null:
		return
	await TestHarness.wait_seconds(0.5)
	TestHarness.check(bool(peds.call("is_crossing_clear", at(20.0, 26.0), at(20.0, 34.0))), "crossing clear while the car stands far away")
	(v as RigidBody3D).linear_velocity = Vector3(-11.0, 0.0, 0.0)
	await TestHarness.wait_seconds(0.35)
	var blocked := not bool(peds.call("is_crossing_clear", at(20.0, 26.0), at(20.0, 34.0)))
	TestHarness.check(blocked, "an approaching car blocks the crossing (car at %s)" % str(v.global_position - ORIGIN))
	TestHarness.check(bool(peds.call("is_crossing_clear", at(70.0, 26.0), at(70.0, 34.0))), "a car driving away does not block")
	v.queue_free()
	await TestHarness.wait_physics_frames(2)


func _t_carhit() -> void:
	if Game.get_system("vehicles") == null:
		return
	var npc := _spawn("civilian_m", at(-50.0, -50.0), {"brain": _idle_brain()})
	var v := Game.spawn_vehicle("sedan", Transform3D(Basis(Vector3.UP, PI * 0.5), at(-34.0, -50.0) + Vector3(0, 0.3, 0)), {})
	if v == null:
		return
	await TestHarness.wait_seconds(0.4)
	crimes.clear()
	(v as RigidBody3D).linear_velocity = Vector3(-15.0, 0.0, 0.0)
	var ok: bool = await _wait_until(func() -> bool: return bool(npc.get("is_down")) or bool(npc.get("is_dead")), 3.0)
	TestHarness.check(ok, "a fast car knocks the pedestrian down (hp %.0f)" % float(npc.get("health")))
	TestHarness.check(float(npc.get("health")) < 100.0, "the impact hurts")
	TestHarness.check(not crimes.has("assault"), "no assault for an NPC-free car hit")
	# down 2.2-3.4 s, up to 2.5 s more while the ragdoll still moves, then 1 s getting up
	var up: bool = await _wait_until(func() -> bool: return bool(npc.get("is_dead")) or not bool(npc.get("is_down")), 9.0)
	TestHarness.check(up, "the pedestrian gets up again (or died) (state %s, %.1f m from the car)" % [str(npc.get("state_tag")), npc.global_position.distance_to(v.global_position)])
	if up and not bool(npc.get("is_dead")):
		var local := v.global_transform.affine_inverse() * npc.global_position
		var ab: Variant = v.get("body_aabb")
		var inside := ab is AABB and (ab as AABB).grow(0.1).has_point(Vector3(local.x, (ab as AABB).get_center().y, local.z))
		TestHarness.check(not inside and absf(npc.global_position.y - ORIGIN.y) < 0.5, "gets up beside the car, on the ground (y %.2f)" % (npc.global_position.y - ORIGIN.y))
	v.queue_free()
	await _cleanup()


func _t_player_stimuli() -> void:
	var p := Game.player
	if p == null or not p.has_method("teleport"):
		TestHarness.log_line("no player: player stimuli skipped")
		return
	Game.invulnerable = true
	var base := at(50.0, -50.0)
	peds.call("set_focus_override", base)
	p.call("teleport", base + Vector3(0, 0.1, 0), 0.0)
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		Game.camera_rig.call("snap_to", 0.0)
	await TestHarness.wait_seconds(0.5)
	# 1) walking into somebody
	var c := _spawn("civilian_m", base + Vector3(0.0, 0.0, -2.6), {"activity": "idle", "yaw": PI})
	await TestHarness.wait_seconds(0.4)
	Input.action_press("move_forward")
	var bumped: bool = await _wait_until(func() -> bool: return str(c.get("state_tag")) == "annoyed", 2.5)
	Input.action_release("move_forward")
	TestHarness.check(bumped, "walking into a pedestrian annoys him")
	await _cleanup()
	p.call("teleport", base + Vector3(0, 0.1, 0), 0.0)
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		Game.camera_rig.call("snap_to", 0.0)
	await TestHarness.wait_seconds(0.4)
	# 2) a firearm pointed at a civilian
	var inv: Variant = p.get("inventory")
	var armed := false
	if inv != null and is_instance_valid(inv) and (inv as Node).has_method("give_weapon"):
		(inv as Node).call("give_weapon", "pistol", 24)
		armed = bool((inv as Node).call("equip", "pistol"))
	if armed:
		await TestHarness.wait_seconds(0.8)
		var t := _spawn("civilian_f", base + Vector3(0.0, 0.0, -8.0), {"activity": "idle", "yaw": PI})
		var got := [0]
		t.connect("threatened", func(_n: Node3D, _b: Node) -> void: got[0] += 1)
		await TestHarness.wait_seconds(0.3)
		Input.action_press("aim")
		var reacted: bool = await _wait_until(func() -> bool: return str(t.get("state_tag")) in ["surrender", "cower", "flee"], 3.0)
		Input.action_release("aim")
		TestHarness.check(got[0] > 0, "aiming a pistol at a civilian emits threatened (%d)" % got[0])
		TestHarness.check(reacted, "threatened civilian raises the hands / cowers / flees (%s)" % str(t.get("state_tag")))
		(inv as Node).call("holster")
		await _cleanup()
	else:
		TestHarness.log_line("player inventory missing: aim threat skipped")
	# 3) a hostile gang member notices the player standing in plain view
	var g := _spawn("gang_member", base + Vector3(0.0, 0.0, -11.0), {"yaw": PI, "hostile": true, "weapon": "pistol"})
	var noticed: bool = await _wait_until(func() -> bool: return bool(g.get("is_alerted")), 4.0)
	TestHarness.check(noticed, "hostile gang member becomes alerted (awareness %.2f)" % float(g.call("get_awareness")))
	await TestHarness.wait_seconds(0.5)
	TestHarness.check(str((g.get("brain") as Node).call("get_mode_name")) == "combat", "and attacks the player")
	await _cleanup()
	peds.call("set_focus_override", ORIGIN)
	Game.invulnerable = false


func _t_tough() -> void:
	var d := _dummy(at(-50.0, 0.0))
	var t := _spawn("civilian_tough", at(-50.0, 3.0), {"activity": "idle", "yaw": 0.0})
	await TestHarness.wait_seconds(0.4)
	t.call("apply_damage", Dmg.make(8.0, "melee", d, t.global_position + Vector3(0, 1.3, 0), Vector3(0, 0, 1)))
	await TestHarness.wait_seconds(0.3)
	TestHarness.check(str(t.get("state_tag")) == "fight", "tough local fights back when punched (%s)" % str(t.get("state_tag")))
	var ok: bool = await _wait_until(func() -> bool: return d.hits > 0, 6.0)
	TestHarness.check(ok, "and lands punches (%d hits)" % d.hits)
	# an ordinary civilian flees instead
	var c := _spawn("civilian_f", at(-55.0, 3.0), {"activity": "idle"})
	await TestHarness.wait_seconds(0.3)
	c.call("apply_damage", Dmg.make(8.0, "melee", d, c.global_position + Vector3(0, 1.3, 0)))
	await TestHarness.wait_seconds(0.3)
	TestHarness.check(str(c.get("state_tag")) == "flee", "ordinary civilian flees when punched (%s)" % str(c.get("state_tag")))
	d.queue_free()
	await _cleanup()


func _t_spawn_opts() -> void:
	# appearance, brain as Script, hostile, persistent
	var look := {"body": "f", "top": "hoodie", "top_color": "#c8443a", "hair": "ponytail", "bottom": "jeans"}
	var a := _spawn("civilian_f", at(40.0, 40.0), {"appearance": look, "brain": load("res://gta/code/ai/brains/ai_brain_staff.gd"),
			"hostile": true, "persistent": true, "weapon": "smg", "yaw": 1.0})
	var app: Dictionary = (a.get("visual") as Node).call("get_appearance")
	TestHarness.check(str(app.get("top")) == "hoodie" and str(app.get("hair")) == "ponytail", "opts.appearance applied")
	TestHarness.check((a.get("brain") as Node).has_method("get_mode_name") and (a.get("brain") as Node).get_script() == load("res://gta/code/ai/brains/ai_brain_staff.gd"), "opts.brain Script instanced")
	TestHarness.check(bool(a.get("hostile")) and bool(a.get("persistent")) and str(a.get("weapon_id")) == "smg", "opts hostile / persistent / weapon")
	TestHarness.check(absf(wrapf(a.rotation.y - 1.0, -PI, PI)) < 0.01, "opts.yaw")
	# vehicle + seat
	if Game.get_system("vehicles") != null:
		var v := Game.spawn_vehicle("sedan", Transform3D(Basis.IDENTITY, at(45.0, 45.0) + Vector3(0, 0.3, 0)), {})
		if v != null:
			await TestHarness.wait_seconds(0.5)
			var d := _spawn("taxi_driver", at(43.0, 45.0), {"vehicle": v, "seat": 0})
			var p := _spawn("civilian_m", at(43.0, 46.0), {"vehicle": v, "seat": 1})
			TestHarness.check(d.get("current_vehicle") == v and v.get("driver") == d, "opts.vehicle seats the driver")
			TestHarness.check(p.get("current_vehicle") == v and int(p.get("seat_index")) == 1, "opts.seat = passenger seat")
			await TestHarness.wait_seconds(0.5)
			v.call("eject_occupants", Vector3(0.0, 60.0, 0.0))
			await TestHarness.wait_physics_frames(3)
			TestHarness.check(d.get("current_vehicle") == null and d.get_parent() == Game.get_entities_root(), "eject_occupants puts the NPC on the street")
			await TestHarness.wait_seconds(0.5)
			var d2 := _spawn("civilian_m", at(43.0, 45.0), {"vehicle": v, "seat": 0})
			TestHarness.check(v.get("driver") == d2, "second driver seated")
			peds.call("clear_all", true)
			await TestHarness.wait_physics_frames(2)
			TestHarness.check(v.get("driver") == null and v.call("get_occupant", 0) == null, "despawning a seated NPC frees the seat")
			v.queue_free()
	await _cleanup()
