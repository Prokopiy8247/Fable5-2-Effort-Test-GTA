class_name Prop
extends RigidBody3D
## Breakable / movable street furniture. Starts frozen (costs nothing); wakes up when a
## fast vehicle is about to hit it, when it is shot, or when an explosion reaches it.
## Explosive props (barrels, gas bottles) blow up. Props put themselves back once the
## player is far away, so the city heals without ever-growing rigid-body counts.

var prop_id := ""
var home := Transform3D.IDENTITY
var awake := false
var explosive := false
var health := 60.0
var wake_speed := 3.0          # minimum vehicle speed (m/s) that knocks it over
var light: Light3D = null
var is_hydrant := false
var _awake_time := 0.0
var _dead := false
var _spray: Node3D = null

func _ready() -> void:
	home = global_transform
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	collision_layer = Phys.PROP
	collision_mask = Phys.WORLD | Phys.VEHICLE | Phys.PROP
	can_sleep = true
	set_physics_process(false)
	add_to_group(&"props")

## Called by vehicles' prop sensors and by damage sources.
func wake(impulse := Vector3.ZERO, at := Vector3.ZERO) -> void:
	if _dead:
		return
	if not awake:
		awake = true
		_awake_time = 0.0
		freeze = false
		sleeping = false
		set_physics_process(true)
		if light != null:
			light.visible = false
			light.set_meta("broken", true)
			if Game.fx:
				Game.fx.sparks(light.global_position, Vector3.DOWN, 14)
			Audio.play(&"glass_break", global_position, -8.0, 1.3)
		if is_hydrant and Game.fx:
			_spray = Game.fx.water_jet(home.origin + Vector3(0, 0.15, 0), 18.0)
		Audio.play(&"melee_hit_metal" if mass > 14.0 else &"melee_hit", global_position, -6.0, 1.0, 0.15)
	if impulse != Vector3.ZERO:
		apply_impulse(impulse, at - global_position if at != Vector3.ZERO else Vector3.ZERO)

func apply_damage(amount: float, source: Node = null, hit_pos := Vector3.ZERO, dir := Vector3.ZERO, _info: Dictionary = {}) -> void:
	if _dead:
		return
	health -= amount
	if explosive:
		if health <= 0.0:
			explode(source)
		return
	wake(dir * minf(amount * 0.6, 40.0), hit_pos)

func explode(source: Node = null) -> void:
	if _dead:
		return
	_dead = true
	var pos := global_position + Vector3(0, 0.4, 0)
	visible = false
	collision_layer = 0
	collision_mask = 0
	freeze = true
	if Game.fx:
		Game.fx.explosion(pos, 6.5, 160.0, source)
	_awake_time = 0.0
	awake = true
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	_awake_time += delta
	if _awake_time < 25.0:
		return
	# restore when the player cannot see it happen
	var d := global_position.distance_to(Game.player_pos())
	if d > 110.0 or (_dead and d > 70.0 and _awake_time > 60.0):
		reset()

func reset() -> void:
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = home
	awake = false
	_dead = false
	visible = true
	collision_layer = Phys.PROP
	collision_mask = Phys.WORLD | Phys.VEHICLE | Phys.PROP
	health = 60.0
	if light != null:
		light.set_meta("broken", false)
	if is_instance_valid(_spray):
		_spray.queue_free()
	set_physics_process(false)
