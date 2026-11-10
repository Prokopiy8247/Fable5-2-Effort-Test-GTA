extends Node3D
## Main scene: builds the world and boots every free-roam system. No missions, no menus in the way:
## launch -> world -> player control.

const SYSTEMS := [
	["fx", "res://gta/code/world/fx.gd"],
	["timew", "res://gta/code/world/time_weather.gd"],
	["traffic", "res://gta/code/traffic/traffic_manager.gd"],
	["peds", "res://gta/code/ai/ped_manager.gd"],
	["wanted", "res://gta/code/police/wanted.gd"],
	["wildlife", "res://gta/code/ai/wildlife.gd"],
	["services", "res://gta/code/world/services.gd"],
]


func _ready() -> void:
	G.main = self
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			G.test_mode = a.substr(7)
	var t0 := Time.get_ticks_msec()
	var w := WorldBuilder.new()
	w.name = "World"
	add_child(w)
	G.world = w
	w.build()
	print("[main] world built in %d ms" % (Time.get_ticks_msec() - t0))
	for s in SYSTEMS:
		var n := _spawn(s[1], s[0].capitalize())
		if n:
			G.set(s[0], n)
	var p := _spawn("res://gta/code/player/player.gd", "Player")
	if p:
		G.player = p
	var h := _spawn("res://gta/code/ui/hud.gd", "HUD")
	if h:
		G.hud = h
	_spawn("res://gta/code/world/interactions.gd", "Interactions")
	_spawn("res://gta/code/ui/menus.gd", "Menus")
	_spawn("res://gta/code/world/activities.gd", "Activities")
	_spawn("res://gta/code/world/train.gd", "Train")
	_spawn("res://gta/code/debug/admin_menu.gd", "AdminMenu")
	if G.test_mode != "":
		_spawn("res://gta/code/debug/test_harness.gd", "TestHarness")
	elif Save and Save.has_method("autoload_game"):
		Save.autoload_game()
	G.game_loaded.emit()
	print("[main] ready in %d ms" % (Time.get_ticks_msec() - t0))


func _spawn(path: String, nm: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var scr = load(path)
	if scr == null:
		push_error("Failed to load " + path)
		return null
	var n: Node = scr.new()
	n.name = nm
	add_child(n)
	return n
