extends Node
## plr_leak - headless regression test: ragdolls and knock-downs must not leak objects or orphan
## nodes, and the global ragdoll cap must hold.
##
##   tools\godot.ps1 -Mode headless -Frames 2400 -TimeoutSec 240 `
##       -UserArgs '--test=plr_leak','--disable=traffic,peds,police','--test-timeout=200'

const Arena := preload("res://gta/tests/plr_arena.gd")

var P: Player = null
var T: Node = null
var arena: Arena = null


func _ready() -> void:
	T = TestHarness
	await _run()


func _counts() -> Vector3:
	return Vector3(Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _run() -> void:
	P = Game.player as Player
	if not T.check(P != null and P.visual != null, "player with a visual exists"):
		T.finish(false, "no player")
		return
	arena = Arena.new()
	Game.main.add_child(arena)
	P.teleport(arena.at(Vector3(0.0, 0.05, 0.0)), 0.0)
	await T.wait_seconds(1.0)

	# warm-up (caches, pools), then measure
	for i in 2:
		var w := Ragdoll.spawn_from(P.visual, Vector3(60.0, 40.0, 0.0)) as Ragdoll
		await T.wait_physics_frames(10)
		if w != null:
			w.dismiss()
	await T.wait_physics_frames(20)
	var before := _counts()

	# cap: more than MAX_ACTIVE non-persistent ragdolls never exist at once
	var made := 0
	var peak := 0
	for i in Ragdoll.MAX_ACTIVE + 6:
		var r := Ragdoll.spawn_from(P.visual, Vector3(randf_range(-80.0, 80.0), 60.0, randf_range(-80.0, 80.0)))
		if r != null:
			made += 1
		await T.wait_physics_frames(3)
		peak = maxi(peak, Ragdoll.get_active_count())
	T.check(made == Ragdoll.MAX_ACTIVE + 6, "spawn_from built every ragdoll (%d)" % made)
	T.check(peak <= Ragdoll.MAX_ACTIVE, "never more than MAX_ACTIVE ragdolls (%d of %d)" % [peak, Ragdoll.MAX_ACTIVE])
	await T.wait_seconds(1.5)
	Ragdoll.clear_all()
	await T.wait_physics_frames(30)
	T.check(Ragdoll.get_active_count() == 0, "clear_all removes every ragdoll")
	var after := _counts()
	T.log_line("objects %d -> %d, nodes %d -> %d, orphans %d -> %d" % [int(before.x), int(after.x), int(before.y), int(after.y), int(before.z), int(after.z)])
	T.check(after.z <= before.z, "no orphan nodes left behind by ragdolls (%d -> %d)" % [int(before.z), int(after.z)])
	T.check(after.y <= before.y + 2.0, "node count returns to the baseline (%d -> %d)" % [int(before.y), int(after.y)])
	T.check(after.x <= before.x + 40.0, "object count returns to the baseline (%d -> %d)" % [int(before.x), int(after.x)])

	# auto clean-up by lifetime
	var short := Ragdoll.spawn_from(P.visual, Vector3.ZERO) as Ragdoll
	short.lifetime = 0.6
	await T.wait_seconds(1.2)
	T.check(not is_instance_valid(short) or short.is_queued_for_deletion(), "a ragdoll removes itself after its lifetime")

	# knock-down cycles of the player itself
	var before2 := _counts()
	for i in 4:
		P.heal(1000.0)
		P.ragdoll(Vector3(180.0, 90.0, 0.0), 0.5)
		var t := 0.0
		while P.state_id != "on_foot" and t < 8.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		P.teleport(arena.at(Vector3(0.0, 0.05, 0.0)), 0.0)
		await T.wait_physics_frames(10)
	P.kill("test")
	await T.wait_seconds(0.6)
	P.respawn(Transform3D(Basis.IDENTITY, arena.at(Vector3(0.0, 0.05, 0.0))))
	await T.wait_physics_frames(40)
	var after2 := _counts()
	T.log_line("player cycles: objects %d -> %d, nodes %d -> %d, orphans %d -> %d" % [int(before2.x), int(after2.x), int(before2.y), int(after2.y), int(before2.z), int(after2.z)])
	T.check(P.state_id == "on_foot" and not P.is_dead and P.visual.visible, "player is fine after 4 knock-downs and a death")
	T.check(after2.z <= before2.z, "no orphan nodes after knock-downs / death (%d -> %d)" % [int(before2.z), int(after2.z)])
	# (the UI may keep a few banner / toast nodes around after a death, hence the tolerance)
	T.check(after2.y <= before2.y + 16.0, "node count stable after knock-downs / death (%d -> %d)" % [int(before2.y), int(after2.y)])
	T.finish(true, "ragdoll leak / cap check")
