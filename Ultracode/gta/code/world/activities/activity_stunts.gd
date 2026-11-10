extends RefCounted
## Stunt jump watcher of the activities system (spec 47A "Stunt jumps"). One instance, ticked by
## activity_system.gd. Cheap when idle: a 4 Hz scan finds the nearest ramp while the player drives
## a ground vehicle (car / bike / bicycle); only then the per-physics-frame state machine runs:
##
##   IDLE -> ARMED      the vehicle is on the ramp (inside its footprint, between Entry and Lip
##                      markers of the props manifest) moving forward faster than min_speed * 0.6
##   ARMED -> AIR       it passes the lip plane at >= min_speed: launch, slow motion
##                      (Game.request_time_scale "activity_stunt" 0.35 for ~1 s of real time),
##                      EventBus.activity_started(<jump id>)
##   AIR -> LANDING     >= 2 wheels touch again (grounded_wheels) or a ground ray hits
##   LANDING -> result  upright (basis.y.y > 0.75 for 0.4 s) within 2 s of touchdown = safe landing;
##                      the jump counts when distance >= min_distance and airtime >= min_airtime
## First successful jump of a ramp: toast + banner + cash reward + driving XP, saved as completed;
## later ones report personal bests. EventBus.activity_finished(<jump id>, result) every time.

enum S { IDLE, ARMED, AIR, LANDING }

const SCAN_INTERVAL := 0.25
const NEAR_DIST := 70.0
const SLOWMO_SCALE := 0.35
const SLOWMO_REAL_MS := 1100
const LAND_WINDOW := 2.0
const UPRIGHT_DOT := 0.75
const UPRIGHT_HOLD := 0.4
const AIR_TIMEOUT := 10.0
const GROUND_CLASSES: Array[String] = ["car", "bike", "bicycle"]
## Fallbacks when the props system / manifest is missing (values of manifest_misc.json).
const RAMP_FALLBACK := {
	"stunt_ramp_big": {"entry": Vector3(0.0, 0.0, 4.6), "lip": Vector3(0.0, 2.6, -3.3), "half_w": 2.55},
	"stunt_ramp_small": {"entry": Vector3(0.0, 0.0, 1.8), "lip": Vector3(0.0, 1.0, -1.5), "half_w": 1.2},
}

var sys: Node = null
var ramps: Array = []                  ## [{id, def, xf, inv, entry_z, lip_z, lip_y, half_w, lip_world}]
var state: int = S.IDLE
var ramp_index: int = -1               ## ramp being watched (nearest)
var vehicle: Node3D = null
var air_t: float = 0.0
var land_t: float = 0.0
var upright_t: float = 0.0
var launch_pos: Vector3 = Vector3.ZERO
var launch_speed: float = 0.0
var land_pos: Vector3 = Vector3.ZERO
var max_height: float = 0.0
var airtime: float = 0.0
var last_result: Dictionary = {}
var jumps_seen: int = 0
var enabled: bool = true
var debug_log: Array[String] = []

var _scan_t: float = 0.0
var _slowmo: bool = false
var _slowmo_until_ms: int = 0
var _ray: PhysicsRayQueryParameters3D = null


func _init(system: Node) -> void:
	sys = system


## Builds the ramp list from the "stunt_jump" definitions (ramp transform = named location on the
## ground, exactly as the dressing places the ramp model).
func setup(defs: Array) -> void:
	ramps.clear()
	var props: Node = Game.get_system("props")
	for d: Dictionary in defs:
		var loc := str(d.get("location", ""))
		var w := Game.world
		if w == null or (w.has_method("has_location") and not bool(w.call("has_location", loc))):
			continue
		var lx := Game.get_location(loc)
		var p := lx.origin
		var xf := Transform3D(lx.basis.orthonormalized(), Vector3(p.x, Game.ground_height(p.x, p.z), p.z))
		var ramp_id := str(d.get("ramp", "stunt_ramp_big"))
		var fb: Dictionary = RAMP_FALLBACK.get(ramp_id, RAMP_FALLBACK["stunt_ramp_big"])
		var entry: Vector3 = fb["entry"]
		var lip: Vector3 = fb["lip"]
		var half_w := float(fb["half_w"])
		if props != null and props.has_method("get_prop_def"):
			var pd: Dictionary = props.call("get_prop_def", ramp_id)
			var mk: Variant = pd.get("markers", {})
			if mk is Dictionary:
				if (mk as Dictionary).has("Entry"):
					entry = _v3((mk as Dictionary)["Entry"], entry)
				if (mk as Dictionary).has("Lip"):
					lip = _v3((mk as Dictionary)["Lip"], lip)
			var sz: Variant = pd.get("size", null)
			if sz is Array and (sz as Array).size() >= 1:
				half_w = float(sz[0]) * 0.5
		ramps.append({
			"id": str(d.get("id", "")), "def": d, "xf": xf, "inv": xf.affine_inverse(),
			"entry_z": entry.z, "lip_z": lip.z, "lip_y": lip.y, "half_w": half_w,
			"lip_world": xf * lip, "entry_world": xf * entry,
		})


func _v3(v: Variant, fb: Vector3) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return fb


func get_ramp(id: String) -> Dictionary:
	for r: Dictionary in ramps:
		if str(r["id"]) == id:
			return r
	return {}


func is_busy() -> bool:
	return state == S.AIR or state == S.LANDING


func tick(delta: float) -> void:
	_check_slowmo()
	if not enabled or ramps.is_empty():
		return
	if state == S.IDLE:
		_scan_t -= delta
		if _scan_t > 0.0:
			return
		_scan_t = SCAN_INTERVAL
		_scan()
		return
	if vehicle == null or not is_instance_valid(vehicle):
		_reset()
		return
	match state:
		S.ARMED:
			_tick_armed()
		S.AIR:
			_tick_air(delta)
		S.LANDING:
			_tick_landing(delta)


## 4 Hz while idle: is the player in a ground vehicle near a ramp, already on it?
func _scan() -> void:
	ramp_index = -1
	var v := Game.get_player_vehicle()
	if v == null or not GROUND_CLASSES.has(str(v.get("vehicle_class"))) or v.get("destroyed") == true:
		return
	var pos := v.global_position
	var best := NEAR_DIST * NEAR_DIST
	for i in ramps.size():
		var d2 := pos.distance_squared_to((ramps[i] as Dictionary)["lip_world"])
		if d2 < best:
			best = d2
			ramp_index = i
	if ramp_index < 0:
		return
	vehicle = v
	# close to the ramp: watch every physics frame
	state = S.ARMED if _on_ramp(ramps[ramp_index], pos) else S.IDLE
	if state == S.IDLE and best < 30.0 * 30.0:
		_scan_t = 0.0   # keep scanning each frame while approaching


func _on_ramp(r: Dictionary, pos: Vector3) -> bool:
	var lp: Vector3 = (r["inv"] as Transform3D) * pos
	return absf(lp.x) <= float(r["half_w"]) + 0.8 and lp.z <= float(r["entry_z"]) + 1.5 \
			and lp.z >= float(r["lip_z"]) - 0.4 and lp.y > -0.6 and lp.y < float(r["lip_y"]) + 1.6


func _fwd_speed(r: Dictionary) -> float:
	var rb := vehicle as RigidBody3D
	if rb == null:
		return 0.0
	return rb.linear_velocity.dot(-(r["xf"] as Transform3D).basis.z)


func _tick_armed() -> void:
	var r: Dictionary = ramps[ramp_index]
	var d: Dictionary = r["def"]
	if Game.get_player_vehicle() != vehicle:
		_reset()
		return
	var pos := vehicle.global_position
	var lp: Vector3 = (r["inv"] as Transform3D) * pos
	var spd := _fwd_speed(r)
	if _on_ramp(r, pos):
		if spd < float(d.get("min_speed", 12.0)) * 0.4:
			pass   # rolling up slowly: stay armed, may still accelerate
		return
	if lp.z < float(r["lip_z"]) + 0.2 and absf(lp.x) <= float(r["half_w"]) + 1.2:
		if spd >= float(d.get("min_speed", 12.0)):
			_launch(r, spd)
		else:
			_log("%s: left the lip too slowly (%.1f m/s)" % [str(r["id"]), spd])
			_reset()
		return
	_reset()


func _launch(r: Dictionary, spd: float) -> void:
	state = S.AIR
	air_t = 0.0
	launch_pos = vehicle.global_position
	launch_speed = spd
	max_height = 0.0
	jumps_seen += 1
	if not _slowmo:
		_slowmo = true
		Game.request_time_scale("activity_stunt", SLOWMO_SCALE)
	_slowmo_until_ms = Time.get_ticks_msec() + SLOWMO_REAL_MS
	var camera: Node = Game.camera_rig
	if camera != null and camera.has_method("add_trauma"):
		camera.call("add_trauma", 0.15)
	EventBus.activity_started.emit(str(r["id"]))
	_log("%s: launch at %.1f m/s from %s" % [str(r["id"]), spd, str(launch_pos)])


func _tick_air(delta: float) -> void:
	air_t += delta
	var r: Dictionary = ramps[ramp_index]
	var pos := vehicle.global_position
	max_height = maxf(max_height, pos.y - launch_pos.y)
	if vehicle.get("destroyed") == true or Game.get_player_vehicle() != vehicle:
		_resolve(false, "bailed out" if vehicle.get("destroyed") != true else "wrecked")
		return
	if bool(vehicle.get("in_water")) or air_t > AIR_TIMEOUT:
		_resolve(false, "into the water" if bool(vehicle.get("in_water")) else "lost")
		return
	if air_t > 0.25 and _grounded():
		state = S.LANDING
		airtime = air_t
		land_pos = pos
		land_t = 0.0
		upright_t = 0.0
		_release_slowmo()
		_log("%s: touchdown after %.2f s, %.1f m" % [str(r["id"]), airtime, _horiz(launch_pos, land_pos)])


func _tick_landing(delta: float) -> void:
	land_t += delta
	if vehicle.get("destroyed") == true:
		_resolve(false, "wrecked")
		return
	var up := vehicle.global_transform.basis.y.normalized().y
	if up > UPRIGHT_DOT and _grounded():
		upright_t += delta
		if upright_t >= UPRIGHT_HOLD:
			_resolve(true, "")
			return
	else:
		upright_t = 0.0
	if land_t > LAND_WINDOW:
		_resolve(false, "crash landing")


func _grounded() -> bool:
	var gw: Variant = vehicle.get("grounded_wheels")
	if gw != null:
		return int(gw) >= 2
	# fallback: a short ray under the body
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.collision_mask = Layers.GROUND_MASK
	var rb := vehicle as CollisionObject3D
	if rb != null:
		_ray.exclude = [rb.get_rid()]
	var p := vehicle.global_position
	_ray.from = p + Vector3.UP * 0.6
	_ray.to = p + Vector3.DOWN * 0.7
	return not vehicle.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


func _horiz(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


func _resolve(safe: bool, why: String) -> void:
	var r: Dictionary = ramps[ramp_index]
	var d: Dictionary = r["def"]
	var dist := _horiz(launch_pos, land_pos) if state == S.LANDING else _horiz(launch_pos, vehicle.global_position if is_instance_valid(vehicle) else launch_pos)
	var at := airtime if state == S.LANDING else air_t
	var qualifies := dist >= float(d.get("min_distance", 15.0)) and at >= float(d.get("min_airtime", 0.8))
	var success := safe and qualifies
	var reason := why
	if safe and not qualifies:
		reason = "too short"
	last_result = {
		"id": str(r["id"]), "success": success, "safe_landing": safe, "distance": dist, "airtime": at,
		"height": max_height, "speed": launch_speed, "reason": reason,
	}
	_release_slowmo()
	_log("%s: %s (%.1f m, %.2f s, %s)" % [str(r["id"]), "SUCCESS" if success else "fail", dist, at, reason])
	state = S.IDLE
	_scan_t = 0.5
	sys.call("_on_stunt_result", d, last_result)


func _reset() -> void:
	state = S.IDLE
	_scan_t = 0.0


func abort() -> void:
	_release_slowmo()
	state = S.IDLE


func _check_slowmo() -> void:
	if _slowmo and Time.get_ticks_msec() >= _slowmo_until_ms:
		_release_slowmo()


func _release_slowmo() -> void:
	if _slowmo:
		_slowmo = false
		Game.release_time_scale("activity_stunt")


func fill_hud(info: Dictionary) -> void:
	var r: Dictionary = ramps[ramp_index] if ramp_index >= 0 and ramp_index < ramps.size() else {}
	var d: Dictionary = r.get("def", {})
	info["title"] = str(d.get("display_name", "Stunt Jump"))
	info["subtitle"] = "Stunt jump"
	var t := air_t if state == S.AIR else airtime
	info["timer"] = t
	info["time"] = t
	info["time_mode"] = "up"
	var dist := 0.0
	if vehicle != null and is_instance_valid(vehicle):
		dist = _horiz(launch_pos, vehicle.global_position if state == S.AIR else land_pos)
	info["id"] = str(r.get("id", ""))
	info["checkpoint"] = 0
	info["total"] = 0
	info["distance"] = dist
	info["airtime"] = t
	info["min_distance"] = float(d.get("min_distance", 0.0))
	info["color"] = Color(0.373, 0.839, 0.8)
	info["hint"] = "%.1f m  (needs %.0f m)" % [dist, float(d.get("min_distance", 0.0))] if state == S.AIR else "Stick the landing!"

	info["phase"] = "air" if state == S.AIR else "landing"


func _log(s: String) -> void:
	debug_log.append(s)
	if debug_log.size() > 40:
		debug_log.remove_at(0)
	print("[Activities] stunt: ", s)
