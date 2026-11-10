extends Node
## ENVIRONMENT test (headless): clock flow, phases, weather blending, wetness, lightning, the
## automatic weather cycle, save / load round-trips and the environment system API.
## Run:
##   tools\godot.ps1 -Mode headless -Frames 3400 -UserArgs '--test=env_cycle','--no_player','--seed=7','--disable=world,city,interactions,vehicles,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## (it also passes with the world loaded; the list above just keeps the run short).

var _time_events: int = 0
var _phases: Array[String] = []
var _weather_events: Array[String] = []
var _strikes: int = 0
var _jumps: int = 0
var _underwater_events: Array[bool] = []


func _ready() -> void:
	EventBus.time_changed.connect(func(_h: float) -> void: _time_events += 1)
	EventBus.day_phase_changed.connect(func(p: String) -> void: _phases.append(p))
	EventBus.weather_changed.connect(func(id: String, _prev: String) -> void: _weather_events.append(id))
	Weather.lightning_strike.connect(func(_d: float, _t: float) -> void: _strikes += 1)
	WorldClock.time_jumped.connect(func(_h: float) -> void: _jumps += 1)
	await _run()


## Order-sensitive comparison that does not care about typed vs untyped arrays.
func _same(a: Array, b: Array) -> bool:
	return str(a) == str(b)


func _run() -> void:
	var t := TestHarness
	Weather.auto_cycle = false
	WorldClock.paused = false
	WorldClock.rate = WorldClock.GAME_SECONDS_PER_REAL_SECOND
	await t.wait_frames(5)

	# --- 1. the clock flows smoothly at the default rate (24 h = 24 real minutes) -----------
	t.check(is_equal_approx(WorldClock.get_day_length_minutes(), 24.0), "default day length is 24 real minutes")
	WorldClock.set_hour(12.0)
	t.check(_jumps == 1, "set_hour emits time_jumped")
	var h0 := WorldClock.hour
	var total0 := WorldClock.total_hours
	_time_events = 0
	await t.wait_seconds(2.0)
	var dh := WorldClock.hour - h0
	t.check(absf(dh - 2.0 / 60.0) < 0.004, "2 s of play = 2 game minutes (got %.4f h)" % dh)
	t.check(absf((WorldClock.total_hours - total0) - dh) < 0.0005, "total_hours follows natural flow")
	t.check(_time_events >= 1 and _time_events <= 4, "time_changed fires about once per game minute (%d)" % _time_events)
	t.check(WorldClock.get_time_string() == "12:02", "time string is 12:02 (got %s)" % WorldClock.get_time_string())

	# --- 2. paused clock stands still ----------------------------------------------------------
	WorldClock.paused = true
	var hp := WorldClock.hour
	await t.wait_seconds(0.5)
	t.check(is_equal_approx(WorldClock.hour, hp), "paused clock does not move")
	WorldClock.paused = false

	# --- 3. a full day: phases change in order, the day counter rolls over ------------------
	WorldClock.set_hour(4.5)
	t.check(WorldClock.get_phase() == "night" and WorldClock.is_night(), "04:30 is night")
	_phases.clear()
	var day0 := WorldClock.day
	WorldClock.rate = 3600.0 * 4.0          # 4 game hours per second
	await t.wait_seconds(6.2)               # ~24.8 game hours
	WorldClock.rate = WorldClock.GAME_SECONDS_PER_REAL_SECOND
	t.check(_phases.size() >= 5 and _same(_phases.slice(0, 4), ["dawn", "day", "dusk", "night"]),
			"phases fire in order dawn, day, dusk, night (got %s)" % str(_phases))
	t.check(WorldClock.day == day0 + 1, "day counter rolled over once")

	# --- 4. derived values ----------------------------------------------------------------------
	t.check(is_equal_approx(WorldClock.daylight_at(12.0), 1.0) and is_zero_approx(WorldClock.daylight_at(0.5)),
			"daylight is 1 at noon and 0 at night")
	var d_dawn := WorldClock.daylight_at(6.0)
	var d_dusk := WorldClock.daylight_at(19.5)
	t.check(d_dawn > 0.05 and d_dawn < 0.95 and d_dusk > 0.05 and d_dusk < 0.95, "daylight is smooth at dawn / dusk")
	var mono := true
	var prev := -1.0
	for i in 60:
		var v := WorldClock.daylight_at(5.0 + float(i) * (2.0 / 59.0))
		if v < prev - 0.00001:
			mono = false
		prev = v
	t.check(mono, "daylight rises monotonically through dawn")
	t.check(WorldClock.sun_direction_at(12.5).y > 0.8, "sun is high at midday")
	t.check(WorldClock.sun_direction_at(6.0).x > 0.8 and WorldClock.sun_direction_at(19.0).x < -0.8, "sun rises east (+X), sets west (-X)")
	t.check(WorldClock.sun_direction_at(0.5).y < -0.5, "sun is below the horizon at night")
	t.check(WorldClock.moon_direction_at(0.5).y > 0.3, "moon is up at night")
	WorldClock.set_hour(18.4)
	_phases.clear()
	WorldClock.set_hour(18.6)
	t.check(_same(_phases, ["dusk"]), "set_hour emits day_phase_changed immediately")
	var day1 := WorldClock.day
	WorldClock.set_hour(22.0)
	WorldClock.advance_hours(5.0)
	t.check(WorldClock.day == day1 + 1 and absf(WorldClock.hour - 3.0) < 0.001, "advance_hours wraps to the next day")

	# --- 5. weather blending -----------------------------------------------------------------
	WorldClock.set_hour(13.0)
	Weather.snap_weather("clear", 0.0)
	t.check(Weather.current == "clear" and is_zero_approx(Weather.rain_intensity) and is_zero_approx(Weather.wetness), "snap to clear / dry")
	t.check(is_equal_approx(Weather.get_grip_multiplier(), 1.0) and is_equal_approx(Weather.get_visibility(), 160.0), "dry grip 1.0, clear visibility 160 m")
	_weather_events.clear()
	var cover0 := Weather.cloud_cover
	Weather.set_weather("rain", 2.0)
	t.check(Weather.current == "rain" and Weather.previous == "clear" and _same(_weather_events, ["rain"]), "set_weather switches and emits weather_changed")
	t.check(is_equal_approx(Weather.cloud_cover, cover0), "blend starts from the current values (no pop)")
	await t.wait_seconds(1.0)
	var target_cover: float = Weather.PRESETS["rain"]["cloud_cover"]
	t.check(Weather.is_transitioning() and Weather.cloud_cover > cover0 + 0.05 and Weather.cloud_cover < target_cover - 0.05,
			"mid-transition values are in between (cover %.2f)" % Weather.cloud_cover)
	await t.wait_seconds(1.3)
	var target_rain: float = Weather.PRESETS["rain"]["rain_intensity"]
	t.check(not Weather.is_transitioning() and is_equal_approx(Weather.rain_intensity, target_rain), "transition reaches the rain preset")
	t.check(Weather.is_raining() and Weather.get_visibility() < 150.0, "raining, visibility reduced (%.0f m)" % Weather.get_visibility())
	Weather.set_weather("nonsense", 1.0)
	t.check(Weather.current == "rain", "unknown weather ids are ignored")

	# --- 6. wetness rises in rain and falls afterwards -----------------------------------
	var w0 := Weather.wetness
	await t.wait_seconds(3.0)
	var w1 := Weather.wetness
	t.check(w1 > w0 + 0.05, "wetness rises in rain (%.3f -> %.3f)" % [w0, w1])
	t.check(Weather.get_grip_multiplier() < 1.0 and Weather.get_grip_multiplier() >= 0.75, "wet grip is between 0.75 and 1")
	Weather.snap_weather("rain")
	t.check(is_equal_approx(Weather.wetness, 1.0) and is_equal_approx(Weather.get_grip_multiplier(), 0.75), "soaked: wetness 1, grip 0.75")
	Weather.set_weather("clear", 0.5)
	await t.wait_seconds(4.0)
	var w2 := Weather.wetness
	t.check(w2 < 0.995 and w2 > 0.5, "wetness dries slowly after the rain (%.3f)" % w2)
	WorldClock.advance_hours(6.0)
	await t.wait_frames(3)
	t.check(Weather.wetness < 0.05, "a 6 h time skip dries the streets (%.3f)" % Weather.wetness)

	# --- 7. storm lightning ----------------------------------------------------------------
	Weather.snap_weather("storm")
	t.check(is_equal_approx(Weather.storminess, 1.0) and is_equal_approx(Weather.wind_strength, 1.0), "storm preset applied")
	_strikes = 0
	Weather.trigger_lightning(500.0)
	t.check(_strikes == 1 and Weather.lightning_flash > 0.5, "trigger_lightning pulses lightning_flash and emits lightning_strike")
	await t.wait_seconds(1.5)
	t.check(Weather.lightning_flash < 0.05, "lightning flash decays")
	await t.wait_seconds(16.0)
	t.check(_strikes >= 2, "storms produce lightning by themselves (%d strikes)" % _strikes)
	Weather.snap_weather("clear", 0.0)
	var strikes_before := _strikes
	await t.wait_seconds(1.0)
	t.check(_strikes == strikes_before, "no lightning in clear weather")

	# --- 8. automatic weather cycle ----------------------------------------------------------
	_weather_events.clear()
	Weather.auto_cycle = true
	WorldClock.rate = 3600.0 * 6.0          # 6 game hours per second
	await t.wait_seconds(8.0)               # 48 game hours
	WorldClock.rate = WorldClock.GAME_SECONDS_PER_REAL_SECOND
	Weather.auto_cycle = false
	t.check(_weather_events.size() >= 2, "auto cycle changed the weather over 48 game hours (%s)" % str(_weather_events))
	Weather.snap_weather("clear", 0.0)
	WorldClock.set_hour(14.0)
	var fair := 0
	for i in 4000:
		var id2 := Weather.roll_next_weather()
		if id2 == "clear" or id2 == "cloudy":
			fair += 1
	t.check(fair > 2800, "from clear weather the cycle mostly picks clear / cloudy (%d of 4000)" % fair)

	# --- 9. save / load round trip ---------------------------------------------------------
	WorldClock.set_hour(17.25)
	WorldClock.day = 5
	Weather.snap_weather("fog", 0.4)
	Weather.auto_cycle = false
	var clock_blob: Variant = JSON.parse_string(JSON.stringify(WorldClock.get_save_data()))
	var weather_blob: Variant = JSON.parse_string(JSON.stringify(Weather.get_save_data()))
	var has_file := false
	if not Game.has_player() and SaveSystem.has_method("save_game"):
		has_file = SaveSystem.save_game("env_cycle_test")
	WorldClock.set_hour(3.0)
	WorldClock.day = 1
	Weather.snap_weather("clear", 0.0)
	Weather.auto_cycle = true
	t.check(clock_blob is Dictionary and weather_blob is Dictionary, "save data is JSON-safe")
	WorldClock.load_save_data(clock_blob as Dictionary)
	Weather.load_save_data(weather_blob as Dictionary)
	t.check(absf(WorldClock.hour - 17.25) < 0.001 and WorldClock.day == 5, "clock round-trips (hour %.2f day %d)" % [WorldClock.hour, WorldClock.day])
	t.check(Weather.current == "fog" and absf(Weather.wetness - 0.4) < 0.001 and not Weather.auto_cycle,
			"weather round-trips (%s wet %.2f)" % [Weather.current, Weather.wetness])
	t.check(is_equal_approx(Weather.fog_amount, 1.0) and Weather.get_visibility() < 50.0, "loaded fog is fully applied at once")
	if has_file:
		WorldClock.set_hour(3.0)
		WorldClock.day = 1
		Weather.snap_weather("clear", 0.0)
		var ok: bool = SaveSystem.load_game("env_cycle_test")
		t.check(ok and absf(WorldClock.hour - 17.25) < 0.01 and Weather.current == "fog", "SaveSystem file round-trip restores clock and weather")
		if SaveSystem.has_method("delete_save"):
			SaveSystem.delete_save("env_cycle_test")
	WorldClock.load_save_data({})
	Weather.load_save_data({})
	t.check(WorldClock.day == 1 and Weather.current == "clear", "loading empty data falls back to defaults")

	# --- 9b. a save from a LONGER session (every load after a restart): the restored
	#         total_hours counter must not be mistaken for a time skip ------------------------
	for clock_first: bool in [true, false]:
		WorldClock.set_hour(10.0)
		Weather.snap_weather("fog", 0.4)
		Weather.auto_cycle = true
		var save_c: Dictionary = JSON.parse_string(JSON.stringify(WorldClock.get_save_data()))
		var save_w: Dictionary = JSON.parse_string(JSON.stringify(Weather.get_save_data()))
		save_c["total_hours"] = WorldClock.total_hours + 400.0
		save_w["hours_until_change"] = 1.5
		Weather.snap_weather("clear", 0.0)
		if clock_first:
			WorldClock.load_save_data(save_c)
			Weather.load_save_data(save_w)
		else:
			Weather.load_save_data(save_w)
			WorldClock.load_save_data(save_c)
		await t.wait_frames(6)
		t.check(Weather.current == "fog" and absf(Weather.wetness - 0.4) < 0.02
				and absf(Weather.get_hours_until_change() - 1.5) < 0.05,
				"loading a save with a larger total_hours keeps weather / wetness (%s first: %s wet %.2f next %.2f h)" % [
				"clock" if clock_first else "weather", Weather.current, Weather.wetness, Weather.get_hours_until_change()])
		Weather.auto_cycle = false
	WorldClock.load_save_data({})
	Weather.load_save_data({})
	# A real skip (sleeping) must still count: 6 h later the cycle has rolled at least once.
	Weather.snap_weather("clear", 0.0)
	Weather.auto_cycle = true
	var due := Weather.get_hours_until_change()
	WorldClock.advance_hours(due + 0.5)
	await t.wait_frames(3)
	t.check(not is_equal_approx(Weather.get_hours_until_change(), due) and Weather.get_hours_until_change() > 0.0,
			"advance_hours past the due time still triggers the automatic cycle")
	Weather.auto_cycle = false
	Weather.snap_weather("clear", 0.0)

	# --- 10. environment system API ------------------------------------------------------------
	await _check_environment_system()

	Weather.auto_cycle = true
	t.log_line("orphan nodes at the end: %d" % int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
	t.finish()


func _check_environment_system() -> void:
	var t := TestHarness
	var env := Game.get_system("environment")
	if env == null:
		t.log_line("environment system not loaded - API checks skipped")
		return
	var cam := Camera3D.new()
	cam.name = "EnvCycleCamera"
	add_child(cam)
	cam.global_position = Vector3(40.0, 6.0, 380.0)
	cam.current = true
	env.underwater_changed.connect(func(on: bool) -> void: _underwater_events.append(on))
	WorldClock.paused = true
	WorldClock.set_hour(12.0)
	Weather.snap_weather("clear", 0.0)
	await t.wait_frames(4)

	# Waves: bounded, animated, flat far from the camera.
	var lo := 1000.0
	var hi := -1000.0
	for i in 400:
		var h: float = env.get_wave_height(40.0 + float(i % 20) * 1.7, 380.0 + floorf(float(i) / 20.0) * 1.3)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	t.check(hi <= Game.WATER_LEVEL + 0.2501 and lo >= Game.WATER_LEVEL - 0.2501, "waves stay within +-0.25 m (%.3f .. %.3f)" % [lo, hi])
	t.check(hi - lo > 0.03, "waves have visible height variation")
	var h_a: float = env.get_wave_height(41.0, 381.0)
	await t.wait_seconds(0.7)
	var h_b: float = env.get_wave_height(41.0, 381.0)
	t.check(absf(h_a - h_b) > 0.0005, "waves move over time")
	t.check(is_equal_approx(env.get_wave_height(4000.0, 4000.0), Game.WATER_LEVEL), "far from the camera the surface is flat")
	Weather.snap_weather("storm")
	await t.wait_frames(3)
	var storm_hi := -1000.0
	for i in 400:
		storm_hi = maxf(storm_hi, absf(env.get_wave_height(40.0 + float(i % 20) * 1.7, 380.0 + floorf(float(i) / 20.0) * 1.3) - Game.WATER_LEVEL))
	t.check(storm_hi <= 0.2501 and storm_hi > hi - Game.WATER_LEVEL, "storm waves are higher but still <= 0.25 m (%.3f)" % storm_hi)

	# The CPU surface is the RENDERED triangle mesh: exact at the 2 m lattice vertices, linear
	# inside each triangle, and never far from the ideal sine sum (still in the storm here).
	var ocean: Variant = env.get("ocean")
	var lattice_ok := true
	var linear_ok := true
	var max_dev := 0.0
	for i in 200:
		var vx := 40.0 + float((i * 7) % 30 - 15) * 2.0
		var vz := 380.0 + float((i * 11) % 30 - 15) * 2.0
		var a: float = env.get_wave_height(vx, vz)
		var b: float = env.get_wave_height(vx + 2.0, vz)
		var c: float = env.get_wave_height(vx, vz + 2.0)
		var d: float = env.get_wave_height(vx + 2.0, vz + 2.0)
		if absf(a - (Game.WATER_LEVEL + float(ocean.vertex_offset(vx, vz)))) > 0.00001:
			lattice_ok = false
		var p1: float = env.get_wave_height(vx + 0.5, vz + 0.7)      # triangle (a, b, c)
		var p2: float = env.get_wave_height(vx + 1.6, vz + 1.1)      # triangle (d, c, b)
		if absf(p1 - (a + (b - a) * 0.25 + (c - a) * 0.35)) > 0.00001:
			linear_ok = false
		if absf(p2 - (d + (c - d) * 0.2 + (b - d) * 0.45)) > 0.00001:
			linear_ok = false
		max_dev = maxf(max_dev, absf(p1 - float(ocean.get_smooth_height(vx + 0.5, vz + 0.7))))
		max_dev = maxf(max_dev, absf(p2 - float(ocean.get_smooth_height(vx + 1.6, vz + 1.1))))
	t.check(lattice_ok, "get_wave_height equals the shader vertex function on the mesh lattice")
	t.check(linear_ok, "get_wave_height interpolates the mesh triangles (same diagonal as the mesh)")
	t.check(max_dev > 0.002 and max_dev < 0.08, "faceted surface stays within a few cm of the sine sum (max %.3f m)" % max_dev)
	var nrm: Vector3 = env.get_water_normal(41.0, 381.0)
	t.check(nrm.y > 0.9 and is_equal_approx(nrm.length(), 1.0), "water normal is a unit vector pointing up")
	var mismatch := _ocean_constants_mismatch(ocean)
	t.check(mismatch == "", "wave constants in env_ocean.gdshader match ocean_surface.gd %s" % mismatch)
	Weather.snap_weather("clear", 0.0)

	# Night-light hook materials.
	var win: ShaderMaterial = env.get_window_material()
	var lamp: ShaderMaterial = env.get_lamp_material()
	var neon: ShaderMaterial = env.get_neon_material(Color(1.0, 0.2, 0.6))
	t.check(win != null and lamp != null and neon != null and win.shader != null, "hook materials exist")
	t.check(env.get_window_material() == win and env.get_neon_material(Color(1.0, 0.2, 0.6)) == neon, "hook materials are shared (cached)")
	t.check(env.get_neon_material(Color(0.1, 0.9, 1.0)) != neon, "neon materials differ per colour")
	var holder := Node3D.new()
	add_child(holder)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	var named := StandardMaterial3D.new()
	named.resource_name = "M_Window"
	box.material = named
	mi.mesh = box
	holder.add_child(mi)
	var mi2 := MeshInstance3D.new()
	var box2 := BoxMesh.new()
	var named2 := StandardMaterial3D.new()
	named2.resource_name = "P_Neon_Pink"
	named2.albedo_color = Color(1.0, 0.3, 0.7)
	box2.material = named2
	mi2.mesh = box2
	holder.add_child(mi2)
	var mi3 := MeshInstance3D.new()
	var box3 := BoxMesh.new()
	var named3 := StandardMaterial3D.new()
	named3.resource_name = "P_Concrete"
	box3.material = named3
	mi3.mesh = box3
	holder.add_child(mi3)
	var replaced: int = env.apply_night_materials(holder)
	t.check(replaced == 2 and mi.get_surface_override_material(0) == win and mi3.get_surface_override_material(0) == null,
			"apply_night_materials swaps M_Window / P_Neon* only (%d)" % replaced)
	holder.queue_free()

	# Automatic hooks: a mesh that simply enters the tree gets its hook materials a frame later.
	var nm: Variant = env.get("night_materials")
	var auto_holder := Node3D.new()
	add_child(auto_holder)
	var auto_mesh := _named_mesh(["M_Window", "P_Plaster", "M_LampGlow"])
	var auto_mi := MeshInstance3D.new()
	auto_mi.mesh = auto_mesh
	auto_holder.add_child(auto_mi)
	var skip_mi := MeshInstance3D.new()
	skip_mi.mesh = auto_mesh
	skip_mi.add_to_group("env_no_night_hook")
	auto_holder.add_child(skip_mi)
	var late_mi := MeshInstance3D.new()
	auto_holder.add_child(late_mi)
	late_mi.mesh = auto_mesh                       # mesh assigned AFTER add_child, same frame
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _named_mesh(["P_NeonCyan", "P_Steel"])
	mm.instance_count = 2
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	auto_holder.add_child(mmi)
	await t.wait_frames(3)
	t.check(nm.is_hook_material(auto_mi.get_surface_override_material(0)) and auto_mi.get_surface_override_material(1) == null
			and nm.is_hook_material(auto_mi.get_surface_override_material(2)),
			"auto hook: M_Window / M_LampGlow surfaces of a new MeshInstance3D are swapped, others untouched")
	t.check(nm.is_hook_material(late_mi.get_surface_override_material(0)), "auto hook also catches a mesh assigned after add_child")
	t.check(skip_mi.get_surface_override_material(0) == null, "group env_no_night_hook opts a node out")
	t.check(nm.is_hook_material(mm.mesh.surface_get_material(0)) and not nm.is_hook_material(mm.mesh.surface_get_material(1)),
			"auto hook swaps P_Neon* on the mesh resource of a MultiMesh")
	t.check(int(env.apply_night_materials(auto_mi)) == 0, "explicit apply on an already hooked mesh changes nothing")
	t.check(String(auto_mi.get_surface_override_material(0).resource_name).begins_with("M_Window"),
			"hook materials keep the Blender name as prefix")
	auto_holder.queue_free()

	var wet: ShaderMaterial = env.make_wet_surface_material(Color(0.3, 0.31, 0.33), 0.6)
	t.check(wet != null and wet.shader != null and is_equal_approx(float(wet.get_shader_parameter("puddle_amount")), 0.6),
			"wet-surface hook material is available")

	# Pooled street lights: off by day, <= 14 near the camera at night.
	var pts: Array = []
	for i in 60:
		pts.append(Vector3(40.0 + float(i % 10) * 12.0 - 54.0, 7.0, 380.0 - floorf(float(i) / 10.0) * 12.0))
	env.clear_light_points()
	env.register_light_points(pts, Color(1.0, 0.8, 0.5), 15.0, 2.4)
	t.check(env.get_light_point_count() == 60, "60 light points registered")
	await t.wait_seconds(0.6)
	t.check(env.get_active_light_count() == 0, "street light pool is off at noon")
	WorldClock.set_hour(23.0)
	await t.wait_seconds(1.2)
	var active: int = env.get_active_light_count()
	t.check(active > 0 and active <= 14, "at night the pool lights the nearest points only (%d active)" % active)
	t.check(env.night_factor > 0.95, "gta_night is ~1 at 23:00")
	cam.global_position = Vector3(40.0, 6.0, 2000.0)
	await t.wait_seconds(1.5)
	t.check(env.get_active_light_count() == 0, "lights fade out when the camera leaves")
	env.clear_light_points()

	# Lamps only need the group "street_light": the marker "Light" becomes an owned light point.
	cam.global_position = Vector3(40.0, 6.0, 380.0)
	var post := Node3D.new()
	post.name = "EnvCycleLamp"
	add_child(post)
	post.global_position = Vector3(44.0, 0.5, 372.0)
	var marker := Node3D.new()
	marker.name = "Light"
	post.add_child(marker)
	marker.position = Vector3(0.0, 6.0, -1.0)
	post.add_to_group("street_light")
	await t.wait_seconds(1.4)
	t.check(env.get_light_point_count() == 1, "a node in group street_light is registered by itself (%d)" % env.get_light_point_count())
	env.register_light_points([marker.global_position + Vector3(0.2, 0.0, 0.1)], Color(1.0, 0.8, 0.5), 15.0, 2.4)
	t.check(env.get_light_point_count() == 1, "registering the same lamp again is ignored (no double light)")
	env.register_light_points([Vector3(52.0, 6.0, 372.0), Vector3(60.0, 6.0, 372.0), Vector3(68.0, 6.0, 372.0)], Color(1.0, 0.8, 0.5), 15.0, 2.4)
	await t.wait_seconds(1.0)
	t.check(env.get_active_light_count() == 4, "group lamp + 3 static points are lit at night (%d)" % env.get_active_light_count())
	env.set_street_light_budget(2)
	await t.wait_seconds(1.0)
	t.check(env.get_active_light_count() == 2, "set_street_light_budget(2) caps the lit lamps (%d)" % env.get_active_light_count())
	env.set_street_light_budget(14)
	post.global_position += Vector3(0.0, -4.0, 3.0)           # knocked over
	await t.wait_seconds(0.5)
	t.check(env.get_light_point_count() == 3, "a lamp that was knocked away loses its light point (%d)" % env.get_light_point_count())
	post.queue_free()
	var post2 := Node3D.new()
	add_child(post2)
	post2.global_position = Vector3(44.0, 0.5, 364.0)
	var marker2 := Node3D.new()
	marker2.name = "Light"
	post2.add_child(marker2)
	marker2.position = Vector3(0.0, 4.0, 0.0)
	post2.add_to_group("street_light")
	await t.wait_seconds(1.6)
	t.check(env.get_light_point_count() == 4, "a second group lamp is picked up (%d)" % env.get_light_point_count())
	post2.queue_free()
	await t.wait_seconds(0.6)
	t.check(env.get_light_point_count() == 3, "a freed lamp node takes its light with it (%d)" % env.get_light_point_count())
	env.clear_light_points()

	# Paused tree: gta_time stands still, but admin-menu time changes still show at once.
	var ts0: float = env.time_seconds
	get_tree().paused = true
	WorldClock.set_hour(12.0)
	await t.wait_frames(4)
	t.check(is_equal_approx(env.time_seconds, ts0) and env.night_factor < 0.05,
			"paused: gta_time is frozen, set_hour(12) is applied (night %.2f)" % env.night_factor)
	WorldClock.set_hour(23.0)
	await t.wait_frames(2)
	t.check(env.night_factor > 0.95, "paused: set_hour(23) is applied")
	get_tree().paused = false
	await t.wait_frames(2)
	t.check(env.time_seconds > ts0, "unpaused: gta_time runs again")
	# (The global shader uniforms themselves are verified on the GPU by the windowed env_waves test.)

	# Underwater switch.
	if Game.world == null:
		cam.global_position = Vector3(40.0, -3.0, 380.0)
		await t.wait_frames(3)
		t.check(env.is_camera_underwater() and _same(_underwater_events, [true]), "camera below the surface -> underwater")
		for i in 4:
			cam.global_position = Vector3(40.0, float(env.get_wave_height(40.0, 380.0)) + 0.008, 380.0)
			await t.wait_frames(1)
		t.check(env.is_camera_underwater() and _same(_underwater_events, [true]), "8 mm above the surface the underwater state holds (hysteresis)")
		cam.global_position = Vector3(40.0, 3.0, 380.0)
		await t.wait_frames(3)
		t.check(not env.is_camera_underwater() and _same(_underwater_events, [true, false]), "camera above the surface -> not underwater")
		for i in 4:
			cam.global_position = Vector3(40.0, float(env.get_wave_height(40.0, 380.0)) - 0.01, 380.0)
			await t.wait_frames(1)
		t.check(not env.is_camera_underwater() and _same(_underwater_events, [true, false]), "1 cm below the surface is not underwater yet (no flicker at the waterline)")
	var info: Dictionary = env.get_debug_info()
	t.check(info.has("weather") and info.has("lights_active"), "debug info available")
	cam.queue_free()
	WorldClock.paused = false


## Flat test mesh with one surface per name; each surface carries a material with that
## resource_name (like an imported GLB).
func _named_mesh(names: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for i in names.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var x := float(i)
		for v: Vector3 in [Vector3(x, 0, 0), Vector3(x + 1.0, 0, 0), Vector3(x, 1, 0)]:
			st.set_normal(Vector3(0, 0, 1))
			st.set_uv(Vector2(v.x, v.y))
			st.add_vertex(v)
		var mat := StandardMaterial3D.new()
		mat.resource_name = String(names[i])
		mat.albedo_color = Color(0.2, 0.9, 1.0)
		st.set_material(mat)
		st.commit(mesh)
	return mesh


## Compares the wave constants in the ocean shader SOURCE with the CPU constants of
## OceanSurface. Returns "" when they match, otherwise a short description.
func _ocean_constants_mismatch(ocean: Variant) -> String:
	var mat := ocean.get("material") as ShaderMaterial
	if mat == null or mat.shader == null:
		return "(no ocean material)"
	var code: String = mat.shader.code
	var dirs: Array = ocean.WAVE_DIR
	var ks: Array = ocean.WAVE_K
	var speeds: Array = ocean.WAVE_SPEED
	var weights: Array = ocean.WAVE_WEIGHT
	var phases: Array = ocean.WAVE_PHASE
	var found := 0
	var re_d := RegEx.create_from_string("W_D(\\d)\\s*=\\s*vec2\\(\\s*(-?[0-9.]+)\\s*,\\s*(-?[0-9.]+)\\s*\\)")
	for m: RegExMatch in re_d.search_all(code):
		var i := int(m.get_string(1)) - 1
		var d: Vector2 = dirs[i]
		if absf(float(m.get_string(2)) - d.x) > 0.00002 or absf(float(m.get_string(3)) - d.y) > 0.00002:
			return "(direction %d differs)" % (i + 1)
		found += 1
	var re_k := RegEx.create_from_string("W_K(\\d)\\s*=\\s*([0-9.]+)")
	for m: RegExMatch in re_k.search_all(code):
		var i := int(m.get_string(1)) - 1
		if absf(float(m.get_string(2)) - float(ks[i])) > 0.00002:
			return "(wave number %d differs)" % (i + 1)
		found += 1
	var re_s := RegEx.create_from_string("W_S(\\d)\\s*=\\s*([0-9.]+)")
	for m: RegExMatch in re_s.search_all(code):
		var i := int(m.get_string(1)) - 1
		if absf(float(m.get_string(2)) - float(speeds[i])) > 0.00002:
			return "(speed %d differs)" % (i + 1)
		found += 1
	var re_w := RegEx.create_from_string("([0-9.]+)\\s*\\*\\s*sin\\(dot\\(p,\\s*W_D(\\d)\\)\\s*\\*\\s*W_K\\d\\s*\\+\\s*t\\s*\\*\\s*W_S\\d(?:\\s*\\+\\s*([0-9.]+))?\\)")
	for m: RegExMatch in re_w.search_all(code):
		var i := int(m.get_string(2)) - 1
		var phase := float(m.get_string(3)) if m.get_string(3) != "" else 0.0
		if absf(float(m.get_string(1)) - float(weights[i])) > 0.00002 or absf(phase - float(phases[i])) > 0.00002:
			return "(weight / phase %d differs)" % (i + 1)
		found += 1
	if found != 16:
		return "(expected 16 constants in the shader source, parsed %d)" % found
	if absf(float(mat.get_shader_parameter("facet_size")) - float(ocean.FINE_CELL)) > 0.0001 \
			or absf(float(mat.get_shader_parameter("wave_fade_start")) - float(ocean.WAVE_FADE_START)) > 0.0001 \
			or absf(float(mat.get_shader_parameter("wave_fade_end")) - float(ocean.WAVE_FADE_END)) > 0.0001:
		return "(facet size / fade distances differ)"
	return ""
