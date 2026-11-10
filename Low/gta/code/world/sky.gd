class_name SkySystem
extends Node3D
# Day/night cycle, weather states, environment, rain, lightning, pooled street-lamp lights.

const WEATHERS := {
	"clear": {"cloud": 0.0, "fog": 0.0007, "rain": 0.0, "wind": 0.1},
	"cloudy": {"cloud": 0.55, "fog": 0.0016, "rain": 0.0, "wind": 0.3},
	"rain": {"cloud": 0.8, "fog": 0.004, "rain": 0.7, "wind": 0.5},
	"fog": {"cloud": 0.6, "fog": 0.022, "rain": 0.0, "wind": 0.05},
	"storm": {"cloud": 1.0, "fog": 0.006, "rain": 1.0, "wind": 1.0},
}

var time := 9.5
var time_scale := 1.0 / 60.0   # game hours per real second (24 min day)
var weather := "clear"
var auto_weather := true
var weather_t := 240.0
var cloud := 0.0
var fog := 0.0007
var rain_amount := 0.0
var wind := 0.1
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var rain: GPUParticles3D
var lamps: Array = []
var lamp_t := 0.0
var flash := 0.0
var flash_t := 8.0
var day := 1.0


func _ready() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	sky_mat = ProceduralSkyMaterial.new()
	var sk := Sky.new()
	sk.sky_material = sky_mat
	env.sky = sk
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.ssao_enabled = true
	env.ssao_intensity = 1.2
	env.ssao_radius = 1.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 130.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.06
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.shadow_enabled = false
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.rotation = Vector3(-1.0, 0.8, 0)
	add_child(moon)
	rain = GPUParticles3D.new()
	rain.amount = 1600
	rain.lifetime = 0.7
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.5, 22)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 24.0
	pm.initial_velocity_max = 28.0
	pm.gravity = Vector3(0, -6, 0)
	rain.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.025, 0.7)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.75, 0.82, 0.95, 0.4)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	qm.material = rm
	rain.draw_pass_1 = qm
	rain.emitting = false
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)
	for i in 10:
		var l := OmniLight3D.new()
		l.omni_range = 15.0
		l.light_color = Color(1.0, 0.85, 0.6)
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		lamps.append(l)
	_apply(1.0)


func is_night() -> bool:
	return time < 6.0 or time > 19.6


func grip() -> float:
	return 1.0 - 0.2 * rain_amount


func set_weather(w: String) -> void:
	weather = w
	weather_t = randf_range(200.0, 420.0)


func _process(dt: float) -> void:
	time = fmod(time + dt * time_scale, 24.0)
	if auto_weather:
		weather_t -= dt
		if weather_t <= 0.0:
			var opts := ["clear", "clear", "clear", "cloudy", "cloudy", "rain", "fog", "storm"]
			set_weather(opts[randi() % opts.size()])
	_apply(dt * 0.25)
	# lamp light pool follows the player
	lamp_t -= dt
	if lamp_t <= 0.0 and G.player and G.world:
		lamp_t = 0.6
		var night := 1.0 - day
		if night > 0.3:
			var pp: Vector3 = G.cam.global_position
			var pts: Array = G.world.lamp_points.duplicate()
			pts.sort_custom(func(a, b): return a.distance_squared_to(pp) < b.distance_squared_to(pp))
			for i in lamps.size():
				var l: OmniLight3D = lamps[i]
				if i < pts.size() and pts[i].distance_to(pp) < 90.0:
					l.global_position = pts[i]
					l.light_energy = 2.4 * night
					l.visible = true
				else:
					l.visible = false
		else:
			for l in lamps:
				l.visible = false
	# rain follows camera; lightning
	if G.cam:
		var cp: Vector3 = G.cam.cam.global_position
		rain.global_position = cp + Vector3(0, 13, 0) + (-G.cam.cam.global_basis.z) * 8.0
		rain.emitting = rain_amount > 0.05 and cp.y > G.WATER_Y
		rain.amount_ratio = clamp(rain_amount, 0.05, 1.0)
		if weather == "storm":
			flash_t -= dt
			if flash_t <= 0.0:
				flash_t = randf_range(5.0, 14.0)
				flash = 1.0
				G.audio.ui("thunder")
		flash = max(0.0, flash - dt * 3.0)
		# underwater look
		if cp.y < G.WATER_Y:
			env.fog_density = 0.07
			env.fog_light_color = Color(0.05, 0.3, 0.4)
			env.ambient_light_color = Color(0.2, 0.5, 0.6)


func _apply(k: float) -> void:
	k = clamp(k, 0.0, 1.0)
	var w: Dictionary = WEATHERS[weather]
	cloud = lerp(cloud, w.cloud, k)
	fog = lerp(fog, w.fog, k)
	rain_amount = lerp(rain_amount, w.rain, k)
	wind = lerp(wind, w.wind, k)
	var ang := (time - 6.0) / 13.6 * PI
	var elev := sin(ang)
	day = clamp(elev * 4.0 + 0.15, 0.0, 1.0)
	var dusk: float = clamp(1.0 - abs(elev) * 4.0, 0.0, 1.0) * (1.0 if (time > 4.5 and time < 21.0) else 0.0)
	sun.rotation = Vector3(-clamp(ang, 0.05, PI - 0.05), -0.6, 0)
	var sun_col := Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.55, 0.3), dusk)
	sun.light_color = sun_col
	sun.light_energy = 1.35 * day * (1.0 - 0.65 * cloud) + flash * 2.0
	sun.visible = sun.light_energy > 0.02
	moon.light_energy = 0.32 * (1.0 - day) * (1.0 - 0.5 * cloud)
	moon.visible = moon.light_energy > 0.01
	var grey := Color(0.5, 0.53, 0.57)
	var top := Color(0.012, 0.018, 0.045).lerp(Color(0.2, 0.42, 0.85), day)
	var hor := Color(0.03, 0.04, 0.08).lerp(Color(0.66, 0.8, 0.95), day).lerp(Color(1.0, 0.55, 0.3), dusk * 0.7)
	top = top.lerp(grey * (0.15 + 0.6 * day), cloud * 0.85)
	hor = hor.lerp(grey * (0.2 + 0.8 * day), cloud * 0.8)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = hor.darkened(0.4)
	sky_mat.sun_angle_max = 6.0
	env.ambient_light_color = hor.lerp(Color(1, 1, 1), 0.3)
	env.ambient_light_energy = 0.24 + 0.54 * day + flash
	env.fog_density = fog
	env.fog_light_color = hor
	env.fog_light_energy = 0.3 + 0.7 * day
	var night := 1.0 - day
	G.shared_mats["WinLit"].emission_energy_multiplier = 2.4 * night
	G.shared_mats["LampGlow"].emission_energy_multiplier = 5.0 * night
	if G.world and G.world.mat_road:
		G.world.mat_road.roughness = lerp(0.85, 0.22, rain_amount)
		G.world.mat_road.metallic = 0.35 * rain_amount
		G.world.mat_slab.roughness = lerp(0.9, 0.4, rain_amount)


func time_text() -> String:
	return "%02d:%02d" % [int(time), int(fmod(time, 1.0) * 60.0)]
