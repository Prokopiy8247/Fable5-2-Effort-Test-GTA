extends RefCounted
## Shooting range controller of the activities system ("Ironsight Challenge" at the
## `shooting_range` landmark, spec 47A). One instance, owned by activity_system.gd; it is ticked
## from the system's _physics_process only while a course runs (no per-target scripts).
##
## Course = rounds of timed target "volleys" across the five lanes:
##   turner  target_round easels that turn face-on for `window` s (score by ring 10/8/6/4/2)
##   popup   target_silhouette steel plates that flip up on their hinge ('Target' child, local X)
##           and are knocked flat by a hit (10 + up to 5 speed bonus + distance bonus + centre bonus)
##   mover   silhouettes that slide across the yard on a track while up (15 + speed + centre)
## Score = target points + accuracy bonus (hits / shots * 40). Medal = score / max score.
## The course weapon and its ammo are handed out for the duration (inventory snapshot restored
## afterwards). Gunfire at the range is lawful: Wanted is switched off for the session (refused
## while wanted) - see docs/ACTIVITIES.md.
##
## Geometry comes from the city landmark (W2.4): Lane_1..5 markers (firing positions, -Z =
## down-range) and the building transform (manifest coordinates: down-range = local +X, lanes
## along local Z, yard floor y 0.03). Targets are pooled GLB instances created on first use.

const TargetBody := preload("res://gta/code/world/activities/activity_target_body.gd")
const SILHOUETTE_GLB := "res://gta/generated/models/misc/target_silhouette.glb"
const ROUND_GLB := "res://gta/generated/models/misc/target_round.glb"

enum Phase { IDLE, STARTING, INTRO, ROUND_INTRO, RUNNING, ROUND_END, DONE }
enum TS { DOWN, RISING, UP, FALLING }

const YARD_Y := 0.03
const INTRO_TIME := 3.0
const ROUND_INTRO_TIME := 2.2
const ROUND_END_TIME := 1.2
const RISE_TIME := 0.18
const FALL_TIME := 0.28
const KNOCK_TIME := 0.12
const TURN_TIME := 0.22
const MOVER_Z := 4.3                     ## movers travel between -MOVER_Z and +MOVER_Z (yard half width 5.4)
const RING_RADII: Array[float] = [0.09, 0.18, 0.27, 0.36, 0.45]
const RING_POINTS: Array[int] = [10, 8, 6, 4, 2]
const CENTRE_RADIUS := 0.16
const CENTRE_BONUS := 3
const ACCURACY_BONUS := 40
const LANE_LEAVE_DIST := 5.0
const FIRING_LINE_X := -8.4              ## building-local x the shooter must stay behind
const LABEL_POOL := 5
const LABEL_TIME := 0.9
const ENFORCE_INTERVAL := 0.25


class Target:
	var key: String = ""
	var kind: String = ""             ## "popup" | "turner" | "mover"
	var node: Node3D = null           ## GLB instance (placed in the range frame)
	var pivot: Node3D = null          ## 'Target' child (hinge / ring face)
	var rest: Transform3D = Transform3D.IDENTITY
	var body: StaticBody3D = null
	var shape: CollisionShape3D = null
	var lane: int = 0
	var row: float = 0.0
	var lane_z: float = 0.0
	var state: int = 0
	var anim: float = 0.0             ## 0 down / edge-on .. 1 up / face-on
	var t_left: float = 0.0
	var window: float = 1.0
	var open: bool = false            ## an exposure is running (not hit / expired yet)
	var hit_center: Vector3 = Vector3.ZERO    ## pivot space
	var z_from: float = 0.0
	var z_to: float = 0.0
	var row_bonus: int = 0
	var knocked: bool = false         ## falling because it was hit (fast knock-down)


var sys: Node = null
var def: Dictionary = {}
var phase: int = Phase.IDLE
var root: Node3D = null
var frame: Transform3D = Transform3D.IDENTITY
var frame_inv: Transform3D = Transform3D.IDENTITY
var lanes: Array[Transform3D] = []
var targets: Array = []                ## Array[Target]
var by_key: Dictionary = {}            ## key -> index into targets
var round_index: int = -1
var events: Array = []                 ## [{t, idx: PackedInt32Array, window}]
var event_cursor: int = 0
var t_phase: float = 0.0
var t_round: float = 0.0
var t_total: float = 0.0
var shots: int = 0
var hits: int = 0
var score: int = 0
var max_score: int = 0
var exposures: int = 0
var exposures_hit: int = 0
var lane_xf: Transform3D = Transform3D.IDENTITY
var weapon_id: String = ""
var last_result: Dictionary = {}
var debug_log: Array[String] = []

var _labels: Array[Label3D] = []
var _label_t: PackedFloat32Array = PackedFloat32Array()
var _label_next: int = 0
var _snapshot: Dictionary = {}
var _have_snapshot: bool = false
var _wanted_prev: bool = true
var _wanted_switched: bool = false
var _enforce_t: float = 0.0
var _countdown_shown: int = -1
var _round_names: PackedStringArray = PackedStringArray()


func _init(system: Node) -> void:
	sys = system


func is_running() -> bool:
	return phase != Phase.IDLE and phase != Phase.DONE


# =================================================================================================
# geometry
# =================================================================================================

## Reads the landmark transform and the lane markers. Returns "" when usable, else the reason.
func resolve_geometry(d: Dictionary) -> String:
	var city: Node = Game.get_system("city")
	var lm := str(d.get("landmark", "shooting_range"))
	if city == null or not city.has_method("has_landmark") or not bool(city.call("has_landmark", lm)):
		return "the range building is missing"
	frame = city.call("get_landmark_transform", lm)
	frame = Transform3D(frame.basis.orthonormalized(), frame.origin)
	frame_inv = frame.affine_inverse()
	lanes.clear()
	for i in 5:
		var mk := "Lane_%d" % (i + 1)
		if not bool(city.call("has_landmark_marker", lm, mk)):
			return "lane marker %s missing" % mk
		lanes.append(city.call("get_landmark_marker", lm, mk))
	return ""


## World transform of the start point of a course definition.
func get_use_transform(d: Dictionary) -> Transform3D:
	var city: Node = Game.get_system("city")
	var lm := str(d.get("landmark", "shooting_range"))
	var ul: Variant = d.get("use_local", [])
	if ul is Array and (ul as Array).size() == 3 and city != null and city.has_method("get_landmark_transform"):
		var xf: Transform3D = city.call("get_landmark_transform", lm)
		var p := xf * Vector3(float(ul[0]), float(ul[1]), float(ul[2]))
		return Transform3D(xf.basis.orthonormalized(), p)
	if city != null and city.has_method("get_landmark_marker"):
		return city.call("get_landmark_marker", lm, str(d.get("use_marker", "Use_Start")))
	return Game.get_location(lm)


func lane_local_z(lane_i: int) -> float:
	return (frame_inv * lanes[clampi(lane_i, 0, lanes.size() - 1)].origin).z


func local_to_world(p: Vector3) -> Vector3:
	return frame * p


# =================================================================================================
# targets (pooled GLB instances)
# =================================================================================================

func _ensure_root() -> void:
	if root != null and is_instance_valid(root):
		return
	root = Node3D.new()
	root.name = "RangeTargets"
	sys.add_child(root)
	root.global_transform = Transform3D.IDENTITY
	for i in LABEL_POOL:
		var l := Label3D.new()
		l.name = "ScorePop%d" % i
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.font_size = 46
		l.outline_size = 14
		l.modulate = Color(1.0, 0.86, 0.32)
		l.outline_modulate = Color(0.05, 0.08, 0.14, 0.9)
		l.visible = false
		root.add_child(l)
		_labels.append(l)
	_label_t.resize(LABEL_POOL)


func _target_index(kind: String, lane: int, row: float) -> int:
	var key := "%s:%d:%.2f" % [kind, lane, row]
	if by_key.has(key):
		return int(by_key[key])
	var glb := ROUND_GLB if kind == "turner" else SILHOUETTE_GLB
	if not ResourceLoader.exists(glb):
		push_warning("Activities: range target model missing (%s)" % glb)
		return -1
	var ps := load(glb) as PackedScene
	if ps == null:
		return -1
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return -1
	var t := Target.new()
	t.key = key
	t.kind = kind
	t.lane = lane
	t.row = row
	t.lane_z = 0.0 if kind == "mover" else lane_local_z(lane)
	inst.name = "Target_%s_%d_%d" % [kind, lane, int(round(row * 10.0))]
	root.add_child(inst)
	t.node = inst
	_place_node(t, t.lane_z)
	var pivot := inst.find_child("Target", true, false) as Node3D
	if pivot == null:
		push_warning("Activities: %s has no 'Target' child" % glb)
		pivot = inst
	t.pivot = pivot
	t.rest = pivot.transform
	_set_shadow(inst)
	# hit centre in pivot space (pivot at rest = standing / face-on)
	if kind == "turner":
		t.hit_center = Vector3.ZERO
	else:
		var hc := inst.find_child("Hit_Center", true, false) as Node3D
		t.hit_center = pivot.global_transform.affine_inverse() * hc.global_position if hc != null else Vector3(0, 0.97, 0)
	# collider on the face / plate (moves with the pivot)
	var body: StaticBody3D = TargetBody.new()
	body.name = "Hit"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.set_meta(&"surface", "wood" if kind == "turner" else "metal")
	body.set("index", targets.size())
	body.set("on_hit", Callable(self, "_on_target_hit"))
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	if kind == "turner":
		var cyl := CylinderShape3D.new()
		cyl.radius = RING_RADII[RING_RADII.size() - 1]
		cyl.height = 0.06
		cs.shape = cyl
		cs.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	else:
		var bb := _pivot_aabb(pivot)
		if bb.size.length() < 0.05:
			bb = AABB(Vector3(-0.35, 0.3, -0.05), Vector3(0.7, 1.3, 0.1))
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(bb.size.x, 0.1), maxf(bb.size.y, 0.1), maxf(bb.size.z, 0.06))
		cs.shape = box
		cs.position = bb.get_center()
	cs.disabled = true
	body.add_child(cs)
	pivot.add_child(body)
	t.body = body
	t.shape = cs
	targets.append(t)
	by_key[key] = targets.size() - 1
	_pose(t)
	inst.visible = false
	return targets.size() - 1


func _place_node(t: Target, z: float) -> void:
	var lp := Vector3(t.row, YARD_Y, z)
	t.node.global_transform = frame * Transform3D(Basis(Vector3.UP, PI * 0.5), lp)


func _set_shadow(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		(n as GeometryInstance3D).visibility_range_end = 160.0
	for c in n.get_children():
		_set_shadow(c)


func _pivot_aabb(pivot: Node3D) -> AABB:
	var inv := pivot.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	var stack: Array[Node] = [pivot]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var bb := (inv * mi.global_transform) * mi.mesh.get_aabb()
			out = bb if first else out.merge(bb)
			first = false
		for c in n.get_children():
			stack.append(c)
	return out


## Applies t.anim to the pivot (hinge flip for plates, quarter turn for ring faces).
func _pose(t: Target) -> void:
	if t.pivot == null:
		return
	var a := (1.0 - clampf(t.anim, 0.0, 1.0)) * PI * 0.5
	if t.kind == "turner":
		t.pivot.transform = Transform3D(Basis(Vector3.UP, a) * t.rest.basis, t.rest.origin)
	else:
		t.pivot.transform = Transform3D(t.rest.basis * Basis(Vector3.RIGHT, a), t.rest.origin)
	var live := t.state == TS.UP or (t.state == TS.RISING and t.anim > 0.55)
	if t.shape != null and t.shape.disabled == live:
		t.shape.disabled = not live


# =================================================================================================
# session
# =================================================================================================

## Starts a course (coroutine: fades). Returns "" on success, else the refusal reason.
func begin(d: Dictionary) -> String:
	var why := resolve_geometry(d)
	if why != "":
		return why
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.get("is_dead") == true:
		return "no player"
	if Game.get_player_vehicle() != null:
		return "on foot only"
	var wanted := sys.get_node_or_null("/root/Wanted")
	if wanted != null and int(wanted.get("level")) > 0:
		return "Not while the police are after you"
	var inv: Node = p.get("inventory") as Node
	weapon_id = str(d.get("weapon", "pistol"))
	if inv == null or not inv.has_method("give_weapon"):
		return "no weapon inventory"
	def = d
	phase = Phase.STARTING
	_ensure_root()
	# build / reuse every target this course needs, all down
	_round_names.clear()
	for r: Dictionary in d.get("rounds", []):
		_round_names.append(str(r.get("name", "")))
		var kind := str(r.get("type", "popup"))
		for row: Variant in r.get("rows", []):
			if kind == "mover":
				_target_index("mover", 0, float(row))
			else:
				for lane in 5:
					_target_index(kind, lane, float(row))
	for t: Target in targets:
		_reset_target(t)
		t.node.visible = false
	# ammo + weapon for the duration (snapshot restored at the end)
	_snapshot = inv.call("get_save_data") if inv.has_method("get_save_data") else {}
	_have_snapshot = inv.has_method("load_save_data") and not _snapshot.is_empty()
	inv.call("give_weapon", weapon_id, int(d.get("ammo", 150)))
	inv.call("equip", weapon_id)
	if wanted != null:
		_wanted_prev = bool(wanted.get("enabled"))
		wanted.set("enabled", false)
		_wanted_switched = true
	# move to the firing position
	lane_xf = lanes[clampi(int(d.get("lane", 3)) - 1, 0, lanes.size() - 1)]
	await _fade(true)
	if phase != Phase.STARTING:
		return "cancelled"
	var f := -lane_xf.basis.z
	if p.has_method("teleport"):
		p.call("teleport", lane_xf.origin + Vector3.UP * 0.05, atan2(-f.x, -f.z))
	if p.has_method("set_aiming"):
		p.call("set_aiming", false)
	shots = 0
	hits = 0
	score = 0
	max_score = 0
	exposures = 0
	exposures_hit = 0
	t_total = 0.0
	round_index = -1
	phase = Phase.INTRO
	t_phase = 0.0
	_countdown_shown = -1
	_show_round_targets(0)
	_fade(false)
	Audio.play("activity_start", -4.0, 1.0, "UI")
	UI.banner(str(d.get("display_name", "Shooting Range")).to_upper(), "%s  -  %d rounds" % [str(d.get("subtitle", "")), _round_names.size()],
			Color(0.97, 0.79, 0.28), 2.6)
	_log("course %s started at lane %s" % [str(d.get("id", "")), str(lane_xf.origin)])
	return ""


func _fade(out: bool) -> void:
	if TestHarness.is_headless():
		return
	if out:
		await UI.fade_out(0.35)
	else:
		UI.fade_in(0.35)


func _reset_target(t: Target) -> void:
	t.state = TS.DOWN
	t.anim = 0.0
	t.open = false
	t.knocked = false
	t.t_left = 0.0
	if t.kind == "mover":
		_place_node(t, -MOVER_Z - 0.6)
	_pose(t)


## Which targets are visible during round r (turner easels only in their round, movers only in
## theirs, plates lie flat in the yard during the whole course).
func _show_round_targets(r: int) -> void:
	var rounds: Array = def.get("rounds", [])
	var cur := ""
	if r >= 0 and r < rounds.size():
		cur = str((rounds[r] as Dictionary).get("type", ""))
	var used := {}
	for rr: Dictionary in rounds:
		used[str(rr.get("type", ""))] = true
	for t: Target in targets:
		var show := false
		if t.kind == "popup":
			show = used.has("popup") and _key_in_course(t)
		elif t.kind == "turner":
			show = cur == "turner" and _key_in_course(t)
		elif t.kind == "mover":
			show = cur == "mover" and _key_in_course(t)
		t.node.visible = show
		if not show:
			_reset_target(t)


func _key_in_course(t: Target) -> bool:
	for r: Dictionary in def.get("rounds", []):
		if str(r.get("type", "")) != t.kind:
			continue
		for row: Variant in r.get("rows", []):
			if absf(float(row) - t.row) < 0.01:
				return true
	return false


func tick(delta: float) -> void:
	if phase == Phase.IDLE or phase == Phase.DONE or phase == Phase.STARTING:
		_tick_labels(delta)
		return
	t_phase += delta
	_tick_labels(delta)
	if not _check_player():
		return
	_enforce_t -= delta
	if _enforce_t <= 0.0:
		_enforce_t = ENFORCE_INTERVAL
		_enforce_weapon()
	match phase:
		Phase.INTRO:
			var left := int(ceil(INTRO_TIME - t_phase))
			if left != _countdown_shown and left > 0 and t_phase > 0.4:
				_countdown_shown = left
				Audio.play("ui_tab", -6.0, 1.0, "UI")
			if t_phase >= INTRO_TIME:
				_next_round()
		Phase.ROUND_INTRO:
			if t_phase >= ROUND_INTRO_TIME:
				phase = Phase.RUNNING
				t_phase = 0.0
				t_round = 0.0
				Audio.play("activity_start", -8.0, 1.25, "UI")
		Phase.RUNNING:
			t_round += delta
			t_total += delta
			while event_cursor < events.size() and float((events[event_cursor] as Dictionary)["t"]) <= t_round:
				_fire_event(events[event_cursor])
				event_cursor += 1
			var busy := _tick_targets(delta)
			if event_cursor >= events.size() and not busy:
				phase = Phase.ROUND_END
				t_phase = 0.0
		Phase.ROUND_END:
			_tick_targets(delta)
			if t_phase >= ROUND_END_TIME:
				_next_round()


func _check_player() -> bool:
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.get("is_dead") == true:
		sys.call("abort_activity", "down")
		return false
	if Game.get_player_vehicle() != null:
		sys.call("abort_activity", "left the firing line")
		return false
	var pos: Vector3 = p.global_position
	var lp := frame_inv * pos
	var off := Vector2(pos.x - lane_xf.origin.x, pos.z - lane_xf.origin.z).length()
	if lp.x > FIRING_LINE_X or off > LANE_LEAVE_DIST or absf(pos.y - lane_xf.origin.y) > 3.0:
		sys.call("abort_activity", "left the firing line")
		return false
	return true


func _enforce_weapon() -> void:
	var p := Game.player
	var inv: Node = p.get("inventory") as Node if p != null else null
	if inv == null:
		return
	if str(inv.get("current_id")) != weapon_id and bool(inv.call("has_weapon", weapon_id)):
		inv.call("equip", weapon_id)


func _next_round() -> void:
	var rounds: Array = def.get("rounds", [])
	round_index += 1
	if round_index >= rounds.size():
		_complete()
		return
	var r: Dictionary = rounds[round_index]
	_show_round_targets(round_index)
	_build_schedule(r)
	# top the reserve up for the next round
	var p := Game.player
	var inv: Node = p.get("inventory") as Node if p != null else null
	if inv != null and round_index > 0:
		inv.call("give_weapon", weapon_id, int(def.get("ammo", 150)) / 2)
	phase = Phase.ROUND_INTRO
	t_phase = 0.0
	UI.banner("ROUND %d" % (round_index + 1), str(r.get("name", "")).to_upper(), Color(0.37, 0.84, 0.8), ROUND_INTRO_TIME)
	_log("round %d (%s): %d volleys" % [round_index + 1, str(r.get("name", "")), events.size()])


## Turns the round parameters into volleys {t, idx, window} (Game.rng: --seed makes it repeatable).
func _build_schedule(r: Dictionary) -> void:
	events.clear()
	event_cursor = 0
	var kind := str(r.get("type", "popup"))
	var rows: Array = r.get("rows", [0.0])
	var n := maxi(int(r.get("exposures", 6)), 1)
	var together := maxi(int(r.get("together", 1)), 1)
	var window := maxf(float(r.get("window", 2.0)), 0.4)
	var gap := maxf(float(r.get("gap", 0.5)), 0.0)
	var t := 0.3
	var made := 0
	var last_lanes: Array[int] = []
	while made < n:
		var count := mini(together, n - made)
		var idx := PackedInt32Array()
		var w := window
		if kind == "mover":
			var movers: Array[int] = []
			for row: Variant in rows:
				var mi := int(by_key.get("mover:0:%.2f" % float(row), -1))
				if mi >= 0:
					movers.append(mi)
			movers.shuffle()
			var sp: Array = r.get("speed", [1.6, 2.4])
			var speed := Game.rng.randf_range(float(sp[0]), float(sp[1]))
			w = minf(MOVER_Z * 2.0 / maxf(speed, 0.2), window * 1.6)
			for k in mini(count, movers.size()):
				idx.append(movers[k])
		else:
			var lanes_pick: Array[int] = [0, 1, 2, 3, 4]
			lanes_pick.shuffle()
			# do not repeat the same lane right away when there is a choice
			lanes_pick.sort_custom(func(a: int, b: int) -> bool: return int(last_lanes.has(a)) < int(last_lanes.has(b)))
			last_lanes.clear()
			for k in mini(count, 5):
				var lane: int = lanes_pick[k]
				var row := float(rows[Game.rng.randi() % rows.size()])
				var ti := int(by_key.get("%s:%d:%.2f" % [kind, lane, row], -1))
				if ti >= 0:
					idx.append(ti)
					last_lanes.append(lane)
		if idx.is_empty():
			break
		events.append({"t": t, "idx": idx, "window": w})
		made += idx.size()
		t += w + RISE_TIME + FALL_TIME + gap


func _fire_event(e: Dictionary) -> void:
	var idx: PackedInt32Array = e["idx"]
	var w := float(e["window"])
	for i in idx:
		var t: Target = targets[i]
		t.window = w
		t.t_left = w
		t.open = true
		t.knocked = false
		t.state = TS.RISING
		exposures += 1
		var base := 15 if t.kind == "mover" else 10
		var row_bonus := 0
		if t.kind == "popup":
			row_bonus = 0 if t.row < 0.0 else (3 if t.row < 7.0 else 6)
		t.row_bonus = row_bonus
		max_score += 10 if t.kind == "turner" else base + 5 + row_bonus + CENTRE_BONUS
		if t.kind == "mover":
			var dir := 1.0 if Game.rng.randf() < 0.5 else -1.0
			t.z_from = -MOVER_Z * dir
			t.z_to = MOVER_Z * dir
			_place_node(t, t.z_from)
		Audio.play_at("weapon_switch", t.node.global_position, -10.0, 0.7, 40.0)


## Animates every target; returns true while any target is still up / moving.
func _tick_targets(delta: float) -> bool:
	var busy := false
	for t: Target in targets:
		if t.state == TS.DOWN:
			continue
		busy = true
		match t.state:
			TS.RISING:
				t.anim = minf(t.anim + delta / (TURN_TIME if t.kind == "turner" else RISE_TIME), 1.0)
				if t.anim >= 1.0:
					t.state = TS.UP
			TS.UP:
				t.t_left -= delta
				if t.t_left <= 0.0:
					if t.open:
						t.open = false      # expired: missed exposure
					t.state = TS.FALLING
			TS.FALLING:
				var dur := TURN_TIME if t.kind == "turner" else (KNOCK_TIME if t.knocked else FALL_TIME)
				t.anim = maxf(t.anim - delta / dur, 0.0)
				if t.anim <= 0.0:
					t.state = TS.DOWN
		if t.kind == "mover" and (t.state == TS.UP or t.state == TS.RISING):
			var f := clampf(1.0 - t.t_left / maxf(t.window, 0.01), 0.0, 1.0)
			_place_node(t, lerpf(t.z_from, t.z_to, f))
		_pose(t)
	# a target that just finished falling still reports busy for this frame - fine
	return busy


func _on_target_hit(index: int, info: Dictionary) -> void:
	if phase != Phase.RUNNING and phase != Phase.ROUND_END:
		return
	if index < 0 or index >= targets.size():
		return
	var t: Target = targets[index]
	if not t.open or (t.state != TS.UP and t.state != TS.RISING):
		return
	if str(info.get("type", "")) != "bullet" or not Dmg.is_player(info.get("instigator", null)):
		return
	var pos: Vector3 = info.get("position", t.pivot.global_position)
	var lp := t.pivot.global_transform.affine_inverse() * pos
	var d := Vector2(lp.x - t.hit_center.x, lp.y - t.hit_center.y).length()
	var pts := 0
	var label := ""
	if t.kind == "turner":
		for k in RING_RADII.size():
			if d <= RING_RADII[k]:
				pts = RING_POINTS[k]
				break
		if pts == 0:
			return                         # clipped the rim of the collider outside the scoring rings
		label = "+%d" % pts
		t.state = TS.FALLING              # turns away
	else:
		var base := 15 if t.kind == "mover" else 10
		var speed_bonus := int(round(5.0 * clampf(t.t_left / maxf(t.window, 0.01), 0.0, 1.0)))
		pts = base + speed_bonus + t.row_bonus
		if d <= CENTRE_RADIUS:
			pts += CENTRE_BONUS
			label = "+%d  CENTRE" % pts
		else:
			label = "+%d" % pts
		t.state = TS.FALLING
		t.knocked = true
		t.t_left = 0.0
	t.open = false
	hits += 1
	exposures_hit += 1
	score += pts
	_pop_label(pos + Vector3.UP * 0.35, label)
	Audio.play("target_hit", -3.0, 1.0 + 0.04 * float(pts % 5), "UI")
	if t.kind != "turner":
		Fx.sparks(pos, (Game.get_player_position() - pos).normalized(), 0.6)
	_pose(t)


func on_weapon_fired(fired_id: String, shooter: Node) -> void:
	if phase != Phase.RUNNING and phase != Phase.ROUND_END:
		return
	if shooter == null or shooter != Game.player:
		return
	if fired_id != weapon_id:
		return
	shots += 1


func _pop_label(pos: Vector3, text: String) -> void:
	if _labels.is_empty():
		return
	var l := _labels[_label_next]
	_label_t[_label_next] = LABEL_TIME
	_label_next = (_label_next + 1) % _labels.size()
	l.text = text
	l.global_position = pos
	l.modulate.a = 1.0
	l.outline_modulate.a = 0.9
	l.visible = true


func _tick_labels(delta: float) -> void:
	for i in _labels.size():
		if _label_t[i] <= 0.0:
			continue
		_label_t[i] -= delta
		var l := _labels[i]
		l.position.y += delta * 0.7
		var a := clampf(_label_t[i] / (LABEL_TIME * 0.5), 0.0, 1.0)
		l.modulate.a = a
		l.outline_modulate.a = a * 0.9
		if _label_t[i] <= 0.0:
			l.visible = false


# =================================================================================================
# end
# =================================================================================================

func _complete() -> void:
	phase = Phase.DONE
	var accuracy := float(hits) / float(shots) if shots > 0 else 0.0
	var acc_bonus := int(round(accuracy * ACCURACY_BONUS))
	var final_score := score + acc_bonus
	var max_total := max_score + ACCURACY_BONUS
	var frac := float(final_score) / float(maxi(max_total, 1))
	var medals: Dictionary = def.get("medals", {})
	var medal := "none"
	for m: String in ["gold", "silver", "bronze"]:
		if frac >= float(medals.get(m, 2.0)):
			medal = m
			break
	_restore()
	_hide_all()
	last_result = {
		"score": final_score, "target_points": score, "accuracy_bonus": acc_bonus, "max_score": max_total,
		"hits": hits, "shots": shots, "accuracy": accuracy, "exposures": exposures, "targets_hit": exposures_hit,
		"time": t_total, "medal": medal, "fraction": frac, "weapon": weapon_id,
	}
	_log("course done: score %d / %d (%.0f%%), hits %d / %d exposures, shots %d, medal %s" % [final_score, max_total,
			frac * 100.0, exposures_hit, exposures, shots, medal])
	phase = Phase.IDLE
	sys.call("_on_range_complete", def, last_result)


## Abort (player left, died, system disabled ...). Restores inventory and Wanted.
func abort(_reason: String) -> void:
	if phase == Phase.IDLE:
		return
	phase = Phase.IDLE
	_restore()
	_hide_all()


func _restore() -> void:
	var p := Game.player
	var inv: Node = p.get("inventory") as Node if (p != null and is_instance_valid(p)) else null
	if inv != null and _have_snapshot:
		inv.call("load_save_data", _snapshot)
	_have_snapshot = false
	_snapshot = {}
	if _wanted_switched:
		_wanted_switched = false
		var wanted := sys.get_node_or_null("/root/Wanted")
		if wanted != null and not bool(wanted.get("enabled")):
			wanted.set("enabled", _wanted_prev)


func _hide_all() -> void:
	for t: Target in targets:
		_reset_target(t)
		t.node.visible = false


## HUD keys (activity_system.get_hud_info): score, round / rounds (= checkpoint / total), hits,
## shots; the round goes into the subtitle (the UI card shows CP / LAP chips only for races).
func fill_hud(info: Dictionary) -> void:
	var rounds: Array = def.get("rounds", [])
	var rn := clampi(round_index, 0, maxi(rounds.size() - 1, 0))
	info["title"] = str(def.get("display_name", "Shooting Range"))
	if round_index >= 0 and not rounds.is_empty():
		info["subtitle"] = "Round %d/%d  %s" % [rn + 1, rounds.size(), str((rounds[rn] as Dictionary).get("name", ""))]
	else:
		info["subtitle"] = str(def.get("subtitle", ""))
	info["timer"] = t_total
	info["time"] = t_total
	info["time_mode"] = "up"
	info["score"] = score
	info["checkpoint"] = rn + 1 if round_index >= 0 else 0
	info["total"] = rounds.size()
	info["round"] = rn + 1 if round_index >= 0 else 0
	info["rounds"] = rounds.size()
	info["hits"] = exposures_hit
	info["shots"] = shots
	info["color"] = Color(0.933, 0.494, 0.392)
	var hint := ""

	match phase:
		Phase.STARTING:
			hint = "Get ready"
		Phase.INTRO:
			hint = "Starting in %d" % maxi(int(ceil(INTRO_TIME - t_phase)), 1)
		Phase.ROUND_INTRO:
			var r: Dictionary = rounds[clampi(round_index, 0, rounds.size() - 1)] if not rounds.is_empty() else {}
			hint = "Round %d: %s" % [round_index + 1, str(r.get("name", ""))]
		Phase.RUNNING:
			hint = "Accuracy %d%%" % int(round(100.0 * float(hits) / float(maxi(shots, 1)))) if shots > 0 else "Shoot the targets"
		Phase.ROUND_END:
			hint = "Round %d done" % (round_index + 1)
	info["hint"] = hint
	info["countdown"] = maxf(INTRO_TIME - t_phase, 0.0) if phase == Phase.INTRO else 0.0
	info["phase"] = ["idle", "starting", "intro", "round_intro", "running", "round_end", "done"][phase]


# =================================================================================================
# tests / debug
# =================================================================================================

## Indices of targets that are up and can be scored right now.
func get_open_targets() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in targets.size():
		var t: Target = targets[i]
		if t.open and t.state == TS.UP:
			out.append(i)
	return out


## World point a scripted shot should aim at (centre of the plate / bullseye).
func get_target_aim_point(i: int) -> Vector3:
	var t: Target = targets[i]
	return t.pivot.global_transform * t.hit_center


## Raises every target of the current / first round at once (screenshots).
func debug_raise_all(kind: String = "popup") -> void:
	for t: Target in targets:
		if t.kind == kind and _key_in_course(t):
			t.node.visible = true
			t.state = TS.UP
			t.anim = 1.0
			t.t_left = 30.0
			t.window = 30.0
			if t.kind == "mover":
				_place_node(t, Game.rng.randf_range(-MOVER_Z, MOVER_Z))
			_pose(t)


## Lays every target of a kind down (screenshots); hide = also hide the models.
func debug_lower_all(kind: String, hide: bool = false) -> void:
	for t: Target in targets:
		if t.kind == kind:
			_reset_target(t)
			if hide:
				t.node.visible = false


func get_lane_transform() -> Transform3D:

	return lane_xf


func _log(s: String) -> void:
	debug_log.append(s)
	if debug_log.size() > 40:
		debug_log.remove_at(0)
	print("[Activities] range: ", s)
