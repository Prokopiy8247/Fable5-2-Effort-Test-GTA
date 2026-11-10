extends Node
## Automated scenario runner (autoload "TestRunner").
## Usage:  godot --path . -- --gta-test=<scenario>[,<scenario>...] [--gta-shots]
## Scenarios live in test_scenarios.gd as coroutines named t_<scenario>.
## Every run is launched through tools/run_godot.ps1, which enforces frame + OS timeouts.

var active := false
var names: PackedStringArray = []
var out_dir := ""
var results: Array = []
var frame := 0
var _scen: Object = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gta-test="):
			names = a.get_slice("=", 1).split(",", false)
			active = true
	if not active:
		set_process(false)
		return
	out_dir = ProjectSettings.globalize_path("res://_test_output/")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not FileAccess.file_exists(out_dir + ".gdignore"):
		var f := FileAccess.open(out_dir + ".gdignore", FileAccess.WRITE)
		if f:
			f.close()
	print("[TEST] runner active: ", names)
	_run.call_deferred()

func _process(_d: float) -> void:
	frame += 1

func _run() -> void:
	var script: GDScript = load("res://gta/code/debug/test_scenarios.gd")
	_scen = script.new()
	_scen.runner = self
	add_child(_scen)
	for n in names:
		var method := "t_" + n
		if not _scen.has_method(method):
			record(n, false, "unknown scenario")
			continue
		print("[TEST] >>> ", n)
		var t0 := Time.get_ticks_msec()
		await _scen.call(method)
		print("[TEST] <<< ", n, " (", Time.get_ticks_msec() - t0, " ms)")
	var failed := 0
	for r in results:
		if not r[1]:
			failed += 1
	print("[TEST] SUMMARY total=", results.size(), " failed=", failed)
	for r in results:
		print("[TEST]   ", "PASS" if r[1] else "FAIL", "  ", r[0], "  ", r[2])
	await get_tree().process_frame
	get_tree().quit(1 if failed > 0 else 0)

func record(check: String, ok: bool, detail: String = "") -> void:
	results.append([check, ok, detail])
	print("[TEST] ", "PASS" if ok else "FAIL", " ", check, " ", detail)

func wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func wait_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func wait_seconds(s: float) -> void:
	# game-time wait that also works under --fixed-fps in headless mode
	var frames := int(ceil(s * 60.0))
	await wait_physics(frames)

## Save the current viewport to _test_output/<name>.png (no-op when headless).
func shot(shot_name: String) -> void:
	if Game.is_headless:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(out_dir + shot_name + ".png")
		print("[TEST] shot ", shot_name)
