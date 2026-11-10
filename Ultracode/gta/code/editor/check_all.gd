extends SceneTree
## Headless validation tool: parse-loads every script/scene/resource under the given folders.
## Run through:  tools\godot.ps1 -Mode check [-Dirs gta/code/player,gta/code/core]
## Prints CHECK_FAIL <path> for anything that does not load, and a final CHECK_DONE line.

var _fails: int = 0
var _count: int = 0


func _initialize() -> void:
	var dirs: PackedStringArray = ["gta"]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--dirs="):
			dirs = a.substr(7).split(",", false)
	for d in dirs:
		_scan("res://" + d.strip_edges().trim_prefix("res://"))
	print("CHECK_DONE files=%d fails=%d" % [_count, _fails])
	quit(1 if _fails > 0 else 0)


func _scan(path: String) -> void:
	if path.get_extension() != "":
		_check_file(path)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		print("CHECK_NOTE cannot open ", path)
		return
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		_scan(path.path_join(sub))
	for f in dir.get_files():
		_check_file(path.path_join(f))


func _check_file(file: String) -> void:
	var ext := file.get_extension()
	if ext == "gd":
		_count += 1
		var s: Variant = ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_REUSE)
		if s == null or not (s is Script):
			_fail(file, "script did not load")
		elif not (s as Script).can_instantiate() and not (s as Script).is_abstract():
			_fail(file, "script has errors (cannot instantiate)")
	elif ext == "tscn" or ext == "tres" or ext == "gdshader":
		_count += 1
		var r: Variant = ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_REUSE)
		if r == null:
			_fail(file, "resource did not load")


func _fail(file: String, why: String) -> void:
	_fails += 1
	print("CHECK_FAIL ", file, " :: ", why)
