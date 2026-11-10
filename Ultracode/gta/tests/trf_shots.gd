extends Node
## TRAFFIC screenshots (windowed, short, real time ~18 s). A busy signalised downtown junction
## (Meridian Avenue x Foundry Street) seeded with cars on every approach lane, by day and by night.
##
##   trf_junction_day      elevated corner view: cars in their lanes, right-hand traffic, queues at red
##   trf_queue_day         street level at the stop line: queued cars, drivers through the windscreen
##   trf_driver_close      the seated driver of a waiting car (humanoid, seated_car pose)
##   trf_junction_night    the same corner view at night: headlights, tail lights, street lamps
##   trf_street_night      street level at night looking down an approach with oncoming headlights
##
## Run: tools\godot.ps1 -Mode window -Frames 700 -TimeoutSec 120 -UserArgs '--test=trf_shots','--no_player',
##      '--disable=police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups,interactions'
## Then LOOK at qa/screenshots/trf_*.png.

var sys: TrafficSystem = null
var L: TrafficLanes = null
var cam: Camera3D = null
var node_id: int = -1
var center: Vector3 = Vector3.ZERO


func _ready() -> void:
	await _run()


func _run() -> void:
	sys = Game.get_system("traffic") as TrafficSystem
	if sys == null or sys.lanes == null:
		TestHarness.check(false, "traffic system with lanes")
		TestHarness.finish(false, "no traffic")
		return
	L = sys.lanes
	cam = Camera3D.new()
	cam.name = "TrafficShotCam"
	cam.far = 1500.0
	cam.fov = 55.0
	Game.main.add_child(cam)
	cam.current = true
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(13.0)
	if "paused" in WorldClock:
		WorldClock.paused = true
	if Weather.has_method("set_weather"):
		Weather.set_weather("clear", 0.0)
	# the junction nearest to (0, -105)
	var best := INF
	for k in L.node_count:
		if L.node_legs[k] < 4 or L.node_signal[k] == 0:
			continue
		var dd := Vector2(L.node_pos[k].x - 0.0, L.node_pos[k].z + 105.0).length()
		if dd < best:
			best = dd
			node_id = k
	center = L.node_pos[node_id]
	TestHarness.log_line("junction %d at %s" % [node_id, str(center)])
	sys.set_focus_override(center)
	sys.set_density(0.0)            # no ambient fill: the cap goes to the junction approaches
	sys.set_enabled(false)
	sys.set_enabled(true)
	_seed_junction()
	sys.set_density(0.5)
	_corner_view()
	await TestHarness.wait_seconds(3.8)
	TestHarness.log_line("day: %s" % str(sys.get_debug_info()))
	_log_cars()
	await TestHarness.shot("trf_junction_day")
	var w: TrafficDriver = null
	for i in 12:
		w = _waiting_car()
		if w != null:
			break
		await TestHarness.wait_seconds(0.25)
	if w != null:
		_queue_view(w)
		await TestHarness.wait_seconds(0.4)
		await TestHarness.shot("trf_queue_day")
		_driver_view(w)
		await TestHarness.wait_seconds(0.4)
		await TestHarness.shot("trf_driver_close")
	else:
		TestHarness.log_line("no waiting car for the queue / driver shots")
	# ---------------------------------------------------------------- night
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(22.5)
	sys.set_density(0.0)
	_seed_junction()
	_corner_view()
	await TestHarness.wait_seconds(2.8)
	TestHarness.log_line("night: %s" % str(sys.get_debug_info()))
	await TestHarness.shot("trf_junction_night")
	_street_view()
	await TestHarness.wait_seconds(1.6)
	await TestHarness.shot("trf_street_night")
	var lit := 0
	for d: TrafficDriver in sys.get_drivers():
		if d.is_valid() and int(d.veh.get("headlight_mode")) > 0:
			lit += 1
	TestHarness.check(lit > 0, "traffic headlights on at night (%d cars)" % lit)
	TestHarness.check(int(sys.get_debug_info()["visible_drivers"]) > 0, "seated drivers are drawn near the camera")
	TestHarness.finish()


## Two cars on every approach lane of the junction (where there is room).
func _seed_junction() -> void:
	for lane in L.count:
		if L.end_node[lane] != node_id:
			continue
		for off_back: float in [26.0, 46.0]:
			var off := L.length[lane] - off_back
			if off < 4.0:
				continue
			var p := L.lane_point(lane, off)
			var busy := false
			for d: TrafficDriver in sys.get_drivers():
				if d.is_valid() and Vector2(d.body.global_position.x - p.x, d.body.global_position.z - p.z).length() < 9.0:
					busy = true
					break
			if not busy:
				sys.spawn_traffic_vehicle(lane, off)


## Above the middle of the longest leg, looking into the junction (never inside a building).
func _corner_view() -> void:
	var best_lane := -1
	var bl := 0.0
	for lane in L.count:
		if L.start_node[lane] == node_id and L.length[lane] > bl:
			bl = L.length[lane]
			best_lane = lane
	var dir := L.lane_start_dir(best_lane) if best_lane >= 0 else Vector3.BACK
	var right := Vector3(-dir.z, 0.0, dir.x)
	cam.fov = 58.0
	cam.global_position = center + dir * 30.0 - right * 1.5 + Vector3.UP * 13.0
	cam.look_at(center - dir * 4.0)


func _waiting_car() -> TrafficDriver:
	var best: TrafficDriver = null
	var bd := INF
	for d: TrafficDriver in sys.get_drivers():
		if not d.is_valid() or d.in_conn or L.end_node[d.lane] != node_id:
			continue
		if not d.visible_driver:
			continue
		var dl := L.length[d.lane] - d.s
		if absf(d.speed) < 0.5 and dl < bd:
			bd = dl
			best = d
	return best


func _queue_view(d: TrafficDriver) -> void:
	var xf := d.body.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	cam.fov = 50.0
	cam.global_position = xf.origin + fwd * 9.0 + right * 3.6 + Vector3.UP * 1.9
	cam.look_at(xf.origin - fwd * 6.0 + Vector3.UP * 0.9)


func _driver_view(d: TrafficDriver) -> void:
	var seat := d.dummy.global_position if d.dummy != null else d.body.global_position + Vector3.UP
	var xf := d.body.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var side := -1.0 if (xf.affine_inverse() * seat).x < 0.0 else 1.0
	# through the driver's side window (clearest view of the seated driver); when something stands in
	# that line of sight (traffic crossing in the next lane), from the front through the windscreen
	var head := seat + Vector3.UP * 0.35
	var side_pos := seat + right * side * 2.4 + fwd * 1.0 + Vector3.UP * 0.5
	var front_pos := seat + fwd * 3.4 + right * side * 1.5 + Vector3.UP * 0.45
	var q := PhysicsRayQueryParameters3D.create(side_pos, head, Layers.VEHICLE | Layers.WORLD | Layers.PROP | Layers.NPC)
	q.exclude = [d.body.get_rid()]
	var blocked := not get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty()
	cam.fov = 45.0 if not blocked else 42.0
	cam.global_position = front_pos if blocked else side_pos
	cam.look_at(head - Vector3.UP * 0.05)
	TestHarness.log_line("driver view from the %s" % ("front (side blocked)" if blocked else "side window"))


func _street_view() -> void:
	# stand at the kerb of the longest approach and look down it
	var best_lane := -1
	var bl := 0.0
	for lane in L.count:
		if L.end_node[lane] == node_id and L.length[lane] > bl:
			bl = L.length[lane]
			best_lane = lane
	if best_lane < 0:
		return
	# oncoming headlights: a few cars on this approach and the other direction of the street
	for back: float in [35.0, 62.0, 90.0]:
		if L.length[best_lane] - back > 4.0:
			sys.spawn_traffic_vehicle(best_lane, L.length[best_lane] - back)
	for o in L.opposite[best_lane]:
		for off: float in [12.0, 40.0]:
			if L.length[o] > off + 10.0:
				sys.spawn_traffic_vehicle(o, off)
	var end := L.lane_point(best_lane, L.length[best_lane])
	var dir := L.lane_end_dir(best_lane)
	var right := Vector3(-dir.z, 0.0, dir.x)
	cam.fov = 55.0
	cam.global_position = end + dir * 4.0 + right * 3.2 + Vector3.UP * 1.7
	cam.look_at(end - dir * 50.0 + Vector3.UP * 1.0)


func _log_cars() -> void:
	for d: TrafficDriver in sys.get_drivers():
		if not d.is_valid():
			continue
		var p := d.body.global_position
		if Vector2(p.x - center.x, p.z - center.z).length() > 70.0:
			continue
		var lane_p := d.point_ahead(L, 0.0)
		TestHarness.log_line("car %d %s lane %d (kind %d idx %d) off-path %.2f m speed %.1f block %d visual %s" % [
				d.uid, d.spec_id, d.lane, L.kind[d.lane], L.index[d.lane],
				Vector2(p.x - lane_p.x, p.z - lane_p.z).length(), d.speed, d.block, str(d.visible_driver)])
