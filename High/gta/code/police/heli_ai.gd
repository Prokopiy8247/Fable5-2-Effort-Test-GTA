class_name HeliAI
extends RefCounted
## Police helicopter pilot: orbits the suspect (or last known position), spotlight at night, gunner at 4+ stars.

var target = null
var leave := false
var _angle := 0.0
var _spot: SpotLight3D
var _burst_t := 4.0
var _shots := 0
var _shot_cd := 0.0
var _alt := 95.0
var _alt_t := 0.0


func update(v: Vehicle, delta: float) -> void:
	var p = target
	if p == null or not is_instance_valid(p):
		return
	_angle += delta * 0.28
	var focus: Vector3 = p.global_position if Wanted.seen else Wanted.last_known
	var goal := focus + Vector3(cos(_angle), 0, sin(_angle)) * 30.0
	if leave or Wanted.level == 0:
		goal = v.global_position + (v.global_position - focus).normalized() * 200.0
		if v.global_position.distance_to(p.global_position) > 300.0:
			v.queue_free()
			return
	_alt_t -= delta
	if _alt_t <= 0.0:
		_alt_t = 0.5
		var hd := Vector2(goal.x - v.global_position.x, goal.z - v.global_position.z).length()
		var gy := 0.0
		for off in [Vector3.ZERO, v.linear_velocity * 1.5]:
			var q: Vector3 = v.global_position + off
			var hit := Game.ray(Vector3(q.x, 300.0, q.z), Vector3(q.x, -5.0, q.z), Game.L_WORLD, [v])
			if not hit.is_empty():
				gy = maxf(gy, hit.position.y)
		_alt = maxf(gy + 26.0, focus.y + 36.0) if hd < 70.0 else 95.0
		if leave:
			_alt = 120.0
	var to := goal - v.global_position
	var fwd := -v.global_basis.z
	var right := v.global_basis.x
	var hv := Vector3(v.linear_velocity.x, 0, v.linear_velocity.z)
	var want := Vector3(to.x, 0, to.z).limit_length(30.0)
	var acc := (want - hv)
	v.pitch_in = clampf(acc.dot(Vector3(fwd.x, 0, fwd.z).normalized()) * 0.09, -1.0, 1.0)
	v.roll_in = clampf(acc.dot(Vector3(right.x, 0, right.z).normalized()) * 0.09, -1.0, 1.0)
	v.lift_in = clampf((_alt - v.global_position.y) * 0.12 - v.linear_velocity.y * 0.15, -1.0, 1.0)
	var look := focus - v.global_position
	var yaw_err := angle_difference(v.global_rotation.y, atan2(-look.x, -look.z))
	v.yaw_in = clampf(-yaw_err * 1.2, -1.0, 1.0)
	# spotlight
	var night: float = Game.daynight.night if Game.daynight else 0.0
	if night > 0.3 and _spot == null:
		_spot = SpotLight3D.new()
		_spot.spot_range = 190.0
		_spot.spot_angle = 9.0
		_spot.light_energy = 24.0
		_spot.light_color = Color(0.9, 0.95, 1.0)
		_spot.shadow_enabled = false
		v.add_child(_spot)
		_spot.position = Vector3(0, 0.5, -2.3)
	if _spot:
		_spot.visible = night > 0.3 and not v.dead
		if _spot.visible:
			_spot.look_at(focus + Vector3.UP, Vector3.UP)
	# door gunner
	if Wanted.level >= 4 and Wanted.seen and not leave and not v.dead:
		_burst_t -= delta
		_shot_cd -= delta
		if _burst_t <= 0.0 and _shots == 0:
			_shots = 5
			_burst_t = Game.rng.randf_range(2.5, 4.5)
		if _shots > 0 and _shot_cd <= 0.0:
			_shots -= 1
			_shot_cd = 0.12
			var from: Vector3 = v.global_position + Vector3.DOWN * 0.8
			var tp: Vector3 = p.center()
			var hit := Game.rng.randf() < 0.14
			var end := tp
			if hit:
				if p.in_vehicle():
					p.vehicle.damage(22.0, tp, v)
				else:
					p.damage(8.0, from, v, "bullet")
			else:
				end = tp + Vector3(Game.rng.randf_range(-3, 3), 0, Game.rng.randf_range(-3, 3))
				end.y = maxf(City.terrain_height(end.x, end.z), 0.0)
				Fx.impact(end, Vector3.UP, "concrete")
			Fx.tracer(from, end)
			Sfx.play3d("shot_rifle", from, 0.0, 1.0, 260.0)
