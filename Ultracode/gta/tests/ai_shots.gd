extends Node
## Windowed screenshots of the AI module in the REAL world (short runs, see ARCHITECTURE 9).
##   part 1: pedestrians on a downtown sidewalk + a panic scene (gunshot, a gun pointed at people)
##   part 2: a gang firefight from cover (gang members behind a car vs. two armed officers driven
##           by a TEST brain that uses the shared AiBrainCombat helper)
## Run:
##   tools\godot.ps1 -Mode window -Frames 540 -TimeoutSec 200 -UserArgs '--test=ai_shots','--ai_part=1','--test-timeout=120','--seed=5','--disable=props,traffic,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,respawn,debug'
##   tools\godot.ps1 -Mode window -Frames 540 -TimeoutSec 200 -UserArgs '--test=ai_shots','--ai_part=2','--test-timeout=120','--seed=5','--disable=props,traffic,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,respawn,debug'
## Output: qa/screenshots/ai_shots_*.png


## Test-only brain for the officers of part 2: fight the nearest gang member with AiBrainCombat.
class OfficerTestBrain extends Node:
	var combat := AiBrainCombat.new()
	var status: String = ""

	func think(npc: Node, delta: float) -> void:
		var best: Node3D = null
		var best_d := INF
		for g in npc.get_tree().get_nodes_in_group("gang"):
			if g is Node3D and not bool(g.get("is_dead")):
				var d := (g as Node3D).global_position.distance_to((npc as Node3D).global_position)
				if d < best_d:
					best_d = d
					best = g
		status = combat.tick(npc as Node3D, best, delta, {"lethal": true, "aggression": 0.55, "use_cover": true})


var peds: Node = null
var cam: Camera3D = null
var part: int = 1


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--ai_part="):
			part = int(a.substr(10))
	peds = Game.get_system("peds")
	if not TestHarness.check(peds != null and Game.world != null, "peds + world"):
		TestHarness.finish(false, "missing systems")
		return
	WorldClock.paused = true
	WorldClock.set_hour(10.5)
	Weather.set_weather("clear", 0.0)
	if UI.has_method("set_hud_visible"):
		UI.set_hud_visible(false)
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.far = 1500.0
	Game.get_entities_root().add_child(cam)
	if part == 1:
		await _part_sidewalk()
	else:
		await _part_gang()
	TestHarness.finish()


func _shot(n: String) -> void:
	cam.make_current()
	await TestHarness.shot(n)


func _look(from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	cam.make_current()


# --- part 1 -------------------------------------------------------------------------------------

func _part_sidewalk() -> void:
	var walk: Object = Game.world.get("walk")
	var roads: Object = Game.world.get("roads")
	var base: Vector3 = walk.call("get_nearest_point", Vector3(44.0, 2.65, -98.5))
	var n0 := int(walk.call("get_nearest_node", base))
	var pts: PackedVector3Array = walk.get("points")
	var links: Array = walk.get("links")
	var dir := Vector3.RIGHT
	if n0 >= 0 and not (links[n0] as PackedInt32Array).is_empty():
		var other: Vector3 = pts[(links[n0] as PackedInt32Array)[0]]
		dir = other - pts[n0]
		dir.y = 0.0
		dir = dir.normalized()
	var to_road := Vector3(0.0, 0.0, -1.0)
	if roads != null and roads.has_method("get_nearest_lane"):
		var nl: Dictionary = roads.call("get_nearest_lane", base, 20.0)
		if not nl.is_empty():
			to_road = (nl["point"] as Vector3) - base
			to_road.y = 0.0
			to_road = to_road.normalized()
	TestHarness.log_line("sidewalk base %s dir %s road %s" % [str(base), str(dir), str(to_road)])
	peds.call("set_focus_override", base)
	if Game.has_player():
		Game.player.call("teleport", base - dir * 30.0 + Vector3(0, 0.3, 0), 0.0)
	# people walking both ways, a talking pair, someone idling
	var people: Array = []
	var kinds := ["civilian_m", "civilian_f", "civilian_f", "civilian_m", "civilian_tough", "civilian_f", "civilian_m",
			"civilian_f", "civilian_m"]
	for k in kinds.size():
		var along := -3.0 + k * 2.6
		var lat := (randf() - 0.5) * 1.2
		var p: Vector3 = walk.call("get_nearest_point", base + dir * along + to_road * lat)
		var vis := ""
		if k % 4 == 1:
			vis = "business"
		var npc: Node3D = peds.call("spawn_npc", kinds[k], p, {"yaw": atan2(-dir.x, -dir.z) if k % 2 == 0 else atan2(dir.x, dir.z),
				"visual": vis, "activity": "idle"})
		if npc == null:
			continue
		people.append(npc)
	# talking pair near the camera
	var tp: Vector3 = walk.call("get_nearest_point", base + dir * 5.0)
	var a: Node3D = peds.call("spawn_npc", "civilian_f", tp - to_road * 0.5, {"yaw": atan2(-dir.x, -dir.z)})
	var b: Node3D = peds.call("spawn_npc", "civilian_m", tp - to_road * 0.5 + dir * 1.2, {"yaw": atan2(dir.x, dir.z), "activity": "talk", "partner": a})
	if a != null and b != null:
		(a.get("brain") as Node).call("on_event", a, "talk_with", {"partner": b, "duration": 60.0})
	await TestHarness.wait_seconds(0.3)
	for i in people.size():
		var npc: Node3D = people[i]
		var dest := npc.global_position + dir * (30.0 if i % 2 == 0 else -30.0)
		npc.call("walk_to", dest, "walk")
	await TestHarness.wait_seconds(3.5)
	_look(base - dir * 7.0 + to_road * 3.2 + Vector3(0, 1.7, 0), base + dir * 6.0 + Vector3(0, 1.0, 0))
	await _shot("ai_shots_sidewalk")
	_look(base + dir * 14.0 + to_road * 2.6 + Vector3(0, 1.6, 0), base + dir * 2.0 + Vector3(0, 1.1, 0))
	await _shot("ai_shots_sidewalk_b")
	# close-up of the talking pair
	if a != null:
		var mid := a.global_position + dir * 0.6
		_look(mid + to_road * 4.6 + dir * 1.2 + Vector3(0, 1.6, 0), mid + Vector3(0, 1.0, 0))
		await _shot("ai_shots_talk")
	# somebody on a bench (TEST EQUIPMENT: the real bench prop placed by the test, because the
	# props system that places benches is not running in this test)
	await _bench_scene(base, dir, to_road)
	# panic: a gun is pointed at two of them, then a shot rings out
	var shooter := Node3D.new()
	Game.get_entities_root().add_child(shooter)
	shooter.global_position = base + to_road * 6.0 + dir * 4.0
	for i in mini(2, people.size()):
		var npc: Node3D = people[i]
		for k in 3:
			npc.call("notify_threatened", Game.player, 0.16)
	await TestHarness.wait_seconds(0.5)
	EventBus.noise_emitted.emit(shooter.global_position + Vector3(0, 1.4, 0), 70.0, "gunshot", shooter)
	await TestHarness.wait_seconds(0.9)
	_look(base - dir * 8.0 + to_road * 4.0 + Vector3(0, 2.2, 0), base + dir * 5.0 + Vector3(0, 0.9, 0))
	await _shot("ai_shots_panic")
	await TestHarness.wait_seconds(1.2)
	await _shot("ai_shots_panic_b")
	var tags := {}
	for npc: Node3D in people:
		if is_instance_valid(npc):
			tags[str(npc.get("state_tag"))] = int(tags.get(str(npc.get("state_tag")), 0)) + 1
	TestHarness.log_line("panic states: %s" % str(tags))
	TestHarness.check(tags.has("flee") or tags.has("cower"), "panic scene: people flee / cower")


func _bench_scene(base: Vector3, dir: Vector3, to_road: Vector3) -> void:
	var glb := "res://gta/generated/models/props/bench.glb"
	if not ResourceLoader.exists(glb):
		TestHarness.log_line("bench.glb missing: bench shot skipped")
		return
	var spot := base - dir * 4.0 - to_road * 1.1
	var face := to_road                          # the sitter looks at the street
	var bench := StaticBody3D.new()
	bench.name = "Bench"
	bench.collision_layer = Layers.PROP
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.7, 0.44, 0.6)
	cs.shape = sh
	cs.position = Vector3(0.0, 0.22, 0.05)
	bench.add_child(cs)
	bench.add_child((load(glb) as PackedScene).instantiate())
	Game.get_entities_root().add_child(bench)
	bench.global_transform = Transform3D(Basis.looking_at(face, Vector3.UP), spot)
	await TestHarness.wait_physics_frames(3)
	peds.call("add_bench_point", bench.global_transform)
	var res: Dictionary = peds.call("claim_bench", self, spot, 3.0)
	TestHarness.check(not res.is_empty(), "bench found by claim_bench")
	if res.is_empty():
		return
	var sitter: Node3D = peds.call("spawn_npc", "civilian_f", (res["transform"] as Transform3D).origin,
			{"activity": "sit", "bench": res["transform"], "bench_key": int(res["key"])})
	await TestHarness.wait_seconds(1.0)
	TestHarness.check(sitter != null and str(sitter.call("get_pose")) == "sit", "civilian sits on the bench")
	if sitter != null:
		var an: Node = sitter.get("animator")
		TestHarness.log_line("sitter at %s (bench %s) seat %s anim %s visual y %.2f visible %s tier %d" % [
				str(sitter.global_position), str(spot), str((res["transform"] as Transform3D).origin),
				str(an.get("state")) if an != null else "-", (sitter.get("visual") as Node3D).position.y,
				str((sitter.get("visual") as Node3D).visible), int(sitter.get("sim_tier"))])
	_look(spot + face * 3.4 + dir * 1.6 + Vector3(0, 1.3, 0), spot + Vector3(0, 0.7, 0))
	await _shot("ai_shots_bench")


# --- part 2 -------------------------------------------------------------------------------------

func _part_gang() -> void:
	var yard: Vector3 = Game.get_location("industrial_yard").origin
	peds.call("set_focus_override", yard)
	peds.call("set_enabled", false)
	if Game.has_player():
		Game.player.call("teleport", yard + Vector3(40, 0.3, -30), 0.0)
	var car_pos := yard + Vector3(0.0, 0.3, 0.0)
	var car := Game.spawn_vehicle("sedan", Transform3D(Basis(Vector3.UP, PI * 0.5), car_pos), {"color": Color(0.2, 0.35, 0.6)})
	await TestHarness.wait_seconds(0.8)
	var gang: Array = []
	for k in 3:
		var g: Node3D = peds.call("spawn_npc", "gang_member", yard + Vector3(-1.5 + k * 1.5, 0.0, 4.5),
				{"yaw": 0.0, "weapon": "smg" if k == 1 else "pistol"})
		if g != null:
			g.set("health", 400.0)
			g.set("max_health", 400.0)
			gang.append(g)
	var cops: Array = []
	for k in 2:
		var c: Node3D = peds.call("spawn_npc", "police_officer", yard + Vector3(-3.0 + k * 6.0, 0.0, -17.0),
				{"yaw": PI, "brain": OfficerTestBrain.new(), "weapon": "pistol"})
		if c != null:
			c.set("health", 400.0)
			c.set("max_health", 400.0)
			c.set("accuracy", 0.35)
			cops.append(c)
	await TestHarness.wait_seconds(0.4)
	for g: Node3D in gang:
		if cops.size() > 0:
			(g.get("brain") as Node).call("provoke", g, cops[0], false)
	await TestHarness.wait_seconds(4.0)
	_look(yard + Vector3(9.0, 2.0, 9.0), yard + Vector3(0.0, 0.8, 0.5))
	await _shot("ai_shots_gang_cover")
	await TestHarness.wait_seconds(1.2)
	_look(yard + Vector3(-6.5, 1.5, 11.0), yard + Vector3(0.0, 1.0, -12.0))
	await _shot("ai_shots_gang_firefight")
	var st := {}
	for g: Node3D in gang:
		if is_instance_valid(g):
			st[str((g.get("brain") as Node).get("last_status"))] = true
	TestHarness.log_line("gang statuses at the end: %s" % str(st.keys()))
	TestHarness.check(st.has("cover") or st.has("peek") or st.has("move_to_cover") or st.has("reload"), "gang uses cover in the firefight")
	if car != null:
		car.queue_free()
