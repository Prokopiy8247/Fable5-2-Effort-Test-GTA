extends RefCounted
## Geometric cover detection of the player (spec 10A "Cover system", ARCHITECTURE_WAVE2 W2.4: cover
## needs no markers). Used by PlayerStateCover; player.gd preloads this script (no class_name: the
## module's reserved names are Player, PlayerCamera, PlayerInteraction and PlayerState*).
##
## Everything is ray / shape casts against Layers.WORLD | VEHICLE | PROP with member query objects
## (nothing is allocated per tick except the result dictionaries of the engine).
##
##   probe(dir)                        best cover surface when the cover key is pressed: rays along
##                                     the stick / camera direction (glide up to SEARCH_REACH) plus a
##                                     ring around the body (RING_REACH). {} = nothing usable.
##   wall_at(feet, n)                  the surface behind a body standing at `feet` with its back to
##                                     wall normal `n` (re-checked every tick while in cover)
##   surface_continues(feet, n, side, offset)   edge detection along the wall (side +1 = along s)
##   edge_distance(feet, n, side, max)          distance from the body centre to the edge (bisection)
##   find_corner(feet, n, side)        outside corner beyond an edge that the player can swing round
##   classify(point, n)                {"height", "low"} or {} (too low / no face)
##
## Conventions: `n` = horizontal wall normal pointing OUT of the wall (towards the player). The body
## in cover stands STAND_OFF in front of the face with its back to it (it faces n).
## s = Vector3.UP.cross(n) runs along the wall: it is camera-RIGHT when the camera looks at the wall,
## which is the character's LEFT. side +1 = along s, -1 = against s.
##
## A cover dictionary: {"point": feet-level stand point, "normal": n, "wall": hit point on the face,
## "height": top of the cover above the floor, "low": bool, "collider": Object, "vehicle": the
## vehicle node the surface belongs to (or null), "distance": metres from the body to the face}.

const MASK := Layers.WORLD | Layers.VEHICLE | Layers.PROP
const STAND_OFF := 0.41                 ## capsule radius 0.35 + a 6 cm gap
const PROBE_Y := 0.55                   ## height of the horizontal search / edge rays (knee, car door)
const SEARCH_REACH := 3.0               ## along the stick / camera direction: glide distance
const RING_REACH := 1.3                 ## all around the body
const RING_RAYS := 12
const LOW_MIN := 0.85                   ## tops lower than this hide nothing
const HIGH_PROBE_Y := 1.55              ## a face at the standing shoot height = high cover
const TOP_SCAN := 2.6                   ## down rays for the top start this high above the floor
const MAX_STEP := 0.6                   ## the stand point may be this much above / below the feet
const MIN_SPAN := 0.3                   ## the face must continue this far to at least one side
const MOVING_SPEED := 0.8               ## rigid bodies faster than this are no cover
const NORMAL_MAX_Y := 0.4               ## faces steeper than this (|n.y|) are walls

var player: Player = null

var _ray := PhysicsRayQueryParameters3D.new()
var _shape_q := PhysicsShapeQueryParameters3D.new()
var _capsule := CapsuleShape3D.new()
var _space: PhysicsDirectSpaceState3D = null


func setup(p: Player) -> void:
	player = p
	_ray.collision_mask = MASK
	_ray.hit_back_faces = false
	_ray.hit_from_inside = false
	_shape_q.collision_mask = MASK
	_capsule.radius = Player.CAPSULE_RADIUS - 0.04
	_capsule.height = Player.CROUCH_HEIGHT - 0.12
	_shape_q.shape = _capsule
	var ex: Array[RID] = [p.get_rid()]
	_ray.exclude = ex
	_shape_q.exclude = ex


func _begin() -> bool:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	_space = player.get_world_3d().direct_space_state
	return _space != null


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	return _space.intersect_ray(_ray)


# =================================================================================================
# search
# =================================================================================================

## Best cover for the cover key. `pref` = preferred horizontal direction (stick, else camera).
func probe(pref: Vector3) -> Dictionary:
	if not _begin():
		return {}
	var feet := player.global_position
	var origin := feet + Vector3(0.0, PROBE_Y, 0.0)
	pref.y = 0.0
	var has_pref := pref.length_squared() > 0.0001
	if has_pref:
		pref = pref.normalized()
	var best: Dictionary = {}
	var best_score := INF
	if has_pref:
		for off: float in [0.0, -0.32, 0.32, -0.65, 0.65]:
			var d := pref.rotated(Vector3.UP, off)
			var c := _try_dir(origin, d, SEARCH_REACH)
			if c.is_empty():
				continue
			var score := float(c["distance"]) + absf(off) * 1.4
			if score < best_score:
				best_score = score
				best = c
	for i in RING_RAYS:
		var a := TAU * float(i) / float(RING_RAYS)
		var d := Vector3(sin(a), 0.0, cos(a))
		var c := _try_dir(origin, d, RING_REACH)
		if c.is_empty():
			continue
		var score := float(c["distance"]) + 0.5
		if has_pref:
			score += (1.0 - d.dot(pref)) * 0.9
		if score < best_score:
			best_score = score
			best = c
	return best


func _try_dir(origin: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var hit := _cast(origin, origin + dir * (Player.CAPSULE_RADIUS + reach))
	if hit.is_empty():
		return {}
	var n: Vector3 = hit["normal"]
	if absf(n.y) > NORMAL_MAX_Y:
		return {}
	n.y = 0.0
	if n.length_squared() < 0.0001:
		return {}
	n = n.normalized()
	if n.dot(-dir) < 0.35:
		return {}                       # grazing a face that runs along the ray
	var col: Object = hit.get("collider", null)
	if is_moving(col):
		return {}
	var wall: Vector3 = hit["position"]
	return evaluate(wall, n, col, Vector2(wall.x - origin.x, wall.z - origin.z).length())


## Validates a face hit at `wall` with normal `n`; returns the cover dictionary or {}.
func evaluate(wall: Vector3, n: Vector3, col: Object, distance: float) -> Dictionary:
	if _space == null and not _begin():
		return {}
	var feet_y := player.global_position.y
	var point := wall + n * STAND_OFF
	var fl := _cast(Vector3(point.x, feet_y + 0.9, point.z), Vector3(point.x, feet_y - MAX_STEP - 0.4, point.z))
	if fl.is_empty() or (fl["normal"] as Vector3).y < 0.7:
		return {}
	var floor_y: float = (fl["position"] as Vector3).y
	if absf(floor_y - feet_y) > MAX_STEP:
		return {}
	point.y = floor_y
	var cls := classify(point, n)
	if cls.is_empty():
		return {}
	if not (surface_continues(point, n, 1.0, MIN_SPAN) or surface_continues(point, n, -1.0, MIN_SPAN)):
		return {}                       # a post / pole: too narrow to hide behind
	if not capsule_free(point):
		return {}
	return {"point": point, "normal": n, "wall": wall, "height": cls["height"], "low": cls["low"],
			"collider": col, "vehicle": vehicle_of(col), "distance": distance}


## Height class of the cover in front of a body standing at `point` (feet) with its back to `n`.
## {} = no usable face (too low, or nothing at knee height).
func classify(point: Vector3, n: Vector3) -> Dictionary:
	if _space == null and not _begin():
		return {}
	var reach := STAND_OFF + 0.45
	var base := point + Vector3(0.0, PROBE_Y, 0.0)
	var face := _cast(base, base - n * reach)
	if face.is_empty():
		return {}
	var hi_from := point + Vector3(0.0, HIGH_PROBE_Y, 0.0)
	var high := not _cast(hi_from, hi_from - n * reach).is_empty()
	# the top: rays down just behind the face
	var face_pt: Vector3 = face["position"]
	var top := -INF
	for inset: float in [0.08, 0.22, 0.40]:
		var x := face_pt - n * inset
		var h := _cast(Vector3(x.x, point.y + TOP_SCAN, x.z), Vector3(x.x, point.y + 0.25, x.z))
		if not h.is_empty() and (h["normal"] as Vector3).y > 0.3:
			top = (h["position"] as Vector3).y
			break
	var height := 0.0
	if top > -INF:
		height = top - point.y
	elif high:
		height = TOP_SCAN               # taller than the scan (the down rays start inside it)
	else:
		# no top found from above and nothing at the high mark: bracket it with horizontal rays
		for y: float in [1.25, 0.95]:
			var o := point + Vector3(0.0, y, 0.0)
			if not _cast(o, o - n * reach).is_empty():
				height = y + 0.1
				break
	if high:
		height = maxf(height, HIGH_PROBE_Y + 0.05)
		return {"height": height, "low": false}
	if height < LOW_MIN:
		return {}
	return {"height": minf(height, HIGH_PROBE_Y), "low": true}


## The face behind a body at `feet` with its back to `n`: {"distance" (from the body centre),
## "normal", "position", "collider"} or {}.
func wall_at(feet: Vector3, n: Vector3, reach: float = STAND_OFF + 0.4) -> Dictionary:
	if not _begin():
		return {}
	var o := feet + Vector3(0.0, PROBE_Y, 0.0)
	var h := _cast(o, o - n * reach)
	if h.is_empty():
		return {}
	var hn: Vector3 = h["normal"]
	if absf(hn.y) > NORMAL_MAX_Y:
		return {}
	hn.y = 0.0
	hn = hn.normalized()
	var hp: Vector3 = h["position"]
	return {"distance": Vector2(hp.x - o.x, hp.z - o.z).length(), "normal": hn, "position": hp,
			"collider": h.get("collider", null)}


## Does the face continue `offset` metres to `side` (+1 along s, -1 against) of the body at `feet`?
func surface_continues(feet: Vector3, n: Vector3, side: float, offset: float) -> bool:
	if _space == null and not _begin():
		return false
	var s := Vector3.UP.cross(n)
	var o := feet + s * (side * offset) + Vector3(0.0, PROBE_Y, 0.0)
	var h := _cast(o, o - n * (STAND_OFF + 0.3))
	return not h.is_empty() and absf((h["normal"] as Vector3).y) < 0.5


## Distance from the body centre to the edge towards `side` (bisection, ~2 cm), INF = no edge
## within `max_dist`.
func edge_distance(feet: Vector3, n: Vector3, side: float, max_dist: float) -> float:
	if not _begin():
		return INF
	if surface_continues(feet, n, side, max_dist):
		return INF
	var lo := 0.0
	var hi := max_dist
	for i in 5:
		var mid := (lo + hi) * 0.5
		if surface_continues(feet, n, side, mid):
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Outside corner beyond the edge towards `side`: the end face of the cover must be at least
## ~0.9 m deep and offer cover itself. Returns {} or a cover dictionary + "corner" (feet level).
func find_corner(feet: Vector3, n: Vector3, side: float) -> Dictionary:
	if not _begin():
		return {}
	var s := Vector3.UP.cross(n) * side
	var base := feet + Vector3(0.0, PROBE_Y, 0.0)
	# a point beyond the edge and behind the face plane, next to where an end face would be
	var q := base + s * 0.95 - n * (STAND_OFF + 0.45)
	var h := _cast(q, q - s * 1.1)
	if h.is_empty():
		return {}
	var n2: Vector3 = h["normal"]
	n2.y = 0.0
	if n2.length_squared() < 0.25:
		return {}
	n2 = n2.normalized()
	if n2.dot(s) < 0.8:
		return {}
	var q2 := q - n * 0.45
	var h2 := _cast(q2, q2 - s * 1.1)
	if h2.is_empty() or (h2["normal"] as Vector3).dot(n2) < 0.8:
		return {}                       # a thin wall: no room to hide on the other side
	var hp: Vector3 = h["position"]
	var face_plane_pt := feet - n * STAND_OFF
	var corner := hp + n * (face_plane_pt - hp).dot(n)
	corner.y = feet.y
	var c := evaluate(corner + n2 * 0.02 - n * 0.32, n2, h.get("collider", null), 0.0)
	if c.is_empty():
		return {}
	c["corner"] = corner
	return c


func capsule_free(point: Vector3) -> bool:
	if _space == null and not _begin():
		return false
	_shape_q.transform = Transform3D(Basis.IDENTITY, point + Vector3(0.0, _capsule.height * 0.5 + 0.06, 0.0))
	return _space.intersect_shape(_shape_q, 1).is_empty()


static func is_moving(col: Variant) -> bool:
	if col is RigidBody3D and is_instance_valid(col):
		return (col as RigidBody3D).linear_velocity.length() > MOVING_SPEED
	return false


## The vehicle a collider belongs to (group "vehicle"), or null.
static func vehicle_of(col: Variant) -> Node3D:
	var n := col as Node
	var guard := 0
	while n != null and is_instance_valid(n) and guard < 4:
		if n.is_in_group("vehicle"):
			return n as Node3D
		n = n.get_parent()
		guard += 1
	return null
