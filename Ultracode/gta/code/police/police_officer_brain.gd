class_name PoliceOfficerBrain
extends Node
## W2.2 brain of a police officer (NpcBase body, archetype "police_officer"). The police system
## spawns officers with Game.spawn_npc(..., {"brain": <this script>, "persistent": true}) and then
## sets `system`, `unit` (PoliceVehicleAi of its car or null), `role` and `post`.
##
## Roles: "beat" (ambient foot patrol around `post`), "crew" (belongs to a car: the vehicle AI deploys
## and recalls it), "foot" (dispatched on foot), "roadblock" (holds `post` behind the roadblock cars).
##
## Behaviour by wanted state (Wanted autoload):
##   0 stars        patrol (beat) / idle at the post / walk away when the system stands units down;
##                  gunfire within earshot is investigated; crimes seen in front of the officer are
##                  reported through Wanted.police_sighting (promotes the pending record at once);
##                  a gun aimed at an officer for > 1 s is reported ("disturbance", direct witness)
##   PURSUIT        engage through AiBrainCombat with the level rules (non-lethal at 1 star unless
##                  Wanted.is_lethal_force_authorized(); lethal from 2 stars), respond to the last
##                  known position when the player is not in sight
##   arrest         levels with "arrest_first" while Wanted.is_player_arrestable(): ONE officer (the
##                  system's arrest claim) walks up with the pistol raised and stays within 2.2 m for
##                  1.8 s -> Wanted.bust(); running away from it reports "resisting" (rate-limited)
##   SEARCH         walks / runs between search points the system spreads inside Wanted.search_radius
##   in a vehicle   passengers fire drive-by shots at 3 stars+ while the car sees the player
## Sightings: continuous line of sight for Wanted.get_recognition_delay() -> police_sighting()
## (throttled by the system). Soft dependencies only (AiBrainCombat is loaded by path).

enum Mode { IDLE, PATROL, INVESTIGATE, RESPOND, ENGAGE, ARREST, SEARCH, BOARD, SEATED, POST, LEAVE }
const MODE_NAMES: Array[String] = ["idle", "patrol", "investigate", "respond", "engage", "arrest", "search",
		"board", "seated", "post", "leave"]

const COMBAT_PATH := "res://gta/code/ai/brains/ai_brain_combat.gd"
const ARREST_RANGE := 2.2
const ARREST_RANGE_VEHICLE := 3.6      ## suspect seated in a stopped car: standing at its side
const ARREST_STALL := 1.5               ## cannot get closer (door blocked, cornered): cuff from here
const ARREST_TIME := 1.8
const ARREST_APPROACH := 10.0
const ARREST_APPROACH_FAR := 24.0
const THREAT_REPORT_TIME := 1.0
const DRIVE_BY_RANGE := 38.0

static var _combat_script: Script = null
static var _combat_checked: bool = false

var system: Node = null
var unit: RefCounted = null            ## PoliceVehicleAi of the officer's car (null = on foot)
var role: String = "foot"              ## "beat", "crew", "foot", "roadblock"
var post: Vector3 = Vector3.INF        ## beat centre / roadblock cover spot
var post_face: Vector3 = Vector3.INF   ## roadblock: where the threat comes from
var standing_down: bool = false
var is_boarding: bool = false
var is_swat: bool = false
var default_weapon: String = "pistol"
var aggression: float = 0.55
var mode: int = Mode.IDLE
var mode_t: float = 0.0
var last_status: String = ""
var sees: bool = false
var seen_t: float = 0.0
var unseen_t: float = 999.0
var arrest_t: float = 0.0
var combat: RefCounted = null

var _rng := RandomNumberGenerator.new()
var _repath: float = 0.0
var _goal: Vector3 = Vector3.INF
var _search_point: Vector3 = Vector3.INF
var _search_wait: float = 0.0
var _search_age: float = 0.0
var _look_t: float = 0.0
var _beat_t: float = 0.0
var _board_vehicle: Node3D = null
var _board_seat: int = 0
var _board_t: float = 0.0
var _board_retry: float = 0.0
var _investigate_pos: Vector3 = Vector3.INF
var _investigate_t: float = 0.0
var _threat_reported: bool = false
var _attack_note_cd: float = 0.0
var _arrest_last_d: float = 99.0
var _arrest_contact: bool = false
var _arrest_stall_t: float = 0.0
var _arrest_best_d: float = INF
var _holster_t: float = 0.0
var _leave_target: Vector3 = Vector3.INF
var _warned: bool = false
var _rules_cache: Array = []
## An NPC (gang member ...) that shot at this officer or a colleague nearby: the officer fights back
## (lethal, own combat state) for NPC_THREAT_TIME after the last attack, before anything else.
var npc_threat: Node3D = null
var _npc_threat_t: float = 0.0
var _threat_combat: RefCounted = null
var _ff_cd: float = 0.0
var _ff_cached: bool = false

const NPC_THREAT_TIME := 14.0
const NPC_THREAT_RANGE := 70.0
const ALLY_ALERT_RADIUS := 35.0


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func _set_mode(m: int) -> void:
	if m != mode:
		mode = m
		mode_t = 0.0


# =================================================================================================
# public (police system / vehicle AI)
# =================================================================================================

## Walk back to `vehicle` and take `seat` (the vehicle AI recalls its crew).
func board(vehicle: Node3D, seat: int) -> void:
	var npc := get_parent() as Node3D
	if npc == null or vehicle == null or not is_instance_valid(vehicle):
		return
	_board_vehicle = vehicle
	_board_seat = seat
	_board_t = 0.0
	_board_retry = 0.0
	is_boarding = true
	_set_mode(Mode.BOARD)
	npc.call("stop_aiming")
	npc.call("set_crouched", false)
	if npc.has_method("enter_vehicle"):
		npc.call("enter_vehicle", vehicle, seat, false)
		if npc.has_method("set_speed_mode"):
			npc.call("set_speed_mode", "run")


## No longer part of a car's crew (left behind, car lost): an officer on foot.
func unlink() -> void:
	unit = null
	is_boarding = false
	_board_vehicle = null
	if role == "crew":
		role = "foot"
	_rules_cache.clear()


func set_standing_down(on: bool) -> void:
	standing_down = on
	if on:
		_leave_target = Vector3.INF


func get_arrest_progress() -> float:
	return clampf(arrest_t / ARREST_TIME, 0.0, 1.0) if mode == Mode.ARREST else 0.0


## An NPC attacked this officer or a colleague nearby (police system broadcast): fight back.
func set_npc_threat(attacker: Node3D) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.is_in_group("police") \
			or attacker.is_in_group("player") or not attacker.is_in_group("npc") or bool(attacker.get("is_dead")):
		return
	if npc_threat != attacker and _threat_combat != null:
		_threat_combat.call("reset")
	npc_threat = attacker
	_npc_threat_t = NPC_THREAT_TIME


# =================================================================================================
# events (W2.2)
# =================================================================================================

func on_event(npc: Node, event: String, data: Dictionary) -> void:
	var n := npc as Node3D
	if n == null:
		return
	match event:
		"spawned":
			_rng.seed = npc.get_instance_id() ^ 0x2f6b9d1
			aggression = _rng.randf_range(0.45, 0.72)
			_on_spawned(n, data)
		"saw_crime":
			# a crime in front of an officer: a sighting right now makes Wanted promote the pending
			# record (no duplicate report). Deferred: we are inside Wanted.report_crime here.
			var inst: Variant = data.get("instigator", null)
			if inst is Node3D and is_instance_valid(inst) and (inst as Node).is_in_group("player") \
					and bool(n.call("can_see", inst)) and system != null and is_instance_valid(system):
				system.call_deferred("report_sighting", n, (inst as Node3D).global_position, true)
		"noise":
			var kind := str(data.get("kind", ""))
			if (kind == "gunshot" or kind == "explosion") and float(data.get("distance", 999.0)) < 75.0:
				var pos: Variant = data.get("position", null)
				if pos is Vector3:
					_investigate_pos = pos
					_investigate_t = 20.0
		"deployed":
			is_boarding = false
			_board_vehicle = null
			arrest_t = 0.0
			_repath = 0.0
			_ensure_weapon(n)
		"vehicle_released":
			is_boarding = false
			_board_vehicle = null
		"damaged":
			# shot by a gang member / another NPC: fight back, and colleagues nearby join in
			var att: Variant = data.get("attacker", null)
			if att is Node3D and is_instance_valid(att) and not (att as Node).is_in_group("police") \
					and not (att as Node).is_in_group("player") and (att as Node).is_in_group("npc"):
				set_npc_threat(att as Node3D)
				if system != null and is_instance_valid(system) and system.has_method("alert_npc_threat"):
					system.call("alert_npc_threat", att, n.global_position, ALLY_ALERT_RADIUS)
		"stuck":
			_repath = 0.0
			_search_point = Vector3.INF
		"reset":
			standing_down = true
			arrest_t = 0.0
			var c := _combat()
			if c != null:
				c.call("reset")
		"died":
			if system != null and is_instance_valid(system) and system.has_method("_on_officer_died"):
				system.call("_on_officer_died", n)


## Subclass hook (SWAT): extra setup after spawning.
func _on_spawned(_n: Node3D, _data: Dictionary) -> void:
	pass


# =================================================================================================
# think (called by the PedSystem at the NPC's tier rate)
# =================================================================================================

func think(npc: Node, delta: float) -> void:
	var n := npc as Node3D
	if n == null or bool(npc.get("is_dead")):
		return
	mode_t += delta
	_attack_note_cd -= delta
	_ff_cd -= delta
	if npc.get("current_vehicle") != null:
		_think_seated(n, delta)
		return
	if is_boarding:
		_think_board(n, delta)
		return
	if bool(npc.get("is_down")):
		return
	var p := _player()
	_update_sight(n, p, delta)
	_check_threat(n, p)
	if npc_threat != null and _think_npc_threat(n, delta):
		return
	if Wanted.level <= 0 or standing_down:
		_think_calm(n, delta)
		return
	if p == null:
		_think_search(n, delta)
		return
	_think_wanted(n, p, delta)


func _player() -> Node3D:
	var p := Game.player
	if p == null or not is_instance_valid(p) or bool(p.get("is_dead")) or not p.is_inside_tree():
		return null
	return p


func _update_sight(n: Node3D, p: Node3D, delta: float) -> void:
	var s := p != null and bool(n.call("can_see", p))
	sees = s
	if s:
		seen_t += delta
		unseen_t = 0.0
		if seen_t >= float(Wanted.get_recognition_delay()) and system != null and is_instance_valid(system):
			system.call("report_sighting", n, Game.get_player_position())
	else:
		seen_t = 0.0
		unseen_t += delta


## A firearm pointed at this officer (PedSystem aim check fills threatened_time).
func _check_threat(n: Node3D, p: Node3D) -> void:
	var tt := float(n.get("threatened_time"))
	if tt <= 0.0 or p == null or n.get("threatened_by") != p:
		_threat_reported = false
		return
	if tt < THREAT_REPORT_TIME:
		return
	if Wanted.level <= 0:
		if not _threat_reported and system != null and is_instance_valid(system):
			_threat_reported = true
			system.call("report_brandishing", n)
	elif _attack_note_cd <= 0.0:
		_attack_note_cd = 1.0
		Wanted.note_player_attack()      # aiming at police: lethal force, no arrest


func _think_wanted(n: Node3D, p: Node3D, delta: float) -> void:
	var lvl := int(Wanted.level)
	var cfg: Dictionary = Wanted.get_level_config(lvl)
	var ppos := Game.get_player_position()
	var d := _flat(n.global_position, ppos)
	var pv := Game.get_player_vehicle()
	var p_fast := pv != null and Game.get_player_velocity().length() > 3.0
	# arrest attempt (one officer at a time)
	# a compliant suspect standing still (on foot or in a stopped car) is approached from further away
	var approach := ARREST_APPROACH_FAR if (sees and Game.get_player_velocity().length() < 1.5) else ARREST_APPROACH
	if _can_arrest(cfg) and not p_fast and (d < approach or mode == Mode.ARREST) and (sees or d < 5.0) \
			and Wanted.is_player_arrestable() and system != null and is_instance_valid(system) \
			and bool(system.call("claim_arrest", n)):
		_think_arrest(n, p, delta)
		return
	if mode == Mode.ARREST:
		_end_arrest(n, d)
	if role == "roadblock" and d > 45.0 and not sees:
		_think_post(n, delta)
		return
	var lethal := bool(Wanted.is_lethal_force_authorized())
	var in_reach := sees or (Wanted.state == Wanted.State.PURSUIT and (unseen_t < 6.0 or d < 25.0))
	# officers on foot do not sprint after a car that is driving away (non-lethal levels)
	if in_reach and not (p_fast and not lethal and d > 25.0):
		_think_engage(n, p, delta, lethal)
	elif Wanted.state == Wanted.State.PURSUIT and not (pv != null and d > 110.0):
		_think_respond(n, delta)
	else:
		_think_search(n, delta)


func _can_arrest(cfg: Dictionary) -> bool:
	return bool(cfg.get("arrest_first", false)) and not is_swat


## Cached rule dictionaries (one per lethal / hold combination; aggression is fixed per officer), so
## the 10 Hz think does not build a Dictionary every time.
func _rules(lethal: bool, hold: bool) -> Dictionary:
	var high := int(Wanted.level) >= 3
	var k := (2 if lethal else 0) + (1 if hold else 0) + (4 if high else 0)
	if _rules_cache.size() < 8:
		_rules_cache.resize(8)
	if _rules_cache[k] == null:
		_rules_cache[k] = _combat_rules(lethal, hold, high)
	return _rules_cache[k]


## `high`: 3 stars and more (better shooting: the response gets more serious with the level).
func _combat_rules(lethal: bool, hold: bool, high: bool = false) -> Dictionary:
	return {"lethal": lethal, "aggression": aggression, "accuracy": 1.25 if high else 1.15, "use_cover": lethal,
			"hold_fire": hold, "melee": false, "flank": role != "roadblock",
			"engage_distance": 14.0 if lethal else 3.0, "cover_radius": 10.0 if role == "roadblock" else 14.0}


func _think_engage(n: Node3D, p: Node3D, delta: float, lethal: bool) -> void:
	_set_mode(Mode.ENGAGE)
	_ensure_weapon(n)
	var hold := not lethal
	if lethal and system != null and is_instance_valid(system) and bool(system.call("arrest_in_progress", n)):
		hold = true           # a colleague is cuffing the suspect right now
	if lethal and not hold and _friendly_in_line(n, _aim_point(p)):
		hold = true           # never shoot through a colleague
	if _pre_engage(n, p, delta):
		return
	var c := _combat()
	if c == null:
		# fallback without the AI module's combat helper: approach and aim (fire when lethal)
		var tp: Vector3 = p.call("get_target_position") if p.has_method("get_target_position") else p.global_position
		_move_towards(n, p.global_position, 10.0 if lethal else 3.0, delta)
		n.call("aim_at", tp)
		if lethal and not hold and sees:
			n.call("fire_at", tp, 1.0)
		last_status = "fallback"
		return
	last_status = str(c.call("tick", n, p, delta, _rules(lethal, hold)))
	n.set("state_tag", "police_" + last_status)
	if last_status == "lost" or last_status == "no_target":
		c.call("reset")
		_search_point = Vector3.INF
		_set_mode(Mode.SEARCH)


## Subclass hook (SWAT pairs): return true when this think was used for something else.
func _pre_engage(_n: Node3D, _p: Node3D, _delta: float) -> bool:
	return false


## Fights an NPC that attacked the police (gang shoot-out). False when there is nothing (left) to do.
func _think_npc_threat(n: Node3D, delta: float) -> bool:
	_npc_threat_t -= delta
	var t := npc_threat
	if t == null or not is_instance_valid(t) or not t.is_inside_tree() or bool(t.get("is_dead")) \
			or _npc_threat_t <= 0.0 or _flat(n.global_position, t.global_position) > NPC_THREAT_RANGE:
		_clear_npc_threat()
		return false
	if _threat_combat == null:
		var s := _combat_script_or_null()
		if s == null:
			_clear_npc_threat()
			return false
		_threat_combat = s.new() as RefCounted
	if mode == Mode.ARREST:
		_end_arrest(n, 99.0)
	_set_mode(Mode.ENGAGE)
	_ensure_weapon(n)
	var hold := _friendly_in_line(n, _aim_point(t))
	var st := str(_threat_combat.call("tick", n, t, delta, _rules(true, hold)))
	last_status = st
	n.set("state_tag", "police_fight")
	if st == "lost" or st == "no_target":
		_clear_npc_threat()
	return true


func _clear_npc_threat() -> void:
	npc_threat = null
	_npc_threat_t = 0.0
	if _threat_combat != null:
		_threat_combat.call("reset")


func _aim_point(t: Node3D) -> Vector3:
	if t.has_method("get_target_position"):
		return t.call("get_target_position")
	return t.global_position + Vector3.UP * 1.2


## True when a fellow officer stands in (or close to) the line of fire from this officer to `tpos`,
## widened along the way like the pistol spread cone: hold fire instead of hitting a colleague.
## Plain geometry over the police system's officer list (<= 16), re-evaluated at most 10x / s.
func _friendly_in_line(n: Node3D, tpos: Vector3) -> bool:
	if _ff_cd > 0.0:
		return _ff_cached
	_ff_cd = 0.1
	_ff_cached = false
	if system == null or not is_instance_valid(system):
		return false
	var list: Variant = system.get("officers")
	if not (list is Array):
		return false
	var from := n.global_position + Vector3.UP * (1.0 if bool(n.get("is_crouching")) else 1.45)
	var seg := tpos - from
	var len2 := seg.length_squared()
	if len2 < 1.0:
		return false
	var length := sqrt(len2)
	for o: Variant in list as Array:
		if o == n or not is_instance_valid(o):
			continue
		var on := o as Node3D
		if on == null or bool(on.get("is_dead")) or on.get("current_vehicle") != null:
			continue
		var q := on.global_position + Vector3.UP * 0.9
		var t := (q - from).dot(seg) / len2
		if t <= 0.0 or t >= 1.02:
			continue
		var c := from + seg * t
		var tol := 0.85 + length * t * 0.085
		if Vector2(q.x - c.x, q.z - c.z).length() < tol and absf(q.y - c.y) < 1.3:
			_ff_cached = true
			return true
	return false


func _think_arrest(n: Node3D, p: Node3D, delta: float) -> void:
	if mode != Mode.ARREST:
		_set_mode(Mode.ARREST)
		arrest_t = 0.0
		_arrest_stall_t = 0.0
		_arrest_best_d = INF
		_arrest_contact = false
		_arrest_last_d = 99.0
	_ensure_weapon(n)
	n.call("set_crouched", false)
	var tp := p.global_position
	var goal := tp
	var reach := ARREST_RANGE
	var pv := Game.get_player_vehicle()
	if pv != null and pv.has_method("get_door_position"):
		# the nearer front door (the driver's may be blocked by a boxing cruiser)
		goal = pv.call("get_door_position", 0)
		var g1: Vector3 = pv.call("get_door_position", 1)
		if _flat(n.global_position, g1) + 1.5 < _flat(n.global_position, goal):
			goal = g1
		reach = ARREST_RANGE_VEHICLE
	var dd := _flat(n.global_position, tp)
	var aim: Vector3 = p.call("get_target_position") if p.has_method("get_target_position") else tp + Vector3.UP * 1.2
	n.call("aim_at", aim)
	if not _warned and dd < 8.0:
		_warned = true
		if UI.has_method("notify"):
			UI.notify("HBPD: Stay where you are - hands up!", "warn")
	# the way to the door is blocked (a boxing cruiser, a wall): close enough is close enough
	if dd < _arrest_best_d - 0.25:
		_arrest_best_d = dd
		_arrest_stall_t = 0.0
	elif dd < reach + 1.8:
		_arrest_stall_t += delta
	if dd > reach and _arrest_stall_t < ARREST_STALL:
		_repath -= delta
		if _repath <= 0.0 or not bool(n.call("is_moving")):
			_repath = 0.4
			n.call("move_to", goal, "run" if dd > 5.0 else "walk")
		arrest_t = maxf(arrest_t - delta * 0.5, 0.0)
		n.set("state_tag", "police_arrest_approach")
	else:
		n.call("stop_moving")
		n.call("face_position", tp)
		_arrest_contact = true
		arrest_t += delta
		n.set("state_tag", "police_arresting")
		if arrest_t >= ARREST_TIME:
			arrest_t = 0.0
			if system != null and is_instance_valid(system):
				system.call("complete_arrest", n)
	# running away from an arrest = resisting
	if _arrest_contact and dd > _arrest_last_d + 0.5 and Game.get_player_velocity().length() > 3.2 and dd > 3.0:
		if system != null and is_instance_valid(system):
			system.call("report_resisting", n)
	_arrest_last_d = dd


func _end_arrest(n: Node3D, d: float) -> void:
	if _arrest_contact and d < 12.0 and Game.get_player_velocity().length() > 3.2 and system != null and is_instance_valid(system):
		system.call("report_resisting", n)
	_arrest_contact = false
	arrest_t = 0.0
	_set_mode(Mode.ENGAGE)
	if system != null and is_instance_valid(system):
		system.call("release_arrest", n)


func _think_respond(n: Node3D, delta: float) -> void:
	_set_mode(Mode.RESPOND)
	_ensure_weapon(n)
	var goal: Vector3 = Wanted.last_known_position
	var d := _flat(n.global_position, goal)
	if d < 7.0:
		_think_search(n, delta)
		return
	n.call("stop_aiming")
	n.call("set_crouched", false)
	_repath -= delta
	if _repath <= 0.0 or not bool(n.call("is_moving")) or _goal == Vector3.INF or _flat(_goal, goal) > 5.0:
		_repath = 1.6
		_goal = goal
		n.call("move_to", goal, "sprint" if d > 30.0 else "run")
	n.set("state_tag", "police_respond")


func _think_search(n: Node3D, delta: float) -> void:
	_set_mode(Mode.SEARCH)
	n.call("set_crouched", false)
	_search_age += delta
	if _search_wait > 0.0:
		_search_wait -= delta
		_look_t -= delta
		if _look_t <= 0.0:
			_look_t = _rng.randf_range(0.9, 1.6)
			var ang := _rng.randf() * TAU
			n.call("face_position", n.global_position + Vector3(sin(ang), 0.0, cos(ang)) * 5.0)
		n.set("state_tag", "police_search_look")
		return
	if _search_point == Vector3.INF or _search_age > 25.0:
		_search_point = _next_search_point(n)
		_search_age = 0.0
		var far := _flat(n.global_position, _search_point) > 25.0
		n.call("stop_aiming")
		n.call("move_to", _search_point, "run" if far else "walk")
	elif bool(n.call("has_arrived", 2.0)) or not bool(n.call("is_moving")):
		_search_point = Vector3.INF
		_search_wait = _rng.randf_range(1.8, 3.6)
		_look_t = 0.0
		n.call("stop_moving")
	n.set("state_tag", "police_search")


func _next_search_point(n: Node3D) -> Vector3:
	if system != null and is_instance_valid(system) and system.has_method("get_search_point"):
		return system.call("get_search_point", n)
	var c: Vector3 = Wanted.search_center
	var r := float(Wanted.search_radius) * 0.7
	var a := _rng.randf() * TAU
	return c + Vector3(sin(a), 0.0, cos(a)) * _rng.randf_range(0.2, 1.0) * r


func _think_post(n: Node3D, delta: float) -> void:
	_set_mode(Mode.POST)
	if post == Vector3.INF:
		post = n.global_position
	if _flat(n.global_position, post) > 1.5:
		_repath -= delta
		if _repath <= 0.0 or not bool(n.call("is_moving")):
			_repath = 2.0
			n.call("move_to", post, "run")
		return
	n.call("stop_moving")
	if Wanted.level > 0:
		_ensure_weapon(n)
		n.call("set_crouched", true)
	if post_face != Vector3.INF:
		n.call("face_position", post_face)
	n.set("state_tag", "police_post")


func _think_calm(n: Node3D, delta: float) -> void:
	if bool(n.get("is_aiming")):
		n.call("stop_aiming")
	if bool(n.get("is_crouching")):
		n.call("set_crouched", false)
	arrest_t = 0.0
	_warned = false
	if mode == Mode.ENGAGE or mode == Mode.ARREST or mode == Mode.SEARCH or mode == Mode.RESPOND:
		var c := _combat()
		if c != null:
			c.call("reset")
		_set_mode(Mode.IDLE)
	# investigate gunfire heard while calm
	if _investigate_t > 0.0 and not standing_down:
		_investigate_t -= delta
		_set_mode(Mode.INVESTIGATE)
		_ensure_weapon(n)
		var d := _flat(n.global_position, _investigate_pos)
		if d > 5.0:
			_repath -= delta
			if _repath <= 0.0 or not bool(n.call("is_moving")):
				_repath = 2.5
				n.call("move_to", _investigate_pos, "run" if d > 20.0 else "walk")
		else:
			n.call("stop_moving")
			_look_t -= delta
			if _look_t <= 0.0:
				_look_t = 1.3
				var a := _rng.randf() * TAU
				n.call("face_position", n.global_position + Vector3(sin(a), 0.0, cos(a)) * 5.0)
		n.set("state_tag", "police_investigate")
		return
	# holster after a while
	if str(n.get("weapon_id")) != "":
		_holster_t += delta
		if _holster_t > 4.0:
			n.call("set_weapon", "")
	else:
		_holster_t = 0.0
	if standing_down and role != "beat":
		_think_leave(n, delta)
		return
	match role:
		"beat":
			_think_beat(n, delta)
		"roadblock":
			_think_post(n, delta)
		"crew":
			# the vehicle AI recalls the crew; without a usable car the officer walks off
			if unit == null or not bool(unit.call("is_valid")) or bool(unit.call("is_destroyed")):
				unlink()
				_think_leave(n, delta)
			else:
				_set_mode(Mode.IDLE)
				n.call("stop_moving")
		_:
			_think_leave(n, delta)


func _think_beat(n: Node3D, delta: float) -> void:
	_set_mode(Mode.PATROL)
	if post == Vector3.INF:
		post = n.global_position
	_beat_t -= delta
	if _beat_t <= 0.0:
		_beat_t = _rng.randf_range(9.0, 22.0)
		var tgt := Vector3.INF
		if system != null and is_instance_valid(system) and system.has_method("random_walk_point"):
			tgt = system.call("random_walk_point", post, 4.0, 32.0)
		if tgt != Vector3.INF:
			if n.has_method("walk_to"):
				n.call("walk_to", tgt, "walk")
			else:
				n.call("move_to", tgt, "walk")
	if not bool(n.call("is_moving")):
		_look_t -= delta
		if _look_t <= 0.0:
			_look_t = _rng.randf_range(2.5, 5.0)
			var p := _player()
			if p != null and _flat(p.global_position, n.global_position) < 10.0:
				n.call("face_position", p.global_position)
				n.set("look_target", p.global_position + Vector3(0.0, 1.5, 0.0))
			else:
				n.set("look_target", Vector3.INF)
				var a := _rng.randf() * TAU
				n.call("face_position", n.global_position + Vector3(sin(a), 0.0, cos(a)) * 5.0)
	n.set("state_tag", "police_patrol")


func _think_leave(n: Node3D, delta: float) -> void:
	_set_mode(Mode.LEAVE)
	if _leave_target == Vector3.INF or (not bool(n.call("is_moving")) and _repath <= 0.0):
		_repath = 6.0
		var pp := Game.get_player_position() if Game.has_player() else n.global_position
		var away := n.global_position - pp
		away.y = 0.0
		if away.length() < 1.0:
			away = Vector3(1.0, 0.0, 0.0)
		var want := n.global_position + away.normalized() * 70.0
		var tgt := want
		if system != null and is_instance_valid(system) and system.has_method("random_walk_point"):
			var w: Vector3 = system.call("random_walk_point", want, 0.0, 25.0)
			if w != Vector3.INF:
				tgt = w
		_leave_target = tgt
		if n.has_method("walk_to"):
			n.call("walk_to", tgt, "walk")
		else:
			n.call("move_to", tgt, "walk")
	_repath -= delta
	n.set("state_tag", "police_leave")


func _think_seated(n: Node3D, _delta: float) -> void:
	is_boarding = false
	_board_vehicle = null
	_set_mode(Mode.SEATED)
	n.set("state_tag", "police_seated")
	if role == "air":
		return             # helicopter crew: the PoliceHeli unit does the looking and the shooting
	var seat := int(n.get("seat_index"))
	var can_fire := seat > 0 and Wanted.level >= 3 and bool(Wanted.is_lethal_force_authorized()) \
			and unit != null and bool(unit.get("sees_target")) and float(unit.get("seen_t")) > 0.8
	var p := _player()
	if not can_fire or p == null:
		if bool(n.get("is_aiming")):
			n.call("stop_aiming")
		return
	var tp: Vector3 = p.call("get_target_position") if p.has_method("get_target_position") else p.global_position
	var to := tp - n.global_position
	if to.length() > DRIVE_BY_RANGE:
		n.call("stop_aiming")
		return
	var veh := n.get("current_vehicle") as Node3D
	if veh != null:
		var vf := -veh.global_basis.z
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length_squared() > 0.01 and vf.dot(flat.normalized()) < -0.45:
			n.call("stop_aiming")
			return             # no shots straight through the rear window
	_ensure_weapon(n)
	n.call("aim_at", tp)
	if not _friendly_in_line(n, tp):
		n.call("fire_at", tp, 0.55)


func _think_board(n: Node3D, delta: float) -> void:
	_set_mode(Mode.BOARD)
	_board_t += delta
	_board_retry -= delta
	var v := _board_vehicle
	if v == null or not is_instance_valid(v) or bool(v.get("destroyed")) or _board_t > 16.0:
		is_boarding = false
		_board_vehicle = null
		return
	if n.get("current_vehicle") == v:
		is_boarding = false
		_board_vehicle = null
		return
	if str(n.get("state_tag")) != "entering_vehicle" and _board_retry <= 0.0:
		_board_retry = 1.2
		var seat := _board_seat
		if v.has_method("get_occupant"):
			var occ: Variant = v.call("get_occupant", seat)
			if occ != null and is_instance_valid(occ) and occ != n:
				seat = int(v.call("get_free_seat")) if v.has_method("get_free_seat") else -1
		if seat < 0:
			is_boarding = false
			_board_vehicle = null
			return
		_board_seat = seat
		n.call("enter_vehicle", v, seat, false)
		if n.has_method("set_speed_mode"):
			n.call("set_speed_mode", "run")


# =================================================================================================
# helpers
# =================================================================================================

func _combat() -> RefCounted:
	if combat != null:
		return combat
	var s := _combat_script_or_null()
	if s != null:
		combat = s.new() as RefCounted
	return combat


## AiBrainCombat (AI module) loaded by path once (soft dependency).
static func _combat_script_or_null() -> Script:
	if not _combat_checked:
		_combat_checked = true
		if ResourceLoader.exists(COMBAT_PATH):
			_combat_script = load(COMBAT_PATH) as Script
	return _combat_script


func _ensure_weapon(n: Node3D) -> void:
	_holster_t = 0.0
	if str(n.get("weapon_id")) == "" and default_weapon != "":
		n.call("set_weapon", default_weapon)


func _move_towards(n: Node3D, target: Vector3, keep: float, delta: float) -> void:
	var d := _flat(n.global_position, target)
	if d <= keep:
		n.call("stop_moving")
		return
	_repath -= delta
	if _repath <= 0.0 or not bool(n.call("is_moving")):
		_repath = 0.7
		n.call("move_to", target, "run" if d > 8.0 else "walk")


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
