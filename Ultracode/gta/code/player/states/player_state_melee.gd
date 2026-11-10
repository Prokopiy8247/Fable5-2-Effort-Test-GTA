class_name PlayerStateMelee
extends PlayerStateOnFoot
## Melee stance (spec 10A "Melee"). Entered from on_foot with fists or a melee weapon in hand when
## fire, melee_heavy or aim is pressed; left again after IDLE_EXIT seconds without fighting, when
## a firearm is drawn, or by sprinting / jumping / entering a vehicle.
##
##   light strike   fire -> WeaponInventory.trigger_pressed -> its 3-hit combo inside a 0.55 s
##                  window (fists: right, left, kick finisher x1.4 with a knock-down chance)
##   heavy strike   melee_heavy -> WeaponInventory.melee_attack(true): wind-up, x1.7-2.0 damage,
##                  knock-down chance + 0.3 (fists 85 %, bat 100 %)
##   soft lock-on   the nearest living NPC / animal inside LOCK_RANGE and a 140 deg cone around the
##                  stick (or camera) direction, hostiles preferred; the body turns to it and every
##                  swing lunges up to LUNGE_MAX towards it so the inventory's sweep connects
##   block          aim held: frontal melee damage x BLOCK_DAMAGE_MULT, no knock-down, costs stamina
##                  per blow (and drains slowly while held, no regeneration); out of stamina =
##                  guard break (full damage + stagger)
##   dodge step     block + jump + direction (PlayerStateRoll kind "step", melee blows miss)
##   finisher       fire / melee_heavy next to a locked target that is down: stomp (fists) or a
##                  heavy downward blow (weapon). The damage goes straight to that target: a knocked
##                  down NPC's body collider may be off, so a sweep could miss it.
## Strength skill: damage multiplier inside the inventory (x0.9 -> x1.35), XP per hit from
## Combat.melee_sweep, plus XP for finishers and blocked blows here.
##
## NPC contract read here (all optional): is_dead, faction, is_hostile_to(player) / hostile,
## is_knocked_down() / state_tag ("knocked_down", "down", "ragdoll") / meta "knocked_down",
## get_target_position(), apply_damage(info).

const LOCK_RANGE := 3.6
const LOCK_COS := 0.34                  ## cos(70 deg): half-cone of the lock search
const LOCK_SCAN := 0.1
const LOCK_GROUPS: Array[StringName] = [&"npc", &"animal"]
const LUNGE_SPEED := 4.4
const LUNGE_MAX := 1.2
const GUARD_SPEED := 2.2
const ATTACK_MOVE_SPEED := 0.8
const IDLE_EXIT := 0.7
const BLOCK_DAMAGE_MULT := 0.2
const BLOCK_ARC_COS := 0.2              ## blows from within ~78 deg of the facing are blockable
const BLOCK_STAMINA_PER_HP := 0.006
const BLOCK_STAMINA_MIN := 0.05
const BLOCK_DRAIN := 0.03               ## stamina / s while the guard is up
const FINISHER_RANGE := 2.4
const FINISHER_TIME := 0.62
const FINISHER_HIT := 0.5               ## fraction of FINISHER_TIME when the blow lands
const FINISHER_MIN_DAMAGE := 40.0
const DOWN_TAGS: PackedStringArray = ["knocked_down", "down", "ragdoll", "knockdown"]

var target: Node3D = null

var _scan_t: float = 0.0
var _idle_t: float = 0.0
var _swing_t: float = -1.0
var _swing_dur: float = 0.5
var _swing_heavy: bool = false
var _lunge_left: float = 0.0
var _lunge_dir: Vector3 = Vector3.FORWARD
var _fin_t: float = -1.0
var _fin_target: Node3D = null
var _fin_done: bool = false
var _trigger: bool = false
var _inv_connected: Node = null
var _delta: float = 0.0166


func _init() -> void:
	public_name = "melee"


func enter(previous: String, args: Dictionary) -> void:
	super.enter(previous, {})
	var p := player
	_connect_inventory()
	_scan_t = 0.0
	_idle_t = 0.0
	_swing_t = -1.0
	_fin_t = -1.0
	_lunge_left = 0.0
	_trigger = false
	target = _find_target()
	p.melee_target = target
	match str(args.get("press", "")):
		"fire":
			_press_fire()
		"heavy":
			_press_heavy()


func exit(next: String) -> void:
	var p := player
	p.is_blocking = false
	p.melee_target = null
	target = null
	if p.animator != null:
		p.animator.guard = 0.0
	if _trigger:
		_trigger = false
		_inv_call("trigger_released")
	super.exit(next)


func is_attacking() -> bool:
	return _swing_t >= 0.0 or _fin_t >= 0.0


# =================================================================================================
# on_foot hooks
# =================================================================================================

func _wants_other_state() -> bool:
	var p := player
	if not p.has_melee_weapon():
		p.change_state("on_foot", {})
		return true
	if is_attacking() or _inv_busy():
		return false
	var mv := p.get_move_input()
	if p.pressed("sprint") and mv.length() > 0.5 and not p.pressed("aim"):
		p.change_state("on_foot", {})
		return true
	if _idle_t > IDLE_EXIT and not p.pressed("aim") and not p.pressed("fire"):
		p.change_state("on_foot", {})
		return true
	return false


func _handle_combat(delta: float) -> bool:
	var p := player
	_delta = delta
	_connect_inventory()
	# lock-on
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = LOCK_SCAN
		target = _find_target()
		p.melee_target = target
	# swing / finisher timers
	if _swing_t >= 0.0:
		_swing_t += delta
		if _swing_t >= _swing_dur:
			_swing_t = -1.0
			_lunge_left = 0.0
	if _fin_t >= 0.0:
		_update_finisher(delta)
	var attacking := is_attacking() or _inv_busy()
	# block
	var aim_held := p.pressed("aim")
	p.is_blocking = aim_held and not attacking and p.stamina > 0.01
	p.set_aiming(aim_held)
	if p.is_blocking:
		p.stamina = maxf(p.stamina - BLOCK_DRAIN * delta, 0.0)
		p.hold_stamina_regen(0.6)
	# strikes
	if p.just_pressed("fire"):
		_press_fire()
	elif _trigger and not p.pressed("fire"):
		_trigger = false
		_inv_call("trigger_released")
	if p.just_pressed("melee_heavy"):
		_press_heavy()
	p.process_weapon_select_input(false)
	if attacking or p.is_blocking or _trigger:
		_idle_t = 0.0
	else:
		_idle_t += delta
	if p.animator != null:
		p.animator.guard = 1.0 if p.is_blocking else 0.0
	return true


func _sprint_allowed() -> bool:
	return false


func _target_speed(mag: float, _combat: bool) -> float:
	var p := player
	if _fin_t >= 0.0:
		return 0.0
	if is_attacking():
		return ATTACK_MOVE_SPEED
	var s := GUARD_SPEED
	if p.is_walk_held() or mag < Player.WALK_INPUT_THRESHOLD:
		s = minf(s, Player.WALK_SPEED)
	return s * lerpf(1.0, 0.45, _wading)


func _target_velocity(wish: Vector3, mag: float, max_speed: float) -> Vector3:
	var p := player
	# lunge: light swings close the gap at once, heavy ones after the wind-up
	if _swing_t >= 0.0 and _lunge_left > 0.0:
		var start := _swing_dur * (0.30 if _swing_heavy else 0.0)
		var stop := _swing_dur * (0.55 if _swing_heavy else 0.40)
		if _swing_t >= start and _swing_t <= stop:
			_lunge_left = maxf(_lunge_left - LUNGE_SPEED * _delta, 0.0)
			return _lunge_dir * LUNGE_SPEED
	if _fin_t >= 0.0 and _fin_target != null and is_instance_valid(_fin_target):
		var to := _fin_target.global_position - p.global_position
		to.y = 0.0
		if to.length() > 1.0 and _fin_t < FINISHER_TIME * FINISHER_HIT:
			return to.normalized() * 2.5
		return Vector3.ZERO
	return super._target_velocity(wish, mag, max_speed)


func _update_facing(delta: float, wish: Vector3, mag: float, _combat: bool) -> void:
	var p := player
	var face: Node3D = _fin_target if _fin_t >= 0.0 else target
	if face != null and is_instance_valid(face):
		var to := face.global_position - p.global_position
		if Vector2(to.x, to.z).length() > 0.15:
			p.turn_toward(atan2(-to.x, -to.z), Player.TURN_RATE_AIM * 1.4, delta)
			return
	if p.is_blocking or is_attacking() or mag <= 0.08:
		p.turn_toward(p.get_view_yaw(), Player.TURN_RATE_AIM, delta)
	else:
		p.turn_toward(atan2(-wish.x, -wish.z), Player.TURN_RATE, delta)


func _try_jump_actions(wish: Vector3, mag: float) -> bool:
	var p := player
	if (p.is_blocking or p.pressed("aim")) and mag > 0.3 and p.states.has("roll") and not is_attacking():
		p.change_state("roll", {"kind": "step", "dir": wish.normalized(), "resume": id})
		return true
	return super._try_jump_actions(wish, mag)


func _update_anim(speed: float) -> void:
	var p := player
	if p.is_crouching:
		p.set_anim_state("crouch")
	elif speed > 0.15 or p.is_blocking or is_attacking() or _idle_t < IDLE_EXIT:
		p.set_anim_state("melee")
	else:
		p.set_anim_state("idle")


# =================================================================================================
# damage hooks: block
# =================================================================================================

func modify_damage(info: Dictionary, amount: float) -> float:
	var p := player
	var type := str(info.get("type", ""))
	if not p.is_blocking or (type != "melee" and type != "bite"):
		return amount
	var from := Vector3.ZERO
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	if dir.length_squared() > 0.0001:
		from = -dir
	else:
		var pos: Vector3 = info.get("position", Vector3.ZERO)
		from = pos - p.global_position
	from.y = 0.0
	if from.length_squared() < 0.0001:
		return amount
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	if from.normalized().dot(fwd.normalized()) < BLOCK_ARC_COS:
		return amount                      # from the side / behind: the guard does not help
	var heavy := bool(info.get("heavy", false))
	var cost := maxf(amount * BLOCK_STAMINA_PER_HP, BLOCK_STAMINA_MIN) * (1.6 if heavy else 1.0)
	if p.stamina < cost:
		# guard break: the blow lands in full and staggers
		p.stamina = 0.0
		p.is_blocking = false
		info["guard_broken"] = true
		Audio.play_at("punch_hit", p.get_target_position(), -2.0, 0.8, 25.0)
		return amount
	p.stamina -= cost
	p.hold_stamina_regen(1.2)
	info["blocked"] = true
	info["knockdown"] = false
	info["no_ragdoll"] = true
	Skills.add_xp("strength", 0.03)
	Audio.play_at("melee_hit", p.get_target_position(), -6.0, 1.35, 25.0)
	return amount * BLOCK_DAMAGE_MULT


func on_damage(info: Dictionary, _amount: float) -> void:
	var p := player
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = p.global_basis.z
	dir = dir.normalized()
	if bool(info.get("guard_broken", false)):
		stagger(dir * 2.6, 0.6)
	elif bool(info.get("blocked", false)) and bool(info.get("heavy", false)):
		stagger(dir * 1.2, 0.18)


# =================================================================================================
# strikes
# =================================================================================================

func _press_fire() -> void:
	if _fin_t >= 0.0:
		return
	var down := _downed_target_in_reach()
	if down != null:
		_start_finisher(down)
		return
	_trigger = true
	if not _inv_call("trigger_pressed"):
		_on_melee_started("", false, 1)       # no inventory: still swing (animation only)
		player.play_action("punch_r")


func _press_heavy() -> void:
	if _fin_t >= 0.0:
		return
	var down := _downed_target_in_reach()
	if down != null:
		_start_finisher(down)
		return
	var inv := player.inventory
	if inv != null and is_instance_valid(inv) and inv.has_method("melee_attack"):
		inv.call("melee_attack", true)
	else:
		_on_melee_started("", true, 1)
		player.play_action("heavy")


## WeaponInventory.melee_started: a light / heavy swing really started.
func _on_melee_started(_weapon_id: String, heavy: bool, _combo_step: int) -> void:
	var p := player
	if p == null or p.state != self:
		return
	var rpm := 95.0
	var reach := 1.5
	var spec := _current_spec()
	if spec != null:
		if bool(spec.call("is_melee")):
			rpm = float(spec.get("rpm"))
			reach = float(spec.get("melee_range"))
	_swing_dur = 60.0 / maxf(rpm, 1.0) * (1.7 if heavy else 1.0)
	_swing_t = 0.0
	_swing_heavy = heavy
	_idle_t = 0.0
	p.is_blocking = false
	if target != null and is_instance_valid(target):
		var to := target.global_position - p.global_position
		to.y = 0.0
		var d := to.length()
		_lunge_dir = to / d if d > 0.01 else -p.global_basis.z
		_lunge_left = clampf(d - reach * 0.7, 0.0, LUNGE_MAX)
	else:
		_lunge_dir = -p.global_basis.z
		_lunge_dir.y = 0.0
		_lunge_dir = _lunge_dir.normalized()
		_lunge_left = 0.25


func _start_finisher(t: Node3D) -> void:
	var p := player
	_fin_t = 0.0
	_fin_target = t
	_fin_done = false
	_idle_t = 0.0
	p.is_blocking = false
	if _trigger:
		_trigger = false
		_inv_call("trigger_released")
	var spec := _current_spec()
	var weapon: bool = spec != null and str(spec.get("id")) != "fists"
	p.play_weapon_action("heavy" if weapon else "stomp", FINISHER_TIME)
	Audio.play_at("melee_swing", p.get_target_position(), -5.0, 0.8, 25.0)


func _update_finisher(delta: float) -> void:
	_fin_t += delta
	if not _fin_done and _fin_t >= FINISHER_TIME * FINISHER_HIT:
		_fin_done = true
		_apply_finisher()
	if _fin_t >= FINISHER_TIME:
		_fin_t = -1.0
		_fin_target = null


func _apply_finisher() -> void:
	var p := player
	var t := _fin_target
	if t == null or not is_instance_valid(t) or not t.has_method("apply_damage") or t.get("is_dead") == true:
		return
	var pos := _aim_point_of(t)
	var flat := pos - p.global_position
	flat.y = 0.0
	if flat.length() > FINISHER_RANGE + 0.4:
		return                             # it rolled away: a whiff
	var spec := _current_spec()
	var dmg := FINISHER_MIN_DAMAGE
	var wid := "fists"
	var sound := "punch_hit"
	if spec != null:
		wid = str(spec.get("id"))
		dmg = maxf(float(spec.get("damage")) * float(spec.get("melee_heavy_mult")) * 1.6, FINISHER_MIN_DAMAGE)
		var sh: Variant = spec.get("melee_sound_hit")
		if sh is String and sh != "":
			sound = sh
	dmg *= Skills.get_multiplier("strength", 0.9, 1.35)
	var dir := (pos - (p.global_position + Vector3(0.0, 1.2, 0.0))).normalized()
	var info := Dmg.make(dmg, "melee", p, pos, dir, {"weapon_id": wid, "finisher": true, "heavy": true,
			"zone": "torso", "impulse": 2.0, "knockdown": false})
	var was_dead: bool = t.get("is_dead") == true
	t.call("apply_damage", info)
	info["killed"] = (not was_dead) and is_instance_valid(t) and t.get("is_dead") == true
	EventBus.hit_confirmed.emit(t if is_instance_valid(t) else null, info)
	Skills.add_xp("strength", 0.25)
	Fx.impact(pos, Vector3.UP, "flesh", 1.0)
	Audio.play_at(sound, pos, 0.0, 0.85, 30.0)
	p.emit_noise(8.0, "melee")
	p.shake_camera(0.12)


# =================================================================================================
# targets
# =================================================================================================

func _find_target() -> Node3D:
	var p := player
	if not p.is_inside_tree():
		return null
	var origin := p.global_position
	var fwd := Vector3.ZERO
	var mv := p.get_move_input()
	if mv.length() > 0.3:
		fwd = p.get_wish_dir(mv)
	else:
		var yaw := p.get_view_yaw()
		fwd = Vector3(-sin(yaw), 0.0, -cos(yaw))
	fwd.y = 0.0
	fwd = fwd.normalized()
	var best: Node3D = null
	var best_score := INF
	var tree := p.get_tree()
	for g: StringName in LOCK_GROUPS:
		for n: Node in tree.get_nodes_in_group(g):
			var n3 := n as Node3D
			if n3 == null or n3 == p or not n3.is_inside_tree() or n3.get("is_dead") == true:
				continue
			var to := n3.global_position - origin
			if absf(to.y) > 2.0:
				continue
			to.y = 0.0
			var d := to.length()
			if d > LOCK_RANGE or d < 0.05:
				continue
			var c := to.dot(fwd) / d
			if c < LOCK_COS:
				continue
			var score := d * (1.6 - c)
			if _is_hostile(n3):
				score -= 1.0
			if n3 == target:
				score -= 0.6                   # sticky: no flicker between two close targets
			if score < best_score:
				best_score = score
				best = n3
	return best


func _downed_target_in_reach() -> Node3D:
	var p := player
	var t := target
	if t == null or not is_instance_valid(t) or not _is_down(t):
		# the lock search skips nobody that is down, but the stick may point elsewhere: look around
		t = null
		for g: StringName in LOCK_GROUPS:
			for n: Node in p.get_tree().get_nodes_in_group(g):
				var n3 := n as Node3D
				if n3 != null and n3.is_inside_tree() and n3.get("is_dead") != true and _is_down(n3):
					var dd := n3.global_position - p.global_position
					dd.y = 0.0
					if dd.length() <= FINISHER_RANGE:
						t = n3
						break
			if t != null:
				break
	if t == null:
		return null
	var d := t.global_position - p.global_position
	d.y = 0.0
	return t if d.length() <= FINISHER_RANGE else null


static func _is_down(n: Node) -> bool:
	if n.has_method("is_knocked_down"):
		return bool(n.call("is_knocked_down"))
	# typed reads: NpcBase also has a SIGNAL named knocked_down (comparing a Signal with a bool is a
	# script error), and its knocked-down flag is is_down
	for prop: StringName in [&"is_knocked_down", &"knocked_down", &"is_down"]:
		var v: Variant = n.get(prop)
		if v is bool and v:
			return true
	var tag: Variant = n.get("state_tag")
	if tag is String and DOWN_TAGS.has(tag):
		return true
	return n.has_meta("knocked_down") and bool(n.get_meta("knocked_down"))


func _is_hostile(n: Node) -> bool:
	if n.has_method("is_hostile_to"):
		return bool(n.call("is_hostile_to", player))
	if n.get("hostile") == true:
		return true
	if n.has_meta("hostile") and bool(n.get_meta("hostile")):
		return true
	return n.get("faction") == "police" and Wanted.level > 0


static func _aim_point_of(n: Node3D) -> Vector3:
	if n.has_method("get_target_position"):
		var v: Variant = n.call("get_target_position")
		if v is Vector3:
			return v
	return n.global_position + Vector3(0.0, 0.3, 0.0)


# =================================================================================================
# inventory glue
# =================================================================================================

func _connect_inventory() -> void:
	var inv := player.inventory
	if inv == _inv_connected:
		return
	if _inv_connected != null and is_instance_valid(_inv_connected) and _inv_connected.is_connected("melee_started", _on_melee_started):
		_inv_connected.disconnect("melee_started", _on_melee_started)
	_inv_connected = inv
	if inv != null and is_instance_valid(inv) and inv.has_signal("melee_started"):
		inv.connect("melee_started", _on_melee_started)


func _inv_call(method: String) -> bool:
	var inv := player.inventory
	if inv == null or not is_instance_valid(inv) or not inv.has_method(method):
		return false
	inv.call(method)
	return true


func _inv_busy() -> bool:
	var inv := player.inventory
	return inv != null and is_instance_valid(inv) and inv.has_method("is_busy") and bool(inv.call("is_busy"))


func _current_spec() -> Object:
	var inv := player.inventory
	if inv == null or not is_instance_valid(inv) or not inv.has_method("get_current_spec"):
		return null
	var s: Variant = inv.call("get_current_spec")
	return s as Object if s is Object else null
