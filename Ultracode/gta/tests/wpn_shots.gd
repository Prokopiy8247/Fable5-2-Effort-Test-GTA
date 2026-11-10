extends Node
## Windowed visual check of the weapon models (short run, screenshots only).
## Run:
##   tools\godot.ps1 -Mode window -Frames 220 -UserArgs '--test=wpn_shots','--no_player','--disable=world,environment,city,interactions,vehicles,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Shots (qa/screenshots/):
##   wpn_shots_side.png         every weapon GLB, orthographic side view. The camera looks along -X,
##                              so screen right = -Z: every barrel must point to the RIGHT.
##   wpn_shots_attachments.png  same sheet with all compatible attachments installed + a finish
##   wpn_shots_persp.png        a few weapons in perspective
##   wpn_shots_hand.png         humanoid: T-pose + animator aim poses with the weapon in Hand_R
##   wpn_shots_pickups.png      pickups of every kind as the PickupSystem builds them
## Also runs data checks on the GLBs (markers, attachment meshes, finish material, sizes).


class FakeVisual extends Node3D:
	var skeleton: Skeleton3D = null
	var sockets: Dictionary = {}

	func get_skeleton() -> Skeleton3D:
		return skeleton

	func get_bone_attachment(bone: String) -> Node3D:
		if sockets.has(bone):
			return sockets[bone]
		var ba := BoneAttachment3D.new()
		ba.name = "Socket_" + bone
		skeleton.add_child(ba)
		ba.bone_name = bone
		sockets[bone] = ba
		return ba


class FakeHolder extends Node3D:
	var visual: Node3D = null


const GRID: Array = [
	["pistol", "heavy_pistol", "smg"],
	["pump_shotgun", "auto_shotgun", "grenade_launcher"],
	["assault_rifle", "carbine", "marksman_rifle"],
	["sniper_rifle", "rocket_launcher", "bat"],
	["crowbar", "knife", "grenade+molotov"],
	["rocket", "grenade_round", ""],
]
const FIREARMS: Array[String] = ["pistol", "heavy_pistol", "smg", "pump_shotgun", "auto_shotgun",
		"assault_rifle", "carbine", "marksman_rifle", "sniper_rifle", "rocket_launcher", "grenade_launcher"]
const FINISHES: Array[String] = ["finish_sand", "finish_olive", "finish_teal", "finish_coral", "finish_gold"]
const COL_STEP := 1.6
const ROW_STEP := 0.47
const HUMANOID := "res://gta/generated/models/characters/humanoid.glb"
const ANIMATOR := "res://gta/code/characters/humanoid_animator.gd"

var _stage: Node3D = null
var _cam: Camera3D = null


func _ready() -> void:
	_build_environment()
	_data_checks()
	await _sheet("wpn_shots_side", false)
	await _sheet("wpn_shots_attachments", true)
	await _perspective()
	await _hand()
	await _pickups()
	TestHarness.finish()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.68, 0.76)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.84, 0.95)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = false
	add_child(sun)
	sun.rotation_degrees = Vector3(-42.0, 62.0, 0.0)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true


func _new_stage() -> Node3D:
	if _stage != null:
		_stage.queue_free()
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)
	return _stage


func _body_centre(model: Node3D) -> Vector3:
	var body := model.find_child("Body", true, false) as MeshInstance3D
	if body != null and body.mesh != null:
		return body.transform * body.mesh.get_aabb().get_center()
	return Vector3.ZERO


func _label(text: String, at: Vector3, size: int = 40) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0016
	l.modulate = Color(0.08, 0.10, 0.16)
	l.outline_modulate = Color(1, 1, 1, 0.9)
	l.outline_size = 8
	_stage.add_child(l)
	l.position = at
	l.rotation.y = PI * 0.5


func _attachments_for(id: String, index: int) -> Array:
	var spec := WeaponSpec.resolve(id)
	var out: Array = []
	if spec == null:
		return out
	for a in spec.attachments:
		if not a.begins_with("finish_"):
			out.append(a)
	if spec.attachments.has(FINISHES[index % FINISHES.size()]):
		out.append(FINISHES[index % FINISHES.size()])
	return out


# --- data checks --------------------------------------------------------------------------------

func _data_checks() -> void:
	var chk := TestHarness
	var loaded := 0
	for id: Variant in Registry.ids("weapons"):
		var spec := WeaponSpec.resolve(id)
		if spec.model_path == "":
			continue
		var m := WeaponModel.create(spec)
		if m.has_model():
			loaded += 1
		else:
			chk.check(false, "GLB present for %s (%s)" % [spec.id, spec.model_path])
			m.free()
			continue
		var body := m.find_child("Body", true, false) as MeshInstance3D
		chk.check(body != null, "%s has a Body mesh" % spec.id)
		if body == null:
			m.free()
			continue
		var aabb := body.mesh.get_aabb()
		if spec.is_firearm():
			var real_muzzle := m.find_child("Model", true, false).find_child("Muzzle", true, false) as Node3D
			chk.check(real_muzzle != null and real_muzzle.position.z < -0.1 and real_muzzle.position.z < aabb.position.z + 0.3,
					"%s: Muzzle marker sits at the -Z end of the barrel (%s)" % [spec.id, str(real_muzzle.position) if real_muzzle != null else "missing"])
			chk.check(aabb.size.z > aabb.size.x * 2.0 and aabb.size.z >= aabb.size.y * 0.8, "%s: barrel axis is Z (size %s)" % [spec.id, str(aabb.size)])
			var has_finish := false
			for s in body.mesh.get_surface_count():
				var mat := body.mesh.surface_get_material(s)
				if mat != null and mat.resource_name == AttachmentSpec.FINISH_MATERIAL:
					has_finish = true
			chk.check(has_finish, "%s: Body uses %s" % [spec.id, AttachmentSpec.FINISH_MATERIAL])
			var missing_nodes: Array = []
			for a in spec.attachments:
				var def := Registry.get_def("attachments", a) as AttachmentSpec
				if def != null and def.node_name != "" and not m.get_attachment_node_names().has(def.node_name):
					missing_nodes.append(def.node_name)
			chk.check(missing_nodes.is_empty(), "%s: every compatible attachment has its mesh (missing %s)" % [spec.id, str(missing_nodes)])
			var unused: Array = []
			for node_name: String in m.get_attachment_node_names():
				var used := spec.builtin_nodes.has(node_name)
				for a in spec.attachments:
					var def := Registry.get_def("attachments", a) as AttachmentSpec
					if def != null and def.node_name == node_name:
						used = true
				if not used:
					unused.append(node_name)
			if not unused.is_empty():
				TestHarness.log_line("%s: attachment meshes without a spec entry: %s" % [spec.id, str(unused)])
		match spec.slot:
			"handgun":
				chk.check(aabb.size.z > 0.14 and aabb.size.z < 0.34, "%s: handgun length %.2f m" % [spec.id, aabb.size.z])
			"rifle", "sniper", "shotgun":
				chk.check(aabb.size.z > 0.7 and aabb.size.z < 1.35, "%s: long gun length %.2f m" % [spec.id, aabb.size.z])
		m.free()
	chk.check(loaded == 16, "all 16 weapon GLBs load (%d)" % loaded)

	# attachments + finish on one model
	var ar := WeaponModel.create("assault_rifle")
	var hidden_ok := true
	for node_name: String in ar.get_attachment_node_names():
		if (ar.find_child(node_name, true, false) as Node3D).visible:
			hidden_ok = false
	chk.check(hidden_ok and ar.get_attachment_node_names().size() == 5, "attachment meshes are hidden by default")
	var plain_muzzle_z := ar.muzzle.position.z
	ar.set_attachments(["ext_mag", "suppressor", "finish_teal", "flashlight"])
	chk.check(ar.muzzle.name == "Muzzle_Suppressed" and ar.muzzle.position.z < plain_muzzle_z - 0.08,
			"with a suppressor the muzzle marker is the suppressor tip (z %.3f -> %.3f)" % [plain_muzzle_z, ar.muzzle.position.z])
	var lens := ar.find_child("Flashlight", true, false) as Node3D
	chk.check(lens != null and ar.light != null and ar.light.position.distance_to(lens.position) < 0.05,
			"weapon light sits at the Flashlight lens marker (%s)" % (str(ar.light.position.snapped(Vector3.ONE * 0.001)) if ar.light != null else "-"))
	chk.check((ar.find_child("Att_ExtMag", true, false) as Node3D).visible and not (ar.find_child("Mag", true, false) as Node3D).visible,
			"extended magazine shown, standard magazine hidden")
	chk.check((ar.find_child("Att_Suppressor", true, false) as Node3D).visible and not (ar.find_child("Att_Scope", true, false) as Node3D).visible,
			"only installed attachments are visible")
	var body_ar := ar.find_child("Body", true, false) as MeshInstance3D
	var tinted := false
	for s in body_ar.mesh.get_surface_count():
		var o := body_ar.get_surface_override_material(s) as BaseMaterial3D
		if o != null and o.albedo_color.is_equal_approx(Color(0.10, 0.62, 0.60)):
			tinted = true
	chk.check(tinted, "finish tint applied to M_Weapon_Finish as a surface override")
	chk.check(ar.has_light() and not ar.light.visible, "flashlight attachment creates a SpotLight3D (off)")
	ar.set_attachments([])
	var clean := (ar.find_child("Mag", true, false) as Node3D).visible and not ar.has_light()
	for s in body_ar.mesh.get_surface_count():
		if body_ar.get_surface_override_material(s) != null:
			clean = false
	chk.check(clean, "removing attachments restores the magazine, the factory finish and removes the light")
	chk.check(ar.muzzle.name == "Muzzle" and is_equal_approx(ar.muzzle.position.z, plain_muzzle_z), "... and the muzzle marker is the bare muzzle again")
	ar.free()
	var sn := WeaponModel.create("sniper_rifle")
	chk.check((sn.find_child("Att_Scope", true, false) as Node3D).visible, "sniper rifle always shows its scope")
	sn.free()
	var rl := WeaponModel.create("rocket_launcher")
	rl.set_mag_loaded(false)
	chk.check(not (rl.find_child("Mag", true, false) as Node3D).visible, "empty rocket launcher hides the loaded rocket")
	rl.free()


# --- sheets -------------------------------------------------------------------------------------

func _sheet(shot_name: String, with_attachments: bool) -> void:
	_new_stage()
	var index := 0
	for r in GRID.size():
		for c in 3:
			var cell := Vector3(0.0, (float(GRID.size() - 1) * 0.5 - float(r)) * ROW_STEP, (1.0 - float(c)) * COL_STEP)
			var entry: String = GRID[r][c]
			if entry == "":
				# 1 m ruler
				var ruler := MeshInstance3D.new()
				var bar := BoxMesh.new()
				bar.size = Vector3(0.01, 0.02, 1.0)
				ruler.mesh = bar
				_stage.add_child(ruler)
				ruler.position = cell
				_label("1 m", cell + Vector3(0.05, -0.1, 0.25))
				continue
			var ids := entry.split("+")
			for k in ids.size():
				var id: String = ids[k]
				var offset := Vector3(0.0, 0.0, (float(k) - float(ids.size() - 1) * 0.5) * -0.5)
				var node: Node3D = null
				if WeaponSpec.resolve(id) != null:
					node = WeaponModel.create(id, _attachments_for(id, index) if with_attachments else [])
				else:
					var scene := WeaponModel.load_scene("%s/%s.glb" % [WeaponSpec.MODEL_DIR, id])
					if scene != null:
						node = scene.instantiate() as Node3D
				if node == null:
					continue
				_stage.add_child(node)
				node.position = cell + offset - _body_centre(node)
				_label(id, cell + offset + Vector3(0.05, -0.19, 0.3), 34)
				index += 1
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = float(GRID.size()) * ROW_STEP + 0.25
	_cam.near = 0.05
	_cam.far = 50.0
	_cam.look_at_from_position(Vector3(6.0, 0.0, 0.0), Vector3.ZERO, Vector3.UP)
	await TestHarness.wait_frames(5)
	await TestHarness.shot(shot_name)


func _perspective() -> void:
	_new_stage()
	var picks := ["pistol", "smg", "assault_rifle", "sniper_rifle", "rocket_launcher", "pump_shotgun"]
	for i in picks.size():
		var id: String = picks[i]
		var m := WeaponModel.create(id, _attachments_for(id, i + 2))
		_stage.add_child(m)
		m.position = Vector3(0.0, 0.3 - float(i / 3) * 0.6, 1.25 - float(i % 3) * 1.25) - _body_centre(m)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 36.0
	_cam.look_at_from_position(Vector3(3.3, 1.1, 1.9), Vector3(0.0, 0.0, -0.15), Vector3.UP)
	await TestHarness.wait_frames(5)
	await TestHarness.shot("wpn_shots_persp")


# --- weapon in the hand of the shared humanoid ----------------------------------------------------

func _spawn_humanoid(at: Vector3) -> FakeHolder:
	var scene := load(HUMANOID) as PackedScene
	if scene == null:
		return null
	var holder := FakeHolder.new()
	_stage.add_child(holder)
	holder.position = at
	var visual := FakeVisual.new()
	holder.add_child(visual)
	var human := scene.instantiate() as Node3D
	visual.add_child(human)
	var skels := human.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return null
	visual.skeleton = skels[0] as Skeleton3D
	holder.visual = visual
	return holder


func _hand() -> void:
	if not ResourceLoader.exists(HUMANOID):
		TestHarness.log_line("humanoid.glb not available: hand shot skipped")
		return
	_new_stage()
	var chk := TestHarness
	# 1) rest pose: canonical grip, and the two ways of computing it agree
	var t_holder := _spawn_humanoid(Vector3(-1.5, 0.0, 0.0))
	if t_holder == null:
		chk.check(false, "humanoid.glb has a Skeleton3D")
		return
	var rifle := WeaponModel.create("assault_rifle", ["scope", "grip"])
	chk.check(rifle.attach_to_holder(t_holder) and rifle.attached_to_hand, "weapon attaches to visual.get_bone_attachment('Hand_R')")
	await TestHarness.wait_frames(2)
	var socket := (t_holder.visual as FakeVisual).get_bone_attachment("Hand_R")
	var with_animator := rifle.compute_hand_transform(t_holder.visual, socket)
	var keep_script: Script = WeaponModel._animator_script
	WeaponModel._animator_checked = true
	WeaponModel._animator_script = null
	var fallback := rifle.compute_hand_transform(t_holder.visual, socket)
	WeaponModel._animator_script = keep_script
	chk.check(with_animator.is_equal_approx(fallback) or keep_script == null,
			"hand transform: animator grip and built-in rest-pose fallback agree")
	var barrel := -rifle.global_basis.z.normalized()
	var top := rifle.global_basis.y.normalized()
	chk.check(barrel.dot(Vector3.RIGHT) > 0.95 and top.dot(Vector3.FORWARD) > 0.95,
			"T-pose: barrel along the right arm (+X), top of the weapon towards the thumb (-Z): barrel %s top %s" % [str(barrel.snapped(Vector3.ONE * 0.01)), str(top.snapped(Vector3.ONE * 0.01))])
	_label("rest pose", Vector3(-1.5, 2.05, 0.0), 44)

	# 2) aim poses through the real animator (soft dependency)
	var poses := [["pistol", "pistol"], ["assault_rifle", "rifle"], ["rocket_launcher", "rpg"], ["bat", "melee"]]
	var aimed: Array = []
	if ResourceLoader.exists(ANIMATOR):
		var anim_script := load(ANIMATOR) as Script
		for i in poses.size():
			var holder := _spawn_humanoid(Vector3(-0.3 + float(i) * 1.15, 0.0, 0.0))
			if holder == null or anim_script == null:
				continue
			var anim := anim_script.new() as Node
			anim.name = "Animator"
			holder.add_child(anim)
			anim.call("setup", (holder.visual as FakeVisual).skeleton)
			anim.set("weapon_pose", poses[i][1])
			if anim.has_method("set_state"):
				anim.call("set_state", "aim" if poses[i][1] != "melee" else "idle", 0.0)
			anim.set("aim_weight", 1.0 if poses[i][1] != "melee" else 0.0)
			var model := WeaponModel.create(poses[i][0])
			model.attach_to_holder(holder)
			aimed.append([poses[i][0], model])
			_label(str(poses[i][1]), Vector3(-0.3 + float(i) * 1.15, 2.05, 0.0), 44)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 40.0
	_cam.look_at_from_position(Vector3(4.6, 1.75, -4.4), Vector3(0.75, 1.05, 0.0), Vector3.UP)
	await TestHarness.wait_frames(24)
	for entry: Array in aimed:
		var model := entry[1] as WeaponModel
		if entry[0] == "bat":
			continue
		var dir := -model.global_basis.z.normalized()
		var up := model.global_basis.y.normalized()
		# informational: the pose itself belongs to the character module
		TestHarness.log_line("aim pose %s: barrel %s (want about (0, 0, -1)), weapon up %s (want about (0, 1, 0)) -> %s" % [
				str(entry[0]), str(dir.snapped(Vector3.ONE * 0.01)), str(up.snapped(Vector3.ONE * 0.01)),
				"OK" if (dir.dot(Vector3.FORWARD) > 0.9 and up.dot(Vector3.UP) > 0.85) else "CHECK THE PNG"])
	await TestHarness.shot("wpn_shots_hand")
	# close side view of the rifle aim pose only (the camera looks along -X: barrel must point right)
	for child in _stage.get_children():
		if child is FakeHolder:
			(child as Node3D).visible = absf((child as Node3D).position.x - 0.85) < 0.01
	_cam.fov = 30.0
	_cam.look_at_from_position(Vector3(4.6, 1.3, -0.25), Vector3(0.85, 1.15, -0.25), Vector3.UP)
	await TestHarness.wait_frames(3)
	await TestHarness.shot("wpn_shots_hand_side")


# --- pickups ------------------------------------------------------------------------------------

func _pickups() -> void:
	var ps := Game.get_system("pickups")
	if ps == null:
		TestHarness.log_line("pickups system missing: pickup shot skipped")
		return
	_new_stage()
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16.0, 8.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.44, 0.47)
	ground.material_override = gm
	_stage.add_child(ground)
	var items := [["weapon", "pistol", 24], ["weapon", "assault_rifle", 60], ["weapon", "sniper_rifle", 10],
			["weapon", "grenade", 2], ["ammo", "rifle", 60], ["health", "", 50], ["armor", "", 50],
			["cash", "", 120], ["cash", "", 800], ["parachute", "", 1], ["scuba", "", 1]]
	var made := 0
	for i in items.size():
		var at := Vector3((float(i % 6) - 2.5) * 1.35, 0.0, -1.0 if i < 6 else 1.0)
		var p: Node3D = ps.call("spawn_pickup", items[i][0], items[i][1], items[i][2], at, {"snap": false})
		if p != null:
			made += 1
			TestHarness.check(p.get("has_model") == true, "pickup %s/%s shows a Blender model" % [str(items[i][0]), str(items[i][1])])
	TestHarness.check(made == items.size(), "all pickup kinds spawned (%d)" % made)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 42.0
	_cam.look_at_from_position(Vector3(0.6, 3.2, 6.2), Vector3(0.0, 0.5, 0.0), Vector3.UP)
	await TestHarness.wait_frames(8)
	await TestHarness.shot("wpn_shots_pickups")
	ps.call("clear_dropped")
