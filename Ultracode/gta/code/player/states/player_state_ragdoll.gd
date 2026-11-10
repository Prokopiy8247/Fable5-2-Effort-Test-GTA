class_name PlayerStateRagdoll
extends PlayerState
## Knocked down: the visual is replaced by a physical ragdoll for a moment, then the character
## blends out of the ragdoll pose, gets up and control returns.
## If no ragdoll can be built (no model yet, cap reached) the lying pose of the animator is used.

enum { DOWN, GET_UP }

var rag: Ragdoll = null
var phase: int = DOWN

var _t: float = 0.0
var _duration: float = 2.0
var _slide: Vector3 = Vector3.ZERO
var _stood: bool = false


func _init() -> void:
	public_name = "ragdoll"


func enter(_previous: String, args: Dictionary) -> void:
	var p := player
	phase = DOWN
	_t = 0.0
	_stood = false
	_duration = maxf(float(args.get("duration", 2.0)), 0.4)
	var impulse: Vector3 = args.get("impulse", Vector3.ZERO)
	var hit_pos: Vector3 = args.get("position", Vector3.INF)
	p.is_sprinting = false
	p.noise_radius = 0.0
	p.set_aiming(false)
	p.release_trigger()
	if p.is_crouching:
		p.set_crouching(false, true)
	p.set_collision_enabled(false)
	_slide = p.velocity + impulse / Ragdoll.TOTAL_MASS
	rag = p.spawn_ragdoll(impulse, hit_pos)
	if rag == null:
		p.set_anim_state("dead", 0.25)
	Audio.play_at("body_fall", p.global_position, -3.0, 1.0)
	p.velocity = Vector3.ZERO


func exit(_next: String) -> void:
	var p := player
	if _next != "dead":
		p.clear_ragdoll()
		rag = null
	if not p.is_dead:
		p.set_collision_enabled(true)


func get_focus_position() -> Vector3:
	if rag != null and is_instance_valid(rag):
		return rag.get_pelvis_position() - Vector3(0.0, 0.25, 0.0)
	return player.global_position


func physics_update(delta: float) -> void:
	var p := player
	_t += delta
	if phase == GET_UP:
		p.velocity = Vector3.ZERO
		if not _stood and _t > Player.GET_UP_TIME * 0.5:
			_stood = true
			p.set_anim_state("idle")
		if _t >= Player.GET_UP_TIME:
			p.update_water()
			p.change_state("swim" if p.water_depth > Player.SWIM_ENTER_DEPTH else "on_foot", {})
		return

	if rag != null and is_instance_valid(rag):
		var pelvis := rag.get_pelvis_position()
		p.global_position = pelvis - Vector3(0.0, 0.25, 0.0)
		# a ragdoll that fell into the sea: start swimming instead of drowning as a puppet
		if Game.is_in_water(pelvis + Vector3(0.0, 0.3, 0.0)) and _t > 0.5:
			_stand_up(true)
			return
		if _t >= _duration and (rag.is_settled() or _t > _duration + 2.5):
			_stand_up(false)
		elif pelvis.y < Player.VOID_Y:
			_stand_up(false)
			p.recover_from_void()
	else:
		# no physical ragdoll: slide to a stop in the lying pose
		_slide = _slide.move_toward(Vector3.ZERO, 9.0 * delta)
		_slide.y = 0.0
		p.global_position += _slide * delta
		if _t >= _duration:
			_stand_up(false)


func _stand_up(into_water: bool) -> void:
	var p := player
	var feet := p.global_position
	var yaw := p.rotation.y
	if rag != null and is_instance_valid(rag):
		var pelvis := rag.get_pelvis_position()
		yaw = rag.get_stand_yaw()
		feet = pelvis
		if not into_water:
			var space := p.get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(pelvis + Vector3(0.0, 0.6, 0.0), pelvis + Vector3(0.0, -3.0, 0.0), Layers.GROUND_MASK)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				feet = hit["position"]
			else:
				feet = pelvis - Vector3(0.0, 0.2, 0.0)
	p.global_position = feet
	p.rotation = Vector3(0.0, yaw, 0.0)
	p.velocity = Vector3.ZERO
	if into_water:
		p.clear_ragdoll()
		rag = null
		p.set_collision_enabled(true)
		p.update_water()
		p.change_state("swim", {"entry_speed": 2.0})
		return
	# blend out of the ragdoll pose into a crouch, then stand
	p.blend_out_of_ragdoll(Player.GET_UP_TIME * 0.6)
	rag = null
	p.set_collision_enabled(true)
	phase = GET_UP
	_t = 0.0
	_stood = false
