class_name AnimalLandAi
extends RefCounted
## Brain of a land animal (deer, boar, coyote, dog, cat, rabbit, cow).
##
## Calm cycle: idle <-> graze / sniff <-> wander (around the home point; pets in town follow the
## WalkGraph, wild animals stay on natural ground). Threats: the player (flee radius scaled by
## sprinting / crouching / vehicle), moving vehicles, loud noises (EventBus.noise_emitted via the
## system), damage. Temperaments (registry):
##   timid     alert (head up, looks) -> flee
##   docile    only moves away from loud things / close vehicles (cow)
##   charger   boar: charges when cornered (5 m) or provoked, up to 3 passes, then leaves
##   predator  coyote: flees by day, stalks + attacks a person on foot at night, attacks when provoked
##   pet       dog: friendly dogs come over and wag, others bark; strays (and provoked dogs) bite
## Bites go through the Dmg contract (type "bite"). step() runs every physics frame (tier 0/1),
## think() at the tier rate.

enum S {IDLE, WANDER, GRAZE, ALERT, FLEE, CHASE, BARK, STALK, SIT}
const NAMES := ["idle", "wander", "graze", "alert", "flee", "chase", "bark", "stalk", "sit"]
const RAY_MASK := Layers.WORLD | Layers.PROP | Layers.VEHICLE
const ISLAND := 296.0
const LOUD := ["gunshot", "suppressed_gunshot", "explosion", "scream", "crash", "siren", "horn"]

var s: int = S.IDLE
var t := 0.0                        ## time in state
var dur := 3.0
var target := Vector3.INF
var path := PackedVector3Array()
var path_i := 0
var want := 0.0                     ## wanted speed (m/s)
var threat := Vector3.INF
var hunt: Node3D = null             ## attack target
var bite_cd := 0.0
var bark_cd := 0.0
var attack_t := 0.0
var bites := 0
var charges := 0
var charge_pass := false
var avoid := 0.0
var urban := false
var friendly := false
var look_point := Vector3.INF
var _ray_t := 0.0
var _bite_pending := -1.0
var _charge_rolled := false
var _flee_eval := 0.0
var _alarm_cd := 0.0
var _call_cd := 0.0
var _slope_t := 0.0
var _slope_yaw := 1000.0
var _slope_goal := 0.0


func state_name() -> String:
	return String(NAMES[s])


func begin(b: AnimalBody, opts: Dictionary) -> void:
	urban = b.habitat == "urban" and b.species in ["dog", "cat"]
	friendly = b.species == "dog" and not b.stray and randf() < 0.6
	hunt = null
	bites = 0
	charges = 0
	path = PackedVector3Array()
	path_i = 0
	target = Vector3.INF
	avoid = 0.0
	_charge_rolled = false
	_call_cd = randf_range(4.0, 14.0)
	_slope_t = 0.0
	_slope_yaw = 1000.0
	var st := String(opts.get("state", ""))
	if st == "wander":
		_go(S.WANDER, 12.0)
		_pick_wander(b)
	elif st == "graze" and String(b.def.get("graze", "")) != "":
		_go(S.GRAZE, randf_range(5.0, 12.0))
	else:
		_go(S.IDLE if randf() < 0.5 or String(b.def.get("graze", "")) == "" else S.GRAZE, randf_range(1.5, 6.0))


func _go(ns: int, d: float) -> void:
	s = ns
	t = 0.0
	dur = d


# =================================================================================================
# decisions
# =================================================================================================

func think(b: AnimalBody, _dt: float) -> void:
	var d := b.def
	var temper := b.temperament
	var pl := Game.player
	var has_pl: bool = pl != null and is_instance_valid(pl) and pl.get("is_dead") != true
	var ppos := Game.get_player_position()
	var pd := INF
	if has_pl:
		pd = _flat(b.global_position, ppos)
	var veh := Game.get_player_vehicle()
	var in_veh := veh != null
	var mult := 1.0
	if has_pl:
		if in_veh:
			mult = 1.8 if Game.get_player_velocity().length() > 3.0 else 0.9
		elif pl.get("is_sprinting") == true:
			mult = 1.6
		elif pl.get("is_crouching") == true or pl.get("in_stealth") == true:
			mult = 0.5
		if pl.get("is_swimming") == true:
			mult *= 0.4
	var flee_r := float(d.get("flee_radius", 10.0)) * mult
	_alarm_cd -= _dt
	_call_cd -= _dt

	match s:
		S.CHASE, S.STALK:
			_think_attack(b, pd, in_veh)
			return
		S.FLEE:
			_flee_eval -= _dt
			var td := _flat(b.global_position, threat) if threat != Vector3.INF else INF
			var still: bool = has_pl and pd < flee_r * 1.25
			if t > dur and (td > maxf(flee_r, 12.0) * 1.8 or td == INF) and not still:
				_go(S.ALERT, randf_range(1.0, 2.5))
				target = Vector3.INF
				look_point = threat
			elif target == Vector3.INF or _flee_eval <= 0.0:
				if still:
					threat = ppos
				_pick_flee_target(b)
			return
		S.BARK:
			_think_bark(b, pd, ppos, in_veh)
			return

	# --- calm states: look for threats ----------------------------------------------------------
	if _vehicle_threat(b):
		return
	if has_pl and pd < 60.0:
		match temper:
			"timid":
				if pd < flee_r:
					flee(b, ppos, 1.0)
					return
				if pd < flee_r * 1.6 and s != S.ALERT and not in_veh:
					_go(S.ALERT, randf_range(1.5, 3.0))
					look_point = ppos
					target = Vector3.INF
					return
			"docile":
				if pd < 3.0 and pl.get("is_sprinting") == true:
					flee(b, ppos, 0.5)
					return
			"charger":
				if pd < 5.0 and not in_veh and not _charge_rolled:
					_charge_rolled = true
					if randf() < float(d.get("charge_chance", 0.4)):
						attack(b, pl)
						return
				if pd < flee_r:
					flee(b, ppos, 1.0)
					return
			"predator":
				var night := WorldClock.has_method("is_night") and bool(WorldClock.is_night())
				var hr := float(d.get("hunt_radius", 20.0)) * (0.6 if pl.get("is_crouching") == true else 1.0)
				if night and not in_veh and pd < hr and pl.get("is_swimming") != true:
					attack(b, pl)
					return
				if pd < flee_r and (not night or in_veh):
					flee(b, ppos, 1.0)
					return
			"pet":
				_think_pet(b, pd, ppos, in_veh, pl)
				if s == S.BARK or s == S.CHASE or s == S.FLEE:
					return
	if s == S.ALERT:
		if look_point != Vector3.INF and has_pl and pd < flee_r * 1.6:
			look_point = ppos
		if t > dur:
			if has_pl and pd < flee_r * 1.3 and temper == "timid":
				flee(b, ppos, 1.0)
			else:
				_next_idle(b)
		return
	if s == S.SIT:
		if not has_pl or pd > 7.0 or t > dur:
			_next_idle(b)
		else:
			look_point = ppos
		return
	# ambient calls (coyotes at night, dogs now and then)
	if _call_cd <= 0.0:
		_call_cd = randf_range(10.0, 24.0)
		if b.sim_tier <= 1 and (b.species == "coyote" and WorldClock.is_night() or b.species == "dog" and randf() < 0.3):
			b.start_action("bark", 0.3)
			b.play_sound("call", -6.0, 70.0, 1.0)
	if t > dur or (s == S.WANDER and target == Vector3.INF and path_i >= path.size()):
		_next_idle(b)


func _next_idle(b: AnimalBody) -> void:
	look_point = Vector3.INF
	var graze := String(b.def.get("graze", "")) != ""
	var r := randf()
	if s == S.WANDER:
		if graze and r < 0.6:
			_go(S.GRAZE, randf_range(4.0, 12.0))
		else:
			_go(S.IDLE, randf_range(1.5, 5.0))
		target = Vector3.INF
		return
	if r < 0.55:
		_go(S.WANDER, 18.0)
		_pick_wander(b)
	elif graze and r < 0.85:
		_go(S.GRAZE, randf_range(4.0, 10.0))
	else:
		_go(S.IDLE, randf_range(1.5, 4.5))
		if b.species in ["dog", "cat"] and randf() < 0.35:
			_go(S.SIT, randf_range(4.0, 9.0))


func _vehicle_threat(b: AnimalBody) -> bool:
	if b.system == null or not b.system.has_method("get_threat_vehicles"):
		return false
	var lim := 9.0 if b.temperament == "docile" else 16.0
	var vs: Array = b.system.call("get_threat_vehicles")
	var p := b.global_position
	for e: Array in vs:
		var vp: Vector3 = e[0]
		var vv: Vector3 = e[1]
		var dd := _flat(p, vp)
		if dd > lim:
			continue
		var to := Vector3(p.x - vp.x, 0.0, p.z - vp.z)
		if vv.dot(to) > 0.0 or dd < 5.0:
			flee(b, vp, 1.0)
			return true
	return false


func _think_pet(b: AnimalBody, pd: float, ppos: Vector3, in_veh: bool, pl: Node3D) -> void:
	var br := float(b.def.get("bark_radius", 9.0))
	if b.species != "dog":
		if pd < float(b.def.get("flee_radius", 6.0)):
			flee(b, ppos, 1.0)
		return
	var night := bool(WorldClock.is_night())
	if b.stray and night and not in_veh and pd < 10.0:
		attack(b, pl)
		return
	if pd > br:
		return
	if in_veh:
		if pd < 12.0 and s != S.BARK:
			_go(S.BARK, randf_range(4.0, 8.0))
			target = Vector3.INF
		return
	if friendly and pl.get("is_sprinting") != true:
		# come over, sit, wag
		if pd > 2.6:
			if s != S.WANDER or t > 1.0:
				_go(S.WANDER, 8.0)
			path = PackedVector3Array()
			path_i = 0
			var dir := (b.global_position - ppos)
			dir.y = 0.0
			target = ppos + dir.normalized() * 2.0 if dir.length() > 0.1 else ppos
			want = float(b.def.get("trot_speed", 3.0))
		elif s != S.SIT:
			_go(S.SIT, randf_range(5.0, 10.0))
			target = Vector3.INF
		look_point = ppos
		return
	if s != S.BARK:
		_go(S.BARK, randf_range(6.0, 12.0))
		target = Vector3.INF
		bark_cd = 0.2


func _think_bark(b: AnimalBody, pd: float, ppos: Vector3, in_veh: bool) -> void:
	look_point = ppos
	var br := float(b.def.get("bark_radius", 9.0))
	if t > dur or pd > br * 1.7:
		_next_idle(b)
		return
	if not in_veh and pd < 3.0:
		# too close: back off a few metres
		var away := b.global_position - ppos
		away.y = 0.0
		if away.length() > 0.05:
			target = b.global_position + away.normalized() * 3.0
			want = float(b.def.get("trot_speed", 3.0))
	else:
		target = Vector3.INF


func _think_attack(b: AnimalBody, _pd: float, _in_veh: bool) -> void:
	if hunt == null or not is_instance_valid(hunt) or hunt.get("is_dead") == true or not hunt.is_inside_tree():
		hunt = null
		calm(b)
		return
	var hp := _hunt_pos()
	var dd := _flat(b.global_position, hp)
	var hunted_in_vehicle := hunt.is_in_group("player") and Game.get_player_vehicle() != null
	if hunted_in_vehicle:
		hunt = null
		if b.species == "dog":
			_go(S.BARK, randf_range(4.0, 8.0))
		else:
			flee(b, hp, 1.0)
		return
	if dd > 45.0 or attack_t > 28.0:
		hunt = null
		_next_idle(b)
		return
	if hunt.get("is_swimming") == true:
		hunt = null
		_go(S.ALERT, 3.0)
		look_point = hp
		return
	var low := b.health < b.max_health * 0.3
	if (low and b.temperament != "charger") or (b.species == "coyote" and bites >= 3):
		var from := hp
		hunt = null
		flee(b, from, 1.0)
		return
	if s == S.STALK:
		want = float(b.def.get("walk_speed", 1.5)) * 1.4
		target = hp
		if dd < 9.0 or t > 12.0:
			_go(S.CHASE, 30.0)
			b.play_sound("attack", 0.0, 60.0)
		return
	# CHASE
	if b.temperament == "charger":
		if charge_pass:
			if target == Vector3.INF or _flat(b.global_position, target) < 1.2:
				charge_pass = false
				charges += 1
				if charges >= 3:
					var from2 := hp
					hunt = null
					flee(b, from2, 1.0)
					return
				b.play_sound("attack", 0.0, 55.0)
		else:
			target = hp
		want = float(b.def.get("run_speed", 8.0))
		return
	target = hp
	want = float(b.def.get("run_speed", 8.0))


func _hunt_pos() -> Vector3:
	if hunt == null or not is_instance_valid(hunt):
		return Vector3.INF
	if hunt.is_in_group("player"):
		return Game.get_player_position()
	return hunt.global_position


## Attack `target` (player, NPC, a test dummy - anything damageable).
func attack(b: AnimalBody, who: Node3D) -> void:
	if who == null or not is_instance_valid(who):
		return
	var first := hunt != who
	hunt = who
	attack_t = 0.0
	if first:
		bites = 0
		charges = 0
	charge_pass = false
	path = PackedVector3Array()
	path_i = 0
	var dd := _flat(b.global_position, who.global_position)
	if b.species == "coyote" and dd > 10.0 and b.health >= b.max_health:
		_go(S.STALK, 14.0)
	else:
		_go(S.CHASE, 30.0)
		b.play_sound("attack", 0.0, 60.0)
	b.alert = 0.4


func on_provoked(b: AnimalBody, by: Node3D) -> void:
	if b.temperament in ["charger", "predator"] or (b.species == "dog" and (b.stray or randf() < 0.6)):
		attack(b, by)
	else:
		flee(b, by.global_position, 1.0)


func flee(b: AnimalBody, from: Vector3, strength: float) -> void:
	var was := s
	threat = from
	hunt = null
	look_point = Vector3.INF
	path = PackedVector3Array()
	path_i = 0
	_go(S.FLEE, randf_range(4.0, 7.0))
	var run := float(b.def.get("run_speed", 6.0))
	if b.temperament == "docile":
		run = float(b.def.get("trot_speed", 2.4))
	want = lerpf(float(b.def.get("trot_speed", run * 0.5)), run, clampf(strength, 0.0, 1.0))
	_pick_flee_target(b)
	if was != S.FLEE and _alarm_cd <= 0.0:
		_alarm_cd = 3.0
		b.play_sound("alarm", -2.0, 60.0)
	b.alert = 1.0


func calm(b: AnimalBody) -> void:
	hunt = null
	threat = Vector3.INF
	target = Vector3.INF
	path = PackedVector3Array()
	path_i = 0
	_go(S.IDLE, randf_range(1.0, 3.0))
	b.alert = 0.0


func on_noise(b: AnimalBody, pos: Vector3, _radius: float, kind: String, _inst: Node, dist: float) -> void:
	if b.is_dead:
		return
	var loud := kind in LOUD
	if (s == S.CHASE or s == S.STALK) and hunt != null and kind != "explosion":
		return
	if loud:
		if b.temperament == "docile" and kind in ["horn", "siren", "crash"] and dist > 12.0:
			return
		flee(b, pos, 1.0)
		return
	if b.temperament == "timid" and (kind == "footstep" or kind == "melee" or kind == "engine"):
		if s == S.FLEE:
			return
		if dist < float(b.def.get("flee_radius", 8.0)) * 0.8:
			flee(b, pos, 1.0)
		elif s != S.ALERT:
			_go(S.ALERT, randf_range(1.5, 3.0))
			look_point = pos
			target = Vector3.INF


func on_damaged(b: AnimalBody, info: Dictionary, who: Node) -> void:
	var src: Vector3 = info.get("position", b.global_position)
	var w3: Node3D = null
	if who != null and is_instance_valid(who) and who is Node3D and not who.is_in_group("vehicle"):
		w3 = who as Node3D
		src = w3.global_position
	var healthy := b.health > b.max_health * 0.3
	var hit_by_car := String(info.get("type", "")) == "vehicle"
	match b.temperament:
		"charger":
			if w3 != null and healthy and not hit_by_car:
				attack(b, w3)
				return
		"predator":
			if w3 != null and healthy and not hit_by_car and (s == S.CHASE or randf() < 0.65):
				attack(b, w3)
				return
		"pet":
			if b.species == "dog" and w3 != null and healthy and not hit_by_car and (b.stray or randf() < 0.55):
				attack(b, w3)
				return
	flee(b, src, 1.0)


func on_death(_b: AnimalBody) -> void:
	hunt = null
	target = Vector3.INF
	path = PackedVector3Array()


# =================================================================================================
# movement (every physics frame at tier 0/1, at the think rate at tier 2)
# =================================================================================================

func step(b: AnimalBody, dt: float) -> void:
	t += dt
	if s == S.CHASE or s == S.STALK:
		attack_t += dt
	bite_cd -= dt
	bark_cd -= dt
	var d := b.def
	var pos := b.global_position
	# --- path following (pets in town) ---------------------------------------------------------
	if path_i < path.size():
		var pp := path[path_i]
		if _flat(pos, pp) < 0.7:
			path_i += 1
			if path_i < path.size():
				pp = path[path_i]
			else:
				pp = Vector3.INF
		target = pp
		if s == S.WANDER:
			want = float(d.get("walk_speed", 1.0))
	elif s == S.WANDER and target != Vector3.INF:
		want = maxf(want, float(d.get("walk_speed", 1.0))) if want > 0.0 else float(d.get("walk_speed", 1.0))
	var goal := 0.0
	var turn := deg_to_rad(float(d.get("turn_rate", 240.0)))
	var reach := float(d.get("bite_range", 0.9)) + 0.35
	var hp := Vector3.INF
	if (s == S.CHASE or s == S.STALK) and hunt != null and is_instance_valid(hunt):
		hp = _hunt_pos()
	if target != Vector3.INF:
		var dd := _flat(pos, target)
		var arrive := 0.45 + absf(b.speed) * 0.12
		if s == S.CHASE and hp != Vector3.INF and not charge_pass:
			arrive = 0.15 if b.temperament == "charger" else reach * 0.8
		if dd < arrive:
			if s != S.CHASE:
				target = Vector3.INF
		else:
			var desired := _yaw_to(pos, target) + avoid
			b.yaw = _turn(b.yaw, desired, turn * (1.6 if s == S.FLEE or s == S.CHASE else 1.0) * dt)
			var diff := absf(wrapf(desired - b.yaw, -PI, PI))
			goal = want * clampf(1.25 - diff / 1.3, 0.15, 1.0)
			if s != S.FLEE and s != S.CHASE:
				goal = minf(goal, dd * 1.4 + 0.25)
	elif look_point != Vector3.INF or hp != Vector3.INF:
		# turn in place towards what we look at / bite
		var lp := hp if hp != Vector3.INF else look_point
		var desired2 := _yaw_to(pos, lp)
		if absf(wrapf(desired2 - b.yaw, -PI, PI)) > 0.5:
			b.yaw = _turn(b.yaw, desired2, turn * 0.6 * dt)
	# --- bite --------------------------------------------------------------------------------------
	if s == S.CHASE and hp != Vector3.INF:
		var dh := _flat(pos, hp)
		if dh < reach * 1.5 and not charge_pass:
			var desired3 := _yaw_to(pos, hp)
			b.yaw = _turn(b.yaw, desired3, turn * 1.5 * dt)
			if b.temperament != "charger":
				goal = minf(goal, maxf(dh - reach * 0.7, 0.0) * 3.0)
			if dh < reach and bite_cd <= 0.0 and absf(wrapf(desired3 - b.yaw, -PI, PI)) < 0.7 and _bite_pending < 0.0:
				_bite_pending = 0.14
				b.start_action("bite", 0.36)
				bite_cd = float(d.get("bite_cooldown", 1.3)) * randf_range(0.85, 1.2)
	if _bite_pending >= 0.0:
		_bite_pending -= dt
		if _bite_pending < 0.0:
			_do_bite(b)
	# --- speed ---------------------------------------------------------------------------------------
	var run := float(d.get("run_speed", 6.0))
	var acc := maxf(run * 1.8, 3.0)
	b.speed = move_toward(b.speed, goal, (acc if goal > b.speed else acc * 1.7) * dt)
	# --- obstacles (tier 0) ----------------------------------------------------------------------
	if b.sim_tier == 0 and b.speed > 0.3:
		_ray_t -= dt
		if _ray_t <= 0.0:
			_ray_t = 0.2
			_check_ahead(b)
	elif avoid != 0.0:
		avoid = move_toward(avoid, 0.0, dt)
	# --- integrate ------------------------------------------------------------------------------------
	# (height queries cost ~6 us each: an animal standing still makes none)
	var f := b.forward()
	var moved := false
	if b.speed > 0.001:
		var np := pos + f * b.speed * dt
		var ny := b.ground_y(np.x, np.z)
		if _step_ok_h(b, pos, np, ny):
			pos = Vector3(np.x, ny, np.z)
			moved = true
		else:
			b.speed = 0.0
			if s == S.FLEE:
				_pick_flee_target(b)
			elif s != S.CHASE and s != S.STALK:
				target = Vector3.INF
				path = PackedVector3Array()
				path_i = 0
	b.global_position = pos
	b.velocity = f * b.speed
	# slope pitch from the ground under the front and hind legs (20 Hz, only after moving / turning)
	_slope_t -= dt
	if b.sim_tier <= 1 and _slope_t <= 0.0 and (moved or absf(wrapf(b.yaw - _slope_yaw, -PI, PI)) > 0.05):
		_slope_t = 0.05
		_slope_yaw = b.yaw
		var half := float(d.get("length", 1.0)) * 0.4
		var hf := b.ground_y(pos.x + f.x * half, pos.z + f.z * half)
		var hb := b.ground_y(pos.x - f.x * half, pos.z - f.z * half)
		_slope_goal = clampf(atan2(hf - hb, half * 2.0), -0.5, 0.5)
	b.slope_pitch = lerpf(b.slope_pitch, _slope_goal, minf(dt * 8.0, 1.0))
	# --- animation parameters ----------------------------------------------------------------------
	b.anim_speed = b.speed
	var lp2 := look_point
	if hp != Vector3.INF:
		lp2 = hp
	if lp2 != Vector3.INF and b.speed < 2.0:
		b.look_yaw = clampf(wrapf(_yaw_to(pos, lp2) - b.yaw, -PI, PI), -1.0, 1.0)
	else:
		b.look_yaw = 0.0
	match s:
		S.GRAZE:
			b.anim_pose = String(d.get("graze", "")) if String(d.get("graze", "")) != "" else "stand"
			if b.anim_pose == "graze" and fmod(t, 7.0) > 5.6:
				b.anim_pose = "stand"
		S.ALERT:
			b.anim_pose = "alert"
		S.BARK:
			b.anim_pose = "bark"
			if bark_cd <= 0.0 and b.speed < 0.5:
				bark_cd = randf_range(0.8, 1.7)
				b.start_action("bark", 0.3)
				b.play_sound("call", -1.0, 70.0)
		S.STALK:
			b.anim_pose = "stalk"
		S.SIT:
			b.anim_pose = "sit"
		_:
			b.anim_pose = "stand"
	var wag_t := 0.0
	if b.species == "dog":
		wag_t = 1.0 if (friendly and (s == S.SIT or s == S.WANDER and look_point != Vector3.INF)) else (0.25 if s == S.WANDER or s == S.IDLE else 0.0)
	b.wag = move_toward(b.wag, wag_t, dt * 2.0)
	b.alert = move_toward(b.alert, 1.0 if s == S.FLEE else (0.5 if s == S.ALERT else 0.0), dt * 1.5)


func _do_bite(b: AnimalBody) -> void:
	if hunt == null or not is_instance_valid(hunt) or b.is_dead:
		return
	var hp := _hunt_pos()
	var reach := float(b.def.get("bite_range", 0.9)) + 0.35
	if _flat(b.global_position, hp) > reach + 0.45:
		return
	var dir := (hp - b.global_position)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else b.forward()
	var hit := hp + Vector3.UP * (0.5 if hunt.is_in_group("player") or hunt.is_in_group("npc") else 0.3)
	if hunt.has_method("get_target_position"):
		var tp: Variant = hunt.call("get_target_position")
		if tp is Vector3:
			hit = (tp as Vector3).lerp(hp, 0.45)
	var info := Dmg.make(float(b.def.get("bite_damage", 8.0)), "bite", b, hit, dir,
			{"impulse": 35.0 + float(b.def.get("mass", 20.0)) * 0.6, "zone": "limb", "weapon_id": ""})
	Dmg.apply(hunt, info)
	bites += 1
	b.play_sound("attack", 0.0, 50.0, 1.1)
	if b.temperament == "charger":
		# run on past the target, then turn for the next pass
		charge_pass = true
		target = b.global_position + b.forward() * 9.0
		if not _step_ok(b, b.global_position, target):
			target = b.global_position - b.forward() * 6.0


func _check_ahead(b: AnimalBody) -> void:
	var space := b.get_world_3d().direct_space_state if b.is_inside_tree() else null
	if space == null:
		return
	var d := b.def
	var h := clampf(float(d.get("shoulder_height", 0.5)) * 0.6, 0.15, 0.8)
	var look := clampf(b.speed * 0.45, 0.9, 3.5) + float(d.get("length", 0.8)) * 0.5
	var pos := b.global_position
	if _ray_clear(b, space, pos, b.yaw, look, h):
		avoid = move_toward(avoid, 0.0, 0.25)
		return
	for off: float in [0.75, -0.75, 1.45, -1.45, 2.3, -2.3]:
		if _ray_clear(b, space, pos, b.yaw + off, look, h):
			avoid = clampf(avoid + off, -2.6, 2.6)
			return
	avoid = 0.0
	b.yaw += PI * 0.85
	if s == S.WANDER:
		target = Vector3.INF
		path = PackedVector3Array()
		path_i = 0


func _ray_clear(b: AnimalBody, space: PhysicsDirectSpaceState3D, pos: Vector3, yaw: float, look: float, h: float) -> bool:
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var a := pos + Vector3.UP * h
	var e := pos + f * look
	e.y = b.ground_y(e.x, e.z) + h
	var q := PhysicsRayQueryParameters3D.create(a, e, RAY_MASK, [b.get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	var n: Vector3 = hit["normal"]
	return n.y > 0.72      # ground / slope, not a wall or a trunk


func _step_ok(b: AnimalBody, a: Vector3, n: Vector3) -> bool:
	return _step_ok_h(b, a, n, b.ground_y(n.x, n.z))


## Dry land inside the island, no wall-like height jump (kerbs are fine). ny = ground height at n.
func _step_ok_h(b: AnimalBody, a: Vector3, n: Vector3, ny: float) -> bool:
	if absf(n.x) > ISLAND or absf(n.z) > ISLAND:
		return false
	if ny < 0.6 and b.water_depth(n.x, n.z) > -0.02:
		return false
	var dh := absf(ny - a.y)
	return dh <= a.distance_to(Vector3(n.x, a.y, n.z)) * 1.4 + 0.24


func _valid_point(b: AnimalBody, p: Vector3, fleeing: bool) -> bool:
	if absf(p.x) > ISLAND or absf(p.z) > ISLAND:
		return false
	var pos := b.global_position
	var mid := (pos + p) * 0.5
	if b.water_depth(p.x, p.z) > -0.05 or b.water_depth(mid.x, mid.z) > -0.05:
		return false
	var gy := b.ground_y(p.x, p.z)
	var dist := _flat(pos, p)
	if absf(gy - pos.y) > dist * 0.75 + 1.0:
		return false
	if not fleeing and not urban and Game.world != null and Game.world.has_method("get_surface_at"):
		var surf := String(Game.world.get_surface_at(Vector3(p.x, gy, p.z)))
		var wild := b.habitat in ["hill", "wild", "pasture", "beach"]
		if wild and surf in ["asphalt", "concrete", "wood"]:
			return false
	return true


func _pick_wander(b: AnimalBody) -> void:
	path = PackedVector3Array()
	path_i = 0
	target = Vector3.INF
	want = float(b.def.get("walk_speed", 1.0))
	var r := float(b.def.get("wander_radius", 25.0))
	if urban and Game.world != null:
		var walk: Variant = Game.world.get("walk")
		if walk != null and (walk as Object).has_method("random_point"):
			var pt: Vector3 = (walk as Object).call("random_point", b.home, 3.0, r)
			if pt.is_finite():
				var pth: PackedVector3Array = (walk as Object).call("find_path", b.global_position, pt)
				if pth.size() > 1 and pth.size() < 40:
					path = pth
					path_i = 1
					return
				if _flat(b.global_position, pt) < 20.0:
					target = pt
					return
	for i in 7:
		var ang := randf() * TAU
		var rad := sqrt(randf()) * r
		var p := b.home + Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
		if _flat(p, b.global_position) < 2.5:
			continue
		if _valid_point(b, p, false):
			target = p
			return


func _pick_flee_target(b: AnimalBody) -> void:
	_flee_eval = 1.0
	var pos := b.global_position
	var away := Vector3(pos.x - threat.x, 0.0, pos.z - threat.z) if threat != Vector3.INF else Vector3.ZERO
	if away.length() < 0.05:
		away = -b.forward()
	away = away.normalized()
	var dist := randf_range(20.0, 30.0)
	for ang: float in [0.0, 0.45, -0.45, 0.9, -0.9, 1.4, -1.4, 2.1, -2.1]:
		var dir := away.rotated(Vector3.UP, ang)
		var cand := pos + dir * dist
		if _valid_point(b, cand, true):
			target = cand
			return
	target = pos + away * 5.0


static func _flat(a: Vector3, c: Vector3) -> float:
	if not c.is_finite() or not a.is_finite():
		return INF
	return Vector2(a.x - c.x, a.z - c.z).length()


static func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


static func _turn(cur: float, goal: float, max_step: float) -> float:
	var diff := wrapf(goal - cur, -PI, PI)
	return cur + clampf(diff, -max_step, max_step)
