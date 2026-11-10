class_name TransitPath
extends RefCounted
## The closed tram loop (World.get_transit_path) as an arc-length parameterised polyline:
## sampling, tangents, projection and a precomputed speed profile (curves + braking into them).
## Plain data, no nodes; owned by TransitSystem. Offsets `s` are metres from the first point,
## always wrapped into [0, length).

const PROFILE_STEP := 1.0           ## metres between speed-profile samples

var pts := PackedVector3Array()      ## loop points (the closing point is not repeated)
var cum := PackedFloat32Array()      ## cum[i] = distance from pts[0] to pts[i]; cum[n] = length
var length: float = 0.0
var count: int = 0
var vlim := PackedFloat32Array()     ## centre speed limit (m/s) every PROFILE_STEP metres
var radius := PackedFloat32Array()   ## estimated curve radius at every profile sample (m, INF straight)


func build(path: PackedVector3Array) -> bool:
	pts = PackedVector3Array()
	for p: Vector3 in path:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 0.05:
			pts.append(p)
	if pts.size() >= 2 and pts[0].distance_to(pts[pts.size() - 1]) < 0.05:
		pts.remove_at(pts.size() - 1)
	count = pts.size()
	if count < 3:
		return false
	cum = PackedFloat32Array()
	cum.resize(count + 1)
	cum[0] = 0.0
	for i in count:
		var a := pts[i]
		var b := pts[(i + 1) % count]
		cum[i + 1] = cum[i] + Vector2(b.x - a.x, b.z - a.z).length()
	length = cum[count]
	return length > 10.0


func wrap_s(s: float) -> float:
	return fposmod(s, length)


## Distance travelled from `from_s` forward to `to_s` (0 .. length).
func ahead(from_s: float, to_s: float) -> float:
	return fposmod(to_s - from_s, length)


## Signed shortest distance from `a` to `b` along the loop (-length/2 .. length/2).
func delta(a: float, b: float) -> float:
	var d := fposmod(b - a, length)
	return d - length if d > length * 0.5 else d


func _seg(s: float) -> int:
	var lo := 0
	var hi := count - 1
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi + 1) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


func sample(s: float) -> Vector3:
	var w := wrap_s(s)
	var i := _seg(w)
	var a := pts[i]
	var b := pts[(i + 1) % count]
	var seg := cum[i + 1] - cum[i]
	var t := 0.0 if seg < 0.0001 else (w - cum[i]) / seg
	return a.lerp(b, clampf(t, 0.0, 1.0))


## Unit travel direction (horizontal) at `s`.
func tangent(s: float) -> Vector3:
	var i := _seg(wrap_s(s))
	var d := pts[(i + 1) % count] - pts[i]
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD


## Offset of the point of the loop nearest to `p` (horizontal distance).
func project(p: Vector3) -> float:
	var best := INF
	var best_s := 0.0
	for i in count:
		var a := pts[i]
		var b := pts[(i + 1) % count]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var l2 := abx * abx + abz * abz
		var t := 0.0 if l2 < 0.000001 else clampf(((p.x - a.x) * abx + (p.z - a.z) * abz) / l2, 0.0, 1.0)
		var qx := a.x + abx * t - p.x
		var qz := a.z + abz * t - p.z
		var d2 := qx * qx + qz * qz
		if d2 < best:
			best = d2
			best_s = cum[i] + t * (cum[i + 1] - cum[i])
	return wrap_s(best_s)


## Horizontal distance of `p` from the loop centre line.
func distance_to(p: Vector3) -> float:
	var q := sample(project(p))
	return Vector2(p.x - q.x, p.z - q.z).length()


## Lateral offset of `p` from the path at `s` (+ = right of the travel direction).
func lateral(s: float, p: Vector3) -> float:
	var q := sample(s)
	var t := tangent(s)
	return (p.x - q.x) * -t.z + (p.z - q.z) * t.x


## Builds `vlim`: curve speed sqrt(a_lat * R) (R from the heading change over +-chord/2), held
## over the whole vehicle length (`half_len` either side of the centre), capped at v_max and
## made reachable with `b_comf` braking (backward pass, twice around the loop).
func build_profile(v_max: float, a_lat: float, half_len: float, b_comf: float, chord: float = 12.0) -> void:
	var m := maxi(int(ceil(length / PROFILE_STEP)), 1)
	var raw := PackedFloat32Array()
	raw.resize(m)
	radius.resize(m)
	for i in m:
		var s := float(i) * PROFILE_STEP
		var t0 := tangent(s - chord * 0.5)
		var t1 := tangent(s + chord * 0.5)
		var ang := absf(t0.signed_angle_to(t1, Vector3.UP))
		var r := INF if ang < 0.002 else chord / ang
		radius[i] = r
		raw[i] = v_max if r == INF else minf(v_max, sqrt(a_lat * r))
	# the whole vehicle must be slow while any part of it is in the curve
	var win := int(ceil(half_len / PROFILE_STEP))
	vlim.resize(m)
	for i in m:
		var v := v_max
		for k in range(-win, win + 1):
			v = minf(v, raw[posmod(i + k, m)])
		vlim[i] = v
	# reachable with comfortable braking
	for _pass in 2:
		for j in range(m - 1, -1, -1):
			var nxt := vlim[(j + 1) % m]
			vlim[j] = minf(vlim[j], sqrt(nxt * nxt + 2.0 * b_comf * PROFILE_STEP))


func speed_limit(s: float) -> float:
	if vlim.is_empty():
		return INF
	var i := int(wrap_s(s) / PROFILE_STEP) % vlim.size()
	return minf(vlim[i], vlim[(i + 1) % vlim.size()])


func radius_at(s: float) -> float:
	if radius.is_empty():
		return INF
	return radius[int(wrap_s(s) / PROFILE_STEP) % radius.size()]
