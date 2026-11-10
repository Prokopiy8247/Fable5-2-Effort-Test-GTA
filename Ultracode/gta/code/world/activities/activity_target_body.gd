extends StaticBody3D
## Hit collider of one pooled shooting-range target (activities module).
## No _process: it only forwards the Dmg contract (`apply_damage`) to the range controller,
## which owns every target in one loop. Combat.fire_hitscan finds it through Dmg.find_damageable.

var index: int = -1
var on_hit: Callable = Callable()


func apply_damage(info: Dictionary) -> void:
	if on_hit.is_valid():
		on_hit.call(index, info)
