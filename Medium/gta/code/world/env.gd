extends Node3D
## Day/night cycle, weather states, street-light pool, underwater presentation.

const WEATHERS := {
	"clear": {"cloud": 0.0, "fog": 0.0006, "rain": 0.0, "sun": 1.0, "wet": 0.0},
	"cloudy": {"cloud": 0.7, "fog": 0.0012, "rain": 0.0, "sun": 0.55, "wet": 0.0},
	"rain": {"cloud": 0.9, "fog": 0.004, "rain": 0.6, "sun": 0.35, "wet": 1.0},
	"fog": {"cloud": 0.6, "fog": 0.022, "rain": 0.0, "sun": 0.4, "wet": 0.2},
	"storm": {"cloud": 1.0, "fog": 0.006, "rain": 1.0, "sun": 0.2, "wet": 1.0},
}

var hour := 9.5
var day_minutes := 24.0          # real minutes per in-game day
var paused_clock := false
var night := 0.0
var weather := "clear"
var w := {"cloud": 0.0, "fog": 0.0006, "rain": 0.0, "sun": 1.0, "wet": 0.0}
var auto_weather := true
var _wtimer := 240.0
var sun: DirectionalLight3D
var we: WorldEnvironment
var envr: Environment
var sky: ProceduralSkyMaterial
var rain: GPUParticles3D
var lamp_pool: Array = []
var _lamp_t := 0.0
var _flash := 0.0
var _thunder_t := 8.0
var underwater := false


func _ready() -> void:
	RenderingServer.global_shader_parameter_add("night_amount", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.shadow_bias = 0.06
	add_child(sun)
	we = WorldEnvironment.new()
	envr = Environment.new()
	sky = ProceduralSkyMaterial.new()
	var s = Sky.new()
	s.sky_material = sky
	s.radiance_size = Sky.RADIANCE_SIZE_64
	s.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	envr.background_mode = Environment.BG_SKY
	envr.sky = s
	envr.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	envr.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	envr.tonemap_white = 6.0
	envr.ssao_enabled = true
	envr.ssao_radius = 1.2
	envr.ssao_intensity = 1.6
	envr.glow_enabled = true
	envr.glow_intensity = 0.5
	envr.glow_bloom = 0.05
	envr.glow_hdr_threshold = 1.1
	envr.fog_enabled = true
	envr.fog_aerial_perspective = 0.5
	envr.fog_sky_affect = 0.3
	we.environment = envr
	add_child(we)
	# rain
	rain = GPUParticles3D.new()
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.5, 22)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 32.0
	pm.gravity = Vector3(0, -6, 0)
	rain.process_material = pm
	var qm = QuadMesh.new()
	qm.size = Vector2(0.025, 0.7)
	var rm = StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.75, 0.82, 0.95, 0.4)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	qm.material = rm
	rain.draw_pass_1 = qm
	rain.amount = 1400
	rain.lifetime = 0.7
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	rain.emitting = false
	add_child(rain)
	for i in 10:
		var l = OmniLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.6)
		l.omni_range = 24.0
		l.omni_attenuation = 0.7
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		lamp_pool.append(l)
	_apply(0.0)


func set_weather(name: String, instant := false) -> void:
	if not WEATHERS.has(name):
		return
	weather = name
	_wtimer = 300.0
	if instant:
		w = WEATHERS[name].duplicate()
	if G.hud:
		G.hud.notify("Weather: " + name.capitalize(), 2.0)


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	_apply(0.0)


func grip_factor() -> float:
	return 1.0 - 0.28 * w.wet


func _process(dt: float) -> void:
	if not paused_clock:
		hour = fposmod(hour + dt * 24.0 / (day_minutes * 60.0), 24.0)
	var target: Dictionary = WEATHERS[weather]
	for k in w:
		w[k] = lerpf(w[k], target[k], clamp(dt * 0.35, 0.0, 1.0))
	if auto_weather:
		_wtimer -= dt
		if _wtimer <= 0.0:
			var opts = ["clear", "clear", "clear", "cloudy", "cloudy", "rain", "fog", "storm"]
			set_weather(opts[G.rng.randi() % opts.size()])
			_wtimer = G.rng.randf_range(180, 420)
	_apply(dt)


func _apply(dt: float) -> void:
	var ang = (hour - 6.0) / 24.0 * TAU
	var elev = sin(ang)
	var dir = Vector3(cos(ang), elev, 0.35).normalized()   # direction TO the sun
	night = clamp(smoothstep(0.12, -0.12, elev), 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("night_amount", night)
	var dusk: float = clamp(1.0 - abs(elev) / 0.3, 0.0, 1.0) * (1.0 - night * 0.5)
	var light_dir = dir if elev > -0.05 else Vector3(-dir.x, -dir.y, 0.35).normalized()
	if abs(light_dir.y) > 0.99:
		light_dir = Vector3(0.05, light_dir.y, 0.05).normalized()
	sun.look_at_from_position(light_dir * 100.0, Vector3.ZERO, Vector3.UP)
	var day_col = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.6, 0.35), dusk)
	sun.light_color = day_col.lerp(Color(0.55, 0.65, 1.0), night)
	_flash = max(0.0, _flash - dt * 4.0)
	sun.light_energy = lerpf(1.25 * w.sun * clamp(elev * 4.0 + 0.2, 0.0, 1.0), 0.16, night) + _flash * 2.0
	var top = Color(0.2, 0.44, 0.85).lerp(Color(0.16, 0.2, 0.42), dusk).lerp(Color(0.012, 0.016, 0.04), night)
	var hor = Color(0.62, 0.8, 0.95).lerp(Color(1.0, 0.58, 0.32), dusk).lerp(Color(0.04, 0.06, 0.12), night)
	var grey = Color(0.45, 0.48, 0.52).lerp(Color(0.03, 0.035, 0.05), night)
	top = top.lerp(grey * 0.8, w.cloud)
	hor = hor.lerp(grey, w.cloud * 0.9)
	sky.sky_top_color = top
	sky.sky_horizon_color = hor
	sky.ground_horizon_color = hor
	sky.ground_bottom_color = hor.darkened(0.4)
	sky.sun_angle_max = 12.0
	sky.sky_energy_multiplier = 1.0 + _flash
	envr.ambient_light_energy = lerpf(0.85, 1.0, night)
	envr.ambient_light_sky_contribution = lerpf(0.35, 0.2, night)
	envr.ambient_light_color = Color(0.62, 0.64, 0.68).lerp(Color(0.16, 0.2, 0.34), night)
	envr.fog_light_color = hor.lerp(Color(0.6, 0.65, 0.7), w.cloud * 0.5)
	envr.fog_density = w.fog
	if underwater:
		envr.fog_light_color = Color(0.03, 0.25, 0.35).lerp(Color(0.0, 0.03, 0.06), night)
		envr.fog_density = 0.07
	rain.emitting = w.rain > 0.08 and not underwater
	rain.amount_ratio = clamp(w.rain, 0.05, 1.0)
	var cam = get_viewport().get_camera_3d()
	if cam:
		rain.global_position = cam.global_position + Vector3(0, 14, 0) - cam.global_basis.z * 8.0
		underwater = cam.global_position.y < G.WATER_Y - 0.05 and G.world != null and G.world.is_sea(cam.global_position.x, cam.global_position.z)
	if weather == "storm" and dt > 0.0:
		_thunder_t -= dt
		if _thunder_t <= 0.0:
			_thunder_t = G.rng.randf_range(6, 16)
			_flash = 1.0
			if G.audio:
				G.audio.play("thunder", -4.0)
	_lamp_t -= dt
	if _lamp_t <= 0.0 and cam and G.world:
		_lamp_t = 0.5
		_update_lamps(cam.global_position)


func _update_lamps(cp: Vector3) -> void:
	if night < 0.3:
		for l in lamp_pool:
			l.light_energy = 0.0
		return
	var near = []
	for p in G.world.lamps:
		var d: float = p.distance_squared_to(cp)
		if d < 90.0 * 90.0:
			near.append([d, p])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in lamp_pool.size():
		if i < near.size():
			lamp_pool[i].global_position = near[i][1] - Vector3(0, 0.6, 0)
			lamp_pool[i].light_energy = 5.0 * night
		else:
			lamp_pool[i].light_energy = 0.0


func time_string() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]
