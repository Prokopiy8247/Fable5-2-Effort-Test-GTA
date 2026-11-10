class_name AiSenses
extends RefCounted
## Senses of one NPC (owned by NpcBase as `npc.senses`): sight cone + range (scaled by
## Weather.get_visibility() and WorldClock.get_daylight()), line of sight through
## Combat.has_line_of_sight, hearing (EventBus.noise_emitted, dispatched by the PedSystem) and the
## stealth awareness meter towards the player (only for NPCs with `track_player`).
##
##   senses.can_see_point(pos)        cone + range + line of sight from the eyes
##   senses.can_see(node)             same towards node.get_target_position()
##   senses.update(dt)                awareness meter (called at the NPC's think rate)
##   senses.hear(pos, radius, kind, instigator) -> bool
##   senses.awareness (0..1), senses.is_alerted, last_seen_position, last_heard_position ...
##
## Everything a player exposes is read defensively: in_stealth, is_crouching, noise_radius,
## visibility_factor (optional), current_vehicle, is_dead.

## Shared environment factor (weather visibility x daylight), refreshed at most once per second.
static var _env_factor: float = 1.0
static var _env_time: float = -1000.0
## Game-time clock of the AI module (seconds; pause / time-scale aware). Advanced once per physics
## frame by whoever calls tick_clock() first (PedSystem, or a stand-alone NpcBase).
static var _clock: float = 0.0
static var _clock_frame: int = -1

const NEAR_RADIUS := 2.6           ## inside this, the cone does not matter (peripheral / touch)
const DECAY_PER_SEC := 0.12
const ALERT_HOLD_SEC := 7.0

var npc: Node3D = null
var sight_range: float = 40.0
var fov_cos: float = cos(deg_to_rad(75.0))
var hearing_mult: float = 1.0
var alertness: float = 1.0
var track_player: bool = false

var awareness: float = 0.0
var is_alerted: bool = false
var player_visible: bool = false
var last_seen_position: Vector3 = Vector3.INF
var last_seen_time: float = -1000.0
var last_heard_position: Vector3 = Vector3.INF
var last_heard_kind: String = ""
var last_heard_time: float = -1000.0
var last_heard_instigator: Node = null

var _alert_hold: float = 0.0
var _exclude: Array = []


func setup(owner_npc: Node3D, arch: Resource) -> void:
	npc = owner_npc
	_exclude = [owner_npc]
	reset()
	if arch != null:
		sight_range = float(arch.get("sight_range"))
		fov_cos = cos(deg_to_rad(clampf(float(arch.get("sight_fov_deg")), 10.0, 359.0) * 0.5))
		hearing_mult = float(arch.get("hearing_mult"))
		alertness = float(arch.get("alertness"))
		track_player = bool(arch.get("tracks_player"))


func reset() -> void:
	awareness = 0.0
	is_alerted = false
	player_visible = false
	last_seen_position = Vector3.INF
	last_seen_time = -1000.0
	last_heard_position = Vector3.INF
	last_heard_kind = ""
	last_heard_time = -1000.0
	last_heard_instigator = null
	_alert_hold = 0.0


## Effective sight distance right now (metres).
func get_sight_range() -> float:
	return sight_range * env_factor()


## Weather visibility (160 m clear .. 45 m fog) and daylight folded into one 0.3..1 factor.
static func env_factor() -> float:
	if _clock - _env_time > 1.0 or _clock < _env_time:
		_env_time = _clock
		var vis := 160.0
		if Weather.has_method("get_visibility"):
			vis = float(Weather.get_visibility())
		var day := 1.0
		if WorldClock.has_method("get_daylight"):
			day = float(WorldClock.get_daylight())
		_env_factor = clampf(vis / 160.0, 0.35, 1.0) * lerpf(0.55, 1.0, clampf(day, 0.0, 1.0))
	return _env_factor


## Daylight 0..1 (1 when the clock is missing).
static func daylight() -> float:
	if WorldClock.has_method("get_daylight"):
		return clampf(float(WorldClock.get_daylight()), 0.0, 1.0)
	return 1.0


func get_eye_position() -> Vector3:
	if npc == null or not is_instance_valid(npc):
		return Vector3.ZERO
	if npc.has_method("get_eye_position"):
		return npc.call("get_eye_position")
	return npc.global_position + Vector3(0.0, 1.62, 0.0)


func get_forward() -> Vector3:
	var f := -npc.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


## Cone + range + line of sight towards a world point. `extra_exclude` = bodies that must not
## block the ray (the target itself, its vehicle).
func can_see_point(pos: Vector3, extra_exclude: Array = []) -> bool:
	if npc == null or not is_instance_valid(npc) or not npc.is_inside_tree():
		return false
	var eye := get_eye_position()
	var to := pos - eye
	var d := to.length()
	if d > get_sight_range():
		return false
	if d > NEAR_RADIUS:
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length_squared() > 0.0001 and get_forward().dot(flat.normalized()) < fov_cos:
			return false
	var ex: Array = _exclude
	if not extra_exclude.is_empty():
		ex = _exclude + extra_exclude
	return Combat.has_line_of_sight(eye, pos, ex)


## Cone + range + line of sight towards a node (its get_target_position()).
func can_see(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	var ex: Array = [target]
	var veh: Variant = target.get("current_vehicle")
	if veh != null and is_instance_valid(veh):
		ex.append(veh)
	return can_see_point(target_point(target), ex)


static func target_point(target: Node3D) -> Vector3:
	if target.has_method("get_target_position"):
		var v: Variant = target.call("get_target_position")
		if v is Vector3:
			return v
	return target.global_position + Vector3(0.0, 1.2, 0.0)


## Awareness meter towards the player (stealth). Call at the think rate with the elapsed time.
func update(dt: float) -> void:
	if not track_player:
		return
	var p := Game.player
	if p == null or not is_instance_valid(p) or bool(p.get("is_dead")):
		player_visible = false
		_decay(dt)
		return
	player_visible = can_see(p)
	if player_visible:
		last_seen_position = p.global_position
		last_seen_time = _clock
		var eye := get_eye_position()
		var tp := target_point(p)
		var d := eye.distance_to(tp)
		var r := maxf(get_sight_range(), 1.0)
		var near_f := clampf(1.0 - d / r, 0.0, 1.0)
		var rate := alertness * (0.3 + 2.4 * near_f * near_f)
		var vf: Variant = p.get("visibility_factor")
		if vf is float or vf is int:
			# the player's own visibility already folds in posture (crouch, sneak, cover) and light
			# (daylight, street lamps, flashlight): do not count stealth / crouch / darkness twice
			rate *= clampf(float(vf), 0.0, 2.0)
		else:
			# darkness hides people even inside the reduced range
			rate *= lerpf(0.45, 1.0, daylight())
			if bool(p.get("in_stealth")):
				rate *= 0.45
			if bool(p.get("is_crouching")):
				rate *= 0.6
		var veh: Variant = p.get("current_vehicle")
		if veh != null and is_instance_valid(veh):
			rate *= 0.8
		# peripheral vision is slower than looking straight at somebody
		var flat := Vector3(tp.x - eye.x, 0.0, tp.z - eye.z)
		if flat.length_squared() > 0.01 and get_forward().dot(flat.normalized()) < 0.5:
			rate *= 0.55
		if d < 3.0:
			rate += 1.5
		awareness = minf(awareness + rate * dt, 1.0)
	else:
		_decay(dt)
	if awareness >= 1.0:
		if not is_alerted:
			is_alerted = true
		_alert_hold = ALERT_HOLD_SEC
	elif is_alerted:
		_alert_hold -= dt
		if _alert_hold <= 0.0 and awareness < 0.3:
			is_alerted = false


func _decay(dt: float) -> void:
	awareness = maxf(awareness - DECAY_PER_SEC * dt * (0.5 if is_alerted else 1.0), 0.0)
	if is_alerted:
		_alert_hold -= dt
		if _alert_hold <= 0.0 and awareness < 0.3:
			is_alerted = false


## A noise reached this NPC (the PedSystem already did the radius test). Returns true when heard.
func hear(pos: Vector3, radius: float, kind: String, instigator: Node) -> bool:
	if npc == null or not is_instance_valid(npc):
		return false
	var r := radius * hearing_mult
	if Weather.has_method("is_raining") and bool(Weather.is_raining()):
		r *= 0.85
	var d := npc.global_position.distance_to(pos)
	if d > r:
		return false
	last_heard_position = pos
	last_heard_kind = kind
	last_heard_time = _clock
	last_heard_instigator = instigator
	if track_player and instigator != null and is_instance_valid(instigator) and instigator == Game.player:
		var closeness := clampf(1.0 - d / maxf(r, 0.1), 0.0, 1.0)
		match kind:
			"footstep":
				awareness = minf(awareness + 0.18 * alertness * (0.3 + closeness), 1.0)
			"melee", "horn", "crash":
				awareness = minf(awareness + 0.45 * alertness, 1.0)
			"gunshot", "explosion", "suppressed_gunshot":
				awareness = 1.0
				_alert_hold = ALERT_HOLD_SEC
				is_alerted = true
	return true


## Seconds since the player was last seen (large when never).
func seconds_since_seen() -> float:
	return _clock - last_seen_time


func seconds_since_heard() -> float:
	return _clock - last_heard_time


## Advance the module clock (call once per physics frame; extra calls in the same frame are ignored).
static func tick_clock(dt: float) -> void:
	var f := Engine.get_physics_frames()
	if f == _clock_frame:
		return
	_clock_frame = f
	_clock += dt


## Game time in seconds (AI module clock).
static func now() -> float:
	return _clock
