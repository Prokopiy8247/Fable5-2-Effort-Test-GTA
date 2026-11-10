extends Node
## Two-wheeler test on a code-built flat proving ground (no world).
##   tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 300 -UserArgs '--test=bkb_bike','--test-timeout=280',
##       '--disable=world,environment,city,interactions,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Checks: motorcycle + bicycle stand upright at rest; top speed / 0-100; braking; lean + turn in the
## commanded direction both ways; crossing a 0.15 m kerb; a head-on wall crash throws the player
## (ragdoll) and drops the bike, which stands up again when remounted; the bicycle is slower,
## its sprint is faster and drains the rider's stamina.

const DT := 1.0 / 60.0
const KERB_X := -105.0
const KERB_Z0 := -30.0
const KERB_Z1 := -24.0
const WALL_X := 100.0
const WALL_Z := 10.0

var _vm: Node = null
var _rows: Array[String] = []


func _ready() -> void:
	Game.invulnerable = true
	_build_ground()
	_vm = Game.get_system("vehicles")
	if _vm == null:
		TestHarness.check(false, "vehicles system present")
		TestHarness.finish(false, "no vehicles system")
		return
	_vm.set("detail_override", 0)
	var pl := Game.player
	if pl != null and pl.has_method("teleport"):
		pl.call("teleport", Vector3(140.0, 0.05, 150.0), 0.0)
	await TestHarness.wait_physics_frames(10)
	await _run()


func _run() -> void:
	var moto := _spawn("motorcycle", Vector3(-10.0, 0.0, 150.0))
	var bici := _spawn("bicycle", Vector3(30.0, 0.0, 150.0))
	if not TestHarness.check(moto != null and bici != null, "motorcycle and bicycle spawn (spec + GLB + class)"):
		TestHarness.finish(false, "spawn failed")
		return
	TestHarness.check(moto is Bike and bici is Bike, "both use the Bike class")
	TestHarness.check(str(moto.get("vehicle_class")) == "bike" and str(bici.get("vehicle_class")) == "bicycle", "vehicle classes bike / bicycle")
	TestHarness.check(moto.get_wheel_count() == 2 and bici.get_wheel_count() == 2, "two wheels each")

	# --- 1. rest: stands upright on its own, no creep
	var p0m := moto.global_position
	var p0b := bici.global_position
	await TestHarness.wait_seconds(3.0)
	for v: Bike in [moto, bici]:
		var p0 := p0m if v == moto else p0b
		var up := v.global_transform.basis.y.y
		var drift := Vector2(v.global_position.x - p0.x, v.global_position.z - p0.z).length()
		TestHarness.check(up > 0.995, "%s stands upright at rest (up.y %.4f)" % [v.spec_id, up])
		TestHarness.check(drift < 0.05, "%s does not creep at rest (%.3f m)" % [v.spec_id, drift])
		TestHarness.check(absf(v.global_position.y) < 0.06, "%s sits on its wheels (origin y %.3f)" % [v.spec_id, v.global_position.y])
		TestHarness.check(not v.fallen, "%s not fallen at rest" % v.spec_id)
	_rows.append("rest: moto sleeping=%s bici sleeping=%s" % [moto.sleeping, bici.sleeping])

	# --- 2. top speed side by side (bicycle: normal pedalling, then sprint)
	moto.set_inputs(1.0, 0.0, 0.0)
	bici.set_inputs(1.0, 0.0, 0.0)
	var t := 0.0
	var t100 := -1.0
	var vmax_m := 0.0
	var vmax_b := 0.0
	var min_up := 1.0
	while t < 20.0:
		await get_tree().physics_frame
		t += DT
		var sm := moto.get_forward_speed()
		vmax_m = maxf(vmax_m, sm)
		if t100 < 0.0 and sm >= 27.78:
			t100 = t
		vmax_b = maxf(vmax_b, bici.get_forward_speed())
		min_up = minf(min_up, minf(moto.global_transform.basis.y.y, bici.global_transform.basis.y.y))
	var bici_cruise := bici.get_forward_speed()
	bici.sprinting = true
	var vmax_sprint := 0.0
	t = 0.0
	while t < 8.0:
		await get_tree().physics_frame
		t += DT
		vmax_sprint = maxf(vmax_sprint, bici.get_forward_speed())
	var kmh_m := vmax_m * 3.6
	_rows.append("motorcycle: 0-100 %.2f s, top %.1f km/h | bicycle cruise %.1f km/h, sprint %.1f km/h" % [t100, kmh_m, bici_cruise * 3.6, vmax_sprint * 3.6])
	TestHarness.check(kmh_m > 150.0 and kmh_m < 205.0, "motorcycle top speed plausible (%.1f km/h)" % kmh_m)
	TestHarness.check(t100 > 0.0 and t100 < 6.5, "motorcycle 0-100 km/h in %.2f s" % t100)
	TestHarness.check(bici_cruise * 3.6 > 22.0 and bici_cruise * 3.6 < 36.0, "bicycle pedalling speed %.1f km/h" % (bici_cruise * 3.6))
	TestHarness.check(vmax_sprint > bici_cruise + 0.8, "bicycle sprint is faster (%.1f > %.1f km/h)" % [vmax_sprint * 3.6, bici_cruise * 3.6])
	TestHarness.check(vmax_b < vmax_m * 0.35, "bicycle much slower than the motorcycle")
	TestHarness.check(min_up > 0.98 and not moto.fallen and not bici.fallen, "upright through the speed run (min up.y %.3f)" % min_up)

	# --- 3. braking from top speed
	var v0 := moto.get_forward_speed()
	var z0 := moto.global_position.z
	moto.set_inputs(0.0, 0.0, 1.0)
	t = 0.0
	while t < 12.0 and moto.get_forward_speed() > 0.3:
		await get_tree().physics_frame
		t += DT
	var dist := absf(moto.global_position.z - z0)
	var decel := v0 / maxf(t, 0.01)
	_rows.append("braking: %.1f km/h -> 0 in %.2f s, %.1f m (%.1f m/s^2)" % [v0 * 3.6, t, dist, decel])
	TestHarness.check(decel > 6.5, "motorcycle brakes hard (%.1f m/s^2)" % decel)
	TestHarness.check(not moto.fallen and moto.global_transform.basis.y.y > 0.98, "upright after a full stop from top speed")
	moto.set_inputs(0.0, 0.0, 0.0)
	bici.set_inputs(0.0, 0.0, 1.0)

	# --- 4. lean and turn in the commanded direction (both ways)
	moto.teleport(Transform3D(Basis.IDENTITY, Vector3(-40.0, 0.02, 150.0)))
	await TestHarness.wait_physics_frames(20)
	moto.set_inputs(0.6, 0.0, 0.0)
	t = 0.0
	while t < 6.0 and moto.get_forward_speed() < 15.0:
		await get_tree().physics_frame
		t += DT
	var res_r := await _turn(moto, 0.7, 1.6)
	var res_l := await _turn(moto, -0.7, 3.0)
	_rows.append("turn right: yaw %.1f deg, lean %.1f deg, speed %.1f | left: yaw %.1f deg, lean %.1f deg" % [res_r[0], res_r[1], res_r[2], res_l[0], res_l[1]])
	TestHarness.check(res_r[0] < -20.0, "steer right turns right (yaw %.1f deg)" % res_r[0])
	TestHarness.check(res_r[1] > 12.0, "leans right into a right turn (%.1f deg)" % res_r[1])
	TestHarness.check(res_l[0] > 20.0, "steer left turns left (yaw %.1f deg)" % res_l[0])
	TestHarness.check(res_l[1] < -12.0, "leans left into a left turn (%.1f deg)" % res_l[1])
	TestHarness.check(not moto.fallen and moto.global_transform.basis.y.y > 0.97, "no crash in normal turns")
	moto.set_inputs(0.0, 0.0, 1.0)
	await TestHarness.wait_seconds(2.5)

	# --- 5. kerb: up and down a 0.15 m step at ~8 m/s
	moto.teleport(Transform3D(Basis.IDENTITY, Vector3(KERB_X, 0.02, 20.0)))
	await TestHarness.wait_physics_frames(20)
	moto.set_inputs(0.5, 0.0, 0.0)
	t = 0.0
	var kerb_min_up := 1.0
	var kerb_speed := 0.0
	while t < 12.0 and moto.global_position.z > KERB_Z0 - 25.0:
		await get_tree().physics_frame
		t += DT
		var sp := moto.get_forward_speed()
		if sp > 8.0:
			moto.set_inputs(0.0, 0.0, 0.0)
		elif sp < 7.0:
			moto.set_inputs(0.5, 0.0, 0.0)
		if moto.global_position.z < KERB_Z1 + 3.0 and moto.global_position.z > KERB_Z0 - 3.0:
			kerb_min_up = minf(kerb_min_up, moto.global_transform.basis.y.y)
			kerb_speed = maxf(kerb_speed, sp)
	_rows.append("kerb: crossed at %.1f m/s, min up.y %.3f, fallen=%s" % [kerb_speed, kerb_min_up, moto.fallen])
	TestHarness.check(moto.global_position.z < KERB_Z0 - 20.0, "crossed the kerb platform (z %.1f)" % moto.global_position.z)
	TestHarness.check(not moto.fallen and kerb_min_up > 0.95, "kerb up and down without falling (min up.y %.3f)" % kerb_min_up)
	moto.set_inputs(0.0, 0.0, 1.0)
	await TestHarness.wait_seconds(1.5)
	moto.release_inputs()

	# --- 5b. lowside: locking the rear and throwing it into a turn at speed ends on the ground
	moto.teleport(Transform3D(Basis.IDENTITY, Vector3(-60.0, 0.02, 150.0)))
	await TestHarness.wait_physics_frames(20)
	moto.set_inputs(1.0, 0.0, 0.0)
	t = 0.0
	while t < 8.0 and moto.get_forward_speed() < 20.0:
		await get_tree().physics_frame
		t += DT
	moto.set_inputs(0.0, 1.0, 0.0, true)
	t = 0.0
	while t < 4.0 and not moto.fallen:
		await get_tree().physics_frame
		t += DT
	_rows.append("lowside: handbrake + full lock at 20 m/s -> fallen=%s reason=%s after %.2f s" % [moto.fallen, moto.last_crash_reason, t])
	TestHarness.check(moto.fallen and moto.last_crash_reason == "lowside", "locked-rear slide at speed ends in a lowside (%s)" % moto.last_crash_reason)
	moto.release_inputs()
	await TestHarness.wait_seconds(3.0)
	TestHarness.check(moto.sleeping or moto.linear_velocity.length() < 0.3, "fallen bike comes to rest")
	moto.repair()
	await TestHarness.wait_seconds(1.5)
	TestHarness.check(not moto.fallen and moto.global_transform.basis.y.y > 0.97, "repair() stands a fallen bike up")

	# --- 6. head-on crash with the player riding: rider thrown, bike falls, remount stands it up
	await _crash_test(moto)

	# --- 7. bicycle with the player: sprint drains stamina
	await _sprint_test(bici)

	for r: String in _rows:
		print("BKB_TABLE: ", r)
	TestHarness.finish()


func _turn(v: Bike, steer: float, seconds: float) -> Array:
	var yaw0 := _yaw(v)
	var acc := 0.0
	var prev := yaw0
	var lean_peak := 0.0
	var t := 0.0
	while t < seconds:
		var sp := v.get_forward_speed()
		v.set_inputs(0.45 if sp < 15.0 else 0.25, steer, 0.0)
		await get_tree().physics_frame
		t += DT
		var y := _yaw(v)
		acc += angle_difference(prev, y)
		prev = y
		var l := v.get_lean_degrees()
		if absf(l) > absf(lean_peak):
			lean_peak = l
	return [rad_to_deg(acc), lean_peak, v.get_forward_speed()]


func _crash_test(moto: Bike) -> void:
	var pl := Game.player
	if pl == null or not pl.has_method("enter_vehicle"):
		TestHarness.check(false, "player present for the crash test")
		return
	moto.teleport(Transform3D(Basis.IDENTITY, Vector3(WALL_X, 0.02, WALL_Z + 50.0)))
	await TestHarness.wait_physics_frames(10)
	pl.call("enter_vehicle", moto, 0, true)
	await TestHarness.wait_physics_frames(5)
	TestHarness.check(pl.get("current_vehicle") == moto and moto.driver == pl and moto.is_player_driven, "player rides the motorcycle")
	TestHarness.check(moto.engine_on, "engine running with the player aboard")
	Input.action_press("move_forward")
	var t := 0.0
	var v_hit := 0.0
	while t < 8.0 and not moto.fallen:
		await get_tree().physics_frame
		t += DT
		v_hit = maxf(v_hit, moto.get_forward_speed())
	Input.action_release("move_forward")
	await TestHarness.wait_physics_frames(3)
	var st := str(pl.get("state_id"))
	_rows.append("crash: wall at %.1f m/s (%.0f km/h) -> fallen=%s reason=%s player state=%s" % [v_hit, v_hit * 3.6, moto.fallen, moto.last_crash_reason, st])
	TestHarness.check(v_hit > 12.0, "hit the wall fast (%.1f m/s)" % v_hit)
	TestHarness.check(moto.fallen and moto.last_crash_reason == "crash", "head-on impact drops the bike (reason %s)" % moto.last_crash_reason)
	TestHarness.check(pl.get("current_vehicle") == null and moto.driver == null, "rider thrown off")
	TestHarness.check(st == "ragdoll", "player ragdolls (state %s)" % st)
	await TestHarness.wait_seconds(3.0)
	TestHarness.check(moto.global_transform.basis.y.y < 0.6, "bike lies on its side (up.y %.2f)" % moto.global_transform.basis.y.y)
	TestHarness.check(moto.can_enter(pl), "fallen bike can be mounted")
	# wait until the player stood up, then remount
	t = 0.0
	while t < 6.0 and str(pl.get("state_id")) != "on_foot":
		await get_tree().physics_frame
		t += DT
	pl.call("enter_vehicle", moto, 0, false)
	await TestHarness.wait_seconds(2.5)
	TestHarness.check(pl.get("current_vehicle") == moto, "player remounted the fallen bike (state %s)" % str(pl.get("state_id")))
	TestHarness.check(not moto.fallen and moto.global_transform.basis.y.y > 0.97, "bike stood up again (up.y %.3f)" % moto.global_transform.basis.y.y)
	pl.call("exit_vehicle")
	await TestHarness.wait_seconds(2.0)
	TestHarness.check(pl.get("current_vehicle") == null, "player got off")
	TestHarness.check(not moto.fallen and moto.global_transform.basis.y.y > 0.99, "parked bike keeps standing after the rider leaves")


func _sprint_test(bici: Bike) -> void:
	var pl := Game.player
	if pl == null:
		return
	bici.teleport(Transform3D(Basis.IDENTITY, Vector3(-80.0, 0.02, 150.0)))
	await TestHarness.wait_physics_frames(10)
	pl.call("enter_vehicle", bici, 0, true)
	await TestHarness.wait_physics_frames(5)
	TestHarness.check(pl.get("current_vehicle") == bici, "player on the bicycle")
	var st0 := float(pl.get("stamina"))
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var t := 0.0
	var vmax := 0.0
	while t < 10.0:
		await get_tree().physics_frame
		t += DT
		vmax = maxf(vmax, bici.get_forward_speed())
	Input.action_release("sprint")
	Input.action_release("move_forward")
	var st1 := float(pl.get("stamina"))
	_rows.append("bicycle (player, sprint 10 s): %.1f km/h, stamina %.2f -> %.2f" % [vmax * 3.6, st0, st1])
	TestHarness.check(st1 < st0 - 0.1, "sprint pedalling drains stamina (%.2f -> %.2f)" % [st0, st1])
	TestHarness.check(vmax * 3.6 > 32.0 and vmax * 3.6 < 48.0, "sprinting bicycle speed %.1f km/h" % (vmax * 3.6))
	pl.call("exit_vehicle")
	await TestHarness.wait_seconds(1.0)


func _spawn(id: String, pos: Vector3) -> Bike:
	return _vm.call("spawn_vehicle", id, Transform3D(Basis.IDENTITY, pos), {"owner_tag": "civilian"}) as Bike


func _yaw(v: Node3D) -> float:
	var f := -v.global_transform.basis.z
	return atan2(-f.x, -f.z)


# --- proving ground (TEST ONLY: plain boxes) ------------------------------------------------------

func _build_ground() -> void:
	var root := Node3D.new()
	root.name = "BkbGround"
	add_child(root)
	_box(root, Vector3(320.0, 2.0, 1800.0), Vector3(0.0, -1.0, -600.0), Color(0.22, 0.23, 0.27), "asphalt")
	_box(root, Vector3(30.0, 0.15, KERB_Z1 - KERB_Z0), Vector3(KERB_X, 0.075, (KERB_Z0 + KERB_Z1) * 0.5), Color(0.72, 0.7, 0.64), "concrete")
	_box(root, Vector3(10.0, 2.5, 1.0), Vector3(WALL_X, 1.25, WALL_Z), Color(0.8, 0.3, 0.2), "concrete")


func _box(parent: Node, size: Vector3, pos: Vector3, color: Color, surface: String) -> void:
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
	mesh.material = mat
	mi.mesh = mesh
	body.add_child(mi)
	body.position = pos
	parent.add_child(body)
