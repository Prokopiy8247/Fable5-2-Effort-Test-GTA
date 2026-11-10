class_name AiResponderBrain
extends Node
## Brain of a medic / firefighter that rides with an emergency response (W2.2 brain contract).
## The emergency system gives the orders (go_to, work, return_to_vehicle, leave_on_foot); this
## brain carries them out at the NPC's think rate and reacts to danger on its own:
##
##   * responders NEVER report crimes (saw_crime is ignored) and NEVER fight;
##   * shot at / hit / a gun pointed at them / gunfire or an explosion close by -> they drop the
##     job (`aborted = true`), flee, and the system sends the response home;
##   * bumped -> a glance, the job goes on; knocked over by a passing car (not the player's) ->
##     gets up and the system gives the order again (`needs_orders`).
##
## Readable state for the system: task, arrived, boarded, aborted, abort_reason, task_t,
## interrupted, needs_orders.

const DANGER_GUNSHOT := 38.0           ## gunfire this close aborts the job
const DANGER_EXPLOSION := 30.0
const REPATH := 1.6
const GOTO_TIMEOUT := 45.0
const BOARD_SNAP := 22.0               ## seconds of trying to board before the body is seated directly

var system: Node = null
var vehicle: Node3D = null             ## the response vehicle
var role: String = "medic"             ## "medic" | "fire"
var task: String = "ride"              ## ride, goto, work, board, flee, leave, idle, hands_up
var task_t: float = 0.0
var target: Vector3 = Vector3.INF
var focus: Vector3 = Vector3.INF       ## what to face on arrival / while working
var speed_mode: String = "run"
var arrived: bool = false
var boarded: bool = false
var aborted: bool = false
var abort_reason: String = ""
var interrupted: bool = false          ## knocked down by an accident: resume after getting up
var needs_orders: bool = false         ## got up after an interruption: the system re-issues the job
var danger_pos: Vector3 = Vector3.INF
var work_pose: String = ""
var _repath_t: float = 0.0
var _seat: int = -1


func get_mode_name() -> String:
	return task


# =================================================================================================
# orders (emergency system)
# =================================================================================================

## `via` = corner points round the response vehicle (the navigation mesh does not know cars).
func go_to(npc: Node, pos: Vector3, p_focus: Vector3 = Vector3.INF, p_speed: String = "run",
		via: PackedVector3Array = PackedVector3Array()) -> void:
	if npc == null or not is_instance_valid(npc) or aborted:
		return
	npc.call("stand_normal")
	target = pos
	focus = p_focus
	speed_mode = p_speed
	arrived = false
	_set_task("goto")
	_repath_t = REPATH
	if via.is_empty():
		npc.call("move_to", pos, p_speed)
	else:
		var pts := via.duplicate()
		pts.append(pos)
		npc.call("follow_path", pts, p_speed)
	npc.set("state_tag", "responding")


## Start working at the current spot: "kneel" (medic, focus = the patient) or "spray" (firefighter,
## focus = the base of the fire).
func work(npc: Node, pose: String, p_focus: Vector3) -> void:
	if npc == null or not is_instance_valid(npc) or aborted:
		return
	npc.call("stop_moving")
	focus = p_focus
	work_pose = pose
	if npc.has_method("set_service_pose"):
		npc.call("set_service_pose", pose, p_focus)
	_set_task("work")
	npc.set("state_tag", "treating" if pose == "kneel" else "spraying")


func stop_work(npc: Node) -> void:
	work_pose = ""
	if npc != null and is_instance_valid(npc) and npc.has_method("set_service_pose"):
		npc.call("set_service_pose", "", Vector3.INF)


## Walk back to the vehicle and get in (seat chosen by the system). `via` = corner points round
## the vehicle to its door.
func return_to_vehicle(npc: Node, v: Node3D, seat: int, via: PackedVector3Array = PackedVector3Array()) -> void:
	if npc == null or not is_instance_valid(npc) or v == null or not is_instance_valid(v):
		return
	stop_work(npc)
	vehicle = v
	_seat = seat
	boarded = npc.get("current_vehicle") == v
	if boarded:
		_set_task("ride")
		return
	npc.set("state_tag", "boarding")
	if not via.is_empty():
		npc.call("stand_normal")
		npc.call("follow_path", via, "walk")
		_set_task("approach")
		return
	_set_task("board")
	npc.call("enter_vehicle", v, seat, false)


## Walk off along the sidewalks (the system despawns the body out of view).
func leave_on_foot(npc: Node) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	stop_work(npc)
	npc.call("stand_normal")
	var n := npc as Node3D
	var dest := Vector3.INF
	var w := Game.world
	if w != null and is_instance_valid(w):
		var walk: Variant = w.get("walk")
		if walk is Object and (walk as Object).has_method("random_point"):
			dest = (walk as Object).call("random_point", n.global_position, 40.0, 90.0)
	if dest != Vector3.INF:
		npc.call("walk_to", dest, "walk")
	_set_task("leave")
	npc.set("state_tag", "leaving")


func _set_task(t: String) -> void:
	task = t
	task_t = 0.0


# =================================================================================================
# brain contract
# =================================================================================================

func think(npc: Node, delta: float) -> void:
	var n := npc as Node3D
	if n == null or npc.get("is_dead") == true:
		return
	task_t += delta
	if npc.get("is_down") == true:
		return
	match task:
		"ride":
			if vehicle != null and is_instance_valid(vehicle):
				boarded = npc.get("current_vehicle") == vehicle
		"goto":
			if npc.get("current_vehicle") != null:
				return
			var d := _flat(n.global_position, target)
			if bool(npc.call("has_arrived", 1.0)) or d < 1.0 or (not bool(npc.call("is_moving")) and d < 2.6):
				_arrive(npc)
			elif task_t > GOTO_TIMEOUT:
				_arrive(npc)              # close enough is good enough; the system decides
			else:
				_repath_t -= delta
				if _repath_t <= 0.0 and not bool(npc.call("is_moving")):
					_repath_t = REPATH
					npc.call("move_to", target, speed_mode)
		"work":
			if focus != Vector3.INF and work_pose == "spray":
				npc.call("aim_at", focus)
		"approach":
			if vehicle == null or not is_instance_valid(vehicle) or vehicle.get("destroyed") == true:
				leave_on_foot(npc)
				return
			if not bool(npc.call("is_moving")) or task_t > 12.0:
				_set_task("board")
				npc.call("enter_vehicle", vehicle, _seat, false)
		"board":
			if vehicle == null or not is_instance_valid(vehicle) or vehicle.get("destroyed") == true:
				leave_on_foot(npc)
				return
			if npc.get("current_vehicle") == vehicle:
				boarded = true
				_set_task("ride")
				npc.set("state_tag", "in_vehicle")
			elif task_t > BOARD_SNAP:
				npc.call("enter_vehicle", vehicle, _seat, true)
			elif task_t > 1.5 and not bool(npc.call("is_moving")) and npc.get("current_vehicle") == null:
				_repath_t -= delta
				if _repath_t <= 0.0:
					_repath_t = 3.0
					npc.call("enter_vehicle", vehicle, _seat, false)
		"hands_up":
			if float(npc.get("threatened_time")) <= 0.0 and task_t > 1.5:
				_flee(npc, danger_pos, "threatened")
		"flee":
			if task_t > 2.0 and not bool(npc.call("is_moving")):
				leave_on_foot(npc)
		"leave":
			if task_t > 2.0 and not bool(npc.call("is_moving")):
				_set_task("idle")
				npc.set("state_tag", "idle")


func _arrive(npc: Node) -> void:
	arrived = true
	npc.call("stop_moving")
	if focus != Vector3.INF:
		npc.call("face_position", focus)


func on_event(npc: Node, event: String, data: Dictionary) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	match event:
		"spawned":
			role = "fire" if str(npc.get("faction")) == "fire" else "medic"
		"damaged":
			var attacker: Variant = data.get("attacker", null)
			var info: Dictionary = data.get("info", {})
			var type := str(info.get("type", ""))
			if type == "fire" and task == "work":
				return                     # singed while spraying: step back is the system's job
			if type == "vehicle" and not _is_player(attacker):
				interrupted = true         # an accident (traffic): carry on after getting up
				return
			var from: Vector3 = (npc as Node3D).global_position
			if attacker is Node3D and is_instance_valid(attacker) and attacker != npc:
				from = (attacker as Node3D).global_position
			else:
				from = info.get("position", from)
			_flee(npc, from, "attacked")
		"vehicle_hit":
			var vi: Dictionary = data.get("info", {})
			if _is_player(data.get("attacker", null)) or _is_player(vi.get("instigator", null)):
				_flee(npc, (npc as Node3D).global_position, "hit")
		"noise":
			var kind := str(data.get("kind", ""))
			var dist := float(data.get("distance", 999.0))
			var pos: Vector3 = data.get("position", (npc as Node3D).global_position)
			if (kind == "gunshot" and dist < DANGER_GUNSHOT) or (kind == "explosion" and dist < DANGER_EXPLOSION) \
					or (kind == "suppressed_gunshot" and dist < 10.0):
				_flee(npc, pos, kind)
		"threatened":
			var by: Variant = data.get("by", null)
			if by is Node3D and is_instance_valid(by):
				danger_pos = (by as Node3D).global_position
			if task in ["flee", "leave", "hands_up"]:
				return
			if npc.get("current_vehicle") != null:
				return
			stop_work(npc)
			aborted = true
			abort_reason = "threatened"
			npc.call("surrender")
			_set_task("hands_up")
		"panic":
			_flee(npc, data.get("from", (npc as Node3D).global_position), "panic")
		"bumped":
			var b: Variant = data.get("by", null)
			if b is Node3D and is_instance_valid(b) and task != "work":
				npc.set("look_target", (b as Node3D).global_position + Vector3(0.0, 1.5, 0.0))
		"knocked_down":
			stop_work(npc)
			if not aborted:
				interrupted = true
		"got_up":
			if aborted:
				_flee(npc, danger_pos if danger_pos != Vector3.INF else (npc as Node3D).global_position, abort_reason)
			elif interrupted:
				interrupted = false
				needs_orders = true
				_set_task("idle")
		"reset":
			aborted = true
			abort_reason = "reset"
		# "saw_crime": responders never call the police; "talk_with", "stuck": nothing to do


func _flee(npc: Node, from: Vector3, why: String) -> void:
	danger_pos = from
	if not aborted:
		aborted = true
		abort_reason = why
	if npc.get("current_vehicle") != null:
		return                       # seated: the driver takes everybody away
	if task == "flee" and task_t < 3.0:
		return
	stop_work(npc)
	npc.call("stand_normal")
	npc.call("flee_from", from, 40.0, "sprint")
	npc.set("state_tag", "flee")
	_set_task("flee")


static func _is_player(n: Variant) -> bool:
	if n == null or not is_instance_valid(n) or not (n is Node):
		return false
	var nn := n as Node
	if nn.is_in_group("player"):
		return true
	return nn.is_in_group("vehicle") and nn.get("is_player_driven") == true


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
