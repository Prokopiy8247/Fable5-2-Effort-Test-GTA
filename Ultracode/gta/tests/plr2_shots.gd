extends Node
## plr2_shots - windowed screenshots of the Wave 2 player layer (look at them!):
##   qa/screenshots/plr2_vault.png      side view, mid vault over the 1 m wall
##   qa/screenshots/plr2_mantle.png     side view, pulling up onto the 1.8 m ledge
##   qa/screenshots/plr2_ladder.png     three-quarter view, climbing the 5 m ladder
##   qa/screenshots/plr2_punch.png      side view, a straight punch into an opponent
##   qa/screenshots/plr2_block.png      front view, guard up
##   qa/screenshots/plr2_driveby.png    the gameplay camera aiming out of the driver's window
##   qa/screenshots/plr2_driveby_side.png  outside view of the arm out of the window
##   qa/screenshots/plr2_down.png       gameplay camera right after dying ("DOWN" banner)
##
##   tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 150 -UserArgs '--test=plr2_shots','--disable=traffic,peds,police'
##   (add '--only=traversal|melee|driveby|down' to re-shoot one group)
##
## The motion is frozen (Engine.time_scale = 0) for each picture so the pose is the one asked for.

const Arena := preload("res://gta/tests/plr_arena.gd")
const Stage := preload("res://gta/tests/plr2_stage.gd")
const HUMANOID := "res://gta/scenes/characters/humanoid.tscn"

var P: Player = null
var arena: Arena = null
var stage: Stage = null
var T: Node = null
var cam: Camera3D = null


func _ready() -> void:
	T = TestHarness
	await _run()


func _run() -> void:
	P = Game.player as Player
	arena = Arena.new()
	Game.main.add_child(arena)
	stage = Stage.new()
	arena.add_child(stage)
	arena.ensure_light()
	cam = Camera3D.new()
	cam.name = "ShotCamera"
	cam.fov = 50.0
	arena.add_child(cam)
	await T.wait_physics_frames(10)
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	if only == "" or only == "traversal":
		await _shot_vault()
		await _shot_mantle()
		await _shot_ladder()
	if only == "" or only == "melee":
		await _shot_melee()
	if only == "" or only == "driveby":
		await _shot_driveby()
	if only == "" or only == "down":
		await _shot_down()
	Engine.time_scale = 1.0
	T.finish(true, "plr2 shots")


# --- helpers ---------------------------------------------------------------------------------------

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "aim", "fire", "interact", "enter_vehicle"]:
		Input.action_release(a)


func _place(local: Vector3, yaw: float = 0.0) -> void:
	_release_all()
	P.teleport(arena.at(local) + Vector3(0.0, 0.03, 0.0), yaw)
	P.heal(1000.0)
	await T.wait_physics_frames(10)


func _until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
	return bool(cond.call())


## Freeze the world, take the picture through `eye -> at` (or the gameplay camera), unfreeze.
func _snap(shot_name: String, eye: Vector3 = Vector3.INF, at: Vector3 = Vector3.ZERO) -> void:
	Engine.time_scale = 0.0
	if eye.is_finite():
		cam.global_position = eye
		cam.look_at(at, Vector3.UP)
		cam.make_current()
	await T.wait_frames(2)
	await T.shot(shot_name)
	if eye.is_finite() and P.camera != null and P.camera.camera != null:
		P.camera.camera.make_current()
	Engine.time_scale = 1.0


# --- shots ----------------------------------------------------------------------------------------

func _shot_vault() -> void:
	await _place(Stage.VAULT_LANE)
	var fz := arena.at(Vector3(0.0, 0.0, Stage.FACE_Z)).z
	Input.action_press("move_forward")
	await _until(func() -> bool: return P.global_position.z - fz < 1.0, 120)
	Input.action_press("jump")
	await _until(func() -> bool: return P.state_id == "vault" and P.animator.motion_t > 0.42, 60)
	Input.action_release("jump")
	var c := arena.at(Vector3(Stage.VAULT_LANE.x, 0.9, Stage.FACE_Z))
	await _snap("plr2_vault", c + Vector3(4.2, 0.5, 0.6), c)
	Input.action_release("move_forward")
	await _until(func() -> bool: return P.state_id != "vault", 60)


func _shot_mantle() -> void:
	await _place(Stage.MANTLE_LANE)
	var fz := arena.at(Vector3(0.0, 0.0, Stage.FACE_Z)).z
	Input.action_press("move_forward")
	await _until(func() -> bool: return P.global_position.z - fz < 0.9, 120)
	Input.action_press("jump")
	await _until(func() -> bool: return P.state_id == "vault" and P.animator.motion_t > 0.45, 90)
	Input.action_release("jump")
	Input.action_release("move_forward")
	var c := arena.at(Vector3(Stage.MANTLE_LANE.x, 1.4, Stage.FACE_Z))
	await _snap("plr2_mantle", c + Vector3(4.0, 0.6, 2.2), c)
	await _until(func() -> bool: return P.state_id != "vault", 90)


func _shot_ladder() -> void:
	await _place(Stage.LADDER_LANE)
	await T.wait_physics_frames(12)
	Input.action_press("interact")
	await T.wait_physics_frames(2)
	Input.action_release("interact")
	await _until(func() -> bool: return P.state_id == "ladder", 30)
	Input.action_press("move_forward")
	await T.wait_physics_frames(60)
	var c := P.global_position + Vector3(0.0, 1.0, 0.0)
	await _snap("plr2_ladder", c + Vector3(2.6, 0.4, 2.8), c + Vector3(0.0, 0.0, -0.3))
	Input.action_release("move_forward")
	P.teleport(arena.at(Stage.OPEN_SPOT), 0.0)
	await T.wait_physics_frames(10)


func _shot_melee() -> void:
	# an opponent made of the shared humanoid (test equipment) standing in front of the player
	var foe := Node3D.new()
	foe.name = "ShotOpponent"
	arena.add_child(foe)
	foe.add_to_group("npc")
	var spot := Stage.OPEN_SPOT + Vector3(-12.0, 0.0, 0.0)
	foe.global_transform = Transform3D(Basis(Vector3.UP, PI), arena.at(spot + Vector3(0.0, 0.0, -1.25)))
	if ResourceLoader.exists(HUMANOID):
		var vis := (load(HUMANOID) as PackedScene).instantiate() as Node3D
		foe.add_child(vis)
		if vis.has_method("randomize_appearance"):
			vis.call("randomize_appearance", "civilian_tough", 11)
		var skel := Ragdoll.find_skeleton(vis)
		if skel != null:
			var an := HumanoidAnimator.new()
			foe.add_child(an)
			an.setup(skel)
			an.weapon_pose = "none"
			an.state = "melee"
			an.guard = 0.6
	await _place(spot, 0.0)
	if P.inventory != null and P.inventory.has_method("equip"):
		P.inventory.call("equip", "fists")
	await T.wait_physics_frames(12)
	Input.action_press("fire")
	await T.wait_physics_frames(2)
	Input.action_release("fire")
	await _until(func() -> bool: return P.animator.get_action().begins_with("punch"), 30)
	await T.wait_physics_frames(9)
	var c := arena.at(spot + Vector3(0.0, 1.15, -0.6))
	await _snap("plr2_punch", c + Vector3(3.4, 0.25, 0.4), c)
	await T.wait_physics_frames(24)
	Input.action_press("aim")
	await _until(func() -> bool: return P.is_blocking, 30)
	await T.wait_physics_frames(12)
	var face := P.global_position + Vector3(0.0, 1.35, 0.0)
	var fwd := -P.global_basis.z
	await _snap("plr2_block", face + fwd * 1.5 + P.global_basis.x * 1.9 + Vector3(0.0, 0.15, 0.0), face)
	Input.action_release("aim")
	foe.queue_free()
	await T.wait_physics_frames(10)


func _shot_driveby() -> void:
	var car := Game.spawn_vehicle("sedan", Transform3D(Basis.IDENTITY, arena.at(Vector3(0.0, 0.6, 52.0))), {"owner_tag": "parked"})
	if car == null:
		T.log_line("SKIP drive-by shots: no sedan")
		return
	await T.wait_physics_frames(20)
	P.teleport(arena.at(Vector3(-3.0, 0.03, 52.0)), 0.0)
	await T.wait_physics_frames(4)
	P.enter_vehicle(car, 0, true)
	await T.wait_physics_frames(10)
	if P.inventory != null and P.inventory.has_method("equip"):
		P.inventory.call("equip", "pistol")
	await T.wait_physics_frames(16)
	Input.action_press("aim")
	await T.wait_frames(12)
	# look out of the left window, slightly ahead, at a stand-in figure (test equipment)
	var left := -car.global_basis.x
	var goal := car.global_position + left * 10.0 - car.global_basis.z * 3.0 + Vector3(0.0, 0.6, 0.0)
	var figure: Node3D = null
	if ResourceLoader.exists(HUMANOID):
		figure = (load(HUMANOID) as PackedScene).instantiate() as Node3D
		arena.add_child(figure)
		figure.global_transform = Transform3D(Basis(Vector3.UP, atan2(left.x, left.z)), Vector3(goal.x, arena.at(Vector3.ZERO).y, goal.z))
		if figure.has_method("randomize_appearance"):
			figure.call("randomize_appearance", "civilian_m", 3)
	for i in 5:
		await T.wait_frames(2)
		var o := P.camera.get_aim_origin()
		var d := P.camera.get_aim_direction()
		var want := (goal - o).normalized()
		P.camera.apply_look(angle_difference(atan2(-d.x, -d.z), atan2(-want.x, -want.z)), asin(want.y) - asin(d.y))
	await T.wait_frames(10)
	await _snap("plr2_driveby")
	var seat := P.global_position
	await _snap("plr2_driveby_side", seat + left * 3.2 - car.global_basis.z * 2.4 + Vector3(0.0, 0.5, 0.0), seat + left * 0.4 + Vector3(0.0, 0.4, 0.0))
	Input.action_release("aim")
	P.exit_vehicle()
	await _until(func() -> bool: return P.state_id == "on_foot", 40)
	if figure != null:
		figure.queue_free()


func _shot_down() -> void:
	await _place(Stage.OPEN_SPOT, 0.4)
	await T.wait_physics_frames(10)
	P.apply_damage(Dmg.make(500.0, "bullet", null, P.get_target_position(), Vector3(0.3, 0.0, -1.0).normalized(), {"impulse": 160.0}))
	await T.wait_frames(18)
	await _snap("plr2_down")
