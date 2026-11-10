extends Node
## Windowed visual check (short, screenshots only): the REAL player with the weapon model in its
## real hand socket, driven by the real animator and seen through the real gameplay camera.
## This is the picture to look at when tuning WeaponSpec.hold_offset / hold_rotation.
## Run (about 12 s):
##   tools\godot.ps1 -Mode window -Frames 360 -UserArgs '--test=wpn_player_shots','--disable=world,environment,city,interactions,vehicles,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Shots (qa/screenshots/):
##   wpn_player_cam_pistol.png   gameplay camera, aiming the pistol (over the shoulder)
##   wpn_player_cam_rifle.png    gameplay camera, aiming the assault rifle
##   wpn_player_side_rifle.png   side camera, rifle aimed        wpn_player_side_pistol.png  pistol aimed
##   wpn_player_side_rpg.png     side camera, launcher aimed     wpn_player_side_bat.png     bat carried
##   wpn_player_fx_shot.png      the frame of a rifle shot: muzzle flash AT the muzzle of the weapon in
##                               the hand, tracer towards the wall, impact on the wall (real Fx)
##   wpn_player_fx_rocket.png    rocket in flight with its trail   wpn_player_fx_explosion.png  its blast
##   wpn_player_fx_fire.png      fire bottle pool burning (Fx fire handle configured by the projectile)

var _side_cam: Camera3D


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.68, 0.76)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.84, 0.95)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = false
	add_child(sun)
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Layers.WORLD
	floor_body.collision_mask = 0
	floor_body.set_meta("surface", "concrete")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	shape.shape = box
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(120.0, 1.0, 120.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.56, 0.58, 0.6)
	mat.roughness = 0.95
	plane.material = mat
	mesh.mesh = plane
	floor_body.add_child(mesh)
	add_child(floor_body)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)
	_side_cam = Camera3D.new()
	_side_cam.fov = 38.0
	add_child(_side_cam)
	await _run()
	Input.action_release("aim")
	TestHarness.finish()


func _frames(n: int) -> void:
	await TestHarness.wait_physics_frames(n)


func _aim_level(p: Node3D) -> void:
	var cam: Variant = p.get("camera")
	if cam != null and is_instance_valid(cam):
		(cam as Object).set("yaw", 0.0)
		(cam as Object).set("pitch", 0.0)


func _game_camera(p: Node3D) -> void:
	var rig: Variant = p.get("camera")
	if rig != null and is_instance_valid(rig):
		var c: Variant = (rig as Object).get("camera")
		if c is Camera3D:
			(c as Camera3D).make_current()


## Side view from the player's right (weapon side), slightly in front.
func _side_camera(p: Node3D) -> void:
	_side_cam.global_position = p.global_position + Vector3(2.3, 1.45, -1.25)
	_side_cam.look_at(p.global_position + Vector3(0.0, 1.2, -0.25), Vector3.UP)
	_side_cam.make_current()


func _run() -> void:
	var chk := TestHarness
	var p := Game.player
	if not chk.check(p != null and is_instance_valid(p), "real player spawned"):
		return
	p.call("teleport", Vector3(0.0, 0.05, 0.0), 0.0)
	await _frames(24)
	var inv := p.get("inventory") as WeaponInventory
	if not chk.check(inv != null, "player has its WeaponInventory"):
		return
	inv.give_weapon("assault_rifle")
	inv.give_weapon("rocket_launcher")
	inv.give_weapon("bat")
	inv.add_attachment("assault_rifle", "scope")
	inv.add_attachment("assault_rifle", "finish_teal")

	# gameplay camera, aiming
	inv.equip("pistol")
	Input.action_press("aim")
	await _frames(26)
	_aim_level(p)
	await _frames(6)
	chk.check(inv.model != null and inv.model.attached_to_hand, "pistol model in the real Hand_R socket")
	_log_pose(p, inv, "pistol")
	_game_camera(p)
	await TestHarness.shot("wpn_player_cam_pistol")
	_side_camera(p)
	await TestHarness.shot("wpn_player_side_pistol")

	inv.equip("assault_rifle")
	await _frames(30)
	_aim_level(p)
	await _frames(4)
	_log_pose(p, inv, "assault_rifle")
	_game_camera(p)
	await TestHarness.shot("wpn_player_cam_rifle")
	_side_camera(p)
	await TestHarness.shot("wpn_player_side_rifle")

	inv.equip("rocket_launcher")
	await _frames(44)
	_aim_level(p)
	await _frames(4)
	_log_pose(p, inv, "rocket_launcher")
	_side_camera(p)
	await TestHarness.shot("wpn_player_side_rpg")

	Input.action_release("aim")
	inv.equip("bat")
	await _frames(30)
	_side_camera(p)
	await TestHarness.shot("wpn_player_side_bat")

	await _fx_section(p, inv)


func _make_wall(at: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	wall.collision_mask = 0
	wall.set_meta("surface", "concrete")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	bm.material = mat
	mesh.mesh = bm
	wall.add_child(mesh)
	add_child(wall)
	wall.global_position = at
	return wall


## The weapons module driving the REAL Fx from the real hand: what a shot, a rocket and a fire
## bottle look like in game. The walls are test fixtures.
func _fx_section(p: Node3D, inv: WeaponInventory) -> void:
	var chk := TestHarness
	var health_before := float(p.get("health"))
	var near_wall := _make_wall(Vector3(0.0, 2.0, -9.0), Vector3(10.0, 4.0, 0.5), Color(0.78, 0.74, 0.66))
	_make_wall(Vector3(0.0, 4.0, -24.0), Vector3(24.0, 8.0, 0.5), Color(0.7, 0.72, 0.76))
	Input.action_press("aim")
	inv.equip("assault_rifle")
	await _frames(36)
	_aim_level(p)
	await _frames(6)

	# --- one rifle shot, captured in the frame it happens -------------------------------------------
	_side_cam.global_position = p.global_position + Vector3(9.0, 1.9, -4.4)
	_side_cam.look_at(p.global_position + Vector3(0.0, 1.35, -4.4), Vector3.UP)
	_side_cam.make_current()
	var results: Array = []
	var on_fired := func(_id: String, result: Dictionary) -> void: results.append(result)
	inv.fired.connect(on_fired)
	await _frames(1)
	var muzzle_at := inv.model.get_muzzle_position() if inv.model != null else Vector3.ZERO
	inv.trigger_pressed()
	await TestHarness.shot("wpn_player_fx_shot")
	inv.trigger_released()
	await _frames(4)
	inv.fired.disconnect(on_fired)
	if chk.check(not results.is_empty() and bool((results[0] as Dictionary).get("hit", false)), "rifle shot from the real hand hit something (%d shot(s))" % results.size()):
		var hit_pos: Vector3 = (results[0] as Dictionary)["position"]
		chk.check(absf(hit_pos.z + 8.75) < 0.05 and absf(hit_pos.x) < 0.6 and hit_pos.y > 0.8 and hit_pos.y < 2.4,
				"the bullet landed on the wall where the crosshair was (%s)" % str(hit_pos.snapped(Vector3.ONE * 0.01)))
	var hand_to_muzzle := muzzle_at - (p.global_position + Vector3(0.0, 1.3, 0.0))
	chk.log_line("muzzle marker at shot time: %s (%.2f m from the chest)" % [str(muzzle_at.snapped(Vector3.ONE * 0.01)), hand_to_muzzle.length()])
	chk.check(hand_to_muzzle.length() < 1.3 and hand_to_muzzle.z < -0.3, "flash / tracer start at the muzzle in front of the player, not at the origin")

	# --- rocket: trail in flight, blast on the far wall -----------------------------------------------
	near_wall.queue_free()
	var booms: Array = []
	var on_boom := func(pos: Vector3, _radius: float, _who: Node) -> void: booms.append(pos)
	EventBus.explosion.connect(on_boom)
	inv.equip("rocket_launcher")
	await _frames(50)
	_aim_level(p)
	await _frames(4)
	_side_cam.fov = 50.0
	_side_cam.global_position = p.global_position + Vector3(16.0, 5.0, 2.0)
	_side_cam.look_at(Vector3(0.0, 2.0, -12.0), Vector3.UP)
	_side_cam.make_current()
	await _frames(1)
	inv.trigger_pressed()
	inv.trigger_released()
	await _frames(8)
	await TestHarness.shot("wpn_player_fx_rocket")
	for i in 120:
		if not booms.is_empty():
			break
		await _frames(1)
	await TestHarness.shot("wpn_player_fx_explosion")
	EventBus.explosion.disconnect(on_boom)
	chk.check(booms.size() == 1 and absf((booms[0] as Vector3).z + 23.75) < 0.8,
			"the rocket flew to the far wall and exploded there (%s)" % (str((booms[0] as Vector3).snapped(Vector3.ONE * 0.1)) if not booms.is_empty() else "no explosion"))
	Input.action_release("aim")

	# --- fire bottle ------------------------------------------------------------------------------------
	var fires: Array = []
	var on_fire := func(pos: Vector3, _src: Node) -> void: fires.append(pos)
	EventBus.fire_started.connect(on_fire)
	Combat.spawn_projectile("molotov", Vector3(1.5, 2.0, -7.0), Vector3(0.0, -6.0, 0.0), p, {})
	_side_cam.fov = 38.0
	_side_cam.global_position = Vector3(7.0, 2.6, -1.0)
	_side_cam.look_at(Vector3(1.5, 0.6, -7.0), Vector3.UP)
	await _frames(70)
	await TestHarness.shot("wpn_player_fx_fire")
	EventBus.fire_started.disconnect(on_fire)
	chk.check(fires.size() == 1, "the fire bottle broke and lit a pool (%d)" % fires.size())
	chk.check(is_equal_approx(float(p.get("health")), health_before), "the player stayed outside every blast and the fire (health %.0f)" % float(p.get("health")))
	Projectile.clear_all()


func _log_pose(p: Node3D, inv: WeaponInventory, id: String) -> void:
	if inv.model == null or not inv.model.is_inside_tree():
		return
	var ray: Dictionary = p.call("get_aim_ray")
	var aim: Vector3 = ray["direction"]
	var barrel := -inv.model.global_basis.z.normalized()
	var up := inv.model.global_basis.y.normalized()
	TestHarness.log_line("%s aimed: barrel.aim = %.3f, weapon up.y = %.3f, grip at %s" % [id, barrel.dot(aim), up.y,
			str((inv.model.global_position - p.global_position).snapped(Vector3.ONE * 0.01))])
	TestHarness.check(barrel.dot(aim) > 0.85 and up.y > 0.7, "%s: barrel along the aim direction, weapon upright (dot %.2f, up %.2f)" % [id, barrel.dot(aim), up.y])
