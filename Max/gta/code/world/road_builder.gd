class_name RoadBuilder
extends RefCounted
## Builds road, junction, runway and taxiway meshes from the CityLayout.
## All markings are procedural in road.gdshader (see the UV contract there).

const T_PLAIN := 0
const T_STREET := 1
const T_ARTERIAL := 2
const T_HILL := 3
const T_RUNWAY := 4
const T_TAXI := 5
const T_APRON := 6

static func kind_type(kind: String) -> int:
	match kind:
		"street": return T_STREET
		"arterial": return T_ARTERIAL
		"hill": return T_HILL
		"runway": return T_RUNWAY
		"taxiway": return T_TAXI
		"apron": return T_APRON
	return T_PLAIN

## Ribbon along a polyline. hw may vary per point (hws) for tapered mouths.
static func strip(buf: GeoBuf, pts: PackedVector3Array, hw: float, type: int, cw_start: bool, cw_end: bool,
		y_off := 0.0, hws: PackedFloat32Array = PackedFloat32Array()) -> void:
	var count := pts.size()
	if count < 2:
		return
	var total := 0.0
	var dist := PackedFloat32Array()
	dist.resize(count)
	for i in range(1, count):
		total += pts[i - 1].distance_to(pts[i])
		dist[i] = total
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var widths := PackedFloat32Array()
	for i in count:
		var t: Vector3
		if i == 0:
			t = pts[1] - pts[0]
		elif i == count - 1:
			t = pts[count - 1] - pts[count - 2]
		else:
			t = pts[i + 1] - pts[i - 1]
		t.y = 0.0
		t = t.normalized()
		var r := Vector3(-t.z, 0.0, t.x)
		var w := hw if hws.is_empty() else hws[i]
		widths.append(w)
		left.append(pts[i] - r * w + Vector3(0, y_off, 0))
		right.append(pts[i] + r * w + Vector3(0, y_off, 0))
	buf.use_uv2 = true
	var uv2v := Vector2(float(type), total)
	for i in range(count - 1):
		var col := Color(1.0 if cw_start else 0.0, 1.0 if cw_end else 0.0, maxf(widths[i], widths[i + 1]) / 16.0)
		var l0 := left[i]; var r0 := right[i]; var l1 := left[i + 1]; var r1 := right[i + 1]
		var nrm := (l1 - l0).cross(r0 - l0).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var ul0 := Vector2(-widths[i], dist[i]); var ur0 := Vector2(widths[i], dist[i])
		var ul1 := Vector2(-widths[i + 1], dist[i + 1]); var ur1 := Vector2(widths[i + 1], dist[i + 1])
		buf.tri(l0, l1, r1, nrm, col, ul0, ul1, ur1, uv2v)
		buf.tri(l0, r1, r0, nrm, col, ul0, ur1, ur0, uv2v)

static func rect(buf: GeoBuf, x0: float, z0: float, x1: float, z1: float, y: float, type: int) -> void:
	buf.use_uv2 = true
	var col := Color(0, 0, 0.5)
	var uv2v := Vector2(float(type), maxf(z1 - z0, x1 - x0))
	var a := Vector3(x0, y, z0); var b := Vector3(x1, y, z0); var c := Vector3(x1, y, z1); var d := Vector3(x0, y, z1)
	buf.tri(a, b, c, Vector3.UP, col, Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), uv2v)
	buf.tri(a, c, d, Vector3.UP, col, Vector2(x0, z0), Vector2(x1, z1), Vector2(x0, z1), uv2v)

static func build(layout: CityLayout, parent: Node3D, material: Material) -> void:
	# --- road segments (grouped per ~8 segments to keep draw calls and culling reasonable)
	var idx := 0
	for road in layout.roads:
		var buf := GeoBuf.new()
		var kind: String = road["kind"]
		var pts: PackedVector3Array = road["pts"]
		if kind == "hill":
			var hws := PackedFloat32Array()
			var n := pts.size()
			for i in n:
				var d_end := minf(float(i), float(n - 1 - i)) * 2.0
				hws.append(lerpf(CityLayout.STREET_HW, CityLayout.HILL_HW, smoothstep(2.0, 16.0, d_end)))
			road["hws"] = hws
			strip(buf, pts, road["hw"], T_HILL, false, false, 0.05, hws)
		else:
			strip(buf, pts, road["hw"], kind_type(kind), true, true, 0.0)
		var mi := buf.instance(parent, "Road_%d" % idx, material)
		if mi:
			mi.set_meta("road", idx)
		idx += 1
	# --- summit spur (plain narrow lane)
	if layout.spur_pts.size() > 1:
		var sb := GeoBuf.new()
		strip(sb, layout.spur_pts, 3.2, T_HILL, false, false, 0.05)
		sb.instance(parent, "Road_spur", material)
	# --- junction boxes with rounded kerb fillets
	var jb := GeoBuf.new()
	jb.use_uv2 = true
	for id in layout.nodes.keys():
		var nd: Dictionary = layout.nodes[id]
		var r := layout.node_rect(nd)
		rect(jb, r.position.x, r.position.y, r.end.x, r.end.y, 0.0, T_PLAIN)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var p := Vector2(nd["pos"].x + sx * nd["hx"], nd["pos"].z + sz * nd["hz"])
				var cen := p + Vector2(sx, sz) * CityLayout.CORNER_R
				var prev := Vector2(p.x, p.y + sz * CityLayout.CORNER_R)
				for k in range(1, 7):
					var a := deg_to_rad(90.0 * float(k) / 6.0)
					var cur := cen + Vector2(-sx * cos(a), -sz * sin(a)) * CityLayout.CORNER_R
					jb.tri(Vector3(p.x, 0, p.y), Vector3(prev.x, 0, prev.y), Vector3(cur.x, 0, cur.y), Vector3.UP,
						Color(0, 0, 0.5), p, prev, cur, Vector2(T_PLAIN, 8.0))
					prev = cur
	jb.instance(parent, "Junctions", material)
