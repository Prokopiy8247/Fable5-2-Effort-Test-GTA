extends PlayerState
## Player state "int_sit" (interactions system): sitting on a bench / bus-stop / tram-stop bench or
## a picnic-table seat. Registered at runtime through the documented extension point
## Player.register_state() (docs/PLAYER.md "Adding a state"); the interactions system loads this
## script with load() + can_instantiate(), so a broken file only disables sitting.
##
## enter args: {"seat": Transform3D (ground point under the hips, -Z = the way the sitter faces),
##              "height": float (hip height above that point), "stand": Vector3 (where to stand up),
##              "point": int (interaction point index, for the system)}
## Leaves on: the "Stand up" use prompt (the system calls stand_up()), movement / jump input held for
## a moment, any damage, a vehicle coming close fast. Collision is off while seated (like the NPC
## bench pose), the body sits at hip height and the animator uses the seated pose with bench tuning
## (same numbers as NpcBase.BENCH_*).

const BENCH_PEDAL := Vector3(0.13, -0.38, -0.30)
const BENCH_WHEEL := Vector3(0.0, -0.02, -0.24)
const BENCH_WHEEL_RADIUS := 0.15
const LEAVE_INPUT_TIME := 0.22          ## s of held movement input before standing up
const DANGER_RADIUS := 4.5              ## a vehicle this close and faster than DANGER_SPEED -> jump up
const DANGER_SPEED := 3.0

var seat: Transform3D = Transform3D.IDENTITY
var stand_pos: Vector3 = Vector3.ZERO
var point_index: int = -1
var seated_time: float = 0.0

var _saved_anim: Dictionary = {}
var _leave_t: float = 0.0
var _danger_t: float = 0.0


func _init() -> void:
	public_name = "sitting"


func enter(_previous: String, args: Dictionary) -> void:
	var p := player
	seat = args.get("seat", Transform3D(Basis.IDENTITY, p.global_position))
	var h := float(args.get("height", 0.41))
	stand_pos = args.get("stand", seat.origin)
	point_index = int(args.get("point", -1))
	seated_time = 0.0
	_leave_t = 0.0
	_danger_t = 0.0
	p.is_sprinting = false
	p.set_aiming(false)
	p.release_trigger()
	if p.is_crouching:
		p.set_crouching(false, true)
	if p.in_stealth:
		p.set_stealth(false)
	p.set_collision_enabled(false)
	p.velocity = Vector3.ZERO
	p.noise_radius = 0.0
	var f := -seat.basis.z
	f.y = 0.0
	var yaw := atan2(-f.x, -f.z) if f.length_squared() > 0.0001 else p.global_rotation.y
	p.global_position = seat.origin + Vector3(0.0, h, 0.0)
	p.global_rotation = Vector3(0.0, yaw, 0.0)
	var a: HumanoidAnimator = p.animator
	if a != null:
		_saved_anim = {"pedal_pos": a.get("pedal_pos"), "wheel_pos": a.get("wheel_pos"),
				"wheel_radius": a.get("wheel_radius")}
		a.set("pedal_pos", BENCH_PEDAL)
		a.set("wheel_pos", BENCH_WHEEL)
		a.set("wheel_radius", BENCH_WHEEL_RADIUS)
		a.stop_action()
	p.set_anim_state("seated_car", 0.25)


func exit(_next: String) -> void:
	var p := player
	var a: HumanoidAnimator = p.animator
	if a != null:
		for k: String in _saved_anim:
			if _saved_anim[k] != null:
				a.set(k, _saved_anim[k])
	_saved_anim = {}
	# back on the ground in front of the seat (never inside the bench collider) - unless something
	# already moved the player away (teleport / respawn / load call _place() before change_state)
	if p.global_position.distance_to(seat.origin) < 1.2:
		p.global_position = stand_pos
	p.velocity = Vector3.ZERO
	p.set_collision_enabled(true)
	point_index = -1


func physics_update(delta: float) -> void:
	var p := player
	seated_time += delta
	p.velocity = Vector3.ZERO
	p.set_anim_state("seated_car")
	# stand up when the player clearly wants to move
	var mv: Vector2 = p.get_move_input()
	if mv.length() > 0.5 or p.pressed(&"jump"):
		_leave_t += delta
		if _leave_t >= LEAVE_INPUT_TIME and seated_time > 0.4:
			p.change_state("on_foot", {})
			return
	else:
		_leave_t = 0.0
	# a car mounting the kerb: jump up instead of being sat on
	_danger_t -= delta
	if _danger_t <= 0.0:
		_danger_t = 0.25
		if _vehicle_threat():
			p.change_state("on_foot", {})
			return
	p.stamina = minf(p.stamina + delta / 4.0, 1.0)


func update_animator(a: HumanoidAnimator) -> void:
	a.aim_weight = 0.0
	a.speed = 0.0


func on_damage(_info: Dictionary, _amount: float) -> void:
	if player.state == self:
		player.change_state("on_foot", {})


func get_focus_position() -> Vector3:
	return player.global_position - Vector3(0.0, 0.3, 0.0)


func _vehicle_threat() -> bool:
	var pos := player.global_position
	for n: Node in player.get_tree().get_nodes_in_group("vehicle"):
		var v := n as RigidBody3D
		if v == null or not v.is_inside_tree():
			continue
		if v.global_position.distance_squared_to(pos) > DANGER_RADIUS * DANGER_RADIUS * 4.0:
			continue
		var rel := pos - v.global_position
		var vel := v.linear_velocity
		if vel.length() < DANGER_SPEED:
			continue
		rel.y = 0.0
		# closing in and the path passes near the seat within ~1.2 s
		var t := clampf(rel.dot(vel) / maxf(vel.length_squared(), 0.01), 0.0, 1.2)
		var closest := v.global_position + vel * t
		if Vector2(closest.x - pos.x, closest.z - pos.z).length() < 2.2:
			return true
	return false
