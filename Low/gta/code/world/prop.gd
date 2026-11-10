class_name Prop
extends RigidBody3D
# Knockable / destructible street prop. Frozen (static) until a vehicle, bullet or blast disturbs it.

const TYPES := {
	"prop_cone": {"box": Vector3(0.36, 0.6, 0.36), "mass": 3.0, "min": 0.0},
	"prop_bin": {"box": Vector3(0.6, 1.0, 0.6), "mass": 12.0, "min": 0.0},
	"prop_crate": {"box": Vector3(1, 1, 1), "mass": 25.0, "min": 0.0, "hp": 60.0, "y": 0.5},
	"prop_barrel": {"box": Vector3(0.6, 0.9, 0.6), "mass": 30.0, "min": 0.0},
	"prop_barrel_explosive": {"box": Vector3(0.6, 0.9, 0.6), "mass": 30.0, "min": 0.0, "hp": 25.0, "explosive": true},
	"prop_mailbox": {"box": Vector3(0.5, 1.25, 0.5), "mass": 30.0, "min": 3.0},
	"prop_hydrant": {"box": Vector3(0.36, 0.75, 0.36), "mass": 40.0, "min": 5.0},
	"prop_bench": {"box": Vector3(1.8, 0.9, 0.55), "mass": 40.0, "min": 4.0},
	"prop_sign_stop": {"box": Vector3(0.3, 2.7, 0.3), "mass": 18.0, "min": 3.0},
	"prop_sign_speed": {"box": Vector3(0.3, 2.7, 0.3), "mass": 18.0, "min": 3.0},
	"prop_street_lamp": {"box": Vector3(0.34, 7.4, 0.34), "mass": 160.0, "min": 11.0},
	"prop_traffic_light": {"box": Vector3(0.34, 5.6, 0.34), "mass": 180.0, "min": 11.0},
	"prop_fence": {"box": Vector3(3.0, 1.9, 0.1), "mass": 35.0, "min": 5.0},
	"prop_utility_box": {"box": Vector3(0.9, 1.3, 0.5), "mass": 80.0, "min": 7.0},
	"prop_dumpster": {"box": Vector3(2.3, 1.35, 1.3), "mass": 320.0, "min": 2.0},
	"prop_pallet": {"box": Vector3(1.2, 0.14, 1.2), "mass": 15.0, "min": 0.0},
	"prop_tire_stack": {"box": Vector3(0.72, 0.75, 0.72), "mass": 25.0, "min": 0.0},
	"prop_roadblock": {"box": Vector3(3.2, 1.2, 0.7), "mass": 30.0, "min": 2.0},
	"prop_picnic_table": {"box": Vector3(1.8, 0.8, 1.8), "mass": 45.0, "min": 3.0},
	"prop_vending": {"box": Vector3(1.0, 1.9, 0.8), "mass": 150.0, "min": 6.0},
	"prop_umbrella": {"box": Vector3(0.6, 2.2, 0.6), "mass": 8.0, "min": 0.0},
	"prop_bollard": {"box": Vector3(0.2, 0.85, 0.2), "mass": 60.0, "min": 13.0},
	"prop_target": {"box": Vector3(0.8, 1.9, 0.3), "mass": 20.0, "min": 2.0},
}

var kind := ""
var min_speed := 0.0
var hp := -1.0
var explosive := false
var awake := false
var home: Transform3D
var cell: Vector2i
var on_hit: Callable


static func make(kind_name: String) -> Prop:
	var t: Dictionary = TYPES[kind_name]
	var p := Prop.new()
	p.kind = kind_name
	p.mass = t.mass
	p.min_speed = t.min
	p.hp = t.get("hp", -1.0)
	p.explosive = t.get("explosive", false)
	p.collision_layer = G.L_PROP
	p.collision_mask = G.L_WORLD | G.L_VEH | G.L_PROP
	p.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	p.freeze = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = t.box
	cs.shape = bs
	cs.position.y = t.box.y / 2.0
	p.add_child(cs)
	p.add_child(G.model("props/" + kind_name))
	p.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	p.center_of_mass = Vector3(0, t.box.y * 0.4, 0)
	return p


func wake(impulse := Vector3.ZERO) -> void:
	if not awake:
		awake = true
		freeze = false
		if G.world:
			G.world.prop_woke(self)
	if impulse != Vector3.ZERO:
		apply_central_impulse(impulse)


func take_damage(amount: float, attacker, pos: Vector3, dir: Vector3, dkind: String) -> void:
	if on_hit.is_valid():
		on_hit.call(self, pos)
	if dkind == "bullet" and min_speed > 6.0:
		return
	wake(dir * min(amount, 60.0) * 0.6)
	if hp > 0.0:
		hp -= amount
		if hp <= 0.0:
			hp = -1.0
			if explosive:
				explosive = false
				G.props.erase(self)
				var p := global_position + Vector3.UP * 0.5
				queue_free()
				G.explode(p, 9.0, 260.0, attacker)
			else:
				G.fx.debris(global_position + Vector3.UP * 0.5, Color(0.5, 0.33, 0.2))
				G.props.erase(self)
				queue_free()
