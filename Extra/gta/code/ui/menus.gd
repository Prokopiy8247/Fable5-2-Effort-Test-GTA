extends Node
## Pause menu (stats, skills, controls, settings, save/load), the in-game phone (taxi, mechanic,
## waypoints, quick save, camera / photo mode, radio) and photo mode.

const CONTROLS := [
	["WASD", "Move / drive"], ["Mouse", "Look / aim"], ["Shift", "Sprint  (plane: throttle up)"], ["Space", "Jump / vault / handbrake / parachute"],
	["C or Ctrl", "Crouch + stealth  (swim: dive, heli: descend)"], ["Q", "Take cover  (vehicle: siren, heli: yaw)"], ["F", "Enter / exit / steal vehicle"],
	["E", "Interact / shop / ladder"], ["LMB / RMB", "Fire - melee / aim - block"], ["R", "Reload"], ["X", "Quick melee    G  throw grenade"],
	["1-8 / wheel", "Weapon class / next weapon"], ["Tab (hold)", "Weapon wheel"], ["Space while aiming", "Combat roll"], ["V", "First / third person"],
	["B", "Look behind"], ["H / L / N / K", "Horn / headlights / radio / convertible roof"], ["M", "Map + waypoint"], ["T or Up", "Phone"],
	["P", "Stats"], ["F5 / F9", "Quick save / load"], ["F1", "Benchmark / admin menu"], ["Esc", "Pause"]]

var menu: MenuPanel
var photo := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu = MenuPanel.new()
	add_child(menu)


func _unhandled_input(ev: InputEvent) -> void:
	if photo:
		if ev.is_action_pressed("pause") or ev.is_action_pressed("phone"):
			_photo(false)
		elif ev.is_action_pressed("fire") or ev.is_action_pressed("photo"):
			_snap()
		return
	if G.player == null:
		return
	if ev.is_action_pressed("pause") and G.ui_blocking == 0:
		open_pause()
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("phone") and G.ui_blocking == 0 and not G.player.dead:
		open_phone()
	elif ev.is_action_pressed("stats") and G.ui_blocking == 0:
		open_stats(true)
	elif ev.is_action_pressed("photo") and G.ui_blocking == 0:
		_snap()


func open_pause() -> void:
	menu.open("Cinder Bay", func(m: MenuPanel):
		m.set_items([
			{"text": "Resume", "fn": m.close, "no_refresh": true},
			{"text": "Stats & skills", "right": ">", "fn": open_stats.bind(false), "no_refresh": true},
			{"text": "Controls", "right": ">", "fn": _controls, "no_refresh": true},
			{"text": "Settings", "right": ">", "fn": _settings, "no_refresh": true},
			{"text": "Save game", "right": "F5", "fn": func():
				G.say("Game saved" if Save.save_game() else "Cannot save right now", Color(0.6, 1.0, 0.6))},
			{"text": "Load game", "right": "F9", "fn": func():
				m.close()
				if Save.load_game():
					G.say("Game loaded", Color(0.6, 1.0, 0.6)), "no_refresh": true},
			{"text": "Benchmark / admin menu", "right": "F1", "fn": func():
				m.close()
				if G.main.has_node("AdminMenu"):
					G.main.get_node("AdminMenu").open(), "no_refresh": true},
			{"text": "Quit to desktop", "fn": func(): get_tree().quit(), "no_refresh": true},
		]), {"pause": true, "side": "center", "sub": "Free roam sandbox  -  no missions, no objectives. Do whatever you like."})


func open_stats(top: bool) -> void:
	var p: Player = G.player
	var build := func(m: MenuPanel):
		var items: Array = [{"header": "Skills  (improve by doing)"}]
		for s in Player.SKILLS:
			var v: float = p.skill(s)
			items.append({"text": Player.SKILL_NAMES[s], "right": "%s  %d%%" % ["|".repeat(int(v * 20.0)) + ".".repeat(20 - int(v * 20.0)), int(v * 100.0)], "disabled": false, "right_color": UIKit.TEAL})
		items.append({"header": "Record"})
		items.append({"text": "Cash", "right": G.fmt_money(p.money)})
		items.append({"text": "Takedowns", "right": str(int(p.stats.kills))})
		items.append({"text": "Shots fired", "right": str(int(p.stats.shots))})
		items.append({"text": "Distance travelled", "right": "%.1f km" % (float(p.stats.distance) / 1000.0)})
		items.append({"text": "Vehicles stolen", "right": str(int(p.stats.cars_stolen))})
		items.append({"text": "Stunt jumps landed", "right": str(int(p.stats.stunts))})
		items.append({"text": "Hospital visits / arrests", "right": "%d / %d" % [int(p.stats.deaths), int(p.stats.busts)]})
		items.append({"text": "Highest wanted level", "right": "%d stars" % (G.wanted.stats_max if G.wanted else 0)})
		m.set_items(items)
	menu.open("Stats", build, {"pause": top, "side": "center"})


func _controls() -> void:
	menu.open("Controls", func(m: MenuPanel):
		var items: Array = []
		for c in CONTROLS:
			items.append({"text": c[1], "right": c[0], "right_color": UIKit.TEAL})
		m.set_items(items), {})


func _settings() -> void:
	menu.open("Settings", func(m: MenuPanel):
		var S: Dictionary = G.settings
		m.set_items([
			{"text": "Mouse sensitivity", "right": "< %.1f >" % (float(S.mouse_sens) * 1000.0), "adjust": func(d: int):
				S.mouse_sens = clampf(float(S.mouse_sens) + d * 0.0003, 0.0008, 0.008)},
			{"text": "Invert Y", "right": "On" if S.invert_y else "Off", "fn": func(): S.invert_y = not S.invert_y},
			{"text": "Master volume", "right": "< %d%% >" % int(float(S.master_volume) * 100.0), "adjust": func(d: int):
				S.master_volume = clampf(float(S.master_volume) + d * 0.1, 0.0, 1.0)
				Sfx.apply_volume()},
			{"text": "Field of view", "right": "< %d >" % int(S.fov), "adjust": func(d: int): S.fov = clampf(float(S.fov) + d * 2.0, 55.0, 90.0)},
			{"text": "Population density", "right": "< %d%% >" % int(float(S.density) * 100.0), "adjust": func(d: int): S.density = clampf(float(S.density) + d * 0.1, 0.3, 1.5)},
			{"text": "Sun shadows", "right": "On" if S.shadows else "Off", "fn": func(): S.shadows = not S.shadows},
			{"text": "Fullscreen", "right": "On" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "Off", "fn": func():
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)},
			{"text": "Delete save file", "color": Color(1, 0.5, 0.4), "fn": func():
				Save.delete_save()
				G.say("Save deleted", Color(1, 0.6, 0.4))},
		]), {"on_close": Callable()})
	Save.save_settings()


# ------------------------------------------------------------------ phone
func open_phone() -> void:
	var p: Player = G.player
	p.vis.phone = 1.0
	menu.open("Pebble Phone", func(m: MenuPanel):
		var items: Array = []
		items.append({"header": "Services"})
		items.append({"text": "Call a taxi", "right": "$ by distance", "fn": func():
			m.close()
			if G.services:
				G.services.call_taxi(), "no_refresh": true})
		items.append({"text": "Mechanic: deliver a stored vehicle", "right": "$100 >", "fn": _mechanic, "no_refresh": true})
		items.append({"text": "Paramedics to my location", "right": "free", "fn": func():
			m.close()
			if G.services:
				G.services.dispatch("ambulance", G.player.global_position_now()), "no_refresh": true})
		items.append({"header": "Tools"})
		items.append({"text": "Map waypoint", "right": ">", "fn": _waypoints, "no_refresh": true})
		items.append({"text": "Camera  (photo mode)", "fn": func():
			m.close()
			_photo(true), "no_refresh": true})
		items.append({"text": "Quick save", "fn": func():
			G.say("Game saved" if Save.save_game() else "Cannot save right now", Color(0.6, 1.0, 0.6))})
		items.append({"text": "Radio station", "right": "< %s >" % Sfx.STATIONS[Sfx.station], "adjust": func(d: int):
			Sfx.station = posmod(Sfx.station + d, Sfx.STATIONS.size())
			Sfx.radio.stop()})
		items.append({"header": "Info"})
		items.append({"text": "Time", "right": G.timew.time_string() if G.timew else "", "disabled": true})
		items.append({"text": "Weather", "right": String(G.timew.weather).capitalize() if G.timew else "", "disabled": true})
		items.append({"text": "District", "right": WorldLayout.district_at(p.global_position_now()), "disabled": true})
		m.set_items(items), {"side": "right", "sub": "", "on_close": func(): p.vis.phone = 0.0})


func _mechanic() -> void:
	var it: Node = G.main.get_node("Interactions") if G.main.has_node("Interactions") else null
	menu.open("Mechanic", func(m: MenuPanel):
		var items: Array = []
		if it == null or it.garage.is_empty():
			items.append({"text": "No stored vehicles - use the safehouse garage", "disabled": true})
		else:
			for i in it.garage.size():
				var st: Dictionary = it.garage[i]
				items.append({"text": Defs.VEHICLES[st.vid].name, "swatch": Color(st.get("paint", "ffffff")), "right": "$100", "fn": func():
					if G.player.spend(100):
						m.close()
						it._retrieve(i, true)
						G.say("Your vehicle has been delivered", Color(0.6, 1.0, 0.6)), "no_refresh": true})
		m.set_items(items), {})


func _waypoints() -> void:
	menu.open("Waypoint", func(m: MenuPanel):
		var items: Array = [{"text": "Clear waypoint", "fn": func():
			G.hud.set_waypoint(null)
			m.close(), "no_refresh": true}]
		for id in G.world.pois.keys():
			var poi: Dictionary = G.world.pois[id]
			items.append({"text": poi.label, "right": "%d m" % int((poi.pos as Vector3).distance_to(G.player.global_position_now())), "fn": func():
				G.hud.set_waypoint(poi.pos)
				m.close(), "no_refresh": true})
		m.set_items(items), {})


func _photo(on: bool) -> void:
	photo = on
	if G.hud:
		G.hud.visible = not on
	if on:
		G.say("Photo mode: move the camera with the mouse, LMB or F12 to shoot, Esc to leave", UIKit.TEAL)
		get_tree().create_timer(0.1).timeout.connect(func(): if photo and G.hud: G.hud.visible = false)


func _snap() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://photos"))
	var path := "user://photos/cinderbay_%d.png" % int(Time.get_unix_time_from_system())
	img.save_png(path)
	Sfx.ui("select")
	if not photo:
		G.say("Screenshot saved to " + ProjectSettings.globalize_path(path), UIKit.DIM)
