extends Node3D
## Test scaffold shared by the plr_* tests (NOT game content): a flat concrete slab far above the
## island with a kerb, a ramp, a camera wall, an aim target and a neutral photo backdrop.
## It makes the player tests independent of the world module (which may be missing or mid-edit).
##
##     var arena: Node3D = load("res://gta/tests/plr_arena.gd").new()
##     Game.main.add_child(arena)            # builds itself in _ready
##     arena.at(Vector3(0, 0, 0))            # arena-local -> world position
##
## When no world system exists it can also register a minimal stand-in world (an endless sea at
## Game.WATER_LEVEL, no ground) so that swimming can be tested: ensure_water().

const ORIGIN := Vector3(0.0, 400.0, 0.0)

# arena-local landmarks (y = 0 is the floor)
const STAGE := Vector3(0.0, 0.0, 0.0)
const KERB_START := Vector3(-20.0, 0.0, 0.0)        ## run towards -Z: a 0.2 m kerb begins at z = -4
const KERB_HEIGHT := 0.2
const RAMP_ANGLE_DEG := 15.0
const RAMP_BASE := Vector3(-40.0, 0.0, -2.0)        ## foot of the ramp; it climbs towards -Z
const WALL_SPOT := Vector3(20.0, 0.0, 0.0)          ## a wall stands 1.35 m behind (+Z) this spot
const WALL_FACE_Z := 1.35
const TARGET_SPOT := Vector3(40.0, 0.0, 0.0)        ## an aim target stands 10 m in front (-Z)
const TARGET_FACE_Z := -9.75

var stub_world: Node3D = null
var _made_light: bool = false


class StubWorld extends Node3D:
	## Endless sea under the arena, nothing else. Only what the player module asks a world for.
	var arena_origin: Vector3 = Vector3.ZERO

	func get_height(_x: float, _z: float) -> float:
		return -30.0

	func get_water_depth(_x: float, _z: float) -> float:
		return 30.0

	func is_water_at(pos: Vector3) -> bool:
		return pos.y < Game.WATER_LEVEL

	func get_surface_at(_pos: Vector3) -> String:
		return "concrete"

	func get_district(_pos: Vector3) -> String:
		return "ocean"

	func get_location(_name: String) -> Transform3D:
		return Transform3D(Basis.IDENTITY, arena_origin + Vector3(6.0, 0.05, 6.0))

	func get_locations() -> Dictionary:
		return {}


class MockVehicle extends RigidBody3D:
	## Smallest thing that satisfies the vehicle side of the enter / exit contract
	## (ARCHITECTURE 5 "Vehicle entry" + 6.5). Records what the player called.
	var vehicle_class: String = "car"
	var spec_id: String = "mock"
	var display_name: String = ""
	var destroyed: bool = false
	var driver: Node = null
	var is_player_driven: bool = false
	var calls: Array = []
	var seat: Node3D = null
	var camera_params: Dictionary = {"distance": 6.0, "height": 2.0, "fov": 72.0, "look_height": 1.0}

	func _init() -> void:
		add_to_group("vehicle")
		collision_layer = Layers.VEHICLE
		collision_mask = Layers.WORLD
		mass = 1200.0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.8, 1.2, 4.2)
		cs.shape = shape
		cs.position = Vector3(0.0, 0.62, 0.0)
		add_child(cs)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = shape.size
		mi.mesh = mesh
		mi.position = cs.position
		add_child(mi)
		seat = Node3D.new()
		seat.name = "Seat_Driver"
		seat.position = Vector3(-0.4, 0.45, 0.2)
		add_child(seat)

	func can_enter(_who: Node) -> bool:
		return not destroyed

	func get_free_seat() -> int:
		return 0 if driver == null else -1

	func occupant_enter(who: Node, seat_index: int = 0) -> void:
		calls.append(["enter", who, seat_index])
		driver = who
		is_player_driven = who.is_in_group("player")

	func occupant_exit(seat_index: int = 0) -> Transform3D:
		calls.append(["exit", seat_index])
		driver = null
		is_player_driven = false
		return get_exit_transform(seat_index)

	func get_seat_node(_seat_index: int = 0) -> Node3D:
		return seat

	func get_exit_transform(_seat_index: int = 0) -> Transform3D:
		return global_transform * Transform3D(Basis.IDENTITY, Vector3(-1.75, 0.0, 0.2))

	func get_occupants() -> Array:
		return [driver] if driver != null else []

	func get_camera_params() -> Dictionary:
		return camera_params

	func get_forward_speed() -> float:
		return linear_velocity.dot(-global_basis.z)

	func count(what: String) -> int:
		var n := 0
		for c: Array in calls:
			if c[0] == what:
				n += 1
		return n


class MockInventory extends Node:
	## Records the intent the player forwards to a WeaponInventory.
	var current_id: String = "pistol"
	var calls: Array = []
	var holder: Node = null
	var aim_fov: float = 40.0
	var vehicle_ok: bool = false

	func setup(p_holder: Node = null) -> void:
		holder = p_holder

	func is_armed() -> bool:
		return current_id != "" and current_id != "fists"

	func get_weapon_pose() -> String:
		return "pistol" if is_armed() else "none"

	func get_aim_fov() -> float:
		return aim_fov

	func can_use_in_vehicle(_id: String) -> bool:
		return vehicle_ok

	func trigger_pressed() -> void:
		calls.append("trigger_pressed")

	func trigger_released() -> void:
		calls.append("trigger_released")

	func reload() -> void:
		calls.append("reload")

	func set_aiming(on: bool) -> void:
		calls.append("aim_on" if on else "aim_off")

	func next_weapon() -> void:
		calls.append("next")

	func prev_weapon() -> void:
		calls.append("prev")

	func equip_slot(slot: int) -> void:
		calls.append("slot_%d" % slot)

	func throw_grenade() -> void:
		calls.append("throw")

	func melee_attack(heavy: bool = false) -> void:
		calls.append("melee_heavy" if heavy else "melee")

	func holster() -> void:
		calls.append("holster")

	func count(what: String) -> int:
		return calls.count(what)


func _ready() -> void:
	name = "PlrArena"
	global_position = ORIGIN
	_box("Floor", Vector3(0.0, -0.5, 0.0), Vector3(140.0, 1.0, 140.0), Color(0.62, 0.61, 0.58))
	_box("Kerb", KERB_START + Vector3(0.0, KERB_HEIGHT * 0.5, -8.0), Vector3(8.0, KERB_HEIGHT, 8.0), Color(0.72, 0.70, 0.66))
	# ramp: a slab rotated about X so that its top face climbs towards -Z
	var a := deg_to_rad(RAMP_ANGLE_DEG)
	var up_slope := Vector3(0.0, sin(a), -cos(a))
	var normal := Vector3(0.0, cos(a), sin(a))
	var ramp := _box("Ramp", RAMP_BASE + up_slope * 8.0 - normal * 0.25, Vector3(8.0, 0.5, 16.0), Color(0.70, 0.66, 0.58))
	ramp.rotation = Vector3(a, 0.0, 0.0)
	_box("CameraWall", WALL_SPOT + Vector3(0.0, 3.0, WALL_FACE_Z + 0.25), Vector3(10.0, 6.0, 0.5), Color(0.55, 0.47, 0.42))
	_box("AimTarget", TARGET_SPOT + Vector3(0.0, 1.5, TARGET_FACE_Z - 0.25), Vector3(3.0, 3.0, 0.5), Color(0.80, 0.42, 0.36))
	# neutral backdrop behind the stage (for the animation shots)
	_box("BackdropN", STAGE + Vector3(0.0, 2.5, -5.0), Vector3(22.0, 5.0, 0.3), Color(0.36, 0.44, 0.50))
	_box("BackdropW", STAGE + Vector3(-9.0, 2.5, 0.0), Vector3(0.3, 5.0, 12.0), Color(0.33, 0.41, 0.47))


## Arena-local point -> world.
func at(local: Vector3) -> Vector3:
	return ORIGIN + local


func ramp_point(distance_up: float) -> Vector3:
	var a := deg_to_rad(RAMP_ANGLE_DEG)
	return at(RAMP_BASE + Vector3(0.0, sin(a), -cos(a)) * distance_up)


## Makes sure the scene is lit for windowed shots (uses the environment system when present).
func ensure_light() -> void:
	if _made_light:
		return
	_made_light = true
	if Game.get_system("environment") != null:
		if WorldClock.has_method("set_hour"):
			WorldClock.call("set_hour", 13.0)
		if Weather.has_method("set_weather"):
			Weather.call("set_weather", "clear", 0.0)
		return
	var sun := DirectionalLight3D.new()
	sun.name = "TestSun"
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var we := WorldEnvironment.new()
	we.name = "TestEnvironment"
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)


## A deep-water point (world). Uses the real sea when a world exists, otherwise registers the
## stand-in world. Returns Vector3.INF when the real world has no deep water where expected.
func ensure_water() -> Vector3:
	if Game.world == null:
		stub_world = StubWorld.new()
		stub_world.name = "StubWorld"
		(stub_world as StubWorld).arena_origin = ORIGIN
		add_child(stub_world)
		Game.register_system("world", stub_world)
		return Vector3(0.0, Game.WATER_LEVEL - 1.0, 0.0)
	if not Game.world.has_method("get_water_depth") or not Game.world.has_method("is_water_at"):
		return Vector3.INF
	for ring in [330.0, 360.0, 400.0, 450.0]:
		for i in 16:
			var ang := TAU * float(i) / 16.0
			var x: float = cos(ang) * ring
			var z: float = sin(ang) * ring
			if float(Game.world.call("get_water_depth", x, z)) > 6.0:
				return Vector3(x, Game.WATER_LEVEL - 1.0, z)
	return Vector3.INF


func spawn_mock_vehicle(local: Vector3, yaw: float = 0.0, cls: String = "car") -> MockVehicle:
	var v := MockVehicle.new()
	v.name = "MockVehicle"
	v.vehicle_class = cls
	Game.get_entities_root().add_child(v)
	v.global_transform = Transform3D(Basis(Vector3.UP, yaw), at(local) + Vector3(0.0, 0.02, 0.0))
	return v


## Replaces the player's WeaponInventory with a recording stand-in (the real one is freed).
func install_mock_inventory(player: Node) -> MockInventory:
	var old: Variant = player.get("inventory")
	if old != null and is_instance_valid(old):
		(old as Node).name = "InventoryRemoved"
		(old as Node).queue_free()
	var inv := MockInventory.new()
	inv.name = "Inventory"
	player.add_child(inv)
	inv.setup(player)
	player.set("inventory", inv)
	return inv


func remove_stub_world() -> void:
	if stub_world != null and Game.world == stub_world:
		Game.systems.erase("world")
		Game.world = null


func _box(box_name: String, local_pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.set_meta("surface", "concrete")
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
	add_child(body)
	body.position = local_pos
	return body
