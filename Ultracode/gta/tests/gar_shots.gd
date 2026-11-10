extends Node
## Garage screenshots (windowed, short). Economy B.
##   tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 90 -UserArgs '--test=gar_shots','--test-timeout=80','--disable=props,traffic,peds,police,emergency,wildlife,transit,taxi,activities,radio,ambience,respawn'
## -> qa/screenshots/gar_mod_repair.png, gar_mod_paint.png, gar_mod_wheels.png, gar_mod_perf.png, gar_mod_body.png,
##    gar_list.png, gar_catalogue.png, gar_safehouse.png, gar_safehouse_menu.png, gar_terminal.png
## Optional: --gar_only=mod,list,home,terminal

const Stats := preload("res://gta/code/world/shops/garage_stats.gd")

var g = null
var only: PackedStringArray = []


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--gar_only="):
			only = a.substr(11).split(",", false)
	_run()


func _want(k: String) -> bool:
	return only.is_empty() or only.has(k)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _run() -> void:
	await TestHarness.wait_frames(10)
	g = Game.get_system("garage")
	if g == null:
		TestHarness.finish(false, "no garage system")
		return
	WorldClock.set_hour(11.0)
	if Weather.has_method("set_weather"):
		Weather.set_weather("clear", 0.0)
	Game.set_money(250000)
	if _want("mod"):
		await _shots_mod()
	if _want("list"):
		await _shots_lists()
	if _want("home"):
		await _shots_home()
	if _want("terminal"):
		await _shot_terminal()
	TestHarness.finish()


func _shots_mod() -> void:
	var ms = g.get_helper("mod_shop")
	var bay: Transform3D = ms.bay_xform
	var v := Game.spawn_vehicle("sports", Transform3D(bay.basis, bay.origin + Vector3(0, 0.1, 0)), {"color": Color("#F0802F")})
	if v == null:
		TestHarness.check(false, "sports car spawned")
		return
	await TestHarness.wait_frames(5)
	Game.player.call("enter_vehicle", v, 0, true)
	await TestHarness.wait_frames(5)
	# a little wear so the Repair tab has something to show
	v.call("apply_damage", Dmg.make(700.0, "bullet", null, v.global_position + Vector3(0, 1.0, 0)))
	v.call("pop_tire", 1)
	var ok: bool = await ms.begin(v)
	TestHarness.check(ok, "Torque Garage session opened")
	var scr = UI.get_screen("mod_garage")
	if scr == null:
		return
	await _wait(1.2)
	await TestHarness.shot("gar_mod_repair")
	scr.select_tab("Paint")
	scr.select_option("Lagoon Teal")
	await _wait(1.6)
	await TestHarness.shot("gar_mod_paint")
	scr.select_tab("Wheels")
	scr.select_option("wheels_deep")
	await _wait(1.4)
	await TestHarness.shot("gar_mod_wheels")
	scr.select_tab("Body")
	scr.select_option("spoiler_b")
	await _wait(1.4)
	await TestHarness.shot("gar_mod_body")
	scr.select_tab("Performance")
	scr.select_option("engine_4")
	await _wait(1.2)
	await TestHarness.shot("gar_mod_perf")
	UI.close_screen("mod_garage")
	await _wait(1.0)
	var pv := Game.get_player_vehicle()
	if pv != null:
		Game.player.call("teleport", pv.global_position + pv.global_transform.basis.x * 4.0, 0.0)
		await TestHarness.wait_frames(3)
		g._despawn(pv)


func _shots_lists() -> void:
	var sh = g.get_helper("safehouse")
	var base: Transform3D = sh.get_marker("Garage_Spot")
	var specs := [["muscle", Color("#D8342C"), {"engine": "engine_3", "spoiler": "spoiler_b", "wheels": "wheels_deep"}, 1050.0],
			["suv", Color("#27405F"), {"tint": "tint_medium"}, 700.0], ["compact", Color("#1FA7A0"), {}, 850.0]]
	for i in specs.size():
		var s: Array = specs[i]
		var xf := Transform3D(base.basis, base.origin - base.basis.z * (9.0 + 6.0 * float(i)) + Vector3(0, 0.1, 0))
		var v := Game.spawn_vehicle(str(s[0]), xf, {"color": s[1], "mods": s[2], "health": float(s[3])})
		await TestHarness.wait_frames(2)
		if v != null:
			g.store_vehicle(v)
	await TestHarness.wait_frames(3)
	var gl := UI.open_screen("garage", {"mode": "stored", "site": "safehouse", "title": "Safehouse garage"})
	TestHarness.check(gl != null, "garage list opened")
	await _wait(0.9)
	await TestHarness.shot("gar_list")
	UI.close_screen("garage")
	var acc = g.get_helper("access")
	var cat: Control = acc.open_terminal("airport")
	TestHarness.check(cat != null, "aircraft catalogue opened")
	await _wait(0.9)
	await TestHarness.shot("gar_catalogue")
	UI.close_screen("garage")
	await TestHarness.wait_frames(2)


func _shots_home() -> void:
	var sh = g.get_helper("safehouse")
	var inside: Transform3D = sh.get_marker("Spawn_Inside")
	Game.player.call("teleport", inside.origin + Vector3(0, 0.05, 0), Sites_yaw(inside))
	var fwd := -inside.basis.z
	var cam := Camera3D.new()
	cam.fov = 70.0
	Game.get_entities_root().add_child(cam)
	cam.global_position = inside.origin + Vector3(0, 1.75, 0) - fwd * 0.6 + inside.basis.x * 0.4
	cam.look_at(inside.origin + fwd * 7.0 + Vector3(0, 1.0, 0), Vector3.UP)
	var prev := get_viewport().get_camera_3d()
	cam.make_current()
	UI.set_hud_visible(false)
	if Game.player.has_method("set_visual_hidden"):
		Game.player.call("set_visual_hidden", "gar_shot", true)
	await _wait(1.0)
	await TestHarness.shot("gar_safehouse")
	if Game.player.has_method("set_visual_hidden"):
		Game.player.call("set_visual_hidden", "gar_shot", false)
	UI.set_hud_visible(true)
	if prev != null and is_instance_valid(prev):
		prev.make_current()
	cam.queue_free()
	await TestHarness.wait_frames(10)
	var scr := UI.open_screen("safehouse", {"focus": "sleep"})
	TestHarness.check(scr != null, "safehouse menu opened")
	await _wait(0.8)
	await TestHarness.shot("gar_safehouse_menu")
	UI.close_screen("safehouse")
	await TestHarness.wait_frames(2)


func _shot_terminal() -> void:
	var acc = g.get_helper("access")
	var xf: Transform3D = acc.get_terminal_transform("parking_garage")
	var screen_dir := -xf.basis.z
	var stand := xf.origin + screen_dir * 1.5 + xf.basis.x * 0.5
	Game.player.call("teleport", stand, atan2(screen_dir.x, screen_dir.z))
	await _wait(1.4)
	await TestHarness.shot("gar_terminal")


static func Sites_yaw(xf: Transform3D) -> float:
	var f := -xf.basis.z
	return atan2(-f.x, -f.z)
