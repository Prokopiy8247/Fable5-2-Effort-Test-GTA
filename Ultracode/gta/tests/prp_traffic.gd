extends Node
## PropSystem (WORLD DRESSING) with the real neighbours: AI traffic, pedestrians, police ... running for a
## minute around the player downtown. Street furniture must not be mowed down by normal AI driving
## (props stand off the carriageway), and nothing in the props system may error.
##   tools\godot.ps1 -Mode headless -Frames 4200 -TimeoutSec 400 -UserArgs '--test=prp_traffic'

var broken: Array = []


func _ready() -> void:
	await TestHarness.wait_frames(20)
	var ps := Game.get_system("props")
	TestHarness.check(ps != null, "props system registered")
	if ps == null:
		TestHarness.finish(false, "no props system")
		return
	Game.invulnerable = true
	EventBus.prop_broken.connect(func(p: Node3D, who: Node) -> void:
		var id := String(p.get("prop_id")) if p != null and is_instance_valid(p) else "?"
		var by := "null"
		if who != null and is_instance_valid(who):
			by = "%s (%s)" % [who.name, "player" if who.is_in_group("player") or who.get("is_player_driven") == true else "ai"]
		broken.append("%s by %s at %s" % [id, by, str(p.global_position.snapped(Vector3.ONE)) if p != null and is_instance_valid(p) else "?"]))
	var xf: Transform3D = Game.get_location("downtown_plaza")
	if Game.player != null:
		Game.player.call("teleport", xf.origin, 0.0)
	var traffic := Game.get_system("traffic")
	var t := 0.0
	var max_cars := 0
	var max_active := 0
	while t < 60.0:
		await TestHarness.wait_seconds(5.0)
		t += 5.0
		if traffic != null and traffic.has_method("get_vehicle_count"):
			max_cars = maxi(max_cars, int(traffic.call("get_vehicle_count")))
		var c: Dictionary = ps.call("get_counts")
		max_active = maxi(max_active, int(c["active"]))
	var c2: Dictionary = ps.call("get_counts")
	TestHarness.log_line("traffic vehicles (max) %d, knocked-over props (max) %d, loose live %d, broken now %d" % [max_cars,
			max_active, int(c2["loose_live"]), int(c2["broken"])])
	TestHarness.log_line("breakages in 60 s: %d %s" % [broken.size(), str(broken.slice(0, 12))])
	var by_ai := 0
	for b: String in broken:
		if b.contains("(ai)"):
			by_ai += 1
	TestHarness.check(by_ai <= 2, "AI traffic leaves the street furniture standing (%d breakages by AI in 60 s)" % by_ai)
	TestHarness.check(int(c2["active"]) <= 60 and int(c2["loose_live"]) <= 64, "body caps respected")
	TestHarness.finish()
