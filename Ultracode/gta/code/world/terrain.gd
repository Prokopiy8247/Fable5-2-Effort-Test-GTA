class_name Terrain
extends Node3D
## Island terrain. The static analytic function Terrain.height(x, z) is the single source of truth
## (coast, plateau, beach, quays, Signal Hill, seabed). The node builds chunked render meshes and
## trimesh collision from a 3 m lattice of that function; get_mesh_height() returns the exact
## height of the generated surface (what physics bodies stand on).

const Geom := preload("res://gta/code/world/gen/world_geom.gd")
const SHADER_PATH := "res://gta/code/world/shaders/world_terrain.gdshader"

const CELL := 3.0
const HALF := 128                 ## lattice spans +-384 m
const N := 257
const CHUNK := 64                 ## cells per render chunk (192 m)
const SEA_FLOOR := -14.5
const PORT_DEPTH := -5.5

static var _inited := false
static var _tracks: Array = []                  ## dirt tracks: [points, heights, bbox min, bbox max]
static var _pads: Array = []                    ## [x, z, radius, blend, height, dirt]
## side results of the last sample() call
static var s_sand := 0.0
static var s_dirt := 0.0
static var s_wild := false
static var s_coast := 0.0

var heights := PackedFloat32Array()
var kinds := PackedByteArray()                  ## per lattice vertex: 0 grass, 1 sand, 2 dirt, +4 = outside the city plateau
var build_ms := 0


# ---------------------------------------------------------------------------------------------
# analytic terrain
# ---------------------------------------------------------------------------------------------

## Signed distance to the natural coast (> 0 inland), before the port is cut out.
static func organic_sd(x: float, z: float) -> float:
	var qx := absf(x - 2.0) - 211.0
	var qz := absf(z + 3.0) - 212.0
	var o := 75.0 - (Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length() + minf(maxf(qx, qz), 0.0))
	o += 2.2 * sin(x * 0.043 + 1.7) * cos(z * 0.037 - 0.6) + 1.4 * sin((x + z) * 0.071 + 0.9) + 0.9 * sin((x - z) * 0.11 + 2.3)
	var bx := (x - 165.0) / 105.0
	var bz := (z - 300.0) / 52.0
	o -= 30.0 * exp(-(bx * bx + bz * bz))                                   # beach bay (south-east)
	var hx := (x - 8.0) / 30.0
	var hz := (z - 285.0) / 40.0
	o += 7.0 * exp(-(hx * hx + hz * hz))                                    # lighthouse headland
	o -= 8.0 * exp(-((x + 290.0) * (x + 290.0) + (z + 150.0) * (z + 150.0)) / 784.0)   # west cove
	o -= 12.0 * exp(-((x - 298.0) * (x - 298.0) + (z - 40.0) * (z - 40.0)) / 900.0)    # east cove
	return o


## Distance to the dredged port water (> 0 outside it). West of the docks quay, south of the marina quay.
static func port_sd(x: float, z: float) -> float:
	var ax := x - WorldLayout.QUAY_X
	var az := WorldLayout.QUAY_NORTH - z
	var a: float = maxf(ax, az) if (ax <= 0.0 and az <= 0.0) else Vector2(maxf(ax, 0.0), maxf(az, 0.0)).length()
	var bx := x - WorldLayout.QUAY_EAST
	var bz := WorldLayout.QUAY_Z - z
	var b: float = maxf(bx, bz) if (bx <= 0.0 and bz <= 0.0) else Vector2(maxf(bx, 0.0), maxf(bz, 0.0)).length()
	return minf(a, b)


## Signed distance to the shore line (> 0 on land).
static func coast_sd(x: float, z: float) -> float:
	return minf(organic_sd(x, z), port_sd(x, z))


## > 0 inside the flat city plateau zone (urban footprint + quay box).
static func plateau_sd(x: float, z: float) -> float:
	var r := 70.0 if z < -23.0 else 30.0
	var qx := absf(x + 2.0) - (268.0 - r)
	var qz := absf(z + 23.0) - (259.0 - r)
	var u := r - (Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length() + minf(maxf(qx, qz), 0.0))
	var q := minf(minf(x - WorldLayout.QUAY_X, WorldLayout.QUAY_EAST - x), minf(z - WorldLayout.QUAY_NORTH, WorldLayout.QUAY_Z - z))
	return maxf(u, q)


static func beach_mask(x: float, z: float) -> float:
	var mx := (x - 160.0) / 120.0
	var mz := (z - 290.0) / 70.0
	return clampf(exp(-(mx * mx + mz * mz)) * 2.2, 0.0, 1.0)


## Signal Hill bump (0 outside its footprint).
static func hill(x: float, z: float) -> float:
	var dx := x - WorldLayout.HILL_CENTRE.x
	var dz := z - WorldLayout.HILL_CENTRE.y
	var r := sqrt(dx * dx + dz * dz)
	if r >= WorldLayout.HILL_RADIUS:
		return 0.0
	var rad := WorldLayout.HILL_RADIUS * (1.0 - 0.035 * (1.0 - sin(atan2(dz, dx) * 3.0 + 0.8)))
	var s := clampf(1.0 - r / rad, 0.0, 1.0)
	return WorldLayout.HILL_HEIGHT * s * s * (3.0 - 2.0 * s)


static func _seabed(x: float, z: float, o: float, dp: float, bm: float) -> float:
	var dep := 0.0
	if o < 0.0:
		var e := -o
		var shelf: float = e * 0.09 if e < 16.0 else 1.44 + (e - 16.0) * 0.36
		dep = lerpf(e * 0.24, shelf, bm)
		var wx := x - WorldLayout.SHIPWRECK.x
		var wz := z - WorldLayout.SHIPWRECK.y - 2.0
		dep += 4.5 * exp(-(wx * wx + wz * wz) / 1500.0) * smoothstep(6.0, 28.0, e)
		dep += 0.35 * sin(x * 0.09) * cos(z * 0.08) * smoothstep(8.0, 30.0, e)
		if dp > 0.0 and dp < 12.0:
			dep = maxf(dep, lerpf(-PORT_DEPTH, 0.0, dp / 12.0))
	if dp <= 0.0:
		dep = maxf(dep, -PORT_DEPTH + minf(-dp * 0.12, 9.0))
	return maxf(-dep, SEA_FLOOR)


## Land / sea height without flat pads and without the dirt track beds. Sets the s_* side results.
static func _land(x: float, z: float) -> float:
	s_sand = 0.0
	s_dirt = 0.0
	s_wild = false
	if x > -250.0 and z > -250.0 and z < 226.0 and (x < 128.0 or (x < 258.0 and z > -22.0)):
		s_coast = 30.0
		return WorldLayout.PLATEAU_Y
	if absf(x) > 372.0 or absf(z) > 372.0:
		s_coast = -80.0
		s_sand = 1.0
		return SEA_FLOOR
	var o := organic_sd(x, z)
	var dp := port_sd(x, z)
	var d := minf(o, dp)
	s_coast = d
	var bm := beach_mask(x, z)
	if d <= 0.0:
		s_sand = 1.0
		return _seabed(x, z, o, dp, bm)
	var h := WorldLayout.PLATEAU_Y
	var p := plateau_sd(x, z)
	if p < 0.0:
		s_wild = true
		s_sand = bm
		h *= 1.0 - pow(1.0 - d / (d - p), lerpf(2.2, 1.0, bm))
	var hl := hill(x, z)
	if hl > 0.0:
		s_wild = true
		h += hl * smoothstep(0.0, 16.0, d)
	if p < 0.0:
		var lx := x - 8.0
		var lz := z - 270.0
		var lr := lx * lx + lz * lz
		if lr < 4900.0:
			h += 3.2 * exp(-lr / 676.0) * smoothstep(0.0, 12.0, d) * smoothstep(0.0, 10.0, -p)
	return h


static func _with_pads(x: float, z: float, h_in: float) -> float:
	var h := h_in
	for pad: Array in _pads:
		var dx: float = x - float(pad[0])
		var dz: float = z - float(pad[1])
		var r: float = float(pad[2]) + float(pad[3])
		var d2 := dx * dx + dz * dz
		if d2 < r * r:
			var w := 1.0 - smoothstep(float(pad[2]), r, sqrt(d2))
			h = lerpf(h, float(pad[4]), w)
			s_dirt = maxf(s_dirt, w * float(pad[5]))
	return h


static func init_static() -> void:
	if _inited:
		return
	_inited = true
	var top := WorldLayout.HILL_CENTRE
	_pads = [[top.x, top.y, 9.0, 7.0, WorldLayout.PLATEAU_Y + WorldLayout.HILL_HEIGHT, 1.0]]
	var vp := WorldLayout.VIEWPOINT
	_pads.append([vp.x, vp.y, 8.0, 7.0, _land(175.2, -151.2), 0.7])
	var lh := WorldLayout.LIGHTHOUSE
	_pads.append([lh.x, lh.y, 7.0, 6.0, _land(lh.x, lh.y), 0.0])
	for flat: Array in WorldLayout.DIRT_TRACKS:
		var pts := Geom.catmull(WorldLayout.pts2(flat), 3.0)
		var ys := PackedFloat32Array()
		ys.resize(pts.size())
		var mn := pts[0]
		var mx := pts[0]
		for i in pts.size():
			var q := pts[i]
			var base := _land(q.x, q.y)
			ys[i] = _with_pads(q.x, q.y, base) if s_wild else base
			mn = Vector2(minf(mn.x, q.x), minf(mn.y, q.y))
			mx = Vector2(maxf(mx.x, q.x), maxf(mx.y, q.y))
		for pass_i in 3:
			var sm := ys.duplicate()
			for i in range(1, ys.size() - 1):
				sm[i] = (ys[i - 1] + ys[i] * 2.0 + ys[i + 1]) * 0.25
			ys = sm
		_tracks.append([pts, ys, mn - Vector2(10, 10), mx + Vector2(10, 10)])


## Full analytic sample: height plus the s_sand / s_dirt / s_wild / s_coast side results.
static func sample(x: float, z: float) -> float:
	if not _inited:
		init_static()
	var h := _land(x, z)
	if s_coast <= 0.0:
		return h
	if s_wild:
		h = _with_pads(x, z, h)
	for tr: Array in _tracks:
		var mn: Vector2 = tr[2]
		var mx: Vector2 = tr[3]
		if x <= mn.x or x >= mx.x or z <= mn.y or z >= mx.y:
			continue
		var pts: PackedVector2Array = tr[0]
		var ys: PackedFloat32Array = tr[1]
		var q := Vector2(x, z)
		var best := 1.0e12
		var best_y := 0.0
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var ab := pts[i] - a
			var t := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var d2 := (a + ab * t).distance_squared_to(q)
			if d2 < best:
				best = d2
				best_y = lerpf(ys[i - 1], ys[i], t)
		if best < 100.0:
			var dist := sqrt(best)
			h = lerpf(h, best_y, 1.0 - smoothstep(4.0, 9.5, dist))
			s_dirt = maxf(s_dirt, 1.0 - smoothstep(2.6, 4.8, dist))
	return h


## Terrain height (world Y) at x,z - below 0 under the sea.
static func height(x: float, z: float) -> float:
	return sample(x, z)


## Natural surface name of the terrain (no roads / slabs): "grass", "sand" or "dirt".
static func surface(x: float, z: float) -> String:
	var h := sample(x, z)
	if s_coast <= 0.0 or h < 0.8 or s_sand > 0.5:
		return "sand"
	if s_dirt > 0.5:
		return "dirt"
	return "grass"


# ---------------------------------------------------------------------------------------------
# generated surface
# ---------------------------------------------------------------------------------------------

func build() -> void:
	var t0 := Time.get_ticks_msec()
	init_static()
	var total := N * N
	heights.resize(total)
	kinds.resize(total)
	var cols := PackedColorArray()
	cols.resize(total)
	var k := 0
	for j in N:
		var z := float(j - HALF) * CELL
		for i in N:
			var x := float(i - HALF) * CELL
			var h := sample(x, z)
			heights[k] = h
			cols[k] = Color(s_sand, s_dirt, 0.0 if s_wild else 1.0, 1.0)
			var kd := 0
			if s_coast <= 0.0 or h < 0.8 or s_sand > 0.5:
				kd = 1
			elif s_dirt > 0.5:
				kd = 2
			if s_wild:
				kd |= 4
			kinds[k] = kd
			k += 1

	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	var per := CHUNK + 1
	@warning_ignore("integer_division")
	var chunks: int = (N - 1) / CHUNK
	for cz in chunks:
		for cx in chunks:
			var verts := PackedVector3Array()
			var vcol := PackedColorArray()
			var idx := PackedInt32Array()
			verts.resize(per * per)
			vcol.resize(per * per)
			idx.resize(CHUNK * CHUNK * 6)
			var vi := 0
			for j in per:
				var gj := cz * CHUNK + j
				for i in per:
					var gi := cx * CHUNK + i
					var g := gj * N + gi
					verts[vi] = Vector3(float(gi - HALF) * CELL, heights[g], float(gj - HALF) * CELL)
					vcol[vi] = cols[g]
					vi += 1
			var ii := 0
			for j in CHUNK:
				for i in CHUNK:
					var a := j * per + i
					idx[ii] = a
					idx[ii + 1] = a + 1
					idx[ii + 2] = a + per + 1
					idx[ii + 3] = a
					idx[ii + 4] = a + per + 1
					idx[ii + 5] = a + per
					ii += 6
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_COLOR] = vcol
			arr[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mi := MeshInstance3D.new()
			mi.name = "TerrainChunk_%d_%d" % [cx, cz]
			mi.mesh = mesh
			mi.material_override = mat
			# the shader computes flat normals itself; shadows only matter on the island chunks
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)

	# far seabed (flat, purely visual; a world boundary plane is the physical floor out there)
	var far := PlaneMesh.new()
	far.size = Vector2(3400.0, 3400.0)
	var far_mi := MeshInstance3D.new()
	far_mi.name = "FarSeabed"
	far_mi.mesh = far
	far_mi.material_override = mat
	far_mi.position = Vector3(0.0, SEA_FLOOR - 0.05, 0.0)
	far_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_mi)

	# collision: one trimesh per natural surface so Fx.surface_of() gets grass / sand / dirt
	var f_grass := PackedVector3Array()
	var f_sand := PackedVector3Array()
	var f_dirt := PackedVector3Array()
	var flat := SEA_FLOOR + 0.01
	for j in N - 1:
		var z0 := float(j - HALF) * CELL
		for i in N - 1:
			var g := j * N + i
			var ha := heights[g]
			var hb := heights[g + 1]
			var hc := heights[g + N + 1]
			var hd := heights[g + N]
			if ha <= flat and hb <= flat and hc <= flat and hd <= flat:
				continue
			var x0 := float(i - HALF) * CELL
			var a := Vector3(x0, ha, z0)
			var b := Vector3(x0 + CELL, hb, z0)
			var c := Vector3(x0 + CELL, hc, z0 + CELL)
			var d := Vector3(x0, hd, z0 + CELL)
			match kinds[g] & 3:
				1:
					f_sand.append(a); f_sand.append(b); f_sand.append(c)
					f_sand.append(a); f_sand.append(c); f_sand.append(d)
				2:
					f_dirt.append(a); f_dirt.append(b); f_dirt.append(c)
					f_dirt.append(a); f_dirt.append(c); f_dirt.append(d)
				_:
					f_grass.append(a); f_grass.append(b); f_grass.append(c)
					f_grass.append(a); f_grass.append(c); f_grass.append(d)
	var names := ["grass", "sand", "dirt"]
	var faces: Array = [f_grass, f_sand, f_dirt]
	for s in 3:
		var fs: PackedVector3Array = faces[s]
		if fs.is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = "TerrainBody_" + str(names[s])
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.set_meta("surface", names[s])
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(fs)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		if s == 1:
			var floor_cs := CollisionShape3D.new()
			var plane := WorldBoundaryShape3D.new()
			plane.plane = Plane(Vector3.UP, SEA_FLOOR)
			floor_cs.shape = plane
			body.add_child(floor_cs)
		add_child(body)
	build_ms = Time.get_ticks_msec() - t0


## Exact height of the generated terrain surface (triangle interpolation of the 3 m lattice).
func get_mesh_height(x: float, z: float) -> float:
	var fx := x / CELL + float(HALF)
	var fz := z / CELL + float(HALF)
	if heights.is_empty() or fx < 0.0 or fz < 0.0 or fx >= float(N - 1) or fz >= float(N - 1):
		return Terrain.height(x, z)
	var i := int(fx)
	var j := int(fz)
	fx -= float(i)
	fz -= float(j)
	var g := j * N + i
	var ha := heights[g]
	var hc := heights[g + N + 1]
	if fx >= fz:
		var hb := heights[g + 1]
		return ha + (hb - ha) * fx + (hc - hb) * fz
	var hd := heights[g + N]
	return ha + (hc - hd) * fx + (hd - ha) * fz


## Triangles of the land part of the lattice (source geometry for the navigation bake).
func get_land_faces(min_y: float = 0.2) -> PackedVector3Array:
	var out := PackedVector3Array()
	for j in N - 1:
		var z0 := float(j - HALF) * CELL
		for i in N - 1:
			var g := j * N + i
			var ha := heights[g]
			var hb := heights[g + 1]
			var hc := heights[g + N + 1]
			var hd := heights[g + N]
			if maxf(maxf(ha, hb), maxf(hc, hd)) < min_y:
				continue
			var x0 := float(i - HALF) * CELL
			var a := Vector3(x0, ha, z0)
			var c := Vector3(x0 + CELL, hc, z0 + CELL)
			out.append(a)
			out.append(Vector3(x0 + CELL, hb, z0))
			out.append(c)
			out.append(a)
			out.append(c)
			out.append(Vector3(x0, hd, z0 + CELL))
	return out


## Lattice surface class at x,z: 0 grass, 1 sand, 2 dirt (bit 2 = outside the city plateau).
func get_kind(x: float, z: float) -> int:
	var i := int(round(x / CELL)) + HALF
	var j := int(round(z / CELL)) + HALF
	if kinds.is_empty() or i < 0 or j < 0 or i >= N or j >= N:
		return 1
	return kinds[j * N + i]
