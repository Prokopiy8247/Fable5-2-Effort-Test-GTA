extends Node
## Autoload "Fx": pooled visual effects, decals, tracers, fire and explosions (visuals + damage).
##
## Style: "Sunlit Low-Poly" - chunky faceted mesh particles (blobs, chips, shards, sparks) that
## pop in and SHRINK out (no alpha fog, no overdraw), plus a few soft additive sprites for flashes.
## Everything is procedural (see fx_assets.gd) and comes from bounded pools created once at boot:
## nothing is allocated per shot. See docs/FX.md for the API, the pool sizes and the GPU budget.
##
## Every public method is safe in --headless runs, before Game.is_ready, with freed / null
## arguments and when the pools are exhausted (the oldest effect is recycled).

signal camera_shake_requested(amount: float)   ## the player camera rig connects to this

const SURFACES: Array[String] = ["concrete", "asphalt", "metal", "glass", "wood", "dirt", "grass",
		"sand", "water", "flesh", "rubber", "foliage"]

const FxAssets := preload("res://gta/code/combat/fx_assets.gd")
const FxHandle := preload("res://gta/code/combat/fx_handle.gd")
const FxBlast := preload("res://gta/code/combat/fx_blast.gd")

# --- budgets (docs/ARCHITECTURE.md section 10: particle systems <= 48, decals <= 64) -------------
const MAX_ACTIVE_SYSTEMS := 48
const MAX_DECALS := 64
const MAX_FIRES := 6
const MAX_LIT_FIRES := 3
const MAX_EXPLOSION_LIGHTS := 2
const EXPLOSION_SLOTS := 4
const TRACER_POOL := 12
const MUZZLE_POOL := 6
const SHELL_POOL := 12
const RING_POOL := 6
const MAX_IMPACTS_PER_FRAME := 8
const MAX_PENDING_EXPLOSIONS := 16

const FIRE_TICK := 0.5
const FIRE_MASK := Layers.PLAYER | Layers.NPC | Layers.VEHICLE | Layers.PROP
const TRACER_SPEED := 300.0
const MUZZLE_TIME := 0.055
const FLASH_TIME := 0.2
const RING_TIME := 0.42
const LIGHT_TIME := 0.5
const SHELL_TIME := 0.8
const WATER_RING_TIME := 0.9
const PUFF_RATE := 14.0       ## repeated-call puffs (tyre smoke, dust, rotor wash) per second
const PUFF_BURST := 4.0

const SMOKE_KINDS: Array[String] = ["light", "heavy", "black"]
const TRAIL_KINDS: Array[String] = ["rocket", "tyre", "wake", "dust", "exhaust"]
const DECAL_KINDS: Array[String] = ["bullet", "scorch", "blood", "skid", "oil"]

# --- palette --------------------------------------------------------------------------------------
const C_CONCRETE_DUST := Color(0.76, 0.74, 0.7)
const C_CONCRETE_CHIP := Color(0.6, 0.59, 0.56)
const C_ASPHALT_DUST := Color(0.5, 0.5, 0.5)
const C_ASPHALT_CHIP := Color(0.2, 0.2, 0.22)
const C_WOOD_DUST := Color(0.74, 0.62, 0.44)
const C_WOOD_CHIP := Color(0.8, 0.62, 0.38)
const C_DIRT_DUST := Color(0.52, 0.4, 0.28)
const C_DIRT_CHIP := Color(0.36, 0.27, 0.18)
const C_GRASS_DUST := Color(0.5, 0.46, 0.3)
const C_GRASS_CHIP := Color(0.36, 0.62, 0.25)
const C_SAND_DUST := Color(0.92, 0.84, 0.62)
const C_SAND_CHIP := Color(0.86, 0.77, 0.55)
const C_LEAF := Color(0.3, 0.56, 0.22)
const C_GLASS := Color(0.74, 0.93, 0.96)
const C_METAL_DUST := Color(0.55, 0.56, 0.6)
const C_RUBBER := Color(0.11, 0.11, 0.12)
const C_BLOOD := Color(0.7, 0.07, 0.08)
const C_BLOOD_DARK := Color(0.48, 0.04, 0.05)
const C_SPARK := Color(1.0, 0.78, 0.32)
const C_WATER := Color(0.86, 0.95, 1.0)
const C_FOAM := Color(0.95, 0.98, 1.0)
const C_SMOKE_LIGHT := Color(0.8, 0.8, 0.8)
const C_SMOKE_HEAVY := Color(0.36, 0.36, 0.38)
const C_SMOKE_BLACK := Color(0.13, 0.13, 0.14)
const C_STEAM := Color(0.95, 0.97, 1.0)
const C_TYRE_SMOKE := Color(0.88, 0.88, 0.88)
const C_DUST := Color(0.74, 0.67, 0.55)
const C_DEBRIS := Color(0.17, 0.15, 0.14)
const C_BRASS := Color(0.86, 0.66, 0.26)
const C_MONEY := Color(0.38, 0.76, 0.42)
const C_GOLD := Color(1.0, 0.84, 0.35)
const C_FLASH := Color(1.0, 0.7, 0.3, 1.0)
const C_FIRE_LIGHT := Color(1.0, 0.56, 0.2)


class BurstDef:
	var first: int = 0
	var count: int = 0
	var next: int = 0
	var life: float = 1.0
	var amount: int = 8


## A pool of looping emitters that share one process material (assigned once, at creation).
class LoopPool:
	var first: int = 0
	var count: int = 0
	var amount: int = 20
	var life: float = 1.0


## One look that runs on a LoopPool (mesh, tint, density, size).
class LoopDef:
	var pool: LoopPool
	var mesh: Mesh
	var mat: Material
	var ratio: float = 1.0
	var size: float = 1.0
	var offset: Vector3 = Vector3.ZERO


var quality: int = 2                 ## 0 low, 1 medium, 2 high (set_quality)

var _built: bool = false
var _assets: FxAssets = null
var _blast: FxBlast = null
var _root: Node3D = null
var _audio: Node = null
var _now: float = 0.0
var _busy: bool = false
var _busy_until: float = 0.0
var _serial: int = 0

# particle emitters (bursts first, then the generic loop emitters)
var _em: Array[GPUParticles3D] = []
var _em_until: PackedFloat64Array = PackedFloat64Array()
var _em_order: PackedInt64Array = PackedInt64Array()
var _em_live: PackedFloat32Array = PackedFloat32Array()
var _em_is_loop: PackedByteArray = PackedByteArray()
var _em_owner: Array = []             # loop emitters: the handle that holds it (or null)
var _bursts: Dictionary = {}          # StringName -> BurstDef
var _loops: Dictionary = {}           # String -> LoopDef
var _loop_first: int = 0

# handles (fire / smoke / trail)
var _handles: Array[Node3D] = []
var _fires: Array[Node3D] = []
var _fire_lights: Array[OmniLight3D] = []
var _fire_light_owner: Array = []
var _fire_audio: Array = []           # pooled looping "fire_loop" players (built on the first fire)
var _fire_audio_owner: Array = []
var _fire_audio_built: bool = false
var _fire_shape := SphereShape3D.new()
var _fire_query := PhysicsShapeQueryParameters3D.new()

# explosions
var _ex_flash: Array[MeshInstance3D] = []
var _ex_ring: Array[MeshInstance3D] = []
var _ex_t0: PackedFloat64Array = PackedFloat64Array()
var _ex_size: PackedFloat32Array = PackedFloat32Array()
var _ex_ring_r: PackedFloat32Array = PackedFloat32Array()
var _ex_next: int = 0
var _ex_lights: Array[OmniLight3D] = []
var _exl_t0: PackedFloat64Array = PackedFloat64Array()
var _exl_energy: PackedFloat32Array = PackedFloat32Array()
var _exl_next: int = 0
var _blast_depth: int = 0
var _pending_explosions: Array = []

# muzzle flashes
var _mz_star: Array[MeshInstance3D] = []
var _mz_glow: Array[MeshInstance3D] = []
var _mz_ref: Array = []
var _mz_until: PackedFloat64Array = PackedFloat64Array()
var _mz_roll: PackedFloat32Array = PackedFloat32Array()
var _mz_scale: PackedFloat32Array = PackedFloat32Array()
var _mz_next: int = 0
var _mz_light: OmniLight3D = null
var _mz_light_until: float = 0.0

# tracers
var _tr: Array[MeshInstance3D] = []
var _tr_from: PackedVector3Array = PackedVector3Array()
var _tr_dir: PackedVector3Array = PackedVector3Array()
var _tr_dist: PackedFloat32Array = PackedFloat32Array()
var _tr_len: PackedFloat32Array = PackedFloat32Array()
var _tr_speed: PackedFloat32Array = PackedFloat32Array()
var _tr_t0: PackedFloat64Array = PackedFloat64Array()
var _tr_next: int = 0

# shell casings
var _sh: Array[MeshInstance3D] = []
var _sh_pos: PackedVector3Array = PackedVector3Array()
var _sh_vel: PackedVector3Array = PackedVector3Array()
var _sh_axis: PackedVector3Array = PackedVector3Array()
var _sh_t0: PackedFloat64Array = PackedFloat64Array()
var _sh_next: int = 0

# water rings
var _wr: Array[MeshInstance3D] = []
var _wr_t0: PackedFloat64Array = PackedFloat64Array()
var _wr_scale: PackedFloat32Array = PackedFloat32Array()
var _wr_next: int = 0

# decals
var _decals: Array[Decal] = []
var _decal_next: int = 0
var _decal_cap: int = MAX_DECALS
var _decals_placed: int = 0

# throttles / quality
var _frame_impacts: int = 0
var _puff_tokens: float = PUFF_BURST
var _last_impact_audio: float = -1.0
var _last_splash_audio: float = -1.0
var _amount_scale: float = 1.0
var _fx_range: float = 160.0
var _lights_on: bool = true
var _muzzle_light_on: bool = true


func _ready() -> void:
	_build()
	if not EventBus.game_ready.is_connected(_on_game_ready):
		EventBus.game_ready.connect(_on_game_ready)
	var q: Variant = Settings.get_value("fx_quality")
	if q != null:
		set_quality(int(q))


func _on_game_ready() -> void:
	# build the decal images while the boot is still settling instead of on the first shot
	if _assets != null:
		_assets.prewarm_decals()


# =================================================================================================
# PUBLIC API - contract methods (names and signatures are frozen)
# =================================================================================================

## Surface type of a hit collider: reads meta "surface" on the collider or its ancestors,
## vehicles -> "metal", characters -> "flesh", glass panes -> "glass", default "concrete".
func surface_of(collider: Object) -> String:
	if collider == null or not is_instance_valid(collider):
		return "concrete"
	var n := collider as Node
	var guard := 0
	while n != null and guard < 6:
		if n.has_meta("surface"):
			return _normalize_surface(str(n.get_meta("surface")))
		if n.is_in_group("vehicle"):
			return "metal"
		if n.is_in_group("npc") or n.is_in_group("player") or n.is_in_group("animal"):
			return "flesh"
		if n.is_in_group("water_surface"):
			return "water"
		var co := n as CollisionObject3D
		if co != null and (co.collision_layer & Layers.GLASS) != 0 and (co.collision_layer & Layers.WORLD) == 0:
			return "glass"
		n = n.get_parent()
		guard += 1
	return "concrete"


## Bullet / melee impact: particles + decal + impact sound chosen by surface.
func impact(position: Vector3, normal: Vector3, surface: String = "concrete", scale: float = 1.0) -> void:
	if not _built:
		_build()
	var n := _safe_normal(normal)
	var s := clampf(scale, 0.2, 3.0)
	if surface == "water":
		_impact_audio("impact_water", position, 1.0)
		_splash_visual(position, 0.45 * s)
		return
	var far := _too_far(position, _fx_range)
	var with_particles := not far and _frame_impacts < MAX_IMPACTS_PER_FRAME
	if with_particles:
		_frame_impacts += 1
	var p := position + n * 0.03
	var b := _basis_up(n, s)
	match surface:
		"concrete", "asphalt":
			var asphalt := surface == "asphalt"
			_impact_audio("impact_concrete", position, 1.0)
			if with_particles:
				_emit(&"puff", p, b * 0.8, _assets.blob, _assets.lit(C_ASPHALT_DUST if asphalt else C_CONCRETE_DUST), 0.7)
				_emit(&"chips", p, b, _assets.chunk, _assets.lit(C_ASPHALT_CHIP if asphalt else C_CONCRETE_CHIP), 0.75)
			if not far:
				_place_decal(position, n, Vector3.ZERO, "bullet", 0.17 * s, -1.0, null)
		"metal":
			_impact_audio("impact_metal", position, 1.0)
			if randf() < 0.2:
				_play_at("ricochet", position, -6.0, randf_range(0.9, 1.2), 50.0)
			if with_particles:
				_emit(&"sparks", p, b, _assets.spark, _assets.glow(C_SPARK, 1.8, 0.0, 0.2), 0.6, 0.55 * s)
				_emit(&"puff", p, b * 0.5, _assets.blob, _assets.lit(C_METAL_DUST), 0.35)
		"glass":
			_impact_audio("impact_glass", position, 1.0)
			if with_particles:
				_emit(&"chips", p, b * 1.3, _assets.shard, _assets.lit(C_GLASS, 0.3), 0.9)
		"wood":
			_impact_audio("impact_wood", position, 1.0)
			if with_particles:
				_emit(&"chips", p, b, _assets.splinter, _assets.lit(C_WOOD_CHIP), 0.75, 1.7 * s)
				_emit(&"puff", p, b * 0.6, _assets.blob, _assets.lit(C_WOOD_DUST), 0.5)
			if not far:
				_place_decal(position, n, Vector3.ZERO, "bullet", 0.14 * s, -1.0, null)
		"dirt":
			_impact_audio("impact_dirt", position, 1.0)
			if with_particles:
				_emit(&"puff", p, b, _assets.blob, _assets.lit(C_DIRT_DUST), 0.85)
				_emit(&"chips", p, b, _assets.chunk, _assets.lit(C_DIRT_CHIP), 0.6)
		"grass":
			_impact_audio("impact_dirt", position, 1.05)
			if with_particles:
				_emit(&"puff", p, b * 0.8, _assets.blob, _assets.lit(C_GRASS_DUST), 0.6)
				_emit(&"chips", p, b * 1.2, _assets.shard, _assets.lit(C_GRASS_CHIP), 0.7)
		"sand":
			_impact_audio("impact_dirt", position, 1.15)
			if with_particles:
				_emit(&"puff", p, b * 1.2, _assets.blob, _assets.lit(C_SAND_DUST), 1.0)
				_emit(&"chips", p, b * 0.7, _assets.chunk, _assets.lit(C_SAND_CHIP), 0.6)
		"flesh":
			_impact_audio("impact_flesh", position, 1.0)
			if with_particles:
				_emit(&"puff", p, b * 0.55, _assets.blob, _assets.lit(C_BLOOD), 0.6)
		"rubber":
			_impact_audio("impact_dirt", position, 0.8)
			if with_particles:
				_emit(&"puff", p, b * 0.6, _assets.blob, _assets.lit(C_RUBBER), 0.5)
				_emit(&"chips", p, b * 0.8, _assets.chunk, _assets.lit(C_RUBBER), 0.5)
		"foliage":
			_impact_audio("impact_dirt", position, 1.2)
			if with_particles:
				_emit(&"chips", p, b * 1.3, _assets.shard, _assets.lit(C_LEAF), 0.9)
				_emit(&"puff", p, b * 0.5, _assets.blob, _assets.lit(C_GRASS_DUST), 0.35)
		_:
			_impact_audio("impact_concrete", position, 1.0)
			if with_particles:
				_emit(&"puff", p, b * 0.8, _assets.blob, _assets.lit(C_CONCRETE_DUST), 0.7)
				_emit(&"chips", p, b, _assets.chunk, _assets.lit(C_CONCRETE_CHIP), 0.75)


## Short faceted flash + glow (+ a pooled light) that follows the muzzle node for a few frames.
## `at` is the weapon's Muzzle marker (its -Z is the firing direction).
func muzzle_flash(at: Node3D, scale: float = 1.0) -> void:
	if at == null or not is_instance_valid(at) or not at.is_inside_tree():
		return
	if not _built:
		_build()
	if _too_far(at.global_position, _fx_range):
		return
	var i := _mz_next
	_mz_next = (_mz_next + 1) % MUZZLE_POOL
	_mz_ref[i] = at
	_mz_until[i] = _now + MUZZLE_TIME
	_mz_roll[i] = randf_range(0.0, TAU)
	_mz_scale[i] = clampf(scale, 0.2, 3.0) * randf_range(0.85, 1.15)
	_mz_star[i].visible = true
	_mz_glow[i].visible = true
	_place_muzzle(i, 1.0)
	if _lights_on and _muzzle_light_on and _mz_light != null:
		_mz_light.global_position = at.global_position
		_mz_light.light_energy = 1.6 * clampf(scale, 0.4, 2.0)
		_mz_light.visible = true
		_mz_light_until = _now + MUZZLE_TIME
	_touch(MUZZLE_TIME + 0.1)


## Bright streak that travels from `from` to `to` at TRACER_SPEED.
func tracer(from: Vector3, to: Vector3) -> void:
	if not _built:
		_build()
	var d := to - from
	var dist := d.length()
	if dist < 0.6 or (_too_far(from, _fx_range) and _too_far(to, _fx_range)):
		return
	var i := _tr_next
	_tr_next = (_tr_next + 1) % TRACER_POOL
	_tr_from[i] = from
	_tr_dir[i] = d / dist
	_tr_dist[i] = dist
	_tr_len[i] = minf(dist, clampf(dist * 0.4, 1.5, 9.0))
	_tr_speed[i] = minf(TRACER_SPEED, dist / 0.05)
	_tr_t0[i] = _now
	_tr[i].visible = true
	_place_tracer(i, 0.0)
	_touch(dist / _tr_speed[i] + 0.1)


## Brass casing that hops out of the weapon's Eject marker (+X of the marker = ejection side).
func shell_eject(at: Node3D) -> void:
	if at == null or not is_instance_valid(at) or not at.is_inside_tree():
		return
	if not _built:
		_build()
	if quality <= 0 or _too_far(at.global_position, 40.0):
		return
	var i := _sh_next
	_sh_next = (_sh_next + 1) % SHELL_POOL
	var bs := at.global_transform.basis.orthonormalized()
	_sh_pos[i] = at.global_position
	_sh_vel[i] = bs.x * randf_range(1.4, 2.4) + Vector3.UP * randf_range(1.6, 2.6) + bs.z * randf_range(-0.4, 0.6)
	_sh_axis[i] = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	_sh_t0[i] = _now
	_sh[i].visible = true
	_sh[i].global_transform = Transform3D(bs, _sh_pos[i])
	_touch(SHELL_TIME + 0.1)


## Full explosion: visuals, sound, radial damage with falloff (through Dmg), physics impulse,
## camera shake, EventBus.explosion + noise_emitted, and a crime report when player-caused.
## opts: {"visual_scale": float, "no_damage": bool, "fire": bool, "ignore": Array[Node],
##        "weapon_id": String, "los": bool (default true), "force": float, "no_crime": bool,
##        "no_scorch": bool, "silent": bool}
## An explosion requested from inside another blast's damage callback is queued and goes off on
## the next physics frame (staggered chain reactions, no recursion).
func explosion(position: Vector3, radius: float = 6.0, damage: float = 160.0,
		instigator: Node = null, opts: Dictionary = {}) -> void:
	if _blast_depth > 0:
		if _pending_explosions.size() < MAX_PENDING_EXPLOSIONS:
			_pending_explosions.append([position, radius, damage, instigator, opts])
		return
	_blast_depth += 1
	_explode_now(position, radius, damage, instigator, opts)
	_blast_depth -= 1


## Persistent fire (burning vehicle, molotov area). Returns the fire handle (fx_handle.gd) or null.
## The fire burns for `duration` seconds (<= 0: until the caller frees the handle), follows
## `parent` when one is given, and damages what stands in it (see fx_handle.gd for the knobs).
func spawn_fire(position: Vector3, duration: float = 8.0, parent: Node3D = null, scale: float = 1.0) -> Node3D:
	if not _built:
		_build()
	if not is_inside_tree():
		return null
	while _fires.size() >= MAX_FIRES:
		var oldest: Variant = _fires[0]
		if is_instance_valid(oldest):
			_on_handle_gone(oldest)
			(oldest as Node).queue_free()
		else:
			_fires.remove_at(0)
	var s := clampf(scale, 0.3, 3.0)
	var h: FxHandle = FxHandle.new()
	h.name = "FxFire"
	h.fx_owner = self
	h.fx_kind = "fire"
	h.fx_scale = s
	h.time_left = duration if duration > 0.0 else -1.0
	h.deals_damage = true
	h.set_meta("deals_damage", true)
	h.radius = 0.9 + 0.9 * s
	h.burn_tick = randf_range(0.1, FIRE_TICK)
	h.phase = randf_range(0.0, TAU)
	var host: Node = _root
	if parent != null and is_instance_valid(parent) and parent.is_inside_tree():
		host = parent
		var own := Dmg.find_damageable(parent)
		h.ignore.append(own if own != null else parent)
	host.add_child(h)
	h.global_position = position
	_loop_start(h, "flames", s)
	_loop_start(h, "fire_smoke", s)
	_handles.append(h)
	_fires.append(h)
	_fire_audio_start(h)
	return h


## kind: "light","heavy","black","steam"
func smoke_puff(position: Vector3, kind: String = "light", scale: float = 1.0) -> void:
	if not _built:
		_build()
	if _too_far(position, _fx_range):
		return
	var c := C_SMOKE_LIGHT
	match kind:
		"heavy":
			c = C_SMOKE_HEAVY
		"black":
			c = C_SMOKE_BLACK
		"steam":
			c = C_STEAM
	_emit(&"smoke", position, Basis.from_scale(Vector3.ONE * clampf(scale, 0.15, 4.0)), _assets.blob, _assets.lit(c), 0.7)


func sparks(position: Vector3, normal: Vector3 = Vector3.UP, amount: float = 1.0) -> void:
	if not _built:
		_build()
	if _too_far(position, _fx_range):
		return
	var a := clampf(amount, 0.1, 3.0)
	_emit(&"sparks", position, _basis_up(_safe_normal(normal), 0.8 + 0.35 * a), _assets.spark,
			_assets.glow(C_SPARK, 1.8, 0.0, 0.2), clampf(0.35 + 0.45 * a, 0.2, 1.0), 0.55 + 0.25 * a)


func dust(position: Vector3, scale: float = 1.0) -> void:
	if not _built:
		_build()
	if _too_far(position, _fx_range) or not _take_puff_token():
		return
	_emit(&"smoke", position + Vector3(0.0, 0.1, 0.0), Basis.from_scale(Vector3.ONE * clampf(0.7 + 0.5 * scale, 0.3, 3.0)),
			_assets.blob, _assets.lit(C_DUST), 0.6)


func splash(position: Vector3, scale: float = 1.0) -> void:
	if not _built:
		_build()
	var s := clampf(scale, 0.2, 4.0)
	if _now - _last_splash_audio > 0.06:
		_last_splash_audio = _now
		if s < 0.7:
			_play_at("impact_water", position, -4.0, randf_range(0.9, 1.15), 40.0)
		else:
			_play_at("splash_large" if s >= 1.4 else "splash_small", position, -2.0 + minf(s, 3.0),
					randf_range(0.92, 1.08), 70.0)
	_splash_visual(position, s)


func tire_smoke(position: Vector3, amount: float = 1.0) -> void:
	if not _built:
		_build()
	if _too_far(position, _fx_range) or not _take_puff_token():
		return
	var a := clampf(amount, 0.0, 2.0)
	_emit(&"smoke", position + Vector3(0.0, 0.12, 0.0), Basis.from_scale(Vector3.ONE * (0.7 + 0.45 * a)),
			_assets.blob, _assets.lit(C_TYRE_SMOKE), clampf(0.35 + 0.3 * a, 0.3, 0.8))


## Shards only - callers already play "glass_break" themselves (vehicle panes, bottles).
func glass_shatter(position: Vector3, normal: Vector3 = Vector3.UP, scale: float = 1.0) -> void:
	if not _built:
		_build()
	if _too_far(position, _fx_range):
		return
	var s := clampf(scale, 0.2, 3.0)
	var n := _safe_normal(normal)
	_emit(&"chips", position, _basis_up(n, 1.2 * s), _assets.shard, _assets.lit(C_GLASS, 0.3), 1.0, 1.6 * s)
	if s >= 0.8:
		_emit(&"debris", position, _basis_up(n, 0.5 * s), _assets.shard, _assets.lit(C_GLASS, 0.3), 0.8, 0.7 * s)


## Small stylised red puff (kept tasteful) + sometimes a splat on the ground below.
func blood(position: Vector3, direction: Vector3 = Vector3.UP) -> void:
	if not _built:
		_build()
	if _too_far(position, minf(_fx_range, 80.0)):
		return
	var n := _safe_normal(direction)
	_emit(&"puff", position, _basis_up(n, 0.6), _assets.blob, _assets.lit(C_BLOOD), 0.7)
	_emit(&"chips", position, _basis_up(n, 0.75), _assets.pebble, _assets.lit(C_BLOOD_DARK), 0.5)
	if quality > 0 and randf() < 0.4:
		var g := _ground_below(position, 2.4)
		if not g.is_empty():
			_place_decal(g["position"], g["normal"], Vector3.ZERO, "blood", randf_range(0.45, 0.8), -1.0, null)


## kind: "bullet","scorch","blood","skid","oil". Pooled (cap 64, oldest recycled), random roll.
## Use decal_oriented() for skid marks or to pin a decal to a moving body.
func decal(position: Vector3, normal: Vector3, kind: String = "bullet", size: float = 0.18) -> void:
	if not _built:
		_build()
	_place_decal(position, _safe_normal(normal), Vector3.ZERO, kind, size, -1.0, null)


func money_burst(position: Vector3) -> void:
	if not _built:
		_build()
	if _too_far(position, 60.0):
		return
	_emit(&"chips", position + Vector3(0.0, 0.3, 0.0), Basis.from_scale(Vector3.ONE * 0.8), _assets.bill,
			_assets.lit(C_MONEY, 0.25), 1.0, 7.0)
	_emit(&"sparkle", position + Vector3(0.0, 0.3, 0.0), Basis.IDENTITY, _assets.chunk,
			_assets.glow(C_GOLD, 1.5, 1.0, 0.3), 0.7)


func pickup_sparkle(position: Vector3, color: Color = Color.WHITE) -> void:
	if not _built:
		_build()
	if _too_far(position, 60.0):
		return
	var c := Color(snappedf(color.r, 0.125), snappedf(color.g, 0.125), snappedf(color.b, 0.125))
	_emit(&"sparkle", position + Vector3(0.0, 0.35, 0.0), Basis.IDENTITY, _assets.chunk,
			_assets.glow(c.lerp(Color.WHITE, 0.25), 1.5, 1.0, 0.3), 1.0)


## Camera trauma 0..1. If `position` is given the amount falls off with distance to the player.
func shake_camera(amount: float, position: Vector3 = Vector3.INF, radius: float = 30.0) -> void:
	var a := amount
	if position != Vector3.INF and Game.has_player():
		var d := Game.get_player_position().distance_to(position)
		a *= clampf(1.0 - d / maxf(radius, 0.01), 0.0, 1.0)
	if a > 0.001:
		var mult: Variant = Settings.get_value("camera_shake")
		camera_shake_requested.emit(a * (float(mult) if mult != null else 1.0))


# =================================================================================================
# PUBLIC API - additions (documented in docs/FX.md)
# =================================================================================================

## Looping smoke for a damaged vehicle. kind: "light" | "heavy" | "black". Returns a handle
## (fx_handle.gd) parented to `parent` at its origin - move it (handle.position) to the engine
## and queue_free() it to stop. Returns null if `parent` is not usable.
func attach_smoke(parent: Node3D, kind: String = "light") -> Node3D:
	var k := kind if SMOKE_KINDS.has(kind) else "light"
	return _attach(parent, "smoke", k, "smoke_" + k)


## Looping trail. kind: "rocket" | "tyre" (alias "tire") | "wake" | "dust" | "exhaust".
## Same handle rules as attach_smoke(); handle.set_strength(0..1) scales the emission live.
func attach_trail(parent: Node3D, kind: String = "rocket") -> Node3D:
	var k := "tyre" if kind == "tire" else kind
	if not TRAIL_KINDS.has(k):
		k = "rocket"
	return _attach(parent, "trail", k, "trail_" + k)


## Ground ring of dust (or spray over water) under a hovering helicopter. Call it repeatedly
## with the ground point below the rotor; it is rate limited internally. strength 0..1.
func rotor_wash(position: Vector3, strength: float = 1.0) -> void:
	if not _built:
		_build()
	var st := clampf(strength, 0.0, 1.5)
	if st <= 0.05 or _too_far(position, _fx_range) or not _take_puff_token():
		return
	var wet := Game.is_in_water(position - Vector3(0.0, 0.1, 0.0))
	_emit(&"dust_ring", position + Vector3(0.0, 0.2, 0.0), Basis.from_scale(Vector3.ONE * (1.4 + 1.2 * st)),
			_assets.blob, _assets.lit(C_FOAM if wet else C_DUST), clampf(0.5 + 0.5 * st, 0.3, 1.0), 1.0 + 0.4 * st)


## Expanding faceted ripple on the water surface (also used by splash()).
func water_ring(position: Vector3, scale: float = 1.0) -> void:
	if not _built:
		_build()
	if _too_far(position, _fx_range):
		return
	var i := _wr_next
	_wr_next = (_wr_next + 1) % RING_POOL
	_wr_t0[i] = _now
	_wr_scale[i] = clampf(scale, 0.2, 6.0)
	var ring := _wr[i]
	ring.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * (1.6 * _wr_scale[i])), position + Vector3(0.0, 0.04, 0.0))
	ring.set_instance_shader_parameter("ring_color", Color(0.94, 0.98, 1.0, 0.85))
	ring.set_instance_shader_parameter("progress", 0.15)
	ring.set_instance_shader_parameter("width", 0.35)
	ring.set_instance_shader_parameter("fade", 1.0)
	ring.visible = true
	_touch(WATER_RING_TIME + 0.1)


## 0 = low (fewer particles, 24 decals, no Fx lights), 1 = medium, 2 = high (default).
func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	_amount_scale = [0.55, 0.8, 1.0][quality]
	_fx_range = [70.0, 110.0, 160.0][quality]
	_lights_on = quality >= 1
	_muzzle_light_on = quality >= 2
	_decal_cap = [24, 48, MAX_DECALS][quality]
	_decal_next = _decal_next % _decal_cap
	for i in _decals.size():
		if i >= _decal_cap and is_instance_valid(_decals[i]):
			_decals[i].visible = false
	if not _lights_on:
		for l in _ex_lights:
			l.visible = false
		for l in _fire_lights:
			l.visible = false
		if _mz_light != null:
			_mz_light.visible = false


## Decal with an explicit orientation: `forward` is the direction of the texture's length axis
## (skid marks), `length` (> 0) stretches it along that axis, and a `parent` pins the decal to a
## moving body (the pooled node is lent to the body; if the body is freed the pool re-creates it).
func decal_oriented(position: Vector3, normal: Vector3, forward: Vector3, kind: String = "skid",
		size: float = 0.25, length: float = -1.0, parent: Node3D = null) -> void:
	if not _built:
		_build()
	_place_decal(position, _safe_normal(normal), forward, kind, size, length, parent)


## Removes every decal (admin menu / respawn clean-up).
func clear_decals() -> void:
	for d in _decals:
		if is_instance_valid(d):
			d.visible = false
	_decal_next = 0


## Debug / test counters. "live_particles" is an upper bound (amount * ratio of active systems).
func get_stats() -> Dictionary:
	var active := 0
	var live := 0.0
	for i in _em.size():
		if _em_until[i] > _now:
			active += 1
			live += _em_live[i]
	var visible_decals := 0
	for d in _decals:
		if is_instance_valid(d) and d.visible:
			visible_decals += 1
	var lights := 0
	for l in _ex_lights:
		if l.visible:
			lights += 1
	var fire_lights := 0
	for l in _fire_lights:
		if l.visible:
			fire_lights += 1
	return {
		"active_systems": active,
		"live_particles": int(ceil(live)),
		"emitters_total": _em.size(),
		"decals_visible": visible_decals,
		"decals_pool": _decals.size(),
		"decals_placed": _decals_placed,
		"fires": _fires.size(),
		"handles": _handles.size(),
		"explosion_lights": lights,
		"fire_lights": fire_lights,
		"materials": _assets.material_count() if _assets != null else 0,
		"pending_explosions": _pending_explosions.size(),
		"quality": quality,
	}


## Explosion damage multiplier at `dist` for a blast of `radius` (same curve the blast uses).
func explosion_falloff(dist: float, radius: float) -> float:
	return FxBlast.falloff(dist, radius)


# =================================================================================================
# frame update
# =================================================================================================

func _process(delta: float) -> void:
	_now += delta
	_frame_impacts = 0
	_puff_tokens = minf(_puff_tokens + delta * PUFF_RATE, PUFF_BURST)
	if not _built:
		return
	if not _handles.is_empty():
		_update_handles(delta)
	if _now > _busy_until:
		if not _busy:
			return
		_busy = false      # one last pass hides whatever has just run out
	_update_explosions()
	_update_muzzle()
	_update_tracers()
	_update_shells(delta)
	_update_rings()


func _physics_process(delta: float) -> void:
	_blast_depth = 0
	if not _pending_explosions.is_empty():
		var e: Array = _pending_explosions.pop_front()
		var who: Variant = e[3]
		var inst: Node = who as Node if (who != null and is_instance_valid(who)) else null
		explosion(e[0], e[1], e[2], inst, e[4])
	if _fires.is_empty():
		return
	for k in range(_fires.size() - 1, -1, -1):
		var fv: Variant = _fires[k]
		if not is_instance_valid(fv):
			_fires.remove_at(k)
			continue
		var h := fv as FxHandle
		if h == null or not h.is_inside_tree():
			continue
		h.burn_tick -= delta
		if h.burn_tick <= 0.0:
			h.burn_tick += FIRE_TICK
			_burn(h)


func _touch(duration: float) -> void:
	_busy = true
	_busy_until = maxf(_busy_until, _now + duration)


func _update_handles(delta: float) -> void:
	for k in range(_handles.size() - 1, -1, -1):
		var hv: Variant = _handles[k]
		if not is_instance_valid(hv):
			_handles.remove_at(k)
			continue
		var h := hv as FxHandle
		if h == null:
			continue
		if not h.is_inside_tree():
			continue
		if h.time_left > 0.0:
			h.time_left -= delta
			if h.time_left <= 0.0:
				_on_handle_gone(h)
				h.queue_free()
				continue
		var pos := h.global_position
		for e in h.emitters.size():
			_em[h.emitters[e]].global_position = pos + h.offsets[e]
		if h.strength != h.applied_strength:
			h.applied_strength = h.strength
			for e in h.emitters.size():
				var p := _em[h.emitters[e]]
				if h.strength <= 0.02:
					p.emitting = false
				else:
					p.amount_ratio = clampf(h.base_ratio[e] * h.strength * _amount_scale, 0.03, 1.0)
					if not p.emitting:
						p.emitting = true
		if h.fx_kind == "fire":
			_update_fire_light(h, pos)
			if h.audio_index >= 0:
				(_fire_audio[h.audio_index] as Node3D).global_position = pos


## Crackle for the first MAX_LIT_FIRES fires: looping players that live in the pool (a player per
## fire that dies with its handle leaves audio playbacks behind in headless runs).
func _fire_audio_start(h: FxHandle) -> void:
	if not _fire_audio_built:
		if not _audio_ok() or not _audio.has_method("make_loop_player") or not _audio.has_method("get_stream"):
			return
		if _audio.call("get_stream", "fire_loop") == null:
			return
		_fire_audio_built = true
		for i in MAX_LIT_FIRES:
			var lp: Variant = _audio.call("make_loop_player", "fire_loop", _root, 45.0, "SFX")
			if lp is AudioStreamPlayer3D:
				(lp as AudioStreamPlayer3D).volume_db = -5.0
				_fire_audio.append(lp)
				_fire_audio_owner.append(null)
	for i in _fire_audio.size():
		var owner_v: Variant = _fire_audio_owner[i]
		if owner_v != null and is_instance_valid(owner_v):
			continue
		var player: Variant = _fire_audio[i]
		if not is_instance_valid(player):
			continue
		_fire_audio_owner[i] = h
		h.audio_index = i
		(player as Node3D).global_position = h.global_position
		(player as Node).call("play")
		return


func _update_fire_light(h: FxHandle, pos: Vector3) -> void:
	if not _lights_on:
		return
	if h.light_index < 0:
		for i in _fire_lights.size():
			if _fire_light_owner[i] == null:
				_fire_light_owner[i] = h
				h.light_index = i
				_fire_lights[i].omni_range = 4.5 + 3.5 * h.fx_scale
				_fire_lights[i].visible = true
				break
		if h.light_index < 0:
			return
	var l := _fire_lights[h.light_index]
	l.global_position = pos + Vector3(0.0, 0.5 + 0.4 * h.fx_scale, 0.0)
	var t := _now * 1.0 + h.phase
	l.light_energy = (1.5 + 0.5 * h.fx_scale) * (0.82 + 0.13 * sin(t * 17.0) + 0.09 * sin(t * 31.0 + 1.3))


func _update_explosions() -> void:
	for i in EXPLOSION_SLOTS:
		if _ex_t0[i] < 0.0:
			continue
		var t := float(_now - _ex_t0[i])
		var flash := _ex_flash[i]
		if t < FLASH_TIME:
			var k := t / FLASH_TIME
			var e := 1.0 - (1.0 - k) * (1.0 - k)
			flash.scale = Vector3.ONE * (_ex_size[i] * (3.5 + 4.5 * e))
			flash.set_instance_shader_parameter("fade", pow(1.0 - k, 1.5))
		elif flash.visible:
			flash.visible = false
		var ring := _ex_ring[i]
		if t < RING_TIME:
			var k2 := t / RING_TIME
			var e2 := 1.0 - (1.0 - k2) * (1.0 - k2) * (1.0 - k2)
			ring.set_instance_shader_parameter("progress", 0.1 + 0.9 * e2)
			ring.set_instance_shader_parameter("width", lerpf(0.55, 0.12, k2))
			ring.set_instance_shader_parameter("fade", (1.0 - k2) * 0.75)
		elif ring.visible:
			ring.visible = false
		if t >= maxf(FLASH_TIME, RING_TIME):
			_ex_t0[i] = -1.0
	for j in _ex_lights.size():
		if _exl_t0[j] < 0.0:
			continue
		var lt := float(_now - _exl_t0[j]) / LIGHT_TIME
		if lt < 1.0:
			_ex_lights[j].light_energy = _exl_energy[j] * (1.0 - lt) * (1.0 - lt)
		else:
			_ex_lights[j].visible = false
			_exl_t0[j] = -1.0


func _update_muzzle() -> void:
	for i in MUZZLE_POOL:
		if _mz_until[i] <= 0.0:
			continue
		var left := float(_mz_until[i] - _now)
		if left <= 0.0 or not is_instance_valid(_mz_ref[i]) or not (_mz_ref[i] as Node3D).is_inside_tree():
			_mz_star[i].visible = false
			_mz_glow[i].visible = false
			_mz_until[i] = 0.0
			_mz_ref[i] = null
			continue
		_place_muzzle(i, clampf(left / MUZZLE_TIME, 0.0, 1.0))
	if _mz_light != null and _mz_light.visible and _now >= _mz_light_until:
		_mz_light.visible = false


func _place_muzzle(i: int, k: float) -> void:
	var at := _mz_ref[i] as Node3D
	var xf := at.global_transform
	var s := _mz_scale[i]
	var b := xf.basis.orthonormalized() * Basis(Vector3.BACK, _mz_roll[i])
	_mz_star[i].global_transform = Transform3D(b * Basis.from_scale(Vector3.ONE * s * (1.15 - 0.15 * k)), xf.origin)
	_mz_star[i].set_instance_shader_parameter("fade", 0.35 + 0.65 * k)
	_mz_glow[i].global_transform = Transform3D(Basis.from_scale(Vector3.ONE * (0.55 * s)), xf.origin - b.z * (0.1 * s))
	_mz_glow[i].set_instance_shader_parameter("fade", 0.7 * k)


func _update_tracers() -> void:
	for i in TRACER_POOL:
		if _tr_speed[i] <= 0.0:
			continue
		var t := float(_now - _tr_t0[i])
		if _tr_speed[i] * t >= _tr_dist[i]:
			_tr[i].visible = false
			_tr_speed[i] = 0.0
			continue
		_place_tracer(i, t)


func _place_tracer(i: int, t: float) -> void:
	var tail := minf(_tr_speed[i] * t, _tr_dist[i])
	var head := minf(_tr_len[i] + _tr_speed[i] * t, _tr_dist[i])
	var l := maxf(head - tail, 0.05)
	var dir := _tr_dir[i]
	var b := _basis_up(dir, 1.0) * Basis.from_scale(Vector3(0.035, l, 0.035))
	_tr[i].global_transform = Transform3D(b, _tr_from[i] + dir * ((head + tail) * 0.5))


func _update_shells(delta: float) -> void:
	for i in SHELL_POOL:
		if _sh_t0[i] < 0.0:
			continue
		var t := float(_now - _sh_t0[i])
		if t >= SHELL_TIME:
			_sh[i].visible = false
			_sh_t0[i] = -1.0
			continue
		var v := _sh_vel[i]
		v.y -= 9.8 * delta
		_sh_vel[i] = v
		_sh_pos[i] += v * delta
		var k := clampf((SHELL_TIME - t) / 0.15, 0.0, 1.0)
		_sh[i].global_transform = Transform3D(Basis(_sh_axis[i], t * 22.0) * Basis.from_scale(Vector3.ONE * k), _sh_pos[i])


func _update_rings() -> void:
	for i in RING_POOL:
		if _wr_t0[i] < 0.0:
			continue
		var k := float(_now - _wr_t0[i]) / WATER_RING_TIME
		if k >= 1.0:
			_wr[i].visible = false
			_wr_t0[i] = -1.0
			continue
		var e := 1.0 - (1.0 - k) * (1.0 - k)
		_wr[i].set_instance_shader_parameter("progress", 0.15 + 0.85 * e)
		_wr[i].set_instance_shader_parameter("width", lerpf(0.4, 0.14, k))
		_wr[i].set_instance_shader_parameter("fade", 1.0 - k)


# =================================================================================================
# explosions
# =================================================================================================

func _explode_now(position: Vector3, radius: float, damage: float, instigator: Node, opts: Dictionary) -> void:
	if not _built:
		_build()
	var r := maxf(radius, 0.1)
	var vs := clampf(float(opts.get("visual_scale", r / 6.0)), 0.4, 2.2)
	var who: Node = instigator if (instigator != null and is_instance_valid(instigator)) else null
	var space := _space()
	var ground: Dictionary = _ground_below(position, 2.0 + r * 0.25) if space != null else {}
	var in_water := position.y <= Game.WATER_LEVEL + 0.6 and Game.is_in_water(
			Vector3(position.x, minf(position.y, Game.WATER_LEVEL - 0.05), position.z))
	if not _too_far(position, 400.0):
		_explosion_visuals(position, r, vs, ground, in_water)
	if not bool(opts.get("silent", false)):
		_play_at("explosion_large" if r >= 4.5 else "explosion_small", position, 4.0 if r >= 4.5 else 1.0,
				randf_range(0.92, 1.08), 300.0)
	var no_damage := bool(opts.get("no_damage", false))
	if not no_damage and space != null:
		_blast.detonate(space, position, r, damage, who, opts)
	EventBus.explosion.emit(position, r, who)
	EventBus.noise_emitted.emit(position, 120.0, "explosion", who)
	if not no_damage and not bool(opts.get("no_crime", false)) and Dmg.caused_by_player({"instigator": who}):
		var wanted := get_node_or_null("/root/Wanted")
		if wanted != null and wanted.has_method("report_crime"):
			wanted.call("report_crime", "explosion", position, {"instigator": who})
	shake_camera(clampf(0.5 + 0.07 * r, 0.3, 1.0), position, maxf(r * 8.0, 40.0))
	if in_water:
		return
	if not ground.is_empty():
		var gp: Vector3 = ground["position"]
		var gn: Vector3 = ground["normal"]
		if not bool(opts.get("no_scorch", false)) and not _too_far(position, _fx_range):
			_place_decal(gp, gn, Vector3.ZERO, "scorch", clampf(r * 0.85, 1.2, 7.0), -1.0, null)
		if bool(opts.get("fire", false)):
			var f := spawn_fire(gp + gn * 0.05, 6.0, null, clampf(vs, 0.6, 1.6))
			if f != null:
				(f as FxHandle).instigator = who


func _explosion_visuals(position: Vector3, radius: float, vs: float, ground: Dictionary, in_water: bool) -> void:
	var i := _ex_next
	_ex_next = (_ex_next + 1) % EXPLOSION_SLOTS
	_ex_t0[i] = _now
	_ex_size[i] = vs
	_ex_ring_r[i] = radius
	var flash := _ex_flash[i]
	flash.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * vs * 3.5), position + Vector3(0.0, 0.6 * vs, 0.0))
	flash.set_instance_shader_parameter("glow_color", C_FLASH)
	flash.set_instance_shader_parameter("fade", 1.0)
	flash.visible = true
	var ring := _ex_ring[i]
	var ring_pos := position
	var ring_basis := Basis.IDENTITY
	if not ground.is_empty():
		var gn: Vector3 = ground["normal"]
		ring_pos = (ground["position"] as Vector3) + gn * 0.08
		ring_basis = _basis_up(gn, 1.0)
	elif in_water:
		ring_pos = Vector3(position.x, Game.WATER_LEVEL + 0.06, position.z)
	ring.global_transform = Transform3D(ring_basis * Basis.from_scale(Vector3.ONE * radius), ring_pos)
	ring.set_instance_shader_parameter("ring_color", Color(1.0, 0.93, 0.78, 0.8))
	ring.set_instance_shader_parameter("progress", 0.1)
	ring.set_instance_shader_parameter("width", 0.55)
	ring.set_instance_shader_parameter("fade", 0.75)
	ring.visible = true
	if _lights_on:
		var j := _exl_next
		_exl_next = (_exl_next + 1) % MAX_EXPLOSION_LIGHTS
		var l := _ex_lights[j]
		l.global_position = position + Vector3(0.0, 0.8 * vs, 0.0)
		l.omni_range = maxf(radius * 3.0, 10.0)
		_exl_energy[j] = 5.0 + 2.0 * vs
		l.light_energy = _exl_energy[j]
		l.visible = true
		_exl_t0[j] = _now
	_touch(maxf(RING_TIME, LIGHT_TIME) + 0.1)
	var b := Basis.from_scale(Vector3.ONE * vs)
	var up := Vector3(0.0, 0.35 * vs, 0.0)
	_emit(&"fireball", position + up, b, _assets.blob, _assets.glow(Color.WHITE, 1.45, 1.0, 0.45), 1.0)
	_emit(&"blast_smoke", position + up * 1.6, b, _assets.blob, _assets.lit(Color.WHITE), 1.0)
	_emit(&"sparks", position + up * 0.5, Basis.from_scale(Vector3.ONE * (1.9 * vs)), _assets.spark,
			_assets.glow(C_SPARK, 1.9, 0.0, 0.2), 1.0, 1.2 * vs)
	if in_water:
		_splash_visual(Vector3(position.x, Game.WATER_LEVEL, position.z), 2.6 * vs)
		return
	_emit(&"debris", position + up * 0.3, b, _assets.chunk, _assets.lit(C_DEBRIS), 1.0)
	if not ground.is_empty():
		var gn2: Vector3 = ground["normal"]
		_emit(&"dust_ring", (ground["position"] as Vector3) + gn2 * 0.25, _basis_up(gn2, vs), _assets.blob,
				_assets.lit(C_DUST), 1.0)


# =================================================================================================
# fire damage
# =================================================================================================

func _burn(h: FxHandle) -> void:
	if not h.deals_damage or h.damage_per_second <= 0.0 and h.vehicle_damage_per_second <= 0.0:
		return
	var space := _space()
	if space == null:
		return
	var center := h.global_position + Vector3(0.0, 0.5, 0.0)
	_fire_shape.radius = maxf(h.radius, 0.2)
	_fire_query.transform = Transform3D(Basis.IDENTITY, center)
	var results: Array[Dictionary] = space.intersect_shape(_fire_query, 16)
	if results.is_empty():
		return
	var who: Node = h.instigator if (h.instigator != null and is_instance_valid(h.instigator)) else null
	var done: Dictionary = {}
	for r: Dictionary in results:
		var target := Dmg.find_damageable(r.get("collider", null))
		if target == null or not is_instance_valid(target):
			continue
		var id := target.get_instance_id()
		if done.has(id) or h.ignore.has(target):
			continue
		done[id] = true
		var dps := h.vehicle_damage_per_second if target.is_in_group("vehicle") else h.damage_per_second
		if dps <= 0.0:
			continue
		var at: Vector3 = (target as Node3D).global_position if target is Node3D else center
		target.call("apply_damage", Dmg.make(dps * FIRE_TICK, "fire", who, at, Vector3.UP, {"weapon_id": h.weapon_id}))


# =================================================================================================
# handles (fire / smoke / trail)
# =================================================================================================

func _attach(parent: Node3D, kind: String, variant: String, loop_id: String) -> Node3D:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	if not _built:
		_build()
	var h: FxHandle = FxHandle.new()
	h.name = "Fx" + kind.capitalize()
	h.fx_owner = self
	h.fx_kind = kind
	h.variant = variant
	parent.add_child(h)
	_loop_start(h, loop_id, 1.0)
	_handles.append(h)
	return h


## Called by a handle when it leaves the tree / is freed, and by Fx when a fire runs out.
func _on_handle_gone(node: Node) -> void:
	var h := node as FxHandle
	if h == null or h.released:
		return
	h.released = true
	for idx in h.emitters:
		_loop_release(idx)
	h.emitters = PackedInt32Array()
	h.base_ratio = PackedFloat32Array()
	h.offsets = PackedVector3Array()
	if h.light_index >= 0 and h.light_index < _fire_lights.size():
		_fire_light_owner[h.light_index] = null
		_fire_lights[h.light_index].visible = false
		h.light_index = -1
	if h.audio_index >= 0 and h.audio_index < _fire_audio.size():
		_fire_audio_owner[h.audio_index] = null
		var player: Variant = _fire_audio[h.audio_index]
		if is_instance_valid(player):
			(player as Node).call("stop")
		h.audio_index = -1
	_handles.erase(h)
	_fires.erase(h)


func _loop_start(h: FxHandle, loop_id: String, scale: float) -> void:
	var def: LoopDef = _loops.get(loop_id, null)
	if def == null:
		return
	var i := _loop_find_free(def.pool)
	if i < 0:
		return
	_reserve_slot(i)
	var p := _em[i]
	var s := scale * def.size
	if p.draw_pass_1 != def.mesh:
		p.draw_pass_1 = def.mesh
	if p.material_override != def.mat:
		p.material_override = def.mat
	p.amount_ratio = clampf(def.ratio * _amount_scale, 0.03, 1.0)
	p.set_instance_shader_parameter(&"size_mul", s)
	p.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * s), h.global_position + def.offset * scale)
	p.visible = true
	p.restart()
	p.emitting = true
	_serial += 1
	_em_until[i] = INF
	_em_order[i] = _serial
	_em_live[i] = float(def.pool.amount) * p.amount_ratio
	_em_owner[i] = h
	h.emitters.append(i)
	h.base_ratio.append(def.ratio)
	h.offsets.append(def.offset * scale)
	h.applied_strength = h.strength


func _loop_release(i: int) -> void:
	if i < _loop_first or i >= _em.size():
		return
	_em[i].emitting = false
	_em_owner[i] = null
	_em_until[i] = _now + _em[i].lifetime + 0.1


## A loop emitter of `pool` that nobody holds: prefer one whose particles are gone, else the one
## closest to being done, else take over the emitter of the pool's oldest handle (that handle
## simply stops emitting). Fire pools are as large as MAX_FIRES, so fires are never robbed.
func _loop_find_free(pool: LoopPool) -> int:
	var best := -1
	var best_until := INF
	var oldest := -1
	var oldest_order := 0x7FFFFFFFFFFFFFFF
	for i in range(pool.first, pool.first + pool.count):
		var ov: Variant = _em_owner[i]
		if ov != null and is_instance_valid(ov):
			if _em_order[i] < oldest_order:
				oldest_order = _em_order[i]
				oldest = i
			continue
		if _em_until[i] <= _now or _em_until[i] == INF:
			return i
		if _em_until[i] < best_until:
			best_until = _em_until[i]
			best = i
	if best >= 0:
		return best
	if oldest >= 0:
		var h := _em_owner[oldest] as FxHandle
		if h != null:
			var k := h.emitters.find(oldest)
			if k >= 0:
				h.emitters.remove_at(k)
				h.base_ratio.remove_at(k)
				h.offsets.remove_at(k)
		_loop_release(oldest)
		return oldest
	return -1


# =================================================================================================
# particle bursts
# =================================================================================================

## Triggers one pooled burst. The basis orients the burst (+Y = main direction) and its scale
## multiplies emission radius and velocities; `size` multiplies the particle size (default: the
## basis scale, so a bigger effect is bigger in every respect).
func _emit(id: StringName, pos: Vector3, basis: Basis, mesh: Mesh, mat: Material, ratio: float = 1.0,
		size: float = -1.0) -> void:
	var def: BurstDef = _bursts.get(id, null)
	if def == null or mat == null:
		return
	var i := def.first + def.next
	def.next = (def.next + 1) % def.count
	_reserve_slot(i)
	var p := _em[i]
	p.global_transform = Transform3D(basis, pos)
	if p.draw_pass_1 != mesh:
		p.draw_pass_1 = mesh
	if p.material_override != mat:
		p.material_override = mat
	p.amount_ratio = clampf(ratio * _amount_scale, 0.08, 1.0)
	p.set_instance_shader_parameter(&"size_mul", size if size > 0.0 else basis.x.length())
	p.visible = true
	p.restart()
	p.emitting = true
	_serial += 1
	_em_until[i] = _now + def.life + 0.15
	_em_order[i] = _serial
	_em_live[i] = float(def.amount) * p.amount_ratio


## Global cap: if MAX_ACTIVE_SYSTEMS other systems are still alive, the oldest burst is cut.
func _reserve_slot(i: int) -> void:
	var active := 0
	var oldest := -1
	var oldest_order := 0x7FFFFFFFFFFFFFFF
	for k in _em.size():
		if k == i or _em_until[k] <= _now:
			continue
		active += 1
		if _em_is_loop[k] == 0 and _em_order[k] < oldest_order:
			oldest_order = _em_order[k]
			oldest = k
	if active >= MAX_ACTIVE_SYSTEMS and oldest >= 0:
		_em[oldest].emitting = false
		_em[oldest].visible = false
		_em_until[oldest] = 0.0


func _splash_visual(position: Vector3, s: float) -> void:
	if _too_far(position, _fx_range):
		return
	_emit(&"droplets", position + Vector3(0.0, 0.05, 0.0), Basis.from_scale(Vector3.ONE * s), _assets.pebble,
			_assets.lit(C_WATER, 0.12), 1.0)
	if s >= 0.6:
		_emit(&"puff", position + Vector3(0.0, 0.15, 0.0), Basis.from_scale(Vector3.ONE * (2.2 * s)), _assets.blob,
				_assets.lit(C_FOAM, 0.08), 1.0, 1.05 * s)
	water_ring(position, s)


# =================================================================================================
# decals
# =================================================================================================

func _place_decal(position: Vector3, normal: Vector3, forward: Vector3, kind: String, size: float,
		length: float, parent: Node3D) -> void:
	if _decal_cap <= 0 or _root == null or not _root.is_inside_tree():
		return
	var i := _decal_next
	_decal_next = (_decal_next + 1) % _decal_cap
	var d := _decals[i]
	if not is_instance_valid(d):
		# the previous node was lent to a body that has been freed since
		d = _make_decal()
		_decals[i] = d
		_root.add_child(d)
	elif d.get_parent() != _root:
		d.get_parent().remove_child(d)
		_root.add_child(d)
	var n := normal
	var f := forward - n * forward.dot(n)
	var roll_random := f.length_squared() < 0.0001
	if roll_random:
		f = n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD)
	f = f.normalized()
	var x := n.cross(f).normalized()
	var b := Basis(x, n, x.cross(n))
	if roll_random:
		b = b * Basis(Vector3.UP, randf_range(0.0, TAU))
	var sz := maxf(size, 0.02)
	var depth := 0.22
	var mix := 1.0
	match kind:
		"scorch":
			depth = clampf(sz * 0.35, 0.5, 1.6)
		"blood":
			depth = 0.4
		"oil":
			depth = 0.4
		"skid":
			depth = 0.3
			mix = 0.85
		"bullet":
			pass
		_:
			kind = "bullet"
	d.texture_albedo = _assets.decal_texture(kind)
	d.size = Vector3(sz, depth, length if length > 0.0 else sz)
	d.albedo_mix = mix
	d.normal_fade = 0.35 if kind == "bullet" else 0.15
	d.global_transform = Transform3D(b, position)
	d.visible = true
	_decals_placed += 1
	if parent != null and is_instance_valid(parent) and parent.is_inside_tree():
		_root.remove_child(d)
		parent.add_child(d)
		d.global_transform = Transform3D(b, position)


func _make_decal() -> Decal:
	var d := Decal.new()
	d.visible = false
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.distance_fade_enabled = true
	d.distance_fade_begin = 45.0
	d.distance_fade_length = 12.0
	return d


# =================================================================================================
# helpers
# =================================================================================================

static func _safe_normal(n: Vector3) -> Vector3:
	if not n.is_finite() or n.length_squared() < 0.0001:
		return Vector3.UP
	return n.normalized()


## Orthonormal basis whose +Y is `n`, uniformly scaled by `s`.
static func _basis_up(n: Vector3, s: float) -> Basis:
	var t := n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD).normalized()
	return Basis(t, n, t.cross(n)) * Basis.from_scale(Vector3(s, s, s))


static func _normalize_surface(s: String) -> String:
	if SURFACES.has(s):
		return s
	match s:
		"road", "tarmac", "pavement":
			return "asphalt"
		"stone", "brick", "plaster", "tile", "rock":
			return "concrete"
		"steel", "iron", "car":
			return "metal"
		"soil", "mud", "gravel":
			return "dirt"
		"leaves", "bush", "tree", "hedge":
			return "foliage"
		"beach":
			return "sand"
		"body", "skin":
			return "flesh"
		"tire", "tyre":
			return "rubber"
		"window":
			return "glass"
	return "concrete"


func _too_far(pos: Vector3, limit: float) -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var cam := vp.get_camera_3d()
	if cam == null:
		return false
	return cam.global_position.distance_squared_to(pos) > limit * limit


func _take_puff_token() -> bool:
	if _puff_tokens < 1.0:
		return false
	_puff_tokens -= 1.0
	return true


func _space() -> PhysicsDirectSpaceState3D:
	if not is_inside_tree():
		return null
	var vp := get_viewport()
	if vp == null:
		return null
	var w := vp.find_world_3d()
	return w.direct_space_state if w != null else null


## First static-world surface below `position` ({} if none within `max_dist`).
func _ground_below(position: Vector3, max_dist: float) -> Dictionary:
	var space := _space()
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(position + Vector3(0.0, 0.3, 0.0),
			position - Vector3(0.0, max_dist, 0.0), Layers.WORLD)
	return space.intersect_ray(q)


func _audio_ok() -> bool:
	if _audio == null or not is_instance_valid(_audio):
		_audio = get_node_or_null("/root/Audio")
	return _audio != null


func _play_at(id: String, pos: Vector3, volume_db: float, pitch: float, max_dist: float) -> void:
	if _audio_ok() and _audio.has_method("play_at"):
		_audio.call("play_at", id, pos, volume_db, pitch, max_dist, "SFX")


func _impact_audio(id: String, pos: Vector3, pitch: float) -> void:
	if _now - _last_impact_audio < 0.035:
		return
	_last_impact_audio = _now
	_play_at(id, pos, -3.0, pitch * randf_range(0.92, 1.1), 45.0)


# =================================================================================================
# pool construction (once)
# =================================================================================================

func _build() -> void:
	if _built:
		return
	_built = true
	_assets = FxAssets.new()
	_blast = FxBlast.new()
	_root = Node3D.new()
	_root.name = "FxPool"
	add_child(_root)
	_fire_query.shape = _fire_shape
	_fire_query.collision_mask = FIRE_MASK
	_fire_query.collide_with_areas = false
	_build_bursts()
	_build_loops()
	_build_transients()
	for i in MAX_DECALS:
		var d := _make_decal()
		_root.add_child(d)
		_decals.append(d)


func _add_burst(id: StringName, pool: int, amount: int, life: float, reach: float, proc: ParticleProcessMaterial) -> void:
	var def := BurstDef.new()
	def.first = _em.size()
	def.count = pool
	def.life = life
	def.amount = amount
	_bursts[id] = def
	for i in pool:
		var p := _new_emitter(amount, life, reach)
		p.name = "%s_%d" % [id, i]
		p.one_shot = true
		p.explosiveness = 1.0
		p.process_material = proc
		_register_emitter(p, false)


func _new_emitter(amount: int, life: float, reach: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.fixed_fps = 0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.visibility_aabb = AABB(Vector3(-reach, -reach, -reach), Vector3(reach, reach, reach) * 2.0)
	p.visible = false
	return p


func _register_emitter(p: GPUParticles3D, is_loop: bool) -> void:
	_root.add_child(p)
	_em.append(p)
	_em_until.append(0.0)
	_em_order.append(0)
	_em_live.append(0.0)
	_em_is_loop.append(1 if is_loop else 0)
	_em_owner.append(null)


func _build_bursts() -> void:
	var a := _assets
	# small dust / blood puff at an impact point (+Y = surface normal)
	_add_burst(&"puff", 12, 6, 0.8, 5.0, a.proc({"spread": 55.0, "vel": Vector2(0.7, 2.0),
			"gravity": Vector3(0, 0.5, 0), "damping": Vector2(1.5, 2.5), "scale": Vector2(0.24, 0.5),
			"curve": a.curve_pop, "shape": "sphere", "r": 0.06, "angle": true, "spin": 90.0, "vary": true}))
	# bigger, slower puff (smoke_puff, tyre smoke, dust)
	_add_burst(&"smoke", 14, 5, 1.1, 6.0, a.proc({"spread": 35.0, "vel": Vector2(0.5, 1.4),
			"gravity": Vector3(0, 0.7, 0), "damping": Vector2(0.4, 0.8), "scale": Vector2(0.32, 0.62),
			"curve": a.curve_smoke, "shape": "sphere", "r": 0.14, "angle": true, "spin": 60.0, "vary": true}))
	# chips / shards / splinters with gravity
	_add_burst(&"chips", 10, 8, 0.75, 6.0, a.proc({"spread": 50.0, "vel": Vector2(2.4, 5.5),
			"gravity": Vector3(0, -13.0, 0), "scale": Vector2(0.08, 0.17), "curve": a.curve_hold,
			"angle": true, "spin": 620.0, "vary": true, "life_rand": 0.3}))
	# sparks: streaks aligned with their velocity
	_add_burst(&"sparks", 8, 16, 0.55, 9.0, a.proc({"spread": 62.0, "vel": Vector2(4.5, 12.0),
			"gravity": Vector3(0, -11.0, 0), "scale": Vector2(0.35, 0.8), "curve": a.curve_hold,
			"align_y": true, "life_rand": 0.4}))
	# water droplets
	_add_burst(&"droplets", 6, 16, 0.9, 9.0, a.proc({"spread": 34.0, "vel": Vector2(3.0, 7.0),
			"gravity": Vector3(0, -9.8, 0), "scale": Vector2(0.1, 0.22), "curve": a.curve_hold,
			"shape": "sphere", "r": 0.12, "angle": true, "spin": 200.0, "life_rand": 0.25}))
	# explosion: emissive fireball blobs
	_add_burst(&"fireball", 4, 16, 0.85, 16.0, a.proc({"radial": Vector2(4.0, 9.0), "damping": Vector2(7.0, 10.0),
			"gravity": Vector3(0, 1.6, 0), "scale": Vector2(1.3, 2.3), "curve": a.curve_fire,
			"ramp": a.ramp_fire, "shape": "sphere", "r": 0.8, "angle": true, "spin": 70.0, "life_rand": 0.25,
			"hue": 0.03}))
	# explosion: dark smoke that outlives the fireball
	_add_burst(&"blast_smoke", 4, 14, 2.6, 20.0, a.proc({"spread": 55.0, "vel": Vector2(0.6, 3.0),
			"radial": Vector2(0.8, 2.4), "damping": Vector2(1.0, 1.6),
			"gravity": Vector3(0, 1.7, 0), "scale": Vector2(1.3, 2.5), "curve": a.curve_smoke,
			"ramp": a.ramp_blast_smoke, "shape": "sphere", "r": 1.0, "angle": true, "spin": 35.0,
			"vary": true, "life_rand": 0.3}))
	# explosion: heavy chunks / glass
	_add_burst(&"debris", 4, 10, 1.4, 20.0, a.proc({"spread": 68.0, "vel": Vector2(6.0, 13.0),
			"gravity": Vector3(0, -15.0, 0), "scale": Vector2(0.18, 0.42), "curve": a.curve_hold,
			"shape": "sphere", "r": 0.3, "angle": true, "spin": 540.0, "vary": true, "life_rand": 0.3}))
	# ground-hugging ring of dust (explosion, rotor wash)
	_add_burst(&"dust_ring", 4, 10, 1.0, 14.0, a.proc({"radial": Vector2(5.5, 9.5), "damping": Vector2(9.0, 13.0),
			"gravity": Vector3(0, 0.5, 0), "scale": Vector2(0.5, 1.0), "curve": a.curve_pop,
			"shape": "ring", "r": 0.7, "ring_h": 0.15, "angle": true, "spin": 60.0, "vary": true}))
	# pickup / money sparkle
	_add_burst(&"sparkle", 4, 8, 0.8, 4.0, a.proc({"spread": 40.0, "vel": Vector2(0.7, 1.7),
			"gravity": Vector3(0, 0.4, 0), "scale": Vector2(0.07, 0.13), "curve": a.curve_pop,
			"shape": "sphere", "r": 0.28, "angle": true, "spin": 300.0}))


func _add_loop_pool(count: int, amount: int, life: float, reach: float, proc: ParticleProcessMaterial) -> LoopPool:
	var pool := LoopPool.new()
	pool.first = _em.size()
	pool.count = count
	pool.amount = amount
	pool.life = life
	for i in count:
		var p := _new_emitter(amount, life, reach)
		p.name = "loop_%d" % _em.size()
		p.one_shot = false
		p.explosiveness = 0.0
		p.process_material = proc
		_register_emitter(p, true)
	return pool


func _add_loop(id: String, pool: LoopPool, ratio: float, mesh: Mesh, mat: Material, size: float = 1.0,
		offset: Vector3 = Vector3.ZERO) -> void:
	var def := LoopDef.new()
	def.pool = pool
	def.mesh = mesh
	def.mat = mat
	def.ratio = ratio
	def.size = size
	def.offset = offset
	_loops[id] = def


## Looping emitters (fire, attached smoke, trails). Every pool keeps the process material it was
## created with: swapping process materials on a live GPUParticles3D makes the renderer print
## "uniform_set is null" for a frame, so looks only differ by mesh / material / density / size.
func _build_loops() -> void:
	var a := _assets
	_loop_first = _em.size()
	var flames := _add_loop_pool(MAX_FIRES, 24, 0.65, 8.0, a.proc({"spread": 10.0,
			"vel": Vector2(1.6, 3.0), "gravity": Vector3(0, 1.2, 0), "scale": Vector2(0.5, 1.05),
			"curve": a.curve_fire, "ramp": a.ramp_flame, "shape": "box", "box": Vector3(0.3, 0.05, 0.3),
			"angle": true, "rotate_y": true, "life_rand": 0.3, "hue": 0.02}))
	var fire_smoke := _add_loop_pool(MAX_FIRES, 10, 1.7, 12.0, a.proc({"spread": 12.0,
			"vel": Vector2(1.8, 2.8), "gravity": Vector3(0, 0.6, 0), "scale": Vector2(0.35, 0.75),
			"curve": a.curve_smoke, "ramp": a.ramp_fire_smoke, "shape": "sphere", "r": 0.2,
			"angle": true, "spin": 40.0, "vary": true}))
	var smoke := _add_loop_pool(8, 20, 2.0, 12.0, a.proc({"spread": 14.0, "vel": Vector2(1.6, 2.6),
			"gravity": Vector3(0, 0.5, 0), "scale": Vector2(0.6, 1.1), "curve": a.curve_smoke,
			"ramp": a.ramp_smoke_age, "shape": "sphere", "r": 0.18, "angle": true, "spin": 50.0, "vary": true}))
	var rocket := _add_loop_pool(3, 30, 0.9, 10.0, a.proc({"spread": 180.0, "vel": Vector2(0.1, 0.5),
			"gravity": Vector3(0, 0.3, 0), "scale": Vector2(0.4, 0.7), "curve": a.curve_pop,
			"shape": "sphere", "r": 0.06, "angle": true, "spin": 60.0, "vary": true}))
	var puffs := _add_loop_pool(6, 12, 1.0, 8.0, a.proc({"spread": 40.0, "vel": Vector2(0.4, 1.3),
			"gravity": Vector3(0, 0.6, 0), "scale": Vector2(0.3, 0.6), "curve": a.curve_smoke,
			"shape": "sphere", "r": 0.1, "angle": true, "spin": 60.0, "vary": true}))
	var wake := _add_loop_pool(3, 20, 1.5, 10.0, a.proc({"spread": 80.0, "flat": 0.9, "vel": Vector2(0.5, 2.2),
			"scale": Vector2(0.3, 0.7), "curve": a.curve_pop, "shape": "sphere", "r": 0.25,
			"angle": true, "spin": 30.0, "vary": true}))
	_add_loop("flames", flames, 1.0, a.flame, a.glow(Color.WHITE, 1.5, 0.0, 0.35), 1.0, Vector3(0.0, 0.12, 0.0))
	_add_loop("fire_smoke", fire_smoke, 1.0, a.blob, a.lit(Color.WHITE), 1.0, Vector3(0.0, 1.1, 0.0))
	_add_loop("smoke_light", smoke, 0.7, a.blob, a.lit(C_SMOKE_LIGHT), 0.75)
	_add_loop("smoke_heavy", smoke, 0.85, a.blob, a.lit(C_SMOKE_HEAVY), 1.0)
	_add_loop("smoke_black", smoke, 1.0, a.blob, a.lit(C_SMOKE_BLACK), 1.3)
	_add_loop("trail_rocket", rocket, 1.0, a.blob, a.lit(C_SMOKE_LIGHT))
	_add_loop("trail_tyre", puffs, 1.0, a.blob, a.lit(C_TYRE_SMOKE))
	_add_loop("trail_dust", puffs, 1.0, a.blob, a.lit(C_DUST), 1.2)
	_add_loop("trail_exhaust", puffs, 0.6, a.blob, a.lit(C_SMOKE_HEAVY), 0.45)
	_add_loop("trail_wake", wake, 0.9, a.blob, a.lit(C_FOAM, 0.08))


func _new_mesh(mesh: Mesh, mat: Material, node_name: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	m.visible = false
	_root.add_child(m)
	return m


func _new_light(node_name: String, color: Color, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = node_name
	l.light_color = color
	l.omni_range = light_range
	l.omni_attenuation = 1.2
	l.light_specular = 0.2
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 80.0
	l.distance_fade_length = 25.0
	l.visible = false
	_root.add_child(l)
	return l


func _build_transients() -> void:
	var a := _assets
	var billboard_box := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	for i in EXPLOSION_SLOTS:
		var flash := _new_mesh(a.quad, a.sprite_add, "ex_flash_%d" % i)
		flash.custom_aabb = billboard_box
		_ex_flash.append(flash)
		_ex_ring.append(_new_mesh(a.plane, a.ring_mat, "ex_ring_%d" % i))
		_ex_t0.append(-1.0)
		_ex_size.append(1.0)
		_ex_ring_r.append(1.0)
	for i in MAX_EXPLOSION_LIGHTS:
		_ex_lights.append(_new_light("ex_light_%d" % i, Color(1.0, 0.72, 0.4), 18.0))
		_exl_t0.append(-1.0)
		_exl_energy.append(0.0)
	for i in MAX_LIT_FIRES:
		_fire_lights.append(_new_light("fire_light_%d" % i, C_FIRE_LIGHT, 7.0))
		_fire_light_owner.append(null)
	_mz_light = _new_light("muzzle_light", Color(1.0, 0.8, 0.5), 5.0)
	var star_mat := a.add(Color(1.0, 0.8, 0.4, 1.0))
	for i in MUZZLE_POOL:
		_mz_star.append(_new_mesh(a.star, star_mat, "mz_star_%d" % i))
		var g := _new_mesh(a.quad, a.sprite_add, "mz_glow_%d" % i)
		g.custom_aabb = billboard_box
		g.set_instance_shader_parameter("glow_color", Color(1.0, 0.55, 0.2, 1.0))
		_mz_glow.append(g)
		_mz_ref.append(null)
		_mz_until.append(0.0)
		_mz_roll.append(0.0)
		_mz_scale.append(1.0)
	var tracer_mat := a.add(Color(1.0, 0.8, 0.4, 1.0))
	for i in TRACER_POOL:
		_tr.append(_new_mesh(a.streak, tracer_mat, "tracer_%d" % i))
		_tr_from.append(Vector3.ZERO)
		_tr_dir.append(Vector3.FORWARD)
		_tr_dist.append(0.0)
		_tr_len.append(0.0)
		_tr_speed.append(0.0)
		_tr_t0.append(0.0)
	var shell_mat := a.lit(C_BRASS, 0.15, 0.0)
	for i in SHELL_POOL:
		_sh.append(_new_mesh(a.shell, shell_mat, "shell_%d" % i))
		_sh_pos.append(Vector3.ZERO)
		_sh_vel.append(Vector3.ZERO)
		_sh_axis.append(Vector3.UP)
		_sh_t0.append(-1.0)
	for i in RING_POOL:
		_wr.append(_new_mesh(a.plane, a.ring_mat, "water_ring_%d" % i))
		_wr_t0.append(-1.0)
		_wr_scale.append(1.0)
