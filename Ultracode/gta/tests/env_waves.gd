extends Node
## ENVIRONMENT windowed test: does EnvironmentSystem.get_wave_height() agree with the PIXELS,
## and do the eight global shader uniforms really reach the GPU?
##
## Waves. A top-down orthographic camera looks at open sea. An 8 x 8 field of small magenta quads
## is placed every frame at get_wave_height(x, z) +EPS (odd probes) or -EPS (even probes). The
## ocean is drawn after them with the depth test on, so a quad ABOVE the rendered surface stays
## pure magenta and a quad BELOW it is painted over by the water. Reading the pixel at every quad
## centre therefore tells on which side of the RENDERED surface the CPU value lies:
## all probes right  <=>  |CPU height - GPU height| < EPS (12 mm).
## The field is checked in calm water and at full storm amplitude, at the wave centre and in the
## ring where the waves fade out (58-76 m from the camera), at several moments.
## For comparison the same probes are also placed with the ideal sine sum (get_smooth_height):
## that count is only logged - it shows why get_wave_height() follows the triangles instead.
##
## Uniforms. RenderingServer.global_shader_parameter_get() is editor-only, so four small 2D
## swatches with a test shader paint the uniform values as colours and the pixels are read back.
##
## Run (about 6 s at the 30 fps cap):
##   tools\godot.ps1 -Mode window -Frames 300 -UserArgs '--test=env_waves','--no_player','--disable=world,city,interactions,vehicles,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Quads and swatches are test instruments (never game content). Headless: everything that
## needs pixels is skipped.

const EPS := 0.012
const GRID := 8
const SPACING := 1.37              ## metres between probes (deliberately not a multiple of the 2 m cell)
const QUAD := 0.26
const VIEW_SIZE := 12.0            ## metres of sea across the screen height
const CAM_POS := Vector3(900.0, 20.0, 900.0)     ## open sea, far outside the island
const RING_OFFSET := 66.0          ## the fade ring is 58-76 m from the wave centre
const SWATCH_CODE := "shader_type canvas_item;
global uniform float gta_daylight;
global uniform float gta_night;
global uniform float gta_wetness;
global uniform float gta_rain;
global uniform float gta_time;
global uniform float gta_underwater;
global uniform vec3 gta_wind;
global uniform vec3 gta_player_pos;
uniform int mode = 0;
void fragment() {
	vec3 c = vec3(gta_night, gta_wetness, gta_rain);
	if (mode == 1) {
		c = vec3(gta_daylight, gta_underwater, fract(gta_time * 0.05));
	} else if (mode == 2) {
		c = gta_wind * 0.5 + 0.5;
	} else if (mode == 3) {
		c = fract(gta_player_pos * 0.001);
	}
	COLOR = vec4(c, 1.0);
}
"

var _env: Node
var _cam: Camera3D
var _markers: Array[MeshInstance3D] = []
var _signs := PackedFloat32Array()
var _place_mode: int = 0           ## 0 idle, 1 get_wave_height, 2 sine sum, 3 calibration (+-0.5 m)
var _offset := Vector2.ZERO        ## probe field centre relative to the camera (x, z)
var _ref_above := Color(1, 0, 1)
var _swatches: Array[ColorRect] = []
var _frame_time: float = 0.0       ## gta_time of the frame that is being drawn
var _frame_wind := Vector3.ZERO
var _debug_left: int = 8


func _ready() -> void:
	process_priority = 1000        # run AFTER the environment system updated the sea this frame
	await _run()


func _process(_delta: float) -> void:
	if _env != null:
		_frame_time = float(_env.get("time_seconds"))
		_frame_wind = Weather.get_wind_vector()
	if _place_mode != 0:
		_place()


func _run() -> void:
	var t := TestHarness
	_env = Game.get_system("environment")
	if not t.check(_env != null, "environment system is loaded"):
		t.finish(false, "no environment system")
		return
	if t.is_headless():
		t.log_line("headless run: this test needs pixels - skipped")
		t.finish()
		return
	if UI.has_method("set_hud_visible"):
		UI.set_hud_visible(false)
	Weather.auto_cycle = false
	WorldClock.paused = true
	# Low morning sun: no mirror glint of the sun can reach a camera that looks straight down.
	WorldClock.set_hour(7.6)
	Weather.snap_weather("clear", 0.0)
	var environment: Environment = _env.call("get_environment")
	var glow_was := environment.glow_enabled if environment != null else false
	if environment != null:
		environment.glow_enabled = false

	_cam = Camera3D.new()
	_cam.name = "EnvWaveCamera"
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = VIEW_SIZE
	_cam.near = 1.0
	_cam.far = 100.0
	add_child(_cam)
	_cam.global_position = CAM_POS
	_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)     # screen right = +X, screen down = +Z
	_cam.current = true

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.0, 1.0)
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := PlaneMesh.new()
	quad.size = Vector2(QUAD, QUAD)
	quad.material = mat
	for k in GRID * GRID:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_markers.append(mi)
		@warning_ignore("integer_division")
		_signs.append(1.0 if ((k % GRID) + (k / GRID)) % 2 == 0 else -1.0)
	_build_swatches()
	await t.wait_frames(8)

	await _check_globals()

	# --- calibration: what does a quad clearly above / clearly below the water look like? ----
	var calib: Dictionary = await _capture(3)
	_ref_above = calib["avg_above"]
	t.log_line("calibration: above avg %s, env underwater=%s fog=%.5f" % [str(_ref_above),
			str(_env.call("is_camera_underwater")), environment.fog_density if environment != null else -1.0])
	t.check(int(calib["above_seen"]) == int(calib["above_total"]) and int(calib["below_hidden"]) == int(calib["below_total"]),
			"instrument works: quads 0.5 m above the sea are visible, 0.5 m below are covered (%d/%d, %d/%d)" % [
			calib["above_seen"], calib["above_total"], calib["below_hidden"], calib["below_total"]])

	# --- the comparison ----------------------------------------------------------------------
	var total := 0
	var wrong := 0
	var smooth_total := 0
	var smooth_wrong := 0
	for storm: bool in [false, true]:
		# Amplitude follows the wind; set it directly so no rain falls through the picture.
		Weather.snap_weather("clear", 0.0)
		Weather.wind_strength = 1.0 if storm else 0.2
		for ring: bool in [false, true]:
			_offset = Vector2(RING_OFFSET, 0.0) if ring else Vector2.ZERO
			_cam.h_offset = _offset.x
			await t.wait_frames(3)
			var pass_wrong := 0
			var pass_total := 0
			for rep in 4:
				var r: Dictionary = await _capture(1)
				pass_wrong += int(r["wrong"])
				pass_total += int(r["total"])
				await t.wait_frames(5)
			var sm: Dictionary = await _capture(2)
			smooth_wrong += int(sm["wrong"])
			smooth_total += int(sm["total"])
			var amp: float = _env.get("ocean").wave_amp
			t.check(pass_wrong == 0, "get_wave_height is within %.0f mm of the rendered sea: %s, %s, amp %.2f m (%d of %d probes wrong)" % [
					EPS * 1000.0, "storm" if storm else "calm", "fade ring" if ring else "wave centre", amp, pass_wrong, pass_total])
			t.log_line("sine-sum comparison (%s, %s): %d of %d probes on the wrong side at +-%.0f mm" % [
					"storm" if storm else "calm", "fade ring" if ring else "centre", int(sm["wrong"]), int(sm["total"]), EPS * 1000.0])
			total += pass_total
			wrong += pass_wrong
	t.log_line("TOTAL exact: %d wrong of %d ; sine sum: %d wrong of %d" % [wrong, total, smooth_wrong, smooth_total])
	t.check(total >= 16 * GRID * GRID, "all passes ran (%d probes)" % total)
	_cam.h_offset = 0.0
	_offset = Vector2.ZERO
	var calib2: Dictionary = await _capture(3)
	t.log_line("calibration again at the end: above avg %s, env underwater=%s fog=%.5f" % [str(calib2["avg_above"]),
			str(_env.call("is_camera_underwater")), environment.fog_density if environment != null else -1.0])
	_place_mode = 1
	await t.wait_frames(2)
	await t.shot("env_20_wave_probe")
	_place_mode = 0
	if environment != null:
		environment.glow_enabled = glow_was
	Weather.snap_weather("clear", 0.0)
	Weather.auto_cycle = true
	WorldClock.paused = false
	t.finish()


# --- global uniforms ---------------------------------------------------------------------------

func _build_swatches() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var shader := Shader.new()
	shader.code = SWATCH_CODE
	for i in 4:
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter(&"mode", i)
		var r := ColorRect.new()
		r.material = m
		r.position = Vector2(24.0 + 72.0 * float(i), 24.0)
		r.size = Vector2(48.0, 48.0)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(r)
		_swatches.append(r)


## Colours of the four swatches in the frame that was just drawn.
func _read_swatches() -> Array[Color]:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var view := get_viewport().get_visible_rect().size
	var out: Array[Color] = []
	for r in _swatches:
		var c := (r.position + r.size * 0.5) * Vector2(float(img.get_width()) / view.x, float(img.get_height()) / view.y)
		out.append(img.get_pixel(clampi(int(c.x), 0, img.get_width() - 1), clampi(int(c.y), 0, img.get_height() - 1)))
	return out


func _near(a: float, b: float, tol: float = 0.025) -> bool:
	return absf(a - b) <= tol


func _check_globals() -> void:
	var t := TestHarness
	# Night + rain: night 1, wetness 1 (snap), rain = the preset intensity.
	WorldClock.set_hour(23.0)
	Weather.snap_weather("rain")
	var s: Array[Color] = await _read_swatches()
	var night: float = _env.get("night_factor")
	t.check(_near(s[0].r, night) and night > 0.95 and _near(s[0].g, Weather.wetness) and Weather.wetness > 0.99
			and _near(s[0].b, Weather.rain_intensity) and Weather.rain_intensity > 0.5,
			"GPU sees gta_night / gta_wetness / gta_rain (pixel %.2f %.2f %.2f, CPU %.2f %.2f %.2f)" % [
			s[0].r, s[0].g, s[0].b, night, Weather.wetness, Weather.rain_intensity])
	var time_px := s[1].b
	var time_cpu := fposmod(_frame_time * 0.05, 1.0)
	var time_err := absf(time_px - time_cpu)
	t.check(_near(s[1].r, 1.0 - night) and _near(s[1].g, 0.0) and minf(time_err, 1.0 - time_err) < 0.03,
			"GPU sees gta_daylight / gta_underwater / gta_time (pixel %.2f %.2f %.3f, CPU %.2f 0 %.3f)" % [
			s[1].r, s[1].g, time_px, 1.0 - night, time_cpu])
	var wind := _frame_wind * 0.5 + Vector3(0.5, 0.5, 0.5)
	t.check(_near(s[2].r, wind.x) and _near(s[2].g, wind.y) and _near(s[2].b, wind.z) and _frame_wind.length() > 0.3,
			"GPU sees gta_wind (pixel %.2f %.2f %.2f, CPU %.2f %.2f %.2f)" % [s[2].r, s[2].g, s[2].b, wind.x, wind.y, wind.z])
	var pos := _cam.global_position * 0.001
	t.check(_near(s[3].r, fposmod(pos.x, 1.0)) and _near(s[3].g, fposmod(pos.y, 1.0)) and _near(s[3].b, fposmod(pos.z, 1.0)),
			"GPU sees gta_player_pos (camera position without a player; pixel %.2f %.2f %.2f)" % [s[3].r, s[3].g, s[3].b])
	# Same frame switch to a dry noon, then under water.
	WorldClock.set_hour(12.0)
	Weather.snap_weather("clear", 0.0)
	_cam.global_position = Vector3(CAM_POS.x, -3.0, CAM_POS.z)
	s = await _read_swatches()
	t.check(_near(s[0].r, 0.0) and _near(s[0].g, 0.0) and _near(s[0].b, 0.0) and _near(s[1].r, 1.0) and _near(s[1].g, 1.0),
			"uniforms follow set_hour / snap_weather / diving at once (night %.2f wet %.2f rain %.2f day %.2f underwater %.2f)" % [
			s[0].r, s[0].g, s[0].b, s[1].r, s[1].g])
	var t1 := s[1].b
	await t.wait_frames(12)
	s = await _read_swatches()
	t.check(not is_equal_approx(s[1].b, t1), "gta_time advances")
	_cam.global_position = CAM_POS
	WorldClock.set_hour(7.6)
	for r in _swatches:
		r.visible = false
	# DIAG: frame-by-frame colour of the first probe right after surfacing
	for f in 8:
		var dd: Dictionary = await _capture(3)
		t.log_line("DIAG frame %d after surfacing: above avg %s underwater=%s" % [f, str(dd["avg_above"]), str(_env.call("is_camera_underwater"))])
		if f == 1:
			var dimg := get_viewport().get_texture().get_image()
			dimg.save_png(ProjectSettings.globalize_path("res://qa/screenshots/env_diag_surfacing.png"))
	await t.wait_frames(3)


# --- wave probes -------------------------------------------------------------------------------

func _probe_xz(k: int) -> Vector2:
	var i := k % GRID
	@warning_ignore("integer_division")
	var j := k / GRID
	var half := float(GRID - 1) * 0.5
	return Vector2(_cam.global_position.x + _offset.x + (float(i) - half) * SPACING,
			_cam.global_position.z + _offset.y + (float(j) - half) * SPACING)


func _place() -> void:
	var ocean: Variant = _env.get("ocean")
	for k in _markers.size():
		var p := _probe_xz(k)
		var y: float
		match _place_mode:
			2:
				y = float(ocean.get_smooth_height(p.x, p.y)) + _signs[k] * EPS
			3:
				y = Game.WATER_LEVEL + _signs[k] * 0.5
			_:
				y = float(_env.call("get_wave_height", p.x, p.y)) + _signs[k] * EPS
		_markers[k].global_position = Vector3(p.x, y, p.y)


## Places the probes in `mode`, renders one frame and reads the pixel at every probe centre.
func _capture(mode: int) -> Dictionary:
	_place_mode = mode
	await get_tree().process_frame          # the next frame starts: sea update, then _place()
	await RenderingServer.frame_post_draw   # ... and has been drawn with exactly these positions
	var img := get_viewport().get_texture().get_image()
	_place_mode = 0
	var out := {"wrong": 0, "total": 0, "above_seen": 0, "above_total": 0, "below_hidden": 0,
			"below_total": 0, "avg_above": Color(1, 0, 1)}
	if img == null or img.is_empty():
		out["wrong"] = _markers.size()
		out["total"] = _markers.size()
		return out
	# Orthographic, looking straight down: world metres map linearly to pixels.
	var w := float(img.get_width())
	var h := float(img.get_height())
	var px_per_m := h / VIEW_SIZE
	var centre_x := _cam.global_position.x + _cam.h_offset
	var centre_z := _cam.global_position.z
	var sum := Color(0, 0, 0)
	for k in _markers.size():
		var mp := _markers[k].global_position
		var px := clampi(int(round(w * 0.5 + (mp.x - centre_x) * px_per_m)), 0, img.get_width() - 1)
		var py := clampi(int(round(h * 0.5 + (mp.z - centre_z) * px_per_m)), 0, img.get_height() - 1)
		var c := img.get_pixel(px, py)
		var seen: bool
		# A quad above the water is pure magenta (green = 0). The thinnest water film over a quad
		# (alpha >= 0.22, or opaque foam) lifts the green channel far above this threshold.
		seen = c.g < 0.10 and c.r > 0.45 and c.b > 0.45
		var should_be_seen := _signs[k] > 0.0
		if k < 2 and _debug_left > 0:
			_debug_left -= 1
			TestHarness.log_line("probe %d mode %d pixel (%d, %d) = %s ref %s seen %s" % [k, mode, px, py, str(c), str(_ref_above), str(seen)])
		out["total"] = int(out["total"]) + 1
		if seen != should_be_seen:
			out["wrong"] = int(out["wrong"]) + 1
		if should_be_seen:
			out["above_total"] = int(out["above_total"]) + 1
			if seen:
				out["above_seen"] = int(out["above_seen"]) + 1
				sum += c
		else:
			out["below_total"] = int(out["below_total"]) + 1
			if not seen:
				out["below_hidden"] = int(out["below_hidden"]) + 1
	if int(out["above_seen"]) > 0:
		var n := float(int(out["above_seen"]))
		out["avg_above"] = Color(sum.r / n, sum.g / n, sum.b / n)
	return out
