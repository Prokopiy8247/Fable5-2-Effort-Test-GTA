class_name PlayerStateVehicle
extends PlayerState
## Getting into, sitting in and leaving a vehicle.
##
##   APPROACH  walk to the door of the seat (the body ghosts through the door frame, no collision)
##   JACK      the seat is taken by somebody else (W2.1): the door swings, "jack" / "shove", the
##             occupant is pulled out (VehicleInteraction.pull_out -> ai_controller.release_vehicle)
##   ENTER     short procedural slide from the door to the seat + "enter_car" action
##   SEATED    the Player is a child of vehicle.get_seat_node(seat), local transform identity,
##             collision off, seated pose; the vehicle reads the driving input itself.
##             Drive-by: aim (or fire) with a drive-by weapon -> free-aim camera, shots from the
##             window inside the seat's arc, one-handed aim pose, steering keeps working; a thrown
##             weapon without aiming is dropped out of the window.
##   EXIT      vehicle.occupant_exit(seat) gave the exit transform; slide out and stand up.
##             Above BAIL_SPEED the player bails out and tumbles (ragdoll).
##
## Vehicle side of the contract: can_enter(player), occupant_enter(player, seat),
## occupant_exit(seat) -> Transform3D, get_seat_node(seat), get_exit_transform(seat); optional
## get_occupant(seat), get_seat_of(who), swing_door(seat), meta "ai_controller".

enum { APPROACH, ENTER, SEATED, EXIT, GONE, JACK }

var vehicle: Node3D = null
var seat: int = 0
var phase: int = APPROACH
var jacking: bool = false               ## this entry pulls somebody out of the seat
var drive_by_in_arc: bool = false       ## drive-by aim currently inside the seat's arc

var _t: float = 0.0
var _dur: float = 0.3
var _from: Transform3D
var _to: Transform3D
var _seat_node: Node3D = null
var _last_safe: Vector3 = Vector3.ZERO
var _wreck_handled: bool = false
var _abort_dist: float = 9.5
var _pulled: bool = false
var _drew_for_aim: bool = false
var _arc: Vector2 = Vector2.ZERO           ## drive-by arc of this seat (cached when seated)


func _init() -> void:
	public_name = "in_vehicle"


func enter(_previous: String, args: Dictionary) -> void:
	var p := player
	vehicle = args.get("vehicle", null) as Node3D
	seat = int(args.get("seat", 0))
	_seat_node = null
	_wreck_handled = false
	_pulled = false
	_drew_for_aim = false
	drive_by_in_arc = false
	p.velocity = Vector3.ZERO
	p.is_sprinting = false
	p.noise_radius = 0.0
	p.set_aiming(false)
	p.release_trigger()
	if p.is_crouching:
		p.set_crouching(false, true)
	if vehicle == null or not is_instance_valid(vehicle):
		p.change_state.call_deferred("on_foot", {})
		return
	jacking = p.vehicle_ix != null and p.vehicle_ix.occupant_of(vehicle, seat) != null
	p.set_collision_enabled(false)
	_last_safe = p.global_position
	_from = p.global_transform
	var dist := _from.origin.distance_to(_door_transform().origin)
	if bool(args.get("instant", false)) or dist > Player.VEHICLE_WALK_MAX:
		if jacking:
			p.vehicle_ix.pull_out(vehicle, seat)
			_pulled = true
		_sit_down(true)
		return
	phase = APPROACH
	_t = 0.0
	# abort only when the vehicle drives away from us, never because the door is a bit far
	_abort_dist = maxf(dist, Player.VEHICLE_WALK_MAX) + 1.5
	_dur = clampf(dist / 3.4, 0.12, 2.4)
	p.set_anim_state("locomotion")


func exit(_next: String) -> void:
	var p := player
	# whatever happens, never stay attached to a vehicle after this state
	if p.current_vehicle != null or (_seat_node != null and is_instance_valid(_seat_node) and p.get_parent() == _seat_node):
		_detach(false)
	p.anim_speed_override = -1.0
	p.anim_aim_yaw = 0.0
	p.drive_by_window = Vector3.INF
	p.aim_dir_override = Vector3.ZERO
	p.set_seated_tuning(null)


func allows_weapons() -> bool:
	if phase != SEATED or player.inventory == null or vehicle == null or not is_instance_valid(vehicle):
		return false
	if _arc == Vector2.ZERO:
		return false
	var inv := player.inventory
	if inv.has_method("can_use_in_vehicle"):
		return bool(inv.call("can_use_in_vehicle", str(inv.get("current_id"))))
	return false


func get_focus_position() -> Vector3:
	if phase == SEATED and vehicle != null and is_instance_valid(vehicle):
		return vehicle.global_position
	return player.global_position


func is_seated() -> bool:
	return phase == SEATED


func physics_update(delta: float) -> void:
	var p := player
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.is_inside_tree():
		_lost_vehicle()
		return
	# the vehicle blew up / got locked while we walked to it or pulled the driver out: give up (review
	# fix: the player used to sit down in the burning wreck and take the 120 hp wreck damage)
	if (phase == APPROACH or phase == JACK or phase == ENTER) and (vehicle.get("destroyed") == true or vehicle.get("locked") == true):
		_abort()
		return
	match phase:
		APPROACH:
			_t += delta
			var door := _door_transform()
			var k := clampf(_t / _dur, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			var pos := _from.origin.lerp(door.origin, e)
			p.global_position = pos
			var seat_pos := _seat_world().origin
			var to_seat := seat_pos - pos
			if Vector2(to_seat.x, to_seat.z).length() > 0.1:
				p.turn_toward(atan2(-to_seat.x, -to_seat.z), 12.0, delta)
			p.anim_speed_override = clampf(_from.origin.distance_to(door.origin) / _dur, 0.0, 3.4) * (1.0 - e * 0.5)
			if _from.origin.distance_to(door.origin) > _abort_dist:
				_abort()
				return
			if k >= 1.0:
				if jacking and p.vehicle_ix != null and p.vehicle_ix.occupant_of(vehicle, seat) != null:
					phase = JACK
					_t = 0.0
					_dur = p.vehicle_ix.jack_time(vehicle)
					p.anim_speed_override = 0.0
					p.set_anim_state("idle", 0.12)
					p.vehicle_ix.begin_jack(vehicle, seat)
				else:
					_begin_enter()
		JACK:
			_t += delta
			p.global_position = _door_transform().origin
			var to_s := _seat_world().origin - p.global_position
			if Vector2(to_s.x, to_s.z).length() > 0.1:
				p.turn_toward(atan2(-to_s.x, -to_s.z), 14.0, delta)
			if not _pulled:
				var spd := (vehicle as RigidBody3D).linear_velocity.length() if vehicle is RigidBody3D else 0.0
				if spd > 3.5:
					_abort()                # the driver floored it
					return
				if _t >= p.vehicle_ix.jack_pull_time(vehicle):
					_pulled = true
					p.vehicle_ix.pull_out(vehicle, seat)
			if _t >= _dur:
				_begin_enter()
		ENTER:
			_t += delta
			var k2 := clampf(_t / _dur, 0.0, 1.0)
			var e2 := k2 * k2 * (3.0 - 2.0 * k2)
			var target := _seat_world()
			var xf := _from.interpolate_with(target, e2)
			xf.origin.y += sin(PI * e2) * 0.10
			p.global_transform = xf.orthonormalized()
			if k2 >= 1.0:
				_sit_down(false)
		SEATED:
			_update_seated(delta)
		EXIT:
			_t += delta
			var k3 := clampf(_t / _dur, 0.0, 1.0)
			var e3 := k3 * k3 * (3.0 - 2.0 * k3)
			var xf3 := _from.interpolate_with(_to, e3)
			xf3.origin.y += sin(PI * e3) * 0.06
			p.global_transform = xf3.orthonormalized()
			if k3 >= 1.0:
				_finish_exit()
		GONE:
			# safety net: the caller that pulled the player out did not pick a new state
			p.set_collision_enabled(true)
			p.change_state("dead" if p.is_dead else "air", {})


func frame_update(_delta: float) -> void:
	# keep glued to the seat between physics ticks as well
	if phase == SEATED and _seat_node != null and is_instance_valid(_seat_node):
		if player.get_parent() == _seat_node:
			player.transform = Transform3D.IDENTITY
		else:
			player.global_transform = _seat_node.global_transform


func _begin_enter() -> void:
	var p := player
	phase = ENTER
	_t = 0.0
	_dur = Player.VEHICLE_ENTER_TIME
	_from = p.global_transform
	p.anim_speed_override = 0.0
	p.set_anim_state(_seated_anim(), Player.VEHICLE_ENTER_TIME * 0.9)
	p.play_action("enter_car", Player.VEHICLE_ENTER_TIME)
	if not jacking and has_doors(vehicle):
		Audio.play_at("door_open", vehicle.global_position, -4.0, 1.0, 40.0)


# --- seated ------------------------------------------------------------------------------------------

func _sit_down(instant: bool) -> void:
	var p := player
	if p.vehicle_ix != null:
		p.vehicle_ix.note_taking(vehicle, seat, jacking)
	if vehicle.has_method("occupant_enter"):
		vehicle.call("occupant_enter", p, seat)
	if not is_instance_valid(vehicle):
		_lost_vehicle()
		return
	_seat_node = _get_seat_node()
	_arc = p.vehicle_ix.drive_by_arc(vehicle, seat) if p.vehicle_ix != null else Vector2.ZERO
	p.current_vehicle = vehicle
	p.attach_to_seat(_seat_node, vehicle)
	phase = SEATED
	p.velocity = Vector3.ZERO
	p.anim_speed_override = 0.0
	p.set_seated_tuning(vehicle)
	p.set_anim_state(_seated_anim(), 0.0 if instant else 0.12)
	if instant:
		p.snap_animator()
	elif has_doors(vehicle):
		Audio.play_at("door_close", vehicle.global_position, -4.0, 1.0, 40.0)
	# aircraft carry a parachute for every occupant (spec 29A: "parachutes at aircraft")
	if Player.AIRCRAFT_CLASSES.has(str(vehicle.get("vehicle_class"))) and not p.has_parachute:
		p.give_parachute()
		if not instant:
			UI.notify("Parachute on board - bail out with %s, open with %s" % [InputSetup.label("enter_vehicle"), InputSetup.label("jump")], "info")
	EventBus.player_entered_vehicle.emit(vehicle, seat)
	p.notify_state_changed("in_vehicle")


func _update_seated(delta: float) -> void:
	var p := player
	if _seat_node == null or not is_instance_valid(_seat_node):
		_lost_vehicle()
		return
	if p.get_parent() == _seat_node:
		p.transform = Transform3D.IDENTITY
	else:
		p.global_transform = _seat_node.global_transform
	_last_safe = vehicle.global_position
	p.set_anim_state(_seated_anim())
	p.anim_steer = Input.get_axis("move_left", "move_right") if (seat == 0 and p.has_control()) else 0.0
	_update_drive_by(delta)

	# the vehicle blew up / was wrecked with the player inside
	if not _wreck_handled and bool(vehicle.get("destroyed")):
		_wreck_handled = true
		p.apply_damage(Dmg.make(Player.WRECK_DAMAGE, "explosion", null, vehicle.global_position, Vector3.UP))
		if p.state != self or phase != SEATED:
			return

	# thrown out by the vehicle (eject_occupants, carjacked by the police ...)
	if seat == 0 and vehicle.get("driver") != null and vehicle.get("driver") != p:
		_detach(false)
		_drop_out(Vector3.ZERO)
		return
	if vehicle.has_method("get_occupants"):
		var occ: Variant = vehicle.call("get_occupants")
		if occ is Array and not (occ as Array).is_empty() and not (occ as Array).has(p) and seat != 0:
			_detach(false)
			_drop_out(Vector3.ZERO)
			return

	# a sinking car is left automatically
	if Game.is_in_water(vehicle.global_position + Vector3(0.0, 0.9, 0.0)) and str(vehicle.get("vehicle_class")) != "boat":
		request_exit()
		return
	if p.just_pressed("enter_vehicle") and not p.interaction_handles("enter_vehicle"):
		request_exit()


## Drive-by: aim / fire with a drive-by weapon. Free-aim camera (PlayerCamera reads is_aiming),
## shots only inside the seat's arc and from the window, one-handed aim pose.
func _update_drive_by(delta: float) -> void:
	var p := player
	var ix := p.vehicle_ix
	var inv := p.inventory
	var arc_ok := ix != null and _arc != Vector2.ZERO
	var aim_held := p.pressed("aim")
	if not aim_held:
		_drew_for_aim = false
	# aim with empty hands: draw the best drive-by weapon once per press
	if arc_ok and aim_held and not _drew_for_aim and inv != null and is_instance_valid(inv):
		_drew_for_aim = true
		var cur := str(inv.get("current_id"))
		if (cur == "" or cur == "fists") and inv.has_method("equip"):
			var w := ix.pick_drive_by_weapon()
			if w != "":
				inv.call("equip", w)
	var cur_id := str(inv.get("current_id")) if inv != null and is_instance_valid(inv) else ""
	var armed := cur_id != "" and cur_id != "fists" and allows_weapons()
	var thrown := cur_id == "grenade" or cur_id == "molotov"
	var want := arc_ok and armed and (aim_held or (p.pressed("fire") and not thrown))
	p.set_aiming(want)
	var dir := Vector3.ZERO
	if p.camera != null:
		dir = p.camera.get_aim_direction()
	drive_by_in_arc = want and dir.length_squared() > 0.0001 and ix.in_arc(vehicle, seat, dir)
	var blocked := not drive_by_in_arc
	p.aim_dir_override = Vector3.ZERO
	if want:
		p.drive_by_window = ix.window_point(vehicle, seat, dir)
		var ang := ix.aim_angles(vehicle, dir)
		var arc := _arc
		p.anim_aim_yaw = clampf(ang.x, arc.x, arc.y)
		p.anim_aim_pitch = clampf(ang.y, Player.VehicleInteractionScript.PITCH_MIN, Player.VehicleInteractionScript.PITCH_MAX)
	else:
		p.anim_aim_yaw = 0.0
		p.anim_aim_pitch = 0.0
		p.drive_by_window = Vector3.INF
		if armed and thrown and arc_ok:
			# not aiming with a grenade / fire bottle: drop it out of the window behind the seat
			var side := ix.seat_side(vehicle, seat)
			var drop := vehicle.global_basis * Vector3(side * 0.55, -0.75, 0.6)
			p.drive_by_window = ix.window_point(vehicle, seat, vehicle.global_basis * Vector3(side, 0.0, 0.0))
			if inv.has_method("drop_throwable"):
				# the inventory's gentle drop (live, at the window, barely any throw speed)
				if p.fire_pressed_edge and p.has_control():
					inv.call("drop_throwable", drop.normalized())
			else:
				p.aim_dir_override = drop.normalized()
				blocked = false
	p.process_fire_input(delta, blocked)
	p.process_weapon_select_input(true)


## Leave the vehicle (called by Player.exit_vehicle). force = no transition (death, teleport).
func request_exit(force: bool = false) -> void:
	var p := player
	if phase == APPROACH or phase == ENTER or phase == JACK:
		_abort()
		return
	if phase != SEATED:
		return
	var v := vehicle
	var vel := Vector3.ZERO
	if v is RigidBody3D:
		vel = (v as RigidBody3D).linear_velocity
	var seat_xf := p.global_transform
	var exit_xf := _detach(true)
	phase = GONE            # nothing below may re-enter this function
	if force:
		p.global_transform = _upright(exit_xf)
		p.set_collision_enabled(true)
		return
	var speed := vel.length()
	var height := _height_above_ground(exit_xf.origin)
	if height > Player.BAIL_FREEFALL_AGL and p.states.has("freefall"):
		# bail out high above the ground (aircraft, a car off a cliff): skydive - deploy with jump
		p.global_transform = _upright(Transform3D(exit_xf.basis, exit_xf.origin))
		p.velocity = vel
		p.set_collision_enabled(true)
		p.change_state("freefall", {"from_vehicle": v})
		return
	if speed > Player.BAIL_SPEED:
		# bail out of a moving vehicle: tumble
		p.global_transform = _upright(Transform3D(exit_xf.basis, exit_xf.origin + Vector3(0.0, 0.3, 0.0)))
		p.velocity = vel
		p.set_collision_enabled(true)
		var dmg := clampf((speed - Player.BAIL_SPEED) * Player.BAIL_DAMAGE_PER_MS, 0.0, 70.0)
		if dmg > 0.5:
			p.apply_damage(Dmg.make(dmg, "fall", null, p.global_position, vel.normalized(), {"no_ragdoll": true}))
		if not p.is_dead:
			# the ragdoll inherits the vehicle velocity; the impulse only adds the push out of the door
			var out := exit_xf.origin - v.global_position
			out.y = 0.0
			out = out.normalized() if out.length_squared() > 0.01 else Vector3.ZERO
			p.ragdoll(out * 110.0 + Vector3(0.0, 110.0, 0.0), 1.6)
		return
	if height > 2.5:
		# stepping out of an aircraft in the air
		p.global_transform = _upright(Transform3D(exit_xf.basis, exit_xf.origin))
		p.velocity = vel
		p.set_collision_enabled(true)
		p.change_state("air", {})
		return
	phase = EXIT
	_t = 0.0
	_dur = Player.VEHICLE_EXIT_TIME
	_from = seat_xf
	_to = _upright(exit_xf)
	p.set_anim_state("idle", Player.VEHICLE_EXIT_TIME)
	p.play_action("exit_car", Player.VEHICLE_EXIT_TIME)
	if has_doors(v):
		Audio.play_at("door_open", v.global_position, -5.0, 1.05, 40.0)


func _finish_exit() -> void:
	var p := player
	p.global_transform = _to
	p.velocity = Vector3.ZERO
	p.set_collision_enabled(true)
	if vehicle != null and is_instance_valid(vehicle) and has_doors(vehicle):
		Audio.play_at("door_close", vehicle.global_position, -5.0, 1.0, 40.0)
	p.update_water()
	if p.water_depth > Player.SWIM_ENTER_DEPTH:
		p.change_state("swim", {"entry_speed": 0.0})
	else:
		p.change_state("on_foot", {})


## The vehicle threw the player out (explosion, eject_occupants, carjack). The seat is already
## free on the vehicle side, so occupant_exit() is not called again.
func eject(exit_xf: Transform3D, impulse: Vector3) -> void:
	var p := player
	if phase == APPROACH or phase == ENTER or phase == JACK:
		_abort()
		return
	if phase != SEATED:
		return
	var vel := Vector3.ZERO
	if vehicle is RigidBody3D:
		vel = (vehicle as RigidBody3D).linear_velocity
	var here := p.global_transform
	_detach(false)
	phase = GONE
	var xf := here
	if exit_xf.origin.is_finite() and exit_xf.origin.distance_to(here.origin) < 12.0 and exit_xf.origin.length_squared() > 0.0:
		xf = exit_xf
	p.global_transform = _upright(xf)
	p.set_collision_enabled(true)
	p.velocity = vel
	if p.is_dead:
		return
	if impulse.length() > 1.0 or vel.length() > Player.BAIL_SPEED:
		p.ragdoll(impulse + Vector3(0.0, 120.0, 0.0), 1.8)
	else:
		p.change_state("air", {})


## Unhooks the player from the vehicle and returns the exit transform (world).
func _detach(call_vehicle: bool) -> Transform3D:
	var p := player
	var v := vehicle
	var exit_xf := p.global_transform
	var had := p.current_vehicle != null
	p.release_trigger()
	p.set_aiming(false)
	if v != null and is_instance_valid(v):
		exit_xf = _door_transform()
		if call_vehicle and had and v.has_method("occupant_exit"):
			var r: Variant = v.call("occupant_exit", seat)
			if r is Transform3D and (r as Transform3D).origin.is_finite():
				var cand := r as Transform3D
				if cand.origin.distance_to(p.global_position) < 12.0 and cand.origin.length_squared() > 0.0:
					exit_xf = cand
	p.detach_from_seat()
	p.current_vehicle = null
	p.ignore_vehicle_hits(v, 1.2)
	_seat_node = null
	p.anim_aim_yaw = 0.0
	p.drive_by_window = Vector3.INF
	p.aim_dir_override = Vector3.ZERO
	if had and v != null and is_instance_valid(v):
		EventBus.player_exited_vehicle.emit(v)
	return exit_xf


func _drop_out(push: Vector3) -> void:
	var p := player
	p.set_collision_enabled(true)
	p.global_transform = _upright(p.global_transform)
	p.velocity = push
	p.change_state("air", {})


func _abort() -> void:
	var p := player
	p.set_collision_enabled(true)
	p.global_transform = _upright(p.global_transform)
	p.anim_speed_override = -1.0
	p.change_state("on_foot", {})


func _lost_vehicle() -> void:
	# the vehicle vanished under us (despawn / free): stand where it was
	var p := player
	p.detach_from_seat()
	var was := p.current_vehicle != null
	p.current_vehicle = null
	_seat_node = null
	if p.is_inside_tree():
		if phase == SEATED:
			p.global_position = _last_safe + Vector3(0.0, 0.5, 0.0)
		p.global_transform = _upright(p.global_transform)
	p.set_collision_enabled(true)
	p.velocity = Vector3.ZERO
	if was:
		EventBus.player_exited_vehicle.emit(null)
	vehicle = null
	if not p.is_dead:
		p.change_state("air", {})


# --- helpers ------------------------------------------------------------------------------------------

func _get_seat_node() -> Node3D:
	if vehicle.has_method("get_seat_node"):
		var n: Variant = vehicle.call("get_seat_node", seat)
		if n is Node3D and is_instance_valid(n):
			return n as Node3D
	return vehicle


func _seat_world() -> Transform3D:
	var n := _get_seat_node()
	if n == vehicle and not vehicle.has_method("get_seat_node"):
		return vehicle.global_transform * Transform3D(Basis.IDENTITY, Vector3(-0.4, 0.5, 0.0))
	return n.global_transform


## Where the player stands before getting in / after getting out (world, feet on the ground).
func _door_transform() -> Transform3D:
	return door_transform_of(vehicle, seat)


## Door / exit point of `seat` (world). Shared with Player.enter_vehicle so that both use the same
## distance (the Wave 1 bug: the centre was < 8 m but the door > 9 m -> silent abort).
static func door_transform_of(v: Node3D, s: int) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var ok := false
	if v.has_method("get_exit_transform"):
		var r: Variant = v.call("get_exit_transform", s)
		if r is Transform3D and (r as Transform3D).origin.is_finite():
			xf = r as Transform3D
			ok = xf.origin.distance_to(v.global_position) < 12.0
	if not ok:
		var side := -1.0 if s % 2 == 0 else 1.0
		xf = v.global_transform * Transform3D(Basis.IDENTITY, Vector3(1.5 * side, 0.0, 0.0))
	return xf


func _upright(xf: Transform3D) -> Transform3D:
	var fwd := -xf.basis.z
	fwd.y = 0.0
	var yaw := 0.0
	if fwd.length_squared() > 0.0001:
		yaw = atan2(-fwd.x, -fwd.z)
	return Transform3D(Basis(Vector3.UP, yaw), xf.origin)


func _height_above_ground(pos: Vector3) -> float:
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0.0, 0.5, 0.0), pos + Vector3(0.0, -60.0, 0.0), Layers.WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		if Game.is_in_water(Vector3(pos.x, Game.WATER_LEVEL - 0.2, pos.z)):
			return maxf(pos.y - Game.WATER_LEVEL, 0.0)
		return 0.0 if Game.world == null else 60.0
	return pos.y - (hit["position"] as Vector3).y


func _seated_anim() -> String:
	if vehicle != null and is_instance_valid(vehicle) and vehicle.has_method("get_rider_pose"):
		# the vehicle knows its rider best (jetski: straddle = "seated_bike")
		var rp: Variant = vehicle.call("get_rider_pose", seat)
		if rp is String and (rp == "seated_bike" or rp == "seated_car"):
			return rp
	var cls := str(vehicle.get("vehicle_class")) if vehicle != null and is_instance_valid(vehicle) else "car"
	if cls == "bike" or cls == "bicycle":
		return "seated_bike"
	return "seated_car"


## Door sounds only for bodies with doors (not bikes, bicycles, boats, jetskis).
static func has_doors(v: Node3D) -> bool:
	if v == null or not is_instance_valid(v):
		return false
	var cls := str(v.get("vehicle_class"))
	return not (cls == "bike" or cls == "bicycle" or cls == "boat")
