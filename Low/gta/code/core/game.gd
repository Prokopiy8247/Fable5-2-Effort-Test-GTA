extends Node
# Autoload "G": global registry, helpers and shared state.

const WATER_Y := -0.8
const L_WORLD := 1
const L_VEH := 2
const L_CHAR := 4
const L_PROP := 8
const MODEL_DIR := "res://gta/generated/models/"

var main: Node
var player
var cam
var world
var hud
var fx
var audio
var wanted
var traffic
var pop
var sky
var menus
var roads
var save
var activities

var vehicles: Array = []
var humanoids: Array = []
var props: Array = []
var locations: Dictionary = {}   # name -> Vector3
var map_icons: Array = []        # [{pos, label, color}]
var money: int = 2500
var skills: Dictionary = {}
var waypoint = null
var invulnerable := false
var show_fps := false
var show_coords := false
var time_now := 0.0
var rng := RandomNumberGenerator.new()
var shared_mats: Dictionary = {}
var _models: Dictionary = {}
var _notes: Array = []

signal danger(pos, radius, source, kind)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	for s in Defs.SKILLS:
		skills[s] = 20.0
	for n in ["WinLit", "LampGlow", "TLRed", "TLYellow", "TLGreen"]:
		var m := StandardMaterial3D.new()
		m.resource_name = n
		m.roughness = 0.3
		m.emission_enabled = true
		m.emission_energy_multiplier = 0.0
		shared_mats[n] = m
	shared_mats["WinLit"].albedo_color = Color(0.55, 0.72, 0.85)
	shared_mats["WinLit"].emission = Color(1.0, 0.85, 0.55)
	shared_mats["LampGlow"].albedo_color = Color(1.0, 0.9, 0.7)
	shared_mats["LampGlow"].emission = Color(1.0, 0.85, 0.55)
	shared_mats["TLRed"].albedo_color = Color(0.3, 0.05, 0.05)
	shared_mats["TLRed"].emission = Color(1, 0.1, 0.1)
	shared_mats["TLYellow"].albedo_color = Color(0.3, 0.25, 0.05)
	shared_mats["TLYellow"].emission = Color(1, 0.8, 0.1)
	shared_mats["TLGreen"].albedo_color = Color(0.05, 0.3, 0.1)
	shared_mats["TLGreen"].emission = Color(0.1, 1, 0.3)
	for n in ["TLRed", "TLYellow", "TLGreen"]:
		var b: StandardMaterial3D = shared_mats[n].duplicate()
		b.resource_name = n + "B"
		shared_mats[n + "B"] = b


func _process(delta: float) -> void:
	if not get_tree().paused:
		time_now += delta


func model(path: String) -> Node3D:
	if not _models.has(path):
		var ps = load(MODEL_DIR + path + ".glb")
		if ps == null:
			push_error("Missing model " + path)
			_models[path] = null
		else:
			var inst = ps.instantiate()
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = mi.mesh
				for i in mesh.get_surface_count():
					var mat = mesh.surface_get_material(i)
					if mat and shared_mats.has(mat.resource_name):
						mesh.surface_set_material(i, shared_mats[mat.resource_name])
					elif mat is StandardMaterial3D and mat.emission_enabled:
						mat.emission_energy_multiplier = min(mat.emission_energy_multiplier, 2.5)
			inst.free()
			_models[path] = ps
	var p = _models[path]
	if p == null:
		return Node3D.new()
	return p.instantiate()


func part(root: Node, pname: String) -> Node3D:
	var suffix := "__" + pname
	for c in root.find_children("*", "Node3D", true, false):
		if String(c.name).ends_with(suffix):
			return c
	return null


func tint(root: Node, mat_name: String, mat: Material) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m = mesh.surface_get_material(i)
			if m and m.resource_name == mat_name:
				mi.set_surface_override_material(i, mat)


func flat_mat(c: Color, rough := 0.7, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func col(a: Array) -> Color:
	return Color(a[0], a[1], a[2])


func notify(text: String, dur := 3.5) -> void:
	_notes.append({"t": text, "until": Time.get_ticks_msec() / 1000.0 + dur})
	if _notes.size() > 5:
		_notes.pop_front()


func height(x: float, z: float) -> float:
	return WorldBuilder.height(x, z)


func add_money(n: int) -> void:
	money = max(0, money + n)


func spend(n: int) -> bool:
	if money < n:
		notify("Not enough cash ($%d needed)" % n)
		if audio:
			audio.ui("deny")
		return false
	money -= n
	if audio:
		audio.ui("buy")
	return true


func ray(from: Vector3, to: Vector3, mask: int, exclude: Array = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var ex: Array[RID] = []
	for e in exclude:
		if e and is_instance_valid(e):
			ex.append(e.get_rid())
	q.exclude = ex
	return main.get_world_3d().direct_space_state.intersect_ray(q)


func los(a: Vector3, b: Vector3, exclude: Array = []) -> bool:
	return ray(a, b, L_WORLD, exclude).is_empty()


func skill(sname: String) -> float:
	return skills.get(sname, 0.0) / 100.0


func skill_gain(sname: String, amt: float) -> void:
	var before: float = skills[sname]
	skills[sname] = min(100.0, before + amt)
	if int(skills[sname] / 10.0) > int(before / 10.0):
		notify("%s skill increased: %d%%" % [sname.capitalize(), int(skills[sname])])


func emit_danger(pos: Vector3, radius: float, source, kind: String) -> void:
	danger.emit(pos, radius, source, kind)


func damage_target(collider, amount: float, attacker, pos: Vector3, dir: Vector3, kind: String) -> Node:
	var n = collider
	while n and not n.has_method("take_damage"):
		n = n.get_parent()
	if n:
		n.take_damage(amount, attacker, pos, dir, kind)
	return n


func explode(pos: Vector3, radius: float, dmg: float, attacker) -> void:
	fx.explosion(pos, radius)
	emit_danger(pos, 90.0, attacker, "explosion")
	if attacker == player and wanted:
		wanted.crime("explosion", pos)
	for list in [humanoids.duplicate(), vehicles.duplicate(), props.duplicate()]:
		for o in list:
			if not is_instance_valid(o):
				continue
			var d: float = o.global_position.distance_to(pos)
			if d < radius:
				var f := 1.0 - d / radius
				var dir: Vector3 = (o.global_position + Vector3.UP * 0.8 - pos).normalized()
				o.take_damage(dmg * f, attacker, o.global_position, dir, "explosion")
				if o is RigidBody3D:
					o.apply_central_impulse(dir * f * min(o.mass, 2500.0) * 9.0)
	if cam:
		cam.shake(clamp(1.2 - cam.global_position.distance_to(pos) / 60.0, 0.0, 1.0))


func district_at(p: Vector3) -> String:
	if p.y < WATER_Y - 0.3:
		return "Sea"
	if p.x > 130:
		return "Airport"
	if p.z > 128:
		return "Waterfront"
	if p.z < -212:
		return "Northridge Hills"
	if p.x < -208:
		return "West Side"
	var ci := clampi(int((p.x + 200.0) / 80.0), 0, 3)
	var ri := clampi(int((p.z + 200.0) / 80.0), 0, 3)
	var d: String = Defs.DISTRICTS[ci][ri]
	return {"industrial": "Ironworks", "residential": "Maple Heights", "park": "Central Park", "mixed": "Midtown", "downtown": "Downtown", "commercial": "Harbor Row"}[d]
