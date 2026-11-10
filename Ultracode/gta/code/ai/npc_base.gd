class_name NpcBase
extends CharacterBody3D
## NPC BODY (ARCHITECTURE 6.7, ARCHITECTURE_WAVE2 W2.2): movement, senses, weapon handling,
## animation, damage, knock-down, death. Decisions live in a BRAIN node (any Node with
## `think(npc, delta)` and optional `on_event(npc, event, data)`), see docs/AI.md.
##
## The PedSystem ("peds") drives every registered NPC from one loop:
##   physics_tick(delta)  movement (tier 0: move_and_slide, tier 1/2: kinematic glide on the path)
##   think_tick(delta)    senses + brain, at the tier rate (10 / 3.3 / 1 Hz)
##   anim_tick(delta)     animator parameters + HumanoidAnimator.advance (rate-limited by tier)
## An NpcBase that no PedSystem registered (tests, other spawners) processes itself.
##
## Neighbours are soft dependencies: the character visual, animator, ragdoll, weapon model and
## pickups are looked up by path / system name and may be missing.

signal died(npc: Node3D, killer: Node)
signal damaged(npc: Node3D, info: Dictionary)
## A firearm is pointed at this NPC (emitted about 6 times a second while it lasts; `threatened_time`
## holds the seconds of the current threat). Shops use it for the robbery hook.
signal threatened(npc: Node3D, by: Node)
signal knocked_down(npc: Node3D)
signal got_up(npc: Node3D)

const HUMANOID_SCENE := "res://gta/scenes/characters/humanoid.tscn"
const ANIMATOR_SCRIPT := "res://gta/code/characters/humanoid_animator.gd"
const RAGDOLL_SCRIPT := "res://gta/code/characters/ragdoll.gd"
const WEAPON_MODEL_SCRIPT := "res://gta/code/weapons/weapon_model.gd"
const VISUAL_SCRIPT := "res://gta/code/characters/character_visual.gd"
const FALLBACK_BRAIN := "res://gta/code/ai/brains/ai_brain_civilian.gd"

const RADIUS := 0.32
const HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const EYE_HEIGHT := 1.62
const CROUCH_EYE_HEIGHT := 1.05
const GRAVITY := 20.0
const ACCEL := 9.0
const TURN_RATE := 7.5
const SAME_IMPACT_FRAMES := 15
const GET_UP_TIME := 1.0
const CORPSE_FREE_DELAY := 6.0          ## non-persistent dead NPC nodes are freed after this (the ragdoll lives on)
const ASSAULT_REPORT_COOLDOWN := 3.0    ## one "assault" per victim per 3 s (an SMG burst is one assault)
const CROSS_WAIT_MAX := 9.0
const CROSS_CHECK_INTERVAL := 0.4
const MAX_COVER_SEARCHES_PER_FRAME := 3
const TIER_ANIM_HZ: Array[float] = [30.0, 8.0, 2.0]
## Bench pose (animator seated_car re-used with feet on the ground and hands on the thighs).
const BENCH_SEAT_HEIGHT := 0.41
const BENCH_PEDAL := Vector3(0.13, -0.38, -0.30)
const BENCH_WHEEL := Vector3(0.0, -0.02, -0.24)
const BENCH_WHEEL_RADIUS := 0.15
## Service poses (emergency responders): "kneel" = deep crouch, body lowered so the knees touch the
## ground, both hands on the patient's chest (CPR compressions); "spray" = two-handed rifle-style
## hold aimed at the fire (no nozzle model exists: see docs/EMERGENCY.md).
const SERVICE_POSES: Array[String] = ["kneel", "spray"]
const KNEEL_SINK := 0.24
const KO_DEFAULT_SECONDS := 30.0
const KO_MAX_SECONDS := 120.0

static var _script_cache: Dictionary = {}
## path planning cost (debug / perf tests): count, total and worst microseconds of walk_to / move_to
static var path_stats: Dictionary = {"walk_n": 0, "walk_us": 0.0, "walk_max": 0.0, "nav_n": 0, "nav_us": 0.0, "nav_max": 0.0,
		"crossings": 0, "crossing_waits": 0}
static var _cover_frame: int = -1
static var _cover_count: int = 0
## cover spots claimed by NPCs (instance id -> Vector3) so a squad spreads out
static var _cover_claims: Dictionary = {}

# --- contract members (W2.2) -------------------------------------------------------------------
var faction: String = "civilian"
var archetype_id: String = ""
var health: float = 100.0
var is_dead: bool = false
var weapon_id: String = ""
var current_vehicle: Node3D = null
var brain: Node = null
var state_tag: String = "idle"
var accuracy: float = 0.4

# --- additional public state --------------------------------------------------------------------
var max_health: float = 100.0
var armor: float = 0.0
var archetype: Resource = null              ## NpcArchetype
var visual: Node3D = null                   ## CharacterVisual (humanoid.tscn)
var animator: Node = null                   ## HumanoidAnimator
var senses: AiSenses = null
var sim_tier: int = 0
var persistent: bool = false
var hostile: bool = false
var cash_carried: int = 0                   ## read by the pickups system on death
var home_position: Vector3 = Vector3.ZERO
var home_yaw: float = 0.0
var seat_index: int = -1
var is_down: bool = false                   ## knocked down (ragdoll) or getting up
var is_crouching: bool = false
var is_aiming: bool = false
var height: float = HEIGHT                  ## Combat reads it for hit zones
var threatened_time: float = 0.0            ## seconds a firearm has been pointed at us (0 = not now)
var threatened_by: Node = null
var last_attacker: Node = null
var last_damage_info: Dictionary = {}
var walk_speed: float = 1.45
var run_speed: float = 4.2
var sprint_speed: float = 6.0
var speed_mult: float = 1.0
var managed: bool = false                   ## true while a PedSystem drives this NPC
var ambient: bool = false                   ## spawned by the population (PedSystem bookkeeping)
var gesture: float = 0.0                    ## 0..1 talking hand gesture (procedural)
var phone_pose: bool = false                ## hand at the ear (witness call)
var look_target: Vector3 = Vector3.INF      ## head look (talking, annoyed)
var last_cover_info: Dictionary = {}        ## filled by find_cover_from: {position, low, peek, normal}
var dead_time: float = 0.0
var think_accum: float = 0.0
var avoid: Vector3 = Vector3.ZERO           ## planar avoidance push, written by the PedSystem
var knocked_out: bool = false               ## down from a takedown knock-out (info.knockout), see knock_out_time
var corpse_held: bool = false               ## hold_corpse(true): the body stays until released (emergency medics)

# --- internals ------------------------------------------------------------------------------------
var _built: bool = false
var _col: CollisionShape3D = null
var _shape: CapsuleShape3D = null
var _pose: String = ""                      ## "", "cower", "surrender", "sit"
var _path: PackedVector3Array = PackedVector3Array()
var _path_kind: PackedByteArray = PackedByteArray()
var _path_i: int = 0
var _moving: bool = false
var _final_target: Vector3 = Vector3.INF
var _speed_mode: String = "walk"
var _face_pos: Vector3 = Vector3.INF
var _aim_pos: Vector3 = Vector3.INF
var _yaw_rate: float = 0.0
var _glide_vel: Vector3 = Vector3.ZERO
var _stuck_t: float = 0.0
var _stuck_ref: Vector3 = Vector3.ZERO
var _stuck_count: int = 0
var _cross_wait: bool = false
var _crossing: bool = false
var _cross_wait_t: float = 0.0
var _cross_check_t: float = 0.0
var _cross_a: Vector3 = Vector3.ZERO
var _cross_b: Vector3 = Vector3.ZERO
var _spec: Resource = null                  ## WeaponSpec
var _mag: int = 0
var _mag_size: int = 0
var _fire_interval: float = 0.3
var _fire_cd: float = 0.0
var _reload_t: float = 0.0
var _melee_cd: float = 0.0
var _punch_left: bool = false
var _weapon_model: Node3D = null
var _weapon_pose: String = "none"
var _ragdoll: Node3D = null
var _ragdoll_frame: int = -100000
var _down_t: float = 0.0
var _down_duration: float = 2.5
var _getup_t: float = 0.0
var _threat_refresh: float = 0.0
var _last_assault_report: float = -1000.0
var _murder_reported: bool = false
var _pending_vehicle: Node3D = null
var _pending_seat: int = 0
var _pending_t: float = 0.0
var _water_t: float = 0.0
var _pain_cd: float = 0.0
var _bump_cd: float = 0.0
var _gesture_t: float = 0.0
var _anim_defaults: Dictionary = {}
var _tier_applied: bool = false


# =================================================================================================
# construction / pooling
# =================================================================================================

func _init() -> void:
	collision_layer = Layers.NPC
	collision_mask = Layers.NPC_MASK
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.45
	safe_margin = 0.02
	_shape = CapsuleShape3D.new()
	_shape.radius = RADIUS
	_shape.height = HEIGHT
	_col = CollisionShape3D.new()
	_col.name = "Capsule"
	_col.shape = _shape
	_col.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(_col)
	senses = AiSenses.new()
	senses.npc = self
	set_physics_process(false)
	set_process(false)


func _ready() -> void:
	_build_body()
	if not _tier_applied:
		set_sim_tier(0)
	if not managed:
		set_physics_process(true)
		set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# a knocked-down body (persistent ragdoll) goes with us; a corpse ragdoll is NOT ours to
		# remove: it has its own lifetime (before this, every corpse vanished with the node 6 s
		# after death, CORPSE_FREE_DELAY)
		if _ragdoll != null and is_instance_valid(_ragdoll) and is_dead and _ragdoll.get("persistent") != true:
			_ragdoll = null
		_clear_ragdoll()


static func load_script(path: String) -> Script:
	if _script_cache.has(path):
		return _script_cache[path]
	var s: Script = null
	if ResourceLoader.exists(path):
		s = load(path) as Script
	_script_cache[path] = s
	return s


static func _load_scene(path: String) -> PackedScene:
	if _script_cache.has(path):
		return _script_cache[path]
	var s: PackedScene = null
	if ResourceLoader.exists(path):
		s = load(path) as PackedScene
	_script_cache[path] = s
	return s


func _build_body() -> void:
	if _built:
		return
	_built = true
	add_to_group("npc")
	var scene := _load_scene(HUMANOID_SCENE)
	if scene != null:
		visual = scene.instantiate() as Node3D
		if visual != null:
			visual.name = "Visual"
			add_child(visual)
	var an := load_script(ANIMATOR_SCRIPT)
	if an != null and visual != null and visual.has_method("get_skeleton"):
		var skel: Variant = visual.call("get_skeleton")
		if skel is Skeleton3D:
			animator = an.new() as Node
			animator.name = "Animator"
			add_child(animator)
			if animator.has_method("setup") and bool(animator.call("setup", skel)):
				animator.set("auto_process", false)
				for k in ["wheel_pos", "wheel_radius", "pedal_pos"]:
					_anim_defaults[k] = animator.get(k)
			else:
				animator.queue_free()
				animator = null


## Called by the PedSystem right after add_child (or by tests). `arch` is an NpcArchetype.
## opts: W2.2 spawn options {"yaw", "brain", "weapon", "hostile", "persistent", "vehicle", "seat",
## "appearance"} plus "visual" (CharacterVisual archetype override) and "home" (Vector3).
func configure(arch: Resource, opts: Dictionary = {}, rng_seed: int = 0) -> void:
	_build_body()
	archetype = arch
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(rng_seed) ^ 0x2545F491
	if arch != null:
		archetype_id = str(arch.get("id"))
		faction = str(arch.get("faction"))
		var groups: PackedStringArray = arch.get("groups")
		for g: String in groups:
			add_to_group(g)
		max_health = float(arch.get("max_health"))
		armor = float(arch.get("armor"))
		accuracy = float(arch.get("accuracy"))
		walk_speed = float(arch.get("walk_speed")) * rng.randf_range(0.9, 1.1)
		run_speed = float(arch.get("run_speed")) * rng.randf_range(0.93, 1.07)
		sprint_speed = float(arch.get("sprint_speed")) * rng.randf_range(0.93, 1.07)
		var cmin := int(arch.get("cash_min"))
		var cmax := int(arch.get("cash_max"))
		cash_carried = rng.randi_range(cmin, maxi(cmin, cmax)) if cmax > 0 else 0
	health = max_health
	senses.setup(self, arch)
	persistent = bool(opts.get("persistent", false))
	hostile = bool(opts.get("hostile", false))
	rotation = Vector3(0.0, float(opts.get("yaw", rotation.y)), 0.0)
	home_position = opts.get("home", global_position) if is_inside_tree() else Vector3.ZERO
	home_yaw = rotation.y
	# look
	if visual != null:
		var look: Dictionary = {}
		var a: Variant = opts.get("appearance", null)
		if a is Dictionary and not (a as Dictionary).is_empty():
			look = a
		else:
			look = _make_look(arch, str(opts.get("visual", "")), rng_seed, rng)
		if visual.has_method("apply_appearance"):
			visual.call("apply_appearance", look)
	if animator != null and animator.has_method("snap"):
		animator.call("snap")
	# weapon
	var w: Variant = opts.get("weapon", null)
	if w == null and arch != null and arch.has_method("pick_weapon"):
		w = arch.call("pick_weapon", rng)
	set_weapon(str(w) if w != null else "")
	# brain
	var b: Variant = opts.get("brain", null)
	if b == null and arch != null and str(arch.get("brain_path")) != "":
		b = load_script(str(arch.get("brain_path")))
	if b == null:
		b = load_script(FALLBACK_BRAIN)
	if b is Script:
		set_brain((b as Script).new() as Node)
	elif b is Node:
		set_brain(b as Node)
	# vehicle
	var v: Variant = opts.get("vehicle", null)
	if v != null and is_instance_valid(v) and v is Node3D:
		enter_vehicle(v as Node3D, int(opts.get("seat", 0)), true)
	_notify("spawned", opts)


func _make_look(arch: Resource, forced_visual: String, rng_seed: int, rng: RandomNumberGenerator) -> Dictionary:
	var vs := load_script(VISUAL_SCRIPT)
	var vis_arch := forced_visual
	if vis_arch == "" and arch != null and arch.has_method("pick_visual"):
		vis_arch = str(arch.call("pick_visual", rng))
	if vis_arch == "":
		vis_arch = "civilian"
	var want_body := str(arch.get("body")) if arch != null else ""
	var look: Dictionary = {}
	if vs != null:
		for i in 8:
			look = vs.call("make_appearance", vis_arch, rng_seed + i * 7919)
			if want_body == "" or str(look.get("body", "")) == want_body:
				break
	if arch != null and arch.has_method("decorate_appearance"):
		look = arch.call("decorate_appearance", look, rng)
	return look


## Back to a blank body for the PedSystem pool (outside the tree).
func reset_for_pool() -> void:
	for sig: String in ["died", "damaged", "threatened", "knocked_down", "got_up"]:
		for c: Dictionary in get_signal_connection_list(sig):
			disconnect(sig, c["callable"])
	for g in get_groups():
		if str(g) != "npc" and not str(g).begins_with("_"):
			remove_from_group(g)
	if brain != null and is_instance_valid(brain):
		brain.queue_free()
	brain = null
	_clear_weapon_model()
	_clear_ragdoll()
	release_cover()
	weapon_id = ""
	_spec = null
	is_dead = false
	is_down = false
	is_aiming = false
	hostile = false
	persistent = false
	ambient = false
	current_vehicle = null
	seat_index = -1
	_pending_vehicle = null
	threatened_time = 0.0
	threatened_by = null
	last_attacker = null
	last_damage_info = {}
	_murder_reported = false
	_last_assault_report = -1000.0
	knocked_out = false
	corpse_held = false
	speed_mult = 1.0
	dead_time = 0.0
	gesture = 0.0
	phone_pose = false
	look_target = Vector3.INF
	last_cover_info = {}
	velocity = Vector3.ZERO
	avoid = Vector3.ZERO
	_getup_t = 0.0
	_water_t = 0.0
	_pose = ""
	state_tag = "idle"
	stop_moving()
	stop_aiming()
	_face_pos = Vector3.INF
	set_crouched(false)
	_set_collision(true)
	if visual != null:
		visual.visible = true
		visual.position = Vector3.ZERO
	senses.reset()


# =================================================================================================
# ticking (driven by the PedSystem, or by ourselves when unmanaged)
# =================================================================================================

func _physics_process(delta: float) -> void:
	if managed:
		return
	AiSenses.tick_clock(delta)
	physics_tick(delta)
	think_accum += delta
	var interval := 0.1 if sim_tier == 0 else (0.3 if sim_tier == 1 else 1.0)
	if think_accum >= interval:
		think_tick(think_accum)
		think_accum = 0.0


func _process(delta: float) -> void:
	if managed:
		return
	anim_tick(delta)


func physics_tick(delta: float) -> void:
	if not _built or not is_inside_tree():
		return
	if is_dead:
		dead_time += delta
		_follow_ragdoll()
		return
	_tick_timers(delta)
	if current_vehicle != null:
		if not is_instance_valid(current_vehicle):
			_vehicle_gone()
		return
	if is_down:
		_tick_down(delta)
		return
	if _pose == "sit":
		# on a bench: collision is off, so no gravity / sliding at all
		velocity = Vector3.ZERO
		_glide_vel = Vector3.ZERO
		_yaw_rate = 0.0
		return
	if _pending_vehicle != null:
		_tick_pending_vehicle(delta)
	var desired := _steer(delta)
	_update_facing(delta, desired)
	if sim_tier == 0:
		var k := 1.0 - exp(-ACCEL * delta)
		velocity.x = lerpf(velocity.x, desired.x, k)
		velocity.z = lerpf(velocity.z, desired.z, k)
		if is_on_floor():
			velocity.y = -0.6
		else:
			velocity.y = maxf(velocity.y - GRAVITY * delta, -40.0)
		move_and_slide()
		if get_slide_collision_count() > 0:
			_check_slide_collisions()
		_glide_vel = Vector3(velocity.x, 0.0, velocity.z)
		_check_stuck(delta)
		if global_position.y < -60.0:
			_fell_out()
	else:
		_glide(desired, delta)


func think_tick(delta: float) -> void:
	if is_dead or not is_inside_tree():
		return
	if current_vehicle == null and not is_down:
		senses.update(delta)
		_check_water(delta)
	if brain != null and is_instance_valid(brain) and brain.has_method("think"):
		brain.call("think", self, delta)


func anim_tick(delta: float) -> void:
	if animator == null or not is_instance_valid(animator):
		return
	if visual != null and not visual.visible and not is_dead:
		return
	var a := animator
	var planar := _glide_vel
	var sp := planar.length()
	a.set("speed", sp)
	if sp > 0.2:
		var local := global_basis.inverse() * (planar / sp)
		a.set("move_dir_local", Vector2(local.x, -local.z))
	a.set("turn_rate", _yaw_rate)
	a.set("lean", clampf(-_yaw_rate * sp * 0.03, -0.6, 0.6))
	a.set("state", _anim_state())
	var spraying := _pose == "spray" and not is_down and current_vehicle == null
	var aim := (is_aiming and not is_down and current_vehicle == null and _pose == "") or spraying
	a.set("aim_weight", 1.0 if aim else 0.0)
	if aim and _aim_pos != Vector3.INF:
		var eye := get_eye_position()
		var to := _aim_pos - eye
		var flat := Vector2(to.x, to.z).length()
		a.set("aim_pitch", clampf(atan2(to.y, maxf(flat, 0.01)), -1.2, 1.2))
	else:
		a.set("aim_pitch", 0.0)
	a.set("weapon_pose", "rifle" if spraying else _weapon_pose)
	# head look
	if look_target != Vector3.INF and not aim:
		var to_l := look_target - get_eye_position()
		var local_l := global_basis.inverse() * to_l
		a.set("look_yaw", clampf(atan2(-local_l.x, -local_l.z), -1.1, 1.1))
		a.set("look_pitch", clampf(atan2(local_l.y, Vector2(local_l.x, local_l.z).length()), -0.5, 0.5))
	else:
		a.set("look_yaw", 0.0)
		a.set("look_pitch", -0.85 if (is_dead and current_vehicle != null) else 0.0)
	# procedural hand layers: CPR, phone call, dazed hand on the head, talking gestures
	if _pose == "kneel" and not is_down:
		_gesture_t += delta
		# chest compressions, about 1.8 per second: heels of both hands on the patient's sternum
		var push := absf(sin(_gesture_t * PI * 1.8))
		var hy := 0.44 + KNEEL_SINK * 0.25 + 0.06 * push
		a.set("hand_target_r", Vector3(0.05, hy, -0.50))
		a.set("hand_target_l", Vector3(-0.05, hy + 0.02, -0.52))
		a.set("hand_target_weight_r", 1.0)
		a.set("hand_target_weight_l", 1.0)
	elif state_tag == "dazed" and not is_down:
		a.set("hand_target_r", Vector3(0.10, 1.68, -0.08))
		a.set("hand_target_weight_r", 0.85)
		a.set("hand_target_weight_l", 0.0)
	elif phone_pose:
		a.set("hand_target_r", Vector3(0.11, 1.56, -0.05))
		a.set("hand_target_weight_r", 1.0)
	elif gesture > 0.01:
		_gesture_t += delta
		var t := _gesture_t
		a.set("hand_target_r", Vector3(0.22 + 0.05 * sin(t * 2.3), 1.08 + 0.07 * sin(t * 3.7), -0.30 + 0.04 * sin(t * 1.9)))
		a.set("hand_target_weight_r", gesture * (0.55 + 0.35 * sin(t * 0.9)))
		a.set("hand_target_l", Vector3(-0.20 - 0.04 * sin(t * 2.9), 1.02 + 0.06 * sin(t * 2.1 + 1.0), -0.26))
		a.set("hand_target_weight_l", gesture * maxf(0.0, 0.5 * sin(t * 0.7 + 2.0)))
	else:
		a.set("hand_target_weight_r", 0.0)
		a.set("hand_target_weight_l", 0.0)
	a.call("advance", delta)


func _anim_state() -> String:
	if is_dead:
		if current_vehicle != null:
			return "seated_car"
		return "dead"
	if current_vehicle != null:
		var vc := str(current_vehicle.get("vehicle_class"))
		return "seated_bike" if (vc == "bike" or vc == "bicycle") else "seated_car"
	if _pose == "sit":
		return "seated_car"
	if _pose == "kneel":
		return "crouch"
	if _pose == "spray":
		return "idle"
	if _pose != "":
		return _pose
	if is_down:
		return "crouch"
	if is_crouching:
		return "crouch"
	if _glide_vel.length_squared() > 0.04:
		return "locomotion"
	return "idle"


func _tick_timers(delta: float) -> void:
	if _fire_cd > 0.0:
		_fire_cd -= delta
	if _melee_cd > 0.0:
		_melee_cd -= delta
	if _pain_cd > 0.0:
		_pain_cd -= delta
	if _bump_cd > 0.0:
		_bump_cd -= delta
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			_reload_t = 0.0
			_mag = _mag_size
			if _weapon_model != null and is_instance_valid(_weapon_model) and _weapon_model.has_method("set_mag_loaded"):
				_weapon_model.call("set_mag_loaded", true)
	if threatened_time > 0.0:
		_threat_refresh -= delta
		if _threat_refresh <= 0.0:
			threatened_time = 0.0
			threatened_by = null


# =================================================================================================
# movement API (W2.2)
# =================================================================================================

## Free target (cover, chase, door): navigation-mesh path, straight line when no mesh answers.
func move_to(target: Vector3, speed_mode: String = "walk") -> void:
	if is_dead or current_vehicle != null:
		return
	_speed_mode = speed_mode
	_leave_pose()
	var t0 := Time.get_ticks_usec()
	var path := PackedVector3Array()
	if is_inside_tree():
		var map := get_world_3d().navigation_map
		if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
			path = NavigationServer3D.map_get_path(map, global_position, target, true)
	if path.size() < 2 or path[path.size() - 1].distance_to(target) > 2.5:
		path = PackedVector3Array([target])
	else:
		# the mesh path starts where we stand; keep the exact target as the last point
		path.remove_at(0)
		if path[path.size() - 1].distance_to(target) > 0.3:
			path.append(target)
	_note_path_cost("nav", t0)
	_start_path(path, PackedByteArray())


static func _note_path_cost(kind: String, t0: int) -> void:
	var us := float(Time.get_ticks_usec() - t0)
	path_stats[kind + "_n"] = int(path_stats[kind + "_n"]) + 1
	path_stats[kind + "_us"] = float(path_stats[kind + "_us"]) + us
	path_stats[kind + "_max"] = maxf(float(path_stats[kind + "_max"]), us)


## Ambient target on the sidewalk network (WalkGraph): crosswalks, waiting for traffic.
## Falls back to move_to when there is no walk graph.
func walk_to(target: Vector3, speed_mode: String = "walk") -> void:
	if is_dead or current_vehicle != null:
		return
	var walk := _get_walk()
	if walk == null or not walk.has_method("find_node_path"):
		move_to(target, speed_mode)
		return
	_speed_mode = speed_mode
	_leave_pose()
	var t0 := Time.get_ticks_usec()
	var a := int(walk.call("get_nearest_node", global_position))
	var b := int(walk.call("get_nearest_node", target))
	if a < 0 or b < 0:
		move_to(target, speed_mode)
		return
	var ids: PackedInt32Array = walk.call("find_node_path", a, b)
	var pts: PackedVector3Array = walk.get("points")
	var kinds: PackedByteArray = walk.get("kinds")
	var path := PackedVector3Array()
	var pk := PackedByteArray()
	for id in ids:
		path.append(pts[id])
		pk.append(kinds[id])
	if path.is_empty() or path[path.size() - 1].distance_to(target) > 0.4:
		path.append(target)
		pk.append(0)
	# skip a first node that lies behind us
	if path.size() >= 2 and pk[0] != 1:
		var p0 := path[0]
		var p1 := path[1]
		if (p0 - global_position).dot(p1 - p0) < 0.0 and global_position.distance_to(p1) < p0.distance_to(p1) + 1.0:
			path.remove_at(0)
			pk.remove_at(0)
	_note_path_cost("walk", t0)
	_start_path(path, pk)


## Follow explicit world points (other modules' own routes).
func follow_path(points: PackedVector3Array, speed_mode: String = "walk") -> void:
	_speed_mode = speed_mode
	_leave_pose()
	_start_path(points, PackedByteArray())


func stop_moving() -> void:
	_moving = false
	_path = PackedVector3Array()
	_path_kind = PackedByteArray()
	_path_i = 0
	_cross_wait = false
	_crossing = false
	_glide_vel = Vector3.ZERO


func is_moving() -> bool:
	return _moving


func has_arrived(tolerance: float = 1.2) -> bool:
	if _final_target == Vector3.INF:
		return not _moving
	var d := Vector2(global_position.x - _final_target.x, global_position.z - _final_target.z).length()
	return d <= tolerance or (not _moving and d <= tolerance * 2.5)


func get_move_target() -> Vector3:
	return _final_target


func get_planar_velocity() -> Vector3:
	return _glide_vel


func is_waiting_to_cross() -> bool:
	return _cross_wait


func set_speed_mode(mode: String) -> void:
	_speed_mode = mode


func face_position(pos: Vector3) -> void:
	_face_pos = pos


func clear_face() -> void:
	_face_pos = Vector3.INF


func set_crouched(on: bool) -> void:
	is_crouching = on
	height = CROUCH_HEIGHT if on else HEIGHT
	if _shape != null:
		_shape.height = height
		_col.position.y = height * 0.5


func _start_path(path: PackedVector3Array, kinds: PackedByteArray) -> void:
	_path = path
	_path_kind = kinds if kinds.size() == path.size() else PackedByteArray()
	_path_i = 0
	_moving = not path.is_empty()
	_final_target = path[path.size() - 1] if _moving else Vector3.INF
	_cross_wait = false
	_crossing = false
	_stuck_t = 0.0
	_stuck_count = 0
	_stuck_ref = global_position
	if _moving and state_tag in ["idle", "sit", "talk"]:
		state_tag = "walk"
	if _moving and _path_kind.size() > 0:
		_on_node_reached(-1)


func _speed_for_mode() -> float:
	match _speed_mode:
		"run":
			return run_speed
		"sprint":
			return sprint_speed
		"crouch":
			return 1.6
	return walk_speed


## Desired planar velocity this physics frame.
func _steer(delta: float) -> Vector3:
	if not _moving:
		if _pose == "kneel" or _pose == "spray":
			return Vector3.ZERO          # working on the spot: passers-by do not shove us around
		return avoid * 0.6 if (sim_tier == 0 and avoid.length_squared() > 0.01) else Vector3.ZERO
	if _cross_wait:
		_cross_wait_t += delta
		_cross_check_t -= delta
		if _cross_check_t <= 0.0:
			_cross_check_t = CROSS_CHECK_INTERVAL
			if _cross_wait_t >= CROSS_WAIT_MAX or _crossing_clear():
				_cross_wait = false
				_crossing = true
				if _cross_wait_t > 0.5:
					path_stats["crossing_waits"] = int(path_stats["crossing_waits"]) + 1
		if _cross_wait:
			_face_pos = _cross_b
			return Vector3.ZERO
		_face_pos = Vector3.INF
	var pos := global_position
	var n := _path.size()
	var spd := _speed_for_mode() * speed_mult
	while _path_i < n:
		var p := _path[_path_i]
		var last := _path_i == n - 1
		var reach := 0.35 if last else (1.1 if spd > 3.0 else 0.7)
		if Vector2(p.x - pos.x, p.z - pos.z).length() < reach:
			_path_i += 1
			if _path_i < n:
				_on_node_reached(_path_i - 1)
				if _cross_wait:
					return Vector3.ZERO
			continue
		break
	if _path_i >= n:
		_moving = false
		if state_tag == "walk":
			state_tag = "idle"
		return Vector3.ZERO
	var target := _path[_path_i]
	var to := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	# corner smoothing: lean into the next segment when close to this point
	if _path_i + 1 < n and dist < 1.6:
		var nxt := _path[_path_i + 1]
		var d2 := Vector3(nxt.x - target.x, 0.0, nxt.z - target.z).normalized()
		dir = dir.lerp(d2, (1.6 - dist) / 1.6 * 0.5).normalized()
	if _path_i == n - 1 and dist < 1.4:
		spd *= clampf(dist / 1.4, 0.35, 1.0)
	if _crossing:
		spd *= 1.12
	var v := dir * spd
	if sim_tier == 0 and avoid.length_squared() > 0.0001:
		v += avoid * minf(spd, 2.0)
		var l := v.length()
		if l > spd * 1.1:
			v = v / l * spd * 1.1
	return v


func _on_node_reached(i: int) -> void:
	if _path_kind.is_empty() or i + 1 >= _path_kind.size():
		return
	var next_cw := _path_kind[i + 1] == 1
	if next_cw and not _crossing:
		# about to step onto the road: find the far end of this crossing and check traffic
		var j := i + 1
		while j + 1 < _path_kind.size() and _path_kind[j + 1] == 1:
			j += 1
		_cross_a = global_position if i < 0 else _path[i]
		_cross_b = _path[j]
		if _cross_a.distance_to(_cross_b) < 2.0:
			return
		_cross_wait = true
		_cross_wait_t = 0.0
		_cross_check_t = 0.0
		path_stats["crossings"] = int(path_stats["crossings"]) + 1
	elif not next_cw:
		_crossing = false


func _crossing_clear() -> bool:
	var sys := Game.get_system("peds")
	if sys != null and sys.has_method("is_crossing_clear"):
		return bool(sys.call("is_crossing_clear", _cross_a, _cross_b))
	return true


func _update_facing(delta: float, desired: Vector3) -> void:
	var want := Vector3.ZERO
	if is_aiming and _aim_pos != Vector3.INF:
		want = _aim_pos - global_position
	elif _moving and desired.length_squared() > 0.04:
		want = desired
	elif _face_pos != Vector3.INF:
		want = _face_pos - global_position
	want.y = 0.0
	if want.length_squared() < 0.0004:
		_yaw_rate = 0.0
		return
	var target_yaw := atan2(-want.x, -want.z)
	var cur := rotation.y
	var diff := wrapf(target_yaw - cur, -PI, PI)
	var rate := TURN_RATE * (1.6 if is_aiming else 1.0)
	var step := clampf(diff, -rate * delta, rate * delta)
	rotation.y = wrapf(cur + step, -PI, PI)
	_yaw_rate = step / maxf(delta, 0.0001)


func _glide(desired: Vector3, delta: float) -> void:
	_glide_vel = desired
	velocity = desired
	if desired.length_squared() < 0.0001:
		return
	var pos := global_position + desired * delta
	if _moving and _path_i < _path.size():
		var tp := _path[_path_i]
		var flat_d := Vector2(tp.x - pos.x, tp.z - pos.z).length()
		var step := desired.length() * delta
		pos.y += (tp.y - pos.y) * clampf(step / maxf(flat_d, 0.05), 0.0, 1.0)
	global_position = pos


func _check_stuck(delta: float) -> void:
	if not _moving or _cross_wait:
		_stuck_t = 0.0
		_stuck_ref = global_position
		return
	_stuck_t += delta
	if _stuck_t < 1.6:
		return
	var moved := Vector2(global_position.x - _stuck_ref.x, global_position.z - _stuck_ref.z).length()
	_stuck_t = 0.0
	_stuck_ref = global_position
	if moved > 0.5:
		_stuck_count = 0
		return
	_stuck_count += 1
	if _stuck_count == 1 and _path_i < _path.size() - 1:
		_path_i += 1                     # skip a blocked node
	elif _stuck_count == 2:
		# side-step around whatever blocks us
		var side := global_basis.x * (1.0 if randf() < 0.5 else -1.0)
		_path.insert(_path_i, global_position + side * 1.4 - global_basis.z * 0.6)
		if not _path_kind.is_empty():
			_path_kind.insert(_path_i, 0)
	elif _stuck_count >= 4:
		stop_moving()
		_notify("stuck", {})


func _check_slide_collisions() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider() as Node
		if other == null or not other.is_in_group("vehicle"):
			continue
		var vel := Vector3.ZERO
		if other is RigidBody3D:
			vel = (other as RigidBody3D).linear_velocity
		if vel.length() > 1.2:
			notify_bumped(other)
		return


func _fell_out() -> void:
	if persistent:
		global_position = home_position + Vector3(0.0, 0.5, 0.0)
		velocity = Vector3.ZERO
	else:
		_die(Dmg.make(9999.0, "fall"), null)


func _check_water(dt: float) -> void:
	if Game.world == null:
		return
	if Game.is_in_water(global_position + Vector3(0.0, 1.3, 0.0)):
		_water_t += dt
		if _water_t > 4.0:
			apply_damage(Dmg.make(25.0 * dt + 5.0, "drown", null, global_position))
	else:
		_water_t = 0.0


## Seconds-scale helper for brains: a flee destination roughly away from `from`.
func flee_from(from: Vector3, distance: float = 35.0, speed_mode: String = "sprint") -> void:
	if is_dead or current_vehicle != null:
		return
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	away = away.normalized()
	var walk := _get_walk()
	var best := Vector3.INF
	if walk != null and walk.has_method("random_point"):
		var best_dot := -2.0
		for i in 6:
			var p: Vector3 = walk.call("random_point", global_position, distance * 0.7, distance * 1.3)
			if p == Vector3.INF:
				break
			var dv := p - global_position
			dv.y = 0.0
			var dt := away.dot(dv.normalized())
			if dt > best_dot:
				best_dot = dt
				best = p
			if dt > 0.75:
				break
		if best != Vector3.INF and best_dot > 0.2:
			walk_to(best, speed_mode)
			return
	var dest := global_position + away * distance
	if is_inside_tree():
		var map := get_world_3d().navigation_map
		if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
			var cp := NavigationServer3D.map_get_closest_point(map, dest)
			if cp.distance_to(dest) < distance * 0.6:
				dest = cp
	move_to(dest, speed_mode)


func _get_walk() -> Object:
	var w := Game.world
	if w == null or not is_instance_valid(w):
		return null
	var walk: Variant = w.get("walk")
	if walk == null or not (walk is Object):
		return null
	return walk


# =================================================================================================
# poses / reactions (W2.2)
# =================================================================================================

## Flee from a danger point (other modules call this: explosions, sirens ...). The brain hears
## about it through on_event("panic", {"from": from}).
func panic(from: Vector3) -> void:
	if is_dead or is_down:
		return
	flee_from(from, 38.0, "sprint")
	state_tag = "flee"
	_notify("panic", {"from": from})


func cower() -> void:
	if is_dead:
		return
	stop_moving()
	stop_aiming()
	_pose = "cower"
	state_tag = "cower"


func surrender() -> void:
	if is_dead:
		return
	stop_moving()
	stop_aiming()
	_pose = "surrender"
	state_tag = "surrender"


## Back to a normal standing pose (after cower / surrender / sitting).
func stand_normal() -> void:
	_leave_pose()


func get_pose() -> String:
	return _pose


func _leave_pose() -> void:
	if _pose == "sit":
		_set_collision(true)
		if visual != null:
			visual.position = Vector3.ZERO
		_restore_anim_defaults()
	elif _pose == "kneel":
		if visual != null:
			visual.position = Vector3.ZERO
		if animator != null:
			animator.set("hand_target_weight_r", 0.0)
			animator.set("hand_target_weight_l", 0.0)
	elif _pose == "spray":
		stop_aiming()
	_pose = ""
	phone_pose = false


## Emergency responders: "kneel" (medic treating `focus`, the patient's chest / pelvis point),
## "spray" (firefighter aiming the water at `focus`), "" = back to normal. Stops movement and turns
## towards `focus`; any move_to / walk_to ends the pose.
func set_service_pose(pose: String, focus: Vector3 = Vector3.INF) -> void:
	if is_dead or current_vehicle != null:
		return
	if pose == "" or not (pose in SERVICE_POSES):
		if _pose in SERVICE_POSES:
			_leave_pose()
			state_tag = "idle"
		return
	stop_moving()
	_leave_pose()
	if focus != Vector3.INF:
		_face_pos = focus
		var to := focus - global_position
		to.y = 0.0
		if to.length_squared() > 0.01:
			rotation = Vector3(0.0, atan2(-to.x, -to.z), 0.0)
	_pose = pose
	_gesture_t = 0.0
	if pose == "kneel":
		if visual != null:
			visual.position = Vector3(0.0, -KNEEL_SINK, 0.0)
		state_tag = "treating"
	else:
		aim_at(focus if focus != Vector3.INF else global_position - global_basis.z * 5.0)
		state_tag = "spraying"


## World position of the right hand (water jet origin for "spray"); INF without a skeleton.
func get_hand_position() -> Vector3:
	if visual == null or not visual.has_method("get_skeleton"):
		return Vector3.INF
	var skel: Variant = visual.call("get_skeleton")
	if not (skel is Skeleton3D) or not (skel as Skeleton3D).is_inside_tree():
		return Vector3.INF
	var sk := skel as Skeleton3D
	if animator != null and animator.has_method("get_hand_position"):
		# the animator's wrist point (skeleton space) after its last evaluation
		var v: Variant = animator.call("get_hand_position", true)
		if v is Vector3:
			return sk.global_transform * (v as Vector3)
	var bi := sk.find_bone("Hand_R")
	if bi >= 0:
		return sk.global_transform * sk.get_bone_global_pose(bi).origin
	return Vector3.INF


## Sit on a bench: `seat` = world transform of the sitting spot on the ground in front of the
## seat (basis -Z = the way the sitter faces).
func sit_at(seat: Transform3D) -> void:
	if is_dead or current_vehicle != null:
		return
	stop_moving()
	stop_aiming()
	global_position = seat.origin
	var f := -seat.basis.z
	rotation = Vector3(0.0, atan2(-f.x, -f.z), 0.0)
	_set_collision(false)
	_pose = "sit"
	state_tag = "sit"
	if visual != null:
		visual.position = Vector3(0.0, BENCH_SEAT_HEIGHT, 0.0)
	if animator != null:
		animator.set("pedal_pos", BENCH_PEDAL)
		animator.set("wheel_pos", BENCH_WHEEL)
		animator.set("wheel_radius", BENCH_WHEEL_RADIUS)
		animator.set("steer", 0.0)


func _restore_anim_defaults() -> void:
	if animator == null:
		return
	for k: String in _anim_defaults.keys():
		animator.set(k, _anim_defaults[k])


func play_action(action: String, duration: float = 0.6) -> void:
	if animator != null and animator.has_method("play_action"):
		animator.call("play_action", action, duration)


func _set_collision(on: bool) -> void:
	if _col != null:
		_col.disabled = not on
	collision_layer = Layers.NPC if on else 0


# =================================================================================================
# weapons (W2.2)
# =================================================================================================

## "" = unarmed. Shows the weapon model in the right hand (when the GLB exists).
func set_weapon(id: String) -> void:
	if id == "<null>":
		id = ""
	if id == weapon_id and (_spec != null or id == ""):
		return
	_clear_weapon_model()
	weapon_id = ""
	_spec = null
	_mag = 0
	_mag_size = 0
	_reload_t = 0.0
	_weapon_pose = "none"
	if id == "":
		return
	var spec: Variant = Registry.get_def("weapons", id)
	if spec == null or not (spec is Resource):
		push_warning("NpcBase.set_weapon: unknown weapon '%s'" % id)
		return
	_spec = spec as Resource
	weapon_id = id
	_mag_size = maxi(int(_spec.get("mag_size")), 0)
	_mag = _mag_size
	if _spec.has_method("get_fire_interval"):
		_fire_interval = maxf(float(_spec.call("get_fire_interval")), 0.05)
	else:
		_fire_interval = 60.0 / maxf(float(_spec.get("rpm")), 1.0)
	var pose: Variant = _spec.get("weapon_pose")
	_weapon_pose = str(pose) if pose != null else "none"
	if id != "fists":
		var wm := load_script(WEAPON_MODEL_SCRIPT)
		if wm != null:
			var m: Variant = wm.call("create", id)
			if m is Node3D:
				_weapon_model = m as Node3D
				var has_model := true
				if _weapon_model.has_method("has_model"):
					has_model = bool(_weapon_model.call("has_model"))
				if has_model and _weapon_model.has_method("attach_to_holder"):
					_weapon_model.call("attach_to_holder", self)
				if _weapon_model.get_parent() == null:
					_weapon_model.free()
					_weapon_model = null


func _clear_weapon_model() -> void:
	if _weapon_model != null and is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
	_weapon_model = null


func get_weapon_spec() -> Resource:
	return _spec


func has_firearm() -> bool:
	return _spec != null and _spec.has_method("is_firearm") and bool(_spec.call("is_firearm"))


func is_melee_weapon() -> bool:
	return _spec == null or (_spec.has_method("is_melee") and bool(_spec.call("is_melee")))


func get_ammo_in_mag() -> int:
	return _mag


func get_mag_size() -> int:
	return _mag_size


func is_reloading() -> bool:
	return _reload_t > 0.0


func get_weapon_range() -> float:
	if _spec == null:
		return 1.5
	if is_melee_weapon():
		return float(_spec.get("melee_range"))
	return float(_spec.get("max_range"))


func get_muzzle_node() -> Node3D:
	if _weapon_model != null and is_instance_valid(_weapon_model) and _weapon_model.is_inside_tree():
		var m: Variant = _weapon_model.get("muzzle")
		if m is Node3D and is_instance_valid(m):
			return m as Node3D
	return null


func get_muzzle_position() -> Vector3:
	var m := get_muzzle_node()
	if m != null and visual != null and visual.visible:
		return m.global_position
	return global_position + Vector3(0.0, 1.0 if is_crouching else 1.45, 0.0) - global_basis.z * 0.35


func aim_at(pos: Vector3) -> void:
	_aim_pos = pos
	is_aiming = true


func stop_aiming() -> void:
	is_aiming = false
	_aim_pos = Vector3.INF


## Obeys fire rate, magazine and reload. True when a shot (or a swing) left.
func fire_at(target_pos: Vector3, accuracy_mult: float = 1.0) -> bool:
	if is_dead or is_down or _spec == null or not is_inside_tree():
		return false
	if current_vehicle != null and not bool(_spec.get("drive_by")):
		return false
	if _reload_t > 0.0 or _fire_cd > 0.0:
		return false
	aim_at(target_pos)
	if is_melee_weapon():
		if global_position.distance_to(target_pos) > get_weapon_range() + 1.0:
			return false
		_fire_cd = maxf(_fire_interval * 1.35, 0.45)
		_swing(target_pos)
		return true
	if _mag_size > 0 and _mag <= 0:
		reload()
		return false
	# only fire roughly along the facing (the body turns towards the aim point first)
	if current_vehicle == null:
		var to := target_pos - global_position
		to.y = 0.0
		if to.length_squared() > 0.25 and (-global_basis.z).dot(to.normalized()) < 0.8:
			return false
	Combat.npc_fire(self, _spec, target_pos, clampf(accuracy * accuracy_mult, 0.0, 1.0))
	_fire_cd = _fire_interval
	if _mag_size > 0:
		_mag -= 1
		if _mag <= 0:
			reload()
	play_action("fire", 0.14)
	return true


func reload() -> bool:
	if _spec == null or _mag_size <= 0 or _mag >= _mag_size or _reload_t > 0.0 or is_dead:
		return false
	_reload_t = maxf(float(_spec.get("reload_time")), 0.4) * 1.15
	play_action("reload", _reload_t)
	var snd: Variant = _spec.get("sound_reload")
	if snd != null and str(snd) != "":
		Audio.play_at(str(snd), global_position + Vector3.UP, -6.0, 1.0, 25.0, "Weapons")
	if _weapon_model != null and is_instance_valid(_weapon_model) and _weapon_model.has_method("set_mag_loaded"):
		_weapon_model.call("set_mag_loaded", false)
	return true


## Close-range attack with the melee weapon in hand, or fists / a weapon bash.
func melee(target: Node3D) -> void:
	if is_dead or is_down or target == null or not is_instance_valid(target) or _melee_cd > 0.0:
		return
	_swing(AiSenses.target_point(target))


func _swing(target_pos: Vector3) -> void:
	var spec: Resource = _spec if (is_melee_weapon() and _spec != null) else (Registry.get_def("weapons", "fists") as Resource)
	var dmg := 14.0
	var reach := 1.5
	var wid := "fists"
	var snd := "punch_hit"
	var impulse := 4.0
	var rpm := 100.0
	if spec != null:
		wid = str(spec.get("id"))
		dmg = float(spec.get("damage"))
		reach = float(spec.get("melee_range"))
		snd = str(spec.get("melee_sound_hit"))
		impulse = float(spec.get("impulse"))
		rpm = float(spec.get("rpm"))
	if _spec != null and not is_melee_weapon():
		dmg = 18.0                     # weapon bash
	_melee_cd = maxf(60.0 / maxf(rpm, 1.0) * 1.5, 0.55)
	face_position(target_pos)
	var origin := global_position + Vector3(0.0, 1.0 if is_crouching else 1.3, 0.0)
	var dir := target_pos - origin
	dir.y *= 0.5
	if dir.length_squared() < 0.0001:
		dir = -global_basis.z
	var heavy := randf() < 0.25
	Combat.melee_sweep(self, origin, dir.normalized(), reach + 0.25, dmg * (1.4 if heavy else 1.0), {
		"weapon_id": wid, "sound_hit": snd, "impulse": impulse * (1.6 if heavy else 1.0),
		"knockdown": heavy and randf() < 0.4, "heavy": heavy,
	})
	if wid == "fists":
		play_action("punch_l" if _punch_left else "punch_r", 0.36)
		_punch_left = not _punch_left
	else:
		play_action("heavy" if heavy else "punch_r", 0.7 if heavy else 0.45)
	Audio.play_at("melee_swing", origin, -8.0, randf_range(0.9, 1.1), 18.0, "SFX")


# =================================================================================================
# senses (W2.2)
# =================================================================================================

func can_see(target: Node3D) -> bool:
	return senses.can_see(target)


func can_see_point(pos: Vector3) -> bool:
	return senses.can_see_point(pos)


func get_awareness() -> float:
	return senses.awareness


var is_alerted: bool:
	get:
		return senses != null and senses.is_alerted


func get_eye_position() -> Vector3:
	if current_vehicle != null:
		return global_position + Vector3(0.0, 0.62, 0.0)
	return global_position + Vector3(0.0, CROUCH_EYE_HEIGHT if is_crouching else EYE_HEIGHT, 0.0)


func get_target_position() -> Vector3:
	if is_down and _ragdoll != null and is_instance_valid(_ragdoll) and _ragdoll.has_method("get_pelvis_position"):
		return (_ragdoll.call("get_pelvis_position") as Vector3) + Vector3(0.0, 0.15, 0.0)
	if current_vehicle != null:
		return global_position + Vector3(0.0, 0.4, 0.0)
	return global_position + Vector3(0.0, 0.85 if is_crouching else 1.25, 0.0)


## A noise reached us (PedSystem dispatch). Forwards to the brain when heard.
func hear_noise(pos: Vector3, radius: float, kind: String, instigator: Node) -> void:
	if is_dead:
		return
	if senses.hear(pos, radius, kind, instigator):
		_notify("noise", {"position": pos, "radius": radius, "kind": kind, "instigator": instigator,
				"distance": global_position.distance_to(pos)})


## A firearm points at us (PedSystem aim check, about 6 Hz).
func notify_threatened(by: Node, dt: float) -> void:
	if is_dead:
		return
	threatened_time += dt
	threatened_by = by
	_threat_refresh = 0.45
	threatened.emit(self, by)
	_notify("threatened", {"by": by, "duration": threatened_time})


func notify_bumped(by: Node) -> void:
	if is_dead or is_down or _bump_cd > 0.0:
		return
	_bump_cd = 0.8
	_notify("bumped", {"by": by})


## The PedSystem decided this NPC saw / heard a crime.
func notify_crime(crime_id: String, pos: Vector3, instigator: Node, may_call: bool) -> void:
	if is_dead:
		return
	_notify("saw_crime", {"crime": crime_id, "position": pos, "instigator": instigator, "may_call": may_call})


# =================================================================================================
# cover (W2.2)
# =================================================================================================

## A standing spot within `search_radius` that is hidden from `threat_pos` (chest / eye level),
## reachable on the navigation mesh when one exists. Vector3.INF if none (or the per-frame search
## budget of MAX_COVER_SEARCHES_PER_FRAME is used up: try again next think).
## `last_cover_info` = {position, low (true = hidden only when crouched), peek (Vector3 to step to
## for a shot from high cover, INF if none), normal (away from the obstacle)}.
func find_cover_from(threat_pos: Vector3, search_radius: float = 14.0) -> Vector3:
	last_cover_info = {}
	if not is_inside_tree():
		return Vector3.INF
	var frame := Engine.get_physics_frames()
	if frame != _cover_frame:
		_cover_frame = frame
		_cover_count = 0
	if _cover_count >= MAX_COVER_SEARCHES_PER_FRAME:
		return Vector3.INF
	_cover_count += 1
	var space := get_world_3d().direct_space_state
	var origin := global_position
	var threat := threat_pos
	if threat.y - origin.y < 0.6:
		threat.y = origin.y + 1.4
	var me_rid := get_rid()
	var ex: Array[RID] = [me_rid]
	var candidates: Array = []            # [point, normal]
	var probe_h := 0.75
	# A) rays from us: faces of obstacles turned away from the threat
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.PROP
	q.exclude = ex
	for i in 16:
		var ang := TAU * float(i) / 16.0
		var d := Vector3(sin(ang), 0.0, cos(ang))
		q.from = origin + Vector3(0.0, probe_h, 0.0)
		q.to = q.from + d * search_radius
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		n.y = 0.0
		if n.length_squared() < 0.1:
			continue
		n = n.normalized()
		var to_threat := threat - (hit["position"] as Vector3)
		to_threat.y = 0.0
		if n.dot(to_threat.normalized()) > -0.25:
			continue
		candidates.append([(hit["position"] as Vector3) + n * 0.55, n])
	# B) rays from the threat through points around us: just behind the first obstacle
	for i in 10:
		var ang := TAU * float(i) / 10.0 + 0.3
		var r := search_radius * (0.35 if i % 2 == 0 else 0.75)
		var p := origin + Vector3(sin(ang) * r, probe_h, cos(ang) * r)
		var dir := p - threat
		dir.y = 0.0
		var dlen := dir.length()
		if dlen < 2.0:
			continue
		dir /= dlen
		q.from = Vector3(threat.x, origin.y + probe_h, threat.z)
		q.to = q.from + dir * (dlen + 6.0)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var front: Vector3 = hit["position"]
		# back face of that obstacle
		q.from = front + dir * 7.0
		q.to = front
		var back := space.intersect_ray(q)
		if back.is_empty():
			continue
		var bp: Vector3 = back["position"]
		candidates.append([Vector3(bp.x, origin.y, bp.z) + dir * 0.55, dir])
	if candidates.is_empty():
		return Vector3.INF
	var nav_map := get_world_3d().navigation_map
	var nav_ok := nav_map.is_valid() and NavigationServer3D.map_get_iteration_id(nav_map) > 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.1
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = capsule
	sq.collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.PROP | Layers.GLASS
	sq.exclude = ex
	var down := PhysicsRayQueryParameters3D.new()
	down.collision_mask = Layers.WORLD | Layers.PROP
	down.exclude = ex
	var los_ex: Array = [self]
	var best := Vector3.INF
	var best_score := INF
	var best_info: Dictionary = {}
	var my_id := get_instance_id()
	var claims: Array = []
	for id: int in _cover_claims.keys():
		if id == my_id:
			continue
		var o: Variant = instance_from_id(id)
		if o == null or not is_instance_valid(o) or bool((o as Object).get("is_dead")):
			_cover_claims.erase(id)
			continue
		claims.append(_cover_claims[id])
	var to_threat_me := threat - origin
	to_threat_me.y = 0.0
	var threat_dir := to_threat_me.normalized()
	for c: Array in candidates:
		var p: Vector3 = c[0]
		var n: Vector3 = c[1]
		if Vector2(p.x - origin.x, p.z - origin.z).length() > search_radius + 1.0:
			continue
		if Vector2(p.x - threat.x, p.z - threat.z).length() < 3.5:
			continue
		# ground under the spot
		down.from = p + Vector3(0.0, 1.2, 0.0)
		down.to = p + Vector3(0.0, -2.5, 0.0)
		var g := space.intersect_ray(down)
		if g.is_empty():
			continue
		var gp: Vector3 = g["position"]
		if absf(gp.y - origin.y) > 1.6:
			continue
		if nav_ok:
			var cp := NavigationServer3D.map_get_closest_point(nav_map, gp)
			if Vector2(cp.x - gp.x, cp.z - gp.z).length() > 0.9 or absf(cp.y - gp.y) > 0.8:
				continue
		# room to crouch there
		sq.transform = Transform3D(Basis.IDENTITY, gp + Vector3(0.0, 0.9, 0.0))
		if not space.intersect_shape(sq, 1).is_empty():
			continue
		# hidden at crouched chest height?
		if Combat.has_line_of_sight(threat, gp + Vector3(0.0, 0.95, 0.0), los_ex):
			continue
		var low := Combat.has_line_of_sight(threat, gp + Vector3(0.0, 1.6, 0.0), los_ex)
		var dist := origin.distance_to(gp)
		var score := dist
		var mv := gp - origin
		mv.y = 0.0
		if mv.length_squared() > 0.01 and mv.normalized().dot(threat_dir) > 0.3:
			score += 6.0               # running towards the threat to get there
		if not low:
			score += 1.5               # high cover: needs a side step to shoot
		for cl: Vector3 in claims:
			if cl.distance_to(gp) < 1.2:
				score += 9.0           # a squad mate already uses this spot
				break
		if score < best_score:
			best_score = score
			best = gp
			best_info = {"position": gp, "low": low, "normal": n, "peek": Vector3.INF}
	if best == Vector3.INF:
		return best
	if not bool(best_info["low"]):
		var side := Vector3.UP.cross(best_info["normal"] as Vector3).normalized()
		for s in [1.0, -1.0, 1.8, -1.8]:
			var pk: Vector3 = best + side * float(s) * 0.9
			if Combat.has_line_of_sight(pk + Vector3(0.0, 1.5, 0.0), threat, los_ex):
				best_info["peek"] = pk
				break
	last_cover_info = best_info
	_cover_claims[my_id] = best
	return best


## Forget the cover spot this NPC claimed with find_cover_from (combat helper calls it on reset).
func release_cover() -> void:
	_cover_claims.erase(get_instance_id())


# =================================================================================================
# vehicles (W2.2 / W2.1)
# =================================================================================================

func enter_vehicle(vehicle: Node3D, seat: int = 0, instant: bool = false) -> void:
	if is_dead or vehicle == null or not is_instance_valid(vehicle):
		return
	if current_vehicle != null:
		return
	if not instant:
		_pending_vehicle = vehicle
		_pending_seat = seat
		_pending_t = 0.0
		var door := vehicle.global_position
		if vehicle.has_method("get_door_position"):
			door = vehicle.call("get_door_position", seat)
		elif vehicle.has_method("get_exit_transform"):
			door = (vehicle.call("get_exit_transform", seat) as Transform3D).origin
		move_to(door, "walk")
		state_tag = "entering_vehicle"
		return
	_seat_into(vehicle, seat)


func _tick_pending_vehicle(delta: float) -> void:
	var v := _pending_vehicle
	if not is_instance_valid(v) or bool(v.get("destroyed")):
		_pending_vehicle = null
		return
	_pending_t += delta
	var door := v.global_position
	if v.has_method("get_door_position"):
		door = v.call("get_door_position", _pending_seat)
	if Vector2(global_position.x - door.x, global_position.z - door.z).length() < 1.3 or _pending_t > 12.0 \
			or (not _moving and global_position.distance_to(door) < 3.0):
		_pending_vehicle = null
		play_action("enter_car", 0.55)
		_seat_into(v, _pending_seat)


func _seat_into(vehicle: Node3D, seat: int) -> void:
	if seat < 0 and vehicle.has_method("get_free_seat"):
		seat = int(vehicle.call("get_free_seat"))
	if seat < 0:
		return
	if vehicle.has_method("get_occupant"):
		var occ: Variant = vehicle.call("get_occupant", seat)
		if occ != null and is_instance_valid(occ) and occ != self:
			return
	var seat_node: Node3D = null
	if vehicle.has_method("get_seat_node"):
		seat_node = vehicle.call("get_seat_node", seat) as Node3D
	if seat_node == null:
		return
	_leave_pose()
	stop_moving()
	stop_aiming()
	_set_collision(false)
	collision_mask = 0
	if vehicle.has_method("occupant_enter"):
		vehicle.call("occupant_enter", self, seat)
	if get_parent() != seat_node:
		if get_parent() != null:
			reparent(seat_node, false)
		else:
			seat_node.add_child(self)
	transform = Transform3D.IDENTITY
	velocity = Vector3.ZERO
	current_vehicle = vehicle
	seat_index = seat
	state_tag = "in_vehicle"
	if visual != null:
		visual.position = Vector3.ZERO
	_restore_anim_defaults()
	if animator != null:
		animator.call("set_state", _anim_state(), 0.35)


func exit_vehicle() -> void:
	if current_vehicle == null:
		return
	if not is_instance_valid(current_vehicle):
		_vehicle_gone()
		return
	var xf := global_transform
	if current_vehicle.has_method("occupant_exit"):
		xf = current_vehicle.call("occupant_exit", seat_index)
	_leave_vehicle_to(xf)
	play_action("exit_car", 0.5)


## VehicleBase calls this when it throws us out (explosion, carjacking, wreck).
func on_vehicle_ejected(_vehicle: Node3D, exit_xform: Transform3D, impulse: Vector3) -> void:
	_leave_vehicle_to(exit_xform)
	if is_dead:
		_spawn_death_ragdoll(impulse)
	elif impulse.length() > 1.0:
		knock_down(impulse)


func _leave_vehicle_to(xf: Transform3D) -> void:
	var root := Game.get_entities_root()
	if root != null and get_parent() != root:
		if get_parent() != null:
			reparent(root, false)
		else:
			root.add_child(self)
	var f := -xf.basis.z
	f.y = 0.0
	var yaw := atan2(-f.x, -f.z) if f.length_squared() > 0.01 else rotation.y
	global_transform = Transform3D(Basis(Vector3.UP, yaw), xf.origin)
	current_vehicle = null
	seat_index = -1
	collision_mask = Layers.NPC_MASK
	if not is_dead:
		_set_collision(true)
		state_tag = "idle"
	velocity = Vector3.ZERO


func _vehicle_gone() -> void:
	current_vehicle = null
	seat_index = -1
	collision_mask = Layers.NPC_MASK
	if not is_dead:
		_set_collision(true)


# =================================================================================================
# damage, knock-down, death (W2.2)
# =================================================================================================

func apply_damage(info: Dictionary) -> void:
	if not is_inside_tree():
		return
	var type := str(info.get("type", "generic"))
	var amount := float(info.get("amount", 0.0))
	if is_dead:
		if _ragdoll != null and is_instance_valid(_ragdoll) and (type == "bullet" or type == "explosion"):
			var dir: Vector3 = info.get("direction", Vector3.ZERO)
			_ragdoll.call("apply_impulse_at", dir * clampf(_impulse_of(info), 10.0, 120.0), info.get("position", Vector3.INF))
		return
	if amount <= 0.0:
		return
	var attacker := _resolve_attacker(info.get("instigator", null))
	if armor > 0.0 and (type == "bullet" or type == "explosion"):
		var absorbed := minf(armor, amount * 0.7)
		armor -= absorbed
		amount -= absorbed
	health -= amount
	last_damage_info = info
	if attacker != null:
		last_attacker = attacker
	var killed := health <= 0.0
	if Dmg.caused_by_player(info):
		_report_harm(type, killed, info)
	damaged.emit(self, info)
	if killed:
		_die(info, attacker)
		return
	EventBus.npc_injured.emit(self, attacker, info)
	if current_vehicle == null and not is_down:
		if type == "bullet" or type == "melee":
			play_action("hit_react", 0.38)
		if _pain_cd <= 0.0 and type != "fire" and not bool(info.get("silent", false)):
			_pain_cd = 1.2
			var female := visual != null and visual.has_method("get_appearance") and str((visual.call("get_appearance") as Dictionary).get("body", "m")) == "f"
			Audio.play_at("grunt_hit_f" if female else "grunt_hit_m", global_position + Vector3.UP * 1.5, -4.0,
					randf_range(0.92, 1.08), 30.0, "SFX")
		if bool(info.get("knockdown", false)) and not bool(info.get("no_ragdoll", false)):
			var dir: Vector3 = info.get("direction", Vector3.ZERO)
			knock_down(dir.normalized() * clampf(_impulse_of(info), 120.0, 900.0) if dir.length_squared() > 0.0001 else Vector3.UP * 150.0)
		if bool(info.get("knockout", false)):
			_knock_out(float(info.get("knockout_seconds", KO_DEFAULT_SECONDS)), info)
	if type == "vehicle":
		_notify("vehicle_hit", {"info": info, "vehicle": info.get("instigator", null), "attacker": attacker})
	_notify("damaged", {"info": info, "attacker": attacker, "amount": amount})


func _impulse_of(info: Dictionary) -> float:
	var imp: Variant = info.get("impulse", 0.0)
	if imp is Vector3:
		return (imp as Vector3).length()
	if imp is float or imp is int:
		return float(imp)
	return 0.0


## The node to blame: a vehicle's driver when that is a real person (NPC / player), else the
## instigator itself (a car driven by a traffic stand-in dummy is blamed as the car).
func _resolve_attacker(who: Variant) -> Node:
	if who == null or not is_instance_valid(who) or not (who is Node):
		return null
	var n := who as Node
	if n.is_in_group("vehicle"):
		var d: Variant = n.get("driver")
		if d != null and is_instance_valid(d) and ((d as Node).is_in_group("npc") or (d as Node).is_in_group("player")):
			return d as Node
	return n


## True when `n` is gone or dead. Safe for nodes whose `is_dead` is a METHOD (TrafficDummy) or
## that have no such member at all (vehicles): `n.get("is_dead") == true` errors on a Callable.
static func is_dead_node(n: Variant) -> bool:
	if n == null or not is_instance_valid(n) or not (n is Object):
		return true
	var v: Variant = (n as Object).get("is_dead")
	if v is bool:
		return v
	if v is Callable:
		return bool((v as Callable).call())
	return false


## The ONE place where harm done by the player to an NPC is reported (W2.2).
## Vehicle hits: VehicleCrime already reported "hit_and_run" -> no extra assault; a kill is murder.
func _report_harm(type: String, killed: bool, info: Dictionary = {}) -> void:
	var cop := faction == "police"
	var crime := ""
	if killed:
		if _murder_reported:
			return
		_murder_reported = true
		crime = "cop_murder" if cop else "murder"
	else:
		if type == "vehicle":
			return
		var now := AiSenses.now()
		if now - _last_assault_report < ASSAULT_REPORT_COOLDOWN:
			return
		_last_assault_report = now
		crime = "cop_assault" if cop else "assault"
	var direct := cop or _police_sees_player()
	var sys := Game.get_system("peds")
	if sys != null and sys.has_method("note_harm_report"):
		sys.call("note_harm_report", crime)
	# silent harm (stealth takedowns): bystanders notice it by sight only, never by ear
	var silent := bool(info.get("silent", false))
	if silent and sys != null and sys.has_method("set_crime_sight_only"):
		sys.call("set_crime_sight_only", true)
	Wanted.report_crime(crime, global_position, {"instigator": Game.player, "victim": self,
			"direct_police_witness": direct})
	if silent and sys != null and is_instance_valid(sys) and sys.has_method("set_crime_sight_only"):
		sys.call("set_crime_sight_only", false)


func _police_sees_player() -> bool:
	var p := Game.player
	if p == null or not is_instance_valid(p) or not is_inside_tree():
		return false
	for n in get_tree().get_nodes_in_group("police"):
		if n == self or not is_instance_valid(n) or not (n is Node3D):
			continue
		if n.get("is_dead") == true:
			continue
		if (n as Node3D).global_position.distance_to(p.global_position) > 80.0:
			continue
		if n.has_method("can_see") and bool(n.call("can_see", p)):
			return true
	return false


## Takedown knock-out (info.knockout): the body stays down `seconds` (default 30) instead of the
## normal 2-3 s, then gets up dazed (brain event got_up {"knockout": true}). A body that is not
## down yet (seated, no knockdown flag) is knocked down first.
func _knock_out(seconds: float, info: Dictionary) -> void:
	if is_dead or current_vehicle != null:
		return
	if not is_down:
		var dir: Vector3 = info.get("direction", Vector3.DOWN)
		_ragdoll_frame = -100000             # not the same impact: really go down
		knock_down(dir.normalized() * 160.0 if dir.length_squared() > 0.0001 else Vector3.DOWN * 160.0)
	if not is_down:
		return
	knocked_out = true
	_down_duration = maxf(_down_duration, clampf(seconds if seconds > 0.0 else KO_DEFAULT_SECONDS, 3.0, KO_MAX_SECONDS))
	state_tag = "knocked_out"


## Seconds until a knocked-out body gets up by itself (0 when not knocked out).
func knock_out_time_left() -> float:
	if not (knocked_out and is_down):
		return 0.0
	return maxf(_down_duration - _down_t, 0.0)


## Keep a knocked-out body down for at least `seconds` more (an ambulance is on its way).
func extend_knockout(seconds: float) -> void:
	if knocked_out and is_down and _getup_t <= 0.0:
		_down_duration = minf(maxf(_down_duration, _down_t + seconds), _down_t + KO_MAX_SECONDS)


## A medic treated this NPC: health back to full and, when it is down (knock-out or knock-down),
## it gets up now. Returns true when something was done.
func treat(_by: Node = null) -> bool:
	if is_dead:
		return false
	health = max_health
	if is_down and _getup_t <= 0.0:
		_down_duration = minf(_down_duration, _down_t + 0.1)
	return true


## Emergency medics: keep the corpse (node + ragdoll) until hold_corpse(false); then it is cleaned
## up normally (the ragdoll lives `linger` more seconds).
func hold_corpse(on: bool, linger: float = 18.0) -> void:
	corpse_held = on
	if _ragdoll != null and is_instance_valid(_ragdoll) and is_dead:
		if on:
			_ragdoll.set("persistent", true)
		else:
			_ragdoll.set("persistent", false)
			_ragdoll.set("lifetime", dead_time + maxf(linger, 1.0))


## World position of the body (the ragdoll pelvis while dead / down), for medics.
func get_body_position() -> Vector3:
	if _ragdoll != null and is_instance_valid(_ragdoll) and _ragdoll.has_method("get_pelvis_position"):
		return _ragdoll.call("get_pelvis_position")
	return global_position + Vector3(0.0, 0.25, 0.0)


func knock_down(impulse: Vector3) -> void:
	if not is_inside_tree():
		return
	if is_dead:
		if _ragdoll != null and is_instance_valid(_ragdoll) and not _is_same_impact():
			_ragdoll.call("apply_impulse_at", impulse, Vector3.INF)
		return
	if current_vehicle != null:
		return
	if _is_same_impact():
		return
	if is_down:
		if _ragdoll != null and is_instance_valid(_ragdoll):
			_ragdoll.call("apply_impulse_at", impulse, Vector3.INF)
		return
	_go_down(impulse)


func _is_same_impact() -> bool:
	return Engine.get_physics_frames() - _ragdoll_frame < SAME_IMPACT_FRAMES


func _go_down(impulse: Vector3) -> void:
	_leave_pose()
	stop_moving()
	stop_aiming()
	set_crouched(false)
	is_down = true
	knocked_out = false
	_down_t = 0.0
	_getup_t = 0.0
	_down_duration = randf_range(2.2, 3.4)
	state_tag = "down"
	_set_collision(false)
	_ragdoll_frame = Engine.get_physics_frames()
	_spawn_ragdoll(impulse, true)
	if _ragdoll == null and animator != null:
		animator.call("set_state", "dead", 0.25)
	Audio.play_at("body_fall", global_position, -4.0, randf_range(0.9, 1.1), 30.0, "SFX")
	knocked_down.emit(self)
	_notify("knocked_down", {"impulse": impulse})


func _spawn_ragdoll(impulse: Vector3, keep: bool) -> void:
	_clear_ragdoll()
	var rs := load_script(RAGDOLL_SCRIPT)
	if rs == null or visual == null or not visual.is_inside_tree() or sim_tier >= 2:
		return
	var rag: Variant = rs.call("spawn_from", visual, impulse, Vector3.INF, Vector3(_glide_vel.x, 0.0, _glide_vel.z))
	if rag is Node3D and is_instance_valid(rag):
		_ragdoll = rag as Node3D
		_ragdoll.set("persistent", keep)
		if not keep:
			_ragdoll.set("lifetime", 20.0)
		visual.visible = false


func _clear_ragdoll() -> void:
	if _ragdoll != null and is_instance_valid(_ragdoll):
		if _ragdoll.has_method("dismiss"):
			_ragdoll.call("dismiss")
		else:
			_ragdoll.queue_free()
	_ragdoll = null


func _tick_down(delta: float) -> void:
	velocity = Vector3.ZERO
	_glide_vel = Vector3.ZERO
	if _getup_t > 0.0:
		_getup_t -= delta
		if _getup_t <= 0.0:
			_finish_get_up()
		return
	_down_t += delta
	var rag_ok := _ragdoll != null and is_instance_valid(_ragdoll)
	if rag_ok:
		var pelvis: Vector3 = _ragdoll.call("get_pelvis_position")
		global_position = pelvis - Vector3(0.0, 0.25, 0.0)
		if pelvis.y < -60.0:
			_die(Dmg.make(9999.0, "fall"), null)
			return
		var settled := bool(_ragdoll.call("is_settled")) if _ragdoll.has_method("is_settled") else true
		if _down_t >= _down_duration and (settled or _down_t > _down_duration + 2.5):
			_stand_up()
	elif _down_t >= _down_duration:
		_stand_up()


func _stand_up() -> void:
	var feet := global_position
	var yaw := rotation.y
	var rag_ok := _ragdoll != null and is_instance_valid(_ragdoll)
	if rag_ok:
		var pelvis: Vector3 = _ragdoll.call("get_pelvis_position")
		if _ragdoll.has_method("get_stand_yaw"):
			yaw = float(_ragdoll.call("get_stand_yaw"))
		feet = pelvis - Vector3(0.0, 0.2, 0.0)
		var g := _ground_below(pelvis)
		if g != Vector3.INF:
			feet = g
		feet = _out_of_vehicles(feet)
	global_position = feet
	rotation = Vector3(0.0, yaw, 0.0)
	if visual != null:
		visual.visible = sim_tier < 2
	if rag_ok and animator != null and animator.has_method("crossfade_from_current"):
		var skel: Variant = animator.get("skeleton")
		if skel is Skeleton3D and _ragdoll.has_method("copy_pose_to"):
			_ragdoll.call("copy_pose_to", skel)
		animator.call("set_state", "crouch", 0.0)
		animator.call("crossfade_from_current", GET_UP_TIME * 0.6)
	elif animator != null:
		animator.call("set_state", "crouch", GET_UP_TIME * 0.5)
	_clear_ragdoll()
	_set_collision(true)
	_getup_t = GET_UP_TIME
	state_tag = "getting_up"


## Ground (world / props, never a car roof) below `p`, INF if none within 3 m.
func _ground_below(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0.0, 0.6, 0.0), p + Vector3(0.0, -3.0, 0.0), Layers.WORLD | Layers.PROP)
	var ex: Array[RID] = [get_rid()]
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else Vector3.INF


## A body that lands on / under a car gets up beside it instead of inside it.
func _out_of_vehicles(feet: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 1.6
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.collision_mask = Layers.VEHICLE
	sq.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0.0, 0.85, 0.0))
	for hit: Dictionary in space.intersect_shape(sq, 4):
		var v := hit.get("collider", null) as Node3D
		if v == null:
			continue
		var reach := 2.7
		var ab: Variant = v.get("body_aabb")
		if ab is AABB:
			reach = Vector2((ab as AABB).size.x, (ab as AABB).size.z).length() * 0.5 + 0.45
		var d := feet - v.global_position
		d.y = 0.0
		if d.length_squared() < 0.01:
			d = v.global_basis.x
			d.y = 0.0
		var p := v.global_position + d.normalized() * reach
		var g := _ground_below(Vector3(p.x, feet.y + 0.5, p.z))
		return g if g != Vector3.INF else Vector3(p.x, feet.y, p.z)
	return feet


func _finish_get_up() -> void:
	is_down = false
	_getup_t = 0.0
	state_tag = "idle"
	var was_ko := knocked_out
	knocked_out = false
	got_up.emit(self)
	_notify("got_up", {"knockout": was_ko})


func _follow_ragdoll() -> void:
	if _ragdoll != null and is_instance_valid(_ragdoll) and current_vehicle == null:
		global_position = (_ragdoll.call("get_pelvis_position") as Vector3) - Vector3(0.0, 0.25, 0.0)


func _die(info: Dictionary, killer: Node) -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	state_tag = "dead"
	dead_time = 0.0
	knocked_out = false
	threatened_time = 0.0
	stop_moving()
	stop_aiming()
	_pending_vehicle = null
	phone_pose = false
	gesture = 0.0
	_set_collision(false)
	if current_vehicle == null:
		if _pose == "sit":
			_leave_pose()
		_pose = ""
		if is_down and _ragdoll != null and is_instance_valid(_ragdoll):
			_ragdoll.set("persistent", false)
			_ragdoll.set("lifetime", 20.0)
		else:
			var dir: Vector3 = info.get("direction", Vector3.ZERO)
			var imp := _impulse_of(info)
			var type := str(info.get("type", ""))
			if type == "bullet":
				imp = clampf(imp * 6.0, 40.0, 260.0)
			elif type == "melee":
				imp = clampf(imp * 20.0, 60.0, 260.0)
			else:
				imp = clampf(imp, 40.0, 1100.0)
			_ragdoll_frame = Engine.get_physics_frames()
			_spawn_death_ragdoll(dir.normalized() * imp if dir.length_squared() > 0.0001 else Vector3.ZERO)
	is_down = false
	if _weapon_model != null and is_instance_valid(_weapon_model):
		_weapon_model.visible = false
	var female := visual != null and visual.has_method("get_appearance") and str((visual.call("get_appearance") as Dictionary).get("body", "m")) == "f"
	Audio.play_at("death_f" if female else "death_m", global_position + Vector3.UP, -3.0, randf_range(0.94, 1.06), 35.0, "SFX")
	var pk := Game.get_system("pickups")
	if pk != null and pk.has_method("drop_from_npc") and current_vehicle == null:
		pk.call("drop_from_npc", self)
	died.emit(self, killer)
	EventBus.npc_died.emit(self, killer, info)
	_notify("died", {"info": info, "killer": killer})


func _spawn_death_ragdoll(impulse: Vector3) -> void:
	_spawn_ragdoll(impulse, false)
	if _ragdoll == null and animator != null:
		animator.call("set_state", "dead", 0.3)
		if visual != null:
			visual.visible = sim_tier < 2


## True when the PedSystem may free this node (dead long enough, not persistent).
func can_be_cleaned() -> bool:
	return is_dead and not persistent and not corpse_held and dead_time > (CORPSE_FREE_DELAY if _ragdoll != null else 20.0)


## Instantly kill without a crime report (admin, tests, cleanup).
func kill(cause: String = "generic") -> void:
	if is_dead:
		return
	health = 0.0
	_die(Dmg.make(max_health, cause), null)


func heal(amount: float) -> void:
	if not is_dead:
		health = minf(health + amount, max_health)


# =================================================================================================
# brain / tiers
# =================================================================================================

func set_brain(brain_node: Node) -> void:
	if brain != null and is_instance_valid(brain) and brain != brain_node:
		brain.queue_free()
	brain = brain_node
	if brain_node != null:
		if brain_node.get_parent() == null:
			brain_node.name = "Brain"
			add_child(brain_node)
		elif brain_node.get_parent() != self:
			brain_node.reparent(self)


func _notify(event: String, data: Dictionary) -> void:
	if brain != null and is_instance_valid(brain) and brain.has_method("on_event"):
		brain.call("on_event", self, event, data)


func set_sim_tier(tier: int) -> void:
	tier = clampi(tier, 0, 2)
	if tier == sim_tier and _tier_applied:
		return
	_tier_applied = true
	sim_tier = tier
	if animator != null:
		animator.set("update_rate_hz", TIER_ANIM_HZ[tier])
	if visual != null:
		if visual.has_method("set_lod"):
			visual.call("set_lod", tier)
		if not is_dead and not (is_down and _ragdoll != null):
			visual.visible = tier < 2
	if tier == 0 and current_vehicle == null and not is_dead:
		velocity = Vector3.ZERO
