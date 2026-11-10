extends Node
## plr4_parachute - parachute / freefall / aircraft bail-out of the PLAYER module (wave 3, spec 29A),
## headless, in the REAL world:
##
##   pickups   parachute pickups stand at the world's "parachute" spawn points (pickups system)
##   mast      climb-free start on the radio-mast platform (Signal Hill, 26 m): the parachute pickup on
##             the platform is collected, the pack shows on the back, the player walks off the edge ->
##             freefall -> jump deploys (canopy opens, pack used up) -> glide -> lands alive
##   heli      REAL heli_civil 200 m above the airport: sitting in it packs a parachute, the enter key bails
##             out -> freefall (no ragdoll tumble), steering turns the body, terminal speed; jump deploys:
##             canopy, glide ratio ~3:1, toggles turn, the test steers back over the runway, flares near
##             the ground -> GOOD landing (run-out, no damage), flying XP
##   cut       under the canopy the enter key cuts away: the canopy flies off, the player falls again
##   nodeploy  a freefall from 150 m without opening the parachute is lethal (no auto-deploy)
##
##   tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 400 -UserArgs '--test=plr4_parachute','--disable=traffic,peds,police,emergency,wildlife,transit,taxi,activities','--test-timeout=380'

var P: Player = null
var T: Node = null
var parts: PackedStringArray = ["pickups", "mast", "heli", "cut", "nodeploy"]
var died: Array[String] = []
var states_seen: Array[String] = []


func _ready() -> void:
	T = TestHarness
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			parts = a.substr(7).split(",")
	await _run()


func _run() -> void:
	P = Game.player as Player
	if not T.check(P != null, "Game.player is a Player"):
		T.finish(false, "no player")
		return
	EventBus.player_died.connect(func(c: String) -> void: died.append(c))
	EventBus.player_state_changed.connect(func(s: String) -> void: states_seen.append(s))
	Game.invulnerable = false
	await T.wait_physics_frames(10)
	if parts.has("pickups"):
		await _test_pickups()
	if parts.has("mast"):
		await _test_mast()
	if parts.has("heli"):
		await _test_heli()
	if parts.has("cut"):
		await _test_cut()
	if parts.has("nodeploy"):
		await _test_nodeploy()
	_release_all()
	T.finish(true, "parachute: " + ",".join(parts))


# =================================================================================================
# helpers
# =================================================================================================

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "enter_vehicle", "sprint", "crouch", "interact"]:
		Input.action_release(a)


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	while t < timeout:
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
		t += step
	return bool(cond.call())


func _tap(action: String, frames: int = 3) -> void:
	Input.action_press(action)
	await T.wait_physics_frames(frames)
	Input.action_release(action)


func _ground(x: float, z: float) -> float:
	return Game.ground_height(x, z)


## Steers (move_left / move_right) towards `target` (planar). Returns the heading error (rad).
func _steer_to(target: Vector3, dead: float = 0.12) -> float:
	var to := target - P.global_position
	var want := atan2(-to.x, -to.z)
	var diff := angle_difference(P.rotation.y, want)       # + = target to the left
	Input.action_release("move_left")
	Input.action_release("move_right")
	if diff > dead:
		Input.action_press("move_left")
	elif diff < -dead:
		Input.action_press("move_right")
	return diff


## Flies the canopy to `target`, circles over it, then (below 30 m) flies the final leg along `axis`
## (a runway: the way it already points), levels the wing low and flares at `flare_agl`.
## Returns {"landing", "sink", "speed", "damage", "hp_before", "hp_after"}.
func _fly_and_land(target: Vector3, flare_agl: float, timeout: float, axis: Vector3 = Vector3.ZERO) -> Dictionary:
	var st := P.states["parachute"] as PlayerStateParachute
	var hp0 := P.health
	var t := 0.0
	var flaring := false
	var final_aim := Vector3.INF
	while t < timeout and P.state_id == "parachute" and st.phase != PlayerStateParachute.LANDED:
		var agl := P.altitude_agl
		var d := Vector2(target.x - P.global_position.x, target.z - P.global_position.z).length()
		if agl < flare_agl:
			if not flaring:
				flaring = true
				T.log_line("flare at %.2f m AGL (sink %.2f, airspeed %.2f)" % [agl, st.sink, st.airspeed])
			Input.action_release("move_left")
			Input.action_release("move_right")
			Input.action_press("move_back")
		elif agl < 7.0:
			# short final: wings level (turns cost height)
			Input.action_release("move_left")
			Input.action_release("move_right")
		elif agl < 30.0 and axis != Vector3.ZERO:
			if not final_aim.is_finite():
				var fwd := -P.global_basis.z
				final_aim = target + axis * (300.0 if fwd.dot(axis) >= 0.0 else -300.0)
			_steer_to(final_aim, 0.08)
		elif d < 30.0:
			Input.action_release("move_right")
			Input.action_press("move_left")          # circle over the target
		else:
			_steer_to(target)
		await get_tree().physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
	_release_all()
	await T.wait_physics_frames(2)
	return {"landing": st.landing, "sink": st.landing_sink, "speed": st.landing_speed, "damage": st.landing_damage,
			"hp_before": hp0, "hp_after": P.health}


func _ensure_alive_on_ground(at: Vector3) -> void:
	if P.is_dead:
		await _until(func() -> bool: return not P.is_dead, 20.0)
	P.teleport(at + Vector3(0.0, 0.2, 0.0), 0.0)
	P.health = P.max_health
	await T.wait_physics_frames(20)


# =================================================================================================
# pickups at the parachute spawn points
# =================================================================================================

func _test_pickups() -> void:
	var w := Game.world
	if w == null or not w.has_method("get_spawn_points"):
		T.check(false, "world spawn points available")
		return
	var pts: Array = w.call("get_spawn_points", "parachute")
	T.check(pts.size() >= 3, "world has parachute spawn points (%d)" % pts.size())
	var pickups := get_tree().get_nodes_in_group("pickup")
	if Game.get_system("pickups") == null:
		T.log_line("SOFT: pickups system not running - pickup placement not checked")
		return
	var near := 0
	for xf: Variant in pts:
		var o := (xf as Transform3D).origin
		for n: Node in pickups:
			if n is Node3D and (n as Node3D).global_position.distance_to(o) < 4.0 and str(n.get("kind")) == "parachute":
				near += 1
				break
	T.check(near >= pts.size() - 1 and near > 0, "a parachute pickup stands at the spawn points (%d / %d)" % [near, pts.size()])


# =================================================================================================
# radio mast base jump
# =================================================================================================

func _test_mast() -> void:
	var city := Game.get_system("city")
	if city == null or not city.has_method("has_landmark_marker") or not bool(city.call("has_landmark_marker", "radio_mast", "Parachute_Spot")):
		T.check(false, "radio mast landmark with its Parachute_Spot marker")
		return
	P.has_parachute = false
	var spot: Transform3D = city.call("get_landmark_marker", "radio_mast", "Parachute_Spot")
	var centre: Transform3D = city.call("get_landmark_transform", "radio_mast")
	var out := spot.origin - centre.origin
	out.y = 0.0
	out = out.normalized() if out.length_squared() > 0.01 else Vector3.RIGHT
	var yaw := atan2(-out.x, -out.z)
	P.teleport(spot.origin + Vector3(0.0, 0.1, 0.0) - out * 0.3, yaw)
	await T.wait_physics_frames(30)
	T.check(P.state_id == "on_foot" and P.grounded, "standing on the mast platform (state %s, y %.1f, AGL %.1f)" % [P.state_id, P.global_position.y, P.measure_agl()])
	# the platform's parachute pickup (pickups system) or the admin hook
	var got := await _until(func() -> bool: return P.has_parachute, 2.0)
	if Game.get_system("pickups") != null:
		T.check(got, "the parachute pickup on the mast platform is collected")
	if not got:
		P.give_parachute()
	await T.wait_physics_frames(5)
	T.check(P.chute != null and P.chute.pack != null and P.chute.pack.visible, "the pack is shown on the back while a parachute is carried")
	# walk off the edge (outwards, away from the mast core)
	P.camera.snap_to(yaw)
	await T.wait_physics_frames(2)
	Input.action_press("move_forward")
	var ff := await _until(func() -> bool: return P.state_id == "freefall", 4.0)
	Input.action_release("move_forward")
	T.check(ff, "walking off the 26 m platform -> freefall (state %s, AGL %.1f)" % [P.state_id, P.altitude_agl])
	if not ff:
		return
	T.check(states_seen.has("freefall"), "player_state_changed('freefall') announced (HUD altimeter)")
	await T.wait_physics_frames(16)
	await _tap("jump")
	var open := await _until(func() -> bool: return P.state_id == "parachute", 1.0)
	T.check(open, "jump deploys the parachute (state %s)" % P.state_id)
	if not open:
		return
	T.check(not P.has_parachute and P.chute.is_open() and not P.chute.pack.visible, "canopy open, pack used up and hidden")
	T.check(states_seen.has("parachute"), "player_state_changed('parachute') announced")
	var agl_open := P.altitude_agl
	T.log_line("mast: canopy opened at %.1f m AGL" % agl_open)
	# glide downhill (away from the mast, the way we jumped) and land
	var target := spot.origin + out * 60.0
	target.y = _ground(target.x, target.z)
	var r := await _fly_and_land(target, 2.8, 40.0)
	T.log_line("mast landing: %s" % str(r))
	await T.wait_physics_frames(40)
	T.check(not P.is_dead and r["landing"] != "", "mast base jump ends alive on the ground (%s, sink %.2f, speed %.2f, damage %.1f)" % [r["landing"], r["sink"], r["speed"], r["damage"]])
	await _ensure_alive_on_ground(P.global_position)


# =================================================================================================
# helicopter bail-out at 200 m
# =================================================================================================

func _runway_target() -> Vector3:
	var a := Game.get_location("airport_runway_start").origin
	var b := Game.get_location("airport_runway_end").origin
	var m := a.lerp(b, 0.5)
	m.y = _ground(m.x, m.z)
	return m


func _test_heli() -> void:
	var target := _runway_target()
	P.teleport(target + Vector3(0.0, 0.2, 6.0), 0.0)
	P.has_parachute = false
	P.health = P.max_health
	await T.wait_physics_frames(20)
	var heli := Game.spawn_vehicle("heli_civil", Transform3D(Basis.IDENTITY, target + Vector3(-60.0, 200.0, 0.0)), {})
	if not T.check(heli != null, "REAL heli_civil spawned 200 m above the airport"):
		return
	await T.wait_physics_frames(5)
	P.enter_vehicle(heli, 0, true)
	await T.wait_physics_frames(10)
	T.check(P.current_vehicle == heli and P.has_parachute, "sitting in the helicopter packs a parachute (has_parachute %s)" % str(P.has_parachute))
	var hp0 := P.health
	# bail out with the enter key
	await _tap("enter_vehicle")
	var ff := await _until(func() -> bool: return P.state_id == "freefall", 1.0)
	T.check(ff and P.current_vehicle == null, "enter key 200 m up bails out into freefall, not a ragdoll tumble (state %s)" % P.state_id)
	if not ff:
		if is_instance_valid(heli):
			heli.queue_free()
		return
	var fs := P.states["freefall"] as PlayerStateFreefall
	T.check(fs.public_name == "freefall" and P.altitude_agl > 150.0, "freefall with the pack: public 'freefall', altitude_agl %.1f m" % P.altitude_agl)
	await T.wait_physics_frames(20)
	if is_instance_valid(heli):
		heli.queue_free()         # the pilotless aircraft is test equipment: keep it out of the landing zone
	T.check(P.chute != null and P.chute.get("_wind") != null, "wind_fall_loop plays in freefall")
	# steer: move_right turns the body right
	var yaw0 := P.rotation.y
	Input.action_press("move_right")
	await T.wait_seconds(0.8)
	Input.action_release("move_right")
	var turned := angle_difference(yaw0, P.rotation.y)
	T.check(turned < -0.6, "move_right turns the skydiver right (%.0f deg)" % rad_to_deg(turned))
	# dive -> faster; terminal speed
	Input.action_press("move_forward")
	await T.wait_seconds(1.2)
	var vdive := -P.velocity.y
	var hdive := Vector2(P.velocity.x, P.velocity.z).length()
	Input.action_release("move_forward")
	T.check(vdive > 38.0 and hdive > 6.0, "head-down dive: falling %.1f m/s, tracking %.1f m/s forward" % [vdive, hdive])
	T.check(fs.time > 1.5 and not P.is_dead, "still alive in freefall after %.1f s (no auto-deploy so far)" % fs.time)
	# deploy around 110 m
	await _until(func() -> bool: return P.altitude_agl < 110.0 or P.state_id != "freefall", 8.0)
	T.check(P.state_id == "freefall", "no automatic opening on the way down (state %s at %.0f m)" % [P.state_id, P.altitude_agl])
	var speed_before := P.velocity.length()
	await _tap("jump")
	var open := await _until(func() -> bool: return P.state_id == "parachute", 1.0)
	T.check(open, "jump deploys at %.0f m AGL" % P.altitude_agl)
	if not open:
		return
	var st := P.states["parachute"] as PlayerStateParachute
	await _until(func() -> bool: return st.phase == PlayerStateParachute.FLY, 3.0)
	await T.wait_seconds(1.5)
	T.check(st.phase == PlayerStateParachute.FLY and P.velocity.length() < speed_before * 0.4, "canopy braked the fall (%.1f -> %.1f m/s)" % [speed_before, P.velocity.length()])
	var ratio := st.airspeed / maxf(st.sink, 0.01)
	T.check(ratio > 2.4 and ratio < 3.5, "glide ratio %.2f : 1 (airspeed %.1f, sink %.1f)" % [ratio, st.airspeed, st.sink])
	T.check(P.chute.is_open() and P.chute.open_k >= 0.99 and P.chute.get("_flap") != null, "canopy fully inflated, parachute_loop playing")
	# toggles turn the canopy (and cost height)
	var y1 := P.rotation.y
	Input.action_press("move_left")
	await T.wait_seconds(1.5)
	var sink_turn := st.sink
	Input.action_release("move_left")
	T.check(angle_difference(y1, P.rotation.y) > 1.0, "left toggle turns the canopy (%.0f deg in 1.5 s)" % rad_to_deg(angle_difference(y1, P.rotation.y)))
	T.check(sink_turn > 4.0, "turning costs height (sink %.1f m/s in the turn)" % sink_turn)
	T.check(states_seen.has("parachute"), "HUD state 'parachute' announced; altitude_agl %.1f" % P.altitude_agl)
	# fly back over the runway, flare, land
	var xp0 := Skills.get_level("flying")
	var axis := Game.get_location("airport_runway_end").origin - Game.get_location("airport_runway_start").origin
	axis.y = 0.0
	var r := await _fly_and_land(target, 2.6, 90.0, axis.normalized())
	T.log_line("heli landing: %s (at %s)" % [str(r), str(P.global_position)])
	T.check(r["landing"] == "good", "flared landing on the runway is GOOD (%s, sink %.2f m/s, speed %.2f m/s)" % [r["landing"], r["sink"], r["speed"]])
	T.check(P.health >= hp0 - 0.5 and not P.is_dead, "no damage from the good landing (hp %.1f -> %.1f)" % [hp0, P.health])
	var dist := Vector2(target.x - P.global_position.x, target.z - P.global_position.z).length()
	T.check(dist < 90.0, "steered back to the runway (%.0f m from the aim point)" % dist)
	await _until(func() -> bool: return P.state_id == "on_foot", 2.0)
	T.check(P.state_id == "on_foot" and P.has_control(), "run-out ends on foot with control")
	T.check(Skills.get_level("flying") > xp0, "flying skill grew (%.3f -> %.3f)" % [xp0, Skills.get_level("flying")])
	await T.wait_seconds(0.5)
	var drop: Variant = P.chute.get("_drop")
	T.check(drop != null and is_instance_valid(drop), "the released canopy lies collapsed on the ground")
	# an unflared landing (cruise) is a stumble with a little damage - checked through the classifier
	var hp1 := P.health
	P.give_parachute()
	P.teleport(target + Vector3(30.0, 40.0, 0.0), -PI * 0.5)
	await _until(func() -> bool: return P.state_id == "freefall", 3.0)
	await _tap("jump")
	await _until(func() -> bool: return P.state_id == "parachute", 1.0)
	var t := 0.0
	while P.state_id == "parachute" and st.phase != PlayerStateParachute.LANDED and t < 30.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await T.wait_physics_frames(10)
	T.check(st.landing == "stumble" or st.landing == "hard", "a landing without flare is bad: %s (sink %.2f, speed %.2f, damage %.1f)" % [st.landing, st.landing_sink, st.landing_speed, st.landing_damage])
	T.check(P.health < hp1 and not P.is_dead, "... and hurts a little (hp %.1f -> %.1f)" % [hp1, P.health])
	await _ensure_alive_on_ground(target + Vector3(0.0, 0.0, 8.0))


# =================================================================================================
# cut away
# =================================================================================================

func _test_cut() -> void:
	var target := _runway_target()
	P.health = P.max_health
	P.give_parachute()
	P.teleport(target + Vector3(-40.0, 70.0, 10.0), 0.0)
	await _until(func() -> bool: return P.state_id == "freefall", 3.0)
	await _tap("jump")
	var st := P.states["parachute"] as PlayerStateParachute
	await _until(func() -> bool: return P.state_id == "parachute" and st.phase == PlayerStateParachute.FLY, 4.0)
	await T.wait_seconds(0.5)
	await _tap("enter_vehicle")
	await T.wait_physics_frames(4)
	T.check(P.state_id != "parachute" and not P.chute.is_open() and str(P.chute.get("_drop_kind")) == "cut", "enter key under the canopy cuts away (state %s, canopy %s)" % [P.state_id, str(P.chute.get("_drop_kind"))])
	await _ensure_alive_on_ground(target + Vector3(0.0, 0.0, 8.0))


# =================================================================================================
# no deploy -> lethal
# =================================================================================================

func _test_nodeploy() -> void:
	var target := _runway_target()
	died.clear()
	P.health = P.max_health
	P.give_parachute()
	P.teleport(target + Vector3(20.0, 150.0, -10.0), 0.0)
	var ff := await _until(func() -> bool: return P.state_id == "freefall", 3.0)
	T.check(ff and P.has_parachute, "falling from 150 m with a parachute -> freefall")
	var peak := 0.0
	var t := 0.0
	while not P.is_dead and t < 15.0:
		peak = maxf(peak, -P.velocity.y)
		await get_tree().physics_frame
		t += 1.0 / 60.0
	T.check(P.is_dead and died.has("fall"), "never deploying is lethal (dead %s, cause %s, impact ~%.1f m/s)" % [str(P.is_dead), ",".join(died), peak])
	T.check(not P.chute.is_open(), "the parachute never opened by itself")
	# the respawn flow (or the dead state's fallback) brings the player back
	var back := await _until(func() -> bool: return not P.is_dead, 20.0)
	T.check(back, "respawned after the fatal fall")
	await T.wait_seconds(1.0)
