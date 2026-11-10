class_name Player
extends CharacterBody3D
## The player character (docs/ARCHITECTURE.md 6.4, docs/PLAYER.md).
##
## CharacterBody3D + a small state machine (gta/code/player/states/): on_foot, air, swim,
## vehicle, ragdoll, dead. The body owns health / armor / stamina / breath, the camera rig
## (PlayerCamera), the interaction scanner (PlayerInteraction), the procedural animator
## (HumanoidAnimator on the shared humanoid visual) and - when the weapons module is present -
## the WeaponInventory child named "Inventory".
##
## Every module that touches the player goes through the public members below; everything that
## crosses a module boundary is a soft dependency (the player runs with no world, no model,
## no inventory, no vehicles).

# =================================================================================================
# Tunables
# =================================================================================================
const WALK_SPEED := 1.9                 ## m/s
const RUN_SPEED := 4.4
const SPRINT_SPEED := 7.0
const CROUCH_SPEED := 2.1
const STEALTH_SPEED := 2.4              ## sneaking (stealth toggle): quiet, between walk and run
const AIM_SPEED := 2.6                  ## strafing while aiming / right after hip fire
const WALK_INPUT_THRESHOLD := 0.6       ## analog stick below this = walk
const JUMP_HEIGHT := 1.1                ## m
const GRAVITY := 20.0                   ## m/s^2 (snappier than 9.8, GTA-like weight)
const TERMINAL_SPEED := 55.0
const ACCEL_GROUND := 18.0              ## m/s^2
const DECEL_GROUND := 24.0
const ACCEL_AIR := 5.0
const AIR_SPEED := 3.2                  ## steering authority in the air
const ACCEL_SWIM := 5.0
const TURN_RATE := 11.0                 ## rad/s
const TURN_RATE_SPRINT := 6.5
const TURN_RATE_AIM := 16.0
const TURN_RATE_SWIM := 4.0
const STEP_HEIGHT := 0.32               ## kerbs / stairs up to this height are walked up
const FLOOR_ANGLE_DEG := 46.0
const CAPSULE_RADIUS := 0.35
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.25
const MAX_HEALTH := 100.0
const MAX_ARMOR := 100.0
const HEALTH_REGEN_DELAY := 8.0         ## seconds without damage before regeneration starts
const HEALTH_REGEN_RATE := 2.5          ## hp / s
const HEALTH_REGEN_CAP := 0.5           ## regenerates only up to this fraction of max_health
const STAMINA_SPRINT_SECONDS := 13.0    ## full bar of sprinting at skill factor 1.0
const STAMINA_REGEN_SECONDS := 7.0
const STAMINA_REGEN_DELAY := 1.0
const FALL_SAFE_SPEED := 12.5           ## m/s impact speed without damage (~3.9 m drop)
const FALL_DAMAGE_PER_MS := 7.5         ## hp per m/s above the safe speed (lethal at ~26 m/s)
const HARD_LAND_SPEED := 9.0            ## landing reaction (short lock + squat)
const RAGDOLL_LAND_SPEED := 17.0        ## landing that knocks the player down
const VOID_Y := -80.0                   ## fell out of the world -> recover
const SWIM_SPEED := 2.1
const SWIM_FAST_SPEED := 3.3
const DIVE_SPEED := 2.4
const DIVE_VERTICAL_SPEED := 1.8
const SURFACE_SPEED_MULT := 1.4         ## swimming up (jump) is faster than diving down (crouch)
const BUOYANCY_SPEED := 0.35
const FLOAT_DEPTH := 1.42               ## origin below the surface while floating (water at the shoulders)
const SUBMERGE_DEPTH := 1.72            ## origin below the surface = head under water
const SWIM_ENTER_DEPTH := 1.25
const SWIM_EXIT_DEPTH := 1.0
const BREATH_SECONDS := 28.0            ## at lung skill multiplier 1.0
const BREATH_REGEN_SECONDS := 2.5
const DROWN_DAMAGE := 10.0              ## per second without air
const SCUBA_BREATH_MULT := 12.0         ## scuba gear (pickup kind "scuba"): breath lasts this many times longer
const SAME_IMPACT_FRAMES := 15          ## a second knock-down impulse this many physics frames after a ragdoll spawned = the same impact
const VEHICLE_REACH := 3.0              ## metres to the door / exit point
const VEHICLE_WALK_MAX := 8.0           ## door farther than this (scripted / admin entries): sit down at once
const VEHICLE_ENTER_TIME := 0.55
const VEHICLE_EXIT_TIME := 0.5
const BAIL_SPEED := 8.0                 ## m/s: leaving a faster vehicle = tumble
const BAIL_DAMAGE_PER_MS := 2.4
const WRECK_DAMAGE := 120.0             ## explosion damage when the vehicle is destroyed with the player inside
const VEHICLE_HIT_SPEED := 4.5          ## closing speed (m/s) at which a vehicle knocks the player down
const VEHICLE_HIT_DAMAGE_PER_MS := 6.5
const GET_UP_TIME := 0.95
const RESPAWN_DELAY := 5.0
const COMBAT_FACE_TIME := 1.4           ## seconds the body keeps facing the camera after a shot
const NOISE_WALK := 5.0
const NOISE_RUN := 7.0
const NOISE_SPRINT := 9.0
const NOISE_STEALTH := 1.5             ## sneaking / crouching at the starting Stealth skill
const STEALTH_SKILL_NOISE := 0.6        ## x NOISE_STEALTH at Stealth 100 (linear from the starting level)
const SAFE_POS_INTERVAL := 0.5          ## how often last_safe_position is refreshed
const HEAVY_HIT_STAGGER := 0.32         ## s of lost control after a heavy blow that did not knock down
# --- Wave 3 (parachute / diving / polish)
const FREEFALL_MIN_AGL := 22.0          ## falling (air state) with more than this below the feet -> freefall
const BAIL_FREEFALL_AGL := 25.0         ## leaving a vehicle / aircraft higher than this -> freefall
const AGL_PROBE := 1500.0               ## longest ground probe of measure_agl()
## Contact normals steeper than the floor angle are edges / walls for _try_step_up (Wave 2 used 0.55:
## sharp edges of 0.107 - 0.157 m gave contact normals between 0.55 and the floor limit 0.695 and
## blocked the capsule - neither stepped up nor walkable).
const STEP_EDGE_NORMAL_Y := 0.6947      ## = cos(FLOOR_ANGLE_DEG)
const TELEPORT_GHOST_TICKS := 2         ## physics ticks without a collision shape after a teleport (Jolt
                                        ## sweeps a kinematic body to its new transform: it kicked vehicles)
const AIRCRAFT_CLASSES: PackedStringArray = ["heli", "plane"]

const HUMANOID_SCENE := "res://gta/scenes/characters/humanoid.tscn"
## Vehicle interaction helper (tap / hold entry, carjacking, theft reports, drive-by arcs).
const VehicleInteractionScript := preload("res://gta/code/player/player_vehicle_interaction.gd")
## Stealth helper (visibility_factor, takedown target, Stealth XP, loud gunfire ends stealth).
const StealthScript := preload("res://gta/code/player/player_stealth.gd")
## Parachute gear presentation (pack on the back, canopy rig, freefall / canopy audio).
const ParachuteScript := preload("res://gta/code/player/player_parachute.gd")
## Diving / underwater exploration helper (wreck treasure, bubbles, lung XP).
const DiveScript := preload("res://gta/code/player/player_dive.gd")
const INVENTORY_SCRIPT := "res://gta/code/weapons/weapon_inventory.gd"
const SLOT_ACTIONS: Array[StringName] = [&"weapon_slot_1", &"weapon_slot_2", &"weapon_slot_3",
		&"weapon_slot_4", &"weapon_slot_5", &"weapon_slot_6", &"weapon_slot_7", &"weapon_slot_8", &"weapon_slot_9"]
## Fallback when a weapon spec carries no `weapon_pose`.
const POSE_BY_WEAPON := {
	"": "none", "fists": "none", "knife": "melee", "bat": "melee", "crowbar": "melee",
	"pistol": "pistol", "heavy_pistol": "pistol", "smg": "rifle", "pump_shotgun": "rifle",
	"auto_shotgun": "rifle", "assault_rifle": "rifle", "carbine": "rifle", "marksman_rifle": "rifle",
	"sniper_rifle": "rifle", "grenade": "throw", "molotov": "throw", "rocket_launcher": "rpg",
	"grenade_launcher": "rifle",
}
const FOOTSTEP_BY_SURFACE := {
	"concrete": "footstep_concrete", "asphalt": "footstep_concrete", "metal": "footstep_metal",
	"glass": "footstep_concrete", "wood": "footstep_wood", "dirt": "footstep_grass",
	"grass": "footstep_grass", "foliage": "footstep_grass", "sand": "footstep_sand",
	"water": "footstep_water", "rubber": "footstep_concrete",
}

# =================================================================================================
# Public contract (ARCHITECTURE 6.4)
# =================================================================================================
var health: float = MAX_HEALTH
var max_health: float = MAX_HEALTH
var armor: float = 0.0
var max_armor: float = MAX_ARMOR
var is_dead: bool = false
var current_vehicle: Node3D = null
var is_aiming: bool = false
var is_sprinting: bool = false
var is_crouching: bool = false
var in_stealth: bool = false
var in_cover: bool = false
var is_swimming: bool = false
var is_underwater: bool = false
var has_parachute: bool = false
var breath: float = 1.0
var stamina: float = 1.0
var noise_radius: float = 0.0
var visual: Node3D = null
var inventory: Node = null

# --- additional public members
var animator: HumanoidAnimator = null
var camera: PlayerCamera = null
var interaction: PlayerInteraction = null
var states: Dictionary = {}             ## id -> PlayerState
var state: PlayerState = null
var state_id: String = ""
var grounded: bool = false              ## on the floor (or walking up a step) after the last move
var water_depth: float = 0.0            ## how deep the feet are under the surface (0 = dry)
var water_surface_y: float = 0.0
var seat_index: int = 0
var last_damage_info: Dictionary = {}
# animation inputs the states may set
var anim_speed_override: float = -1.0   ## >= 0 replaces the measured speed
var anim_steer: float = 0.0
var anim_dive_pitch: float = 0.0
var has_scuba: bool = false             ## scuba gear: breath drains SCUBA_BREATH_MULT times slower
# --- Wave 2 additions
var is_blocking: bool = false           ## melee guard up (PlayerStateMelee)
var on_ladder: bool = false             ## climbing a ladder (PlayerStateLadder)
var melee_target: Node3D = null         ## soft lock-on target of the melee stance (or null)
var last_safe_position: Vector3 = Vector3.INF   ## last grounded, dry on-foot position (respawn rescue)
var vehicle_ix: VehicleInteractionScript = null   ## child "VehicleInteraction"
var anim_aim_yaw: float = 0.0           ## drive-by: aim yaw relative to the seat (animator aim_yaw)
var anim_aim_pitch: float = 0.0
var drive_by_window: Vector3 = Vector3.INF      ## drive-by: world point shots leave from (INF = none)
var aim_dir_override: Vector3 = Vector3.ZERO    ## drive-by drop: aim ray direction override (ZERO = none)
# --- Wave 2: cover / stealth (player programmer B)
## 0.1..1: how easy the player is to spot right now (posture x light). AiSenses multiplies its
## awareness rate by it. Updated by the Stealth helper every 0.2 s.
var visibility_factor: float = 1.0
var takedown_target: Node3D = null      ## NPC a stealth takedown would hit right now (or null)
var aim_spread_extra_deg: float = 0.0   ## extra random cone on get_aim_ray() (blind fire from cover)
var stealth: StealthScript = null       ## child "Stealth"
## True in the first physics tick in which `fire` is held (the same edge process_fire_input uses for
## trigger_pressed; just_pressed can lag one tick behind is_action_pressed for synthetic presses).
var fire_pressed_edge: bool = false
var _fire_was_held: bool = false
# --- Wave 3: parachute / diving / polish (player programmer, wave 3)
## Metres above the ground / water surface under the player. Refreshed every physics tick in the
## freefall / parachute states (HUD altimeter), every 0.1 s while falling, 0 on the ground.
var altitude_agl: float = 0.0
var chute: ParachuteScript = null       ## child "Parachute" (pack / canopy visuals, wind + canopy audio)
var dive: DiveScript = null             ## child "Dive" (wreck treasure, bubbles)
## Ids of the one-time underwater treasures this save has already collected (saved with the player).
var treasures_found: PackedStringArray = []
## >= 0: the inventory's shots / throws start this high above the feet (get_shoot_origin): blind fire
## over low cover shoots from the standing eye height while the body stays crouched.
var shoot_height_override: float = -1.0
var _ghost_ticks: int = 0
var _agl_query: PhysicsRayQueryParameters3D = null

var _control_enabled: bool = true
var _collision_on: bool = true
var _collider: CollisionShape3D = null
var _capsule: CapsuleShape3D = null
var _states_root: Node = null
var _home_parent: Node = null
var _vehicle_sensor: Area3D = null
var _kc := KinematicCollision3D.new()
var _stepped: bool = false
var _was_grounded: bool = false
var _visual_drop: float = 0.0
var _planar_accel: float = 0.0
var _yaw_rate: float = 0.0
var _prev_yaw: float = 0.0
var _trigger_down: bool = false
var _combat_face_t: float = 0.0
var _weapon_pose: String = "none"
var _weapon_poll_t: float = 0.0
var _last_weapon_id: String = ""
var _stamina_delay: float = 0.0
var _regen_delay: float = 0.0
var _vehicle_hit_cd: float = 0.0
var _ignored_vehicle: Node = null
var _ignore_vehicle_t: float = 0.0
var _district: String = ""
var _district_t: float = 0.0
var _ragdoll: Ragdoll = null
var _ragdoll_spawn_frame: int = -100000
var _attached_vehicle: Node = null
var _reattaching: bool = false
var _floor_collider: Object = null
var _punch_side: int = 0
var _warned_no_model: bool = false
var _hide_reasons: Dictionary = {}
var _head_hidden: bool = false
var _safe_t: float = 0.0
var _rehome_home_id: int = 0
var _rehome_keep: Transform3D = Transform3D.IDENTITY


# =================================================================================================
# Setup
# =================================================================================================

func _ready() -> void:
	add_to_group("player")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.PLAYER_MASK
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(FLOOR_ANGLE_DEG)
	floor_snap_length = 0.3
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_block_on_wall = true
	max_slides = 5
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	platform_floor_layers = Layers.WORLD | Layers.VEHICLE | Layers.PROP
	platform_wall_layers = 0
	_home_parent = get_parent()
	_setup_collider()
	_setup_visual()
	_setup_states()
	_setup_sensor()
	interaction = PlayerInteraction.new()
	interaction.name = "Interaction"
	add_child(interaction)
	interaction.setup(self)
	vehicle_ix = VehicleInteractionScript.new()
	vehicle_ix.name = "VehicleInteraction"
	add_child(vehicle_ix)
	vehicle_ix.setup(self)
	stealth = StealthScript.new()
	stealth.name = "Stealth"
	add_child(stealth)
	stealth.setup(self)
	chute = ParachuteScript.new()
	chute.name = "Parachute"
	add_child(chute)
	chute.setup(self)
	dive = DiveScript.new()
	dive.name = "Dive"
	add_child(dive)
	dive.setup(self)
	camera = get_node_or_null("CameraRig") as PlayerCamera
	if camera == null:
		camera = PlayerCamera.new()
		camera.name = "CameraRig"
		add_child(camera)
	camera.setup(self)
	_setup_inventory()
	SaveSystem.register_provider("player", self)
	EventBus.weapon_equipped.connect(_on_weapon_equipped)
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.weapon_reload_started.connect(_on_reload_started)
	_prev_yaw = rotation.y
	change_state("on_foot", {})
	_register_player.call_deferred()
	EventBus.player_health_changed.emit(health, armor)


func _register_player() -> void:
	if Game.player == null or not is_instance_valid(Game.player):
		Game.set_player(self)


func _setup_collider() -> void:
	_collider = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collider == null:
		_collider = CollisionShape3D.new()
		_collider.name = "CollisionShape3D"
		add_child(_collider)
	_capsule = CapsuleShape3D.new()
	_capsule.radius = CAPSULE_RADIUS
	_capsule.height = STAND_HEIGHT
	_collider.shape = _capsule
	_collider.position = Vector3(0.0, STAND_HEIGHT * 0.5, 0.0)


func _setup_visual() -> void:
	visual = get_node_or_null("Visual") as Node3D
	if visual == null and ResourceLoader.exists(HUMANOID_SCENE):
		var ps := load(HUMANOID_SCENE) as PackedScene
		if ps != null:
			visual = ps.instantiate() as Node3D
			if visual != null:
				visual.name = "Visual"
				add_child(visual)
	if visual == null:
		if not _warned_no_model:
			_warned_no_model = true
			push_warning("Player: character model missing (%s) - the player is invisible" % HUMANOID_SCENE)
		return
	var skel := Ragdoll.find_skeleton(visual)
	if skel == null:
		push_warning("Player: the character visual has no Skeleton3D")
		return
	# the visual may already carry an animator; otherwise the player owns one
	for c in visual.get_children():
		if c is HumanoidAnimator:
			animator = c as HumanoidAnimator
	var va: Variant = visual.get("animator")
	if animator == null and va is HumanoidAnimator:
		animator = va as HumanoidAnimator
	if animator == null:
		animator = HumanoidAnimator.new()
		animator.name = "Animator"
		add_child(animator)
	if not animator.is_ready():
		animator.setup(skel)
	animator.update_rate_hz = 0.0
	animator.phase = 0.0
	animator.swim_depth = FLOAT_DEPTH
	if not animator.footstep.is_connected(on_footstep):
		animator.footstep.connect(on_footstep)


func _setup_states() -> void:
	_states_root = Node.new()
	_states_root.name = "States"
	add_child(_states_root)
	register_state("on_foot", PlayerStateOnFoot.new())
	register_state("air", PlayerStateAir.new())
	register_state("swim", PlayerStateSwim.new())
	register_state("vehicle", PlayerStateVehicle.new())
	register_state("ragdoll", PlayerStateRagdoll.new())
	register_state("dead", PlayerStateDead.new())
	register_state("vault", PlayerStateVault.new())
	register_state("ladder", PlayerStateLadder.new())
	register_state("roll", PlayerStateRoll.new())
	register_state("melee", PlayerStateMelee.new())
	register_state("busted", PlayerStateBusted.new())
	register_state("cover", PlayerStateCover.new())
	register_state("takedown", PlayerStateTakedown.new())
	register_state("freefall", PlayerStateFreefall.new())
	register_state("parachute", PlayerStateParachute.new())


func _setup_sensor() -> void:
	_vehicle_sensor = Area3D.new()
	_vehicle_sensor.name = "VehicleSensor"
	_vehicle_sensor.collision_layer = 0
	_vehicle_sensor.collision_mask = Layers.VEHICLE
	_vehicle_sensor.monitorable = false
	_vehicle_sensor.monitoring = true
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_RADIUS + 0.22
	cap.height = STAND_HEIGHT - 0.1
	cs.shape = cap
	cs.position = Vector3(0.0, STAND_HEIGHT * 0.5 + 0.05, 0.0)
	_vehicle_sensor.add_child(cs)
	add_child(_vehicle_sensor)


func _setup_inventory() -> void:
	inventory = get_node_or_null("Inventory")
	if inventory != null:
		return
	if not ResourceLoader.exists(INVENTORY_SCRIPT):
		return
	var scr := load(INVENTORY_SCRIPT) as Script
	if scr == null or not scr.can_instantiate():
		push_warning("Player: weapon inventory script does not load, running unarmed")
		return
	var node: Variant = scr.new()
	if not (node is Node):
		return
	inventory = node as Node
	inventory.name = "Inventory"
	add_child(inventory)
	if inventory.has_method("setup"):
		inventory.call("setup", self)


## Add (or replace) a state. The node is parented under Player/States.
func register_state(id: String, node: PlayerState) -> void:
	if states.has(id):
		var old: PlayerState = states[id]
		if old == state:
			return
		old.queue_free()
	node.name = id.to_pascal_case()
	node.setup(self, id)
	_states_root.add_child(node)
	states[id] = node


func change_state(id: String, args: Dictionary = {}) -> void:
	if not states.has(id):
		push_warning("Player: unknown state '%s'" % id)
		return
	var prev_id := state_id
	var prev_public := state.public_name if state != null else ""
	if state != null:
		state.exit(id)
	state = states[id]
	state_id = id
	state.enter(prev_id, args)
	# a state may redirect inside enter(); only announce what is really active
	if state_id == id and state.public_name != prev_public and not (id == "vehicle"):
		notify_state_changed(state.public_name)


func notify_state_changed(public_state: String) -> void:
	EventBus.player_state_changed.emit(public_state)


func get_state_name() -> String:
	return state_id


# =================================================================================================
# Frame loop
# =================================================================================================

func _physics_process(delta: float) -> void:
	if state == null:
		return
	if _ghost_ticks > 0:
		_ghost_ticks -= 1
		if _ghost_ticks == 0 and _collider != null:
			_collider.set_deferred("disabled", not _collision_on)
	if current_vehicle == null:
		update_water()
	var fire_held := pressed(&"fire")
	fire_pressed_edge = fire_held and not _fire_was_held
	_fire_was_held = fire_held
	state.physics_update(delta)
	_update_timers(delta)
	if state_id == "on_foot" or state_id == "air" or state_id == "melee" or state_id == "roll" or state_id == "cover":
		_check_vehicle_hits()
	_safe_t -= delta
	if _safe_t <= 0.0:
		_safe_t = SAFE_POS_INTERVAL
		if state_id == "on_foot" and grounded and water_depth <= 0.0 and current_vehicle == null \
				and is_inside_tree() and global_position.is_finite() and global_position.y > VOID_Y + 10.0:
			# never under the terrain (the sea-floor plane runs below the whole island)
			var p := global_position
			if Game.world == null or p.y > Game.ground_height(p.x, p.z) - 1.5:
				last_safe_position = p
	var yaw := global_rotation.y
	_yaw_rate = angle_difference(_prev_yaw, yaw) / maxf(delta, 0.0001)
	_prev_yaw = yaw


func _process(delta: float) -> void:
	if state == null:
		return
	state.frame_update(delta)
	if visual != null:
		if absf(_visual_drop) > 0.0005:
			_visual_drop = lerpf(_visual_drop, 0.0, 1.0 - exp(-14.0 * delta))
			visual.position.y = _visual_drop
		elif visual.position.y != 0.0:
			_visual_drop = 0.0
			visual.position.y = 0.0
	_update_animator()


func _update_timers(delta: float) -> void:
	_combat_face_t = maxf(_combat_face_t - delta, 0.0)
	_vehicle_hit_cd = maxf(_vehicle_hit_cd - delta, 0.0)
	if _ignore_vehicle_t > 0.0:
		_ignore_vehicle_t -= delta
		if _ignore_vehicle_t <= 0.0:
			_ignored_vehicle = null
	if is_dead:
		return
	# breath comes back quickly with the head above water
	if not is_underwater and breath < 1.0:
		breath = minf(breath + delta / BREATH_REGEN_SECONDS, 1.0)
	# slow regeneration up to half health when left alone
	_regen_delay = maxf(_regen_delay - delta, 0.0)
	if _regen_delay <= 0.0 and health < max_health * HEALTH_REGEN_CAP:
		var before := health
		health = minf(health + HEALTH_REGEN_RATE * delta, max_health * HEALTH_REGEN_CAP)
		if int(health) != int(before):
			EventBus.player_health_changed.emit(health, armor)
	# weapon pose follow-up (in case nobody emits weapon_equipped)
	_weapon_poll_t -= delta
	if _weapon_poll_t <= 0.0:
		_weapon_poll_t = 0.25
		_refresh_weapon_pose()
	_district_t -= delta
	if _district_t <= 0.0:
		_district_t = 0.5
		if Game.world != null and Game.world.has_method("get_district"):
			var d := str(Game.world.call("get_district", Game.get_player_position()))
			if d != _district:
				_district = d
				EventBus.player_district_changed.emit(d)


func _update_animator() -> void:
	var a := animator
	if a == null:
		return
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var sp := planar.length()
	if anim_speed_override >= 0.0:
		a.speed = anim_speed_override
		a.move_dir_local = Vector2(0.0, 1.0)
	else:
		a.speed = sp
		if sp > 0.25:
			var local := global_basis.inverse() * (planar / sp)
			a.move_dir_local = Vector2(local.x, -local.z)
	a.vertical_speed = velocity.y
	a.turn_rate = _yaw_rate
	a.lean = clampf(-_yaw_rate * sp * 0.035, -1.0, 1.0)
	a.accel_lean = clampf(_planar_accel / 14.0, -1.0, 1.0)
	a.steer = anim_steer
	a.sneak = 1.0 if (in_stealth and (state_id == "on_foot" or state_id == "melee")) else 0.0
	a.weapon_pose = _weapon_pose
	if state_id == "vehicle":
		# drive-by: one-handed aim out of the window (the vehicle state fills anim_aim_*)
		a.aim_weight = 1.0 if is_aiming else 0.0
		a.aim_yaw = anim_aim_yaw if is_aiming else 0.0
		a.aim_pitch = anim_aim_pitch if is_aiming else 0.0
		return
	a.aim_yaw = 0.0
	var combat := (is_aiming or _combat_face_t > 0.0) and (state_id == "on_foot" or state_id == "air" or state_id == "melee")
	a.aim_weight = 1.0 if combat else 0.0
	if state_id == "swim":
		a.aim_pitch = anim_dive_pitch
	elif state_id == "melee":
		a.aim_pitch = 0.0
	else:
		a.aim_pitch = get_view_pitch() if combat else 0.0
	# the active state may refine the animator (cover: side / peek / blind fire)
	state.update_animator(a)


## Animator state with the default cross-fade (blend < 0) or an explicit one.
func set_anim_state(anim_state: String, blend: float = -1.0) -> void:
	if animator != null:
		animator.set_state(anim_state, blend)


func snap_animator() -> void:
	if animator != null:
		animator.snap()


## One-shot action on the character (reload, punch_l, punch_r, heavy, kick, hit_react, throw,
## pickup, enter_car, exit_car). Other modules (weapons, pickups) may call this.
func play_action(action_name: String, duration: float = -1.0) -> void:
	if animator != null:
		animator.play_action(action_name, duration)


## Hook used by WeaponInventory (reload, punch_l / punch_r, heavy, kick, throw ...).
func play_weapon_action(action_name: String, duration: float = -1.0) -> void:
	_combat_face_t = maxf(_combat_face_t, COMBAT_FACE_TIME * 0.6)
	play_action(action_name, duration)


## First-person view: hide everything on the head (the body and its shadow stay).
func set_head_hidden(hidden: bool) -> void:
	if hidden == _head_hidden:
		return
	_head_hidden = hidden
	if visual != null and visual.has_method("set_head_visible"):
		visual.call("set_head_visible", not hidden)
	elif animator != null:
		animator.hide_head = hidden


func is_head_hidden() -> bool:
	return _head_hidden


## Several systems may want the body hidden (ragdoll stand-in, scope view, camera inside the
## body). The visual is shown only while nobody asks for it to be hidden.
func set_visual_hidden(reason: String, hidden: bool) -> void:
	if hidden:
		_hide_reasons[reason] = true
	else:
		_hide_reasons.erase(reason)
	if visual != null:
		visual.visible = _hide_reasons.is_empty()


## Feet-level world position the camera follows (vehicle, ragdoll and corpse aware).
func get_camera_focus() -> Vector3:
	if state != null:
		return state.get_focus_position()
	return global_position


func is_first_person() -> bool:
	return camera != null and camera.mode == "first"


func has_animator_footsteps() -> bool:
	return animator != null and animator.is_ready()


# =================================================================================================
# Input helpers (used by the states)
# =================================================================================================

func has_control() -> bool:
	return _control_enabled and not is_dead and not Game.is_input_locked()


func pressed(action: StringName) -> bool:
	return has_control() and Input.is_action_pressed(action)


func just_pressed(action: StringName) -> bool:
	return has_control() and Input.is_action_just_pressed(action)


## x = right, y = forward, length <= 1.
func get_move_input() -> Vector2:
	if not has_control():
		return Vector2.ZERO
	var v := Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	return v


## Walk modifier. InputSetup has no "walk" action yet, so the raw Left-Alt key is the fallback
## (hold to walk); a game-pad walks with a partially tilted stick (WALK_INPUT_THRESHOLD).
func is_walk_held() -> bool:
	if InputMap.has_action(&"walk"):
		return Input.is_action_pressed(&"walk")
	return Input.is_physical_key_pressed(KEY_ALT)


func get_view_yaw() -> float:
	return camera.yaw if camera != null else rotation.y


func get_view_pitch() -> float:
	return camera.pitch if camera != null else 0.0


## Camera-relative world direction for a move input (length = input length).
func get_wish_dir(input: Vector2) -> Vector3:
	var yaw := get_view_yaw()
	var s := sin(yaw)
	var c := cos(yaw)
	# forward = (-sin, 0, -cos), right = (cos, 0, -sin)
	return Vector3(c * input.x - s * input.y, 0.0, -s * input.x - c * input.y)


func is_combat_facing() -> bool:
	return _combat_face_t > 0.0


func interaction_handles(action: String) -> bool:
	return interaction != null and interaction.handles_action(action)


func can_enter_vehicles() -> bool:
	return state != null and state.allows_vehicle_entry() and not is_dead


## Tap / hold handling of the enter_vehicle key for the ground and swim states. True = an entry
## started (the state changed).
func process_vehicle_entry_input(delta: float, allowed: bool) -> bool:
	if vehicle_ix == null:
		return false
	return vehicle_ix.process_enter_key(delta, allowed)


## Fists or a melee weapon in hand (the melee stance applies).
func has_melee_weapon() -> bool:
	var inv := inventory
	if inv == null or not is_instance_valid(inv):
		return false
	var id := str(inv.get("current_id"))
	if id == "" or id == "<null>" or id == "fists":
		return id == "fists"
	if inv.has_method("get_current_spec"):
		var spec: Variant = inv.call("get_current_spec")
		if spec is Object and spec != null and (spec as Object).has_method("is_melee"):
			return bool((spec as Object).call("is_melee"))
	return id == "knife" or id == "bat" or id == "crowbar"


## Keeps stamina from regenerating for at least `seconds` (blocking, climbing ...).
func hold_stamina_regen(seconds: float) -> void:
	_stamina_delay = maxf(_stamina_delay, seconds)


## Directional hit reaction: `from_local` = where the blow came from in the body frame (x right,
## y front), strength ~0.5 (graze) .. 1.6 (heavy).
func play_hit_react(from_local: Vector2, strength: float = 1.0) -> void:
	if animator == null:
		return
	animator.hit_dir = from_local
	animator.hit_strength = strength
	animator.play_action("hit_react", 0.30 + 0.12 * clampf(strength, 0.0, 1.6))


# =================================================================================================
# Traversal (vault / mantle / ladders)
# =================================================================================================

## Vault or mantle along `dir` if an obstacle allows it (PlayerStateVault.probe). True = started.
func try_traversal(dir: Vector3, from_air: bool) -> bool:
	if not states.has("vault") or is_dead or current_vehicle != null:
		return false
	var v := states["vault"] as PlayerStateVault
	var max_rise := PlayerStateVault.AIR_MAX_RISE if from_air else PlayerStateVault.MANTLE_MAX_HEIGHT
	var d := v.probe(dir, max_rise)
	if d.is_empty():
		return false
	change_state("vault", {"data": d})
	return state_id == "vault"


## Nearest ladder the player could mount right now: {} or {"ladder", "from_top", "distance"}.
func find_ladder() -> Dictionary:
	if not is_inside_tree() or is_dead or current_vehicle != null:
		return {}
	var best: Dictionary = {}
	var best_d := INF
	var feet := global_position
	for n: Node in get_tree().get_nodes_in_group("ladder"):
		var l := n as Node3D
		if l == null:
			continue
		var info := PlayerStateLadder.mount_info(l, feet, is_swimming)
		if info.is_empty():
			continue
		if float(info["distance"]) < best_d:
			best_d = float(info["distance"])
			best = info
	return best


## Jump pressed while standing at the foot of a ladder and facing it: climb.
func try_start_ladder_from_jump() -> bool:
	var info := find_ladder()
	if info.is_empty() or bool(info["from_top"]):
		return false
	var l := info["ladder"] as Node3D
	var to := l.global_position - global_position
	to.y = 0.0
	var fwd := -global_basis.z
	if to.length() > 0.05 and to.normalized().dot(fwd) < 0.3:
		return false
	return start_ladder(l, false)


## Mount `ladder` (group "ladder" node). from_top < 0 = decide by the player's height.
func start_ladder(ladder: Node3D, from_top: int = -1) -> bool:
	if ladder == null or not is_instance_valid(ladder) or not states.has("ladder") or is_dead:
		return false
	if current_vehicle != null:
		return false
	var top := from_top == 1
	if from_top < 0:
		top = global_position.y > ladder.global_position.y + PlayerStateLadder.ladder_height(ladder) - 0.8
	change_state("ladder", {"ladder": ladder, "from_top": top})
	return state_id == "ladder"


## Alias for interactables of other modules ("Climb" use points).
func climb_ladder(ladder: Node3D) -> void:
	start_ladder(ladder, -1)


# =================================================================================================
# Movement helpers (used by the states)
# =================================================================================================

func get_jump_speed() -> float:
	# half a tick of gravity is added so the discrete integration really reaches JUMP_HEIGHT
	return sqrt(2.0 * GRAVITY * JUMP_HEIGHT) + GRAVITY / (2.0 * float(Engine.physics_ticks_per_second))


func accelerate_planar(target: Vector3, rate: float, delta: float) -> void:
	var cur := Vector3(velocity.x, 0.0, velocity.z)
	var nxt := cur.move_toward(target, rate * delta)
	_planar_accel = (nxt.length() - cur.length()) / maxf(delta, 0.0001)
	velocity.x = nxt.x
	velocity.z = nxt.z


func turn_toward(yaw: float, rate: float, delta: float) -> void:
	var diff := angle_difference(rotation.y, yaw)
	# ease out near the target so the turn does not snap
	var step := clampf(diff, -rate * delta, rate * delta) * clampf(absf(diff) * 4.0 + 0.25, 0.0, 1.0)
	rotation.y = wrapf(rotation.y + step, -PI, PI)


## Moves the body with velocity. with_steps: walk up kerbs / stairs up to STEP_HEIGHT.
func move_body(delta: float, with_steps: bool = true) -> void:
	_stepped = false
	if with_steps and _was_grounded and velocity.y <= 0.01:
		_stepped = _try_step_up(delta)
	if not _stepped:
		move_and_slide()
		_push_props()
	grounded = is_on_floor() or _stepped
	_was_grounded = grounded
	if is_on_floor():
		for i in get_slide_collision_count():
			var col := get_slide_collision(i)
			if col.get_normal().y > 0.6:
				_floor_collider = col.get_collider()
				break


func _try_step_up(delta: float) -> bool:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var sp := hv.length()
	if sp < 0.4:
		return false
	var motion := hv * delta
	var from := global_transform
	if not test_move(from, motion, _kc):
		return false
	if _kc.get_normal().y > STEP_EDGE_NORMAL_Y:
		return false                    # a walkable slope: the normal slide handles it
	# (steeper contact normals are kerb / step edges or walls; the walkable-top ray below tells them
	# apart from steep ramps)
	var up := Vector3(0.0, STEP_HEIGHT, 0.0)
	if test_move(from, up):
		return false                    # no head room
	var raised := from.translated(up)
	var dir := hv / sp
	if test_move(raised, dir * maxf(motion.length(), 0.08)):
		return false                    # still blocked one step higher: a wall
	# the top of the step must be a real, walkable surface just in front of the body
	var space := get_world_3d().direct_space_state
	var probe := global_position + dir * (CAPSULE_RADIUS + 0.06)
	var q := PhysicsRayQueryParameters3D.create(probe + Vector3(0.0, STEP_HEIGHT + 0.05, 0.0),
			probe - Vector3(0.0, 0.05, 0.0), collision_mask)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	if (hit["normal"] as Vector3).y < 0.7:
		return false
	var rise_top := (hit["position"] as Vector3).y - global_position.y
	if rise_top < 0.02 or rise_top > STEP_HEIGHT:
		return false
	# drop back down from the raised position: the capsule comes to rest on the step edge
	var target := raised.translated(motion)
	if not test_move(target, -up, _kc):
		return false
	var landed := target.origin + _kc.get_travel()
	var rise := landed.y - global_position.y
	if rise < 0.005:
		return false
	global_position = landed
	velocity.y = 0.0
	_visual_drop -= rise
	_floor_collider = hit.get("collider", null)
	return true


func _push_props() -> void:
	var n := get_slide_collision_count()
	if n == 0:
		return
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	for i in n:
		var col := get_slide_collision(i)
		var body := col.get_collider() as RigidBody3D
		if body == null or (body.collision_layer & Layers.PROP) == 0:
			continue
		var into := -col.get_normal()
		into.y = 0.0
		var push := maxf(planar.dot(into), 0.0) + 0.6
		body.apply_impulse(into * push * minf(body.mass, 40.0) * 0.12, col.get_position() - body.global_position)


func can_stand() -> bool:
	if not is_crouching:
		return true
	return not test_move(global_transform, Vector3(0.0, STAND_HEIGHT - CROUCH_HEIGHT, 0.0))


func set_crouching(on: bool, force: bool = false) -> void:
	if on == is_crouching:
		return
	if not on and not force and not can_stand():
		return
	is_crouching = on
	var h := CROUCH_HEIGHT if on else STAND_HEIGHT
	_capsule.height = h
	_collider.position = Vector3(0.0, h * 0.5, 0.0)


## Sneak mode (the "stealth" action toggles it on foot / in cover): slower, almost silent, light
## hunch, lower visibility_factor, takedowns from behind. Sprinting and loud gunfire end it.
## Announced through EventBus.player_state_changed("stealth") (leaving: the public name of the
## active state) so the HUD can show it.
func set_stealth(on: bool) -> void:
	if on == in_stealth:
		return
	in_stealth = on
	if not on:
		takedown_target = null
	if stealth != null:
		stealth.update_visibility()
	notify_state_changed("stealth" if on else (state.public_name if state != null else "on_foot"))


## Footstep noise radius while sneaking or crouching: NOISE_STEALTH at the starting Stealth level
## (Skills.START_LEVEL), down to NOISE_STEALTH x STEALTH_SKILL_NOISE at 100.
func get_stealth_noise_radius() -> float:
	var start := 20.0
	var sv: Variant = Skills.get("START_LEVEL")
	if sv is float or sv is int:
		start = float(sv)
	var k := clampf((Skills.get_level("stealth") - start) / maxf(100.0 - start, 1.0), 0.0, 1.0)
	return NOISE_STEALTH * lerpf(1.0, STEALTH_SKILL_NOISE, k)


## Stealth takedown on takedown_target if the rules still hold (PlayerStateTakedown). True = started.
func try_takedown() -> bool:
	var t := takedown_target
	if t == null or not is_instance_valid(t) or not states.has("takedown") or not in_stealth or is_dead:
		return false
	if not PlayerStateTakedown.can_take_down(self, t):
		takedown_target = null
		return false
	change_state("takedown", {"target": t})
	return state_id == "takedown"


## Cover key: take cover at the best surface in reach (PlayerStateCover). True = started.
func try_take_cover() -> bool:
	if not states.has("cover") or is_dead or current_vehicle != null:
		return false
	var st := states["cover"] as PlayerStateCover
	var d := st.find_cover()
	if d.is_empty():
		return false
	change_state("cover", {"cover": d})
	return state_id == "cover"


func set_collision_enabled(on: bool) -> void:
	if on == _collision_on:
		return
	_collision_on = on
	# deferred: this may be reached from inside a physics callback (damage from a contact signal)
	if _collider != null:
		_collider.set_deferred("disabled", not on or _ghost_ticks > 0)
	set_deferred("collision_layer", Layers.PLAYER if on else 0)
	if _vehicle_sensor != null:
		_vehicle_sensor.set_deferred("monitoring", on)


func is_collision_enabled() -> bool:
	return _collision_on


func update_stamina(delta: float, draining: bool) -> void:
	if draining:
		stamina = maxf(stamina - delta / (STAMINA_SPRINT_SECONDS * Skills.get_multiplier("stamina", 0.75, 1.9)), 0.0)
		_stamina_delay = STAMINA_REGEN_DELAY
		Skills.add_xp("stamina", delta * 0.02)
	else:
		_stamina_delay = maxf(_stamina_delay - delta, 0.0)
		if _stamina_delay <= 0.0 and stamina < 1.0:
			stamina = minf(stamina + delta / STAMINA_REGEN_SECONDS, 1.0)


## Refreshes water_surface_y / water_depth for the current position.
func update_water() -> void:
	var p := global_position
	var surf: float = Game.WATER_LEVEL
	var env := Game.get_system("environment")
	if env != null and env.has_method("get_wave_height"):
		surf = float(env.call("get_wave_height", p.x, p.z))
	water_surface_y = surf
	if p.y < surf and Game.is_in_water(Vector3(p.x, minf(p.y + 0.05, surf - 0.02), p.z)):
		water_depth = surf - p.y
	else:
		water_depth = 0.0


func recover_from_void() -> void:
	var p := global_position
	var y := Game.ground_height(p.x, p.z)
	if Game.world == null:
		var home := Game.get_location("spawn_start")
		teleport(home.origin, rotation.y)
		return
	teleport(Vector3(p.x, maxf(y, Game.WATER_LEVEL) + 1.0, p.z), rotation.y)


func emit_noise(radius: float, kind: String = "footstep") -> void:
	EventBus.noise_emitted.emit(Game.get_player_position(), radius, kind, self)


func shake_camera(amount: float) -> void:
	if camera != null:
		camera.add_trauma(amount * float(Settings.get_value("camera_shake")))


## Footstep event (from the animator, or from the distance fallback of the on_foot state).
func on_footstep(_foot: int, intensity: float) -> void:
	if (state_id != "on_foot" and state_id != "cover" and state_id != "melee") or not grounded or is_dead:
		return
	var sp := Vector2(velocity.x, velocity.z).length()
	if sp < 0.5:
		return
	var surface := _surface_under_feet()
	var id: String = FOOTSTEP_BY_SURFACE.get(surface, "footstep_concrete")
	if water_depth > 0.12:
		id = "footstep_water"
		if water_depth > 0.3:
			Fx.splash(Vector3(global_position.x, water_surface_y, global_position.z), 0.35)
	var quiet := is_crouching or in_stealth
	var vol := lerpf(-16.0, -5.0, clampf(intensity, 0.0, 1.0)) - (8.0 if quiet else 0.0)
	Audio.play_at(id, global_position + Vector3(0.0, 0.05, 0.0), vol, randf_range(0.92, 1.08), 35.0)
	if noise_radius > 0.0:
		EventBus.noise_emitted.emit(global_position, noise_radius, "footstep", self)


func _surface_under_feet() -> String:
	var n := _floor_collider as Node
	var guard := 0
	while n != null and is_instance_valid(n) and guard < 4:
		if n.has_meta("surface"):
			return str(n.get_meta("surface"))
		if n.is_in_group("vehicle"):
			return "metal"
		n = n.get_parent()
		guard += 1
	if Game.world != null and Game.world.has_method("get_surface_at"):
		return str(Game.world.call("get_surface_at", global_position))
	return "concrete"


# =================================================================================================
# Weapons
# =================================================================================================

func set_aiming(on: bool) -> void:
	if on and (state == null or not state.allows_weapons()):
		on = false
	if on == is_aiming:
		return
	is_aiming = on
	if inventory != null and inventory.has_method("set_aiming"):
		inventory.call("set_aiming", on)


func release_trigger() -> void:
	if _trigger_down:
		_trigger_down = false
		if inventory != null and inventory.has_method("trigger_released"):
			inventory.call("trigger_released")


## Forwards fire / reload / switch input to the WeaponInventory (which is input-agnostic).
func process_weapon_input(delta: float) -> void:
	process_fire_input(delta)
	process_weapon_select_input(true)


## The fire trigger alone (press -> trigger_pressed, release -> trigger_released). `blocked`
## keeps the trigger up (drive-by aim outside the seat's arc).
func process_fire_input(_delta: float, blocked: bool = false) -> void:
	var inv := inventory
	if inv == null:
		return
	var ok := has_control() and state != null and state.allows_weapons()
	var want_fire := ok and not blocked and Input.is_action_pressed(&"fire")
	if want_fire and not _trigger_down:
		_trigger_down = true
		_combat_face_t = COMBAT_FACE_TIME
		if inv.has_method("trigger_pressed"):
			inv.call("trigger_pressed")
	elif not want_fire and _trigger_down:
		release_trigger()
	if _trigger_down:
		_combat_face_t = COMBAT_FACE_TIME


## Reload, weapon wheel / slots, holster, quick throw and (with_heavy) melee_heavy.
func process_weapon_select_input(with_heavy: bool = true) -> void:
	var inv := inventory
	if inv == null:
		return
	if not (has_control() and state != null and state.allows_weapons()):
		return
	if Input.is_action_just_pressed(&"reload") and inv.has_method("reload"):
		inv.call("reload")
	if Input.is_action_just_pressed(&"weapon_next") and inv.has_method("next_weapon"):
		inv.call("next_weapon")
	if Input.is_action_just_pressed(&"weapon_prev") and inv.has_method("prev_weapon"):
		inv.call("prev_weapon")
	if inv.has_method("equip_slot"):
		for i in SLOT_ACTIONS.size():
			if Input.is_action_just_pressed(SLOT_ACTIONS[i]):
				inv.call("equip_slot", i + 1)
	if Input.is_action_just_pressed(&"throw_grenade") and inv.has_method("throw_grenade"):
		_combat_face_t = COMBAT_FACE_TIME
		inv.call("throw_grenade")
	if with_heavy and Input.is_action_just_pressed(&"melee_heavy") and inv.has_method("melee_attack"):
		_combat_face_t = COMBAT_FACE_TIME
		inv.call("melee_attack", true)
	if Input.is_action_just_pressed(&"holster") and inv.has_method("holster"):
		inv.call("holster")


func is_armed() -> bool:
	if inventory == null or not is_instance_valid(inventory):
		return false
	if inventory.has_method("is_armed"):
		return bool(inventory.call("is_armed"))
	var id := str(inventory.get("current_id"))
	return id != "" and id != "fists" and id != "<null>"


## {"origin": Vector3, "direction": Vector3} along the camera view. The origin is pushed forward
## to the plane of the player so that nothing between the camera and the character is hit.
func get_aim_ray() -> Dictionary:
	var origin := get_target_position()
	var dir := -global_basis.z
	if camera != null:
		var o := camera.get_aim_origin()
		dir = camera.get_aim_direction()
		var t := maxf((origin - o).dot(dir), 0.0)
		origin = o + dir * t
	if aim_dir_override != Vector3.ZERO:
		# drive-by drop: straight out of the window, not along the camera
		return {"origin": get_target_position(), "direction": aim_dir_override}
	if aim_spread_extra_deg > 0.0:
		# blind fire: a random cone around the crosshair on top of the weapon's own spread
		var a := deg_to_rad(aim_spread_extra_deg) * sqrt(randf())
		var phi := randf() * TAU
		var o1 := dir.cross(Vector3.UP)
		if o1.length_squared() < 0.0001:
			o1 = dir.cross(Vector3.RIGHT)
		o1 = o1.normalized()
		var o2 := o1.cross(dir)
		dir = (dir * cos(a) + (o1 * cos(phi) + o2 * sin(phi)) * sin(a)).normalized()
	return {"origin": origin, "direction": dir}


## World point under the crosshair (first hit on Layers.BULLET_MASK, or a far point).
func get_aim_point() -> Vector3:
	var ray := get_aim_ray()
	var o: Vector3 = ray["origin"]
	var d: Vector3 = ray["direction"]
	var far := o + d * 400.0
	if not is_inside_tree():
		return far
	var q := PhysicsRayQueryParameters3D.create(o, far, Layers.BULLET_MASK)
	var ex: Array[RID] = [get_rid()]
	if current_vehicle is CollisionObject3D:
		ex.append((current_vehicle as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return far
	return hit["position"]


## Chest position (AI aims here).
func get_target_position() -> Vector3:
	if state != null and (state_id == "ragdoll" or state_id == "dead"):
		return state.get_focus_position() + Vector3(0.0, 0.3, 0.0)
	if current_vehicle != null:
		if drive_by_window.is_finite():
			# leaning out of the window to shoot (the inventory fires from here + 0.3 m up)
			return drive_by_window - Vector3(0.0, 0.3, 0.0)
		return global_transform * Vector3(0.0, 0.42, 0.0)
	if is_swimming:
		return global_position + Vector3(0.0, 1.2, 0.0)
	return global_position + Vector3(0.0, 0.85 if is_crouching else 1.25, 0.0)


## Camera kick from a shot. Units: degrees (WeaponSpec.recoil_pitch / recoil_yaw).
func add_recoil(pitch: float, yaw: float) -> void:
	if camera != null:
		camera.add_recoil(pitch, yaw)


func _refresh_weapon_pose() -> void:
	var pose := "none"
	var id := ""
	if inventory != null and is_instance_valid(inventory):
		id = str(inventory.get("current_id"))
		if id == "<null>":
			id = ""
		pose = str(POSE_BY_WEAPON.get(id, "none"))
		if inventory.has_method("get_weapon_pose"):
			var gp: Variant = inventory.call("get_weapon_pose")
			if gp is String and gp != "":
				pose = gp
		elif inventory.has_method("get_current_spec"):
			var spec: Variant = inventory.call("get_current_spec")
			if spec is Object and spec != null:
				var wp: Variant = (spec as Object).get("weapon_pose")
				if wp is String and wp != "":
					pose = wp
		if id == "" or id == "fists":
			pose = "none"
	_last_weapon_id = id
	_weapon_pose = pose


func _on_weapon_equipped(_weapon_id: String) -> void:
	_refresh_weapon_pose()


func _on_weapon_fired(_weapon_id: String, shooter: Node, _origin: Vector3, _direction: Vector3) -> void:
	if shooter != self:
		return
	_combat_face_t = COMBAT_FACE_TIME
	if animator != null:
		animator.play_action("fire")


func _on_reload_started(weapon_id: String, duration: float) -> void:
	if inventory == null or weapon_id != str(inventory.get("current_id")):
		return
	play_action("reload", duration)


# =================================================================================================
# Health / damage
# =================================================================================================

func apply_damage(info: Dictionary) -> void:
	if is_dead or Game.invulnerable:
		return
	var amount := float(info.get("amount", 0.0))
	if amount <= 0.0:
		return
	var type := str(info.get("type", "generic"))
	if (type == "vehicle" or type == "collision") and current_vehicle == null:
		if _vehicle_hit_cd > 0.0:
			return
		_vehicle_hit_cd = 0.9
	# the active state may block / dodge / reduce the hit (melee guard, dodge roll, cover ...)
	if state != null:
		info = info.duplicate()
		amount = state.modify_damage(info, amount)
		if amount <= 0.0:
			if bool(info.get("dodged", false)):
				Audio.play_at("melee_swing", get_target_position(), -8.0, 1.25, 20.0)
			return
	var total := amount
	# armor soaks up bullets and explosions first
	if armor > 0.0 and (type == "bullet" or type == "explosion"):
		var absorbed := minf(armor, amount)
		armor -= absorbed
		amount -= absorbed
	health = maxf(health - amount, 0.0)
	_regen_delay = HEALTH_REGEN_DELAY
	last_damage_info = info
	EventBus.player_damaged.emit(total, info)
	EventBus.player_health_changed.emit(health, armor)
	shake_camera(clampf(0.12 + total / 90.0, 0.0, 0.7))
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	var pos: Vector3 = info.get("position", Vector3.ZERO)
	if health <= 0.0:
		_die(type, info)
		return
	if type != "drown" and type != "fall":
		Audio.play_at("grunt_hit_m", get_target_position(), -4.0, randf_range(0.95, 1.05), 30.0)
	if (type == "bullet" or type == "melee" or type == "bite") and pos != Vector3.ZERO and amount > 0.0:
		Fx.blood(pos, -dir if dir != Vector3.ZERO else Vector3.UP)
	if state != null:
		state.on_damage(info, total)
	# heavy impacts knock the player down
	if state_id == "ragdoll":
		return
	var impulse := float(info.get("impulse", 0.0))
	var push := dir
	push.y = 0.0
	if push.length_squared() < 0.0001:
		push = -global_basis.z
	push = push.normalized()
	if bool(info.get("no_ragdoll", false)):
		if type != "fall":
			_react_to_hit(info, type, dir, pos, push)
		return
	if (type == "vehicle" or type == "collision") and total >= 8.0 and current_vehicle == null:
		# the hitter's own impulse (N*s, from its closing speed) when it sends one; the damage-based
		# guess only for bare infos - harsh vehicle damage must not also mean a cartoon throw
		var hit_impulse := clampf(impulse, 150.0, 1100.0) if impulse > 0.0 else total * 14.0
		ragdoll(push * hit_impulse + Vector3(0.0, 140.0, 0.0), 1.8)
	elif type == "explosion" and (total >= 20.0 or impulse >= 260.0):
		ragdoll(push * maxf(impulse, total * 9.0) + Vector3(0.0, 220.0, 0.0), 2.2)
	elif bool(info.get("knockdown", false)):
		ragdoll(push * maxf(impulse, 180.0) + Vector3(0.0, 60.0, 0.0), 1.4)
	else:
		_react_to_hit(info, type, dir, pos, push)


## Directional flinch (+ a short stagger for heavy blows and blasts that do not knock down).
func _react_to_hit(info: Dictionary, type: String, dir: Vector3, pos: Vector3, push: Vector3) -> void:
	var from := Vector3.ZERO
	if dir.length_squared() > 0.0001:
		from = -dir
	elif pos != Vector3.ZERO and is_inside_tree():
		from = pos - global_position
	var local := Vector2(0.0, 1.0)
	if from.length_squared() > 0.0001 and is_inside_tree():
		var l := global_basis.inverse() * from
		var v := Vector2(l.x, -l.z)
		if v.length_squared() > 0.0001:
			local = v.normalized()
	var strength := 1.0
	var heavy := bool(info.get("heavy", false))
	match type:
		"melee", "bite":
			strength = 1.5 if heavy else 1.1
		"bullet":
			strength = 0.8
		"explosion":
			strength = 1.4
		"fall", "drown", "fire":
			strength = 0.6
	if bool(info.get("blocked", false)):
		strength = 0.5
	play_hit_react(local, strength)
	if current_vehicle != null or state == null or not state.has_method("stagger"):
		return
	if (heavy and type == "melee" and not bool(info.get("blocked", false))) or type == "explosion":
		state.call("stagger", push * (2.2 if type == "explosion" else 1.6), HEAVY_HIT_STAGGER)


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	health = minf(health + amount, max_health)
	EventBus.player_health_changed.emit(health, armor)


func add_armor(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	armor = minf(armor + amount, max_armor)
	EventBus.player_health_changed.emit(health, armor)


func kill(cause: String = "generic") -> void:
	if is_dead:
		return
	health = 0.0
	EventBus.player_health_changed.emit(health, armor)
	_die(cause, {})


func _die(cause: String, info: Dictionary) -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	if current_vehicle != null or state_id == "vehicle":
		(states["vehicle"] as PlayerStateVehicle).request_exit(true)
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	var impulse := dir * maxf(float(info.get("impulse", 0.0)), float(info.get("amount", 0.0)) * 6.0)
	if state_id != "ragdoll":
		impulse += velocity * 12.0
	change_state("dead", {"cause": cause, "impulse": impulse, "position": info.get("position", Vector3.INF)})
	Audio.play("player_down", -2.0)
	Audio.play_at("death_m", get_target_position(), -3.0, 1.0, 40.0)
	if interaction != null:
		interaction.clear()
	EventBus.player_died.emit(cause)


## Bring the player back to life at `xform` (called by the respawn system, or by the built-in
## fallback in the dead state).
func respawn(xform: Transform3D) -> void:
	is_dead = false
	health = max_health
	armor = 0.0
	breath = 1.0
	stamina = 1.0
	is_underwater = false
	is_blocking = false
	on_ladder = false
	melee_target = null
	takedown_target = null
	aim_spread_extra_deg = 0.0
	shoot_height_override = -1.0
	altitude_agl = 0.0
	anim_aim_yaw = 0.0
	drive_by_window = Vector3.INF
	aim_dir_override = Vector3.ZERO
	_regen_delay = 0.0
	_vehicle_hit_cd = 0.0
	if vehicle_ix != null:
		vehicle_ix.cancel()
	if current_vehicle != null or state_id == "vehicle":
		(states["vehicle"] as PlayerStateVehicle).request_exit(true)
	clear_ragdoll()
	if chute != null:
		chute.release_canopy("reset")
	var fwd := -xform.basis.z
	var yaw := atan2(-fwd.x, -fwd.z) if Vector2(fwd.x, fwd.z).length_squared() > 0.0001 else 0.0
	_place(xform.origin, yaw)
	change_state("on_foot", {})
	EventBus.player_health_changed.emit(health, armor)
	EventBus.player_respawned.emit(global_position)


## Arrest (W2.5): leave the vehicle, hands up, no control until the respawn system releases the
## player at the police station (Player.respawn). Called by the respawn system on player_busted.
func arrest() -> void:
	if is_dead or not states.has("busted"):
		return
	if current_vehicle != null or state_id == "vehicle":
		(states["vehicle"] as PlayerStateVehicle).request_exit(true)
	if state_id == "ragdoll":
		clear_ragdoll()
	release_trigger()
	set_aiming(false)
	change_state("busted", {})


func is_busted() -> bool:
	return state_id == "busted"


## Knock the player down with a physical ragdoll for `duration` seconds, then get up.
func ragdoll(impulse: Vector3, duration: float = 2.0) -> void:
	if is_dead or state_id == "ragdoll":
		# already a ragdoll: push it - unless it was spawned by this very impact a moment ago (a
		# vehicle both damages and knocks down; Combat sends knockdown in the info AND calls
		# knock_down), so one hit is never applied twice
		if _ragdoll != null and is_instance_valid(_ragdoll) and not is_same_impact():
			_ragdoll.apply_impulse_at(impulse)
		return
	if current_vehicle != null or state_id == "vehicle":
		(states["vehicle"] as PlayerStateVehicle).request_exit(true)
	change_state("ragdoll", {"impulse": impulse, "duration": duration})


## NpcBase-compatible knock-down (vehicles and knock-down weapons call this on any character).
func knock_down(impulse: Vector3) -> void:
	ragdoll(impulse, 1.8)


## True right after a ragdoll was spawned (SAME_IMPACT_FRAMES, game time): further impulses belong to that impact.
func is_same_impact() -> bool:
	return Engine.get_physics_frames() - _ragdoll_spawn_frame < SAME_IMPACT_FRAMES


## Pickup hooks (pickup_system.gd kinds "parachute" / "scuba").
func give_parachute() -> void:
	has_parachute = true
	if chute != null:
		chute.refresh_pack()


func give_scuba() -> void:
	has_scuba = true


## Height of the feet above the ground / water surface right below (ray on WORLD | PROP | VEHICLE,
## up to AGL_PROBE m; open water counts as ground). Used by the freefall trigger and the altimeter.
func measure_agl() -> float:
	if not is_inside_tree():
		return 0.0
	var p := global_position
	if _agl_query == null:
		_agl_query = PhysicsRayQueryParameters3D.new()
		_agl_query.collision_mask = Layers.WORLD | Layers.PROP | Layers.VEHICLE
	_agl_query.from = p + Vector3(0.0, 0.05, 0.0)
	_agl_query.to = p - Vector3(0.0, AGL_PROBE, 0.0)
	var ex: Array[RID] = [get_rid()]
	if current_vehicle is CollisionObject3D:
		ex.append((current_vehicle as CollisionObject3D).get_rid())
	_agl_query.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(_agl_query)
	var ground := -INF
	if not hit.is_empty():
		ground = (hit["position"] as Vector3).y
	elif Game.world != null:
		ground = Game.ground_height(p.x, p.z)
	# open water: the surface is the "ground" (the sea floor plane runs under the whole island)
	var surf := water_surface_y if current_vehicle == null else Game.WATER_LEVEL
	if ground < surf and Game.is_in_water(Vector3(p.x, surf - 0.1, p.z)):
		ground = surf
	if not is_finite(ground):
		return AGL_PROBE
	return maxf(p.y - ground, 0.0)


## Where the WeaponInventory's shots / throws start (its holder hook, docs/WEAPONS.md). Vector3.INF =
## no opinion (the inventory then uses its own eye height). Drive-by: the window point; blind fire over
## low cover: the standing eye height above the crouched body (shoot_height_override).
func get_shoot_origin() -> Vector3:
	if current_vehicle != null:
		return drive_by_window if drive_by_window.is_finite() else Vector3.INF
	if shoot_height_override >= 0.0 and is_inside_tree():
		return global_position + Vector3.UP * shoot_height_override
	return Vector3.INF


## The player is in the air with the parachute rig (freefall with a pack, or under the canopy).
func is_skydiving() -> bool:
	return state_id == "freefall" or state_id == "parachute"


func spawn_ragdoll(impulse: Vector3, hit_position: Vector3 = Vector3.INF) -> Ragdoll:
	clear_ragdoll()
	if visual == null:
		return null
	var rag := Ragdoll.spawn_from(visual, impulse, hit_position, velocity) as Ragdoll
	if rag == null:
		return null
	rag.persistent = true
	_ragdoll = rag
	_ragdoll_spawn_frame = Engine.get_physics_frames()
	set_visual_hidden("ragdoll", true)
	return rag


func get_active_ragdoll() -> Ragdoll:
	if _ragdoll != null and is_instance_valid(_ragdoll) and not _ragdoll.is_queued_for_deletion():
		return _ragdoll
	return null


func clear_ragdoll() -> void:
	if _ragdoll != null and is_instance_valid(_ragdoll):
		_ragdoll.dismiss()
	_ragdoll = null
	set_visual_hidden("ragdoll", false)


## Shows the animated visual again in the pose the ragdoll ended in and cross-fades to a crouch.
func blend_out_of_ragdoll(blend: float) -> void:
	var rag := get_active_ragdoll()
	set_visual_hidden("ragdoll", false)
	if rag != null and animator != null and animator.is_ready():
		rag.copy_pose_to(animator.skeleton)
		animator.set_state("crouch", 0.0)
		animator.crossfade_from_current(blend)
	elif animator != null:
		animator.set_state("crouch", blend)
	if rag != null:
		rag.dismiss()
	_ragdoll = null


# =================================================================================================
# Vehicles
# =================================================================================================

## Best vehicle the player could enter right now (group "vehicle", can_enter, door in reach).
func find_enterable_vehicle() -> Node3D:
	if not is_inside_tree():
		return null
	var best: Node3D = null
	var best_score := INF
	var pos := global_position
	var look := -global_basis.z
	if camera != null:
		look = camera.get_aim_direction()
	look.y = 0.0
	for n: Node in get_tree().get_nodes_in_group("vehicle"):
		var v := n as Node3D
		if v == null or not v.is_inside_tree() or v == _ignored_vehicle and _ignore_vehicle_t > 0.6:
			continue
		var centre := v.global_position
		if centre.distance_squared_to(pos) > 144.0:
			continue
		if not v.has_method("can_enter") or not bool(v.call("can_enter", self)):
			continue
		var door := centre
		if v.has_method("get_exit_transform"):
			var r: Variant = v.call("get_exit_transform", pick_seat(v))
			if r is Transform3D:
				door = (r as Transform3D).origin
		var d := minf(Vector2(door.x - pos.x, door.z - pos.z).length(), Vector2(centre.x - pos.x, centre.z - pos.z).length() - 0.4)
		if d > VEHICLE_REACH or absf(door.y - pos.y) > 3.0:
			continue
		var to := centre - pos
		to.y = 0.0
		var facing := 0.0
		if to.length_squared() > 0.01 and look.length_squared() > 0.01:
			facing = to.normalized().dot(look.normalized())
		var score := d - facing * 0.8
		if score < best_score:
			best_score = score
			best = v
	return best


## Seat the player takes when pressing the enter key: the driver seat. (Passenger rides go
## through enter_vehicle(vehicle, seat) directly.)
func pick_seat(_vehicle: Node3D) -> int:
	return 0


func enter_vehicle(vehicle: Node3D, seat: int = 0, instant: bool = false) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or is_dead:
		return
	if current_vehicle == vehicle:
		return
	if current_vehicle != null or state_id == "vehicle":
		(states["vehicle"] as PlayerStateVehicle).request_exit(true)
	if state_id == "ragdoll":
		clear_ragdoll()
	seat_index = seat
	# the SAME door distance the vehicle state walks (Wave 1 bug: the centre distance was tested
	# here and the door distance there, so a car < 8 m away with its door > 9 m away aborted)
	var door := PlayerStateVehicle.door_transform_of(vehicle, seat).origin
	var far := global_position.distance_to(door) > VEHICLE_WALK_MAX
	change_state("vehicle", {"vehicle": vehicle, "seat": seat, "instant": instant or far})


func exit_vehicle() -> void:
	if state_id == "vehicle":
		(states["vehicle"] as PlayerStateVehicle).request_exit(false)


func is_in_vehicle() -> bool:
	return current_vehicle != null


## Vehicle side hook (VehicleBase.eject_occupants / carjack): the vehicle already freed the seat
## and throws the player out at `exit_xform` with `impulse` (N*s).
func on_vehicle_ejected(vehicle: Node, exit_xform: Transform3D, impulse: Vector3 = Vector3.ZERO) -> void:
	if state_id != "vehicle":
		return
	var st := states["vehicle"] as PlayerStateVehicle
	if st.vehicle != vehicle:
		return
	st.eject(exit_xform, impulse)


## Called by the vehicle state: become a child of the seat node (local transform identity).
func attach_to_seat(seat_node: Node3D, vehicle: Node) -> void:
	if seat_node == null or not is_instance_valid(seat_node):
		return
	if _attached_vehicle != null and is_instance_valid(_attached_vehicle) and _attached_vehicle.tree_exiting.is_connected(_on_vehicle_tree_exiting):
		_attached_vehicle.tree_exiting.disconnect(_on_vehicle_tree_exiting)
	_attached_vehicle = vehicle
	if vehicle != null and not vehicle.tree_exiting.is_connected(_on_vehicle_tree_exiting):
		vehicle.tree_exiting.connect(_on_vehicle_tree_exiting)
	if get_parent() != seat_node:
		_reattaching = true
		reparent(seat_node, false)
		_reattaching = false
	transform = Transform3D.IDENTITY
	_visual_drop = 0.0
	if visual != null:
		visual.position.y = 0.0


## Called by the vehicle state: go back under the node the player lived in before.
func detach_from_seat() -> void:
	if _attached_vehicle != null and is_instance_valid(_attached_vehicle) and _attached_vehicle.tree_exiting.is_connected(_on_vehicle_tree_exiting):
		_attached_vehicle.tree_exiting.disconnect(_on_vehicle_tree_exiting)
	_attached_vehicle = null
	var home := _get_home()
	if home == null or get_parent() == home or not is_inside_tree():
		return
	_reattaching = true
	reparent(home, true)
	_reattaching = false


func _get_home() -> Node:
	if _home_parent != null and is_instance_valid(_home_parent) and _home_parent.is_inside_tree():
		return _home_parent
	if Game.main != null and is_instance_valid(Game.main) and Game.main.is_inside_tree():
		return Game.main
	return get_tree().current_scene if is_inside_tree() else null


## Safety net: the vehicle (or one of its ancestors) leaves the tree while the player sits in it.
## Without this the player would be freed together with the vehicle.
func _on_vehicle_tree_exiting() -> void:
	var v := _attached_vehicle
	if v == null or not is_instance_valid(v) or not v.is_ancestor_of(self):
		return
	var keep := global_transform if is_inside_tree() else (v as Node3D).global_transform if v is Node3D and v.is_inside_tree() else Transform3D.IDENTITY
	var home := _get_home()
	if home == null or home == v or v.is_ancestor_of(home):
		return                      # the whole world is going away
	var parent := get_parent()
	if parent == null:
		return
	parent.remove_child(self)
	# Wave 1 bug: the home node used to be passed as an argument of the deferred call. When the
	# game quits while the player sits in a vehicle, Main is freed before the deferred call runs and
	# the engine failed with "_rehome: Cannot convert argument 1 from Object to Object". The home is
	# now looked up by instance id when the call runs.
	_rehome_home_id = home.get_instance_id()
	_rehome_keep = keep
	_rehome.call_deferred()


func _rehome() -> void:
	var home := instance_from_id(_rehome_home_id) as Node
	_rehome_home_id = 0
	var keep := _rehome_keep
	if home == null or not is_instance_valid(home) or not home.is_inside_tree() or home.is_queued_for_deletion():
		if not is_inside_tree() and not is_queued_for_deletion():
			queue_free()            # the world went away (quit / scene change): nothing to return to
		return
	if get_parent() == null:
		home.add_child(self)
	global_transform = Transform3D(Basis(Vector3.UP, keep.basis.get_euler().y), keep.origin + Vector3(0.0, 0.3, 0.0))
	current_vehicle = null
	_attached_vehicle = null
	set_collision_enabled(true)
	velocity = Vector3.ZERO
	if state_id == "vehicle":
		EventBus.player_exited_vehicle.emit(null)
		if is_dead:
			change_state("dead", {})
		else:
			change_state("air", {})


func ignore_vehicle_hits(vehicle: Node, seconds: float) -> void:
	_ignored_vehicle = vehicle
	_ignore_vehicle_t = seconds


## Seated animation tuning from the vehicle (steering wheel / handlebar position). null resets.
func set_seated_tuning(vehicle: Node3D) -> void:
	var a := animator
	if a == null:
		return
	a.wheel_pos = Vector3(0.0, 0.33, -0.43)
	a.bar_pos = Vector3(0.0, 0.31, -0.55)
	anim_steer = 0.0
	if vehicle == null or not is_instance_valid(vehicle) or not is_inside_tree():
		return
	var inv := global_transform.affine_inverse()
	var wheel := vehicle.find_child("SteeringWheel", true, false) as Node3D
	if wheel != null:
		var local := inv * wheel.global_position
		if local.length() < 1.2 and local.z < -0.15:
			a.wheel_pos = local
	var bar := vehicle.find_child("Handlebar", true, false) as Node3D
	if bar != null:
		var lb := inv * bar.global_position
		if lb.length() < 1.4 and lb.z < -0.2:
			a.bar_pos = Vector3(0.0, clampf(lb.y + 0.25, 0.15, 0.6), lb.z + 0.08)


func _check_vehicle_hits() -> void:
	if _vehicle_hit_cd > 0.0 or is_dead or not _collision_on:
		return
	# monitoring is switched with set_deferred, so it can lag one tick behind _collision_on
	if not _vehicle_sensor.monitoring or not _vehicle_sensor.has_overlapping_bodies():
		return
	for b: Node3D in _vehicle_sensor.get_overlapping_bodies():
		var rb := b as RigidBody3D
		if rb == null or rb == _ignored_vehicle:
			continue
		var rel := rb.linear_velocity - velocity
		var speed := rel.length()
		if speed < VEHICLE_HIT_SPEED:
			continue
		var to_me := global_position - rb.global_position
		to_me.y = 0.0
		if rel.dot(to_me) <= 0.0:
			continue
		var dmg := clampf((speed - VEHICLE_HIT_SPEED) * VEHICLE_HIT_DAMAGE_PER_MS, 4.0, 160.0)
		var dir := rel / speed
		apply_damage(Dmg.make(dmg, "vehicle", rb, global_position + Vector3(0.0, 0.8, 0.0), dir, {"impulse": speed * 55.0}))
		return


# =================================================================================================
# Placement / control / persistence
# =================================================================================================

func teleport(pos: Vector3, yaw: float = 0.0) -> void:
	if vehicle_ix != null:
		vehicle_ix.cancel()             # a tap / hold decision pending on a vehicle that is now far away
	if chute != null:
		chute.release_canopy("reset")   # an open canopy does not travel along
	altitude_agl = 0.0
	if current_vehicle != null or state_id == "vehicle":
		(states["vehicle"] as PlayerStateVehicle).request_exit(true)
	if not is_dead:
		clear_ragdoll()
	_place(pos, yaw)
	if not is_dead and state_id != "on_foot":
		change_state("on_foot", {})


func _place(pos: Vector3, yaw: float) -> void:
	if is_inside_tree():
		# Jolt moves a kinematic body to a new transform as a sweep in the next step: whatever the
		# capsule touched (a boat it stood on, a car beside it) was kicked with tens of m/s. No shape for
		# the next physics ticks (review item of the bikes / boats programmer).
		_ghost_ticks = TELEPORT_GHOST_TICKS
		if _collider != null:
			_collider.set_deferred("disabled", true)
		global_position = pos
		global_rotation = Vector3(0.0, yaw, 0.0)
	else:
		position = pos
		rotation = Vector3(0.0, yaw, 0.0)
	velocity = Vector3.ZERO
	_prev_yaw = yaw
	_yaw_rate = 0.0
	_visual_drop = 0.0
	_was_grounded = false
	grounded = false
	if visual != null:
		visual.position.y = 0.0
	if not is_dead:
		set_collision_enabled(true)
	if is_inside_tree():
		update_water()
	snap_animator()
	if camera != null:
		camera.snap_to(yaw)


## Disable / enable player control (cut-scenes of other systems, shops, arrests). Physics keeps
## running; only the input is ignored.
func set_control_enabled(on: bool) -> void:
	_control_enabled = on
	if not on:
		release_trigger()
		set_aiming(false)


func get_appearance() -> Dictionary:
	if visual != null and visual.has_method("get_appearance"):
		var a: Variant = visual.call("get_appearance")
		if a is Dictionary:
			return a
	return {}


func set_appearance(appearance: Dictionary) -> void:
	if visual != null and visual.has_method("apply_appearance"):
		visual.call("apply_appearance", appearance)
		EventBus.player_appearance_changed.emit(get_appearance())


func get_save_data() -> Dictionary:
	var pos := Game.get_player_position() if is_inside_tree() else position
	if is_dead:
		pos = Game.get_location("hospital").origin
	elif (is_skydiving() or state_id == "air") and last_safe_position.is_finite():
		pos = last_safe_position        # never load into mid-air (a fall / jump in progress)
	var d := {
		"position": SaveSystem.vec3_to_array(pos),
		"yaw": global_rotation.y if is_inside_tree() else rotation.y,
		"health": health if not is_dead else max_health,
		"armor": armor,
		"has_parachute": has_parachute,
		"has_scuba": has_scuba,
		"appearance": get_appearance(),
		"treasures": Array(treasures_found),
	}
	return d


func load_save_data(d: Dictionary) -> void:
	# every value is read type-safely: a hand-edited / older / corrupt save (null, strings, NaN) must
	# never raise a script error or put the player at a non-finite position (review fix)
	var here := global_position if is_inside_tree() else position
	var pos: Vector3 = here
	var pv: Variant = d.get("position", null)
	if pv is Array and (pv as Array).size() >= 3:
		var pa := pv as Array
		var cand := Vector3(_save_num(pa[0], INF), _save_num(pa[1], INF), _save_num(pa[2], INF))
		if cand.is_finite():
			pos = cand
	var yaw := _save_num(d.get("yaw", 0.0), 0.0)
	if is_dead:
		respawn(Transform3D(Basis(Vector3.UP, yaw), pos))
	else:
		teleport(pos, yaw)
	health = clampf(_save_num(d.get("health", max_health), max_health), 1.0, max_health)
	armor = clampf(_save_num(d.get("armor", 0.0), 0.0), 0.0, max_armor)
	# (a typed check: Variant == bool raises a script error for a String)
	var hp: Variant = d.get("has_parachute", false)
	has_parachute = hp is bool and hp
	var hs: Variant = d.get("has_scuba", false)
	has_scuba = hs is bool and hs
	if chute != null:
		chute.refresh_pack()
	# one-time treasures (older saves have none: every treasure is still there)
	treasures_found = PackedStringArray()
	var tv: Variant = d.get("treasures", [])
	if tv is Array:
		for t: Variant in tv:
			if t is String and t != "" and not treasures_found.has(t):
				treasures_found.append(t)
	if dive != null:
		dive.refresh_treasures()
	var app: Variant = d.get("appearance", null)
	if app is Dictionary and not (app as Dictionary).is_empty():
		set_appearance(app)
	EventBus.player_health_changed.emit(health, armor)


## A finite number from a save value (JSON gives floats; strings of digits are accepted), else `def`.
static func _save_num(v: Variant, def: float) -> float:
	var f := def
	if v is float or v is int:
		f = float(v)
	elif v is String and (v as String).is_valid_float():
		f = (v as String).to_float()
	return f if is_finite(f) else def      # (def may itself be INF: "no usable value")
