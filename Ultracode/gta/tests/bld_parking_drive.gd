extends Node
## Real-physics drivability test of the generic car park `parking_a.glb` (art critic, building kit).
##
## Builds the collider exactly like the game is asked to (docs/BUILDING_KIT.md): a trimesh from the
## `Building` node only (manifest key collision_nodes), on a flat street slab at y = 0. Then a real
## vehicle from the vehicle module (default: sedan) drives itself with a pure-pursuit follower along
## the manifest's `route_up` (street -> ground floor -> back ramp -> deck 1 -> front ramp -> roof deck)
## and back down the same way. Checks: reaches the roof deck, comes back out onto the street, stays
## upright, never stalls, lateral tracking error stays small. Prints a table of what happened.
##
## Run (headless, about 3 game minutes):
##   tools\godot.ps1 -Mode headless -Frames 14000 -UserArgs '--test=bld_parking_drive','--test-timeout=400','--no_player',
##      '--disable=world,environment,city,interactions,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Optional: --veh=suv,van,...  (comma list of vehicle spec ids; each one runs the whole route)
## Windowed: no driving, the car is posed at the entrance / on both ramps / on the roof and screenshots
##   qa/screenshots/bld_parking_<n>.png are saved (same command with -Mode window -Frames 200).
## The street slab, light and camera are test scaffolding, never game content.

const DIR := "res://gta/generated/models/buildings/"
const LOOKAHEAD := 3.2
const FILLET := 4.0
const CRUISE := 3.6          ## m/s (13 km/h) - car park speed

var _level_y: Array = [0.12, 3.12, 6.12]
var _ramp_slope := 0.15
var _path: PackedVector3Array = []      ## smoothed centre line, 0.25 m spacing, with heights
var _cum: PackedFloat32Array = []
var _building: Node3D
var _body: StaticBody3D
var _cam: Camera3D


func _ready() -> void:
	await _run()


func _run() -> void:
	var entry := _manifest_entry("parking_a")
	if not TestHarness.check(not entry.is_empty(), "parking_a is in manifest_generic.json"):
		TestHarness.finish(false, "no manifest entry")
		return
	TestHarness.check(String(entry.get("collision", "")) == "trimesh", "manifest: collision is trimesh")
	_ramp_slope = float(entry.get("ramp_slope", 0.15))
	TestHarness.check(_ramp_slope <= 0.18 + 1e-4, "manifest: ramp slope %.1f %% <= 18 %%" % (_ramp_slope * 100.0))
	TestHarness.check(float(entry.get("clear_height", 0.0)) >= 2.6, "manifest: clear height %.2f m >= 2.6 m" % float(entry.get("clear_height", 0.0)))
	TestHarness.check(float(entry.get("lane_width_min", 0.0)) >= 3.5, "manifest: narrowest lane %.2f m >= 3.5 m" % float(entry.get("lane_width_min", 0.0)))
	if entry.has("levels"):
		_level_y = entry["levels"]
	if not _build_site(entry):
		TestHarness.finish(false, "cannot build the car park")
		return
	var route: Array = entry.get("route_up", [])
	if not TestHarness.check(route.size() >= 4, "manifest: route_up has %d points" % route.size()):
		TestHarness.finish(false, "no route")
		return
	_make_path(route)
	TestHarness.log_line("route length %.1f m, %d samples, end height %.2f m" % [_cum[_cum.size() - 1], _path.size(), _path[_path.size() - 1].y])
	await TestHarness.wait_physics_frames(3)
	_probe_route()
	if not TestHarness.is_headless():
		await _pose_shots()
		TestHarness.finish()
		return
	var ids: Array[String] = ["sedan"]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--veh="):
			ids.assign(a.substr(6).split(",", false))
	for id: String in ids:
		await _drive(id)
	TestHarness.finish()


# ----------------------------------------------------------------------------------------------- site
func _manifest_entry(id: String) -> Dictionary:
	var f := FileAccess.open(DIR + "manifest_generic.json", FileAccess.READ)
	if f == null:
		return {}
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) != TYPE_DICTIONARY:
		return {}
	for e: Variant in (doc as Dictionary).get("buildings", []):
		if typeof(e) == TYPE_DICTIONARY and String((e as Dictionary).get("id", "")) == id:
			return e
	return {}


func _build_site(entry: Dictionary) -> bool:
	# street: a big slab whose top is y = 0 (the building origin sits on the ground)
	var street := StaticBody3D.new()
	street.name = "TestStreet"
	street.collision_layer = Layers.WORLD
	street.collision_mask = 0
	street.set_meta("surface", "asphalt")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(240.0, 2.0, 240.0)
	cs.shape = box
	street.add_child(cs)
	var smi := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = box.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.29)
	mat.roughness = 0.95
	sm.material = mat
	smi.mesh = sm
	street.add_child(smi)
	street.position = Vector3(0.0, -1.0, 0.0)
	add_child(street)
	var path := DIR + String(entry.get("file", "parking_a.glb"))
	if not TestHarness.check(ResourceLoader.exists(path), "GLB imported: " + path):
		return false
	var ps := load(path) as PackedScene
	_building = ps.instantiate() as Node3D if ps != null else null
	if not TestHarness.check(_building != null, "GLB instantiates"):
		return false
	add_child(_building)
	_body = StaticBody3D.new()
	_body.name = "ParkingCollision"
	_body.collision_layer = Layers.WORLD
	_body.collision_mask = 0
	_body.set_meta("surface", "concrete")
	add_child(_body)
	var faces := 0
	for n: Variant in entry.get("collision_nodes", ["Building"]):
		var mi := _building.find_child(String(n), true, false) as MeshInstance3D
		if not TestHarness.check(mi != null and mi.mesh != null, "collision node '%s' exists" % String(n)):
			return false
		var shape := mi.mesh.create_trimesh_shape()
		faces += shape.get_faces().size() / 3
		var c := CollisionShape3D.new()
		c.shape = shape
		_body.add_child(c)
		c.global_transform = mi.global_transform
	TestHarness.check(faces > 100, "trimesh collider built from the Building node (%d triangles)" % faces)
	return true


# ----------------------------------------------------------------------------------------------- path
## Fillets the 90-degree corners of the manifest route, resamples it every 0.25 m and reads the surface
## height under every sample with a ray (so the path follows the ramps).
func _make_path(route: Array) -> void:
	var pts: Array[Vector2] = []
	for p: Variant in route:
		pts.append(Vector2(float(p[0]), float(p[1])))
	pts[0] = Vector2(pts[0].x, pts[0].y - 10.0)             # start further out on the street
	var poly: Array[Vector2] = [pts[0]]
	for i in range(1, pts.size() - 1):
		var a := (pts[i] - pts[i - 1]).normalized()
		var b := (pts[i + 1] - pts[i]).normalized()
		var r := minf(FILLET, minf(pts[i].distance_to(pts[i - 1]), pts[i].distance_to(pts[i + 1])) * 0.45)
		var c := pts[i] - a * r + b * r
		for k in 9:
			var t := float(k) / 8.0 * PI * 0.5
			poly.append(c - b * r * cos(t) + a * r * sin(t))
	poly.append(pts[pts.size() - 1])
	var flat: Array[Vector2] = []
	for i in range(poly.size() - 1):
		var d := poly[i].distance_to(poly[i + 1])
		var n := maxi(1, int(ceil(d / 0.25)))
		for k in n:
			flat.append(poly[i].lerp(poly[i + 1], float(k) / float(n)))
	flat.append(poly[poly.size() - 1])
	_path.clear()
	_cum.clear()
	var y := 0.0
	var dist := 0.0
	for i in flat.size():
		y = _surface_y(flat[i], y)
		var p3 := Vector3(flat[i].x, y, flat[i].y)
		if i > 0:
			dist += p3.distance_to(_path[i - 1])
		_path.append(p3)
		_cum.append(dist)


func _surface_y(p: Vector2, near_y: float) -> float:
	var space := get_viewport().find_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, near_y + 1.2, p.y), Vector3(p.x, near_y - 2.0, p.y), Layers.WORLD)
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if not hit.is_empty() else near_y


## Physics-space version of the Blender drive test: steps, slope and headroom along the path.
func _probe_route() -> void:
	var space := get_viewport().find_world_3d().direct_space_state
	var max_step := 0.0
	var max_slope := 0.0
	var min_head := 99.0
	for i in range(1, _path.size()):
		var run := Vector2(_path[i].x - _path[i - 1].x, _path[i].z - _path[i - 1].z).length()
		var dy := absf(_path[i].y - _path[i - 1].y)
		max_step = maxf(max_step, dy)
		if run > 0.05:
			max_slope = maxf(max_slope, dy / run)
		var q := PhysicsRayQueryParameters3D.create(_path[i] + Vector3(0, 0.3, 0), _path[i] + Vector3(0, 30.0, 0), Layers.WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			min_head = minf(min_head, float(hit["position"].y) - _path[i].y)
	var top := _path[_path.size() - 1].y
	TestHarness.log_line("physics probe: max step %.3f m, max slope %.1f %%, min headroom %.2f m, top %.2f m" % [max_step, max_slope * 100.0, min_head, top])
	TestHarness.check(max_step < 0.09, "collider: no step above 9 cm on the route (max %.3f m)" % max_step)
	TestHarness.check(max_slope <= 0.18 + 0.005, "collider: steepest part of the route %.1f %% <= 18 %%" % (max_slope * 100.0))
	TestHarness.check(min_head >= 2.6 - 0.01, "collider: headroom on the route %.2f m >= 2.6 m" % min_head)
	TestHarness.check(absf(top - float(_level_y[_level_y.size() - 1])) < 0.05, "route ends on the roof deck (y %.2f)" % top)


# ----------------------------------------------------------------------------------------------- drive
func _spawn(id: String, at: int, reverse: bool) -> Node3D:
	var fwd := (_path[mini(at + 4, _path.size() - 1)] - _path[maxi(at - 4, 0)]).normalized()
	if reverse:
		fwd = -fwd
	fwd.y = 0.0
	var basis := Basis.looking_at(fwd.normalized(), Vector3.UP)
	return Game.spawn_vehicle(id, Transform3D(basis, _path[at] + Vector3(0, 0.05, 0)), {"color": Color(0.85, 0.3, 0.2)})


func _drive(id: String) -> void:
	if not TestHarness.check(Registry.get_def("vehicles", id) != null, "%s: spec is registered" % id):
		return
	var car: Variant = _spawn(id, 0, false)
	if not TestHarness.check(car != null, "%s spawns on the street" % id):
		return
	await TestHarness.wait_physics_frames(90)
	var up: Dictionary = await _follow(car, false)
	var top_y: float = car.global_position.y
	TestHarness.check(bool(up["done"]), "%s UP: reached the end of the route in %.0f s (progress %.0f / %.0f m)" % [id, up["time"], up["s"], _cum[_cum.size() - 1]])
	TestHarness.check(top_y > float(_level_y[_level_y.size() - 1]) - 0.3, "%s UP: stands on the roof deck (y %.2f m)" % [id, top_y])
	TestHarness.check(float(up["min_up"]) > 0.85, "%s UP: stayed upright (min up.y %.3f)" % [id, up["min_up"]])
	TestHarness.check(float(up["max_err"]) < 1.5, "%s UP: tracking error stayed below 1.5 m (max %.2f m)" % [id, up["max_err"]])
	TestHarness.log_line("%s UP   time %.1f s  avg %.1f km/h  max %.1f km/h  max lateral error %.2f m  longest stall %.1f s  max pitch %.1f deg" % [
			id, up["time"], up["avg_kmh"], up["max_kmh"], up["max_err"], up["stall"], up["max_pitch"]])
	# turn the car round on the roof (teleport, same spot) and drive the same line down again
	car.release_inputs()
	var n := _path.size() - 1
	var back := (_path[n - 4] - _path[n]).normalized()
	back.y = 0.0
	car.teleport(Transform3D(Basis.looking_at(back.normalized(), Vector3.UP), _path[n] + Vector3(0, 0.05, 0)))
	await TestHarness.wait_physics_frames(90)
	var down: Dictionary = await _follow(car, true)
	var end_pos: Vector3 = car.global_position
	TestHarness.check(bool(down["done"]), "%s DOWN: reached the street end of the route in %.0f s" % [id, down["time"]])
	TestHarness.check(end_pos.y < 0.6 and end_pos.z < -15.0, "%s DOWN: is back on the street (y %.2f, z %.1f)" % [id, end_pos.y, end_pos.z])
	TestHarness.check(float(down["min_up"]) > 0.85, "%s DOWN: stayed upright (min up.y %.3f)" % [id, down["min_up"]])
	TestHarness.check(float(down["max_err"]) < 1.5, "%s DOWN: tracking error stayed below 1.5 m (max %.2f m)" % [id, down["max_err"]])
	TestHarness.log_line("%s DOWN time %.1f s  avg %.1f km/h  max %.1f km/h  max lateral error %.2f m  longest stall %.1f s" % [
			id, down["time"], down["avg_kmh"], down["max_kmh"], down["max_err"], down["stall"]])
	var health_txt := ""
	if "health" in car and "max_health" in car:
		health_txt = "  health %.0f / %.0f" % [car.health, car.max_health]
		TestHarness.check(float(car.health) > float(car.max_health) * 0.9, "%s: no serious damage from walls or columns (health %.0f / %.0f)" % [id, car.health, car.max_health])
	TestHarness.log_line("%s round trip done%s" % [id, health_txt])
	car.queue_free()
	await TestHarness.wait_physics_frames(5)


## Pure-pursuit follower. reverse = drive the path from its end to its start. Returns statistics.
func _follow(car: Variant, reverse: bool) -> Dictionary:
	var total := _cum[_cum.size() - 1]
	var idx := _path.size() - 1 if reverse else 0
	var st := {"done": false, "time": 0.0, "s": 0.0, "max_err": 0.0, "min_up": 1.0, "max_kmh": 0.0, "avg_kmh": 0.0, "stall": 0.0, "max_pitch": 0.0}
	var wb := 2.7
	if "wheelbase" in car:
		wb = float(car.wheelbase)
	var max_steer := deg_to_rad(35.0)
	if "spec" in car and car.spec != null:
		max_steer = deg_to_rad(float(car.spec.max_steer_angle))
	var stall_t := 0.0
	var dist_sum := 0.0
	var last_pos: Vector3 = car.global_position
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var limit := 240.0
	while st["time"] < limit:
		await get_tree().physics_frame
		st["time"] += dt
		var pos: Vector3 = car.global_position
		var xf: Transform3D = car.global_transform
		# progress: nearest path sample in a short window ahead (the route overlaps itself on other levels)
		var best := idx
		var best_d := INF
		var step := -1 if reverse else 1
		var j := idx
		for k in 28:
			if j < 0 or j >= _path.size():
				break
			var d := pos.distance_squared_to(_path[j] + Vector3(0, 0.4, 0))
			if d < best_d:
				best_d = d
				best = j
			j += step
		idx = best
		var s_now := (total - _cum[idx]) if reverse else _cum[idx]
		st["s"] = s_now
		var flat_err := Vector2(pos.x - _path[idx].x, pos.z - _path[idx].z).length()
		st["max_err"] = maxf(st["max_err"], flat_err)
		st["min_up"] = minf(st["min_up"], xf.basis.y.y)
		st["max_pitch"] = maxf(st["max_pitch"], rad_to_deg(asin(clampf(-xf.basis.z.y, -1.0, 1.0))))
		var v: float = car.get_forward_speed()
		st["max_kmh"] = maxf(st["max_kmh"], absf(v) * 3.6)
		dist_sum += Vector2(pos.x - last_pos.x, pos.z - last_pos.z).length()
		last_pos = pos
		if absf(v) < 0.25:
			stall_t += dt
			st["stall"] = maxf(st["stall"], stall_t)
		else:
			stall_t = 0.0
		if s_now >= total - 1.2:
			st["done"] = true
			break
		if stall_t > 12.0:
			TestHarness.log_line("stalled for 12 s at %s (progress %.1f m)" % [str(pos), s_now])
			break
		# look-ahead target
		var want := LOOKAHEAD
		var t_i := idx
		while t_i + step >= 0 and t_i + step < _path.size() and absf(_cum[t_i] - _cum[idx]) < want:
			t_i += step
		var target := _path[t_i]
		var to := target - pos
		var lateral := to.dot(xf.basis.x)
		var ahead := to.dot(-xf.basis.z)
		var l2 := maxf(lateral * lateral + ahead * ahead, 0.5)
		var steer := clampf(atan(wb * 2.0 * lateral / l2) / max_steer, -1.0, 1.0)
		# speed: slower in the bends, a little faster on the straights
		var v_want := CRUISE * (1.0 - 0.35 * absf(steer))
		var throttle := clampf((v_want - v) * 0.7 + 0.08, 0.0, 1.0)
		var brake := clampf((v - v_want - 0.8) * 0.5, 0.0, 1.0)
		car.set_inputs(throttle, steer, brake, false)
	car.set_inputs(0.0, 0.0, 1.0, false)
	await TestHarness.wait_physics_frames(90)
	car.set_inputs(0.0, 0.0, 0.0, true)
	st["avg_kmh"] = dist_sum / maxf(st["time"], 0.01) * 3.6
	return st


# ----------------------------------------------------------------------------------------------- shots
func _pose_shots() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	sun.look_at_from_position(Vector3(-6.0, 10.0, -9.0), Vector3.ZERO, Vector3.UP)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.25, 0.48, 0.82)
	psm.sky_horizon_color = Color(0.78, 0.86, 0.93)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	we.environment = env
	add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.make_current()
	if UI != null and UI.has_method("set_hud_visible"):
		UI.set_hud_visible(false)
	var total := _cum[_cum.size() - 1]
	# [progress along the route (0..1), camera offset in the car's frame (right, up, back)]
	var poses := [[0.085, Vector3(5.5, 2.4, 9.0)], [0.44, Vector3(0.9, 2.0, 7.5)], [0.80, Vector3(0.9, 2.0, 7.5)], [0.985, Vector3(7.0, 5.0, 11.0)]]
	var car: Variant = null
	var n := 0
	for pz: Variant in poses:
		var want := total * float(pz[0])
		var at := 0
		while at < _path.size() - 1 and _cum[at] < want:
			at += 1
		if car == null:
			car = _spawn("sedan", at, false)
			if car == null:
				TestHarness.check(false, "sedan spawns for the screenshots")
				return
		else:
			var fwd := (_path[mini(at + 4, _path.size() - 1)] - _path[maxi(at - 4, 0)]).normalized()
			car.teleport(Transform3D(Basis.looking_at(Vector3(fwd.x, 0.0, fwd.z).normalized(), Vector3.UP), _path[at] + Vector3(0, 0.08, 0)))
		await TestHarness.wait_physics_frames(40)
		var xf: Transform3D = car.global_transform
		var off: Vector3 = pz[1]
		var eye := xf.origin + xf.basis.x * off.x + Vector3.UP * off.y + xf.basis.z * off.z
		_cam.look_at_from_position(eye, xf.origin + Vector3(0, 0.8, 0), Vector3.UP)
		await TestHarness.wait_frames(4)
		n += 1
		await TestHarness.shot("bld_parking_%d" % n)
