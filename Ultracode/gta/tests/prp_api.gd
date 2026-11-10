extends Node
## PropSystem (WORLD DRESSING) headless API test.
##   tools\godot.ps1 -Mode headless -Frames 4400 -TimeoutSec 320 -UserArgs '--test=prp_api','--no_player','--disable=traffic,peds,police,wildlife,emergency,transit,taxi,activities,radio,ambience,shops,garage'
## Checks: counts per category within caps, setup budget, no solid prop on a carriageway / the runway,
## the sidewalk walking strip stays free, spawn_prop / get_prop_def, a fast dummy vehicle converts a
## lamp post into a rigid body (+ EventBus.prop_broken), bullets and explosions break props, an
## explosive barrel chain reaction, traffic-light lenses follow RoadGraph.get_signal_state, loose
## props near the focus become sleeping bodies, ladders (node on the rail line of the visible ladder),
## set pieces present, a respawn waits while a vehicle stands on the spot, respawn.

var ps: Node
var broken_events: Array = []
var explosions: Array = []


func _ready() -> void:
	await TestHarness.wait_frames(10)
	ps = Game.get_system("props")
	TestHarness.check(ps != null, "props system registered")
	if ps == null:
		TestHarness.finish(false, "no props system")
		return
	EventBus.prop_broken.connect(func(p: Node3D, who: Node) -> void: broken_events.append([p, who]))
	EventBus.explosion.connect(func(pos: Vector3, r: float, _w: Node) -> void: explosions.append([pos, r]))
	_test_counts()
	_test_placement_rules()
	_test_api()
	await _test_signals()
	await _test_vehicle_lamp()
	await _test_bullet_and_blast()
	await _test_chain()
	await _test_loose()
	await _test_night_lights()
	await _test_respawn_blocked()
	_test_respawn()
	TestHarness.finish()


## Timed respawn is held back while a vehicle stands on the home spot of a broken prop.
func _test_respawn_blocked() -> void:
	var cam := get_viewport().get_camera_3d()
	var hyd: PackedInt32Array = ps.call("find_instances", "hydrant", Vector3(0.0, 2.6, 0.0), 600.0)
	var h := -1
	for i in hyd:
		if String(ps.call("get_instance_state", i)) == "idle":
			h = i
			break
	TestHarness.check(h >= 0, "an idle hydrant for the respawn test")
	if h < 0:
		return
	var hp: Vector3 = (ps.call("get_instance_transform", h) as Transform3D).origin
	ps.call("break_instance", h, Vector3(0, 60.0, 260.0))
	await TestHarness.wait_seconds(0.5)
	var car := RigidBody3D.new()
	car.name = "ParkedDummy"
	car.freeze = true
	car.collision_layer = Layers.VEHICLE
	car.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.8, 1.2, 4.4)
	cs.shape = bx
	cs.position = Vector3(0, 0.8, 0)
	car.add_child(cs)
	Game.get_entities_root().add_child(car)
	car.global_position = hp
	var old := float(ps.get("respawn_seconds"))
	ps.set("respawn_seconds", 1.0)
	if cam != null:
		cam.global_position = hp + Vector3(0.0, 250.0, 260.0)     # far and not looking at it
		cam.look_at(cam.global_position + Vector3(0, 0, 10))
	await TestHarness.wait_seconds(5.0)
	var held := String(ps.call("get_instance_state", h)) != "idle"
	car.queue_free()
	await TestHarness.wait_seconds(13.0)
	var back := String(ps.call("get_instance_state", h)) == "idle"
	ps.set("respawn_seconds", old)
	TestHarness.check(held and back, "respawn waits while a vehicle stands on the spot, then the hydrant is back (held %s, back %s)" % [str(held), str(back)])


func _test_counts() -> void:
	var c: Dictionary = ps.call("get_counts")
	var rep: Dictionary = ps.call("get_debug_report")
	print("PRP_COUNTS ", JSON.stringify(c))
	print("PRP_REPORT ", JSON.stringify(rep))
	var st: Dictionary = rep["stats"]
	TestHarness.check(int(st.get("setup_ms", 99999)) < 2500, "setup under 2.5 s (%d ms)" % int(st.get("setup_ms", -1)))
	var tags: Dictionary = c["by_tag"]
	TestHarness.check(int(c["instances"]) > 4000, "dressing instances > 4000 (%d)" % int(c["instances"]))
	TestHarness.check(int(c["signal_heads"]) >= 80, "traffic signal heads >= 80 (%d)" % int(c["signal_heads"]))
	TestHarness.check(int(c["lamps"]) >= 150, "street lamps with pooled lights >= 150 (%d)" % int(c["lamps"]))
	TestHarness.check(int(tags.get("tree_hill", 0)) >= 220, "Signal Hill wood >= 220 trees (%d)" % int(tags.get("tree_hill", 0)))
	TestHarness.check(int(tags.get("ground_cover", 0)) >= 2000, "ground cover >= 2000 (%d)" % int(tags.get("ground_cover", 0)))
	TestHarness.check(int(tags.get("reef", 0)) >= 150, "reef dressing >= 150 (%d)" % int(tags.get("reef", 0)))
	TestHarness.check(int(tags.get("furniture", 0)) >= 150, "street furniture >= 150 (%d)" % int(tags.get("furniture", 0)))
	TestHarness.check(int(tags.get("set_piece", 0)) >= 40, "set pieces >= 40 (%d)" % int(tags.get("set_piece", 0)))
	TestHarness.check(int(tags.get("ladder", 0)) >= 10, "ladder sections >= 10 (%d)" % int(tags.get("ladder", 0)))
	TestHarness.check(int(c["active"]) <= 60 and int(c["loose_live"]) <= 64, "body caps respected")
	TestHarness.check(int(c["multimesh_nodes"]) <= 900, "MultiMesh nodes <= 900 (%d)" % int(c["multimesh_nodes"]))
	TestHarness.check(int(c["static_bodies"]) <= 140, "batched static bodies <= 140 (%d)" % int(c["static_bodies"]))
	TestHarness.check(int(c["ladders"]) >= 12, "ladder nodes >= 12 (%d)" % int(c["ladders"]))
	TestHarness.check((rep["missing"] as Array).is_empty(), "no missing assets " + str(rep["missing"]))
	var rails: PackedInt32Array = ps.call("find_instances", "guardrail")
	var on_hill := 0
	for i in rails:
		if (ps.call("get_instance_transform", i) as Transform3D).origin.y > 4.0:
			on_hill += 1
	TestHarness.log_line("guard rails: %d (%d above y 4 = hill road)" % [rails.size(), on_hill])
	TestHarness.check(rails.size() >= 10, "guard rails placed (%d)" % rails.size())


## Allowed on carriageways: flush plates, stunt ramps (named locations), underwater / floating things.
const ROAD_OK := ["manhole", "drain", "tree_grate", "stunt_ramp_big", "stunt_ramp_small", "shipwreck", "buoy",
		"fishing_boat_static", "fire_escape_ladder"]
## Allowed in the walking strip (documented exceptions).
const STRIP_OK := ["bus_stop", "bin", "tree_grate", "manhole", "drain", "fence_wood", "fence_chainlink", "hedge",
		"wall_low", "guardrail", "bench", "bench_park", "traffic_light_ped", "sign_street", "utility_box"]


func _test_placement_rules() -> void:
	var roads: Object = Game.world.get("roads")
	var segs: Array = roads.get("segments")
	var n: int = ps.call("get_instance_count")
	var on_road: PackedStringArray = []
	var on_runway: PackedStringArray = []
	var in_strip: PackedStringArray = []
	for i in n:
		var id: String = ps.call("get_instance_id_of", i)
		var xf: Transform3D = ps.call("get_instance_transform", i)
		var p := xf.origin
		var def: Dictionary = ps.call("get_prop_def", id)
		var h := float((def.get("size_v", Vector3.ONE) as Vector3).y)
		if absf(p.z + 264.0) <= 12.0 and p.x >= -170.0 and p.x <= 210.0 and h > 0.12:
			on_runway.append("%s@%.0f,%.0f" % [id, p.x, p.z])
		if ROAD_OK.has(id) or h <= 0.12 or p.y < -0.5:
			continue
		if bool(ps.call("on_carriageway", p)):
			on_road.append("%s@%.1f,%.1f" % [id, p.x, p.z])
			continue
		if STRIP_OK.has(id) or String(ps.call("get_instance_tag", i)) in ["tree_hill", "tree_wild", "rock", "reef", "ground_cover", "bush", "underwater"]:
			continue
		# lateral position relative to the nearest street / arterial with a sidewalk
		var q := Vector2(p.x, p.z)
		for s: Dictionary in segs:
			var kind := String(s["kind"])
			if kind != "street" and kind != "arterial":
				continue
			var hw := float(s["hw"])
			var p2: PackedVector2Array = s["pts2"]
			var best := INF
			var acc := 0.0
			var best_s := 0.0
			for k in range(1, p2.size()):
				var a := p2[k - 1]
				var ab := p2[k] - a
				var l2 := ab.length_squared()
				var t := clampf((q - a).dot(ab) / l2, 0.0, 1.0)
				var d := (a + ab * t).distance_to(q)
				if d < best:
					best = d
					best_s = acc + t * sqrt(l2)
				acc += sqrt(l2)
			var lat := best - hw
			if lat < 1.05 or lat > 2.95:
				continue
			# inside a sidewalk span (not a corner patch / lot)
			var right := ((p2[1] - p2[0]).x * (q.y - p2[0].y) - (p2[1] - p2[0]).y * (q.x - p2[0].x)) > 0.0
			var sp: Array = s["sw_r_span"] if right else s["sw_l_span"]
			if sp.is_empty() or best_s < float(sp[0]) + 0.5 or best_s > float(sp[1]) - 0.5:
				continue
			var fp := float((def.get("size_v", Vector3.ONE) as Vector3).z) * 0.5
			if lat - fp < 1.0 or lat + fp > 1.5:
				in_strip.append("%s@%.1f,%.1f(lat %.2f)" % [id, p.x, p.z, lat])
			break
	TestHarness.check(on_road.is_empty(), "no solid prop on a carriageway (%d): %s" % [on_road.size(), ", ".join(on_road.slice(0, 12))])
	TestHarness.check(on_runway.is_empty(), "nothing standing on the runway (%d): %s" % [on_runway.size(), ", ".join(on_runway.slice(0, 8))])
	TestHarness.check(in_strip.size() <= 3, "sidewalk walking strip clear (%d): %s" % [in_strip.size(), ", ".join(in_strip.slice(0, 12))])


func _test_api() -> void:
	var d: Dictionary = ps.call("get_prop_def", "hydrant")
	TestHarness.check(String(d.get("physics", "")) == "breakable" and String(d.get("class", "")) == "breakable", "get_prop_def(hydrant)")
	TestHarness.check((ps.call("get_prop_def", "no_such_prop") as Dictionary).is_empty(), "get_prop_def(unknown) is empty")
	var spot := Vector3(-215.0, 2.53, -255.0)      # apron
	var cone: Node3D = ps.call("spawn_prop", "cone", Transform3D(Basis.IDENTITY, spot))
	TestHarness.check(cone != null and cone is RigidBody3D and cone.is_in_group("prop"), "spawn_prop(cone) -> rigid prop")
	var bench: Node3D = ps.call("spawn_prop", "bench", Transform3D(Basis.IDENTITY, spot + Vector3(4, 0, 0)))
	TestHarness.check(bench != null and bench.is_inside_tree(), "spawn_prop(bench) -> node in the tree")
	TestHarness.check(ps.call("spawn_prop", "nope", Transform3D.IDENTITY) == null, "spawn_prop(unknown) -> null")
	if cone != null:
		cone.queue_free()
	if bench != null:
		bench.queue_free()
	var ladders: Array = get_tree().get_nodes_in_group("ladder")
	var ok := 0
	for l: Node in ladders:
		if l is Node3D and l.has_meta("height") and float(l.get_meta("height")) > 0.5:
			ok += 1
	TestHarness.check(ok >= 12, "ladder group nodes with height meta (%d)" % ok)
	# every props ladder node stands on the rail line of its visible fire-escape ladder (PlayerStateLadder
	# hangs the body STAND_OFF behind the node origin), climb side = node +Z
	var aligned := 0
	var bad: PackedStringArray = []
	for l: Node3D in ps.call("get_ladders"):
		var f: PackedInt32Array = ps.call("find_instances", "fire_escape_ladder", l.global_position + Vector3(0, 2.0, 0), 4.5)
		if f.is_empty():
			continue        # a climb node for a ladder that is part of a landmark mesh
		var rx: Transform3D = ps.call("get_instance_transform", f[0])
		var dxz := Vector2(rx.origin.x - l.global_position.x, rx.origin.z - l.global_position.z).length()
		var climb := -rx.basis.z.normalized()
		if dxz < 0.05 and climb.dot(l.global_basis.z.normalized()) > 0.99:
			aligned += 1
		else:
			bad.append("%s (%.2f m)" % [l.name, dxz])
	TestHarness.check(aligned >= 12 and bad.is_empty(), "ladder nodes on the rail line of their ladder (%d ok, bad: %s)" % [aligned, ", ".join(bad)])
	for id: String in ["park_statue", "volleyball_net", "fountain", "gazebo", "lifeguard_tower", "dock_crane", "shipwreck"]:
		TestHarness.check(not (ps.call("find_instances", id) as PackedInt32Array).is_empty(), "set piece placed: " + id)


func _test_signals() -> void:
	var roads: Object = Game.world.get("roads")
	var total := 0
	var good := 0
	for round in 3:
		await TestHarness.wait_seconds(3.7)
		var heads: Array = ps.call("get_signal_heads_info")
		for k in heads.size():
			var lane := int(heads[k]["lane_id"])
			var left := float(roads.call("get_signal_time_left", lane))
			var st := int(roads.call("get_signal_state", lane))
			var dur := 9.0 if st == 0 else (2.5 if st == 1 else 14.5)
			if left < 0.3 or dur - left < 0.3:
				continue        # the manager runs at 4 Hz: skip heads that just changed / are about to
			total += 1
			if int(ps.call("get_head_lit_state", k)) == int(roads.call("get_signal_state", lane)):
				good += 1
	TestHarness.check(total > 150 and good == total, "traffic lenses follow the road graph (%d / %d)" % [good, total])


func _test_vehicle_lamp() -> void:
	var lamps: PackedInt32Array = ps.call("find_instances", "street_lamp_a", Vector3(-30.0, 2.6, -110.0), 400.0)
	var target := -1
	for i in lamps:
		if String(ps.call("get_instance_state", i)) == "idle":
			target = i
			break
	TestHarness.check(target >= 0, "found an idle lamp post")
	if target < 0:
		return
	var lxf: Transform3D = ps.call("get_instance_transform", target)
	var along := lxf.basis.x.normalized()
	var car := RigidBody3D.new()
	car.name = "DummyCar"
	car.add_to_group("vehicle")
	car.mass = 1300.0
	car.gravity_scale = 0.0
	car.collision_layer = Layers.VEHICLE
	car.collision_mask = Layers.VEHICLE_MASK
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.8, 1.2, 4.4)
	cs.shape = bx
	cs.position = Vector3(0, 0.8, 0)
	car.add_child(cs)
	Game.get_entities_root().add_child(car)
	var start := lxf.origin - along * 16.0 + Vector3(0, 0.05, 0)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-along.x, -along.z)), start)
	car.linear_velocity = along * 20.0
	broken_events.clear()
	await TestHarness.wait_seconds(1.6)
	var st: String = ps.call("get_instance_state", target)
	TestHarness.check(st == "active" or st == "broken", "lamp post hit at 72 km/h became a rigid body (%s)" % st)
	var body: Node3D = ps.call("get_instance_body", target)
	var tilted := body != null and body.global_basis.y.dot(Vector3.UP) < 0.9
	TestHarness.check(body != null and body is RigidBody3D, "the lamp is a WorldProp")
	TestHarness.check(tilted or (body != null and body.global_position.distance_to(lxf.origin) > 1.0), "the lamp post toppled / moved")
	var emitted := false
	for e: Array in broken_events:
		if e[0] == body:
			emitted = true
	TestHarness.check(emitted, "EventBus.prop_broken emitted for the lamp")
	car.queue_free()
	await _test_real_vehicle()
	await _test_player_crime()
	await _test_light_vehicle()


## A 95 kg "bicycle" at 8 m/s: momentum too small for a 180 kg lamp post (it stays, the bike stops at
## its collider) but enough for a 12 kg speed sign.
func _test_light_vehicle() -> void:
	var results: PackedStringArray = []
	# lamps: along the kerb (local X); speed signs face the traffic: approach from the front (local -Z side)
	for pair: Array in [["street_lamp_a", "idle", "x"], ["sign_speed", "active", "z"]]:
		var f: PackedInt32Array = ps.call("find_instances", String(pair[0]), Vector3(120.0, 2.6, 70.0), 500.0)
		var target := -1
		for i in f:
			if String(ps.call("get_instance_state", i)) != "idle":
				continue
			var x: Transform3D = ps.call("get_instance_transform", i)
			var ax := x.basis.x.normalized() if pair[2] == "x" else x.basis.z.normalized()
			var ok := true
			for k in range(2, 12, 2):
				if not bool(ps.call("is_free", x.origin - ax * float(k), 0.6)):
					ok = false
					break
			if ok:
				target = i
				break
		if target < 0:
			results.append("%s: no target" % pair[0])
			continue
		var lxf: Transform3D = ps.call("get_instance_transform", target)
		var along := lxf.basis.x.normalized() if pair[2] == "x" else lxf.basis.z.normalized()
		var bike := RigidBody3D.new()
		bike.name = "DummyBike"
		bike.add_to_group("vehicle")
		bike.mass = 95.0
		bike.gravity_scale = 0.0
		bike.collision_layer = Layers.VEHICLE
		bike.collision_mask = Layers.VEHICLE_MASK
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.5, 1.2, 1.8)
		cs.shape = bx
		cs.position = Vector3(0, 0.8, 0)
		bike.add_child(cs)
		Game.get_entities_root().add_child(bike)
		bike.global_transform = Transform3D(Basis(Vector3.UP, atan2(-along.x, -along.z)), lxf.origin - along * 8.0 + Vector3(0, 0.05, 0))
		bike.linear_velocity = along * 8.0
		await TestHarness.wait_seconds(1.6)
		var st := String(ps.call("get_instance_state", target))
		results.append("%s: %s" % [pair[0], st])
		TestHarness.check(st == String(pair[1]), "a 95 kg bike at 29 km/h vs %s -> %s (expected %s)" % [pair[0], st, pair[1]])
		bike.queue_free()
		await TestHarness.wait_frames(2)
	TestHarness.log_line("light vehicle: " + ", ".join(results))


## A "player-driven" dummy (runtime script with is_player_driven = true) knocks two props over within a
## few seconds: exactly one property_damage crime is reported (rate limit 8 s).
func _test_player_crime() -> void:
	var crimes: Array = []
	var cb := func(id: String, _p: Vector3, _w: Node) -> void: crimes.append(id)
	EventBus.crime_committed.connect(cb)
	var lamps: PackedInt32Array = ps.call("find_instances", "street_lamp_a", Vector3(-60.0, 2.6, 70.0), 300.0)
	var hits := 0
	for i in lamps:
		if hits >= 2:
			break
		if String(ps.call("get_instance_state", i)) != "idle":
			continue
		var lxf: Transform3D = ps.call("get_instance_transform", i)
		var along := lxf.basis.x.normalized()
		var scr := GDScript.new()
		scr.source_code = "extends RigidBody3D
var is_player_driven := true
var driver: Node = null
"
		scr.reload()
		var car := RigidBody3D.new()
		car.set_script(scr)
		car.add_to_group("vehicle")
		car.mass = 1300.0
		car.gravity_scale = 0.0
		car.collision_layer = Layers.VEHICLE
		car.collision_mask = Layers.VEHICLE_MASK
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(1.8, 1.2, 4.4)
		cs.shape = bx
		cs.position = Vector3(0, 0.8, 0)
		car.add_child(cs)
		Game.get_entities_root().add_child(car)
		car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-along.x, -along.z)), lxf.origin - along * 10.0 + Vector3(0, 0.05, 0))
		car.linear_velocity = along * 20.0
		await TestHarness.wait_seconds(0.9)
		if String(ps.call("get_instance_state", i)) != "idle":
			hits += 1
		car.queue_free()
		await TestHarness.wait_frames(2)
	EventBus.crime_committed.disconnect(cb)
	var pd := crimes.count("property_damage")
	TestHarness.check(hits >= 2 and pd == 1, "player-caused breakage reports property_damage once per 8 s (%d hits, %d reports)" % [hits, pd])


## The same with a real VehicleBase car (if the vehicle module is present): a sedan rolling at 15 m/s
## along the kerb strip into a hydrant / sign / lamp.
func _test_real_vehicle() -> void:
	if Game.get_system("vehicles") == null:
		TestHarness.log_line("no vehicle system: real-car test skipped")
		return
	var lamps: PackedInt32Array = ps.call("find_instances", "street_lamp_a", Vector3(60.0, 2.6, -20.0), 400.0)
	var target := -1
	for i in lamps:
		if String(ps.call("get_instance_state", i)) != "idle":
			continue
		var xf: Transform3D = ps.call("get_instance_transform", i)
		var along := xf.basis.x.normalized()
		var clear := true
		for k in range(4, 22, 3):
			if not bool(ps.call("is_free", xf.origin - along * float(k), 0.9)):
				clear = false
				break
		if clear:
			target = i
			break
	if target < 0:
		TestHarness.log_line("no lamp with a clear run-up: real-car test skipped")
		return
	var lxf: Transform3D = ps.call("get_instance_transform", target)
	var dir := lxf.basis.x.normalized()
	var start := lxf.origin - dir * 18.0 + Vector3(0, 0.4, 0)
	var car: Node3D = Game.spawn_vehicle("sedan", Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), start), {})
	TestHarness.check(car != null, "spawned a real sedan")
	if car == null:
		return
	await TestHarness.wait_frames(3)
	(car as RigidBody3D).linear_velocity = dir * 15.0
	await TestHarness.wait_seconds(2.0)
	var st: String = ps.call("get_instance_state", target)
	TestHarness.check(st == "active" or st == "broken", "a real sedan at 54 km/h knocks the lamp post over (%s)" % st)
	car.queue_free()


func _test_bullet_and_blast() -> void:
	# bullets: a sign takes enough damage and flies
	var signs: PackedInt32Array = ps.call("find_instances", "sign_speed")
	var target := -1
	for i in signs:
		if String(ps.call("get_instance_state", i)) == "idle":
			target = i
			break
	if target >= 0:
		var xf: Transform3D = ps.call("get_instance_transform", target)
		var hit := xf.origin + Vector3(0, 1.0, 0)
		var space := get_viewport().world_3d.direct_space_state
		var q := PhysicsRayQueryParameters3D.create(hit + xf.basis.z * 3.0, hit - xf.basis.z * 3.0, Layers.BULLET_MASK)
		var r := space.intersect_ray(q)
		TestHarness.check(not r.is_empty(), "a ray hits the idle sign collider")
		if not r.is_empty():
			for k in 4:
				Dmg.apply(r["collider"], Dmg.make(18.0, "bullet", null, r["position"], -xf.basis.z, {"impulse": 6.0,
						"collider": r["collider"], "shape": r["shape"]}))
		await TestHarness.wait_frames(5)
		TestHarness.check(String(ps.call("get_instance_state", target)) == "active", "four pistol hits knock the sign over")
	# explosion: hydrants / benches / signs within the blast radius are thrown
	var hyd: PackedInt32Array = ps.call("find_instances", "hydrant")
	var h := -1
	for i in hyd:
		if String(ps.call("get_instance_state", i)) == "idle":
			h = i
			break
	if h >= 0:
		var hp: Vector3 = (ps.call("get_instance_transform", h) as Transform3D).origin
		Fx.explosion(hp + Vector3(1.5, 0.4, 0.0), 5.0, 160.0, null, {"no_scorch": true})
		await TestHarness.wait_frames(3)
		TestHarness.check(String(ps.call("get_instance_state", h)) == "active", "an explosion pops the hydrant off")
		await TestHarness.wait_seconds(1.0)
		var jets: Array = ps.get("_jets")
		TestHarness.check(not jets.is_empty(), "the broken hydrant sprays water")


func _test_chain() -> void:
	explosions.clear()
	var base := Vector3(-225.0, 2.53, -260.0)      # apron, open concrete
	var barrels: Array[Node3D] = []
	for k in 4:
		var b: Node3D = ps.call("spawn_prop", "barrel_explosive", Transform3D(Basis.IDENTITY, base + Vector3(k * 2.6, 0.0, 0.0)))
		if b != null:
			barrels.append(b)
	TestHarness.check(barrels.size() == 4, "spawned 4 explosive barrels")
	await TestHarness.wait_frames(10)
	if barrels.is_empty():
		return
	Dmg.apply(barrels[0], Dmg.make(40.0, "bullet", null, barrels[0].global_position + Vector3(0, 0.5, 0), Vector3.FORWARD, {"impulse": 4.0}))
	await TestHarness.wait_seconds(3.0)
	var near := 0
	for e: Array in explosions:
		if (e[0] as Vector3).distance_to(base) < 14.0:
			near += 1
	TestHarness.check(near >= 4, "explosive barrel chain reaction (%d explosions)" % near)


func _test_loose() -> void:
	var cam := get_viewport().get_camera_3d()
	var lot := Vector3(-164.0, 20.0, 126.0)           # Foundry Yard
	if cam != null:
		cam.global_position = lot
	await TestHarness.wait_seconds(0.8)
	var c: Dictionary = ps.call("get_counts")
	TestHarness.check(int(c["loose_live"]) > 4, "loose props near the focus are sleeping bodies (%d)" % int(c["loose_live"]))
	if cam != null:
		cam.global_position = Vector3(0, 60, 120)
	await TestHarness.wait_seconds(0.8)
	var c2: Dictionary = ps.call("get_counts")
	TestHarness.check(int(c2["loose_live"]) < int(c["loose_live"]), "loose bodies released when the focus leaves (%d)" % int(c2["loose_live"]))


func _test_night_lights() -> void:
	var env := Game.get_system("environment")
	if env == null or not env.has_method("get_light_point_count"):
		TestHarness.log_line("no environment system: light pool not checked")
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		cam.global_position = Vector3(4.0, 5.0, -140.0)
		cam.look_at(Vector3(0.0, 3.0, -100.0))
	WorldClock.set_hour(23.0)
	await TestHarness.wait_seconds(1.5)
	var pts := int(env.call("get_light_point_count"))
	var act := int(env.call("get_active_light_count"))
	TestHarness.log_line("light points %d, active %d" % [pts, act])
	TestHarness.check(pts >= 150, "lamp positions registered with the environment light pool (%d)" % pts)
	TestHarness.check(act > 0, "pooled street lights switch on at night near the camera (%d)" % act)
	# admin toggle: the dressing (and its lights) goes away and comes back
	ps.call("set_enabled", false)
	await TestHarness.wait_seconds(0.6)
	var act_off := int(env.call("get_active_light_count"))
	var hidden := not (ps as Node3D).visible
	ps.call("set_enabled", true)
	await TestHarness.wait_seconds(0.8)
	var act_on := int(env.call("get_active_light_count"))
	TestHarness.check(hidden and act_off == 0 and act_on > 0, "set_enabled(false/true) hides the dressing and its lights (%d -> %d)" % [act_off, act_on])
	WorldClock.set_hour(11.0)
	for id: String in ["fountain", "park_statue", "gazebo", "shipwreck", "dock_crane"]:
		var f: PackedInt32Array = ps.call("find_instances", id)
		TestHarness.log_line("%s: %s" % [id, str((ps.call("get_instance_transform", f[0]) as Transform3D).origin) if not f.is_empty() else "none"])


func _test_respawn() -> void:
	# (the timed respawn above may already have put earlier breakages back: knock two more over)
	for id: String in ["bench", "sign_parking"]:
		var f: PackedInt32Array = ps.call("find_instances", id)
		for i in f:
			if String(ps.call("get_instance_state", i)) == "idle":
				ps.call("break_instance", i, Vector3(0, 40.0, 0))
				break
	var n: int = ps.call("respawn_all")
	var c: Dictionary = ps.call("get_counts")
	TestHarness.check(n >= 2 and int(c["broken"]) == 0 and int(c["active"]) == 0, "respawn_all restores broken props (%d)" % n)
