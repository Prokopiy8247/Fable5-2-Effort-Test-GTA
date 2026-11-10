extends Node3D
## PropSystem helper: the damageable owner of the batched static colliders of breakable / loose
## props. Bullets, melee sweeps and vehicle impacts reach it through Dmg.find_damageable(collider)
## and it forwards the hit (with collider + shape index when the caller supplies them) to the
## PropSystem, which resolves the exact instance. Solid scenery (trees, walls, set pieces) lives
## under a different parent, so it never becomes a "target" (no hit markers on walls).

var system: WeakRef = null


func apply_damage(info: Dictionary) -> void:
	if system == null:
		return
	var s: Variant = system.get_ref()
	if s != null and is_instance_valid(s) and (s as Node).has_method("_on_static_prop_damage"):
		(s as Node).call("_on_static_prop_damage", info)
