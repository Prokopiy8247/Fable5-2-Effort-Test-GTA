extends "res://gta/code/debug/autotest.gd"
## Gameplay validation scenarios (each is time-limited and quits when done).


func spawn_car(id: String, pos: Vector3, yaw := 0.0):
	var v = G.traffic.create(id, pos, yaw)
	v.owner_tag = "player"
	return v


func quiet() -> void:
	G.traffic.enabled = false
	for v in G.traffic.ai_list.duplicate():
		if is_instance_valid(v):
			v.queue_free()
	G.pop.set_enabled(false)


func drive(v) -> void:
	var p = G.player
	p.vehicle = v
	p.state = "vehicle"
	p.col.disabled = true
	v.set_driver(p)


func t_basic() -> void:
	var p = G.player
	check("player exists", p != null)
	await wait(1.0)
	check("player on ground", p.is_on_floor(), str(p.global_position))
	var a: Vector3 = p.global_position
	await hold("fwd", 1.2)
	check("player walks", p.global_position.distance_to(a) > 1.0, "moved %.1f" % p.global_position.distance_to(a))
	await shot("basic_player")
	quiet()
	var car = spawn_car("sedan", Vector3(-200, 0.6, 2.5), -PI / 2)
	await wait(1.0)
	check("car settles upright", car.global_basis.y.y > 0.95 and abs(car.global_position.y) < 0.6, "y=%.2f grounded=%d" % [car.global_position.y, car.grounded])
	p.teleport(car.door_pos(-1.0) + Vector3(0, 0.3, 1.2))
	await wait(0.5)
	await tap("enter")
	await wait(1.2)
	check("entered vehicle", p.state == "vehicle", p.state)
	await hold("fwd", 5.0)
	check("car accelerates", car.speed > 15.0, "speed %.1f" % car.speed)
	await shot("basic_drive")
	Input.action_press("left")
	await hold("fwd", 1.2)
	Input.action_release("left")
	check("car steers", abs(angle_difference(car.global_rotation.y, -PI / 2)) > 0.3, "yaw %.2f" % car.global_rotation.y)
	await hold("back", 2.5)
	check("car brakes", abs(car.speed) < 9.0, "speed %.1f" % car.speed)
	check("car upright", car.global_basis.y.y > 0.8)
	await wait(1.0)
	await tap("enter")
	await wait(0.8)
	check("exited vehicle", p.state in ["ground", "ragdoll"], p.state)
	await wait(1.0)
	await shot("basic_exit")


func t_combat() -> void:
	var p = G.player
	quiet()
	p.teleport(Vector3(-60, 0.4, 60))
	await wait(0.5)
	for id in ["pistol", "smg", "shotgun", "rifle", "sniper", "rpg", "grenade", "bat"]:
		p.weapons.give(id, 500)
	p.select_weapon("rifle")
	var npc = G.pop.spawn_ped(p.global_position + Vector3(0, 0, -9), {}, "ped")
	npc.set_state("idle")
	G.cam.yaw = 0.0
	G.cam.pitch = -0.05
	await wait(0.6)
	Input.action_press("aim")
	await wait(0.5)
	var hp0: float = npc.health
	Input.action_press("fire")
	await wait(1.0)
	Input.action_release("fire")
	await shot("combat_aim")
	Input.action_release("aim")
	check("rifle fired", p.weapons.inv["rifle"].clip < 30, "clip %d" % p.weapons.inv["rifle"].clip)
	check("npc took damage", npc.health < hp0 or npc.dead, "hp %.0f" % npc.health)
	await wait(0.5)
	check("npc dead or fleeing", npc.dead or npc.state in ["flee", "down", "fight"], npc.state)
	p.select_weapon("bat")
	var n2 = G.pop.spawn_ped(p.global_position + Vector3(0, 0, -1.4), {}, "ped")
	n2.set_state("idle")
	await wait(0.4)
	await tap("fire")
	await wait(0.6)
	check("melee hit", n2.health < 100.0 or n2.dead, "hp %.0f" % n2.health)
	p.select_weapon("rpg")
	var car = spawn_car("compact", p.global_position + Vector3(0, 0.6, -30), 0.0)
	await wait(1.0)
	Input.action_press("aim")
	await wait(0.4)
	G.cam.pitch = -0.045
	await wait(0.2)
	await tap("fire")
	await wait(1.6)
	Input.action_release("aim")
	check("rocket destroyed car", car.dead or car.health < car.max_health * 0.5, "hp %.0f" % car.health)
	await shot("combat_explosion")
	p.select_weapon("pistol")
	p.weapons.inv["pistol"].clip = 2
	await wait(0.3)
	await tap("reload")
	await wait(2.2)
	check("reload works", p.weapons.inv["pistol"].clip >= 12, "clip %d" % p.weapons.inv["pistol"].clip)
	Input.action_press("wheel")
	await wait(0.3)
	await shot("combat_wheel")
	Input.action_release("wheel")
	await wait(0.2)
	check("time scale restored", Engine.time_scale == 1.0)


func t_wanted() -> void:
	var p = G.player
	p.teleport(Vector3(-280, 0.4, -100))
	G.cheats.god = true
	await wait(1.0)
	check("starts at 0 stars", G.wanted.stars == 0)
	G.pop.set_enabled(false)
	G.traffic.enabled = false
	for v in G.traffic.ai_list.duplicate():
		if is_instance_valid(v):
			v.queue_free()
	for c in get_tree().get_nodes_in_group("cops"):
		c.queue_free()
	await wait(0.4)
	G.wanted.crime("assault", p.global_position, 1.0)
	await wait(0.5)
	var who = []
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.state == "phone":
			who.append("%s@%s" % [n.role, str(n.global_position)])
	check("unwitnessed crime ignored", G.wanted.stars == 0 and G.wanted.calls_pending == 0, "stars %d pending %d %s" % [G.wanted.stars, G.wanted.calls_pending, str(who)])
	var w = G.pop.spawn_ped(p.global_position + Vector3(8, 0.1, 0), {}, "ped")
	w.set_state("idle")
	await wait(0.8)
	G.wanted.crime("assault", p.global_position, 1.0)
	await wait(0.4)
	check("witness phones police", w.state == "phone", w.state)
	check("report not instant", G.wanted.stars == 0)
	await wait(5.2)
	check("witness report gives a star", G.wanted.stars >= 1, "stars %d heat %.2f log %s" % [G.wanted.stars, G.wanted.heat, str(G.wanted.crime_log)])
	G.traffic.enabled = true
	G.wanted.set_stars(3)
	await wait(9.0)
	check("police units dispatched", G.wanted.units.size() >= 1, "units %d" % G.wanted.units.size())
	check("air support at 3 stars", G.wanted.heli != null)
	await wait(9.0)
	var cops = get_tree().get_nodes_in_group("cops").size()
	print("[TEST] info state=%s seen=%s cops=%d units=%d" % [G.wanted.state, str(G.wanted.seen), cops, G.wanted.units.size()])
	await shot("wanted_3star")
	check("pursuit or search active", G.wanted.state in ["pursuit", "search"])
	G.wanted.clear(false)
	await wait(0.5)
	for c in get_tree().get_nodes_in_group("cops"):
		c.queue_free()
	G.wanted.set_stars(1)
	G.wanted.heat = 1.05
	p.teleport(G.world.locations["SafehouseInside"])
	await wait(3.0)
	check("search state when unseen", G.wanted.state == "search" and not G.wanted.seen, "%s seen=%s" % [G.wanted.state, str(G.wanted.seen)])
	await wait(16.0)
	check("wanted level lost by hiding", G.wanted.stars == 0, "stars %d escape %.0f" % [G.wanted.stars, G.wanted.escape_t])
	G.cheats.god = false
	p.teleport(Vector3(-6, 0.4, 60))
	await wait(0.5)
	G.wanted.set_stars(1)
	G.wanted.heat = 1.05
	var c2 = G.pop.spawn_ped(p.global_position + Vector3(5, 0.1, 0), {}, "cop")
	c2.set_meta("dispatched", true)
	await wait(7.0)
	check("busted when surrendering", p.state == "busted" or G.stats.busted > 0, p.state)
	await shot("wanted_busted")


func t_vehicles() -> void:
	var p = G.player
	quiet()
	G.cheats.god = true
	var x = -200.0
	var bad = []
	for id in ["sedan", "compact", "sports", "muscle", "suv", "pickup", "van", "taxi", "police", "ambulance", "firetruck", "swat", "truck", "motorcycle", "bicycle"]:
		var v = spawn_car(id, Vector3(x, 0.8, G.world.RUNWAY_Z), -PI / 2)
		x += 9.0
		v.set_meta("t_id", id)
	await wait(2.0)
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.has_meta("t_id"):
			if v.global_basis.y.y < 0.9 or v.global_position.y > 1.2 or v.global_position.y < 0.0:
				bad.append("%s(y=%.2f up=%.2f)" % [v.get_meta("t_id"), v.global_position.y, v.global_basis.y.y])
	check("all land vehicles rest upright", bad.is_empty(), str(bad))
	p.teleport(Vector3(-150, 6, G.world.RUNWAY_Z + 14))
	G.cam.yaw = 0.3
	await wait(0.6)
	await shot("vehicles_lineup")
	bad = []
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.has_meta("t_id"):
			v.set_driver(G.traffic)
			v.in_throttle = 1.0
			v.in_brake = 0.0
	await wait(4.0)
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.has_meta("t_id"):
			if v.speed < 5.0 or v.global_basis.y.y < 0.8:
				bad.append("%s(v=%.1f)" % [v.get_meta("t_id"), v.speed])
			v.queue_free()
	check("all land vehicles drive", bad.is_empty(), str(bad))
	await wait(0.3)
	var h = spawn_car("helicopter", Vector3(95, 0.5, -244), 0.0)
	await wait(1.0)
	p.teleport(h.door_pos(-1.0) + Vector3(0, 0.3, 0))
	await wait(0.3)
	await tap("enter")
	await wait(1.0)
	check("in helicopter", p.state == "vehicle" and p.vehicle == h)
	Input.action_press("jump")
	await wait(6.0)
	check("helicopter lifts off", h.global_position.y > 4.0, "y=%.1f" % h.global_position.y)
	Input.action_press("fwd")
	await wait(4.0)
	Input.action_release("fwd")
	Input.action_release("jump")
	check("helicopter flies forward", G.flat(h.linear_velocity).length() > 6.0, "v=%.1f" % G.flat(h.linear_velocity).length())
	await shot("vehicles_heli")
	check("helicopter stable", h.global_basis.y.y > 0.5 and not h.dead)
	p._exit_vehicle(true)
	h.queue_free()
	await wait(0.3)
	var pl = spawn_car("plane", Vector3(-230, 0.5, G.world.RUNWAY_Z), -PI / 2)
	await wait(1.5)
	check("plane rests on gear", pl.global_basis.y.y > 0.9, "up=%.2f y=%.2f" % [pl.global_basis.y.y, pl.global_position.y])
	drive(pl)
	Input.action_press("sprint")
	await wait(7.0)
	check("plane reaches takeoff speed", pl.speed > 22.0, "v=%.1f" % pl.speed)
	Input.action_press("back")
	await wait(4.0)
	Input.action_release("back")
	check("plane takes off", pl.global_position.y > 5.0, "y=%.1f v=%.1f" % [pl.global_position.y, pl.speed])
	await shot("vehicles_plane")
	await wait(2.0)
	Input.action_release("sprint")
	check("plane still flying", not pl.dead and pl.global_position.y > 3.0, "y=%.1f" % pl.global_position.y)
	p._exit_vehicle(true)
	pl.queue_free()
	await wait(0.3)
	var b = spawn_car("speedboat", Vector3(60, G.WATER_Y + 0.4, 270), PI)
	await wait(2.0)
	check("boat floats", abs(b.global_position.y - G.WATER_Y) < 0.8 and b.global_basis.y.y > 0.9, "y=%.2f" % b.global_position.y)
	drive(b)
	await hold("fwd", 5.0)
	check("boat moves", b.speed > 6.0, "v=%.1f" % b.speed)
	await shot("vehicles_boat")
	p._exit_vehicle(true)
	await wait(1.0)
	check("player swims after leaving boat", p.state == "swim", p.state)


func t_extras() -> void:
	var p = G.player
	var ex = G.extras
	G.cheats.god = true
	p.give_chute()
	p.teleport(G.world.locations["Spire Roof"] + Vector3(0, 0.5, 12.5))
	G.cam.yaw = PI
	await wait(0.5)
	p.facing = PI
	await hold("fwd", 1.6)
	await wait(1.0)
	check("falling from roof", not p.is_on_floor() and p.global_position.y < 72.0, "y=%.1f" % p.global_position.y)
	await tap("jump")
	await wait(0.5)
	check("parachute deployed", p.state == "chute", p.state)
	await shot("extras_parachute")
	var t = 0.0
	while p.state == "chute" and t < 25.0:
		await wait(0.5)
		t += 0.5
	check("parachute landing survived", p.state in ["ground", "swim"] and p.health > 0.0, "%s hp=%.0f" % [p.state, p.health])
	p.teleport(Vector3(-200, G.WATER_Y - 1.2, 325))
	await wait(1.0)
	check("swimming", p.state == "swim", p.state)
	Input.action_press("stealth")
	await wait(4.0)
	Input.action_release("stealth")
	check("dives underwater", p.head_underwater() and p.breath < 1.0, "y=%.1f breath=%.2f" % [p.global_position.y, p.breath])
	await shot("extras_dive")
	await hold("jump", 5.0)
	check("resurfaces", not p.head_underwater(), "y=%.1f" % p.global_position.y)
	p.teleport(Vector3(ex.train_stop, 6.8, 4.0))
	t = 0.0
	while ex.train_wait <= 1.0 and t < 60.0:
		p.global_position = Vector3(ex.train_stop, 6.8, 4.0)
		p.velocity = Vector3.ZERO
		await wait(0.5)
		t += 0.5
	p.global_position = Vector3(ex.train_x, 6.8, 3.6)
	p.velocity = Vector3.ZERO
	await wait(0.3)
	check("metro boarding prompt", p.interact_cur != null and "Metro" in p.interact_cur.text, str(p.interact_cur.text if p.interact_cur else "none"))
	ex._board_train()
	var x0: float = ex.train_x
	await wait(13.0)
	check("riding the metro", p.state == "passenger" and abs(ex.train_x - x0) > 20.0, "dx=%.0f" % abs(ex.train_x - x0))
	await shot("extras_metro")
	ex.riding_train = false
	p.leave_passenger(Vector3(-6, 0.5, 60))
	await wait(0.5)
	ex.call_taxi()
	check("taxi dispatched", ex.taxi != null)
	if ex.taxi:
		ex.taxi.global_position = p.global_position + Vector3(4, 0.6, 0)
		ex.taxi.ai.wait = 999.0
		await wait(1.0)
		check("taxi boardable", ex.try_board(ex.taxi))
		ex.taxi_state = "riding"
		G.menus.close_all()
		ex.taxi_go(G.world.locations["Hospital"])
		await wait(6.0)
		check("taxi ride in progress", p.state == "passenger" and ex.taxi_state == "riding", "%s %s" % [p.state, ex.taxi_state])
		Input.action_press("skip")
		await wait(0.3)
		Input.action_release("skip")
		await wait(1.5)
		check("taxi arrives (skip)", p.state == "ground" and G.dist2d(p.global_position, G.world.locations["Hospital"]) < 60.0, "d=%.0f" % G.dist2d(p.global_position, G.world.locations["Hospital"]))
	check("wildlife spawned", G.pop.animals.size() > 20, str(G.pop.animals.size()))
	p.teleport(G.world.locations["Shooting Range"] + Vector3(0, 0.4, 6))
	p.weapons.give("rifle", 300)
	p.select_weapon("rifle")
	await wait(0.5)
	ex.start_range()
	await wait(2.0)
	check("range target spawned", ex.activity == "range" and ex.act.get("cur") != null)
	if ex.act.get("cur") != null:
		ex.act.cur.damage(10.0, p)
		check("range hit counted", ex.act.hits == 1)
	await shot("extras_range")
	ex.end_activity()


func _press(prefix: String) -> bool:
	for c in G.menus.list.get_children():
		if c is Button and c.text.begins_with(prefix):
			c.pressed.emit()
			return true
	return false


func t_menus() -> void:
	var p = G.player
	var M = G.menus
	quiet()
	await wait(0.5)
	M.open_debug()
	await wait(0.4)
	await shot("menu_debug")
	check("debug menu open", M.is_open() and M.list.get_child_count() > 20, str(M.list.get_child_count()))
	M.close_all()
	M.open_shop("guns")
	await wait(0.3)
	await shot("menu_guns")
	G.money = 50000
	_press("Buy Wasp SMG")
	await wait(0.2)
	check("bought SMG in shop", p.weapons.has("smg") and G.money < 50000, "money %d" % G.money)
	M._weapon_bench("smg")
	await wait(0.2)
	_press("Suppressor")
	await wait(0.2)
	check("installed suppressor", p.weapons.inv["smg"].mods.has("Suppressor"))
	M.close_all()
	M.open_shop("clothes")
	await wait(0.3)
	var shirt0: Color = p.look.shirt
	_press("Shirt")
	await wait(0.2)
	check("clothing changes look", not p.look.shirt.is_equal_approx(shirt0))
	await shot("menu_clothes")
	M.close_all()
	var car = spawn_car("sports", G.world.locations["Torque Bay"] + Vector3(-3, 0.6, 0), PI / 2)
	await wait(1.0)
	drive(car)
	car.health = 500.0
	await wait(0.3)
	M.open_mods()
	await wait(0.3)
	check("mod garage opens", M.is_open())
	_press("Repair vehicle")
	await wait(0.2)
	check("repair restores health", car.health >= car.max_health - 1.0, "hp %.0f" % car.health)
	var top0: float = car.st.top
	var eng0: float = car.st.engine
	M._upgrade_menu(car, "engine")
	await wait(0.2)
	_press("Race tune")
	await wait(0.2)
	check("engine upgrade changes performance", car.st.engine > eng0 * 1.2 and car.st.top > top0, "engine %.0f -> %.0f" % [eng0, car.st.engine])
	M.back()
	M._upgrade_menu(car, "spoiler")
	await wait(0.2)
	_press("GT wing")
	await wait(0.2)
	var sp = G.part(car.model, "_Mod_Spoiler2")
	check("spoiler part visible", sp != null and sp.visible)
	M.back()
	M._paint_menu(car, false)
	await wait(0.2)
	_press("Deep Blue")
	await wait(0.2)
	check("paint applied", car.paint.is_equal_approx(M.Defs.PAINTS["Deep Blue"]))
	M.close_all()
	G.cam.yaw = 2.2
	await wait(1.0)
	await shot("menu_modded_car")
	M.open_garage(p.global_position + Vector3(8, 0, 0))
	await wait(0.2)
	_press("Store this")
	await wait(0.4)
	check("vehicle stored in garage", G.save.garage.size() == 1 and p.state != "vehicle", str(G.save.garage.size()))
	M.close_all()
	M.open_map()
	await wait(0.4)
	await shot("menu_map")
	M.close_map()
	M.open_phone()
	await wait(0.3)
	await shot("menu_phone")
	M.close_all()
	M.open_pause()
	await wait(0.2)
	check("pause stops the tree", get_tree().paused)
	M.close_all()
	check("unpaused", not get_tree().paused)
	G.money = 4321
	var pos: Vector3 = p.global_position
	check("save works", G.save.save_game())
	G.money = 1
	p.teleport(Vector3(0, 0.5, 0))
	check("load works", G.save.load_game())
	await wait(0.5)
	check("money restored", G.money == 4321, str(G.money))
	check("position restored", p.global_position.distance_to(pos) < 4.0, str(p.global_position))
	check("weapons restored", p.weapons.has("smg") and p.weapons.inv["smg"].mods.has("Suppressor"))
	check("garage restored", G.save.garage.size() == 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(G.save.PATH))


func t_look() -> void:
	var p = G.player
	p.teleport(Vector3(-20, 0.4, 8))
	G.cam.yaw = -1.2
	G.cam.pitch = -0.1
	await wait(8.0)
	await shot("look_day")
	G.env.set_hour(21.5)
	await wait(2.0)
	await shot("look_night")
	G.env.set_weather("storm", true)
	G.env.set_hour(17.0)
	await wait(2.5)
	await shot("look_storm")
	G.env.set_weather("fog", true)
	G.env.set_hour(7.0)
	await wait(1.5)
	await shot("look_fog")
	G.env.set_weather("clear", true)
	G.env.set_hour(18.6)
	p.teleport(Vector3(-170, 0.4, 211))
	G.cam.yaw = 0.6
	await wait(1.5)
	await shot("look_sunset_beach")
	G.env.set_hour(11.0)
	p.teleport(G.world.locations["Signal Hill"] + Vector3(0, 0.5, 3))
	G.cam.yaw = -2.2
	G.cam.pitch = -0.2
	await wait(1.5)
	await shot("look_hill")
	p.teleport(Vector3(180, 0.4, 150))
	G.cam.yaw = 0.8
	await wait(1.5)
	await shot("look_docks")


func t_perf() -> void:
	var p = G.player
	p.teleport(Vector3(-6, 0.4, 20))
	G.cheats.god = true
	await wait(6.0)
	var frames = 0
	var t0 = Time.get_ticks_msec()
	var worst = 0.0
	var last = Time.get_ticks_usec()
	while Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
		frames += 1
		var now = Time.get_ticks_usec()
		worst = max(worst, (now - last) / 1000.0)
		last = now
		if frames == 300:
			G.wanted.set_stars(4)
		if frames == 600:
			G.env.set_weather("storm", true)
	var secs = (Time.get_ticks_msec() - t0) / 1000.0
	print("[PERF] avg_fps=%.1f worst_frame_ms=%.1f nodes=%d vehicles=%d npcs=%d draw_calls=%d prims=%d vram_mb=%.0f" % [frames / secs, worst, get_tree().get_node_count(),
		get_tree().get_nodes_in_group("vehicles").size(), get_tree().get_nodes_in_group("npcs").size(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
	check("frame rate acceptable (capped 60)", frames / secs > 30.0, "%.1f" % (frames / secs))
	await shot("perf_chaos")


func t_dbg() -> void:
	var p = G.player
	p.teleport(Vector3(-6, 0.4, -40))
	G.cheats.god = true
	await wait(1.0)
	G.wanted.set_stars(3)
	for i in 40:
		await wait(0.25)
		var bad = []
		for n in get_tree().get_nodes_in_group("vehicles"):
			if not n.global_transform.is_finite():
				bad.append("veh:" + n.id + ":" + n.owner_tag)
		for n in get_tree().get_nodes_in_group("npcs"):
			if not n.global_transform.is_finite():
				bad.append("npc:" + n.role + ":" + n.state)
		if G.wanted.heli and not G.wanted.heli.global_transform.is_finite():
			bad.append("heli")
		if not p.global_transform.is_finite():
			bad.append("player")
		print("[TEST] t=%.2f units=%d cops=%d bad=%s" % [i * 0.25, G.wanted.units.size(), get_tree().get_nodes_in_group("cops").size(), str(bad)])
		if bad.size() > 0:
			break


func t_plane() -> void:
	var p = G.player
	quiet()
	G.cheats.god = true
	for id in ["plane", "jet"]:
		var pl = spawn_car(id, Vector3(-240, 0.5, G.world.RUNWAY_Z), -PI / 2)
		await wait(1.5)
		drive(pl)
		Input.action_press("sprint")
		for i in 16:
			await wait(1.0)
			if i == 7:
				Input.action_press("back")
			if i == 10:
				Input.action_release("back")
			print("[TEST] %s t=%d v=%.1f thr=%.2f gnd=%d pitch=%.2f y=%.1f x=%.0f" % [id, i, pl.speed, pl.throttle_state, pl.grounded, pl.global_rotation.x, pl.global_position.y, pl.global_position.x])
		Input.action_release("sprint")
		Input.action_release("back")
		p._exit_vehicle(true)
		pl.queue_free()
		await wait(0.5)


func t_misc() -> void:
	var p = G.player
	var W = G.world
	G.cheats.god = true
	await wait(1.0)
	# --- carjack an occupied traffic car
	G.pop.set_enabled(false)
	var l: Dictionary = G.traffic.lanes[0]
	p.teleport(l.p0 + l.dir * 30.0 + Vector3(0, 0.3, 6))
	await wait(0.3)
	var car = G.traffic.spawn_on_lane("sedan", 0, 30.0)
	car.linear_velocity = Vector3.ZERO
	car.ai.wait = 999.0
	await wait(1.0)
	p.teleport(car.door_pos(-1.0) + Vector3(0, 0.3, 0))
	await wait(0.4)
	check("hijack prompt target", p.near_vehicle == car and car.has_ai_driver())
	var n0 = get_tree().get_nodes_in_group("npcs").size()
	await tap("enter")
	await wait(1.6)
	check("carjack: player now drives", p.state == "vehicle" and p.vehicle == car, p.state)
	check("carjack: driver thrown out", get_tree().get_nodes_in_group("npcs").size() > n0)
	check("carjack counted as stolen", G.stats.cars_stolen >= 1)
	# --- drive-by
	p.weapons.give("smg", 300)
	p.select_weapon("smg")
	await wait(0.4)
	var c0: int = p.weapons.inv["smg"].clip
	Input.action_press("aim")
	Input.action_press("fire")
	await wait(0.6)
	Input.action_release("fire")
	Input.action_release("aim")
	check("drive-by fires SMG", p.weapons.inv["smg"].clip < c0, "clip %d" % p.weapons.inv["smg"].clip)

	# --- roadblock at 4 stars while driving
	G.wanted.set_stars(4)
	G.wanted._rb_cd = 0.0
	Input.action_press("fwd")
	var t = 0.0
	while G.wanted.roadblock.is_empty() and t < 12.0:
		await wait(0.5)
		t += 0.5
	Input.action_release("fwd")
	check("roadblock created at 4 stars", not G.wanted.roadblock.is_empty(), "t=%.1f speed=%.1f" % [t, car.speed])
	if not G.wanted.roadblock.is_empty():
		check("spike strip present at 4 stars", G.wanted.roadblock.has("spike"))
		p.teleport(G.wanted.roadblock.pos - G.wanted.roadblock.dir * 30.0, atan2(-G.wanted.roadblock.dir.x, -G.wanted.roadblock.dir.z))
		G.cam.yaw = atan2(-G.wanted.roadblock.dir.x, -G.wanted.roadblock.dir.z)
		G.cam.pitch = -0.15
		await wait(1.2)
		await shot("misc_roadblock")
		await hold("fwd", 2.5)
		var flats = 0
		for w in car.wheels:
			if w.flat:
				flats += 1
		check("spike strip punctures tyres", flats >= 2, "flats=%d" % flats)
	await wait(4.0)
	check("heli present at 4 stars", G.wanted.heli != null and is_instance_valid(G.wanted.heli))
	G.wanted.clear(false)
	p._exit_vehicle(true)
	await wait(0.5)
	for c in get_tree().get_nodes_in_group("cops"):
		c.queue_free()
	# --- cover
	p.teleport(Vector3(-128.5, 0.3, -60))
	p.facing = -PI / 2
	await wait(0.6)
	var b = W.prop("barrier", p.global_position + Vector3(-1.6, 0, 0), PI / 2, true)
	await wait(0.3)
	await tap("cover")
	await wait(0.4)
	check("cover: attaches to low cover", p.state == "cover" and p.cover.get("low", false), "%s %s" % [p.state, str(p.cover.get("low"))])
	G.cam.yaw = -PI / 2 + PI
	await wait(0.4)
	await shot("misc_cover")
	await hold("left", 0.5)
	p.select_weapon("smg")
	await wait(0.5)
	var c1: int = p.weapons.inv["smg"].clip
	await hold("fire", 0.3)
	await wait(0.3)
	check("cover: blind fire", p.weapons.inv["smg"].clip < c1 and p.state == "cover")
	await tap("cover")
	await wait(0.2)
	check("cover: leaves cover", p.state == "ground", p.state)
	# --- vault / mantle over the barrier
	p.facing = -PI / 2
	p.rotation.y = p.facing
	var x0: float = p.global_position.x
	await tap("jump")
	await wait(0.8)
	check("mantle onto obstacle", p.global_position.y > 0.6 or p.global_position.x < x0 - 0.8, "y=%.2f" % p.global_position.y)
	# --- stealth takedown
	p.teleport(Vector3(-128.5, 0.3, -20))
	await wait(0.4)
	var victim = G.pop.spawn_ped(p.global_position + Vector3(0, 0, -1.3), {}, "ped")
	victim.set_state("idle")
	victim.rotation.y = 0.0
	p.facing = 0.0
	G.cam.yaw = 0.0
	p.select_weapon("fists")
	await wait(0.4)
	await tap("stealth")
	await wait(0.4)
	check("stealth mode on", p.stealth and p.detect_mult < 0.7)
	await tap("fire")
	await wait(0.5)
	check("stealth takedown kills unaware target", victim.dead, "hp %.0f" % victim.health)
	await tap("stealth")
	# --- emergency services respond
	await wait(3.0)
	G.traffic.enabled = true
	G.extras._svc_cd = 0.0
	G.extras.on_casualty(victim.global_position, true)
	check("ambulance dispatched", G.extras._amb != null)
	G.fx.explode(p.global_position + Vector3(20, 0.5, 0), 6.0, 50.0, null)
	await wait(0.5)
	G.extras.on_explosion(p.global_position + Vector3(20, 0.5, 0))
	check("fire engine dispatched", G.extras._fire != null)
	# --- ladder
	var lad: Dictionary = W.ladders[0]
	p.teleport(lad.pos - lad.dir * 0.6)
	p.facing = atan2(-lad.dir.x, -lad.dir.z)
	G.cam.yaw = p.facing
	await wait(0.4)
	Input.action_press("fwd")
	await wait(4.5)
	Input.action_release("fwd")
	check("ladder climbed", p.global_position.y > lad.h * 0.8, "y=%.1f state=%s" % [p.global_position.y, p.state])
	# --- store robbery
	var clerk = G.pop.clerks[0]
	p.teleport(clerk.global_position + Vector3(0, 0.1, 4))
	p.select_weapon("smg")
	G.cam.yaw = 0.0
	G.cam.pitch = 0.0
	p.facing = 0.0
	await wait(0.5)
	Input.action_press("aim")
	await wait(4.2)
	Input.action_release("aim")
	check("store robbery works", clerk.robbed, clerk.state)
	check("robbery is a crime", G.wanted.stars >= 1 or G.wanted.heat > 0.5)
	G.wanted.clear(false)
	# --- gang turf
	p.teleport(Vector3(272, 0.4, 100))
	await wait(1.5)
	check("gang members spawned on turf", G.pop.count("gang") >= 3 or not G.pop.enabled, str(G.pop.count("gang")))
	# --- sleep/save at the safehouse
	G.menus.sleep()
	var h0: float = G.env.hour
	await wait(2.5)
	check("sleep advances time", abs(fposmod(G.env.hour - h0, 24.0) - 8.0) < 0.5, "%.1f -> %.1f" % [h0, G.env.hour])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(G.save.PATH))
	await wait(6.0)
	print("[TEST] info services amb=%s fire=%s" % [str(G.extras._amb.state if G.extras._amb else "done"), str(G.extras._fire.state if G.extras._fire else "done")])


func t_city() -> void:
	var p = G.player
	G.cheats.god = true
	p.teleport(Vector3(-14, 0.4, 14))
	G.cam.yaw = -2.3
	G.cam.pitch = -0.12
	for k in 5:
		await wait(7.0)
		var n = 0
		var moving = 0
		var stuck = 0
		for v in G.traffic.ai_list:
			if is_instance_valid(v):
				n += 1
				if abs(v.speed) > 2.0:
					moving += 1
				if v.ai.get("stuck", 0.0) > 8.0:
					stuck += 1
		print("[TEST] info t=%d traffic=%d moving=%d stuck=%d peds=%d cops=%d" % [k * 7 + 7, n, moving, stuck, G.pop.count("ped"), get_tree().get_nodes_in_group("cops").size()])
	await shot("city_downtown")
	check("traffic populated", G.traffic.ai_list.size() >= 8, str(G.traffic.ai_list.size()))
	check("pedestrians populated", G.pop.count("ped") >= 6, str(G.pop.count("ped")))
	p.teleport(Vector3(-124, 0.4, 14))
	G.cam.yaw = -1.0
	await wait(6.0)
	await shot("city_avenue")
