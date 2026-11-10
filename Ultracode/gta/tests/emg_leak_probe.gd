extends Node
## Diagnostic (AI open item "exit-time leak when props + peds run together"): runs the real city
## downtown for ~25 s with pedestrians (bench sitting needs the props system), then prints the
## orphan nodes (nodes outside the scene tree are never freed automatically - the usual source of
## "ObjectDB instances leaked at exit") and the object counters. Compare a run with
## '--disable=props' / '--disable=peds'.
##
## Run: tools\godot.ps1 -Mode headless -Frames 2400 -TimeoutSec 240 -UserArgs '--test=emg_leak_probe','--test-timeout=200',
##      '--disable=police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'


func _ready() -> void:
	if Game.player != null:
		Game.player.call("teleport", Vector3(6.0, 3.0, -40.0), 0.0)
	Game.invulnerable = true
	await TestHarness.wait_seconds(25.0)
	var peds := Game.get_system("peds")
	if peds != null and peds.has_method("get_debug_info"):
		var d: Dictionary = peds.call("get_debug_info")
		TestHarness.log_line("peds: npcs %s pool %s benches %s taken %s" % [str(d.get("npcs")), str(d.get("pool")),
				str(d.get("benches")), str(d.get("benches_taken"))])
	TestHarness.log_line("objects %d nodes %d orphan nodes %d resources %d" % [
			int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))])
	print("ORPHANS_BEGIN")
	Node.print_orphan_nodes()
	print("ORPHANS_END")
	TestHarness.check(true, "probe ran")
	TestHarness.finish()
