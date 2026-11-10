class_name PoliceHeli
extends RefCounted
## Police helicopter unit "HBPD Air One" (spec 18 / 18A / 19, Wanted.get_level_config(level)["heli"]).
## One instance per police helicopter = the W2.1 `ai_controller` object of its `heli_police` vehicle.
## Owned and ticked (10 Hz) by PoliceSystem; no per-frame work of its own: the Helicopter autopilot
## (fly_to / orbit / set_autopilot_target / set_autopilot_heading, docs/AIRCRAFT.md section 7) flies it.
##
##  * crew: two real `police_officer` NPCs with the brain role "air" - the pilot in the driver seat and
##    an observer / marksman on the left rear bench (`Seat_Passenger_2`, facing out of the open bay);
##  * APPROACH: flies in from out of view at transit altitude (above every roof and Signal Hill);
##  * PURSUIT: orbits the player (or the last known position) ~42 m out, ~55 m above the highest ground
##    around the circle, nose (or at 4-5 stars the marksman's side) towards him, searchlight on him; a
##    fast-moving player is tracked overhead instead (an orbit cannot keep up with a car);
##  * SEARCH: sweeps waypoints spread over Wanted's search circle (golden-angle sectors) at 12 m/s while
##    the searchlight swings across the ground ahead;
##  * sight: the crew sees the player when he is in clear view below the aircraft (within 72 deg of
##    straight down, range by weather and daylight) or inside the lit searchlight cone, and nothing solid
##    is in between (roofs, interiors, tunnels, bridges hide him) -> PoliceSystem.report_sighting(),
##    after Wanted.get_recognition_delay() of continuous sight (SEARCH disguise rules);
##  * 4-5 stars: the marksman fires a marksman rifle through the bay (Combat.npc_fire, accuracy falls
##    with range), never through a colleague and never while an arrest is under way;
##  * damage: burning or nearly wrecked -> MAYDAY (engine dies, spinning descent) -> it crashes and
##    explodes; PoliceSystem reports police_vehicle_destroyed and sends a replacement after a cool-down;
##  * stand down (level cleared): searchlight off, flies away, despawned out of view by the system.

enum Mode { APPROACH, PURSUIT, SEARCH, LEAVE, MAYDAY }
const MODE_NAMES: Array[String] = ["approach", "pursuit", "search", "leave", "mayday"]

const COMBAT_PATH := "res://gta/code/combat/combat.gd"
const ORBIT_ALT := 55.0             ## metres above the highest ground around the orbit circle
const SWEEP_ALT := 52.0             ## SEARCH: above the higher of search centre / waypoint ground
const TRANSIT_ALT := 80.0           ## minimum world y while flying in from far away
const CRUISE_SPEED := 34.0
const ORBIT_RADIUS := 42.0
const ORBIT_RADIUS_MARKSMAN := 48.0
const ORBIT_SPEED := 13.0
const SWEEP_SPEED := 12.0
const TRACK_SPEED := 9.0            ## player faster than this (m/s): track overhead instead of orbiting
const SIGHT_INTERVAL := 0.2
const SIGHT_RANGE := 140.0          ## clear view below in daylight and good weather
const BELOW_COS := 0.309            ## cos(72 deg): "below the aircraft" cone of the crew
const BEAM_COS := 0.985             ## cos(10 deg): inside the lit searchlight cone
const BEAM_RANGE := 150.0
const MARKSMAN_SEAT := 2
const MARKSMAN_RANGE := 125.0
const MARKSMAN_WEAPON := "marksman_rifle"
const MAYDAY_HEALTH := 0.12         ## health ratio that starts the crash (burning starts it too)

var system: Node = null
var vehicle: RigidBody3D = null
var pilot: Node3D = null
var marksman: Node3D = null
var crew: Array[Node3D] = []
var mode: int = Mode.APPROACH
var mode_t: float = 0.0
var sub: String = ""                ## pursuit sub-state for debugging: "orbit" | "track" | "transit"
var standing_down: bool = false
var released: bool = false
var think_acc: float = 0.0
var sees_target: bool = false       ## the crew has the player in sight right now
var seen_t: float = 0.0             ## continuous sight (s)
var unseen_t: float = 999.0
var in_beam: bool = false           ## the last sighting was inside the searchlight cone
var light_point: Vector3 = Vector3.INF
var age: float = 0.0
var stats := {"sightings": 0, "beam_sightings": 0, "below_sightings": 0, "shots": 0, "sweep_points": 0,
		"orbit_t": 0.0, "track_t": 0.0, "search_t": 0.0, "min_dist": INF}

var _sight_cd: float = 0.0
var _ray: PhysicsRayQueryParameters3D = null
var _ray_vehicle: Object = null
var _spot: Node3D = null
var _orbit_alt: float = 0.0
var _alt_ref: Vector3 = Vector3.INF
var _alt_r: float = 0.0
var _sweep_point: Vector3 = Vector3.INF
var _sweep_t: float = 0.0
var _sweep_idx: int = 0
var _beam_phase: float = 0.0
var _fire_cd: float = 2.5
var _seat_yaw: float = PI * 0.5      ## yaw of the marksman's outward direction relative to the nose
var _leave_point: Vector3 = Vector3.INF
var _air_factor: float = 1.0
var _alt_bonus: float = 0.0          ## extra height while buildings keep blocking the view (street canyons)
var _blocked_t: float = 0.0
var _env_t: float = 0.0
var _rng := RandomNumberGenerator.new()
static var _combat_script: Script = null
static var _combat_checked: bool = false


func setup(p_system: Node, v: RigidBody3D, p_pilot: Node3D, p_marksman: Node3D) -> void:
	system = p_system
	vehicle = v
	pilot = p_pilot
	marksman = p_marksman
	crew.clear()
	for c: Node3D in [p_pilot, p_marksman]:
		if c != null and is_instance_valid(c):
			crew.append(c)
	_rng.seed = v.get_instance_id() ^ 0x51ed27
	_sweep_idx = _rng.randi_range(0, 16)
	v.set_meta("ai_controller", self)
	v.set("owner_tag", "police")
	if not v.is_in_group("police_vehicle"):
		v.add_to_group("police_vehicle")
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = Layers.SIGHT_MASK
	_ray.exclude = [v.get_rid()]
	_ray_vehicle = null
	# where the marksman looks out (seat basis -Z, in the helicopter's frame)
	if marksman != null and v.has_method("get_seat_node"):
		var sn: Variant = v.call("get_seat_node", MARKSMAN_SEAT)
		if sn is Node3D:
			var out := v.global_basis.inverse() * (-(sn as Node3D).global_basis.z)
			if Vector2(out.x, out.z).length() > 0.1:
				_seat_yaw = atan2(-out.x, -out.z)
	if marksman != null and is_instance_valid(marksman):
		marksman.call("set_weapon", MARKSMAN_WEAPON)
	_update_env()
	v.call("set_searchlight", true, Vector3.INF)


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func is_valid() -> bool:
	return not released and vehicle != null and is_instance_valid(vehicle) and vehicle.is_inside_tree()


func is_destroyed() -> bool:
	return vehicle == null or not is_instance_valid(vehicle) or bool(vehicle.get("destroyed"))


## Out of the fight: crashing or wrecked (the dispatcher may send a replacement).
func is_down() -> bool:
	return mode == Mode.MAYDAY or is_destroyed()


func get_position() -> Vector3:
	return vehicle.global_position if is_valid() else Vector3.INF


func get_debug_info() -> Dictionary:
	var d := {"mode": get_mode_name(), "sub": sub, "sees": sees_target, "seen_t": seen_t, "unseen_t": unseen_t,
			"in_beam": in_beam, "age": age, "standing_down": standing_down}
	if is_valid():
		var pos := vehicle.global_position
		d["pos"] = pos
		d["dist"] = _flat(pos, Game.get_player_position())
		d["agl"] = float(vehicle.get("altitude_agl"))
		d["health"] = float(vehicle.get("health"))
		d["autopilot"] = str(vehicle.get("autopilot_mode"))
		d["searchlight"] = bool(vehicle.get("searchlight_on"))
	d["marksman"] = marksman != null and is_instance_valid(marksman) and not bool(marksman.get("is_dead"))
	d["stats"] = stats.duplicate()
	return d


# =================================================================================================
# W2.1
# =================================================================================================

## "carjacked" / "abandon" / "crash": the crew climbs out (the pilot is returned); "despawn" /
## "destroyed": clean-up only (seated crew freed on despawn). Afterwards: no meta, no driver, no autopilot.
func release_vehicle(v: Node3D, reason: String) -> Node3D:
	if released:
		return null
	released = true
	var out: Node3D = null
	var leave := reason == "carjacked" or reason == "abandon" or reason == "crash"
	for c: Node3D in crew.duplicate():
		if c == null or not is_instance_valid(c):
			continue
		if c.get("current_vehicle") == v:
			if leave:
				c.call("exit_vehicle")
				if c == pilot:
					out = c
			elif reason == "despawn":
				c.call("exit_vehicle")
				c.queue_free()
	if v != null and is_instance_valid(v):
		if v.has_meta("ai_controller") and v.get_meta("ai_controller") == self:
			v.remove_meta("ai_controller")
		if v.has_method("set_searchlight"):
			v.call("set_searchlight", false)
		if v.has_method("release_inputs"):
			v.call("release_inputs")
		if v.get("driver") != null and v.get("driver") != Game.player:
			v.set("driver", null)
	if system != null and is_instance_valid(system) and system.has_method("_on_heli_released"):
		system.call("_on_heli_released", self, reason)
	return out


# =================================================================================================
# tick (PoliceSystem, 10 Hz)
# =================================================================================================

func tick(dt: float) -> void:
	if not is_valid():
		return
	age += dt
	mode_t += dt
	var v := vehicle
	if bool(v.get("destroyed")):
		if mode != Mode.MAYDAY:
			_set_mode(Mode.MAYDAY)
		return
	_env_t -= dt
	if _env_t <= 0.0:
		_env_t = 1.0
		_update_env()
	if mode == Mode.MAYDAY:
		_tick_mayday()
		return
	var hr := 1.0
	if v.has_method("get_health_ratio"):
		hr = float(v.call("get_health_ratio"))
	if bool(v.get("on_fire")) or hr < MAYDAY_HEALTH:
		_begin_mayday()
		return
	_update_sight(dt)
	if standing_down or Wanted.level <= 0:
		_tick_leave()
		_aim_light(dt)
		_stop_marksman()
		return
	if Wanted.state == Wanted.State.PURSUIT or sees_target:
		_tick_pursuit(dt)
	else:
		_tick_search(dt)
	_aim_light(dt)
	_tick_marksman(dt)


func _set_mode(m: int) -> void:
	if m != mode:
		mode = m
		mode_t = 0.0


func _update_env() -> void:
	var vis := 160.0
	if Weather.has_method("get_visibility"):
		vis = float(Weather.get_visibility())
	var day := 1.0
	if WorldClock.has_method("get_daylight"):
		day = float(WorldClock.get_daylight())
	_air_factor = clampf(vis / 160.0, 0.35, 1.0) * lerpf(0.4, 1.0, clampf(day, 0.0, 1.0))


# --- pursuit -------------------------------------------------------------------------------------

func _tick_pursuit(dt: float) -> void:
	var v := vehicle
	var hp := v.global_position
	var fresh := sees_target or unseen_t < 1.5
	var tgt: Vector3 = Game.get_player_position() if fresh else Wanted.last_known_position
	var tvel := Game.get_player_velocity() if fresh else Vector3.ZERO
	tvel.y = 0.0
	var d := _flat(hp, tgt)
	var r := ORBIT_RADIUS_MARKSMAN if _marksman_ok() and Wanted.level >= 4 else ORBIT_RADIUS
	# buildings keep cutting the line of sight: climb and tighten the circle (steeper view down)
	if _blocked_t > 1.2:
		_blocked_t = 0.0
		_alt_bonus = minf(_alt_bonus + 12.0, 36.0)
	elif sees_target:
		_alt_bonus = maxf(_alt_bonus - 1.5 * dt, 0.0)
	r *= 1.0 - _alt_bonus / 36.0 * 0.3
	var alt := _orbit_altitude(tgt, r) + _alt_bonus
	var ap := str(v.get("autopilot_mode"))
	if d > r + 110.0 or (mode == Mode.APPROACH and d > r + 60.0):
		# far away: transit high and fast towards the target
		sub = "transit"
		var talt := maxf(alt, TRANSIT_ALT) if d > 160.0 else alt
		var aim := tgt + tvel * 2.0
		if ap != "fly_to":
			v.call("fly_to", aim, talt, CRUISE_SPEED)
		else:
			v.call("set_autopilot_target", aim, talt)
		if mode != Mode.APPROACH and mode != Mode.PURSUIT:
			_set_mode(Mode.APPROACH)
		return
	_set_mode(Mode.PURSUIT)
	stats["min_dist"] = minf(float(stats["min_dist"]), d)
	if tvel.length() > TRACK_SPEED:
		# a car: an orbit cannot keep up -> hold station above / just behind him
		sub = "track"
		stats["track_t"] = float(stats["track_t"]) + dt
		# fly_to brakes towards its target (lag ~ v^2 / 4.4 m): lead the car by about that much
		var tv := tvel.length()
		var aim2 := tgt + tvel * clampf(tv / 4.4, 1.2, 4.5)
		var spd := clampf(tv * 1.35 + 6.0, 18.0, 52.0)
		if ap != "fly_to":
			v.call("fly_to", aim2, alt, spd)
		else:
			v.call("set_autopilot_target", aim2, alt)
		v.call("set_autopilot_heading", INF)
		return
	sub = "orbit"
	stats["orbit_t"] = float(stats["orbit_t"]) + dt
	if ap != "orbit":
		v.call("orbit", tgt, r, alt, ORBIT_SPEED, 1.0)
	else:
		v.call("set_autopilot_target", tgt, alt)
	# 4-5 stars: turn the marksman's side (left bay) towards the suspect; otherwise the nose
	if Wanted.level >= 4 and _marksman_ok():
		var to := tgt - hp
		if Vector2(to.x, to.z).length() > 2.0:
			v.call("set_autopilot_heading", wrapf(atan2(-to.x, -to.z) - _seat_yaw, -PI, PI))
	else:
		v.call("set_autopilot_heading", INF)


## Highest ground around the orbit circle + ORBIT_ALT (recomputed when the target moved > 8 m).
func _orbit_altitude(tgt: Vector3, r: float) -> float:
	if _alt_ref != Vector3.INF and _flat(_alt_ref, tgt) < 8.0 and absf(_alt_r - r) < 1.0:
		return _orbit_alt
	_alt_ref = tgt
	_alt_r = r
	var g := maxf(_ground(tgt), 0.0)
	for k in 6:
		var a := float(k) * TAU / 6.0
		g = maxf(g, _ground(tgt + Vector3(sin(a), 0.0, cos(a)) * r))
	_orbit_alt = g + ORBIT_ALT
	return _orbit_alt


# --- search --------------------------------------------------------------------------------------

func _tick_search(dt: float) -> void:
	var v := vehicle
	var hp := v.global_position
	var c: Vector3 = Wanted.search_center
	var sr := maxf(float(Wanted.search_radius), 30.0)
	_sweep_t += dt
	stats["search_t"] = float(stats["search_t"]) + dt
	sub = "sweep"
	var need := _sweep_point == Vector3.INF or mode != Mode.SEARCH or _flat(hp, _sweep_point) < 14.0 \
			or _sweep_t > 20.0 or _flat(_sweep_point, c) > sr + 25.0
	if need:
		if mode != Mode.SEARCH:
			_sweep_point = c                 # first pass straight over the last known area
		else:
			_sweep_idx += 1
			var ang := float(_sweep_idx) * 2.39996 + _rng.randf() * 0.4
			var rad := sr * lerpf(0.2, 0.85, _rng.randf())
			_sweep_point = c + Vector3(sin(ang), 0.0, cos(ang)) * rad
		_sweep_t = 0.0
		stats["sweep_points"] = int(stats["sweep_points"]) + 1
		var alt := maxf(maxf(_ground(c), _ground(_sweep_point)), 0.0) + SWEEP_ALT
		var far := _flat(hp, _sweep_point) > 160.0
		v.call("fly_to", _sweep_point, maxf(alt, TRANSIT_ALT) if far else alt, CRUISE_SPEED if far else SWEEP_SPEED)
		v.call("set_autopilot_heading", INF)
		_set_mode(Mode.SEARCH)


# --- leave / mayday ------------------------------------------------------------------------------

func _tick_leave() -> void:
	var v := vehicle
	if mode != Mode.LEAVE or _leave_point == Vector3.INF:
		var pp := Game.get_player_position()
		var away := v.global_position - pp
		away.y = 0.0
		if away.length() < 5.0:
			away = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
		_leave_point = pp + away.normalized() * 520.0
		v.call("fly_to", _leave_point, maxf(v.global_position.y, TRANSIT_ALT + 15.0), CRUISE_SPEED)
		v.call("set_searchlight", false)
		light_point = Vector3.INF
		sub = "leave"
		_set_mode(Mode.LEAVE)
	elif mode_t > 1.0 and str(v.get("autopilot_mode")) == "":
		v.call("fly_to", _leave_point, maxf(v.global_position.y, TRANSIT_ALT + 15.0), CRUISE_SPEED)


## Back on duty after a stand-down (a new episode while it was still leaving).
func resume() -> void:
	standing_down = false
	_leave_point = Vector3.INF
	if is_valid() and mode == Mode.LEAVE:
		vehicle.call("set_searchlight", true, Vector3.INF)
		_set_mode(Mode.APPROACH)


func _begin_mayday() -> void:
	_set_mode(Mode.MAYDAY)
	sub = "mayday"
	sees_target = false
	_stop_marksman()
	var v := vehicle
	v.call("set_searchlight", false)
	light_point = Vector3.INF
	# the engine dies: rotor winds down, collective down, spinning, nose dipping
	v.call("set_flight_inputs", 0.35, 0.45, 1.0, 0.0)
	v.call("stop_engine")


func _tick_mayday() -> void:
	var v := vehicle
	if bool(v.get("destroyed")):
		return
	v.call("set_flight_inputs", 0.35, 0.45, 1.0, 0.0)
	if bool(v.get("engine_on")):
		v.call("stop_engine")
	# landed in one piece (soft ground, water): the fire / the crash finishes it
	if mode_t > 18.0 and v.has_method("explode"):
		v.call("explode", v.call("get_last_instigator") if v.has_method("get_last_instigator") else null)


# --- sight ---------------------------------------------------------------------------------------

func _update_sight(dt: float) -> void:
	_sight_cd -= dt
	if _sight_cd > 0.0:
		return
	_sight_cd = SIGHT_INTERVAL
	var seen := false
	var lit := false
	var below := false
	var p := Game.player
	if p != null and is_instance_valid(p) and not bool(p.get("is_dead")) and p.is_inside_tree() \
			and not bool(p.get("is_underwater")):
		var tp: Vector3 = p.call("get_target_position") if p.has_method("get_target_position") else p.global_position + Vector3.UP
		var hp := vehicle.global_position + vehicle.global_basis.y * 0.9
		var to := tp - hp
		var dist := to.length()
		if dist > 0.5:
			var dir := to / dist
			lit = _in_beam(tp)
			below = dir.y < 0.0 and -dir.y > BELOW_COS and dist < SIGHT_RANGE * _air_factor
			if lit or below:
				seen = _los(hp, tp)
				if not seen and mode == Mode.PURSUIT:
					_blocked_t += SIGHT_INTERVAL
	sees_target = seen
	in_beam = seen and lit
	if seen:
		seen_t += SIGHT_INTERVAL
		unseen_t = 0.0
		_blocked_t = 0.0
		if seen_t >= float(Wanted.get_recognition_delay()) and system != null and is_instance_valid(system):
			stats["sightings"] = int(stats["sightings"]) + 1
			if lit:
				stats["beam_sightings"] = int(stats["beam_sightings"]) + 1
			if below:
				stats["below_sightings"] = int(stats["below_sightings"]) + 1
			var obs: Node = pilot if pilot != null and is_instance_valid(pilot) else vehicle
			system.call("report_sighting", obs, Game.get_player_position())
	else:
		seen_t = 0.0
		unseen_t += SIGHT_INTERVAL


## The point is inside the searchlight's lit cone (the real SpotLight3D direction).
func _in_beam(tp: Vector3) -> bool:
	if not bool(vehicle.get("searchlight_on")):
		return false
	if _spot == null or not is_instance_valid(_spot):
		_spot = vehicle.find_child("SearchSpot", true, false) as Node3D
		if _spot == null:
			return false
	var o := _spot.global_position
	var to := tp - o
	var d := to.length()
	if d < 0.5 or d > BEAM_RANGE:
		return false
	return (-_spot.global_basis.z).dot(to / d) > BEAM_COS


func _los(from: Vector3, to: Vector3) -> bool:
	var pv := Game.get_player_vehicle()
	if pv != _ray_vehicle:
		_ray_vehicle = pv
		var ex: Array[RID] = [vehicle.get_rid()]
		if pv != null and is_instance_valid(pv) and pv is CollisionObject3D:
			ex.append((pv as CollisionObject3D).get_rid())
		_ray.exclude = ex
	_ray.from = from
	_ray.to = to
	return vehicle.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


# --- searchlight ---------------------------------------------------------------------------------

func _aim_light(dt: float) -> void:
	var v := vehicle
	if mode == Mode.LEAVE or mode == Mode.MAYDAY:
		return
	var target := Vector3.INF
	if mode == Mode.PURSUIT or mode == Mode.APPROACH:
		var fresh := sees_target or unseen_t < 1.5
		target = Game.get_player_position() if fresh else Wanted.last_known_position
		if mode == Mode.APPROACH and _flat(v.global_position, target) > 150.0:
			target = Vector3.INF             # rest pose (forward-down) while still far out
	else:
		# SEARCH: the beam swings across the ground ahead of the aircraft
		_beam_phase += dt * 0.85
		var f := -v.global_basis.z
		f.y = 0.0
		f = f.normalized() if f.length() > 0.05 else Vector3.FORWARD
		var rt := Vector3(-f.z, 0.0, f.x)
		target = v.global_position + f * (26.0 + 8.0 * sin(_beam_phase * 0.6)) + rt * sin(_beam_phase) * 24.0
		target.y = _ground(target)
	light_point = target
	v.call("set_searchlight", true, target)


# --- marksman (4-5 stars) ------------------------------------------------------------------------

func _marksman_ok() -> bool:
	return marksman != null and is_instance_valid(marksman) and not bool(marksman.get("is_dead")) \
			and marksman.get("current_vehicle") == vehicle


func _stop_marksman() -> void:
	if _marksman_ok() and bool(marksman.get("is_aiming")):
		marksman.call("stop_aiming")


func _tick_marksman(dt: float) -> void:
	if not _marksman_ok():
		return
	_fire_cd -= dt
	var p := Game.player
	var active := Wanted.level >= 4 and mode == Mode.PURSUIT and sees_target and seen_t > 1.2 \
			and bool(Wanted.is_lethal_force_authorized()) and p != null and is_instance_valid(p)
	if not active:
		_stop_marksman()
		return
	var tp: Vector3 = p.call("get_target_position") if p.has_method("get_target_position") else p.global_position + Vector3.UP
	var mp := marksman.global_position + Vector3.UP * 1.1
	var to := tp - mp
	var d := to.length()
	if d > MARKSMAN_RANGE or d < 1.0:
		_stop_marksman()
		return
	# only out of his own bay (the pilot turns that side towards the suspect)
	var out := -marksman.global_basis.z
	if out.dot(to / d) < 0.2:
		_stop_marksman()
		return
	marksman.call("aim_at", tp)
	if _fire_cd > 0.0:
		return
	if system != null and is_instance_valid(system) and (bool(system.call("arrest_in_progress", null)) or _friendly_near_line(mp, tp)):
		_fire_cd = 0.5
		return
	var s := _combat()
	if s == null:
		return
	var acc := clampf(0.9 - (d - 30.0) * 0.0065, 0.3, 0.85) * clampf(_air_factor * 1.4, 0.6, 1.0)
	s.call("npc_fire", marksman, MARKSMAN_WEAPON, tp, acc)
	marksman.call("play_action", "fire", 0.14)
	stats["shots"] = int(stats["shots"]) + 1
	_fire_cd = _rng.randf_range(1.7, 2.5) if Wanted.level >= 5 else _rng.randf_range(2.4, 3.4)


## A police officer on the ground near the line of fire (close to the target end).
func _friendly_near_line(from: Vector3, to: Vector3) -> bool:
	var offs: Variant = system.get("officers")
	if not (offs is Array):
		return false
	var seg := to - from
	var l2 := seg.length_squared()
	if l2 < 0.01:
		return false
	for o: Variant in offs:
		if not (o is Node3D) or not is_instance_valid(o) or bool((o as Node3D).get("is_dead")):
			continue
		var q := (o as Node3D).global_position + Vector3.UP
		var t := (q - from).dot(seg) / l2
		if t < 0.3 or t > 1.08:
			continue
		var c := from + seg * t
		if q.distance_to(c) < 1.2 + 0.03 * seg.length() * t:
			return true
	return false


static func _combat() -> Script:
	if not _combat_checked:
		_combat_checked = true
		if ResourceLoader.exists(COMBAT_PATH):
			_combat_script = load(COMBAT_PATH) as Script
	return _combat_script


# --- helpers -------------------------------------------------------------------------------------

func _ground(p: Vector3) -> float:
	if Game.world != null and is_instance_valid(Game.world) and Game.world.has_method("get_height"):
		return float(Game.world.call("get_height", p.x, p.z))
	return 0.0


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
