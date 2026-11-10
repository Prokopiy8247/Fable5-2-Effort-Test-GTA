extends Node
## plr2_melee - headless test of the melee stance (PlayerStateMelee) through the REAL WeaponInventory
## and Combat: light combo timing (3 steps, finisher harder, window reset), soft lock-on + lunge,
## heavy attack wind-up + knock-down (bat), finisher on the downed target, block (frontal only,
## stamina cost, guard break), dodge step, directional hit reactions, strength XP, leaving the stance.
##
##   tools\godot.ps1 -Mode headless -Frames 4200 -TimeoutSec 300 `
##       -UserArgs '--test=plr2_melee','--disable=traffic,peds,police','--test-timeout=240'

const Arena := preload("res://gta/tests/plr_arena.gd")
const SPOT := Vector3(-30.0, 0.0, 50.0)


## Stand-in NPC (test equipment): records every hit and knock-down. NpcBase-compatible members.
class Dummy extends CharacterBody3D:
	var health: float = 400.0
	var is_dead: bool = false
	var knocked: bool = false
	var faction: String = "gang"
	var hostile: bool = true
	var hits: Array = []
	var knockdowns: int = 0

	func _init() -> void:
		add_to_group("npc")
		collision_layer = Layers.NPC
		collision_mask = Layers.WORLD
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.32
		cap.height = 1.75
		cs.shape = cap
		cs.position = Vector3(0.0, 0.875, 0.0)
		add_child(cs)

	func apply_damage(info: Dictionary) -> void:
		if is_dead:
			return
		hits.append(info)
		health -= float(info.get("amount", 0.0))
		if health <= 0.0:
			is_dead = true

	func knock_down(_impulse: Vector3) -> void:
		knockdowns += 1
		knocked = true

	func is_knocked_down() -> bool:
		return knocked

	func get_target_position() -> Vector3:
		return global_position + Vector3(0.0, 0.3 if knocked else 1.2, 0.0)

	func damage_of(i: int) -> float:
		return float((hits[i] as Dictionary).get("amount", 0.0)) if i < hits.size() else 0.0


var P: Player = null
var arena: Arena = null
var T: Node = null
var inv: Node = null
var dummy: Dummy = null
var swings: Array = []          # [heavy, step]


func _ready() -> void:
	T = TestHarness
	await _run()


func _run() -> void:
	P = Game.player as Player
	if not T.check(P != null, "Game.player is a Player"):
		T.finish(false, "no player")
		return
	arena = Arena.new()
	Game.main.add_child(arena)
	inv = P.inventory
	if not T.check(inv != null and inv.has_signal("melee_started") and inv.has_method("melee_attack"), "real WeaponInventory present"):
		T.finish(false, "melee needs the weapons module")
		return
	inv.connect("melee_started", func(_id: String, heavy: bool, step: int) -> void: swings.append([heavy, step]))
	dummy = Dummy.new()
	dummy.name = "MeleeDummy"
	arena.add_child(dummy)
	await T.wait_physics_frames(5)
	await _test_combo()
	await _test_lock_on()
	await _test_heavy_and_finisher()
	await _test_block()
	await _test_dodge_step()
	await _test_hit_direction()
	await _test_leave_stance()
	_release_all()
	T.finish(true, "melee")


# --- helpers ---------------------------------------------------------------------------------------

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "aim", "fire", "melee_heavy"]:
		Input.action_release(a)


func _place(yaw: float = 0.0) -> void:
	_release_all()
	P.teleport(arena.at(SPOT) + Vector3(0.0, 0.03, 0.0), yaw)
	P.heal(1000.0)
	P.stamina = 1.0
	await T.wait_physics_frames(12)


func _put_dummy(local_offset: Vector3) -> void:
	dummy.global_position = arena.at(SPOT) + local_offset
	dummy.knocked = false
	dummy.is_dead = false
	dummy.health = 400.0
	dummy.hits.clear()
	dummy.knockdowns = 0


func _equip(id: String) -> void:
	if id != "fists" and not bool(inv.call("has_weapon", id)):
		inv.call("give_weapon", id)
	inv.call("equip", id)
	await T.wait_physics_frames(30)


func _tap(action: String) -> void:
	Input.action_press(action)
	await T.wait_physics_frames(2)
	Input.action_release(action)


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	while t < timeout:
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
		t += step
	return bool(cond.call())


func _yaw_error_to(n: Node3D) -> float:
	var to := n.global_position - P.global_position
	var want := atan2(-to.x, -to.z)
	return absf(rad_to_deg(angle_difference(P.rotation.y, want)))


# --- tests ----------------------------------------------------------------------------------------

func _test_combo() -> void:
	await _place(0.0)
	await _equip("fists")
	_put_dummy(Vector3(0.0, 0.0, -1.3))
	swings.clear()
	var xp0 := Skills.get_level("strength")
	# three presses in rhythm: each one lands inside the previous swing and is chained
	await _tap("fire")
	var stance := await _until(func() -> bool: return P.state_id == "melee", 0.2)
	T.check(stance, "fire with fists enters the melee stance (state %s)" % P.state_id)
	await T.wait_seconds(0.30)
	await _tap("fire")
	await T.wait_seconds(0.45)
	await _tap("fire")
	await _until(func() -> bool: return swings.size() >= 3 and dummy.hits.size() >= 3, 2.5)
	await T.wait_seconds(0.4)
	var steps: Array = []
	for s: Array in swings:
		steps.append(int(s[1]))
	T.check(steps.size() >= 3 and steps.slice(0, 3) == [1, 2, 3], "three timed presses chain the combo steps 1-2-3 (%s)" % str(steps))
	T.check(dummy.hits.size() >= 3, "every strike of the combo lands (%d hits)" % dummy.hits.size())
	T.check(dummy.damage_of(2) > dummy.damage_of(0) * 1.3, "the combo finisher hits harder (%.1f vs %.1f)" % [dummy.damage_of(2), dummy.damage_of(0)])
	T.check(Skills.get_level("strength") > xp0, "hits train strength (%.2f -> %.2f)" % [xp0, Skills.get_level("strength")])
	# outside the combo window the chain starts over (the fist finisher may have knocked the dummy
	# down: stand it up, or the next press would be a finisher)
	await T.wait_seconds(0.9)
	dummy.knocked = false
	swings.clear()
	await _tap("fire")
	await _until(func() -> bool: return not swings.is_empty(), 0.5)
	T.check(not swings.is_empty() and int(swings[0][1]) == 1, "after the 0.55 s window the combo restarts at step 1 (%s)" % str(swings))
	await T.wait_seconds(0.8)


func _test_lock_on() -> void:
	await _place(0.0)
	# 45 deg to the front-left, 2.0 m away; the player faces straight ahead (-Z)
	_put_dummy(Vector3(-1.414, 0.0, -1.414))
	await T.wait_physics_frames(3)
	var err0 := _yaw_error_to(dummy)
	var d0 := Vector2(dummy.global_position.x - P.global_position.x, dummy.global_position.z - P.global_position.z).length()
	await _tap("fire")
	await _until(func() -> bool: return not dummy.hits.is_empty(), 1.2)
	T.check(P.melee_target == dummy, "soft lock-on picks the dummy in reach (%s)" % str(P.melee_target))
	T.check(_yaw_error_to(dummy) < 15.0 and err0 > 30.0, "the body turns to the locked target (%.0f -> %.0f deg off)" % [err0, _yaw_error_to(dummy)])
	var d1 := Vector2(dummy.global_position.x - P.global_position.x, dummy.global_position.z - P.global_position.z).length()
	T.check(d1 < d0 - 0.3, "the strike lunges towards it (%.2f -> %.2f m)" % [d0, d1])
	T.check(not dummy.hits.is_empty(), "... and connects (%d hits)" % dummy.hits.size())
	await T.wait_seconds(1.0)


func _test_heavy_and_finisher() -> void:
	await _place(0.0)
	await _equip("bat")
	_put_dummy(Vector3(0.0, 0.0, -1.7))
	swings.clear()
	await _tap("melee_heavy")
	await _until(func() -> bool: return not swings.is_empty(), 0.3)
	T.check(P.state_id == "melee" and not swings.is_empty() and bool(swings[0][0]), "melee_heavy starts a heavy swing (%s, %s)" % [P.state_id, str(swings)])
	await T.wait_seconds(0.35)
	T.check(dummy.hits.is_empty(), "wind-up: nothing lands in the first 0.35 s")
	await _until(func() -> bool: return not dummy.hits.is_empty(), 1.2)
	T.check(not dummy.hits.is_empty() and bool((dummy.hits[0] as Dictionary).get("heavy", false)), "the heavy blow lands (%d hits)" % dummy.hits.size())
	T.check(dummy.knockdowns >= 1, "a heavy bat blow knocks the target down (%d)" % dummy.knockdowns)
	await T.wait_seconds(0.6)
	# finisher on the downed target
	var before := dummy.hits.size()
	var xp0 := Skills.get_level("strength")
	await _tap("fire")
	await _until(func() -> bool: return dummy.hits.size() > before, 1.2)
	var fin: Dictionary = dummy.hits[dummy.hits.size() - 1] if dummy.hits.size() > before else {}
	T.check(bool(fin.get("finisher", false)), "fire next to the downed target = finisher (%s)" % str(fin.keys()))
	T.check(float(fin.get("amount", 0.0)) >= 40.0, "the finisher is a big hit (%.0f)" % float(fin.get("amount", 0.0)))
	T.check(Skills.get_level("strength") > xp0, "a finisher trains strength")
	await T.wait_seconds(0.8)
	await _equip("fists")


func _test_block() -> void:
	await _place(0.0)
	_put_dummy(Vector3(0.0, 0.0, -1.6))
	Input.action_press("aim")
	var blocking := await _until(func() -> bool: return P.is_blocking, 0.4)
	T.check(blocking and P.state_id == "melee", "aim with fists raises the guard (blocking %s, state %s)" % [str(blocking), P.state_id])
	await T.wait_physics_frames(10)
	T.check(P.animator.guard > 0.5, "the animator shows the guard (%.2f)" % P.animator.guard)
	var hp := P.health
	var st := P.stamina
	# a frontal punch from the dummy (direction = from the dummy to the player)
	var dir := (P.global_position - dummy.global_position).normalized()
	P.apply_damage(Dmg.make(20.0, "melee", dummy, P.get_target_position(), dir))
	var lost := hp - P.health
	T.check(lost > 0.0 and lost <= 5.0, "a frontal blow is blocked (%.1f of 20 hp)" % lost)
	T.check(P.stamina < st - 0.04, "blocking costs stamina (%.2f -> %.2f)" % [st, P.stamina])
	# from behind the guard does not help
	hp = P.health
	P.apply_damage(Dmg.make(20.0, "melee", dummy, P.get_target_position(), -P.global_basis.z))
	T.check(hp - P.health > 19.0, "a blow from behind is not blocked (%.1f hp)" % (hp - P.health))
	# guard break when out of stamina
	P.heal(1000.0)
	P.stamina = 0.03
	hp = P.health
	P.apply_damage(Dmg.make(20.0, "melee", dummy, P.get_target_position(), dir))
	var of := P.states["melee"] as PlayerStateMelee
	T.check(hp - P.health > 19.0 and of.is_staggering(), "out of stamina the guard breaks: full damage + stagger (%.1f hp, stagger %s)" % [hp - P.health, str(of.is_staggering())])
	Input.action_release("aim")
	P.stamina = 1.0
	await T.wait_seconds(0.8)


func _test_dodge_step() -> void:
	await _place(0.0)
	_put_dummy(Vector3(0.0, 0.0, -1.8))
	Input.action_press("aim")
	await _until(func() -> bool: return P.is_blocking, 0.4)
	var start := P.global_position
	Input.action_press("move_right")
	await T.wait_physics_frames(3)
	await _tap("jump")
	var stepping := await _until(func() -> bool: return P.state_id == "roll", 0.3)
	var roll := P.states["roll"] as PlayerStateRoll
	T.check(stepping and roll.kind == "step", "guard + right + jump = dodge step (state %s, kind %s)" % [P.state_id, roll.kind])
	var hp := P.health
	P.apply_damage(Dmg.make(20.0, "melee", dummy, P.get_target_position(), (P.global_position - dummy.global_position).normalized()))
	T.check(is_equal_approx(P.health, hp), "a blow during the dodge step misses (%.1f hp lost)" % (hp - P.health))
	await _until(func() -> bool: return P.state_id != "roll", 1.0)
	Input.action_release("move_right")
	var moved := P.global_position - start
	T.check(moved.x > 0.9 and P.state_id == "melee", "the step moves sideways and returns to the stance (%.2f m, %s)" % [moved.x, P.state_id])
	Input.action_release("aim")
	await T.wait_seconds(1.0)


func _test_hit_direction() -> void:
	await _place(0.0)
	_put_dummy(Vector3(-1.5, 0.0, 0.0))
	await T.wait_physics_frames(3)
	# a blow from the left side (travelling towards +X)
	P.apply_damage(Dmg.make(6.0, "melee", dummy, P.get_target_position(), Vector3(1.0, 0.0, 0.0)))
	var l := P.global_basis.inverse() * Vector3(-1.0, 0.0, 0.0)
	var want := Vector2(l.x, -l.z).normalized()
	T.check(P.animator.get_action() == "hit_react" and P.animator.hit_dir.dot(want) > 0.8,
			"a hit from the left plays a reaction from the left (from %s, expected %s)" % [str(P.animator.hit_dir), str(want)])
	await T.wait_physics_frames(30)
	# a heavy blow from the front staggers
	P.heal(1000.0)
	_put_dummy(Vector3(0.0, 0.0, -1.5))
	P.apply_damage(Dmg.make(12.0, "melee", dummy, P.get_target_position(), Vector3(0.0, 0.0, 1.0), {"heavy": true}))
	var st := P.state as PlayerStateOnFoot
	T.check(st != null and st.is_staggering(), "a heavy blow staggers the player (state %s)" % P.state_id)
	await T.wait_seconds(0.6)


func _test_leave_stance() -> void:
	await _place(0.0)
	_put_dummy(Vector3(0.0, 0.0, -1.5))
	await _tap("fire")
	await _until(func() -> bool: return P.state_id == "melee", 0.3)
	var left := await _until(func() -> bool: return P.state_id == "on_foot", 2.5)
	T.check(left, "the stance ends by itself after a moment without fighting (%s)" % P.state_id)
	# drawing a firearm leaves it at once
	Input.action_press("aim")
	await _until(func() -> bool: return P.state_id == "melee", 0.3)
	inv.call("equip", "pistol")
	var out := await _until(func() -> bool: return P.state_id == "on_foot", 0.5)
	T.check(out, "drawing a firearm leaves the melee stance (%s)" % P.state_id)
	Input.action_release("aim")
	await T.wait_physics_frames(10)
	inv.call("equip", "fists")
