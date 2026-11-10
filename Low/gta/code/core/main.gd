extends Node3D
# Bootstrap: builds the whole sandbox in code and drops the player straight into free roam.


func _ready() -> void:
	G.main = self
	var t0 := Time.get_ticks_msec()
	G.audio = GameAudio.new()
	add_child(G.audio)
	G.fx = FX.new()
	add_child(G.fx)
	G.roads = RoadGraph.new()
	G.sky = SkySystem.new()
	add_child(G.sky)
	G.world = WorldBuilder.new()
	add_child(G.world)
	G.world.build()
	G.locations["Safehouse"] = Vector3(-127.5, 0.4, 3)
	G.player = Player.new()
	add_child(G.player)
	G.player.global_position = G.locations["Safehouse"]
	G.player.rotation.y = -PI / 2
	G.cam = CameraRig.new()
	add_child(G.cam)
	G.cam.yaw = -PI / 2
	G.hud = HUD.new()
	add_child(G.hud)
	G.menus = Menus.new()
	add_child(G.menus)
	G.traffic = Traffic.new()
	add_child(G.traffic)
	G.pop = Population.new()
	add_child(G.pop)
	G.wanted = Wanted.new()
	add_child(G.wanted)
	G.activities = Activities.new()
	add_child(G.activities)
	G.save = SaveSystem.new()
	add_child(G.save)
	G.traffic.setup_parked()
	G.pop.setup_fixed()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var test := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			test = a.substr(11)
	if test == "":
		if G.save.load_game():
			G.notify("Save loaded. Free roam: no missions. F1 admin menu, Esc pause/controls.", 7.0)
		else:
			G.notify("Welcome to Port Fable. Free roam: no missions. F1 admin menu, Esc pause/controls.", 8.0)
	else:
		var at := AutoTest.new()
		at.plan = test
		add_child(at)
	print("[boot] world built in %d ms: %d props, %d vehicles, %d buildings rects" % [Time.get_ticks_msec() - t0, G.props.size(), G.vehicles.size(), G.world.rects.size()])
