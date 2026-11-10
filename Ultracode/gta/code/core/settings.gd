extends Node
## Autoload "Settings": user settings persisted to user://settings.cfg.
## Safe-by-default GPU policy (benchmark spec 3A): V-Sync on, FPS cap <= 60 unless the user
## raises it, 3D render scale never above 1.0.

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"mouse_sensitivity": 0.0022,
	"invert_y": false,
	"fov": 70.0,
	"master_volume": 0.8,
	"sfx_volume": 0.9,
	"music_volume": 0.6,
	"ambience_volume": 0.7,
	"vsync": true,
	"max_fps": 60,
	"render_scale": 1.0,
	"shadows": 2,              # 0 off, 1 low, 2 medium, 3 high
	"traffic_density": 1.0,    # 0..1.5
	"ped_density": 1.0,        # 0..1.5
	"show_fps": false,
	"radio_station": "",
	"camera_shake": 1.0,
	"subtitles": true,
}

var values: Dictionary = DEFAULTS.duplicate()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key, null))


func set_value(key: String, value: Variant, save_now: bool = true) -> void:
	values[key] = value
	apply()
	if save_now:
		save_settings()
	EventBus.settings_changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in DEFAULTS:
		values[k] = cfg.get_value("settings", k, DEFAULTS[k])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("settings", k, values[k])
	cfg.save(PATH)


## Applies engine-level settings. Hard safety clamps live here on purpose.
func apply() -> void:
	var fps := clampi(int(values.get("max_fps", 60)), 30, 120)
	# A --max-fps given on the command line (tools/godot.ps1 test runs, GPU safety) always wins:
	# never raise the cap above it from user settings.
	var cli_cap := _cmdline_max_fps()
	if cli_cap > 0:
		fps = mini(fps, cli_cap)
	Engine.max_fps = fps
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if bool(values.get("vsync", true)) else DisplayServer.VSYNC_DISABLED)
	var scale := clampf(float(values.get("render_scale", 1.0)), 0.5, 1.0)
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = scale
	_apply_volume("Master", float(values.get("master_volume", 0.8)))
	_apply_volume("SFX", float(values.get("sfx_volume", 0.9)))
	_apply_volume("Music", float(values.get("music_volume", 0.6)))
	_apply_volume("Ambience", float(values.get("ambience_volume", 0.7)))


func _cmdline_max_fps() -> int:
	var args := OS.get_cmdline_args()
	for i in args.size():
		var a: String = args[i]
		if a == "--max-fps" and i + 1 < args.size():
			return int(args[i + 1])
		if a.begins_with("--max-fps="):
			return int(a.substr(10))
	return 0


func _apply_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
