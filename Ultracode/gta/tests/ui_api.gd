extends Node
## UI module API test (headless).
##   tools\godot.ps1 -Mode headless -Frames 1500 -UserArgs '--test=ui_api','--no_player','--disable=world,traffic,peds,police'
## Covers: structure + theme, notify / prompt / banner / subtitle / fades (also while paused),
## every implemented screen (pause / time scale / input lock / HUD hiding / stack order), the
## global actions through real input events, HUD reactions to simulated EventBus signals,
## waypoint + route, map click, widget kit smoke test. Input-lock count must return to its start.

const FAKE_VEHICLE := """
extends Node3D
var spec_id := "sports"
var vehicle_class := "car"
var health := 760.0
var max_health := 1000.0
var speed_kmh := 88.0
"""

var _waypoint_events: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await TestHarness.wait_frames(6)
	await _run()
	TestHarness.finish()


func _action(action: String, pressed: bool = true) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await TestHarness.wait_frames(3)


func _scripted(base: Node, source: String) -> Node:
	var gs := GDScript.new()
	gs.source_code = source
	gs.reload()
	base.set_script(gs)
	return base


func _run() -> void:
	var T := TestHarness
	var hud := UI.hud as HudRoot
	var lock0 := Game.input_locked

	# --- structure -------------------------------------------------------------------------------
	T.check(hud != null, "HUD is a HudRoot")
	if hud == null:
		return
	T.check(UI.game_theme != null and UI.game_theme.get_type_variation_base(&"HeaderLabel") == &"Label", "theme built with type variations")
	T.check(ResourceLoader.exists(UI.HUD_SCENE), "hud.tscn exists at UI.HUD_SCENE")
	T.check(ResourceLoader.exists(UI.THEME_PATH) and load(UI.THEME_PATH) is Theme, "game_theme.tres exists and loads")
	for id: String in ["pause", "status", "map", "weapon_wheel"]:
		T.check(ResourceLoader.exists(UI.SCREENS[id]), "screen script exists: " + id)
	T.check(hud.minimap != null and hud.minimap.data == UI.map_data, "minimap shares UI.map_data")
	T.check(not hud.minimap.data.places.is_empty() or hud.minimap.data.source != "world", "minimap tolerates a missing world (source=%s)" % hud.minimap.data.source)
	T.check(hud.visible, "HUD visible after game_ready")

	# --- toasts / prompt / banner / subtitle -----------------------------------------------------
	UI.toasts.clear()
	UI.notify("Test toast", "good")
	T.check(UI.toasts.get_count() == 1, "notify adds a toast")
	UI.notify("Test toast", "good")
	T.check(UI.toasts.get_count() == 1, "identical toast is merged, not stacked")
	EventBus.notification.emit("From the bus", "warn")
	T.check(UI.toasts.get_count() == 2, "EventBus.notification from other modules shows a toast")
	for i in 8:
		UI.notify("Flood %d" % i, "info")
	T.check(UI.toasts.get_count() <= UiToasts.MAX_VISIBLE, "toast stack is capped")
	UI.show_prompt("Enter vehicle", "enter_vehicle")
	T.check(UI.get_prompt_text() == "Enter vehicle" and hud.prompt.is_showing() and hud.prompt.key_label == InputSetup.label("enter_vehicle"),
			"show_prompt shows text + key label '%s'" % hud.prompt.key_label)
	UI.hide_prompt()
	T.check(UI.get_prompt_text() == "" and not hud.prompt.is_showing(), "hide_prompt hides it")
	UI.banner("DOWN", "sub line", Color(0.95, 0.36, 0.3), 1.0)
	T.check(UI.is_banner_showing(), "banner shows")
	UI.subtitle("A subtitle line", 1.0)
	await T.wait_frames(2)

	# --- fades (awaitable, also while paused) ---------------------------------------------------
	await UI.fade_out(0.2)
	T.check(UI.get_fade_alpha() > 0.99, "fade_out reaches black")
	await UI.fade_in(0.2)
	T.check(UI.get_fade_alpha() < 0.01, "fade_in clears")
	get_tree().paused = true
	await UI.fade_out(0.15)
	T.check(UI.get_fade_alpha() > 0.99, "fade_out works while the tree is paused")
	await UI.fade_in(0.15)
	get_tree().paused = false
	T.check(UI.get_fade_alpha() < 0.01, "fade_in works while the tree is paused")
	UI.fade_out(1.0)                      # not awaited, then superseded
	await T.wait_frames(2)
	await UI.fade_in(0.0)
	T.check(UI.get_fade_alpha() < 0.01, "a newer fade supersedes a running one")

	# --- every implemented screen ----------------------------------------------------------------
	for id: String in ["pause", "status", "map"]:
		var node := UI.open_screen(id)
		T.check(node != null and UI.is_screen_open(id) and UI.is_screen_open(""), "open " + id)
		T.check(get_tree().paused, id + " pauses the game")
		T.check(Game.input_locked == lock0 + 1, id + " locks input once")
		T.check(not hud.visible, id + " hides the HUD")
		T.check(UI.open_screen(id) == node, id + " is not opened twice")
		await T.wait_frames(4)
		UI.close_screen(id)
		T.check(not UI.is_screen_open(id) and not get_tree().paused and Game.input_locked == lock0 and hud.visible,
				"close " + id + " restores pause / lock / HUD")
		await T.wait_frames(2)

	var wheel := UI.open_screen("weapon_wheel")
	T.check(wheel != null and not get_tree().paused, "weapon wheel opens without pausing")
	T.check(is_equal_approx(Engine.time_scale, 0.15), "weapon wheel slow motion 0.15 (is %.2f)" % Engine.time_scale)
	T.check(Game.input_locked == lock0 + 1 and hud.visible, "weapon wheel locks input, keeps the HUD")
	if wheel != null:
		wheel.call("select_slot", 1)
		T.check(int(wheel.call("get_hovered_slot")) == 1, "wheel select_slot")
		wheel.call("set_pointer", Vector2(0, 110))
		T.check(int(wheel.call("get_hovered_slot")) == 4, "wheel pointer down selects slot 5 (rifle)")
		wheel.call("set_pointer", Vector2(-110, 0))
		T.check(int(wheel.call("get_hovered_slot")) == 6, "wheel pointer left selects slot 7 (heavy)")
	await T.wait_frames(3)
	UI.close_screen("weapon_wheel")
	T.check(is_equal_approx(Engine.time_scale, 1.0) and Game.input_locked == lock0, "closing the wheel restores time scale and lock")

	# --- stack ----------------------------------------------------------------------------------
	UI.open_screen("pause")
	UI.open_screen("map")
	T.check(UI.get_top_screen() == "map" and Game.input_locked == lock0 + 2 and get_tree().paused, "map stacks on pause")
	UI.close_screen()
	T.check(UI.is_screen_open("pause") and not UI.is_screen_open("map") and get_tree().paused, "close_screen() closes the top one, still paused")
	UI.open_screen("status")
	UI.close_all_screens()
	T.check(not UI.is_screen_open("") and not get_tree().paused and Game.input_locked == lock0, "close_all_screens restores everything")
	T.check(UI.open_screen("no_such_screen") == null, "unknown screen id returns null")
	await T.wait_frames(2)

	# --- global actions through real input events ----------------------------------------------
	await _action("pause")
	T.check(UI.is_screen_open("pause"), "pause action opens the pause menu")
	await _action("map")
	T.check(UI.get_top_screen() == "map", "map action opens the map over pause")
	await _action("pause")
	T.check(UI.get_top_screen() == "pause", "pause action closes the top screen")
	await _action("pause")
	T.check(not UI.is_screen_open(""), "pause action closes the pause menu")
	await _action("map")
	T.check(UI.is_screen_open("map"), "map action opens the map")
	await _action("map")
	T.check(not UI.is_screen_open("map"), "map action closes the map")
	await _action("weapon_wheel", true)
	T.check(UI.is_screen_open("weapon_wheel"), "weapon_wheel press opens the wheel")
	await _action("weapon_wheel", false)
	T.check(not UI.is_screen_open("weapon_wheel") and is_equal_approx(Engine.time_scale, 1.0), "weapon_wheel release closes it")
	var dbg := UI.debug_overlay_visible
	await _action("debug_overlay")
	T.check(UI.debug_overlay_visible != dbg, "debug_overlay toggles the overlay")
	await T.wait_frames(20)
	await _action("debug_overlay")
	T.check(UI.debug_overlay_visible == dbg, "debug_overlay toggles back")

	# settings page: back returns to the home page first
	var pause := UI.open_screen("pause", {"page": "settings", "tab": 2})
	await T.wait_frames(3)
	T.check(pause != null and str(pause.get("_page")) == "settings", "pause opens straight into settings")
	UI.handle_action("pause")
	T.check(UI.is_screen_open("pause") and str(pause.get("_page")) == "home", "back leaves settings but keeps the menu")
	UI.handle_action("pause")
	T.check(not UI.is_screen_open("pause"), "back closes the menu")

	# quick save (keeps whatever quick save existed before the test)
	var slot_path: String = SaveSystem.slot_path("quick")
	var had_save: bool = SaveSystem.has_save("quick")
	var backup := FileAccess.get_file_as_string(slot_path) if had_save else ""
	UI.toasts.clear()
	await _action("quick_save")
	T.check(SaveSystem.has_save("quick"), "quick_save action writes the quick slot")
	T.check(UI.toasts.get_texts().has("Game saved"), "quick_save shows a toast")
	if had_save:
		var f := FileAccess.open(slot_path, FileAccess.WRITE)
		if f != null:
			f.store_string(backup)
			f.close()
	else:
		SaveSystem.delete_save("quick")

	# --- HUD reacts to EventBus -----------------------------------------------------------------
	EventBus.player_health_changed.emit(62.0, 40.0)
	var st := hud.get_state()
	T.check(is_equal_approx(float(st["health"]), 62.0) and is_equal_approx(float(st["armor"]), 40.0), "HUD health / armor follow player_health_changed")
	EventBus.player_damaged.emit(25.0, {})
	T.check(float(hud.get_state()["flash"]) > 0.3, "damage flash on player_damaged")
	var money0 := Game.money
	Game.add_money(250)
	T.check(int(hud.get_state()["money"]) == money0 + 250, "HUD money follows money_changed")
	Game.set_money(money0)
	Wanted.set_level(3)
	await T.wait_frames(2)
	T.check(int(hud.get_state()["wanted_level"]) == 3, "wanted stars follow the Wanted level")
	hud.wanted.set_wanted(3, Wanted.State.SEARCH, 0.4)
	T.check(int(hud.get_state()["wanted_state"]) == Wanted.State.SEARCH and is_equal_approx(hud.wanted.escape, 0.4), "wanted strip takes SEARCH + escape progress")
	Wanted.clear("cheat")
	await T.wait_frames(2)
	T.check(int(hud.get_state()["wanted_level"]) == 0, "wanted strip clears")
	EventBus.weapon_equipped.emit("pistol")
	EventBus.ammo_changed.emit("pistol", 9, 48)
	st = hud.get_state()
	T.check(str(st["weapon_id"]) == "pistol" and int(st["in_mag"]) == 9 and int(st["reserve"]) == 48 and bool(st["weapon_shown"]),
			"weapon card follows weapon_equipped / ammo_changed (name '%s')" % hud.weapon.weapon_name)
	EventBus.weapon_reload_started.emit("pistol", 1.2)
	EventBus.weapon_equipped.emit("fists")
	T.check(not bool(hud.get_state()["weapon_shown"]), "weapon card hides when unarmed")
	EventBus.hit_confirmed.emit(null, {"killed": true})
	EventBus.camera_mode_changed.emit("scope")
	T.check(bool(hud.get_state()["scoped"]), "scope overlay on camera_mode_changed('scope')")
	EventBus.camera_mode_changed.emit("third")
	T.check(not bool(hud.get_state()["scoped"]), "scope overlay off again")
	var veh := _scripted(Node3D.new(), FAKE_VEHICLE) as Node3D
	add_child(veh)
	EventBus.player_entered_vehicle.emit(veh, 0)
	await T.wait_frames(3)
	st = hud.get_state()
	T.check(bool(st["in_vehicle"]) and is_equal_approx(float(st["speed"]), 88.0), "vehicle cluster reads speed_kmh (%.0f)" % float(st["speed"]))
	T.check(is_equal_approx(hud.vehicle.health_frac, 0.76), "vehicle cluster reads health / max_health")
	EventBus.player_exited_vehicle.emit(veh)
	T.check(not bool(hud.get_state()["in_vehicle"]), "vehicle cluster hides on exit")
	veh.queue_free()
	EventBus.player_district_changed.emit("midtown")
	st = hud.get_state()
	T.check(str(st["district"]) == "midtown" and str(st["caption"]) == "MIDTOWN", "district caption on player_district_changed")
	EventBus.radio_station_changed.emit("coast_fm")
	var radio := Game.get_system("radio")
	if radio != null and radio.has_method("is_listening") and not bool(radio.call("is_listening")):
		# a real radio system is loaded and the player is not in a vehicle: no caption expected
		T.check(str(hud.get_state()["caption"]) == "MIDTOWN", "radio caption stays quiet while not listening")
	else:
		T.check(str(hud.get_state()["caption"]) == "COAST FM", "radio caption on radio_station_changed")
	EventBus.time_changed.emit(WorldClock.hour)
	T.check(str(hud.get_state()["time"]) == WorldClock.get_time_string(), "clock follows time_changed")
	EventBus.weather_changed.emit("rain", "clear")
	UI.toasts.clear()
	var lvl0 := int(Skills.get_level("driving"))
	Skills.add_xp("driving", 6.0)
	await T.wait_frames(3)
	var skill_toast := false
	for txt in UI.toasts.get_texts():
		if txt.contains("Driving"):
			skill_toast = true
	T.check(int(Skills.get_level("driving")) > lvl0 and skill_toast, "skill-up toast on skill_changed")
	UI.set_hud_visible(false)
	T.check(not hud.visible, "set_hud_visible(false)")
	UI.set_hud_visible(true)
	T.check(hud.visible, "set_hud_visible(true)")

	# --- waypoint / route / map click -------------------------------------------------------------
	EventBus.waypoint_changed.connect(_on_waypoint)
	UI.set_waypoint(Vector3(60.0, 0.0, 80.0))
	T.check(UI.has_waypoint() and UI.nav.route.size() >= 2 and _waypoint_events.size() == 1 and bool(_waypoint_events[0]),
			"set_waypoint builds a route and emits waypoint_changed")
	UI.clear_waypoint()
	T.check(not UI.has_waypoint() and _waypoint_events.size() == 2 and not bool(_waypoint_events[1]), "clear_waypoint emits waypoint_changed(false)")
	EventBus.waypoint_changed.emit(true, Vector3(10.0, 0.0, 10.0))
	T.check(UI.has_waypoint(), "a waypoint emitted by another module is adopted")
	UI.clear_waypoint()
	var map := UI.open_screen("map")
	await T.wait_frames(5)
	if map != null:
		var where: Vector3 = map.call("click_at", Vector2(200.0, 200.0))
		T.check(UI.has_waypoint() and where != Vector3.INF, "map click sets a waypoint at %s" % str(where))
		var back: Vector2 = map.call("to_view", Vector2(UI.nav.waypoint.x, UI.nav.waypoint.z))
		map.call("click_at", back)
		T.check(not UI.has_waypoint(), "clicking the waypoint again clears it")
	UI.close_screen("map")
	EventBus.waypoint_changed.disconnect(_on_waypoint)

	# --- widget kit smoke test ---------------------------------------------------------------------
	await _widgets()

	T.check(UI.stats != null and UI.stats.format("distance_foot") != "", "stats tracker formats values")
	T.check(Game.input_locked == lock0, "input lock count is back to its start (%d)" % Game.input_locked)
	T.check(not get_tree().paused and is_equal_approx(Engine.time_scale, 1.0), "not paused, time scale 1.0 at the end")


func _on_waypoint(has: bool, _pos: Vector3) -> void:
	_waypoint_events.append(has)


func _widgets() -> void:
	var T := TestHarness
	var host := Control.new()
	host.theme = UI.game_theme
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.add_child(host)
	var panel := UiKit.panel(&"SolidPanel")
	panel.position = Vector2(100, 100)
	panel.custom_minimum_size = Vector2(700, 600)
	host.add_child(panel)
	panel.add(UiKit.header("Widgets", "smoke test", "$1,234"))
	var tabs := UiTabBar.new(["One", "Two", "Three"])
	panel.add(tabs)
	var tab_seen := [-1]
	tabs.tab_changed.connect(func(i: int) -> void: tab_seen[0] = i)
	tabs.select(2)
	T.check(tabs.current == 2 and tab_seen[0] == 2, "UiTabBar select emits tab_changed")
	var list := UiList.new()
	list.custom_minimum_size.y = 200.0
	panel.add(list)
	list.set_items([{"text": "Pistol", "price": 450, "icon": &"handgun", "id": "pistol"},
			{"text": "Carbine", "price": 999999, "sub": "Too expensive", "id": "carbine"},
			{"text": "Bat", "price": 60, "owned": true, "id": "bat"}, {"text": "Locked", "disabled": true}])
	var act := [""]
	list.item_activated.connect(func(_i: int, item: Dictionary) -> void: act[0] = str(item.get("id", "")))
	await T.wait_frames(2)
	list.select(1)
	T.check(list.selected == 1 and list.get_count() == 4, "UiList selection")
	list.get_row(0).activated.emit()
	T.check(act[0] == "pistol" and list.selected == 0, "UiList item_activated carries the item")
	var price := UiPriceRow.new("Suppressor", 350)
	panel.add(price)
	T.check(price.is_affordable() == (Game.money >= 350) and price.get_price() == 350, "UiPriceRow affordability")
	var slider := UiSliderRow.new("Volume", 0.0, 1.0, 0.05, 0.5, "percent")
	panel.add(slider)
	var sv := [-1.0]
	slider.value_changed.connect(func(v: float) -> void: sv[0] = v)
	slider.slider.value = 0.75
	T.check(is_equal_approx(sv[0], 0.75) and is_equal_approx(slider.get_value(), 0.75), "UiSliderRow value_changed")
	var opt := UiOptionRow.new("Shadows", ["Off", "Low", "High"], 0)
	panel.add(opt)
	var ov := [-1]
	opt.changed.connect(func(i: int) -> void: ov[0] = i)
	opt.step(1)
	opt.step(1)
	opt.step(1)
	T.check(ov[0] == 0 and opt.get_text() == "Off", "UiOptionRow cycles and wraps")
	panel.add(UiBar.new(UiStyle.TEAL, &"bolt"))
	panel.add(UiKeyHints.new([{"action": "pause", "text": "Back"}, {"key": "Enter", "text": "Select"}]))
	T.check(UiKeyHints.labels_of({"action": "pause"})[0] == "Esc", "UiKeyHints resolves action labels")
	var dlg := UiConfirmDialog.ask(host, "Confirm?", "Body text", "Yes", "No")
	var res := [0]
	dlg.confirmed.connect(func() -> void: res[0] = 1)
	await T.wait_frames(2)
	dlg.accept()
	T.check(res[0] == 1 and not dlg.is_open(), "UiConfirmDialog confirm")
	var dlg2 := UiConfirmDialog.ask(host, "Cancel?", "", "Yes", "No")
	var res2 := [0]
	dlg2.cancelled.connect(func() -> void: res2[0] = 1)
	await T.wait_frames(2)
	await _action("pause")
	T.check(res2[0] == 1 and not UI.is_screen_open("pause"), "Esc cancels a confirm dialog without opening the pause menu")
	T.check(UiStyle.money(1234567) == "$1,234,567" and UiStyle.money(-50) == "-$50", "UiStyle.money formatting")
	T.check(UiMapData.district_name("residential") != "", "district display names")
	await T.wait_frames(2)
	host.queue_free()
	await T.wait_frames(2)
