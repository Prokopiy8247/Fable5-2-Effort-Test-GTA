extends Node
## Autoload "Registry": data-driven definition store.
## kind -> id -> definition (a custom Resource with an `id` property, or a Dictionary with "id").
##
## Sources, loaded at startup in this order:
##   1. every *.tres / *.res under res://gta/resources/data/<kind>/      (kind = folder name)
##   2. every script under res://gta/resources/registries/*.gd that has
##          static func register_all(registry: Node) -> void
##      (use this to build many definitions in code: registry.register("weapons", spec))
##
## Kinds used by the project (see docs/ARCHITECTURE.md): "weapons", "attachments", "vehicles",
## "vehicle_mods", "npc_archetypes", "clothing", "hair", "shops", "radio_stations", "animals",
## "skills", "activities".

const DATA_ROOT := "res://gta/resources/data"
const REGISTRAR_ROOT := "res://gta/resources/registries"

var _defs: Dictionary = {}      ## kind -> {id -> def}
var _loaded: bool = false


func _ready() -> void:
	load_all()


func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	_load_data_folders()
	_run_registrars()


func reload() -> void:
	_defs.clear()
	_loaded = false
	load_all()


## Register (or replace) a definition. `def` must expose an id (property or "id" key).
func register(kind: String, def: Variant) -> void:
	var id := _id_of(def)
	if id == "":
		push_warning("Registry.register(%s): definition without id ignored" % kind)
		return
	if not _defs.has(kind):
		_defs[kind] = {}
	_defs[kind][id] = def


func has_def(kind: String, id: String) -> bool:
	return _defs.has(kind) and _defs[kind].has(id)


## Returns the definition or null.
func get_def(kind: String, id: String) -> Variant:
	if _defs.has(kind):
		return _defs[kind].get(id, null)
	return null


func ids(kind: String) -> Array:
	if not _defs.has(kind):
		return []
	var out: Array = _defs[kind].keys()
	out.sort()
	return out


func all(kind: String) -> Array:
	var out: Array = []
	for id in ids(kind):
		out.append(_defs[kind][id])
	return out


func count(kind: String) -> int:
	return _defs[kind].size() if _defs.has(kind) else 0


func kinds() -> Array:
	return _defs.keys()


func _id_of(def: Variant) -> String:
	if def is Dictionary:
		return str((def as Dictionary).get("id", ""))
	if def is Object:
		var v: Variant = (def as Object).get("id")
		return "" if v == null else str(v)
	return ""


func _load_data_folders() -> void:
	var root := DirAccess.open(DATA_ROOT)
	if root == null:
		return
	for kind in root.get_directories():
		var dir := DirAccess.open(DATA_ROOT.path_join(kind))
		if dir == null:
			continue
		for f in dir.get_files():
			var file := f.trim_suffix(".remap")
			if not (file.ends_with(".tres") or file.ends_with(".res")):
				continue
			var res: Resource = load(DATA_ROOT.path_join(kind).path_join(file))
			if res != null:
				register(kind, res)


func _run_registrars() -> void:
	var dir := DirAccess.open(REGISTRAR_ROOT)
	if dir == null:
		return
	var files := Array(dir.get_files())
	files.sort()
	for f: String in files:
		var file := f.trim_suffix(".remap")
		if not (file.ends_with(".gd") or file.ends_with(".gdc")):
			continue
		var script: Script = load(REGISTRAR_ROOT.path_join(file.trim_suffix("c") if file.ends_with(".gdc") else file))
		if script == null:
			continue
		var found := false
		for m: Dictionary in script.get_script_method_list():
			if m.get("name", "") == "register_all":
				found = true
				break
		if found:
			script.call("register_all", self)
		else:
			push_warning("Registry: %s has no static register_all(registry)" % file)
