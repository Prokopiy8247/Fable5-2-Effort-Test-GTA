class_name PlayerStateDead
extends PlayerState
## Dead: ragdoll, no control. The `respawn` system (BootManifest) owns what happens next; when
## that system does not exist this state runs a built-in fallback: original "DOWN" banner, fade,
## respawn at Game.get_location("hospital") after RESPAWN_DELAY seconds with the wanted level
## cleared.

var rag: Ragdoll = null

var _t: float = 0.0
var _fallback: bool = false
var _faded: bool = false
var _done: bool = false


func _init() -> void:
	public_name = "dead"


func enter(_previous: String, args: Dictionary) -> void:
	var p := player
	_t = 0.0
	_faded = false
	_done = false
	p.is_sprinting = false
	p.set_aiming(false)                 # through the setter: the inventory must drop its aim too
	p.noise_radius = 0.0
	p.release_trigger()
	if p.is_crouching:
		p.set_crouching(false, true)
	p.set_collision_enabled(false)
	var impulse: Vector3 = args.get("impulse", Vector3.ZERO)
	var hit_pos: Vector3 = args.get("position", Vector3.INF)
	rag = p.get_active_ragdoll()
	if rag == null:
		rag = p.spawn_ragdoll(impulse, hit_pos)
	elif impulse.length_squared() > 1.0:
		rag.apply_impulse_at(impulse, hit_pos)
	if rag == null:
		p.set_anim_state("dead", 0.3)
	p.velocity = Vector3.ZERO
	_fallback = not _respawn_system_active()
	if _fallback:
		UI.banner("DOWN", "", Color(0.95, 0.36, 0.30), Player.RESPAWN_DELAY - 0.8)


func exit(_next: String) -> void:
	player.clear_ragdoll()
	rag = null


func get_focus_position() -> Vector3:
	if rag != null and is_instance_valid(rag):
		return rag.get_pelvis_position() - Vector3(0.0, 0.25, 0.0)
	return player.global_position


## The `respawn` system exists AND is enabled (review fix: an admin-disabled respawn system used to
## leave the player dead for good, because this fallback only ran when the system was missing).
static func _respawn_system_active() -> bool:
	var rs := Game.get_system("respawn")
	return rs != null and is_instance_valid(rs) and rs.get("enabled") != false


func physics_update(delta: float) -> void:
	var p := player
	_t += delta
	if rag != null and is_instance_valid(rag):
		p.global_position = rag.get_pelvis_position() - Vector3(0.0, 0.25, 0.0)
	if not _fallback or _done:
		return
	if _respawn_system_active():
		_fallback = false        # a real respawn system appeared / was re-enabled; it is in charge now
		return
	if not _faded and _t >= Player.RESPAWN_DELAY - 0.6:
		_faded = true
		UI.fade_out(0.55)
	if _t >= Player.RESPAWN_DELAY:
		_done = true
		Wanted.clear("died")
		p.respawn(Game.get_location("hospital"))
		UI.fade_in(0.6)
