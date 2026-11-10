extends Node3D
## ENVIRONMENT module helper: rain presentation around the active camera.
##  - one camera-following GPUParticles3D (MAX_DROPS <= 1500 streaks, scaled by rain intensity
##    through amount_ratio, world-space so the drops do not follow camera motion)
##  - a small camera-following GPUParticlesCollisionHeightField3D so drops stop at roofs,
##    canopies and vehicles (no rain inside walk-in interiors); only active while it rains
##  - splash rings on the ground near the camera: one MultiMesh (MAX_SPLASHES instances) placed
##    by a few physics rays per frame, animated in the shader
## Created and driven by EnvironmentSystem. Everything is off (no draw calls) in dry weather.

const RAIN_SHADER: Shader = preload("res://gta/code/world/shaders/env_rain.gdshader")
const SPLASH_SHADER: Shader = preload("res://gta/code/world/shaders/env_rain_splash.gdshader")

const MAX_DROPS := 1400
const DROP_LIFETIME := 0.62
const DROP_SPEED := 21.0
const BOX_HALF := Vector3(11.5, 1.0, 11.5)
const BOX_HEIGHT := 9.0                 ## spawn height above the camera
const MAX_SPLASHES := 128
const SPLASH_RADIUS := 11.0
const SPLASH_LIFETIME := 0.34
const SPLASHES_PER_SECOND := 240.0      ## at full intensity
const MAX_RAYS_PER_TICK := 8
const HEIGHTFIELD_SNAP := 4.0

var particles: GPUParticles3D
var collider: GPUParticlesCollisionHeightField3D
var splash_mmi: MultiMeshInstance3D

var _process_mat: ParticleProcessMaterial
var _streak_mat: ShaderMaterial
var _splash_mat: ShaderMaterial
var _splash_mm: MultiMesh
var _splash_cursor: int = 0
var _splash_debt: float = 0.0
var _intensity: float = 0.0
var _cam_pos := Vector3.ZERO
var _cam_forward := Vector3.FORWARD
var _time_s: float = 0.0
var _rng := RandomNumberGenerator.new()
var _use_collision: bool = true
var _query: PhysicsRayQueryParameters3D      ## reused by the splash rays (no per-tick allocation)


func _ready() -> void:
	_build()


func _build() -> void:
	if particles != null:
		return
	# The environment system runs with PROCESS_MODE_ALWAYS (the look must follow the admin menu
	# while the game is paused). Rain itself must freeze with the world: PAUSABLE stops the
	# particle simulation and the splash rays while the tree is paused.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.seed = 90210
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = Layers.WORLD | Layers.VEHICLE
	_query.collide_with_areas = false
	_use_collision = not Game.flags.has("no_rain_collision")

	# --- streaks -----------------------------------------------------------------------------
	_process_mat = ParticleProcessMaterial.new()
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_mat.emission_box_extents = BOX_HALF
	_process_mat.direction = Vector3(0.0, -1.0, 0.0)
	_process_mat.spread = 2.0
	_process_mat.initial_velocity_min = DROP_SPEED * 0.9
	_process_mat.initial_velocity_max = DROP_SPEED * 1.1
	_process_mat.gravity = Vector3.ZERO
	_process_mat.scale_min = 0.8
	_process_mat.scale_max = 1.25
	if _use_collision:
		_process_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT

	_streak_mat = ShaderMaterial.new()
	_streak_mat.shader = RAIN_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.78)
	quad.material = _streak_mat

	particles = GPUParticles3D.new()
	particles.name = "RainStreaks"
	particles.amount = MAX_DROPS
	particles.lifetime = DROP_LIFETIME
	particles.preprocess = DROP_LIFETIME
	particles.local_coords = false
	particles.fixed_fps = 0
	particles.interpolate = false
	particles.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	particles.process_material = _process_mat
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-20.0, -22.0, -20.0), Vector3(40.0, 36.0, 40.0))
	particles.emitting = false
	particles.visible = false
	add_child(particles)

	# --- roof / canopy occlusion -------------------------------------------------------------
	if _use_collision:
		collider = GPUParticlesCollisionHeightField3D.new()
		collider.name = "RainHeightField"
		collider.size = Vector3(40.0, 48.0, 40.0)
		collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
		collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
		collider.visible = false
		add_child(collider)

	# --- splash rings ------------------------------------------------------------------------
	_splash_mat = ShaderMaterial.new()
	_splash_mat.shader = SPLASH_SHADER
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.36, 0.36)
	plane.material = _splash_mat
	_splash_mm = MultiMesh.new()
	_splash_mm.transform_format = MultiMesh.TRANSFORM_3D
	_splash_mm.use_custom_data = true
	_splash_mm.mesh = plane
	_splash_mm.instance_count = MAX_SPLASHES
	for i in MAX_SPLASHES:
		_splash_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, -1000.0, 0.0)))
		_splash_mm.set_instance_custom_data(i, Color(-100.0, SPLASH_LIFETIME, 0.0, 0.0))
	splash_mmi = MultiMeshInstance3D.new()
	splash_mmi.name = "RainSplashes"
	splash_mmi.multimesh = _splash_mm
	splash_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	splash_mmi.custom_aabb = AABB(Vector3(-20000.0, -200.0, -20000.0), Vector3(40000.0, 1200.0, 40000.0))
	splash_mmi.top_level = true
	splash_mmi.visible = false
	add_child(splash_mmi)
	splash_mmi.global_transform = Transform3D.IDENTITY
	set_physics_process(false)


## Called every frame by EnvironmentSystem.
## `color` is the streak colour for the current light, `flash` the lightning pulse (0..1).
func update_rain(cam: Camera3D, time_s: float, intensity: float, wind: Vector3, color: Color,
		flash: float, underwater: bool) -> void:
	if particles == null:
		return
	_time_s = time_s
	_intensity = 0.0 if underwater else clampf(intensity, 0.0, 1.0)
	var active := _intensity > 0.02 and cam != null
	if particles.emitting != active:
		particles.emitting = active
	if particles.visible != active:
		particles.visible = active
	if collider != null and collider.visible != active:
		collider.visible = active
	if splash_mmi.visible != active:
		splash_mmi.visible = active
	set_physics_process(active)
	if not active:
		return
	_cam_pos = cam.global_position
	_cam_forward = -cam.global_transform.basis.z
	var ahead := Vector3(_cam_forward.x, 0.0, _cam_forward.z) * 6.0
	# The emitter sits upwind so slanted drops still pass through the view.
	var slant := Vector3(wind.x, 0.0, wind.z) * 0.32
	var fall_dir := (Vector3(0.0, -1.0, 0.0) + slant).normalized()
	particles.global_position = _cam_pos + ahead + Vector3(0.0, BOX_HEIGHT, 0.0) - slant * BOX_HEIGHT
	_process_mat.direction = fall_dir
	particles.amount_ratio = clampf(0.12 + _intensity * 0.95, 0.0, 1.0)
	_streak_mat.set_shader_parameter(&"streak_color", color)
	_streak_mat.set_shader_parameter(&"opacity", lerpf(0.45, 0.72, _intensity))
	_streak_mat.set_shader_parameter(&"flash", flash)
	_splash_mat.set_shader_parameter(&"splash_color", color.lightened(0.12))
	if collider != null:
		var snapped_pos := Vector3(snappedf(_cam_pos.x + ahead.x, HEIGHTFIELD_SNAP),
				snappedf(_cam_pos.y, HEIGHTFIELD_SNAP), snappedf(_cam_pos.z + ahead.z, HEIGHTFIELD_SNAP))
		if not collider.global_position.is_equal_approx(snapped_pos):
			collider.global_position = snapped_pos


func _physics_process(delta: float) -> void:
	if _intensity <= 0.02 or _splash_mm == null:
		return
	_splash_debt += SPLASHES_PER_SECOND * _intensity * delta
	var rays := mini(int(_splash_debt), MAX_RAYS_PER_TICK)
	if rays <= 0:
		return
	_splash_debt = minf(_splash_debt - float(rays), float(MAX_RAYS_PER_TICK))
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	var centre := _cam_pos + Vector3(_cam_forward.x, 0.0, _cam_forward.z) * 5.0
	var query := _query
	for i in rays:
		var ang := _rng.randf() * TAU
		var rad := sqrt(_rng.randf()) * SPLASH_RADIUS
		var px := centre.x + cos(ang) * rad
		var pz := centre.z + sin(ang) * rad
		query.from = Vector3(px, _cam_pos.y + 30.0, pz)
		query.to = Vector3(px, _cam_pos.y - 40.0, pz)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var pos: Vector3 = hit["position"]
		var nrm: Vector3 = hit["normal"]
		# No rings on steep faces, and none on the sea bed (the ocean shader draws its own).
		if nrm.y < 0.55 or pos.y < Game.WATER_LEVEL + 0.03:
			continue
		var bx := nrm.cross(Vector3.FORWARD)
		if bx.length_squared() < 0.001:
			bx = Vector3.RIGHT
		bx = bx.normalized()
		var bz := bx.cross(nrm).normalized()
		var s := _rng.randf_range(0.7, 1.35)
		var xf := Transform3D(Basis(bx * s, nrm, bz * s), pos)
		_splash_mm.set_instance_transform(_splash_cursor, xf)
		_splash_mm.set_instance_custom_data(_splash_cursor,
				Color(_time_s, SPLASH_LIFETIME * _rng.randf_range(0.8, 1.3), _rng.randf(), 0.0))
		_splash_cursor = (_splash_cursor + 1) % MAX_SPLASHES
