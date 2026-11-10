extends Node
## WORLD physics test (headless):
##   tools\godot.ps1 -Mode headless -Frames 2600 -UserArgs '--test=wld_ground','--disable=traffic,peds,police','--no_player'
## Drops rigid spheres on every kind of ground, walks a capsule over kerbs / up the pier ramp / along the
## hill track, rolls a wheel-sized cylinder over a kerb, and times the height queries.

var T: Node


func _ready() -> void:
	T = TestHarness
	var w: Variant = Game.world
	if not T.check(w != null and w.get("roads") != null, "world is built"):
		T.finish(false, "no world")
		return
	await T.wait_physics_frames(2)
	await _drop_spheres(w)
	await _walk(w, "kerb from road to sidewalk (Marlin Avenue)", Vector3(-118.0, 2.6, -150.0), Vector3(1, 0, 0), 3.0, 2.2, 2.65, "concrete")
	await _walk(w, "kerb from sidewalk down to the road", Vector3(-112.5, 2.75, -140.0), Vector3(-1, 0, 0), 3.0, 2.0, 2.53, "asphalt")
	await _walk(w, "sidewalk corner onto the crosswalk", Vector3(8.5, 2.75, -96.5), Vector3(-1, 0, 0), 3.0, 3.0, 2.53, "asphalt")
	await _walk(w, "kerb ramp into the beach parking", Vector3(158.0, 2.6, 166.0), Vector3(0, 0, 1), 3.0, 3.0, 2.65, "")
	await _walk(w, "quay deck onto the pier ramp", Vector3(-150.0, 2.6, 250.0), Vector3(0, 0, 1), 3.0, 5.0, 1.15, "wood")
	await _walk(w, "along the hill track", Vector3(168.0, 2.6, -36.0), Vector3(-0.181, 0, -0.983), 4.0, 6.0, -1.0, "dirt")
	await _walk(w, "hill track higher up (slope)", Vector3(196.9, 26.0, -168.1), Vector3(0.995, 0, -0.103), 4.0, 5.0, -1.0, "dirt")
	await _walk(w, "beach down towards the water line", Vector3(150.0, 2.7, 240.0), Vector3(0, 0, 1), 4.0, 5.0, -1.0, "sand")
	await _roll_wheel(w)
	_timing(w)
	T.finish()


func _drop_spheres(w: Variant) -> void:
	var spots: Array = [[0.0, -60.0], [-113.0, -150.0], [-90.0, -150.0], [30.0, -60.0], [191.0, 26.0], [205.0, -100.0],
			[225.0, -128.0], [150.0, 258.0], [-150.0, 272.0], [-274.0, 100.0], [-200.0, -250.0], [0.0, -264.0],
			[95.0, -217.0], [8.0, 268.0], [-144.0, 240.0], [100.0, 234.3], [158.0, 182.0], [-168.0, 0.0]]
	var bodies: Array = []
	for s: Array in spots:
		var x := float(s[0])
		var z := float(s[1])
		var body := RigidBody3D.new()
		var shape := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.3
		shape.shape = sph
		body.add_child(shape)
		body.collision_layer = Layers.PROP
		body.collision_mask = Layers.WORLD
		body.linear_damp = 0.8
		body.angular_damp = 6.0
		add_child(body)
		body.global_position = Vector3(x, float(w.get_height(x, z)) + 3.0, z)
		bodies.append(body)
	await T.wait_physics_frames(200)
	var bad := 0
	for i in bodies.size():
		var body: RigidBody3D = bodies[i]
		var p := body.global_position
		var ground := float(w.get_height(p.x, p.z))
		if absf(p.y - 0.3 - ground) > 0.12:
			bad += 1
			T.log_line("sphere %d at %s rests %.2f above get_height (%.2f)" % [i, str(p), p.y - 0.3 - ground, ground])
		body.queue_free()
	T.check(bad == 0, "18 dropped spheres rest on the ground at get_height() (%d off)" % bad)


func _walk(w: Variant, label: String, from: Vector3, dir: Vector3, speed: float, seconds: float, expect_y: float, expect_surface: String) -> void:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(shape)
	body.collision_layer = Layers.NPC
	body.collision_mask = Layers.WORLD
	body.floor_snap_length = 0.4
	body.floor_max_angle = deg_to_rad(46.0)
	add_child(body)
	body.global_position = from
	var frames := int(seconds * 60.0)
	var vy := 0.0
	var max_drop := 0.0
	var last_y := from.y
	for i in frames:
		await get_tree().physics_frame
		vy = 0.0 if body.is_on_floor() else vy - 20.0 / 60.0
		body.velocity = dir * speed + Vector3(0.0, vy, 0.0)
		body.move_and_slide()
		max_drop = maxf(max_drop, last_y - body.global_position.y)
		last_y = body.global_position.y
	var p := body.global_position
	var moved := Vector2(p.x - from.x, p.z - from.z).length()
	var ground := float(w.get_height(p.x, p.z))
	var surf := String(w.get_surface_at(p))
	var ok := moved > speed * seconds * 0.8 and absf(p.y - ground) < 0.12
	if expect_y > 0.0:
		ok = ok and absf(p.y - expect_y) < 0.08
	if expect_surface != "":
		ok = ok and surf == expect_surface
	T.check(ok, "%s: moved %.1f m, feet y %.2f (ground %.2f), surface %s" % [label, moved, p.y, ground, surf])
	body.queue_free()


## A free rolling wheel-sized cylinder must climb the sloped kerb (0.15 m) without being stopped.
func _roll_wheel(w: Variant) -> void:
	var body := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.34
	cyl.height = 0.24
	shape.shape = cyl
	shape.rotation = Vector3(0.0, 0.0, PI * 0.5)
	body.add_child(shape)
	body.mass = 20.0
	body.collision_layer = Layers.PROP
	body.collision_mask = Layers.WORLD
	add_child(body)
	body.global_position = Vector3(1.0, 2.53 + 0.36, 20.0)
	body.rotation = Vector3(0.0, PI * 0.5, 0.0)
	await T.wait_physics_frames(20)
	body.linear_velocity = Vector3(5.0, 0.0, 0.0)
	body.angular_velocity = Vector3(0.0, 0.0, -5.0 / 0.34)
	await T.wait_physics_frames(110)
	var p := body.global_position
	T.check(p.x > 6.5 and absf(p.y - 0.34 - float(w.get_height(p.x, p.z))) < 0.15,
			"a 0.34 m wheel rolls from the lane over the kerb onto the sidewalk (x %.2f, y %.2f)" % [p.x, p.y])
	body.queue_free()


func _timing(w: Variant) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pts: Array[Vector3] = []
	for i in 20000:
		pts.append(Vector3(rng.randf_range(-290.0, 290.0), 3.0, rng.randf_range(-290.0, 290.0)))
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	for p in pts:
		acc += float(w.get_height(p.x, p.z))
	var t1 := Time.get_ticks_usec()
	var n := 0
	for p in pts:
		if String(w.get_surface_at(p)) == "asphalt":
			n += 1
	var t2 := Time.get_ticks_usec()
	for p in pts:
		if String(w.get_district(p)) == "ocean":
			n += 1
	var t3 := Time.get_ticks_usec()
	var roads: Variant = w.get("roads")
	for i in 2000:
		roads.get_nearest_lane(pts[i], 40.0)
	var t4 := Time.get_ticks_usec()
	var walk: Variant = w.get("walk")
	for i in 2000:
		walk.get_nearest_point(pts[i])
	var t5 := Time.get_ticks_usec()
	T.log_line("timing per call: get_height %.2f us, get_surface_at %.2f us, get_district %.2f us, get_nearest_lane(40 m) %.2f us, walk.get_nearest_point %.2f us" % [
			float(t1 - t0) / 20000.0, float(t2 - t1) / 20000.0, float(t3 - t2) / 20000.0, float(t4 - t3) / 2000.0, float(t5 - t4) / 2000.0])
	T.check(float(t1 - t0) / 20000.0 < 25.0, "get_height is cheap (%.2f us per call)" % (float(t1 - t0) / 20000.0))
	T.check(acc != 0.0 and n >= 0, "timing loops ran")
