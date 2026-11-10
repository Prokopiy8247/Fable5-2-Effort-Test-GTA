extends Node
## Autoload "SaveSystem": versioned JSON persistence in user://saves/ (docs/SAVE.md).
## The public names of the lead's contract stub are kept (register_provider, save_game, load_game,
## has_save, slot_path, delete_save, vec3/color helpers); everything else is additive.
##
## Provider pattern: anything with
##     func get_save_data() -> Dictionary
##     func load_save_data(data: Dictionary) -> void
## registers itself once:  SaveSystem.register_provider("player", self)
## World systems (BootManifest) that implement both methods but never registered are picked up
## automatically at EventBus.game_ready under their system name.
## Values must be JSON-safe (use SaveSystem.vec3_to_array / array_to_vec3 for vectors); the save
## system sanitises anything else (vectors, colours -> arrays, NaN / INF -> 0, objects -> null).
##
## File safety:
##   * write `<slot>.json.tmp`, read it back and compare, then rotate the previous good file to
##     `<slot>.json.bak` and rename the temp file into place (a corrupt main file is never rotated
##     over a good backup);
##   * loading tries main -> temp -> backup and reports which one was used (last_load_info);
##   * `version` + `format` header, migration from the v1 stub format, files from a newer build are
##     refused (the backup is tried instead);
##   * a provider that is missing at load time gets its blob as soon as it registers; blobs of
##     providers that do not exist in this session are carried over into the next save.
##
## Session flow: autosave every `autosave_interval` seconds of unpaused play (deferred while wanted,
## dead, in a menu or airborne) to slot "autosave"; at EventBus.game_ready the newest real save is
## continued automatically (launch straight into free roam) unless `--new-game` is passed.
## Test runs (--test=...) never continue unless `--continue=<slot>` is given, and saves written
## during tests carry meta.test = true so a later real session never continues from them.

signal save_failed(slot: String, reason: String)
signal load_failed(slot: String, reason: String)
signal autosaved(slot: String)
signal continued(slot: String)

const SAVE_DIR := "user://saves"
const VERSION := 2
const FORMAT := "halcyon_bay_save"
const AUTOSAVE_SLOT := "autosave"
const AUTOSAVE_INTERVAL := 300.0          ## seconds of unpaused play between autosaves
const AUTOSAVE_RETRY := 10.0              ## an unsafe moment postpones the autosave by this much
## Providers are applied in this order (dependencies first): the clock before the weather (wetness
## resync), skills before the player (max health from strength), the player before the vehicles
## (teleport leaves the current car first) and the session last (re-seats the player).
const LOAD_ORDER: Array[String] = ["settings", "clock", "weather", "skills", "wanted", "player", "weapons",
	"wardrobe", "shops", "vehicles", "garage", "session", "interactions", "activities", "radio", "ui_stats"]
## Settings that travel with a save by default (machine-local controls / audio / display stay as the
## user set them on this machine). restore_all_settings = true restores every saved value.
const WORLD_SETTINGS: Array[String] = ["traffic_density", "ped_density"]
const MACHINE_SETTINGS: Array[String] = ["vsync", "max_fps", "render_scale", "shadows"]

var autosave_enabled: bool = true
var autosave_interval: float = AUTOSAVE_INTERVAL
var restore_all_settings: bool = false
var is_loading: bool = false
var last_error: String = ""
## {slot, source: "main"|"temp"|"backup", version, migrated: bool, applied: [...], missing: [...],
##  pending: [...], msec}
var last_load_info: Dictionary = {}
## {slot, reason, bytes, msec, providers: [...], carried: [...]}
var last_save_info: Dictionary = {}
var continued_from: String = ""            ## slot the boot "continue" loaded ("" = new game)
var save_count: int = 0
var load_count: int = 0

var _providers: Dictionary = {}     ## key -> Object
var _pending: Dictionary = {}       ## data loaded before a provider registered
var _carry: Dictionary = {}         ## blobs of providers absent in this session (kept for the next save)
var _autosave_t: float = 0.0
var _is_test_run: bool = false
var _new_game: bool = false
var _continue_slot: String = ""
var _settings_provider: RefCounted = null
var _session_provider: RefCounted = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			_is_test_run = true
		elif a == "--new-game" or a == "--new_game":
			_new_game = true
		elif a.begins_with("--continue="):
			_continue_slot = a.substr(11).strip_edges()
	# test runs never autosave on their own (a long test would overwrite the player's real autosave)
	autosave_enabled = not _is_test_run
	_settings_provider = _SettingsProvider.new(self)
	_session_provider = _SessionProvider.new(self)
	register_provider("settings", _settings_provider)
	register_provider("clock", WorldClock)
	register_provider("weather", Weather)
	register_provider("skills", Skills)
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and wanted.has_method("get_save_data") and wanted.has_method("load_save_data"):
		register_provider("wanted", wanted)
	register_provider("session", _session_provider)
	EventBus.game_ready.connect(_on_game_ready)


# =================================================================================================
# providers
# =================================================================================================

func register_provider(key: String, provider: Object) -> void:
	if key == "" or provider == null:
		return
	_providers[key] = provider
	_carry.erase(key)
	if _pending.has(key) and provider.has_method("load_save_data"):
		var blob: Variant = _pending[key]
		_pending.erase(key)
		if blob is Dictionary:
			provider.load_save_data(blob)


func unregister_provider(key: String) -> void:
	_providers.erase(key)


func has_provider(key: String) -> bool:
	var p: Variant = _providers.get(key, null)
	return p != null and is_instance_valid(p)


func get_provider_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _ordered_keys(_providers.keys()):
		if has_provider(k):
			out.append(k)
	return out


## World systems that implement get_save_data / load_save_data but never registered themselves are
## registered under their system name (radio, a future activities system ...).
func register_system_providers() -> void:
	var known: Array = []
	for k: Variant in _providers:
		known.append(_providers[k])
	for sys_name: Variant in Game.systems.keys():
		var s: Variant = Game.systems[sys_name]
		if not (s is Object) or not is_instance_valid(s):
			continue
		var o := s as Object
		if not (o.has_method("get_save_data") and o.has_method("load_save_data")):
			continue
		if known.has(o) or _providers.has(str(sys_name)):
			continue
		register_provider(str(sys_name), o)
		known.append(o)


# =================================================================================================
# slots and paths
# =================================================================================================

func slot_path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]


func backup_path(slot: String) -> String:
	return slot_path(slot) + ".bak"


func temp_path(slot: String) -> String:
	return slot_path(slot) + ".tmp"


## True if the slot can be loaded (main file, or its backup after a damaged write).
func has_save(slot: String = "quick") -> bool:
	return FileAccess.file_exists(slot_path(slot)) or FileAccess.file_exists(backup_path(slot))


func delete_save(slot: String = "quick") -> void:
	for p: String in [slot_path(slot), backup_path(slot), temp_path(slot)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## Every slot in the save folder: [{slot, meta, valid, source, modified}], newest first.
func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	var seen := {}
	for f: String in dir.get_files():
		var slot := ""
		if f.ends_with(".json"):
			slot = f.trim_suffix(".json")
		elif f.ends_with(".json.bak"):
			slot = f.trim_suffix(".json.bak")
		if slot == "" or seen.has(slot):
			continue
		seen[slot] = true
		var info := get_slot_info(slot)
		out.append({"slot": slot, "meta": info.get("meta", {}), "valid": bool(info.get("valid", false)),
				"source": str(info.get("source", "")), "modified": int(info.get("modified", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _slot_time(a) > _slot_time(b))
	return out


## Header of a slot without loading it: {valid, source, version, meta: {slot, reason, saved_unix,
## datetime, playtime, day, time, district, money, test}, modified}. {"valid": false} if unreadable.
func get_slot_info(slot: String) -> Dictionary:
	for c: Array in [[slot_path(slot), "main"], [temp_path(slot), "temp"], [backup_path(slot), "backup"]]:
		var path: String = c[0]
		if not FileAccess.file_exists(path):
			continue
		var r := _read_file(path)
		if r.is_empty():
			continue
		var data: Dictionary = _migrate(r, slot, path)
		return {"valid": true, "source": c[1], "version": int(r.get("version", 1)),
				"meta": data.get("meta", {}), "modified": int(FileAccess.get_modified_time(path))}
	return {"valid": false}


## Newest loadable slot ("" = none). Saves written by automated tests are skipped unless asked.
func get_latest_slot(include_test: bool = false) -> String:
	for e: Dictionary in list_slots():
		if not bool(e.get("valid", false)):
			continue
		var meta: Dictionary = e.get("meta", {})
		if not include_test and bool(meta.get("test", false)):
			continue
		return str(e["slot"])
	return ""


func _slot_time(e: Dictionary) -> float:
	var meta: Dictionary = e.get("meta", {})
	var t := float(meta.get("saved_unix", 0.0))
	return t if t > 0.0 else float(e.get("modified", 0))


# =================================================================================================
# save
# =================================================================================================

func save_game(slot: String = "quick") -> bool:
	return _save(slot, "autosave" if slot == AUTOSAVE_SLOT else slot)


## Autosave to the "autosave" slot (timer, sleep, other systems). Returns true if written.
func autosave(reason: String = "timer") -> bool:
	var ok := _save(AUTOSAVE_SLOT, reason)
	if ok:
		autosaved.emit(AUTOSAVE_SLOT)
	return ok


func _save(slot: String, reason: String) -> bool:
	var t0 := Time.get_ticks_msec()
	if slot == "" or slot.contains("/") or slot.contains("\\") or slot.contains(".."):
		return _fail_save(slot, "invalid slot name")
	if is_loading:
		return _fail_save(slot, "a load is in progress")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var providers := {}
	var written: Array[String] = []
	for key: String in _ordered_keys(_providers.keys()):
		var p: Variant = _providers[key]
		if p == null or not is_instance_valid(p) or not (p as Object).has_method("get_save_data"):
			continue
		var blob: Variant = (p as Object).call("get_save_data")
		if blob is Dictionary:
			providers[key] = _sanitize(blob, key)
			written.append(key)
		elif blob != null:
			push_warning("SaveSystem: provider '%s' returned %s instead of a Dictionary" % [key, type_string(typeof(blob))])
	var carried: Array[String] = []
	for key: Variant in _carry:
		if not providers.has(key):
			providers[key] = _carry[key]
			carried.append(str(key))
	_fix_airborne_player(providers)
	var data := {
		"format": FORMAT,
		"version": VERSION,
		"meta": _make_meta(slot, reason),
		"money": Game.money,
		"providers": providers,
	}
	var text := JSON.stringify(data, "\t")
	if text == "" or text.length() < 16:
		return _fail_save(slot, "serialisation failed")
	var main := slot_path(slot)
	var tmp := temp_path(slot)
	var bak := backup_path(slot)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _fail_save(slot, "cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
	f.store_string(text)
	var werr := f.get_error()
	f.close()
	if werr != OK:
		_remove(tmp)
		return _fail_save(slot, "write error " + error_string(werr))
	# read the temp file back before it replaces anything
	if FileAccess.get_file_as_string(tmp) != text:
		_remove(tmp)
		return _fail_save(slot, "verification of the written file failed")
	# rotate: previous GOOD file -> .bak (a damaged main file is dropped, the old backup stays)
	if FileAccess.file_exists(main):
		if _read_file(main).is_empty():
			_remove(main)
		else:
			_remove(bak)
			if DirAccess.rename_absolute(_abs(main), _abs(bak)) != OK:
				_remove(main)
	if DirAccess.rename_absolute(_abs(tmp), _abs(main)) != OK:
		# could not move the new file into place: put the previous one back
		if not FileAccess.file_exists(main) and FileAccess.file_exists(bak):
			DirAccess.copy_absolute(_abs(bak), _abs(main))
		return _fail_save(slot, "could not move the temp file into place")
	save_count += 1
	last_error = ""
	last_save_info = {"slot": slot, "reason": reason, "bytes": text.length(), "msec": Time.get_ticks_msec() - t0,
			"providers": written, "carried": carried, "path": main}
	EventBus.save_completed.emit(slot)
	return true


func _fail_save(slot: String, reason: String) -> bool:
	last_error = reason
	push_warning("SaveSystem: save '%s' failed: %s" % [slot, reason])
	save_failed.emit(slot, reason)
	return false


func _make_meta(slot: String, reason: String) -> Dictionary:
	var pos := Game.get_player_position() if Game.has_player() else Vector3.ZERO
	var district := ""
	if Game.world != null and Game.world.has_method("get_district") and Game.has_player():
		district = str(Game.world.call("get_district", pos))
	return {
		"slot": slot,
		"reason": reason,
		"saved_unix": Time.get_unix_time_from_system(),
		"datetime": Time.get_datetime_string_from_system(false, true),
		"playtime": Game.playtime_seconds,
		"day": int(WorldClock.get("day")) if WorldClock.get("day") != null else 1,
		"time": WorldClock.get_time_string() if WorldClock.has_method("get_time_string") else "",
		"district": district,
		"money": Game.money,
		"test": _is_test_run,
		"engine": Engine.get_version_info().get("string", ""),
	}


## A save made while flying would put the player back in mid-air without the aircraft (only
## aircraft on the ground are restored): store the last safe ground position instead.
func _fix_airborne_player(providers: Dictionary) -> void:
	var s: Variant = providers.get("session", null)
	if not (s is Dictionary) or not bool((s as Dictionary).get("airborne", false)):
		return
	var pl: Variant = providers.get("player", null)
	if not (pl is Dictionary) or not Game.has_player():
		return
	var safe: Variant = Game.player.get("last_safe_position")
	var pos: Vector3 = safe if (safe is Vector3 and (safe as Vector3).is_finite()) else Game.get_location("spawn_start").origin
	(pl as Dictionary)["position"] = vec3_to_array(pos)


# =================================================================================================
# load
# =================================================================================================

func load_game(slot: String = "quick") -> bool:
	var t0 := Time.get_ticks_msec()
	if is_loading:
		return _fail_load(slot, "a load is already in progress")
	var data: Dictionary = {}
	var source := ""
	var raw_version := 0
	for c: Array in [[slot_path(slot), "main"], [temp_path(slot), "temp"], [backup_path(slot), "backup"]]:
		var path: String = c[0]
		if not FileAccess.file_exists(path):
			continue
		var r := _read_file(path)
		if r.is_empty():
			push_warning("SaveSystem: %s file of slot '%s' is damaged or from a newer build" % [c[1], slot])
			continue
		raw_version = int(r.get("version", 1))
		data = _migrate(r, slot, path)
		source = c[1]
		break
	if data.is_empty():
		return _fail_load(slot, "no readable save in slot '%s'" % slot)
	is_loading = true
	_pending.clear()
	_carry.clear()
	_reset_transient_state()
	Game.set_money(maxi(int(_num(data.get("money", Game.money), Game.money)), 0))
	var blobs: Dictionary = data.get("providers", {})
	var applied: Array[String] = []
	var pending: Array[String] = []
	for key: String in _ordered_keys(blobs.keys()):
		var blob: Variant = blobs[key]
		if not (blob is Dictionary):
			continue
		var p: Variant = _providers.get(key, null)
		if p != null and is_instance_valid(p) and (p as Object).has_method("load_save_data"):
			(p as Object).call("load_save_data", blob)
			applied.append(key)
		else:
			_pending[key] = blob
			_carry[key] = blob
			pending.append(key)
	var missing: Array[String] = []
	for key: String in _ordered_keys(_providers.keys()):
		if has_provider(key) and not blobs.has(key):
			missing.append(key)
	is_loading = false
	_autosave_t = 0.0
	load_count += 1
	last_error = ""
	last_load_info = {"slot": slot, "source": source, "version": raw_version, "migrated": raw_version < VERSION,
			"applied": applied, "missing": missing, "pending": pending, "msec": Time.get_ticks_msec() - t0,
			"meta": data.get("meta", {})}
	if source != "main":
		push_warning("SaveSystem: slot '%s' loaded from its %s file" % [slot, source])
		var ui := get_node_or_null("/root/UI")
		if ui != null and ui.has_method("notify"):
			ui.call("notify", "Save file was damaged - restored the backup", "warn")
	EventBus.load_completed.emit(slot)
	return true


func _fail_load(slot: String, reason: String) -> bool:
	last_error = reason
	push_warning("SaveSystem: load '%s' failed: %s" % [slot, reason])
	load_failed.emit(slot, reason)
	return false


## Like the respawn flow: chases, police units, transient shop / garage state are dropped before
## the saved state is applied (dynamic world objects are not persisted).
func _reset_transient_state() -> void:
	for key: Variant in Game.systems.keys():
		var s: Variant = Game.systems[key]
		if s is Object and is_instance_valid(s) and (s as Object).has_method("reset_for_respawn"):
			(s as Object).call("reset_for_respawn")
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and wanted.has_method("clear") and int(_num(wanted.get("level"), 0)) > 0:
		wanted.call("clear", "load")


## Parsed + validated file content, or {} (missing, damaged, wrong format, newer version).
func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed
	if not (d.get("providers", null) is Dictionary):
		return {}
	var fmt: Variant = d.get("format", FORMAT)
	if str(fmt) != FORMAT:
		return {}
	var ver := int(_num(d.get("version", 1), 1))
	if ver < 1 or ver > VERSION:
		return {}
	return d


## Brings an older file up to VERSION (v1 = the lead's stub: version, timestamp, money, providers).
func _migrate(d: Dictionary, slot: String, path: String) -> Dictionary:
	var ver := int(_num(d.get("version", 1), 1))
	if ver >= VERSION:
		return d
	var out := d.duplicate()
	if ver < 2:
		out["format"] = FORMAT
		out["meta"] = {"slot": slot, "reason": "legacy", "saved_unix": float(FileAccess.get_modified_time(path)),
				"datetime": str(d.get("timestamp", "")), "playtime": 0.0, "test": false}
	out["version"] = VERSION
	return out


# =================================================================================================
# session: autosave + continue
# =================================================================================================

func _on_game_ready() -> void:
	register_system_providers()
	_autosave_t = 0.0
	if _should_continue():
		_continue_flow.call_deferred()


func _should_continue() -> bool:
	if _new_game or Game.flags.has("no_player"):
		return false
	if _continue_slot != "":
		return true
	return not _is_test_run


## Loads the newest real save (or the --continue=<slot> one) right after boot, behind the loading
## veil. Returns true if a save was continued.
func continue_latest(slot: String = "") -> bool:
	var s := slot if slot != "" else get_latest_slot(false)
	if s == "" or not has_save(s):
		return false
	var ui := get_node_or_null("/root/UI")
	if ui != null and ui.has_method("set_loading_veil"):
		ui.call("set_loading_veil", true)
	await get_tree().process_frame
	var ok := load_game(s)
	# deferred work of the providers (safehouse spawn point, sleeping vehicles) settles first
	for i in 3:
		await get_tree().process_frame
	if ui != null and ui.has_method("set_loading_veil"):
		ui.call("set_loading_veil", false)
	if ok:
		continued_from = s
		var meta: Dictionary = last_load_info.get("meta", {})
		if ui != null and ui.has_method("notify"):
			ui.call("notify", "Continued: day %d, %s" % [int(_num(meta.get("day", 1), 1)), str(meta.get("time", ""))], "info")
		continued.emit(s)
	return ok


func _continue_flow() -> void:
	await continue_latest(_continue_slot)


func _process(delta: float) -> void:
	if not autosave_enabled or not Game.is_ready or is_loading or get_tree().paused:
		return
	_autosave_t += delta
	if _autosave_t < autosave_interval:
		return
	if is_autosave_safe():
		_autosave_t = 0.0
		if autosave("timer"):
			var ui := get_node_or_null("/root/UI")
			if ui != null and ui.has_method("notify"):
				ui.call("notify", "Autosaved", "info", 1.8)
	else:
		_autosave_t = maxf(autosave_interval - AUTOSAVE_RETRY, 0.0)


## A calm moment to autosave: alive, not wanted, no menu, not in a scripted state, not flying.
func is_autosave_safe() -> bool:
	if not Game.has_player():
		return false
	var p := Game.player
	if p.get("is_dead") == true or Game.is_input_locked():
		return false
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and int(_num(wanted.get("level"), 0)) > 0:
		return false
	var rs := Game.get_system("respawn")
	if rs != null and rs.has_method("is_busy") and bool(rs.call("is_busy")):
		return false
	var sid := str(p.get("state_id"))
	if not (sid == "on_foot" or sid == "vehicle" or sid == "swim" or sid == "int_sit" or sid == "int_view"):
		return false
	var v := Game.get_player_vehicle()
	if v != null and _is_airborne(v):
		return false
	return true


static func _is_airborne(v: Node3D) -> bool:
	var cls := str(v.get("vehicle_class"))
	if cls != "heli" and cls != "plane":
		return false
	if v.get("on_ground") == true:
		return false
	var agl: Variant = v.get("altitude_agl")
	if agl is float or agl is int:
		return float(agl) > 2.5
	return v.global_position.y - Game.ground_height(v.global_position.x, v.global_position.z) > 3.0


# =================================================================================================
# helpers
# =================================================================================================

## Keys in LOAD_ORDER first (in that order), then the rest alphabetically.
func _ordered_keys(keys: Array) -> Array[String]:
	var out: Array[String] = []
	for k: String in LOAD_ORDER:
		if keys.has(k):
			out.append(k)
	var rest: Array[String] = []
	for k: Variant in keys:
		var ks := str(k)
		if not LOAD_ORDER.has(ks):
			rest.append(ks)
	rest.sort()
	out.append_array(rest)
	return out


## JSON-safe deep copy: vectors / colours -> arrays, non-finite floats -> 0, objects -> null.
func _sanitize(v: Variant, path: String) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return v
		TYPE_FLOAT:
			if is_finite(v):
				return v
			push_warning("SaveSystem: non-finite number at %s replaced by 0" % path)
			return 0.0
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(v)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return _sanitize([v.x, v.y], path)
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return _sanitize([v.x, v.y, v.z], path)
		TYPE_VECTOR4, TYPE_QUATERNION:
			return _sanitize([v.x, v.y, v.z, v.w], path)
		TYPE_COLOR:
			return _sanitize([v.r, v.g, v.b, v.a], path)
		TYPE_DICTIONARY:
			var out := {}
			for k: Variant in (v as Dictionary):
				out[str(k)] = _sanitize((v as Dictionary)[k], path + "." + str(k))
			return out
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
				TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
				TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var arr: Array = []
			var i := 0
			for e: Variant in v:
				arr.append(_sanitize(e, "%s[%d]" % [path, i]))
				i += 1
			return arr
	push_warning("SaveSystem: %s value at %s is not JSON-safe, stored as null" % [type_string(typeof(v)), path])
	return null


static func _num(v: Variant, def: float) -> float:
	if v is float or v is int:
		return float(v) if is_finite(float(v)) else def
	if v is String and (v as String).is_valid_float():
		return (v as String).to_float()
	return def


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


static func _remove(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func array_to_vec3(a: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		var v := Vector3(_num(a[0], fallback.x), _num(a[1], fallback.y), _num(a[2], fallback.z))
		return v
	return fallback


static func color_to_array(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


static func array_to_color(a: Variant, fallback: Color = Color.WHITE) -> Color:
	if a is Array and (a as Array).size() >= 3:
		return Color(_num(a[0], fallback.r), _num(a[1], fallback.g), _num(a[2], fallback.b),
				_num(a[3], 1.0) if (a as Array).size() > 3 else 1.0)
	return fallback


# =================================================================================================
# built-in providers
# =================================================================================================

## "settings": every Settings value is stored; loading restores the world settings (or all of them
## with restore_all_settings) without writing user://settings.cfg.
class _SettingsProvider extends RefCounted:
	var _sys: Node

	func _init(sys: Node) -> void:
		_sys = sys

	func get_save_data() -> Dictionary:
		var vals: Dictionary = Settings.values
		return {"values": vals.duplicate(true)}

	func load_save_data(d: Dictionary) -> void:
		var vals: Variant = d.get("values", {})
		if not (vals is Dictionary):
			return
		var all := bool(_sys.get("restore_all_settings"))
		for k: Variant in (vals as Dictionary):
			var key := str(k)
			if not Settings.DEFAULTS.has(key):
				continue
			if not all and not WORLD_SETTINGS.has(key):
				continue
			if MACHINE_SETTINGS.has(key):
				continue
			var def: Variant = Settings.DEFAULTS[key]
			var v: Variant = (vals as Dictionary)[k]
			var typed: Variant = null
			match typeof(def):
				TYPE_BOOL:
					typed = v if v is bool else null
				TYPE_INT:
					typed = int(v) if (v is float or v is int) else null
				TYPE_FLOAT:
					typed = float(v) if (v is float or v is int) and is_finite(float(v)) else null
				TYPE_STRING:
					typed = str(v) if v is String else null
			if typed != null and typed != Settings.get_value(key):
				Settings.set_value(key, typed, false)


## "session": play time and the vehicle the player sits in (personal -> re-seated, any other car /
## bike / boat / landed aircraft -> recreated and re-seated; a flight is not restored).
class _SessionProvider extends RefCounted:
	var _sys: Node

	func _init(sys: Node) -> void:
		_sys = sys

	func get_save_data() -> Dictionary:
		var d := {"playtime": Game.playtime_seconds, "vehicle": {}, "airborne": false}
		var v := Game.get_player_vehicle()
		if v == null or not Game.has_player():
			return d
		var seat := int(SaveSystem._num(Game.player.get("seat_index"), 0.0))
		if SaveSystem._is_airborne(v):
			d["airborne"] = true
			return d
		if seat != 0:
			# a passenger (taxi, ride along): the ride is not persisted, the player gets out
			if v.has_method("get_exit_transform"):
				d["exit_position"] = SaveSystem.vec3_to_array((v.call("get_exit_transform", seat) as Transform3D).origin)
			return d
		if v.get("personal") == true:
			d["vehicle"] = {"kind": "personal"}
		elif v.has_method("get_save_data"):
			var blob: Variant = v.call("get_save_data")
			if blob is Dictionary and str((blob as Dictionary).get("spec_id", "")) != "":
				d["vehicle"] = {"kind": "other", "data": blob}
		return d

	func load_save_data(d: Dictionary) -> void:
		Game.playtime_seconds = maxf(SaveSystem._num(d.get("playtime", Game.playtime_seconds), Game.playtime_seconds), 0.0)
		if not Game.has_player():
			return
		var exit_pos: Variant = d.get("exit_position", null)
		if exit_pos is Array and Game.player.has_method("teleport"):
			var p := SaveSystem.array_to_vec3(exit_pos, Game.player.global_position)
			Game.player.call("teleport", p, Game.player.global_rotation.y)
		var info: Variant = d.get("vehicle", {})
		if not (info is Dictionary) or (info as Dictionary).is_empty():
			return
		var kind := str((info as Dictionary).get("kind", ""))
		var v: Node3D = null
		if kind == "personal":
			for sys_name: String in ["garage", "vehicles"]:
				var s := Game.get_system(sys_name)
				if s != null and s.has_method("get_personal_vehicle"):
					v = s.call("get_personal_vehicle") as Node3D
					if v != null:
						break
		elif kind == "other":
			var vm := Game.get_system("vehicles")
			var data: Variant = (info as Dictionary).get("data", {})
			if vm != null and vm.has_method("spawn_from_save") and data is Dictionary:
				v = vm.call("spawn_from_save", data, false) as Node3D
		if v != null and is_instance_valid(v) and Game.player.has_method("enter_vehicle"):
			Game.player.call("enter_vehicle", v, 0, true)
