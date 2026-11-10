class_name PedGraph
extends RefCounted
## Sidewalk network for pedestrians, derived from the road layout: two points beside every
## junction arm, linked along sidewalks, around block corners and over zebra crossings.

const T_WALK := 0
const T_CORNER := 1
const T_CROSS := 2

var pts: PackedVector3Array = PackedVector3Array()
var adj: Array = []              # per point: Array of [neighbour index, edge type]
var _key: Dictionary = {}        # "node|arm|side" -> point index

func build(layout: CityLayout) -> void:
	var arm_dir := {"N": Vector3(0, 0, -1), "S": Vector3(0, 0, 1), "E": Vector3(1, 0, 0), "W": Vector3(-1, 0, 0)}
	for id in layout.nodes.keys():
		var nd: Dictionary = layout.nodes[id]
		for arm: String in ["N", "S", "E", "W"]:
			var ri := int(nd["arms"][arm])
			if ri < 0:
				continue
			var road: Dictionary = layout.roads[ri]
			if not road["sidewalk"]:
				continue
			var d: Vector3 = arm_dir[arm]
			var half: float = nd["hz"] if (arm == "N" or arm == "S") else nd["hx"]
			var side := Vector3(-d.z, 0, d.x)
			for sgn: float in [-1.0, 1.0]:
				var p: Vector3 = nd["pos"] + d * (half + 2.2) + side * float(sgn) * (float(road["hw"]) + 1.75)
				p.y = CityLayout.CURB_H
				# key by the world-space side so both ends of a road agree
				var world_side := side * float(sgn)
				var tag := "x+" if world_side.x > 0.5 else ("x-" if world_side.x < -0.5 else ("z+" if world_side.z > 0.5 else "z-"))
				_key["%s|%s|%s" % [id, arm, tag]] = pts.size()
				pts.append(p)
				adj.append([])
	# crosswalks + sidewalks along each road
	var opposite := {"N": "S", "S": "N", "E": "W", "W": "E"}
	for id in layout.nodes.keys():
		var nd: Dictionary = layout.nodes[id]
		for arm: String in ["N", "S", "E", "W"]:
			var tags := ["x-", "x+"] if (arm == "N" or arm == "S") else ["z-", "z+"]
			var a := _pt("%s|%s|%s" % [id, arm, tags[0]])
			var b := _pt("%s|%s|%s" % [id, arm, tags[1]])
			if a >= 0 and b >= 0:
				_link(a, b, T_CROSS)
			var ri := int(nd["arms"][arm])
			if ri < 0:
				continue
			var road: Dictionary = layout.roads[ri]
			var other: String = road["b"] if road["a"] == id else road["a"]
			if other < id:
				continue
			for tg in tags:
				var p0 := _pt("%s|%s|%s" % [id, arm, tg])
				var p1 := _pt("%s|%s|%s" % [other, opposite[arm], tg])
				if p0 >= 0 and p1 >= 0:
					_link(p0, p1, T_WALK)
		# corners / straight-through sidewalks in each quadrant of the junction
		for qx: String in ["x-", "x+"]:
			for qz: String in ["z-", "z+"]:
				var arm_x := "E" if qx == "x+" else "W"
				var arm_z := "S" if qz == "z+" else "N"
				var px := _pt("%s|%s|%s" % [id, arm_x, qz])
				var pz := _pt("%s|%s|%s" % [id, arm_z, qx])
				if px >= 0 and pz >= 0:
					_link(px, pz, T_CORNER)
				elif px >= 0:
					var across := _pt("%s|%s|%s" % [id, opposite[arm_x], qz])
					if across >= 0:
						_link(px, across, T_WALK)
				elif pz >= 0:
					var across2 := _pt("%s|%s|%s" % [id, opposite[arm_z], qx])
					if across2 >= 0:
						_link(pz, across2, T_WALK)

func _pt(key: String) -> int:
	return int(_key.get(key, -1))

func _link(a: int, b: int, t: int) -> void:
	for e in adj[a]:
		if int(e[0]) == b:
			return
	(adj[a] as Array).append([b, t])
	(adj[b] as Array).append([a, t])

func nearest(pos: Vector3) -> int:
	var best := -1
	var bd := 1.0e18
	for i in pts.size():
		var d := pts[i].distance_squared_to(pos)
		if d < bd:
			bd = d
			best = i
	return best

## Next point to walk to from `at`, avoiding an immediate U-turn.
func next(at: int, came_from: int, rng: RandomNumberGenerator) -> Array:
	var list: Array = adj[at]
	if list.is_empty():
		return [at, T_WALK]
	var options: Array = []
	for e in list:
		if int(e[0]) != came_from:
			options.append(e)
	if options.is_empty():
		options = list
	return options[rng.randi() % options.size()]
