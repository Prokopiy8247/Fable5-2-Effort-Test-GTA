extends Node
## Windowed wildlife screenshots in the real world (two short parts, each well under 20 s):
##   tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 200 -UserArgs '--test=wld3_shots','--wld3_part=1','--test-timeout=150','--seed=5','--disable=traffic,peds,police,emergency,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups'
##   tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 200 -UserArgs '--test=wld3_shots','--wld3_part=2','--test-timeout=150','--seed=5','--disable=traffic,peds,police,emergency,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups'
## part 1 -> qa/screenshots/wld3_deer_hill.png, wld3_gulls_docks.png, wld3_pets.png
## part 2 -> qa/screenshots/wld3_fish_reef.png, wld3_shark.png, wld3_shark_fin.png

var _cam: Camera3D = null
var _part := 1
var ws: Node = null


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--wld3_part="):
			_part = int(a.substr(12))
	Game.invulnerable = true
	WorldClock.set_hour(9.5)
	if Weather.has_method("set_weather"):
		Weather.set_weather("clear", 0.0)
	if UI.has_method("set_hud_visible"):
		UI.set_hud_visible(false)
	_cam = Camera3D.new()
	_cam.name = "WldShotCam"
	_cam.fov = 55.0
	_cam.far = 1500.0
	add_child(_cam)
	await TestHarness.wait_frames(3)
	ws = Game.get_system("wildlife")
	if not TestHarness.check(ws != null, "wildlife system present"):
		TestHarness.finish(false)
		return
	ws.set("auto_spawn", false)
	ws.clear_all(true)
	if _part == 1:
		await _deer()
		await _gulls()
		await _pets()
	else:
		await _fish()
		await _shark()
	TestHarness.finish()


func _aim(from: Vector3, to: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(to, Vector3.UP)
	_cam.current = true


func _nearest(pts: PackedVector3Array, to: Vector3) -> Vector3:
	var best := pts[0]
	for p in pts:
		if Vector2(p.x - to.x, p.z - to.z).length() < Vector2(best.x - to.x, best.z - to.z).length():
			best = p
	return best


func _h(x: float, z: float) -> float:
	return Game.ground_height(x, z)


func _tree_pts() -> PackedVector3Array:
	var out := PackedVector3Array()
	for k: String in ["tree_hill", "tree_wild", "tree_park", "tree_palm", "tree_street"]:
		for xf: Transform3D in Game.world.get_spawn_points(k):
			out.append(xf.origin)
	return out


## No tree crown within r of the camera -> target line, and no collider in the way (both directions,
## so a camera inside a prop / building is rejected too).
func _view_clear(cam: Vector3, target: Vector3, trees: PackedVector3Array, r: float) -> bool:
	var a := Vector2(cam.x, cam.z)
	var b := Vector2(target.x, target.z)
	for t in trees:
		var t2 := Vector2(t.x, t.z)
		if Geometry2D.get_closest_point_to_segment(t2, a, b).distance_to(t2) < r:
			return false
	var space := get_viewport().world_3d.direct_space_state
	var mask := Layers.WORLD | Layers.PROP | Layers.VEHICLE
	for pair: Array in [[cam, target], [target, cam]]:
		var q := PhysicsRayQueryParameters3D.create(pair[0], pair[1], mask)
		if not space.intersect_ray(q).is_empty():
			return false
	return true


## A camera position around `target` (dist m away, h m above the ground) with a clear view.
func _find_cam(target: Vector3, dist: float, h: float, trees: PackedVector3Array, r: float, from_deg: float = 0.0,
		to_deg: float = 360.0) -> Vector3:
	for k in 24:
		var ang := deg_to_rad(lerpf(from_deg, to_deg, float(k) / 24.0))
		var cp := target + Vector3(cos(ang), 0.0, sin(ang)) * dist
		cp.y = maxf(_h(cp.x, cp.z), Game.WATER_LEVEL) + h
		if _view_clear(cp, target + Vector3.UP * 0.5, trees, r):
			return cp
	return Vector3.INF


# --- part 1 ----------------------------------------------------------------------------------------

func _deer() -> void:
	# the hill is a wood: pick the hill point with the fewest trees around it and a clear camera
	var trees := _tree_pts()
	var base := Vector3.INF
	var cam := Vector3.INF
	var best := 1 << 30
	for p in ws.get_habitat_points("hill"):
		var n := 0
		for t in trees:
			if Vector2(t.x - p.x, t.z - p.z).length() < 8.0:
				n += 1
		if n >= best:
			continue
		var cp := _find_cam(p, 9.0, 1.6, trees, 3.2)
		if cp.is_finite():
			best = n
			base = p
			cam = cp
	if not base.is_finite():
		base = _nearest(ws.get_habitat_points("hill"), Vector3(185.0, 0.0, -112.0))
	TestHarness.log_line("deer clearing %s (%d trees within 8 m)" % [str(base.round()), best])
	ws.set_focus_override(base)
	var a: Node3D = ws.spawn_animal("deer", base, {"state": "graze", "persistent": true, "yaw": 0.6})
	var b: Node3D = ws.spawn_animal("deer", base + Vector3(2.6, 0.0, 1.8), {"state": "wander", "persistent": true, "yaw": 2.0})
	var c: Node3D = ws.spawn_animal("deer", base + Vector3(-2.2, 0.0, 2.4), {"state": "graze", "persistent": true, "yaw": -1.2})
	ws.spawn_animal("rabbit", base + Vector3(1.0, 0.0, 4.2), {"state": "graze", "persistent": true})
	TestHarness.check(a != null and b != null and c != null, "deer spawned on the hill")
	await TestHarness.wait_seconds(1.6)
	var centre := (a.global_position + b.global_position + c.global_position) / 3.0
	var cp := cam
	if not cp.is_finite():
		cp = centre + Vector3(-6.8, 0.0, 5.1)
		cp.y = maxf(_h(cp.x, cp.z), centre.y) + 1.7
	_aim(cp, centre + Vector3.UP * 0.6)
	await TestHarness.wait_frames(2)
	await TestHarness.shot("wld3_deer_hill")
	TestHarness.log_line("deer states %s %s %s" % [a.call("get_state_name"), b.call("get_state_name"), c.call("get_state_name")])
	ws.clear_all(true)


func _gulls() -> void:
	# a docks perch with a clear view from the deck towards the sea (containers stand on the deck)
	var dock := Vector3.INF
	var cam := Vector3.INF
	var none := PackedVector3Array()
	for p in ws.get_habitat_points("coast"):
		if p.x > -270.0 or p.z < -60.0 or p.z > 230.0:
			continue
		var cp := _find_cam(p, 5.0, 1.3, none, 0.0, -50.0, 50.0)
		if cp.is_finite():
			dock = p
			cam = cp
			break
	if not dock.is_finite():
		dock = _nearest(ws.get_habitat_points("coast"), Vector3(-277.0, 2.5, 30.0))
	TestHarness.log_line("gull perch %s cam %s" % [str(dock.round()), str(cam.round())])
	ws.set_focus_override(dock)
	var perched: Array = ws.spawn_flock("seagull", dock, 4, {"flying": false, "persistent": true})
	var fly: Array = ws.spawn_flock("seagull", dock + Vector3(-14.0, 0.0, -6.0), 3, {"flying": true, "persistent": true})
	TestHarness.check(perched.size() == 4 and fly.size() == 3, "gulls spawned at the docks")
	# bring the flyers down to a low circle in front of the camera
	for g: Node3D in fly:
		g.global_position = dock + Vector3(randf_range(-12.0, -4.0), randf_range(4.0, 7.0), randf_range(-8.0, 4.0))
		var br: Object = g.get("brain")
		if br != null:
			br.set("circle_c", dock + Vector3(-9.0, 0.0, -2.0))
			br.set("circle_r", 7.0)
			br.set("cruise_y", dock.y + 5.5)
	await TestHarness.wait_seconds(1.4)
	var cp := cam if cam.is_finite() else dock + Vector3(7.5, 1.9, 5.5)
	_cam.fov = 50.0
	_aim(cp, dock + Vector3(-2.0, 1.4, 0.0))
	await TestHarness.wait_frames(2)
	await TestHarness.shot("wld3_gulls_docks")
	_cam.fov = 55.0
	ws.clear_all(true)


func _pets() -> void:
	var walk: Variant = Game.world.get("walk")
	var p := Vector3(205.0, 2.65, 110.0)
	if walk != null:
		var q: Vector3 = (walk as Object).call("random_point", p, 0.0, 25.0)
		if q.is_finite():
			p = q
	ws.set_focus_override(p)
	var dog: Node3D = ws.spawn_animal("dog", p, {"state": "wander", "persistent": true, "habitat": "urban"})
	var cat: Node3D = ws.spawn_animal("cat", p + Vector3(1.8, 0.0, 1.2), {"persistent": true, "habitat": "urban"})
	ws.spawn_flock("pigeon", p + Vector3(-2.5, 0.0, 2.0), 4, {"flying": false, "persistent": true})
	TestHarness.check(dog != null and cat != null, "pets spawned in town")
	await TestHarness.wait_seconds(1.2)
	var centre := (dog.global_position + cat.global_position) * 0.5
	var cp := centre + Vector3(4.0, 1.3, 4.5)
	_aim(cp, centre + Vector3.UP * 0.3)
	await TestHarness.wait_frames(2)
	await TestHarness.shot("wld3_pets")
	ws.clear_all(true)


# --- part 2 ----------------------------------------------------------------------------------------

func _fish() -> void:
	var rp := _nearest(ws.get_habitat_points("reef"), Vector3(160.0, 0.0, 285.0))
	var depth := Game.WATER_LEVEL - Game.ground_height(rp.x, rp.z)
	if Game.world != null and Game.world.has_method("get_water_depth"):
		depth = float(Game.world.get_water_depth(rp.x, rp.z))
	var bed := Game.WATER_LEVEL - depth
	ws.set_focus_override(rp)
	var s1: Node3D = ws.spawn_fish_school(Vector3(rp.x, bed + 1.8, rp.z), {"count": 18, "persistent": true, "radius": 4.0})
	var s2: Node3D = ws.spawn_fish_school(Vector3(rp.x + 3.0, bed + 2.6, rp.z - 2.0), {"count": 14, "persistent": true, "radius": 4.0})
	TestHarness.check(s1 != null and s2 != null, "fish schools spawned at the reef")
	await TestHarness.wait_seconds(1.0)
	var c: Vector3 = s1.get("centre")
	var cp := c + Vector3(4.2, 0.6, 3.0)
	cp.y = minf(cp.y, Game.WATER_LEVEL - 1.5)
	_aim(cp, c)
	await TestHarness.wait_seconds(0.6)
	c = s1.get("centre")
	_aim(c + Vector3(4.2, 0.6, 3.0), c)
	await TestHarness.wait_frames(2)
	await TestHarness.shot("wld3_fish_reef")
	ws.clear_all(true)


func _shark() -> void:
	var home := _nearest(ws.get_habitat_points("deep"), Vector3(148.0, -6.0, 300.0))
	ws.set_focus_override(home)
	var shark: Node3D = ws.spawn_animal("shark", home, {"persistent": true, "home": home})
	TestHarness.check(shark != null, "shark spawned")
	if shark == null:
		return
	shark.global_position = Vector3(home.x, -4.0, home.z)
	await TestHarness.wait_seconds(1.2)
	var p := shark.global_position
	var f := Vector3(-sin(float(shark.get("yaw"))), 0.0, -cos(float(shark.get("yaw"))))
	var r := f.cross(Vector3.UP).normalized()
	_aim(p + r * 6.5 + f * 2.0 + Vector3.UP * 0.8, p)
	await TestHarness.wait_frames(2)
	await TestHarness.shot("wld3_shark")
	# fin above the surface: the shark circles a swimmer-like target just under the waves
	var target := Node3D.new()
	add_child(target)
	target.global_position = Vector3(p.x + 6.0, -0.3, p.z + 4.0)
	shark.global_position = Vector3(p.x, -0.9, p.z)
	shark.call("attack", target)
	var brain: Object = shark.get("brain")
	if brain != null:
		brain.set("dur", 30.0)
	await TestHarness.wait_seconds(3.0)
	p = shark.global_position
	_aim(p + Vector3(7.0, 2.2, 6.0), p + Vector3(0.0, 0.3, 0.0))
	await TestHarness.wait_frames(2)
	await TestHarness.shot("wld3_shark_fin")
	TestHarness.log_line("shark y %.2f state %s" % [p.y, shark.call("get_state_name")])
	target.queue_free()
	ws.clear_all(true)
