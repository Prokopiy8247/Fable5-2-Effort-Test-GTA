extends Node
## WORLD integration test with the real player (headless, full boot):
##   tools\godot.ps1 -Mode headless -Frames 900 -UserArgs '--test=wld_spawn','--disable=traffic,peds,police'
## The player (when its scene exists) must be standing on the sidewalk at spawn_start after two seconds.


func _ready() -> void:
	var T := TestHarness
	var w: Variant = Game.world
	if not T.check(w != null and w.get("roads") != null, "world is built"):
		T.finish(false, "no world")
		return
	if not Game.has_player():
		T.log_line("no player scene in this build: nothing to check")
		T.check(true, "skipped (no player)")
		T.finish()
		return
	await T.wait_physics_frames(120)
	var spawn: Transform3D = w.get_location("spawn_start")
	var p: Vector3 = Game.player.global_position
	var ground := float(w.get_height(p.x, p.z))
	T.log_line("player at %s, spawn_start %s, ground %.2f, surface %s, district %s" % [str(p), str(spawn.origin), ground,
			String(w.get_surface_at(p)), String(w.get_district(p))])
	T.check(Vector2(p.x - spawn.origin.x, p.z - spawn.origin.z).length() < 3.0, "player stays at spawn_start")
	T.check(absf(p.y - ground) < 0.25, "player stands on the ground (y %.2f, ground %.2f)" % [p.y, ground])
	T.check(String(w.get_surface_at(p)) == "concrete", "player stands on the sidewalk")
	T.finish()
