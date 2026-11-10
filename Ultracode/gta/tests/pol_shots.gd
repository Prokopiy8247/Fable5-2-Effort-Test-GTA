extends Node
## POLICE screenshots (windowed, short): qa/screenshots/pol_*.png
##   --pol_shot=A  3-star car chase on the Coral Ring: cruisers with sirens behind the player's car
##                 (pol_chase.png, pol_chase_b.png)
##   --pol_shot=B  a 4-star roadblock (two cruisers across the road, barricades, spike strips) and its
##                 officers firing from cover at the (invulnerable) player (pol_roadblock.png,
##                 pol_cover_fire.png)
##   tools\godot.ps1 -Mode window -Frames 640 -TimeoutSec 150 -UserArgs '--test=pol_shots','--pol_shot=A','--test-timeout=120','--seed=4','--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
##   tools\godot.ps1 -Mode window -Frames 640 -TimeoutSec 150 -UserArgs '--test=pol_shots','--pol_shot=B','--test-timeout=120','--seed=4','--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
##   --pol_shot=C  1 star: an officer walks up to the idle, unarmed player with the pistol raised and
##                 cuffs him (pol_arrest.png)
##   --pol_shot=D  4 stars on foot: a SWAT van pulls up, the tactical team gets out and spreads into
##                 cover in pairs (pol_swat.png)
## Headless runs execute the same scenario and only check the setup.

var T: Node
var pol: Node
var _shot: String = "A"
var _drive: bool = false
var _police_shots: int = 0


func _ready() -> void:
	T = TestHarness
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pol_shot="):
			_shot = a.substr(11)
	EventBus.weapon_fired.connect(func(_w: String, shooter: Node, _o: Vector3, _d: Vector3) -> void:
		if shooter != null and is_instance_valid(shooter) and shooter.is_in_group("police"):
			_police_shots += 1)
	await T.wait_seconds(0.5)
	pol = Game.get_system("police")
	var p := Game.player
	if T.check(pol != null and p != null, "police + player present"):
		Game.invulnerable = true
		WorldClock.set_hour(16.5)
		match _shot:
			"A":
				await _chase(p)
			"C":
				await _arrest(p)
			"D":
				await _swat(p)
			_:
				await _roadblock(p)
	_drive = false
	for a in ["move_left", "move_right", "move_forward", "move_back", "aim"]:
		Input.action_release(a)
	Game.invulnerable = false
	T.finish()


func _physics_process(_delta: float) -> void:
	if _drive:
		_autopilot(15.0)


func _ring_lane(x: float) -> Transform3D:
	var roads: Object = Game.world.get("roads")
	var lanes: Array = roads.get("lanes")
	var best := Transform3D()
	var best_d := INF
	for l: Dictionary in lanes:
		if str(l.get("kind", "")) != "arterial" or int(l.get("index", 0)) != 1:
			continue
		var pts: PackedVector3Array = l["points"]
		var cum: PackedFloat32Array = l["cum"]
		for i in pts.size() - 1:
			var dir := pts[i + 1] - pts[i]
			dir.y = 0.0
			if dir.length() < 0.5 or dir.normalized().x < 0.95:
				continue
			for f: float in [0.25, 0.5, 0.75]:
				var q := pts[i].lerp(pts[i + 1], f)
				var d := Vector2(q.x - x, q.z + 190.0).length()
				if d < best_d:
					best_d = d
					best = roads.call("sample_lane", int(l["id"]), cum[i] + (cum[i + 1] - cum[i]) * f)
	return best


func _chase(p: Node3D) -> void:
	var xf := _ring_lane(-150.0)
	var car := Game.spawn_vehicle("sedan", Transform3D(xf.basis, xf.origin + Vector3.UP * 0.4), {"owner_tag": "player", "color": Color(0.85, 0.32, 0.22)})
	if not T.check(car != null, "player car spawned"):
		return
	p.call("teleport", xf.origin + xf.basis.x * 3.0, 0.0)
	await T.wait_seconds(0.2)
	p.call("enter_vehicle", car, 0, true)
	Wanted.set_level(3)
	var fwd := -xf.basis.z
	var c1: Node3D = pol.call("spawn_unit_at", "cruiser", Transform3D(xf.basis, xf.origin - fwd * 16.0 + xf.basis.x * -0.2))
	var c2: Node3D = pol.call("spawn_unit_at", "cruiser", Transform3D(xf.basis, xf.origin - fwd * 30.0 - xf.basis.x * 3.4))
	T.check(c1 != null and c2 != null, "two pursuit cruisers placed behind the player")
	await T.wait_seconds(0.4)
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		Game.camera_rig.call("snap_to", atan2(-fwd.x, -fwd.z))
	_drive = true
	await T.wait_seconds(4.0)
	Input.action_press("look_back")          # the driver glances back at the pursuers
	await T.wait_seconds(0.5)
	await T.shot("pol_chase")
	Input.action_release("look_back")
	await T.wait_seconds(1.0)
	Input.action_press("look_back")
	await T.wait_seconds(0.4)
	await T.shot("pol_chase_b")
	Input.action_release("look_back")
	var d1 := c1.global_position.distance_to(car.global_position) if is_instance_valid(c1) else INF
	var d2 := c2.global_position.distance_to(car.global_position) if is_instance_valid(c2) else INF
	T.check(minf(d1, d2) < 45.0, "a cruiser keeps up with the car (%.1f / %.1f m)" % [d1, d2])
	T.check(bool(c1.get("siren_on")) if is_instance_valid(c1) else false, "siren on in pursuit")
	for c: Node3D in [c1, c2]:
		if is_instance_valid(c) and c.has_meta("ai_controller"):
			T.log_line("cruiser %s" % str((c.get_meta("ai_controller") as Object).call("get_debug_info")))


func _roadblock(p: Node3D) -> void:
	Wanted.set_level(4)
	pol.call("clear_units")
	var pts: Array = Game.world.call("get_spawn_points", "roadblock")
	# a roadblock on the northern Coral Ring stretch, the player 30 m east of it
	var best := -1
	var best_d := INF
	for i in pts.size():
		var q: Vector3 = (pts[i] as Transform3D).origin
		var d := Vector2(q.x + 30.0, q.z + 190.0).length()
		if d < best_d:
			best_d = d
			best = i
	if not T.check(best >= 0, "roadblock spawn point found"):
		return
	var rxf: Transform3D = pts[best]
	var along := -rxf.basis.z
	along.y = 0.0
	along = along.normalized()
	var side := along.cross(Vector3.UP).normalized()
	var stand := rxf.origin + along * 21.0 + side * 4.5
	var rb: Object = pol.call("_build_roadblock", best, rxf, stand - rxf.origin, Wanted.get_level_config(4))
	if not T.check(rb != null, "roadblock built"):
		return
	T.check((rb.get("cars") as Array).size() == 2, "two cruisers across the road")
	T.check((rb.get("spikes") as Array).size() >= 2, "spike strips at 4 stars (%d)" % (rb.get("spikes") as Array).size())
	T.check((rb.get("officers") as Array).size() >= 2, "officers at the roadblock (%d)" % (rb.get("officers") as Array).size())
	var look := rxf.origin - stand
	var yaw := atan2(-look.x, -look.z)          # facing the roadblock
	p.call("teleport", stand, yaw)
	await T.wait_seconds(0.3)
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		Game.camera_rig.call("snap_to", yaw)
	await T.wait_seconds(1.6)
	await T.shot("pol_roadblock")
	# second angle for the firefight: from the kerb, diagonally in front of the cars, so the officers
	# crouched behind them are in view
	var stand2 := rxf.origin + along * 9.0 + side * 9.5
	var look2 := rxf.origin - along * 3.0 - stand2
	var yaw2 := atan2(-look2.x, -look2.z)
	p.call("teleport", stand2, yaw2)
	await T.wait_seconds(0.2)
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		Game.camera_rig.call("snap_to", yaw2)
	# officers engage from cover: take the picture right after a shot (muzzle flash, tracer)
	var t := 0.0
	while t < 9.0 and _police_shots < 5:
		await T.wait_seconds(0.1)
		t += 0.1
	var n0 := _police_shots
	t = 0.0
	while t < 3.0 and _police_shots == n0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await T.shot("pol_cover_fire")
	var crouched := 0
	for o: Variant in rb.get("officers"):
		if o is Node3D and is_instance_valid(o) and bool((o as Node3D).get("is_crouching")):
			crouched += 1
	T.check(_police_shots > 0, "roadblock officers fired (%d shots)" % _police_shots)
	T.log_line("crouched officers %d" % crouched)


## Downtown plaza; the camera looks along `yaw`. Returns the player position.
func _plaza(p: Node3D) -> Vector3:
	pol.call("reset_for_respawn")
	var xf := Game.get_location("downtown_plaza")
	p.call("teleport", xf.origin, 0.0)
	await T.wait_seconds(0.3)
	return p.global_position


func _arrest(p: Node3D) -> void:
	var pp: Vector3 = await _plaza(p)
	# the officer comes from the camera's view direction (north) so his walk and the cuffing are in frame
	var walk: Object = Game.world.get("walk")
	var spot := pp + Vector3(1.5, 0.0, -13.0)
	if walk != null:
		var q: Vector3 = walk.call("get_nearest_point", spot)
		if q != Vector3.INF and q.distance_to(spot) < 6.0:
			spot = q
	Wanted.set_level(1)
	var o: Node3D = pol.call("spawn_unit_at", "officer", Transform3D(Basis.IDENTITY, spot))
	if not T.check(o != null, "officer placed in front of the player"):
		return
	var to_o := spot - pp
	var cam_yaw := atan2(-to_o.x, -to_o.z)          # looking from the player towards the officer
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		Game.camera_rig.call("snap_to", cam_yaw + 0.35)
	var busted := [false]
	EventBus.player_busted.connect(func() -> void: busted[0] = true, CONNECT_ONE_SHOT)
	var t := 0.0
	var shot_done := false
	while t < 14.0 and not busted[0]:
		await T.wait_seconds(0.1)
		t += 0.1
		if not is_instance_valid(o):
			break
		var b: Variant = o.get("brain")
		var prog := float((b as Node).call("get_arrest_progress")) if b is Node else 0.0
		if not shot_done and prog > 0.35:
			shot_done = true
			await T.shot("pol_arrest")
	T.check(shot_done, "the officer was cuffing the player (screenshot taken)")
	T.check(busted[0], "1 star: arrest completed (%.1f s)" % t)


func _swat(p: Node3D) -> void:
	var pp: Vector3 = await _plaza(p)
	Wanted.set_level(4)
	pol.call("clear_units")
	# the van arrives on the nearest lane about 35 m away and stops near the player
	var roads: Object = Game.world.get("roads")
	var res: Dictionary = roads.call("random_lane_point", pp, 18.0, 34.0)
	if not T.check(not res.is_empty(), "lane near the plaza"):
		return
	var lxf: Transform3D = res["transform"]
	var van: Node3D = pol.call("spawn_unit_at", "swat", lxf)
	if not T.check(van != null, "SWAT van placed"):
		return
	var to_van := van.global_position - pp
	var yaw := atan2(-to_van.x, -to_van.z)
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		Game.camera_rig.call("snap_to", yaw)
	var t := 0.0
	var out := 0
	while t < 9.0:
		await T.wait_seconds(0.25)
		t += 0.25
		out = 0
		for n in get_tree().get_nodes_in_group("police"):
			if is_instance_valid(n) and str(n.get("archetype_id")) == "police_swat" and n.get("current_vehicle") == null and not bool(n.get("is_dead")):
				out += 1
		if out >= 3 and t > 2.5:
			break
	T.log_line("SWAT out %d after %.1f s, van %s" % [out, t, str((van.get_meta("ai_controller") as Object).call("get_mode_name")) if is_instance_valid(van) and van.has_meta("ai_controller") else "-"])
	# look at the team (centroid of the tactical officers on foot), not just at the van
	var c := Vector3.ZERO
	var k := 0
	for n in get_tree().get_nodes_in_group("police"):
		if is_instance_valid(n) and str(n.get("archetype_id")) == "police_swat" and n.get("current_vehicle") == null:
			c += (n as Node3D).global_position
			k += 1
	var look_at := c / float(k) if k > 0 else van.global_position
	var to_team := look_at - p.global_position
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		Game.camera_rig.call("snap_to", atan2(-to_team.x, -to_team.z) + 0.25)
	await T.wait_seconds(0.9)
	await T.shot("pol_swat")
	T.check(out >= 2, "tactical officers deployed from the van (%d)" % out)


func _autopilot(speed: float) -> void:
	var car := Game.get_player_vehicle()
	if car == null or pol == null:
		return
	var path: Dictionary = pol.call("_predict_path", 60.0)
	var pts: PackedVector3Array = path.get("pts", PackedVector3Array())
	var cum: PackedFloat32Array = path.get("cum", PackedFloat32Array())
	if pts.size() < 2:
		return
	var spd := float(car.call("get_forward_speed"))
	var aim: Vector3 = pol.call("_path_point", pts, cum, clampf(spd * 0.8 + 6.0, 8.0, 22.0))
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
	if spd < speed:
		Input.action_press("move_forward", clampf(0.3 + (speed - spd) * 0.15, 0.0, 1.0))
	else:
		Input.action_press("move_forward", 0.2)
