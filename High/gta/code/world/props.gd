class_name PropManager
extends Node3D
## Instanced street furniture / nature (MultiMesh) with shared collision bodies. Light props turn into pooled
## rigid bodies when hit by vehicles, bullets or explosions; red barrels explode and chain-react.

const CELL := 10.0
const MAX_DYNAMIC := 34
const LIGHT := {"cone": 3.0, "bin": 12.0, "bench": 40.0, "hydrant": 30.0, "mailbox": 30.0, "newsbox": 15.0, "parking_meter": 10.0,
	"barrier_plastic": 14.0, "crate": 25.0, "pallet": 12.0, "barrel_red": 25.0, "barrel_blue": 25.0, "street_lamp": 90.0,
	"sign_stop": 12.0, "sign_speed": 12.0, "sign_parking": 12.0, "sign_street": 12.0, "bollard": 20.0, "fence_wood": 25.0,
	"picnic_table": 40.0, "beach_set": 20.0, "planter": 60.0, "stall": 45.0, "vending": 80.0, "atm": 80.0, "bush": 5.0,
	"fence_chain": 30.0, "target": 15.0, "trash": 4.0}
const NO_COLLIDE := ["grass_tuft", "flower", "seaweed", "coral", "bush", "helipad", "cone", "pallet"]

var recs: Array = []            # {asset, xf, alive, shape, mm, idx, light}
var _by_asset: Dictionary = {}
var _grid: Dictionary = {}
var _solid: StaticBody3D
var _soft: StaticBody3D
var _dyn: Array = []
var lamp_bulbs: PackedVector3Array = PackedVector3Array()
var _scan := 0


func add(asset: String, pos: Vector3, yaw: float = 0.0, scale: float = 1.0) -> void:
	if not Assets.has_asset(asset):
		return
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos)
	var r := {"asset": asset, "xf": xf, "alive": true, "shape": null, "idx": -1, "light": LIGHT.has(asset)}
	recs.append(r)
	if not _by_asset.has(asset):
		_by_asset[asset] = []
	_by_asset[asset].append(r)


func finalize() -> void:
	_solid = StaticBody3D.new()
	_solid.collision_layer = Game.L_WORLD
	_solid.collision_mask = 0
	add_child(_solid)
	_soft = StaticBody3D.new()
	_soft.collision_layer = Game.L_SOFT
	_soft.collision_mask = 0
	add_child(_soft)
	for asset in _by_asset:
		var list: Array = _by_asset[asset]
		var mesh := Assets.mesh_of(asset)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "MM_" + asset
		var big: bool = Assets.size_of(asset).size.length() > 6.0
		mmi.visibility_range_end = 420.0 if big else 190.0
		mmi.visibility_range_end_margin = 20.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if asset in ["grass_tuft", "flower"]:
			mmi.visibility_range_end = 70.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		var bb := Assets.size_of(asset)
		for i in range(list.size()):
			var r: Dictionary = list[i]
			r.mm = mm
			r.idx = i
			mm.set_instance_transform(i, r.xf)
			var key := _key(r.xf.origin)
			if not _grid.has(key):
				_grid[key] = []
			_grid[key].append(r)
			if asset in NO_COLLIDE:
				continue
			var cs := CollisionShape3D.new()
			var sc: float = r.xf.basis.get_scale().x
			if asset in ["tree_a", "tree_b", "tree_c", "pine", "palm", "street_lamp", "sign_stop", "sign_speed", "sign_parking", "sign_street", "bollard", "parking_meter"]:
				var cyl := CylinderShape3D.new()
				cyl.radius = 0.28 * sc if asset.begins_with("tree") or asset in ["pine", "palm"] else 0.12
				cyl.height = minf(bb.size.y * sc, 5.0)
				cs.shape = cyl
				cs.transform = Transform3D(Basis(), r.xf.origin + Vector3(0, cyl.height * 0.5, 0))
			else:
				var bs := BoxShape3D.new()
				bs.size = bb.size * sc
				cs.shape = bs
				cs.transform = Transform3D(r.xf.basis.orthonormalized(), r.xf * (bb.position + bb.size * 0.5))
			(_soft if r.light else _solid).add_child(cs)
			r.shape = cs
			if asset == "street_lamp":
				var bulb: Vector3 = r.xf * Vector3(0, 7.2, 2.2)
				r["lamp"] = lamp_bulbs.size()
				lamp_bulbs.append(bulb)


func _key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


func near(pos: Vector3, radius: float) -> Array:
	var out := []
	var k := _key(pos)
	var span := int(ceil(radius / CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := Vector2i(k.x + dx, k.y + dz)
			if _grid.has(key):
				for r in _grid[key]:
					if r.alive and (r.xf.origin as Vector3).distance_to(pos) < radius:
						out.append(r)
	return out


func _physics_process(_delta: float) -> void:
	# vehicles ploughing through light props
	_scan += 1
	for v in Game.vehicles:
		if not is_instance_valid(v) or v.parked:
			continue
		var sp: float = v.linear_velocity.length()
		if sp < 3.0:
			continue
		var reach: float = v._half.z + 1.2
		var inv: Transform3D = v.global_transform.affine_inverse()
		for r in near(v.global_position, reach + 1.0):
			if not r.light:
				continue
			var lp: Vector3 = inv * (r.xf.origin + Vector3.UP * 0.4)
			if absf(lp.x) < v._half.x + 0.45 and absf(lp.z) < reach and lp.y < 2.5 and lp.y > -1.0:
				var mass: float = LIGHT[r.asset]
				knock(r, v.linear_velocity * 0.85 + Vector3.UP * (2.0 + sp * 0.08))
				v.apply_central_impulse(-v.linear_velocity.normalized() * mass * sp * 0.25)
				if v.driver == Game.player and v.driver != null and mass > 20.0 and Game.cam:
					Game.cam.shake(0.12)
	var i := 0
	var now := Time.get_ticks_msec()
	while i < _dyn.size():
		var d = _dyn[i]
		if not is_instance_valid(d[0]) or now > d[1]:
			if is_instance_valid(d[0]):
				d[0].queue_free()
			_dyn.remove_at(i)
			continue
		i += 1


func knock(r: Dictionary, vel: Vector3) -> RigidBody3D:
	if not r.alive:
		return null
	r.alive = false
	r.mm.set_instance_transform(r.idx, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -100, 0)))
	if r.shape != null:
		r.shape.queue_free()
		r.shape = null
	if r.has("lamp"):
		lamp_bulbs[r.lamp] = Vector3(0, -1000, 0)
		if Game.daynight:
			Game.daynight.lamp_bulbs = lamp_bulbs
	var asset: String = r.asset
	if asset == "bush":
		Fx.dust(r.xf.origin + Vector3.UP * 0.5, 1.0, Color(0.3, 0.55, 0.25, 0.8))
		return null
	if asset == "hydrant":
		for k in range(8):
			get_tree().create_timer(k * 0.5).timeout.connect(func(): Fx.splash(r.xf.origin + Vector3.UP * 0.3, 1.6))
	if _dyn.size() >= MAX_DYNAMIC:
		var old = _dyn.pop_front()
		if is_instance_valid(old[0]):
			old[0].queue_free()
	var body := RigidBody3D.new()
	body.collision_layer = Game.L_PROP
	body.collision_mask = Game.L_WORLD | Game.L_VEHICLE | Game.L_PROP
	body.mass = LIGHT.get(asset, 20.0)
	var mi := MeshInstance3D.new()
	mi.mesh = r.mm.mesh
	body.add_child(mi)
	var bb := Assets.size_of(asset)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(maxf(bb.size.x, 0.15), maxf(bb.size.y, 0.15), maxf(bb.size.z, 0.15)) * 0.92
	cs.shape = bs
	cs.position = bb.position + bb.size * 0.5
	body.add_child(cs)
	add_child(body)
	body.global_transform = r.xf.orthonormalized()
	body.linear_velocity = vel
	body.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(-3, 3))
	body.set_meta("asset", asset)
	_dyn.append([body, Time.get_ticks_msec() + 30000])
	Sfx.play3d("crash_small", r.xf.origin, -6.0, randf_range(0.9, 1.3), 45.0)
	return body


func bullet_hit(collider, pos: Vector3, dir: Vector3, attacker) -> bool:
	if collider is RigidBody3D and collider.has_meta("asset"):
		if collider.get_meta("asset") == "barrel_red":
			var p: Vector3 = collider.global_position
			collider.queue_free()
			Fx.explosion(p + Vector3.UP * 0.4, 7.0, 200.0, attacker)
			return true
		return false
	if collider != _soft and collider != _solid:
		return false
	var best = null
	var bd := 2.2
	for r in near(pos, 2.6):
		var c: Vector3 = r.xf.origin + Vector3.UP * minf(Assets.size_of(r.asset).size.y * 0.5, 1.0)
		var d := Vector2(c.x - pos.x, c.z - pos.z).length()
		if d < bd:
			bd = d
			best = r
	if best == null:
		return false
	match best.asset:
		"barrel_red":
			best.alive = false
			best.mm.set_instance_transform(best.idx, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -100, 0)))
			if best.shape:
				best.shape.queue_free()
				best.shape = null
			Fx.explosion(best.xf.origin + Vector3.UP * 0.5, 7.0, 200.0, attacker)
		"cone", "bin", "barrel_blue", "crate", "newsbox", "trash", "target":
			knock(best, dir * 3.0 + Vector3.UP * 1.5)
			Fx.impact(pos, -dir, "metal")
		"bus_stop", "vending":
			Fx.impact(pos, -dir, "glass")
		"tree_a", "tree_b", "tree_c", "pine", "palm", "fence_wood", "bench", "picnic_table", "crate":
			Fx.impact(pos, -dir, "dirt")
		_:
			Fx.impact(pos, -dir, "metal")
	return true


func blast(pos: Vector3, radius: float, attacker) -> void:
	for r in near(pos, radius):
		if not r.alive:
			continue
		var o: Vector3 = r.xf.origin
		if r.asset == "barrel_red":
			r.alive = false
			r.mm.set_instance_transform(r.idx, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -100, 0)))
			if r.shape:
				r.shape.queue_free()
				r.shape = null
			get_tree().create_timer(randf_range(0.15, 0.45)).timeout.connect(func(): Fx.explosion(o + Vector3.UP * 0.5, 7.0, 200.0, attacker))
		elif r.light:
			var dir := (o - pos + Vector3.UP * 1.5).normalized()
			knock(r, dir * (5.0 + 8.0 * (1.0 - o.distance_to(pos) / radius)))
	for d in _dyn:
		if is_instance_valid(d[0]):
			var b: RigidBody3D = d[0]
			var dd := b.global_position.distance_to(pos)
			if dd < radius:
				b.apply_central_impulse((b.global_position - pos + Vector3.UP).normalized() * b.mass * 9.0 * (1.0 - dd / radius))
