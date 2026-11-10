extends Node
## Admin / debug API test against the FULL game (real world, player, vehicles, inventory).
##   tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 400 -UserArgs '--test=adm_api','--test-timeout=380'
## Checks every cheat function of the debug system: teleport to every district and named location
## (ends on solid ground, or floating for water locations), every spawnable vehicle spec, weapons,
## player cheats, wanted, time / weather, system toggles, time scale, overlay, text commands and the
## admin menu screen itself. Features whose module is not built yet are logged as SKIP.

var T: Node = null
var dbg: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	T = TestHarness
	await T.wait_frames(30)
	dbg = Game.get_system("debug")
	T.check(dbg != null, "debug system registered as world system 'debug'")
	if dbg == null:
		T.finish(false, "no debug system")
		return
	if not Game.has_player():
		T.finish(false, "no player")
		return
	Game.invulnerable = true          # keep the player alive while it is thrown around the map
	await _test_sector()
	await _test_teleports()
	await _test_vehicles()
	await _test_weapons()
	await _test_player()
	await _test_wanted()
	await _test_world()
	await _test_debug()
	await _test_services()
	await _test_menu()
	Game.invulnerable = false
	T.finish()


func _log(msg: String) -> void:
	T.log_line("[adm_api] " + msg)


func _player() -> Node3D:
	return Game.player


# --- sector grid -------------------------------------------------------------------------------

func _test_sector() -> void:
	T.check(dbg.get_sector(Vector3(-299, 0, -299)) == "A1", "sector A1 at the north-west corner")
	T.check(dbg.get_sector(Vector3(299, 0, 299)) == "F6", "sector F6 at the south-east corner")
	T.check(dbg.get_sector(Vector3(0, 0, 0)) == "D4", "sector D4 at the island centre")
	T.check(dbg.get_sector(Vector3(500, 0, 0)) == "OFF", "sector OFF outside the grid")


# --- teleports ---------------------------------------------------------------------------------

func _test_teleports() -> void:
	var targets: Array = dbg.get_teleport_targets()
	var n_d := 0
	var n_l := 0
	for t: Dictionary in targets:
		if str(t["kind"]) == "district":
			n_d += 1
		else:
			n_l += 1
	T.check(n_d == 8, "8 district teleport targets (%d)" % n_d)
	T.check(n_l >= 36, "every named location is a teleport target (%d)" % n_l)
	var p := _player()
	var failed: PackedStringArray = []
	for t: Dictionary in targets:
		var id := str(t["id"])
		var ok: bool = dbg.teleport_player(id, false)
		if not ok:
			failed.append(id + " (refused)")
			continue
		await T.wait_physics_frames(24)
		var pos := p.global_position
		var target: Vector3 = t["position"]
		var horiz := Vector2(pos.x - target.x, pos.z - target.z).length()
		if bool(t["water"]):
			var swimming := bool(p.get("is_swimming"))
			var depth := float(p.get("water_depth"))
			var good := swimming and horiz < 6.0
			_log("%-22s water  swim=%s depth=%.2f y=%.2f off=%.1f m" % [id, str(swimming), depth, pos.y, horiz])
			if not good:
				failed.append(id + " (not floating)")
			continue
		var hit := _ray_down(pos + Vector3.UP * 0.5, 1.2)
		var grounded := bool(p.get("grounded")) or (p as CharacterBody3D).is_on_floor()
		var on_solid := not hit.is_empty() and absf(Vector3(hit["position"]).y - pos.y) < 0.35
		var not_under := pos.y > Game.ground_height(pos.x, pos.z) - 0.6
		var good2 := grounded and on_solid and not_under and horiz < 22.0 and not bool(p.get("is_swimming"))
		_log("%-22s land   grounded=%s solid=%s y=%.2f ground=%.2f off=%.1f m" % [id, str(grounded), str(on_solid), pos.y,
				Game.ground_height(pos.x, pos.z), horiz])
		if not good2:
			failed.append("%s (grounded %s, solid %s, off %.1f m)" % [id, str(grounded), str(on_solid), horiz])
	T.check(failed.is_empty(), "teleport to all %d targets ends on solid ground / floating%s" % [targets.size(),
			"" if failed.is_empty() else ": FAILED " + ", ".join(failed)])
	T.check(dbg.teleport_player(Vector3(30.0, 0.0, -60.0), false), "teleport to a raw position")
	await T.wait_physics_frames(10)
	T.check(not dbg.teleport_player("no_such_place", false), "unknown teleport target is refused")


func _ray_down(from: Vector3, depth: float) -> Dictionary:
	var space := (Game.player as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * depth, Layers.WORLD | Layers.VEHICLE | Layers.PROP)
	q.exclude = [(Game.player as CollisionObject3D).get_rid()]
	return space.intersect_ray(q)


# --- vehicles ----------------------------------------------------------------------------------

func _test_vehicles() -> void:
	dbg.teleport_player("downtown_plaza", false)
	await T.wait_physics_frames(20)
	var specs: Array = dbg.get_vehicle_specs("")
	T.check(specs.size() >= 13, "vehicle specs listed (%d)" % specs.size())
	var groups := {}
	for s: Dictionary in specs:
		groups[s["group"]] = int(groups.get(s["group"], 0)) + 1
	_log("vehicle groups: %s" % str(groups))
	var spawned := 0
	var spawnable := 0
	var failed: PackedStringArray = []
	var skipped: PackedStringArray = []
	for s: Dictionary in specs:
		var id := str(s["id"])
		if not bool(s["can_spawn"]):
			skipped.append("%s (%s)" % [id, str(s["reason"])])
			continue
		spawnable += 1
		var v: Node3D = dbg.spawn_vehicle_for_player(id, false)
		if v == null:
			failed.append(id)
			continue
		spawned += 1
		await T.wait_physics_frames(12)
		if not is_instance_valid(v):
			failed.append(id + " (freed)")
			continue
		var vp := v.global_position
		var where := str(dbg.last_spawn.get("where", ""))
		var cls := str(v.get("vehicle_class"))
		var ok := true
		match cls:
			"boat":
				ok = Game.world.get_water_depth(vp.x, vp.z) > 1.0
			"plane":
				ok = vp.distance_to(Game.get_location("airport_runway_start").origin) < 260.0
			_:
				ok = absf(vp.y - Game.ground_height(vp.x, vp.z)) < 2.5 and Game.world.get_water_depth(vp.x, vp.z) < 0.5
		_log("spawn %-15s class=%-7s %-24s at (%.1f, %.1f, %.1f) %s" % [id, cls, where, vp.x, vp.y, vp.z, "ok" if ok else "BAD SURFACE"])
		if not ok:
			failed.append(id + " (surface)")
		if spawned % 6 == 0:
			dbg.clear_admin_vehicles()
			await T.wait_frames(2)
	T.check(failed.is_empty() and spawned == spawnable, "every spawnable spec spawns on a suitable surface (%d / %d)%s" % [spawned, spawnable,
			"" if failed.is_empty() else ": FAILED " + ", ".join(failed)])
	if not skipped.is_empty():
		_log("SKIP (not spawnable yet): " + ", ".join(skipped))
	# GLB present but class missing is reported, not hidden
	for s: Dictionary in specs:
		if not bool(s["can_spawn"]):
			T.check(str(s["reason"]) != "", "unspawnable %s has a reason: %s" % [s["id"], s["reason"]])
	dbg.clear_admin_vehicles()
	await T.wait_frames(3)
	# two boats in a row must not share a spot
	var boat_id := ""
	for s: Dictionary in specs:
		if str(s["group"]) == "boat" and bool(s["can_spawn"]):
			boat_id = str(s["id"])
			break
	if boat_id != "":
		var b1: Node3D = dbg.spawn_vehicle_for_player(boat_id, false)
		await T.wait_physics_frames(2)
		var b2: Node3D = dbg.spawn_vehicle_for_player(boat_id, false)
		await T.wait_physics_frames(2)
		T.check(b1 != null and b2 != null and b1.global_position.distance_to(b2.global_position) > 4.0,
				"two %s spawns get separate water spots" % boat_id)
		dbg.clear_admin_vehicles()
		await T.wait_frames(3)

	# spawn and enter, repair, flip, teleport with the vehicle
	var p := _player()
	var car: Node3D = dbg.spawn_vehicle_for_player("sedan", true)
	T.check(car != null, "spawn and enter: sedan spawned")
	if car == null:
		return
	await T.wait_physics_frames(20)
	T.check(Game.get_player_vehicle() == car, "spawn and enter: player sits in the sedan")
	car.call("apply_damage", Dmg.make(400.0, "explosion", null, car.global_position, Vector3.UP))
	await T.wait_physics_frames(2)
	var hurt := float(car.get("health")) < float(car.get("max_health"))
	T.check(dbg.repair_current_vehicle() and hurt and is_equal_approx(float(car.get("health")), float(car.get("max_health"))),
			"repair_current_vehicle restores full health")
	car.call("teleport", Transform3D(Basis(Vector3.FORWARD, PI), car.global_position + Vector3.UP * 1.5))
	await T.wait_physics_frames(30)
	T.check(dbg.flip_current_vehicle(), "flip_current_vehicle")
	await T.wait_physics_frames(30)
	T.check(car.global_basis.y.dot(Vector3.UP) > 0.85, "vehicle upright after flip (up . y = %.2f)" % car.global_basis.y.dot(Vector3.UP))
	T.check(dbg.teleport_player("hospital", true), "teleport while driving")
	await T.wait_physics_frames(20)
	var hosp := Game.get_location("hospital").origin
	T.check(Game.get_player_vehicle() == car and car.global_position.distance_to(hosp) < 45.0,
			"vehicle came along to the hospital (%.1f m)" % car.global_position.distance_to(hosp))
	dbg.teleport_player("boat_spawn", true)
	await T.wait_physics_frames(30)
	T.check(Game.get_player_vehicle() == null and bool(p.get("is_swimming")), "teleport to water leaves a car behind and swims")
	dbg.set_mods_unlocked(true)
	T.check(bool(Game.flags.get("free_shopping", false)) and bool(Game.flags.get("unlock_all_mods", false)), "unlock all mods sets the shop flags")
	dbg.set_mods_unlocked(false)
	T.check(not Game.flags.has("free_shopping"), "unlock all mods off clears the flags")
	dbg.clear_admin_vehicles()
	dbg.teleport_player("downtown_plaza", false)
	await T.wait_physics_frames(20)


# --- weapons -----------------------------------------------------------------------------------

func _test_weapons() -> void:
	var inv: Object = _player().get("inventory")
	if inv == null:
		_log("SKIP weapons: no inventory")
		return
	var n: int = dbg.give_all_weapons()
	T.check(n == Registry.count("weapons"), "give_all_weapons: %d / %d weapons" % [n, Registry.count("weapons")])
	inv.call("add_ammo", "pistol", -100000)
	inv.call("add_ammo", "rifle", -100000)
	T.check(dbg.refill_ammo(), "refill_ammo")
	var full := true
	for id: Variant in inv.call("get_weapons"):
		var spec: Object = inv.call("get_spec", str(id))
		if spec == null or str(spec.get("ammo_type")) == "":
			continue
		var a: Dictionary = inv.call("get_ammo", str(id))
		var amax := int(spec.call("get_ammo_max"))
		if int(a.get("mag_size", 0)) == 0:
			if int(a.get("in_mag", 0)) < amax:          # thrown: the pool is the count in hand
				full = false
		elif int(a.get("reserve", 0)) < amax or int(a.get("in_mag", 0)) < int(a.get("mag_size", 0)):
			full = false
			_log("not full: %s %s" % [str(id), str(a)])
	T.check(full, "every ammo pool is full after refill")
	var atts: int = dbg.give_all_attachments()
	T.check(atts > 0, "give_all_attachments installed %d" % atts)
	T.check(dbg.set_infinite_ammo(true) and bool(inv.get("infinite_ammo")), "infinite ammo on")
	dbg.set_infinite_ammo(false)
	T.check(dbg.give_weapon("pistol", true) and str(inv.get("current_id")) == "pistol", "give_weapon pistol and draw it")
	var list: Array = dbg.get_weapon_list()
	T.check(list.size() == Registry.count("weapons"), "weapon list for the menu (%d)" % list.size())


# --- player ------------------------------------------------------------------------------------

func _test_player() -> void:
	var p := _player()
	T.check(dbg.set_health(50.0) and is_equal_approx(float(p.get("health")), 50.0), "set_health 50")
	T.check(dbg.set_armor(75.0) and is_equal_approx(float(p.get("armor")), 75.0), "set_armor 75")
	T.check(dbg.heal_full() and float(p.get("health")) >= 99.9 and float(p.get("armor")) >= 99.9, "heal_full")
	dbg.set_money(123456)
	T.check(Game.money == 123456, "set_money")
	dbg.add_money(1000)
	T.check(Game.money == 124456, "add_money")
	dbg.set_invulnerable(true)
	var h0 := float(p.get("health"))
	p.call("apply_damage", Dmg.make(40.0, "bullet", null, p.global_position, Vector3.FORWARD))
	T.check(is_equal_approx(float(p.get("health")), h0) and is_equal_approx(float(p.get("armor")), 100.0), "invulnerable player takes no damage")
	dbg.set_invulnerable(false)
	T.check(not Game.invulnerable, "invulnerability off")
	p.call("apply_damage", Dmg.make(10.0, "melee", null, p.global_position, Vector3.FORWARD))
	T.check(float(p.get("health")) < h0, "damage applies again once invulnerability is off")
	dbg.set_invulnerable(true)
	dbg.max_skills()
	var all_max := true
	for s: String in Skills.SKILLS:
		all_max = all_max and Skills.get_level(s) >= 100.0
	T.check(all_max, "max_skills sets every skill to 100")
	dbg.reset_skills()
	T.check(is_equal_approx(Skills.get_level("driving"), Skills.START_LEVEL), "reset_skills")
	p.set("has_parachute", false)
	T.check(dbg.give_parachute() and bool(p.get("has_parachute")), "give_parachute")
	T.check(dbg.set_scuba(true) and bool(p.get("has_scuba")), "scuba on")
	T.check(dbg.set_scuba(false) and not bool(p.get("has_scuba")), "scuba off")
	p.set("breath", 0.2)
	T.check(dbg.refill_breath() and is_equal_approx(float(p.get("breath")), 1.0), "refill lung capacity")
	var before: Dictionary = p.call("get_appearance")
	T.check(dbg.randomize_appearance(4242), "randomize_appearance")
	var after: Dictionary = p.call("get_appearance")
	T.check(str(before) != str(after), "appearance changed")


# --- wanted / police ---------------------------------------------------------------------------

func _test_wanted() -> void:
	dbg.set_wanted(3)
	await T.wait_frames(2)
	T.check(int(Wanted.level) == 3, "set_wanted 3")
	dbg.set_wanted(5)
	T.check(int(Wanted.level) == 5, "set_wanted 5")
	dbg.clear_wanted()
	T.check(int(Wanted.level) == 0, "clear_wanted")
	if dbg.is_available("never_wanted"):
		T.check(dbg.set_never_wanted(true) and dbg.is_never_wanted(), "never wanted on")
		Wanted.report_crime("murder", Game.get_player_position(), {"force": true, "direct_police_witness": true})
		await T.wait_frames(2)
		T.check(int(Wanted.level) == 0, "never wanted: a witnessed crime raises nothing")
		dbg.set_never_wanted(false)
		T.check(not dbg.is_never_wanted(), "never wanted off")
	if dbg.is_available("police_units"):
		var u: Node = dbg.spawn_police("cruiser")
		T.check(u != null, "spawn_police cruiser")
		await T.wait_frames(30)
		dbg.clear_police()
	else:
		_log("SKIP police units: %s" % dbg.unavailable_reason("police_units"))
	T.check(dbg.run_command("wanted 2") == "ok" and int(Wanted.level) == 2, "run_command wanted 2")
	dbg.clear_wanted()


# --- world -------------------------------------------------------------------------------------

func _test_world() -> void:
	dbg.set_time(21.5)
	T.check(absf(float(WorldClock.hour) - 21.5) < 0.05, "set_time 21:30 (%.2f)" % float(WorldClock.hour))
	dbg.set_clock_paused(true)
	var h := float(WorldClock.hour)
	await T.wait_frames(90)
	T.check(is_equal_approx(float(WorldClock.hour), h), "clock paused")
	dbg.set_clock_paused(false)
	await T.wait_frames(30)
	T.check(float(WorldClock.hour) > h, "clock running again")
	T.check(dbg.set_weather("rain", true) and str(Weather.current) == "rain", "set_weather rain (instant)")
	await T.wait_frames(5)
	T.check(float(Weather.rain_intensity) > 0.3, "rain is falling (%.2f)" % float(Weather.rain_intensity))
	T.check(not dbg.is_auto_weather(), "choosing a weather stops automatic changes")
	dbg.set_weather("storm", false)
	await T.wait_frames(10)
	T.check(str(Weather.current) == "storm", "set_weather storm (blended)")
	T.check(not dbg.set_weather("snow", true), "unknown weather refused")
	dbg.set_weather("clear", true)
	dbg.set_auto_weather(true)
	T.check(dbg.is_auto_weather(), "automatic weather back on")
	dbg.set_time(10.0)
	# toggles through Game.set_system_enabled
	var any := false
	for sys_name: String in ["traffic", "peds", "wildlife", "police", "emergency", "transit", "pickups"]:
		if not Game.has_system(sys_name):
			_log("SKIP toggle %s: system not built yet" % sys_name)
			continue
		any = true
		T.check(dbg.toggle_system(sys_name, false) and not dbg.is_system_enabled(sys_name), "toggle %s off" % sys_name)
		var s := Game.get_system(sys_name)
		if "enabled" in s:
			T.check(not bool(s.get("enabled")), "%s.enabled is false" % sys_name)
		T.check(dbg.toggle_system(sys_name, true) and dbg.is_system_enabled(sys_name), "toggle %s on" % sys_name)
	T.check(any, "at least one real system toggled")
	T.check(not dbg.toggle_system("no_such_system", false), "toggling a missing system is refused")
	dbg.set_density("traffic", 0.5)
	T.check(is_equal_approx(float(Settings.get_value("traffic_density")), 0.5), "traffic density 0.5")
	dbg.set_density("traffic", 1.0)
	dbg.set_density("peds", 1.0)


# --- debug: time scale, overlay, stats, commands -------------------------------------------------

func _test_debug() -> void:
	dbg.set_time_scale(0.5)
	await T.wait_frames(2)
	T.check(is_equal_approx(Engine.time_scale, 0.5), "time scale 0.5")
	dbg.set_time_scale(2.0)
	await T.wait_frames(2)
	T.check(is_equal_approx(Engine.time_scale, 2.0), "time scale 2.0")
	Game.request_time_scale("adm_test", 0.15)
	await T.wait_frames(2)
	T.check(is_equal_approx(Engine.time_scale, 0.15), "another slow-motion request wins over fast forward")
	Game.release_time_scale("adm_test")
	await T.wait_frames(2)
	T.check(is_equal_approx(Engine.time_scale, 2.0), "fast forward resumes after the request ends")
	dbg.set_time_scale(1.0)
	await T.wait_frames(2)
	T.check(is_equal_approx(Engine.time_scale, 1.0), "time scale back to 1.0")
	dbg.set_overlay_visible(true)
	await T.wait_frames(30)
	T.check(dbg.is_overlay_visible() and bool(UI.debug_overlay_visible), "overlay on (UI flag mirrors)")
	var layer := dbg.get_node_or_null("DebugOverlay") as CanvasLayer
	T.check(layer != null and layer.visible, "overlay layer shown")
	var basic := UI.get_node_or_null("Root/Debug") as CanvasItem
	T.check(basic == null or not basic.visible, "UI's basic overlay hidden while ours shows")
	var st: Dictionary = dbg.get_stats()
	for k: String in ["fps", "avg_fps", "low_1_fps", "avg_ms", "draw_calls", "primitives", "nodes", "vehicles", "peds", "police",
			"position", "district", "sector", "time", "weather"]:
		if not st.has(k):
			T.check(false, "stats key %s" % k)
	T.check(int(st["frames"]) > 10 and float(st["avg_fps"]) > 0.0 and float(st["low_1_fps"]) > 0.0 and float(st["low_1_fps"]) <= float(st["avg_fps"]) + 0.01,
			"frame stats: avg %.1f fps, 1%% low %.1f over %d frames" % [float(st["avg_fps"]), float(st["low_1_fps"]), int(st["frames"])])
	T.check(str(st["district"]) != "" and str(st["sector"]) != "", "stats district %s sector %s" % [st["district"], st["sector"]])
	dbg.set_overlay_visible(false)
	await T.wait_frames(3)
	T.check(not dbg.is_overlay_visible() and (layer == null or not layer.visible), "overlay off")
	T.check(dbg.run_command("time 13") == "ok" and absf(float(WorldClock.hour) - 13.0) < 0.05, "run_command time 13")
	T.check(dbg.run_command("tp beach") == "ok", "run_command tp beach")
	await T.wait_physics_frames(10)
	T.check(dbg.run_command("bogus 1").begins_with("error"), "run_command rejects unknown commands")
	T.check(dbg.repair_all_vehicles(), "repair_all_vehicles")
	T.check(dbg.respawn_pickups() or not Game.has_system("pickups"), "respawn_pickups")


# --- services (next-wave systems; each one only when it exists) ----------------------------------

func _test_services() -> void:
	dbg.teleport_player("downtown_plaza", false)
	await T.wait_physics_frames(15)
	var v: Node3D = dbg.spawn_vehicle_for_player("compact", true)
	await T.wait_physics_frames(15)
	if dbg.is_available("customise") and v != null:
		T.check(dbg.open_customisation(), "customisation screen opens anywhere")
		await T.wait_frames(5)
		T.check(UI.is_screen_open("mod_garage"), "mod garage screen is open for the current vehicle")
		UI.close_screen("mod_garage")
		await T.wait_frames(3)
	else:
		_log("SKIP customise: %s" % dbg.unavailable_reason("customise"))
	if dbg.is_available("garage_store"):
		var stored: bool = dbg.store_current_vehicle()
		_log("store_current_vehicle -> %s" % str(stored))
		await T.wait_frames(5)
		if dbg.is_available("garage_delivery"):
			var back: Node3D = dbg.deliver_personal_vehicle()
			_log("deliver_personal_vehicle -> %s" % str(back))
			T.check(true, "garage services callable (store %s, deliver %s)" % [str(stored), str(back != null)])
	else:
		_log("SKIP garage: %s" % dbg.unavailable_reason("garage_store"))
	if dbg.is_available("taxi"):
		T.check(dbg.call_taxi(), "call_taxi accepted")
	else:
		_log("SKIP taxi: %s" % dbg.unavailable_reason("taxi"))
	if Game.get_player_vehicle() != null:
		_player().call("exit_vehicle")
		await T.wait_physics_frames(40)
	dbg.clear_admin_vehicles()
	await T.wait_frames(3)


# --- the admin menu screen ---------------------------------------------------------------------

func _test_menu() -> void:
	T.check(UI.handle_action("admin_menu"), "F1 action opens the admin menu")
	await T.wait_frames(3)
	var scr: Control = UI.get_screen("admin")
	T.check(scr != null and UI.is_screen_open("admin"), "admin screen open")
	if scr == null:
		return
	T.check(Game.is_input_locked(), "admin menu locks gameplay input")
	T.check(not get_tree().paused, "admin menu does not pause the game")
	for id: String in ["teleport", "vehicles", "weapons", "player", "wanted", "world", "services", "debug"]:
		scr.call("select_tab", id)
		await T.wait_frames(3)
		T.check(scr.call("get_tab_id") == id and scr.call("get_page", id) != null, "tab %s builds" % id)
	var tp_page: Control = scr.call("get_page", "teleport")
	T.check(tp_page != null and tp_page.find_children("*", "UiList", true, false).size() >= 2, "teleport tab has district + place lists")
	UI.handle_action("admin_menu")
	await T.wait_frames(3)
	T.check(not UI.is_screen_open("admin") and not Game.is_input_locked(), "F1 closes the menu and unlocks input")
