class_name World
extends Node3D
## HALCYON BAY world foundation (system "world", Game.world): terrain, coast, roads, lanes, sidewalks,
## lots, named locations, spawn points, navigation and minimap data. Everything is generated in code
## at boot from the deterministic data in WorldLayout. Contract: docs/ARCHITECTURE.md 6.1, details and
## the map description: docs/WORLD.md.

signal nav_ready                       ## a navigation mesh has been installed on nav_region

const Geom := preload("res://gta/code/world/gen/world_geom.gd")
const LotGen := preload("res://gta/code/world/gen/world_lots.gd")
const CityMesh := preload("res://gta/code/world/gen/world_citymesh.gd")
const Points := preload("res://gta/code/world/gen/world_points.gd")
const NavGen := preload("res://gta/code/world/gen/world_nav.gd")

const S_NONE := 0
const S_ASPHALT := 1
const S_CONCRETE := 2
const S_GRASS := 3
const S_WOOD := 4
const SURFACE_NAMES: Array[String] = ["", "asphalt", "concrete", "grass", "wood"]
const NAV_CACHE_VERSION := 2
const NAV_BAKE_TIMEOUT_MS := 60000

const LOCATION_LABELS := {
	"police_station": "HBPD", "hospital": "Bayview Medical", "gun_shop": "Bay Arms", "mod_garage": "Torque Garage",
	"clothing_store": "Tide Threads", "barber": "Clip Joint", "general_store": "Corner Cart", "gas_station": "Sunfuel",
	"parking_garage": "Stack Parking", "safehouse": "Safehouse", "shooting_range": "Bay Arms Range",
	"airport_hangar": "Hangar One", "airport_helipad": "Helipad", "lighthouse": "Halcyon Light",
	"downtown_plaza": "Founders Plaza", "industrial_yard": "Foundry Yard", "residential_park": "Sandpiper Park",
	"hill_viewpoint": "Signal Hill Lookout", "hill_top": "Signal Mast", "beach": "Halcyon Beach", "marina_dock": "Marina",
	"tram_stop_1": "Tram - Plaza", "tram_stop_2": "Tram - Sandpiper", "tram_stop_3": "Tram - Tideline",
	"taxi_stand": "Taxi Stand", "airport_runway_start": "Runway 09",
}

var roads: RoadGraph
var walk: WalkGraph
var nav_region: NavigationRegion3D
var terrain: Terrain
var stats := {}                        ## build statistics (ms per stage, counts)

var _lots: Array[Dictionary] = []
var _slabs: Array = []
var _slab_lots: Array = []             ## per slab: Array of [x0, z0, x1, z1, surface code, y]
var _slab_cells := {}                  ## 16 m grid -> PackedInt32Array of slab indices
var _decks: Array = []                 ## [x0, z0, x1, z1, y, surface code]
var _wedges: Array = []                ## [min x, min z, max x, max z, centre, outer radius]
var _locations := {}
var _spawns := {}                      ## kind -> Array[Transform3D]
var _transit_path := PackedVector3Array()
var _transit_stops: Array[Dictionary] = []
var _tram2d := PackedVector2Array()
var _minimap := {}
var _signal_heads: Array[Dictionary] = []
var _nav: NavGen                       ## fallback grid builder while it is running
var _nav_ready := false
var _nav_bake_id := 0
var _nav_baking := false
var _nav_started_ms := 0
var _nav_cache_path := ""
var _nav_rects: Array = []
var _nav_pending: NavigationMesh       ## baked mesh waiting to be installed from _process (not from the bake callback)
var _nav_pending_source := ""
var _nav_verify_at_ms := 0             ## real-time deadline of the next "did the server take the mesh" check
var _nav_verify_tries := 0
var _city: CityMesh
var _built := false
var _p_y := 0.0
var _empty := PackedInt32Array()
var _warned := {}

var _y0: float = WorldLayout.PLATEAU_Y
var _yr: float = WorldLayout.PLATEAU_Y + WorldLayout.ROAD_LIFT
var _ys: float = WorldLayout.PLATEAU_Y + WorldLayout.CURB_H
var _yd: float = WorldLayout.PLATEAU_Y + WorldLayout.DECK_LIFT


# ---------------------------------------------------------------------------------------------
# boot
# ---------------------------------------------------------------------------------------------

func setup() -> void:
	if _built:
		return
	_built = true
	var t0 := Time.get_ticks_msec()
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build()
	var t1 := Time.get_ticks_msec()

	roads = RoadGraph.new()
	roads.build(terrain)
	var lotgen := LotGen.new()
	lotgen.build(roads, terrain)
	_lots = lotgen.lots
	_slabs = lotgen.slabs
	for e in lotgen.errors:
		push_warning("[World] layout: " + e)
	var t2 := Time.get_ticks_msec()

	_tram2d = _build_tram_loop()
	var city := CityMesh.new()
	city.build(self, roads, lotgen, _tram2d)
	_city = city
	_build_ground_index()
	var t3 := Time.get_ticks_msec()

	walk = WalkGraph.new()
	walk.build(roads, get_height)
	var t4 := Time.get_ticks_msec()

	var pts := Points.new()
	pts.build(self, _lots, _tram2d, city.parking_bays, city.driveways)
	_locations = pts.locations
	for k: String in pts.spawns:
		var typed: Array[Transform3D] = []
		typed.assign(pts.spawns[k])
		_spawns[k] = typed
	_transit_path = pts.transit_path
	_transit_stops = pts.transit_stops
	_signal_heads = roads.get_signal_heads()
	var t5 := Time.get_ticks_msec()

	# no placeholder mesh: a second mesh assignment while the server still builds the first region
	# iteration on its worker thread can get lost (see _verify_nav)
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	add_child(nav_region)
	_start_navigation([], true)

	var zone_count := {}
	for lot in _lots:
		zone_count[lot["zone"]] = int(zone_count.get(lot["zone"], 0)) + 1
	var signals := 0
	for n in roads.intersections:
		if n["has_signal"]:
			signals += 1
	stats.merge({
		"terrain_ms": t1 - t0, "roads_lots_ms": t2 - t1, "mesh_ms": t3 - t2, "walk_ms": t4 - t3, "points_ms": t5 - t4,
		"setup_ms": Time.get_ticks_msec() - t0, "segments": roads.segments.size(), "lanes": roads.lanes.size(),
		"intersections": roads.intersections.size(), "signals": signals, "lots": _lots.size(), "lots_by_zone": zone_count,
		"walk_nodes": walk.node_count(), "city_tris": city.tri_total, "lane_km": roads.total_lane_length / 1000.0,
	}, true)
	print("[World] built in %d ms (terrain %d, roads+lots %d, city mesh %d, walk %d, points %d) | %d segments, %d lanes, %d intersections (%d signalised), %d lots, %d walk nodes, %d city tris" % [
			stats["setup_ms"], stats["terrain_ms"], stats["roads_lots_ms"], stats["mesh_ms"], stats["walk_ms"], stats["points_ms"],
			stats["segments"], stats["lanes"], stats["intersections"], signals, _lots.size(), walk.node_count(), city.tri_total])


func _physics_process(delta: float) -> void:
	if roads != null:
		roads.advance(delta)


func _process(_delta: float) -> void:
	var busy := false
	if _nav != null:
		busy = true
		if _nav.step(5.0):
			var grid_mesh := _nav.mesh
			stats["nav_ms"] = _nav.work_ms
			_nav = null
			_install_nav(grid_mesh, "grid")
	elif _nav_pending != null:
		busy = true
		var pending := _nav_pending
		_nav_pending = null
		_install_nav(pending, _nav_pending_source)
	elif _nav_baking:
		busy = true
		if Time.get_ticks_msec() - _nav_started_ms > NAV_BAKE_TIMEOUT_MS:
			push_warning("[World] navigation bake timed out, building the grid fallback")
			_nav_bake_id += 1
			_nav_baking = false
			_start_grid_nav()
	if _nav_verify_at_ms > 0:
		busy = true
		if Time.get_ticks_msec() >= _nav_verify_at_ms:
			_verify_nav()
	if not busy:
		set_process(false)


## The navigation server builds region iterations asynchronously; an update that arrives while a build is
## in flight can be dropped. Check that the map really answers from the installed mesh and re-submit if not.
func _verify_nav() -> void:
	_nav_verify_at_ms = 0
	var nm := nav_region.navigation_mesh
	if nm == null or nm.get_vertices().is_empty() or not is_inside_tree():
		return
	var probe: Vector3 = nm.get_vertices()[0]
	var got := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, probe)
	if got.distance_to(probe) <= 1.5:
		stats["nav_verified"] = true
		return
	if _nav_verify_tries < 10:
		_nav_verify_tries += 1
		NavigationServer3D.region_set_navigation_mesh(nav_region.get_rid(), nm)
		_nav_verify_at_ms = Time.get_ticks_msec() + 350


# ---------------------------------------------------------------------------------------------
# navigation mesh
# ---------------------------------------------------------------------------------------------

## Rectangles [x0, z0, x1, z1] carved out of the navigation mesh.
func _blocked_rects(obstacles: Array, carve_lots: bool) -> Array:
	var out: Array = obstacles.duplicate()
	if carve_lots:
		for lot in _lots:
			var zone: String = lot["zone"]
			var lm: String = lot["landmark"]
			if zone in ["plaza", "park", "parking"] or lm.begins_with("tram_stop"):
				continue
			var c: Vector3 = lot["center"]
			var size: Vector2 = lot["size"]
			var sideways := absf(sin(float(lot["yaw"]))) > 0.5
			var hx := (size.y if sideways else size.x) * 0.5 - 1.0
			var hz := (size.x if sideways else size.y) * 0.5 - 1.0
			if hx > 0.5 and hz > 0.5:
				out.append([c.x - hx, c.z - hz, c.x + hx, c.z + hz])
	return out


## Installs a cached mesh, or bakes one with Recast on a worker thread (cached in user:// afterwards).
## Falls back to the direct 2 m grid when the bake fails. User flags: --nav_grid, --nav_nocache.
func _start_navigation(obstacles: Array, carve_lots: bool) -> void:
	_nav_ready = false
	_nav = null
	_nav_bake_id += 1
	_nav_rects = _blocked_rects(obstacles, carve_lots)
	var key := hash([NAV_CACHE_VERSION, WorldLayout.SEED, _nav_rects, hash(terrain.heights), _city.tri_total, roads.segments.size()])
	_nav_cache_path = "user://halcyon_nav_%d_%x.res" % [NAV_CACHE_VERSION, key]
	if Game.flags.has("nav_grid"):
		_start_grid_nav()
		return
	if not Game.flags.has("nav_nocache") and FileAccess.file_exists(_nav_cache_path):
		var res: Resource = ResourceLoader.load(_nav_cache_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is NavigationMesh and (res as NavigationMesh).get_polygon_count() > 50:
			_nav_pending = res as NavigationMesh
			_nav_pending_source = "cache"
			set_process(true)
			return
	var src := NavigationMeshSourceGeometryData3D.new()
	var faces := terrain.get_land_faces(0.2)
	faces.append_array(_city.asphalt.v)
	faces.append_array(_city.g_concrete.v)
	faces.append_array(_city.g_grass.v)
	faces.append_array(_city.g_wood.v)
	src.add_faces(faces, Transform3D.IDENTITY)
	for r: Array in _nav_rects:
		var x0 := float(r[0])
		var z0 := float(r[1])
		var x1 := float(r[2])
		var z1 := float(r[3])
		src.add_projected_obstruction(PackedVector3Array([Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1),
				Vector3(x0, 0.0, z1)]), 0.0, 45.0, true)
	var nm := NavigationMesh.new()
	nm.cell_size = 0.5                     # baked coarser than the map cell size (0.25); reset after the bake
	nm.cell_height = 0.25
	nm.agent_height = 1.75
	nm.agent_radius = 0.5
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 44.0
	nm.region_min_size = 6.0
	nm.region_merge_size = 20.0
	nm.edge_max_length = 0.0
	nm.edge_max_error = 1.3
	nm.vertices_per_polygon = 6.0
	nm.detail_sample_distance = 12.0
	nm.detail_sample_max_error = 2.0
	nm.filter_baking_aabb = AABB(Vector3(-306.0, -2.0, -306.0), Vector3(612.0, 60.0, 612.0))
	_nav_baking = true
	_nav_started_ms = Time.get_ticks_msec()
	set_process(true)
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, _on_nav_baked.bind(nm, _nav_bake_id))


func _on_nav_baked(nm: NavigationMesh, bake_id: int) -> void:
	if bake_id != _nav_bake_id:
		return
	_nav_baking = false
	stats["nav_ms"] = Time.get_ticks_msec() - _nav_started_ms
	if nm == null or nm.get_polygon_count() < 50:
		push_warning("[World] navigation bake returned no usable mesh, building the grid fallback")
		_start_grid_nav()
		return
	nm.cell_size = 0.25                    # vertices lie on a 0.5 m grid, which the 0.25 m map grid contains
	var err := ResourceSaver.save(nm, _nav_cache_path)
	if err != OK:
		push_warning("[World] could not cache the navigation mesh (%d)" % err)
	# the server is in the middle of its own sync while it runs this callback: install on the next frame
	_nav_pending = nm
	_nav_pending_source = "recast"
	set_process(true)


func _start_grid_nav() -> void:
	_nav = NavGen.new()
	_nav.start(self, _nav_rects)
	set_process(true)


func _install_nav(nm: NavigationMesh, source: String) -> void:
	nav_region.navigation_mesh = nm
	_nav_verify_tries = 0
	_nav_verify_at_ms = Time.get_ticks_msec() + 350
	set_process(true)
	stats["nav_polygons"] = nm.get_polygon_count()
	stats["nav_source"] = source
	print("[World] navmesh ready (%s): %d polygons, %d vertices, %s ms" % [source, nm.get_polygon_count(),
			nm.get_vertices().size(), str(stats.get("nav_ms", 0))])
	_nav_ready = true
	nav_ready.emit()


func _build_tram_loop() -> PackedVector2Array:
	var raw := WorldLayout.pts2(WorldLayout.TRAM_LOOP)
	if raw.size() < 3:
		return PackedVector2Array()
	# start in the middle of the first edge so the seam of the closed loop lies on a straight
	var start := (raw[0] + raw[1]) * 0.5
	var ring := PackedVector2Array([start])
	for i in range(1, raw.size()):
		ring.append(raw[i])
	ring.append(raw[0])
	ring.append(start)
	var radii := PackedFloat32Array()
	radii.resize(ring.size())
	radii.fill(WorldLayout.TRAM_RADIUS)
	var unused: Array = []
	return Geom.resample(Geom.round_some(ring, radii, unused), 8.0)


func _cell_key(x: float, z: float) -> int:
	return (int(floor(x / 16.0)) + 4096) * 8192 + (int(floor(z / 16.0)) + 4096)


static func _ground_code(ground: String) -> int:
	match ground:
		"grass":
			return S_GRASS
		"planks":
			return S_WOOD
		"tarmac":
			return S_ASPHALT
	return S_CONCRETE


func _build_ground_index() -> void:
	var slab_of := {}
	for i in _slabs.size():
		var sl: Dictionary = _slabs[i]
		slab_of[String(sl["id"])] = i
		_slab_lots.append([])
		var cx0 := int(floor(float(sl["x0"]) / 16.0))
		var cx1 := int(floor(float(sl["x1"]) / 16.0))
		var cz0 := int(floor(float(sl["z0"]) / 16.0))
		var cz1 := int(floor(float(sl["z1"]) / 16.0))
		for cz in range(cz0, cz1 + 1):
			for cx in range(cx0, cx1 + 1):
				var k := (cx + 4096) * 8192 + (cz + 4096)
				var lst: PackedInt32Array = _slab_cells.get(k, _empty)
				if lst.is_empty():
					lst = PackedInt32Array()
				lst.append(i)
				_slab_cells[k] = lst
	for lot in _lots:
		var block := String(lot["block"])
		if block == "" or String(lot["row"]) == "R" or not slab_of.has(block):
			continue
		var si: int = slab_of[block]
		var code := _ground_code(String(lot["ground"]))
		if code == _ground_code(String(_slabs[si]["ground"])):
			continue
		var c: Vector3 = lot["center"]
		var size: Vector2 = lot["size"]
		var sideways := absf(sin(float(lot["yaw"]))) > 0.5
		var hx := (size.y if sideways else size.x) * 0.5
		var hz := (size.x if sideways else size.y) * 0.5
		(_slab_lots[si] as Array).append([c.x - hx, c.z - hz, c.x + hx, c.z + hz, code, c.y + 0.012])
	var qx: float = WorldLayout.QUAY_X
	var qz: float = WorldLayout.QUAY_Z
	var dx: float = qx + WorldLayout.QUAY_DECK_W
	var dz: float = qz - WorldLayout.QUAY_DECK_S
	var ap: Rect2 = WorldLayout.APRON
	var dw: Rect2 = WorldLayout.APRON_DRIVEWAY
	_decks = [
		[qx, WorldLayout.QUAY_NORTH, dx, qz, _yd, S_CONCRETE], [dx, dz, WorldLayout.QUAY_EAST, qz, _yd, S_CONCRETE],
		[dx, 232.5, -254.5, dz, _yd, S_CONCRETE], [-34.5, 232.5, WorldLayout.QUAY_EAST, dz, _yd, S_CONCRETE],
		[ap.position.x, ap.position.y, ap.end.x, ap.end.y, _yd, S_CONCRETE],
		[dw.position.x, dw.position.y, dw.end.x, dw.end.y, _yd, S_ASPHALT],
	]
	var off_sw: float = WorldLayout.SIDEWALK_W
	for b in roads.bends:
		var s: float = b["side"]
		if not bool(b["sw_l"] if s > 0.0 else b["sw_r"]):
			continue
		var off: float = float(b["hw"]) + off_sw
		var v: Vector2 = b["v"]
		var m: Vector2 = v - Geom.right_of(b["d0"]) * (s * off) - Geom.right_of(b["d1"]) * (s * off)
		var centre: Vector2 = b["centre"]
		_wedges.append([minf(m.x, centre.x), minf(m.y, centre.y), maxf(m.x, centre.x), maxf(m.y, centre.y), centre, float(b["r"]) + off])


# ---------------------------------------------------------------------------------------------
# ground queries
# ---------------------------------------------------------------------------------------------

## The quay decks cover the first terrain cells that already slope down to the harbour bed.
func _in_quay_box(x: float, z: float) -> bool:
	return x >= WorldLayout.QUAY_X and x <= WorldLayout.QUAY_EAST and z >= WorldLayout.QUAY_NORTH and z <= WorldLayout.QUAY_Z


func _pier_height(x: float, z: float) -> float:
	if z < WorldLayout.QUAY_Z or z > WorldLayout.PIER_END_Z:
		return -1000.0
	for px: float in WorldLayout.PIER_X:
		if absf(x - px) <= WorldLayout.PIER_HALF_W:
			if z >= WorldLayout.PIER_RAMP_Z:
				return WorldLayout.PIER_DECK_Y
			return lerpf(_yd, WorldLayout.PIER_DECK_Y, (z - WorldLayout.QUAY_Z) / (WorldLayout.PIER_RAMP_Z - WorldLayout.QUAY_Z))
	return -1000.0


## Paved surface at x,z (roads, kerbs, sidewalks, slabs, decks). Returns an S_* code and sets _p_y.
func _paved(x: float, z: float) -> int:
	var q := Vector2(x, z)
	var grid := roads.seg_grid
	var on_road := false
	var on_kerb := false
	var kerb_y := 0.0
	var on_walk := false
	var sw_w: float = WorldLayout.SIDEWALK_W
	var run: float = WorldLayout.CURB_RUN
	for e in grid.candidates(q):
		var a := grid.ea[e]
		var ab := grid.eb[e] - a
		var l2 := ab.length_squared()
		var tr := (q - a).dot(ab) / l2
		var t := clampf(tr, 0.0, 1.0)
		var d := (a + ab * t).distance_to(q)
		var seg: Dictionary = roads.segments[grid.eid[e]]
		var hw: float = seg["hw"]
		if d >= hw + sw_w:
			continue
		if String(seg["kind"]) == "dirt":
			continue
		var right := (ab.x * (q.y - a.y) - ab.y * (q.x - a.x)) > 0.0
		var span: Array = seg["sw_r_span"] if right else seg["sw_l_span"]
		if d < hw:
			if d > hw - run and not span.is_empty():
				var s := grid.eoff[e] + t * sqrt(l2)
				if s >= float(span[0]) and s <= float(span[1]):
					on_kerb = true
					kerb_y = lerpf(_yr, _ys, (d - (hw - run)) / run)
					continue
			on_road = true
			break
		if span.is_empty():
			continue
		var fl := grid.eflag[e]
		if (tr < 0.0 and (fl & 1) != 0) or (tr > 1.0 and (fl & 2) != 0):
			continue
		on_walk = true
	if on_road:
		_p_y = _yr
		return S_ASPHALT
	if on_kerb:
		_p_y = kerb_y
		return S_CONCRETE
	if on_walk:
		_p_y = _ys
		return S_CONCRETE
	for si in (_slab_cells.get(_cell_key(x, z), _empty) as PackedInt32Array):
		var sl: Dictionary = _slabs[si]
		if Geom.in_rounded_rect(q, sl["x0"], sl["z0"], sl["x1"], sl["z1"], sl["radii"]):
			for lr: Array in _slab_lots[si]:
				if x >= float(lr[0]) and x <= float(lr[2]) and z >= float(lr[1]) and z <= float(lr[3]):
					_p_y = lr[5]
					return lr[4]
			_p_y = sl["y"]
			return _ground_code(String(sl["ground"]))
	for dk: Array in _decks:
		if x >= float(dk[0]) and x <= float(dk[2]) and z >= float(dk[1]) and z <= float(dk[3]):
			_p_y = dk[4]
			return dk[5]
	for w: Array in _wedges:
		if x >= float(w[0]) and x <= float(w[2]) and z >= float(w[1]) and z <= float(w[3]) \
				and q.distance_to(w[4]) >= float(w[5]):
			_p_y = _ys
			return S_CONCRETE
	if q.distance_squared_to(WorldLayout.AIRPORT_HELIPAD) <= WorldLayout.HELIPAD_RADIUS * WorldLayout.HELIPAD_RADIUS:
		_p_y = _yd
		return S_CONCRETE
	return S_NONE


## Height of the surface you stand on at x,z: terrain, road, kerb, sidewalk / slab, quay deck or pier.
## Below 0 under the sea (seabed). Buildings and props are not included.
func get_height(x: float, z: float) -> float:
	if terrain == null:
		return Terrain.height(x, z)
	var h := terrain.get_mesh_height(x, z)
	if h < 1.0 and not _in_quay_box(x, z):
		return maxf(h, _pier_height(x, z))
	if roads != null and absf(x) < 300.0 and absf(z) < 300.0 and _paved(x, z) != S_NONE:
		return _p_y
	return h


## Raw terrain height (seabed under piers, plateau under slabs).
func get_terrain_height(x: float, z: float) -> float:
	if terrain == null:
		return Terrain.height(x, z)
	return terrain.get_mesh_height(x, z)


## WATER_LEVEL - seabed height: > 0 over water, <= 0 on land.
func get_water_depth(x: float, z: float) -> float:
	return Game.WATER_LEVEL - _seabed_height(x, z)


## Terrain height for water tests: the cells hidden under the quay decks count as land.
func _seabed_height(x: float, z: float) -> float:
	if _in_quay_box(x, z):
		return _y0
	return get_terrain_height(x, z)


## True if the point is inside the sea volume (below the surface, over the seabed).
func is_water_at(pos: Vector3) -> bool:
	return pos.y < Game.WATER_LEVEL + 0.05 and _seabed_height(pos.x, pos.z) < Game.WATER_LEVEL - 0.05


## One of Fx.SURFACES: "asphalt", "concrete", "grass", "sand", "dirt", "wood", "water".
func get_surface_at(pos: Vector3) -> String:
	if terrain == null:
		return "grass"
	var h := terrain.get_mesh_height(pos.x, pos.z)
	if h < 1.0 and not _in_quay_box(pos.x, pos.z):
		if _pier_height(pos.x, pos.z) > -100.0 and pos.y > 0.5:
			return "wood"
		if h < Game.WATER_LEVEL - 0.05:
			return "water"
		return "sand"
	if roads != null and absf(pos.x) < 300.0 and absf(pos.z) < 300.0:
		var code := _paved(pos.x, pos.z)
		if code != S_NONE:
			return SURFACE_NAMES[code]
	match terrain.get_kind(pos.x, pos.z) & 3:
		1:
			return "sand"
		2:
			return "dirt"
	return "grass"


## District id of a position ("ocean" off-shore).
func get_district(pos: Vector3) -> String:
	if _seabed_height(pos.x, pos.z) < -0.2:
		if pos.x > WorldLayout.QUAY_X - 4.0 and pos.x < WorldLayout.QUAY_EAST and pos.z > WorldLayout.QUAY_Z - 1.0 \
				and pos.z < WorldLayout.PIER_END_Z + 6.0:
			return "waterfront"
		return "ocean"
	return WorldLayout.district_at(pos.x, pos.z)


# ---------------------------------------------------------------------------------------------
# locations, lots, spawn points
# ---------------------------------------------------------------------------------------------

func get_location(location_name: String) -> Transform3D:
	if _locations.has(location_name):
		return _locations[location_name]
	if not _warned.has(location_name):
		_warned[location_name] = true
		push_warning("[World] unknown location '%s'" % location_name)
	return Transform3D(Basis.IDENTITY, Vector3(0.0, _ys, 0.0))


func has_location(location_name: String) -> bool:
	return _locations.has(location_name)


func get_locations() -> Dictionary:
	return _locations


## Lets the city builder / other systems refine or add a named location (e.g. the real roof helipad).
func set_location(location_name: String, xform: Transform3D) -> void:
	_locations[location_name] = xform
	_minimap = {}


func get_lots() -> Array[Dictionary]:
	return _lots


## The lot reserved for a landmark ("police_station", "tram_stop_2", ...). {} if unknown.
func get_landmark_lot(landmark: String) -> Dictionary:
	for lot in _lots:
		if String(lot["landmark"]) == landmark:
			return lot
	return {}


func get_spawn_points(kind: String) -> Array[Transform3D]:
	if _spawns.has(kind):
		return _spawns[kind]
	var none: Array[Transform3D] = []
	return none


func get_spawn_kinds() -> Array:
	return _spawns.keys()


func add_spawn_point(kind: String, xform: Transform3D) -> void:
	if not _spawns.has(kind):
		var arr: Array[Transform3D] = []
		_spawns[kind] = arr
	var lst: Array[Transform3D] = _spawns[kind]
	lst.append(xform)


## One entry per signalised approach: {transform, lane_ids, intersection_id}; same order as the
## "traffic_light" spawn points.
func get_signal_heads() -> Array[Dictionary]:
	return _signal_heads


func get_transit_path() -> PackedVector3Array:
	return _transit_path


func get_transit_stops() -> Array[Dictionary]:
	return _transit_stops


func is_nav_ready() -> bool:
	return _nav_ready


## Rebuilds the navigation mesh with explicit obstacle rectangles ([x0, z0, x1, z1] each, e.g. the real
## building footprints) instead of carving out whole building lots. Emits nav_ready when done.
func rebuild_navigation(obstacles: Array, carve_lots: bool = false) -> void:
	_start_navigation(obstacles, carve_lots)


# ---------------------------------------------------------------------------------------------
# minimap
# ---------------------------------------------------------------------------------------------

func _coast_polygon() -> PackedVector2Array:
	var entries: Array = []
	var steps := 300
	for i in steps:
		var ang := TAU * float(i) / float(steps)
		var dir := Vector2(cos(ang), sin(ang))
		var r0 := 190.0
		var r1 := r0
		while r1 < 470.0 and Terrain.coast_sd(dir.x * r1, dir.y * r1) > 0.0:
			r0 = r1
			r1 += 9.0
		for it in 9:
			var rm := (r0 + r1) * 0.5
			if Terrain.coast_sd(dir.x * rm, dir.y * rm) > 0.0:
				r0 = rm
			else:
				r1 = rm
		entries.append([ang, dir * r0])
	for corner: Vector2 in [Vector2(WorldLayout.QUAY_X, WorldLayout.QUAY_Z)]:
		entries.append([fposmod(atan2(corner.y, corner.x), TAU), corner])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out := PackedVector2Array()
	for e: Array in entries:
		out.append(e[1])
	return out


## {"roads": [{points: PackedVector2Array, width, kind, name}], "coast": PackedVector2Array,
##  "lots": [{center: Vector2, size: Vector2, yaw, zone, landmark, district}],
##  "labels": [{text, position: Vector2, kind: "district"|"location", id}], "water_rects": [],
##  extras: "piers": [Rect2], "decks": [Rect2], "transit": PackedVector2Array, "helipads": [Vector3(x, z, r)],
##  "bounds": Rect2}. Coordinates are map x / z.
func get_minimap_data() -> Dictionary:
	if not _minimap.is_empty():
		return _minimap
	var road_list: Array = []
	if roads != null:
		for s in roads.segments:
			road_list.append({"points": s["pts2"], "width": s["width"], "kind": s["kind"], "name": s["name"]})
	var lot_list: Array = []
	for lot in _lots:
		var c: Vector3 = lot["center"]
		lot_list.append({"center": Vector2(c.x, c.z), "size": lot["size"], "yaw": lot["yaw"], "zone": lot["zone"],
				"landmark": lot["landmark"], "district": lot["district"]})
	var labels: Array = []
	for id: String in WorldLayout.DISTRICT_LABELS:
		var d: Array = WorldLayout.DISTRICT_LABELS[id]
		labels.append({"text": String(d[2]), "position": Vector2(float(d[0]), float(d[1])), "kind": "district", "id": id})
	for id: String in LOCATION_LABELS:
		if _locations.has(id):
			var o: Vector3 = (_locations[id] as Transform3D).origin
			labels.append({"text": String(LOCATION_LABELS[id]), "position": Vector2(o.x, o.z), "kind": "location", "id": id})
	var piers: Array = []
	for px: float in WorldLayout.PIER_X:
		piers.append(Rect2(px - WorldLayout.PIER_HALF_W, WorldLayout.QUAY_Z, WorldLayout.PIER_HALF_W * 2.0,
				WorldLayout.PIER_END_Z - WorldLayout.QUAY_Z))
	var decks: Array = []
	for dk: Array in _decks:
		decks.append(Rect2(float(dk[0]), float(dk[1]), float(dk[2]) - float(dk[0]), float(dk[3]) - float(dk[1])))
	_minimap = {
		"roads": road_list, "coast": _coast_polygon(), "lots": lot_list, "labels": labels, "water_rects": [],
		"piers": piers, "decks": decks, "transit": _tram2d,
		"helipads": [Vector3(WorldLayout.AIRPORT_HELIPAD.x, WorldLayout.AIRPORT_HELIPAD.y, WorldLayout.HELIPAD_RADIUS),
				Vector3(WorldLayout.HARBOR_HELIPAD.x, WorldLayout.HARBOR_HELIPAD.y, WorldLayout.HARBOR_HELIPAD_RADIUS)],
		"bounds": Rect2(-WorldLayout.MAP_HALF, -WorldLayout.MAP_HALF, WorldLayout.MAP_HALF * 2.0, WorldLayout.MAP_HALF * 2.0),
	}
	return _minimap
