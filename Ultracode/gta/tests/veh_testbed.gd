extends RefCounted
## TEST-ONLY helpers shared by the veh_* tests: a code-built proving ground (flat pad, kerb
## platform, jump ramp), a light rig for screenshots and a programmatic stand-in model used to
## exercise the fallback paths of the vehicle builder. Nothing here is used by the game.

const GROUND_COLOR := Color(0.2, 0.22, 0.27)
const KERB_COLOR := Color(0.72, 0.7, 0.64)
const RAMP_COLOR := Color(0.85, 0.48, 0.2)

## Kerb platform (0.15 m high) spans z = KERB_Z0 .. KERB_Z1, ramp rises from RAMP_Z0 to RAMP_Z1.
const KERB_Z0 := 60.0
const KERB_Z1 := 66.0
const KERB_H := 0.15
const RAMP_Z0 := 160.0
const RAMP_Z1 := 170.0
const RAMP_H := 1.4


static func add_static_box(parent: Node, size: Vector3, xform: Transform3D, color: Color, surface: String = "asphalt") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material = mat
	mi.mesh = mesh
	body.add_child(mi)
	body.transform = xform
	parent.add_child(body)
	return body


## Flat pad (top at y = 0), a 0.15 m kerb platform and a jump ramp, all spanning every lane.
static func build_proving_ground(parent: Node, half_width: float = 140.0, z_min: float = -1500.0, z_max: float = 420.0) -> Node3D:
	var root := Node3D.new()
	root.name = "VehProvingGround"
	parent.add_child(root)
	var len_z := z_max - z_min
	add_static_box(root, Vector3(half_width * 2.0, 2.0, len_z), Transform3D(Basis.IDENTITY, Vector3(0.0, -1.0, (z_min + z_max) * 0.5)), GROUND_COLOR)
	add_static_box(root, Vector3(half_width * 2.0, KERB_H, KERB_Z1 - KERB_Z0),
			Transform3D(Basis.IDENTITY, Vector3(0.0, KERB_H * 0.5, (KERB_Z0 + KERB_Z1) * 0.5)), KERB_COLOR, "concrete")
	var run := RAMP_Z1 - RAMP_Z0
	var ang := atan(RAMP_H / run)
	var slope_len := sqrt(run * run + RAMP_H * RAMP_H)
	var thick := 0.4
	var basis := Basis(Vector3.RIGHT, -ang)
	var mid := Vector3(0.0, RAMP_H * 0.5, (RAMP_Z0 + RAMP_Z1) * 0.5)
	add_static_box(root, Vector3(half_width * 2.0, thick, slope_len), Transform3D(basis, mid - basis.y * (thick * 0.5)), RAMP_COLOR, "wood")
	return root


static func add_light_rig(parent: Node, night: bool = false) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "TestSun"
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 0.04 if night else 1.25
	sun.light_color = Color(0.6, 0.7, 1.0) if night else Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = not night
	sun.directional_shadow_max_distance = 80.0
	parent.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	if night:
		sm.sky_top_color = Color(0.01, 0.015, 0.04)
		sm.sky_horizon_color = Color(0.03, 0.04, 0.08)
		sm.ground_horizon_color = Color(0.03, 0.04, 0.08)
		sm.ground_bottom_color = Color(0.01, 0.01, 0.02)
	else:
		sm.sky_top_color = Color(0.25, 0.5, 0.85)
		sm.sky_horizon_color = Color(0.72, 0.82, 0.9)
		sm.ground_horizon_color = Color(0.72, 0.82, 0.9)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.25 if night else 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.name = "TestEnvironment"
	we.environment = env
	parent.add_child(we)


## Switch an existing light rig between day and night IN PLACE (no nodes are freed, so the
## renderer never sees a frame without an environment).
static func set_rig_night(parent: Node, night: bool) -> void:
	var sun := parent.get_node_or_null("TestSun") as DirectionalLight3D
	if sun != null:
		sun.light_energy = 0.04 if night else 1.25
		sun.light_color = Color(0.6, 0.7, 1.0) if night else Color(1.0, 0.95, 0.86)
		sun.shadow_enabled = not night
	var we := parent.get_node_or_null("TestEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	env.ambient_light_energy = 0.25 if night else 0.9
	var sm: ProceduralSkyMaterial = null
	if env.sky != null:
		sm = env.sky.sky_material as ProceduralSkyMaterial
	if sm == null:
		return
	if night:
		sm.sky_top_color = Color(0.01, 0.015, 0.04)
		sm.sky_horizon_color = Color(0.03, 0.04, 0.08)
		sm.ground_horizon_color = Color(0.03, 0.04, 0.08)
		sm.ground_bottom_color = Color(0.01, 0.01, 0.02)
	else:
		sm.sky_top_color = Color(0.25, 0.5, 0.85)
		sm.sky_horizon_color = Color(0.72, 0.82, 0.9)
		sm.ground_horizon_color = Color(0.72, 0.82, 0.9)
		sm.ground_bottom_color = Color(0.2, 0.17, 0.13)


static func make_camera(parent: Node) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = "VehTestCamera"
	cam.fov = 55.0
	cam.far = 2000.0
	parent.add_child(cam)
	cam.current = true
	return cam


## Signed heading of a vehicle in radians: 0 = facing -Z, positive = turned to the right (+X).
static func heading(v: Node3D) -> float:
	var f := -v.global_transform.basis.z
	return atan2(f.x, -f.z)


static func ids_with_models() -> Array[String]:
	var out: Array[String] = []
	var mgr := Game.get_system("vehicles")
	for id: Variant in Registry.ids("vehicles"):
		if mgr != null and mgr.can_spawn(str(id)):
			out.append(str(id))
	return out


## TEST ONLY: rough outer dimensions per spec for the programmatic stand-in rigs used while a
## spec's GLB has not been exported yet: [length, width, height, wheelbase, track, wheel radius].
const RIG_DIMS := {
	"compact": [3.7, 1.68, 1.45, 2.40, 1.45, 0.31],
	"sedan": [4.6, 1.80, 1.45, 2.75, 1.52, 0.34],
	"taxi": [4.6, 1.80, 1.45, 2.75, 1.52, 0.34],
	"sports": [4.4, 1.90, 1.20, 2.60, 1.62, 0.34],
	"muscle": [4.8, 1.90, 1.35, 2.80, 1.60, 0.35],
	"suv": [4.8, 1.95, 1.78, 2.85, 1.65, 0.38],
	"pickup": [5.3, 1.95, 1.80, 3.30, 1.65, 0.38],
	"van": [5.2, 2.00, 2.30, 3.20, 1.70, 0.36],
	"police_cruiser": [4.9, 1.85, 1.50, 2.90, 1.58, 0.34],
	"ambulance": [6.0, 2.20, 2.70, 3.60, 1.80, 0.40],
	"swat_van": [6.2, 2.30, 2.70, 3.70, 1.90, 0.45],
	"box_truck": [7.0, 2.40, 3.20, 4.20, 1.95, 0.45],
	"firetruck": [8.0, 2.50, 3.10, 4.60, 2.05, 0.50],
}


## Programmatic stand-in WITHOUT collision helpers, seats or markers (builder fallback test).
static func make_bare_model() -> Node3D:
	return make_rig_model("")


## Programmatic stand-in sized like `spec_id` (see RIG_DIMS; unknown ids get a generic saloon).
## Only a Body box and four Wheel_* cylinders: no Col_* helpers, seats, doors or markers.
static func make_rig_model(spec_id: String) -> Node3D:
	var d: Array = RIG_DIMS.get(spec_id, [4.2, 1.8, 1.25, 2.6, 1.6, 0.33])
	var length := float(d[0])
	var width := float(d[1])
	var height := float(d[2])
	var half_wb := float(d[3]) * 0.5
	var half_track := float(d[4]) * 0.5
	var wheel_r := float(d[5])
	var clearance := 0.25
	var root := Node3D.new()
	root.name = "BareRig"
	var asset := Node3D.new()
	asset.name = "bare_rig"
	root.add_child(asset)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(width, height - clearance, length)
	var paint := StandardMaterial3D.new()
	paint.resource_name = "M_Paint_Primary"
	paint.albedo_color = Color(0.5, 0.5, 0.5)
	bm.material = paint
	body.mesh = bm
	body.position = Vector3(0.0, (height + clearance) * 0.5, 0.0)
	asset.add_child(body)
	var tire := StandardMaterial3D.new()
	tire.resource_name = "M_Tire"
	tire.albedo_color = Color(0.05, 0.05, 0.05)
	for spec: Array in [["Wheel_FL", -half_track, -half_wb], ["Wheel_FR", half_track, -half_wb], ["Wheel_RL", -half_track, half_wb], ["Wheel_RR", half_track, half_wb]]:
		var w := MeshInstance3D.new()
		w.name = spec[0]
		var cyl := CylinderMesh.new()
		cyl.top_radius = wheel_r
		cyl.bottom_radius = wheel_r
		cyl.height = 0.22
		cyl.material = tire
		w.mesh = cyl
		# CylinderMesh is along Y: bake a 90 degree roll into the node so the wheel keeps the
		# contract (origin at the centre, axle along the body's X axis)
		w.position = Vector3(float(spec[1]), wheel_r, float(spec[2]))
		w.rotation = Vector3(0.0, 0.0, PI * 0.5)
		asset.add_child(w)
	return root
