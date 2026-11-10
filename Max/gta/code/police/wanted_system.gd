class_name WantedSystem
extends Node
## Wanted level 0-5 driven by *witnessed* crime. A crime only counts when an officer sees or
## hears it, when the victim is the police, or when a civilian witness finishes a phone call.
## While officers have eyes on the player the state is PURSUIT; once they lose sight it
## becomes SEARCH around the last known position and the level clears after a cool-down.

enum { NONE, PURSUIT, SEARCH }

const THRESHOLDS := [0.0, 8.0, 40.0, 110.0, 220.0, 380.0]
const COOLDOWN := [0.0, 20.0, 28.0, 38.0, 50.0, 62.0]
## heat per crime, whether an officer merely hearing it is enough, radius in which witnesses count
const CRIMES := {
	&"gunfire": {"heat": 6.0, "label": "Shots fired", "radius": 55.0},
	&"assault": {"heat": 10.0, "label": "Assault", "radius": 40.0},
	&"hit_and_run": {"heat": 14.0, "label": "Hit and run", "radius": 50.0},
	&"collision": {"heat": 3.0, "label": "Reckless driving", "radius": 35.0},
	&"carjack": {"heat": 16.0, "label": "Carjacking", "radius": 45.0},
	&"steal_parked": {"heat": 9.0, "label": "Vehicle theft", "radius": 35.0},
	&"steal_police": {"heat": 42.0, "label": "Theft of a police vehicle", "radius": 60.0},
	&"murder": {"heat": 35.0, "label": "Homicide", "radius": 55.0},
	&"explosion": {"heat": 45.0, "label": "Explosion", "radius": 120.0},
	&"cop_assault": {"heat": 45.0, "label": "Assault on an officer", "radius": 80.0},
	&"cop_murder": {"heat": 110.0, "label": "Officer down", "radius": 80.0},
	&"threaten_cop": {"heat": 12.0, "label": "Armed suspect", "radius": 40.0},
	&"trespass": {"heat": 9.0, "label": "Trespassing", "radius": 60.0},
	&"shoplift": {"heat": 20.0, "label": "Armed robbery", "radius": 40.0},
}

var level := 0
var heat := 0.0
var state: int = NONE
var last_known := Vector3.ZERO
var search_radius := 40.0
var evade_time := 0.0                # seconds hidden in SEARCH
var seen_now := false                # an officer has eyes on the player right now
var last_seen := -100.0
var known_vehicle: Node3D = null     # the vehicle officers last saw the player in
var busted_meter := 0.0
var last_violence := -100.0
var crimes_log: Array = []           # recent reported crimes (for the pause menu / debug)
var _busted_tick := -100.0
var _seen_cd := 0.0
var _gunfire_gate := 0.0
var _cop_hurt_gate := 0.0
var _victims: Dictionary = {}
var _calls := 0
var _first_seen_delay := 0.0

func _ready() -> void:
	Events.crime.connect(_on_crime)
	Events.npc_died.connect(_on_npc_died)
	Events.npc_hurt.connect(_on_npc_hurt)
	Events.player_died.connect(func(_c: String) -> void: clear(true))
	Events.player_busted.connect(func() -> void: clear(true))
	Events.vehicle_destroyed.connect(_on_vehicle_destroyed)

func now() -> float:
	return Game.clock

func is_wanted() -> bool:
	return level > 0

# ---------------------------------------------------------------- crime intake
func _enabled() -> bool:
	return not Game.cheats["never_wanted"] and Game.flags["police"]

func _on_npc_died(npc: Node3D, killer: Node) -> void:
	if killer == null or killer != Game.player:
		return
	_victims[npc.get_instance_id()] = true
	var cop := npc is NPC and (npc as NPC).is_cop()
	_handle(&"cop_murder" if cop else &"murder", npc.global_position, {"victim": npc})

func _on_npc_hurt(npc: Node3D, attacker: Node, _amount: float) -> void:
	if attacker != Game.player or not (npc is NPC) or not (npc as NPC).is_cop():
		return
	if now() < _cop_hurt_gate:
		return
	_cop_hurt_gate = now() + 2.5
	_handle(&"cop_assault", npc.global_position, {"victim": npc})

func _on_vehicle_destroyed(veh: Node3D, by: Node) -> void:
	if by == Game.player and veh is Vehicle and (veh as Vehicle).owner_tag == "police":
		_handle(&"cop_assault", veh.global_position, {"force": true})

func _on_crime(type: StringName, pos: Vector3, data: Dictionary) -> void:
	if type == &"murder" or type == &"assault":
		var victim: Variant = data.get("victim")
		if victim is Object and is_instance_valid(victim):
			# kills are reported through npc_died (covers every weapon)
			if type == &"murder" or _victims.has((victim as Object).get_instance_id()):
				return
			if victim is NPC and (victim as NPC).is_cop():
				type = &"cop_assault"
	if type == &"gunfire":
		if now() < _gunfire_gate:
			return
		_gunfire_gate = now() + 1.0
	_handle(type, pos, data)

func _handle(type: StringName, pos: Vector3, data: Dictionary) -> void:
	if not _enabled() or not CRIMES.has(type):
		return
	var def: Dictionary = CRIMES[type]
	var amount := float(def["heat"])
	var radius := float(def["radius"])
	var victim: Variant = data.get("victim")
	var vs_police := type == &"cop_assault" or type == &"cop_murder" or type == &"threaten_cop" or bool(data.get("force", false))
	if type == &"murder" or type == &"cop_murder" or type == &"cop_assault" or type == &"explosion" or type == &"gunfire":
		last_violence = now()
	if type == &"collision":
		var other: Variant = data.get("vehicle")
		if other is Vehicle and (other as Vehicle).owner_tag == "police":
			amount = 12.0
			vs_police = true
		elif level == 0:
			return                   # fender benders alone never start a chase
	if type == &"gunfire":
		if bool(data.get("suppressed", false)):
			radius = 12.0
		# shooting alone never pushes beyond two stars
		if heat >= THRESHOLDS[2] + 12.0:
			amount = 0.0
	if bool(data.get("silent", false)):
		radius = 14.0
	var w: Dictionary = {"civil": [], "police": []}
	if Game.peds != null:
		w = Game.peds.witnesses(pos, radius)
	var cops: Array = w["police"]
	var civil: Array = w["civil"]
	# officers also react to loud crimes they only hear
	var heard := false
	if type == &"gunfire" or type == &"explosion":
		var hear_r := float(data.get("radius", 60.0)) if type == &"gunfire" else 140.0
		for n in get_tree().get_nodes_in_group(&"police_units"):
			if n is Node3D and (n as Node3D).global_position.distance_to(pos) < hear_r:
				heard = true
				break
	if vs_police or not cops.is_empty() or heard or (level > 0 and state == PURSUIT):
		report(type, pos, amount, not cops.is_empty() or vs_police)
		return
	# a civilian witness has to phone it in
	var best: NPC = null
	var best_d := 1.0e9
	for c in civil:
		var npc := c as NPC
		if npc == victim or npc.is_witness_calling or npc.state == NPC.S.SEATED:
			continue
		var d := npc.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = npc
	if best != null and _calls < 2:
		_calls += 1
		best.threat_pos = pos
		best.call_police({"type": type, "pos": pos, "heat": amount})
		if level == 0:
			Game.notify("A witness is calling the police", "wanted")

## Called by a witness NPC when the phone call went through.
func witness_report(crime: Dictionary, _who: Node) -> void:
	_calls = maxi(0, _calls - 1)
	if not _enabled():
		return
	report(crime.get("type", &"assault"), crime.get("pos", Game.player_pos()), float(crime.get("heat", 8.0)), false)

func report(type: StringName, pos: Vector3, amount: float, eyes_on := false) -> void:
	if not _enabled():
		return
	var label := String(CRIMES.get(type, {}).get("label", String(type)))
	crimes_log.append({"type": type, "label": label, "time": Game.time.clock_text() if Game.time else "", "district": Game.district_at(pos)})
	if crimes_log.size() > 12:
		crimes_log.pop_front()
	heat += amount
	var new_level := level
	for i in range(5, 0, -1):
		if heat >= float(THRESHOLDS[i]):
			new_level = maxi(level, i)
			break
	if state == NONE:
		last_known = pos
		search_radius = 40.0
		evade_time = 0.0
		_set_state(SEARCH)
	elif eyes_on:
		last_known = Game.player_pos()
	if new_level != level:
		_set_level(new_level, label)

func _set_level(n: int, reason := "") -> void:
	n = clampi(n, 0, 5)
	var was := level
	level = n
	if n > was:
		Game.stats["max_wanted"] = maxi(int(Game.stats["max_wanted"]), n)
		evade_time = 0.0
		Audio.play_ui(&"ui_wanted_up", -4.0)
		if reason != "":
			Game.notify("%s  -  wanted level %d" % [reason, n], "wanted")
	Events.wanted_changed.emit(level)

func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	Events.wanted_state_changed.emit(state)

# ---------------------------------------------------------------- admin / gameplay API
func set_level(n: int) -> void:
	n = clampi(n, 0, 5)
	if n == 0:
		clear()
		return
	heat = float(THRESHOLDS[n])
	if state == NONE:
		last_known = Game.player_pos()
		search_radius = 40.0
		_set_state(SEARCH)
	evade_time = 0.0
	level = n
	Game.stats["max_wanted"] = maxi(int(Game.stats["max_wanted"]), n)
	Events.wanted_changed.emit(level)

func clear(silent := false) -> void:
	var was := level
	level = 0
	heat = 0.0
	evade_time = 0.0
	busted_meter = 0.0
	seen_now = false
	known_vehicle = null
	_calls = 0
	_set_state(NONE)
	if was > 0:
		Events.wanted_changed.emit(0)
		if not silent:
			Game.notify("You lost the police", "good")
			Audio.play_ui(&"ui_wanted_clear", -6.0)

## Respray / plate change: only works while nobody is watching.
func can_lose_by_disguise() -> bool:
	return level > 0 and not seen_now

# ---------------------------------------------------------------- rules of engagement
func police_may_shoot(_cop: Node) -> bool:
	if level >= 3:
		return true
	var pl: Player = Game.player
	if pl == null:
		return false
	var t := now()
	if t - last_violence < 9.0:
		return true
	if level == 2:
		if pl.gunner.is_gun() and pl.vehicle == null:
			return true
		if pl.vehicle != null and absf((pl.vehicle as Vehicle).speed) > 9.0:
			return true
	# pointing a gun at people is a lethal threat at any level
	return pl.aiming and pl.gunner.is_gun()

## An officer is within reach of the suspect: fill the arrest meter while they hold still.
func arrest_tick(_cop: Node, delta: float) -> void:
	var pl: Player = Game.player
	if pl == null or not pl.alive or level == 0 or level >= 3:
		return
	var sp := pl.velocity.length()
	if pl.vehicle != null:
		sp = absf((pl.vehicle as Vehicle).speed)
	if sp > 2.2 or pl.state == Player.St.BUSTED:
		return
	_busted_tick = now()
	busted_meter += delta
	if busted_meter >= 1.5:
		busted_meter = 0.0
		pl.busted()

# ---------------------------------------------------------------- per-frame
func _physics_process(delta: float) -> void:
	if level == 0:
		if state != NONE:
			# a report came in but did not reach one star: forget it after a moment
			evade_time += delta
			if evade_time > 12.0:
				clear(true)
		heat = maxf(0.0, heat - delta * 0.15)
		return
	if not _enabled():
		clear(true)
		return
	var pl: Player = Game.player
	if pl == null:
		return
	if now() - _busted_tick > 0.4:
		busted_meter = maxf(0.0, busted_meter - delta * 1.5)
	_seen_cd -= delta
	if _seen_cd <= 0.0:
		_seen_cd = 0.2
		_update_seen(pl)
	var t := now()
	if seen_now:
		last_seen = t
		last_known = pl.global_position
		known_vehicle = pl.vehicle
		evade_time = 0.0
		search_radius = 40.0
		_set_state(PURSUIT)
	elif state == PURSUIT and t - last_seen > 2.5:
		_set_state(SEARCH)
	if state == SEARCH:
		evade_time += delta
		search_radius = minf(search_radius + delta * 2.6, 90.0 + level * 14.0)
		if evade_time >= float(COOLDOWN[level]):
			clear()

func _update_seen(pl: Player) -> void:
	seen_now = false
	if not pl.alive:
		return
	# a fresh, unseen vehicle works as a disguise until an officer gets close
	var disguised := state == SEARCH and pl.vehicle != null and pl.vehicle != known_vehicle
	for n in get_tree().get_nodes_in_group(&"police_units"):
		if n is NPC:
			var cop := n as NPC
			if not cop.alive or cop.down:
				continue
			if cop.can_see(pl):
				if disguised and cop.global_position.distance_to(pl.global_position) > 16.0:
					continue
				seen_now = true
				return
		elif n.has_method("sees_player") and n.sees_player():
			seen_now = true
			return

# ---------------------------------------------------------------- persistence
func save_state() -> Dictionary:
	return {"level": 0}           # a saved game always resumes clean (no pursuit in progress)

func load_state(_d: Dictionary) -> void:
	clear(true)
