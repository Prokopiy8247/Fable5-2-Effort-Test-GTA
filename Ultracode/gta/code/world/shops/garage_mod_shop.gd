extends Node3D
## Torque Garage (landmark `mod_garage`, spec 14A) - created by the garage system.
## An in-vehicle Interactable on the `Use_Bay` marker: drive in, press the interact key, the car is
## parked in the middle of the bay (lit by two work lights while the session runs) and the
## `mod_garage` screen opens with an orbit camera. When the screen closes the car is put on the
## driveway (`Exit_Bay`, facing out) with the player still at the wheel.
## Police vehicles are refused, wrecks too, and nobody works on a car while the police are after
## the driver. Classes without mod options get the Repair tab only (decided by the screen).

const Sites := preload("res://gta/code/world/shops/garage_sites.gd")
const Stats := preload("res://gta/code/world/shops/garage_stats.gd")

const LANDMARK := "mod_garage"
const SCREEN := "mod_garage"
const USE_RADIUS := 3.2
const MAX_ENTRY_SPEED := 4.0          ## m/s
const SHOP_NAME := "Torque Garage"

var system: Node = null
var bay_xform: Transform3D = Transform3D.IDENTITY
var exit_xform: Transform3D = Transform3D.IDENTITY
var source: String = ""                ## "city" / "lot" / "location" / "" (where the markers came from)
var interactable: Interactable = null
var session_vehicle: Node3D = null
var session_spent: int = 0
var session_items: int = 0
var enabled: bool = true

var _lights: Array[Light3D] = []
var _busy: bool = false


func setup_site(sys: Node) -> void:
	system = sys
	interactable = Interactable.create("%s - customise / repair" % SHOP_NAME, USE_RADIUS, "interact")
	interactable.name = "UseBay"
	interactable.in_vehicle_only = true
	interactable.on_foot_only = false
	interactable.use_priority = 5
	interactable.condition = _can_offer
	add_child(interactable)
	interactable.interacted.connect(_on_interacted)
	EventBus.ui_screen_closed.connect(_on_screen_closed)
	relocate()


func relocate() -> void:
	var bay := Sites.marker(LANDMARK, "Use_Bay", LANDMARK)
	source = str(bay["source"])
	bay_xform = bay["xform"]
	var ex := Sites.marker(LANDMARK, "Exit_Bay")
	if bool(ex["ok"]):
		exit_xform = ex["xform"]
	else:
		# no exit marker: 11 m out of the door, facing away from the bay
		var out_dir := bay_xform.basis.z
		exit_xform = Transform3D(Basis(Vector3.UP, Sites.yaw_of(bay_xform) + PI), bay_xform.origin + out_dir * 11.0)
	if interactable != null:
		interactable.global_position = bay_xform.origin + Vector3(0.0, 0.8, 0.0)


func set_enabled(on: bool) -> void:
	enabled = on
	if interactable != null:
		interactable.enabled = on


func reset_for_respawn() -> void:
	if session_vehicle != null and UI.is_screen_open(SCREEN):
		UI.close_screen(SCREEN)


func is_session_active() -> bool:
	return session_vehicle != null


func _can_offer(player: Node3D) -> bool:
	if not enabled or _busy or session_vehicle != null:
		return false
	var v: Variant = player.get("current_vehicle")
	if v == null or not is_instance_valid(v):
		return false
	var rb := v as RigidBody3D
	return rb == null or rb.linear_velocity.length() < MAX_ENTRY_SPEED


## "" when Torque Garage will take the vehicle, else the reason.
func refuse_reason(v: Node3D) -> String:
	if v == null or not is_instance_valid(v):
		return "No vehicle"
	if Stats.flag(v, "destroyed"):
		return "%s can't fix a burnt-out wreck" % SHOP_NAME
	if Stats.flag(v, "is_police") or Stats.text(v, "owner_tag") == "police":
		return "%s doesn't work on police vehicles" % SHOP_NAME
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and wanted.get("level") is int and int(wanted.get("level")) > 0:
		return "Lose the police before you pull in"
	return ""


func _on_interacted(player: Node3D) -> void:
	var v: Variant = player.get("current_vehicle")
	if v == null or not is_instance_valid(v):
		return
	await begin(v as Node3D)


## Starts a session with `v` (the player's vehicle): park it in the bay, open the screen.
func begin(v: Node3D) -> bool:
	var reason := refuse_reason(v)
	if reason != "":
		_notify(reason, "warn")
		Audio.play("ui_error", -6.0, 1.0, "UI")
		return false
	if _busy or session_vehicle != null:
		return false
	_busy = true
	session_vehicle = v
	session_spent = 0
	session_items = 0
	await _fade_out()
	if is_instance_valid(v):
		if v.has_method("release_inputs"):
			v.call("release_inputs")
		if v.has_method("teleport"):
			v.call("teleport", Transform3D(bay_xform.basis, bay_xform.origin + Vector3(0.0, 0.03, 0.0)))
		else:
			v.global_transform = bay_xform
	_spawn_lights()
	var scr := UI.open_screen(SCREEN, {"vehicle": v, "shop": self})
	if scr == null:
		_notify("%s is closed (screen missing)" % SHOP_NAME, "bad")
		session_vehicle = null
		_clear_lights()
	await _fade_in()
	_busy = false
	return scr != null


## Called by the screen for every purchase (summary toast on leaving).
func on_purchase(_kind: String, _id: String, paid: int) -> void:
	session_spent += paid
	session_items += 1
	if system != null and system.has_method("set_personal_vehicle") and session_vehicle != null:
		system.call("set_personal_vehicle", session_vehicle)


func _on_screen_closed(id: String) -> void:
	if id != SCREEN or session_vehicle == null:
		return
	await finish()


func finish() -> void:
	var v := session_vehicle
	session_vehicle = null
	_busy = true
	await _fade_out()
	_clear_lights()
	if v != null and is_instance_valid(v) and not Stats.flag(v, "destroyed"):
		if v.has_method("teleport"):
			v.call("teleport", Transform3D(exit_xform.basis, exit_xform.origin + Vector3(0.0, 0.05, 0.0)))
	await _fade_in()
	_busy = false
	if session_items > 0:
		_notify("%s: %d job%s done, %s" % [SHOP_NAME, session_items, "" if session_items == 1 else "s",
				"no charge" if session_spent <= 0 else Stats.money(session_spent)], "money")


# --- work lights (only while a car is in the bay) ----------------------------------------------

func _spawn_lights() -> void:
	_clear_lights()
	var key := SpotLight3D.new()
	key.name = "BayKeyLight"
	key.light_color = Color(1.0, 0.95, 0.86)
	key.light_energy = 2.4
	key.spot_range = 9.0
	key.spot_angle = 58.0
	key.shadow_enabled = false
	add_child(key)
	var fwd := -bay_xform.basis.z
	var origin := bay_xform.origin + Vector3(0.0, 3.4, 0.0) - fwd * 1.6
	key.global_transform = Transform3D(Basis.IDENTITY, origin)
	key.look_at(bay_xform.origin + Vector3(0.0, 0.5, 0.0), Vector3.UP)
	_lights.append(key)
	var fill := OmniLight3D.new()
	fill.name = "BayFillLight"
	fill.light_color = Color(0.78, 0.86, 1.0)
	fill.light_energy = 0.9
	fill.omni_range = 8.0
	fill.shadow_enabled = false
	add_child(fill)
	fill.global_position = bay_xform.origin + Vector3(0.0, 2.6, 0.0) + fwd * 2.6 + bay_xform.basis.x * 1.8
	_lights.append(fill)


func _clear_lights() -> void:
	for l: Light3D in _lights:
		if is_instance_valid(l):
			l.queue_free()
	_lights.clear()


func _fade_out() -> void:
	await UI.fade_out(0.3)


func _fade_in() -> void:
	await UI.fade_in(0.3)


func _notify(text: String, kind: String) -> void:
	UI.notify(text, kind)
