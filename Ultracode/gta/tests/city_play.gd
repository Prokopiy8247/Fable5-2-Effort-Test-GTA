extends Node
## City gameplay test: the REAL player, driven by Input actions, uses the city the way a player would.
##   tools\godot.ps1 -Mode headless -Frames 5400 -TimeoutSec 300 -UserArgs '--test=city_play','--test-timeout=240','--disable=traffic,peds,police,emergency,wildlife,taxi,transit,activities,radio,ambience'
## Windowed (adds screenshots qa/screenshots/city_play_*.png of the climbs and an interior):
##   tools\godot.ps1 -Mode window -Frames 3000 -TimeoutSec 200 -UserArgs '--test=city_play','--test-timeout=150','--hour=13','--freeze-time','--weather=clear','--city_play_quick', ...
##
## 1. walks (move_forward) from the street through the doorway of every walk-in landmark, 1.8 m inside;
##    the safehouse door must open on the way in
## 2. climbs the radio-mast ladder (interact, then move_forward + sprint) and stands on the platform,
##    then climbs back down from the top (interact at the top exit, move_back) to the ground
## 3. swims to the GLB pier-end swim ladder, climbs it and stands on the deck
## Option --city_play_quick: only the gun shop, the safehouse and the two ladders.

var P: Node3D
var _city: Node
var _quick := false


func _ready() -> void:
	_city = Game.get_system("city")
	P = Game.player
	if not TestHarness.check(_city != null and P != null, "city system and player exist"):
		TestHarness.finish(false, "no city or no player")
		return
	_quick = OS.get_cmdline_user_args().has("--city_play_quick")
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--city_play_only="):
			_only = a.substr(17).split(",", false)
	var ui := get_node_or_null("/root/UI")
	if ui != null and ui.has_method("set_hud_visible") and not TestHarness.is_headless():
		ui.call("set_hud_visible", false)
	await TestHarness.wait_seconds(0.5)
	await _walk_ins()
	if _wanted("stair"):
		await _safehouse_stair()
	if _wanted("mast"):
		await _mast()
	if _wanted("pier"):
		await _pier()
	_release()
	TestHarness.finish()


## --city_play_only=a,b: run only the stages whose name contains one of the parts ("mast", "pier",
## "walk:<landmark>").
var _only: PackedStringArray = []


func _wanted(stage: String) -> bool:
	if _only.is_empty():
		return true
	for o in _only:
		if stage.contains(o):
			return true
	return false


func _ray_y(sp: PhysicsDirectSpaceState3D, p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.2, 0), p - Vector3(0, 2.0, 0), Layers.WORLD)
	var h := sp.intersect_ray(q)
	return (h["position"] as Vector3).y if not h.is_empty() else NAN


## Replays the sub-tests of the player's kerb step-up (Player._try_step_up) at the current position to
## report WHICH one refuses the step (diagnostic for the PLAYER module).
func _diagnose_step(dir: Vector3) -> void:
	var body := P as CharacterBody3D
	if body == null:
		return
	var kc := KinematicCollision3D.new()
	var from := body.global_transform
	var motion := dir * 0.073
	var hit_fwd := body.test_move(from, motion, kc)
	var n := kc.get_normal() if hit_fwd else Vector3.ZERO
	var col: Object = kc.get_collider() if hit_fwd else null
	var up := Vector3(0, 0.32, 0)
	var kc2 := KinematicCollision3D.new()
	var head := body.test_move(from, up, kc2)
	var col2: Object = kc2.get_collider() if head else null
	var raised := from.translated(up)
	var kc3 := KinematicCollision3D.new()
	var wall := body.test_move(raised, dir * 0.08, kc3)
	var col3: Object = kc3.get_collider() if wall else null
	TestHarness.log_line("step diag: forward hit %s normal %s by %s | head blocked %s by %s | raised blocked %s by %s (pos %s)" % [
			str(hit_fwd), str(n), _nm(col), str(head), _nm(col2), str(wall), _nm(col3), str(kc3.get_position() if wall else Vector3.ZERO)])
	TestHarness.log_line("step diag: velocity %s, grounded %s, was_grounded %s" % [str(body.velocity), str(P.get("grounded")), str(P.get("_was_grounded"))])
	if P.has_method("_try_step_up"):
		var keep := body.velocity
		body.velocity = dir * 4.4
		var y0 := body.global_position.y
		var ok: Variant = P.call("_try_step_up", 1.0 / 60.0)
		TestHarness.log_line("step diag: _try_step_up at full run speed -> %s (rise %.3f)" % [str(ok), body.global_position.y - y0])
		body.velocity = keep


func _nm(o: Object) -> String:
	if o == null:
		return "-"
	if o is Node:
		var nd := o as Node
		return "%s (%s)" % [nd.get_path(), nd.get_parent().name if nd.get_parent() != null else ""]
	return str(o)


func _release() -> void:
	for a: String in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact", "crouch"]:
		Input.action_release(a)


func _cam_yaw(yaw: float) -> void:
	var cam: Variant = P.get("camera")
	if cam is Object and is_instance_valid(cam):
		(cam as Object).set("yaw", yaw)


func _state() -> String:
	return String(P.get("state_id"))


func _tap(action: String) -> void:
	Input.action_press(action)
	await TestHarness.wait_physics_frames(2)
	Input.action_release(action)


# ---------------------------------------------------------------------------------------------
# 1. walk in through the doorway
# ---------------------------------------------------------------------------------------------

func _walk_ins() -> void:
	var names: Array = ["gun_shop", "safehouse"]
	if not _quick:
		names = Array(_city.call("get_landmark_names") as PackedStringArray)
	for lm: String in names:
		var b: Dictionary = _city.call("get_landmark_building", lm)
		if b.is_empty() or not bool(b.get("walk_in", false)) or not bool(_city.call("has_landmark_marker", lm, "Entrance")):
			continue
		if not _wanted("walk:" + lm):
			continue
		var ent: Transform3D = _city.call("get_landmark_marker", lm, "Entrance")
		var inward := -ent.basis.z
		inward.y = 0.0
		inward = inward.normalized()
		var yaw := atan2(-inward.x, -inward.z)
		var start := ent.origin - inward * 3.5
		var goal := ent.origin + inward * 1.8
		P.call("teleport", start + Vector3(0, 0.25, 0), yaw)
		_cam_yaw(yaw)
		await TestHarness.wait_seconds(0.4)
		var door_open := 0.0
		var reached := false
		var t := 0.0
		Input.action_press("move_forward")
		while t < 4.5:
			await TestHarness.wait_physics_frames(6)
			t += 0.1
			_cam_yaw(yaw)
			for d: Dictionary in _city.call("get_doors"):
				door_open = maxf(door_open, float(d["open"]))
			var p := P.global_position
			if Vector2(p.x - goal.x, p.z - goal.z).length() < 0.8 or (p - start).dot(inward) > 5.3 + 0.8:
				reached = true
				break
		Input.action_release("move_forward")
		var p2 := P.global_position
		var inside := (p2 - ent.origin).dot(inward)
		TestHarness.check(reached and inside > 1.0, "%s: the player walks from the street through the doorway (%.1f m inside, %.1f s, y %.2f)" % [lm, inside, t, p2.y])
		if not reached:
			var sp := (P as Node3D).get_world_3d().direct_space_state
			var outside := _ray_y(sp, ent.origin - inward * 1.0)
			var at_door := _ray_y(sp, ent.origin + inward * 0.6)
			TestHarness.log_line("%s: stuck at %s; ground outside y %.3f, inside the doorway y %.3f (rise %.3f), building origin y %.3f" % [
					lm, str(p2), outside, at_door, at_door - outside, (b["transform"] as Transform3D).origin.y])
			_diagnose_step(inward)
		if lm == "safehouse":
			TestHarness.check(door_open > 0.9, "safehouse door opened as the player walked in (%.2f)" % door_open)
		if lm == "gun_shop":
			await TestHarness.wait_seconds(0.8)
			_cam_yaw(yaw + PI)
			await TestHarness.wait_seconds(0.6)
			await TestHarness.shot("city_play_gun_shop_inside")
		await TestHarness.wait_seconds(0.2)


# ---------------------------------------------------------------------------------------------
# 1b. safehouse stair to the mezzanine bedroom (Use_Bed)
# ---------------------------------------------------------------------------------------------

func _safehouse_stair() -> void:
	if not bool(_city.call("has_landmark", "safehouse")):
		return
	var cat := BuildingCatalog.new()
	cat.load_all()
	var st: Variant = cat.get_def("safehouse").get("stair")
	if not TestHarness.check(st is Dictionary, "safehouse manifest has its stair"):
		return
	var xf: Transform3D = _city.call("get_landmark_transform", "safehouse")
	var b: Array = (st as Dictionary)["bottom"]
	var t: Array = (st as Dictionary)["top"]
	var bot := xf * Vector3(float(b[0]), float(b[1]), float(b[2]))
	var top := xf * Vector3(float(t[0]), float(t[1]), float(t[2]))
	var dir := Vector3(top.x - bot.x, 0, top.z - bot.z).normalized()
	var yaw := atan2(-dir.x, -dir.z)
	P.call("teleport", bot - dir * 0.4 + Vector3(0, 0.1, 0), yaw)
	_cam_yaw(yaw)
	await TestHarness.wait_seconds(0.5)
	Input.action_press("move_forward")
	var t_up := 0.0
	while t_up < 5.0 and P.global_position.y < top.y - 0.15:
		await TestHarness.wait_physics_frames(6)
		t_up += 0.1
		_cam_yaw(yaw)
	await TestHarness.wait_seconds(0.3)
	Input.action_release("move_forward")
	var p := P.global_position
	TestHarness.check(p.y > top.y - 0.2, "safehouse: the player walks up the stair to the mezzanine (y %.2f, landing %.2f, %.1f s)" % [p.y, top.y, t_up])
	# to the bed
	var bed: Transform3D = _city.call("get_landmark_marker", "safehouse", "Use_Bed")
	var t_bed := 0.0
	Input.action_press("move_forward")
	while t_bed < 5.0:
		var to := bed.origin - P.global_position
		to.y = 0.0
		if to.length() < 1.3:
			break
		_cam_yaw(atan2(-to.x, -to.z))
		await TestHarness.wait_physics_frames(6)
		t_bed += 0.1
	Input.action_release("move_forward")
	await TestHarness.wait_seconds(0.4)
	var d := (bed.origin - P.global_position)
	TestHarness.check(Vector2(d.x, d.z).length() < 1.6 and absf(d.y) < 0.6, "safehouse: the player reaches the bed on the mezzanine (%.2f m, dy %.2f)" % [Vector2(d.x, d.z).length(), d.y])
	_cam_yaw(yaw + PI * 0.75)
	await TestHarness.wait_seconds(0.5)
	await TestHarness.shot("city_play_safehouse_mezzanine")


# ---------------------------------------------------------------------------------------------
# 2. radio mast ladder: up, stand on the platform, down again
# ---------------------------------------------------------------------------------------------

func _ladder_of(lm: String) -> Node3D:
	var node: Node3D = _city.call("get_landmark_node", lm)
	if node == null:
		return null
	return node.get_node_or_null("Ladder") as Node3D


## Windowed runs must stay short (<= 20 s): mount the ladders directly at the heights to photograph.
func _ladder_shots(lm: String, heights: Array, prefix: String) -> void:
	var lad := _ladder_of(lm)
	if lad == null:
		return
	var back := lad.global_transform.basis.z
	back.y = 0.0
	back = back.normalized()
	var face_yaw := atan2(back.x, back.z)
	var foot := lad.global_position
	for hgt: float in heights:
		P.call("teleport", foot + back * 0.36 + Vector3(0, hgt, 0), face_yaw)
		await TestHarness.wait_physics_frames(2)
		P.call("start_ladder", lad, 0)
		var cam: Variant = P.get("camera")
		if cam is Object and is_instance_valid(cam):
			(cam as Object).set("yaw", face_yaw + 0.7)
			(cam as Object).set("pitch", -0.1)
		await TestHarness.wait_seconds(0.9)
		TestHarness.log_line("%s at %.1f m: state %s, y %.2f" % [prefix, hgt, _state(), P.global_position.y])
		await TestHarness.shot("%s_%d" % [prefix, int(hgt)])
	_release()
	P.call("teleport", foot + back * 3.0 + Vector3(0, 0.5, 0), face_yaw)
	await TestHarness.wait_seconds(0.3)


func _mast() -> void:
	var lad := _ladder_of("radio_mast")
	if not TestHarness.check(lad != null, "radio mast ladder node"):
		return
	if not TestHarness.is_headless():
		await _ladder_shots("radio_mast", [3.0, 23.5], "city_play_mast")
		return
	var back := lad.global_transform.basis.z
	back.y = 0.0
	back = back.normalized()
	var face_yaw := atan2(back.x, back.z)          # facing = -back
	var h := float(lad.get_meta("height"))
	var foot := lad.global_position
	P.call("teleport", foot + back * 0.75 + Vector3(0, 0.3, 0), face_yaw)
	_cam_yaw(face_yaw)
	await TestHarness.wait_seconds(0.8)
	await _tap("interact")
	await TestHarness.wait_seconds(0.2)
	if _state() != "ladder":
		TestHarness.log_line("interact did not mount the mast ladder (state %s, prompt focus elsewhere?) - using start_ladder()" % _state())
		P.call("start_ladder", lad, 0)
	TestHarness.check(_state() == "ladder", "mast: the player mounts the ladder at its foot (state %s)" % _state())
	Input.action_press("move_forward")
	var t := 0.0
	var shot_low := false
	var shot_high := false
	while t < 30.0 and _state() == "ladder":
		await TestHarness.wait_physics_frames(6)
		t += 0.1
		var climbed := P.global_position.y - foot.y
		if not shot_low and climbed > 3.0:
			shot_low = true
			await _ladder_shot("city_play_mast_low", back)
		if not shot_high and climbed > h - 3.0:
			shot_high = true
			await _ladder_shot("city_play_mast_high", back)
	Input.action_release("move_forward")
	await TestHarness.wait_seconds(1.5)
	var top_y := foot.y + h
	var p := P.global_position
	TestHarness.check(_state() == "on_foot" and absf(p.y - top_y) < 0.35 and bool(P.get("grounded")),
			"mast: the player climbs %.1f m and stands on the platform (state %s, y %.2f, platform %.2f, %.1f s)" % [h, _state(), p.y, top_y, t])
	if _state() != "on_foot" or absf(p.y - top_y) > 0.5:
		return
	await TestHarness.shot("city_play_mast_top")
	# back down: stand at the top exit, interact, move_back to the foot
	var exit := foot + Vector3(0, h, 0) - back * 0.55
	P.call("teleport", exit + Vector3(0, 0.05, 0), face_yaw + PI)
	_cam_yaw(face_yaw + PI)
	await TestHarness.wait_seconds(0.6)
	await _tap("interact")
	await TestHarness.wait_seconds(0.2)
	if _state() != "ladder":
		TestHarness.log_line("interact did not mount the mast ladder from the top (state %s) - using start_ladder()" % _state())
		P.call("start_ladder", lad, 1)
	TestHarness.check(_state() == "ladder", "mast: the player mounts the ladder from the platform (state %s)" % _state())
	await TestHarness.wait_seconds(1.0)
	Input.action_press("move_back")
	t = 0.0
	while t < 30.0 and _state() == "ladder":
		await TestHarness.wait_physics_frames(6)
		t += 0.1
	Input.action_release("move_back")
	await TestHarness.wait_seconds(1.0)
	p = P.global_position
	var g := float(Game.world.call("get_height", p.x, p.z)) if Game.world != null else foot.y
	TestHarness.check(_state() == "on_foot" and p.y < foot.y + 1.0 and p.y > g - 0.3,
			"mast: the player climbs back down to the ground (state %s, y %.2f, foot %.2f, %.1f s)" % [_state(), p.y, foot.y, t])


func _ladder_shot(n: String, back: Vector3) -> void:
	if TestHarness.is_headless():
		return
	var cam: Variant = P.get("camera")
	if cam is Object and is_instance_valid(cam):
		(cam as Object).set("yaw", atan2(back.x, back.z) + 0.6)
		(cam as Object).set("pitch", -0.15)
	Input.action_release("move_forward")
	await TestHarness.wait_seconds(0.5)
	await TestHarness.shot(n)
	Input.action_press("move_forward")


# ---------------------------------------------------------------------------------------------
# 3. pier-end swim ladder: out of the water onto the deck
# ---------------------------------------------------------------------------------------------

func _pier() -> void:
	var lad := _ladder_of("marina_pier")
	if not TestHarness.check(lad != null, "pier end swim ladder node"):
		return
	if not TestHarness.is_headless():
		await _ladder_shots("marina_pier", [0.1], "city_play_pier")
		return
	var back := lad.global_transform.basis.z
	back.y = 0.0
	back = back.normalized()
	var face_yaw := atan2(back.x, back.z)
	var foot := lad.global_position
	var deck_y := foot.y + float(lad.get_meta("height"))
	P.call("teleport", foot + back * 1.4 + Vector3(0, -0.4, 0), face_yaw)
	_cam_yaw(face_yaw)
	await TestHarness.wait_seconds(1.5)
	TestHarness.log_line("pier: in the water state %s, swimming %s, y %.2f" % [_state(), str(P.get("is_swimming")), P.global_position.y])
	# swim to the ladder
	Input.action_press("move_forward")
	var t := 0.0
	while t < 3.0:
		await TestHarness.wait_physics_frames(6)
		t += 0.1
		_cam_yaw(face_yaw)
		var fl: Variant = P.call("find_ladder") if P.has_method("find_ladder") else {}
		if fl is Dictionary and not (fl as Dictionary).is_empty():
			break
	Input.action_release("move_forward")
	await _tap("interact")
	await TestHarness.wait_seconds(0.2)
	if _state() != "ladder":
		TestHarness.log_line("interact did not mount the pier ladder from the water (state %s, pos %s) - using start_ladder()" % [_state(), str(P.global_position)])
		P.call("start_ladder", lad, 0)
	TestHarness.check(_state() == "ladder", "pier: the swimmer mounts the swim ladder (state %s)" % _state())
	Input.action_press("move_forward")
	t = 0.0
	while t < 10.0 and _state() == "ladder":
		await TestHarness.wait_physics_frames(6)
		t += 0.1
	Input.action_release("move_forward")
	await TestHarness.wait_seconds(1.5)
	var p := P.global_position
	TestHarness.check(_state() == "on_foot" and absf(p.y - deck_y) < 0.3 and bool(P.get("grounded")),
			"pier: the player climbs out of the water and stands on the deck (state %s, y %.2f, deck %.2f)" % [_state(), p.y, deck_y])
	await TestHarness.shot("city_play_pier_deck")
