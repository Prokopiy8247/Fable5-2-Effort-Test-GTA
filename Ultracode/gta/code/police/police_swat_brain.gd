class_name PoliceSwatBrain
extends PoliceOfficerBrain
## Tactical officer brain (archetype "police_swat", spawned four to a swat_van at 4-5 stars).
## Same layering as the officer brain, with: armour (more health, the archetype's 100 armour on top),
## carbine / SMG, aggressive combat rules (short cover waits, early advances, flanking), no arrests,
## and PAIRS: the system gives every tactical officer a `buddy`; a member that drifts too far from its
## buddy while not in cover closes up first (moves as a fire team), and the pair flanks to opposite
## sides when the target hides.

const PAIR_MAX_DIST := 13.0
const SWAT_HEALTH := 150.0

var buddy: Node3D = null
var flank_side: float = 1.0


func _on_spawned(n: Node3D, _data: Dictionary) -> void:
	is_swat = true
	aggression = _rng.randf_range(0.78, 0.95)
	n.set("max_health", SWAT_HEALTH)
	n.set("health", SWAT_HEALTH)
	var w := str(n.get("weapon_id"))
	if w != "":
		default_weapon = w
	else:
		default_weapon = "carbine"


func _can_arrest(_cfg: Dictionary) -> bool:
	return false


func _combat_rules(lethal: bool, hold: bool, _high: bool = false) -> Dictionary:
	return {"lethal": lethal, "aggression": aggression, "accuracy": 1.1, "use_cover": lethal,
			"hold_fire": hold, "melee": false, "flank": true, "engage_distance": 12.0 if lethal else 4.0,
			"cover_radius": 16.0, "retreat_health": 0.2}


## Fire-team cohesion: catch up with the buddy before re-engaging (unless the target is in sight
## and close, or we are already in cover).
func _pre_engage(n: Node3D, p: Node3D, delta: float) -> bool:
	if buddy == null or not is_instance_valid(buddy) or bool(buddy.get("is_dead")) or buddy.get("current_vehicle") != null:
		return false
	var c := _combat()
	if c != null:
		var st := str(c.call("get_state_name"))
		if st == "cover" or st == "peek" or st == "move_to_cover":
			return false
	var bd := _flat(n.global_position, buddy.global_position)
	if bd <= PAIR_MAX_DIST:
		return false
	if sees and _flat(n.global_position, p.global_position) < 20.0:
		return false
	var to_target := p.global_position - buddy.global_position
	to_target.y = 0.0
	var side := Vector3(-to_target.z, 0.0, to_target.x).normalized() * flank_side * 2.5 if to_target.length() > 0.1 else Vector3.ZERO
	_repath -= delta
	if _repath <= 0.0 or not bool(n.call("is_moving")):
		_repath = 0.8
		n.call("move_to", buddy.global_position + side, "sprint")
	n.call("stop_aiming")
	n.set("state_tag", "police_swat_regroup")
	return true
