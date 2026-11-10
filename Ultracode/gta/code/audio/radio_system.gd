class_name RadioSystem
extends Node
## World system "radio": the in-vehicle radio.
##
## * Stations come from Registry kind "radio_stations" (resources/registries/radio_registry.gd).
## * Music plays on the Music bus while the player sits in a vehicle that has a radio
##   (not bicycles, not police / emergency vehicles, not wrecks).
## * Input actions radio_next / radio_prev cycle through the stations including "off".
## * Every station is a continuous "broadcast": its two loops alternate on a shared clock, so
##   switching away and back does not restart the music, and tuning in lands mid-song.
## * A short static blip marks every station change; the last station is remembered in
##   Settings ("radio_station"); EventBus.radio_station_changed(id) is emitted on change.
## * The players are pausable, so the radio pauses with the game.
##
## API for the radio wheel UI: get_stations(), get_station(), set_station(id), next_station(),
## prev_station(), get_station_info(id), is_listening(), is_playing(), get_now_playing().

signal station_changed(station_id: String)
signal listening_changed(listening: bool)

const OFF := "off"
const KIND := "radio_stations"
const REPEATS := 2                 ## how many times a loop plays before the station moves on
const FADE_IN_SEC := 0.45
const FADE_OUT_SEC := 0.3
const CROSSFADE_SEC := 1.4
const TUNE_DELAY_SEC := 0.14       ## music comes in just after the static blip
const NO_RADIO_CLASSES: Array[String] = ["bicycle"]

var enabled: bool = true
var announce: bool = true          ## toast with the station name on change (UI.notify)

var _stations: Array[Dictionary] = []
var _station: String = OFF
var _listening: bool = false
var _clock: float = 0.0            ## broadcast clock in seconds (advances while unpaused)
var _active: AudioStreamPlayer = null
var _fading: AudioStreamPlayer = null
var _active_track: String = ""
var _active_gain: float = 0.0
var _fading_gain: float = 0.0
var _tune_delay: float = 0.0
var _poll_t: float = 0.0
var _lengths: Dictionary = {}      ## track id -> seconds
var _setup_done: bool = false
var _forced: int = -1              ## test / debug override of "listening": -1 auto, 0 off, 1 on


func _ready() -> void:
	if not _setup_done:
		setup()


func setup() -> void:
	if _setup_done:
		return
	_setup_done = true
	_load_stations()
	_active = _make_player("RadioA")
	_fading = _make_player("RadioB")
	# start the broadcast at a pseudo-random point so the first tune-in is mid-song
	_clock = fmod(float(Time.get_ticks_msec()) * 0.001 + float(Time.get_unix_time_from_system()), 600.0)
	var saved: Variant = Settings.get_value("radio_station")
	var want := str(saved) if saved != null else ""
	if want == OFF:
		_station = OFF
	elif _has_station(want):
		_station = want
	elif not _stations.is_empty():
		_station = str(_stations[0]["id"])
	EventBus.player_entered_vehicle.connect(_on_vehicle_event)
	EventBus.player_exited_vehicle.connect(_on_vehicle_exit)
	EventBus.player_died.connect(_on_player_died)


# --- public API -------------------------------------------------------------------------------

## Station definitions in dial order. Each: {id, name, genre, frequency, tagline, color, tracks,
## volume_db, order}. With include_off an entry {id = "off", name = "Radio Off"} comes first.
func get_stations(include_off: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if include_off:
		out.append(_off_info())
	for s: Dictionary in _stations:
		out.append(s)
	return out


func get_station_ids(include_off: bool = true) -> PackedStringArray:
	var out := PackedStringArray()
	if include_off:
		out.append(OFF)
	for s: Dictionary in _stations:
		out.append(str(s["id"]))
	return out


## Currently selected station id, or "off".
func get_station() -> String:
	return _station


func get_station_info(station_id: String = "") -> Dictionary:
	var id := _station if station_id == "" else station_id
	for s: Dictionary in _stations:
		if str(s["id"]) == id:
			return s
	return _off_info()


## Select a station ("off" or "" turns the radio off). Unknown ids are ignored.
func set_station(station_id: String) -> void:
	var id := OFF if station_id == "" else station_id
	if id != OFF and not _has_station(id):
		return
	if id == _station:
		return
	_station = id
	Settings.set_value("radio_station", id)
	if _listening:
		Audio.play("radio_static", -5.0, randf_range(0.9, 1.15), "Music", 0.0)
		_retune(true)
		if announce:
			_announce()
	station_changed.emit(id)
	EventBus.radio_station_changed.emit(id)


func next_station() -> void:
	_cycle(1)


func prev_station() -> void:
	_cycle(-1)


## True while the player sits in a vehicle that has a radio.
func is_listening() -> bool:
	return _listening


## True while music is actually sounding (listening and not "off").
func is_playing() -> bool:
	return _listening and _station != OFF and _active != null and _active.playing


func get_now_playing() -> Dictionary:
	var info := get_station_info()
	return {"station": _station, "name": str(info.get("name", "")), "genre": str(info.get("genre", "")),
		"track": _active_track, "listening": _listening, "playing": is_playing(),
		"position": _active.get_playback_position() if (_active != null and _active.playing) else 0.0}


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		_set_listening(false)


## Debug / tests: force the "player is in a radio vehicle" state. -1 = automatic.
func force_listening(mode: int) -> void:
	_forced = clampi(mode, -1, 1)
	_update_listening()


func reset_for_respawn() -> void:
	_update_listening()


func get_save_data() -> Dictionary:
	return {"station": _station}


func load_save_data(d: Dictionary) -> void:
	if d.has("station"):
		set_station(str(d["station"]))


# --- internals --------------------------------------------------------------------------------

func _load_stations() -> void:
	_stations.clear()
	for def: Variant in Registry.all(KIND):
		if def is Dictionary and (def as Dictionary).has("id"):
			var d: Dictionary = (def as Dictionary).duplicate(true)
			var tracks: Array = []
			for t: Variant in d.get("tracks", []):
				if Audio.has_sound(str(t)):
					tracks.append(str(t))
			d["tracks"] = tracks
			if not tracks.is_empty():
				_stations.append(d)
	_stations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 0)) < int(b.get("order", 0)))


func _off_info() -> Dictionary:
	return {"id": OFF, "name": "Radio Off", "genre": "", "frequency": "", "tagline": "",
		"color": Color(0.6, 0.62, 0.68), "tracks": [], "volume_db": 0.0, "order": -1}


func _has_station(id: String) -> bool:
	for s: Dictionary in _stations:
		if str(s["id"]) == id:
			return true
	return false


func _make_player(node_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	p.volume_db = -80.0
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(p)
	return p


func _cycle(dir: int) -> void:
	var ids := get_station_ids(true)
	if ids.size() <= 1:
		return
	var i := ids.find(_station)
	if i < 0:
		i = 0
	set_station(ids[posmod(i + dir, ids.size())])


func _track_length(track: String) -> float:
	if not _lengths.has(track):
		var st := Audio.get_stream(track)
		_lengths[track] = maxf(st.get_length(), 1.0) if st != null else 1.0
	return _lengths[track]


## Where the station's broadcast is at `clock`: {track, offset, remaining}.
func locate(station_id: String, clock: float) -> Dictionary:
	var info := get_station_info(station_id)
	var tracks: Array = info.get("tracks", [])
	if tracks.is_empty():
		return {"track": "", "offset": 0.0, "remaining": 0.0}
	var total := 0.0
	for t: Variant in tracks:
		total += _track_length(str(t)) * REPEATS
	var u := fposmod(clock + float(int(info.get("order", 0))) * 47.0, total)
	for t: Variant in tracks:
		var block := _track_length(str(t)) * REPEATS
		if u < block:
			return {"track": str(t), "offset": fmod(u, _track_length(str(t))), "remaining": block - u}
		u -= block
	return {"track": str(tracks[0]), "offset": 0.0, "remaining": _track_length(str(tracks[0]))}


func _station_gain_db() -> float:
	return float(get_station_info().get("volume_db", -3.0))


## Start (or restart) the active player on the selected station.
func _retune(with_delay: bool) -> void:
	if _active == null:
		return
	# whatever was playing fades out on the second player
	if _active.playing and _active_gain > 0.001:
		var tmp := _active
		_active = _fading
		_fading = tmp
		_fading_gain = _active_gain
	if _active.playing:
		_active.stop()
	_active_gain = 0.0
	_active.volume_db = -80.0
	_active_track = ""
	if not _listening or _station == OFF:
		return
	var loc := locate(_station, _clock)
	var stream := Audio.get_stream(str(loc["track"]))
	if stream == null:
		return
	_active.stream = stream
	_active_track = str(loc["track"])
	_tune_delay = TUNE_DELAY_SEC if with_delay else 0.0
	_active.play(clampf(float(loc["offset"]), 0.0, maxf(stream.get_length() - 0.05, 0.0)))


func _set_listening(on: bool) -> void:
	if on == _listening:
		return
	_listening = on
	if on:
		if _station != OFF:
			Audio.play("radio_static", -9.0, randf_range(0.95, 1.1), "Music", 0.0)
		_retune(true)
		if announce and _station != OFF:
			_announce()
	else:
		_retune(false)
	listening_changed.emit(on)


func _vehicle_has_radio(v: Node) -> bool:
	if v == null or not is_instance_valid(v):
		return false
	var cls: Variant = v.get("vehicle_class")
	if cls != null and NO_RADIO_CLASSES.has(str(cls)):
		return false
	if v.get("is_emergency") == true or v.get("is_police") == true:
		return false
	if v.get("destroyed") == true:
		return false
	return true


func _update_listening() -> void:
	var on := false
	if enabled:
		if _forced >= 0:
			on = _forced == 1
		else:
			on = _vehicle_has_radio(Game.get_player_vehicle())
	_set_listening(on)


func _on_vehicle_event(_vehicle: Node3D, _seat: int) -> void:
	_update_listening()


func _on_vehicle_exit(_vehicle: Node3D) -> void:
	# the player may still report the vehicle during the exit animation: re-check shortly
	_poll_t = 0.0
	_update_listening()


func _on_player_died(_cause: String) -> void:
	_poll_t = 0.0


func _announce() -> void:
	var ui := get_node_or_null("/root/UI")
	if ui == null or not ui.has_method("notify"):
		return
	var info := get_station_info()
	if _station == OFF:
		ui.call("notify", "Radio off", "info")
	else:
		ui.call("notify", "%s  -  %s" % [str(info.get("name", "")), str(info.get("genre", ""))], "info")


func _process(delta: float) -> void:
	_clock += delta
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = 0.25
		_update_listening()
	if _listening and not Game.is_input_locked():
		if InputMap.has_action("radio_next") and Input.is_action_just_pressed("radio_next"):
			next_station()
		elif InputMap.has_action("radio_prev") and Input.is_action_just_pressed("radio_prev"):
			prev_station()
	_update_players(delta)


func _update_players(delta: float) -> void:
	if _active == null:
		return
	var base_db := _station_gain_db()
	# outgoing player
	if _fading.playing:
		_fading_gain = move_toward(_fading_gain, 0.0, delta / FADE_OUT_SEC)
		if _fading_gain <= 0.001:
			_fading.stop()
		else:
			_fading.volume_db = base_db + linear_to_db(_fading_gain)
	if not _listening or _station == OFF or _active_track == "":
		return
	# the broadcast moved on to the station's other loop: cross over
	var loc := locate(_station, _clock)
	if str(loc["track"]) != _active_track and str(loc["track"]) != "":
		var stream := Audio.get_stream(str(loc["track"]))
		if stream != null:
			var tmp := _active
			_active = _fading
			_fading = tmp
			_fading_gain = _active_gain
			if _active.playing:
				_active.stop()
			_active.stream = stream
			_active_track = str(loc["track"])
			_active_gain = 0.0
			_active.volume_db = -80.0
			_active.play(clampf(float(loc["offset"]), 0.0, maxf(stream.get_length() - 0.05, 0.0)))
			_tune_delay = 0.0
	if not _active.playing and _active.stream != null and not get_tree().paused:
		_active.play(float(loc["offset"]))
	if _tune_delay > 0.0:
		_tune_delay -= delta
		return
	var rate := delta / (CROSSFADE_SEC if _fading.playing else FADE_IN_SEC)
	_active_gain = move_toward(_active_gain, 1.0, rate)
	_active.volume_db = base_db + linear_to_db(maxf(_active_gain, 0.0001))
