extends Node3D
## World system "wildlife" (BootManifest): region-based animal population around the player.
##
## Habitats (built at setup from WORLD data):
##   hill     wildlife_land points on Signal Hill        deer, rabbits, boar, coyotes
##   wild     wildlife_land on the lighthouse knoll / east dunes   rabbits, coyotes, deer
##   park     wildlife_land in the residential park        dogs, cats, pigeons, rabbits
##   beach    wildlife_land on the sand                   seagulls
##   coast    generated perches (docks deck, marina promenade, piers, boardwalk, lighthouse)  seagulls
##   urban    WalkGraph points near the focus in town     dogs, cats (residential), pigeons
##   reef     wildlife_water + reef points (>= 3 m deep)  fish schools (one MultiMesh node each)
##   deep     the wreck basin south of the beach (> 9 m)  the shark (rare roll, max 1)
##   pasture  spawn kind "pasture" if the world ever has one   cows (the island has none: skipped)
## Caps (ARCHITECTURE 10): <= 16 animal nodes in total (a fish school counts as one), land 9,
## birds 7, water 4, plus per-species caps from the registry. Simulation tiers by distance to the
## focus: 0 < 45 m (full: every frame, obstacle rays, animation), 1 < 110 m (movement every frame,
## think 2.5 Hz, animation 10 Hz), 2 beyond (movement + think 2 Hz, hidden); despawn beyond
## ~165 m. One loop drives everything (no per-animal _process). Despawned bodies are pooled.
##
## API: set_enabled(on), get_count(), reset_for_respawn(), spawn_animal(id, pos, opts),
## spawn_fish_school(pos, opts), get_animals(), get_schools(), get_counts(), clear_all(),
## set_focus_override(pos) / clear_focus_override(), get_focus(), get_debug_info(),
## get_habitat_points(name), signals animal_spawned / animal_died.

signal animal_spawned(animal: Node3D)
signal animal_died(animal: Node3D, killer: Node)

const MAX_ANIMALS := 16
const CATEGORY_CAP := {"land": 9, "bird": 7, "water": 4}
const SPAWN_INTERVAL := 0.5
const TIER_INTERVAL := 0.25
const VEH_INTERVAL := 0.3
const SHARK_INTERVAL := 12.0
const TIER0 := 45.0
const TIER1 := 110.0
const THINK := [0.125, 0.4, 1.0]
const FAR_MOVE := 0.5
const DESPAWN := {"land": 165.0, "bird": 180.0, "water": 130.0}
const RING := {"hill": [38.0, 125.0], "wild": [38.0, 125.0], "park": [32.0, 110.0], "beach": [30.0, 130.0],
		"coast": [30.0, 140.0], "urban": [30.0, 100.0], "reef": [18.0, 90.0], "pasture": [38.0, 125.0]}
const HAB_WEIGHT := {"hill": 1.2, "wild": 0.8, "park": 1.0, "beach": 0.7, "coast": 1.0, "urban": 1.0,
		"reef": 1.3, "pasture": 1.0}
const HAB_TABLE := {
	"hill": {"deer": 3.0, "rabbit": 2.5, "boar": 2.0, "coyote": 1.2},
	"wild": {"rabbit": 3.0, "coyote": 1.0, "deer": 1.2},
	"park": {"dog": 2.0, "cat": 1.0, "pigeon": 2.5, "rabbit": 1.2},
	"beach": {"seagull": 1.0},
	"coast": {"seagull": 1.0},
	"reef": {"fish_small": 1.0},
	"pasture": {"cow": 1.0},
}
const URBAN_TABLE := {
	"residential": {"dog": 2.0, "cat": 2.0, "pigeon": 2.0},
	"midtown": {"pigeon": 1.5, "cat": 0.8},
	"downtown": {"pigeon": 1.4},
	"waterfront": {"pigeon": 0.6, "cat": 0.6},
}
const COAST_DISTRICTS := ["waterfront", "beach", "industrial"]
const TOWN_DISTRICTS := ["residential", "midtown", "downtown"]
const CALL_GAP := {"seagull": 2.5, "pigeon": 4.0}

var enabled := true
var auto_spawn := true               ## tests switch the automatic population off
var focus_override := Vector3.INF
var density := 1.0
var corpse_time_mult := 1.0
var roof_chance_override := -1.0     ## >= 0: forces the share of roof perches (tests)
var stats := {"spawned": 0, "despawned": 0, "deaths": 0, "pet_crimes": 0, "noise_events": 0,
		"phys_us": 0.0, "anim_us": 0.0, "phys_us_max": 0.0, "spawn_us_max": 0.0, "pooled": 0}

var _animals: Array[AnimalBody] = []
var _schools: Array[AnimalFishSchool] = []
var _pool: Dictionary = {}           ## species -> Array[AnimalBody]
var _defs: Dictionary = {}           ## species -> merged def
var _hab: Dictionary = {}            ## habitat -> PackedVector3Array
var _coast_tops: Array = []          ## [Rect2, top y] buildings near the sea
var _town_tops: Array = []           ## [Rect2, top y] town buildings
var _all_tops: Array = []            ## [Rect2, top y]
var _veh_cache: Array = []           ## [pos, vel] of moving vehicles near the focus
var _flocks: Dictionary = {}         ## id -> {dest, roof, t}
var _next_flock := 1
var _focus := Vector3.ZERO
var _spawn_t := 0.0
var _tier_t := 0.0
var _veh_t := 0.0
var _shark_t := 4.0
var _shark_cd := 0.0
var _call_time: Dictionary = {}
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
var _built := false
var _park_centre := Vector3(189.5, 2.65, 26.5)
var _plaza_centre := Vector3(32.8, 2.65, -59.5)
var _ray := PhysicsRayQueryParameters3D.new()


func setup() -> void:
	_rng.seed = Game.rng.randi()
	for id: Variant in Registry.ids("animals"):
		var d := AnimalAssets.species_def(String(id))
		if d.is_empty():
			push_warning("[Wildlife] species without art or tuning: " + String(id))
			continue
		_defs[String(id)] = d
		AnimalAssets.scene(String(id))
	if _defs.has("fish_small"):
		AnimalAssets.merged_mesh("fish_small")
	if not EventBus.noise_emitted.is_connected(_on_noise):
		EventBus.noise_emitted.connect(_on_noise)
	_build_habitats()
	_prewarm()
	print("[Wildlife] species %d, habitats %s" % [_defs.size(), _habitat_summary()])


## Builds a few bodies per species up front so spawning a flock in game costs no GLB instancing.
func _prewarm() -> void:
	for id: String in _defs:
		var d: Dictionary = _defs[id]
		if String(d.get("kind", "")) == "fish" and id == "fish_small":
			continue
		var pool: Array = _pool.get(id, [])
		for i in _pool_cap(id):
			var a := AnimalBody.new()
			if not a.setup_animal(id, d, self, AnimalAssets.scene(id)):
				a.free()
				break
			pool.append(a)
		_pool[id] = pool


func _pool_cap(id: String) -> int:
	var d: Dictionary = _defs.get(id, {})
	if String(d.get("kind", "")) == "bird":
		return 4
	return 2 if int(d.get("cap", 1)) >= 3 else 1


func _exit_tree() -> void:
	for arr: Variant in _pool.values():
		for a: Variant in arr:
			if is_instance_valid(a) and not (a as Node).is_inside_tree():
				(a as Node).free()
	_pool.clear()
	AnimalAssets.clear_cache()
	AnimalFishSchool.clear_static()


func _habitat_summary() -> String:
	var parts: PackedStringArray = []
	for k: String in _hab:
		parts.append("%s %d" % [k, (_hab[k] as PackedVector3Array).size()])
	return ", ".join(parts)


# =================================================================================================
# public API
# =================================================================================================

func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		clear_all(false)


func is_enabled() -> bool:
	return enabled


## Animal nodes in the world (living + corpses; a fish school counts as one).
func get_count() -> int:
	return _animals.size() + _schools.size()


func get_animals() -> Array:
	var out: Array = []
	for a in _animals:
		if is_instance_valid(a):
			out.append(a)
	return out


func get_schools() -> Array:
	var out: Array = []
	for s in _schools:
		if is_instance_valid(s):
			out.append(s)
	return out


## {"total", "land", "bird", "water", "alive", "dead", "<species>": n ...}
func get_counts() -> Dictionary:
	var c := {"total": get_count(), "land": 0, "bird": 0, "water": _schools.size(), "alive": 0, "dead": 0}
	for a in _animals:
		if not is_instance_valid(a):
			continue
		c[a.category] = int(c.get(a.category, 0)) + 1
		c[a.species] = int(c.get(a.species, 0)) + 1
		if a.is_dead:
			c["dead"] = int(c["dead"]) + 1
		else:
			c["alive"] = int(c["alive"]) + 1
	c["fish_small"] = _schools.size()
	return c


func set_focus_override(pos: Vector3) -> void:
	focus_override = pos


func clear_focus_override() -> void:
	focus_override = Vector3.INF


func get_focus() -> Vector3:
	if focus_override.is_finite():
		return focus_override
	if Game.has_player():
		return Game.get_player_position()
	return Vector3.ZERO


func set_density(mult: float) -> void:
	density = clampf(mult, 0.0, 1.5)


func get_habitat_points(habitat: String) -> PackedVector3Array:
	return _hab.get(habitat, PackedVector3Array())


func get_species_def(id: String) -> Dictionary:
	return _defs.get(id, {})


func reset_for_respawn() -> void:
	for a in _animals:
		if is_instance_valid(a) and not a.is_dead:
			var st := a.get_state_name()
			if st in ["chase", "stalk", "bark", "circle", "charge", "retreat"]:
				a.calm()


func clear_all(include_persistent: bool = false) -> void:
	for i in range(_animals.size() - 1, -1, -1):
		var a := _animals[i]
		if not is_instance_valid(a):
			_animals.remove_at(i)
			continue
		if a.persistent and not include_persistent:
			continue
		_despawn(a, i)
	for i in range(_schools.size() - 1, -1, -1):
		var s := _schools[i]
		if is_instance_valid(s) and s.persistent and not include_persistent:
			continue
		if is_instance_valid(s):
			s.queue_free()
		_schools.remove_at(i)
	_flocks.clear()


## Spawns one animal (or a fish school for "fish_small"). opts: yaw, persistent, home, state
## ("wander" | "graze"), flying (birds), roof (bird perched on a roof), flock (id), stray (dogs),
## habitat, count (fish), radius (fish roam radius). Returns the node or null.
func spawn_animal(id: String, pos: Vector3, opts: Dictionary = {}) -> Node3D:
	if id == "fish_small":
		return spawn_fish_school(pos, opts)
	var d: Dictionary = _defs.get(id, {})
	if d.is_empty():
		push_warning("[Wildlife] unknown species: " + id)
		return null
	var t0 := Time.get_ticks_usec()
	var a: AnimalBody = null
	var pool: Array = _pool.get(id, [])
	while not pool.is_empty() and a == null:
		var cand: Variant = pool.pop_back()
		if is_instance_valid(cand):
			a = cand as AnimalBody
	if a == null:
		a = AnimalBody.new()
		if not a.setup_animal(id, d, self, AnimalAssets.scene(id)):
			a.free()
			return null
	else:
		stats["pooled"] = int(stats["pooled"]) + 1
	var parent := Game.get_entities_root()
	if parent == null:
		parent = self
	parent.add_child(a)
	var o := opts.duplicate()
	if not o.has("habitat"):
		o["habitat"] = _habitat_at(pos)
	a.begin(pos, o)
	_animals.append(a)
	_focus = get_focus()
	a.set_sim_tier(_tier_for(a.global_position))
	stats["spawned"] = int(stats["spawned"]) + 1
	stats["spawn_us_max"] = maxf(float(stats["spawn_us_max"]), float(Time.get_ticks_usec() - t0))
	animal_spawned.emit(a)
	return a


func spawn_fish_school(pos: Vector3, opts: Dictionary = {}) -> Node3D:
	var d: Dictionary = _defs.get("fish_small", {})
	if d.is_empty():
		return null
	var s := AnimalFishSchool.new()
	var parent := Game.get_entities_root()
	if parent == null:
		parent = self
	parent.add_child(s)
	var size: Array = d.get("school_size", [12, 18])
	var n := int(opts.get("count", _rng.randi_range(int(size[0]), int(size[1]))))
	if not s.setup_school(d, self, pos, n, opts):
		s.queue_free()
		return null
	_schools.append(s)
	stats["spawned"] = int(stats["spawned"]) + 1
	animal_spawned.emit(s)
	return s


func get_debug_info() -> Dictionary:
	var tiers := [0, 0, 0]
	for a in _animals:
		if is_instance_valid(a):
			tiers[a.sim_tier] = int(tiers[a.sim_tier]) + 1
	return {"enabled": enabled, "counts": get_counts(), "tiers": tiers, "stats": stats.duplicate(),
			"focus": _focus, "habitats": _habitat_summary(),
			"roofs": {"coast": _coast_tops.size(), "town": _town_tops.size(), "all": _all_tops.size()}}


# =================================================================================================
# helpers used by the brains (duck-typed calls from AnimalBody / brains)
# =================================================================================================

func get_threat_vehicles() -> Array:
	return _veh_cache


func can_call(species: String) -> bool:
	var gap := float(CALL_GAP.get(species, 3.0))
	var last := float(_call_time.get(species, -100.0))
	if _clock - last < gap:
		return false
	_call_time[species] = _clock
	return true


func flock_alarm(flock_id: int, from: Vector3, src: Node) -> void:
	for a in _animals:
		if a == src or not is_instance_valid(a) or a.is_dead or a.flock_id != flock_id:
			continue
		if src is Node3D and a.global_position.distance_to((src as Node3D).global_position) > 18.0:
			continue
		if a.brain != null and a.brain.has_method("alarm_from_flock"):
			a.brain.call("alarm_from_flock", a, from)


## Highest building top under the box spanned by a and b (grown by margin); ground level if none.
func get_obstacle_top(a: Vector3, b: Vector3, margin: float) -> float:
	var r := Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z))).grow(margin)
	var top := -INF
	for e: Array in _all_tops:
		if (e[0] as Rect2).intersects(r):
			top = maxf(top, float(e[1]))
	if top == -INF:
		return maxf(Game.ground_height(a.x, a.z), Game.ground_height(b.x, b.z))
	return top


## Where a gull circles: over the water / shore close to `around`.
func get_circle_center(b: AnimalBody, around: Vector3) -> Vector3:
	var pts: PackedVector3Array = _hab.get("coast", PackedVector3Array())
	if b.species != "seagull" or pts.is_empty():
		return around
	var best := around
	var best_d := INF
	for i in 6:
		var p := pts[_rng.randi() % pts.size()]
		var d := Vector2(p.x - around.x, p.z - around.z).length()
		if d < best_d:
			best_d = d
			best = p
	if best_d > 160.0:
		return around
	return best + Vector3(_rng.randf_range(-14.0, 14.0), 0.0, _rng.randf_range(-14.0, 14.0))


## A landing spot for a bird: {pos, roof} ({} if none). Flock mates land next to each other.
func find_perch(b: AnimalBody) -> Dictionary:
	var pos := b.global_position
	if b.flock_id >= 0 and _flocks.has(b.flock_id):
		# flock mates that left together land together (but never back on the spot they just fled)
		var fl: Dictionary = _flocks[b.flock_id]
		if fl["dest"] is Vector3 and (fl["dest"] as Vector3).is_finite() and _clock - float(fl["t"]) < 8.0 				and (fl["dest"] as Vector3).distance_to(pos) > 8.0:
			return _offset_perch(fl["dest"], bool(fl["roof"]))
	var res := _new_perch(b, pos)
	if not res.is_empty() and b.flock_id >= 0:
		_flocks[b.flock_id] = {"dest": res["pos"], "roof": res["roof"], "t": _clock}
	return res


func _new_perch(b: AnimalBody, pos: Vector3) -> Dictionary:
	var pp := Game.get_player_position() if Game.has_player() else Vector3.INF
	var gull := b.species == "seagull"
	var roof_chance := 0.3 if gull else 0.4
	if roof_chance_override >= 0.0:
		roof_chance = roof_chance_override
	if _rng.randf() < roof_chance:
		var r := _roof_perch(_coast_tops if gull else _town_tops, pos, 12.0, 85.0)
		if not r.is_empty():
			return r
	if gull:
		var pts: PackedVector3Array = _hab.get("coast", PackedVector3Array())
		pts = pts.duplicate()
		pts.append_array(_hab.get("beach", PackedVector3Array()))
		for i in 12:
			if pts.is_empty():
				break
			var p := pts[_rng.randi() % pts.size()]
			var d := Vector2(p.x - pos.x, p.z - pos.z).length()
			if d < 10.0 or d > 110.0:
				continue
			if pp.is_finite() and Vector2(p.x - pp.x, p.z - pp.z).length() < 12.0:
				continue
			return {"pos": _settle(p), "roof": false}
		return {}
	# pigeons: a pavement / park point in town
	var walk: Variant = Game.world.get("walk") if Game.world != null else null
	for i in 6:
		var p := Vector3.INF
		if walk != null and (walk as Object).has_method("random_point"):
			p = (walk as Object).call("random_point", pos, 14.0, 65.0)
		if not p.is_finite():
			continue
		if pp.is_finite() and Vector2(p.x - pp.x, p.z - pp.z).length() < 10.0:
			continue
		if Game.world.has_method("get_water_depth") and float(Game.world.get_water_depth(p.x, p.z)) > -0.05:
			continue
		return {"pos": _settle(Vector3(p.x, Game.ground_height(p.x, p.z), p.z)), "roof": false}
	return _roof_perch(_town_tops, pos, 10.0, 90.0)


func _offset_perch(dest: Vector3, roof: bool) -> Dictionary:
	var ang := _rng.randf() * TAU
	var r := _rng.randf_range(0.35, 1.4)
	var p := dest + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	if roof:
		var y := _ray_down(p, dest.y + 3.0, dest.y - 2.0)
		if is_nan(y) or absf(y - dest.y) > 0.6:
			return {"pos": dest, "roof": true}
		p.y = y
		return {"pos": p, "roof": true}
	p.y = Game.ground_height(p.x, p.z)
	if Game.world != null and Game.world.has_method("get_water_depth") and float(Game.world.get_water_depth(p.x, p.z)) > -0.05:
		return {"pos": dest, "roof": false}
	p = _settle(p)
	if absf(p.y - dest.y) > 1.2:
		return {"pos": dest, "roof": false}
	return {"pos": p, "roof": false}


## A point on the edge of a flat roof (ray cast onto the building collider), {} if none fits.
func _roof_perch(list: Array, near: Vector3, min_d: float, max_d: float) -> Dictionary:
	var near_list: Array = []
	for e: Array in list:
		var c0 := (e[0] as Rect2).get_center()
		var d0 := Vector2(c0.x - near.x, c0.y - near.z).length()
		if d0 >= min_d and d0 <= max_d:
			near_list.append(e)
	if near_list.is_empty():
		return {}
	for i in 8:
		var e: Array = near_list[_rng.randi() % near_list.size()]
		var rect: Rect2 = e[0]
		# a point 0.35 m inside one of the four edges
		var side := _rng.randi() % 4
		var u := _rng.randf_range(0.15, 0.85)
		var p := Vector2.ZERO
		match side:
			0:
				p = Vector2(rect.position.x + rect.size.x * u, rect.position.y + 0.35)
			1:
				p = Vector2(rect.position.x + rect.size.x * u, rect.end.y - 0.35)
			2:
				p = Vector2(rect.position.x + 0.35, rect.position.y + rect.size.y * u)
			_:
				p = Vector2(rect.end.x - 0.35, rect.position.y + rect.size.y * u)
		var top := float(e[1])
		var y := _ray_down(Vector3(p.x, 0.0, p.y), top + 4.0, top - 6.0)
		if is_nan(y):
			continue
		if y < Game.ground_height(p.x, p.y) + 2.5:
			continue
		return {"pos": Vector3(p.x, y, p.y), "roof": true}
	return {}


## Ground / prop top under a perch point: birds stand on containers, crates, benches, shelters.
func _settle(p: Vector3) -> Vector3:
	var y := _ray_down(p, p.y + 6.0, p.y - 1.5, Layers.WORLD | Layers.PROP)
	if is_nan(y):
		return p
	return Vector3(p.x, y, p.z)


func _ray_down(p: Vector3, from_y: float, to_y: float, mask: int = Layers.WORLD) -> float:
	if not is_inside_tree():
		return NAN
	var space := get_world_3d().direct_space_state
	_ray.from = Vector3(p.x, from_y, p.z)
	_ray.to = Vector3(p.x, to_y, p.z)
	_ray.collision_mask = mask
	_ray.collide_with_areas = false
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return NAN
	var n: Vector3 = hit["normal"]
	if n.y < 0.8:
		return NAN
	return (hit["position"] as Vector3).y


## Dogs / cats harmed by the player: an "assault" report if a civilian (or an officer) sees it.
func report_pet_harm(animal: Node3D, _info: Dictionary) -> void:
	if animal == null or not is_instance_valid(animal) or not Game.has_player():
		return
	var peds := Game.get_system("peds")
	if peds == null or not peds.has_method("get_npcs"):
		return
	var pos := animal.global_position
	var seen := false
	var police := false
	for n: Variant in peds.call("get_npcs"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var npc := n as Node3D
		if npc.get("is_dead") == true:
			continue
		var faction := String(npc.get("faction")) if npc.get("faction") != null else ""
		if faction != "civilian" and faction != "police":
			continue
		var d := npc.global_position.distance_to(pos)
		if d > 40.0:
			continue
		var sees := d < 8.0
		if not sees and npc.has_method("can_see_point"):
			sees = bool(npc.call("can_see_point", pos + Vector3.UP * 0.4))
		if sees:
			seen = true
			if faction == "police":
				police = true
	if not seen:
		return
	if Wanted.has_method("report_crime"):
		Wanted.report_crime("assault", pos, {"instigator": Game.player, "victim": animal,
				"direct_police_witness": police})
		stats["pet_crimes"] = int(stats["pet_crimes"]) + 1


func on_animal_died(animal: Node3D, killer: Node) -> void:
	stats["deaths"] = int(stats["deaths"]) + 1
	animal_died.emit(animal, killer)


# =================================================================================================
# main loops
# =================================================================================================

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var t0 := Time.get_ticks_usec()
	_clock += delta
	_focus = get_focus()
	for i in range(_animals.size() - 1, -1, -1):
		var a := _animals[i]
		if not is_instance_valid(a) or a.is_queued_for_deletion():
			_animals.remove_at(i)
			continue
		if not a.is_inside_tree():
			continue
		if a.sim_tier <= 1 or a.is_dead:
			a.tick_move(delta)
		else:
			a.anim_accum += delta
			if a.anim_accum >= FAR_MOVE:
				var acc := a.anim_accum
				a.anim_accum = 0.0
				a.tick_move(acc)
		a.think_accum += delta
		if a.think_accum >= float(THINK[a.sim_tier]):
			var acc2 := a.think_accum
			a.think_accum = 0.0
			a.tick_think(acc2)
	for i in range(_schools.size() - 1, -1, -1):
		var s := _schools[i]
		if not is_instance_valid(s):
			_schools.remove_at(i)
			continue
		s.think_accum += delta
		var need := 0.0 if s.sim_tier == 0 else (0.1 if s.sim_tier == 1 else 0.5)
		if s.think_accum >= need:
			var acc3 := s.think_accum
			s.think_accum = 0.0
			s.tick(acc3)
	_tier_t -= delta
	if _tier_t <= 0.0:
		_tier_t = TIER_INTERVAL
		_update_tiers_and_despawn()
	_veh_t -= delta
	if _veh_t <= 0.0:
		_veh_t = VEH_INTERVAL
		_refresh_vehicles()
	if auto_spawn:
		_spawn_t -= delta
		if _spawn_t <= 0.0:
			_spawn_t = SPAWN_INTERVAL
			_spawn_step()
		_shark_t -= delta
		_shark_cd -= delta
		if _shark_t <= 0.0:
			_shark_t = SHARK_INTERVAL
			_shark_roll()
	var us := float(Time.get_ticks_usec() - t0)
	stats["phys_us"] = lerpf(float(stats["phys_us"]), us, 0.05)
	stats["phys_us_max"] = maxf(float(stats["phys_us_max"]) * 0.999, us)


func _process(delta: float) -> void:
	if not enabled:
		return
	var t0 := Time.get_ticks_usec()
	for a in _animals:
		if not is_instance_valid(a) or not a.is_inside_tree():
			continue
		if a.sim_tier == 0 or a.is_dead:
			a.tick_anim(delta)
		elif a.sim_tier == 1:
			a.anim_t += delta
			if a.anim_t >= 0.1:
				a.tick_anim(a.anim_t)
				a.anim_t = 0.0
	stats["anim_us"] = lerpf(float(stats["anim_us"]), float(Time.get_ticks_usec() - t0), 0.05)


func _tier_for(pos: Vector3) -> int:
	var d := Vector2(pos.x - _focus.x, pos.z - _focus.z).length()
	if d < TIER0:
		return 0
	if d < TIER1:
		return 1
	return 2


func _update_tiers_and_despawn() -> void:
	for i in range(_animals.size() - 1, -1, -1):
		var a := _animals[i]
		if not is_instance_valid(a):
			_animals.remove_at(i)
			continue
		var p := a.global_position
		var d := Vector2(p.x - _focus.x, p.z - _focus.z).length()
		var tier := 0 if d < TIER0 else (1 if d < TIER1 else 2)
		if tier != a.sim_tier:
			a.set_sim_tier(tier)
		if a.persistent:
			continue
		if d > float(DESPAWN.get(a.category, 165.0)):
			_despawn(a, i)
			continue
		if a.is_dead and a.corpse_timer <= 0.0:
			if a.corpse_timer < -25.0 or not _in_view(p, 90.0):
				_despawn(a, i)
	for i in range(_schools.size() - 1, -1, -1):
		var s := _schools[i]
		if not is_instance_valid(s):
			_schools.remove_at(i)
			continue
		var d := Vector2(s.centre.x - _focus.x, s.centre.z - _focus.z).length()
		s.set_sim_tier(0 if d < 70.0 else (1 if d < TIER1 else 2))
		if s.persistent:
			continue
		if d > float(DESPAWN["water"]) or s.is_finished():
			s.queue_free()
			_schools.remove_at(i)
			stats["despawned"] = int(stats["despawned"]) + 1


func _despawn(a: AnimalBody, index: int) -> void:
	if index >= 0 and index < _animals.size():
		_animals.remove_at(index)
	else:
		_animals.erase(a)
	stats["despawned"] = int(stats["despawned"]) + 1
	if a.species == "shark":
		_shark_cd = 60.0
	if not is_instance_valid(a):
		return
	if a.flock_id >= 0:
		var still := false
		for o in _animals:
			if is_instance_valid(o) and o.flock_id == a.flock_id:
				still = true
				break
		if not still:
			_flocks.erase(a.flock_id)
	var pool: Array = _pool.get(a.species, [])
	if pool.size() < _pool_cap(a.species) and a.is_inside_tree():
		a.get_parent().remove_child(a)
		pool.append(a)
		_pool[a.species] = pool
	else:
		a.queue_free()


func _refresh_vehicles() -> void:
	_veh_cache = []
	for n: Node in get_tree().get_nodes_in_group("vehicle"):
		if not (n is RigidBody3D) or not is_instance_valid(n):
			continue
		var rb := n as RigidBody3D
		var v := rb.linear_velocity
		if v.length() < 3.0:
			continue
		var p := rb.global_position
		if Vector2(p.x - _focus.x, p.z - _focus.z).length() > 150.0:
			continue
		_veh_cache.append([p, v])


func _in_view(p: Vector3, max_d: float) -> bool:
	if not is_inside_tree():
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var head := p + Vector3(0.0, 0.6, 0.0)
	if cam.global_position.distance_to(head) > max_d:
		return false
	if not cam.is_position_in_frustum(head):
		return false
	var space := get_world_3d().direct_space_state
	_ray.from = cam.global_position
	_ray.to = head
	_ray.collision_mask = Layers.SIGHT_MASK
	_ray.collide_with_areas = false
	return space.intersect_ray(_ray).is_empty()


func _on_noise(pos: Vector3, radius: float, kind: String, instigator: Node) -> void:
	if not enabled or radius <= 0.0:
		return
	stats["noise_events"] = int(stats["noise_events"]) + 1
	var r2 := radius * radius * 7.0
	for a in _animals:
		if not is_instance_valid(a) or a.is_dead or a == instigator:
			continue
		if a.global_position.distance_squared_to(pos) > r2:
			continue
		a.hear_noise(pos, radius, kind, instigator)
	for s in _schools:
		if is_instance_valid(s) and s.centre.distance_to(pos) < radius:
			s.on_noise(pos, radius, kind)


# =================================================================================================
# population
# =================================================================================================

func _cap() -> int:
	return int(round(MAX_ANIMALS * clampf(density, 0.0, 1.0)))


func _category_count(cat: String) -> int:
	if cat == "water":
		var n := _schools.size()
		for a in _animals:
			if is_instance_valid(a) and a.category == "water":
				n += 1
		return n
	var c := 0
	for a in _animals:
		if is_instance_valid(a) and a.category == cat:
			c += 1
	return c


func _species_count(id: String) -> int:
	if id == "fish_small":
		return _schools.size()
	var c := 0
	for a in _animals:
		if is_instance_valid(a) and a.species == id:
			c += 1
	return c


func _spawn_step() -> void:
	if not _built or _defs.is_empty():
		return
	var total := get_count()
	var cap := _cap()
	if total >= cap:
		return
	var night := WorldClock.is_night()
	# habitats with candidate points in their ring around the focus
	var cands: Array = []
	var weight_sum := 0.0
	for hab: String in HAB_TABLE.keys():
		var pts: PackedVector3Array = _hab.get(hab, PackedVector3Array())
		if pts.is_empty():
			continue
		var ring: Array = RING[hab]
		var n := 0
		for p in pts:
			var d := Vector2(p.x - _focus.x, p.z - _focus.z).length()
			if d >= float(ring[0]) and d <= float(ring[1]):
				n += 1
				if n >= 6:
					break
		if n > 0:
			var w := float(HAB_WEIGHT.get(hab, 1.0)) * float(n) / 6.0
			cands.append([hab, w])
			weight_sum += w
	var urban_d := _urban_district()
	if urban_d != "":
		cands.append(["urban", float(HAB_WEIGHT["urban"])])
		weight_sum += float(HAB_WEIGHT["urban"])
	if cands.is_empty():
		return
	# weighted habitat order, then a species that still fits its caps
	for attempt in 3:
		var r := _rng.randf() * weight_sum
		var hab := String(cands[0][0])
		for c: Array in cands:
			r -= float(c[1])
			if r <= 0.0:
				hab = String(c[0])
				break
		var table: Dictionary = URBAN_TABLE.get(urban_d, {}) if hab == "urban" else HAB_TABLE.get(hab, {})
		var sp := _pick_species(table, night, total, cap)
		if sp == "":
			continue
		var pos := _pick_point(hab, sp)
		if not pos.is_finite():
			continue
		_spawn_group(sp, pos, hab, night)
		return


func _pick_species(table: Dictionary, night: bool, total: int, cap: int) -> String:
	var opts: Array = []
	var sum := 0.0
	for id: String in table:
		var d: Dictionary = _defs.get(id, {})
		if d.is_empty():
			continue
		var w := float(table[id]) * float(d.get("night" if night else "day", 1.0))
		if String(d.get("kind", "")) == "bird" and Weather.has_method("is_raining") and bool(Weather.is_raining()):
			w *= 0.35
		if w <= 0.0:
			continue
		if _species_count(id) >= int(d.get("cap", 3)):
			continue
		var cat := String(d.get("category", "land"))
		var room := int(CATEGORY_CAP.get(cat, 4)) - _category_count(cat)
		var gmin := int((d.get("group", [1, 1]) as Array)[0])
		if room < (1 if cat == "water" else gmin) or total + gmin > cap:
			continue
		opts.append([id, w])
		sum += w
	if opts.is_empty():
		return ""
	var r := _rng.randf() * sum
	for o: Array in opts:
		r -= float(o[1])
		if r <= 0.0:
			return String(o[0])
	return String(opts[0][0])


func _pick_point(hab: String, sp: String) -> Vector3:
	if hab == "urban":
		var walk: Variant = Game.world.get("walk") if Game.world != null else null
		if walk == null or not (walk as Object).has_method("random_point"):
			return Vector3.INF
		var ring: Array = RING["urban"]
		for i in 5:
			var p: Vector3 = (walk as Object).call("random_point", _focus, float(ring[0]), float(ring[1]))
			if not p.is_finite():
				continue
			var dist := String(Game.world.get_district(p)) if Game.world.has_method("get_district") else ""
			if not URBAN_TABLE.has(dist) or not (URBAN_TABLE[dist] as Dictionary).has(sp):
				continue
			if dist == "downtown" and Vector2(p.x - _plaza_centre.x, p.z - _plaza_centre.z).length() > 45.0:
				continue
			if _in_view(p, 75.0):
				continue
			return p
		return Vector3.INF
	var pts: PackedVector3Array = _hab.get(hab, PackedVector3Array())
	var ring2: Array = RING.get(hab, [38.0, 125.0])
	var cand: Array = []
	for p in pts:
		var d := Vector2(p.x - _focus.x, p.z - _focus.z).length()
		if d >= float(ring2[0]) and d <= float(ring2[1]):
			cand.append(p)
	for i in 5:
		if cand.is_empty():
			break
		var k := _rng.randi() % cand.size()
		var p: Vector3 = cand[k]
		cand.remove_at(k)
		if _occupied(p, 6.0):
			continue
		var check := p
		if hab == "reef":
			if _in_view(p, 40.0):
				continue
		elif _in_view(check, 75.0):
			continue
		return p
	return Vector3.INF


func _occupied(p: Vector3, r: float) -> bool:
	for a in _animals:
		if is_instance_valid(a) and a.global_position.distance_to(p) < r:
			return true
	for s in _schools:
		if is_instance_valid(s) and s.centre.distance_to(p) < r * 2.0:
			return true
	return false


func _spawn_group(sp: String, pos: Vector3, hab: String, night: bool) -> void:
	var d: Dictionary = _defs[sp]
	if sp == "fish_small":
		var p := pos
		var depth := float(Game.world.get_water_depth(p.x, p.z)) if Game.world != null else 4.0
		p.y = minf(Game.WATER_LEVEL - depth + _rng.randf_range(1.2, 3.0), Game.WATER_LEVEL - 1.2)
		spawn_fish_school(p, {"habitat": hab})
		return
	var g: Array = d.get("group", [1, 1])
	var n := _rng.randi_range(int(g[0]), int(g[1]))
	if sp == "coyote" and night:
		n = maxi(n, 2)
	var cat := String(d.get("category", "land"))
	n = mini(n, int(CATEGORY_CAP.get(cat, 4)) - _category_count(cat))
	n = mini(n, int(d.get("cap", 3)) - _species_count(sp))
	n = mini(n, _cap() - get_count())
	if n <= 0:
		return
	var kind := String(d.get("kind", "land"))
	if kind == "bird":
		_spawn_flock(sp, pos, n, hab)
		return
	var stray := sp == "dog" and _rng.randf() < float(d.get("stray_chance", 0.15)) * (3.0 if night else 1.0)
	for i in n:
		var p := pos
		if i > 0:
			for k in 6:
				var ang := _rng.randf() * TAU
				var r := _rng.randf_range(1.5, 5.0)
				var q := pos + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
				if Game.world != null and float(Game.world.get_water_depth(q.x, q.z)) < -0.1 \
						and absf(Game.ground_height(q.x, q.z) - pos.y) < 1.5:
					p = q
					break
		p.y = Game.ground_height(p.x, p.z)
		spawn_animal(sp, p, {"habitat": hab, "home": pos, "stray": stray,
				"state": "graze" if _rng.randf() < 0.5 else "wander"})


## Spawns a flock of n birds at pos (perched, or flying when opts.flying). Returns the birds.
func spawn_flock(id: String, pos: Vector3, n: int, opts: Dictionary = {}) -> Array:
	if not _defs.has(id) or String((_defs[id] as Dictionary).get("kind", "")) != "bird":
		return []
	return _spawn_flock(id, pos, n, String(opts.get("habitat", _habitat_at(pos))), opts)


func _spawn_flock(sp: String, pos: Vector3, n: int, hab: String, force: Dictionary = {}) -> Array:
	var out: Array = []
	var d: Dictionary = _defs[sp]
	var fid := _next_flock
	_next_flock += 1
	var flying := bool(force.get("flying", sp == "seagull" and _rng.randf() < 0.45))
	var base := pos
	var roof := false
	if not flying and not force.has("flying") and _rng.randf() < 0.3:
		var r := _roof_perch(_coast_tops if sp == "seagull" else _town_tops, pos, 0.0, 40.0)
		if not r.is_empty():
			base = r["pos"]
			roof = true
	if not flying and not roof:
		base.y = Game.ground_height(base.x, base.z)
		base = _settle(base)
	_flocks[fid] = {"dest": base, "roof": roof, "t": _clock}
	for i in n:
		var p := base
		if flying:
			var alt := _rng.randf_range(float(d.get("alt_min", 8.0)), float(d.get("alt_max", 20.0)))
			p = pos + Vector3(_rng.randf_range(-8.0, 8.0), 0.0, _rng.randf_range(-8.0, 8.0))
			p.y = maxf(Game.ground_height(p.x, p.z), Game.WATER_LEVEL) + alt
			p.y = maxf(p.y, get_obstacle_top(p, p, 6.0) + 5.0)
		elif i > 0:
			var o := _offset_perch(base, roof)
			p = o["pos"]
			roof = bool(o["roof"])
		var a := spawn_animal(sp, p, {"habitat": hab, "flock": fid, "flying": flying, "roof": roof and not flying,
				"yaw": _rng.randf() * TAU, "persistent": bool(force.get("persistent", false))})
		if a != null:
			out.append(a)
	return out


func _shark_roll() -> void:
	if _shark_cd > 0.0 or not _defs.has("shark") or _species_count("shark") > 0:
		return
	var pts: PackedVector3Array = _hab.get("deep", PackedVector3Array())
	if pts.is_empty() or get_count() >= _cap() or _category_count("water") >= int(CATEGORY_CAP["water"]):
		return
	var near := false
	for p in pts:
		if Vector2(p.x - _focus.x, p.z - _focus.z).length() < 140.0:
			near = true
			break
	if not near:
		return
	var swimming: bool = Game.has_player() and (Game.player.get("is_swimming") == true or Game.player.get("is_underwater") == true)
	if _rng.randf() > (0.7 if swimming else 0.3):
		return
	for i in 8:
		var p := pts[_rng.randi() % pts.size()]
		var d := Vector2(p.x - _focus.x, p.z - _focus.z).length()
		if d < 40.0 or d > 115.0:
			continue
		spawn_animal("shark", p, {"habitat": "deep", "home": p})
		return


func _urban_district() -> String:
	if Game.world == null or not Game.world.has_method("get_district"):
		return ""
	var dist := String(Game.world.get_district(_focus))
	if URBAN_TABLE.has(dist):
		return dist
	return ""


func _habitat_at(p: Vector3) -> String:
	if Game.world == null or not Game.world.has_method("get_district"):
		return "wild"
	if Game.world.has_method("get_water_depth") and float(Game.world.get_water_depth(p.x, p.z)) > 0.5:
		return "reef"
	var dist := String(Game.world.get_district(p))
	if dist == "hill":
		return "hill"
	if Vector2(p.x - _park_centre.x, p.z - _park_centre.z).length() < 40.0:
		return "park"
	if dist in TOWN_DISTRICTS or dist == "industrial" or dist == "airport":
		return "urban"
	if dist == "beach" or dist == "waterfront":
		var surf := String(Game.world.get_surface_at(p)) if Game.world.has_method("get_surface_at") else ""
		if surf in ["asphalt", "concrete", "wood"]:
			return "urban"
		return "beach" if surf == "sand" else "wild"
	return "wild"


# =================================================================================================
# habitats
# =================================================================================================

func _build_habitats() -> void:
	_hab.clear()
	for k: String in ["hill", "wild", "park", "beach", "coast", "reef", "deep", "pasture"]:
		_hab[k] = PackedVector3Array()
	var w := Game.world
	if w == null or not w.has_method("get_spawn_points"):
		push_warning("[Wildlife] no world: no habitats")
		return
	if w.has_method("has_location") and bool(w.has_location("residential_park")):
		_park_centre = (w.get_location("residential_park") as Transform3D).origin
	if w.has_method("has_location") and bool(w.has_location("downtown_plaza")):
		_plaza_centre = (w.get_location("downtown_plaza") as Transform3D).origin
	# land points (packed arrays are values inside a Dictionary: fill locals, store them after)
	var land := {"hill": PackedVector3Array(), "wild": PackedVector3Array(), "park": PackedVector3Array(),
			"beach": PackedVector3Array()}
	for xf: Transform3D in w.get_spawn_points("wildlife_land"):
		var p := xf.origin
		var dist := String(w.get_district(p))
		var key := "wild"
		if dist == "hill":
			key = "hill"
		elif Vector2(p.x - _park_centre.x, p.z - _park_centre.z).length() < 45.0:
			key = "park"
		elif String(w.get_surface_at(p)) == "sand" and dist == "beach":
			key = "beach"
		var arr: PackedVector3Array = land[key]
		arr.append(p)
		land[key] = arr
	for k: String in land:
		_hab[k] = land[k]
	var past := PackedVector3Array()
	for xf: Transform3D in w.get_spawn_points("pasture"):
		past.append(xf.origin)
	_hab["pasture"] = past
	# water: wildlife_water points + reef decor points (at least 3 m deep)
	var reef := PackedVector3Array()
	var deep0 := PackedVector3Array()
	for xf: Transform3D in w.get_spawn_points("wildlife_water"):
		var p := xf.origin
		var depth := float(w.get_water_depth(p.x, p.z))
		if depth >= 3.0:
			reef.append(Vector3(p.x, -depth * 0.5, p.z))
		if depth > 9.0 and Vector2(p.x - 148.0, p.z - 298.0).length() < 90.0:
			deep0.append(Vector3(p.x, -depth * 0.55, p.z))
	var rp: Array = w.get_spawn_points("reef")
	var step := maxi(1, rp.size() / 90)
	for i in range(0, rp.size(), step):
		var p := (rp[i] as Transform3D).origin
		var depth := float(w.get_water_depth(p.x, p.z))
		if depth >= 3.0:
			reef.append(Vector3(p.x, -depth * 0.5, p.z))
	_hab["reef"] = reef
	# the deep basin south of the beach around the wreck
	var deep: PackedVector3Array = deep0
	for x in range(80, 236, 16):
		for z in range(262, 350, 16):
			var depth := float(w.get_water_depth(float(x), float(z)))
			if depth > 9.0:
				deep.append(Vector3(float(x), -depth * 0.55, float(z)))
	_hab["deep"] = deep
	# coast perches for gulls
	var coast := PackedVector3Array()
	for z in range(-90, 250, 14):
		_add_perch(coast, -277.6, float(z))
	for x in range(-270, -30, 14):
		_add_perch(coast, float(x), 250.8)
	for px: float in [-210.0, -150.0, -90.0]:
		for z: float in [262.0, 272.0, 283.0]:
			_add_perch(coast, px + _rng.randf_range(-1.1, 1.1), z)
	for x in range(50, 242, 16):
		_add_perch(coast, float(x), 234.4)
		_add_perch(coast, float(x) + 8.0, 249.0 + _rng.randf_range(0.0, 8.0))
	for i in 6:
		var ang := TAU * float(i) / 6.0
		_add_perch(coast, 8.0 + cos(ang) * 6.5, 274.0 + sin(ang) * 6.5)
	_hab["coast"] = coast
	# building tops (perches on roofs, flight clearance)
	_all_tops.clear()
	_coast_tops.clear()
	_town_tops.clear()
	var city := Game.get_system("city")
	if city != null and city.has_method("get_buildings"):
		for bd: Dictionary in city.call("get_buildings"):
			if not bd.has("rect") or not bd.has("transform"):
				continue
			var rect: Rect2 = bd["rect"]
			var top := (bd["transform"] as Transform3D).origin.y + float(bd.get("height", 8.0))
			_all_tops.append([rect, top])
			var dist := String(bd.get("district", ""))
			var cat := String(bd.get("category", ""))
			var h := float(bd.get("height", 8.0))
			if h < 4.0 or h > 34.0 or cat == "house" or String(bd.get("role", "")) == "pier":
				continue
			if rect.size.x < 6.0 or rect.size.y < 6.0:
				continue
			if dist in COAST_DISTRICTS:
				_coast_tops.append([rect, top])
			if dist in TOWN_DISTRICTS:
				_town_tops.append([rect, top])
	_built = true


func _add_perch(arr: PackedVector3Array, x: float, z: float) -> void:
	var w := Game.world
	if float(w.get_water_depth(x, z)) > -0.05:
		return
	var y := float(w.get_height(x, z))
	if y < 0.3:
		return
	arr.append(Vector3(x, y, z))
