extends RefCounted
## WORLD module helper: FALLBACK navigation mesh built directly as a conforming 2 m polygon grid from the
## layout. World normally bakes a Recast mesh on a worker thread; this grid is used when that bake fails
## or with the user flag --nav_grid. The work is time-sliced: call step(budget_ms) every frame until it
## returns true, then take "mesh". Module-private (no class_name).

const CELL := 2.0
const HALF := 150                 ## lattice spans +-300 m
const N := 301
const MAX_STEP := 1.9             ## max height difference inside one cell (about 43 degrees)
const MIN_LAND_Y := 0.25

var mesh: NavigationMesh
var done := false
var polygon_count := 0
var work_ms := 0.0

var _w: Node3D
var _terrain: Terrain
var _hs := PackedFloat32Array()
var _ok := PackedByteArray()
var _vidx := PackedInt32Array()
var _verts := PackedVector3Array()
var _blocked: Array = []
var _phase := 0
var _row := 0


## blocked: rectangles [x0, z0, x1, z1] that are carved out (building lots / footprints).
func start(world: Node3D, blocked: Array) -> void:
	_w = world
	_terrain = world.get("terrain")
	_hs.resize(N * N)
	_ok.resize(N * N)
	_ok.fill(0)
	_vidx.resize(N * N)
	_vidx.fill(-1)
	_verts = PackedVector3Array()
	_blocked = blocked
	mesh = NavigationMesh.new()
	_phase = 0
	_row = 0
	done = false
	polygon_count = 0
	work_ms = 0.0


func step(budget_ms: float) -> bool:
	if done:
		return true
	var t0 := Time.get_ticks_usec()
	var limit := int(budget_ms * 1000.0)
	while not done and Time.get_ticks_usec() - t0 < limit:
		match _phase:
			0:
				_sample_row(_row)
				_row += 1
				if _row >= N:
					_phase = 1
			1:
				_carve()
				_phase = 2
				_row = 0
			2:
				_emit_row(_row)
				_row += 1
				if _row >= N - 1:
					_phase = 3
			_:
				mesh.vertices = _verts
				done = true
	work_ms += float(Time.get_ticks_usec() - t0) / 1000.0
	return done


func _sample_row(j: int) -> void:
	var z := float(j - HALF) * CELL
	var base := j * N
	for i in N:
		var x := float(i - HALF) * CELL
		var h := _terrain.get_mesh_height(x, z)
		if h < MIN_LAND_Y:
			# open water: only the piers are walkable
			var top := float(_w.call("get_height", x, z))
			if top > 0.6:
				_hs[base + i] = top
				_ok[base + i] = 1
			continue
		_hs[base + i] = float(_w.call("get_height", x, z))
		_ok[base + i] = 1


func _carve() -> void:
	for r: Array in _blocked:
		var i0 := maxi(int(ceil(float(r[0]) / CELL)) + HALF, 0)
		var i1 := mini(int(floor(float(r[2]) / CELL)) + HALF, N - 1)
		var j0 := maxi(int(ceil(float(r[1]) / CELL)) + HALF, 0)
		var j1 := mini(int(floor(float(r[3]) / CELL)) + HALF, N - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				_ok[j * N + i] = 0


func _vertex(g: int) -> int:
	var v := _vidx[g]
	if v >= 0:
		return v
	v = _verts.size()
	@warning_ignore("integer_division")
	var j := g / N
	var i := g - j * N
	_verts.append(Vector3(float(i - HALF) * CELL, _hs[g], float(j - HALF) * CELL))
	_vidx[g] = v
	return v


func _emit_row(j: int) -> void:
	var base := j * N
	for i in N - 1:
		var g := base + i
		if _ok[g] == 0 or _ok[g + 1] == 0 or _ok[g + N] == 0 or _ok[g + N + 1] == 0:
			continue
		var ha := _hs[g]
		var hb := _hs[g + 1]
		var hc := _hs[g + N + 1]
		var hd := _hs[g + N]
		if maxf(maxf(ha, hb), maxf(hc, hd)) - minf(minf(ha, hb), minf(hc, hd)) > MAX_STEP:
			continue
		mesh.add_polygon(PackedInt32Array([_vertex(g), _vertex(g + 1), _vertex(g + N + 1), _vertex(g + N)]))
		polygon_count += 1
