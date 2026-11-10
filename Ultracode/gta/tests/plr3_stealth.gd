extends Node
## plr3_stealth - headless test of stealth mode and stealth takedowns with the REAL WeaponInventory:
##   noise radii (walk / run / sprint / sneak, Stealth skill), stealth speed, the HUD event
##   (player_state_changed "stealth"), sprint and loud gunfire end stealth while a suppressed pistol
##   does not (and its noise radius is the reduced one from WEAPONS.md), visibility_factor (crouch,
##   sneak, night, street lamp), Stealth XP near unaware NPCs, takedowns: from behind works (fists =
##   silent knock-out, knife = silent kill, pistol-whip on melee_heavy), from the front / the side /
##   out of reach / alerted / not sneaking does not, the "Takedown" prompt, no noise event, and
##   (soft, when the peds system runs) a real NpcBase civilian killed unseen gives no wanted level.
##
##   tools\godot.ps1 -Mode headless -Frames 7000 -TimeoutSec 300 `
##       -UserArgs '--test=plr3_stealth','--disable=traffic,police','--test-timeout=240'

const Arena := preload("res://gta/tests/plr_arena.gd")
const SPOT := Vector3(-30.0, 0.0, -40.0)        ## arena-local open floor

var P: Player = null
var arena: Arena = null
var T: Node = null
var inv: Node = null
var noises: Array = []                  ## [radius, kind] emitted by the player
var states_seen: Array = []
var dummy: StealthDummy = null


## NpcBase-compatible stand-in (test equipment): records hits, knock-downs, stop_moving calls.
class StealthDummy extends CharacterBody3D:
	var health: float = 100.0
	var is_dead: bool = false
	var is_alerted: bool = false
	var awareness: float = 0.0
	var faction: String = "civilian"
	var hits: Array = []
	var knockdowns: int = 0
	var stops: int = 0

	func _init() -> void:
		add_to_group("npc")
		collision_layer = Layers.NPC
		collision_mask = Layers.WORLD
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.32
		cap.height = 1.8
		cs.shape = cap
		cs.position = Vector3(0.0, 0.9, 0.0)
		add_child(cs)

	func get_awareness() -> float:
		return awareness

	func apply_damage(info: Dictionary) -> void:
		if is_dead:
			return
		hits.append(info)
		health -= float(info.get("amount", 0.0))
		if health <= 0.0:
			is_dead = true

	func knock_down(_impulse: Vector3) -> void:
		knockdowns += 1

	func stop_moving() -> void:
		stops += 1

	func get_target_position() -> Vector3:
		return global_position + Vector3(0.0, 1.2, 0.0)

	func reset() -> void:
		health = 100.0
		is_dead = false
		is_alerted = false
		awareness = 0.0
		hits.clear()
		knockdowns = 0
		stops = 0


class IdleBrain extends Node:
	func think(_npc: Node, _delta: float) -> void:
		pass


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
	var peds := Game.get_system("peds")
	if peds != null and peds.has_method("set_density"):
		peds.call("set_density", 0.0)
	if peds != null and peds.has_method("clear_all"):
		peds.call("clear_all")
	inv = P.inventory
	if not T.check(inv != null and inv.has_method("give_weapon"), "real WeaponInventory present"):
		T.finish(false, "needs the weapons module")
		return
	inv.set("infinite_ammo", true)
	EventBus.noise_emitted.connect(_on_noise)
	EventBus.player_state_changed.connect(func(s: String) -> void: states_seen.append(s))
	T.check(P.states.has("takedown") and P.stealth != null, "takedown state + stealth helper present")
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(13.0)
	await T.wait_physics_frames(20)
	await _test_noise()
	await _test_exit_rules()
	await _test_visibility()
	await _test_takedowns()
	await _test_real_npc()
	_release_all()
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(13.0)
	T.finish(true, "stealth")


func _on_noise(_pos: Vector3, radius: float, kind: String, who: Node) -> void:
	if who == P:
		noises.append([radius, kind])


# --- helpers ---------------------------------------------------------------------------------------

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "aim", "fire", "melee_heavy", "stealth", "crouch"]:
		Input.action_release(a)


func _place(local: Vector3, yaw: float = 0.0) -> void:
	_release_all()
	P.teleport(arena.at(local) + Vector3(0.0, 0.03, 0.0), yaw)
	P.heal(1000.0)
	P.stamina = 1.0
	await T.wait_physics_frames(10)


func _tap(action: String, frames: int = 2) -> void:
	Input.action_press(action)
	await T.wait_physics_frames(frames)
	Input.action_release(action)
	await T.wait_physics_frames(1)


func _until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
	return bool(cond.call())


func _set_stealth(on: bool) -> void:
	if P.in_stealth != on:
		await _tap("stealth")
	await T.wait_physics_frames(2)


func _equip(id: String) -> void:
	if id != "fists" and not bool(inv.call("has_weapon", id)):
		inv.call("give_weapon", id, 60)
	inv.call("equip", id)
	await T.wait_physics_frames(40)


func _footstep_radii() -> Array:
	var out := []
	for n: Array in noises:
		if n[1] == "footstep":
			out.append(float(n[0]))
	return out


# --- tests ----------------------------------------------------------------------------------------

func _test_noise() -> void:
	var old_lvl := Skills.get_level("stealth")
	Skills.levels["stealth"] = 0.0
	var r0 := P.get_stealth_noise_radius()
	Skills.levels["stealth"] = 100.0
	var r100 := P.get_stealth_noise_radius()
	Skills.levels["stealth"] = old_lvl
	T.check(absf(r0 - Player.NOISE_STEALTH) < 0.001 and r100 < r0 * 0.7, "sneak noise radius %.2f m at Stealth 0, %.2f m at 100" % [r0, r100])

	await _place(SPOT, 0.0)
	Input.action_press("move_forward")
	await T.wait_physics_frames(50)
	T.check(absf(P.noise_radius - Player.NOISE_RUN) < 0.01, "running: noise radius %.1f m" % P.noise_radius)
	Input.action_press("sprint")
	await T.wait_physics_frames(40)
	T.check(absf(P.noise_radius - Player.NOISE_SPRINT) < 0.01, "sprinting: noise radius %.1f m" % P.noise_radius)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _place(SPOT, 0.0)
	states_seen.clear()
	await _set_stealth(true)
	T.check(P.in_stealth and states_seen.has("stealth"), "stealth key: sneaking + player_state_changed('stealth') for the HUD")
	noises.clear()
	Input.action_press("move_forward")
	await T.wait_physics_frames(90)
	var sp := Vector2(P.velocity.x, P.velocity.z).length()
	var want := P.get_stealth_noise_radius()
	T.check(sp <= Player.STEALTH_SPEED + 0.05 and sp > 1.5, "sneaking is slower (%.2f m/s)" % sp)
	T.check(absf(P.noise_radius - want) < 0.01 and P.noise_radius < Player.NOISE_WALK * 0.5, "sneaking: noise radius %.2f m (walk %.1f)" % [P.noise_radius, Player.NOISE_WALK])
	var fr := _footstep_radii()
	var all_small := not fr.is_empty()
	for r: float in fr:
		all_small = all_small and r <= want + 0.001
	T.check(all_small, "sneaking footsteps are heard only %.2f m away (%d steps)" % [want, fr.size()])
	Input.action_release("move_forward")
	await T.wait_physics_frames(30)
	T.check(P.noise_radius == 0.0, "standing still while sneaking: no noise")
	states_seen.clear()
	await _set_stealth(false)
	T.check(not P.in_stealth and states_seen.has("on_foot"), "stealth off announced (on_foot)")


func _test_exit_rules() -> void:
	await _place(SPOT, 0.0)
	await _set_stealth(true)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await T.wait_physics_frames(20)
	T.check(not P.in_stealth and P.is_sprinting, "sprinting ends stealth")
	_release_all()
	await T.wait_physics_frames(20)

	# loud pistol vs suppressed pistol (WEAPONS.md: suppressor noise radius x0.17)
	await _place(SPOT, PI)                  # face +Z: open floor of the arena
	await _equip("pistol")
	await _set_stealth(true)
	noises.clear()
	Input.action_press("aim")
	await T.wait_physics_frames(16)
	await _tap("fire", 3)
	await T.wait_physics_frames(10)
	Input.action_release("aim")
	var loud := -1.0
	for n: Array in noises:
		if n[1] == "gunshot":
			loud = float(n[0])
	T.check(loud > 40.0 and not P.in_stealth, "a loud shot (%.0f m) ends stealth" % loud)
	await T.wait_physics_frames(30)
	var att_ok := bool(inv.call("add_attachment", "pistol", "suppressor"))
	T.check(att_ok, "suppressor fitted to the pistol")
	await T.wait_physics_frames(10)
	await _set_stealth(true)
	noises.clear()
	Input.action_press("aim")
	await T.wait_physics_frames(16)
	await _tap("fire", 3)
	await T.wait_physics_frames(10)
	Input.action_release("aim")
	var quiet := -1.0
	var quiet_kind := ""
	for n: Array in noises:
		if str(n[1]).contains("gunshot"):
			quiet = float(n[0])
			quiet_kind = str(n[1])
	T.check(quiet_kind == "suppressed_gunshot" and quiet > 0.0 and quiet <= 12.5 and quiet < loud * 0.25,
			"suppressed shot: noise %s %.1f m (loud %.0f m; WEAPONS.md 65 -> 11 m)" % [quiet_kind, quiet, loud])
	T.check(P.in_stealth, "a suppressed shot keeps stealth")
	if inv.has_method("remove_attachment"):
		inv.call("remove_attachment", "pistol", "suppressor")
	await _set_stealth(false)


func _test_visibility() -> void:
	await _place(SPOT, 0.0)
	await _equip("fists")
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(13.0)
	await T.wait_physics_frames(4)
	var stand := P.stealth.update_visibility()
	await _tap("crouch")
	await T.wait_physics_frames(4)
	var crouch := P.stealth.update_visibility()
	await _tap("crouch")
	await _set_stealth(true)
	var sneak := P.stealth.update_visibility()
	T.check(stand > 0.95, "standing in daylight: visibility_factor %.2f" % stand)
	T.check(crouch < stand - 0.1 and sneak < stand - 0.2, "crouched %.2f / sneaking %.2f are harder to see" % [crouch, sneak])
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(1.0)
	await T.wait_physics_frames(4)
	P.stealth.refresh_lamps()
	var night := P.stealth.update_visibility()
	var lamp := Node3D.new()
	lamp.name = "TestLamp"
	arena.add_child(lamp)
	lamp.global_position = P.global_position + Vector3(1.5, 6.0, 0.0)
	lamp.add_to_group("street_light")
	P.stealth.refresh_lamps()
	var lit := P.stealth.update_visibility()
	T.check(night < sneak * 0.8, "sneaking in the dark away from lights: %.2f (day %.2f)" % [night, sneak])
	T.check(lit > night + 0.1, "under a street lamp at night: %.2f (dark %.2f)" % [lit, night])
	lamp.queue_free()
	await T.wait_physics_frames(2)
	P.stealth.refresh_lamps()
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(13.0)
	await _set_stealth(false)


func _put_dummy(local: Vector3, yaw: float) -> void:
	if dummy == null:
		dummy = StealthDummy.new()
		dummy.name = "StealthDummy"
		arena.add_child(dummy)
	dummy.reset()
	dummy.global_transform = Transform3D(Basis(Vector3.UP, yaw), arena.at(local))
	await T.wait_physics_frames(2)


func _test_takedowns() -> void:
	var d_spot := SPOT + Vector3(10.0, 0.0, 0.0)
	await _put_dummy(d_spot, 0.0)               # faces -Z: its back is towards +Z
	await _equip("fists")
	# Stealth XP while sneaking near an unaware NPC
	await _place(d_spot + Vector3(-4.0, 0.0, 5.0), 0.0)
	await _set_stealth(true)
	var xp0 := P.stealth.xp_awarded
	Input.action_press("move_right")
	await T.wait_physics_frames(80)
	Input.action_release("move_right")
	T.check(P.stealth.xp_awarded > xp0, "Stealth XP while sneaking near an unaware NPC (+%.3f)" % (P.stealth.xp_awarded - xp0))

	# from behind with fists: silent knock-out
	await _place(d_spot + Vector3(0.0, 0.0, 1.2), 0.0)
	await _set_stealth(true)
	await T.wait_physics_frames(12)
	T.check(P.takedown_target == dummy, "behind an unaware NPC within 1.6 m: takedown offered")
	await T.wait_physics_frames(10)
	T.check(P.interaction.get_prompt_text() == "Takedown", "the 'Takedown' prompt is shown (%s)" % P.interaction.get_prompt_text())
	var lvl0 := Skills.get_level("stealth")
	noises.clear()
	await _tap("melee_heavy")
	var started := await _until(func() -> bool: return P.state_id == "takedown", 4)
	await T.wait_frames(3)
	var anim_td := P.animator != null and P.animator.state == "takedown"
	await _until(func() -> bool: return P.state_id != "takedown", 120)
	T.check(started and anim_td, "melee_heavy starts the takedown (animator 'takedown')")
	T.check(dummy.hits.size() == 1, "one takedown blow landed (%d)" % dummy.hits.size())
	if dummy.hits.size() >= 1:
		var info: Dictionary = dummy.hits[0]
		T.check(bool(info.get("silent", false)) and bool(info.get("takedown", false)), "Dmg info: silent = true, takedown = true")
		T.check(bool(info.get("knockout", false)) and bool(info.get("knockdown", false)) and not dummy.is_dead, "unarmed takedown knocks out (not lethal: %.0f hp)" % float(info.get("amount", 0.0)))
		T.check(info.get("instigator", null) == P and str(info.get("type", "")) == "melee", "damage through the Dmg contract (melee, instigator = player)")
	var player_noise := 0
	for n: Array in noises:
		if n[1] != "footstep" or float(n[0]) > P.get_stealth_noise_radius() + 0.01:
			player_noise += 1
	T.check(player_noise == 0, "no noise event from the takedown (%d)" % player_noise)
	T.check(dummy.stops > 0, "the victim is held still (stop_moving)")
	T.check(Skills.get_level("stealth") > lvl0, "Stealth XP for the takedown (%.2f -> %.2f)" % [lvl0, Skills.get_level("stealth")])
	T.check(P.state_id == "on_foot" and P.in_stealth, "back on foot, still sneaking")

	# knife from behind: silent kill (fire key with a melee weapon)
	await _put_dummy(d_spot, 0.0)
	await _equip("knife")
	await _place(d_spot + Vector3(0.3, 0.0, 1.1), 0.0)
	await _set_stealth(true)
	await T.wait_physics_frames(12)
	var offered_knife := P.takedown_target == dummy
	await _tap("fire")
	var knife_td := await _until(func() -> bool: return P.state_id == "takedown", 4)
	await _until(func() -> bool: return P.state_id != "takedown", 120)
	var k_silent := dummy.hits.size() >= 1 and bool(dummy.hits[0].get("silent", false))
	for h: Dictionary in dummy.hits:
		T.log_line("knife case hit: amount %.1f silent %s takedown %s weapon %s frame-info %s" % [float(h.get("amount", 0.0)), str(h.get("silent", false)), str(h.get("takedown", false)), str(h.get("weapon_id", "")), str(h.get("combo_step", h.get("heavy", "")))])
	T.check(dummy.is_dead and dummy.hits.size() == 1 and k_silent, "knife takedown: a silent kill (offered %s, started %s, hits %d, dead %s, weapon %s)" % [
			offered_knife, knife_td, dummy.hits.size(), dummy.is_dead, str(inv.get("current_id"))])

	# pistol: fire shoots (no takedown), melee_heavy pistol-whips (knock-out)
	await _put_dummy(d_spot, 0.0)
	await _equip("pistol")
	await _place(d_spot + Vector3(0.0, 0.0, 1.2), PI * 0.5)
	await _set_stealth(true)
	await T.wait_physics_frames(12)
	await _tap("fire")
	await T.wait_physics_frames(4)
	T.check(P.state_id != "takedown", "with a firearm the fire key does not start a takedown")
	await _set_stealth(true)
	await T.wait_physics_frames(12)
	await _tap("melee_heavy")
	var whip := await _until(func() -> bool: return P.state_id == "takedown", 4)
	await _until(func() -> bool: return P.state_id != "takedown", 120)
	var silent_ko := false
	for h: Dictionary in dummy.hits:
		silent_ko = silent_ko or (bool(h.get("silent", false)) and bool(h.get("knockout", false)))
	T.check(whip and silent_ko, "melee_heavy with a pistol: silent pistol-whip knock-out")
	await _equip("fists")

	# cases where it must NOT work
	var cases := [
		["from the front", d_spot + Vector3(0.0, 0.0, -1.2), PI, false, 0.0],
		["from the side", d_spot + Vector3(1.2, 0.0, 0.0), PI * 0.5, false, 0.0],
		["out of reach (2.1 m)", d_spot + Vector3(0.0, 0.0, 2.1), 0.0, false, 0.0],
		["alerted NPC", d_spot + Vector3(0.0, 0.0, 1.2), 0.0, true, 0.0],
		["aware NPC (awareness 0.7)", d_spot + Vector3(0.0, 0.0, 1.2), 0.0, false, 0.7],
	]
	for c: Array in cases:
		await _put_dummy(d_spot, 0.0)
		dummy.is_alerted = bool(c[3])
		dummy.awareness = float(c[4])
		await _place(c[1], float(c[2]))
		await _set_stealth(true)
		await T.wait_physics_frames(12)
		var offered := P.takedown_target != null
		await _tap("melee_heavy")
		var went := await _until(func() -> bool: return P.state_id == "takedown", 6)
		var silent := false
		for h: Dictionary in dummy.hits:
			silent = silent or bool(h.get("silent", false))
		T.check(not offered and not went and not silent, "no takedown %s" % str(c[0]))
		await T.wait_physics_frames(40)
	# not sneaking
	await _put_dummy(d_spot, 0.0)
	await _place(d_spot + Vector3(0.0, 0.0, 1.2), 0.0)
	await _set_stealth(false)
	await T.wait_physics_frames(12)
	T.check(P.takedown_target == null, "no takedown without stealth mode")
	await T.wait_physics_frames(30)
	dummy.queue_free()
	dummy = null
	await T.wait_physics_frames(2)


func _test_real_npc() -> void:
	var peds := Game.get_system("peds")
	if peds == null or not peds.has_method("spawn_npc"):
		T.log_line("SKIP real NPC takedown: peds system not running")
		return
	var spot := SPOT + Vector3(20.0, 0.0, 0.0)
	var npc := Game.spawn_npc("civilian_m", arena.at(spot) + Vector3(0.0, 0.05, 0.0), {"yaw": 0.0, "persistent": true, "brain": IdleBrain.new()})
	if not T.check(npc != null and is_instance_valid(npc), "real civilian NPC spawned"):
		return
	await T.wait_physics_frames(40)
	Wanted.clear("cheat")
	var crimes: Array = []
	var on_crime := func(id: String, _p: Vector3, _who: Node) -> void: crimes.append(id)
	EventBus.crime_committed.connect(on_crime)
	await _equip("knife")
	var behind := npc.global_position + npc.global_basis.z * 1.15
	P.teleport(behind + Vector3(0.0, 0.03, 0.0), npc.global_rotation.y)
	await T.wait_physics_frames(10)
	await _set_stealth(true)
	await T.wait_physics_frames(12)
	T.check(P.takedown_target == npc, "takedown offered behind a real (unaware) civilian")
	await _tap("fire")
	await _until(func() -> bool: return P.state_id == "takedown", 4)
	await _until(func() -> bool: return P.state_id != "takedown", 120)
	T.check(npc.get("is_dead") == true, "real civilian killed by the knife takedown")
	await T.wait_seconds(3.0)
	T.check(Wanted.level == 0, "nobody saw it: no wanted level (crimes recorded: %s)" % str(crimes))
	EventBus.crime_committed.disconnect(on_crime)
	await _set_stealth(false)
