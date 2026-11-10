class_name WildlifeManager
extends Node
## Wildlife around the player, built from the Blender animals (rigid parts animated in code):
## gulls circling the shore and perching on the sand / pier, dogs and cats in Palm Row,
## deer, rabbits and (at night) coyotes on Lookout Hill, fish schools over the reefs and one
## shark in deep water. Species without an exported model are simply not spawned.

const SPECIES := {
	"seagull": {"area": "coast", "max": 9, "walk": 1.0, "run": 8.0, "hp": 5.0, "shy": 7.0},
	"dog": {"area": "residential", "max": 3, "walk": 1.5, "run": 6.5, "hp": 40.0, "shy": 0.0},
	"cat": {"area": "residential", "max": 2, "walk": 0.7, "run": 5.5, "hp": 12.0, "shy": 6.0},
	"deer": {"area": "hill", "max": 4, "walk": 1.1, "run": 9.5, "hp": 70.0, "shy": 14.0},
	"rabbit": {"area": "hill", "max": 4, "walk": 0.8, "run": 7.0, "hp": 6.0, "shy": 8.0},
	"coyote": {"area": "hill_night", "max": 2, "walk": 1.4, "run": 8.0, "hp": 45.0, "shy": 10.0},
	"fish": {"area": "sea", "max": 14, "walk": 1.0, "run": 4.0, "hp": 2.0, "shy": 3.0},
	"fish_b": {"area": "sea", "max": 8, "walk": 0.9, "run": 3.5, "hp": 2.0, "shy": 3.0},
	"shark": {"area": "deep", "max": 1, "walk": 2.2, "run": 5.0, "hp": 220.0, "shy": 0.0},
}
const DESPAWN := 115.0

class Animal:
	extends CharacterBody3D
	var sp := ""
	var cfg: Dictionary = {}
	var model: Node3D
	var parts: Dictionary = {}
	var rest: Dictionary = {}
	var hp := 10.0
	var dead := false
	var dead_t := 0.0
	var mode := "idle"           # idle | walk | run | fly | perch | swim | attack
	var goal := Vector3.ZERO
	var home := Vector3.ZERO
	var timer := 0.0
	var phase := 0.0
	var threat := Vector3.ZERO
	var flying := false
	var bite_cd := 0.0
	var rng := RandomNumberGenerator.new()

	func apply_damage(amount: float, source: Node = null, _hit_pos := Vector3.ZERO, dir := Vector3.ZERO, _info: Dictionary = {}) -> void:
		if dead:
			return
		hp -= amount
		if source is Node3D:
			threat = (source as Node3D).global_position
		if hp <= 0.0:
			die(dir)
		else:
			mode = "run" if sp != "shark" else "attack"
			timer = 6.0

	func hit_by_vehicle(v: Node, vel: Vector3) -> void:
		if not dead and vel.length() > 3.0:
			apply_damage(vel.length() * 8.0, v, global_position, vel.normalized(), {})

	func die(dir: Vector3) -> void:
		dead = true
		mode = "dead"
		collision_layer = 0
		velocity = dir * 2.0
		if sp == "seagull":
			flying = false
		Audio.play(&"body_fall", global_position, -14.0, 1.6)

	func part_rot(nm: String, rot: Vector3) -> void:
		if parts.has(nm):
			(parts[nm] as Node3D).transform.basis = (rest[nm] as Basis) * Basis.from_euler(rot)

var animals: Array[Animal] = []
var rng := RandomNumberGenerator.new()
var _tick := 0.0
var _hill_pts: Array[Vector3] = []
var _res_pts: Array[Vector3] = []
var _coast_pts: Array[Vector3] = []

func _ready() -> void:
	rng.seed = 5150
	Events.noise.connect(_on_noise)
	_collect_points()
	var have: Array = []
	for s: String in SPECIES.keys():
		if Assets.has_model("animals/" + s):
			have.append(s)
	print("[Wildlife] species with models: ", have)

func _collect_points() -> void:
	var city: CityBuilder = Game.world.city
	for a in city.ped_areas:
		var r: Rect2 = a["rect"]
		var nm := String(a["name"])
		for i in 8:
			var p := Vector3(rng.randf_range(r.position.x, r.end.x), float(a.get("y", 0.15)), rng.randf_range(r.position.y, r.end.y))
			if nm in ["Coral Beach", "Promenade", "Pier", "Marina"]:
				_coast_pts.append(p)
			elif nm in ["Palm Park"]:
				_res_pts.append(p)
	if Game.peds != null and Game.peds.graph != null:
		for p2 in (Game.peds.graph as PedGraph).pts:
			if Game.district_at(p2) == "Palm Row":
				_res_pts.append(p2)
	for i in 400:
		var x := rng.randf_range(-292.0, -70.0)
		var z := rng.randf_range(-292.0, -70.0)
		if Terrain.in_city(x, z) or Terrain.road_distance(x, z) < 6.0:
			continue
		var y := Terrain.sample(x, z)
		if y < 2.0 or Terrain.normal(x, z).y < 0.82:
			continue
		_hill_pts.append(Vector3(x, y, z))

func clear() -> void:
	for a in animals:
		if is_instance_valid(a):
			a.queue_free()
	animals.clear()

func count() -> int:
	return animals.size()

# ---------------------------------------------------------------- spawning
func _spawn(sp: String, pos: Vector3) -> Animal:
	var a := Animal.new()
	a.sp = sp
	a.cfg = SPECIES[sp]
	a.hp = float(a.cfg["hp"])
	a.rng.seed = rng.randi()
	a.name = "%s_%d" % [sp, rng.randi() % 100000]
	a.collision_layer = Phys.CHARACTER
	a.collision_mask = Phys.WORLD | Phys.PROP
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var size := Vector3(0.4, 0.4, 0.6)
	match sp:
		"deer": size = Vector3(0.45, 1.2, 1.5)
		"dog", "coyote": size = Vector3(0.35, 0.6, 0.9)
		"cat", "rabbit": size = Vector3(0.2, 0.3, 0.45)
		"shark": size = Vector3(0.8, 0.9, 3.2)
		"fish", "fish_b": size = Vector3(0.1, 0.15, 0.35)
		"seagull": size = Vector3(0.5, 0.3, 0.5)
	box.size = size
	cs.shape = box
	# fish and shark have their origin at the body centre, land animals stand on it
	cs.position = Vector3.ZERO if (sp == "fish" or sp == "fish_b" or sp == "shark") else Vector3(0, size.y * 0.5, 0)
	a.add_child(cs)
	a.model = Assets.instance("animals/" + sp)
	a.add_child(a.model)
	for nm: String in ["body", "head", "leg_fl", "leg_fr", "leg_rl", "leg_rr", "tail", "wing_l", "wing_r"]:
		var n := PropFactory.part(a.model, nm)
		if n != null:
			a.parts[nm] = n
			a.rest[nm] = n.transform.basis
	(Game.main.get_node("Entities/NPCs") as Node3D).add_child(a)
	a.global_position = pos
	a.rotation.y = rng.randf() * TAU
	a.home = pos
	a.goal = pos
	a.phase = rng.randf() * TAU
	if sp == "seagull":
		a.flying = rng.randf() < 0.6
		a.mode = "fly" if a.flying else "perch"
		if a.flying:
			a.global_position = pos + Vector3(0, rng.randf_range(10.0, 22.0), 0)
	elif sp == "fish" or sp == "fish_b" or sp == "shark":
		a.mode = "swim"
	animals.append(a)
	return a

func _area_point(area: String, centre: Vector3) -> Variant:
	var list: Array[Vector3] = []
	match area:
		"coast": list = _coast_pts
		"residential": list = _res_pts
		"hill", "hill_night": list = _hill_pts
		"sea", "deep":
			for attempt in 12:
				var a := rng.randf() * TAU
				var r := rng.randf_range(12.0, 45.0)
				var x := centre.x + cos(a) * r
				var z := centre.z + sin(a) * r
				var floor_y := Terrain.sample(x, z)
				var need := 2.5 if area == "sea" else 9.0
				if Terrain.is_water(x, z) and floor_y < Terrain.SEA - need:
					var y := rng.randf_range(floor_y + 0.8, minf(Terrain.SEA - 1.2, floor_y + (4.0 if area == "sea" else 8.0)))
					return Vector3(x, y, z)
			return null
	if list.is_empty():
		return null
	for attempt in 8:
		var p: Vector3 = list[rng.randi() % list.size()]
		var d := p.distance_to(centre)
		if d > 22.0 and d < 80.0:
			return p
	return null

func _physics_process(delta: float) -> void:
	_tick -= delta
	var pl: Player = Game.player
	if pl == null:
		return
	var centre := pl.global_position
	if _tick <= 0.0:
		_tick = 1.0
		if Game.flags["wildlife"]:
			_populate(centre)
		elif not animals.is_empty():
			clear()
		for i in range(animals.size() - 1, -1, -1):
			var a := animals[i]
			if not is_instance_valid(a):
				animals.remove_at(i)
			elif a.global_position.distance_to(centre) > DESPAWN or (a.dead and a.dead_t > 40.0):
				a.queue_free()
				animals.remove_at(i)
	for a in animals:
		if is_instance_valid(a):
			_update(a, delta, pl)

func _populate(centre: Vector3) -> void:
	var counts := {}
	for a in animals:
		counts[a.sp] = int(counts.get(a.sp, 0)) + 1
	var night := Game.time.night if Game.time != null else 0.0
	var swimming := Game.player.state == Player.St.SWIM or Game.water_depth(Game.player.global_position + Vector3(0, 1.0, 0)) > 0.0
	for sp: String in SPECIES.keys():
		if not Assets.has_model("animals/" + sp):
			continue
		var cfg: Dictionary = SPECIES[sp]
		var area := String(cfg["area"])
		var mx := int(cfg["max"])
		if area == "hill_night" and night < 0.5:
			mx = 0
		if (sp == "cat" or sp == "dog") and night > 0.7:
			mx = maxi(1, mx - 1)
		if sp == "seagull" and night > 0.6:
			mx = 2
		if (area == "sea" or area == "deep") and absf(centre.z - 230.0) > 140.0 and not swimming:
			mx = 0
		if sp == "shark" and not swimming:
			mx = 0
		if int(counts.get(sp, 0)) >= mx:
			continue
		var p: Variant = _area_point(area, centre)
		if p != null:
			var a := _spawn(sp, p)
			if sp == "fish" or sp == "fish_b":
				# small school around the first fish
				for k in 4:
					var o := Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-1.5, 1.5))
					var f := _spawn(sp, (p as Vector3) + o)
					f.home = a.home

# ---------------------------------------------------------------- behaviour
func _on_noise(pos: Vector3, radius: float, kind: StringName, _source: Node) -> void:
	if kind != &"gunshot" and kind != &"explosion" and kind != &"horn":
		return
	for a in animals:
		if is_instance_valid(a) and not a.dead and a.global_position.distance_to(pos) < radius * 0.8:
			a.threat = pos
			if a.sp == "seagull":
				a.flying = true
				a.mode = "fly"
			elif a.sp != "shark":
				a.mode = "run"
				a.timer = a.rng.randf_range(5.0, 9.0)

func _update(a: Animal, delta: float, pl: Player) -> void:
	a.phase += delta
	if a.dead:
		a.dead_t += delta
		if not a.flying and a.sp != "fish" and a.sp != "fish_b" and a.sp != "shark":
			a.velocity.y -= 16.0 * delta
			a.velocity.x = move_toward(a.velocity.x, 0.0, delta * 6.0)
			a.velocity.z = move_toward(a.velocity.z, 0.0, delta * 6.0)
			a.move_and_slide()
		elif a.sp == "fish" or a.sp == "fish_b" or a.sp == "shark":
			a.global_position.y = minf(a.global_position.y + delta * 0.5, Terrain.SEA - 0.1)
		a.model.rotation.z = move_toward(a.model.rotation.z, PI * 0.5, delta * 5.0)
		return
	var cfg := a.cfg
	var dpl := a.global_position.distance_to(pl.global_position)
	match a.sp:
		"seagull": _bird(a, delta, dpl, pl)
		"fish", "fish_b": _fish(a, delta, dpl, pl)
		"shark": _shark(a, delta, dpl, pl)
		_: _quad(a, delta, dpl, pl, cfg)

func _quad(a: Animal, delta: float, dpl: float, pl: Player, cfg: Dictionary) -> void:
	var shy := float(cfg["shy"])
	if shy > 0.0 and dpl < shy and a.mode != "run":
		a.mode = "run"
		a.threat = pl.global_position
		a.timer = a.rng.randf_range(4.0, 7.0)
	a.timer -= delta
	var speed := 0.0
	match a.mode:
		"idle":
			if a.timer <= 0.0:
				a.mode = "walk"
				a.goal = a.home + Vector3(a.rng.randf_range(-8, 8), 0, a.rng.randf_range(-8, 8))
				a.timer = 12.0
			if a.sp == "dog" and dpl < 9.0 and a.rng.randf() < delta * 0.6:
				Audio.play(StringName("dog_bark_%d" % (1 + a.rng.randi() % 2)), a.global_position, -6.0, 1.0, 0.1, 40.0)
		"walk":
			speed = float(cfg["walk"])
			if Vector2(a.goal.x - a.global_position.x, a.goal.z - a.global_position.z).length() < 0.8 or a.timer <= 0.0:
				a.mode = "idle"
				a.timer = a.rng.randf_range(2.0, 7.0)
		"run":
			speed = float(cfg["run"])
			var away := a.global_position - a.threat
			away.y = 0.0
			a.goal = a.global_position + away.normalized() * 6.0
			if a.timer <= 0.0:
				a.mode = "idle"
				a.home = a.global_position
				a.timer = a.rng.randf_range(3.0, 6.0)
	var dirv := a.goal - a.global_position
	dirv.y = 0.0
	if speed > 0.0 and dirv.length() > 0.1:
		dirv = dirv.normalized()
		# do not run into the sea or off cliffs: turn back toward home
		var ahead := a.global_position + dirv * 1.5
		if Game.water_depth(Vector3(ahead.x, Terrain.SEA - 0.3, ahead.z)) > 0.0 and Terrain.sample(ahead.x, ahead.z) < Terrain.SEA:
			dirv = (a.home - a.global_position).normalized()
		a.velocity.x = move_toward(a.velocity.x, dirv.x * speed, delta * 12.0)
		a.velocity.z = move_toward(a.velocity.z, dirv.z * speed, delta * 12.0)
		a.rotation.y = lerp_angle(a.rotation.y, atan2(-dirv.x, -dirv.z), clampf(delta * 8.0, 0.0, 1.0))
	else:
		a.velocity.x = move_toward(a.velocity.x, 0.0, delta * 10.0)
		a.velocity.z = move_toward(a.velocity.z, 0.0, delta * 10.0)
	if not a.is_on_floor():
		a.velocity.y -= 16.0 * delta
	else:
		a.velocity.y = -0.5
	a.move_and_slide()
	# procedural gait
	var hs := Vector2(a.velocity.x, a.velocity.z).length()
	var freq := 3.0 + hs * 1.6
	var amp := clampf(hs / maxf(float(cfg["run"]), 0.1), 0.0, 1.0) * 0.7 + (0.25 if hs > 0.2 else 0.0)
	var s1 := sin(a.phase * freq * TAU * 0.25) * amp
	a.part_rot("leg_fl", Vector3(s1, 0, 0))
	a.part_rot("leg_rr", Vector3(s1, 0, 0))
	a.part_rot("leg_fr", Vector3(-s1, 0, 0))
	a.part_rot("leg_rl", Vector3(-s1, 0, 0))
	a.part_rot("tail", Vector3(0, sin(a.phase * (8.0 if a.sp == "dog" else 2.0)) * 0.35, 0))
	var graze := a.mode == "idle" and (a.sp == "deer" or a.sp == "rabbit") and sin(a.phase * 0.4) > 0.3
	a.part_rot("head", Vector3(-0.7 if graze else sin(a.phase * 1.3) * 0.08, 0, 0))

func _bird(a: Animal, delta: float, dpl: float, pl: Player) -> void:
	if a.mode == "perch":
		if dpl < float(a.cfg["shy"]) or pl.velocity.length() > 5.0 and dpl < 12.0:
			a.mode = "fly"
			a.flying = true
			a.timer = a.rng.randf_range(8.0, 16.0)
			Audio.play(&"bird_flap", a.global_position, -8.0, 1.0, 0.1, 30.0)
		a.part_rot("head", Vector3(0, sin(a.phase * 0.9) * 0.6, 0))
		a.part_rot("wing_l", Vector3(0, 1.45, 0))      # folded along the body
		a.part_rot("wing_r", Vector3(0, -1.45, 0))
		return
	# circle the home point, then glide down to land again
	a.timer -= delta
	var r := 9.0 + float(a.get_instance_id() % 7)
	var ang := a.phase * 0.35 + float(a.get_instance_id() % 13)
	var alt := a.home.y + 10.0 + 4.0 * sin(a.phase * 0.2)
	var target := a.home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	target.y = alt
	if a.timer <= 0.0 and a.rng.randf() < 0.004:
		target = a.home
	var to := target - a.global_position
	var step := to.limit_length(float(a.cfg["run"]) * delta)
	a.global_position += step
	if step.length() > 0.001:
		a.rotation.y = lerp_angle(a.rotation.y, atan2(-step.x, -step.z), clampf(delta * 4.0, 0.0, 1.0))
	if a.global_position.distance_to(a.home) < 0.6 and a.timer <= 0.0:
		a.mode = "perch"
		a.flying = false
	var flap := sin(a.phase * 11.0) * 0.7 if to.y > -0.5 else 0.15
	a.part_rot("wing_l", Vector3(0, 0, flap))
	a.part_rot("wing_r", Vector3(0, 0, -flap))

func _fish(a: Animal, delta: float, dpl: float, pl: Player) -> void:
	var r := 3.0 + float(a.get_instance_id() % 5) * 0.6
	var ang := a.phase * (0.5 + float(a.get_instance_id() % 3) * 0.1) + float(a.get_instance_id() % 11)
	var target := a.home + Vector3(cos(ang) * r, sin(a.phase * 0.7) * 0.4, sin(ang) * r)
	var speed := float(a.cfg["walk"])
	if dpl < float(a.cfg["shy"]):
		var away := a.global_position - pl.global_position
		target = a.global_position + away.normalized() * 3.0
		speed = float(a.cfg["run"])
	target.y = clampf(target.y, Terrain.sample(target.x, target.z) + 0.4, Terrain.SEA - 0.6)
	var step := (target - a.global_position).limit_length(speed * delta)
	a.global_position += step
	if step.length() > 0.0005:
		a.rotation.y = lerp_angle(a.rotation.y, atan2(-step.x, -step.z), clampf(delta * 6.0, 0.0, 1.0))
	a.part_rot("tail", Vector3(0, sin(a.phase * (9.0 if speed > 1.5 else 5.0)) * 0.5, 0))

func _shark(a: Animal, delta: float, dpl: float, pl: Player) -> void:
	a.bite_cd = maxf(0.0, a.bite_cd - delta)
	var swimming := pl.state == Player.St.SWIM and pl.vehicle == null
	var target := a.home + Vector3(cos(a.phase * 0.15) * 14.0, 0.0, sin(a.phase * 0.15) * 14.0)
	var speed := float(a.cfg["walk"])
	if swimming and dpl < 28.0 and pl.alive:
		target = pl.global_position + Vector3(0, 0.3, 0)
		speed = float(a.cfg["run"])
		if dpl < 2.4 and a.bite_cd <= 0.0:
			a.bite_cd = 2.5
			pl.apply_damage(28.0, a, pl.global_position + Vector3(0, 0.8, 0), Vector3.ZERO, {"type": "melee"})
			Audio.play(&"shark_bite", pl.global_position, 0.0)
			if Game.cam != null:
				Game.cam.shake(0.4)
	target.y = clampf(target.y, Terrain.sample(target.x, target.z) + 1.0, Terrain.SEA - 0.8)
	var step := (target - a.global_position).limit_length(speed * delta)
	a.global_position += step
	if step.length() > 0.001:
		a.rotation.y = lerp_angle(a.rotation.y, atan2(-step.x, -step.z), clampf(delta * 2.5, 0.0, 1.0))
	a.part_rot("tail", Vector3(0, sin(a.phase * (4.0 if speed > 3.0 else 2.2)) * 0.45, 0))
