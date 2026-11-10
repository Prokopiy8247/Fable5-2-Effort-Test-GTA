extends Node
## plr_anim_shots - windowed pose sheet of the HumanoidAnimator on the REAL character model.
##
##   tools\godot.ps1 -Mode window -Frames 420 -UserArgs '--test=plr_anim_shots','--disable=traffic,peds,police'
##   optional: '--shots=run,sprint'   only these shots        '--set=extra'   the second sheet
##
## Every shot shows the SAME pose twice on the test arena, seen by the test's own camera:
## left = profile (the character faces screen-right), right = three-quarter front view.
## The poses are frozen (animator.auto_process = false), so a shot is reproducible.
## PNGs: qa/screenshots/plr_anim_<name>.png. The log gets one "POSE" line per shot with numbers
## (foot heights, knee direction, hand positions) so that broken poses can be spotted without eyes.
## Headless runs only print the numbers.

const Arena := preload("res://gta/tests/plr_arena.gd")
const HUMANOID := "res://gta/scenes/characters/humanoid.tscn"
const WEAPON_DIR := "res://gta/generated/models/weapons/"

const MAIN: Array = [
	{"name": "idle", "state": "idle"},
	{"name": "walk", "state": "locomotion", "speed": 1.9, "phase": 0.03},
	{"name": "run", "state": "locomotion", "speed": 4.4, "phase": 0.03},
	{"name": "sprint", "state": "locomotion", "speed": 7.0, "phase": 0.55},
	{"name": "crouch", "state": "crouch"},
	{"name": "jump", "state": "jump", "vspeed": 4.0, "lift": 0.7},
	{"name": "aim_pistol", "state": "idle", "weapon": "pistol", "pose": "pistol", "aim": 1.0},
	{"name": "aim_rifle", "state": "idle", "weapon": "assault_rifle", "pose": "rifle", "aim": 1.0},
	{"name": "swim", "state": "swim", "speed": 2.1, "advance": 0.1, "water": true, "high": true},
	{"name": "seated_car", "state": "seated_car", "lift": 0.45, "wheel": true},
	{"name": "dead", "state": "dead", "high": true},
]
const EXTRA: Array = [
	{"name": "run_b", "state": "locomotion", "speed": 4.4, "phase": 0.30},
	{"name": "sprint_b", "state": "locomotion", "speed": 7.0, "phase": 0.80},
	{"name": "crouch_walk", "state": "crouch", "speed": 2.0, "phase": 0.05},
	{"name": "fall", "state": "fall", "vspeed": -9.0, "lift": 0.7},
	{"name": "tread", "state": "tread", "water": true},
	{"name": "dive", "state": "dive", "speed": 2.0, "advance": 0.2, "lift": 0.4, "high": true},
	{"name": "seated_bike", "state": "seated_bike", "lift": 0.8, "bar": true},
	{"name": "carry_rifle", "state": "locomotion", "speed": 4.4, "phase": 0.03, "weapon": "assault_rifle", "pose": "rifle"},
	{"name": "aim_rpg", "state": "idle", "weapon": "rocket_launcher", "pose": "rpg", "aim": 1.0},
	{"name": "aim_up", "state": "idle", "weapon": "pistol", "pose": "pistol", "aim": 1.0, "pitch": 0.7},
	{"name": "aim_down_rifle", "state": "idle", "weapon": "assault_rifle", "pose": "rifle", "aim": 1.0, "pitch": -0.6},
	{"name": "melee_guard", "state": "idle", "weapon": "bat", "pose": "melee", "aim": 1.0},
	{"name": "punch", "state": "idle", "pose": "none", "aim": 1.0, "action": "punch_r", "action_t": 0.12},
	{"name": "reload", "state": "idle", "weapon": "pistol", "pose": "pistol", "aim": 1.0, "action": "reload", "action_t": 0.5},
	{"name": "throw", "state": "idle", "pose": "throw", "aim": 1.0, "action": "throw", "action_t": 0.2},
	{"name": "surrender", "state": "surrender"},
	{"name": "cower", "state": "cower"},
	{"name": "land", "state": "idle", "then": "land", "advance": 0.06},
	{"name": "strafe", "state": "locomotion", "speed": 2.6, "phase": 0.05, "dir": Vector2(1.0, 0.0), "weapon": "pistol", "pose": "pistol", "aim": 1.0},
]

var arena: Arena = null
var cam: Camera3D = null
var dummies: Array = []          # {"root": Node3D, "visual": Node3D, "anim": HumanoidAnimator, "skel": Skeleton3D}
var water: MeshInstance3D = null
var T: Node = null
var weapon_cache: Dictionary = {}
var missing_weapons: PackedStringArray = []


func _ready() -> void:
	T = TestHarness
	await _run()


func _run() -> void:
	if not ResourceLoader.exists(HUMANOID):
		T.check(false, "humanoid.tscn exists")
		T.finish(false, "no character model")
		return
	arena = Arena.new()
	Game.main.add_child(arena)
	arena.ensure_light()
	UI.set_hud_visible(false)
	if Game.player != null and Game.player.has_method("teleport"):
		Game.player.call("teleport", arena.at(Vector3(0.0, 0.05, 55.0)), 0.0)
		Game.player.call("set_control_enabled", false)
	cam = Camera3D.new()
	cam.name = "ShotCamera"
	cam.fov = 36.0
	cam.near = 0.1
	cam.far = 500.0
	arena.add_child(cam)
	_build_dummies()
	_build_water()
	await T.wait_frames(6)
	cam.make_current()
	if not T.is_headless():
		await T.wait_seconds(1.6)        # let the boot overlay of the UI fade away

	var which: Array = MAIN
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a == "--set=extra":
			which = EXTRA
		elif a == "--set=all":
			which = MAIN + EXTRA
		elif a.begins_with("--shots="):
			only = a.substr(8).split(",", false)
			which = MAIN + EXTRA
	var done := 0
	for shot: Dictionary in which:
		if not only.is_empty() and not only.has(str(shot["name"])):
			continue
		await _shoot(shot)
		done += 1
	T.check(done > 0, "%d pose shots taken" % done)
	_skate_report()
	T.check(dummies.size() == 2 and (dummies[0]["anim"] as HumanoidAnimator).is_ready(), "animator bound to the real humanoid skeleton")
	if not missing_weapons.is_empty():
		T.log_line("weapon models missing for the shots: " + ", ".join(missing_weapons))
	T.finish(true, "animation pose sheet")


func _build_dummies() -> void:
	var ps := load(HUMANOID) as PackedScene
	# left: profile, facing +X (screen right).  right: three-quarter front.
	var spots := [Vector3(-1.25, 0.0, 0.0), Vector3(1.25, 0.0, 0.0)]
	var yaws := [-PI * 0.5, PI + 0.55]
	for i in 2:
		var root := Node3D.new()
		root.name = "Dummy%d" % i
		arena.add_child(root)
		root.position = spots[i]
		root.rotation.y = yaws[i]
		var visual := ps.instantiate() as Node3D
		root.add_child(visual)
		var skel: Skeleton3D = visual.call("get_skeleton") as Skeleton3D
		var anim := HumanoidAnimator.new()
		anim.name = "Animator"
		anim.auto_process = false
		root.add_child(anim)
		anim.setup(skel)
		dummies.append({"root": root, "visual": visual, "anim": anim, "skel": skel, "spot": spots[i], "props": []})


func _build_water() -> void:
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9.0, 5.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.55, 0.75, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.material = mat
	water.mesh = pm
	water.visible = false
	arena.add_child(water)


func _shoot(shot: Dictionary) -> void:
	var lift := float(shot.get("lift", 0.0))
	for d: Dictionary in dummies:
		var root: Node3D = d["root"]
		var anim: HumanoidAnimator = d["anim"]
		for p: Node in d["props"]:
			p.queue_free()
		(d["props"] as Array).clear()
		root.position = (d["spot"] as Vector3) + Vector3(0.0, lift, 0.0)
		anim.stop_action()
		anim.state = "idle"
		anim.speed = float(shot.get("speed", 0.0))
		anim.move_dir_local = shot.get("dir", Vector2(0.0, 1.0))
		anim.vertical_speed = float(shot.get("vspeed", 0.0))
		anim.weapon_pose = str(shot.get("pose", "none"))
		anim.aim_weight = float(shot.get("aim", 0.0))
		anim.aim_pitch = float(shot.get("pitch", 0.0))
		anim.lean = float(shot.get("lean", 0.0))
		anim.steer = float(shot.get("steer", 0.0))
		anim.accel_lean = 0.0
		anim.turn_rate = 0.0
		anim.set_state(str(shot["state"]), 0.0)
		anim.snap()
		anim.phase = float(shot.get("phase", 0.0))
		anim.advance(0.0)
		if shot.has("action"):
			anim.play_action(str(shot["action"]))
			var left := float(shot.get("action_t", 0.1))
			while left > 0.0001:
				var step := minf(left, 0.2)
				anim.advance(step)
				left -= step
		if shot.has("then"):
			anim.set_state(str(shot["then"]), 0.0)
		var adv := float(shot.get("advance", 0.0))
		while adv > 0.0001:
			var step2 := minf(adv, 0.2)
			anim.advance(step2)
			adv -= step2
		if shot.has("weapon"):
			_give_weapon(d, str(shot["weapon"]))
		if bool(shot.get("wheel", false)):
			_add_wheel(d)
		if bool(shot.get("bar", false)):
			_add_bar(d)
	water.visible = bool(shot.get("water", false))
	if water.visible:
		water.position = Vector3(0.0, lift + (dummies[0]["anim"] as HumanoidAnimator).swim_depth, 0.0)
	if bool(shot.get("high", false)):
		cam.position = Vector3(0.0, 2.6 + lift, 4.9)
		cam.look_at(arena.at(Vector3(0.0, 0.5 + lift, 0.0)))
	else:
		cam.position = Vector3(0.0, 1.2 + lift * 0.7, 4.7)
		cam.look_at(arena.at(Vector3(0.0, 0.95 + lift * 0.85, 0.0)))
	_report(shot)
	await T.wait_frames(3)
	await T.shot("plr_anim_" + str(shot["name"]))


func _give_weapon(d: Dictionary, id: String) -> void:
	var path := WEAPON_DIR + id + ".glb"
	if not ResourceLoader.exists(path):
		if not missing_weapons.has(id):
			missing_weapons.append(id)
		return
	if not weapon_cache.has(id):
		weapon_cache[id] = load(path)
	var ps := weapon_cache[id] as PackedScene
	if ps == null:
		return
	var visual: Node3D = d["visual"]
	var hand := visual.call("get_bone_attachment", "Hand_R") as Node3D
	if hand == null:
		return
	var w := ps.instantiate() as Node3D
	hand.add_child(w)
	w.transform = HumanoidAnimator.get_grip_transform(d["skel"] as Skeleton3D, "Hand_R")
	(d["props"] as Array).append(w)


func _add_wheel(d: Dictionary) -> void:
	var anim: HumanoidAnimator = d["anim"]
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = anim.wheel_radius - 0.02
	tm.outer_radius = anim.wheel_radius + 0.012
	mi.mesh = tm
	var x := Vector3.RIGHT
	var y := Vector3(0.0, 0.375, 0.927)
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), anim.wheel_pos)
	(d["visual"] as Node3D).add_child(mi)
	(d["props"] as Array).append(mi)
	# a seat cushion for context
	var seat := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.12, 0.5)
	seat.mesh = bm
	seat.position = Vector3(0.0, -0.16, 0.05)
	(d["visual"] as Node3D).add_child(seat)
	(d["props"] as Array).append(seat)


func _add_bar(d: Dictionary) -> void:
	var anim: HumanoidAnimator = d["anim"]
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.018
	cm.height = anim.bar_half_width * 2.0 + 0.1
	mi.mesh = cm
	mi.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), anim.bar_pos)
	(d["visual"] as Node3D).add_child(mi)
	(d["props"] as Array).append(mi)
	var seat := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.28, 0.1, 0.6)
	seat.mesh = bm
	seat.position = Vector3(0.0, -0.15, 0.1)
	(d["visual"] as Node3D).add_child(seat)
	(d["props"] as Array).append(seat)


## Numbers for the log: model-space joint positions of the first dummy.
func _report(shot: Dictionary) -> void:
	var d: Dictionary = dummies[0]
	var skel: Skeleton3D = d["skel"]
	var p := func(bone: String) -> Vector3:
		return skel.get_bone_global_pose(skel.find_bone(bone)).origin
	var knee_fwd := func(side: String) -> float:
		# > 0: the knee is in front (-Z) of the hip-ankle line
		var hip: Vector3 = p.call("UpperLeg_" + side)
		var knee: Vector3 = p.call("LowerLeg_" + side)
		var ankle: Vector3 = p.call("Foot_" + side)
		var mid := hip.lerp(ankle, 0.5)
		var fwd := skel.get_bone_global_pose(skel.find_bone("Hips")).basis * Vector3(0.0, 0.0, -1.0)
		return (knee - mid).dot(fwd.normalized())
	var elbow_back := func(side: String) -> float:
		# > 0: the elbow is behind / below the shoulder-wrist line (never "hyper-extended" forward-up)
		var sh: Vector3 = p.call("UpperArm_" + side)
		var el: Vector3 = p.call("LowerArm_" + side)
		var wr: Vector3 = p.call("Hand_" + side)
		var mid := sh.lerp(wr, 0.5)
		return (el - mid).dot(Vector3(0.0, -0.6, 0.8).normalized())
	var fl: Vector3 = p.call("Foot_L")
	var fr: Vector3 = p.call("Foot_R")
	var hl: Vector3 = p.call("Hand_L")
	var hr: Vector3 = p.call("Hand_R")
	var head: Vector3 = p.call("Head")
	var hips: Vector3 = p.call("Hips")
	print("POSE %-14s hips=(%.2f,%.2f,%.2f) head=(%.2f,%.2f,%.2f) footL=(%.2f,%.2f,%.2f) footR=(%.2f,%.2f,%.2f) kneeFwd L=%.2f R=%.2f handL=(%.2f,%.2f,%.2f) handR=(%.2f,%.2f,%.2f) elbowBack L=%.2f R=%.2f" % [
			str(shot["name"]), hips.x, hips.y, hips.z, head.x, head.y, head.z, fl.x, fl.y, fl.z, fr.x, fr.y, fr.z,
			float(knee_fwd.call("L")), float(knee_fwd.call("R")), hl.x, hl.y, hl.z, hr.x, hr.y, hr.z,
			float(elbow_back.call("L")), float(elbow_back.call("R"))])


## Foot skating: how far a planted foot slides over the ground, relative to the distance the body
## travels meanwhile (0 = perfectly planted). Also the cost of one evaluation.
func _skate_report() -> void:
	var d: Dictionary = dummies[0]
	var anim: HumanoidAnimator = d["anim"]
	var skel: Skeleton3D = d["skel"]
	var foot := skel.find_bone("Foot_L")
	var ankle := skel.get_bone_global_rest(foot).origin.y
	(d["root"] as Node3D).position = d["spot"]
	for cfg: Array in [[1.2, "locomotion"], [1.9, "locomotion"], [2.6, "locomotion"], [4.4, "locomotion"], [7.0, "locomotion"], [2.1, "crouch"]]:
		var speed: float = cfg[0]
		anim.stop_action()
		anim.weapon_pose = "none"
		anim.aim_weight = 0.0
		anim.aim_pitch = 0.0
		anim.move_dir_local = Vector2(0.0, 1.0)
		anim.speed = speed
		anim.set_state("idle", 0.0)
		anim.set_state(str(cfg[1]), 0.0)
		anim.snap()
		anim.phase = 0.0
		anim.advance(0.0)
		var dt := 1.0 / 120.0
		var t := 0.0
		var slip := 0.0
		var stance_dist := 0.0
		var prev := INF
		var hips_min := 9.0
		var hips_max := 0.0
		for i in 480:
			anim.advance(dt)
			t += dt
			var p := skel.get_bone_global_pose(foot).origin
			var world_z := p.z - speed * t
			var hy := skel.get_bone_global_pose(skel.find_bone("Hips")).origin.y
			hips_min = minf(hips_min, hy)
			hips_max = maxf(hips_max, hy)
			if p.y < ankle + 0.012:
				if prev != INF:
					slip += absf(world_z - prev)
					stance_dist += speed * dt
				prev = world_z
			else:
				prev = INF
		var ratio := slip / maxf(stance_dist, 0.001)
		print("SKATE %s %.1f m/s: planted foot slides %.0f %% of the distance, pelvis bob %.3f m" % [str(cfg[1]), speed, ratio * 100.0, hips_max - hips_min])
		if str(cfg[1]) == "locomotion" and speed >= 1.9:
			T.check(ratio < 0.22, "feet stay planted at %.1f m/s (slide %.0f %%)" % [speed, ratio * 100.0])
	# cost of one evaluation (NPC budget: well under 0.05 ms at a reduced rate)
	anim.speed = 4.4
	anim.set_state("locomotion", 0.0)
	var n := 2000
	var t0 := Time.get_ticks_usec()
	for i in n:
		anim.advance(1.0 / 60.0)
	var us := float(Time.get_ticks_usec() - t0) / float(n)
	print("ANIM_COST one evaluation = %.1f us (%.4f ms); at update_rate_hz 15 that is %.4f ms per 60 Hz frame" % [us, us / 1000.0, us / 1000.0 * 0.25])
	T.check(us < 200.0, "one animator evaluation costs %.0f us" % us)
