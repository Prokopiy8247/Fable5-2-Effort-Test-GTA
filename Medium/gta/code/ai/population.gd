extends Node3D
## Pedestrian population around the player, panic/witness propagation, gang turf, shop clerks and wildlife zones.

const NPC := preload("res://gta/code/ai/npc.gd")
const Animal := preload("res://gta/code/ai/animal.gd")

var enabled := true
var wildlife_enabled := true
var max_peds := 16
var _t := 0.0
var gang_spawned := false
var animals: Array = []
var clerks: Array = []


func start() -> void:
	# shop staff standing by their storefronts
	for key in ["Gun Shop", "Clothing Store", "Barber"]:
		if G.world.locations.has(key):
			var p: Vector3 = G.world.locations[key]
			var c = spawn_ped(p + Vector3(1.8, 0.1, -0.2), {}, "clerk")
			c.home = c.global_position
			c.rotation.y = 0.0
			clerks.append(c)
	_spawn_wildlife()


func spawn_ped(pos: Vector3, look: Dictionary = {}, role := "ped"):
	var n = CharacterBody3D.new()
	n.set_script(NPC)
	G.main.add_child(n)
	n.global_position = pos
	n.setup(role, look)
	return n


func count(role := "ped") -> int:
	var c = 0
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.role == role and not n.dead:
			c += 1
	return c


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.6
	var pp = G.player_pos()
	var cam = get_viewport().get_camera_3d()
	var n_ped = 0
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.role != "ped" or n.dead:
			continue
		var d = G.dist2d(n.global_position, pp)
		var behind: bool = cam != null and (n.global_position - cam.global_position).dot(-cam.global_basis.z) < 0.0
		if d > 150.0 or (d > 80.0 and behind):
			n.queue_free()
		else:
			n_ped += 1
	if enabled:
		var want = max_peds
		var dn: String = G.world.district(pp)
		if dn in ["Ironside", "Rustyard", "Westwood", "Cinder Airfield", "Cinder Bay"]:
			want = int(want * 0.45)
		elif dn in ["Larkspur", "Signal Hill"]:
			want = int(want * 0.7)
		if G.is_night():
			want = int(want * 0.5)
		if G.env and G.env.w.rain > 0.4:
			want = int(want * 0.6)
		var tries = 0
		while n_ped < want and tries < 5:
			tries += 1
			var i = G.rng.randi() % G.world.ped_nodes.size()
			var p: Vector3 = G.world.ped_nodes[i]
			var d = G.dist2d(p, pp)
			if d < 38.0 or d > 115.0:
				continue
			if cam and d < 90.0:
				var to = (p - cam.global_position).normalized()
				if to.dot(-cam.global_basis.z) > 0.5 and G.los(cam.global_position, p + Vector3(0, 1.5, 0)):
					continue
			var ped = spawn_ped(p + Vector3(G.rng.randf_range(-1, 1), 0.1, G.rng.randf_range(-1, 1)))
			ped.node_i = i
			ped.prev_i = i
			n_ped += 1
	# gang turf in the Rustyard
	var turf = Vector3(272, 0.3, 150)
	if not gang_spawned and enabled and G.dist2d(pp, turf) < 120.0 and G.dist2d(pp, turf) > 45.0:
		gang_spawned = true
		for k in 5:
			var g = spawn_ped(turf + Vector3(G.rng.randf_range(-6, 6), 0, G.rng.randf_range(-6, 6)), {}, "gang")
			g.set_state("idle")
			g.home = g.global_position
			g.rotation.y = G.rng.randf() * TAU
	elif gang_spawned and G.dist2d(pp, turf) > 200.0:
		gang_spawned = false
		for n in get_tree().get_nodes_in_group("npcs"):
			if n.role == "gang":
				n.queue_free()
	# gang aggression when the player gets close with a weapon out
	if gang_spawned and G.player and G.player.state != "vehicle":
		for n in get_tree().get_nodes_in_group("npcs"):
			if n.role == "gang" and not n.dead and n.state == "idle":
				var d2: float = n.global_position.distance_to(G.player.global_position)
				if d2 < 9.0 or (d2 < 22.0 and G.player.weapons.is_gun() and n.sees(G.player, 25.0)):
					n.target = G.player
					n._arm()
					n.set_state("combat")
					G.notify("You are on Rust Hounds turf!", 3.0)
	for a in animals:
		if is_instance_valid(a):
			var near: bool = wildlife_enabled and G.dist2d(a.home, pp) < 170.0
			if a.visible != near:
				a.visible = near
				a.set_physics_process(near)


## Danger event: bystanders flee, cower or phone the police; traffic panics.
func panic(pos: Vector3, radius: float, source = null, exclude = null) -> void:
	for n in get_tree().get_nodes_in_group("npcs"):
		if n == exclude or n.dead or n.role in ["cop", "swat"]:
			continue
		var d: float = n.global_position.distance_to(pos)
		if d > radius:
			continue
		n.alerted = true
		if n.role == "gang":
			continue
		if n.state in ["flee", "cower", "phone", "down", "fight"]:
			continue
		n.threat = pos
		var r = G.rng.randf()
		if n.role == "clerk":
			n.set_state("cower")
		elif r < 0.7 or d < 6.0:
			n.flee(pos)
		elif r < 0.85:
			n.set_state("cower")
		else:
			n.flee(pos)
	if G.traffic:
		G.traffic.scare(pos, radius * 0.8)
	for a in animals:
		if is_instance_valid(a) and a.visible and a.global_position.distance_to(pos) < radius * 1.5:
			a.scare(pos)


## Find a civilian who can see `pos` and have them phone it in. Returns true if somebody starts a call.
func find_witness(pos: Vector3, crime: Dictionary, radius := 38.0) -> bool:
	var best = null
	var bd = radius
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.dead or n.role in ["cop", "swat", "gang"] or n.state in ["down", "phone"]:
			continue
		var d: float = n.global_position.distance_to(pos)
		if d < bd and d > 2.0 and G.los(n.global_position + Vector3(0, 1.6, 0), pos + Vector3(0, 1.2, 0)):
			bd = d
			best = n
	if best == null:
		# occupied traffic vehicles also count as witnesses (drivers have phones too)
		if G.traffic:
			for v in G.traffic.ai_list:
				if is_instance_valid(v) and v.owner_tag == "traffic" and v.global_position.distance_to(pos) < radius * 0.7:
					get_tree().create_timer(5.0).timeout.connect(func(): if G.wanted and is_instance_valid(v) and not v.dead and v.has_ai_driver(): G.wanted.witness_report(crime))
					return true
		return false
	best.threat = pos
	best.report_crime = crime
	best.set_state("phone")
	return true


func honk(pos: Vector3, dir: Vector3) -> void:
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.dead or n.state != "wander":
			continue
		var to: Vector3 = n.global_position - pos
		if to.length() < 12.0 and to.normalized().dot(dir) > 0.7:
			n.flee(pos, 2.5)


func rally_gang(who, target) -> void:
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.role == "gang" and n != who and not n.dead and n.global_position.distance_to(who.global_position) < 40.0:
			n.target = target
			n._arm()
			n.set_state("combat")


func on_death(npc, by_player: bool) -> void:
	if G.extras:
		G.extras.on_casualty(npc.global_position, by_player)


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		for n in get_tree().get_nodes_in_group("npcs"):
			if n.role in ["ped", "gang"]:
				n.queue_free()
		gang_spawned = false


# ------------------------------------------------------------------ wildlife
func _animal(kind: String, pos: Vector3, zone: Rect2, y_range := Vector2.ZERO):
	var a = CharacterBody3D.new()
	a.set_script(Animal)
	G.main.add_child(a)
	a.global_position = pos
	a.setup(kind, zone, y_range)
	animals.append(a)
	return a


func _spawn_wildlife() -> void:
	var woods = Rect2(-297, -200, 46, 400)
	var r = G.rng
	for i in 4:
		_animal("deer", Vector3(r.randf_range(-295, -253), 0.2, r.randf_range(-190, 190)), woods)
	for i in 5:
		_animal("rabbit", Vector3(r.randf_range(-295, -253), 0.2, r.randf_range(-190, 190)), woods)
	for i in 2:
		_animal("cow", Vector3(r.randf_range(-290, -258), 0.2, r.randf_range(60, 110)), Rect2(-294, 50, 40, 70))
	var park = Rect2(-230, 110, 100, 80)
	for i in 3:
		_animal("dog", Vector3(r.randf_range(-225, -135), 0.2, r.randf_range(115, 185)), park)
	_animal("rabbit", Vector3(-180, 0.2, 150), park)
	for i in 8:
		_animal("seagull", Vector3(r.randf_range(-250, 150), r.randf_range(14, 30), r.randf_range(215, 290)), Rect2(-280, 205, 460, 110), Vector2(12, 34))
	for i in 10:
		_animal("fish", Vector3(r.randf_range(-120, 120), r.randf_range(-7, -2.5), r.randf_range(250, 320)), Rect2(-140, 240, 280, 100), Vector2(-8.0, -2.0))
	for i in 8:
		_animal("fish", Vector3(-200 + r.randf_range(-18, 18), r.randf_range(-8, -3), 330 + r.randf_range(-18, 18)), Rect2(-225, 305, 50, 50), Vector2(-8.5, -2.5))
	_animal("shark", Vector3(-200, -5, 360), Rect2(-290, 320, 240, 120), Vector2(-7.5, -2.5))
	_animal("shark", Vector3(380, -5, 40), Rect2(330, -120, 130, 300), Vector2(-7.5, -2.5))
	_animal("shark", Vector3(60, -5, 370), Rect2(-60, 330, 260, 110), Vector2(-7.5, -2.5))
