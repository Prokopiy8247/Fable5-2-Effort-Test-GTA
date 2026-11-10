class_name PlayerMoves
extends Node
## Contextual traversal and close-quarters moves of the player: cover system (low / high,
## slide along, peek-aim, blind fire, corner rounding), vault / mantle, ladders, combat
## roll, stealth takedown, freefall and parachute.

enum Mode { NONE, COVER, VAULT, LADDER, ROLL, FREEFALL, CHUTE, TAKEDOWN }

static var ladders: Array = []      # {bottom: Vector3, top: Vector3, normal: Vector3}

var p: Player
var mode: int = Mode.NONE
var cover_normal := Vector3.ZERO
var cover_low := true
var cover_edge := 0           # -1 / +1 when at the end of the cover
var _edge_hold := 0.0
var _leave_hold := 0.0
var _t := 0.0
var _dur := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _arc := 0.0
var _ladder: Dictionary = {}
var _ladder_s := 0.0
var _roll_dir := Vector3.ZERO
var _canopy: Node3D = null
var _chute_yaw := 0.0
var _peeking := false
var _near_ladder: Dictionary = {}
var agl := 0.0                 # height above ground while skydiving (for the HUD altimeter)

func setup(player: Player) -> void:
	p = player

static func add_ladder(bottom: Vector3, top: Vector3, normal: Vector3) -> void:
	ladders.append({"bottom": bottom, "top": top, "normal": normal.normalized()})

func in_cover() -> bool:
	return mode == Mode.COVER

func cancel() -> void:
	if _canopy != null and is_instance_valid(_canopy):
		_canopy.queue_free()
	_canopy = null
	mode = Mode.NONE
	p.collision_mask = p._body_mask

func prompt() -> String:
	if not _near_ladder.is_empty():
		return "[E] Climb ladder"
	return ""

func _ray(from: Vector3, to: Vector3, mask := Phys.WORLD | Phys.VEHICLE | Phys.PROP) -> Dictionary:
	return Game.ray(from, to, mask, [p.get_rid()])

# ---------------------------------------------------------------- per-frame checks while on foot
func foot_checks(_delta: float, _dir: Vector3) -> void:
	_near_ladder = {}
	for l in ladders:
		var b: Vector3 = l["bottom"]
		var t: Vector3 = l["top"]
		if p.global_position.distance_to(b) < 1.5 or p.global_position.distance_to(t) < 1.6:
			_near_ladder = l
			break
	if not _near_ladder.is_empty() and not Game.ui_blocked() and Input.is_action_just_pressed("interact"):
		_start_ladder(_near_ladder)

func tick(delta: float) -> void:
	match mode:
		Mode.COVER: _tick_cover(delta)
		Mode.VAULT: _tick_vault(delta)
		Mode.LADDER: _tick_ladder(delta)
		Mode.ROLL: _tick_roll(delta)
		Mode.FREEFALL, Mode.CHUTE: _tick_air(delta)
		Mode.TAKEDOWN:
			_t += delta
			if _t >= _dur:
				_end()
		_:
			_end()

func _end() -> void:
	mode = Mode.NONE
	p.collision_mask = p._body_mask
	if p.alive:
		p.state = Player.St.FOOT

# ---------------------------------------------------------------- cover
func try_cover() -> bool:
	if mode == Mode.COVER:
		_end()
		p.set_crouched(false)
		return false
	var origin := p.global_position + Vector3(0, 0.7, 0)
	var best := {}
	var dirs := [p.forward(), Basis(Vector3.UP, p.camera_yaw()) * Vector3.FORWARD]
	for a: float in [0.0, 0.6, -0.6, 1.2, -1.2]:
		dirs.append(p.forward().rotated(Vector3.UP, a))
	for d in dirs:
		var hit := _ray(origin, origin + (d as Vector3) * 1.9)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if absf(n.y) > 0.35:
			continue
		if best.is_empty() or origin.distance_to(hit["position"]) < origin.distance_to(best["position"]):
			best = hit
	if best.is_empty():
		return false
	_snap_cover(best)
	return true

func _snap_cover(hit: Dictionary) -> void:
	var n: Vector3 = hit["normal"]
	n.y = 0.0
	n = n.normalized()
	cover_normal = n
	var pos: Vector3 = hit["position"]
	p.global_position = Vector3(pos.x, p.global_position.y, pos.z) + n * 0.44
	# high or low cover?
	var head := p.global_position + Vector3(0, 1.55, 0)
	cover_low = _ray(head, head - n * 1.2).is_empty()
	p.set_crouched(cover_low)
	p.velocity = Vector3.ZERO
	p.set_face_yaw(atan2(-n.x, -n.z))
	mode = Mode.COVER
	p.state = Player.St.MOVE
	cover_edge = 0
	_edge_hold = 0.0
	_leave_hold = 0.0
	_peeking = false
	Audio.play(&"roll", p.global_position, -14.0)

func _cover_probe(pos: Vector3) -> Dictionary:
	var o := pos + Vector3(0, 0.6, 0)
	return _ray(o, o - cover_normal * 1.1)

func _tick_cover(delta: float) -> void:
	if not p.alive or p.down:
		_end()
		return
	var blocked := Game.ui_blocked()
	var tangent := cover_normal.cross(Vector3.UP).normalized()
	var dir := p.input_dir()
	var along := dir.dot(tangent)
	var away := dir.dot(cover_normal)
	var aim := not blocked and Input.is_action_pressed("aim") and p.gunner.is_gun()
	var fire := not blocked and Input.is_action_pressed("fire")
	# leaving: [Q], jump, sprint, or walking away from the wall
	if not blocked and (Input.is_action_just_pressed("cover") or Input.is_action_just_pressed("jump") or Input.is_action_pressed("sprint")):
		p.set_crouched(false)
		_end()
		return
	if away > 0.7 and not aim:
		_leave_hold += delta
		if _leave_hold > 0.22:
			p.set_crouched(false)
			_end()
			return
	else:
		_leave_hold = 0.0
	# --- sliding along the cover, stopping (or rounding the corner) at its ends
	cover_edge = 0
	if absf(along) > 0.2 and not aim:
		var step := tangent * signf(along) * 1.9 * delta
		var next := p.global_position + step
		var probe := _cover_probe(next + tangent * signf(along) * 0.28)
		if probe.is_empty():
			cover_edge = int(signf(along))
			_edge_hold += delta
			if _edge_hold > 0.45:
				_round_corner(tangent * signf(along))
		else:
			_edge_hold = 0.0
			var hp: Vector3 = probe["position"]
			p.global_position = Vector3(hp.x, p.global_position.y, hp.z) + cover_normal * 0.44 - tangent * signf(along) * 0.28
			var head := p.global_position + Vector3(0, 1.55, 0)
			var low := _ray(head, head - cover_normal * 1.2).is_empty()
			if low != cover_low:
				cover_low = low
				p.set_crouched(low)
	else:
		_edge_hold = 0.0
		# know whether we are next to an edge (for peeking out of high cover)
		for sgn: float in [-1.0, 1.0]:
			if _cover_probe(p.global_position + tangent * sgn * 0.75).is_empty():
				cover_edge = int(sgn)
	if not p.is_on_floor():
		p.velocity.y -= Character.GRAVITY * delta
	else:
		p.velocity.y = 0.0
	p.velocity.x = 0.0
	p.velocity.z = 0.0
	p.move_and_slide()
	# --- shooting from cover
	p.gunner.driveby = false
	var target: Vector3 = Game.cam.aim_point() if Game.cam else p.global_position + p.forward() * 20.0
	if aim:
		# peek: stand up over low cover, lean out at an edge of high cover
		if not _peeking:
			_peeking = true
			if cover_low:
				p.set_crouched(false)
		p.gunner.aiming = true
		p.aiming = true
		p.set_face_yaw(lerp_angle(p.face_yaw, p.camera_yaw(), clampf(delta * 16.0, 0.0, 1.0)))
		p.visual.upper = &"aim_pistol" if p.gunner.hold() == &"pistol" else &"aim_rifle"
		p.visual.aim_pitch = Game.cam.pitch if Game.cam else 0.0
		p.visual.position = tangent * float(cover_edge) * 0.55 if (not cover_low and cover_edge != 0) else Vector3.ZERO
		p.gunner.aim_dir = (target - p.eye_position()).normalized()
		var just := Input.is_action_just_pressed("fire")
		if fire and p.gunner.trigger(target, just) and Game.cam:
			Game.cam.kick(p.gunner.recoil_kick())
	else:
		if _peeking:
			_peeking = false
			p.set_crouched(cover_low)
			p.visual.position = Vector3.ZERO
		p.aiming = false
		p.gunner.aiming = false
		p.set_face_yaw(lerp_angle(p.face_yaw, atan2(-cover_normal.x, -cover_normal.z), clampf(delta * 12.0, 0.0, 1.0)))
		p.visual.upper = &""
		p.visual.aim_pitch = 0.0
		if fire and p.gunner.is_gun():
			# blind fire: arm over / around the cover, much less accurate
			p.gunner.bloom = maxf(p.gunner.bloom, 6.0)
			p.gunner.aim_dir = (target - p.eye_position()).normalized()
			p.visual.upper = &"aim_one"
			p.gunner.trigger(target, Input.is_action_just_pressed("fire"))
	if not blocked and Input.is_action_just_pressed("reload"):
		p.gunner.reload()
	p.visual.set_state(&"cover_low" if p.crouched else &"cover_high", 0.0)
	if p.visual.upper == &"" and not p.visual.has_clip("CoverLow"):
		p.visual.state = &"crouch_idle" if p.crouched else &"idle"

func _round_corner(dirv: Vector3) -> void:
	# look for the side face of the obstacle just around the corner
	var from := p.global_position + Vector3(0, 0.6, 0) + dirv * 0.95 - cover_normal * 0.95
	var hit := _ray(from, from - dirv * 1.4)
	_edge_hold = 0.0
	if hit.is_empty():
		return
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.35 or n.dot(dirv) < 0.5:
		return
	_snap_cover(hit)

# ---------------------------------------------------------------- vault / mantle
func try_vault(dir: Vector3) -> bool:
	var fwd := dir.normalized() if dir.length() > 0.2 else p.forward()
	var base := p.global_position
	var low := _ray(base + Vector3(0, 0.45, 0), base + Vector3(0, 0.45, 0) + fwd * 1.0)
	if low.is_empty():
		return false
	var n: Vector3 = low["normal"]
	if absf(n.y) > 0.4 or n.dot(-fwd) < 0.45:
		return false
	var hp: Vector3 = low["position"]
	var dist := Vector2(hp.x - base.x, hp.z - base.z).length()       # horizontal distance to the face
	# top of the obstacle (probe just behind the face so thin walls and fences are found too)
	var probe_top := base + fwd * (dist + 0.15) + Vector3(0, 2.6, 0)
	var top := _ray(probe_top, probe_top - Vector3(0, 2.5, 0))
	if top.is_empty():
		return false
	var h: float = (top["position"] as Vector3).y - base.y
	if h < 0.4 or h > 2.35:
		return false
	# head room above the top
	if not _ray((top["position"] as Vector3) + Vector3(0, 0.2, 0), (top["position"] as Vector3) + Vector3(0, 1.7, 0)).is_empty():
		return false
	var far := base + fwd * (dist + 1.25) + Vector3(0, 2.6, 0)
	var landing := _ray(far, far - Vector3(0, 4.5, 0))
	var over := h < 1.25 and not landing.is_empty() and (landing["position"] as Vector3).y < base.y + h - 0.35
	_from = base
	if over:
		_to = landing["position"]
		_dur = 0.5
		_arc = h + 0.35
		if p.visual.play_action("Vault", 1.2) <= 0.0:
			p.visual.set_state(&"jump")
	else:
		_to = (top["position"] as Vector3) + fwd * 0.25
		_dur = 0.55 if h < 1.3 else 0.9
		_arc = 0.25
		if p.visual.play_action("Mantle", 1.0 if h >= 1.3 else 1.5) <= 0.0:
			p.visual.set_state(&"jump")
	_t = 0.0
	mode = Mode.VAULT
	p.state = Player.St.MOVE
	p.collision_mask = 0
	p.velocity = Vector3.ZERO
	p.turn_toward(fwd, 1.0, 100.0)
	Audio.play(&"climb", p.global_position, -8.0)
	return true

func _tick_vault(delta: float) -> void:
	_t += delta
	var k := clampf(_t / _dur, 0.0, 1.0)
	var pos := _from.lerp(_to, smoothstep(0.0, 1.0, k))
	# rise first, then travel: keeps the body clear of the ledge
	var rise := sin(k * PI) * _arc * 0.35 + (_to.y - _from.y) * (smoothstep(0.0, 0.55, k) - smoothstep(0.0, 1.0, k))
	if _to.y <= _from.y + 0.3:
		rise = sin(k * PI) * _arc
	pos.y += rise
	p.global_position = pos
	if k >= 1.0:
		p.velocity = Vector3.ZERO
		p.visual.stop_action()
		_end()

# ---------------------------------------------------------------- ladders
func _start_ladder(l: Dictionary) -> void:
	_ladder = l
	var b: Vector3 = l["bottom"]
	var t: Vector3 = l["top"]
	_ladder_s = 0.0 if p.global_position.distance_to(b) < p.global_position.distance_to(t) else b.distance_to(t) - 0.4
	mode = Mode.LADDER
	p.state = Player.St.MOVE
	p.velocity = Vector3.ZERO
	p.set_crouched(false)
	p.visual.upper = &""
	p.collision_mask = 0
	var n: Vector3 = l["normal"]
	p.set_face_yaw(atan2(n.x, n.z))

func _tick_ladder(delta: float) -> void:
	var b: Vector3 = _ladder["bottom"]
	var t: Vector3 = _ladder["top"]
	var n: Vector3 = _ladder["normal"]
	var length := b.distance_to(t)
	var inp := 0.0 if Game.ui_blocked() else Input.get_axis("move_back", "move_forward")
	_ladder_s = clampf(_ladder_s + inp * 2.1 * delta, 0.0, length)
	p.global_position = b.lerp(t, _ladder_s / maxf(length, 0.01)) + n * 0.38
	p.visual.set_state(&"ladder", absf(inp) * 1.2)
	if p.visual.anim and p.visual.has_clip("ClimbLadder"):
		p.visual.anim.speed_scale = absf(inp) * 1.4
	if _ladder_s >= length - 0.02 and inp > 0.0:
		p.global_position = t - n * 0.7 + Vector3(0, 0.1, 0)
		_end()
	elif _ladder_s <= 0.02 and inp < 0.0:
		p.global_position = b + n * 0.6
		_end()
	elif not Game.ui_blocked() and (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("interact")):
		p.global_position += n * 0.5
		p.velocity = n * 2.5
		_end()

# ---------------------------------------------------------------- roll / takedown
func try_roll(dir: Vector3) -> bool:
	if p.stamina < 12.0:
		return false
	p.stamina -= 12.0
	_roll_dir = dir.normalized()
	_t = 0.0
	_dur = 0.55
	mode = Mode.ROLL
	p.state = Player.St.MOVE
	p.set_crouched(true)
	if p.visual.play_action("Roll", 1.3) <= 0.0:
		p.visual.set_state(&"crouch_walk", 5.0)
	Audio.play(&"roll", p.global_position, -8.0)
	return true

func _tick_roll(delta: float) -> void:
	_t += delta
	var k := _t / _dur
	var sp := lerpf(7.5, 3.0, k)
	p.velocity.x = _roll_dir.x * sp
	p.velocity.z = _roll_dir.z * sp
	if not p.is_on_floor():
		p.velocity.y -= Character.GRAVITY * delta
	p.move_and_slide()
	p.turn_toward(_roll_dir, delta, 14.0)
	if k >= 1.0:
		p.set_crouched(false)
		_end()

func try_takedown() -> bool:
	var fwd := p.forward()
	var best: Character = null
	var best_d := 1.7
	for n in p.get_tree().get_nodes_in_group(&"npcs"):
		var c := n as Character
		if c == null or not c.alive or c.down or c.vehicle != null:
			continue
		var to := c.global_position - p.global_position
		var d := to.length()
		if d > best_d or absf(to.y) > 0.8:
			continue
		if to.normalized().dot(fwd) < 0.55:
			continue
		# only from behind and only if they have not noticed you
		if c.forward().dot(fwd) < 0.35:
			continue
		if c.has_method("is_alerted") and c.is_alerted():
			continue
		best = c
		best_d = d
	if best == null:
		return false
	var lethal := p.gunner.weapon_id == &"knife"
	_t = 0.0
	_dur = 0.8
	mode = Mode.TAKEDOWN
	p.state = Player.St.MOVE
	p.velocity = Vector3.ZERO
	p.global_position = best.global_position - best.forward() * 0.55
	p.turn_toward(best.forward(), 1.0, 100.0)
	if p.visual.play_action("Takedown", 1.3) <= 0.0:
		p.visual.recoil = 2.0
	if best.has_method("on_takedown"):
		best.on_takedown(p, lethal)
	else:
		best.apply_damage(9999.0 if lethal else 60.0, p, best.global_position + Vector3(0, 1.4, 0), fwd, {"type": "melee", "silent": true})
	Audio.play(&"knife_stab" if lethal else &"melee_hit", best.global_position, -10.0)
	Events.noise.emit(best.global_position, 2.5, &"impact", p)
	Events.crime.emit(&"assault" if not lethal else &"murder", best.global_position, {"victim": best, "silent": true})
	if Game.skills:
		Game.skills.add(&"stealth", 0.02)
	return true

# ---------------------------------------------------------------- skydiving
func ground_below(max_dist := 400.0) -> float:
	var from := p.global_position + Vector3(0, 0.5, 0)
	var hit := Game.ray(from, from - Vector3(0, max_dist, 0), Phys.WORLD | Phys.VEHICLE, [p.get_rid()])
	var ground_y := -1000.0
	if not hit.is_empty():
		ground_y = (hit["position"] as Vector3).y
	if Terrain.is_water(p.global_position.x, p.global_position.z):
		ground_y = maxf(ground_y, Terrain.SEA)
	return p.global_position.y - ground_y

func can_freefall() -> bool:
	return ground_below(60.0) > 14.0

func start_freefall() -> void:
	mode = Mode.FREEFALL
	p.state = Player.St.MOVE
	p.set_crouched(false)
	p.visual.upper = &""
	p.gunner.aiming = false
	_chute_yaw = p.face_yaw
	if p.parachute:
		Game.notify("Parachute ready - [Space] or [LMB] to deploy", "info")

func _deploy() -> void:
	mode = Mode.CHUTE
	p.parachute = false
	p.inventory.has_parachute = false
	_chute_yaw = p.face_yaw
	Audio.play(&"parachute_open", p.global_position, 0.0)
	_canopy = _make_canopy()
	p.visual.add_child(_canopy)
	_canopy.position = Vector3(0, 1.45, 0)
	p.velocity.y = maxf(p.velocity.y, -9.0)
	if Game.cam:
		Game.cam.shake(0.3)

func _make_canopy() -> Node3D:
	if Assets.has_model("weapons/parachute_canopy"):
		var c := Assets.instance("weapons/parachute_canopy")
		Assets.set_instance_param(c, &"tint_a", Color.html("ef7f2d").srgb_to_linear())
		Assets.set_instance_param(c, &"tint_b", Color.html("f2f0ea").srgb_to_linear())
		return c
	# generated stand-in canopy until the Blender asset is exported
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6.5, 0.25, 2.6)
	mi.mesh = bm
	mi.position = Vector3(0, 5.2, 0.4)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.94, 0.5, 0.18)
	mi.material_override = sm
	root.add_child(mi)
	return root

func _tick_air(delta: float) -> void:
	var blocked := Game.ui_blocked()
	agl = ground_below()
	var iv := Vector2.ZERO if blocked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if mode == Mode.FREEFALL:
		# terminal velocity ~52 m/s, a little steering by leaning
		p.velocity.y = maxf(p.velocity.y - Character.GRAVITY * delta, -52.0)
		var steer := Basis(Vector3.UP, p.camera_yaw()) * Vector3(iv.x, 0, iv.y) * 9.0
		p.velocity.x = move_toward(p.velocity.x, steer.x, delta * 6.0)
		p.velocity.z = move_toward(p.velocity.z, steer.z, delta * 6.0)
		p.set_face_yaw(lerp_angle(p.face_yaw, p.camera_yaw(), clampf(delta * 4.0, 0.0, 1.0)))
		p.visual.set_state(&"freefall")
		if p.parachute and not blocked and (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("fire")) and agl > 6.0:
			_deploy()
	else:
		# canopy flight: A/D turn, W dive for speed, S flare
		_chute_yaw -= iv.x * 1.25 * delta
		var fwd := Vector3(-sin(_chute_yaw), 0, -cos(_chute_yaw))
		var sink := -5.2
		var glide := 9.5
		if iv.y < -0.3:
			sink = -9.5
			glide = 14.0
		elif iv.y > 0.3:
			sink = -2.4
			glide = 5.0
		p.velocity.y = move_toward(p.velocity.y, sink, delta * 14.0)
		p.velocity.x = move_toward(p.velocity.x, fwd.x * glide, delta * 9.0)
		p.velocity.z = move_toward(p.velocity.z, fwd.z * glide, delta * 9.0)
		p.set_face_yaw(_chute_yaw)
		p.visual.set_state(&"parachute")
		p.visual.lean = lerpf(p.visual.lean, -iv.x * 0.35, clampf(delta * 5.0, 0.0, 1.0))
		if _canopy:
			_canopy.rotation.z = p.visual.lean * 0.6
	var impact_v := p.velocity
	p.move_and_slide()
	# --- touchdown
	p.update_water()
	if p.water_depth > 1.2:
		_finish_air()
		p._enter_swim()
		return
	if p.is_on_floor() or p.get_slide_collision_count() > 0 and impact_v.y < -1.0 and agl < 1.5:
		var hard := mode == Mode.FREEFALL
		var vs := -impact_v.y
		var hs := Vector2(impact_v.x, impact_v.z).length()
		_finish_air()
		if hard:
			p.apply_damage(maxf(0.0, (vs - 9.0) * 6.5), null, p.global_position, Vector3.ZERO, {"type": "fall"})
			if p.alive:
				p.knockdown(impact_v * 0.2, 2.0)
		elif vs > 7.5 or hs > 12.5:
			p.apply_damage((maxf(vs - 7.5, 0.0) + maxf(hs - 12.5, 0.0)) * 5.0, null, p.global_position, Vector3.ZERO, {"type": "fall"})
			if p.alive:
				p.knockdown(impact_v * 0.4, 1.6)
		else:
			Audio.play(&"land", p.global_position, -6.0)
			if Game.activities and Game.activities.has_method("on_parachute_landing"):
				Game.activities.on_parachute_landing(p.global_position)

func _finish_air() -> void:
	if _canopy != null and is_instance_valid(_canopy):
		_canopy.queue_free()
	_canopy = null
	p.visual.lean = 0.0
	mode = Mode.NONE
	if p.alive:
		p.state = Player.St.FOOT
