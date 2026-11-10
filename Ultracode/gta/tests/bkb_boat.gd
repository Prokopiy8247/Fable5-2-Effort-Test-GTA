extends Node
## Boat test in the real world with the environment's waves.
##   tools\godot.ps1 -Mode headless -Frames 12000 -TimeoutSec 540 -UserArgs '--test=bkb_boat','--test-timeout=500','--disable=traffic,peds,police,emergency,wildlife'
## Checks: moorings at boot (boats at the "boat" spawn points, upright, at the waterline); the
## speedboat at boat_spawn floats at the waterline with the player aboard; full throttle reaches
## 15-22 m/s with bow rise; turns right and left; coasts to a stop; stays upright for 30 s
## without input; runs aground on the beach without breaking or flipping and reverses off; the
## player exits onto the deck, and boards again from the water.

const DT := 1.0 / 60.0

var _rows: Array[String] = []
var _min_up: float = 1.0


func _ready() -> void:
	Game.invulnerable = true
	await TestHarness.wait_physics_frames(30)
	await _run()


func _run() -> void:
	var pl := Game.player
	var root := Game.get_entities_root()
	var moorings: Node = root.get_node_or_null("BoatMoorings") if root != null else null
	TestHarness.check(moorings != null, "boat moorings created at boot")
	var boat: Boat = null
	if moorings != null:
		var slips: Array = moorings.get("slips")
		var kinds: Array[String] = []
		for i in slips.size():
			var v := moorings.call("get_slip_vehicle", i) as Boat
			if v == null:
				continue
			kinds.append(v.spec_id)
			if i == 0:
				boat = v
		_rows.append("moorings: %s" % ", ".join(kinds))
		TestHarness.check(kinds.size() >= 3, "at least 3 boats moored (%d)" % kinds.size())
		TestHarness.check(kinds.has("jetski") and kinds.has("dinghy"), "jetski and dinghy moored too")
		await TestHarness.wait_seconds(4.0)
		for i in slips.size():
			var v := moorings.call("get_slip_vehicle", i) as Boat
			if v == null:
				continue
			var dy := v.global_position.y - v.get_surface_height()
			var up := v.global_transform.basis.y.y
			var off := Vector2(v.global_position.x - (slips[i]["placed"] as Transform3D).origin.x, v.global_position.z - (slips[i]["placed"] as Transform3D).origin.z).length()
			_rows.append("moored %s: waterline offset %.3f m, up.y %.3f, drift %.2f m, moored=%s" % [v.spec_id, dy, up, off, v.moored])
			TestHarness.check(absf(dy) < 0.12 and up > 0.97, "moored %s floats level at its waterline (dy %.3f, up %.3f)" % [v.spec_id, dy, up])
			TestHarness.check(off < 1.5, "moored %s stays at its berth (%.2f m)" % [v.spec_id, off])
	if moorings != null:
		await _small_craft(moorings)
	if boat == null or boat.spec_id != "speedboat":
		var bs := Game.get_location("boat_spawn")
		boat = Game.spawn_vehicle("speedboat", bs, {"owner_tag": "parked"}) as Boat
	if not TestHarness.check(boat != null, "speedboat available at boat_spawn"):
		TestHarness.finish(false, "no speedboat")
		return
	EventBus.vehicle_damaged.connect(_on_damaged.bind(boat))
	EventBus.vehicle_collision.connect(_on_collision.bind(boat))
	var bs_pos := Game.get_location("boat_spawn").origin
	TestHarness.check(Vector2(boat.global_position.x - bs_pos.x, boat.global_position.z - bs_pos.z).length() < 4.0, "speedboat sits at boat_spawn")

	# --- board from the pier: stand on the deck planks beside the moored boat, press enter
	await _pier_boarding(pl, boat)
	# --- (re)board instantly and float with the camera close (waves only exist near the camera)
	if pl.get("current_vehicle") != boat:
		pl.call("enter_vehicle", boat, 0, true)
	await TestHarness.wait_seconds(5.0)
	TestHarness.check(pl.get("current_vehicle") == boat and boat.is_player_driven, "player aboard the speedboat")
	TestHarness.check(not boat.moored, "boarding casts off the mooring line")
	var dy0 := boat.global_position.y - boat.get_surface_height()
	TestHarness.check(absf(dy0) < 0.1, "floats at the waterline (origin %.3f m from the surface)" % dy0)
	TestHarness.check(boat.afloat and boat.global_transform.basis.y.y > 0.97, "afloat and level")
	_rows.append("at rest: waterline offset %.3f m, submerged %.2f, trim %.1f deg" % [dy0, boat.submerged, boat.trim_deg])

	# --- full throttle south out of the marina
	Input.action_press("move_forward")
	var t := 0.0
	var vmax := 0.0
	var t15 := -1.0
	var trim_peak := 0.0
	var wake_seen := false
	while t < 22.0:
		await get_tree().physics_frame
		t += DT
		var sp := boat.get_forward_speed()
		vmax = maxf(vmax, sp)
		if t15 < 0.0 and sp >= 15.0:
			t15 = t
		trim_peak = maxf(trim_peak, boat.trim_deg)
		_track_up(boat)
		if not boat._wake_handles.is_empty():
			wake_seen = true
	var trim_top := boat.trim_deg
	_rows.append("speed run: top %.1f m/s (%.0f km/h), 0-15 m/s %.1f s, bow rise peak %.1f deg, at top %.1f deg, prop wet %s" % [vmax, vmax * 3.6, t15, trim_peak, trim_top, boat.prop_in_water])
	TestHarness.check(vmax >= 15.0 and vmax <= 22.0, "speedboat top speed 15-22 m/s (%.1f)" % vmax)
	TestHarness.check(trim_peak > 2.0 and trim_peak < 14.0, "bow rises when getting on the plane (%.1f deg)" % trim_peak)
	TestHarness.check(trim_top < trim_peak, "trim settles once planing (%.1f < %.1f deg)" % [trim_top, trim_peak])
	TestHarness.check(wake_seen or TestHarness.is_headless(), "wake trails attached while running")

	# --- turns both ways at speed
	var r := await _turn(boat, "move_right", 4.0)
	var l := await _turn(boat, "move_left", 4.0)
	Input.action_release("move_forward")
	_rows.append("turns: right %.1f deg (bank %.1f), left %.1f deg (bank %.1f), speed after %.1f m/s" % [r[0], r[1], l[0], l[1], boat.get_forward_speed()])
	TestHarness.check(r[0] < -45.0, "turns right (%.1f deg in 4 s)" % r[0])
	TestHarness.check(l[0] > 45.0, "turns left (%.1f deg in 4 s)" % l[0])
	TestHarness.check(r[1] > 1.0 and l[1] < -1.0, "banks into the turns (%.1f / %.1f deg)" % [r[1], l[1]])
	TestHarness.check(_min_up > 0.85, "stable in turns (min up.y %.3f)" % _min_up)

	# --- coast to a stop, no input, at least 30 s upright
	_min_up = 1.0
	t = 0.0
	var t_stop := -1.0
	while t < 45.0:
		await get_tree().physics_frame
		t += DT
		_track_up(boat)
		if t_stop < 0.0 and boat.linear_velocity.length() < 0.5:
			t_stop = t
		if t_stop > 0.0 and t > 30.0:
			break
	var dy1 := boat.global_position.y - boat.get_surface_height()
	_rows.append("coast: stopped (<0.5 m/s) after %.1f s, min up.y %.3f over %.0f s, waterline offset %.3f" % [t_stop, _min_up, t, dy1])
	TestHarness.check(t_stop > 0.0, "coasts to a stop (%.1f s)" % t_stop)
	TestHarness.check(t >= 30.0 and _min_up > 0.95, "upright for 30 s without input (min up.y %.3f)" % _min_up)
	TestHarness.check(absf(dy1) < 0.12, "back at the waterline at rest (%.3f)" % dy1)

	# --- exit onto the deck, then board again from the water
	pl.call("exit_vehicle")
	await TestHarness.wait_seconds(2.0)
	var pp: Vector3 = (pl as Node3D).global_position
	var local := boat.global_transform.affine_inverse() * pp
	_rows.append("exit: player state %s at boat-local %s (boat health %.0f destroyed %s)" % [str(pl.get("state_id")), str(local), boat.health, boat.destroyed])
	TestHarness.check(pl.get("current_vehicle") == null, "player left the helm")
	TestHarness.check(local.y > 0.2 and absf(local.x) < 1.3 and absf(local.z) < 4.0, "player stands on the deck (boat-local %s)" % str(local))
	var side := boat.global_transform * Vector3(-2.3, 0.0, 0.5)
	side.y = boat.get_surface_height() - 1.42
	_rows.append("teleport player at t=%d to %s (boat at %s)" % [Engine.get_physics_frames(), str(side), str(boat.global_position)])
	pl.call("teleport", side, 0.0)
	await TestHarness.wait_seconds(2.0)
	var swim := bool(pl.get("is_swimming"))
	TestHarness.check(swim, "player swims beside the boat (state %s, underwater %s)" % [str(pl.get("state_id")), str(pl.get("is_underwater"))])
	var found: Variant = pl.call("find_enterable_vehicle") if pl.has_method("find_enterable_vehicle") else null
	_rows.append("swim boarding: player at boat-local %s, enterable=%s, door=%s" % [str(boat.global_transform.affine_inverse() * (pl as Node3D).global_position), str(found == boat), str(boat.get_exit_transform(0).origin)])
	Input.action_press("enter_vehicle")
	await TestHarness.wait_physics_frames(2)
	Input.action_release("enter_vehicle")
	await TestHarness.wait_seconds(2.0)
	TestHarness.check(pl.get("current_vehicle") == boat, "boarded from the water (state %s)" % str(pl.get("state_id")))
	if pl.get("current_vehicle") != boat:
		pl.call("enter_vehicle", boat, 0, true)
		await TestHarness.wait_physics_frames(5)

	# --- run aground on the beach, then reverse off
	await _aground(boat)
	# leave the boat before quitting (quitting while seated leaks the player node - player module)
	pl.call("exit_vehicle")
	await TestHarness.wait_seconds(1.0)

	for row: String in _rows:
		print("BKB_TABLE: ", row)
	TestHarness.finish()


## AI-driven run of one moored jetski and one dinghy (set_inputs): speed, turning, stability.
func _small_craft(moorings: Node) -> void:
	var crafts: Array[Boat] = []
	var slips: Array = moorings.get("slips")
	for i in slips.size():
		var v := moorings.call("get_slip_vehicle", i) as Boat
		if v == null or i == 0:
			continue
		if (v.spec_id == "jetski" or v.spec_id == "dinghy") and not crafts.any(func(c: Boat) -> bool: return c.spec_id == v.spec_id):
			crafts.append(v)
	var vmax: Array[float] = []
	var yaw: Array[float] = []
	var prev: Array[float] = []
	var min_up: Array[float] = []
	for c: Boat in crafts:
		c.set_inputs(1.0, 0.0, 0.0)
		vmax.append(0.0)
		yaw.append(0.0)
		prev.append(_yaw(c))
		min_up.append(1.0)
	var t := 0.0
	while t < 13.0:
		await get_tree().physics_frame
		t += DT
		for k in crafts.size():
			var c := crafts[k]
			if t > 10.0 and absf(c.in_steer) < 0.5:
				c.set_inputs(1.0, 0.7, 0.0)
			vmax[k] = maxf(vmax[k], c.get_forward_speed())
			var y := _yaw(c)
			if t > 10.0:
				yaw[k] += angle_difference(prev[k], y)
			prev[k] = y
			min_up[k] = minf(min_up[k], c.global_transform.basis.y.y)
	for k in crafts.size():
		var c := crafts[k]
		c.release_inputs()
		_rows.append("%s (AI): top %.1f m/s, right turn %.0f deg in 3 s, min up.y %.3f, moored=%s" % [c.spec_id, vmax[k], rad_to_deg(yaw[k]), min_up[k], c.moored])
		var lo := 15.0 if c.spec_id == "jetski" else 6.0
		var hi := 24.0 if c.spec_id == "jetski" else 11.0
		TestHarness.check(vmax[k] >= lo and vmax[k] <= hi, "%s top speed %.1f m/s (%.0f-%.0f)" % [c.spec_id, vmax[k], lo, hi])
		TestHarness.check(rad_to_deg(yaw[k]) < -30.0, "%s turns right under AI steering (%.0f deg)" % [c.spec_id, rad_to_deg(yaw[k])])
		TestHarness.check(min_up[k] > 0.85, "%s stays upright (min up.y %.3f)" % [c.spec_id, min_up[k]])
	TestHarness.check(crafts.size() == 2, "jetski and dinghy driven (%d)" % crafts.size())


func _pier_boarding(pl: Node, boat: Boat) -> void:
	# find the pier face beside the boat (ray from the hull centre sideways at deck height)
	var space := boat.get_world_3d().direct_space_state
	var c := boat.global_position
	var pier := Vector3.INF
	for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, 0.95, c.z), Vector3(c.x, 0.95, c.z) + dir * 6.0, Layers.WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			pier = (hit["position"] as Vector3) + dir * 0.7
			pier.y = 1.2
			break
	if not TestHarness.check(pier != Vector3.INF, "pier beside the moored boat"):
		return
	var gap := absf(pier.x - c.x) - 0.7 - boat.body_aabb.size.x * 0.5
	pl.call("teleport", pier, 0.0)
	await TestHarness.wait_seconds(1.5)
	var on_pier: Vector3 = (pl as Node3D).global_position
	Input.action_press("enter_vehicle")
	await TestHarness.wait_physics_frames(2)
	Input.action_release("enter_vehicle")
	await TestHarness.wait_seconds(2.5)
	_rows.append("pier boarding: player on the pier at %s (hull-pier gap %.2f m), state %s" % [str(on_pier), gap, str(pl.get("state_id"))])
	TestHarness.check(gap > 0.1 and gap < 1.0, "moored alongside the pier (gap %.2f m)" % gap)
	TestHarness.check(pl.get("current_vehicle") == boat, "boarded from the pier (state %s)" % str(pl.get("state_id")))
	if pl.get("current_vehicle") != boat:
		return
	pl.call("exit_vehicle")
	await TestHarness.wait_seconds(2.0)
	var p: Vector3 = (pl as Node3D).global_position
	_rows.append("pier exit: player at %s (pier deck y 1.15)" % str(p))
	TestHarness.check(pl.get("current_vehicle") == null and absf(p.y - 1.15) < 0.3 and absf(p.x - c.x) > boat.body_aabb.size.x * 0.5, "stepped off onto the pier (%s)" % str(p))
	pl.call("enter_vehicle", boat, 0, true)
	await TestHarness.wait_physics_frames(5)


func _turn(boat: Boat, action: String, seconds: float) -> Array:
	var prev := _yaw(boat)
	var acc := 0.0
	var bank := 0.0
	var t := 0.0
	Input.action_press(action)
	while t < seconds:
		await get_tree().physics_frame
		t += DT
		var y := _yaw(boat)
		acc += angle_difference(prev, y)
		prev = y
		if absf(boat.bank_deg) > absf(bank):
			bank = boat.bank_deg
		_track_up(boat)
	Input.action_release(action)
	return [rad_to_deg(acc), bank]


func _aground(boat: Boat) -> void:
	var x := 100.0
	var shore_z := INF
	var z := 420.0
	while z > 150.0:
		if Game.ground_height(x, z) > -0.2:
			shore_z = z
			break
		z -= 1.0
	if not TestHarness.check(shore_z < INF, "found the beach shoreline at x %.0f" % x):
		return
	var start := Vector3(x, 0.0, shore_z + 170.0)
	start.y = boat.get_surface_height()
	boat.teleport(Transform3D(Basis.IDENTITY, Vector3(start.x, Game.WATER_LEVEL, start.z)))
	await TestHarness.wait_seconds(2.0)
	var h0 := boat.health
	Input.action_press("move_forward")
	var t := 0.0
	var vmax := 0.0
	var stopped_t := 0.0
	while t < 20.0:
		await get_tree().physics_frame
		t += DT
		var sp := boat.linear_velocity.length()
		vmax = maxf(vmax, sp)
		if t > 4.0 and sp < 1.0:
			stopped_t += DT
			if stopped_t > 1.5:
				break
		else:
			stopped_t = 0.0
	Input.action_release("move_forward")
	await TestHarness.wait_seconds(1.5)
	var beached_z := boat.global_position.z
	var up := boat.global_transform.basis.y.y
	_rows.append("aground: shore z %.1f, ran in at %.1f m/s, stopped at z %.1f (ground %.2f), up.y %.3f, health %.0f -> %.0f, aground=%s prop wet=%s" % [shore_z, vmax, beached_z, Game.ground_height(boat.global_position.x, beached_z), up, h0, boat.health, boat.aground, boat.prop_in_water])
	TestHarness.check(vmax > 12.0, "hit the beach at speed (%.1f m/s)" % vmax)
	TestHarness.check(beached_z < shore_z + 12.0, "ran up onto the beach (z %.1f, shore %.1f)" % [beached_z, shore_z])
	TestHarness.check(not boat.destroyed and up > 0.7, "survives running aground (up.y %.2f, health %.0f)" % [up, boat.health])
	# reverse off
	Input.action_press("move_back")
	t = 0.0
	while t < 30.0:
		await get_tree().physics_frame
		t += DT
		if boat.global_position.z > beached_z + 8.0 and boat.submerged > 0.6:
			break
	Input.action_release("move_back")
	_rows.append("reverse off: moved %.1f m back in %.1f s, submerged %.2f" % [boat.global_position.z - beached_z, t, boat.submerged])
	TestHarness.check(boat.global_position.z > beached_z + 8.0 and boat.submerged > 0.6, "reverses off the beach into the water (%.1f m, %.1f s)" % [boat.global_position.z - beached_z, t])


func _on_damaged(v: Node3D, amount: float, info: Dictionary, boat: Node3D) -> void:
	if v != boat:
		return
	var inst: Variant = info.get("instigator", null)
	var who := str(inst.name) if inst is Node and is_instance_valid(inst) else "-"
	_rows.append("damage: %.1f %s by %s at %s (health %.0f)" % [amount, str(info.get("type", "")), who, str(info.get("position", Vector3.ZERO)), float(v.get("health"))])


func _on_collision(v: Node3D, other: Node, impulse: float, pos: Vector3, boat: Node3D) -> void:
	if v != boat or impulse < 2000.0:
		return
	var nm := "%s (%s)" % [str(other.name), other.get_class()] if other != null and is_instance_valid(other) else "null"
	_rows.append("collision: impulse %.0f with %s at %s, t=%d" % [impulse, nm, str(pos), Engine.get_physics_frames()])


func _track_up(v: Node3D) -> void:
	_min_up = minf(_min_up, v.global_transform.basis.y.y)


func _yaw(v: Node3D) -> float:
	var f := -v.global_transform.basis.z
	return atan2(-f.x, -f.z)
