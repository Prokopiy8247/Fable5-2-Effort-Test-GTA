extends Node
## Garage system API test (headless, real world + player). Economy B.
##   tools\godot.ps1 -Mode headless -Frames 12000 -TimeoutSec 400 -UserArgs '--test=gar_api','--test-timeout=380','--disable=traffic,peds,police,emergency,wildlife,transit,taxi,activities,radio,ambience'
## Covers: site resolution, store / retrieve (colours, mods, health), police refusal, SaveSystem
## round trip, Torque Garage bay session, mod purchases (money, measured acceleration + braking,
## visible parts, stat bars, preview revert), repair, gas-station quick service, catalogue
## rentals (car / boat / aircraft when their specs can spawn), safehouse sleep + save + spawn
## inside on load, explosive pumps (when the city exposes them). Uses its own save slots.

const Stats := preload("res://gta/code/world/shops/garage_stats.gd")
const TEST_SLOT := "gar_test"
const HOME_SLOT := "gar_test_home"

var g = null      ## untyped: coroutine helpers are awaited with plain method syntax
var player: Node3D = null


func _ready() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	await TestHarness.wait_frames(20)
	g = Game.get_system("garage")
	if not TestHarness.check(g != null, "garage system registered"):
		TestHarness.finish(false, "no garage system")
		return
	player = Game.player if Game.has_player() else null
	TestHarness.check(player != null, "player present")
	Game.set_money(900000)
	var sh = g.get_helper("safehouse")
	if sh != null:
		sh.set("save_slot", HOME_SLOT)
	await _test_sites()
	await _test_store_retrieve()
	await _test_refusals()
	await _test_persistence()
	await _test_bay_session()
	await _test_mods_measured()
	await _test_repair()
	await _test_gas_service()
	await _test_catalogue()
	await _test_safehouse()
	await _test_pumps()
	SaveSystem.delete_save(TEST_SLOT)
	SaveSystem.delete_save(HOME_SLOT)
	TestHarness.finish()


# ---------------------------------------------------------------------------------------------
func _test_sites() -> void:
	for h: String in ["mod_shop", "safehouse", "gas_station", "access"]:
		TestHarness.check(g.call("get_helper", h) != null, "helper '%s' created" % h)
	var ms = g.get_helper("mod_shop")
	if ms != null:
		var bay: Transform3D = ms.get("bay_xform")
		var loc := Game.get_location("mod_garage")
		TestHarness.log_line("mod garage markers from '%s': Use_Bay %s, Exit_Bay %s" % [str(ms.get("source")), str(bay.origin), str((ms.get("exit_xform") as Transform3D).origin)])
		TestHarness.check(bay.origin.distance_to(loc.origin) < 30.0, "Use_Bay resolved near the mod_garage location (%.1f m)" % bay.origin.distance_to(loc.origin))
	var sh = g.get_helper("safehouse")
	if sh != null:
		var gs: Transform3D = sh.call("get_marker", "Garage_Spot")
		TestHarness.log_line("safehouse markers from '%s': Garage_Spot %s, Spawn_Inside %s" % [str(sh.get("source")), str(gs.origin), str((sh.call("get_marker", "Spawn_Inside") as Transform3D).origin)])
		TestHarness.check(gs.origin.distance_to(Game.get_location("safehouse").origin) < 25.0, "Garage_Spot resolved at the safehouse")
	var acc = g.get_helper("access")
	if acc != null:
		for site: String in ["airport", "marina", "parking_garage"]:
			var xf: Transform3D = acc.call("get_terminal_transform", site)
			TestHarness.check(xf.origin != Vector3.ZERO, "terminal '%s' placed at %s" % [site, str(xf.origin)])
		var kiosk: Node = acc.get_node_or_null("Terminal_Airport/Kiosk")
		TestHarness.check(kiosk != null and kiosk.get_child_count() >= 2, "terminal uses the atm kiosk model + collider")
	TestHarness.check(get_tree().get_nodes_in_group("interactable").size() >= 11, "garage interactables registered (%d in group)" % get_tree().get_nodes_in_group("interactable").size())


# ---------------------------------------------------------------------------------------------
func _test_store_retrieve() -> void:
	var sh = g.get_helper("safehouse")
	var spot: Transform3D = sh.call("get_marker", "Garage_Spot")
	var c1 := Color("#7A50D0")
	var c2 := Color("#F2C331")
	var mods := {"engine": "engine_2", "spoiler": "spoiler_a", "wheel_color": "wheelcol_gold"}
	var v := Game.spawn_vehicle("sedan", spot, {"color": c1, "color2": c2, "mods": mods, "health": 640.0})
	if not TestHarness.check(v != null, "sedan spawned at the Garage_Spot"):
		return
	await _frames(10)
	var mods_in: Dictionary = v.get("mods")
	player.call("enter_vehicle", v, 0, true)
	await _frames(10)
	TestHarness.check(player.get("current_vehicle") == v, "player seated in the sedan")
	var store_it := sh.get("garage_store") as Interactable
	TestHarness.check(store_it != null and store_it.can_interact(player), "in-vehicle store prompt offered at the Garage_Spot")
	var ok: bool = await sh.store_here(v)
	await _frames(5)
	TestHarness.check(ok, "store_here() stored the sedan")
	TestHarness.check(not is_instance_valid(v) or v.is_queued_for_deletion(), "stored vehicle removed from the world")
	TestHarness.check(player.get("current_vehicle") == null, "player on foot after storing")
	var stored: Array = g.call("get_stored")
	TestHarness.check(stored.size() == 1, "one vehicle stored (%d)" % stored.size())
	# step out of the bay first: the contract call spawns right where it is told to
	player.call("teleport", spot.origin - spot.basis.z * 7.0, 0.0)
	await _frames(3)
	var v2: Node3D = g.call("retrieve_vehicle", 0, spot)
	await _frames(10)
	if not TestHarness.check(v2 != null, "retrieve_vehicle() spawned it again"):
		return
	TestHarness.check(str(v2.get("spec_id")) == "sedan", "same spec")
	TestHarness.check(Stats.same_color(v2.get("paint_primary"), c1) and Stats.same_color(v2.get("paint_secondary"), c2), "colours kept (%s / %s)" % [str(v2.get("paint_primary")), str(v2.get("paint_secondary"))])
	TestHarness.check(v2.get("mods") == mods_in, "mods kept (%s)" % str(v2.get("mods")))
	TestHarness.check(absf(float(v2.get("health")) - 640.0) < 1.0, "health kept (%.0f)" % float(v2.get("health")))
	TestHarness.check(g.call("get_personal_vehicle") == v2, "retrieved vehicle is the personal vehicle")
	await _frames(70)
	TestHarness.check(v2.is_in_group("personal_vehicle") and v2.is_in_group("minimap_blip"), "personal vehicle tagged for the map blip")
	TestHarness.check((g.call("get_stored") as Array).is_empty(), "storage empty again")
	# the screen path: retrieve at the site with the player seated
	TestHarness.check(bool(g.call("store_vehicle", v2)), "store_vehicle() (contract) with nobody inside")
	await _frames(5)
	var v3: Node3D = await g.retrieve_at_site(0, "safehouse")
	await _frames(10)
	TestHarness.check(v3 != null and player.get("current_vehicle") == v3, "retrieve_at_site() seats the player")
	player.call("teleport", spot.origin - spot.basis.z * 7.0, 0.0)
	await _frames(5)
	g.call("_despawn", v3)
	await _frames(5)


func _test_refusals() -> void:
	var pos := Game.get_location("police_station")
	var pv := Game.spawn_vehicle("police_cruiser", Transform3D(Basis.IDENTITY, pos.origin + Vector3(0, 0.1, 6)), {})
	if pv == null:
		TestHarness.log_line("police_cruiser could not spawn - refusal not exercised")
		return
	await _frames(5)
	var reason := str(g.call("can_store", pv))
	TestHarness.check(reason != "", "police vehicle refused: '%s'" % reason)
	TestHarness.check(not bool(g.call("store_vehicle", pv)), "store_vehicle(police) returns false")
	var ms = g.get_helper("mod_shop")
	TestHarness.check(str(ms.call("refuse_reason", pv)) != "", "Torque Garage refuses police vehicles")
	g.call("_despawn", pv)
	await _frames(3)


# ---------------------------------------------------------------------------------------------
func _test_persistence() -> void:
	var xf := Transform3D(Basis.IDENTITY, Game.get_location("safehouse").origin + Vector3(-14, 0.1, 6))
	var v := Game.spawn_vehicle("compact", xf, {"color": Color("#1FA7A0"), "mods": {"tint": "tint_limo", "brakes": "brakes_2"}, "health": 500.0})
	if not TestHarness.check(v != null, "compact spawned for the save test"):
		return
	await _frames(5)
	TestHarness.check(bool(g.call("store_vehicle", v)), "compact stored")
	var before: Array = g.call("get_stored")
	TestHarness.check(SaveSystem.save_game(TEST_SLOT), "SaveSystem.save_game(%s)" % TEST_SLOT)
	var txt := FileAccess.get_file_as_string(SaveSystem.slot_path(TEST_SLOT))
	TestHarness.check(txt.contains("\"garage\"") and txt.contains("tint_limo"), "save file contains the garage provider")
	(g.get("stored") as Array).clear()
	TestHarness.check((g.call("get_stored") as Array).is_empty(), "storage cleared in memory")
	TestHarness.check(SaveSystem.load_game(TEST_SLOT), "SaveSystem.load_game(%s)" % TEST_SLOT)
	await _frames(10)
	var after: Array = g.call("get_stored")
	TestHarness.check(after.size() == before.size() and after.size() == 1, "stored list restored (%d)" % after.size())
	if after.size() == 1:
		var a: Dictionary = after[0]
		TestHarness.check(str(a["spec_id"]) == "compact" and (a["mods"] as Dictionary).get("tint", "") == "tint_limo"
				and Stats.same_color(SaveSystem.array_to_color(a["primary"]), Color("#1FA7A0")) and absf(float(a["health"]) - 500.0) < 1.0,
				"restored entry keeps spec, mods, colour and health")
	g.call("remove_stored", 0)
	Game.set_money(900000)


# ---------------------------------------------------------------------------------------------
func _test_bay_session() -> void:
	var ms = g.get_helper("mod_shop")
	if ms == null:
		return
	var bay: Transform3D = ms.get("bay_xform")
	var v := Game.spawn_vehicle("muscle", Transform3D(bay.basis, bay.origin + Vector3(0, 0.1, 0)), {})
	if not TestHarness.check(v != null, "muscle car spawned in the bay"):
		return
	await _frames(10)
	player.call("enter_vehicle", v, 0, true)
	await _frames(10)
	var it := ms.get("interactable") as Interactable
	TestHarness.check(it != null and it.can_interact(player), "Torque Garage prompt offered to a car in the bay")
	var opened: bool = await ms.begin(v)
	await _frames(5)
	TestHarness.check(opened and UI.is_screen_open("mod_garage"), "bay session opened the mod_garage screen")
	var scr := UI.get_screen("mod_garage")
	TestHarness.check(v.global_position.distance_to(bay.origin) < 0.6, "car held in the middle of the bay")
	if scr != null:
		var tabs: Array = scr.call("get_tab_names")
		TestHarness.log_line("tabs for the muscle car: %s" % str(tabs))
		TestHarness.check(tabs.size() == 9, "all nine tabs offered for a customisable car")
		TestHarness.check(get_viewport().get_camera_3d() != null and get_viewport().get_camera_3d().name == "ModGarageCamera", "orbit camera is current")
	UI.close_screen("mod_garage")
	await TestHarness.wait_seconds(1.6)
	await _frames(10)
	var ex: Transform3D = ms.get("exit_xform")
	TestHarness.check(v.global_position.distance_to(ex.origin) < 1.5, "car put on the Exit_Bay driveway after leaving (%.2f m)" % v.global_position.distance_to(ex.origin))
	TestHarness.check(player.get("current_vehicle") == v, "player still at the wheel")
	TestHarness.check(get_viewport().get_camera_3d() == null or get_viewport().get_camera_3d().name != "ModGarageCamera", "gameplay camera restored")
	player.call("teleport", ex.origin + ex.basis.x * 4.0, 0.0)
	await _frames(5)
	g.call("_despawn", v)
	await _frames(3)


func _runway() -> Transform3D:
	var s := Game.get_location("airport_runway_start")
	return Transform3D(s.basis, s.origin + s.basis.x * 4.0 + Vector3(0, 0.05, 0))


func _time_to_speed(v: Node3D, target: float) -> float:
	v.call("release_inputs")
	v.call("teleport", _runway())
	await _frames(50)
	v.call("set_inputs", 1.0, 0.0, 0.0)
	var t := 0.0
	for f in 900:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if float(v.call("get_forward_speed")) >= target:
			break
	v.call("set_inputs", 0.0, 0.0, 1.0)
	return t


func _brake_distance(v: Node3D, from_speed: float) -> float:
	v.call("release_inputs")
	v.call("teleport", _runway())
	await _frames(50)
	v.call("set_inputs", 1.0, 0.0, 0.0)
	for f in 1200:
		await get_tree().physics_frame
		if float(v.call("get_forward_speed")) >= from_speed:
			break
	var p0 := v.global_position
	v.call("set_inputs", 0.0, 0.0, 1.0)
	for f in 900:
		await get_tree().physics_frame
		if float(v.call("get_forward_speed")) < 0.2:
			break
	var d := v.global_position.distance_to(p0)
	v.call("set_inputs", 0.0, 0.0, 0.0)
	return d


func _test_mods_measured() -> void:
	# stock reference
	var a := Game.spawn_vehicle("sedan", _runway(), {})
	if not TestHarness.check(a != null, "stock sedan on the runway"):
		return
	await _frames(10)
	var t_stock: float = await _time_to_speed(a, 22.0)
	var d_stock: float = await _brake_distance(a, 25.0)
	g.call("_despawn", a)
	await _frames(5)
	# customised through the screen (remote session: admin path)
	var b := Game.spawn_vehicle("sedan", _runway(), {})
	await _frames(10)
	var scr := UI.open_screen("mod_garage", {"vehicle": b, "remote": true})
	await _frames(5)
	if not TestHarness.check(scr != null, "mod_garage screen opens remotely"):
		g.call("_despawn", b)
		return
	var spec := Stats.spec_of(b)
	var st0 := Stats.stats_for(spec, {})
	var m0 := Game.money
	TestHarness.check(bool(scr.call("purchase_mod", "engine", "engine_4")), "bought engine_4")
	TestHarness.check(Game.money == m0 - Stats.mod_price("engine_4"), "engine_4 cost %s" % Stats.money(Stats.mod_price("engine_4")))
	scr.call("purchase_mod", "turbo", "turbo_3")
	scr.call("purchase_mod", "transmission", "transmission_3")
	scr.call("purchase_mod", "brakes", "brakes_3")
	TestHarness.check((b.get("mods") as Dictionary).get("engine", "") == "engine_4" and (b.get("mods") as Dictionary).get("brakes", "") == "brakes_3", "mods installed on the car (%s)" % str(b.get("mods")))
	var st1: Dictionary = scr.call("get_stats")
	TestHarness.check(float(st1["acceleration"]["value"]) > float(st0["acceleration"]["value"]) * 1.4
			and float(st1["top_speed"]["value"]) > float(st0["top_speed"]["value"]) and float(st1["braking"]["value"]) > float(st0["braking"]["value"]),
			"stat bars recomputed (accel %s -> %s, top %s -> %s, brake %s -> %s)" % [st0["acceleration"]["text"], st1["acceleration"]["text"],
			st0["top_speed"]["text"], st1["top_speed"]["text"], st0["braking"]["text"], st1["braking"]["text"]])
	# visible body part
	var opts: Dictionary = b.call("get_mod_options")
	if opts.has("spoiler"):
		var sid := str((opts["spoiler"] as Array).back())
		var node_name := str(Stats.mod_def(sid).get("node", ""))
		TestHarness.check(bool(scr.call("purchase_mod", "spoiler", sid)), "bought %s" % sid)
		var part: Variant = b.call("get_part", node_name)
		TestHarness.check(part is Node3D and (part as Node3D).visible, "%s visible after the purchase" % node_name)
	if opts.has("hood"):
		scr.call("preview_mod", "hood", "hood_a")
		var hood: Variant = b.call("get_part", "Mod_Hood_A")
		TestHarness.check(hood is Node3D and (hood as Node3D).visible, "hover preview shows Mod_Hood_A")
		scr.call("select_tab", "Paint")
		await _frames(2)
		TestHarness.check(not (hood as Node3D).visible and not (b.get("mods") as Dictionary).has("hood"), "preview reverted when browsing on (not bought)")
	# paint
	var m1 := Game.money
	var new_col: Color = Stats.PALETTE[0]["color"]
	for e: Dictionary in Stats.PALETTE:
		if not Stats.same_color(e["color"], b.get("paint_primary")):
			new_col = e["color"]
			break
	TestHarness.check(bool(scr.call("purchase_paint", "primary", new_col)), "bought %s paint" % Stats.palette_name(new_col))
	TestHarness.check(Stats.same_color(b.get("paint_primary"), new_col) and Game.money == m1 - Stats.PRIMARY_PRICE, "paint applied and charged")
	TestHarness.check(not bool(scr.call("purchase_paint", "primary", new_col)), "the colour already on the car is not sold twice")
	# admin unlock: free
	Game.flags["free_shopping"] = true
	var m2 := Game.money
	TestHarness.check(bool(scr.call("purchase_mod", "tint", "tint_limo")) and Game.money == m2, "free_shopping makes mods free")
	Game.flags.erase("free_shopping")
	# not enough money
	Game.set_money(10)
	TestHarness.check(not bool(scr.call("purchase_mod", "armor", "armor_4")) and not (b.get("mods") as Dictionary).has("armor"), "purchase refused without the money")
	Game.set_money(900000)
	UI.close_screen("mod_garage")
	await _frames(10)
	TestHarness.check((b.get("mods") as Dictionary).get("turbo", "") == "turbo_3", "purchases stay after leaving")
	var t_mod: float = await _time_to_speed(b, 22.0)
	var d_mod: float = await _brake_distance(b, 25.0)
	TestHarness.check(t_mod < t_stock * 0.9, "measured 0-79 km/h: stock %.2f s -> modded %.2f s" % [t_stock, t_mod])
	TestHarness.check(d_mod < d_stock * 0.95, "measured braking from 90 km/h: stock %.1f m -> modded %.1f m" % [d_stock, d_mod])
	g.call("_despawn", b)
	await _frames(5)


# ---------------------------------------------------------------------------------------------
func _test_repair() -> void:
	var v := Game.spawn_vehicle("suv", _runway(), {})
	if v == null:
		return
	await _frames(10)
	v.call("apply_damage", Dmg.make(1200.0, "bullet", null, v.global_position + Vector3(0, 1.0, 0)))
	v.call("pop_tire", 0)
	var dmg: Variant = v.get("damage")
	if dmg is Object and (dmg as Object).has_method("break_all_glass"):
		(dmg as Object).call("break_all_glass", false)
	await _frames(5)
	var c := Stats.condition(v)
	var cost := Stats.repair_cost(v)
	TestHarness.log_line("damaged suv: health %.0f %%, glass broken %d, flat %d -> repair %s" % [float(c["health"]) * 100.0, int(c["glass_broken"]), int(c["tyres_flat"]), Stats.money(cost)])
	TestHarness.check(cost > 0 and Stats.needs_repair(c), "repair cost by damage (%s)" % Stats.money(cost))
	var scr := UI.open_screen("mod_garage", {"vehicle": v, "remote": true})
	await _frames(3)
	var m0 := Game.money
	TestHarness.check(bool(scr.call("purchase_repair")), "repair bought")
	var c2 := Stats.condition(v)
	TestHarness.check(float(c2["health"]) > 0.999 and int(c2["tyres_flat"]) == 0 and int(c2["glass_broken"]) == 0, "health, tyres and glass restored")
	TestHarness.check(Game.money == m0 - cost, "repair charged %s" % Stats.money(cost))
	UI.close_screen("mod_garage")
	await _frames(3)
	# a bike / boat class only gets Repair
	g.call("_despawn", v)
	await _frames(3)


func _test_gas_service() -> void:
	var gas = g.get_helper("gas_station")
	if gas == null:
		return
	var xf: Transform3D = gas.get("service_xform")
	var v := Game.spawn_vehicle("pickup", Transform3D(xf.basis, xf.origin + Vector3(0, 0.15, 0)), {})
	if not TestHarness.check(v != null, "pickup spawned under the canopy"):
		return
	await _frames(10)
	v.set("health", float(v.get("max_health")) * 0.3)
	v.call("pop_tire", 1)
	player.call("enter_vehicle", v, 0, true)
	await _frames(10)
	var it := gas.get("service_point") as Interactable
	TestHarness.check(it != null and it.can_interact(player), "quick service offered: '%s'" % (it.prompt if it != null else ""))
	var cost := Stats.service_cost(v)
	var m0 := Game.money
	var ok: bool = await gas.service(v)
	await _frames(3)
	var c := Stats.condition(v)
	TestHarness.check(ok and float(c["health"]) >= Stats.SERVICE_HEALTH - 0.01 and float(c["health"]) < 0.9 and int(c["tyres_flat"]) == 0,
			"quick service: tyres fixed, health patched to %d %%" % roundi(float(c["health"]) * 100.0))
	TestHarness.check(Game.money == m0 - cost and cost < Stats.repair_cost(v) + 500, "service charged %s (cheap)" % Stats.money(cost))
	TestHarness.check(not it.can_interact(player), "no service prompt once the vehicle is fine")
	player.call("teleport", xf.origin + xf.basis.x * 9.0, 0.0)
	await _frames(5)
	g.call("_despawn", v)
	await _frames(3)


# ---------------------------------------------------------------------------------------------
func _rent(spec_id: String, site: String) -> Node3D:
	var fee := Stats.rental_fee(spec_id)
	var m0 := Game.money
	var v: Node3D = await g.rent_and_board(spec_id, site)
	await _frames(10)
	if not TestHarness.check(v != null, "rented '%s' at %s (%s)" % [spec_id, site, str(g.get("last_error"))]):
		return null
	TestHarness.check(Game.money == m0 - fee, "rental fee %s charged" % Stats.money(fee))
	TestHarness.check(player.get("current_vehicle") == v, "player seated in the rented %s" % spec_id)
	return v


func _first_spawnable(cls: Array) -> String:
	for e: Dictionary in g.call("get_catalogue", cls):
		if bool(e["available"]):
			return str(e["id"])
	return ""


func _test_catalogue() -> void:
	var cars: Array = g.call("get_catalogue", ["car"])
	TestHarness.check(cars.size() >= 13, "car catalogue lists every registered car (%d)" % cars.size())
	var acc = g.get_helper("access")
	var scr := acc.call("open_terminal", "parking_garage") as Control
	await _frames(3)
	TestHarness.check(scr != null and UI.is_screen_open("garage"), "parking garage terminal opens the catalogue")
	if scr != null:
		TestHarness.check((scr.call("get_items") as Array).size() >= 13, "catalogue rows listed")
		UI.close_screen("garage")
		await _frames(3)
	var car := await _rent("compact", "parking_garage")
	if car != null:
		var a: Transform3D = Game.get_location("parking_garage")
		TestHarness.check(car.global_position.distance_to(a.origin) < 90.0, "car delivered near the parking garage (%.0f m)" % car.global_position.distance_to(a.origin))
	var boat := _first_spawnable(["boat"])
	if boat != "":
		var bv := await _rent(boat, "marina")
		if bv != null:
			TestHarness.check(Game.is_in_water(bv.global_position + Vector3(0, -0.3, 0)), "boat delivered on the water at the marina")
			var ms := UI.open_screen("mod_garage", {"vehicle": bv, "remote": true})
			await _frames(3)
			if ms != null:
				var tabs: Array = ms.call("get_tab_names")
				TestHarness.check(tabs == ["Repair"], "a boat gets the Repair tab only (%s)" % str(tabs))
				UI.close_screen("mod_garage")
				await _frames(3)
	else:
		TestHarness.log_line("no boat spec can spawn yet (%d registered) - boat rental not exercised" % (g.call("get_catalogue", ["boat"]) as Array).size())
	for kind: String in ["heli", "plane"]:
		var air := _first_spawnable([kind])
		if air != "":
			var av := await _rent(air, "airport")
			if av != null:
				var ref := Game.get_location("airport_helipad" if kind == "heli" else "airport_runway_start").origin
				TestHarness.check(av.global_position.y > 1.0 and av.global_position.distance_to(ref) < (60.0 if kind == "heli" else 240.0),
						"%s delivered at the airport (%s, %.0f m from the %s)" % [kind, str(av.global_position), av.global_position.distance_to(ref),
						"helipad" if kind == "heli" else "runway start"])
		else:
			TestHarness.log_line("no %s spec can spawn yet (%d registered) - not exercised" % [kind, (g.call("get_catalogue", [kind]) as Array).size()])
	Game.flags["free_shopping"] = true
	TestHarness.check(Stats.rental_fee("sports") == 0, "rentals free with free_shopping")
	Game.flags.erase("free_shopping")
	var pv := Game.get_player_vehicle()
	player.call("teleport", Game.get_location("parking_garage").origin, 0.0)
	await _frames(5)
	if pv != null:
		g.call("_despawn", pv)
	await _frames(3)


# ---------------------------------------------------------------------------------------------
func _test_safehouse() -> void:
	var sh = g.get_helper("safehouse")
	if sh == null:
		return
	var inside: Transform3D = sh.call("get_marker", "Spawn_Inside")
	player.call("teleport", inside.origin + Vector3(0, 0.1, 0), 0.0)
	await _frames(5)
	player.set("health", 35.0)
	var h0 := WorldClock.hour
	var ok: bool = await sh.sleep()
	await _frames(3)
	var dh := fposmod(WorldClock.hour - h0, 24.0)
	TestHarness.check(ok and absf(dh - 8.0) < 0.1, "sleep advanced the clock 8 h (%.2f -> %.2f)" % [h0, WorldClock.hour])
	TestHarness.check(float(player.get("health")) >= float(player.get("max_health")) - 0.5, "sleep healed the player")
	TestHarness.check(SaveSystem.has_save(HOME_SLOT), "sleep autosaved (%s)" % HOME_SLOT)
	TestHarness.check(bool(sh.call("save_here", false)), "save point saves")
	player.call("teleport", Game.get_location("hospital").origin, 0.0)
	await _frames(5)
	TestHarness.check(SaveSystem.load_game(HOME_SLOT), "loaded the home save")
	await _frames(6)
	var d := player.global_position.distance_to(inside.origin)
	TestHarness.check(d < 1.5, "a save made at home loads with the player inside (%.2f m from Spawn_Inside)" % d)
	if ResourceLoader.exists(str(UI.SCREENS.get("wardrobe", ""))):
		TestHarness.check(bool(sh.open_wardrobe()) and UI.is_screen_open("wardrobe"), "safehouse wardrobe opens the wardrobe screen")
		UI.close_screen("wardrobe")
		await _frames(3)
	else:
		TestHarness.log_line("wardrobe screen not built yet - wardrobe point not exercised")
	var scr := UI.open_screen("safehouse", {"focus": "save"})
	await _frames(3)
	TestHarness.check(scr != null, "safehouse screen opens")
	UI.close_screen("safehouse")
	await _frames(2)
	var gl := UI.open_screen("garage", {"mode": "stored", "site": "safehouse"})
	await _frames(3)
	TestHarness.check(gl != null and (gl.call("get_items") as Array).size() == int(g.call("get_capacity")), "garage list shows every bay")
	UI.close_screen("garage")
	await _frames(2)


func _test_pumps() -> void:
	var gas = g.get_helper("gas_station")
	if gas == null:
		return
	var n := int(gas.call("get_pump_count"))
	if n == 0:
		TestHarness.log_line("gas station building not exposed by a city builder - explosive pumps not exercised")
		return
	TestHarness.check(n == 4, "four pump colliders bound (%d)" % n)
	var body: Node = gas.get_node_or_null("PumpBody1")
	for k in 6:
		Dmg.apply(body, Dmg.make(25.0, "bullet", null, (body as Node3D).global_position))
	await _frames(5)
	TestHarness.check(bool(gas.call("is_pump_destroyed", 0)), "shot pump explodes")
	await _frames(30)
