extends Node
## Vehicle interactions of the player (spec 13A, ARCHITECTURE_WAVE2 W2.1). Child "VehicleInteraction"
## of the Player; player.gd preloads this script (no class_name: the module's reserved names are
## Player, PlayerCamera, PlayerInteraction and PlayerState*).
##
##   entry key      tap enter_vehicle = drive (steal the vehicle when somebody else drives it);
##                  hold it (HOLD_TIME) next to a vehicle that has a driver and a free passenger seat
##                  = ride along as a passenger (seat > 0), the driver stays
##   carjacking     PlayerStateVehicle walks to the door, plays "jack" (cars: the door swings) or
##                  "shove" (bikes / bicycles), then pull_out(): ai_controller.release_vehicle(vehicle,
##                  "carjacked") -> the driver lands beside the door and is knocked down,
##                  EventBus.vehicle_stolen(vehicle, player, true), Wanted.report_crime("vehicle_theft"
##                  or "police_vehicle_theft", pos, {"instigator", "victim"})
##   empty vehicles taking the driver seat of a vehicle that is not already the player's emits
##                  vehicle_stolen(vehicle, player, false); only police vehicles are a crime
##                  ("police_vehicle_theft"). Riding as a passenger is never theft.
##   drive-by       seat arcs (cars: the window side + forward, bikes: forward and both sides), the
##                  window point the shots leave from, the weapon drawn when aim is pressed unarmed.

const HOLD_TIME := 0.35
const JACK_TIME_CAR := 0.9
const JACK_PULL_CAR := 0.48            ## when (s) the driver comes out
const JACK_TIME_BIKE := 0.55
const JACK_PULL_BIKE := 0.24
const THROW_IMPULSE_CAR := 130.0       ## knock_down impulse (N*s) for a driver pulled out
const THROW_IMPULSE_BIKE := 190.0      ## a rider shoved off
const ROOM_DISTANCE := 0.7             ## a pulled-out occupant closer than this to the player is moved aside
## Drive-by aim arcs: yaw relative to the vehicle forward (+ = left), radians.
const ARC_SEAT_LEFT := Vector2(-0.49, 2.88)     ## -28 .. +165 deg (left seats: forward-right to rear-left)
const ARC_SEAT_RIGHT := Vector2(-2.88, 0.49)
const ARC_BIKE := Vector2(-2.0, 2.0)            ## +-115 deg: forward and both sides
const PITCH_MIN := -0.75
const PITCH_MAX := 0.62

var player: Player = null
var last_victim: Node = null              ## the last occupant pulled / shoved out (tests, AI)

var _pending: Node3D = null
var _hold_t: float = 0.0
var _taken: Dictionary = {}               ## instance id -> true: vehicles already reported as taken


func setup(p: Player) -> void:
	player = p


# =================================================================================================
# entry key
# =================================================================================================

## Called by the ground / swim states every physics tick. Returns true when an entry started (the
## state changed). Tap = driver seat (jack an occupied one), hold = passenger seat next to a driver.
func process_enter_key(delta: float, allowed: bool) -> bool:
	var p := player
	if _pending != null:
		if not is_instance_valid(_pending) or not allowed or not p.has_control():
			_pending = null
			return false
		_hold_t += delta
		var held := Input.is_action_pressed(&"enter_vehicle")
		if held and _hold_t < HOLD_TIME:
			return false
		var v := _pending
		_pending = null
		# the vehicle drove off (or the player was moved) while the key was held: no long walk / warp
		var c := v.global_position
		if Vector2(c.x - p.global_position.x, c.z - p.global_position.z).length() > Player.VEHICLE_REACH + 4.0:
			return false
		if held:
			var seat := passenger_seat(v)
			if seat > 0:
				p.enter_vehicle(v, seat)
				return p.state_id == "vehicle"
		p.enter_vehicle(v, 0)
		return p.state_id == "vehicle"
	if not allowed or not p.just_pressed(&"enter_vehicle") or p.interaction_handles("enter_vehicle"):
		return false
	var veh := p.find_enterable_vehicle()
	if veh == null:
		return false
	if has_other_driver(veh) and passenger_seat(veh) > 0:
		_pending = veh                    # wait: tap (steal) or hold (ride along)?
		_hold_t = 0.0
		return false
	p.enter_vehicle(veh, 0)
	return p.state_id == "vehicle"


func is_deciding() -> bool:
	return _pending != null and is_instance_valid(_pending)


func cancel() -> void:
	_pending = null


## Somebody other than the player drives `v`.
func has_other_driver(v: Node3D) -> bool:
	if v == null or not is_instance_valid(v):
		return false
	var d: Variant = v.get("driver")
	return d != null and is_instance_valid(d) and d != player


## Occupant of `seat` other than the player (null if free / unknown).
func occupant_of(v: Node3D, seat: int) -> Node:
	if v == null or not is_instance_valid(v):
		return null
	if v.has_method("get_occupant"):
		var o: Variant = v.call("get_occupant", seat)
		if o is Node and is_instance_valid(o) and o != player:
			return o as Node
		return null
	if seat == 0:
		var d: Variant = v.get("driver")
		if d is Node and is_instance_valid(d) and d != player:
			return d as Node
	return null


## Free passenger seat (> 0) with the door nearest to the player, or -1.
func passenger_seat(v: Node3D) -> int:
	if v == null or not v.has_method("get_seat_count") or not v.has_method("get_occupant"):
		return -1
	var n := int(v.call("get_seat_count"))
	var best := -1
	var best_d := INF
	for i in range(1, n):
		if v.call("get_occupant", i) != null:
			continue
		var door := v.global_position
		if v.has_method("get_door_position"):
			door = v.call("get_door_position", i)
		var d := door.distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			best = i
	return best


static func is_bike(v: Node3D) -> bool:
	var cls := str(v.get("vehicle_class")) if v != null else ""
	return cls == "bike" or cls == "bicycle"


# =================================================================================================
# carjacking
# =================================================================================================

func jack_time(v: Node3D) -> float:
	return JACK_TIME_BIKE if is_bike(v) else JACK_TIME_CAR


func jack_pull_time(v: Node3D) -> float:
	return JACK_PULL_BIKE if is_bike(v) else JACK_PULL_CAR


## Start of the jack transition: the door swings, the player reaches in / shoves.
func begin_jack(v: Node3D, seat: int) -> void:
	if v.has_method("swing_door"):
		v.call("swing_door", seat)
	if is_bike(v):
		player.play_action("shove", JACK_TIME_BIKE)
	else:
		player.play_action("jack", JACK_TIME_CAR)
		Audio.play_at("door_open", v.global_position, -4.0, 1.0, 40.0)
	player.emit_noise(10.0, "footstep")


## Pull the occupant of `seat` out (W2.1). Returns the victim (may be null).
func pull_out(v: Node3D, seat: int) -> Node:
	var p := player
	var victim := occupant_of(v, seat)
	var released: Node = null
	if seat == 0 and v.has_meta("ai_controller"):
		var ctrl: Variant = v.get_meta("ai_controller")
		if ctrl is Object and is_instance_valid(ctrl) and (ctrl as Object).has_method("release_vehicle"):
			var r: Variant = (ctrl as Object).call("release_vehicle", v, "carjacked")
			if r is Node and is_instance_valid(r):
				released = r as Node
		if v.has_meta("ai_controller") and v.get_meta("ai_controller") == ctrl:
			v.remove_meta("ai_controller")        # the controller must let go (W2.1); make sure
	if released == null:
		released = victim
	last_victim = released
	var bike := is_bike(v)
	# no (compliant) controller: free the seat now, with the same notifications VehicleBase uses
	# when it evicts somebody, so the occupant is out before the player slides in
	if released != null and is_instance_valid(released) and v.has_method("get_seat_of") \
			and int(v.call("get_seat_of", released)) == seat and v.has_method("occupant_exit"):
		var xf: Transform3D = v.call("occupant_exit", seat)
		if released.has_method("on_vehicle_ejected"):
			released.call("on_vehicle_ejected", v, xf, Vector3.ZERO)
		elif released.has_method("exit_vehicle") and released.get("current_vehicle") == v:
			released.call("exit_vehicle")
		elif released is Node3D and v.is_ancestor_of(released):
			(released as Node3D).reparent(Game.get_entities_root(), false)
			(released as Node3D).global_transform = xf
	# a victim that is out of the seat now is thrown / shoved to the ground; one that is still seated
	# is evicted by occupant_enter() (VehicleBase._evict -> on_vehicle_ejected / knock_down)
	if released != null and is_instance_valid(released) and released is Node3D and released != p:
		var still_in := v.has_method("get_seat_of") and int(v.call("get_seat_of", released)) >= 0
		if not still_in:
			var r3 := released as Node3D
			var away := r3.global_position - v.global_position
			away.y = 0.0
			if away.length_squared() < 0.01:
				away = r3.global_position - p.global_position
				away.y = 0.0
			away = away.normalized() if away.length_squared() > 0.0001 else -v.global_basis.x
			_make_room(r3, v, away)
			var imp := THROW_IMPULSE_BIKE if bike else THROW_IMPULSE_CAR
			if r3.has_method("knock_down"):
				r3.call("knock_down", away * imp + Vector3(0.0, imp * 0.45, 0.0))
			elif r3.has_method("panic"):
				r3.call("panic", p.global_position)
	Audio.play_at("body_fall", v.global_position, -4.0, 1.0, 30.0)
	report_taken(v, released, true)
	return released


## The pulled-out occupant lands on the door point - where the player stands. Put it a step further
## out and towards the rear (if nothing solid is in the way) so the two bodies do not overlap on
## screen while it is thrown down (review fix, seen in plr4_carjack_pull.png).
func _make_room(who: Node3D, v: Node3D, away: Vector3) -> void:
	var p := player
	var flat := who.global_position - p.global_position
	flat.y = 0.0
	if flat.length() > ROOM_DISTANCE or not p.is_inside_tree():
		return
	var rear := v.global_basis.z
	rear.y = 0.0
	rear = rear.normalized() if rear.length_squared() > 0.0001 else Vector3.ZERO
	var goal := who.global_position + away * 0.45 + rear * 0.4
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0.0, 1.0, 0.0), goal + Vector3(0.0, 1.0, 0.0),
			Layers.WORLD | Layers.VEHICLE | Layers.PROP)
	if not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return
	who.global_position = goal


## The player takes a seat: theft bookkeeping (call BEFORE occupant_enter, which retags the owner).
func note_taking(v: Node3D, seat: int, jacked: bool) -> void:
	if seat != 0 or jacked:
		return
	report_taken(v, null, false)


## EventBus.vehicle_stolen + crime report, once per vehicle (a carjack always reports).
func report_taken(v: Node3D, victim: Node, had_driver: bool) -> void:
	if v == null or not is_instance_valid(v):
		return
	var key := v.get_instance_id()
	var owner := str(v.get("owner_tag"))
	var personal: bool = v.get("personal") == true
	if not had_driver and (_taken.has(key) or owner == "player" or personal):
		return
	if _taken.size() > 64:
		_taken.clear()
	_taken[key] = true
	EventBus.vehicle_stolen.emit(v, player, had_driver)
	var crime := ""
	if v.get("is_police") == true:
		crime = "police_vehicle_theft"
	elif had_driver:
		crime = "vehicle_theft"
	if crime != "":
		var opts := {"instigator": player, "vehicle": v}
		if victim != null and is_instance_valid(victim):
			opts["victim"] = victim
		Wanted.report_crime(crime, v.global_position, opts)


# =================================================================================================
# drive-by
# =================================================================================================

## Allowed aim yaw range for `seat` (radians relative to the vehicle forward, + = left).
## Vector2.ZERO = no drive-by from this seat (aircraft pilot).
func drive_by_arc(v: Node3D, seat: int) -> Vector2:
	var cls := str(v.get("vehicle_class"))
	if cls == "bike" or cls == "bicycle":
		return ARC_BIKE
	if (cls == "heli" or cls == "plane") and seat == 0:
		return Vector2.ZERO
	return ARC_SEAT_LEFT if seat_side(v, seat) < 0.0 else ARC_SEAT_RIGHT


## -1 = the seat is on the left of the vehicle, +1 = right.
func seat_side(v: Node3D, seat: int) -> float:
	if v.has_method("get_seat_node"):
		var sn: Variant = v.call("get_seat_node", seat)
		if sn is Node3D and is_instance_valid(sn) and (sn as Node3D).is_inside_tree():
			var local := v.global_transform.affine_inverse() * (sn as Node3D).global_position
			if absf(local.x) > 0.05:
				return signf(local.x)
	return -1.0 if seat % 2 == 0 else 1.0


## Aim direction in the vehicle frame: x = yaw (+ left), y = pitch (+ up).
func aim_angles(v: Node3D, dir: Vector3) -> Vector2:
	var l := v.global_transform.basis.orthonormalized().inverse() * dir.normalized()
	return Vector2(atan2(-l.x, -l.z), asin(clampf(l.y, -1.0, 1.0)))


func in_arc(v: Node3D, seat: int, dir: Vector3) -> bool:
	var arc := drive_by_arc(v, seat)
	if arc == Vector2.ZERO:
		return false
	var a := aim_angles(v, dir)
	return a.x >= arc.x and a.x <= arc.y and a.y >= PITCH_MIN and a.y <= PITCH_MAX


## World point the shots leave from: the window on the aim side of the seat (leaning out).
func window_point(v: Node3D, seat: int, dir: Vector3) -> Vector3:
	var sn: Node3D = v
	if v.has_method("get_seat_node"):
		var s: Variant = v.call("get_seat_node", seat)
		if s is Node3D and is_instance_valid(s):
			sn = s as Node3D
	var xf := sn.global_transform.orthonormalized()
	var ld := xf.basis.inverse() * dir
	ld.y = 0.0
	ld = ld.normalized() if ld.length_squared() > 0.0001 else Vector3(-1.0, 0.0, 0.0)
	var reach := 0.32 if is_bike(v) else 0.46
	return xf * (Vector3(ld.x * reach, 0.5, ld.z * 0.30))


## Best weapon to draw for a drive-by when aim is pressed unarmed ("" = none).
func pick_drive_by_weapon() -> String:
	var inv := player.inventory
	if inv == null or not is_instance_valid(inv) or not inv.has_method("get_weapons"):
		return ""
	var list: Variant = inv.call("get_weapons")
	if not (list is Array):
		return ""
	var best := ""
	for idv: Variant in list:
		var id := str(idv)
		if id == "fists" or id == "":
			continue
		if inv.has_method("can_use_in_vehicle") and not bool(inv.call("can_use_in_vehicle", id)):
			continue
		if inv.has_method("get_ammo"):
			var a: Variant = inv.call("get_ammo", id)
			if a is Dictionary and int((a as Dictionary).get("in_mag", 0)) + int((a as Dictionary).get("reserve", 0)) <= 0:
				continue
		if best == "" or (_is_thrown(best) and not _is_thrown(id)):
			best = id
	return best


func _is_thrown(id: String) -> bool:
	return id == "grenade" or id == "molotov"
