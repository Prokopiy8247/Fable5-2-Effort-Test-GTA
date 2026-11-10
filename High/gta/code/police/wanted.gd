extends Node
## 0-5 star wanted system: crimes, witnesses, pursuit/search states, police dispatch (foot, cars, tactical, air,
## roadblocks), arrests (autoload "Wanted").

signal level_changed(level: int)

const THRESH := [0.0, 1.0, 30.0, 75.0, 140.0, 215.0]
const ESCAPE := [0.0, 16.0, 24.0, 34.0, 46.0, 60.0]
const CRIMES := {
	"gunfire": {"heat": 9.0, "min": 1, "hear": 45.0},
	"gunfire_suppressed": {"heat": 5.0, "min": 1, "hear": 0.0, "sight": 14.0},
	"brandish": {"heat": 6.0, "min": 1},
	"assault": {"heat": 12.0, "min": 1},
	"hit_ped": {"heat": 14.0, "min": 1},
	"shoot_ped": {"heat": 24.0, "min": 2},
	"kill_ped": {"heat": 34.0, "min": 2},
	"kill_gang": {"heat": 14.0, "min": 1},
	"kill_silent": {"heat": 30.0, "min": 2, "sight": 14.0},
	"carjack": {"heat": 16.0, "min": 1},
	"carjack_police": {"heat": 60.0, "min": 3, "always": true},
	"attack_cop": {"heat": 40.0, "min": 2, "always": true},
	"kill_cop": {"heat": 70.0, "min": 3, "always": true},
	"explosion": {"heat": 40.0, "min": 3, "always": true},
	"destroy_vehicle": {"heat": 15.0, "min": 2},
	"destroy_police_vehicle": {"heat": 55.0, "min": 3, "always": true},
	"robbery": {"heat": 40.0, "min": 2, "always": true},
	"collision": {"heat": 6.0, "min": 1, "cop_only": true},
	"trespass": {"heat": 3.0, "min": 1, "cop_only": true},
}

var level := 0
var heat := 0.0
var state := "none"          # none | pursuit | search
var seen := false
var last_known := Vector3.ZERO
var unseen := 0.0
var disguised := false
var known_vehicle = null
var locked := false           # debug: freeze level
var cops: Array = []          # foot officers we spawned
var cars: Array = []          # police vehicles with AI
var helis: Array = []
var blocks: Array = []        # {nodes:[], pos, t}
var _scan_t := 0.0
var _dispatch_t := 0.0
var _busted_t := 0.0
var _block_t := 10.0
var _witness_cd: Dictionary = {}
var _evade_t := 0.0
var _pending_reports := 0
var enabled := true


func clear(silent: bool = false) -> void:
	var had := level > 0
	level = 0
	heat = 0.0
	state = "none"
	seen = false
	unseen = 0.0
	disguised = false
	_busted_t = 0.0
	level_changed.emit(0)
	if had and not silent:
		Sfx.play("wanted_clear", -4.0)
		Game.say("You lost the police", Color(0.6, 1.0, 0.6))
	for v in cars:
		if is_instance_valid(v):
			v.set_siren(false)
			if v.ai != null:
				var l := City.nearest_lane(v.global_position, -v.global_basis.z)
				if not l.is_empty():
					v.ai.mode = "traffic"
					v.ai.start_lane(l.seg, l.dir, l.lane, v.global_position)
	for c in cops:
		if is_instance_valid(c) and not c.dead:
			c.target = null
			c._set_state(Npc.S.WANDER)
			c.rig.set_weapon(null)


func set_level(n: int) -> void:
	n = clampi(n, 0, 5)
	if n == 0:
		clear()
		return
	heat = maxf(THRESH[n] + 0.5, 1.0)
	_apply_heat(true)
	level = n
	heat = THRESH[n] + 0.5
	level_changed.emit(level)
	if Game.player:
		last_known = Game.player.global_position
	state = "search" if not seen else "pursuit"
	unseen = 0.0


func _apply_heat(force: bool = false) -> void:
	var nl := 0
	for i in range(1, 6):
		if heat >= THRESH[i]:
			nl = i
	if nl > level or force:
		if nl > level:
			Sfx.play("wanted_up", -3.0)
		level = maxi(level, nl)
		level_changed.emit(level)
		if state == "none":
			state = "search"
			unseen = 0.0


func add_heat(h: float, min_level: int = 0) -> void:
	if locked or not enabled:
		return
	heat += h
	if min_level > 0:
		heat = maxf(heat, THRESH[min_level] + 0.5)
	heat = minf(heat, THRESH[5] + 40.0)
	_apply_heat()


func arrest_mode() -> bool:
	var p = Game.player
	return level >= 1 and level <= 2 and p != null and not lethal()


func lethal() -> bool:
	var p = Game.player
	if p == null:
		return false
	var now := Time.get_ticks_msec() * 0.001
	if level >= 3:
		return true
	if now - p.last_violence_time < 9.0:
		return true
	return level == 2 and p.is_armed() and p.aiming


# ------------------------------------------------------------------ crimes and witnesses
func _cop_sees(pos: Vector3) -> bool:
	if seen:
		return true
	for n in Game.npcs:
		if is_instance_valid(n) and n.is_law() and not n.dead and n.down_time <= 0.0 and n.global_position.distance_to(pos) < 55.0:
			if n.can_see_player(55.0):
				return true
	return false


func crime(type: String, pos: Vector3) -> void:
	if not enabled or locked or not CRIMES.has(type):
		return
	var c: Dictionary = CRIMES[type]
	var p = Game.player
	if p == null:
		return
	if c.get("always", false) or _cop_sees(pos):
		add_heat(c.heat, c.min)
		last_known = p.global_position
		if state != "pursuit" and _cop_sees(pos):
			state = "pursuit"
		return
	if c.get("cop_only", false):
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_witness_cd.get(type, -100.0)) < 2.5:
		return
	# civilians who directly see the crime start calling it in
	var sight: float = c.get("sight", 30.0)
	var callers := 0
	for n in Game.npcs:
		if callers >= 2:
			break
		if not is_instance_valid(n) or n.dead or n.kind != "civ" or n.down_time > 0.0 or n.state == Npc.S.CALL:
			continue
		var d: float = n.global_position.distance_to(pos)
		if d < sight and d > 1.5 and Game.los(n.eye(), pos + Vector3.UP * 1.2, [n, p]):
			if Game.rng.randf() < 0.55:
				n.start_witness(type)
				callers += 1
	if callers > 0:
		_witness_cd[type] = now
		return
	# unseen gunshots / blasts can still be reported by anyone in earshot
	var hear: float = c.get("hear", 0.0)
	if hear > 0.0:
		for n in Game.npcs:
			if is_instance_valid(n) and not n.dead and n.kind == "civ" and n.global_position.distance_to(pos) < hear:
				_witness_cd[type] = now
				_pending_reports += 1
				var at := pos
				get_tree().create_timer(6.0).timeout.connect(func(): _indirect_report(at))
				break


func _indirect_report(pos: Vector3) -> void:
	_pending_reports = maxi(0, _pending_reports - 1)
	if level >= 1 or not enabled or locked:
		return
	heat = maxf(heat, THRESH[1] + 0.5)
	_apply_heat()
	last_known = pos
	state = "search"
	unseen = 0.0
	Game.say("Shots reported to police", Color(1.0, 0.75, 0.4))


func witness_report(type: String, pos: Vector3) -> void:
	if not CRIMES.has(type) or not enabled or locked:
		return
	var c: Dictionary = CRIMES[type]
	var was := level
	add_heat(c.heat * 0.9, c.min)
	if was == 0:
		last_known = pos
		state = "search"
		unseen = 0.0
		Game.say("A witness called the police", Color(1.0, 0.75, 0.4))


func on_player_vehicle_changed(v) -> void:
	if level > 0 and not seen and v != known_vehicle:
		disguised = true
		Game.say("Vehicle switched out of sight - harder to identify", Color(0.6, 0.8, 1.0))
	if seen:
		known_vehicle = v


func on_appearance_changed() -> void:
	if level > 0 and not seen:
		disguised = true
		Game.say("New look - police will have trouble recognising you", Color(0.6, 0.8, 1.0))


func search_radius() -> float:
	return clampf(22.0 + unseen * 2.2, 22.0, 95.0)


func search_point() -> Vector3:
	var r := search_radius()
	var a := Game.rng.randf() * TAU
	return last_known + Vector3(cos(a), 0, sin(a)) * Game.rng.randf_range(4.0, r)


func escape_progress() -> float:
	if level == 0 or state != "search":
		return 0.0
	return clampf(unseen / ESCAPE[level], 0.0, 1.0)


# ------------------------------------------------------------------ update
func _physics_process(delta: float) -> void:
	var p = Game.player
	if p == null or Game.world == null:
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_cleanup()
		if level > 0:
			_update_seen(p, 0.25)
			_check_busted(p, 0.25)
	if level == 0:
		return
	_dispatch_t -= delta
	if _dispatch_t <= 0.0:
		_dispatch_t = 3.0
		_dispatch(p)
	_block_t -= delta
	if level >= 3 and _block_t <= 0.0:
		_block_t = 22.0 - level * 2.0
		_try_roadblock(p)
	_units(p, delta)
	# resisting arrest: fleeing in plain sight slowly raises the heat
	if seen and p.velocity_now().length() > 6.0 and not locked:
		_evade_t += delta
		if _evade_t > 1.0:
			_evade_t = 0.0
			add_heat(1.1)


func _cleanup() -> void:
	cops = cops.filter(func(c): return is_instance_valid(c) and not c.dead)
	cars = cars.filter(func(v): return is_instance_valid(v) and not v.dead)
	helis = helis.filter(func(h): return is_instance_valid(h) and not h.dead)
	var p = Game.player
	if level == 0 and p != null:
		for c in cops:
			if c.global_position.distance_to(p.global_position) > 90.0 and not c.persistent:
				c.queue_free()
		for v in cars:
			if v.global_position.distance_to(p.global_position) > 150.0 and v.driver == null:
				v.queue_free()
		for h in helis:
			if h.ai is HeliAI:
				h.ai.leave = true
	var i := 0
	while i < blocks.size():
		var b: Dictionary = blocks[i]
		if p != null and (b.pos as Vector3).distance_to(p.global_position) > 190.0 or level == 0 and p != null and (b.pos as Vector3).distance_to(p.global_position) > 90.0:
			for n in b.nodes:
				if is_instance_valid(n) and not (n is Vehicle and n.driver != null):
					n.queue_free()
			blocks.remove_at(i)
			continue
		i += 1


func _update_seen(p, dt: float) -> void:
	var mult := 0.5 if disguised else 1.0
	var s := false
	var ppos: Vector3 = p.global_position
	for n in Game.npcs:
		if not is_instance_valid(n) or not n.is_law() or n.dead or n.down_time > 0.0:
			continue
		if n.global_position.distance_to(ppos) < 75.0 * mult and n.can_see_player(70.0 * mult):
			s = true
			break
	if not s:
		var ex: Array = [p]
		if p.in_vehicle():
			ex.append(p.vehicle)
		for v in cars:
			var d: float = v.global_position.distance_to(ppos)
			if d < 65.0 * mult * p.visibility() and v.has_occupant():
				if Game.ray(v.global_position + Vector3.UP * 1.5, p.center(), Game.L_WORLD, ex + [v]).is_empty():
					s = true
					break
		if not s:
			for h in helis:
				var dh: float = h.global_position.distance_to(ppos)
				if dh < 170.0 * (0.7 if disguised else 1.0) and Game.ray(h.global_position + Vector3.DOWN * 2.0, p.center(), Game.L_WORLD, ex + [h]).is_empty():
					s = true
					break
	seen = s
	if s:
		if state != "pursuit":
			state = "pursuit"
		unseen = 0.0
		last_known = ppos
		if disguised:
			disguised = false
		known_vehicle = p.vehicle if p.in_vehicle() else null
	else:
		unseen += dt
		if unseen > 1.5 and state == "pursuit":
			state = "search"
		if unseen >= ESCAPE[level] and not locked:
			clear()


func _check_busted(p, dt: float) -> void:
	if not p.alive() or level == 0:
		_busted_t = 0.0
		return
	var slow: bool = p.velocity_now().length() < 1.6
	var down: bool = p.state == Player.St.RAGDOLL
	if (lethal() and not down) or level > 3 or not (slow or down):
		_busted_t = maxf(0.0, _busted_t - dt)
		return
	var near := false
	for n in Game.npcs:
		if is_instance_valid(n) and n.is_law() and not n.dead and n.down_time <= 0.0 and n.global_position.distance_to(p.global_position) < 2.9:
			near = true
			break
	if near:
		_busted_t += dt
		if _busted_t > (0.9 if down else 1.8):
			_busted_t = 0.0
			p.busted()
	else:
		_busted_t = maxf(0.0, _busted_t - dt)


# ------------------------------------------------------------------ dispatch
func _want_units() -> Dictionary:
	match level:
		1:
			return {"cars": 1, "swat": 0, "heli": 0}
		2:
			return {"cars": 2, "swat": 0, "heli": 0}
		3:
			return {"cars": 3, "swat": 0, "heli": 1}
		4:
			return {"cars": 3, "swat": 1, "heli": 1}
		5:
			return {"cars": 4, "swat": 2, "heli": 2}
	return {"cars": 0, "swat": 0, "heli": 0}


func _dispatch(p) -> void:
	var want := _want_units()
	var ncars := 0
	var nswat := 0
	for v in cars:
		if v.def.id == "swat":
			nswat += 1
		else:
			ncars += 1
	var active_cops := 0
	for c in cops:
		if c.global_position.distance_to(p.global_position) < 120.0:
			active_cops += 1
	if ncars < want.cars and active_cops < 4 + level * 2:
		spawn_police_car(p, "police")
	elif nswat < want.swat:
		spawn_police_car(p, "swat")
	if helis.size() < want.heli:
		spawn_heli(p)
	# make sure nearby patrol officers respond
	for n in Game.npcs:
		if is_instance_valid(n) and n.is_law() and not n.dead and n.state in [Npc.S.IDLE, Npc.S.WANDER] and n.global_position.distance_to(last_known) < 140.0:
			n.investigate(last_known)
			if not cops.has(n):
				cops.append(n)


func _spawn_lane_point(p, dmin: float, dmax: float) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	var ppos: Vector3 = p.global_position
	for attempt in range(14):
		var s: Dictionary = City.segs[Game.rng.randi() % City.segs.size()]
		var dir := Game.rng.randi() % 2
		var lp := City.lane_points(s.id, dir, 0)
		var pos: Vector3 = (lp[0] as Vector3).lerp(lp[1], Game.rng.randf_range(0.1, 0.8))
		var d := pos.distance_to(ppos)
		if d < dmin or d > dmax:
			continue
		if cam and cam.is_position_in_frustum(pos + Vector3.UP) and Game.los(cam.global_position, pos + Vector3.UP * 1.5):
			continue
		var clear := true
		for o in Game.vehicles:
			if is_instance_valid(o) and o.global_position.distance_to(pos) < 10.0:
				clear = false
				break
		if clear:
			return {"pos": pos, "dir": City.seg_dir(s.id, dir), "seg": s.id, "d": dir}
	return {}


func spawn_police_car(p, id: String = "police") -> Vehicle:
	var sp := _spawn_lane_point(p, 85.0, 150.0)
	if sp.is_empty() or Game.traffic == null:
		return null
	var fwd: Vector3 = sp.dir
	var v: Vehicle = Game.traffic.spawn_vehicle(id, sp.pos + Vector3.UP * 0.4, atan2(-fwd.x, -fwd.z))
	var swat := id == "swat"
	v.set_ai_driver(Data.look_cop(Game.rng, swat))
	v.crew_looks = []
	for i in range(3 if swat else 1):
		v.crew_looks.append(Data.look_cop(Game.rng, swat))
	var ai := DriverAI.new()
	ai.mode = "pursue"
	ai.target = p
	ai.obey_signals = false
	v.ai = ai
	v.set_siren(true)
	v.set_lights(true)
	v.linear_velocity = fwd * 8.0
	cars.append(v)
	return v


func spawn_heli(p) -> void:
	if Game.traffic == null:
		return
	var a := Game.rng.randf() * TAU
	var pos: Vector3 = p.global_position + Vector3(cos(a), 0, sin(a)) * 170.0
	pos.y = 55.0
	var h: Vehicle = Game.traffic.spawn_vehicle("heli_police", pos, 0.0)
	h.set_ai_driver(Data.look_cop(Game.rng))
	h.rotor_speed = 1.0
	var ai := HeliAI.new()
	ai.target = p
	h.ai = ai
	h.set_meta("heli_ai", ai)
	helis.append(h)


func _units(p, _delta: float) -> void:
	# crews leave their cars when the driver AI says it is time
	for v in cars:
		if not is_instance_valid(v) or v.ai == null or not (v.ai is DriverAI):
			continue
		var ai: DriverAI = v.ai
		if ai.dismount_ready and v.driver_rig != null and v.global_position.distance_to(p.global_position if seen else last_known) < 30.0:
			_dismount(v, p)
		elif v.driver_rig == null and v.driver == null:
			pass
	# officers far from the action get back to work / are recycled
	for c in cops:
		if not is_instance_valid(c):
			continue
		if c.state == Npc.S.IDLE and level > 0:
			c.investigate(last_known)
		var d: float = c.global_position.distance_to(p.global_position)
		if d > 150.0 and not c.persistent:
			c.queue_free()


func _dismount(v: Vehicle, p) -> void:
	var looks: Array = [v.remove_ai_driver()] + v.crew_looks
	v.crew_looks = []
	v.ai = null
	v.throttle_in = 0.0
	v.handbrake_in = true
	var swat: bool = v.def.id == "swat"
	for i in range(looks.size()):
		var pos := v.door_pos(mini(i, v.seats.size() - 1))
		pos.y = maxf(pos.y, v.global_position.y - 0.4)
		var n := Npc.spawn("swat" if swat else "cop", pos + Vector3(Game.rng.randf_range(-0.3, 0.3), 0, Game.rng.randf_range(-0.3, 0.3)), looks[i])
		n.squad_vehicle = v
		cops.append(n)
		if seen:
			n.engage(p)
		else:
			n.investigate(last_known)


func _try_roadblock(p) -> void:
	if not p.in_vehicle() or p.vehicle.is_air() or p.vehicle.def.kind == "boat" or blocks.size() >= 2 or Game.traffic == null:
		return
	var vel: Vector3 = p.vehicle.linear_velocity
	if vel.length() < 7.0:
		return
	var l := City.nearest_lane(p.global_position, vel.normalized())
	if l.is_empty() or l.dist > 14.0:
		return
	# walk ahead through the graph ~120 m
	var seg: int = l.seg
	var dir: int = l.dir
	var remaining := 120.0 - (1.0 - float(l.t)) * float(City.segs[seg].len)
	var guard := 0
	while remaining > 0.0 and guard < 4:
		var opts := City.next_options(seg, dir, 0)
		if opts.is_empty():
			return
		var pick: Dictionary = opts[0]
		for o in opts:
			if o.turn == 0:
				pick = o
		seg = pick.seg
		dir = pick.dir
		remaining -= City.segs[seg].len
		guard += 1
	var s: Dictionary = City.segs[seg]
	var mid: Vector3 = (s.p0 + s.p1) * 0.5
	if mid.distance_to(p.global_position) < 70.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.is_position_in_frustum(mid + Vector3.UP) and Game.los(cam.global_position, mid + Vector3.UP * 2.0) and mid.distance_to(p.global_position) < 90.0:
		return
	var d: Vector3 = s.dir
	var right := Vector3(-d.z, 0, d.x)
	var nodes := []
	var yaw := atan2(-right.x, -right.z)
	var half: float = s.half
	var n_cars := 2 if half < 6.0 else 3
	for i in range(n_cars):
		var off := (float(i) - (n_cars - 1) * 0.5) * 5.2
		var v: Vehicle = Game.traffic.spawn_vehicle("swat" if (level >= 4 and i == 0) else "police", mid + right * off + Vector3.UP * 0.4, yaw + (0.25 if i % 2 == 0 else -0.25))
		v.set_siren(true)
		v.set_lights(true)
		v.handbrake_in = true
		nodes.append(v)
		for k in range(2 if i == 0 else 1):
			var behind: Vector3 = mid + right * (off + Game.rng.randf_range(-1.5, 1.5)) + d * (3.0 if (p.global_position - mid).dot(d) < 0.0 else -3.0)
			var c := Npc.spawn("swat" if level >= 4 else "cop", behind + Vector3.UP * 0.2)
			c.alerted = true
			c.persistent = true
			c._face(p.global_position, 1.0)
			cops.append(c)
			nodes.append(c)
	if level >= 4:
		var strip := _make_spikes(half * 2.0 - 1.0)
		Game.world.add_child(strip)
		var sp: Vector3 = mid + d * (9.0 if (p.global_position - mid).dot(d) > 0.0 else -9.0)
		strip.global_transform = Transform3D(Basis(Vector3.UP, yaw), sp + Vector3.UP * 0.05)
		strip.set_meta("spikes", true)
		nodes.append(strip)
	blocks.append({"nodes": nodes, "pos": mid})
	Game.say("Roadblock ahead!", Color(1.0, 0.6, 0.4))


func _make_spikes(width: float) -> Node3D:
	var n := SpikeStrip.new()
	n.width = width
	return n
