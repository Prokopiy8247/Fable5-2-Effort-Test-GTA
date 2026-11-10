extends Node
## Wanted / pursuit system (0-5 stars). Crimes need witnesses, police have line of sight, a last known
## position and a search area; stars are only lost by staying genuinely unseen. Handles dispatch of
## cruisers, tactical vans, roadblocks, spike strips and helicopter support.

const THRESH := [0.0, 1.0, 3.0, 6.5, 11.0, 17.0]
const ESCAPE := [0.0, 14.0, 22.0, 32.0, 44.0, 58.0]
const WANT_CARS := [0, 1, 2, 3, 4, 5]

var level := 0
var heat := 0.0
var state := "none"
var last_known := Vector3.ZERO
var unseen_t := 0.0
var escape_t := 0.0
var lethal := false
var units: Array = []
var heli: Heli = null
var heli_light: SpotLight3D
var heli_fire := 0.0
var dispatch_t := 2.0
var block_t := 12.0
var roadblocks: Array = []
var spikes: Array = []
var recent := {}
var pending: Array = []
var seen_vehicle: Vehicle = null
var resist_t := 0.0
var last_spot_time := -99.0
var stats_max := 0


func _ready() -> void:
	G.crime.connect(_on_crime)


func stars_flash() -> bool:
	return level > 0 and state == "search"


func escape_progress() -> float:
	if level == 0 or state != "search":
		return 0.0
	return clampf(escape_t / float(ESCAPE[level]), 0.0, 1.0)


func search_radius() -> float:
	return 45.0 + level * 22.0 + unseen_t * 1.2


func random_search_point() -> Vector3:
	var a := randf() * TAU
	var r := randf_range(10.0, minf(search_radius(), 150.0))
	var p := last_known + Vector3(cos(a) * r, 0, sin(a) * r)
	return WorldLayout.inter_pos(WorldLayout.nearest_inter(p)) if randf() < 0.6 else p


# ------------------------------------------------------------------ crime intake
func _on_crime(kind: String, pos: Vector3, severity: float, culprit: Node) -> void:
	# only crimes the player is responsible for count (environmental fires / AI crashes have no culprit)
	if culprit == null or not G.is_player(culprit):
		return
	if G.player == null or G.player.dead:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if recent.has(kind) and now - float(recent[kind]) < (1.2 if not kind.begins_with("murder") else 0.0):
		return
	recent[kind] = now
	# 1) police who directly see it
	var seen_by_police := false
	if G.peds:
		for c in G.peds.police_near(pos, 65.0):
			if c.vehicle != null or c.can_see(pos + Vector3(0, 1.0, 0), 65.0, -0.7):
				seen_by_police = true
				break
	if not seen_by_police:
		for u in get_tree().get_nodes_in_group("vehicles"):
			var v := u as Vehicle
			if v != null and v.is_emergency and v.def.get("emergency", "") == "police" and v.driver != null and not G.is_player(v.driver) and v.global_position.distance_to(pos) < 55.0:
				if G.los(v.global_position + Vector3(0, 1.4, 0), pos + Vector3(0, 1.0, 0), [v.get_rid()]):
					seen_by_police = true
					break
	if seen_by_police or (level > 0 and state == "pursuit"):
		report(kind, pos, severity, true)
		return
	# 2) civilian witnesses phone it in (can be interrupted)
	var ws: Array = G.peds.witnesses(pos, 32.0) if G.peds else []
	if not ws.is_empty() and severity >= 0.6:
		var n := 0
		for w in ws:
			if w.kind == "civ" and w.st in [NPC.S.WANDER, NPC.S.IDLE, NPC.S.FLEE] and n < 2 and randf() < 0.75:
				w.witness({"kind": kind, "pos": pos, "severity": severity * 0.95})
				n += 1
		if n > 0:
			return
	# 3) loud crimes can be reported by people who only heard them
	if kind in ["gunfire", "explosion"] and severity >= 0.8:
		var hearers: Array = []
		if G.peds:
			for npc in G.peds.npcs:
				if is_instance_valid(npc) and not npc.dead and npc.global_position_now().distance_to(pos) < (110.0 if kind == "explosion" else 60.0):
					hearers.append(npc)
		if not hearers.is_empty() and randf() < (0.85 if kind == "explosion" else 0.5):
			pending.append({"t": randf_range(4.0, 8.0), "info": {"kind": kind, "pos": pos, "severity": severity * 0.65}})


func witness_report(info: Dictionary) -> void:
	## A civilian finished their call to the police.
	report(String(info.get("kind", "crime")), info.get("pos", last_known), float(info.get("severity", 1.0)), false)


func report(_kind: String, pos: Vector3, severity: float, direct: bool) -> void:
	var before := level
	heat += severity
	var nl := 0
	for i in range(1, 6):
		if heat >= float(THRESH[i]):
			nl = i
	if nl > level:
		level = nl
		stats_max = maxi(stats_max, level)
		Sfx.play("wanted_up")
		escape_t = 0.0
	if _kind in ["assault_police", "murder_police", "murder", "gunfire", "explosion", "destroy_police"] or level >= 3:
		lethal = true
	if level > 0:
		if before == 0:
			state = "pursuit" if direct else "search"
			unseen_t = 0.0 if direct else 99.0
			last_known = pos
			dispatch_t = 0.5
			G.say("Wanted: the police are %s" % ("on to you" if direct else "investigating a report"), Color(1, 0.5, 0.4))
		if direct:
			spotted(null)
		elif state != "pursuit":
			last_known = pos


func spotted(_by: Node) -> void:
	if level == 0 or G.player == null:
		return
	unseen_t = 0.0
	escape_t = 0.0
	state = "pursuit"
	last_known = G.player.global_position_now()
	seen_vehicle = G.player.vehicle
	last_spot_time = Time.get_ticks_msec() / 1000.0


func set_level(n: int) -> void:
	n = clampi(n, 0, 5)
	if n == 0:
		clear()
		return
	level = n
	heat = float(THRESH[n]) + 0.1
	lethal = n >= 3
	state = "pursuit"
	unseen_t = 0.0
	escape_t = 0.0
	last_known = G.player.global_position_now()
	dispatch_t = 0.2


func clear() -> void:
	level = 0
	heat = 0.0
	state = "none"
	lethal = false
	escape_t = 0.0
	pending.clear()
	for u in units:
		if is_instance_valid(u) and u.ai != null:
			u.ai.mode = "leave" if not u.ai.officers_out else u.ai.mode
			u.set_siren(false)
	for rb in roadblocks:
		for n in rb.nodes:
			if is_instance_valid(n):
				if n is Vehicle:
					n.add_to_group("loose")
				else:
					n.queue_free()
	roadblocks.clear()
	for s in spikes:
		if is_instance_valid(s):
			s.queue_free()
	spikes.clear()
	if heli != null and is_instance_valid(heli):
		heli.set_meta("leaving", true)


# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	var p: Node = G.player
	if p == null:
		return
	var i := pending.size() - 1
	while i >= 0:
		pending[i].t -= delta
		if pending[i].t <= 0.0:
			witness_report(pending[i].info)
			pending.remove_at(i)
		i -= 1
	_update_heli(delta)
	_update_spikes()
	if level == 0:
		_retire_units(delta)
		return
	var pp: Vector3 = p.global_position_now()
	unseen_t += delta
	if unseen_t > 1.5 and state == "pursuit":
		state = "search"
		Sfx.play("radio_blip")
	if state == "pursuit":
		last_known = pp
		resist_t += delta
		if resist_t > 20.0 and level < 5:
			resist_t = 0.0
			report("resisting", pp, 0.9, true)
	else:
		# only genuinely unseen time counts; a changed vehicle / outfit helps a little
		var rate := 1.0
		if p.vehicle != seen_vehicle and p.vehicle != null:
			rate = 1.35
		if p.hidden_look_change > 0.0:
			rate = 1.5
		if p.st == p.St.SWIM and p.underwater:
			rate *= 1.3
		escape_t += delta * rate
		if escape_t >= float(ESCAPE[level]):
			G.say("You lost the police", Color(0.6, 1.0, 0.6))
			Sfx.play("wanted_clear")
			clear()
			return
	dispatch_t -= delta
	if dispatch_t <= 0.0:
		dispatch_t = 3.5 - level * 0.35
		_dispatch(pp)
	block_t -= delta
	if block_t <= 0.0 and level >= 3:
		block_t = 16.0 - level * 1.5
		_roadblock(pp)
	# update search targets for units
	for u in units:
		if is_instance_valid(u) and u.ai != null and state == "search" and u.ai.search_point == Vector3.ZERO:
			u.ai.search_point = random_search_point()


func _retire_units(_delta: float) -> void:
	var pp: Vector3 = G.player.global_position_now()
	var cam := get_viewport().get_camera_3d()
	var i := units.size() - 1
	while i >= 0:
		var u = units[i]
		if not is_instance_valid(u):
			units.remove_at(i)
		else:
			var d: float = u.global_position.distance_to(pp)
			if d > 150.0 or (d > 70.0 and cam != null and not cam.is_position_in_frustum(u.global_position)):
				if not u.has_player():
					for o in u.occupants():
						if not G.is_player(o):
							o.queue_free()
					u.queue_free()
				units.remove_at(i)
		i -= 1


func _count_units() -> int:
	var n := 0
	var i := units.size() - 1
	while i >= 0:
		var u = units[i]
		if not is_instance_valid(u) or u.dead or u.has_player():
			units.remove_at(i)
		elif u.global_position.distance_to(last_known) > 320.0:
			for o in u.occupants():
				if not G.is_player(o):
					o.queue_free()
			u.queue_free()
			units.remove_at(i)
		else:
			n += 1
		i -= 1
	return n


func _hidden_road_point(pp: Vector3, dmin: float, dmax: float) -> Array:
	var cam := get_viewport().get_camera_3d()
	for attempt in 14:
		var a := Vector2i(randi() % WorldLayout.NX, randi() % WorldLayout.NZ)
		var nb := WorldLayout.neighbors(a)
		var b: Vector2i = nb[randi() % nb.size()]
		var ends := WorldLayout.lane_ends(a, b, 0)
		var t := randf_range(0.1, 0.9)
		var pos: Vector3 = (ends[0] as Vector3).lerp(ends[1], t)
		var d := pos.distance_to(pp)
		if d < dmin or d > dmax:
			continue
		if cam != null and cam.is_position_in_frustum(pos + Vector3(0, 1, 0)) and G.los(cam.global_position, pos + Vector3(0, 1.2, 0)):
			continue
		var clear := true
		for v in get_tree().get_nodes_in_group("vehicles"):
			if (v as Node3D).global_position.distance_to(pos) < 10.0:
				clear = false
				break
		if clear:
			return [a, b, t]
	return []


func _dispatch(pp: Vector3) -> void:
	if G.traffic == null:
		return
	var n := _count_units()
	var want: int = WANT_CARS[level]
	if n >= want:
		return
	var spot := _hidden_road_point(last_known if state == "search" else pp, 70.0, 150.0)
	if spot.is_empty():
		return
	var tactical := level >= 4 and randf() < 0.45
	var vid := "swat" if tactical else "police"
	var v: Vehicle = G.traffic.spawn_traffic_vehicle(vid, spot[0], spot[1], 0, spot[2], "swat" if tactical else "cop")
	if v == null:
		return
	G.traffic.moving.erase(v)
	units.append(v)
	if G.peds:
		var mate: NPC = G.peds.make_driver("swat" if tactical or level >= 4 else "cop")
		mate.enter_vehicle(v, 1)
	v.set_siren(true)
	v.ai.mode = "pursuit"
	v.ai.target = G.player
	v.ai.ignore_signals = true
	v.ai.search_point = random_search_point() if state == "search" else Vector3.ZERO


func spawn_unit_near(dist: float = 45.0) -> void:
	## Debug/admin helper: forces a cruiser onto the nearest road.
	var pp: Vector3 = G.player.global_position_now()
	var spot := _hidden_road_point(pp, dist * 0.6, dist * 2.2)
	if spot.is_empty() or G.traffic == null:
		return
	var v: Vehicle = G.traffic.spawn_traffic_vehicle("police", spot[0], spot[1], 0, spot[2], "cop")
	if v:
		G.traffic.moving.erase(v)
		units.append(v)
		if G.peds:
			G.peds.make_driver("cop").enter_vehicle(v, 1)
		if level > 0:
			v.set_siren(true)
			v.ai.mode = "pursuit"
			v.ai.target = G.player
			v.ai.ignore_signals = true


func _roadblock(pp: Vector3) -> void:
	var pv: Vehicle = G.player.vehicle
	if pv == null or pv.speed < 6.0 or pv.kind not in ["car", "bike"] or roadblocks.size() >= (1 if level < 4 else 2):
		return
	# intersection ahead of the player along its heading
	var dir := G.flat(pv.linear_velocity).normalized()
	var ahead := pp + dir * 115.0
	var ix := WorldLayout.nearest_inter(ahead)
	var c := WorldLayout.inter_pos(ix)
	if c.distance_to(pp) < 70.0 or c.distance_to(pp) > 190.0:
		return
	var along_x := absf(dir.x) > absf(dir.z)
	var back := Vector3(-signf(dir.x), 0, 0) if along_x else Vector3(0, 0, -signf(dir.z))
	var centre := c + back * (WorldLayout.inter_half(ix, along_x) + 9.0)
	var cross := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var nodes: Array = []
	for s in [-1.0, 1.0]:
		var v := VehicleFactory.spawn("police" if level < 4 or s < 0 else "swat", centre + cross * s * 3.0 + Vector3(0, 0.4, 0), atan2(-cross.x, -cross.z) + (0.25 * s))
		v.handbrake = true
		v.brake = 1.0
		v.set_siren(true)
		nodes.append(v)
		if G.peds:
			var cop: NPC = G.peds.spawn("swat" if level >= 4 else "cop", centre + cross * s * 4.5 + back * 2.5 + Vector3(0, 0.2, 0))
			cop.engage(G.player)
			cop.cover_pos = cop.global_position
	if level >= 4:
		var sp := MeshInstance3D.new()
		sp.mesh = Assets.mesh("props/kit_props", "prop_spike_strip")
		G.main.add_child(sp)
		sp.global_transform = Transform3D(Basis(Vector3.UP, atan2(cross.x, cross.z) + PI * 0.5), centre - back * 9.0 + Vector3(0, 0.02, 0))
		spikes.append(sp)
	roadblocks.append({"pos": centre, "nodes": nodes, "t": 40.0})
	Sfx.play("radio_blip")


func _update_spikes() -> void:
	if spikes.is_empty() or G.player == null:
		return
	var pv: Vehicle = G.player.vehicle
	if pv == null or not (pv is Car):
		return
	for s in spikes:
		if is_instance_valid(s) and pv.global_position.distance_to(s.global_position) < 2.6 and pv.speed > 3.0:
			var car := pv as Car
			if not car.perf.bulletproof:
				for k in car.tires_popped.size():
					if not car.tires_popped[k] and randf() < 0.8:
						car.tires_popped[k] = true
				Sfx.play("tire_pop", pv.global_position)
				G.say("Spike strip! Tires blown", Color(1, 0.6, 0.3))
			s.queue_free()
	spikes = spikes.filter(func(x): return is_instance_valid(x))
	var i := roadblocks.size() - 1
	while i >= 0:
		roadblocks[i].t -= get_process_delta_time()
		if roadblocks[i].t <= 0.0 and G.player.global_position_now().distance_to(roadblocks[i].pos) > 90.0:
			for n in roadblocks[i].nodes:
				if is_instance_valid(n) and not (n as Vehicle).has_player():
					n.queue_free()
			roadblocks.remove_at(i)
		i -= 1


# ------------------------------------------------------------------ helicopter support
func _update_heli(delta: float) -> void:
	var want := level >= 3
	if heli != null and not is_instance_valid(heli):
		heli = null
	if heli == null:
		if want and randf() < delta * 0.25:
			var pp: Vector3 = G.player.global_position_now()
			var a := randf() * TAU
			heli = VehicleFactory.spawn("policeheli", pp + Vector3(cos(a) * 260.0, 70.0, sin(a) * 260.0), 0.0) as Heli
			heli.engine_on = true
			heli.rotor = 1.0
			heli.gravity_scale = 0.0
			heli.ai = Node.new()
			heli.add_child(heli.ai)
			heli_light = SpotLight3D.new()
			heli_light.spot_range = 120.0
			heli_light.spot_angle = 11.0
			heli_light.light_energy = 22.0
			heli_light.shadow_enabled = false
			heli.add_child(heli_light)
			heli_light.position = Vector3(0, 0.5, -1.5)
		return
	if heli.dead:
		heli.gravity_scale = 1.0
		heli.ai_target_vel = null
		heli = null
		return
	var hp := heli.global_position
	var ppos: Vector3 = G.player.global_position_now()
	var leaving: bool = heli.has_meta("leaving") or not want
	var focus := ppos if state == "pursuit" else last_known
	var t := Time.get_ticks_msec() / 1000.0
	var orbit := focus + Vector3(cos(t * 0.22) * 38.0, 46.0 + 4.0 * level, sin(t * 0.22) * 38.0)
	if leaving:
		orbit = hp + (hp - ppos).normalized() * 200.0 + Vector3(0, 30, 0)
		if hp.distance_to(ppos) > 330.0:
			heli.queue_free()
			heli = null
			return
	var to := orbit - hp
	heli.ai_target_vel = to.limit_length(1.0) * minf(to.length() * 0.8, 34.0)
	heli_light.visible = G.timew != null and G.timew.night > 0.3 and not leaving
	heli_light.look_at(focus + Vector3(0, 0.5, 0), Vector3.UP)
	if leaving or level == 0:
		return
	var sees := G.los(hp + Vector3(0, -1.0, 0), ppos + Vector3(0, 1.0, 0), [heli.get_rid(), G.player.get_rid()] + ([G.player.vehicle.get_rid()] if G.player.vehicle else []))
	if sees and hp.distance_to(ppos) < 130.0 and not (G.player.st == G.player.St.SWIM and G.player.underwater):
		spotted(heli)
		heli_fire -= delta
		if level >= 4 and heli_fire <= 0.0 and hp.distance_to(ppos) < 95.0:
			heli_fire = randf_range(0.12, 0.2) if randi() % 7 != 0 else randf_range(1.5, 3.0)
			var from := hp + Vector3(0, -0.8, 0)
			var dir := (ppos + Vector3(0, 1.0, 0) + Vector3(randf_range(-2.2, 2.2), randf_range(-1, 1), randf_range(-2.2, 2.2)) - from).normalized()
			Weapons.fire(heli, "carbine", from, dir, {"exclude": [heli.get_rid()], "muzzle": from, "dmg_mul": 0.5})
