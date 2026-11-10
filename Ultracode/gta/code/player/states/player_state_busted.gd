class_name PlayerStateBusted
extends PlayerState
## Arrested (W2.5): hands up, no control, until the respawn system releases the player at the
## police station (Player.respawn). Entered through Player.arrest(); the vehicle is left first.
## When no (enabled) respawn system runs its arrest flow, the state releases the player itself after
## FALLBACK_TIME seconds.

const FALLBACK_TIME := 6.0

var _t: float = 0.0


func _init() -> void:
	public_name = "busted"


func enter(_previous: String, _args: Dictionary) -> void:
	var p := player
	_t = 0.0
	p.is_sprinting = false
	p.noise_radius = 0.0
	p.set_aiming(false)
	p.release_trigger()
	if p.is_crouching:
		p.set_crouching(false, true)
	p.set_collision_enabled(true)
	p.velocity.x = 0.0
	p.velocity.z = 0.0
	if p.animator != null:
		p.animator.stop_action()
	p.set_anim_state("surrender", 0.3)


func physics_update(delta: float) -> void:
	var p := player
	_t += delta
	# stand still (gravity only)
	p.velocity.x = move_toward(p.velocity.x, 0.0, 20.0 * delta)
	p.velocity.z = move_toward(p.velocity.z, 0.0, 20.0 * delta)
	if p.grounded:
		p.velocity.y = minf(p.velocity.y, 0.0)
	else:
		p.velocity.y = maxf(p.velocity.y - Player.GRAVITY * delta, -Player.TERMINAL_SPEED)
	p.move_body(delta)
	p.set_anim_state("surrender")
	if _t >= FALLBACK_TIME and not _respawn_handles_arrest():
		p.respawn(Game.get_location("police_station"))


## The respawn system is active and running its arrest flow (review fix: without this check an
## arrest() that did not come through EventBus.player_busted, or a disabled respawn system, left the
## player with the hands up for good).
static func _respawn_handles_arrest() -> bool:
	var rs := Game.get_system("respawn")
	if rs == null or not is_instance_valid(rs) or rs.get("enabled") == false:
		return false
	return str(rs.get("flow")) == "busted"
