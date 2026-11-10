class_name Pickup
extends Area3D
## One collectable in the world (weapon, ammo, health, armor, cash, parachute, scuba gear).
##
## A Pickup is passive data + visuals: the PickupSystem ("pickups" world system) creates it,
## animates it (slow spin + bob, one loop for all pickups), decides what collecting it gives and
## handles respawn / despawn. Create pickups through
##     Game.get_system("pickups").spawn_pickup(kind, id, amount, position)
##
## Collision: layer Layers.PICKUP, mask PLAYER | VEHICLE; a body in group "player" (or a vehicle
## the player drives) that touches it collects it. `position` of the node is the GROUND point,
## the model hovers HOVER metres above it.

const KINDS: Array[String] = ["weapon", "ammo", "health", "armor", "cash", "parachute", "scuba"]
const HOVER := 0.6
const TOUCH_RADIUS := 0.95
const BAG_CASH := 400               ## cash pickups of at least this much show the bag model
const MODEL_ROOT := "res://gta/generated/models"
const COLORS := {
	"weapon": Color(0.99, 0.80, 0.25), "ammo": Color(0.97, 0.56, 0.22), "health": Color(0.30, 0.92, 0.55),
	"armor": Color(0.32, 0.62, 1.0), "cash": Color(0.50, 0.92, 0.36), "parachute": Color(0.86, 0.84, 1.0),
	"scuba": Color(0.20, 0.86, 0.96),
}
const HALO_SHADER := "
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(0.55, 0.8, r) * (1.0 - smoothstep(0.8, 1.0, r));
	float core = (1.0 - smoothstep(0.0, 0.75, r)) * 0.22;
	float pulse = 0.75 + 0.25 * sin(TIME * 3.0);
	ALBEDO = tint.rgb;
	ALPHA = (ring * pulse + core) * tint.a;
}
"

static var _scene_cache: Dictionary = {}       ## "kind:id" -> PackedScene or null
static var _halo_mesh: QuadMesh = null
static var _halo_shader: Shader = null
static var _halo_materials: Dictionary = {}    ## kind -> ShaderMaterial

var kind: String = "cash"
var item_id: String = ""
var amount: int = 0
var respawn_time: float = 0.0       ## > 0: comes back after this many seconds (world pickups)
var lifetime: float = 0.0           ## > 0: disappears after this many seconds (dropped pickups)
var available: bool = true
var dropped: bool = false
var age: float = 0.0
var respawn_left: float = 0.0
var phase: float = 0.0
var visual: Node3D = null           ## spinning / bobbing part
var halo: MeshInstance3D = null
var has_model: bool = false


## Candidate GLB paths for a pickup, most specific first.
static func model_candidates(p_kind: String, p_id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if p_kind == "weapon":
		out.append("%s/weapons/%s.glb" % [MODEL_ROOT, p_id])
		return out
	var names: PackedStringArray = []
	if p_id != "":
		names.append("%s_%s" % [p_kind, p_id])
		names.append(p_id)
	names.append(p_kind)
	match p_kind:
		"ammo": names.append_array(PackedStringArray(["ammo_box", "ammo_crate"]))
		"health": names.append_array(PackedStringArray(["medkit", "health_kit", "first_aid"]))
		"armor": names.append_array(PackedStringArray(["body_armor", "armor_vest", "vest"]))
		"cash": names.append_array(PackedStringArray(["cash_stack", "money", "cash_bundle"]))
		"parachute": names.append_array(PackedStringArray(["parachute_pack", "parachute_bag"]))
		"scuba": names.append_array(PackedStringArray(["scuba_tank", "scuba_gear"]))
	for n in names:
		out.append("%s/props/pickups/%s.glb" % [MODEL_ROOT, n])
	for n in names:
		out.append("%s/props/pickup_%s.glb" % [MODEL_ROOT, n])
		out.append("%s/props/%s.glb" % [MODEL_ROOT, n])
	return out


static func find_model(p_kind: String, p_id: String) -> PackedScene:
	var key := "%s:%s" % [p_kind, p_id]
	if _scene_cache.has(key):
		return _scene_cache[key]
	var scene: PackedScene = null
	for path in model_candidates(p_kind, p_id):
		if ResourceLoader.exists(path):
			scene = load(path) as PackedScene
			if scene != null:
				break
	_scene_cache[key] = scene
	return scene


static func clear_cache() -> void:
	_scene_cache.clear()


func configure(p_kind: String, p_id: String, p_amount: int) -> void:
	kind = p_kind
	item_id = p_id
	amount = p_amount
	name = "Pickup_%s_%s" % [kind, item_id if item_id != "" else "item"]
	add_to_group("pickup")
	collision_layer = Layers.PICKUP
	collision_mask = Layers.PLAYER | Layers.VEHICLE
	monitoring = true
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = TOUCH_RADIUS
	shape.shape = sphere
	shape.position = Vector3(0.0, 0.75, 0.0)
	add_child(shape)
	phase = randf() * TAU
	_build_visual()


func get_color() -> Color:
	return COLORS.get(kind, Color.WHITE)


## World position of the hovering item (for sparkle FX).
func get_item_position() -> Vector3:
	return global_position + Vector3.UP * HOVER


func set_available(on: bool) -> void:
	available = on
	visible = on
	set_deferred("monitoring", on)
	if on:
		age = 0.0


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	visual.position = Vector3(0.0, HOVER, 0.0)
	add_child(visual)
	# big money comes in a bag
	var scene := find_model(kind, "cash_bag" if (kind == "cash" and amount >= BAG_CASH) else item_id)
	if scene != null:
		var model := scene.instantiate() as Node3D
		if model != null:
			has_model = true
			model.name = "Model"
			var size := 2.0 if (kind == "cash" and amount < BAG_CASH) else 1.5
			var shown: Array[String] = []
			if kind == "weapon":
				# weapons have their origin at the grip: spin them about the middle of the body,
				# barrel tipped up a little
				var spec := WeaponSpec.resolve(item_id)
				var small := spec != null and (spec.slot == "handgun" or spec.slot == "thrown" or item_id == "knife")
				size = 1.7 if small else 1.25
				if spec != null:
					shown = spec.builtin_nodes
				var tilt := Node3D.new()
				tilt.name = "Tilt"
				tilt.rotation.x = deg_to_rad(14.0)
				visual.add_child(tilt)
				tilt.add_child(model)
				var body := model.find_child("Body", true, false) as MeshInstance3D
				if body != null and body.mesh != null:
					model.position = -(body.transform * body.mesh.get_aabb().get_center()) * size
			else:
				visual.add_child(model)
			model.scale = Vector3.ONE * size
			for n in model.find_children("*", "Node3D", true, false):
				var n3 := n as Node3D
				if (n3.name.begins_with("Att_") and not shown.has(str(n3.name))) or n3.name.begins_with("Col_"):
					n3.visible = false
			for g in model.find_children("*", "GeometryInstance3D", true, false):
				var gi := g as GeometryInstance3D
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				gi.visibility_range_end = 110.0
	halo = MeshInstance3D.new()
	halo.name = "Halo"
	halo.mesh = _get_halo_mesh()
	halo.material_override = _get_halo_material(kind)
	halo.position = Vector3(0.0, 0.05, 0.0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.visibility_range_end = 70.0
	add_child(halo)


static func _get_halo_mesh() -> QuadMesh:
	if _halo_mesh == null:
		_halo_mesh = QuadMesh.new()
		_halo_mesh.size = Vector2(1.25, 1.25)
		_halo_mesh.orientation = PlaneMesh.FACE_Y
	return _halo_mesh


static func _get_halo_material(p_kind: String) -> ShaderMaterial:
	if _halo_materials.has(p_kind):
		return _halo_materials[p_kind]
	if _halo_shader == null:
		_halo_shader = Shader.new()
		_halo_shader.code = HALO_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _halo_shader
	var c: Color = COLORS.get(p_kind, Color.WHITE)
	mat.set_shader_parameter("tint", Color(c.r, c.g, c.b, 0.7))
	_halo_materials[p_kind] = mat
	return mat
