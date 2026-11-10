extends Node
## PropSystem (WORLD DRESSING) look test: windowed screenshots of the dressed world.
##   tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 200 -UserArgs '--test=prp_shots','--no_player','--disable=traffic,peds,police,wildlife,emergency,transit,taxi,activities,radio,ambience,garage'
## Optional: --prp_only=street,night,hill (substring match on the shot names).
## Writes qa/screenshots/prp_*.png.

var _cam: Camera3D
var _only: PackedStringArray = []
var ps: Node


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--prp_only="):
			_only = a.substr(11).split(",", false)
	ps = Game.get_system("props")
	_cam = Camera3D.new()
	_cam.name = "PrpShotCam"
	_cam.fov = 62.0
	_cam.far = 2500.0
	add_child(_cam)
	_cam.current = true
	if Weather.has_method("snap_weather"):
		Weather.call("snap_weather", "clear")
	Weather.auto_cycle = false
	WorldClock.set_hour(10.5)
	WorldClock.paused = true
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await TestHarness.wait_frames(10)
	TestHarness.check(ps != null, "props system present")
	var shots := [
		["prp_street_day", Vector3(4.2, 4.0, -138.0), Vector3(-1.0, 4.0, -100.0), 10.5],
		["prp_street_midtown", Vector3(-28.0, 3.6, -26.0), Vector3(8.0, 3.2, -18.0), 15.5],
		["prp_street_night", Vector3(4.2, 4.0, -138.0), Vector3(-1.0, 4.0, -100.0), 22.5],
		["prp_signal_night", Vector3(10.5, 3.0, -122.0), Vector3(2.0, 5.0, -108.0), 22.5],
		["prp_hill_wood", Vector3(150.0, 26.0, -62.0), Vector3(222.0, 14.0, -126.0), 9.5],
		["prp_hill_inside", Vector3(200.0, 0.0, -100.0), Vector3(222.0, 0.0, -126.0), 9.5],
		["prp_beach", Vector3(118.0, 5.5, 237.0), Vector3(165.0, 0.5, 262.0), 13.0],
		["prp_docks", Vector3(-262.0, 9.0, -30.0), Vector3(-276.0, 3.0, 40.0), 11.0],
		["prp_yard", Vector3(-136.0, 11.0, 150.0), Vector3(-170.0, 2.5, 124.0), 11.0],
		["prp_park", Vector3(189.0, 7.5, -16.0), Vector3(189.0, 2.5, 26.0), 16.0],
		["prp_plaza", Vector3(54.0, 7.0, -30.0), Vector3(32.0, 2.6, -55.0), 12.0],
		["prp_marina", Vector3(-140.0, 5.0, 228.0), Vector3(-175.0, 2.0, 246.0), 17.5],
		["prp_airport", Vector3(-150.0, 6.0, -245.0), Vector3(-60.0, 2.5, -262.0), 12.0],
	]
	for s: Array in shots:
		var nm: String = s[0]
		if not _want(nm):
			continue
		WorldClock.set_hour(float(s[3]))
		var from: Vector3 = s[1]
		var to: Vector3 = s[2]
		if nm == "prp_hill_inside":
			from.y = _ground(from.x, from.z) + 1.7
			to.y = _ground(to.x, to.z) + 4.0
		_look(from, to)
		await TestHarness.wait_seconds(1.1 if float(s[3]) > 20.0 else 0.6)
		await TestHarness.shot(nm)
		_stats(nm)
	if _want("prp_cost") and ps != null:
		# whole frame with and without the dressing at the busiest view (downtown street)
		WorldClock.set_hour(10.5)
		_look(Vector3(4.2, 4.0, -138.0), Vector3(-1.0, 4.0, -100.0))
		await TestHarness.wait_seconds(0.5)
		_stats("cost_with_props")
		(ps as Node3D).visible = false
		await TestHarness.wait_seconds(0.5)
		_stats("cost_without_props")
		(ps as Node3D).visible = true
	if _want("prp_ladder"):
		await _instance_shot("fire_escape_ladder", "prp_ladder", 9.0, 3.0, 4.0, 11.0, func(x: Transform3D) -> bool: return x.origin.y > 1.0)
	if _want("prp_ladder_top"):
		await _ladder_top_shot()
	if _want("prp_ped_walk"):
		await _ped_walk_shot()
	if _want("prp_signal_driver"):
		await _signal_driver_shot()
	if _want("prp_guardrail"):
		await _instance_shot("guardrail", "prp_guardrail", 14.0, 3.5, 1.0, 10.0, func(x: Transform3D) -> bool: return x.origin.y > 8.0)
	if _want("prp_ring_rail"):
		await _instance_shot("guardrail", "prp_ring_rail", 16.0, 3.0, 0.8, 15.0, func(x: Transform3D) -> bool: return x.origin.y < 4.0)
	if _want("prp_alley"):
		await _instance_shot("dumpster", "prp_alley", 7.0, 2.2, 0.6, 14.0, func(_x: Transform3D) -> bool: return true)
	if _want("prp_hydrant"):
		await _hydrant_shot()
	TestHarness.finish()


## Camera `dist` m in front of the first instance of `id` that passes `pred` (its -Z side), slightly to the side.
func _instance_shot(id: String, nm: String, dist: float, height: float, look_h: float, hour: float, pred: Callable) -> void:
	if ps == null:
		return
	var all: PackedInt32Array = ps.call("find_instances", id)
	for i in all:
		var xf: Transform3D = ps.call("get_instance_transform", i)
		if not pred.call(xf):
			continue
		WorldClock.set_hour(hour)
		var fwd := -xf.basis.z.normalized()
		var side := xf.basis.x.normalized()
		var from := xf.origin + fwd * dist + side * dist * 0.35
		from.y = maxf(_ground(from.x, from.z), xf.origin.y) + height
		_look(from, xf.origin + Vector3(0, look_h, 0))
		await TestHarness.wait_seconds(0.6)
		await TestHarness.shot(nm)
		return
	TestHarness.log_line("no instance of %s for %s" % [id, nm])


## The top end of the tallest building fire-escape ladder (cornice / parapet clearance).
func _ladder_top_shot() -> void:
	if ps == null:
		return
	var best: Node3D = null
	for l: Node3D in ps.call("get_ladders"):
		if bool(l.get_meta("water", false)):
			continue
		if best == null or float(l.get_meta("height", 0.0)) > float(best.get_meta("height", 0.0)):
			best = l
	if best == null:
		TestHarness.log_line("no building ladder for prp_ladder_top")
		return
	WorldClock.set_hour(15.0)
	var h := float(best.get_meta("height", 3.0))
	var back := best.global_basis.z
	back.y = 0.0
	back = back.normalized()
	var side := Vector3(back.z, 0.0, -back.x)
	var top := best.global_position + Vector3(0.0, h, 0.0)
	_look(top + back * 6.0 + side * 3.0 + Vector3(0.0, 0.5, 0.0), top - Vector3(0.0, 0.8, 0.0))
	await TestHarness.wait_seconds(0.6)
	await TestHarness.shot("prp_ladder_top")


## A pedestrian signal showing WALK at night (close-up from the kerb opposite).
func _ped_walk_shot() -> void:
	if ps == null or not ps.has_method("get_ped_signals_info"):
		return
	WorldClock.set_hour(22.0)
	var t := 0.0
	while t < 20.0:
		for h: Dictionary in ps.call("get_ped_signals_info"):
			if not bool(h["walk"]) or String(ps.call("get_instance_state", int(h["instance"]))) != "idle":
				continue
			var p: Vector3 = h["position"]
			if p.distance_to(Vector3(0.0, 2.6, -110.0)) > 260.0:
				continue
			var f: Vector3 = h["facing"]
			f.y = 0.0
			f = f.normalized()
			_look(p + f * 3.2 + Vector3(f.z, 0.0, -f.x) * 0.8 + Vector3(0, 1.7, 0), p + Vector3(0, 2.3, 0))
			await TestHarness.wait_seconds(0.8)
			var still := false
			for h2: Dictionary in ps.call("get_ped_signals_info"):
				if int(h2["instance"]) == int(h["instance"]):
					still = bool(h2["walk"])
			if still:
				await TestHarness.shot("prp_ped_walk")
				TestHarness.check(true, "pedestrian signal shows WALK at night")
				return
		await TestHarness.wait_seconds(1.0)
		t += 1.0
	TestHarness.check(false, "a pedestrian signal showing WALK was found")


## Driver's view of a signal head at night: camera in the approach lane 16 m before the stop line.
func _signal_driver_shot() -> void:
	if ps == null:
		return
	WorldClock.set_hour(21.5)
	var heads: Array = ps.call("get_signal_heads_info")
	for k in heads.size():
		var p: Vector3 = heads[k]["position"]
		if p.distance_to(Vector3(0.0, 2.6, -110.0)) > 200.0:
			continue
		var i: PackedInt32Array = ps.call("find_instances", "traffic_light", p, 0.5)
		if i.is_empty():
			continue
		var xf: Transform3D = ps.call("get_instance_transform", i[0])
		var toward := -xf.basis.z.normalized()      # toward the approaching drivers
		var over := xf.basis.x.normalized()          # the arm reaches over the road
		_look(p + toward * 16.0 + over * 2.6 + Vector3(0, 1.4, 0), p + over * 3.6 + Vector3(0, 5.6, 0))
		await TestHarness.wait_seconds(0.8)
		await TestHarness.shot("prp_signal_driver")
		TestHarness.log_line("signal head %d lit state %d (road graph %d)" % [k, int(ps.call("get_head_lit_state", k)),
				int(Game.world.get("roads").call("get_signal_state", int(heads[k]["lane_id"])))])
		return


## Whole-frame numbers (city + dressing + environment + HUD) for docs/DRESSING.md.
func _stats(nm: String) -> void:
	var vp := get_viewport().get_viewport_rid()
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var obj := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var prim := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	TestHarness.log_line("FRAME %s draw_calls=%d objects=%d primitives=%d gpu_ms=%.2f" % [nm, dc, obj, prim, gpu])


func _want(n: String) -> bool:
	if _only.is_empty():
		return true
	for o in _only:
		if n.contains(o):
			return true
	return false


func _ground(x: float, z: float) -> float:
	return Game.ground_height(x, z)


func _look(from: Vector3, to: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(to, Vector3.UP)


func _hydrant_shot() -> void:
	WorldClock.set_hour(12.0)
	if ps == null:
		return
	var hyd: PackedInt32Array = ps.call("find_instances", "hydrant", Vector3(0.0, 2.6, -60.0), 500.0)
	if hyd.is_empty():
		TestHarness.check(false, "a hydrant exists")
		return
	var i := hyd[0]
	var xf: Transform3D = ps.call("get_instance_transform", i)
	var road := -xf.basis.z
	var side := xf.basis.x
	_look(xf.origin + side * 6.5 + Vector3(0, 2.2, 0) - road * 1.5, xf.origin + Vector3(0, 0.9, 0))
	await TestHarness.wait_seconds(0.4)
	await TestHarness.shot("prp_hydrant_before")
	ps.call("break_instance", i, (road + Vector3.UP * 1.4).normalized() * 450.0)
	await TestHarness.wait_seconds(0.55)
	await TestHarness.shot("prp_hydrant_broken")
	TestHarness.check(String(ps.call("get_instance_state", i)) == "active", "hydrant knocked off")
