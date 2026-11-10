class_name PlayerStateVault
extends PlayerState
## Vault over low obstacles and mantle onto ledges (spec 10A "Traversal").
##
##   vault   top 0.45 - VAULT_MAX_HEIGHT (1.1 m) above the feet, obstacle at most VAULT_MAX_DEPTH
##           thick, free landing on the far side -> one-hand side vault, the run continues
##   mantle  top up to MANTLE_MAX_HEIGHT (2.0 m) with standing room on top (also low but deep
##           obstacles such as a table or a car bonnet) -> both hands on the ledge, pull up, stand
##
## Detection (probe()) uses ray casts against Layers.WORLD | VEHICLE | PROP when the jump key is
## pressed towards an obstacle (on foot) or when a jump carries the player into a wall (air state,
## ledge <= AIR_MAX_RISE above the feet). Moving vehicles are never vaulted.
## Motion: a procedural piecewise curve (rise -> over -> drop / hang -> pull -> step), collision off,
## animator state "vault" with motion_t / motion_style / motion_height (hands planted on the top).

const VAULT_MIN_HEIGHT := 0.45          ## lower = a step / plain jump
const VAULT_MAX_HEIGHT := 1.1
const MANTLE_MAX_HEIGHT := 2.0
const AIR_MAX_RISE := 1.5               ## ledge above the current feet when grabbing it from a jump
const VAULT_MAX_DEPTH := 1.25           ## thicker obstacles are mantled (climbed onto) instead
const REACH := 0.85                     ## front face at most this far beyond the capsule
const PROBE_MASK := Layers.WORLD | Layers.VEHICLE | Layers.PROP
const VAULT_TIME := 0.62
const MANTLE_TIME := 0.78
const MIN_EXIT_SPEED := 3.0

var kind: String = "vault"
var data: Dictionary = {}

var _t: float = 0.0
var _dur: float = 0.6
var _dir: Vector3 = Vector3.FORWARD
var _a: Vector3
var _b: Vector3
var _c: Vector3
var _d: Vector3
var _top_y: float = 0.0
var _exit_speed: float = 3.0
var _drop_after: bool = false
var _prev_pos: Vector3
var _planted: bool = false
var _ray: PhysicsRayQueryParameters3D = null
var _shape_q: PhysicsShapeQueryParameters3D = null
var _capsule: CapsuleShape3D = null
var _box: BoxShape3D = null


func _init() -> void:
	public_name = "vault"


# =================================================================================================
# detection
# =================================================================================================

## What is in front of the player along `dir` (horizontal unit vector)? `max_rise` = highest top
## above the feet that counts. Returns {} or {"kind": "vault"|"mantle", "top_y", "rise", "wall",
## "far" (vault: point past the obstacle at top height), "land" (vault landing / mantle stand point),
## "drop" (vault: landing is a fall), "dir"}.
func probe(dir: Vector3, max_rise: float = MANTLE_MAX_HEIGHT) -> Dictionary:
	var p := player
	if p == null or not p.is_inside_tree():
		return {}
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return {}
	dir = dir.normalized()
	var feet := p.global_position
	var space := p.get_world_3d().direct_space_state
	_ensure_queries(p)
	# 1) a front face at knee and at waist height (thin rails and kerbs differ)
	var reach := Player.CAPSULE_RADIUS + REACH
	var hit := _ray_hit(space, feet + Vector3(0.0, 0.42, 0.0), feet + Vector3(0.0, 0.42, 0.0) + dir * reach)
	if hit.is_empty():
		hit = _ray_hit(space, feet + Vector3(0.0, 0.85, 0.0), feet + Vector3(0.0, 0.85, 0.0) + dir * reach)
		if hit.is_empty():
			return {}
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.5 or n.dot(-dir) < 0.45:
		return {}
	if _is_moving_body(hit.get("collider", null)):
		return {}
	var wall: Vector3 = hit["position"]
	# 2) the top: rays down a little behind the front face
	var top_y := -INF
	for inset: float in [0.12, 0.30]:
		var x := wall + dir * inset
		var top_hit := _ray_hit(space, Vector3(x.x, feet.y + max_rise + 0.35, x.z), Vector3(x.x, feet.y + 0.25, x.z))
		if not top_hit.is_empty() and (top_hit["normal"] as Vector3).y > 0.7:
			top_y = maxf(top_y, (top_hit["position"] as Vector3).y)
	if top_y == -INF:
		return {}
	var rise := top_y - feet.y
	if rise < VAULT_MIN_HEIGHT or rise > max_rise:
		return {}
	# the space just above the top edge must be free (no wall continuing upwards)
	if not _box_free(space, wall + dir * 0.35 + Vector3(0.0, top_y - wall.y + 0.55, 0.0), Vector3(0.5, 0.8, 0.5)):
		return {}
	# 3) depth of the obstacle: where does the top end?
	var depth := INF
	var far_ground := -INF
	var s := 0.35
	while s <= VAULT_MAX_DEPTH + 0.36:
		var q := wall + dir * s
		var down := _ray_hit(space, Vector3(q.x, top_y + 0.3, q.z), Vector3(q.x, feet.y - 2.5, q.z))
		var y := -INF if down.is_empty() else (down["position"] as Vector3).y
		if y < top_y - 0.3:
			depth = s
			far_ground = y
			break
		s += 0.15
	if rise <= VAULT_MAX_HEIGHT and depth <= VAULT_MAX_DEPTH:
		# vault: land a little past the far edge
		var land_xz := wall + dir * (depth + 0.55)
		var ground := _ray_hit(space, Vector3(land_xz.x, top_y + 0.3, land_xz.z), Vector3(land_xz.x, feet.y - 4.0, land_xz.z))
		var drop := ground.is_empty()
		var land_y := feet.y - 4.0 if drop else (ground["position"] as Vector3).y
		var land := Vector3(land_xz.x, land_y, land_xz.z)
		if not drop and not _capsule_free(space, land + Vector3(0.0, 0.08, 0.0)):
			return {}
		var far := Vector3((wall + dir * depth).x, top_y, (wall + dir * depth).z)
		return {"kind": "vault", "top_y": top_y, "rise": rise, "wall": wall, "far": far, "land": land,
				"drop": drop or land_y < feet.y - 1.6, "dir": dir, "depth": depth, "far_ground": far_ground}
	# mantle: standing room on top
	var stand := wall + dir * 0.45
	stand.y = top_y
	if not _capsule_free(space, stand + Vector3(0.0, 0.04, 0.0)):
		return {}
	return {"kind": "mantle", "top_y": top_y, "rise": rise, "wall": wall, "land": stand, "drop": false, "dir": dir}


func _ensure_queries(p: Player) -> void:
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.collision_mask = PROBE_MASK
		_ray.hit_back_faces = false
	_ray.exclude = [p.get_rid()]
	if _shape_q == null:
		_shape_q = PhysicsShapeQueryParameters3D.new()
		_shape_q.collision_mask = PROBE_MASK
		_capsule = CapsuleShape3D.new()
		_capsule.radius = Player.CAPSULE_RADIUS - 0.03
		_capsule.height = Player.STAND_HEIGHT - 0.1
		_box = BoxShape3D.new()
	_shape_q.exclude = [p.get_rid()]


func _ray_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	return space.intersect_ray(_ray)


func _capsule_free(space: PhysicsDirectSpaceState3D, feet: Vector3) -> bool:
	_shape_q.shape = _capsule
	_shape_q.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0.0, _capsule.height * 0.5 + 0.02, 0.0))
	return space.intersect_shape(_shape_q, 1).is_empty()


func _box_free(space: PhysicsDirectSpaceState3D, centre: Vector3, size: Vector3) -> bool:
	_box.size = size
	_shape_q.shape = _box
	_shape_q.transform = Transform3D(Basis.IDENTITY, centre)
	return space.intersect_shape(_shape_q, 1).is_empty()


func _is_moving_body(collider: Variant) -> bool:
	if collider is RigidBody3D and is_instance_valid(collider):
		return (collider as RigidBody3D).linear_velocity.length() > 1.0
	return false


# =================================================================================================
# motion
# =================================================================================================

func enter(_previous: String, args: Dictionary) -> void:
	var p := player
	data = args.get("data", {})
	kind = str(data.get("kind", "vault"))
	_dir = data.get("dir", -p.global_basis.z)
	_top_y = float(data.get("top_y", p.global_position.y + 1.0))
	var wall: Vector3 = data.get("wall", p.global_position + _dir * 0.6)
	var land: Vector3 = data.get("land", wall + _dir)
	_drop_after = bool(data.get("drop", false))
	var rise := float(data.get("rise", 1.0))
	_t = 0.0
	_planted = false
	_a = p.global_position
	var planar := Vector2(p.velocity.x, p.velocity.z).length()
	_exit_speed = maxf(planar, MIN_EXIT_SPEED)
	p.is_sprinting = false
	p.noise_radius = 0.0
	p.set_aiming(false)
	p.release_trigger()
	if p.is_crouching:
		p.set_crouching(false, true)
	p.set_collision_enabled(false)
	var wall_flat := Vector3(wall.x, _a.y, wall.z)
	if kind == "vault":
		var far: Vector3 = data.get("far", wall + _dir * 0.3)
		_dur = VAULT_TIME + rise * 0.10
		# origin ~0.3 below the top while passing over it: the tucked feet clear the edge
		_b = Vector3(wall_flat.x, _top_y - 0.28, wall_flat.z) - _dir * 0.15
		_c = Vector3(far.x, _top_y - 0.26, far.z) + _dir * 0.05
		if _drop_after:
			_d = _c + _dir * 0.65 + Vector3(0.0, -0.45, 0.0)
		else:
			_d = land
	else:
		_dur = MANTLE_TIME + rise * 0.22
		_b = wall_flat - _dir * (Player.CAPSULE_RADIUS + 0.04)
		_b.y = maxf(_a.y, _top_y - 1.35)
		_c = Vector3(wall_flat.x, _top_y + 0.02, wall_flat.z) - _dir * 0.10
		_d = land
	_prev_pos = _a
	if p.animator != null:
		p.animator.motion_style = HumanoidAnimator.MOTION_MANTLE if kind == "mantle" else HumanoidAnimator.MOTION_VAULT
		p.animator.motion_t = 0.0
		p.animator.motion_height = _top_y - _a.y
		p.animator.stop_action()
	p.set_anim_state("vault", 0.10)
	p.velocity = Vector3.ZERO
	Audio.play_at("footstep_concrete", _a, -6.0, 0.9, 25.0)
	p.emit_noise(4.0, "footstep")


func exit(_next: String) -> void:
	var p := player
	if p.animator != null:
		p.animator.motion_t = -1.0
		p.animator.motion_height = 0.0
	if not p.is_dead:
		p.set_collision_enabled(true)


func get_focus_position() -> Vector3:
	return player.global_position


func physics_update(delta: float) -> void:
	var p := player
	_t += delta
	var u := clampf(_t / maxf(_dur, 0.01), 0.0, 1.0)
	var pos := _sample(u)
	p.global_position = pos
	p.turn_toward(atan2(-_dir.x, -_dir.z), 18.0, delta)
	p.velocity = (pos - _prev_pos) / maxf(delta, 0.0001)
	_prev_pos = pos
	if p.animator != null:
		p.animator.motion_t = u
		p.animator.motion_height = _top_y - pos.y
	if not _planted and u > (0.25 if kind == "vault" else 0.15):
		_planted = true
		Audio.play_at("footstep_concrete", Vector3(pos.x, _top_y, pos.z), -8.0, 1.15, 20.0)
	if u >= 1.0:
		_finish()


func _sample(u: float) -> Vector3:
	if kind == "vault":
		if u < 0.3:
			var k := u / 0.3
			var e := 1.0 - (1.0 - k) * (1.0 - k)            # ease out: spring up
			return _a.lerp(_b, k) + Vector3(0.0, (_b.y - _a.y) * (e - k), 0.0)
		if u < 0.7:
			var k2 := (u - 0.3) / 0.4
			return _b.lerp(_c, k2) + Vector3(0.0, sin(PI * k2) * 0.06, 0.0)
		var k3 := (u - 0.7) / 0.3
		var e3 := k3 * k3                                  # ease in: drop onto the far side
		var out := _c.lerp(_d, k3)
		out.y = lerpf(_c.y, _d.y, e3)
		return out
	# mantle: hang -> pull up -> step onto the top
	if u < 0.2:
		var m := u / 0.2
		var em := m * m * (3.0 - 2.0 * m)
		return _a.lerp(_b, em)
	if u < 0.72:
		var m2 := (u - 0.2) / 0.52
		var em2 := m2 * m2 * (3.0 - 2.0 * m2)
		var o := _b.lerp(_c, em2 * 0.35)
		o.y = lerpf(_b.y, _c.y, em2)
		return o
	var m3 := (u - 0.72) / 0.28
	var em3 := m3 * m3 * (3.0 - 2.0 * m3)
	return _b.lerp(_c, 0.35).lerp(_d, em3) if m3 < 1.0 else _d


func _finish() -> void:
	var p := player
	p.set_collision_enabled(true)
	if kind == "vault" and _drop_after:
		p.velocity = _dir * _exit_speed * 0.8 + Vector3(0.0, -1.0, 0.0)
		p.change_state("air", {})
		return
	p.global_position = _d + Vector3(0.0, 0.02, 0.0)
	if kind == "vault":
		p.velocity = _dir * _exit_speed
		Audio.play_at("jump_land", p.global_position, -10.0, 1.1, 25.0)
	else:
		p.velocity = Vector3.ZERO
	p.update_water()
	if p.water_depth > Player.SWIM_ENTER_DEPTH:
		p.change_state("swim", {"entry_speed": 2.0})
		return
	p.change_state("on_foot", {"landed": 3.0 if kind == "vault" else 0.0})
