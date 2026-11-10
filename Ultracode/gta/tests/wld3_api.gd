extends Node
## Wildlife API test (headless, real world). Run:
##   tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 400 -UserArgs '--test=wld3_api','--test-timeout=380','--seed=7','--disable=traffic,police,emergency,shops,garage,transit,taxi,activities,radio,ambience,respawn'
## Covers: habitats built, region-correct automatic spawning (hill / town / docks / reef), ground
## following, flee from the player / a gunshot noise / a moving vehicle, coyote bites a dummy target
## (Dmg type "bite"), coyote hunts the player at night, the shark circles and bites an underwater
## dummy and stays in the water, fish stay under water and scatter, birds take off / fly / land,
## damage -> death -> corpse despawn, pet crime only with a civilian witness, caps, toggle,
## reset_for_respawn, frame cost.

const HAB_SPECIES := {
	"hill": ["deer", "rabbit", "boar", "coyote"],
	"wild": ["rabbit", "coyote", "deer"],
	"park": ["dog", "cat", "pigeon", "rabbit"],
	"beach": ["seagull"],
	"coast": ["seagull"],
	"urban": ["dog", "cat", "pigeon"],
	"reef": ["fish_small"],
	"deep": ["shark"],
	"pasture": ["cow"],
}


class Dummy extends Node3D:
	var hits: Array = []
	var is_dead := false

	func apply_damage(info: Dictionary) -> void:
		hits.append(info)

	func get_target_position() -> Vector3:
		return global_position + Vector3.UP * 0.6


var ws: Node = null
var w: Node = null


func _ready() -> void:
	Game.invulnerable = true
	WorldClock.set_hour(10.0)
	if Weather.has_method("set_weather"):
		Weather.set_weather("clear", 0.0)
	await TestHarness.wait_frames(10)
	await _run()


func _run() -> void:
	ws = Game.get_system("wildlife")
	w = Game.world
	if not TestHarness.check(ws != null and w != null, "wildlife system and world present"):
		TestHarness.finish(false)
		return
	var dbg: Dictionary = ws.get_debug_info()
	TestHarness.log_line("habitats: " + str(dbg["habitats"]))
	TestHarness.check(ws.get_habitat_points("hill").size() >= 10, "hill habitat points")
	TestHarness.check(ws.get_habitat_points("coast").size() >= 20, "coast perches")
	TestHarness.check(ws.get_habitat_points("reef").size() >= 20, "reef points")
	TestHarness.check(ws.get_habitat_points("deep").size() >= 3, "deep water points (shark)")
	TestHarness.check(ws.get_species_def("deer").has("pivots"), "species def merged with the manifest")

	await _test_regions()
	await _test_ground_and_flee()
	await _test_coyote_bite()
	await _test_night_hunt()
	await _test_pets_and_charge()
	await _test_fish()
	await _test_birds()
	await _test_shark()
	await _test_death_and_crime()
	await _test_vehicle_flee()
	await _test_caps_and_toggle()
	var st: Dictionary = ws.get("stats")
	TestHarness.log_line("WLD_COST phys_us=%.1f (max %.1f) anim_us=%.1f spawn_us_max=%.0f spawned=%d despawned=%d pooled=%d" % [
			float(st["phys_us"]), float(st["phys_us_max"]), float(st["anim_us"]), float(st["spawn_us_max"]),
			int(st["spawned"]), int(st["despawned"]), int(st["pooled"])])
	TestHarness.finish()


# -------------------------------------------------------------------------------------------------

func _region_ok(a: Node3D) -> bool:
	var hab := String(a.get("habitat"))
	var sp := String(a.get("species"))
	if not HAB_SPECIES.has(hab) or not (HAB_SPECIES[hab] as Array).has(sp):
		return false
	var h: Vector3 = a.get("home") if a.get("home") != null else a.global_position
	if a is AnimalFishSchool:
		h = (a as AnimalFishSchool).anchor
	match hab:
		"hill":
			return String(w.get_district(h)) == "hill"
		"urban":
			return String(w.get_district(h)) in ["residential", "midtown", "downtown", "waterfront", "industrial"]
		"park":
			return h.distance_to(Game.get_location("residential_park").origin) < 55.0
		"wild":
			return String(w.get_surface_at(h)) in ["grass", "sand", "dirt"]
		"beach", "coast":
			for i in 12:
				var ang := TAU * float(i) / 12.0
				if float(w.get_water_depth(h.x + cos(ang) * 75.0, h.z + sin(ang) * 75.0)) > 0.5:
					return true
			return false
		"reef", "deep":
			return float(w.get_water_depth(h.x, h.z)) > 2.5
	return true


func _populate(label: String, focus: Vector3, seconds: float, want_species: Array) -> void:
	ws.clear_all(true)
	ws.set("auto_spawn", true)
	ws.set_focus_override(focus)
	await TestHarness.wait_seconds(seconds)
	var all: Array = ws.get_animals() + ws.get_schools()
	var bad: PackedStringArray = []
	var got := {}
	for a: Node3D in all:
		got[String(a.get("species"))] = int(got.get(String(a.get("species")), 0)) + 1
		if not _region_ok(a):
			bad.append("%s@%s(%s)" % [a.get("species"), a.get("habitat"), str(a.global_position.round())])
	TestHarness.log_line("%s: %d animals %s" % [label, all.size(), str(got)])
	TestHarness.check(all.size() > 0, "%s: animals spawned" % label)
	TestHarness.check(bad.is_empty(), "%s: every animal in a matching region %s" % [label, ", ".join(bad)])
	var any := false
	for s: String in want_species:
		if got.has(s):
			any = true
	TestHarness.check(any, "%s: expected species present (%s)" % [label, ", ".join(want_species)])


func _test_regions() -> void:
	var hill_top := Game.get_location("hill_top").origin
	await _populate("hill", hill_top + Vector3(-20.0, 0.0, 15.0), 6.0, ["deer", "boar", "rabbit", "coyote"])
	# town: a residential pavement point
	var town := Vector3(215.0, 2.65, 105.0)
	var walk: Variant = w.get("walk")
	if walk != null:
		var p: Vector3 = (walk as Object).call("random_point", town, 0.0, 30.0)
		if p.is_finite():
			town = p
	TestHarness.log_line("town focus %s district %s" % [str(town.round()), w.get_district(town)])
	await _populate("town", town, 7.0, ["dog", "cat", "pigeon"])
	await _populate("docks", Vector3(-272.0, 2.5, 90.0), 6.0, ["seagull"])
	await _populate("wreck", Vector3(148.0, 0.0, 285.0), 5.0, ["fish_small"])
	ws.set("auto_spawn", false)
	ws.clear_all(true)


func _hill_point(i: int) -> Vector3:
	var pts: PackedVector3Array = ws.get_habitat_points("hill")
	return pts[i % pts.size()]


func _test_ground_and_flee() -> void:
	# --- ground following of a wandering herd ----------------------------------------------------
	var base := _hill_point(3)
	ws.set_focus_override(base)
	var herd: Array = []
	for i in 4:
		var a: Node3D = ws.spawn_animal(["deer", "boar", "rabbit", "deer"][i], base + Vector3(i * 2.5 - 4.0, 0.0, 1.5),
				{"state": "wander", "persistent": true})
		herd.append(a)
	var start: Array = []
	for a: Node3D in herd:
		start.append(a.global_position)
	var worst := 0.0
	for k in 120:
		await get_tree().physics_frame
		for a: Node3D in herd:
			var p := a.global_position
			worst = maxf(worst, absf(p.y - float(w.get_height(p.x, p.z))))
	await TestHarness.wait_seconds(4.0)
	var moved := 0.0
	for i in herd.size():
		var p: Vector3 = (herd[i] as Node3D).global_position
		worst = maxf(worst, absf(p.y - float(w.get_height(p.x, p.z))))
		moved = maxf(moved, p.distance_to(start[i]))
	TestHarness.check(worst < 0.05, "land animals follow the ground (worst %.3f m)" % worst)
	TestHarness.check(moved > 1.0, "herd wandered (max %.1f m)" % moved)
	# --- flee from a gunshot noise --------------------------------------------------------------
	var deer: Node3D = herd[0]
	var noise := deer.global_position + Vector3(9.0, 0.0, 0.0)
	var d0 := deer.global_position.distance_to(noise)
	EventBus.noise_emitted.emit(noise, 70.0, "gunshot", null)
	await TestHarness.wait_seconds(0.4)
	TestHarness.check(deer.call("get_state_name") == "flee", "deer flees from a gunshot noise (%s)" % deer.call("get_state_name"))
	await TestHarness.wait_seconds(2.0)
	var d1 := deer.global_position.distance_to(noise)
	TestHarness.check(d1 > d0 + 8.0, "deer ran away from the shot (%.1f -> %.1f m, speed %.1f)" % [d0, d1, float(deer.get("speed"))])
	var all_fled := true
	for a: Node3D in herd:
		if a.call("get_state_name") != "flee":
			all_fled = false
	TestHarness.check(all_fled, "the whole herd heard the shot")
	# --- flee from the player ------------------------------------------------------------------
	ws.clear_all(true)
	var pp := Game.player.global_position
	ws.set_focus_override(pp)
	var deer2: Node3D = ws.spawn_animal("deer", pp + Vector3(7.0, 0.0, 0.0), {"persistent": true, "state": "graze"})
	deer2.global_position.y = float(w.get_height(deer2.global_position.x, deer2.global_position.z))
	await TestHarness.wait_seconds(0.8)
	TestHarness.check(deer2.call("get_state_name") == "flee", "deer flees from the player at 7 m (%s)" % deer2.call("get_state_name"))
	ws.clear_all(true)


func _test_coyote_bite() -> void:
	var base := _hill_point(8)
	ws.set_focus_override(base)
	var coy: Node3D = ws.spawn_animal("coyote", base, {"persistent": true})
	var dummy := Dummy.new()
	add_child(dummy)
	var dp := base + Vector3(7.0, 0.0, 3.0)
	dp.y = float(w.get_height(dp.x, dp.z))
	dummy.global_position = dp
	coy.call("attack", dummy)
	var t := 0.0
	while t < 8.0 and dummy.hits.is_empty():
		await TestHarness.wait_seconds(0.1)
		t += 0.1
	TestHarness.check(not dummy.hits.is_empty(), "coyote reached and bit the dummy (%.1f s)" % t)
	if not dummy.hits.is_empty():
		var info: Dictionary = dummy.hits[0]
		TestHarness.check(String(info.get("type")) == "bite" and float(info.get("amount")) > 0.0 and info.get("instigator") == coy,
				"bite damage through Dmg (type %s, %.0f hp)" % [info.get("type"), float(info.get("amount"))])
	await TestHarness.wait_seconds(2.5)
	TestHarness.check(dummy.hits.size() >= 2, "coyote keeps biting (%d bites)" % dummy.hits.size())
	ws.reset_for_respawn()
	await TestHarness.wait_seconds(0.3)
	TestHarness.check(not (String(coy.call("get_state_name")) in ["chase", "stalk"]), "reset_for_respawn calms attackers (%s)" % coy.call("get_state_name"))
	dummy.queue_free()
	ws.clear_all(true)


func _test_pets_and_charge() -> void:
	var pp := Game.player.global_position
	ws.set_focus_override(pp)
	# friendly dog comes over and sits next to the player
	var dog: Node3D = ws.spawn_animal("dog", pp + Vector3(6.0, 0.0, 0.0), {"persistent": true})
	var br: Object = dog.get("brain")
	br.set("friendly", true)
	var t := 0.0
	var seen := {}
	while t < 6.0:
		await TestHarness.wait_seconds(0.25)
		t += 0.25
		seen[String(dog.call("get_state_name"))] = true
		if dog.call("get_state_name") == "sit":
			break
	var dd := Vector2(dog.global_position.x - pp.x, dog.global_position.z - pp.z).length()
	TestHarness.check(dog.call("get_state_name") == "sit" and dd < 3.5, "friendly dog comes over and sits (%.1f m, %s)" % [dd, str(seen.keys())])
	TestHarness.check(float(dog.get("wag")) > 0.3, "and wags its tail (%.2f)" % float(dog.get("wag")))
	ws.clear_all(true)
	# unfriendly dog barks
	var dog2: Node3D = ws.spawn_animal("dog", pp + Vector3(-6.0, 0.0, 0.0), {"persistent": true})
	(dog2.get("brain") as Object).set("friendly", false)
	await TestHarness.wait_seconds(1.0)
	TestHarness.check(dog2.call("get_state_name") == "bark", "unfriendly dog barks at the player (%s)" % dog2.call("get_state_name"))
	ws.clear_all(true)
	# provoked boar charges through a target and turns for another pass
	var base := _hill_point(5)
	ws.set_focus_override(base)
	var boar: Node3D = ws.spawn_animal("boar", base, {"persistent": true})
	var dummy := Dummy.new()
	add_child(dummy)
	var dp := base + Vector3(-8.0, 0.0, 2.0)
	dp.y = float(w.get_height(dp.x, dp.z))
	dummy.global_position = dp
	boar.call("provoke", dummy)
	t = 0.0
	while t < 8.0 and dummy.hits.size() < 2:
		await TestHarness.wait_seconds(0.2)
		t += 0.2
	TestHarness.check(dummy.hits.size() >= 1, "provoked boar charges and gores (%d hits in %.1f s)" % [dummy.hits.size(), t])
	TestHarness.check(int((boar.get("brain") as Object).get("charges")) >= 1 or dummy.hits.size() >= 2, "boar makes repeated passes")
	dummy.queue_free()
	ws.clear_all(true)
	# simulation tiers: a far animal is tier 2 and hidden
	var far: Node3D = ws.spawn_animal("deer", base + Vector3(0.0, 0.0, 0.0), {"persistent": true})
	ws.set_focus_override(base + Vector3(125.0, 0.0, 0.0))
	await TestHarness.wait_seconds(0.6)
	var vis: Node3D = far.get("visual")
	TestHarness.check(int(far.get("sim_tier")) == 2 and vis != null and not vis.visible, "far animal: tier 2, hidden")
	ws.set_focus_override(base + Vector3(60.0, 0.0, 0.0))
	await TestHarness.wait_seconds(0.6)
	TestHarness.check(int(far.get("sim_tier")) == 1 and vis.visible, "mid-range animal: tier 1, visible")
	ws.clear_all(true)


func _test_night_hunt() -> void:
	WorldClock.set_hour(23.0)
	var pp := Game.player.global_position
	ws.set_focus_override(pp)
	var coy: Node3D = ws.spawn_animal("coyote", pp + Vector3(0.0, 0.0, 14.0), {"persistent": true})
	await TestHarness.wait_seconds(1.0)
	var st := String(coy.call("get_state_name"))
	TestHarness.check(st == "stalk" or st == "chase", "coyote hunts a person on foot at night (%s)" % st)
	ws.clear_all(true)
	WorldClock.set_hour(10.0)
	await TestHarness.wait_seconds(0.2)


func _nearest(pts: PackedVector3Array, to: Vector3) -> Vector3:
	var best := pts[0]
	for p in pts:
		if p.distance_to(to) < best.distance_to(to):
			best = p
	return best


func _test_fish() -> void:
	var rp := _nearest(ws.get_habitat_points("reef"), Vector3(148.0, -7.0, 285.0))
	ws.set_focus_override(rp)
	var school: AnimalFishSchool = ws.spawn_fish_school(rp, {"count": 16, "persistent": true})
	TestHarness.check(school != null and school.get_fish_positions().size() == 16, "fish school of 16 = one MultiMesh node")
	if school == null:
		return
	var c0 := school.centre
	var worst_top := -INF
	var worst_bed := INF
	for k in 10:
		await TestHarness.wait_seconds(0.4)
		for p in school.get_fish_positions():
			worst_top = maxf(worst_top, p.y)
			worst_bed = minf(worst_bed, p.y - (Game.WATER_LEVEL - float(w.get_water_depth(p.x, p.z))))
	TestHarness.check(worst_top < Game.WATER_LEVEL - 0.2, "fish stay under the surface (highest %.2f)" % worst_top)
	TestHarness.check(worst_bed > -0.6, "fish stay above the seabed (lowest %.2f m over the bed)" % worst_bed)
	TestHarness.check(school.centre.distance_to(c0) > 0.8, "school swims (%.1f m)" % school.centre.distance_to(c0))
	EventBus.noise_emitted.emit(school.centre + Vector3(3.0, 0.0, 0.0), 70.0, "gunshot", null)
	await get_tree().physics_frame
	TestHarness.check(school.burst_t > 0.0, "school scatters from a shot")
	EventBus.noise_emitted.emit(school.centre, 120.0, "explosion", null)
	await TestHarness.wait_seconds(0.5)
	TestHarness.check(school.get_count() < 16, "an explosion kills fish (%d left)" % school.get_count())
	ws.clear_all(true)


func _test_birds() -> void:
	var coast: PackedVector3Array = ws.get_habitat_points("coast")
	var dock := _nearest(coast, Vector3(-277.0, 2.5, 60.0))
	ws.set_focus_override(dock)
	var flock: Array = ws.spawn_flock("seagull", dock, 3, {"flying": false, "persistent": true})
	TestHarness.check(flock.size() == 3, "gull flock spawned perched")
	await TestHarness.wait_seconds(0.5)
	var g0: Node3D = flock[0]
	var ground0 := float(w.get_height(g0.global_position.x, g0.global_position.z))
	TestHarness.check(g0.global_position.y > ground0 - 0.1 and g0.global_position.y < ground0 + 4.0 and g0.call("get_state_name") in ["perch", "walk"],
			"gull stands on the deck or a prop on it (%s, %.2f m up)" % [g0.call("get_state_name"), g0.global_position.y - ground0])
	EventBus.noise_emitted.emit(dock + Vector3(6.0, 0.0, 0.0), 70.0, "gunshot", null)
	await TestHarness.wait_seconds(2.5)
	var flying := 0
	var max_alt := 0.0
	for g: Node3D in flock:
		var p := g.global_position
		var alt := p.y - maxf(float(w.get_height(p.x, p.z)), 0.0)
		max_alt = maxf(max_alt, alt)
		if alt > 2.0 and String(g.call("get_state_name")) in ["takeoff", "fly", "circle"]:
			flying += 1
	TestHarness.check(flying == 3, "all gulls took off and fly (%d, max %.1f m up)" % [flying, max_alt])
	var rig: AnimalRig = g0.get("rig")
	var wing: Node3D = rig.parts.get("Wing_R") if rig != null else null
	var rots: Array = []
	for k in 8:
		await get_tree().process_frame
		if wing != null:
			rots.append(wing.rotation.z)
	var spread := 0.0
	for r: float in rots:
		spread = maxf(spread, absf(r - float(rots[0])))
	TestHarness.check(wing != null and (spread > 0.02 or String(g0.call("get_state_name")) == "circle"), "wings move in flight (%.2f rad)" % spread)
	# pigeons: fly to another perch and land again
	ws.clear_all(true)
	var town := Vector3(215.0, 2.65, 105.0)
	var walk: Variant = w.get("walk")
	if walk != null:
		var p: Vector3 = (walk as Object).call("random_point", town, 0.0, 30.0)
		if p.is_finite():
			town = p
	ws.set_focus_override(town)
	var pig: Array = ws.spawn_flock("pigeon", town, 4, {"flying": false, "persistent": true})
	await TestHarness.wait_seconds(0.3)
	for b: Node3D in pig:
		b.call("provoke", Game.player)
	await TestHarness.wait_seconds(1.5)
	var up := 0
	for b: Node3D in pig:
		if b.global_position.y > float(w.get_height(b.global_position.x, b.global_position.z)) + 1.5:
			up += 1
	TestHarness.check(up >= 3, "pigeon flock in the air (%d)" % up)
	var landed := 0
	var t := 0.0
	while t < 26.0:
		await TestHarness.wait_seconds(0.5)
		t += 0.5
		landed = 0
		for b: Node3D in pig:
			if b.call("get_state_name") in ["perch", "walk"]:
				landed += 1
		if landed >= 3:
			break
	var where := ""
	for b: Node3D in pig:
		var p := b.global_position
		where += "%s y%.1f/g%.1f " % [b.call("get_state_name"), p.y, float(w.get_height(p.x, p.z))]
	TestHarness.check(landed >= 3, "pigeons landed again after %.1f s (%s)" % [t, where])
	# roofs: force roof perches, scare them again, they must settle on a building top
	TestHarness.log_line("roof candidates: " + str(ws.get_debug_info().get("roofs")))
	ws.set("roof_chance_override", 1.0)
	for b: Node3D in pig:
		b.call("provoke", Game.player)
	var on_roof := 0
	t = 0.0
	while t < 30.0:
		await TestHarness.wait_seconds(0.5)
		t += 0.5
		on_roof = 0
		for b: Node3D in pig:
			var p := b.global_position
			var br: Object = b.get("brain")
			if b.call("get_state_name") == "perch" and br != null and bool(br.get("on_roof")) 					and p.y > float(w.get_height(p.x, p.z)) + 2.5:
				on_roof += 1
		if on_roof >= 2 and t > 2.0:
			break
	TestHarness.check(on_roof >= 2, "pigeons landed on a roof (%d after %.1f s)" % [on_roof, t])
	ws.set("roof_chance_override", -1.0)
	ws.clear_all(true)


func _test_shark() -> void:
	var deep: PackedVector3Array = ws.get_habitat_points("deep")
	var home := _nearest(deep, Vector3(148.0, -6.0, 300.0))
	ws.set_focus_override(home)
	var shark: Node3D = ws.spawn_animal("shark", home, {"persistent": true, "home": home})
	TestHarness.check(shark != null, "shark spawned in deep water")
	if shark == null:
		return
	var dummy := Dummy.new()
	add_child(dummy)
	var dp := home + Vector3(10.0, 0.0, 6.0)
	var depth := float(w.get_water_depth(dp.x, dp.z))
	dp.y = Game.WATER_LEVEL - minf(depth * 0.5, 4.0)
	dummy.global_position = dp
	shark.call("attack", dummy)
	var t := 0.0
	var max_y := -INF
	var states := {}
	while t < 22.0 and dummy.hits.is_empty():
		await TestHarness.wait_seconds(0.2)
		t += 0.2
		max_y = maxf(max_y, shark.global_position.y)
		states[String(shark.call("get_state_name"))] = true
	TestHarness.check(states.has("circle"), "shark circles its prey first (%s)" % str(states.keys()))
	TestHarness.check(not dummy.hits.is_empty(), "shark bites an underwater target (%.1f s)" % t)
	if not dummy.hits.is_empty():
		var info: Dictionary = dummy.hits[0]
		var amt := float(info.get("amount"))
		TestHarness.check(String(info.get("type")) == "bite" and amt >= 25.0 and amt < 60.0, "strong but survivable bite (%.0f hp)" % amt)
	await TestHarness.wait_seconds(1.5)
	TestHarness.check(String(shark.call("get_state_name")) == "retreat", "shark retreats after the bite (%s)" % shark.call("get_state_name"))
	TestHarness.check(max_y < Game.WATER_LEVEL - 0.3, "shark stayed under water (max y %.2f)" % max_y)
	dummy.queue_free()
	ws.clear_all(true)
	# the real player swimming in the basin is noticed and circled
	var pl := Game.player
	if pl == null or not pl.has_method("teleport") or pl.get("is_swimming") == null:
		TestHarness.log_line("player module unavailable: swimmer check skipped")
		return
	var back := pl.global_position
	var sp := home + Vector3(14.0, 0.0, 0.0)
	pl.call("teleport", Vector3(sp.x, 0.2, sp.z), 0.0)
	await TestHarness.wait_seconds(1.5)
	TestHarness.log_line("player swimming %s underwater %s at %s" % [pl.get("is_swimming"), pl.get("is_underwater"), str(pl.global_position.round())])
	var shark2: Node3D = ws.spawn_animal("shark", home, {"persistent": true, "home": home})
	var circ := false
	t = 0.0
	while t < 10.0 and not circ:
		await TestHarness.wait_seconds(0.25)
		t += 0.25
		var br: Object = shark2.get("brain")
		circ = shark2.call("get_state_name") == "circle" and br != null and br.get("prey") == pl
	TestHarness.check(circ, "shark notices and circles the swimming player (%.1f s)" % t)
	ws.clear_all(true)
	pl.call("teleport", back, 0.0)
	await TestHarness.wait_seconds(0.5)


func _test_death_and_crime() -> void:
	var base := _hill_point(12)
	ws.set_focus_override(base)
	ws.set("corpse_time_mult", 0.06)
	var deer: Node3D = ws.spawn_animal("deer", base, {"persistent": false, "state": "graze"})
	var crimes0 := int((ws.get("stats") as Dictionary)["pet_crimes"])
	deer.call("apply_damage", Dmg.make(30.0, "bullet", Game.player, deer.call("get_target_position"), Vector3.RIGHT))
	TestHarness.check(not bool(deer.get("is_dead")) and float(deer.get("health")) < 70.0, "deer takes damage (%.0f hp)" % float(deer.get("health")))
	deer.call("apply_damage", Dmg.make(80.0, "bullet", Game.player, deer.call("get_target_position"), Vector3.RIGHT))
	TestHarness.check(bool(deer.get("is_dead")) and (deer as CollisionObject3D).collision_layer == 0, "deer dies, collision off")
	await TestHarness.wait_seconds(0.8)
	var vis: Node3D = deer.get("visual")
	var roll := absf(vis.rotation.z) if vis != null else 0.0
	TestHarness.check(roll > 1.2, "corpse lies on its side (roll %.2f rad)" % roll)
	TestHarness.check(int((ws.get("stats") as Dictionary)["pet_crimes"]) == crimes0, "killing a deer is not a crime")
	var t := 0.0
	while t < 6.0 and ws.get_animals().has(deer):
		await TestHarness.wait_seconds(0.25)
		t += 0.25
	TestHarness.check(not ws.get_animals().has(deer), "corpse despawned (%.1f s)" % t)
	ws.set("corpse_time_mult", 1.0)
	# --- dog harmed with nobody around: no report ---------------------------------------------------
	var dog: Node3D = ws.spawn_animal("dog", base + Vector3(3.0, 0.0, 0.0), {"persistent": true})
	dog.call("apply_damage", Dmg.make(5.0, "melee", Game.player, dog.call("get_target_position"), Vector3.RIGHT))
	TestHarness.check(int((ws.get("stats") as Dictionary)["pet_crimes"]) == crimes0, "no witness: harming a dog is not reported")
	ws.clear_all(true)
	# --- dog harmed in front of a civilian: assault report -------------------------------------------
	var peds := Game.get_system("peds")
	if peds == null:
		TestHarness.log_line("peds disabled: pet witness check skipped")
		return
	var np := base + Vector3(0.0, 0.0, 6.0)
	np.y = float(w.get_height(np.x, np.z))
	var npc: Node3D = Game.spawn_npc("civilian_m", np, {"persistent": true, "yaw": 0.0})
	await TestHarness.wait_seconds(0.3)
	var dpos := base + Vector3(0.0, 0.0, 2.0)
	dpos.y = float(w.get_height(dpos.x, dpos.z))
	var dog2: Node3D = ws.spawn_animal("dog", dpos, {"persistent": true})
	dog2.call("apply_damage", Dmg.make(5.0, "melee", Game.player, dog2.call("get_target_position"), Vector3.RIGHT))
	var crimes1 := int((ws.get("stats") as Dictionary)["pet_crimes"])
	TestHarness.check(crimes1 == crimes0 + 1, "dog harmed in front of a civilian -> assault report (%d)" % (crimes1 - crimes0))
	dog2.call("apply_damage", Dmg.make(5.0, "melee", Game.player, dog2.call("get_target_position"), Vector3.RIGHT))
	TestHarness.check(int((ws.get("stats") as Dictionary)["pet_crimes"]) == crimes1, "one report per burst")
	if npc != null and is_instance_valid(npc):
		npc.queue_free()
	ws.clear_all(true)
	if Wanted.has_method("clear"):
		Wanted.clear("cheat")


func _test_vehicle_flee() -> void:
	var base := _hill_point(16)
	ws.set_focus_override(base)
	var deer: Node3D = ws.spawn_animal("deer", base, {"persistent": true, "state": "graze"})
	var cp := base + Vector3(14.0, 1.2, 0.0)
	cp.y = float(w.get_height(cp.x, cp.z)) + 0.6
	var car: Node3D = Game.spawn_vehicle("sedan", Transform3D(Basis(Vector3.UP, PI * 0.5), cp), {"owner_tag": "civilian"})
	if car == null:
		TestHarness.log_line("vehicles missing: vehicle flee check skipped")
		ws.clear_all(true)
		return
	for k in 40:
		if car is RigidBody3D:
			(car as RigidBody3D).linear_velocity = Vector3(-8.0, (car as RigidBody3D).linear_velocity.y, 0.0)
		await get_tree().physics_frame
	var st := String(deer.call("get_state_name"))
	TestHarness.check(st == "flee" or bool(deer.get("is_dead")), "deer flees from an approaching vehicle (%s)" % st)
	car.queue_free()
	ws.clear_all(true)
	await get_tree().physics_frame
	# a car at speed runs a cow over (VehicleBase strikes group "animal": damage + knock_down);
	# a cow because it only trots away, so the test does not depend on the escape direction
	var boar: Node3D = ws.spawn_animal("cow", base + Vector3(-5.0, 0.0, 5.0), {"persistent": true, "state": "graze"})
	var bp := boar.global_position
	var cp2 := bp + Vector3(7.0, 0.0, 0.0)
	cp2.y = float(w.get_height(cp2.x, cp2.z)) + 0.55
	var car2: Node3D = Game.spawn_vehicle("sedan", Transform3D(Basis(Vector3.UP, PI * 0.5), cp2), {"owner_tag": "civilian"})
	var h0 := float(boar.get("health"))
	for k in 50:
		if is_instance_valid(car2) and car2 is RigidBody3D:
			var rb := car2 as RigidBody3D
			var to := boar.global_position - rb.global_position
			to.y = 0.0
			rb.linear_velocity = to.normalized() * 16.0 + Vector3(0.0, rb.linear_velocity.y, 0.0)
			if rb.has_method("set_inputs"):
				rb.call("set_inputs", 0.6, 0.0, 0.0, false)     # wakes the vehicle (idle cars skip their sweep)
		await get_tree().physics_frame
		if float(boar.get("health")) < h0:
			break
	TestHarness.check(float(boar.get("health")) < h0, "a speeding car hits the cow (%.0f -> %.0f hp, %s)" % [h0, float(boar.get("health")), boar.call("get_state_name")])
	if is_instance_valid(car2):
		car2.queue_free()
	ws.clear_all(true)


func _test_caps_and_toggle() -> void:
	ws.set("auto_spawn", true)
	var worst := 0
	var worst_cat := {"land": 0, "bird": 0, "water": 0}
	var species_over: PackedStringArray = []
	for focus: Vector3 in [Vector3(160.0, 2.0, 245.0), Vector3(210.0, 20.0, -110.0), Vector3(180.0, 2.65, 40.0)]:
		ws.clear_all(true)
		ws.set_focus_override(focus)
		for k in 16:
			await TestHarness.wait_seconds(0.5)
			var c: Dictionary = ws.get_counts()
			worst = maxi(worst, int(c["total"]))
			for cat: String in worst_cat:
				worst_cat[cat] = maxi(int(worst_cat[cat]), int(c.get(cat, 0)))
			for sp: String in ["deer", "boar", "coyote", "dog", "cat", "rabbit", "seagull", "pigeon", "shark", "fish_small"]:
				if int(c.get(sp, 0)) > int(ws.get_species_def(sp).get("cap", 99)):
					species_over.append(sp)
		TestHarness.log_line("caps at %s: %s" % [str(focus.round()), str(ws.get_counts())])
	TestHarness.check(worst > 4 and worst <= 16, "population within the cap of 16 (peak %d)" % worst)
	TestHarness.check(int(worst_cat["land"]) <= 9 and int(worst_cat["bird"]) <= 7 and int(worst_cat["water"]) <= 4,
			"category caps hold %s" % str(worst_cat))
	TestHarness.check(species_over.is_empty(), "species caps hold %s" % ", ".join(species_over))
	# admin toggle
	Game.set_system_enabled("wildlife", false)
	await TestHarness.wait_seconds(1.5)
	TestHarness.check(ws.get_count() == 0, "toggle off removes every animal (%d)" % ws.get_count())
	Game.set_system_enabled("wildlife", true)
	await TestHarness.wait_seconds(4.0)
	TestHarness.check(ws.get_count() > 0, "toggle on repopulates (%d)" % ws.get_count())
	ws.clear_focus_override()
