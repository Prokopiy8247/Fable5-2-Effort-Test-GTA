class_name Minimap
extends Control
## Circular HUD minimap (bottom-left). Heading-up: the map rotates with the camera yaw.
##
## Efficiency: the static world geometry lives in a MinimapWorldLayer that is drawn once; every
## frame only the transform of that node changes. Dynamic things (route, search circle, place
## icons, waypoint, police blips) are drawn in the same map space on a second layer that is
## redrawn at REDRAW_HZ and shares the transform, so everything moves smoothly at 60 fps.
## Both layers are Node2D (not Control) so they are culled by their content, not by a zero rect.
## Without map data it shows a plain radar (range rings) with the same blips.
##
## Extra blips for other modules: add a Node3D to the group "minimap_blip" and optionally set
## metas "blip_icon" (UiIcons id), "blip_color" (Color), "blip_clamp" (bool: stick to the rim).
##
## Police: group "police" nodes are dots; a police node that is a helicopter (vehicle_class
## "heli") - or an officer seated in one - is drawn once as a heli glyph with its search light.
## During SEARCH the search circle is centred on Wanted.search_center and every officer / cruiser
## in range shows a short sight cone. A soft ring shows how far the player's noise carries
## (player.noise_radius) while on foot.

const DIAMETER := 268.0
const MAP_RADIUS := 124.0
const RANGE_FOOT := 95.0
const RANGE_VEHICLE := 150.0
const RANGE_VEHICLE_FAST := 235.0
const RANGE_AIR := 330.0
const REDRAW_HZ := 30.0
const CONE_FOOT := 24.0          ## sight cone length (m) of an officer on foot during SEARCH
const CONE_VEHICLE := 34.0
const CONE_HALF_DEG := 32.0
const MAX_CONES := 18

var data: UiMapData = null
var nav: UiNav = null
var zoom: float = MAP_RADIUS / RANGE_FOOT        ## logical px per metre
var range_override: float = 0.0                  ## > 0 forces the shown radius in metres (tests)
var air_mode: bool = false                       ## skydiving (set by HudRoot): aircraft range

var _base: UiCanvas
var _clip: UiCanvas
var _world: MinimapWorldLayer
var _dyn: UiCanvas2D
var _ring: UiCanvas
var _arrow: UiCanvas
var _north: UiCanvas
var _pos: Vector2 = Vector2.ZERO
var _yaw: float = 0.0
var _heading: float = 0.0
var _timer: float = 0.0
var _slow: float = 1.0
var _flash: float = 0.0
var _police: Array = []
var _blips: Array = []
var _ring_state: int = -1
var _cone: PackedVector2Array = PackedVector2Array()
var _heli_ids: PackedInt64Array = PackedInt64Array()
var _noise_r: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(DIAMETER, DIAMETER)
	size = custom_minimum_size


func _ready() -> void:
	var full := Vector2(DIAMETER, DIAMETER)
	_base = UiCanvas.new(_draw_base)
	_base.size = full
	add_child(_base)
	_clip = UiCanvas.new(_draw_clip)
	_clip.name = "Clip"
	_clip.size = full
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	add_child(_clip)
	_world = MinimapWorldLayer.new()
	_clip.add_child(_world)
	_dyn = UiCanvas2D.new(_draw_dyn)
	_clip.add_child(_dyn)
	_ring = UiCanvas.new(_draw_ring)
	_ring.size = full
	add_child(_ring)
	_arrow = UiCanvas.new(_draw_arrow)
	_arrow.size = Vector2(44, 44)
	_arrow.pivot_offset = Vector2(22, 22)
	_arrow.position = full * 0.5 - Vector2(22, 22)
	add_child(_arrow)
	_north = UiCanvas.new(_draw_north)
	_north.size = Vector2(30, 30)
	add_child(_north)
	if data != null:
		_world.set_data(data)
	_apply_transform()


func set_sources(p_data: UiMapData, p_nav: UiNav) -> void:
	data = p_data
	nav = p_nav
	if _world != null:
		_world.set_data(data)


func get_shown_range() -> float:
	return MAP_RADIUS / maxf(zoom, 0.001)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var p3 := Game.get_player_position()
	_pos = Vector2(p3.x, p3.z)
	_yaw = _camera_yaw()
	_heading = _player_heading()
	var range_m := RANGE_FOOT
	var veh := Game.get_player_vehicle()
	if veh != null:
		var cls := UiKit.text_of(veh, &"vehicle_class", "car")
		if cls == "heli" or cls == "plane":
			range_m = RANGE_AIR
		else:
			range_m = lerpf(RANGE_VEHICLE, RANGE_VEHICLE_FAST, clampf(absf(UiKit.num(veh, &"speed_kmh")) / 140.0, 0.0, 1.0))
	elif air_mode:
		range_m = RANGE_AIR
	if range_override > 0.0:
		range_m = range_override
	zoom = lerpf(zoom, MAP_RADIUS / range_m, 1.0 - exp(-2.5 * delta))
	_apply_transform()
	_flash += delta
	_timer += delta
	var nr := 0.0
	if veh == null and Game.has_player():
		nr = UiKit.num(Game.player, &"noise_radius", 0.0)
	_noise_r = nr if nr > _noise_r else maxf(_noise_r - delta * maxf(_noise_r, 4.0) * 0.9, 0.0)
	if _timer >= 1.0 / REDRAW_HZ:
		_timer = 0.0
		_dyn.queue_redraw()
	_slow += delta
	if _slow >= 0.25:
		_slow = 0.0
		_slow_update()


func _apply_transform() -> void:
	var c := Vector2(DIAMETER, DIAMETER) * 0.5
	var origin := c - (_pos * zoom).rotated(_yaw)
	var sc := Vector2(zoom, zoom)
	_world.position = origin
	_world.rotation = _yaw
	_world.scale = sc
	_dyn.position = origin
	_dyn.rotation = _yaw
	_dyn.scale = sc
	_arrow.rotation = _yaw - _heading
	_north.position = c + Vector2(sin(_yaw), -cos(_yaw)) * (MAP_RADIUS + 2.0) - _north.size * 0.5


func _slow_update() -> void:
	if data != null:
		if data.source != "world" and Game.world != null and is_instance_valid(Game.world):
			data.refresh()
		_world.check_version()
	var tree := get_tree()
	_police = tree.get_nodes_in_group("police")
	_blips = tree.get_nodes_in_group("minimap_blip")
	var state := 0
	if Wanted.level > 0:
		state = 2 if Wanted.state == Wanted.State.SEARCH else (3 + (int(_flash * 4.0) % 2))
	if state != _ring_state:
		_ring_state = state
		_ring.queue_redraw()


func _camera_yaw() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var fwd := -cam.global_transform.basis.z
		if absf(fwd.x) + absf(fwd.z) > 0.05:
			return atan2(-fwd.x, -fwd.z)
	var rig := Game.camera_rig
	if rig != null and is_instance_valid(rig):
		return UiKit.num(rig, &"yaw", _yaw)
	return _yaw


func _player_heading() -> float:
	var node: Node3D = Game.get_player_vehicle()
	if node == null and Game.has_player():
		node = Game.player
	if node == null:
		return _yaw
	var fwd := -node.global_transform.basis.z
	if absf(fwd.x) + absf(fwd.z) < 0.01:
		return _heading
	return atan2(-fwd.x, -fwd.z)


# --- drawing ---------------------------------------------------------------------------------------

func _draw_base(c: UiCanvas) -> void:
	var ctr := c.size * 0.5
	c.draw_circle(ctr + Vector2(0, 5), MAP_RADIUS + 11.0, Color(0, 0, 0, 0.3), true, -1.0, true)


func _draw_clip(c: UiCanvas) -> void:
	c.draw_circle(c.size * 0.5, MAP_RADIUS + 0.5, Color(MinimapWorldLayer.SEA, 0.96), true, -1.0, true)


func _draw_ring(c: UiCanvas) -> void:
	var ctr := c.size * 0.5
	c.draw_arc(ctr, MAP_RADIUS + 3.5, 0.0, TAU, 96, Color(UiStyle.NAVY_DEEP, 0.96), 9.0, true)
	var tint: Color = UiStyle.LINE_STRONG
	match _ring_state:
		2: tint = UiStyle.CORAL
		3: tint = UiStyle.POLICE_RED
		4: tint = UiStyle.POLICE_BLUE
	c.draw_arc(ctr, MAP_RADIUS + 8.0, 0.0, TAU, 96, tint, 2.5 if _ring_state >= 2 else 2.0, true)
	c.draw_arc(ctr, MAP_RADIUS - 1.0, 0.0, TAU, 96, Color(1, 1, 1, 0.1), 1.5, true)


func _draw_arrow(c: UiCanvas) -> void:
	var ctr := c.size * 0.5
	UiIcons.draw(c, &"arrow", ctr, 42.0, UiStyle.NAVY_DEEP)
	UiIcons.draw(c, &"arrow", ctr + Vector2(0, 0.5), 30.0, UiStyle.SUN)


func _draw_north(c: UiCanvas) -> void:
	var ctr := c.size * 0.5
	c.draw_circle(ctr, 14.0, UiStyle.NAVY_DEEP, true, -1.0, true)
	c.draw_arc(ctr, 14.0, 0.0, TAU, 32, UiStyle.CORAL, 2.0, true)
	UiIcons.draw(c, &"north", ctr, 22.0, UiStyle.CORAL)


func _icon(c: CanvasItem, pos: Vector2, icon: StringName, col: Color, inv: float, px: float) -> void:
	c.draw_set_transform(pos, -_yaw, Vector2(inv, inv))
	c.draw_circle(Vector2.ZERO, px * 0.62, Color(UiStyle.NAVY_DEEP, 0.9), true, -1.0, true)
	UiIcons.draw(c, icon, Vector2.ZERO, px * 0.76, col)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _clamp_rim(p: Vector2, rim: float) -> Vector2:
	var d := p - _pos
	var dist := d.length()
	if dist > rim and dist > 0.001:
		return _pos + d / dist * rim
	return p


## Dynamic layer, drawn in MAP SPACE (metres); `inv` converts logical px to metres.
func _draw_dyn(c: UiCanvas2D) -> void:
	var inv := 1.0 / maxf(zoom, 0.01)
	var rim := (MAP_RADIUS - 13.0) * inv
	if data == null or not data.has_map():
		var ring_col := Color(1, 1, 1, 0.13)
		for i in 3:
			c.draw_arc(_pos, MAP_RADIUS * inv * float(i + 1) / 3.0, 0.0, TAU, 48, ring_col, 1.5 * inv, true)
		var r := MAP_RADIUS * inv
		c.draw_line(_pos - Vector2(r, 0), _pos + Vector2(r, 0), ring_col, 1.5 * inv)
		c.draw_line(_pos - Vector2(0, r), _pos + Vector2(0, r), ring_col, 1.5 * inv)
	if nav != null and nav.has_waypoint and nav.route.size() >= 2:
		c.draw_polyline(nav.route, Color(UiStyle.NAVY_DEEP, 0.9), 8.0 * inv, true)
		c.draw_polyline(nav.route, UiStyle.CORAL, 4.5 * inv, true)
	var wanted := Wanted.level > 0
	var searching := wanted and Wanted.state == Wanted.State.SEARCH
	if searching:
		var sc3 := search_center()
		var lk := Vector2(sc3.x, sc3.z)
		var pulse := 0.5 + 0.5 * sin(_flash * 4.0)
		var sr := maxf(Wanted.search_radius, 5.0)
		c.draw_circle(lk, sr, Color(UiStyle.CORAL_HOT, 0.13 + 0.09 * pulse), true, -1.0, true)
		c.draw_arc(lk, sr, 0.0, TAU, 64, Color(UiStyle.CORAL_HOT, 0.85), 2.5 * inv, true)
	if data != null:
		for pl in data.places:
			if bool(pl["minor"]):
				continue
			var pp: Vector2 = pl["pos"]
			if pp.distance_to(_pos) > rim + 4.0 * inv:
				continue
			_icon(c, pp, pl["icon"], pl["color"], inv, clampf(27.0 * zoom / (MAP_RADIUS / RANGE_FOOT) + 6.0, 21.0, 28.0))
	for n in _blips:
		if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		var bp3 := (n as Node3D).global_position
		var bp := Vector2(bp3.x, bp3.z)
		if bp.distance_to(_pos) > rim:
			if not bool((n as Node).get_meta("blip_clamp", false)):
				continue
			bp = _clamp_rim(bp, rim)
		var b_icon: StringName = (n as Node).get_meta("blip_icon", &"circle")
		var b_col: Color = (n as Node).get_meta("blip_color", UiStyle.TEAL_LIGHT)
		_icon(c, bp, b_icon, b_col, inv, 24.0)
	if nav != null and nav.has_waypoint:
		var wp := _clamp_rim(Vector2(nav.waypoint.x, nav.waypoint.z), rim)
		_icon(c, wp, &"pin", UiStyle.CORAL, inv, 30.0)
	if _noise_r > 1.5:
		var na := clampf(_noise_r / 12.0, 0.25, 0.7)
		c.draw_arc(_pos, _noise_r, 0.0, TAU, 40, Color(UiStyle.CREAM, na * 0.8), 2.0 * inv, true)
		c.draw_circle(_pos, _noise_r, Color(UiStyle.CREAM, na * 0.12), true, -1.0, true)
	var blink := int(_flash * 5.0) % 2 == 0
	_heli_ids.clear()
	var cones := 0
	for n in _police:
		if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		var node := n as Node3D
		var heli := is_heli(node)
		if not heli:
			var cv: Variant = node.get(&"current_vehicle")
			if cv is Node3D and is_instance_valid(cv) and is_heli(cv as Node3D):
				node = cv as Node3D
				heli = true
		if heli:
			var hid := node.get_instance_id()
			if _heli_ids.has(hid):
				continue
			_heli_ids.append(hid)
		var p3 := node.global_position
		var pp2 := Vector2(p3.x, p3.z)
		var dist := pp2.distance_to(_pos)
		var clamped := false
		if dist > rim:
			if not wanted or dist > (900.0 if heli else 450.0):
				continue
			pp2 = _clamp_rim(pp2, rim)
			clamped = true
		var col: Color = UiStyle.POLICE_BLUE
		if wanted:
			col = UiStyle.POLICE_RED if blink else UiStyle.POLICE_BLUE
		if heli:
			if not clamped:
				c.draw_circle(pp2, 16.0, Color(UiStyle.CREAM, 0.12 + 0.05 * sin(_flash * 3.0)), true, -1.0, true)
			_icon(c, pp2, &"heli", col, inv, 30.0)
			continue
		if searching and not clamped and cones < MAX_CONES:
			cones += 1
			_draw_cone(c, pp2, node, CONE_VEHICLE if node.is_in_group(&"vehicle") else CONE_FOOT)
		c.draw_circle(pp2, 7.0 * inv, Color(0, 0, 0, 0.65), true, -1.0, true)
		c.draw_circle(pp2, 5.0 * inv, col, true, -1.0, true)


## Translucent sight cone in front of a police unit (map space; forward = -Z of the node).
func _draw_cone(c: CanvasItem, at: Vector2, node: Node3D, length: float) -> void:
	var f := -node.global_transform.basis.z
	if absf(f.x) + absf(f.z) < 0.01:
		return
	var ang := atan2(f.z, f.x)
	var half := deg_to_rad(CONE_HALF_DEG)
	if _cone.size() != 8:
		_cone.resize(8)
	_cone[0] = at
	for i in 7:
		var a := ang - half + half * 2.0 * float(i) / 6.0
		_cone[i + 1] = at + Vector2(cos(a), sin(a)) * length
	c.draw_colored_polygon(_cone, Color(UiStyle.SUN, 0.34))


## A police / any vehicle node that flies as a helicopter.
static func is_heli(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and UiKit.text_of(n, &"vehicle_class", "") == "heli"


## SEARCH centre: Wanted.search_center (last known position drifted along the last velocity)
## when the wanted system provides it, else Wanted.last_known_position.
static func search_center() -> Vector3:
	var sc: Variant = Wanted.get(&"search_center")
	if sc is Vector3 and (sc as Vector3) != Vector3.ZERO:
		return sc
	return Wanted.last_known_position
