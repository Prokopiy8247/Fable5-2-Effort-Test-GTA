extends Node
## Autoload "Skills": use-based character stats (0..100), spec 46A. docs/SKILLS.md lists every XP
## source and every benefit with the file that implements it (audited in Wave 3).
## Public names of the lead's contract stub are kept; additions are marked below.
## Gameplay code awards XP where the activity happens (Skills.add_xp("driving", delta * k)) and
## reads benefits through get_multiplier() / get_factor(). Benefits stay modest (low skill is fun).

const SKILLS: Array[String] = ["stamina", "shooting", "strength", "stealth", "driving", "flying", "lung"]
const DISPLAY_NAMES := {
	"stamina": "Stamina", "shooting": "Shooting", "strength": "Strength", "stealth": "Stealth",
	"driving": "Driving", "flying": "Flying", "lung": "Lung Capacity",
}
const START_LEVEL := 20.0

## --- additions ---------------------------------------------------------------------------------
## Strength = physical resilience: the player's max health grows from its base value at
## START_LEVEL up to +STRENGTH_HEALTH_BONUS (fraction) at 100 (100 hp -> 115 hp).
const STRENGTH_HEALTH_BONUS := 0.15
## Which skill a vehicle class trains (award_vehicle_xp). "" = none.
const VEHICLE_SKILL := {
	"car": "driving", "bike": "driving", "boat": "driving", "bicycle": "stamina",
	"heli": "flying", "plane": "flying",
}
## Skill points per second of player-driven travel at full pace (award_vehicle_xp).
const VEHICLE_XP_RATE := {"driving": 0.012, "flying": 0.017, "stamina": 0.01}
## Short benefit descriptions (status screen / docs). Values mirror the audited call sites.
const BENEFITS := {
	"stamina": "Longer sprints, faster swims, stronger pedalling",
	"shooting": "Less recoil, faster reloads",
	"strength": "Harder melee hits, more health",
	"stealth": "Quieter footsteps, harder to spot",
	"driving": "More grip in tricky driving",
	"flying": "Less turbulence, crisper aircraft control",
	"lung": "Longer breath under water",
}

var levels: Dictionary = {}
var xp_log: Dictionary = {}          ## skill -> total skill points gained this session (tests, debug)


func _ready() -> void:
	reset()
	EventBus.player_spawned.connect(func(_p: Node3D) -> void: _apply_strength_health.call_deferred())
	EventBus.player_respawned.connect(func(_pos: Vector3) -> void: _apply_strength_health())


func reset() -> void:
	for s in SKILLS:
		levels[s] = START_LEVEL
		EventBus.skill_changed.emit(s, START_LEVEL)
	_apply_strength_health()


func set_all(value: float) -> void:
	for s in SKILLS:
		levels[s] = clampf(value, 0.0, 100.0)
		EventBus.skill_changed.emit(s, levels[s])
	_apply_strength_health()


func get_level(skill: String) -> float:
	return float(levels.get(skill, 0.0))


## 0..1 normalised level.
func get_factor(skill: String) -> float:
	return clampf(get_level(skill) / 100.0, 0.0, 1.0)


## Linear benefit helper: value at skill 0 -> `at_zero`, at skill 100 -> `at_max`.
func get_multiplier(skill: String, at_zero: float, at_max: float) -> float:
	return lerpf(at_zero, at_max, get_factor(skill))


## Award experience (in skill points; ~100 total points from 0 to max, diminishing near the top).
func add_xp(skill: String, amount: float) -> void:
	if not levels.has(skill) or amount <= 0.0 or not is_finite(amount):
		return
	var before: float = levels[skill]
	var gain := amount * lerpf(1.0, 0.35, before / 100.0)
	levels[skill] = clampf(before + gain, 0.0, 100.0)
	xp_log[skill] = float(xp_log.get(skill, 0.0)) + gain
	if int(levels[skill]) != int(before):
		EventBus.skill_changed.emit(skill, levels[skill])
		if skill == "strength":
			_apply_strength_health()


func get_save_data() -> Dictionary:
	return {"levels": levels.duplicate()}


func load_save_data(d: Dictionary) -> void:
	var saved: Variant = d.get("levels", {})
	if not (saved is Dictionary):
		saved = {}
	for s in SKILLS:
		var v: Variant = (saved as Dictionary).get(s, START_LEVEL)
		var f := float(v) if (v is float or v is int) and is_finite(float(v)) else START_LEVEL
		levels[s] = clampf(f, 0.0, 100.0)
		EventBus.skill_changed.emit(s, levels[s])
	_apply_strength_health()


# =================================================================================================
# additions
# =================================================================================================

## Set one skill (admin menu, tests). Emits skill_changed.
func set_level(skill: String, value: float) -> void:
	if not levels.has(skill) or not is_finite(value):
		return
	levels[skill] = clampf(value, 0.0, 100.0)
	EventBus.skill_changed.emit(skill, levels[skill])
	if skill == "strength":
		_apply_strength_health()


## 0..1 progress above the starting level (0 at START_LEVEL or below, 1 at 100). Benefits that must
## not make a new character worse than the baseline use this instead of get_factor().
func get_progress(skill: String) -> float:
	return clampf((get_level(skill) - START_LEVEL) / (100.0 - START_LEVEL), 0.0, 1.0)


## The skill a vehicle class trains ("car"/"bike"/"boat" -> driving, "bicycle" -> stamina,
## "heli"/"plane" -> flying, anything else -> "").
func vehicle_skill(vehicle_class: String) -> String:
	return str(VEHICLE_SKILL.get(vehicle_class, ""))


## Single entry point for travel XP of a player-driven vehicle: `seconds` of travel at `pace`
## (0..1, e.g. speed / cruise speed). VehicleBase / aircraft should call this instead of picking
## the skill themselves (see docs/SKILLS.md, request to the vehicle owner).
func award_vehicle_xp(vehicle: Node, seconds: float, pace: float = 1.0) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or seconds <= 0.0:
		return
	var skill := vehicle_skill(str(vehicle.get("vehicle_class")))
	if skill == "":
		return
	add_xp(skill, float(VEHICLE_XP_RATE.get(skill, 0.01)) * seconds * clampf(pace, 0.0, 1.0))


## Max health the player has at the current Strength (base = the player's own value at boot).
func get_strength_max_health(base: float = 100.0) -> float:
	return base * (1.0 + STRENGTH_HEALTH_BONUS * get_progress("strength"))


func get_benefit_text(skill: String) -> String:
	return str(BENEFITS.get(skill, ""))


## Strength resilience through the player's public `max_health` (the HUD reads it). Health above
## the new maximum is clamped; a full bar stays full.
func _apply_strength_health() -> void:
	if not Game.has_player():
		return
	var p := Game.player
	var mh: Variant = p.get("max_health")
	if not (mh is float or mh is int):
		return
	if not p.has_meta(&"skills_base_max_health"):
		p.set_meta(&"skills_base_max_health", float(mh))
	var base := float(p.get_meta(&"skills_base_max_health"))
	var new_max := snappedf(get_strength_max_health(base), 0.1)
	var old_max := float(mh)
	if is_equal_approx(new_max, old_max):
		return
	p.set("max_health", new_max)
	var hv: Variant = p.get("health")
	if hv is float or hv is int:
		var h := float(hv)
		if p.get("is_dead") != true:
			if h >= old_max - 0.01:
				h = new_max
			h = minf(h, new_max)
			p.set("health", h)
		var av: Variant = p.get("armor")
		EventBus.player_health_changed.emit(h, float(av) if (av is float or av is int) else 0.0)
