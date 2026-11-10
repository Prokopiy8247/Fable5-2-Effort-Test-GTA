extends Node
## Audio module test (works headless with the Dummy audio driver):
##   tools\godot.ps1 -Mode headless -Frames 3000 -UserArgs '--test=aud_api','--no_player','--disable=world,traffic,peds,police'
##
## Covers: every canonical sound id resolves to a stream, loops are flagged as loops, sample
## formats / lengths, bus layout + limiter + underwater low-pass, voice pools (no growth,
## stealing, culling, de-duplication, pitch variation), loop players (incl. horn sustain loops,
## checked sample-exactly), the radio system with a simulated vehicle, and the ambience system
## with fake districts / times / weather.

var T: Node = TestHarness

var _radio_events: Array = []


func _ready() -> void:
	await T.wait_frames(5)
	_test_streams()
	await _test_buses()
	await _test_pools()
	_test_loop_players()
	await _test_radio()
	await _test_ambience()
	await _test_event_glue()
	var stats: Dictionary = Audio.get_stats()
	T.log_line("final audio stats: " + str(stats))
	T.finish()


# --- streams ----------------------------------------------------------------------------------

func _test_streams() -> void:
	var missing: PackedStringArray = []
	var bad_loop: PackedStringArray = []
	var pcm := 0
	var qoa := 0
	var other := 0
	var loops := 0
	for id: String in Audio.SOUND_IDS:
		var stream: AudioStream = Audio.get_stream(id)
		if stream == null:
			missing.append(id)
			continue
		var wav := stream as AudioStreamWAV
		if wav == null:
			continue
		match wav.format:
			AudioStreamWAV.FORMAT_16_BITS: pcm += 1
			AudioStreamWAV.FORMAT_QOA: qoa += 1
			_: other += 1
		var frames := int(round(wav.get_length() * float(wav.mix_rate)))
		if Audio.is_loop_id(id):
			loops += 1
			if wav.loop_mode != AudioStreamWAV.LOOP_FORWARD or wav.loop_begin != 0 or wav.loop_end != frames or frames <= 0:
				bad_loop.append(id)
		elif wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			bad_loop.append(id)
	print("AUD_MISSING: ", ", ".join(missing) if not missing.is_empty() else "(none)")
	T.check(Audio.SOUND_IDS.size() == 120, "canonical id list has 120 entries (got %d)" % Audio.SOUND_IDS.size())
	T.check(missing.is_empty(), "every canonical sound id resolves to a stream (missing: %d)" % missing.size())
	T.check(bad_loop.is_empty(), "loop flags are right for all ids (wrong: %s)" % ", ".join(bad_loop))
	T.check(loops == 31, "31 canonical *_loop ids are configured as forward loops (got %d)" % loops)
	T.log_line("formats: %d PCM16, %d QOA, %d other" % [pcm, qoa, other])
	T.check(other == 0, "all streams are PCM16 or QOA")
	# ambience beds are 6-12 s long
	for id: String in ["rain_loop", "rain_heavy_loop", "wind_loop", "ocean_loop", "city_loop", "industrial_loop",
			"park_birds_loop", "night_crickets_loop", "airport_loop", "harbor_loop"]:
		var st: AudioStream = Audio.get_stream(id)
		var length := st.get_length() if st != null else 0.0
		T.check(length >= 6.0 and length <= 12.01, "%s is a 6-12 s bed (%.2f s)" % [id, length])
	# unknown ids are silent and harmless
	T.check(not Audio.has_sound("no_such_sound"), "unknown id has no stream")
	T.check(Audio.get_stream("../project") == null and Audio.get_stream("") == null, "odd ids resolve to null")
	Audio.play("no_such_sound")
	Audio.play_at("no_such_sound", Vector3.ZERO)
	Audio.play_ui("no_such_sound")
	T.check(int(Audio.get_stats()["unknown"]) >= 3, "unknown ids are counted, not played")
	# radio music
	var stations: Array = Registry.all("radio_stations")
	T.check(stations.size() == 5, "5 radio stations registered (got %d)" % stations.size())
	var radio_ok := true
	for def: Variant in stations:
		var tracks: Array = (def as Dictionary).get("tracks", [])
		if tracks.size() != 2:
			radio_ok = false
		for t: Variant in tracks:
			var rs := Audio.get_stream(str(t)) as AudioStreamWAV
			if rs == null or rs.loop_mode != AudioStreamWAV.LOOP_FORWARD or rs.get_length() < 30.0 or rs.get_length() > 50.0:
				radio_ok = false
				T.log_line("radio track problem: " + str(t))
	T.check(radio_ok, "every station has 2 looping tracks of 30-50 s")
	T.check(Audio.get_sound_ids().size() >= 130, "get_sound_ids lists canonical ids + radio loops (%d)" % Audio.get_sound_ids().size())
	T.check(Audio.get_category("pistol_shot") == "weapon" and Audio.get_category("engine_car_loop") == "engine"
		and Audio.get_category("ui_click") == "ui" and Audio.get_category("footstep_sand") == "footstep",
		"category lookup")


# --- buses ------------------------------------------------------------------------------------

func _lowpass_state(bus: String) -> Array:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return [false, 0.0, false]
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectLowPassFilter:
			return [AudioServer.is_bus_effect_enabled(idx, i), (fx as AudioEffectLowPassFilter).cutoff_hz, true]
	return [false, 0.0, false]


func _test_buses() -> void:
	var all_buses := true
	for bus: String in ["Master", "SFX", "Weapons", "Engine", "Music", "Ambience", "UI"]:
		if AudioServer.get_bus_index(bus) < 0:
			all_buses = false
			T.log_line("bus missing: " + bus)
	T.check(all_buses, "bus layout Master/SFX/Weapons/Engine/Music/Ambience/UI exists")
	T.check(AudioServer.get_bus_send(AudioServer.get_bus_index("Weapons")) == &"SFX"
		and AudioServer.get_bus_send(AudioServer.get_bus_index("Engine")) == &"SFX"
		and AudioServer.get_bus_send(AudioServer.get_bus_index("Music")) == &"Master", "bus sends are right")
	var limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			limiter = true
	T.check(limiter, "Master has a hard limiter")
	T.check(not _lowpass_state("SFX")[0], "underwater low-pass is off by default")
	Audio.set_underwater(true)
	await T.wait_frames(40)
	var on_all := true
	for bus: String in ["SFX", "Music", "Ambience"]:
		var st := _lowpass_state(bus)
		if not st[0] or float(st[1]) > 1200.0:
			on_all = false
			T.log_line("low-pass state %s: %s" % [bus, str(st)])
	T.check(on_all and Audio.is_underwater(), "set_underwater(true) muffles SFX / Music / Ambience")
	T.check(not _lowpass_state("UI")[2], "UI bus has no underwater filter")
	Audio.set_underwater(false)
	await T.wait_frames(40)
	T.check(not _lowpass_state("SFX")[0] and not _lowpass_state("Music")[0] and not Audio.is_underwater(),
		"set_underwater(false) removes the filter")
	EventBus.player_submerged.emit(true)
	await T.wait_frames(3)
	T.check(Audio.is_underwater(), "EventBus.player_submerged also drives the filter")
	EventBus.player_submerged.emit(false)
	await T.wait_frames(40)


# --- pools ------------------------------------------------------------------------------------

func _voice_children() -> int:
	var n := 0
	for c: Node in Audio.get_children():
		if str(c.name).begins_with("Voice"):
			n += 1
	return n


func _listener() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO


func _test_pools() -> void:
	var s0: Dictionary = Audio.get_stats()
	var voices0 := _voice_children()
	var children0 := Audio.get_child_count()
	T.check(int(s0["pool_2d"]) == 12 and int(s0["pool_3d"]) == 32 and voices0 == 44, "pools are 12 + 32 voices")
	var one_shots: Array[String] = []
	for id: String in Audio.SOUND_IDS:
		if not Audio.is_loop_id(id):
			one_shots.append(id)
	var origin := _listener()
	# 300 positional + 100 non-positional one-shots in a burst
	for i in 300:
		var id: String = one_shots[i % one_shots.size()]
		var a := float(i) * 0.7
		var radius := 4.0 + float((i * 37) % 100) * 0.15
		Audio.play_at(id, origin + Vector3(cos(a) * radius, 0.0, sin(a) * radius), -6.0, 1.0, 80.0)
	for i in 100:
		Audio.play(one_shots[(i * 7) % one_shots.size()], -12.0)
	await T.wait_frames(2)
	var s1: Dictionary = Audio.get_stats()
	T.log_line("after burst: " + str(s1))
	T.check(_voice_children() == voices0 and Audio.get_child_count() == children0, "pools did not grow (children %d -> %d)" % [children0, Audio.get_child_count()])
	T.check(int(s1["active_3d"]) <= 32 and int(s1["active_2d"]) <= 12, "active voices stay within the pools")
	T.check(int(s1["played_3d"]) - int(s0["played_3d"]) >= 60 and int(s1["played_2d"]) - int(s0["played_2d"]) >= 50,
		"burst was played through the pools (%d positional, %d non-positional, %d dropped as less important)" % [
		int(s1["played_3d"]) - int(s0["played_3d"]), int(s1["played_2d"]) - int(s0["played_2d"]), int(s1["dropped"]) - int(s0["dropped"])])
	T.check(int(s1["stolen"]) > int(s0["stolen"]), "voice stealing happened under load (%d)" % (int(s1["stolen"]) - int(s0["stolen"])))
	# a loop id played as a one-shot must not loop forever
	Audio.play_at("siren_police_loop", origin + Vector3(3, 0, 3))
	var looping_voice := false
	for p: Variant in Audio.get("_voices_3d"):
		var st := (p as AudioStreamPlayer3D).stream as AudioStreamWAV
		if (p as AudioStreamPlayer3D).playing and st != null and st.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			looping_voice = true
	T.check(not looping_voice, "pooled voices never hold a looping stream")
	Audio.stop_all()
	await T.wait_frames(2)
	var s2: Dictionary = Audio.get_stats()
	T.check(int(s2["active_3d"]) == 0 and int(s2["active_2d"]) == 0, "stop_all() silences every pooled voice")
	# culling: far beyond the audible range
	var culled0 := int(s2["culled"])
	Audio.play_at("footstep_concrete", origin + Vector3(5000, 0, 0), 0.0, 1.0, 35.0)
	T.check(int(Audio.get_stats()["culled"]) == culled0 + 1, "out-of-range positional sounds are culled")
	# de-duplication of identical simultaneous requests (the windows are real-time milliseconds)
	OS.delay_msec(70)
	var dd0 := int(Audio.get_stats()["deduped"])
	Audio.play("ui_click")
	Audio.play("ui_click")
	Audio.play_at("impact_metal", origin + Vector3(2, 0, 0))
	Audio.play_at("impact_metal", origin + Vector3(2.2, 0, 0))
	T.check(int(Audio.get_stats()["deduped"]) >= dd0 + 2, "identical simultaneous requests are merged")
	Audio.stop_all()
	# pitch variation (category default for footsteps is +-6 %)
	var pitches := {}
	for i in 12:
		Audio.play_at("footstep_grass", origin + Vector3(3.0 + i * 2.0, 0, 1.0), -6.0, 1.0, 60.0)
	for p: Variant in Audio.get("_voices_3d"):
		var v := p as AudioStreamPlayer3D
		if v.playing:
			pitches[snappedf(v.pitch_scale, 0.0001)] = true
	T.check(pitches.size() >= 6, "random pitch variation is applied (%d distinct pitches of 12)" % pitches.size())
	Audio.stop_all()
	Audio.play_at("footstep_grass", origin + Vector3(3, 0, 1), -6.0, 1.25, 60.0, "SFX", 0.0)
	var exact := false
	for p: Variant in Audio.get("_voices_3d"):
		var v := p as AudioStreamPlayer3D
		if v.playing and is_equal_approx(v.pitch_scale, 1.25):
			exact = true
	T.check(exact, "pitch_variation = 0 keeps the requested pitch")
	# routing
	Audio.stop_all()
	OS.delay_msec(70)
	Audio.play_at("rifle_shot", origin + Vector3(6, 0, 0))
	Audio.play_ui("ui_open")
	var weapon_bus := ""
	var weapon_range := 0.0
	for p: Variant in Audio.get("_voices_3d"):
		var v := p as AudioStreamPlayer3D
		if v.playing:
			weapon_bus = str(v.bus)
			weapon_range = v.max_distance
	var ui_bus := ""
	var ui_mode := -1
	for p: Variant in Audio.get("_voices_2d"):
		var v2 := p as AudioStreamPlayer
		if v2.playing:
			ui_bus = str(v2.bus)
			ui_mode = v2.process_mode
	T.check(weapon_bus == "Weapons" and weapon_range >= 150.0, "gunshots route to Weapons with a long range (%s, %.0f m)" % [weapon_bus, weapon_range])
	T.check(ui_bus == "UI" and ui_mode == Node.PROCESS_MODE_ALWAYS, "play_ui uses the UI bus and survives pause")
	Audio.stop_all()
	T.check(_voice_children() == voices0 and Audio.get_child_count() == children0, "pools still did not grow")


# --- loop players -----------------------------------------------------------------------------

func _s16(wav: AudioStreamWAV, frame: int) -> int:
	return wav.data.decode_s16(frame * 2)


func _test_loop_players() -> void:
	var holder := Node3D.new()
	holder.name = "AudLoopHolder"
	add_child(holder)
	var eng: AudioStreamPlayer3D = Audio.make_loop_player("engine_car_loop", holder, 65.0, "Engine")
	var eng_wav := eng.stream as AudioStreamWAV
	T.check(eng != null and eng.get_parent() == holder and eng_wav != null and eng_wav.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"make_loop_player returns a looping 3D player under the given parent")
	T.check(str(eng.bus) == "Engine" and is_equal_approx(eng.max_distance, 65.0) and not eng.playing, "loop player: bus / range set, not started")
	eng.play()
	eng.pitch_scale = 1.7
	T.check(eng.playing, "loop player starts when the caller plays it")
	eng.stop()
	# horn: natural stream is a one-shot, the loop player sustains its periodic middle section
	var horn_natural := Audio.get_stream("horn_car") as AudioStreamWAV
	var horn: AudioStreamPlayer3D = Audio.make_loop_player("horn_car", holder, 70.0, "SFX")
	var horn_wav := horn.stream as AudioStreamWAV
	T.check(horn_natural.loop_mode == AudioStreamWAV.LOOP_DISABLED and horn_wav != null
		and horn_wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and horn_wav.loop_begin == 8820 and horn_wav.loop_end == 30870,
		"horn_car: one-shot stream + sustain loop [0.2 s, 0.7 s]")
	for horn_id: String in ["horn_car", "horn_truck", "horn_bike"]:
		var hw := (Audio.make_loop_player(horn_id, holder) as AudioStreamPlayer3D).stream as AudioStreamWAV
		if hw != null and hw.format == AudioStreamWAV.FORMAT_16_BITS:
			var worst := 0
			var peak := 1
			for k in 2000:
				worst = maxi(worst, absi(_s16(hw, hw.loop_begin + k) - _s16(hw, hw.loop_end + k)))
				peak = maxi(peak, absi(_s16(hw, hw.loop_begin + k)))
			T.check(worst <= 8, "%s sustain loop is sample-periodic (max error %d LSB, peak %d)" % [horn_id, worst, peak])
		else:
			T.log_line("%s is not PCM16 here - sustain periodicity not checked in-engine" % horn_id)
	# seam of every canonical loop, measured on the imported data
	var worst_id := ""
	var worst_ratio := 0.0
	var measured := 0
	for id: String in Audio.SOUND_IDS:
		if not Audio.is_loop_id(id):
			continue
		var lw := Audio.get_stream(id) as AudioStreamWAV
		if lw == null or lw.format != AudioStreamWAV.FORMAT_16_BITS or lw.stereo:
			continue
		var n := lw.loop_end
		var sum := 0.0
		var count := mini(n - 1, 20000)
		for k in count:
			var d := float(_s16(lw, k + 1) - _s16(lw, k))
			sum += d * d
		var typical := sqrt(sum / float(count)) + 1.0
		var ratio := absf(float(_s16(lw, 0) - _s16(lw, n - 1))) / typical
		measured += 1
		if ratio > worst_ratio:
			worst_ratio = ratio
			worst_id = id
	T.log_line("loop seams measured in-engine: %d, worst %s = %.2f x the typical sample step" % [measured, worst_id, worst_ratio])
	T.check(measured == 0 or worst_ratio < 6.0, "imported loops wrap without a discontinuity (worst %.2f)" % worst_ratio)
	var none: AudioStreamPlayer3D = Audio.make_loop_player("no_such_loop", holder)
	T.check(none != null and none.stream == null, "unknown loop id gives a silent player, not a crash")
	var bed: AudioStreamPlayer = Audio.make_loop_player_2d("rain_loop")
	var bed_wav := bed.stream as AudioStreamWAV
	T.check(bed != null and str(bed.bus) == "Ambience" and bed_wav != null and bed_wav.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"make_loop_player_2d returns a looping bed on the Ambience bus")
	bed.play()
	Audio.stop_all(true)
	T.check(not bed.playing, "stop_all(true) also stops handed-out loop players")
	bed.queue_free()
	holder.queue_free()


# --- radio ------------------------------------------------------------------------------------

func _make_script(source: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = source
	s.reload()
	return s


func _press(action: String) -> void:
	Input.action_press(action)
	await T.wait_frames(2)
	Input.action_release(action)
	await T.wait_frames(2)


func _test_radio() -> void:
	var radio: Node = Game.get_system("radio")
	if not T.check(radio != null, "radio system is registered"):
		return
	var saved_station: Variant = Settings.get_value("radio_station")
	var saved_player: Node3D = Game.player
	radio.set("announce", false)
	var stations: Array = radio.call("get_stations")
	var ids: Array = []
	for s: Variant in stations:
		ids.append(str((s as Dictionary)["id"]))
	T.check(ids == ["neon_tide", "low_tide", "boogie_bay", "breakwater", "drift"], "get_stations() lists the 5 stations in dial order: " + str(ids))
	T.check((radio.call("get_stations", true) as Array).size() == 6, "get_stations(true) adds the 'off' entry")
	T.check(not radio.call("is_listening") and not radio.call("is_playing"), "radio is silent on foot")
	EventBus.radio_station_changed.connect(func(id: String) -> void: _radio_events.append(id))

	# a dummy player sitting in a dummy car (carries the public Player members other modules,
	# e.g. the HUD, read every frame, so they do not error while Game.player is the dummy)
	var dummy_player := Node3D.new()
	dummy_player.set_script(_make_script("extends Node3D\nvar current_vehicle: Node3D = null\n"
		+ "var health := 100.0\nvar max_health := 100.0\nvar armor := 0.0\nvar max_armor := 100.0\n"
		+ "var is_dead := false\nvar is_aiming := false\nvar is_sprinting := false\nvar is_crouching := false\n"
		+ "var in_stealth := false\nvar in_cover := false\nvar is_swimming := false\nvar is_underwater := false\n"
		+ "var has_parachute := false\nvar breath := 1.0\nvar stamina := 1.0\nvar noise_radius := 0.0\n"
		+ "var visual: Node3D = null\nvar inventory: Node = null\n"
		+ "func is_armed() -> bool:\n\treturn false\n"))
	add_child(dummy_player)
	var car := Node3D.new()
	car.set_script(_make_script("extends Node3D\nvar vehicle_class := \"car\"\nvar is_emergency := false\nvar is_police := false\nvar destroyed := false\nvar spec_id := \"sedan\"\n"))
	add_child(car)
	Game.player = dummy_player
	radio.call("set_station", "off")
	_radio_events.clear()
	dummy_player.set("current_vehicle", car)
	EventBus.player_entered_vehicle.emit(car, 0)
	await T.wait_frames(3)
	T.check(radio.call("is_listening") and not radio.call("is_playing"), "in a car with the radio off: listening, not playing")
	radio.call("set_station", "neon_tide")
	await T.wait_frames(30)
	var now: Dictionary = radio.call("get_now_playing")
	T.check(radio.call("is_playing") and str(now["track"]).begins_with("radio_neon_tide_"), "set_station() starts the station's music: " + str(now["track"]))
	var active: AudioStreamPlayer = radio.get("_active")
	T.check(active != null and str(active.bus) == "Music", "radio plays on the Music bus")
	T.check(_radio_events == ["neon_tide"], "EventBus.radio_station_changed emitted once: " + str(_radio_events))
	T.check(str(Settings.get_value("radio_station")) == "neon_tide", "last station is remembered in Settings")

	# cycle with the input actions: neon_tide -> low_tide -> boogie_bay -> breakwater -> drift -> off -> neon_tide
	var walked: Array = []
	for i in 6:
		await _press("radio_next")
		walked.append(str(radio.call("get_station")))
	T.check(walked == ["low_tide", "boogie_bay", "breakwater", "drift", "off", "neon_tide"], "radio_next cycles through all stations and 'off': " + str(walked))
	await _press("radio_prev")
	T.check(str(radio.call("get_station")) == "off", "radio_prev steps back to 'off'")
	await T.wait_frames(40)
	T.check(not radio.call("is_playing"), "'off' is silent")
	await _press("radio_prev")
	T.check(str(radio.call("get_station")) == "drift", "radio_prev wraps to the last station")
	radio.call("set_station", "does_not_exist")
	T.check(str(radio.call("get_station")) == "drift", "unknown station ids are ignored")
	await T.wait_frames(30)

	# the broadcast advances and pauses with the game. Audio runs on the real-time clock while
	# this run simulates frames as fast as it can, so block the main thread instead of awaiting.
	active = radio.get("_active")
	OS.delay_msec(120)
	var p0 := active.get_playback_position()
	OS.delay_msec(300)
	var p1 := active.get_playback_position()
	var track_len := active.stream.get_length() if active.stream != null else 1.0
	var ran := fposmod(p1 - p0, track_len)          # the loop may wrap between the two readings
	if ran > 0.05 and ran < 2.0:
		get_tree().paused = true
		await T.wait_frames(2)
		OS.delay_msec(120)
		var p2 := active.get_playback_position()
		OS.delay_msec(300)
		var p3 := active.get_playback_position()
		get_tree().paused = false
		await T.wait_frames(2)
		T.check(absf(p3 - p2) < 0.03, "radio pauses with the game (advanced %.3f s while paused, %.3f s while running)" % [p3 - p2, ran])
		OS.delay_msec(150)
		var p4 := active.get_playback_position()
		T.check(fposmod(p4 - p3, track_len) > 0.03, "radio resumes after the pause (%.3f s)" % fposmod(p4 - p3, track_len))
	else:
		T.check(false, "playback position did not advance as expected (%.3f s in 0.3 s) - pause check impossible" % ran)

	# vehicles without a radio
	car.set("is_emergency", true)
	await T.wait_frames(40)
	T.check(not radio.call("is_listening"), "emergency vehicles have no radio")
	car.set("is_emergency", false)
	car.set("vehicle_class", "bicycle")
	await T.wait_frames(40)
	T.check(not radio.call("is_listening"), "bicycles have no radio")
	car.set("vehicle_class", "car")
	await T.wait_frames(40)
	T.check(radio.call("is_listening") and radio.call("is_playing"), "back in a normal car the radio resumes")

	# leaving the vehicle
	dummy_player.set("current_vehicle", null)
	EventBus.player_exited_vehicle.emit(car)
	await T.wait_frames(60)
	var a: AudioStreamPlayer = radio.get("_active")
	var b: AudioStreamPlayer = radio.get("_fading")
	T.check(not radio.call("is_listening") and not a.playing and not b.playing, "leaving the vehicle fades the radio out")

	# broadcast timeline sanity
	var loc0: Dictionary = radio.call("locate", "neon_tide", 0.0)
	var len0 := Audio.get_stream(str(loc0["track"])).get_length()
	var loc1: Dictionary = radio.call("locate", "neon_tide", float(loc0["remaining"]) + 0.5)
	T.check(str(loc0["track"]) != str(loc1["track"]) and float(loc0["remaining"]) <= len0 * 2.0 + 0.01,
		"a station alternates its two loops on the broadcast clock (%s -> %s)" % [str(loc0["track"]), str(loc1["track"])])

	Game.player = saved_player
	radio.set("announce", true)
	Settings.set_value("radio_station", saved_station if saved_station != null else "")
	radio.set("_station", str(saved_station) if (saved_station != null and str(saved_station) != "") else "neon_tide")
	dummy_player.queue_free()
	car.queue_free()


# --- ambience ---------------------------------------------------------------------------------

func _ctx(district: String, daylight: float, extra: Dictionary = {}) -> Dictionary:
	var c := {"district": district, "daylight": daylight, "rain": 0.0, "wind": 0.2, "altitude": 0.0,
		"sea": 0.0, "in_vehicle": false, "underwater": false}
	for k: String in extra:
		c[k] = extra[k]
	return c


func _test_ambience() -> void:
	var amb: Node = Game.get_system("ambience")
	if not T.check(amb != null, "ambience system is registered"):
		return
	amb.set("spot_sounds", false)
	var m: Dictionary = amb.call("compute_targets", _ctx("downtown", 1.0))
	T.check(float(m["city"]) > 0.9 and float(m["crickets"]) == 0.0 and float(m["birds"]) < 0.1 and float(m["chatter"]) > 0.4, "downtown by day: city + chatter")
	m = amb.call("compute_targets", _ctx("downtown", 0.0))
	T.check(float(m["city"]) < 0.6 and float(m["chatter"]) == 0.0, "downtown at night: quieter, no chatter")
	m = amb.call("compute_targets", _ctx("hill", 1.0))
	T.check(float(m["birds"]) > 0.9 and float(m["crickets"]) == 0.0, "hill by day: birds")
	m = amb.call("compute_targets", _ctx("hill", 0.0))
	T.check(float(m["crickets"]) > 0.9 and float(m["birds"]) == 0.0, "hill at night: crickets")
	m = amb.call("compute_targets", _ctx("industrial", 1.0))
	T.check(float(m["industrial"]) > 0.9, "industrial district: machinery bed")
	m = amb.call("compute_targets", _ctx("waterfront", 1.0))
	T.check(float(m["harbor"]) > 0.9 and float(m["ocean"]) > 0.3, "waterfront: harbour + some ocean")
	m = amb.call("compute_targets", _ctx("airport", 1.0))
	T.check(float(m["airport"]) > 0.9, "airport: apron bed")
	m = amb.call("compute_targets", _ctx("residential", 1.0, {"sea": 1.0}))
	T.check(float(m["ocean"]) > 0.95, "next to the sea the ocean bed comes in regardless of district")
	m = amb.call("compute_targets", _ctx("midtown", 1.0, {"rain": 0.3}))
	T.check(float(m["rain"]) > 0.6 and float(m["rain_heavy"]) < 0.05, "light rain: rain_loop")
	m = amb.call("compute_targets", _ctx("midtown", 1.0, {"rain": 1.0}))
	T.check(float(m["rain_heavy"]) > 0.95 and float(m["rain"]) < 0.05 and float(m["birds"]) == 0.0, "storm: rain_heavy_loop, birds silent")
	var ground: Dictionary = amb.call("compute_targets", _ctx("downtown", 1.0))
	m = amb.call("compute_targets", _ctx("downtown", 1.0, {"altitude": 220.0}))
	T.check(float(m["wind"]) > 0.9 and float(m["city"]) < float(ground["city"]) * 0.3, "high altitude: wind up, city down")
	m = amb.call("compute_targets", _ctx("beach", 1.0, {"underwater": true}))
	T.check(float(m["underwater"]) == 1.0 and float(m["ocean"]) < 0.07 and float(m["city"]) < 0.07, "underwater: beds ducked, underwater bed in")
	m = amb.call("compute_targets", _ctx("downtown", 1.0, {"in_vehicle": true}))
	T.check(float(m["city"]) < float(ground["city"]) * 0.7, "inside a car the ambience is ducked")

	# live crossfade: hill at night -> downtown by day in a storm
	amb.call("set_context_override", _ctx("hill", 0.0))
	await T.wait_seconds(4.0)
	var g: Dictionary = amb.call("get_layer_gains")
	var players: Dictionary = amb.get("_players")
	var cricket_player: AudioStreamPlayer = players.get("crickets", null)
	T.check(float(g["crickets"]) > 0.9 and str(amb.call("get_dominant_layer")) == "crickets", "live: crickets bed faded in on the night hill (%.2f)" % float(g["crickets"]))
	T.check(cricket_player != null and cricket_player.playing and str(cricket_player.bus) == "Ambience"
		and (cricket_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "live: crickets loop is playing on the Ambience bus")
	amb.call("set_context_override", _ctx("downtown", 1.0, {"rain": 1.0}))
	await T.wait_seconds(1.2)
	var mid: Dictionary = amb.call("get_layer_gains")
	T.check(float(mid["crickets"]) > 0.05 and float(mid["crickets"]) < 0.95 and float(mid["city"]) > 0.05, "live: beds crossfade smoothly (crickets %.2f, city %.2f mid-way)" % [float(mid["crickets"]), float(mid["city"])])
	await T.wait_seconds(4.0)
	g = amb.call("get_layer_gains")
	players = amb.get("_players")
	T.check(float(g["crickets"]) < 0.01 and float(g["city"]) > 0.9 and float(g["rain_heavy"]) > 0.9, "live: city + heavy rain took over")
	T.check(not cricket_player.playing and players.has("city") and (players["city"] as AudioStreamPlayer).playing, "live: silent beds are stopped, active beds play")
	amb.call("set_context_override", _ctx("beach", 1.0, {"underwater": true}))
	await T.wait_seconds(1.5)
	g = amb.call("get_layer_gains")
	T.check(float(g["underwater"]) > 0.9 and float(g["city"]) < 0.1, "live: underwater ducks the beds quickly")
	# sparse positional life calls (gull near the sea by day)
	amb.call("set_context_override", _ctx("beach", 1.0, {"sea": 0.9}))
	await T.wait_frames(20)
	var before: Dictionary = Audio.get_stats()
	for i in 6:
		OS.delay_msec(30)
		amb.call("_play_spot")
	var after: Dictionary = Audio.get_stats()
	T.check(int(after["played_3d"]) > int(before["played_3d"]), "ambience places positional animal calls (%d played)" % (int(after["played_3d"]) - int(before["played_3d"])))
	amb.call("clear_context_override")
	await T.wait_seconds(0.5)
	var ctx: Dictionary = amb.call("get_context")
	T.check(ctx.has("district") and ctx.has("daylight") and ctx.has("sea") and ctx.has("altitude"), "live sampling works without a world / player: " + str(ctx))
	amb.set("spot_sounds", true)


# --- event glue -------------------------------------------------------------------------------

func _voice_playing(sound_id: String) -> bool:
	var want: AudioStream = Audio.get_stream(sound_id)
	for p: Variant in Audio.get("_voices_2d"):
		var v := p as AudioStreamPlayer
		if v.playing and v.stream == want:
			return true
	return false


func _test_event_glue() -> void:
	Audio.stop_all()
	OS.delay_msec(70)
	EventBus.wanted_level_changed.emit(1, 0)
	T.check(_voice_playing("wanted_up"), "wanted level up plays the wanted_up stinger")
	EventBus.wanted_cleared.emit("cheat")
	T.check(_voice_playing("wanted_clear"), "wanted cleared plays the wanted_clear stinger")
	EventBus.ui_screen_opened.emit("aud_test_screen")
	await T.wait_frames(3)
	T.check(_voice_playing("ui_open"), "opening a UI screen plays ui_open")
	OS.delay_msec(150)
	# a module that plays its own UI sound for the screen does not get a second one
	Audio.stop_all()
	Audio.play_ui("ui_click")
	EventBus.ui_screen_closed.emit("aud_test_screen")
	await T.wait_frames(3)
	T.check(not _voice_playing("ui_close"), "no double UI sound when the UI module already played one")
	Audio.set("auto_event_sounds", false)
	OS.delay_msec(150)
	Audio.stop_all()
	EventBus.ui_screen_opened.emit("aud_test_screen")
	await T.wait_frames(3)
	T.check(not _voice_playing("ui_open"), "auto_event_sounds = false silences the glue")
	Audio.set("auto_event_sounds", true)
	Audio.stop_all(true)
