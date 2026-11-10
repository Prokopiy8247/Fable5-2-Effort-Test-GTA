class_name Character
extends CharacterBody3D
## Shared base of the player and every NPC: capsule body, health/armour, damage zones,
## vehicle seating, knock-down / death handling, water detection and the CharacterVisual.

signal died(killer: Node)
signal damaged(amount: float, attacker: Node)

const HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const RADIUS := 0.3
const GRAVITY := 16.0
const SWIM_DEPTH := 1.3        # feet this far below the surface => swimming

var team: StringName = &"civil"
var is_player := false
var max_health := 100.0
var health := 100.0
var armor := 0.0
var alive := true
var visual: CharacterVisual
var col: CollisionShape3D
var capsule: CapsuleShape3D
var appearance: Dictionary = {}
var vehicle: Node3D = null
var seat := -1
var in_water := false
var water_depth := -1.0
var last_attacker: Node = null
var last_damage_time := -100.0
var down := false               # knocked down / ragdolled
var crouched := false
var gunner: Gunner = null
var inventory: Inventory = null
var face_yaw := 0.0             # model facing (radians, 0 = -Z)
var _down_timer := 0.0
var _body_layer := Phys.CHARACTER
var _body_mask := Phys.WALK_SOLID

func setup_body(ap: Dictionary) -> void:
	appearance = ap
	collision_layer = _body_layer
	collision_mask = _body_mask
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.35
	max_slides = 4
	capsule = CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	col = CollisionShape3D.new()
	col.shape = capsule
	col.position = Vector3(0, HEIGHT * 0.5, 0)
	add_child(col)
	visual = CharacterVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.build(String(ap.get("body", "male")))
	visual.set_appearance(ap)
	inventory = Inventory.new()
	inventory.owner_is_player = is_player
	gunner = Gunner.new()
	gunner.name = "Gunner"
	add_child(gunner)
	gunner.setup(self)

func set_appearance(ap: Dictionary) -> void:
	var body_changed := String(ap.get("body", "male")) != String(appearance.get("body", "male"))
	appearance = ap
	if body_changed and visual != null:
		var old := visual
		visual = CharacterVisual.new()
		visual.name = "Visual"
		add_child(visual)
		visual.build(String(ap.get("body", "male")))
		visual.rotation = old.rotation
		old.queue_free()
		if gunner:
			gunner.refresh_model()
	visual.set_appearance(ap)

func set_crouched(on: bool) -> void:
	if on == crouched:
		return
	if not on:
		# need head room to stand up
		var from := global_position + Vector3(0, CROUCH_HEIGHT, 0)
		if not Game.ray(from, from + Vector3(0, HEIGHT - CROUCH_HEIGHT + 0.1, 0), Phys.WORLD | Phys.VEHICLE, [get_rid()]).is_empty():
			return
	crouched = on
	var h := CROUCH_HEIGHT if on else HEIGHT
	capsule.height = h
	col.position.y = h * 0.5

func eye_position() -> Vector3:
	return global_position + Vector3(0, (1.05 if crouched else 1.62), 0)

func chest_position() -> Vector3:
	return global_position + Vector3(0, (0.75 if crouched else 1.15), 0)

func forward() -> Vector3:
	return Vector3(-sin(face_yaw), 0.0, -cos(face_yaw))

func set_face_yaw(y: float) -> void:
	face_yaw = y
	if visual:
		visual.rotation.y = y

func turn_toward(dir: Vector3, delta: float, rate := 10.0) -> void:
	if dir.length_squared() < 0.0001:
		return
	var target := atan2(-dir.x, -dir.z)
	set_face_yaw(lerp_angle(face_yaw, target, clampf(delta * rate, 0.0, 1.0)))

func update_water() -> void:
	water_depth = Game.water_depth(global_position)
	in_water = water_depth > 0.0

# ---------------------------------------------------------------- damage
func hit_zone(hit_pos: Vector3) -> StringName:
	if visual == null:
		return &"torso"
	var head := visual.head_position()
	if hit_pos.distance_to(head) < 0.2 or hit_pos.y > head.y - 0.12:
		return &"head"
	if hit_pos.y < global_position.y + (0.45 if crouched else 0.85):
		return &"legs"
	return &"torso"

## info keys: zone, type ("bullet" | "melee" | "explosion" | "vehicle" | "fall" | "drown" | "fire"), force
func apply_damage(amount: float, source: Node = null, hit_pos := Vector3.ZERO, dir := Vector3.ZERO, info: Dictionary = {}) -> void:
	if not alive or amount <= 0.0:
		return
	if is_player and Game.cheats["invulnerable"]:
		return
	var kind := String(info.get("type", "bullet"))
	var zone: StringName = info.get("zone", &"torso")
	if kind == "bullet":
		if zone == &"head":
			amount *= 2.6
		elif zone == &"legs":
			amount *= 0.7
	# armour soaks most bullet / blast damage
	if armor > 0.0 and (kind == "bullet" or kind == "explosion" or kind == "melee"):
		var soak := minf(armor, amount * 0.8)
		armor -= soak
		amount -= soak * 0.9
	health -= amount
	last_attacker = source
	last_damage_time = Game.clock
	if visual:
		visual.flash_hit()
	damaged.emit(amount, source)
	_on_damaged(amount, source, hit_pos, dir, info)
	if health <= 0.0:
		health = 0.0
		die(source, dir * float(info.get("force", 2.0)), info)
	elif (kind == "vehicle" or kind == "explosion") and amount >= 12.0:
		knockdown(dir * float(info.get("force", 4.0)), 2.2)

func _on_damaged(_amount: float, _source: Node, _hit_pos: Vector3, _dir: Vector3, _info: Dictionary) -> void:
	pass

func heal(amount: float) -> void:
	if alive:
		health = minf(max_health, health + amount)

func die(killer: Node = null, impulse := Vector3.ZERO, info: Dictionary = {}) -> void:
	if not alive:
		return
	alive = false
	down = true
	if vehicle != null and is_instance_valid(vehicle) and vehicle.has_method("eject"):
		vehicle.eject(self)
	collision_layer = 0
	collision_mask = Phys.WORLD
	if gunner:
		gunner.drop_weapon_model()
	velocity = impulse * 0.6
	if visual:
		visual.upper = &""
		var kind := String(info.get("type", "bullet"))
		# physical ragdoll for violent deaths, animated collapse for quiet ones (takedowns, drowning)
		var limp := kind != "drown" and not bool(info.get("silent", false)) and visual.start_ragdoll(impulse * 0.5, velocity)
		if not limp:
			if visual.play_action("Death_Front" if info.get("from_behind", false) else "Death_Back") <= 0.0:
				visual.set_state(&"dead")
			else:
				visual.state = &"dead"
	died.emit(killer)
	_on_died(killer)

func _on_died(_killer: Node) -> void:
	pass

## Short loss of control (hit by a car, explosion, heavy melee). NPCs and the player get up again.
func knockdown(impulse := Vector3.ZERO, seconds := 2.0) -> void:
	if not alive or down or vehicle != null:
		return
	down = true
	_down_timer = seconds
	velocity = impulse
	velocity.y = maxf(velocity.y, 2.0)
	if visual:
		visual.upper = &""
		# hard hits throw the body around physically, light ones play the knockdown animation
		if impulse.length() > 5.0 and visual.start_ragdoll(impulse * 0.35, velocity):
			pass
		elif visual.play_action("Knockdown") <= 0.0:
			visual.set_state(&"dead")
	Audio.play(&"body_fall", global_position, -6.0)

func _tick_down(delta: float) -> void:
	# shared "lying on the ground" physics for knocked-down and dead characters
	if visual != null and visual.ragdolling:
		_tick_ragdoll(delta)
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, delta * 9.0)
	velocity.z = move_toward(velocity.z, 0.0, delta * 9.0)
	move_and_slide()
	if alive and down:
		_down_timer -= delta
		if _down_timer <= 0.0 and is_on_floor():
			down = false
			var t := visual.play_action("GetUp") if visual else 0.0
			if t <= 0.0 and visual:
				visual.set_state(&"idle")

## While ragdolled the body is simulated: the character root follows the pelvis on the ground
## (the skinned mesh stays where physics put it), and a knocked-down character gets up once settled.
func _tick_ragdoll(delta: float) -> void:
	var hips := visual.ragdoll_hips()
	var root_y := global_position.y
	var hit := Game.ray(hips + Vector3(0, 0.5, 0), hips - Vector3(0, 3.0, 0), Phys.WORLD)
	if not hit.is_empty():
		root_y = (hit["position"] as Vector3).y
	global_position = Vector3(hips.x, root_y, hips.z)
	velocity = Vector3.ZERO
	if alive and down:
		_down_timer -= delta
		if _down_timer <= 0.0 and visual.ragdoll_settled():
			down = false
			var face_down := visual.ragdoll_face_down()
			visual.stop_ragdoll()
			if face_down:
				set_face_yaw(face_yaw + PI)
			var t0 := visual.play_action("GetUp")
			if t0 <= 0.0:
				visual.set_state(&"idle")

# ---------------------------------------------------------------- vehicles
func attach_to_seat(veh: Node3D, seat_index: int, seat_node: Node3D, pose: StringName) -> void:
	vehicle = veh
	seat = seat_index
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	var parent := get_parent()
	if parent != seat_node:
		if parent:
			parent.remove_child(self)
		seat_node.add_child(self)
	transform = Transform3D.IDENTITY
	set_face_yaw(0.0)
	if visual:
		visual.set_state(pose)
		visual.upper = &""

func detach_from_seat(world_pos: Vector3, yaw: float) -> void:
	var entities: Node = Game.main.get_node_or_null("Entities") if Game.main else null
	var parent := get_parent()
	if parent:
		parent.remove_child(self)
	if entities:
		entities.add_child(self)
	vehicle = null
	seat = -1
	global_transform = Transform3D(Basis.IDENTITY, world_pos)
	set_face_yaw(yaw)
	if visual:
		visual.position = Vector3.ZERO
		visual.set_ik_hands(null, null)
		visual.set_state(&"idle")
	if alive:
		collision_layer = _body_layer
		collision_mask = _body_mask

## Keeps the seated character's hips on the seat marker whatever the sit pose does.
func _seat_align() -> void:
	if visual == null or visual.skeleton == null:
		return
	var hi := visual.skeleton.find_bone("Hips")
	if hi < 0:
		return
	var hips := visual.skeleton.get_bone_global_pose(hi).origin
	var sc := 0.94 if visual.female else 1.0
	# seat markers sit ~0.1 m above the cushion while the pelvis underside is 0.13 below the hips bone
	visual.position = -Vector3(hips.x, hips.y, hips.z) * sc + Vector3(0, -0.1, 0)
