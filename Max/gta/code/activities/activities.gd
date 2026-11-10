class_name Activities
extends Node
## Optional free-roam hobbies (no missions): unique stunt jumps with slow motion and landing
## zones, and the Ironworks shooting range with timed pop-up target challenges and medals.

const JUMPS := [
	# name, ramp centre (y from the ground), launch direction, minimum distance past the lip, lateral tolerance
	["Scrapyard Leap", Vector3(182.0, 0.0, 112.0), Vector3(0, 0, -1), 12.0, 9.0],
	["Runway Rocket", Vector3(279.0, 0.0, 30.0), Vector3(0, 0, -1), 18.0, 12.0],
	["Apron Arc", Vector3(252.0, 0.0, -60.0), Vector3(0, 0, 1), 15.0, 9.0],
	["Coral Beach Hop", Vector3(-200.0, 0.0, 228.0), Vector3(-1, 0, 0), 15.0, 5.5],
]
## Car-sized kicker: the Blender ramp (4 x 7 x 1.8) is stretched to this size so the curve is
## gentle enough for raycast suspension at 30 m/s; the collider is an exact parabolic trimesh.
const RAMP_SIZE := Vector3(4.0, 2.0, 16.0)     # width, height, length

const CHALLENGES := [
	{"name": "Pistol Plinking", "weapon": &"pistol", "time": 30.0, "near": 7.0, "far": 16.0, "up": 2.6, "medals": [12, 20, 28]},
	{"name": "SMG Sweep", "weapon": &"smg", "time": 30.0, "near": 8.0, "far": 18.0, "up": 2.0, "medals": [14, 24, 34]},
	{"name": "Rifle Reach", "weapon": &"rifle_assault", "time": 35.0, "near": 14.0, "far": 25.0, "up": 2.8, "medals": [12, 22, 32]},
	{"name": "Shotgun Rush", "weapon": &"shotgun_pump", "time": 30.0, "near": 5.0, "far": 11.0, "up": 1.8, "medals": [10, 18, 26]},
]

class RangeTarget:
	extends StaticBody3D
	var owner_act: Node = null
	var centre := Vector3.ZERO           # bullseye in local space
	var up := false
	var face: Node3D = null
	var face_rest := Basis.IDENTITY
	var asset := false

	func apply_damage(_amount: float, source: Node = null, hit_pos := Vector3.ZERO, _dir := Vector3.ZERO, _info: Dictionary = {}) -> void:
		if not up or source != Game.player:
			return
		var d := (to_local(hit_pos) - centre).length()
		var pts := 3 if d < 0.1 else (2 if d < 0.2 else 1)
		owner_act.target_hit(self, pts)

var completed: Dictionary = {}        # jump name -> true
var best: Dictionary = {}             # challenge name -> best score
var ramps: Array = []                 # {def, lip: Vector3, dir: Vector3, land: Vector3, r: float}
var _tracking := -1
var _track_t := 0.0
# range state
var _ch: Dictionary = {}
var _range_t := 0.0
var _score := 0
var _hits := 0
var _shown := 0
var _targets: Array[RangeTarget] = []
var _next_pop := 0.0
var _loaner := false
var _range_root: Node3D = null
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 1999
	for j in JUMPS:
		_build_ramp(j)
	print("[Activities] %d stunt jumps, %d range challenges" % [ramps.size(), CHALLENGES.size()])

func busy() -> bool:
	return not _ch.is_empty()

# ---------------------------------------------------------------- stunt jumps
func _surface(p: Vector3) -> Vector3:
	var hit := Game.ray(p + Vector3(0, 30.0, 0), p - Vector3(0, 30.0, 0), Phys.WORLD)
	return (hit["position"] as Vector3) if not hit.is_empty() else Vector3(p.x, Game.ground_y(p.x, p.z), p.z)

func _build_ramp(j: Array) -> void:
	var centre := _surface(j[1])
	var dirv: Vector3 = (j[2] as Vector3).normalized()
	var yaw := atan2(-dirv.x, -dirv.z)      # local -Z (asset +Y) along the launch direction
	var root := _procedural_ramp(centre, yaw, Assets.has_model("props/prop_ramp_stunt"))
	var lip := centre + dirv * (RAMP_SIZE.z * 0.5) + Vector3(0, RAMP_SIZE.y, 0)
	ramps.append({"name": j[0], "lip": lip, "dir": dirv, "min": float(j[3]), "lat": float(j[4]), "start": centre - dirv * RAMP_SIZE.z * 0.5})
	var key := "stunt_%d" % ramps.size()
	Game.world.city.locations[key] = {"id": "stunt", "root": root, "markers": {}, "pos": centre - dirv * 12.0}

## Parabolic kicker (height = H * t^2 along the launch direction). Visual: the Blender
## `prop_ramp_stunt` stretched to size when it exists, otherwise plank strips built here.
func _procedural_ramp(centre: Vector3, yaw: float, use_asset: bool) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "StuntRamp"
	body.collision_layer = Phys.WORLD
	body.collision_mask = 0
	Game.world.city.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), centre)
	var w := RAMP_SIZE.x * 0.5
	var h := RAMP_SIZE.y
	var l := RAMP_SIZE.z * 0.5
	var n := 14
	# profile points: z from +l (start, ground) to -l (lip), y = h * t^2
	var prof: Array[Vector3] = []
	for i in n + 1:
		var t := float(i) / float(n)
		prof.append(Vector3(0, h * t * t, l - 2.0 * l * t))
	var faces := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck := Color(0.79, 0.64, 0.29)
	var frame := Color(0.2, 0.21, 0.24)
	var stripe := Color(0.95, 0.75, 0.1)
	for i in n:
		var a: Vector3 = prof[i]
		var b: Vector3 = prof[i + 1]
		var q := [a + Vector3(-w, 0, 0), a + Vector3(w, 0, 0), b + Vector3(w, 0, 0), b + Vector3(-w, 0, 0)]
		faces.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
		var c := deck if i % 2 == 0 else deck.darkened(0.12)
		if i == n - 1:
			c = stripe
		_quad(st, q[0], q[1], q[2], q[3], c)
		# side skirts down to the ground
		_quad(st, Vector3(-w, 0, a.z), a + Vector3(-w, 0, 0), b + Vector3(-w, 0, 0), Vector3(-w, 0, b.z), frame)
		_quad(st, Vector3(w, 0, b.z), b + Vector3(w, 0, 0), a + Vector3(w, 0, 0), Vector3(w, 0, a.z), frame)
		faces.append_array(PackedVector3Array([Vector3(-w, 0, a.z), a + Vector3(-w, 0, 0), b + Vector3(-w, 0, 0),
			Vector3(w, 0, b.z), b + Vector3(w, 0, 0), a + Vector3(w, 0, 0)]))
	var top: Vector3 = prof[n]
	_quad(st, Vector3(-w, 0, top.z), top + Vector3(-w, 0, 0), top + Vector3(w, 0, 0), Vector3(w, 0, top.z), frame)
	faces.append_array(PackedVector3Array([Vector3(-w, 0, top.z), top + Vector3(-w, 0, 0), top + Vector3(w, 0, 0),
		Vector3(-w, 0, top.z), top + Vector3(w, 0, 0), Vector3(w, 0, top.z)]))
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	if use_asset:
		var vis := Assets.instance("props/prop_ramp_stunt")
		body.add_child(vis)
		vis.scale = Vector3(RAMP_SIZE.x / 4.0, RAMP_SIZE.y / 1.8, RAMP_SIZE.z / 7.0)
		var col := PropFactory.part(vis, "col")
		if col != null:
			col.visible = false
		return body
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	mi.material_override = mat
	body.add_child(mi)
	return body

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for v in [a, b, c]:
		st.set_color(col)
		st.add_vertex(v)

func _physics_process(delta: float) -> void:
	_range_tick(delta)
	var p: Player = Game.player
	if p == null or p.vehicle == null or not (p.vehicle is Car) or p.passenger:
		_tracking = -1
		return
	var car := p.vehicle as Car
	if _tracking >= 0:
		_track_t += delta
		if _track_t > 0.9:
			Game.set_slowmo("stunt", 1.0)
		if _track_t > 8.0:
			_tracking = -1
			Game.set_slowmo("stunt", 1.0)
		return
	if car.airborne_time > 0.0 and car.airborne_time < 0.25:
		var hv := Vector3(car.linear_velocity.x, 0.0, car.linear_velocity.z)
		for i in ramps.size():
			var r: Dictionary = ramps[i]
			if car.air_start.distance_to(r["lip"]) < 4.5 and hv.dot(r["dir"]) > 11.0:
				_tracking = i
				_track_t = 0.0
				Game.set_slowmo("stunt", 0.4)
				if Game.cam != null:
					Game.cam.shake(0.15)
				break

## Called by Car._landed for every landing after more than 0.6 s in the air.
func on_jump(vehicle: Vehicle, air_time: float, dist: float, upright: bool) -> void:
	if vehicle == null or not vehicle.has_player():
		return
	Game.stats["best_jump"] = maxf(float(Game.stats["best_jump"]), dist)
	if _tracking < 0:
		if air_time > 1.6 and upright:
			Game.notify("Air time %.1f s, %d m" % [air_time, int(dist)], "good")
		return
	var r: Dictionary = ramps[_tracking]
	_tracking = -1
	Game.set_slowmo("stunt", 1.0)
	var rel: Vector3 = vehicle.global_position - (r["lip"] as Vector3)
	var dirv: Vector3 = r["dir"]
	var along := rel.dot(dirv)
	var lateral := absf(rel.dot(Vector3(-dirv.z, 0.0, dirv.x)))
	dist = maxf(dist, along)
	if upright and along >= float(r["min"]) and lateral <= float(r["lat"]):
		var first := not completed.has(r["name"])
		completed[r["name"]] = true
		var reward := 1000 if first else 150
		Game.add_cash(reward)
		if first:
			Game.stats["stunt_jumps"] += 1
		Game.banner("STUNT JUMP COMPLETED", "%s  -  %d m  -  $%d%s" % [r["name"], int(dist), reward, "" if first else " (repeat)"], Color(1.0, 0.6, 0.2), 4.0)
		Audio.play_ui(&"ui_success", -4.0)
		if Game.skills:
			Game.skills.add(&"driving", 0.03)
	else:
		Game.banner("STUNT JUMP FAILED", String(r["name"]) + ("  -  missed the landing" if upright else "  -  crashed"), Color(0.8, 0.8, 0.85), 3.0)
		Audio.play_ui(&"ui_fail", -6.0)

# ---------------------------------------------------------------- shooting range
func _range_loc() -> Dictionary:
	return Game.world.city.locations.get("range", {})

func open_range() -> void:
	if busy() or Game.menus == null:
		return
	Game.menus.open_menu("shop", "Ironworks Range", "Timed target challenges", _range_rows, false, false, Color(1.0, 0.45, 0.4))

func _range_rows() -> Array:
	var rows: Array = []
	for c in CHALLENGES:
		var m: Array = c["medals"]
		var b := int(best.get(c["name"], 0))
		var medal := "Gold" if b >= int(m[2]) else ("Silver" if b >= int(m[1]) else ("Bronze" if b >= int(m[0]) else "-"))
		var cc: Dictionary = c
		rows.append({"text": String(c["name"]), "right": "best %d  (%s)" % [b, medal],
			"desc": "%s, %d seconds. Targets pop up %d-%d m away. Bullseye 3 points, inner ring 2, outer 1. Medals at %d / %d / %d points." % [
				String(WeaponDB.get_w(c["weapon"])["name"]), int(c["time"]), int(c["near"]), int(c["far"]), int(m[0]), int(m[1]), int(m[2])],
			"fn": func() -> void:
				Game.menus.menu.close()
				start_challenge(cc)})
	rows.append({"text": "Leave", "fn": func() -> void: Game.menus.menu.close()})
	return rows

func start_challenge(c: Dictionary) -> void:
	var loc := _range_loc()
	if loc.is_empty():
		return
	var p: Player = Game.player
	var from: Vector3 = loc.get("lane_from", loc["pos"])
	var dirv: Vector3 = loc.get("lane_dir", Vector3(0, 0, -1))
	p.teleport(from, atan2(-dirv.x, -dirv.z))
	if Game.cam != null:
		Game.cam.yaw = atan2(-dirv.x, -dirv.z)
		Game.cam.snap()
	var wid: StringName = c["weapon"]
	_loaner = not p.inventory.has(wid)
	p.inventory.give(wid, int(WeaponDB.get_w(wid).get("reserve", 60)))
	p.inventory.items[wid]["mag"] = p.inventory.mag_size(wid)
	p.gunner.equip(wid)
	_ch = c
	_range_t = float(c["time"])
	_score = 0
	_hits = 0
	_shown = 0
	_next_pop = 1.5
	_range_root = Node3D.new()
	_range_root.name = "RangeTargets"
	Game.world.city.add_child(_range_root)
	Game.banner(String(c["name"]).to_upper(), "Shoot the targets  -  %d seconds" % int(c["time"]), Color(1.0, 0.45, 0.4), 2.0)
	Audio.play_ui(&"ui_countdown", -4.0)

func _spawn_target() -> void:
	var loc := _range_loc()
	var from: Vector3 = loc.get("lane_from", loc["pos"])
	var dirv: Vector3 = (loc.get("lane_dir", Vector3(0, 0, -1)) as Vector3).normalized()
	var side := Vector3(-dirv.z, 0.0, dirv.x)
	var dist := _rng.randf_range(float(_ch["near"]), float(_ch["far"]))
	var lateral := _rng.randf_range(-7.5, 7.5) * clampf(dist / 20.0, 0.4, 1.0)
	var pos := _surface(from + dirv * dist + side * lateral)
	var t := RangeTarget.new()
	t.owner_act = self
	t.collision_layer = Phys.PROP
	t.collision_mask = 0
	_range_root.add_child(t)
	if PropFactory.exists("prop_target_round"):
		# Blender target: disc faces local -Z, `target` part hinges on its bottom edge
		t.global_transform = Transform3D(Basis(Vector3.UP, atan2(dirv.x, dirv.z)), pos)
		var inst := Assets.instance("props/prop_target_round" if (_rng.randf() < 0.65 or not PropFactory.exists("prop_target_man")) else "props/prop_target_man")
		t.add_child(inst)
		t.face = PropFactory.part(inst, "target")
		if t.face != null:
			t.asset = true
			t.face_rest = t.face.transform.basis
			var cs2 := CollisionShape3D.new()
			var cyl2 := CylinderShape3D.new()
			cyl2.radius = 0.32
			cyl2.height = 0.06
			cs2.shape = cyl2
			cs2.rotation.x = PI * 0.5
			cs2.position = Vector3(0, 1.2, 0)
			t.add_child(cs2)
			t.centre = Vector3(0, 1.2, 0)
			t.up = true
			t.set_meta("life", float(_ch["up"]))
			t.set_meta("flip", 0.0)
			_targets.append(t)
			_shown += 1
			Audio.play(&"climb", pos, -8.0)
			return
		inst.queue_free()
	t.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dirv.x, -dirv.z)), pos)   # local +Z faces the firing line
	# post + disc facing the shooter (local +Z toward the firing line)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.08, 1.2, 0.08)
	post.mesh = pm
	post.position = Vector3(0, 0.6, -0.05)
	post.material_override = _mat(Color(0.25, 0.25, 0.28))
	t.add_child(post)
	t.face = Node3D.new()
	t.face.position = Vector3(0, 1.2, 0)
	t.add_child(t.face)
	for ring in [[0.3, Color(0.95, 0.95, 0.92)], [0.2, Color(0.15, 0.15, 0.17)], [0.1, Color(0.85, 0.15, 0.12)]]:
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(ring[0])
		cm.bottom_radius = float(ring[0])
		cm.height = 0.03
		cm.radial_segments = 24
		disc.mesh = cm
		disc.rotation.x = PI * 0.5
		disc.position = Vector3(0, 0, 0.02 * (0.3 - float(ring[0])) * 10.0)
		disc.material_override = _mat(ring[1])
		t.face.add_child(disc)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3
	cyl.height = 0.06
	cs.shape = cyl
	cs.rotation.x = PI * 0.5
	cs.position = Vector3(0, 1.2, 0)
	t.add_child(cs)
	t.centre = Vector3(0, 1.2, 0)
	t.face.rotation.x = -PI * 0.5           # starts flat, flips up
	t.up = true
	t.set_meta("life", float(_ch["up"]))
	t.set_meta("flip", 0.0)
	_targets.append(t)
	_shown += 1
	Audio.play(&"climb", pos, -8.0)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m

func target_hit(t: RangeTarget, pts: int) -> void:
	t.up = false
	_score += pts
	_hits += 1
	Audio.play_ui(&"ui_checkpoint" if pts < 3 else &"ui_success", -10.0)

func _range_tick(delta: float) -> void:
	if _ch.is_empty():
		return
	var p: Player = Game.player
	var loc := _range_loc()
	var from: Vector3 = loc.get("lane_from", loc["pos"])
	if p == null or not p.alive or p.vehicle != null or p.global_position.distance_to(from) > 12.0:
		_end_challenge(true)
		return
	_range_t -= delta
	_next_pop -= delta
	if _next_pop <= 0.0 and _range_t > 1.0:
		_next_pop = _rng.randf_range(0.7, 1.4)
		var live := 0
		for t in _targets:
			if t.up:
				live += 1
		if live < 3:
			_spawn_target()
	for i in range(_targets.size() - 1, -1, -1):
		var t := _targets[i]
		var flip := float(t.get_meta("flip"))
		if t.up:
			flip = minf(1.0, flip + delta * 6.0)
			t.set_meta("life", float(t.get_meta("life")) - delta)
			if float(t.get_meta("life")) <= 0.0:
				t.up = false
		else:
			flip = maxf(0.0, flip - delta * 5.0)
			if flip <= 0.0:
				t.queue_free()
				_targets.remove_at(i)
				continue
		t.set_meta("flip", flip)
		if t.asset:
			t.face.transform.basis = t.face_rest * Basis(Vector3.RIGHT, -PI * 0.5 * (1.0 - flip))
		else:
			t.face.rotation.x = -PI * 0.5 * (1.0 - flip)
	if Game.hud != null:
		Game.hud.info_text = "%s    score %d    hits %d / %d    %d s" % [String(_ch["name"]), _score, _hits, _shown, int(ceil(maxf(_range_t, 0.0)))]
	if _range_t <= 0.0:
		_end_challenge(false)

func _end_challenge(aborted: bool) -> void:
	var c := _ch
	_ch = {}
	for t in _targets:
		if is_instance_valid(t):
			t.queue_free()
	_targets.clear()
	if _range_root != null:
		_range_root.queue_free()
		_range_root = null
	if Game.hud != null:
		Game.hud.info_text = ""
	var p: Player = Game.player
	if _loaner and p != null:
		p.inventory.remove(c["weapon"])
		p.gunner.equip(&"unarmed")
	if aborted:
		Game.notify("Range challenge abandoned", "bad")
		return
	var m: Array = c["medals"]
	var medal := 3 if _score >= int(m[2]) else (2 if _score >= int(m[1]) else (1 if _score >= int(m[0]) else 0))
	var names := ["No medal", "Bronze", "Silver", "Gold"]
	var reward = [0, 100, 250, 500][medal]
	var prev := int(best.get(c["name"], 0))
	best[c["name"]] = maxi(prev, _score)
	if reward > 0:
		Game.add_cash(reward)
	if Game.skills:
		Game.skills.add(&"shooting", 0.02 * float(medal + 1))
	Game.banner(names[medal].to_upper(), "%s  -  %d points (%d / %d hits)%s" % [String(c["name"]), _score, _hits, _shown,
		"  -  new best!" if _score > prev else ""], [Color(0.7, 0.7, 0.75), Color(0.8, 0.5, 0.25), Color(0.85, 0.88, 0.92), Color(1.0, 0.82, 0.25)][medal], 4.0)
	Audio.play_ui(&"ui_success" if medal > 0 else &"ui_fail", -4.0)

# ---------------------------------------------------------------- persistence
func save_state() -> Dictionary:
	return {"completed": completed.keys(), "best": best.duplicate()}

func load_state(d: Dictionary) -> void:
	completed.clear()
	for k in d.get("completed", []):
		completed[String(k)] = true
	best = (d.get("best", {}) as Dictionary).duplicate()
