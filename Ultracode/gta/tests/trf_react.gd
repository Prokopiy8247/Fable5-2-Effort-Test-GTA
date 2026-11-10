extends Node
## TRAFFIC reactions (headless, real world + vehicles, no ambient traffic):
##   gunfire nearby -> panic driving or abandoning the car; light bump -> brake + honk;
##   heavy crash -> abandon / drive off fast / shaken stop; siren behind -> pull right + slow;
##   a stand-in player aiming a gun at a waiting driver from close range -> surrender or flee;
##   carjack through occupant_enter (eviction path) -> control dropped cleanly;
##   explosion with the driver aboard -> cleaned up; release reasons.
##
## Run: tools\godot.ps1 -Mode headless -Frames 6000 -TimeoutSec 300 -UserArgs '--test=trf_react','--no_player',
##      '--disable=police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups,interactions'

const FAKE_PLAYER_SRC := "extends Node3D
var is_aiming := true
var is_dead := false
var in_stealth := false
var is_crouching := false
var is_sprinting := false
var inventory: Node = null
var visibility_factor := 1.0
var current_vehicle: Node3D = null
var aim_target := Vector3.ZERO
func is_armed() -> bool:
	return true
func get_aim_ray() -> Dictionary:
	var o := global_position + Vector3.UP * 1.5
	return {\"origin\": o, \"direction\": (aim_target - o).normalized()}
"

const THIEF_SRC := "extends Node3D
var is_aiming := false
var is_dead := false
var in_stealth := false
var is_crouching := false
var is_sprinting := false
var inventory: Node = null
var visibility_factor := 1.0
var current_vehicle: Node3D = null
func on_vehicle_ejected(_v: Node, _xf: Transform3D, _impulse: Vector3) -> void:
	pass
"

var sys: TrafficSystem = null
var L: TrafficLanes = null
var lane_a: int = -1


func _ready() -> void:
	await _run()


func _spawn(off: float, spec: String = "sedan") -> TrafficDriver:
	# spawn_traffic_vehicle refuses an occupied spot (e.g. a car abandoned there): try a bit further on
	for k in 4:
		var o := off + 7.0 * float(k)
		var v := sys.spawn_traffic_vehicle(lane_a, o, spec)
		if v == null:
			v = sys.spawn_traffic_vehicle(lane_a, o)
		if v != null:
			return sys.get_driver(v)
	return null


func _run() -> void:
	sys = Game.get_system("traffic") as TrafficSystem
	if not TestHarness.check(sys != null and sys.lanes != null, "traffic system with lanes"):
		TestHarness.finish(false, "no traffic")
		return
	L = sys.lanes
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(12.0)
	if "paused" in WorldClock:
		WorldClock.paused = true
	# the longest outer arterial lane: room for several cars, no junction for a while
	var best := 0.0
	for i in L.count:
		if L.kind[i] == TrafficLanes.KIND_ARTERIAL and L.length[i] > best and L.index[i] == L.lanes_per_dir[i] - 1:
			best = L.length[i]
			lane_a = i
	TestHarness.log_line("test lane %d length %.0f" % [lane_a, best])
	var mid := L.lane_point(lane_a, best * 0.5)
	sys.set_focus_override(mid)
	sys.set_density(0.0)
	sys.set_enabled(false)
	sys.set_enabled(true)
	await TestHarness.wait_physics_frames(5)

	# ---------------------------------------------------------------- gunfire
	var a := _spawn(10.0)
	var b := _spawn(30.0)
	if not TestHarness.check(a != null and b != null, "two test cars spawned"):
		TestHarness.finish(false, "spawn failed")
		return
	await TestHarness.wait_seconds(1.5)
	var shot_pos := a.body.global_position + Vector3(5.0, 0.0, 3.0)
	EventBus.noise_emitted.emit(shot_pos, 70.0, "gunshot", null)
	await TestHarness.wait_physics_frames(2)
	TestHarness.check(a.panic_t > 0.0 or a.release_reason == "abandon", "gunshot 6 m away: panic driving or abandoning (panic %.1f, release '%s')" % [a.panic_t, a.release_reason])
	if a.panic_t > 0.0:
		await TestHarness.wait_seconds(1.0)
		TestHarness.check(a.target_speed > L.limit[a.lane] * 1.05 or a.d_line < 40.0 or a.lead_gap < 30.0, "a panicking driver drives faster than the limit (target %.1f, limit %.1f)" % [a.target_speed, L.limit[a.lane]])
	elif a.release_reason == "abandon":
		await TestHarness.wait_seconds(2.5)
		TestHarness.check(sys.get_driver(a.body) == null, "the scared driver left the car once it stopped")
		TestHarness.check(is_instance_valid(a.body) and a.body.get("driver") == null and not a.body.has_meta("ai_controller"), "abandoned car has no driver / ai_controller")

	# ---------------------------------------------------------------- light bump (a fresh, calm car)
	b = _spawn(100.0)
	if not TestHarness.check(b != null, "bump test car"):
		TestHarness.finish(false, "spawn failed")
		return
	await TestHarness.wait_seconds(1.0)
	var honks0 := int(sys.stats["honks"])
	EventBus.vehicle_collision.emit(b.body, a.body if is_instance_valid(a.body) else null, 3.0 * b.body.mass, b.body.global_position)
	await TestHarness.wait_physics_frames(2)
	TestHarness.check(b.brake_t > 0.0, "light bump: the driver brakes (brake_t %.2f)" % b.brake_t)
	TestHarness.check(int(sys.stats["honks"]) > honks0, "light bump: the driver honks")
	await TestHarness.wait_seconds(2.0)

	# ---------------------------------------------------------------- heavy crash
	var c := _spawn(60.0)
	await TestHarness.wait_seconds(1.0)
	if TestHarness.check(c != null, "crash test car"):
		EventBus.vehicle_collision.emit(c.body, b.body, 10.0 * c.body.mass, c.body.global_position)
		await TestHarness.wait_physics_frames(2)
		var reacted := c.release_reason == "crash" or c.panic_t > 0.0 or c.brake_t >= 2.0
		TestHarness.check(c.crash_reacted and reacted, "heavy crash: abandon / drive off / shaken stop (release '%s', panic %.1f, brake %.1f)" % [c.release_reason, c.panic_t, c.brake_t])
		# force the "flee on foot" branch to verify it end to end
		c.release_reason = "crash"
		c.release_t = 0.3
		c.panic_t = 0.0
		var cv := c.body
		await TestHarness.wait_seconds(3.0)
		TestHarness.check(sys.get_driver(cv) == null and is_instance_valid(cv) and cv.get("driver") == null, "crash: the driver got out once the car stopped")
		TestHarness.check(int(cv.get("indicator")) == 2, "abandoned car shows hazard lights")

	# ---------------------------------------------------------------- siren behind
	await _clear()
	var e := _spawn(40.0)
	await TestHarness.wait_seconds(1.5)
	var cop: Node3D = null
	if e != null:
		var behind := e.body.global_transform * Vector3(0.0, 0.0, 14.0)
		var xf := Transform3D(e.body.global_transform.basis, Vector3(behind.x, e.body.global_position.y, behind.z))
		cop = Game.spawn_vehicle("police_cruiser", xf, {"owner_tag": "police", "siren": true, "engine_on": true})
	if TestHarness.check(cop != null and bool(cop.get("siren_on")), "police cruiser with siren behind a traffic car"):
		await TestHarness.wait_seconds(1.2)
		TestHarness.check(e.siren_t > 0.0, "the driver noticed the siren (siren_t %.1f)" % e.siren_t)
		TestHarness.check(e.lateral_target > 0.3 and e.target_speed <= 3.01, "pulls right (%.2f m) and slows (target %.1f m/s)" % [e.lateral_target, e.target_speed])
		var vm := Game.get_system("vehicles")
		if vm != null:
			vm.despawn_vehicle(cop)

	# ---------------------------------------------------------------- gun aimed at a waiting driver
	await _clear()
	var f := _spawn(40.0)
	await TestHarness.wait_seconds(0.5)
	if TestHarness.check(f != null, "aim test car"):
		f.brake_t = 6.0                     # waits (like at a light)
		await TestHarness.wait_seconds(2.0)
		var gs := GDScript.new()
		gs.source_code = FAKE_PLAYER_SRC
		gs.reload()
		var fake := Node3D.new()
		fake.set_script(gs)
		fake.name = "FakeAimingPlayer"
		Game.main.add_child(fake)
		var side := f.body.global_transform.basis.x
		fake.global_position = f.dummy.global_position + side * -5.0 + Vector3.DOWN * 0.6
		fake.set("aim_target", f.dummy.global_position + Vector3.UP * 0.55)
		var prev_player := Game.player
		Game.player = fake
		await TestHarness.wait_seconds(1.2)
		Game.player = prev_player
		TestHarness.check(f.reacted_aim and (f.release_reason == "surrender" or f.panic_t > 0.0), "gun aimed at the driver: surrender or flee (release '%s', panic %.1f)" % [f.release_reason, f.panic_t])
		fake.queue_free()

	# ---------------------------------------------------------------- carjack through occupant_enter (eviction path)
	await _clear()
	var g := _spawn(40.0)
	await TestHarness.wait_seconds(0.8)
	if TestHarness.check(g != null, "carjack test car"):
		var gv := g.body
		g.brake_t = 3.0
		await TestHarness.wait_seconds(1.5)
		var ts := GDScript.new()
		ts.source_code = THIEF_SRC
		ts.reload()
		var thief := Node3D.new()
		thief.set_script(ts)
		thief.name = "FakeThief"
		Game.main.add_child(thief)
		var released0 := int(sys.stats["released"])
		gv.call("occupant_enter", thief, 0)
		await TestHarness.wait_physics_frames(3)
		TestHarness.check(sys.get_driver(gv) == null, "eviction by occupant_enter: traffic lets go of the car")
		TestHarness.check(not gv.has_meta("ai_controller") and gv.get("driver") == thief, "the new occupant drives, ai_controller removed")
		TestHarness.check(int(sys.stats["released"]) > released0, "eviction counted as a release")
		gv.call("occupant_exit", 0)
		thief.queue_free()

	# ---------------------------------------------------------------- explosion with the driver aboard
	await _clear()
	var h := _spawn(40.0)
	await TestHarness.wait_seconds(0.8)
	if TestHarness.check(h != null, "explosion test car"):
		var hv := h.body
		var n0 := sys.get_vehicle_count()
		hv.call("explode", null)
		await TestHarness.wait_physics_frames(4)
		TestHarness.check(sys.get_driver(hv) == null and sys.get_vehicle_count() == n0 - 1, "destroyed car: the driver is cleaned up (%d -> %d)" % [n0, sys.get_vehicle_count()])
		TestHarness.check(not is_instance_valid(hv) or (hv.get("driver") == null and not hv.has_meta("ai_controller")), "wreck has no driver / ai_controller")

	# ---------------------------------------------------------------- slow car ahead on the arterial -> lane change
	await _clear()
	var slow := _spawn(30.0)
	var fast := _spawn(8.0)
	if TestHarness.check(slow != null and fast != null, "lane change test cars"):
		slow.speed_factor = 0.25
		fast.speed_factor = 1.05
		fast.lc_cd = 0.0
		var lc0 := int(sys.stats["lane_changes"])
		for i in 40:
			await TestHarness.wait_seconds(0.25)
			if fast.lane != lane_a:
				break
		TestHarness.check(fast.lane != lane_a and int(sys.stats["lane_changes"]) > lc0, "stuck behind a slow car on the arterial: changes lane (lane %d -> %d)" % [lane_a, fast.lane])
		# (review: while the car still overlaps its old lane it keeps its distance to the slow car there,
		# so the move takes a little longer than the old 3 s)
		await TestHarness.wait_seconds(4.0)
		TestHarness.check(absf(fast.cross_track(L, fast.body.global_position)) < 0.8, "lane change completed: on the new lane centre (%.2f m)" % fast.cross_track(L, fast.body.global_position))

	# ---------------------------------------------------------------- broken-down car in a one-lane street -> honk, go around
	await _clear()
	var street := -1
	var sbest := 0.0
	for i in L.count:
		if L.kind[i] == TrafficLanes.KIND_STREET and L.lanes_per_dir[i] == 1 and L.length[i] > sbest and L.spawnable[i] == 1:
			sbest = L.length[i]
			street = i
	if TestHarness.check(street >= 0, "a long one-lane street (%d, %.0f m)" % [street, sbest]):
		var bp := L.lane_point(street, 45.0)
		sys.set_focus_override(bp)
		var bd := L.lane_dir(street, 45.0)
		var wreck := Game.spawn_vehicle("van", Transform3D(Basis(Vector3.UP, atan2(-bd.x, -bd.z)), bp), {"owner_tag": "civilian", "engine_on": false})
		await TestHarness.wait_physics_frames(2)
		var vs := sys.spawn_traffic_vehicle(street, 8.0, "sedan")
		var dq: TrafficDriver = sys.get_driver(vs)
		if TestHarness.check(wreck != null and dq != null, "stalled van + a car behind it"):
			var h0 := int(sys.stats["honks"])
			var went_around := false
			var passed := false
			for i in 120:
				await TestHarness.wait_seconds(0.25)
				if not dq.is_valid():
					break
				if dq.bypass_t > 0.0 or dq.lateral_target < -1.0:
					went_around = true
				if dq.s > 45.0 + 8.0:
					passed = true
					break
			TestHarness.log_line("blocked car: honks %d, bypasses %d, reverses %d, s %.1f" % [int(sys.stats["honks"]) - h0, int(sys.stats["bypasses"]), int(sys.stats["reverses"]), dq.s if dq.is_valid() else -1.0])
			TestHarness.check(int(sys.stats["honks"]) > h0, "blocked by a stalled van: honks")
			TestHarness.check(went_around, "blocked for long: goes around through the free opposite lane")
			TestHarness.check(passed, "got past the stalled van")
		if wreck != null and is_instance_valid(wreck):
			sys.despawn_vehicle_node(wreck)

	# ---------------------------------------------------------------- release reasons
	var peds := Game.get_system("peds")
	sys.set_focus_override(mid)
	await _clear()
	var k := _spawn(90.0)
	if k != null:
		var kv := k.body
		var arch := k.archetype
		var npc: Node3D = sys.release_vehicle(kv, "surrender")
		if peds == null:
			TestHarness.check(npc == null, "surrender release without a peds system returns null")
		else:
			TestHarness.check(npc != null and is_instance_valid(npc), "surrender: the driver got out as a real NPC (%s)" % arch)
			if npc != null:
				TestHarness.check(npc.global_position.distance_to(kv.global_position) < 4.0, "the NPC stands beside the car (%.1f m)" % npc.global_position.distance_to(kv.global_position))
				TestHarness.check(str(npc.get("archetype_id")) == arch, "NPC archetype matches the driver (%s / %s)" % [str(npc.get("archetype_id")), arch])
		TestHarness.check(not kv.has_meta("ai_controller") and kv.get("driver") == null, "surrender release cleans the vehicle")
	if peds != null:
		# carjack by the (stand-in) player through release_vehicle, like PlayerVehicleInteraction.pull_out
		await _clear()
		var j := _spawn(60.0)
		if TestHarness.check(j != null, "carjack-release test car"):
			j.brake_t = 4.0
			await TestHarness.wait_seconds(1.5)
			var gs2 := GDScript.new()
			gs2.source_code = THIEF_SRC
			gs2.reload()
			var thief2 := Node3D.new()
			thief2.set_script(gs2)
			thief2.name = "FakeCarjacker"
			Game.main.add_child(thief2)
			thief2.global_position = j.body.global_position + j.body.global_transform.basis.x * -2.5
			var prev2 := Game.player
			Game.player = thief2
			var jv := j.body
			var victim: Node3D = sys.release_vehicle(jv, "carjacked")
			# (the stand-in player stays: the PedSystem recycles NPCs that are far from the player)
			TestHarness.check(victim != null and is_instance_valid(victim), "carjacked: release_vehicle returns the driver as an NPC")
			if victim != null and is_instance_valid(victim):
				await TestHarness.wait_seconds(1.0)
				var b2: Variant = victim.get("brain")
				var mode := str(b2.call("get_mode_name")) if b2 != null and is_instance_valid(b2) and (b2 as Object).has_method("get_mode_name") else "?"
				TestHarness.log_line("carjacked driver %s reacts: mode %s state %s" % [str(victim.get("archetype_id")), mode, str(victim.get("state_tag"))])
				TestHarness.check(mode in ["fight", "flee", "hands_up", "cower", "recover"] or str(victim.get("state_tag")) in ["flee", "fight"], "the carjacked driver reacts (mode %s)" % mode)
			# a tough driver fights back
			var j2 := _spawn(110.0)
			if j2 != null:
				j2.archetype = "civilian_tough"
				j2.brake_t = 4.0
				await TestHarness.wait_seconds(1.5)
				thief2.global_position = j2.body.global_position + j2.body.global_transform.basis.x * -2.5
				Game.player = thief2
				var tough: Node3D = sys.release_vehicle(j2.body, "carjacked")
				Game.player = thief2
				if TestHarness.check(tough != null and is_instance_valid(tough), "tough driver released as an NPC"):
					for step in 6:
						var bb: Variant = tough.get("brain")
						TestHarness.log_line("tough t+%.1f: brain %s mode %s tough %s state %s fight_target %s" % [float(step) * 0.1,
								str(bb), str(bb.call("get_mode_name")) if bb != null else "-", str(bb.get("_tough")) if bb != null else "-",
								str(tough.get("state_tag")), str(bb.get("fight_target")) if bb != null else "-"])
						await TestHarness.wait_seconds(0.1)
					var b3: Variant = tough.get("brain")
					var m3 := str(b3.call("get_mode_name")) if b3 != null and is_instance_valid(b3) and (b3 as Object).has_method("get_mode_name") else "?"
					TestHarness.check(m3 == "fight", "carjacked civilian_tough fights back (mode %s)" % m3)
				Game.player = prev2
			thief2.queue_free()
	var st: Dictionary = sys.get_debug_info()
	TestHarness.log_line("stats: %s" % str(st))
	TestHarness.check(int(st["red_violations"]) == 0, "no red light run by a calm driver (%d)" % int(st["red_violations"]))
	TestHarness.finish()


func _clear() -> void:
	sys.clear_all()
	await TestHarness.wait_physics_frames(3)
