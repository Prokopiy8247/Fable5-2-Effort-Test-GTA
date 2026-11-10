extends UiScreen
## Taxi destination picker (TRANSIT module; data from the "taxi" world system).
##     UI.open_screen("taxi", {})      opened by the taxi system when the player sits in a hired cab
## Tabs: All / per district (Q / E). Rows: the map waypoint (if set) and the named places with
## the distance, the trip time and the fare (red when the player cannot pay - the driver refuses).
## Enter: go there (TaxiSystem.choose_destination). Esc: close - the cab waits ("Choose a
## destination" in the cab reopens this screen; the enter-vehicle key gets out).

const PAUSES_GAME := false
const TIME_SCALE := 1.0
const LOCKS_INPUT := true
const SHOWS_MOUSE := true
const HIDES_HUD := false

var _header: UiHeader
var _tabs: UiTabBar
var _list: UiList
var _info: Dictionary = {}
var _hint: Label
var _all: Array[Dictionary] = []
var _districts: Array[String] = []
var _refresh_t: float = 0.0


func _init() -> void:
	super()
	backdrop_alpha = 0.45


func _ready() -> void:
	var center := CenterContainer.new()
	UiKit.fill(center)
	add_child(center)
	var row := UiKit.hbox(26)
	center.add_child(row)
	var left := UiPanel.new(&"GlassPanel", 12)
	left.custom_minimum_size = Vector2(780.0, 0.0)
	row.add_child(left)
	_header = UiKit.header("Bay Cabs", "Where to?", UiStyle.money(Game.money))
	_header.accent = UiStyle.SUN
	left.add(_header)
	_tabs = UiTabBar.new(["ALL"], 0)
	_tabs.custom_minimum_size = Vector2(720.0, 58.0)
	_tabs.tab_changed.connect(_on_tab)
	left.add(_tabs)
	_list = UiList.new()
	_list.custom_minimum_size = Vector2(720.0, 7.0 * 82.0)
	_list.item_activated.connect(_on_activated)
	_list.item_selected.connect(_on_selected)
	left.add(_list)
	left.add(UiKeyHints.new([{"keys": ["W", "S"], "text": "Select"}, {"keys": ["Q", "E"], "text": "District"},
			{"key": "Enter", "text": "Go"}, {"action": "pause", "text": "Stay in the cab"}]))
	var right := UiPanel.new(&"GlassPanel", 6)
	right.custom_minimum_size = Vector2(470.0, 0.0)
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(right)
	right.add(UiKit.label("TRIP", &"SectionLabel"))
	for key: String in ["Destination", "District", "Distance", "Trip time", "Fare", "Your cash"]:
		var r := UiKit.stat_row(key, "-")
		right.add(r)
		_info[key] = r
	right.add(UiKit.spacer(Vector2(0.0, 10.0), false))
	_hint = UiKit.paragraph("", &"MutedLabel", 420.0)
	right.add(_hint)


func open(_args: Dictionary) -> void:
	_reload()


func regain_focus() -> void:
	_list.grab()


func _reload() -> void:
	_all.clear()
	var sys := Game.get_system("taxi")
	if sys != null and sys.has_method("get_destinations"):
		var got: Variant = sys.call("get_destinations")
		if got is Array:
			for e: Variant in (got as Array):
				if e is Dictionary:
					_all.append(e as Dictionary)
	_districts.clear()
	var names: Array = ["ALL"]
	for e: Dictionary in _all:
		var dl := str(e.get("district_label", ""))
		if str(e.get("id", "")) == "waypoint" or dl == "" or _districts.has(dl):
			continue
		_districts.append(dl)
		names.append(dl.to_upper())
	_tabs.set_tabs(names, 0)
	_fill(0)
	var skip_key := InputSetup.label("skip") if InputSetup.has_method("label") else "Enter"
	_hint.text = "The fare is paid on arrival. During the ride: %s skips the trip, %s stops the cab where you are (you pay the distance so far)." % [
			skip_key, InputSetup.label("enter_vehicle") if InputSetup.has_method("label") else "F"]
	if _all.is_empty():
		_hint.text = "No destinations - the cab cannot reach the road network from here."


func _fill(tab: int) -> void:
	var want := "" if tab <= 0 or tab > _districts.size() else _districts[tab - 1]
	var items: Array = []
	for e: Dictionary in _all:
		var is_wp := str(e.get("id", "")) == "waypoint"
		if want != "" and not is_wp and str(e.get("district_label", "")) != want:
			continue
		var dist := float(e.get("distance", 0.0))
		var sub := "%s  -  %s  -  about %d min" % [str(e.get("district_label", "")), _dist_text(dist), int(e.get("minutes", 1))]
		var it := {"text": str(e.get("label", "?")), "sub": sub, "icon": e.get("icon", &"pin"),
				"price": int(e.get("fare", 0)), "id": str(e.get("id", "")), "icon_color": UiStyle.CORAL_HOT if is_wp else UiStyle.TEAL_LIGHT}
		if bool(e.get("disabled", false)):
			it["disabled"] = true
			it["sub"] = "You are here"
			it.erase("price")
			it["right"] = "-"
		items.append(it)
	_list.set_items(items)
	_list.grab()


func _on_tab(i: int) -> void:
	_fill(i)


func _on_selected(_i: int, item: Dictionary) -> void:
	var e := _entry(str(item.get("id", "")))
	if e.is_empty():
		return
	UiKit.set_stat_value(_info["Destination"], str(e.get("label", "")))
	UiKit.set_stat_value(_info["District"], str(e.get("district_label", "")))
	UiKit.set_stat_value(_info["Distance"], _dist_text(float(e.get("distance", 0.0))))
	UiKit.set_stat_value(_info["Trip time"], "about %d min (game time)" % int(e.get("minutes", 1)))
	var fare := int(e.get("fare", 0))
	UiKit.set_stat_value(_info["Fare"], "FREE" if fare <= 0 else UiStyle.money(fare))
	UiKit.set_stat_value(_info["Your cash"], UiStyle.money(Game.money))


func _entry(id: String) -> Dictionary:
	for e: Dictionary in _all:
		if str(e.get("id", "")) == id:
			return e
	return {}


func _on_activated(_i: int, item: Dictionary) -> void:
	var sys := Game.get_system("taxi")
	if sys == null or not sys.has_method("choose_destination"):
		UiKit.sfx("ui_error")
		return
	var ok := bool(sys.call("choose_destination", str(item.get("id", ""))))
	if not ok:
		UiKit.sfx("ui_error")
		_header.right_text = UiStyle.money(Game.money)
		_list.refresh()
		return
	if UI.is_screen_open(screen_id):
		close_self()


func _process(delta: float) -> void:
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.5
		_header.right_text = UiStyle.money(Game.money)


static func _dist_text(m: float) -> String:
	if m >= 1000.0:
		return "%.1f km" % (m / 1000.0)
	return "%d m" % (roundi(m / 10.0) * 10)
