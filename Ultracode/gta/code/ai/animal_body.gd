class_name AnimalBody
extends CharacterBody3D
## One animal (land mammal, bird or shark): the BODY. Group "animal", layer Layers.NPC, mask 0.
##
## No per-node _process: the wildlife system (code/ai/wildlife_system.gd) drives every animal from
## one loop - tick_move() every physics frame (tier 0/1), tick_think() at the tier rate,
## tick_anim() from _process. Behaviour lives in a brain (AnimalLandAi / AnimalBirdAi /
## AnimalSharkAi), animation in an AnimalRig. Positions are set kinematically: ground following via
## Game.world.get_height(), the collider exists so bullets, melee, explosions and vehicles
## (VehicleBase strikes group "animal") can hit it.
##
## Damage contract: apply_damage(info) (Dmg), knock_down(impulse) (vehicles), get_target_position().
## Killing animals is not a crime, except dogs / cats harmed by the player in front of a civilian
## (the system reports "assault" once per burst).

signal died(animal: Node3D, killer: Node)
signal damaged(animal: Node3D, info: Dictionary)

var species := ""
var def: Dictionary = {}
var kind := "land"                  ## "land" | "bird" | "fish"
var category := "land"              ## spawn budget: "land" | "bird" | "water"
var temperament := ""
var health := 10.0
var max_health := 10.0
var is_dead := false
var persistent := false             ## never auto-despawned (the caller frees it)
var home := Vector3.ZERO
var system: Node = null             ## the wildlife system
var brain: RefCounted = null
var rig: AnimalRig = null
var visual: Node3D = null
var sim_tier := 0
var think_accum := 0.0
var anim_accum := 0.0                ## far-tier movement accumulator
var anim_t := 0.0                    ## tier-1 animation accumulator
var flock_id := -1
var habitat := ""
var stray := false                  ## dogs: aggressive stray
var corpse_timer := 0.0
var age := 0.0

# --- kinematic state (written by the brain) ----------------------------------------------------
var yaw := 0.0
var speed := 0.0                    ## forward speed m/s
var vspeed := 0.0                   ## vertical speed (birds / fish / falling corpses)
var slope_pitch := 0.0              ## visual pitch (radians, + = nose up)
var bank := 0.0                     ## visual roll in flight (radians)

# --- animation parameters (read by AnimalRig) ---------------------------------------------------
var anim_speed := 0.0
var anim_pose := "stand"
var look_yaw := 0.0
var wag := 0.0
var alert := 0.0
var flap := 0.0
var fold := 1.0
var action := ""
var action_t := 0.0
var action_dur := 0.0
var death_t := 0.0
var death_side := 1.0

# --- reactions ---------------------------------------------------------------------------------
var last_attacker: Node = null
var last_damage_info: Dictionary = {}
var _hit_box: CollisionShape3D = null
var _crime_cd := 0.0
var _hurt_cd := 0.0
var _corpse_vel := Vector3.ZERO
var _corpse_air := false
var _meshes: Array[MeshInstance3D] = []
var _visible := true


## Builds the animal (called once by the wildlife system). `d` = AnimalAssets.species_def().
func setup_animal(id: String, d: Dictionary, sys: Node, ps: PackedScene) -> bool:
	species = id
	def = d
	system = sys
	kind = String(d.get("kind", "land"))
	category = String(d.get("category", "land"))
	temperament = String(d.get("temperament", "timid"))
	name = "Animal_" + id
	add_to_group("animal")
	collision_layer = Layers.NPC
	collision_mask = 0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if ps == null:
		return false
	visual = ps.instantiate() as Node3D
	if visual == null:
		return false
	visual.name = "Visual"
	add_child(visual)
	var vis_end := 150.0 if kind == "land" else (125.0 if kind == "bird" else 90.0)
	for n: Node in visual.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = 8.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if kind == "bird" or (kind == "land" and float(d.get("shoulder_height", 0.5)) < 0.3):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_meshes.append(mi)
	rig = AnimalRig.new()
	rig.setup(visual, d)
	_build_collider()
	match kind:
		"bird":
			brain = AnimalBirdAi.new()
		"fish":
			brain = AnimalSharkAi.new()
		_:
			brain = AnimalLandAi.new()
	return true


func _build_collider() -> void:
	var sz: Vector3 = def.get("size_v", Vector3(0.5, 0.5, 0.5))
	var sh := shape_box_for(def)
	_hit_box = CollisionShape3D.new()
	_hit_box.name = "Hit"
	var box := BoxShape3D.new()
	box.size = sh
	_hit_box.shape = box
	match kind:
		"fish":
			_hit_box.position = Vector3(0.0, -0.1, 0.0)
		"bird":
			_hit_box.position = Vector3(0.0, sh.y * 0.5, 0.0)
		_:
			_hit_box.position = Vector3(0.0, sh.y * 0.5 + minf(sz.y * 0.05, 0.05), 0.0)
	add_child(_hit_box)


static func shape_box_for(d: Dictionary) -> Vector3:
	var sz: Vector3 = d.get("size_v", Vector3(0.5, 0.5, 0.5))
	var k := String(d.get("kind", "land"))
	if k == "bird":
		var r := float(d.get("length", 0.4))
		return Vector3(r * 0.7, maxf(sz.y * 0.9, 0.18), r * 0.9)
	if k == "fish":
		return Vector3(minf(sz.x, 0.95), sz.y * 0.8, sz.z * 0.85)
	var sh := float(d.get("shoulder_height", sz.y * 0.6))
	return Vector3(clampf(sz.x * 0.85, 0.12, 0.8), maxf(sh * 1.05, 0.15), sz.z * 0.85)


## (Re)starts the animal at `pos`. opts: yaw, persistent, home, state, flock, stray, flying, habitat.
func begin(pos: Vector3, opts: Dictionary) -> void:
	is_dead = false
	max_health = float(def.get("health", 10.0))
	health = max_health
	persistent = bool(opts.get("persistent", false))
	home = opts.get("home", pos)
	habitat = String(opts.get("habitat", ""))
	flock_id = int(opts.get("flock", -1))
	stray = bool(opts.get("stray", false))
	yaw = float(opts.get("yaw", randf() * TAU))
	speed = 0.0
	vspeed = 0.0
	slope_pitch = 0.0
	bank = 0.0
	anim_speed = 0.0
	anim_pose = "stand"
	look_yaw = 0.0
	wag = 0.0
	alert = 0.0
	flap = 0.0
	fold = 1.0
	action = ""
	action_t = 0.0
	death_t = 0.0
	corpse_timer = 0.0
	age = 0.0
	last_attacker = null
	last_damage_info = {}
	_corpse_air = false
	_corpse_vel = Vector3.ZERO
	_crime_cd = 0.0
	_hurt_cd = 0.0
	anim_accum = 0.0
	anim_t = 0.0
	think_accum = randf() * 0.1
	if kind == "land":
		pos.y = ground_y(pos.x, pos.z)
	collision_layer = Layers.NPC
	if _hit_box != null:
		_hit_box.disabled = false
	if rig != null:
		rig.reset_pose()
	global_position = pos
	_apply_yaw()
	velocity = Vector3.ZERO
	set_visual_visible(true)
	if brain != null and brain.has_method("begin"):
		brain.call("begin", self, opts)
	if rig != null:
		rig.update(self, 0.0)


func _apply_yaw() -> void:
	global_basis = Basis(Vector3.UP, yaw)


func set_visual_visible(on: bool) -> void:
	if _visible == on or visual == null:
		return
	_visible = on
	visual.visible = on


func set_sim_tier(t: int) -> void:
	sim_tier = t
	set_visual_visible(t < 2 or is_dead)


func is_alive() -> bool:
	return not is_dead


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func ground_y(x: float, z: float) -> float:
	if Game.world != null and is_instance_valid(Game.world) and Game.world.has_method("get_height"):
		return Game.world.get_height(x, z)
	return Game.ground_height(x, z)


func water_depth(x: float, z: float) -> float:
	if Game.world != null and is_instance_valid(Game.world) and Game.world.has_method("get_water_depth"):
		return Game.world.get_water_depth(x, z)
	return -1.0


func get_target_position() -> Vector3:
	var h := float(def.get("shoulder_height", 0.4))
	if kind == "fish":
		return global_position
	if kind == "bird":
		return global_position + Vector3.UP * 0.15
	return global_position + Vector3.UP * h * 0.7


func start_action(a: String, dur: float) -> void:
	action = a
	action_t = 0.0
	action_dur = dur


func play_sound(key: String, vol_db: float = 0.0, max_dist: float = 60.0, pitch_mul: float = 1.0) -> void:
	var sounds: Dictionary = def.get("sounds", {})
	var id := String(sounds.get(key, ""))
	if id == "" or not Audio.has_method("play_at"):
		return
	var p := float(def.get("pitch", 1.0)) * pitch_mul * randf_range(0.92, 1.08)
	Audio.play_at(id, get_target_position(), vol_db, p, max_dist)


# =================================================================================================
# per-frame entry points (called by the wildlife system)
# =================================================================================================

func tick_move(dt: float) -> void:
	age += dt
	if action != "":
		action_t += dt
		if action_t >= action_dur:
			action = ""
	if _crime_cd > 0.0:
		_crime_cd -= dt
	if _hurt_cd > 0.0:
		_hurt_cd -= dt
	if is_dead:
		_tick_corpse(dt)
		return
	if brain != null:
		brain.call("step", self, dt)
	_apply_yaw()


func tick_think(dt: float) -> void:
	if is_dead or brain == null:
		return
	brain.call("think", self, dt)


func tick_anim(dt: float) -> void:
	if rig != null:
		rig.update(self, dt)


# =================================================================================================
# stimuli
# =================================================================================================

func hear_noise(pos: Vector3, radius: float, noise_kind: String, instigator: Node) -> void:
	if is_dead or brain == null:
		return
	var hearing := float(def.get("hearing", 1.0))
	var d := global_position.distance_to(pos)
	if d > radius * hearing:
		return
	brain.call("on_noise", self, pos, radius, noise_kind, instigator, d)


## Make the animal attack `target` (any Node3D with apply_damage), e.g. the player or a test dummy.
func attack(target: Node3D) -> void:
	if is_dead or brain == null or target == null or not is_instance_valid(target):
		return
	if brain.has_method("attack"):
		brain.call("attack", self, target)


## Provocation without damage (aimed at, shoved): aggressive species attack, others flee.
func provoke(by: Node3D) -> void:
	if is_dead or brain == null or by == null:
		return
	if brain.has_method("on_provoked"):
		brain.call("on_provoked", self, by)


func flee_from(pos: Vector3) -> void:
	if is_dead or brain == null:
		return
	if brain.has_method("flee"):
		brain.call("flee", self, pos, 1.0)


func calm() -> void:
	if brain != null and brain.has_method("calm"):
		brain.call("calm", self)


func get_state_name() -> String:
	if is_dead:
		return "dead"
	if brain != null and brain.has_method("state_name"):
		return String(brain.call("state_name"))
	return "idle"


# =================================================================================================
# damage / death
# =================================================================================================

func apply_damage(info: Dictionary) -> void:
	var amount := float(info.get("amount", 0.0))
	if amount <= 0.0:
		return
	var attacker: Variant = info.get("instigator", null)
	var who: Node = null
	if attacker != null and is_instance_valid(attacker) and attacker is Node:
		who = attacker as Node
		# a vehicle's driver is the one who did it
		if who.is_in_group("vehicle"):
			var drv: Variant = who.get("driver")
			if drv != null and is_instance_valid(drv) and drv is Node:
				who = drv as Node
	var by_player := Dmg.caused_by_player(info)
	if is_dead:
		_push_corpse(info)
		return
	health -= amount
	last_attacker = who
	last_damage_info = info
	var t := String(info.get("type", "generic"))
	var pos: Vector3 = info.get("position", get_target_position())
	if pos == Vector3.ZERO:
		pos = get_target_position()
	if t in ["bullet", "melee", "bite", "explosion", "vehicle"] and kind != "fish":
		var dir: Vector3 = info.get("direction", Vector3.ZERO)
		Fx.blood(pos, -dir if dir != Vector3.ZERO else Vector3.UP)
	elif kind == "fish" and t in ["bullet", "melee", "bite"]:
		Fx.blood(pos, Vector3.UP)
	damaged.emit(self, info)
	if by_player and bool(def.get("crime_victim", false)) and system != null and _crime_cd <= 0.0:
		_crime_cd = 3.0
		system.call("report_pet_harm", self, info)
	if health <= 0.0:
		_die(who, info)
		return
	if _hurt_cd <= 0.0:
		_hurt_cd = 0.6
		play_sound("hurt", -2.0, 55.0, 1.25)
	start_action("flinch", 0.3)
	if brain != null and brain.has_method("on_damaged"):
		brain.call("on_damaged", self, info, who)


## Vehicles call this on a strike (after apply_damage): living animals stumble, corpses are thrown.
func knock_down(impulse: Vector3) -> void:
	if is_dead:
		_launch_corpse(impulse)
		return
	start_action("flinch", 0.45)
	if brain != null and brain.has_method("flee"):
		brain.call("flee", self, global_position - impulse.normalized() * 3.0, 1.0)


func kill(cause: String = "generic") -> void:
	if is_dead:
		return
	health = 0.0
	_die(null, Dmg.make(max_health, cause))


func _die(killer: Node, info: Dictionary) -> void:
	is_dead = true
	health = 0.0
	collision_layer = 0
	if _hit_box != null:
		_hit_box.set_deferred("disabled", true)
	speed = 0.0
	anim_speed = 0.0
	action = ""
	velocity = Vector3.ZERO
	death_side = -1.0 if randf() < 0.5 else 1.0
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	if dir != Vector3.ZERO:
		# fall away from the hit: roll towards the side the hit pushes to
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		death_side = -1.0 if dir.dot(right) > 0.0 else 1.0
	var mult := 1.0
	if system != null and is_instance_valid(system):
		var m: Variant = system.get("corpse_time_mult")
		if m != null:
			mult = float(m)
	corpse_timer = float(def.get("corpse_time", 30.0)) * mult
	_corpse_air = kind == "bird" and global_position.y > ground_y(global_position.x, global_position.z) + 0.2
	if kind == "fish":
		_corpse_air = true
	var imp := float(info.get("impulse", 0.0))
	if imp > 0.0 and dir != Vector3.ZERO and kind != "fish":
		_launch_corpse(dir.normalized() * imp)
	play_sound("hurt", 0.0, 60.0, 0.9)
	if brain != null and brain.has_method("on_death"):
		brain.call("on_death", self)
	died.emit(self, killer)
	if system != null:
		system.call("on_animal_died", self, killer)


func _launch_corpse(impulse: Vector3) -> void:
	if kind == "fish":
		return
	var mass := maxf(float(def.get("mass", 20.0)), 0.3)
	var v := impulse / mass
	if v.length() > 14.0:
		v = v.normalized() * 14.0
	v.y = maxf(v.y, minf(v.length() * 0.35, 5.0))
	if v.length() < 0.8:
		return
	_corpse_vel = v
	_corpse_air = true


func _push_corpse(info: Dictionary) -> void:
	var imp := float(info.get("impulse", 0.0))
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	if imp > 40.0 and dir != Vector3.ZERO:
		_launch_corpse(dir.normalized() * imp * 0.6)


func _tick_corpse(dt: float) -> void:
	corpse_timer -= dt
	death_t = minf(death_t + dt / (0.55 if kind != "fish" else 2.5), 1.0)
	var p := global_position
	if kind == "fish":
		# belly up, drifting slowly to the surface
		var surf := Game.WATER_LEVEL - 0.35
		if p.y < surf:
			p.y = minf(p.y + dt * 0.35, surf)
		slope_pitch = lerpf(slope_pitch, 0.0, dt)
		global_position = p
		return
	if _corpse_air:
		_corpse_vel.y -= 9.8 * dt
		p += _corpse_vel * dt
		var g := ground_y(p.x, p.z)
		if water_depth(p.x, p.z) > 0.3:
			g = maxf(g, Game.WATER_LEVEL - 0.25)
		if p.y <= g:
			p.y = g
			_corpse_air = false
			_corpse_vel = Vector3.ZERO
		global_position = p
	else:
		var g := ground_y(p.x, p.z)
		if water_depth(p.x, p.z) > 0.3:
			g = maxf(g, Game.WATER_LEVEL - 0.25)
		p.y = g
		global_position = p
	slope_pitch = lerpf(slope_pitch, 0.0, minf(dt * 4.0, 1.0))
	bank = lerpf(bank, 0.0, minf(dt * 4.0, 1.0))
