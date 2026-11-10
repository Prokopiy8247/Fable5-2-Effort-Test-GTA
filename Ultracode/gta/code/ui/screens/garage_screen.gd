extends UiScreen
## Garage list + vehicle catalogue (garage system, Economy B).
##   UI.open_screen("garage", {"mode": "stored", "site": "safehouse"})
##       stored vehicles (W2.7): Enter brings the selected one out at the site's spot with the
##       player at the wheel, X releases it for good (confirm).
##   UI.open_screen("garage", {"mode": "catalogue", "site": "airport", "kinds": ["heli", "plane"],
##       "title": "Aircraft rentals", "allow_stored": false})
##       every registered vehicle of those classes (spec 26) with its rental fee (free with
##       Game.flags.free_shopping); vehicles whose class / model is not in the game yet are listed
##       greyed out. Enter rents it, spawns it at the site and seats the player.
##   With "allow_stored": true both pages are shown as tabs (parking garage).
##   Site "player" spawns in front of the player (admin).

const PAUSES_GAME := false
const TIME_SCALE := 1.0
const LOCKS_INPUT := true
const SHOWS_MOUSE := true
const HIDES_HUD := true

const Stats := preload("res://gta/code/world/shops/garage_stats.gd")
const CLASS_NAMES := {"car": "Car", "bike": "Motorbike", "bicycle": "Bicycle", "boat": "Boat", "heli": "Helicopter", "plane": "Plane"}
const CLASS_ICONS := {"car": &"car", "bike": &"car", "bicycle": &"car", "boat": &"boat", "heli": &"heli", "plane": &"plane"}

var mode: String = "stored"
var site: String = "safehouse"
var kinds: Array = []
var allow_stored: bool = false
var pages: Array[String] = []

var _header: UiHeader
var _tabs: UiTabBar
var _list: UiList
var _detail_title: UiHeader
var _detail_lines: VBoxContainer
var _stats_canvas: UiCanvas
var _swatches: UiCanvas
var _hints: UiKeyHints
var _empty: Label
var _sel_item: Dictionary = {}


func _init() -> void:
	super()
	backdrop_alpha = 0.55


func _ready() -> void:
	var margin := UiKit.margin(null, 80, 56, 80, 40)
	UiKit.fill(margin)
	add_child(margin)
	var col := UiKit.vbox(16)
	margin.add_child(col)
	_header = UiKit.header("Garage", "", UiStyle.money(Game.money))
	_header.title_size = UiStyle.FS_H1
	col.add_child(_header)
	_tabs = UiTabBar.new([], 0)
	_tabs.custom_minimum_size = Vector2(620.0, 58.0)
	_tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tabs.tab_changed.connect(_on_page_changed)
	col.add_child(_tabs)
	var row := UiKit.hbox(28)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	var left := UiPanel.new(&"GlassPanel", 10)
	left.custom_minimum_size = Vector2(820.0, 0.0)
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(left)
	_list = UiList.new()
	_list.custom_minimum_size = Vector2(760.0, 420.0)
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(_on_activated)
	left.add(_list)
	_empty = UiKit.paragraph("", &"MutedLabel", 700.0)
	left.add(_empty)

	var right := UiPanel.new(&"GlassPanel", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_detail_title = UiKit.header("", "", "")
	_detail_title.title_size = UiStyle.FS_H2
	right.add(_detail_title)
	_swatches = UiCanvas.new(_draw_swatches)
	_swatches.custom_minimum_size = Vector2(400.0, 46.0)
	right.add(_swatches)
	_detail_lines = UiKit.vbox(4)
	right.add(_detail_lines)
	right.add(UiKit.label("PERFORMANCE", &"SectionLabel"))
	_stats_canvas = UiCanvas.new(_draw_stats)
	_stats_canvas.custom_minimum_size = Vector2(520.0, 5.0 * 54.0)
	right.add(_stats_canvas)

	_hints = UiKeyHints.new([])
	col.add_child(_hints)
	EventBus.money_changed.connect(_on_money)


func open(args: Dictionary) -> void:
	mode = str(args.get("mode", "stored"))
	site = str(args.get("site", "safehouse"))
	kinds = args.get("kinds", ["car", "bike", "bicycle"]) as Array
	allow_stored = bool(args.get("allow_stored", false))
	pages.clear()
	if mode == "catalogue":
		pages.append("Rentals")
		if allow_stored:
			pages.append("Stored")
	else:
		pages.append("Stored")
	var titles: Array = []
	for p: String in pages:
		titles.append(p)
	_tabs.set_tabs(titles, 0)
	_tabs.visible = pages.size() > 1
	_header.title = str(args.get("title", "Garage" if mode == "stored" else "Vehicle rentals"))
	_header.subtitle = str(args.get("subtitle", "Stored vehicles - Enter to bring one out" if mode == "stored" else ""))
	_show_page(pages[0])


func regain_focus() -> void:
	_list.grab()


func get_page() -> String:
	return pages[_tabs.current] if _tabs.current < pages.size() else ""


func get_items() -> Array:
	var out: Array = []
	for i in _list.get_count():
		out.append(_list.get_item(i))
	return out


func _system() -> Node:
	return Game.get_system("garage")


func _on_page_changed(i: int) -> void:
	if i >= 0 and i < pages.size():
		_show_page(pages[i])


func _show_page(page: String) -> void:
	var items: Array = []
	var g := _system()
	if page == "Stored":
		var stored: Array = g.call("get_stored") if g != null else []
		var cap := int(g.call("get_capacity")) if g != null else 0
		for i in stored.size():
			var d: Dictionary = stored[i]
			var mods: Dictionary = d.get("mods", {}) if d.get("mods", {}) is Dictionary else {}
			var hp := float(d.get("health", 1.0))
			var mx := _max_health(str(d.get("spec_id", "")))
			var col := SaveSystem.array_to_color(d.get("primary", null), Color.WHITE)
			items.append({"text": str(d.get("name", Stats.display_name(str(d.get("spec_id", ""))))),
					"sub": "%s  -  %d mod%s  -  condition %d %%" % [Stats.palette_name(col), mods.size(), "" if mods.size() == 1 else "s", roundi(clampf(hp / mx, 0.0, 1.0) * 100.0)],
					"icon": CLASS_ICONS.get(str(d.get("class", "car")), &"car"), "icon_color": col,
					"badge": "PERSONAL" if bool(d.get("personal", false)) else "",
					"right": "BAY %d" % (i + 1), "id": {"type": "stored", "index": i, "data": d}})
		for k in range(stored.size(), cap):
			items.append({"text": "Empty bay", "sub": "Drive a car or bike in to store it", "icon": &"house",
					"disabled": true, "right": "BAY %d" % (k + 1), "id": {"type": "empty"}})
		_empty.text = "%d of %d bays used. Police and emergency vehicles cannot be stored." % [stored.size(), cap]
		_hints.set_hints([{"keys": ["W", "S"], "text": "Select"}, {"key": "Enter", "text": "Take out"},
				{"key": "X", "text": "Release"}] + ([{"keys": ["Q", "E"], "text": "Page"}] if pages.size() > 1 else []) + [{"action": "pause", "text": "Back"}])
	else:
		var cat: Array = g.call("get_catalogue", kinds) if g != null else []
		var n_avail := 0
		for e: Dictionary in cat:
			var avail := bool(e["available"])
			if avail:
				n_avail += 1
			var sub := "%s  -  %d seat%s  -  %d km/h" % [str(CLASS_NAMES.get(str(e["class"]), str(e["class"]))), int(e["seats"]),
					"" if int(e["seats"]) == 1 else "s", roundi(float(e["top_kmh"]))]
			if not avail:
				sub = "%s  -  not in the game yet" % str(CLASS_NAMES.get(str(e["class"]), str(e["class"])))
			var it := {"text": str(e["name"]), "sub": sub, "icon": CLASS_ICONS.get(str(e["class"]), &"car"),
					"disabled": not avail, "id": {"type": "rent", "spec_id": str(e["id"]), "class": str(e["class"])}}
			if avail:
				it["price"] = int(e["fee"])
			else:
				it["right"] = "N/A"
			if (e["flags"] as Array).size() > 0:
				it["badge"] = "SERVICE"
			items.append(it)
		_empty.text = "%d of %d registered vehicles available%s." % [n_avail, cat.size(),
				"  -  free (unlock all)" if Stats.is_free() else ""] if not cat.is_empty() else "No vehicle of this kind is registered yet."
		_hints.set_hints([{"keys": ["W", "S"], "text": "Select"}, {"key": "Enter", "text": "Rent and drive"}]
				+ ([{"keys": ["Q", "E"], "text": "Page"}] if pages.size() > 1 else []) + [{"action": "pause", "text": "Back"}])
	_list.set_items(items)
	_list.grab()
	if items.is_empty():
		_sel_item = {}
		_fill_details({})


func _max_health(spec_id: String) -> float:
	var d: Variant = Registry.get_def("vehicles", spec_id)
	if d is Object:
		var v: Variant = (d as Object).get("max_health")
		if v is float or v is int:
			return maxf(float(v), 1.0)
	return 1000.0


func _on_selected(_i: int, item: Dictionary) -> void:
	_sel_item = item
	_fill_details(item)


func _fill_details(item: Dictionary) -> void:
	for c in _detail_lines.get_children():
		c.queue_free()
	var id: Dictionary = item.get("id", {}) if item.get("id", {}) is Dictionary else {}
	var t := str(id.get("type", ""))
	if t == "":
		_detail_title.title = ""
		_detail_title.subtitle = ""
		_swatches.queue_redraw()
		_stats_canvas.queue_redraw()
		return
	_detail_title.title = str(item.get("text", ""))
	if t == "stored":
		var d: Dictionary = id["data"]
		var spec_id := str(d.get("spec_id", ""))
		_detail_title.subtitle = "%s  -  stored in bay %d" % [str(CLASS_NAMES.get(str(d.get("class", "car")), "Vehicle")), int(id["index"]) + 1]
		var mods: Dictionary = d.get("mods", {}) if d.get("mods", {}) is Dictionary else {}
		var names: PackedStringArray = []
		for slot: Variant in mods:
			names.append(str(Stats.mod_def(str(mods[slot])).get("display_name", mods[slot])))
		_detail_lines.add_child(UiKit.stat_row("Condition", "%d %%" % roundi(clampf(float(d.get("health", 1.0)) / _max_health(spec_id), 0.0, 1.0) * 100.0)))
		var mod_label := UiKit.paragraph("Mods: " + (", ".join(names) if not names.is_empty() else "stock"), &"MutedLabel", 520.0)
		_detail_lines.add_child(mod_label)
	elif t == "rent":
		var spec_id := str(id["spec_id"])
		var spec: Variant = Registry.get_def("vehicles", spec_id)
		_detail_title.subtitle = str(CLASS_NAMES.get(str(id["class"]), "Vehicle"))
		var fee := Stats.rental_fee(spec_id)
		_detail_lines.add_child(UiKit.stat_row("Rental fee", "FREE" if fee <= 0 else Stats.money(fee), UiStyle.SUN))
		if spec is Object:
			var desc := str((spec as Object).get("description"))
			if desc != "":
				_detail_lines.add_child(UiKit.paragraph(desc, &"MutedLabel", 520.0))
		if bool(item.get("disabled", false)):
			_detail_lines.add_child(UiKit.paragraph("This vehicle is registered but its class or model is not in the game yet.", &"MutedLabel", 520.0))
	else:
		_detail_title.subtitle = ""
	_swatches.queue_redraw()
	_stats_canvas.queue_redraw()


func _sel_spec_and_mods() -> Array:
	var id: Dictionary = _sel_item.get("id", {}) if _sel_item.get("id", {}) is Dictionary else {}
	match str(id.get("type", "")):
		"stored":
			var d: Dictionary = id["data"]
			var m: Variant = d.get("mods", {})
			return [Registry.get_def("vehicles", str(d.get("spec_id", ""))), m if m is Dictionary else {}]
		"rent":
			return [Registry.get_def("vehicles", str(id["spec_id"])), {}]
	return [null, {}]


func _draw_stats(c: Control) -> void:
	var sm := _sel_spec_and_mods()
	if not (sm[0] is Object):
		return
	var st := Stats.stats_for(sm[0], sm[1])
	var body := UiStyle.font(&"bold")
	var num := UiStyle.font(&"num")
	var y := 0.0
	# tyre numbers (braking / handling) mean nothing for boats and aircraft
	var cls := str((sm[0] as Object).get("vehicle_class"))
	var keys: Array = (Stats.STAT_KEYS as Array) if cls in ["car", "bike", "bicycle"] else ["top_speed", "acceleration", "durability"]
	for key: String in keys:
		var e: Dictionary = st[key]
		UiStyle.text(c, body, Vector2(0.0, y + UiStyle.FS_SMALL), str(Stats.STAT_NAMES[key]).to_upper(), UiStyle.FS_SMALL, UiStyle.MUTED)
		UiStyle.text_in(c, num, Rect2(0.0, y, c.size.x, UiStyle.FS_BODY + 2.0), str(e["text"]), UiStyle.FS_SMALL, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		UiStyle.draw_bar(c, Rect2(0.0, y + 30.0, c.size.x, 12.0), float(e["frac"]), UiStyle.TEAL_LIGHT, true)
		y += 54.0


func _draw_swatches(c: Control) -> void:
	var id: Dictionary = _sel_item.get("id", {}) if _sel_item.get("id", {}) is Dictionary else {}
	if str(id.get("type", "")) != "stored":
		return
	var d: Dictionary = id["data"]
	var cols: Array[Color] = [SaveSystem.array_to_color(d.get("primary", null), Color.WHITE)]
	var sec := SaveSystem.array_to_color(d.get("secondary", null), Color(0, 0, 0, 0))
	if sec.a > 0.0:
		cols.append(sec)
	var x := 0.0
	for col: Color in cols:
		c.draw_style_box(UiStyle._fill_box(Color(col, 1.0)), Rect2(x, 6.0, 74.0, 32.0))
		x += 86.0
	UiStyle.text_in(c, UiStyle.font(&"body"), Rect2(x + 6.0, 6.0, 360.0, 32.0), Stats.palette_name(cols[0]), UiStyle.FS_SMALL, UiStyle.MUTED)


func _on_activated(_i: int, item: Dictionary) -> void:
	var id: Dictionary = item.get("id", {}) if item.get("id", {}) is Dictionary else {}
	var g := _system()
	if g == null:
		return
	match str(id.get("type", "")):
		"stored":
			var spot: Dictionary = g.call("find_spawn", site, str((id["data"] as Dictionary).get("class", "car")))
			if not bool(spot["ok"]):
				UI.notify("The garage spot is blocked - move the vehicle that is in the way", "warn")
				UiKit.sfx("ui_error")
				return
			close_self()
			# runs on the garage system (fade, spawn, seat, toast); this screen is gone by then
			g.call("retrieve_at_site", int(id["index"]), site)
		"rent":
			var spec_id := str(id["spec_id"])
			var fee := Stats.rental_fee(spec_id)
			if Game.money < fee:
				UI.notify("Not enough money (%s)" % Stats.money(fee), "warn")
				UiKit.sfx("ui_error")
				return
			var spot2: Dictionary = g.call("find_spawn", site, str(id["class"]))
			if not bool(spot2["ok"]):
				UI.notify("The pick-up spot is blocked", "warn")
				UiKit.sfx("ui_error")
				return
			close_self()
			g.call("rent_and_board", spec_id, site)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or has_dialog():
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY_X:
		var id: Dictionary = _sel_item.get("id", {}) if _sel_item.get("id", {}) is Dictionary else {}
		if str(id.get("type", "")) == "stored":
			get_viewport().set_input_as_handled()
			var idx := int(id["index"])
			var dlg := confirm("Release %s?" % str(_sel_item.get("text", "")), "It leaves the garage for good.", "Release", "Keep", true)
			dlg.confirmed.connect(func() -> void:
				var g := _system()
				if g != null and bool(g.call("remove_stored", idx)):
					UI.notify("Released %s" % str(_sel_item.get("text", "")), "info")
				_show_page(get_page()))


func _on_money(amount: int, _delta: int) -> void:
	if _header != null:
		_header.right_text = UiStyle.money(amount)
	if _list != null:
		_list.refresh()
