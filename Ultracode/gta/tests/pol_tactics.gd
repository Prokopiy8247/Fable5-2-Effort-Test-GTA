extends Node
## POLICE tactics test (headless, real systems, invulnerable player):
##   S  4 stars: a roadblock with spike strips on the Coral Ring; the player drives a sedan over the
##      strips -> tyres pop (vehicle.pop_tire through the police spike check)
##   D  3 stars: two cruisers chase the player on the ring; passenger officers fire from the car
##   W  4 stars on foot downtown: the SWAT van arrives, tactical officers are paired and open fire
##   R  1 star: an officer starts cuffing the player, who sprints away -> "resisting" is reported
##   G  a gang member shoots an officer: the officer and a colleague nearby fight back (police fire at
##      the gang member), nothing is charged to the player
##   P  a frozen pedestrian stands in the lane in front of a responding cruiser: it stops short, steers
##      round him without hurting him and still reaches the player
##   L  a witness who finishes his call about an old crime right after the arrest does not start a
##      new wanted episode (Wanted review fix)
##   X  W2.1 release_vehicle: "carjacked" puts the crew out and returns the driver; "despawn" frees the
##      seated crew (nobody left behind in the seats), no ai_controller meta, driver null
##   tools\godot.ps1 -Mode headless -Frames 12000 -TimeoutSec 400 -UserArgs '--test=pol_tactics','--test-timeout=380','--seed=12','--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## (--pol_part=S,D,W limits the parts)

var T: Node
var pol: Node
var _parts: PackedStringArray = ["S", "D", "W", "R", "G", "P", "X", "L"]
var _seated_shots: int = 0
var _swat_shots: int = 0
var _drive_target: Vector3 = Vector3.INF
var _drive_speed: float = 12.0
var _follow_road: bool = false


func _ready() -> void:
	T = TestHarness
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pol_part="):
			_parts = a.substr(11).split(",")
	EventBus.weapon_fired.connect(_on_fired)
	Wanted.crime_became_known.connect(func(id: String, _pos: Vector3, source: String) -> void:
		T.log_line("CRIME known %s source=%s level=%d" % [id, source, Wanted.level]))
	await T.wait_seconds(1.0)
	pol = Game.get_system("police")
	var p := Game.player
	if T.check(pol != null and p != null, "police system + player present"):
		Game.invulnerable = true
		if "S" in _parts:
			await _spikes(p)
		if "D" in _parts:
			await _driveby(p)
		if "W" in _parts:
			await _swat(p)
		if "R" in _parts:
			await _resist(p)
		if "G" in _parts:
			await _gang(p)
		if "P" in _parts:
			await _pedestrian(p)
		if "X" in _parts:
			await _release(p)
		if "L" in _parts:
			await _late_witness(p)
	_drive_target = Vector3.INF
	_follow_road = false
	for a in ["move_left", "move_right", "move_forward", "move_back", "aim", "sprint"]:
		Input.action_release(a)
	Game.invulnerable = false
	Wanted.clear("cheat")
	T.log_line("POLICE_STATS %s" % str(pol.call("get_debug_info")))
	T.finish()


func _on_fired(_w: String, shooter: Node, _o: Vector3, _d: Vector3) -> void:
	if shooter == null or not is_instance_valid(shooter) or not shooter.is_in_group("police"):
		return
	if shooter.get("current_vehicle") != null:
		_seated_shots += 1
	if str(shooter.get("archetype_id")) == "police_swat":
		_swat_shots += 1


func _physics_process(_delta: float) -> void:
	var car := Game.get_player_vehicle()
	if car == null:
		return
	if _follow_road:
		var path: Dictionary = pol.call("_predict_path", 60.0)
		var pts: PackedVector3Array = path.get("pts", PackedVector3Array())
		var cum: PackedFloat32Array = path.get("cum", PackedFloat32Array())
		if pts.size() >= 2:
			_steer_to(car, pol.call("_path_point", pts, cum, clampf(float(car.call("get_forward_speed")) * 0.8 + 6.0, 8.0, 22.0)))
	elif _drive_target != Vector3.INF:
		_steer_to(car, _drive_target)


func _steer_to(car: Node3D, aim: Vector3) -> void:
	var lp := car.global_transform.affine_inverse() * aim
	var steer := clampf(atan2(lp.x, -lp.z) * 2.2, -1.0, 1.0)
	if steer > 0.02:
		Input.action_press("move_right", steer)
		Input.action_release("move_left")
	elif steer < -0.02:
		Input.action_press("move_left", -steer)
		Input.action_release("move_right")
	else:
		Input.action_release("move_left")
		Input.action_release("move_right")
	var spd := float(car.call("get_forward_speed"))
	if spd < _drive_speed:
		Input.action_press("move_forward", clampf(0.3 + (_drive_speed - spd) * 0.15, 0.0, 1.0))
	else:
		Input.action_press("move_forward", 0.15)


func _reset(p: Node3D) -> void:
	_drive_target = Vector3.INF
	_follow_road = false
	for a in ["move_left", "move_right", "move_forward", "move_back", "aim"]:
		Input.action_release(a)
	Wanted.clear("cheat")
	if p.get("current_vehicle") != null:
		p.call("exit_vehicle")
		await T.wait_seconds(1.0)
	pol.call("reset_for_respawn")
	# like the respawn flow: the population restarts (witnesses of an earlier part must not call in
	# their crime during the next one)
	var peds := Game.get_system("peds")
	if peds != null and peds.has_method("reset_for_respawn"):
		peds.call("reset_for_respawn")
	await T.wait_seconds(0.5)


func _ring_point_index(x: float) -> int:
	var pts: Array = Game.world.call("get_spawn_points", "roadblock")
	var best := -1
	var best_d := INF
	for i in pts.size():
		var q: Vector3 = (pts[i] as Transform3D).origin
		var d := Vector2(q.x - x, q.z + 190.0).length()
		if d < best_d:
			best_d = d
			best = i
	return best


func _spikes(p: Node3D) -> void:
	await _reset(p)
	Wanted.set_level(4)
	pol.call("clear_units")
	var pts: Array = Game.world.call("get_spawn_points", "roadblock")
	var idx := _ring_point_index(-30.0)
	if not T.check(idx >= 0, "S: roadblock point on the ring"):
		return
	var rxf: Transform3D = pts[idx]
	var west := Vector3(-1.0, 0.0, 0.0)
	var rb: Object = pol.call("_build_roadblock", idx, rxf, west * 50.0, Wanted.get_level_config(4))
	if not T.check(rb != null and (rb.get("spikes") as Array).size() >= 2, "S: 4-star roadblock with spike strips"):
		return
	# east-bound sedan 45 m before the strip line, in the outer lane
	var start := rxf.origin + west * (17.0 + 45.0) + Vector3(0.0, 0.4, 3.6)
	var car := Game.spawn_vehicle("sedan", Transform3D(Basis(Vector3.UP, -PI * 0.5), start), {"owner_tag": "player"})
	if not T.check(car != null, "S: sedan spawned"):
		return
	p.call("teleport", start + Vector3(0.0, 0.0, 3.0), 0.0)
	await T.wait_seconds(0.3)
	p.call("enter_vehicle", car, 0, true)
	await T.wait_seconds(0.5)
	_drive_speed = 11.0
	_drive_target = rxf.origin + Vector3(0.0, 0.0, 3.6) - west * 4.0
	var t := 0.0
	var flat := 0
	while t < 10.0:
		await T.wait_seconds(0.25)
		t += 0.25
		flat = 0
		for i in int(car.call("get_wheel_count")):
			if bool(car.call("is_tire_flat", i)):
				flat += 1
		if flat >= 2:
			break
	_drive_target = Vector3.INF
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await T.wait_seconds(1.0)
	Input.action_release("move_back")
	var pops := int((pol.call("get_debug_info") as Dictionary)["stats"].get("spike_pops", 0))
	T.check(flat >= 1 and pops >= 1, "S: the spike strip popped %d tyre(s) (police counted %d)" % [flat, pops])


func _driveby(p: Node3D) -> void:
	await _reset(p)
	var idx := _ring_point_index(-150.0)
	var pts: Array = Game.world.call("get_spawn_points", "roadblock")
	var rxf: Transform3D = pts[idx]
	var roads: Object = Game.world.get("roads")
	var near: Dictionary = roads.call("get_nearest_lane", rxf.origin + Vector3(0.0, 0.0, 3.6), 6.0)
	if not T.check(not near.is_empty(), "D: east-bound ring lane"):
		return
	var xf: Transform3D = roads.call("sample_lane", int(near["lane_id"]), float(near["offset"]))
	var car := Game.spawn_vehicle("sedan", Transform3D(xf.basis, xf.origin + Vector3.UP * 0.4), {"owner_tag": "player"})
	p.call("teleport", xf.origin + xf.basis.x * 3.0, 0.0)
	await T.wait_seconds(0.3)
	p.call("enter_vehicle", car, 0, true)
	Wanted.set_level(3)
	var fwd := -xf.basis.z
	var c1: Node3D = pol.call("spawn_unit_at", "cruiser", Transform3D(xf.basis, xf.origin - fwd * 15.0))
	var c2: Node3D = pol.call("spawn_unit_at", "cruiser", Transform3D(xf.basis, xf.origin - fwd * 28.0 - xf.basis.x * 3.4))
	T.check(c1 != null and c2 != null, "D: two cruisers behind the player")
	_seated_shots = 0
	_follow_road = true
	_drive_speed = 13.0
	var t := 0.0
	while t < 25.0 and _seated_shots < 3:
		await T.wait_seconds(0.5)
		t += 0.5
	_follow_road = false
	T.check(_seated_shots >= 1, "D: passenger officers fired from the moving cruiser (%d shots in %.1f s)" % [_seated_shots, t])


func _swat(p: Node3D) -> void:
	await _reset(p)
	var plaza := Game.get_location("downtown_plaza")
	p.call("teleport", plaza.origin, 0.0)
	var inv: Node = p.get("inventory")
	if inv != null:
		inv.call("give_weapon", "pistol", 200)
		inv.call("equip", "pistol")
	await T.wait_seconds(0.5)
	Input.action_press("aim")
	Wanted.set_level(4)
	_swat_shots = 0
	var t := 0.0
	var paired := 0
	while t < 60.0 and _swat_shots < 3:
		await T.wait_seconds(0.5)
		t += 0.5
		paired = 0
		for n in get_tree().get_nodes_in_group("police"):
			if is_instance_valid(n) and str(n.get("archetype_id")) == "police_swat":
				var b: Variant = n.get("brain")
				if b is Node and (b as Node).get("buddy") != null:
					paired += 1
	Input.action_release("aim")
	T.check(paired >= 2, "W: tactical officers work in pairs (%d with a buddy)" % paired)
	T.check(_swat_shots >= 1, "W: SWAT opened fire (%d shots, %.1f s)" % [_swat_shots, t])
	var hp := 0.0
	for n in get_tree().get_nodes_in_group("police"):
		if is_instance_valid(n) and str(n.get("archetype_id")) == "police_swat":
			hp = maxf(hp, float(n.get("max_health")))
	T.check(hp >= 150.0, "W: SWAT are armoured (max health %.0f + armour)" % hp)


func _resist(p: Node3D) -> void:
	await _reset(p)
	var inv: Node = p.get("inventory")
	if inv != null:
		inv.call("holster")
	var plaza := Game.get_location("downtown_plaza")
	p.call("teleport", plaza.origin, 0.0)
	await T.wait_seconds(0.5)
	var known: Array = []
	var cb := func(id: String, _pos: Vector3, src: String) -> void: known.append([id, src])
	Wanted.crime_became_known.connect(cb)
	Wanted.set_level(1)
	var t := 0.0
	var cuffer: Node3D = null
	while t < 50.0 and cuffer == null:
		await T.wait_seconds(0.25)
		t += 0.25
		if int(t * 4.0) % 12 == 0:
			_log_police(p, "R t=%.1f" % t)
		for n in get_tree().get_nodes_in_group("police"):
			var b: Variant = n.get("brain")
			if b is Node and is_instance_valid(b) and (b as Node).has_method("get_arrest_progress") 					and float((b as Node).call("get_arrest_progress")) > 0.2:
				cuffer = n as Node3D
	if not T.check(cuffer != null, "R: an officer is cuffing the player (%.1f s)" % t):
		Wanted.crime_became_known.disconnect(cb)
		return
	# turn away from him and sprint off
	var away := p.global_position - cuffer.global_position
	away.y = 0.0
	var yaw := atan2(-away.x, -away.z)
	p.call("teleport", p.global_position, yaw)
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		Game.camera_rig.call("snap_to", yaw)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await T.wait_seconds(3.0)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Wanted.crime_became_known.disconnect(cb)
	var resisted := false
	for k: Array in known:
		if str(k[0]) == "resisting" and str(k[1]) == "police":
			resisted = true
	var st: Dictionary = (pol.call("get_debug_info") as Dictionary)["stats"]
	T.check(resisted and int(st.get("resisting", 0)) >= 1, "R: running from the arrest reported 'resisting' (%s, level %d)" % [str(known), Wanted.level])
	T.check(int(st.get("busts", 0)) == 0 or Wanted.level > 0, "R: the suspect got away from the cuffs")


## A spot on the walk network near `near`.
func _walk_spot(near: Vector3, dmin: float, dmax: float) -> Vector3:
	var walk: Object = Game.world.get("walk")
	if walk != null:
		var q: Vector3 = walk.call("random_point", near, dmin, dmax)
		if q != Vector3.INF:
			return q
	return near + Vector3(dmin, 0.0, 0.0)


func _gang(p: Node3D) -> void:
	await _reset(p)
	var plaza := Game.get_location("downtown_plaza")
	p.call("teleport", plaza.origin + Vector3(0.0, 0.0, 26.0), 0.0)   # the player is not involved
	await T.wait_seconds(0.5)
	var c := _walk_spot(plaza.origin, 0.0, 12.0)
	var o1: Node3D = pol.call("spawn_unit_at", "officer", Transform3D(Basis.IDENTITY, c))
	var o2: Node3D = pol.call("spawn_unit_at", "officer", Transform3D(Basis.IDENTITY, c + Vector3(4.0, 0.0, 3.0)))
	var g: Node3D = Game.spawn_npc("gang_member", c + Vector3(-14.0, 0.0, 6.0), {"weapon": "pistol"})
	if not T.check(o1 != null and o2 != null and g != null, "G: two officers and a gang member placed"):
		return
	await T.wait_seconds(0.5)
	if not T.check(is_instance_valid(o1) and is_instance_valid(o2) and is_instance_valid(g), "G: everybody still there"):
		return
	var shots_at := [0]
	var cb := func(_w: String, shooter: Node, _o: Vector3, _d: Vector3) -> void:
		if shooter == o1 or shooter == o2:
			shots_at[0] += 1
	EventBus.weapon_fired.connect(cb)
	# the gang member opens fire on officer 1 (the damage path a real shot takes)
	o1.call("apply_damage", Dmg.make(12.0, "bullet", g, o1.global_position + Vector3.UP * 1.2, (o1.global_position - g.global_position).normalized()))
	var t := 0.0
	var both := false
	while t < 12.0 and shots_at[0] < 3:
		await T.wait_seconds(0.25)
		t += 0.25
		var b1: Variant = o1.get("brain") if is_instance_valid(o1) else null
		var b2: Variant = o2.get("brain") if is_instance_valid(o2) else null
		if b1 is Node and b2 is Node and (b1 as Node).get("npc_threat") == g and (b2 as Node).get("npc_threat") == g:
			both = true
	EventBus.weapon_fired.disconnect(cb)
	T.check(both, "G: the attacked officer and his colleague both took the gang member on")
	T.check(shots_at[0] >= 1, "G: the officers fired back (%d shots in %.1f s)" % [shots_at[0], t])
	T.check(Wanted.level == 0, "G: nothing was charged to the player (level %d)" % Wanted.level)
	var st: Dictionary = (pol.call("get_debug_info") as Dictionary)["stats"]
	T.check(int(st.get("npc_threats", 0)) >= 1, "G: the police system broadcast the threat (%d)" % int(st.get("npc_threats", 0)))
	if is_instance_valid(g) and not bool(g.get("is_dead")):
		g.call("kill", "test")


func _pedestrian(p: Node3D) -> void:
	await _reset(p)
	var roads: Object = Game.world.get("roads")
	var idx := _ring_point_index(-60.0)
	var pts: Array = Game.world.call("get_spawn_points", "roadblock")
	var rxf: Transform3D = pts[idx]
	var near: Dictionary = roads.call("get_nearest_lane", rxf.origin + Vector3(0.0, 0.0, 3.6), 6.0)
	if not T.check(not near.is_empty(), "P: east-bound ring lane"):
		return
	var lane := int(near["lane_id"])
	var off := float(near["offset"])
	var car_xf: Transform3D = _lane_walk(roads, lane, off, 0.0)
	var ped_xf: Transform3D = _lane_walk(roads, lane, off, 32.0)
	var player_xf: Transform3D = _lane_walk(roads, lane, off, 85.0)
	# the player waits on the kerb further down the road (1 star, unarmed: the cruiser comes for him)
	var kerb := player_xf.origin + player_xf.basis.x * 6.5
	p.call("teleport", kerb, 0.0)
	await T.wait_seconds(0.3)
	# a pedestrian frozen in the lane (no brain: he never gets out of the way), cowering
	var still := Node.new()
	var ped: Node3D = Game.spawn_npc("civilian_m", ped_xf.origin, {"persistent": true, "brain": still})
	if not T.check(ped != null, "P: pedestrian placed in the lane"):
		return
	ped.call("cower")
	var hurt := [0.0]
	var cb := func(npc: Node3D, _a: Node, info: Dictionary) -> void:
		if npc == ped and str(info.get("type", "")) == "vehicle":
			hurt[0] += float(info.get("amount", 0.0))
	EventBus.npc_injured.connect(cb)
	Wanted.set_level(1)
	var car: Node3D = pol.call("spawn_unit_at", "cruiser", Transform3D(car_xf.basis, car_xf.origin))
	if not T.check(car != null, "P: cruiser placed 32 m behind the pedestrian (player %.0f m ahead)" % car_xf.origin.distance_to(kerb)):
		EventBus.npc_injured.disconnect(cb)
		return
	var fwd := -car_xf.basis.z
	var t := 0.0
	var passed := false
	var min_gap := INF
	while t < 25.0:
		await T.wait_seconds(0.1)
		t += 0.1
		if not is_instance_valid(car) or not is_instance_valid(ped):
			break
		if int(t * 10.0) % 10 == 0:
			_log_police(p, "P t=%.1f" % t)
		var rel := ped.global_position - car.global_position
		min_gap = minf(min_gap, Vector2(rel.x, rel.z).length())
		if rel.dot(fwd) < -4.0:
			passed = true
		if passed:
			break
	EventBus.npc_injured.disconnect(cb)
	T.check(hurt[0] <= 0.0, "P: the pedestrian was not run over (vehicle damage %.0f, closest %.1f m)" % [hurt[0], min_gap])
	T.check(passed, "P: the cruiser got past the pedestrian (%.1f s)" % t)
	Wanted.clear("cheat")
	if is_instance_valid(ped):
		ped.queue_free()


## Transform `dist` metres down the road from (lane, off), following the straightest next lane.
func _lane_walk(roads: Object, lane: int, off: float, dist: float) -> Transform3D:
	var lanes: Array = roads.get("lanes")
	var id := lane
	var s := off + dist
	for _i in 8:
		var length := float((lanes[id] as Dictionary)["length"])
		if s <= length:
			break
		var nxt: PackedInt32Array = roads.call("get_next_lanes", id)
		if nxt.is_empty():
			s = length
			break
		s -= length
		var here: Transform3D = roads.call("sample_lane", id, length)
		var best := nxt[0]
		var best_dot := -INF
		for n in nxt:
			var there: Transform3D = roads.call("sample_lane", n, 2.0)
			var d := (-here.basis.z).dot(-there.basis.z)
			if d > best_dot:
				best_dot = d
				best = n
		id = best
	return roads.call("sample_lane", id, s)


func _release(p: Node3D) -> void:
	await _reset(p)
	# 0 stars (patrol units): the crews stay seated, nobody deploys towards the player meanwhile
	var plaza := Game.get_location("downtown_plaza")
	var roads: Object = Game.world.get("roads")
	var res: Dictionary = roads.call("random_lane_point", plaza.origin, 60.0, 120.0)
	var res2: Dictionary = roads.call("random_lane_point", plaza.origin, 60.0, 120.0)
	if not T.check(not res.is_empty() and not res2.is_empty(), "X: lanes found"):
		return
	var v1: Node3D = pol.call("spawn_unit_at", "cruiser", res["transform"])
	var x2: Transform3D = res2["transform"]
	if v1 != null and v1.global_position.distance_to(x2.origin) < 8.0:
		x2.origin += Vector3(0.0, 0.0, 12.0)
	var v2: Node3D = pol.call("spawn_unit_at", "cruiser", x2)
	if not T.check(v1 != null and v2 != null, "X: two cruiser units"):
		return
	await T.wait_seconds(0.5)
	# carjacked: the whole crew is put out, the driver is returned
	var c1: Object = v1.get_meta("ai_controller")
	var crew1: Array = (c1.call("living_crew") as Array).duplicate()
	var drv1: Variant = v1.get("driver")
	var r1: Variant = c1.call("release_vehicle", v1, "carjacked")
	T.check(drv1 != null and r1 == drv1, "X: carjacked returns the driver (%s / %s, mode %s)" % [str(drv1), str(r1), str(c1.call("get_mode_name"))])
	var seated := 0
	for c: Variant in crew1:
		if is_instance_valid(c) and (c as Node).get("current_vehicle") != null:
			seated += 1
	T.check(seated == 0 and v1.get("driver") == null and not v1.has_meta("ai_controller"),
			"X: carjacked: crew out (%d still seated), driver null, no ai_controller" % seated)
	# despawn: the seated crew is freed with the unit, nothing is left in the seats
	var c2: Object = v2.get_meta("ai_controller")
	var crew2: Array = (c2.call("living_crew") as Array).duplicate()
	var r2: Variant = c2.call("release_vehicle", v2, "despawn")
	await get_tree().process_frame
	var left := 0
	for c: Variant in crew2:
		if is_instance_valid(c) and not (c as Node).is_queued_for_deletion():
			left += 1
	T.check(r2 == null and v2.get("driver") == null and not v2.has_meta("ai_controller") \
			and (v2.call("get_occupants") as Array).is_empty() and left == 0,
			"X: despawn: no driver, no meta, empty seats, crew freed (%d left)" % left)
	var units: Array = pol.get("units")
	var still := 0
	for u: Variant in units:
		if (u as Object).get("vehicle") == v1 or (u as Object).get("vehicle") == v2:
			still += 1
	T.check(still == 0, "X: both units left the dispatcher's list")
	var vm := Game.get_system("vehicles")
	for v: Node3D in [v1, v2]:
		if is_instance_valid(v) and vm != null and vm.has_method("despawn_vehicle"):
			vm.call("despawn_vehicle", v)
	Wanted.clear("cheat")


func _log_police(p: Node3D, head: String) -> void:
	var line := head
	for u: Variant in pol.get("units"):
		var o := u as Object
		var v: Node3D = o.get("vehicle")
		if v == null or not is_instance_valid(v):
			continue
		var di: Dictionary = o.call("get_debug_info")
		line += " | car d=%.0f %s %s v=%.1f thr=%.2f brk=%.2f st=%.2f blk=%s" % [v.global_position.distance_to(p.global_position),
				str(di["mode"]), str(di["tactic"]), float(di["speed"]), float(di["thr"]), float(di["brk"]), float(di["steer"]), str(di["block"])]
	for n in get_tree().get_nodes_in_group("police"):
		if n is Node3D and is_instance_valid(n) and n.get("current_vehicle") == null and not bool(n.get("is_dead")):
			var b: Variant = n.get("brain")
			line += " | off d=%.0f %s" % [(n as Node3D).global_position.distance_to(p.global_position), str(n.get("state_tag"))]
	for n in get_tree().get_nodes_in_group("gang"):
		if n is Node3D and is_instance_valid(n) and not bool(n.get("is_dead")) and str(n.get("state_tag")) == "combat":
			line += " | GANG fighting d=%.0f" % (n as Node3D).global_position.distance_to(p.global_position)
	T.log_line(line)


func _late_witness(p: Node3D) -> void:
	await _reset(p)
	var witness := Node3D.new()          # stands in for a civilian NPC (only is_dead is read)
	add_child(witness)
	var pos := p.global_position + Vector3(6.0, 0.0, 0.0)
	Wanted.set_level(1)
	await T.wait_seconds(0.3)
	Wanted.bust()
	T.check(Wanted.level == 0 and Wanted.last_clear_reason == "busted", "L: arrested, level cleared")
	await T.wait_seconds(2.0)
	Wanted.report_witnessed("collision_major", pos, witness)
	T.check(Wanted.level == 0, "L: a late call about a crime from before the arrest starts no new episode (level %d)" % Wanted.level)
	# once that window (PENDING_TTL + WITNESS_CALL_GRACE) is over, the AI's own observations count again
	Wanted.debug_time_scale = 20.0
	await T.wait_seconds(1.6)
	Wanted.debug_time_scale = 1.0
	Wanted.report_witnessed("disturbance", pos, witness)
	T.check(Wanted.level == 1, "L: later, an independent witness observation counts again (level %d)" % Wanted.level)
	Wanted.clear("cheat")
	witness.queue_free()
