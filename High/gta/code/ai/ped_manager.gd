class_name PedManager
extends Node
## Ambient pedestrian population around the player with simulation tiers, plus persistent staff and gang posts.

const MAX_PEDS := 26
var density := 1.0
var ambient: Array = []
var posts: Array = []        # persistent NPC posts: {kind, pos, yaw, npc, t}
var _t := 0.0
var _tier_t := 0.0


func _ready() -> void:
	Game.peds = self


func add_post(kind: String, pos: Vector3, yaw: float = 0.0) -> void:
	posts.append({"kind": kind, "pos": pos, "yaw": yaw, "npc": null, "t": 0.0})


func on_npc_died(_n) -> void:
	pass


func _physics_process(delta: float) -> void:
	var p = Game.player
	if p == null:
		return
	_tier_t -= delta
	if _tier_t <= 0.0:
		_tier_t = 0.4
		var ppos: Vector3 = p.global_position
		for n in Game.npcs:
			if not is_instance_valid(n):
				continue
			var d: float = n.global_position.distance_to(ppos)
			var busy: bool = n.state == Npc.S.COMBAT or n.state == Npc.S.INVESTIGATE
			n.tier = 0 if (d < 45.0 or busy) else (1 if d < 95.0 else 2)
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.3
	var ppos2: Vector3 = p.global_position
	var i := 0
	while i < ambient.size():
		var n = ambient[i]
		if not is_instance_valid(n):
			ambient.remove_at(i)
			continue
		var d2: float = n.global_position.distance_to(ppos2)
		if (d2 > 125.0 and not n.dead) or not Game.flags.peds:
			n.queue_free()
			ambient.remove_at(i)
			continue
		i += 1
	_posts(p)
	if not Game.flags.peds:
		return
	var night: float = Game.daynight.night if Game.daynight else 0.0
	var rain: float = Game.daynight._w.rain if Game.daynight else 0.0
	var want := int(MAX_PEDS * density * (1.0 - 0.55 * night) * (1.0 - 0.4 * rain))
	if ambient.size() >= want:
		return
	var cam := get_viewport().get_camera_3d()
	for attempt in range(5):
		var idx := Game.rng.randi() % City.walk_nodes.size()
		var pos: Vector3 = City.walk_nodes[idx]
		var edges: Array = City.walk_edges[idx]
		if not edges.is_empty():
			var e: Dictionary = edges[Game.rng.randi() % edges.size()]
			if not e.cross:
				pos = pos.lerp(City.walk_nodes[e.to], Game.rng.randf())
		var d3 := pos.distance_to(ppos2)
		if d3 < 38.0 or d3 > 105.0:
			continue
		if cam and cam.is_position_in_frustum(pos + Vector3.UP) and d3 < 75.0:
			continue
		var n2 := Npc.spawn("civ", pos + Vector3(Game.rng.randf_range(-0.8, 0.8), 0.1, Game.rng.randf_range(-0.8, 0.8)))
		ambient.append(n2)
		break


func _posts(p) -> void:
	var ppos: Vector3 = p.global_position
	for post in posts:
		var n = post.npc
		var d: float = (post.pos as Vector3).distance_to(ppos)
		if n != null and (not is_instance_valid(n) or n.dead):
			post.npc = null
			post.t = 90.0
			n = null
		if n == null:
			post.t -= 0.3
			if post.t <= 0.0 and d < 110.0 and (d > 40.0 or post.get("first", true)):
				var nn := Npc.spawn(post.kind, post.pos)
				nn.persistent = true
				nn.home = post.pos
				nn.home_yaw = post.yaw
				nn.rotation.y = post.yaw
				post.npc = nn
				post["first"] = false
		elif d > 160.0:
			n.queue_free()
			post.npc = null
			post.t = 0.0
			post["first"] = true
