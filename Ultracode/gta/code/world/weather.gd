extends Node
## Autoload "Weather": weather state machine for Halcyon Bay (ENVIRONMENT module).
##
## Owns the five weather types, the smoothly blended parameters every other system reads, ground
## wetness, the automatic weather cycle and storm lightning timing. Presentation (sky, fog, rain
## particles, wet look, thunder) lives in the "environment" world system, which reads these
## values every frame - so set_weather() is visible immediately (it starts blending at once;
## pass 0 seconds or call snap_weather() for an instant change).
##
## Frozen contract (written by the lead, do not rename): TYPES, current, previous, auto_cycle,
## transition, cloud_cover, rain_intensity, fog_amount, wetness, wind_strength, lightning_flash,
## wind_direction, get_weather(), set_weather(), get_grip_multiplier(), get_visibility(),
## is_raining(), get_save_data(), load_save_data(). Everything else is an addition.

## A lightning bolt struck `distance` metres away; thunder should be heard after `delay` seconds.
signal lightning_strike(distance: float, delay: float)
## The blend towards `weather_id` has finished.
signal transition_finished(weather_id: String)

const TYPES: Array[String] = ["clear", "cloudy", "rain", "fog", "storm"]

## Target values of the blended parameters per weather type.
const PRESETS := {
	"clear": {"cloud_cover": 0.14, "rain_intensity": 0.0, "fog_amount": 0.0, "wind_strength": 0.20, "storminess": 0.0},
	"cloudy": {"cloud_cover": 0.66, "rain_intensity": 0.0, "fog_amount": 0.06, "wind_strength": 0.36, "storminess": 0.0},
	"rain": {"cloud_cover": 0.93, "rain_intensity": 0.62, "fog_amount": 0.24, "wind_strength": 0.52, "storminess": 0.0},
	"fog": {"cloud_cover": 0.50, "rain_intensity": 0.0, "fog_amount": 1.0, "wind_strength": 0.08, "storminess": 0.0},
	"storm": {"cloud_cover": 1.0, "rain_intensity": 1.0, "fog_amount": 0.36, "wind_strength": 1.0, "storminess": 1.0},
}
const DISPLAY_NAMES := {"clear": "Clear", "cloudy": "Cloudy", "rain": "Rain", "fog": "Fog", "storm": "Storm"}

## Automatic cycle: weights of the NEXT weather given the current one (rows need not sum to 1).
## Tuned so the bay is mostly clear / cloudy, rain is a regular visitor and storms are events.
const AUTO_WEIGHTS := {
	"clear": {"clear": 0.44, "cloudy": 0.40, "rain": 0.08, "fog": 0.07, "storm": 0.01},
	"cloudy": {"clear": 0.50, "cloudy": 0.14, "rain": 0.26, "fog": 0.05, "storm": 0.05},
	"rain": {"clear": 0.24, "cloudy": 0.48, "rain": 0.10, "fog": 0.06, "storm": 0.12},
	"fog": {"clear": 0.52, "cloudy": 0.40, "rain": 0.08, "fog": 0.0, "storm": 0.0},
	"storm": {"clear": 0.14, "cloudy": 0.50, "rain": 0.36, "fog": 0.0, "storm": 0.0},
}
## How long a weather type lasts before the next automatic roll, in GAME hours [min, max].
const AUTO_DURATION := {
	"clear": Vector2(2.5, 5.5), "cloudy": Vector2(2.0, 4.5), "rain": Vector2(1.2, 2.6),
	"fog": Vector2(1.0, 2.2), "storm": Vector2(0.8, 1.6),
}
const AUTO_TRANSITION_SEC := 40.0      ## real seconds an automatic change takes to blend
const WET_SECONDS := 24.0              ## real seconds of full rain until the ground is soaked
const DRY_SECONDS := 120.0             ## real seconds to dry completely in average conditions
const FOG_DAMPNESS := 0.22             ## wetness floor in dense fog
const LIGHTNING_MIN_GAP := 5.0         ## real seconds between strikes at full storm
const LIGHTNING_MAX_GAP := 15.0

var current: String = "clear"
var auto_cycle: bool = true       ## weather changes by itself every few in-game hours
var transition: float = 1.0       ## 0..1 blend from `previous` to `current`
var previous: String = "clear"

## Blended presentation/gameplay parameters (0..1 unless noted). Read-only for other systems.
var cloud_cover: float = 0.14
var rain_intensity: float = 0.0
var fog_amount: float = 0.0
var wetness: float = 0.0          ## rises while raining, dries slowly afterwards
var wind_strength: float = 0.2
var lightning_flash: float = 0.0  ## short pulses during storms
var wind_direction: Vector3 = Vector3(1, 0, 0.3).normalized()
## Addition: 0..1, only the "storm" type raises it (darker sky, lightning, rougher sea).
var storminess: float = 0.0

var _from := {"cloud_cover": 0.14, "rain_intensity": 0.0, "fog_amount": 0.0, "wind_strength": 0.2, "storminess": 0.0}
var _transition_sec: float = 8.0
var _rng := RandomNumberGenerator.new()
var _last_total_hours: float = 0.0
var _hours_until_change: float = 3.0
var _lightning_timer: float = 6.0
var _pulses: Array[Vector2] = []      ## pending after-flashes: x = seconds from now, y = strength
var _wind_phase: float = 0.0
var _wind_base_yaw: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = Game.rng.randi()
	_wind_base_yaw = atan2(wind_direction.z, wind_direction.x)
	_apply_blend(1.0)
	_hours_until_change = _roll_duration(current)
	_last_total_hours = WorldClock.total_hours
	if WorldClock.has_signal(&"save_loaded"):
		WorldClock.connect(&"save_loaded", _resync_clock)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):
			snap_weather(a.substr(10))
			auto_cycle = false
		elif a == "--no-weather-cycle":
			auto_cycle = false


func _process(delta: float) -> void:
	# Blending always runs (also while the tree is paused) so admin-menu changes are visible.
	if transition < 1.0:
		transition = minf(1.0, transition + delta / maxf(_transition_sec, 0.001))
		_apply_blend(transition)
		if transition >= 1.0:
			transition_finished.emit(current)
	if get_tree().paused:
		return
	_update_wetness(delta)
	_update_wind(delta)
	_update_lightning(delta)
	_update_auto_cycle()


# --- contract ---------------------------------------------------------------------------------

func get_weather() -> String:
	return current


## Change the weather. `transition_sec` is the blend time in real seconds (0 = instant).
func set_weather(id: String, transition_sec: float = 8.0) -> void:
	if not TYPES.has(id):
		return
	if id == current:
		if transition_sec <= 0.0 and transition < 1.0:
			transition = 1.0
			_apply_blend(1.0)
			transition_finished.emit(current)
		return
	previous = current
	current = id
	_capture_from()
	_transition_sec = maxf(transition_sec, 0.0)
	_hours_until_change = _roll_duration(current)
	if transition_sec <= 0.0:
		transition = 1.0
		_apply_blend(1.0)
	else:
		transition = 0.0
	EventBus.weather_changed.emit(current, previous)
	if transition >= 1.0:
		transition_finished.emit(current)


## Tire grip multiplier for vehicles (1.0 dry .. ~0.75 soaked).
func get_grip_multiplier() -> float:
	return lerpf(1.0, 0.75, clampf(wetness, 0.0, 1.0))


## Approximate sight distance in metres for AI vision (fog / heavy rain shorten it).
func get_visibility() -> float:
	return lerpf(160.0, 45.0, clampf(maxf(fog_amount, rain_intensity * 0.6), 0.0, 1.0))


func is_raining() -> bool:
	return rain_intensity > 0.15


func get_save_data() -> Dictionary:
	return {"current": current, "wetness": wetness, "auto_cycle": auto_cycle,
		"hours_until_change": _hours_until_change}


func load_save_data(d: Dictionary) -> void:
	auto_cycle = bool(d.get("auto_cycle", true))
	var id := str(d.get("current", "clear"))
	if not TYPES.has(id):
		id = "clear"
	snap_weather(id, clampf(float(d.get("wetness", 0.0)), 0.0, 1.0))
	_hours_until_change = maxf(0.05, float(d.get("hours_until_change", _hours_until_change)))
	# The clock's total_hours counter is restored by the same load: that jump is not elapsed
	# game time, so it must neither dry the ground nor trigger the automatic cycle.
	_resync_clock()


# --- additions --------------------------------------------------------------------------------

## Instant change including the ground state. `wetness_override` < 0 picks a matching wetness
## (soaked for rain / storm, damp for fog, dry otherwise). Used by loading, tests and photo tools.
func snap_weather(id: String, wetness_override: float = -1.0) -> void:
	if not TYPES.has(id):
		return
	if id != current:
		set_weather(id, 0.0)
	else:
		transition = 1.0
		_apply_blend(1.0)
	if wetness_override >= 0.0:
		wetness = clampf(wetness_override, 0.0, 1.0)
	elif rain_intensity > 0.05:
		wetness = 1.0
	else:
		wetness = fog_amount * FOG_DAMPNESS
	lightning_flash = 0.0
	_pulses.clear()


## Pretty name for UI ("Clear", "Storm" ...).
func get_display_name(id: String = "") -> String:
	var key := current if id == "" else id
	return str(DISPLAY_NAMES.get(key, key.capitalize()))


## Wind as a vector: direction * strength (the value of the global shader uniform `gta_wind`).
func get_wind_vector() -> Vector3:
	return wind_direction * wind_strength


func get_storminess() -> float:
	return storminess


## True while a blend between two weather types is running.
func is_transitioning() -> bool:
	return transition < 1.0


## Game hours until the automatic cycle rolls again (meaningful while auto_cycle is on).
func get_hours_until_change() -> float:
	return _hours_until_change


func set_auto_cycle(on: bool) -> void:
	auto_cycle = on


## Fire one lightning bolt now (admin menu / tests). `distance` < 0 picks a random distance.
func trigger_lightning(distance: float = -1.0) -> void:
	var dist := distance if distance >= 0.0 else _rng.randf_range(250.0, 2400.0)
	var strength := clampf(1.15 - dist / 3200.0, 0.45, 1.0)
	lightning_flash = maxf(lightning_flash, strength)
	_pulses.clear()
	var t := _rng.randf_range(0.07, 0.13)
	_pulses.append(Vector2(t, strength * _rng.randf_range(0.5, 0.9)))
	if _rng.randf() < 0.6:
		_pulses.append(Vector2(t + _rng.randf_range(0.09, 0.22), strength * _rng.randf_range(0.3, 0.7)))
	lightning_strike.emit(dist, dist / 343.0)


## Picks the weather the automatic cycle would choose next (does not apply it).
func roll_next_weather() -> String:
	var weights: Dictionary = AUTO_WEIGHTS.get(current, AUTO_WEIGHTS["clear"])
	var h := WorldClock.hour
	var total := 0.0
	var w_list: Array[float] = []
	for id in TYPES:
		var w := float(weights.get(id, 0.0))
		if id == "fog":
			# Fog belongs to the early morning; it is rare at other times.
			w *= 3.2 if (h >= 3.5 and h <= 8.5) else 0.35
		w_list.append(w)
		total += w
	if total <= 0.0:
		return current
	var pick := _rng.randf() * total
	for i in TYPES.size():
		pick -= w_list[i]
		if pick <= 0.0:
			return TYPES[i]
	return current


# --- internals --------------------------------------------------------------------------------

## Forget the game time that "passed" since the last frame (called when a save was loaded, in
## whichever order the clock and the weather are restored).
func _resync_clock() -> void:
	_last_total_hours = WorldClock.total_hours


func _capture_from() -> void:
	_from["cloud_cover"] = cloud_cover
	_from["rain_intensity"] = rain_intensity
	_from["fog_amount"] = fog_amount
	_from["wind_strength"] = wind_strength
	_from["storminess"] = storminess


func _apply_blend(t: float) -> void:
	var to: Dictionary = PRESETS[current]
	var w := smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	cloud_cover = lerpf(float(_from["cloud_cover"]), float(to["cloud_cover"]), w)
	fog_amount = lerpf(float(_from["fog_amount"]), float(to["fog_amount"]), w)
	wind_strength = lerpf(float(_from["wind_strength"]), float(to["wind_strength"]), w)
	storminess = lerpf(float(_from["storminess"]), float(to["storminess"]), w)
	# Rain starts only once the clouds have closed in and stops before they open up again.
	var rain_from := float(_from["rain_intensity"])
	var rain_to := float(to["rain_intensity"])
	var rw := smoothstep(0.25, 1.0, t) if rain_to > rain_from else smoothstep(0.0, 0.7, t)
	rain_intensity = lerpf(rain_from, rain_to, rw)


func _time_factor() -> float:
	# Ground state follows game time loosely: a faster clock dries / soaks the streets faster.
	if WorldClock.paused:
		return 1.0
	return clampf(WorldClock.rate / WorldClock.GAME_SECONDS_PER_REAL_SECOND, 0.25, 8.0)


func _update_wetness(delta: float) -> void:
	var dt := delta * _time_factor()
	if rain_intensity > 0.05:
		wetness = minf(1.0, wetness + pow(rain_intensity, 0.7) * dt / WET_SECONDS)
	else:
		var damp_floor := fog_amount * FOG_DAMPNESS
		if wetness > damp_floor:
			# Sun and wind dry the streets faster; a cloudy night keeps them wet for longer.
			var sun := WorldClock.get_daylight() * (1.0 - cloud_cover)
			var speed := 0.55 + sun * 0.9 + wind_strength * 0.35
			wetness = maxf(damp_floor, wetness - speed * dt / DRY_SECONDS)
		elif wetness < damp_floor:
			wetness = minf(damp_floor, wetness + dt / (WET_SECONDS * 3.0))


func _update_wind(delta: float) -> void:
	# The wind slowly veers around its base direction (+-25 degrees), a little faster in storms.
	_wind_phase += delta * (0.02 + 0.03 * wind_strength)
	var yaw := _wind_base_yaw + sin(_wind_phase) * 0.44 + sin(_wind_phase * 2.7 + 1.3) * 0.12
	wind_direction = Vector3(cos(yaw), 0.0, sin(yaw))


func _update_lightning(delta: float) -> void:
	if lightning_flash > 0.0:
		lightning_flash = maxf(0.0, lightning_flash * exp(-delta * 9.0) - delta * 0.35)
	if not _pulses.is_empty():
		var i := _pulses.size() - 1
		while i >= 0:
			var p := _pulses[i]
			p.x -= delta
			if p.x <= 0.0:
				lightning_flash = maxf(lightning_flash, p.y)
				_pulses.remove_at(i)
			else:
				_pulses[i] = p
			i -= 1
	if storminess < 0.35:
		_lightning_timer = minf(_lightning_timer, LIGHTNING_MAX_GAP)
		return
	_lightning_timer -= delta * storminess
	if _lightning_timer <= 0.0:
		_lightning_timer = _rng.randf_range(LIGHTNING_MIN_GAP, LIGHTNING_MAX_GAP)
		trigger_lightning()


func _update_auto_cycle() -> void:
	var now := WorldClock.total_hours
	var passed := now - _last_total_hours
	_last_total_hours = now
	if passed <= 0.0:
		return
	if passed > 0.25:
		_simulate_skip(passed)
	if not auto_cycle:
		return
	_hours_until_change -= passed
	if _hours_until_change > 0.0:
		return
	var next_id := roll_next_weather()
	if next_id == current:
		_hours_until_change = _roll_duration(current)
		return
	# After a time skip (sleeping) the new weather is simply there; otherwise blend slowly.
	set_weather(next_id, 0.0 if passed > 0.25 else AUTO_TRANSITION_SEC)
	if passed > 0.25:
		wetness = 1.0 if rain_intensity > 0.05 else wetness


## Time was skipped (advance_hours): let the ground dry / soak for the skipped time.
func _simulate_skip(hours: float) -> void:
	var seconds := hours * 3600.0 / WorldClock.GAME_SECONDS_PER_REAL_SECOND
	if rain_intensity > 0.05:
		wetness = minf(1.0, wetness + pow(rain_intensity, 0.7) * seconds / WET_SECONDS)
	else:
		wetness = maxf(fog_amount * FOG_DAMPNESS, wetness - seconds / DRY_SECONDS)


func _roll_duration(id: String) -> float:
	var r: Vector2 = AUTO_DURATION.get(id, Vector2(2.0, 5.0))
	return _rng.randf_range(r.x, r.y)
