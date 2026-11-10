class_name Wanted
extends Node
# 0-5 star wanted system: witnesses, delayed reports, pursuit vs search with last-known position,
# line-of-sight based escape, dispatch of cruisers / tactical vans / helicopter, roadblocks, arrest.

const CRIMES := {
	"gunfire": [4.0, 1], "gunfire_quiet": [1.0, 1], "assault": [8.0, 1], "kill": [22.0, 2], "kill_cop": [60.0, 3],
	"attack_police": [32.0, 2], "carjack": [12.0, 1], "carjack_police": [45.0, 2], "steal_police": [30.0, 2],
	"hit_ped": [10.0, 1], "collision": [3.0, 1], "ram_police": [22.0, 2], "explosion": [35.0, 3],
	"destroy_police": [50.0, 3], "robbery": [28.0, 2],
}
const THRESH := [0.0, 6.0, 30.0, 75.0, 140.0, 230.0]
const ESCAPE := [0.0, 14.0, 22.0, 32.0, 44.0, 58.0]
const UNITS := [0, 1, 2, 3, 4, 5]

var stars := 0
var heat := 0.0
var state := "none"
var seen := false
var lethal := false
var last_known := Vector3.ZERO
var unseen_t := 0.0
var units: Array = []
var heli = null
var blocks: Array = []
var pending: Array = []
var spawn_t := 0.0
var block_t := 12.0
var heli_t := 0.0
var arrest_t := 0.0
var known_vehicle = null
var veh_disguise := false
var cloth_disguise_t := -100.0
var check_t := 0.0
var search_seed := 0.0


func crime(type: String, pos: Vector3, victim = null) -> void:
	var c: Array = CRIMES[type]
	var p = G.player
	var direct := stars > 0 and seen
	if not direct:
		for h in G.humanoids:
			if h is NPC and not h.dead and h.role in ["cop", "swat"] and h != victim:
				var d: float = h.global_position.distance_to(pos)
				if d < 65.0 and (h.state == "vehicle" or G.los(h.eye(), pos + Vector3.UP * 1.2, [h, p])):
					direct = true
					break
		if not direct and victim != null and is_instance_valid(victim) and victim is NPC and victim.role in ["cop", "swat"] and not victim.dead:
			direct = true
	if direct:
		_add(c[0], c[1])
		return
	# civilian witnesses report after a delay; noisy crimes are also heard
	var hearing := 0.0
	if type == "gunfire": hearing = 45.0
	elif type == "explosion": hearing = 90.0
	elif type == "gunfire_quiet": hearing = 6.0
	var witness = null
	for h in G.humanoids:
		if not (h is NPC) or h.dead or h == victim or h.role == "gang":
			continue
		var d2: float = h.global_position.distance_to(pos)
		if d2 < hearing or (d2 < 32.0 and h.state != "vehicle" and G.los(h.eye(), pos + Vector3.UP * 1.2, [h, p])) or (d2 < 25.0 and h.state == "vehicle"):
			witness = h
			break
	if witness != null:
		for pr in pending:
			if pr.w == witness:
				pr.heat += c[0]
				pr.min = max(pr.min, c[1])
				return
		pending.append({"t": G.time_now + 3.5, "heat": c[0], "min": c[1], "w": witness, "pos": pos})


func _add(h: float, min_stars: int) -> void:
	heat += h
	var ns := stars
	for k in range(5, 0, -1):
		if heat >= THRESH[k]:
			ns = max(ns, k)
			break
	ns = min(5, max(ns, min_stars))
	if stars == 0:
		last_known = G.player.global_position
		unseen_t = 0.0
		state = "search"
		known_vehicle = G.player.vehicle
		veh_disguise = false
		spawn_t = 1.5
	if ns > stars:
		stars = ns
		heat = max(heat, THRESH[ns])
		G.audio.ui("star")
		unseen_t = min(unseen_t, 4.0)


func set_stars(n: int) -> void:
	if n <= 0:
		clear()
		return
	heat = THRESH[n]
	if stars == 0:
		last_known = G.player.global_position
		state = "search"
		unseen_t = 0.0
		spawn_t = 0.5
	stars = n
	G.audio.ui("star")


func clear() -> void:
	stars = 0
	heat = 0.0
	state = "none"
	seen = false
	lethal = false
	pending.clear()
	arrest_t = 0.0
	for b in blocks:
		for n in b.nodes:
			if is_instance_valid(n):
				if n is NPC:
					G.pop.remove(n)
				elif n is Prop:
					n.wake()
	blocks.clear()
	for v in units:
		if is_instance_valid(v):
			v.siren_on = false
			if G.traffic and v.ai != null and v.ai.mode != "heli":
				G.traffic.cars.append(v)
	units.clear()
	for h in G.humanoids:
		if h is NPC and h.role in ["cop", "swat"] and not h.dead and not h.has_meta("fixed") and h.state != "vehicle":
			h.calm_t = 0.0
			get_tree().create_timer(25.0).timeout.connect(func():
				if is_instance_valid(h) and stars == 0 and not h.dead:
					G.pop.remove(h))


func vehicle_changed(v) -> void:
	if stars > 0 and not seen and v != known_vehicle:
		veh_disguise = true
		G.notify("Switched vehicles unseen: harder to identify")


func changed_clothes() -> void:
	if stars > 0 and not seen:
		cloth_disguise_t = G.time_now
		G.notify("Changed appearance: harder to identify")


func search_point(who) -> Vector3:
	var k: float = float(who.get_instance_id() % 97)
	var r: float = 14.0 + min(unseen_t * 2.2, 55.0)
	var a: float = k * 0.7 + floor(G.time_now / 7.0) * 2.4
	var p := last_known + Vector3(cos(a), 0, sin(a)) * r * (0.4 + fmod(k, 5.0) * 0.15)
	p.x = clamp(p.x, -205.0, 125.0)
	p.z = clamp(p.z, -205.0, 125.0)
	return p


func arrest_tick(dt: float) -> void:
	var p = G.player
	if p.dead or p.busted or lethal:
		return
	if p.vehicle != null and p.vehicle.linear_velocity.length() > 3.0:
		return
	arrest_t += dt * 2.0
	if arrest_t > 2.2:
		arrest_t = 0.0
		p.get_busted()


func _range() -> float:
	var p = G.player
	var r := 80.0
	if p.vehicle == null and p.crouching:
		r *= 0.55 - 0.15 * G.skill("stealth")
	if p.state == "cover":
		r *= 0.7
	if veh_disguise and p.vehicle != null:
		r *= 0.55
	if G.time_now - cloth_disguise_t < 90.0 and p.vehicle == null:
		r *= 0.65
	if G.sky and G.sky.is_night():
		r *= 0.85
	return r


func _check_seen() -> bool:
	var p = G.player
	var tp: Vector3 = p.global_position + Vector3.UP * (0.6 if p.crouching else 1.2)
	var r := _range()
	for h in G.humanoids:
		if not (h is NPC) or h.dead or not (h.role in ["cop", "swat"]):
			continue
		var d: float = h.global_position.distance_to(tp)
		if d > r:
			continue
		if h.state == "vehicle":
			if G.los(h.global_position + Vector3.UP * 1.3, tp, [h, h.vehicle, p, p.vehicle]):
				return true
			continue
		var facing: float = (-h.global_basis.z).dot((tp - h.global_position).normalized())
		if (facing > -0.1 or d < 10.0) and G.los(h.eye(), tp, [h, p, p.vehicle]):
			return true
	if heli != null and is_instance_valid(heli) and not heli.wrecked:
		var d2: float = heli.global_position.distance_to(tp)
		if d2 < 170.0 and G.los(heli.global_position + Vector3.DOWN * 1.0, tp, [heli, p, p.vehicle]):
			return true
	return false


func _process(dt: float) -> void:
	var p = G.player
	if p == null:
		return
	# pending witness reports
	for i in range(pending.size() - 1, -1, -1):
		var pr: Dictionary = pending[i]
		if not is_instance_valid(pr.w) or pr.w.dead:
			pending.remove_at(i)
			G.notify("Witness silenced before reporting", 2.5)
			continue
		if G.time_now >= pr.t:
			pending.remove_at(i)
			var was := stars
			_add(pr.heat, pr.min)
			if was == 0 and stars > 0:
				last_known = pr.pos
				G.notify("A witness called the police")
	arrest_t = max(0.0, arrest_t - dt)
	if stars == 0:
		return
	if p.dead or p.busted:
		return
	check_t -= dt
	if check_t <= 0.0:
		check_t = 0.2
		seen = _check_seen()
	if seen:
		state = "pursuit"
		last_known = p.global_position
		unseen_t = 0.0
		known_vehicle = p.vehicle
		veh_disguise = false
	else:
		state = "search"
		unseen_t += dt
		if unseen_t > ESCAPE[stars]:
			G.notify("You lost the police")
			clear()
			return
	lethal = stars >= 2 or G.time_now - p.last_shot_t < 8.0 or (p.aiming and not p.wdef().get("melee", false))
	# prune + dispatch
	for i in range(units.size() - 1, -1, -1):
		var v = units[i]
		if not is_instance_valid(v) or v.wrecked:
			units.remove_at(i)
		elif v.ai != null and v.ai.want_despawn and v.global_position.distance_to(p.global_position) > 120.0:
			if v.driver != null:
				G.pop.remove(v.driver)
			v.queue_free()
			units.remove_at(i)
	spawn_t -= dt
	var active := 0
	for v in units:
		if v.ai != null and v.driver != null:
			active += 1
	var foot := 0
	for h in G.humanoids:
		if h is NPC and not h.dead and h.role in ["cop", "swat"] and h.state != "vehicle" and not h.has_meta("fixed"):
			foot += 1
	if spawn_t <= 0.0 and units.size() < 10 and active < UNITS[stars] and foot < 2 + int(stars * 1.6):
		spawn_t = 9.0 - stars
		spawn_unit()
	if stars >= 3:
		heli_t -= dt
		if (heli == null or not is_instance_valid(heli) or heli.wrecked) and heli_t <= 0.0:
			heli_t = 45.0
			_spawn_heli()
		block_t -= dt
		if block_t <= 0.0 and p.vehicle != null and p.vehicle.kind in ["car", "bike"] and p.vehicle.linear_velocity.length() > 8.0:
			block_t = 30.0 - stars * 2.0
			_roadblock()
	if heli != null and is_instance_valid(heli) and heli.ai != null and heli.ai.want_despawn:
		heli.queue_free()
		heli = null
	for i in range(blocks.size() - 1, -1, -1):
		var b: Dictionary = blocks[i]
		if G.time_now - b.t > 60.0 and b.pos.distance_to(p.global_position) > 110.0:
			for n in b.nodes:
				if is_instance_valid(n):
					if n is NPC:
						G.pop.remove(n)
					else:
						n.queue_free()
			blocks.remove_at(i)


func spawn_unit(force_id := "") -> void:
	var p = G.player
	var s: Array = G.traffic._spawn_point(last_known, 80.0, 190.0)
	if s.is_empty():
		spawn_t = 1.0
		return
	var id := "police"
	if stars >= 4 and randf() < 0.5:
		id = "swat"
	if force_id != "":
		id = force_id
	var v := Vehicle.make(id)
	G.main.add_child(v)
	v.owner_tag = "police"
	v.ai = AIDriver.new()
	# face toward the suspect along the edge
	var g = G.roads
	var a: int = s[0]
	var b: int = s[1]
	if g.nodes[a].distance_to(last_known) < g.nodes[b].distance_to(last_known):
		var len: float = g.nodes[a].distance_to(g.nodes[b])
		v.ai.place_on(v, b, a, len - s[2])
	else:
		v.ai.place_on(v, a, b, s[2])
	v.ai.mode = "pursuit"
	v.siren_on = true
	v.linear_velocity = -v.global_basis.z * 10.0
	var role := "swat" if id == "swat" else "cop"
	var drv: NPC = G.traffic.add_driver(v, role)
	drv.car = v
	drv.target = p
	v.set_meta("cops", 3 if id == "swat" else 1)
	v.set_meta("role", role)
	v.ai.on_arrive = func(): _unit_arrived(v)
	units.append(v)


func _unit_arrived(v) -> void:
	if not is_instance_valid(v) or v.wrecked or stars == 0:
		return
	var p = G.player
	var drv = v.driver
	v.ai = null
	v.throttle = 0.0
	v.brake = 1.0
	v.handbrake = true
	if drv != null and is_instance_valid(drv) and not drv.is_player:
		drv.leave_vehicle(-1.0)
		drv.car = v
		drv.engage(p)
	v.engine_on = false
	var extra: int = v.get_meta("cops", 0)
	v.set_meta("cops", 0)
	for k in extra:
		var n: NPC = G.pop.spawn(v.get_meta("role", "cop"), v.global_transform * Vector3(v.def.W / 2 + 0.9, 0.3, -1.0 + k * 1.2))
		n.car = v
		n.engage(p)


func _spawn_heli() -> void:
	var p = G.player
	var a := randf() * TAU
	var pos: Vector3 = p.global_position + Vector3(cos(a) * 230.0, 60.0, sin(a) * 230.0)
	heli = Vehicle.make("heli_police")
	G.main.add_child(heli)
	heli.owner_tag = "police"
	heli.global_position = pos
	heli.engine_on = true
	heli.rotor = 1.0
	heli.siren_on = true
	heli.ai = AIDriver.new()
	heli.ai.mode = "heli"
	var sl := SpotLight3D.new()
	sl.spot_range = 90.0
	sl.spot_angle = 12.0
	sl.light_energy = 12.0
	sl.shadow_enabled = false
	sl.position = Vector3(0, 0.4, -1.6)
	heli.add_child(sl)
	heli.set_meta("spot", sl)
	G.notify("Police helicopter inbound")


func _roadblock() -> void:
	var p = G.player
	var g = G.roads
	var vel: Vector3 = p.vehicle.linear_velocity
	var ahead: Vector3 = p.global_position + vel.normalized() * 110.0
	var n0: int = g.nearest(ahead)
	if g.nodes[n0].distance_to(p.global_position) < 60.0:
		return
	# pick the edge leading from that node back toward the player
	var best := -1
	var bd := 1e9
	for n in g.links[n0]:
		var d: float = g.nodes[n].distance_to(p.global_position)
		if d < bd:
			bd = d
			best = n
	if best < 0:
		return
	var dir: Vector3 = g.edge_dir(n0, best)
	var mid: Vector3 = g.nodes[n0] + dir * 30.0
	if G.cam.cam.is_position_in_frustum(mid + Vector3.UP) and mid.distance_to(p.global_position) < 90.0:
		return
	var right := dir.cross(Vector3.UP)
	var hw: float = g.half_width(n0, best)
	var nodes: Array = []
	var yaw := atan2(-right.x, -right.z)
	for sx in [-1.0, 1.0]:
		var v := Vehicle.make("police" if stars < 5 or sx < 0 else "swat")
		G.main.add_child(v)
		v.owner_tag = "police"
		v.global_transform = Transform3D(Basis(Vector3.UP, yaw), mid + right * sx * (hw * 0.5) + Vector3.UP * 0.3)
		v.siren_on = true
		v.set_meta("crew_alive", 0)
		nodes.append(v)
		units.append(v)
		var c: NPC = G.pop.spawn("swat" if stars >= 4 else "cop", mid + right * sx * (hw * 0.5) - dir * 2.6)
		c.car = v
		c.engage(p)
		nodes.append(c)
	for k in 3:
		var pr: Prop = G.world.add_prop("prop_roadblock", mid + dir * 4.0 + right * (k - 1) * hw * 0.62, yaw + PI / 2)
		nodes.append(pr)
	blocks.append({"nodes": nodes, "t": G.time_now, "pos": mid})
	G.notify("Roadblock ahead")
