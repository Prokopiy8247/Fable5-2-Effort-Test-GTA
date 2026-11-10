extends Node
## UI wave 3 screenshots (windowed, short) -> qa/screenshots/ui3_*.png
##   tools\godot.ps1 -Mode window -Frames 900 -UserArgs '--test=ui3_shots','--no_player','--disable=traffic,peds,police,vehicles,pickups,props,interactions,shops,garage,transit,taxi,activities,radio,ambience,respawn,emergency,wildlife,debug'
## Optional --ui3_only=<name>[,<name>...]: phone_home phone_contacts phone_call phone_map photo
## photo_noir radio_wheel activity_result hud_parachute hud_dive hud_extras
## Real world + city as the backdrop (fallback camera), a fake player and fake neighbour systems
## (taxi, garage, emergency, activities, radio) so every widget has data. Also verifies that a
## real photo is written to user://photos/ (the PNG must not contain the photo-mode panel).

const FAKE_PLAYER := """
extends Node3D
var health := 84.0
var max_health := 100.0
var armor := 30.0
var max_armor := 100.0
var stamina := 1.0
var breath := 1.0
var is_dead := false
var current_vehicle: Node3D = null
var inventory: Node = null
var is_aiming := false
var in_stealth := false
var is_underwater := false
var has_scuba := false
var water_surface_y := 0.0
var visibility_factor := 0.3
var velocity := Vector3.ZERO
var altitude_agl := 300.0
var noise_radius := 0.0
var state: Object = null
"""

const FAKE_RADIO := """
extends Node
var station := "neon_tide"
var stations: Array[Dictionary] = [
	{"id": "neon_tide", "name": "Neon Tide FM", "genre": "Synthwave", "frequency": "101.5", "tagline": "Night drives, chrome skies.", "color": Color(1.0, 0.36, 0.62)},
	{"id": "low_tide", "name": "Low Tide Lounge", "genre": "Lo-fi Hip-Hop", "frequency": "88.3", "tagline": "Slow beats for slow traffic.", "color": Color(0.98, 0.78, 0.36)},
	{"id": "boogie_bay", "name": "Boogie Bay 98.7", "genre": "Funk / Disco", "frequency": "98.7", "tagline": "Four on the floor since sunrise.", "color": Color(1.0, 0.55, 0.2)},
	{"id": "breakwater", "name": "Breakwater", "genre": "Drum & Bass", "frequency": "107.9", "tagline": "172 beats per minute of pier pressure.", "color": Color(0.25, 0.85, 0.8)},
	{"id": "drift", "name": "Halcyon Drift", "genre": "Ambient / Chill", "frequency": "93.1", "tagline": "Let the bay breathe.", "color": Color(0.55, 0.7, 1.0)},
]
func get_stations(include_off: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if include_off:
		out.append({"id": "off", "name": "Radio Off"})
	out.append_array(stations)
	return out
func get_station() -> String:
	return station
func set_station(id: String) -> void:
	station = id
func is_listening() -> bool:
	return true
"""

const FAKE_SERVICES := """
extends Node
var riding := false
func call_taxi(_pos: Vector3) -> bool:
	return true
func get_fare() -> Variant:
	return {"fare": 34, "distance": 640.0, "destination": "Bay Arms"}
func is_player_riding() -> bool:
	return riding
func deliver_personal_vehicle(_near: Vector3) -> Node3D:
	return null
func get_personal_vehicle() -> Node3D:
	return null
func get_stored() -> Array:
	return [{"name": "Kestrel GT", "spec_id": "sports", "health": 820.0, "max_health": 1000.0, "personal": true},
		{"name": "Haulmark", "spec_id": "pickup", "health": 1000.0, "max_health": 1000.0}]
func get_capacity() -> int:
	return 4
func call_ambulance(_pos: Vector3) -> bool:
	return true
func get_hud_info() -> Dictionary:
	return {"title": "Harbour Sprint", "subtitle": "Street race", "time": 47.3, "checkpoint": 5, "checkpoints": 12,
		"lap": 2, "laps": 3, "position": 2, "racers": 6, "hint": "Follow the arches through the marina"}
func retry_activity(_id: String) -> void:
	pass
"""

const FAKE_STATE := """
extends RefCounted
var public_name := "on_foot"
var drive_by_in_arc := true
"""

var T: Variant = null
var _only: String = ""
var _player: Node3D
var _cam: Camera3D
var _svc: Node
var _radio: Node
var _extra: Array[Node] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	T = TestHarness
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--ui3_only="):
			_only = a.substr(11)
	await T.wait_frames(20)
	await _run()
	T.finish()


func _scripted(base: Object, source: String) -> Object:
	var gs := GDScript.new()
	gs.source_code = source
	gs.reload()
	base.set_script(gs)
	return base


func _want(shot_name: String) -> bool:
	return _only == "" or shot_name in _only.split(",")


func _shot(shot_name: String, frames: int = 12) -> void:
	await T.wait_frames(frames)
	await T.shot("ui3_" + shot_name)


func _look(from: Vector3, at: Vector3) -> void:
	if _cam != null and is_instance_valid(_cam):
		_cam.global_position = from
		_cam.look_at(at)


func _run() -> void:
	var hud := UI.hud as HudRoot
	T.check(hud != null, "HUD exists")
	if hud == null:
		return
	WorldClock.set_hour(17.6)
	_player = _scripted(Node3D.new(), FAKE_PLAYER) as Node3D
	_player.name = "FakePlayer"
	_player.set("state", _scripted(RefCounted.new(), FAKE_STATE))
	Game.main.add_child(_player)
	var plaza := Game.get_location("downtown_plaza").origin
	_player.global_position = plaza + Vector3(0, 0.1, 0)
	Game.set_player(_player)
	_svc = _scripted(Node.new(), FAKE_SERVICES) as Node
	add_child(_svc)
	_radio = _scripted(Node.new(), FAKE_RADIO) as Node
	add_child(_radio)
	for sys_name: String in ["taxi", "garage", "emergency", "activities"]:
		Game.register_system(sys_name, _svc)
	Game.register_system("radio", _radio)
	Game.money = 18250
	_cam = get_viewport().get_camera_3d()
	_look(plaza + Vector3(-38.0, 9.0, 46.0), plaza + Vector3(10.0, 14.0, -40.0))
	hud.sync_all()
	await T.wait_frames(10)

	if _want("phone_home") or _want("phone_contacts") or _want("phone_call") or _want("phone_map"):
		await _phone_shots()
	if _want("photo") or _want("photo_noir"):
		await _photo_shots(plaza)
	if _want("radio_wheel"):
		var w: Variant = UI.open_screen("radio_wheel")
		if w != null:
			w.select_station("breakwater")
			await _shot("radio_wheel", 14)
		UI.close_screen("radio_wheel")
	if _want("activity_result"):
		UI.open_screen("activity_result", {"id": "street_race_1", "title": "Harbour Sprint", "subtitle": "Street race  -  3 laps, 6 racers",
				"passed": true, "medal": "gold", "lines": [{"label": "Position", "value": "1st / 6"}, {"label": "Best lap", "value": "0:31.42", "best": true}],
				"time": 98.64, "best_time": 101.2, "reward": 750, "xp": {"driving": 4, "stamina": 1}, "new_record": true})
		await _shot("activity_result", 40)
		UI.close_screen("activity_result")
	if _want("hud_parachute"):
		await _hud_parachute(plaza)
	if _want("hud_dive"):
		await _hud_dive()
	if _want("hud_extras"):
		await _hud_extras(plaza)


func _phone_shots() -> void:
	var phone: Variant = UI.open_screen("phone")
	T.check(phone != null, "phone opens")
	if phone == null:
		return
	if _want("phone_home"):
		await _shot("phone_home", 24)
	phone.launch("contacts")
	if _want("phone_contacts"):
		await _shot("phone_contacts", 10)
	if _want("phone_call"):
		phone.activate_row(phone.find_row("taxi"))
		await _shot("phone_call", 16)
		await T.wait_frames(150)
	if _want("phone_map"):
		phone.show_page("map")
		await _shot("phone_map", 10)
	UI.close_screen("phone")
	await T.wait_frames(3)


func _photo_shots(plaza: Vector3) -> void:
	_look(plaza + Vector3(-14.0, 3.0, 18.0), plaza + Vector3(10.0, 12.0, -40.0))
	await T.wait_frames(2)
	var ph: Variant = UI.open_screen("photo")
	T.check(ph != null, "photo mode opens")
	if ph == null:
		return
	ph.set_filter(1)
	ph.set_grid(true)
	ph.set_fov(52.0)
	if _want("photo"):
		await _shot("photo", 14)
	ph.set_grid(false)
	ph.set_filter(2)
	ph.set_ui_visible(false)
	if _want("photo_noir"):
		await _shot("photo_noir", 10)
	# a real capture into user://photos
	ph.set_ui_visible(true)
	ph.set_filter(1)
	var path: String = await ph.take_photo()
	T.check(path != "" and FileAccess.file_exists(path), "a real photo was written: %s" % ProjectSettings.globalize_path(path))
	if path != "":
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		T.check(img != null and img.get_width() >= 640, "photo is a full-frame PNG (%dx%d)" % [img.get_width() if img else 0, img.get_height() if img else 0])
		if img != null:
			img.save_png(ProjectSettings.globalize_path("res://qa/screenshots/ui3_photo_capture.png"))
	await T.wait_frames(20)
	UI.close_screen("photo")
	await T.wait_frames(4)


func _hud_parachute(plaza: Vector3) -> void:
	_player.global_position = plaza + Vector3(20.0, 230.0, 40.0)
	_player.set("altitude_agl", 112.0)
	_player.set("velocity", Vector3(0.0, -46.0, 0.0))
	_look(_player.global_position + Vector3(0.0, 6.0, 9.0), plaza + Vector3(10.0, 0.0, -30.0))
	EventBus.player_state_changed.emit("freefall")
	await _shot("hud_parachute", 26)
	_player.set("altitude_agl", 340.0)
	_player.set("velocity", Vector3(0.0, -5.2, 0.0))
	EventBus.player_state_changed.emit("parachute")
	await T.wait_frames(4)
	EventBus.player_state_changed.emit("on_foot")
	_player.global_position = plaza + Vector3(0, 0.1, 0)


func _hud_dive() -> void:
	var beach := Game.get_location("beach").origin
	_player.global_position = beach + Vector3(0.0, -4.0, 30.0)
	_player.set("is_underwater", true)
	_player.set("breath", 0.42)
	_player.set("has_scuba", true)
	_player.set("water_surface_y", 0.0)
	_look(beach + Vector3(-6.0, 2.5, 6.0), beach + Vector3(10.0, 0.0, 60.0))
	await _shot("hud_dive", 30)
	_player.set("is_underwater", false)
	_player.set("breath", 1.0)


func _hud_extras(plaza: Vector3) -> void:
	_player.global_position = plaza + Vector3(0, 0.1, 0)
	_look(plaza + Vector3(-38.0, 9.0, 46.0), plaza + Vector3(10.0, 14.0, -40.0))
	# police: a helicopter and two officers searching
	var heli := _scripted(Node3D.new(), "extends Node3D\nvar vehicle_class := \"heli\"\n") as Node3D
	add_child(heli)
	heli.global_position = plaza + Vector3(36.0, 50.0, -24.0)
	heli.add_to_group(&"police")
	_extra.append(heli)
	for i in 2:
		var cop := Node3D.new()
		add_child(cop)
		cop.global_position = plaza + Vector3(-22.0 + 50.0 * i, 0.0, 18.0 - 30.0 * i)
		cop.rotation.y = 0.6 + 2.2 * i
		cop.add_to_group(&"police")
		_extra.append(cop)
	Wanted.set(&"search_center", plaza + Vector3(8.0, 0.0, 6.0))
	Wanted.search_radius = 55.0
	Wanted.level = 2
	Wanted.state = Wanted.State.SEARCH
	Wanted.escape_progress = 0.35
	_player.set("in_stealth", true)
	_player.set("visibility_factor", 0.24)
	_player.set("noise_radius", 9.0)
	_svc.set("riding", true)
	EventBus.activity_started.emit("street_race_1")
	await _shot("hud_extras", 40)
	EventBus.activity_finished.emit("street_race_1", {"result_screen": false})
	_svc.set("riding", false)
	Wanted.level = 0
	Wanted.state = Wanted.State.NONE
	_player.set("in_stealth", false)
	for n in _extra:
		n.queue_free()
