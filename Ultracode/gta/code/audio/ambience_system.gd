class_name AmbienceSystem
extends Node
## World system "ambience": layered environmental beds with smooth crossfades.
##
## Inputs, sampled a few times per second:
##   * district   - Game.world.get_district(listener position)
##   * time       - WorldClock.get_daylight(): birds by day, crickets at night, quieter city at night
##   * sea        - distance to the nearest water (terrain probes): ocean bed
##   * altitude   - height above ground / sea: wind rises, ground beds fall away
##   * weather    - Weather.rain_intensity (light rain -> heavy rain crossfade), wind_strength
##   * state      - enclosed vehicle (ducked), underwater (everything ducked, underwater bed in)
## Thunder is NOT played here (the environment system triggers thunder_1 / thunder_2).
## Besides the beds a few sparse positional "life" calls (gulls, birds, a far dog) are placed
## around the listener.
##
## compute_targets(ctx) is a pure function (also used by tests / tools).

const FADE_SEC := 2.4                  ## full-scale crossfade time of a bed
const SAMPLE_SEC := 0.25
const SEA_PROBE_RADII: Array[float] = [14.0, 32.0, 55.0, 85.0]
const SEA_RANGE := 100.0

## layer -> [sound id, level in dB at full gain]
const LAYERS := {
	"city": ["city_loop", -4.0],
	"industrial": ["industrial_loop", -4.0],
	"chatter": ["chatter_loop", -9.0],
	"birds": ["park_birds_loop", -5.0],
	"crickets": ["night_crickets_loop", -6.0],
	"airport": ["airport_loop", -4.0],
	"harbor": ["harbor_loop", -4.0],
	"ocean": ["ocean_loop", -3.0],
	"wind": ["wind_loop", -5.0],
	"rain": ["rain_loop", -3.0],
	"rain_heavy": ["rain_heavy_loop", -2.0],
	"underwater": ["underwater_loop", -2.0],
}

## district -> base weights (nature drives birds by day and crickets at night).
const DISTRICT_MIX := {
	"downtown": {"city": 1.0, "chatter": 0.6, "nature": 0.05, "wind": 0.1},
	"midtown": {"city": 0.85, "chatter": 0.5, "nature": 0.15, "wind": 0.08},
	"residential": {"city": 0.35, "chatter": 0.12, "nature": 0.75, "wind": 0.1},
	"industrial": {"city": 0.3, "industrial": 1.0, "nature": 0.05, "wind": 0.12},
	"waterfront": {"city": 0.35, "chatter": 0.25, "harbor": 1.0, "ocean": 0.35, "nature": 0.1, "wind": 0.2},
	"beach": {"city": 0.1, "chatter": 0.15, "ocean": 0.9, "nature": 0.25, "wind": 0.25},
	"hill": {"city": 0.1, "nature": 1.0, "wind": 0.35},
	"airport": {"city": 0.15, "airport": 1.0, "nature": 0.05, "wind": 0.3},
	"ocean": {"ocean": 1.0, "wind": 0.4},
	"": {"city": 0.5, "nature": 0.3, "wind": 0.15},
}

var enabled: bool = true
var spot_sounds: bool = true           ## sparse positional animal calls around the listener

var _players: Dictionary = {}          ## layer -> AudioStreamPlayer (created on demand)
var _missing: Dictionary = {}          ## layer -> true when its sound does not exist
var _gain: Dictionary = {}             ## layer -> current linear gain
var _target: Dictionary = {}           ## layer -> target linear gain
var _context: Dictionary = {}          ## last sampled context
var _override: Dictionary = {}         ## test / photo-mode override of the context
var _sample_t: float = 0.0
var _sea_t: float = 0.0
var _sea: float = 0.0
var _district_hint: String = ""
var _underwater: bool = false
var _spot_t: float = 6.0
var _rng := RandomNumberGenerator.new()
var _setup_done: bool = false


func _ready() -> void:
	if not _setup_done:
		setup()


func setup() -> void:
	if _setup_done:
		return
	_setup_done = true
	_rng.randomize()
	for layer: String in LAYERS:
		_gain[layer] = 0.0
		_target[layer] = 0.0
	EventBus.player_district_changed.connect(_on_district_changed)
	EventBus.player_submerged.connect(_on_submerged)
	EventBus.player_respawned.connect(_on_respawned)


# --- public API -------------------------------------------------------------------------------

## Pure mix function. ctx keys (all optional): district (String), daylight (0..1), rain (0..1),
## wind (0..1), altitude (m above ground / sea), sea (0..1 proximity of open water),
## in_vehicle (bool, enclosed cabin), underwater (bool). Returns layer -> gain 0..1.
static func compute_targets(ctx: Dictionary) -> Dictionary:
	var district := str(ctx.get("district", ""))
	var day := clampf(float(ctx.get("daylight", 1.0)), 0.0, 1.0)
	var night := 1.0 - day
	var rain := clampf(float(ctx.get("rain", 0.0)), 0.0, 1.0)
	var wind := clampf(float(ctx.get("wind", 0.2)), 0.0, 1.0)
	var alt := maxf(float(ctx.get("altitude", 0.0)), 0.0)
	var sea := clampf(float(ctx.get("sea", 0.0)), 0.0, 1.0)
	var mix: Dictionary = DISTRICT_MIX.get(district, DISTRICT_MIX[""])
	var nature := float(mix.get("nature", 0.0))
	var t := {}
	t["city"] = float(mix.get("city", 0.0)) * lerpf(0.55, 1.0, day)
	t["industrial"] = float(mix.get("industrial", 0.0)) * lerpf(0.6, 1.0, day)
	t["chatter"] = float(mix.get("chatter", 0.0)) * smoothstep(0.25, 0.7, day) * (1.0 - 0.8 * rain)
	t["birds"] = nature * smoothstep(0.2, 0.6, day) * (1.0 - smoothstep(0.1, 0.5, rain))
	t["crickets"] = nature * smoothstep(0.35, 0.75, night) * (1.0 - smoothstep(0.2, 0.6, rain))
	t["airport"] = float(mix.get("airport", 0.0))
	t["harbor"] = float(mix.get("harbor", 0.0))
	t["ocean"] = maxf(float(mix.get("ocean", 0.0)), sea)
	t["wind"] = clampf(float(mix.get("wind", 0.0)) + wind * 0.7 + smoothstep(12.0, 90.0, alt) * 0.8, 0.0, 1.0)
	t["rain"] = smoothstep(0.03, 0.35, rain) * (1.0 - smoothstep(0.5, 0.85, rain))
	t["rain_heavy"] = smoothstep(0.45, 0.85, rain)
	t["underwater"] = 0.0
	# high above the island the ground beds fall away and the wind takes over
	var high := smoothstep(40.0, 160.0, alt)
	for k: String in ["city", "industrial", "chatter", "birds", "crickets", "airport", "harbor"]:
		t[k] = float(t[k]) * (1.0 - 0.85 * high)
	t["ocean"] = float(t["ocean"]) * (1.0 - 0.6 * high)
	if bool(ctx.get("in_vehicle", false)):
		for k: String in t:
			t[k] = float(t[k]) * (0.75 if k.begins_with("rain") else 0.6)
	if bool(ctx.get("underwater", false)):
		for k: String in t:
			t[k] = float(t[k]) * 0.06
		t["underwater"] = 1.0
	return t


## Current (smoothed) gain of every layer.
func get_layer_gains() -> Dictionary:
	return _gain.duplicate()


func get_target_gains() -> Dictionary:
	return _target.duplicate()


## The context the mix is currently based on (district, daylight, rain, ...).
func get_context() -> Dictionary:
	return _context.duplicate()


## Loudest bed right now ("" when silent).
func get_dominant_layer() -> String:
	var best := ""
	var best_g := 0.01
	for layer: String in _target:
		if float(_target[layer]) > best_g:
			best_g = float(_target[layer])
			best = layer
	return best


## Replace the sampled context (tests, photo mode, cut-scenes without a player). Keys as in
## compute_targets; missing keys keep being sampled from the world.
func set_context_override(ctx: Dictionary) -> void:
	_override = ctx.duplicate()
	_sample_t = 0.0


func clear_context_override() -> void:
	_override = {}
	_sample_t = 0.0


## Jump straight to the target mix (no crossfade) - after teleports / loading.
func snap() -> void:
	_sea_t = 0.0
	_sample()
	for layer: String in LAYERS:
		_gain[layer] = float(_target.get(layer, 0.0))
	_apply(0.0)


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		for layer: String in LAYERS:
			_target[layer] = 0.0


func reset_for_respawn() -> void:
	_underwater = false
	_sample_t = 0.0


# --- sampling ---------------------------------------------------------------------------------

func _listener_position() -> Vector3:
	if Game.has_player():
		return Game.get_player_position()
	var vp := get_viewport()
	if vp != null:
		var cam: Camera3D = vp.get_camera_3d()
		if cam != null:
			return cam.global_position
	return Vector3.ZERO


func _sample_context(delta_since: float) -> Dictionary:
	var pos := _listener_position()
	var ctx := {}
	var district := _district_hint
	var world := Game.world
	if world != null and is_instance_valid(world) and world.has_method("get_district"):
		district = str(world.call("get_district", pos))
	ctx["district"] = district
	ctx["daylight"] = float(WorldClock.get_daylight()) if WorldClock.has_method("get_daylight") else 1.0
	var rain: Variant = Weather.get("rain_intensity")
	var wind: Variant = Weather.get("wind_strength")
	ctx["rain"] = float(rain) if rain != null else 0.0
	ctx["wind"] = float(wind) if wind != null else 0.2
	var ground := maxf(Game.ground_height(pos.x, pos.z), Game.WATER_LEVEL)
	ctx["altitude"] = maxf(pos.y - ground, 0.0)
	_sea_t -= delta_since
	if _sea_t <= 0.0:
		_sea_t = 0.6
		_sea = _sea_proximity(pos)
	ctx["sea"] = _sea
	var vehicle := Game.get_player_vehicle()
	var enclosed := false
	if vehicle != null:
		var cls := str(vehicle.get("vehicle_class"))
		enclosed = cls == "car" or cls == "heli" or cls == "plane"
	ctx["in_vehicle"] = enclosed
	var submerged := _underwater
	if Game.has_player() and Game.player.get("is_underwater") != null:
		submerged = bool(Game.player.get("is_underwater"))
	ctx["underwater"] = submerged or (Audio.has_method("is_underwater") and bool(Audio.call("is_underwater")))
	for k: String in _override:
		ctx[k] = _override[k]
	return ctx


## 0 (inland) .. 1 (standing in / next to open water), from terrain probes around `pos`.
func _sea_proximity(pos: Vector3) -> float:
	var world := Game.world
	if world == null or not is_instance_valid(world) or not world.has_method("get_height"):
		var edge := maxf(absf(pos.x), absf(pos.z))
		return clampf((edge - (Game.MAP_HALF_EXTENT - 90.0)) / 90.0, 0.0, 1.0)
	var by_district := world.has_method("get_district")
	if _is_sea(world, pos.x, pos.z, by_district):
		return 1.0
	for radius: float in SEA_PROBE_RADII:
		for i in 8:
			var a := TAU * float(i) / 8.0
			if _is_sea(world, pos.x + cos(a) * radius, pos.z + sin(a) * radius, by_district):
				return clampf(1.0 - radius / SEA_RANGE, 0.0, 1.0)
	return 0.0


## Open water at x,z: below sea level, or what the world calls the "ocean" district (this also
## counts the sea under piers and bridges, where get_height returns the deck).
func _is_sea(world: Node, x: float, z: float, by_district: bool) -> bool:
	if float(world.call("get_height", x, z)) < Game.WATER_LEVEL - 0.3:
		return true
	return by_district and str(world.call("get_district", Vector3(x, 0.0, z))) == "ocean"


func _sample() -> void:
	_context = _sample_context(SAMPLE_SEC)
	var targets := compute_targets(_context) if enabled else {}
	for layer: String in LAYERS:
		_target[layer] = float(targets.get(layer, 0.0))


func _on_district_changed(district: String) -> void:
	_district_hint = district
	_sample_t = 0.0


func _on_submerged(underwater: bool) -> void:
	_underwater = underwater
	_sample_t = 0.0


func _on_respawned(_position: Vector3) -> void:
	_underwater = false
	_sample_t = 0.0


# --- mixing -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_sample_t -= delta
	if _sample_t <= 0.0:
		_sample_t = SAMPLE_SEC
		_sample()
	_apply(delta)
	if spot_sounds and enabled:
		_spot_t -= delta
		if _spot_t <= 0.0:
			_spot_t = _rng.randf_range(7.0, 16.0)
			_play_spot()


func _apply(delta: float) -> void:
	var step := delta / FADE_SEC
	for layer: String in LAYERS:
		var target := float(_target[layer])
		var g := float(_gain[layer])
		if delta > 0.0:
			# rain and the underwater switch react faster than the slow district beds
			var k := 3.0 if layer == "underwater" else (1.6 if layer.begins_with("rain") else 1.0)
			if bool(_context.get("underwater", false)) or layer == "underwater":
				k = 4.0
			g = move_toward(g, target, step * k)
			_gain[layer] = g
		if g <= 0.001:
			var idle: AudioStreamPlayer = _players.get(layer, null)
			if idle != null and idle.playing:
				idle.stop()
			continue
		var p := _player_for(layer)
		if p == null:
			continue
		p.volume_db = float((LAYERS[layer] as Array)[1]) + linear_to_db(g)
		if not p.playing and not get_tree().paused:
			var length := p.stream.get_length() if p.stream != null else 0.0
			p.play(_rng.randf() * maxf(length - 0.1, 0.0))


func _player_for(layer: String) -> AudioStreamPlayer:
	if _players.has(layer):
		return _players[layer]
	if _missing.has(layer):
		return null
	var sound_id := str((LAYERS[layer] as Array)[0])
	if not Audio.has_sound(sound_id):
		_missing[layer] = true
		return null
	var p: AudioStreamPlayer = Audio.make_loop_player_2d(sound_id, "Ambience")
	p.name = "Bed_" + layer
	p.volume_db = -80.0
	_players[layer] = p
	return p


## One sparse animal call somewhere around the listener, chosen from the current context.
func _play_spot() -> void:
	if _context.is_empty() or bool(_context.get("underwater", false)):
		return
	var day := float(_context.get("daylight", 1.0))
	var rain := float(_context.get("rain", 0.0))
	var district := str(_context.get("district", ""))
	if rain > 0.5 or float(_context.get("altitude", 0.0)) > 40.0:
		return
	var options: Array[String] = []
	if day > 0.4 and float(_context.get("sea", 0.0)) > 0.3:
		options.append("animal_gull")
		options.append("animal_gull")
	if day > 0.4 and (district == "hill" or district == "residential" or district == "beach"):
		options.append("animal_bird")
	if district == "residential" or district == "industrial":
		options.append("animal_dog_bark")
	if options.is_empty():
		return
	var id := options[_rng.randi() % options.size()]
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(28.0, 60.0)
	var pos := _listener_position() + Vector3(cos(a) * r, _rng.randf_range(2.0, 14.0), sin(a) * r)
	Audio.play_at(id, pos, _rng.randf_range(-9.0, -4.0), _rng.randf_range(0.92, 1.08), 90.0, "Ambience")
