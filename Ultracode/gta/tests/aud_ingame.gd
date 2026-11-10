extends Node
## Audio integration smoke test in the real game (world + player + vehicles, soft dependencies):
##   tools\godot.ps1 -Mode headless -Frames 2400 -UserArgs '--test=aud_ingame'
## * ambience samples the real world (district, sea proximity, altitude) at a few named locations;
## * the radio starts when the real player enters a real car, cycles with the input action and
##   stops on exit; a bicycle / police cruiser stays silent.
## Parts whose neighbours are missing are logged as skipped, not failed.

var T: Node = TestHarness


func _ready() -> void:
	await T.wait_frames(20)
	var amb: Node = Game.get_system("ambience")
	var radio: Node = Game.get_system("radio")
	T.check(amb != null and radio != null, "radio + ambience systems are running in the full game")
	if amb == null or radio == null:
		T.finish()
		return
	amb.set("spot_sounds", false)
	radio.set("announce", false)
	await _ambience_walk(amb)
	await _radio_drive(radio)
	T.log_line("audio stats: " + str(Audio.get_stats()))
	T.finish()


func _ambience_walk(amb: Node) -> void:
	if Game.world == null or not Game.world.has_method("get_district") or not Game.has_player():
		T.log_line("SKIP ambience walk: world or player missing")
		return
	var seen := {}
	for loc: String in ["downtown_plaza", "industrial_yard", "hill_top", "beach", "marina_dock", "airport_hangar", "residential_park"]:
		var xf: Transform3D = Game.get_location(loc)
		if Game.player.has_method("teleport"):
			Game.player.call("teleport", xf.origin + Vector3(0, 0.5, 0), 0.0)
		else:
			Game.player.global_position = xf.origin + Vector3(0, 0.5, 0)
		await T.wait_frames(8)
		amb.call("snap")
		var ctx: Dictionary = amb.call("get_context")
		var dom := str(amb.call("get_dominant_layer"))
		seen[str(ctx.get("district", ""))] = dom
		T.log_line("%-18s district=%-12s sea=%.2f alt=%.1f day=%.2f rain=%.2f -> dominant bed: %s" % [loc, str(ctx.get("district", "")),
			float(ctx.get("sea", 0.0)), float(ctx.get("altitude", 0.0)), float(ctx.get("daylight", 0.0)), float(ctx.get("rain", 0.0)), dom])
	T.check(seen.size() >= 4, "ambience saw %d different districts from the real world: %s" % [seen.size(), str(seen)])
	var gains: Dictionary = amb.call("get_layer_gains")
	var playing := 0
	for p: Variant in (amb.get("_players") as Dictionary).values():
		if (p as AudioStreamPlayer).playing:
			playing += 1
	T.check(playing >= 1, "ambience beds are playing in the real world (%d beds, gains %s)" % [playing, str(gains)])


func _radio_drive(radio: Node) -> void:
	if not Game.has_player() or Game.get_system("vehicles") == null or not Game.player.has_method("enter_vehicle"):
		T.log_line("SKIP radio drive: player or vehicle system missing")
		return
	var saved: Variant = Settings.get_value("radio_station")
	var spawn: Transform3D = Game.get_location("spawn_start")
	if Game.player.has_method("teleport"):
		Game.player.call("teleport", spawn.origin + Vector3(0, 0.5, 0), 0.0)
	await T.wait_frames(10)
	var car: Node3D = Game.spawn_vehicle("sedan", Transform3D(Basis.IDENTITY, spawn.origin + Vector3(4.0, 1.0, 0.0)), {"owner_tag": "player"})
	if car == null:
		T.log_line("SKIP radio drive: sedan could not be spawned")
		return
	await T.wait_frames(30)
	radio.call("set_station", "boogie_bay")
	T.check(not radio.call("is_listening"), "radio silent on foot")
	Game.player.call("enter_vehicle", car, 0)
	var waited := 0
	while waited < 300 and not radio.call("is_listening"):
		await T.wait_frames(5)
		waited += 5
	await T.wait_frames(40)
	T.check(Game.get_player_vehicle() == car, "player sits in the spawned sedan (after %d frames)" % waited)
	T.check(radio.call("is_listening") and radio.call("is_playing"), "radio plays in a real car: " + str(radio.call("get_now_playing")))
	Input.action_press("radio_next")
	await T.wait_frames(2)
	Input.action_release("radio_next")
	await T.wait_frames(20)
	T.check(str(radio.call("get_station")) == "breakwater", "radio_next works while driving (now %s)" % str(radio.call("get_station")))
	if Game.player.has_method("exit_vehicle"):
		Game.player.call("exit_vehicle")
		waited = 0
		while waited < 400 and radio.call("is_listening"):
			await T.wait_frames(5)
			waited += 5
		await T.wait_frames(60)
		T.check(not radio.call("is_listening") and not radio.call("is_playing"), "radio stops after leaving the car (after %d frames)" % waited)
	# a police cruiser has no entertainment radio
	var cruiser: Node3D = Game.spawn_vehicle("police_cruiser", Transform3D(Basis.IDENTITY, spawn.origin + Vector3(-5.0, 1.0, 0.0)), {"owner_tag": "player"})
	if cruiser != null:
		await T.wait_frames(120)
		# walk-up entry aborts when the door is > 9 m away: stand next to the cruiser first;
		# the player may also still be finishing the exit transition, so retry a few times
		if Game.player.has_method("teleport"):
			Game.player.call("teleport", cruiser.global_position + Vector3(-2.5, 0.5, 0.0), 0.0)
		await T.wait_frames(10)
		waited = 0
		while waited < 600 and Game.get_player_vehicle() != cruiser:
			if waited % 120 == 0:
				Game.player.call("enter_vehicle", cruiser, 0)
			await T.wait_frames(5)
			waited += 5
		await T.wait_frames(40)
		if Game.get_player_vehicle() == cruiser:
			T.check(not radio.call("is_listening") and not radio.call("is_playing"), "no music radio in the police cruiser (entered after %d frames)" % waited)
			# leave the cruiser again so the test does not end with the player parented to a seat
			if Game.player.has_method("exit_vehicle"):
				Game.player.call("exit_vehicle")
				waited = 0
				while waited < 400 and Game.get_player_vehicle() != null:
					await T.wait_frames(5)
					waited += 5
				await T.wait_frames(30)
		else:
			var can: Variant = cruiser.call("can_enter", Game.player) if cruiser.has_method("can_enter") else "?"
			T.log_line("SKIP cruiser check: player did not get into the cruiser (can_enter=%s, player vehicle=%s)" % [str(can), str(Game.get_player_vehicle())])
	Settings.set_value("radio_station", saved if saved != null else "")
