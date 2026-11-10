class_name Projectile
extends RigidBody3D
## Thrown / launched explosive (spawn through Combat.spawn_projectile or Combat.launch).
##
##   grenade        real rigid body: bounces, explodes when the fuse runs out
##   rocket         swept kinematic flight, accelerates, explodes on contact, smoke trail
##                  (Fx.attach_trail when the Fx module offers it, Fx.smoke_puff otherwise)
##   grenade_round  swept ballistic arc, impact fuse once it has travelled ARM distance;
##                  a round that hits earlier becomes a bouncing dud with a short fuse
##   molotov        swept ballistic arc, breaks on impact -> fire pool (Fx.spawn_fire). The Fx
##                  fire handle burns what stands in it (this code sets its radius, damage and
##                  instigator); with an Fx that has no burning fires the projectile ticks itself
##
## Explosions go through Fx.explosion (radial damage, impulse, noise, crime, EventBus.explosion).
## Models come from res://gta/generated/models/weapons/<kind>.glb when present.
## The number of live projectiles is bounded (MAX_ACTIVE; the oldest goes off early).

const MAX_ACTIVE := 24
const MODEL_DIR := "res://gta/generated/models/weapons"
const SWEEP_MASK := Layers.WORLD | Layers.PLAYER | Layers.NPC | Layers.VEHICLE | Layers.PROP | Layers.GLASS
const BODY_MASK := Layers.WORLD | Layers.VEHICLE | Layers.PROP | Layers.NPC | Layers.PLAYER | Layers.GLASS
const BURN_MASK := Layers.PLAYER | Layers.NPC | Layers.VEHICLE | Layers.PROP
const GRAVITY := 9.8

## Defaults per kind (damage / radius / fuse can be overridden through the launch opts).
const KINDS := {
	"grenade": {"damage": 220.0, "radius": 7.0, "fuse": 3.2, "swept": false, "gravity": 1.0,
			"shape_radius": 0.07, "mass": 0.45, "bounce": 0.38},
	"rocket": {"damage": 480.0, "radius": 8.5, "fuse": 6.0, "swept": true, "gravity": 0.0,
			"accel": 45.0, "max_speed": 85.0, "arm": 1.2, "shape_radius": 0.08, "mass": 2.0, "bounce": 0.0},
	"grenade_round": {"damage": 230.0, "radius": 6.0, "fuse": 8.0, "swept": true, "gravity": 1.0,
			"arm": 4.0, "dud_fuse": 2.2, "shape_radius": 0.06, "mass": 0.3, "bounce": 0.3},
	"molotov": {"damage": 12.0, "radius": 3.0, "fuse": 8.0, "swept": true, "gravity": 1.0,
			"fire_duration": 9.0, "burn_interval": 0.5, "shape_radius": 0.07, "mass": 0.5, "bounce": 0.0},
}

static var _active: Array = []          ## live projectiles, oldest first
static var _scene_cache: Dictionary = {}

var kind: String = "grenade"
var instigator: Node = null
var weapon_id: String = ""
var damage: float = 200.0
var radius: float = 6.0
var fuse: float = 3.0                   ## seconds left (lifetime for swept kinds)
var exploded: bool = false

var _cfg: Dictionary = {}
var _swept: bool = false
var _velocity: Vector3 = Vector3.ZERO
var _travelled: float = 0.0
var _age: float = 0.0
var _trail_t: float = 0.0
var _bounce_cd: float = 0.0
var _burning: bool = false
var _burn_left: float = 0.0
var _burn_tick: float = 0.0
var _burn_external: bool = false
var _fire_node: Node3D = null
var _model: Node3D = null
var _exhaust: Node3D = null
var _trail: Node3D = null               ## Fx trail handle of a rocket (child of this node) or null
var _exclude: Array[RID] = []


## Create, configure and add a projectile to the world. Returns null for unknown kinds.
static func launch(p_kind: String, origin: Vector3, velocity: Vector3, p_instigator: Node = null,
		opts: Dictionary = {}) -> Projectile:
	if not KINDS.has(p_kind):
		push_warning("Projectile.launch: unknown kind '%s'" % p_kind)
		return null
	var root := Game.get_entities_root()
	if root == null:
		return null
	_prune()
	while _active.size() >= MAX_ACTIVE:
		var oldest: Projectile = _active[0]
		oldest._end_early()
	var p := Projectile.new()
	p.kind = p_kind
	p.instigator = p_instigator
	p._cfg = KINDS[p_kind]
	p.damage = float(opts.get("damage", p._cfg["damage"]))
	p.radius = float(opts.get("radius", p._cfg["radius"]))
	if p.radius <= 0.0:
		p.radius = float(p._cfg["radius"])
	p.fuse = maxf(float(opts.get("fuse", p._cfg["fuse"])), 0.05)
	p.weapon_id = str(opts.get("weapon_id", p_kind))
	p._velocity = velocity
	p.name = "Projectile_%s" % p_kind
	p._configure_body()
	root.add_child(p)
	p.global_position = origin
	p._after_spawn()
	_active.append(p)
	return p


static func get_active_count() -> int:
	_prune()
	return _active.size()


## Remove every live projectile without detonating it (admin / respawn clean-up).
static func clear_all() -> void:
	_prune()
	for p: Projectile in _active.duplicate():
		p.queue_free()
	_active.clear()


static func _prune() -> void:
	for i in range(_active.size() - 1, -1, -1):
		var p: Variant = _active[i]
		if p == null or not is_instance_valid(p) or (p as Node).is_queued_for_deletion():
			_active.remove_at(i)


func _configure_body() -> void:
	_swept = bool(_cfg["swept"])
	add_to_group("projectile")
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = float(_cfg["shape_radius"])
	shape.shape = sphere
	add_child(shape)
	mass = float(_cfg["mass"])
	var mat := PhysicsMaterial.new()
	mat.bounce = float(_cfg["bounce"])
	mat.friction = 0.8
	physics_material_override = mat
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	linear_damp = 0.25
	angular_damp = 1.5
	if _swept:
		_set_swept_mode(true)
	else:
		collision_layer = Layers.PROJECTILE
		collision_mask = BODY_MASK
		gravity_scale = float(_cfg["gravity"])
	_exclude.append(get_rid())
	if instigator != null and is_instance_valid(instigator):
		if instigator is CollisionObject3D:
			_exclude.append((instigator as CollisionObject3D).get_rid())
			add_collision_exception_with(instigator)
		var vehicle: Variant = instigator.get("current_vehicle")
		if vehicle != null and is_instance_valid(vehicle) and vehicle is CollisionObject3D:
			_exclude.append((vehicle as CollisionObject3D).get_rid())
			add_collision_exception_with(vehicle as Node)
	body_entered.connect(_on_body_entered)
	_load_model()


func _set_swept_mode(on: bool) -> void:
	_swept = on
	if on:
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		collision_layer = 0
		collision_mask = 0
	else:
		freeze = false
		collision_layer = Layers.PROJECTILE
		collision_mask = BODY_MASK
		gravity_scale = 1.0


func _load_model() -> void:
	var path := "%s/%s.glb" % [MODEL_DIR, kind]
	var scene: PackedScene = null
	if _scene_cache.has(path):
		scene = _scene_cache[path]
	else:
		if ResourceLoader.exists(path):
			scene = load(path) as PackedScene
		_scene_cache[path] = scene
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	if _model == null:
		return
	_model.name = "Model"
	add_child(_model)
	_exhaust = _model.find_child("Exhaust", true, false) as Node3D
	for n in _model.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.name.begins_with("Att_") or g.name.begins_with("Col_"):
			g.visible = false
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visibility_range_end = 150.0


func _after_spawn() -> void:
	if _swept:
		_face_velocity()
	else:
		linear_velocity = _velocity
		angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-3.0, 3.0), randf_range(-6.0, 6.0))
	if kind == "molotov" and _model != null:
		_model.rotation.x = randf_range(-0.4, 0.4)
	# looping exhaust trail from the Fx pool; it is a child handle and goes away with the rocket
	if kind == "rocket" and Fx.has_method("attach_trail"):
		var handle: Variant = Fx.call("attach_trail", self, "rocket")
		if handle is Node3D and is_instance_valid(handle):
			_trail = handle as Node3D
			if _exhaust != null and _exhaust.is_inside_tree():
				_trail.global_position = _exhaust.global_position


func _exit_tree() -> void:
	_active.erase(self)


func _physics_process(delta: float) -> void:
	if _burning:
		_process_burn(delta)
		return
	if exploded:
		return
	_age += delta
	fuse -= delta
	_bounce_cd -= delta
	if _swept:
		_process_swept(delta)
		if exploded or _burning:
			return
	else:
		# a live grenade that rolls into the sea goes off under water
		if global_position.y < Game.WATER_LEVEL - 0.6 and Game.is_in_water(global_position):
			fuse = minf(fuse, 0.35)
	if fuse <= 0.0:
		if kind == "molotov":
			_break_molotov(global_position, Vector3.UP, null)
		else:
			_explode(global_position)


func _process_swept(delta: float) -> void:
	if float(_cfg["gravity"]) > 0.0:
		_velocity.y -= GRAVITY * float(_cfg["gravity"]) * delta
	if _cfg.has("accel"):
		var speed := _velocity.length()
		if speed > 0.01 and speed < float(_cfg["max_speed"]):
			_velocity = _velocity / speed * minf(speed + float(_cfg["accel"]) * delta, float(_cfg["max_speed"]))
	var from := global_position
	var step := _velocity * delta
	var to := from + step
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, SWEEP_MASK, _exclude)
	var hit := space.intersect_ray(query)
	# sea surface
	if from.y > Game.WATER_LEVEL and to.y <= Game.WATER_LEVEL and (hit.is_empty() or (hit["position"] as Vector3).y < Game.WATER_LEVEL):
		var t := (from.y - Game.WATER_LEVEL) / maxf(from.y - to.y, 0.0001)
		var surface_point := from.lerp(to, t)
		if Game.is_in_water(Vector3(surface_point.x, Game.WATER_LEVEL - 0.05, surface_point.z)):
			global_position = surface_point
			Fx.splash(surface_point, 1.5)
			if kind == "molotov":
				_finish()            # the flame is drowned
			else:
				_explode(surface_point)
			return
	if not hit.is_empty():
		var pos: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		_travelled += from.distance_to(pos)
		global_position = pos + normal * 0.05
		_on_swept_contact(pos, normal, hit["collider"])
		return
	_travelled += step.length()
	global_position = to
	_face_velocity()
	if kind == "rocket" and (_trail == null or not is_instance_valid(_trail)):
		_trail_t -= delta
		if _trail_t <= 0.0:
			_trail_t = 0.045
			Fx.smoke_puff(_exhaust.global_position if _exhaust != null else from, "light", 0.55)


func _on_swept_contact(pos: Vector3, normal: Vector3, collider: Object) -> void:
	match kind:
		"rocket":
			_explode(pos + normal * 0.1)
		"grenade_round":
			if _travelled >= float(_cfg["arm"]):
				_explode(pos + normal * 0.1)
			else:
				# not armed yet: drops as a dud that cooks off shortly after
				var reflected := _velocity.bounce(normal) * 0.25
				_set_swept_mode(false)
				linear_velocity = reflected
				fuse = float(_cfg["dud_fuse"])
				Audio.play_at("grenade_bounce", pos, -4.0, 1.1, 40.0, "SFX")
		"molotov":
			_break_molotov(pos, normal, collider)
		_:
			_explode(pos)


func _face_velocity() -> void:
	if _velocity.length_squared() < 0.01:
		return
	var dir := _velocity.normalized()
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(dir, up), global_position)


func _on_body_entered(_body: Node) -> void:
	if _swept or exploded or _burning:
		return
	if _bounce_cd <= 0.0 and linear_velocity.length() > 1.2:
		_bounce_cd = 0.18
		Audio.play_at("grenade_bounce", global_position, -5.0, randf_range(0.9, 1.1), 40.0, "SFX")
		Combat.emit_noise(global_position, 9.0, "footstep", instigator)


func _explode(at: Vector3) -> void:
	if exploded:
		return
	exploded = true
	var who: Node = instigator if (instigator != null and is_instance_valid(instigator)) else null
	Fx.explosion(at, radius, damage, who, {"weapon_id": weapon_id, "ignore": [self]})
	_finish()


## Goes off where it is, right now (bounded-count eviction).
func _end_early() -> void:
	_active.erase(self)
	if _burning:
		_finish()
	elif kind == "molotov":
		_finish()
	else:
		_explode(global_position)


func _finish() -> void:
	exploded = true
	_burning = false
	_active.erase(self)
	set_physics_process(false)
	queue_free()


# --- molotov ------------------------------------------------------------------------------------

func _break_molotov(pos: Vector3, normal: Vector3, collider: Object) -> void:
	exploded = true
	var who: Node = instigator if (instigator != null and is_instance_valid(instigator)) else null
	if _model != null:
		_model.visible = false
	_set_swept_mode(true)
	global_position = pos + normal * 0.1
	Fx.glass_shatter(pos, normal, 0.6)
	Audio.play_at("glass_break", pos, -2.0, 1.15, 60.0, "SFX")
	var duration := float(_cfg["fire_duration"])
	_fire_node = Fx.spawn_fire(pos, duration, null, 1.6)
	# the real Fx fire may burn things itself; then this projectile only keeps the bookkeeping
	_burn_external = _fire_node != null and is_instance_valid(_fire_node) and (
			_fire_node.get("deals_damage") == true or _fire_node.has_meta("deals_damage"))
	if _burn_external:
		# same pool as the built-in ticks: spec damage per burn interval inside the blast radius
		_fire_node.set("instigator", who)
		_fire_node.set("weapon_id", weapon_id)
		_fire_node.set("radius", radius)
		_fire_node.set("damage_per_second", damage / maxf(float(_cfg["burn_interval"]), 0.05))
	EventBus.fire_started.emit(pos, who)
	Combat.emit_noise(pos, 25.0, "crash", who)
	if Dmg.is_player(who):
		Wanted.report_crime("disturbance", pos, {"instigator": who})
	# whoever the bottle hits directly gets splashed
	if collider != null:
		Dmg.apply(collider, Dmg.make(damage * 1.5, "fire", who, pos, -normal, {"weapon_id": weapon_id}))
	_burning = true
	_burn_left = duration
	_burn_tick = 0.0


func _process_burn(delta: float) -> void:
	_burn_left -= delta
	if _burn_left <= 0.0:
		_finish()
		return
	if _burn_external:
		return
	_burn_tick -= delta
	if _burn_tick > 0.0:
		return
	_burn_tick = float(_cfg["burn_interval"])
	var who: Node = instigator if (instigator != null and is_instance_valid(instigator)) else null
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 0.6)
	query.collision_mask = BURN_MASK
	var done: Dictionary = {}
	for res: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 12):
		var target := Dmg.find_damageable(res["collider"])
		if target == null or done.has(target.get_instance_id()):
			continue
		done[target.get_instance_id()] = true
		var amount := damage * (0.35 if target.is_in_group("vehicle") else 1.0)
		var at: Vector3 = (target as Node3D).global_position if target is Node3D else global_position
		target.apply_damage(Dmg.make(amount, "fire", who, at, Vector3.UP, {"weapon_id": weapon_id}))
