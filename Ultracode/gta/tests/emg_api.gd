extends Node
## EMERGENCY services - headless, the full game (traffic + pedestrians on, police off so nothing
## else reacts to the scene). The player stands on a downtown sidewalk (invulnerable, clock paused
## at noon). Covered:
##   * API: set_enabled / get_active_responses / reset_for_respawn / dispatch / get_debug_info
##   * medical: a civilian is killed (kill(): no crime) and a second one knocked out by a takedown
##     info next to the player -> an ambulance spawns out of view, drives with the siren, arrives
##     within 60 s, a medic reaches each body and kneels; the corpse is still there (held), the
##     knocked-out civilian stays down until treated and then gets up dazed
##   * traffic yields to our siren (TrafficDriver.siren_t)
##   * fire: a sedan is blown up 40 m along the road -> a fire truck arrives, firefighters spray
##     (water jets active), the fire is put out (no fire handle left on the wreck)
##   * responders leave and are despawned when far (the player is moved away)
##   * caps: 7 more deaths at separate spots -> at most one ambulance at a time, <= 4 pending
##     medical incidents, <= 5 held corpses
##   * set_enabled(false) ignores incidents; reset_for_respawn clears a running response
##   * never touches the wanted system (level stays 0, no crime witnessed / reported by responders)
##   * AI open items: peds.count_near(), silent takedown witnessed by sight only, knock-out duration
##
## Run: tools\godot.ps1 -Mode headless -Frames 36000 -TimeoutSec 420 -UserArgs '--test=emg_api','--test-timeout=400',
##      '--seed=7','--disable=police,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'

var emg: Node = null
var crimes_by_responders: int = 0
var crimes_total: int = 0


func _ready() -> void:
	EventBus.crime_witnessed.connect(_on_witnessed)
	EventBus.crime_reported.connect(_on_reported)
	await _run()


func _on_witnessed(_c: String, _p: Vector3, witness: Node) -> void:
	if witness != null and is_instance_valid(witness) and str(witness.get("faction")) in ["medic", "fire"]:
		crimes_by_responders += 1


func _on_reported(_c: String, _p: Vector3) -> void:
	crimes_total += 1


func _run() -> void:
	emg = Game.get_system("emergency")
	if not TestHarness.check(emg != null, "emergency system is registered"):
		TestHarness.finish(false, "no emergency system")
		return
	for m in ["set_enabled", "get_active_responses", "reset_for_respawn", "dispatch", "clear_all", "get_debug_info"]:
		TestHarness.check(emg.has_method(m), "API: %s" % m)
	if not TestHarness.check(Game.world != null and Game.world.get("roads") != null and Game.player != null 			and Game.player.has_method("teleport"), "world + player (with its script)"):
		TestHarness.finish(false, "needs world and a working player")
		return
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(12.0)
	if "paused" in WorldClock:
		WorldClock.paused = true
	Game.invulnerable = true
	var roads: Object = Game.world.get("roads")
	var spot: Dictionary = roads.call("get_nearest_lane", Vector3(0.0, 2.6, -60.0), 40.0)
	var lane_xf: Transform3D = roads.call("sample_lane", int(spot["lane_id"]), float(spot["offset"]))
	var dir := -lane_xf.basis.z
	var right := Vector3(-dir.z, 0.0, dir.x)
	var walk_p := lane_xf.origin + right * 7.0
	Game.player.call("teleport", walk_p + Vector3.UP * 0.2, atan2(-right.x, -right.z))
	await TestHarness.wait_seconds(4.0)
	var peds := Game.get_system("peds")
	TestHarness.check(peds != null, "peds system running")

	# ---- AI open item: count_near ------------------------------------------------------------
	var bystander: Node3D = Game.spawn_npc("civilian_f", walk_p + dir * 3.0, {"yaw": 0.0, "activity": "idle"})
	await TestHarness.wait_seconds(0.3)
	if peds != null and peds.has_method("count_near"):
		TestHarness.check(int(peds.call("count_near", walk_p, 8.0)) >= 1, "peds.count_near sees the living civilian beside the player")

	# ---- medical + fire incidents ---------------------------------------------------------------
	var victim: Node3D = Game.spawn_npc("civilian_m", walk_p + dir * 6.0 + right * 0.5, {"yaw": 0.0, "activity": "idle"})
	var ko: Node3D = Game.spawn_npc("civilian_m", walk_p + dir * 8.5 - right * 0.4, {"yaw": PI, "activity": "idle"})
	await TestHarness.wait_seconds(0.5)
	if not TestHarness.check(victim != null and ko != null, "test civilians spawned"):
		TestHarness.finish(false, "no NPCs")
		return
	victim.call("kill", "test")
	var ko_info := Dmg.make(30.0, "melee", null, ko.global_position + Vector3.UP, Vector3.DOWN,
			{"silent": true, "takedown": true, "knockout": true, "knockout_seconds": 30.0, "knockdown": true, "impulse": 80.0})
	ko.call("apply_damage", ko_info)
	var t_incident := _now()
	TestHarness.check(victim.get("is_dead") == true, "victim is dead")
	TestHarness.check(ko.get("is_down") == true and ko.get("knocked_out") == true, "takedown knock-out puts the NPC down (knocked_out)")
	# a car blown up 40 m further along the road
	var car_xf: Transform3D = roads.call("sample_lane", int(spot["lane_id"]), float(spot["offset"]) + 40.0)
	car_xf.origin.y += 0.4
	var car: Node3D = Game.spawn_vehicle("sedan", car_xf, {"owner_tag": "parked"})
	await TestHarness.wait_seconds(0.6)
	if TestHarness.check(car != null and car.has_method("explode"), "test sedan spawned"):
		car.call("explode", null)
	await TestHarness.wait_seconds(0.5)
	var pend: Array = emg.call("get_pending_incidents")
	TestHarness.log_line("pending after the incidents: %s" % str(pend))
	TestHarness.check(pend.size() >= 2, "a medical and a fire incident are pending")

	# ---- watch both responses ------------------------------------------------------------------
	var med := {"dispatched": -1.0, "arrived": -1.0, "reached": -1.0, "siren": false, "spawn_dist": 0.0, "corpse_ok": false,
			"ko_down_15": false, "ko_up": -1.0, "ko_dazed": false, "max_amb": 0}
	var fire := {"dispatched": -1.0, "arrived": -1.0, "spraying": -1.0, "jets": 0, "out": -1.0, "siren": false}
	var yielded := {}
	var steps := 0
	while _now() - t_incident < 100.0:
		await TestHarness.wait_seconds(0.25)
		steps += 1
		var el := _now() - t_incident
		var resp: Array = emg.call("get_active_responses")
		var n_amb := 0
		for r: Dictionary in resp:
			if r["kind"] == "medical":
				n_amb += 1
				if med["dispatched"] < 0.0:
					med["dispatched"] = el
					med["spawn_dist"] = float(r["spawn_dist"])
				if bool(r["siren"]) and str(r["state"]) == "driving":
					med["siren"] = true
				if bool(r["arrived"]) and med["arrived"] < 0.0:
					med["arrived"] = el
					med["corpse_ok"] = is_instance_valid(victim) and victim.get("is_dead") == true and victim.get("corpse_held") == true
				if med["reached"] < 0.0:
					for c: Node3D in r["crew"]:
						if is_instance_valid(c) and str(c.get("state_tag")) == "treating" and is_instance_valid(victim) \
								and _flat(c.global_position, victim.call("get_body_position")) < 1.6:
							med["reached"] = el
			elif r["kind"] == "fire":
				if fire["dispatched"] < 0.0:
					fire["dispatched"] = el
				if bool(r["siren"]) and str(r["state"]) == "driving":
					fire["siren"] = true
				if bool(r["arrived"]) and fire["arrived"] < 0.0:
					fire["arrived"] = el
				for c: Node3D in r["crew"]:
					if is_instance_valid(c) and str(c.get("state_tag")) == "spraying" and fire["spraying"] < 0.0:
						fire["spraying"] = el
				var efx: Node = emg.get("fx")
				if efx != null:
					fire["jets"] = maxi(int(fire["jets"]), int(efx.get("active_count")))
				if bool(r["fire_out"]) and fire["out"] < 0.0:
					fire["out"] = el
			# traffic yielding to our sirens
			if bool(r["siren"]):
				_collect_yields(yielded)
		med["max_amb"] = maxi(int(med["max_amb"]), n_amb)
		if el > 15.0 and el < 16.0 and is_instance_valid(ko):
			med["ko_down_15"] = ko.get("is_down") == true
		if is_instance_valid(ko) and med["ko_up"] < 0.0 and ko.get("is_down") == false and el > 3.0:
			med["ko_up"] = el
		if is_instance_valid(ko) and str(ko.get("state_tag")) == "dazed":
			med["ko_dazed"] = true
		if steps % 40 == 0:
			TestHarness.log_line("t=%.0f %s" % [el, str((emg.call("get_debug_info") as Dictionary).get("list", []))])
		if med["reached"] >= 0.0 and fire["out"] >= 0.0 and med["ko_up"] >= 0.0 and el > med["reached"] + 12.0:
			break
	TestHarness.log_line("medical: %s" % str(med))
	TestHarness.log_line("fire: %s" % str(fire))
	TestHarness.log_line("traffic drivers that yielded to a siren: %d" % yielded.size())
	TestHarness.check(med["dispatched"] >= 0.0, "an ambulance was dispatched")
	TestHarness.check(float(med["spawn_dist"]) >= 60.0, "the ambulance spawned away from the scene (%.0f m)" % float(med["spawn_dist"]))
	TestHarness.check(bool(med["siren"]), "the ambulance drove with the siren on")
	TestHarness.check(med["arrived"] >= 0.0 and med["arrived"] <= 60.0, "the ambulance arrived within 60 s (%.1f s)" % float(med["arrived"]))
	TestHarness.check(bool(med["corpse_ok"]), "the corpse was still there (held) when the ambulance arrived")
	TestHarness.check(med["reached"] >= 0.0, "a medic reached the body and kneeled (%.1f s)" % float(med["reached"]))
	TestHarness.check(bool(med["ko_down_15"]), "the knocked-out civilian was still down after 15 s")
	TestHarness.check(med["ko_up"] >= 0.0 and med["ko_up"] > float(med["arrived"]), "the knocked-out civilian got up after the medics came (%.1f s)" % float(med["ko_up"]))
	TestHarness.check(bool(med["ko_dazed"]), "it woke up dazed (not panicking)")
	TestHarness.check(int(med["max_amb"]) <= 1, "never more than one ambulance")
	TestHarness.check(fire["dispatched"] >= 0.0, "a fire truck was dispatched")
	TestHarness.check(bool(fire["siren"]), "the fire truck drove with the siren on")
	TestHarness.check(fire["arrived"] >= 0.0 and fire["arrived"] <= 60.0, "the fire truck arrived within 60 s (%.1f s)" % float(fire["arrived"]))
	TestHarness.check(fire["spraying"] >= 0.0 and int(fire["jets"]) >= 1, "firefighters sprayed water (%d jets)" % int(fire["jets"]))
	TestHarness.check(fire["out"] >= 0.0, "the fire was put out (%.1f s)" % float(fire["out"]))
	if car != null and is_instance_valid(car):
		var fires := 0
		for c in car.get_children():
			if c.get("fx_kind") == "fire" and not c.is_queued_for_deletion():
				fires += 1
		TestHarness.check(fires == 0, "no fire handle left on the wreck (%d)" % fires)
	TestHarness.check(yielded.size() >= 1, "traffic yielded to the emergency sirens (%d drivers)" % yielded.size())

	# ---- leaving + despawn ----------------------------------------------------------------------
	var left := false
	for i in 120:
		await TestHarness.wait_seconds(0.25)
		var all_leaving := true
		for r: Dictionary in (emg.call("get_active_responses") as Array):
			if str(r["state"]) != "leaving":
				all_leaving = false
		if all_leaving:
			left = true
			break
	TestHarness.check(left, "the crews boarded and the vehicles are leaving")
	var vehicles: Array = []
	for r: Dictionary in (emg.call("get_active_responses") as Array):
		vehicles.append(r["vehicle"])
	# walk away: everything of ours must be despawned out of view / far away
	var far_p: Vector3 = walk_p + Vector3(0.0, 0.0, 280.0)
	far_p.y = Game.ground_height(far_p.x, far_p.z) + 0.3
	Game.player.call("teleport", far_p, 0.0)
	await TestHarness.wait_seconds(3.0)
	TestHarness.check((emg.call("get_active_responses") as Array).is_empty(), "responses despawned when far")
	var gone := true
	for v: Variant in vehicles:
		if v != null and is_instance_valid(v) and not (v as Node).is_queued_for_deletion():
			gone = false
	TestHarness.check(gone, "response vehicles removed")
	Game.player.call("teleport", walk_p + Vector3.UP * 0.2, 0.0)
	await TestHarness.wait_seconds(3.0)

	# ---- caps -------------------------------------------------------------------------------------
	var max_amb := 0
	var max_pending := 0
	var max_held := 0
	# deaths at 7 separate places 35-100 m around the player (> 35 m apart: no merging)
	var placed: Array[Vector3] = []
	for k in 60:
		if placed.size() >= 7:
			break
		var rp: Dictionary = roads.call("random_lane_point", walk_p, 35.0, 100.0)
		if rp.is_empty():
			continue
		var lxf: Transform3D = rp["transform"]
		var p := lxf.origin + (-lxf.basis.z).cross(Vector3.UP).normalized() * 6.5
		var ok := not Game.is_in_water(p)
		for q in placed:
			if _flat(q, p) < 36.0:
				ok = false
		if not ok:
			continue
		placed.append(p)
		var n: Node3D = Game.spawn_npc("civilian_f", p, {"activity": "idle"})
		await TestHarness.wait_seconds(0.1)
		if n != null:
			n.call("kill", "test")
	TestHarness.log_line("caps: %d deaths placed" % placed.size())
	for i in 80:
		await TestHarness.wait_seconds(0.25)
		var dbg: Dictionary = emg.call("get_debug_info")
		var amb := 0
		for r: Dictionary in (emg.call("get_active_responses") as Array):
			if r["kind"] == "medical":
				amb += 1
		max_amb = maxi(max_amb, amb)
		var med_pending := 0
		for inc: Dictionary in (emg.call("get_pending_incidents") as Array):
			if inc["kind"] == "medical":
				med_pending += 1
		max_pending = maxi(max_pending, med_pending)
		max_held = maxi(max_held, int(dbg.get("held", 0)))
	TestHarness.log_line("caps: ambulances %d, pending medical %d, held corpses %d" % [max_amb, max_pending, max_held])
	TestHarness.check(max_amb == 1, "caps: exactly one ambulance at a time (%d)" % max_amb)
	TestHarness.check(max_pending <= 4 and max_pending >= 3, "caps: incidents queue up to the cap of 4 (%d)" % max_pending)
	TestHarness.check(max_held <= 5, "caps: at most 5 held corpses (%d)" % max_held)

	# ---- theft: the vehicle is carjacked while driving (the PLAYER module's call) -------------------
	emg.call("clear_all")
	await TestHarness.wait_seconds(0.5)
	var t_body: Node3D = Game.spawn_npc("civilian_m", walk_p + dir * 5.0, {"activity": "idle"})
	await TestHarness.wait_seconds(0.2)
	if t_body != null:
		t_body.call("kill", "test")
	TestHarness.check(bool(emg.call("dispatch", "medical", walk_p + dir * 5.0)), "theft: ambulance dispatched")
	var stolen_v: Node3D = null
	var crew_t: Array = []
	for i in 80:
		await TestHarness.wait_seconds(0.25)
		var rs: Array = emg.call("get_active_responses")
		if rs.is_empty():
			continue
		var r0: Dictionary = rs[0]
		if str(r0["state"]) == "driving" and float(r0["age"]) > 3.0 and r0["vehicle"] != null:
			stolen_v = r0["vehicle"]
			crew_t = r0["crew"]
			break
	if TestHarness.check(stolen_v != null and stolen_v.has_meta("ai_controller"), "theft: ambulance on its way with an ai_controller"):
		var ctrl: Object = stolen_v.get_meta("ai_controller")
		var drv_npc: Variant = ctrl.call("release_vehicle", stolen_v, "carjacked")
		await TestHarness.wait_seconds(0.5)
		TestHarness.check(drv_npc is Node3D and is_instance_valid(drv_npc) and (drv_npc as Node3D).get("current_vehicle") == null,
				"theft: release_vehicle('carjacked') returns the driver, out of the seat")
		TestHarness.check(not stolen_v.has_meta("ai_controller") and stolen_v.get("driver") == null, "theft: no ai_controller meta, driver == null")
		var seated := 0
		for c: Variant in crew_t:
			if c != null and is_instance_valid(c) and (c as Node3D).get("current_vehicle") != null:
				seated += 1
		TestHarness.check(seated == 0, "theft: the whole crew got out")
		await TestHarness.wait_seconds(6.0)
		var rs2: Array = emg.call("get_active_responses")
		TestHarness.check(rs2.is_empty(), "theft: the response let go (crew walks off)")
		TestHarness.check(int(Wanted.level) == 0, "theft: no police involvement from the emergency module")
		# far away: the stray crew is removed, the stolen vehicle is NOT ours to remove
		Game.player.call("teleport", far_p, 0.0)
		await TestHarness.wait_seconds(2.0)
		var strays_left := 0
		for c: Variant in crew_t:
			if c != null and is_instance_valid(c) and not (c as Node).is_queued_for_deletion():
				strays_left += 1
		TestHarness.check(strays_left == 0, "theft: the stranded crew is despawned when far (%d left)" % strays_left)
		TestHarness.check(is_instance_valid(stolen_v), "theft: the stolen vehicle is left alone")
		Game.player.call("teleport", walk_p + Vector3.UP * 0.2, 0.0)
		await TestHarness.wait_seconds(2.0)

	# ---- abort: gunfire at the scene while the medics work --------------------------------------
	emg.call("clear_all")
	var a_body: Node3D = Game.spawn_npc("civilian_f", walk_p + dir * 5.0, {"activity": "idle"})
	await TestHarness.wait_seconds(0.2)
	if a_body != null:
		a_body.call("kill", "test")
	emg.call("dispatch", "medical", walk_p + dir * 5.0)
	var shot_fired := false
	var fled := false
	var aborted0 := int((emg.get("stats") as Dictionary).get("aborted", 0))
	for i in 240:
		await TestHarness.wait_seconds(0.25)
		var rs3: Array = emg.call("get_active_responses")
		if not shot_fired:
			if rs3.is_empty() or str((rs3[0] as Dictionary)["state"]) != "working" or float((rs3[0] as Dictionary)["time_on_scene"]) < 4.0:
				continue
			EventBus.noise_emitted.emit(walk_p + dir * 12.0, 70.0, "gunshot", null)
			shot_fired = true
			continue
		var crew3: Array = (rs3[0] as Dictionary)["crew"] if not rs3.is_empty() else []
		for c: Variant in crew3:
			if c != null and is_instance_valid(c) and str((c as Node).get("state_tag")) == "flee":
				fled = true
		for s2: Variant in (emg.get("strays") as Array):
			if s2 != null and is_instance_valid(s2) and str((s2 as Node).get("state_tag")) in ["flee", "leaving"]:
				fled = true
		if fled:
			break
	TestHarness.check(shot_fired, "abort: the medics were at work when the shot was fired")
	TestHarness.check(int((emg.get("stats") as Dictionary).get("aborted", 0)) > aborted0, "abort: gunfire close by aborts the job")
	TestHarness.check(fled, "abort: the responders run away")
	emg.call("clear_all")

	# ---- reset_for_respawn / set_enabled -------------------------------------------------------------
	var amb_v: Variant = null
	for r: Dictionary in (emg.call("get_active_responses") as Array):
		amb_v = r["vehicle"]
	emg.call("reset_for_respawn")
	await TestHarness.wait_seconds(0.3)
	TestHarness.check((emg.call("get_active_responses") as Array).is_empty() and (emg.call("get_pending_incidents") as Array).is_empty(),
			"reset_for_respawn clears responses and incidents")
	TestHarness.check(amb_v == null or not is_instance_valid(amb_v) or (amb_v as Node).is_queued_for_deletion(), "reset_for_respawn removes the vehicle")
	emg.call("set_enabled", false)
	var n2: Node3D = Game.spawn_npc("civilian_m", walk_p + dir * 4.0, {"activity": "idle"})
	await TestHarness.wait_seconds(0.2)
	if n2 != null:
		n2.call("kill", "test")
	await TestHarness.wait_seconds(0.5)
	TestHarness.check((emg.call("get_pending_incidents") as Array).is_empty(), "disabled: incidents are ignored")
	emg.call("set_enabled", true)

	# ---- wanted untouched -------------------------------------------------------------------------
	TestHarness.check(crimes_by_responders == 0, "responders never witnessed / reported a crime")
	TestHarness.check(int(Wanted.level) == 0, "the wanted level stayed 0 (%d)" % int(Wanted.level))
	TestHarness.log_line("emergency stats: %s" % str(emg.call("get_debug_info")))

	# ---- AI open item: brain event 'carjacked' (and the traffic module's damaged{carjacked}) ---------
	var tough: Node3D = Game.spawn_npc("civilian_tough", walk_p + dir * 3.0 - right * 2.0, {"activity": "idle"})
	var meek: Node3D = Game.spawn_npc("civilian_f", walk_p + dir * 4.0 - right * 2.5, {"activity": "idle"})
	await TestHarness.wait_seconds(0.4)
	if tough != null and meek != null:
		var bt: Node = tough.get("brain")
		var bm: Node = meek.get("brain")
		bt.call("on_event", tough, "carjacked", {"attacker": Game.player})
		bm.call("on_event", meek, "damaged", {"attacker": Game.player, "amount": 0.0,
				"info": {"type": "melee", "amount": 0.0, "instigator": Game.player, "carjacked": true}})
		await TestHarness.wait_seconds(0.3)
		TestHarness.check(str(bt.call("get_mode_name")) == "fight" and bt.get("carjacked_by") == Game.player,
				"carjacked: a tough local goes for the thief (%s)" % str(bt.call("get_mode_name")))
		TestHarness.check(str(bm.call("get_mode_name")) == "flee" and bm.get("carjacked_by") == Game.player,
				"carjacked (traffic's damaged{carjacked}): a civilian runs (%s)" % str(bm.call("get_mode_name")))
		tough.queue_free()
		meek.queue_free()

	# ---- AI open item: silent takedown witnessed by sight only (last: it reports crimes) ----
	await _silent_harm_check(walk_p, dir, right)
	if is_instance_valid(bystander):
		bystander.queue_free()
	TestHarness.finish()


## A civilian 12 m away facing AWAY from a silent takedown (by the player) must not witness it;
## the same civilian hears a normal (non-silent) assault at that distance (CRIME_HEAR assault 14 m).
func _silent_harm_check(walk_p: Vector3, dir: Vector3, right: Vector3) -> void:
	var peds := Game.get_system("peds")
	var target: Node3D = Game.spawn_npc("civilian_m", walk_p - dir * 4.0, {"yaw": 0.0, "activity": "idle"})
	var w_pos := walk_p - dir * 4.0 - dir * 12.0
	var witness: Node3D = Game.spawn_npc("civilian_f", w_pos, {"activity": "idle"})
	await TestHarness.wait_seconds(0.4)
	if target == null or witness == null:
		TestHarness.check(false, "silent-harm NPCs spawned")
		return
	# the witness faces away from the target (further along -dir)
	var away := -dir
	var face_away := atan2(-away.x, -away.z)
	witness.rotation = Vector3(0.0, face_away, 0.0)
	witness.call("face_position", witness.global_position + away * 5.0)
	var b: Node = witness.get("brain")
	var before := int((peds.get("stats") as Dictionary).get("silent_crimes", 0)) if peds != null else 0
	var info := Dmg.make(30.0, "melee", Game.player, target.global_position + Vector3.UP, Vector3.DOWN,
			{"silent": true, "takedown": true, "knockout": true, "knockout_seconds": 30.0, "knockdown": true})
	target.call("apply_damage", info)
	await TestHarness.wait_seconds(0.3)
	var after := int((peds.get("stats") as Dictionary).get("silent_crimes", 0)) if peds != null else 0
	TestHarness.check(after == before + 1, "a silent takedown is reported as a sight-only crime")
	TestHarness.check(b == null or str(b.get("witness_crime")) == "", "a civilian facing away 12 m off did not witness the silent takedown")
	# control: a loud assault on another civilian at the same spot is heard
	var target2: Node3D = Game.spawn_npc("civilian_m", walk_p - dir * 5.0 + right * 0.6, {"yaw": 0.0, "activity": "idle"})
	await TestHarness.wait_seconds(0.4)
	if target2 != null:
		witness.rotation = Vector3(0.0, face_away, 0.0)
		target2.call("apply_damage", Dmg.make(10.0, "melee", Game.player, target2.global_position + Vector3.UP, Vector3.FORWARD))
		await TestHarness.wait_seconds(0.3)
		TestHarness.check(b != null and str(b.get("witness_crime")) == "assault", "the same civilian hears a loud assault (control)")
	Wanted.clear("cheat")
	for n: Variant in [target, target2, witness]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()


func _collect_yields(out: Dictionary) -> void:
	var tr := Game.get_system("traffic")
	if tr == null or not tr.has_method("get_drivers"):
		return
	for d: Variant in tr.call("get_drivers"):
		if d == null or not (d is Object):
			continue
		var st: Variant = (d as Object).get("siren_t")
		if (st is float or st is int) and float(st) > 0.0:
			out[(d as Object).get("uid")] = true


func _now() -> float:
	return AiSenses.now()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
