extends Node
## Parachute gear of the player (docs/PLAYER.md section 14) - presentation only, the flight physics
## live in PlayerStateFreefall / PlayerStateParachute:
##   * the pack (models/misc/parachute_pack.glb) on the back while Player.has_parachute;
##   * the canopy rig: models/misc/parachute_canopy.glb (origin = harness point at the shoulders,
##     canopy 4.6 m above, leading edge -Z) on a node at HARNESS_HEIGHT above the feet, inflating
##     over OPEN_TIME and banking / pitching with the steering and the flare;
##   * the canopy left behind after a landing / water landing / cut-away (collapses, then goes);
##   * audio: wind_fall_loop in freefall, parachute_open + parachute_loop under the canopy.
## One node under the player, one _process; nothing runs while the gear is idle.

const PACK_SCENE := "res://gta/generated/models/misc/parachute_pack.glb"
const CANOPY_SCENE := "res://gta/generated/models/misc/parachute_canopy.glb"
const HARNESS_HEIGHT := 1.42        ## canopy origin (harness = shoulders) above the player's feet
const PACK_UP := 0.12               ## pack origin above the Chest bone head (visual space)
const PACK_BACK := 0.115            ## pack origin behind the Chest bone head (the back surface, +Z)
const OPEN_TIME := 0.9              ## canopy inflation
const COLLAPSE_TIME := 1.8          ## a released canopy folds down onto the ground / water
const DROP_LINGER := 7.0            ## seconds a collapsed canopy stays before it is removed
const CANOPY_CENTER_Y := 4.75       ## manifest marker Canopy_Center above the harness
const FOLDED_SCALE_Y := 0.12        ## a collapsed canopy: lines + arc squashed to this
const ATTITUDE_RATE := 4.0          ## 1/s smoothing of bank / pitch
const WIND_DB_MIN := -30.0
const WIND_DB_MAX := -4.0
const FLAP_DB_MIN := -24.0
const FLAP_DB_MAX := -6.0

var player: Node3D = null
var pack: Node3D = null
var rig: Node3D = null              ## child of the player at the harness point (bank / pitch)
var canopy: Node3D = null           ## the canopy GLB under `rig`
var open_k: float = 0.0             ## 0 packed .. 1 fully inflated
var missing: PackedStringArray = [] ## asset paths that did not load (reported once)

var _pack_state: int = -1           ## last applied pack visibility (-1 unknown)
var _opening: bool = false
var _open_t: float = 0.0
var _bank: float = 0.0
var _pitch: float = 0.0
var _bank_target: float = 0.0
var _pitch_target: float = 0.0
var _drop: Node3D = null            ## released canopy (world space)
var _drop_kind: String = ""
var _drop_t: float = 0.0
var _drop_vel: Vector3 = Vector3.ZERO
var _drop_start: Transform3D = Transform3D.IDENTITY
var _drop_floor: float = 0.0
var _wind: AudioStreamPlayer = null
var _flap: AudioStreamPlayer = null
var _wind_level: float = 0.0
var _flap_level: float = 0.0
var _wind_target: float = 0.0
var _flap_target: float = 0.0


func setup(p: Node3D) -> void:
	player = p
	set_process(true)


func _exit_tree() -> void:
	for a: AudioStreamPlayer in [_wind, _flap]:
		if a != null and is_instance_valid(a):
			a.queue_free()
	_wind = null
	_flap = null
	if _drop != null and is_instance_valid(_drop):
		_drop.queue_free()
	_drop = null


# =================================================================================================
# pack
# =================================================================================================

## Shows / hides the pack on the back for Player.has_parachute (also polled every frame, so modules
## that set has_parachute directly are honoured).
func refresh_pack() -> void:
	var want: bool = player != null and is_instance_valid(player) and player.get("has_parachute") == true and not is_open()
	var st := 1 if want else 0
	if st == _pack_state and (not want or (pack != null and is_instance_valid(pack))):
		return
	if want and (pack == null or not is_instance_valid(pack)):
		_build_pack()
	if pack != null and is_instance_valid(pack):
		pack.visible = want
	_pack_state = st


func _build_pack() -> void:
	var vis: Variant = player.get("visual")
	if not (vis is Node3D) or not is_instance_valid(vis) or not (vis as Node3D).is_inside_tree():
		return
	var visual := vis as Node3D
	if not visual.has_method("get_bone_attachment") or not visual.has_method("get_skeleton"):
		return
	var scene := _load_scene(PACK_SCENE)
	if scene == null:
		return
	var att := visual.call("get_bone_attachment", "Chest") as Node3D
	var skel := visual.call("get_skeleton") as Skeleton3D
	if att == null or skel == null:
		return
	var idx := skel.find_bone("Chest")
	if idx < 0:
		return
	# the pack sits on the back surface behind the chest bone, upright in the visual's frame (the
	# character faces -Z, the pack's +Z points backwards): offset computed against the REST pose, so
	# it follows the chest when the spine bends
	var rest := skel.get_bone_global_rest(idx)
	var sk_rel := visual.global_transform.affine_inverse() * skel.global_transform
	var chest_v := sk_rel * rest.origin
	var want_v := Transform3D(Basis.IDENTITY, chest_v + Vector3(0.0, PACK_UP, PACK_BACK))
	pack = scene.instantiate() as Node3D
	if pack == null:
		return
	pack.name = "ParachutePack"
	att.add_child(pack)
	pack.transform = rest.affine_inverse() * sk_rel.affine_inverse() * want_v
	_shadow(pack, false)


# =================================================================================================
# canopy
# =================================================================================================

func is_open() -> bool:
	return rig != null and is_instance_valid(rig) and rig.visible


## Starts the inflation above the harness (PlayerStateParachute.enter). False when the asset is missing
## (the state still flies, the canopy is reported as missing - no stand-in geometry).
func open_canopy() -> bool:
	if not _ensure_canopy():
		refresh_pack()
		return false
	rig.visible = true
	_opening = true
	_open_t = 0.0
	open_k = 0.0
	_bank = 0.0
	_pitch = -0.35                   # the canopy snaps open from behind / below the pilot
	_bank_target = 0.0
	_pitch_target = 0.0
	_apply_inflation(0.0)
	_apply_attitude()
	refresh_pack()
	Audio.play("parachute_open", -2.0, randf_range(0.95, 1.05))
	return true


## Bank (rad, + = right side down / turning right) and pitch (rad, + = leading edge up / flare) the
## canopy should swing to (smoothed).
func set_attitude(bank: float, pitch: float) -> void:
	_bank_target = bank
	_pitch_target = pitch


## The pilot lets go of the canopy: "land" (folds down in front onto the ground), "water" (settles on
## the surface and sinks), "cut" (cut away in the air: flies off), "reset" (gone at once: respawn /
## teleport / death clean-up).
func release_canopy(kind: String, velocity: Vector3 = Vector3.ZERO) -> void:
	_opening = false
	open_k = 0.0
	if rig == null or not is_instance_valid(rig) or not rig.visible:
		refresh_pack()
		return
	if kind == "reset" or canopy == null or not is_instance_valid(canopy) or not rig.is_inside_tree():
		rig.visible = false
		refresh_pack()
		return
	# hand the canopy over to the world (a new one is instantiated for the next jump)
	if _drop != null and is_instance_valid(_drop):
		_drop.queue_free()
	var parent := Game.get_entities_root()
	if parent == null:
		parent = player.get_parent()
	var g := canopy.global_transform
	var holder := Node3D.new()
	holder.name = "DroppedCanopy"
	parent.add_child(holder)
	holder.global_transform = Transform3D(Basis(Vector3.UP, g.basis.get_euler().y), g.origin)
	canopy.reparent(holder, true)
	_drop = holder
	_drop_kind = kind
	_drop_t = 0.0
	_drop_vel = velocity
	_drop_start = canopy.transform
	var o := g.origin
	_drop_floor = o.y - HARNESS_HEIGHT
	if kind == "water":
		_drop_floor = float(player.get("water_surface_y")) if player.get("water_surface_y") != null else Game.WATER_LEVEL
	elif kind == "land" and Game.world != null:
		_drop_floor = maxf(_drop_floor, Game.ground_height(o.x, o.z))
	canopy = null
	rig.visible = false
	refresh_pack()


func _ensure_canopy() -> bool:
	if rig == null or not is_instance_valid(rig):
		rig = Node3D.new()
		rig.name = "CanopyRig"
		rig.position = Vector3(0.0, HARNESS_HEIGHT, 0.0)
		rig.visible = false
		player.add_child(rig)
	if canopy != null and is_instance_valid(canopy):
		return true
	var scene := _load_scene(CANOPY_SCENE)
	if scene == null:
		return false
	canopy = scene.instantiate() as Node3D
	if canopy == null:
		return false
	canopy.name = "Canopy"
	rig.add_child(canopy)
	return true


func _apply_inflation(k: float) -> void:
	if canopy == null or not is_instance_valid(canopy):
		return
	# span first narrow and short, the cells fill from the centre out (ease-out with a small overshoot)
	var e := 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)
	var over := sin(clampf(k, 0.0, 1.0) * PI) * 0.06
	var sx := lerpf(0.12, 1.0, e) + over
	var sy := lerpf(0.30, 1.0, minf(e * 1.25, 1.0))
	var sz := lerpf(0.45, 1.0, e)
	canopy.transform = Transform3D(Basis.from_scale(Vector3(sx, sy, sz)), Vector3.ZERO)


func _apply_attitude() -> void:
	if rig == null:
		return
	# roll about the flight direction (-Z): right side down for a right turn; pitch about +X: leading
	# edge up while flaring (the canopy swings back over the pilot)
	rig.transform = Transform3D(Basis(Vector3.BACK, -_bank) * Basis(Vector3.RIGHT, _pitch), Vector3(0.0, HARNESS_HEIGHT, 0.0))


# =================================================================================================
# audio
# =================================================================================================

## 0..1 wind roar of the freefall (by speed).
func set_wind(level: float) -> void:
	_wind_target = clampf(level, 0.0, 1.0)
	if _wind_target > 0.0 and _wind == null:
		_wind = Audio.make_loop_player_2d("wind_fall_loop", "SFX")
		if _wind != null:
			_wind.volume_db = WIND_DB_MIN
			_wind.play()


## 0..1 canopy flutter (by airspeed).
func set_flap(level: float) -> void:
	_flap_target = clampf(level, 0.0, 1.0)
	if _flap_target > 0.0 and _flap == null:
		_flap = Audio.make_loop_player_2d("parachute_loop", "SFX")
		if _flap != null:
			_flap.volume_db = FLAP_DB_MIN
			_flap.play()


func stop_audio() -> void:
	_wind_target = 0.0
	_flap_target = 0.0


func _update_audio(delta: float) -> void:
	var k := 1.0 - exp(-5.0 * delta)
	_wind_level = lerpf(_wind_level, _wind_target, k)
	_flap_level = lerpf(_flap_level, _flap_target, k)
	if _wind != null and is_instance_valid(_wind):
		if _wind_target <= 0.0 and _wind_level < 0.02:
			_wind.queue_free()
			_wind = null
		else:
			_wind.volume_db = lerpf(WIND_DB_MIN, WIND_DB_MAX, sqrt(_wind_level))
			_wind.pitch_scale = lerpf(0.85, 1.15, _wind_level)
	if _flap != null and is_instance_valid(_flap):
		if _flap_target <= 0.0 and _flap_level < 0.02:
			_flap.queue_free()
			_flap = null
		else:
			_flap.volume_db = lerpf(FLAP_DB_MIN, FLAP_DB_MAX, sqrt(_flap_level))
			_flap.pitch_scale = lerpf(0.9, 1.1, _flap_level)


# =================================================================================================
# frame
# =================================================================================================

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# pack follows Player.has_parachute (cheap bool compare unless it changed)
	var want := 1 if (player.get("has_parachute") == true and not is_open()) else 0
	if want != _pack_state:
		refresh_pack()
	if rig != null and is_instance_valid(rig) and rig.visible:
		if _opening:
			_open_t += delta
			open_k = clampf(_open_t / OPEN_TIME, 0.0, 1.0)
			_apply_inflation(open_k)
			if open_k >= 1.0:
				_opening = false
		var k := 1.0 - exp(-ATTITUDE_RATE * delta)
		_bank = lerpf(_bank, _bank_target, k)
		_pitch = lerpf(_pitch, _pitch_target, k)
		_apply_attitude()
	if _drop != null:
		_update_drop(delta)
	if _wind != null or _flap != null:
		_update_audio(delta)


func _update_drop(delta: float) -> void:
	if not is_instance_valid(_drop):
		_drop = null
		return
	_drop_t += delta
	var c := _drop.get_child(0) as Node3D if _drop.get_child_count() > 0 else null
	if c == null:
		_drop.queue_free()
		_drop = null
		return
	var t := clampf(_drop_t / COLLAPSE_TIME, 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)
	match _drop_kind:
		"cut":
			# cut away: carried off upwards / backwards, tumbling, then gone
			_drop_vel = _drop_vel.lerp(Vector3(0.0, 2.5, 0.0), 1.0 - exp(-0.8 * delta))
			_drop.global_position += _drop_vel * delta
			_drop.rotate_object_local(Vector3.RIGHT, -0.9 * delta)
			c.transform = Transform3D(Basis.from_scale(Vector3(lerpf(1.0, 0.55, e), lerpf(1.0, 0.6, e), 1.0)), Vector3.ZERO)
			if _drop_t > 5.0:
				_free_drop()
		_:
			# the canopy loses its pressure: the fabric sinks down in front of the pilot and lies
			# crumpled on the ground / water (lines and arc squashed, a slight forward slump)
			var drift := _drop_vel * (1.0 - e) * delta * 0.6
			_drop.global_position += Vector3(drift.x, 0.0, drift.z)
			var sy := lerpf(1.0, FOLDED_SCALE_Y, e)
			var target_y := (_drop_floor + 0.22) - _drop.global_position.y - CANOPY_CENTER_Y * FOLDED_SCALE_Y
			var y := lerpf(0.0, target_y, e)
			if _drop_kind == "water" and _drop_t > COLLAPSE_TIME:
				y -= (_drop_t - COLLAPSE_TIME) * 0.22          # soaks and sinks
			var fold := Basis(Vector3.RIGHT, -0.3 * e) * Basis.from_scale(Vector3(lerpf(1.0, 0.8, e), sy, lerpf(1.0, 0.95, e)))
			c.transform = Transform3D(fold, Vector3(0.0, y, lerpf(0.0, -2.6, e)))
			if _drop_t > COLLAPSE_TIME + DROP_LINGER:
				_free_drop()


func _free_drop() -> void:
	if _drop != null and is_instance_valid(_drop):
		_drop.queue_free()
	_drop = null


# =================================================================================================
# helpers
# =================================================================================================

func _load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		if not missing.has(path):
			missing.append(path)
			push_warning("Player parachute: asset missing (%s) - not shown" % path)
		return null
	var ps := load(path) as PackedScene
	if ps == null and not missing.has(path):
		missing.append(path)
		push_warning("Player parachute: asset does not load (%s)" % path)
	return ps


static func _shadow(n: Node, on: bool) -> void:
	for mi: Node in n.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
