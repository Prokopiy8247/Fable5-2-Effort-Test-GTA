extends Node
## UI wave 3 live integration (headless): the new HUD widgets and screens against the REAL player,
## radio, taxi, garage, emergency and activities systems (whatever exists at run time - a missing
## neighbour is logged and skipped, never faked here).
##   tools\godot.ps1 -Mode headless -Frames 3000 -UserArgs '--test=ui3_live','--disable=peds,police,wildlife,ambience,pickups'
## Covers: stealth eye from Player.set_stealth, skydive -> HUD altimeter (freefall, pull cue,
## parachute deploy with the jump key), radio wheel in a real car tuning the real radio, phone
## contact availability + a real taxi call, the activity card against activities.get_hud_info().

var T: Variant = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	T = TestHarness
	await T.wait_frames(10)
	await _run()
	UI.close_all_screens()
	T.finish()


func _action(action: String, pressed: bool = true) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await T.wait_frames(3)


func _public_state(pl: Node) -> String:
	var st: Variant = pl.get("state")
	if st is Object and is_instance_valid(st):
		return str((st as Object).get("public_name"))
	return ""


func _run() -> void:
	var hud := UI.hud as HudRoot
	var pl: Node3D = Game.player
	T.check(hud != null and pl != null, "HUD and the real player exist")
	if hud == null or pl == null:
		return
	var plaza := Game.get_location("downtown_plaza").origin
	await _stealth(hud, pl)
	await _skydive(hud, pl, plaza)
	await _radio(hud, pl, plaza)
	await _phone(pl)
	await _activities(hud)


func _stealth(hud: HudRoot, pl: Node3D) -> void:
	if not pl.has_method("set_stealth"):
		T.log_line("player has no set_stealth - skipped")
		return
	pl.call("set_stealth", true)
	await T.wait_frames(6)
	T.check(bool(hud.get_state()["stealth"]), "real stealth -> HUD stealth eye")
	pl.call("set_stealth", false)
	await T.wait_frames(20)
	T.check(not bool(hud.get_state()["stealth"]), "leaving stealth hides the eye")


func _skydive(hud: HudRoot, pl: Node3D, plaza: Vector3) -> void:
	if not pl.has_method("give_parachute") or not ("altitude_agl" in pl):
		T.log_line("player has no parachute support yet - skipped")
		return
	pl.call("give_parachute")
	pl.call("teleport", plaza + Vector3(0.0, 300.0, 0.0), 0.0)
	var seen := false
	for i in 120:
		await T.wait_physics_frames(1)
		if _public_state(pl) == "freefall":
			seen = true
			break
	T.check(seen, "falling from 300 m with a pack enters freefall (state %s)" % _public_state(pl))
	if not seen:
		return
	await T.wait_frames(4)
	var s := hud.get_state()
	T.check(bool(s["altimeter"]), "HUD altimeter shows in real freefall")
	T.check(absf(float(s["altitude"]) - float(pl.get("altitude_agl"))) < 3.0, "altimeter reads player.altitude_agl (%.0f vs %.0f)" % [float(s["altitude"]), float(pl.get("altitude_agl"))])
	T.check(hud.altimeter.vspeed < -1.0, "vertical speed is negative while falling (%.1f)" % hud.altimeter.vspeed)
	T.check(hud.minimap.air_mode, "minimap uses the aircraft range while skydiving")
	Input.action_press("jump")
	await T.wait_physics_frames(3)
	Input.action_release("jump")
	var open := false
	for i in 60:
		await T.wait_physics_frames(1)
		if _public_state(pl) == "parachute":
			open = true
			break
	T.check(open, "jump deploys the canopy (state %s)" % _public_state(pl))
	await T.wait_frames(4)
	T.check(open and hud.altimeter.canopy and not hud.altimeter.is_pull_warning(), "HUD shows CANOPY after deploying")
	pl.call("teleport", plaza + Vector3(0.0, 0.5, 0.0), 0.0)
	for i in 40:
		await T.wait_physics_frames(1)
		if not bool(hud.get_state()["altimeter"]):
			break
	T.check(not bool(hud.get_state()["altimeter"]), "altimeter hides back on the ground (state %s)" % _public_state(pl))


func _radio(_hud: HudRoot, pl: Node3D, plaza: Vector3) -> void:
	var radio := Game.get_system("radio")
	if radio == null:
		T.log_line("no radio system - skipped")
		return
	var xf := Transform3D(Basis.IDENTITY, plaza + Vector3(4.0, 0.6, 0.0))
	var car := Game.spawn_vehicle("sedan", xf, {})
	if car == null:
		T.log_line("could not spawn a sedan - radio wheel skipped")
		return
	await T.wait_frames(4)
	pl.call("enter_vehicle", car, 0, true)
	var listening := false
	for i in 90:
		await T.wait_frames(1)
		if bool(radio.call("is_listening")):
			listening = true
			break
	T.check(listening, "radio listens in a real sedan")
	if listening:
		var before := str(radio.call("get_station"))
		await _action("radio_wheel", true)
		var wheel: Variant = UI.get_screen("radio_wheel")
		T.check(wheel != null, "Y opens the radio wheel in a real car")
		if wheel != null:
			var ids: PackedStringArray = wheel.get_station_ids()
			T.check(ids.size() >= 2 and ids[0] == "off", "wheel lists the real stations (%d)" % ids.size())
			var target := ids[ids.size() - 1] if ids[ids.size() - 1] != before else ids[1]
			wheel.select_station(target)
			await _action("radio_wheel", false)
			T.check(str(radio.call("get_station")) == target, "release tunes the real radio to %s" % target)
	if pl.has_method("exit_vehicle"):
		pl.call("exit_vehicle")
	await T.wait_frames(30)


func _phone(pl: Node3D) -> void:
	await _action("phone")
	var phone: Variant = UI.get_screen("phone")
	T.check(phone != null, "phone opens with the real systems")
	if phone == null:
		return
	for c: String in ["taxi", "mechanic", "ambulance", "fire"]:
		var sys_name: String = {"taxi": "taxi", "mechanic": "garage", "ambulance": "emergency", "fire": "emergency"}[c]
		var st: String = phone.service_status(c)
		if Game.get_system(sys_name) != null:
			T.check(st == "", "contact %s available with the real %s system (%s)" % [c, sys_name, st])
		else:
			T.check(st != "", "contact %s greyed out without a %s system" % [c, sys_name])
	if Game.get_system("taxi") != null:
		phone.launch("contacts")
		phone.activate_row(phone.find_row("taxi"))
		await T.wait_frames(70)
		T.check(str(phone.last_action).begins_with("taxi:"), "real taxi call answered (%s)" % phone.last_action)
		T.log_line("real taxi call result: %s" % phone.last_action)
		await T.wait_frames(120)
		var tx := Game.get_system("taxi")
		if tx != null and tx.has_method("cancel_taxi"):
			tx.call("cancel_taxi", "test")
	if Game.get_system("emergency") != null:
		phone.show_page("contacts")
		phone.activate_row(phone.find_row("ambulance"))
		await T.wait_frames(70)
		T.log_line("real ambulance call result: %s" % phone.last_action)
		T.check(str(phone.last_action).begins_with("ambulance:"), "real emergency call answered (%s)" % phone.last_action)
		await T.wait_frames(120)
	UI.close_screen("phone")
	await T.wait_frames(3)
	T.check(not Game.is_input_locked(), "input unlocked after the phone")
	pl.call("teleport", pl.global_position, 0.0)


func _activities(hud: HudRoot) -> void:
	var acts := Game.get_system("activities")
	if acts == null or not acts.has_method("get_hud_info"):
		T.log_line("no activities system - skipped")
		return
	var info: Variant = acts.call("get_hud_info")
	T.check(info is Dictionary, "activities.get_hud_info() returns a Dictionary")
	await T.wait_frames(40)
	T.check(str(hud.get_state()["activity"]) == "" or bool((info as Dictionary).get("active", false)), "no activity card while idle")
	if acts.has_method("_has_external_widget"):
		T.check(bool(acts.call("_has_external_widget")), "activities system detects the UI activity widget (no fallback HUD)")
