extends Node
## plr2_respawn - headless test of the "respawn" world system (W2.5): death -> "DOWN" banner, slow
## motion, fade, hospital respawn with a medical fee, cleared wanted level, time advance,
## reset_for_respawn() on systems, weapons kept; Wanted.bust() -> hands up, "ARRESTED" banner,
## police station, fine, ammunition confiscated (weapons kept), cleared wanted level; and the
## out-of-world rescue (under the terrain -> back on the last safe ground).
##
##   tools\godot.ps1 -Mode headless -Frames 3600 -TimeoutSec 300 `
##       -UserArgs '--test=plr2_respawn','--disable=traffic,peds,police','--test-timeout=240'

const Arena := preload("res://gta/tests/plr_arena.gd")


class ResetProbe extends Node:
	var resets: int = 0

	func reset_for_respawn() -> void:
		resets += 1


var P: Player = null
var arena: Arena = null
var T: Node = null
var R: Node = null
var probe: ResetProbe = null


func _ready() -> void:
	T = TestHarness
	await _run()


func _run() -> void:
	P = Game.player as Player
	R = Game.get_system("respawn")
	if not T.check(P != null and R != null, "player and the respawn system are registered"):
		T.finish(false, "missing respawn system")
		return
	arena = Arena.new()
	Game.main.add_child(arena)
	probe = ResetProbe.new()
	probe.name = "ResetProbe"
	add_child(probe)
	Game.register_system("plr2_reset_probe", probe)
	await T.wait_physics_frames(5)
	await _test_death()
	await _test_busted()
	await _test_rescue()
	Game.systems.erase("plr2_reset_probe")
	T.finish(true, "respawn")


func _until(cond: Callable, timeout_frames: int) -> bool:
	for i in timeout_frames:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _banner_text() -> String:
	var b: Variant = UI.get("_banner")
	if b is Object and is_instance_valid(b) and (b as Object).has_method("get_text"):
		return str((b as Object).call("get_text"))
	return ""


func _hours_since(h0: float) -> float:
	return fposmod(WorldClock.hour - h0, 24.0)


func _test_death() -> void:
	P.teleport(arena.at(Vector3(0.0, 0.03, 50.0)), 0.0)
	await T.wait_physics_frames(10)
	if P.inventory != null and P.inventory.has_method("give_weapon"):
		P.inventory.call("give_weapon", "pistol")
		P.inventory.call("refill_all")
	Game.set_money(1000)
	Wanted.set_level(2)
	var h0 := WorldClock.hour
	var resets0 := probe.resets
	T.check(Wanted.level == 2, "wanted level 2 before dying")
	P.kill("bullet")
	await T.wait_frames(3)
	T.check(P.is_dead and P.state_id == "dead", "the player is dead (%s)" % P.state_id)
	T.check(_banner_text() == "DOWN", "original 'DOWN' banner ('%s')" % _banner_text())
	T.check(Engine.time_scale < 0.9, "brief slow motion (time scale %.2f)" % Engine.time_scale)
	var faded := await _until(func() -> bool: return float(UI.call("get_fade_alpha")) > 0.95, 900)
	T.check(faded, "the screen fades out")
	var back := await _until(func() -> bool: return not P.is_dead, 900)
	T.check(back and P.state_id == "on_foot", "the player is alive again (state %s)" % P.state_id)
	T.check(is_equal_approx(Engine.time_scale, 1.0), "slow motion released (%.2f)" % Engine.time_scale)
	var want: Transform3D = R.call("respawn_transform", "hospital")
	var d := P.global_position.distance_to(want.origin)
	T.check(d < 1.5, "respawned at the hospital (%.2f m from %s)" % [d, str(want.origin)])
	T.check(int(R.get("last_fee")) == 200 and Game.money == 800, "medical fee charged ($%d of $1000 left)" % Game.money)
	T.check(Wanted.level == 0, "wanted level cleared (%d)" % Wanted.level)
	var dh := _hours_since(h0)
	T.check(dh > 3.8 and dh < 5.0, "a few in-game hours passed (%.2f h)" % dh)
	T.check(probe.resets == resets0 + 1, "reset_for_respawn() called on the systems (%d)" % (probe.resets - resets0))
	T.check(is_equal_approx(P.health, P.max_health), "full health after the respawn (%.0f)" % P.health)
	if P.inventory != null and P.inventory.has_method("get_ammo"):
		var a: Dictionary = P.inventory.call("get_ammo", "pistol")
		T.check(bool(P.inventory.call("has_weapon", "pistol")) and int(a["in_mag"]) + int(a["reserve"]) > 0,
				"weapons and ammunition are kept after dying (%s)" % str(a))
	await _until(func() -> bool: return float(UI.call("get_fade_alpha")) < 0.05, 300)
	T.check(float(UI.call("get_fade_alpha")) < 0.05, "the screen fades back in")


func _test_busted() -> void:
	P.teleport(arena.at(Vector3(6.0, 0.03, 50.0)), 0.0)
	await T.wait_physics_frames(10)
	if P.inventory != null and P.inventory.has_method("refill_all"):
		P.inventory.call("equip", "pistol")
		P.inventory.call("refill_all")
	await T.wait_physics_frames(20)
	Game.set_money(1000)
	Wanted.set_level(1)
	var h0 := WorldClock.hour
	if Wanted.has_method("bust"):
		Wanted.call("bust")
	else:
		EventBus.player_busted.emit()
	await T.wait_frames(3)
	T.check(P.state_id == "busted" and P.animator.state == "surrender", "busted: hands up (%s / %s)" % [P.state_id, P.animator.state])
	T.check(_banner_text() == "ARRESTED", "original 'ARRESTED' banner ('%s')" % _banner_text())
	T.check(not P.has_control() or P.state_id == "busted", "no control while arrested")
	var back := await _until(func() -> bool: return P.state_id == "on_foot", 900)
	T.check(back, "released after processing (state %s)" % P.state_id)
	var want: Transform3D = R.call("respawn_transform", "police_station")
	var d := P.global_position.distance_to(want.origin)
	T.check(d < 1.5, "released at the police station (%.2f m from %s)" % [d, str(want.origin)])
	T.check(int(R.get("last_fee")) == 500 and Game.money == 500, "fine charged ($%d of $1000 left)" % Game.money)
	T.check(Wanted.level == 0, "wanted level cleared (%d)" % Wanted.level)
	var dh := _hours_since(h0)
	T.check(dh > 5.8 and dh < 7.0, "the night in custody advanced the clock (%.2f h)" % dh)
	if P.inventory != null and P.inventory.has_method("get_ammo"):
		var a: Dictionary = P.inventory.call("get_ammo", "pistol")
		T.check(bool(P.inventory.call("has_weapon", "pistol")), "weapons are kept")
		T.check(int(a["in_mag"]) == 0 and int(a["reserve"]) == 0, "ammunition confiscated (%s)" % str(a))
		T.check(str(P.inventory.get("current_id")) == "fists", "released empty-handed (%s)" % str(P.inventory.get("current_id")))
	await _until(func() -> bool: return float(UI.call("get_fade_alpha")) < 0.05, 300)


func _test_rescue() -> void:
	if Game.world == null:
		T.log_line("SKIP rescue: no world")
		return
	var spawn := Game.get_location("spawn_start").origin
	P.teleport(spawn + Vector3(0.0, 0.2, 0.0), 0.0)
	var safe := await _until(func() -> bool: return P.grounded and P.state_id == "on_foot" and P.last_safe_position.distance_to(P.global_position) < 0.5, 120)
	T.check(safe, "standing on the island records a safe position (%s)" % str(P.last_safe_position))
	var safe_pos := P.last_safe_position
	var n0 := int(R.get("rescue_count"))
	var g := Game.ground_height(spawn.x + 4.0, spawn.z + 4.0)
	P.teleport(Vector3(spawn.x + 4.0, g - 15.0, spawn.z + 4.0), 0.0)
	var rescued := await _until(func() -> bool: return int(R.get("rescue_count")) > n0, 240)
	T.log_line("rescue: at %s state %s safe %s" % [str(P.global_position), P.state_id, str(P.last_safe_position)])
	await T.wait_frames(5)
	T.log_line("rescue +5: at %s state %s" % [str(P.global_position), P.state_id])
	T.check(rescued, "falling under the terrain triggers the rescue")
	T.check(P.global_position.distance_to(safe_pos) < 1.5 and not P.is_dead,
			"... back on the last safe ground (%.2f m away)" % P.global_position.distance_to(safe_pos))
