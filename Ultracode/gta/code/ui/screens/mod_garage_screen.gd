extends UiScreen
## Torque Garage - vehicle customisation and repair (spec 14A). Owner: Economy B (garage system).
##     UI.open_screen("mod_garage", {"vehicle": v, "shop": torque_garage_helper})   # from the bay
##     UI.open_screen("mod_garage", {"vehicle": v, "remote": true})                  # admin: anywhere
## ("anywhere": true is accepted as "remote"; "free": true makes this session free of charge.)
## Tabs: Repair, Paint, Wheels, Body, Lights, Windows, Plate, Horn, Performance (only those the
## vehicle supports: vehicle.get_mod_options(); classes other than "car" and service vehicles get
## Repair only). Hovering an option previews it on the car (mods / paint applied live, orbit
## camera frames the part), Enter buys it (Game.spend, EventBus.item_purchased + vehicle_modified),
## leaving reverts every preview to what was bought. Stat bars are recomputed from VehicleSpec +
## mods (garage_stats.gd): installed (solid) vs preview (ghost, green = better, coral = worse).
## Controls: Q / E category, A / D section, W / S option, Enter buy, mouse drag orbit, wheel zoom.

const PAUSES_GAME := false
const TIME_SCALE := 1.0
const LOCKS_INPUT := true
const SHOWS_MOUSE := true
const HIDES_HUD := true

const Stats := preload("res://gta/code/world/shops/garage_stats.gd")

const TABS: Array[String] = ["Repair", "Paint", "Wheels", "Body", "Lights", "Windows", "Plate", "Horn", "Performance"]
const BODY_SLOTS: Array[String] = ["spoiler", "bumper_f", "bumper_r", "hood", "skirts", "roof", "exhaust", "grille"]
const PERF_SLOTS: Array[String] = ["engine", "turbo", "transmission", "brakes", "suspension", "tires", "armor"]
const MOD_CLASSES: Array[String] = ["car"]
const SLOT_TITLES := {
	"engine": "Engine", "turbo": "Turbo", "transmission": "Transmission", "brakes": "Brakes",
	"suspension": "Suspension", "tires": "Tyres", "armor": "Armour", "spoiler": "Spoiler",
	"bumper_f": "Front bumper", "bumper_r": "Rear bumper", "hood": "Hood", "skirts": "Side skirts",
	"roof": "Roof", "exhaust": "Exhaust", "grille": "Grille", "wheels": "Rims", "wheel_color": "Rim colour",
	"paint_finish": "Finish", "tint": "Window tint", "lights": "Headlights", "plate": "Plate style", "horn": "Horn",
}
## camera framing per slot / tab: rel yaw (deg, 0 = in front, 90 = left side, 180 = behind), pitch
## (deg up), distance (x car length), look offset (m up from the body centre), "wheel" = frame a wheel
const VIEWS := {
	"default": [38.0, 16.0, 1.18, 0.0], "front": [14.0, 13.0, 1.05, 0.0], "rear": [158.0, 15.0, 1.05, 0.05],
	"side": [92.0, 9.0, 1.1, 0.0], "top": [42.0, 48.0, 1.15, 0.0], "wheel": [64.0, 5.0, 0.52, 0.0],
	"hood": [8.0, 30.0, 0.95, 0.1], "low_rear": [172.0, 6.0, 0.86, -0.15],
}
const SLOT_VIEWS := {
	"spoiler": "rear", "bumper_r": "rear", "exhaust": "low_rear", "bumper_f": "front", "grille": "front",
	"hood": "hood", "skirts": "side", "roof": "top", "wheels": "wheel", "wheel_color": "wheel",
	"lights": "front", "tint": "side", "plate": "low_rear", "primary": "default", "secondary": "side",
	"paint_finish": "default",
}
const AUTO_ORBIT_SPEED := 0.16          ## rad / s while idle on the overview
const IDLE_BEFORE_ORBIT := 2.5

var vehicle: Node3D = null
var shop: Node = null
var remote: bool = false
var free: bool = false                 ## args "free": everything costs 0 this session (admin)
var tab_names: Array[String] = []
var current_tab: String = ""
var sections: Array[Dictionary] = []
var section_index: int = 0
var purchases: int = 0
var spent: int = 0

var _installed_mods: Dictionary = {}
var _installed_primary: Color = Color.WHITE
var _installed_secondary: Color = Color(0, 0, 0, 0)
var _preview_mods: Dictionary = {}
var _options: Dictionary = {}
var _prev_headlights: int = -1
var _honk_left: float = 0.0

var _header: UiHeader
var _tabs: UiTabBar
var _section_label: Label
var _section_row: UiOptionRow
var _list: UiList
var _desc: Label
var _cond_box: VBoxContainer
var _cond_bars: Dictionary = {}
var _repair_spacer: Control
var _stats_canvas: UiCanvas
var _stats_name: Label
var _hints: UiKeyHints

var _cam: Camera3D = null
var _prev_cam: Camera3D = null
var _view: String = "default"
var _rel_yaw: float = 0.6
var _pitch: float = 0.28
var _dist: float = 5.5
var _user_yaw: float = 0.0
var _user_pitch: float = 0.0
var _zoom: float = 1.0
var _idle: float = 0.0
var _auto: float = 0.0
var _dragging: bool = false
var _ray := PhysicsRayQueryParameters3D.new()
var _look: Vector3 = Vector3.ZERO
var _cam_ready: bool = false
var _scroll_pending: int = -1
var _scroll_frames: int = 0


func _init() -> void:
	super()
	backdrop_alpha = 0.0


func _ready() -> void:
	# soft darkening behind the left column so text reads over any background
	var grad := Gradient.new()
	grad.set_color(0, Color(0.015, 0.035, 0.07, 0.82))
	grad.set_color(1, Color(0.015, 0.035, 0.07, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 4
	var shade := TextureRect.new()
	shade.name = "Shade"
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_right = 0.62
	shade.anchor_bottom = 1.0
	add_child(shade)
	# and a band across the top so the title and the tab strip read over a busy street
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.015, 0.035, 0.07, 0.84))
	g2.set_color(1, Color(0.015, 0.035, 0.07, 0.0))
	g2.add_point(0.62, Color(0.015, 0.035, 0.07, 0.62))
	var gt2 := GradientTexture2D.new()
	gt2.gradient = g2
	gt2.fill_from = Vector2(0.5, 0.0)
	gt2.fill_to = Vector2(0.5, 1.0)
	gt2.width = 4
	gt2.height = 128
	var band := TextureRect.new()
	band.name = "TopBand"
	band.texture = gt2
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_right = 1.0
	band.offset_bottom = 290.0
	add_child(band)

	var margin := UiKit.margin(null, 56, 40, 56, 34)
	UiKit.fill(margin)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var col := UiKit.vbox(14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	_header = UiKit.header("Torque Garage", "", UiStyle.money(Game.money))
	_header.title_size = UiStyle.FS_H1
	col.add_child(_header)
	_tabs = UiTabBar.new([], 0)
	_tabs.custom_minimum_size = Vector2(1500.0, 58.0)
	_tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tabs.tab_changed.connect(_on_tab_changed)
	col.add_child(_tabs)

	var row := UiKit.hbox(24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)

	var left := UiPanel.new(&"GlassPanel", 10)
	left.custom_minimum_size = Vector2(660.0, 0.0)
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(left)
	_section_label = UiKit.label("", &"SectionLabel")
	left.add(_section_label)
	_section_row = UiOptionRow.new("Section", [], 0)
	_section_row.focus_mode = Control.FOCUS_NONE
	_section_row.changed.connect(_on_section_changed)
	left.add(_section_row)
	_list = UiList.new()
	_list.custom_minimum_size = Vector2(600.0, 360.0)
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(_on_item_activated)
	left.add(_list)
	_cond_box = UiKit.vbox(4)
	left.add(_cond_box)
	_cond_box.add_child(UiKit.label("CONDITION", &"SectionLabel"))
	for key: String in ["Body", "Glass", "Tyres", "Engine"]:
		var bar := UiBar.new(UiStyle.TEAL, &"", 12.0)
		bar.value_width = 120.0
		var r := UiKit.hbox(12)
		var l := UiKit.label(key.to_upper(), &"MutedLabel")
		l.custom_minimum_size.x = 120.0
		r.add_child(l)
		r.add_child(bar)
		_cond_box.add_child(r)
		_cond_bars[key] = bar
	_repair_spacer = UiKit.spacer(Vector2.ZERO, true)
	_repair_spacer.size_flags_horizontal = Control.SIZE_FILL
	left.add(_repair_spacer)
	_desc = UiKit.paragraph("", &"MutedLabel", 560.0)
	_desc.custom_minimum_size.y = 64.0
	left.add(_desc)

	row.add_child(UiKit.spacer())
	var right := UiKit.vbox(10)
	right.custom_minimum_size.x = 600.0
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	right.add_child(UiKit.spacer())
	var stats_panel := UiPanel.new(&"GlassPanel", 6)
	right.add_child(stats_panel)
	_stats_name = UiKit.label("", &"SectionLabel")
	stats_panel.add(_stats_name)
	_stats_canvas = UiCanvas.new(_draw_stats)
	_stats_canvas.custom_minimum_size = Vector2(560.0, 5.0 * 62.0 + 8.0)
	stats_panel.add(_stats_canvas)

	_hints = UiKeyHints.new([{"keys": ["Q", "E"], "text": "Category"}, {"keys": ["A", "D"], "text": "Section"},
			{"keys": ["W", "S"], "text": "Option"}, {"key": "Enter", "text": "Buy"}, {"key": "Mouse", "text": "Drag to rotate"},
			{"action": "pause", "text": "Leave"}])
	col.add_child(_hints)
	_ray.collision_mask = Layers.WORLD
	_ray.collide_with_areas = false
	EventBus.money_changed.connect(_on_money_changed)


func open(args: Dictionary) -> void:
	var v: Variant = args.get("vehicle", null)
	if v == null or not is_instance_valid(v):
		v = Game.get_player_vehicle()
	if v == null or not is_instance_valid(v):
		UI.notify("No vehicle to work on", "warn")
		close_self.call_deferred()
		return
	vehicle = v as Node3D
	var s: Variant = args.get("shop", null)
	shop = s as Node if (s != null and is_instance_valid(s)) else null
	remote = bool(args.get("remote", false)) or bool(args.get("anywhere", false)) or shop == null
	free = bool(args.get("free", false))
	_snapshot_installed()
	_options = {}
	if _mods_supported() and vehicle.has_method("get_mod_options"):
		var o: Variant = vehicle.call("get_mod_options")
		if o is Dictionary:
			_options = o
	tab_names = _available_tabs()
	var titles: Array = []
	for t: String in tab_names:
		titles.append(t)
	_tabs.set_tabs(titles, 0)
	_header.subtitle = "%s%s" % [Stats.vehicle_name(vehicle), "  -  remote session" if remote else ""]
	_stats_name.text = Stats.vehicle_name(vehicle).to_upper()
	if remote and vehicle.has_method("release_inputs"):
		vehicle.call("release_inputs")
	_setup_camera()
	var start := str(args.get("tab", ""))
	_show_tab(start if tab_names.has(start) else tab_names[0])


func close() -> void:
	_revert_preview()
	_restore_headlights()
	_stop_honk()
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	if _prev_cam != null and is_instance_valid(_prev_cam) and _prev_cam.is_inside_tree():
		_prev_cam.make_current()
	elif Game.camera_rig != null and is_instance_valid(Game.camera_rig):
		var c: Variant = Game.camera_rig.get("camera")
		if c is Camera3D and is_instance_valid(c):
			(c as Camera3D).make_current()


func regain_focus() -> void:
	_list.grab()


# =================================================================================================
# public API (tests, admin)
# =================================================================================================

func get_tab_names() -> Array[String]:
	return tab_names.duplicate()


func select_tab(tab: String) -> bool:
	if not tab_names.has(tab):
		return false
	_tabs.select(tab_names.find(tab), false)
	_show_tab(tab)
	return true


func select_section(i: int) -> void:
	if sections.is_empty():
		return
	_show_section(clampi(i, 0, sections.size() - 1))


## Moves the cursor to a section by slot ("wheels", "spoiler", ...) or paint layer ("primary").
func select_section_for(slot: String) -> bool:
	for i in sections.size():
		if str(sections[i].get("slot", sections[i].get("layer", ""))) == slot:
			_show_section(i)
			return true
	return false


## Moves the cursor (and so the live preview) to the row of a mod id, a palette colour name or
## "" (stock), exactly as hovering it would.
func select_option(key: String) -> bool:
	for i in _list.get_count():
		var it := _list.get_item(i)
		var id: Dictionary = it.get("id", {}) if it.get("id", {}) is Dictionary else {}
		if str(id.get("mod_id", "<none>")) == key or (str(id.get("type", "")) == "paint" and str(it.get("text", "")) == key):
			_list.select(i, true)
			_scroll_to(i)
			return true
	return false


func get_installed_mods() -> Dictionary:
	return _installed_mods.duplicate()


## Stat bars of the installed build (preview = false) or the build on the car right now.
func get_stats(preview: bool = false) -> Dictionary:
	return Stats.stats_for(Stats.spec_of(vehicle), _preview_mods if preview else _installed_mods)


## Hover equivalent: shows `mod_id` ("" = stock) in `slot` on the car without buying it.
func preview_mod(slot: String, mod_id: String) -> void:
	_preview({"type": "mod", "slot": slot, "mod_id": mod_id})


func purchase_mod(slot: String, mod_id: String) -> bool:
	return _purchase({"type": "mod", "slot": slot, "mod_id": mod_id})


func purchase_paint(layer: String, color: Color) -> bool:
	return _purchase({"type": "paint", "layer": layer, "color": color})


func purchase_repair() -> bool:
	return _purchase({"type": "repair"})


# =================================================================================================
# tabs / sections / items
# =================================================================================================

func _mods_supported() -> bool:
	if vehicle == null:
		return false
	var cls := Stats.text(vehicle, "vehicle_class", "car")
	if not MOD_CLASSES.has(cls):
		return false
	return not (Stats.flag(vehicle, "is_police") or Stats.flag(vehicle, "is_emergency"))


func _paint_allowed() -> bool:
	if not _mods_supported():
		return false
	var spec := Stats.spec_of(vehicle)
	if spec != null and Stats.flag(spec, "fixed_livery"):
		return false
	return vehicle.has_method("has_material") and bool(vehicle.call("has_material", "M_Paint_Primary"))


func _sections_for(tab: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match tab:
		"Repair":
			out.append({"kind": "repair", "title": "Repair", "view": "default"})
		"Paint":
			if _paint_allowed():
				out.append({"kind": "paint", "layer": "primary", "title": "Primary colour", "view": "default"})
				if bool(vehicle.call("has_material", "M_Paint_Secondary")):
					out.append({"kind": "paint", "layer": "secondary", "title": "Secondary colour", "view": "side"})
			_add_mod_section(out, "paint_finish")
		"Wheels":
			_add_mod_section(out, "wheels")
			_add_mod_section(out, "wheel_color")
		"Body":
			for s: String in BODY_SLOTS:
				_add_mod_section(out, s)
		"Lights":
			_add_mod_section(out, "lights")
		"Windows":
			_add_mod_section(out, "tint")
		"Plate":
			_add_mod_section(out, "plate")
		"Horn":
			_add_mod_section(out, "horn")
		"Performance":
			for s: String in PERF_SLOTS:
				_add_mod_section(out, s)
	return out


func _add_mod_section(out: Array[Dictionary], slot: String) -> void:
	var ids: Variant = _options.get(slot, [])
	if ids is Array and not (ids as Array).is_empty():
		out.append({"kind": "mod", "slot": slot, "title": str(SLOT_TITLES.get(slot, slot.capitalize())),
				"ids": ids, "view": str(SLOT_VIEWS.get(slot, "default"))})


func _available_tabs() -> Array[String]:
	var out: Array[String] = []
	for t: String in TABS:
		if not _sections_for(t).is_empty():
			out.append(t)
	return out


func _on_tab_changed(i: int) -> void:
	if i >= 0 and i < tab_names.size():
		_show_tab(tab_names[i])


func _show_tab(tab: String) -> void:
	_revert_preview()
	if current_tab == "Lights" and tab != "Lights":
		_restore_headlights()
	_stop_honk()
	current_tab = tab
	sections = _sections_for(tab)
	if tab == "Lights" and vehicle != null and _prev_headlights < 0:
		_prev_headlights = int(vehicle.get("headlight_mode")) if vehicle.get("headlight_mode") is int else 0
		if vehicle.has_method("set_headlights"):
			vehicle.call("set_headlights", 2)
	var titles: Array = []
	for s: Dictionary in sections:
		titles.append(str(s["title"]))
	_section_row.options = titles
	_section_row.visible = sections.size() > 1
	_cond_box.visible = tab == "Repair"
	_repair_spacer.visible = tab == "Repair"
	_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if tab == "Repair" else Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.y = 84.0 if tab == "Repair" else 360.0
	_show_section(0)


## Rows are created this frame: scroll once they have a layout (handled in _process).
func _scroll_to(index: int) -> void:
	_scroll_pending = index
	_scroll_frames = 2


func _on_section_changed(i: int) -> void:
	_show_section(i)


func _show_section(i: int) -> void:
	_revert_preview()
	section_index = i
	_section_row.set_index_silent(i)
	var sec: Dictionary = sections[i] if i < sections.size() else {}
	_section_label.text = current_tab.to_upper() if sections.size() > 1 else ("%s  -  %s" % [current_tab, str(sec.get("title", ""))]).to_upper()
	if current_tab == str(sec.get("title", "")):
		_section_label.text = current_tab.to_upper()
	_view = str(sec.get("view", "default"))
	_user_yaw = 0.0
	_user_pitch = 0.0
	_idle = 0.0
	var items := _items_for(sec)
	_list.set_items(items)
	var sel := 0
	for k in items.size():
		if bool(items[k].get("owned", false)):
			sel = k
			break
	_list.select(sel, true)
	_scroll_to(sel)
	_refresh_condition()
	_stats_canvas.queue_redraw()


func _items_for(sec: Dictionary) -> Array:
	var items: Array = []
	match str(sec.get("kind", "")):
		"repair":
			var cost := _price(Stats.repair_cost(vehicle))
			var c := Stats.condition(vehicle)
			if Stats.needs_repair(c):
				items.append({"text": "Full repair", "sub": "Body, glass, lights, tyres and handling", "price": cost,
						"icon": &"wrench", "id": {"type": "repair"}})
			else:
				items.append({"text": "Nothing to repair", "sub": "The vehicle is in perfect condition", "icon": &"check",
						"icon_color": UiStyle.GOOD, "disabled": true, "id": {"type": "none"}})
		"paint":
			var layer := str(sec["layer"])
			var cur := _installed_primary if layer == "primary" else _installed_secondary
			var base_price := Stats.PRIMARY_PRICE if layer == "primary" else Stats.SECONDARY_PRICE
			var found := false
			for e: Dictionary in Stats.PALETTE:
				var col: Color = e["color"]
				var owned := Stats.same_color(col, cur) and (layer == "primary" or cur.a > 0.0)
				found = found or owned
				items.append({"text": str(e["name"]), "icon": &"circle", "icon_color": col, "price": _price(Stats.price(base_price)),
						"owned": owned, "badge": "CURRENT" if owned else "", "id": {"type": "paint", "layer": layer, "color": col}})
			if not found and (layer == "primary" or cur.a > 0.0):
				items.push_front({"text": "Current colour", "sub": "Factory paint", "icon": &"circle", "icon_color": cur,
						"price": 0, "owned": true, "badge": "CURRENT", "id": {"type": "paint", "layer": layer, "color": cur}})
		"mod":
			var slot := str(sec["slot"])
			var inst := str(_installed_mods.get(slot, ""))
			items.append({"text": "Stock", "sub": "Factory %s" % str(SLOT_TITLES.get(slot, slot)).to_lower(), "price": 0,
					"owned": inst == "", "badge": "FITTED" if inst == "" else "", "icon": _slot_icon(slot),
					"id": {"type": "mod", "slot": slot, "mod_id": ""}})
			for id: Variant in sec["ids"]:
				var def := Stats.mod_def(str(id))
				var owned := inst == str(id)
				var it := {"text": str(def.get("display_name", id)), "sub": str(def.get("description", "")),
						"price": _price(Stats.mod_price(str(id))), "owned": owned, "badge": "FITTED" if owned else "",
						"icon": _slot_icon(slot), "id": {"type": "mod", "slot": slot, "mod_id": str(id)}}
				if def.has("color") and def["color"] is Color:
					it["icon"] = &"circle"
					it["icon_color"] = def["color"]
				items.append(it)
	return items


func _slot_icon(slot: String) -> StringName:
	if PERF_SLOTS.has(slot):
		return &"bolt" if slot in ["engine", "turbo", "transmission"] else (&"shield" if slot == "armor" else &"gear")
	if slot == "horn":
		return &"radio"
	return &"wrench"


func _on_item_selected(_i: int, item: Dictionary) -> void:
	var id: Variant = item.get("id", {})
	if id is Dictionary:
		_preview(id)
		_describe(item)


func _on_item_activated(_i: int, item: Dictionary) -> void:
	var id: Variant = item.get("id", {})
	if id is Dictionary:
		_purchase(id)


func _describe(item: Dictionary) -> void:
	var id: Dictionary = item.get("id", {})
	var t := str(id.get("type", ""))
	var text := str(item.get("sub", ""))
	if t == "mod":
		var def := Stats.mod_def(str(id.get("mod_id", "")))
		var cat := str(def.get("category", ""))
		if cat == "performance":
			text = "%s. Performance part: changes the real handling of the car." % str(def.get("description", ""))
		elif str(def.get("node", "")) != "":
			text = "%s. Body part fitted to this model." % str(def.get("display_name", ""))
		elif text == "":
			text = str(def.get("display_name", ""))
	elif t == "paint":
		text = "%s paint, %s." % [str(item.get("text", "")), "main body" if str(id.get("layer", "")) == "primary" else "trim and accents"]
	_desc.text = text


# =================================================================================================
# preview / purchase
# =================================================================================================

func _snapshot_installed() -> void:
	var m: Variant = vehicle.get("mods")
	_installed_mods = (m as Dictionary).duplicate() if m is Dictionary else {}
	_preview_mods = _installed_mods.duplicate()
	var p: Variant = vehicle.get("paint_primary")
	var s: Variant = vehicle.get("paint_secondary")
	_installed_primary = p if p is Color else Color.WHITE
	_installed_secondary = s if s is Color else Color(0, 0, 0, 0)


func _preview(id: Dictionary) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	match str(id.get("type", "")):
		"mod":
			var m := _installed_mods.duplicate()
			var slot := str(id["slot"])
			var mod_id := str(id["mod_id"])
			if mod_id == "":
				m.erase(slot)
			else:
				m[slot] = mod_id
			_apply_mods(m)
			_preview_mods = m
			if slot == "horn":
				_preview_horn()
		"paint":
			_apply_mods(_installed_mods)
			_preview_mods = _installed_mods.duplicate()
			var col: Color = id["color"]
			if str(id["layer"]) == "primary":
				vehicle.call("set_paint", col, _installed_secondary if _installed_secondary.a > 0.0 else Color(0, 0, 0, 0))
			else:
				vehicle.call("set_paint", _installed_primary, col)
		_:
			_revert_preview()
	_stats_canvas.queue_redraw()


func _apply_mods(m: Dictionary) -> void:
	var cur: Variant = vehicle.get("mods")
	if cur is Dictionary and (cur as Dictionary) == m:
		return
	if vehicle.has_method("apply_mods"):
		vehicle.call("apply_mods", m)


func _revert_preview() -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	_apply_mods(_installed_mods)
	_preview_mods = _installed_mods.duplicate()
	var p: Variant = vehicle.get("paint_primary")
	var s: Variant = vehicle.get("paint_secondary")
	if not (p is Color and Stats.same_color(p, _installed_primary)) or not (s is Color and (s as Color).is_equal_approx(_installed_secondary)):
		vehicle.call("set_paint", _installed_primary, _installed_secondary if _installed_secondary.a > 0.0 else Color(0, 0, 0, 0))


func _purchase(id: Dictionary) -> bool:
	if vehicle == null or not is_instance_valid(vehicle):
		return false
	var t := str(id.get("type", ""))
	var cost := 0
	var sound := "wrench"
	var kind := "vehicle_mod"
	var item_id := ""
	match t:
		"repair":
			cost = _price(Stats.repair_cost(vehicle))
			if not Stats.needs_repair(Stats.condition(vehicle)):
				UI.notify("Nothing to repair", "info")
				return false
			kind = "vehicle_repair"
			item_id = Stats.text(vehicle, "spec_id")
		"mod":
			var slot := str(id["slot"])
			var mod_id := str(id["mod_id"])
			if str(_installed_mods.get(slot, "")) == mod_id:
				UiKit.sfx("ui_error")
				return false
			cost = _price(Stats.mod_price(mod_id)) if mod_id != "" else 0
			item_id = mod_id if mod_id != "" else "stock_" + slot
			if slot in ["paint_finish"]:
				sound = "spray_paint"
		"paint":
			var col: Color = id["color"]
			var layer := str(id["layer"])
			var cur := _installed_primary if layer == "primary" else _installed_secondary
			if Stats.same_color(col, cur) and (layer == "primary" or cur.a > 0.0):
				UiKit.sfx("ui_error")
				return false
			cost = _price(Stats.price(Stats.PRIMARY_PRICE if layer == "primary" else Stats.SECONDARY_PRICE))
			kind = "vehicle_paint"
			item_id = "%s_%s" % [layer, col.to_html(false)]
			sound = "spray_paint"
		_:
			return false
	if not Game.spend(cost):
		UiKit.sfx("ui_error")
		UI.notify("Not enough money (%s)" % Stats.money(cost), "warn")
		return false
	match t:
		"repair":
			if vehicle.has_method("repair"):
				vehicle.call("repair")
			_snapshot_installed()
		"mod":
			var slot := str(id["slot"])
			var mod_id := str(id["mod_id"])
			if mod_id == "":
				_installed_mods.erase(slot)
			else:
				_installed_mods[slot] = mod_id
			_apply_mods(_installed_mods)
			# apply_mods() drops what the vehicle cannot take: keep our record honest
			var m: Variant = vehicle.get("mods")
			if m is Dictionary:
				_installed_mods = (m as Dictionary).duplicate()
		"paint":
			if str(id["layer"]) == "primary":
				_installed_primary = id["color"]
			else:
				_installed_secondary = id["color"]
			vehicle.call("set_paint", _installed_primary, _installed_secondary if _installed_secondary.a > 0.0 else Color(0, 0, 0, 0))
			EventBus.vehicle_modified.emit(vehicle)
	_preview_mods = _installed_mods.duplicate()
	purchases += 1
	spent += cost
	Audio.play(sound, -2.0, randf_range(0.95, 1.05), "SFX")
	UiKit.sfx("ui_buy")
	EventBus.item_purchased.emit(kind, item_id, cost)
	if shop != null and is_instance_valid(shop) and shop.has_method("on_purchase"):
		shop.call("on_purchase", kind, item_id, cost)
	elif cost >= 0 and t != "repair":
		var g := Game.get_system("garage")
		if g != null and g.has_method("set_personal_vehicle"):
			g.call("set_personal_vehicle", vehicle)
	# refresh rows (owned flags, prices); the cursor lands on what was just fitted, so the
	# preview that follows the selection shows the purchase itself
	var keep := _list.selected
	var items := _items_for(sections[section_index]) if section_index < sections.size() else []
	_list.set_items(items)
	for k in items.size():
		if bool((items[k] as Dictionary).get("owned", false)):
			keep = k
			break
	_list.select(clampi(keep, 0, maxi(_list.get_count() - 1, 0)), true)
	_refresh_condition()
	_stats_canvas.queue_redraw()
	return true


func _price(p: int) -> int:
	return 0 if free else p


func _refresh_condition() -> void:
	if not _cond_box.visible or vehicle == null:
		return
	var c := Stats.condition(vehicle)
	_set_bar("Body", float(c["health"]), "%d %%" % roundi(float(c["health"]) * 100.0))
	var gt := int(c["glass_total"])
	_set_bar("Glass", 1.0 if gt == 0 else float(gt - int(c["glass_broken"])) / float(gt), "%d / %d" % [gt - int(c["glass_broken"]), gt])
	var tt := int(c["tyres_total"])
	_set_bar("Tyres", 1.0 if tt == 0 else float(tt - int(c["tyres_flat"])) / float(tt), "%d / %d" % [tt - int(c["tyres_flat"]), tt])
	_set_bar("Engine", float(c["power"]) * (1.0 - float(c["pull"])), "%d %%" % roundi(float(c["power"]) * 100.0))


func _set_bar(key: String, frac: float, text: String) -> void:
	var bar: UiBar = _cond_bars.get(key, null)
	if bar == null:
		return
	bar.value = frac
	bar.value_text = text
	bar.color = UiStyle.GOOD if frac > 0.85 else (UiStyle.SUN if frac > 0.45 else UiStyle.BAD)


func _on_money_changed(amount: int, _delta: int) -> void:
	if _header != null:
		_header.right_text = UiStyle.money(amount)
	if _list != null:
		_list.refresh()


# --- horn / headlight previews ------------------------------------------------------------------

func _preview_horn() -> void:
	if vehicle != null and vehicle.has_method("honk"):
		vehicle.call("honk", true)
		_honk_left = 0.55


func _stop_honk() -> void:
	if _honk_left > 0.0 and vehicle != null and is_instance_valid(vehicle) and vehicle.has_method("honk"):
		vehicle.call("honk", false)
	_honk_left = 0.0


func _restore_headlights() -> void:
	if _prev_headlights >= 0 and vehicle != null and is_instance_valid(vehicle) and vehicle.has_method("set_headlights"):
		vehicle.call("set_headlights", _prev_headlights)
	_prev_headlights = -1


# =================================================================================================
# stat bars
# =================================================================================================

func _draw_stats(c: Control) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var spec := Stats.spec_of(vehicle)
	var base := Stats.stats_for(spec, _installed_mods)
	var prev := Stats.stats_for(spec, _preview_mods)
	var body := UiStyle.font(&"bold")
	var num := UiStyle.font(&"num")
	var y := 4.0
	var w := c.size.x
	for key: String in Stats.STAT_KEYS:
		var b: Dictionary = base[key]
		var p: Dictionary = prev[key]
		UiStyle.text(c, body, Vector2(0.0, y + UiStyle.FS_SMALL), str(Stats.STAT_NAMES[key]).to_upper(), UiStyle.FS_SMALL, UiStyle.MUTED)
		var changed := absf(float(p["frac"]) - float(b["frac"])) > 0.002
		var better := float(p["value"]) > float(b["value"])
		var vcol: Color = UiStyle.TEXT if not changed else (UiStyle.GOOD if better else UiStyle.CORAL_HOT)
		UiStyle.text_in(c, num, Rect2(0.0, y, w, UiStyle.FS_BODY + 4.0), str(p["text"]), UiStyle.FS_BODY, vcol, HORIZONTAL_ALIGNMENT_RIGHT)
		var r := Rect2(0.0, y + 34.0, w, 14.0)
		UiStyle.draw_bar(c, r, 0.0, UiStyle.TEAL, true)
		var lo := minf(float(b["frac"]), float(p["frac"]))
		var hi := maxf(float(b["frac"]), float(p["frac"]))
		if changed:
			_fill(c, r, hi, UiStyle.GOOD if better else UiStyle.CORAL_HOT)
		_fill(c, r, lo if changed else float(b["frac"]), UiStyle.TEAL_LIGHT)
		y += 62.0


static func _fill(c: Control, r: Rect2, frac: float, col: Color) -> void:
	var f := clampf(frac, 0.0, 1.0)
	if f <= 0.001:
		return
	var w := maxf(r.size.x * f, minf(r.size.y, r.size.x))
	c.draw_style_box(UiStyle._fill_box(col), Rect2(r.position, Vector2(w, r.size.y)))


# =================================================================================================
# orbit camera
# =================================================================================================

func _setup_camera() -> void:
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.name = "ModGarageCamera"
	_cam.fov = 52.0
	_cam.near = 0.05
	_cam.far = 1500.0
	var host: Node = Game.get_entities_root()
	if host == null:
		host = get_tree().current_scene
	host.add_child(_cam)
	_cam_ready = false
	_update_camera(1.0, true)
	_cam.make_current()


func _car_length() -> float:
	var box: Variant = vehicle.get("body_aabb")
	if box is AABB:
		return clampf(maxf((box as AABB).size.z, (box as AABB).size.x), 2.0, 9.0)
	return 4.5


func _focus_point() -> Vector3:
	var center := vehicle.global_position + Vector3(0.0, 0.7, 0.0)
	if vehicle.has_method("get_center_position"):
		center = vehicle.call("get_center_position")
	if _view == "wheel":
		var wl := _wheel_node()
		if wl != null:
			return wl.global_position + Vector3(0.0, 0.08, 0.0)
	return center


func _wheel_node() -> Node3D:
	if vehicle.has_method("get_part"):
		for n: String in ["Wheel_FL", "Wheel_F", "Wheel_L"]:
			var p: Variant = vehicle.call("get_part", n)
			if p is Node3D:
				return p
	return null


func _process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or Stats.flag(vehicle, "destroyed"):
		if vehicle != null:
			vehicle = null
			close_self.call_deferred()
		return
	var rd := delta / maxf(Engine.time_scale, 0.05)
	if _scroll_pending >= 0:
		_scroll_frames -= 1
		if _scroll_frames <= 0:
			var row := _list.get_row(_scroll_pending)
			if row != null:
				_list.ensure_control_visible(row)
			_scroll_pending = -1
	if _honk_left > 0.0:
		_honk_left -= rd
		if _honk_left <= 0.0 and vehicle.has_method("honk"):
			vehicle.call("honk", false)
	if remote:
		var rb := vehicle as RigidBody3D
		if rb != null and rb.linear_velocity.length() > 0.5:
			rb.linear_velocity = rb.linear_velocity.lerp(Vector3.ZERO, clampf(rd * 3.0, 0.0, 1.0))
	_update_camera(rd, false)


func _update_camera(rd: float, snap: bool) -> void:
	if _cam == null or not is_instance_valid(_cam) or vehicle == null:
		return
	var v: Array = VIEWS.get(_view, VIEWS["default"])
	_idle += rd
	if _view == "default" and _idle > IDLE_BEFORE_ORBIT and not _dragging:
		_auto += AUTO_ORBIT_SPEED * rd
	elif not _dragging:
		_auto = lerpf(_auto, 0.0, clampf(rd * 1.5, 0.0, 1.0))
	var side := 1.0
	if _view == "wheel":
		var wl := _wheel_node()
		if wl != null:
			var local := vehicle.global_transform.affine_inverse() * wl.global_position
			side = 1.0 if local.x < 0.0 else -1.0
	var t_yaw := deg_to_rad(float(v[0])) * side + _user_yaw + _auto
	var t_pitch := clampf(deg_to_rad(float(v[1])) + _user_pitch, deg_to_rad(-4.0), deg_to_rad(70.0))
	var t_dist := float(v[2]) * _car_length() * _zoom + 1.2
	if snap or not _cam_ready:
		_rel_yaw = t_yaw
		_pitch = t_pitch
		_dist = t_dist
		_look = _focus_point() + Vector3(0.0, float(v[3]), 0.0)
		_cam_ready = true
	else:
		var k := clampf(rd * 4.0, 0.0, 1.0)
		_rel_yaw = lerp_angle(_rel_yaw, t_yaw, k)
		_pitch = lerpf(_pitch, t_pitch, k)
		_dist = lerpf(_dist, t_dist, k)
		_look = _look.lerp(_focus_point() + Vector3(0.0, float(v[3]), 0.0), k)
	var fwd := -vehicle.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-4 else Vector3.FORWARD
	var left := Vector3.UP.cross(fwd).normalized()
	var dir := (fwd * cos(_rel_yaw) + left * sin(_rel_yaw)) * cos(_pitch) + Vector3.UP * sin(_pitch)
	var want := _look + dir * _dist
	# keep the camera inside the workshop walls
	var space := _cam.get_world_3d().direct_space_state if _cam.is_inside_tree() else null
	if space != null:
		_ray.from = _look
		_ray.to = want
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty():
			want = (hit["position"] as Vector3) - dir * 0.3
	_cam.global_position = want
	if want.distance_to(_look) > 0.05:
		_cam.look_at(_look, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
			_idle = 0.0
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom - 0.08, 0.6, 1.6)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom + 0.08, 0.6, 1.6)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_user_yaw -= mm.relative.x * 0.006
		_user_pitch = clampf(_user_pitch + mm.relative.y * 0.004, -0.4, 0.9)
		_idle = 0.0
		accept_event()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or has_dialog() or sections.size() < 2:
		return
	if event.is_action_pressed("ui_left", true):
		_step_section(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right", true):
		_step_section(1)
		get_viewport().set_input_as_handled()


func _step_section(dir: int) -> void:
	var n := sections.size()
	var i := posmod(section_index + dir, n)
	UiKit.sfx("ui_tab")
	_show_section(i)
