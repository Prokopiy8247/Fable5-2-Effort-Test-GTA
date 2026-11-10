extends Node3D
## World system "emergency" (BootManifest, ARCHITECTURE 4 / spec 35A): ambulances and fire trucks
## that react to incidents near the player. Atmospheric, bounded, never touches the wanted system.
##
## Incidents (EventBus, within RESPOND_RADIUS of the player):
##   medical  npc_died (the corpse is held until the medics are done), npc_injured with a takedown
##            knock-out (kept unconscious until treated) or a body that is down and badly hurt
##   fire     vehicle_destroyed (the wreck smoulders until extinguished), fire_started, big
##            explosions; severities add up per area, a fire truck comes at FIRE_THRESHOLD
## Dispatch (one ambulance and one fire truck at a time; at most MAX_PENDING incidents queue):
##   after a short delay (and when no gunfire is going on at the scene) a vehicle spawns OUT OF
##   VIEW on a lane 85-170 m away, two responders seated (persistent NPCs with
##   AiResponderBrain), and drives a RoadGraph lane route with the siren on (AiEmergencyDriver:
##   the W2.1 ai_controller - traffic pulls over for siren_on vehicles on its own).
## On scene:
##   medics walk to the bodies, kneel (CPR pose) ~9 s; knocked-out patients are treated and get
##   up (dazed); corpses are released to the normal clean-up when the crew leaves. Firefighters
##   take positions 6.5 m from the fire, spray (water jets: emergency_fx.gd + Fx steam) until the
##   fire is out: our own smoulder fire is stopped, so are fire handles attached to the wreck, and
##   Fx.extinguish(pos, r) is called when the Fx module offers it.
## Leaving: the crew boards, the vehicle drives away calmly (siren off) and is despawned out of
##   view (DESPAWN_FAR / DESPAWN_ALWAYS). Danger (gunfire, explosions, attacks, a gun pointed at a
##   responder) aborts the job: the crew flees / leaves. Stealing the vehicle is a normal vehicle
##   theft (PLAYER module); the stranded crew walks off and is despawned out of view.
##
## API: set_enabled(on), get_active_responses() -> Array[Dictionary], reset_for_respawn(),
## clear_all(), dispatch(kind, position) -> bool (admin / tests), get_debug_info(), stats.

const DriverScript := preload("res://gta/code/ai/emergency_driver.gd")
const BrainScript := preload("res://gta/code/ai/emergency_responder_brain.gd")
const FxScript := preload("res://gta/code/ai/emergency_fx.gd")

const KIND_DEF := {
	"medical": {"spec": "ambulance", "arch": "medic", "crew": 2, "delay": Vector2(5.0, 9.0)},
	"fire": {"spec": "firetruck", "arch": "firefighter", "crew": 2, "delay": Vector2(4.0, 7.0)},
}
const RESPOND_RADIUS := 110.0        ## incidents farther than this from the player are ignored
const CANCEL_RADIUS := 190.0         ## a pending incident is dropped when the player is this far away
const MERGE_RADIUS := 30.0
const MAX_PENDING := 4
const MAX_PATIENTS := 4
const MAX_HELD_CORPSES := 5
const INCIDENT_TTL := 150.0          ## a pending incident older than this is dropped
const FIRE_THRESHOLD := 0.9
const SPAWN_MIN := 85.0
const SPAWN_MAX := 170.0
const MAX_ROUTE := 460.0
const DESPAWN_FAR := 150.0           ## leaving vehicles / strays beyond this and unseen are removed
const DESPAWN_ALWAYS := 260.0
const STRAY_NEAR := 45.0             ## stray responders are removed out of view beyond this
const UNSAFE_GUNFIRE := 60.0         ## gunfire this close to a scene delays the dispatch ...
const UNSAFE_SECONDS := 12.0         ## ... while it happened within the last seconds
const UNSAFE_MAX_WAIT := 40.0
const DRIVE_TIMEOUT := 95.0          ## seconds of driving before the crew gets out where it is
const WORK_TIMEOUT := 50.0
const BOARD_TIMEOUT := 30.0
const LEAVE_TIMEOUT := 120.0
const TREAT_DEAD := Vector2(8.0, 11.0)
const TREAT_ALIVE := Vector2(5.5, 7.5)
const FIRE_WORK := 16.0              ## spray-seconds (summed over the sprayers) to put a fire out
const FIRE_STAND := 6.5              ## firefighters stand this far from the fire
const SMOULDER_SECONDS := 140.0      ## our wreck fire burns at most this long without a fire truck
const TICK_NEAR := 1.0 / 15.0
const TICK_FAR := 1.0 / 5.0
const STATE_TICK := 0.25

enum State { DRIVING, ARRIVED, WORKING, RETURNING, LEAVING, STRANDED, DONE }
const STATE_NAMES: Array[String] = ["driving", "arrived", "working", "returning", "leaving", "stranded", "done"]


## One dispatched vehicle + crew.
class Response extends RefCounted:
	var id: int = 0
	var kind: String = ""
	var state: int = 0
	var state_t: float = 0.0
	var age: float = 0.0
	var vehicle: RigidBody3D = null
	var driver: RefCounted = null          ## AiEmergencyDriver (the vehicle's ai_controller)
	var crew: Array[Node3D] = []
	var incident: Dictionary = {}
	var scene: Vector3 = Vector3.ZERO
	var vehicle_lost: bool = false        ## stolen / destroyed / released
	var tick_acc: float = 0.0
	var arrive_time: float = -1.0         ## response age when the vehicle stopped at the scene
	var assign: Dictionary = {}           ## crew instance id -> {target, focus, kind: "patient"|"fire", patient, working, worked, jet}
	var fire_work: float = 0.0
	var fire_out: bool = false
	var fire_out_t: float = 0.0
	var spawn_dist: float = 0.0
	var log: PackedStringArray = PackedStringArray()


var enabled: bool = true
## Spawn distance band from the scene and the minimum distance from the player (tests / admin may
## narrow them; spawns are always out of the camera's view).
var spawn_range: Vector2 = Vector2(SPAWN_MIN, SPAWN_MAX)
var spawn_player_min: float = 60.0
var stats: Dictionary = {
	"incidents": 0, "merged": 0, "dispatched": 0, "arrived": 0, "treated": 0, "revived": 0,
	"bodies_attended": 0, "fires_out": 0, "aborted": 0, "despawned": 0, "spawn_fail": 0,
	"stolen": 0, "cancelled": 0, "held_corpses": 0,
}
var incidents: Array[Dictionary] = []
var responses: Array[Response] = []
var strays: Array[Node3D] = []           ## responders on foot that lost their job (despawned out of view)
var fx: Node3D = null

var _clock: float = 0.0
var _inc_t: float = 0.0
var _next_id: int = 1
var _gunfire: Array = []                 ## [position, clock] of recent gunshots / explosions
var _rng := RandomNumberGenerator.new()
var _view_q: PhysicsRayQueryParameters3D = null
var _shape_q: PhysicsShapeQueryParameters3D = null
var _sphere := SphereShape3D.new()
var _warned: Dictionary = {}


func _ready() -> void:
	process_physics_priority = 6


func setup() -> void:
	_rng.seed = Game.rng.randi() ^ 0x45a7
	fx = FxScript.new()
	fx.name = "EmergencyFx"
	add_child(fx)
	EventBus.npc_died.connect(_on_npc_died)
	EventBus.npc_injured.connect(_on_npc_injured)
	EventBus.vehicle_destroyed.connect(_on_vehicle_destroyed)
	EventBus.fire_started.connect(_on_fire_started)
	EventBus.explosion.connect(_on_explosion)
	EventBus.noise_emitted.connect(_on_noise)
	EventBus.player_entered_vehicle.connect(_on_player_entered_vehicle)
	EventBus.vehicle_stolen.connect(_on_vehicle_stolen)
	# brain + driver scripts are preloaded; warm the vehicle models so the first dispatch does not hitch
	var vm := Game.get_system("vehicles")
	if vm != null and vm.has_method("preload_spec"):
		for k: String in KIND_DEF.keys():
			vm.call("preload_spec", str(KIND_DEF[k]["spec"]))


func _exit_tree() -> void:
	for inc in incidents:
		_release_incident(inc)
	incidents.clear()


# =================================================================================================
# public API
# =================================================================================================

func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		clear_all()


## Every live response: {id, kind, state, vehicle, crew, scene, patients, fire_out, arrived,
## time_on_scene, age, remaining_route (m), siren}.
func get_active_responses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in responses:
		var patients: Array = []
		for p: Dictionary in (r.incident.get("patients", []) as Array):
			var n: Variant = p.get("node")
			patients.append({"node": n if (n != null and is_instance_valid(n)) else null, "dead": bool(p.get("dead", false)),
					"treated": bool(p.get("treated", false))})
		var siren := false
		if r.vehicle != null and is_instance_valid(r.vehicle):
			siren = r.vehicle.get("siren_on") == true
		out.append({"id": r.id, "kind": r.kind, "state": STATE_NAMES[r.state], "vehicle": r.vehicle if is_instance_valid(r.vehicle) else null,
				"crew": r.crew.filter(func(c: Variant) -> bool: return is_instance_valid(c)), "scene": r.scene,
				"patients": patients, "fire_out": r.fire_out, "arrived": r.arrive_time >= 0.0,
				"time_on_scene": (r.age - r.arrive_time) if r.arrive_time >= 0.0 else 0.0, "age": r.age,
				"remaining_route": float(r.driver.call("remaining")) if r.driver != null else 0.0, "siren": siren,
				"spawn_dist": r.spawn_dist})
	return out


## Pending (not yet dispatched) incidents: {kind, position, severity, patients, age, dispatch_in}.
func get_pending_incidents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for inc in incidents:
		out.append({"kind": inc["kind"], "position": inc["pos"], "severity": inc["severity"],
				"patients": (inc["patients"] as Array).size(), "age": _clock - float(inc["created"]),
				"dispatch_in": float(inc["dispatch_at"]) - _clock})
	return out


## Death / arrest: everything transient goes (responses, pending incidents, held corpses, fires).
func reset_for_respawn() -> void:
	clear_all()


func clear_all() -> void:
	for r in responses.duplicate():
		_despawn_response(r)
	responses.clear()
	for inc in incidents:
		_release_incident(inc)
	incidents.clear()
	for s in strays:
		_free_npc(s)
	strays.clear()
	if fx != null and fx.has_method("stop_all"):
		fx.call("stop_all")


## Admin / tests: an incident of `kind` ("medical" | "fire") at `position`, dispatched right away
## (the usual scene and slot rules still apply). Medical incidents adopt bodies lying near it.
func dispatch(kind: String, position: Vector3) -> bool:
	if not KIND_DEF.has(kind) or not enabled:
		return false
	var inc := _incident_for(kind, position, true)
	if inc.is_empty():
		return false
	inc["severity"] = maxf(float(inc["severity"]), FIRE_THRESHOLD)
	inc["dispatch_at"] = _clock
	inc["forced"] = true
	if kind == "medical":
		_adopt_bodies_near(inc, position, 14.0)
	return true


func get_debug_info() -> Dictionary:
	var d := stats.duplicate()
	d["pending"] = incidents.size()
	d["responses"] = responses.size()
	d["strays"] = strays.size()
	d["held"] = _held_count()
	var rs: Array = []
	for r in responses:
		var dd: Dictionary = r.driver.call("get_debug_info") if r.driver != null else {}
		rs.append("%s#%d %s t=%.0f drv=%s v=%.1f rem=%.0f %s" % [r.kind, r.id, STATE_NAMES[r.state], r.age,
				str(dd.get("mode", "-")), float(dd.get("speed", 0.0)), float(dd.get("remaining", 0.0)), str(dd.get("block", ""))])
	d["list"] = rs
	return d


# =================================================================================================
# incidents
# =================================================================================================

func _near_player(pos: Vector3, radius: float) -> bool:
	if not Game.has_player():
		return false
	return _flat(Game.get_player_position(), pos) <= radius


## The incident of `kind` within MERGE_RADIUS of pos (pending ones first), or a new one.
## {} when the queue is full.
func _incident_for(kind: String, pos: Vector3, create: bool) -> Dictionary:
	for inc in incidents:
		if inc["kind"] == kind and _flat(inc["pos"], pos) <= MERGE_RADIUS:
			stats["merged"] = int(stats["merged"]) + 1
			return inc
	if not create:
		return {}
	var pending := 0
	for inc in incidents:
		if inc["kind"] == kind:
			pending += 1
	if pending >= MAX_PENDING:
		return {}
	var def: Dictionary = KIND_DEF[kind]
	var delay: Vector2 = def["delay"]
	var inc := {"kind": kind, "pos": pos, "severity": 0.0, "patients": [], "created": _clock,
			"dispatch_at": _clock + _rng.randf_range(delay.x, delay.y), "wreck": null, "smoulder": null,
			"fires": [], "forced": false, "unsafe_wait": 0.0}
	incidents.append(inc)
	stats["incidents"] = int(stats["incidents"]) + 1
	return inc


func _held_count() -> int:
	var n := 0
	for inc in incidents:
		for p: Dictionary in (inc["patients"] as Array):
			if bool(p.get("held", false)):
				n += 1
	for r in responses:
		for p: Dictionary in (r.incident.get("patients", []) as Array):
			if bool(p.get("held", false)):
				n += 1
	return n


func _is_patient(npc: Node) -> bool:
	for inc in incidents:
		for p: Dictionary in (inc["patients"] as Array):
			if p.get("node") == npc:
				return true
	for r in responses:
		for p: Dictionary in (r.incident.get("patients", []) as Array):
			if p.get("node") == npc:
				return true
	return false


func _add_patient(inc: Dictionary, npc: Node3D, dead: bool) -> void:
	var list: Array = inc["patients"]
	for p: Dictionary in list:
		if p.get("node") == npc:
			p["dead"] = dead or bool(p.get("dead", false))
			_hold_if_dead(p)
			return
	if list.size() >= MAX_PATIENTS:
		return
	var p := {"node": npc, "dead": dead, "treated": false, "held": false, "pos": _body_pos(npc)}
	list.append(p)
	inc["severity"] = float(inc["severity"]) + 1.0
	_hold_if_dead(p)


func _hold_if_dead(p: Dictionary) -> void:
	var n: Variant = p.get("node")
	if not bool(p.get("dead", false)) or bool(p.get("held", false)) or n == null or not is_instance_valid(n):
		return
	if _held_count() >= MAX_HELD_CORPSES:
		return
	if (n as Node).has_method("hold_corpse"):
		(n as Node).call("hold_corpse", true)
		p["held"] = true
		stats["held_corpses"] = int(stats["held_corpses"]) + 1


func _release_patient(p: Dictionary) -> void:
	var n: Variant = p.get("node")
	if bool(p.get("held", false)) and n != null and is_instance_valid(n) and (n as Node).has_method("hold_corpse"):
		(n as Node).call("hold_corpse", false)
	p["held"] = false


func _release_incident(inc: Dictionary) -> void:
	for p: Dictionary in (inc.get("patients", []) as Array):
		_release_patient(p)
	var sm: Variant = inc.get("smoulder", null)
	if sm != null and is_instance_valid(sm) and (sm as Object).has_method("stop"):
		(sm as Object).call("stop")
	inc["smoulder"] = null


func _is_ours(n: Node) -> bool:
	if n == null:
		return false
	for r in responses:
		if r.vehicle == n or r.crew.has(n):
			return true
	return strays.has(n)


func _on_npc_died(npc: Node3D, _killer: Node, _info: Dictionary) -> void:
	if not enabled or not Game.is_ready or npc == null or not is_instance_valid(npc):
		return
	if _is_ours(npc):
		return
	var fac := str(npc.get("faction"))
	if fac == "medic" or fac == "fire":
		return
	if npc.get("current_vehicle") != null:
		return                         # slumped in a seat: no body on the street
	var pos := _body_pos(npc)
	if not _near_player(pos, RESPOND_RADIUS) or Game.is_in_water(pos + Vector3.UP * 0.3):
		return
	var inc := _incident_for("medical", pos, true)
	if inc.is_empty():
		return
	_add_patient(inc, npc, true)


func _on_npc_injured(npc: Node3D, _attacker: Node, info: Dictionary) -> void:
	if not enabled or not Game.is_ready or npc == null or not is_instance_valid(npc):
		return
	if _is_ours(npc) or npc.get("is_dead") == true:
		return
	var fac := str(npc.get("faction"))
	if fac == "medic" or fac == "fire":
		return
	var ko := bool(info.get("knockout", false))
	var hp := float(npc.get("health"))
	var mhp := maxf(float(npc.get("max_health")), 1.0)
	if not ko:
		if hp / mhp < 0.4:
			# npc_injured fires before the body falls (knock-down / ragdoll): decide a frame later
			_check_injured.call_deferred(npc)
		return
	_add_injured(npc, true)


func _check_injured(npc: Node3D) -> void:
	if npc == null or not is_instance_valid(npc) or npc.get("is_dead") == true or npc.get("is_down") != true:
		return
	if _is_patient(npc):
		return
	_add_injured(npc, false)


func _add_injured(npc: Node3D, ko: bool) -> void:
	var pos := _body_pos(npc)
	if not _near_player(pos, RESPOND_RADIUS):
		return
	var inc := _incident_for("medical", pos, true)
	if inc.is_empty():
		return
	_add_patient(inc, npc, false)
	if ko and npc.has_method("extend_knockout"):
		npc.call("extend_knockout", 70.0)        # unconscious until the medics arrive (capped)


func _on_vehicle_destroyed(vehicle: Node3D, _instigator: Node) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	for r in responses:
		if r.vehicle == vehicle:
			_vehicle_lost(r, "destroyed")
	if not enabled or not Game.is_ready:
		return
	var vc := str(vehicle.get("vehicle_class"))
	if vc == "bicycle" or vc == "boat" or Game.is_in_water(vehicle.global_position):
		return
	var pos := vehicle.global_position
	if not _near_player(pos, RESPOND_RADIUS):
		return
	var inc := _incident_for("fire", pos, true)
	if inc.is_empty():
		return
	inc["severity"] = float(inc["severity"]) + 1.0
	if inc["wreck"] == null or not is_instance_valid(inc["wreck"]):
		inc["wreck"] = vehicle
		inc["pos"] = pos


func _on_fire_started(position: Vector3, source: Node) -> void:
	if not enabled or not Game.is_ready or not _near_player(position, RESPOND_RADIUS):
		return
	if Game.is_in_water(position):
		return
	var inc := _incident_for("fire", position, true)
	if inc.is_empty():
		return
	var veh := source != null and is_instance_valid(source) and source.is_in_group("vehicle")
	inc["severity"] = float(inc["severity"]) + (0.6 if veh else 0.45)
	(inc["fires"] as Array).append(position)


func _on_explosion(position: Vector3, radius: float, _instigator: Node) -> void:
	if not enabled or not Game.is_ready or not _near_player(position, RESPOND_RADIUS):
		return
	if Game.is_in_water(position) or radius < 2.5:
		return
	var inc := _incident_for("fire", position, true)
	if inc.is_empty():
		return
	inc["severity"] = float(inc["severity"]) + (0.6 if radius >= 4.5 else 0.3)


## Gunfire makes a scene unsafe (dispatch waits). Explosions do not: they are what fire trucks
## come for (responders on scene still run from a NEW explosion close to them - their brain).
func _on_noise(position: Vector3, _radius: float, kind: String, _instigator: Node) -> void:
	if kind == "gunshot" or kind == "suppressed_gunshot":
		_note_danger(position)


func _note_danger(position: Vector3) -> void:
	# keep only a handful of recent danger points (no growth)
	if _gunfire.size() >= 16:
		_gunfire.remove_at(0)
	_gunfire.append([position, _clock])


func _scene_unsafe(pos: Vector3) -> bool:
	for g: Array in _gunfire:
		if _clock - float(g[1]) <= UNSAFE_SECONDS and _flat(g[0], pos) <= UNSAFE_GUNFIRE:
			return true
	return false


## Admin "dispatch" next to bodies that are already there.
func _adopt_bodies_near(inc: Dictionary, pos: Vector3, radius: float) -> void:
	var peds := Game.get_system("peds")
	if peds == null or not peds.has_method("get_npcs"):
		return
	for n: Variant in peds.call("get_npcs"):
		if n == null or not is_instance_valid(n) or _is_ours(n):
			continue
		var nn := n as Node3D
		if _flat(_body_pos(nn), pos) > radius:
			continue
		if nn.get("is_dead") == true and nn.get("current_vehicle") == null:
			_add_patient(inc, nn, true)
		elif nn.get("knocked_out") == true or (nn.get("is_down") == true and float(nn.get("health")) < float(nn.get("max_health")) * 0.4):
			_add_patient(inc, nn, false)


func _body_pos(npc: Node) -> Vector3:
	if npc == null or not is_instance_valid(npc):
		return Vector3.INF
	if npc.has_method("get_body_position"):
		var v: Variant = npc.call("get_body_position")
		if v is Vector3:
			return v
	return (npc as Node3D).global_position


## Patients that still need the medics (corpse still there, knocked out, badly hurt and down).
func _patients_needing_care(inc: Dictionary) -> int:
	var n := 0
	for p: Dictionary in (inc["patients"] as Array):
		if bool(p.get("treated", false)):
			continue
		var node: Variant = p.get("node")
		if node == null or not is_instance_valid(node) or not (node as Node).is_inside_tree():
			continue
		if bool(p.get("dead", false)) or node.get("is_dead") == true:
			if node.get("current_vehicle") == null:
				n += 1
		elif node.get("is_down") == true or node.get("knocked_out") == true:
			n += 1
	return n


func _tick_incidents(dt: float) -> void:
	for i in range(incidents.size() - 1, -1, -1):
		var inc := incidents[i]
		var age := _clock - float(inc["created"])
		var pos: Vector3 = inc["pos"]
		var drop := age > INCIDENT_TTL or not _near_player(pos, CANCEL_RADIUS)
		if inc["kind"] == "medical" and not drop and _clock >= float(inc["dispatch_at"]) and _patients_needing_care(inc) == 0:
			drop = true
		if inc["kind"] == "fire":
			_tick_smoulder(inc)
			if not drop and age > 25.0 and float(inc["severity"]) < FIRE_THRESHOLD and not bool(inc["forced"]):
				drop = true            # a small fire that nobody made bigger
		if drop:
			stats["cancelled"] = int(stats["cancelled"]) + 1
			_release_incident(inc)
			incidents.remove_at(i)
			continue
		if _clock < float(inc["dispatch_at"]):
			continue
		if inc["kind"] == "fire" and float(inc["severity"]) < FIRE_THRESHOLD:
			continue
		if _slot_busy(inc["kind"]):
			continue
		if _scene_unsafe(pos) and float(inc["unsafe_wait"]) < UNSAFE_MAX_WAIT:
			inc["unsafe_wait"] = float(inc["unsafe_wait"]) + dt
			continue
		if _dispatch_now(inc):
			incidents.remove_at(i)
		else:
			inc["dispatch_at"] = _clock + 3.0     # no spawn spot right now: try again


func _slot_busy(kind: String) -> bool:
	for r in responses:
		if r.kind == kind and r.state != State.DONE:
			return true
	return false


## A destroyed vehicle keeps smouldering (our own Fx fire, low damage, parented to the wreck) once
## its own wreck fire is out, so the fire brigade has something to put out.
func _tick_smoulder(inc: Dictionary) -> void:
	var w: Variant = inc.get("wreck", null)
	if w == null or not is_instance_valid(w) or not (w as Node3D).is_inside_tree():
		return
	var sm: Variant = inc.get("smoulder", null)
	if sm != null and is_instance_valid(sm):
		return
	if _clock - float(inc["created"]) > SMOULDER_SECONDS * 0.5 or bool(inc.get("smoulder_done", false)):
		return
	if _wreck_fires(w as Node3D) > 0:
		return
	var wn := w as Node3D
	var at := wn.global_position + Vector3.UP * 0.6
	if wn.has_method("get_engine_position"):
		var e: Variant = wn.call("get_engine_position")
		if e is Vector3:
			at = e
	var h: Variant = Fx.spawn_fire(at, SMOULDER_SECONDS, wn, 0.8)
	if h is Node3D and is_instance_valid(h):
		(h as Node3D).set("damage_per_second", 5.0)
		(h as Node3D).set("vehicle_damage_per_second", 0.0)
		(h as Node3D).set("radius", 1.3)
		inc["smoulder"] = h
		inc["smoulder_done"] = true


## Fire handles attached to a wreck (Fx parents a fire to the vehicle it burns on: FX.md).
static func _wreck_fires(w: Node3D) -> int:
	var n := 0
	for c in w.get_children():
		if c.get("fx_kind") == "fire" and not c.is_queued_for_deletion():
			n += 1
	return n


# =================================================================================================
# dispatch
# =================================================================================================

func _dispatch_now(inc: Dictionary) -> bool:
	var kind: String = inc["kind"]
	var def: Dictionary = KIND_DEF[kind]
	var vm := Game.get_system("vehicles")
	if vm == null or not Game.has_system("peds"):
		_warn_once("deps", "EmergencySystem: needs the vehicles and peds systems")
		return false
	if vm.has_method("can_spawn") and not bool(vm.call("can_spawn", str(def["spec"]))):
		_warn_once("spec_" + kind, "EmergencySystem: vehicle spec '%s' cannot be spawned" % str(def["spec"]))
		return false
	var scene: Vector3 = inc["pos"]
	if kind == "medical":
		# aim at the patients' centre (bodies may have slid / been moved)
		var c := Vector3.ZERO
		var k := 0
		for p: Dictionary in (inc["patients"] as Array):
			var node: Variant = p.get("node")
			if node != null and is_instance_valid(node):
				c += _body_pos(node)
				k += 1
		if k > 0:
			scene = c / float(k)
	elif inc["wreck"] != null and is_instance_valid(inc["wreck"]):
		scene = (inc["wreck"] as Node3D).global_position
	var spot := _find_spawn(scene)
	if spot.is_empty():
		stats["spawn_fail"] = int(stats["spawn_fail"]) + 1
		return false
	var xf: Transform3D = spot["xf"]
	xf.origin.y += 0.35
	var night := WorldClock.get_daylight() < 0.3 if WorldClock.has_method("get_daylight") else false
	var v := Game.spawn_vehicle(str(def["spec"]), xf, {"owner_tag": "emergency", "engine_on": true,
			"headlights": 1 if night else 0, "siren": true})
	if v == null or not (v is RigidBody3D):
		stats["spawn_fail"] = int(stats["spawn_fail"]) + 1
		return false
	var crew: Array[Node3D] = []
	var seats := 2
	if v.has_method("get_seat_count"):
		seats = maxi(int(v.call("get_seat_count")), 1)
	for s in mini(int(def["crew"]), seats):
		var npc := Game.spawn_npc(str(def["arch"]), xf.origin + Vector3.UP, {"vehicle": v, "seat": s,
				"persistent": true, "brain": BrainScript})
		if npc != null and is_instance_valid(npc):
			crew.append(npc)
			var b: Variant = npc.get("brain")
			if b is Node and is_instance_valid(b):
				(b as Node).set("system", self)
				(b as Node).set("vehicle", v)
	if crew.is_empty() or v.get("driver") != crew[0]:
		for c in crew:
			_free_npc(c)
		_despawn_vehicle(v)
		stats["spawn_fail"] = int(stats["spawn_fail"]) + 1
		return false
	var r := Response.new()
	r.id = _next_id
	_next_id += 1
	r.kind = kind
	r.vehicle = v as RigidBody3D
	r.crew = crew
	r.incident = inc
	r.scene = scene
	r.spawn_dist = _flat(xf.origin, scene)
	var drv: RefCounted = DriverScript.new()
	drv.call("setup", self, v, crew)
	r.driver = drv
	v.set_meta("ai_controller", drv)
	v.set_meta("emergency_response", r.id)
	v.add_to_group("emergency_vehicle")
	var stop_before := 9.0 if kind == "medical" else 11.0
	if not bool(drv.call("drive_to", scene, true, stop_before)):
		drv.call("release_vehicle", v, "despawn")
		for c in crew:
			_free_npc(c)
		_despawn_vehicle(v)
		stats["spawn_fail"] = int(stats["spawn_fail"]) + 1
		return false
	if v.has_method("set_siren"):
		v.call("set_siren", true)
	responses.append(r)
	stats["dispatched"] = int(stats["dispatched"]) + 1
	_log(r, "dispatched %s from %.0f m (route %.0f m)" % [str(def["spec"]), r.spawn_dist, float(drv.call("remaining"))])
	# knocked-out patients stay down until the medics are there
	for p: Dictionary in (inc["patients"] as Array):
		var node: Variant = p.get("node")
		if node != null and is_instance_valid(node) and node.get("knocked_out") == true and (node as Node).has_method("extend_knockout"):
			(node as Node).call("extend_knockout", 75.0)
	return true


## A lane spot SPAWN_MIN..SPAWN_MAX from the scene, out of the camera's view, free of vehicles,
## whose lane route to the scene is not absurdly long. {} when none was found.
func _find_spawn(scene: Vector3) -> Dictionary:
	var roads := _roads()
	if roads == null:
		return {}
	var lanes: Array = roads.get("lanes")
	var target: Dictionary = roads.call("get_nearest_lane", scene, 70.0)
	if target.is_empty():
		return {}
	var best := {}
	var best_score := -INF
	for attempt in 14:
		var dmin := spawn_range.x if attempt < 10 else spawn_range.x + 40.0
		var dmax := spawn_range.y if attempt < 10 else spawn_range.y + 70.0
		var r: Dictionary = roads.call("random_lane_point", scene, dmin, dmax)
		if r.is_empty():
			continue
		var lane: Dictionary = lanes[int(r["lane_id"])]
		var k := str(lane.get("kind", ""))
		if k == "dirt" or k == "runway" or k == "taxiway" or k == "alley":
			continue
		var off := float(r["offset"])
		if off < 8.0 or off > float(lane["length"]) - 14.0:
			continue
		var xf: Transform3D = r["transform"]
		var p := xf.origin
		if Game.is_in_water(p) or _in_view(p + Vector3.UP * 1.5):
			continue
		if Game.has_player() and _flat(p, Game.get_player_position()) < spawn_player_min:
			continue
		if _vehicle_near(p, 8.0):
			continue
		var ids: PackedInt32Array = roads.call("find_lane_route", int(r["lane_id"]), int(target["lane_id"]))
		if ids.is_empty():
			continue
		var length := float(lane["length"]) - off + float(target["offset"])
		for i in range(1, ids.size() - 1):
			length += float((lanes[ids[i]] as Dictionary)["length"])
		if length > MAX_ROUTE:
			continue
		var to := scene - p
		to.y = 0.0
		var score := -length * 0.01 + _rng.randf() * 0.5
		if to.length() > 0.1:
			score += (-xf.basis.z).dot(to.normalized()) * 0.6
		if score > best_score:
			best_score = score
			best = {"xf": xf, "lane": int(r["lane_id"]), "route": length}
		if attempt >= 4 and not best.is_empty():
			break
	return best


# =================================================================================================
# main loop
# =================================================================================================

func _physics_process(delta: float) -> void:
	if not Game.is_ready:
		return
	_clock += delta
	_inc_t -= delta
	if _inc_t <= 0.0:
		_inc_t = 0.5
		if enabled:
			_tick_incidents(0.5)
		_tick_strays()
		if fx != null:
			fx.call("reap")
	for i in range(responses.size() - 1, -1, -1):
		var r := responses[i]
		r.age += delta
		r.state_t += delta
		_drive(r, delta)
		_tick_work_fx(r, delta)
		r.tick_acc += delta
		if r.tick_acc >= STATE_TICK:
			var step := r.tick_acc
			r.tick_acc = 0.0
			_update_response(r, step)
		if r.state == State.DONE:
			responses.erase(r)            # (_despawn_response may have taken it out already)


func _drive(r: Response, delta: float) -> void:
	if r.driver == null or r.vehicle_lost or not is_instance_valid(r.vehicle):
		return
	var near := Game.has_player() and _flat(r.vehicle.global_position, Game.get_player_position()) < 90.0
	var acc := float(r.driver.get("think_acc")) + delta
	var interval := TICK_NEAR if near else TICK_FAR
	if acc >= interval:
		r.driver.set("think_acc", 0.0)
		r.driver.call("tick", acc)
	else:
		r.driver.set("think_acc", acc)


func _set_state(r: Response, s: int) -> void:
	if r.state == s:
		return
	_log(r, "%s -> %s" % [STATE_NAMES[r.state], STATE_NAMES[s]])
	r.state = s
	r.state_t = 0.0


func _update_response(r: Response, dt: float) -> void:
	# crew bookkeeping: dead / freed members drop out (corpses go to the normal clean-up)
	for i in range(r.crew.size() - 1, -1, -1):
		var c := r.crew[i]
		if c == null or not is_instance_valid(c):
			r.crew.remove_at(i)
			continue
		if c.get("is_dead") == true:
			_stop_jet(r, c)
			c.set("persistent", false)
			r.crew.remove_at(i)
	var vehicle_ok: bool = not r.vehicle_lost and r.vehicle != null and is_instance_valid(r.vehicle) \
			and r.vehicle.get("destroyed") != true and r.vehicle.is_inside_tree()
	if not vehicle_ok and r.state != State.STRANDED and r.state != State.DONE:
		_strand(r, "vehicle lost")
		return
	if r.state in [State.DRIVING, State.ARRIVED, State.WORKING] and _any_aborted(r):
		stats["aborted"] = int(stats["aborted"]) + 1
		_log(r, "aborted (%s)" % _abort_reason(r))
		_begin_return(r)
		return
	if r.kind == "fire" and not r.fire_out and r.state <= State.WORKING:
		_tick_smoulder(r.incident)
	match r.state:
		State.DRIVING:
			_update_driving(r)
		State.ARRIVED:
			_update_arrived(r)
		State.WORKING:
			_update_working(r, dt)
		State.RETURNING:
			_update_returning(r)
		State.LEAVING:
			_update_leaving(r)
		State.STRANDED:
			if r.crew.is_empty() or r.state_t > 5.0:
				for c in r.crew:
					if not strays.has(c):
						strays.append(c)
				r.crew.clear()
				_release_incident(r.incident)
				_set_state(r, State.DONE)


func _update_driving(r: Response) -> void:
	var drv := r.driver
	if r.crew.is_empty() or drv.call("seated_driver") == null:
		# nobody of ours can drive (killed / pulled out): the rest walks
		_strand(r, "no driver")
		return
	var vpos := r.vehicle.global_position
	var close := _flat(vpos, r.scene) < 22.0 and absf(float(drv.call("get_speed"))) < 1.5
	if bool(drv.get("arrived")) or close:
		drv.call("park")
		r.arrive_time = r.age
		stats["arrived"] = int(stats["arrived"]) + 1
		_log(r, "arrived %.0f m from the scene after %.1f s" % [_flat(vpos, r.scene), r.age])
		_set_state(r, State.ARRIVED)
		return
	if int(drv.get("mode")) != 0:          # not ROUTE: the plan failed / ended early
		if not bool(drv.call("drive_to", r.scene, true, 9.0 if r.kind == "medical" else 11.0)):
			if _flat(vpos, r.scene) < 70.0:
				drv.call("park")
				r.arrive_time = r.age
				_set_state(r, State.ARRIVED)
			elif not _in_view(vpos + Vector3.UP):
				_log(r, "no route - despawned")
				_requeue(r)
		return
	var hopeless := bool(drv.call("is_hopeless")) or float(drv.get("drive_time")) > DRIVE_TIMEOUT
	if hopeless:
		if _flat(vpos, r.scene) < 75.0:
			drv.call("park")              # stuck close by: the crew walks the rest
			r.arrive_time = r.age
			_set_state(r, State.ARRIVED)
		elif not _in_view(vpos + Vector3.UP):
			_log(r, "stuck far away - despawned, incident queued again")
			_requeue(r)


## The vehicle could not get there: remove it (out of view) and put the incident back in the queue.
func _requeue(r: Response) -> void:
	var inc := r.incident
	r.incident = {}
	_despawn_response(r)
	if not inc.is_empty() and incidents.size() < MAX_PENDING * 2:
		inc["dispatch_at"] = _clock + 4.0
		incidents.append(inc)


func _update_arrived(r: Response) -> void:
	# crew out (driver last), ambulance rear doors open
	if r.state_t < 0.3:
		return
	for c in r.crew:
		if c.get("current_vehicle") == r.vehicle and c.has_method("exit_vehicle"):
			c.call("exit_vehicle")
	if r.kind == "medical" and r.vehicle.has_method("open_door"):
		r.vehicle.call("open_door", "Door_RL", 600.0)
		r.vehicle.call("open_door", "Door_RR", 600.0)
	_assign_work(r)
	_set_state(r, State.WORKING)


func _assign_work(r: Response) -> void:
	r.assign.clear()
	var vpos := r.vehicle.global_position
	if r.kind == "medical":
		var pats: Array = []
		for p: Dictionary in (r.incident.get("patients", []) as Array):
			var node: Variant = p.get("node")
			if node != null and is_instance_valid(node) and not bool(p.get("treated", false)):
				pats.append(p)
		for i in r.crew.size():
			var c := r.crew[i]
			var b := _brain(c)
			if b == null:
				continue
			if pats.is_empty():
				# nobody left to treat: look at the scene, then go back
				b.call("go_to", c, r.scene + Vector3(_rng.randf_range(-2, 2), 0.0, _rng.randf_range(-2, 2)), r.scene, "run")
				r.assign[c.get_instance_id()] = {"kind": "look", "focus": r.scene, "working": false, "worked": 0.0, "need": 3.0}
				continue
			var p: Dictionary = pats[i % pats.size()]
			var body := _body_pos(p["node"])
			var away := body - vpos
			away.y = 0.0
			away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
			var side := Vector3(-away.z, 0.0, away.x) * (0.78 if i % 2 == 0 else -0.78)
			var spot := body + side
			spot.y = _ground_y(spot, body.y)
			var dead: bool = bool(p.get("dead", false)) or (p["node"] as Node).get("is_dead") == true
			var need := _rng.randf_range(TREAT_DEAD.x, TREAT_DEAD.y) if dead else _rng.randf_range(TREAT_ALIVE.x, TREAT_ALIVE.y)
			b.call("go_to", c, spot, body, "run", _path_around(r.vehicle, c.global_position, spot))
			r.assign[c.get_instance_id()] = {"kind": "patient", "patient": p, "focus": body, "working": false,
					"worked": 0.0, "need": need, "spot": spot}
	else:
		var fire_at := r.scene
		var w: Variant = r.incident.get("wreck", null)
		if w != null and is_instance_valid(w):
			fire_at = (w as Node3D).global_position
		var to_truck := vpos - fire_at
		to_truck.y = 0.0
		to_truck = to_truck.normalized() if to_truck.length_squared() > 0.01 else Vector3.BACK
		for i in r.crew.size():
			var c := r.crew[i]
			var b := _brain(c)
			if b == null:
				continue
			var ang := deg_to_rad(38.0) * (1.0 if i % 2 == 0 else -1.0) * (1.0 + 0.5 * float(i >> 1))
			var dir := to_truck.rotated(Vector3.UP, ang)
			var spot := fire_at + dir * FIRE_STAND
			spot.y = _ground_y(spot, fire_at.y)
			b.call("go_to", c, spot, fire_at, "run", _path_around(r.vehicle, c.global_position, spot))
			r.assign[c.get_instance_id()] = {"kind": "fire", "focus": fire_at + Vector3.UP * 0.4, "working": false,
					"worked": 0.0, "jet": -1, "spot": spot}


func _update_working(r: Response, dt: float) -> void:
	var all_done := true
	for c in r.crew:
		var a: Dictionary = r.assign.get(c.get_instance_id(), {})
		if a.is_empty():
			continue
		var b := _brain(c)
		if b == null:
			continue
		var kind := str(a["kind"])
		if bool(b.get("needs_orders")):
			# knocked over by a passing car and back on its feet: go back to the job
			b.set("needs_orders", false)
			a["working"] = false
			var spot: Variant = a.get("spot", null)
			if spot is Vector3:
				var focus: Vector3 = a["focus"]
				if kind == "patient" and is_instance_valid((a["patient"] as Dictionary).get("node")):
					focus = _body_pos((a["patient"] as Dictionary)["node"])
				b.call("go_to", c, spot, focus, "run")
			_log(r, "%s resumes after an accident" % str(c.get("archetype_id")))
		if not bool(a["working"]):
			all_done = false
			if bool(b.get("arrived")) or str(b.get("task")) == "idle":
				a["working"] = true
				_log(r, "%s starts %s %.1f m from the focus" % [str(c.get("archetype_id")), kind,
						_flat(c.global_position, Vector3(a["focus"]))])
				match kind:
					"patient":
						var p: Dictionary = a["patient"]
						var focus := _body_pos(p["node"]) if is_instance_valid(p.get("node")) else Vector3(a["focus"])
						b.call("work", c, "kneel", focus)
						if not bool(p.get("counted", false)):
							p["counted"] = true
							stats["bodies_attended" if bool(p.get("dead", false)) else "treated"] = int(stats["bodies_attended" if bool(p.get("dead", false)) else "treated"]) + 1
					"fire":
						b.call("work", c, "spray", a["focus"])
						a["jet"] = fx.call("start_jet", c) if fx != null else -1
					_:
						pass
			continue
		a["worked"] = float(a["worked"]) + dt
		match kind:
			"patient":
				var p: Dictionary = a["patient"]
				if float(a["worked"]) >= float(a["need"]):
					if not bool(p.get("treated", false)):
						p["treated"] = true
						var node: Variant = p.get("node")
						if node != null and is_instance_valid(node) and node.get("is_dead") != true and (node as Node).has_method("treat"):
							(node as Node).call("treat", c)
							stats["revived"] = int(stats["revived"]) + 1
					if str(b.get("task")) == "work":
						b.call("stop_work", c)
						c.call("face_position", r.vehicle.global_position)
				else:
					all_done = false
			"look":
				if float(a["worked"]) < float(a["need"]):
					all_done = false
			"fire":
				if not r.fire_out:
					all_done = false
					r.fire_work += dt
				elif r.age - r.fire_out_t < 2.5:
					all_done = false               # a last douse after the flames are gone
				elif str(b.get("task")) == "work":
					b.call("stop_work", c)
					_stop_jet(r, c)
	if r.kind == "fire" and not r.fire_out and r.fire_work >= FIRE_WORK:
		_extinguish(r)
	if all_done or r.state_t > WORK_TIMEOUT:
		if r.state_t > WORK_TIMEOUT:
			_log(r, "work timeout")
			if r.kind == "fire" and not r.fire_out:
				_extinguish(r)
		_begin_return(r)


func _extinguish(r: Response) -> void:
	r.fire_out = true
	r.fire_out_t = r.age
	var n := 0
	var inc := r.incident
	var sm: Variant = inc.get("smoulder", null)
	if sm != null and is_instance_valid(sm) and (sm as Object).has_method("stop"):
		(sm as Object).call("stop")
		n += 1
	inc["smoulder"] = null
	var w: Variant = inc.get("wreck", null)
	var at := r.scene
	if w != null and is_instance_valid(w):
		at = (w as Node3D).global_position
		for c in (w as Node).get_children():
			if c.get("fx_kind") == "fire" and c.has_method("stop"):
				c.call("stop")
				n += 1
	if Fx.has_method("extinguish"):
		n += int(Fx.call("extinguish", at, 7.0))
	for k in 3:
		Fx.smoke_puff(at + Vector3(_rng.randf_range(-1.0, 1.0), 0.6 + 0.5 * k, _rng.randf_range(-1.0, 1.0)), "steam", 1.6)
	stats["fires_out"] = int(stats["fires_out"]) + 1
	_log(r, "fire out (%d fire handles stopped)" % n)


func _tick_work_fx(r: Response, dt: float) -> void:
	if r.kind != "fire" or fx == null or (r.state != State.WORKING and r.state != State.RETURNING):
		return
	for c in r.crew:
		if not is_instance_valid(c):
			continue
		var a: Dictionary = r.assign.get(c.get_instance_id(), {})
		if a.is_empty() or int(a.get("jet", -1)) < 0:
			continue
		var b := _brain(c)
		if b == null or str(b.get("task")) != "work":
			_stop_jet(r, c)
			continue
		var from := Vector3.INF
		if c.has_method("get_hand_position"):
			from = c.call("get_hand_position")
		if from == Vector3.INF:
			from = c.global_position + Vector3.UP * 1.2 - c.global_basis.z * 0.5
		var f: Vector3 = a["focus"]
		var w: Variant = r.incident.get("wreck", null)
		if w != null and is_instance_valid(w):
			f = (w as Node3D).global_position + Vector3.UP * 0.5
		fx.call("aim_jet", int(a["jet"]), from - c.global_basis.z * 0.25, f, dt)


func _stop_jet(r: Response, c: Node3D) -> void:
	if c == null or not is_instance_valid(c):
		return
	var a: Dictionary = r.assign.get(c.get_instance_id(), {})
	if a.is_empty():
		return
	var j := int(a.get("jet", -1))
	if j >= 0 and fx != null:
		fx.call("stop_jet", j)
	a["jet"] = -1


func _begin_return(r: Response) -> void:
	for c in r.crew:
		_stop_jet(r, c)
	# corpses: the medics are done with them
	for p: Dictionary in (r.incident.get("patients", []) as Array):
		_release_patient(p)
	var claimed: Array[int] = []
	for c in r.crew:
		var b := _brain(c)
		if b == null:
			continue
		var seated: bool = c.get("current_vehicle") == r.vehicle
		if bool(b.get("aborted")) and not seated:
			if str(b.get("task")) not in ["flee", "leave", "hands_up"]:
				b.call("leave_on_foot", c)
			if not strays.has(c):
				strays.append(c)
			continue
		var seat := -1
		if seated:
			seat = int(c.get("seat_index"))
		else:
			seat = _free_seat(r, claimed)
		claimed.append(seat)
		var via := PackedVector3Array()
		if not seated and seat >= 0 and r.vehicle.has_method("get_door_position"):
			var door: Vector3 = r.vehicle.call("get_door_position", seat)
			via = _path_around(r.vehicle, c.global_position, door)
		b.call("return_to_vehicle", c, r.vehicle, seat, via)
	# aborted members walk off on their own
	for s in strays:
		r.crew.erase(s)
	if r.crew.is_empty():
		_strand(r, "crew gone")
		return
	_set_state(r, State.RETURNING)


## Corner points that lead from `from` to `to` round the vehicle's footprint (body_aabb + margin)
## when the straight line would cross it; empty when the straight line is clear. The navigation
## mesh has no cars in it, so a responder walking from the driver door to the kerb would run into
## its own ambulance.
func _path_around(v: Node3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if v == null or not is_instance_valid(v):
		return out
	var ab := AABB(Vector3(-1.1, 0.0, -3.0), Vector3(2.2, 2.5, 6.0))
	var abv: Variant = v.get("body_aabb")
	if abv is AABB:
		ab = abv
	var x0 := ab.position.x - 0.75
	var x1 := ab.end.x + 0.75
	var z0 := ab.position.z - 0.9
	var z1 := ab.end.z + 0.9
	var inv := v.global_transform.affine_inverse()
	var lf := inv * from
	var lt := inv * to
	var a := Vector2(lf.x, lf.z)
	var b := Vector2(lt.x, lt.z)
	var hits := false
	for k in range(1, 16):
		var p := a.lerp(b, float(k) / 16.0)
		if p.x > x0 + 0.15 and p.x < x1 - 0.15 and p.y > z0 + 0.15 and p.y < z1 - 0.15:
			hits = true
			break
	if not hits:
		return out
	var cx := (x0 + x1) * 0.5
	var sf := x1 if a.x >= cx else x0
	var st := x1 if b.x >= cx else x0
	var best: Array[Vector2] = []
	var best_len := INF
	for zc: float in [z0, z1]:
		var pts: Array[Vector2] = []
		var cur := a
		if a.x > x0 and a.x < x1:
			pts.append(Vector2(sf, clampf(a.y, z0, z1)))      # step out sideways first
			cur = pts[0]
		pts.append(Vector2(sf, zc))
		if not is_equal_approx(sf, st):
			pts.append(Vector2(st, zc))
		var length := 0.0
		for q in pts:
			length += cur.distance_to(q)
			cur = q
		length += cur.distance_to(b)
		if length < best_len:
			best_len = length
			best = pts
	var gxf := v.global_transform
	for q in best:
		var w := gxf * Vector3(q.x, lf.y, q.y)
		w.y = _ground_y(w, from.y)
		out.append(w)
	return out


## First seat of the response vehicle that nobody sits in and nobody of the crew claimed (driver first).
func _free_seat(r: Response, claimed: Array[int]) -> int:
	var n := 2
	if r.vehicle.has_method("get_seat_count"):
		n = int(r.vehicle.call("get_seat_count"))
	for s in n:
		if claimed.has(s):
			continue
		if r.vehicle.has_method("get_occupant"):
			var o: Variant = r.vehicle.call("get_occupant", s)
			if o != null and is_instance_valid(o):
				continue
		return s
	return -1


func _update_returning(r: Response) -> void:
	var all_in := true
	for c in r.crew:
		if c.get("current_vehicle") != r.vehicle:
			all_in = false
	var none: Array[int] = []
	for c in r.crew:
		var b := _brain(c)
		if b != null and bool(b.get("needs_orders")):
			b.set("needs_orders", false)
			b.call("return_to_vehicle", c, r.vehicle, int(c.get("seat_index")) if c.get("current_vehicle") == r.vehicle else _free_seat(r, none))
	if not all_in and r.state_t > BOARD_TIMEOUT:
		for c in r.crew:
			if c.get("current_vehicle") != r.vehicle:
				var b := _brain(c)
				if b != null:
					b.call("leave_on_foot", c)
				if not strays.has(c):
					strays.append(c)
		for s in strays:
			r.crew.erase(s)
		all_in = not r.crew.is_empty()
	if not all_in:
		return
	if r.driver.call("seated_driver") == null:
		_strand(r, "nobody at the wheel")
		return
	if r.kind == "medical" and r.vehicle.has_method("open_door"):
		r.vehicle.call("open_door", "Door_RL", 0.2)
		r.vehicle.call("open_door", "Door_RR", 0.2)
	r.driver.call("drive_away")
	_set_state(r, State.LEAVING)


func _update_leaving(r: Response) -> void:
	var vpos := r.vehicle.global_position
	var d := _flat(vpos, Game.get_player_position()) if Game.has_player() else 9999.0
	var seen := _in_view(vpos + Vector3.UP * 1.5)
	if d > DESPAWN_ALWAYS or (d > DESPAWN_FAR and not seen) or (r.state_t > LEAVE_TIMEOUT and not seen) \
			or (bool(r.driver.call("is_hopeless")) and not seen):
		_log(r, "despawned leaving (%.0f m)" % d)
		_despawn_response(r)
		return
	if int(r.driver.get("mode")) != 0:
		r.driver.call("drive_away")


## The vehicle is gone (stolen, destroyed, released): the crew walks off on foot.
func _strand(r: Response, why: String) -> void:
	_log(r, "stranded: " + why)
	for c in r.crew:
		_stop_jet(r, c)
		var b := _brain(c)
		if b != null and c.get("current_vehicle") == null and str(b.get("task")) not in ["flee", "leave", "hands_up"]:
			b.call("leave_on_foot", c)
	for p: Dictionary in (r.incident.get("patients", []) as Array):
		_release_patient(p)
	if r.driver != null and r.vehicle != null and is_instance_valid(r.vehicle) and not r.vehicle_lost \
			and r.vehicle.has_meta("ai_controller") and r.vehicle.get_meta("ai_controller") == r.driver:
		r.driver.call("release_vehicle", r.vehicle, "abandon")
	r.vehicle_lost = true
	_set_state(r, State.STRANDED)


func _vehicle_lost(r: Response, why: String) -> void:
	if r.vehicle_lost:
		return
	if why == "stolen":
		stats["stolen"] = int(stats["stolen"]) + 1
	if r.driver != null and r.vehicle != null and is_instance_valid(r.vehicle) and r.vehicle.has_meta("ai_controller") \
			and r.vehicle.get_meta("ai_controller") == r.driver:
		r.driver.call("release_vehicle", r.vehicle, "despawn" if why == "destroyed" else "abandon")
	r.vehicle_lost = true
	_log(r, "vehicle lost: " + why)


## AiEmergencyDriver.release_vehicle() callback (also when the PLAYER module carjacks it).
func _on_driver_released(drv: RefCounted, reason: String) -> void:
	for r in responses:
		if r.driver == drv:
			if not r.vehicle_lost:
				r.vehicle_lost = true
				if reason == "carjacked":
					stats["stolen"] = int(stats["stolen"]) + 1
				_log(r, "vehicle released (%s)" % reason)


func _on_player_entered_vehicle(vehicle: Node3D, _seat: int) -> void:
	for r in responses:
		if r.vehicle == vehicle and not r.vehicle_lost:
			_vehicle_lost(r, "stolen")


func _on_vehicle_stolen(vehicle: Node3D, _thief: Node, _had_driver: bool) -> void:
	_on_player_entered_vehicle(vehicle, 0)


func _any_aborted(r: Response) -> bool:
	for c in r.crew:
		var b := _brain(c)
		if b != null and bool(b.get("aborted")):
			return true
	return false


func _abort_reason(r: Response) -> String:
	for c in r.crew:
		var b := _brain(c)
		if b != null and bool(b.get("aborted")):
			return str(b.get("abort_reason"))
	return ""


# =================================================================================================
# clean-up
# =================================================================================================

func _despawn_response(r: Response) -> void:
	var ours := not r.vehicle_lost          # release_vehicle() below marks it lost: decide first
	for c in r.crew:
		_stop_jet(r, c)
		_free_npc(c)
	r.crew.clear()
	if r.driver != null and r.vehicle != null and is_instance_valid(r.vehicle) and r.vehicle.has_meta("ai_controller") \
			and r.vehicle.get_meta("ai_controller") == r.driver:
		r.driver.call("release_vehicle", r.vehicle, "despawn")
	if ours and r.vehicle != null and is_instance_valid(r.vehicle):
		_despawn_vehicle(r.vehicle)
	if not r.incident.is_empty():
		_release_incident(r.incident)
	r.vehicle_lost = true
	r.state = State.DONE
	stats["despawned"] = int(stats["despawned"]) + 1
	responses.erase(r)


func _tick_strays() -> void:
	if strays.is_empty():
		return
	var pp := Game.get_player_position() if Game.has_player() else Vector3.ZERO
	for i in range(strays.size() - 1, -1, -1):
		var s := strays[i]
		if s == null or not is_instance_valid(s):
			strays.remove_at(i)
			continue
		if s.get("is_dead") == true:
			s.set("persistent", false)        # the peds system cleans the corpse up
			strays.remove_at(i)
			continue
		if s.get("current_vehicle") != null:
			continue
		var d := _flat(s.global_position, pp)
		if d > DESPAWN_FAR or (d > STRAY_NEAR and not _in_view(s.global_position + Vector3.UP * 1.2)):
			strays.remove_at(i)
			_free_npc(s)


func _free_npc(n: Node3D) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n.get("current_vehicle") != null and n.has_method("exit_vehicle"):
		n.call("exit_vehicle")
	if n.get("is_dead") == true:
		n.set("persistent", false)
		return
	n.queue_free()


func _despawn_vehicle(v: Node3D) -> void:
	if v == null or not is_instance_valid(v) or v == Game.get_player_vehicle() or v.get("is_player_driven") == true:
		return
	var vm := Game.get_system("vehicles")
	if vm != null and vm.has_method("despawn_vehicle"):
		vm.call("despawn_vehicle", v)
	else:
		v.queue_free()


# =================================================================================================
# helpers
# =================================================================================================

func _brain(c: Node) -> Node:
	if c == null or not is_instance_valid(c):
		return null
	var b: Variant = c.get("brain")
	if b is Node and is_instance_valid(b) and (b as Node).has_method("go_to"):
		return b as Node
	return null


func _roads() -> Object:
	var w := Game.world
	if w == null or not is_instance_valid(w):
		return null
	var r: Variant = w.get("roads")
	return r as Object if r is Object else null


func _ground_y(p: Vector3, fallback: float) -> float:
	if Game.world != null and Game.world.has_method("get_height"):
		var h := float(Game.world.call("get_height", p.x, p.z))
		if absf(h - fallback) < 3.0:
			return h
	return fallback


## True when the camera could see `p` (frustum, < 240 m, nothing solid in between).
func _in_view(p: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	if not cam.is_position_in_frustum(p):
		return false
	var cp := cam.global_position
	if cp.distance_to(p) > 240.0:
		return false
	if _view_q == null:
		_view_q = PhysicsRayQueryParameters3D.new()
		_view_q.collision_mask = Layers.WORLD
	_view_q.from = cp
	_view_q.to = p
	return get_world_3d().direct_space_state.intersect_ray(_view_q).is_empty()


func _vehicle_near(p: Vector3, r: float) -> bool:
	if not is_inside_tree():
		return false
	if _shape_q == null:
		_shape_q = PhysicsShapeQueryParameters3D.new()
		_shape_q.collision_mask = Layers.VEHICLE
		_shape_q.collide_with_areas = false
	_sphere.radius = r
	_shape_q.shape = _sphere
	_shape_q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
	return not get_world_3d().direct_space_state.intersect_shape(_shape_q, 1).is_empty()


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)


func _log(r: Response, msg: String) -> void:
	if r.log.size() >= 24:
		r.log.remove_at(0)
	r.log.append("[%.1f] %s" % [r.age, msg])
	if TestHarness.is_testing():
		print("EMG %s#%d %s" % [r.kind, r.id, msg])


func get_response_log(id: int) -> PackedStringArray:
	for r in responses:
		if r.id == id:
			return r.log
	return PackedStringArray()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
