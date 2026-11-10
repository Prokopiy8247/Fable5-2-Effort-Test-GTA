extends RefCounted
## WORLD module helper: 2D polyline geometry in the XZ plane (Vector2(x, z)).
## No class_name on purpose (module-private); load with preload() from WORLD scripts only.


## Right-hand side of a travel direction (map axes: +X east, +Z south). North (0,-1) -> east (1,0).
static func right_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


static func length_of(p: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i].distance_to(p[i - 1])
	return l


## Parallel polyline. Positive offset = right of the travel direction. Miter joins.
static func offset(p: PackedVector2Array, off: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := p.size()
	if n < 2:
		return p
	out.resize(n)
	for i in n:
		var d0: Vector2 = (p[i] - p[i - 1]).normalized() if i > 0 else (p[1] - p[0]).normalized()
		var d1: Vector2 = (p[i + 1] - p[i]).normalized() if i < n - 1 else d0
		var r0 := right_of(d0)
		var r1 := right_of(d1)
		var m := r0 + r1
		if m.length() < 0.001:
			m = r0
		else:
			m = m.normalized()
		var c := maxf(m.dot(r1), 0.4)
		out[i] = p[i] + m * (off / c)
	return out


## Replaces interior corners by arcs of the given radius (ends stay untouched).
static func round_corners(p: PackedVector2Array, radius: float, step_deg: float = 9.0) -> PackedVector2Array:
	var n := p.size()
	if n < 3 or radius <= 0.01:
		return p
	var out := PackedVector2Array()
	out.append(p[0])
	for i in range(1, n - 1):
		var a := p[i - 1]
		var b := p[i]
		var c := p[i + 1]
		var d0 := (b - a).normalized()
		var d1 := (c - b).normalized()
		var ang := d0.angle_to(d1)
		if absf(ang) < 0.05:
			out.append(b)
			continue
		var t := radius * tan(absf(ang) * 0.5)
		t = minf(t, minf(a.distance_to(b), b.distance_to(c)) * 0.48)
		var r := t / tan(absf(ang) * 0.5)
		var p0 := b - d0 * t
		var side := signf(ang)   # +1: turning right (clockwise seen with z down)
		var centre := p0 + right_of(d0) * (r * side)
		var steps := maxi(2, int(ceil(rad_to_deg(absf(ang)) / step_deg)))
		var start := p0 - centre
		for s in steps + 1:
			out.append(centre + start.rotated(ang * float(s) / float(steps)))
	out.append(p[n - 1])
	return out


## Catmull-Rom through the points, resampled about every `step` metres. First edge stays straight.
static func catmull(p: PackedVector2Array, step: float = 3.0) -> PackedVector2Array:
	var n := p.size()
	if n < 3:
		return p
	var out := PackedVector2Array()
	for i in n - 1:
		var p0 := p[maxi(i - 1, 0)]
		var p1 := p[i]
		var p2 := p[i + 1]
		var p3 := p[mini(i + 2, n - 1)]
		var cnt := maxi(1, int(ceil(p1.distance_to(p2) / step)))
		for s in cnt:
			var t := float(s) / float(cnt)
			if i == 0:
				out.append(p1.lerp(p2, t))
			else:
				out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
						+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(p[n - 1])
	return out


## Cuts d0 metres from the start and d1 metres from the end.
static func trim(p: PackedVector2Array, d0: float, d1: float) -> PackedVector2Array:
	var total := length_of(p)
	if total <= d0 + d1 + 0.05:
		var mid := point_at(p, total * 0.5)
		return PackedVector2Array([mid, mid])
	return sub(p, d0, total - d1)


## Sub-polyline between two distances along p.
static func sub(p: PackedVector2Array, a: float, b: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var acc := 0.0
	out.append(point_at(p, a))
	for i in range(1, p.size()):
		var l := p[i].distance_to(p[i - 1])
		var e := acc + l
		if e > a + 0.01 and e < b - 0.01:
			out.append(p[i])
		acc = e
	out.append(point_at(p, b))
	return out


static func point_at(p: PackedVector2Array, dist: float) -> Vector2:
	var acc := 0.0
	for i in range(1, p.size()):
		var l := p[i].distance_to(p[i - 1])
		if acc + l >= dist and l > 0.0001:
			return p[i - 1].lerp(p[i], clampf((dist - acc) / l, 0.0, 1.0))
		acc += l
	return p[p.size() - 1]


static func dir_at(p: PackedVector2Array, dist: float) -> Vector2:
	var acc := 0.0
	for i in range(1, p.size()):
		var l := p[i].distance_to(p[i - 1])
		if acc + l >= dist and l > 0.0001:
			return (p[i] - p[i - 1]) / l
		acc += l
	var n := p.size()
	return (p[n - 1] - p[n - 2]).normalized()


## Inserts points so that no edge is longer than max_step.
static func resample(p: PackedVector2Array, max_step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in p.size() - 1:
		var cnt := maxi(1, int(ceil(p[i].distance_to(p[i + 1]) / max_step)))
		for s in cnt:
			out.append(p[i].lerp(p[i + 1], float(s) / float(cnt)))
	out.append(p[p.size() - 1])
	return out


## Closest point on a polyline. Returns [distance, offset_along, point].
static func closest(p: PackedVector2Array, q: Vector2) -> Array:
	var best := INF
	var best_off := 0.0
	var best_pt := p[0]
	var acc := 0.0
	for i in range(1, p.size()):
		var a := p[i - 1]
		var ab := p[i] - a
		var l2 := ab.length_squared()
		var t := 0.0
		if l2 > 0.000001:
			t = clampf((q - a).dot(ab) / l2, 0.0, 1.0)
		var c := a + ab * t
		var d := c.distance_squared_to(q)
		var l := sqrt(l2)
		if d < best:
			best = d
			best_off = acc + l * t
			best_pt = c
		acc += l
	return [sqrt(best), best_off, best_pt]


## Segment/segment intersection (inclusive ends, tolerance eps). Returns Vector2.INF if none.
static func seg_hit(a: Vector2, b: Vector2, c: Vector2, d: Vector2, eps: float = 0.05) -> Vector2:
	var r := b - a
	var s := d - c
	var den := r.x * s.y - r.y * s.x
	if absf(den) < 0.00001:
		# parallel: only report touching end points
		for e: Vector2 in [a, b]:
			for f: Vector2 in [c, d]:
				if e.distance_to(f) < eps:
					return e
		return Vector2.INF
	var t := ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / den
	var u := ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / den
	var et := eps / maxf(r.length(), 0.001)
	var eu := eps / maxf(s.length(), 0.001)
	if t < -et or t > 1.0 + et or u < -eu or u > 1.0 + eu:
		return Vector2.INF
	return a + r * clampf(t, 0.0, 1.0)


static func to3(p: PackedVector2Array, y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(p.size())
	for i in p.size():
		out[i] = Vector3(p[i].x, y, p[i].y)
	return out


static func to2(p: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(p.size())
	for i in p.size():
		out[i] = Vector2(p[i].x, p[i].z)
	return out


## Rounded rectangle outline (clockwise seen from above with z down). radii: [nw, ne, se, sw].
static func rounded_rect(x0: float, z0: float, x1: float, z1: float, radii: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]
	var inward := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	var start_ang := [PI, -PI * 0.5, 0.0, PI * 0.5]
	for i in 4:
		var r: float = float(radii[i])
		var cpt: Vector2 = corners[i]
		if r < 0.05:
			out.append(cpt)
			continue
		var inw: Vector2 = inward[i]
		var centre: Vector2 = cpt + inw * r
		var a0: float = start_ang[i]
		for s in 7:
			var a := a0 + PI * 0.5 * float(s) / 6.0
			out.append(centre + Vector2(cos(a), sin(a)) * r)
	return out


## Like round_corners() but with one radius per vertex (0 = keep the corner sharp). Every rounded
## corner is appended to `bends` as {v, centre, r, d0, d1, side, ang, steps} (side +1 = right turn).
static func round_some(p: PackedVector2Array, radii: PackedFloat32Array, bends: Array, step_deg: float = 9.0) -> PackedVector2Array:
	var n := p.size()
	if n < 3:
		return p
	var out := PackedVector2Array()
	out.append(p[0])
	for i in range(1, n - 1):
		var a := p[i - 1]
		var b := p[i]
		var c := p[i + 1]
		var d0 := (b - a).normalized()
		var d1 := (c - b).normalized()
		var ang := d0.angle_to(d1)
		if radii[i] <= 0.01 or absf(ang) < 0.05:
			out.append(b)
			continue
		var t := radii[i] * tan(absf(ang) * 0.5)
		t = minf(t, minf(a.distance_to(b), b.distance_to(c)) * 0.48)
		var r := t / tan(absf(ang) * 0.5)
		var p0 := b - d0 * t
		var side := signf(ang)
		var centre := p0 + right_of(d0) * (r * side)
		var steps := maxi(2, int(ceil(rad_to_deg(absf(ang)) / step_deg)))
		var start := p0 - centre
		for s in steps + 1:
			out.append(centre + start.rotated(ang * float(s) / float(steps)))
		bends.append({"v": b, "centre": centre, "r": r, "d0": d0, "d1": d1, "side": side, "ang": ang, "steps": steps})
	out.append(p[n - 1])
	return out


static func reversed(p: PackedVector2Array) -> PackedVector2Array:
	var out := p.duplicate()
	out.reverse()
	return out


## Cumulative distances (same size as p).
static func cumulative(p: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(p.size())
	var acc := 0.0
	for i in range(1, p.size()):
		acc += p[i].distance_to(p[i - 1])
		out[i] = acc
	return out


## Yaw (rotation about +Y) that makes -Z point along the XZ direction d (Vector2(x, z)).
static func yaw_of(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


## True if q lies inside the axis-aligned rounded rectangle (radii: [nw, ne, se, sw]).
static func in_rounded_rect(q: Vector2, x0: float, z0: float, x1: float, z1: float, radii: Array) -> bool:
	if q.x < x0 or q.x > x1 or q.y < z0 or q.y > z1:
		return false
	var r: float = float(radii[0])
	if r > 0.05 and q.x < x0 + r and q.y < z0 + r:
		return q.distance_squared_to(Vector2(x0 + r, z0 + r)) <= r * r
	r = float(radii[1])
	if r > 0.05 and q.x > x1 - r and q.y < z0 + r:
		return q.distance_squared_to(Vector2(x1 - r, z0 + r)) <= r * r
	r = float(radii[2])
	if r > 0.05 and q.x > x1 - r and q.y > z1 - r:
		return q.distance_squared_to(Vector2(x1 - r, z1 - r)) <= r * r
	r = float(radii[3])
	if r > 0.05 and q.x < x0 + r and q.y > z1 - r:
		return q.distance_squared_to(Vector2(x0 + r, z1 - r)) <= r * r
	return true
