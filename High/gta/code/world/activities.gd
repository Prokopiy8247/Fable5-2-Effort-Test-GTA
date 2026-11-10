class_name Activities
extends Node3D
## Optional free-roam activities, started only by deliberate interaction: shooting range, time trial, stunt jumps,
## precision parachute landing. No story, no progression gates.

# ---- shooting range
var range_pos := Vector3(232, 0.2, 60)
var range_active := false
var range_time := 0.0
var range_score := 0
var range_hits := 0
var range_ammo_start := 0
var targets: Array = []        # {body, node, up, t}
# ---- time trial
var trial_points: Array = []
var trial_active := false
var trial_idx := 0
var trial_time := 0.0
var ring: MeshInstance3D
# ---- stunt jumps
var ramps: Array = []          # {pos, dir, done}
var _jump := {}                # tracking state
# ---- parachute target
var chute_target := Vector3(-140, 0.3, 195.5)


func setup() -> void:
	# shooting range lane: targets 14..38 m down-range (towards +x)
	for i in range(9):
		var pos := range_pos + Vector3(14.0 + (i % 3) * 11.0, 0.0, -8.0 + (i / 3) * 8.0 + (i % 3) * 1.5)
		var body := StaticBody3D.new()
		body.collision_layer = Game.L_PROP
		body.collision_mask = 0
		var node := Assets.inst("target")
		node.rotation.y = -PI * 0.5
		body.add_child(node)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.12, 0.95, 0.95)
		cs.shape = bs
		cs.position.y = 1.55
		body.add_child(cs)
		add_child(body)
		body.global_position = pos
		body.set_meta("range_target", i)
		targets.append({"body": body, "node": node, "up": false, "t": 0.0})
		_set_target(i, false)
	Game.world.add_interact(null, range_pos, 3.0, "E  Shooting range - 45 second round ($20)", start_range, func(): return not range_active)
	# time trial loop through the grid
	for p in [Vector3(-100, 0, 10), Vector3(0, 0, 10), Vector3(100, 0, 10), Vector3(100, 0, -90), Vector3(100, 0, -190), Vector3(0, 0, -190),
			Vector3(-100, 0, -190), Vector3(-200, 0, -190), Vector3(-200, 0, -90), Vector3(-200, 0, 10), Vector3(-200, 0, 110), Vector3(-100, 0, 110)]:
		trial_points.append(p)
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 4.2
	tm.outer_radius = 5.0
	tm.rings = 24
	tm.ring_segments = 6
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.8, 0.2, 0.6)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.75, 0.2)
	m.emission_energy_multiplier = 2.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = m
	ring.rotation.x = PI * 0.5
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	Game.world.add_interact(null, Vector3(-112, 0.3, 104), 5.0, "E  City Loop time trial (bring a vehicle)", start_trial,
		func(): return not trial_active and Game.player.in_vehicle(), true)


func _set_target(i: int, up: bool) -> void:
	var t: Dictionary = targets[i]
	t.up = up
	t.node.visible = up
	t.body.collision_layer = Game.L_PROP if up else 0
	t.t = 0.0


# ------------------------------------------------------------------ shooting range
func start_range() -> void:
	if range_active or not Game.spend(20):
		return
	var p = Game.player
	if p.inv.def().kind != "hitscan":
		Game.say("Equip a firearm first", Color(1, 0.6, 0.5))
		Game.add_money(20)
		return
	range_active = true
	range_time = 45.0
	range_score = 0
	range_hits = 0
	range_ammo_start = _ammo_total()
	Wanted.enabled = false
	for i in range(3):
		_pop_random()
	Game.banner("SHOOTING RANGE", "Hit the targets - 45 seconds", Color(1.0, 0.85, 0.3))


func _ammo_total() -> int:
	var n := 0
	for id in Game.player.inv.owned:
		n += Game.player.inv.total_ammo(id)
	return n


func _pop_random() -> void:
	var down := []
	for i in range(targets.size()):
		if not targets[i].up:
			down.append(i)
	if not down.is_empty():
		_set_target(down[Game.rng.randi() % down.size()], true)


func on_bullet(collider, pos: Vector3, attacker) -> void:
	if not range_active or collider == null or not (collider is Node) or not collider.has_meta("range_target") or attacker != Game.player:
		return
	var i: int = collider.get_meta("range_target")
	var c: Vector3 = collider.global_position + Vector3(0, 1.55, 0)
	var off := Vector2(pos.z - c.z, pos.y - c.y).length()
	var pts := 10
	if off < 0.1:
		pts = 25
	elif off < 0.22:
		pts = 15
	range_score += pts
	range_hits += 1
	Game.say("+%d" % pts, Color(1.0, 0.9, 0.4))
	Sfx.play("tick", -2.0, 1.0 + pts * 0.02)
	_set_target(i, false)
	_pop_random()
	Game.skill_up("shooting", 0.5)


func _end_range() -> void:
	range_active = false
	Wanted.enabled = true
	for i in range(targets.size()):
		_set_target(i, false)
	var shots := maxi(range_ammo_start - _ammo_total(), 1)
	var acc := clampf(float(range_hits) / float(shots), 0.0, 1.0)
	var reward := int(range_score * 0.6 * (0.5 + acc))
	Game.add_money(reward)
	Game.stats.best_range_score = maxi(int(Game.stats.best_range_score), range_score)
	Game.banner("RANGE COMPLETE", "Score %d   Accuracy %d%%   +$%d" % [range_score, int(acc * 100.0), reward], Color(0.6, 1.0, 0.6))
	Sfx.play("sting_good", -4.0)


# ------------------------------------------------------------------ time trial
func start_trial() -> void:
	if trial_active or not Game.player.in_vehicle():
		return
	trial_active = true
	trial_idx = 0
	trial_time = 0.0
	ring.visible = true
	_place_ring()
	Game.banner("CITY LOOP", "Drive through the rings - best: %s" % _fmt(float(Game.stats.best_trial)), Color(1.0, 0.85, 0.3))


func _fmt(t: float) -> String:
	if t <= 0.0:
		return "--:--"
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]


func _place_ring() -> void:
	var p: Vector3 = trial_points[trial_idx]
	ring.global_position = p + Vector3.UP * 3.0
	Game.waypoint = p


func _trial(delta: float) -> void:
	trial_time += delta
	var p = Game.player
	if not p.in_vehicle():
		if trial_time > 3.0:
			trial_active = false
			ring.visible = false
			Game.waypoint = null
			Game.say("Time trial cancelled", Color(1, 0.6, 0.5))
		return
	ring.rotation.z += delta * 1.5
	var tp: Vector3 = trial_points[trial_idx]
	if Vector2(p.global_position.x - tp.x, p.global_position.z - tp.z).length() < 9.0:
		trial_idx += 1
		Sfx.play("pickup", -4.0)
		if trial_idx >= trial_points.size():
			trial_active = false
			ring.visible = false
			Game.waypoint = null
			var best := float(Game.stats.best_trial)
			var new_best := best <= 0.0 or trial_time < best
			if new_best:
				Game.stats.best_trial = trial_time
			var reward := 150 + (350 if trial_time < 75.0 else 0) + (200 if new_best else 0)
			Game.add_money(reward)
			Game.banner("LOOP COMPLETE", "%s%s   +$%d" % [_fmt(trial_time), "  NEW BEST" if new_best else "", reward], Color(0.6, 1.0, 0.6))
			Sfx.play("sting_good", -4.0)
			Game.skill_up("driving", 3.0)
		else:
			_place_ring()


# ------------------------------------------------------------------ stunt jumps
func add_ramp(pos: Vector3, yaw: float) -> void:
	ramps.append({"pos": pos, "dir": Vector3(-sin(yaw), 0, -cos(yaw)), "id": ramps.size()})


func _stunts(delta: float) -> void:
	var p = Game.player
	if not p.in_vehicle() or p.vehicle.is_air() or p.vehicle.def.kind == "boat":
		_jump = {}
		return
	var v: Vehicle = p.vehicle
	if _jump.is_empty():
		for r in ramps:
			if v.global_position.distance_to(r.pos + Vector3.UP * 1.5) < 5.5 and v.linear_velocity.dot(r.dir) > 9.0:
				_jump = {"ramp": r, "state": "ramp", "air": 0.0, "from": v.global_position, "t": 0.0}
				break
		return
	_jump.t += delta
	if _jump.state == "ramp":
		if v.grounded_wheels == 0:
			_jump.state = "air"
			_jump.from = v.global_position
		elif _jump.t > 3.0:
			_jump = {}
	elif _jump.state == "air":
		_jump.air += delta
		if v.grounded_wheels >= 2 or v.dead:
			var dist := Vector2(v.global_position.x - _jump.from.x, v.global_position.z - _jump.from.z).length()
			var ok: bool = _jump.air > 0.9 and dist > 9.0 and not v.dead and v.global_basis.y.dot(Vector3.UP) > 0.5
			if ok:
				var id: int = _jump.ramp.id
				var first: bool = not Game.stats.stunts_found.has(id)
				if first:
					Game.stats.stunts_found.append(id)
					Game.stats.stunt_jumps = Game.stats.stunts_found.size()
					Game.add_money(250)
				Game.banner("STUNT JUMP", "%.0f m   %.1f s airtime%s" % [dist, _jump.air, "   +$250" if first else ""], Color(1.0, 0.6, 0.9))
				Sfx.play("sting_good", -4.0)
				Game.skill_up("driving", 2.0)
			elif _jump.air > 0.6:
				Game.say("Stunt failed", Color(1, 0.6, 0.5))
			_jump = {}


func on_chute_landed(pos: Vector3) -> void:
	var d := Vector2(pos.x - chute_target.x, pos.z - chute_target.z).length()
	if d < 14.0:
		var reward := int(300.0 * (1.0 - d / 14.0)) + 50
		Game.add_money(reward)
		Game.banner("PRECISION LANDING", "%.1f m from the bullseye   +$%d" % [d, reward], Color(0.6, 1.0, 0.6))
		Sfx.play("sting_good", -4.0)


func _physics_process(delta: float) -> void:
	if Game.player == null:
		return
	if range_active:
		range_time -= delta
		for i in range(targets.size()):
			var t: Dictionary = targets[i]
			if t.up:
				t.t += delta
				if t.t > 4.0:
					_set_target(i, false)
					_pop_random()
		if range_time <= 0.0 or Game.player.global_position.distance_to(range_pos) > 14.0:
			_end_range()
	if trial_active:
		_trial(delta)
	_stunts(delta)
