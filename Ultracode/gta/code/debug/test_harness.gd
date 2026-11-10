extends Node
## Autoload "TestHarness": automated test + screenshot driver for agents and QA.
##
## Command line (after `--`):
##   --test=NAME          after EventBus.game_ready, instantiate res://gta/tests/NAME.gd (extends Node)
##                        and add it under Main. The test must call TestHarness.finish(ok, msg).
##   --test-timeout=SEC   fail the test automatically after SEC real seconds (default 90)
##   --disable=a,b        skip world systems (handled by Game), e.g. --disable=traffic,peds,police
##   --seed=N             deterministic RNG
##
## A test script typically looks like:
##     extends Node
##     func _ready() -> void:
##         await TestHarness.wait_frames(30)
##         Input.action_press("move_forward")
##         await TestHarness.wait_seconds(2.0)
##         Input.action_release("move_forward")
##         await TestHarness.shot("player_walk")          # no-op in --headless
##         TestHarness.check(Game.player.global_position.length() > 1.0, "player moved")
##         TestHarness.finish()                            # PASS if no check failed
##
## Results are printed as `TEST_RESULT: PASS|FAIL <name> <message>`; tools/godot.ps1 surfaces them.

var test_name: String = ""
var active: bool = false
var failures: PackedStringArray = []
var checks_run: int = 0
var _timeout_sec: float = 90.0
var _started_msec: int = 0
var _finished: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			test_name = a.substr(7)
		elif a.begins_with("--test-timeout="):
			_timeout_sec = float(a.substr(15))
	if test_name != "":
		active = true
		_started_msec = Time.get_ticks_msec()
		EventBus.game_ready.connect(_on_game_ready, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if active and not _finished and Time.get_ticks_msec() - _started_msec > int(_timeout_sec * 1000.0):
		failures.append("timeout after %.0f s" % _timeout_sec)
		finish(false, "timeout")


func is_testing() -> bool:
	return active


func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _on_game_ready() -> void:
	var path := "res://gta/tests/%s.gd" % test_name
	if not ResourceLoader.exists(path):
		failures.append("test script not found: " + path)
		finish(false, "missing test")
		return
	var script := load(path) as Script
	if script == null or not script.can_instantiate():
		failures.append("test script failed to load: " + path)
		finish(false, "parse error")
		return
	var node := script.new() as Node
	node.name = "Test_" + test_name
	var parent: Node = Game.main if Game.main != null else get_tree().root
	parent.add_child(node)


func log_line(msg: String) -> void:
	print("TEST_LOG: ", msg)


## Record an assertion. Returns `condition` so it can be chained.
func check(condition: bool, description: String) -> bool:
	checks_run += 1
	if condition:
		print("TEST_CHECK: ok   - ", description)
	else:
		print("TEST_CHECK: FAIL - ", description)
		failures.append(description)
	return condition


func wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func wait_physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Waits in GAME time (respects Engine.time_scale; under --fixed-fps it is simulated time).
func wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, false).timeout


## Saves a PNG of the viewport to <project>/qa/screenshots/<shot_name>.png (windowed runs only).
func shot(shot_name: String) -> String:
	if is_headless():
		return ""
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return ""
	var dir := ProjectSettings.globalize_path("res://qa/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("SHOT_SAVED: ", path)
	return path


## Finish the test and quit. `ok` is AND-ed with "no failed checks".
func finish(ok: bool = true, msg: String = "") -> void:
	if _finished:
		return
	_finished = true
	var passed := ok and failures.is_empty()
	var detail := msg
	if not failures.is_empty():
		detail += " | failed: " + "; ".join(failures)
	print("TEST_RESULT: %s %s checks=%d %s" % ["PASS" if passed else "FAIL", test_name, checks_run, detail])
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)
