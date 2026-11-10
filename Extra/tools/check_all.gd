extends SceneTree
# Dev helper: loads every GDScript in the project so parse errors are reported in one pass.
#   godot --headless --path . -s tools/check_all.gd


func _init() -> void:
	var files: Array = []
	_scan("res://gta", files)
	var bad := 0
	for f in files:
		var s = load(f)
		if s == null or not (s as GDScript).can_instantiate():
			bad += 1
			print("FAILED: " + f)
	print("checked %d scripts, %d failed" % [files.size(), bad])
	quit()


func _scan(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if d.current_is_dir():
			if not n.begins_with("."):
				_scan(dir + "/" + n, out)
		elif n.ends_with(".gd"):
			out.append(dir + "/" + n)
		n = d.get_next()
