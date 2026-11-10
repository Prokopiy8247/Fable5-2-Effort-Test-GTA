extends Node
## Scripted validation runs: `-- --autotest=<name>`. Drives the real game through Input actions, prints state and
## saves screenshots to res://screens/. Always quits by itself (and the launcher adds a hard timeout).

var _n := 0
var _name := ""


func _ready() -> void:
	_name = Game.autotest
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[autotest] start: ", _name)
	await wait(1.0)
	var p = Game.player
	Game.flags.show_fps = true
	match _name:
		"boot":
			await _boot()
		"tour":
			await _tour()
		"drive":
			await _drive()
		"combat":
			await _combat()
		"wanted":
			await _wanted()
		"air":
			await _air()
		"water":
			await _water()
		"ui":
			await _ui()
		"night":
			await _night()
		"systems":
			await _systems()
		"perf":
			await _perf()
		"assets":
			await _assets()
		"bake_nav":
			await _bake_nav()
		"chute":
			await _chute()
		"export_data":
			_export_data()
		"flows":
			await _flows()
		"flows2":
			await _flows2()
		"final":
			await _final()
		_:
			print("[autotest] unknown test")
	print("[autotest] done: ", _name, " player=", p.global_position, " hp=", p.health)
	get_tree().quit()


func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func shot(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		_n += 1
		return
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://screens")
	Game.screenshot("%s/%s_%02d_%s.png" % [dir, _name, _n, tag])
	_n += 1


func look(yaw: float, pitch: float = -0.2) -> void:
	Game.cam.yaw = yaw
	Game.cam.pitch = pitch
	Game.cam._mouse_idle = 0.0


func aim_at(target: Vector3) -> void:
	var o: Vector3 = Game.cam.cam.global_position
	var d := (target - o).normalized()
	Game.cam.yaw = atan2(-d.x, -d.z)
	Game.cam.pitch = asin(clampf(d.y, -1.0, 1.0))
	Game.cam._mouse_idle = 0.0


func side_shot(tag: String, offset: Vector3) -> void:
	## Screenshot from a temporary camera placed relative to the player (for pose / asset checks).
	var p = Game.player
	var c := Camera3D.new()
	Game.world.add_child(c)
	c.global_position = p.global_transform * offset
	c.look_at(p.global_position + Vector3.UP * 1.2, Vector3.UP)
	c.fov = 55.0
	c.make_current()
	await wait(0.15)
	await shot(tag)
	Game.cam.cam.make_current()
	c.queue_free()


func tp(pos: Vector3, yaw: float = 0.0, pitch: float = -0.2) -> void:
	Game.player.teleport(pos, yaw)
	look(yaw, pitch)
	await wait(0.6)


func press(action: String, dur: float) -> void:
	Input.action_press(action)
	await wait(dur)
	Input.action_release(action)


func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func stats(tag: String) -> void:
	print("[autotest] %s fps=%d vehicles=%d npcs=%d wanted=%d state=%s pos=%s" % [tag, Engine.get_frames_per_second(), Game.vehicles.size(), Game.npcs.size(),
		Wanted.level, Wanted.state, str(Game.player.global_position)])


func _boot() -> void:
	await wait(1.5)
	await shot("spawn")
	stats("boot")
	await press("move_fwd", 1.5)
	await shot("walk")
	stats("after-walk")


func _tour() -> void:
	var t: Dictionary = Game.world.teleports
	var views := [["Downtown", 0.6, -0.1], ["Midtown Market", -0.4, -0.15], ["Founders Park", 0.8, -0.2], ["Palm Court (residential)", 2.4, -0.15],
		["Ironworks (industrial)", -1.2, -0.15], ["Airfield apron", 0.3, -0.12], ["Coral Beach", 2.9, -0.15], ["Port Marlow docks", -2.6, -0.2],
		["Signal Hill viewpoint", -1.7, -0.25], ["Tower rooftop (base jump)", 2.2, -0.5], ["Gun shop", 0.0, -0.1], ["Safehouse", 0.0, -0.1],
		["Torque House garage", 0.0, -0.1], ["Police station", 0.0, -0.1], ["Hospital", 0.0, -0.1], ["Skyline station", 3.1, 0.0], ["Marina pier", 3.1, -0.2]]
	for v in views:
		if not t.has(v[0]):
			print("[autotest] missing teleport ", v[0])
			continue
		await tp(t[v[0]], v[1], v[2])
		await wait(0.9)
		await shot(String(v[0]).replace(" ", "_").replace("(", "").replace(")", ""))
		stats(v[0])


func _drive() -> void:
	var p = Game.player
	await tp(Vector3(-150, 0.5, 16.5), -PI * 0.5)
	var v := Admin.spawn("sedan")
	v.place(Vector3(-150, 0.8, 12.5), -PI * 0.5)
	await wait(1.0)
	print("[autotest] car rest y=", v.global_position.y, " up=", v.global_basis.y)
	await shot("car_spawned")
	await tap("enter_vehicle")
	await wait(1.2)
	print("[autotest] in vehicle: ", p.in_vehicle())
	await shot("in_car")
	await press("move_fwd", 4.0)
	print("[autotest] speed after 4s: ", v.speed, " pos=", v.global_position)
	await shot("driving")
	Input.action_press("move_fwd")
	await press("move_right", 0.9)
	Input.action_release("move_fwd")
	print("[autotest] after turn: yaw=", v.global_rotation.y, " speed=", v.speed)
	await press("handbrake", 1.5)
	print("[autotest] after brake: speed=", v.speed)
	await shot("stopped")
	await tap("enter_vehicle")
	await wait(0.8)
	print("[autotest] exited: ", not p.in_vehicle(), " player=", p.global_position)
	# motorcycle
	var b := Admin.spawn("motorcycle")
	await wait(0.8)
	await tap("enter_vehicle")
	await wait(1.0)
	await press("move_fwd", 3.0)
	print("[autotest] bike speed=", b.speed, " up=", b.global_basis.y.y)
	await shot("bike")
	await tap("enter_vehicle")
	await wait(0.5)
	stats("traffic")
	await wait(4.0)
	await shot("traffic")
	stats("traffic2")


func _combat() -> void:
	var p = Game.player
	await tp(Vector3(40, 0.5, -236), 0.0)
	for id in Data.weapon_order:
		p.inv.give(id)
	p.inv.refill_all()
	Wanted.enabled = false
	p.equip("assault_rifle")
	var n := Npc.spawn("civ", p.global_position + Vector3(0, 0, -9))
	await wait(0.5)
	look(0.0, -0.05)
	Input.action_press("aim")
	await wait(0.6)
	n._set_state(Npc.S.IDLE)
	n._wait = 99.0
	aim_at(n.global_position + Vector3.UP * 1.2)
	await wait(0.3)
	aim_at(n.global_position + Vector3.UP * 1.2)
	await wait(0.2)
	await shot("aim")
	await side_shot("aim_side", Vector3(2.6, 1.4, -1.2))
	Input.action_press("fire")
	await wait(1.2)
	Input.action_release("fire")
	await shot("fired")
	print("[autotest] target dead=", (not is_instance_valid(n)) or n.dead, " ammo=", p.inv.entry().mag)
	Input.action_release("aim")
	p.equip("rocket_launcher")
	look(0.0, 0.05)
	Input.action_press("aim")
	await wait(0.5)
	await tap("fire")
	await wait(1.6)
	await shot("rocket")
	Input.action_release("aim")
	p.equip("grenade")
	await tap("fire")
	await wait(3.6)
	await shot("grenade")
	p.equip("bat")
	var n2 := Npc.spawn("civ", p.global_position + Vector3(0, 0, -1.4))
	await wait(0.3)
	look(0.0, -0.1)
	await tap("fire")
	await wait(0.8)
	print("[autotest] melee target hp=", n2.health if is_instance_valid(n2) else -1.0)
	await shot("melee")
	# cover
	await tp(Vector3(133.8, 0.4, -222), -PI * 0.5)
	await tap("cover")
	await wait(0.6)
	print("[autotest] cover state=", p.state == Player.St.COVER, " low=", p.cover_low)
	await shot("cover")
	await tap("cover")
	# weapon wheel
	Input.action_press("weapon_wheel")
	await wait(0.4)
	await shot("wheel")
	Input.action_release("weapon_wheel")
	await wait(0.3)
	Wanted.enabled = true


func _wanted() -> void:
	var p = Game.player
	await tp(Vector3(-50, 0.5, 14), -PI * 0.5)
	Game.flags.invuln = true
	p.inv.give("smg")
	p.inv.refill_all()
	p.equip("smg")
	Wanted.set_level(2)
	stats("set2")
	await wait(9.0)
	stats("after9s")
	await shot("wanted2")
	Wanted.set_level(4)
	await wait(12.0)
	stats("level4")
	await shot("wanted4")
	look(Game.cam.yaw, 0.5)
	await wait(0.4)
	await shot("sky")
	# escape test: hide far away
	Wanted.set_level(1)
	await tp(Vector3(-250, 25.0, -90), 0.0)
	var t0 := Time.get_ticks_msec()
	while Wanted.level > 0 and Time.get_ticks_msec() - t0 < 30000:
		await wait(1.0)
	print("[autotest] escaped=", Wanted.level == 0, " after ", (Time.get_ticks_msec() - t0) / 1000.0, "s")
	stats("end")
	Game.flags.invuln = false


func _air() -> void:
	var p = Game.player
	Game.flags.invuln = true
	await tp(Vector3(222, 0.5, -232), 0.0)
	await wait(1.0)
	var h: Vehicle = p.nearest_vehicle(30.0)
	print("[autotest] using showcase vehicle: ", h.def.id)
	p._mount(h, 0)
	await wait(0.5)
	await shot("heli_ground")
	await press("jump", 6.0)
	print("[autotest] heli y=", h.global_position.y, " rotor=", h.rotor_speed)
	Input.action_press("jump")
	await press("move_fwd", 4.0)
	Input.action_release("jump")
	print("[autotest] heli pos=", h.global_position, " vel=", h.linear_velocity)
	await shot("heli_fly")
	p._leave_vehicle(true)
	await wait(3.2)
	print("[autotest] falling y=", p.global_position.y, " chute prompt=", p._chute_prompt)
	await tap("jump")
	await wait(1.5)
	print("[autotest] chute state=", p.state == Player.St.CHUTE)
	await shot("parachute")
	await wait(3.0)
	# plane takeoff
	await tp(Vector3(-240, 0.5, -266), -PI * 0.5)
	var pl := Admin.spawn("plane")
	pl.place(Vector3(-250, 0.8, -272), -PI * 0.5)
	await wait(1.0)
	p._mount(pl, 0)
	await shot("plane_ground")
	Input.action_press("move_fwd")
	await wait(7.0)
	print("[autotest] plane speed=", pl.linear_velocity.length(), " thr=", pl.plane_throttle, " pos=", pl.global_position)
	Input.action_press("jump")
	await wait(4.0)
	Input.action_release("jump")
	print("[autotest] plane alt=", pl.global_position.y, " speed=", pl.linear_velocity.length())
	await shot("plane_fly")
	await wait(3.0)
	print("[autotest] plane alt2=", pl.global_position.y, " pos=", pl.global_position)
	Input.action_release("move_fwd")
	Game.flags.invuln = false


func _water() -> void:
	var p = Game.player
	await tp(Vector3(60, 0.6, 236), PI)
	var b := Admin.spawn("speedboat")
	b.place(Vector3(67, Game.WATER_Y + 0.6, 240), PI)
	await wait(2.0)
	print("[autotest] boat y=", b.global_position.y, " in_water=", b.in_water)
	await shot("boat_idle")
	p._mount(b, 0)
	await press("move_fwd", 5.0)
	print("[autotest] boat speed=", b.speed, " pos=", b.global_position)
	await shot("boat_run")
	p._leave_vehicle(true)
	await tp(Vector3(-120, 0.5, 234), PI)
	await wait(2.0)
	print("[autotest] swimming=", p.is_swimming(), " y=", p.global_position.y)
	await shot("swim")
	await press("crouch", 2.5)
	print("[autotest] underwater=", p.underwater, " y=", p.global_position.y, " breath=", p.breath)
	await shot("dive")
	await tp(Vector3(-170, -2.0, 252), PI)
	await press("crouch", 3.0)
	await shot("wreck")


func _ui() -> void:
	var p = Game.player
	await tp(Vector3(-50, 0.5, 14), 0.0)
	Game.hud.open_admin()
	await wait(0.5)
	await shot("admin")
	Game.hud.menu.close()
	Game.hud.open_shop("gun")
	await wait(0.4)
	await shot("gunshop")
	Game.hud.menu.push("Weapons", func(): return Shops.gun_weapons(Game.hud.menu))
	await wait(0.4)
	await shot("gunshop_weapons")
	Game.hud.menu.close()
	Game.hud.open_big_map()
	await wait(0.4)
	await shot("bigmap")
	Game.hud.close_big_map()
	var v := Admin.spawn("sports")
	await wait(0.6)
	p._mount(v, 0)
	Game.hud.open_shop("mod")
	await wait(0.4)
	await shot("modshop")
	v.mods["spoiler"] = 2
	v.mods["paint_color"] = Color("2f9c95")
	v.mods["rims"] = 1
	v.mods["neon"] = 1
	v.mods["hood"] = 1
	v.apply_mods()
	Game.hud.menu.close()
	look(v.global_rotation.y + 2.4, -0.2)
	await wait(0.6)
	await shot("modded_car")
	Game.hud.menu.open("pause", "PAUSED", func(): return Shops.pause(Game.hud.menu), true)
	await wait(0.4)
	await shot("pause")
	Game.hud.menu.push("Stats", func(): return Shops.stats())
	await wait(0.3)
	await shot("stats")
	Game.hud.menu.close()
	print("[autotest] save=", SaveGame.save_game(true), " load=", SaveGame.load_game())
	await wait(0.5)
	Game.hud.open_shop("clothes")
	await wait(0.3)
	await shot("clothes")
	Game.hud.menu.close()


func _night() -> void:
	await tp(Vector3(8, 0.5, -60), 0.3)
	Game.daynight.set_hour(22.0)
	await wait(2.0)
	await shot("night_downtown")
	stats("night")
	Game.daynight.set_weather("storm", true)
	await wait(2.5)
	await shot("storm")
	Game.daynight.set_hour(17.55)
	Game.daynight.set_weather("clear", true)
	await tp(Vector3(-120, 0.5, 192), 1.9, -0.05)
	await wait(1.5)
	await shot("sunset_beach")
	Game.daynight.set_hour(12.0)
	Game.daynight.set_weather("fog", true)
	await wait(1.5)
	await shot("fog")
	Game.daynight.set_weather("rain", true)
	await tp(Vector3(8, 0.5, -60), 0.3)
	await wait(2.0)
	await shot("rain")


func _systems() -> void:
	var p = Game.player
	Game.flags.invuln = true
	# taxi
	await tp(Vector3(-50, 0.5, 16.5), 0.0)
	Game.world.emergency.call_taxi()
	await wait(1.0)
	print("[autotest] taxi state=", Game.world.emergency.taxi_state)
	# train
	await tp(Vector3(-170, 6.4, 192.5), 0.0)
	await wait(1.0)
	await shot("station")
	print("[autotest] interact=", p.interact_target.get("text", "-"))
	# ladder + vault
	if not Game.world.ladders.is_empty():
		var l: Dictionary = Game.world.ladders[0]
		await tp(l.pos + l.out * 0.8, 0.0)
		p.grab_ladder(l)
		await press("move_fwd", 3.5)
		print("[autotest] ladder: y=", p.global_position.y, " top=", l.top, " state=", p.state)
		await shot("ladder")
	# carjack
	await tp(Vector3(-150, 0.5, 14), 0.0)
	await wait(3.0)
	var target = null
	for v in Game.traffic.ambient:
		if is_instance_valid(v) and v.driver_rig != null:
			target = v
			break
	if target:
		p.teleport(target.door_pos(0) + Vector3(0, 0.3, 0))
		await wait(0.2)
		await tap("enter_vehicle")
		await wait(1.5)
		print("[autotest] carjack: in_vehicle=", p.in_vehicle(), " wanted heat=", Wanted.heat)
		await shot("carjack")
		p._leave_vehicle(true)
	# wildlife
	await tp(Vector3(-250, 25.0, -100), 0.0)
	await wait(3.0)
	var animals := 0
	for c in Game.world.npc_root.get_children():
		if c is Animal:
			animals += 1
	print("[autotest] animals active=", animals)
	await shot("hill")
	# shooting range
	await tp(Game.world.activities.range_pos, -PI * 0.5)
	await wait(0.6)
	p.inv.give("pistol", 200)
	p.equip("pistol")
	Game.world.activities.start_range()
	await wait(0.6)
	await shot("range")
	print("[autotest] range active=", Game.world.activities.range_active)
	stats("systems-end")
	Game.flags.invuln = false


func _perf() -> void:
	Game.flags.invuln = true
	var samples := []
	for spot in [Vector3(8, 0.5, -90), Vector3(-50, 0.5, 14), Vector3(150, 0.5, 6), Vector3(-120, 0.5, 192)]:
		await tp(spot, 0.5)
		for i in range(6):
			await wait(1.0)
			samples.append(Engine.get_frames_per_second())
		stats("perf")
	Wanted.set_level(5)
	await tp(Vector3(-50, 0.5, 14), 0.5)
	for i in range(14):
		await wait(1.0)
		samples.append(Engine.get_frames_per_second())
	stats("perf-5star")
	await shot("five_stars")
	var mn := 999.0
	var sum := 0.0
	for s in samples:
		mn = minf(mn, s)
		sum += s
	print("[autotest] PERF avg=%.1f min=%.1f samples=%d draw_calls=%d objects=%d" % [sum / samples.size(), mn, samples.size(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	print("[autotest] MEM static=%.1f MB  video=%.1f MB" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
	Game.flags.invuln = false


func cam_shot(tag: String, pos: Vector3, target: Vector3, fov: float = 50.0) -> void:
	var c := Camera3D.new()
	Game.world.add_child(c)
	c.global_position = pos
	c.look_at(target, Vector3.UP)
	c.fov = fov
	c.make_current()
	await wait(0.2)
	await shot(tag)
	Game.cam.cam.make_current()
	c.queue_free()


func _assets() -> void:
	## Line-up of vehicles, characters and weapons for the asset-quality gate.
	Game.flags.traffic = false
	Game.flags.peds = false
	await tp(Vector3(-20, 0.5, -215), 0.0)
	await wait(1.0)
	var x := -70.0
	var xs := []
	for id in Data.vehicle_order:
		var d: VehicleDef = Data.vehicles[id]
		if d.kind == "boat":
			continue
		var v: Vehicle = Game.traffic.spawn_vehicle(id, Vector3(x, 1.0, -262), PI * 0.8)
		xs.append(x)
		x += maxf(v._half.x * 2.0 + 3.2, 4.5) if not v.is_air() else 14.0
	await wait(2.5)
	var i := 0
	while i < xs.size():
		var cx: float = (xs[i] + xs[mini(i + 3, xs.size() - 1)]) * 0.5
		await cam_shot("vehicles", Vector3(cx - 2.0, 3.2, -250.0), Vector3(cx, 0.8, -262.0), 58.0)
		i += 4
	var kinds := ["civ", "civ", "civ", "civ", "civ", "cop", "swat", "gang", "clerk", "medic"]
	for k in range(kinds.size()):
		var n := Npc.spawn(kinds[k], Vector3(96.0 + k * 1.5, 0.2, -240))
		n.state = Npc.S.IDLE
		n._wait = 999.0
		n.rotation.y = 0.0
		if kinds[k] in ["cop", "swat", "gang"]:
			n.rig.set_weapon(n.weapon)
	Game.player.teleport(Vector3(94.5, 0.2, -240), 0.0)
	await wait(1.2)
	await cam_shot("characters", Vector3(102.5, 1.5, -246.5), Vector3(102.5, 1.0, -240.0), 62.0)
	await cam_shot("characters_close", Vector3(105.5, 1.5, -243.0), Vector3(105.5, 1.2, -240.0), 50.0)
	stats("assets")


func _bake_nav() -> void:
	## Editor-automation step: bake the pedestrian/police navigation mesh from the built city and cache it.
	Game.flags.traffic = false
	Game.flags.peds = false
	Game.flags.wildlife = false
	await wait(1.0)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Game.L_WORLD
	nm.cell_size = 0.5
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 46.0
	nm.region_min_size = 40.0
	nm.filter_baking_aabb = AABB(Vector3(-300, -1.4, -300), Vector3(600, 34, 512))
	var src := NavigationMeshSourceGeometryData3D.new()
	var t0 := Time.get_ticks_msec()
	NavigationServer3D.parse_source_geometry_data(nm, src, Game.world)
	print("[autotest] nav parse ms=", Time.get_ticks_msec() - t0)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	print("[autotest] nav bake ms=", Time.get_ticks_msec() - t0, " polys=", nm.get_polygon_count(), " verts=", nm.get_vertices().size())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://gta/generated/nav"))
	var err := ResourceSaver.save(nm, "res://gta/generated/nav/city_navmesh.res")
	print("[autotest] nav saved err=", err)


func _chute() -> void:
	var p = Game.player
	Game.flags.invuln = true
	await tp(Vector3(-128, 160.0, 150), PI)
	await wait(1.6)
	print("[autotest] falling y=", p.global_position.y, " prompt=", p._chute_prompt, " vy=", p.velocity.y)
	await tap("jump")
	await wait(1.0)
	print("[autotest] chute state=", p.state == Player.St.CHUTE, " vy=", p.velocity.y)
	await shot("chute")
	await side_shot("chute_side", Vector3(6.0, 3.0, -7.0))
	var t0 := Time.get_ticks_msec()
	while p.state == Player.St.CHUTE and Time.get_ticks_msec() - t0 < 30000:
		await wait(0.5)
	print("[autotest] landed at ", p.global_position, " state=", p.state, " hp=", p.health)
	await shot("landed")


func _export_data() -> void:
	## Editor-automation step: write the data registries and UI theme out as .tres resources.
	for sub in ["weapons", "vehicles"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://gta/resources/data/" + sub))
	for id in Data.weapons:
		ResourceSaver.save(Data.weapons[id], "res://gta/resources/data/weapons/%s.tres" % id)
	for id in Data.vehicles:
		ResourceSaver.save(Data.vehicles[id], "res://gta/resources/data/vehicles/%s.tres" % id)
	ResourceSaver.save(GameMenu.make_theme(), "res://gta/resources/themes/menu_theme.tres")
	print("[autotest] exported ", Data.weapons.size(), " weapon defs, ", Data.vehicles.size(), " vehicle defs, 1 theme")


func _press_all(items: Array, limit: int = 99) -> int:
	## Invoke every callback of a menu builder result (smoke test for shop code paths).
	var n := 0
	for it in items:
		if it.has("cb") and not it.get("disabled", false) and n < limit:
			it.cb.call()
			n += 1
	return n


func _flows() -> void:
	var p = Game.player
	var m: GameMenu = Game.hud.menu
	Game.add_money(500000)
	await tp(Vector3(40, 0.5, -236), 0.0)
	# --- shops (call every purchase path once)
	Game.hud.open_shop("gun")
	print("[autotest] gun weapons: ", _press_all(Shops.gun_weapons(m)))
	print("[autotest] gun ammo: ", _press_all(Shops.gun_ammo(m)))
	p.equip("carbine")
	print("[autotest] gun mods: ", _press_all(Shops.gun_mods(m)), " mods=", p.inv.entry().mods)
	print("[autotest] gun tints: ", _press_all(Shops.gun_tints(m), 3))
	_press_all(Shops.gun(m))
	m.close()
	Game.hud.open_shop("clothes")
	for w in Data.WARDROBE:
		_press_all(Shops.clothes_options(w, false), 2)
	_press_all(Shops.clothes(m))
	m.close()
	Game.hud.open_shop("barber")
	_press_all(Shops.barber(m))
	m.close()
	Shops._set_look("hair", "hair_mohawk", 0)
	Shops._set_look("beard", "beard", 0)
	Shops._set_look("gender", "female", 0)
	await wait(0.3)
	await side_shot("female_look", Vector3(1.6, 1.3, -2.4))
	Shops._set_look("gender", "male", 0)
	Game.hud.open_shop("food")
	p.health = 40.0
	_press_all(Shops.food(m))
	m.close()
	print("[autotest] hp after food=", p.health, " money=", Game.money)
	# --- mod shop: every option
	var v := Admin.spawn("muscle")
	await wait(0.8)
	p._mount(v, 0)
	Game.hud.open_shop("mod")
	var cnt := 0
	for up in Data.UPGRADES:
		cnt += _press_all(Shops.mod_options(m, up))
	for cat in ["Cosmetic", "Body", "Performance"]:
		Shops.mod_cat(m, cat)
	v.health = v.max_health * 0.5
	_press_all(Shops.mod(m), 2)
	m.close()
	print("[autotest] mod options pressed=", cnt, " engine_mult=", v.engine_mult, " health=", v.health, " mods=", v.mods.size())
	await side_shot("modded_muscle", Vector3(4.5, 2.0, -5.5))
	# --- garage store / retrieve
	Game.hud.open_shop("garage")
	_press_all(Shops.garage(m), 1)
	await wait(0.3)
	print("[autotest] stored=", Game.world.stored_vehicles.size(), " in_vehicle=", p.in_vehicle())
	_press_all(Shops.garage(m), 1)
	m.close()
	await wait(0.5)
	print("[autotest] stored after retrieve=", Game.world.stored_vehicles.size())
	# --- admin menu smoke
	for b in [Admin.root(m), Admin.player(m), Admin.world(m), Admin.toggles(m), Admin.weapons(m), Admin.wanted(m), Admin.vehicles(m), Admin.teleport(m), Admin.vehicle(m)]:
		pass
	_press_all(Admin.world(m))
	_press_all(Admin.player(m))
	Game.daynight.set_weather("clear", true)
	Game.daynight.set_hour(10.0)
	Game.daynight.minutes_per_second = 1.0
	Game.daynight.paused_time = false
	Game.flags.unlock_all = false
	Game.flags.invuln = false
	Game.flags.scuba = false
	# --- phone + pause builders
	Shops.phone(m)
	Shops.pause(m)
	Shops.stats()
	Shops.controls()
	_press_all(Shops.settings())
	Game.settings.vsync = true
	Game.settings.max_fps = 60
	Game.settings.render_scale = 1.0
	Game.settings.shadows = true
	Game.settings.master_volume = 0.8
	Game.apply_settings()
	await _flows2()


func _flows2() -> void:
	var p = Game.player
	Game.add_money(50000)
	# --- death and respawn
	await tp(Vector3(40, 0.5, -236), 0.0)
	p.damage(500.0, p.global_position + Vector3(1, 0, 0), null, "bullet")
	print("[autotest] dead state=", p.state == Player.St.DEAD)
	await wait(4.5)
	print("[autotest] respawned at ", p.global_position, " hp=", p.health, " state=", p.state)
	# --- busted
	Wanted.set_level(1)
	var c := Npc.spawn("cop", p.global_position + Vector3(1.5, 0, 0))
	Wanted.cops.append(c)
	await wait(5.0)
	print("[autotest] busted count=", Game.stats.busted, " wanted=", Wanted.level, " pos=", p.global_position)
	await wait(2.5)
	# --- taxi ride with skip
	await tp(Vector3(-50, 0.5, 16.5), 0.0)
	Wanted.clear(true)
	Game.world.emergency.call_taxi()
	var t0 := Time.get_ticks_msec()
	while Game.world.emergency.taxi_state == "coming" and Time.get_ticks_msec() - t0 < 25000:
		await wait(0.5)
	print("[autotest] taxi state=", Game.world.emergency.taxi_state)
	if Game.world.emergency.taxi_state == "waiting":
		Game.world.emergency._set_destination(Vector3(150, 0, 110))
		await wait(2.0)
		print("[autotest] riding=", p.state == Player.St.RIDE)
		await shot("taxi_ride")
		Game.world.emergency._skip_ride()
		await wait(0.5)
		print("[autotest] after skip pos=", p.global_position, " state=", p.state)
	# --- train
	await tp(Vector3(-170, 6.4, 192.3), 0.0)
	var tr: SkylineTrain = Game.world.train
	t0 = Time.get_ticks_msec()
	while not (tr.at_station == 0 and tr.dwell > 1.0) and Time.get_ticks_msec() - t0 < 60000:
		await wait(0.5)
	tr._board(0)
	await wait(6.0)
	print("[autotest] train riding=", tr.riding, " x=", tr.x, " player state=", p.state)
	await shot("train_ride")
	t0 = Time.get_ticks_msec()
	while tr.at_station != 1 and Time.get_ticks_msec() - t0 < 30000:
		await wait(0.5)
	tr._try_exit()
	await wait(0.5)
	print("[autotest] got off at ", p.global_position, " state=", p.state)
	# --- explosions, fire, roadblock, heli, wildlife
	Game.flags.invuln = true
	await tp(Vector3(-50, 0.5, 16.5), -PI * 0.5)
	Fx.explosion(p.global_position + Vector3(12, 0.5, 0), 9.0, 200.0, p)
	Fx.fire_patch(p.global_position + Vector3(6, 0, 3), 4.0, 2.5, p)
	Projectile.launch("molotov", p.global_position + Vector3(0, 1.5, 0), Vector3(8, 4, 0), p, 40.0)
	await wait(2.0)
	await shot("explosion")
	stats("after-explosion")
	var car := Admin.spawn("sports")
	car.place(Vector3(-80, 0.6, 12.5), -PI * 0.5)
	await wait(0.6)
	p._mount(car, 0)
	look(-PI * 0.5)
	Wanted.set_level(4)
	await press("move_fwd", 2.5)
	Wanted._try_roadblock(p)
	print("[autotest] roadblocks=", Wanted.blocks.size(), " helis=", Wanted.helis.size(), " cars=", Wanted.cars.size(), " cops=", Wanted.cops.size())
	await press("move_fwd", 6.0)
	await shot("pursuit")
	stats("pursuit")
	Game.flags.invuln = false
	car.damage(99999.0)
	await wait(2.0)
	print("[autotest] after car explosion: state=", p.state, " hp=", p.health)
	Wanted.clear(true)
	await wait(1.0)
	for a in Game.world.npc_root.get_children():
		if a is Animal:
			a.hit(999.0, p)
			break
	print("[autotest] flows complete money=", Game.money)
	Game.flags.invuln = false


func _final() -> void:
	## Final validation pass: free-roam start, key interact points, counts, no-mission check.
	var p = Game.player
	var w = Game.world
	print("[autotest] start state=", p.state, " in safehouse at ", p.global_position, " ui_blocked=", Game.ui_blocked())
	await press("move_back", 1.0)
	print("[autotest] player can move: ", p.global_position.distance_to(w.safehouse_spawn) > 0.5)
	print("[autotest] interactables=", w.interactables.size(), " ladders=", w.ladders.size(), " pois=", w.pois.size(), " teleports=", w.teleports.size(),
		" pickups=", w.pickups.items.size(), " props=", w.props.recs.size(), " buildings=", w.buildings.get_child_count(), " nav=", Npc.nav_ready)
	for item in [["gunshop", "E  Brass"], ["safehouse", "E  "]]:
		pass
	for it in w.interactables:
		if String(it.text).begins_with("E  Brass"):
			await tp(it.offset + Vector3(0, 0.2, -1.0), 0.0)
			await wait(0.4)
			print("[autotest] gun shop prompt: ", p.interact_target.get("text", "-"))
			await shot("gunshop_interior")
			await side_shot("gunshop_side", Vector3(3.5, 1.6, -3.5))
	var v := Admin.spawn("sedan")
	v.place(w.mod_bay + Vector3(0, 0.5, 0), w.mod_bay_yaw)
	await wait(0.8)
	p._mount(v, 0)
	await wait(0.4)
	print("[autotest] mod bay prompt: ", p.interact_target.get("text", "-"))
	look(w.mod_bay_yaw + 2.6, -0.25)
	await wait(0.5)
	await shot("mod_bay")
	p._leave_vehicle(true)
	await tp(w.teleports["Tower rooftop (base jump)"], 2.2, -0.45)
	await shot("rooftop")
	await tp(Vector3(-2, 0.5, 60), 0.0, -0.1)
	await wait(6.0)
	stats("midtown")
	await shot("midtown_life")
	var missions := 0
	for n in get_tree().root.find_children("*", "", true, false):
		var nm := String(n.name).to_lower()
		if nm.contains("mission") or nm.contains("quest"):
			missions += 1
	print("[autotest] mission/quest nodes in scene tree: ", missions)
