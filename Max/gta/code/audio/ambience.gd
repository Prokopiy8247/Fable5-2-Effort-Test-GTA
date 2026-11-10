class_name Ambience
extends Node
## World soundscape and in-vehicle radio.
## Ambience: crossfaded 2D beds chosen from where the listener is (city day / night, park,
## ocean by distance to the coast, industrial, hill wind, underwater) plus sparse one-shots
## (gulls by the sea, dogs at night in Palm Row, distant sirens downtown, police radio near cops).
## Radio: five original generative stations (Music bus) in motor vehicles, cycled with , and .,
## remembered in the settings; a burst of static between stations.

const BEDS := [&"amb_city_day_loop", &"amb_city_night_loop", &"amb_park_loop", &"amb_ocean_loop",
	&"amb_industrial_loop", &"amb_wind_loop", &"underwater_loop", &"crowd_murmur_loop"]
const STATIONS := [
	["OFF", &""], ["NEON 88.4  -  synthwave", &"radio_neon"], ["LOW TIDE FM  -  lo-fi beats", &"radio_lowtide"],
	["PULSE 101  -  house", &"radio_pulse"], ["DUSTY ROAD 92  -  surf rock", &"radio_dusty"], ["DRIFT  -  ambient", &"radio_ambient"],
]

var players: Dictionary = {}          # bed name -> AudioStreamPlayer
var level: Dictionary = {}            # bed name -> current linear gain
var radio: AudioStreamPlayer = null
var static_p: AudioStreamPlayer = null
var station := 1
var _radio_on := false
var _oneshot_cd := 6.0
var _tick := 0.0
var _rng := RandomNumberGenerator.new()
var _positions: Dictionary = {}       # station -> playback position (stations keep "playing" while off)

func _ready() -> void:
	_rng.seed = 4242
	for b in BEDS:
		var p := Audio.make_loop_2d(b, -80.0, &"Ambient")
		if p.stream == null:
			p.queue_free()
			continue
		p.play(_rng.randf() * 4.0)
		players[b] = p
		level[b] = 0.0
	radio = AudioStreamPlayer.new()
	radio.bus = &"Music"
	radio.volume_db = -6.0
	add_child(radio)
	static_p = Audio.make_loop_2d(&"radio_static", -80.0, &"Music")
	station = clampi(int(Settings.get_v("radio_station", 1)), 0, STATIONS.size() - 1)
	Events.player_entered_vehicle.connect(_on_enter)
	Events.player_exited_vehicle.connect(func(_v: Node3D) -> void: _radio_off())

# ---------------------------------------------------------------- radio
func _radio_vehicle() -> bool:
	var p: Player = Game.player
	if p == null or p.vehicle == null or not is_instance_valid(p.vehicle):
		return false
	var v := p.vehicle as Vehicle
	return not bool(v.def.get("pedal", false)) and v.kind != &"bike"

func _on_enter(_v: Node3D, _seat: int) -> void:
	if _radio_vehicle():
		_tune(station, false)

func _radio_off() -> void:
	if radio.playing:
		_positions[station] = radio.get_playback_position()
	radio.stop()
	_radio_on = false
	if static_p != null:
		static_p.stop()

func _tune(i: int, announce := true) -> void:
	if radio.playing:
		_positions[station] = radio.get_playback_position()
	station = posmod(i, STATIONS.size())
	Settings.set_v("radio_station", station)
	var snd: StringName = STATIONS[station][1]
	radio.stop()
	_radio_on = snd != &""
	if _radio_on:
		var s := Audio.loop_stream(snd)
		if s == null:
			_radio_on = false
		else:
			radio.stream = s
			# stations run "live": resume where it would be by now
			var length := s.get_length()
			var pos := float(_positions.get(station, _rng.randf() * maxf(length - 1.0, 0.0)))
			radio.play(fposmod(pos + Game.clock * 0.0, maxf(length, 0.01)))
			if static_p != null and announce:
				static_p.volume_db = -10.0
				static_p.play()
				get_tree().create_timer(0.35).timeout.connect(func() -> void:
					if static_p != null:
						static_p.stop())
	if Game.hud != null and (announce or _radio_on):
		Game.hud.show_radio(String(STATIONS[station][0]))

func _unhandled_input(event: InputEvent) -> void:
	if not _radio_vehicle() or Game.ui_blocked():
		return
	if event.is_action_pressed("radio_next"):
		_tune(station + 1)
	elif event.is_action_pressed("radio_prev"):
		_tune(station - 1)

# ---------------------------------------------------------------- ambience
func _target_levels() -> Dictionary:
	var t := {}
	for b in players.keys():
		t[b] = 0.0
	var p: Player = Game.player
	if p == null:
		return t
	var pos := Game.cam.cam.global_position if Game.cam != null else p.global_position
	var env: WorldEnv = Game.time
	var night := env.night if env != null else 0.0
	var district := Game.district_at(pos)
	var height := pos.y - maxf(Game.ground_y(pos.x, pos.z), Terrain.SEA)
	# under water: only the underwater bed
	if Game.water_depth(pos) > 0.2:
		t[&"underwater_loop"] = 1.0
		return t
	# distance to the sea (south coast and the east harbour)
	var sea_d := minf(absf(pos.z - 222.0), 1000.0)
	if pos.x > 210.0 and pos.z > 120.0:
		sea_d = minf(sea_d, absf(pos.z - 222.0))
	if Terrain.is_water(pos.x, pos.z):
		sea_d = 0.0
	var ocean := clampf(1.0 - sea_d / 90.0, 0.0, 1.0)
	var city := 1.0
	match district:
		"Lookout Hill": city = 0.25
		"Coral Beach", "Saltline Docks": city = 0.55
		"Vesper Airfield": city = 0.4
		"Ironworks": city = 0.6
	t[&"amb_city_day_loop"] = city * (1.0 - night) * (1.0 - ocean * 0.5)
	t[&"amb_city_night_loop"] = city * night * (1.0 - ocean * 0.4)
	t[&"amb_ocean_loop"] = ocean
	t[&"amb_industrial_loop"] = 0.8 if district == "Ironworks" or district == "Saltline Docks" else 0.0
	t[&"amb_park_loop"] = (0.9 if (district == "Palm Row" or district == "Lookout Hill") else 0.0) * (1.0 - night * 0.6)
	var near_park := false
	var city_b: CityBuilder = Game.world.city
	for a in city_b.ped_areas:
		var r: Rect2 = a["rect"]
		if r.grow(10.0).has_point(Vector2(pos.x, pos.z)):
			near_park = String(a["name"]) == "Palm Park" or String(a["name"]) == "Hospital Garden"
			if String(a["name"]) in ["Meridian Square", "Promenade", "Pier"]:
				t[&"crowd_murmur_loop"] = 0.7 * (1.0 - night * 0.7)
	if near_park:
		t[&"amb_park_loop"] = maxf(float(t[&"amb_park_loop"]), 1.0 - night * 0.5)
	t[&"amb_wind_loop"] = clampf((height - 20.0) / 60.0, 0.0, 1.0) + (0.6 if district == "Lookout Hill" else 0.0)
	# inside a vehicle the world is quieter
	if p.vehicle != null:
		for k in t.keys():
			t[k] = float(t[k]) * 0.5
	return t

func _process(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		var target := _target_levels()
		for b in players.keys():
			level[b] = move_toward(float(level[b]), float(target.get(b, 0.0)), 0.25)
			var pl: AudioStreamPlayer = players[b]
			pl.volume_db = linear_to_db(maxf(float(level[b]), 0.0001)) - 4.0
		_oneshots(0.5)
	if _radio_on and not _radio_vehicle():
		_radio_off()

func _oneshots(dt: float) -> void:
	_oneshot_cd -= dt
	if _oneshot_cd > 0.0:
		return
	_oneshot_cd = _rng.randf_range(4.0, 11.0)
	var p: Player = Game.player
	if p == null:
		return
	var pos := p.global_position
	var district := Game.district_at(pos)
	var env: WorldEnv = Game.time
	var night := env.night if env != null else 0.0
	var a := _rng.randf() * TAU
	var where := pos + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(18.0, 45.0) + Vector3(0, 6.0, 0)
	if absf(pos.z - 222.0) < 70.0 and night < 0.6 and _rng.randf() < 0.6:
		Audio.play(StringName("seagull_%d" % (1 + _rng.randi() % 2)), where, -8.0, _rng.randf_range(0.9, 1.15), 0.05, 120.0, &"Ambient")
	elif district == "Palm Row" and _rng.randf() < 0.35:
		Audio.play(StringName("dog_bark_%d" % (1 + _rng.randi() % 2)), where - Vector3(0, 6.0, 0), -10.0, 1.0, 0.08, 110.0, &"Ambient")
	elif (district == "Downtown" or district == "Midtown") and _rng.randf() < 0.25 and (Game.wanted == null or Game.wanted.level == 0):
		Audio.play(&"siren_police_loop", where + Vector3(0, 0, 80.0), -22.0, 1.0, 0.0, 300.0, &"Ambient")
	for n in get_tree().get_nodes_in_group(&"police_units"):
		if (n as Node3D).global_position.distance_to(pos) < 20.0 and _rng.randf() < 0.4:
			Audio.play(StringName("police_radio_%d" % (1 + _rng.randi() % 2)), (n as Node3D).global_position + Vector3(0, 1.2, 0), -12.0, 1.0, 0.05, 30.0)
			break
