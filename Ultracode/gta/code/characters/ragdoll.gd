class_name Ragdoll
extends Node3D
## Simple, stable rigid-segment ragdoll for the shared humanoid (docs/ARCHITECTURE.md 6.3).
##
##     var rag := Ragdoll.spawn_from(visual, impulse, hit_position)      # returns null on failure
##
## * 11 rigid segments (pelvis, torso, head, 2 x upper / lower arm, 2 x thigh / shin) on
##   Layers.RAGDOLL, tied together with cone-twist joints (spine, neck, shoulders, hips) and
##   hinges (elbows, knees).
## * The joints are created in a REFERENCE pose in which every joint sits in the middle of its
##   range, then the bodies are moved to the pose the character has right now. All limits are
##   therefore symmetric and independent of any sign convention of the physics backend - knees
##   and elbows cannot bend the wrong way.
## * The ragdoll owns a fresh copy of the character visual (same appearance) and drives its
##   skeleton from the bodies; the source visual is NOT touched (the caller hides or frees it).
## * Auto clean-up after `lifetime` seconds, at most MAX_ACTIVE ragdolls exist (oldest goes
##   first). Set `persistent = true` to manage the lifetime yourself (the player does).

const MAX_ACTIVE := 8
const DEFAULT_LIFETIME := 16.0
const TOTAL_MASS := 75.0

enum { J_NONE, J_CONE, J_HINGE }

## name, bone, tail bone ("" = special), parent segment, radius, mass share, joint, span a, span b
const SEGMENTS: Array = [
	["Pelvis", "Hips", "Spine", -1, 0.125, 11.0, J_NONE, 0.0, 0.0],
	["Torso", "Spine", "Neck", 0, 0.140, 24.0, J_CONE, 0.42, 0.35],
	["Head", "Neck", "Head", 1, 0.105, 6.0, J_CONE, 0.60, 0.50],
	["UpperArm_L", "UpperArm_L", "LowerArm_L", 1, 0.050, 2.4, J_CONE, 1.35, 0.60],
	["LowerArm_L", "LowerArm_L", "Hand_L", 3, 0.043, 2.0, J_HINGE, 1.15, 0.0],
	["UpperArm_R", "UpperArm_R", "LowerArm_R", 1, 0.050, 2.4, J_CONE, 1.35, 0.60],
	["LowerArm_R", "LowerArm_R", "Hand_R", 5, 0.043, 2.0, J_HINGE, 1.15, 0.0],
	["Thigh_L", "UpperLeg_L", "LowerLeg_L", 0, 0.075, 8.5, J_CONE, 0.90, 0.30],
	["Shin_L", "LowerLeg_L", "Foot_L", 7, 0.058, 5.0, J_HINGE, 1.15, 0.0],
	["Thigh_R", "UpperLeg_R", "LowerLeg_R", 0, 0.075, 8.5, J_CONE, 0.90, 0.30],
	["Shin_R", "LowerLeg_R", "Foot_R", 9, 0.058, 5.0, J_HINGE, 1.15, 0.0],
]

static var _active: Array = []

var lifetime: float = DEFAULT_LIFETIME
var persistent: bool = false
var bodies: Array[RigidBody3D] = []

var _visual: Node3D = null
var _skel: Skeleton3D = null
var _skel_inv: Transform3D = Transform3D.IDENTITY
var _bone: PackedInt32Array = PackedInt32Array()
var _anc: PackedInt32Array = PackedInt32Array()
var _off: Array[Transform3D] = []          # bone transform in body space (may carry the model scale)
var _chain: Array[Transform3D] = []        # static local poses between the driven ancestor and the bone
var _pose: Array[Transform3D] = []         # scratch: bone global poses in skeleton space
var _age: float = 0.0
var _check_t: float = 0.0
var _frozen: bool = false
var _in_water: bool = false


## Builds a ragdoll that matches `visual` (a CharacterVisual or any Node3D containing the contract
## Skeleton3D) in its current pose. `impulse` (N*s) is applied at `position` (world; Vector3.INF =
## centre of mass). `initial_velocity` carries the momentum of the character.
static func spawn_from(visual: Node3D, impulse: Vector3 = Vector3.ZERO, position: Vector3 = Vector3.INF,
		initial_velocity: Vector3 = Vector3.ZERO) -> Node3D:
	if visual == null or not is_instance_valid(visual) or not visual.is_inside_tree():
		return null
	var src := find_skeleton(visual)
	if src == null:
		return null
	var parent: Node = Game.get_entities_root()
	if parent == null:
		parent = visual.get_tree().current_scene
	if parent == null:
		return null
	var rag := Ragdoll.new()
	rag.name = "Ragdoll"
	parent.add_child(rag)
	if not rag._build(visual, src, initial_velocity):
		rag.queue_free()
		return null
	rag.apply_impulse_at(impulse, position)
	_register(rag)
	return rag


static func find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	if node.has_method("get_skeleton"):
		var s: Variant = node.call("get_skeleton")
		if s is Skeleton3D:
			return s as Skeleton3D
	for c in node.get_children():
		var r := find_skeleton(c)
		if r != null:
			return r
	return null


static func get_active_count() -> int:
	_prune()
	return _active.size()


static func clear_all() -> void:
	for r: Variant in _active:
		if is_instance_valid(r):
			(r as Node).queue_free()
	_active.clear()


static func _prune() -> void:
	var i := _active.size() - 1
	while i >= 0:
		if not is_instance_valid(_active[i]) or (_active[i] as Node).is_queued_for_deletion():
			_active.remove_at(i)
		i -= 1


static func _register(rag: Ragdoll) -> void:
	_prune()
	_active.append(rag)
	var guard := 0
	while _active.size() > MAX_ACTIVE and guard < 16:
		guard += 1
		var victim := -1
		for i in _active.size():
			if not (_active[i] as Ragdoll).persistent and _active[i] != rag:
				victim = i
				break
		if victim < 0:
			break
		(_active[victim] as Node).queue_free()
		_active.remove_at(victim)


func get_pelvis() -> RigidBody3D:
	return bodies[0] if bodies.size() > 0 else null


func get_pelvis_position() -> Vector3:
	return bodies[0].global_position if bodies.size() > 0 else global_position


func get_velocity() -> Vector3:
	return bodies[0].linear_velocity if bodies.size() > 0 else Vector3.ZERO


## Yaw (radians, 0 = -Z) a character should face when it stands up from this ragdoll: towards its
## feet when lying on the back, towards its head when lying face down.
func get_stand_yaw() -> float:
	if bodies.size() < 2:
		return 0.0
	var f := bodies[1].global_position - bodies[0].global_position
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return bodies[0].global_rotation.y
	if is_face_up():
		f = -f
	return atan2(-f.x, -f.z)


func is_face_up() -> bool:
	if bodies.size() < 2:
		return true
	return bodies[1].global_basis.z.y < 0.0     # -Z of the torso body is the chest front


## Copies the pose the ragdoll has right now onto another contract skeleton (for example the
## character's own, hidden, visual) so that an animator can cross-fade out of it without a pop.
## The Hips bone is re-expressed in the frame of `target`, wherever that skeleton stands.
func copy_pose_to(target: Skeleton3D) -> void:
	if target == null or _skel == null or not is_instance_valid(_skel):
		return
	if target.get_bone_count() != _skel.get_bone_count():
		return
	_drive_skeleton()
	for b in _skel.get_bone_count():
		target.set_bone_pose_rotation(b, _skel.get_bone_pose_rotation(b))
		target.set_bone_pose_position(b, _skel.get_bone_pose_position(b))
	var hips := _bone[0]
	var world := _skel.global_transform * _skel.get_bone_global_pose(hips)
	var parent := target.get_bone_parent(hips)
	var parent_global := target.global_transform
	if parent >= 0:
		parent_global = target.global_transform * target.get_bone_global_pose(parent)
	var local := (parent_global.affine_inverse() * world).orthonormalized()
	target.set_bone_pose_position(hips, local.origin)
	target.set_bone_pose_rotation(hips, local.basis.get_rotation_quaternion())


func is_settled() -> bool:
	if _frozen:
		return true
	for b in bodies:
		if b.linear_velocity.length_squared() > 0.25 or b.angular_velocity.length_squared() > 1.5:
			return false
	return true


func apply_impulse_at(impulse: Vector3, position: Vector3 = Vector3.INF) -> void:
	if bodies.is_empty() or impulse.length_squared() < 0.000001:
		return
	_unfreeze()
	var target := bodies[1] if bodies.size() > 1 else bodies[0]
	var offset := Vector3.ZERO
	if position.is_finite():
		var best := INF
		for b in bodies:
			var d := b.global_position.distance_squared_to(position)
			if d < best:
				best = d
				target = b
		offset = (position - target.global_position).limit_length(0.25)
	target.apply_impulse(impulse * 0.55, offset)
	for b in bodies:
		b.apply_central_impulse(impulse * 0.45 * (b.mass / TOTAL_MASS))


func set_velocity(v: Vector3) -> void:
	_unfreeze()
	for b in bodies:
		b.linear_velocity = v


## Remove the ragdoll now (the owner calls this for persistent ragdolls).
func dismiss() -> void:
	_active.erase(self)
	if not is_queued_for_deletion():
		queue_free()


func _exit_tree() -> void:
	_active.erase(self)


func _process(delta: float) -> void:
	_age += delta
	if not persistent and _age >= lifetime:
		dismiss()
		return
	if bodies.is_empty():
		return
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.3
		_update_water()
		if not _frozen and _age > 2.5 and not _in_water and _all_slow():
			_frozen = true
			for b in bodies:
				b.freeze = true
	if not _frozen:
		_drive_skeleton()


func _all_slow() -> bool:
	for b in bodies:
		if b.linear_velocity.length_squared() > 0.006 or b.angular_velocity.length_squared() > 0.04:
			return false
	return true


func _unfreeze() -> void:
	if _frozen:
		_frozen = false
		for b in bodies:
			b.freeze = false
	_age = minf(_age, 1.0) if persistent else _age


func _update_water() -> void:
	var wet := Game.is_in_water(bodies[0].global_position)
	if wet == _in_water:
		return
	_in_water = wet
	for b in bodies:
		b.gravity_scale = 0.12 if wet else 1.0
		b.linear_damp = 2.6 if wet else 0.12
		b.angular_damp = 3.5 if wet else 1.6


# --- construction ---------------------------------------------------------------------------------

func _build(src_visual: Node3D, src: Skeleton3D, initial_velocity: Vector3) -> bool:
	var n := SEGMENTS.size()
	var bone_src := PackedInt32Array()
	bone_src.resize(n)
	for i in n:
		bone_src[i] = src.find_bone(SEGMENTS[i][1])
		if bone_src[i] < 0:
			return false

	# --- visual copy
	var path := src_visual.scene_file_path
	if path != "" and ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			_visual = ps.instantiate() as Node3D
	if _visual == null:
		_visual = src_visual.duplicate() as Node3D
	if _visual == null:
		return false
	_visual.name = "Visual"
	add_child(_visual)
	_visual.global_transform = src_visual.global_transform
	_visual.visible = true
	if _visual.has_method("apply_appearance") and src_visual.has_method("get_appearance"):
		var app: Variant = src_visual.call("get_appearance")
		if app is Dictionary:
			_visual.call("apply_appearance", app)
	_strip_drivers(_visual)
	_skel = find_skeleton(_visual)
	if _skel == null or _skel.get_bone_count() != src.get_bone_count():
		return false
	for b in src.get_bone_count():
		_skel.set_bone_pose_position(b, src.get_bone_pose_position(b))
		_skel.set_bone_pose_rotation(b, src.get_bone_pose_rotation(b))
		_skel.set_bone_pose_scale(b, Vector3.ONE)
	# keep the copy exactly where the source skeleton is
	_skel.global_transform = src.global_transform
	var S := src.global_transform
	var S_rot := S.basis.orthonormalized()
	var sc := S.basis.get_scale().x
	_skel_inv = S.affine_inverse()

	# --- rest geometry in skeleton space
	_bone.resize(n)
	_anc.resize(n)
	_off.resize(n)
	_chain.resize(n)
	_pose.resize(n)
	var rest_body: Array[Transform3D] = []
	var anchor: PackedVector3Array = PackedVector3Array()
	var seg_dir: PackedVector3Array = PackedVector3Array()
	var seg_len: PackedFloat32Array = PackedFloat32Array()
	rest_body.resize(n)
	anchor.resize(n)
	seg_dir.resize(n)
	seg_len.resize(n)
	for i in n:
		_bone[i] = _skel.find_bone(SEGMENTS[i][1])
		var a := src.get_bone_global_rest(bone_src[i]).origin
		var tail_bone := src.find_bone(SEGMENTS[i][2])
		var b := a + Vector3(0.0, 0.1, 0.0)
		if tail_bone >= 0:
			b = src.get_bone_global_rest(tail_bone).origin
		if i == 2:
			b = b + Vector3(0.0, 0.17, 0.0)          # top of the skull
		elif i == 4 or i == 6:
			b = b + (b - a).normalized() * 0.07     # include the hand
		var y := b - a
		var length := maxf(y.length(), 0.04)
		y = y / length if y.length() > 0.0001 else Vector3.UP
		var x := Vector3.RIGHT - y * y.dot(Vector3.RIGHT)
		if x.length_squared() < 0.05:
			x = Vector3.BACK - y * y.dot(Vector3.BACK)
		x = x.normalized()
		var z := x.cross(y)
		rest_body[i] = Transform3D(Basis(x, y, z), (a + b) * 0.5)
		anchor[i] = a
		seg_dir[i] = y
		seg_len[i] = length

	# --- reference pose (every joint in the middle of its range), model-space deltas
	var g_ref: Array[Quaternion] = []
	g_ref.resize(n)
	var a_ref: PackedVector3Array = PackedVector3Array()
	a_ref.resize(n)
	var d_ref: Array[Quaternion] = [
		Quaternion.IDENTITY, Quaternion.IDENTITY, Quaternion.IDENTITY,
		Quaternion(Vector3.BACK, 0.80), Quaternion(Vector3.UP, -1.15),
		Quaternion(Vector3.BACK, -0.80), Quaternion(Vector3.UP, 1.15),
		Quaternion(Vector3.RIGHT, 0.45), Quaternion(Vector3.RIGHT, -1.15),
		Quaternion(Vector3.RIGHT, 0.45), Quaternion(Vector3.RIGHT, -1.15),
	]
	for i in n:
		var p: int = SEGMENTS[i][3]
		if p < 0:
			g_ref[i] = Quaternion.IDENTITY
			a_ref[i] = anchor[i]
		else:
			g_ref[i] = g_ref[p] * d_ref[i]
			a_ref[i] = a_ref[p] + g_ref[p] * (anchor[i] - anchor[p])

	# --- bodies in the reference pose
	var mass_sum := 0.0
	for i in n:
		mass_sum += float(SEGMENTS[i][5])
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	phys.bounce = 0.0
	for i in n:
		var radius: float = float(SEGMENTS[i][4]) * sc
		var length: float = seg_len[i] * sc
		var body := RigidBody3D.new()
		body.name = SEGMENTS[i][0]
		body.collision_layer = Layers.RAGDOLL
		body.collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.PROP
		body.mass = float(SEGMENTS[i][5]) / mass_sum * TOTAL_MASS
		body.physics_material_override = phys
		body.linear_damp = 0.12
		body.angular_damp = 1.6
		body.can_sleep = true
		body.continuous_cd = i < 3
		var cs := CollisionShape3D.new()
		if i == 0:
			var box := BoxShape3D.new()
			box.size = Vector3(0.28 * sc, maxf(length + 0.08 * sc, 0.14 * sc), 0.19 * sc)
			cs.shape = box
		elif i == 1:
			var box2 := BoxShape3D.new()
			box2.size = Vector3(0.31 * sc, maxf(length, 0.2 * sc), 0.20 * sc)
			cs.shape = box2
		elif i == 2:
			var sph := SphereShape3D.new()
			sph.radius = radius
			cs.shape = sph
			cs.position = Vector3(0.0, length * 0.12, 0.0)
		else:
			var cap := CapsuleShape3D.new()
			cap.radius = radius
			cap.height = maxf(length + radius, radius * 2.0 + 0.01)
			cs.shape = cap
		body.add_child(cs)
		add_child(body)
		var ref_model := Transform3D(Basis(g_ref[i]) * rest_body[i].basis,
				a_ref[i] + g_ref[i] * (rest_body[i].origin - anchor[i]))
		body.global_transform = Transform3D(S_rot * ref_model.basis, S * ref_model.origin)
		bodies.append(body)

	# --- joints (created while the bodies are in the reference pose)
	var self_inv := global_transform.affine_inverse()
	for i in n:
		var p: int = SEGMENTS[i][3]
		var kind: int = SEGMENTS[i][6]
		if p < 0 or kind == J_NONE:
			continue
		var joint: Joint3D
		var jb: Basis
		if kind == J_HINGE:
			var hj := HingeJoint3D.new()
			hj.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			hj.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -float(SEGMENTS[i][7]))
			hj.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, float(SEGMENTS[i][7]))
			joint = hj
			# elbows hinge about the model Y axis, knees about the model X axis (parent frame)
			var axis_local := Vector3.UP if (i == 4 or i == 6) else Vector3.RIGHT
			var az := (S_rot * (g_ref[p] * axis_local)).normalized()
			var ax := az.cross(Vector3.UP)
			if ax.length_squared() < 0.01:
				ax = az.cross(Vector3.RIGHT)
			ax = ax.normalized()
			jb = Basis(ax, az.cross(ax), az)
		else:
			var cj := ConeTwistJoint3D.new()
			cj.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, float(SEGMENTS[i][7]))
			cj.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, float(SEGMENTS[i][8]))
			joint = cj
			# twist axis (joint X) along the child segment
			var tx := (S_rot * (g_ref[i] * seg_dir[i])).normalized()
			var ty := tx.cross(Vector3.RIGHT)
			if ty.length_squared() < 0.01:
				ty = tx.cross(Vector3.UP)
			ty = ty.normalized()
			jb = Basis(tx, ty, tx.cross(ty))
		joint.name = "J_" + String(SEGMENTS[i][0])
		joint.node_a = NodePath("../" + String(SEGMENTS[p][0]))
		joint.node_b = NodePath("../" + String(SEGMENTS[i][0]))
		joint.exclude_nodes_from_collision = true
		# the joint is configured when it enters the tree, so place it first
		joint.transform = self_inv * Transform3D(jb, S * a_ref[i])
		add_child(joint)

	# --- bone <-> body mapping, then move every body to the pose the character has right now
	for i in n:
		var rest_world_body := Transform3D(S_rot * rest_body[i].basis, S * rest_body[i].origin)
		var bone_rest_world := S * src.get_bone_global_rest(bone_src[i])
		_off[i] = rest_world_body.affine_inverse() * bone_rest_world
		var pose_world := S * src.get_bone_global_pose(bone_src[i])
		var now := (pose_world * _off[i].affine_inverse()).orthonormalized()
		bodies[i].global_transform = now
		bodies[i].linear_velocity = initial_velocity
		bodies[i].angular_velocity = Vector3.ZERO
	# ancestors: which driven bone (if any) is above each driven bone, and the static chain between
	for i in n:
		var chain := Transform3D.IDENTITY
		var pb := _skel.get_bone_parent(_bone[i])
		var anc := -1
		while pb >= 0:
			var found := -1
			for j in n:
				if _bone[j] == pb:
					found = j
					break
			if found >= 0:
				anc = found
				break
			chain = _skel.get_bone_pose(pb) * chain
			pb = _skel.get_bone_parent(pb)
		_anc[i] = anc
		_chain[i] = chain
		_pose[i] = Transform3D.IDENTITY
	_drive_skeleton()
	return true


func _strip_drivers(node: Node) -> void:
	for c in node.get_children():
		if c is HumanoidAnimator:
			(c as HumanoidAnimator).auto_process = false
			c.process_mode = Node.PROCESS_MODE_DISABLED
		elif c is AnimationPlayer or c is AnimationTree:
			c.process_mode = Node.PROCESS_MODE_DISABLED
		_strip_drivers(c)


func _drive_skeleton() -> void:
	if _skel == null or not is_instance_valid(_skel):
		return
	var n := bodies.size()
	for i in n:
		_pose[i] = _skel_inv * (bodies[i].global_transform * _off[i])
	for i in n:
		var parent_global: Transform3D = _chain[i]
		if _anc[i] >= 0:
			parent_global = _pose[_anc[i]] * _chain[i]
		var local := parent_global.affine_inverse() * _pose[i]
		_skel.set_bone_pose_position(_bone[i], local.origin)
		_skel.set_bone_pose_rotation(_bone[i], local.basis.get_rotation_quaternion())
