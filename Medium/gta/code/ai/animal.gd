extends CharacterBody3D
## Lightweight wildlife: grazers that flee, park dogs, gulls, fish schools and sharks that hunt swimmers.

var kind := "deer"
var zone := Rect2()
var yr := Vector2.ZERO
var home := Vector3.ZERO
var model: Node3D
var legs: Array = []
var tail: Node3D
var wings: Array = []
var health := 40.0
var dead := false
var state := "wander"
var goal := Vector3.ZERO
var t := 0.0
var ph := 0.0
var speed_walk := 1.2
var speed_run := 8.0
var flying := false
var aquatic := false
var _bite := 0.0
var _tick := 0


func setup(k: String, z: Rect2, y_range: Vector2) -> void:
	kind = k
	zone = z
	yr = y_range
	home = global_position
	model = G.model("wildlife/" + k)
	add_child(model)
	for n in ["_Leg_FL", "_Leg_RR", "_Leg_FR", "_Leg_RL"]:
		var l = G.part(model, n)
		if l:
			legs.append(l)
	tail = G.part(model, "_Tail")
	for n in ["_Wing_L", "_Wing_R"]:
		var w = G.part(model, n)
		if w:
			wings.append(w)
	collision_layer = G.L_CHAR
	collision_mask = G.L_WORLD
	var cs = CollisionShape3D.new()
	var sh = SphereShape3D.new()
	match k:
		"deer":
			sh.radius = 0.55; health = 60.0; speed_walk = 1.1; speed_run = 9.0
		"cow":
			sh.radius = 0.75; health = 160.0; speed_walk = 0.7; speed_run = 3.5
		"dog":
			sh.radius = 0.35; health = 40.0; speed_walk = 1.8; speed_run = 7.0
		"rabbit":
			sh.radius = 0.18; health = 10.0; speed_walk = 1.0; speed_run = 7.5
		"seagull":
			sh.radius = 0.25; health = 8.0; speed_walk = 7.0; speed_run = 11.0; flying = true
		"fish":
			sh.radius = 0.15; health = 5.0; speed_walk = 1.4; speed_run = 5.0; aquatic = true
		"shark":
			sh.radius = 0.6; health = 260.0; speed_walk = 2.6; speed_run = 7.5; aquatic = true
	cs.shape = sh
	cs.position.y = sh.radius if not (flying or aquatic) else 0.0
	add_child(cs)
	if flying or aquatic:
		collision_mask = 0
	_new_goal()
	t = G.rng.randf() * 5.0


func _new_goal() -> void:
	goal = Vector3(G.rng.randf_range(zone.position.x, zone.end.x), global_position.y, G.rng.randf_range(zone.position.y, zone.end.y))
	if flying or aquatic:
		goal.y = G.rng.randf_range(yr.x, yr.y)


func scare(from: Vector3) -> void:
	if dead or kind in ["shark", "cow"]:
		return
	state = "flee"
	t = 0.0
	var away = G.flat(global_position - from).normalized()
	goal = global_position + away * 30.0
	goal.x = clamp(goal.x, zone.position.x, zone.end.x)
	goal.z = clamp(goal.z, zone.position.y, zone.end.y)
	if flying or aquatic:
		goal.y = clamp(global_position.y + G.rng.randf_range(-1, 3), yr.x, yr.y)


func damage(amount: float, _from = null, _pos := Vector3.ZERO, _kind := "bullet") -> void:
	if dead:
		return
	health -= amount
	if health <= 0.0:
		dead = true
		state = "dead"
		t = 0.0
		collision_layer = 0
		model.rotation.z = PI / 2 if not aquatic else PI
	else:
		scare(_pos)


func hit_by_vehicle(_veh, vel: Vector3) -> void:
	if vel.length() > 4.0:
		damage(vel.length() * 8.0, null, global_position - vel)
		velocity = vel * 0.7 + Vector3(0, 3, 0)


func _physics_process(dt: float) -> void:
	_tick += 1
	t += dt
	if dead:
		if not (flying or aquatic):
			velocity.y -= 14.0 * dt
			velocity.x = move_toward(velocity.x, 0, dt * 6.0)
			velocity.z = move_toward(velocity.z, 0, dt * 6.0)
			move_and_slide()
		elif flying:
			global_position.y = max(0.3, global_position.y - 9.0 * dt)
		if t > 40.0:
			queue_free()
		return
	var p = G.player
	var pp: Vector3 = p.global_position if p else Vector3.ZERO
	var pd = global_position.distance_to(pp)
	var sp = speed_walk
	match kind:
		"shark":
			var swimmer: bool = p != null and p.state == "swim" and pd < 26.0 and zone.grow(25.0).has_point(Vector2(pp.x, pp.z))
			if swimmer:
				state = "hunt"
				goal = pp + Vector3(0, 0.6, 0)
				sp = speed_run
				_bite -= dt
				if pd < 2.2 and _bite <= 0.0:
					_bite = 1.8
					p.damage(24.0, self, global_position, "bite")
					G.fx.burst("flesh", pp + Vector3(0, 1, 0))
					G.notify("Shark attack!", 2.0)
			elif state == "hunt":
				state = "wander"
				_new_goal()
		"deer", "rabbit", "fish":
			if state != "flee" and pd < (14.0 if kind != "fish" else 4.0) * (p.detect_mult if p and kind != "fish" else 1.0):
				scare(pp)
		"dog":
			if state == "wander" and pd < 10.0 and p and p.state == "ground" and int(t) % 9 < 5:
				goal = pp + Vector3(1.5, 0, 1.5)
	if state == "flee":
		sp = speed_run
		if t > 6.0:
			state = "wander"
			_new_goal()
	var to = goal - global_position
	if not (flying or aquatic):
		to.y = 0.0
	if to.length() < 1.2 or (state == "wander" and t > 14.0):
		if state == "wander" and not (flying or aquatic) and G.rng.randf() < 0.6 and t < 14.0:
			# graze / idle
			velocity.x = 0.0
			velocity.z = 0.0
			if t > 5.0:
				t = 0.0
				_new_goal()
		else:
			t = 0.0
			_new_goal()
		to = Vector3.ZERO
	var v = to.normalized() * sp if to.length() > 0.01 else Vector3.ZERO
	if flying or aquatic:
		velocity = velocity.lerp(v, clamp(dt * 1.5, 0.0, 1.0))
		global_position += velocity * dt
		if aquatic:
			global_position.y = min(global_position.y, G.WATER_Y - 0.8)
	else:
		velocity.x = move_toward(velocity.x, v.x, dt * 10.0)
		velocity.z = move_toward(velocity.z, v.z, dt * 10.0)
		velocity.y = velocity.y - 14.0 * dt if not is_on_floor() else -0.5
		move_and_slide()
	var hv = G.flat(velocity)
	if hv.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(-hv.x, -hv.z), clamp(dt * 5.0, 0.0, 1.0))
	if pd > 90.0:
		return
	ph += dt * (4.0 + hv.length() * 2.2)
	var amp: float = clamp(hv.length() * 0.25, 0.0, 0.8)
	for i in legs.size():
		legs[i].rotation.x = sin(ph + (PI if i >= 2 else 0.0)) * amp
	if tail:
		tail.rotation.y = sin(ph * (1.0 if kind == "shark" else 2.5)) * 0.4
	for i in wings.size():
		wings[i].rotation.z = sin(ph * 1.5) * 0.7 * (1.0 if i == 0 else -1.0)
	if flying:
		model.rotation.z = lerpf(model.rotation.z, clamp(-velocity.cross(Vector3.UP).dot(to.normalized()) * 0.1, -0.6, 0.6), dt * 2.0)
	if kind == "rabbit" and hv.length() > 0.5:
		model.position.y = abs(sin(ph * 0.8)) * 0.18
