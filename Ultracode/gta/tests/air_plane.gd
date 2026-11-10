extends Node
## Airplane flight test on the real runway of Halcyon Airfield (09-27, z = -264, x -170..210).
##   tools\godot.ps1 -Mode headless -Frames 16000 -TimeoutSec 420 -UserArgs '--test=air_plane','--test-timeout=400','--disable=traffic,peds,police'
## plane_prop, scripted through the AI hooks (set_flight_inputs / set_brakes), full circuit:
##   rest on the gear -> full-throttle take-off roll (lift-off before the runway end, distance printed)
##   -> climb to 60 m -> climb to ~110 m -> throttle off + nose up = stall -> recovery
##   -> banked 180 degree turn -> intercept the extended centre line -> 4 degree glide path -> flare
##   -> touchdown (sink rate, no damage) -> brakes -> stops on the runway.
## plane_jet: take-off roll distance, then a landing from a short final (teleported 900 m out).

const RUNWAY_Z := -264.0
const RWY_W := -170.0
const RWY_E := 210.0
const GLIDE := 0.07                  ## ~4 degrees

var _log: PackedStringArray = []
var _sim: float = 0.0
var _rwy_y: float = 2.53


func _ready() -> void:
	_run.call_deferred()


func _physics_process(delta: float) -> void:
	_sim += delta


func _run() -> void:
	await TestHarness.wait_physics_frames(20)
	var vm := Game.get_system("vehicles")
	if not TestHarness.check(vm != null, "vehicles system present"):
		TestHarness.finish(false)
		return
	var start := Game.get_location("airport_runway_start")
	_rwy_y = _ground_y(start.origin.x, RUNWAY_Z)
	var plane := Game.spawn_vehicle("plane_prop", Transform3D(start.basis, Vector3(start.origin.x, _rwy_y, RUNWAY_Z)), {})
	if not TestHarness.check(plane != null and plane.get("vehicle_class") == "plane", "plane_prop spawns as a plane"):
		TestHarness.finish(false, "spawn failed")
		return
	await TestHarness.wait_seconds(1.5)
	var hp0: float = plane.get("health")
	_note("rest: gear %d agl %.3f pitch %.2f deg y %.3f" % [plane.get("gear_contacts"), plane.get("altitude_agl"), _att(plane).x, plane.global_position.y - _rwy_y])
	TestHarness.check(int(plane.get("gear_contacts")) == 3, "stands on three wheels")
	TestHarness.check(absf(plane.global_position.y - _rwy_y) < 0.06, "rests at the modelled gear height")
	TestHarness.check(absf(_att(plane).x) < 1.5, "level on the ground")

	# ------------------------------------------------------------------ take-off
	var x0: float = plane.global_position.x
	var vs: float = plane.get("stall_speed")
	var lift_x := INF
	var t := 0.0
	while t < 40.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var v: float = plane.get("airspeed")
		var p_in := 0.0 if v < vs * 1.05 else 0.75
		var yaw_in := _centerline_yaw(plane, -PI * 0.5)
		plane.call("set_flight_inputs", p_in, _level_roll(plane, 0.0), yaw_in, 1.0)
		if int(plane.get("gear_contacts")) == 0 and float(plane.get("altitude_agl")) > 1.0:
			lift_x = plane.global_position.x
			break
	var roll_d := lift_x - x0
	_note("prop take-off: lift-off after %.0f m at x %.0f (runway end %.0f), %.1f m/s, %.1f s" % [roll_d, lift_x, RWY_E, plane.get("airspeed"), t])
	TestHarness.check(lift_x < RWY_E, "lifts off before the runway end")
	TestHarness.check(roll_d < 230.0, "prop take-off roll fits comfortably (%.0f m)" % roll_d)

	# ------------------------------------------------------------------ climb to 60 m
	var ok := await _fly_until(plane, func() -> bool: return float(plane.get("altitude_agl")) >= 60.0, 40.0, -PI * 0.5, 0.11, 1.0)
	_note("climb: 60 m AGL %s at x %.0f, %.1f m/s, vs %.1f" % [ok, plane.global_position.x, plane.get("airspeed"), plane.get("vertical_speed")])
	TestHarness.check(ok, "climbs to 60 m")
	ok = await _fly_until(plane, func() -> bool: return plane.global_position.y >= _rwy_y + 110.0, 40.0, -PI * 0.5, 0.11, 1.0)
	await _fly_for(plane, 2.0, -PI * 0.5, 0.0, 0.6)

	# ------------------------------------------------------------------ stall + recovery
	var y_st: float = plane.global_position.y
	var min_v := INF
	var stalled := false
	t = 0.0
	while t < 30.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		min_v = minf(min_v, float(plane.get("airspeed")))
		# idle power, nose held ~16 degrees up: the speed bleeds off until the wing quits
		var hold_in := clampf((16.0 - _att(plane).x) / 10.0, -1.0, 1.0)
		plane.call("set_flight_inputs", hold_in, _level_roll(plane, 0.0), 0.0, 0.0)
		if float(plane.get("stall_amount")) > 0.6:
			stalled = true
			break
	var att := _att(plane)
	_note("stall: %s after %.1f s at %.1f m/s (stall speed %.1f), aoa %.1f deg, pitch %.1f deg" % [stalled, t, plane.get("airspeed"), vs, plane.get("angle_of_attack"), att.x])
	TestHarness.check(stalled, "throttle off + nose up stalls the wing")
	# hold the stick back a moment: the nose must drop by itself
	var pitch_a := _att(plane).x
	await _hold(plane, 1.5, 1.0, 0.0)
	var pitch_b := _att(plane).x
	_note("stall nose drop: pitch %.1f -> %.1f deg while holding full back stick" % [pitch_a, pitch_b])
	TestHarness.check(pitch_b < pitch_a - 3.0, "the nose drops in the stall")
	var rec_t := 0.0
	var recovered := false
	while rec_t < 20.0:
		await get_tree().physics_frame
		rec_t += get_physics_process_delta_time()
		var g := _gamma(plane)
		var p_in := -0.6 if float(plane.get("stall_amount")) > 0.05 else clampf((0.0 - g) * 3.0, -1.0, 1.0)
		plane.call("set_flight_inputs", p_in, _level_roll(plane, 0.0), 0.0, 1.0)
		if float(plane.get("stall_amount")) < 0.02 and float(plane.get("airspeed")) > vs * 1.25 and g > -0.03:
			recovered = true
			break
	var lost: float = y_st - plane.global_position.y
	_note("recovery: %s in %.1f s, height change %.1f m, agl %.0f m" % [recovered, rec_t, -lost, plane.get("altitude_agl")])
	TestHarness.check(recovered, "recovers from the stall (nose down + power)")
	TestHarness.check(float(plane.get("altitude_agl")) > 15.0, "recovery stays clear of the sea")

	# ------------------------------------------------------------------ banked turn (180)
	await _fly_for(plane, 3.0, -PI * 0.5, 0.0, 0.5)
	var h0 := _heading(plane)
	var max_bank := 0.0
	t = 0.0
	var target_h := wrapf(h0 + PI, -PI, PI)
	while t < 40.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		max_bank = maxf(max_bank, absf(_att(plane).y))
		_control(plane, target_h, _hold_alt_gamma(plane, _rwy_y + 100.0), _speed_throttle(plane, vs * 1.5), 0.62)
		if absf(wrapf(_heading(plane) - target_h, -PI, PI)) < deg_to_rad(8.0):
			break
	var turned := rad_to_deg(absf(wrapf(_heading(plane) - h0, -PI, PI)))
	_note("turn: heading changed %.0f deg in %.1f s, max bank %.0f deg, now at %s" % [turned, t, max_bank, str(plane.global_position.round())])
	TestHarness.check(turned > 150.0, "a banked turn reverses the heading (%.0f deg)" % turned)
	TestHarness.check(max_bank > 20.0, "it banks into the turn (%.0f deg)" % max_bank)

	# ------------------------------------------------------------------ approach + landing
	var landed := await _approach_and_land(plane, "prop", 160.0)
	_note("prop landing: %s" % str(landed))
	TestHarness.check(bool(landed.get("touched", false)), "prop: scripted approach touches down")
	TestHarness.check(bool(landed.get("on_runway", false)), "prop: touches down on the runway")
	TestHarness.check(bool(landed.get("stopped", false)), "prop: stops on the runway")
	TestHarness.check(float(landed.get("sink", 99.0)) < float(plane.get("_touchdown_sink")), "prop: touchdown sink below the damage limit")
	TestHarness.check(float(plane.get("health")) >= hp0 - 1.0, "prop: no damage on landing (%.0f / %.0f)" % [plane.get("health"), hp0])
	vm.call("despawn_vehicle", plane)
	await TestHarness.wait_physics_frames(3)

	# ------------------------------------------------------------------ jet take-off + short final
	var jet := Game.spawn_vehicle("plane_jet", Transform3D(start.basis, Vector3(start.origin.x, _rwy_y, RUNWAY_Z)), {})
	if not TestHarness.check(jet != null, "plane_jet spawns"):
		TestHarness.finish(false)
		return
	await TestHarness.wait_seconds(1.5)
	TestHarness.check(int(jet.get("gear_contacts")) == 3, "jet stands on three wheels")
	var jhp: float = jet.get("health")
	var jvs: float = jet.get("stall_speed")
	x0 = jet.global_position.x
	lift_x = INF
	t = 0.0
	while t < 40.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var v2: float = jet.get("airspeed")
		jet.call("set_flight_inputs", 0.0 if v2 < jvs * 1.05 else 0.7, _level_roll(jet, 0.0), _centerline_yaw(jet, -PI * 0.5), 1.0)
		if int(jet.get("gear_contacts")) == 0 and float(jet.get("altitude_agl")) > 1.0:
			lift_x = jet.global_position.x
			break
	_note("jet take-off: lift-off after %.0f m at x %.0f, %.1f m/s, %.1f s" % [lift_x - x0, lift_x, jet.get("airspeed"), t])
	TestHarness.check(lift_x < RWY_E, "jet lifts off before the runway end")
	TestHarness.check(lift_x - x0 < 320.0, "jet take-off roll fits the runway (%.0f m)" % (lift_x - x0))
	ok = await _fly_until(jet, func() -> bool: return float(jet.get("altitude_agl")) >= 40.0, 20.0, -PI * 0.5, 0.1, 1.0)
	TestHarness.check(ok, "jet climbs out")
	# short final: 900 m east of the touchdown zone, on the glide path, westbound at approach speed
	var td := 150.0
	var fx := td + 900.0
	var fy := _rwy_y + 900.0 * GLIDE
	var west := Basis(Vector3.UP, PI * 0.5)
	jet.call("teleport", Transform3D(west * Basis(Vector3.RIGHT, -0.02), Vector3(fx, fy, RUNWAY_Z)))
	jet.linear_velocity = Vector3(-jvs * 1.3, -jvs * 1.3 * GLIDE, 0.0)
	jet.call("set_flight_inputs", 0.0, 0.0, 0.0, 0.35)
	jet.set("throttle", 0.35)
	var jl := await _approach_and_land(jet, "jet", td)
	_note("jet landing from a short final: %s" % str(jl))
	TestHarness.check(bool(jl.get("touched", false)) and bool(jl.get("on_runway", false)), "jet: touches down on the runway from a short final")
	TestHarness.check(bool(jl.get("stopped", false)), "jet: stops on the runway")
	TestHarness.check(float(jet.get("health")) >= jhp - 1.0, "jet: no damage on landing")
	vm.call("despawn_vehicle", jet)
	await TestHarness.wait_physics_frames(3)

	await _player_input_check(vm)
	for l: String in _log:
		TestHarness.log_line(l)
	TestHarness.finish(true, "plane flight")


## The player's input path: enter a plane, W opens the throttle, the plane rolls, Space brakes, exit.
func _player_input_check(vm: Node) -> void:
	var p := Game.player
	if p == null or not p.has_method("enter_vehicle"):
		_note("player input check SKIPPED: no player in this run")
		return
	var x := -60.0
	var gy := _ground_y(x, RUNWAY_Z)
	var pl := Game.spawn_vehicle("plane_prop", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, gy, RUNWAY_Z)), {})
	if pl == null:
		TestHarness.check(false, "plane for the player check spawned")
		return
	await TestHarness.wait_seconds(0.5)
	p.call("teleport", pl.global_position + Vector3(0.0, 0.2, 4.0), 0.0)
	await TestHarness.wait_physics_frames(3)
	p.call("enter_vehicle", pl, 0, true)
	await TestHarness.wait_seconds(0.5)
	TestHarness.check(bool(pl.get("is_player_driven")), "player sits in the plane")
	Input.action_press("air_throttle_up")
	await TestHarness.wait_seconds(2.2)
	Input.action_release("air_throttle_up")
	var thr: float = pl.get("throttle")
	await TestHarness.wait_seconds(2.0)
	var sp: float = pl.get("airspeed")
	_note("player: throttle %.2f after holding W 2.2 s, %.1f m/s after 2 s more" % [thr, sp])
	TestHarness.check(thr > 0.9, "W opens the throttle (persistent lever)")
	TestHarness.check(sp > 3.0, "the plane rolls under power")
	# close the throttle, then the wheel brakes stop it
	Input.action_press("air_throttle_down")
	await TestHarness.wait_seconds(2.5)
	Input.action_press("handbrake")
	var stopped := false
	var t := 0.0
	while t < 12.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if pl.linear_velocity.length() < 0.3:
			stopped = true
			break
	Input.action_release("air_throttle_down")
	Input.action_release("handbrake")
	_note("player: throttle %.2f, stopped %s after %.1f s of braking" % [pl.get("throttle"), stopped, t])
	TestHarness.check(float(pl.get("throttle")) < 0.05 and stopped, "S closes the throttle and the brakes stop the plane")
	p.call("exit_vehicle")
	await TestHarness.wait_seconds(1.5)
	TestHarness.check(p.get("current_vehicle") == null, "player left the plane")
	vm.call("despawn_vehicle", pl)


# ==============================================================================================
# guidance helpers (test-side autopilot, uses only the public AI hooks)
# ==============================================================================================

## Captures the extended centre line from the east, flies a 4 degree glide path to `td_x`, flares,
## lands, brakes and keeps the centre line. Returns {touched, on_runway, stopped, sink, td_x, stop_x}.
func _approach_and_land(plane: Node3D, tag: String, td_x: float) -> Dictionary:
	var vs: float = plane.get("stall_speed")
	var v_app := vs * 1.3
	var out := {"touched": false, "on_runway": false, "stopped": false, "sink": 99.0}
	var t := 0.0
	var touched := false
	var t_ground := 0.0
	var west := PI * 0.5
	while t < 150.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var p := plane.global_position
		var agl: float = plane.get("altitude_agl")
		var gear: int = plane.get("gear_contacts")
		if not touched and gear >= 2:
			touched = true
			out["touched"] = true
			out["td_x"] = p.x
			out["on_runway"] = p.x > RWY_W and p.x < RWY_E and absf(p.z - RUNWAY_Z) < 12.0
			await TestHarness.wait_physics_frames(2)
			out["sink"] = plane.get("last_touchdown_sink")
			_note("%s touchdown at x %.0f z %.1f, sink %.2f m/s, %.1f m/s" % [tag, p.x, p.z, out["sink"], plane.get("airspeed")])
		if touched:
			# roll-out: nose down, idle, brakes, nose-wheel steering on the centre line
			plane.call("set_flight_inputs", -0.3, _level_roll(plane, 0.0), _centerline_yaw(plane, west), 0.0)
			plane.call("set_brakes", 1.0 if t_ground > 0.6 else 0.0)
			t_ground += dt
			if plane.linear_velocity.length() < 0.4:
				var q := plane.global_position
				out["stopped"] = q.x > RWY_W and q.x < RWY_E and absf(q.z - RUNWAY_Z) < 12.0
				out["stop_x"] = q.x
				plane.call("set_brakes", 0.0)
				return out
			if t_ground > 40.0:
				return out
			continue
		# lateral: carrot on the extended centre line, 350 m ahead (westward) of our projection
		var along := maxf(p.x - 350.0, td_x - 400.0)
		var carrot := Vector3(along, p.y, RUNWAY_Z)
		var d := carrot - p
		var psi_d := atan2(-d.x, -d.z)
		# vertical: glide path to td_x, flare near the ground
		var dist := p.x - td_x
		var y_gp := _rwy_y + maxf(dist, 0.0) * GLIDE
		var lateral := absf(p.z - RUNWAY_Z)
		var gamma_d := -GLIDE + clampf((y_gp - p.y) * 0.025, -0.06, 0.06)
		if lateral > 120.0:
			gamma_d = clampf((maxf(y_gp, _rwy_y + 60.0) - p.y) * 0.02, -0.08, 0.08)
		var thr := _speed_throttle(plane, v_app)
		if agl < 7.0:
			gamma_d = lerpf(-0.012, -GLIDE, clampf((agl - 0.4) / 6.6, 0.0, 1.0))
			thr = 0.0 if agl < 2.5 else minf(thr, 0.3)
		_control(plane, psi_d, gamma_d, thr, 0.45)
	return out


## One step of attitude guidance: heading -> bank -> roll stick; flight-path angle -> pitch stick.
func _control(plane: Node3D, psi_d: float, gamma_d: float, throttle: float, bank_limit: float) -> void:
	var b := plane.global_transform.basis.orthonormalized()
	var fwd := -b.z
	var psi := atan2(-fwd.x, -fwd.z)
	var e := wrapf(psi_d - psi, -PI, PI)
	var bank_d := clampf(-e * 1.6, -bank_limit, bank_limit)
	var att := _att(plane)
	var bank := deg_to_rad(att.y)
	var roll_in := clampf((bank_d - bank) * 2.5, -1.0, 1.0)
	var av: Vector3 = plane.get("angular_velocity")
	var wl: Vector3 = b.inverse() * av
	var g := _gamma(plane)
	var pitch_in := clampf((gamma_d - g) * 4.0 - wl.x * 0.35 + absf(sin(bank)) * 0.15, -1.0, 1.0)
	plane.call("set_flight_inputs", pitch_in, roll_in, 0.0, throttle)


func _fly_until(plane: Node3D, cond: Callable, timeout: float, psi_d: float, gamma_d: float, throttle: float) -> bool:
	var t := 0.0
	while t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_control(plane, psi_d, gamma_d, throttle, 0.5)
		if cond.call():
			return true
	return false


func _fly_for(plane: Node3D, seconds: float, psi_d: float, gamma_d: float, throttle: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_control(plane, psi_d, gamma_d, throttle, 0.5)


func _hold(plane: Node3D, seconds: float, pitch_in: float, throttle: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		plane.call("set_flight_inputs", pitch_in, _level_roll(plane, 0.0), 0.0, throttle)


func _hold_alt_gamma(plane: Node3D, y: float) -> float:
	return clampf((y - plane.global_position.y) * 0.02, -0.08, 0.08)


func _speed_throttle(plane: Node3D, v: float) -> float:
	return clampf(0.45 + (v - float(plane.get("airspeed"))) * 0.1, 0.0, 1.0)


func _level_roll(plane: Node3D, bank_d: float) -> float:
	return clampf((bank_d - deg_to_rad(_att(plane).y)) * 2.5, -1.0, 1.0)


## Nose-wheel / rudder input that keeps the runway centre line (z = RUNWAY_Z) at heading psi_d.
func _centerline_yaw(plane: Node3D, psi_d: float) -> float:
	var b := plane.global_transform.basis.orthonormalized()
	var right := b.x
	right.y = 0.0
	var e_lat := (plane.global_position - Vector3(plane.global_position.x, plane.global_position.y, RUNWAY_Z)).dot(right.normalized())
	var e_psi := wrapf(psi_d - _heading(plane), -PI, PI)
	return clampf(-e_lat * 0.12 - e_psi * 2.5, -1.0, 1.0)


func _att(plane: Node3D) -> Vector2:
	return plane.call("get_attitude_degrees")


func _gamma(plane: Node3D) -> float:
	var v: Vector3 = plane.get("linear_velocity")
	return asin(clampf(v.y / maxf(v.length(), 1.0), -1.0, 1.0))


func _heading(n: Node3D) -> float:
	var f := -n.global_transform.basis.z
	return atan2(-f.x, -f.z)


func _ground_y(x: float, z: float) -> float:
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -20.0, z), Layers.WORLD)
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else Game.ground_height(x, z)


func _note(s: String) -> void:
	_log.append(s)
	print("AIR_PLANE: ", s)
