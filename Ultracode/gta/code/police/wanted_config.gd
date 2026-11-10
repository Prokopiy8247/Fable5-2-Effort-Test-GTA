extends RefCounted
## Tuning tables of the Wanted system (autoload "Wanted", wanted_system.gd).
## Pure data + tiny static helpers; no state, no class_name. Reach it at runtime through
## `Wanted.Config.<CONST>` / `Wanted.get_level_config(lvl)` / `Wanted.get_crime_def(id)`.
## Design notes: docs/WANTED.md.
## All times are GAME seconds (Wanted additionally multiplies by Wanted.debug_time_scale).

# --- crimes -----------------------------------------------------------------------------------
## Heat added when a crime becomes KNOWN to the police (x opts.severity). Stars come from
## HEAT_THRESHOLDS. Every id here also has a row in CRIMES (wnt_core checks that).
## Exposed unchanged as the frozen contract constant `Wanted.CRIME_HEAT`.
const CRIME_HEAT := {
	"disturbance": 0.25,          # brandishing, thrown molotov, minor mischief
	"property_damage": 0.3,
	"collision_major": 0.4,
	"resisting": 0.5,             # internal: a pursuit that drags on (never reported by gameplay)
	"assault": 0.6,
	"hit_and_run": 0.7,
	"vehicle_theft": 0.8,         # carjacking an occupied vehicle (empty civilian cars are free)
	"gunfire": 0.8,
	"aircraft_violation": 1.0,
	"robbery": 1.2,
	"murder": 1.4,
	"explosion": 1.6,
	"cop_assault": 1.6,
	"police_vehicle_theft": 2.0,
	"police_vehicle_destroyed": 2.2,
	"cop_murder": 2.6,
}
## Fallback heat of an unknown crime id.
const DEFAULT_HEAT := 0.3

## Per crime id:
##   min_level   the crime alone guarantees at least this many stars once known
##   violent     a violent crime lifts the 3-star cap of non-violent episodes
##   loud        earshot radius in metres (0 = silent). Loud crimes nobody saw are still called in
##               by people within earshot after INDIRECT_DELAY_MIN..MAX seconds.
##   damp        repeated occurrences within REPEAT_WINDOW give less and less heat (spam crimes)
##   auto_known  the police learn about it without any witness (officer hurt / cruiser transponder)
const CRIMES := {
	"disturbance":              {"min_level": 1, "violent": false, "loud": 0.0,   "damp": true,  "auto_known": false},
	"property_damage":          {"min_level": 1, "violent": false, "loud": 0.0,   "damp": true,  "auto_known": false},
	"collision_major":          {"min_level": 1, "violent": false, "loud": 0.0,   "damp": true,  "auto_known": false},
	"resisting":                {"min_level": 0, "violent": false, "loud": 0.0,   "damp": false, "auto_known": true},
	"assault":                  {"min_level": 1, "violent": true,  "loud": 0.0,   "damp": false, "auto_known": false},
	"hit_and_run":              {"min_level": 1, "violent": true,  "loud": 0.0,   "damp": false, "auto_known": false},
	"vehicle_theft":            {"min_level": 1, "violent": false, "loud": 0.0,   "damp": false, "auto_known": false},
	"gunfire":                  {"min_level": 1, "violent": false, "loud": 70.0,  "damp": true,  "auto_known": false},
	"aircraft_violation":       {"min_level": 1, "violent": false, "loud": 0.0,   "damp": true,  "auto_known": false},
	"robbery":                  {"min_level": 1, "violent": false, "loud": 0.0,   "damp": false, "auto_known": false},
	"murder":                   {"min_level": 2, "violent": true,  "loud": 0.0,   "damp": false, "auto_known": false},
	"explosion":                {"min_level": 2, "violent": true,  "loud": 120.0, "damp": false, "auto_known": false},
	"cop_assault":              {"min_level": 2, "violent": true,  "loud": 0.0,   "damp": false, "auto_known": true},
	"police_vehicle_theft":     {"min_level": 2, "violent": false, "loud": 0.0,   "damp": false, "auto_known": true},
	"police_vehicle_destroyed": {"min_level": 2, "violent": true,  "loud": 0.0,   "damp": false, "auto_known": false},
	"cop_murder":               {"min_level": 3, "violent": true,  "loud": 0.0,   "damp": false, "auto_known": true},
}
## Unknown crime ids are treated like this (never crash on a neighbour's new id).
const CRIME_DEFAULT := {"min_level": 1, "violent": false, "loud": 0.0, "damp": true, "auto_known": false}

## Heat needed for star 1..5.
const HEAT_THRESHOLDS: Array[float] = [0.25, 1.6, 3.6, 6.5, 10.0]
## Without a violent crime in the current wanted episode heat (incl. "resisting") stops here.
const NON_VIOLENT_MAX_LEVEL := 3

# --- witness logic ----------------------------------------------------------------------------
## A police sighting this close in time (before or after) to a crime makes it known.
const SIGHTING_WINDOW := 1.1
## Unknown (pending) crimes are forgotten after this long without a report.
const PENDING_TTL := 15.0
## EventBus.crime_witnessed (a civilian started calling) keeps a pending crime alive this much longer.
const WITNESS_CALL_GRACE := 12.0
## A witness report matches a crime record of the same id within this distance.
const WITNESS_MATCH_RADIUS := 40.0
## Crime records (pending, known, expired) are kept this long for de-duplication.
const RECORD_MEMORY := 60.0
const MAX_RECORDS := 32
## Loud crimes heard by people nearby are called in after this delay (more listeners = faster).
const INDIRECT_DELAY_MIN := 6.0
const INDIRECT_DELAY_MAX := 10.0
## Listeners needed for the fastest call (linear between 1 and this many).
const INDIRECT_FAST_LISTENERS := 6
## An indirect report only says roughly where the noise came from.
const INDIRECT_POSITION_ERROR := 12.0
## Repeated loud crimes of the same kind close together merge into one pending report.
const MERGE_RADIUS := 35.0
const MERGE_MAX_EXTRA_HEAT := 1.0        ## a merged report gives at most (1 + this) x heat
const MERGE_HEAT_PER_EVENT := 0.25
## A noise event of the player this close (m / s) to a loud crime sets its earshot radius.
const NOISE_MATCH_DIST := 4.0
const NOISE_MATCH_TIME := 0.35
## Spam damping: heat x 1 / (1 + REPEAT_DAMP * recent repeats of the same id).
const REPEAT_DAMP := 0.5
const REPEAT_WINDOW := 20.0

# --- pursuit / search / escape ----------------------------------------------------------------
## Without a new sighting for this long the player is no longer "visible to police".
const VISIBLE_TIMEOUT := 0.6
## Escape progress rate while the player is still INSIDE the search circle (outside = 1.0).
const INSIDE_SEARCH_RATE := 0.55
## ... and multiplied by this while a police unit is within NEAR_POLICE_RADIUS (searching nearby).
const NEAR_POLICE_RATE := 0.6
const NEAR_POLICE_RADIUS := 30.0
## The search centre drifts along the last known velocity for this long (capped distance).
const SEARCH_DRIFT_SECONDS := 4.0
const SEARCH_DRIFT_MAX := 30.0
## A crime reported during SEARCH re-centres the search and costs this share of the progress.
const REPORT_PROGRESS_LOSS := 0.5

# --- disguise (vehicle / appearance change while unseen) --------------------------------------
## The player must have been unseen this long for a change to count.
const CHANGE_MIN_UNSEEN := 1.5
## Share of the REMAINING escape time removed per credit.
const VEHICLE_CHANGE_CUT := 0.25
const APPEARANCE_CHANGE_CUT := 0.3
## Credits per unseen episode (reset by the next sighting).
const MAX_VEHICLE_CREDITS := 2
const MAX_APPEARANCE_CREDITS := 1
## A disguise can never push escape progress past this (never an instant clear).
const CHANGE_PROGRESS_CAP := 0.85
## Recognition delay (seconds an officer must keep the player in sight before a sighting counts).
const RECOGNITION_BASE_SEARCH := 0.35
const RECOGNITION_PER_VEHICLE := 1.0
const RECOGNITION_APPEARANCE := 1.4
const RECOGNITION_MAX := 3.0

# --- arrest -----------------------------------------------------------------------------------
## Not arrestable for this long after the player fired / attacked.
const ARREST_CALM_SECONDS := 3.0
## Max speed (m/s) of the player's vehicle for an arrest (stopped).
const ARREST_MAX_VEHICLE_SPEED := 1.5
## Lethal force is authorized at any level for this long after the player attacked.
const LETHAL_AFTER_ATTACK_SECONDS := 10.0

# --- levels -----------------------------------------------------------------------------------
## Seconds unseen (outside the search circle) needed to lose star level 1..5.
## Exposed unchanged as the frozen contract constant `Wanted.ESCAPE_SECONDS`.
const ESCAPE_SECONDS: Array[float] = [20.0, 30.0, 45.0, 60.0, 80.0]

## Index = star level (0 = not wanted). W2.3 keys: officers, cruisers, swat_vans, heli,
## roadblocks, lethal, respawn_interval, search_radius (+ escape_seconds, merged in from
## ESCAPE_SECONDS by Wanted.get_level_config). Extra keys:
##   search_growth (m/s), search_radius_max, lost_contact_grace (s without sightings PURSUIT ->
##   SEARCH), resist_interval (s of sustained pursuit per "resisting" heat), resist_heat,
##   arrest_first (officers try to cuff an arrestable player before shooting), roadblock_spikes.
## "lethal" is the level's default; Wanted.is_lethal_force_authorized() also allows it at 1 star
## while the player is armed + aiming or attacked recently.
## Unit counts respect ARCHITECTURE 10 caps (<= 16 officers, <= 8 vehicles, <= 1 heli).
const LEVELS: Array[Dictionary] = [
	{"officers": 0, "cruisers": 0, "swat_vans": 0, "heli": 0, "roadblocks": 0, "lethal": false,
		"respawn_interval": 0.0, "search_radius": 0.0, "search_growth": 0.0, "search_radius_max": 0.0,
		"lost_contact_grace": 0.0, "resist_interval": 0.0, "resist_heat": 0.0,
		"arrest_first": false, "roadblock_spikes": false},
	{"officers": 2, "cruisers": 1, "swat_vans": 0, "heli": 0, "roadblocks": 0, "lethal": false,
		"respawn_interval": 20.0, "search_radius": 45.0, "search_growth": 1.6, "search_radius_max": 110.0,
		"lost_contact_grace": 3.0, "resist_interval": 25.0, "resist_heat": 0.5,
		"arrest_first": true, "roadblock_spikes": false},
	{"officers": 4, "cruisers": 2, "swat_vans": 0, "heli": 0, "roadblocks": 0, "lethal": true,
		"respawn_interval": 15.0, "search_radius": 60.0, "search_growth": 2.0, "search_radius_max": 150.0,
		"lost_contact_grace": 3.5, "resist_interval": 30.0, "resist_heat": 0.7,
		"arrest_first": true, "roadblock_spikes": false},
	{"officers": 8, "cruisers": 4, "swat_vans": 0, "heli": 1, "roadblocks": 1, "lethal": true,
		"respawn_interval": 12.0, "search_radius": 80.0, "search_growth": 2.6, "search_radius_max": 190.0,
		"lost_contact_grace": 4.0, "resist_interval": 35.0, "resist_heat": 0.9,
		"arrest_first": true, "roadblock_spikes": false},
	{"officers": 12, "cruisers": 5, "swat_vans": 1, "heli": 1, "roadblocks": 2, "lethal": true,
		"respawn_interval": 10.0, "search_radius": 100.0, "search_growth": 3.2, "search_radius_max": 230.0,
		"lost_contact_grace": 4.5, "resist_interval": 40.0, "resist_heat": 1.0,
		"arrest_first": false, "roadblock_spikes": true},
	{"officers": 16, "cruisers": 6, "swat_vans": 2, "heli": 1, "roadblocks": 3, "lethal": true,
		"respawn_interval": 8.0, "search_radius": 120.0, "search_growth": 4.0, "search_radius_max": 270.0,
		"lost_contact_grace": 5.0, "resist_interval": 45.0, "resist_heat": 1.2,
		"arrest_first": false, "roadblock_spikes": true},
]


## Heat of a crime id (DEFAULT_HEAT for unknown ids).
static func crime_heat(crime_id: String) -> float:
	return float(CRIME_HEAT.get(crime_id, DEFAULT_HEAT))


## Crime attributes (CRIME_DEFAULT for unknown ids). Returned dictionaries are shared constants:
## read them, never modify them.
static func crime(crime_id: String) -> Dictionary:
	return CRIMES.get(crime_id, CRIME_DEFAULT)


## Raw level row for 0..5 (clamped, WITHOUT escape_seconds; use Wanted.get_level_config()).
static func level_row(lvl: int) -> Dictionary:
	return LEVELS[clampi(lvl, 0, LEVELS.size() - 1)]


## Star level reached by `heat` (0..5).
static func level_for_heat(heat: float) -> int:
	var lvl := 0
	for i in HEAT_THRESHOLDS.size():
		if heat >= HEAT_THRESHOLDS[i] - 0.0001:
			lvl = i + 1
	return lvl


## Heat at the threshold of star `lvl` (0 for 0).
static func heat_for_level(lvl: int) -> float:
	if lvl <= 0:
		return 0.0
	return HEAT_THRESHOLDS[clampi(lvl, 1, HEAT_THRESHOLDS.size()) - 1]


## Seconds unseen needed to escape `lvl` stars (0 for 0).
static func escape_seconds(lvl: int) -> float:
	if lvl <= 0:
		return 0.0
	return ESCAPE_SECONDS[clampi(lvl, 1, ESCAPE_SECONDS.size()) - 1]