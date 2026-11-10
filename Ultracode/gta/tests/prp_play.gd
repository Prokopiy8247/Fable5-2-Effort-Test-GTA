extends Node
## PropSystem (WORLD DRESSING) gameplay test with the REAL player (input through Input.action_press):
##   tools\godot.ps1 -Mode headless -Frames 5400 -TimeoutSec 420 -UserArgs '--test=prp_play','--disable=traffic,peds,police,wildlife,emergency,transit,taxi,activities,radio,ambience,shops,garage'
## 1. a building fire-escape ladder: prompt at the foot, interact mounts it, the body hangs on the rungs
##    (STAND_OFF behind the rail line of the visible ladder), holding forward climbs onto the roof
## 2. a quay ladder: swim to it, interact, climb out onto the quay deck
## 3. the player drives a real sedan (throttle = move_forward) into a lamp post: it topples, its pooled
##    night light goes, a property_damage crime is reported
## 4. the player shoots a sign through Combat.fire_hitscan: it is knocked over
## 5. timed respawn (respawn_seconds shortened): once the player is far away the props stand again,
##    the lamp light is back

const COMBAT_PATH := "res://gta/code/combat/combat.gd"

var ps: Node
var P: Node3D
var crimes: Array = []


func _ready() -> void:
	await TestHarness.wait_frames(20)
	ps = Game.get_system("props")
	P = Game.player
	TestHarness.check(ps != null and P != null, "props system and player present")
	if ps == null or P == null:
		TestHarness.finish(false, "missing props or player")
		return
	if Weather.has_method("snap_weather"):
		Weather.call("snap_weather", "clear")
	Weather.auto_cycle = false
	WorldClock.set_hour(11.0)
	WorldClock.paused = true
	Game.invulnerable = true
	EventBus.crime_committed.connect(func(id: String, _p: Vector3, _w: Node) -> void: crimes.append(id))
	await TestHarness.wait_seconds(1.0)
	await _test_building_ladder()
	await _test_quay_ladder()
	var lamp := await _test_drive_into_lamp()
	var sign_i := await _test_shoot_sign()
	await _test_timed_respawn(lamp, sign_i)
	_release_all()
	TestHarness.finish()


func _release_all() -> void:
	for a: String in ["move_forward", "move_back", "move_left", "move_right", "sprint", "interact", "jump"]:
		Input.action_release(a)


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await TestHarness.wait_physics_frames(3)
		t += 3.0 / 60.0
	return bool(cond.call())


func _state() -> String:
	return String(P.get("state_id"))


func _back(l: Node3D) -> Vector3:
	var b := l.global_basis.z
	b.y = 0.0
	return b.normalized()


## Nearest fire_escape_ladder section to a ladder node (its rail line), -1 if none within 1.5 m.
func _rail_of(l: Node3D) -> int:
	var f: PackedInt32Array = ps.call("find_instances", "fire_escape_ladder", l.global_position, 1.5)
	if f.is_empty():
		f = ps.call("find_instances", "fire_escape_ladder", l.global_position + Vector3(0, 3.0, 0), 4.0)
	return f[0] if not f.is_empty() else -1


## Stand at the foot (or float behind it), interact, hold forward until the player leaves the ladder.
func _climb(l: Node3D, label: String, from_water: bool) -> void:
	var back := _back(l)
	var h := float(l.get_meta("height", 3.0))
	_release_all()
	if from_water:
		var w := l.global_position + back * 0.9
		P.call("teleport", Vector3(w.x, -0.6, w.z), atan2(back.x, back.z))
		await _until(func() -> bool: return bool(P.get("is_swimming")), 4.0)
		TestHarness.check(bool(P.get("is_swimming")), "%s: the player swims at the foot of the ladder" % label)
	else:
		var s := l.global_position + back * 0.6
		P.call("teleport", s + Vector3(0, 0.05, 0), atan2(back.x, back.z))
		await TestHarness.wait_physics_frames(12)
	var info: Dictionary = P.call("find_ladder") if P.has_method("find_ladder") else {}
	TestHarness.check(not info.is_empty() and info.get("ladder") == l, "%s: the ladder is offered at its foot" % label)
	Input.action_press("interact")
	await TestHarness.wait_physics_frames(2)
	Input.action_release("interact")
	var on := await _until(func() -> bool: return _state() == "ladder", 1.0)
	TestHarness.check(on, "%s: interact mounts the ladder (state %s)" % [label, _state()])
	if not on:
		return
	# hanging on the rungs: the body is STAND_OFF (0.36 m) behind the rail line of the visible ladder
	await TestHarness.wait_seconds(0.6)
	var rail := _rail_of(l)
	if rail >= 0:
		var rx: Transform3D = ps.call("get_instance_transform", rail)
		var d := Vector2(P.global_position.x - rx.origin.x, P.global_position.z - rx.origin.z).dot(Vector2(back.x, back.z))
		TestHarness.check(d > 0.25 and d < 0.5, "%s: the climber hangs on the visible rungs (%.2f m behind the rail line)" % [label, d])
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var done := await _until(func() -> bool: return _state() != "ladder", h / 2.5 + 4.0)
	_release_all()
	var rise := P.global_position.y - l.global_position.y
	TestHarness.check(done and _state() == "on_foot" and absf(rise - h) < 0.45,
			"%s: climbed out at the top (state %s, %.2f m above the foot, ladder %.2f m)" % [label, _state(), rise, h])
	await TestHarness.wait_physics_frames(10)


func _test_building_ladder() -> void:
	var picked: Node3D = null
	for l: Node3D in ps.call("get_ladders"):
		if not bool(l.get_meta("water", false)) and float(l.get_meta("height", 0.0)) > 4.0:
			picked = l
			break
	TestHarness.check(picked != null, "a building fire-escape ladder exists")
	if picked != null:
		TestHarness.log_line("building ladder %s at %s, %.1f m" % [picked.name, str(picked.global_position.snapped(Vector3.ONE * 0.1)), float(picked.get_meta("height"))])
		await _climb(picked, "building ladder", false)


func _test_quay_ladder() -> void:
	var picked: Node3D = null
	for l: Node3D in ps.call("get_ladders"):
		if bool(l.get_meta("water", false)):
			picked = l
			break
	TestHarness.check(picked != null, "a quay ladder exists")
	if picked != null:
		TestHarness.log_line("quay ladder %s at %s" % [picked.name, str(picked.global_position.snapped(Vector3.ONE * 0.1))])
		await _climb(picked, "quay ladder", true)


## Returns the lamp instance that was knocked over (-1 if none).
func _test_drive_into_lamp() -> int:
	var lamps: PackedInt32Array = ps.call("find_instances", "street_lamp_a", Vector3(60.0, 2.6, -20.0), 500.0)
	var target := -1
	for i in lamps:
		if String(ps.call("get_instance_state", i)) != "idle":
			continue
		var xf: Transform3D = ps.call("get_instance_transform", i)
		var along := xf.basis.x.normalized()
		var clear := true
		for k in range(3, 26, 3):
			if not bool(ps.call("is_free", xf.origin - along * float(k), 1.0)):
				clear = false
				break
		if clear:
			target = i
			break
	TestHarness.check(target >= 0, "a lamp post with a clear run-up")
	if target < 0:
		return -1
	var lxf: Transform3D = ps.call("get_instance_transform", target)
	var dir := lxf.basis.x.normalized()
	var start := lxf.origin - dir * 22.0
	start.y = Game.ground_height(start.x, start.z) + 0.5
	var car: Node3D = Game.spawn_vehicle("sedan", Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), start), {"owner_tag": "parked"})
	TestHarness.check(car != null, "spawned a sedan for the player")
	if car == null:
		return -1
	P.call("teleport", start - lxf.basis.z * 3.0 + Vector3(0, 0.1, 0), atan2(-dir.x, -dir.z))
	await TestHarness.wait_seconds(0.8)
	P.call("enter_vehicle", car, 0)
	var seated := await _until(func() -> bool: return P.get("current_vehicle") == car and bool(car.get("is_player_driven")), 5.0)
	TestHarness.check(seated, "the player drives the sedan")
	crimes.clear()
	var lights_before: int = (ps.get("_lights") as Dictionary).size()
	Input.action_press("move_forward")
	var hit := await _until(func() -> bool: return String(ps.call("get_instance_state", target)) != "idle", 7.0)
	var speed := float(car.get("speed_kmh"))
	await TestHarness.wait_seconds(1.2)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await TestHarness.wait_seconds(1.0)
	Input.action_release("move_back")
	TestHarness.check(hit, "driving into the lamp post knocks it over (%s, %.0f km/h at contact)" % [String(ps.call("get_instance_state", target)), speed])
	var body: Node3D = ps.call("get_instance_body", target)
	if body != null:
		TestHarness.check(body.global_basis.y.dot(Vector3.UP) < 0.95 or body.global_position.distance_to(lxf.origin) > 0.8, "the lamp post toppled")
	TestHarness.check(not (ps.get("_lights") as Dictionary).has(target) and (ps.get("_lights") as Dictionary).size() == lights_before - 1,
			"its night light anchor is gone")
	TestHarness.check(crimes.count("property_damage") == 1, "property_damage reported once (%s)" % str(crimes))
	P.call("exit_vehicle")
	await _until(func() -> bool: return P.get("current_vehicle") == null and _state() == "on_foot", 4.0)
	car.queue_free()
	if Wanted.has_method("clear"):
		Wanted.clear("cheat")
	await _test_bicycle_into_lamp(target)
	return target if hit else -1


## The player pedals a real bicycle into another lamp post: the post stands (the bike stops at it).
func _test_bicycle_into_lamp(skip: int) -> void:
	var lamps: PackedInt32Array = ps.call("find_instances", "street_lamp_a", Vector3(-60.0, 2.6, 70.0), 500.0)
	var target := -1
	for i in lamps:
		if i == skip or String(ps.call("get_instance_state", i)) != "idle":
			continue
		var xf: Transform3D = ps.call("get_instance_transform", i)
		var along := xf.basis.x.normalized()
		var clear := true
		for k in range(3, 25, 3):
			if not bool(ps.call("is_free", xf.origin - along * float(k), 0.8)):
				clear = false
				break
		if clear:
			target = i
			break
	if target < 0:
		TestHarness.log_line("no lamp with a clear run-up for the bicycle")
		return
	var lxf: Transform3D = ps.call("get_instance_transform", target)
	var dir := lxf.basis.x.normalized()
	var start := lxf.origin - dir * 20.0
	start.y = Game.ground_height(start.x, start.z) + 0.4
	var bike: Node3D = Game.spawn_vehicle("bicycle", Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), start), {"owner_tag": "parked"})
	if bike == null:
		TestHarness.log_line("no bicycle spec: bicycle check skipped")
		return
	P.call("teleport", start - lxf.basis.z * 2.0 + Vector3(0, 0.1, 0), atan2(-dir.x, -dir.z))
	await TestHarness.wait_seconds(0.6)
	P.call("enter_vehicle", bike, 0)
	var seated := await _until(func() -> bool: return P.get("current_vehicle") == bike, 5.0)
	TestHarness.check(seated, "the player rides a bicycle")
	crimes.clear()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var top := 0.0
	var t := 0.0
	while t < 6.0:
		await TestHarness.wait_physics_frames(6)
		t += 0.1
		top = maxf(top, float(bike.get("speed_kmh")) if is_instance_valid(bike) else 0.0)
	_release_all()
	var st := String(ps.call("get_instance_state", target))
	var reach := Vector2(bike.global_position.x - lxf.origin.x, bike.global_position.z - lxf.origin.z).length() if is_instance_valid(bike) else -1.0
	TestHarness.check(reach >= 0.0 and reach < 3.5, "the bicycle reached the lamp post (%.1f m from it, top %.0f km/h)" % [reach, top])
	TestHarness.check(st == "idle" and crimes.count("property_damage") == 0,
			"a bicycle does not knock the 180 kg lamp post over (%s)" % st)
	if P.get("current_vehicle") != null:
		P.call("exit_vehicle")
	await _until(func() -> bool: return P.get("current_vehicle") == null, 4.0)
	await TestHarness.wait_seconds(0.5)
	if is_instance_valid(bike):
		bike.queue_free()
	if Wanted.has_method("clear"):
		Wanted.clear("cheat")


## Returns the sign instance that was shot over (-1 if none).
func _test_shoot_sign() -> int:
	if not ResourceLoader.exists(COMBAT_PATH):
		TestHarness.log_line("no Combat module: sign shooting skipped")
		return -1
	var combat: Script = load(COMBAT_PATH)
	var signs: PackedInt32Array = ps.call("find_instances", "sign_speed", Vector3(0.0, 2.6, -60.0), 600.0)
	var target := -1
	for i in signs:
		if String(ps.call("get_instance_state", i)) == "idle":
			target = i
			break
	TestHarness.check(target >= 0, "an idle speed sign")
	if target < 0:
		return -1
	var xf: Transform3D = ps.call("get_instance_transform", target)
	var face := -xf.basis.z.normalized()
	var stand := xf.origin + face * 6.0
	stand.y = Game.ground_height(stand.x, stand.z)
	P.call("teleport", stand + Vector3(0, 0.05, 0), atan2(face.x, face.z))
	await TestHarness.wait_physics_frames(10)
	var origin := stand + Vector3(0, 1.5, 0)
	var aim := xf.origin + Vector3(0, 1.0, 0)
	var shots := 0
	while shots < 6 and String(ps.call("get_instance_state", target)) == "idle":
		combat.call("fire_hitscan", origin, (aim - origin).normalized(), "pistol", P, {})
		shots += 1
		await TestHarness.wait_physics_frames(4)
	TestHarness.check(String(ps.call("get_instance_state", target)) == "active", "the player's pistol knocks the sign over (%d shots)" % shots)
	if Wanted.has_method("clear"):
		Wanted.clear("cheat")
	return target


func _test_timed_respawn(lamp: int, sign_i: int) -> void:
	var ids: Array[int] = []
	for i: int in [lamp, sign_i]:
		if i >= 0:
			ids.append(i)
	if ids.is_empty():
		TestHarness.log_line("nothing broken: timed respawn skipped")
		return
	var old := float(ps.get("respawn_seconds"))
	ps.set("respawn_seconds", 3.0)
	# far away (> 70 m and > 160 m from the camera) on the airport apron
	P.call("teleport", Vector3(-215.0, 2.6, -255.0), PI * 0.5)
	var all_idle := func() -> bool:
		for i: int in ids:
			if String(ps.call("get_instance_state", i)) != "idle":
				return false
		return true
	var back := await _until(all_idle, 12.0)
	ps.set("respawn_seconds", old)
	var states: PackedStringArray = []
	for i: int in ids:
		states.append(String(ps.call("get_instance_state", i)))
	TestHarness.check(back, "broken props stand again once the player is far away (%s)" % ", ".join(states))
	if lamp >= 0:
		TestHarness.check((ps.get("_lights") as Dictionary).has(lamp), "the respawned lamp has its night light anchor again")
	var c: Dictionary = ps.call("get_counts")
	TestHarness.check(int(c["active"]) == 0, "no knocked-over bodies left after the respawn (%d)" % int(c["active"]))
