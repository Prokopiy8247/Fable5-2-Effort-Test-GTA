extends Node
## POLICE response test (headless): real world, vehicles, peds, police, real player downtown.
##   part 1  set_level(1): an officer reaches the idle unarmed player within 30 s, the arrest
##           (Wanted.bust) follows
##   part 2  set_level(2): officers open fire (the armed, aiming player takes damage)
##   part 3  set_level(3): the player drives a spawned sedan east along the Coral Ring arterial
##           (test autopilot through Input actions) -> a roadblock appears on the route ahead; at
##           least two cruisers reach him within 45 s
##   part 4  2 stars, the player drives the ring: pursuit tactics (PIT / box / ram) are used; the player
##           stops -> the cruisers stop and deploy, an officer walks to the driver door -> arrest
##   part 5  set_level(5): SWAT vans with police_swat officers are dispatched and arrive
##   part 6  officers on foot near the player re-board their cruiser when he drives away, then chase
## Command (all parts; --pol_part=1,2 limits them):
##   tools\godot.ps1 -Mode headless -Frames 16000 -TimeoutSec 420 -UserArgs '--test=pol_response','--test-timeout=400','--seed=21','--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'

var T: Node
var pol: Node
var _parts: PackedStringArray = ["1", "2", "3", "4", "5", "6"]
var _busted: int = 0
var _player_dmg: float = 0.0
var _police_shots: int = 0
var _drive: bool = false
var _drive_speed: float = 17.0
var _friendly_harm: int = 0


func _ready() -> void:
	T = TestHarness
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pol_part="):
			_parts = a.substr(11).split(",")
	EventBus.player_busted.connect(func() -> void: _busted += 1)
	EventBus.player_damaged.connect(func(amount: float, _info: Dictionary) -> void: _player_dmg += amount)
	EventBus.weapon_fired.connect(func(_w: String, shooter: Node, _o: Vector3, _d: Vector3) -> void:
		if shooter != null and is_instance_valid(shooter) and shooter.is_in_group("police"):
			_police_shots += 1)
	Wanted.crime_became_known.connect(func(id: String, _pos: Vector3, source: String) -> void:
		T.log_line("CRIME known %s source=%s level=%d" % [id, source, Wanted.level]))
	EventBus.npc_injured.connect(func(npc: Node3D, attacker: Node, info: Dictionary) -> void:
		_log_police_harm("hurt", npc, attacker, info))
	EventBus.npc_died.connect(func(npc: Node3D, killer: Node, info: Dictionary) -> void:
		_log_police_harm("died", npc, killer, info))
	await T.wait_seconds(1.0)
	await _run()
	_release_inputs()
	Wanted.debug_time_scale = 1.0
	Wanted.clear("cheat")
	T.finish()


## Who hurts police officers (friendly fire / own cars must not happen).
func _log_police_harm(what: String, npc: Node3D, attacker: Node, info: Dictionary) -> void:
	if npc == null or not is_instance_valid(npc) or not (npc.is_in_group("police") or npc.is_in_group("gang")):
		return
	var who := "null"
	if attacker != null and is_instance_valid(attacker):
		who = "player" if attacker.is_in_group("player") else ("police" if attacker.is_in_group("police") else attacker.get_class())
	var inst: Variant = info.get("instigator", null)
	var inst_s := "null"
	if inst is Node and is_instance_valid(inst):
		inst_s = str((inst as Node).get("archetype_id")) if (inst as Node).is_in_group("npc") else (inst as Node).get_class()
	if npc.is_in_group("gang"):
		T.log_line("GANG %s by=%s inst=%s type=%s amount=%.0f" % [what, who, inst_s, str(info.get("type", "")), float(info.get("amount", 0.0))])
		return
	if who == "police":
		_friendly_harm += 1
	T.log_line("POLICE %s by=%s inst=%s type=%s amount=%.0f" % [what, who, inst_s, str(info.get("type", "")), float(info.get("amount", 0.0))])


func _physics_process(_delta: float) -> void:
	if _drive:
		_autopilot()


func _run() -> void:
	pol = Game.get_system("police")
	if not T.check(pol != null and pol.has_method("spawn_unit"), "police system registered"):
		return
	var p := Game.player
	if not T.check(p != null and is_instance_valid(p), "real player present"):
		return
	T.check(pol.has_method("get_units") and pol.has_method("clear_units") and pol.has_method("set_enabled") \
			and pol.has_method("adopt_patrol") and pol.has_method("reset_for_respawn"), "police API complete")
	if "1" in _parts:
		await _part1(p)
	if "2" in _parts:
		await _part2(p)
	if "3" in _parts:
		await _part3(p)
	if "4" in _parts:
		await _part4(p)
	if "5" in _parts:
		await _part5(p)
	if "6" in _parts:
		await _part6(p)
	var info: Dictionary = pol.call("get_debug_info")
	T.log_line("POLICE_STATS %s" % str(info))
	T.check(_friendly_harm == 0, "no officer was hurt by police fire (friendly fire events: %d)" % _friendly_harm)


func _reset(p: Node3D, where: String = "downtown_plaza") -> void:
	_release_inputs()
	_drive = false
	Wanted.clear("cheat")
	if p.get("current_vehicle") != null:
		p.call("exit_vehicle")
		await T.wait_seconds(1.0)
	pol.call("reset_for_respawn")
	var xf := Game.get_location(where)
	p.call("teleport", xf.origin, xf.basis.get_euler().y)
	if p.has_method("heal"):
		p.call("heal", 999.0)
	var inv: Node = p.get("inventory")
	if inv != null and inv.has_method("holster"):
		inv.call("holster")
	await T.wait_seconds(1.0)


func _nearest_officer(pos: Vector3) -> float:
	var best := INF
	for n in get_tree().get_nodes_in_group("police"):
		if n is Node3D and is_instance_valid(n) and not bool(n.get("is_dead")) and n.get("current_vehicle") == null:
			best = minf(best, (n as Node3D).global_position.distance_to(pos))
	return best


func _part1(p: Node3D) -> void:
	await _reset(p)
	_busted = 0
	Wanted.set_level(1)
	var t := 0.0
	var reached := -1.0
	var min_d := INF
	while t < 60.0 and _busted == 0:
		await T.wait_seconds(0.5)
		t += 0.5
		var d := _nearest_officer(p.global_position)
		min_d = minf(min_d, d)
		if reached < 0.0 and d < 6.0:
			reached = t
		if int(t * 2.0) % 6 == 0:
			T.log_line("P1 t=%.1f level=%d state=%d nearest=%.1f units=%s" % [t, Wanted.level, Wanted.state, d,
					str((pol.call("get_debug_info") as Dictionary).get("unit_modes"))])
			_log_units(p)
	T.check(reached >= 0.0 and reached <= 30.0, "1 star: an officer reached the player within 30 s (t=%.1f, closest %.1f m)" % [reached, min_d])
	T.check(_busted == 1, "1 star: idle unarmed player was arrested (bust after %.1f s)" % t)
	T.check(Wanted.level == 0 and Wanted.last_clear_reason == "busted", "bust cleared the wanted level")
	var info: Dictionary = pol.call("get_debug_info")
	T.check(int((info["stats"] as Dictionary).get("busts", 0)) >= 1, "police system counted the arrest")


func _part2(p: Node3D) -> void:
	# in front of the hospital: no gang hangout within earshot (the downtown plaza has one on the
	# street next to it, whose members join any gunfight there and make this check about them)
	await _reset(p, "hospital")
	var inv: Node = p.get("inventory")
	if inv != null:
		inv.call("give_weapon", "pistol", 120)
		inv.call("equip", "pistol")
	await T.wait_seconds(0.5)
	_player_dmg = 0.0
	_police_shots = 0
	Wanted.set_level(2)
	Input.action_press("aim")          # armed and aiming (away from anyone): no arrest, lethal force
	var t := 0.0
	var h0 := float(p.get("health")) + float(p.get("armor"))
	while t < 50.0 and _player_dmg <= 0.0:
		await T.wait_seconds(0.5)
		t += 0.5
		if int(t * 2.0) % 10 == 0:
			T.log_line("P2 t=%.1f shots=%d dmg=%.1f nearest=%.1f state=%d" % [t, _police_shots, _player_dmg, _nearest_officer(p.global_position), Wanted.state])
			_log_units(p)
	Input.action_release("aim")
	var h1 := float(p.get("health")) + float(p.get("armor"))
	T.check(_police_shots > 0, "2 stars: officers opened fire (%d shots, t=%.1f)" % [_police_shots, t])
	T.check(_player_dmg > 0.0 or h1 < h0, "2 stars: the player took damage from police fire (%.1f)" % _player_dmg)
	Wanted.clear("cheat")
	if p.has_method("heal"):
		p.call("heal", 999.0)


## East-bound lane of the Coral Ring near (x, -190).
func _ring_start(x: float) -> Transform3D:
	var roads: Object = Game.world.get("roads")
	var lanes: Array = roads.get("lanes")
	var best := Transform3D()
	var best_d := INF
	for l: Dictionary in lanes:
		if str(l.get("kind", "")) != "arterial":
			continue
		var pts: PackedVector3Array = l["points"]
		var cum: PackedFloat32Array = l["cum"]
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var dir := (b - a)
			dir.y = 0.0
			if dir.length() < 0.5 or dir.normalized().x < 0.95:
				continue
			var mid := (a + b) * 0.5
			var d := Vector2(mid.x - x, mid.z + 190.0).length()
			if d < best_d:
				best_d = d
				best = roads.call("sample_lane", int(l["id"]), cum[i] + (cum[i + 1] - cum[i]) * 0.5)
	return best


func _part3(p: Node3D) -> void:
	await _reset(p)
	var xf := _ring_start(-200.0)
	var car := Game.spawn_vehicle("sedan", Transform3D(xf.basis, xf.origin + Vector3.UP * 0.4), {"owner_tag": "player"})
	if not T.check(car != null, "spawned a sedan on the Coral Ring"):
		return
	p.call("teleport", xf.origin + xf.basis.x * 3.0, 0.0)
	await T.wait_seconds(0.5)
	p.call("enter_vehicle", car, 0, true)
	await T.wait_seconds(1.0)
	T.check(p.get("current_vehicle") == car, "player sits in the sedan")
	Wanted.set_level(3)
	var arrivals := {}
	var rb_seen := false
	var rb_t := -1.0
	var t := 0.0
	_drive = true
	_drive_speed = 16.0
	while t < 45.0:
		await T.wait_seconds(0.5)
		t += 0.5
		var info: Dictionary = pol.call("get_debug_info")
		if not rb_seen and int(info.get("roadblocks", 0)) > 0:
			rb_seen = true
			rb_t = t
			_drive = false
			_release_inputs()
			Input.action_press("move_back")
			T.log_line("P3 roadblock at t=%.1f" % t)
		for u: Variant in pol.call("get_units"):
			if u is RigidBody3D and is_instance_valid(u):
				var d := (u as Node3D).global_position.distance_to(car.global_position)
				if d < 55.0:
					arrivals[(u as Node).get_instance_id()] = true
		if int(t * 2.0) % 10 == 0:
			T.log_line("P3 t=%.1f speed=%.1f pos=%s units=%s arrived=%d rb=%d" % [t, Game.get_player_velocity().length(),
					str(car.global_position.round()), str(info.get("unit_modes")), arrivals.size(), int(info.get("roadblocks", 0))])
			_log_units(p)
		if rb_seen and t > rb_t + 1.5:
			Input.action_release("move_back")
		if rb_seen and arrivals.size() >= 2:
			break
	_release_inputs()
	T.check(rb_seen, "3 stars: a roadblock appeared ahead of the driving player (t=%.1f)" % rb_t)
	T.check(arrivals.size() >= 2, "3 stars: at least two cruisers reached the player within 45 s (%d)" % arrivals.size())
	var rbs: Array = pol.get("roadblocks")
	if not rbs.is_empty():
		var rb: Object = rbs[0]
		var cars: Array = rb.get("cars")
		var props: Array = rb.get("props")
		T.check(cars.size() == 2, "roadblock has two cruisers (%d)" % cars.size())
		T.check(props.size() >= 1, "roadblock has roadblock_police barricades (%d)" % props.size())
		var d_rb := Vector2((rb.get("center") as Vector3).x - car.global_position.x, (rb.get("center") as Vector3).z - car.global_position.z).length()
		T.log_line("P3 roadblock distance from the car %.1f m, officers %d" % [d_rb, (rb.get("officers") as Array).size()])


func _tactic_sum() -> Dictionary:
	var out := {"pits": 0, "boxes": 0, "rams": 0, "deploys": 0}
	for u: Variant in pol.get("units"):
		var st: Dictionary = (u as Object).get("stats")
		for k: String in out.keys():
			out[k] = int(out[k]) + int(st.get(k, 0))
	return out


func _part4(p: Node3D) -> void:
	await _reset(p)
	var xf := _ring_start(-200.0)
	var car := Game.spawn_vehicle("sedan", Transform3D(xf.basis, xf.origin + Vector3.UP * 0.4), {"owner_tag": "player"})
	if not T.check(car != null, "4: sedan spawned"):
		return
	p.call("teleport", xf.origin + xf.basis.x * 3.0, 0.0)
	await T.wait_seconds(0.5)
	p.call("enter_vehicle", car, 0, true)
	await T.wait_seconds(0.5)
	Wanted.set_level(2)
	_busted = 0
	# wait (engine running, rolling slowly so the arrest cannot happen) until a unit has eyes on us
	var w := 0.0
	_drive = true
	_drive_speed = 3.0
	while w < 40.0:
		await T.wait_seconds(0.5)
		w += 0.5
		var seen_by := false
		for u: Variant in pol.get("units"):
			var o := u as Object
			if bool(o.get("sees_target")) and (o.get("vehicle") as Node3D).global_position.distance_to(car.global_position) < 90.0:
				seen_by = true
		if seen_by:
			break
	T.log_line("P4 a unit has eyes on the player after %.1f s" % w)
	_drive_speed = 13.0
	var t := 0.0
	var acc := {"pits": 0, "boxes": 0, "rams": 0, "deploys": 0}
	var close_t := 0.0
	while t < 32.0:
		await T.wait_seconds(0.5)
		t += 0.5
		var ts := _tactic_sum()
		for k: String in acc.keys():
			acc[k] = maxi(int(acc[k]), int(ts[k]))
		for u: Variant in pol.call("get_units"):
			if u is RigidBody3D and is_instance_valid(u) and (u as Node3D).global_position.distance_to(car.global_position) < 30.0:
				close_t += 0.5
				break
		if int(t * 2.0) % 4 == 0:
			T.log_line("P4 t=%.1f lvl=%d state=%d speed=%.1f pos=%s tactics=%s" % [t, Wanted.level, Wanted.state, Game.get_player_velocity().length(), str(car.global_position.round()), str(ts)])
			_log_units(p)
	_drive = false
	_release_inputs()
	Input.action_press("move_back")
	await T.wait_seconds(2.0)
	Input.action_release("move_back")
	T.check(int(acc["pits"]) + int(acc["boxes"]) + int(acc["rams"]) >= 1, "4: pursuit tactics used while chasing (%s)" % str(acc))
	T.check(close_t >= 8.0, "4: cruisers stayed within 30 m for %.1f s of the chase" % close_t)
	# stopped in the car: deploy + arrest at the driver door
	t = 0.0
	while t < 40.0 and _busted == 0:
		await T.wait_seconds(0.5)
		t += 0.5
		if int(t * 2.0) % 4 == 0:
			T.log_line("P4 stopped t=%.1f nearest=%.1f arrestable=%s attack_t=%.1f lethal=%s speed=%.2f" % [t,
					_nearest_officer(p.global_position), str(Wanted.is_player_arrestable()), Wanted.time_since_player_attack,
					str(Wanted.is_lethal_force_authorized()), Game.get_player_velocity().length()])
			_log_units(p)
	var ts2 := _tactic_sum()
	T.check(int(ts2["deploys"]) >= 1 or int(acc["deploys"]) >= 1, "4: cruisers stopped and the crews got out (%s)" % str(ts2))
	T.check(_busted >= 1, "4: arrested in the car (boxed in during the chase, or at the door %.1f s after stopping)" % t)


func _part6(p: Node3D) -> void:
	await _reset(p)
	Game.invulnerable = true
	var inv: Node = p.get("inventory")
	if inv != null:
		inv.call("give_weapon", "pistol", 120)
		inv.call("equip", "pistol")
	var xf := _ring_start(-200.0)
	p.call("teleport", xf.origin + xf.basis.x * 6.0, 0.0)
	var car := Game.spawn_vehicle("sedan", Transform3D(xf.basis, xf.origin + Vector3.UP * 0.4), {"owner_tag": "player"})
	await T.wait_seconds(0.5)
	Input.action_press("aim")
	Wanted.set_level(2)
	var t := 0.0
	var unit: Object = null
	while t < 45.0 and unit == null:
		await T.wait_seconds(0.5)
		t += 0.5
		for u: Variant in pol.get("units"):
			var o := u as Object
			if str(o.call("get_mode_name")) == "deployed":
				for c: Variant in o.call("living_crew"):
					if (c as Node3D).global_position.distance_to(p.global_position) < 35.0:
						unit = o
	T.check(unit != null, "6: a crew got out near the player on foot (%.1f s)" % t)
	if unit == null:
		Game.invulnerable = false
		return
	# straight into the car (armed and aiming until then: not arrestable)
	Input.action_release("aim")
	p.call("enter_vehicle", car, 0, true)
	await T.wait_seconds(0.3)
	_drive = true
	_drive_speed = 14.0
	var boarded := false
	var resumed := false
	t = 0.0
	while t < 30.0:
		await T.wait_seconds(0.25)
		t += 0.25
		if not bool(unit.call("is_valid")):
			break
		var m := str(unit.call("get_mode_name"))
		if m == "board":
			boarded = true
		if boarded and (m == "pursuit" or m == "search") and (unit.call("seated_crew") as Array).size() >= 1:
			resumed = true
			break
		if int(t * 4.0) % 20 == 0:
			_log_units(p)
	_drive = false
	_release_inputs()
	T.check(boarded, "6: the crew was recalled to its cruiser when the player drove off")
	T.check(resumed, "6: the re-boarded cruiser resumed the pursuit (%.1f s)" % t)
	Game.invulnerable = false


func _part5(p: Node3D) -> void:
	await _reset(p)
	Wanted.set_level(5)
	var t := 0.0
	var swat_npcs := 0
	var van_near := false
	while t < 50.0:
		await T.wait_seconds(0.5)
		t += 0.5
		swat_npcs = 0
		for n in get_tree().get_nodes_in_group("police"):
			if is_instance_valid(n) and str(n.get("archetype_id")) == "police_swat" and not bool(n.get("is_dead")):
				swat_npcs += 1
		for u: Variant in pol.call("get_units"):
			if u is RigidBody3D and is_instance_valid(u) and str((u as Node).get("spec_id")) == "swat_van":
				if (u as Node3D).global_position.distance_to(p.global_position) < 70.0:
					van_near = true
		if int(t * 2.0) % 10 == 0:
			T.log_line("P5 t=%.1f swat=%d van_near=%s info=%s" % [t, swat_npcs, str(van_near), str((pol.call("get_debug_info") as Dictionary).get("unit_modes"))])
		if swat_npcs >= 4 and van_near:
			break
	T.check(swat_npcs >= 2, "5 stars: SWAT officers present (%d)" % swat_npcs)
	T.check(van_near, "5 stars: a SWAT van reached the player")
	var info: Dictionary = pol.call("get_debug_info")
	T.check(int(info.get("officers_alive", 0)) <= 16, "officer cap respected (%d)" % int(info.get("officers_alive", 0)))
	T.check(int(info.get("units", 0)) <= 8, "vehicle cap respected (%d)" % int(info.get("units", 0)))
	Wanted.clear("cheat")


func _log_units(p: Node3D) -> void:
	for u: Variant in pol.get("units"):
		var o := u as Object
		var v: Node3D = o.get("vehicle")
		if v == null or not is_instance_valid(v):
			continue
		var di: Dictionary = o.call("get_debug_info")
		T.log_line("   unit %s d=%.0f pos=%s %s" % [str(v.get("spec_id")), v.global_position.distance_to(p.global_position),
				str(v.global_position.round()), str(di)])
	for n in get_tree().get_nodes_in_group("police"):
		if n is Node3D and is_instance_valid(n) and n.get("current_vehicle") == null:
			var b: Variant = n.get("brain")
			var m := str((b as Node).call("get_mode_name")) if b is Node else "?"
			var sees := bool((b as Node).get("sees")) if b is Node else false
			T.log_line("   officer d=%.0f mode=%s tag=%s sees=%s hp=%.0f" % [(n as Node3D).global_position.distance_to(p.global_position), m,
					str(n.get("state_tag")), str(sees), float(n.get("health"))])


# --- test autopilot (Input actions, like a player) -------------------------------------------------

func _autopilot() -> void:
	var car := Game.get_player_vehicle()
	if car == null or pol == null:
		return
	var path: Dictionary = pol.call("_predict_path", 60.0)
	var pts: PackedVector3Array = path.get("pts", PackedVector3Array())
	var cum: PackedFloat32Array = path.get("cum", PackedFloat32Array())
	if pts.size() < 2:
		return
	var spd := float(car.call("get_forward_speed"))
	var look := clampf(spd * 0.8 + 6.0, 8.0, 22.0)
	var aim: Vector3 = pol.call("_path_point", pts, cum, look)
	var lp := car.global_transform.affine_inverse() * aim
	var steer := clampf(atan2(lp.x, -lp.z) * 2.2, -1.0, 1.0)
	_set_axis("move_right", "move_left", steer)
	# slow for the bends further ahead (heading change over the next 40 m)
	var want := _drive_speed
	var far_pt: Vector3 = pol.call("_path_point", pts, cum, 40.0)
	var lp2 := car.global_transform.affine_inverse() * far_pt
	if absf(atan2(lp2.x, -lp2.z)) > 0.35:
		want = minf(want, 9.0)
	var err := want - spd
	if err > 0.5:
		Input.action_press("move_forward", clampf(0.3 + err * 0.15, 0.0, 1.0))
		Input.action_release("move_back")
	elif err < -2.0:
		Input.action_release("move_forward")
		Input.action_press("move_back", 0.4)
	else:
		Input.action_press("move_forward", 0.25)
		Input.action_release("move_back")


func _set_axis(pos_action: String, neg_action: String, v: float) -> void:
	if v > 0.02:
		Input.action_press(pos_action, v)
		Input.action_release(neg_action)
	elif v < -0.02:
		Input.action_press(neg_action, -v)
		Input.action_release(pos_action)
	else:
		Input.action_release(pos_action)
		Input.action_release(neg_action)


func _release_inputs() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back", "aim", "fire", "handbrake"]:
		Input.action_release(a)
