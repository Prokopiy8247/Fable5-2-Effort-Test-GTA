extends Node
## POLICE helicopter screenshots (windowed, short). Night, clear sky, the player on the waterfront street
## in front of the general store, ground units off (only the helicopter):
##   qa/screenshots/pol_heli_night.png   3 stars: the helicopter circles over the street, its searchlight
##                                       cone on the player (PURSUIT)
##   qa/screenshots/pol_heli_search.png  the player slipped into the store: SEARCH, the beam sweeps the
##                                       street in front of it
## Headless runs execute the same scenario and only check the setup.
##   tools\godot.ps1 -Mode window -Frames 660 -TimeoutSec 160 -UserArgs '--test=pol_shots3','--test-timeout=120','--seed=4','--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'

var T: Node
var pol: Node
var cam: Camera3D = null
var _mode: String = ""
var _heli_v: Node3D = null
var _open: Vector3 = Vector3.INF
var _inside: Vector3 = Vector3.INF
var _front: Vector3 = Vector3.FORWARD


func _ready() -> void:
	T = TestHarness
	await T.wait_seconds(0.5)
	pol = Game.get_system("police")
	var p := Game.player
	if T.check(pol != null and p != null and is_instance_valid(p), "police + player present"):
		await _run(p)
	_mode = ""
	Game.invulnerable = false
	Wanted.clear("cheat")
	if pol != null:
		pol.set("ground_dispatch", true)
	T.finish()


func _run(p: Node3D) -> void:
	Game.invulnerable = true
	WorldClock.set_hour(23.2)
	if Weather.has_method("snap_weather"):
		Weather.snap_weather("clear")
	if not T.check(_find_spots(), "street spot in front of the store %s" % str(_open.round())):
		return
	var side := Vector3(-_front.z, 0.0, _front.x)          # along the street
	p.call("teleport", _open, atan2(side.x, side.z))
	pol.set("ground_dispatch", false)
	Wanted.set_level(3)
	await T.wait_seconds(0.2)
	pol.call("clear_units")
	# the helicopter is already on station above the street
	var hp := _open + side * 40.0 + Vector3.UP * 56.0
	var to := _open - hp
	_heli_v = pol.call("spawn_unit_at", "heli", Transform3D(Basis(Vector3.UP, atan2(-to.x, -to.z)), hp))
	if not T.check(_heli_v != null, "police helicopter placed over the street"):
		return
	cam = Camera3D.new()
	cam.name = "PolHeliShotCam"
	cam.fov = 64.0
	cam.far = 2500.0
	Game.get_entities_root().add_child(cam)
	await T.wait_seconds(3.5)
	_mode = "pursuit"
	cam.make_current()
	await T.wait_seconds(0.4)
	var h := _info()
	T.log_line("night shot: state=%d %s" % [Wanted.state, str(h)])
	T.check(bool(h.get("searchlight", false)) and Wanted.state == Wanted.State.PURSUIT, "PURSUIT with the searchlight on")
	T.check(bool(h.get("in_beam", false)), "the player stands inside the lit cone")
	await T.shot("pol_heli_night")

	# --- the player slips into the store: SEARCH, the beam sweeps the street
	_mode = ""
	p.call("teleport", _inside, 0.0)
	var t := 0.0
	while t < 8.0 and Wanted.state != Wanted.State.SEARCH:
		await T.wait_seconds(0.25)
		t += 0.25
	T.check(Wanted.state == Wanted.State.SEARCH, "hidden in the store -> SEARCH (%.1f s)" % t)
	_mode = "search"
	await T.wait_seconds(1.6)
	T.log_line("search shot: %s" % str(_info()))
	await T.shot("pol_heli_search")


func _process(_delta: float) -> void:
	if cam == null or _mode == "" or _heli_v == null or not is_instance_valid(_heli_v):
		return
	var hp := _heli_v.global_position
	var p := Game.player
	if _mode == "pursuit" and p != null:
		# on the far side of the player from the helicopter: player, beam and aircraft in one frame
		var pp := p.global_position
		var away := pp - hp
		away.y = 0.0
		away = away.normalized() if away.length() > 1.0 else _front
		var c := pp + away * 34.0 + Vector3.UP * 4.0
		cam.global_position = c
		cam.look_at(pp.lerp(hp, 0.42) + Vector3.UP * 1.0, Vector3.UP)
	elif _mode == "search":
		var lp: Vector3 = _info().get("light_point", Vector3.INF)
		if lp == Vector3.INF:
			lp = _open
		var away2 := lp - hp
		away2.y = 0.0
		away2 = away2.normalized() if away2.length() > 1.0 else _front
		cam.global_position = lp + away2 * 36.0 + Vector3.UP * 5.0
		cam.look_at(lp.lerp(hp, 0.45), Vector3.UP)


func _info() -> Dictionary:
	var h: Variant = pol.get("heli") if pol != null else null
	if h == null or not (h is RefCounted):
		return {}
	var d: Dictionary = (h as RefCounted).call("get_debug_info")
	d["light_point"] = (h as RefCounted).get("light_point")
	return d


func _find_spots() -> bool:
	var city := Game.get_system("city")
	if city == null or not city.has_method("has_landmark"):
		return false
	for lm: String in ["general_store", "gun_shop", "clothing_store"]:
		if not bool(city.call("has_landmark", lm)) or not bool(city.call("has_landmark_marker", lm, "Use_Counter")):
			continue
		var bx: Transform3D = city.call("get_landmark_transform", lm)
		_front = -bx.basis.z
		_front.y = 0.0
		_front = _front.normalized()
		var q := bx.origin + _front * 14.0
		if Game.world != null and Game.world.has_method("get_height"):
			q.y = float(Game.world.call("get_height", q.x, q.z))
		_open = q + Vector3.UP * 0.1
		_inside = (city.call("get_landmark_marker", lm, "Use_Counter") as Transform3D).origin + Vector3.UP * 0.1
		return true
	return false
