extends Node
## plr2_traversal - headless test of the Wave 2 traversal layer of the player:
## vault (1.0 m wall), mantle (1.8 m ledge), nothing on a 2.6 m wall, running-jump ledge grab,
## a 5 m ladder (prompt, foot mount, climb, top dismount, mount from the top, climb down, step off,
## jump off), dodge roll while aiming, hard-landing stagger, blast ragdoll + get-up, blast stagger.
##
##   tools\godot.ps1 -Mode headless -Frames 5400 -TimeoutSec 300 `
##       -UserArgs '--test=plr2_traversal','--disable=traffic,peds,police','--test-timeout=240'
##
## Runs on the plr_arena slab (400 m above the island) with the plr2_stage obstacles.

const Arena := preload("res://gta/tests/plr_arena.gd")
const Stage := preload("res://gta/tests/plr2_stage.gd")

var P: Player = null
var arena: Arena = null
var stage: Stage = null
var T: Node = null


func _ready() -> void:
	T = TestHarness
	await _run()


func _run() -> void:
	P = Game.player as Player
	if not T.check(P != null, "Game.player is a Player"):
		T.finish(false, "no player")
		return
	arena = Arena.new()
	Game.main.add_child(arena)
	stage = Stage.new()
	arena.add_child(stage)
	await T.wait_physics_frames(5)
	await _test_vault()
	await _test_mantle()
	await _test_too_high()
	await _test_air_mantle()
	await _test_ladder()
	await _test_roll()
	await _test_hard_landing()
	await _test_blasts()
	await _test_real_ladders()
	_release_all()
	T.finish(true, "traversal")


# --- helpers ---------------------------------------------------------------------------------------

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "crouch", "aim", "fire",
			"interact", "enter_vehicle", "melee_heavy"]:
		Input.action_release(a)


func _place(local: Vector3, yaw: float = 0.0) -> void:
	_release_all()
	P.teleport(arena.at(local) + Vector3(0.0, 0.03, 0.0), yaw)
	await T.wait_physics_frames(15)


func _tap(action: String) -> void:
	Input.action_press(action)
	await T.wait_physics_frames(2)
	Input.action_release(action)
	await T.wait_physics_frames(1)


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	while t < timeout:
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
		t += step
	return bool(cond.call())


func _face_z() -> float:
	return arena.at(Vector3(0.0, 0.0, Stage.FACE_Z)).z


func _floor_y() -> float:
	return arena.at(Vector3.ZERO).y


## Run at the obstacle and press jump `dist` metres before its face.
func _run_and_jump(lane: Vector3, dist: float) -> void:
	await _place(lane, 0.0)
	var fz := _face_z()
	Input.action_press("move_forward")
	await _until(func() -> bool: return P.global_position.z - fz < dist, 3.0)
	await _tap("jump")


# --- vault / mantle --------------------------------------------------------------------------------

func _test_vault() -> void:
	await _run_and_jump(Stage.VAULT_LANE, 1.0)
	var started := await _until(func() -> bool: return P.state_id == "vault", 0.3)
	var v := P.states["vault"] as PlayerStateVault
	T.check(started, "jump at a 1.0 m wall starts a vault (state %s)" % P.state_id)
	T.check(v.kind == "vault", "... a vault, not a mantle (%s)" % v.kind)
	await T.wait_physics_frames(12)
	T.check(P.animator.state == "vault" and P.animator.motion_t > 0.0 and P.animator.motion_t < 1.0,
			"animator plays 'vault' with the motion curve progress (%s, t %.2f, hands at +%.2f m)" % [P.animator.state, P.animator.motion_t, P.animator.motion_height])
	var done := await _until(func() -> bool: return P.state_id != "vault", 2.0)
	var fz := _face_z()
	T.check(done and P.global_position.z < fz - 0.5, "the vault ends on the far side (z %.2f, wall face %.2f)" % [P.global_position.z, fz])
	T.check(absf(P.global_position.y - _floor_y()) < 0.25, "... back on the floor (y %.2f)" % (P.global_position.y - _floor_y()))
	T.check(Vector2(P.velocity.x, P.velocity.z).length() > 2.0, "... and keeps running (%.1f m/s)" % Vector2(P.velocity.x, P.velocity.z).length())
	Input.action_release("move_forward")
	await T.wait_physics_frames(10)
	T.check(P.state_id == "on_foot" and P.is_collision_enabled(), "on foot with collision after the vault (%s)" % P.state_id)


func _test_mantle() -> void:
	await _run_and_jump(Stage.MANTLE_LANE, 0.9)
	var started := await _until(func() -> bool: return P.state_id == "vault", 0.3)
	var v := P.states["vault"] as PlayerStateVault
	T.check(started and v.kind == "mantle", "jump at a 1.8 m ledge starts a mantle (state %s, kind %s)" % [P.state_id, v.kind])
	var t0 := Time.get_ticks_msec()
	var done := await _until(func() -> bool: return P.state_id != "vault", 2.5)
	Input.action_release("move_forward")
	var top := _floor_y() + Stage.MANTLE_HEIGHT
	T.check(done and absf(P.global_position.y - top) < 0.2, "the mantle ends standing on the ledge (y %.2f, top %.2f)" % [P.global_position.y - _floor_y(), Stage.MANTLE_HEIGHT])
	T.check(P.global_position.z < _face_z() - 0.2, "... beyond the edge (z %.2f)" % (P.global_position.z - _face_z()))
	await T.wait_physics_frames(10)
	T.check(P.state_id == "on_foot" and P.grounded, "on foot on top (%s, grounded %s)" % [P.state_id, str(P.grounded)])
	T.log_line("mantle took %d ms (real)" % (Time.get_ticks_msec() - t0))


func _test_too_high() -> void:
	await _run_and_jump(Stage.HIGH_LANE, 0.9)
	var vaulted := await _until(func() -> bool: return P.state_id == "vault", 0.6)
	T.check(not vaulted, "a 2.6 m wall is neither vaulted nor mantled (state %s)" % P.state_id)
	Input.action_release("move_forward")
	await _until(func() -> bool: return P.state_id == "on_foot", 2.0)


func _test_air_mantle() -> void:
	# jump too far away for the ground probe: the jump carries the player into the ledge
	await _run_and_jump(Stage.AIR_LANE, 2.0)
	var in_air := P.state_id == "air"
	var grabbed := await _until(func() -> bool: return P.state_id == "vault", 1.2)
	var v := P.states["vault"] as PlayerStateVault
	T.check(in_air and grabbed and v.kind == "mantle", "a running jump into a 1.8 m ledge grabs it (air %s, grab %s, kind %s)" % [str(in_air), str(grabbed), v.kind])
	await _until(func() -> bool: return P.state_id != "vault", 2.5)
	Input.action_release("move_forward")
	T.check(absf(P.global_position.y - (_floor_y() + Stage.MANTLE_HEIGHT)) < 0.25, "... and climbs onto it (y %.2f)" % (P.global_position.y - _floor_y()))


# --- ladder ---------------------------------------------------------------------------------------

func _test_ladder() -> void:
	var top_y := _floor_y() + Stage.LADDER_HEIGHT
	await _place(Stage.LADDER_LANE, 0.0)
	await T.wait_physics_frames(15)
	var prompt := P.interaction.get_prompt_text()
	T.check(prompt == "Climb ladder", "the ladder foot shows a prompt ('%s')" % prompt)
	await _tap("interact")
	var on := await _until(func() -> bool: return P.state_id == "ladder", 0.5)
	T.check(on and P.on_ladder, "interact at the foot mounts the ladder (state %s)" % P.state_id)
	Input.action_press("move_forward")
	await T.wait_physics_frames(50)
	var mid_y := P.global_position.y - _floor_y()
	T.check(P.state_id == "ladder" and mid_y > 0.5, "forward climbs up (%.2f m after 0.8 s)" % mid_y)
	T.check(P.animator.state == "climb_ladder" and P.animator.vertical_speed > 0.5, "animator 'climb_ladder' climbing (%s, %.1f m/s)" % [P.animator.state, P.animator.vertical_speed])
	T.check(not P.is_collision_enabled(), "no body collision while on the ladder")
	var up := await _until(func() -> bool: return P.state_id != "ladder", 6.0)
	Input.action_release("move_forward")
	T.check(up and P.state_id == "on_foot" and absf(P.global_position.y - top_y) < 0.25,
			"at the top the player climbs over onto the platform (state %s, y %.2f)" % [P.state_id, P.global_position.y - _floor_y()])
	await T.wait_physics_frames(20)
	# from the top: face the edge and climb down
	await _place(Vector3(Stage.LADDER_LANE.x, Stage.LADDER_HEIGHT, Stage.FACE_Z - 0.9), PI)
	await T.wait_physics_frames(15)
	prompt = P.interaction.get_prompt_text()
	T.check(prompt == "Climb down", "the top of the ladder shows 'Climb down' ('%s')" % prompt)
	await _tap("interact")
	on = await _until(func() -> bool: return P.state_id == "ladder", 0.5)
	T.check(on, "interact at the top mounts the ladder from above")
	Input.action_press("move_back")
	var down := await _until(func() -> bool: return P.state_id != "ladder", 7.0)
	Input.action_release("move_back")
	T.check(down and P.state_id == "on_foot" and absf(P.global_position.y - _floor_y()) < 0.25,
			"back climbs down and steps off at the foot (state %s, y %.2f)" % [P.state_id, P.global_position.y - _floor_y()])
	# jump off half way
	await _place(Stage.LADDER_LANE, 0.0)
	await T.wait_physics_frames(12)
	await _tap("interact")
	await _until(func() -> bool: return P.state_id == "ladder", 0.5)
	Input.action_press("move_forward")
	await T.wait_physics_frames(70)
	Input.action_release("move_forward")
	await _tap("jump")
	var off := await _until(func() -> bool: return P.state_id == "air", 0.3)
	var landed := await _until(func() -> bool: return P.state_id == "on_foot", 2.5)
	T.check(off and landed and P.global_position.z > _face_z() + 0.6, "jump pushes off the ladder backwards and lands (z +%.2f)" % (P.global_position.z - _face_z()))


# --- roll, landings, blasts -----------------------------------------------------------------------

func _test_roll() -> void:
	await _place(Stage.OPEN_SPOT, 0.0)
	if P.inventory != null and P.inventory.has_method("equip"):
		P.inventory.call("equip", "pistol")
	await T.wait_physics_frames(30)
	Input.action_press("aim")
	await T.wait_physics_frames(10)
	var start := P.global_position
	Input.action_press("move_right")
	await T.wait_physics_frames(3)
	await _tap("jump")
	var rolling := await _until(func() -> bool: return P.state_id == "roll", 0.3)
	T.check(rolling, "aim + right + jump = dodge roll (state %s, aiming %s)" % [P.state_id, str(P.is_aiming)])
	await T.wait_physics_frames(8)
	T.check(P.animator.state == "roll" and P.animator.motion_t > 0.0, "animator plays 'roll' (%s, t %.2f)" % [P.animator.state, P.animator.motion_t])
	await _until(func() -> bool: return P.state_id != "roll", 1.5)
	Input.action_release("move_right")
	var moved := P.global_position - start
	T.check(moved.x > 2.2 and absf(moved.z) < 1.2, "the roll covers ground to the right (%.2f m right, %.2f m fwd)" % [moved.x, -moved.z])
	await T.wait_physics_frames(6)
	T.check(P.state_id == "on_foot" and P.is_aiming, "back on foot and still aiming after the roll (%s)" % P.state_id)
	Input.action_release("aim")
	if P.inventory != null and P.inventory.has_method("equip"):
		P.inventory.call("equip", "fists")
	await T.wait_physics_frames(10)


func _test_hard_landing() -> void:
	await _place(Stage.OPEN_SPOT + Vector3(-10.0, 0.0, 0.0), 0.0)
	P.heal(1000.0)
	var hp0 := P.health
	Input.action_press("move_forward")
	P.teleport(arena.at(Stage.OPEN_SPOT + Vector3(-10.0, 6.5, 0.0)), 0.0)
	var airborne := await _until(func() -> bool: return P.state_id == "air", 0.6)
	var landed := await _until(func() -> bool: return P.state_id == "on_foot", 2.5)
	var of := P.states["on_foot"] as PlayerStateOnFoot
	var stagger := of.is_staggering()
	T.check(airborne and landed and stagger, "a 6.5 m drop at a run lands with a stagger (air %s, landed %s, stagger %s)" % [str(airborne), str(landed), str(stagger)])
	T.check(P.health < hp0, "... and costs health (%.0f -> %.0f)" % [hp0, P.health])
	Input.action_release("move_forward")
	await T.wait_physics_frames(40)


func _test_blasts() -> void:
	await _place(Stage.OPEN_SPOT, 0.0)
	P.heal(1000.0)
	P.armor = 0.0
	var pos := P.global_position
	# a blast close by: knocked down, gets up again
	P.apply_damage(Dmg.make(28.0, "explosion", null, pos + Vector3(2.0, 0.5, 0.0), Vector3(-1.0, 0.2, 0.0).normalized(), {"impulse": 320.0}))
	await T.wait_physics_frames(3)
	T.check(P.state_id == "ragdoll", "a strong blast ragdolls the player (state %s)" % P.state_id)
	var up := await _until(func() -> bool: return P.state_id == "on_foot", 6.0)
	T.check(up and not P.is_dead, "... who gets up again (state %s)" % P.state_id)
	await T.wait_physics_frames(30)
	# a weak blast further away: a stagger, no knock-down
	P.heal(1000.0)
	P.apply_damage(Dmg.make(9.0, "explosion", null, P.global_position + Vector3(6.0, 0.5, 0.0), Vector3(-1.0, 0.0, 0.0), {"impulse": 90.0}))
	await T.wait_physics_frames(2)
	var of := P.states["on_foot"] as PlayerStateOnFoot
	T.check(P.state_id == "on_foot" and of.is_staggering(), "a weak blast only staggers (state %s, stagger %s)" % [P.state_id, str(of.is_staggering())])
	# the blast is on world +X; in the body frame (x right, y front) that depends on the facing after
	# the get-up
	var l := P.global_basis.inverse() * Vector3(1.0, 0.0, 0.0)
	var want := Vector2(l.x, -l.z).normalized()
	T.check(P.animator.get_action() == "hit_react" and P.animator.hit_dir.dot(want) > 0.8,
			"... with a hit reaction from the blast side (action '%s', from %s, expected %s)" % [P.animator.get_action(), str(P.animator.hit_dir), str(want)])
	await T.wait_physics_frames(30)


# --- the ladders of the real world (city / props), logged as REAL_LADDER -----------------------------

func _test_real_ladders() -> void:
	var real: Array[Node3D] = []
	for n: Node in get_tree().get_nodes_in_group("ladder"):
		if n is Node3D and not stage.is_ancestor_of(n) and (n as Node3D).is_inside_tree():
			real.append(n as Node3D)
	T.log_line("REAL_LADDER: %d ladder nodes in the world" % real.size())
	if real.is_empty():
		return
	var topped := 0
	var tried := 0
	for l: Node3D in real:
		if tried >= 3:
			break
		tried += 1
		var h := PlayerStateLadder.ladder_height(l)
		var back := PlayerStateLadder.ladder_back(l)
		var stand := l.global_position + back * (PlayerStateLadder.STAND_OFF + 0.2)
		_release_all()
		P.teleport(stand + Vector3(0.0, 0.05, 0.0), atan2(back.x, back.z))
		await T.wait_physics_frames(6)
		var ok := P.start_ladder(l, 0)
		Input.action_press("move_forward")
		var done := await _until(func() -> bool: return P.state_id != "ladder", h / PlayerStateLadder.CLIMB_SPEED + 2.5)
		Input.action_release("move_forward")
		var rise := P.global_position.y - l.global_position.y
		var top_out := done and P.state_id == "on_foot" and absf(rise - h) < 0.35
		if top_out:
			topped += 1
		elif P.state_id == "ladder":
			# what blocks the top-out? (colliders around the default exit spot)
			var ex := l.global_position + Vector3(0.0, h, 0.0) - back * PlayerStateLadder.TOP_EXIT_FORWARD
			var sq := PhysicsShapeQueryParameters3D.new()
			var sph := SphereShape3D.new()
			sph.radius = 0.6
			sq.shape = sph
			sq.collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.PROP
			sq.transform = Transform3D(Basis.IDENTITY, ex + Vector3(0.0, 0.9, 0.0))
			var names: PackedStringArray = []
			for r: Dictionary in P.get_world_3d().direct_space_state.intersect_shape(sq, 6):
				var c: Object = r["collider"]
				names.append(str((c as Node).get_path()) if c is Node else str(c))
			T.log_line("REAL_LADDER   top exit %s blocked by %s" % [str(ex.snapped(Vector3.ONE * 0.1)), str(names)])
		T.log_line("REAL_LADDER %s h=%.1f at %s: mounted %s, end state %s, %.2f m above the foot%s" % [l.name, h,
				str(l.global_position.snapped(Vector3.ONE * 0.1)), str(ok), P.state_id, rise, " (topped out)" if top_out else ""])
		await T.wait_physics_frames(10)
	T.check(topped > 0, "at least one real world ladder is climbed to the top (%d of %d)" % [topped, tried])
