extends Node
## POLICE ambient presence at 0 stars (headless, every system incl. traffic):
##   * two patrol cruisers drive around the player (lane walks, obeying signals), beat officers stroll
##     near the police station / downtown plaza, parked cruisers stand in front of the station
##   * a crime committed in front of a beat officer (pistol shots) is known at once (police sighting)
##     and the ambient units respond; after a clear they stand down
##   * taking a parked police cruiser is police_vehicle_theft (2 stars, reported by the player module);
##     the police system lets go of the car
##   tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 400 -UserArgs '--test=pol_ambient','--test-timeout=380','--seed=8','--disable=emergency,wildlife,transit,taxi,activities,radio,ambience,respawn,debug'

var T: Node
var pol: Node
var _reported: Array = []


func _ready() -> void:
	T = TestHarness
	Wanted.crime_became_known.connect(func(id: String, _p: Vector3, src: String) -> void: _reported.append([id, src]))
	await T.wait_seconds(1.0)
	await _run()
	Wanted.clear("cheat")
	Input.action_release("aim")
	Input.action_release("fire")
	T.finish()


func _run() -> void:
	pol = Game.get_system("police")
	var p := Game.player
	if not T.check(pol != null and p != null, "police system + player present"):
		return
	var st := Game.get_location("police_station")
	# between the station and the plaza: both beat anchors are within reach
	p.call("teleport", st.origin + Vector3(0.0, 0.0, 14.0), 0.0)
	var t := 0.0
	var moved := {}
	var start_pos := {}
	while t < 30.0:
		await T.wait_seconds(1.0)
		t += 1.0
		for u: Variant in pol.get("units"):
			var o := u as Object
			var v: Node3D = o.get("vehicle")
			if v == null or not is_instance_valid(v):
				continue
			var k := v.get_instance_id()
			if not start_pos.has(k):
				start_pos[k] = v.global_position
			elif v.global_position.distance_to(start_pos[k]) > 40.0:
				moved[k] = true
	var info: Dictionary = pol.call("get_debug_info")
	T.log_line("ambient %s" % str(info))
	var um: Dictionary = info.get("unit_modes", {})
	var om: Dictionary = info.get("officer_modes", {})
	T.check(int(um.get("patrol", 0)) >= 1, "patrol cruisers on the road at 0 stars (%s)" % str(um))
	T.check(moved.size() >= 1, "patrol cruisers drive around (%d moved > 40 m)" % moved.size())
	T.check(int(om.get("patrol", 0)) >= 2, "beat officers on foot near the station / plaza (%s)" % str(om))
	T.check(int(info.get("station_cars", 0)) >= 1, "parked cruisers in front of the station (%d)" % int(info.get("station_cars", 0)))
	T.check(Wanted.level == 0, "nobody is wanted yet")

	# --- a crime in front of a beat officer
	var beat: Node3D = null
	var best := INF
	for n in get_tree().get_nodes_in_group("police"):
		if not (n is Node3D) or not is_instance_valid(n) or bool(n.get("is_dead")) or n.get("current_vehicle") != null:
			continue
		var b: Variant = n.get("brain")
		if b is Node and str((b as Node).get("role")) == "beat":
			var d := (n as Node3D).global_position.distance_to(p.global_position)
			if d < best:
				best = d
				beat = n as Node3D
	if not T.check(beat != null, "a beat officer exists"):
		return
	# stand 8 m in front of him, facing away, and fire into the air
	var bf := -beat.global_basis.z
	bf.y = 0.0
	var spot := beat.global_position + bf.normalized() * 8.0
	p.call("teleport", spot, atan2(-bf.x, -bf.z))      # back to the officer, shooting into the street
	beat.call("face_position", spot)
	await T.wait_seconds(1.0)
	var inv: Node = p.get("inventory")
	if inv != null:
		inv.call("give_weapon", "pistol", 40)
		inv.call("equip", "pistol")
	await T.wait_seconds(0.5)
	_reported.clear()
	Input.action_press("aim")
	await T.wait_seconds(0.4)
	Input.action_press("fire")
	await T.wait_seconds(0.15)
	Input.action_release("fire")
	await T.wait_seconds(1.0)
	Input.action_release("aim")
	var police_src := false
	for r: Array in _reported:
		if str(r[1]) == "police":
			police_src = true
	T.check(Wanted.level >= 1 and police_src, "gunfire in front of an officer is known at once (level %d, %s)" % [Wanted.level, str(_reported)])
	await T.wait_seconds(4.0)
	var info2: Dictionary = pol.call("get_debug_info")
	var om2: Dictionary = info2.get("officer_modes", {})
	T.check(int(om2.get("engage", 0)) + int(om2.get("arrest", 0)) + int(om2.get("respond", 0)) >= 1,
			"ambient officers respond (%s)" % str(om2))
	Wanted.clear("cheat")
	if inv != null:
		inv.call("holster")
	await T.wait_seconds(3.0)
	var om3: Dictionary = (pol.call("get_debug_info") as Dictionary).get("officer_modes", {})
	T.check(int(om3.get("engage", 0)) == 0 and int(om3.get("arrest", 0)) == 0, "officers calm down after the clear (%s)" % str(om3))

	# --- adopt_patrol: a parked cruiser gets a crew and drives off on patrol
	var cars: Array = pol.get("station_cars")
	if not T.check(not cars.is_empty(), "a parked station cruiser to steal"):
		return
	if cars.size() >= 2:
		var spare: Node3D = cars[1]
		var ok := bool(pol.call("adopt_patrol", spare))
		await T.wait_seconds(6.0)
		var adopted := false
		var dbg := "no unit"
		for u: Variant in pol.get("units"):
			if (u as Object).get("vehicle") == spare:
				dbg = str((u as Object).call("get_debug_info"))
				if str((u as Object).call("get_mode_name")) == "patrol":
					adopted = true
		var valid := is_instance_valid(spare)
		T.check(ok and adopted and valid and spare.get("driver") != null and spare.has_meta("ai_controller"),
				"adopt_patrol: the parked cruiser got a crew and patrols (ok %s, valid %s, level %d, %s, relocated %d)" % [str(ok), str(valid),
				Wanted.level, dbg, int((pol.call("get_debug_info") as Dictionary)["stats"].get("relocated", 0))])
	var car: Node3D = cars[0]
	p.call("teleport", car.global_position + car.global_basis.x * 3.0, 0.0)
	await T.wait_seconds(0.5)
	_reported.clear()
	Input.action_press("enter_vehicle")
	await T.wait_seconds(0.1)
	Input.action_release("enter_vehicle")
	t = 0.0
	while t < 6.0 and p.get("current_vehicle") != car:
		await T.wait_seconds(0.25)
		t += 0.25
	await T.wait_seconds(0.5)
	T.check(p.get("current_vehicle") == car, "the player took the police cruiser")
	var theft := false
	for r: Array in _reported:
		if str(r[0]) == "police_vehicle_theft":
			theft = true
	T.check(theft and Wanted.level >= 2, "police_vehicle_theft known at once -> %d stars" % Wanted.level)
	T.check(not (pol.get("station_cars") as Array).has(car) and not car.has_meta("ai_controller"), "the police system let go of the stolen cruiser")
	T.log_line("POLICE_STATS %s" % str(pol.call("get_debug_info")))
	# --- admin switch
	Wanted.clear("cheat")
	pol.call("set_enabled", false)
	await T.wait_seconds(1.0)
	var info_off: Dictionary = pol.call("get_debug_info")
	T.check(int(info_off.get("units", 0)) == 0 and int(info_off.get("officers_alive", 0)) == 0 			and (pol.call("get_units") as Array).is_empty(), "set_enabled(false) removes every unit (%s)" % str(info_off.get("units")))
	pol.call("set_enabled", true)
	await T.wait_seconds(7.0)
	T.check(int((pol.call("get_debug_info") as Dictionary).get("officers_alive", 0)) >= 1, "set_enabled(true): the ambient presence returns")
