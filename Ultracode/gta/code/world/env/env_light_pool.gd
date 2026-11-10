extends Node3D
## ENVIRONMENT module helper: pooled night street lights.
##
## Other modules only REGISTER lamp positions (EnvironmentSystem.register_light_points, or simply
## put the lamp node into the group "street_light" - the environment system registers those by
## itself). At night at most `max_lights` (<= POOL_SIZE) real OmniLight3D (no shadows) sit on the
## registered points nearest to the camera and fade in / out as the camera moves; every other
## lamp is emissive-only (lamp lens material driven by gta_night). By day the pool is completely
## off (zero light cost). Lookup is a coarse grid, so thousands of registered points stay cheap.
##
## Points registered as Node3D are OWNED by that node: when the node is freed, or moves more
## than OWNER_MOVE_LIMIT away from where it was registered (a lamp post that was knocked over),
## its light goes out for good. Vector3 / Transform3D points are static.
## Registering a point twice (within DEDUPE_DISTANCE) is harmless: the second one is ignored.

const POOL_SIZE := 14
const RESCAN_INTERVAL := 0.2          ## seconds between nearest-point searches
const MAX_DISTANCE := 95.0            ## points further than this from the focus never get a light
const FOCUS_AHEAD := 14.0             ## search around a point this far in front of the camera
const FADE_SPEED := 2.6               ## 1 / seconds
const GRID_CELL := 48.0
const NIGHT_START := 0.30             ## gta_night where the lamps begin to switch on
const NIGHT_FULL := 0.55
const LIGHT_DROP := 0.35              ## the light sits this far below the registered lens point
const LIGHT_ATTENUATION := 0.55       ## OmniLight3D.omni_attenuation of the pooled lights
const DEDUPE_DISTANCE := 0.75         ## a new point this close to a live one is a duplicate
const OWNER_MOVE_LIMIT := 1.0         ## metres an owner node may drift before its light dies

## How many pooled lights may be lit at once (0..POOL_SIZE). Lower it when other light users
## (headlights, police light bars, muzzle flashes) need a bigger share of the 16-light budget.
var max_lights: int = POOL_SIZE

var _pos := PackedVector3Array()
var _col := PackedColorArray()
var _range := PackedFloat32Array()
var _energy := PackedFloat32Array()
var _owner := PackedInt64Array()      ## instance id of the owning Node3D, 0 = static point
var _dead := PackedByteArray()        ## 1 = the owner is gone / knocked over: never lit again
var _grid: Dictionary = {}            ## Vector2i cell -> PackedInt32Array of point indices
var _live_count: int = 0

var _lights: Array[OmniLight3D] = []
var _slot_point := PackedInt32Array()     ## point index per pooled light, -1 = free
var _slot_level := PackedFloat32Array()   ## current fade 0..1
var _slot_target := PackedFloat32Array()
var _point_slot: Dictionary = {}          ## point index -> slot

var _rescan_timer: float = 0.0
var _night_gain: float = 0.0
var _wanted := PackedInt32Array()
var _wanted_d := PackedFloat32Array()


func _ready() -> void:
	_build()


func _build() -> void:
	if not _lights.is_empty():
		return
	_slot_point.resize(POOL_SIZE)
	_slot_level.resize(POOL_SIZE)
	_slot_target.resize(POOL_SIZE)
	for i in POOL_SIZE:
		var l := OmniLight3D.new()
		l.name = "StreetLight%02d" % i
		l.shadow_enabled = false
		l.light_bake_mode = Light3D.BAKE_DISABLED
		# Soft falloff: with the engine's 1/d^attenuation law a lamp 5-9 m above the street
		# still throws a clearly readable pool at the registered energy (2-4).
		l.omni_attenuation = LIGHT_ATTENUATION
		l.light_specular = 0.35
		l.distance_fade_enabled = true
		l.distance_fade_begin = 80.0
		l.distance_fade_length = 25.0
		l.visible = false
		add_child(l)
		_lights.append(l)
		_slot_point[i] = -1
		_slot_level[i] = 0.0
		_slot_target[i] = 0.0


## Adds lamp positions (Vector3, Transform3D or Node3D entries). Returns how many were added
## (duplicates of points that are already registered are skipped and not counted).
func register_points(points: Array, color: Color, light_range: float, energy: float) -> int:
	var added := 0
	for p: Variant in points:
		var v: Vector3
		var owner_id := 0
		if p is Vector3:
			v = p
		elif p is Transform3D:
			v = (p as Transform3D).origin
		elif p is Node3D and is_instance_valid(p):
			var n3 := p as Node3D
			if not n3.is_inside_tree():
				continue
			v = n3.global_position
			owner_id = n3.get_instance_id()
		else:
			continue
		var cell := Vector2i(floori(v.x / GRID_CELL), floori(v.z / GRID_CELL))
		var revive := -1
		var duplicate := false
		for cz in range(cell.y - 1, cell.y + 2):
			for cx in range(cell.x - 1, cell.x + 2):
				var near: Variant = _grid.get(Vector2i(cx, cz))
				if near == null:
					continue
				for other: int in (near as PackedInt32Array):
					if _pos[other].distance_squared_to(v) > DEDUPE_DISTANCE * DEDUPE_DISTANCE:
						continue
					if _dead[other] == 0:
						duplicate = true
					elif revive < 0:
						revive = other
		if duplicate:
			continue
		if revive >= 0:
			# A lamp was put back where a broken one stood: reuse its entry.
			_pos[revive] = v
			_col[revive] = color
			_range[revive] = maxf(light_range, 1.0)
			_energy[revive] = maxf(energy, 0.0)
			_owner[revive] = owner_id
			_dead[revive] = 0
			_live_count += 1
			added += 1
			continue
		var idx := _pos.size()
		_pos.append(v)
		_col.append(color)
		_range.append(maxf(light_range, 1.0))
		_energy.append(maxf(energy, 0.0))
		_owner.append(owner_id)
		_dead.append(0)
		var bucket: PackedInt32Array = _grid.get(cell, PackedInt32Array())
		bucket.append(idx)
		_grid[cell] = bucket
		_live_count += 1
		added += 1
	_rescan_timer = 0.0
	return added


func clear_points() -> void:
	_pos.clear()
	_col.clear()
	_range.clear()
	_energy.clear()
	_owner.clear()
	_dead.clear()
	_grid.clear()
	_point_slot.clear()
	_live_count = 0
	for i in _lights.size():
		_slot_point[i] = -1
		_slot_level[i] = 0.0
		_slot_target[i] = 0.0
		_lights[i].visible = false


## Number of registered points that can still be lit (dead lamps are not counted).
func get_point_count() -> int:
	return _live_count


## Number of pooled lights that are currently lit.
func get_active_count() -> int:
	var n := 0
	for i in _lights.size():
		if _lights[i].visible:
			n += 1
	return n


func set_max_lights(n: int) -> void:
	max_lights = clampi(n, 0, POOL_SIZE)
	_rescan_timer = 0.0


## Called every frame by EnvironmentSystem. `night` is the gta_night value (0..1).
func update_pool(cam: Camera3D, delta: float, night: float) -> void:
	if _lights.is_empty():
		return
	_night_gain = smoothstep(NIGHT_START, NIGHT_FULL, night)
	if _night_gain <= 0.0 or _live_count <= 0 or cam == null or max_lights <= 0:
		if not _point_slot.is_empty():
			for i in _lights.size():
				_slot_point[i] = -1
				_slot_level[i] = 0.0
				_slot_target[i] = 0.0
				_lights[i].visible = false
			_point_slot.clear()
		return
	_rescan_timer -= delta
	if _rescan_timer <= 0.0:
		_rescan_timer = RESCAN_INTERVAL
		var fwd := -cam.global_transform.basis.z
		var focus := cam.global_position + Vector3(fwd.x, 0.0, fwd.z) * FOCUS_AHEAD
		_rescan(focus)
	var step := FADE_SPEED * delta
	for i in _lights.size():
		var pt := _slot_point[i]
		if pt < 0:
			continue
		var level := move_toward(_slot_level[i], _slot_target[i], step)
		_slot_level[i] = level
		var l := _lights[i]
		if level <= 0.0 and _slot_target[i] <= 0.0:
			_point_slot.erase(pt)
			_slot_point[i] = -1
			l.visible = false
			continue
		l.light_energy = _energy[pt] * level * _night_gain
		l.visible = true


## False once the node that owns point `idx` is gone or has been knocked away from its place.
func _owner_alive(idx: int) -> bool:
	var owner_id := _owner[idx]
	if owner_id == 0:
		return true
	var obj := instance_from_id(owner_id)
	if obj == null or not is_instance_valid(obj):
		return false
	var n3 := obj as Node3D
	if n3 == null or not n3.is_inside_tree():
		return false
	return n3.global_position.distance_squared_to(_pos[idx]) <= OWNER_MOVE_LIMIT * OWNER_MOVE_LIMIT


func _kill_point(idx: int) -> void:
	if _dead[idx] != 0:
		return
	_dead[idx] = 1
	_live_count -= 1
	var slot: int = _point_slot.get(idx, -1)
	if slot >= 0:
		# Broken lamps go dark at once (no gentle fade).
		_point_slot.erase(idx)
		_slot_point[slot] = -1
		_slot_level[slot] = 0.0
		_slot_target[slot] = 0.0
		_lights[slot].visible = false


func _rescan(focus: Vector3) -> void:
	# Collect the `max_lights` nearest live points (insertion into a small sorted list).
	_wanted.clear()
	_wanted_d.clear()
	var budget := clampi(max_lights, 0, POOL_SIZE)
	var max_d2 := MAX_DISTANCE * MAX_DISTANCE
	var c0 := Vector2i(floori((focus.x - MAX_DISTANCE) / GRID_CELL), floori((focus.z - MAX_DISTANCE) / GRID_CELL))
	var c1 := Vector2i(floori((focus.x + MAX_DISTANCE) / GRID_CELL), floori((focus.z + MAX_DISTANCE) / GRID_CELL))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var bucket: Variant = _grid.get(Vector2i(cx, cz))
			if bucket == null:
				continue
			for idx: int in (bucket as PackedInt32Array):
				if _dead[idx] != 0:
					continue
				var d2 := _pos[idx].distance_squared_to(focus)
				if d2 > max_d2:
					continue
				var n := _wanted.size()
				if n >= budget and d2 >= _wanted_d[n - 1]:
					continue
				if not _owner_alive(idx):
					_kill_point(idx)
					continue
				var at := n
				while at > 0 and _wanted_d[at - 1] > d2:
					at -= 1
				_wanted.insert(at, idx)
				_wanted_d.insert(at, d2)
				if _wanted.size() > budget:
					_wanted.remove_at(budget)
					_wanted_d.remove_at(budget)
	# Lights whose point is no longer wanted fade out.
	for i in _lights.size():
		var pt := _slot_point[i]
		if pt >= 0:
			_slot_target[i] = 1.0 if _wanted.has(pt) else 0.0
	# Wanted points without a light take a free slot.
	for idx: int in _wanted:
		if _point_slot.has(idx):
			continue
		var slot := _slot_point.find(-1)
		if slot < 0:
			break
		_slot_point[slot] = idx
		_slot_level[slot] = 0.0
		_slot_target[slot] = 1.0
		_point_slot[idx] = slot
		var l := _lights[slot]
		l.global_position = _pos[idx] - Vector3(0.0, LIGHT_DROP, 0.0)
		l.light_color = _col[idx]
		l.omni_range = _range[idx]
		l.light_energy = 0.0
