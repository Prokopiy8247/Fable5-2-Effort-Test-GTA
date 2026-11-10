class_name World
extends Node3D
## Root of the generated open world. Builds everything from CityLayout at boot:
## terrain, sea, roads, raised blocks, buildings, props, lights, navigation.

var layout: CityLayout
var env: WorldEnv
var graph: RoadGraph
var ground_body: StaticBody3D
var mat_road: ShaderMaterial
var mat_ground: ShaderMaterial
var mat_water: ShaderMaterial
var water_time := 0.0
var wave_amp := 0.28
var city: CityBuilder
var nav_region: NavigationRegion3D
var nav_ready := false
var nav_map: RID
var build_ms := {}
var _nav_mesh: NavigationMesh
var _nav_src: NavigationMeshSourceGeometryData3D
var _nav_t0 := 0

var _terrain_root: Node3D
var _roads_root: Node3D
var _ground_root: Node3D

func _ready() -> void:
	name = "World"

func build() -> void:
	var t0 := Time.get_ticks_msec()
	layout = CityLayout.new()
	Terrain.build_grid()
	build_ms["layout+grid"] = Time.get_ticks_msec() - t0
	mat_road = ShaderMaterial.new()
	mat_road.shader = load("res://gta/shaders/road.gdshader")
	mat_road.set_shader_parameter("noise_tex", Assets.noise_tex)
	mat_road.set_shader_parameter("detail_tex", Assets.detail_noise)
	mat_ground = ShaderMaterial.new()
	mat_ground.shader = load("res://gta/shaders/ground.gdshader")
	mat_ground.set_shader_parameter("noise_tex", Assets.noise_tex)
	mat_ground.set_shader_parameter("detail_tex", Assets.detail_noise)
	Assets.register_material("Ground", mat_ground)
	Assets.register_material("Road", mat_road)

	env = WorldEnv.new()
	env.name = "Environment"
	add_child(env)
	Game.time = env
	Game.weather = env

	var t1 := Time.get_ticks_msec()
	_terrain_root = _group("Terrain")
	Terrain.build(_terrain_root, mat_ground)
	build_ms["terrain"] = Time.get_ticks_msec() - t1

	t1 = Time.get_ticks_msec()
	_roads_root = _group("Roads")
	RoadBuilder.build(layout, _roads_root, mat_road)
	_ground_root = _group("Ground")
	ground_body = GroundBuilder.build(layout, _ground_root, mat_ground)
	build_ms["roads+ground"] = Time.get_ticks_msec() - t1

	_build_water()
	_build_bounds()

	t1 = Time.get_ticks_msec()
	graph = RoadGraph.new()
	graph.build(layout)
	build_ms["road_graph"] = Time.get_ticks_msec() - t1

	t1 = Time.get_ticks_msec()
	city = CityBuilder.new()
	city.name = "City"
	add_child(city)
	city.build(self)
	build_ms["city"] = Time.get_ticks_msec() - t1
	build_ms["total"] = Time.get_ticks_msec() - t0
	print("[World] built in ", build_ms)
	bake_navigation.call_deferred()

# ---------------------------------------------------------------- navigation
## Bakes one navigation mesh for the whole map from the static world colliders. Parsing runs
## here, the bake itself on a worker thread; until it lands AI steers directly (see NPC._path_to).
func bake_navigation() -> void:
	if _nav_mesh != null:
		return
	_nav_t0 = Time.get_ticks_msec()
	nav_map = get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(nav_map, 0.4)
	NavigationServer3D.map_set_cell_height(nav_map, 0.25)
	_nav_mesh = NavigationMesh.new()
	_nav_mesh.cell_size = 0.4
	_nav_mesh.cell_height = 0.25
	_nav_mesh.agent_radius = 0.4
	_nav_mesh.agent_height = 1.75
	_nav_mesh.agent_max_climb = 0.25
	_nav_mesh.agent_max_slope = 40.0
	_nav_mesh.region_min_size = 16.0
	_nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_nav_mesh.geometry_collision_mask = Phys.WORLD
	# nothing below ankle-deep water, nothing above the tallest roof
	_nav_mesh.filter_baking_aabb = AABB(Vector3(-306.0, -0.75, -306.0), Vector3(612.0, 60.0, 612.0))
	_nav_src = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_nav_mesh, _nav_src, self)
	build_ms["nav_parse"] = Time.get_ticks_msec() - _nav_t0
	NavigationServer3D.bake_from_source_geometry_data_async(_nav_mesh, _nav_src, _on_nav_baked)

func _on_nav_baked() -> void:
	_apply_nav.call_deferred()

func _apply_nav() -> void:
	if not is_inside_tree():
		return
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	nav_region.navigation_mesh = _nav_mesh
	add_child(nav_region)
	_nav_src = null
	nav_ready = true
	build_ms["nav_bake"] = Time.get_ticks_msec() - _nav_t0
	print("[World] navigation mesh ready: ", _nav_mesh.get_polygon_count(), " polygons, parse ", build_ms["nav_parse"], " ms, total ", build_ms["nav_bake"], " ms")

func _group(group_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = group_name
	add_child(n)
	return n

# ---------------------------------------------------------------- water
func _build_water() -> void:
	mat_water = ShaderMaterial.new()
	mat_water.shader = load("res://gta/shaders/water.gdshader")
	mat_water.set_shader_parameter("noise_tex", Assets.noise_tex)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1500, 1500)
	plane.subdivide_width = 249
	plane.subdivide_depth = 249
	plane.material = mat_water
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = plane
	mi.position = Vector3(150.0, Terrain.SEA, 200.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	add_child(mi)
	# flat far ocean ring out to the horizon
	var far := MeshInstance3D.new()
	far.name = "SeaFar"
	var st := GeoBuf.new()
	var inner := Rect2(150.0 - 750.0, 200.0 - 750.0, 1500.0, 1500.0)
	var o := 6000.0
	var y := Terrain.SEA - 0.02
	var col := Color(0, 0, 0)
	st.rect_up(-o, -o, o, inner.position.y, y, col)
	st.rect_up(-o, inner.end.y, o, o, y, col)
	st.rect_up(-o, inner.position.y, inner.position.x, inner.end.y, y, col)
	st.rect_up(inner.end.x, inner.position.y, o, inner.end.y, y, col)
	far.mesh = st.commit(mat_water)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)

func _process(delta: float) -> void:
	water_time += delta
	wave_amp = lerpf(wave_amp, float(env._wp.get("waves", 0.28)) if env else 0.28, clampf(delta * 0.2, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set(&"water_time", water_time)
	RenderingServer.global_shader_parameter_set(&"wave_amp", wave_amp)

static func _wave(x: float, z: float, t: float) -> float:
	return sin(x * 0.105 + z * 0.062 + t * 0.95) * 0.5 + sin(z * 0.171 - x * 0.043 + t * 1.25) * 0.3 + sin((x + z) * 0.31 + t * 1.9) * 0.12

func wave_height(x: float, z: float) -> float:
	return Terrain.SEA + _wave(x, z, water_time) * wave_amp

func height_at(x: float, z: float) -> float:
	return Terrain.sample(x, z)

func is_water_at(x: float, z: float) -> bool:
	return Terrain.is_water(x, z)

func district_at(pos: Vector3) -> String:
	return layout.district_at(pos.x, pos.z)

# ---------------------------------------------------------------- invisible limits
func _build_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "Bounds"
	body.collision_layer = Phys.BOUNDS
	body.collision_mask = 0
	add_child(body)
	# land limits (north / west), far sea limits (south / east)
	var walls := [
		[Vector3(-312.0, 30.0, 0.0), Vector3(4.0, 160.0, 1400.0)],
		[Vector3(0.0, 30.0, -312.0), Vector3(1400.0, 160.0, 4.0)],
	]
	for w in walls:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = w[1]
		cs.shape = bs
		cs.position = w[0]
		body.add_child(cs)
