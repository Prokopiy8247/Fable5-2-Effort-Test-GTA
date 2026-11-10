class_name VehicleDamage
extends RefCounted
## Health and wreck logic shared by every vehicle (benchmark spec section 22):
##   health -> collision / bullet / explosion damage -> damaged handling (power loss, steering
##   pull) -> engine smoke below 45 % -> fire below 15 % -> explosion a few seconds later ->
##   burnt wreck (darkened materials, broken glass, a few detached parts) that freezes and is
##   later removed by VehicleManager.
## Bullets do reduced damage, break the glass pane they hit and pop tyres.

const SMOKE_AT := 0.45
const FIRE_AT := 0.15
const BULLET_FACTOR := 0.35
const MELEE_FACTOR := 0.5
const EXPLOSION_FACTOR := 3.2
const MAX_DEBRIS := 12
const WRECK_FREEZE_SECONDS := 7.0
const DEBRIS_GROUP := "vehicle_debris"

var v: VehicleBase = null
var panes: Array[Node3D] = []
var pane_aabb: Array[AABB] = []
var pane_broken: PackedByteArray = PackedByteArray()
var steer_pull: float = 0.0           ## -1..1 fraction of the steering lock the wheel drags to
var burning: bool = false
var smoking: bool = false
var fuse: float = 0.0                 ## seconds until a burning vehicle explodes
var fire_node: Node3D = null
var smoke_node: Node3D = null         ## looping engine smoke handle (Fx.attach_smoke), if Fx offers one

var _pull_sign: float = 1.0
var _smoke_t: float = 0.0
var _smoke_kind: String = ""
var _wreck_t: float = 0.0
var _hidden_parts: Array[Node3D] = []


func setup(vehicle: VehicleBase) -> void:
	v = vehicle
	_pull_sign = -1.0 if (randi() % 2) == 0 else 1.0
	for part_name: String in v._nodes:
		if not part_name.begins_with("Glass_"):
			continue
		var n := v.get_part(part_name)
		if n == null:
			continue
		panes.append(n)
		pane_aabb.append(v.aabb_in_body(n))
		pane_broken.append(0)


# ==============================================================================================
# taking damage
# ==============================================================================================

func apply(info: Dictionary) -> void:
	if v.destroyed:
		return
	var amount := float(info.get("amount", 0.0))
	if amount <= 0.0:
		return
	var type := str(info.get("type", "generic"))
	var inst: Variant = info.get("instigator", null)
	if inst != null and is_instance_valid(inst) and inst is Node:
		v.last_instigator = inst
	var pos: Vector3 = info.get("position", Vector3.ZERO)
	var has_pos := pos != Vector3.ZERO and v.is_inside_tree()
	match type:
		"bullet":
			amount *= BULLET_FACTOR
			if has_pos:
				_bullet_hit(pos)
		"melee":
			amount *= MELEE_FACTOR
			if has_pos:
				break_glass_at(pos, 0.12)
		"explosion":
			amount *= EXPLOSION_FACTOR
			if amount > 120.0:
				break_all_glass(true)
		_:
			pass
	amount *= float(v.mod_stats.get("damage_taken", 1.0))
	v.health = maxf(v.health - amount, 0.0)
	_update_pull()
	if v.is_inside_tree():
		if v.sleeping:
			v.sleeping = false
		EventBus.vehicle_damaged.emit(v, amount, info)
	if v.health <= 0.0:
		# never pop instantly from regular damage: burn for a moment (also staggers chain reactions)
		v.health = 1.0
		if not burning:
			_ignite(randf_range(0.35, 0.9) if type == "explosion" else randf_range(1.6, 2.6))
		else:
			fuse = minf(fuse, 0.6)


func on_collision(other: Node, dv: float, pos: Vector3, normal: Vector3) -> void:
	var d := maxf(dv - VehicleBase.COLLISION_DV_MIN, 0.0)
	var amount := (d * 10.0 + d * d * 0.5) * v.spec.collision_damage_scale
	var rb := other as RigidBody3D
	if rb != null and rb.mass < v.mass * 0.2:
		amount *= 0.25
	# who is to blame: the other vehicle's driver, else whoever drives this one (self-inflicted)
	var inst: Node = null
	if other != null and other.is_in_group("vehicle"):
		inst = other
		var od: Variant = other.get("driver")
		if od != null and is_instance_valid(od):
			inst = od
	elif v.driver != null and is_instance_valid(v.driver):
		inst = v.driver
	if amount > 0.5:
		apply(Dmg.make(amount, "collision", inst, pos, -normal, {"normal": normal}))
	if v.destroyed:
		return
	if dv > 6.0:
		break_glass_at(pos, 0.5 + dv * 0.04)
	if dv > 7.5 and v.is_inside_tree():
		# heavy hit on the nose / tail: the lid springs ajar, harder hits also kill the lamps
		var local := v.global_transform.affine_inverse() * pos
		var c := v.body_aabb.get_center()
		var front := local.z < c.z - v.body_aabb.size.z * 0.3
		var rear := local.z > c.z + v.body_aabb.size.z * 0.3
		if front:
			v.set_lid_open("hood", maxf(v.get_lid_open("hood"), randf_range(0.16, 0.38)))
		elif rear:
			v.set_lid_open("trunk", maxf(v.get_lid_open("trunk"), randf_range(0.16, 0.38)))
		if dv > 9.0 and v.lights != null:
			if front:
				v.lights.set_broken(true, v.lights.tail_broken)
			elif rear:
				v.lights.set_broken(v.lights.head_broken, true)


func _bullet_hit(pos: Vector3) -> void:
	if break_glass_at(pos, 0.1):
		return
	if bool(v.mod_stats.get("bulletproof_tires", false)):
		return
	for i in v.get_wheel_count():
		if v.is_tire_flat(i):
			continue
		if pos.distance_to(v.get_wheel_position(i)) < v.get_wheel_radius(i) * 1.1:
			v.pop_tire(i)
			return


func _update_pull() -> void:
	var r := v.get_health_ratio()
	steer_pull = _pull_sign * clampf((0.5 - r) / 0.5, 0.0, 1.0) * 0.12


# ==============================================================================================
# glass
# ==============================================================================================

## Break every intact pane whose bounds (grown by `radius`) contain the world position.
func break_glass_at(world_pos: Vector3, radius: float = 0.0) -> bool:
	if panes.is_empty() or not v.is_inside_tree():
		return false
	var local := v.global_transform.affine_inverse() * world_pos
	var any := false
	for i in panes.size():
		if pane_broken[i] == 0 and pane_aabb[i].grow(radius).has_point(local):
			_break_pane(i, true)
			any = true
	return any


func break_all_glass(with_fx: bool) -> void:
	var fx_left := 2
	for i in panes.size():
		if pane_broken[i] == 0:
			_break_pane(i, with_fx and fx_left > 0)
			fx_left -= 1


func get_broken_glass_count() -> int:
	var n := 0
	for b in pane_broken:
		n += int(b)
	return n


func _break_pane(i: int, with_fx: bool) -> void:
	pane_broken[i] = 1
	var n := panes[i]
	if is_instance_valid(n):
		n.visible = false
	if with_fx and v.is_inside_tree() and v.detail_level <= 1:
		var wp := v.global_transform * pane_aabb[i].get_center()
		var out := wp - v.get_center_position()
		Fx.glass_shatter(wp, out.normalized() if out.length() > 0.01 else Vector3.UP, 1.0)
		Audio.play_at("glass_break", wp, -4.0, randf_range(0.9, 1.1), 45.0)


# ==============================================================================================
# smoke / fire / explosion
# ==============================================================================================

func update(delta: float) -> void:
	if v.destroyed:
		if not v.freeze:
			_wreck_t += delta
			if _wreck_t > WRECK_FREEZE_SECONDS or (_wreck_t > 2.5 and v.sleeping):
				v.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
				v.freeze = true
		return
	var r := v.get_health_ratio()
	if r >= SMOKE_AT and not burning:
		smoking = false
		if _smoke_kind != "":
			_set_smoke("")
		return
	smoking = true
	if r < FIRE_AT and not burning:
		_ignite(randf_range(4.5, 7.0))
	if burning:
		fuse -= delta
		if fuse <= 0.0:
			explode(v.get_last_instigator())
			return
	var heavy := r < 0.3
	var kind := ""
	if v.detail_level <= 1 and v.is_inside_tree():
		kind = "black" if burning else ("heavy" if heavy else "light")
	if kind != _smoke_kind:
		_set_smoke(kind)
	if kind != "" and smoke_node == null:
		# Fx without attachable emitters: timed puffs instead
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.2 if heavy else 0.4
			Fx.smoke_puff(v.get_engine_position() + Vector3.UP * 0.2, kind, 1.3 if heavy else 0.8)


## Engine smoke: one looping emitter from the Fx pool that follows the Engine marker.
## kind "" stops it; "light" / "heavy" / "black" swap the look as the damage gets worse.
func _set_smoke(kind: String) -> void:
	_smoke_kind = kind
	if smoke_node != null and is_instance_valid(smoke_node):
		smoke_node.queue_free()
	smoke_node = null
	if kind == "" or not v.is_inside_tree() or not Fx.has_method("attach_smoke"):
		return
	var h: Variant = Fx.call("attach_smoke", v, kind)
	if h != null and is_instance_valid(h) and h is Node3D:
		smoke_node = h
		smoke_node.position = v.global_transform.affine_inverse() * v.get_engine_position() + Vector3(0.0, 0.15, 0.0)


func _ignite(fuse_seconds: float) -> void:
	burning = true
	smoking = true
	v.on_fire = true
	fuse = fuse_seconds
	if not v.is_inside_tree():
		return
	var pos := v.get_engine_position()
	fire_node = Fx.spawn_fire(pos, fuse_seconds + 0.5, v, 1.1)
	_blame_fire()
	EventBus.fire_started.emit(pos, v)
	if v.is_player_driven:
		UI.notify("Vehicle on fire - get out!", "bad")


## Burn damage dealt by this vehicle's fire is credited to whoever damaged the vehicle last.
func _blame_fire() -> void:
	if fire_node == null or not is_instance_valid(fire_node):
		return
	var who := v.get_last_instigator()
	if who != null and "instigator" in fire_node:
		fire_node.set("instigator", who)


func explode(instigator: Node = null) -> void:
	if v.destroyed:
		return
	_set_smoke("")
	v.destroyed = true
	v.health = 0.0
	burning = false
	smoking = false
	v.on_fire = false
	v.engine_on = false
	v.siren_on = false
	v.horn_on = false
	v.headlight_mode = 0
	v.wreck_time_msec = VehicleBase.now_msec()
	if instigator == null or not is_instance_valid(instigator):
		instigator = v.get_last_instigator()
	var in_tree := v.is_inside_tree()
	var pos := v.get_center_position() if in_tree else Vector3.ZERO
	# occupants: lethal blast, then thrown clear
	for o: Variant in v.get_occupants():
		if o != null and is_instance_valid(o) and (o as Node).has_method("apply_damage"):
			(o as Node).call("apply_damage", Dmg.make(1000.0, "explosion", instigator, pos, Vector3.UP, {"impulse": 600.0}))
	v.eject_occupants(Vector3.UP * 450.0 + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 250.0)
	break_all_glass(false)
	v.set_lid_open("hood", randf_range(0.45, 1.0), true)
	v.set_lid_open("trunk", randf_range(0.15, 1.0), true)
	if in_tree:
		_spawn_debris()
	v._apply_burnt_look()
	v._on_destroyed()
	if v.audio != null:
		v.audio.stop_all()
	if v.lights != null:
		v.lights.refresh()
	if fire_node != null and is_instance_valid(fire_node):
		fire_node.queue_free()
	fire_node = null
	if not in_tree:
		return
	v.sleeping = false
	v.apply_central_impulse(Vector3.UP * v.mass * 3.0 + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * v.mass * 0.7)
	v.apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3), randf_range(-1.0, 1.0)) * v.mass * 0.8)
	# the wreck carries its own fire (it follows the tumbling body and never burns the wreck itself)
	Fx.explosion(pos, 7.5, 220.0, instigator, {"ignore": [v], "fire": false, "visual_scale": 1.2})
	fire_node = Fx.spawn_fire(pos, 14.0, v, 1.5)
	_blame_fire()
	EventBus.vehicle_destroyed.emit(v, instigator)


## Full restore: health, glass, tyres, lights, burnt look, flooded engine (if out of the water).
func repair() -> void:
	var was_wreck := v.destroyed
	v.destroyed = false
	v.health = v.max_health
	burning = false
	smoking = false
	v.on_fire = false
	fuse = 0.0
	steer_pull = 0.0
	_wreck_t = 0.0
	_set_smoke("")
	if fire_node != null and is_instance_valid(fire_node):
		fire_node.queue_free()
	fire_node = null
	for i in panes.size():
		pane_broken[i] = 0
		if is_instance_valid(panes[i]):
			panes[i].visible = true
	for n: Node3D in _hidden_parts:
		if is_instance_valid(n):
			n.visible = true
	_hidden_parts.clear()
	v.set_lid_open("hood", 0.0, true)
	v.set_lid_open("trunk", 0.0, true)
	if v.lights != null:
		v.lights.set_broken(false, false)
	if not v.in_water:
		v.stalled = false
	if was_wreck:
		v.freeze = false
		v._restore_materials()
	v._on_repaired()
	v._apply_paint()
	if v.is_inside_tree():
		v.sleeping = false


# ==============================================================================================
# debris
# ==============================================================================================

func _spawn_debris() -> void:
	var parts: Array[Node3D] = []
	var wc := v.get_wheel_count()
	if wc > 0 and v.has_method("detach_wheel"):
		var first := randi() % wc
		for k in 2:
			if randf() < 0.75:
				var idx := (first + k * 3) % wc
				var node: Variant = v.call("detach_wheel", idx)
				if node != null and is_instance_valid(node):
					parts.append(node as Node3D)
	if v.has_lid("hood") and randf() < 0.35:
		parts.append(v.get_part("Hood"))
	if not v._doors.is_empty() and randf() < 0.7:
		var door := v._doors[randi() % v._doors.size()]
		if is_instance_valid(door) and door.visible:
			parts.append(door)
	for p: Node3D in parts:
		_make_debris(p)


func _make_debris(part: Node3D) -> void:
	if not part.visible or v.get_tree().get_nodes_in_group(DEBRIS_GROUP).size() >= MAX_DEBRIS:
		return
	var gt := part.global_transform
	var box := v.aabb_in_body(part)
	var body := RigidBody3D.new()
	body.name = "VehicleDebris"
	body.add_to_group(DEBRIS_GROUP)
	body.collision_layer = Layers.DEBRIS
	body.collision_mask = Layers.WORLD
	body.mass = 16.0
	Game.get_entities_root().add_child(body)
	body.global_transform = Transform3D(gt.basis.orthonormalized(), gt.origin)
	var vis := part.duplicate() as Node3D
	body.add_child(vis)
	vis.global_transform = gt
	vis.visible = true
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.size.x, 0.12), maxf(box.size.y, 0.12), maxf(box.size.z, 0.12))
	# the body-space box is close enough to the part's own frame for cosmetic debris
	cs.shape = shape
	body.add_child(cs)
	cs.global_position = v.global_transform * box.get_center()
	var out := gt.origin - v.get_center_position()
	out.y = 0.0
	out = out.normalized() if out.length() > 0.05 else Vector3.RIGHT
	body.apply_central_impulse((out * randf_range(4.0, 8.0) + Vector3.UP * randf_range(5.0, 9.0)) * body.mass)
	body.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	part.visible = false
	_hidden_parts.append(part)
	# the debris frees itself (the callable lives on the debris body, not on this helper)
	v.get_tree().create_timer(randf_range(9.0, 14.0), false).timeout.connect(body.queue_free)
