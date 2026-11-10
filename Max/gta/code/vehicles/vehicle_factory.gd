class_name VehicleFactory
extends RefCounted
## Creates fully configured vehicles from VehicleDB ids.

static var _rng := RandomNumberGenerator.new()
static var count := 0

static func root() -> Node:
	if Game.main == null:
		return null
	var e := Game.main.get_node_or_null("Entities/Vehicles")
	return e if e != null else Game.main

## opts: paint (Color), paint_b (Color), tag (String), engine (bool), personal (bool), mods (Dictionary)
static func spawn(id: String, pos: Vector3, yaw := 0.0, opts: Dictionary = {}) -> Vehicle:
	if not VehicleDB.exists(id):
		push_warning("VehicleFactory: unknown vehicle " + id)
		return null
	var d := VehicleDB.get_v(id)
	var v: Vehicle
	match d.get("kind", &"car"):
		&"boat": v = Boat.new()
		&"heli": v = Heli.new()
		&"plane": v = Airplane.new()
		_: v = Car.new()
	var paints: Array = d.get("paint", [])
	if paints.is_empty():
		v.paint_a = opts.get("paint", VehicleDB.random_paint(_rng))
		v.paint_b = opts.get("paint_b", Color(0.08, 0.08, 0.09))
	v.setup(id)
	if opts.has("paint") and not paints.is_empty():
		v.set_paint(opts["paint"], opts.get("paint_b", v.paint_b))
	v.owner_tag = String(opts.get("tag", ""))
	v.personal = bool(opts.get("personal", false))
	var parent := root()
	parent.add_child(v)
	v.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.25 if d.get("kind", &"car") != &"boat" else 0.1, 0))
	if opts.has("mods"):
		VehicleMods.apply_all(v, opts["mods"])
	count += 1
	return v

## Number of live (non-destroyed) vehicles in the world.
static func alive_count() -> int:
	var n := 0
	for v in Game.get_tree().get_nodes_in_group(&"vehicles"):
		if not (v as Vehicle).destroyed:
			n += 1
	return n
