extends Node
## Autoload "Wanted": 0-5 star wanted / pursuit state machine (spec 18 / 18A, ARCHITECTURE 6.9,
## ARCHITECTURE_WAVE2 W2.3). Owned by the WANTED programmer; the police module (units, brains,
## dispatcher) builds on this API. Full design: docs/WANTED.md. Tables: wanted_config.gd.
##
##   * Crimes add HEAT; heat thresholds give the star level (+ per-crime minimum stars).
##   * A crime only becomes KNOWN when (a) opts.force / opts.direct_police_witness, (b) police saw
##     the player within SIGHTING_WINDOW of it (police_sighting), (c) a civilian finished calling it
##     in (report_witnessed), or (d) a LOUD crime (gunfire, explosion) was heard by people nearby,
##     who call it in after 6-10 s. Everything else stays PENDING and expires.
##   * NONE -> PURSUIT while police keep sighting the player -> SEARCH after the level's grace
##     without sightings (stars flash; search circle around last_known_position grows) -> cleared
##     ("escaped") after the level's escape time spent unseen. Any sighting resumes PURSUIT.
##   * A pursuit that drags on escalates slowly ("resisting"), max 3 stars without violence.
##   * Vehicle / appearance changes while unseen shorten the remaining escape time a little and
##     raise get_recognition_delay() (officer brains wait that long before a sighting counts).
##
## Every public name of the lead's stub is kept (frozen contract); timers run on game time
## (pause / Engine.time_scale) multiplied by debug_time_scale. Not persisted in saves.

const Config := preload("res://gta/code/police/wanted_config.gd")

enum State { NONE, PURSUIT, SEARCH }

## Heat added per reported crime (stars come from HEAT_THRESHOLDS). Source: wanted_config.gd.
const CRIME_HEAT := Config.CRIME_HEAT
## heat needed for star 1..5
const HEAT_THRESHOLDS: Array[float] = Config.HEAT_THRESHOLDS
## seconds unseen in SEARCH needed to lose the wanted level, per star 1..5 (outside the search circle)
const ESCAPE_SECONDS: Array[float] = Config.ESCAPE_SECONDS

const REC_PENDING := 0
const REC_KNOWN := 1
const REC_EXPIRED := 2

## A crime became known to the police. source: "police", "forced", "auto", "witness",
## "indirect", "resisting".
signal crime_became_known(crime_id: String, position: Vector3, source: String)
## A pending crime was never reported and is forgotten.
signal crime_expired(crime_id: String, position: Vector3)
## A vehicle / appearance change while unseen paid off. kind: "vehicle" | "appearance".
signal disguise_applied(kind: String, escape_progress: float, recognition_delay: float)

var level: int = 0
var state: int = State.NONE
var heat: float = 0.0
var last_known_position: Vector3 = Vector3.ZERO
var last_known_velocity: Vector3 = Vector3.ZERO
var seconds_since_seen: float = 9999.0
var search_radius: float = 60.0
var escape_progress: float = 0.0          ## 0..1 while in SEARCH
var player_visible_to_police: bool = false
var identified_vehicle: Node3D = null     ## vehicle police last saw the player in (null = on foot / unknown)
## admin toggle ("never wanted"): false drops pending crimes and clears the current level.
var enabled: bool = true:
	set(value):
		if enabled == value:
			return
		enabled = value
		if not value:
			if level > 0:
				clear("cheat")
			else:
				_records.clear()

# --- W2.3 additions + extras --------------------------------------------------------------------
var time_in_state: float = 0.0            ## seconds (scaled) since the last state change
var time_since_last_crime: float = 9999.0 ## seconds since the player last committed a reported crime
var time_since_player_attack: float = 9999.0  ## since the player fired / hurt someone / violent crime
var debug_time_scale: float = 1.0         ## tests / admin: multiplies every Wanted timer
var search_center: Vector3 = Vector3.ZERO ## SEARCH: last_known_position drifted along the last velocity
var episode_violent: bool = false         ## a violent crime is known in this wanted episode (lifts the 3-star cap)
var stingers_enabled: bool = true         ## see _level_stinger: never doubles the Audio EventBus glue
var last_clear_reason: String = ""
var crimes_known_total: int = 0           ## statistics (session)

var _clock: float = 0.0                   ## scaled game time of this autoload
var _last_sighting_clock: float = -1.0e9
var _search_time: float = 0.0             ## time since the search was (re)centred
var _resist_timer: float = 0.0
var _records: Array[CrimeRecord] = []
var _repeat_count: Dictionary = {}        ## crime id -> recent known repeats (damping)
var _repeat_clock: Dictionary = {}        ## crime id -> clock of the last known repeat
var _identified_key: int = -1             ## -1 never seen this episode, 0 on foot, else vehicle instance id
var _vehicle_credits: int = 0
var _appearance_credits: int = 0
var _credited_keys: PackedInt64Array = PackedInt64Array()
var _recognition_bonus: float = 0.0
var _last_noise_clock: float = -1.0e9
var _last_noise_pos: Vector3 = Vector3.ZERO
var _last_noise_radius: float = 0.0
var _near_police: bool = false
var _near_police_timer: float = 0.0
var _emitted_level: int = 0
var _emitted_state: int = State.NONE
var _busting: bool = false
var _last_clear_clock: float = -1.0e9     ## when an episode last ended by an arrest or the player's death
var _level_cfg: Array[Dictionary] = []


## One crime the player committed (pending, known or expired). Kept for de-duplication.
class CrimeRecord extends RefCounted:
	var id: String = ""
	var position: Vector3 = Vector3.ZERO
	var clock: float = 0.0                ## when it happened (Wanted._clock)
	var status: int = 0                   ## REC_PENDING / REC_KNOWN / REC_EXPIRED
	var expires: float = 0.0
	var heat: float = 0.0                 ## base heat x severity
	var loud: float = 0.0                 ## earshot radius (0 = silent)
	var listeners: int = 0
	var due: float = -1.0                 ## clock of the indirect report (-1 none)
	var events: int = 1                   ## merged repeats (loud crimes)
	var grace_used: bool = false
	var source: String = ""
	var victim: Node = null


func _ready() -> void:
	_build_level_cfg()
	EventBus.noise_emitted.connect(_on_noise_emitted)
	EventBus.crime_witnessed.connect(_on_crime_witnessed)
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.hit_confirmed.connect(_on_hit_confirmed)
	EventBus.npc_injured.connect(_on_npc_injured)
	EventBus.player_entered_vehicle.connect(_on_player_entered_vehicle)
	EventBus.player_exited_vehicle.connect(_on_player_exited_vehicle)
	EventBus.player_appearance_changed.connect(_on_player_appearance_changed)
	EventBus.player_died.connect(_on_player_died)


func is_wanted() -> bool:
	return level > 0


func is_in_pursuit() -> bool:
	return level > 0 and state == State.PURSUIT


func is_searching() -> bool:
	return level > 0 and state == State.SEARCH


# --- crimes ------------------------------------------------------------------------------------

## Report a crime by the PLAYER. Not every call raises the level: unless
## opts.direct_police_witness is true, the implementation runs witness / report-delay logic.
## opts: {"instigator": Node, "victim": Node, "direct_police_witness": bool, "severity": float,
##        "force": bool (skip witness logic)}
func report_crime(crime_id: String, position: Vector3, opts: Dictionary = {}) -> void:
	if not enabled:
		return
	EventBus.crime_committed.emit(crime_id, position, opts.get("instigator", null))
	time_since_last_crime = 0.0
	var def := Config.crime(crime_id)
	if bool(def["violent"]):
		time_since_player_attack = 0.0
	var victim: Node = null
	var v: Variant = opts.get("victim", null)
	if v is Node and is_instance_valid(v):
		victim = v as Node
	var source := ""
	if bool(opts.get("force", false)):
		source = "forced"
	elif bool(opts.get("direct_police_witness", false)):
		source = "police"
	elif victim != null and victim.is_in_group("police") and victim.get("is_dead") != true:
		source = "police"               # the officer who got hurt saw who did it
	elif bool(def["auto_known"]):
		source = "auto"                 # officer down on the radio / cruiser transponder
	elif _clock - _last_sighting_clock <= Config.SIGHTING_WINDOW:
		source = "police"               # police had eyes on the player right now
	var base := Config.crime_heat(crime_id) * maxf(float(opts.get("severity", 1.0)), 0.0)
	var loud := float(def["loud"])
	if source == "" and loud > 0.0 and _merge_loud(crime_id, position):
		return
	var rec := _new_record(crime_id, position, base, victim)
	if source != "":
		_make_known(rec, source, position)
		return
	if loud > 0.0:
		rec.loud = loud
		if _clock - _last_noise_clock <= Config.NOISE_MATCH_TIME \
				and _last_noise_pos.distance_to(position) <= Config.NOISE_MATCH_DIST:
			rec.loud = _last_noise_radius
		_schedule_indirect(rec)


## A civilian finished calling a crime in (AI witness flow, W2.3).
func report_witnessed(crime_id: String, position: Vector3, witness: Node) -> void:
	if not enabled:
		return
	if witness != null and is_instance_valid(witness) and witness.get("is_dead") == true:
		return
	var rec := _find_record(crime_id, position)
	if rec == null:
		# a call about something from before the arrest / death (the clear dropped its records):
		# that episode is over, the late caller does not start a new one (review fix)
		if _clock - _last_clear_clock < Config.PENDING_TTL + Config.WITNESS_CALL_GRACE:
			return
		# an observation that never went through report_crime (the AI saw it itself)
		rec = _new_record(crime_id, position, Config.crime_heat(crime_id), null)
		_make_known(rec, "witness", position)
		return
	if rec.status == REC_PENDING:
		_make_known(rec, "witness", rec.position)
	# REC_KNOWN: already reported (duplicate call); REC_EXPIRED: the call came too late


## Police units call this whenever they have confirmed line of sight on the player (also while the
## player is not wanted: a crime within SIGHTING_WINDOW of a sighting is known immediately).
## During SEARCH officer brains wait get_recognition_delay() of continuous sight before calling.
func police_sighting(_observer: Node, position: Vector3) -> void:
	if not enabled:
		return
	_note_seen(position)
	_promote_recent_pending()
	if level > 0 and state != State.PURSUIT:
		_resume_pursuit()


## Dispatcher / admin: the police are on the player right now (gives 1 star when not wanted).
func force_pursuit(position: Vector3) -> void:
	if not enabled:
		return
	if level <= 0:
		heat = maxf(heat, Config.heat_for_level(1))
		level = 1
	_note_seen(position)
	if state != State.PURSUIT:
		_resume_pursuit()
	else:
		_flush_signals()


## The police module calls this when the player attacks officers in a way no crime covers
## (e.g. aiming at them). Blocks arrests for a moment and authorizes lethal force.
func note_player_attack() -> void:
	time_since_player_attack = 0.0


# --- level control -----------------------------------------------------------------------------

func set_level(new_level: int, _reason: String = "cheat") -> void:
	new_level = clampi(new_level, 0, 5)
	if new_level == 0:
		clear(_reason)
		return
	if not enabled:
		return
	heat = Config.heat_for_level(new_level)
	level = new_level
	if state == State.NONE:
		_note_seen(Game.get_player_position())
		_set_state_raw(State.PURSUIT)
	_flush_signals()


func add_stars(n: int) -> void:
	set_level(level + n, "script")


## Ends the wanted episode. reason: "escaped", "busted", "died", "cheat", "load", ...
func clear(reason: String = "cheat") -> void:
	var was := level
	if was > 0 and (reason == "busted" or reason == "died"):
		_last_clear_clock = _clock
	_reset_episode(reason != "escaped")
	level = 0
	_set_state_raw(State.NONE)
	_flush_signals()
	if was > 0:
		last_clear_reason = reason
		_clear_stinger(reason)
		EventBus.wanted_cleared.emit(reason)


## Arrest completed (police module): EventBus.player_busted, then clear("busted").
func bust() -> void:
	if _busting or level <= 0:
		return
	_busting = true
	EventBus.player_busted.emit()
	clear("busted")
	_busting = false


## On foot or stopped, alive, not swimming, not aiming a weapon, no attack for ARREST_CALM_SECONDS.
func is_player_arrestable() -> bool:
	if level <= 0 or not enabled or not Game.has_player():
		return false
	var p := Game.player
	if p.get("is_dead") == true or p.get("is_swimming") == true:
		return false
	if time_since_player_attack < Config.ARREST_CALM_SECONDS:
		return false
	var veh := Game.get_player_vehicle()
	if veh is RigidBody3D and (veh as RigidBody3D).linear_velocity.length() > Config.ARREST_MAX_VEHICLE_SPEED:
		return false
	if _player_aiming_weapon():
		return false
	return true


## Officers may shoot to kill: the level's "lethal" flag, or at 1 star while the player is armed +
## aiming or attacked within LETHAL_AFTER_ATTACK_SECONDS.
func is_lethal_force_authorized() -> bool:
	if level <= 0:
		return false
	if bool(get_level_config(level)["lethal"]):
		return true
	return time_since_player_attack < Config.LETHAL_AFTER_ATTACK_SECONDS or _player_aiming_weapon()


# --- disguise ----------------------------------------------------------------------------------

## The player swapped vehicle (null = left the vehicle on foot) while unseen: a modest benefit,
## once per distinct vehicle and at most MAX_VEHICLE_CREDITS per unseen episode. Never clears.
## Called automatically from EventBus.player_entered_vehicle / player_exited_vehicle; explicit
## calls for the same vehicle are ignored.
func note_vehicle_change(vehicle: Node3D) -> void:
	if not _can_disguise():
		return
	var key := 0
	if vehicle != null and is_instance_valid(vehicle):
		key = vehicle.get_instance_id()
	if key == _identified_key or _credited_keys.has(key):
		return
	if _vehicle_credits >= Config.MAX_VEHICLE_CREDITS:
		return
	_vehicle_credits += 1
	_credited_keys.append(key)
	_apply_disguise("vehicle", Config.VEHICLE_CHANGE_CUT, Config.RECOGNITION_PER_VEHICLE)


## Wardrobe / barber change while unseen (also called from EventBus.player_appearance_changed).
func note_appearance_change() -> void:
	if not _can_disguise():
		return
	if _appearance_credits >= Config.MAX_APPEARANCE_CREDITS:
		return
	_appearance_credits += 1
	_apply_disguise("appearance", Config.APPEARANCE_CHANGE_CUT, Config.RECOGNITION_APPEARANCE)


## Seconds an officer must keep the player in continuous sight before calling police_sighting.
## 0 while the police are tracking the player (or not wanted); small during SEARCH, larger after
## a vehicle / appearance change while unseen.
func get_recognition_delay() -> float:
	if level <= 0 or player_visible_to_police:
		return 0.0
	var base := Config.RECOGNITION_BASE_SEARCH if state == State.SEARCH else 0.0
	return minf(base + _recognition_bonus, Config.RECOGNITION_MAX)


# --- queries -----------------------------------------------------------------------------------

## {"officers", "cruisers", "swat_vans", "heli", "roadblocks", "lethal", "respawn_interval",
##  "search_radius", "escape_seconds"} + extras (see wanted_config.gd). Shared: do not modify.
func get_level_config(lvl: int) -> Dictionary:
	if _level_cfg.is_empty():
		_build_level_cfg()
	return _level_cfg[clampi(lvl, 0, _level_cfg.size() - 1)]


## {"id", "heat", "min_level", "violent", "loud", "damp", "auto_known"} (new dictionary).
func get_crime_def(crime_id: String) -> Dictionary:
	var d := Config.crime(crime_id).duplicate()
	d["id"] = crime_id
	d["heat"] = Config.crime_heat(crime_id)
	return d


## Seconds of unseen SEARCH needed to escape at the current level.
func get_escape_time_required() -> float:
	return Config.escape_seconds(clampi(level, 1, 5))


## Remaining unseen seconds (outside the search circle) until the level is lost.
func get_escape_time_remaining() -> float:
	if level <= 0:
		return 0.0
	return (1.0 - escape_progress) * get_escape_time_required()


func get_search_center() -> Vector3:
	return search_center


## People within `radius` who would hear / report something (peds system count when it offers
## one, else a group scan) + police officers + occupied AI vehicles. Not for per-frame use.
func count_listeners_near(position: Vector3, radius: float) -> int:
	var n := 0
	var peds := Game.get_system("peds")
	if peds != null and peds.has_method("count_near"):
		n += int(peds.call("count_near", position, radius))
	elif peds != null and peds.has_method("count_peds_near"):
		n += int(peds.call("count_peds_near", position, radius))
	else:
		n += _count_group("ped", position, radius, false)
	n += _count_group("police", position, radius, false)
	n += _count_group("vehicle", position, radius, true)
	return n


func get_pending_count() -> int:
	var n := 0
	for r in _records:
		if r.status == REC_PENDING:
			n += 1
	return n


## Debug / admin snapshot of the crime records (new array of dictionaries).
func get_crime_records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _records:
		out.append({"id": r.id, "position": r.position, "age": _clock - r.clock,
				"status": ["pending", "known", "expired"][r.status], "listeners": r.listeners, "loud": r.loud,
				"due_in": (r.due - _clock) if r.due >= 0.0 else -1.0, "events": r.events, "source": r.source})
	return out


func get_debug_info() -> Dictionary:
	return {
		"level": level, "state": ["NONE", "PURSUIT", "SEARCH"][clampi(state, 0, 2)], "heat": heat,
		"time_in_state": time_in_state, "seconds_since_seen": seconds_since_seen,
		"visible": player_visible_to_police, "escape_progress": escape_progress,
		"escape_remaining": get_escape_time_remaining(), "search_radius": search_radius,
		"search_center": search_center, "recognition_delay": get_recognition_delay(),
		"pending": get_pending_count(), "violent": episode_violent,
		"arrestable": is_player_arrestable(), "lethal": is_lethal_force_authorized(),
		"time_since_last_crime": time_since_last_crime, "debug_time_scale": debug_time_scale,
	}


func set_enabled(on: bool) -> void:
	enabled = on


## Respawn system hook: no chase state survives a respawn.
func reset_for_respawn() -> void:
	if level > 0:
		clear("died")
	else:
		_reset_episode(true)


func get_save_data() -> Dictionary:
	return {}   ## wanted level is intentionally not persisted


func load_save_data(_d: Dictionary) -> void:
	clear("load")


# --- update ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var dt := delta * maxf(debug_time_scale, 0.0)
	if dt <= 0.0:
		return
	_clock += dt
	time_in_state += dt
	time_since_last_crime = minf(time_since_last_crime + dt, 1.0e6)
	time_since_player_attack = minf(time_since_player_attack + dt, 1.0e6)
	seconds_since_seen = minf(seconds_since_seen + dt, 1.0e6)
	if player_visible_to_police and _clock - _last_sighting_clock > Config.VISIBLE_TIMEOUT:
		player_visible_to_police = false
	if not _records.is_empty():
		_update_records()
	if level <= 0:
		return
	if Game.has_player() and Game.player.get("is_dead") == true:
		return                          # frozen until the respawn flow clears us
	if state == State.PURSUIT:
		_update_pursuit(dt)
	elif state == State.SEARCH:
		_update_search(dt, delta)
	else:
		_set_state_raw(State.PURSUIT)   # level without a state (external assignment)
		_flush_signals()


func _update_pursuit(dt: float) -> void:
	var cfg := get_level_config(level)
	if seconds_since_seen >= float(cfg["lost_contact_grace"]):
		var drift := Vector3(last_known_velocity.x, 0.0, last_known_velocity.z) * Config.SEARCH_DRIFT_SECONDS
		search_center = last_known_position + drift.limit_length(Config.SEARCH_DRIFT_MAX)
		_begin_search()
		return
	var interval := float(cfg["resist_interval"])
	if interval > 0.0:
		_resist_timer += dt
		if _resist_timer >= interval:
			_resist_timer = 0.0
			_escalate_resisting()


func _update_search(dt: float, real_delta: float) -> void:
	var cfg := get_level_config(level)
	_search_time += dt
	search_radius = minf(float(cfg["search_radius"]) + float(cfg["search_growth"]) * _search_time,
			float(cfg["search_radius_max"]))
	var rate := 1.0
	if Game.has_player():
		var pp := Game.get_player_position()
		var dx := pp.x - search_center.x
		var dz := pp.z - search_center.z
		if dx * dx + dz * dz < search_radius * search_radius:
			rate = Config.INSIDE_SEARCH_RATE
		_near_police_timer -= real_delta
		if _near_police_timer <= 0.0:
			_near_police_timer = 0.5
			_near_police = _count_group("police", pp, Config.NEAR_POLICE_RADIUS, false) > 0
		if _near_police:
			rate *= Config.NEAR_POLICE_RATE
	escape_progress = minf(escape_progress + dt * rate / maxf(get_escape_time_required(), 0.1), 1.0)
	if escape_progress >= 1.0:
		clear("escaped")


func _update_records() -> void:
	var i := _records.size() - 1
	while i >= 0:
		if i >= _records.size():
			i = _records.size() - 1
			continue
		var r := _records[i]
		if r.status == REC_PENDING:
			if r.due >= 0.0 and _clock >= r.due:
				r.due = -1.0
				var err := Config.INDIRECT_POSITION_ERROR
				var fuzz := Vector3(Game.rng.randf_range(-err, err), 0.0, Game.rng.randf_range(-err, err))
				_make_known(r, "indirect", r.position + fuzz)
			elif _clock >= r.expires:
				r.status = REC_EXPIRED
				crime_expired.emit(r.id, r.position)
		elif _clock - r.clock > Config.RECORD_MEMORY:
			_records.remove_at(i)
		i -= 1


# --- internals ---------------------------------------------------------------------------------

func _build_level_cfg() -> void:
	_level_cfg.clear()
	for i in Config.LEVELS.size():
		var d: Dictionary = Config.LEVELS[i].duplicate()
		d["level"] = i
		d["escape_seconds"] = Config.escape_seconds(i)
		_level_cfg.append(d)


func _new_record(crime_id: String, position: Vector3, base_heat: float, victim: Node) -> CrimeRecord:
	var r := CrimeRecord.new()
	r.id = crime_id
	r.position = position
	r.clock = _clock
	r.expires = _clock + Config.PENDING_TTL
	r.heat = base_heat
	r.victim = victim
	if _records.size() >= Config.MAX_RECORDS:
		_drop_oldest_record()
	_records.append(r)
	return r


func _drop_oldest_record() -> void:
	# prefer forgetting finished records; a pending one only if nothing else is left
	for i in _records.size():
		if _records[i].status != REC_PENDING:
			_records.remove_at(i)
			return
	_records.remove_at(0)


## Most recent record of `crime_id` within WITNESS_MATCH_RADIUS (null if none).
func _find_record(crime_id: String, position: Vector3) -> CrimeRecord:
	var r2 := Config.WITNESS_MATCH_RADIUS * Config.WITNESS_MATCH_RADIUS
	for i in range(_records.size() - 1, -1, -1):
		var r := _records[i]
		if r.id == crime_id and r.position.distance_squared_to(position) <= r2:
			return r
	return null


## A loud crime close to a pending one of the same kind joins it (one report, a bit more heat).
func _merge_loud(crime_id: String, position: Vector3) -> bool:
	var r2 := Config.MERGE_RADIUS * Config.MERGE_RADIUS
	for i in range(_records.size() - 1, -1, -1):
		var r := _records[i]
		if r.status == REC_PENDING and r.id == crime_id and r.position.distance_squared_to(position) <= r2:
			r.events += 1
			r.expires = maxf(r.expires, _clock + Config.PENDING_TTL * 0.5)
			if r.due < 0.0:
				# nobody heard the first one; maybe somebody hears this one
				r.position = position
				r.clock = _clock
				_schedule_indirect(r)
			return true
	return false


func _schedule_indirect(r: CrimeRecord) -> void:
	r.listeners = count_listeners_near(r.position, r.loud)
	if r.listeners <= 0:
		r.due = -1.0
		return
	var f := clampf(float(r.listeners - 1) / float(maxi(Config.INDIRECT_FAST_LISTENERS - 1, 1)), 0.0, 1.0)
	var delay := lerpf(Config.INDIRECT_DELAY_MAX, Config.INDIRECT_DELAY_MIN, f) + Game.rng.randf_range(-0.4, 0.4)
	r.due = r.clock + clampf(delay, Config.INDIRECT_DELAY_MIN, Config.INDIRECT_DELAY_MAX)
	r.expires = maxf(r.expires, r.due + 1.0)


func _promote_recent_pending() -> void:
	var n := _records.size()
	for i in n:
		if i >= _records.size():
			break
		var r := _records[i]
		if r.status == REC_PENDING and _clock - r.clock <= Config.SIGHTING_WINDOW:
			_make_known(r, "police", r.position, false)   # the sighting itself was just noted


## `note_seen`: for police / forced sources, treat report_pos as a sighting of the player.
func _make_known(r: CrimeRecord, source: String, report_pos: Vector3, note_seen: bool = true) -> void:
	r.status = REC_KNOWN
	r.source = source
	r.due = -1.0
	var def := Config.crime(r.id)
	var amount := r.heat
	if r.events > 1:
		amount *= 1.0 + minf(Config.MERGE_HEAT_PER_EVENT * float(r.events - 1), Config.MERGE_MAX_EXTRA_HEAT)
	if bool(def["damp"]):
		amount *= _take_repeat_factor(r.id)
	if bool(def["violent"]):
		episode_violent = true
	crimes_known_total += 1
	var seen := source == "police" or source == "forced"
	if seen and note_seen:
		_note_seen(report_pos)
	var was := level
	var prev_state := state
	heat += amount
	var cap := 5 if episode_violent else Config.NON_VIOLENT_MAX_LEVEL
	cap = maxi(cap, level)
	if cap < 5:
		# capped episodes do not bank hidden heat that would jump several stars later
		heat = minf(heat, Config.heat_for_level(cap + 1) - 0.05)
	var target := mini(maxi(Config.level_for_heat(heat), int(def["min_level"])), cap)
	if target > level:
		level = target
		heat = maxf(heat, Config.heat_for_level(target))
	if level > 0:
		if was <= 0 or prev_state == State.NONE:
			if seen:
				_set_state_raw(State.PURSUIT)
			else:
				_start_search_at(report_pos)
		elif prev_state == State.SEARCH:
			if seen:
				_resume_pursuit_raw()
			elif source != "resisting":
				_recenter_search(report_pos)
	EventBus.crime_reported.emit(r.id, report_pos)
	crime_became_known.emit(r.id, report_pos, source)
	_flush_signals()


func _take_repeat_factor(crime_id: String) -> float:
	var n := float(_repeat_count.get(crime_id, 0.0))
	if _clock - float(_repeat_clock.get(crime_id, -1.0e9)) > Config.REPEAT_WINDOW:
		n = 0.0
	_repeat_count[crime_id] = n + 1.0
	_repeat_clock[crime_id] = _clock
	return 1.0 / (1.0 + Config.REPEAT_DAMP * n)


func _escalate_resisting() -> void:
	var cap := 5 if episode_violent else Config.NON_VIOLENT_MAX_LEVEL
	if level >= cap:
		return
	var r := _new_record("resisting", last_known_position, float(get_level_config(level)["resist_heat"]), null)
	_make_known(r, "resisting", last_known_position)


func _note_seen(position: Vector3) -> void:
	_last_sighting_clock = _clock
	last_known_position = position
	search_center = position
	last_known_velocity = Game.get_player_velocity()
	seconds_since_seen = 0.0
	player_visible_to_police = true
	var veh := Game.get_player_vehicle()
	identified_vehicle = veh
	_identified_key = veh.get_instance_id() if veh != null else 0
	_vehicle_credits = 0
	_appearance_credits = 0
	if not _credited_keys.is_empty():
		_credited_keys.clear()
	_recognition_bonus = 0.0


func _begin_search() -> void:
	search_radius = float(get_level_config(level)["search_radius"])
	_search_time = 0.0
	_set_state_raw(State.SEARCH)
	_flush_signals()


## A report (no sighting) starts the episode in SEARCH around the reported position.
func _start_search_at(pos: Vector3) -> void:
	last_known_position = pos
	search_center = pos
	last_known_velocity = Vector3.ZERO
	escape_progress = 0.0
	seconds_since_seen = maxf(seconds_since_seen, float(get_level_config(level)["lost_contact_grace"]))
	search_radius = float(get_level_config(level)["search_radius"])
	_search_time = 0.0
	_set_state_raw(State.SEARCH)


func _recenter_search(pos: Vector3) -> void:
	last_known_position = pos
	search_center = pos
	_search_time = 0.0
	escape_progress *= 1.0 - Config.REPORT_PROGRESS_LOSS


func _resume_pursuit() -> void:
	_resume_pursuit_raw()
	_flush_signals()


func _resume_pursuit_raw() -> void:
	escape_progress = 0.0
	_set_state_raw(State.PURSUIT)


func _set_state_raw(s: int) -> void:
	if s == state:
		return
	state = s
	time_in_state = 0.0
	if s == State.NONE:
		escape_progress = 0.0


## Emits the level / state signals for whatever changed since the last flush (each change once,
## level first, consistent snapshot for listeners).
func _flush_signals() -> void:
	if level != _emitted_level:
		var prev := _emitted_level
		_emitted_level = level
		_resist_timer = 0.0
		EventBus.wanted_level_changed.emit(level, prev)
		_level_stinger(level, prev)
	if state != _emitted_state:
		_emitted_state = state
		EventBus.wanted_state_changed.emit(state)


func _reset_episode(drop_records: bool) -> void:
	heat = 0.0
	escape_progress = 0.0
	episode_violent = false
	_resist_timer = 0.0
	_search_time = 0.0
	_vehicle_credits = 0
	_appearance_credits = 0
	_credited_keys.clear()
	_recognition_bonus = 0.0
	_identified_key = -1
	identified_vehicle = null
	player_visible_to_police = false
	seconds_since_seen = 9999.0
	_last_sighting_clock = -1.0e9
	_repeat_count.clear()
	_repeat_clock.clear()
	if drop_records:
		_records.clear()
	else:
		# keep only what is still pending (a crime committed just before the escape is not wiped)
		for i in range(_records.size() - 1, -1, -1):
			if _records[i].status != REC_PENDING:
				_records.remove_at(i)


func _can_disguise() -> bool:
	return enabled and level > 0 and not player_visible_to_police \
			and seconds_since_seen >= Config.CHANGE_MIN_UNSEEN


func _apply_disguise(kind: String, cut: float, recognition: float) -> void:
	var p := escape_progress + (1.0 - escape_progress) * cut
	escape_progress = maxf(escape_progress, minf(p, Config.CHANGE_PROGRESS_CAP))
	_recognition_bonus += recognition
	disguise_applied.emit(kind, escape_progress, get_recognition_delay())


func _player_aiming_weapon() -> bool:
	if not Game.has_player():
		return false
	var p := Game.player
	if p.get("is_aiming") != true:
		return false
	return p.has_method("is_armed") and bool(p.call("is_armed"))


func _count_group(group: String, position: Vector3, radius: float, need_ai_driver: bool) -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var r2 := radius * radius
	var n := 0
	for node in tree.get_nodes_in_group(group):
		var n3 := node as Node3D
		if n3 == null or not n3.is_inside_tree() or n3.is_in_group("player"):
			continue
		if n3.global_position.distance_squared_to(position) > r2:
			continue
		if n3.get("is_dead") == true:
			continue
		if need_ai_driver:
			var d: Variant = n3.get("driver")
			if d == null or not is_instance_valid(d) or not (d is Node):
				continue
			if (d as Node).is_in_group("player") or n3.get("is_player_driven") == true \
					or n3.get("destroyed") == true:
				continue
		n += 1
	return n


func _is_player_node(who: Variant) -> bool:
	return who != null and is_instance_valid(who) and Dmg.caused_by_player({"instigator": who})


# --- stingers ----------------------------------------------------------------------------------
# The Audio autoload already plays wanted_up / wanted_down / wanted_clear / arrested from the
# EventBus signals (its "event glue"). Wanted plays them itself only when that glue is off, so a
# stinger is never doubled.

func _audio_for_stinger() -> Node:
	if not stingers_enabled:
		return null
	var a := get_node_or_null("/root/Audio")
	if a == null or a.get("auto_event_sounds") == true or not a.has_method("play"):
		return null
	return a


func _level_stinger(lvl: int, prev: int) -> void:
	var a := _audio_for_stinger()
	if a == null:
		return
	if lvl > prev:
		a.call("play", "wanted_up", -3.0, 1.0 + 0.03 * float(clampi(lvl - 1, 0, 4)), "UI")
	elif lvl < prev and lvl > 0:
		a.call("play", "wanted_down", -5.0, 1.0, "UI")


func _clear_stinger(reason: String) -> void:
	var a := _audio_for_stinger()
	if a == null:
		return
	if reason == "busted":
		a.call("play", "arrested", -3.0, 1.0, "UI")
	elif reason != "died":
		a.call("play", "wanted_clear", -4.0, 1.0, "UI")


# --- event listeners ---------------------------------------------------------------------------

func _on_noise_emitted(position: Vector3, radius: float, kind: String, instigator: Node) -> void:
	if kind != "gunshot" and kind != "suppressed_gunshot" and kind != "explosion":
		return
	if not _is_player_node(instigator):
		return
	_last_noise_clock = _clock
	_last_noise_pos = position
	_last_noise_radius = radius
	# the crime may have been reported a moment before its noise: fix its earshot radius
	for r in _records:
		if r.status == REC_PENDING and r.loud > 0.0 and absf(r.clock - _clock) <= Config.NOISE_MATCH_TIME \
				and r.position.distance_to(position) <= Config.NOISE_MATCH_DIST and not is_equal_approx(r.loud, radius):
			r.loud = radius
			_schedule_indirect(r)


func _on_crime_witnessed(crime_id: String, position: Vector3, _witness: Node) -> void:
	var r := _find_record(crime_id, position)
	if r != null and r.status == REC_PENDING and not r.grace_used:
		r.grace_used = true
		r.expires += Config.WITNESS_CALL_GRACE


func _on_weapon_fired(_weapon_id: String, shooter: Node, _origin: Vector3, _direction: Vector3) -> void:
	if _is_player_node(shooter):
		time_since_player_attack = 0.0


func _on_hit_confirmed(_target: Node, _info: Dictionary) -> void:
	time_since_player_attack = 0.0      # only ever emitted for the player's hits


func _on_npc_injured(_npc: Node3D, attacker: Node, _info: Dictionary) -> void:
	if _is_player_node(attacker):
		time_since_player_attack = 0.0


func _on_player_entered_vehicle(vehicle: Node3D, _seat: int) -> void:
	note_vehicle_change(vehicle)


func _on_player_exited_vehicle(vehicle: Node3D) -> void:
	# abandoning the vehicle the police identified counts as a change (to "on foot")
	if vehicle != null and is_instance_valid(vehicle) and vehicle.get_instance_id() == _identified_key:
		note_vehicle_change(null)


func _on_player_appearance_changed(_appearance: Dictionary) -> void:
	note_appearance_change()


func _on_player_died(_cause: String) -> void:
	# nobody reports the crimes of a dead man; the respawn flow clears the level
	for i in range(_records.size() - 1, -1, -1):
		if _records[i].status == REC_PENDING:
			_records.remove_at(i)
