extends Node3D
## Test scaffold of the plr2_* tests (NOT game content): traversal obstacles on the plr_arena slab
## (400 m above the island). Every lane is approached towards -Z from its start spot; the obstacle
## front faces stand at z = FACE_Z (arena-local).
##
##     var arena := Arena.new(); Game.main.add_child(arena)
##     var stage := Stage.new(); arena.add_child(stage)      # builds itself
##
##   lane            start (arena-local)   obstacle
##   VAULT_LANE      (-30, 0, 34)          1.0 m wall, 0.25 m thick
##   MANTLE_LANE     (-20, 0, 34)          1.8 m ledge (block 6 m deep)
##   HIGH_LANE       (-10, 0, 34)          2.6 m wall (too high for anything)
##   LADDER_LANE     (  0, 0, 31)          5 m ladder up the front of a 5 m platform
##   AIR_LANE        ( 10, 0, 36)          1.8 m ledge for the running-jump grab
##   OPEN_SPOT       ( 30, 0, 40)          open floor (rolls, drops)

const FACE_Z := 30.0
const VAULT_LANE := Vector3(-30.0, 0.0, 34.0)
const VAULT_HEIGHT := 1.0
const MANTLE_LANE := Vector3(-20.0, 0.0, 34.0)
const MANTLE_HEIGHT := 1.8
const HIGH_LANE := Vector3(-10.0, 0.0, 34.0)
const HIGH_HEIGHT := 2.6
const LADDER_LANE := Vector3(0.0, 0.0, 31.0)
const LADDER_HEIGHT := 5.0
const AIR_LANE := Vector3(10.0, 0.0, 36.0)
const OPEN_SPOT := Vector3(30.0, 0.0, 40.0)

var ladder: Node3D = null


func _ready() -> void:
	name = "Plr2Stage"
	position = Vector3.ZERO
	var stone := Color(0.70, 0.66, 0.58)
	var brick := Color(0.66, 0.45, 0.38)
	_box("VaultWall", Vector3(VAULT_LANE.x, VAULT_HEIGHT * 0.5, FACE_Z - 0.125), Vector3(5.0, VAULT_HEIGHT, 0.25), brick)
	_box("MantleLedge", Vector3(MANTLE_LANE.x, MANTLE_HEIGHT * 0.5, FACE_Z - 3.0), Vector3(5.0, MANTLE_HEIGHT, 6.0), stone)
	_box("HighWall", Vector3(HIGH_LANE.x, HIGH_HEIGHT * 0.5, FACE_Z - 0.2), Vector3(5.0, HIGH_HEIGHT, 0.4), brick)
	_box("LadderPlatform", Vector3(LADDER_LANE.x, LADDER_HEIGHT * 0.5, FACE_Z - 2.5), Vector3(4.0, LADDER_HEIGHT, 5.0), stone)
	_box("AirLedge", Vector3(AIR_LANE.x, MANTLE_HEIGHT * 0.5, FACE_Z - 3.0), Vector3(5.0, MANTLE_HEIGHT, 6.0), stone)
	ladder = _ladder(Vector3(LADDER_LANE.x, 0.0, FACE_Z + 0.04), LADDER_HEIGHT)


## Ladder node per W2.4: origin at the foot, climber facing local -Z (into the wall), meta height.
func _ladder(local: Vector3, h: float) -> Node3D:
	var l := Node3D.new()
	l.name = "TestLadder"
	l.set_meta("height", h)
	add_child(l)
	l.position = local
	l.add_to_group("ladder")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.34, 0.36)
	mat.metallic = 0.4
	for side: float in [-0.24, 0.24]:
		_mesh(l, Vector3(side, h * 0.5, 0.06), Vector3(0.05, h, 0.05), mat)
	var y := 0.3
	while y < h:
		_mesh(l, Vector3(0.0, y, 0.06), Vector3(0.48, 0.035, 0.035), mat)
		y += 0.3
	return l


func _mesh(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	_mesh(body, Vector3.ZERO, size, mat)
	add_child(body)
	body.position = local_pos
	return body
