class_name Animal
extends CharacterBody3D
# Lightweight wildlife: deer / boar / dog on land, gulls in the air, fish and sharks in the sea.

const SPEC := {
	"deer": {"model": "animal_deer", "speed": 2.0, "run": 9.0, "hp": 60.0, "r": 0.4, "h": 1.5},
	"boar": {"model": "animal_boar", "speed": 1.5, "run": 7.0, "hp": 90.0, "r": 0.45, "h": 1.0, "attack": 16.0},
	"dog": {"model": "animal_dog", "speed": 2.2, "run": 7.0, "hp": 40.0, "r": 0.3, "h": 0.7},
	"gull": {"model": "animal_gull", "speed": 7.0, "run": 11.0, "hp": 5.0, "r": 0.3, "h": 0.3},
	"fish": {"model": "animal_fish", "speed": 1.6, "run": 4.0, "hp": 3.0, "r": 0.15, "h": 0.2},
	"shark": {"model": "animal_shark", "speed": 3.0, "run": 7.5, "hp": 260.0, "r": 0.5, "h": 0.8, "attack": 28.0},
}

var kind := "deer"
var spec: Dictionary
var model: Node3D
var home := Vector3.ZERO
var dest := Vector3.ZERO
var wait_t := 0.0
var scared_t := 0.0
var scare_from := Vector3.ZERO
var dead := false
var health := 50.0
var phase := 0.0
var bite_t := 0.0
var mass := 60.0


static func make(k: String) -> Animal:
	var a := Animal.new()
	a.kind = k
	a.spec = SPEC[k]
	a.health = a.spec.hp
	a.collision_layer = G.L_CHAR
	a.collision_mask = G.L_WORLD if k in ["deer", "boar", "dog"] else 0
	var cs := CollisionShape3D.new()
	var c := CapsuleShape3D.new()
	c.radius = a.spec.r
	c.height = max(a.spec.h, a.spec.r * 2.0)
	cs.shape = c
	cs.position.y = a.spec.h / 2.0 if k in ["deer", "boar", "dog"] else 0.0
	a.add_child(cs)
	a.model = G.model("characters/" + a.spec.model)
	a.add_child(a.model)
	a.phase = randf() * TAU
	G.props.append(a)
	return a


func _exit_tree() -> void:
	G.props.erase(self)


func scare(from: Vector3) -> void:
	if kind in ["shark", "boar"]:
		return
	scared_t = 8.0
	scare_from = from


func take_damage(amount: float, _attacker, _pos: Vector3, _dir: Vector3, _kind: String) -> void:
	if dead:
		return
	health -= amount
	scared_t = 10.0
	scare_from = G.player.global_position
	if health <= 0.0:
		dead = true
		collision_layer = 0
		model.rotation.z = PI / 2 if kind != "gull" else PI
		G.fx.blood(global_position + Vector3.UP * 0.4)


func update(dt: float) -> void:
	if dead:
		if kind == "gull" and global_position.y > G.height(global_position.x, global_position.z) + 0.2:
			global_position.y -= 9.0 * dt
		return
	var p = G.player
	var pp: Vector3 = p.global_position
	var dp := global_position.distance_to(pp)
	phase += dt * 6.0
	scared_t = max(0.0, scared_t - dt)
	bite_t = max(0.0, bite_t - dt)
	var speed: float = spec.speed
	var dir := Vector3.ZERO
	var land := kind in ["deer", "boar", "dog"]
	# reactions
	var chase := false
	if kind == "boar" and dp < 8.0 and not p.dead and p.vehicle == null:
		chase = true
	if kind == "shark" and p.state == "swim" and dp < 32.0 and pp.z > 238.0 and not p.dead:
		chase = true
	if chase:
		dir = (pp + Vector3.UP * 0.6 - global_position).normalized()
		speed = spec.run
		if dp < 1.7 and bite_t <= 0.0:
			bite_t = 1.4
			p.take_damage(spec.attack, null, pp + Vector3.UP, dir, "melee")
			G.audio.play3d("punch", pp)
	elif (kind in ["deer", "dog", "fish"] and dp < (16.0 if kind == "deer" else 5.0) and not (kind == "dog")) or scared_t > 0.0:
		var from := scare_from if scared_t > 0.0 else pp
		dir = global_position - from
		if land:
			dir.y = 0
		if dir.length() < 0.1:
			dir = Vector3(1, 0, 0)
		dir = dir.normalized()
		speed = spec.run
	else:
		if wait_t > 0.0 and kind != "gull":
			wait_t -= dt
		else:
			if dest == Vector3.ZERO or global_position.distance_to(dest) < 1.5:
				var rr := 12.0 if kind == "fish" else 30.0
				dest = home + Vector3(randf_range(-rr, rr), randf_range(-1.5, 1.5) if not land else 0.0, randf_range(-rr, rr))
				if kind in ["fish", "shark"]:
					dest.y = clamp(dest.y, G.height(dest.x, dest.z) + 0.8, G.WATER_Y - 0.8)
				if kind == "gull":
					dest.y = randf_range(10, 22)
				if land and randf() < 0.5:
					wait_t = randf_range(1.0, 5.0)
			dir = dest - global_position
			if land:
				dir.y = 0
			dir = dir.normalized() if dir.length() > 0.1 else Vector3.ZERO
	# keep to habitat
	if land:
		velocity.x = move_toward(velocity.x, dir.x * speed, 20.0 * dt)
		velocity.z = move_toward(velocity.z, dir.z * speed, 20.0 * dt)
		velocity.y -= 20.0 * dt
		move_and_slide()
		if global_position.y < G.WATER_Y - 0.3:
			dest = home
			scared_t = 0.0
		model.position.y = abs(sin(phase * (2.0 if speed > 3.0 else 1.0))) * 0.05 * (1.0 if velocity.length() > 0.3 else 0.0)
	else:
		var np := global_position + dir * speed * dt
		if kind in ["fish", "shark"]:
			np.y = clamp(np.y, G.height(np.x, np.z) + 0.5, G.WATER_Y - 0.5)
			if G.height(np.x, np.z) > G.WATER_Y - 1.2:
				np = global_position
				dest = home
				scared_t = 0.0
		else:
			np.y = max(np.y, 6.0)
		global_position = np
		model.rotation.z = sin(phase * (0.4 if kind == "shark" else 1.6)) * (0.12 if kind != "gull" else 0.25)
	if dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), min(1.0, dt * 4.0))
