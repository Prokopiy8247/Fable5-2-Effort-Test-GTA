class_name AiBrainCivilian
extends Node
## Brain of ordinary pedestrians (civilian_m / civilian_f / civilian_tough / taxi_driver) and the
## passive fallback for service NPCs (medic, firefighter, police without a police brain).
##
## Ambient life: wander along the sidewalks to destinations, idle, sit on benches, small talking
## pairs. Reactions: bumped -> annoyed; gun pointed at them -> hands up / cower / flee; gunfire,
## explosions, screams -> scream + flee along the walk graph (some cower); a player crime seen or
## heard -> EventBus.crime_witnessed, move to a safe distance, ~4 s phone call, then the report
## (PedSystem.submit_witness_report -> Wanted.report_witnessed) - cancelled when the witness is
## killed, knocked down or chased off first. `civilian_tough` fights back with fists.
## Carjacked (event "carjacked" {attacker}, or a "damaged" event whose info has carjacked = true):
## tough locals fight the thief, everybody else shouts, runs and may phone it in. Knocked out by a
## takedown (info.knockout): no scream, stays down (NpcBase), then wakes up DAZED (hand on the head,
## slow stagger) instead of panicking.
## Driven by NpcBase: think(npc, delta) at the simulation-tier rate, on_event(npc, event, data).

enum { IDLE, WANDER, SIT, TALK, FLEE, COWER, HANDS_UP, WITNESS, PHONE, ANNOYED, FIGHT, DUTY, RECOVER, DAZED }
const MODE_NAMES := ["idle", "walk", "sit", "talk", "flee", "cower", "hands_up", "witness", "phone",
		"annoyed", "fight", "duty", "recover", "dazed"]

const SAFE_DISTANCE := 24.0            ## witnesses get at least this far from the crime before calling
const CALL_SECONDS := 4.0
const CHASE_CANCEL_DISTANCE := 6.5     ## the player this close (and coming closer) aborts the call
const SCREAM_MIN_INTERVAL := 0.6       ## global rate limit for screams

static var _last_scream: float = -100.0

var mode: int = IDLE
var t: float = 0.0
var timer: float = 2.0
var fear: float = 0.0
var danger_pos: Vector3 = Vector3.INF
var partner: Node3D = null
var bench: Transform3D = Transform3D()
var bench_key: int = -1
var fight_target: Node3D = null
var witness_crime: String = ""
var witness_pos: Vector3 = Vector3.INF
var witness_may_call: bool = false
var report_sent: bool = false
var report_cancelled: String = ""         ## why the last call was cancelled ("", "killed", "down", "chased")
var bumps: int = 0
var carjacked_by: Node3D = null           ## the thief who pulled us out of our car (if any)
var knocked_out: bool = false             ## down from a takedown knock-out
var _bump_t: float = 0.0
var _annoy_by: Node3D = null
var _resume_mode: int = IDLE
var _repath: float = 0.0
var _service: bool = false
var _brave: float = 0.2
var _tough: bool = false
var _rng := RandomNumberGenerator.new()


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func on_event(npc: Node, event: String, data: Dictionary) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	match event:
		"spawned":
			_on_spawned(npc, data)
		"noise":
			_on_noise(npc, data)
		"saw_crime":
			_on_crime(npc, data)
		"threatened":
			_on_threatened(npc, data)
		"bumped":
			_on_bumped(npc, data)
		"damaged":
			_on_damaged(npc, data)
		"carjacked":
			_on_carjacked(npc, data)
		"vehicle_hit":
			danger_pos = (npc as Node3D).global_position
			fear = 1.0
		"knocked_down":
			_cancel_call(npc, "down")
			_release_bench(npc)
			mode = RECOVER
			t = 0.0
		"got_up":
			if bool(data.get("knockout", false)) or knocked_out:
				knocked_out = false
				_start_dazed(npc)
			elif mode == RECOVER:
				if _tough and fight_target != null and is_instance_valid(fight_target):
					_set_mode(FIGHT, 25.0)
				else:
					_start_flee(npc, danger_pos if danger_pos != Vector3.INF else (npc as Node3D).global_position, "run")
		"panic":
			if mode != FLEE:
				_cancel_call(npc, "chased")
				_release_bench(npc)
				danger_pos = data.get("from", (npc as Node3D).global_position)
				fear = maxf(fear, 0.8)
				mode = FLEE
				t = 0.0
				timer = 10.0
		"died":
			_cancel_call(npc, "killed")
			_release_bench(npc)
		"talk_with":
			var p: Variant = data.get("partner", null)
			if p is Node3D and is_instance_valid(p) and mode in [IDLE, WANDER, DUTY]:
				partner = p
				npc.call("stop_moving")
				_set_mode(TALK, float(data.get("duration", _rng.randf_range(20.0, 55.0))))
				npc.set("state_tag", "talk")
		"reset":
			_cancel_call(npc, "chased")
			fight_target = null
			fear = 0.0
			if not _service and not bool(npc.get("is_down")):
				_start_wander(npc)
		"stuck":
			if mode == WANDER:
				_set_mode(IDLE, _rng.randf_range(1.0, 3.0))


func think(npc: Node, delta: float) -> void:
	var n := npc as Node3D
	if n == null or bool(npc.get("is_dead")):
		return
	t += delta
	fear = maxf(fear - delta * 0.05, 0.0)
	_repath -= delta
	if _bump_t > 0.0:
		_bump_t -= delta
		if _bump_t <= 0.0:
			bumps = 0
	if bool(npc.get("is_down")) or npc.get("current_vehicle") != null:
		return
	match mode:
		IDLE:
			if t >= timer:
				_choose_activity(npc)
		DUTY:
			if t >= timer:
				t = 0.0
				timer = _rng.randf_range(4.0, 9.0)
				npc.call("face_position", n.global_position + Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)))
		WANDER:
			if bool(npc.call("has_arrived", 1.0)) or (not bool(npc.call("is_moving")) and not bool(npc.call("is_waiting_to_cross"))):
				if _resume_mode == SIT and bench_key >= 0:
					_resume_mode = IDLE
					if n.global_position.distance_to(bench.origin) < 2.5:
						_arrived_bench(npc)
						return
					_release_bench(npc)
				_set_mode(IDLE, _rng.randf_range(1.5, 6.0))
				npc.set("state_tag", "idle")
				npc.call("face_position", n.global_position + (-n.global_basis.z).rotated(Vector3.UP, _rng.randf_range(-1.2, 1.2)) * 3.0)
			elif t > 120.0:
				_set_mode(IDLE, 1.0)
		SIT:
			if t >= timer or fear > 0.3:
				_release_bench(npc)
				npc.call("stand_normal")
				_start_wander(npc)
		TALK:
			var p_ok: bool = partner != null and is_instance_valid(partner) and partner.is_inside_tree() and n.is_inside_tree() and partner.get("is_dead") != true \
					and partner.global_position.distance_to(n.global_position) < 3.5
			if p_ok:
				npc.call("face_position", partner.global_position)
				npc.set("look_target", partner.global_position + Vector3(0.0, 1.55, 0.0))
				# take turns: one gestures while the other listens
				var talking := fmod(t + (0.0 if npc.get_instance_id() % 2 == 0 else 3.0), 6.0) < 3.0
				npc.set("gesture", 0.9 if talking else 0.15)
			if t >= timer or not p_ok:
				npc.set("gesture", 0.0)
				npc.set("look_target", Vector3.INF)
				partner = null
				_start_wander(npc)
		FLEE:
			if t >= timer or (not bool(npc.call("is_moving")) and t > 1.0):
				if fear > 0.55 and t < 30.0:
					_start_flee(npc, danger_pos, "run")
				else:
					fear = 0.0
					_start_wander(npc)
		COWER:
			if t >= timer:
				npc.call("stand_normal")
				if fear > 0.3 and danger_pos != Vector3.INF:
					_start_flee(npc, danger_pos, "sprint")
				else:
					_start_wander(npc)
		HANDS_UP:
			if float(npc.get("threatened_time")) > 0.0:
				t = 0.0
				var by: Variant = npc.get("threatened_by")
				if by is Node3D and is_instance_valid(by):
					npc.call("face_position", (by as Node3D).global_position)
					danger_pos = (by as Node3D).global_position
			elif t > 1.6:
				npc.call("stand_normal")
				_start_flee(npc, danger_pos, "sprint")
		WITNESS:
			var far := witness_pos == Vector3.INF or n.global_position.distance_to(witness_pos) >= SAFE_DISTANCE
			# Wanted forgets a pending crime after ~15 s: never run longer than 7 s before calling
			if far or t > 7.0 or (not bool(npc.call("is_moving")) and t > 1.5):
				if witness_may_call and not report_sent:
					_begin_call(npc)
				else:
					_start_flee(npc, witness_pos, "run")
		PHONE:
			if _call_interrupted(npc):
				_cancel_call(npc, "chased")
				_start_flee(npc, Game.get_player_position(), "sprint")
				return
			if witness_pos != Vector3.INF:
				npc.call("face_position", n.global_position + (n.global_position - witness_pos))
			if t >= CALL_SECONDS:
				_finish_call(npc)
		ANNOYED:
			if _annoy_by != null and is_instance_valid(_annoy_by):
				npc.call("face_position", _annoy_by.global_position)
				npc.set("look_target", _annoy_by.global_position + Vector3(0.0, 1.5, 0.0))
			if t >= timer:
				npc.set("look_target", Vector3.INF)
				npc.set("gesture", 0.0)
				_start_wander(npc)
		FIGHT:
			_tick_fight(npc, delta)
		RECOVER:
			if t > 8.0:
				_start_wander(npc)
		DAZED:
			if t >= timer:
				npc.set("speed_mult", 1.0)
				npc.set("state_tag", "idle")
				_start_wander(npc)
			elif not bool(npc.call("is_moving")) and t > 2.0 and _rng.randf() < 0.3:
				var walk := _walk()
				if walk != null:
					var p: Vector3 = walk.call("random_point", n.global_position, 4.0, 12.0)
					if p != Vector3.INF:
						npc.call("walk_to", p, "walk")
						npc.set("state_tag", "dazed")


# --- ambient life ----------------------------------------------------------------------------------

func _on_spawned(npc: Node, data: Dictionary) -> void:
	_rng.seed = npc.get_instance_id() ^ 0x5f3759df
	var arch: Variant = npc.get("archetype")
	if arch != null:
		_brave = float((arch as Resource).get("bravery"))
		_tough = bool((arch as Resource).get("fights_back"))
	var fac := str(npc.get("faction"))
	_service = fac in ["medic", "fire", "police"]
	mode = IDLE
	t = 0.0
	timer = _rng.randf_range(0.2, 2.5)
	var activity := str(data.get("activity", ""))
	if _service:
		_set_mode(DUTY, 1.0)
		return
	match activity:
		"talk":
			var p: Variant = data.get("partner", null)
			if p is Node3D and is_instance_valid(p):
				partner = p
				_set_mode(TALK, _rng.randf_range(20.0, 55.0))
				npc.set("state_tag", "talk")
		"sit":
			var b: Variant = data.get("bench", null)
			if b is Transform3D:
				bench = b
				bench_key = int(data.get("bench_key", -1))
				npc.call("sit_at", bench)
				_set_mode(SIT, _rng.randf_range(25.0, 70.0))
		"idle":
			_set_mode(IDLE, _rng.randf_range(3.0, 10.0))
		_:
			_set_mode(IDLE, _rng.randf_range(0.2, 2.0))


func _choose_activity(npc: Node) -> void:
	var sys := Game.get_system("peds")
	if _rng.randf() < 0.12 and sys != null and sys.has_method("claim_bench"):
		var res: Dictionary = sys.call("claim_bench", npc, (npc as Node3D).global_position, 35.0)
		if not res.is_empty():
			bench = res["transform"]
			bench_key = int(res["key"])
			npc.call("walk_to", bench.origin, "walk")
			_set_mode(WANDER, 60.0)
			_resume_mode = SIT
			return
	_start_wander(npc)


func _start_wander(npc: Node) -> void:
	var n := npc as Node3D
	npc.call("stand_normal")
	npc.set("speed_mult", 1.0)
	npc.set("gesture", 0.0)
	npc.set("look_target", Vector3.INF)
	npc.call("clear_face")
	_resume_mode = IDLE
	var walk := _walk()
	var dest := Vector3.INF
	if walk != null:
		dest = walk.call("random_point", n.global_position, 20.0, 75.0)
	if dest == Vector3.INF:
		_set_mode(IDLE, _rng.randf_range(4.0, 10.0))
		npc.set("state_tag", "idle")
		return
	npc.call("walk_to", dest, "walk")
	npc.set("state_tag", "walk")
	_set_mode(WANDER, 0.0)


func _set_mode(m: int, duration: float) -> void:
	mode = m
	t = 0.0
	timer = duration


func _walk() -> Object:
	var w := Game.world
	if w == null or not is_instance_valid(w):
		return null
	var walk: Variant = w.get("walk")
	return walk as Object if walk is Object else null


func _release_bench(npc: Node) -> void:
	if bench_key >= 0:
		var sys := Game.get_system("peds")
		if sys != null and sys.has_method("release_bench"):
			sys.call("release_bench", bench_key)
		bench_key = -1
	if npc != null and is_instance_valid(npc) and str(npc.call("get_pose")) == "sit":
		npc.call("stand_normal")


## Called by the WANDER mode when a bench walk ends.
func _arrived_bench(npc: Node) -> void:
	npc.call("sit_at", bench)
	_set_mode(SIT, _rng.randf_range(25.0, 70.0))


# --- reactions ------------------------------------------------------------------------------------

func _on_noise(npc: Node, data: Dictionary) -> void:
	var kind := str(data.get("kind", ""))
	var inst: Variant = data.get("instigator", null)
	if inst == npc:
		return
	var pos: Vector3 = data.get("position", Vector3.ZERO)
	var dist := float(data.get("distance", 0.0))
	match kind:
		"gunshot", "explosion", "suppressed_gunshot":
			if kind == "suppressed_gunshot" and dist > 8.0:
				return
			_react_danger(npc, pos, 1.0 if kind == "explosion" else clampf(1.15 - dist / 80.0, 0.4, 1.0), inst)
		"scream":
			if mode in [IDLE, WANDER, SIT, TALK, DUTY] and not _service and _rng.randf() < 0.5:
				danger_pos = pos
				fear = maxf(fear, 0.6)
				_release_bench(npc)
				_start_flee(npc, pos, "run")
		"melee":
			if mode in [IDLE, WANDER, SIT, TALK] and dist < 9.0:
				npc.call("face_position", pos)
				npc.set("look_target", pos + Vector3(0.0, 1.4, 0.0))
				if _rng.randf() < 0.4 and not _tough:
					danger_pos = pos
					_release_bench(npc)
					_start_flee(npc, pos, "run")
		"horn", "crash":
			if mode in [IDLE, WANDER, TALK] and dist < 15.0:
				npc.set("look_target", pos + Vector3(0.0, 1.0, 0.0))


func _react_danger(npc: Node, pos: Vector3, strength: float, _who: Variant) -> void:
	fear = maxf(fear, strength)
	danger_pos = pos
	if mode in [WITNESS, PHONE]:
		return                     # already getting away / calling it in
	if mode == FIGHT and _tough and strength < 0.9:
		return
	if mode in [FLEE, COWER, HANDS_UP] and t < 1.5:
		return
	_release_bench(npc)
	npc.set("gesture", 0.0)
	_scream(npc)
	if _service and str(npc.get("faction")) == "police":
		npc.call("face_position", pos)
		return
	var cower_chance := 0.3 * (1.0 - _brave)
	if (npc as Node3D).global_position.distance_to(pos) < 12.0:
		cower_chance += 0.1
	if _rng.randf() < cower_chance:
		npc.call("cower")
		_set_mode(COWER, _rng.randf_range(3.5, 8.0))
	else:
		_start_flee(npc, pos, "sprint")


func _start_flee(npc: Node, from: Vector3, speed: String) -> void:
	npc.call("stand_normal")
	npc.set("speed_mult", 1.0)
	npc.set("gesture", 0.0)
	npc.set("look_target", Vector3.INF)
	if from == Vector3.INF:
		from = (npc as Node3D).global_position + Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1))
	npc.call("flee_from", from, 32.0 + fear * 18.0, speed)
	npc.set("state_tag", "flee")
	_set_mode(FLEE, _rng.randf_range(8.0, 14.0))


func _scream(npc: Node) -> void:
	var now := AiSenses.now()
	if now - _last_scream < SCREAM_MIN_INTERVAL or _rng.randf() > 0.7:
		return
	_last_scream = now
	var n := npc as Node3D
	var female := false
	var vis: Variant = npc.get("visual")
	if vis is Node and is_instance_valid(vis) and (vis as Node).has_method("get_appearance"):
		female = str(((vis as Node).call("get_appearance") as Dictionary).get("body", "m")) == "f"
	Audio.play_at("scream_f" if female else "scream_m", n.global_position + Vector3(0.0, 1.6, 0.0), -2.0,
			_rng.randf_range(0.92, 1.1), 55.0, "SFX")
	Combat.emit_noise(n.global_position, 22.0, "scream", npc)


func _on_threatened(npc: Node, data: Dictionary) -> void:
	var by: Variant = data.get("by", null)
	if by is Node3D and is_instance_valid(by):
		danger_pos = (by as Node3D).global_position
	if mode in [HANDS_UP, COWER, FLEE, PHONE, WITNESS] and t < 30.0:
		if mode == PHONE:
			_cancel_call(npc, "chased")
			_start_flee(npc, danger_pos, "sprint")
		return
	_release_bench(npc)
	npc.set("gesture", 0.0)
	fear = maxf(fear, 0.8)
	var r := _rng.randf()
	if _service and str(npc.get("faction")) == "police":
		npc.call("face_position", danger_pos)
		return
	if _tough:
		if r < 0.5:
			npc.call("surrender")
			_set_mode(HANDS_UP, 0.0)
		else:
			_start_flee(npc, danger_pos, "sprint")
		return
	if r < 0.45:
		npc.call("surrender")
		_set_mode(HANDS_UP, 0.0)
	elif r < 0.7:
		npc.call("cower")
		_set_mode(COWER, _rng.randf_range(4.0, 8.0))
	else:
		_scream(npc)
		_start_flee(npc, danger_pos, "sprint")


func _on_bumped(npc: Node, data: Dictionary) -> void:
	var by: Variant = data.get("by", null)
	if not (by is Node3D) or not is_instance_valid(by):
		return
	if not (mode in [IDLE, WANDER, TALK, ANNOYED, DUTY]):
		return
	var b3 := by as Node3D
	bumps += 1
	_bump_t = 10.0
	if b3.is_in_group("vehicle"):
		npc.call("stop_moving")
		npc.call("flee_from", b3.global_position, 4.0, "run")
		_annoy_by = b3
		_set_mode(ANNOYED, 2.0)
		return
	if _tough and bumps >= 3:
		fight_target = b3
		_set_mode(FIGHT, 25.0)
		return
	npc.call("stop_moving")
	_annoy_by = b3
	npc.set("gesture", 0.6)
	npc.call("play_action", "hit_react", 0.35)
	_set_mode(ANNOYED, _rng.randf_range(1.4, 2.4))
	npc.set("state_tag", "annoyed")


func _on_damaged(npc: Node, data: Dictionary) -> void:
	var attacker: Variant = data.get("attacker", null)
	var info: Dictionary = data.get("info", {})
	var type := str(info.get("type", ""))
	if bool(info.get("carjacked", false)):
		_on_carjacked(npc, {"attacker": attacker if attacker != null else info.get("instigator", null)})
		return
	if bool(info.get("knockout", false)) and bool(npc.get("is_down")):
		# knocked out from behind: no scream, nobody to flee from - wakes up dazed (got_up)
		knocked_out = true
		_cancel_call(npc, "down")
		_release_bench(npc)
		mode = RECOVER
		t = 0.0
		return
	if attacker is Node3D and is_instance_valid(attacker) and attacker != npc:
		danger_pos = (attacker as Node3D).global_position
	else:
		danger_pos = info.get("position", (npc as Node3D).global_position)
	fear = 1.0
	if mode == PHONE:
		_cancel_call(npc, "chased")
	_release_bench(npc)
	if _tough and attacker is Node3D and is_instance_valid(attacker) and attacker != npc \
			and (type == "melee" or (type == "bullet" and _rng.randf() < 0.25)) \
			and (attacker as Node3D).global_position.distance_to((npc as Node3D).global_position) < 12.0:
		fight_target = attacker
		_set_mode(FIGHT, 25.0)
		npc.set("state_tag", "fight")
		return
	if type == "fire" or type == "explosion" or type == "bullet" or type == "melee":
		_scream(npc)
	if mode != FLEE or t > 2.0:
		_start_flee(npc, danger_pos, "sprint")


## Pulled out of the driver seat (TRAFFIC sends "damaged" {info.carjacked}; "carjacked" {attacker}
## is the dedicated event). Tough locals go for the thief (after getting up, when knocked down);
## the others shout and run - the vehicle_theft crime that follows may make them phone it in.
func _on_carjacked(npc: Node, data: Dictionary) -> void:
	var attacker: Variant = data.get("attacker", null)
	var n := npc as Node3D
	if attacker is Node3D and is_instance_valid(attacker) and attacker != npc:
		carjacked_by = attacker
		danger_pos = (attacker as Node3D).global_position
	elif danger_pos == Vector3.INF:
		danger_pos = n.global_position
	fear = 1.0
	_cancel_call(npc, "chased")
	_release_bench(npc)
	npc.set("gesture", 0.0)
	var down := bool(npc.get("is_down"))
	if _tough and carjacked_by != null:
		fight_target = carjacked_by
		if down:
			mode = RECOVER                 # got_up -> FIGHT (fight_target is set)
			t = 0.0
		else:
			_set_mode(FIGHT, 25.0)
			npc.set("state_tag", "fight")
		return
	_scream(npc)
	if down:
		mode = RECOVER                     # got_up -> flee
		t = 0.0
		return
	_start_flee(npc, danger_pos, "sprint")


## Woke up from a knock-out: hand on the head, a few slow steps, no panic, no phone call.
func _start_dazed(npc: Node) -> void:
	npc.call("stand_normal")
	npc.call("stop_moving")
	npc.set("gesture", 0.0)
	npc.set("look_target", Vector3.INF)
	npc.set("speed_mult", 0.55)
	npc.set("state_tag", "dazed")
	fear = 0.2
	_set_mode(DAZED, _rng.randf_range(7.0, 11.0))


func _tick_fight(npc: Node, _delta: float) -> void:
	var n := npc as Node3D
	var tgt := fight_target
	if tgt == null or not is_instance_valid(tgt) or NpcBase.is_dead_node(tgt) or t > timer \
			or tgt.get("current_vehicle") != null:
		fight_target = null
		npc.call("stop_aiming")
		_start_wander(npc)
		return
	var d := n.global_position.distance_to(tgt.global_position)
	if d > 25.0:
		fight_target = null
		_start_wander(npc)
		return
	npc.set("state_tag", "fight")
	if d > 1.35:
		if _repath <= 0.0 or not bool(npc.call("is_moving")):
			_repath = 0.4
			npc.call("move_to", tgt.global_position, "run")
	else:
		npc.call("stop_moving")
		npc.call("face_position", tgt.global_position)
		npc.call("melee", tgt)


# --- witness flow ---------------------------------------------------------------------------------

func _on_crime(npc: Node, data: Dictionary) -> void:
	if _service:
		return
	if mode in [WITNESS, PHONE]:
		return
	var crime := str(data.get("crime", ""))
	if crime == "":
		return
	if _tough and fight_target != null and is_instance_valid(fight_target) and mode in [FIGHT, RECOVER] 			and crime in ["vehicle_theft", "police_vehicle_theft", "assault"]:
		return                         # busy getting even with the thief
	witness_crime = crime
	witness_pos = data.get("position", (npc as Node3D).global_position)
	witness_may_call = bool(data.get("may_call", false))
	report_sent = false
	report_cancelled = ""
	danger_pos = witness_pos
	fear = maxf(fear, 0.7)
	_release_bench(npc)
	npc.call("stand_normal")
	npc.set("gesture", 0.0)
	EventBus.crime_witnessed.emit(crime, witness_pos, npc)
	if crime in ["gunfire", "murder", "cop_murder", "explosion", "assault", "cop_assault"]:
		_scream(npc)
	var n := npc as Node3D
	if n.global_position.distance_to(witness_pos) >= SAFE_DISTANCE:
		if witness_may_call:
			_begin_call(npc)
		else:
			_start_flee(npc, witness_pos, "run")
		return
	npc.call("flee_from", witness_pos, SAFE_DISTANCE + 10.0, "sprint")
	npc.set("state_tag", "witness")
	_set_mode(WITNESS, 0.0)


func _begin_call(npc: Node) -> void:
	npc.call("stop_moving")
	npc.set("phone_pose", true)
	npc.set("state_tag", "phone")
	Audio.play_at("phone_open", (npc as Node3D).global_position + Vector3.UP * 1.5, -8.0, 1.0, 15.0, "SFX")
	_set_mode(PHONE, CALL_SECONDS)


func _call_interrupted(npc: Node) -> bool:
	if bool(npc.get("is_down")) or bool(npc.get("is_dead")):
		return true
	if float(npc.get("threatened_time")) > 0.0:
		return true
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return false
	var n := npc as Node3D
	var d := n.global_position.distance_to(p.global_position)
	if d < CHASE_CANCEL_DISTANCE:
		var pv := Game.get_player_velocity()
		var to_me := n.global_position - p.global_position
		if pv.length() > 1.5 and pv.normalized().dot(to_me.normalized()) > 0.4:
			return true
		if d < 2.5:
			return true
	return false


func _finish_call(npc: Node) -> void:
	npc.set("phone_pose", false)
	report_sent = true
	var sys := Game.get_system("peds")
	if sys != null and sys.has_method("submit_witness_report"):
		sys.call("submit_witness_report", witness_crime, witness_pos, npc)
	elif Wanted.has_method("report_witnessed"):
		Wanted.call("report_witnessed", witness_crime, witness_pos, npc)
	witness_may_call = false
	_start_flee(npc, witness_pos, "run")
	fear = 0.4


func _cancel_call(npc: Node, why: String) -> void:
	if mode == PHONE or mode == WITNESS:
		if witness_may_call and not report_sent:
			report_cancelled = why
			var sys := Game.get_system("peds")
			if sys != null and sys.has_method("note_witness_cancelled"):
				sys.call("note_witness_cancelled", witness_crime, npc, why)
		witness_may_call = false
	if npc != null and is_instance_valid(npc):
		npc.set("phone_pose", false)
