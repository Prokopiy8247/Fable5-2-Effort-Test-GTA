extends Node
## plr_move - headless functional test of the player controller (docs/PLAYER.md).
##
##   tools\godot.ps1 -Mode headless -Frames 5400 -TimeoutSec 300 `
##       -UserArgs '--test=plr_move','--disable=traffic,peds,police','--test-timeout=240'
##
## Covers: contract API surface, teleport, walk / run / sprint speeds (camera relative), stamina,
## jump height, crouch, kerb step-up, standing on a slope, armor / damage rules, invulnerability,
## ragdoll + get up, fall damage, swimming / diving / breath / drowning, death, respawn (direct and
## built-in fallback), save / load, input lock.
## The test builds its own arena (gta/tests/plr_arena.gd) so it does not depend on the world.

const Arena := preload("res://gta/tests/plr_arena.gd")

const CONTRACT_VARS: PackedStringArray = [
	"health", "max_health", "armor", "max_armor", "is_dead", "current_vehicle", "is_aiming",
	"is_sprinting", "is_crouching", "in_stealth", "in_cover", "is_swimming", "is_underwater",
	"has_parachute", "breath", "stamina", "noise_radius", "visual", "inventory",
]
const CONTRACT_METHODS: PackedStringArray = [
	"apply_damage", "heal", "add_armor", "teleport", "set_control_enabled", "enter_vehicle",
	"exit_vehicle", "get_aim_ray", "get_aim_point", "get_target_position", "add_recoil", "is_armed",
	"kill", "respawn", "ragdoll", "get_save_data", "load_save_data",
]
const MOVE_ACTIONS: PackedStringArray = ["move_forward", "move_back", "move_left", "move_right",
		"sprint", "jump", "crouch", "aim", "fire"]

var P: Player = null
var arena: Arena = null
var T: Node = null
var ev: Dictionary = {}
var skipped: PackedStringArray = []


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
	_connect_events()
	await T.wait_physics_frames(3)
	_test_api()
	await _test_teleport()
	await _test_speeds()
	await _test_jump()
	await _test_crouch()
	await _test_stealth()
	await _test_kerb()
	await _test_slope()
	await _test_damage()
	await _test_ragdoll()
	await _test_fall()
	await _test_swim()
	await _test_death_respawn()
	await _test_save()
	await _test_input_lock()
	_release_all()
	arena.remove_stub_world()
	var note := "player controller"
	if not skipped.is_empty():
		note += " | SKIPPED: " + ", ".join(skipped)
	T.finish(true, note)


# --- helpers ---------------------------------------------------------------------------------------

func _connect_events() -> void:
	for n: String in ["damaged", "health", "died", "respawned", "water_in", "water_out", "sub_on", "sub_off", "noise", "state"]:
		ev[n] = 0
	EventBus.player_damaged.connect(func(_a: float, _i: Dictionary) -> void: ev["damaged"] += 1)
	EventBus.player_health_changed.connect(func(_h: float, _a: float) -> void: ev["health"] += 1)
	EventBus.player_died.connect(func(_c: String) -> void: ev["died"] += 1)
	EventBus.player_respawned.connect(func(_p: Vector3) -> void: ev["respawned"] += 1)
	EventBus.player_entered_water.connect(func() -> void: ev["water_in"] += 1)
	EventBus.player_exited_water.connect(func() -> void: ev["water_out"] += 1)
	EventBus.player_submerged.connect(func(on: bool) -> void: ev["sub_on" if on else "sub_off"] += 1)
	EventBus.noise_emitted.connect(func(_p: Vector3, _r: float, _k: String, who: Node) -> void:
		if who == P:
			ev["noise"] += 1)
	EventBus.player_state_changed.connect(func(_s: String) -> void: ev["state"] += 1)


func _release_all() -> void:
	for a in MOVE_ACTIONS:
		Input.action_release(a)


func _tap(action: String) -> void:
	await get_tree().physics_frame
	Input.action_press(action)
	await T.wait_physics_frames(3)
	Input.action_release(action)


func _planar_speed() -> float:
	return Vector2(P.velocity.x, P.velocity.z).length()


func _place(local: Vector3, yaw: float = 0.0) -> void:
	_release_all()
	P.teleport(arena.at(local) + Vector3(0.0, 0.03, 0.0), yaw)
	await T.wait_physics_frames(20)


func _wait_state(id: String, max_seconds: float) -> bool:
	var frames := int(max_seconds * 60.0)
	for i in frames:
		if P.state_id == id:
			return true
		await get_tree().physics_frame
	return P.state_id == id


func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


# --- tests -----------------------------------------------------------------------------------------

func _test_api() -> void:
	var missing_v: PackedStringArray = []
	for v in CONTRACT_VARS:
		if not (v in P):
			missing_v.append(v)
	T.check(missing_v.is_empty(), "contract members exist" + ("" if missing_v.is_empty() else " (missing: %s)" % ", ".join(missing_v)))
	var missing_m: PackedStringArray = []
	for m in CONTRACT_METHODS:
		if not P.has_method(m):
			missing_m.append(m)
	T.check(missing_m.is_empty(), "contract methods exist" + ("" if missing_m.is_empty() else " (missing: %s)" % ", ".join(missing_m)))
	T.check(P.is_in_group("player"), "player is in group 'player'")
	T.check(P.collision_layer == Layers.PLAYER and P.collision_mask == Layers.PLAYER_MASK, "collision layer / mask from Layers")
	var cs := P.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var cap := cs.shape as CapsuleShape3D if cs != null else null
	T.check(cap != null and _near(cap.radius, 0.35, 0.001) and _near(cap.height, 1.8, 0.001) and _near(cs.position.y, 0.9, 0.001),
			"capsule r 0.35 h 1.8, origin at the feet")
	T.check(Game.camera_rig != null and Game.camera_rig is PlayerCamera, "Game.camera_rig is the PlayerCamera")
	var rig: Node = Game.camera_rig
	T.check(rig != null and ("yaw" in rig) and ("pitch" in rig) and rig.has_method("add_trauma") and rig.has_method("set_fov_override"),
			"camera rig exposes yaw / pitch / add_trauma / set_fov_override")
	T.check(P.visual != null and P.visual.has_method("get_skeleton"), "character visual (real humanoid model) is attached")
	T.check(P.animator != null and P.animator.is_ready(), "HumanoidAnimator is bound to the model skeleton")
	T.check(_near(P.health, 100.0, 0.01) and _near(P.max_health, 100.0, 0.01) and _near(P.max_armor, 100.0, 0.01), "100 hp / 100 max armor baseline")
	T.log_line("inventory present: %s, armed: %s" % [str(P.inventory != null), str(P.is_armed())])
	var ray: Dictionary = P.get_aim_ray()
	T.check(ray.has("origin") and ray.has("direction") and ray["origin"] is Vector3 and ray["direction"] is Vector3, "get_aim_ray returns {origin, direction}")
	T.check(P.get_aim_point() is Vector3 and P.get_target_position() is Vector3, "get_aim_point / get_target_position return Vector3")


func _test_teleport() -> void:
	var target: Vector3 = arena.at(Vector3(2.0, 0.03, 3.0))
	P.teleport(target, 0.7)
	T.check(P.global_position.distance_to(target) < 0.01 and _near(P.global_rotation.y, 0.7, 0.001), "teleport places the body and the yaw")
	T.check(_near(P.camera.yaw, 0.7, 0.001), "teleport puts the camera behind the new facing")
	await T.wait_physics_frames(20)
	T.check(P.grounded and P.state_id == "on_foot", "stands on the ground after the teleport (state %s)" % P.state_id)
	T.check(absf(P.global_position.y - target.y) < 0.05, "feet rest on the floor (dy %.3f)" % (P.global_position.y - target.y))


func _test_speeds() -> void:
	await _place(Vector3(0.0, 0.0, 20.0), 0.0)
	# walk: partially tilted stick
	Input.action_press("move_forward", 0.5)
	await T.wait_seconds(1.5)
	var walk := _planar_speed()
	var p0 := P.global_position
	await T.wait_seconds(1.0)
	var walked := P.global_position - p0
	T.check(_near(walk, Player.WALK_SPEED, 0.12), "walk speed %.2f m/s (want %.1f)" % [walk, Player.WALK_SPEED])
	T.check(walked.z < -1.6 and absf(walked.x) < 0.1, "walks straight ahead along the camera forward (%.2f, %.2f)" % [walked.x, walked.z])
	T.check(_near(P.noise_radius, Player.NOISE_WALK, 0.01), "walk noise radius %.1f" % P.noise_radius)
	T.check(P.animator.state == "locomotion", "animator is in 'locomotion' while walking (%s)" % P.animator.state)
	# run
	Input.action_press("move_forward", 1.0)
	await T.wait_seconds(1.5)
	var run := _planar_speed()
	T.check(_near(run, Player.RUN_SPEED, 0.15), "run speed %.2f m/s (want %.1f)" % [run, Player.RUN_SPEED])
	T.check(_near(P.noise_radius, Player.NOISE_RUN, 0.01), "run noise radius %.1f" % P.noise_radius)
	# sprint
	var stamina0 := P.stamina
	Input.action_press("sprint")
	await T.wait_seconds(1.6)
	var sprint := _planar_speed()
	T.check(_near(sprint, Player.SPRINT_SPEED, 0.2), "sprint speed %.2f m/s (want %.1f)" % [sprint, Player.SPRINT_SPEED])
	T.check(P.is_sprinting and P.stamina < stamina0 - 0.03, "sprinting drains stamina (%.2f -> %.2f)" % [stamina0, P.stamina])
	T.check(_near(P.noise_radius, Player.NOISE_SPRINT, 0.01), "sprint noise radius %.1f" % P.noise_radius)
	T.check(int(ev["noise"]) > 0, "footsteps emit EventBus.noise_emitted (%d so far)" % int(ev["noise"]))
	Input.action_release("sprint")
	# camera relative: look west (yaw +90 deg = left), forward must go to -X
	P.camera.yaw = PI * 0.5
	await T.wait_seconds(1.2)
	T.check(P.velocity.x < -3.8 and absf(P.velocity.z) < 0.6, "movement is camera relative (v = %.2f, %.2f)" % [P.velocity.x, P.velocity.z])
	T.check(absf(angle_difference(P.rotation.y, PI * 0.5)) < 0.15, "body turns smoothly into the direction of travel")
	# stop
	_release_all()
	await T.wait_seconds(0.5)
	T.check(_planar_speed() < 0.05, "stops quickly when the input is released (%.2f m/s)" % _planar_speed())
	var s1 := P.stamina
	await T.wait_seconds(2.0)
	T.check(P.stamina > s1, "stamina regenerates at rest (%.2f -> %.2f)" % [s1, P.stamina])
	T.check(P.animator.state == "idle", "animator is back in 'idle' (%s)" % P.animator.state)
	P.camera.yaw = 0.0


func _test_jump() -> void:
	await _place(Vector3(0.0, 0.0, 0.0), 0.0)
	var y0 := P.global_position.y
	var top := y0
	await get_tree().physics_frame
	Input.action_press("jump")
	var left_ground := false
	for i in 80:
		await get_tree().physics_frame
		if i == 3:
			Input.action_release("jump")
		top = maxf(top, P.global_position.y)
		if P.state_id == "air":
			left_ground = true
	var h := top - y0
	T.check(left_ground, "jump enters the air state")
	T.check(h > 1.0 and h < 1.25, "jump height %.2f m (want about %.1f)" % [h, Player.JUMP_HEIGHT])
	T.check(P.grounded and P.state_id == "on_foot" and absf(P.global_position.y - y0) < 0.03, "lands on the ground again")
	T.check(_near(P.health, P.max_health, 0.01), "a normal jump does no fall damage")


func _test_crouch() -> void:
	await _place(Vector3(0.0, 0.0, 0.0), 0.0)
	await _tap("crouch")
	await T.wait_physics_frames(5)
	var cap := (P.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	T.check(P.is_crouching and _near(cap.height, Player.CROUCH_HEIGHT, 0.001), "crouch toggles on, capsule height %.2f" % cap.height)
	Input.action_press("move_forward")
	await T.wait_seconds(1.2)
	var sp := _planar_speed()
	T.check(_near(sp, Player.CROUCH_SPEED, 0.15), "crouch speed %.2f m/s" % sp)
	T.check(_near(P.noise_radius, Player.NOISE_STEALTH, 0.01), "crouched noise radius %.1f" % P.noise_radius)
	T.check(P.animator.state == "crouch", "animator is in 'crouch' (%s)" % P.animator.state)
	Input.action_release("move_forward")
	await _tap("crouch")
	await T.wait_physics_frames(5)
	T.check(not P.is_crouching and _near(cap.height, Player.STAND_HEIGHT, 0.001), "crouch toggles off, capsule height %.2f" % cap.height)


func _test_stealth() -> void:
	await _place(Vector3(0.0, 0.0, 0.0), 0.0)
	if not InputMap.has_action("stealth"):
		skipped.append("stealth toggle (no 'stealth' input action)")
		return
	await _tap("stealth")
	T.check(P.in_stealth, "the stealth action toggles sneaking on")
	Input.action_press("move_forward")
	await T.wait_seconds(1.2)
	T.check(_near(_planar_speed(), Player.STEALTH_SPEED, 0.15), "sneak speed %.2f m/s" % _planar_speed())
	T.check(_near(P.noise_radius, Player.NOISE_STEALTH, 0.01), "sneaking is nearly silent (noise radius %.1f)" % P.noise_radius)
	Input.action_press("sprint")
	await T.wait_seconds(0.6)
	T.check(not P.in_stealth and P.is_sprinting, "sprinting ends the sneak")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await T.wait_seconds(0.4)
	await _tap("stealth")
	await _tap("stealth")
	T.check(not P.in_stealth, "the stealth action toggles sneaking off")


func _test_kerb() -> void:
	await _place(Arena.KERB_START, 0.0)
	var y0 := P.global_position.y
	Input.action_press("move_forward")
	var min_speed := 99.0
	var air_frames := 0
	for i in 130:
		await get_tree().physics_frame
		if i > 40:
			min_speed = minf(min_speed, _planar_speed())
		if P.state_id != "on_foot":
			air_frames += 1
	Input.action_release("move_forward")
	await T.wait_physics_frames(20)
	var rise := P.global_position.y - y0
	var z: float = P.global_position.z - arena.at(Arena.KERB_START).z
	T.check(_near(rise, Arena.KERB_HEIGHT, 0.03), "steps up a %.2f m kerb (rise %.3f)" % [Arena.KERB_HEIGHT, rise])
	T.check(z < -6.0, "keeps going across the kerb (z %.2f)" % z)
	T.check(min_speed > 3.3, "does not stall on the kerb (min speed %.2f m/s)" % min_speed)
	T.check(air_frames < 10, "stays in the on_foot state while stepping up (%d air frames)" % air_frames)


func _test_slope() -> void:
	_release_all()
	var spot: Vector3 = arena.ramp_point(5.0)
	P.teleport(spot + Vector3(0.0, 0.05, 0.0), 0.0)
	await T.wait_seconds(0.6)
	var p0 := P.global_position
	await T.wait_seconds(1.5)
	var drift := P.global_position.distance_to(p0)
	T.check(P.grounded and drift < 0.02, "does not slide on a %d degree slope (drift %.3f m)" % [int(Arena.RAMP_ANGLE_DEG), drift])
	Input.action_press("move_forward")
	await T.wait_seconds(1.2)
	var up := P.global_position.y - p0.y
	var sp := P.velocity.length()
	Input.action_release("move_forward")
	T.check(up > 0.8 and P.grounded, "walks up the slope (gained %.2f m)" % up)
	T.check(_near(sp, Player.RUN_SPEED, 0.35), "keeps its speed on the slope (%.2f m/s)" % sp)
	await T.wait_seconds(0.4)


func _test_damage() -> void:
	await _place(Vector3(0.0, 0.0, 0.0), 0.0)
	P.heal(1000.0)
	P.armor = 0.0
	var d0 := int(ev["damaged"])
	var h0 := int(ev["health"])
	P.add_armor(50.0)
	T.check(_near(P.armor, 50.0, 0.01), "add_armor adds armor")
	P.apply_damage(Dmg.make(30.0, "bullet", null, P.get_target_position(), Vector3(0, 0, -1)))
	T.check(_near(P.armor, 20.0, 0.01) and _near(P.health, 100.0, 0.01), "armor absorbs bullets first (armor %.0f hp %.0f)" % [P.armor, P.health])
	P.apply_damage(Dmg.make(40.0, "bullet", null, P.get_target_position(), Vector3(0, 0, -1)))
	T.check(_near(P.armor, 0.0, 0.01) and _near(P.health, 80.0, 0.01), "damage spills over to health when the armor is gone (armor %.0f hp %.0f)" % [P.armor, P.health])
	P.add_armor(30.0)
	P.apply_damage(Dmg.make(10.0, "melee", null, P.get_target_position(), Vector3(0, 0, -1)))
	T.check(_near(P.armor, 30.0, 0.01) and _near(P.health, 70.0, 0.01), "armor does not absorb melee (armor %.0f hp %.0f)" % [P.armor, P.health])
	Game.invulnerable = true
	P.apply_damage(Dmg.make(60.0, "bullet"))
	P.apply_damage(Dmg.make(60.0, "fall"))
	Game.invulnerable = false
	T.check(_near(P.armor, 30.0, 0.01) and _near(P.health, 70.0, 0.01), "Game.invulnerable blocks all damage")
	T.check(int(ev["damaged"]) - d0 == 3, "EventBus.player_damaged emitted per hit (%d)" % (int(ev["damaged"]) - d0))
	T.check(int(ev["health"]) - h0 >= 5, "EventBus.player_health_changed emitted (%d)" % (int(ev["health"]) - h0))
	P.heal(15.0)
	T.check(_near(P.health, 85.0, 0.01), "heal adds health")
	P.heal(1000.0)
	P.add_armor(1000.0)
	T.check(_near(P.health, P.max_health, 0.01) and _near(P.armor, P.max_armor, 0.01), "heal / add_armor clamp at the maximum")
	P.armor = 0.0
	await T.wait_physics_frames(30)


func _test_ragdoll() -> void:
	await _place(Vector3(0.0, 0.0, 0.0), 0.0)
	var start := P.global_position
	P.ragdoll(Vector3(260.0, 120.0, 0.0), 1.0)
	await T.wait_physics_frames(3)
	T.check(P.state_id == "ragdoll", "ragdoll(impulse, duration) enters the ragdoll state")
	var rag := P.get_active_ragdoll()
	T.check(rag != null and rag.bodies.size() == 11, "a physical ragdoll (11 segments) replaces the visual")
	if rag != null:
		T.check((rag.bodies[0].collision_layer & Layers.RAGDOLL) != 0, "ragdoll bodies are on Layers.RAGDOLL")
	T.check(P.visual != null and not P.visual.visible, "the animated visual is hidden while the ragdoll is active")
	T.check(Ragdoll.get_active_count() >= 1 and Ragdoll.get_active_count() <= Ragdoll.MAX_ACTIVE, "ragdoll count is tracked and capped")
	# one hit that both damages (knockdown) and calls knock_down() must be applied once
	T.check(P.is_same_impact(), "a second impulse right after the spawn counts as the same impact")
	await T.wait_seconds(0.7)
	T.check(not P.is_same_impact(), "the same-impact window is short (game time)")
	var moved := P.get_camera_focus().distance_to(start)
	T.check(moved > 0.25, "the impulse throws the ragdoll (%.2f m)" % moved)
	var rag_low := true
	if rag != null and is_instance_valid(rag):
		rag_low = rag.get_pelvis_position().y - start.y < 1.2
	T.check(rag_low, "the ragdoll falls to the ground (stable, no explosion)")
	var ok := await _wait_state("on_foot", 7.0)
	T.check(ok, "gets up again after the ragdoll (state %s)" % P.state_id)
	T.check(P.visual.visible and P.get_active_ragdoll() == null, "visual is shown again and the ragdoll is gone")
	T.check(P.grounded and absf(P.global_position.y - start.y) < 0.1, "stands on the ground where the ragdoll came to rest (dy %.2f)" % (P.global_position.y - start.y))
	T.check(P.global_position.distance_to(start) < 9.0, "stays in a sane range (%.2f m)" % P.global_position.distance_to(start))
	# NpcBase-compatible knock_down(impulse) (vehicles / knock-down weapons call it on any character)
	P.knock_down(Vector3(0.0, 120.0, 220.0))
	await T.wait_physics_frames(3)
	T.check(P.state_id == "ragdoll", "knock_down(impulse) ragdolls the player")
	ok = await _wait_state("on_foot", 7.0)
	T.check(ok, "gets up after knock_down (state %s)" % P.state_id)


func _test_fall() -> void:
	_release_all()
	P.heal(1000.0)
	# harmless drop
	P.teleport(arena.at(Vector3(0.0, 2.0, 0.0)), 0.0)
	await T.wait_seconds(1.0)
	T.check(_near(P.health, P.max_health, 0.01) and P.state_id == "on_foot", "a 2 m drop does no damage")
	# hard fall: 9 m -> about 19 m/s
	P.teleport(arena.at(Vector3(0.0, 9.0, 0.0)), 0.0)
	var saw_air := false
	var saw_ragdoll := false
	for i in 150:
		await get_tree().physics_frame
		if P.state_id == "air":
			saw_air = true
		if P.state_id == "ragdoll":
			saw_ragdoll = true
			break
	T.check(saw_air, "falling uses the air state")
	T.check(P.health < 70.0 and P.health > 30.0, "a 9 m fall hurts (hp %.0f)" % P.health)
	T.check(saw_ragdoll, "a very hard landing knocks the player down")
	var ok := await _wait_state("on_foot", 8.0)
	T.check(ok and not P.is_dead, "recovers after the hard landing")
	P.heal(1000.0)


func _test_swim() -> void:
	_release_all()
	var spot: Vector3 = arena.ensure_water()
	if not spot.is_finite():
		skipped.append("swimming (the world has no deep water where the test looks)")
		T.log_line("SKIP swimming: no deep water found")
		return
	var in0 := int(ev["water_in"])
	var out0 := int(ev["water_out"])
	P.teleport(spot, 0.0)
	await T.wait_seconds(2.5)
	T.check(P.state_id == "swim" and P.is_swimming, "deep water switches to the swim state (%s)" % P.state_id)
	T.check(int(ev["water_in"]) - in0 == 1, "EventBus.player_entered_water emitted")
	var depth := P.water_surface_y - P.global_position.y
	T.check(_near(depth, Player.FLOAT_DEPTH, 0.3), "floats at the surface (origin %.2f m under it)" % depth)
	T.check(not P.is_underwater, "head is above water while floating")
	T.check(P.animator.state == "tread", "animator treads water at rest (%s)" % P.animator.state)
	# surface swimming
	Input.action_press("move_forward")
	await T.wait_seconds(2.0)
	var sp := _planar_speed()
	T.check(_near(sp, Player.SWIM_SPEED, 0.25), "swim speed %.2f m/s" % sp)
	T.check(P.animator.state == "swim", "animator swims (%s)" % P.animator.state)
	Input.action_release("move_forward")
	# dive
	var on0 := int(ev["sub_on"])
	Input.action_press("crouch")
	await T.wait_seconds(2.5)
	T.check(P.is_underwater and int(ev["sub_on"]) - on0 == 1, "crouch dives: is_underwater + player_submerged(true)")
	T.check(P.breath < 0.97, "breath drains under water (%.2f)" % P.breath)
	T.check(P.animator.state == "dive", "animator dives (%s)" % P.animator.state)
	# scuba gear (pickup kind "scuba") makes the air last SCUBA_BREATH_MULT times longer
	var b0 := P.breath
	await T.wait_seconds(1.0)
	var plain_drop := b0 - P.breath
	P.give_scuba()
	b0 = P.breath
	await T.wait_seconds(1.0)
	var scuba_drop := b0 - P.breath
	P.has_scuba = false
	T.check(plain_drop > 0.0 and scuba_drop > 0.0 and scuba_drop < plain_drop * 0.2, "scuba gear slows the breath drain (%.4f -> %.4f per s)" % [plain_drop, scuba_drop])
	# drowning
	P.breath = 0.0
	var h0 := P.health
	await T.wait_seconds(2.3)
	T.check(P.health <= h0 - Player.DROWN_DAMAGE, "drowning damage without air (hp %.0f -> %.0f)" % [h0, P.health])
	Input.action_release("crouch")
	# surface again
	var off0 := int(ev["sub_off"])
	var deep := P.water_surface_y - P.global_position.y
	Input.action_press("jump")
	var rise_t := 0.0
	while P.is_underwater and rise_t < 12.0:
		await get_tree().physics_frame
		rise_t += 1.0 / 60.0
	await T.wait_seconds(0.5)
	Input.action_release("jump")
	T.log_line("surfaced from %.1f m in %.1f s" % [deep, rise_t])
	T.check(not P.is_underwater and int(ev["sub_off"]) - off0 == 1, "jump swims up: surfaces + player_submerged(false)")
	await T.wait_seconds(2.8)
	T.check(P.breath > 0.9, "breath comes back at the surface (%.2f)" % P.breath)
	var depth2 := P.water_surface_y - P.global_position.y
	T.check(_near(depth2, Player.FLOAT_DEPTH, 0.3), "settles at the floating line again (%.2f m)" % depth2)
	# out of the water
	await _place(Vector3(0.0, 0.0, 0.0), 0.0)
	T.check(not P.is_swimming and P.state_id == "on_foot", "leaves the swim state on land")
	T.check(int(ev["water_out"]) - out0 == 1, "EventBus.player_exited_water emitted")
	P.heal(1000.0)


func _test_death_respawn() -> void:
	await _place(Vector3(0.0, 0.0, 0.0), 0.0)
	var died0 := int(ev["died"])
	var resp0 := int(ev["respawned"])
	P.add_armor(40.0)
	P.kill("test")
	await T.wait_physics_frames(3)
	T.check(P.is_dead and _near(P.health, 0.0, 0.01) and P.state_id == "dead", "kill() -> dead state")
	T.check(int(ev["died"]) - died0 == 1, "EventBus.player_died emitted once")
	P.apply_damage(Dmg.make(50.0, "bullet"))
	T.check(int(ev["died"]) - died0 == 1, "damage on a dead player is ignored")
	Input.action_press("move_forward")
	await T.wait_seconds(0.5)
	Input.action_release("move_forward")
	T.check(P.velocity.length() < 0.01, "no control while dead")
	var where := Transform3D(Basis(Vector3.UP, 1.0), arena.at(Vector3(3.0, 0.05, 3.0)))
	P.respawn(where)
	await T.wait_physics_frames(20)
	T.check(not P.is_dead and _near(P.health, P.max_health, 0.01) and _near(P.armor, 0.0, 0.01), "respawn(xform) restores health, clears armor")
	T.check(P.state_id == "on_foot" and P.global_position.distance_to(where.origin) < 0.2 and _near(P.rotation.y, 1.0, 0.01), "respawn places the player at the transform")
	T.check(int(ev["respawned"]) - resp0 == 1, "EventBus.player_respawned emitted")
	T.check(P.visual.visible and P.get_active_ragdoll() == null, "death ragdoll is cleaned up on respawn")

	# built-in fallback (only when no 'respawn' system is registered)
	if Game.get_system("respawn") != null:
		skipped.append("fallback respawn (a respawn system is registered and owns it)")
		return
	Wanted.set_level(2)
	P.apply_damage(Dmg.make(500.0, "explosion", null, P.global_position, Vector3(1, 0, 0)))
	T.check(P.is_dead and int(ev["died"]) - died0 == 2, "lethal damage kills")
	await T.wait_seconds(Player.RESPAWN_DELAY - 1.0)
	T.check(P.is_dead, "still down before the respawn delay is over")
	await T.wait_seconds(1.6)
	var hospital := Game.get_location("hospital").origin
	T.check(not P.is_dead and int(ev["respawned"]) - resp0 == 2, "fallback respawn after about %.0f s" % Player.RESPAWN_DELAY)
	T.check(Vector2(P.global_position.x - hospital.x, P.global_position.z - hospital.z).length() < 3.0, "fallback respawn is at Game.get_location('hospital')")
	T.check(Wanted.level == 0, "fallback respawn clears the wanted level")


func _test_save() -> void:
	await _place(Vector3(5.0, 0.0, -2.0), 1.2)
	P.heal(1000.0)
	P.apply_damage(Dmg.make(25.0, "melee"))
	P.add_armor(35.0)
	var d: Dictionary = P.get_save_data()
	T.check(d.has("position") and d.has("yaw") and d.has("health") and d.has("armor") and d.has("appearance"), "get_save_data has position / yaw / health / armor / appearance")
	var saved_pos := P.global_position
	await _place(Vector3(-6.0, 0.0, 8.0), -2.0)
	P.heal(1000.0)
	P.armor = 0.0
	P.load_save_data(d)
	await T.wait_physics_frames(10)
	T.check(P.global_position.distance_to(saved_pos) < 0.1 and _near(P.rotation.y, 1.2, 0.01), "load_save_data restores position and yaw")
	T.check(_near(P.health, 75.0, 0.6) and _near(P.armor, 35.0, 0.01), "load_save_data restores health and armor (%.0f / %.0f)" % [P.health, P.armor])
	var json := JSON.stringify(d)
	T.check(json.length() > 10 and JSON.parse_string(json) is Dictionary, "save data is JSON friendly")
	P.heal(1000.0)
	P.armor = 0.0


func _test_input_lock() -> void:
	await _place(Vector3(0.0, 0.0, 0.0), 0.0)
	Game.lock_input()
	Input.action_press("move_forward")
	await T.wait_seconds(0.6)
	T.check(_planar_speed() < 0.05, "Game.lock_input() blocks player movement")
	Game.unlock_input()
	await T.wait_seconds(0.5)
	T.check(_planar_speed() > 3.0, "movement resumes after unlock_input()")
	P.set_control_enabled(false)
	await T.wait_seconds(0.6)
	T.check(_planar_speed() < 0.05, "set_control_enabled(false) stops the player")
	P.set_control_enabled(true)
	await T.wait_seconds(0.4)
	T.check(_planar_speed() > 3.0, "set_control_enabled(true) gives control back")
	_release_all()
	await T.wait_seconds(0.3)
