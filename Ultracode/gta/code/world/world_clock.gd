extends Node
## Autoload "WorldClock": time of day for Halcyon Bay (ENVIRONMENT module).
##
## The clock only owns TIME. Everything visible (sun, sky, fog, lamps) is derived from it every
## frame by the "environment" world system, so `set_hour()` changes the look immediately.
##
## Frozen contract (written by the lead, do not rename): hour, day, rate, paused, get_hour(),
## set_hour(), advance_hours(), get_phase(), is_night(), get_daylight(), get_time_string(),
## get_save_data(), load_save_data(). Everything else here is an addition.
##
## Time flows with the scene tree: it stops while the tree is paused and follows
## Engine.time_scale (slow motion slows the day too).

## Emitted when the time is changed discontinuously (set_hour, advance_hours, load).
## Natural flow never emits this. Presentation code can use it to skip smoothing.
signal time_jumped(hour: float)
## Emitted once when the day counter increases.
signal day_changed(day: int)
## Emitted at the end of load_save_data(). `total_hours` may have jumped by any amount in either
## direction: that is a restored counter, NOT game time that has passed (Weather listens to this
## so a loaded game does not look like a huge time skip).
signal save_loaded()

const GAME_SECONDS_PER_REAL_SECOND := 60.0   ## default: 24 in-game hours = 24 real minutes
const DEFAULT_START_HOUR := 9.5

## Phase boundaries in hours (see get_phase()).
const DAWN_START := 5.0
const DAY_START := 7.0
const DUSK_START := 18.5
const NIGHT_START := 20.5
const PHASES: Array[String] = ["dawn", "day", "dusk", "night"]

## Astronomy used by the sky / sun (the visual sun crosses the horizon at these hours).
const SUNRISE_HOUR := 5.6
const SUNSET_HOUR := 19.9
const SUN_TILT_DEG := 28.0          ## the sun arc leans to the south (+Z) by this angle
const MOON_TILT_DEG := 38.0
const MOONRISE_HOUR := 19.3
const MOONSET_HOUR := 6.2

var hour: float = DEFAULT_START_HOUR   ## 0..24
var day: int = 1
var rate: float = GAME_SECONDS_PER_REAL_SECOND   ## game seconds per real second
var paused: bool = false
## Monotonic count of game hours that have really passed (natural flow + advance_hours()).
## set_hour() does NOT change it, so systems can use it for "every few game hours" timers.
var total_hours: float = 0.0

var _last_minute: int = -1
var _last_phase: String = ""


func _ready() -> void:
	_last_phase = get_phase()
	_last_minute = int(hour * 60.0)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--hour="):
			hour = fposmod(float(a.substr(7)), 24.0)
			_last_phase = get_phase()
			_last_minute = int(hour * 60.0)
		elif a.begins_with("--clock-rate="):
			rate = maxf(0.0, float(a.substr(13)))
		elif a == "--freeze-time":
			paused = true


func _process(delta: float) -> void:
	if paused or not Game.is_ready:
		return
	var step := delta * rate / 3600.0
	if step <= 0.0:
		return
	hour += step
	total_hours += step
	while hour >= 24.0:
		hour -= 24.0
		day += 1
		day_changed.emit(day)
	_emit_changes(false)


func _emit_changes(force_time: bool) -> void:
	var minute := int(hour * 60.0)
	if force_time or minute != _last_minute:
		_last_minute = minute
		EventBus.time_changed.emit(hour)
	var phase := get_phase()
	if phase != _last_phase:
		_last_phase = phase
		EventBus.day_phase_changed.emit(phase)


# --- contract ---------------------------------------------------------------------------------

func get_hour() -> float:
	return hour


## Jump to an hour of the current day (admin menu, tests). The look updates in the same frame.
func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	_emit_changes(true)
	time_jumped.emit(hour)


## Skip forward (sleeping at the safehouse, taxi skip). Rolls the day counter over.
func advance_hours(h: float) -> void:
	var total := hour + h
	var day_delta := int(floor(total / 24.0))
	if h > 0.0:
		total_hours += h
	if day_delta != 0:
		day = maxi(1, day + day_delta)
		day_changed.emit(day)
	set_hour(total)


## "dawn" 5-7, "day" 7-18.5, "dusk" 18.5-20.5, "night" otherwise.
func get_phase() -> String:
	return phase_at(hour)


func is_night() -> bool:
	return hour < 5.5 or hour >= 20.0


## 0 = deep night, 1 = full daylight (smooth). Drives street lights, window glow, AI sight range.
func get_daylight() -> float:
	return daylight_at(hour)


func get_time_string() -> String:
	var total_minutes := int(floor(hour * 60.0 + 0.0001)) % 1440
	@warning_ignore("integer_division")
	return "%02d:%02d" % [total_minutes / 60, total_minutes % 60]


func get_save_data() -> Dictionary:
	return {"hour": hour, "day": day, "total_hours": total_hours}


func load_save_data(d: Dictionary) -> void:
	day = maxi(1, int(d.get("day", 1)))
	total_hours = maxf(0.0, float(d.get("total_hours", total_hours)))
	set_hour(float(d.get("hour", DEFAULT_START_HOUR)))
	save_loaded.emit()


# --- additions --------------------------------------------------------------------------------

## Phase name for an arbitrary hour (pure function).
func phase_at(h: float) -> String:
	if h >= DAWN_START and h < DAY_START:
		return "dawn"
	if h >= DAY_START and h < DUSK_START:
		return "day"
	if h >= DUSK_START and h < NIGHT_START:
		return "dusk"
	return "night"


## Daylight factor for an arbitrary hour (pure function, smooth, 0..1).
func daylight_at(h: float) -> float:
	var a := smoothstep(5.0, 7.0, h)
	var b := 1.0 - smoothstep(18.75, 20.5, h)
	return clampf(minf(a, b), 0.0, 1.0)


## 1 - daylight. The value written to the global shader uniform `gta_night`.
func get_night_factor() -> float:
	return 1.0 - get_daylight()


func is_day() -> bool:
	return not is_night()


func get_minute() -> int:
	return int(floor(fposmod(hour, 1.0) * 60.0 + 0.0001)) % 60


func get_day() -> int:
	return day


## 0..1 position inside the current day (0 = midnight).
func get_day_fraction() -> float:
	return hour / 24.0


## Real minutes one full game day takes at the current rate (INF when the clock stands still).
func get_day_length_minutes() -> float:
	if rate <= 0.0:
		return INF
	return 86400.0 / rate / 60.0


## Convenience for settings / admin: "one game day lasts N real minutes".
func set_day_length_minutes(real_minutes: float) -> void:
	rate = 86400.0 / (maxf(real_minutes, 0.05) * 60.0)


func set_rate(game_seconds_per_real_second: float) -> void:
	rate = maxf(0.0, game_seconds_per_real_second)


func set_paused(on: bool) -> void:
	paused = on


## Unit vector pointing FROM the world TO the sun for the current hour.
## The sun rises in the east (+X), culminates in the south (+Z) and sets in the west (-X).
## Y is negative while the sun is below the horizon.
func get_sun_direction() -> Vector3:
	return sun_direction_at(hour)


## Sine of the sun elevation (-1..1); > 0 while the sun is above the horizon.
func get_sun_elevation() -> float:
	return sun_direction_at(hour).y


func sun_direction_at(h: float) -> Vector3:
	var theta: float
	if h >= SUNRISE_HOUR and h < SUNSET_HOUR:
		theta = (h - SUNRISE_HOUR) / (SUNSET_HOUR - SUNRISE_HOUR) * PI
	else:
		var night_len := 24.0 - SUNSET_HOUR + SUNRISE_HOUR
		var since_set := fposmod(h - SUNSET_HOUR, 24.0)
		theta = PI + since_set / night_len * PI
	var tilt := deg_to_rad(SUN_TILT_DEG)
	return Vector3(cos(theta), sin(theta) * cos(tilt), sin(theta) * sin(tilt)).normalized()


## Unit vector pointing to the moon. Y > 0 between MOONRISE_HOUR and MOONSET_HOUR.
func get_moon_direction() -> Vector3:
	return moon_direction_at(hour)


func moon_direction_at(h: float) -> Vector3:
	var up_len := 24.0 - MOONRISE_HOUR + MOONSET_HOUR
	var since_rise := fposmod(h - MOONRISE_HOUR, 24.0)
	var theta: float
	if since_rise < up_len:
		theta = since_rise / up_len * PI
	else:
		theta = PI + (since_rise - up_len) / (24.0 - up_len) * PI
	var tilt := deg_to_rad(MOON_TILT_DEG)
	# The moon arc leans the other way (slightly north) so moon shadows differ from sun shadows.
	return Vector3(cos(theta) * 0.92 + 0.08, sin(theta) * cos(tilt), -sin(theta) * sin(tilt) * 0.6).normalized()
