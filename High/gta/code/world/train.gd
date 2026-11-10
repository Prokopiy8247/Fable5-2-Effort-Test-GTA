class_name SkylineTrain
extends Node3D
## Elevated "Skyline" monorail shuttle along the beachfront. Fixed route, three stations, rideable as a passenger.

const RAIL_Z := 189.6
const RAIL_Y := 6.45
const STATIONS := [-170.0, -50.0, 70.0]
const STATION_NAMES := ["Coral Beach West", "Boardwalk", "Marina"]
const FARE := 5

var car: AnimatableBody3D
var x := -170.0
var dir := 1
var speed := 0.0
var dwell := 6.0
var at_station := 0
var target_station := 1
var riding := false
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	car = AnimatableBody3D.new()
	car.collision_layer = Game.L_WORLD
	car.collision_mask = 0
	car.sync_to_physics = false
	var model := Assets.inst("train_car")
	model.rotation.y = PI * 0.5
	car.add_child(model)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(12.0, 2.8, 2.7)
	cs.shape = bs
	cs.position.y = 1.6
	car.add_child(cs)
	add_child(car)
	car.global_position = Vector3(x, RAIL_Y, RAIL_Z)
	_audio = Sfx.loop3d(car, "train_loop", 70.0, -6.0)
	for i in range(STATIONS.size()):
		var idx := i
		Game.world.add_interact(null, Vector3(STATIONS[i], 6.2, RAIL_Z + 2.6), 3.2, "E  Board the Skyline ($%d)" % FARE, func(): _board(idx),
			func(): return dwell > 0.5 and at_station == idx and not riding)


func _board(idx: int) -> void:
	if dwell <= 0.3 or at_station != idx or riding:
		return
	if not Game.spend(FARE):
		return
	riding = true
	Game.player.rig.sit = 1.0
	Game.player.start_ride(car, Vector3(0.0, 0.25, 0.6), _try_exit)
	Game.say("Skyline to %s  -  F to get off at a station" % STATION_NAMES[target_station], Color(0.5, 0.95, 0.9))


func _try_exit() -> void:
	if dwell > 0.0 and at_station >= 0:
		riding = false
		Game.player.end_ride(Vector3(STATIONS[at_station], 6.2, RAIL_Z + 3.4))
	else:
		Game.say("Wait for the next station")


func _physics_process(delta: float) -> void:
	if dwell > 0.0:
		dwell -= delta
		speed = 0.0
		if dwell <= 0.0:
			if at_station == 0:
				dir = 1
			elif at_station == STATIONS.size() - 1:
				dir = -1
			target_station = at_station + dir
			at_station = -1
			if riding:
				Game.say("Next stop: " + STATION_NAMES[target_station], Color(0.5, 0.95, 0.9))
	else:
		var tx: float = STATIONS[target_station]
		var dist := absf(tx - x)
		var want := minf(13.0, sqrt(2.0 * 2.2 * maxf(dist, 0.0)) + 0.4)
		speed = move_toward(speed, want, 3.0 * delta)
		x += signf(tx - x) * minf(speed * delta, dist)
		if dist < 0.05:
			x = tx
			at_station = target_station
			dwell = 7.0
			if riding:
				Game.say("%s station  -  F to get off" % STATION_NAMES[at_station], Color(0.5, 0.95, 0.9))
	car.global_position = Vector3(x, RAIL_Y, RAIL_Z)
	if _audio:
		if speed > 0.5 and not _audio.playing:
			_audio.play()
		elif speed <= 0.5 and _audio.playing:
			_audio.stop()
		_audio.pitch_scale = 0.7 + speed * 0.04
	# safety: knock down anyone standing on the track path is unnecessary (track is 6 m up); vehicles cannot reach it
