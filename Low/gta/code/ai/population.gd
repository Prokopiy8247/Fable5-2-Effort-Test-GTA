class_name Population
extends Node
# Pedestrian spawn/despawn with simulation tiers, fixed NPCs (staff, patrol cops, gang),
# danger propagation, corpse cleanup and wildlife.

var enabled := true
var wildlife_on := true
var max_peds := 22
var npcs: Array = []          # managed NPCs (not drivers)
var drivers: Array = []
var animals: Array = []
var spawn_t := 0.0
var frame := 0
var fixed: Array = []         # {pos, role, node, ai, yaw}


func _ready() -> void:
	G.danger.connect(_on_danger)


func setup_fixed() -> void:
	fixed.append({"pos": Vector3(-14, 0.3, 34.0), "role": "staff", "yaw": PI})
	fixed.append({"pos": Vector3(12, 0.3, 34.0), "role": "staff", "yaw": PI})
	fixed.append({"pos": Vector3(-100, 0.3, 46.5), "role": "staff", "yaw": 0.0})
	fixed.append({"pos": Vector3(14.5, 0.3, -133.5), "role": "staff", "yaw": PI})
	fixed.append({"pos": Vector3(78, 0.3, -114), "role": "cop", "yaw": 0.0})
	fixed.append({"pos": Vector3(92, 0.3, -114), "role": "cop", "yaw": 0.0})
	var gy: Vector3 = G.locations["Gang Yard"]
	for k in 5:
		fixed.append({"pos": gy + Vector3(-4 + k * 2.0, 0.2, (k % 2) * 2.0), "role": "gang", "yaw": randf() * TAU})
	for f in fixed:
		f["node"] = null
		f["dead_t"] = -1000.0
	# wildlife
	for k in 4:
		_animal("deer", Vector3(randf_range(-240, 80), 0, randf_range(-280, -230)))
	for k in 2:
		_animal("boar", Vector3(randf_range(-240, 80), 0, randf_range(-280, -230)))
	for k in 3:
		_animal("dog", Vector3(randf_range(-110, -50), 0, randf_range(-30, 30)))
	for k in 8:
		_animal("gull", Vector3(randf_range(-200, 120), 14, randf_range(190, 250)))
	for k in 14:
		_animal("fish", Vector3(-150 + randf_range(-25, 25), -6, 262 + randf_range(-20, 20)) if k < 8 else Vector3(-80 + randf_range(-15, 15), -2.5, 244 + randf_range(-8, 14)))
	for k in 2:
		_animal("shark", Vector3(randf_range(-200, 200), -4, randf_range(275, 330)))


func _animal(kind: String, pos: Vector3) -> void:
	var a := Animal.make(kind)
	G.main.add_child(a)
	if kind in ["deer", "boar", "dog"]:
		pos.y = max(G.height(pos.x, pos.z), 0.2) + 0.1
	a.global_position = pos
	a.home = pos
	animals.append(a)


func register(n: NPC, driver: bool) -> void:
	if driver:
		drivers.append(n)
	else:
		npcs.append(n)


func remove(n) -> void:
	npcs.erase(n)
	drivers.erase(n)
	if is_instance_valid(n):
		n.queue_free()


func spawn(role: String, pos: Vector3) -> NPC:
	var n := NPC.make(role)
	G.main.add_child(n)
	n.global_position = pos
	register(n, false)
	return n


func talk_target(_p):
	return null


func _on_danger(pos: Vector3, radius: float, source, kind: String) -> void:
	for n in npcs:
		if is_instance_valid(n) and not n.dead and n != source and n.global_position.distance_to(pos) < radius:
			n.on_danger(pos, source, kind)
	if kind != "horn":
		for a in animals:
			if is_instance_valid(a) and a.global_position.distance_to(pos) < radius:
				a.scare(pos)


func _physics_process(dt: float) -> void:
	frame += 1
	var p = G.player
	if p == null:
		return
	var pp: Vector3 = p.global_position
	var cp: Vector3 = G.cam.global_position
	# update with tiers
	for i in range(npcs.size() - 1, -1, -1):
		var n: NPC = npcs[i]
		if not is_instance_valid(n):
			npcs.remove_at(i)
			continue
		var d := n.global_position.distance_to(cp)
		if n.dead and (n.corpse_t > 45.0 or d > 160.0):
			remove(n)
			continue
		var is_fixed: bool = n.has_meta("fixed")
		if not n.dead and ((d > 170.0 and n.role == "civ" and not is_fixed) or n.global_position.y < -20.0 or (not enabled and n.role == "civ" and not is_fixed)):
			remove(n)
			continue
		if d < 55.0 or n.ai in ["combat", "return_car"]:
			n.update(dt, 0)
		elif d < 110.0:
			if (frame + i) % 3 == 0:
				n.update(dt * 3.0, 1)
		elif (frame + i) % 10 == 0:
			n.update(dt * 10.0, 2)
	for i in range(drivers.size() - 1, -1, -1):
		var dn: NPC = drivers[i]
		if not is_instance_valid(dn):
			drivers.remove_at(i)
			continue
		if dn.state != "vehicle":
			drivers.remove_at(i)
			npcs.append(dn)
			continue
		if dn.visible or (frame + i) % 20 == 0:
			dn.update(dt, 0)
	# spawn pedestrians
	spawn_t -= dt
	var want := max_peds
	if G.sky:
		if G.sky.is_night(): want = int(max_peds * 0.5)
		if G.sky.rain_amount > 0.4: want = int(want * 0.6)
	var civs := 0
	for n in npcs:
		if n.role == "civ" and not n.dead:
			civs += 1
	if enabled and spawn_t <= 0.0 and civs < want:
		spawn_t = 0.25
		_spawn_ped(pp)
	# fixed NPCs
	if frame % 30 == 0:
		for f in fixed:
			var near: bool = f.pos.distance_to(pp) < 150.0
			var node = f.node
			if node != null and (not is_instance_valid(node) or node.dead):
				if f.node != null:
					f.dead_t = G.time_now
				f.node = null
				node = null
			if node == null and near and G.time_now - f.dead_t > 180.0 and not G.cam.cam.is_position_in_frustum(f.pos + Vector3.UP):
				var n2 := spawn(f.role, f.pos)
				n2.set_meta("fixed", true)
				n2.rotation.y = f.yaw
				n2.home = f.pos
				n2.ai = "idle"
				if f.role == "cop":
					n2.ai = "wander"
					n2.route = {"type": "area", "rect": Rect2(f.pos.x - 14, f.pos.z - 3, 28, 6)}
				f.node = n2
			elif node != null and not near and node.ai in ["idle", "wander"]:
				remove(node)
				f.node = null
	# wildlife
	for a in animals:
		if not is_instance_valid(a):
			continue
		a.visible = wildlife_on
		if wildlife_on and a.global_position.distance_to(pp) < 170.0:
			a.update(dt)


func _spawn_ped(pp: Vector3) -> void:
	for attempt in 6:
		var pos: Vector3
		var route: Dictionary
		if randf() < 0.12:
			var x := randf_range(-200, 50)
			pos = Vector3(x, 0.3, randf_range(152, 168))
			route = {"type": "area", "rect": Rect2(-204, 150, 260, 19)}
		elif randf() < 0.1:
			var pr: Rect2 = G.world.block_rect(1, 2).grow(-6)
			pos = Vector3(randf_range(pr.position.x, pr.end.x), 0.4, randf_range(pr.position.y, pr.end.y))
			route = {"type": "area", "rect": pr}
		else:
			var i := randi() % 4
			var j := randi() % 4
			var c := randi() % 4
			var a: Vector3 = NPC.corner_pos(i, j, c)
			var b: Vector3 = NPC.corner_pos(i, j, (c + 1) % 4)
			pos = a.lerp(b, randf()) + Vector3.UP * 0.2
			var dirn := 1 if randf() < 0.5 else -1
			route = {"type": "block", "i": i, "j": j, "c": (c + 1) % 4 if dirn == 1 else c, "dir": dirn}
		var d := pos.distance_to(pp)
		if d < 35.0 or d > 140.0:
			continue
		if d < 100.0 and G.cam.cam.is_position_in_frustum(pos + Vector3.UP):
			continue
		var n := spawn("civ", pos)
		n.route = route
		n.move_speed = randf_range(1.2, 1.8)
		if randf() < 0.06:
			n.move_speed = 3.2
		return
