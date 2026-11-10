extends Node3D
## Boot scene: builds the world, spawns the player and wires the sandbox systems together.
## The game launches straight into free roam - there is no menu gate, campaign or mission.

var world: World

func _ready() -> void:
	Game.main = self
	var t0 := Time.get_ticks_msec()
	world = World.new()
	add_child(world)
	Game.world = world
	world.build()
	_boot_systems()
	Game.boot_ms = Time.get_ticks_msec() - t0
	print("[Main] boot %d ms" % Game.boot_ms)
	Events.world_ready.emit.call_deferred()

func _boot_systems() -> void:
	var boot_script := "res://gta/code/core/boot_systems.gd"
	if ResourceLoader.exists(boot_script):
		var bs: GDScript = load(boot_script)
		bs.call("boot", self)
	else:
		# world-only preview (early development): a free camera
		var cam := Camera3D.new()
		cam.name = "PreviewCamera"
		cam.position = Vector3(40, 60, 120)
		cam.rotation_degrees = Vector3(-25, 0, 0)
		cam.far = 3000.0
		add_child(cam)
		cam.make_current()
