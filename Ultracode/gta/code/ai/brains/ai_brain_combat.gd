class_name AiBrainCombat
extends RefCounted
## Reusable combat helper for ANY armed NPC (gang members, police officers, SWAT ...).
## It is not a brain itself: a brain owns one instance per NPC and calls tick() from think().
##
##     var combat := AiBrainCombat.new()          # or load("res://gta/code/ai/brains/ai_brain_combat.gd").new()
##     func think(npc, delta):
##         var status := combat.tick(npc, target, delta, {"lethal": true, "aggression": 0.6})
##
## rules (all optional):
##   lethal: bool = true        false -> never fires a gun: closes in to engage_distance and aims
##                               (fists only when `melee` is true and the target is within reach)
##   aggression: float = 0.5    0 = holds cover, long pauses .. 1 = short pauses, advances / flanks early
##   accuracy: float = 1.0      multiplier on npc.accuracy
##   use_cover: bool = true     look for cover with npc.find_cover_from()
##   hold_fire: bool = false    aim / take cover but never shoot (e.g. waiting for a surrender)
##   melee: bool = lethal       allow fists / melee weapons at close range
##   engage_distance: float     preferred distance without cover (default min(weapon range * 0.5, 18))
##   retreat_health: float = 0.3  below this health ratio retreat once to a farther cover
##   flank: bool = true         allow flanking when the target hides
##   cover_radius: float = 14   search radius for cover
##
## Returns a status String: "no_target", "busy" (down / seated without a drive-by weapon),
## "melee", "hold", "engage", "move_to_cover", "cover", "peek", "reload", "advance", "flank",
## "retreat", "search", "lost" (target unseen for long: the brain should give up or search itself).
##
## State kept between ticks: last_known (Vector3), sees_target (bool), unseen_time (s), state name
## through get_state_name(). Call reset() when the brain switches targets for a fresh start.

enum { S_ENGAGE, S_TO_COVER, S_COVER, S_PEEK, S_ADVANCE, S_FLANK, S_SEARCH, S_RETREAT }
const STATE_NAMES := ["engage", "move_to_cover", "cover", "peek", "advance", "flank", "search", "retreat"]

var state: int = S_ENGAGE
var state_time: float = 0.0
var cover_pos: Vector3 = Vector3.INF
var cover_low: bool = true
var peek_pos: Vector3 = Vector3.INF
var last_known: Vector3 = Vector3.INF
var sees_target: bool = false
var unseen_time: float = 0.0
var seen_time: float = 0.0
var reaction: float = 0.0
var burst_left: int = 0
var burst_pause: float = 0.0
var peeks: int = 0
var retreated: bool = false
var cover_retry: float = 0.0
var exposed_time: float = 0.0

var _target: Node3D = null
var _repath: float = 0.0
var _wait: float = 0.0
var _compromised: int = 0
var _strafe_t: float = 0.0


func reset() -> void:
	state = S_ENGAGE
	state_time = 0.0
	cover_pos = Vector3.INF
	peek_pos = Vector3.INF
	last_known = Vector3.INF
	sees_target = false
	unseen_time = 0.0
	seen_time = 0.0
	reaction = 0.0
	burst_left = 0
	burst_pause = 0.0
	peeks = 0
	retreated = false
	cover_retry = 0.0
	exposed_time = 0.0
	_repath = 0.0
	_wait = 0.0
	_compromised = 0
	_target = null


func get_state_name() -> String:
	return STATE_NAMES[state]


func tick(npc: Node3D, target: Node3D, delta: float, rules: Dictionary = {}) -> String:
	if npc == null or not is_instance_valid(npc) or bool(npc.get("is_dead")):
		return "no_target"
	if target == null or not is_instance_valid(target) or NpcBase.is_dead_node(target) or not target.is_inside_tree():
		_release(npc)
		reset()
		return "no_target"
	if target != _target:
		reset()
		_target = target
	if bool(npc.get("is_down")):
		return "busy"
	var lethal := bool(rules.get("lethal", true))
	var aggression := clampf(float(rules.get("aggression", 0.5)), 0.0, 1.0)
	var acc_mult := float(rules.get("accuracy", 1.0))
	var use_cover := bool(rules.get("use_cover", true))
	var hold_fire := bool(rules.get("hold_fire", false))
	var allow_melee := bool(rules.get("melee", lethal))
	state_time += delta
	_repath -= delta
	cover_retry -= delta
	if burst_pause > 0.0:
		burst_pause -= delta

	var tpos := AiSenses.target_point(target)
	sees_target = npc.call("can_see", target)
	if sees_target:
		last_known = tpos
		unseen_time = 0.0
		seen_time += delta
	else:
		unseen_time += delta
		seen_time = 0.0
		if unseen_time > 1.5:
			reaction = 0.0
	if last_known == Vector3.INF:
		last_known = tpos
	var my := npc.global_position
	var dist := my.distance_to(target.global_position)
	var can_shoot := lethal and not hold_fire and bool(npc.call("has_firearm"))
	var weapon_range: float = float(npc.call("get_weapon_range"))

	# seated: only drive-by shooting
	if npc.get("current_vehicle") != null:
		if can_shoot and sees_target:
			npc.call("aim_at", tpos)
			_try_fire(npc, tpos, acc_mult, delta, aggression)
			return "engage"
		return "busy"

	# close combat: melee weapons, unarmed, or a target that is right on top of us
	var melee_wpn := bool(npc.call("is_melee_weapon"))
	if allow_melee and ((melee_wpn and (lethal or dist < 1.8)) or (not can_shoot and dist < 1.8)):
		return _melee(npc, target, dist)
	if not can_shoot:
		return _hold(npc, target, tpos, dist, rules, weapon_range)

	# badly hurt: one retreat to a farther cover
	var hp_ratio := float(npc.get("health")) / maxf(float(npc.get("max_health")), 1.0)
	if not retreated and use_cover and hp_ratio < float(rules.get("retreat_health", 0.3)):
		retreated = true
		var far: Vector3 = npc.call("find_cover_from", last_known, float(rules.get("cover_radius", 14.0)) * 1.6)
		if far != Vector3.INF and far.distance_to(last_known) > my.distance_to(last_known):
			_take_cover(npc, far, "sprint")
			state = S_RETREAT
			state_time = 0.0
			return "retreat"

	match state:
		S_ENGAGE:
			npc.call("set_crouched", false)
			if use_cover and cover_retry <= 0.0:
				var cp: Vector3 = npc.call("find_cover_from", last_known, float(rules.get("cover_radius", 14.0)))
				if cp != Vector3.INF:
					_take_cover(npc, cp, "sprint" if dist < 25.0 else "run")
					return "move_to_cover"
				cover_retry = 2.0 + randf() * 1.5
			# no cover: fight standing, keep a sensible distance, strafe a little
			var engage_d := float(rules.get("engage_distance", minf(weapon_range * 0.5, 18.0)))
			if sees_target:
				npc.call("aim_at", tpos)
				if dist > engage_d + 4.0 and _repath <= 0.0:
					_repath = 0.8
					npc.call("move_to", _approach_point(my, target.global_position, engage_d), "run")
				elif dist <= engage_d + 4.0:
					_strafe_t -= delta
					if _strafe_t <= 0.0:
						_strafe_t = randf_range(1.2, 2.6)
						if randf() < 0.35 + aggression * 0.4:
							var side := (target.global_position - my).cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
							npc.call("move_to", my + side * randf_range(1.5, 3.0), "walk")
						else:
							npc.call("stop_moving")
				_try_fire(npc, tpos, acc_mult * (0.75 if bool(npc.call("is_moving")) else 1.0), delta, aggression)
				return "engage"
			npc.call("stop_aiming")
			if unseen_time > lerpf(4.0, 1.5, aggression):
				_begin_advance(npc, target, aggression, rules)
				return get_state_name()
			npc.call("face_position", last_known)
			return "engage"
		S_TO_COVER, S_RETREAT:
			if sees_target and aggression > 0.55 and float(npc.get("accuracy")) > 0.3:
				npc.call("aim_at", tpos)
				_try_fire(npc, tpos, acc_mult * 0.6, delta, aggression)
			else:
				npc.call("stop_aiming")
			if bool(npc.call("has_arrived", 0.7)) or (not bool(npc.call("is_moving")) and state_time > 0.5):
				state = S_COVER
				state_time = 0.0
				_wait = _cover_wait(aggression, state == S_RETREAT)
				npc.call("stop_moving")
				npc.call("set_crouched", true)
				return "cover"
			if state_time > 9.0:
				_set_state(S_ENGAGE)
			return "retreat" if state == S_RETREAT else "move_to_cover"
		S_COVER:
			npc.call("stop_aiming")
			npc.call("set_crouched", true)
			npc.call("face_position", last_known)
			if npc.global_position.distance_to(cover_pos) > 1.5 and not bool(npc.call("is_moving")):
				npc.call("move_to", cover_pos, "run")
			# reload behind cover
			var mag := int(npc.call("get_ammo_in_mag"))
			var mag_size := int(npc.call("get_mag_size"))
			if mag_size > 0 and mag < maxi(int(mag_size * 0.4), 1):
				npc.call("reload")
			if bool(npc.call("is_reloading")):
				return "reload"
			# compromised: the target sees our crouched body
			if sees_target and Combat.has_line_of_sight(tpos, npc.call("get_target_position"), [npc, target]):
				_compromised += 1
				if _compromised >= 3:
					_compromised = 0
					cover_retry = 0.0
					_set_state(S_ENGAGE)
					return "engage"
			else:
				_compromised = 0
			if unseen_time > lerpf(10.0, 4.0, aggression) and state_time > 2.0:
				_begin_advance(npc, target, aggression, rules)
				return get_state_name()
			if state_time >= _wait:
				_set_state(S_PEEK)
				peeks += 1
				if cover_low or peek_pos == Vector3.INF:
					npc.call("set_crouched", false)
				else:
					npc.call("set_crouched", false)
					npc.call("move_to", peek_pos, "walk")
			return "cover"
		S_PEEK:
			npc.call("aim_at", last_known if not sees_target else tpos)
			if sees_target:
				if bool(npc.call("is_moving")) and peek_pos != Vector3.INF and npc.global_position.distance_to(peek_pos) < 1.2:
					npc.call("stop_moving")
				_try_fire(npc, tpos, acc_mult, delta, aggression)
			var peek_len := lerpf(1.6, 2.8, aggression)
			var mag2 := int(npc.call("get_ammo_in_mag"))
			if state_time > peek_len or (not sees_target and state_time > 1.3) or (int(npc.call("get_mag_size")) > 0 and mag2 <= 0):
				_set_state(S_COVER)
				_wait = _cover_wait(aggression, false)
				npc.call("stop_aiming")
				if cover_pos != Vector3.INF and npc.global_position.distance_to(cover_pos) > 0.8:
					npc.call("move_to", cover_pos, "walk")
				npc.call("set_crouched", true)
				# too many fruitless peeks: re-evaluate the position
				if peeks >= 4 and unseen_time > 3.0:
					peeks = 0
					_begin_advance(npc, target, aggression, rules)
			return "peek"
		S_ADVANCE, S_FLANK:
			npc.call("set_crouched", false)
			if sees_target:
				npc.call("aim_at", tpos)
				_try_fire(npc, tpos, acc_mult * 0.7, delta, aggression)
				if dist < weapon_range * 0.7 and state_time > 1.0:
					cover_retry = 0.0
					_set_state(S_ENGAGE)
					return "engage"
			else:
				npc.call("stop_aiming")
			if bool(npc.call("has_arrived", 1.5)) or (not bool(npc.call("is_moving")) and state_time > 0.6):
				_set_state(S_SEARCH)
				return "search"
			if state_time > 14.0:
				_set_state(S_SEARCH)
			return get_state_name()
		S_SEARCH:
			npc.call("set_crouched", false)
			if sees_target:
				cover_retry = 0.0
				_set_state(S_ENGAGE)
				return "engage"
			if unseen_time > 22.0:
				return "lost"
			if not bool(npc.call("is_moving")) or _repath <= 0.0:
				_repath = 4.0
				var around := last_known + Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))
				npc.call("move_to", around, "walk")
			return "search"
	return get_state_name()


func _set_state(s: int) -> void:
	state = s
	state_time = 0.0


func _take_cover(npc: Node3D, cp: Vector3, mode: String) -> void:
	cover_pos = cp
	var info: Dictionary = npc.get("last_cover_info")
	cover_low = bool(info.get("low", true))
	peek_pos = info.get("peek", Vector3.INF)
	_set_state(S_TO_COVER)
	npc.call("set_crouched", false)
	npc.call("move_to", cp, mode)


func _cover_wait(aggression: float, defensive: bool) -> float:
	var w := lerpf(2.4, 0.8, aggression) + randf() * 1.2
	return w * (1.8 if defensive else 1.0)


func _begin_advance(npc: Node3D, target: Node3D, aggression: float, rules: Dictionary) -> void:
	npc.call("set_crouched", false)
	var my := npc.global_position
	var tp := target.global_position if last_known == Vector3.INF else Vector3(last_known.x, my.y, last_known.z)
	if bool(rules.get("flank", true)) and randf() < 0.35 + aggression * 0.4:
		var to := my - tp
		to.y = 0.0
		var r := clampf(to.length(), 8.0, 14.0)
		var ang := atan2(to.x, to.z) + (1.0 if randf() < 0.5 else -1.0) * randf_range(0.9, 1.4)
		var fp := tp + Vector3(sin(ang) * r, 0.0, cos(ang) * r)
		_set_state(S_FLANK)
		npc.call("move_to", fp, "run")
	else:
		_set_state(S_ADVANCE)
		npc.call("move_to", tp, "run")


func _approach_point(from: Vector3, to: Vector3, keep: float) -> Vector3:
	var d := from - to
	d.y = 0.0
	if d.length() < 0.1:
		return from
	return to + d.normalized() * keep


func _try_fire(npc: Node3D, tpos: Vector3, acc_mult: float, delta: float, aggression: float) -> void:
	# reaction delay after (re)acquiring the target
	var reaction_need := lerpf(0.9, 0.3, clampf(float(npc.get("accuracy")) * acc_mult, 0.0, 1.0))
	if reaction < reaction_need:
		reaction += delta
		return
	if burst_pause > 0.0:
		return
	if burst_left <= 0:
		var spec: Resource = npc.call("get_weapon_spec")
		var auto := spec != null and str(spec.get("fire_mode")) == "auto"
		burst_left = randi_range(3, 6) if auto else randi_range(1, 3)
	var m := acc_mult
	# the first shots of a sighting are worse, then they settle
	m *= lerpf(0.6, 1.0, clampf(seen_time / 1.5, 0.0, 1.0))
	if _target != null and is_instance_valid(_target):
		var tv: Variant = _target.get("velocity")
		if tv is Vector3 and (tv as Vector3).length() > 4.0:
			m *= 0.75
	if bool(npc.call("fire_at", tpos, m)):
		burst_left -= 1
		if burst_left <= 0:
			burst_pause = randf_range(0.45, 1.2) * (1.4 - aggression * 0.6)


func _melee(npc: Node3D, target: Node3D, dist: float) -> String:
	npc.call("set_crouched", false)
	npc.call("stop_aiming")
	var reach := 1.6
	if bool(npc.call("is_melee_weapon")):
		reach = maxf(float(npc.call("get_weapon_range")), 1.3)
	if dist > reach:
		if _repath <= 0.0 or not bool(npc.call("is_moving")):
			_repath = 0.4
			npc.call("move_to", target.global_position, "sprint" if dist > 6.0 else "run")
	else:
		npc.call("stop_moving")
		npc.call("face_position", target.global_position)
		npc.call("melee", target)
	return "melee"


func _hold(npc: Node3D, target: Node3D, tpos: Vector3, dist: float, rules: Dictionary, weapon_range: float) -> String:
	var engage_d := float(rules.get("engage_distance", 3.0 if not bool(rules.get("lethal", true)) else minf(weapon_range * 0.5, 15.0)))
	npc.call("set_crouched", false)
	if sees_target or dist < 6.0:
		if bool(npc.call("has_firearm")):
			npc.call("aim_at", tpos)
		else:
			npc.call("face_position", target.global_position)
	if dist > engage_d + 1.5:
		if _repath <= 0.0 or not bool(npc.call("is_moving")):
			_repath = 0.6
			npc.call("move_to", _approach_point(npc.global_position, target.global_position, engage_d), "run" if dist > 12.0 else "walk")
	elif dist < engage_d - 1.0:
		npc.call("stop_moving")
	return "hold"


func _release(npc: Node3D) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	if npc.has_method("release_cover"):
		npc.call("release_cover")
	if bool(npc.get("is_dead")):
		return
	npc.call("stop_aiming")
	npc.call("set_crouched", false)
