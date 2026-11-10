extends Node3D
## Bootstrap of the free-roam session (res://gta/scenes/bootstrap/main.tscn).
## Launch -> build world systems from BootManifest -> spawn player -> EventBus.game_ready.
## There is no menu gate and no mission layer: the player is in control immediately.

var _entities: Node3D


func _ready() -> void:
	Game.main = self
	_entities = Node3D.new()
	_entities.name = "Entities"
	add_child(_entities)
	await _boot()


func _boot() -> void:
	var t0 := Time.get_ticks_msec()
	for entry: Dictionary in BootManifest.SYSTEMS:
		var sys_name: String = entry["name"]
		var path: String = entry["path"]
		if Game.is_disabled(sys_name):
			print("[Main] system disabled by flag: ", sys_name)
			continue
		if not ResourceLoader.exists(path):
			continue
		var res: Resource = load(path)
		var node: Node = null
		if res is PackedScene:
			node = (res as PackedScene).instantiate()
		elif res is Script:
			if not (res as Script).can_instantiate():
				push_error("[Main] system '%s' has script errors, skipped: %s" % [sys_name, path])
				continue
			node = (res as Script).new() as Node
		if node == null:
			push_error("[Main] could not create system '%s' from %s" % [sys_name, path])
			continue
		node.name = sys_name.to_pascal_case()
		add_child(node)
		Game.register_system(sys_name, node)
		if node.has_method("setup"):
			var t1 := Time.get_ticks_msec()
			await node.call("setup")
			print("[Main] %s setup in %d ms" % [sys_name, Time.get_ticks_msec() - t1])
	_spawn_player()
	await get_tree().process_frame
	Game.is_ready = true
	print("[Main] boot finished in %d ms, systems: %s" % [Time.get_ticks_msec() - t0, str(Game.systems.keys())])
	EventBus.game_ready.emit()


func _spawn_player() -> void:
	if Game.flags.has("no_player"):
		_fallback_camera()
		return
	if not ResourceLoader.exists(BootManifest.PLAYER_SCENE):
		push_warning("[Main] player scene missing: " + BootManifest.PLAYER_SCENE)
		_fallback_camera()
		return
	var scene := load(BootManifest.PLAYER_SCENE) as PackedScene
	if scene == null:
		push_error("[Main] player scene failed to load")
		_fallback_camera()
		return
	var player := scene.instantiate() as Node3D
	player.name = "Player"
	add_child(player)
	var spawn := Game.get_location("spawn_start")
	if player.has_method("teleport"):
		player.teleport(spawn.origin, spawn.basis.get_euler().y)
	else:
		player.global_transform = spawn
	if Game.player == null:
		Game.set_player(player)


func _fallback_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "FallbackCamera"
	add_child(cam)
	cam.global_position = Vector3(0, 60, 120)
	cam.look_at(Vector3.ZERO)
	cam.far = 3000.0
	cam.current = true
