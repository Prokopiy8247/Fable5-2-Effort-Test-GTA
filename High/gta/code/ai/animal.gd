class_name Animal
extends AnimatableBody3D
## Lightweight wildlife agent (deer, boar, cow, dog, seagull, fish, shark) with region-appropriate behaviour.

var species := "deer"
var home := Vector3.ZERO
var home_r := 30.0
var model: Node3D
var legs: Array = []
var wings: Array = []
var tail: Node3D
var head: Node3D
var health := 40.0
var dead := false
var state := "idle"      # idle | wander | flee | attack
var goal := Vector3.ZERO
var speed := 0.0
var _t := 0.0
var _phase := 0.0
var _gy := 0.0
var _gy_t := 0.0
var _bite_cd := 0.0
var _dead_t := 0.0
var _angle := 0.0
var _alt := 14.0
var yaw := 0.0

const SPEC := {
	"deer": {"asset": "ani_deer", "hp": 45.0, "walk": 1.6, "run": 9.0, "size": Vector3(0.5, 1.2, 1.4), "ground": true, "shy": 22.0},
	"boar": {"asset": "ani_boar", "hp": 70.0, "walk": 1.3, "run": 7.0, "size": Vector3(0.5, 0.8, 1.2), "ground": true, "shy": 0.0, "aggro": 7.0},
	"cow": {"asset": "ani_cow", "hp": 120.0, "walk": 0.8, "run": 3.5, "size": Vector3(0.8, 1.4, 2.0), "ground": true, "shy": 5.0},
	"dog": {"asset": "ani_dog", "hp": 30.0, "walk": 2.0, "run": 7.5, "size": Vector3(0.35, 0.6, 0.8), "ground": true, "shy": 0.0},
	"seagull": {"asset": "ani_seagull", "hp": 5.0, "walk": 7.0, "run": 11.0, "size": Vector3(0.6, 0.3, 0.6), "ground": false, "shy": 0.0},
	"fish": {"asset": "ani_fish", "hp": 3.0, "walk": 1.4, "run": 5.0, "size": Vector3(0.3, 0.3, 0.6), "ground": false, "shy": 5.0},
	"shark": {"asset": "ani_shark", "hp": 180.0, "walk": 2.6, "run": 6.5, "size": Vector3(0.9, 0.9, 3.2), "ground": false, "shy": 0.0, "aggro": 20.0},
}


static func spawn(p_species: String, pos: Vector3, p_home: Vector3, radius: float) -> Animal:
	var a := Animal.new()
	a.species = p_species
	a.home = p_home
	a.home_r = radius
	Game.world.npc_root.add_child(a)
	a.global_position = pos
	return a


func _ready() -> void:
	var sp: Dictionary = SPEC[species]
	sync_to_physics = false
	collision_layer = Game.L_CHAR
	collision_mask = 0
	health = sp.hp
	model = Assets.inst(sp.asset)
	add_child(model)
	for n in Assets.find_all(model, "_leg_"):
		legs.append(n)
	for n in Assets.find_all(model, "_wing_"):
		wings.append(n)
	tail = Assets.find(model, "_tail")
	head = Assets.find(model, "_head")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sp.size
	cs.shape = bs
	cs.position.y = sp.size.y * 0.5 if sp.ground else 0.0
	add_child(cs)
	set_meta("animal", self)
	_t = Game.rng.randf() * 3.0
	_angle = Game.rng.randf() * TAU
	_alt = Game.rng.randf_range(10.0, 24.0)
	yaw = Game.rng.randf() * TAU
	Game.noise_event.connect(_on_noise)
	tree_exiting.connect(func():
		if Game.noise_event.is_connected(_on_noise):
			Game.noise_event.disconnect(_on_noise))


func _on_noise(pos: Vector3, radius: float, kind: String) -> void:
	if dead or kind == "steps" or species == "shark" or species == "fish":
		return
	if global_position.distance_to(pos) < minf(radius, 70.0):
		_flee_from(pos)


func _flee_from(pos: Vector3) -> void:
	state = "flee"
	_t = Game.rng.randf_range(4.0, 7.0)
	var away := global_position - pos
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	goal = global_position + away.normalized().rotated(Vector3.UP, Game.rng.randf_range(-0.6, 0.6)) * 30.0
	if species == "dog" and Game.rng.randf() < 0.6:
		Sfx.play3d("bark", global_position, -4.0, Game.rng.randf_range(0.9, 1.2), 40.0)


func hit(dmg: float, attacker) -> void:
	if dead:
		return
	health -= dmg
	Fx.blood(global_position + Vector3.UP * 0.5)
	if health <= 0.0:
		dead = true
		collision_layer = 0
		_dead_t = 0.0
		if species == "shark" and attacker == Game.player:
			Game.say("Shark killed", Color(0.6, 1.0, 0.6))
	else:
		var sp: Dictionary = SPEC[species]
		if sp.get("aggro", 0.0) > 0.0 and attacker == Game.player:
			state = "attack"
			_t = 12.0
		elif attacker != null and is_instance_valid(attacker):
			_flee_from(attacker.global_position)


func _physics_process(delta: float) -> void:
	var p = Game.player
	if p == null:
		return
	var sp: Dictionary = SPEC[species]
	if dead:
		_dead_t += delta
		model.rotation.z = lerpf(model.rotation.z, 1.5 if sp.ground else 3.1, clampf(delta * 5.0, 0.0, 1.0))
		if not sp.ground and species != "seagull":
			global_position.y = move_toward(global_position.y, Game.WATER_Y - 0.2, delta * 0.6)
		elif species == "seagull":
			global_position.y = move_toward(global_position.y, maxf(City.terrain_height(global_position.x, global_position.z), Game.WATER_Y), delta * 12.0)
		if _dead_t > 30.0:
			queue_free()
		return
	var ppos: Vector3 = p.global_position
	var dist := global_position.distance_to(ppos)
	if dist > 130.0 and Engine.get_physics_frames() % 4 != 0:
		return
	_t -= delta
	_bite_cd -= delta
	match species:
		"seagull":
			_bird(delta)
		"fish", "shark":
			_swim(delta, p, dist, sp)
		_:
			_ground(delta, p, dist, sp)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 6.0, 0.0, 1.0))
	# limb animation
	_phase += speed * delta * (5.0 if sp.ground else 3.0)
	for i in range(legs.size()):
		legs[i].rotation.x = sin(_phase + (PI if (i == 1 or i == 2) else 0.0)) * clampf(speed * 0.25, 0.0, 0.7)
	if head and sp.ground:
		head.rotation.x = lerpf(head.rotation.x, 0.9 if (state == "idle" and species in ["deer", "cow"] and fmod(_t, 6.0) < 3.0) else 0.0, clampf(delta * 3.0, 0.0, 1.0))
	for i in range(wings.size()):
		wings[i].rotation.z = sin(Time.get_ticks_msec() * 0.012) * 0.7 * (1.0 if i == 0 else -1.0)
	if tail:
		tail.rotation.y = sin(Time.get_ticks_msec() * 0.008 * (1.0 + speed * 0.3)) * 0.5


func _ground(delta: float, p, dist: float, sp: Dictionary) -> void:
	var shy: float = sp.shy
	if state != "flee" and state != "attack" and shy > 0.0 and dist < shy * (0.5 if p.crouching else 1.0) and not p.in_vehicle():
		_flee_from(p.global_position)
	if state != "flee" and p.in_vehicle() and dist < 14.0 and absf(p.vehicle.speed) > 4.0:
		_flee_from(p.global_position)
	var aggro: float = sp.get("aggro", 0.0)
	if species == "boar" and state != "attack" and aggro > 0.0 and dist < aggro and not p.in_vehicle() and p.alive():
		state = "attack"
		_t = 8.0
	if state == "attack":
		goal = p.global_position
		if _t <= 0.0 or not p.alive() or p.in_vehicle():
			state = "idle"
			_t = 2.0
		elif dist < 1.5 and _bite_cd <= 0.0:
			_bite_cd = 1.6
			p.damage(12.0, global_position, null, "melee")
			if p.alive():
				p.knockdown((p.global_position - global_position).normalized() * 5.0 + Vector3.UP * 2.5)
			_flee_from(p.global_position)
	elif state == "idle":
		if _t <= 0.0:
			state = "wander"
			_t = Game.rng.randf_range(4.0, 9.0)
			var a := Game.rng.randf() * TAU
			goal = home + Vector3(cos(a), 0, sin(a)) * Game.rng.randf_range(2.0, home_r)
	elif _t <= 0.0:
		state = "idle"
		_t = Game.rng.randf_range(3.0, 9.0)
	var target_speed := 0.0
	if state == "wander":
		target_speed = sp.walk
	elif state == "flee" or state == "attack":
		target_speed = sp.run
	var to := goal - global_position
	to.y = 0.0
	if to.length() < 1.2 and state != "attack":
		target_speed = 0.0
		if state == "wander":
			state = "idle"
			_t = Game.rng.randf_range(3.0, 8.0)
	speed = move_toward(speed, target_speed, delta * 10.0)
	if speed > 0.05 and to.length() > 0.2:
		var dir := to.normalized()
		yaw = atan2(-dir.x, -dir.z)
		var np := global_position + dir * speed * delta
		var th := City.terrain_height(np.x, np.z)
		if th > Game.WATER_Y + 0.1:
			global_position.x = np.x
			global_position.z = np.z
		else:
			state = "idle"
	_gy_t -= delta
	if _gy_t <= 0.0:
		_gy_t = 0.25
		_gy = Game.ground_y(global_position.x, global_position.z)
	global_position.y = lerpf(global_position.y, _gy, clampf(delta * 10.0, 0.0, 1.0))


func _bird(delta: float) -> void:
	_angle += delta * 0.45
	var c := home + Vector3(cos(_angle), 0, sin(_angle)) * home_r * 0.6
	c.y = _alt + sin(_angle * 2.3) * 3.0 + (10.0 if state == "flee" else 0.0)
	var to := c - global_position
	speed = 7.0
	global_position += to.limit_length(speed * delta)
	yaw = atan2(-to.x, -to.z)
	if state == "flee" and _t <= 0.0:
		state = "idle"


func _swim(delta: float, p, dist: float, sp: Dictionary) -> void:
	var depth := -3.5 if species == "shark" else -2.2
	var aggro: float = sp.get("aggro", 0.0)
	var swimmer: bool = p.is_swimming() and City.terrain_height(p.global_position.x, p.global_position.z) < -3.0
	if aggro > 0.0 and swimmer and dist < aggro and p.alive():
		state = "attack"
	elif state == "attack":
		state = "idle"
	var c: Vector3
	if state == "attack":
		c = p.global_position + Vector3.UP * 0.6
		speed = sp.run
		if dist < 2.2 and _bite_cd <= 0.0:
			_bite_cd = 1.9
			p.damage(24.0, global_position, null, "melee")
			Fx.splash(Vector3(p.global_position.x, Game.WATER_Y, p.global_position.z), 1.0)
			Game.say("Shark attack!", Color(1.0, 0.4, 0.4))
	else:
		_angle += delta * (0.25 if species == "shark" else 0.6)
		c = home + Vector3(cos(_angle), 0, sin(_angle)) * home_r
		c.y = maxf(depth + sin(_angle * 3.0) * 0.8, City.terrain_height(c.x, c.z) + 1.0)
		c.y = minf(c.y, Game.WATER_Y - 0.8)
		speed = sp.walk
		if species == "fish" and dist < 5.0:
			speed = sp.run
	var to := c - global_position
	var np := global_position + to.limit_length(speed * delta)
	if City.terrain_height(np.x, np.z) < np.y - 0.4:
		global_position = np
	global_position.y = minf(global_position.y, Game.WATER_Y - 0.5)
	if to.length() > 0.1:
		yaw = atan2(-to.x, -to.z)
