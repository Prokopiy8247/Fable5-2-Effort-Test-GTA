class_name Dmg
extends RefCounted
## Shared damage contract.
##
## A "damageable" is ANY node that implements:
##     func apply_damage(info: Dictionary) -> void
## Hits usually land on a physics body; use Dmg.find_damageable(collider) to walk up to the
## damageable owner (for example a wheel/door collider that belongs to a vehicle).
##
## info keys (all optional except amount / type):
##   amount: float          damage in hit points (player and NPCs have 100 hp by default)
##   type: String           one of TYPES
##   instigator: Node       who caused it (player, an NPC, a vehicle ...) or null
##   position: Vector3      world hit position
##   normal: Vector3        world surface normal at the hit
##   direction: Vector3     world direction the damage travels (for knock-back / ragdoll)
##   impulse: float         physical push strength (N*s) applied along direction
##   weapon_id: String      Registry "weapons" id, or ""
##   headshot: bool         true if the hit landed on the head zone
##   zone: String           "head" | "torso" | "limb" | ""
##   silent: bool           true for suppressed weapons / stealth takedowns

const TYPES := ["bullet", "melee", "explosion", "fire", "fall", "collision", "drown", "vehicle", "bite", "generic"]


static func make(amount: float, type: String = "generic", instigator: Node = null,
		position: Vector3 = Vector3.ZERO, direction: Vector3 = Vector3.ZERO, extra: Dictionary = {}) -> Dictionary:
	var info := {
		"amount": amount,
		"type": type,
		"instigator": instigator,
		"position": position,
		"normal": Vector3.UP,
		"direction": direction,
		"impulse": 0.0,
		"weapon_id": "",
		"headshot": false,
		"zone": "",
		"silent": false,
	}
	for k in extra:
		info[k] = extra[k]
	return info


## Walk up from a collider to the first ancestor (or itself) implementing apply_damage().
static func find_damageable(node: Object) -> Node:
	var n := node as Node
	var guard := 0
	while n != null and guard < 12:
		if n.has_method("apply_damage"):
			return n
		n = n.get_parent()
		guard += 1
	return null


## Apply damage to whatever owns `target`. Returns true if something took the damage.
static func apply(target: Object, info: Dictionary) -> bool:
	var d := find_damageable(target)
	if d == null or not is_instance_valid(d):
		return false
	d.apply_damage(info)
	return true


## Hit zone for a standing humanoid whose origin is at its feet (height ~1.8 m).
static func zone_for_humanoid(character: Node3D, hit_position: Vector3, height: float = 1.8) -> String:
	var local_y := hit_position.y - character.global_position.y
	if local_y > height * 0.83:
		return "head"
	if local_y > height * 0.45:
		return "torso"
	return "limb"


static func is_player(node: Object) -> bool:
	return node is Node and (node as Node).is_in_group("player")


## True if the instigator is the player or a vehicle currently driven by the player.
static func caused_by_player(info: Dictionary) -> bool:
	var who: Variant = info.get("instigator", null)
	if who == null or not is_instance_valid(who):
		return false
	if is_player(who):
		return true
	if who is Node and (who as Node).is_in_group("vehicle"):
		return (who as Node).get("is_player_driven") == true
	return false
