class_name TimeWeather
extends Node3D
## Day/night cycle, weather states, sky, fog, rain, lightning, street-light pool and global shader parameters.

const WEATHERS := {
	"clear": {"cloud": 0.22, "fog": 0.0005, "rain": 0.0, "wet": 0.0, "sun": 1.0, "wind": 1.0, "storm": 0.0, "grey": 0.0},
	"cloudy": {"cloud": 0.78, "fog": 0.0011, "rain": 0.0, "wet": 0.0, "sun": 0.55, "wind": 1.3, "storm": 0.1, "grey": 0.45},
	"rain": {"cloud": 0.97, "fog": 0.0035, "rain": 1.0, "wet": 1.0, "sun": 0.32, "wind": 1.6, "storm": 0.35, "grey": 0.75},
	"fog": {"cloud": 0.6, "fog": 0.018, "rain": 0.0, "wet": 0.25, "sun": 0.45, "wind": 0.6, "storm": 0.0, "grey": 0.65},
	"storm": {"cloud": 1.0, "fog": 0.0055, "rain": 1.7, "wet": 1.0, "sun": 0.2, "wind": 2.6, "storm": 1.0, "grey": 0.9},
}
const WEATHER_ORDER := ["clear", "cloudy", "rain", "fog", "storm"]

var time := 9.5
var minutes_per_second := 1.0
var paused_time := false
var weather := "clear"
var cur := {}
var night := 0.0
var wetness := 0.0
var wind_time := 0.0
var underwater := false
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var rain: GPUParticles3D
var rain_mat: ParticleProcessMaterial
var lamp_lights: Array = []
var _lamp_timer := 0.0
var _weather_timer := 240.0
var _flash := 0.0
var _flash_timer := 6.0
var auto_weather := true


func _ready() -> void:
	cur = WEATHERS["clear"].duplicate()
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 170.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.4
	sun.light_angular_distance = 0.6
	add_child(sun)
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = Assets.shader("sky")
	if G.world:
		sky_mat.set_shader_parameter("noise_tex", G.world.noise_tex)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.15
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_make_rain()
	for i in 12:
		var l := OmniLight3D.new()
		l.omni_range = 15.0
		l.light_energy = 0.0
		l.light_color = Color(1.0, 0.86, 0.6)
		l.shadow_enabled = false
		l.omni_attenuation = 1.3
		l.visible = false
		add_child(l)
		lamp_lights.append(l)
	_apply(0.0)


func _make_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 2600
	rain.lifetime = 0.75
	rain.emitting = false
	rain.local_coords = false
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	rain_mat = ParticleProcessMaterial.new()
	rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rain_mat.emission_box_extents = Vector3(24, 0.5, 24)
	rain_mat.direction = Vector3(0.12, -1, 0.05)
	rain_mat.spread = 2.5
	rain_mat.initial_velocity_min = 22.0
	rain_mat.initial_velocity_max = 28.0
	rain_mat.gravity = Vector3.ZERO
	rain.process_material = rain_mat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.025, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.88, 1.0, 0.32)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.material = m
	rain.draw_pass_1 = qm
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)


func set_time(h: float) -> void:
	time = fposmod(h, 24.0)
	_apply(0.0)


func set_weather(w: String, instant: bool = false) -> void:
	if not WEATHERS.has(w):
		return
	weather = w
	_weather_timer = randf_range(200.0, 420.0)
	if instant:
		cur = WEATHERS[w].duplicate()
		wetness = cur.wet
		_apply(0.0)


func next_weather() -> void:
	set_weather(WEATHER_ORDER[(WEATHER_ORDER.find(weather) + 1) % WEATHER_ORDER.size()])


func is_night() -> bool:
	return night > 0.5


func grip_factor() -> float:
	return 1.0 - 0.22 * wetness


func time_string() -> String:
	var h := int(time)
	var m := int((time - h) * 60.0)
	return "%02d:%02d" % [h, m]


func _process(delta: float) -> void:
	if not paused_time:
		time = fposmod(time + delta * minutes_per_second / 60.0, 24.0)
	var tgt: Dictionary = WEATHERS[weather]
	for k in tgt.keys():
		cur[k] = lerpf(cur[k], tgt[k], clampf(delta * 0.3, 0.0, 1.0))
	wetness = move_toward(wetness, cur.wet, delta * (0.06 if cur.wet > wetness else 0.02))
	wind_time += delta * cur.wind
	if auto_weather:
		_weather_timer -= delta
		if _weather_timer <= 0.0:
			var r := randf()
			set_weather("clear" if r < 0.45 else ("cloudy" if r < 0.70 else ("rain" if r < 0.86 else ("fog" if r < 0.93 else "storm"))))
	if cur.storm > 0.7:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_timer = randf_range(4.0, 13.0)
			_flash = 1.0
			if Sfx:
				get_tree().create_timer(randf_range(0.4, 1.8)).timeout.connect(func(): Sfx.play("thunder", null, -4.0, randf_range(0.8, 1.1)))
	_flash = move_toward(_flash, 0.0, delta * 5.0)
	_apply(delta)


func _apply(delta: float) -> void:
	var ang := (time - 6.0) / 12.0 * PI
	var elev := sin(ang)
	night = smoothstep(0.10, -0.12, elev)
	var day := 1.0 - night
	var low := clampf(1.0 - absf(elev) * 3.2, 0.0, 1.0) * (1.0 - smoothstep(0.0, -0.2, elev))
	var sp := Vector3(cos(ang), elev, 0.42).normalized()
	var is_moon := elev < -0.02
	if is_moon:
		var ma := ang - PI
		sp = Vector3(cos(ma), maxf(sin(ma), 0.25), -0.35).normalized()
	sun.look_at_from_position(sp * 200.0, Vector3.ZERO, Vector3.UP)
	var grey: float = cur.grey
	var sun_e: float = clampf(elev * 4.0, 0.0, 1.0) * 1.35 * cur.sun
	var top := Color(0.14, 0.40, 0.84).lerp(Color(0.24, 0.22, 0.46), low).lerp(Color(0.006, 0.012, 0.035), night)
	var hor := Color(0.62, 0.80, 0.96).lerp(Color(1.0, 0.52, 0.28), low).lerp(Color(0.03, 0.05, 0.11), night)
	var grey_c := Color(0.52, 0.56, 0.60) * (0.25 + 0.75 * day)
	top = top.lerp(grey_c * 0.8, grey * 0.85)
	hor = hor.lerp(grey_c, grey * 0.85)
	var sun_c := Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.56, 0.30), low)
	if is_moon:
		sun.light_color = Color(0.55, 0.68, 1.0)
		sun.light_energy = 0.16 * (1.0 - grey * 0.6) * smoothstep(-0.02, -0.15, elev) + _flash * 2.5
	else:
		sun.light_color = sun_c
		sun.light_energy = sun_e + _flash * 2.5
	sun.shadow_enabled = G.settings.shadows
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("ground_color", hor * 0.55)
	sky_mat.set_shader_parameter("sun_color", (Color(0.8, 0.86, 1.0) * 0.6) if is_moon else sun_c * (1.0 - grey * 0.8))
	sky_mat.set_shader_parameter("sun_size", 0.03 if is_moon else 0.042)
	sky_mat.set_shader_parameter("cloud_cover", cur.cloud)
	sky_mat.set_shader_parameter("star_vis", night * (1.0 - cur.cloud * 0.9))
	sky_mat.set_shader_parameter("cloud_light", Color(1, 1, 1).lerp(Color(1.0, 0.7, 0.5), low).lerp(Color(0.10, 0.12, 0.18), night).lerp(grey_c, grey * 0.6) + Color(_flash, _flash, _flash))
	sky_mat.set_shader_parameter("cloud_dark", Color(0.62, 0.66, 0.76).lerp(Color(0.5, 0.35, 0.4), low).lerp(Color(0.03, 0.04, 0.07), night).lerp(grey_c * 0.55, grey * 0.8))
	env.ambient_light_energy = lerpf(1.0, 0.55, night) + _flash
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_exposure = lerpf(1.0, 1.35, night)
	if underwater:
		env.fog_density = 0.07
		env.fog_light_color = Color(0.04, 0.26, 0.34)
		env.fog_sky_affect = 1.0
	else:
		env.fog_density = cur.fog
		env.fog_light_color = hor.lerp(Color(0.6, 0.64, 0.68) * (0.2 + 0.8 * day), grey * 0.7)
		env.fog_sky_affect = clampf(cur.fog * 40.0, 0.15, 0.9)
	RenderingServer.global_shader_parameter_set("night_factor", night)
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	RenderingServer.global_shader_parameter_set("wind_time", wind_time)
	if Assets.mats.has("LampGlow"):
		var lg: StandardMaterial3D = Assets.mats["LampGlow"]
		lg.emission_enabled = true
		lg.emission_energy_multiplier = 0.05 + night * 4.5
	if G.world and G.world.water_mat:
		G.world.water_mat.set_shader_parameter("storm", cur.storm)
		G.world.water_mat.set_shader_parameter("shallow", Color(0.18, 0.66, 0.68).lerp(Color(0.02, 0.06, 0.10), night * 0.92).lerp(grey_c * 0.6, grey * 0.5))
		G.world.water_mat.set_shader_parameter("deep", Color(0.03, 0.22, 0.38).lerp(Color(0.005, 0.02, 0.05), night * 0.92))
	# rain follows the camera
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		underwater = cam.global_position.y < WorldLayout.WATER - 0.05
		var r: float = cur.rain
		rain.emitting = r > 0.05 and not underwater
		if rain.emitting:
			rain.global_position = cam.global_position + Vector3(0, 13.0, 0) - cam.global_transform.basis.z * 8.0
			rain.amount_ratio = clampf(r / 1.7, 0.05, 1.0)
			rain_mat.direction = Vector3(0.10 + 0.12 * cur.storm, -1, 0.05)
		_lamp_timer -= delta
		if _lamp_timer <= 0.0:
			_lamp_timer = 0.4
			_update_lamps(cam.global_position)


func _update_lamps(cp: Vector3) -> void:
	if night < 0.25 or G.world == null:
		for l in lamp_lights:
			l.visible = false
		return
	var lamps: PackedVector3Array = G.world.lamps
	var best: Array = []
	for p in lamps:
		var d := p.distance_squared_to(cp)
		if d < 85.0 * 85.0:
			best.append([d, p])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for i in lamp_lights.size():
		var l: OmniLight3D = lamp_lights[i]
		if i < best.size():
			l.visible = true
			l.global_position = best[i][1] - Vector3(0, 0.5, 0)
			l.light_energy = 2.6 * night
		else:
			l.visible = false
