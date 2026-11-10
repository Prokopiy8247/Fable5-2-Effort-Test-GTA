extends Node
## G - global game state, event bus and shared helpers (autoload).

const L_WORLD := 1
const L_VEHICLE := 2
const L_CHAR := 4
const L_PROP := 8
const L_TRIGGER := 16
const L_DEBRIS := 32
const L_WATER := 64
const SOLID := L_WORLD | L_VEHICLE | L_PROP
const WATER_LEVEL := -1.2
const MAP_HALF := 300.0

signal crime(kind: String, pos: Vector3, severity: float, culprit: Node)
signal noise(pos: Vector3, radius: float, kind: String, source: Node)
signal notify(text: String, color: Color)
signal explosion(pos: Vector3, radius: float)
signal player_vehicle_changed(vehicle: Node)
signal money_changed(amount: int)
signal game_loaded()

var main: Node = null
var world: Node = null
var player: Node = null
var cam: Node = null
var hud: Node = null
var fx: Node = null
var wanted: Node = null
var traffic: Node = null
var peds: Node = null
var timew: Node = null
var wildlife: Node = null
var services: Node = null

var rng := RandomNumberGenerator.new()
var settings := {"mouse_sens": 0.0028, "invert_y": false, "master_volume": 0.8, "fov": 68.0, "shadows": true, "density": 1.0}
var flags := {"traffic": true, "peds": true, "wildlife": true, "god": false, "show_fps": false, "show_coords": false, "all_mods": false}
var test_mode := ""
var ui_blocking := 0   # >0 while a menu owns the mouse
var time_scale_target := 1.0


func _enter_tree() -> void:
	rng.seed = 20261109
	_setup_input()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if absf(Engine.time_scale - time_scale_target) > 0.001:
		Engine.time_scale = move_toward(Engine.time_scale, time_scale_target, delta * 6.0 / maxf(Engine.time_scale, 0.05))


func _key(action: String, keys: Array, mouse: Array = [], pad: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.3)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in mouse:
		var mb := InputEventMouseButton.new()
		mb.button_index = b
		InputMap.action_add_event(action, mb)
	for p in pad:
		if p is Array:
			var ax := InputEventJoypadMotion.new()
			ax.axis = p[0]
			ax.axis_value = p[1]
			InputMap.action_add_event(action, ax)
		else:
			var jb := InputEventJoypadButton.new()
			jb.button_index = p
			InputMap.action_add_event(action, jb)


func _setup_input() -> void:
	_key("move_forward", [KEY_W], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_key("move_back", [KEY_S], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_key("move_left", [KEY_A], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_key("move_right", [KEY_D], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_key("sprint", [KEY_SHIFT], [], [JOY_BUTTON_LEFT_STICK])
	_key("jump", [KEY_SPACE], [], [JOY_BUTTON_A])
	_key("crouch", [KEY_C, KEY_CTRL], [], [JOY_BUTTON_RIGHT_STICK])
	_key("enter_vehicle", [KEY_F], [], [JOY_BUTTON_Y])
	_key("interact", [KEY_E], [], [JOY_BUTTON_X])
	_key("fire", [], [MOUSE_BUTTON_LEFT], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_key("aim", [], [MOUSE_BUTTON_RIGHT], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_key("reload", [KEY_R], [], [JOY_BUTTON_B])
	_key("weapon_wheel", [KEY_TAB], [], [JOY_BUTTON_LEFT_SHOULDER])
	_key("next_weapon", [], [MOUSE_BUTTON_WHEEL_DOWN], [JOY_BUTTON_DPAD_RIGHT])
	_key("prev_weapon", [], [MOUSE_BUTTON_WHEEL_UP], [JOY_BUTTON_DPAD_LEFT])
	_key("map", [KEY_M], [], [JOY_BUTTON_BACK])
	_key("pause", [KEY_ESCAPE], [], [JOY_BUTTON_START])
	_key("camera_toggle", [KEY_V])
	_key("horn", [KEY_H])
	_key("cover", [KEY_Q], [], [JOY_BUTTON_RIGHT_SHOULDER])
	_key("phone", [KEY_T, KEY_UP], [], [JOY_BUTTON_DPAD_UP])
	_key("admin", [KEY_F1])
	_key("headlights", [KEY_L])
	_key("radio", [KEY_N])
	_key("grenade", [KEY_G])
	_key("siren", [KEY_Q])
	_key("roof", [KEY_K])
	_key("yaw_left", [KEY_Q])
	_key("yaw_right", [KEY_E])
	_key("look_back", [KEY_B])
	_key("melee", [KEY_X])
	_key("quicksave", [KEY_F5])
	_key("quickload", [KEY_F9])
	_key("skip", [KEY_ENTER])
	_key("photo", [KEY_F12])
	_key("stats", [KEY_P])
	for i in range(1, 10):
		_key("slot_%d" % i, [KEY_0 + i])


# ---------------------------------------------------------------- helpers
func say(text: String, color: Color = Color(1, 1, 1)) -> void:
	notify.emit(text, color)


func ray(from: Vector3, to: Vector3, mask: int = SOLID, exclude: Array = [], areas := false) -> Dictionary:
	if main == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = exclude
	q.collide_with_areas = areas
	return main.get_world_3d().direct_space_state.intersect_ray(q)


func los(from: Vector3, to: Vector3, exclude: Array = []) -> bool:
	return ray(from, to, L_WORLD | L_VEHICLE, exclude).is_empty()


func ground_y(x: float, z: float, from_y: float = 200.0) -> float:
	var h := ray(Vector3(x, from_y, z), Vector3(x, -50.0, z), L_WORLD)
	if h.is_empty():
		return 0.0
	return h.position.y


func in_water(pos: Vector3) -> bool:
	return pos.y < WATER_LEVEL


func rid_of(node: Node) -> Array:
	var out: Array = []
	if node is CollisionObject3D:
		out.append(node.get_rid())
	return out


func dist2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func pick(arr: Array):
	return arr[rng.randi() % arr.size()]


func chance(p: float) -> bool:
	return rng.randf() < p


func player_pos() -> Vector3:
	if player == null:
		return Vector3.ZERO
	return player.global_position_now()


func is_player(n: Node) -> bool:
	return n != null and n == player


func make_noise(pos: Vector3, radius: float, kind: String, source: Node = null) -> void:
	noise.emit(pos, radius, kind, source)


func report_crime(kind: String, pos: Vector3, severity: float, culprit: Node = null) -> void:
	crime.emit(kind, pos, severity, culprit)


func damage_radius(pos: Vector3, radius: float, dmg: float, instigator: Node = null, impulse: float = 9.0) -> void:
	## Explosion style damage + physics impulse.
	explosion.emit(pos, radius)
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = L_VEHICLE | L_CHAR | L_PROP | L_DEBRIS
	var seen := {}
	for r in main.get_world_3d().direct_space_state.intersect_shape(q, 48):
		var c: Object = r.collider
		if c == null or seen.has(c):
			continue
		seen[c] = true
		var cp: Vector3 = c.global_position + Vector3(0, 0.6, 0)
		var d := cp.distance_to(pos)
		var f := clampf(1.0 - d / radius, 0.0, 1.0)
		var dir := (cp - pos).normalized() if d > 0.05 else Vector3.UP
		if c.has_method("take_damage"):
			c.take_damage(dmg * (0.25 + 0.75 * f), instigator, pos, "explosion")
		if c is RigidBody3D:
			c.apply_central_impulse((dir + Vector3.UP * 0.5) * impulse * f * minf(c.mass, 1600.0))
		elif c.has_method("knockdown"):
			c.knockdown((dir + Vector3.UP * 0.6) * impulse * f * 1.2)
	make_noise(pos, radius * 9.0, "explosion", instigator)
	report_crime("explosion", pos, 2.2, instigator)


func timer(t: float) -> Signal:
	return get_tree().create_timer(t, false).timeout


func fmt_money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + "$" + s + out
