extends Node
## plr3_shots - windowed screenshots of cover / stealth (look at them!):
##   qa/screenshots/plr3_cover_low.png        gameplay camera, hunkered behind the 1.1 m wall (pistol)
##   qa/screenshots/plr3_cover_low_out.png    outside view of the low-cover pose
##   qa/screenshots/plr3_peek.png             gameplay camera, leaning out past the 2.5 m corner, aiming
##   qa/screenshots/plr3_peek_out.png         outside view of the corner peek
##   qa/screenshots/plr3_cover_high_out.png   outside view, back to the high block at its corner
##   qa/screenshots/plr3_blind_low.png        outside view, blind fire over the low wall
##   qa/screenshots/plr3_blind_corner.png     outside view, blind fire round the high corner
##   qa/screenshots/plr3_stealth_walk.png     side view, sneaking
##   qa/screenshots/plr3_takedown.png         side view, rear choke takedown (fists)
##   qa/screenshots/plr3_takedown_knife.png   side view, knife takedown
##
##   tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 150 -UserArgs '--test=plr3_shots','--disable=traffic,peds,police'
##   (add '--only=cover|stealth' to re-shoot one group)
##
## The motion is frozen (Engine.time_scale = 0) for each picture so the pose is the one asked for.

const Arena := preload("res://gta/tests/plr_arena.gd")
const Stage := preload("res://gta/tests/plr3_stage.gd")
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
	if P.inventory != null and P.inventory.has_method("give_weapon"):
		P.inventory.call("give_weapon", "pistol", 200)
		P.inventory.call("give_weapon", "knife", 1)
		P.inventory.set("infinite_ammo", true)
	await T.wait_physics_frames(10)
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	if only == "" or only == "cover":
		await _shot_cover()
	if only == "" or only == "stealth":
		await _shot_stealth()
	Engine.time_scale = 1.0
	T.finish(true, "plr3 shots")


# --- helpers ---------------------------------------------------------------------------------------

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "aim", "fire", "cover", "stealth", "melee_heavy"]:
		Input.action_release(a)


func _place(local: Vector3, yaw: float = 0.0) -> void:
	_release_all()
	P.teleport(arena.at(local) + Vector3(0.0, 0.03, 0.0), yaw)
	P.heal(1000.0)
	await T.wait_physics_frames(8)


func _tap(action: String, frames: int = 2) -> void:
	Input.action_press(action)
	await T.wait_physics_frames(frames)
	Input.action_release(action)
	await T.wait_physics_frames(1)


func _until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
	return bool(cond.call())


func _equip(id: String) -> void:
	if P.inventory != null and P.inventory.has_method("equip"):
		P.inventory.call("equip", id)
	await T.wait_physics_frames(24)


func _look_at(world: Vector3) -> void:
	for i in 6:
		await T.wait_frames(2)
		var o := P.camera.get_aim_origin()
		var d := P.camera.get_aim_direction()
		var want := (world - o).normalized()
		P.camera.apply_look(angle_difference(atan2(-d.x, -d.z), atan2(-want.x, -want.z)), asin(clampf(want.y, -1.0, 1.0)) - asin(clampf(d.y, -1.0, 1.0)))


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


func _cover_state() -> PlayerStateCover:
	return P.states["cover"] as PlayerStateCover


func _enter_cover(local: Vector3) -> bool:
	await _place(local, 0.0)
	await _tap("cover")
	return await _until(func() -> bool: return P.state_id == "cover" and _cover_state().phase == PlayerStateCover.Phase.COVER, 90)


## A humanoid stand-in (test equipment) facing `yaw`, in group "npc" so the takedown scanner sees it.
func _make_victim(local: Vector3, yaw: float) -> Node3D:
	var foe := Node3D.new()
	foe.name = "ShotVictim"
	arena.add_child(foe)
	foe.add_to_group("npc")
	foe.global_transform = Transform3D(Basis(Vector3.UP, yaw), arena.at(local))
	if ResourceLoader.exists(HUMANOID):
		var vis := (load(HUMANOID) as PackedScene).instantiate() as Node3D
		foe.add_child(vis)
		if vis.has_method("randomize_appearance"):
			vis.call("randomize_appearance", "civilian_m", 7)
		var skel := Ragdoll.find_skeleton(vis)
		if skel != null:
			var an := HumanoidAnimator.new()
			foe.add_child(an)
			an.setup(skel)
			an.state = "idle"
	return foe


# --- shots ----------------------------------------------------------------------------------------

func _shot_cover() -> void:
	await _equip("pistol")
	var st := _cover_state()
	# low cover: gameplay camera + outside
	if await _enter_cover(Stage.LOW_LANE + Vector3(-0.6, 0.0, 0.0)):
		await T.wait_physics_frames(20)
		P.camera.pitch = -0.2
		await T.wait_frames(10)
		await _snap("plr3_cover_low")
		var c := P.global_position + Vector3(0.0, 0.7, 0.0)
		await _snap("plr3_cover_low_out", c + Vector3(2.6, 0.5, 2.2), c)
		# blind fire over the top (outside view from the side, the backstop beyond)
		await _look_at(stage.low_target.chest())
		Input.action_press("fire")
		await _until(func() -> bool: return st.blind > 0.95, 30)
		await T.wait_frames(6)
		await _snap("plr3_blind_low", c + Vector3(3.2, 0.7, -0.4), c + Vector3(0.0, 0.25, -0.2))
		Input.action_release("fire")
		await T.wait_physics_frames(40)
	# high cover: back to the block at its right corner, then lean out and aim
	if await _enter_cover(Stage.HIGH_LANE):
		Input.action_press("move_right")
		await _until(func() -> bool: return st.edge_pos, 200)
		await T.wait_physics_frames(20)
		Input.action_release("move_right")
		await T.wait_physics_frames(30)
		var c2 := P.global_position + Vector3(0.0, 1.0, 0.0)
		await _snap("plr3_cover_high_out", c2 + Vector3(2.4, 0.4, 2.6), c2 + Vector3(0.2, 0.0, 0.0))
		# blind fire round the corner
		await _look_at(stage.high_target.chest())
		Input.action_press("fire")
		await _until(func() -> bool: return st.blind > 0.95, 30)
		await T.wait_frames(6)
		var c3 := P.global_position + Vector3(0.0, 1.2, 0.0)
		await _snap("plr3_blind_corner", c3 + Vector3(2.8, 0.6, 1.4), c3 + Vector3(0.3, 0.0, -0.3))
		Input.action_release("fire")
		await T.wait_physics_frames(45)
		# peek while aiming
		await _look_at(stage.high_target.chest())
		Input.action_press("aim")
		await _until(func() -> bool: return st.peek > 0.97, 60)
		await _look_at(stage.high_target.chest())
		await T.wait_frames(12)
		await _snap("plr3_peek")
		var c4 := P.global_position + Vector3(0.0, 1.2, 0.0)
		await _snap("plr3_peek_out", c4 + Vector3(2.0, 0.5, -2.6), c4)
		Input.action_release("aim")
		await T.wait_physics_frames(20)
	_release_all()
	await _tap("cover")
	await T.wait_physics_frames(6)


func _shot_stealth() -> void:
	await _equip("fists")
	var spot := Stage.OPEN_SPOT
	# sneaking (side view)
	await _place(spot, PI * 0.5)
	await _tap("stealth")
	Input.action_press("move_forward")
	await T.wait_physics_frames(45)
	var c := P.global_position + Vector3(0.0, 0.9, 0.0)
	await _snap("plr3_stealth_walk", c + Vector3(-0.8, 0.1, 3.4), c)
	Input.action_release("move_forward")
	await T.wait_physics_frames(10)
	# rear choke takedown
	var vic := _make_victim(spot + Vector3(-4.0, 0.0, 0.0), 0.0)
	await _place(spot + Vector3(-4.0, 0.0, 1.2), 0.0)
	if not P.in_stealth:
		await _tap("stealth")
	await T.wait_physics_frames(12)
	await _tap("melee_heavy")
	await _until(func() -> bool: return P.state_id == "takedown" and P.animator.motion_t > 0.5, 60)
	var v := vic.global_position + Vector3(0.0, 1.1, 0.4)
	await _snap("plr3_takedown", v + Vector3(3.0, 0.3, 0.2), v)
	await _until(func() -> bool: return P.state_id != "takedown", 90)
	# knife takedown
	await _equip("knife")
	await _place(spot + Vector3(-4.0, 0.0, 1.2), 0.0)
	if not P.in_stealth:
		await _tap("stealth")
	await T.wait_physics_frames(12)
	await _tap("fire")
	await _until(func() -> bool: return P.state_id == "takedown" and P.animator.motion_t > 0.47, 60)
	await _snap("plr3_takedown_knife", v + Vector3(-2.6, 0.3, 1.6), v)
	await _until(func() -> bool: return P.state_id != "takedown", 90)
	vic.queue_free()
	await _tap("stealth")
