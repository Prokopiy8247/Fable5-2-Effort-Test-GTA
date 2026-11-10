extends Node
## Headless API / logic test of the Fx autoload (pools, explosion damage + force, fire, surfaces).
## Run:
##   tools\godot.ps1 -Mode headless -Frames 2400 -UserArgs '--test=fx_api','--no_player','--disable=world,environment,city,interactions,vehicles,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## (the short form '--disable=world,traffic,peds,police' works too, it only boots more systems).
## Everything is built by the test itself far above the map, so no world is needed.

const BASE := Vector3(0.0, 400.0, 0.0)
const RADIUS := 6.0
const DAMAGE := 160.0


class Dummy extends StaticBody3D:
	var hits: Array = []
	var total: float = 0.0

	func apply_damage(info: Dictionary) -> void:
		hits.append(info)
		total += float(info.get("amount", 0.0))


class MultiBody extends Node3D:
	var hits: Array = []

	func apply_damage(info: Dictionary) -> void:
		hits.append(info)


## Damageable that blows up when hit (chain reaction): must be queued, never recursive.
class Barrel extends StaticBody3D:
	var exploded: bool = false
	var depth_seen: int = 0

	func apply_damage(_info: Dictionary) -> void:
		if exploded:
			return
		exploded = true
		Fx.explosion(global_position, 3.0, 50.0, null, {"no_crime": true})


var _stage: Node3D
var _cam: Camera3D
var _explosions: Array = []
var _noises: Array = []
var _crimes: Array = []
var _shakes: Array = []
var _max_active: int = 0
var _max_live: int = 0


func _ready() -> void:
	_stage = Node3D.new()
	_stage.name = "FxApiStage"
	add_child(_stage)
	# Fx culls effects by distance to the active camera: keep one next to every test stage
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_cam.global_position = BASE + Vector3(0.0, 3.0, 12.0)
	EventBus.explosion.connect(func(p: Vector3, r: float, who: Node) -> void: _explosions.append([p, r, who]))
	EventBus.noise_emitted.connect(func(p: Vector3, r: float, kind: String, _who: Node) -> void: _noises.append([p, r, kind]))
	EventBus.crime_committed.connect(func(id: String, _p: Vector3, _who: Node) -> void: _crimes.append(id))
	Fx.camera_shake_requested.connect(func(a: float) -> void: _shakes.append(a))
	await TestHarness.wait_frames(5)
	_test_surfaces()
	_test_safe_arguments()
	await _test_explosion()
	await _test_fire()
	await _test_pools()
	await _test_budgets()
	await TestHarness.wait_seconds(4.0)      # let the last sounds ring out before quitting
	TestHarness.finish()


# --- helpers ---------------------------------------------------------------------------------------

func _box_body(body: CollisionObject3D, pos: Vector3, size: Vector3, layer: int, parent: Node = null) -> CollisionObject3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.collision_layer = layer
	body.collision_mask = 0
	(parent if parent != null else _stage).add_child(body)
	(body as Node3D).global_position = pos
	return body


func _dummy(pos: Vector3, layer: int = Layers.NPC) -> Dummy:
	return _box_body(Dummy.new(), pos, Vector3(0.6, 1.8, 0.6), layer) as Dummy


func _fx_nodes() -> int:
	return Fx.find_children("*", "", true, false).size()


func _sample() -> void:
	var st: Dictionary = Fx.get_stats()
	_max_active = maxi(_max_active, int(st["active_systems"]))
	_max_live = maxi(_max_live, int(st["live_particles"]))


# --- surface_of ------------------------------------------------------------------------------------

func _test_surfaces() -> void:
	var wood := Node3D.new()
	wood.set_meta("surface", "wood")
	var child := Node3D.new()
	wood.add_child(child)
	var road := Node3D.new()
	road.set_meta("surface", "road")
	var car := Node3D.new()
	car.add_to_group("vehicle")
	var wheel := Node3D.new()
	car.add_child(wheel)
	var npc := Node3D.new()
	npc.add_to_group("npc")
	var pane := StaticBody3D.new()
	pane.collision_layer = Layers.GLASS
	var plain := StaticBody3D.new()
	TestHarness.check(Fx.surface_of(wood) == "wood", "surface_of: meta on the collider")
	TestHarness.check(Fx.surface_of(child) == "wood", "surface_of: meta on an ancestor")
	TestHarness.check(Fx.surface_of(road) == "asphalt", "surface_of: alias 'road' -> asphalt")
	TestHarness.check(Fx.surface_of(wheel) == "metal", "surface_of: vehicle part -> metal")
	TestHarness.check(Fx.surface_of(npc) == "flesh", "surface_of: npc -> flesh")
	TestHarness.check(Fx.surface_of(pane) == "glass", "surface_of: glass layer -> glass")
	TestHarness.check(Fx.surface_of(plain) == "concrete", "surface_of: default concrete")
	TestHarness.check(Fx.surface_of(null) == "concrete", "surface_of: null is safe")
	for s: String in Fx.SURFACES:
		var n := Node3D.new()
		n.set_meta("surface", s)
		TestHarness.check(Fx.surface_of(n) == s, "surface_of: '%s' round-trips" % s)
		n.free()
	for n: Node in [wood, road, car, npc, pane, plain]:
		n.free()


# --- null / freed arguments --------------------------------------------------------------------------

func _test_safe_arguments() -> void:
	var gone := Node3D.new()
	_stage.add_child(gone)
	gone.free()
	Fx.muzzle_flash(null)
	Fx.shell_eject(null)
	var out_of_tree := Node3D.new()
	Fx.muzzle_flash(out_of_tree)
	Fx.shell_eject(out_of_tree)
	TestHarness.check(Fx.attach_smoke(null, "light") == null, "attach_smoke(null) returns null")
	TestHarness.check(Fx.attach_trail(out_of_tree, "rocket") == null, "attach_trail(out-of-tree) returns null")
	out_of_tree.free()
	Fx.impact(BASE, Vector3.ZERO, "no_such_surface", 1.0)
	Fx.impact(BASE, Vector3(NAN, 0.0, 0.0), "concrete", 1.0)
	Fx.decal(BASE, Vector3.ZERO, "no_such_kind", 0.2)
	Fx.tracer(BASE, BASE)
	Fx.smoke_puff(BASE, "no_such_kind", 1.0)
	Fx.explosion(BASE + Vector3(0, 50, 0), 0.0, 0.0, null, {"silent": true})
	_shakes.clear()
	Fx.shake_camera(0.5)
	TestHarness.check(_shakes.size() == 1 and absf(float(_shakes[0]) - 0.5 * float(Settings.get_value("camera_shake"))) < 0.001,
			"shake_camera emits camera_shake_requested")
	TestHarness.check(true, "null / freed / odd arguments did not crash")


# --- explosion damage + force ------------------------------------------------------------------------

func _test_explosion() -> void:
	var o := BASE
	var c := o + Vector3(0.0, 1.0, 0.0)
	# ground + a wall on the +X side
	_box_body(StaticBody3D.new(), o + Vector3(0, -0.5, 0), Vector3(60, 1, 60), Layers.WORLD)
	_box_body(StaticBody3D.new(), o + Vector3(2.0, 2.0, 0.0), Vector3(0.5, 4.0, 6.0), Layers.WORLD)
	var d1 := _dummy(c + Vector3(-1.5, 0, 0))          # surface 1.2 m away
	var d3 := _dummy(c + Vector3(-3.3, 0, 0))          # 3.0 m
	var d5 := _dummy(c + Vector3(-5.3, 0, 0))          # 5.0 m
	var d8 := _dummy(c + Vector3(-8.3, 0, 0))          # 8.0 m: outside
	var behind := _dummy(c + Vector3(3.3, 0, 0))       # 3.0 m but behind the wall
	var ignored := _dummy(c + Vector3(0, 0, 1.5))
	var multi := MultiBody.new()
	_stage.add_child(multi)
	multi.global_position = c + Vector3(0, 0, 3.0)
	_box_body(StaticBody3D.new(), multi.global_position + Vector3(-0.4, 0, 0), Vector3(0.5, 0.5, 0.5), Layers.PROP, multi)
	_box_body(StaticBody3D.new(), multi.global_position + Vector3(0.4, 0, 0), Vector3(0.5, 0.5, 0.5), Layers.PROP, multi)
	var bodies: Array[RigidBody3D] = []
	for z: float in [-2.5, -4.5, -9.0]:
		var rb := RigidBody3D.new()
		rb.mass = 10.0
		rb.gravity_scale = 0.0
		_box_body(rb, c + Vector3(0, 0, z), Vector3(0.5, 0.5, 0.5), Layers.PROP)
		bodies.append(rb)
	await TestHarness.wait_physics_frames(3)

	_explosions.clear()
	_noises.clear()
	Fx.explosion(c, RADIUS, DAMAGE, null, {"ignore": [ignored]})
	TestHarness.check(d1.hits.size() == 1 and d3.hits.size() == 1 and d5.hits.size() == 1,
			"explosion: every damageable in range is hit exactly once (%d/%d/%d)" % [d1.hits.size(), d3.hits.size(), d5.hits.size()])
	TestHarness.check(d8.hits.is_empty(), "explosion: nothing outside the radius is damaged")
	TestHarness.check(d1.total > d3.total and d3.total > d5.total and d5.total > 0.0,
			"explosion: damage falls off with distance (%.1f > %.1f > %.1f)" % [d1.total, d3.total, d5.total])
	TestHarness.check(absf(d1.total - DAMAGE * Fx.explosion_falloff(1.2, RADIUS)) < 1.0
			and absf(d3.total - DAMAGE * Fx.explosion_falloff(3.0, RADIUS)) < 1.0,
			"explosion: amounts follow the documented falloff from the closest surface point")
	TestHarness.check(absf(Fx.explosion_falloff(0.0, RADIUS) - 1.0) < 0.001 and Fx.explosion_falloff(RADIUS, RADIUS) == 0.0
			and Fx.explosion_falloff(4.0, RADIUS) < (RADIUS - 4.0) / RADIUS + 0.2, "explosion: falloff curve end points")
	TestHarness.check(behind.hits.size() == 1 and behind.total > 0.0 and behind.total < d3.total * 0.5,
			"explosion: line of sight attenuates damage behind a wall (%.1f vs %.1f in the open)" % [behind.total, d3.total])
	TestHarness.check(multi.hits.size() == 1, "explosion: one application per owner with several colliders (%d)" % multi.hits.size())
	TestHarness.check(ignored.hits.is_empty(), "explosion: opts.ignore is respected")
	if d1.hits.size() == 1:
		var info: Dictionary = d1.hits[0]
		var dir: Vector3 = info.get("direction", Vector3.ZERO)
		TestHarness.check(str(info.get("type", "")) == "explosion" and float(info.get("impulse", 0.0)) > 100.0,
				"explosion: info.type / info.impulse are set for knock-down (impulse %.0f)" % float(info.get("impulse", 0.0)))
		TestHarness.check(dir.x < -0.5 and dir.y > 0.0 and absf(dir.length() - 1.0) < 0.01,
				"explosion: info.direction points away from the blast with an upward bias")
	TestHarness.check(_explosions.size() == 1 and absf(float(_explosions[0][1]) - RADIUS) < 0.001, "explosion: EventBus.explosion emitted once")
	TestHarness.check(_noises.size() == 1 and absf(float(_noises[0][1]) - 120.0) < 0.001 and str(_noises[0][2]) == "explosion",
			"explosion: EventBus.noise_emitted(120 m, 'explosion')")
	TestHarness.check(_crimes.is_empty(), "explosion: no crime report without a player instigator")
	await TestHarness.wait_physics_frames(3)
	var v_near := bodies[0].linear_velocity
	var v_mid := bodies[1].linear_velocity
	var v_far := bodies[2].linear_velocity
	TestHarness.check(v_near.z < -1.0 and v_near.length() > v_mid.length() and v_mid.length() > 0.2,
			"explosion: rigid bodies are pushed away, nearer = harder (%.2f > %.2f m/s)" % [v_near.length(), v_mid.length()])
	TestHarness.check(v_far.length() < 0.001, "explosion: rigid body outside the radius is not pushed")

	# cosmetic explosion
	var before := d1.hits.size()
	Fx.explosion(c, RADIUS, DAMAGE, null, {"no_damage": true})
	TestHarness.check(d1.hits.size() == before, "explosion: opts.no_damage skips the blast")

	# player-caused -> crime report through Wanted (only if the police module's autoload is there)
	var fake_player := Node3D.new()
	fake_player.add_to_group("player")
	_crimes.clear()
	Fx.explosion(c + Vector3(0, 30, 0), 3.0, 10.0, fake_player, {})
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and wanted.has_method("report_crime") and wanted.get("enabled") != false:
		TestHarness.check(_crimes.has("explosion"), "explosion: player-caused blast reports the 'explosion' crime")
		if wanted.has_method("clear"):
			wanted.call("clear", "cheat")
	else:
		TestHarness.log_line("Wanted autoload not usable - crime report check skipped")
	fake_player.free()

	# chain reaction: an explosion requested from inside apply_damage is queued, not nested
	var barrel := _box_body(Barrel.new(), c + Vector3(40, 0, 0), Vector3(0.6, 1.0, 0.6), Layers.PROP) as Barrel
	await TestHarness.wait_physics_frames(2)
	_explosions.clear()
	Fx.explosion(barrel.global_position + Vector3(1.0, 0, 0), 4.0, 100.0, null, {})
	TestHarness.check(barrel.exploded and _explosions.size() == 1 and int(Fx.get_stats()["pending_explosions"]) == 1,
			"explosion: nested explosion is queued (pending %d)" % int(Fx.get_stats()["pending_explosions"]))
	await TestHarness.wait_physics_frames(3)
	TestHarness.check(_explosions.size() == 2 and int(Fx.get_stats()["pending_explosions"]) == 0,
			"explosion: queued chain explosion went off on a later physics frame")
	for n in _stage.get_children():
		n.queue_free()
	await TestHarness.wait_physics_frames(2)


# --- fire damage over time ------------------------------------------------------------------------------

func _test_fire() -> void:
	var o := BASE + Vector3(200.0, 0.0, 0.0)
	_cam.global_position = o + Vector3(0.0, 3.0, 12.0)
	_box_body(StaticBody3D.new(), o + Vector3(0, -0.5, 0), Vector3(60, 1, 60), Layers.WORLD)
	var inside := _dummy(o + Vector3(0.8, 0.9, 0.0))
	var outside := _dummy(o + Vector3(6.0, 0.9, 0.0))
	var car := _dummy(o + Vector3(-0.9, 0.9, 0.0), Layers.VEHICLE)
	car.add_to_group("vehicle")
	# a burning "vehicle" with its own fire attached, and a bystander next to it
	var burning := _dummy(o + Vector3(30.0, 0.9, 0.0), Layers.VEHICLE)
	var bystander := _dummy(o + Vector3(31.0, 0.9, 0.0))
	await TestHarness.wait_physics_frames(3)
	var fire := Fx.spawn_fire(o, 1.6, null, 1.0)
	var attached := Fx.spawn_fire(burning.global_position, 1.6, burning, 1.0)
	TestHarness.check(fire != null and attached != null, "spawn_fire returns a handle")
	if fire == null or attached == null:
		return
	TestHarness.check(fire.get("deals_damage") == true and fire.has_meta("deals_damage"), "fire handle advertises deals_damage")
	TestHarness.check(attached.get_parent() == burning, "fire with a parent is parented to it")
	TestHarness.check(int(Fx.get_stats()["fires"]) == 2, "two fires are tracked")
	await TestHarness.wait_seconds(1.3)
	var all_fire := true
	for h: Dictionary in inside.hits:
		all_fire = all_fire and str(h.get("type", "")) == "fire"
	TestHarness.check(inside.hits.size() >= 2 and all_fire, "fire: repeated 'fire' damage ticks inside the radius (%d ticks, %.1f hp)" % [inside.hits.size(), inside.total])
	TestHarness.check(inside.total > 10.0 and inside.total < 45.0, "fire: damage over time is in a sane range (%.1f hp in 1.3 s)" % inside.total)
	TestHarness.check(outside.hits.is_empty(), "fire: nothing outside the radius burns")
	TestHarness.check(car.hits.size() >= 2 and car.total > inside.total, "fire: vehicles take the vehicle rate (%.1f hp)" % car.total)
	TestHarness.check(burning.hits.is_empty(), "fire: a fire attached to a vehicle does not burn its own vehicle")
	TestHarness.check(bystander.hits.size() >= 1, "fire: a burning vehicle's fire burns bystanders")
	await TestHarness.wait_seconds(0.9)
	TestHarness.check(not is_instance_valid(fire) and not is_instance_valid(attached), "fire: handles are freed after their duration")
	TestHarness.check(int(Fx.get_stats()["fires"]) == 0, "fire: no fire left in the pool")
	var ticks := inside.hits.size()
	await TestHarness.wait_seconds(0.8)
	TestHarness.check(inside.hits.size() == ticks, "fire: damage stops when the fire is gone")
	# a fire freed by its owner (vehicle code does fire_node.queue_free())
	var manual := Fx.spawn_fire(o, 0.0, null, 1.2)
	await TestHarness.wait_frames(3)
	TestHarness.check(manual != null and int(Fx.get_stats()["fires"]) == 1, "fire: duration <= 0 burns until freed")
	if manual != null:
		manual.queue_free()
	await TestHarness.wait_frames(3)
	TestHarness.check(int(Fx.get_stats()["fires"]) == 0 and int(Fx.get_stats()["fire_lights"]) == 0, "fire: queue_free() on the handle releases the slot and its light")
	car.remove_from_group("vehicle")
	for n in _stage.get_children():
		n.queue_free()
	await TestHarness.wait_physics_frames(2)


# --- every method, many times; pool exhaustion; no node growth -------------------------------------------

func _test_pools() -> void:
	var o := BASE + Vector3(400.0, 0.0, 0.0)
	_cam.global_position = o + Vector3(0.0, 3.0, 12.0)
	_box_body(StaticBody3D.new(), o + Vector3(0, -0.5, 0), Vector3(80, 1, 80), Layers.WORLD)
	var muzzle := Node3D.new()
	_stage.add_child(muzzle)
	muzzle.global_position = o + Vector3(0, 1.5, 0)
	var mover := Node3D.new()
	_stage.add_child(mover)
	mover.global_position = o + Vector3(5, 1, 0)
	await TestHarness.wait_physics_frames(2)
	await TestHarness.wait_frames(10)
	var nodes_before := _fx_nodes()
	var stats0: Dictionary = Fx.get_stats()
	TestHarness.check(int(stats0["decals_pool"]) == Fx.MAX_DECALS, "decal pool has %d nodes" % Fx.MAX_DECALS)
	var kinds_smoke := ["light", "heavy", "black", "steam", "bogus"]
	var handles: Array[Node3D] = []
	for frame in 60:
		for k in 6:
			var p := o + Vector3(randf_range(-8, 8), 0.0, randf_range(-8, 8))
			Fx.impact(p, Vector3.UP, Fx.SURFACES[(frame + k) % Fx.SURFACES.size()], randf_range(0.5, 1.5))
			Fx.decal(p, Vector3.UP, Fx.DECAL_KINDS[(frame + k) % Fx.DECAL_KINDS.size()], randf_range(0.1, 1.5))
		Fx.muzzle_flash(muzzle, 1.0)
		Fx.shell_eject(muzzle)
		Fx.tracer(muzzle.global_position, o + Vector3(randf_range(-30, 30), 1.0, -40.0))
		Fx.smoke_puff(o + Vector3(2, 1, 2), kinds_smoke[frame % kinds_smoke.size()], 1.0)
		Fx.sparks(o + Vector3(-2, 0.5, 2), Vector3.UP, randf_range(0.3, 2.0))
		Fx.dust(o + Vector3(3, 0, 3), 1.0)
		Fx.tire_smoke(o + Vector3(-3, 0, 3), 1.0)
		Fx.tire_smoke(o + Vector3(-3, 0, 4), 1.0)
		Fx.splash(o + Vector3(6, 0, 0), randf_range(0.4, 2.0))
		Fx.water_ring(o + Vector3(6, 0, 2), 1.0)
		Fx.glass_shatter(o + Vector3(0, 1.5, 4), Vector3.FORWARD, 1.0)
		Fx.blood(o + Vector3(1, 1.2, -3), Vector3.UP)
		Fx.money_burst(o + Vector3(-4, 0, -4))
		Fx.pickup_sparkle(o + Vector3(-5, 0, -4), Color(randf(), randf(), randf()))
		Fx.rotor_wash(o + Vector3(0, 0, 8), 1.0)
		Fx.shake_camera(0.2, o, 30.0)
		if frame % 5 == 0:
			Fx.explosion(o + Vector3(randf_range(-6, 6), 0.5, -10.0), 5.0, 0.0, null, {"no_damage": true, "fire": frame % 10 == 0})
		if frame % 3 == 0:
			var hs := Fx.attach_smoke(mover, Fx.SMOKE_KINDS[frame % 3])
			var ht := Fx.attach_trail(mover, Fx.TRAIL_KINDS[frame % Fx.TRAIL_KINDS.size()])
			if hs != null:
				handles.append(hs)
			if ht != null:
				ht.call("set_strength", randf())
				handles.append(ht)
			Fx.spawn_fire(o + Vector3(randf_range(-5, 5), 0.0, 12.0), 0.4, null, 1.0)
		if frame == 20:
			Fx.set_quality(0)
		if frame == 30:
			Fx.set_quality(1)
		if frame == 40:
			Fx.set_quality(2)
		mover.global_position.x += 0.5
		_sample()
		await get_tree().process_frame
	var st: Dictionary = Fx.get_stats()
	TestHarness.check(_max_active <= Fx.MAX_ACTIVE_SYSTEMS and _max_active >= 30, "pools: active particle systems never above %d under spam (peak %d)" % [Fx.MAX_ACTIVE_SYSTEMS, _max_active])
	TestHarness.check(int(st["decals_visible"]) <= Fx.MAX_DECALS and int(st["decals_placed"]) > Fx.MAX_DECALS,
			"pools: %d decals placed, %d visible (cap %d)" % [int(st["decals_placed"]), int(st["decals_visible"]), Fx.MAX_DECALS])
	TestHarness.check(int(st["fires"]) <= Fx.MAX_FIRES and int(st["fire_lights"]) <= Fx.MAX_LIT_FIRES,
			"pools: fires %d (cap %d), lit %d (cap %d)" % [int(st["fires"]), Fx.MAX_FIRES, int(st["fire_lights"]), Fx.MAX_LIT_FIRES])
	TestHarness.check(int(st["explosion_lights"]) <= Fx.MAX_EXPLOSION_LIGHTS, "pools: explosion lights <= %d" % Fx.MAX_EXPLOSION_LIGHTS)
	TestHarness.check(int(st["materials"]) <= 96, "pools: material cache is bounded (%d)" % int(st["materials"]))
	TestHarness.check(handles.size() >= 30, "attach_smoke / attach_trail returned handles past pool exhaustion (%d)" % handles.size())
	# a decal lent to a moving body that then disappears
	var body := Node3D.new()
	_stage.add_child(body)
	body.global_position = o
	Fx.decal_oriented(o, Vector3.UP, Vector3.FORWARD, "skid", 0.3, 1.2, body)
	body.queue_free()
	for h in handles:
		if is_instance_valid(h):
			h.queue_free()
	mover.queue_free()
	muzzle.queue_free()
	await TestHarness.wait_seconds(6.6)      # the lingering explosion fires burn for 6 s
	for i in 70:
		Fx.decal(o + Vector3(i * 0.1, 0, 0), Vector3.UP, "bullet", 0.2)
	await TestHarness.wait_frames(5)
	st = Fx.get_stats()
	TestHarness.check(int(st["handles"]) == 0 and int(st["fires"]) == 0, "pools: every handle released (%d handles, %d fires)" % [int(st["handles"]), int(st["fires"])])
	TestHarness.check(int(st["decals_pool"]) == Fx.MAX_DECALS, "pools: decal pool is whole again after a lent decal was freed")
	var nodes_after := _fx_nodes()
	TestHarness.check(nodes_after == nodes_before, "pools: no node growth under the Fx autoload (%d -> %d)" % [nodes_before, nodes_after])
	Fx.clear_decals()
	TestHarness.check(int(Fx.get_stats()["decals_visible"]) == 0, "clear_decals hides every decal")
	for n in _stage.get_children():
		n.queue_free()
	await TestHarness.wait_seconds(2.6)


# --- particle budgets ---------------------------------------------------------------------------------------

func _test_budgets() -> void:
	var o := BASE + Vector3(600.0, 0.0, 0.0)
	_cam.global_position = o + Vector3(0.0, 3.0, 12.0)
	_box_body(StaticBody3D.new(), o + Vector3(0, -0.5, 0), Vector3(80, 1, 80), Layers.WORLD)
	var muzzle := Node3D.new()
	_stage.add_child(muzzle)
	muzzle.global_position = o + Vector3(0, 1.5, 0)
	await TestHarness.wait_physics_frames(2)
	TestHarness.check(int(Fx.get_stats()["active_systems"]) == 0, "budget: everything has died down before measuring (%d active)" % int(Fx.get_stats()["active_systems"]))
	# distance culling: an impact 1 km from the camera costs nothing
	Fx.impact(o + Vector3(0, 0, -1000.0), Vector3.UP, "concrete", 1.0)
	Fx.smoke_puff(o + Vector3(0, 0, -1000.0), "black", 1.0)
	TestHarness.check(int(Fx.get_stats()["active_systems"]) == 0, "budget: far-away effects are culled")
	Fx.impact(o + Vector3(0, 0, -6.0), Vector3.UP, "concrete", 1.0)
	TestHarness.check(int(Fx.get_stats()["active_systems"]) == 2, "budget: a near impact starts its two bursts (%d)" % int(Fx.get_stats()["active_systems"]))
	await TestHarness.wait_seconds(1.2)
	# one explosion with everything on
	Fx.explosion(o + Vector3(0, 0.4, -12.0), 6.0, 0.0, null, {"no_damage": true, "fire": true, "visual_scale": 1.2})
	var st: Dictionary = Fx.get_stats()
	TestHarness.check(int(st["live_particles"]) <= 150 and int(st["active_systems"]) >= 6, "budget: one explosion = %d particles (limit ~150) in %d systems" % [int(st["live_particles"]), int(st["active_systems"])])
	await TestHarness.wait_seconds(8.0)
	# steady gunfight: 10 shots per second for 3 s, each with flash + shell + tracer + impact
	_max_live = 0
	_max_active = 0
	for frame in 180:
		if frame % 6 == 0:
			var p := o + Vector3(randf_range(-6, 6), 0.0, randf_range(-14, -6))
			Fx.muzzle_flash(muzzle, 1.0)
			Fx.shell_eject(muzzle)
			Fx.tracer(muzzle.global_position, p)
			Fx.impact(p, Vector3.UP, Fx.SURFACES[(frame / 6) % Fx.SURFACES.size()], 1.0)
		_sample()
		await get_tree().process_frame
	TestHarness.check(_max_live <= 300 and _max_live >= 20, "budget: steady gunfight peaks at %d live particles (limit ~300), %d systems" % [_max_live, _max_active])
	for n in _stage.get_children():
		n.queue_free()
	await TestHarness.wait_frames(3)
