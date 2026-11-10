extends Node
## User settings (persisted to user://settings.cfg) + safe rendering defaults.
## The shipped defaults are deliberately GPU-friendly: V-Sync on, 60 FPS cap,
## 3D render scale never above 1.0 (spec section 3A).

const PATH := "user://settings.cfg"

var data := {
	"master_volume": 0.9,
	"sfx_volume": 1.0,
	"music_volume": 0.7,
	"ambient_volume": 0.8,
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"fov": 70.0,
	"quality": 1,            # 0 low, 1 medium (default), 2 high
	"fullscreen": false,
	"max_fps": 60,
	"vsync": true,
	"render_scale": 1.0,
	"camera_shake": 1.0,
	"show_fps": false,
	"radio_station": 1,
	"traffic_density": 1.0,
	"ped_density": 1.0,
}

signal changed(key: String)

func _ready() -> void:
	load_settings()
	apply_all()

func get_v(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)

func set_v(key: String, value: Variant, save := true) -> void:
	data[key] = value
	_apply(key)
	changed.emit(key)
	if save:
		save_settings()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in data.keys():
		if cf.has_section_key("settings", k):
			var v: Variant = cf.get_value("settings", k)
			if typeof(v) == typeof(data[k]) or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(data[k]) in [TYPE_INT, TYPE_FLOAT]):
				data[k] = v

func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in data.keys():
		cf.set_value("settings", k, data[k])
	cf.save(PATH)

func apply_all() -> void:
	for k in data.keys():
		_apply(k)

func _apply(key: String) -> void:
	match key:
		"master_volume":
			_bus_volume("Master", data[key])
		"sfx_volume":
			_bus_volume("SFX", data[key])
		"music_volume":
			_bus_volume("Music", data[key])
		"ambient_volume":
			_bus_volume("Ambient", data[key])
		"fullscreen":
			if DisplayServer.get_name() != "headless":
				var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if data[key] else DisplayServer.WINDOW_MODE_WINDOWED
				if DisplayServer.window_get_mode() != mode and not _is_automated():
					DisplayServer.window_set_mode(mode)
		"max_fps":
			# Never uncapped: clamp to a sane range.
			Engine.max_fps = clampi(int(data[key]), 30, 120)
		"vsync":
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if data[key] else DisplayServer.VSYNC_ADAPTIVE)
		"render_scale":
			var vp := get_viewport()
			if vp:
				vp.scaling_3d_scale = clampf(float(data[key]), 0.5, 1.0)
		"quality":
			_apply_quality(int(data[key]))

func _is_automated() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gta-test"):
			return true
	return false

func _bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)

func _apply_quality(q: int) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	match q:
		0:
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		1:
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_:
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	changed.emit("quality_applied")
