class_name PedSystem
extends Node3D
## World system "peds" (BootManifest): the pedestrian population and the manager of EVERY NPC body.
##
## * spawn_npc(archetype, pos, opts) (= Game.spawn_npc) for all modules (W2.2 options).
## * Ambient population: pooled NpcBase bodies spawned on WalkGraph points 35-90 m from the focus
##   (player, or set_focus_override), preferably out of view, despawned beyond 110 m. Cap from
##   Settings "ped_density" (<= 40), fewer at night and in rain, density + archetype mix by district.
##   Gang groups hang out at the world's "gang" spawn points while the focus is near.
## * One loop drives every NPC (ARCHITECTURE section 10): physics_tick (movement), think_tick
##   (senses + brain at 10 / 3.3 / 1 Hz by tier), anim_tick (animator, 30 / 8 / 2 Hz by tier).
##   Tiers by distance to the focus: 0 < 45 m (move_and_slide), 1 < 110 m (kinematic glide), 2 beyond.
## * Central stimulus dispatch (no per-NPC signal connections): EventBus.noise_emitted -> hear_noise,
##   EventBus.crime_committed -> witnesses (notify_crime), the player's aimed firearm -> notify_threatened,
##   the player walking into people -> notify_bumped, local avoidance between characters.
## * Witness reports: submit_witness_report() -> Wanted.report_witnessed (fallback: report_crime(force)).

const NpcScript := preload("res://gta/code/ai/npc_base.gd")

const MAX_CAP := 40
const BASE_CAP := 28                    ## ambient pedestrians at ped_density 1.0 (x1.5 -> 40 max)
const MIN_SPAWN := 35.0
const MAX_SPAWN := 90.0
const DESPAWN_DIST := 110.0
const TIER0_DIST := 45.0
const TIER1_DIST := 110.0
const SPAWN_INTERVAL := 0.2
const TIER_INTERVAL := 0.25
const STIMULUS_INTERVAL := 0.16
const VEHICLE_CACHE_INTERVAL := 0.25
const GANG_INTERVAL := 1.0
const GANG_ACTIVATE := 105.0
const GANG_RELEASE := 150.0
const GANG_RESPAWN := 240.0
const GANG_MAX_PER_SPOT := 4
const POOL_MAX := 16
const MAX_CALLERS_PER_CRIME := 2
const AVOID_PER_FRAME := 10
const THINK_INTERVAL: Array[float] = [0.1, 0.3, 1.0]

const DISTRICT_DENSITY := {
	"downtown": 1.0, "midtown": 1.0, "waterfront": 0.85, "beach": 0.8, "residential": 0.6,
	"industrial": 0.42, "hill": 0.22, "airport": 0.25, "ocean": 0.0,
}
## archetype id -> weight per district ("default" for the rest)
const DISTRICT_MIX := {
	"default": {"civilian_m": 1.0, "civilian_f": 1.0, "civilian_tough": 0.07},
	"industrial": {"civilian_m": 1.0, "civilian_f": 0.45, "civilian_tough": 0.35},
	"waterfront": {"civilian_m": 1.0, "civilian_f": 1.0, "civilian_tough": 0.12},
	"beach": {"civilian_m": 1.0, "civilian_f": 1.15, "civilian_tough": 0.05},
	"hill": {"civilian_m": 1.0, "civilian_f": 1.0},
}
## [CharacterVisual archetype, chance] that replaces the archetype's own look in that district
const DISTRICT_VISUAL := {
	"downtown": ["business", 0.32], "midtown": ["business", 0.1], "beach": ["beach", 0.62],
	"waterfront": ["beach", 0.2], "residential": ["beach", 0.08],
}
## how far (m) a crime is noticed by ear; beyond that only by sight
const CRIME_HEAR := {
	"gunfire": 70.0, "explosion": 110.0, "murder": 22.0, "cop_murder": 22.0, "assault": 14.0,
	"cop_assault": 14.0, "hit_and_run": 25.0, "robbery": 18.0, "vehicle_theft": 10.0,
	"police_vehicle_theft": 12.0, "collision_major": 30.0, "disturbance": 10.0,
	"property_damage": 12.0,
}

var enabled: bool = true
var density_mult: float = 1.0
var focus_override: Vector3 = Vector3.INF
## chance that a qualified witness (one of the first MAX_CALLERS_PER_CRIME) phones it in
var witness_call_chance: float = 0.85
var stats: Dictionary = {
	"spawned": 0, "despawned": 0, "pooled_reuse": 0, "noise_events": 0, "crime_events": 0,
	"witness_reports": 0, "witness_cancelled": 0, "harm_reports": 0,
	"phys_us": 0.0, "anim_us": 0.0, "phys_us_max": 0.0, "anim_us_max": 0.0, "spawn_us_max": 0.0,
	"spawn_us_total": 0.0,
}

var _npcs: Array[NpcBase] = []
var _pool: Array[NpcBase] = []
var _gang_spots: Array = []            ## {pos, yaw, members: Array, active, cooldown}
var _benches: Array = []               ## {xform: Transform3D (spawn point), seat: Variant (Transform3D or null), next_check: float}
var _bench_taken: Dictionary = {}      ## bench index -> npc instance id
var _veh_cache := PackedVector3Array() ## pos, vel pairs of moving vehicles
var _pending_calls: Dictionary = {}    ## crime id -> callers still on the phone
var _bump_cd: Dictionary = {}          ## npc instance id -> clock time
var _spawn_t: float = 0.0
var _tier_t: float = 0.0
var _stim_t: float = 0.0
var _veh_t: float = 0.0
var _gang_t: float = 0.0
var _avoid_cursor: int = 0
var _reporting: bool = false
var _sight_only: bool = false          ## the crime being reported right now was silent (takedown)
var _focus: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _walk: Object = null
var _ambient_count: int = 0
var _seed_counter: int = 0


func _ready() -> void:
	process_priority = 5
	process_physics_priority = 5


func _exit_tree() -> void:
	# pooled bodies live outside the tree: free them with the system
	for npc in _pool:
		if is_instance_valid(npc):
			npc.free()
	_pool.clear()


func setup() -> void:
	_rng.seed = Game.rng.randi()
	if not EventBus.noise_emitted.is_connected(_on_noise):
		EventBus.noise_emitted.connect(_on_noise)
	if not EventBus.crime_committed.is_connected(_on_crime):
		EventBus.crime_committed.connect(_on_crime)
	_refresh_world_data()
	_prewarm(6)


## Builds a few bodies at boot (first humanoid instance loads the part library, ~70 ms) so the
## first spawns in free roam do not hitch.
func _prewarm(n: int) -> void:
	var root := Game.get_entities_root()
	if root == null:
		return
	# brains and the weapon models NPCs carry (GLB loads would hitch the first spawn otherwise)
	for path: String in ["res://gta/code/ai/brains/ai_brain_civilian.gd", "res://gta/code/ai/brains/ai_brain_gang.gd",
			"res://gta/code/ai/brains/ai_brain_staff.gd"]:
		NpcBase.load_script(path)
	var wm := NpcBase.load_script(NpcBase.WEAPON_MODEL_SCRIPT)
	if wm != null:
		for wid: String in ["pistol", "smg", "bat", "carbine", "assault_rifle"]:
			var m: Variant = wm.call("create", wid)
			if m is Node and is_instance_valid(m):
				(m as Node).free()
	for k in n:
		var npc: NpcBase = NpcScript.new()
		npc.managed = true
		root.add_child(npc)
		npc.global_position = Vector3(0.0, -500.0, 0.0)
		if k == 0 and npc.visual != null and npc.visual.has_method("apply_appearance"):
			# the first dressed character builds the shared part library: pay that at boot
			var vs := NpcBase.load_script(NpcBase.VISUAL_SCRIPT)
			if vs != null:
				npc.visual.call("apply_appearance", vs.call("make_appearance", "civilian_m", 1))
		root.remove_child(npc)
		npc.reset_for_pool()
		_pool.append(npc)


func _refresh_world_data() -> void:
	var w := Game.world
	if w == null or not is_instance_valid(w):
		return
	var walk: Variant = w.get("walk")
	_walk = walk as Object if walk is Object else null
	if w.has_method("get_spawn_points"):
		_gang_spots.clear()
		for xf: Transform3D in w.call("get_spawn_points", "gang"):
			_gang_spots.append({"pos": xf.origin, "yaw": xf.basis.get_euler().y, "members": [], "active": false, "cooldown": 0.0})
		_benches.clear()
		# benches placed by the props system (MultiMesh instances: no per-bench node) ...
		var props := Game.get_system("props")
		if props != null and props.has_method("find_instances") and props.has_method("get_instance_transform"):
			for pid: String in ["bench", "bench_park"]:
				for i: int in props.call("find_instances", pid):
					var bx: Transform3D = props.call("get_instance_transform", i)
					_benches.append({"xform": bx, "seat": _seat_from_bench(bx), "next_check": 0.0, "prop": i})
		# ... else the world's bench points, used once a bench collider is found there
		if _benches.is_empty():
			for xf: Transform3D in w.call("get_spawn_points", "bench"):
				_benches.append({"xform": xf, "seat": null, "next_check": 0.0, "prop": -1})


# =================================================================================================
# public API
# =================================================================================================

## W2.2 spawn. opts: yaw, brain (Script | Node), weapon, hostile, persistent, vehicle, seat,
## appearance; extras: visual (CharacterVisual archetype), activity ("talk", "sit", "idle"),
## partner, bench, home, group, parent.
func spawn_npc(archetype_id: String, position: Vector3, opts: Dictionary = {}) -> Node3D:
	var arch: Variant = Registry.get_def("npc_archetypes", archetype_id)
	if arch == null:
		push_warning("PedSystem.spawn_npc: unknown archetype '%s' (using civilian_m)" % archetype_id)
		arch = Registry.get_def("npc_archetypes", "civilian_m")
		if arch == null:
			return null
	var npc: NpcBase = null
	while not _pool.is_empty() and npc == null:
		var c: NpcBase = _pool.pop_back()
		if is_instance_valid(c):
			npc = c
			stats["pooled_reuse"] = int(stats["pooled_reuse"]) + 1
	if npc == null:
		npc = NpcScript.new()
	var t_spawn := Time.get_ticks_usec()
	npc.managed = true
	var parent: Node = opts.get("parent", null)
	if parent == null or not is_instance_valid(parent):
		parent = Game.get_entities_root()
	if parent == null:
		parent = self
	parent.add_child(npc)
	npc.global_position = position
	npc.velocity = Vector3.ZERO
	_seed_counter += 1
	npc.configure(arch as Resource, opts, _rng.randi() ^ _seed_counter)
	npc.think_accum = _rng.randf() * 0.1
	_npcs.append(npc)
	npc.set_sim_tier(_tier_for(npc.global_position))
	stats["spawned"] = int(stats["spawned"]) + 1
	var sus := float(Time.get_ticks_usec() - t_spawn)
	stats["spawn_us_max"] = maxf(float(stats["spawn_us_max"]), sus)
	stats["spawn_us_total"] = float(stats["spawn_us_total"]) + sus
	EventBus.npc_spawned.emit(npc)
	return npc


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		clear_all(false)


## Removes every NPC that is not persistent (persistent too with include_persistent).
func clear_all(include_persistent: bool = false) -> void:
	for i in range(_npcs.size() - 1, -1, -1):
		var npc := _npcs[i]
		if not is_instance_valid(npc):
			_npcs.remove_at(i)
			continue
		if npc.persistent and not include_persistent:
			continue
		_despawn(npc, i)
	for spot: Dictionary in _gang_spots:
		spot["active"] = false
		spot["members"] = []
	_bench_taken.clear()
	_pending_calls.clear()


## Live (not dead) NPCs managed here: ambient peds + gang + everybody spawned through spawn_npc.
func get_npc_count() -> int:
	var n := 0
	for npc in _npcs:
		if is_instance_valid(npc) and not npc.is_dead:
			n += 1
	return n


## Live ambient pedestrians (the population; no gang groups, no persistent NPCs).
func get_ambient_count() -> int:
	return _ambient_count


## Living civilians (faction "civilian", not knocked down) within `radius` of `position`
## (Wanted uses it for indirect "somebody heard it" reports).
func count_near(position: Vector3, radius: float) -> int:
	var r2 := radius * radius
	var n := 0
	for npc in _npcs:
		if is_instance_valid(npc) and not npc.is_dead and npc.faction == "civilian" and npc.global_position.distance_squared_to(position) <= r2:
			n += 1
	return n


func get_npcs() -> Array:
	var out: Array = []
	for npc in _npcs:
		if is_instance_valid(npc):
			out.append(npc)
	return out


func set_focus_override(pos: Vector3) -> void:
	focus_override = pos


func clear_focus_override() -> void:
	focus_override = Vector3.INF


func set_density(mult: float) -> void:
	density_mult = clampf(mult, 0.0, 2.0)


## Called by the respawn system after death / arrest: the population restarts around the new spot.
func reset_for_respawn() -> void:
	clear_all(false)
	for npc in _npcs:
		if is_instance_valid(npc) and npc.brain != null and npc.brain.has_method("on_event"):
			npc.brain.call("on_event", npc, "reset", {})


func get_focus() -> Vector3:
	if focus_override != Vector3.INF:
		return focus_override
	if Game.has_player():
		return Game.get_player_position()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam != null else Vector3.ZERO


## Ambient pedestrians wanted around the focus right now.
func get_target_count() -> int:
	if not enabled or _walk == null:
		return 0
	var density := float(Settings.get_value("ped_density")) if Settings.get_value("ped_density") != null else 1.0
	var cap := mini(MAX_CAP, int(round(BASE_CAP * density * density_mult)))
	var district := _district_at(_focus)
	var dfac := float(DISTRICT_DENSITY.get(district, 0.5))
	var tfac := 1.0
	if WorldClock.has_method("is_night") and bool(WorldClock.is_night()):
		var h := float(WorldClock.get("hour"))
		tfac = 0.3 if (h >= 1.0 and h < 5.0) else 0.45
	var rfac := 1.0
	var rain: Variant = Weather.get("rain_intensity")
	if rain is float:
		rfac = lerpf(1.0, 0.45, clampf(float(rain), 0.0, 1.0))
	return int(round(cap * dfac * tfac * rfac))


func get_debug_info() -> Dictionary:
	var tiers := [0, 0, 0]
	for npc in _npcs:
		if is_instance_valid(npc):
			tiers[npc.sim_tier] += 1
	var d := stats.duplicate()
	d["npcs"] = _npcs.size()
	d["ambient"] = _ambient_count
	d["target"] = get_target_count()
	d["tiers"] = tiers
	d["pool"] = _pool.size()
	d["gang_active"] = _gang_spots.filter(func(s: Dictionary) -> bool: return bool(s["active"])).size()
	d["benches"] = _benches.size()
	d["benches_taken"] = _bench_taken.size()
	return d


# --- services for NPC bodies / brains -----------------------------------------------------------

## True when no vehicle will pass the crossing a -> b in the next few seconds.
func is_crossing_clear(a: Vector3, b: Vector3) -> bool:
	var mid := (a + b) * 0.5
	var half := a.distance_to(b) * 0.5
	var i := 0
	while i + 1 < _veh_cache.size():
		var p := _veh_cache[i]
		var v := _veh_cache[i + 1]
		i += 2
		var rel := mid - p
		rel.y = 0.0
		if rel.length_squared() > 2500.0:
			continue
		var speed := Vector2(v.x, v.z).length()
		if speed < 1.0:
			if _dist_point_segment(p, a, b) < 2.6:
				return false
			continue
		var vd := Vector3(v.x, 0.0, v.z) / speed
		var along := rel.dot(vd)
		if along < -4.0:
			continue
		var lateral := (rel - vd * along).length()
		if lateral > half + 3.0:
			continue
		if along / speed < 4.5:
			return false
	return true


## A free bench seat within `radius` of `near` that really has a bench model on it.
## Returns {transform, key} or {}.
func claim_bench(npc: Node, near: Vector3, radius: float) -> Dictionary:
	var checks := 0
	for i in _benches.size():
		if _bench_taken.has(i):
			continue
		var b: Dictionary = _benches[i]
		var xf: Transform3D = b["xform"]
		if xf.origin.distance_to(near) > radius:
			continue
		var seat: Variant = _resolve_bench(i)
		checks += 1
		if seat is Transform3D:
			_bench_taken[i] = npc.get_instance_id()
			return {"transform": seat, "key": i}
		if checks >= 3:
			break
	return {}


func release_bench(key: int) -> void:
	_bench_taken.erase(key)


## Extra bench point (props placed by other systems, tests). `xform` = where the bench stands.
## A bench model with a collider whose node name (or meta "prop_id") contains "bench" must be
## there for anybody to sit on it. Returns the bench key.
func add_bench_point(xform: Transform3D) -> int:
	_benches.append({"xform": xform, "seat": null, "next_check": 0.0, "prop": -1})
	return _benches.size() - 1


## Sitting spot of a bench model: just in front of its origin, facing its -Z (manifest: "sitter faces +Y").
static func _seat_from_bench(bx: Transform3D) -> Transform3D:
	var o := bx.orthonormalized()
	var fwd := -o.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), o.origin + fwd * 0.12)


## A civilian finished the phone call: the crime goes to Wanted.
func submit_witness_report(crime_id: String, position: Vector3, witness: Node) -> void:
	_pending_calls[crime_id] = maxi(int(_pending_calls.get(crime_id, 1)) - 1, 0)
	stats["witness_reports"] = int(stats["witness_reports"]) + 1
	if Wanted.has_method("report_witnessed"):
		Wanted.call("report_witnessed", crime_id, position, witness)
		return
	# contract stub without report_witnessed: report it ourselves (and do not re-witness it)
	_reporting = true
	EventBus.crime_reported.emit(crime_id, position)
	Wanted.report_crime(crime_id, position, {"instigator": Game.player, "force": true, "witness": witness})
	_reporting = false


func note_witness_cancelled(crime_id: String, _witness: Node, _why: String) -> void:
	_pending_calls[crime_id] = maxi(int(_pending_calls.get(crime_id, 1)) - 1, 0)
	stats["witness_cancelled"] = int(stats["witness_cancelled"]) + 1


func note_harm_report(_crime_id: String) -> void:
	stats["harm_reports"] = int(stats["harm_reports"]) + 1


## NpcBase wraps the Wanted.report_crime() of a SILENT harm (info.silent: stealth takedowns) in
## set_crime_sight_only(true) / (false): the crime_committed it causes is witnessed by sight only
## (no CRIME_HEAR earshot - a quiet choke hold 15 m behind somebody's back is not "heard").
func set_crime_sight_only(on: bool) -> void:
	_sight_only = on
	if on:
		stats["silent_crimes"] = int(stats.get("silent_crimes", 0)) + 1


# =================================================================================================
# main loops
# =================================================================================================

func _physics_process(delta: float) -> void:
	AiSenses.tick_clock(delta)
	var t0 := Time.get_ticks_usec()
	_focus = get_focus()
	var i := _npcs.size() - 1
	while i >= 0:
		var npc := _npcs[i]
		if not is_instance_valid(npc) or npc.is_queued_for_deletion():
			_npcs.remove_at(i)
			i -= 1
			continue
		if npc.is_inside_tree():
			npc.physics_tick(delta)
			npc.think_accum += delta
			if npc.think_accum >= THINK_INTERVAL[npc.sim_tier]:
				var acc := npc.think_accum
				npc.think_accum = 0.0
				npc.think_tick(acc)
		i -= 1
	_avoidance_slice()
	_tier_t -= delta
	if _tier_t <= 0.0:
		_tier_t = TIER_INTERVAL
		_update_tiers_and_despawn()
	_veh_t -= delta
	if _veh_t <= 0.0:
		_veh_t = VEHICLE_CACHE_INTERVAL
		_refresh_vehicle_cache()
	_stim_t -= delta
	if _stim_t <= 0.0:
		_stim_t = STIMULUS_INTERVAL
		_player_stimuli()
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = SPAWN_INTERVAL
		if _walk == null and Game.world != null:
			_refresh_world_data()
		_spawn_step()
	_gang_t -= delta
	if _gang_t <= 0.0:
		_gang_t = GANG_INTERVAL
		_gang_step(GANG_INTERVAL)
	var us := float(Time.get_ticks_usec() - t0)
	stats["phys_us"] = lerpf(float(stats["phys_us"]), us, 0.05)
	stats["phys_us_max"] = maxf(float(stats["phys_us_max"]) * 0.999, us)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	for npc in _npcs:
		if is_instance_valid(npc) and npc.is_inside_tree():
			npc.anim_tick(delta)
	var us := float(Time.get_ticks_usec() - t0)
	stats["anim_us"] = lerpf(float(stats["anim_us"]), us, 0.05)
	stats["anim_us_max"] = maxf(float(stats["anim_us_max"]) * 0.999, us)


func _tier_for(pos: Vector3) -> int:
	var d := Vector2(pos.x - _focus.x, pos.z - _focus.z).length()
	if d < TIER0_DIST:
		return 0
	if d < TIER1_DIST:
		return 1
	return 2


func _update_tiers_and_despawn() -> void:
	var amb := 0
	var target := get_target_count()
	var excess_done := false
	for i in range(_npcs.size() - 1, -1, -1):
		var npc := _npcs[i]
		if not is_instance_valid(npc):
			_npcs.remove_at(i)
			continue
		var p := npc.global_position
		var d := Vector2(p.x - _focus.x, p.z - _focus.z).length()
		npc.set_sim_tier(0 if d < TIER0_DIST else (1 if d < TIER1_DIST else 2))
		if npc.is_dead:
			if npc.can_be_cleaned():
				_despawn(npc, i)
			continue
		if npc.persistent or npc.current_vehicle != null or npc.has_meta("gang_spot"):
			continue                 # owners / vehicles / gang spots decide about these
		if npc.ambient:
			amb += 1
		if d > DESPAWN_DIST:
			# every non-persistent NPC (ambient or spawned by another module) leaves beyond 110 m
			var was_ambient := npc.ambient
			_despawn(npc, i)
			if was_ambient:
				amb -= 1
		elif npc.ambient and amb > target + 2 and not excess_done and d > 40.0 and npc.state_tag != "phone" and not _in_view(p):
			# too many for the time of day / weather / density: one leaves per tier update, unseen
			excess_done = true
			_despawn(npc, i)
			amb -= 1
	_ambient_count = amb


func _despawn(npc: NpcBase, index: int = -1) -> void:
	if index >= 0 and index < _npcs.size() and _npcs[index] == npc:
		_npcs.remove_at(index)
	else:
		_npcs.erase(npc)
	if not is_instance_valid(npc):
		return
	stats["despawned"] = int(stats["despawned"]) + 1
	for k: int in _bench_taken.keys():
		if int(_bench_taken[k]) == npc.get_instance_id():
			_bench_taken.erase(k)
	_bump_cd.erase(npc.get_instance_id())
	if npc.current_vehicle != null and is_instance_valid(npc.current_vehicle):
		npc.exit_vehicle()           # free the seat first: the vehicle must not keep a dead reference
	var can_pool := not npc.is_dead and npc.current_vehicle == null and _pool.size() < POOL_MAX \
			and not npc.is_down and npc.get_parent() == Game.get_entities_root()
	if can_pool:
		npc.get_parent().remove_child(npc)
		npc.reset_for_pool()
		if npc.has_meta("gang_spot"):
			npc.remove_meta("gang_spot")
		_pool.append(npc)
	else:
		npc.queue_free()


# --- population ----------------------------------------------------------------------------------

func _spawn_step() -> void:
	if not enabled or _walk == null or not _walk.has_method("random_point"):
		return
	if _ambient_count >= get_target_count():
		return
	for attempt in 6:
		var p: Vector3 = _walk.call("random_point", _focus, MIN_SPAWN, MAX_SPAWN)
		if p == Vector3.INF:
			return
		if Game.is_in_water(p + Vector3(0.0, 0.2, 0.0)):
			continue
		var district := _district_at(p)
		if _rng.randf() > float(DISTRICT_DENSITY.get(district, 0.5)) + 0.05:
			continue
		var d := Vector2(p.x - _focus.x, p.z - _focus.z).length()
		if attempt < 4 and d < 70.0 and _in_view(p):
			continue
		if _crowded(p, 2.5):
			continue
		_spawn_ambient(p, district)
		return


func _spawn_ambient(p: Vector3, district: String) -> void:
	var arch_id := _pick_archetype(district)
	var opts := {"yaw": _rng.randf_range(-PI, PI)}
	var vis: Variant = DISTRICT_VISUAL.get(district, null)
	if vis is Array and _rng.randf() < float((vis as Array)[1]) and arch_id != "civilian_tough":
		opts["visual"] = str((vis as Array)[0])
	var r := _rng.randf()
	if r < 0.1:
		# sitting on a bench near the spawn point, when one is really there
		var bi := _free_bench_near(p, 30.0)
		if bi >= 0:
			var seat: Variant = _resolve_bench(bi)
			if seat is Transform3D:
				var st: Transform3D = seat
				opts["activity"] = "sit"
				opts["bench"] = st
				opts["bench_key"] = bi
				var npc := spawn_npc(arch_id, st.origin, opts)
				if npc != null:
					npc.set("ambient", true)
					_bench_taken[bi] = npc.get_instance_id()
					_ambient_count += 1
				return
	if r < 0.26 and _ambient_count + 2 <= get_target_count():
		# a small talking pair
		var side := Vector3(cos(float(opts["yaw"])), 0.0, -sin(float(opts["yaw"])))
		var p2 := p + side * 1.25
		if _walk.has_method("get_nearest_point"):
			var np: Vector3 = _walk.call("get_nearest_point", p2)
			if np != Vector3.INF and np.distance_to(p2) < 1.6:
				p2.y = np.y
		var a := spawn_npc(arch_id, p, {"yaw": atan2(-side.x, -side.z), "visual": opts.get("visual", "")})
		var b := spawn_npc(_pick_archetype(district), p2, {"yaw": atan2(side.x, side.z), "activity": "talk", "partner": a})
		for n: Node3D in [a, b]:
			if n != null:
				n.set("ambient", true)
				_ambient_count += 1
		if a != null and b != null and a.get("brain") != null:
			(a.get("brain") as Node).call("on_event", a, "talk_with", {"partner": b})
		return
	var npc2 := spawn_npc(arch_id, p, opts)
	if npc2 != null:
		npc2.set("ambient", true)
		_ambient_count += 1


func _pick_archetype(district: String) -> String:
	var mix: Dictionary = DISTRICT_MIX.get(district, DISTRICT_MIX["default"])
	var total := 0.0
	for k: String in mix.keys():
		total += float(mix[k])
	var r := _rng.randf() * total
	for k: String in mix.keys():
		r -= float(mix[k])
		if r <= 0.0:
			return k
	return "civilian_m"


func _district_at(p: Vector3) -> String:
	var w := Game.world
	if w != null and is_instance_valid(w) and w.has_method("get_district"):
		return str(w.call("get_district", p))
	return "midtown"


func _crowded(p: Vector3, r: float) -> bool:
	var r2 := r * r
	for npc in _npcs:
		if is_instance_valid(npc) and npc.global_position.distance_squared_to(p) < r2:
			return true
	return false


func _in_view(p: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var head := p + Vector3(0.0, 1.2, 0.0)
	if not cam.is_position_in_frustum(head):
		return false
	if cam.global_position.distance_to(head) > 140.0:
		return false
	return Combat.has_line_of_sight(cam.global_position, head)


func _free_bench_near(p: Vector3, radius: float) -> int:
	for i in _benches.size():
		if _bench_taken.has(i):
			continue
		var xf: Transform3D = (_benches[i] as Dictionary)["xform"]
		if xf.origin.distance_to(p) <= radius:
			return i
	return -1


## The sitting spot of bench point `i` when a bench model with a collider stands there
## (node name / meta "prop_id" containing "bench"), else null. Cached; re-checked every 20 s.
func _resolve_bench(i: int) -> Variant:
	var b: Dictionary = _benches[i]
	var pi := int(b.get("prop", -1))
	if pi >= 0:
		# a props-system bench: usable while it stands (not knocked over / broken)
		var props := Game.get_system("props")
		if props != null and props.has_method("get_instance_state") and str(props.call("get_instance_state", pi)) != "idle":
			return null
		return b["seat"]
	if b["seat"] is Transform3D:
		return b["seat"]
	var now := AiSenses.now()
	if now < float(b["next_check"]):
		return null
	b["next_check"] = now + 20.0
	if not is_inside_tree():
		return null
	var xf: Transform3D = b["xform"]
	var space := get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 0.5, 1.6)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis.IDENTITY, xf.origin + Vector3(0.0, 0.45, 0.0))
	q.collision_mask = Layers.WORLD | Layers.PROP
	for hit: Dictionary in space.intersect_shape(q, 8):
		var col := hit.get("collider", null) as Node3D
		var bench_node := _bench_node_of(col)
		if bench_node == null:
			continue
		var seat := _seat_from_bench(bench_node.global_transform)
		seat.origin.y = xf.origin.y
		b["seat"] = seat
		return seat
	return null


func _bench_node_of(n: Node) -> Node3D:
	var cur := n
	var guard := 0
	while cur != null and guard < 4:
		if str(cur.name).to_lower().contains("bench"):
			return cur as Node3D
		if cur.has_meta("prop_id") and str(cur.get_meta("prop_id")).contains("bench"):
			return cur as Node3D
		cur = cur.get_parent()
		guard += 1
	return null


# --- gang groups ---------------------------------------------------------------------------------

func _gang_step(dt: float) -> void:
	for idx in _gang_spots.size():
		var spot: Dictionary = _gang_spots[idx]
		var pos: Vector3 = spot["pos"]
		var d := Vector2(pos.x - _focus.x, pos.z - _focus.z).length()
		spot["cooldown"] = maxf(float(spot["cooldown"]) - dt, 0.0)
		var members: Array = spot["members"]
		if bool(spot["active"]):
			var alive := 0
			var fighting := false
			for m: Variant in members:
				if m != null and is_instance_valid(m) and not bool((m as Node).get("is_dead")):
					alive += 1
					if str((m as Node).get("state_tag")) == "combat":
						fighting = true
			if alive == 0:
				spot["active"] = false
				spot["members"] = []
				spot["cooldown"] = GANG_RESPAWN
			elif d > GANG_RELEASE and not fighting:
				for m: Variant in members:
					if m != null and is_instance_valid(m) and not bool((m as Node).get("is_dead")):
						_despawn(m as NpcBase)
				spot["active"] = false
				spot["members"] = []
		elif enabled and d < GANG_ACTIVATE and float(spot["cooldown"]) <= 0.0 and _walk != null:
			_spawn_gang(idx, spot)


func _spawn_gang(idx: int, spot: Dictionary) -> void:
	var pos: Vector3 = spot["pos"]
	var n := _rng.randi_range(3, GANG_MAX_PER_SPOT)
	var members: Array = []
	for k in n:
		var ang := TAU * float(k) / float(n) + _rng.randf_range(-0.3, 0.3)
		var r := _rng.randf_range(1.2, 2.2)
		var p := pos + Vector3(sin(ang) * r, 0.0, cos(ang) * r)
		p.y = Game.ground_height(p.x, p.z) if Game.world != null else pos.y
		if absf(p.y - pos.y) > 1.0:
			p = pos
		var face := pos - p
		var npc := spawn_npc("gang_member", p, {"yaw": atan2(-face.x, -face.z), "home": p, "group": idx,
				"activity": "hang"})
		if npc != null:
			npc.set("ambient", true)
			npc.set_meta("gang_spot", idx)
			members.append(npc)
	spot["members"] = members
	spot["active"] = true


# --- stimuli ---------------------------------------------------------------------------------------

func _on_noise(pos: Vector3, radius: float, kind: String, instigator: Node) -> void:
	if radius <= 0.0:
		return
	stats["noise_events"] = int(stats["noise_events"]) + 1
	var r2 := radius * radius * 1.6
	for npc in _npcs:
		if not is_instance_valid(npc) or npc.is_dead or npc == instigator or not npc.is_inside_tree():
			continue
		if npc.global_position.distance_squared_to(pos) > r2:
			continue
		npc.hear_noise(pos, radius, kind, instigator)


func _on_crime(crime_id: String, pos: Vector3, instigator: Node) -> void:
	if _reporting:
		return
	if instigator == null or not is_instance_valid(instigator) or not instigator.is_in_group("player"):
		return
	stats["crime_events"] = int(stats["crime_events"]) + 1
	var hear_r := 0.0 if _sight_only else float(CRIME_HEAR.get(crime_id, 12.0))
	var cands: Array = []
	for npc in _npcs:
		if not is_instance_valid(npc) or npc.is_dead or not npc.is_inside_tree() or npc.current_vehicle != null:
			continue
		var d := npc.global_position.distance_to(pos)
		var sight := npc.senses.get_sight_range()
		if d > maxf(hear_r, sight):
			continue
		var witnessed := d <= hear_r
		if not witnessed and not npc.is_down:
			witnessed = npc.can_see_point(pos + Vector3(0.0, 1.0, 0.0)) or npc.can_see(instigator as Node3D)
		if witnessed:
			cands.append([d, npc])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var pending := int(_pending_calls.get(crime_id, 0))
	for c: Array in cands:
		var npc: NpcBase = c[1]
		var may_call := false
		if pending < MAX_CALLERS_PER_CRIME and not npc.is_down and npc.faction == "civilian" and _rng.randf() < witness_call_chance:
			may_call = true
			pending += 1
		npc.notify_crime(crime_id, pos, instigator, may_call)
	_pending_calls[crime_id] = pending


## Gun pointed at people, people bumped by the player (about 6 Hz).
func _player_stimuli() -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p) or bool(p.get("is_dead")):
		return
	if Game.get_player_vehicle() != null:
		return
	var now := AiSenses.now()
	# bumps
	var pv := Game.get_player_velocity()
	var pspeed := Vector2(pv.x, pv.z).length()
	if pspeed > 1.2:
		var pp := p.global_position
		for npc in _npcs:
			if not is_instance_valid(npc) or npc.is_dead or npc.sim_tier > 0 or npc.current_vehicle != null:
				continue
			var q := npc.global_position
			if absf(q.y - pp.y) > 1.2 or Vector2(q.x - pp.x, q.z - pp.z).length_squared() > 0.95 * 0.95:
				continue
			var id := npc.get_instance_id()
			if now - float(_bump_cd.get(id, -100.0)) < 1.5:
				continue
			_bump_cd[id] = now
			npc.notify_bumped(p)
	# a firearm aimed at somebody
	if not bool(p.get("is_aiming")) or not _player_has_firearm(p) or not p.has_method("get_aim_ray"):
		return
	var ray: Dictionary = p.call("get_aim_ray")
	var origin: Vector3 = ray.get("origin", p.global_position)
	var dir: Vector3 = ray.get("direction", -p.global_basis.z)
	for npc in _npcs:
		if not is_instance_valid(npc) or npc.is_dead or npc.sim_tier > 1 or not npc.is_inside_tree():
			continue
		var c := npc.get_target_position()
		var v := c - origin
		var t := v.dot(dir)
		if t < 0.5 or t > 32.0:
			continue
		if (v - dir * t).length() > 0.75 + t * 0.025:
			continue
		if not Combat.has_line_of_sight(origin, c, [p, npc]):
			continue
		npc.notify_threatened(p, STIMULUS_INTERVAL)


func _player_has_firearm(p: Node) -> bool:
	var inv: Variant = p.get("inventory")
	if inv == null or not is_instance_valid(inv):
		return false
	if (inv as Object).has_method("get_current_spec"):
		var spec: Variant = (inv as Object).call("get_current_spec")
		if spec is Object and (spec as Object).has_method("is_firearm"):
			return bool((spec as Object).call("is_firearm"))
	return false


# --- local avoidance -------------------------------------------------------------------------------

func _avoidance_slice() -> void:
	var n := _npcs.size()
	if n == 0:
		return
	var count := mini(AVOID_PER_FRAME, n)
	var player_pos := Vector3.INF
	if Game.has_player() and Game.get_player_vehicle() == null:
		player_pos = Game.player.global_position
	for k in count:
		_avoid_cursor = (_avoid_cursor + 1) % n
		var npc := _npcs[_avoid_cursor]
		if not is_instance_valid(npc) or npc.sim_tier > 0 or npc.is_dead or npc.is_down or npc.current_vehicle != null:
			if is_instance_valid(npc):
				npc.avoid = Vector3.ZERO
			continue
		var p := npc.global_position
		var vel := npc.get_planar_velocity()
		var fwd := vel.normalized() if vel.length_squared() > 0.04 else -npc.global_basis.z
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var push := Vector3.ZERO
		for other in _npcs:
			if other == npc or not is_instance_valid(other) or other.sim_tier > 0 or other.is_dead or other.current_vehicle != null:
				continue
			push += _avoid_term(p, other.global_position, fwd, right)
		if player_pos != Vector3.INF:
			push += _avoid_term(p, player_pos, fwd, right) * 1.3
		npc.avoid = push.limit_length(1.0)


func _avoid_term(p: Vector3, o: Vector3, fwd: Vector3, right: Vector3) -> Vector3:
	var d := Vector3(o.x - p.x, 0.0, o.z - p.z)
	if absf(o.y - p.y) > 1.5:
		return Vector3.ZERO
	var l2 := d.length_squared()
	if l2 > 4.0 or l2 < 0.0001:
		return Vector3.ZERO
	var l := sqrt(l2)
	var dn := d / l
	var out := Vector3.ZERO
	var ahead := fwd.dot(dn)
	if ahead > -0.2:
		var s := 1.0 if right.dot(dn) > 0.0 else -1.0
		out -= right * s * (2.0 - l) * 0.5 * (0.4 + ahead)
	if l < 0.8:
		out -= dn * (0.8 - l) * 1.5
	return out


# --- vehicles near crossings -------------------------------------------------------------------

func _refresh_vehicle_cache() -> void:
	_veh_cache.clear()
	var vs := Game.get_system("vehicles")
	if vs == null or not vs.has_method("get_vehicles"):
		return
	for v: Variant in vs.call("get_vehicles"):
		if v == null or not is_instance_valid(v) or not (v is RigidBody3D):
			continue
		var rb := v as RigidBody3D
		if rb.sleeping or rb.freeze:
			continue
		var p := rb.global_position
		if Vector2(p.x - _focus.x, p.z - _focus.z).length_squared() > 140.0 * 140.0:
			continue
		_veh_cache.append(p)
		_veh_cache.append(rb.linear_velocity)


static func _dist_point_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return ap.length()
	var t := clampf(ap.dot(ab) / l2, 0.0, 1.0)
	return (ap - ab * t).length()
