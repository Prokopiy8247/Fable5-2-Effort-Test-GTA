extends Node3D
## Bootstrap: creates every runtime system in code so no manual scene assembly is required.

const SYSTEMS := [
	["env", "res://gta/code/world/env.gd"],
	["audio", "res://gta/code/audio/audio.gd"],
	["fx", "res://gta/code/combat/fx.gd"],
	["world", "res://gta/code/world/world.gd"],
	["skills", "res://gta/code/core/skills.gd"],
	["wanted", "res://gta/code/police/wanted.gd"],
	["traffic", "res://gta/code/traffic/traffic.gd"],
	["pop", "res://gta/code/ai/population.gd"],
	["extras", "res://gta/code/world/extras.gd"],
	["save", "res://gta/code/save/save.gd"],
]


func _ready() -> void:
	G.main = self
	var t0 = Time.get_ticks_msec()
	for s in SYSTEMS:
		if not ResourceLoader.exists(s[1]):
			continue
		var n: Node = Node3D.new()
		n.name = s[0].capitalize()
		n.set_script(load(s[1]))
		add_child(n)
		G.set(s[0], n)
	G.world.build()
	if ResourceLoader.exists("res://gta/code/player/player.gd"):
		var p = CharacterBody3D.new()
		p.name = "Player"
		p.set_script(load("res://gta/code/player/player.gd"))
		add_child(p)
		G.player = p
		var rig = Node3D.new()
		rig.name = "CameraRig"
		rig.set_script(load("res://gta/code/player/camera_rig.gd"))
		add_child(rig)
		G.cam = rig
	if ResourceLoader.exists("res://gta/code/ui/hud.gd"):
		var h = CanvasLayer.new()
		h.name = "HUD"
		h.set_script(load("res://gta/code/ui/hud.gd"))
		add_child(h)
		G.hud = h
	if ResourceLoader.exists("res://gta/code/ui/menus.gd"):
		var m = CanvasLayer.new()
		m.name = "Menus"
		m.layer = 5
		m.set_script(load("res://gta/code/ui/menus.gd"))
		add_child(m)
		G.menus = m
	for s in SYSTEMS:
		var n = G.get(s[0])
		if n and n.has_method("start"):
			n.start()
	if G.player:
		G.player.spawn_initial()
	print("[main] world ready in %d ms, nodes=%d" % [Time.get_ticks_msec() - t0, get_tree().get_node_count()])
	set_meta("booted", true)
	var args = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--test="):
			G.autotest = true
			var at = Node.new()
			at.name = "Autotest"
			at.set_script(load("res://gta/code/debug/tests.gd"))
			at.set("scenario", a.substr(7))
			add_child(at)
