extends Node
## Autoload "Audio": sound playback service for the whole game.
##
## Every sound is original and synthesised by tools/audio/synth.py into
## res://gta/generated/audio/<id>.wav (ids: docs/ARCHITECTURE.md 6.11, docs/AUDIO.md).
## Unknown ids are silent - no errors, no crash - so gameplay code can call any id safely.
##
## What this node does:
##   * builds the bus layout at boot: Master (hard limiter) <- SFX <- {Weapons, Engine},
##     Music, Ambience, UI; a toggleable low-pass on SFX / Music / Ambience for underwater;
##   * one-shots come from fixed pools (12 non-positional + 32 positional voices) with voice
##     stealing by age / distance - nothing is allocated per call;
##   * `*_loop` ids (and radio music) are configured as forward loops when they are loaded;
##   * per-category distance attenuation, default volume trim and pitch variation;
##   * a few global stingers are played from EventBus signals (wanted level, UI open/close).
##
## Contract (frozen): play, play_at, make_loop_player, make_loop_player_2d, get_stream,
## has_sound keep their names and parameter order. Additions: play_ui, stop_all,
## set_underwater / is_underwater, get_stats, get_sound_ids, get_bus_names, set_bus_volume.

signal underwater_changed(on: bool)

const AUDIO_DIR := "res://gta/generated/audio"
const BUS_NAMES: Array[String] = ["Master", "SFX", "Weapons", "Engine", "Music", "Ambience", "UI"]
const BUS_SENDS := {"SFX": "Master", "Weapons": "SFX", "Engine": "SFX", "Music": "Master",
	"Ambience": "Master", "UI": "Master"}
## Static trims of the buses this module owns alone (Settings drives Master/SFX/Music/Ambience).
const BUS_TRIM_DB := {"Weapons": 0.0, "Engine": -2.0, "UI": -3.0}
const UNDERWATER_BUSES: Array[String] = ["SFX", "Music", "Ambience"]
const UNDERWATER_CUTOFF_HZ := 560.0
const OPEN_CUTOFF_HZ := 18000.0

const POOL_2D := 12
const POOL_3D := 32
const DEDUPE_2D_MSEC := 45      ## the same non-positional id again within this window is dropped
const DEDUPE_3D_MSEC := 25      ## ... positional: same id, same spot (within DEDUPE_3D_DIST)
const DEDUPE_3D_DIST := 1.5

## Canonical sound ids (docs/ARCHITECTURE.md 6.11). Radio music loops are radio_<station>_<n>.
const SOUND_IDS: Array[String] = [
	"pistol_shot", "heavy_pistol_shot", "smg_shot", "rifle_shot", "shotgun_shot", "sniper_shot",
	"suppressed_shot", "rocket_launch", "grenade_launcher_shot", "dry_fire", "reload", "weapon_switch",
	"melee_swing", "melee_hit", "punch_hit", "knife_hit", "grenade_bounce", "pin_pull",
	"impact_concrete", "impact_metal", "impact_glass", "impact_flesh", "impact_wood", "impact_dirt",
	"impact_water", "ricochet", "glass_break", "explosion_small", "explosion_large", "fire_loop",
	"footstep_concrete", "footstep_grass", "footstep_sand", "footstep_metal", "footstep_wood", "footstep_water",
	"jump_land", "body_fall", "splash_small", "splash_large", "swim_stroke", "underwater_loop", "breath_gasp",
	"grunt_hit_m", "grunt_hit_f", "scream_m", "scream_f", "death_m", "death_f", "chatter_loop",
	"engine_car_loop", "engine_sport_loop", "engine_truck_loop", "engine_bike_loop", "engine_boat_loop",
	"heli_rotor_loop", "plane_prop_loop", "jet_loop", "bicycle_loop", "tire_skid_loop", "tire_roll_loop",
	"crash_small", "crash_large", "metal_scrape_loop", "horn_car", "horn_truck", "horn_bike", "door_open",
	"door_close", "engine_start", "tire_pop", "siren_police_loop", "siren_ambulance_loop", "siren_fire_loop",
	"tram_bell", "tram_loop", "parachute_open", "parachute_loop", "wind_fall_loop",
	"ui_click", "ui_hover", "ui_open", "ui_close", "ui_error", "ui_buy", "ui_tab", "pickup_cash", "pickup_weapon",
	"pickup_health", "wanted_up", "wanted_down", "wanted_clear", "arrested", "player_down", "camera_shutter",
	"phone_open", "cash_register", "spray_paint", "wrench", "target_hit", "activity_start", "activity_win",
	"rain_loop", "rain_heavy_loop", "thunder_1", "thunder_2", "wind_loop", "ocean_loop", "city_loop",
	"industrial_loop", "park_birds_loop", "night_crickets_loop", "airport_loop", "harbor_loop",
	"radio_static", "animal_deer", "animal_dog_bark", "animal_bird", "animal_gull", "animal_growl",
]

## Category profiles: 3D falloff (unit_size = distance of 0 dB with inverse-distance falloff),
## minimum audible range, distance low-pass, default trim and automatic pitch variation.
const PROFILES := {
	"weapon": {"unit": 14.0, "min_range": 150.0, "cutoff": 9000.0, "db": 0.0, "var": 0.03, "bus": "Weapons"},
	"explosion": {"unit": 30.0, "min_range": 280.0, "cutoff": 7000.0, "db": 1.5, "var": 0.05, "bus": "Weapons"},
	"impact": {"unit": 5.0, "min_range": 0.0, "cutoff": 6000.0, "db": -1.0, "var": 0.07, "bus": ""},
	"footstep": {"unit": 3.0, "min_range": 0.0, "cutoff": 5000.0, "db": -2.0, "var": 0.06, "bus": ""},
	"voice": {"unit": 6.0, "min_range": 0.0, "cutoff": 5000.0, "db": -1.0, "var": 0.04, "bus": ""},
	"vehicle": {"unit": 8.0, "min_range": 0.0, "cutoff": 5500.0, "db": 0.0, "var": 0.03, "bus": ""},
	"engine": {"unit": 6.5, "min_range": 0.0, "cutoff": 5000.0, "db": 0.0, "var": 0.0, "bus": "Engine"},
	"siren": {"unit": 18.0, "min_range": 150.0, "cutoff": 6500.0, "db": -2.0, "var": 0.0, "bus": ""},
	"horn": {"unit": 12.0, "min_range": 0.0, "cutoff": 6000.0, "db": -1.0, "var": 0.0, "bus": ""},
	"animal": {"unit": 8.0, "min_range": 0.0, "cutoff": 6000.0, "db": -3.0, "var": 0.06, "bus": ""},
	"ambience": {"unit": 20.0, "min_range": 0.0, "cutoff": 6000.0, "db": 0.0, "var": 0.0, "bus": ""},
	"ui": {"unit": 8.0, "min_range": 0.0, "cutoff": 20000.0, "db": -2.0, "var": 0.0, "bus": ""},
	"default": {"unit": 8.0, "min_range": 0.0, "cutoff": 5000.0, "db": 0.0, "var": 0.0, "bus": ""},
}

## id prefix -> category (first match wins; exact ids are checked before prefixes).
const CATEGORY_EXACT := {
	"rocket_launch": "weapon", "dry_fire": "impact", "reload": "impact", "weapon_switch": "impact",
	"melee_swing": "impact", "melee_hit": "impact", "punch_hit": "impact", "knife_hit": "impact",
	"grenade_bounce": "impact", "pin_pull": "impact", "ricochet": "impact", "glass_break": "impact",
	"jump_land": "footstep", "body_fall": "footstep", "swim_stroke": "footstep", "breath_gasp": "voice",
	"tram_bell": "horn", "tram_loop": "engine", "engine_start": "vehicle", "tire_pop": "vehicle",
	"metal_scrape_loop": "vehicle", "fire_loop": "ambience", "chatter_loop": "ambience",
	"underwater_loop": "ambience", "wind_fall_loop": "ambience", "radio_static": "ui",
	"phone_open": "ui", "camera_shutter": "ui", "cash_register": "ui", "spray_paint": "ui",
	"wrench": "ui", "target_hit": "ui", "arrested": "ui", "player_down": "ui",
}
const CATEGORY_PREFIX: Array = [
	["explosion_", "explosion"], ["impact_", "impact"], ["footstep_", "footstep"], ["splash_", "footstep"],
	["grunt_", "voice"], ["scream_", "voice"], ["death_", "voice"],
	["engine_", "engine"], ["heli_", "engine"], ["plane_", "engine"], ["jet_", "engine"],
	["bicycle_", "engine"], ["tire_", "engine"], ["siren_", "siren"], ["horn_", "horn"],
	["crash_", "vehicle"], ["door_", "vehicle"], ["parachute_", "vehicle"], ["animal_", "animal"],
	["ui_", "ui"], ["pickup_", "ui"], ["wanted_", "ui"], ["activity_", "ui"], ["radio_", "ui"],
	["rain_", "ambience"], ["thunder_", "ambience"], ["wind_", "ambience"], ["ocean_", "ambience"],
	["city_", "ambience"], ["industrial_", "ambience"], ["park_", "ambience"], ["night_", "ambience"],
	["airport_", "ambience"], ["harbor_", "ambience"],
]

## Per-id volume trims (dB) on top of the category trim.
const ID_DB := {
	"ui_hover": -3.0, "footstep_metal": -1.0, "sniper_shot": 1.0, "shotgun_shot": 1.0,
	"smg_shot": -1.0, "glass_break": 1.0, "crash_large": 1.0, "weapon_switch": -2.0,
}

## Non-loop ids that can be held as a loop (horns): sustain section [begin_s, end_s] of the file
## that is exactly periodic (see tools/audio/sfx.py `horn`). make_loop_player() uses it.
const SUSTAIN_SECTIONS := {
	"horn_car": [0.2, 0.7], "horn_truck": [0.3, 0.8], "horn_bike": [0.1, 0.35],
}

## 2D ids that must keep sounding while the scene tree is paused (menus).
const ALWAYS_IDS := {"phone_open": true, "camera_shutter": true, "cash_register": true,
	"pickup_cash": true, "pickup_weapon": true, "pickup_health": true}

## Stingers / UI feedback played automatically from EventBus (see _connect_events).
var auto_event_sounds: bool = true

var _cache: Dictionary = {}            ## id -> AudioStream (loops loop, one-shots do not)
var _oneshot_cache: Dictionary = {}    ## loop id -> non-looping copy (for play / play_at)
var _sustain_cache: Dictionary = {}    ## one-shot id -> looping copy (for make_loop_player*)
var _category_cache: Dictionary = {}   ## id -> category name

var _voices_2d: Array[AudioStreamPlayer] = []
var _voices_3d: Array[AudioStreamPlayer3D] = []
var _start_2d: PackedInt64Array = PackedInt64Array()
var _start_3d: PackedInt64Array = PackedInt64Array()
var _last_2d: Dictionary = {}          ## id -> msec of the last non-positional play
var _last_3d: Dictionary = {}          ## id -> [msec, Vector3]
var _last_ui_msec: int = -100000     ## last UI sound played by another module (not by the glue)
var _in_glue: bool = false             ## true while _connect_events handlers play their own stingers
var _loop_players: Array = []          ## WeakRef of players handed out by make_loop_player*

var _stats := {"played_2d": 0, "played_3d": 0, "stolen": 0, "culled": 0, "dropped": 0, "deduped": 0, "unknown": 0}
var _buses_ready: bool = false
var _lowpass: Dictionary = {}          ## bus name -> AudioEffectLowPassFilter
var _uw_env: bool = false              ## set_underwater() (environment system / camera)
var _uw_player: bool = false           ## EventBus.player_submerged
var _uw_mix: float = 0.0               ## 0 dry .. 1 fully muffled (smoothed)
var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()


func _ready() -> void:
	_rng.randomize()
	_build_pools()
	_apply_settings_volumes()
	_connect_events()
	set_process(false)


# --- public API (contract) --------------------------------------------------------------------

func has_sound(sound_id: String) -> bool:
	return get_stream(sound_id) != null


## The stream of a sound id (null if unknown). `*_loop` ids and radio music come back as
## forward loops; everything else as a one-shot.
func get_stream(sound_id: String) -> AudioStream:
	if _cache.has(sound_id):
		return _cache[sound_id]
	var stream: AudioStream = null
	if sound_id != "" and sound_id.is_valid_filename():
		for ext: String in ["wav", "ogg"]:
			var path := "%s/%s.%s" % [AUDIO_DIR, sound_id, ext]
			if ResourceLoader.exists(path):
				stream = load(path) as AudioStream
				break
	if stream is AudioStreamWAV:
		_configure_loop(stream as AudioStreamWAV, is_loop_id(sound_id))
	_cache[sound_id] = stream
	return stream


## Non-positional one-shot (UI, player feedback, stingers). `pitch_variation` is a +- fraction
## (0.05 = +-5 %); negative = use the category default.
func play(sound_id: String, volume_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX",
		pitch_variation: float = -1.0) -> void:
	var stream := _oneshot_stream(sound_id)
	if stream == null or _voices_2d.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_2d.get(sound_id, -100000)) < DEDUPE_2D_MSEC:
		_stats["deduped"] += 1
		return
	_last_2d[sound_id] = now
	var category := get_category(sound_id)
	var prof: Dictionary = PROFILES[category]
	var out_bus := _route_bus(bus, category, sound_id)
	if category == "ui" and not _in_glue:
		_last_ui_msec = now
	var i := _take_2d(now)
	var p := _voices_2d[i]
	if p.playing:
		p.stop()
	p.stream = stream
	p.volume_db = volume_db + float(prof["db"]) + float(ID_DB.get(sound_id, 0.0))
	p.pitch_scale = _pitch(pitch, pitch_variation, float(prof["var"]))
	p.bus = out_bus
	var always := out_bus == "UI" or sound_id.begins_with("ui_") or ALWAYS_IDS.has(sound_id) \
			or (is_inside_tree() and get_tree().paused)
	p.process_mode = Node.PROCESS_MODE_ALWAYS if always else Node.PROCESS_MODE_PAUSABLE
	p.play()
	_start_2d[i] = now
	_stats["played_2d"] += 1


## Positional one-shot in the world. Sounds beyond their audible range are not started at all.
func play_at(sound_id: String, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0,
		max_distance: float = 80.0, bus: String = "SFX", pitch_variation: float = -1.0) -> void:
	var stream := _oneshot_stream(sound_id)
	if stream == null or _voices_3d.is_empty():
		return
	var now := Time.get_ticks_msec()
	var category := get_category(sound_id)
	var prof: Dictionary = PROFILES[category]
	var range_m := maxf(max_distance, float(prof["min_range"]))
	var listener := _listener_position()
	var dist := 0.0
	if listener.is_finite():
		dist = position.distance_to(listener)
		if dist > range_m * 1.05:
			_stats["culled"] += 1
			return
	var last: Variant = _last_3d.get(sound_id, null)
	if last != null and now - int(last[0]) < DEDUPE_3D_MSEC \
			and (last[1] as Vector3).distance_squared_to(position) < DEDUPE_3D_DIST * DEDUPE_3D_DIST:
		_stats["deduped"] += 1
		return
	_last_3d[sound_id] = [now, position]
	var i := _take_3d(now, listener, dist / maxf(range_m, 1.0))
	if i < 0:
		_stats["dropped"] += 1
		return
	var p := _voices_3d[i]
	if p.playing:
		p.stop()
	p.stream = stream
	p.volume_db = volume_db + float(prof["db"]) + float(ID_DB.get(sound_id, 0.0))
	p.pitch_scale = _pitch(pitch, pitch_variation, float(prof["var"]))
	p.bus = _route_bus(bus, category, sound_id)
	_apply_profile(p, prof, range_m)
	p.global_position = position
	p.play()
	_start_3d[i] = now
	_stats["played_3d"] += 1


## Creates (but does not start) a looping 3D player parented to `parent` - engines, sirens,
## rotors, horns. The caller owns it and drives pitch_scale / volume_db / playing.
## Non-loop ids (horns) get a looping copy that sustains the periodic middle of the sample.
func make_loop_player(sound_id: String, parent: Node3D, max_distance: float = 70.0,
		bus: String = "SFX") -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var category := get_category(sound_id)
	var prof: Dictionary = PROFILES[category]
	p.stream = _loop_stream(sound_id)
	p.bus = _route_bus(bus, category, sound_id)
	_apply_profile(p, prof, max_distance)
	if parent != null and is_instance_valid(parent):
		parent.add_child(p)
	else:
		add_child(p)
		p.process_mode = Node.PROCESS_MODE_PAUSABLE
	_loop_players.append(weakref(p))
	return p


## Non-positional loop (ambience beds, rain, radio). Returns the player; the caller owns it.
## It pauses with the game (set process_mode = ALWAYS on it if it must not).
func make_loop_player_2d(sound_id: String, bus: String = "Ambience") -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _loop_stream(sound_id)
	p.bus = _route_bus(bus, get_category(sound_id), sound_id)
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(p)
	_loop_players.append(weakref(p))
	return p


# --- public API (additions) -------------------------------------------------------------------

## UI feedback: non-positional, on the UI bus, audible while the game is paused.
func play_ui(sound_id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	play(sound_id, volume_db, pitch, "UI", 0.0)


## Stops every pooled one-shot voice; with `include_loops` also every loop player that was
## handed out by make_loop_player / make_loop_player_2d (their owners may restart them).
func stop_all(include_loops: bool = false) -> void:
	for p: AudioStreamPlayer in _voices_2d:
		p.stop()
	for p3: AudioStreamPlayer3D in _voices_3d:
		p3.stop()
	if include_loops:
		for ref: WeakRef in _loop_players:
			var n: Variant = ref.get_ref()
			if n != null and is_instance_valid(n):
				(n as Node).call("stop")
	_prune_loop_players()


## Underwater muffling (low-pass on SFX / Music / Ambience). Called by the environment system;
## EventBus.player_submerged is honoured as well.
func set_underwater(on: bool) -> void:
	_uw_env = on
	_underwater_updated()


func is_underwater() -> bool:
	return _uw_env or _uw_player


func is_loop_id(sound_id: String) -> bool:
	return sound_id.ends_with("_loop") or (sound_id.begins_with("radio_") and sound_id != "radio_static")


func get_category(sound_id: String) -> String:
	if _category_cache.has(sound_id):
		return _category_cache[sound_id]
	var category := "default"
	if CATEGORY_EXACT.has(sound_id):
		category = CATEGORY_EXACT[sound_id]
	elif sound_id.ends_with("_shot"):
		category = "weapon"
	elif is_loop_id(sound_id) and sound_id.begins_with("radio_"):
		category = "default"
	else:
		for pair: Array in CATEGORY_PREFIX:
			if sound_id.begins_with(pair[0]):
				category = pair[1]
				break
	_category_cache[sound_id] = category
	return category


func get_bus_names() -> Array[String]:
	return BUS_NAMES.duplicate()


## linear 0..1 (the Settings autoload owns Master / SFX / Music / Ambience persistently).
func set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)) + float(BUS_TRIM_DB.get(bus, 0.0)))


## Every sound id that exists on disk (canonical ids first, then extras such as radio loops).
func get_sound_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in SOUND_IDS:
		if has_sound(id):
			out.append(id)
	var dir := DirAccess.open(AUDIO_DIR)
	if dir != null:
		var extra := PackedStringArray()
		for f: String in dir.get_files():
			var base := f.trim_suffix(".import").trim_suffix(".remap")
			if base.get_extension() in ["wav", "ogg"]:
				var id2 := base.get_basename()
				if not SOUND_IDS.has(id2) and not extra.has(id2):
					extra.append(id2)
		extra.sort()
		out.append_array(extra)
	return out


## Pool / activity counters for debugging and tests.
func get_stats() -> Dictionary:
	var d := _stats.duplicate()
	var a2 := 0
	for p: AudioStreamPlayer in _voices_2d:
		if p.playing:
			a2 += 1
	var a3 := 0
	for p3: AudioStreamPlayer3D in _voices_3d:
		if p3.playing:
			a3 += 1
	_prune_loop_players()
	d["active_2d"] = a2
	d["active_3d"] = a3
	d["pool_2d"] = _voices_2d.size()
	d["pool_3d"] = _voices_3d.size()
	d["loop_players"] = _loop_players.size()
	d["children"] = get_child_count()
	d["cached_streams"] = _cache.size()
	return d


# --- streams ----------------------------------------------------------------------------------

func _frame_count(wav: AudioStreamWAV) -> int:
	return int(round(wav.get_length() * float(wav.mix_rate)))


func _configure_loop(wav: AudioStreamWAV, looping: bool) -> void:
	if looping:
		wav.loop_begin = 0
		wav.loop_end = _frame_count(wav)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	else:
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED


## Stream for play / play_at: never loops (a loop id played as a one-shot plays once).
func _oneshot_stream(sound_id: String) -> AudioStream:
	var stream := get_stream(sound_id)
	if stream == null:
		_stats["unknown"] += 1
		return null
	if stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED:
		if not _oneshot_cache.has(sound_id):
			var copy := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
			copy.loop_mode = AudioStreamWAV.LOOP_DISABLED
			_oneshot_cache[sound_id] = copy
		return _oneshot_cache[sound_id]
	return stream


## Stream for make_loop_player*: always loops.
func _loop_stream(sound_id: String) -> AudioStream:
	var stream := get_stream(sound_id)
	if stream == null or not (stream is AudioStreamWAV):
		return stream
	var wav := stream as AudioStreamWAV
	if wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return wav
	if not _sustain_cache.has(sound_id):
		var copy := wav.duplicate() as AudioStreamWAV
		var frames := _frame_count(wav)
		var begin := 0
		var end := frames
		if SUSTAIN_SECTIONS.has(sound_id):
			var sec: Array = SUSTAIN_SECTIONS[sound_id]
			begin = clampi(int(round(float(sec[0]) * wav.mix_rate)), 0, frames)
			end = clampi(int(round(float(sec[1]) * wav.mix_rate)), begin + 1, frames)
		copy.loop_begin = begin
		copy.loop_end = end
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_sustain_cache[sound_id] = copy
	return _sustain_cache[sound_id]


# --- voices -----------------------------------------------------------------------------------

func _build_pools() -> void:
	_start_2d.resize(POOL_2D)
	_start_3d.resize(POOL_3D)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.name = "Voice2D_%02d" % i
		p.bus = "SFX"
		add_child(p)
		_voices_2d.append(p)
		_start_2d[i] = 0
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.name = "Voice3D_%02d" % i
		p3.bus = "SFX"
		p3.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(p3)
		_voices_3d.append(p3)
		_start_3d[i] = 0


## Free voice, else the oldest one (stolen).
func _take_2d(_now: int) -> int:
	var oldest := 0
	var oldest_t: int = 0x7FFFFFFFFFFFFFFF
	for i in POOL_2D:
		if not _voices_2d[i].playing:
			return i
		if _start_2d[i] < oldest_t:
			oldest_t = _start_2d[i]
			oldest = i
	_stats["stolen"] += 1
	return oldest


## Free voice, else steal the least important one: far away (relative to its range) and old.
## Returns -1 when the new sound is less important than everything that is playing.
func _take_3d(now: int, listener: Vector3, new_rel_dist: float) -> int:
	var victim := -1
	var victim_score := -INF
	var has_listener := listener.is_finite()
	for i in POOL_3D:
		var p := _voices_3d[i]
		if not p.playing:
			return i
		var rel := 0.0
		if has_listener:
			rel = p.global_position.distance_to(listener) / maxf(p.max_distance, 1.0)
		var score := rel + float(now - _start_3d[i]) * 0.0004
		if score > victim_score:
			victim_score = score
			victim = i
	if new_rel_dist > victim_score:
		return -1
	_stats["stolen"] += 1
	return victim


func _apply_profile(p: AudioStreamPlayer3D, prof: Dictionary, range_m: float) -> void:
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = float(prof["unit"])
	p.max_distance = range_m
	p.max_db = 3.0
	p.attenuation_filter_cutoff_hz = float(prof["cutoff"])
	p.attenuation_filter_db = -18.0
	p.panning_strength = 1.0


func _pitch(pitch: float, variation: float, default_variation: float) -> float:
	var v := default_variation if variation < 0.0 else variation
	var out := pitch
	if v > 0.0:
		out *= 1.0 + _rng.randf_range(-v, v)
	return clampf(out, 0.05, 8.0)


func _route_bus(bus: String, category: String, sound_id: String) -> String:
	var out := bus
	if bus == "SFX" or bus == "":
		var preferred := str((PROFILES[category] as Dictionary)["bus"])
		if preferred != "":
			out = preferred
		elif sound_id.begins_with("ui_"):
			out = "UI"
		else:
			out = "SFX"
	return out if AudioServer.get_bus_index(out) >= 0 else "Master"


func _listener_position() -> Vector3:
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if cam != null and cam.is_inside_tree():
			return cam.global_position
	if Game.has_player():
		return Game.get_player_position()
	return Vector3.INF


func _prune_loop_players() -> void:
	var keep: Array = []
	for ref: WeakRef in _loop_players:
		var n: Variant = ref.get_ref()
		if n != null and is_instance_valid(n):
			keep.append(ref)
	_loop_players = keep


# --- buses ------------------------------------------------------------------------------------

func _setup_buses() -> void:
	if _buses_ready:
		return
	_buses_ready = true
	for bus_name: String in BUS_NAMES:
		if bus_name == "Master":
			continue
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, BUS_SENDS[bus_name])
		if BUS_TRIM_DB.has(bus_name):
			AudioServer.set_bus_volume_db(idx, float(BUS_TRIM_DB[bus_name]))
	# Master: brick-wall limiter so stacked gunfire / explosions can never clip the output.
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.5
		limiter.pre_gain_db = 0.0
		limiter.release = 0.12
		AudioServer.add_bus_effect(0, limiter)
	# Underwater low-pass, disabled until needed.
	for bus_name: String in UNDERWATER_BUSES:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			continue
		var found: AudioEffectLowPassFilter = null
		for i in AudioServer.get_bus_effect_count(idx):
			var fx := AudioServer.get_bus_effect(idx, i)
			if fx is AudioEffectLowPassFilter:
				found = fx as AudioEffectLowPassFilter
				AudioServer.set_bus_effect_enabled(idx, i, false)
		if found == null:
			found = AudioEffectLowPassFilter.new()
			found.cutoff_hz = OPEN_CUTOFF_HZ
			found.resonance = 0.6
			AudioServer.add_bus_effect(idx, found)
			AudioServer.set_bus_effect_enabled(idx, AudioServer.get_bus_effect_count(idx) - 1, false)
		_lowpass[bus_name] = found


func _apply_settings_volumes() -> void:
	for pair: Array in [["Master", "master_volume"], ["SFX", "sfx_volume"], ["Music", "music_volume"],
			["Ambience", "ambience_volume"]]:
		var v: Variant = Settings.get_value(pair[1])
		if v != null:
			set_bus_volume(pair[0], float(v))


func _underwater_updated() -> void:
	set_process(true)
	underwater_changed.emit(is_underwater())


func _process(delta: float) -> void:
	var target := 1.0 if is_underwater() else 0.0
	_uw_mix = move_toward(_uw_mix, target, delta * 5.0)
	var active := _uw_mix > 0.01
	var cutoff := exp(lerpf(log(OPEN_CUTOFF_HZ), log(UNDERWATER_CUTOFF_HZ), _uw_mix))
	for bus_name: String in _lowpass:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			continue
		var fx: AudioEffectLowPassFilter = _lowpass[bus_name]
		fx.cutoff_hz = cutoff * (1.6 if bus_name == "Music" else 1.0)
		for i in AudioServer.get_bus_effect_count(idx):
			if AudioServer.get_bus_effect(idx, i) == fx:
				if AudioServer.is_bus_effect_enabled(idx, i) != active:
					AudioServer.set_bus_effect_enabled(idx, i, active)
	if is_equal_approx(_uw_mix, target):
		set_process(false)


# --- event glue -------------------------------------------------------------------------------

func _connect_events() -> void:
	EventBus.settings_changed.connect(_apply_settings_volumes)
	EventBus.player_submerged.connect(_on_player_submerged)
	EventBus.player_respawned.connect(_on_player_respawned)
	EventBus.wanted_level_changed.connect(_on_wanted_level_changed)
	EventBus.wanted_cleared.connect(_on_wanted_cleared)
	EventBus.ui_screen_opened.connect(_on_ui_screen.bind(true))
	EventBus.ui_screen_closed.connect(_on_ui_screen.bind(false))
	EventBus.item_purchased.connect(_on_item_purchased)


## Stingers played by the glue itself; they do not count as "another module played a UI sound".
func _glue_play(sound_id: String, volume_db: float, pitch: float = 1.0) -> void:
	_in_glue = true
	play(sound_id, volume_db, pitch, "UI", 0.0)
	_in_glue = false


func _on_player_submerged(underwater: bool) -> void:
	_uw_player = underwater
	_underwater_updated()


func _on_player_respawned(_position: Vector3) -> void:
	_uw_player = false
	_uw_env = false
	_underwater_updated()


func _on_wanted_level_changed(level: int, previous: int) -> void:
	if not auto_event_sounds:
		return
	if level > previous:
		_glue_play("wanted_up", -3.0, 1.0 + 0.03 * float(clampi(level - 1, 0, 4)))
	elif level < previous and level > 0:
		_glue_play("wanted_down", -5.0)


func _on_wanted_cleared(reason: String) -> void:
	if not auto_event_sounds:
		return
	match reason:
		"busted":
			_glue_play("arrested", -3.0)
		"died":
			pass
		_:
			_glue_play("wanted_clear", -4.0)


## Screens get a soft open / close blip unless the UI module already played a UI sound for it
## (checked one frame later, in either order).
func _on_ui_screen(screen_id: String, opened: bool) -> void:
	if not auto_event_sounds or not is_inside_tree():
		return
	var stamp := Time.get_ticks_msec()
	await get_tree().process_frame
	if _last_ui_msec >= stamp - 120:
		return
	if screen_id == "phone" and opened:
		_glue_play("phone_open", -6.0)
	else:
		_glue_play("ui_open" if opened else "ui_close", -8.0)


func _on_item_purchased(_kind: String, _id: String, _price: int) -> void:
	if not auto_event_sounds or not is_inside_tree():
		return
	var stamp := Time.get_ticks_msec()
	await get_tree().process_frame
	if _last_ui_msec >= stamp - 120:
		return
	_glue_play("ui_buy", -4.0)
