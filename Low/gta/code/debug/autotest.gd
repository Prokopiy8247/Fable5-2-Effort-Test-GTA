class_name AutoTest
extends Node
# Scripted validation runs: godot --path . -- --autotest=boot,tour,drive,...
# Prints "[test]" lines and writes screenshots to the run tmp folder, then quits.

var plan := ""
var out_dir := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	out_dir = ProjectSettings.globalize_path("res://").path_join(".fable-5.2-gta-runs/run-20261109-214834/tmp")
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.max_fps = 30
	G.invulnerable = true
	_run.call_deferred()


func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func shot(sname: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(out_dir.path_join(sname + ".png"))
		print("[test] shot ", sname)


func view(pos: Vector3, yaw: float, pitch := -0.15) -> void:
	G.player.warp(pos)
	G.cam.yaw = yaw
	G.cam.pitch = pitch
	G.cam.last_mouse = G.time_now + 100.0


func _run() -> void:
	await wait(1.5)
	for step in plan.split(","):
		print("[test] ---- ", step)
		await call("t_" + step)
	print("[test] DONE fps=%d npcs=%d vehicles=%d props=%d nav=%s" % [Engine.get_frames_per_second(), G.humanoids.size(), G.vehicles.size(), G.props.size(), G.world.nav_ready])
	get_tree().quit()


func t_boot() -> void:
	await wait(3.0)
	print("[test] player at ", G.player.global_position, " on_floor=", G.player.is_on_floor(), " state=", G.player.state)
	await shot("boot")
	var seen := {}
	for mi in G.main.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			if mi.get_active_material(i) == null and not seen.has(mi.name):
				seen[mi.name] = true
				print("[test] NULL MATERIAL: ", mi.get_path(), " surface ", i)


func t_tour() -> void:
	var spots := [["downtown", Vector3(-40, 0.3, -40), 0.6, -0.05], ["safehouse", Vector3(-118, 0.3, 3), PI / 2, -0.1], ["gunshop", Vector3(-2, 0.3, 40), 0.5, -0.05],
		["industrial", Vector3(-40, 0.3, -120), 0.9, -0.05], ["park", Vector3(-80, 0.4, 20), 0.2, -0.15], ["beach", Vector3(-60, 0.5, 186), 2.6, -0.1],
		["docks", Vector3(84, 0.6, 176), -2.4, -0.05], ["airport", Vector3(186, 0.3, -90), 0.9, -0.1], ["hill", Vector3(-60, 24.5, -256), PI, -0.25],
		["residential", Vector3(-200, 0.3, 40), -1.2, -0.05], ["police", Vector3(84, 0.3, -124), 0.0, 0.05], ["rooftop", Vector3(-14, 57, -100), 2.4, -0.4]]
	for s in spots:
		view(s[1], s[2], s[3])
		await wait(1.6)
		await shot("tour_" + s[0])


func t_night() -> void:
	G.sky.time = 22.5
	view(Vector3(-40, 0.3, -40), 0.6, 0.0)
	await wait(4.0)
	await shot("night_downtown")
	G.sky.set_weather("storm")
	G.sky.auto_weather = false
	await wait(5.0)
	await shot("night_storm")
	G.sky.time = 13.0
	G.sky.set_weather("rain")
	await wait(5.0)
	await shot("day_rain")
	G.sky.set_weather("clear")
	await wait(3.0)


func _drive(id: String, pos: Vector3, yaw: float) -> Vehicle:
	var v: Vehicle = G.traffic.spawn_vehicle(id, pos, yaw)
	await wait(0.6)
	G.player.global_position = v.global_position + Vector3(2, 0, 0)
	G.player._seat(v)
	return v


func t_drive() -> void:
	G.traffic.enabled = false
	await wait(0.5)
	for id in ["sedan", "sports", "motorcycle", "truck"]:
		var v: Vehicle = await _drive(id, Vector3(-190, 0.3, 124.5), -PI / 2)
		G.player.test_input = Vector2(0, 1)
		var mx := 0.0
		for k in 16:
			await wait(0.5)
			mx = max(mx, v.fspeed)
			if k == 6:
				G.player.test_input = Vector2(0.35, 1)
			if k == 8:
				G.player.test_input = Vector2(0, 1)
		print("[test] %s max_speed=%.1f m/s pos=%s up=%.2f health=%.0f grounded=%d" % [id, mx, v.global_position, v.global_basis.y.y, v.health, v.grounded])
		if id == "sedan":
			await shot("drive_sedan")
		G.player.test_input = Vector2(0, -1)
		await wait(2.5)
		print("[test] %s after braking speed=%.1f" % [id, v.fspeed])
		G.player.test_input = null
		G.player.exit_vehicle()
		await wait(0.3)
		print("[test] exit ok state=", G.player.state, " pos=", G.player.global_position)
		v.queue_free()
		await wait(0.2)
	G.traffic.enabled = true


func t_fly() -> void:
	var v: Vehicle = await _drive("heli", Vector3(195, 0.4, 20), 0.0)
	G.player.test_lift = 1.0
	await wait(6.0)
	print("[test] heli alt=%.1f rotor=%.2f" % [v.global_position.y, v.rotor])
	G.player.test_input = Vector2(0, 1)
	G.player.test_lift = 0.0
	await wait(5.0)
	print("[test] heli speed=%.1f alt=%.1f up=%.2f" % [v.linear_velocity.length(), v.global_position.y, v.global_basis.y.y])
	await shot("fly_heli")
	G.player.test_input = null
	G.player.exit_vehicle()
	G.player.set_parachute(true)
	await wait(1.0)
	G.player._start_chute()
	await wait(1.5)
	await shot("parachute")
	print("[test] chute state=", G.player.state, " vy=", G.player.velocity.y)
	v.queue_free()
	await wait(8.0)
	print("[test] after chute state=", G.player.state, " y=", G.player.global_position.y, " hp=", G.player.health)
	for id in ["plane", "jet"]:
		var pl: Vehicle = await _drive(id, Vector3(240, 0.4, 150), 0.0)
		G.player.test_lift = 1.0
		await wait(5.0)
		print("[test] %s ground speed=%.1f thr=%.2f z=%.1f" % [id, pl.fspeed, pl.plane_throttle, pl.global_position.z])
		G.player.test_input = Vector2(0, -0.6)
		await wait(5.0)
		print("[test] %s alt=%.1f speed=%.1f z=%.1f grounded=%d" % [id, pl.global_position.y, pl.fspeed, pl.global_position.z, pl.grounded])
		if id == "plane":
			await shot("fly_plane")
		G.player.test_input = null
		G.player.test_lift = 0.0
		G.player.force_exit()
		pl.queue_free()
		G.player.warp(Vector3(240, 0.4, 180))
		await wait(0.5)


func t_boat() -> void:
	var v: Vehicle = await _drive("speedboat", Vector3(-87, 0, 250), PI)
	await wait(2.0)
	print("[test] boat rest y=%.2f in_water=%s" % [v.global_position.y, v.in_water])
	G.player.test_input = Vector2(0, 1)
	await wait(6.0)
	print("[test] boat speed=%.1f y=%.2f pos=%s" % [v.fspeed, v.global_position.y, v.global_position])
	await shot("boat")
	G.player.test_input = null
	G.player.exit_vehicle()
	await wait(2.5)
	print("[test] swim state=", G.player.state, " y=", G.player.global_position.y)
	await shot("swim")
	v.queue_free()
	view(Vector3(-150, -6, 258), 0.0, -0.1)
	await wait(2.0)
	print("[test] dive state=", G.player.state, " breath=", G.player.breath)
	await shot("dive_wreck")
	view(Vector3(-60, 0.5, 186), 0.0)
	await wait(1.0)


func t_combat() -> void:
	var p = G.player
	view(Vector3(210, 0.3, 20), 0.0, 0.0)
	G.pop.enabled = false
	await wait(1.0)
	for w in Defs.WEAPON_ORDER:
		p.give_weapon(w, 999)
	var dummy: NPC = G.pop.spawn("civ", p.global_position + Vector3(0, 0.2, -12))
	dummy.ai = "idle"
	dummy.set_meta("fixed", true)
	await wait(0.6)
	for w in ["pistol", "smg", "shotgun", "rifle", "sniper"]:
		p.equip(w)
		await wait(0.2)
		var hp0 := dummy.health
		var o: Vector3 = p.global_position + Vector3.UP * 1.4
		var d: Vector3 = (dummy.global_position + Vector3.UP * 1.0 - o).normalized()
		var ok: bool = p.fire(o, d, 0.0)
		await wait(0.3)
		print("[test] fire %s ok=%s dummy hp %.0f -> %.0f dead=%s wanted=%d" % [w, ok, hp0, dummy.health, dummy.dead, G.wanted.stars])
		if dummy.dead:
			dummy = G.pop.spawn("civ", p.global_position + Vector3(0, 0.2, -12))
			dummy.ai = "idle"
			dummy.set_meta("fixed", true)
			await wait(0.4)
	p.equip("rifle")
	p.aiming = true
	await shot("combat_aim")
	p.equip("rocket")
	var car: Vehicle = G.traffic.spawn_vehicle("compact", p.global_position + Vector3(0, 0.3, -40), 0.0)
	await wait(1.0)
	var o2: Vector3 = p.global_position + Vector3.UP * 1.5
	p.fire(o2, (car.global_position + Vector3.UP * 0.6 - o2).normalized(), 0.0)
	await wait(1.2)
	await shot("combat_explosion")
	print("[test] rocket: car wrecked=%s health=%.0f" % [car.wrecked, car.health])
	p.equip("grenade")
	p.fire(o2, Vector3(0.3, 0.3, -1).normalized(), 0.0)
	await wait(3.2)
	p.equip("bat")
	var d2: NPC = G.pop.spawn("gang", p.global_position + Vector3(0, 0.2, -1.4))
	d2.set_meta("fixed", true)
	await wait(0.3)
	p.rotation.y = 0.0
	p.melee_attack(true)
	await wait(0.5)
	print("[test] melee: target hp=%.0f state=%s" % [d2.health, d2.state])
	G.wanted.clear()
	G.pop.enabled = true


func t_police() -> void:
	var p = G.player
	view(Vector3(-40, 0.3, -34), 0.0, -0.1)
	await wait(1.0)
	G.wanted.set_stars(3)
	for k in 6:
		await wait(4.0)
		var cops := 0
		for h in G.humanoids:
			if h is NPC and h.role in ["cop", "swat"] and not h.dead and h.state != "vehicle":
				cops += 1
		print("[test] wanted t=%ds stars=%d state=%s seen=%s units=%d foot_cops=%d heli=%s" % [(k + 1) * 4, G.wanted.stars, G.wanted.state, G.wanted.seen, G.wanted.units.size(), cops, G.wanted.heli != null])
	await shot("police")
	# hide: teleport far away and wait for the search to expire
	view(Vector3(-139, 0.45, -1.5), 0.0)
	G.player.crouching = true
	for k in 12:
		await wait(4.0)
		print("[test] escape t=%ds stars=%d state=%s unseen=%.0f" % [(k + 1) * 4, G.wanted.stars, G.wanted.state, G.wanted.unseen_t])
		if G.wanted.stars == 0:
			break
	G.player.crouching = false
	G.wanted.clear()


func t_ui() -> void:
	view(Vector3(-14, 0.3, 33), PI, -0.1)
	await wait(0.8)
	G.menus.open("gunshop")
	await wait(0.4)
	await shot("ui_gunshop")
	G.menus.close()
	G.menus.open("admin")
	await wait(0.3)
	await shot("ui_admin")
	G.menus.close()
	G.hud.map_open = true
	await wait(0.3)
	await shot("ui_map")
	G.hud.map_open = false
	G.player.wheel_open = true
	G.hud.wheel_slot = 4
	await wait(0.3)
	await shot("ui_wheel")
	G.hud._close_wheel(true)
	G.save.save_game()
	var ok: bool = G.save.load_game()
	print("[test] save/load ok=", ok)
	G.save.delete_save()


func t_perf() -> void:
	# short capped stress sample: busy downtown with a wanted level
	view(Vector3(0, 0.3, -40), 0.6, -0.1)
	G.traffic.density = 18
	G.wanted.set_stars(4)
	var acc := 0.0
	var n := 0
	var worst := 999.0
	for k in 40:
		await wait(0.5)
		var f := Engine.get_frames_per_second()
		acc += f
		n += 1
		worst = min(worst, f)
	print("[test] perf (capped 30fps) avg=%.1f min=%.1f npcs=%d vehicles=%d frame_ms=%.2f" % [acc / n, worst, G.humanoids.size(), G.vehicles.size(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	print("[test] perf draw_calls=%d objects=%d phys_ms=%.2f" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	await shot("perf")
	G.wanted.clear()
	G.traffic.density = 13


func t_traffic() -> void:
	view(Vector3(-32, 0.3, -32), 0.8, -0.1)
	G.sky.time = 12.0
	for k in 3:
		await wait(10.0)
		var n := 0
		var moving := 0
		var stuck := 0
		var sp := 0.0
		for v in G.traffic.cars:
			if is_instance_valid(v) and v.ai != null:
				n += 1
				sp += abs(v.fspeed)
				if abs(v.fspeed) > 1.0: moving += 1
				if v.ai.stuck_t > 2.0: stuck += 1
		var st := {}
		var walk := 0
		for h in G.pop.npcs:
			if is_instance_valid(h) and not h.dead:
				st[h.ai] = st.get(h.ai, 0) + 1
				if h.velocity.length() > 0.5: walk += 1
		print("[test] traffic t=%d cars=%d moving=%d stuck=%d avg_speed=%.1f peds=%s walking=%d fps=%d" % [(k + 1) * 10, n, moving, stuck, sp / max(n, 1), st, walk, Engine.get_frames_per_second()])
	await shot("traffic")
	view(Vector3(-200, 6.0, 4), -PI / 2, -0.35)
	await wait(6.0)
	await shot("traffic_arterial")


func t_misc() -> void:
	var p = G.player
	G.sky.time = 12.0
	# --- carjack an AI driven car
	view(Vector3(-32, 0.3, -32), 0.8, -0.1)
	await wait(3.0)
	var tv = null
	for v in G.traffic.cars:
		if is_instance_valid(v) and v.ai != null and v.kind == "car" and v.owner_tag == "civ":
			tv = v
			break
	if tv != null:
		p.global_position = tv.door_pos() + Vector3(-1.0, 0.3, 0)
		await wait(0.1)
		p.try_enter_vehicle()
		await wait(1.2)
		print("[test] carjack: state=%s in=%s stars=%d pending=%d" % [p.state, p.vehicle == tv, G.wanted.stars, G.wanted.pending.size()])
		await wait(4.5)
		print("[test] carjack after report window: stars=%d" % G.wanted.stars)
		p.exit_vehicle()
		G.wanted.clear()
	# --- mod garage
	var mv: Vehicle = await _drive("sedan", Vector3(-14, 0.4, -133), PI)
	await wait(1.0)
	G.money = 100000
	p._scan_prompts()
	print("[test] modshop prompt: '", p.prompt, "'")
	mv.mods.engine = 3
	mv.mods.turbo = 1
	mv.mods.parts = ["spoiler", "skirts", "bumper", "hood", "exhaust", "roof"]
	mv.mods.finish = 2
	mv.paint = Color(0.9, 0.4, 0.05)
	mv.health = 300.0
	mv.apply_mods()
	G.menus.open("modshop")
	await wait(0.4)
	await shot("ui_modshop")
	G.menus.close()
	mv.repair()
	G.cam.yaw = 2.2
	G.cam.pitch = -0.25
	await wait(0.6)
	await shot("modded_car")
	print("[test] mods: accel_mult=%.2f top_mult=%.2f spoiler_visible=%s health=%.0f" % [mv.accel_mult, mv.top_mult, G.part(mv.model, "mod_spoiler").visible, mv.health])
	# --- garage store / retrieve
	p.exit_vehicle()
	mv.global_position = G.locations["Garage Spot"] + Vector3(0, 0.3, 0)
	mv.linear_velocity = Vector3.ZERO
	await wait(0.5)
	G.menus.garage.append(mv.serialize())
	mv.queue_free()
	await wait(0.3)
	var rv := Vehicle.deserialize(G.menus.garage[0])
	G.main.add_child(rv)
	rv.global_position = G.locations["Garage Spot"] + Vector3(0, 0.4, 0)
	print("[test] garage roundtrip: id=%s engine=%d parts=%d paint=%s" % [rv.id, rv.mods.engine, rv.mods.parts.size(), rv.paint])
	G.menus.garage.clear()
	rv.queue_free()
	# --- cover / vault / ladder
	view(Vector3(-126.5, 0.3, 20), 0.0)
	await wait(0.6)
	p.global_position = Vector3(-128.0, 0.3, 17.0)
	await wait(0.4)
	p.try_cover()
	await wait(0.5)
	print("[test] cover: state=%s low=%s normal=%s" % [p.state, p.cover_low, p.cover_n])
	await shot("cover")
	p.state = "normal"
	p.crouching = false
	var lad: Dictionary = G.world.ladders[0]
	p.global_position = lad.pos + Vector3(0.3, 0.2, 0)
	await wait(0.3)
	p._scan_prompts()
	print("[test] ladder prompt: '", p.prompt, "'")
	if p.prompt_action.is_valid():
		p.prompt_action.call()
	await wait(0.3)
	print("[test] ladder state=", p.state)
	p.state = "normal"
	# --- danger reaction
	view(Vector3(-32, 0.3, -32), 0.8, -0.1)
	await wait(4.0)
	G.emit_danger(p.global_position, 75.0, p, "gunshot")
	await wait(1.0)
	var st := {}
	for h in G.pop.npcs:
		if is_instance_valid(h) and not h.dead and h.role == "civ":
			st[h.ai] = st.get(h.ai, 0) + 1
	print("[test] civ reactions after gunshot: ", st)
	await shot("panic")
	# --- taxi
	G.traffic.call_taxi()
	for k in 25:
		await wait(2.0)
		if G.traffic.taxi_state == "waiting":
			break
		if k % 5 == 4 and G.traffic.taxi:
			var tx = G.traffic.taxi
			print("[test] taxi coming: mode=%s speed=%.1f dist=%.0f route=%s stuck=%.1f" % [tx.ai.mode, tx.fspeed, tx.global_position.distance_to(p.global_position), tx.ai.route, tx.ai.stuck_t])
	print("[test] taxi state=%s dist=%.0f" % [G.traffic.taxi_state, G.traffic.taxi.global_position.distance_to(p.global_position) if G.traffic.taxi else -1.0])
	if G.traffic.taxi_state == "waiting":
		p._ride_taxi(G.traffic.taxi)
		G.menus.panel.visible = false
		G.traffic.taxi_go(G.locations["Hospital"])
		await wait(6.0)
		print("[test] taxi riding: state=%s speed=%.1f" % [G.traffic.taxi_state, G.traffic.taxi.fspeed if G.traffic.taxi else 0.0])
		G.traffic.taxi_skip()
		await wait(5.0)
		print("[test] taxi after skip: state=%s player_state=%s dist_to_dest=%.0f" % [G.traffic.taxi_state, p.state, p.global_position.distance_to(G.locations["Hospital"])])
	# --- range
	p.warp(G.locations["Shooting Range"])
	p.give_weapon("rifle", 500)
	p.equip("rifle")
	await wait(0.5)
	G.activities.start_range()
	await wait(0.5)
	var hits := 0
	for k in 6:
		if G.activities.targets.is_empty():
			break
		var t: Prop = G.activities.targets[0]
		var o: Vector3 = p.global_position + Vector3.UP * 1.5
		p.fire_cd = 0.0
		p.fire(o, (t.global_position + Vector3.UP * 1.5 - o).normalized(), 0.0)
		await wait(0.3)
	print("[test] range: on=%s score=%d hits=%d" % [G.activities.range_on, G.activities.range_score, G.activities.range_hits])
	await shot("range")
	G.activities.range_t = 0.1
	await wait(0.5)
	# --- emergency + wildlife
	G.traffic._dispatch("ambulance", Vector3(-40, 0, -34))
	await wait(1.0)
	print("[test] responders=%d animals=%d" % [G.traffic.responders.size(), G.pop.animals.size()])
	view(Vector3(-60, 24.5, -256), 1.2, -0.2)
	await wait(2.0)
	await shot("wildlife")


func t_death() -> void:
	var p = G.player
	view(Vector3(-40, 0.3, -34), 0.0, -0.1)
	await wait(1.0)
	G.invulnerable = false
	G.wanted.set_stars(2)
	var c: NPC = G.pop.spawn("cop", p.global_position + Vector3(6, 0.2, -8))
	c.engage(p)
	var h0: float = p.health
	for k in 10:
		await wait(1.5)
		print("[test] under fire t=%.1f hp=%.0f cop_ai=%s state=%s seen=%s lethal=%s clip=%s reload=%.1f aiming=%s dist=%.1f crouch=%s copstate=%s" % [(k + 1) * 1.5, p.health, c.ai, p.state, G.wanted.seen, G.wanted.lethal, c.clip, c.reload_t, c.aiming, c.global_position.distance_to(p.global_position), c.crouching, c.state])
		if p.dead:
			break
	if not p.dead:
		p.take_damage(500.0, null, p.global_position, Vector3.UP, "fall")
	await shot("wasted")
	await wait(5.5)
	print("[test] respawn: dead=%s hp=%.0f pos=%s stars=%d" % [p.dead, p.health, p.global_position, G.wanted.stars])
	G.wanted.set_stars(1)
	await wait(0.3)
	p.get_busted()
	await wait(1.0)
	await shot("busted")
	await wait(3.5)
	print("[test] busted respawn: busted=%s pos=%s stars=%d money=%d" % [p.busted, p.global_position, G.wanted.stars, G.money])
	G.invulnerable = true


func key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func mouse(b: int, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	e.position = Vector2(640, 360)
	Input.parse_input_event(e)


func t_input() -> void:
	var p = G.player
	G.pop.enabled = false
	G.traffic.enabled = false
	view(Vector3(210, 0.3, 40), 0.0, -0.1)
	await wait(1.0)
	print("[test] mouse captured=", Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	var p0: Vector3 = p.global_position
	key(KEY_W, true)
	await wait(2.0)
	key(KEY_SHIFT, true)
	await wait(1.5)
	key(KEY_SHIFT, false)
	key(KEY_W, false)
	print("[test] walked %.1f m (W + sprint), stamina=%.0f" % [p0.distance_to(p.global_position), p.stamina])
	key(KEY_SPACE, true)
	await wait(0.25)
	key(KEY_SPACE, false)
	print("[test] jump: y=%.2f on_floor=%s" % [p.global_position.y, p.is_on_floor()])
	await wait(1.0)
	key(KEY_C, true)
	key(KEY_C, false)
	await wait(0.3)
	print("[test] crouch=", p.crouching)
	key(KEY_C, true)
	key(KEY_C, false)
	p.give_weapon("smg", 300)
	key(KEY_3, true)
	key(KEY_3, false)
	await wait(0.3)
	print("[test] slot key 3 -> weapon=", p.weapon)
	var c0: int = p.clip.get("smg", 0)
	mouse(MOUSE_BUTTON_RIGHT, true)
	await wait(0.4)
	mouse(MOUSE_BUTTON_LEFT, true)
	await wait(0.8)
	await shot("input_fire")
	mouse(MOUSE_BUTTON_LEFT, false)
	mouse(MOUSE_BUTTON_RIGHT, false)
	print("[test] on-foot fire: smg clip %d -> %d aiming_was=%s" % [c0, p.clip.get("smg", 0), p.face_cam_t > 0.0])
	key(KEY_R, true)
	key(KEY_R, false)
	await wait(0.2)
	print("[test] reload_t=%.2f" % p.reload_t)
	await wait(2.0)
	# enter a car with F, drive with W, drive-by with LMB, exit with F
	var v: Vehicle = G.traffic.spawn_vehicle("sedan", p.global_position + Vector3(3.0, 0.3, 0), 0.0)
	await wait(1.0)
	key(KEY_F, true)
	key(KEY_F, false)
	await wait(1.2)
	print("[test] F enter: state=%s weapon=%s" % [p.state, p.weapon])
	key(KEY_W, true)
	await wait(3.0)
	var c1: int = p.clip.get(p.weapon, 0)
	mouse(MOUSE_BUTTON_LEFT, true)
	await wait(0.7)
	mouse(MOUSE_BUTTON_LEFT, false)
	print("[test] driving speed=%.1f, drive-by clip %d -> %d" % [v.fspeed, c1, p.clip.get(p.weapon, 0)])
	await shot("input_driveby")
	key(KEY_W, false)
	key(KEY_SPACE, true)
	await wait(2.5)
	key(KEY_SPACE, false)
	key(KEY_H, true)
	key(KEY_H, false)
	key(KEY_F, true)
	key(KEY_F, false)
	await wait(0.6)
	print("[test] F exit: state=%s speed_was=%.1f" % [p.state, v.fspeed])
	# weapon wheel + phone + map + pause
	key(KEY_TAB, true)
	await wait(0.3)
	print("[test] wheel open=%s time_scale=%.2f" % [p.wheel_open, Engine.time_scale])
	key(KEY_TAB, false)
	await wait(0.2)
	key(KEY_P, true)
	key(KEY_P, false)
	await wait(0.3)
	print("[test] phone menu=%s blocking=%s" % [G.menus.current, G.menus.blocking()])
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	await wait(0.3)
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	await wait(0.3)
	print("[test] pause menu=%s paused=%s" % [G.menus.current, get_tree().paused])
	await shot("ui_pause")
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	await wait(0.3)
	print("[test] resumed paused=%s mouse_captured=%s" % [get_tree().paused, Input.mouse_mode == Input.MOUSE_MODE_CAPTURED])
	v.queue_free()
	G.pop.enabled = true
	G.traffic.enabled = true


func t_stunt() -> void:
	var p = G.player
	G.traffic.enabled = false
	var v: Vehicle = await _drive("sports", Vector3(205, 0.3, 170), 0.0)
	p.test_input = Vector2(0, 1)
	for k in 14:
		await wait(0.5)
		if k == 7:
			await shot("stunt")
	print("[test] stunt: best=%.1f m car_z=%.1f health=%.0f up=%.2f" % [G.activities.best_stunt, v.global_position.z, v.health, v.global_basis.y.y])
	p.test_input = null
	# roadblock while driving on the arterial with 3 stars
	G.wanted.set_stars(3)
	v.global_transform = Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-190, 0.4, 122.4))
	v.linear_velocity = Vector3(20, 0, 0)
	v.angular_velocity = Vector3.ZERO
	v.repair()
	p.test_input = Vector2(0, 1)
	await wait(1.0)
	G.wanted._roadblock()
	print("[test] roadblock: blocks=%d units=%d" % [G.wanted.blocks.size(), G.wanted.units.size()])
	if G.wanted.blocks.size() > 0:
		print("[test] roadblock at ", G.wanted.blocks[0].pos, " player at ", p.global_position)
	await wait(3.5)
	await shot("roadblock")
	await wait(3.0)
	print("[test] after roadblock: speed=%.1f health=%.0f x=%.0f" % [v.fspeed, v.health, v.global_position.x])
	p.test_input = null
	G.wanted.clear()
	p.exit_vehicle()
	G.traffic.enabled = true
