extends Node
## Automated QA scenarios (run with:  godot --path . -- --test=<name>). Saves screenshots to res://_qa/.

var cam: Camera3D
var log_lines: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await get_tree().process_frame
	var m := "t_" + G.test_mode
	G.notify.connect(func(t: String, _c: Color): out("   NOTIFY: " + t))
	if has_method(m):
		await call(m)
	else:
		push_error("Unknown test " + G.test_mode)
	_flush()
	get_tree().quit()


func out(s: String) -> void:
	print("[test] " + s)
	log_lines.append(s)


func _flush() -> void:
	var f := FileAccess.open("res://_qa/test_%s.txt" % G.test_mode, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func secs(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func free_cam() -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.far = 2500.0
		cam.fov = 65.0
		add_child(cam)
	cam.make_current()


func shot(nm: String, pos: Vector3, target: Vector3, wait: int = 14, fov: float = 65.0) -> void:
	free_cam()
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	await frames(wait)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_qa/%s.png" % nm)
	out("shot " + nm)


func snap(nm: String, wait: int = 6) -> void:
	## Screenshot through whatever camera is current (gameplay camera).
	await frames(wait)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_qa/%s.png" % nm)
	out("snap " + nm)


func t_world() -> void:
	await frames(20)
	await shot("w_overview", Vector3(-40, 420, 520), Vector3(0, 0, 20), 20, 60.0)
	await shot("w_downtown", Vector3(60, 60, 60), Vector3(0, 20, -60))
	await shot("w_street", Vector3(4, 2.2, 30), Vector3(4, 4, -80))
	await shot("w_res", Vector3(-200, 16, -20), Vector3(-230, 0, -60))
	await shot("w_ind", Vector3(150, 22, -30), Vector3(210, 0, -80))
	await shot("w_coast", Vector3(-80, 14, 150), Vector3(-30, 0, 250))
	await shot("w_docks", Vector3(120, 26, 150), Vector3(200, 0, 215))
	await shot("w_airport", Vector3(40, 40, -150), Vector3(150, 0, -230))
	await shot("w_hill", Vector3(-110, 30, -170), Vector3(-208, 18, -243))
	await shot("w_park", Vector3(-80, 18, 90), Vector3(-44, 0, 42))


func t_night() -> void:
	G.timew.set_time(22.5)
	await frames(30)
	await shot("n_downtown", Vector3(60, 60, 60), Vector3(0, 20, -60), 30)
	await shot("n_street", Vector3(4, 2.2, 30), Vector3(4, 4, -80), 20)
	G.timew.set_time(18.2)
	G.timew.set_weather("rain", true)
	await shot("n_rain", Vector3(4, 2.2, 30), Vector3(4, 4, -80), 40)


func t_play() -> void:
	var p: Player = G.player
	await frames(40)
	await snap("p_spawn")
	p.cam.yaw += 2.6
	Input.action_press("aim")
	await frames(40)
	await snap("p_aim")
	p.inv.give("rifle")
	p.equip("rifle")
	await frames(40)
	await snap("p_aim_rifle")
	Input.action_release("aim")
	p.cam.yaw -= 2.6
	Input.action_press("move_forward")
	await frames(50)
	await snap("p_run")
	Input.action_release("move_forward")
	var v := VehicleFactory.spawn_near_player("sedan")
	await frames(90)
	out("car pos %s up %s" % [v.global_position, v.global_transform.basis.y])
	await snap("c_spawn")
	p.warp_into(v)
	await frames(30)
	await snap("c_in")
	Input.action_press("move_forward")
	await secs(4.0)
	out("speed %.1f pos %s" % [v.speed, v.global_position])
	await snap("c_drive")
	Input.action_press("move_right")
	await secs(1.2)
	out("turn speed %.1f yaw %.2f up %s" % [v.speed, v.rotation.y, v.global_transform.basis.y])
	await snap("c_turn")
	Input.action_release("move_right")
	Input.action_release("move_forward")


func counts() -> String:
	return "npcs %d moving %d vehicles %d wanted %d/%s units %d hp %.0f fps %d" % [G.peds.npcs.size() if G.peds else -1, G.traffic.moving.size() if G.traffic else -1,
		get_tree().get_nodes_in_group("vehicles").size(), G.wanted.level if G.wanted else -1, G.wanted.state if G.wanted else "", G.wanted.units.size() if G.wanted else -1,
		G.player.health, Engine.get_frames_per_second()]


func t_sim() -> void:
	var p: Player = G.player
	p.teleport(Vector3(10, 0.3, 40), 0.0)
	G.flags.god = true
	await secs(7.0)
	out(counts())
	await snap("s_street1")
	p.cam.yaw = PI
	await secs(6.0)
	out(counts())
	await snap("s_street2")
	G.wanted.set_level(3)
	await secs(11.0)
	out(counts())
	await snap("s_wanted")
	p.cam.yaw = 0.0
	await secs(4.0)
	out(counts())
	await snap("s_wanted2")


func t_systems() -> void:
	var p: Player = G.player
	G.flags.god = true
	await secs(1.0)
	out("wildlife animals %d birds %d fish %d" % [G.wildlife.animals.size(), G.wildlife.birds.size(), G.wildlife.fish.size()])
	# --- menus
	var it: Node = G.main.get_node("Interactions")
	it.open_gunshop()
	await frames(20)
	await snap("u_gunshop")
	it.menu.close()
	G.main.get_node("AdminMenu").open()
	await frames(20)
	await snap("u_admin")
	G.main.get_node("AdminMenu").menu.close()
	G.main.get_node("Menus").open_pause()
	await frames(10)
	await snap("u_pause")
	G.main.get_node("Menus").menu.close()
	out("ui_blocking after menus %d paused %s" % [G.ui_blocking, get_tree().paused])
	# --- combat
	p.teleport(Vector3(150, 0.4, -40), 0.0)
	for wid in Defs.WEAPON_ORDER:
		p.inv.give(wid, false)
	p.inv.refill_all()
	p.equip("rifle")
	await secs(0.5)
	var foe: NPC = G.peds.spawn("gang", p.global_position + Vector3(0, 0, -12))
	foe.engage(p)
	p.cam.yaw = 0.0
	p.cam.pitch = -0.02
	Input.action_press("aim")
	await secs(0.6)
	Input.action_press("fire")
	await secs(1.2)
	await snap("u_combat")
	Input.action_release("fire")
	Input.action_release("aim")
	out("foe dead %s hp %.0f  ammo %d shots %d" % [foe.dead, foe.health, p.inv.in_clip("rifle"), p.stats.shots])
	await secs(1.0)
	out(counts())
	# --- vehicles
	var heli := VehicleFactory.spawn("helicopter", Vector3(190, 0.5, -208), 0.0)
	var plane := VehicleFactory.spawn("plane", Vector3(-40, 0.6, -252), -PI * 0.5)
	var boat := VehicleFactory.spawn("speedboat", Vector3(140, G.WATER_LEVEL + 0.4, 232), PI)
	var bike := VehicleFactory.spawn("motorcycle", Vector3(150, 0.5, -30), 0.0)
	await secs(2.5)
	out("rest heli y %.2f plane y %.2f up %.2f boat y %.2f up %.2f bike y %.2f up %.2f" % [heli.global_position.y, plane.global_position.y, plane.global_transform.basis.y.y,
		boat.global_position.y, boat.global_transform.basis.y.y, bike.global_position.y, bike.global_transform.basis.y.y])
	p.warp_into(bike)
	Input.action_press("move_forward")
	await secs(2.5)
	out("bike speed %.1f up %.2f" % [bike.speed, bike.global_transform.basis.y.y])
	await snap("u_bike")
	Input.action_release("move_forward")
	p._leave_vehicle_now()
	p.warp_into(boat)
	Input.action_press("move_forward")
	await secs(3.5)
	out("boat speed %.1f y %.2f" % [boat.speed, boat.global_position.y])
	out("   boat thr %.2f engine %s in_water %d sleeping %s freeze %s driver %s pveh %s pos %s ui %d paused %s st %d seat %d fwd %.1f busy %s ragdoll %s" % [boat.throttle, boat.engine_on, (boat as Boat).in_water, boat.sleeping, boat.freeze, boat.driver != null, p.vehicle == boat, boat.global_position, G.ui_blocking, get_tree().paused, p.st, p.seat, Input.get_action_strength("move_forward"), p.busy, p.ragdoll != null])
	await snap("u_boat")
	Input.action_release("move_forward")
	p._leave_vehicle_now()
	p.warp_into(heli)
	Input.action_press("jump")
	await secs(4.5)
	out("heli y %.1f rotor %.2f" % [heli.global_position.y, heli.rotor])
	Input.action_press("move_forward")
	await secs(2.5)
	out("heli speed %.1f y %.1f" % [heli.speed, heli.global_position.y])
	await snap("u_heli")
	Input.action_release("move_forward")
	Input.action_release("jump")
	p._leave_vehicle_now()
	p.teleport(Vector3(-40, 0.6, -246), 0.0)
	p.warp_into(plane)
	Input.action_press("sprint")
	await secs(7.0)
	out("plane speed %.1f y %.1f" % [plane.speed, plane.global_position.y])
	Input.action_press("move_back")
	await secs(4.0)
	out("plane speed %.1f y %.1f x %.0f" % [plane.speed, plane.global_position.y, plane.global_position.x])
	await snap("u_plane")
	Input.action_release("move_back")
	Input.action_release("sprint")
	out(counts())


func t_police() -> void:
	var p: Player = G.player
	p.teleport(Vector3(10, 0.3, 40), 0.0)
	await secs(4.0)
	# crime in front of witnesses: shoot in the street
	p.inv.give("smg")
	p.equip("smg")
	Input.action_press("fire")
	await secs(1.5)
	Input.action_release("fire")
	await secs(9.0)
	out("after gunfire: " + counts())
	G.wanted.set_level(2)
	await secs(9.0)
	out("lvl2: " + counts())
	await snap("k_wanted2")
	# hide: teleport far away and wait for the search to expire
	p.teleport(Vector3(-230, 0.4, 120), 0.0)
	var t0 := Time.get_ticks_msec()
	while G.wanted.level > 0 and Time.get_ticks_msec() - t0 < 45000:
		await secs(0.5)
		var near := ""
		for n in G.peds.npcs:
			if is_instance_valid(n) and n.is_police and n.global_position_now().distance_to(p.global_position) < 30.0:
				near += " cop@%.1fm(arrest %.1f veh %s)" % [n.global_position_now().distance_to(p.global_position), n.arrest_t, n.vehicle != null]
		if near != "":
			out("   t=%.1f st %d pos %s%s" % [(Time.get_ticks_msec() - t0) / 1000.0, p.st, p.global_position, near])
	out("escape took %.1fs state %s level %d" % [(Time.get_ticks_msec() - t0) / 1000.0, G.wanted.state, G.wanted.level])
	# busted test: level 1 next to a cop, unarmed and standing still
	p.equip("fists")
	var cop: NPC = G.peds.spawn("cop", p.global_position + Vector3(4, 0, 0))
	G.wanted.report("assault", p.global_position, 1.1, true)
	await secs(7.0)
	out("busted? st=%d money %d level %d pos %s" % [p.st, p.money, G.wanted.level, p.global_position])
	await secs(4.5)
	out("after bust st=%d pos %s" % [p.st, p.global_position])
	# death + respawn
	p.take_damage(500.0, null, p.global_position, "bullet")
	await secs(1.0)
	await snap("k_dead")
	await secs(5.0)
	out("after death: dead %s hp %.0f pos %s" % [p.dead, p.health, p.global_position])
	if is_instance_valid(cop):
		cop.queue_free()


func t_misc() -> void:
	var p: Player = G.player
	G.flags.god = true
	# --- carjack a traffic car
	p.teleport(Vector3(10, 0.3, 40), 0.0)
	await secs(6.0)
	var victim: Vehicle = null
	for v in G.traffic.moving:
		if is_instance_valid(v) and v.driver != null and v.kind == "car":
			victim = v
			break
	if victim:
		victim.linear_velocity = Vector3.ZERO
		victim.ai.mode = "park"
		p.teleport(victim.door_point(0) + Vector3(0, 0.2, 0), 0.0)
		await frames(5)
		p.try_enter_vehicle()
		await secs(2.0)
		out("carjack: in vehicle %s driver_is_player %s stolen %d wanted %d" % [p.vehicle != null, victim.driver == p, p.stats.cars_stolen, G.wanted.level])
		await snap("m_carjack")
		# drive-by
		p.equip("smg")
		Input.action_press("aim")
		Input.action_press("fire")
		await secs(0.8)
		Input.action_release("fire")
		Input.action_release("aim")
		out("driveby shots %d" % p.stats.shots)
		p.try_exit_vehicle()
		await secs(1.0)
	G.wanted.clear()
	# --- swim + dive
	p.teleport(Vector3(-100, -0.5, 230), PI)
	await secs(2.0)
	out("swim st=%d y=%.2f breath %.2f" % [p.st, p.global_position.y, p.breath])
	Input.action_press("crouch")
	await secs(3.0)
	out("dive y=%.2f underwater %s breath %.2f" % [p.global_position.y, p.underwater, p.breath])
	await snap("m_dive")
	Input.action_release("crouch")
	# --- parachute from the tower
	p.give_parachute()
	p.teleport(G.world.tower_roof + Vector3(-13.5, 0.5, 0), -PI * 0.5)
	await secs(0.5)
	Input.action_press("move_forward")
	await secs(1.2)
	Input.action_press("jump")
	await frames(3)
	Input.action_release("jump")
	await secs(0.9)
	Input.action_press("jump")
	await frames(3)
	Input.action_release("jump")
	await secs(1.5)
	out("chute st=%d y=%.1f vy=%.1f" % [p.st, p.global_position.y, p.velocity.y])
	await snap("m_chute")
	Input.action_release("move_forward")
	var t0 := Time.get_ticks_msec()
	while p.st == p.St.CHUTE and Time.get_ticks_msec() - t0 < 30000:
		await secs(0.5)
	out("landed st=%d y=%.1f hp %.0f" % [p.st, p.global_position.y, p.health])
	# --- save / load round trip
	p.add_money(1234)
	var m0 := p.money
	out("save ok %s" % Save.save_game())
	p.add_money(-m0)
	p.teleport(Vector3(0, 1, 0))
	out("load ok %s money %d (expected %d) pos %s" % [Save.load_game(), p.money, m0, p.global_position])
	Save.delete_save()
	# --- taxi
	p.teleport(Vector3(10, 0.3, 40), 0.0)
	G.services.call_taxi()
	var t1 := Time.get_ticks_msec()
	while G.services.taxi_state == "coming" and Time.get_ticks_msec() - t1 < 40000:
		await secs(0.5)
	out("taxi state %s dist %.0f" % [G.services.taxi_state, G.services.taxi.global_position.distance_to(p.global_position) if G.services.taxi else -1.0])
	if G.services.taxi:
		p.teleport(G.services.taxi.door_point(2) + Vector3(0, 0.2, 0))
		await frames(5)
		p.try_enter_vehicle()
		await secs(1.5)
		G.services.menu.close()
		G.services._go(G.world.pois["hospital"].pos)
		await secs(6.0)
		out("taxi riding: state %s speed %.1f passenger %s" % [G.services.taxi_state, G.services.taxi.speed if G.services.taxi else -1.0, p.vehicle != null])
		await snap("m_taxi")
		G.services._skip_trip()
		await secs(5.0)
		out("after skip: state '%s' player pos %s money %d" % [G.services.taxi_state, p.global_position, p.money])
	# --- shooting range
	G.main.get_node("AdminMenu")._range()
	await secs(2.0)
	out("range on %s" % G.main.get_node("Activities").range_on)
	await snap("m_range")


func t_looks() -> void:
	var p: Player = G.player
	G.flags.god = true
	G.flags.peds = false
	G.flags.traffic = false
	await secs(0.5)
	# NPC line-up on the airport apron
	var base := Vector3(120, 0.1, -230)
	var kinds := ["civ", "civ", "civ", "civ", "civ", "cop", "swat", "gang", "medic", "fire", "clerk"]
	var made: Array = []
	for i in kinds.size():
		var n: NPC = G.peds.spawn(kinds[i], base + Vector3(i * 1.25, 0, 0))
		n.st = NPC.S.IDLE
		n.state_t = -60.0
		n.face_yaw = 0.0
		n.set_physics_process(false)
		if kinds[i] in ["cop", "swat", "gang"]:
			n._show_weapon(true)
			n.vis.aim = 1.0 if i % 2 == 0 else 0.0
		made.append(n)
	p.teleport(base + Vector3(-1.4, 0.2, 0), 0.0)
	p.inv.give("rifle")
	p.equip("rifle")
	Input.action_press("aim")
	await frames(40)
	await shot("l_npcs", base + Vector3(6.2, 1.5, -6.5), base + Vector3(6.2, 1.0, 0), 6, 50.0)
	await shot("l_npcs_close", base + Vector3(1.0, 1.5, -3.0), base + Vector3(1.2, 1.2, 0), 6, 45.0)
	await shot("l_player_aim", base + Vector3(-2.6, 1.6, -2.2), base + Vector3(-1.4, 1.2, 0), 6, 45.0)
	Input.action_release("aim")
	for n in made:
		n.queue_free()
	# vehicle line-up
	var x := 30.0
	var vs: Array = []
	for vid in ["compact", "sedan", "sports", "muscle", "suv", "pickup", "van", "taxi", "police", "ambulance", "truck", "firetruck", "swat", "motorcycle", "bicycle"]:
		var v := VehicleFactory.spawn(vid, Vector3(x, 0.5, -230), PI * 0.2)
		x += 3.0 + v.half.x * 2.0
		vs.append(v)
	await secs(1.5)
	await shot("l_vehicles1", Vector3(48, 5, -216), Vector3(52, 0.5, -230), 8, 60.0)
	await shot("l_vehicles2", Vector3(88, 6, -214), Vector3(90, 0.5, -230), 8, 60.0)
	# mods on the sports car
	var sp: Vehicle = vs[2]
	for slot in ["spoiler", "bumper_f", "bumper_r", "hood", "skirts", "exhaust", "livery", "wheels"]:
		sp.set_mod(slot, 1 if slot != "spoiler" else 2)
	sp.set_paint(Color("c9302a"), Color("f2efe8"), "Metallic")
	sp.set_roof(true)
	await shot("l_modded", sp.global_position + Vector3(3.8, 1.6, 4.4), sp.global_position + Vector3(0, 0.5, 0), 8, 50.0)
	# explosion
	var boom: Vehicle = vs[0]
	boom.explode(null)
	await frames(14)
	await shot("l_explosion", boom.global_position + Vector3(7, 3, 8), boom.global_position + Vector3(0, 1, 0), 1, 60.0)
	for v in vs:
		if is_instance_valid(v):
			v.queue_free()
	# night + rain in the city through the gameplay camera
	G.flags.peds = true
	G.flags.traffic = true
	p.teleport(Vector3(10, 0.3, 40), 0.0)
	p.cam.make_current_cam()
	G.timew.set_time(22.0)
	await secs(9.0)
	await snap("l_night")
	G.timew.set_time(18.3)
	G.timew.set_weather("storm", true)
	await secs(4.0)
	await snap("l_storm")
	out(counts())


func t_fx() -> void:
	var p: Player = G.player
	G.flags.god = true
	G.flags.peds = false
	G.flags.traffic = false
	p.teleport(Vector3(150, 0.3, -230), 0.0)
	await secs(1.0)
	var c := p.global_position + Vector3(0, 0, -9)
	G.fx.explosion(c + Vector3(0, 0.5, 0), 1.3)
	G.fx.dust(c + Vector3(4, 0.5, 0), 6)
	G.fx.sparks(c + Vector3(-4, 1.0, 0), 20)
	G.fx.splash(c + Vector3(-7, 0.2, 0), 1.5)
	await frames(5)
	await snap("f_fx1", 1)
	await frames(14)
	await snap("f_fx2", 1)
	var e: Node3D = G.fx.fire_at(c + Vector3(6, 0.1, 2), 1.2, 8.0)
	var holder := Node3D.new()
	G.main.add_child(holder)
	holder.global_position = c + Vector3(-5, 0.5, 3)
	var sm: Node3D = G.fx.attach_smoke(holder, Vector3.ZERO)
	sm.set_level(0.9)
	await secs(1.6)
	await snap("f_fx3", 1)
	if e == null:
		out("no fire")


func t_verify() -> void:
	var p: Player = G.player
	G.flags.god = true
	# --- traffic observation at a signalised junction
	p.teleport(Vector3(12, 0.3, -12), 0.0)
	await secs(12.0)
	var moving := 0
	var stopped := 0
	var off := 0
	var flipped := 0
	for v in G.traffic.moving:
		if not is_instance_valid(v):
			continue
		if v.speed > 1.0:
			moving += 1
		else:
			stopped += 1
		if not WorldLayout.on_road(v.global_position):
			off += 1
		if v.global_transform.basis.y.y < 0.7:
			flipped += 1
	out("traffic: moving %d stopped %d offroad %d flipped %d | %s" % [moving, stopped, off, flipped, counts()])
	await shot("v_traffic", Vector3(30, 26, 30), Vector3(0, 0, 0), 4, 60.0)
	await secs(10.0)
	moving = 0
	stopped = 0
	off = 0
	for v in G.traffic.moving:
		if is_instance_valid(v):
			if v.speed > 1.0:
				moving += 1
			else:
				stopped += 1
			if not WorldLayout.on_road(v.global_position):
				off += 1
	out("traffic later: moving %d stopped %d offroad %d" % [moving, stopped, off])
	p.cam.make_current_cam()
	# --- parachute: drop from 120 m above the park
	p.give_parachute()
	p.teleport(Vector3(-44, 120, 42), 0.0)
	await secs(1.3)
	Input.action_press("jump")
	await frames(3)
	Input.action_release("jump")
	await secs(2.0)
	out("chute st=%d y=%.1f vy=%.1f" % [p.st, p.global_position.y, p.velocity.y])
	await snap("v_chute")
	var t0 := Time.get_ticks_msec()
	while p.st == p.St.CHUTE and Time.get_ticks_msec() - t0 < 30000:
		await secs(0.5)
	out("landed st=%d y=%.2f hp %.0f in %.1fs" % [p.st, p.global_position.y, p.health, (Time.get_ticks_msec() - t0) / 1000.0])
	# --- cover against a jersey barrier / wall at the shooting range
	var poi: Dictionary = G.world.pois["range"]
	p.teleport(poi.pos + Vector3(0.2, 0.2, 0), -PI * 0.5)
	p.face_yaw = -PI * 0.5
	await secs(0.4)
	p._try_cover()
	await secs(0.6)
	out("cover in=%s low=%s normal=%s" % [p.in_cover, p.cover_low, p.cover_normal])
	await snap("v_cover")
	Input.action_press("aim")
	await secs(0.6)
	await snap("v_cover_aim")
	Input.action_release("aim")
	p.in_cover = false
	# --- ladder at the quay
	p.teleport(Vector3(140, -3.0, 196.2), 0.0)
	await secs(1.0)
	Input.action_press("move_forward")
	var t1 := Time.get_ticks_msec()
	while p.global_position.y < 0.1 and Time.get_ticks_msec() - t1 < 9000:
		await secs(0.25)
	Input.action_release("move_forward")
	out("ladder: st=%d pos %s after %.1fs" % [p.st, p.global_position, (Time.get_ticks_msec() - t1) / 1000.0])
	# --- train
	var tr: Node = G.main.get_node("Train")
	out("train s=%.0f speed %.1f stopped_at %d cars %d" % [tr.s, tr.speed, tr.stopped_at, tr.cars.size()])
	await shot("v_train", tr.cars[0].global_position + Vector3(14, 4, 14), tr.cars[0].global_position, 4, 60.0)
	# --- wildlife on the hill
	await shot("v_wild", G.wildlife.animals[0].global_position + Vector3(5, 2.5, 5), G.wildlife.animals[0].global_position + Vector3(0, 0.6, 0), 4, 55.0)
	out("animal0 %s at %s" % [G.wildlife.animals[0].kind, G.wildlife.animals[0].global_position])
	# --- mod shop performance check
	var car := VehicleFactory.spawn("sedan", Vector3(-40, 0.5, -252), -PI * 0.5) as Car
	await secs(1.0)
	p.warp_into(car)
	Input.action_press("move_forward")
	await secs(5.0)
	var s_stock := car.speed
	Input.action_release("move_forward")
	car.linear_velocity = Vector3.ZERO
	car.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-40, 0.5, -252))
	car.set_mod("engine", 3)
	car.set_mod("turbo", 1)
	car.set_mod("transmission", 2)
	await secs(0.5)
	Input.action_press("move_forward")
	await secs(5.0)
	out("mod perf: stock %.1f m/s after 5s, tuned %.1f m/s" % [s_stock, car.speed])
	Input.action_release("move_forward")
	out(counts())


func t_verify2() -> void:
	var p: Player = G.player
	G.flags.god = true
	var inter: Node = G.main.get_node("Interactions")
	# --- emergency response: ambulance to a casualty
	p.teleport(Vector3(12, 0.3, 30), 0.0)
	await secs(3.0)
	var vic: NPC = G.peds.spawn("civ", p.global_position + Vector3(3, 0, -6))
	await secs(0.5)
	vic.die(null, "bullet")
	G.services.dispatch("ambulance", vic.global_position)
	out("responders %d" % G.services.responders.size())
	var t0 := Time.get_ticks_msec()
	while G.services.responders.size() > 0 and String(G.services.responders[0].state) == "enroute" and Time.get_ticks_msec() - t0 < 45000:
		await secs(1.0)
	if G.services.responders.size() > 0:
		var r: Dictionary = G.services.responders[0]
		out("ambulance state %s after %.1fs dist %.1f" % [r.state, (Time.get_ticks_msec() - t0) / 1000.0, (r.veh as Vehicle).global_position.distance_to(r.pos)])
		await secs(4.0)
		out("crew %d state %s" % [(r.crew as Array).size(), r.state])
		await shot("w_ambulance", (r.pos as Vector3) + Vector3(9, 5, 9), r.pos, 4, 60.0)
	p.cam.make_current_cam()
	perf("after ambulance")
	# --- stealth takedown
	p.teleport(Vector3(-230, 0.4, 120), 0.0)
	await secs(1.0)
	var tgt: NPC = G.peds.spawn("civ", p.global_position + Vector3(0, 0, -1.3))
	tgt.face_yaw = 0.0
	tgt.rotation.y = 0.0
	await frames(3)
	p.crouching = true
	p.cam.yaw = 0.0
	p.face_yaw = 0.0
	out("can_takedown %s (aware %.2f)" % [tgt.can_takedown(p), tgt.aware])
	p._melee_attack(false)
	await secs(0.8)
	out("takedown: target dead %s kills %d" % [tgt.dead, p.stats.kills])
	p.crouching = false
	# --- weapon mods + garage
	p.inv.give("pistol")
	p.inv.give("smg")
	p.inv.add_mod("pistol", "suppressor")
	p.inv.add_mod("pistol", "extmag")
	p.equip("pistol")
	await secs(0.4)
	out("pistol mods %s mag %d" % [p.inv.mods_of("pistol"), p.inv.mag_size("pistol")])
	await snap("w_pistol_mod")
	var car := VehicleFactory.spawn("sports", p.global_position + Vector3(4, 0.5, 0), 0.0) as Car
	car.set_mod("spoiler", 1)
	car.set_paint(Color(0.9, 0.2, 0.5))
	await secs(0.8)
	inter.garage.append(car.export_state())
	car.queue_free()
	await secs(0.3)
	var back: Vehicle = inter._retrieve(0, true)
	await secs(0.8)
	out("garage retrieve: %s mods %s owned %s" % [back.vid, back.mods, back.owned])
	back.queue_free()
	perf("after garage")
	# --- train boarding
	var tr: Node = G.main.get_node("Train")
	var t1 := Time.get_ticks_msec()
	while tr.stopped_at < 0 and Time.get_ticks_msec() - t1 < 60000:
		await secs(0.5)
	out("train stopped_at %d after %.1fs" % [tr.stopped_at, (Time.get_ticks_msec() - t1) / 1000.0])
	if tr.stopped_at >= 0:
		tr._board()
		await secs(1.0)
		await snap("w_train_ride")
		var t2 := Time.get_ticks_msec()
		await secs(10.0)
		while tr.stopped_at < 0 and Time.get_ticks_msec() - t2 < 70000:
			await secs(0.5)
		tr.player_leave()
		await secs(0.5)
		out("left train: st=%d pos %s (ride %.1fs)" % [p.st, p.global_position, (Time.get_ticks_msec() - t2) / 1000.0])
	perf("after train")
	# --- stunt jump on the east ring road ramp
	var sc := VehicleFactory.spawn("sports", Vector3(284, 0.5, 150), 0.0) as Car
	await secs(0.8)
	p.warp_into(sc)
	var money0 := p.money
	Input.action_press("move_forward")
	var t3 := Time.get_ticks_msec()
	while sc.global_position.z > 0.0 and Time.get_ticks_msec() - t3 < 12000:
		await secs(0.1)
	Input.action_release("move_forward")
	await secs(2.5)
	out("stunt: done %s money +%d car at %s upright %.2f" % [G.main.get_node("Activities").stunts_done, p.money - money0, sc.global_position, sc.global_transform.basis.y.y])
	perf("after stunt")
	# --- 4 stars while driving: roadblock, helicopter, tactical units, drive-by
	sc.linear_velocity = Vector3.ZERO
	sc.angular_velocity = Vector3.ZERO
	sc.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-250, 0.5, 2.6))
	await secs(0.5)
	G.wanted.set_level(4)
	G.wanted.block_t = 1.0
	p.equip("smg")
	Input.action_press("move_forward")
	await secs(3.0)
	var shots0: int = p.stats.shots
	Input.action_press("fire")
	await secs(1.0)
	Input.action_release("fire")
	out("drive-by shots %d (weapon %s)" % [p.stats.shots - shots0, p.inv.current])
	var seen_block := 0
	var t4 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t4 < 24000:
		await secs(0.5)
		seen_block = maxi(seen_block, G.wanted.roadblocks.size())
		if int((Time.get_ticks_msec() - t4) / 500) % 6 == 0:
			perf("chase")
		if sc.speed < 2.0 and Time.get_ticks_msec() - t4 > 6000:
			break
	Input.action_release("move_forward")
	out("4 stars: roadblocks seen %d spikes %d heli %s | %s" % [seen_block, G.wanted.spikes.size(), is_instance_valid(G.wanted.heli), counts()])
	await snap("w_wanted4")
	if is_instance_valid(G.wanted.heli):
		await shot("w_heli", G.wanted.heli.global_position + Vector3(14, 3, 14), G.wanted.heli.global_position, 4, 50.0)
	p.cam.make_current_cam()
	G.wanted.set_level(5)
	await secs(10.0)
	var swat := 0
	for u in G.wanted.units:
		if is_instance_valid(u) and u.vid == "swat":
			swat += 1
	out("5 stars: swat vans %d | %s" % [swat, counts()])
	await snap("w_wanted5")
	G.wanted.clear()
	await secs(1.0)
	out("cleared: " + counts())


func perf(tag: String) -> void:
	var asleep := 0
	var frozen := 0
	for v in get_tree().get_nodes_in_group("vehicles"):
		if (v as RigidBody3D).sleeping:
			asleep += 1
		if (v as RigidBody3D).freeze:
			frozen += 1
	var emit := 0
	for e in get_tree().get_nodes_in_group("fx_emitters"):
		emit += 1
	out("   asleep %d frozen %d players %d" % [asleep, frozen, Sfx.active_count() if Sfx.has_method("active_count") else -1])
	out("%s | fps %d proc %.1fms phys %.1fms active %d pairs %d islands %d nodes %d draws %d prims %dk | %s" % [tag, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0), counts()])


func t_perf() -> void:
	var p: Player = G.player
	G.flags.god = true
	p.teleport(Vector3(12, 0.3, 30), 0.0)
	await secs(6.0)
	perf("idle city")
	p.inv.give("smg")
	var sc := VehicleFactory.spawn("sports", Vector3(-250, 0.5, 2.6), -PI * 0.5) as Car
	await secs(0.8)
	p.warp_into(sc)
	await secs(2.0)
	perf("in car")
	G.wanted.set_level(4)
	G.wanted.block_t = 1.0
	Input.action_press("move_forward")
	for i in 14:
		await secs(2.0)
		perf("4 stars t=%d" % (i * 2 + 2))
		if i == 5:
			Input.action_release("move_forward")
	G.wanted.clear()
	await secs(3.0)
	perf("cleared")
	var cnt := {}
	for n in G.main.get_children():
		var k := String(n.get_script().resource_path.get_file()) if n.get_script() != null else n.get_class()
		cnt[k] = int(cnt.get(k, 0)) + 1
	out("children: %s" % cnt)


func t_rest() -> void:
	## Parked cars must freeze when settled and wake when rammed, shot or entered.
	var p: Player = G.player
	G.flags.god = true
	p.teleport(Vector3(12, 0.3, 30), 0.0)
	await secs(7.0)
	perf("city after 7s")
	var a := VehicleFactory.spawn("sedan", Vector3(-250, 0.5, 2.6), -PI * 0.5) as Car
	var b := VehicleFactory.spawn("sports", Vector3(-280, 0.5, 2.6), -PI * 0.5) as Car
	await secs(3.5)
	out("parked sedan resting %s y %.2f" % [a.resting, a.global_position.y])
	p.warp_into(b)
	await secs(0.3)
	out("entered sports resting %s" % b.resting)
	Input.action_press("move_forward")
	var t0 := Time.get_ticks_msec()
	while a.resting and Time.get_ticks_msec() - t0 < 8000:
		await frames(1)
	await secs(0.25)
	Input.action_release("move_forward")
	out("after ram: sedan resting %s speed %.1f moved to x %.1f | sports speed %.1f" % [a.resting, a.speed, a.global_position.x, b.speed])
	await secs(4.0)
	out("later: sedan resting %s x %.1f upright %.2f" % [a.resting, a.global_position.x, a.global_transform.basis.y.y])
	await snap("r_rest")
	a.take_damage(5.0, p, a.global_position, "bullet")
	out("after bullet: resting %s" % a.resting)
	G.fx.explosion(a.global_position + Vector3(2.5, 0.2, 0), 1.0)
	G.damage_radius(a.global_position + Vector3(2.5, 0.2, 0), 7.0, 120.0, p)
	await secs(0.6)
	out("after blast: sedan speed %.1f y %.2f hp %.0f" % [a.speed, a.global_position.y, a.health])
	await secs(5.0)
	perf("end")


func t_stunt() -> void:
	var p: Player = G.player
	G.flags.god = true
	G.flags.traffic = false
	p.teleport(Vector3(284, 0.4, 110), 0.0)
	await secs(1.5)
	await shot("s_ramp_e", Vector3(300, 14, 96), Vector3(284, 1, 60), 6, 60.0)
	await shot("s_ramp_e2", Vector3(284, 5, 120), Vector3(284, 1, 60), 6, 60.0)
	p.cam.make_current_cam()
	var act: Node = G.main.get_node("Activities")
	for cfg in [[Vector3(284, 0.5, 140), 0.0, "z", -1.0], [Vector3(60, 0.5, -230), PI * 0.5, "x", -1.0]]:
		var sc := VehicleFactory.spawn("sports", cfg[0], cfg[1]) as Car
		await secs(0.8)
		p.warp_into(sc)
		Input.action_press("move_forward")
		var t3 := Time.get_ticks_msec()
		var maxy := 0.0
		while Time.get_ticks_msec() - t3 < 9000:
			await frames(2)
			maxy = maxf(maxy, sc.global_position.y)
			if sc.airtime > 0.0 and int(sc.airtime * 60.0) % 40 == 0:
				out("   air %.2f at %s speed %.1f" % [sc.airtime, sc.global_position, sc.speed])
		Input.action_release("move_forward")
		await secs(2.0)
		out("run yaw %.1f: car at %s max y %.1f speed %.1f stunts %s" % [cfg[1], sc.global_position, maxy, sc.speed, act.stunts_done])
		await secs(3.0)
		out("   after: player st %d pos %s car flooded %s y %.1f" % [p.st, p.global_position, sc.flooded, sc.global_position.y])
		await snap("s_after_%d" % int(cfg[1]))
		if p.vehicle != null:
			p._leave_vehicle_now()
		sc.queue_free()
		await secs(0.5)


func t_boat() -> void:
	var p: Player = G.player
	G.flags.god = true
	p.teleport(Vector3(12, 0.3, 30), 0.0)
	await secs(3.0)
	var bike := VehicleFactory.spawn("motorcycle", Vector3(150, 0.5, -30), 0.0) as Car
	await secs(2.5)
	out("bike resting %s y %.2f up %.2f" % [bike.resting, bike.global_position.y, bike.global_transform.basis.y.y])
	p.warp_into(bike)
	Input.action_press("move_forward")
	for i in 8:
		await secs(0.4)
		out("bike speed %.1f thr %.2f resting %s grounded %d up %.2f pos %s st %d ragdoll %s" % [bike.speed, bike.throttle, bike.resting, bike.grounded_count, bike.global_transform.basis.y.y, bike.global_position, p.st, p.ragdoll != null])
	Input.action_release("move_forward")


func t_orphans() -> void:
	await secs(2.0)
	print("[test] orphan nodes:")
	Node.print_orphan_nodes()


func _ev(action: String, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	Input.parse_input_event(e)


func t_final() -> void:
	var p: Player = G.player
	G.flags.god = true
	# --- climb onto the sandbag wall at the shooting range
	var poi: Dictionary = G.world.pois["range"]
	var y0 := 0.0
	var climbed := false
	for dx in [0.2, 0.6, 1.0, 1.4]:
		p.teleport(poi.pos + Vector3(dx, 0.2, 0), -PI * 0.5)
		p.face_yaw = -PI * 0.5
		await secs(0.5)
		y0 = p.global_position.y
		climbed = p._try_climb()
		if climbed:
			break
	await secs(1.0)
	out("climb: started %s dy %.2f" % [climbed, p.global_position.y - y0])
	# --- melee with a bat
	p.teleport(Vector3(-230, 0.4, 120), 0.0)
	await secs(0.8)
	p.inv.give("bat")
	p.equip("bat")
	p.cam.yaw = 0.0
	var npc: NPC = G.peds.spawn("civ", p.global_position + Vector3(0, 0, -1.3))
	await frames(4)
	var h0 := npc.health
	p._melee_attack(false)
	await secs(0.8)
	out("melee: npc hp %.0f -> %.0f dead %s" % [h0, npc.health, npc.dead])
	# --- knock over a promenade street lamp with a car
	var before := 0
	for c in G.world.get_children():
		if c is RigidBody3D and c.has_meta("prop_name"):
			before += 1
	var car := VehicleFactory.spawn("sedan", Vector3(-46, 0.5, 164), PI) as Car
	await secs(0.8)
	p.warp_into(car)
	Input.action_press("move_forward")
	await secs(3.0)
	Input.action_release("move_forward")
	await secs(1.0)
	var after := 0
	var names: Array = []
	for c in G.world.get_children():
		if c is RigidBody3D and c.has_meta("prop_name"):
			after += 1
			names.append(c.get_meta("prop_name"))
	out("props knocked: %d -> %d %s car at %s" % [before, after, names, car.global_position])
	await snap("f_prop")
	# --- time trial start
	G.main.get_node("Activities").start_trial()
	await secs(0.5)
	out("time trial on %s" % G.main.get_node("Activities").trial_on)
	G.main.get_node("Activities")._end_trial(false)
	p._leave_vehicle_now()
	# --- wreck fire + fire engine response
	p.teleport(Vector3(14, 0.3, 52), 0.0)
	await secs(2.0)
	var wreck := VehicleFactory.spawn("sedan", Vector3(4, 0.5, 40), 0.0)
	await secs(0.6)
	wreck.explode()
	await secs(0.5)
	var fe: Dictionary = {}
	for r in G.services.responders:
		if is_instance_valid(r.veh) and r.veh.vid == "firetruck":
			fe = r
	out("fire engine dispatched %s, wreck fire %s" % [not fe.is_empty(), wreck.fire != null])
	var t0 := Time.get_ticks_msec()
	while not fe.is_empty() and Time.get_ticks_msec() - t0 < 60000 and not (String(fe.state) == "work" and float(fe.t) > 8.0):
		await secs(0.5)
	if not fe.is_empty():
		out("fire engine state %s after %.1fs, wreck fire now %s" % [fe.state, (Time.get_ticks_msec() - t0) / 1000.0, wreck.fire != null])
		await shot("f_fire", wreck.global_position + Vector3(10, 6, 10), wreck.global_position, 4, 60.0)
	p.cam.make_current_cam()
	# --- UI: full map, weapon wheel, phone
	_ev("map", true)
	await frames(2)
	_ev("map", false)
	await secs(0.4)
	await snap("f_map")
	_ev("map", true)
	await frames(2)
	_ev("map", false)
	await secs(0.3)
	_ev("weapon_wheel", true)
	await secs(0.4)
	await snap("f_wheel")
	_ev("weapon_wheel", false)
	await secs(0.3)
	G.main.get_node("Menus").open_phone()
	await secs(0.4)
	await snap("f_phone")
	out("ui_blocking %d" % G.ui_blocking)
	out(counts())
