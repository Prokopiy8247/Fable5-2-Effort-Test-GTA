extends Node
## Autoload "Game": central game state and service locator.
## Thin on purpose - gameplay lives in the systems registered through BootManifest.
## RULE: public names here are a frozen contract; you may add, never rename/remove.

const START_MONEY := 5000
const WATER_LEVEL := 0.0            ## world Y of the sea surface
const MAP_HALF_EXTENT := 300.0      ## playable island fits inside x,z in [-300, 300]
const WORLD_SOFT_LIMIT := 1500.0    ## aircraft/boats are turned back beyond this radius

var main: Node = null               ## the Main bootstrap node (scene root)
var systems: Dictionary = {}        ## system name -> Node (see BootManifest)
var player: Node3D = null           ## the Player (CharacterBody3D, group "player")
var world: Node3D = null            ## the World system node (terrain, roads, layout API)
var camera_rig: Node3D = null       ## the gameplay camera rig (owned by the player module)
var is_ready: bool = false          ## true after EventBus.game_ready
var money: int = START_MONEY
var invulnerable: bool = false      ## admin toggle; damage code for the PLAYER must respect it
var flags: Dictionary = {}          ## command line / debug flags ("no_traffic": true ...)
var disabled_systems: Dictionary = {}   ## name -> true, from --disable=a,b
var rng := RandomNumberGenerator.new()
var playtime_seconds: float = 0.0
var input_locked: int = 0           ## >0 while a menu owns the input (see lock_input / unlock_input)

var _time_scale_requests: Dictionary = {}   ## requester id -> scale


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_cmdline()


func _process(delta: float) -> void:
	if is_ready and not get_tree().paused:
		playtime_seconds += delta


func _parse_cmdline() -> void:
	rng.randomize()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--disable="):
			for n in a.substr(10).split(",", false):
				disabled_systems[n.strip_edges()] = true
		elif a.begins_with("--seed="):
			rng.seed = int(a.substr(7))
			seed(int(a.substr(7)))
		elif a.begins_with("--flag="):
			flags[a.substr(7)] = true
		elif a.begins_with("--") and not a.contains("="):
			flags[a.substr(2)] = true


# --- systems ---------------------------------------------------------------------------------

func register_system(system_name: String, node: Node) -> void:
	systems[system_name] = node
	if system_name == "world":
		world = node as Node3D


## Returns the system node or null. Always null-check: systems can be disabled or missing.
func get_system(system_name: String) -> Node:
	var n: Variant = systems.get(system_name, null)
	if n != null and is_instance_valid(n):
		return n
	return null


func has_system(system_name: String) -> bool:
	return get_system(system_name) != null


func is_disabled(system_name: String) -> bool:
	return disabled_systems.has(system_name)


## Enable/disable a running system (admin menu). Systems should implement set_enabled(bool).
func set_system_enabled(system_name: String, enabled: bool) -> void:
	var s := get_system(system_name)
	if s == null:
		return
	if s.has_method("set_enabled"):
		s.set_enabled(enabled)
	else:
		s.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	EventBus.system_toggled.emit(system_name, enabled)


# --- player ----------------------------------------------------------------------------------

func set_player(p: Node3D) -> void:
	player = p
	EventBus.player_spawned.emit(p)


func has_player() -> bool:
	return player != null and is_instance_valid(player)


## World position of the player (or of the vehicle the player sits in).
func get_player_position() -> Vector3:
	if not has_player():
		return Vector3.ZERO
	var v: Variant = player.get("current_vehicle")
	if v != null and is_instance_valid(v):
		return (v as Node3D).global_position
	return player.global_position


## World velocity of the player (vehicle velocity while driving).
func get_player_velocity() -> Vector3:
	if not has_player():
		return Vector3.ZERO
	var v: Variant = player.get("current_vehicle")
	if v != null and is_instance_valid(v) and v is RigidBody3D:
		return (v as RigidBody3D).linear_velocity
	if player is CharacterBody3D:
		return (player as CharacterBody3D).velocity
	return Vector3.ZERO


func get_player_vehicle() -> Node3D:
	if not has_player():
		return null
	var v: Variant = player.get("current_vehicle")
	if v != null and is_instance_valid(v):
		return v as Node3D
	return null


## Active gameplay camera (falls back to the viewport camera).
func get_camera() -> Camera3D:
	return get_viewport().get_camera_3d()


# --- economy ---------------------------------------------------------------------------------

func add_money(amount: int) -> void:
	if amount == 0:
		return
	money = max(0, money + amount)
	EventBus.money_changed.emit(money, amount)


## Returns true and deducts if the player can afford it.
func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if money < amount:
		return false
	money -= amount
	EventBus.money_changed.emit(money, -amount)
	return true


func set_money(amount: int) -> void:
	var delta := amount - money
	money = max(0, amount)
	EventBus.money_changed.emit(money, delta)


# --- world helpers (delegate to the World system) --------------------------------------------

## Terrain height (world Y) at x,z. Falls back to 0 when no world is loaded.
func ground_height(x: float, z: float) -> float:
	if world != null and world.has_method("get_height"):
		return world.get_height(x, z)
	return 0.0


## Named location (see docs/ARCHITECTURE.md "Named locations"). Identity at origin if unknown.
func get_location(location_name: String) -> Transform3D:
	if world != null and world.has_method("get_location"):
		return world.get_location(location_name)
	return Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))


func is_in_water(pos: Vector3) -> bool:
	if world != null and world.has_method("is_water_at"):
		return world.is_water_at(pos)
	return false


# --- spawning (delegates) --------------------------------------------------------------------

## Spawn any registered vehicle. opts: {"owner_tag": "player"/"civilian"/"police"/"parked",
## "color": Color, "with_driver": String npc archetype, "engine_on": bool, "mods": Dictionary}
func spawn_vehicle(spec_id: String, xform: Transform3D, opts: Dictionary = {}) -> Node3D:
	var s := get_system("vehicles")
	if s != null and s.has_method("spawn_vehicle"):
		return s.spawn_vehicle(spec_id, xform, opts)
	push_warning("Game.spawn_vehicle: vehicles system missing")
	return null


## Spawn an NPC by archetype id (Registry kind "npc_archetypes").
func spawn_npc(archetype_id: String, position: Vector3, opts: Dictionary = {}) -> Node3D:
	var s := get_system("peds")
	if s != null and s.has_method("spawn_npc"):
		return s.spawn_npc(archetype_id, position, opts)
	push_warning("Game.spawn_npc: peds system missing")
	return null


## Node that owns runtime-spawned world entities (vehicles, npcs, props, projectiles).
func get_entities_root() -> Node:
	if main != null and is_instance_valid(main):
		var n := main.get_node_or_null("Entities")
		if n != null:
			return n
		return main
	return get_tree().current_scene


# --- pause / time scale / input lock ---------------------------------------------------------

func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	EventBus.game_paused.emit(paused)


## Several systems may want slow motion at once (weapon wheel, death cam). Lowest scale wins.
func request_time_scale(requester: String, scale: float) -> void:
	_time_scale_requests[requester] = clampf(scale, 0.05, 2.0)
	_apply_time_scale()


func release_time_scale(requester: String) -> void:
	_time_scale_requests.erase(requester)
	_apply_time_scale()


func _apply_time_scale() -> void:
	# Slow-motion requests (< 1) win over fast-forward requests (> 1); fast-forward only applies
	# when nobody asks for slow motion.
	var slow := 1.0
	var fast := 1.0
	for k in _time_scale_requests:
		var v := float(_time_scale_requests[k])
		if v < 1.0:
			slow = minf(slow, v)
		else:
			fast = maxf(fast, v)
	var s := slow if slow < 1.0 else fast
	Engine.time_scale = s


## Menus call lock_input() when they open and unlock_input() when they close.
## Player / vehicle input code must ignore gameplay input while Game.is_input_locked().
func lock_input() -> void:
	input_locked += 1


func unlock_input() -> void:
	input_locked = max(0, input_locked - 1)


func is_input_locked() -> bool:
	return input_locked > 0
