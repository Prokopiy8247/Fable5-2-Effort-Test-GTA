class_name PlayerStateLadder
extends PlayerState
## Ladder climbing (ARCHITECTURE_WAVE2 W2.4): any Node3D in group "ladder" with its origin at the
## foot of the ladder, the climber facing local -Z, and get_meta("height") in metres.
##
##   mount    at the foot (interact, or jump while facing it), at the top (interact near the top
##            exit, the player turns round and climbs down) or from the water (harbour ladders)
##   climb    move_forward = up, move_back = down (camera independent), sprint = faster,
##            crouch held = slide down
##   leave    up at the top -> pull over onto the top; down at the foot -> step off backwards (into
##            the water when the foot is wet); jump -> push off backwards; interact -> let go
##
## Collision is off while on the ladder; the animator plays "climb_ladder" (hands and feet
## alternate with the climbed distance through vertical_speed).
##
## Wave 3: leaning ladders - when the node carries the metas "line_bottom" / "line_top" (world points
## of the real rail line, CityBuilder: the radio-mast cage leans 0.7 m) the body follows that line
## (STAND_OFF behind it at chest height) instead of climbing straight up from the node. The top exit
## tries the node's "top" (city: Ladder_Top marker) / "top_exit" (dressing) meta first, then points
## 0.55 - 1.4 m past the ladder line, also 0.5 m to either side (a prop on the platform edge).

const CLIMB_SPEED := 1.6
const CLIMB_FAST := 2.5
const SLIDE_SPEED := 4.5
const STAND_OFF := 0.36                 ## body origin behind the ladder line (+Z of the ladder)
const TOP_HANG := 1.05                  ## highest origin = top - TOP_HANG; above that = dismount
const TOP_EXIT_FORWARD := 0.55          ## where the player stands after climbing over the top
const MOUNT_RADIUS := 0.95              ## horizontal reach of the foot mount
const TOP_MOUNT_RADIUS := 1.0
const MOUNT_TIME := 0.32
const TOP_DISMOUNT_TIME := 0.85
const TOP_MOUNT_TIME := 0.7
const DEFAULT_HEIGHT := 3.0
const LINE_CHEST := 1.0                 ## the body keeps STAND_OFF from the rail line at this height above its feet
const EXIT_SIDE: Array[float] = [0.0, -0.5, 0.5]     ## lateral offsets tried for the top exit

enum { MOUNT, CLIMB, TOP_OUT, TOP_IN }

var ladder: Node3D = null
var height: float = DEFAULT_HEIGHT
var climb_y: float = 0.0                ## origin height above the ladder foot
var phase: int = CLIMB

var _t: float = 0.0
var _from: Vector3
var _from_yaw: float = 0.0
var _rung_dist: float = 0.0
var _vspeed: float = 0.0
var _q: PhysicsShapeQueryParameters3D = null
var _cap: CapsuleShape3D = null
var _ray: PhysicsRayQueryParameters3D = null
var _exit: Vector3 = Vector3.INF          ## where the top-out ends (found when the top is reached)
var _line_b: Vector3 = Vector3.INF        ## leaning rail line (world) or INF = vertical from the node
var _line_t: Vector3 = Vector3.INF


func _init() -> void:
	public_name = "ladder"


# --- static helpers (also used by Player.find_ladder) -------------------------------------------

static func ladder_height(l: Node3D) -> float:
	if l != null and l.has_meta("height"):
		return maxf(float(l.get_meta("height")), 0.5)
	return DEFAULT_HEIGHT


## Climber side of the ladder (+Z of the node, flattened).
static func ladder_back(l: Node3D) -> Vector3:
	var b := l.global_transform.basis.z
	b.y = 0.0
	return b.normalized() if b.length_squared() > 0.0001 else Vector3.BACK


## The leaning rail line of `l` ([bottom, top] world points) or [] for a vertical ladder.
static func ladder_line(l: Node3D) -> Array:
	if l == null or not l.has_meta("line_bottom") or not l.has_meta("line_top"):
		return []
	var b: Variant = l.get_meta("line_bottom")
	var t: Variant = l.get_meta("line_top")
	if not (b is Vector3) or not (t is Vector3) or not (b as Vector3).is_finite() or not (t as Vector3).is_finite():
		return []
	if (t as Vector3).y - (b as Vector3).y < 0.5:
		return []
	return [b, t]


## Body origin (feet) on ladder `l` at `climb_y` above its foot: STAND_OFF behind the rail line at
## chest height (leaning ladders), else straight up from the node.
static func climb_point(l: Node3D, climb_y: float) -> Vector3:
	var foot := l.global_position
	var back := ladder_back(l)
	var p := foot + back * STAND_OFF + Vector3(0.0, climb_y, 0.0)
	var line := ladder_line(l)
	if line.is_empty():
		return p
	var lb: Vector3 = line[0]
	var lt: Vector3 = line[1]
	var y := foot.y + climb_y + LINE_CHEST
	var k := clampf((y - lb.y) / (lt.y - lb.y), 0.0, 1.0)
	var q := lb.lerp(lt, k)
	return Vector3(q.x, foot.y + climb_y, q.z) + back * STAND_OFF


## Can a player with feet at `feet` mount `l` right now? {} or {"ladder", "from_top", "distance"}.
static func mount_info(l: Node3D, feet: Vector3, swimming: bool) -> Dictionary:
	if l == null or not l.is_inside_tree():
		return {}
	var foot := l.global_position
	var back := ladder_back(l)
	var h := ladder_height(l)
	var stand := climb_point(l, 0.0)
	var d := Vector2(feet.x - stand.x, feet.z - stand.z).length()
	var low := foot.y - (2.4 if swimming else 0.7)
	if d < MOUNT_RADIUS * (1.4 if swimming else 1.0) and feet.y > low and feet.y < foot.y + minf(h - TOP_HANG, 1.2) + 0.1:
		return {"ladder": l, "from_top": false, "distance": d}
	if swimming:
		return {}
	var line := ladder_line(l)
	var top_base := foot if line.is_empty() else Vector3((line[1] as Vector3).x, foot.y, (line[1] as Vector3).z)
	var top := top_base + Vector3(0.0, h, 0.0) - back * TOP_EXIT_FORWARD
	var dt := Vector2(feet.x - top.x, feet.z - top.z).length()
	if dt < TOP_MOUNT_RADIUS and absf(feet.y - (foot.y + h)) < 0.75:
		return {"ladder": l, "from_top": true, "distance": dt}
	return {}


# --- state ------------------------------------------------------------------------------------------

func enter(_previous: String, args: Dictionary) -> void:
	var p := player
	ladder = args.get("ladder", null) as Node3D
	if ladder == null or not is_instance_valid(ladder):
		p.change_state.call_deferred("on_foot", {})
		return
	height = ladder_height(ladder)
	p.on_ladder = true
	p.is_sprinting = false
	p.noise_radius = 0.0
	p.set_aiming(false)
	p.release_trigger()
	if p.is_crouching:
		p.set_crouching(false, true)
	p.is_swimming = false
	p.is_underwater = false
	p.set_collision_enabled(false)
	p.velocity = Vector3.ZERO
	_from = p.global_position
	_from_yaw = p.rotation.y
	_t = 0.0
	_rung_dist = 0.0
	_vspeed = 0.0
	_exit = Vector3.INF
	var line := ladder_line(ladder)
	_line_b = line[0] if not line.is_empty() else Vector3.INF
	_line_t = line[1] if not line.is_empty() else Vector3.INF
	if bool(args.get("from_top", false)):
		phase = TOP_IN
		climb_y = maxf(height - TOP_HANG, 0.0)
	else:
		phase = MOUNT
		climb_y = clampf(_from.y - ladder.global_position.y, 0.0, maxf(height - TOP_HANG, 0.0))
	if p.animator != null:
		p.animator.stop_action()
	p.set_anim_state("climb_ladder", 0.18)
	Audio.play_at("footstep_metal", _from, -6.0, 1.0, 25.0)


func exit(_next: String) -> void:
	var p := player
	p.on_ladder = false
	if not p.is_dead:
		p.set_collision_enabled(true)
	if p.animator != null:
		p.animator.vertical_speed = 0.0


func allows_weapons() -> bool:
	return false


func physics_update(delta: float) -> void:
	var p := player
	if ladder == null or not is_instance_valid(ladder) or not ladder.is_inside_tree():
		_let_go()
		return
	_t += delta
	var foot := ladder.global_position
	var back := ladder_back(ladder)
	var yaw := atan2(back.x, back.z)          # facing = -back
	match phase:
		MOUNT:
			var k := clampf(_t / MOUNT_TIME, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			p.global_position = _from.lerp(_climb_pos(foot, back), e)
			p.rotation.y = lerp_angle(_from_yaw, yaw, e)
			if k >= 1.0:
				phase = CLIMB
		TOP_IN:
			# from the top platform: step to the edge, turn round, lower onto the rungs
			var k2 := clampf(_t / TOP_MOUNT_TIME, 0.0, 1.0)
			var e2 := k2 * k2 * (3.0 - 2.0 * k2)
			var edge := foot + Vector3(0.0, height, 0.0) - back * 0.15
			if _line_t.is_finite():
				edge = Vector3(_line_t.x, foot.y + height, _line_t.z) - back * 0.15
			var target := _climb_pos(foot, back)
			var pos := _from.lerp(edge, minf(e2 * 1.6, 1.0))
			if e2 > 0.45:
				pos = edge.lerp(target, (e2 - 0.45) / 0.55)
			p.global_position = pos
			p.rotation.y = lerp_angle(_from_yaw, yaw, e2)
			_vspeed = -1.0 if e2 > 0.45 else 0.0
			if k2 >= 1.0:
				phase = CLIMB
				_vspeed = 0.0
		CLIMB:
			_update_climb(delta, foot, back, yaw)
		TOP_OUT:
			var k3 := clampf(_t / TOP_DISMOUNT_TIME, 0.0, 1.0)
			var top_stand := _exit if _exit.is_finite() else foot + Vector3(0.0, height, 0.0) - back * TOP_EXIT_FORWARD
			var start := _climb_pos(foot, back)
			var pos3: Vector3
			if k3 < 0.55:
				# pull up the last rungs
				var m := k3 / 0.55
				pos3 = start.lerp(Vector3(start.x, foot.y + height - 0.25, start.z), m * m * (3.0 - 2.0 * m))
				_vspeed = CLIMB_SPEED
			else:
				# over the edge onto the top
				var m2 := (k3 - 0.55) / 0.45
				var e3 := m2 * m2 * (3.0 - 2.0 * m2)
				var mid := Vector3(start.x, foot.y + height - 0.25, start.z)
				pos3 = mid.lerp(top_stand, e3)
				pos3.y = lerpf(mid.y, top_stand.y, sqrt(e3))
				_vspeed = 0.4
			p.global_position = pos3
			p.rotation.y = yaw
			if k3 >= 1.0:
				p.global_position = top_stand + Vector3(0.0, 0.02, 0.0)
				p.velocity = Vector3.ZERO
				p.change_state("on_foot", {})
				return
	if p.animator != null:
		p.animator.vertical_speed = _vspeed
	p.set_anim_state("climb_ladder")


func _climb_pos(foot: Vector3, back: Vector3) -> Vector3:
	if _line_b.is_finite() and ladder != null and is_instance_valid(ladder):
		return climb_point(ladder, climb_y)
	return foot + back * STAND_OFF + Vector3(0.0, climb_y, 0.0)


func _update_climb(delta: float, foot: Vector3, back: Vector3, yaw: float) -> void:
	var p := player
	var input := p.get_move_input()
	# jump: push off backwards
	if p.just_pressed("jump"):
		p.global_position = _climb_pos(foot, back)
		p.velocity = back * 3.2 + Vector3(0.0, 2.4, 0.0)
		p.rotation.y = yaw
		p.set_collision_enabled(true)
		p.change_state("air", {})
		return
	if p.just_pressed("interact") and not p.interaction_handles("interact"):
		_let_go()
		return
	var v := 0.0
	if p.pressed("crouch") and climb_y > 0.0:
		v = -SLIDE_SPEED
	elif absf(input.y) > 0.2:
		v = signf(input.y) * (CLIMB_FAST if p.pressed("sprint") else CLIMB_SPEED)
	var top_y := maxf(height - TOP_HANG, 0.0)
	climb_y = clampf(climb_y + v * delta, 0.0, top_y)
	_vspeed = v
	p.global_position = _climb_pos(foot, back)
	p.rotation.y = yaw
	p.velocity = Vector3(0.0, v, 0.0)
	if v > 0.0:
		p.update_stamina(delta, false)
		Skills.add_xp("stamina", delta * 0.01)
	# rung sounds
	_rung_dist += absf(v) * delta
	if _rung_dist > 0.6:
		_rung_dist = 0.0
		Audio.play_at("footstep_metal", p.global_position, -12.0, randf_range(0.95, 1.1), 20.0)
		p.emit_noise(Player.NOISE_WALK, "footstep")
	# top: climb over when there is room, else stay at the top
	if climb_y >= top_y - 0.001 and input.y > 0.2:
		_exit = find_top_exit(foot, back)
		if _exit.is_finite():
			phase = TOP_OUT
			_t = 0.0
			Audio.play_at("footstep_metal", p.global_position, -8.0, 0.9, 20.0)
		return
	# bottom: step off backwards (into the water if the foot is wet)
	if climb_y <= 0.001 and input.y < -0.2:
		var off := climb_point(ladder, 0.0) + back * 0.25
		p.global_position = off + Vector3(0.0, 0.03, 0.0)
		p.velocity = Vector3.ZERO
		p.set_collision_enabled(true)
		p.update_water()
		if p.water_depth > Player.SWIM_ENTER_DEPTH or Game.is_in_water(off + Vector3(0.0, 0.3, 0.0)):
			p.change_state("swim", {"entry_speed": 0.5})
		else:
			p.change_state("on_foot", {})


func _let_go() -> void:
	var p := player
	p.set_collision_enabled(true)
	if ladder != null and is_instance_valid(ladder):
		p.global_position += ladder_back(ladder) * 0.15
	p.velocity = Vector3.ZERO
	if not p.is_dead:
		p.change_state("air", {})


## Standing spot beyond the top of the ladder: the node's own "top" / "top_exit" meta, then the first of
## a few distances past the ladder line (straight, then 0.5 m to either side) with walkable ground near
## the top height and room for a standing capsule (platform lips, rails, a prop on the edge).
## Vector3.INF = no room (the player waits at the top).
func find_top_exit(foot: Vector3, back: Vector3) -> Vector3:
	var p := player
	if not p.is_inside_tree():
		return Vector3.INF
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.PROP
	_ray.exclude = [p.get_rid()]
	var top_y := foot.y + height
	var line_top := foot
	if _line_t.is_finite():
		line_top = Vector3(_line_t.x, foot.y, _line_t.z)
	# the ladder's own exit point (marker / dressing meta) when it is a real standing spot
	for key: String in ["top", "top_exit"]:
		if ladder != null and is_instance_valid(ladder) and ladder.has_meta(key):
			var mv: Variant = ladder.get_meta(key)
			if mv is Vector3 and (mv as Vector3).is_finite():
				var m := mv as Vector3
				var flat := Vector2(m.x - line_top.x, m.z - line_top.z).length()
				if flat < 2.0 and absf(m.y - top_y) < 0.9:
					var g0 := _ground_at(m, top_y)
					if g0.is_finite() and _room_at(g0):
						return g0
	var side := Vector3.UP.cross(back).normalized()
	for lat: float in EXIT_SIDE:
		for d: float in [TOP_EXIT_FORWARD, 0.8, 1.1, 1.4]:
			var q := line_top - back * d + side * lat
			var g := _ground_at(q, top_y)
			if g.is_finite() and _room_at(g):
				return g
	return Vector3.INF


## Walkable ground under `q` near `top_y` (ray from 0.9 m above to 0.7 m below), or INF.
func _ground_at(q: Vector3, top_y: float) -> Vector3:
	_ray.from = Vector3(q.x, top_y + 0.9, q.z)
	_ray.to = Vector3(q.x, top_y - 0.7, q.z)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.7:
		return Vector3.INF
	return hit["position"]


func _room_at(feet: Vector3) -> bool:
	var p := player
	if not p.is_inside_tree():
		return false
	if _q == null:
		_q = PhysicsShapeQueryParameters3D.new()
		_cap = CapsuleShape3D.new()
		_cap.radius = Player.CAPSULE_RADIUS - 0.04
		_cap.height = Player.STAND_HEIGHT - 0.15
		_q.shape = _cap
		_q.collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.PROP
	_q.exclude = [p.get_rid()]
	_q.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0.0, _cap.height * 0.5 + 0.06, 0.0))
	return p.get_world_3d().direct_space_state.intersect_shape(_q, 1).is_empty()
