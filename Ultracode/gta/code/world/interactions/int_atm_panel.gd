extends Control
## Keyboard ATM panel of the interactions system ("Bay Savings" cash machine). Not a UI.SCREENS
## screen: the system locks gameplay input while it is open; the panel reads the number keys
## (weapon_slot_1..4) and closes on interact / Esc. Styled with the game theme when the UI autoload
## provides it (type variations GlassPanel / HeaderLabel / SectionLabel / SmallLabel).

signal option_chosen(option: String)     ## "w100", "w500", "d100", "dall", "close"

const OPTIONS: Array[Array] = [
	["w100", "1", "Withdraw $100"], ["w500", "2", "Withdraw $500"],
	["d100", "3", "Deposit $100"], ["dall", "4", "Deposit all cash"],
]
const SLOT_ACTIONS: Array[StringName] = [&"weapon_slot_1", &"weapon_slot_2", &"weapon_slot_3", &"weapon_slot_4"]

var _title: Label
var _cash: Label
var _bank: Label
var _limit: Label
var _status: Label
var _rows: Array[Label] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ui := get_node_or_null("/root/UI")
	if ui != null and ui.has_method("get_game_theme"):
		var th: Variant = ui.call("get_game_theme")
		if th is Theme:
			theme = th
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = &"GlassPanel"
	panel.custom_minimum_size = Vector2(430.0, 0.0)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -500.0
	panel.offset_right = -70.0
	panel.offset_top = -190.0
	panel.offset_bottom = 190.0
	add_child(panel)
	var m := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	m.add_child(box)
	_title = _label(box, "BAY SAVINGS  ATM", &"HeaderLabel", 26)
	_label(box, "Cash machine - your account", &"SmallLabel", 14)
	box.add_child(HSeparator.new())
	_cash = _label(box, "", &"", 18)
	_bank = _label(box, "", &"", 18)
	_limit = _label(box, "", &"SmallLabel", 14)
	box.add_child(HSeparator.new())
	for o: Array in OPTIONS:
		_rows.append(_label(box, "[%s]  %s" % [o[1], o[2]], &"", 18))
	_label(box, "[%s] / [Esc]  Leave" % _key_label(&"interact", "E"), &"SmallLabel", 14)
	_status = _label(box, "", &"SmallLabel", 15)
	_status.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))


func _label(parent: Control, text: String, variation: StringName, fs: int) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", fs)
	parent.add_child(l)
	return l


func _key_label(action: StringName, fallback: String) -> String:
	var setup := get_node_or_null("/root/InputSetup")
	if setup != null and setup.has_method("label"):
		var s: Variant = setup.call("label", String(action))
		if s is String and s != "":
			return s
	return fallback


func show_values(cash: int, bank: int, remaining: int, status: String = "") -> void:
	if _cash == null:
		return
	_cash.text = "Cash in hand:   $%s" % _money(cash)
	_bank.text = "Account balance:   $%s" % _money(bank)
	_limit.text = "Withdrawal limit left today: $%s" % _money(remaining)
	_status.text = status


static func _money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


func _input(event: InputEvent) -> void:
	if not visible or not is_inside_tree():
		return
	if event.is_echo():
		return
	for i in SLOT_ACTIONS.size():
		if InputMap.has_action(SLOT_ACTIONS[i]) and event.is_action_pressed(SLOT_ACTIONS[i]):
			get_viewport().set_input_as_handled()
			option_chosen.emit(String(OPTIONS[i][0]))
			return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		option_chosen.emit("close")
