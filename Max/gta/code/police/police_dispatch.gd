class_name PoliceDispatch
extends Node
## Police presence and response. Keeps a patrol car in ordinary traffic, and while the
## player is wanted sends units that escalate with the level:
##   1 - one patrol car, officers try to arrest      2 - two cars, officers return fire
##   3 - three cars, helicopter, roadblocks           4 - tactical teams, spike strips
##   5 - maximum units, second tactical team, most aggressive pursuit driving
## Units drive to the last known position, pursue while the player is seen, dismount to
## fight / arrest, search on foot and by car when the player is hidden, and get back into
## their cars when the suspect drives off.

class Unit:
	extends RefCounted
	var veh: Vehicle = null
	var officers: Array[NPC] = []
	var ai: AIDriver = null
	var kind: StringName = &"patrol"       # patrol | swat | block | air
	var ambient := false                   # ordinary patrol (not a response unit)
	var timer := 0.0
	var dismount_cd := 0.0
	var until := 0.0
	var extras: Array[Node] = []           # roadblock props

const GROUND_UNITS := [0, 1, 2, 3, 4, 5]
const AGGRESSION := [0.0, 0.2, 0.45, 0.7, 0.9, 1.0]

var units: Array[Unit] = []
var rng := RandomNumberGenerator.new()
var graph: RoadGraph = null
var air: Unit = null
var _tick := 0.0
var _spawn_cd := 2.0
var _block_cd := 22.0
var _patrol_cd := 6.0
var _air_cd := 0.0
var _orbit := 0.0
var _beat_done := false
var debug_blocks := false

func _ready() -> void:
	rng.seed = 110
	graph = Game.world.graph
	Events.player_respawned.connect(_on_respawn)

func now() -> float:
	return Game.clock

func _visible(p: Vector3) -> bool:
	var cam: Camera3D = Game.cam.cam if Game.cam != null else null
	return cam != null and cam.is_position_in_frustum(p + Vector3(0, 1.0, 0))

# ---------------------------------------------------------------- unit creation
func _car_id(swat: bool) -> String:
	if swat and VehicleDB.has_model("car_swat"):
		return "car_swat"
	return "car_police" if VehicleDB.has_model("car_police") else "car_sedan"

func _tune(cop: NPC, lvl: int) -> void:
	cop.accuracy_spread = maxf(1.6, cop.accuracy_spread - 0.35 * float(lvl))
	cop.sight += 4.0 * float(lvl)

func spawn_unit(kind: StringName, lane_id: int, s0: float, lvl := 1) -> Unit:
	var p := graph.sample(lane_id, s0)
	var dirv := graph.direction(lane_id, s0)
	var id := _car_id(kind == &"swat")
	var opts := {"tag": "police"}
	if id == "car_sedan":
		opts["paint"] = Color.html("1c2748")       # unmarked cruiser until the Interceptor model is exported
	var v := VehicleFactory.spawn(id, p, atan2(-dirv.x, -dirv.z), opts) as Car
	if v == null:
		return null
	var u := Unit.new()
	u.veh = v
	u.kind = kind
	var crew := 4 if (kind == &"swat" and v.seat_count() >= 4) else 2
	var peds: PedManager = Game.peds
	for i in mini(crew, v.seat_count()):
		var cop := peds.seat_in(v, i, &"swat" if kind == &"swat" else &"police")
		if cop == null:
			continue
		cop.dispatch_vehicle = v
		_tune(cop, lvl)
		u.officers.append(cop)
	u.ai = AIDriver.attach(v, Game.traffic, lane_id, s0)
	v.linear_velocity = dirv * 9.0
	v.lights_on = Game.time != null and Game.time.is_night
	units.append(u)
	return u

## A lane position between `lo` and `hi` metres from `around`, out of the player's view,
## preferably already heading toward it.
func _find_spawn(around: Vector3, lo: float, hi: float) -> Array:
	var pp := Game.player_pos()
	for attempt in 24:
		var lid := graph.random_lane(rng)
		var l := graph.lanes[lid]
		if l.length < 14.0:
			continue
		var s0 := rng.randf_range(5.0, l.length - 6.0)
		var p := graph.sample(lid, s0)
		var d := p.distance_to(around)
		if d < lo or d > hi:
			continue
		var dp := p.distance_to(pp)
		if dp < 65.0 or (dp < 135.0 and _visible(p)):
			continue
		if attempt < 16 and graph.direction(lid, s0).dot((around - p).normalized()) < 0.15:
			continue
		# the lane must actually lead toward the target (no long detours around the block)
		if attempt < 12:
			var b := graph.nearest(around, 60.0)
			if not b.is_empty():
				var r := graph.route(lid, int(b["lane"]))
				var len_r := 0.0
				for li in r:
					len_r += graph.lanes[li].length
				if r.is_empty() or len_r > d * 2.2 + 60.0:
					continue
		if Game.traffic != null and not Game.traffic._free_at(p, 9.0):
			continue
		return [lid, s0]
	return []

func ground_units() -> int:
	var n := 0
	for u in units:
		if (u.kind == &"patrol" or u.kind == &"swat") and not u.officers.is_empty():
			n += 1
	return n

func officer_count() -> int:
	var n := 0
	for u in units:
		n += u.officers.size()
	return n

# ---------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	if air != null:
		_fly(delta)
	_tick -= delta
	if _tick > 0.0:
		return
	var dt := 0.25
	_tick = dt
	var w: WantedSystem = Game.wanted
	var pl: Player = Game.player
	if w == null or pl == null or Game.peds == null:
		return
	if not Game.flags["police"]:
		if not units.is_empty():
			despawn_all()
		return
	var lvl := w.level
	# --- prune
	for i in range(units.size() - 1, -1, -1):
		var u := units[i]
		var alive: Array[NPC] = []
		for o in u.officers:
			if is_instance_valid(o) and o.alive:
				alive.append(o)
		u.officers = alive
		var veh_ok := u.veh != null and is_instance_valid(u.veh) and not u.veh.destroyed
		if alive.is_empty():
			if veh_ok and u.veh.owner_tag == "police" and not u.veh.has_meta("static_spawn"):
				u.veh.owner_tag = ""        # abandoned cruiser: normal clean-up applies
			_free_extras(u)
			if u == air:
				air = null
			units.remove_at(i)
			continue
		u.dismount_cd = maxf(0.0, u.dismount_cd - dt)
		if u.kind == &"air":
			continue
		if lvl > 0:
			_unit_wanted(u, w, pl, lvl, dt)
		else:
			_unit_idle(u, pl, i)
	# --- officers that belong to no unit (beat cops) join in
	if lvl > 0 and w.state == WantedSystem.PURSUIT:
		for n in get_tree().get_nodes_in_group(&"police_units"):
			var cop := n as NPC
			if cop != null and cop.alive and cop.vehicle == null and cop.state != NPC.S.FIGHT and not cop.down:
				if cop.global_position.distance_to(pl.global_position) < 75.0:
					cop.fight(pl)
	# --- reinforcements
	_spawn_cd -= dt
	_block_cd -= dt
	_patrol_cd -= dt
	if lvl > 0:
		if _spawn_cd <= 0.0 and ground_units() < int(GROUND_UNITS[lvl]) and officer_count() < 14:
			var swat_units := 0
			for u in units:
				if u.kind == &"swat":
					swat_units += 1
			var kind: StringName = &"swat" if (lvl >= 4 and swat_units < lvl - 3) else &"patrol"
			var spot := _find_spawn(w.last_known, 85.0, 175.0)
			if not spot.is_empty():
				var u2 := spawn_unit(kind, int(spot[0]), float(spot[1]), lvl)
				if u2 != null:
					u2.ai.drive_to(w.last_known, true)
					_spawn_cd = maxf(2.5, 7.0 - float(lvl))
		if lvl >= 3 and _block_cd <= 0.0 and pl.vehicle != null and absf((pl.vehicle as Vehicle).speed) > 11.0 and w.state == WantedSystem.PURSUIT:
			_block_cd = 9.0
			if _make_roadblock(lvl):
				_block_cd = 30.0
		if lvl >= 3 and air == null:
			_air_cd -= dt
			if _air_cd <= 0.0:
				_spawn_air(w.last_known, lvl)
				_air_cd = 45.0
	else:
		_spawn_cd = 2.0
		_air_cd = 6.0
		if _patrol_cd <= 0.0:
			_patrol_cd = 8.0
			var ambient := 0
			for u in units:
				if u.ambient:
					ambient += 1
			if ambient < 1 and Game.flags["traffic"]:
				var spot2 := _find_spawn(pl.global_position, 80.0, 150.0)
				if not spot2.is_empty():
					var pu := spawn_unit(&"patrol", int(spot2[0]), float(spot2[1]), 1)
					if pu != null:
						pu.ambient = true
	if not _beat_done:
		_beat_done = true
		_spawn_beat_cops()

func _unit_wanted(u: Unit, w: WantedSystem, pl: Player, lvl: int, dt: float) -> void:
	var veh_ok := u.veh != null and is_instance_valid(u.veh) and not u.veh.destroyed
	var seen := w.state == WantedSystem.PURSUIT
	var tpos := w.last_known
	u.ambient = false
	if u.kind == &"block":
		for o in u.officers:
			if seen and o.state != NPC.S.FIGHT and o.global_position.distance_to(pl.global_position) < 80.0:
				o.fight(pl)
		if now() > u.until or pl.global_position.distance_to(tpos) > 400.0:
			_free_extras(u)
			u.kind = &"patrol"
		return
	var drv: Character = u.veh.driver() if veh_ok else null
	var mounted := drv != null and drv.alive and u.officers.has(drv as NPC)
	if mounted:
		var car := u.veh as Car
		if u.ai == null or not is_instance_valid(u.ai) or u.ai.is_queued_for_deletion():
			u.ai = AIDriver.attach(car, Game.traffic, -1, 0.0)
		car.set_siren(true)
		car.lights_on = true
		var d := car.global_position.distance_to(pl.global_position)
		if seen:
			var tgt := Game.player_target()
			if u.ai.mode != AIDriver.Mode.CHASE or u.ai.target != tgt:
				u.ai.chase(tgt, float(AGGRESSION[lvl]))
			u.ai.aggression = float(AGGRESSION[lvl])
			var on_foot := pl.vehicle == null
			var p_speed := pl.velocity.length() if on_foot else absf((pl.vehicle as Vehicle).speed)
			var my_speed := absf(car.speed)
			if u.dismount_cd <= 0.0 and my_speed < 5.0 and p_speed < 4.5 and d < (26.0 if on_foot else 15.0):
				_dismount(u, pl)
			elif u.dismount_cd <= 0.0 and on_foot and d < 13.0 and my_speed < 9.0:
				_dismount(u, pl)
		else:
			u.timer -= dt
			if u.ai.mode != AIDriver.Mode.GOTO or u.ai.arrived or u.timer <= 0.0:
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.0, w.search_radius)
				if not u.ai.drive_to(tpos + Vector3(cos(a), 0.0, sin(a)) * r, true):
					u.ai.cruise()
					u.ai.emergency = true
				u.timer = 14.0
				# every now and then a crew gets out and searches on foot
				if u.ai.arrived and lvl <= 3 and rng.randf() < 0.4 and car.global_position.distance_to(tpos) < 40.0:
					_dismount(u, null)
		return
	# --- crew on foot
	var fleeing := pl.vehicle != null and absf((pl.vehicle as Vehicle).speed) > 7.0
	var nearest := 1.0e9
	for o in u.officers:
		nearest = minf(nearest, o.global_position.distance_to(pl.global_position))
	var remount := veh_ok and u.dismount_cd <= 0.0 and (fleeing or (seen and nearest > 60.0) or (not seen and u.veh.global_position.distance_to(tpos) > 70.0))
	for k in u.officers.size():
		var o := u.officers[k]
		if o.vehicle != null or o.down:
			continue
		if remount and k < u.veh.seat_count() and u.veh.seats[k]["occupant"] == null:
			if o.enter_vehicle != u.veh:
				o.order_enter(u.veh, k)
		elif o.enter_vehicle != null:
			pass                         # already on the way to the car
		elif seen:
			if o.state != NPC.S.FIGHT:
				o.fight(pl)
		elif o.state != NPC.S.GOTO and o.state != NPC.S.FIGHT:
			var a2 := rng.randf() * TAU
			var r2 := rng.randf_range(4.0, minf(w.search_radius, 34.0))
			o.order_search(tpos + Vector3(cos(a2), 0.0, sin(a2)) * r2)
		elif o.state == NPC.S.FIGHT and now() - o.last_seen_target > 7.0:
			o.calm()

func _unit_idle(u: Unit, pl: Player, _index: int) -> void:
	var veh_ok := u.veh != null and is_instance_valid(u.veh) and not u.veh.destroyed
	if u.kind == &"block":
		_free_extras(u)
		u.kind = &"patrol"
	if veh_ok:
		(u.veh as Vehicle).set_siren(false)
	var drv: Character = u.veh.driver() if veh_ok else null
	var mounted := drv != null and drv.alive and u.officers.has(drv as NPC)
	var d := 1.0e9
	if mounted:
		if u.ai == null or not is_instance_valid(u.ai) or u.ai.is_queued_for_deletion():
			u.ai = AIDriver.attach(u.veh as Car, Game.traffic, -1, 0.0)
		if u.ai.mode != AIDriver.Mode.CRUISE:
			u.ai.cruise()
		d = u.veh.global_position.distance_to(pl.global_position)
	else:
		for k in u.officers.size():
			var o := u.officers[k]
			d = minf(d, o.global_position.distance_to(pl.global_position))
			if o.vehicle != null or o.down:
				continue
			if o.state == NPC.S.FIGHT:
				o.calm()
			if veh_ok and k < u.veh.seat_count() and u.veh.seats[k]["occupant"] == null:
				if o.enter_vehicle != u.veh:
					o.order_enter(u.veh, k)
			elif o.enter_vehicle == null and not o.ambient:
				o.ambient = true                 # on their own now: the ambient population reclaims them
				o.remove_from_group(&"police_units")
	# stand-down: response units leave the scene, one patrol stays in traffic
	var ambient_units := 0
	for other in units:
		if other.ambient:
			ambient_units += 1
	if not u.ambient and mounted and ambient_units == 0:
		u.ambient = true
	var far := d > 150.0 or (d > 85.0 and not u.ambient and not _visible(u.veh.global_position if veh_ok else pl.global_position))
	if far and (not u.ambient or d > 200.0):
		_despawn(u)

func _dismount(u: Unit, pl: Player) -> void:
	if u.veh == null or not is_instance_valid(u.veh):
		return
	u.veh.in_handbrake = true
	u.veh.in_throttle = 0.0
	for i in u.veh.seat_count():
		var c: Character = u.veh.seats[i]["occupant"]
		if c is NPC and (c as NPC).is_cop():
			u.veh.open_door(i, true)
			u.veh.unseat(i)
			if pl != null:
				(c as NPC).fight(pl)
	u.dismount_cd = 7.0
	u.ai = null

func _free_extras(u: Unit) -> void:
	for e in u.extras:
		if not is_instance_valid(e):
			continue
		if e is Vehicle:
			# roadblock cars stay behind as abandoned cruisers (normal clean-up removes them later)
			if e != u.veh:
				(e as Vehicle).owner_tag = ""
				(e as Vehicle).set_siren(false)
		else:
			e.queue_free()
	u.extras.clear()

func _despawn(u: Unit) -> void:
	_free_extras(u)
	for o in u.officers:
		if is_instance_valid(o) and o.vehicle == null:
			o.queue_free()
	if u.veh != null and is_instance_valid(u.veh) and not u.veh.has_player() and not u.veh.has_meta("static_spawn"):
		if u.veh.ai != null and is_instance_valid(u.veh.ai):
			u.veh.ai.release()
		u.veh.queue_free()
	if u == air:
		air = null
	units.erase(u)

func despawn_all() -> void:
	for u in units.duplicate():
		_despawn(u)

func _on_respawn() -> void:
	# after WASTED / BUSTED the scene is reset around the hospital / station
	for u in units.duplicate():
		if u.veh == null or not is_instance_valid(u.veh) or u.veh.global_position.distance_to(Game.player_pos()) > 60.0:
			_despawn(u)

# ---------------------------------------------------------------- beat cops
func _spawn_beat_cops() -> void:
	var city: CityBuilder = Game.world.city
	var hq: Dictionary = city.locations.get("police_hq", {})
	if hq.is_empty():
		return
	var c: Vector3 = hq.get("release", hq["pos"])
	var rect := Rect2(c.x - 9.0, c.z - 3.0, 18.0, 7.0)
	for i in 2:
		var p := Vector3(rng.randf_range(rect.position.x, rect.end.x), c.y + 0.1, rng.randf_range(rect.position.y, rect.end.y))
		var cop := (Game.peds as PedManager).spawn(&"police", p, rng.randf() * TAU)
		cop.wander_area({"rect": rect, "y": c.y})

# ---------------------------------------------------------------- roadblocks
func _make_roadblock(lvl: int) -> bool:
	var pt: Node3D = Game.player_target()
	if not (pt is RigidBody3D):
		return false
	var vel := (pt as RigidBody3D).linear_velocity
	var near := graph.nearest(pt.global_position, 25.0, vel.normalized())
	if near.is_empty():
		return false
	var base_dist := clampf(vel.length() * 6.0, 130.0, 200.0)
	var found: Array = []
	# several look-ahead distances: the first one that lands on a plain stretch of road wins
	for extra: float in [0.0, 25.0, -25.0, 50.0, 75.0, -45.0]:
		found = _block_point(int(near["lane"]), float(near["s"]), base_dist + extra, pt.global_position)
		if not found.is_empty():
			break
	if found.is_empty():
		return false
	var lid: int = found[0]
	var s: float = found[1]
	var lane := graph.lanes[lid]
	var p := graph.sample(lid, s)
	var dirv := graph.direction(lid, s)
	var right := Vector3(-dirv.z, 0.0, dirv.x)
	var offs: Array = RoadGraph.lane_offsets(lane.kind)
	var centre := p - right * float(offs[lane.lane_index])
	var half := 5.2 if lane.kind != "arterial" else 8.6
	var u := Unit.new()
	u.kind = &"block"
	u.until = now() + 55.0
	var yaw := atan2(-dirv.x, -dirv.z)
	var id := _car_id(false)
	var n_cars := 2 if lane.kind != "arterial" else 3
	for i in n_cars:
		var t := (float(i) + 0.5) / float(n_cars) * 2.0 - 1.0
		var cp := centre + right * t * (half - 1.2)
		var opts := {"tag": "police"}
		if id == "car_sedan":
			opts["paint"] = Color.html("1c2748")
		var v := VehicleFactory.spawn(id, cp, yaw + PI * 0.5 + rng.randf_range(-0.2, 0.2), opts)
		if v == null:
			continue
		v.set_siren(true)
		v.lights_on = true
		v.in_handbrake = true
		u.extras.append(v)
		if u.veh == null:
			u.veh = v
		var cop := (Game.peds as PedManager).spawn(&"swat" if lvl >= 4 else &"police", cp + dirv * 2.6 + Vector3(0, 0.2, 0), yaw + PI)
		cop.cover_pos = cp + dirv * 2.6
		_tune(cop, lvl)
		u.officers.append(cop)
		cop.fight(Game.player)
	if u.officers.is_empty():
		return false
	if lvl >= 4 and PropFactory.exists("spike_strip"):
		var sp := centre - dirv * 13.0
		var strip := PropFactory.spawn(Game.world.city, "spike_strip", sp + Vector3(0, 0.03, 0), yaw + PI * 0.5, {"static": true})
		if strip != null:
			u.extras.append(strip)
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = Phys.VEHICLE
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(half * 2.0 - 1.0, 0.6, 0.7)
		cs.shape = box
		area.add_child(cs)
		Game.world.city.add_child(area)
		area.global_transform = Transform3D(Basis(Vector3.UP, yaw), sp + Vector3(0, 0.3, 0))
		area.body_entered.connect(_on_spikes)
		u.extras.append(area)
	units.append(u)
	Game.notify("Police roadblock ahead", "wanted")
	return true

func _on_spikes(body: Node) -> void:
	if body is Car and (body as Car).owner_tag != "police":
		var car := body as Car
		if bool(car.def.get("bulletproof_tires", false)) or bool(car.mods.get("bp_tires", false)):
			return
		var popped := false
		for wd in car.wheels:
			if not wd["punctured"]:
				wd["punctured"] = true
				popped = true
		if popped:
			Audio.play(&"tire_pop", car.global_position, 0.0)

# ---------------------------------------------------------------- air support
func _spawn_air(around: Vector3, lvl: int) -> void:
	var id := "heli_police" if VehicleDB.has_model("heli_police") else "heli_civil"
	if not VehicleDB.has_model(id):
		return
	var a := rng.randf() * TAU
	var pos := around + Vector3(cos(a), 0.0, sin(a)) * 190.0
	pos.x = clampf(pos.x, -290.0, 290.0)
	pos.z = clampf(pos.z, -290.0, 320.0)
	pos.y = maxf(Game.ground_y(pos.x, pos.z), 0.0) + 55.0
	var opts := {"tag": "police"}
	if id == "heli_civil":
		opts["paint"] = Color.html("17181b")
		opts["paint_b"] = Color.html("f2f0ea")
	var h := VehicleFactory.spawn(id, pos, a + PI * 0.5, opts) as Heli
	if h == null:
		return
	var u := Unit.new()
	u.veh = h
	u.kind = &"air"
	var peds: PedManager = Game.peds
	var pilot := peds.seat_in(h, 0, &"police")
	if pilot == null:
		h.queue_free()
		return
	pilot.sight = 140.0
	u.officers.append(pilot)
	if lvl >= 4 and h.seat_count() > 2:
		var gunner_seat := h.seat_count() - 1
		var g := peds.seat_in(h, gunner_seat, &"swat")
		if g != null:
			g.sight = 120.0
			g.accuracy_spread = 3.2
			u.officers.append(g)
	h.engine_on = true
	h.rotor_speed = 1.0
	h.sleeping = false
	if h.searchlight != null:
		h.searchlight.visible = true
	units.append(u)
	air = u
	Game.notify("Police helicopter inbound", "wanted")

## Simple pilot on the real flight model: hold altitude, orbit the target, face it.
func _fly(delta: float) -> void:
	if air == null or air.veh == null or not is_instance_valid(air.veh) or air.veh.destroyed:
		return
	var h := air.veh as Heli
	var w: WantedSystem = Game.wanted
	var pl: Player = Game.player
	if w == null or pl == null:
		return
	var pilot_ok := h.driver() != null and h.driver().alive
	if not pilot_ok:
		return
	var leaving := w.level < 3
	var focus := pl.global_position if w.state == WantedSystem.PURSUIT else w.last_known
	_orbit += delta * (0.16 if w.state == WantedSystem.PURSUIT else 0.28)
	var radius := 34.0 if w.state == WantedSystem.PURSUIT else minf(w.search_radius, 60.0)
	var goal := focus + Vector3(cos(_orbit), 0.0, sin(_orbit)) * radius
	var alt := 36.0
	if leaving:
		goal = h.global_position + (h.global_position - pl.global_position).normalized() * 80.0
		alt = 70.0
		if h.global_position.distance_to(pl.global_position) > 260.0:
			_despawn(air)
			return
	var ground := maxf(Game.ground_y(h.global_position.x, h.global_position.z), 0.0)
	# clear rooftops ahead
	var roof := Game.ray(h.global_position + Vector3(0, 60.0, 0), h.global_position - Vector3(0, 80.0, 0), Phys.WORLD, [h.get_rid()])
	if not roof.is_empty():
		ground = maxf(ground, (roof["position"] as Vector3).y)
	var target_y := ground + alt
	h.in_lift = clampf((target_y - h.global_position.y) * 0.22, -1.0, 1.0)
	var to := goal - h.global_position
	to.y = 0.0
	var v_des := to * 0.55
	if v_des.length() > 22.0:
		v_des = v_des.normalized() * 22.0
	var err := v_des - Vector3(h.linear_velocity.x, 0.0, h.linear_velocity.z)
	var b := h.global_transform.basis
	var fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	h.in_pitch = clampf(err.dot(fwd) * 0.11, -1.0, 1.0)
	h.in_roll = clampf(err.dot(right) * 0.11, -1.0, 1.0)
	var look := focus - h.global_position
	var ang := atan2(look.dot(right), look.dot(fwd))
	h.in_yaw = clampf(ang * 1.3, -1.0, 1.0)
	if h.searchlight != null:
		h.searchlight.visible = Game.time != null and Game.time.night > 0.3
		if h.searchlight.visible:
			h.searchlight.look_at(focus + Vector3(0, 0.5, 0), Vector3.UP)

# ---------------------------------------------------------------- admin / debug
func status() -> Dictionary:
	return {"units": units.size(), "officers": officer_count(), "air": air != null}

## Lane position `dist` metres ahead of (lane, s) along straight connectors, on a plain stretch
## of road far enough from the player and out of sight when close. Returns [lane, s] or [].
func _block_point(lane_id: int, s0: float, dist: float, from: Vector3) -> Array:
	var lid := lane_id
	var s := s0
	var remaining := dist
	for hop in 14:
		var l := graph.lanes[lid]
		if s + remaining <= l.length:
			s += remaining
			remaining = 0.0
			break
		remaining -= l.length - s
		if l.next.is_empty():
			return []
		var pick: int = l.next[0]
		for c in l.next:
			if graph.lanes[c].turn == 0:
				pick = c
		lid = pick
		s = 0.0
	var lane := graph.lanes[lid]
	if lane.is_connector or remaining > 0.0 or s < 10.0 or s > lane.length - 12.0 or lane.kind == "hill":
		if debug_blocks:
			print("[block] d %.0f: lane %d conn %s rem %.1f s %.1f/%.1f kind %s" % [dist, lid, lane.is_connector, remaining, s, lane.length, lane.kind])
		return []
	var p := graph.sample(lid, s)
	var dp := p.distance_to(from)
	if dp < 85.0 or (dp < 125.0 and _visible(p)):
		if debug_blocks:
			print("[block] d %.0f: too close / visible dp %.0f" % [dist, dp])
		return []
	var dirv := graph.direction(lid, s)
	var offs: Array = RoadGraph.lane_offsets(lane.kind)
	var centre := p - Vector3(-dirv.z, 0.0, dirv.x) * float(offs[lane.lane_index])
	if Game.traffic != null and not Game.traffic._free_at(centre, 6.0):
		if debug_blocks:
			print("[block] d %.0f: occupied at %s" % [dist, centre])
		return []
	return [lid, s]
