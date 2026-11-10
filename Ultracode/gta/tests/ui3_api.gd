extends Node
## UI wave 3 API test (headless): phone, photo mode, radio wheel, activity result, the new HUD
## widgets, minimap police / search helpers, icons and the debug-overlay coupling.
##   tools\godot.ps1 -Mode headless -Frames 4000 -UserArgs '--test=ui3_api','--no_player','--disable=traffic,peds,police,vehicles,pickups,props,city,interactions,shops,garage,transit,taxi,activities,radio,ambience,respawn,emergency,wildlife'
## The neighbour systems (taxi, garage, emergency, activities, radio) are replaced by small fake
## nodes registered with Game.register_system(), so every code path runs even while those modules
## are still being written. A fake player feeds the HUD. Input-lock / pause / time scale must be
## restored after every screen.

const FAKE_PLAYER := """
extends Node3D
var health := 100.0
var max_health := 100.0
var armor := 0.0
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

const FAKE_STATE := """
extends RefCounted
var public_name := "on_foot"
var drive_by_in_arc := true
"""

const FAKE_VEHICLE := """
extends Node3D
var spec_id := "taxi"
var vehicle_class := "car"
var owner_tag := "taxi"
var health := 900.0
var max_health := 1000.0
var speed_kmh := 40.0
var is_player_driven := false
"""

const FAKE_RADIO := """
extends Node
var station := "off"
var listening := true
var stations: Array[Dictionary] = [
	{"id": "neon_tide", "name": "Neon Tide FM", "genre": "Synthwave", "frequency": "101.5", "tagline": "Night drives, chrome skies.", "color": Color(1.0, 0.36, 0.62)},
	{"id": "low_tide", "name": "Low Tide Lounge", "genre": "Lo-fi Hip-Hop", "frequency": "88.3", "tagline": "Slow beats for slow traffic.", "color": Color(0.98, 0.78, 0.36)},
	{"id": "boogie_bay", "name": "Boogie Bay 98.7", "genre": "Funk / Disco", "frequency": "98.7", "tagline": "Four on the floor.", "color": Color(1.0, 0.55, 0.2)},
	{"id": "breakwater", "name": "Breakwater", "genre": "Drum & Bass", "frequency": "107.9", "tagline": "Pier pressure.", "color": Color(0.25, 0.85, 0.8)},
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
	return listening
"""

const FAKE_TAXI := """
extends Node
var calls := 0
var last_pos := Vector3.INF
var riding := false
var fare := 0
func call_taxi(pos: Vector3) -> bool:
	calls += 1
	last_pos = pos
	return true
func get_fare() -> Variant:
	return {"fare": fare, "distance": 640.0, "destination": "Bay Arms"}
func is_player_riding() -> bool:
	return riding
"""

const FAKE_GARAGE := """
extends Node
var delivered := 0
var last_error := ""
var vehicle: Node3D = null
func deliver_personal_vehicle(_near: Vector3) -> Node3D:
	delivered += 1
	if vehicle == null:
		last_error = "No personal vehicle"
	return vehicle
func get_personal_vehicle() -> Node3D:
	return null
func get_stored() -> Array:
	return [{"name": "Sports", "spec_id": "sports", "health": 800.0, "max_health": 1000.0, "personal": true},
		{"name": "Pickup", "spec_id": "pickup", "health": 1000.0, "max_health": 1000.0}]
func get_capacity() -> int:
	return 4
"""

const FAKE_EMERGENCY := """
extends Node
var ambulance := 0
var services: Array = []
func call_ambulance(_pos: Vector3) -> bool:
	ambulance += 1
	return true
func call_service(kind: String, _pos: Vector3) -> bool:
	services.append(kind)
	return true
"""

const FAKE_ACTIVITIES := """
extends Node
var retried := ""
var info := {}
func get_hud_info() -> Dictionary:
	return info
func retry_activity(id: String) -> void:
	retried = id
"""

var T: Variant = null
const CALL_T := 0.9          ## phone_screen.CALL_TIME
const RESULT_T := 1.8        ## phone_screen.RESULT_TIME
var _fakes: Dictionary = {}
var _saved: Dictionary = {}
var _lock0: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	T = TestHarness
	await T.wait_frames(6)
	await _run()
	_cleanup()
	T.finish()


func _scripted(base: Object, source: String) -> Object:
	var gs := GDScript.new()
	gs.source_code = source
	gs.reload()
	base.set_script(gs)
	return base


func _action(action: String, pressed: bool = true) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await T.wait_frames(3)


func _fake_system(sys_name: String, source: String) -> Node:
	if not _saved.has(sys_name):
		_saved[sys_name] = Game.systems.get(sys_name, null)
	var n := _scripted(Node.new(), source) as Node
	n.name = "Fake_" + sys_name
	add_child(n)
	Game.register_system(sys_name, n)
	_fakes[sys_name] = n
	return n


func _drop_system(sys_name: String) -> void:
	Game.systems.erase(sys_name)


func _cleanup() -> void:
	UI.close_all_screens()
	for k: String in _saved:
		if _saved[k] != null:
			Game.systems[k] = _saved[k]
		else:
			Game.systems.erase(k)
	if Game.player != null and Game.player.name == "FakePlayer":
		Game.player.queue_free()
		Game.player = null


func _neutral(what: String) -> void:
	T.check(not get_tree().paused, what + ": game unpaused")
	T.check(Game.input_locked == _lock0, what + ": input lock restored (%d)" % Game.input_locked)
	T.check(absf(Engine.time_scale - 1.0) < 0.01, what + ": time scale back to 1 (%.2f)" % Engine.time_scale)


func _run() -> void:
	var hud := UI.hud as HudRoot
	T.check(hud != null, "HUD exists")
	if hud == null:
		return
	_lock0 = Game.input_locked
	for id: String in ["phone", "photo", "radio_wheel", "activity_result"]:
		T.check(ResourceLoader.exists(UI.SCREENS[id]), "screen script exists: " + id)

	# --- fake player ----------------------------------------------------------------------------------
	var pl := _scripted(Node3D.new(), FAKE_PLAYER) as Node3D
	pl.name = "FakePlayer"
	pl.set("state", _scripted(RefCounted.new(), FAKE_STATE))
	Game.main.add_child(pl)
	var spawn := Game.get_location("downtown_plaza").origin
	pl.global_position = spawn + Vector3(0.0, 0.2, 0.0)
	Game.set_player(pl)
	await T.wait_frames(4)

	await _test_icons()
	await _test_phone(pl)
	await _test_photo(pl)
	await _test_radio_wheel(pl)
	await _test_activity_result()
	await _test_hud(hud, pl)
	await _test_minimap_helpers()
	await _test_debug_overlay()


# --- icons -------------------------------------------------------------------------------------------

func _test_icons() -> void:
	for key: StringName in [&"canopy", &"flame", &"eye", &"hat_crown", &"hat_brim", &"shoe", &"camera_body", &"trophy_cup"]:
		var shape := UiIcons._shape(key)
		var tris := Geometry2D.triangulate_polygon(shape)
		T.check(shape.size() >= 3 and tris.size() >= 3, "icon polygon '%s' is simple (%d pts, %d tri idx)" % [key, shape.size(), tris.size()])
	# draw every new glyph once into a canvas (smoke test, no errors expected)
	var ids: Array[StringName] = [&"parachute", &"hat", &"glasses", &"shoes", &"phone", &"call", &"camera", &"flame", &"medal",
			&"trophy", &"timer", &"note", &"eye", &"eye_off", &"filter", &"signal", &"battery", &"ambulance", &"altimeter"]
	var canvas := UiCanvas.new(func(c: UiCanvas) -> void:
		var x := 30.0
		for id in ids:
			UiIcons.draw(c, id, Vector2(x, 30.0), 40.0, UiStyle.CREAM)
			x += 50.0)
	canvas.size = Vector2(1000, 60)
	UI.get_node("Root").add_child(canvas)
	await T.wait_frames(2)
	canvas.queue_free()
	T.check(true, "new glyphs drawn: %d" % ids.size())


# --- phone -------------------------------------------------------------------------------------------

func _test_phone(pl: Node3D) -> void:
	var taxi := _fake_system("taxi", FAKE_TAXI)
	var garage := _fake_system("garage", FAKE_GARAGE)
	var emergency := _fake_system("emergency", FAKE_EMERGENCY)
	var radio := _fake_system("radio", FAKE_RADIO)
	await _action("phone")
	var phone: Variant = UI.get_screen("phone")
	T.check(phone != null, "P opens the phone")
	if phone == null:
		return
	T.check(Game.input_locked > _lock0 and not get_tree().paused, "phone locks input and does not pause")
	T.check(phone.get_page() == "home" and phone.get_app_ids().size() == 8, "phone home with 8 apps")
	await T.wait_frames(20)

	# contacts: taxi
	phone.launch("contacts")
	T.check(phone.get_page() == "contacts" and phone.get_list() != null and phone.get_list().get_count() == 4, "contacts lists 4 services")
	T.check(phone.service_status("taxi") == "" and phone.service_status("ambulance") == "", "taxi + ambulance available with the systems present")
	phone.activate_row(phone.find_row("taxi"))
	T.check(phone.is_calling(), "calling Bay Cabs shows the call screen")
	await T.wait_frames(int((CALL_T + 0.2) * 60.0))
	T.check(int(taxi.get("calls")) == 1 and (taxi.get("last_pos") as Vector3).distance_to(pl.global_position) < 0.5,
			"taxi.call_taxi(player position) called once")
	T.check(phone.last_action == "taxi:ok", "taxi call reported ok (%s)" % phone.last_action)
	await T.wait_frames(int((RESULT_T + 0.2) * 60.0))
	T.check(not phone.is_calling() and phone.get_page() == "contacts", "call screen returns to the list")

	# mechanic without a personal vehicle -> graceful failure text
	phone.activate_row(phone.find_row("mechanic"))
	await T.wait_frames(int((CALL_T + 0.2) * 60.0))
	T.check(int(garage.get("delivered")) == 1 and phone.last_action == "mechanic:fail", "mechanic asks the garage (no vehicle -> fail)")
	await T.wait_frames(int((RESULT_T + 0.2) * 60.0))
	var pv := _scripted(Node3D.new(), FAKE_VEHICLE) as Node3D
	pv.set("spec_id", "sports")
	add_child(pv)
	garage.set("vehicle", pv)
	phone.activate_row(phone.find_row("mechanic"))
	await T.wait_frames(int((CALL_T + 0.2) * 60.0))
	T.check(phone.last_action == "mechanic:ok", "mechanic delivers the personal vehicle")
	await T.wait_frames(int((RESULT_T + 0.2) * 60.0))

	# ambulance (direct method) + fire (generic call_service)
	phone.activate_row(phone.find_row("ambulance"))
	await T.wait_frames(int((CALL_T + RESULT_T + 0.4) * 60.0))
	T.check(int(emergency.get("ambulance")) == 1, "ambulance via emergency.call_ambulance()")
	phone.activate_row(phone.find_row("fire"))
	await T.wait_frames(int((CALL_T + RESULT_T + 0.4) * 60.0))
	T.check((emergency.get("services") as Array).has("fire"), "fire crew via emergency.call_service('fire')")

	# missing systems -> greyed rows
	_drop_system("taxi")
	_drop_system("emergency")
	phone.show_page("contacts")
	var ti: Dictionary = phone.get_list().get_item(phone.find_row("taxi"))
	T.check(bool(ti.get("disabled", false)) and str(ti.get("sub", "")) == "Not in service", "taxi row greyed out without a taxi system")
	phone.activate_row(phone.find_row("taxi"))
	T.check(not phone.is_calling(), "a greyed contact cannot be called")
	Game.register_system("taxi", taxi)
	Game.register_system("emergency", emergency)

	# back -> home
	T.check(phone.handle_back() and phone.get_page() == "home", "Esc in an app returns home")

	# map app: GPS to a place
	phone.launch("map")
	var lst: UiList = phone.get_list()
	T.check(lst != null and lst.get_count() >= 2, "map app lists 'open map' + places (%d rows)" % (lst.get_count() if lst else 0))
	UI.clear_waypoint()
	var place_row := -1
	for i in lst.get_count():
		if lst.get_item(i).get("id") is Vector2:
			place_row = i
			break
	T.check(place_row >= 0, "map app has at least one named place")
	if place_row >= 0:
		phone.activate_row(place_row)
		T.check(UI.has_waypoint(), "selecting a place sets the waypoint")
		var cl: int = phone.find_row("clear_wp")
		T.check(cl >= 0, "clear-waypoint row appears")
		phone.activate_row(cl)
		T.check(not UI.has_waypoint(), "clear-waypoint row clears it")
	phone.activate_row(phone.find_row("open_map"))
	await T.wait_frames(3)
	T.check(UI.is_screen_open("map") and UI.get_top_screen() == "map", "Open full map opens the map screen on top")
	UI.close_screen("map")
	await T.wait_frames(3)
	T.check(UI.get_top_screen() == "phone", "closing the map returns to the phone")

	# radio app
	phone.show_page("home")
	phone.launch("radio")
	T.check(phone.get_list().get_count() == 6, "radio app lists off + 5 stations")
	phone.activate_row(phone.find_row("low_tide"))
	T.check(str(radio.get("station")) == "low_tide", "radio app tunes the station")

	# garage app
	phone.show_page("home")
	phone.launch("garage")
	T.check(phone.get_list().get_count() == 3, "garage app: deliver row + 2 stored vehicles")

	# save app
	phone.show_page("home")
	phone.launch("save")
	phone.activate_row(phone.find_row("save"))
	T.check(phone.last_action == "save:ok" and SaveSystem.has_save("quick"), "save app quick-saves (%s)" % phone.last_action)

	# skills + settings open on top and come back
	phone.show_page("home")
	phone.launch("skills")
	await T.wait_frames(3)
	T.check(UI.get_top_screen() == "status" and not phone.visible, "Skills opens the status screen over the phone")
	UI.close_screen("status")
	await T.wait_frames(3)
	T.check(UI.get_top_screen() == "phone" and phone.visible, "phone visible again after status")
	phone.launch("settings")
	await T.wait_frames(3)
	T.check(UI.get_top_screen() == "pause", "Settings opens the pause menu (settings page)")
	UI.close_screen("pause")
	await T.wait_frames(3)

	# camera app -> photo mode
	phone.launch("camera")
	await T.wait_frames(4)
	T.check(not UI.is_screen_open("phone") and UI.is_screen_open("photo"), "Camera closes the phone and opens photo mode")
	UI.close_screen("photo")
	await T.wait_frames(3)
	_neutral("phone")

	# P toggles closed, Esc at home closes
	await _action("phone")
	T.check(UI.is_screen_open("phone"), "phone re-opens")
	await _action("phone")
	T.check(not UI.is_screen_open("phone"), "P closes the phone")
	await _action("phone")
	await _action("pause")
	T.check(not UI.is_screen_open("phone") and not UI.is_screen_open("pause"), "Esc on the home screen closes the phone")
	_neutral("phone closed")
	pv.queue_free()


# --- photo mode ----------------------------------------------------------------------------------------

func _test_photo(pl: Node3D) -> void:
	var prev_cam := get_viewport().get_camera_3d()
	await _action("photo_mode")
	var ph: Variant = UI.get_screen("photo")
	T.check(ph != null, "F2 opens photo mode")
	if ph == null:
		return
	T.check(get_tree().paused, "photo mode pauses the game")
	T.check(not UI.hud.visible, "photo mode hides the HUD")
	var cam: Camera3D = ph.get_camera()
	T.check(cam != null and get_viewport().get_camera_3d() == cam, "photo camera is current")
	ph.set_fov(500.0)
	T.check(is_equal_approx(ph.fov, 100.0) and is_equal_approx(cam.fov, 100.0), "FOV clamps to the max")
	ph.set_roll(90.0)
	T.check(is_equal_approx(ph.roll, 45.0), "roll clamps to 45 deg")
	ph.move_camera_to(pl.global_position + Vector3(200.0, 40.0, 0.0))
	T.check(ph.distance_to_subject() <= 25.05, "camera stays within 25 m of the player (%.1f)" % ph.distance_to_subject())
	ph.move_camera_to(pl.global_position + Vector3(0.0, -50.0, 3.0))
	var g := Game.ground_height(cam.global_position.x, cam.global_position.z)
	T.check(cam.global_position.y >= g + 0.25, "camera stays above the ground")
	ph.set_filter(2)
	T.check(ph.get_filter_name() == "Harbour Noir", "filter preset by index")
	ph.cycle_filter(-3)
	T.check(ph.filter_index == 7, "filter cycling wraps around")
	ph.set_filter(0)
	ph.set_dof_mode(1)
	T.check(cam.attributes is CameraAttributesPractical and (cam.attributes as CameraAttributesPractical).dof_blur_far_enabled,
			"portrait focus enables depth of field")
	ph.set_dof_mode(0)
	ph.set_grid(true)
	T.check(ph.grid_on, "grid toggles")
	var shots := [0]
	ph.photo_taken.connect(func(_p: String) -> void: shots[0] += 1)
	var path: String = await ph.take_photo()
	T.check(shots[0] == 1 and ph.photos_taken == 1, "take_photo runs the capture state machine (headless path '%s')" % path)
	T.check(ph.ui_visible and not ph.is_busy(), "panel restored after the capture")
	var img := Image.create(64, 36, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.5, 0.4))
	var saved: String = ph.save_image(img)
	T.check(saved.begins_with("user://photos/") and FileAccess.file_exists(saved), "save_image writes a PNG to user://photos (%s)" % saved)
	if saved != "":
		var back := Image.load_from_file(ProjectSettings.globalize_path(saved))
		T.check(back != null and back.get_width() == 64, "saved photo loads back as a 64x36 PNG")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saved))
	await _action("photo_mode")
	T.check(not UI.is_screen_open("photo"), "F2 leaves photo mode")
	T.check(UI.hud.visible, "HUD back after photo mode")
	T.check(get_viewport().get_camera_3d() == prev_cam, "previous camera current again")
	T.check(not is_instance_valid(cam) or cam.is_queued_for_deletion(), "photo camera freed")
	_neutral("photo")


# --- radio wheel ---------------------------------------------------------------------------------------

func _test_radio_wheel(_pl: Node3D) -> void:
	var radio: Node = _fakes.get("radio")
	if radio == null:
		radio = _fake_system("radio", FAKE_RADIO)
	Game.register_system("radio", radio)
	radio.set("station", "neon_tide")
	radio.set("listening", true)
	await _action("radio_wheel", true)
	var wheel: Variant = UI.get_screen("radio_wheel")
	T.check(wheel != null, "holding Y opens the radio wheel")
	if wheel == null:
		return
	await T.wait_frames(2)
	T.check(absf(Engine.time_scale - 0.15) < 0.02, "radio wheel slows time to 0.15 (%.2f)" % Engine.time_scale)
	T.check(wheel.get_station_ids().size() == 6 and wheel.get_station_ids()[0] == "off", "wheel shows off + 5 stations")
	T.check(wheel.get_hovered_station() == "neon_tide", "wheel starts on the current station")
	wheel.set_pointer(Vector2(0.0, 120.0))         # straight down
	T.check(wheel.get_hovered_index() == 3, "pointer down selects the opposite wedge (%d)" % wheel.get_hovered_index())
	wheel.select_station("breakwater")
	wheel.cycle(1)
	T.check(wheel.get_hovered_station() == "drift", "scroll moves the highlight")
	await _action("radio_wheel", false)
	T.check(not UI.is_screen_open("radio_wheel") and str(radio.get("station")) == "drift", "release tunes the highlighted station")
	_neutral("radio wheel")
	# cancel
	await _action("radio_wheel", true)
	wheel = UI.get_screen("radio_wheel")
	if wheel != null:
		wheel.select_station("off")
	await _action("pause")
	T.check(not UI.is_screen_open("radio_wheel") and str(radio.get("station")) == "drift", "Esc cancels without tuning")
	await _action("radio_wheel", false)
	_neutral("radio wheel cancel")
	# not available on foot without a radio
	radio.set("listening", false)
	await _action("radio_wheel", true)
	T.check(not UI.is_screen_open("radio_wheel"), "no radio wheel on foot")
	await _action("radio_wheel", false)
	radio.set("listening", true)


# --- activity result -----------------------------------------------------------------------------------

func _test_activity_result() -> void:
	var acts := _fake_system("activities", FAKE_ACTIVITIES)
	var result := {"title": "Harbour Sprint", "subtitle": "Street race - 3 laps", "passed": true, "medal": "gold",
		"lines": [{"label": "Position", "value": "1st / 6"}], "time": 102.35, "best_time": 102.35, "reward": 500,
		"xp": {"driving": 4}, "new_record": true}
	EventBus.activity_finished.emit("street_race_1", result)
	await T.wait_frames(3)
	var scr: Variant = UI.get_screen("activity_result")
	T.check(scr != null, "activity_finished opens the result panel")
	if scr == null:
		return
	T.check(get_tree().paused, "result panel pauses")
	T.check(scr.is_passed() and scr.get_medal() == "gold", "passed + gold medal parsed")
	T.check(scr.get_line_count() == 3, "lines: position + time + best time (%d)" % scr.get_line_count())
	T.check(scr.can_retry(), "retry offered (activities.retry_activity exists)")
	scr.retry()
	await T.wait_frames(3)
	T.check(not UI.is_screen_open("activity_result") and str(acts.get("retried")) == "street_race_1", "retry closes the panel and restarts the activity")
	_neutral("activity result")
	# failed run without a retry path
	_drop_system("activities")
	UI.open_screen("activity_result", {"id": "range_1", "title": "Bay Arms Range", "passed": false, "score": 1250,
			"stats": {"Hits": "18 / 30"}, "fail_reason": "Time up"})
	await T.wait_frames(2)
	scr = UI.get_screen("activity_result")
	T.check(scr != null and not scr.is_passed() and not scr.can_retry(), "failed result without retry path hides Retry")
	T.check(scr != null and scr.get_line_count() == 2, "stats dict + score become lines")
	await _action("pause")
	T.check(not UI.is_screen_open("activity_result"), "Esc closes the result panel")
	# opt-out
	EventBus.activity_finished.emit("quiet", {"result_screen": false})
	await T.wait_frames(3)
	T.check(not UI.is_screen_open("activity_result"), "result_screen = false opts out")
	Game.register_system("activities", acts)
	_neutral("activity result 2")


# --- HUD widgets ---------------------------------------------------------------------------------------

func _test_hud(hud: HudRoot, pl: Node3D) -> void:
	var st: Object = pl.get("state")
	# skydiving
	pl.set("altitude_agl", 320.0)
	pl.set("velocity", Vector3(0.0, -52.0, 0.0))
	EventBus.player_state_changed.emit("freefall")
	await T.wait_frames(4)
	var s := hud.get_state()
	T.check(bool(s["altimeter"]) and absf(float(s["altitude"]) - 320.0) < 0.5, "freefall shows the altimeter (altitude_agl)")
	T.check(not bool(s["pull_warning"]), "no pull cue high up")
	pl.set("altitude_agl", 90.0)
	await T.wait_frames(2)
	T.check(bool(hud.get_state()["pull_warning"]), "pull cue below 140 m in freefall")
	EventBus.player_state_changed.emit("parachute")
	await T.wait_frames(2)
	T.check(hud.altimeter.canopy and not bool(hud.get_state()["pull_warning"]), "canopy state, no pull cue")
	EventBus.player_state_changed.emit("on_foot")
	st.set("public_name", "parachute")
	await T.wait_frames(2)
	T.check(bool(hud.get_state()["altimeter"]), "altimeter also follows state.public_name")
	st.set("public_name", "on_foot")
	await T.wait_frames(2)
	T.check(not bool(hud.get_state()["altimeter"]), "altimeter hides on landing")
	# under water
	pl.set("is_underwater", true)
	pl.set("breath", 0.4)
	pl.set("has_scuba", true)
	pl.global_position.y = -6.0
	await T.wait_frames(3)
	s = hud.get_state()
	T.check(bool(s["dive"]) and bool(s["scuba"]) and absf(float(s["breath"]) - 0.4) < 0.01, "dive gauge with breath + scuba tag")
	T.check(absf(hud.dive.depth - 5.1) < 0.2, "depth from water_surface_y (%.1f m)" % hud.dive.depth)
	T.check(not hud.vitals.show_breath, "thin breath bar replaced by the dive gauge")
	pl.set("is_underwater", false)
	pl.set("breath", 1.0)
	pl.global_position.y = Game.get_location("downtown_plaza").origin.y + 0.2
	await T.wait_frames(2)
	T.check(not bool(hud.get_state()["dive"]) and hud.vitals.show_breath, "dive gauge hides on surfacing")
	# stealth
	pl.set("in_stealth", true)
	pl.set("visibility_factor", 0.2)
	await T.wait_frames(2)
	T.check(bool(hud.get_state()["stealth"]) and hud.stealth.is_hidden(), "stealth eye shows (hidden)")
	pl.set("in_stealth", false)
	await T.wait_frames(2)
	T.check(not bool(hud.get_state()["stealth"]), "stealth eye hides")
	# activity card
	var acts: Node = Game.get_system("activities")
	if acts != null:
		acts.set("info", {"time": 12.0, "checkpoint": 2, "checkpoints": 8, "lap": 1, "laps": 3, "hint": "Follow the arches"})
	EventBus.activity_started.emit("street_race_1")
	await T.wait_frames(6)
	s = hud.get_state()
	T.check(str(s["activity"]) == "street_race_1", "activity card on activity_started")
	T.check(str(s["activity_time"]).begins_with("0:12"), "timer synced from get_hud_info (%s)" % str(s["activity_time"]))
	if acts != null:
		acts.set("info", {"checkpoint": 3, "checkpoints": 8})     # no "time": the card keeps counting itself
	await T.wait_frames(60)
	T.check(str(hud.get_state()["activity_time"]).begins_with("0:13"), "timer runs locally between polls (%s)" % str(hud.get_state()["activity_time"]))
	T.check(int(hud.activity.info.get("checkpoint", 0)) == 3, "checkpoint counter follows get_hud_info")
	if acts != null:
		acts.set("info", {})
	EventBus.activity_finished.emit("street_race_1", {"result_screen": false})
	await T.wait_frames(3)
	T.check(str(hud.get_state()["activity"]) == "", "activity card hides on activity_finished")
	# taxi meter
	var taxi: Node = Game.get_system("taxi")
	if taxi != null:
		taxi.set("riding", true)
		taxi.set("fare", 42)
		await T.wait_frames(20)
		T.check(int(hud.get_state()["taxi_fare"]) == 42, "taxi meter shows get_fare() while riding (%d)" % int(hud.get_state()["taxi_fare"]))
		taxi.set("riding", false)
		await T.wait_frames(20)
		T.check(int(hud.get_state()["taxi_fare"]) == -1, "taxi meter hides when the ride ends")
	# drive-by out of arc
	var car := _scripted(Node3D.new(), FAKE_VEHICLE) as Node3D
	add_child(car)
	car.global_position = pl.global_position
	pl.set("current_vehicle", car)
	pl.set("is_aiming", true)
	st.set("drive_by_in_arc", false)
	await T.wait_frames(20)
	T.check(bool(hud.get_state()["drive_by_blocked"]), "drive-by out of arc shows the blocked reticle")
	st.set("drive_by_in_arc", true)
	await T.wait_frames(2)
	T.check(not bool(hud.get_state()["drive_by_blocked"]), "in arc: normal reticle")
	pl.set("is_aiming", false)
	pl.set("current_vehicle", null)
	await T.wait_frames(20)
	car.queue_free()
	# aircraft altimeter reads altitude_agl
	hud.vehicle.set_vehicle(true, "Test", "heli")
	hud.vehicle.update_values(0.0, 1.0, 123.0)
	T.check(hud.vehicle._alt_str == "ALT 123 m", "aircraft altitude pill")


# --- minimap helpers -----------------------------------------------------------------------------------

func _test_minimap_helpers() -> void:
	var heli := _scripted(Node3D.new(), "extends Node3D\nvar vehicle_class := \"heli\"\nvar spec_id := \"heli_police\"\n") as Node3D
	add_child(heli)
	T.check(Minimap.is_heli(heli), "Minimap.is_heli on a heli vehicle")
	heli.add_to_group(&"police")
	await T.wait_frames(20)       # minimap refreshes its police list at 4 Hz and redraws with a heli glyph
	heli.queue_free()
	var had: Variant = Wanted.get(&"search_center")
	if had is Vector3:
		Wanted.set(&"search_center", Vector3(12.0, 0.0, -34.0))
		T.check(Minimap.search_center().is_equal_approx(Vector3(12.0, 0.0, -34.0)), "search circle uses Wanted.search_center")
		Wanted.set(&"search_center", had)
	else:
		T.log_line("Wanted has no search_center - skipped")


# --- debug overlay coupling ------------------------------------------------------------------------------

func _test_debug_overlay() -> void:
	var box := UI.get_node_or_null("Root/Debug") as CanvasItem
	var was := UI.debug_overlay_visible
	UI.set_debug_overlay(true)
	await T.wait_frames(2)
	if UI.has_rich_debug_overlay():
		T.check(box != null and not box.visible, "basic debug box stays hidden while the debug system owns the overlay")
	else:
		T.check(box != null and box.visible, "basic debug box shows without a debug system")
	UI.set_debug_overlay(was)
	await T.wait_frames(2)
