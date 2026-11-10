class_name VehicleCrime
extends RefCounted
## The ONE place where vehicles report crimes to the Wanted system (ARCHITECTURE 6.5):
##   * the player's vehicle runs a pedestrian over          -> "hit_and_run"
##   * the player's vehicle causes a major traffic collision -> "collision_major"
## Wanted owns the witness logic, heat and stars; nothing here sets stars directly.
## (Vehicle theft is reported by the player module, explosions by Fx.explosion, and destroyed
## police vehicles by the police module listening to EventBus.vehicle_destroyed.)

const HIT_MIN_SPEED := 4.0          ## m/s: slower bumps are not a crime
const MAJOR_DV := 5.5               ## m/s velocity change that counts as a major collision
const MAJOR_DV_SOLO := 9.0          ## ... against an empty / parked vehicle
const COOLDOWN_MSEC := {"hit_and_run": 900, "collision_major": 3500}

static var _last_msec: Dictionary = {}


## Called by VehicleBase when it strikes a character at speed.
static func character_hit(vehicle: VehicleBase, victim: Node, rel_speed: float, _damage: float) -> void:
	if vehicle == null or not vehicle.is_player_driven or victim == null:
		return
	if victim.is_in_group("player") or victim.is_in_group("animal"):
		return
	if rel_speed < HIT_MIN_SPEED:
		return
	var police_victim := victim.is_in_group("police")
	_report("hit_and_run", vehicle, {
		"victim": victim,
		"severity": clampf(rel_speed / 12.0, 0.6, 1.6),
		"direct_police_witness": police_victim,
	})


## Called by VehicleBase for every hull impact. `pre_speed` is this vehicle's speed just before.
static func collision(vehicle: VehicleBase, other: Node, dv: float, _position: Vector3, pre_speed: float) -> void:
	if vehicle == null or not vehicle.is_player_driven or other == null:
		return
	if not other.is_in_group("vehicle"):
		return                      # walls, props and scenery are the player's own problem
	var occupied := false
	var od: Variant = other.get("driver")
	if od != null and is_instance_valid(od):
		occupied = true
	var other_police := bool(other.get("is_police"))
	if dv < (MAJOR_DV if (occupied or other_police) else MAJOR_DV_SOLO):
		return
	# fault: the player has to be the one who was moving
	var other_speed := 0.0
	if other is RigidBody3D:
		other_speed = (other as RigidBody3D).linear_velocity.length()
	if pre_speed < 5.0 or pre_speed < other_speed * 0.8:
		return
	_report("collision_major", vehicle, {
		"victim": od if occupied else other,
		"severity": clampf(dv / 9.0, 0.7, 1.8),
		"direct_police_witness": other_police and occupied,
	})


static func _report(crime_id: String, vehicle: VehicleBase, opts: Dictionary) -> void:
	var now := VehicleBase.now_msec()
	if now - int(_last_msec.get(crime_id, -100000)) < int(COOLDOWN_MSEC.get(crime_id, 1000)):
		return
	_last_msec[crime_id] = now
	opts["instigator"] = Game.player if Game.has_player() else vehicle.driver
	opts["vehicle"] = vehicle
	Wanted.report_crime(crime_id, vehicle.global_position, opts)
