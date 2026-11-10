class_name AiBrainGang
extends Node
## Brain of gang members. Groups hang out at the world's "gang" spawn points; a member is
## provoked by being attacked, shots fired close by, a weapon aimed at it, or (spawn option
## "hostile") by spotting the player. Provocation spreads to the members of the same group / nearby
## gang members. Combat goes through the shared AiBrainCombat helper (cover, peek, bursts, reload,
## advance / flank, melee, retreat). The group calms down and walks back home when the enemy is
## dead or lost.

enum { HANG, COMBAT, RETURN }
const MODE_NAMES := ["hang", "combat", "return"]
const ALLY_RADIUS := 35.0
const PROVOKE_SHOT_RADIUS := 28.0

var mode: int = HANG
var t: float = 0.0
var target: Node3D = null
var home: Vector3 = Vector3.INF
var group_id: int = -1
var aggression: float = 0.6
var combat := AiBrainCombat.new()
var last_status: String = ""
var _shift_t: float = 0.0
var _rng := RandomNumberGenerator.new()


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func on_event(npc: Node, event: String, data: Dictionary) -> void:
	var n := npc as Node3D
	if n == null:
		return
	match event:
		"spawned":
			_rng.seed = npc.get_instance_id() ^ 0x1234567
			var h: Variant = data.get("home", null)
			home = h if h is Vector3 else n.global_position
			group_id = int(data.get("group", -1))
			aggression = _rng.randf_range(0.45, 0.8)
			_shift_t = _rng.randf_range(2.0, 8.0)
			npc.set("state_tag", "hang")
		"damaged":
			var att: Variant = data.get("attacker", null)
			if att is Node3D and is_instance_valid(att):
				provoke(npc, att as Node3D, true)
		"threatened":
			var by: Variant = data.get("by", null)
			if by is Node3D and is_instance_valid(by):
				provoke(npc, by as Node3D, true)
		"noise":
			var kind := str(data.get("kind", ""))
			var inst: Variant = data.get("instigator", null)
			if (kind == "gunshot" or kind == "explosion") and float(data.get("distance", 99.0)) < PROVOKE_SHOT_RADIUS \
					and inst is Node3D and is_instance_valid(inst) and inst != npc and not (inst as Node).is_in_group("gang"):
				provoke(npc, inst as Node3D, true)
		"ally_attacked":
			var a: Variant = data.get("attacker", null)
			if a is Node3D and is_instance_valid(a):
				provoke(npc, a as Node3D, false)
		"bumped":
			var by2: Variant = data.get("by", null)
			if mode == HANG and by2 is Node3D and is_instance_valid(by2) and (by2 as Node).is_in_group("player"):
				npc.call("face_position", (by2 as Node3D).global_position)
				npc.set("look_target", (by2 as Node3D).global_position + Vector3(0.0, 1.5, 0.0))
				npc.call("play_action", "hit_react", 0.35)
				if bool(npc.get("hostile")):
					provoke(npc, by2 as Node3D, true)
		"reset":
			if mode == COMBAT:
				_calm(npc)


## Start fighting `who` (and tell the group when `spread`).
func provoke(npc: Node, who: Node3D, spread: bool) -> void:
	if who == null or not is_instance_valid(who) or who == npc or who.is_in_group("gang"):
		return
	if NpcBase.is_dead_node(who):
		return
	var was_fighting := mode == COMBAT
	if not was_fighting or target == null or not is_instance_valid(target) or NpcBase.is_dead_node(target):
		target = who
		combat.reset()
	mode = COMBAT
	t = 0.0
	npc.set("state_tag", "combat")
	npc.set("gesture", 0.0)
	npc.set("look_target", Vector3.INF)
	if spread and not was_fighting:
		_alert_allies(npc, who)


func _alert_allies(npc: Node, who: Node3D) -> void:
	var n := npc as Node3D
	for m in npc.get_tree().get_nodes_in_group("gang"):
		if m == npc or not is_instance_valid(m) or not (m is Node3D) or m.get("is_dead") == true:
			continue
		var b: Variant = m.get("brain")
		if not (b is Node) or not is_instance_valid(b):
			continue
		var gid: Variant = (b as Node).get("group_id")
		var same_group := group_id >= 0 and gid is int and int(gid) == group_id
		if same_group or (m as Node3D).global_position.distance_to(n.global_position) < ALLY_RADIUS:
			if (b as Node).has_method("on_event"):
				(b as Node).call("on_event", m, "ally_attacked", {"attacker": who, "ally": npc})


func think(npc: Node, delta: float) -> void:
	var n := npc as Node3D
	if n == null or npc.get("is_dead") == true:
		return
	t += delta
	match mode:
		HANG:
			_hang(npc, delta)
		COMBAT:
			if target == null or not is_instance_valid(target) or NpcBase.is_dead_node(target):
				_calm(npc)
				return
			last_status = combat.tick(n, target, delta, {"lethal": true, "aggression": aggression,
					"accuracy": 1.0, "use_cover": true, "flank": true})
			npc.set("state_tag", "combat")
			if last_status == "no_target" or last_status == "lost":
				_calm(npc)
			elif n.global_position.distance_to(target.global_position) > 95.0 and combat.unseen_time > 12.0:
				_calm(npc)
		RETURN:
			npc.set("state_tag", "return")
			if bool(npc.call("has_arrived", 2.5)) or (not bool(npc.call("is_moving")) and t > 2.0):
				mode = HANG
				t = 0.0
				npc.call("stop_moving")


func _hang(npc: Node, delta: float) -> void:
	var n := npc as Node3D
	# hostile groups attack the player once they notice him
	if bool(npc.get("hostile")):
		var p := Game.player
		if p != null and is_instance_valid(p) and bool(npc.get("is_alerted")) \
				and p.global_position.distance_to(n.global_position) < 32.0:
			provoke(npc, p, true)
			return
	if float(npc.get("threatened_time")) > 0.4:
		var by: Variant = npc.get("threatened_by")
		if by is Node3D and is_instance_valid(by):
			provoke(npc, by as Node3D, true)
			return
	_shift_t -= delta
	if home == Vector3.INF:
		home = n.global_position
	if _shift_t <= 0.0:
		_shift_t = _rng.randf_range(5.0, 14.0)
		if n.global_position.distance_to(home) > 4.5:
			npc.call("move_to", home, "walk")
		elif _rng.randf() < 0.4:
			var off := Vector3(_rng.randf_range(-2.5, 2.5), 0.0, _rng.randf_range(-2.5, 2.5))
			npc.call("move_to", home + off, "walk")
	if not bool(npc.call("is_moving")):
		# face the group centre and chat
		npc.call("face_position", home)
		var talking := fmod(t + float(npc.get_instance_id() % 7), 7.0) < 3.0
		npc.set("gesture", 0.8 if talking else 0.1)
		var p2 := Game.player
		if p2 != null and is_instance_valid(p2) and p2.global_position.distance_to(n.global_position) < 9.0:
			npc.set("look_target", p2.global_position + Vector3(0.0, 1.5, 0.0))
		else:
			npc.set("look_target", Vector3.INF)
	npc.set("state_tag", "hang")


func _calm(npc: Node) -> void:
	target = null
	combat.reset()
	npc.call("stop_aiming")
	npc.call("set_crouched", false)
	mode = RETURN
	t = 0.0
	if home != Vector3.INF:
		npc.call("move_to", home, "walk")
	npc.set("state_tag", "return")
