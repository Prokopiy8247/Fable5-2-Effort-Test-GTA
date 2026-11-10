extends RefCounted
## PropSystem placer: vegetation, rocks and reef (WORLD DRESSING).
##
## Uses the WORLD nature placement kinds (tree_hill, tree_wild, tree_palm, tree_park, bush, rock,
## ground_cover, reef: they already avoid roads, paths, lots and the runway) and adds its own only
## where those leave gaps: the Signal Hill wood is thickened with a seeded jittered grid (patches of
## pine vs broadleaf from a noise field, clearings, the dirt road / paths / viewpoint sight line kept
## free), undergrowth and fallen logs; the park lawns get grass and flowers.

const HILL_C := Vector2(225.0, -128.0)
const HILL_R := 96.0

var sys: Node
var world: Node
var walk: Object
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var clearing := FastNoiseLite.new()
var _view: Transform3D = Transform3D(Basis.IDENTITY, Vector3.INF)
var _park: Dictionary = {}
var _trees_on_hill: Array[Vector3] = []


func run(s: Node) -> void:
	sys = s
	world = s.get("world")
	walk = world.get("walk")
	rng.seed = 520317
	noise.seed = 4711
	noise.frequency = 0.022
	clearing.seed = 1907
	clearing.frequency = 0.03
	if world.has_method("has_location") and bool(world.call("has_location", "hill_viewpoint")):
		_view = world.call("get_location", "hill_viewpoint")
	for lot: Dictionary in world.call("get_lots"):
		if String(lot.get("zone", "")) == "park":
			_park = lot
			break
	_hill_trees()
	sys.call("mark_phase", "nature.hill_trees")
	_hill_fill()
	sys.call("mark_phase", "nature.hill_fill")
	_other_trees()
	sys.call("mark_phase", "nature.other_trees")
	_bushes()
	sys.call("mark_phase", "nature.bushes")
	_rocks()
	sys.call("mark_phase", "nature.rocks")
	_ground_cover()
	sys.call("mark_phase", "nature.ground_cover")
	_park_lawn()
	sys.call("mark_phase", "nature.park_lawn")
	_reef()
	sys.call("mark_phase", "nature.reef")


func place(id: String, xf: Transform3D, opts: Dictionary = {}) -> int:
	return int(sys.call("place", id, xf, opts))


func g(x: float, z: float) -> float:
	return float(sys.call("ground", x, z))


func pts(kind: String) -> Array:
	return sys.call("spawn_points", kind)


func path_dist(p: Vector3) -> float:
	if walk == null:
		return INF
	var q: Vector3 = walk.call("get_nearest_point", p)
	if q == Vector3.INF:
		return INF
	return Vector2(q.x - p.x, q.z - p.z).length()


func rot(yaw: float, scale: float = 1.0) -> Basis:
	return Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))


## Would a tree of `height` at p block the view from the hill viewpoint?
func blocks_view(p: Vector3, height: float) -> bool:
	if _view.origin == Vector3.INF:
		return false
	var fwd := -_view.basis.z
	var d := Vector2(p.x - _view.origin.x, p.z - _view.origin.z)
	var dist := d.length()
	if dist > 70.0 or dist < 0.5:
		return dist <= 0.5
	var f2 := Vector2(fwd.x, fwd.z).normalized()
	if d.normalized().dot(f2) < cos(deg_to_rad(34.0)):
		return false
	return p.y + height > _view.origin.y - 0.5


func tree_height(id: String) -> float:
	var d: Dictionary = sys.call("get_prop_def", id)
	return float(d.get("height", 8.0))


# ---------------------------------------------------------------------------------------------
# Signal Hill wood
# ---------------------------------------------------------------------------------------------

func hill_species(p: Vector3) -> String:
	var n := noise.get_noise_2d(p.x, p.z)
	var r := rng.randf()
	if r < 0.03:
		return "tree_dead"
	if p.y > 25.0 or n > 0.12:
		return "tree_pine_a" if rng.randf() < 0.55 else "tree_pine_b"
	if r < 0.45:
		return "tree_broadleaf_a"
	if r < 0.8:
		return "tree_broadleaf_b"
	return "tree_broadleaf_c" if r < 0.9 else "tree_small_a"


func _hill_trees() -> void:
	for xf: Transform3D in pts("tree_hill"):
		var p := xf.origin
		var id := hill_species(p)
		var sc := rng.randf_range(0.85, 1.2)
		if blocks_view(p, tree_height(id) * sc):
			continue
		if place(id, Transform3D(rot(rng.randf() * TAU, sc), p), {"r": 2.0, "tag": "tree_hill"}) >= 0:
			_trees_on_hill.append(p)


func _hill_fill() -> void:
	var step := 5.6
	var added := 0
	var x := HILL_C.x - HILL_R
	while x <= HILL_C.x + HILL_R:
		var z := HILL_C.y - HILL_R
		while z <= HILL_C.y + HILL_R:
			var q := Vector2(x + rng.randf_range(-1.8, 1.8), z + rng.randf_range(-1.8, 1.8))
			z += step
			if q.distance_to(HILL_C) > HILL_R:
				continue
			if q.y > -40.0 or q.x < 130.0:
				continue
			if clearing.get_noise_2d(q.x, q.y) > 0.32:
				continue      # glades
			var h := g(q.x, q.y)
			if h < 5.5:
				continue
			var p := Vector3(q.x, h, q.y)
			if not bool(sys.call("is_free", p, 2.3)):
				continue
			var slope := absf(g(q.x + 2.0, q.y) - g(q.x - 2.0, q.y)) + absf(g(q.x, q.y + 2.0) - g(q.x, q.y - 2.0))
			if slope > 5.0:
				continue
			var surf := String(sys.call("surface_at", q.x, q.y))
			if surf != "grass":
				continue
			if bool(sys.call("on_carriageway", p, 6.0)):
				continue
			if path_dist(p) < 3.2:
				continue
			var id := hill_species(p)
			var sc := rng.randf_range(0.8, 1.15)
			if blocks_view(p, tree_height(id) * sc):
				continue
			if place(id, Transform3D(rot(rng.randf() * TAU, sc), p), {"r": 2.0, "tag": "tree_hill"}) >= 0:
				_trees_on_hill.append(p)
				added += 1
		x += step
	# undergrowth around the trunks: grass tufts, ferns and the odd bush
	for p: Vector3 in _trees_on_hill:
		if rng.randf() < 0.65:
			for k in rng.randi_range(3, 6):
				var ga := rng.randf() * TAU
				var gq := p + Vector3(cos(ga), 0.0, sin(ga)) * rng.randf_range(0.9, 3.4)
				if bool(sys.call("on_carriageway", gq, 0.5)):
					continue
				var gid := "grass_tuft_a" if rng.randf() < 0.5 else "grass_tuft_b"
				if k == 0 and rng.randf() < 0.3:
					gid = "fern"
				place(gid, Transform3D(rot(rng.randf() * TAU, rng.randf_range(0.9, 1.4)), Vector3(gq.x, g(gq.x, gq.z) - 0.02, gq.z)),
						{"no_occ": true, "tag": "ground_cover"})
		var r := rng.randf()
		if r < 0.45:
			var a := rng.randf() * TAU
			var q := p + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(1.4, 2.6)
			if path_dist(q) > 1.5 and not bool(sys.call("on_carriageway", q, 1.5)):
				place("fern", Transform3D(rot(rng.randf() * TAU, rng.randf_range(0.9, 1.3)), Vector3(q.x, g(q.x, q.z), q.z)),
						{"no_occ": true, "tag": "ground_cover"})
		elif r < 0.6:
			var a2 := rng.randf() * TAU
			var q2 := p + Vector3(cos(a2), 0.0, sin(a2)) * rng.randf_range(2.0, 3.2)
			if path_dist(q2) > 1.8 and bool(sys.call("is_free", q2, 0.6)) and not bool(sys.call("on_carriageway", q2, 2.0)):
				place("bush_b" if rng.randf() < 0.6 else "bush_a", Transform3D(rot(rng.randf() * TAU), Vector3(q2.x, g(q2.x, q2.z), q2.z)),
						{"r": 0.8, "tag": "bush"})
	# fallen logs in the wood
	var logs := 0
	var tries := 0
	while logs < 16 and tries < 300 and not _trees_on_hill.is_empty():
		tries += 1
		var base: Vector3 = _trees_on_hill[rng.randi() % _trees_on_hill.size()]
		var a3 := rng.randf() * TAU
		var q3 := base + Vector3(cos(a3), 0.0, sin(a3)) * rng.randf_range(2.8, 4.0)
		q3.y = g(q3.x, q3.z)
		if path_dist(q3) < 2.5 or bool(sys.call("on_carriageway", q3, 3.0)) or not bool(sys.call("is_free", q3, 1.4)):
			continue
		if place("log", Transform3D(rot(rng.randf() * TAU), q3), {"r": 1.3, "tag": "log"}) >= 0:
			logs += 1
	sys.set_meta(&"hill_fill_trees", added)


# ---------------------------------------------------------------------------------------------
# other trees (WORLD points)
# ---------------------------------------------------------------------------------------------

func _other_trees() -> void:
	for xf: Transform3D in pts("tree_wild"):
		var r := rng.randf()
		var id := "tree_broadleaf_a"
		if r < 0.12:
			id = "tree_dead"
		elif r < 0.27:
			id = "tree_pine_b"
		elif r < 0.5:
			id = "tree_broadleaf_b"
		elif r < 0.65:
			id = "tree_broadleaf_c"
		place(id, Transform3D(rot(rng.randf() * TAU, rng.randf_range(0.85, 1.15)), xf.origin), {"r": 2.0, "tag": "tree_wild"})
	var k := 0
	for xf: Transform3D in pts("tree_palm"):
		place("palm_a" if k % 3 != 1 else "palm_b", Transform3D(rot(rng.randf() * TAU, rng.randf_range(0.9, 1.15)), xf.origin),
				{"r": 1.6, "tag": "tree_palm"})
		k += 1
	for xf: Transform3D in pts("tree_park"):
		var r2 := rng.randf()
		var id2 := "tree_broadleaf_c" if r2 < 0.4 else ("tree_broadleaf_a" if r2 < 0.75 else "tree_small_a")
		place(id2, Transform3D(rot(rng.randf() * TAU, rng.randf_range(0.85, 1.1)), xf.origin), {"r": 1.8, "tag": "tree_park"})


func _bushes() -> void:
	for xf: Transform3D in pts("bush"):
		var p := xf.origin
		var dist := String(world.call("get_district", p))
		var id := "bush_a"
		var r := rng.randf()
		if dist == "hill":
			id = "bush_b" if r < 0.6 else ("bush_a" if r < 0.85 else "bush_c")
		elif dist == "residential":
			id = "bush_c" if r < 0.45 else ("hedge_ball" if r < 0.6 else "bush_a")
		elif dist == "beach":
			id = "bush_a" if r < 0.7 else "bush_b"
		else:
			id = "bush_a" if r < 0.5 else ("bush_b" if r < 0.8 else "bush_c")
		place(id, Transform3D(rot(rng.randf() * TAU, rng.randf_range(0.85, 1.25)), p), {"r": 0.9, "tag": "bush"})


# ---------------------------------------------------------------------------------------------
# rocks and cliff chunks
# ---------------------------------------------------------------------------------------------

func _near_water(p: Vector3, d: float) -> bool:
	for a in 8:
		var ang := a * TAU / 8.0
		if float(world.call("get_water_depth", p.x + cos(ang) * d, p.z + sin(ang) * d)) > 0.2:
			return true
	return false


func _rocks() -> void:
	for xf: Transform3D in pts("rock"):
		var p := xf.origin
		var shore := p.y < 4.0 and _near_water(p, 12.0)
		var id := "rock_c"
		var yaw := rng.randf() * TAU
		if shore:
			var dx := g(p.x + 2.0, p.z) - g(p.x - 2.0, p.z)
			var dz := g(p.x, p.z + 2.0) - g(p.x, p.z - 2.0)
			var down := Vector2(-dx, -dz)
			var big_ok := path_dist(p) > 6.0 and not bool(sys.call("on_carriageway", p, 6.0))
			if big_ok and down.length() > 0.05 and rng.randf() < 0.55:
				id = "cliff_chunk_a" if rng.randf() < 0.6 else "cliff_chunk_b"
				down = down.normalized()
				yaw = atan2(-down.x, -down.y)
			else:
				id = "rock_e" if rng.randf() < 0.5 else "rock_d"
		else:
			var r := rng.randf()
			id = "rock_c" if r < 0.4 else ("rock_d" if r < 0.75 else "rock_e")
		var i := place(id, Transform3D(rot(yaw, rng.randf_range(0.85, 1.2)), p), {"r": 1.4 if id.begins_with("rock") else 3.5, "tag": "rock"})
		if i < 0:
			continue
		# scatter of small stones around the big one
		for k in rng.randi_range(1, 3):
			var a := rng.randf() * TAU
			var q := p + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(1.6, 3.4)
			if path_dist(q) < 1.2 or bool(sys.call("on_carriageway", q, 1.0)):
				continue
			place("rock_a" if rng.randf() < 0.6 else "rock_b", Transform3D(rot(rng.randf() * TAU, rng.randf_range(0.8, 1.3)),
					Vector3(q.x, g(q.x, q.z), q.z)), {"r": 0.4, "tag": "rock"})


# ---------------------------------------------------------------------------------------------
# ground cover (MultiMesh, short visibility range)
# ---------------------------------------------------------------------------------------------

func _in_park(p: Vector3) -> bool:
	if _park.is_empty():
		return false
	var c: Vector3 = _park["center"]
	var s: Vector2 = _park["size"]
	var yaw := float(_park["yaw"])
	var dx := p.x - c.x
	var dz := p.z - c.z
	var lx := dx * cos(yaw) - dz * sin(yaw)
	var lz := dx * sin(yaw) + dz * cos(yaw)
	return absf(lx) <= s.x * 0.5 and absf(lz) <= s.y * 0.5


func _tuft(id: String, q: Vector3, sc: float) -> void:
	place(id, Transform3D(rot(rng.randf() * TAU, sc), Vector3(q.x, g(q.x, q.z) - 0.02, q.z)), {"no_occ": true, "tag": "ground_cover"})


func _ground_cover() -> void:
	for xf: Transform3D in pts("ground_cover"):
		var p := xf.origin
		var dist := String(world.call("get_district", p))
		var low := p.y < 1.5 and _near_water(p, 6.0)
		if low:
			for k in rng.randi_range(2, 4):
				var q := p + Vector3(rng.randf_range(-1.6, 1.6), 0.0, rng.randf_range(-1.6, 1.6))
				if float(world.call("get_water_depth", q.x, q.z)) < 0.3:
					_tuft("reeds", q, rng.randf_range(0.8, 1.2))
			continue
		var hill := dist == "hill" and p.y > 5.0
		var n := rng.randi_range(4, 7)
		for k in n:
			var q := p + Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5))
			var r := rng.randf()
			var id := "grass_tuft_a" if r < 0.5 else "grass_tuft_b"
			if hill and k == 0 and rng.randf() < 0.6:
				id = "fern"
			elif k == 0 and rng.randf() < (0.35 if dist != "hill" else 0.15):
				id = "flower_patch_a" if rng.randf() < 0.5 else "flower_patch_b"
			_tuft(id, q, rng.randf_range(0.8, 1.35))


func _park_lawn() -> void:
	if _park.is_empty():
		return
	var c: Vector3 = _park["center"]
	var s: Vector2 = _park["size"]
	var placed := 0
	var tries := 0
	while placed < 220 and tries < 900:
		tries += 1
		var q := c + Vector3(rng.randf_range(-s.x * 0.5 + 0.6, s.x * 0.5 - 0.6), 0.0, rng.randf_range(-s.y * 0.5 + 0.6, s.y * 0.5 - 0.6))
		if path_dist(q) < 1.6 or not bool(sys.call("is_free", q, 0.5)):
			continue
		var r := rng.randf()
		var id := "grass_tuft_a" if r < 0.45 else ("grass_tuft_b" if r < 0.8 else ("flower_patch_a" if r < 0.9 else "flower_patch_b"))
		_tuft(id, q, rng.randf_range(0.9, 1.3))
		placed += 1
	# flower beds and clipped shrubs along the lot edges
	var yaw := float(_park["yaw"])
	var basis := Basis(Vector3.UP, yaw)
	for k in 14:
		var side := -1.0 if k % 2 == 0 else 1.0
		var lz := -s.y * 0.5 + 4.0 + floorf(k / 2.0) * (s.y - 8.0) / 6.0
		var q2 := c + basis * Vector3(side * (s.x * 0.5 - 0.9), 0.0, lz)
		if path_dist(q2) < 1.4 or not bool(sys.call("is_free", q2, 0.7)):
			continue
		var id2 := "hedge_ball" if k % 3 == 0 else ("bush_c" if k % 3 == 1 else "flower_patch_b")
		place(id2, Transform3D(rot(rng.randf() * TAU), Vector3(q2.x, g(q2.x, q2.z), q2.z)), {"r": 0.7, "tag": "bush"})


# ---------------------------------------------------------------------------------------------
# reef: corals, kelp (only where it stays under water), shells, starfish
# ---------------------------------------------------------------------------------------------

func _reef() -> void:
	var wreck := Vector3.INF
	if world.has_method("has_location") and bool(world.call("has_location", "shipwreck")):
		wreck = (world.call("get_location", "shipwreck") as Transform3D).origin
	for xf: Transform3D in pts("reef"):
		var p := xf.origin
		var depth := float(world.call("get_water_depth", p.x, p.z))
		var near_wreck := wreck != Vector3.INF and Vector2(p.x - wreck.x, p.z - wreck.z).length() < 50.0
		var r := rng.randf()
		var kelp_share := 0.4 if near_wreck else 0.18
		var id := "coral_a"
		var sc := rng.randf_range(0.8, 1.5)
		if r < kelp_share and depth > 6.5:
			id = "kelp_a"
			sc = clampf((depth - 1.5) / 5.3, 0.6, 1.25) * rng.randf_range(0.85, 1.0)
		else:
			var r2 := rng.randf()
			id = "coral_a" if r2 < 0.35 else ("coral_b" if r2 < 0.7 else "coral_c")
		place(id, Transform3D(rot(rng.randf() * TAU, sc), p), {"no_occ": true, "road_ok": true, "tag": "reef"})
		for k in rng.randi_range(0, 2):
			var q := p + Vector3(rng.randf_range(-1.8, 1.8), 0.0, rng.randf_range(-1.8, 1.8))
			var sid := "seashell" if rng.randf() < 0.55 else "starfish"
			if k == 1 and rng.randf() < 0.5:
				sid = "coral_c"
			place(sid, Transform3D(rot(rng.randf() * TAU, rng.randf_range(0.9, 1.4)), Vector3(q.x, g(q.x, q.z), q.z)),
					{"no_occ": true, "road_ok": true, "tag": "reef"})
