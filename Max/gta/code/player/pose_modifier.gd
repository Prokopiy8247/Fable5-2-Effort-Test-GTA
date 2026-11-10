class_name PoseModifier
extends SkeletonModifier3D
## Procedural animation layer that runs AFTER the AnimationPlayer every frame:
##   * `base`     full-body procedural pose (used when no authored clip exists for a state)
##   * `overlay`  per-bone rotations blended on top (upper-body aim, reload, melee, sitting...)
##   * `add`      additive rotations (aim pitch on the spine, recoil, lean)
##   * `ik`       two-bone IK targets for hands / feet in skeleton space
## The character skeleton has identity rest rotations (bone axes: X right, Y up, Z back),
## so every rotation here is expressed directly in model axes.

var base: Dictionary = {}        # bone idx -> Quaternion
var base_weight := 0.0
var overlay: Dictionary = {}     # bone idx -> Quaternion
var overlay_weight := 0.0
var add: Dictionary = {}         # bone idx -> Quaternion (applied after everything else)
var hips_offset := Vector3.ZERO  # extra translation of the Hips bone (crouch, sit, swim)
var hips_weight := 0.0
var ik_hand_l: Variant = null    # Vector3 target in skeleton space or null
var ik_hand_r: Variant = null
var ik_weight := 1.0
var idx: Dictionary = {}         # bone name -> index
var _len: Dictionary = {}

func setup(sk: Skeleton3D) -> void:
	idx.clear()
	for i in sk.get_bone_count():
		idx[sk.get_bone_name(i)] = i
	for side: String in ["L", "R"]:
		if idx.has("UpperArm_" + side) and idx.has("LowerArm_" + side) and idx.has("Hand_" + side):
			var a := sk.get_bone_global_rest(idx["UpperArm_" + side]).origin
			var b := sk.get_bone_global_rest(idx["LowerArm_" + side]).origin
			var c := sk.get_bone_global_rest(idx["Hand_" + side]).origin
			_len[side] = [a.distance_to(b), b.distance_to(c), (b - a).normalized(), (c - b).normalized()]

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if base_weight > 0.001:
		for b in base.keys():
			var cur := sk.get_bone_pose_rotation(b)
			sk.set_bone_pose_rotation(b, cur.slerp(base[b], base_weight))
	if hips_weight > 0.001 and idx.has("Hips"):
		var hi: int = idx["Hips"]
		var rest_pos := sk.get_bone_rest(hi).origin
		var cur_pos := sk.get_bone_pose_position(hi)
		sk.set_bone_pose_position(hi, cur_pos.lerp(rest_pos + hips_offset, hips_weight))
	if overlay_weight > 0.001:
		for b in overlay.keys():
			var cur2 := sk.get_bone_pose_rotation(b)
			sk.set_bone_pose_rotation(b, cur2.slerp(overlay[b], overlay_weight))
	for b in add.keys():
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * (add[b] as Quaternion))
	if ik_hand_l != null:
		_solve_arm(sk, "L", ik_hand_l)
	if ik_hand_r != null:
		_solve_arm(sk, "R", ik_hand_r)

func _solve_arm(sk: Skeleton3D, side: String, target: Vector3) -> void:
	if not _len.has(side):
		return
	var ua: int = idx["UpperArm_" + side]
	var la: int = idx["LowerArm_" + side]
	var info: Array = _len[side]
	var l1: float = info[0]
	var l2: float = info[1]
	var parent := sk.get_bone_parent(ua)
	var parent_basis := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var shoulder := sk.get_bone_global_pose(ua).origin
	var to_t := target - shoulder
	var dist := clampf(to_t.length(), 0.05, l1 + l2 - 0.005)
	var dir := to_t.normalized()
	# elbow: law of cosines, bent toward a pole pointing down / outward / slightly back
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sx := -1.0 if side == "L" else 1.0
	var pole := Vector3(sx * 0.6, -1.0, 0.45).normalized()
	var perp := (pole - dir * pole.dot(dir))
	if perp.length() < 0.001:
		perp = Vector3.DOWN
	perp = perp.normalized()
	var elbow := shoulder + dir * (cos_a * l1) + perp * (sqrt(maxf(0.0, 1.0 - cos_a * cos_a)) * l1)
	var hand := shoulder + dir * dist
	var u_dir := (elbow - shoulder).normalized()
	var f_dir := (hand - elbow).normalized()
	var r1 := Quaternion(info[2] as Vector3, u_dir)
	var r2 := Quaternion(info[3] as Vector3, f_dir)
	var local1 := parent_basis.get_rotation_quaternion().inverse() * r1
	var local2 := r1.inverse() * r2
	if ik_weight < 0.999:
		local1 = sk.get_bone_pose_rotation(ua).slerp(local1, ik_weight)
		local2 = sk.get_bone_pose_rotation(la).slerp(local2, ik_weight)
	sk.set_bone_pose_rotation(ua, local1)
	sk.set_bone_pose_rotation(la, local2)
