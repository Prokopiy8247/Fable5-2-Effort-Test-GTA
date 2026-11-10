class_name PoliceRoadblock
extends RefCounted
## One roadblock (spec 18 / 18A, 3 stars+): two police cruisers parked across the road in a V with
## their light bars on, roadblock_police barricades in the gaps (dynamic props: they fly when rammed),
## officers crouched behind the cars, and from 4 stars spike strips (spike_strip asset) across the
## carriageway on the approach side. The police system owns the list, checks the spikes at 10 Hz
## (vehicle.pop_tire on overlap) and cleans the whole roadblock up when it is far away / old and
## nobody sees it.

const SPIKE_SCENE := "res://gta/generated/models/misc/spike_strip.glb"
const SPIKE_X_MIN := -2.1          ## spike_strip asset extent along its local X (manifest aabb)
const SPIKE_X_MAX := 3.4
const SPIKE_HALF_DEPTH := 0.42
const SPIKE_CENTER_X := 0.64       ## middle of the strip in its local X
const SPIKE_DIST := 17.0           ## metres in front of the cars (towards the incoming player)

var system: Node = null
var center: Vector3 = Vector3.ZERO
var approach: Vector3 = Vector3.FORWARD    ## unit vector from the roadblock towards the incoming player
var half_width: float = 5.5
var cars: Array[Node3D] = []
var props: Array[Node3D] = []
var spikes: Array[Node3D] = []
var spike_inv: Array[Transform3D] = []
var officers: Array[Node3D] = []
var age: float = 0.0
var spike_hits: int = 0
var with_spikes: bool = false
var point_index: int = -1                  ## index of the world's roadblock spawn point used


## Builds the roadblock. `xf.origin` = road centre (world "roadblock" spawn point), `toward` =
## direction from the roadblock to the incoming player (any length), `hw` = carriageway half width.
func build(p_system: Node, xf: Transform3D, toward: Vector3, hw: float, spikes_on: bool, officer_count: int) -> bool:
	system = p_system
	center = xf.origin
	var a := Vector3(toward.x, 0.0, toward.z)
	if a.length_squared() < 0.001:
		a = -xf.basis.z
		a.y = 0.0
	approach = a.normalized()
	half_width = clampf(hw, 3.5, 9.0)
	with_spikes = spikes_on
	var right := approach.cross(Vector3.UP).normalized()
	var offs := half_width * 0.44
	for k: float in [-1.0, 1.0]:
		var pos := center + right * (k * offs) + approach * (k * 0.7)
		# nose towards the centre line, turned a little towards the incoming traffic
		var head := (-right * k * 0.9 + approach * 0.42).normalized()
		var yaw := atan2(-head.x, -head.z)
		var t := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, center.y + 0.15, pos.z))
		var v := Game.spawn_vehicle("police_cruiser", t, {"owner_tag": "police", "asleep": true, "engine_on": false})
		if v == null:
			continue
		v.set("owner_tag", "police")
		v.set_meta("police_roadblock", true)
		v.add_to_group("police_vehicle")
		if v.has_method("set_siren"):
			v.call("set_siren", true)
		if WorldClock.get_daylight() < 0.3 and v.has_method("set_headlights"):
			v.call("set_headlights", 1)
		cars.append(v)
	if cars.is_empty():
		return false
	# barricades: centre gap and both road edges
	var bar_yaw := atan2(-right.z, right.x)
	var bar_basis := Basis(Vector3.UP, bar_yaw)
	for lat: float in [0.0, -(half_width - 1.2), half_width - 1.2]:
		var bp := center + right * lat + approach * (1.6 if lat == 0.0 else 0.6)
		var node := _spawn_prop("roadblock_police", Transform3D(bar_basis, Vector3(bp.x, _ground(bp), bp.z)))
		if node != null:
			props.append(node)
	if with_spikes:
		var n := clampi(int(ceil(half_width * 2.0 * 0.85 / 4.0)), 2, 4)
		var span := half_width * 2.0 * 0.85
		for i in n:
			var lat := -span * 0.5 + span * (float(i) + 0.5) / float(n)
			# the strip's own middle (local X = SPIKE_CENTER_X) sits on `lat`
			var sp := center + approach * SPIKE_DIST + right * (lat - SPIKE_CENTER_X)
			var sxf := Transform3D(bar_basis, Vector3(sp.x, _ground(sp) + 0.01, sp.z))
			var s := _spawn_spike(sxf)
			if s != null:
				spikes.append(s)
				spike_inv.append(sxf.affine_inverse())
	# officers in cover behind the cars (away from the player)
	for i in officer_count:
		var k := -1.0 if i % 2 == 0 else 1.0
		var cp := center - approach * (2.9 + 0.8 * floorf(float(i) * 0.5)) + right * (k * offs * 0.95)
		cp.y = _ground(cp)
		var o: Node3D = null
		if system != null and system.has_method("spawn_officer"):
			o = system.call("spawn_officer", "police_officer", cp, "roadblock", null, 0)
		if o == null:
			continue
		var b: Variant = o.get("brain")
		if b is Node and is_instance_valid(b):
			(b as Node).set("post", cp)
			(b as Node).set("post_face", center + approach * 40.0)
		o.call("face_position", center + approach * 40.0)
		officers.append(o)
	return true


func update(dt: float) -> void:
	age += dt
	for i in range(cars.size() - 1, -1, -1):
		var v := cars[i]
		if not is_instance_valid(v):
			cars.remove_at(i)
		elif bool(v.get("is_player_driven")) or str(v.get("owner_tag")) == "player":
			# the player took one of our cars: it is his now (theft is reported by the player module)
			v.remove_meta("police_roadblock")
			v.remove_from_group("police_vehicle")
			cars.remove_at(i)
	for i in range(officers.size() - 1, -1, -1):
		if not is_instance_valid(officers[i]):
			officers.remove_at(i)
	for i in range(props.size() - 1, -1, -1):
		if not is_instance_valid(props[i]):
			props.remove_at(i)


## Pops the tyres of vehicles whose wheels are over a strip. `vehicles`: candidates (Node3D).
func check_spikes(vehicles: Array, sweep: float = 0.1) -> void:
	if spikes.is_empty():
		return
	var mid := center + approach * SPIKE_DIST
	for vv: Variant in vehicles:
		if not (vv is RigidBody3D) or not is_instance_valid(vv):
			continue
		var v := vv as RigidBody3D
		if bool(v.get("is_police")) or bool(v.get("destroyed")):
			continue
		if v.linear_velocity.length() < 1.0:
			continue
		var vp := v.global_position
		if Vector2(vp.x - mid.x, vp.z - mid.z).length() > half_width + 8.0:
			continue
		if not v.has_method("get_wheel_count"):
			continue
		var nw := int(v.call("get_wheel_count"))
		for w in nw:
			if v.has_method("is_tire_flat") and bool(v.call("is_tire_flat", w)):
				continue
			var wp: Vector3 = v.call("get_wheel_position", w)
			# swept test: where the wheel was one check period ago (the strip is only 0.8 m deep and
			# a car at 20 m/s moves 2 m between two checks)
			var wp0 := wp - v.linear_velocity * sweep
			for k in spikes.size():
				if not is_instance_valid(spikes[k]):
					continue
				var lp := spike_inv[k] * wp
				var lp0 := spike_inv[k] * wp0
				if lp.y > 1.3 or lp.y < -0.6:
					continue
				var crossed := absf(lp.z) <= SPIKE_HALF_DEPTH or (signf(lp.z) != signf(lp0.z) and absf(lp.z - lp0.z) < 6.0)
				if not crossed:
					continue
				# lateral position where the wheel crossed the strip line
				var x := lp.x
				if absf(lp.z - lp0.z) > 0.001 and absf(lp.z) > SPIKE_HALF_DEPTH:
					x = lerpf(lp0.x, lp.x, lp0.z / (lp0.z - lp.z))
				if x >= SPIKE_X_MIN and x <= SPIKE_X_MAX:
					v.call("pop_tire", w)
					spike_hits += 1
					break


## Every Node3D of the roadblock (for view checks).
func get_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for a in [cars, props, spikes, officers]:
		for n: Variant in a:
			if n is Node3D and is_instance_valid(n):
				out.append(n as Node3D)
	return out


func living_officers() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for o in officers:
		if is_instance_valid(o) and not bool(o.get("is_dead")):
			out.append(o)
	return out


## Removes everything that is still ours (officers are freed by the system).
func cleanup() -> void:
	var vm := Game.get_system("vehicles")
	for v in cars:
		if not is_instance_valid(v):
			continue
		if bool(v.get("is_player_driven")) or v == Game.get_player_vehicle():
			continue
		if vm != null and vm.has_method("despawn_vehicle"):
			vm.call("despawn_vehicle", v)
		else:
			v.queue_free()
	cars.clear()
	for n in props:
		if is_instance_valid(n):
			n.queue_free()
	props.clear()
	for s in spikes:
		if is_instance_valid(s):
			s.queue_free()
	spikes.clear()
	spike_inv.clear()


func _spawn_prop(id: String, xf: Transform3D) -> Node3D:
	var ps := Game.get_system("props")
	if ps != null and ps.has_method("spawn_prop"):
		var n: Variant = ps.call("spawn_prop", id, xf)
		if n is Node3D and is_instance_valid(n):
			return n as Node3D
	return null


func _spawn_spike(xf: Transform3D) -> Node3D:
	var n := _spawn_prop("spike_strip", xf)
	if n != null:
		return n
	# the props catalog does not know it: instance the asset directly (visual only, no collider)
	if not ResourceLoader.exists(SPIKE_SCENE):
		return null
	var ps := load(SPIKE_SCENE) as PackedScene
	if ps == null:
		return null
	var node := ps.instantiate() as Node3D
	if node == null:
		return null
	node.name = "SpikeStrip"
	var root := Game.get_entities_root()
	if root == null:
		node.queue_free()
		return null
	root.add_child(node)
	node.global_transform = xf
	return node


func _ground(p: Vector3) -> float:
	if Game.world != null and Game.world.has_method("get_height"):
		return float(Game.world.call("get_height", p.x, p.z))
	return p.y
