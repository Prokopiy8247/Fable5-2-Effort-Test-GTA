extends Node
## Traffic: signal clock, moving civilian traffic on the lane graph (spawn/despawn around the player),
## parked vehicles at the world's parking spots, and the persistent aircraft / boats.

var sig_time := 0.0
var moving: Array = []
var cap := 13
var spawn_t := 1.0
var park_t := 0.5
var clean_t := 2.0
var enabled := true
var persistent: Array = []
var weights: Array = []
var total_w := 0.0
var _sig_state := ""


func _ready() -> void:
	for vid in Defs.VEHICLES.keys():
		var w: float = float(Defs.VEHICLES[vid].get("traffic", 0.0))
		if w > 0.0:
			weights.append([vid, w])
			total_w += w
	call_deferred("_spawn_persistent")


func pick_vehicle() -> String:
	var r := G.rng.randf() * total_w
	for w in weights:
		r -= w[1]
		if r <= 0.0:
			return w[0]
	return "sedan"


func _spawn_persistent() -> void:
	if G.world == null:
		return
	for key in ["air", "boats", "special"]:
		for s in G.world.spawns.get(key, []):
			persistent.append({"veh": s.veh, "pos": s.pos, "yaw": s.yaw, "node": null})
	_refresh_persistent(true)


func _refresh_persistent(force: bool = false) -> void:
	var pp: Vector3 = G.player.global_position_now() if G.player else Vector3.ZERO
	for p in persistent:
		var n = p.node
		var gone: bool = n == null or not is_instance_valid(n)
		if not gone and (n.dead and n.wreck_timer <= 0.0) and n.global_position.distance_to(pp) > 80.0:
			n.queue_free()
			gone = true
		if not gone and not n.dead and n.driver == null and not n.owned and n.global_position.distance_to(p.pos) > 40.0 and n.global_position.distance_to(pp) > 220.0:
			n.queue_free()
			gone = true
		if gone and (force or (p.pos as Vector3).distance_to(pp) > 120.0):
			var v := VehicleFactory.spawn(p.veh, p.pos, p.yaw)
			v.no_despawn = true
			p.node = v


func intersection_busy(ix: Vector2i, me: Vehicle) -> bool:
	var c := WorldLayout.inter_pos(ix)
	for v in moving:
		if is_instance_valid(v) and v != me and v.speed > 1.0 and G.dist2(v.global_position, c) < 9.0:
			return true
	var pv = G.player.vehicle if G.player else null
	if pv != null and pv.speed > 2.0 and G.dist2(pv.global_position, c) < 10.0:
		return true
	return false


func _process(delta: float) -> void:
	sig_time += delta
	_update_signals()
	if G.player == null:
		return
	var pp: Vector3 = G.player.global_position_now()
	var cam := get_viewport().get_camera_3d()
	clean_t -= delta
	if clean_t <= 0.0:
		clean_t = 1.0
		_cleanup(pp, cam)
		_refresh_persistent()
		_yield_to_sirens()
	if not enabled or not G.flags.traffic:
		return
	park_t -= delta
	if park_t <= 0.0:
		park_t = 0.6
		_update_parked(pp, cam)
	spawn_t -= delta
	if spawn_t <= 0.0:
		spawn_t = 0.45
		var density: float = float(G.settings.density) * (lerpf(1.0, 0.6, G.timew.night) if G.timew else 1.0)
		if moving.size() < int(cap * density):
			_spawn_moving(pp, cam)


func _update_signals() -> void:
	var ax := WorldLayout.signal_state(Vector2i(3, 0), true, sig_time)
	var az := WorldLayout.signal_state(Vector2i(3, 0), false, sig_time)
	var key := "%d%d" % [ax, az]
	if key == _sig_state:
		return
	_sig_state = key
	for grp in [["A", ax], ["B", az]]:
		var names := ["TrafficGreen", "TrafficYellow", "TrafficRed"]
		for i in 3:
			var mn: String = names[i] + grp[0]
			if Assets.mats.has(mn):
				var m: StandardMaterial3D = Assets.mats[mn]
				m.emission_enabled = true
				m.emission_energy_multiplier = 6.0 if i == grp[1] else 0.03


func _cleanup(pp: Vector3, cam: Camera3D) -> void:
	var i := moving.size() - 1
	while i >= 0:
		var raw = moving[i]
		if not is_instance_valid(raw):
			moving.remove_at(i)
			i -= 1
			continue
		var v: Vehicle = raw
		var d := v.global_position.distance_to(pp)
		var vis := cam != null and cam.is_position_in_frustum(v.global_position)
		var player_in: bool = v.has_player()
		var stale := (v.ai == null and v.driver == null) or v.flooded
		if player_in or v.owned:
			moving.remove_at(i)
			if not get_tree().get_nodes_in_group("loose").has(v):
				v.add_to_group("loose")
		elif d > 210.0 or (d > 125.0 and not vis) or (v.dead and v.wreck_timer <= 0.0 and (d > 60.0 or not vis)) or v.global_position.y < -30.0:
			_despawn(v)
			moving.remove_at(i)
		elif stale and d > 90.0 and not vis:
			_despawn(v)
			moving.remove_at(i)
		i -= 1
	for v2 in get_tree().get_nodes_in_group("loose"):
		var lv := v2 as Vehicle
		if lv == null or lv.has_player() or lv.owned or lv.no_despawn or lv == G.player.last_vehicle:
			continue
		var d2 := lv.global_position.distance_to(pp)
		if d2 > 230.0 or (lv.dead and lv.wreck_timer <= 0.0 and d2 > 70.0) or (lv.flooded and d2 > 90.0):
			_despawn(lv)


func _despawn(v: Vehicle) -> void:
	for o in v.occupants():
		if is_instance_valid(o) and not G.is_player(o):
			o.queue_free()
	if G.world:
		for s in G.world.parking:
			if s.veh == v:
				s.veh = null
	v.queue_free()


func _yield_to_sirens() -> void:
	for v in get_tree().get_nodes_in_group("vehicles"):
		var e := v as Vehicle
		if e == null or not e.siren or e.speed < 5.0:
			continue
		for m in moving:
			if not is_instance_valid(m) or m == e or m.ai == null:
				continue
			var rel: Vector3 = m.global_position - e.global_position
			if rel.length() < 34.0 and rel.normalized().dot(e.linear_velocity.normalized()) > 0.6:
				m.ai.yielding = 2.5


func spawn_traffic_vehicle(vid: String, a: Vector2i, b: Vector2i, lane: int, t: float, driver_kind: String = "civ") -> Vehicle:
	var ai := VehicleAI.new()
	ai.manager = self
	var xf := ai.place_on_lane(a, b, lane, t)
	var v := VehicleFactory.spawn(vid, xf.origin, xf.basis.get_euler().y) as Car
	if v == null:
		ai.free()
		return null
	ai.attach(v)
	if G.peds:
		var drv: NPC = G.peds.make_driver(driver_kind)
		drv.enter_vehicle(v, 0)
		if vid == "taxi" or (v.seats.size() > 1 and G.rng.randf() < 0.25 and driver_kind == "civ"):
			pass
	v.linear_velocity = -xf.basis.z * 6.0
	moving.append(v)
	return v


func _spawn_moving(pp: Vector3, cam: Camera3D) -> void:
	for attempt in 8:
		var a := Vector2i(G.rng.randi() % WorldLayout.NX, G.rng.randi() % WorldLayout.NZ)
		var nb := WorldLayout.neighbors(a)
		var b: Vector2i = nb[G.rng.randi() % nb.size()]
		var lane := G.rng.randi() % WorldLayout.seg_lanes(a, b)
		var ends := WorldLayout.lane_ends(a, b, lane)
		var t := G.rng.randf_range(0.1, 0.8)
		var p: Vector3 = (ends[0] as Vector3).lerp(ends[1], t)
		var d := p.distance_to(pp)
		if d < 55.0 or d > 150.0:
			continue
		if cam != null and cam.is_position_in_frustum(p + Vector3(0, 1, 0)) and d < 110.0:
			continue
		var blocked := false
		for v in get_tree().get_nodes_in_group("vehicles"):
			if (v as Node3D).global_position.distance_to(p) < 13.0:
				blocked = true
				break
		if blocked:
			continue
		var vid := pick_vehicle()
		var kind := "civ"
		if G.rng.randf() < 0.06 and (G.wanted == null or G.wanted.level == 0):
			vid = "police"
			kind = "cop"
		spawn_traffic_vehicle(vid, a, b, lane, t, kind)
		return


func _update_parked(pp: Vector3, cam: Camera3D) -> void:
	if G.world == null:
		return
	var budget := 2
	for s in G.world.parking:
		var sp: Vector3 = s.pos
		var d := sp.distance_to(pp)
		var v = s.veh
		if v != null and not is_instance_valid(v):
			s.veh = null
			v = null
		if v != null:
			if v.has_player() or v.owned or v.driver != null or v.global_position.distance_to(sp) > 6.0:
				if not v.is_in_group("loose"):
					v.add_to_group("loose")
				s.veh = null
				s["cool"] = 90.0
			elif d > 150.0:
				v.queue_free()
				s.veh = null
			continue
		if s.has("cool") and float(s.cool) > 0.0:
			s.cool = float(s.cool) - 0.6
			continue
		if budget <= 0 or d > 110.0 or d < 40.0:
			continue
		if not s.has("roll"):
			s["roll"] = G.rng.randf()
		var chance := 0.38 if s.tag == "street" else 0.7
		if s.tag in ["police", "ambulance"]:
			chance = 1.0
		if float(s.roll) > chance:
			continue
		if cam != null and cam.is_position_in_frustum(sp + Vector3(0, 1, 0)) and d < 80.0:
			continue
		var vid := pick_vehicle()
		match String(s.tag):
			"police": vid = "police" if G.rng.randf() < 0.85 else "swat"
			"ambulance": vid = "ambulance" if G.rng.randf() < 0.7 else "firetruck"
			"ind": vid = ["truck", "van", "pickup", "van"][G.rng.randi() % 4]
			"res": vid = ["compact", "sedan", "suv", "pickup", "motorcycle", "bicycle", "muscle"][G.rng.randi() % 7]
			"lot": vid = pick_vehicle() if G.rng.randf() < 0.85 else "motorcycle"
		if vid in ["truck", "firetruck"] and s.tag == "street":
			vid = "sedan"
		var nv := VehicleFactory.spawn(vid, sp + Vector3(0, 0.35, 0), float(s.yaw))
		nv.handbrake = true
		nv.brake = 1.0
		s.veh = nv
		budget -= 1


func clear_traffic() -> void:
	for v in moving:
		if is_instance_valid(v) and not v.has_player():
			_despawn(v)
	moving.clear()
