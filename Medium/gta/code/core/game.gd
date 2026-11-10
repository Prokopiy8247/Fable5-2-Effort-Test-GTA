extends Node
## Global game hub (autoload "G"): shared references, registries, helpers.

const L_WORLD := 1
const L_VEH := 2
const L_CHAR := 4
const L_PROP := 8
const L_TRIG := 16
const L_SOLID := 1 | 2 | 8
const L_SHOT := 1 | 2 | 4 | 8
const WATER_Y := -0.9
const MODELS := "res://gta/generated/models/"

var man: Dictionary = {}
var _scenes: Dictionary = {}
var _mats: Dictionary = {}
var rng := RandomNumberGenerator.new()

# system references (assigned by main.gd)
var main: Node3D
var world
var player
var cam
var hud
var menus
var traffic
var pop
var wanted
var audio
var fx
var env
var save
var extras
var skills

var money: int = 2500
var paused := false
var time_scale := 1.0
var cheats := {"god": false, "fps": false, "coords": false}
var stats := {"kills": 0, "cars_stolen": 0, "busted": 0, "wasted": 0, "stunts": 0}
var autotest := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = 20261109
	Engine.max_fps = 60
	var f = FileAccess.open(MODELS + "manifest.json", FileAccess.READ)
	if f:
		man = JSON.parse_string(f.get_as_text())
	_setup_input()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			autotest = true
			# hard watchdog so a broken automated run can never stay alive
			get_tree().create_timer(105.0, true, false, true).timeout.connect(func(): get_tree().quit(3))
			_err_watch()


func _err_watch() -> void:
	# if the main scene failed to finish booting, quit quickly instead of idling until the watchdog
	await get_tree().create_timer(12.0, true, false, true).timeout
	if main == null or not main.has_meta("booted"):
		print("[TEST] FAIL boot did not complete")
		get_tree().quit(4)


func _setup_input() -> void:
	var keys = {
		"fwd": [KEY_W], "back": [KEY_S], "left": [KEY_A], "right": [KEY_D], "sprint": [KEY_SHIFT], "jump": [KEY_SPACE],
		"crouch": [KEY_C], "stealth": [KEY_CTRL], "interact": [KEY_E], "enter": [KEY_F], "reload": [KEY_R], "wheel": [KEY_TAB],
		"map": [KEY_M], "pause": [KEY_ESCAPE], "camera": [KEY_V], "horn": [KEY_H], "cover": [KEY_Q], "grenade": [KEY_G],
		"phone": [KEY_P, KEY_UP], "debug": [KEY_F1], "radio": [KEY_N], "lights": [KEY_L], "roll_l": [KEY_Q], "roll_r": [KEY_E],
		"descend": [KEY_CTRL], "quicksave": [KEY_F5], "quickload": [KEY_F9], "heavy": [KEY_X], "siren": [KEY_J], "flip": [KEY_B],
		"skip": [KEY_ENTER], "lookback": [KEY_Z], "roof": [KEY_K], "status": [KEY_I], "block": [KEY_ALT],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var ev = InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
	for a in [["fire", MOUSE_BUTTON_LEFT], ["aim", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0])
		var mb = InputEventMouseButton.new()
		mb.button_index = a[1]
		InputMap.action_add_event(a[0], mb)
	# basic gamepad support
	var pad = {"jump": JOY_BUTTON_A, "enter": JOY_BUTTON_Y, "reload": JOY_BUTTON_X, "interact": JOY_BUTTON_B, "wheel": JOY_BUTTON_LEFT_SHOULDER,
		"sprint": JOY_BUTTON_LEFT_STICK, "crouch": JOY_BUTTON_RIGHT_STICK, "pause": JOY_BUTTON_START, "phone": JOY_BUTTON_DPAD_UP, "horn": JOY_BUTTON_DPAD_DOWN}
	for a in pad:
		var jb = InputEventJoypadButton.new()
		jb.button_index = pad[a]
		InputMap.action_add_event(a, jb)
	for a in [["fwd", JOY_AXIS_LEFT_Y, -1.0], ["back", JOY_AXIS_LEFT_Y, 1.0], ["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0],
			["fire", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["aim", JOY_AXIS_TRIGGER_LEFT, 1.0]]:
		var jm = InputEventJoypadMotion.new()
		jm.axis = a[1]
		jm.axis_value = a[2]
		InputMap.action_add_event(a[0], jm)


# ---------- assets ----------
func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(MODELS + path + ".glb")
	return _scenes[path]


func model(path: String) -> Node3D:
	var s = scene(path)
	if s == null:
		push_warning("missing model " + path)
		return Node3D.new()
	return s.instantiate()


func info(name: String) -> Dictionary:
	return man.get(name, {})


func v3(a: Array, o: int = 0) -> Vector3:
	return Vector3(a[o], a[o + 1], a[o + 2])


func part(root: Node, suffix: String) -> Node3D:
	for c in root.find_children("*", "Node3D", true, false):
		if String(c.name).ends_with(suffix):
			return c
	return null


func parts(root: Node, contains: String) -> Array:
	var out = []
	for c in root.find_children("*", "Node3D", true, false):
		if String(c.name).contains(contains):
			out.append(c)
	return out


func meshes(root: Node) -> Array:
	var out = []
	if root is MeshInstance3D:
		out.append(root)
	out.append_array(root.find_children("*", "MeshInstance3D", true, false))
	return out


## Replace surfaces whose source material name matches a key with the given material.
func remat(root: Node, map: Dictionary) -> void:
	for mi in meshes(root):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(i)
			if m and map.has(m.resource_name):
				mi.set_surface_override_material(i, map[m.resource_name])


func flat_mat(col: Color, rough := 0.8, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	return m


func cmat(key: String, col: Color, rough := 0.8, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		_mats[key] = flat_mat(col, rough, metal, emit)
	return _mats[key]


# ---------- physics helpers ----------
func ray(from: Vector3, to: Vector3, mask: int = L_SOLID, exclude: Array = [], areas := false) -> Dictionary:
	var q = PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.collide_with_areas = areas
	return main.get_world_3d().direct_space_state.intersect_ray(q)


func ground_y(x: float, z: float, from_y: float = 200.0) -> float:
	var h = ray(Vector3(x, from_y, z), Vector3(x, -40, z), L_WORLD)
	return h.position.y if h else 0.0


func los(a: Vector3, b: Vector3, exclude: Array = []) -> bool:
	return ray(a, b, L_WORLD, exclude).is_empty()


func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func dist2d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func chance(p: float) -> bool:
	return rng.randf() < p


func pick(a: Array):
	return a[rng.randi() % a.size()]


func notify(t: String, dur := 3.0) -> void:
	if hud:
		hud.notify(t, dur)


func add_money(n: int) -> void:
	money = max(0, money + n)
	if hud and n != 0:
		hud.money_flash(n)


func player_pos() -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.vehicle:
		return player.vehicle.global_position
	return player.global_position


func player_body():
	return player.vehicle if player and player.vehicle else player


func in_water(p: Vector3) -> bool:
	return p.y < WATER_Y and world and world.is_sea(p.x, p.z)


func is_night() -> bool:
	return env != null and env.night > 0.5
