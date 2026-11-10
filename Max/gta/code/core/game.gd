extends Node
## Global game state + service locator (autoload "Game").

const GAME_TITLE := "NEON TIDE: Vesper Bay"
const SEA_LEVEL := -1.0
const MAP_HALF := 300.0

# --- live references (set by main.gd while booting) --------------------------
var main: Node = null
var world: World = null
var player: Player = null
var cam: CameraRig = null
var hud: HUD = null
var ui: Node = null
var time: WorldEnv = null
var weather: WorldEnv = null
var wanted: Node = null
var police: Node = null
var traffic: Node = null
var peds: Node = null
var wildlife: Node = null
var skills: Skills = null
var fx: FX = null
var pickups: Node = null
var services: Node = null
var garage: Node = null
var activities: Node = null
var transit: Node = null

# --- sandbox state -----------------------------------------------------------
var cash: int = 2500
var stats := {
	"kills": 0, "police_kills": 0, "vehicles_destroyed": 0, "vehicles_stolen": 0,
	"distance_foot": 0.0, "distance_drive": 0.0, "distance_fly": 0.0, "distance_swim": 0.0,
	"deaths": 0, "busted": 0, "max_wanted": 0, "stunt_jumps": 0, "best_jump": 0.0,
	"cash_spent": 0, "shots_fired": 0, "play_time": 0.0,
}
var cheats := {
	"invulnerable": false,
	"infinite_ammo": false,
	"never_wanted": false,
	"unlock_all_mods": false,
	"free_shopping": false,
}
var flags := {
	"traffic": true,
	"pedestrians": true,
	"wildlife": true,
	"police": true,
	"show_fps": false,
	"show_coords": false,
}

var menus: Node = null        # UIManager (pause menu, shops, phone, admin menu)
var soft_block := 0          # >0 while an overlay (weapon wheel) takes player input but keeps the mouse captured
var _ui_block := 0           # >0 while a menu owns the mouse/keyboard
var _slowmo_sources := {}    # name -> time scale
var is_headless := false
var automated := false       # true during --gta-test runs
var boot_ms := 0
## Game-time seconds (physics clock). Every gameplay timer uses this instead of the wall
## clock so slow motion, pause and fast-forwarded test runs behave identically.
var clock := 0.0

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_headless = DisplayServer.get_name() == "headless"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gta-test"):
			automated = true
	InputSetup.install()

func _ready() -> void:
	if not is_headless:
		DisplayServer.window_set_title(GAME_TITLE + "  -  Fable 5.2 GTA (Max)")

func _process(delta: float) -> void:
	if not get_tree().paused:
		stats["play_time"] += delta

func _physics_process(delta: float) -> void:
	if not get_tree().paused:
		clock += delta

# ---------------------------------------------------------------- economy
func add_cash(amount: int, show := true) -> void:
	if amount == 0:
		return
	cash = max(0, cash + amount)
	Events.cash_changed.emit(cash, amount)
	if show and amount > 0:
		Audio.play_ui(&"ui_cash", -8.0)

func can_afford(amount: int) -> bool:
	return cheats["free_shopping"] or cash >= amount

func spend(amount: int) -> bool:
	if cheats["free_shopping"]:
		return true
	if cash < amount:
		notify("Not enough cash", "bad")
		Audio.play_ui(&"ui_deny", -6.0)
		return false
	cash -= amount
	stats["cash_spent"] += amount
	Events.cash_changed.emit(cash, -amount)
	return true

# ---------------------------------------------------------------- feedback
func notify(text: String, kind := "info") -> void:
	Events.notify.emit(text, kind)

func banner(title: String, subtitle := "", color := Color.WHITE, seconds := 3.0) -> void:
	Events.banner.emit(title, subtitle, color, seconds)

# ---------------------------------------------------------------- UI / time
func ui_push() -> void:
	_ui_block += 1
	_update_mouse()

func ui_pop() -> void:
	_ui_block = max(0, _ui_block - 1)
	_update_mouse()

func ui_blocked() -> bool:
	return _ui_block > 0 or soft_block > 0

func _update_mouse() -> void:
	if is_headless:
		return
	if _ui_block > 0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not automated:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func capture_mouse() -> void:
	_update_mouse()

## Named slow-motion sources (weapon wheel, death cam). The slowest one wins.
func set_slowmo(source: String, scale: float) -> void:
	if scale >= 0.999:
		_slowmo_sources.erase(source)
	else:
		_slowmo_sources[source] = scale
	var s := 1.0
	for v in _slowmo_sources.values():
		s = minf(s, float(v))
	Engine.time_scale = s

# ---------------------------------------------------------------- world queries
func ground_y(x: float, z: float) -> float:
	if world and world.has_method("height_at"):
		return world.height_at(x, z)
	return 0.0

func water_depth(pos: Vector3) -> float:
	## > 0 when `pos` is below the sea surface over open water.
	if world and world.has_method("is_water_at") and world.is_water_at(pos.x, pos.z):
		return water_surface(pos) - pos.y
	return -1.0

func water_surface(pos: Vector3) -> float:
	if world and world.has_method("wave_height"):
		return world.wave_height(pos.x, pos.z)
	return SEA_LEVEL

func district_at(pos: Vector3) -> String:
	if world and world.has_method("district_at"):
		return world.district_at(pos)
	return ""

func sector_of(pos: Vector3) -> String:
	## 6x6 grid of 100 m sectors: A1 (north-west) .. F6 (south-east).
	var cx := clampi(int(floor((pos.x + MAP_HALF) / 100.0)), 0, 5)
	var cz := clampi(int(floor((pos.z + MAP_HALF) / 100.0)), 0, 5)
	return "%s%d" % [char(65 + cx), cz + 1]

func player_pos() -> Vector3:
	if is_instance_valid(player):
		return player.global_position
	return Vector3.ZERO

## Position that AI should aim at / track (vehicle body when driving).
func player_target() -> Node3D:
	if is_instance_valid(player):
		if player.get("vehicle") != null and is_instance_valid(player.vehicle):
			return player.vehicle
		return player
	return null

func space() -> PhysicsDirectSpaceState3D:
	return get_viewport().world_3d.direct_space_state

## Convenience ray cast. Returns {} on miss.
func ray(from: Vector3, to: Vector3, mask: int, exclude: Array[RID] = [], areas := false) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.collide_with_areas = areas
	return space().intersect_ray(q)

func has_los(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> bool:
	return ray(from, to, Phys.SIGHT_BLOCK, exclude).is_empty()
