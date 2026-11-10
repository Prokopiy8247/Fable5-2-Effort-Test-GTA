class_name DayNight
extends Node3D
## Time of day, stylised sky shader, sun/moon light, weather states, rain, lightning, pooled street-lamp lights.

const SKY_SHADER := """
shader_type sky;
uniform vec3 top_color : source_color = vec3(0.2, 0.5, 0.9);
uniform vec3 horizon_color : source_color = vec3(0.65, 0.8, 0.95);
uniform vec3 ground_color : source_color = vec3(0.1, 0.2, 0.28);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float star_amount = 0.0;
uniform float cloud_cover = 0.3;
uniform float disc_size = 0.04;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.55 + vnoise(p * 2.1) * 0.28 + vnoise(p * 4.3) * 0.17; }
void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55));
	if (h < 0.0) { col = mix(horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0)); }
	if (LIGHT0_ENABLED) {
		float sd = distance(dir, LIGHT0_DIRECTION);
		col += sun_color * smoothstep(disc_size, disc_size * 0.8, sd) * 3.0;
		col += sun_color * pow(max(dot(dir, LIGHT0_DIRECTION), 0.0), 28.0) * 0.4;
	}
	if (h > 0.0 && star_amount > 0.01) {
		vec2 sp = dir.xz / (h + 0.35) * 150.0;
		vec2 cell = floor(sp);
		float tw = hash(cell + 7.0);
		float s = step(0.992, hash(cell)) * step(length(fract(sp) - 0.5), 0.2 + 0.2 * tw);
		col += vec3(s) * (0.5 + 0.5 * tw) * star_amount * smoothstep(0.0, 0.2, h);
	}
	if (h > 0.01) {
		vec2 cp = dir.xz / (h + 0.18) * 1.5 + vec2(TIME * 0.008, TIME * 0.003);
		float c = fbm(cp);
		float m = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.2, c) * smoothstep(0.01, 0.16, h);
		float shade = smoothstep(1.0 - cloud_cover + 0.1, 1.0 - cloud_cover + 0.5, c);
		col = mix(col, cloud_color * (1.0 - shade * 0.25), m * 0.92);
	}
	COLOR = col;
}
"""

const WEATHERS := {
	"clear": {"cloud": 0.28, "fog": 0.0006, "rain": 0.0, "dim": 0.0, "wet": 0.0, "wind": 0.2},
	"cloudy": {"cloud": 0.72, "fog": 0.0012, "rain": 0.0, "dim": 0.35, "wet": 0.0, "wind": 0.4},
	"rain": {"cloud": 0.9, "fog": 0.003, "rain": 0.7, "dim": 0.5, "wet": 1.0, "wind": 0.5},
	"fog": {"cloud": 0.6, "fog": 0.018, "rain": 0.0, "dim": 0.35, "wet": 0.2, "wind": 0.1},
	"storm": {"cloud": 1.0, "fog": 0.005, "rain": 1.0, "dim": 0.68, "wet": 1.0, "wind": 1.0},
}

var hour := 9.5
var minutes_per_second := 1.0
var paused_time := false
var weather := "clear"
var auto_weather := true
var _w := {"cloud": 0.28, "fog": 0.0006, "rain": 0.0, "dim": 0.0, "wet": 0.0, "wind": 0.2}
var _weather_timer := 240.0
var night := 0.0
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var rain: GPUParticles3D
var lamp_bulbs: PackedVector3Array = PackedVector3Array()
var _lamps: Array[OmniLight3D] = []
var _lamp_timer := 0.0
var _flash := 0.0
var _flash_timer := 6.0
var underwater := false


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 1.2
	add_child(sun)
	env = Environment.new()
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat.shader = sh
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.3
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.5
	env.tonemap_exposure = 0.92
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_density = 0.0006
	env.fog_aerial_perspective = 0.45
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_make_rain()
	for i in range(14):
		var l := OmniLight3D.new()
		l.omni_range = 24.0
		l.light_energy = 0.0
		l.light_color = Color(1.0, 0.86, 0.6)
		l.shadow_enabled = false
		l.omni_attenuation = 0.9
		add_child(l)
		_lamps.append(l)
	_apply(0.0)


func _make_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 1400
	rain.lifetime = 0.7
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	rain.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3(0.12, -1, 0.05)
	pm.spread = 2.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 32.0
	pm.gravity = Vector3(0, -6, 0)
	rain.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.025, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.8, 0.88, 1.0, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	qm.material = m
	rain.draw_pass_1 = qm
	rain.emitting = false
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)


func set_weather(w: String, instant: bool = false) -> void:
	if not WEATHERS.has(w):
		return
	weather = w
	if instant:
		_w = WEATHERS[w].duplicate()
	_weather_timer = Game.rng.randf_range(200.0, 420.0)


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	_apply(0.0)


func grip_factor() -> float:
	return 1.0 - 0.2 * _w.wet


func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]


func _process(delta: float) -> void:
	if not paused_time:
		hour = fposmod(hour + delta * minutes_per_second / 60.0, 24.0)
	if auto_weather:
		_weather_timer -= delta
		if _weather_timer <= 0.0:
			var opts := ["clear", "clear", "clear", "cloudy", "cloudy", "rain", "fog", "storm"]
			set_weather(opts[Game.rng.randi() % opts.size()])
	var target: Dictionary = WEATHERS[weather]
	for k in _w:
		_w[k] = move_toward(_w[k], target[k], delta * (0.12 if k != "fog" else 0.002))
	_apply(delta)


func _apply(delta: float) -> void:
	var d := (hour - 6.0) / 12.0
	var e := sin(d * PI)                    # sun elevation proxy (-1..1)
	var dayness := smoothstep(-0.08, 0.3, e)
	var dusk := clampf(1.0 - absf(e) / 0.32, 0.0, 1.0)
	night = 1.0 - smoothstep(-0.2, 0.06, e)
	var dim: float = _w.dim
	# light direction
	var sun_v := Vector3(cos(d * PI), maxf(e, -0.2), 0.42).normalized()
	var is_moon := e < -0.02
	if is_moon:
		var dm := (fposmod(hour - 18.0, 24.0)) / 12.0
		sun_v = Vector3(cos(dm * PI) * 0.8, 0.35 + sin(dm * PI) * 0.6, -0.45).normalized()
	sun.look_at_from_position(sun_v * 200.0, Vector3.ZERO, Vector3.UP)
	var day_col := Color(1.0, 0.96, 0.88)
	var dusk_col := Color(1.0, 0.62, 0.36)
	var moon_col := Color(0.55, 0.68, 1.0)
	var base_e := 1.2
	if is_moon:
		sun.light_color = moon_col
		sun.light_energy = 0.5 * (1.0 - dim * 0.6)
	else:
		sun.light_color = day_col.lerp(dusk_col, dusk)
		sun.light_energy = base_e * smoothstep(-0.02, 0.25, e) * (1.0 - dim * 0.75) + 0.05
	sun.light_energy += _flash * 3.0
	sun.shadow_enabled = Game.settings.shadows
	# sky colours
	var top := Color(0.02, 0.035, 0.09).lerp(Color(0.2, 0.47, 0.9), dayness)
	var hor := Color(0.07, 0.11, 0.2).lerp(Color(0.66, 0.83, 0.96), dayness)
	top = top.lerp(Color(0.22, 0.24, 0.52), dusk * 0.7)
	hor = hor.lerp(Color(1.0, 0.56, 0.32), dusk * 0.85)
	var grey := Color(0.42, 0.45, 0.5) * (0.25 + 0.75 * dayness)
	top = top.lerp(grey * 0.8, dim)
	hor = hor.lerp(grey, dim)
	top += Color(0.5, 0.5, 0.6) * _flash
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("ground_color", hor.darkened(0.6))
	sky_mat.set_shader_parameter("sun_color", (moon_col * 0.7) if is_moon else day_col.lerp(dusk_col, dusk) * (1.0 - dim))
	sky_mat.set_shader_parameter("disc_size", 0.03 if is_moon else 0.045)
	sky_mat.set_shader_parameter("star_amount", night * (1.0 - _w.cloud * 0.9))
	sky_mat.set_shader_parameter("cloud_cover", _w.cloud)
	var cc := Color(1, 1, 1).lerp(Color(0.5, 0.52, 0.56), dim) * (0.12 + 0.88 * dayness)
	cc = cc.lerp(Color(1.0, 0.7, 0.55) * 0.9, dusk * 0.6 * (1.0 - dim))
	sky_mat.set_shader_parameter("cloud_color", cc)
	env.ambient_light_color = hor.lerp(Color(0.95, 0.9, 0.82), 0.55 * dayness).lerp(Color(0.25, 0.3, 0.45), night * 0.6)
	env.ambient_light_energy = lerpf(1.1, 0.85, dayness) + _flash
	if underwater:
		env.fog_density = 0.085
		env.fog_light_color = Color(0.04, 0.26, 0.36) * (0.25 + 0.75 * dayness)
		env.fog_sky_affect = 1.0
	else:
		env.fog_sky_affect = 0.25
		env.fog_density = _w.fog
		env.fog_light_color = hor.lerp(Color(0.6, 0.63, 0.68) * (0.2 + 0.8 * dayness), 0.5)
	Assets.set_night(night)
	RenderingServer.global_shader_parameter_set("wetness", _w.wet)
	# rain + lightning
	var cam := get_viewport().get_camera_3d()
	if cam:
		rain.global_position = cam.global_position + Vector3(0, 14, 0) - cam.global_transform.basis.z * 8.0
	rain.emitting = _w.rain > 0.05 and not underwater
	rain.amount_ratio = clampf(_w.rain, 0.05, 1.0)
	if delta > 0.0:
		_flash = move_toward(_flash, 0.0, delta * 5.0)
		if weather == "storm" and _w.rain > 0.8:
			_flash_timer -= delta
			if _flash_timer <= 0.0:
				_flash_timer = Game.rng.randf_range(5.0, 14.0)
				_flash = 1.0
				Sfx.play("thunder", -3.0, Game.rng.randf_range(0.8, 1.1))
		_lamp_timer -= delta
		if _lamp_timer <= 0.0:
			_lamp_timer = 0.4
			_update_lamps(cam)
	if Game.world and Game.world.ground and Game.world.ground.water_mat:
		Game.world.ground.water_mat.set_shader_parameter("storm", _w.wind)
		var wm: ShaderMaterial = Game.world.ground.water_mat
		wm.set_shader_parameter("shallow", Color(0.16, 0.62, 0.66).lerp(Color(0.03, 0.1, 0.16), night * 0.85).lerp(Color(0.3, 0.38, 0.42), dim * 0.6))
		wm.set_shader_parameter("deep", Color(0.03, 0.2, 0.34).lerp(Color(0.01, 0.03, 0.07), night * 0.9))


func _update_lamps(cam: Camera3D) -> void:
	if cam == null or night < 0.05 or lamp_bulbs.is_empty():
		for l in _lamps:
			l.light_energy = 0.0
		return
	var cp := cam.global_position - cam.global_transform.basis.z * 12.0
	var best: Array = []
	for p in lamp_bulbs:
		var dd := p.distance_squared_to(cp)
		if dd < 70.0 * 70.0:
			best.append([dd, p])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for i in range(_lamps.size()):
		if i < best.size():
			_lamps[i].global_position = best[i][1] + Vector3(0, -0.4, 0)
			_lamps[i].light_energy = 5.0 * night
		else:
			_lamps[i].light_energy = 0.0
