extends Node
## Windowed visual check of the Fx autoload (short run, screenshots only).
## Run:
##   tools\godot.ps1 -Mode window -Frames 560 -UserArgs '--test=fx_shots','--no_player','--disable=world,environment,city,interactions,vehicles,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Optional: '--flag=fx_only_<name>' (decals, impacts, muzzle, smoke, splash, explosion, fire)
## renders just one station.
## Shots (qa/screenshots/):
##   fx_shots_decals.png        bullet / blood / oil / skid / scorch decals, close-up
##   fx_shots_impacts.png       impacts on concrete, metal, wood and dirt panels (+ _marks: the decals left)
##   fx_shots_muzzle.png        muzzle flash + tracer + shell + target sparks
##   fx_shots_smoke.png         attach_smoke light / heavy / black columns + a rocket trail
##   fx_shots_splash.png        water splash (large + bullet sized) with rings
##   fx_shots_explosion_1/2/3   one explosion: flash, fireball, smoke
##   fx_shots_fire_night.png    a burning fire at night (flicker light)
## The stage (ground, panels, crates, sun, sky colour, glow like the game environment) is built
## here, so no world system is needed. Stations are 60 m apart along X.

const BASE := Vector3(0.0, 300.0, 0.0)
const STEP := 60.0

var _env: Environment
var _sun: DirectionalLight3D
var _cam: Camera3D
var _stage: Node3D


func _ready() -> void:
	_build_stage()
	# the HUD and the boot splash are not part of these pictures
	var ui := get_node_or_null("/root/UI")
	if ui != null and ui.has_method("set_hud_visible"):
		ui.call("set_hud_visible", false)
	await TestHarness.wait_seconds(1.6)
	if _wants("decals"):
		printerr("FXMARK decals")
		await _shot_decals(_station(0))
	if _wants("impacts"):
		printerr("FXMARK impacts")
		await _shot_impacts(_station(1))
	if _wants("muzzle"):
		printerr("FXMARK muzzle")
		await _shot_muzzle(_station(2))
	if _wants("smoke"):
		printerr("FXMARK smoke")
		await _shot_smoke(_station(3))
	if _wants("splash"):
		printerr("FXMARK splash")
		await _shot_splash(_station(4))
	if _wants("explosion"):
		printerr("FXMARK explosion")
		await _shot_explosion(_station(5))
	if _wants("fire"):
		printerr("FXMARK fire")
		await _shot_fire_night(_station(6))
	printerr("FXMARK end")
	var st: Dictionary = Fx.get_stats()
	TestHarness.log_line("fx stats at the end: %s" % str(st))
	TestHarness.check(int(st["active_systems"]) <= Fx.MAX_ACTIVE_SYSTEMS, "active particle systems within budget")
	TestHarness.finish()


func _wants(station: String) -> bool:
	var only := ""
	for k: String in Game.flags:
		if k.begins_with("fx_only_"):
			only = k.substr(8)
	return only == "" or only == station


func _station(i: int) -> Vector3:
	return BASE + Vector3(STEP * float(i), 0.0, 0.0)


# --- stage -------------------------------------------------------------------------------------------

func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.name = "FxShotsStage"
	add_child(_stage)
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 6.0
	_env.glow_enabled = true
	_env.glow_normalized = false
	_env.glow_strength = 0.95
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	_env.glow_hdr_threshold = 1.05
	_env.glow_hdr_scale = 2.0
	var we := WorldEnvironment.new()
	we.environment = _env
	_stage.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 80.0
	_stage.add_child(_sun)
	_sun.rotation_degrees = Vector3(-48.0, 38.0, 0.0)
	_set_time(false)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 600.0
	_stage.add_child(_cam)
	_cam.current = true
	# one long ground slab under every station
	_solid(BASE + Vector3(STEP * 3.0, -0.5, 0.0), Vector3(STEP * 8.0, 1.0, 90.0), Color(0.6, 0.6, 0.58), "concrete")


func _set_time(night: bool) -> void:
	if night:
		_env.background_color = Color(0.015, 0.025, 0.06)
		_env.ambient_light_color = Color(0.35, 0.45, 0.8)
		_env.ambient_light_energy = 0.18
		_env.glow_intensity = 0.8
		_env.glow_bloom = 0.025
		_sun.light_color = Color(0.6, 0.7, 1.0)
		_sun.light_energy = 0.08
	else:
		_env.background_color = Color(0.5, 0.71, 0.9)
		_env.ambient_light_color = Color(0.72, 0.8, 0.95)
		_env.ambient_light_energy = 0.75
		_env.glow_intensity = 0.55
		_env.glow_bloom = 0.0
		_sun.light_color = Color(1.0, 0.95, 0.85)
		_sun.light_energy = 1.25


func _solid(center: Vector3, size: Vector3, color: Color, surface: String, dynamic: bool = false) -> PhysicsBody3D:
	var body: PhysicsBody3D
	if dynamic:
		var rb := RigidBody3D.new()
		rb.mass = 18.0
		rb.collision_layer = Layers.PROP
		rb.collision_mask = Layers.PROP_MASK
		body = rb
	else:
		body = StaticBody3D.new()
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
	mat.roughness = 0.9
	mesh.material = mat
	mi.mesh = mesh
	body.add_child(mi)
	_stage.add_child(body)
	body.global_position = center
	return body


## A 1.8 m figure for scale.
func _figure(feet: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.28
	mesh.height = 1.8
	mesh.radial_segments = 10
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.5, 0.36)
	mesh.material = mat
	mi.mesh = mesh
	_stage.add_child(mi)
	mi.global_position = feet + Vector3(0.0, 0.9, 0.0)


func _look(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at)


# --- stations ----------------------------------------------------------------------------------------

func _shot_decals(o: Vector3) -> void:
	_look(o + Vector3(0.0, 2.4, 2.6), o + Vector3(0.0, 0.0, -0.6))
	_solid(o + Vector3(0.0, 1.0, -3.2), Vector3(9.0, 2.0, 0.4), Color(0.72, 0.68, 0.6), "concrete")
	var x := -3.2
	for i in 5:
		Fx.decal(o + Vector3(x + float(i) * 0.38, 0.0, 1.2), Vector3.UP, "bullet", 0.18)
		Fx.decal(o + Vector3(-3.4 + float(i) * 0.5, 0.7 + 0.25 * float(i % 3), -3.0), Vector3.BACK, "bullet", 0.17)
	Fx.decal(o + Vector3(-2.3, 0.0, -0.4), Vector3.UP, "blood", 0.8)
	Fx.decal(o + Vector3(-0.8, 0.0, -0.3), Vector3.UP, "oil", 1.1)
	Fx.decal_oriented(o + Vector3(0.45, 0.0, -0.4), Vector3.UP, Vector3(0.25, 0.0, -1.0), "skid", 0.28, 2.6)
	Fx.decal_oriented(o + Vector3(0.95, 0.0, -0.3), Vector3.UP, Vector3(0.25, 0.0, -1.0), "skid", 0.28, 2.6)
	Fx.decal(o + Vector3(2.7, 0.0, -0.6), Vector3.UP, "scorch", 2.6)
	await TestHarness.wait_frames(4)
	await TestHarness.shot("fx_shots_decals")


func _shot_impacts(o: Vector3) -> void:
	_look(o + Vector3(0.0, 1.7, 6.2), o + Vector3(0.0, 1.15, 0.0))
	var surfaces := ["concrete", "metal", "wood", "dirt"]
	var colors := [Color(0.7, 0.69, 0.66), Color(0.36, 0.45, 0.56), Color(0.58, 0.4, 0.24), Color(0.45, 0.34, 0.24)]
	for i in 4:
		_solid(o + Vector3(-3.6 + 2.4 * float(i), 1.1, -0.2), Vector3(2.1, 2.2, 0.4), colors[i], surfaces[i])
	await TestHarness.wait_frames(3)
	for burst in 3:
		for i in 4:
			var p := o + Vector3(-3.6 + 2.4 * float(i) + (float(burst) - 1.0) * 0.55, 0.75 + 0.42 * float(burst), 0.0)
			Fx.impact(p, Vector3.BACK, surfaces[i], 1.0)
		await TestHarness.wait_seconds(0.11)
	await TestHarness.shot("fx_shots_impacts")
	await TestHarness.wait_seconds(1.1)
	await TestHarness.shot("fx_shots_impacts_marks")      # what the bullets leave behind


func _shot_muzzle(o: Vector3) -> void:
	_look(o + Vector3(1.6, 1.8, 3.4), o + Vector3(-2.4, 1.3, -0.6))
	_figure(o + Vector3(0.95, 0.0, -0.25))
	# a stand-in weapon: barrel along -X, so the Muzzle marker's -Z must point along -X
	var gun := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.7, 0.09, 0.07)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.13, 0.13, 0.15)
	gm.material = gmat
	gun.mesh = gm
	_stage.add_child(gun)
	gun.global_position = o + Vector3(0.25, 1.4, 0.0)
	var muzzle := Node3D.new()
	gun.add_child(muzzle)
	muzzle.position = Vector3(-0.36, 0.0, 0.0)
	muzzle.rotation.y = PI * 0.5        # -Z of the marker -> -X world
	var eject := Node3D.new()
	gun.add_child(eject)
	eject.position = Vector3(0.1, 0.05, 0.0)
	eject.rotation.y = PI * 0.5
	var target := _solid(o + Vector3(-9.0, 1.4, 0.0), Vector3(0.4, 2.8, 3.0), Color(0.36, 0.45, 0.56), "metal")
	await TestHarness.wait_frames(3)
	# a short automatic burst so shells / tracers of several ages are in the frame
	for i in 4:
		Fx.shell_eject(eject)
		Fx.tracer(muzzle.global_position, target.global_position + Vector3(0.21, randf_range(-0.6, 0.6), randf_range(-0.8, 0.8)))
		Fx.impact(target.global_position + Vector3(0.21, randf_range(-0.6, 0.6), randf_range(-0.8, 0.8)), Vector3.RIGHT, "metal", 1.0)
		Fx.muzzle_flash(muzzle, 1.0)
		if i < 3:
			await TestHarness.wait_seconds(0.085)
	await TestHarness.shot("fx_shots_muzzle")
	await TestHarness.wait_seconds(0.3)


func _shot_smoke(o: Vector3) -> void:
	_look(o + Vector3(0.0, 3.2, 12.5), o + Vector3(0.0, 2.6, 0.0))
	var kinds := ["light", "heavy", "black"]
	for i in 3:
		var car := _solid(o + Vector3(-5.0 + 5.0 * float(i), 0.6, 0.0), Vector3(1.9, 1.2, 3.6), Color(0.2, 0.5, 0.62), "metal")
		var h := Fx.attach_smoke(car, kinds[i])
		if h != null:
			h.position = Vector3(0.0, 0.65, -1.2)
	_figure(o + Vector3(-7.4, 0.0, 0.5))
	var rocket := Node3D.new()
	_stage.add_child(rocket)
	rocket.global_position = o + Vector3(-11.0, 5.2, -3.0)
	Fx.attach_trail(rocket, "rocket")
	var t := 0.0
	while t < 2.2:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		if t > 1.45:
			rocket.global_position += Vector3(26.0, 1.2, 0.0) * dt
	await TestHarness.shot("fx_shots_smoke")
	rocket.queue_free()
	await TestHarness.wait_frames(2)


func _shot_splash(o: Vector3) -> void:
	_look(o + Vector3(0.0, 2.6, 8.5), o + Vector3(0.0, 0.9, 0.0))
	var water := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(40.0, 0.1, 30.0)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.1, 0.42, 0.62)
	wmat.roughness = 0.25
	wm.material = wmat
	water.mesh = wm
	_stage.add_child(water)
	water.global_position = o + Vector3(0.0, 0.06, 0.0)
	var surface := o + Vector3(0.0, 0.12, 0.0)
	_figure(o + Vector3(-4.2, 0.0, 0.5))
	await TestHarness.wait_frames(3)
	Fx.splash(surface + Vector3(-0.8, 0.0, 0.0), 1.8)
	await TestHarness.wait_seconds(0.16)
	Fx.splash(surface + Vector3(2.6, 0.0, 0.8), 0.5)
	Fx.impact(surface + Vector3(3.6, 0.0, -0.4), Vector3.UP, "water", 1.0)
	Fx.water_ring(surface + Vector3(-3.0, 0.0, 2.0), 1.5)
	await TestHarness.wait_seconds(0.16)
	await TestHarness.shot("fx_shots_splash")
	await TestHarness.wait_seconds(0.4)


func _shot_explosion(o: Vector3) -> void:
	_look(o + Vector3(0.0, 3.4, 15.0), o + Vector3(0.0, 2.4, 0.0))
	_figure(o + Vector3(-6.0, 0.0, 1.0))
	_solid(o + Vector3(6.2, 0.6, -1.0), Vector3(1.9, 1.2, 3.6), Color(0.2, 0.5, 0.62), "metal")
	for i in 5:
		_solid(o + Vector3(-2.2 + 1.1 * float(i), 0.3, 1.6 - 0.5 * float(i % 2)), Vector3(0.6, 0.6, 0.6), Color(0.62, 0.44, 0.25), "wood", true)
	await TestHarness.wait_seconds(0.25)
	Fx.explosion(o + Vector3(0.0, 0.5, 0.0), 6.0, 160.0, null, {})
	await TestHarness.wait_seconds(0.04)
	await TestHarness.shot("fx_shots_explosion_1")
	await TestHarness.wait_seconds(0.2)
	await TestHarness.shot("fx_shots_explosion_2")
	await TestHarness.wait_seconds(0.8)
	await TestHarness.shot("fx_shots_explosion_3")
	await TestHarness.wait_seconds(0.3)


func _shot_fire_night(o: Vector3) -> void:
	_set_time(true)
	_look(o + Vector3(0.0, 2.0, 7.5), o + Vector3(0.0, 1.2, 0.0))
	_figure(o + Vector3(-2.6, 0.0, 0.4))
	_solid(o + Vector3(2.6, 0.6, -0.6), Vector3(1.9, 1.2, 3.6), Color(0.2, 0.5, 0.62), "metal")
	_solid(o + Vector3(0.0, 1.5, -3.5), Vector3(9.0, 3.0, 0.4), Color(0.72, 0.68, 0.6), "concrete")
	Fx.spawn_fire(o + Vector3(0.0, 0.0, 0.0), 6.0, null, 1.3)
	Fx.spawn_fire(o + Vector3(2.6, 1.2, 0.6), 6.0, null, 0.8)
	await TestHarness.wait_seconds(1.5)
	await TestHarness.shot("fx_shots_fire_night")
	_set_time(false)
