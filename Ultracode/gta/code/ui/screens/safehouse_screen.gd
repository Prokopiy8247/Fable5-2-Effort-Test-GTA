extends UiScreen
## Safehouse menu (spec 23A; garage system, Economy B). Opened by the bed and the save point:
##     UI.open_screen("safehouse", {"site": "safehouse", "focus": "sleep" | "save", "safehouse": helper})
## Sleep 8 hours (full health, autosave), save, wardrobe, stored vehicles. The actions themselves
## live in garage_safehouse.gd; this screen only chooses one and closes itself first.

const PAUSES_GAME := false
const TIME_SCALE := 1.0
const LOCKS_INPUT := true
const SHOWS_MOUSE := true
const HIDES_HUD := false

const Stats := preload("res://gta/code/world/shops/garage_stats.gd")

var safehouse: Node = null
var _header: UiHeader
var _list: UiList
var _info: Dictionary = {}
var _timer: float = 0.0


func _init() -> void:
	super()
	backdrop_alpha = 0.5


func _ready() -> void:
	var center := CenterContainer.new()
	UiKit.fill(center)
	add_child(center)
	var row := UiKit.hbox(26)
	center.add_child(row)
	var left := UiPanel.new(&"GlassPanel", 12)
	left.custom_minimum_size = Vector2(720.0, 0.0)
	row.add_child(left)
	_header = UiKit.header("Home", "Your safehouse", UiStyle.money(Game.money))
	left.add(_header)
	_list = UiList.new()
	_list.custom_minimum_size = Vector2(660.0, 5.0 * 82.0)
	_list.item_activated.connect(_on_activated)
	left.add(_list)
	left.add(UiKeyHints.new([{"keys": ["W", "S"], "text": "Select"}, {"key": "Enter", "text": "Choose"},
			{"action": "pause", "text": "Back"}]))
	var right := UiPanel.new(&"GlassPanel", 6)
	right.custom_minimum_size = Vector2(500.0, 0.0)
	row.add_child(right)
	right.add(UiKit.label("AT HOME", &"SectionLabel"))
	for key: String in ["Time", "Health", "Money", "Garage", "Personal vehicle"]:
		var r := UiKit.stat_row(key, "-")
		right.add(r)
		_info[key] = r
	right.add(UiKit.spacer(Vector2(0.0, 12.0), false))
	right.add(UiKit.paragraph("Games saved at home load with you standing inside the front door.", &"MutedLabel", 440.0))


func open(args: Dictionary) -> void:
	var s: Variant = args.get("safehouse", null)
	if s == null or not is_instance_valid(s):
		var g := Game.get_system("garage")
		if g != null and g.has_method("get_helper"):
			s = g.call("get_helper", "safehouse")
	safehouse = s as Node if (s != null and is_instance_valid(s)) else null
	var items := [
		{"text": "Sleep", "sub": "8 hours pass - full health - game saved", "icon": &"moon", "id": "sleep"},
		{"text": "Save game", "sub": "Loads right here, inside the front door", "icon": &"save", "id": "save"},
		{"text": "Wardrobe", "sub": "Change your outfit", "icon": &"shirt", "id": "wardrobe"},
		{"text": "Garage", "sub": "Stored vehicles", "icon": &"car", "id": "garage"},
		{"text": "Leave", "icon": &"close", "id": "leave"},
	]
	if safehouse == null:
		for it: Dictionary in items:
			if str(it["id"]) != "leave" and str(it["id"]) != "save":
				it["disabled"] = true
	_list.set_items(items)
	var focus := str(args.get("focus", "sleep"))
	var sel := 0
	for i in items.size():
		if str(items[i]["id"]) == focus:
			sel = i
	_list.select(sel, true)
	_refresh()


func regain_focus() -> void:
	_list.grab()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.5
		_refresh()


func _refresh() -> void:
	_header.right_text = UiStyle.money(Game.money)
	UiKit.set_stat_value(_info["Time"], "Day %d, %s" % [WorldClock.get_day(), WorldClock.get_time_string()])
	if Game.has_player():
		var hp := UiKit.num(Game.player, &"health", 0.0)
		var mh := maxf(UiKit.num(Game.player, &"max_health", 100.0), 1.0)
		UiKit.set_stat_value(_info["Health"], "%d %%" % roundi(hp / mh * 100.0))
	UiKit.set_stat_value(_info["Money"], UiStyle.money(Game.money))
	var g := Game.get_system("garage")
	if g != null:
		UiKit.set_stat_value(_info["Garage"], "%d / %d bays" % [(g.call("get_stored") as Array).size(), int(g.call("get_capacity"))])
		var pv: Variant = g.call("get_personal_vehicle")
		if pv != null and is_instance_valid(pv):
			var d := (pv as Node3D).global_position.distance_to(Game.get_player_position())
			UiKit.set_stat_value(_info["Personal vehicle"], "%s, %d m" % [Stats.vehicle_name(pv), roundi(d)])
		else:
			UiKit.set_stat_value(_info["Personal vehicle"], "none outside")


func _on_activated(_i: int, item: Dictionary) -> void:
	var sh := safehouse
	match str(item.get("id", "")):
		"sleep":
			close_self()
			if sh != null:
				sh.call("sleep")          # coroutine on the helper (fade, clock, heal, autosave)
		"save":
			if sh != null:
				sh.call("save_here", true)
			else:
				UI.notify("Game saved" if SaveSystem.save_game("manual") else "Saving failed", "good")
			close_self()
		"wardrobe":
			close_self()
			if sh != null:
				sh.call("open_wardrobe")
		"garage":
			close_self()
			if sh != null:
				sh.call("open_garage_list")
		"leave":
			close_self()
