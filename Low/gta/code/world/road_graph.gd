class_name RoadGraph
extends RefCounted
# Project-owned lane/road graph: 5x5 intersections, right-hand traffic, signal phases.

var nodes: Array = []      # Vector3
var links: Array = []      # per node: Array of neighbour indices
const CYCLE := 18.0


func _init() -> void:
	for i in 5:
		for j in 5:
			nodes.append(Vector3(Defs.ROADS[i], 0.05, Defs.ROADS[j]))
	for i in 5:
		for j in 5:
			var l := []
			if i > 0: l.append(idx(i - 1, j))
			if i < 4: l.append(idx(i + 1, j))
			if j > 0: l.append(idx(i, j - 1))
			if j < 4: l.append(idx(i, j + 1))
			links.append(l)


func idx(i: int, j: int) -> int:
	return i * 5 + j


func is_arterial(a: int, b: int) -> bool:
	var ia := a / 5
	var ja := a % 5
	var ib := b / 5
	var jb := b % 5
	if ia == ib:
		return ia == 0 or ia == 4
	return ja == 0 or ja == 4 and ja == jb


func half_width(a: int, b: int) -> float:
	return 9.0 if is_arterial(a, b) else 6.0


func lane_offset(a: int, b: int, lane := 0) -> float:
	if is_arterial(a, b):
		return 2.4 + 4.2 * lane
	return 3.0


func edge_dir(a: int, b: int) -> Vector3:
	return (nodes[b] - nodes[a]).normalized()


func lane_point(a: int, b: int, t: float, lane := 0) -> Vector3:
	# point at distance t from node a toward b, shifted to the right-hand lane
	var d := edge_dir(a, b)
	return nodes[a] + d * t + d.cross(Vector3.UP) * lane_offset(a, b, lane)


func cross_half(n: int, a_from: int) -> float:
	# half width of the road crossing node n, perpendicular to travel from a_from
	var moving_x: bool = abs(nodes[n].x - nodes[a_from].x) > 1.0
	var i := n / 5
	var j := n % 5
	if moving_x:
		return 9.0 if (i == 0 or i == 4) else 6.0
	return 9.0 if (j == 0 or j == 4) else 6.0


func light_state(n: int, moving_x: bool) -> int:
	# 0 green, 1 yellow, 2 red
	var i := n / 5
	var j := n % 5
	var t := fmod(G.time_now + ((i + j) % 2) * CYCLE * 0.5, CYCLE)
	var ph := t if not moving_x else fmod(t + CYCLE * 0.5, CYCLE)
	if ph < CYCLE * 0.5 - 3.0:
		return 0
	if ph < CYCLE * 0.5 - 1.0:
		return 1
	return 2


func nearest(p: Vector3) -> int:
	var best := 0
	var bd := 1e9
	for k in nodes.size():
		var d: float = Vector2(nodes[k].x - p.x, nodes[k].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = k
	return best


func path(a: int, b: int) -> Array:
	if a == b:
		return [a]
	var prev := {a: -1}
	var q := [a]
	while not q.is_empty():
		var c: int = q.pop_front()
		if c == b:
			break
		for n in links[c]:
			if not prev.has(n):
				prev[n] = c
				q.append(n)
	var out := []
	var c2 := b
	while c2 != -1:
		out.push_front(c2)
		c2 = prev.get(c2, -1)
	return out


func nearest_edge(p: Vector3) -> Array:
	# returns [a, b, t] of the closest directed lane whose right side contains p
	var best := [0, 1, 0.0]
	var bd := 1e9
	for a in nodes.size():
		for b in links[a]:
			var d := edge_dir(a, b)
			var rel: Vector3 = p - nodes[a]
			var t: float = clamp(rel.dot(d), 0.0, 80.0)
			var lp := lane_point(a, b, t)
			var dist := Vector2(lp.x - p.x, lp.z - p.z).length()
			if dist < bd:
				bd = dist
				best = [a, b, t]
	return best
