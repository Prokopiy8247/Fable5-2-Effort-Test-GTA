extends Node
## POLICE + respawn integration (headless, the REAL respawn system enabled): 1 star at the downtown plaza,
## an officer cuffs the idle, unarmed player -> Wanted.bust() -> the respawn system's arrest flow (banner,
## fade, fine, ammunition taken, reset_for_respawn on every system) -> the player stands at the police
## station, the level is 0, the police system dropped the episode's units and rebuilds its ambient
## presence around the station. Then 2 stars again and the player is shot dead -> hospital, level 0.
##   tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 360 -UserArgs '--test=pol_bust_flow','--test-timeout=340','--seed=21','--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,debug'

var T: Node
var _busted: int = 0
var _died: int = 0
var _respawned: int = 0


func _ready() -> void:
	T = TestHarness
	EventBus.player_busted.connect(func() -> void: _busted += 1)
	EventBus.player_died.connect(func(_c: String) -> void: _died += 1)
	EventBus.player_respawned.connect(func(_p: Vector3) -> void: _respawned += 1)
	await T.wait_seconds(1.0)
	await _run()
	Wanted.clear("cheat")
	T.finish()


func _run() -> void:
	var pol := Game.get_system("police")
	var rs := Game.get_system("respawn")
	var p := Game.player
	if not T.check(pol != null and rs != null and p != null, "police, respawn system and player present"):
		return
	var plaza := Game.get_location("downtown_plaza")
	p.call("teleport", plaza.origin, 0.0)
	var inv: Node = p.get("inventory")
	if inv != null and inv.has_method("holster"):
		inv.call("holster")
	await T.wait_seconds(1.0)
	var money0 := int(Game.money)
	Wanted.set_level(1)
	var t := 0.0
	while t < 60.0 and _busted == 0:
		await T.wait_seconds(0.5)
		t += 0.5
	if not T.check(_busted == 1, "1 star: arrested by an officer (%.1f s)" % t):
		return
	# the respawn system's arrest flow: hold, fade, fine, station
	t = 0.0
	while t < 15.0 and _respawned == 0:
		await T.wait_seconds(0.25)
		t += 0.25
	await T.wait_seconds(1.0)
	var st := Game.get_location("police_station")
	var d := Vector2(p.global_position.x - st.origin.x, p.global_position.z - st.origin.z).length()
	T.check(_respawned >= 1 and d < 40.0, "released at the police station (%.1f m from it, %.1f s)" % [d, t])
	T.check(Wanted.level == 0 and Wanted.last_clear_reason == "busted", "level 0 after the arrest")
	T.check(int(Game.money) < money0 or bool(Game.flags.get("free_shopping", false)), "a fine was charged ($%d -> $%d)" % [money0, int(Game.money)])
	var info: Dictionary = pol.call("get_debug_info")
	var modes: Dictionary = info.get("unit_modes", {})
	var busy := 0
	for k: String in modes.keys():
		if k != "patrol":
			busy += int(modes[k])
	T.check(busy == 0, "the episode's units were dropped by reset_for_respawn (%s)" % str(modes))
	# the ambient presence comes back around the station (beat officers, parked cruisers, patrols)
	t = 0.0
	var amb := false
	while t < 20.0 and not amb:
		await T.wait_seconds(0.5)
		t += 0.5
		info = pol.call("get_debug_info")
		amb = int(info.get("officers_alive", 0)) >= 2 and int(info.get("station_cars", 0)) >= 1
	T.check(amb, "ambient police rebuilt around the station (%d officers, %d parked cruisers)" % [int(info.get("officers_alive", 0)), int(info.get("station_cars", 0))])
	# killed at 2 stars -> hospital, level 0, police reset again
	await T.wait_seconds(1.0)
	Wanted.set_level(2)
	await T.wait_seconds(1.0)
	_respawned = 0
	p.call("kill", "shot")
	t = 0.0
	while t < 20.0 and _respawned == 0:
		await T.wait_seconds(0.25)
		t += 0.25
	await T.wait_seconds(1.0)
	var hosp := Game.get_location("hospital")
	var dh := Vector2(p.global_position.x - hosp.origin.x, p.global_position.z - hosp.origin.z).length()
	T.check(_died >= 1 and _respawned >= 1 and dh < 50.0, "death -> respawned at the hospital (%.1f m, %.1f s)" % [dh, t])
	T.check(Wanted.level == 0, "level 0 after the death")
	info = pol.call("get_debug_info")
	modes = info.get("unit_modes", {})
	busy = 0
	for k: String in modes.keys():
		if k != "patrol":
			busy += int(modes[k])
	T.check(busy == 0, "no pursuing units left after the death (%s)" % str(modes))
