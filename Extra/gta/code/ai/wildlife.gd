extends Node3D
## Wildlife: region based animals with simple ecosystem behaviour - grazing deer, rabbits, boar and
## cattle on Ember Hill (hunted by coyotes), dogs / cats / pigeons in the park, gulls over the coast,
## fish schools and a dangerous shark in deep water. Animals are rigid part hierarchies animated in code.

const KIT := "characters/kit_animals"
const SPEC := {
	"deer": {"model": "animal_deer", "hp": 60.0, "walk": 1.3, "run": 9.0, "flee": 16.0, "r": 0.45, "h": 1.5},
	"rabbit": {"model": "animal_rabbit", "hp": 10.0, "walk": 1.0, "run": 7.0, "flee": 9.0, "r": 0.15, "h": 0.3, "prey": true},
	"boar": {"model": "animal_boar", "hp": 90.0, "walk": 1.1, "run": 7.5, "flee": 0.0, "r": 0.4, "h": 0.9, "charges": true},
	"coyote": {"model": "animal_coyote", "hp": 45.0, "walk": 1.6, "run": 8.5, "flee": 11.0, "r": 0.3, "h": 0.8, "hunts": true},
	"cow": {"model": "animal_cow", "hp": 200.0, "walk": 0.7, "run": 3.5, "flee": 6.0, "r": 0.7, "h": 1.6},
	"dog": {"model": "animal_dog", "hp": 40.0, "walk": 1.5, "run": 6.5, "flee": 0.0, "r": 0.3, "h": 0.8, "friendly": true},
	"cat": {"model": "animal_cat", "hp": 15.0, "walk": 1.0, "run": 6.0, "flee": 6.0, "r": 0.18, "h": 0.4},
}

var animals: Array = []
var birds: Array = []
var fish: Array = []
var shark: Node3D = null
var shark_state := "patrol"
var shark_t := 0.0
var shark_bite := 0.0
var shark_hp := 220.0
var shark_goal := Vector3.ZERO
var spawned := false
var _t := 0.0


class Animal:
	extends CharacterBody3D
	var kind := "deer"
	var spec := {}
	var model: Node3D
	var legs: Array = []
	var head: Node3D
	var tail: Node3D
	var health := 50.0
	var dead := false
	var home := Vector3.ZERO
	var home_r := 40.0
	var goal := Vector3.ZERO
	var state := "graze"
	var t := 0.0
	var phase := 0.0
	var yaw := 0.0
	var target: Node3D = null
	var bite_cd := 0.0
	var vehicle = null
	var owner_mgr: Node

	func setup(k: String, at: Vector3, mgr: Node) -> void:
		kind = k
		owner_mgr = mgr
		spec = SPEC[k]
		health = float(spec.hp)
		home = at
		goal = at
		add_to_group("chars")
		add_to_group("animals")
		collision_layer = G.L_CHAR
		collision_mask = G.L_WORLD
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = float(spec.r)
		cap.height = maxf(float(spec.h), float(spec.r) * 2.0 + 0.02)
		cs.shape = cap
		cs.position = Vector3(0, float(spec.h) * 0.5, 0)
		add_child(cs)
		model = Assets.sub(KIT, String(spec.model), String(spec.model) + "_")
		add_child(model)
		for nm in ["Leg_FL", "Leg_FR", "Leg_RL", "Leg_RR"]:
			if model.has_node(nm):
				legs.append(model.get_node(nm))
		head = model.get_node_or_null("Head")
		tail = model.get_node_or_null("Tail")
		yaw = randf() * TAU
		floor_snap_length = 0.4

	func global_position_now() -> Vector3:
		return global_position

	func is_head_hit(_p: Vector3) -> bool:
		return false

	func take_damage(a: float, instigator: Node = null, _pos: Vector3 = Vector3.ZERO, _k: String = "") -> void:
		if dead:
			return
		health -= a
		if health <= 0.0:
			_die()
			return
		if spec.get("charges", false) and instigator is Node3D:
			state = "attack"
			target = instigator
			t = 0.0
		else:
			flee_from((instigator as Node3D).global_position if instigator is Node3D else global_position + Vector3(1, 0, 0))

	func hit_by_vehicle(_veh, vel: Vector3) -> void:
		take_damage(vel.length() * 9.0, null)
		velocity = vel * 0.6 + Vector3(0, 3, 0)

	func knockdown(imp: Vector3) -> void:
		velocity = imp

	func _die() -> void:
		dead = true
		state = "dead"
		remove_from_group("chars")
		collision_layer = 0
		var tw := create_tween()
		tw.tween_property(model, "rotation:z", PI * 0.5, 0.35)
		tw.parallel().tween_property(model, "position:y", float(spec.r) * 0.6, 0.35)
		tw.tween_interval(25.0)
		tw.tween_callback(queue_free)
		Sfx.play("thud", global_position, -4.0, 1.3)

	func flee_from(p: Vector3) -> void:
		if dead or float(spec.flee) <= 0.0:
			return
		var away := G.flat(global_position - p).normalized()
		if away.length() < 0.1:
			away = Vector3(1, 0, 0)
		goal = global_position + away.rotated(Vector3.UP, randf_range(-0.6, 0.6)) * 26.0
		state = "flee"
		t = 0.0

	func _physics_process(delta: float) -> void:
		if dead:
			return
		t += delta
		bite_cd -= delta
		var p: Node3D = G.player
		var pp: Vector3 = p.global_position_now() if p else Vector3.ZERO
		var dp := pp.distance_to(global_position)
		if dp > 190.0:
			return
		var sp := 0.0
		match state:
			"graze":
				if t > 4.0 + randf() * 6.0:
					var a := randf() * TAU
					goal = home + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, home_r)
					state = "walk"
					t = 0.0
				if head:
					head.rotation.x = lerpf(head.rotation.x, -0.9 if kind in ["deer", "cow", "rabbit", "boar"] else 0.0, delta * 2.0)
			"walk":
				sp = float(spec.walk)
				if head:
					head.rotation.x = lerpf(head.rotation.x, 0.0, delta * 3.0)
				if G.dist2(global_position, goal) < 1.0 or t > 14.0:
					state = "graze"
					t = 0.0
			"flee":
				sp = float(spec.run)
				if head:
					head.rotation.x = lerpf(head.rotation.x, 0.2, delta * 4.0)
				if t > 5.0 or G.dist2(global_position, goal) < 2.0:
					state = "graze"
					t = 0.0
					if global_position.distance_to(home) > home_r * 1.6:
						goal = home
						state = "walk"
			"attack", "hunt":
				if target == null or not is_instance_valid(target) or target.get("dead") == true or t > 14.0:
					state = "graze"
					target = null
				else:
					goal = target.global_position
					sp = float(spec.run)
					if global_position.distance_to(goal) < 1.6 + float(spec.r):
						sp = 0.0
						if bite_cd <= 0.0:
							bite_cd = 1.1
							if target.has_method("take_damage"):
								target.take_damage(12.0 if kind != "boar" else 20.0, self, target.global_position, "melee")
							Sfx.play("punch", global_position, -2.0, 0.8)
			"follow":
				goal = pp
				sp = float(spec.run) if dp > 7.0 else (float(spec.walk) if dp > 3.0 else 0.0)
				if dp > 45.0 or t > 40.0:
					state = "graze"
		# stimulus
		if int(t * 4.0) != int((t - delta) * 4.0) and state in ["graze", "walk", "follow"]:
			var scare := float(spec.flee)
			var psp: float = (p.velocity as Vector3).length() if p and p.get("velocity") != null else 0.0
			var loud: bool = psp > 3.0 or (p != null and p.vehicle != null)
			if scare > 0.0 and dp < (scare if loud else scare * 0.45) and not (p != null and p.crouching and dp > 3.0):
				flee_from(pp)
			elif spec.get("friendly", false) and dp < 9.0 and state != "follow" and randf() < 0.3:
				state = "follow"
				t = 0.0
			elif spec.get("charges", false) and dp < 5.0 and p != null and p.vehicle == null:
				state = "attack"
				target = p
				t = 0.0
			elif spec.get("hunts", false) and randf() < 0.05:
				for o in get_tree().get_nodes_in_group("animals"):
					if o.get("spec") != null and o.spec.get("prey", false) and not o.dead and o.global_position.distance_to(global_position) < 28.0:
						state = "hunt"
						target = o
						t = 0.0
						o.flee_from(global_position)
						break
		var dir := G.flat(goal - global_position)
		var tv := Vector3.ZERO
		if sp > 0.0 and dir.length() > 0.3:
			dir = dir.normalized()
			tv = dir * sp
			yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z), clampf(delta * 6.0, 0.0, 1.0))
		velocity.x = move_toward(velocity.x, tv.x, 20.0 * delta)
		velocity.z = move_toward(velocity.z, tv.z, 20.0 * delta)
		velocity.y = velocity.y - 18.0 * delta if not is_on_floor() else -0.5
		move_and_slide()
		rotation.y = yaw
		if global_position.y < G.WATER_LEVEL - 0.2:
			goal = home
			state = "walk"
		# procedural gait
		var hs := Vector3(velocity.x, 0, velocity.z).length()
		phase += hs * delta * (6.0 / maxf(float(spec.h), 0.3))
		var amp := clampf(hs / maxf(float(spec.walk), 0.5), 0.0, 1.0) * (0.55 if hs < float(spec.walk) * 2.0 else 0.9)
		for i in legs.size():
			var off := 0.0 if i in [0, 3] else PI
			(legs[i] as Node3D).rotation.x = sin(phase + off) * amp
		if tail:
			tail.rotation.y = sin(Time.get_ticks_msec() * 0.008 + get_instance_id() % 7) * (0.5 if spec.get("friendly", false) else 0.15)
		if kind == "rabbit" and hs > 0.5:
			model.position.y = absf(sin(phase * 0.5)) * 0.12


func _ready() -> void:
	call_deferred("_populate")


func _spawn(kind: String, at: Vector3, home_r: float = 40.0) -> void:
	var a := Animal.new()
	a.setup(kind, at, self)
	a.home_r = home_r
	add_child(a)
	a.global_position = Vector3(at.x, WorldLayout.height(at.x, at.z) + 0.3 if at.z < -175.0 else at.y + 0.3, at.z)
	animals.append(a)


func _populate() -> void:
	if spawned or G.world == null:
		return
	spawned = true
	var hill: Rect2 = G.world.spawns.get("wild", Rect2(-296, -296, 190, 108))
	var kinds := ["deer", "deer", "deer", "rabbit", "rabbit", "rabbit", "rabbit", "coyote", "boar", "deer", "rabbit", "coyote"]
	for k in kinds:
		for attempt in 8:
			var x := randf_range(hill.position.x, hill.end.x)
			var z := randf_range(hill.position.y, hill.end.y)
			if WorldLayout.path_info(x, z).x > 8.0 and absf(WorldLayout.height(x + 2.0, z) - WorldLayout.height(x, z)) < 1.2:
				_spawn(k, Vector3(x, 0, z), 34.0)
				break
	for i in 2:
		_spawn("cow", Vector3(-135.0 + i * 9.0, 0, -196.0 - i * 4.0), 12.0)
	if G.world.spawns.has("park"):
		var park: Rect2 = G.world.spawns["park"]
		var c := park.get_center()
		_spawn("dog", Vector3(c.x - 14.0, 0.2, c.y + 12.0), 22.0)
		_spawn("dog", Vector3(c.x + 16.0, 0.2, c.y - 10.0), 22.0)
		_spawn("cat", Vector3(c.x + 12.0, 0.2, c.y + 16.0), 18.0)
		for i in 8:
			_bird("animal_pigeon", Vector3(c.x + randf_range(-18, 18), 0.2, c.y + randf_range(-18, 18)), true)
	_spawn("cat", Vector3(-216.0, 0.2, 40.0), 16.0)
	_spawn("dog", Vector3(-150.0, 0.2, -120.0), 18.0)
	for i in 9:
		_bird("animal_seagull", Vector3(randf_range(-220, 220), randf_range(14, 30), randf_range(190, 260)), false)
	for i in 4:
		_bird("animal_seagull", Vector3(randf_range(60, 240), randf_range(18, 34), randf_range(150, 200)), false)
	# fish schools near the pier, the wreck and the reef
	for centre in [Vector3(-40, -4.0, 232), Vector3(165, -6.5, 262), Vector3(-150, -5.0, 258), Vector3(60, -6.0, 280), Vector3(230, -6.0, 236)]:
		var school := {"centre": centre, "goal": centre, "t": randf() * 5.0, "nodes": []}
		for i in 7:
			var f := Assets.sub(KIT, "animal_fish" if (i + int(centre.x)) % 2 == 0 else "animal_fish_b", "")
			add_child(f)
			f.global_position = centre + Vector3(randf_range(-2, 2), randf_range(-0.8, 0.8), randf_range(-2, 2))
			(school.nodes as Array).append({"n": f, "off": Vector3(randf_range(-2.2, 2.2), randf_range(-0.9, 0.9), randf_range(-2.2, 2.2)), "ph": randf() * 6.0})
		fish.append(school)
	shark = Assets.sub(KIT, "animal_shark", "animal_shark_")
	add_child(shark)
	shark.global_position = Vector3(40.0, -4.5, 300.0)
	shark_goal = shark.global_position
	var body := StaticBody3D.new()
	body.collision_layer = G.L_CHAR
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 2.8
	cs.shape = cap
	cs.rotation.x = PI * 0.5
	body.add_child(cs)
	body.set_script(load("res://gta/code/ai/shark_body.gd"))
	shark.add_child(body)
	body.set("mgr", self)


func _bird(model: String, at: Vector3, ground: bool) -> void:
	var b := Assets.sub(KIT, model, model + "_")
	add_child(b)
	b.global_position = at
	birds.append({"n": b, "home": at, "ground": ground, "state": "ground" if ground else "fly", "ph": randf() * TAU, "r": randf_range(9.0, 22.0),
		"t": randf() * 5.0, "goal": at, "wl": b.get_node_or_null("Wing_L"), "wr": b.get_node_or_null("Wing_R"), "spd": randf_range(0.25, 0.45)})


func shark_hit(a: float) -> void:
	shark_hp -= a
	shark_state = "flee" if shark_hp > 0.0 else "dead"
	shark_t = 0.0
	if shark_hp <= 0.0 and shark:
		create_tween().tween_property(shark, "rotation:z", PI, 1.2)
		G.say("The shark is dead", UIKit.DIM)


func _process(delta: float) -> void:
	var on: bool = G.flags.wildlife
	visible = on
	if not on or G.player == null:
		return
	var p: Player = G.player
	var pp := p.global_position_now()
	_t += delta
	# birds
	for b in birds:
		var n: Node3D = b.n
		if n.global_position.distance_to(pp) > 230.0:
			continue
		b.t = float(b.t) + delta
		var flap := 0.0
		if b.state == "ground":
			n.rotation.x = sin(float(b.t) * 6.0 + float(b.ph)) * 0.25
			if int(float(b.t) * 0.4) != int((float(b.t) - delta) * 0.4):
				n.rotation.y += randf_range(-1.0, 1.0)
				n.global_position += Basis(Vector3.UP, n.rotation.y) * Vector3(0, 0, -0.3)
			if n.global_position.distance_to(pp) < 5.5 or (p.last_shot < 0.3 and n.global_position.distance_to(pp) < 40.0):
				b.state = "flee"
				b.t = 0.0
				var a := randf() * TAU
				b.goal = (b.home as Vector3) + Vector3(cos(a) * 16.0, 0.0, sin(a) * 16.0)
		elif b.state == "flee":
			flap = 1.0
			var tt := clampf(float(b.t) / 5.0, 0.0, 1.0)
			var g: Vector3 = b.goal
			var arc := Vector3(g.x, (b.home as Vector3).y + sin(tt * PI) * 9.0, g.z)
			var prev := n.global_position
			n.global_position = n.global_position.lerp(arc, clampf(delta * 0.9, 0.0, 1.0))
			var d := n.global_position - prev
			if d.length() > 0.001:
				n.rotation.y = atan2(-d.x, -d.z)
			n.rotation.x = 0.0
			if tt >= 1.0:
				b.state = "ground"
				n.global_position = Vector3(g.x, (b.home as Vector3).y, g.z)
		else:
			b.ph = float(b.ph) + delta * float(b.spd)
			var h: Vector3 = b.home
			var r: float = b.r
			var np := h + Vector3(cos(float(b.ph)) * r, sin(float(b.ph) * 2.3) * 2.0, sin(float(b.ph)) * r)
			n.global_position = np
			n.rotation.y = -float(b.ph) + PI
			n.rotation.z = 0.35
			flap = 0.35 + 0.3 * sin(float(b.t) * 0.7)
		if b.wl:
			var w := sin(float(b.t) * 14.0) * 0.9 * flap
			(b.wl as Node3D).rotation.z = -w
			(b.wr as Node3D).rotation.z = w
	# fish
	if pp.z > 150.0:
		for s in fish:
			s.t = float(s.t) + delta
			var c: Vector3 = s.centre
			if float(s.t) > 6.0 or (s.goal as Vector3).distance_to(c) < 0.5:
				s.t = 0.0
				var base: Vector3 = s.centre
				s.goal = Vector3(clampf(base.x + randf_range(-9, 9), -280, 280), clampf(base.y + randf_range(-1.0, 1.0), -9.0, -2.4), clampf(base.z + randf_range(-9, 9), 205, 320))
			if pp.distance_to(c) < 5.0:
				s.goal = c + (c - pp).normalized() * 9.0
				(s.goal as Vector3).y = clampf((s.goal as Vector3).y, -9.0, -2.4)
			var ng := (s.goal as Vector3)
			ng.y = minf(ng.y, -2.2)
			s.centre = c.move_toward(ng, delta * (1.4 if pp.distance_to(c) > 6.0 else 4.0))
			for f in s.nodes:
				var fn: Node3D = f.n
				var tgt: Vector3 = (s.centre as Vector3) + (f.off as Vector3) + Vector3(sin(_t + float(f.ph)), 0, cos(_t * 0.8 + float(f.ph))) * 0.4
				var prev2 := fn.global_position
				fn.global_position = prev2.lerp(tgt, clampf(delta * 2.0, 0.0, 1.0))
				var d2 := fn.global_position - prev2
				if d2.length() > 0.002:
					fn.rotation.y = lerp_angle(fn.rotation.y, atan2(-d2.x, -d2.z), clampf(delta * 6.0, 0.0, 1.0))
				var tl := fn.get_node_or_null("animal_fish_Tail")
				if tl == null:
					tl = fn.get_node_or_null("animal_fish_b_Tail")
				if tl:
					(tl as Node3D).rotation.y = sin(_t * 10.0 + float(f.ph)) * 0.5
	_shark(delta, p, pp)


func _shark(delta: float, p: Player, pp: Vector3) -> void:
	if shark == null or shark_state == "dead":
		return
	shark_t += delta
	shark_bite -= delta
	var sp := 2.4
	var swimming: bool = p.st == p.St.SWIM
	var depth_ok := WorldLayout.height(pp.x, pp.z) < -3.2
	var d := shark.global_position.distance_to(pp)
	match shark_state:
		"patrol":
			if shark.global_position.distance_to(shark_goal) < 3.0 or shark_t > 20.0:
				shark_t = 0.0
				shark_goal = Vector3(randf_range(-240, 260), randf_range(-7.0, -3.0), randf_range(250, 330))
			if swimming and depth_ok and d < 42.0:
				shark_state = "attack"
				shark_t = 0.0
				G.say("Something large is circling below...", Color(1, 0.6, 0.4))
		"attack":
			sp = 7.5
			shark_goal = pp + Vector3(0, 0.3, 0)
			if not swimming or not depth_ok or d > 70.0:
				shark_state = "patrol"
				shark_t = 30.0
			elif d < 2.3 and shark_bite <= 0.0:
				shark_bite = 1.4
				p.take_damage(24.0, null, shark.global_position, "melee")
				Sfx.play("splash", pp, 0.0, 0.7)
				if G.fx:
					G.fx.splash(Vector3(pp.x, G.WATER_LEVEL, pp.z), 1.2)
		"flee":
			sp = 8.0
			shark_goal = shark.global_position + (shark.global_position - pp).normalized() * 30.0
			if shark_t > 6.0:
				shark_state = "patrol"
	shark_goal.y = clampf(shark_goal.y, WorldLayout.height(shark.global_position.x, shark.global_position.z) + 1.0, -1.9)
	shark_goal.z = maxf(shark_goal.z, 214.0)
	var to := shark_goal - shark.global_position
	if to.length() > 0.3:
		var dir := to.normalized()
		shark.global_position += dir * sp * delta
		shark.rotation.y = lerp_angle(shark.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 2.5, 0.0, 1.0))
		shark.rotation.x = lerpf(shark.rotation.x, clampf(dir.y, -0.5, 0.5), delta * 2.0)
	var tl := shark.get_node_or_null("Tail")
	if tl:
		(tl as Node3D).rotation.y = sin(_t * (4.0 + sp)) * 0.45
