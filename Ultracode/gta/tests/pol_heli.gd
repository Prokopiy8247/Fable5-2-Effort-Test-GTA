extends Node
## POLICE helicopter test (headless): real world, vehicles, peds, police, the real player.
## Ground units are switched off (`police.ground_dispatch = false`) so every sighting comes from the
## helicopter crew.
##   1. 3 stars, the player stands in the open in front of the general store: the helicopter (spawned
##      out of view) arrives within 40 s and comes within 120 m
##   2. it orbits within 120 m of the player and its sightings keep PURSUIT going (no SEARCH while he
##      stands in the open); its searchlight follows him
##   3. 4 stars: the marksman in the side bay fires (the pilot turns that side to the suspect)
##   4. the player walks into the store (under the roof): the crew loses him -> SEARCH starts while the
##      helicopter sweeps the search area overhead (no sighting through the roof)
##   5. he steps back out into the open: the helicopter finds him again -> PURSUIT
##   6. shot down: apply_damage (the player's bullets) until destroyed -> mayday, explosion,
##      police_vehicle_destroyed known, the wreck comes down, a replacement only after the cool-down
##   7. a new helicopter, then the level clears: it flies away and is despawned out of view
##   tools\godot.ps1 -Mode headless -Frames 15000 -TimeoutSec 480 -UserArgs '--test=pol_heli','--test-timeout=460','--seed=11','--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'

var T: Node
var pol: Node
var _known: Array[String] = []
var _police_shots: int = 0
var _open: Vector3 = Vector3.INF
var _inside: Vector3 = Vector3.INF


func _ready() -> void:
	T = TestHarness
	Wanted.crime_became_known.connect(func(id: String, _pos: Vector3, src: String) -> void:
		_known.append(id)
		T.log_line("CRIME known %s (%s)" % [id, src]))
	EventBus.weapon_fired.connect(func(_w: String, shooter: Node, _o: Vector3, _d: Vector3) -> void:
		if shooter != null and is_instance_valid(shooter) and shooter.is_in_group("police"):
			_police_shots += 1)
	await T.wait_seconds(1.0)
	await _run()
	Game.invulnerable = false
	Wanted.clear("cheat")
	if pol != null:
		pol.set("ground_dispatch", true)
	T.finish()


func _run() -> void:
	pol = Game.get_system("police")
	var p := Game.player
	if not T.check(pol != null and p != null and is_instance_valid(p), "police system + player present"):
		return
	Game.invulnerable = true
	WorldClock.set_hour(13.0)
	if not T.check(_find_spots(), "open spot in front of the store %s, inside %s" % [str(_open.round()), str(_inside.round())]):
		return
	pol.set("ground_dispatch", false)
	p.call("teleport", _open, 0.0)
	await T.wait_seconds(1.0)

	# --- 1. arrival
	Wanted.set_level(3)
	await T.wait_seconds(0.2)
	pol.call("clear_units")              # ambient patrols / beat officers: only the helicopter may see him
	var t := 0.0
	var arrived := -1.0
	var spawned := -1.0
	var first_pos := Vector3.INF
	while t < 45.0:
		await T.wait_seconds(0.5)
		t += 0.5
		var h := _heli_info()
		if h.is_empty():
			continue
		if spawned < 0.0:
			spawned = t
			first_pos = h.get("pos", Vector3.INF)
			T.log_line("heli spawned t=%.1f at %s (%.0f m from the player, view? %s)" % [t, str(first_pos.round()),
					float(h.get("dist", 0.0)), str(_on_screen(first_pos))])
		if int(t * 2.0) % 4 == 0:
			T.log_line("t=%.1f %s" % [t, _fmt(h)])
		if float(h.get("dist", 999.0)) < 120.0:
			arrived = t
			break
	T.check(spawned >= 0.0, "a police helicopter was dispatched at 3 stars (after %.1f s)" % spawned)
	T.check(first_pos != Vector3.INF and _flat(first_pos, _open) > 200.0 and first_pos.y > 60.0,
			"spawned far away at altitude (%.0f m, y %.0f)" % [_flat(first_pos, _open), first_pos.y])
	T.check(arrived >= 0.0 and arrived <= 40.0, "the helicopter arrived within 40 s (%.1f s)" % arrived)
	var hv := _heli_vehicle()
	if not T.check(hv != null, "helicopter vehicle found"):
		return
	var pilot: Variant = hv.get("driver")
	T.check(pilot is Node3D and (pilot as Node).is_in_group("police") and str(hv.get("spec_id")) == "heli_police"
			and hv.has_meta("ai_controller"), "heli_police with a seated police pilot (ai_controller set)")
	T.check(int(pol.call("get_debug_info")["officers_alive"]) == 0, "the air crew does not use the ground officer budget")

	# --- 2. orbit + sightings keep PURSUIT
	t = 0.0
	while t < 20.0 and Wanted.state != Wanted.State.PURSUIT:
		await T.wait_seconds(0.25)
		t += 0.25
	T.check(Wanted.state == Wanted.State.PURSUIT, "the crew spotted the player in the open -> PURSUIT (%.1f s)" % t)
	var s0 := int(_heli_info().get("stats", {}).get("sightings", 0))
	var max_d := 0.0
	var pursuit_n := 0
	var samples := 0
	var lit_n := 0
	var ang0 := INF
	var swept := 0.0
	var prev_ang := INF
	t = 0.0
	while t < 22.0:
		await T.wait_seconds(0.5)
		t += 0.5
		var h := _heli_info()
		samples += 1
		max_d = maxf(max_d, float(h.get("dist", 999.0)))
		if Wanted.state == Wanted.State.PURSUIT:
			pursuit_n += 1
		if bool(h.get("searchlight", false)):
			lit_n += 1
		var hp: Vector3 = h.get("pos", _open)
		var a := atan2(hp.x - p.global_position.x, hp.z - p.global_position.z)
		if prev_ang != INF:
			swept += absf(wrapf(a - prev_ang, -PI, PI))
		prev_ang = a
		if int(t * 2.0) % 6 == 0:
			T.log_line("orbit t=%.1f state=%d %s" % [t, Wanted.state, _fmt(h)])
	var s1 := int(_heli_info().get("stats", {}).get("sightings", 0))
	T.check(max_d < 120.0, "stays within 120 m of the player while orbiting (max %.0f m)" % max_d)
	T.check(swept > PI * 0.5, "it circles the player (%.0f deg swept in 22 s)" % rad_to_deg(swept))
	T.check(pursuit_n == samples, "PURSUIT held by the helicopter's sightings (%d / %d samples)" % [pursuit_n, samples])
	T.check(s1 - s0 >= 20, "crew sightings reported (%d in 22 s)" % (s1 - s0))
	T.check(lit_n == samples, "searchlight on during the pursuit (%d / %d)" % [lit_n, samples])

	# --- 3. 4 stars: marksman
	Wanted.set_level(4)
	var shots0 := int(_heli_info().get("stats", {}).get("shots", 0))
	var ps0 := _police_shots
	t = 0.0
	while t < 18.0 and int(_heli_info().get("stats", {}).get("shots", 0)) - shots0 < 3:
		await T.wait_seconds(0.5)
		t += 0.5
	var shots := int(_heli_info().get("stats", {}).get("shots", 0)) - shots0
	T.log_line("marksman: %d shots, %d police weapon_fired, %s" % [shots, _police_shots - ps0, _fmt(_heli_info())])
	T.check(shots >= 3, "4 stars: the marksman fires from the side bay (%d shots in %.1f s)" % [shots, t])

	# --- 4. hide inside the store
	p.call("teleport", _inside, 0.0)
	var s_hide := int(_heli_info().get("stats", {}).get("sightings", 0))
	t = 0.0
	while t < 14.0 and Wanted.state != Wanted.State.SEARCH:
		await T.wait_seconds(0.25)
		t += 0.25
	T.check(Wanted.state == Wanted.State.SEARCH, "inside the store (under the roof) -> SEARCH after %.1f s" % t)
	var over := INF
	var search_ok := 0
	samples = 0
	t = 0.0
	var s_mid := int(_heli_info().get("stats", {}).get("sightings", 0))
	while t < 16.0:
		await T.wait_seconds(0.5)
		t += 0.5
		samples += 1
		var h := _heli_info()
		over = minf(over, float(h.get("dist", 999.0)))
		if Wanted.state == Wanted.State.SEARCH and str(h.get("mode", "")) == "search":
			search_ok += 1
		if int(t * 2.0) % 8 == 0:
			T.log_line("search t=%.1f progress=%.2f r=%.0f %s" % [t, Wanted.escape_progress, Wanted.search_radius, _fmt(h)])
	var s_end := int(_heli_info().get("stats", {}).get("sightings", 0))
	T.check(search_ok == samples, "stays in SEARCH, the helicopter sweeps the area (%d / %d)" % [search_ok, samples])
	T.check(over < 60.0, "it passed over / near the hidden player (closest %.0f m)" % over)
	T.check(s_end == s_mid, "no sighting through the roof (%d -> %d, %d before the search)" % [s_mid, s_end, s_hide])
	T.check(int(_heli_info().get("stats", {}).get("sweep_points", 0)) >= 2, "sweep waypoints flown (%d)" %
			int(_heli_info().get("stats", {}).get("sweep_points", 0)))

	# --- 5. step out -> found again
	p.call("teleport", _open, 0.0)
	t = 0.0
	while t < 30.0 and Wanted.state != Wanted.State.PURSUIT:
		await T.wait_seconds(0.25)
		t += 0.25
	T.check(Wanted.state == Wanted.State.PURSUIT, "back in the open: the helicopter finds him again (%.1f s, beam %s)" %
			[t, str(_heli_info().get("in_beam", false))])

	# --- 6. shot down
	hv = _heli_vehicle()
	if not T.check(hv != null, "helicopter still up for the shoot-down"):
		return
	var y_hit := hv.global_position.y
	var mayday := false
	var hits := 0
	t = 0.0
	while t < 25.0 and is_instance_valid(hv) and not bool(hv.get("destroyed")):
		var dir := (hv.global_position - p.global_position).normalized()
		hv.call("apply_damage", Dmg.make(120.0, "bullet", p, hv.global_position + Vector3.UP * 0.5, dir))
		hits += 1
		await T.wait_seconds(0.1)
		t += 0.1
		var h := _heli_info()
		if str(h.get("mode", "")) == "mayday":
			mayday = true
	var destroyed := is_instance_valid(hv) and bool(hv.get("destroyed"))
	T.check(destroyed, "shot down: destroyed after %d hits / %.1f s" % [hits, t])
	T.check(mayday, "it went into a mayday (spinning descent) before blowing up")
	await T.wait_seconds(0.5)
	T.check(_known.has("police_vehicle_destroyed"), "police_vehicle_destroyed reported and known (%s)" % str(_known))
	var info: Dictionary = pol.call("get_debug_info")
	T.check((info.get("heli", {}) as Dictionary).is_empty() and int(info["stats"]["helis_down"]) == 1,
			"the unit is gone (helis_down %d)" % int(info["stats"]["helis_down"]))
	T.check(float(info.get("heli_cd", 0.0)) > 30.0, "replacement only after a cool-down (%.0f s)" % float(info.get("heli_cd", 0.0)))
	t = 0.0
	while t < 12.0 and is_instance_valid(hv) and hv.global_position.y > _ground(hv.global_position) + 4.0:
		await T.wait_seconds(0.5)
		t += 0.5
	if is_instance_valid(hv):
		T.check(hv.global_position.y < y_hit - 15.0, "the wreck came down (y %.0f -> %.0f)" % [y_hit, hv.global_position.y])

	# --- 7. a new helicopter, then the level clears
	var nv: Node3D = pol.call("spawn_unit", "heli", p.global_position)
	T.check(nv != null, "spawn_unit('heli') places a new helicopter")
	t = 0.0
	while t < 40.0 and float(_heli_info().get("dist", 999.0)) > 140.0:
		await T.wait_seconds(0.5)
		t += 0.5
	T.log_line("second heli near after %.1f s: %s" % [t, _fmt(_heli_info())])
	Wanted.clear("cheat")
	var left := false
	var leave_seen := false
	t = 0.0
	while t < 45.0:
		await T.wait_seconds(0.5)
		t += 0.5
		var h := _heli_info()
		if h.is_empty():
			left = true
			break
		if str(h.get("mode", "")) == "leave":
			leave_seen = true
		if int(t * 2.0) % 10 == 0:
			T.log_line("leaving t=%.1f %s" % [t, _fmt(h)])
	T.check(leave_seen, "level cleared: the helicopter flies off (mode leave)")
	T.check(left and (nv == null or not is_instance_valid(nv)), "and is despawned out of view (%.1f s)" % t)
	T.log_line("POLICE_STATS %s" % str(pol.call("get_debug_info")))


# --- helpers -------------------------------------------------------------------------------------

## The open spot in front of the general store (sky clear) and a spot inside it (Use_Counter).
func _find_spots() -> bool:
	var city := Game.get_system("city")
	if city == null or not city.has_method("has_landmark"):
		return false
	for lm: String in ["general_store", "gun_shop", "clothing_store"]:
		if not bool(city.call("has_landmark", lm)):
			continue
		if not bool(city.call("has_landmark_marker", lm, "Use_Counter")):
			continue
		var inside: Vector3 = (city.call("get_landmark_marker", lm, "Use_Counter") as Transform3D).origin
		var bx: Transform3D = city.call("get_landmark_transform", lm)
		var front := -bx.basis.z
		front.y = 0.0
		front = front.normalized()
		for dist: float in [14.0, 18.0, 22.0, 26.0, 30.0, 35.0]:
			var q := bx.origin + front * dist
			q.y = _ground(q)
			if _sky_open(q):
				_open = q + Vector3.UP * 0.1
				_inside = inside + Vector3.UP * 0.1
				T.log_line("landmark %s at %s, open spot %.0f m in front" % [lm, str(bx.origin.round()), dist])
				return true
	return false


func _sky_open(q: Vector3) -> bool:
	var space := get_viewport().get_world_3d().direct_space_state
	var dirs: Array[Vector3] = [Vector3.UP]
	for k in 8:
		var a := float(k) * TAU / 8.0
		dirs.append(Vector3(sin(a) * 0.8, 1.0, cos(a) * 0.8).normalized())   # ~51 deg elevation
	for d: Vector3 in dirs:
		var rq := PhysicsRayQueryParameters3D.create(q + Vector3.UP * 1.4, q + Vector3.UP * 1.4 + d * 90.0, Layers.WORLD)
		if not space.intersect_ray(rq).is_empty():
			return false
	return true


func _heli_info() -> Dictionary:
	if pol == null:
		return {}
	var info: Dictionary = pol.call("get_debug_info")
	return info.get("heli", {})


func _heli_vehicle() -> Node3D:
	var h: Variant = pol.get("heli")
	if h == null or not (h is RefCounted):
		return null
	var v: Variant = (h as RefCounted).get("vehicle")
	return v as Node3D if v is Node3D and is_instance_valid(v) else null


func _fmt(h: Dictionary) -> String:
	if h.is_empty():
		return "(no heli)"
	return "mode=%s/%s dist=%.0f agl=%.0f sees=%s beam=%s ap=%s hp=%.0f sightings=%d" % [h.get("mode", ""), h.get("sub", ""),
			float(h.get("dist", 0.0)), float(h.get("agl", 0.0)), str(h.get("sees", false)), str(h.get("in_beam", false)),
			str(h.get("autopilot", "")), float(h.get("health", 0.0)), int(h.get("stats", {}).get("sightings", 0))]


func _on_screen(pos: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.is_position_in_frustum(pos) and cam.global_position.distance_to(pos) < 260.0


func _ground(p: Vector3) -> float:
	if Game.world != null and Game.world.has_method("get_height"):
		return float(Game.world.call("get_height", p.x, p.z))
	return p.y


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
