extends RefCounted
## Creates the gameplay layer on top of the generated world: entity containers, FX,
## skills, the player + camera, UI and every sandbox system. Called once by main.gd.

const SPAWN := Vector3(-185.0, 0.2, 137.0)

static func _node(parent: Node, node_name: String, n: Node = null) -> Node:
	if n == null:
		n = Node3D.new()
	n.name = node_name
	parent.add_child(n)
	return n

static func boot(main: Node3D) -> void:
	var entities := _node(main, "Entities")
	_node(entities, "Vehicles")
	_node(entities, "NPCs")
	_node(entities, "Pickups")
	var systems := _node(main, "Systems", Node.new())
	Game.fx = FX.new()
	main.add_child(Game.fx)
	Game.skills = Skills.new()
	Game.skills.name = "Skills"
	systems.add_child(Game.skills)
	# --- player + camera
	var player := Player.new()
	entities.add_child(player)
	player.global_position = SPAWN
	player.set_face_yaw(PI)
	Game.player = player
	var cam := CameraRig.new()
	main.add_child(cam)
	cam.yaw = PI
	Game.cam = cam
	# --- UI
	var ui := CanvasLayer.new()
	ui.name = "UI"
	main.add_child(ui)
	Game.ui = ui
	var hud := HUD.new()
	ui.add_child(hud)
	Game.hud = hud
	# --- sandbox systems (each one is optional so partial builds still run)
	for entry in [
		["pickups", "res://gta/code/world/pickups.gd"],
		["wanted", "res://gta/code/police/wanted_system.gd"],
		["police", "res://gta/code/police/police_dispatch.gd"],
		["traffic", "res://gta/code/traffic/traffic_manager.gd"],
		["peds", "res://gta/code/ai/ped_manager.gd"],
		["wildlife", "res://gta/code/ai/wildlife_manager.gd"],
		["services", "res://gta/code/police/emergency_services.gd"],
		["garage", "res://gta/code/world/garage_system.gd"],
		["activities", "res://gta/code/activities/activities.gd"],
		["transit", "res://gta/code/world/transit.gd"],
	]:
		if ResourceLoader.exists(entry[1]):
			var script: GDScript = load(entry[1])
			var n: Node = script.new()
			n.name = String(entry[0]).capitalize()
			systems.add_child(n)
			Game.set(entry[0], n)
	for ui_script: String in ["res://gta/code/ui/ui_manager.gd"]:
		if ResourceLoader.exists(ui_script):
			var us: GDScript = load(ui_script)
			var un: Node = us.new()
			ui.add_child(un)
	if ResourceLoader.exists("res://gta/code/world/locations.gd"):
		var ls: GDScript = load("res://gta/code/world/locations.gd")
		var ln: Node = ls.new()
		ln.name = "Locations"
		systems.add_child(ln)
	if ResourceLoader.exists("res://gta/code/audio/ambience.gd"):
		var asr: GDScript = load("res://gta/code/audio/ambience.gd")
		var an: Node = asr.new()
		an.name = "Ambience"
		systems.add_child(an)
	_spawn_world_vehicles()
	Game.capture_mouse()

static func _spawn_world_vehicles() -> void:
	var world: World = Game.world
	if world == null or world.city == null:
		return
	# the player's own car, parked outside the safehouse
	var car := VehicleFactory.spawn("car_sedan", Vector3(-176.0, 0.0, 133.9), -PI * 0.5, {"tag": "player", "personal": true, "paint": Color.html("2aa59a")})
	if car != null:
		car.set_meta("home", true)
	if Game.traffic != null and Game.traffic.has_method("spawn_static"):
		Game.traffic.spawn_static()
		return
	for s in world.city.vehicle_spawns:
		var id := String(s["id"])
		if not VehicleDB.exists(id):
			continue
		# only spawn special vehicles whose model exists (no fake breadth), cars may use the stand-in
		if not VehicleDB.has_model(id) and VehicleDB.get_v(id).get("kind", &"car") != &"car":
			continue
		var tag := String(s.get("tag", ""))
		var owner_tag := "police" if tag.begins_with("police") else ("parked" if tag != "taxi_depot" else "parked")
		VehicleFactory.spawn(id, s["pos"], float(s["yaw"]), {"tag": owner_tag})
