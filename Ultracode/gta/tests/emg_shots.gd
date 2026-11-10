extends Node
## EMERGENCY services - windowed screenshots (short runs, one part each).
##   --emg_part=1  noon: a civilian lies dead on a downtown sidewalk, the ambulance arrives with
##                 its siren lights on, the medics kneel at the body
##                 -> qa/screenshots/emg_shots_ambulance_arriving.png, emg_shots_ambulance_scene.png
##   --emg_part=2  night: a car is blown up, the fire truck comes, firefighters spray the burning wreck
##                 -> qa/screenshots/emg_shots_firetruck_night.png, emg_shots_firetruck_night_b.png
## The spawn band is narrowed (45-80 m, still out of view) and the game runs at 2x so the response
## arrives within the short GPU budget of a windowed run.
##
## Run: tools\godot.ps1 -Mode window -Frames 720 -TimeoutSec 200 -UserArgs '--test=emg_shots','--emg_part=1','--test-timeout=150',
##      '--seed=7','--disable=police,wildlife,shops,garage,transit,taxi,activities,radio,respawn,debug'

var emg: Node = null
var cam: Camera3D = null
var part: int = 1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--emg_part="):
			part = int(a.get_slice("=", 1))
	await _run()


func _run() -> void:
	emg = Game.get_system("emergency")
	if not TestHarness.check(emg != null and Game.world != null and Game.player != null, "emergency + world + player"):
		TestHarness.finish(false, "missing systems")
		return
	if not TestHarness.check(Game.player.has_method("teleport"), "the player script is loaded (teleport)"):
		TestHarness.finish(false, "player script broken (neighbour mid-edit?)")
		return
	WorldClock.paused = true
	if Weather.has_method("set_weather"):
		Weather.set_weather("clear", 0.0)
	if UI.has_method("set_hud_visible"):
		UI.set_hud_visible(false)
	Game.invulnerable = true
	emg.set("spawn_range", Vector2(45.0, 80.0))
	emg.set("spawn_player_min", 30.0)
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.far = 1500.0
	Game.get_entities_root().add_child(cam)
	if part == 1:
		WorldClock.set_hour(11.0)
		await _part_medical()
	else:
		WorldClock.set_hour(22.4)
		await _part_fire()
	Game.release_time_scale("emg_shots")
	TestHarness.finish()


func _scene_spot(at: Vector3) -> Dictionary:
	var roads: Object = Game.world.get("roads")
	var spot: Dictionary = roads.call("get_nearest_lane", at, 40.0)
	var xf: Transform3D = roads.call("sample_lane", int(spot["lane_id"]), float(spot["offset"]))
	var dir := -xf.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	return {"xf": xf, "dir": dir, "right": Vector3(-dir.z, 0.0, dir.x), "lane": int(spot["lane_id"]), "offset": float(spot["offset"])}


func _medical_response() -> Dictionary:
	for r: Dictionary in (emg.call("get_active_responses") as Array):
		if r["kind"] == "medical":
			return r
	return {}


func _fire_response() -> Dictionary:
	for r: Dictionary in (emg.call("get_active_responses") as Array):
		if r["kind"] == "fire":
			return r
	return {}


# --- part 1: ambulance at a body, noon ----------------------------------------------------------

func _part_medical() -> void:
	var s := _scene_spot(Vector3(0.0, 2.6, -60.0))
	var lane_xf: Transform3D = s["xf"]
	var dir: Vector3 = s["dir"]
	var right: Vector3 = s["right"]
	var body_p := lane_xf.origin + right * 6.2
	Game.player.call("teleport", body_p - dir * 9.0 + right * 1.5 + Vector3.UP * 0.2, atan2(-dir.x, -dir.z))
	await TestHarness.wait_seconds(1.5)
	var victim: Node3D = Game.spawn_npc("civilian_m", body_p, {"yaw": 0.0, "activity": "idle"})
	await TestHarness.wait_seconds(0.3)
	if victim == null:
		TestHarness.check(false, "victim spawned")
		return
	victim.call("kill", "test")
	await TestHarness.wait_seconds(0.4)
	Game.request_time_scale("emg_shots", 2.0)
	TestHarness.check(bool(emg.call("dispatch", "medical", victim.call("get_body_position"))), "ambulance dispatched")
	var shot_arriving := false
	for i in 120:
		await TestHarness.wait_seconds(0.25)
		var r := _medical_response()
		if r.is_empty():
			continue
		var v: Node3D = r["vehicle"]
		if v == null or not is_instance_valid(v):
			break
		if not shot_arriving and str(r["state"]) == "driving" and _flat(v.global_position, body_p) < 30.0:
			# the ambulance coming down the street with its lights on
			var vf := -v.global_basis.z
			vf.y = 0.0
			vf = vf.normalized()
			var vr := Vector3(-vf.z, 0.0, vf.x)
			_look(v.global_position + vf * 13.0 + vr * 4.5 + Vector3.UP * 2.0, v.global_position + Vector3.UP * 1.3)
			await TestHarness.shot("emg_shots_ambulance_arriving")
			shot_arriving = true
		var treating := false
		for c: Node3D in r["crew"]:
			if is_instance_valid(c) and str(c.get("state_tag")) == "treating":
				treating = true
		if treating and float(r["time_on_scene"]) > 4.0:
			var b: Vector3 = victim.call("get_body_position") if is_instance_valid(victim) else body_p
			var mid := (b + v.global_position) * 0.5
			var side := (b - v.global_position)
			side.y = 0.0
			side = side.normalized()
			var cam_p := b + side * 4.0 + side.rotated(Vector3.UP, PI * 0.5) * 5.5 + Vector3.UP * 2.6
			_look(cam_p, mid.lerp(b, 0.45) + Vector3.UP * 0.6)
			await TestHarness.wait_seconds(0.4)
			await TestHarness.shot("emg_shots_ambulance_scene")
			TestHarness.check(true, "medics kneeling at the body")
			TestHarness.check(bool(r["siren"]), "ambulance lights on at the scene")
			return
	TestHarness.check(false, "medics reached the body in time")


# --- part 2: fire truck at a burning car, night ------------------------------------------------

func _part_fire() -> void:
	var s := _scene_spot(Vector3(0.0, 2.6, -60.0))
	var roads: Object = Game.world.get("roads")
	var car_xf: Transform3D = roads.call("sample_lane", int(s["lane"]), float(s["offset"]) + 10.0)
	var dir: Vector3 = s["dir"]
	var right: Vector3 = s["right"]
	Game.player.call("teleport", car_xf.origin + right * 7.0 - dir * 6.0 + Vector3.UP * 0.2, atan2(-dir.x, -dir.z))
	await TestHarness.wait_seconds(1.5)
	car_xf.origin.y += 0.4
	var car: Node3D = Game.spawn_vehicle("sedan", car_xf, {"owner_tag": "parked"})
	await TestHarness.wait_seconds(0.5)
	if car == null or not car.has_method("explode"):
		TestHarness.check(false, "test car spawned")
		return
	car.call("explode", null)
	await TestHarness.wait_seconds(0.5)
	Game.request_time_scale("emg_shots", 2.0)
	TestHarness.check(bool(emg.call("dispatch", "fire", car.global_position)), "fire truck dispatched")
	var shots := 0
	for i in 140:
		await TestHarness.wait_seconds(0.25)
		var r := _fire_response()
		if r.is_empty():
			continue
		var v: Node3D = r["vehicle"]
		if v == null or not is_instance_valid(v):
			break
		var spraying := 0
		for c: Node3D in r["crew"]:
			if is_instance_valid(c) and str(c.get("state_tag")) == "spraying":
				spraying += 1
		if spraying >= 1 and shots == 0:
			await TestHarness.wait_seconds(0.8)
			var w := car.global_position if is_instance_valid(car) else v.global_position
			var tv := v.global_position - w
			tv.y = 0.0
			tv = tv.normalized()
			var sd := tv.rotated(Vector3.UP, PI * 0.5)
			_look(w + sd * 9.0 + tv * 3.5 + Vector3.UP * 3.0, w.lerp(v.global_position, 0.35) + Vector3.UP * 0.8)
			await TestHarness.wait_seconds(0.2)
			await TestHarness.shot("emg_shots_firetruck_night")
			shots += 1
			_look(w - tv * 7.0 - sd * 4.0 + Vector3.UP * 2.2, w.lerp(v.global_position, 0.6) + Vector3.UP * 1.0)
			await TestHarness.wait_seconds(0.2)
			await TestHarness.shot("emg_shots_firetruck_night_b")
			shots += 1
			TestHarness.check(int((emg.get("fx") as Node).get("active_count")) >= 1, "water jets active")
			return
	TestHarness.check(false, "firefighters sprayed in time")


func _look(from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	cam.make_current()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
