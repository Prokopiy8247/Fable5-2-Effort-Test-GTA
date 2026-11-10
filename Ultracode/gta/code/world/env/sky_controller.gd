class_name SkyController
extends Node3D
## ENVIRONMENT module helper: owns the DirectionalLight3D (sun by day, dim cool moon at night)
## and the WorldEnvironment (procedural sky shader, sky ambient, filmic tonemap, moderate glow,
## moderate SSAO, depth fog). Created and driven by EnvironmentSystem - do not instantiate it
## from other modules; talk to Game.get_system("environment") instead.
##
## The whole look is a pure function of (WorldClock.hour, Weather parameters, underwater state):
## `update_look()` recomputes it every frame, so admin-menu time / weather changes are instant.
## Colour keys are indexed by the sine of the sun elevation, which makes dawn and dusk symmetric.

const SKY_SHADER: Shader = preload("res://gta/code/world/shaders/env_sky.gdshader")

## Sine of the sun elevation for each colour key (night .. twilight .. horizon .. golden .. noon).
const KEYS: Array[float] = [-0.30, -0.12, -0.02, 0.07, 0.22, 0.55, 1.0]
const SKY_TOP: Array[Color] = [
	Color(0.028, 0.052, 0.140), Color(0.070, 0.095, 0.260), Color(0.180, 0.240, 0.520),
	Color(0.230, 0.390, 0.740), Color(0.170, 0.430, 0.850), Color(0.135, 0.395, 0.850),
	Color(0.115, 0.365, 0.840)]
const SKY_HORIZON: Array[Color] = [
	Color(0.075, 0.125, 0.260), Color(0.400, 0.255, 0.365), Color(1.000, 0.520, 0.270),
	Color(0.990, 0.745, 0.510), Color(0.720, 0.860, 0.955), Color(0.650, 0.835, 0.960),
	Color(0.610, 0.815, 0.960)]
const SUN_LIGHT: Array[Color] = [
	Color(1.00, 0.46, 0.20), Color(1.00, 0.46, 0.20), Color(1.00, 0.46, 0.20),
	Color(1.00, 0.70, 0.42), Color(1.00, 0.90, 0.74), Color(1.00, 0.95, 0.84),
	Color(1.00, 0.96, 0.86)]
const SUN_ENERGY: Array[float] = [0.0, 0.0, 0.0, 0.72, 0.96, 1.03, 1.06]
const AMBIENT: Array[Color] = [
	Color(0.215, 0.290, 0.530), Color(0.340, 0.320, 0.520), Color(0.600, 0.480, 0.520),
	Color(0.700, 0.640, 0.670), Color(0.640, 0.750, 0.920), Color(0.620, 0.750, 0.950),
	Color(0.620, 0.750, 0.950)]
const AMBIENT_ENERGY: Array[float] = [0.72, 0.66, 0.60, 0.56, 0.52, 0.52, 0.52]
const SUN_DISC: Array[Color] = [
	Color(1.00, 0.30, 0.10), Color(1.00, 0.30, 0.10), Color(1.00, 0.34, 0.11),
	Color(1.00, 0.46, 0.16), Color(1.00, 0.93, 0.78), Color(1.00, 0.97, 0.88),
	Color(1.00, 0.98, 0.90)]
const CLOUD_LIT: Array[Color] = [
	Color(0.150, 0.185, 0.300), Color(0.470, 0.360, 0.470), Color(1.000, 0.640, 0.430),
	Color(1.000, 0.840, 0.660), Color(1.000, 0.985, 0.960), Color(1.000, 1.000, 1.000),
	Color(1.000, 1.000, 1.000)]
const CLOUD_DARK: Array[Color] = [
	Color(0.040, 0.052, 0.105), Color(0.165, 0.150, 0.280), Color(0.420, 0.300, 0.430),
	Color(0.540, 0.460, 0.560), Color(0.600, 0.680, 0.800), Color(0.630, 0.710, 0.830),
	Color(0.640, 0.720, 0.840)]

const MOON_LIGHT_COLOR := Color(0.56, 0.69, 1.0)
const MOON_LIGHT_ENERGY := 0.30
const MIN_LIGHT_ELEVATION := 0.16     ## sine; keeps shadows from stretching to infinity
const BASE_FOG_DENSITY := 0.00022
const FOG_WEATHER_DENSITY := 0.0105   ## extra density at Weather.fog_amount = 1 (~45 % left at 75 m)
const UNDERWATER_FOG_DENSITY := 0.042

var sun_light: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_material: ShaderMaterial

# --- derived state (recomputed by update_look, read by the other environment helpers) ------
var daylight: float = 1.0          ## WorldClock.get_daylight()
var night: float = 0.0             ## 1 - daylight
var day_factor: float = 1.0        ## 0 night .. 1 day, from the real sun elevation
var sun_dir := Vector3(0.3, 0.8, 0.5)
var moon_dir := Vector3(-0.3, 0.7, -0.4)
var sun_elevation: float = 0.8
var light_dir := Vector3(0.3, 0.8, 0.5)       ## direction TO the active light (sun or moon)
var light_color := Color(1, 1, 1)
var light_energy: float = 1.3
var moon_is_key: bool = false
var sky_top := Color(0.12, 0.37, 0.84)
var sky_horizon := Color(0.61, 0.82, 0.96)
var fog_color := Color(0.61, 0.82, 0.96)
var fog_density: float = BASE_FOG_DENSITY
var ambient_color := Color(0.62, 0.75, 0.95)
var ambient_energy: float = 0.9
var overcast: float = 0.0

var _cloud_offset := Vector2.ZERO
var _applied_light_dir := Vector3.ZERO
var _shadow_level: int = -1


func _ready() -> void:
	_build()


func _build() -> void:
	if sun_light != null:
		return
	sun_light = DirectionalLight3D.new()
	sun_light.name = "Sun"
	sun_light.light_bake_mode = Light3D.BAKE_DISABLED
	sun_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun_light.light_angular_distance = 0.0
	sun_light.shadow_bias = 0.035
	sun_light.shadow_normal_bias = 1.3
	sun_light.shadow_blur = 1.1
	sun_light.shadow_opacity = 0.93
	sun_light.directional_shadow_pancake_size = 24.0
	sun_light.directional_shadow_fade_start = 0.86
	add_child(sun_light)
	apply_shadow_quality(2)

	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	var sky_res := Sky.new()
	sky_res.sky_material = sky_material
	# Incremental: the radiance cubemap is refreshed over several frames (cheap, self-limiting).
	sky_res.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky_res.radiance_size = Sky.RADIANCE_SIZE_128

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky_res
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	# SSAO: moderate, mostly in ambient light (keeps the faceted look crisp in the sun).
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.18
	# Glow: only real HDR emitters (sun, neon, lit windows, lamp lenses, water glints) bloom.
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.55
	env.glow_strength = 0.95
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.05
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 10.0
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.4)
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)
	# Depth fog (no volumetric fog, no SDFGI, no SSR, no SSIL: the GPU is shared).
	env.fog_enabled = true
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.1
	env.fog_density = BASE_FOG_DENSITY
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.0
	env.fog_height = -200.0
	env.fog_height_density = 0.0
	env.volumetric_fog_enabled = false
	env.sdfgi_enabled = false
	env.ssr_enabled = false
	env.ssil_enabled = false
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.20

	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)


## 0 off, 1 low, 2 medium, 3 high (Settings key "shadows").
func apply_shadow_quality(level: int) -> void:
	if sun_light == null or level == _shadow_level:
		return
	_shadow_level = level
	match level:
		0:
			sun_light.shadow_enabled = false
		1:
			sun_light.shadow_enabled = true
			sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun_light.directional_shadow_max_distance = 110.0
			sun_light.directional_shadow_split_1 = 0.22
			sun_light.directional_shadow_blend_splits = false
		3:
			sun_light.shadow_enabled = true
			sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun_light.directional_shadow_max_distance = 200.0
			sun_light.directional_shadow_split_1 = 0.055
			sun_light.directional_shadow_split_2 = 0.16
			sun_light.directional_shadow_split_3 = 0.42
			sun_light.directional_shadow_blend_splits = true
		_:
			sun_light.shadow_enabled = true
			sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun_light.directional_shadow_max_distance = 170.0
			sun_light.directional_shadow_split_1 = 0.06
			sun_light.directional_shadow_split_2 = 0.18
			sun_light.directional_shadow_split_3 = 0.45
			sun_light.directional_shadow_blend_splits = false


## Recomputes and applies the whole look.
## `underwater` 0/1, `underwater_depth` metres of water above the camera, `time_s` = gta_time.
func update_look(delta: float, time_s: float, underwater: float, underwater_depth: float) -> void:
	if sun_light == null:
		return
	var hour := WorldClock.hour
	daylight = WorldClock.get_daylight()
	night = 1.0 - daylight
	sun_dir = WorldClock.sun_direction_at(hour)
	moon_dir = WorldClock.moon_direction_at(hour)
	sun_elevation = sun_dir.y
	var e := sun_elevation
	day_factor = smoothstep(-0.14, 0.24, e)

	var cover := Weather.cloud_cover
	var rain := Weather.rain_intensity
	var fog_w := Weather.fog_amount
	var storm := Weather.storminess
	var flash := Weather.lightning_flash
	overcast = smoothstep(0.45, 0.95, cover)
	var gloom := clampf(rain * 0.30 + storm * 0.30, 0.0, 0.6)     # how much the deck darkens the day

	# --- key light --------------------------------------------------------------------------
	var sun_e := _sample_f(SUN_ENERGY, e)
	var moon_e := MOON_LIGHT_ENERGY * smoothstep(-0.08, -0.22, e) * smoothstep(0.02, 0.16, moon_dir.y)
	moon_is_key = sun_e <= 0.0005 and e < -0.04
	var direct_scale := lerpf(1.0, 0.30, overcast) * (1.0 - 0.45 * storm)
	if moon_is_key:
		light_dir = moon_dir
		light_color = MOON_LIGHT_COLOR
		light_energy = moon_e * lerpf(1.0, 0.45, overcast)
	else:
		light_dir = sun_dir
		light_color = _sample_c(SUN_LIGHT, e).lerp(Color(0.86, 0.88, 0.92), overcast * 0.75)
		light_energy = sun_e * direct_scale
	if light_dir.y < MIN_LIGHT_ELEVATION:
		light_dir = Vector3(light_dir.x, MIN_LIGHT_ELEVATION, light_dir.z).normalized()

	# --- sky ---------------------------------------------------------------------------------
	sky_top = _sample_c(SKY_TOP, e)
	sky_horizon = _sample_c(SKY_HORIZON, e)
	var grey_top := Color(0.30, 0.34, 0.40) * day_factor + Color(0.040, 0.048, 0.075)
	var grey_hor := Color(0.60, 0.64, 0.68) * day_factor + Color(0.075, 0.085, 0.125)
	var gloom_day := gloom * day_factor
	sky_top = sky_top.lerp(grey_top, overcast * 0.92) * (1.0 - gloom_day * 0.55)
	sky_horizon = sky_horizon.lerp(grey_hor, overcast * 0.88) * (1.0 - gloom_day * 0.45)

	var cloud_lit := _sample_c(CLOUD_LIT, e)
	var cloud_dark := _sample_c(CLOUD_DARK, e)
	# Closed deck: grey by day (darker with rain / storm); at night it keeps a faint glow from
	# the city below so a storm sky still shows structure instead of going black.
	var city_glow := Color(0.185, 0.200, 0.285) + Color(0.055, 0.036, 0.024) * night
	var deck_lit := Color(0.74, 0.76, 0.80) * (day_factor * (1.0 - gloom * 0.6)) + city_glow
	var deck_dark := Color(0.40, 0.43, 0.49) * (day_factor * (1.0 - gloom * 0.75)) + city_glow * 0.42
	cloud_lit = cloud_lit.lerp(deck_lit, overcast * 0.85)
	cloud_dark = cloud_dark.lerp(deck_dark, overcast * 0.85)

	# --- ambient -----------------------------------------------------------------------------
	ambient_color = _sample_c(AMBIENT, e)
	var amb_grey := Color(0.70, 0.73, 0.78).lerp(Color(0.26, 0.31, 0.46), 1.0 - day_factor)
	ambient_color = ambient_color.lerp(amb_grey, overcast * 0.7)
	# Overcast light is diffuse light: lift the ambient a little while the sun is dimmed.
	# Rain / storm gloom darkens the DAY; at night it must not take the last light away.
	# A closed deck at night glows from the city below: lift the night ambient under it.
	var overcast_lift := lerpf(1.0, lerpf(1.30, 1.12, day_factor), overcast)
	ambient_energy = _sample_f(AMBIENT_ENERGY, e) * overcast_lift * (1.0 - gloom * 0.42 * (0.30 + 0.70 * day_factor))

	# --- fog ---------------------------------------------------------------------------------
	var fog_grey := Color(0.74, 0.77, 0.80) * day_factor + Color(0.080, 0.095, 0.140)
	fog_color = sky_horizon.lerp(fog_grey, clampf(fog_w * 0.85, 0.0, 0.85))
	fog_density = BASE_FOG_DENSITY + fog_w * fog_w * FOG_WEATHER_DENSITY + rain * 0.0016 + storm * 0.0012
	var fog_sky := clampf(fog_w * 0.95 + rain * 0.18 + storm * 0.15, 0.0, 1.0)
	var aerial := lerpf(0.55, 0.10, clampf(fog_w * 1.2, 0.0, 1.0))
	var sun_scatter := 0.14 * day_factor * (1.0 - overcast)

	# --- lightning ---------------------------------------------------------------------------
	var out_light_color := light_color
	var out_light_energy := light_energy
	var out_ambient_energy := ambient_energy
	var out_ambient_color := ambient_color
	if flash > 0.001:
		out_light_color = light_color.lerp(Color(0.80, 0.86, 1.0), clampf(flash * 1.5, 0.0, 1.0))
		out_light_energy += flash * 1.5
		out_ambient_energy += flash * 0.8
		out_ambient_color = ambient_color.lerp(Color(0.78, 0.84, 1.0), clampf(flash, 0.0, 1.0))

	# --- underwater overrides ----------------------------------------------------------------
	var out_fog_color := fog_color
	var out_fog_density := fog_density
	if underwater > 0.5:
		var deep := clampf(underwater_depth / 14.0, 0.0, 1.0)
		var lum := 0.16 + 0.84 * day_factor
		out_fog_color = Color(0.12, 0.58, 0.66).lerp(Color(0.020, 0.170, 0.330), deep) * lum
		out_fog_color += Color(0.008, 0.020, 0.040)
		out_fog_density = UNDERWATER_FOG_DENSITY * lerpf(1.0, 1.35, deep) * lerpf(1.0, 1.4, storm)
		fog_sky = 1.0
		aerial = 0.0
		sun_scatter = 0.0
		out_light_energy *= lerpf(0.75, 0.25, deep)
		out_light_color = out_light_color.lerp(Color(0.45, 0.85, 0.95), 0.6)
		out_ambient_color = out_ambient_color.lerp(Color(0.25, 0.70, 0.85), 0.65)
		out_ambient_energy *= lerpf(0.95, 0.55, deep)

	# --- apply: light ------------------------------------------------------------------------
	if _applied_light_dir.dot(light_dir) < 0.9999995:
		_applied_light_dir = light_dir
		var up := Vector3.UP if absf(light_dir.y) < 0.98 else Vector3.RIGHT
		sun_light.basis = Basis.looking_at(-light_dir, up)
	sun_light.light_color = out_light_color
	sun_light.light_energy = out_light_energy
	sun_light.light_specular = 0.55 if moon_is_key else lerpf(1.0, 0.5, overcast)
	sun_light.visible = out_light_energy > 0.004

	# --- apply: environment ------------------------------------------------------------------
	env.ambient_light_color = out_ambient_color
	env.ambient_light_energy = out_ambient_energy
	env.fog_light_color = out_fog_color
	env.fog_density = out_fog_density
	env.fog_sky_affect = fog_sky
	env.fog_aerial_perspective = aerial
	env.fog_sun_scatter = sun_scatter
	env.glow_intensity = lerpf(0.50, 0.80, night)
	env.glow_bloom = lerpf(0.0, 0.025, night)

	# --- apply: sky shader -------------------------------------------------------------------
	var wind := Weather.wind_direction * (0.25 + Weather.wind_strength)
	_cloud_offset += Vector2(wind.x, wind.z) * delta * 0.012
	if absf(_cloud_offset.x) > 512.0 or absf(_cloud_offset.y) > 512.0:
		_cloud_offset = Vector2(fposmod(_cloud_offset.x, 512.0), fposmod(_cloud_offset.y, 512.0))
	var horizon_low := smoothstep(0.30, 0.0, e)       # 1 while the sun is near the horizon
	var sm := sky_material
	sm.set_shader_parameter(&"top_color", sky_top)
	sm.set_shader_parameter(&"horizon_color", sky_horizon)
	sm.set_shader_parameter(&"ground_color", fog_color.lerp(Color(0.03, 0.12, 0.22) * (0.15 + 0.85 * day_factor), 0.35))
	sm.set_shader_parameter(&"sun_dir", sun_dir)
	sm.set_shader_parameter(&"sun_color", _sample_c(SUN_DISC, e))
	sm.set_shader_parameter(&"sun_energy", lerpf(8.0, 2.1, horizon_low) * (1.0 - overcast * 0.6))
	sm.set_shader_parameter(&"sun_radius", lerpf(0.040, 0.056, horizon_low))
	# A closed rain / storm deck hides the disc (it would otherwise peek out under the cloud
	# layer at the horizon); broken cloud ("cloudy") keeps it.
	sm.set_shader_parameter(&"sun_disc_alpha", 1.0 - 0.94 * smoothstep(0.74, 0.93, cover))
	sm.set_shader_parameter(&"sun_glow_color", _sample_c(SUN_LIGHT, e))
	sm.set_shader_parameter(&"sun_glow", lerpf(0.28, 0.85, horizon_low) * (1.0 - overcast * 0.85))
	sm.set_shader_parameter(&"moon_dir", moon_dir)
	sm.set_shader_parameter(&"moon_energy", smoothstep(-0.04, -0.2, e) * smoothstep(0.0, 0.1, moon_dir.y))
	sm.set_shader_parameter(&"star_intensity", smoothstep(-0.06, -0.26, e) * (1.0 - overcast * 0.9))
	sm.set_shader_parameter(&"time_s", time_s)
	sm.set_shader_parameter(&"cloud_cover", cover)
	sm.set_shader_parameter(&"cloud_offset", _cloud_offset)
	sm.set_shader_parameter(&"cloud_lit", cloud_lit)
	sm.set_shader_parameter(&"cloud_dark", cloud_dark)
	sm.set_shader_parameter(&"cloud_light_dir", moon_dir if moon_is_key else sun_dir)
	sm.set_shader_parameter(&"flash", flash)


func _sample_c(cols: Array[Color], e: float) -> Color:
	var n := KEYS.size()
	if e <= KEYS[0]:
		return cols[0]
	if e >= KEYS[n - 1]:
		return cols[n - 1]
	for i in range(1, n):
		if e < KEYS[i]:
			return cols[i - 1].lerp(cols[i], (e - KEYS[i - 1]) / (KEYS[i] - KEYS[i - 1]))
	return cols[n - 1]


func _sample_f(vals: Array[float], e: float) -> float:
	var n := KEYS.size()
	if e <= KEYS[0]:
		return vals[0]
	if e >= KEYS[n - 1]:
		return vals[n - 1]
	for i in range(1, n):
		if e < KEYS[i]:
			return lerpf(vals[i - 1], vals[i], (e - KEYS[i - 1]) / (KEYS[i] - KEYS[i - 1]))
	return vals[n - 1]
