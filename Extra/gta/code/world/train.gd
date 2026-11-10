extends Node3D
## Elevated transit: a two-car train running the downtown loop on a fixed route. It stops at both
## stations; the player can board at a platform, ride and get off at the next stop.

const CRUISE := 13.0
const DWELL := 8.0

var pts := PackedVector3Array()
var cum := PackedFloat32Array()
var total := 0.0
var s := 0.0
var speed := 0.0
var stops: Array = []
var dwell := 0.0
var next_stop := 0
var cars: Array = []
var bodies: Array = []
var stopped_at := -1
var player_on := false
var horn_cd := 0.0


func _ready() -> void:
	if G.world == null or not G.world.spawns.has("rail"):
		set_process(false)
		set_physics_process(false)
		return
	var rail: Dictionary = G.world.spawns["rail"]
	pts = rail.points
	cum.resize(pts.size() + 1)
	for i in pts.size():
		cum[i] = total
		total += pts[i].distance_to(pts[(i + 1) % pts.size()])
	cum[pts.size()] = total
	for st in rail.stations:
		var best := 0.0
		var bd := 1e9
		for i in pts.size():
			var d := pts[i].distance_to(st)
			if d < bd:
				bd = d
				best = cum[i]
		stops.append(best)
	stops.sort()
	var mesh := Assets.mesh("world/kit_landmarks", "train_car")
	for i in 2:
		var body := AnimatableBody3D.new()
		body.collision_layer = G.L_WORLD
		body.collision_mask = 0
		body.sync_to_physics = false
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(2.9, 3.0, 15.0)
		cs.shape = bs
		cs.position = Vector3(0, 1.8, 0)
		body.add_child(cs)
		add_child(body)
		cars.append(body)
	s = stops[0] - 60.0
	next_stop = 0


func sample(d: float) -> Transform3D:
	d = fposmod(d, total)
	var lo := 0
	var hi := pts.size()
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var a := pts[lo]
	var b := pts[(lo + 1) % pts.size()]
	var seg := cum[lo + 1] - cum[lo]
	var t := (d - cum[lo]) / maxf(seg, 0.001)
	var dir := (b - a).normalized()
	return Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), a.lerp(b, t))


func _physics_process(delta: float) -> void:
	horn_cd -= delta
	var target: float = stops[next_stop]
	var dist := fposmod(target - s, total)
	if dwell > 0.0:
		dwell -= delta
		speed = 0.0
		if dwell <= 0.0:
			stopped_at = -1
			next_stop = (next_stop + 1) % stops.size()
	else:
		var want := CRUISE
		if dist < 45.0:
			want = clampf(dist * 0.32, 0.6, CRUISE)
		speed = move_toward(speed, want, delta * 2.2)
		s += speed * delta
		if dist < 0.6:
			dwell = DWELL
			stopped_at = next_stop
			Sfx.play("horn_truck", sample(s).origin, -6.0, 1.3)
	for i in cars.size():
		var xf := sample(s - i * 15.6)
		(cars[i] as Node3D).global_transform = xf
	# anything standing on the track gets knocked aside
	var p: Player = G.player
	if p != null and not player_on and speed > 2.0 and p.ragdoll == null and p.vehicle == null:
		var front := sample(s + 8.5).origin
		if p.global_position.distance_to(front + Vector3(0, 0.5, 0)) < 3.0:
			var dir := -(cars[0] as Node3D).global_transform.basis.z
			p.take_damage(speed * 3.0, null, front, "vehicle")
			p.knockdown(dir * speed * 0.8 + Vector3(0, 4, 0))
	_player_logic()


func _player_logic() -> void:
	var p: Player = G.player
	if p == null or G.world == null or G.hud == null:
		return
	if player_on:
		G.hud.alt_text = "TRAIN  -  %s" % ("F: get off at this station" if stopped_at >= 0 else "next stop in %d m" % int(fposmod(float(stops[next_stop]) - s, total)))
		return
	if stopped_at < 0 or p.st != p.St.FOOT or G.ui_blocking > 0:
		return
	var car: Node3D = cars[0]
	if p.global_position.distance_to(car.global_position + Vector3(0, 1.0, 0)) < 9.5 and p.global_position.y > car.global_position.y - 0.5:
		G.hud.prompt_text = "[E]  Board the Loop Line train"
		if Input.is_action_just_pressed("interact"):
			_board()


func _board() -> void:
	var p: Player = G.player
	player_on = true
	p.st = p.St.RIDE
	p.ride_node = self
	p.vis.visible = false
	p.get_node("Col").disabled = true
	p.velocity = Vector3.ZERO
	Sfx.ui("select")
	G.say("Riding the Loop Line  -  press F at a station to get off", UIKit.TEAL)


func player_leave() -> void:
	## Called by the player (F). Only possible while the train is standing at a platform.
	var p: Player = G.player
	if stopped_at < 0:
		G.say("Wait for the next station", UIKit.DIM)
		return
	var plat: Vector3 = (G.world.pois["station_a"] if _station_id() == 0 else G.world.pois["station_b"]).platform
	player_on = false
	p.ride_node = null
	p.st = p.St.FOOT
	p.vis.visible = true
	p.get_node("Col").disabled = false
	p.global_position = plat + Vector3(0, 0.2, 0)
	G.hud.alt_text = ""


func _station_id() -> int:
	var here := sample(s).origin
	var a: Vector3 = G.world.pois["station_a"].platform
	var b: Vector3 = G.world.pois["station_b"].platform
	return 0 if here.distance_to(a) < here.distance_to(b) else 1


func _process(_delta: float) -> void:
	# the player object follows the lead car while riding
	if player_on and G.player:
		global_position = (cars[0] as Node3D).global_position
