extends RefCounted
## Explosion damage + force resolution used by Fx.explosion (kept apart from the visuals so it can
## be reasoned about and tested on its own).
##
## One call = one sphere shape query over PLAYER | NPC | VEHICLE | PROP | RAGDOLL | GLASS.
##   * damage: exactly ONE Dmg application per damageable owner (Dmg.find_damageable, de-duplicated
##     over all of its colliders), falloff measured from the closest point of the owner's shapes;
##   * line of sight: a ray on Layers.WORLD from the blast to the target attenuates (not blocks)
##     damage and push by LOS_FACTOR;
##   * force: radial impulse on every RigidBody3D / PhysicalBone3D (mass aware, slight up bias);
##   * characters get `info.impulse` + `info.direction` so their own code can knock them down.

const MASK := Layers.PLAYER | Layers.NPC | Layers.VEHICLE | Layers.PROP | Layers.RAGDOLL | Layers.GLASS
const CORE := 0.15            ## inner fraction of the radius that takes full damage
const LOS_FACTOR := 0.25      ## damage / force multiplier behind solid world geometry
const MAX_RESULTS := 64
const IMPULSE_POWER := 11.0   ## m/s delta-v for a light body at the centre of a 160 dmg blast
const MASS_KNEE := 350.0      ## bodies much heavier than this get progressively less delta-v
const CHAR_IMPULSE_MIN := 140.0
const CHAR_IMPULSE_MAX := 650.0

var _shape := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _ray := PhysicsRayQueryParameters3D.new()
var _convex_aabb: Dictionary = {}     # shape instance id -> AABB (small cache)


func _init() -> void:
	_query.shape = _shape
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_query.collision_mask = MASK
	_ray.collision_mask = Layers.WORLD
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true


## Damage multiplier at `dist` metres: 1 inside the core, then a blend of linear and quadratic
## falloff ("linear-to-quadratic": t * (0.5 + 0.5 t)), 0 at the radius.
static func falloff(dist: float, radius: float) -> float:
	if radius <= 0.0 or dist >= radius:
		return 0.0
	var t := clampf((radius - dist) / (radius * (1.0 - CORE)), 0.0, 1.0)
	return t * (0.5 + 0.5 * t)


## Runs the blast. opts: "ignore": Array[Node] (never damaged / pushed, children included),
## "los": bool (default true), "force": float (impulse multiplier, default 1),
## "weapon_id": String. Returns {"damaged": int, "pushed": int, "targets": Array[Node]}.
func detonate(space: PhysicsDirectSpaceState3D, center: Vector3, radius: float, damage: float,
		instigator: Node, opts: Dictionary) -> Dictionary:
	var out := {"damaged": 0, "pushed": 0, "targets": []}
	if space == null or radius <= 0.0:
		return out
	_shape.radius = radius
	_query.transform = Transform3D(Basis.IDENTITY, center)
	var results: Array[Dictionary] = space.intersect_shape(_query, MAX_RESULTS)
	if results.is_empty():
		return out
	var ignore: Array = opts.get("ignore", [])
	var use_los := bool(opts.get("los", true))
	var force := float(opts.get("force", 1.0))
	var weapon_id := str(opts.get("weapon_id", ""))
	var ray_from := center + Vector3(0.0, 0.25, 0.0)

	var owners: Dictionary = {}     # owner id -> [owner, distance, closest point]
	var bodies: Dictionary = {}     # body id -> [body, distance, closest point]
	for r: Dictionary in results:
		var col := r.get("collider", null) as Node
		if col == null or not is_instance_valid(col) or _is_ignored(col, ignore):
			continue
		var cp := closest_point(col, center)
		var dist := cp.distance_to(center)
		var target := Dmg.find_damageable(col)
		if target != null and not _is_ignored(target, ignore):
			var tid := target.get_instance_id()
			if not owners.has(tid) or dist < float(owners[tid][1]):
				owners[tid] = [target, dist, cp]
		if col is RigidBody3D or col is PhysicalBone3D:
			bodies[col.get_instance_id()] = [col, dist, cp]

	# --- damage: one application per owner -------------------------------------------------------
	var los_cache: Dictionary = {}
	for tid: int in owners:
		var entry: Array = owners[tid]
		var target: Node = entry[0]
		if not is_instance_valid(target):
			continue
		var dist: float = entry[1]
		var cp: Vector3 = entry[2]
		var aim := _aim_point(target, cp)
		var los := 1.0
		if use_los and _blocked(space, ray_from, aim):
			los = LOS_FACTOR
		los_cache[tid] = los
		var f := falloff(dist, radius) * los
		if f <= 0.001:
			continue
		var dir := _push_dir(center, aim)
		var info := Dmg.make(damage * f, "explosion", instigator, cp, dir, {
			"impulse": lerpf(CHAR_IMPULSE_MIN, CHAR_IMPULSE_MAX, f) * force,
			"normal": -dir,
			"weapon_id": weapon_id,
			"radius": radius,
			"falloff": f,
			"knockdown": f >= 0.2,
		})
		target.call("apply_damage", info)
		out["damaged"] = int(out["damaged"]) + 1
		(out["targets"] as Array).append(target)

	# --- force: radial impulse on dynamic bodies -------------------------------------------------
	var power := IMPULSE_POWER * clampf(damage / 160.0, 0.35, 2.0) * force
	for bid: int in bodies:
		var entry: Array = bodies[bid]
		var body := entry[0] as PhysicsBody3D
		if body == null or not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var rb := body as RigidBody3D
		if rb != null and rb.freeze:
			continue
		var dist: float = entry[1]
		var cp: Vector3 = entry[2]
		var los := float(los_cache.get(bid, -1.0))
		if los < 0.0:
			los = LOS_FACTOR if (use_los and _blocked(space, ray_from, _lift(cp, center))) else 1.0
		var f := falloff(dist, radius) * los
		if f <= 0.001:
			continue
		var mass := 1.0
		if rb != null:
			mass = rb.mass
		elif body is PhysicalBone3D:
			mass = (body as PhysicalBone3D).mass
		var com := body.global_position
		if rb != null:
			com = rb.global_transform * rb.center_of_mass
		var dir := _push_dir(center, com)
		var impulse := dir * (f * power * mass / (1.0 + mass / MASS_KNEE))
		if rb != null:
			rb.sleeping = false
			rb.apply_impulse(impulse, (cp - rb.global_position) * 0.25)
		else:
			body.call("apply_impulse", impulse, Vector3.ZERO)
		out["pushed"] = int(out["pushed"]) + 1
	return out


## True when static world geometry separates the two points.
func blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	return _blocked(space, from, to)


## Closest point (world space) of a collider's shapes to `center`. Vehicles expose `body_aabb`
## (local AABB of the shell); other bodies use their box / sphere / capsule / cylinder / convex
## shapes; anything else falls back to the node origin.
func closest_point(node: Node, center: Vector3) -> Vector3:
	var n3 := node as Node3D
	if n3 == null or not n3.is_inside_tree():
		return center
	var bb: Variant = node.get("body_aabb")
	if bb is AABB and (bb as AABB).size != Vector3.ZERO:
		var box: AABB = bb
		var local: Vector3 = n3.global_transform.affine_inverse() * center
		return n3.global_transform * local.clamp(box.position, box.end)
	var co := node as CollisionObject3D
	if co == null:
		return n3.global_position
	var best := n3.global_position
	var best_d := INF
	for owner_id: int in co.get_shape_owners():
		if co.is_shape_owner_disabled(owner_id):
			continue
		var xf := co.global_transform * co.shape_owner_get_transform(owner_id)
		var inv := xf.affine_inverse()
		for s in co.shape_owner_get_shape_count(owner_id):
			var shape := co.shape_owner_get_shape(owner_id, s)
			var local := inv * center
			var p := Vector3.ZERO
			if shape is SphereShape3D:
				var r := (shape as SphereShape3D).radius
				p = local if local.length() <= r else local.normalized() * r
			else:
				var box := _shape_aabb(shape)
				p = local.clamp(box.position, box.end)
			var w := xf * p
			var dd := w.distance_squared_to(center)
			if dd < best_d:
				best_d = dd
				best = w
	return best


func _shape_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var sz := (shape as BoxShape3D).size
		return AABB(-sz * 0.5, sz)
	if shape is CapsuleShape3D:
		var c := shape as CapsuleShape3D
		return AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2.0, c.height, c.radius * 2.0))
	if shape is CylinderShape3D:
		var cy := shape as CylinderShape3D
		return AABB(Vector3(-cy.radius, -cy.height * 0.5, -cy.radius), Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0))
	if shape is ConvexPolygonShape3D:
		var id := shape.get_instance_id()
		if _convex_aabb.has(id):
			return _convex_aabb[id]
		var pts := (shape as ConvexPolygonShape3D).points
		var box := AABB()
		if pts.size() > 0:
			box = AABB(pts[0], Vector3.ZERO)
			for p in pts:
				box = box.expand(p)
		if _convex_aabb.size() > 128:
			_convex_aabb.clear()
		_convex_aabb[id] = box
		return box
	return AABB()


static func _is_ignored(node: Node, ignore: Array) -> bool:
	if ignore.is_empty():
		return false
	var n := node
	var guard := 0
	while n != null and guard < 8:
		if ignore.has(n):
			return true
		n = n.get_parent()
		guard += 1
	return false


## Where the blast "looks" at a target: chest of a character, centre of a vehicle, else the
## closest point (lifted a little so rays do not skim the ground).
static func _aim_point(target: Node, closest: Vector3) -> Vector3:
	if target.has_method("get_target_position"):
		var v: Variant = target.call("get_target_position")
		if v is Vector3:
			return v
	if target.has_method("get_center_position"):
		var c: Variant = target.call("get_center_position")
		if c is Vector3:
			return c
	if target is CharacterBody3D:
		return (target as Node3D).global_position + Vector3(0.0, 0.95, 0.0)
	return closest + Vector3(0.0, 0.12, 0.0)


static func _lift(point: Vector3, center: Vector3) -> Vector3:
	return point + Vector3(0.0, 0.12, 0.0) + (center - point).limit_length(0.05)


static func _push_dir(center: Vector3, to: Vector3) -> Vector3:
	var d := to - center
	if d.length_squared() < 0.0004:
		return Vector3.UP
	d = d.normalized()
	d.y += 0.35
	return d.normalized()


func _blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var d := to - from
	var l := d.length()
	if l < 0.3:
		return false
	_ray.from = from
	_ray.to = to - d / l * 0.1
	return not space.intersect_ray(_ray).is_empty()
