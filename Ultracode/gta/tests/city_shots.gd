extends Node
## City builder screenshots (windowed, short):
##   tools\godot.ps1 -Mode window -Frames 900 -TimeoutSec 200 -UserArgs '--test=city_shots','--no_player','--hour=13','--freeze-time','--weather=clear','--disable=traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups'
## Writes qa/screenshots/city_*.png. Optional: --city_only=name1,name2 (substring match).

var _cam: Camera3D
var _city: Node
var _only: PackedStringArray = []


func _ready() -> void:
	_city = Game.get_system("city")
	if _city == null:
		TestHarness.finish(false, "no city system")
		return
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--city_only="):
			_only = a.substr(12).split(",", false)
	_cam = Camera3D.new()
	_cam.far = 4000.0
	_cam.near = 0.1
	_cam.fov = 60.0
	add_child(_cam)
	_cam.make_current()
	var ui := get_node_or_null("/root/UI")
	if ui != null and ui.has_method("set_hud_visible"):
		ui.call("set_hud_visible", false)
	_set_hour(13.0)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await TestHarness.wait_frames(40)

	await _shot("city_skyline_bay", Vector3(40.0, 20.0, 330.0), Vector3(-10.0, 30.0, -90.0), 50.0)
	await _shot("city_downtown_canyon", Vector3(-116.0, 3.6, -107.5), Vector3(-10.0, 15.0, -104.0), 62.0)
	await _shot("city_downtown_aerial", Vector3(80.0, 70.0, 10.0), Vector3(-30.0, 10.0, -110.0), 55.0)
	await _shot("city_midtown_street", Vector3(-118.0, 4.0, 72.5), Vector3(-10.0, 6.0, 69.0), 60.0)
	await _shot("city_residential", Vector3(166.0, 4.5, 68.0), Vector3(150.0, 3.5, 8.0), 60.0)
	await _shot("city_residential_south", Vector3(130.0, 5.0, 117.0), Vector3(190.0, 3.5, 130.0), 60.0)
	await _shot("city_industrial", Vector3(-122.0, 24.0, -52.0), Vector3(-185.0, 4.0, -115.0), 60.0)
	# camera 8 m further down the street than before: the dressing's corner signal poles stood in the frame
	await _shot("city_docks_row", Vector3(-210.4, 6.0, -92.4), Vector3(-240.0, 6.0, 10.0), 60.0)
	await _shot("city_police_station", Vector3(-48.0, 5.0, 68.0), Vector3(-60.0, 6.0, 90.0), 62.0)
	await _shot("city_gun_shop", Vector3(-41.0, 3.4, 70.0), Vector3(-48.0, 3.5, 55.0), 62.0)
	await _shot("city_mod_garage", Vector3(-117.0, 4.0, 10.0), Vector3(-138.0, 3.5, 0.5), 62.0)
	await _shot("city_safehouse", Vector3(92.0, 4.2, 227.0), Vector3(101.5, 4.5, 209.0), 62.0)
	await _shot("city_gas_station", Vector3(-82.0, 6.5, 159.0), Vector3(-96.5, 4.0, 137.0), 62.0)
	await _shot("city_hospital", Vector3(-80.0, 9.0, -23.0), Vector3(-94.5, 10.0, 3.5), 62.0)
	await _shot_local("city_interior_gun_shop", "gun_shop", Vector3(0.6, 1.65, -5.3), Vector3(-1.5, 1.2, 4.5), 74.0)
	await _shot_local("city_interior_safehouse", "safehouse", Vector3(-6.0, 1.7, -5.0), Vector3(3.0, 1.2, 4.0), 72.0)
	await _shot("city_marina_pier", Vector3(-22.0, 7.0, 282.0), Vector3(-45.0, 1.5, 268.0), 60.0)
	await _shot("city_airport", Vector3(10.0, 22.0, -262.0), Vector3(-55.0, 6.0, -220.0), 60.0)
	await _shot("city_hill_mast", Vector3(200.0, 48.0, -100.0), Vector3(229.0, 52.0, -131.5), 60.0)
	await _shot("city_lighthouse", Vector3(-12.0, 9.0, 250.0), Vector3(8.0, 13.0, 274.0), 60.0)
	_set_hour(22.5)
	await TestHarness.wait_frames(20)
	await _shot("city_night_downtown", Vector3(60.0, 32.0, 12.0), Vector3(-30.0, 16.0, -100.0), 55.0)
	await _shot("city_night_street", Vector3(-118.0, 4.0, 72.5), Vector3(-10.0, 6.0, 69.0), 60.0)
	await _shot("city_night_skyline", Vector3(40.0, 20.0, 330.0), Vector3(-10.0, 30.0, -90.0), 50.0)
	TestHarness.finish()


func _wanted(n: String) -> bool:
	if _only.is_empty():
		return true
	for o in _only:
		if n.contains(o):
			return true
	return false


func _set_hour(h: float) -> void:
	var wc := get_node_or_null("/root/WorldClock")
	if wc != null and wc.has_method("set_hour"):
		wc.call("set_hour", h)
	var env := Game.get_system("environment")
	if env != null and env.has_method("refresh"):
		env.call("refresh")


func _shot(n: String, from: Vector3, to: Vector3, fov: float, frames: int = 6) -> void:
	if not _wanted(n):
		return
	_cam.fov = fov
	_cam.global_position = from
	_cam.look_at(to, Vector3.UP)
	await TestHarness.wait_frames(frames)
	await TestHarness.shot(n)
	_perf(n)


func _shot_local(n: String, landmark: String, from: Vector3, to: Vector3, fov: float) -> void:
	if not _wanted(n) or not bool(_city.call("has_landmark", landmark)):
		return
	var xf: Transform3D = _city.call("get_landmark_transform", landmark)
	await _shot(n, xf * from, xf * to, fov, 30)          # the pooled room light needs ~0.7 s to fade in


## Render cost of the current view (logged next to every shot).
func _perf(n: String) -> void:
	var vp := get_viewport().get_viewport_rid()
	TestHarness.log_line("PERF %s: draw calls %d, objects %d, primitives %d, gpu %.2f ms, cpu %.2f ms" % [n,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			RenderingServer.viewport_get_measured_render_time_gpu(vp),
			RenderingServer.viewport_get_measured_render_time_cpu(vp)])
