extends Node
## Helicopter flight test on the real world (runway of Halcyon Airfield).
##   tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 400 -UserArgs '--test=air_heli','--test-timeout=380','--disable=traffic,peds,police'
## The player flies heli_civil through the real input path (Input.action_press):
##   spool up -> climb to 30 m -> hover (drift) -> 150 m forward -> yaw 180 -> soft landing (no damage).
## Then: a hard crash (dropped from 9 m) damages a second helicopter; the autopilot hover_at holds its
## position within a few metres, fly_to arrives, orbit keeps its radius; the parked aircraft exist; the
## police helicopter's searchlight works.

const RUNWAY_Z := -264.0

var _log: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await TestHarness.wait_physics_frames(20)
	var vm := Game.get_system("vehicles")
	if not TestHarness.check(vm != null, "vehicles system present"):
		TestHarness.finish(false, "no vehicles system")
		return
	await _check_parked()

	# ------------------------------------------------------------------ player flight
	var gy := _ground_y(150.0, RUNWAY_Z)
	var heli := Game.spawn_vehicle("heli_civil", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(150.0, gy, RUNWAY_Z)), {"owner_tag": "civilian"})
	if not TestHarness.check(heli != null and heli.get("vehicle_class") == "heli", "heli_civil spawns as a helicopter"):
		TestHarness.finish(false, "spawn failed")
		return
	await TestHarness.wait_seconds(1.0)
	var p := Game.player
	TestHarness.check(p != null, "player exists")
	if p == null:
		TestHarness.finish(false, "no player")
		return
	p.call("teleport", heli.global_position + Vector3(-3.0, 0.2, 0.0), 0.0)
	await TestHarness.wait_physics_frames(5)
	p.call("enter_vehicle", heli, 0, true)
	await TestHarness.wait_seconds(0.6)
	TestHarness.check(heli.get("driver") == p and bool(heli.get("is_player_driven")), "player is the pilot")
	TestHarness.check(bool(heli.get("engine_on")), "engine started on entering")
	var hp0: float = heli.get("health")
	var skill0 := Skills.get_level("flying")
	await TestHarness.wait_seconds(4.6)
	_note("spool: rpm %.2f on_ground %s agl %.2f" % [heli.get("rotor_rpm"), heli.get("on_ground"), heli.get("altitude_agl")])
	TestHarness.check(float(heli.get("rotor_rpm")) > 0.95, "rotor spooled up in ~4 s")
	TestHarness.check(float(heli.get("altitude_agl")) < 0.5, "neutral collective keeps it on the pad while spooling")

	# climb to 30 m
	var t0 := _now()
	Input.action_press("air_throttle_up")
	var ok := await _wait_until(func() -> bool: return float(heli.get("altitude_agl")) >= 30.0, 14.0)
	Input.action_release("air_throttle_up")
	_note("climb to 30 m: %s in %.1f s, vs %.1f" % [ok, _now() - t0, heli.get("vertical_speed")])
	TestHarness.check(ok, "climbed to 30 m AGL")

	# hover: no input for 6 s
	await TestHarness.wait_seconds(2.0)
	var h0: Vector3 = heli.global_position
	await TestHarness.wait_seconds(6.0)
	var h1: Vector3 = heli.global_position
	var drift := Vector2(h1.x - h0.x, h1.z - h0.z).length()
	_note("hover: drift %.2f m, dy %.2f m, agl %.1f" % [drift, h1.y - h0.y, heli.get("altitude_agl")])
	TestHarness.check(drift < 6.0, "hover drift < 6 m over 6 s (%.2f)" % drift)
	TestHarness.check(absf(h1.y - h0.y) < 2.5, "hover holds the height (%.2f m)" % (h1.y - h0.y))

	# 150 m forward
	var start: Vector3 = heli.global_position
	var f0 := _heading_vec(heli)
	t0 = _now()
	Input.action_press("air_pitch_down")
	ok = await _wait_until(func() -> bool: return (heli.global_position - start).dot(f0) >= 150.0, 20.0)
	Input.action_release("air_pitch_down")
	var fwd_d: float = (heli.global_position - start).dot(f0)
	_note("forward: %.1f m in %.1f s, speed %.1f km/h, agl %.1f" % [fwd_d, _now() - t0, heli.get("speed_kmh"), heli.get("altitude_agl")])
	TestHarness.check(ok, "flew 150 m forward")
	TestHarness.check(float(heli.get("altitude_agl")) > 15.0, "kept height in forward flight")
	await TestHarness.wait_seconds(7.0)
	_note("after slowing: %.1f km/h" % heli.get("speed_kmh"))
	TestHarness.check(float(heli.get("speed_kmh")) < 30.0, "slows down by itself with the cyclic centred")

	# yaw 180
	var yaw0 := _heading(heli)
	Input.action_press("air_yaw_right")
	ok = await _wait_until(func() -> bool: return absf(wrapf(_heading(heli) - yaw0, -PI, PI)) > deg_to_rad(172.0), 8.0)
	Input.action_release("air_yaw_right")
	await TestHarness.wait_seconds(1.5)
	var turned := rad_to_deg(absf(wrapf(_heading(heli) - yaw0, -PI, PI)))
	_note("yaw: %.1f deg" % turned)
	TestHarness.check(ok and turned > 160.0, "yawed about 180 degrees (%.1f)" % turned)

	# soft landing
	var hp_before: float = heli.get("health")
	Input.action_press("air_throttle_down")
	ok = await _wait_until(func() -> bool: return bool(heli.get("on_ground")), 25.0)
	await TestHarness.wait_seconds(1.0)
	Input.action_release("air_throttle_down")
	await TestHarness.wait_seconds(1.0)
	_note("landing: %s sink %.2f m/s health %.1f -> %.1f" % [ok, heli.get("last_touchdown_sink"), hp_before, heli.get("health")])
	TestHarness.check(ok, "landed")
	TestHarness.check(float(heli.get("last_touchdown_sink")) < 2.5, "touchdown sink rate < 2.5 m/s")
	TestHarness.check(is_equal_approx(float(heli.get("health")), hp0), "soft landing did no damage")
	TestHarness.check(not bool(heli.get("destroyed")), "not destroyed")
	TestHarness.check(float(heli.get("altitude_agl")) < 0.6, "standing on the ground")
	# camera params / HUD fields
	var cp: Variant = heli.call("get_camera_params")
	TestHarness.check(cp is Dictionary and float((cp as Dictionary).get("distance", 0.0)) > 8.0, "aircraft camera params")
	TestHarness.check(Skills.get_level("flying") > skill0, "flying skill gained XP (%.3f -> %.3f)" % [skill0, Skills.get_level("flying")])
	# soft world limit: pushed outward past Game.WORLD_SOFT_LIMIT, the player is turned back + told
	var notes: Array[String] = []
	var on_note := func(text: String, _kind: String) -> void: notes.append(text)
	EventBus.notification.connect(on_note)
	var far := Game.WORLD_SOFT_LIMIT + 60.0
	heli.call("teleport", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(far, 60.0, 0.0)))
	heli.set("linear_velocity", Vector3(25.0, 0.0, 0.0))
	Input.action_press("air_pitch_down")
	await TestHarness.wait_seconds(6.0)
	Input.action_release("air_pitch_down")
	var lv: Vector3 = heli.get("linear_velocity")
	var hd := rad_to_deg(absf(wrapf(_heading(heli) - (-PI * 0.5), -PI, PI)))
	_note("soft limit: x %.0f, vx %.1f m/s, heading turned %.0f deg, notes %s" % [heli.global_position.x, lv.x, hd, str(notes)])
	TestHarness.check(lv.x < 0.0, "beyond the soft limit the helicopter is pushed back toward the island")
	TestHarness.check(hd > 45.0, "beyond the soft limit the nose turns toward the island")
	var told := false
	for n: String in notes:
		if n.contains("Airspace"):
			told = true
	TestHarness.check(told, "UI.notify tells the player about the airspace limit")
	EventBus.notification.disconnect(on_note)
	gy = _ground_y(60.0, RUNWAY_Z)
	heli.call("teleport", Transform3D(Basis.IDENTITY, Vector3(60.0, gy, RUNWAY_Z)))
	await TestHarness.wait_seconds(1.0)
	p.call("exit_vehicle")
	await TestHarness.wait_seconds(1.5)
	TestHarness.check(p.get("current_vehicle") == null, "player left the helicopter")

	# ------------------------------------------------------------------ hard crash
	gy = _ground_y(-80.0, RUNWAY_Z)
	var crash := Game.spawn_vehicle("heli_civil", Transform3D(Basis.IDENTITY, Vector3(-80.0, gy + 9.0, RUNWAY_Z)), {})
	await TestHarness.wait_seconds(3.0)
	if crash != null:
		var ch: float = crash.get("health")
		var mh: float = crash.get("max_health")
		_note("crash: health %.0f / %.0f destroyed %s sink %.1f" % [ch, mh, crash.get("destroyed"), crash.get("last_touchdown_sink")])
		TestHarness.check(ch < mh * 0.85, "a hard crash (9 m drop) damages it")
	else:
		TestHarness.check(false, "crash heli spawned")

	# ------------------------------------------------------------------ autopilot
	gy = _ground_y(-130.0, RUNWAY_Z)
	var ai := Game.spawn_vehicle("heli_civil", Transform3D(Basis.IDENTITY, Vector3(-130.0, gy, RUNWAY_Z + 6.0)), {})
	if ai == null:
		TestHarness.check(false, "autopilot heli spawned")
		TestHarness.finish(false)
		return
	var target := Vector3(-130.0, 0.0, RUNWAY_Z + 6.0)
	ai.call("hover_at", target, gy + 25.0)
	await TestHarness.wait_seconds(16.0)
	var max_h := 0.0
	var max_v := 0.0
	for i in 60:
		await TestHarness.wait_seconds(0.1)
		var q: Vector3 = ai.global_position
		max_h = maxf(max_h, Vector2(q.x - target.x, q.z - target.z).length())
		max_v = maxf(max_v, absf(q.y - (gy + 25.0)))
	_note("hover_at: max horizontal error %.2f m, max vertical error %.2f m" % [max_h, max_v])
	TestHarness.check(max_h < 4.0, "hover_at holds position within 4 m (%.2f)" % max_h)
	TestHarness.check(max_v < 3.0, "hover_at holds altitude within 3 m (%.2f)" % max_v)

	var dest := Vector3(-30.0, 0.0, RUNWAY_Z - 20.0)
	ai.call("fly_to", dest, gy + 35.0)
	ok = await _wait_until(func() -> bool:
		var q: Vector3 = ai.global_position
		return Vector2(q.x - dest.x, q.z - dest.z).length() < 6.0 and absf(q.y - (gy + 35.0)) < 4.0 and Vector2(ai.linear_velocity.x, ai.linear_velocity.z).length() < 3.0, 25.0)
	_note("fly_to: arrived %s at %s" % [ok, str(ai.global_position)])
	TestHarness.check(ok, "fly_to arrives and stops at the destination")

	ai.call("orbit", dest, 35.0, gy + 30.0, 14.0)
	await TestHarness.wait_seconds(14.0)
	var rmin := INF
	var rmax := 0.0
	var a0 := _bearing(ai.global_position, dest)
	var swept := 0.0
	var last := a0
	for i in 50:
		await TestHarness.wait_seconds(0.2)
		var q: Vector3 = ai.global_position
		var r := Vector2(q.x - dest.x, q.z - dest.z).length()
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
		var a := _bearing(q, dest)
		swept += absf(wrapf(a - last, -PI, PI))
		last = a
	_note("orbit: radius %.1f..%.1f, swept %.0f deg in 10 s" % [rmin, rmax, rad_to_deg(swept)])
	TestHarness.check(rmin > 27.0 and rmax < 43.0, "orbit keeps the radius (35 m +- 8)")
	TestHarness.check(swept > deg_to_rad(120.0), "orbit circles the target")
	ai.call("stop_autopilot")

	# ------------------------------------------------------------------ police searchlight
	var police: Node3D = null
	for v: Node in get_tree().get_nodes_in_group("vehicle"):
		if v.get("spec_id") == "heli_police":
			police = v as Node3D
	if police != null:
		police.call("set_searchlight", true, police.global_position + Vector3(0.0, -2.0, -20.0))
		await TestHarness.wait_seconds(0.5)
		TestHarness.check(bool(police.get("searchlight_on")) and police.find_child("SearchSpot", true, false) != null, "police searchlight switches on")
		police.call("set_searchlight", false)
	else:
		TestHarness.check(false, "a heli_police is parked at the airfield")

	for l: String in _log:
		TestHarness.log_line(l)
	TestHarness.finish(true, "heli flight")


func _check_parked() -> void:
	await TestHarness.wait_physics_frames(5)
	var helis := 0
	var planes := 0
	for v: Node in get_tree().get_nodes_in_group("vehicle"):
		if v.get("owner_tag") != "parked":
			continue
		match str(v.get("vehicle_class")):
			"heli": helis += 1
			"plane": planes += 1
	_note("parked aircraft: %d helicopters, %d planes" % [helis, planes])
	TestHarness.check(helis >= 2, "parked helicopters at the helipads (%d)" % helis)
	TestHarness.check(planes >= 2, "parked planes at the airfield (%d)" % planes)


func _ground_y(x: float, z: float) -> float:
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -20.0, z), Layers.WORLD)
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else Game.ground_height(x, z)


func _heading(n: Node3D) -> float:
	var f := -n.global_transform.basis.z
	return atan2(-f.x, -f.z)


func _heading_vec(n: Node3D) -> Vector3:
	var f := -n.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _bearing(p: Vector3, c: Vector3) -> float:
	return atan2(p.x - c.x, p.z - c.z)


func _now() -> float:
	return _sim_time


var _sim_time: float = 0.0


func _physics_process(delta: float) -> void:
	_sim_time += delta


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if cond.call():
			return true
	return false


func _note(s: String) -> void:
	_log.append(s)
	print("AIR_HELI: ", s)
