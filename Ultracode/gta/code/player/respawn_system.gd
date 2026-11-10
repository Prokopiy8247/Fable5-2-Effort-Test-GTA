extends Node
## World system "respawn" (BootManifest; ARCHITECTURE_WAVE2 W2.5, spec 18A "Busted", 48).
##
##   died     EventBus.player_died -> original "DOWN" banner, brief slow motion, fade out, respawn at
##            the hospital "Respawn" marker (city system; fallback Game.get_location("hospital")),
##            medical fee, Wanted.clear("died"), DEATH_HOURS of game time pass,
##            reset_for_respawn() on every system (+ Wanted + the player's inventory), fade in.
##            Weapons and ammunition are kept.
##   busted   EventBus.player_busted (Wanted.bust) -> Player.arrest() (out of the vehicle, hands up),
##            original "ARRESTED" banner, fade out, respawn at the police station "Respawn" marker
##            (fallback Game.get_location("police_station")), fine, every round of ammunition
##            confiscated (weapons kept), Wanted.clear("busted"), ARREST_HOURS pass,
##            reset_for_respawn(), fade in.
##   rescue   out-of-world safety net: the player (or the vehicle he sits in) is RESCUE_BELOW metres
##            under the terrain / seabed and not standing on anything, or below Player.VOID_Y, for
##            RESCUE_CONFIRM checks in a row -> short fade and back to the last safe ground
##            (Player.last_safe_position; a driven vehicle goes back to its own last safe spot).
##
## Fees never push the money below zero (whatever the player has, up to the fee). Every step talks
## to neighbours through soft calls; a missing UI / city / clock only skips that part.

const MEDICAL_FEE := 200
const ARREST_FINE := 500
const DEATH_HOURS := 4.0
const ARREST_HOURS := 6.0
const SLOWMO_SCALE := 0.3
const SLOWMO_REAL_SECONDS := 1.3
const DEATH_HOLD := 2.2                 ## game seconds after the slow motion before the fade
const ARREST_HOLD := 2.4
const BANNER_TIME := 4.6
const FADE_OUT := 0.7
const FADE_IN := 0.9
const RESCUE_BELOW := 4.0               ## m under the terrain that count as "out of the world"
const RESCUE_BELOW_ANYWAY := 12.0       ## ... even when standing on something down there
const RESCUE_BELOW_VEHICLE := 6.0
const RESCUE_CHECK := 0.25
const RESCUE_CONFIRM := 2
const DEAD_WATCHDOG := 0.5              ## dead this long with no flow running -> start the death flow
const DOWN_COLOR := Color(0.95, 0.36, 0.30)       ## coral (UI identity)
const ARREST_COLOR := Color(0.25, 0.74, 0.76)     ## teal
const DEATH_LINES := {
	"drown": "The tide won this one", "fall": "Gravity always collects",
	"explosion": "That one was loud", "vehicle": "Should have looked both ways",
	"bullet": "Medics are on the way", "fire": "Too close to the flames",
}

var enabled: bool = true
var busy: bool = false
var flow: String = ""                   ## "", "died", "busted", "rescue"
var respawn_count: int = 0
var arrest_count: int = 0
var rescue_count: int = 0
var last_fee: int = 0
var last_confiscated: int = 0
var last_respawn_position: Vector3 = Vector3.INF

var _connected: bool = false
var _check_t: float = 0.0
var _bad_checks: int = 0
var _last_cause: String = "generic"
var _dead_idle: float = 0.0             ## game seconds the player has been dead with no flow running
var _veh_safe: Vector3 = Vector3.INF
var _veh_safe_yaw: float = 0.0
var _veh_safe_id: int = 0


func _ready() -> void:
	_connect()


func setup() -> void:
	_connect()


func _connect() -> void:
	if _connected:
		return
	_connected = true
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_busted.connect(_on_player_busted)


func set_enabled(on: bool) -> void:
	enabled = on


## Nothing of this system survives a respawn except its statistics.
func reset_for_respawn() -> void:
	_bad_checks = 0


func is_busy() -> bool:
	return busy


# =================================================================================================
# death
# =================================================================================================

func _on_player_died(cause: String) -> void:
	_last_cause = cause
	if busy or not enabled:
		# another flow (arrest, rescue) is running: it stands down when it sees the player dead and
		# the watchdog in _physics_process starts the death flow right after (review fix: a death
		# during the arrest hold used to leave the player dead for good)
		return
	_run_death(cause)


func _run_death(cause: String) -> void:
	busy = true
	flow = "died"
	UI.banner("DOWN", str(DEATH_LINES.get(cause, "Medics are on the way")), DOWN_COLOR, BANNER_TIME)
	Game.request_time_scale("respawn_down", SLOWMO_SCALE)
	await _wait_real(SLOWMO_REAL_SECONDS)
	Game.release_time_scale("respawn_down")
	await _wait_game(DEATH_HOLD)
	if not _still_dead():
		_stand_down()               # somebody else revived the player (load, admin, test)
		return
	await UI.fade_out(FADE_OUT)
	var p := _player()
	if not _still_dead():
		_stand_down()
		await UI.fade_in(FADE_IN)
		return
	var fee := _charge(MEDICAL_FEE)
	Wanted.clear("died")
	_advance_time(DEATH_HOURS)
	_reset_systems(p, true)
	if p != null and p.has_method("respawn"):
		p.call("respawn", respawn_transform("hospital"))
		last_respawn_position = p.global_position
	respawn_count += 1
	busy = false
	await UI.fade_in(FADE_IN)
	if fee > 0:
		UI.notify("Hospital bill: $%d" % fee, "money")
	if flow == "died":
		flow = ""


# =================================================================================================
# arrest
# =================================================================================================

func _on_player_busted() -> void:
	if busy or not enabled:
		return
	_run_arrest()


func _run_arrest() -> void:
	busy = true
	flow = "busted"
	var p := _player()
	if p != null and p.has_method("arrest"):
		p.call("arrest")
	UI.banner("ARRESTED", "Booked and released by the HBPD", ARREST_COLOR, BANNER_TIME)
	await _wait_game(ARREST_HOLD)
	if not _still_busted():
		_stand_down()               # released / teleported / killed by somebody else meanwhile
		return
	await UI.fade_out(FADE_OUT)
	p = _player()
	if not _still_busted():
		_stand_down()
		await UI.fade_in(FADE_IN)
		return
	var fine := _charge(ARREST_FINE)
	last_confiscated = _confiscate_ammo(p)
	Wanted.clear("busted")
	_advance_time(ARREST_HOURS)
	_reset_systems(p, true)            # weapons are kept (the rounds were taken above)
	if p != null and p.has_method("respawn"):
		p.call("respawn", respawn_transform("police_station"))
		last_respawn_position = p.global_position
	arrest_count += 1
	busy = false
	await UI.fade_in(FADE_IN)
	var msg := "Fine: $%d" % fine
	if last_confiscated > 0:
		msg += "  -  ammunition confiscated"
	UI.notify(msg, "bad")
	if flow == "busted":
		flow = ""


# =================================================================================================
# helpers
# =================================================================================================

## Where to come back: the landmark's "Respawn" marker (city system), else the named location;
## snapped onto the ground below / around it.
func respawn_transform(landmark: String) -> Transform3D:
	var xf := Game.get_location(landmark)
	var city := Game.get_system("city")
	if city != null and city.has_method("has_landmark_marker") and city.has_method("get_landmark_marker"):
		if bool(city.call("has_landmark_marker", landmark, "Respawn")):
			var m: Variant = city.call("get_landmark_marker", landmark, "Respawn")
			if m is Transform3D:
				xf = m
	xf.origin = _snap_to_ground(xf.origin)
	return xf


func _snap_to_ground(pos: Vector3) -> Vector3:
	var tree := get_tree()
	var w3: World3D = tree.root.find_world_3d() if tree != null else null
	if w3 != null:
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0.0, 3.0, 0.0), pos + Vector3(0.0, -8.0, 0.0), Layers.WORLD | Layers.PROP)
		var hit := w3.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			return (hit["position"] as Vector3) + Vector3(0.0, 0.05, 0.0)
	if Game.world != null:
		return Vector3(pos.x, maxf(pos.y, Game.ground_height(pos.x, pos.z) + 0.05), pos.z)
	return pos


func _charge(amount: int) -> int:
	if bool(Game.flags.get("free_shopping", false)):
		last_fee = 0
		return 0
	var take := mini(amount, Game.money)
	if take > 0:
		Game.spend(take)
	last_fee = take
	return take


## Every round (magazines + reserve pools, thrown pieces too) goes; the weapons stay.
func _confiscate_ammo(p: Node) -> int:
	if p == null:
		return 0
	var inv: Variant = p.get("inventory")
	if not (inv is Node) or not is_instance_valid(inv):
		return 0
	var n := inv as Node
	if not n.has_method("get_save_data") or not n.has_method("load_save_data"):
		return 0
	var d: Variant = n.call("get_save_data")
	if not (d is Dictionary):
		return 0
	var data := d as Dictionary
	var removed := 0
	var ammo: Variant = data.get("ammo", {})
	if ammo is Dictionary:
		for k: Variant in (ammo as Dictionary).keys():
			removed += int((ammo as Dictionary)[k])
			(ammo as Dictionary)[k] = 0
	var weapons: Variant = data.get("weapons", {})
	if weapons is Dictionary:
		for id: Variant in (weapons as Dictionary).keys():
			var e: Variant = (weapons as Dictionary)[id]
			if e is Dictionary:
				removed += maxi(int((e as Dictionary).get("in_mag", 0)), 0)
				(e as Dictionary)["in_mag"] = 0
	data["current"] = "fists"
	n.call("load_save_data", data)
	return removed


func _advance_time(hours: float) -> void:
	if WorldClock.has_method("advance_hours"):
		WorldClock.call("advance_hours", hours)


## reset_for_respawn() on every world system, the Wanted autoload and the player's inventory.
func _reset_systems(p: Node, keep_weapons: bool) -> void:
	for key: Variant in Game.systems.keys():
		var s: Variant = Game.systems[key]
		if s == self or not (s is Object) or not is_instance_valid(s):
			continue
		if (s as Object).has_method("reset_for_respawn"):
			(s as Object).call("reset_for_respawn")
	if Wanted.has_method("reset_for_respawn"):
		Wanted.call("reset_for_respawn")
	if p != null:
		var inv: Variant = p.get("inventory")
		if inv is Node and is_instance_valid(inv) and (inv as Node).has_method("reset_for_respawn"):
			(inv as Node).call("reset_for_respawn", keep_weapons)


func _still_dead() -> bool:
	var p := _player()
	return p != null and p.get("is_dead") == true


func _still_busted() -> bool:
	var p := _player()
	if p == null or p.get("is_dead") == true:
		return false
	return not p.has_method("is_busted") or bool(p.call("is_busted"))


func _stand_down() -> void:
	busy = false
	flow = ""


func _player() -> Node3D:
	var p := Game.player
	if p != null and is_instance_valid(p):
		return p
	return null


func _wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


## Game time: respects Engine.time_scale AND the pause (review fix: the timer used to run on while
## the game was paused, so the respawn happened behind the pause menu).
func _wait_game(seconds: float) -> void:
	await get_tree().create_timer(seconds, false, false, false).timeout


# =================================================================================================
# out-of-world rescue
# =================================================================================================

func _physics_process(delta: float) -> void:
	# watchdog: the player is dead and no flow handles it (died while an arrest / rescue flow was
	# busy, or the system was re-enabled while the player lay dead) -> run the death flow now
	if enabled and not busy and _still_dead():
		_dead_idle += delta
		if _dead_idle >= DEAD_WATCHDOG:
			_dead_idle = 0.0
			_run_death(_last_cause)
			return
	else:
		_dead_idle = 0.0
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = RESCUE_CHECK
	var p := _player()
	if p == null or busy or not enabled or not p.is_inside_tree() or p.get("is_dead") == true:
		_bad_checks = 0
		return
	var sid := str(p.get("state_id"))
	if sid == "busted":
		_bad_checks = 0
		return
	var veh: Variant = p.get("current_vehicle")
	var in_vehicle := veh is Node3D and is_instance_valid(veh)
	var pos: Vector3
	if in_vehicle:
		var v3 := veh as Node3D
		pos = v3.global_position
		_track_vehicle(v3)
	else:
		pos = p.call("get_camera_focus") if p.has_method("get_camera_focus") else p.global_position
	var bad := not pos.is_finite() or pos.y < Player.VOID_Y
	if not bad and Game.world != null:
		var below := Game.ground_height(pos.x, pos.z) - pos.y
		if in_vehicle:
			bad = below > RESCUE_BELOW_VEHICLE
		else:
			var standing: bool = p.get("grounded") == true and sid == "on_foot"
			bad = below > RESCUE_BELOW_ANYWAY or (below > RESCUE_BELOW and not standing)
	if not bad:
		_bad_checks = 0
		return
	_bad_checks += 1
	if _bad_checks >= RESCUE_CONFIRM:
		_bad_checks = 0
		print("[Respawn] out-of-world rescue: %s at %s (terrain %.1f), state %s" % ["vehicle" if in_vehicle else "player",
				str(pos), Game.ground_height(pos.x, pos.z) if pos.is_finite() else 0.0, sid])
		_rescue(p, veh as Node3D if in_vehicle else null)


func _track_vehicle(v: Node3D) -> void:
	if Game.world == null:
		return
	var pos := v.global_position
	var g := Game.ground_height(pos.x, pos.z)
	if pos.y > g - 1.5 and pos.y < g + 3.0 and v.global_basis.y.y > 0.7:
		var spd := (v as RigidBody3D).linear_velocity.length() if v is RigidBody3D else 0.0
		if spd < 30.0:
			_veh_safe = pos
			var f := -v.global_basis.z
			_veh_safe_yaw = atan2(-f.x, -f.z)
			_veh_safe_id = v.get_instance_id()


func _rescue(p: Node3D, veh: Node3D) -> void:
	busy = true
	flow = "rescue"
	# the destination is fixed NOW: during the fade the player may land on something down there
	var dest := Game.get_location("spawn_start").origin
	var target: Variant = p.get("last_safe_position")
	if target is Vector3 and (target as Vector3).is_finite():
		dest = target
	var veh_dest := _veh_safe
	var veh_yaw := _veh_safe_yaw
	var veh_ok := veh != null and is_instance_valid(veh) and veh.has_method("teleport") and _veh_safe.is_finite() \
			and _veh_safe_id == veh.get_instance_id()
	await UI.fade_out(0.25)
	if p != null and is_instance_valid(p) and p.get("is_dead") != true:
		if veh_ok and is_instance_valid(veh) and p.get("current_vehicle") == veh:
			veh.call("teleport", Transform3D(Basis(Vector3.UP, veh_yaw), veh_dest + Vector3(0.0, 0.8, 0.0)))
		else:
			if p.has_method("teleport"):
				p.call("teleport", dest + Vector3(0.0, 0.1, 0.0), p.rotation.y)
			else:
				p.global_position = dest
		rescue_count += 1
	busy = false
	await UI.fade_in(0.4)
	if flow == "rescue":
		flow = ""
