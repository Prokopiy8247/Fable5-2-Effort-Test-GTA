extends Node
## UI screenshot run (windowed, short). Drives the HUD with fake values and captures every
## implemented screen to qa/screenshots/ui_*.png.
##   tools\godot.ps1 -Mode window -Frames 560 -UserArgs '--test=ui_shots','--no_player','--disable=world,traffic,peds,police,vehicles,pickups,props,interactions,city,emergency,wildlife,shops,garage,transit,taxi,activities,respawn'
## With the world system enabled (drop "world" from --disable, keep --no_player) the map shots
## use the real World.get_minimap_data(); otherwise the WorldLayout fallback is drawn.
## Optional user arg --ui_only=<name>[,<name>...] captures only those shots (hud_foot, hud_vehicle, hud_search,
## hud_low, banner, wheel, pause, settings, status, map, map_zoom, widgets).

const FAKE_PLAYER := """
extends Node3D
var health := 62.0
var max_health := 100.0
var armor := 40.0
var max_armor := 100.0
var stamina := 0.55
var breath := 1.0
var is_dead := false
var current_vehicle: Node3D = null
var inventory: Node = null
"""

const FAKE_INVENTORY := """
extends Node
var current_id := "pistol"
var spread := 2.4
var owned: Array = ["fists", "bat", "pistol", "heavy_pistol", "smg", "pump_shotgun", "assault_rifle", "carbine", "sniper_rifle", "grenade"]
var ammo := {"pistol": [9, 48], "heavy_pistol": [7, 28], "smg": [30, 120], "pump_shotgun": [6, 24],
	"assault_rifle": [30, 150], "carbine": [25, 90], "sniper_rifle": [5, 15], "grenade": [4, 0]}
var equipped: Array = []
func get_current_spread() -> float:
	return spread if current_id != "fists" and current_id != "bat" else 0.0
func get_weapons() -> Array:
	return owned
func get_ammo(id: String) -> Dictionary:
	if not ammo.has(id):
		return {"in_mag": -1, "reserve": -1, "mag_size": 0}
	var a: Array = ammo[id]
	return {"in_mag": a[0], "reserve": a[1], "mag_size": 0 if id == "grenade" else int(a[0])}
func equip(id: String) -> bool:
	current_id = id
	equipped.append(id)
	EventBus.weapon_equipped.emit(id)
	var a := get_ammo(id)
	EventBus.ammo_changed.emit(id, a["in_mag"], a["reserve"])
	return true
"""

const FAKE_VEHICLE := """
extends Node3D
var spec_id := "sports"
var vehicle_class := "car"
var health := 760.0
var max_health := 1000.0
var speed_kmh := 87.0
"""

var _only: String = ""
var _player: Node3D
var _inv: Node
var _vehicle: Node3D
var _cops: Array[Node3D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--ui_only="):
			_only = a.substr(10)
	await TestHarness.wait_frames(24)
	await _run()
	TestHarness.finish()


func _scripted(base: Node, source: String) -> Node:
	var gs := GDScript.new()
	gs.source_code = source
	gs.reload()
	base.set_script(gs)
	return base


func _want(shot_name: String) -> bool:
	return _only == "" or shot_name in _only.split(",")


func _shot(shot_name: String, frames: int = 14) -> void:
	await TestHarness.wait_frames(frames)
	await TestHarness.shot("ui_" + shot_name)


func _run() -> void:
	var T := TestHarness
	var hud := UI.hud as HudRoot
	T.check(hud != null, "HUD exists")
	if hud == null:
		return
	# --- fake player + inventory so every HUD source has data ------------------------------------
	_player = _scripted(Node3D.new(), FAKE_PLAYER) as Node3D
	_player.name = "FakePlayer"
	_inv = _scripted(Node.new(), FAKE_INVENTORY)
	_inv.name = "Inventory"
	_player.add_child(_inv)
	_player.set("inventory", _inv)
	Game.main.add_child(_player)
	_player.global_position = Vector3(-30.0, 2.5, 70.0)
	_player.rotation.y = deg_to_rad(-35.0)
	Game.set_player(_player)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		cam.global_position = _player.global_position + Vector3(4.0, 5.0, 9.0)
		cam.look_at(_player.global_position + Vector3(0, 1.5, 0))
	if UI.map_data.source == "none" or not UI.map_data.has_map():
		UI.map_data.refresh()
	T.log_line("map data source = %s roads=%d lots=%d places=%d" % [UI.map_data.source, UI.map_data.roads.size(),
			UI.map_data.lots.size(), UI.map_data.places.size()])
	Game.money = 18250          # silent: no "+$13,250" delta in the shots
	hud.sync_all()
	await T.wait_frames(4)

	# --- HUD on foot ---------------------------------------------------------------------------
	EventBus.player_health_changed.emit(62.0, 40.0)
	_inv.call("equip", "pistol")
	EventBus.player_district_changed.emit("midtown")
	if _want("hud_foot"):
		UI.show_prompt("Enter vehicle", "enter_vehicle")
		UI.notify("Pistol ammo +24", "good")
		UI.notify("Street race payout", "money")
		Game.add_money(350)
		await _shot("hud_foot", 22)
		T.check(hud.get_state()["weapon_shown"] and int(hud.get_state()["crosshair_style"]) == 2, "on foot: weapon card + spread crosshair")
		# cost of the HUD in draw calls: same view with the HUD, without the minimap, without the HUD
		await T.wait_frames(4)
		var with_hud := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		hud.minimap.visible = false
		await T.wait_frames(4)
		var no_minimap := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		UI.set_hud_visible(false)
		UI.toasts.visible = false
		await T.wait_frames(4)
		var without_hud := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		hud.minimap.visible = true
		UI.set_hud_visible(true)
		UI.toasts.visible = true
		T.log_line("draw calls: with HUD %d, HUD without minimap %d, no HUD %d  ->  HUD cost %d (minimap %d), map mesh %d tris" % [
				with_hud, no_minimap, without_hud, with_hud - without_hud, with_hud - no_minimap,
				(hud.minimap.get_node("Clip").get_child(0) as MinimapWorldLayer).get_triangle_count()])
		UI.hide_prompt()
		UI.toasts.clear()

	# --- HUD in a vehicle, 3 stars in pursuit, then search ---------------------------------------
	_vehicle = _scripted(Node3D.new(), FAKE_VEHICLE) as Node3D
	Game.main.add_child(_vehicle)
	_vehicle.global_position = _player.global_position
	_vehicle.rotation.y = _player.rotation.y
	for off: Vector3 in [Vector3(40, 0, -20), Vector3(-55, 0, 35), Vector3(20, 0, 70), Vector3(160, 0, -120)]:
		var cop := Node3D.new()
		cop.add_to_group("police")
		Game.main.add_child(cop)
		cop.global_position = _player.global_position + off
		_cops.append(cop)
	if _want("hud_vehicle") or _want("hud_search"):
		_player.set("current_vehicle", _vehicle)
		_player.set("stamina", 1.0)
		EventBus.player_entered_vehicle.emit(_vehicle, 0)
		Wanted.set_level(3)
		UI.set_waypoint(Vector3(120.0, 2.5, -105.0))
		if _want("hud_vehicle"):
			await _shot("hud_vehicle", 40)
			T.check(bool(hud.get_state()["in_vehicle"]) and int(hud.get_state()["wanted_level"]) == 3, "vehicle HUD with 3 stars")
			T.check(int(hud.get_state()["crosshair_style"]) == 0, "no reticle while driving without aiming")
		if _want("hud_search"):
			Wanted.state = Wanted.State.SEARCH
			Wanted.last_known_position = _player.global_position + Vector3(25, 0, -30)
			Wanted.search_radius = 70.0
			Wanted.escape_progress = 0.45
			EventBus.wanted_state_changed.emit(Wanted.State.SEARCH)
			_vehicle.set("speed_kmh", 143.0)
			await _shot("hud_search", 30)
		Wanted.clear("cheat")
		UI.clear_waypoint()
		_player.set("current_vehicle", null)
		EventBus.player_exited_vehicle.emit(_vehicle)

	# --- low health vignette + breath bar --------------------------------------------------------
	if _want("hud_low"):
		_player.set("health", 17.0)
		_player.set("armor", 0.0)
		_player.set("breath", 0.4)
		_player.set("stamina", 0.2)
		EventBus.player_health_changed.emit(17.0, 0.0)
		EventBus.player_damaged.emit(30.0, {})
		_inv.call("equip", "assault_rifle")
		EventBus.hit_confirmed.emit(null, {})
		EventBus.radio_station_changed.emit("coast_fm")
		await _shot("hud_low", 28)
		_player.set("health", 62.0)
		_player.set("armor", 40.0)
		_player.set("breath", 1.0)
		_player.set("stamina", 1.0)
		EventBus.player_health_changed.emit(62.0, 40.0)

	# --- aircraft cluster (altitude), sniper scope, debug overlay ----------------------------------
	if _want("hud_air"):
		_vehicle.set("vehicle_class", "plane")
		_vehicle.set("spec_id", "plane_prop")
		_vehicle.set("speed_kmh", 212.0)
		_vehicle.global_position = _player.global_position + Vector3(0, 148.0, 0)
		_player.set("current_vehicle", _vehicle)
		EventBus.player_entered_vehicle.emit(_vehicle, 0)
		_inv.call("equip", "fists")
		await _shot("hud_air", 30)
		T.check(hud.vehicle.is_aircraft and hud.minimap.get_shown_range() > 200.0, "aircraft: altitude pill + zoomed-out minimap (%.0f m)" % hud.minimap.get_shown_range())
		_player.set("current_vehicle", null)
		EventBus.player_exited_vehicle.emit(_vehicle)
		_vehicle.set("vehicle_class", "car")
		_vehicle.set("spec_id", "sports")
		_vehicle.global_position = _player.global_position
	if _want("scope"):
		_inv.call("equip", "sniper_rifle")
		EventBus.camera_mode_changed.emit("scope")
		await _shot("scope", 10)
		T.check(bool(hud.get_state()["scoped"]) and int(hud.get_state()["crosshair_style"]) == 0, "scope overlay replaces the crosshair")
		EventBus.camera_mode_changed.emit("third")
	if _want("debug"):
		UI.set_debug_overlay(true)
		await _shot("debug", 12)
		UI.set_debug_overlay(false)

	if _want("veil"):
		UI.set_loading_veil(true)
		await _shot("veil", 8)
		UI.set_loading_veil(false)
		for i in 90:
			if not UI.is_loading_veil_visible():
				break
			await T.wait_frames(1)
		T.check(not UI.is_loading_veil_visible(), "loading veil fades out again")

	if _want("banner"):
		UI.banner("DOWN", "Bayview Medical will patch you up", Color(0.95, 0.36, 0.3), 3.0)
		UI.subtitle("Subtitle line: the city never sleeps, and neither do its sirens.", 3.0)
		await _shot("banner", 24)
		UI.banner("", "")
		UI.subtitle("")

	# --- weapon wheel ---------------------------------------------------------------------------
	if _want("wheel"):
		_inv.call("equip", "pistol")
		var wheel := UI.open_screen("weapon_wheel")
		T.check(wheel != null, "weapon wheel opens")
		if wheel != null:
			wheel.call("select_slot", 4)
			await _shot("wheel", 14)
			T.check(str(wheel.call("get_hovered_weapon")) == "assault_rifle", "wheel highlights the rifle slot (%s)" % str(wheel.call("get_hovered_weapon")))
		UI.close_screen("weapon_wheel")
		T.check(str(_inv.get("current_id")) == "assault_rifle", "wheel equips the highlighted weapon on close")
		await T.wait_frames(3)

	# --- menus ----------------------------------------------------------------------------------
	if _want("pause"):
		UI.open_screen("pause")
		await _shot("pause", 16)
		UI.close_all_screens()
	if _want("settings"):
		UI.open_screen("pause", {"page": "settings", "tab": 2})
		await _shot("settings", 16)
		UI.close_all_screens()
	if _want("status"):
		Skills.add_xp("driving", 40.0)
		Skills.add_xp("shooting", 22.0)
		Skills.add_xp("stamina", 12.0)
		UI.open_screen("status")
		await _shot("status", 16)
		UI.close_all_screens()
	if _want("map") or _want("map_zoom"):
		UI.set_waypoint(Vector3(120.0, 2.5, -105.0))
		var map := UI.open_screen("map")
		if _want("map"):
			await _shot("map", 18)
		if _want("map_zoom") and map != null:
			map.call("focus_on", Vector2(_player.global_position.x, _player.global_position.z), 2.6)
			await _shot("map_zoom", 12)
		UI.close_all_screens()
		UI.clear_waypoint()
	if _want("widgets"):
		await _widgets()

	# --- cleanup --------------------------------------------------------------------------------
	T.check(not UI.is_screen_open("") and Game.input_locked == 0 and not get_tree().paused, "everything closed again")
	for c in _cops:
		c.queue_free()
	Game.player = null
	_player.queue_free()
	_vehicle.queue_free()


## Widget gallery so the next wave can see what the kit looks like.
func _widgets() -> void:
	var host := Control.new()
	host.theme = UI.game_theme
	UI.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.04, 0.085, 0.8)
	host.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := UiKit.margin(null, 80, 60, 80, 60)
	host.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := UiKit.hbox(30)
	margin.add_child(row)
	var left := UiKit.panel(&"GlassPanel")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	left.add(UiKit.header("Bay Arms", "UiHeader + UiTabBar + UiList", UiStyle.money(Game.money)))
	left.add(UiTabBar.new(["Weapons", "Ammo", "Attachments"], 0))
	var list := UiList.new()
	left.add(list)
	list.set_items([
		{"text": "Pistol", "sub": "Reliable 9 mm sidearm", "price": 450, "icon": &"handgun", "owned": true},
		{"text": "SMG", "sub": "High rate of fire, short range", "price": 2400, "icon": &"smg", "badge": "NEW"},
		{"text": "Pump Shotgun", "sub": "Devastating up close", "price": 1800, "icon": &"shotgun"},
		{"text": "Sniper Rifle", "sub": "Scoped, bolt action", "price": 96000, "icon": &"sniper"},
		{"text": "Rocket Launcher", "sub": "Not sold here", "icon": &"heavy", "disabled": true, "right": "LOCKED"},
	])
	left.add(UiKeyHints.new([{"keys": ["W", "S"], "text": "Navigate"}, {"key": "Enter", "text": "Buy"}, {"action": "pause", "text": "Back"}]))
	var right := UiKit.panel(&"GlassPanel")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add(UiKit.label("ROWS", &"SectionLabel"))
	right.add(UiPriceRow.new("Suppressor", 350, false, &"handgun", "UiPriceRow"))
	right.add(UiSliderRow.new("UiSliderRow", 0.0, 1.0, 0.05, 0.65, "percent"))
	right.add(UiOptionRow.new("UiOptionRow", ["Low", "Medium", "High"], 1))
	var bar := UiBar.new(UiStyle.TEAL_LIGHT, &"bolt")
	bar.value = 0.62
	bar.value_text = "62"
	right.add(bar)
	right.add(UiKit.separator())
	right.add(UiKit.stat_row("UiKit.stat_row", "1,250 m"))
	right.add(UiKit.paragraph("UiKit.paragraph: muted wrapping body text for descriptions and notes."))
	var buttons := UiKit.hbox(14)
	buttons.add_child(UiKit.button("Button"))
	buttons.add_child(UiKit.button("Accent", Callable(), &"AccentButton"))
	buttons.add_child(UiKit.button("Ghost", Callable(), &"GhostButton"))
	right.add(buttons)
	var icons := UiCanvas.new(_draw_icons)
	icons.custom_minimum_size = Vector2(740.0, 190.0)
	right.add(icons)
	await TestHarness.wait_frames(6)
	list.select(1)
	await _shot("widgets", 8)
	UiConfirmDialog.ask(host, "Quit Halcyon Bay?", "UiConfirmDialog: unsaved progress will be lost.", "Quit", "Stay", true)
	await _shot("widgets_dialog", 8)
	host.queue_free()
	await TestHarness.wait_frames(2)


func _draw_icons(c: UiCanvas) -> void:
	var ids: Array[StringName] = [&"heart", &"shield", &"star", &"bolt", &"house", &"hospital", &"police", &"gun_shop", &"wrench",
			&"shirt", &"scissors", &"bag", &"drop", &"parking", &"plane", &"helipad", &"anchor", &"lighthouse", &"mountain",
			&"target", &"taxi", &"flag", &"umbrella", &"tram", &"ramp", &"pin", &"car", &"boat", &"heli", &"person", &"radio",
			&"gear", &"map", &"stats", &"save", &"load", &"power", &"play", &"lock", &"info", &"warn", &"sun", &"moon", &"cloud",
			&"rain", &"storm", &"fog", &"bubbles", &"speed", &"dollar", &"fists", &"bat", &"handgun", &"smg", &"shotgun",
			&"rifle", &"sniper", &"heavy", &"grenade", &"check", &"close"]
	for i in ids.size():
		@warning_ignore("integer_division")
		var p := Vector2(22.0 + (i % 16) * 46.0, 22.0 + (i / 16) * 46.0)
		UiIcons.draw(c, ids[i], p, 30.0, UiStyle.CREAM)
