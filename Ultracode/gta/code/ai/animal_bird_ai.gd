class_name AnimalBirdAi
extends RefCounted
## Brain of a bird (seagull, pigeon): perch / walk / peck on the ground or a roof edge, take off
## from people, vehicles and loud noises (the whole flock goes), fly (flapping and gliding with
## banked turns) to another perch or circle over the coast (gulls), then approach, flare and land.
## Perches come from the wildlife system (coast points, WalkGraph ground points, roof edges found
## by ray casts); cruise altitude clears the buildings under the flight path.

enum S {PERCH, WALK, TAKEOFF, FLY, CIRCLE, LAND}
const NAMES := ["perch", "walk", "takeoff", "fly", "circle", "land"]
const LOUD := ["gunshot", "suppressed_gunshot", "explosion", "scream", "crash", "horn", "siren"]

var s: int = S.PERCH
var t := 0.0
var dur := 10.0
var perch := Vector3.INF
var on_roof := false
var dest := Vector3.INF
var dest_roof := false
var circle_c := Vector3.ZERO
var circle_r := 15.0
var circle_dir := 1.0
var cruise_y := 14.0
var threat := Vector3.INF
var hop_target := Vector3.INF
var flapping := true
var takeoff_delay := -1.0
var _seg_t := 0.0
var _peck_t := 2.0
var _look_t := 1.0
var _call_t := 6.0
var _look := 0.0
var _after_takeoff := S.FLY


func state_name() -> String:
	return String(NAMES[s])


func is_flying() -> bool:
	return s == S.TAKEOFF or s == S.FLY or s == S.CIRCLE or s == S.LAND


func begin(b: AnimalBody, opts: Dictionary) -> void:
	threat = Vector3.INF
	takeoff_delay = -1.0
	hop_target = Vector3.INF
	_call_t = randf_range(3.0, 12.0)
	if bool(opts.get("flying", false)):
		b.fold = 0.0
		b.flap = 1.0
		b.speed = float(b.def.get("cruise_speed", 8.0))
		if b.species == "seagull":
			_start_circle(b, b.global_position)
		else:
			_pick_destination(b)
		return
	perch = b.global_position
	on_roof = bool(opts.get("roof", false))
	b.fold = 1.0
	b.flap = 0.0
	_go(S.PERCH, _boredom(b))


func _go(ns: int, d: float) -> void:
	s = ns
	t = 0.0
	dur = d


func _boredom(b: AnimalBody) -> float:
	var base := randf_range(18.0, 45.0) if b.species == "seagull" else randf_range(22.0, 60.0)
	if WorldClock.is_night():
		base *= 2.5
	return base


# =================================================================================================
# decisions
# =================================================================================================

func think(b: AnimalBody, dt: float) -> void:
	_call_t -= dt
	if s == S.PERCH or s == S.WALK:
		var thr := _threat_point(b)
		if thr != Vector3.INF:
			take_off(b, thr, true)
			return
		if t > dur:
			take_off(b, Vector3.INF, false)
			return
		if _call_t <= 0.0:
			_call_t = randf_range(6.0, 16.0)
			if b.system != null and bool(b.system.call("can_call", b.species)):
				b.play_sound("call", -4.0 if b.species == "seagull" else -9.0, 70.0 if b.species == "seagull" else 35.0)
		return
	if s == S.CIRCLE:
		if t > dur:
			_pick_destination(b)
		elif _call_t <= 0.0:
			_call_t = randf_range(5.0, 12.0)
			if b.system != null and bool(b.system.call("can_call", b.species)):
				b.play_sound("call", -3.0, 80.0)
		return
	if s == S.FLY or s == S.LAND:
		# somebody stands on the landing spot: go elsewhere
		if dest != Vector3.INF and Game.has_player():
			var pp := Game.get_player_position()
			var lim := float(b.def.get("flee_radius", 6.0)) * 1.5
			if not dest_roof and Vector2(pp.x - dest.x, pp.z - dest.z).length() < lim:
				if b.species == "seagull":
					_start_circle(b, b.global_position)
				else:
					_pick_destination(b)


func _threat_point(b: AnimalBody) -> Vector3:
	var pos := b.global_position
	if Game.has_player() and Game.player.get("is_dead") != true:
		var pp := Game.get_player_position()
		var mult := 1.0
		var veh := Game.get_player_vehicle()
		if veh != null:
			mult = 2.4 if Game.get_player_velocity().length() > 3.0 else 1.2
		elif Game.player.get("is_sprinting") == true:
			mult = 1.6
		elif Game.player.get("is_crouching") == true or Game.player.get("in_stealth") == true:
			mult = 0.6
		var r := float(b.def.get("flee_radius", 6.0)) * mult
		if on_roof:
			if pos.distance_to(pp) < 4.0:
				return pp
		elif Vector2(pp.x - pos.x, pp.z - pos.z).length() < r and absf(pp.y - pos.y) < 6.0:
			return pp
	if not on_roof and b.system != null and b.system.has_method("get_threat_vehicles"):
		for e: Array in b.system.call("get_threat_vehicles"):
			var vp: Vector3 = e[0]
			if Vector2(vp.x - pos.x, vp.z - pos.z).length() < 9.0:
				return vp
	return Vector3.INF


func take_off(b: AnimalBody, from: Vector3, alarm: bool) -> void:
	if is_flying() or b.is_dead:
		return
	threat = from
	_go(S.TAKEOFF, 0.75)
	b.fold = 0.0
	b.flap = 1.0
	var away := Vector3.ZERO
	if from != Vector3.INF:
		away = b.global_position - from
		away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	b.yaw = atan2(-away.x, -away.z) + randf_range(-0.4, 0.4)
	b.speed = 0.8
	b.vspeed = 2.6
	if b.species == "seagull" and (alarm or randf() < 0.7):
		_after_takeoff = S.CIRCLE
	else:
		_after_takeoff = S.FLY
	if alarm:
		if b.system != null and bool(b.system.call("can_call", b.species)):
			b.play_sound("alarm", -2.0, 60.0)
		if b.system != null and b.flock_id >= 0:
			b.system.call("flock_alarm", b.flock_id, from, b)


## The flock mates of an alarmed bird follow it into the air after a short random delay.
func alarm_from_flock(b: AnimalBody, from: Vector3) -> void:
	if is_flying() or b.is_dead or takeoff_delay >= 0.0:
		return
	threat = from
	takeoff_delay = randf_range(0.05, 0.45)


func on_noise(b: AnimalBody, pos: Vector3, _radius: float, kind: String, _inst: Node, dist: float) -> void:
	if kind in LOUD:
		if is_flying():
			if s == S.LAND:
				_start_circle(b, b.global_position)
			return
		take_off(b, pos, true)
	elif (kind == "footstep" or kind == "melee") and not on_roof and dist < float(b.def.get("flee_radius", 5.0)):
		take_off(b, pos, true)


func on_damaged(b: AnimalBody, info: Dictionary, _who: Node) -> void:
	take_off(b, info.get("position", b.global_position), true)


func on_provoked(b: AnimalBody, by: Node3D) -> void:
	take_off(b, by.global_position, true)


func flee(b: AnimalBody, from: Vector3, _strength: float) -> void:
	if is_flying():
		_start_circle(b, b.global_position)
	else:
		take_off(b, from, true)


func attack(b: AnimalBody, who: Node3D) -> void:
	flee(b, who.global_position, 1.0)


func calm(_b: AnimalBody) -> void:
	threat = Vector3.INF


func on_death(_b: AnimalBody) -> void:
	s = S.PERCH


func _start_circle(b: AnimalBody, around: Vector3) -> void:
	var c := around
	if b.system != null and b.system.has_method("get_circle_center"):
		c = b.system.call("get_circle_center", b, around)
	circle_c = c
	circle_r = randf_range(10.0, 22.0)
	circle_dir = 1.0 if randf() < 0.5 else -1.0
	var base := _surface_y(b, c.x, c.z)
	var alt := randf_range(float(b.def.get("alt_min", 8.0)), float(b.def.get("alt_max", 20.0)))
	cruise_y = base + alt
	if b.system != null and b.system.has_method("get_obstacle_top"):
		var top := float(b.system.call("get_obstacle_top", c, c, circle_r + 6.0))
		cruise_y = maxf(cruise_y, top + 5.0)
	dest = Vector3.INF
	_go(S.CIRCLE, randf_range(14.0, 34.0))


func _pick_destination(b: AnimalBody) -> void:
	var res: Dictionary = {}
	if b.system != null and b.system.has_method("find_perch"):
		res = b.system.call("find_perch", b)
	if res.is_empty():
		if b.species == "seagull":
			_start_circle(b, b.global_position)
			return
		# pigeons without a perch: land on the ground somewhere ahead
		var f := b.forward() * randf_range(15.0, 30.0)
		var p := b.global_position + f
		res = {"pos": Vector3(p.x, b.ground_y(p.x, p.z), p.z), "roof": false}
	dest = res["pos"]
	dest_roof = bool(res.get("roof", false))
	var pos := b.global_position
	var base := maxf(_surface_y(b, pos.x, pos.z), _surface_y(b, dest.x, dest.z))
	cruise_y = maxf(base + randf_range(float(b.def.get("alt_min", 6.0)), float(b.def.get("alt_max", 14.0)) * 0.7), dest.y + 4.0)
	if b.system != null and b.system.has_method("get_obstacle_top"):
		var top := float(b.system.call("get_obstacle_top", pos, dest, 5.0))
		cruise_y = maxf(cruise_y, top + 4.0)
	_go(S.FLY, 40.0)


func _surface_y(b: AnimalBody, x: float, z: float) -> float:
	return maxf(b.ground_y(x, z), Game.WATER_LEVEL)


# =================================================================================================
# movement
# =================================================================================================

func step(b: AnimalBody, dt: float) -> void:
	t += dt
	if takeoff_delay >= 0.0:
		takeoff_delay -= dt
		if takeoff_delay < 0.0:
			take_off(b, threat, false)
	match s:
		S.PERCH:
			_step_perch(b, dt)
		S.WALK:
			_step_walk(b, dt)
		S.TAKEOFF:
			_step_takeoff(b, dt)
		_:
			_step_flight(b, dt)


func _step_perch(b: AnimalBody, dt: float) -> void:
	b.speed = 0.0
	b.vspeed = 0.0
	b.anim_speed = 0.0
	b.fold = 1.0
	b.flap = move_toward(b.flap, 0.0, dt * 4.0)
	b.anim_pose = "perch"
	b.bank = lerpf(b.bank, 0.0, minf(dt * 6.0, 1.0))
	b.slope_pitch = lerpf(b.slope_pitch, 0.0, minf(dt * 6.0, 1.0))
	if perch == Vector3.INF:
		perch = b.global_position
	var p := perch
	if not on_roof and b.water_depth(p.x, p.z) > 0.2:
		p.y = maxf(p.y, Game.WATER_LEVEL)
	b.global_position = p
	b.velocity = Vector3.ZERO
	_look_t -= dt
	if _look_t <= 0.0:
		_look_t = randf_range(0.5, 2.2)
		_look = randf_range(-1.1, 1.1) if randf() < 0.7 else 0.0
	b.look_yaw = _look
	if not on_roof and b.sim_tier == 0:
		_peck_t -= dt
		if _peck_t <= 0.0:
			_peck_t = randf_range(0.8, 3.0)
			var r := randf()
			if r < 0.5:
				b.start_action("peck", 0.35)
			elif r < 0.8:
				var ang := randf() * TAU
				var hp := perch + Vector3(cos(ang), 0.0, sin(ang)) * randf_range(0.3, 1.1)
				if b.water_depth(hp.x, hp.z) < -0.05 and absf(b.ground_y(hp.x, hp.z) - p.y) < 0.3:
					hop_target = hp
					s = S.WALK


func _step_walk(b: AnimalBody, dt: float) -> void:
	b.fold = 1.0
	b.anim_pose = "walk"
	if hop_target == Vector3.INF:
		s = S.PERCH
		return
	var pos := b.global_position
	var to := hop_target - pos
	to.y = 0.0
	if to.length() < 0.06:
		perch = hop_target
		hop_target = Vector3.INF
		s = S.PERCH
		b.anim_speed = 0.0
		return
	var goal := atan2(-to.x, -to.z)
	b.yaw = AnimalLandAi._turn(b.yaw, goal, deg_to_rad(360.0) * dt)
	var sp := float(b.def.get("walk_speed", 0.4))
	var mv := minf(sp * dt, to.length())
	pos += to.normalized() * mv
	pos.y = b.ground_y(pos.x, pos.z)
	b.global_position = pos
	b.anim_speed = sp
	b.velocity = to.normalized() * sp


func _step_takeoff(b: AnimalBody, dt: float) -> void:
	b.anim_pose = "takeoff"
	b.fold = 0.0
	b.flap = 1.0
	var cruise := float(b.def.get("cruise_speed", 8.0))
	b.speed = move_toward(b.speed, cruise * 0.6, dt * 6.0)
	b.vspeed = move_toward(b.vspeed, 2.2, dt * 2.0)
	var pos := b.global_position + b.forward() * b.speed * dt + Vector3.UP * b.vspeed * dt
	b.global_position = pos
	b.velocity = b.forward() * b.speed + Vector3.UP * b.vspeed
	b.anim_speed = b.speed
	b.slope_pitch = lerpf(b.slope_pitch, 0.35, minf(dt * 5.0, 1.0))
	on_roof = false
	if t >= dur:
		if _after_takeoff == S.CIRCLE:
			_start_circle(b, pos)
		else:
			_pick_destination(b)


func _step_flight(b: AnimalBody, dt: float) -> void:
	var pos := b.global_position
	var cruise := float(b.def.get("cruise_speed", 8.0))
	var goal := Vector3.ZERO
	var goal_speed := cruise
	var goal_y := cruise_y
	var landing_d := INF
	match s:
		S.CIRCLE:
			var ang := atan2(pos.z - circle_c.z, pos.x - circle_c.x) + circle_dir * 0.55
			goal = circle_c + Vector3(cos(ang) * circle_r, 0.0, sin(ang) * circle_r)
			goal_speed = cruise * 0.85
		S.FLY:
			if dest == Vector3.INF:
				_start_circle(b, pos)
				return
			goal = dest
			var dd := Vector2(dest.x - pos.x, dest.z - pos.z).length()
			if dd < 16.0:
				_go(S.LAND, 25.0)
			if t > dur:
				_start_circle(b, pos)
				return
		S.LAND:
			goal = dest
			landing_d = Vector2(dest.x - pos.x, dest.z - pos.z).length()
			goal_y = lerpf(dest.y, cruise_y, clampf((landing_d - 1.2) / 13.0, 0.0, 1.0))
			goal_speed = clampf(landing_d * 0.8, 1.0, cruise * 0.8)
			if t > dur:
				_start_circle(b, pos)
				return
			if landing_d < 1.6 and pos.y - dest.y < 2.5:
				_final_approach(b, dt)
				return
	var desired := atan2(-(goal.x - pos.x), -(goal.z - pos.z))
	var turn := deg_to_rad(float(b.def.get("turn_rate", 180.0)))
	if s == S.LAND and landing_d < 4.0:
		turn *= 2.0
	var prev := b.yaw
	b.yaw = AnimalLandAi._turn(b.yaw, desired, turn * dt)
	var yaw_rate := wrapf(b.yaw - prev, -PI, PI) / maxf(dt, 0.0001)
	b.bank = lerpf(b.bank, clampf(yaw_rate * 0.42, -0.75, 0.75), minf(dt * 3.0, 1.0))
	b.speed = move_toward(b.speed, goal_speed, dt * 4.0)
	var vs_goal := clampf((goal_y - pos.y) * 1.1, -3.2, 3.0)
	b.vspeed = move_toward(b.vspeed, vs_goal, dt * 4.0)
	pos += b.forward() * b.speed * dt + Vector3.UP * b.vspeed * dt
	var floor_y := _surface_y(b, pos.x, pos.z) + (0.0 if s == S.LAND and landing_d < 6.0 else 1.2)
	if s == S.LAND:
		floor_y = minf(floor_y, dest.y)
	if pos.y < floor_y:
		pos.y = floor_y
		b.vspeed = maxf(b.vspeed, 0.0)
	b.global_position = pos
	b.velocity = b.forward() * b.speed + Vector3.UP * b.vspeed
	b.anim_speed = b.speed
	# flapping vs gliding
	_seg_t -= dt
	var must_flap := b.vspeed > 0.7 or b.speed < cruise * 0.7 or (s == S.LAND and landing_d < 5.0)
	if _seg_t <= 0.0:
		var gl := float(b.def.get("glide", 0.4))
		flapping = randf() > gl
		_seg_t = randf_range(1.0, 2.4) if flapping else randf_range(1.2, 3.5) * (0.6 + gl)
	var fl := 1.0 if (flapping or must_flap) else 0.0
	b.flap = move_toward(b.flap, fl, dt * 3.5)
	b.fold = 0.0
	b.anim_pose = "land" if (s == S.LAND and landing_d < 5.0) else ("fly" if b.flap > 0.3 else "glide")
	var pitch := clampf(atan2(b.vspeed, maxf(b.speed, 0.5)) * 0.6, -0.45, 0.45)
	if s == S.LAND and landing_d < 2.5:
		pitch = 0.45
	b.slope_pitch = lerpf(b.slope_pitch, pitch, minf(dt * 4.0, 1.0))
	b.look_yaw = clampf(yaw_rate * 0.15, -0.5, 0.5)


## Last metre and a half: flare and settle straight onto the perch point.
func _final_approach(b: AnimalBody, dt: float) -> void:
	var pos := b.global_position
	var to := dest - pos
	var d := to.length()
	var sp := clampf(d * 1.6, 0.8, 3.0)
	if d <= sp * dt + 0.02:
		_touch_down(b)
		return
	pos += to / d * sp * dt
	b.global_position = pos
	var flat := Vector2(to.x, to.z)
	if flat.length() > 0.05:
		b.yaw = AnimalLandAi._turn(b.yaw, atan2(-to.x, -to.z), deg_to_rad(300.0) * dt)
	b.speed = sp
	b.vspeed = to.y / d * sp
	b.velocity = to / d * sp
	b.anim_speed = sp
	b.flap = move_toward(b.flap, 1.0, dt * 5.0)
	b.fold = 0.0
	b.anim_pose = "land"
	b.bank = lerpf(b.bank, 0.0, minf(dt * 6.0, 1.0))
	b.slope_pitch = lerpf(b.slope_pitch, 0.5, minf(dt * 6.0, 1.0))


func _touch_down(b: AnimalBody) -> void:
	perch = dest
	on_roof = dest_roof
	b.global_position = dest
	b.speed = 0.0
	b.vspeed = 0.0
	b.bank = 0.0
	b.velocity = Vector3.ZERO
	dest = Vector3.INF
	_go(S.PERCH, _boredom(b))
	b.fold = 1.0
