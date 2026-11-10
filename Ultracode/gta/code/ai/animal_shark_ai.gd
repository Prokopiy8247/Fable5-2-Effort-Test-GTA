class_name AnimalSharkAi
extends RefCounted
## Brain of the shark: patrols the deep water around its home (the wreck basin south of the beach),
## circles a swimmer / diver that comes within its hunting radius (the dorsal fin breaks the surface
## around surface swimmers), tightens the circle, charges, bites once (strong but survivable: 34 hp,
## Dmg type "bite"), retreats, and after two bites leaves the prey alone for a while. Badly hurt it
## flees. It never enters water shallower than the species' min_depth.

enum S {PATROL, CIRCLE, CHARGE, RETREAT, FLEE}
const NAMES := ["patrol", "circle", "charge", "retreat", "flee"]

var s: int = S.PATROL
var t := 0.0
var dur := 10.0
var wp := Vector3.INF
var prey: Node3D = null
var circle_r := 13.0
var circle_dir := 1.0
var bites := 0
var bite_cd := 0.0
var leave_cd := 0.0
var away := Vector3.ZERO
var pitch := 0.0
var forced := false                 ## attack() was called explicitly (test / scripted)


func state_name() -> String:
	return String(NAMES[s])


func begin(b: AnimalBody, _opts: Dictionary) -> void:
	prey = null
	bites = 0
	bite_cd = 0.0
	leave_cd = 0.0
	forced = false
	_go(S.PATROL, 0.0)
	wp = Vector3.INF
	b.speed = float(b.def.get("swim_speed", 1.6))


func _go(ns: int, d: float) -> void:
	s = ns
	t = 0.0
	dur = d


func think(b: AnimalBody, dt: float) -> void:
	leave_cd -= dt
	match s:
		S.PATROL:
			if leave_cd <= 0.0:
				var cand := _find_prey(b)
				if cand != null:
					_engage(b, cand)
		S.CIRCLE:
			if not _prey_ok(b):
				_drop(b)
			elif t > dur and bite_cd <= 0.0:
				_go(S.CHARGE, 6.0)
				b.play_sound("attack", 2.0, 60.0)
		S.CHARGE:
			if not _prey_ok(b) or t > dur:
				_retreat(b)
		S.RETREAT:
			if t > dur:
				if bites >= 2 and not forced:
					leave_cd = 50.0
					_drop(b)
				elif _prey_ok(b):
					_go(S.CIRCLE, randf_range(7.0, 12.0))
					circle_r = randf_range(10.0, 14.0)
				else:
					_drop(b)
		S.FLEE:
			pass


func _find_prey(b: AnimalBody) -> Node3D:
	if not Game.has_player():
		return null
	var pl := Game.player
	if pl.get("is_dead") == true or Game.get_player_vehicle() != null:
		return null
	if pl.get("is_swimming") != true and pl.get("is_underwater") != true:
		return null
	var hr := float(b.def.get("hunt_radius", 45.0))
	if pl.global_position.distance_to(b.global_position) > hr:
		return null
	if b.water_depth(pl.global_position.x, pl.global_position.z) < 3.0:
		return null
	return pl


func _prey_ok(b: AnimalBody) -> bool:
	if prey == null or not is_instance_valid(prey) or not prey.is_inside_tree() or prey.get("is_dead") == true:
		return false
	var pp := prey.global_position
	if pp.distance_to(b.global_position) > float(b.def.get("hunt_radius", 45.0)) * 1.4:
		return false
	if prey.is_in_group("player"):
		if Game.get_player_vehicle() != null:
			return false
		return prey.get("is_swimming") == true or prey.get("is_underwater") == true
	return pp.y < Game.WATER_LEVEL + 0.2 and b.water_depth(pp.x, pp.z) > 1.0


func _engage(b: AnimalBody, who: Node3D) -> void:
	prey = who
	circle_dir = 1.0 if randf() < 0.5 else -1.0
	circle_r = randf_range(12.0, 15.0)
	_go(S.CIRCLE, randf_range(8.0, 14.0) if not forced else 3.0)
	b.alert = 1.0


func _drop(b: AnimalBody) -> void:
	prey = null
	forced = false
	_go(S.PATROL, 0.0)
	wp = Vector3.INF
	b.alert = 0.0


func _retreat(b: AnimalBody) -> void:
	away = b.forward()
	_go(S.RETREAT, randf_range(6.0, 10.0))


func attack(b: AnimalBody, who: Node3D) -> void:
	forced = true
	bites = 0
	leave_cd = 0.0
	_engage(b, who)


func on_provoked(b: AnimalBody, by: Node3D) -> void:
	if s == S.PATROL:
		_engage(b, by)


func flee(b: AnimalBody, from: Vector3, _strength: float) -> void:
	var d := b.global_position - from
	d.y = 0.0
	away = d.normalized() if d.length() > 0.1 else -b.forward()
	prey = null
	_go(S.FLEE, 30.0)


func calm(b: AnimalBody) -> void:
	_drop(b)
	leave_cd = 20.0


func on_noise(b: AnimalBody, pos: Vector3, _radius: float, kind: String, _inst: Node, dist: float) -> void:
	if kind == "explosion" and dist < 25.0 and s == S.PATROL:
		flee(b, pos, 1.0)


func on_damaged(b: AnimalBody, info: Dictionary, who: Node) -> void:
	if b.health < b.max_health * 0.4:
		flee(b, info.get("position", b.global_position), 1.0)
		return
	if who != null and is_instance_valid(who) and who is Node3D and not who.is_in_group("vehicle"):
		prey = who as Node3D
		if _prey_ok(b):
			_go(S.CHARGE, 6.0)
			bite_cd = 0.0
			return
	flee(b, info.get("position", b.global_position), 1.0)


func on_death(_b: AnimalBody) -> void:
	prey = null


# =================================================================================================
# swimming
# =================================================================================================

func step(b: AnimalBody, dt: float) -> void:
	t += dt
	bite_cd -= dt
	if b.action == "" and b.alert > 0.0:
		b.alert = maxf(b.alert - dt * 0.05, 0.0)
	var pos := b.global_position
	var goal := pos
	var goal_speed := float(b.def.get("swim_speed", 1.6))
	var turn := deg_to_rad(float(b.def.get("turn_rate", 70.0)))
	var pp := Vector3.INF
	if prey != null and is_instance_valid(prey):
		pp = prey.global_position
		if prey.has_method("get_target_position"):
			var tp: Variant = prey.call("get_target_position")
			if tp is Vector3:
				pp = tp
	match s:
		S.PATROL:
			if wp == Vector3.INF or pos.distance_to(wp) < 4.0 or t > 40.0:
				wp = _pick_wp(b)
				t = 0.0
			goal = wp
		S.CIRCLE:
			if pp == Vector3.INF:
				_drop(b)
				return
			var r := lerpf(circle_r, 7.0, clampf(t / maxf(dur, 0.1), 0.0, 1.0))
			var ang := atan2(pos.z - pp.z, pos.x - pp.x) + circle_dir * 0.45
			goal = pp + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
			# surface swimmer: cruise just under the surface so the fin shows; diver: a little below
			goal.y = -0.45 if pp.y > Game.WATER_LEVEL - 1.6 else pp.y - 0.9
			goal_speed = 2.8
			turn *= 1.3
		S.CHARGE:
			if pp == Vector3.INF:
				_retreat(b)
				return
			goal = pp
			goal_speed = float(b.def.get("run_speed", 7.0))
			turn *= 1.8
			var reach := float(b.def.get("bite_range", 2.3))
			if pos.distance_to(pp) < reach and bite_cd <= 0.0:
				_bite(b, pp)
		S.RETREAT:
			goal = pos + away * 10.0
			goal.y = pos.y - 1.0
			goal_speed = 4.0
		S.FLEE:
			goal = pos + away * 12.0
			goal.y = pos.y - 2.0
			goal_speed = float(b.def.get("run_speed", 7.0)) * 0.8
	# keep the goal in deep enough water
	var min_depth := float(b.def.get("min_depth", 6.0))
	if b.water_depth(goal.x, goal.z) < min_depth * 0.7 and s != S.CHARGE:
		var toward_home := b.home - pos
		toward_home.y = 0.0
		goal = pos + toward_home.normalized() * 8.0 if toward_home.length() > 1.0 else b.home
	var seabed := Game.WATER_LEVEL - b.water_depth(goal.x, goal.z)
	goal.y = clampf(goal.y, seabed + 1.3, Game.WATER_LEVEL - 0.45)
	# steer
	var to := goal - pos
	var flat := Vector2(to.x, to.z).length()
	var desired_yaw := atan2(-to.x, -to.z) if flat > 0.05 else b.yaw
	var prev := b.yaw
	b.yaw = AnimalLandAi._turn(b.yaw, desired_yaw, turn * dt)
	var yaw_rate := wrapf(b.yaw - prev, -PI, PI) / maxf(dt, 0.0001)
	var desired_pitch := clampf(atan2(to.y, maxf(flat, 0.5)), -0.6, 0.6)
	pitch = move_toward(pitch, desired_pitch, dt * 0.8)
	var align := cos(wrapf(desired_yaw - b.yaw, -PI, PI))
	b.speed = move_toward(b.speed, goal_speed * clampf(align + 0.3, 0.35, 1.0), dt * (5.0 if s == S.CHARGE else 1.5))
	var dir := Vector3(-sin(b.yaw) * cos(pitch), sin(pitch), -cos(b.yaw) * cos(pitch))
	var np := pos + dir * b.speed * dt
	# never swim into the shallows / out of the water / into the seabed
	if b.water_depth(np.x, np.z) < min_depth * 0.55 and s != S.CHARGE:
		np.x = pos.x
		np.z = pos.z
		b.yaw += turn * dt * circle_dir
	var bed := Game.WATER_LEVEL - b.water_depth(np.x, np.z)
	np.y = clampf(np.y, bed + 0.9, Game.WATER_LEVEL - 0.4)
	b.global_position = np
	b.velocity = dir * b.speed
	b.anim_speed = b.speed
	b.slope_pitch = pitch
	b.bank = lerpf(b.bank, clampf(-yaw_rate * 0.35, -0.5, 0.5), minf(dt * 2.0, 1.0))
	b.anim_pose = "swim"


func _pick_wp(b: AnimalBody) -> Vector3:
	var min_depth := float(b.def.get("min_depth", 6.0))
	for i in 10:
		var ang := randf() * TAU
		var r := randf_range(10.0, 40.0)
		var p := b.home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var depth := b.water_depth(p.x, p.z)
		if depth > min_depth + 1.0:
			p.y = Game.WATER_LEVEL - depth * randf_range(0.35, 0.7)
			return p
	return b.home


func _bite(b: AnimalBody, pp: Vector3) -> void:
	if prey == null or not is_instance_valid(prey):
		return
	var dir := (pp - b.global_position).normalized()
	var info := Dmg.make(float(b.def.get("bite_damage", 34.0)), "bite", b, pp, dir,
			{"impulse": 160.0, "zone": "torso"})
	Dmg.apply(prey, info)
	bites += 1
	bite_cd = float(b.def.get("bite_cooldown", 9.0))
	b.start_action("bite", 0.5)
	b.play_sound("attack", 3.0, 50.0, 0.9)
	Fx.blood(pp, -dir)
	_retreat(b)
