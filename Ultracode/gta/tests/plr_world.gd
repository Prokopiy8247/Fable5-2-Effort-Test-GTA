extends Node
## plr_world - headless test of the player in the REAL world (skipped when no world system exists).
##
##   tools\godot.ps1 -Mode headless -Frames 4200 -TimeoutSec 300 `
##       -UserArgs '--test=plr_world','--disable=traffic,peds,police','--test-timeout=240'
##
## Covers: spawn point stands on real collision, walking on real ground, named locations hold the
## player (hospital = fallback respawn target), district events, footstep surface lookup, walking
## from the beach into the sea (wading -> swimming) and back out, camera not buried in terrain.

const LOCATIONS: PackedStringArray = ["hospital", "downtown_plaza", "safehouse", "police_station", "gun_shop",
		"hill_viewpoint", "marina_dock", "airport_runway_start", "residential_park", "industrial_yard", "beach"]

var P: Player = null
var T: Node = null
var W: Node3D = null
var districts: PackedStringArray = []
var soft: PackedStringArray = []
var water_in := 0
var water_out := 0


func _ready() -> void:
	T = TestHarness
	await _run()


func _run() -> void:
	P = Game.player as Player
	if not T.check(P != null, "Game.player is a Player"):
		T.finish(false, "no player")
		return
	W = Game.world
	if W == null or not W.has_method("get_height") or not W.has_method("get_location"):
		T.log_line("SKIP: no world system registered")
		T.finish(true, "SKIPPED: no world system")
		return
	EventBus.player_district_changed.connect(func(d: String) -> void: districts.append(d))
	EventBus.player_entered_water.connect(func() -> void: water_in += 1)
	EventBus.player_exited_water.connect(func() -> void: water_out += 1)
	await T.wait_seconds(1.0)
	await _test_spawn()
	await _test_locations()
	await _test_beach_to_sea()
	_release()
	for s in soft:
		T.log_line("SOFT: " + s)
	T.finish(true, "player in the real world" + ("" if soft.is_empty() else " | %d soft notes (see SOFT lines)" % soft.size()))


func _release() -> void:
	for a in ["move_forward", "move_back", "sprint", "jump", "crouch"]:
		Input.action_release(a)


func _ground(p: Vector3) -> float:
	return float(W.call("get_height", p.x, p.z))


func _test_spawn() -> void:
	var spawn: Transform3D = W.call("get_location", "spawn_start")
	var yaw := spawn.basis.get_euler().y
	P.teleport(spawn.origin + Vector3(0.0, 0.3, 0.0), yaw)
	await T.wait_seconds(1.2)
	var g := _ground(P.global_position)
	T.log_line("spawn_start: player y %.2f, terrain %.2f, state %s" % [P.global_position.y, g, P.state_id])
	T.check(P.grounded and P.state_id == "on_foot", "stands on real collision at spawn_start")
	T.check(P.global_position.y > g - 0.3 and P.global_position.y < g + 3.0, "spawn height is sane (%.2f above the terrain)" % (P.global_position.y - g))
	T.check(P.global_position.distance_to(spawn.origin) < 1.5, "stays at the spawn point")
	# walk around: forward 2.5 s, then back
	var p0 := P.global_position
	var best := 0.0
	for turn in 4:
		P.camera.yaw = yaw + float(turn) * PI * 0.5
		Input.action_press("move_forward")
		await T.wait_seconds(2.0)
		Input.action_release("move_forward")
		best = maxf(best, P.global_position.distance_to(p0))
		await T.wait_seconds(0.3)
		if best > 6.0:
			break
	T.check(best > 6.0, "can walk away from the spawn point (%.1f m)" % best)
	var g2 := _ground(P.global_position)
	T.check(P.global_position.y > g2 - 0.3 and not P.is_dead, "did not fall through the world (y %.2f, terrain %.2f)" % [P.global_position.y, g2])
	if W.has_method("get_surface_at"):
		var surf := str(W.call("get_surface_at", P.global_position))
		T.check(surf != "", "world surface under the player: '%s'" % surf)
	var cam := P.camera.camera
	var cg := _ground(cam.global_position)
	T.check(cam.global_position.y > cg - 0.05, "the camera is not below the terrain (%.2f above)" % (cam.global_position.y - cg))
	var aim := P.get_aim_point()
	T.check(aim.is_finite(), "get_aim_point works in the real world")


func _test_locations() -> void:
	for loc in LOCATIONS:
		var xf: Transform3D = W.call("get_location", loc)
		P.teleport(xf.origin + Vector3(0.0, 0.5, 0.0), xf.basis.get_euler().y)
		await T.wait_seconds(0.9)
		var g := _ground(P.global_position)
		var ok := (P.grounded or P.is_swimming) and P.global_position.y > g - 0.3 and P.global_position.y < g + 40.0
		var line := "%s: y %.2f terrain %.2f state %s grounded %s" % [loc, P.global_position.y, g, P.state_id, str(P.grounded)]
		if loc == "hospital":
			T.check(ok, "the hospital respawn point holds the player (" + line + ")")
		elif not ok:
			soft.append("location " + line)
		else:
			T.log_line("ok " + line)
	# the tour crosses several districts (the event at boot fired before this test listened)
	T.check(districts.size() >= 2, "EventBus.player_district_changed follows the player (%s)" % ", ".join(districts))


func _test_beach_to_sea() -> void:
	if not W.has_method("get_water_depth"):
		soft.append("world has no get_water_depth: beach test skipped")
		return
	var beach: Transform3D = W.call("get_location", "beach")
	# find the sea: nearest direction in which the water gets deep within 90 m
	var best_dir := Vector3.ZERO
	var best_dist := INF
	for i in 24:
		var ang := TAU * float(i) / 24.0
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		for d in [20.0, 35.0, 50.0, 70.0, 90.0]:
			var q: Vector3 = beach.origin + dir * d
			if float(W.call("get_water_depth", q.x, q.z)) > 2.5:
				if d < best_dist:
					best_dist = d
					best_dir = dir
				break
	if best_dir == Vector3.ZERO:
		soft.append("no deep water within 90 m of 'beach': wading test skipped")
		return
	P.teleport(beach.origin + Vector3(0.0, 0.5, 0.0), 0.0)
	await T.wait_seconds(0.8)
	var in0 := water_in
	P.camera.yaw = atan2(-best_dir.x, -best_dir.z)
	Input.action_press("move_forward")
	var slowed := false
	var t := 0.0
	var max_depth_on_foot := 0.0
	while t < 45.0 and P.state_id != "swim":
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if P.state_id == "on_foot" and P.water_depth > 0.6:
			max_depth_on_foot = maxf(max_depth_on_foot, P.water_depth)
			if Vector2(P.velocity.x, P.velocity.z).length() < Player.RUN_SPEED * 0.85:
				slowed = true
	T.check(P.state_id == "swim", "walking from the beach into the sea ends in swimming (after %.1f s, state %s)" % [t, P.state_id])
	T.check(water_in - in0 == 1, "player_entered_water emitted on the way in")
	T.log_line("wading: deepest on foot %.2f m, slowed down: %s" % [max_depth_on_foot, str(slowed)])
	if max_depth_on_foot > 0.7:
		T.check(slowed, "wading through shallow water slows the player down")
	await T.wait_seconds(2.0)
	T.check(P.is_swimming and not P.is_underwater, "floats at the surface of the real sea")
	var surf := P.water_surface_y - P.global_position.y
	T.check(absf(surf - Player.FLOAT_DEPTH) < 0.45, "rides the waves at the floating line (%.2f m under the surface)" % surf)
	# and back to the shore
	Input.action_release("move_forward")
	var out0 := water_out
	P.camera.yaw = atan2(best_dir.x, best_dir.z)
	Input.action_press("move_forward")
	t = 0.0
	while t < 45.0 and P.state_id != "on_foot":
		await get_tree().physics_frame
		t += 1.0 / 60.0
	Input.action_release("move_forward")
	T.check(P.state_id == "on_foot" and water_out - out0 == 1, "swims back and walks out of the water (after %.1f s, state %s)" % [t, P.state_id])
	await T.wait_seconds(0.5)
