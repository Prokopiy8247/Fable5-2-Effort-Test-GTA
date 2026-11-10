extends RefCounted
## WORLD module helper: spatial hash of polyline edges in the XZ plane (lanes, road corridors,
## walk links). Module-private (no class_name); load with preload() from WORLD scripts only.

var cell := 16.0
var ea := PackedVector2Array()        ## edge start
var eb := PackedVector2Array()        ## edge end
var eid := PackedInt32Array()         ## owner id (lane / segment / link)
var eidx := PackedInt32Array()        ## index of the edge inside its polyline
var eoff := PackedFloat32Array()      ## 2D distance along the polyline at the edge start
var eflag := PackedByteArray()        ## bit 0: first edge of its polyline, bit 1: last edge
var _cells := {}                      ## int key -> PackedInt32Array of entries
var _empty := PackedInt32Array()

## results of the last nearest() call
var r_dist := 0.0
var r_t := 0.0
var r_point := Vector2.ZERO


func _init(cell_size: float = 16.0) -> void:
	cell = cell_size


func _key(cx: int, cz: int) -> int:
	return (cx + 4096) * 8192 + (cz + 4096)


## Registers every edge of the polyline in all cells its bounding box (grown by margin) touches.
func add_polyline(id: int, pts: PackedVector2Array, margin: float = 0.0) -> void:
	var acc := 0.0
	var n := pts.size()
	for i in range(1, n):
		var a := pts[i - 1]
		var b := pts[i]
		var l := a.distance_to(b)
		if l < 0.0001:
			continue
		var e := ea.size()
		ea.append(a)
		eb.append(b)
		eid.append(id)
		eidx.append(i - 1)
		eoff.append(acc)
		eflag.append((1 if i == 1 else 0) | (2 if i == n - 1 else 0))
		acc += l
		var x0 := int(floor((minf(a.x, b.x) - margin) / cell))
		var x1 := int(floor((maxf(a.x, b.x) + margin) / cell))
		var z0 := int(floor((minf(a.y, b.y) - margin) / cell))
		var z1 := int(floor((maxf(a.y, b.y) + margin) / cell))
		for cz in range(z0, z1 + 1):
			for cx in range(x0, x1 + 1):
				var k := _key(cx, cz)
				var lst: PackedInt32Array = _cells.get(k, _empty)
				if lst.is_empty():
					lst = PackedInt32Array()
				lst.append(e)
				_cells[k] = lst


## Entries registered in the cell of q (use together with a margin given to add_polyline()).
func candidates(q: Vector2) -> PackedInt32Array:
	return _cells.get(_key(int(floor(q.x / cell)), int(floor(q.y / cell))), _empty)


func _scan(k: int, q: Vector2, best: float, found: int) -> int:
	var lst: PackedInt32Array = _cells.get(k, _empty)
	var res := found
	var bst := best
	for e in lst:
		var a := ea[e]
		var ab := eb[e] - a
		var t := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var c := a + ab * t
		var d2 := c.distance_squared_to(q)
		if d2 < bst:
			bst = d2
			res = e
			r_t = t
			r_point = c
	r_dist = bst
	return res


## Nearest edge within max_dist. Returns the entry index (-1 if none) and fills r_dist / r_t / r_point.
func nearest(q: Vector2, max_dist: float) -> int:
	var cx := int(floor(q.x / cell))
	var cz := int(floor(q.y / cell))
	var rmax := int(ceil(max_dist / cell)) + 1
	var best := max_dist * max_dist
	var found := -1
	for ring in range(0, rmax + 1):
		if ring == 0:
			found = _scan(_key(cx, cz), q, best, found)
			best = r_dist
		else:
			for dz in range(-ring, ring + 1):
				if absi(dz) == ring:
					for dx in range(-ring, ring + 1):
						found = _scan(_key(cx + dx, cz + dz), q, best, found)
						best = r_dist
				else:
					found = _scan(_key(cx - ring, cz + dz), q, best, found)
					best = r_dist
					found = _scan(_key(cx + ring, cz + dz), q, best, found)
					best = r_dist
		if found >= 0 and best <= (float(ring) * cell) * (float(ring) * cell):
			break
	r_dist = sqrt(best)
	return found
