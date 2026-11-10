class_name BuildingCatalog
extends RefCounted
## WORLD / city builder: the building catalogue.
## Loads and merges every manifest*.json in res://gta/generated/models/buildings (ARCHITECTURE 8.4:
## "each author writes its own manifest file; loaders merge every manifest*.json in the folder").
## Pure data - no nodes. The city builder turns entries into placed buildings (docs/CITY.md).
##
##     var cat := BuildingCatalog.new()
##     cat.load_all()
##     var d := cat.get_def("office_a")          # manifest entry (+ normalised extras, see _normalise)
##     cat.find_landmark("tram_stop_2")          # -> the tram_stop entry (via "serves")
##     cat.by_category("house")                  # Array[Dictionary], sorted by id
##
## Normalised extras added to every entry (always present, typed):
##   "fp": Vector2 footprint (x width, z depth), "co": Vector2 centre offset (x, z),
##   "ov": Dictionary overhang {front, back, left, right}, "h": float height, "roof": float roof height,
##   "path": String resource path of the GLB, "source": String manifest file name,
##   "tags": Array[String], "lm": String landmark ("" for generic buildings).

const DIR := "res://gta/generated/models/buildings"

var defs: Dictionary = {}                ## id -> Dictionary
var errors: PackedStringArray = []
var manifests: PackedStringArray = []    ## file names that were merged

var _by_landmark: Dictionary = {}        ## landmark / served location -> id


## Reads every manifest*.json of the buildings folder. Returns the number of building entries.
func load_all(dir: String = DIR) -> int:
	defs.clear()
	_by_landmark.clear()
	errors.clear()
	manifests.clear()
	var files := _manifest_files(dir)
	for f in files:
		_load_manifest(dir, f)
	return defs.size()


func has_def(id: String) -> bool:
	return defs.has(id)


func get_def(id: String) -> Dictionary:
	return defs.get(id, {})


func ids() -> PackedStringArray:
	var out := PackedStringArray(defs.keys())
	out.sort()
	return out


func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids():
		out.append(defs[id])
	return out


## Every entry of one manifest category ("office", "house", "landmark", "misc" ...), sorted by id.
func by_category(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids():
		var d: Dictionary = defs[id]
		if String(d.get("category", "")) == category:
			out.append(d)
	return out


## Every entry carrying `tag`, sorted by id.
func by_tag(tag: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids():
		var d: Dictionary = defs[id]
		if (d["tags"] as Array).has(tag):
			out.append(d)
	return out


## The building that serves a landmark lot: manifest "landmark" == name, or name listed in "serves"
## (tram_stop_1..3 -> tram_stop). {} when none.
func find_landmark(landmark: String) -> Dictionary:
	var id: String = _by_landmark.get(landmark, "")
	if id == "":
		return {}
	return defs.get(id, {})


## Landmark names that have a building ("police_station", "tram_stop_1", ...).
func landmark_names() -> PackedStringArray:
	var out := PackedStringArray(_by_landmark.keys())
	out.sort()
	return out


# ---------------------------------------------------------------------------------------------

func _manifest_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		errors.append("cannot open " + dir)
		return out
	for f in da.get_files():
		var name := f
		if name.ends_with(".remap"):
			name = name.trim_suffix(".remap")
		if name.begins_with("manifest") and name.ends_with(".json") and not out.has(name):
			out.append(name)
	out.sort()
	return out


func _load_manifest(dir: String, file: String) -> void:
	var path := dir.path_join(file)
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		errors.append("empty or unreadable manifest " + file)
		return
	var data: Variant = JSON.parse_string(txt)
	if not (data is Dictionary) or not ((data as Dictionary).get("buildings") is Array):
		errors.append("manifest %s has no 'buildings' array" % file)
		return
	manifests.append(file)
	for e: Variant in (data as Dictionary)["buildings"]:
		if not (e is Dictionary):
			continue
		var d: Dictionary = (e as Dictionary).duplicate(true)
		var id := String(d.get("id", ""))
		if id == "":
			errors.append("entry without id in " + file)
			continue
		if defs.has(id):
			errors.append("duplicate building id '%s' in %s (kept the one from %s)" % [id, file, defs[id]["source"]])
			continue
		if not _normalise(d, dir, file):
			continue
		defs[id] = d
		var lm := String(d["lm"])
		if lm != "":
			_by_landmark[lm] = id
		for s: Variant in d.get("serves", []):
			_by_landmark[String(s)] = id


func _normalise(d: Dictionary, dir: String, file: String) -> bool:
	var id := String(d["id"])
	var fp: Variant = d.get("footprint")
	if not (fp is Array) or (fp as Array).size() < 2:
		errors.append("%s: missing footprint" % id)
		return false
	d["fp"] = Vector2(float(fp[0]), float(fp[1]))
	var co: Variant = d.get("center_offset", [0.0, 0.0])
	d["co"] = Vector2(float(co[0]), float(co[1])) if co is Array and (co as Array).size() >= 2 else Vector2.ZERO
	var ov: Dictionary = {"front": 0.0, "back": 0.0, "left": 0.0, "right": 0.0}
	var src_ov: Variant = d.get("overhang", {})
	if src_ov is Dictionary:
		for k in ov:
			ov[k] = maxf(float((src_ov as Dictionary).get(k, 0.0)), 0.0)
	d["ov"] = ov
	d["h"] = float(d.get("height", 0.0))
	d["roof"] = float(d.get("roof_height", d["h"]))
	d["lm"] = String(d.get("landmark", ""))
	d["category"] = String(d.get("category", "misc"))
	d["collision"] = String(d.get("collision", "box"))
	var tags: Array[String] = []
	for t: Variant in d.get("tags", []):
		tags.append(String(t))
	d["tags"] = tags
	var f := String(d.get("file", id + ".glb"))
	d["path"] = dir.path_join(f)
	d["source"] = file
	if not ResourceLoader.exists(String(d["path"])):
		errors.append("%s: GLB missing %s" % [id, d["path"]])
		return false
	return true
