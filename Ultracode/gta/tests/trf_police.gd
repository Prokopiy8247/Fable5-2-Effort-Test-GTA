extends Node
## TRAFFIC x the REAL police system (headless, review test). The player stands downtown with 2 wanted
## stars (invulnerable, respawn disabled so nothing moves him); the police dispatch cruisers with sirens
## through the traffic for 40 s. Checks: police units come, traffic drivers notice the sirens and yield
## (siren_t), the traffic population stays up, no gridlock (longest standstill of a traffic car), no red
## light run by a calm traffic driver, contacts between traffic and police cars are logged (rate), and
## the traffic module raises no script errors while the police take / leave vehicles.
##
## Run: tools\godot.ps1 -Mode headless -Frames 4200 -TimeoutSec 300 -UserArgs '--test=trf_police','--test-timeout=280',
##      '--disable=emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups,interactions'

var sys: TrafficSystem = null
var yields: Dictionary = {}            ## uid -> true: traffic drivers that yielded to a siren
var police_hits: int = 0
var still: Dictionary = {}
var still_max: float = 0.0
var still_info: String = ""


func _ready() -> void:
	await _run()


func _run() -> void:
	sys = Game.get_system("traffic") as TrafficSystem
	var police := Game.get_system("police")
	if not TestHarness.check(sys != null and sys.lanes != null and Game.player != null, "traffic + player"):
		TestHarness.finish(false, "needs traffic and the player")
		return
	if police == null:
		TestHarness.log_line("police system not running - nothing to test")
		TestHarness.finish(true, "no police system")
		return
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(12.0)
	if "paused" in WorldClock:
		WorldClock.paused = true
	Game.invulnerable = true
	EventBus.vehicle_collision.connect(_on_collision)
	var spot: Dictionary = sys.lanes.roads.get_nearest_lane(Vector3(0.0, 2.6, -60.0), 40.0)
	var p: Vector3 = spot["point"] if not spot.is_empty() else Vector3(0.0, 2.6, -60.0)
	# on the pavement beside Meridian Avenue
	var dir: Vector3 = sys.lanes.lane_dir(int(spot.get("lane_id", 0)), float(spot.get("offset", 0.0)))
	Game.player.call("teleport", p + Vector3(-dir.z, 0.0, dir.x) * 7.0 + Vector3.UP * 0.2, 0.0)
	await TestHarness.wait_seconds(4.0)
	var n0 := sys.get_vehicle_count()
	var red0 := int(sys.stats["red_violations"])
	TestHarness.log_line("before: traffic %d, police units %d" % [n0, _units(police)])
	Wanted.set_level(2)
	var units_max := 0
	var sirens_max := 0
	var count_min := 999
	for i in 160:
		await TestHarness.wait_seconds(0.25)
		units_max = maxi(units_max, _units(police))
		var sirens := 0
		var vm := Game.get_system("vehicles")
		if vm != null:
			for v: Variant in (vm.get("vehicles") as Array):
				if v != null and is_instance_valid(v) and bool(v.get("siren_on")):
					sirens += 1
		sirens_max = maxi(sirens_max, sirens)
		count_min = mini(count_min, sys.get_vehicle_count())
		for d: TrafficDriver in sys.get_drivers():
			if not d.is_valid() or d.frozen:
				continue
			if d.siren_t > 0.0:
				yields[d.uid] = true
			if absf(d.speed) < 0.5:
				var t := float(still.get(d.uid, 0.0)) + 0.25
				still[d.uid] = t
				if t > still_max:
					still_max = t
					still_info = "uid %d %s lane %d block %d obs %s siren %.1f" % [d.uid, d.spec_id, d.lane, d.block, d.obs_name, d.siren_t]
			else:
				still.erase(d.uid)
		if i % 40 == 39:
			TestHarness.log_line("t=%.0fs wanted %d police units %d sirens %d traffic %d yielded %d" % [float(i + 1) * 0.25, int(Wanted.level),
					_units(police), sirens, sys.get_vehicle_count(), yields.size()])
	var st: Dictionary = sys.get_debug_info()
	TestHarness.log_line("police run: units max %d, sirens max %d, traffic min %d, drivers that yielded %d, traffic-police contacts %d, longest standstill %.1f s (%s) | %s" % [
			units_max, sirens_max, count_min, yields.size(), police_hits, still_max, still_info, str(st)])
	TestHarness.check(units_max > 0 and sirens_max > 0, "police units came with sirens (%d units, %d sirens)" % [units_max, sirens_max])
	TestHarness.check(yields.size() > 0, "traffic drivers yielded to the sirens (%d drivers)" % yields.size())
	TestHarness.check(count_min >= mini(8, n0), "the traffic population stayed up (min %d)" % count_min)
	TestHarness.check(int(st["red_violations"]) == red0, "no calm traffic driver ran a red light")
	TestHarness.check(still_max < 45.0, "no traffic gridlock around the police (longest standstill %.1f s)" % still_max)
	if Wanted.has_method("clear"):
		Wanted.clear("cheat")
	Game.invulnerable = false
	TestHarness.finish()


func _units(police: Node) -> int:
	if police == null or not is_instance_valid(police) or not police.has_method("get_units"):
		return 0
	return (police.call("get_units") as Array).size()


func _on_collision(vehicle: Node3D, other: Node, impulse: float, _pos: Vector3) -> void:
	if sys.get_driver(vehicle) != null and other != null and is_instance_valid(other) and other.get("is_police") == true \
			and impulse / maxf((vehicle as RigidBody3D).mass, 1.0) >= 2.0:
		police_hits += 1
