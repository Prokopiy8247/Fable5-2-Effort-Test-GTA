class_name AiBrainStaff
extends Node
## Brain of shop staff (archetype shop_staff). Holds its post (spawn position + yaw = facing the
## counter), watches customers, raises its hands while a firearm is pointed at it (the body emits
## the `threatened` signal and on_event "threatened" - shops use it for the robbery hook), cowers
## when shots are fired close by, then flees and comes back to the post once things calm down.

enum { POST, HANDS_UP, COWER, FLEE, RETURN }
const MODE_NAMES := ["post", "hands_up", "cower", "flee", "return"]

var mode: int = POST
var t: float = 0.0
var timer: float = 0.0
var post: Vector3 = Vector3.INF
var post_yaw: float = 0.0
var danger_pos: Vector3 = Vector3.INF
var last_shot_t: float = -100.0
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func on_event(npc: Node, event: String, data: Dictionary) -> void:
	var n := npc as Node3D
	if n == null:
		return
	match event:
		"spawned":
			_rng.seed = npc.get_instance_id()
			post = n.global_position
			post_yaw = n.rotation.y
			mode = POST
			npc.set("state_tag", "post")
		"threatened":
			if mode == POST or mode == RETURN:
				npc.call("surrender")
				mode = HANDS_UP
				t = 0.0
			var by: Variant = data.get("by", null)
			if by is Node3D and is_instance_valid(by):
				danger_pos = (by as Node3D).global_position
		"noise":
			var kind := str(data.get("kind", ""))
			if (kind == "gunshot" or kind == "explosion") and float(data.get("distance", 99.0)) < 40.0 \
					and data.get("instigator", null) != npc:
				last_shot_t = _clock
				danger_pos = data.get("position", n.global_position)
				if mode == POST or mode == RETURN or mode == HANDS_UP:
					npc.call("cower")
					mode = COWER
					t = 0.0
					timer = _rng.randf_range(3.0, 5.0)
		"damaged":
			last_shot_t = _clock
			var att: Variant = data.get("attacker", null)
			if att is Node3D and is_instance_valid(att):
				danger_pos = (att as Node3D).global_position
			if mode != FLEE:
				_flee(npc)
		"panic":
			_flee(npc)
		"got_up":
			_flee(npc)


func think(npc: Node, delta: float) -> void:
	var n := npc as Node3D
	if n == null or bool(npc.get("is_dead")) or bool(npc.get("is_down")):
		return
	t += delta
	_clock += delta
	match mode:
		POST:
			if post == Vector3.INF:
				post = n.global_position
			var d := Vector2(n.global_position.x - post.x, n.global_position.z - post.z).length()
			if d > 0.7:
				if not bool(npc.call("is_moving")):
					npc.call("move_to", post, "walk")
			else:
				npc.call("stop_moving")
				npc.call("face_position", post + Vector3(-sin(post_yaw), 0.0, -cos(post_yaw)) * 3.0)
			# glance at a customer who comes close
			var p := Game.player
			if p != null and is_instance_valid(p) and p.global_position.distance_to(n.global_position) < 7.0:
				npc.set("look_target", p.global_position + Vector3(0.0, 1.6, 0.0))
			else:
				npc.set("look_target", Vector3.INF)
			npc.set("state_tag", "post")
		HANDS_UP:
			npc.set("state_tag", "hands_up")
			if float(npc.get("threatened_time")) > 0.0:
				t = 0.0
				var by: Variant = npc.get("threatened_by")
				if by is Node3D and is_instance_valid(by):
					npc.call("face_position", (by as Node3D).global_position)
			elif t > 3.0:
				npc.call("stand_normal")
				mode = POST
				t = 0.0
		COWER:
			npc.set("state_tag", "cower")
			if t >= timer:
				npc.call("stand_normal")
				if _clock - last_shot_t < 6.0:
					_flee(npc)
				else:
					mode = POST
					t = 0.0
		FLEE:
			if t > 25.0 and _clock - last_shot_t > 20.0:
				mode = RETURN
				t = 0.0
				npc.call("move_to", post, "walk")
			elif not bool(npc.call("is_moving")) and t < 25.0 and t > 2.0 and _clock - last_shot_t < 8.0:
				npc.call("flee_from", danger_pos if danger_pos != Vector3.INF else n.global_position, 25.0, "run")
		RETURN:
			npc.set("state_tag", "return")
			if bool(npc.call("has_arrived", 0.8)) or (not bool(npc.call("is_moving")) and t > 1.0):
				if n.global_position.distance_to(post) > 2.0 and t < 30.0:
					npc.call("move_to", post, "walk")
				else:
					mode = POST
					t = 0.0


func _flee(npc: Node) -> void:
	npc.call("stand_normal")
	npc.call("flee_from", danger_pos if danger_pos != Vector3.INF else (npc as Node3D).global_position, 28.0, "sprint")
	npc.set("state_tag", "flee")
	mode = FLEE
	t = 0.0
