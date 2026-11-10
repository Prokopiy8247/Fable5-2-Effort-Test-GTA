extends Node
## sav_roundtrip (SAVE module, Wave 3): full game, headless.
##   1. change everything (money, weapons, ammo, attachments + finish tint, appearance, health,
##      armor, parachute, scuba, position, time, weather, skills, wardrobe, unlocked attachments,
##      garage + personal vehicle, activity best score, bank balance, robbed ATM, radio, stats,
##      world + machine settings), save, change it all again, load, compare -> provider table
##   2. file safety: backup rotation, corrupt main -> backup used, corrupt main is not rotated over a
##      good backup, temp-file recovery, v1 migration, newer version refused, extra / missing
##      providers, JSON sanitising
##   3. session: re-seat in a personal car and in a non-personal car after load
##   4. autosave: deferred while wanted, fires when calm; continue_latest(); sleep at the safehouse
## The player's real saves in user://saves and the touched settings are restored at the end.
##
## tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 420 -UserArgs '--test=sav_roundtrip','--test-timeout=380'

const SLOT := "sav_test"
const SLOT_B := "sav_test_b"
const SLOT_C := "sav_test_c"
const SLOT_V1 := "sav_test_v1"
const SLOT_NEW := "sav_test_future"
const TEST_SLOTS: Array[String] = [SLOT, SLOT_B, SLOT_C, SLOT_V1, SLOT_NEW]

var T: Node
var rows: Array = []                 ## [provider, field, ok]
var _user_files: Dictionary = {}     ## file name -> text (the player's own saves, restored at the end)
var _settings_backup: Dictionary = {}
var _probe: RefCounted = null


class _Probe extends RefCounted:
	func get_save_data() -> Dictionary:
		return {"vec": Vector3(1.5, 2.0, -3.0), "col": Color(1, 0, 0, 1), "nan": NAN, "inf": INF, "name": &"sn",
				"nested": {"v2": Vector2(4, 5)}, "packed": PackedInt32Array([1, 2])}

	func load_save_data(_d: Dictionary) -> void:
		pass


func _ready() -> void:
	T = TestHarness
	await T.wait_frames(90)
	_backup_user_files()
	for k: String in ["traffic_density", "ped_density", "mouse_sensitivity", "fov"]:
		_settings_backup[k] = Settings.get_value(k)
	var ok := Game.has_player()
	T.check(ok, "player exists")
	if ok:
		await _phase_roundtrip()
		await _phase_file_safety()
		await _phase_vehicle_session()
		await _phase_autosave_continue()
		await _phase_sleep()
	_print_table()
	_cleanup()
	T.finish()


# =================================================================================================
# 1. round trip
# =================================================================================================

func _phase_roundtrip() -> void:
	var p := Game.player
	var inv: Node = p.get("inventory")
	var shops := Game.get_system("shops")
	var garage := Game.get_system("garage")
	var vm := Game.get_system("vehicles")
	var acts := Game.get_system("activities")
	var radio := Game.get_system("radio")
	var ix := Game.get_system("interactions")
	T.check(SaveSystem.has_provider("player") and SaveSystem.has_provider("weapons"), "player + weapons providers registered")
	T.log_line("providers: %s" % str(SaveSystem.get_provider_keys()))

	# ---------------- state A ----------------
	var base := Game.get_location("downtown_plaza").origin + Vector3(4.0, 0.0, 6.0)
	base.y = Game.ground_height(base.x, base.z) + 0.3
	p.call("teleport", base, 1.0)
	await T.wait_physics_frames(40)
	var pos_a: Vector3 = p.global_position
	Game.set_money(12345)
	p.set("health", 63.0)
	p.set("armor", 40.0)
	p.set("has_parachute", true)
	p.set("has_scuba", true)
	var vis: Node = p.get("visual")
	var opts: Dictionary = vis.call("get_part_options") if vis != null else {}
	var app_a: Dictionary = p.call("get_appearance")
	app_a["hair"] = _pick(opts.get("hair", []), str(app_a.get("hair", "")), 1)
	app_a["top_color"] = _pick(opts.get("top_color", []), str(app_a.get("top_color", "")), 2)
	app_a["bottom"] = _pick(opts.get("bottom", []), str(app_a.get("bottom", "")), 1)
	app_a["hat"] = _pick(opts.get("hat", []), str(app_a.get("hat", "")), 1)
	p.call("set_appearance", app_a)
	app_a = p.call("get_appearance")
	# weapons: pistol with a suppressor-type part + a finish tint, smg with ammo, current = smg
	inv.call("give_weapon", "pistol", 60)
	inv.call("give_weapon", "smg", 120)
	var atts: Array = inv.call("get_compatible_attachments", "pistol")
	var att_part := ""
	var att_tint := ""
	for a: Variant in atts:
		var def: Variant = Registry.get_def("attachments", str(a))
		var kind := str(def.get("kind")) if def != null else ""
		if kind == "finish" and att_tint == "":
			att_tint = str(a)
		elif kind != "finish" and att_part == "":
			att_part = str(a)
	if att_part != "":
		inv.call("add_attachment", "pistol", att_part)
	if att_tint != "":
		inv.call("add_attachment", "pistol", att_tint)
	inv.call("equip", "smg")
	await T.wait_frames(20)
	var weapons_a: Array = (inv.call("get_weapons") as Array).duplicate()
	var ammo_pistol_a: Dictionary = inv.call("get_ammo", "pistol")
	var ammo_smg_a: Dictionary = inv.call("get_ammo", "smg")
	var atts_a: Array = (inv.call("get_attachments", "pistol") as Array).duplicate()
	T.log_line("pistol parts: %s / tint %s -> %s" % [att_part, att_tint, str(atts_a)])
	WorldClock.set_hour(17.25)
	WorldClock.set("day", 4)
	Weather.snap_weather("rain")
	var skills_a := {}
	var lv := 31.0
	for s: String in Skills.SKILLS:
		Skills.set_level(s, lv)
		skills_a[s] = lv
		lv += 7.5
	# wardrobe + unlocked attachment
	var clothing_ids: Array = Registry.ids("clothing")
	var wardrobe: Variant = shops.get("wardrobe") if shops != null else null
	var ward_a: Array = []
	if wardrobe != null and clothing_ids.size() >= 2:
		(wardrobe as Object).call("add", str(clothing_ids[0]))
		(wardrobe as Object).call("add", str(clothing_ids[clothing_ids.size() - 1]))
		ward_a = ((wardrobe as Object).call("get_owned") as Array).duplicate()
	if shops != null and shops.has_method("unlock_attachment") and att_part != "":
		shops.call("unlock_attachment", "pistol", att_part)
	var unlocked_a: Dictionary = (shops.get("unlocked_attachments") as Dictionary).duplicate(true) if shops != null else {}
	# garage: one stored car + a personal car parked nearby
	var stored_a := 0
	var personal_pos := Vector3.INF
	if garage != null and vm != null:
		var xf := Transform3D(Basis(Vector3.UP, 0.4), base + Vector3(-7.0, 0.5, 0.0))
		var c1: Node3D = Game.spawn_vehicle("compact", xf, {"owner_tag": "player"})
		await T.wait_physics_frames(10)
		if c1 != null:
			c1.call("set_paint", Color("#1FA7A0"), Color(0, 0, 0, 0))
			T.check(bool(garage.call("store_vehicle", c1)), "garage stored a compact")
		stored_a = (garage.call("get_stored") as Array).size()
		var c2: Node3D = Game.spawn_vehicle("muscle", Transform3D(Basis(Vector3.UP, 1.2), base + Vector3(9.0, 0.5, 4.0)), {"owner_tag": "player"})
		await T.wait_physics_frames(40)
		if c2 != null:
			c2.call("set_paint", Color("#E8553A"), Color(0, 0, 0, 0))
			garage.call("set_personal_vehicle", c2)
			personal_pos = c2.global_position
	# activities: a best score
	var act_id := ""
	if acts != null and acts.has_method("get_activity_list"):
		for a: Variant in acts.call("get_activity_list"):
			if a is Dictionary:
				act_id = str((a as Dictionary).get("id", ""))
				break
		if act_id != "":
			var rec: Dictionary = acts.call("get_record", act_id)
			rec["best_score"] = 4321
			rec["plays"] = 3
			(acts.get("records") as Dictionary)[act_id] = rec
	# bank + a robbed ATM
	var atm_key := ""
	if ix != null:
		ix.set("bank_balance", 2500)
		var atms: Array = ix.call("get_points", "atm")
		if not atms.is_empty():
			atm_key = str((atms[0] as Dictionary)["key"])
			(ix.get("_robbed") as Dictionary)[atm_key] = float(WorldClock.get("total_hours")) + 10.0
	# radio, stats, settings
	var station_a := ""
	if radio != null and radio.has_method("get_station_ids"):
		var ids: PackedStringArray = radio.call("get_station_ids", false)
		if ids.size() >= 2:
			station_a = ids[1]
			radio.call("set_station", station_a)
	var st: Variant = UI.get("stats")
	if st is Object:
		(st as Object).call("add", "vehicles_stolen", 7.0)
	var stats_stolen_a := float((st as Object).call("get_value", "vehicles_stolen")) if st is Object else 0.0
	Settings.set_value("traffic_density", 0.55, false)
	Settings.set_value("mouse_sensitivity", 0.0031, false)
	var playtime_a := Game.playtime_seconds
	await T.wait_frames(5)

	# ---------------- save ----------------
	T.check(SaveSystem.save_game(SLOT), "save_game(%s)" % SLOT)
	var path := SaveSystem.slot_path(SLOT)
	T.check(FileAccess.file_exists(path) and not FileAccess.file_exists(SaveSystem.temp_path(SLOT)), "file written, no temp file left")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	T.check(parsed is Dictionary and int(parsed.get("version", 0)) == SaveSystem.VERSION and str(parsed.get("format", "")) == SaveSystem.FORMAT, "versioned header")
	var meta: Dictionary = parsed.get("meta", {}) if parsed is Dictionary else {}
	T.check(bool(meta.get("test", false)) and str(meta.get("reason", "")) == SLOT, "meta marks a test save (reason %s)" % str(meta.get("reason", "")))
	T.log_line("save: %s" % str(SaveSystem.last_save_info))

	# ---------------- state B (everything different) ----------------
	p.call("teleport", Game.get_location("beach").origin + Vector3(0, 1, 0), -2.0)
	Game.set_money(77)
	p.set("health", 100.0)
	p.set("armor", 0.0)
	p.set("has_parachute", false)
	p.set("has_scuba", false)
	var app_b: Dictionary = app_a.duplicate()
	app_b["hair"] = _pick(opts.get("hair", []), str(app_a.get("hair", "")), 2)
	app_b["top_color"] = _pick(opts.get("top_color", []), str(app_a.get("top_color", "")), 3)
	p.call("set_appearance", app_b)
	inv.call("remove_weapon", "pistol")
	inv.call("remove_weapon", "smg")
	WorldClock.set_hour(3.0)
	WorldClock.set("day", 9)
	Weather.snap_weather("clear")
	Skills.set_all(5.0)
	if wardrobe != null:
		(wardrobe as Object).call("clear")
	if shops != null:
		(shops.get("unlocked_attachments") as Dictionary).clear()
	if garage != null:
		while (garage.call("get_stored") as Array).size() > 0:
			garage.call("remove_stored", 0)
		var pv: Node3D = garage.call("get_personal_vehicle")
		if pv != null and vm != null:
			vm.call("despawn_vehicle", pv)
	if acts != null and act_id != "":
		(acts.get("records") as Dictionary).erase(act_id)
	if ix != null:
		ix.set("bank_balance", 0)
		(ix.get("_robbed") as Dictionary).clear()
	if radio != null and station_a != "":
		radio.call("set_station", "")
	if st is Object:
		(st as Object).call("reset")
	Settings.set_value("traffic_density", 1.2, false)
	Settings.set_value("mouse_sensitivity", 0.0019, false)
	Wanted.set_level(2)
	await T.wait_physics_frames(30)

	# ---------------- load ----------------
	T.check(SaveSystem.load_game(SLOT), "load_game(%s)" % SLOT)
	await T.wait_physics_frames(30)
	T.log_line("load: %s" % str(SaveSystem.last_load_info))
	T.check(str(SaveSystem.last_load_info.get("source", "")) == "main", "loaded from the main file")

	# ---------------- compare ----------------
	_row("money", "money", Game.money == 12345, "%d" % Game.money)
	var pos_b: Vector3 = p.global_position
	_row("player", "position", pos_b.distance_to(pos_a) < 0.6, "%s vs %s" % [str(pos_b), str(pos_a)])
	_row("player", "yaw", absf(angle_difference(p.global_rotation.y, 1.0)) < 0.05, "%.2f" % p.global_rotation.y)
	_row("player", "health", absf(float(p.get("health")) - 63.0) < 0.5, str(p.get("health")))
	_row("player", "armor", absf(float(p.get("armor")) - 40.0) < 0.5, str(p.get("armor")))
	_row("player", "parachute", p.get("has_parachute") == true, str(p.get("has_parachute")))
	_row("player", "scuba", p.get("has_scuba") == true, str(p.get("has_scuba")))
	var app_now: Dictionary = p.call("get_appearance")
	var app_ok := true
	for k: String in ["hair", "top_color", "bottom", "hat"]:
		app_ok = app_ok and str(app_now.get(k, "")) == str(app_a.get(k, ""))
	_row("player", "appearance", app_ok, "%s/%s/%s/%s" % [app_now.get("hair"), app_now.get("top_color"), app_now.get("bottom"), app_now.get("hat")])
	var weapons_now: Array = inv.call("get_weapons")
	_row("weapons", "owned", weapons_now.has("pistol") and weapons_now.has("smg") and weapons_now.size() == weapons_a.size(), str(weapons_now))
	var ap: Dictionary = inv.call("get_ammo", "pistol")
	var asmg: Dictionary = inv.call("get_ammo", "smg")
	_row("weapons", "ammo (mag + reserve)", ap == ammo_pistol_a and asmg == ammo_smg_a, "%s %s" % [str(ap), str(asmg)])
	var atts_now: Array = inv.call("get_attachments", "pistol")
	_row("weapons", "attachments", att_part == "" or atts_now.has(att_part), str(atts_now))
	_row("weapons", "tint (finish)", att_tint == "" or atts_now.has(att_tint), att_tint)
	_row("weapons", "current", str(inv.get("current_id")) == "smg", str(inv.get("current_id")))
	var saved_hour := float((((parsed.get("providers", {}) as Dictionary).get("clock", {})) as Dictionary).get("hour", -1.0))
	_row("clock", "hour", absf(saved_hour - 17.25) < 0.02 and absf(WorldClock.hour - saved_hour) < 0.05, "%.3f (saved %.3f)" % [WorldClock.hour, saved_hour])
	_row("clock", "day", int(WorldClock.get("day")) == 4, str(WorldClock.get("day")))
	_row("weather", "current", str(Weather.current) == "rain", str(Weather.current))
	var sk_ok := true
	for s: String in Skills.SKILLS:
		sk_ok = sk_ok and absf(Skills.get_level(s) - float(skills_a[s])) < 0.01
	_row("skills", "7 levels", sk_ok, str(Skills.levels))
	var mh := float(p.get("max_health"))
	_row("skills", "strength max health", absf(mh - Skills.get_strength_max_health(100.0)) < 0.2 and mh > 100.0, "%.1f" % mh)
	if wardrobe != null:
		var ward_now: Array = (wardrobe as Object).call("get_owned")
		var w_ok := ward_now.size() == ward_a.size()
		for id: Variant in ward_a:
			w_ok = w_ok and ward_now.has(id)
		_row("wardrobe", "owned clothes", w_ok and not ward_a.is_empty(), str(ward_now.size()))
	if shops != null:
		_row("shops", "unlocked attachments", (shops.get("unlocked_attachments") as Dictionary).size() == unlocked_a.size(), str(unlocked_a.keys()))
	if garage != null:
		var stored_now: Array = garage.call("get_stored")
		var g_ok := stored_now.size() == stored_a and stored_a >= 1
		if g_ok:
			var d: Dictionary = stored_now[stored_now.size() - 1]
			g_ok = str(d.get("spec_id", "")) == "compact" and SaveSystem.array_to_color(d.get("primary", null), Color.BLACK).is_equal_approx(Color("#1FA7A0"))
		_row("garage", "stored vehicles", g_ok, str(stored_now.size()))
		var pv: Node3D = garage.call("get_personal_vehicle")
		var pv_ok := pv != null and str(pv.get("spec_id")) == "muscle" and pv.global_position.distance_to(personal_pos) < 1.5
		_row("vehicles", "personal vehicle", pv_ok, str(pv.global_position) if pv != null else "none")
		if pv != null:
			_row("vehicles", "personal paint", (pv.get("paint_primary") as Color).is_equal_approx(Color("#E8553A")), str(pv.get("paint_primary")))
	if acts != null and act_id != "":
		var rec_now: Dictionary = acts.call("get_record", act_id)
		_row("activities", "best score", int(rec_now.get("best_score", -1)) == 4321 and int(rec_now.get("plays", 0)) == 3, act_id)
	if ix != null:
		_row("interactions", "bank balance", int(ix.get("bank_balance")) == 2500, str(ix.get("bank_balance")))
		if atm_key != "":
			_row("interactions", "robbed ATM", (ix.get("_robbed") as Dictionary).has(atm_key), atm_key)
	if radio != null and station_a != "":
		_row("radio", "station", str(radio.call("get_station")) == station_a, str(radio.call("get_station")))
	if st is Object:
		_row("ui_stats", "vehicles_stolen", absf(float((st as Object).call("get_value", "vehicles_stolen")) - stats_stolen_a) < 0.01, str(stats_stolen_a))
	_row("settings", "traffic_density (restored)", absf(float(Settings.get_value("traffic_density")) - 0.55) < 0.001, str(Settings.get_value("traffic_density")))
	_row("settings", "mouse_sensitivity (machine-local, kept)", absf(float(Settings.get_value("mouse_sensitivity")) - 0.0019) < 0.00001, str(Settings.get_value("mouse_sensitivity")))
	var saved_settings: Dictionary = ((parsed.get("providers", {}) as Dictionary).get("settings", {}) as Dictionary).get("values", {})
	_row("settings", "all values in the file", absf(float(saved_settings.get("mouse_sensitivity", 0.0)) - 0.0031) < 0.00001, "%d keys" % saved_settings.size())
	_row("session", "playtime", absf(Game.playtime_seconds - playtime_a) < 2.0, "%.1f" % Game.playtime_seconds)
	_row("wanted", "cleared on load", Wanted.level == 0, str(Wanted.level))
	# restore_all_settings path
	SaveSystem.restore_all_settings = true
	T.check(SaveSystem.load_game(SLOT), "reload with restore_all_settings")
	_row("settings", "mouse_sensitivity (restore_all)", absf(float(Settings.get_value("mouse_sensitivity")) - 0.0031) < 0.00001, str(Settings.get_value("mouse_sensitivity")))
	SaveSystem.restore_all_settings = false
	await T.wait_physics_frames(10)


# =================================================================================================
# 2. file safety
# =================================================================================================

func _phase_file_safety() -> void:
	Game.set_money(1111)
	T.check(SaveSystem.save_game(SLOT_B), "save B1")
	Game.set_money(2222)
	T.check(SaveSystem.save_game(SLOT_B), "save B2")
	var bak := SaveSystem.backup_path(SLOT_B)
	_row("file", "backup of the previous file", FileAccess.file_exists(bak) and _money_in(bak) == 1111 and _money_in(SaveSystem.slot_path(SLOT_B)) == 2222,
			"bak %d main %d" % [_money_in(bak), _money_in(SaveSystem.slot_path(SLOT_B))])
	# corrupt the main file -> load uses the backup
	_write(SaveSystem.slot_path(SLOT_B), "{\"format\": \"halcyon_bay_save\", \"version\": 2, \"providers\": {\"pla")
	Game.set_money(5)
	var ok := SaveSystem.load_game(SLOT_B)
	await T.wait_physics_frames(5)
	_row("file", "corrupt main -> backup loaded", ok and str(SaveSystem.last_load_info.get("source", "")) == "backup" and Game.money == 1111,
			"%s money %d" % [str(SaveSystem.last_load_info.get("source", "")), Game.money])
	# saving over a corrupt main keeps the good backup
	Game.set_money(3333)
	T.check(SaveSystem.save_game(SLOT_B), "save B3 over a corrupt main")
	_row("file", "corrupt main never rotated over the backup", _money_in(bak) == 1111 and _money_in(SaveSystem.slot_path(SLOT_B)) == 3333,
			"bak %d main %d" % [_money_in(bak), _money_in(SaveSystem.slot_path(SLOT_B))])
	# temp-file recovery (crash between writing the temp file and the rename)
	var good := FileAccess.get_file_as_string(SaveSystem.slot_path(SLOT_B))
	_write(SaveSystem.temp_path(SLOT_B), good)
	_write(SaveSystem.slot_path(SLOT_B), "")
	Game.set_money(6)
	ok = SaveSystem.load_game(SLOT_B)
	_row("file", "empty main -> complete temp file loaded", ok and str(SaveSystem.last_load_info.get("source", "")) == "temp" and Game.money == 3333,
			str(SaveSystem.last_load_info.get("source", "")))
	SaveSystem.delete_save(SLOT_B)
	_row("file", "delete_save removes main/bak/tmp", not FileAccess.file_exists(bak) and not SaveSystem.has_save(SLOT_B)
			and not FileAccess.file_exists(SaveSystem.temp_path(SLOT_B)), "")
	# v1 (contract stub format) migration
	var hour_before := WorldClock.hour
	_write(SaveSystem.slot_path(SLOT_V1), JSON.stringify({"version": 1, "timestamp": "2026-11-09T22:00:00", "money": 4242,
			"providers": {"clock": {"hour": 9.5, "day": 2, "total_hours": 33.5}}}))
	ok = SaveSystem.load_game(SLOT_V1)
	_row("file", "v1 file migrated + loaded", ok and Game.money == 4242 and absf(WorldClock.hour - 9.5) < 0.02 and bool(SaveSystem.last_load_info.get("migrated", false)),
			"hour %.2f (was %.2f)" % [WorldClock.hour, hour_before])
	# a file from a newer build is refused (nothing applied)
	_write(SaveSystem.slot_path(SLOT_NEW), JSON.stringify({"format": SaveSystem.FORMAT, "version": 99, "money": 99999, "providers": {}}))
	ok = SaveSystem.load_game(SLOT_NEW)
	_row("file", "newer version refused", not ok and Game.money == 4242, SaveSystem.last_error)
	# extra provider (absent in this session) is kept and carried into the next save; a missing
	# provider keeps its current state
	Skills.set_level("lung", 66.0)
	_write(SaveSystem.slot_path(SLOT_V1), JSON.stringify({"format": SaveSystem.FORMAT, "version": 2, "meta": {"test": true},
			"money": 4343, "providers": {"ghost_system": {"answer": 42}, "clock": {"hour": 11.0, "day": 3, "total_hours": 60.0}}}))
	ok = SaveSystem.load_game(SLOT_V1)
	var pend: Array = SaveSystem.last_load_info.get("pending", [])
	_row("file", "extra provider tolerated (pending)", ok and pend.has("ghost_system") and Game.money == 4343, str(pend))
	_row("file", "missing provider keeps its state", absf(Skills.get_level("lung") - 66.0) < 0.01 and (SaveSystem.last_load_info.get("missing", []) as Array).has("skills"),
			str(SaveSystem.last_load_info.get("missing", [])))
	_probe = _Probe.new()
	SaveSystem.register_provider("zz_probe", _probe)
	T.check(SaveSystem.save_game(SLOT_V1), "save with a carried + an unsafe provider")
	var re: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.slot_path(SLOT_V1)))
	var provs: Dictionary = re.get("providers", {}) if re is Dictionary else {}
	_row("file", "carried provider kept in the next save", provs.has("ghost_system") and int((provs["ghost_system"] as Dictionary).get("answer", 0)) == 42, "")
	var pr: Dictionary = provs.get("zz_probe", {})
	var vec: Variant = pr.get("vec", null)
	var san_ok: bool = vec is Array and (vec as Array).size() == 3 and absf(float(vec[2]) + 3.0) < 0.001 \
			and float(pr.get("nan", 1.0)) == 0.0 and float(pr.get("inf", 1.0)) == 0.0 and str(pr.get("name", "")) == "sn" \
			and (pr.get("nested", {}) as Dictionary).get("v2", null) is Array and pr.get("packed", null) is Array
	_row("file", "JSON sanitising (vectors, NaN, INF, packed)", san_ok, str(pr))
	SaveSystem.unregister_provider("zz_probe")
	_probe = null
	# registering late applies a pending blob
	var late := _LateProbe.new()
	SaveSystem.register_provider("ghost_system", late)
	_row("file", "late provider receives its pending blob", int(late.got.get("answer", 0)) == 42, str(late.got))
	SaveSystem.unregister_provider("ghost_system")


class _LateProbe extends RefCounted:
	var got: Dictionary = {}

	func get_save_data() -> Dictionary:
		return got

	func load_save_data(d: Dictionary) -> void:
		got = d


# =================================================================================================
# 3. vehicle session
# =================================================================================================

func _phase_vehicle_session() -> void:
	var p := Game.player
	var garage := Game.get_system("garage")
	var vm := Game.get_system("vehicles")
	if vm == null:
		T.log_line("vehicles system missing: vehicle session skipped")
		return
	var spot := Game.get_location("downtown_plaza").origin + Vector3(-6.0, 0.0, -10.0)
	spot.y = Game.ground_height(spot.x, spot.z) + 0.2
	p.call("teleport", spot, 0.0)
	await T.wait_physics_frames(20)
	# (a) a non-personal car
	var car: Node3D = Game.spawn_vehicle("taxi", Transform3D(Basis(Vector3.UP, 0.3), spot + Vector3(3.0, 0.4, 0.0)), {"owner_tag": "civilian"})
	await T.wait_physics_frames(30)
	if car == null:
		T.check(false, "spawn a taxi")
		return
	p.call("enter_vehicle", car, 0, true)
	await T.wait_physics_frames(30)
	T.check(Game.get_player_vehicle() == car, "player seated in the taxi")
	T.check(SaveSystem.save_game(SLOT_C), "save while driving a taxi")
	p.call("exit_vehicle")
	await T.wait_physics_frames(60)
	vm.call("despawn_vehicle", car)
	p.call("teleport", spot + Vector3(30.0, 0.0, 0.0), 0.0)
	await T.wait_physics_frames(10)
	T.check(SaveSystem.load_game(SLOT_C), "load the driving save")
	await T.wait_physics_frames(30)
	var v := Game.get_player_vehicle()
	_row("session", "re-seated in a recreated non-personal car", v != null and str(v.get("spec_id")) == "taxi", str(v.get("spec_id")) if v != null else "on foot")
	# (b) the personal car
	if v != null:
		p.call("exit_vehicle")
		await T.wait_physics_frames(60)
		vm.call("despawn_vehicle", v)
	if garage != null:
		var pv: Node3D = garage.call("get_personal_vehicle")
		if pv == null:
			pv = Game.spawn_vehicle("muscle", Transform3D(Basis.IDENTITY, spot + Vector3(-3.0, 0.4, 0.0)), {"owner_tag": "player"})
			await T.wait_physics_frames(30)
			garage.call("set_personal_vehicle", pv)
		p.call("enter_vehicle", pv, 0, true)
		await T.wait_physics_frames(30)
		T.check(SaveSystem.save_game(SLOT_C), "save while driving the personal car")
		p.call("exit_vehicle")
		await T.wait_physics_frames(60)
		p.call("teleport", spot + Vector3(25.0, 0.0, 5.0), 0.0)
		await T.wait_physics_frames(10)
		T.check(SaveSystem.load_game(SLOT_C), "load the personal-car save")
		await T.wait_physics_frames(30)
		var v2 := Game.get_player_vehicle()
		var npv: Node3D = garage.call("get_personal_vehicle")
		_row("session", "re-seated in the personal car", v2 != null and v2 == npv, str(v2.get("spec_id")) if v2 != null else "on foot")
		var n_personal := 0
		for n: Node in get_tree().get_nodes_in_group("vehicle"):
			if n.get("personal") == true:
				n_personal += 1
		_row("vehicles", "no duplicate personal car", n_personal == 1, "%d" % n_personal)
		if v2 != null:
			p.call("exit_vehicle")
			await T.wait_physics_frames(60)


# =================================================================================================
# 4. autosave, continue, sleep
# =================================================================================================

func _phase_autosave_continue() -> void:
	var p := Game.player
	var spot := Game.get_location("residential_park").origin
	spot.y = Game.ground_height(spot.x, spot.z) + 0.3
	p.call("teleport", spot, 0.5)
	await T.wait_physics_frames(30)
	SaveSystem.delete_save(SaveSystem.AUTOSAVE_SLOT)
	SaveSystem.autosave_interval = 1.0
	Wanted.set_level(1)
	SaveSystem.autosave_enabled = true
	await T.wait_seconds(2.5)
	_row("autosave", "deferred while wanted", not SaveSystem.has_save(SaveSystem.AUTOSAVE_SLOT), "")
	Wanted.clear("cheat")
	await T.wait_seconds(2.5)
	SaveSystem.autosave_enabled = false
	SaveSystem.autosave_interval = SaveSystem.AUTOSAVE_INTERVAL
	var info := SaveSystem.get_slot_info(SaveSystem.AUTOSAVE_SLOT)
	var meta: Dictionary = info.get("meta", {})
	_row("autosave", "fires when calm (5 min of play by default)", bool(info.get("valid", false)) and str(meta.get("reason", "")) == "timer",
			str(meta.get("reason", "")))
	# newest slot / continue
	var latest := SaveSystem.get_latest_slot(true)
	_row("continue", "newest slot found", latest == SaveSystem.AUTOSAVE_SLOT, latest)
	var real := SaveSystem.get_latest_slot(false)
	var real_meta: Dictionary = SaveSystem.get_slot_info(real).get("meta", {}) if real != "" else {}
	_row("continue", "test saves never continued", real == "" or not bool(real_meta.get("test", false)), real)
	var target: Vector3 = p.global_position
	p.call("teleport", Game.get_location("hill_top").origin + Vector3(4, 1, 4), 0.0)
	Game.set_money(12)
	await T.wait_physics_frames(10)
	var ok: bool = await SaveSystem.continue_latest(SaveSystem.AUTOSAVE_SLOT)
	await T.wait_physics_frames(20)
	_row("continue", "continue_latest() restores the slot", ok and SaveSystem.continued_from == SaveSystem.AUTOSAVE_SLOT
			and p.global_position.distance_to(target) < 1.0 and Game.money != 12, "%s %s" % [SaveSystem.continued_from, str(p.global_position)])
	T.log_line("loading veil visible after continue: %s" % str(UI.call("is_loading_veil_visible")))


func _phase_sleep() -> void:
	var garage := Game.get_system("garage")
	var sh: Variant = garage.call("get_helper", "safehouse") if garage != null and garage.has_method("get_helper") else null
	if sh == null or not (sh as Object).has_method("sleep"):
		T.log_line("safehouse helper missing: sleep autosave not verified")
		return
	Wanted.clear("cheat")
	var before := SaveSystem.save_count
	var slot := str((sh as Object).get("save_slot"))
	var slept: bool = await sh.sleep()
	await T.wait_frames(5)
	var info := SaveSystem.get_slot_info(slot)
	_row("autosave", "sleeping at the safehouse saves (slot %s)" % slot, slept and SaveSystem.save_count > before and bool(info.get("valid", false)), str(slept))


# =================================================================================================
# helpers
# =================================================================================================

func _row(provider: String, field: String, ok: bool, detail: String) -> void:
	rows.append([provider, field, ok, detail])
	T.check(ok, "%s.%s (%s)" % [provider, field, detail])


func _print_table() -> void:
	T.log_line("| provider | field | result | detail |")
	T.log_line("|---|---|---|---|")
	for r: Array in rows:
		T.log_line("| %s | %s | %s | %s |" % [r[0], r[1], "OK" if r[2] else "FAIL", str(r[3]).left(70)])


static func _pick(options: Variant, current: String, nth: int) -> String:
	if not (options is Array) or (options as Array).is_empty():
		return current
	var arr: Array = options
	var n := 0
	for o: Variant in arr:
		if str(o) != current and str(o) != "":
			n += 1
			if n >= nth:
				return str(o)
	return current


func _money_in(path: String) -> int:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return int(v.get("money", -1)) if v is Dictionary else -1


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSystem.SAVE_DIR))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _backup_user_files() -> void:
	var dir := DirAccess.open(SaveSystem.SAVE_DIR)
	if dir == null:
		return
	for f: String in dir.get_files():
		_user_files[f] = FileAccess.get_file_as_bytes(SaveSystem.SAVE_DIR + "/" + f)
	T.log_line("backed up %d user save files" % _user_files.size())


func _cleanup() -> void:
	for s: String in TEST_SLOTS:
		SaveSystem.delete_save(s)
	# put the player's own files back exactly as they were (autosave / manual / quick included)
	var dir := DirAccess.open(SaveSystem.SAVE_DIR)
	if dir != null:
		for f: String in dir.get_files():
			if not _user_files.has(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.SAVE_DIR + "/" + f))
	for f: String in _user_files:
		var h := FileAccess.open(SaveSystem.SAVE_DIR + "/" + f, FileAccess.WRITE)
		if h != null:
			h.store_buffer(_user_files[f])
			h.close()
	for k: String in _settings_backup:
		Settings.set_value(k, _settings_backup[k], false)
	Settings.save_settings()
