extends RefCounted
## Checkpoint race / time trial controller of the activities system (spec 47A: street race,
## sea race, off-road trail, time trial). One instance, ticked by activity_system.gd only while a
## race runs. No opponents: the clock races against par times derived from the real route length.
##
## Routes (built once per definition, then cached):
##   road   RoadGraph.find_route over the `via` list (named locations or [x, z]) leg by leg, so
##          the polyline follows the right-hand lanes; checkpoints every `spacing` m + the finish.
##   trail  the RoadGraph segment named `trail_road` (Signal Hill Road), driven bottom -> top.
##   water  explicit sea points, pushed away from the shore until the water is >= 2.5 m deep.
## Visuals while a race runs: the Blender `checkpoint_arch` over the start / finish line (props
## system spawn_prop, freed after the race), additive columns on the `vfx_checkpoint_ring` mesh
## for the next two checkpoints, a minimap blip (group minimap_blip) on the next checkpoint.
## The vehicle: the player's own if its class fits, otherwise `vehicle` is spawned on the grid.

const RING_GLB := "res://gta/generated/models/misc/vfx_checkpoint_ring.glb"
const RING_SHADER := preload("res://gta/code/world/activities/activity_ring.gdshader")

enum Phase { IDLE, STARTING, COUNTDOWN, RUNNING, DONE }

const COUNTDOWN_TIME := 3.0
const OUT_OF_VEHICLE_LIMIT := 10.0
const OFF_COURSE_DIST := 450.0
const MAX_RACE_TIME := 900.0
const MIN_CP_GAP := 45.0
const RING_HEIGHT := 6.5
const COLOR_NEXT := Color(1.0, 0.78, 0.25)
const COLOR_AFTER := Color(0.25, 0.75, 0.72)
const COLOR_FINISH := Color(0.95, 0.45, 0.38)
const WATER_MIN_DEPTH := 2.5

var sys: Node = null
var def: Dictionary = {}
var phase: int = Phase.IDLE
var route: PackedVector3Array = PackedVector3Array()
var cps: Array = []                    ## [{pos: Vector3, dir: Vector3, radius: float}]
var grid: Transform3D = Transform3D.IDENTITY
var length: float = 0.0
var par: Dictionary = {}               ## medal -> seconds
var cp_index: int = 0
var t_race: float = 0.0
var t_phase: float = 0.0
var vehicle: Node3D = null
var spawned_vehicle: bool = false
var top_speed: float = 0.0
var splits: PackedFloat32Array = PackedFloat32Array()
var last_result: Dictionary = {}
var debug_log: Array[String] = []

var _cache: Dictionary = {}            ## def id -> built route data
var _prev_pos: Vector3 = Vector3.ZERO
var _out_t: float = 0.0
var _props: Array[Node3D] = []
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[ShaderMaterial] = []
var _ring_mesh: Mesh = null
var _blip: Node3D = null
var _locked: bool = false
var _countdown_shown: int = -1


func _init(system: Node) -> void:
	sys = system


func is_running() -> bool:
	return phase != Phase.IDLE and phase != Phase.DONE


# =================================================================================================
# routes
# =================================================================================================

## Builds (or returns the cached) route of a race definition:
## {ok, route, cps, grid, length, point (activity point Transform3D), why}.
func get_route(d: Dictionary) -> Dictionary:
	var id := str(d.get("id", ""))
	if _cache.has(id):
		return _cache[id]
	var r := _build_route(d)
	if bool(r.get("ok", false)):
		_cache[id] = r
	return r


func clear_cache() -> void:
	_cache.clear()


func _build_route(d: Dictionary) -> Dictionary:
	var mode := str(d.get("mode", "road"))
	var poly := PackedVector3Array()
	var out := {"ok": false, "why": ""}
	var world := Game.world
	if world == null:
		out["why"] = "no world"
		return out
	if mode == "water":
		var g := Game.get_location(str(d.get("grid", "boat_spawn")))
		poly.append(Vector3(g.origin.x, Game.WATER_LEVEL, g.origin.z))
		for p: Variant in d.get("points", []):
			if p is Array and (p as Array).size() >= 2:
				poly.append(_water_point(Vector3(float(p[0]), Game.WATER_LEVEL, float(p[1]))))
	else:
		var roads: Object = world.get("roads")
		if roads == null or not roads.has_method("find_route"):
			out["why"] = "no road graph"
			return out
		var pts: Array[Vector3] = []
		if mode == "trail":
			pts = _trail_points(roads, d)
		else:
			for v: Variant in d.get("via", []):
				pts.append(_via_pos(v))
		if pts.size() < 2:
			out["why"] = "route needs two points"
			return out
		for i in pts.size() - 1:
			var from: Vector3 = pts[i] if poly.is_empty() else poly[poly.size() - 1]
			var leg: PackedVector3Array = roads.call("find_route", from, pts[i + 1])
			if leg.size() < 2:
				out["why"] = "no road route for leg %d" % i
				return out
			for k in leg.size():
				if not poly.is_empty() and poly[poly.size() - 1].distance_to(leg[k]) < 0.5:
					continue
				poly.append(leg[k])
		for k in poly.size():
			var q := poly[k]
			poly[k] = Vector3(q.x, Game.ground_height(q.x, q.z), q.z)
	if poly.size() < 2:
		out["why"] = "empty route"
		return out
	# length + checkpoints
	var total := 0.0
	for k in range(1, poly.size()):
		total += poly[k - 1].distance_to(poly[k])
	var radius := float(d.get("radius", 9.0))
	var list: Array = []
	if mode == "water":
		for k in range(1, poly.size()):
			var dir := (poly[k] - poly[k - 1])
			dir.y = 0.0
			list.append({"pos": poly[k], "dir": dir.normalized(), "radius": radius})
	else:
		var spacing := maxf(float(d.get("spacing", 110.0)), MIN_CP_GAP)
		var acc := 0.0
		var next_at := spacing
		for k in range(1, poly.size()):
			var a := poly[k - 1]
			var b := poly[k]
			var seg := a.distance_to(b)
			while seg > 0.001 and acc + seg >= next_at and next_at <= total - MIN_CP_GAP:
				var f := (next_at - acc) / seg
				var p := a.lerp(b, f)
				var dir := (b - a)
				dir.y = 0.0
				list.append({"pos": Vector3(p.x, Game.ground_height(p.x, p.z), p.z), "dir": dir.normalized(), "radius": radius})
				next_at += spacing
			acc += seg
		var last := poly[poly.size() - 1]
		var ld := last - poly[poly.size() - 2]
		ld.y = 0.0
		list.append({"pos": last, "dir": ld.normalized(), "radius": radius})
	# grid: route start facing along the first 10 m (water: the named grid location)
	var g0 := poly[0]
	var ahead := _point_along(poly, 10.0)
	var fwd := ahead - g0
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var basis := Basis.looking_at(fwd, Vector3.UP)
	var gxf := Transform3D(basis, g0)
	if mode == "water":
		var gl := Game.get_location(str(d.get("grid", "boat_spawn")))
		gxf = Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(gl.origin.x, Game.WATER_LEVEL, gl.origin.z))
	out["ok"] = true
	out["route"] = poly
	out["cps"] = list
	out["grid"] = gxf
	out["length"] = total
	out["point"] = _activity_point(d, gxf)
	return out


func _via_pos(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 2:
		var x := float(v[0])
		var z := float(v[1])
		return Vector3(x, Game.ground_height(x, z), z)
	return Game.get_location(str(v)).origin


## Bottom -> top points of a named road segment (trail races).
func _trail_points(roads: Object, d: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var road_name := str(d.get("trail_road", ""))
	var segs: Variant = roads.get("segments")
	if not (segs is Array):
		return out
	var line := PackedVector3Array()
	for s: Variant in segs:
		if s is Dictionary and str((s as Dictionary).get("name", "")) == road_name:
			line = (s as Dictionary).get("points", PackedVector3Array())
			break
	if line.size() < 2:
		return out
	var a := line[0]
	var b := line[line.size() - 1]
	if Game.ground_height(a.x, a.z) > Game.ground_height(b.x, b.z):
		line.reverse()
	var skip := float(d.get("trail_skip", 20.0))
	var stop := float(d.get("trail_stop", 10.0))
	var total := 0.0
	for k in range(1, line.size()):
		total += line[k - 1].distance_to(line[k])
	out.append(_point_along(line, skip))
	out.append(_point_along(line, total * 0.5))
	out.append(_point_along(line, maxf(total - stop, skip + 1.0)))
	if bool(d.get("trail_return", false)):
		# back down through the U-turn at the dead end (the router takes the downhill lane)
		out.append(_point_along(line, total * 0.5))
		out.append(_point_along(line, skip))
	return out



func _point_along(poly: PackedVector3Array, dist: float) -> Vector3:
	var acc := 0.0
	for k in range(1, poly.size()):
		var seg := poly[k - 1].distance_to(poly[k])
		if acc + seg >= dist and seg > 0.0001:
			return poly[k - 1].lerp(poly[k], (dist - acc) / seg)
		acc += seg
	return poly[poly.size() - 1]


## Pushes a sea point away from the island until the water is deep enough.
func _water_point(p: Vector3) -> Vector3:
	var w := Game.world
	if w == null or not w.has_method("get_water_depth"):
		return p
	var dir := Vector3(p.x, 0.0, p.z)
	dir = dir.normalized() if dir.length() > 1.0 else Vector3.BACK
	var q := p
	for i in 30:
		if float(w.call("get_water_depth", q.x, q.z)) >= WATER_MIN_DEPTH:
			return Vector3(q.x, Game.WATER_LEVEL, q.z)
		q += dir * 6.0
	return Vector3(q.x, Game.WATER_LEVEL, q.z)


## Where the activity point (Interactable + flag) of a race stands.
func _activity_point(d: Dictionary, gxf: Transform3D) -> Transform3D:
	var pt: Variant = d.get("point", null)
	var mode := str(d.get("mode", "road"))
	if mode == "water":
		var loc := Game.get_location(str(pt if pt != null else "marina_dock"))
		return loc
	var pos := gxf.origin
	var right := gxf.basis.x
	# stand on the kerb / roadside to the right of the start line
	var off := float(d.get("point_offset", 6.0))
	var roads: Object = Game.world.get("roads") if Game.world != null else null
	if roads != null and roads.has_method("get_segment_at"):
		var sid := int(roads.call("get_segment_at", pos))
		var segs: Variant = roads.get("segments")
		if sid >= 0 and segs is Array and sid < (segs as Array).size():
			var seg: Dictionary = (segs as Array)[sid]
			var hw := float(seg.get("hw", 4.0))
			var line: PackedVector3Array = seg.get("points", PackedVector3Array())
			var c := _closest_on_polyline(line, pos)
			var lat := pos - c
			lat.y = 0.0
			var side := 1.0 if lat.dot(right) >= 0.0 else -1.0
			var kind := str(seg.get("kind", "street"))
			var extra := 1.6 if (kind == "arterial" or kind == "street") else 2.6
			var p2 := c + right * side * (hw + extra)
			return Transform3D(gxf.basis, Vector3(p2.x, Game.ground_height(p2.x, p2.z), p2.z))
	var p := pos + right * off
	return Transform3D(gxf.basis, Vector3(p.x, Game.ground_height(p.x, p.z), p.z))


func _closest_on_polyline(line: PackedVector3Array, p: Vector3) -> Vector3:
	var best := p
	var bd := INF
	for k in range(1, line.size()):
		var a := line[k - 1]
		var b := line[k]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + ab * t
		var dd := q.distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = q
	return best


# =================================================================================================
# session
# =================================================================================================

## Coroutine. Returns "" when the race is under way, otherwise the refusal reason.
func begin(d: Dictionary) -> String:
	var r := get_route(d)
	if not bool(r.get("ok", false)):
		return "route unavailable (%s)" % str(r.get("why", ""))
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.get("is_dead") == true:
		return "no player"
	var wanted := sys.get_node_or_null("/root/Wanted")
	if wanted != null and int(wanted.get("level")) > 0:
		return "Lose the police first"
	def = d
	route = r["route"]
	cps = r["cps"]
	grid = r["grid"]
	length = float(r["length"])
	par.clear()
	var ps: Dictionary = d.get("par_speed", {})
	for m: String in ["gold", "silver", "bronze"]:
		par[m] = length / maxf(float(ps.get(m, 10.0)), 1.0)
	phase = Phase.STARTING
	# vehicle: keep a suitable one, otherwise spawn the race vehicle on the grid
	var classes: Array = d.get("classes", ["car"])
	var cur := Game.get_player_vehicle()
	vehicle = null
	spawned_vehicle = false
	if cur != null and is_instance_valid(cur) and cur.get("destroyed") != true and classes.has(str(cur.get("vehicle_class"))):
		vehicle = cur
	await _fade(true)
	if phase != Phase.STARTING:
		return "cancelled"
	var gxf := _grid_spawn_xform()
	if vehicle == null:
		if cur != null and p.has_method("teleport"):
			p.call("teleport", gxf.origin + gxf.basis.x * 3.0 + Vector3.UP * 0.2, 0.0)
		vehicle = Game.spawn_vehicle(str(d.get("vehicle", "sports")), gxf, {"owner_tag": "player", "engine_on": true})
		if vehicle == null:
			phase = Phase.IDLE
			_fade(false)
			return "could not spawn the race vehicle"
		spawned_vehicle = true
	elif vehicle.has_method("teleport"):
		vehicle.call("teleport", gxf)
	if vehicle.has_method("repair") and vehicle.get("health") != null and float(vehicle.get("health")) < float(vehicle.get("max_health")) * 0.35:
		vehicle.call("repair")
	if Game.get_player_vehicle() != vehicle and p.has_method("enter_vehicle"):
		p.call("enter_vehicle", vehicle, 0, true)
	vehicle.set("owner_tag", "player")
	if vehicle.has_method("start_engine"):
		vehicle.call("start_engine")
	var cam: Node = Game.camera_rig
	if cam != null and cam.has_method("snap_to"):
		var f := -gxf.basis.z
		cam.call("snap_to", atan2(-f.x, -f.z))
	_spawn_dressing()
	_ensure_rings()
	cp_index = 0
	t_race = 0.0
	t_phase = 0.0
	top_speed = 0.0
	splits.clear()
	_out_t = 0.0
	_prev_pos = vehicle.global_position
	_update_rings()
	phase = Phase.COUNTDOWN
	_countdown_shown = -1
	if not _locked:
		Game.lock_input()
		_locked = true
	_fade(false)
	_log("race %s started: %.0f m, %d checkpoints, par gold %.1f s, vehicle %s%s" % [str(d.get("id", "")), length,
			cps.size(), float(par["gold"]), str(vehicle.get("spec_id")), " (spawned)" if spawned_vehicle else ""])
	return ""


## Grid slot for the race vehicle: the route start, moved back along the lane (7 m steps, up to
## 4 times) while another vehicle (traffic, parked) stands on it.
func _grid_spawn_xform() -> Transform3D:
	var o := grid.origin
	var back := grid.basis.z.normalized()
	var water := str(def.get("mode", "road")) == "water"
	for i in 5:
		var q := o + back * (7.0 * i)
		if not _vehicle_near(q, 3.6):
			o = q
			break
	if water:
		return Transform3D(grid.basis, Vector3(o.x, Game.WATER_LEVEL, o.z))
	return Transform3D(grid.basis, Vector3(o.x, Game.ground_height(o.x, o.z) + 0.05, o.z))


func _vehicle_near(p: Vector3, r: float) -> bool:
	var own := Game.get_player_vehicle()
	for v: Node in sys.get_tree().get_nodes_in_group("vehicle"):
		if v == own or not (v is Node3D) or not is_instance_valid(v):
			continue
		var d := (v as Node3D).global_position - p
		d.y = 0.0
		if d.length() < r:
			return true
	return false



func _fade(out: bool) -> void:
	if TestHarness.is_headless():
		return
	if out:
		await UI.fade_out(0.35)
	else:
		UI.fade_in(0.4)


func tick(delta: float) -> void:
	if phase != Phase.COUNTDOWN and phase != Phase.RUNNING:
		return
	t_phase += delta
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.get("is_dead") == true:
		sys.call("abort_activity", "down")
		return
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.get("destroyed") == true:
		sys.call("abort_activity", "vehicle wrecked")
		return
	if phase == Phase.COUNTDOWN:
		var left := int(ceil(COUNTDOWN_TIME - t_phase))
		if left != _countdown_shown and left > 0:
			_countdown_shown = left
			UI.banner(str(left), str(def.get("display_name", "")), Color(0.97, 0.79, 0.28), 0.85)
			Audio.play("ui_tab", -3.0, 1.0, "UI")
		if t_phase >= COUNTDOWN_TIME:
			phase = Phase.RUNNING
			t_phase = 0.0
			_unlock()
			UI.banner("GO", "", Color(0.35, 0.84, 0.55), 0.9)
			Audio.play("activity_start", -2.0, 1.0, "UI")
			_prev_pos = vehicle.global_position
		return
	# running
	t_race += delta
	var sp := float(vehicle.get("speed_kmh")) if vehicle.get("speed_kmh") != null else 0.0
	top_speed = maxf(top_speed, sp)
	if Game.get_player_vehicle() != vehicle:
		_out_t += delta
		if _out_t > OUT_OF_VEHICLE_LIMIT:
			sys.call("abort_activity", "left the vehicle")
			return
	else:
		_out_t = 0.0
	var pos := vehicle.global_position
	if cp_index < cps.size():
		var cp: Dictionary = cps[cp_index]
		var c: Vector3 = cp["pos"]
		var r := float(cp["radius"])
		if _seg_dist2_xz(_prev_pos, pos, c) <= r * r and absf(pos.y - c.y) < 12.0:
			_pass_checkpoint()
		elif Vector2(pos.x - c.x, pos.z - c.z).length() > OFF_COURSE_DIST:
			sys.call("abort_activity", "off course")
			return
	_prev_pos = pos
	if t_race > MAX_RACE_TIME:
		sys.call("abort_activity", "time limit")


func _seg_dist2_xz(a: Vector3, b: Vector3, c: Vector3) -> float:
	var a2 := Vector2(a.x, a.z)
	var ab := Vector2(b.x, b.z) - a2
	var c2 := Vector2(c.x, c.z)
	var t := 0.0
	if ab.length_squared() > 0.000001:
		t = clampf((c2 - a2).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (a2 + ab * t).distance_squared_to(c2)


func _pass_checkpoint() -> void:
	splits.append(t_race)
	cp_index += 1
	if cp_index >= cps.size():
		Audio.play("activity_win", -2.0, 1.0, "UI")
		_complete()
		return
	Audio.play("ui_click", -2.0, 1.35, "UI")
	_update_rings()


## Debug / tests: positions of the remaining checkpoints.
func get_checkpoint(i: int) -> Dictionary:
	if i < 0 or i >= cps.size():
		return {}
	return cps[i]


func _complete() -> void:
	phase = Phase.DONE
	_unlock()
	var medal := "none"
	for m: String in ["gold", "silver", "bronze"]:
		if t_race <= float(par.get(m, 0.0)):
			medal = m
			break
	last_result = {
		"time": t_race, "medal": medal, "length": length, "checkpoints": cps.size(), "top_speed_kmh": top_speed,
		"par": par.duplicate(), "vehicle": str(vehicle.get("spec_id")) if is_instance_valid(vehicle) else "",
		"splits": splits.duplicate(),
	}
	_log("race done: %.2f s, medal %s, top %.0f km/h" % [t_race, medal, top_speed])
	_cleanup()
	phase = Phase.IDLE
	sys.call("_on_race_complete", def, last_result)


func abort(_reason: String) -> void:
	if phase == Phase.IDLE:
		return
	phase = Phase.IDLE
	_unlock()
	_cleanup()


func _unlock() -> void:
	if _locked:
		_locked = false
		Game.unlock_input()


# =================================================================================================
# visuals
# =================================================================================================

func _spawn_dressing() -> void:
	_free_props()
	if not bool(def.get("arch", false)):
		return
	var props: Node = Game.get_system("props")
	if props == null or not props.has_method("spawn_prop"):
		return
	var xf := _arch_xform()
	var n: Variant = props.call("spawn_prop", "checkpoint_arch", xf)
	if n is Node3D:
		(n as Node3D).name = "RaceArch"
		_props.append(n as Node3D)


## The arch spans the carriageway of the grid lane (feet on the kerb / centre line) on wide
## roads, or is centred on narrow roads / tracks.
func _arch_xform() -> Transform3D:
	var o := grid.origin
	var basis := grid.basis
	var right := basis.x
	var roads: Object = Game.world.get("roads") if Game.world != null else null
	var centre := o
	if roads != null and roads.has_method("get_segment_at"):
		var sid := int(roads.call("get_segment_at", o))
		var segs: Variant = roads.get("segments")
		if sid >= 0 and segs is Array and sid < (segs as Array).size():
			var seg: Dictionary = (segs as Array)[sid]
			var hw := float(seg.get("hw", 4.0))
			var c := _closest_on_polyline(seg.get("points", PackedVector3Array()), o)
			if hw * 2.0 > 9.0:
				var lat := o - c
				lat.y = 0.0
				var side := 1.0 if lat.dot(right) >= 0.0 else -1.0
				centre = c + right * side * (hw * 0.5)
			else:
				centre = c
	# 4 m past the grid so the car starts behind the line
	centre += -basis.z * 4.0
	return Transform3D(basis, Vector3(centre.x, Game.ground_height(centre.x, centre.z), centre.z))


func _ensure_rings() -> void:
	for r in _rings:
		if not is_instance_valid(r):
			_rings.clear()
			_ring_mats.clear()
			break
	if not _rings.is_empty():
		return
	if _ring_mesh == null and ResourceLoader.exists(RING_GLB):
		var ps := load(RING_GLB) as PackedScene
		if ps != null:
			var inst := ps.instantiate()
			var mi := _first_mesh(inst)
			if mi != null:
				_ring_mesh = mi.mesh
			inst.free()
	if _ring_mesh == null:
		push_warning("Activities: vfx_checkpoint_ring mesh missing - checkpoints have no column")
		return
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.name = "CheckpointRing%d" % i
		mi.mesh = _ring_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = RING_SHADER
		mi.material_override = m
		mi.visible = false
		sys.add_child(mi)
		_rings.append(mi)
		_ring_mats.append(m)
	if _blip == null or not is_instance_valid(_blip):
		_blip = Node3D.new()
		_blip.name = "CheckpointBlip"
		_blip.set_meta(&"blip_icon", &"flag")
		_blip.set_meta(&"blip_color", COLOR_NEXT)
		_blip.set_meta(&"blip_clamp", true)
		sys.add_child(_blip)


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n as MeshInstance3D
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


func _update_rings() -> void:
	for i in _rings.size():
		var k := cp_index + i
		var mi := _rings[i]
		if k >= cps.size():
			mi.visible = false
			continue
		var cp: Dictionary = cps[k]
		var r := float(cp["radius"]) * 0.85
		var finish := k == cps.size() - 1
		var col := COLOR_FINISH if finish else (COLOR_NEXT if i == 0 else COLOR_AFTER)
		mi.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(r, RING_HEIGHT, r)), cp["pos"] as Vector3 + Vector3.DOWN * 0.3)
		_ring_mats[i].set_shader_parameter("color", col)
		_ring_mats[i].set_shader_parameter("intensity", 1.0 if i == 0 else 0.45)
		mi.visible = true
	if _blip != null and is_instance_valid(_blip):
		if cp_index < cps.size():
			_blip.global_position = cps[cp_index]["pos"]
			_blip.set_meta(&"blip_color", COLOR_FINISH if cp_index == cps.size() - 1 else COLOR_NEXT)
			if not _blip.is_in_group("minimap_blip"):
				_blip.add_to_group("minimap_blip")
		elif _blip.is_in_group("minimap_blip"):
			_blip.remove_from_group("minimap_blip")


func _cleanup() -> void:
	_free_props()
	for r in _rings:
		if is_instance_valid(r):
			r.visible = false
	if _blip != null and is_instance_valid(_blip) and _blip.is_in_group("minimap_blip"):
		_blip.remove_from_group("minimap_blip")


func _free_props() -> void:
	for n in _props:
		if is_instance_valid(n):
			n.queue_free()
	_props.clear()


## HUD keys (activity_system.get_hud_info): checkpoint = checkpoints passed, checkpoints / total,
## lap / laps (1), par_gold, distance_to_checkpoint. No score key (the UI card would show "SCORE").
func fill_hud(info: Dictionary) -> void:
	info["title"] = str(def.get("display_name", "Race"))
	info["subtitle"] = str(def.get("subtitle", ""))
	info["timer"] = t_race
	info["time"] = t_race
	info["time_mode"] = "up"
	info["checkpoint"] = cp_index
	info["total"] = cps.size()
	info["checkpoints"] = cps.size()
	info["lap"] = 1
	info["laps"] = 1
	info["par_gold"] = float(par.get("gold", 0.0))
	info["color"] = Color(0.969, 0.788, 0.282)
	var hint := ""
	if phase == Phase.STARTING:
		hint = "Get ready"
	elif phase == Phase.COUNTDOWN:
		hint = "Starting in %d" % maxi(int(ceil(COUNTDOWN_TIME - t_phase)), 1)
	elif _out_t > 0.0:
		hint = "Back in the vehicle! %d" % maxi(int(ceil(OUT_OF_VEHICLE_LIMIT - _out_t)), 0)
	elif cp_index == cps.size() - 1:
		hint = "Finish line  -  gold %s" % _fmt_time(float(par.get("gold", 0.0)))
	else:
		hint = "Next checkpoint %d / %d  -  gold %s" % [cp_index + 1, cps.size(), _fmt_time(float(par.get("gold", 0.0)))]

	info["hint"] = hint
	info["countdown"] = maxf(COUNTDOWN_TIME - t_phase, 0.0) if phase == Phase.COUNTDOWN else 0.0
	info["phase"] = ["idle", "starting", "countdown", "running", "done"][phase]
	if cp_index < cps.size() and vehicle != null and is_instance_valid(vehicle):
		var c: Vector3 = cps[cp_index]["pos"]
		info["distance_to_checkpoint"] = Vector2(vehicle.global_position.x - c.x, vehicle.global_position.z - c.z).length()


static func _fmt_time(t: float) -> String:
	var m := int(t / 60.0)
	return "%d:%04.1f" % [m, t - m * 60.0]


func _log(s: String) -> void:
	debug_log.append(s)
	if debug_log.size() > 40:
		debug_log.remove_at(0)
	print("[Activities] race: ", s)
