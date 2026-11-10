class_name WorldEnv
extends Node3D
## Time of day + weather + all sky / lighting / fog presentation.
## Game.time and Game.weather both point at this node.

signal night_changed(is_night: bool)

const HOUR_SECONDS := 75.0     # real seconds per in-game hour (a full day = 30 minutes)

const WEATHERS := {
	&"clear": {"clouds": 0.24, "density": 0.85, "fog": 0.0007, "rain": 0.0, "wind": 0.3, "light": 1.0, "wet": 0.0, "storm": 0.0, "waves": 0.26},
	&"cloudy": {"clouds": 0.7, "density": 1.0, "fog": 0.0014, "rain": 0.0, "wind": 0.55, "light": 0.72, "wet": 0.0, "storm": 0.0, "waves": 0.34},
	&"rain": {"clouds": 0.92, "density": 1.0, "fog": 0.0042, "rain": 0.7, "wind": 0.75, "light": 0.5, "wet": 1.0, "storm": 0.0, "waves": 0.42},
	&"fog": {"clouds": 0.6, "density": 0.9, "fog": 0.022, "rain": 0.0, "wind": 0.12, "light": 0.66, "wet": 0.3, "storm": 0.0, "waves": 0.18},
	&"storm": {"clouds": 1.0, "density": 1.0, "fog": 0.006, "rain": 1.0, "wind": 1.25, "light": 0.36, "wet": 1.0, "storm": 1.0, "waves": 0.7},
}
const WEATHER_ORDER: Array[StringName] = [&"clear", &"cloudy", &"rain", &"fog", &"storm"]

# sky keyframes on the sun height (sin of elevation)
const KEYS := [
	{"s": -0.34, "top": Color(0.025, 0.04, 0.1), "hor": Color(0.09, 0.12, 0.22), "gnd": Color(0.05, 0.055, 0.075),
		"sun": Color(0.6, 0.7, 1.0), "glow": Color(0.12, 0.17, 0.32), "cloud": Color(0.13, 0.15, 0.22), "cshadow": Color(0.04, 0.05, 0.09), "amb": 1.35},
	{"s": -0.12, "top": Color(0.07, 0.09, 0.22), "hor": Color(0.6, 0.33, 0.42), "gnd": Color(0.07, 0.07, 0.1),
		"sun": Color(1.0, 0.5, 0.3), "glow": Color(1.0, 0.4, 0.35), "cloud": Color(0.72, 0.45, 0.5), "cshadow": Color(0.2, 0.15, 0.25), "amb": 0.66},
	{"s": 0.03, "top": Color(0.22, 0.33, 0.6), "hor": Color(0.98, 0.66, 0.42), "gnd": Color(0.2, 0.18, 0.18),
		"sun": Color(1.0, 0.72, 0.45), "glow": Color(1.0, 0.55, 0.25), "cloud": Color(1.0, 0.8, 0.65), "cshadow": Color(0.5, 0.38, 0.42), "amb": 0.82},
	{"s": 0.3, "top": Color(0.15, 0.39, 0.78), "hor": Color(0.63, 0.8, 0.94), "gnd": Color(0.32, 0.35, 0.36),
		"sun": Color(1.0, 0.96, 0.88), "glow": Color(1.0, 0.75, 0.5), "cloud": Color(1.0, 1.0, 1.0), "cshadow": Color(0.62, 0.67, 0.76), "amb": 1.0},
]

var hour := 10.0
var day := 0
var time_running := true
var time_scale := 1.0

var weather: StringName = &"clear"
var auto_weather := true
var _wp := {}                  # current (blended) weather parameters
var _wt := {}                  # target parameters
var _weather_timer := 240.0
var night := 0.0               # 0 = full day, 1 = full night
var wetness := 0.0
var rain := 0.0
var wind := 0.3
var sun_dir := Vector3(0.3, 0.8, 0.5)
var is_night := false

var env: Environment
var wenv: WorldEnvironment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var rain_fx: GPUParticles3D
var _rain_loop: AudioStreamPlayer
var _rain_heavy: AudioStreamPlayer
var _wind_loop: AudioStreamPlayer
var _flash := 0.0
var _next_lightning := 8.0
var _underwater := false
var _last_hour_int := -1
var _cloud_time := 0.0
var _indoor := 0.0
var _indoor_check := 0.0

func _ready() -> void:
	_wp = (WEATHERS[weather] as Dictionary).duplicate()
	_wt = _wp.duplicate()
	_build()
	_update(0.0, true)

func _build() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://gta/shaders/sky.gdshader")
	sky_mat.set_shader_parameter("noise_tex", Assets.noise_tex)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.84
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.fog_enabled = true
	env.fog_density = 0.0007
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	wenv = WorldEnvironment.new()
	wenv.environment = env
	add_child(wenv)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 170.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)
	_build_rain()
	_rain_loop = Audio.make_loop_2d(&"rain_loop", -80.0)
	_rain_heavy = Audio.make_loop_2d(&"rain_heavy_loop", -80.0)
	_wind_loop = Audio.make_loop_2d(&"amb_wind_loop", -80.0)
	Settings.changed.connect(_on_setting)
	_on_setting("quality_applied")

func _on_setting(key: String) -> void:
	if key != "quality_applied" and key != "quality":
		return
	var q := int(Settings.get_v("quality", 1))
	env.ssao_enabled = q >= 1
	env.glow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 110.0 if q == 0 else 170.0
	env.ssr_enabled = q >= 2
	env.ssr_max_steps = 32

func _build_rain() -> void:
	rain_fx = GPUParticles3D.new()
	rain_fx.name = "Rain"
	rain_fx.amount = 1400
	rain_fx.lifetime = 0.9
	rain_fx.preprocess = 0.5
	rain_fx.visibility_aabb = AABB(Vector3(-22, -24, -22), Vector3(44, 44, 44))
	rain_fx.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 0.5, 18)
	pm.direction = Vector3(0.12, -1, 0.05)
	pm.spread = 2.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 27.0
	pm.gravity = Vector3(0, -6, 0)
	rain_fx.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.022, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.78, 0.85, 0.95, 0.32)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	rain_fx.draw_pass_1 = quad
	rain_fx.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY
	rain_fx.emitting = false
	rain_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain_fx)

# ---------------------------------------------------------------- public API
func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	_update(0.0, true)

func advance_hours(h: float) -> void:
	hour += h
	while hour >= 24.0:
		hour -= 24.0
		day += 1
	_update(0.0, true)

func set_weather(kind: StringName, instant := false) -> void:
	if not WEATHERS.has(kind):
		return
	weather = kind
	_wt = (WEATHERS[kind] as Dictionary).duplicate()
	if instant:
		_wp = _wt.duplicate()
		_update(0.0, true)
	_weather_timer = randf_range(200.0, 420.0)
	Events.weather_changed.emit(kind)

func clock_text() -> String:
	var h := int(hour)
	var m := int((hour - float(h)) * 60.0)
	return "%02d:%02d" % [h, m]

## Tyre grip multiplier from the current road wetness.
func grip_factor() -> float:
	return lerpf(1.0, 0.72, wetness)

func visibility_range() -> float:
	## Rough AI sight range multiplier (fog / night / rain reduce it).
	var f := 1.0 - 0.35 * night
	f *= 1.0 - clampf(float(_wp["fog"]) * 28.0, 0.0, 0.55)
	return clampf(f, 0.3, 1.0)

func set_underwater(on: bool) -> void:
	_underwater = on

func save_state() -> Dictionary:
	return {"hour": hour, "day": day, "weather": String(weather), "auto": auto_weather}

func load_state(d: Dictionary) -> void:
	hour = float(d.get("hour", hour))
	day = int(d.get("day", day))
	auto_weather = bool(d.get("auto", true))
	set_weather(StringName(String(d.get("weather", "clear"))), true)

# ---------------------------------------------------------------- update
func _process(delta: float) -> void:
	if time_running:
		hour += delta / HOUR_SECONDS * time_scale
		if hour >= 24.0:
			hour -= 24.0
			day += 1
	if auto_weather:
		_weather_timer -= delta
		if _weather_timer <= 0.0:
			_pick_weather()
	_update(delta, false)

func _pick_weather() -> void:
	var r := randf()
	var next: StringName = &"clear"
	if r < 0.46: next = &"clear"
	elif r < 0.7: next = &"cloudy"
	elif r < 0.86: next = &"rain"
	elif r < 0.94: next = &"fog"
	else: next = &"storm"
	set_weather(next)

static func _key_lerp(s: float) -> Dictionary:
	var a: Dictionary = KEYS[0]
	var b: Dictionary = KEYS[KEYS.size() - 1]
	if s <= float(a["s"]):
		return a
	if s >= float(b["s"]):
		return b
	for i in range(KEYS.size() - 1):
		if s <= float(KEYS[i + 1]["s"]):
			a = KEYS[i]
			b = KEYS[i + 1]
			break
	var t := (s - float(a["s"])) / (float(b["s"]) - float(a["s"]))
	var out := {}
	for k in a.keys():
		if a[k] is Color:
			out[k] = (a[k] as Color).lerp(b[k], t)
		else:
			out[k] = lerpf(float(a[k]), float(b[k]), t)
	return out

func _update(delta: float, instant: bool) -> void:
	# --- blend weather parameters
	var k := 1.0 if instant else clampf(delta * 0.12, 0.0, 1.0)
	for key in _wt.keys():
		_wp[key] = lerpf(float(_wp[key]), float(_wt[key]), k)
	rain = float(_wp["rain"])
	wind = float(_wp["wind"])
	# roads get wet quickly, dry slowly
	var wet_target := float(_wp["wet"])
	var wk := 1.0 if instant else clampf(delta * (0.08 if wet_target > wetness else 0.02), 0.0, 1.0)
	wetness = lerpf(wetness, wet_target, wk)
	# --- sun / moon
	var a := (hour - 13.0) / 24.0 * TAU
	sun_dir = Vector3(-sin(a), cos(a) * 0.87, cos(a) * 0.5).normalized()
	var moon_dir := Vector3(sin(a) * 0.9, -cos(a) * 0.8, 0.45).normalized()
	var s := sun_dir.y
	var key := _key_lerp(s)
	night = 1.0 - smoothstep(-0.16, 0.1, s)
	var light: float = float(_wp["light"])
	var gray := Color(0.5, 0.52, 0.56)
	var overcast := clampf((float(_wp["clouds"]) - 0.45) * 1.8, 0.0, 1.0)
	var lum_scale := lerpf(1.0, 0.55 + 0.3 * light, overcast)
	var top: Color = (key["top"] as Color).lerp(gray * (key["top"] as Color).get_luminance() * 2.2, overcast * 0.85) * lum_scale
	var hor: Color = (key["hor"] as Color).lerp(gray * (key["hor"] as Color).get_luminance() * 1.5, overcast * 0.8) * lum_scale
	var flash_boost := _flash * 2.5
	sky_mat.set_shader_parameter("top_color", top + Color(flash_boost, flash_boost, flash_boost) * 0.3)
	sky_mat.set_shader_parameter("horizon_color", hor + Color(flash_boost, flash_boost, flash_boost) * 0.4)
	sky_mat.set_shader_parameter("ground_color", key["gnd"])
	sky_mat.set_shader_parameter("sun_color", key["sun"])
	sky_mat.set_shader_parameter("sun_glow", key["glow"])
	var ccol: Color = (key["cloud"] as Color).lerp((key["cloud"] as Color) * 0.5, overcast * (1.0 - light))
	sky_mat.set_shader_parameter("cloud_color", ccol + Color(flash_boost, flash_boost, flash_boost))
	sky_mat.set_shader_parameter("cloud_shadow", (key["cshadow"] as Color) * lerpf(1.0, 0.6, overcast))
	sky_mat.set_shader_parameter("cloud_cover", float(_wp["clouds"]))
	sky_mat.set_shader_parameter("cloud_density", float(_wp["density"]))
	sky_mat.set_shader_parameter("star_amount", night * (1.0 - overcast))
	sky_mat.set_shader_parameter("glow_amount", 0.55 * (1.0 - overcast * 0.7))
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("sun_visible", 1.0 - overcast * 0.85)
	_cloud_time += delta * (0.6 + wind * 2.0)
	sky_mat.set_shader_parameter("cloud_time", _cloud_time)
	# --- the single shadowed directional light plays sun by day and moon by night
	var day_energy := smoothstep(-0.02, 0.22, s) * 1.2 * lerpf(1.0, light * 0.55, overcast)
	if s > -0.04:
		sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO, Vector3.UP)
		sun.light_color = key["sun"]
		sun.light_energy = day_energy + _flash * 1.5
	else:
		sun.look_at_from_position(moon_dir * 100.0, Vector3.ZERO, Vector3.UP)
		sun.light_color = Color(0.55, 0.66, 1.0)
		sun.light_energy = smoothstep(0.0, 0.25, moon_dir.y) * 0.4 * (1.0 - overcast * 0.6) + _flash * 1.5
	sun.shadow_enabled = sun.light_energy > 0.02
	# --- ambient / fog / exposure
	env.ambient_light_energy = float(key["amb"]) * lerpf(1.0, 0.8, overcast) + _flash
	env.ambient_light_sky_contribution = 1.0
	var fog_col: Color = hor.lerp(top, 0.25)
	var fog_d := float(_wp["fog"]) * lerpf(1.0, 1.6, night * 0.3)
	if _underwater:
		fog_col = Color(0.04, 0.3, 0.38) * lerpf(1.0, 0.25, night)
		fog_d = 0.085
	env.fog_light_color = fog_col
	env.fog_density = fog_d
	env.fog_sky_affect = 1.0 if _underwater else clampf(0.2 + float(_wp["fog"]) * 30.0, 0.2, 0.95)
	env.fog_aerial_perspective = 0.0 if _underwater else 0.35
	# --- globals shared with every material
	RenderingServer.global_shader_parameter_set(&"night_factor", night)
	RenderingServer.global_shader_parameter_set(&"wetness", wetness)
	RenderingServer.global_shader_parameter_set(&"rain_amount", rain)
	RenderingServer.global_shader_parameter_set(&"wind_strength", 0.25 + wind * 0.9)
	# evening: most windows lit, small hours: few
	var late := smoothstep(22.0, 26.0, hour if hour > 12.0 else hour + 24.0)
	RenderingServer.global_shader_parameter_set(&"window_lit_ratio", lerpf(0.62, 0.2, late))
	var new_night := night > 0.5
	if new_night != is_night or instant:
		is_night = new_night
		night_changed.emit(is_night)
	var hi := int(hour)
	if hi != _last_hour_int:
		_last_hour_int = hi
		Events.hour_changed.emit(hi)
	_update_rain(delta)
	_update_storm(delta)

func _update_rain(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	_indoor_check -= delta
	if _indoor_check <= 0.0:
		_indoor_check = 0.35
		var from := cam.global_position
		var hit := Game.ray(from, from + Vector3.UP * 30.0, Phys.WORLD)
		_indoor = 1.0 if not hit.is_empty() else 0.0
	var amount := rain * (1.0 - _indoor) * (0.0 if _underwater else 1.0)
	rain_fx.emitting = amount > 0.03
	rain_fx.amount_ratio = clampf(amount, 0.05, 1.0)
	rain_fx.global_position = cam.global_position + Vector3(0, 13.0, 0) - cam.global_transform.basis.z * 6.0
	var pm := rain_fx.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0.1 + wind * 0.22, -1.0, 0.06 + wind * 0.1)
	var muffle := lerpf(0.0, -9.0, _indoor)
	_fade_loop(_rain_loop, rain > 0.05 and rain < 0.85, -11.0 + muffle, delta)
	_fade_loop(_rain_heavy, rain >= 0.85, -8.0 + muffle, delta)
	_fade_loop(_wind_loop, wind > 0.45, lerpf(-26.0, -12.0, clampf(wind - 0.4, 0.0, 1.0)), delta)

func _fade_loop(p: AudioStreamPlayer, on: bool, target_db: float, delta: float) -> void:
	if p == null or p.stream == null:
		return
	var goal := target_db if on else -80.0
	p.volume_db = move_toward(p.volume_db, goal, delta * 30.0)
	if p.volume_db > -70.0 and not p.playing:
		p.play()
	elif p.volume_db <= -79.0 and p.playing:
		p.stop()

func _update_storm(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 5.0)
	if float(_wp["storm"]) < 0.5:
		return
	_next_lightning -= delta
	if _next_lightning <= 0.0:
		_next_lightning = randf_range(6.0, 19.0)
		_flash = 1.0
		var delay := randf_range(0.4, 2.2)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			Audio.play_ui(&"thunder_1" if randf() < 0.5 else &"thunder_2", lerpf(-2.0, -12.0, delay / 2.2), randf_range(0.9, 1.1), &"Ambient"))
