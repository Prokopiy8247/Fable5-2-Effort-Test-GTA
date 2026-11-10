extends Node
## Automated test scenarios. Each `t_<name>` coroutine is callable through
## `--gta-test=<name>` (see test_runner.gd). They double as regression tests.

var runner: Node = null

func ok(check: String, cond: bool, detail: String = "") -> void:
	runner.record(check, cond, detail)

func t_smoke() -> void:
	await runner.wait_frames(20)
	ok("palette loaded", Assets.palette_index.size() >= 100, str(Assets.palette_index.size()))
	ok("materials built", Assets.mat("Palette") != null and Assets.mat("Paint1") != null)
	await runner.shot("smoke")

## Detached camera for screenshots (does not disturb the gameplay camera permanently).
func _cam_at(pos: Vector3, look: Vector3, fov := 70.0) -> Camera3D:
	var cam: Camera3D = get_node_or_null("ShotCam")
	if cam == null:
		cam = Camera3D.new()
		cam.name = "ShotCam"
		cam.far = 4000.0
		add_child(cam)
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.make_current()
	return cam

func _release_cam() -> void:
	var cam: Camera3D = get_node_or_null("ShotCam")
	if cam:
		cam.clear_current()

## World overview shots: checks that the map builds and looks right from key viewpoints.
func t_world() -> void:
	await runner.wait_frames(10)
	var w: World = Game.world
	ok("world exists", w != null)
	ok("layout roads", w.layout.roads.size() >= 45, str(w.layout.roads.size()))
	ok("lane graph", w.graph.lanes.size() > 200, str(w.graph.lanes.size()))
	ok("build time < 15 s", int(w.build_ms.get("total", 99999)) < 15000, str(w.build_ms))
	var shots := [
		["world_overview", Vector3(40, 420, 330), Vector3(0, 0, 0)],
		["world_downtown", Vector3(-70, 16, -30), Vector3(40, 30, -140)],
		["world_street", Vector3(36, 2.2, 20), Vector3(40, 3, -60)],
		["world_midtown", Vector3(20, 9, 62), Vector3(60, 2, 30)],
		["world_residential", Vector3(-150, 12, 20), Vector3(-190, 2, 60)],
		["world_beach", Vector3(-150, 6, 240), Vector3(-60, 2, 215)],
		["world_hill", Vector3(-120, 30, -100), Vector3(-195, 28, -195)],
		["world_airfield", Vector3(300, 30, 120), Vector3(250, 2, -100)],
		["world_industrial", Vector3(128, 14, -60), Vector3(170, 4, -110)],
		["world_marina", Vector3(110, 10, 270), Vector3(86, 0, 215)],
	]
	for s in shots:
		_cam_at(s[1], s[2])
		await runner.wait_frames(6)
		await runner.shot(s[0])
	_release_cam()

func _tap(action: String) -> void:
	Input.action_press(action)
	await runner.wait_physics(3)
	Input.action_release(action)

func _home_car() -> Vehicle:
	for v in get_tree().get_nodes_in_group(&"vehicles"):
		if v.has_meta("home"):
			return v
	return null

## Player locomotion on foot.
func t_walk() -> void:
	await runner.wait_frames(30)
	var p: Player = Game.player
	ok("player exists", p != null)
	if p == null:
		return
	Game.cam.yaw = -PI * 0.5
	await runner.wait_seconds(0.5)
	var start := p.global_position
	Input.action_press("move_forward")
	await runner.wait_seconds(2.0)
	var moved := p.global_position.distance_to(start)
	ok("player jogs", moved > 5.0, "moved %.2f m" % moved)
	Input.action_press("sprint")
	var s2 := p.global_position
	await runner.wait_seconds(1.5)
	ok("player sprints", p.global_position.distance_to(s2) > 8.0, "%.2f m in 1.5 s" % p.global_position.distance_to(s2))
	Input.action_release("sprint")
	Input.action_release("move_forward")
	ok("player on the sidewalk", absf(p.global_position.y - 0.15) < 0.4, "y=%.2f" % p.global_position.y)
	await _tap("jump")
	await runner.wait_seconds(0.22)
	ok("player jumps", p.global_position.y > 0.4, "y=%.2f" % p.global_position.y)
	await runner.wait_seconds(1.0)
	await _tap("crouch")
	await runner.wait_seconds(0.3)
	ok("player crouches", p.crouched)
	await _tap("crouch")
	await runner.shot("player_walk")

## Enter the home car, accelerate, steer, brake, get out.
func t_drive() -> void:
	await runner.wait_frames(30)
	var p: Player = Game.player
	var car := _home_car()
	ok("home car exists", car != null)
	if car == null or p == null:
		return
	await runner.wait_seconds(1.5)
	ok("car rests on its wheels", absf(car.global_position.y) < 0.5 and car.global_transform.basis.y.y > 0.97,
		"y=%.2f up=%.2f" % [car.global_position.y, car.global_transform.basis.y.y])
	p.teleport(car.door_position(0) + Vector3(0, 0.1, 0.6))
	await runner.wait_seconds(0.3)
	await _tap("enter_vehicle")
	await runner.wait_seconds(2.0)
	ok("player is in the car", p.state == Player.St.VEHICLE and p.vehicle == car, "state=%d" % p.state)
	Input.action_press("move_forward")
	await runner.wait_seconds(4.0)
	var v1 := car.speed
	ok("car accelerates", v1 > 9.0, "%.1f m/s after 4 s" % v1)
	var yaw0 := car.global_rotation.y
	Input.action_press("move_right")
	await runner.wait_seconds(1.2)
	Input.action_release("move_right")
	ok("car steers", absf(angle_difference(yaw0, car.global_rotation.y)) > 0.15, "dyaw=%.2f" % angle_difference(yaw0, car.global_rotation.y))
	ok("car stays upright", car.global_transform.basis.y.y > 0.85, "up=%.2f" % car.global_transform.basis.y.y)
	Input.action_release("move_forward")
	await runner.shot("drive")
	Input.action_press("handbrake")
	Input.action_press("move_back")
	await runner.wait_seconds(2.5)
	Input.action_release("move_back")
	Input.action_release("handbrake")
	ok("car brakes", absf(car.speed) < 6.0, "%.1f m/s" % car.speed)
	Input.action_press("handbrake")
	await runner.wait_seconds(2.0)
	Input.action_release("handbrake")
	await _tap("enter_vehicle")
	await runner.wait_seconds(1.5)
	ok("player left the car", p.state == Player.St.FOOT and p.vehicle == null, "state=%d" % p.state)
	ok("player is standing somewhere sane", p.global_position.y > -0.5 and p.global_position.y < 3.0, "y=%.2f" % p.global_position.y)

## Close-up beauty shots of the player and the home car (visual QA of imported assets).
func t_look() -> void:
	await runner.wait_frames(20)
	var p: Player = Game.player
	var car := _home_car()
	p.teleport(Vector3(-170.0, 0.2, 125.0), 0.0)
	if car:
		car.global_position = Vector3(-166.0, 0.3, 127.0)
		car.global_rotation = Vector3(0, 0.6, 0)
	await runner.wait_seconds(1.0)
	_cam_at(Vector3(-171.5, 1.5, 121.5), Vector3(-169.0, 1.0, 126.0), 60.0)
	await runner.wait_frames(8)
	await runner.shot("look_player_car")
	_cam_at(Vector3(-163.0, 2.2, 121.0), Vector3(-166.0, 0.8, 127.0), 50.0)
	await runner.wait_frames(8)
	await runner.shot("look_car")
	_cam_at(Vector3(20.0, 26.0, 80.0), Vector3(50.0, 6.0, 30.0), 65.0)
	await runner.wait_frames(8)
	await runner.shot("look_midtown")
	_release_cam()

## Ambient pedestrians: population, walking, navigation mesh, panic reactions.
func t_peds() -> void:
	await runner.wait_seconds(7.0)
	var pm: PedManager = Game.peds
	ok("ped manager", pm != null)
	if pm == null:
		return
	var t0 := Time.get_ticks_msec()
	while not Game.world.nav_ready and Time.get_ticks_msec() - t0 < 20000:
		await runner.wait_frames(5)
	ok("navmesh baked", Game.world.nav_ready, str(Game.world.build_ms.get("nav_bake", -1)) + " ms")
	var alive := 0
	var start := {}
	for n in get_tree().get_nodes_in_group(&"npcs"):
		var npc := n as NPC
		if npc.alive:
			alive += 1
		start[npc] = npc.global_position
	ok("pedestrians spawned", alive >= 12, str(alive))
	await runner.wait_seconds(4.0)
	var moved := 0
	for k in start.keys():
		if is_instance_valid(k) and (k as NPC).global_position.distance_to(start[k]) > 1.5:
			moved += 1
	ok("pedestrians walk", moved >= 6, "%d of %d" % [moved, start.size()])
	var path := NavigationServer3D.map_get_path(Game.world.nav_map, Vector3(-185, 0.2, 137), Vector3(-100, 0.2, 60), true)
	ok("nav path across blocks", path.size() >= 3, "%d points" % path.size())
	_cam_at(Game.player.global_position + Vector3(6, 5, 8), Game.player.global_position + Vector3(-10, 1, -14))
	await runner.wait_frames(6)
	await runner.shot("peds_street")
	_release_cam()
	Events.noise.emit(Game.player.global_position, 70.0, &"gunshot", Game.player)
	await runner.wait_seconds(1.5)
	var scared := 0
	for n in get_tree().get_nodes_in_group(&"npcs"):
		var npc := n as NPC
		if npc.state == NPC.S.FLEE or npc.state == NPC.S.COWER or npc.state == NPC.S.FIGHT:
			scared += 1
	ok("gunfire panics pedestrians", scared >= 3, str(scared))
	await runner.wait_seconds(2.0)
	await runner.shot("peds_panic")

## AI traffic: population, lane following, signals, no pile-ups.
func t_traffic() -> void:
	await runner.wait_seconds(6.0)
	var tm: TrafficManager = Game.traffic
	ok("traffic manager", tm != null)
	if tm == null:
		return
	var cars := tm.ai_vehicles()
	tm.debug_log = true
	ok("traffic spawned", cars.size() >= 8, str(cars.size()))
	var start := {}
	for v in cars:
		start[v] = v.global_position
	await runner.wait_seconds(14.0)
	var moved := 0
	var upright := 0
	var off_lane := 0
	var max_speed := 0.0
	var valid := 0
	for k in start.keys():
		if not is_instance_valid(k):
			moved += 1          # drove out of range and was recycled
			continue
		valid += 1
		var v := k as Vehicle
		if v.global_position.distance_to(start[k]) > 12.0:
			moved += 1
		if v.global_transform.basis.y.y > 0.8:
			upright += 1
		max_speed = maxf(max_speed, absf(v.speed))
		var near := tm.graph.nearest(v.global_position, 30.0, Vector3.ZERO, true)
		if near.is_empty() or float(near["dist"]) > 2.6:
			off_lane += 1
	ok("traffic drives", moved >= int(start.size() * 0.6), "%d of %d moved > 12 m, top %.1f m/s" % [moved, start.size(), max_speed])
	ok("traffic stays upright", upright == valid, "%d of %d" % [upright, valid])
	ok("traffic keeps its lanes", off_lane <= 1, "%d off lane" % off_lane)
	var wrecks := 0
	for n in get_tree().get_nodes_in_group(&"vehicles"):
		if (n as Vehicle).health < (n as Vehicle).max_health * 0.7:
			wrecks += 1
	ok("no pile-ups", wrecks <= 1, "%d damaged vehicles" % wrecks)
	var parked := 0
	for n in get_tree().get_nodes_in_group(&"vehicles"):
		if (n as Vehicle).owner_tag == "parked":
			parked += 1
	ok("parked cars streamed in", parked >= 4, str(parked))
	# overview of a junction
	var best: Vehicle = null
	for v in tm.ai_vehicles():
		if best == null or v.global_position.distance_to(Game.player_pos()) < best.global_position.distance_to(Game.player_pos()):
			best = v
	if best != null:
		_cam_at(best.global_position + Vector3(9, 7, 12), best.global_position)
		await runner.wait_frames(6)
		await runner.shot("traffic_car")
	_cam_at(Vector3(40, 38, 75), Vector3(40, 0, 40))
	await runner.wait_frames(6)
	await runner.shot("traffic_junction")
	_release_cam()

## Two minutes of traffic: junction reservations must not deadlock and nobody should crash.
func t_traffic_soak() -> void:
	await runner.wait_seconds(5.0)
	var tm: TrafficManager = Game.traffic
	if tm == null:
		ok("traffic manager", false)
		return
	var worst_blocked := 0.0
	var jammed := 0
	for i in 24:
		await runner.wait_seconds(5.0)
		jammed = 0
		for v in tm.ai_vehicles():
			var ai := v.ai as AIDriver
			worst_blocked = maxf(worst_blocked, ai.blocked)
			if ai.blocked > 12.0 or ai.stuck > 8.0:
				jammed += 1
	var damaged := 0
	var flipped := 0
	for v in tm.ai_vehicles():
		if v.health < v.max_health * 0.8:
			damaged += 1
		if v.global_transform.basis.y.y < 0.7:
			flipped += 1
	ok("no gridlock after 2 minutes", jammed <= 1, "%d jammed, worst wait %.1f s" % [jammed, worst_blocked])
	ok("traffic undamaged", damaged <= 2, "%d damaged of %d" % [damaged, tm.ai_vehicles().size()])
	ok("nobody flipped", flipped == 0, str(flipped))
	_cam_at(Vector3(40, 60, 90), Vector3(40, 0, 40))
	await runner.wait_frames(6)
	await runner.shot("traffic_soak")
	_release_cam()

## Wanted system: witnesses, police response, pursuit / search / escape, arrest.
func t_police() -> void:
	await runner.wait_seconds(4.0)
	var w: WantedSystem = Game.wanted
	var pd: PoliceDispatch = Game.police
	var pl: Player = Game.player
	ok("wanted system + dispatch", w != null and pd != null)
	if w == null or pd == null:
		return
	Game.cheats["invulnerable"] = true
	# 1. an unwitnessed crime does nothing
	pl.teleport(Vector3(-270.0, 0.4, 250.0))
	await runner.wait_seconds(1.0)
	for n in get_tree().get_nodes_in_group(&"npcs"):
		if (n as Node3D).global_position.distance_to(pl.global_position) < 70.0:
			n.queue_free()
	await runner.wait_frames(3)
	Events.crime.emit(&"assault", pl.global_position, {})
	await runner.wait_seconds(1.0)
	ok("unwitnessed crime ignored", w.level == 0 and w.heat < 1.0, "heat %.1f" % w.heat)
	# 2. an officer who sees it reports immediately
	pl.teleport(Vector3(-185.0, 0.3, 137.0))
	await runner.wait_seconds(0.5)
	var cop := (Game.peds as PedManager).spawn(&"police", pl.global_position + Vector3(0, 0, -7.0), 0.0)
	cop.set_face_yaw(PI)
	await runner.wait_seconds(0.5)
	Events.crime.emit(&"assault", pl.global_position, {})
	await runner.wait_seconds(0.5)
	ok("officer witnesses crime", w.level >= 1, "level %d heat %.1f" % [w.level, w.heat])
	ok("pursuit while seen", w.state == WantedSystem.PURSUIT, str(w.state))
	# 3. standing still next to an officer at one star -> busted
	var busted_before: int = Game.stats["busted"]
	var t := 0.0
	while t < 14.0 and int(Game.stats["busted"]) == busted_before:
		await runner.wait_seconds(0.5)
		t += 0.5
	ok("arrest when surrendering at 1 star", int(Game.stats["busted"]) > busted_before, "after %.1f s" % t)
	await runner.wait_seconds(6.0)
	ok("wanted cleared after arrest", w.level == 0)
	ok("released at the station", pl.global_position.distance_to(Vector3(-6.0, 0.0, -243.5)) < 60.0, str(pl.global_position))
	# 4. three stars: units respond, see the player and open fire
	pl.teleport(Vector3(36.0, 0.3, 60.0))
	await runner.wait_seconds(1.0)
	w.set_level(3)
	t = 0.0
	var arrived := false
	var fighting := 0
	while t < 45.0:
		await runner.wait_seconds(1.0)
		t += 1.0
		fighting = 0
		for n in get_tree().get_nodes_in_group(&"police_units"):
			if n is NPC and (n as NPC).state == NPC.S.FIGHT and (n as NPC).global_position.distance_to(pl.global_position) < 60.0:
				fighting += 1
		if fighting >= 2 and w.state == WantedSystem.PURSUIT:
			arrived = true
			break
	ok("police respond at 3 stars", arrived, "%d officers engaging after %.0f s, units %d" % [fighting, t, pd.ground_units()])
	_cam_at(pl.global_position + Vector3(10, 9, 14), pl.global_position)
	await runner.wait_frames(6)
	await runner.shot("police_response")
	_release_cam()
	await runner.wait_seconds(6.0)
	ok("helicopter dispatched", pd.air != null)
	if pd.air != null and is_instance_valid(pd.air.veh):
		var hy := pd.air.veh.global_position.y
		ok("helicopter airborne", hy > 15.0, "y %.1f" % hy)
	# 5. escape: hide far away -> search -> cleared
	var seen_at := pl.global_position
	pl.teleport(Vector3(-195.0, 30.5, -195.0))
	w.seen_now = false               # the teleport is not something the officers could follow
	w.last_known = seen_at
	t = 0.0
	var searched := false
	while t < 75.0 and w.level > 0:
		await runner.wait_seconds(1.0)
		t += 1.0
		if w.state == WantedSystem.SEARCH:
			searched = true
	ok("search state when hidden", searched)
	ok("wanted level cools down", w.level == 0, "after %.0f s" % t)
	Game.cheats["invulnerable"] = false

## Menus: pause, map, weapon wheel, phone, admin pages (screenshots + function checks).
func t_ui() -> void:
	await runner.wait_seconds(3.0)
	var ui: UIManager = Game.menus
	ok("ui manager", ui != null)
	if ui == null:
		return
	var p: Player = Game.player
	ui.open_pause()
	await runner.wait_frames(4)
	ok("pause menu pauses the game", get_tree().paused and ui.menu.visible)
	await runner.shot("ui_pause")
	ui.menu.push_page("Settings", "", ui._settings_rows)
	await runner.wait_frames(3)
	await runner.shot("ui_settings")
	ui.menu.close()
	await runner.wait_frames(2)
	ok("pause menu closes", not get_tree().paused and ui.mode == "")
	ui.open_map()
	await runner.wait_frames(4)
	await runner.shot("ui_map")
	ui.map.close()
	await runner.wait_frames(2)
	for id in WeaponDB.ORDER:
		p.inventory.give(id, -1, true)
	ui._open_wheel()
	await runner.wait_frames(4)
	ok("weapon wheel slows time", Engine.time_scale < 0.5, str(Engine.time_scale))
	await runner.shot("ui_wheel")
	ui.wheel.slot = 4
	ui.wheel.choice[4] = &"rifle_assault"
	ui._close_wheel(true)
	await runner.wait_frames(3)
	ok("wheel equips the chosen weapon", p.gunner.weapon_id == &"rifle_assault", String(p.gunner.weapon_id))
	ok("time scale restored", is_equal_approx(Engine.time_scale, 1.0))
	ui.open_phone()
	await runner.wait_frames(4)
	await runner.shot("ui_phone")
	ui.menu.close()
	ui.open_admin()
	await runner.wait_frames(3)
	await runner.shot("ui_admin")
	ui.menu.push_page("Spawn vehicle", "", func() -> Array: return AdminMenu._vehicles(ui))
	await runner.wait_frames(3)
	await runner.shot("ui_admin_vehicles")
	ui.menu.close()
	await runner.wait_frames(2)
	# admin functions
	Game.wanted.set_level(3)
	ok("admin: set wanted 3", Game.wanted.level == 3)
	Game.wanted.clear(true)
	ok("admin: clear wanted", Game.wanted.level == 0)
	Game.time.set_hour(22.0)
	await runner.wait_frames(5)
	ok("admin: set time", absf(Game.time.hour - 22.0) < 0.2, str(Game.time.hour))
	Game.time.set_hour(10.0)
	Game.time.set_weather(&"rain", true)
	await runner.wait_frames(5)
	ok("admin: set weather", Game.time.weather == &"rain")
	Game.time.set_weather(&"clear", true)
	var target: Variant = AdminMenu.district_point("Ironworks")
	ok("admin: district point", target != null)
	if target != null:
		AdminMenu.go(target)
		await runner.wait_seconds(0.5)
		ok("admin: teleport", p.global_position.distance_to(target) < 4.0, str(p.global_position))
	var heli := AdminMenu.spawn_vehicle("heli_civil", true)
	await runner.wait_seconds(1.0)
	ok("admin: spawn helicopter + seat player", heli != null and p.vehicle == heli)
	if heli != null:
		p.force_exit_vehicle()
		await runner.wait_frames(3)
		heli.queue_free()
	var boat := AdminMenu.spawn_vehicle("boat_speed", true)
	await runner.wait_seconds(1.5)
	ok("admin: spawn boat on water", boat != null and Game.water_depth(boat.global_position + Vector3(0, -0.3, 0)) > -1.0 and p.vehicle == boat)
	if boat != null:
		_cam_at(boat.global_position + Vector3(8, 5, 10), boat.global_position)
		await runner.wait_frames(5)
		await runner.shot("ui_spawned_boat")
		_release_cam()
		p.force_exit_vehicle()
		await runner.wait_frames(2)
		p.teleport(Vector3(-185.0, 0.3, 137.0))

## Shops: buying, live previews that revert, Torque House upgrades, pickups.
func t_shops() -> void:
	await runner.wait_seconds(3.0)
	var ui: UIManager = Game.menus
	var p: Player = Game.player
	Game.cash = 50000
	var city: CityBuilder = Game.world.city
	ok("gun shop location", city.locations.has("shop_guns"))
	var e: Variant = city.marker("shop_guns", "entrance")
	if e != null:
		p.teleport((e as Transform3D).origin + Vector3(0, 0.2, 0))
		await runner.wait_seconds(0.6)
		_cam_at(p.global_position + Vector3(0, 4, 9), p.global_position + Vector3(0, 2, -6))
		await runner.wait_frames(5)
		await runner.shot("shop_guns_outside")
		_release_cam()
	p.inventory.remove(&"smg")
	ui.open_shop("guns")
	await runner.wait_frames(3)
	await runner.shot("shop_guns_menu")
	var cash0 := Game.cash
	var rows := ShopMenus._gun_page(ui, [&"smg"])
	(rows[0]["fn"] as Callable).call()
	ok("buy SMG", p.inventory.has(&"smg") and Game.cash == cash0 - int(WeaponDB.get_w(&"smg")["price"]), "cash %d -> %d" % [cash0, Game.cash])
	ui.menu.push_page("Workbench", "", func() -> Array: return ShopMenus._workbench_page(ui, &"smg"))
	await runner.wait_frames(3)
	await runner.shot("shop_workbench")
	var wrows := ShopMenus._workbench_page(ui, &"smg")
	(wrows[1]["fn"] as Callable).call()
	ok("fit suppressor", p.inventory.has_att("suppressor", &"smg"))
	ui.menu.close()
	await runner.wait_frames(2)
	# clothing preview reverts unless paid
	var shirt0 := String(p.appearance.get("shirt", ""))
	ui.open_shop("clothes")
	await runner.wait_frames(3)
	var crow: Dictionary = ui.menu.current_row()
	var crows: Array = ui.menu.pages.back()["rows"]
	for r in crows:
		if String(r.get("text", "")) == "Shirt / jacket colour":
			(r["on_opt"] as Callable).call((Appearance.SHIRTS.find(shirt0) + 3) % Appearance.SHIRTS.size())
			break
	await runner.wait_frames(3)
	ok("clothes preview applied", String(p.appearance.get("shirt", "")) != shirt0)
	_cam_at(p.global_position + p.forward() * 2.6 + Vector3(0, 1.5, 0), p.global_position + Vector3(0, 1.0, 0))
	await runner.wait_frames(4)
	await runner.shot("shop_clothes_preview")
	_release_cam()
	ui.menu.close()
	await runner.wait_frames(3)
	ok("unpaid clothes reverted", String(p.appearance.get("shirt", "")) == shirt0)
	# Torque House on a sports car
	var car := AdminMenu.spawn_vehicle("car_sports", true)
	await runner.wait_seconds(1.0)
	ok("spawn sports car", car != null and p.vehicle == car)
	if car != null:
		var ps0 := (car as Car).power_scale
		var ctx: Dictionary = {"vehicle": car}
		ui.open_shop("mods", ctx)
		await runner.wait_frames(3)
		await runner.shot("shop_mods_menu")
		var mrows := ShopMenus._mod_page(ui, car, ctx, "engine")
		(mrows[2]["fn"] as Callable).call()
		ok("engine upgrade bought", int(car.mods.get("engine", 0)) == 2 and (car as Car).power_scale > ps0, "power %.2f" % (car as Car).power_scale)
		var paint_rows := ShopMenus._mod_page(ui, car, ctx, "paint")
		(paint_rows[3]["hover"] as Callable).call()
		await runner.wait_frames(2)
		_cam_at(car.global_position + Vector3(5, 2.5, 6), car.global_position)
		await runner.wait_frames(4)
		await runner.shot("shop_mods_paint_preview")
		_release_cam()
		if ui.menu.visible:
			ui.menu.close()
		else:
			ShopMenus.on_close("mods", ctx)
		await runner.wait_frames(2)
		ok("paint preview reverted", not car.mods.has("paint"))
		ok("engine kept", int(car.mods.get("engine", 0)) == 2)
		p.force_exit_vehicle()
		await runner.wait_frames(2)
	# pickups: health
	var pk: Pickups = Game.pickups
	ok("pickups system", pk != null and pk.count() >= 10, str(pk.count() if pk else 0))
	if pk != null:
		p.health = 40.0
		var hp_item: Pickups.Item = null
		for it in pk.items:
			if it.kind == "health":
				hp_item = it
				break
		if hp_item != null:
			p.teleport(hp_item.home)
			await runner.wait_seconds(0.6)
			ok("health pickup heals", p.health > 60.0, "%.0f" % p.health)

## Garage, save/load, taxi, emergency services, stunt jump, shooting range.
func t_services() -> void:
	await runner.wait_seconds(3.0)
	if OS.get_cmdline_user_args().has("--garage-only"):
		Game.cash = 20000
		var gs2: GarageSystem = Game.garage
		var home2 := _home_car()
		gs2.store(home2)
		await runner.wait_frames(3)
		var near2 := []
		for vv in get_tree().get_nodes_in_group(&"vehicles"):
			if (vv as Node3D).global_position.distance_to(gs2._out) < 8.0:
				near2.append("%s@%s" % [vv.name, (vv as Node3D).global_position])
		var v2 := gs2.take_out(0)
		ok("garage take out", v2 != null, "out %s spot %s near %s" % [gs2._out, gs2._spot, str(near2)])
		return
	if OS.get_cmdline_user_args().has("--only-jump"):
		await _jump_only()
		return
	var p: Player = Game.player
	Game.cheats["invulnerable"] = true
	Game.cash = 20000
	# --- garage + save/load
	var gs: GarageSystem = Game.garage
	ok("garage system", gs != null)
	var home := _home_car()
	if gs != null and home != null:
		var n0 := gs.stored.size()
		gs.store(home)
		await runner.wait_frames(3)
		ok("store personal car", gs.stored.size() == n0 + 1)
		ok("save game", SaveSystem.save_game("test"))
		var cash_saved := Game.cash
		Game.cash = 1
		gs.stored.clear()
		ok("load game", SaveSystem.load_game("test"))
		await runner.wait_frames(3)
		ok("load restores cash + garage", Game.cash == cash_saved and gs.stored.size() == n0 + 1, "cash %d stored %d" % [Game.cash, gs.stored.size()])
		var near := []
		for vv in get_tree().get_nodes_in_group(&"vehicles"):
			if (vv as Node3D).global_position.distance_to(gs._out) < 6.0:
				near.append("%s@%s" % [vv.name, (vv as Node3D).global_position])
		var v := gs.take_out(gs.stored.size() - 1)
		await runner.wait_seconds(0.5)
		ok("take car out of the garage", v != null and v.personal, "out %s spot %s near %s" % [gs._out, gs._spot, str(near)])
		SaveSystem.delete_save("test")
	# --- taxi
	var tr: Transit = Game.transit
	p.teleport(Vector3(36.0, 0.3, 60.0))
	await runner.wait_seconds(1.0)
	tr.call_taxi()
	var t := 0.0
	while t < 60.0 and tr.state == Transit.T.COMING:
		await runner.wait_seconds(1.0)
		t += 1.0
	ok("taxi arrives", tr.state == Transit.T.WAITING, "after %.0f s, state %d" % [t, tr.state])
	if tr.cab != null and is_instance_valid(tr.cab):
		var cab := tr.cab
		p.warp_into(cab, 1)
		tr.on_board(cab)
		await runner.wait_frames(5)
		if Game.menus.menu.visible:
			Game.menus.menu.close()
		var dest := Vector3(-185.0, 0.2, 137.0)
		tr._go(dest, "test destination")
		var start := cab.global_position
		await runner.wait_seconds(8.0)
		ok("taxi drives toward the destination", cab.global_position.distance_to(start) > 20.0, "%.0f m" % cab.global_position.distance_to(start))
		_cam_at(cab.global_position + Vector3(7, 5, 9), cab.global_position)
		await runner.wait_frames(5)
		await runner.shot("svc_taxi_ride")
		_release_cam()
		var cash0 := Game.cash
		await tr.skip_trip()
		await runner.wait_seconds(1.5)
		ok("taxi skip + fare", tr.state == Transit.T.NONE and Game.cash < cash0 and p.vehicle == null, "cash %d -> %d" % [cash0, Game.cash])
		ok("dropped near destination", p.global_position.distance_to(dest) < 90.0, "%.0f m" % p.global_position.distance_to(dest))
	# --- emergency services
	var es: EmergencyServices = Game.services
	if es != null and es.available("ambulance"):
		p.teleport(Vector3(36.0, 0.3, 60.0))
		await runner.wait_seconds(1.0)
		p.health = 50.0
		es.request("ambulance", p.global_position, true)
		t = 0.0
		var working := false
		while t < 70.0 and not working:
			await runner.wait_seconds(1.0)
			t += 1.0
			for u in es.units:
				if u.state >= EmergencyServices.U.WORK:
					working = true
		ok("ambulance responds", working, "after %.0f s" % t)
		await runner.shot("svc_ambulance")
	else:
		ok("ambulance responds (model not exported yet - skipped)", true)
	# --- stunt jump on the runway
	var act: Activities = Game.activities
	ok("activities", act != null and act.ramps.size() >= 3)
	if act != null:
		var r: Dictionary = act.ramps[1]
		var dirv: Vector3 = r["dir"]
		var car := AdminMenu.spawn_vehicle("car_sports", false)
		await runner.wait_frames(2)
		var at: Vector3 = (r["start"] as Vector3) - dirv * 70.0
		car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dirv.x, -dirv.z)), at + Vector3(0, 0.6, 0))
		p.warp_into(car, 0)
		await runner.wait_seconds(0.8)
		Input.action_press("move_forward")
		t = 0.0
		var logged := false
		while t < 14.0 and not act.completed.has(r["name"]):
			await runner.wait_physics(5)
			t += 5.0 / 60.0
			var cc := car as Car
			if cc.airborne_time > 0.0 and not logged:
				logged = true
				print("[dbg] airborne at ", cc.global_position, " speed ", cc.linear_velocity.length(), " vel ", cc.linear_velocity, " air_start ", cc.air_start, " lip ", r["lip"], " tracking ", act._tracking)
			elif cc.airborne_time == 0.0 and logged:
				logged = false
				print("[dbg] landed at ", cc.global_position, " upright ", cc.global_transform.basis.y.y)
		Input.action_release("move_forward")
		ok("stunt jump completed", act.completed.has(r["name"]), "best jump %.1f m" % float(Game.stats["best_jump"]))
		p.force_exit_vehicle()
		await runner.wait_frames(2)
		# --- shooting range
		act.start_challenge(Activities.CHALLENGES[0])
		await runner.wait_seconds(4.0)
		var hits := 0
		for tg in act._targets:
			if tg.up:
				tg.apply_damage(20.0, p, tg.to_global(tg.centre), Vector3.ZERO, {})
				hits += 1
		await runner.wait_seconds(0.5)
		_cam_at(p.global_position + Vector3(2.0, 2.2, 3.0), p.global_position + Vector3(0, 1.0, -12.0))
		await runner.wait_frames(5)
		await runner.shot("svc_range")
		_release_cam()
		act._range_t = 0.5
		await runner.wait_seconds(1.0)
		ok("range challenge scored", hits > 0 and int(act.best.get(Activities.CHALLENGES[0]["name"], 0)) >= hits, "hits %d best %d" % [hits, int(act.best.get(Activities.CHALLENGES[0]["name"], 0))])
	Game.cheats["invulnerable"] = false

func _jump_only() -> void:
	var p: Player = Game.player
	var act: Activities = Game.activities
	var r: Dictionary = act.ramps[1]
	var dirv: Vector3 = r["dir"]
	var car := AdminMenu.spawn_vehicle("car_sports", false)
	await runner.wait_frames(2)
	var at: Vector3 = (r["start"] as Vector3) - dirv * 70.0
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dirv.x, -dirv.z)), at + Vector3(0, 0.6, 0))
	p.warp_into(car, 0)
	await runner.wait_seconds(0.8)
	Input.action_press("move_forward")
	var t := 0.0
	var logged := false
	var shot_taken := false
	while t < 12.0:
		await runner.wait_physics(3)
		t += 3.0 / 60.0
		var cc := car as Car
		if not shot_taken and cc.global_position.distance_to(r["start"]) < 9.0:
			shot_taken = true
			_cam_at((r["lip"] as Vector3) + Vector3(14, 3, 6), r["lip"])
			await runner.shot("jump_ramp")
		if cc.airborne_time > 0.0 and not logged:
			logged = true
			print("[dbg] airborne at ", cc.global_position, " speed ", cc.linear_velocity.length(), " air_start ", cc.air_start, " lip ", r["lip"], " tracking ", act._tracking)
		elif cc.airborne_time == 0.0 and logged:
			logged = false
			print("[dbg] landed at ", cc.global_position, " upright ", cc.global_transform.basis.y.y, " t=", t)
	Input.action_release("move_forward")
	_release_cam()
	ok("stunt jump completed", act.completed.has(r["name"]), "best jump %.1f m" % float(Game.stats["best_jump"]))

## Chaos: five stars at night in a storm, shooting and grenades for a minute. Looks for script
## errors in system interplay and records the frame rate under load.
func t_chaos() -> void:
	await runner.wait_seconds(3.0)
	var p: Player = Game.player
	Game.cheats["invulnerable"] = true
	Game.cheats["infinite_ammo"] = true
	for id in WeaponDB.ORDER:
		p.inventory.give(id, -1, true)
	p.inventory.refill_all()
	Game.time.set_hour(22.0)
	Game.time.set_weather(&"storm", true)
	p.teleport(Vector3(36.0, 0.3, 60.0))
	await runner.wait_seconds(2.0)
	Game.wanted.set_level(5)
	p.gunner.equip(&"rifle_assault")
	var t := 0.0
	var min_fps := 999.0
	var fps_sum := 0.0
	var fps_n := 0
	var kills0: int = Game.stats["kills"]
	var shots := 0
	while t < 60.0:
		await runner.wait_seconds(0.5)
		t += 0.5
		var fps := Engine.get_frames_per_second()
		if t > 5.0:
			min_fps = minf(min_fps, fps)
			fps_sum += fps
			fps_n += 1
		var best: Node3D = null
		var bd := 60.0
		for n in get_tree().get_nodes_in_group(&"police_units"):
			var c := n as NPC
			if c != null and c.alive:
				var d := c.global_position.distance_to(p.global_position)
				if d < bd and Game.has_los(p.eye_position(), c.chest_position(), [p.get_rid(), c.get_rid()]):
					bd = d
					best = c
		if best != null:
			p.gunner.aiming = true
			p.gunner.aim_dir = ((best as NPC).chest_position() - p.eye_position()).normalized()
			p.set_face_yaw(atan2(-p.gunner.aim_dir.x, -p.gunner.aim_dir.z))
			for k in 3:
				if p.gunner.fire_at((best as NPC).chest_position()):
					shots += 1
				await runner.wait_physics(6)
		if int(t * 2.0) % 20 == 0:
			for v in get_tree().get_nodes_in_group(&"vehicles"):
				if (v as Vehicle).owner_tag == "police" and (v as Node3D).global_position.distance_to(p.global_position) < 30.0:
					Projectile.spawn("grenade", p.eye_position(), ((v as Node3D).global_position - p.eye_position()).normalized(), p, 16.0)
					break
		if is_equal_approx(t, 20.0) or is_equal_approx(t, 50.0):
			await runner.shot("chaos_%d" % int(t))
	p.gunner.aiming = false
	ok("player survived (god mode) and fought", p.alive and shots > 10, "%d shots, %d kills" % [shots, int(Game.stats["kills"]) - kills0])
	ok("wanted level held during the fight", Game.wanted.level >= 4, str(Game.wanted.level))
	ok("frame rate under load", min_fps >= 25.0 or Game.is_headless, "avg %.0f min %.0f fps" % [fps_sum / maxf(fps_n, 1), min_fps])
	print("[PERF] chaos avg %.1f min %.1f fps, vehicles %d, npcs %d" % [fps_sum / maxf(fps_n, 1), min_fps,
		get_tree().get_nodes_in_group(&"vehicles").size(), get_tree().get_nodes_in_group(&"npcs").size()])
	Game.wanted.clear(true)
	Game.cheats["invulnerable"] = false
	Game.cheats["infinite_ammo"] = false

## Night look: street lights, lit windows, headlights, neon.
func t_night() -> void:
	await runner.wait_seconds(4.0)
	Game.time.set_hour(23.0)
	Game.time.set_weather(&"clear", true)
	await runner.wait_seconds(3.0)
	var shots := [
		["night_downtown", Vector3(-70, 16, -30), Vector3(40, 30, -140)],
		["night_street", Vector3(36, 2.2, 20), Vector3(40, 3, -60)],
		["night_midtown", Vector3(20, 9, 62), Vector3(60, 2, 30)],
		["night_beach", Vector3(-150, 6, 240), Vector3(-60, 2, 215)],
	]
	Game.cheats["invulnerable"] = true
	for s in shots:
		AdminMenu.go(s[2])
		await runner.wait_seconds(2.0)
		_cam_at(s[1], s[2])
		await runner.wait_frames(8)
		await runner.shot(s[0])
	_release_cam()
	ok("night shots taken", true)

## Ragdolls: shot NPC goes limp, a car-hit NPC is thrown and gets up again.
func t_ragdoll() -> void:
	await runner.wait_seconds(3.0)
	var p: Player = Game.player
	var pm: PedManager = Game.peds
	var at := p.global_position + p.forward() * 5.0
	var a := pm.spawn(&"civil", at, 0.0)
	var b := pm.spawn(&"civil", at + Vector3(3.0, 0, 0), 0.0)
	await runner.wait_seconds(0.6)
	_cam_at(at + Vector3(4, 2.5, 5), at + Vector3(1.5, 0.6, 0))
	a.apply_damage(500.0, p, a.chest_position(), Vector3(0, 0.2, -1), {"type": "bullet", "force": 6.0})
	b.knockdown(Vector3(0, 3.0, -9.0), 2.0)
	await runner.wait_seconds(0.4)
	ok("dead NPC ragdolls", a.visual.ragdolling)
	ok("hard knockdown ragdolls", b.visual.ragdolling)
	await runner.shot("ragdoll_fall")
	await runner.wait_seconds(1.6)
	await runner.shot("ragdoll_rest")
	var hips := a.visual.ragdoll_hips()
	ok("ragdoll lies on the ground", hips.y < at.y + 0.6 and hips.y > at.y - 0.5, str(hips))
	await runner.wait_seconds(3.0)
	ok("knocked-down NPC got up", not b.down and not b.visual.ragdolling and b.alive)
	_release_cam()

## Every car / service vehicle with a model: spawns on the runway, accelerates, steers, brakes.
func t_roster() -> void:
	await runner.wait_seconds(3.0)
	var p: Player = Game.player
	Game.cheats["invulnerable"] = true
	Game.flags["traffic"] = false
	var ids: Array = []
	for g: String in ["Cars", "Service", "Bikes"]:
		for id in VehicleDB.GROUPS[g]:
			if VehicleDB.has_model(id):
				ids.append(id)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roster="):
			ids = [a.substr(9)]
	var lane_x := 279.0
	p.teleport(Vector3(lane_x + 14.0, 0.3, 80.0))
	await runner.wait_seconds(0.5)
	for id: String in ids:
		var at := Vector3(lane_x, 0.3, 80.0)
		var v := VehicleFactory.spawn(id, at, 0.0, {"tag": "player"})
		v.personal = true
		await runner.wait_seconds(0.8)
		_cam_at(v.global_position + Vector3(5.5, 2.2, -6.5), v.global_position + Vector3(0, 0.7, 0), 50.0)
		await runner.wait_frames(4)
		await runner.shot("car_" + id)
		_release_cam()
		var rest_ok := v.global_transform.basis.y.y > 0.95
		p.warp_into(v, 0)
		await runner.wait_seconds(0.4)
		Input.action_press("move_forward")
		if ids.size() == 1:
			for k in 24:
				await runner.wait_physics(10)
				print("[dbg] thr t=%d speed %.2f up %.2f pos %s yaw %.2f grounded %d" % [k, v.speed, v.global_transform.basis.y.y, v.global_position, v.global_rotation.y, (v as Car).grounded_wheels])
		else:
			await runner.wait_seconds(4.0)
		var top := absf(v.speed)
		Input.action_press("move_right")
		await runner.wait_seconds(1.0)
		Input.action_release("move_right")
		Input.action_release("move_forward")
		var upright := v.global_transform.basis.y.y > 0.8
		Input.action_press("move_back")
		var min_speed := 999.0
		for k in 24:
			await runner.wait_physics(10)
			min_speed = minf(min_speed, absf(v.speed))
			if ids.size() == 1:
				var cv := v as Car
				print("[dbg] brake t=%d speed %.2f in_thr %.2f in_brake %.2f hb %s grounded %d drv %s" % [k, v.speed, v.in_throttle, v.in_brake, v.in_handbrake, cv.grounded_wheels, v.driver() != null])
		Input.action_release("move_back")
		var stopped := min_speed < 2.0
		var need := 8.0 if (id in ["car_truck", "car_firetruck", "bicycle"]) else 12.0
		ok("%s drives" % id, rest_ok and top > need and upright and stopped, "rest %s top %.1f m/s upright %s stopped %s" % [rest_ok, top, upright, stopped])
		p.force_exit_vehicle()
		await runner.wait_frames(2)
		v.queue_free()
		p.teleport(Vector3(lane_x + 14.0, 0.3, 80.0))
		await runner.wait_frames(5)
	Game.flags["traffic"] = true
	Game.cheats["invulnerable"] = false

## Aircraft: the Kestrel takes off from the runway, the police Skywatch lifts off; a car gets mod parts.
func t_air() -> void:
	await runner.wait_seconds(3.0)
	var p: Player = Game.player
	Game.cheats["invulnerable"] = true
	Game.flags["traffic"] = false
	AdminMenu.go(Vector3(270.0, 0.3, 80.0))
	await runner.wait_seconds(0.5)
	var plane := AdminMenu.spawn_vehicle("plane_prop", true)
	await runner.wait_seconds(1.0)
	ok("plane spawned and seated", plane != null and p.vehicle == plane)
	if plane != null:
		var y0 := plane.global_position.y
		Input.action_press("air_up")
		await runner.wait_seconds(1.6)
		Input.action_release("air_up")
		var t := 0.0
		var rotated := false
		while t < 25.0:
			await runner.wait_physics(10)
			t += 10.0 / 60.0
			var a := plane as Airplane
			if not rotated and a.airspeed > float(a.def.get("stall", 21.0)) * 1.25:
				rotated = true
				Input.action_press("move_back")
				await runner.wait_seconds(1.2)
				Input.action_release("move_back")
			if rotated and plane.global_position.y - y0 > 40.0:
				break
		var alt := plane.global_position.y - y0
		ok("plane takes off and climbs", alt > 15.0 and plane.global_transform.basis.y.y > 0.5, "alt %.1f m after %.1f s, airspeed %.1f" % [alt, t, (plane as Airplane).airspeed])
		_cam_at(plane.global_position + Vector3(14, 4, 18), plane.global_position, 55.0)
		await runner.wait_frames(4)
		await runner.shot("air_plane")
		_release_cam()
		p.force_exit_vehicle()
		plane.queue_free()
		await runner.wait_frames(3)
	AdminMenu.go(Vector3(236.0, 0.3, -150.0))
	await runner.wait_seconds(0.5)
	var heli := AdminMenu.spawn_vehicle("heli_police", true)
	await runner.wait_seconds(1.0)
	ok("police helicopter spawned", heli != null and p.vehicle == heli)
	if heli != null:
		var hy := heli.global_position.y
		await runner.wait_seconds(2.5)
		Input.action_press("air_up")
		await runner.wait_seconds(4.0)
		Input.action_release("air_up")
		await runner.wait_seconds(1.0)
		ok("police helicopter lifts off", heli.global_position.y - hy > 6.0 and heli.global_transform.basis.y.y > 0.8, "%.1f m" % (heli.global_position.y - hy))
		_cam_at(heli.global_position + Vector3(10, 3, 14), heli.global_position, 55.0)
		await runner.wait_frames(4)
		await runner.shot("air_heli_police")
		_release_cam()
		p.force_exit_vehicle()
		heli.queue_free()
		await runner.wait_frames(3)
	# mod parts on a sports car
	AdminMenu.go(Vector3(36.0, 0.3, 60.0))
	await runner.wait_seconds(0.5)
	var car := AdminMenu.spawn_vehicle("car_sports", false)
	await runner.wait_seconds(0.8)
	if car != null:
		var before := Assets.find_meshes(car).size()
		var avail := VehicleMods.available(car, "spoiler", "spoiler_wing")
		VehicleMods.apply(car, "spoiler", "spoiler_wing")
		VehicleMods.apply(car, "wheels", "rim_sport5")
		VehicleMods.apply(car, "front", "bumper_splitter")
		VehicleMods.apply(car, "neon", "cyan")
		await runner.wait_frames(3)
		var after := Assets.find_meshes(car).size()
		ok("mod parts mount on the car", avail and after > before, "available %s meshes %d -> %d" % [avail, before, after])
		_cam_at(car.global_position + Vector3(4.5, 1.8, 5.5), car.global_position + Vector3(0, 0.5, 0), 50.0)
		await runner.wait_frames(4)
		await runner.shot("air_modded_car")
		_release_cam()
	Game.flags["traffic"] = true
	Game.cheats["invulnerable"] = false

func _block(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Phys.WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	b.add_child(mi)
	Game.world.add_child(b)
	b.global_position = pos + Vector3(0, size.y * 0.5, 0)
	return b

## Player moves: cover, vault, roll, melee, stealth takedown, carjacking, parachute, photo mode.
func t_moves() -> void:
	await runner.wait_seconds(3.0)
	var p: Player = Game.player
	Game.cheats["invulnerable"] = true
	AdminMenu.go(Vector3(-150.0, 0.0, 229.0))      # open beach
	await runner.wait_seconds(0.8)
	p.set_face_yaw(0.0)
	var base := p.global_position
	# cover behind a waist-high block
	var wall := _block(base + Vector3(0, 0, -1.1), Vector3(3.0, 1.1, 0.4))
	await runner.wait_physics(4)
	var covered := p.moves.try_cover()
	await runner.wait_seconds(0.6)
	ok("take cover", covered and p.moves.in_cover(), "low=%s" % p.moves.cover_low)
	p.moves.cancel()
	p.state = Player.St.FOOT
	await runner.wait_seconds(0.3)
	# vault over it
	p.teleport(base, 0.0)
	await runner.wait_physics(3)
	var vaulted := p.moves.try_vault(Vector3(0, 0, -1))
	await runner.wait_seconds(1.2)
	ok("vault over a low wall", vaulted and p.global_position.z < wall.global_position.z - 0.3, "vaulted %s z %.2f wall %.2f base.y %.2f wall.y %.2f" % [vaulted, p.global_position.z, wall.global_position.z, base.y, wall.global_position.y])
	wall.queue_free()
	# combat roll
	p.teleport(base, 0.0)
	await runner.wait_physics(3)
	if OS.get_cmdline_user_args().has("--vault-only"):
		return
	var x0 := p.global_position.x
	var rolled := p.moves.try_roll(Vector3(1, 0, 0))
	await runner.wait_seconds(0.9)
	ok("combat roll", rolled and p.global_position.x - x0 > 1.5, "%.2f m" % (p.global_position.x - x0))
	p.state = Player.St.FOOT
	# melee: three punches
	var pm: PedManager = Game.peds
	var victim := pm.spawn(&"civil", base + Vector3(0, 0.1, -1.2), PI)
	victim.brave = false
	await runner.wait_seconds(0.4)
	p.teleport(base, 0.0)
	p.gunner.equip(&"unarmed")
	var hp0 := victim.health
	for i in 3:
		p.set_face_yaw(atan2(-(victim.global_position.x - p.global_position.x), -(victim.global_position.z - p.global_position.z)))
		p.gunner.melee(false)
		await runner.wait_seconds(0.5)
	ok("melee hits", victim.health < hp0 or not victim.alive, "%.0f -> %.0f" % [hp0, victim.health])
	victim.queue_free()
	# stealth takedown from behind with a knife
	var mark := pm.spawn(&"civil", base + Vector3(0, 0.1, -1.0), 0.0)
	mark.calm()
	mark.home_area = {}
	mark.state = NPC.S.IDLE
	await runner.wait_seconds(0.3)
	mark.set_face_yaw(0.0)
	p.teleport(base, 0.0)
	p.inventory.give(&"knife")
	p.gunner.equip(&"knife")
	p.set_crouched(true)
	await runner.wait_physics(3)
	var td := p.moves.try_takedown()
	await runner.wait_seconds(1.6)
	ok("stealth takedown", td and not mark.alive, "started %s alive %s" % [td, mark.alive])
	p.set_crouched(false)
	p.state = Player.St.FOOT
	# carjacking a car with a driver
	AdminMenu.go(Vector3(36.0, 0.3, 60.0))
	await runner.wait_seconds(0.6)
	var car := VehicleFactory.spawn("car_sedan", p.global_position + p.forward() * 3.5 + Vector3(2.0, 0, 0), p.face_yaw + PI * 0.5, {"tag": "traffic"})
	await runner.wait_seconds(0.5)
	var drv := pm.seat_in(car, 0, &"driver")
	await runner.wait_seconds(0.3)
	p.global_position = car.door_position(0) + Vector3(0, 0.1, 0)
	await runner.wait_physics(3)
	p._try_enter_vehicle()
	await runner.wait_seconds(2.5)
	ok("carjack", p.vehicle == car and drv.vehicle == null, "player in car %s, old driver out %s" % [p.vehicle == car, drv.vehicle == null])
	p.force_exit_vehicle()
	await runner.wait_frames(3)
	# skydive + parachute over the park
	p.parachute = true
	p.teleport(Vector3(-100.0, 140.0, 75.0), 0.0)
	await runner.wait_frames(2)
	p.moves.start_freefall()
	await runner.wait_seconds(2.0)
	ok("free fall", p.moves.mode == PlayerMoves.Mode.FREEFALL, "agl %.0f" % p.moves.agl)
	Input.action_press("jump")
	await runner.wait_physics(2)
	Input.action_release("jump")
	await runner.wait_seconds(1.0)
	ok("parachute opens", p.moves.mode == PlayerMoves.Mode.CHUTE)
	_cam_at(p.global_position + Vector3(6, 3, 9), p.global_position + Vector3(0, 3, 0), 60.0)
	await runner.wait_frames(4)
	await runner.shot("moves_parachute")
	_release_cam()
	var t := 0.0
	while t < 40.0 and p.state != Player.St.FOOT:
		await runner.wait_seconds(0.5)
		t += 0.5
	ok("lands safely", p.alive and p.state == Player.St.FOOT, "after %.1f s" % t)
	# photo mode
	var ui: UIManager = Game.menus
	ui.enter_photo()
	await runner.wait_frames(5)
	ok("photo mode", ui.mode == "photo" and get_tree().paused)
	await ui._take_photo()
	var dir := DirAccess.open("user://photos")
	ok("photo saved", dir != null and dir.get_files().size() > 0)
	ui._exit_photo()
	await runner.wait_frames(3)
	ok("photo mode exits", ui.mode == "" and not get_tree().paused)
	Game.cheats["invulnerable"] = false

## The 60-second benchmark tour (writes user://benchmark.txt).
func t_bench() -> void:
	await runner.wait_seconds(5.0)
	Benchmark.start()
	await runner.wait_seconds(64.0)
	var f := FileAccess.open("user://benchmark.txt", FileAccess.READ)
	ok("benchmark report written", f != null)
	if f != null:
		print(f.get_as_text())

## Audio: every sound of the manifest loads, loops loop, ambience beds run, the car radio plays.
func t_audio() -> void:
	await runner.wait_seconds(3.0)
	var f := FileAccess.open("res://gta/resources/data/manifests/audio.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var sounds: Array = data["sounds"]
	var missing: Array = []
	var bad_loops: Array = []
	for e in sounds:
		var nm := StringName(String(e["name"]))
		if bool(e["loop"]):
			var ls := Audio.loop_stream(nm)
			if ls == null:
				missing.append(nm)
			elif ls is AudioStreamWAV and (ls as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
				bad_loops.append(nm)
		elif Audio.stream(nm) == null:
			missing.append(nm)
	ok("all sounds load", missing.is_empty(), "%d sounds, missing %s" % [sounds.size(), str(missing)])
	ok("loops are looping", bad_loops.is_empty(), str(bad_loops))
	var amb: Ambience = get_tree().root.find_child("Ambience", true, false) as Ambience
	ok("ambience beds", amb != null and amb.players.size() >= 6, str(amb.players.size() if amb else 0))
	var car := AdminMenu.spawn_vehicle("car_sedan", true)
	await runner.wait_seconds(1.5)
	ok("car radio plays", amb != null and amb.radio.playing, "station %d" % (amb.station if amb else -1))
	if amb != null:
		var pos0 := amb.radio.get_playback_position()
		await runner.wait_seconds(1.0)
		ok("radio advances", amb.radio.get_playback_position() != pos0)
		amb._tune(amb.station + 1)
		await runner.wait_seconds(0.5)
		ok("radio station change", amb.radio.playing or amb.station == 0)
	Game.player.force_exit_vehicle()
	await runner.wait_seconds(0.5)
	ok("radio stops on exit", amb == null or not amb.radio.playing)

## Boat, swimming / diving, fire engine response, police roadblock.
func t_misc() -> void:
	await runner.wait_seconds(3.0)
	var p: Player = Game.player
	Game.cheats["invulnerable"] = true
	if OS.get_cmdline_user_args().has("--fire-only"):
		await _fire_only()
		return
	# --- boat
	p.teleport(Vector3(86.0, 0.3, 218.0))
	await runner.wait_seconds(0.5)
	var boat := AdminMenu.spawn_vehicle("boat_speed", true)
	await runner.wait_seconds(1.5)
	ok("boat seated", boat != null and p.vehicle == boat)
	if boat != null:
		Input.action_press("move_forward")
		await runner.wait_seconds(4.0)
		var bsp := boat.linear_velocity.length()
		Input.action_release("move_forward")
		ok("boat drives on water", bsp > 8.0 and boat.global_position.y > Terrain.SEA - 1.5, "%.1f m/s y %.2f" % [bsp, boat.global_position.y])
		_cam_at(boat.global_position + Vector3(9, 4, 11), boat.global_position, 55.0)
		await runner.wait_frames(4)
		await runner.shot("misc_boat")
		_release_cam()
		# --- swim and dive from the boat
		p.force_exit_vehicle()
		var t := 0.0
		while t < 6.0 and p.state != Player.St.SWIM:
			await runner.wait_seconds(0.5)
			t += 0.5
		ok("player swims", p.state == Player.St.SWIM)
		p.scuba = false
		p.breath = 1.0
		Input.action_press("crouch")
		await runner.wait_seconds(3.0)
		Input.action_release("crouch")
		await runner.wait_seconds(1.0)
		ok("dives and loses breath", p.diving and p.breath < 0.98, "breath %.2f depth %.1f" % [p.breath, Game.water_surface(p.global_position) - p.global_position.y])
		_cam_at(p.global_position + Vector3(2.5, 0.6, 3.0), p.global_position + Vector3(0, 0.8, 0), 65.0)
		await runner.wait_frames(5)
		await runner.shot("misc_dive")
		_release_cam()
		Input.action_press("jump")
		await runner.wait_seconds(3.0)
		Input.action_release("jump")
		boat.queue_free()
	if OS.get_cmdline_user_args().has("--fire-only"):
		pass
	await _fire_only()
	# --- roadblock at 4 stars while driving fast on the arterial
	var pd: PoliceDispatch = Game.police
	# empty roads: the test drives blind (no steering), so traffic would only make it crash
	Game.flags["traffic"] = false
	Game.traffic.clear_traffic()
	AdminMenu.go(Vector3(-200.0, 0.3, 195.0))
	await runner.wait_seconds(0.5)
	var racer := AdminMenu.spawn_vehicle("car_sports", true)
	await runner.wait_seconds(1.0)
	if racer != null:
		racer.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-230.0, 0.6, 192.0))
		racer.linear_velocity = Vector3.ZERO
		await runner.wait_seconds(0.5)
		Game.wanted.set_level(4)
		Game.wanted.seen_now = true
		pd.debug_blocks = true
		var blocks := 0
		var t3 := 0.0
		Input.action_press("move_forward")
		while t3 < 20.0 and blocks == 0:
			await runner.wait_physics(15)
			t3 += 0.25
			Game.wanted.last_seen = Game.clock          # officers keep eyes on the suspect
			Game.wanted._set_state(WantedSystem.PURSUIT)
			pd._block_cd = minf(pd._block_cd, 0.5)
			for u in pd.units:
				if u.kind == &"block":
					blocks += 1
			if int(t3 * 4.0) % 8 == 0:
				print("[block] t %.1f speed %.1f state %d x %.0f" % [t3, absf(racer.speed), Game.wanted.state, racer.global_position.x])
			if racer.global_position.x > 150.0:
				break
		Input.action_release("move_forward")
		ok("police roadblock set up ahead", blocks > 0, "after %.1f s" % t3)
		Game.wanted.clear(true)
	Game.flags["traffic"] = true
	Game.cheats["invulnerable"] = false

func _fire_only() -> void:
	var p: Player = Game.player
	Game.cheats["invulnerable"] = true
	# --- fire engine to a burning car
	AdminMenu.go(Vector3(36.0, 0.3, 60.0))
	await runner.wait_seconds(0.8)
	var es: EmergencyServices = Game.services
	if es != null and es.available("fire"):
		var car := VehicleFactory.spawn("car_sedan", p.global_position + p.forward() * 8.0, 0.0, {"tag": "parked"})
		await runner.wait_seconds(0.5)
		car._start_fire(null)
		car._burn = 999.0
		var t2 := 0.0
		var out := false
		while t2 < 90.0 and not out:
			await runner.wait_seconds(1.0)
			t2 += 1.0
			out = is_instance_valid(car) and not car.on_fire
			if int(t2) % 10 == 0:
				for u in es.units:
					var ai_mode := -1
					var arrived := false
					if u.ai != null and is_instance_valid(u.ai):
						ai_mode = u.ai.mode
						arrived = u.ai.arrived
					print("[dbg] fire t=%d state %d dist %.0f ai %d arrived %s crew %d speed %.1f pos %s" % [int(t2), u.state, u.veh.global_position.distance_to(u.target), ai_mode, arrived, u.crew.size(), absf(u.veh.speed), u.veh.global_position])
					if u.ai != null and is_instance_valid(u.ai):
						var ai: AIDriver = u.ai
						var bl: String = String(ai._blocker.name) if ai._blocker != null and is_instance_valid(ai._blocker) else "-"
						print("[dbg]    gap %.1f gap_v %.1f blocked %.1f stuck %.1f swerve %.1f reverse %.1f waiting %s blocker %s ped %s lane %d s %.1f/%.1f next %d" % [ai._gap, ai._gap_v, ai.blocked, ai.stuck, ai._swerve, ai._reverse, ai.waiting, bl, ai._ped_ahead, ai.lane, ai.s, ai.graph.lanes[ai.lane].length if ai.lane >= 0 else 0.0, ai.next_lane])
				if es.units.is_empty():
					print("[dbg] fire t=%d no units, calls %d" % [int(t2), es.calls.size()])
		ok("fire engine puts the fire out", out, "after %.0f s, units %d" % [t2, es.active()])
		await runner.shot("misc_fire")

## Landmark look-around: shops (outside + inside), safehouse, gas station, airfield, waterfront.
func t_landmarks() -> void:
	await runner.wait_seconds(4.0)
	var city: CityBuilder = Game.world.city
	Game.cheats["invulnerable"] = true
	var views := [
		["shop_guns", Vector3(0, 3.0, -10.0), Vector3(0, 1.5, 0)],
		["shop_guns", Vector3(0, 1.7, 0.5), Vector3(0, 1.2, 5.0)],
		["shop_clothes", Vector3(-6, 3.0, -9.0), Vector3(0, 1.5, 0)],
		["shop_market", Vector3(0, 1.7, 1.0), Vector3(0, 1.2, 5.0)],
		["shop_barber", Vector3(5, 3.0, -8.0), Vector3(0, 1.5, 0)],
		["safehouse", Vector3(-9, 4.5, -14.0), Vector3(-3, 1.5, 0)],
		["lm_gas_station", Vector3(10, 5.0, -14.0), Vector3(0, 2.0, 0)],
		["lm_hangar", Vector3(14, 8.0, -34.0), Vector3(0, 4.0, 0)],
		["lm_control_tower", Vector3(30, 14.0, -30.0), Vector3(0, 12.0, 0)],
		["lm_lighthouse", Vector3(25, 10.0, -25.0), Vector3(0, 10.0, 0)],
		["lm_ferris_wheel", Vector3(-30, 10.0, -25.0), Vector3(0, 12.0, 0)],
		["lm_fountain", Vector3(8, 5.0, -10.0), Vector3(0, 1.0, 0)],
	]
	var n := 0
	for v in views:
		var key := String(v[0])
		if not city.locations.has(key):
			ok("landmark %s placed" % key, false)
			continue
		var root: Node3D = city.locations[key].get("root")
		if root == null:
			ok("landmark %s has a model" % key, false)
			continue
		var xf := root.global_transform
		AdminMenu.go(xf * Vector3(0, 0, -16.0))
		await runner.wait_seconds(0.8)
		_cam_at(xf * (v[1] as Vector3), xf * (v[2] as Vector3), 60.0)
		await runner.wait_frames(6)
		n += 1
		await runner.shot("lm_%02d_%s" % [n, key])
	_release_cam()
	ok("landmark views", n >= 10, str(n))

func t_matdbg() -> void:
	await runner.wait_frames(5)
	for rel: String in ["landmarks/shop_guns", "landmarks/lm_hangar", "landmarks/safehouse", "props/prop_umbrella"]:
		var inst := Assets.instance(rel)
		add_child(inst)
		var seen := {}
		for mi in Assets.find_meshes(inst):
			for si in mi.mesh.get_surface_count():
				var m := mi.get_active_material(si)
				var key := "%s|%s" % [m.resource_name if m else "null", (m as ShaderMaterial).shader.resource_path if m is ShaderMaterial else m.get_class() if m else "-"]
				if seen.has(key):
					continue
				seen[key] = true
				var arrays := mi.mesh.surface_get_arrays(si)
				var has_col: bool = arrays[Mesh.ARRAY_COLOR] != null and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0
				var c0 := (arrays[Mesh.ARRAY_COLOR] as PackedColorArray)[0] if has_col else Color(-1, -1, -1)
				print("[mat] %s  %s  vertex colours %s first %s  tint_a %s" % [rel, key, has_col, c0, mi.get_instance_shader_parameter(&"tint_a")])
		inst.queue_free()
	var pj: Dictionary = JSON.parse_string(FileAccess.open("res://gta/resources/data/palette.json", FileAccess.READ).get_as_text())
	var cols: Array = pj["colors"]
	for rel2: String in ["landmarks/lm_statue", "props/prop_bench", "landmarks/shop_garage"]:
		var inst2 := Assets.instance(rel2)
		var cnt := {}
		for mi in Assets.find_meshes(inst2):
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
				for k in range(0, uvs.size(), 7):
					var uv := uvs[k]
					var idx := int(uv.x * 16.0) + 16 * int(uv.y * 16.0)
					var nm := String(cols[idx][0]) if idx >= 0 and idx < cols.size() else "idx%d" % idx
					cnt[nm] = int(cnt.get(nm, 0)) + 1
		print("[uv] %s %s" % [rel2, str(cnt)])
		inst2.free()
	var st := Assets.instance("landmarks/lm_statue")
	var bench := Assets.instance("props/prop_bench")
	for pair in [["statue", st], ["bench", bench]]:
		for mi in Assets.find_meshes(pair[1]):
			for si in mi.mesh.get_surface_count():
				var m := mi.get_active_material(si)
				if m is ShaderMaterial:
					var tex: Variant = (m as ShaderMaterial).get_shader_parameter("pal_albedo")
					print("[tex] %s surf %d mat %s tex %s same_as_assets %s override %s lod_bias %s" % [pair[0], si, m.get_instance_id(), tex, tex == Assets.pal_albedo, mi.material_override, mi.lod_bias])
			break
	print("[pal] granite ", Assets.color("granite"), " gold ", Assets.color("gold"), " hazard_yellow ", Assets.color("hazard_yellow"))
	st.free()
	bench.free()
	# visual check: same model with default tint and with a red tint, side by side
	var at := Vector3(279.0, 0.0, 60.0)
	var a := Assets.instance("landmarks/lm_statue")
	var b := Assets.instance("landmarks/lm_statue")
	var c := Assets.instance("props/prop_umbrella")
	add_child(a)
	add_child(b)
	add_child(c)
	a.global_position = at + Vector3(-2.5, 0, 0)
	b.global_position = at + Vector3(2.5, 0, 0)
	c.global_position = at + Vector3(0, 0, 3.0)
	for mi in Assets.find_meshes(b):
		mi.lod_bias = 100.0          # force the full-detail mesh
	for mi in Assets.find_meshes(a):
		print("[lod] statue mesh %s lods %s" % [mi.name, str(mi.mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)])
	_cam_at(at + Vector3(0, 3.5, 12.0), at + Vector3(0, 2.0, 0), 60.0)
	await runner.wait_frames(8)
	await runner.shot("matdbg")
	_release_cam()
	ok("material dump", true)

func _tree(n: Node, depth: int) -> void:
	if depth > 3:
		return
	print("[tree] %s%s (%s)%s" % ["  ".repeat(depth), n.name, n.get_class(), (" mesh" if n is MeshInstance3D else "")])
	for c in n.get_children():
		_tree(c, depth + 1)

func t_treedbg() -> void:
	await runner.wait_frames(3)
	for rel: String in ["landmarks/lm_statue", "landmarks/shop_garage"]:
		var inst := Assets.instance(rel)
		_tree(inst, 0)
		var cp := PropFactory.part(inst, "col")
		print("[tree] part(col) -> %s %s" % [cp, cp.get_class() if cp else "-"])
		inst.free()
	ok("tree", true)

## Ladder climb up the radio tower, wildlife sightings, drive-by shooting.
func t_extras() -> void:
	await runner.wait_seconds(3.0)
	var p: Player = Game.player
	Game.cheats["invulnerable"] = true
	# --- ladder
	ok("ladders registered", not PlayerMoves.ladders.is_empty(), str(PlayerMoves.ladders.size()))
	if not PlayerMoves.ladders.is_empty():
		var l: Dictionary = PlayerMoves.ladders[0]
		var b: Vector3 = l["bottom"]
		var n: Vector3 = l["normal"]
		p.teleport(b + n * 0.8)
		await runner.wait_seconds(0.5)
		var hint := p.moves.prompt()
		Input.action_press("interact")
		await runner.wait_physics(3)
		Input.action_release("interact")
		await runner.wait_physics(3)
		ok("ladder grabbed", p.moves.mode == PlayerMoves.Mode.LADDER, "prompt '%s'" % hint)
		Input.action_press("move_forward")
		var t := 0.0
		while t < 30.0 and p.moves.mode == PlayerMoves.Mode.LADDER:
			await runner.wait_seconds(0.5)
			t += 0.5
		Input.action_release("move_forward")
		var top: Vector3 = l["top"]
		ok("climbed to the top", p.global_position.y > top.y - 1.5, "y %.1f top %.1f after %.0f s" % [p.global_position.y, top.y, t])
		_cam_at(p.global_position + Vector3(8, 3, 10), p.global_position, 60.0)
		await runner.wait_frames(5)
		await runner.shot("extra_radio_tower")
		_release_cam()
	# --- wildlife
	var wm: WildlifeManager = Game.wildlife
	for spot in [[Vector3(-150.0, 0.0, 229.0), "seagull"], [Vector3(-200.0, 20.0, -150.0), "deer"]]:
		AdminMenu.go(spot[0])
		var t2 := 0.0
		var found: Node3D = null
		while t2 < 20.0 and found == null:
			await runner.wait_seconds(1.0)
			t2 += 1.0
			for a in wm.animals:
				if is_instance_valid(a) and a.sp == String(spot[1]) and a.global_position.distance_to(p.global_position) < 90.0:
					found = a
					break
		ok("wildlife: %s nearby" % spot[1], found != null, "animals %d" % wm.count())
		if found != null:
			_cam_at(found.global_position + Vector3(2.5, 1.5, 3.5), found.global_position + Vector3(0, 0.4, 0), 50.0)
			await runner.wait_frames(5)
			await runner.shot("extra_%s" % spot[1])
			_release_cam()
	# --- drive-by: passenger seat aiming out of the window
	AdminMenu.go(Vector3(36.0, 0.3, 60.0))
	await runner.wait_seconds(0.5)
	var car := AdminMenu.spawn_vehicle("car_sedan", true)
	await runner.wait_seconds(1.0)
	p.inventory.give(&"smg")
	p.gunner.equip(&"smg")
	var shots0: int = Game.stats["shots_fired"]
	Input.action_press("aim")
	await runner.wait_seconds(0.4)
	Input.action_press("fire")
	await runner.wait_seconds(1.2)
	Input.action_release("fire")
	Input.action_release("aim")
	ok("drive-by fires from the car", int(Game.stats["shots_fired"]) > shots0 and p.vehicle == car, "%d shots" % (int(Game.stats["shots_fired"]) - shots0))
	Game.cheats["invulnerable"] = false
