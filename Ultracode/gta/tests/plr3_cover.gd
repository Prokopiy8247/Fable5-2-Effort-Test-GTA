extends Node
## plr3_cover - headless test of the cover system (PlayerStateCover + player_cover.gd) with the REAL
## WeaponInventory / Combat and a real parked sedan:
##   low cover (1.1 m wall): enter (glide, back to the wall, crouched, low class), move along it, edge
##   stop, the shot line blocked while hunkered / clear when risen, aimed hits, blind fire over the
##   top (wider spread than aimed fire, no zoom, no aim), leaving by key / pull-away / sprint / vault;
##   high cover (2.5 m block): high class, edge stop, blocked when hunkered, lean out past the corner
##   (camera on the open side, line clear, target hit), back again, mid-wall aim keeps the trigger
##   up, blind fire round the corner, corner swing onto the end face; damage reduction from the
##   covered side; no cover in the open / behind a 0.6 m box; the camera never inside a collider
##   (yaw / pitch sweep at all three covers); the sedan as low cover and leaving when it moves;
##   soft REAL check: cover against the facades of real city buildings (city system).
##
##   tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 300 `
##       -UserArgs '--test=plr3_cover','--disable=traffic,peds,police','--test-timeout=240'

const Arena := preload("res://gta/tests/plr_arena.gd")
const Stage := preload("res://gta/tests/plr3_stage.gd")

var P: Player = null
var arena: Arena = null
var stage: Stage = null
var T: Node = null
var inv: Node = null
var shots: Array = []               # inventory "fired" results
var states_seen: Array = []


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
	inv = P.inventory
	if not T.check(inv != null and inv.has_method("give_weapon") and inv.has_signal("fired"), "real WeaponInventory present"):
		T.finish(false, "cover shooting needs the weapons module")
		return
	inv.call("give_weapon", "pistol", 300)
	inv.call("equip", "pistol")
	inv.set("infinite_ammo", true)
	inv.connect("fired", func(_id: String, result: Dictionary) -> void: shots.append(result))
	EventBus.player_state_changed.connect(func(s: String) -> void: states_seen.append(s))
	T.check(P.states.has("cover") and P.states["cover"] is PlayerStateCover, "cover state registered")
	await T.wait_physics_frames(30)
	await _test_no_cover()
	await _test_low()
	await _test_low_leave()
	await _test_high()
	await _test_damage()
	await _test_car()
	await _test_real_city()
	_release_all()
	T.finish(true, "cover")


# --- helpers ---------------------------------------------------------------------------------------

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "aim", "fire", "cover", "crouch"]:
		Input.action_release(a)


func _place(local: Vector3, yaw: float = 0.0) -> void:
	_release_all()
	P.teleport(arena.at(local) + Vector3(0.0, 0.03, 0.0), yaw)
	P.heal(1000.0)
	P.stamina = 1.0
	await T.wait_physics_frames(12)


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


func _cover() -> PlayerStateCover:
	return P.states["cover"] as PlayerStateCover


func _enter_cover(local: Vector3) -> bool:
	await _place(local, 0.0)
	await _tap("cover")
	return await _until(func() -> bool: return P.state_id == "cover" and _cover().phase == PlayerStateCover.Phase.COVER, 90)


## Turn the gameplay camera until its crosshair points at `world`.
func _look_at(world: Vector3) -> void:
	for i in 8:
		await T.wait_frames(2)
		var o := P.camera.get_aim_origin()
		var d := P.camera.get_aim_direction()
		var want := (world - o).normalized()
		P.camera.apply_look(angle_difference(atan2(-d.x, -d.z), atan2(-want.x, -want.z)), asin(clampf(want.y, -1.0, 1.0)) - asin(clampf(d.y, -1.0, 1.0)))
	await T.wait_frames(2)


## Where the inventory's bullets start (WeaponInventory._shoot_origin: the holder hook
## Player.get_shoot_origin when it answers, else the eye height of the body).
func _shoot_origin() -> Vector3:
	var so := P.get_shoot_origin()
	if so.is_finite():
		return so
	return P.global_position + Vector3.UP * (1.05 if P.is_crouching else 1.55)


## First thing a bullet from the shoot origin towards `to` would hit (collider or null).
func _first_hit(to: Vector3) -> Object:
	var from := _shoot_origin()
	var q := PhysicsRayQueryParameters3D.create(from, from + (to - from) * 1.2, Layers.BULLET_MASK, [P.get_rid()])
	var hit := P.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.get("collider", null) if not hit.is_empty() else null


## Presses fire n times (semi-auto pistol), returns the results of the shots that left the barrel.
func _fire_n(n: int, gap_frames: int = 22) -> Array:
	var before := shots.size()
	for i in n:
		Input.action_press("fire")
		await T.wait_physics_frames(3)
		Input.action_release("fire")
		await T.wait_physics_frames(gap_frames)
	return shots.slice(before)


## Mean angle (deg) between the shots' paths and the line from the shoot origin to `aim`.
func _mean_dev(results: Array, from: Vector3, aim: Vector3) -> float:
	if results.is_empty():
		return -1.0
	var want := (aim - from).normalized()
	var sum := 0.0
	for r: Dictionary in results:
		var e: Vector3 = r.get("end", aim)
		sum += rad_to_deg(want.angle_to((e - from).normalized()))
	return sum / float(results.size())


## The camera is never inside a collider (WORLD / VEHICLE / PROP) for a sweep of view directions.
func _camera_sweep(label: String) -> void:
	var space := P.get_world_3d().direct_space_state
	var pq := PhysicsPointQueryParameters3D.new()
	pq.collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.PROP
	var sq := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.06
	sq.shape = sph
	sq.collision_mask = pq.collision_mask
	var bad := 0
	var n := 0
	var worst := ""
	for pi in 3:
		for yi in 12:
			P.camera.yaw = wrapf(float(yi) * TAU / 12.0, -PI, PI)
			P.camera.pitch = [-0.55, -0.12, 0.45][pi]
			await T.wait_frames(3)
			var cp := P.camera.camera.global_position
			pq.position = cp
			sq.transform = Transform3D(Basis.IDENTITY, cp)
			n += 1
			if not space.intersect_point(pq, 1).is_empty() or not space.intersect_shape(sq, 1).is_empty():
				bad += 1
				worst = "yaw %d pitch %.2f" % [yi * 30, P.camera.pitch]
	T.check(bad == 0, "%s: camera never inside the cover or anything solid (%d / %d views clear%s)" % [label, n - bad, n, "" if bad == 0 else ", e.g. " + worst])
	P.camera.yaw = 0.0
	P.camera.pitch = -0.14
	await T.wait_frames(3)


# --- tests ----------------------------------------------------------------------------------------

func _test_no_cover() -> void:
	await _place(Stage.OPEN_SPOT, 0.0)
	await _tap("cover")
	await T.wait_physics_frames(6)
	T.check(P.state_id == "on_foot" and not P.in_cover, "no cover in the open: the cover key does nothing")
	await _place(Stage.KERB_LANE, 0.0)
	await _tap("cover")
	await T.wait_physics_frames(6)
	T.check(P.state_id == "on_foot", "a 0.6 m box is too low to be cover")


func _test_low() -> void:
	states_seen.clear()
	var ok := await _enter_cover(Stage.LOW_LANE)
	var st := _cover()
	T.check(ok, "low wall: the cover key glides into cover")
	T.check(states_seen.has("cover"), "EventBus.player_state_changed('cover')")
	T.check(P.in_cover and st.low, "1.1 m wall classified as LOW cover (height %.2f)" % st.cover_height)
	T.check(st.cover_height > 0.95 and st.cover_height < 1.25, "low cover top measured ~1.1 m (%.2f)" % st.cover_height)
	var face_z := arena.at(Vector3(0.0, 0.0, Stage.FACE_Z)).z
	var gap := P.global_position.z - face_z
	T.check(absf(gap - 0.41) < 0.08, "stands 0.41 m in front of the face (%.3f)" % gap)
	var fwd := -P.global_basis.z
	T.check(fwd.dot(Vector3.BACK) > 0.95, "back to the wall (facing away from it, dot %.2f)" % fwd.dot(Vector3.BACK))
	T.check(P.is_crouching, "crouched behind low cover")
	await T.wait_frames(4)
	T.check(P.animator != null and P.animator.state == "cover_low", "animator state cover_low (%s)" % (P.animator.state if P.animator != null else "?"))

	# move along the wall (camera looks at the wall: right = +X)
	var x0 := P.global_position.x
	Input.action_press("move_right")
	await T.wait_physics_frames(45)
	var moved := P.global_position.x - x0
	T.check(moved > 0.6 and P.state_id == "cover", "moves right along the wall (%.2f m in 0.75 s)" % moved)
	T.check(absf(P.global_position.z - face_z - 0.41) < 0.08, "keeps the distance to the face while moving (%.3f)" % (P.global_position.z - face_z))
	await _until(func() -> bool: return st.edge_pos, 200)
	await T.wait_physics_frames(40)
	Input.action_release("move_right")
	var edge_x := arena.at(Vector3(Stage.LOW_HALF_WIDTH, 0.0, 0.0)).x
	var inside := edge_x - P.global_position.x
	T.check(st.edge_pos and P.state_id == "cover", "edge detected, still in cover")
	T.check(inside > 0.08 and inside < 0.32, "stops at the edge with the body still covered (%.2f m inside)" % inside)
	await _camera_sweep("low wall")
	# back to the middle for the shooting tests
	Input.action_press("move_left")
	await _until(func() -> bool: return P.global_position.x < arena.at(Vector3(0.3, 0.0, 0.0)).x, 200)
	Input.action_release("move_left")
	await T.wait_physics_frames(10)

	# hunkered: the shot line ends in the wall; risen: it reaches the target
	var target := stage.low_target
	var hit_hunkered := _first_hit(target.chest())
	T.check(hit_hunkered == stage.low_wall, "hunkered behind low cover: the shot line is blocked by the wall")
	await _look_at(target.chest())
	Input.action_press("aim")
	var risen := await _until(func() -> bool: return st.peek >= 0.95, 40)
	await _look_at(target.chest())
	T.check(risen and not P.is_crouching and P.is_aiming, "aim rises over low cover (peek %.2f, standing, aiming)" % st.peek)
	T.check(_first_hit(target.chest()) == target, "risen: the shot line clears the wall and reaches the target")
	await T.wait_frames(2)
	T.check(P.animator.state == "cover_low" and P.animator.aim_weight > 0.9, "animator keeps cover_low with the aim overlay")
	var h0 := target.hits.size()
	var aimed := await _fire_n(8)
	T.check(aimed.size() >= 7, "fire while aimed from cover (%d shots)" % aimed.size())
	T.check(target.hits.size() - h0 >= 6, "aimed shots hit the target over the wall (%d / %d)" % [target.hits.size() - h0, aimed.size()])
	var aim_pt := target.chest()
	var dev_aimed := _mean_dev(aimed, _shoot_origin(), aim_pt)
	Input.action_release("aim")
	await _until(func() -> bool: return P.is_crouching and st.peek < 0.05, 40)
	T.check(P.is_crouching and not P.is_aiming, "releasing aim ducks back down")

	# blind fire over the top: no aim, no zoom, wide spread, the shots clear the wall
	await _look_at(aim_pt)
	var fov_before := P.camera.camera.fov
	var blind_results := []
	var aiming_seen := false
	var min_fov := 999.0
	for i in 10:
		Input.action_press("fire")
		for f in 4:
			await get_tree().physics_frame
			aiming_seen = aiming_seen or P.is_aiming
			min_fov = minf(min_fov, P.camera.camera.fov)
		if i == 4:
			T.check(st.blind_firing and P.animator.cover_blind > 0.3, "blind fire pose (cover_blind %.2f)" % P.animator.cover_blind)
			var cap := P.get("_capsule") as CapsuleShape3D
			var so_y := P.get_shoot_origin().y - P.global_position.y
			T.check(P.is_crouching and so_y > 1.5 and cap != null and cap.height < Player.STAND_HEIGHT - 0.3, "blind fire: shots leave above the wall (shoot origin %.2f m, get_shoot_origin hook) while the body stays crouched (capsule %.2f m)" % [so_y, cap.height if cap != null else -1.0])
		Input.action_release("fire")
		await T.wait_physics_frames(18)
	blind_results = shots.slice(shots.size() - mini(shots.size(), 10))
	await T.wait_physics_frames(40)
	T.check(not aiming_seen, "blind fire never aims")
	T.check(min_fov > fov_before - 3.0, "blind fire does not zoom (fov %.1f -> min %.1f)" % [fov_before, min_fov])
	var past := 0
	for r: Dictionary in blind_results:
		var e: Vector3 = r.get("end", Vector3.ZERO)
		if e.z < face_z - 0.4:
			past += 1
	T.check(blind_results.size() >= 8 and past >= blind_results.size() - 1, "blind shots go over the wall (%d / %d past it)" % [past, blind_results.size()])
	var dev_blind := _mean_dev(blind_results, P.global_position + Vector3.UP * 1.55, aim_pt)
	T.check(dev_blind > dev_aimed * 2.0 and dev_blind > 2.0, "blind fire spread %.2f deg >> aimed %.2f deg" % [dev_blind, dev_aimed])
	T.check(P.is_crouching and not st.blind_firing and not P.get_shoot_origin().is_finite(), "blind pose released (crouched, shoot origin back to the inventory's default)")


func _test_low_leave() -> void:
	var st := _cover()
	# leave by pressing cover again
	await _enter_cover(Stage.LOW_LANE)
	await _tap("cover")
	await T.wait_physics_frames(4)
	T.check(P.state_id == "on_foot" and not P.in_cover and not P.is_crouching, "cover key again: leaves cover and stands up")
	# pull away from the wall
	await _enter_cover(Stage.LOW_LANE)
	Input.action_press("move_back")
	await _until(func() -> bool: return P.state_id != "cover", 40)
	Input.action_release("move_back")
	T.check(P.state_id == "on_foot" and st.leave_reason == "pull_away", "pulling away leaves cover (%s)" % st.leave_reason)
	# sprint
	await _enter_cover(Stage.LOW_LANE)
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _until(func() -> bool: return P.state_id != "cover", 40)
	await T.wait_physics_frames(20)
	T.check(st.leave_reason == "sprint" and P.is_sprinting, "sprinting leaves cover and sprints (%s)" % st.leave_reason)
	Input.action_release("sprint")
	Input.action_release("move_right")
	# vault over the low cover
	await _enter_cover(Stage.LOW_LANE)
	await _tap("jump")
	var vaulted := await _until(func() -> bool: return P.state_id == "vault", 10)
	T.check(vaulted, "jump in low cover vaults over it")
	await _until(func() -> bool: return P.state_id == "on_foot" or P.state_id == "air", 120)
	await T.wait_physics_frames(20)
	var face_z := arena.at(Vector3(0.0, 0.0, Stage.FACE_Z)).z
	T.check(P.global_position.z < face_z - 0.5, "landed on the far side of the wall (%.2f m past the face)" % (face_z - P.global_position.z))


func _test_high() -> void:
	var ok := await _enter_cover(Stage.HIGH_LANE)
	var st := _cover()
	T.check(ok and not st.low, "2.5 m block classified as HIGH cover (height %.2f)" % st.cover_height)
	T.check(not P.is_crouching, "standing in high cover")
	await T.wait_frames(4)
	T.check(P.animator.state == "cover_high", "animator state cover_high")
	await _camera_sweep("high block")
	# edge on the right (+X)
	Input.action_press("move_right")
	await _until(func() -> bool: return st.edge_pos, 200)
	await T.wait_physics_frames(30)
	Input.action_release("move_right")
	await T.wait_physics_frames(10)
	var edge_x := arena.at(Vector3(Stage.HIGH_X1, 0.0, 0.0)).x
	var inside := edge_x - P.global_position.x
	T.check(st.edge_pos and st.near_pos and P.state_id == "cover", "high cover: right edge detected")
	T.check(inside > 0.08 and inside < 0.32, "stops %.2f m inside the corner" % inside)
	var target := stage.high_target
	T.check(_first_hit(target.chest()) == stage.high_block, "not peeking: the shot line is blocked by the corner")
	# lean out past the corner
	await _look_at(target.chest())
	Input.action_press("aim")
	var leaned := await _until(func() -> bool: return st.peek >= 0.95, 60)
	await _look_at(target.chest())
	var past := P.global_position.x - edge_x
	T.check(leaned and st.peek_kind == PlayerStateCover.Peek.LEAN, "aim at the edge leans out (peek %.2f)" % st.peek)
	T.check(past > 0.3 and past < 0.6, "the body is %.2f m past the corner" % past)
	var cam_x := P.camera.camera.global_position.x
	T.check(cam_x > edge_x + 0.2, "camera on the open side of the corner (%.2f m past it)" % (cam_x - edge_x))
	T.check(_first_hit(target.chest()) == target, "peeking: the shot line clears the corner")
	var h0 := target.hits.size()
	var res := await _fire_n(4)
	T.check(res.size() >= 3 and target.hits.size() - h0 >= 3, "shots from the peek hit the target (%d / %d)" % [target.hits.size() - h0, res.size()])
	Input.action_release("aim")
	await _until(func() -> bool: return st.peek < 0.05 and absf(P.global_position.x - (edge_x - inside)) < 0.06, 60)
	T.check(absf(P.global_position.x - (edge_x - inside)) < 0.08 and P.state_id == "cover", "releasing aim slides back behind the corner")
	await _camera_sweep("high block edge")
	# blind fire round the corner
	await _look_at(target.chest())
	var b0 := shots.size()
	var max_past := -1.0
	var aimed_seen := false
	for i in 5:
		Input.action_press("fire")
		for f in 8:
			await get_tree().physics_frame
			max_past = maxf(max_past, P.global_position.x - edge_x)
			aimed_seen = aimed_seen or P.is_aiming
		Input.action_release("fire")
		await T.wait_physics_frames(14)
	T.check(shots.size() - b0 >= 4 and not aimed_seen, "blind fire round the corner without aiming (%d shots)" % (shots.size() - b0))
	T.check(max_past > 0.0 and max_past < 0.3, "blind fire: the body slides just to the corner (%.2f m past)" % max_past)
	await T.wait_physics_frames(50)
	# mid-wall: aiming holds the trigger up (nothing to shoot round)
	Input.action_press("move_left")
	await _until(func() -> bool: return P.global_position.x < arena.at(Vector3(9.5, 0.0, 0.0)).x, 200)
	Input.action_release("move_left")
	await T.wait_physics_frames(10)
	Input.action_press("aim")
	await T.wait_physics_frames(12)
	var m0 := shots.size()
	await _fire_n(2)
	T.check(st.peek_kind == PlayerStateCover.Peek.IN_PLACE and shots.size() == m0, "mid-wall in high cover: aim held, no shot into the wall")
	Input.action_release("aim")
	await T.wait_physics_frames(10)
	# swing round the outside corner onto the end face (normal +X)
	Input.action_press("move_right")
	await _until(func() -> bool: return st.edge_pos, 200)
	await T.wait_physics_frames(10)
	await _tap("cover")
	var swung := await _until(func() -> bool: return st.phase == PlayerStateCover.Phase.SWING, 6)
	await _until(func() -> bool: return st.phase == PlayerStateCover.Phase.COVER, 60)
	Input.action_release("move_right")
	await T.wait_physics_frames(10)
	T.check(swung and P.state_id == "cover", "corner swing at the outside corner")
	T.check(st.normal.dot(Vector3.RIGHT) > 0.9, "now in cover on the end face (normal %s)" % str(st.normal))
	var off := P.global_position.x - edge_x
	var along := arena.at(Vector3(0.0, 0.0, Stage.FACE_Z)).z - P.global_position.z
	T.check(absf(off - 0.41) < 0.1 and along > 0.05 and along < 0.6, "stands beside the end face (%.2f m off, %.2f m along)" % [off, along])
	await _tap("cover")
	await T.wait_physics_frames(4)
	T.check(P.state_id == "on_foot", "left high cover")


func _test_damage() -> void:
	await _enter_cover(Stage.LOW_LANE)
	P.armor = 0.0
	P.health = 100.0
	# a bullet from beyond the wall travels towards +Z
	P.apply_damage(Dmg.make(20.0, "bullet", null, P.get_target_position(), Vector3(0.0, 0.0, 1.0)))
	var covered := 100.0 - P.health
	P.health = 100.0
	P.apply_damage(Dmg.make(20.0, "bullet", null, P.get_target_position(), Vector3(0.0, 0.0, -1.0)))
	var open := 100.0 - P.health
	T.check(covered > 0.0 and covered < 8.0 and absf(open - 20.0) < 0.01, "cover damage: %.1f hp from the covered side, %.1f from the open side" % [covered, open])
	P.heal(1000.0)
	await _tap("cover")
	await T.wait_physics_frames(4)


func _test_car() -> void:
	var car := Game.spawn_vehicle("sedan", Transform3D(Basis(Vector3.UP, PI * 0.5), arena.at(Stage.CAR_SPOT) + Vector3(0.0, 0.5, 0.0)), {"owner_tag": "parked"})
	if not T.check(car != null, "sedan spawned for the vehicle cover test"):
		return
	await T.wait_physics_frames(90)
	var ok := await _enter_cover(Stage.CAR_LANE)
	var st := _cover()
	T.check(ok and st.cover_vehicle == car, "parked sedan used as cover")
	T.check(st.low, "a car body is LOW cover (height %.2f)" % st.cover_height)
	await _camera_sweep("sedan")
	# rise over the car
	Input.action_press("aim")
	var risen := await _until(func() -> bool: return st.peek >= 0.95, 40)
	T.check(risen and not P.is_crouching, "rises over the car to aim")
	Input.action_release("aim")
	await T.wait_physics_frames(20)
	# the car starts rolling: cover is lost
	if car is RigidBody3D:
		var rb := car as RigidBody3D
		rb.freeze = false
		rb.sleeping = false
		rb.apply_central_impulse(Vector3(1.0, 0.0, 0.0) * rb.mass * 3.0)
	var left := await _until(func() -> bool: return P.state_id != "cover", 30)
	T.check(left and st.leave_reason == "vehicle_moved", "the moving car throws the player out of cover (%s)" % st.leave_reason)
	car.queue_free()
	await T.wait_physics_frames(5)


## Soft check on real game content: walk up to the facades of real city buildings and take cover.
func _test_real_city() -> void:
	var city := Game.get_system("city")
	if city == null or not city.has_method("get_buildings"):
		T.log_line("SKIP real city cover: no city system")
		return
	var list: Variant = city.call("get_buildings")
	if not (list is Array) or (list as Array).is_empty():
		T.log_line("SKIP real city cover: no buildings")
		return
	var space := P.get_world_3d().direct_space_state
	var tried := 0
	var ok := 0
	var high := 0
	var cam_ok := true
	for b: Variant in list:
		if tried >= 14 or ok >= 4:
			break
		if not (b is Dictionary):
			continue
		var d := b as Dictionary
		var cat := str(d.get("category", ""))
		if cat == "landmark" or cat == "parking":
			continue
		var xf: Transform3D = d.get("transform", Transform3D.IDENTITY)
		var fp: Vector2 = d.get("footprint", Vector2.ZERO)
		if fp.y < 4.0:
			continue
		var fwd := -xf.basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 0.01:
			continue
		fwd = fwd.normalized()
		var p := xf.origin + fwd * (fp.y * 0.5 + 1.4)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0.0, 6.0, 0.0), p - Vector3(0.0, 6.0, 0.0), Layers.WORLD)
		var g := space.intersect_ray(q)
		if g.is_empty():
			continue
		tried += 1
		P.teleport((g["position"] as Vector3) + Vector3(0.0, 0.05, 0.0), atan2(fwd.x, fwd.z))
		await T.wait_physics_frames(12)
		await _tap("cover")
		var got := await _until(func() -> bool: return P.state_id == "cover" and _cover().phase == PlayerStateCover.Phase.COVER, 70)
		if got:
			ok += 1
			if not _cover().low:
				high += 1
			await T.wait_frames(6)
			var pq := PhysicsPointQueryParameters3D.new()
			pq.position = P.camera.camera.global_position
			pq.collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.PROP
			if not space.intersect_point(pq, 1).is_empty():
				cam_ok = false
			T.log_line("real cover at %s (%s): %s, height %.2f" % [str(d.get("id", "?")), cat, "low" if _cover().low else "high", _cover().cover_height])
			await _tap("cover")
			await T.wait_physics_frames(4)
		_release_all()
	T.check(tried == 0 or (ok >= 1 and cam_ok), "REAL city: took cover at %d of %d building facades (%d high), camera clear" % [ok, tried, high])
