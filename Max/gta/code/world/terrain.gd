class_name Terrain
extends RefCounted
## Analytic terrain for Vesper Bay: one height function drives the render mesh, the
## collision mesh, water detection and AI/gameplay height queries.
##
## Layout (x east, z south, metres):  the flat city plateau is y = 0;  Lookout Hill fills
## the north-west corner (x,z < -59);  the beach / sea floor starts south of z = 222;
## the sea also wraps the east side (x > 296);  hills rise beyond the north and west edges.

const SEA := -1.0
const HILL_EDGE := -59.0
const PEAK := Vector2(-195.0, -195.0)
const PEAK_H := 30.0
const COAST_Z := 222.0
const EAST_X := 296.0
const CELL := 2.5
const EXTENT := 470.0
const CHUNK_CELLS := 32

static var _noise: FastNoiseLite
static var _road_pts: PackedVector3Array = PackedVector3Array()
static var _road_w: PackedFloat32Array = PackedFloat32Array()
static var _road_hash: Dictionary = {}
static var _grid: PackedFloat32Array = PackedFloat32Array()
static var _gn := 0
static var ready := false

static func _ensure_noise() -> void:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 4217
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.021
		_noise.fractal_octaves = 3

## Register road centre-line samples (with their design height) that the terrain must be
## flattened to. `half_width` is the flat half width; the blend continues ~16 m beyond.
static func add_road(points: PackedVector3Array, half_width: float) -> void:
	for p in points:
		var idx := _road_pts.size()
		_road_pts.append(p)
		_road_w.append(half_width)
		var key := Vector2i(int(floor(p.x / 12.0)), int(floor(p.z / 12.0)))
		if not _road_hash.has(key):
			_road_hash[key] = PackedInt32Array()
		var arr: PackedInt32Array = _road_hash[key]
		arr.append(idx)
		_road_hash[key] = arr

static func clear_roads() -> void:
	_road_pts = PackedVector3Array()
	_road_w = PackedFloat32Array()
	_road_hash = {}
	ready = false

static func _pw(x: float, pts: Array) -> float:
	# piecewise-linear lookup: pts = [x0, y0, x1, y1, ...]
	if x <= pts[0]:
		return pts[1]
	var n := pts.size()
	var i := 2
	while i < n:
		if x <= pts[i]:
			var t: float = (x - pts[i - 2]) / (pts[i] - pts[i - 2])
			return lerpf(pts[i - 1], pts[i + 1], t)
		i += 2
	return pts[n - 1]

## The hill dome without noise (used to design road profiles).
static func dome(x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(PEAK)
	var base := PEAK_H * (1.0 - smoothstep(18.0, 128.0, d))
	var margin := minf(HILL_EDGE - x, HILL_EDGE - z)
	return base * smoothstep(0.0, 26.0, margin)

static func in_city(x: float, z: float) -> bool:
	if x < -300.0 or x > EAST_X or z < -300.0 or z > COAST_Z:
		return false
	return not (x < HILL_EDGE and z < HILL_EDGE)

## Terrain height before road flattening.
static func raw_height(x: float, z: float) -> float:
	_ensure_noise()
	var h := 0.0
	var out_w := maxf(-300.0 - x, 0.0)
	var out_n := maxf(-300.0 - z, 0.0)
	if x < HILL_EDGE and z < HILL_EDGE:
		var d := Vector2(x, z).distance_to(PEAK)
		var base := PEAK_H * (1.0 - smoothstep(18.0, 128.0, d))
		base += _noise.get_noise_2d(x, z) * 2.4 * smoothstep(0.0, 8.0, base)
		var margin := minf(HILL_EDGE - x, HILL_EDGE - z)
		h = maxf(base, 0.0) * smoothstep(0.0, 26.0, margin)
	var outside := maxf(out_w, out_n)
	if outside > 0.0:
		var ridge := smoothstep(0.0, 110.0, outside) * (27.0 + 15.0 * _noise.get_noise_2d(x * 0.55, z * 0.55))
		ridge *= 1.0 - smoothstep(270.0, 335.0, x)       # the ridge falls into the sea in the east
		h += maxf(ridge, 0.0)
	if z > COAST_Z:
		var s := z - COAST_Z
		var beach := _pw(s, [0.0, -0.25, 14.0, -1.0, 40.0, -3.4, 78.0, -11.0, 150.0, -16.0])
		beach += _noise.get_noise_2d(x * 2.0, z * 2.0) * 0.12 * smoothstep(-0.9, -3.0, beach)
		var dock := _pw(s, [0.0, -6.5, 60.0, -8.5, 130.0, -14.0])
		var k := smoothstep(30.0, 44.0, x)
		var c := lerpf(beach, dock, k)
		# rock breakwater between beach and harbour
		var mole := (1.0 - smoothstep(2.5, 6.5, absf(x - 37.0))) * (1.0 - smoothstep(62.0, 74.0, s))
		c = lerpf(c, 1.3 - s * 0.006, mole)
		if x > EAST_X:
			c = minf(c, _pw(x - EAST_X, [0.0, -3.0, 50.0, -9.0, 140.0, -15.0]))
		# rocky headland closes the beach in the west
		var head := smoothstep(0.0, 45.0, out_w) * (1.0 - smoothstep(40.0, 110.0, s))
		h = lerpf(c, maxf(h, 6.0 + 8.0 * head), head)
	elif x > EAST_X:
		var e := x - EAST_X
		var shore := _pw(e, [0.0, -0.4, 5.0, -3.0, 50.0, -9.0, 140.0, -15.0])
		if out_n > 0.0:
			h = lerpf(shore, h, 1.0 - smoothstep(0.0, 30.0, e))
		else:
			h = shore
	return h

static func _road_influence(x: float, z: float, h: float) -> float:
	if _road_pts.is_empty():
		return h
	var cx := int(floor(x / 12.0))
	var cz := int(floor(z / 12.0))
	var best := 1.0e9
	var best_i := -1
	for ox in range(-2, 3):
		for oz in range(-2, 3):
			var key := Vector2i(cx + ox, cz + oz)
			if not _road_hash.has(key):
				continue
			var arr: PackedInt32Array = _road_hash[key]
			for i in arr:
				var p := _road_pts[i]
				var dx := p.x - x
				var dz := p.z - z
				var d2 := dx * dx + dz * dz
				if d2 < best:
					best = d2
					best_i = i
	if best_i < 0:
		return h
	var d := sqrt(best)
	var hw := _road_w[best_i]
	var rh := _road_pts[best_i].y
	if d <= hw + 1.0:
		return rh
	return lerpf(rh, h, smoothstep(hw + 1.0, hw + 17.0, d))

static func height(x: float, z: float) -> float:
	var h := raw_height(x, z)
	if x < HILL_EDGE + 8.0 and z < HILL_EDGE + 8.0:
		h = _road_influence(x, z, h)
	return h

## Distance (metres) from (x,z) to the nearest registered hill-road sample, or 1e9.
static func road_distance(x: float, z: float) -> float:
	var cx := int(floor(x / 12.0))
	var cz := int(floor(z / 12.0))
	var best := 1.0e18
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			var key := Vector2i(cx + ox, cz + oz)
			if _road_hash.has(key):
				var arr: PackedInt32Array = _road_hash[key]
				for i in arr:
					var p := _road_pts[i]
					best = minf(best, (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z))
	return sqrt(best)

# ---------------------------------------------------------------- cached grid
static func build_grid() -> void:
	_gn = int(round(EXTENT * 2.0 / CELL)) + 1
	_grid.resize(_gn * _gn)
	for j in _gn:
		var z := -EXTENT + j * CELL
		for i in _gn:
			var x := -EXTENT + i * CELL
			var v := 0.0
			if not _deep_inside_city(x, z):
				v = height(x, z)
			_grid[j * _gn + i] = v
	ready = true

static func _deep_inside_city(x: float, z: float) -> bool:
	return in_city(x - 3.0, z - 3.0) and in_city(x + 3.0, z + 3.0) and in_city(x - 3.0, z + 3.0) and in_city(x + 3.0, z - 3.0)

## Fast bilinear height lookup (falls back to the analytic function outside the grid).
static func sample(x: float, z: float) -> float:
	if not ready:
		return height(x, z)
	var fx := (x + EXTENT) / CELL
	var fz := (z + EXTENT) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= float(_gn - 1) or fz >= float(_gn - 1):
		return height(x, z)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var a := _grid[j * _gn + i]
	var b := _grid[j * _gn + i + 1]
	var c := _grid[(j + 1) * _gn + i]
	var d := _grid[(j + 1) * _gn + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

static func is_water(x: float, z: float) -> bool:
	if z <= COAST_Z and x <= EAST_X:
		return false
	return sample(x, z) < SEA - 0.05

static func normal(x: float, z: float) -> Vector3:
	var e := 1.25
	var hx := sample(x + e, z) - sample(x - e, z)
	var hz := sample(x, z + e) - sample(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()

# ---------------------------------------------------------------- colours
static func ground_color(x: float, z: float, h: float, slope: float) -> Color:
	var n := _noise.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5
	var sand := Assets.color("sand")
	var col: Color
	if z > COAST_Z or x > EAST_X:
		if h > -0.55:
			col = sand
			if absf(x - 37.0) < 8.0 and z > COAST_Z:
				col = Assets.color("rock").lerp(Assets.color("rock_dark"), n)
		elif h > -1.6:
			col = sand.lerp(Assets.color("sand_wet"), smoothstep(-0.55, -1.1, h))
		else:
			col = Assets.color("sand_wet").lerp(Color(0.16, 0.27, 0.3), smoothstep(-1.6, -9.0, h))
		if slope > 0.5:
			col = col.lerp(Assets.color("rock_dark"), smoothstep(0.5, 0.8, slope))
		if h > 2.0:
			col = Assets.color("grass_dark").lerp(Assets.color("rock"), smoothstep(0.35, 0.7, slope))
	else:
		var g := Assets.color("grass").lerp(Assets.color("grass_dark"), n)
		g = g.lerp(Assets.color("grass_dry"), 0.25 * smoothstep(0.55, 0.9, _noise.get_noise_2d(x * 0.4 + 90.0, z * 0.4) * 0.5 + 0.5))
		col = g.lerp(Assets.color("rock"), smoothstep(0.5, 0.85, slope))
		var rd := road_distance(x, z)
		if rd < 9.0:
			col = col.lerp(Assets.color("dirt"), 1.0 - smoothstep(4.5, 9.0, rd))
		var outside := maxf(maxf(-300.0 - x, -300.0 - z), 0.0)
		if outside > 0.0:
			col = col.lerp(Color(0.2, 0.32, 0.27), smoothstep(0.0, 120.0, outside) * 0.6)
	return col.srgb_to_linear()

# ---------------------------------------------------------------- mesh + collision
## Builds chunked terrain meshes under `parent` plus one static trimesh body.
static func build(parent: Node3D, material: Material) -> void:
	if not ready:
		build_grid()
	var cells := _gn - 1
	var faces := PackedVector3Array()
	var cz0 := 0
	while cz0 < cells:
		var cx0 := 0
		while cx0 < cells:
			_build_chunk(parent, material, cx0, cz0, mini(CHUNK_CELLS, cells - cx0), mini(CHUNK_CELLS, cells - cz0), faces)
			cx0 += CHUNK_CELLS
		cz0 += CHUNK_CELLS
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = Phys.WORLD
	body.collision_mask = 0
	body.set_meta("surface", &"ground")
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)

static func _build_chunk(parent: Node3D, material: Material, cx0: int, cz0: int, nx: int, nz: int, faces: PackedVector3Array) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var vmap := {}
	for j in nz:
		for i in nx:
			var gi := cx0 + i
			var gj := cz0 + j
			var x0 := -EXTENT + gi * CELL
			var z0 := -EXTENT + gj * CELL
			if _deep_inside_city(x0, z0) and _deep_inside_city(x0 + CELL, z0 + CELL):
				continue
			var corner: Array[int] = []
			for c: Array in [[0, 0], [1, 0], [0, 1], [1, 1]]:
				var ki: int = gi + c[0]
				var kj: int = gj + c[1]
				var key := kj * _gn + ki
				if not vmap.has(key):
					var x := -EXTENT + ki * CELL
					var z := -EXTENT + kj * CELL
					var h := _grid[key]
					var nrm := normal(x, z)
					vmap[key] = verts.size()
					verts.append(Vector3(x, h, z))
					norms.append(nrm)
					cols.append(ground_color(x, z, h, 1.0 - nrm.y))
					uvs.append(Vector2(3.0 if (z <= COAST_Z and x <= EAST_X) else 4.0, 1.0))
				corner.append(vmap[key])
			# two triangles (clockwise winding = front face in Godot)
			idx.append(corner[0]); idx.append(corner[1]); idx.append(corner[2])
			idx.append(corner[1]); idx.append(corner[3]); idx.append(corner[2])
			var a := verts[corner[0]]
			var b := verts[corner[1]]
			var c2 := verts[corner[2]]
			var d := verts[corner[3]]
			# collision only where gameplay can reach
			if absf(a.x) < 420.0 and absf(a.z) < 420.0:
				faces.append(a); faces.append(b); faces.append(c2)
				faces.append(b); faces.append(d); faces.append(c2)
	if idx.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain_%d_%d" % [cx0 / CHUNK_CELLS, cz0 / CHUNK_CELLS]
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
