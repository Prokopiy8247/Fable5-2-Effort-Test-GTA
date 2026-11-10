extends Node3D
## Test scaffold of the plr3_* tests (NOT game content): cover geometry on the plr_arena slab
## (400 m above the island). Every lane is approached towards -Z; the cover faces stand at
## z = FACE_Z (arena-local) and face +Z.
##
##     var arena := Arena.new(); Game.main.add_child(arena)
##     var stage := Stage.new(); arena.add_child(stage)      # builds itself
##
##   lane          start (arena-local)   cover
##   LOW_LANE      ( 0, 0, -38.6)        1.1 m wall, 4 m wide (x -2..2), 0.3 m thick; target dummy + backstop behind
##   HIGH_LANE     ( 9.5, 0, -38.6)      2.5 m block, 3 m wide (x 8..11), 2 m deep: outside corners at x = 8 / 11
##   CAR_LANE      (22, 0, -38.5)        a parked sedan, long side facing +Z (spawned by the test)
##   KERB_LANE     (32, 0, -38.8)        0.6 m box: too low to be cover
##   OPEN_SPOT     (45, 0, -30)          open floor

const FACE_Z := -40.0
const LOW_LANE := Vector3(0.0, 0.0, -38.6)
const LOW_HEIGHT := 1.1
const LOW_HALF_WIDTH := 2.0
const HIGH_LANE := Vector3(9.5, 0.0, -38.6)
const HIGH_HEIGHT := 2.5
const HIGH_X0 := 8.0
const HIGH_X1 := 11.0
const HIGH_DEPTH := 2.0
const CAR_LANE := Vector3(22.0, 0.0, -38.5)
const CAR_SPOT := Vector3(22.0, 0.0, -41.0)
const KERB_LANE := Vector3(32.0, 0.0, -38.8)
const OPEN_SPOT := Vector3(45.0, 0.0, -30.0)
const LOW_TARGET := Vector3(0.0, 0.0, -50.0)
const HIGH_TARGET := Vector3(12.6, 0.0, -50.0)
const BACKSTOP_Z := -58.0

var low_wall: StaticBody3D = null
var high_block: StaticBody3D = null
var backstop: StaticBody3D = null
var low_target: TargetDummy = null
var high_target: TargetDummy = null


## A shooting target (test equipment): records every hit. Not an NPC (no takedowns, no AI).
class TargetDummy extends StaticBody3D:
	var hits: Array = []

	func _init() -> void:
		collision_layer = Layers.NPC
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.7, 1.8, 0.4)
		cs.shape = shape
		cs.position = Vector3(0.0, 0.9, 0.0)
		add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = shape.size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.86, 0.40, 0.34)
		bm.material = mat
		mi.mesh = bm
		mi.position = cs.position
		add_child(mi)

	func apply_damage(info: Dictionary) -> void:
		hits.append(info)

	func chest() -> Vector3:
		return global_position + Vector3(0.0, 1.2, 0.0)


func _ready() -> void:
	name = "Plr3Stage"
	position = Vector3.ZERO
	var brick := Color(0.66, 0.45, 0.38)
	var stone := Color(0.70, 0.66, 0.58)
	low_wall = _box("LowWall", Vector3(LOW_LANE.x, LOW_HEIGHT * 0.5, FACE_Z - 0.15), Vector3(LOW_HALF_WIDTH * 2.0, LOW_HEIGHT, 0.3), brick)
	high_block = _box("HighBlock", Vector3((HIGH_X0 + HIGH_X1) * 0.5, HIGH_HEIGHT * 0.5, FACE_Z - HIGH_DEPTH * 0.5),
			Vector3(HIGH_X1 - HIGH_X0, HIGH_HEIGHT, HIGH_DEPTH), stone)
	_box("KerbBox", Vector3(KERB_LANE.x, 0.3, FACE_Z - 0.3), Vector3(3.0, 0.6, 0.6), stone)
	backstop = _box("Backstop", Vector3(6.0, 3.0, BACKSTOP_Z - 0.25), Vector3(26.0, 6.0, 0.5), Color(0.36, 0.44, 0.50))
	low_target = _target("LowTarget", LOW_TARGET)
	high_target = _target("HighTarget", HIGH_TARGET)


func _target(n: String, local: Vector3) -> TargetDummy:
	var t := TargetDummy.new()
	t.name = n
	add_child(t)
	t.position = local
	return t


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
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)
	body.position = local_pos
	return body
