class_name WorldProp
extends RigidBody3D
## A physical street prop (WORLD DRESSING). Pooled by PropSystem: idle props are MultiMesh entries
## with batched static colliders; when one is hit hard enough PropSystem hands its slot to a
## WorldProp (this body) and applies the impulse. Loose props near the player (cones, crates,
## barrels ...) are sleeping WorldProps too. Bodies spawned through PropSystem.spawn_prop() are
## WorldProps that belong to the caller.
##
## No per-frame script: PropSystem's manager loop checks every active body a few times per second
## (sleep, distance, lifetime). The body only forwards damage and reports its first hard landing.

## Asset id (manifest id).
var prop_id: String = ""
## Index of the dressing instance this body stands in for, -1 for spawned / loose-free bodies.
var source_index: int = -1
## Hit points left (explosive props detonate at 0).
var hp: float = 100.0
var explosive: bool = false
## "active" (knocked over), "loose" (sleeping near the player), "spawned" (owned by a caller).
var role: String = "active"
## Game-time second the body was (re)activated.
var activated_at: float = 0.0
var surface: String = "metal"
var instigator: Node = null

var mesh_instance: MeshInstance3D
var _shapes: Array[CollisionShape3D] = []
var _system: WeakRef = null
var _landed := false


func _init() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	collision_layer = Layers.PROP
	collision_mask = Layers.PROP_MASK
	continuous_cd = false
	can_sleep = true
	add_to_group("prop")
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)


## Sets everything up for one asset. `shapes` = Array of [Shape3D, Transform3D] (asset space),
## `vis` = {"mesh": Mesh, "xf": Transform3D}.
func configure(system: Node, id: String, vis: Dictionary, shapes: Array, body_mass: float,
		surf: String, cast_shadow: bool) -> void:
	_system = weakref(system) if system != null else null
	prop_id = id
	surface = surf
	mass = maxf(body_mass, 0.5)
	set_meta(&"surface", surf)
	set_meta(&"prop_id", id)
	mesh_instance.mesh = vis.get("mesh", null)
	mesh_instance.transform = vis.get("xf", Transform3D.IDENTITY)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	while _shapes.size() < shapes.size():
		var cs := CollisionShape3D.new()
		add_child(cs)
		_shapes.append(cs)
	for i in _shapes.size():
		var cs := _shapes[i]
		if i < shapes.size():
			cs.shape = shapes[i][0]
			cs.transform = shapes[i][1]
			cs.disabled = false
		else:
			cs.shape = null
			cs.disabled = true
	_landed = false
	instigator = null


## Puts the body into or out of service (pooled bodies stay in the tree, frozen and hidden).
func set_in_use(on: bool) -> void:
	visible = on
	freeze = not on
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = Layers.PROP if on else 0
	collision_mask = Layers.PROP_MASK if on else 0
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if not on:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		source_index = -1
		explosive = false
		instigator = null


func apply_damage(info: Dictionary) -> void:
	var sys := _get_system()
	if sys != null and sys.has_method("_on_world_prop_damage"):
		sys.call("_on_world_prop_damage", self, info)
		return
	# orphaned (spawned while no PropSystem exists): at least react physically
	var imp := float(info.get("impulse", 0.0))
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	if imp > 0.0 and dir != Vector3.ZERO:
		apply_impulse(dir.normalized() * minf(imp, mass * 12.0), Vector3(info.get("position", global_position)) - global_position)


func _get_system() -> Node:
	if _system == null:
		return null
	var s: Variant = _system.get_ref()
	if s == null or not is_instance_valid(s):
		return null
	return s as Node


func _on_body_entered(other: Node) -> void:
	if _landed or not visible:
		return
	var sys := _get_system()
	if sys == null or not sys.has_method("_on_world_prop_contact"):
		return
	if linear_velocity.length_squared() < 4.0:
		return
	_landed = true
	sys.call("_on_world_prop_contact", self, other)
