class_name AnimalFishSchool
extends Node3D
## A school of small reef fish = ONE node with ONE MultiMeshInstance3D (one draw call).
##
## The fish GLB parts are merged into a single vertex-coloured mesh (AnimalAssets.merged_mesh); the
## tail undulation is done in the vertex shader (travelling sine wave towards the tail, per-fish
## phase / beat rate in INSTANCE_CUSTOM). The school centre wanders around its anchor (a reef point
## or the wreck) between the seabed and the surface; every fish keeps a personal offset that
## breathes over time. A diver coming close or a loud noise makes the school burst away and spread;
## an explosion close by kills some fish (belly up, they drift to the surface, then vanish).
## Group "animal_school" (not "animal": melee lock-on / vehicle code expect bodies there); counts as ONE
## animal in the wildlife caps. No collider (fish cannot be shot).

const SHADER_CODE := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

global uniform float gta_time;
uniform float amp = 0.035;
uniform float wave_k = 13.0;
uniform float tail_start = -0.03;
uniform float tail_end = 0.2;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float beat = 5.0 + INSTANCE_CUSTOM.y * 9.0;
	float alive = INSTANCE_CUSTOM.z;
	float w = smoothstep(tail_start, tail_end, VERTEX.z);
	float tt = gta_time * beat + phase;
	VERTEX.x += sin(tt - VERTEX.z * wave_k) * amp * w * alive;
	VERTEX.x -= sin(tt) * amp * 0.18 * (1.0 - w) * alive;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.5;
	SPECULAR = 0.45;
}
"""

const SURFACE_MARGIN := 1.0
const SEABED_MARGIN := 0.9

static var _material: ShaderMaterial = null

var species := "fish_small"
var kind := "fish"
var category := "water"
var is_dead := false
var persistent := false
var system: Node = null
var anchor := Vector3.ZERO
var roam_radius := 14.0
var count := 0
var alive_count := 0
var sim_tier := 0
var think_accum := 0.0
var centre := Vector3.ZERO
var vel := Vector3.ZERO
var speed := 0.9
var burst_t := 0.0
var spread := 1.0
var waypoint := Vector3.INF
var habitat := "reef"

var _mmi: MultiMeshInstance3D = null
var _mm: MultiMesh = null
var _offsets := PackedVector3Array()
var _freq := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _dead_t := PackedFloat32Array()      ## < 0 alive, else seconds since death
var _dead_pos := PackedVector3Array()
var _t := 0.0
var _swim := 0.9
var _burst := 3.0
var _corpse_time := 20.0
var _accum := 0.0


static func clear_static() -> void:
	_material = null


static func _get_material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = sh
	return _material


## Builds the school (n fish) around `pos`. Returns false when the fish model is missing.
func setup_school(def: Dictionary, sys: Node, pos: Vector3, n: int, opts: Dictionary = {}) -> bool:
	system = sys
	name = "FishSchool"
	add_to_group("animal_school")     # not "animal": other modules treat that group as bodies with colliders
	var mesh := AnimalAssets.merged_mesh(species)
	if mesh == null:
		return false
	_swim = float(def.get("swim_speed", 0.9))
	_burst = float(def.get("burst_speed", 3.0))
	_corpse_time = float(def.get("corpse_time", 20.0))
	if sys != null and sys.get("corpse_time_mult") != null:
		_corpse_time *= float(sys.get("corpse_time_mult"))
	persistent = bool(opts.get("persistent", false))
	roam_radius = float(opts.get("radius", 14.0))
	count = clampi(n, 1, 32)
	alive_count = count
	anchor = pos
	centre = pos
	speed = _swim
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = count
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Fish"
	_mmi.multimesh = _mm
	_mmi.material_override = _get_material()
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.visibility_range_end = 75.0
	_mmi.visibility_range_end_margin = 6.0
	_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_mmi)
	_offsets.resize(count)
	_freq.resize(count)
	_phase.resize(count)
	_scale.resize(count)
	_dead_t.resize(count)
	_dead_pos.resize(count)
	for i in count:
		var o := Vector3(randf_range(-1.0, 1.0), randf_range(-0.45, 0.45), randf_range(-1.0, 1.0))
		_offsets[i] = o * Vector3(1.5, 0.8, 2.0)
		_freq[i] = randf_range(0.6, 1.6)
		_phase[i] = randf()
		_scale[i] = randf_range(0.8, 1.2)
		_dead_t[i] = -1.0
		_mm.set_instance_custom_data(i, Color(_phase[i], 0.2, 1.0, 0.0))
	var ang := randf() * TAU
	vel = Vector3(cos(ang), 0.0, sin(ang)) * _swim
	_clamp_centre()
	_write(0.0)
	return true


func get_count() -> int:
	return alive_count


func set_sim_tier(t: int) -> void:
	sim_tier = t


func _water_band(x: float, z: float) -> Vector2:
	var depth := 2.0
	if Game.world != null and is_instance_valid(Game.world) and Game.world.has_method("get_water_depth"):
		depth = Game.world.get_water_depth(x, z)
	var top := Game.WATER_LEVEL - SURFACE_MARGIN
	var bottom := Game.WATER_LEVEL - depth + SEABED_MARGIN
	return Vector2(bottom, top)


func _clamp_centre() -> void:
	var band := _water_band(centre.x, centre.z)
	if band.x > band.y:
		centre.y = (band.x + band.y) * 0.5
	else:
		centre.y = clampf(centre.y, band.x + 0.4, band.y - 0.4)


## Per-frame update from the wildlife system (dt already accumulated for far tiers).
func tick(dt: float) -> void:
	_t += dt
	if burst_t > 0.0:
		burst_t -= dt
	spread = lerpf(spread, 1.7 if burst_t > 0.0 else 1.0, minf(dt * 2.0, 1.0))
	# --- diver close by: scatter ----------------------------------------------------------
	if Game.has_player() and burst_t <= 0.0:
		var pp := Game.get_player_position()
		if pp.distance_to(centre) < 4.5 and (Game.player.get("is_underwater") == true or Game.player.get("is_swimming") == true):
			scatter(pp)
	# --- steer the centre ------------------------------------------------------------------
	if waypoint == Vector3.INF or centre.distance_to(waypoint) < 2.0:
		waypoint = _pick_waypoint()
	var want := (waypoint - centre)
	var sp := _burst if burst_t > 0.0 else _swim
	if want.length() > 0.01:
		want = want.normalized() * sp
	vel = vel.lerp(want, minf(dt * (1.6 if burst_t > 0.0 else 0.6), 1.0))
	var np := centre + vel * dt
	var band := _water_band(np.x, np.z)
	if band.y - band.x < 0.6:
		# too shallow ahead: turn back towards the anchor
		vel = vel.lerp((anchor - centre).normalized() * sp, minf(dt * 3.0, 1.0))
		waypoint = anchor
		np = centre + vel * dt
	centre = np
	_clamp_centre()
	speed = vel.length()
	_write(dt)


func _pick_waypoint() -> Vector3:
	for i in 8:
		var ang := randf() * TAU
		var r := sqrt(randf()) * roam_radius
		var p := anchor + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var band := _water_band(p.x, p.z)
		if band.y - band.x >= 0.8:
			# reef fish keep close to the bottom (1-3.5 m above the seabed)
			p.y = clampf(band.x + randf_range(0.2, 2.6), band.x, band.y)
			return p
	return anchor


## Burst away from `from` (diver, gunshot, explosion).
func scatter(from: Vector3) -> void:
	var away := centre - from
	if away.length() < 0.1:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	away.y *= 0.3
	waypoint = centre + away.normalized() * 10.0
	var band := _water_band(waypoint.x, waypoint.z)
	waypoint.y = clampf(waypoint.y, band.x, maxf(band.x, band.y))
	burst_t = 2.6


func on_noise(pos: Vector3, radius: float, noise_kind: String) -> void:
	var d := pos.distance_to(centre)
	if noise_kind == "explosion" and d < minf(radius * 0.12, 12.0):
		_kill_near(pos, minf(radius * 0.12, 12.0))
	if noise_kind in ["gunshot", "explosion", "suppressed_gunshot", "crash"] and d < radius * 0.5:
		scatter(pos)


func _kill_near(pos: Vector3, r: float) -> void:
	var sb := _school_basis()
	for i in count:
		if _dead_t[i] >= 0.0:
			continue
		var p := centre + sb * (_offsets[i] * spread)
		if p.distance_to(pos) < r * randf_range(0.6, 1.0):
			_dead_t[i] = 0.0
			_dead_pos[i] = p
			alive_count -= 1
			_mm.set_instance_custom_data(i, Color(_phase[i], 0.0, 0.0, 0.0))
	if alive_count <= 0:
		is_dead = true


func _school_basis() -> Basis:
	var f := Vector3(vel.x, 0.0, vel.z)
	if f.length() < 0.05:
		return Basis.IDENTITY
	return Basis(Vector3.UP, atan2(-f.x, -f.z))


func is_finished() -> bool:
	if alive_count > 0:
		return false
	for i in count:
		if _dead_t[i] >= 0.0 and _dead_t[i] < _corpse_time:
			return false
	return true


func _write(dt: float) -> void:
	if _mm == null:
		return
	if is_inside_tree():
		global_position = centre
	else:
		position = centre
	var sb := _school_basis()
	var cband := _water_band(centre.x, centre.z)     # one seabed query per school, not per fish
	var heading := atan2(-vel.x, -vel.z) if Vector2(vel.x, vel.z).length() > 0.02 else 0.0
	var sp_norm := clampf(speed / maxf(_burst, 0.1), 0.0, 1.0)
	for i in count:
		var s := _scale[i]
		if _dead_t[i] >= 0.0:
			_dead_t[i] += dt
			var dp := _dead_pos[i]
			var top := Game.WATER_LEVEL - 0.12
			dp.y = minf(dp.y + dt * 0.45, top)
			_dead_pos[i] = dp
			var sc := s if _dead_t[i] < _corpse_time else 0.0
			var bd := Basis(Vector3.UP, _phase[i] * TAU) * Basis(Vector3.BACK, PI)
			_mm.set_instance_transform(i, Transform3D(bd.scaled(Vector3.ONE * sc), dp - centre))
			continue
		var w := _t * _freq[i]
		var o := _offsets[i] * spread + Vector3(sin(w + _phase[i] * 6.0) * 0.3, sin(w * 0.7 + _phase[i]) * 0.12,
				cos(w * 0.8 + _phase[i] * 4.0) * 0.3)
		var p := centre + sb * o
		p.y = clampf(p.y, cband.x - 0.5, Game.WATER_LEVEL - 0.35)
		var yaw := heading + sin(w * 1.3 + _phase[i] * 9.0) * 0.22
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, sin(w + _phase[i]) * 0.08)
		_mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * s), p - centre))
		if burst_t > 0.0 or i % 4 == int(_t * 4.0) % 4:
			_mm.set_instance_custom_data(i, Color(_phase[i], clampf(sp_norm * 0.7 + _freq[i] * 0.2, 0.0, 1.0), 1.0, 0.0))


## Fish positions (alive fish only) - tests / debug.
func get_fish_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	if _mm == null:
		return out
	for i in count:
		if _dead_t[i] < 0.0:
			out.append(centre + _mm.get_instance_transform(i).origin)
	return out
