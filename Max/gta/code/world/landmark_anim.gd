class_name LandmarkAnim
extends Node
## Moving parts of the Blender landmarks: sliding shop doors that open for people, the
## safehouse front door and garage door, the barber pole, the control-tower beacon, the
## lighthouse lamp (with a sweeping beam at night) and the pier ferris wheel.

class Door:
	extends RefCounted
	var nodes: Array[Node3D] = []
	var rest: Array[Transform3D] = []
	var kind := "slide"          # slide | hinge | roll
	var at := Vector3.ZERO       # trigger point
	var radius := 3.5
	var vehicles := false        # opens for the player's vehicle (garages)
	var open := 0.0

var doors: Array[Door] = []
var spinners: Array = []        # [Node3D, axis (local), speed rad/s, rest Basis]
var wheel: Node3D = null
var wheel_rest := Basis.IDENTITY
var gondolas: Array[Node3D] = []
var axle := Vector3.ZERO
var wheel_angle := 0.0
var beam: SpotLight3D = null
var _tick := 0.0
var _near: Dictionary = {}

func _ready() -> void:
	var city: CityBuilder = Game.world.city
	for key in city.locations.keys():
		var loc: Dictionary = city.locations[key]
		var root: Node3D = loc.get("root")
		if root == null or not is_instance_valid(root):
			continue
		var id := String(loc.get("id", key))
		match id:
			"shop_guns", "shop_clothes", "shop_market", "shop_barber":
				var d := Door.new()
				for nm: String in ["door_l", "door_r"]:
					var n := PropFactory.part(root, nm)
					if n != null:
						d.nodes.append(n)
						d.rest.append(n.transform)
				if not d.nodes.is_empty():
					var m: Variant = city.marker(String(key), "entrance")
					d.at = (m as Transform3D).origin if m != null else root.global_position
					doors.append(d)
				if id == "shop_barber":
					_spin(PropFactory.part(root, "pole"), Vector3.UP, 2.4)
			"safehouse":
				var fd := PropFactory.part(root, "door")
				if fd != null:
					var d2 := Door.new()
					d2.kind = "hinge"
					d2.nodes.append(fd)
					d2.rest.append(fd.transform)
					var m2: Variant = city.marker(String(key), "entrance")
					d2.at = (m2 as Transform3D).origin if m2 != null else fd.global_position
					d2.radius = 2.8
					doors.append(d2)
				var gd := PropFactory.part(root, "garage_door")
				if gd != null:
					var d3 := Door.new()
					d3.kind = "roll"
					d3.nodes.append(gd)
					d3.rest.append(gd.transform)
					var m3: Variant = city.marker(String(key), "garage_out")
					d3.at = (m3 as Transform3D).origin if m3 != null else gd.global_position
					d3.radius = 9.0
					d3.vehicles = true
					doors.append(d3)
			"lm_control_tower":
				_spin(PropFactory.part(root, "beacon"), Vector3.UP, 3.0)
			"lm_lighthouse":
				var lamp := PropFactory.part(root, "lamp")
				_spin(lamp, Vector3.UP, 1.1)
				if lamp != null:
					beam = SpotLight3D.new()
					beam.light_color = Color(1.0, 0.93, 0.75)
					beam.light_energy = 8.0
					beam.spot_range = 160.0
					beam.spot_angle = 7.0
					beam.shadow_enabled = false
					beam.visible = false
					lamp.add_child(beam)
					beam.rotation = Vector3(-0.08, 0.0, 0.0)
			"lm_ferris_wheel":
				wheel = PropFactory.part(root, "wheel")
				if wheel != null:
					wheel_rest = wheel.transform.basis
					axle = wheel.position
				for k in 12:
					var g := PropFactory.part(root, "gondola_%02d" % (k + 1))
					if g != null:
						gondolas.append(g)
	print("[Landmarks] animated: %d doors, %d spinners, ferris wheel %s, lighthouse beam %s" % [doors.size(), spinners.size(), wheel != null, beam != null])

func _spin(n: Node3D, axis: Vector3, speed: float) -> void:
	if n != null:
		spinners.append([n, axis, speed, n.transform.basis])

func _process(delta: float) -> void:
	for s in spinners:
		var n: Node3D = s[0]
		if is_instance_valid(n):
			n.transform.basis = (s[3] as Basis) * Basis(s[1], Game.clock * float(s[2]))
	if beam != null:
		beam.visible = Game.time != null and Game.time.night > 0.35
	if wheel != null and is_instance_valid(wheel):
		wheel_angle += delta * 0.12
		wheel.transform.basis = wheel_rest * Basis(Vector3.BACK, wheel_angle)
		for k in gondolas.size():
			var a := wheel_angle + float(k) * TAU / float(gondolas.size())
			gondolas[k].position = axle + Vector3(cos(a), sin(a), 0.0) * 11.0
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.15
		_update_triggers()
	for d in doors:
		var target := 1.0 if _near.get(d, false) else 0.0
		if absf(d.open - target) < 0.001:
			continue
		d.open = move_toward(d.open, target, delta * (2.5 if d.kind == "slide" else 1.2))
		for i in d.nodes.size():
			var n: Node3D = d.nodes[i]
			var r: Transform3D = d.rest[i]
			match d.kind:
				"slide":
					var dirx := -1.0 if String(n.name).ends_with("door_l") else 1.0
					n.transform = Transform3D(r.basis, r.origin + r.basis.x.normalized() * dirx * 0.8 * d.open)
				"hinge":
					n.transform = Transform3D(r.basis * Basis(Vector3.UP, -1.6 * d.open), r.origin)
				"roll":
					# rolls up into the lintel: scale toward the top-edge origin
					n.transform = Transform3D(r.basis * Basis.from_scale(Vector3(1.0, maxf(1.0 - d.open, 0.03), 1.0)), r.origin)

func _update_triggers() -> void:
	var p: Player = Game.player
	if p == null:
		return
	for d in doors:
		var near := false
		if d.vehicles:
			near = p.vehicle != null and is_instance_valid(p.vehicle) and (p.vehicle as Node3D).global_position.distance_to(d.at) < d.radius
		else:
			near = p.vehicle == null and p.global_position.distance_to(d.at) < d.radius + 1.5
			if not near:
				for n in get_tree().get_nodes_in_group(&"npcs"):
					var c := n as NPC
					if c.alive and c.vehicle == null and c.global_position.distance_squared_to(d.at) < d.radius * d.radius:
						near = true
						break
		_near[d] = near
