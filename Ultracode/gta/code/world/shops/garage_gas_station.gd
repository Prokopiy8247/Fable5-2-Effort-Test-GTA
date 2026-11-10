extends Node3D
## Halcyon Fuel (landmark `gas_station`) - created by the garage system.
##  * In-vehicle quick service under the canopy: flat tyres fixed and the engine patched up to 75 %
##    health for a small fee (much cheaper than Torque Garage's full repair).
##  * The four pumps (`Pump_1..4`, separate mesh objects of the landmark GLB) get small static
##    colliders on Layers.PROP when the city builder exposes the building: bullets, explosions,
##    fire and crashes wear them down; at 0 they blow up (Fx.explosion + fire), which chains to the
##    neighbouring pumps. They are restored after a while when the player is far away.
## The kiosk counter (`Use_Kiosk`) and the staff NPC belong to the shop system (Economy A).

const Sites := preload("res://gta/code/world/shops/garage_sites.gd")
const Stats := preload("res://gta/code/world/shops/garage_stats.gd")

const LANDMARK := "gas_station"
const PUMPS := ["Pump_1", "Pump_2", "Pump_3", "Pump_4"]
const SERVICE_RADIUS := 6.0
const PUMP_HEALTH := 60.0
const PUMP_RESTORE_SECONDS := 150.0
const PUMP_RESTORE_DISTANCE := 90.0
const BLAST_RADIUS := 7.5
const BLAST_DAMAGE := 240.0
const DAMAGE_SCALE := {"bullet": 1.0, "explosion": 1.0, "fire": 0.6, "melee": 0.25, "collision": 0.5, "vehicle": 0.5}


## One collider per pump; damage is forwarded to the station (Dmg.find_damageable finds this).
class PumpBody:
	extends StaticBody3D
	var station: Node = null
	var index: int = -1

	func apply_damage(info: Dictionary) -> void:
		if station != null and is_instance_valid(station):
			station.call("damage_pump", index, info)


var system: Node = null
var service_point: Interactable = null
var service_xform: Transform3D = Transform3D.IDENTITY
var source: String = ""
var enabled: bool = true
var pumps: Array[Dictionary] = []      ## {mesh, body, health, destroyed, since, position}
var _tick: float = 0.0


func setup_site(sys: Node) -> void:
	system = sys
	service_point = Interactable.create("Halcyon Fuel - quick service", SERVICE_RADIUS, "interact")
	service_point.name = "ServicePoint"
	service_point.in_vehicle_only = true
	service_point.on_foot_only = false
	service_point.use_priority = 3
	service_point.condition = _can_offer
	add_child(service_point)
	service_point.interacted.connect(_on_service)
	relocate()


func relocate() -> void:
	# canopy centre = between the pump islands (average of the pump markers)
	var sum := Vector3.ZERO
	var n := 0
	var srcs := {}
	for p: String in PUMPS:
		var r := Sites.marker(LANDMARK, p)
		if bool(r["ok"]):
			sum += (r["xform"] as Transform3D).origin
			n += 1
			srcs[str(r["source"])] = true
	if n > 0:
		var b := Sites.landmark_transform(LANDMARK)
		var yaw := Sites.yaw_of(b["xform"]) if bool(b["ok"]) else 0.0
		service_xform = Transform3D(Basis(Vector3.UP, yaw), sum / float(n))
	else:
		service_xform = Game.get_location(LANDMARK)
		srcs["location"] = true
	source = ",".join(PackedStringArray(srcs.keys()))
	if service_point != null:
		service_point.global_position = service_xform.origin + Vector3(0.0, 0.6, 0.0)
	_bind_pumps()


func set_enabled(on: bool) -> void:
	enabled = on
	if service_point != null:
		service_point.enabled = on


# --- quick service ------------------------------------------------------------------------------

func _can_offer(player: Node3D) -> bool:
	if not enabled:
		return false
	var v: Variant = player.get("current_vehicle")
	if v == null or not is_instance_valid(v) or Stats.flag(v, "destroyed"):
		return false
	var rb := v as RigidBody3D
	if rb != null and rb.linear_velocity.length() > 3.0:
		return false
	var c := Stats.condition(v)
	if not Stats.needs_service(c):
		return false
	var cost := Stats.service_cost(v)
	service_point.prompt = "Halcyon Fuel - quick service (%s)" % ("free" if cost <= 0 else Stats.money(cost))
	return true


func _on_service(player: Node3D) -> void:
	var v: Variant = player.get("current_vehicle")
	if v == null or not is_instance_valid(v):
		return
	await service(v as Node3D)


## Tyres + engine patched to Stats.SERVICE_HEALTH. Returns true when the service was paid for.
func service(v: Node3D) -> bool:
	var c := Stats.condition(v)
	if not Stats.needs_service(c):
		UI.notify("Your vehicle is fine", "info")
		return false
	var cost := Stats.service_cost(v)
	if not Game.spend(cost):
		UI.notify("Quick service costs %s" % Stats.money(cost), "warn")
		Audio.play("ui_error", -6.0, 1.0, "UI")
		return false
	await UI.fade_out(0.25)
	apply_service(v)
	Audio.play_at("wrench", v.global_position, 0.0, 1.0, 30.0)
	await UI.fade_in(0.25)
	EventBus.item_purchased.emit("vehicle_service", "gas_quick_service", cost)
	UI.notify("Tyres fixed, engine patched up (%s)" % ("free" if cost <= 0 else Stats.money(cost)), "money")
	return true


## The partial repair itself (no money involved). Uses the vehicle's own fix_tires() when it
## exists; otherwise repair() (which also replaces glass) and then caps the health again.
func apply_service(v: Node3D) -> void:
	var hp := float(v.get("health"))
	var mx := float(v.get("max_health"))
	var target := maxf(hp, mx * Stats.SERVICE_HEALTH)
	if v.has_method("fix_tires"):
		v.call("fix_tires")
	elif v.has_method("repair"):
		v.call("repair")
	v.set("health", minf(target, mx))
	EventBus.vehicle_modified.emit(v)


# --- explosive pumps ----------------------------------------------------------------------------

func _bind_pumps() -> void:
	var node := Sites.landmark_node(LANDMARK)
	if node == null:
		return
	for i in PUMPS.size():
		if i < pumps.size() and is_instance_valid(pumps[i].get("mesh")):
			continue
		var mesh := node.find_child(PUMPS[i], true, false) as Node3D
		if mesh == null:
			continue
		var body := PumpBody.new()
		body.name = "PumpBody%d" % (i + 1)
		body.station = self
		body.index = pumps.size()
		body.collision_layer = Layers.PROP
		body.collision_mask = 0
		body.add_to_group("damageable")
		body.set_meta("surface", "metal")
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var aabb := _mesh_aabb(mesh)
		box.size = Vector3(maxf(aabb.size.x, 0.4), maxf(aabb.size.y, 1.0), maxf(aabb.size.z, 0.4))
		shape.shape = box
		body.add_child(shape)
		add_child(body)
		body.global_transform = Transform3D(Basis(Vector3.UP, mesh.global_rotation.y), mesh.global_transform * aabb.get_center())
		pumps.append({"mesh": mesh, "body": body, "shape": shape, "health": PUMP_HEALTH, "destroyed": false,
				"since": 0.0, "position": mesh.global_position})


static func _mesh_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var list: Array[Node] = [n]
	list.append_array(n.find_children("*", "MeshInstance3D", true, false))
	for c: Node in list:
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var rel := n.global_transform.affine_inverse() * mi.global_transform
		var a := rel * mi.get_aabb()
		out = a if first else out.merge(a)
		first = false
	if first:
		return AABB(Vector3(-0.4, 0.0, -0.3), Vector3(0.8, 1.8, 0.6))
	return out


func get_pump_count() -> int:
	return pumps.size()


func is_pump_destroyed(i: int) -> bool:
	return i >= 0 and i < pumps.size() and bool(pumps[i]["destroyed"])


func damage_pump(i: int, info: Dictionary) -> void:
	if i < 0 or i >= pumps.size() or bool(pumps[i]["destroyed"]):
		return
	var kind := str(info.get("type", "generic"))
	var amount := float(info.get("amount", 0.0)) * float(DAMAGE_SCALE.get(kind, 0.4))
	pumps[i]["health"] = float(pumps[i]["health"]) - amount
	if float(pumps[i]["health"]) <= 0.0:
		var who: Variant = info.get("instigator", null)
		explode_pump(i, who as Node if (who != null and is_instance_valid(who)) else null)


func explode_pump(i: int, instigator: Node = null) -> void:
	if i < 0 or i >= pumps.size() or bool(pumps[i]["destroyed"]):
		return
	var p: Dictionary = pumps[i]
	p["destroyed"] = true
	p["since"] = 0.0
	var mesh := p["mesh"] as Node3D
	var pos: Vector3 = p["position"]
	if is_instance_valid(mesh):
		pos = mesh.global_position
		mesh.visible = false
	var shape := p["shape"] as CollisionShape3D
	if is_instance_valid(shape):
		shape.set_deferred("disabled", true)
	Fx.explosion(pos + Vector3(0.0, 0.9, 0.0), BLAST_RADIUS, BLAST_DAMAGE, instigator)
	Fx.spawn_fire(pos + Vector3(0.0, 0.3, 0.0), 14.0, null, 1.3)
	set_process(true)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	var any := false
	var ppos := Game.get_player_position()
	for p: Dictionary in pumps:
		if not bool(p["destroyed"]):
			continue
		p["since"] = float(p["since"]) + 1.0
		if float(p["since"]) >= PUMP_RESTORE_SECONDS and ppos.distance_to(p["position"]) > PUMP_RESTORE_DISTANCE:
			_restore(p)
		else:
			any = true
	if not any:
		set_process(false)


func _restore(p: Dictionary) -> void:
	p["destroyed"] = false
	p["health"] = PUMP_HEALTH
	var mesh := p["mesh"] as Node3D
	if is_instance_valid(mesh):
		mesh.visible = true
	var shape := p["shape"] as CollisionShape3D
	if is_instance_valid(shape):
		shape.disabled = false


func reset_for_respawn() -> void:
	pass
