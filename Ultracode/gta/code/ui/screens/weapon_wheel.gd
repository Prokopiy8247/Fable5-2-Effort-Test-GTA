extends UiScreen
## Radial weapon wheel: the 8 slots from ARCHITECTURE 6.6 (melee, handgun, smg, shotgun, rifle,
## sniper, heavy, thrown) clockwise from the top. Opens while Tab is held (the UI autoload opens /
## closes it), slows time to 0.15 and equips the highlighted weapon on release through
## Game.player.inventory. Selection: push the mouse (or right stick) towards a slot, or press
## 1-8; the mouse wheel cycles the weapons that share the highlighted slot; Esc cancels.
## Original look: navy glass wedges, coral highlight, code-drawn class icons.

const PAUSES_GAME := false
const TIME_SCALE := 0.15
const LOCKS_INPUT := true
const SHOWS_MOUSE := false
const HIDES_HUD := false

const SLOTS: Array[String] = ["melee", "handgun", "smg", "shotgun", "rifle", "sniper", "heavy", "thrown"]
const SLOT_LABELS := {
	"melee": "MELEE", "handgun": "HANDGUN", "smg": "SMG", "shotgun": "SHOTGUN", "rifle": "RIFLE",
	"sniper": "SNIPER", "heavy": "HEAVY", "thrown": "THROWN",
}
const R_IN := 178.0
const R_OUT := 372.0
const WEDGE_GAP_DEG := 2.2
const DEADZONE := 34.0
const STICK_MAX := 150.0

var _slots: Array[Dictionary] = []     ## {slot, weapons: Array, index: int}
var _hover: int = -1
var _stick: Vector2 = Vector2.ZERO
var _cancelled: bool = false
var _current_id: String = ""
var _canvas: UiCanvas
var _time: float = 0.0
var _wedges: Array[PackedVector2Array] = []


func _init() -> void:
	super()
	backdrop_alpha = 0.38
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_canvas = UiCanvas.new(_draw_wheel)
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_wedges()
	_collect()


func open(_args: Dictionary) -> void:
	_collect()
	_cancelled = false
	_stick = Vector2.ZERO
	# start on the slot of the weapon in hand
	_hover = -1
	for i in _slots.size():
		if (_slots[i]["weapons"] as Array).has(_current_id):
			_hover = i
	_canvas.queue_redraw()


## Equip on release (called by the UI manager just before the wheel is freed).
func close() -> void:
	if _cancelled:
		return
	var id := get_hovered_weapon()
	var inv := _inventory()
	if id == "" or inv == null or id == _current_id:
		return
	if inv.has_method("equip"):
		inv.call("equip", id)


func handle_back() -> bool:
	_cancelled = true
	return false


# --- public helpers (tests, gamepad glue) ------------------------------------------------------------

## Point the selector: any direction with a length above the dead zone highlights that slot.
func set_pointer(direction: Vector2) -> void:
	_stick = direction.limit_length(STICK_MAX)
	_update_hover()


func select_slot(index: int) -> void:
	if index >= 0 and index < _slots.size():
		_hover = index
		var a := deg_to_rad(-90.0 + index * 45.0)
		_stick = Vector2(cos(a), sin(a)) * (DEADZONE + 40.0)
		_canvas.queue_redraw()


func get_hovered_slot() -> int:
	return _hover


func get_hovered_weapon() -> String:
	if _hover < 0 or _hover >= _slots.size():
		return ""
	var s: Dictionary = _slots[_hover]
	var list: Array = s["weapons"]
	if list.is_empty():
		return ""
	return str(list[clampi(int(s["index"]), 0, list.size() - 1)])


func get_slot_weapons(index: int) -> Array:
	if index < 0 or index >= _slots.size():
		return []
	return _slots[index]["weapons"]


func cycle(dir: int) -> void:
	if _hover < 0 or _hover >= _slots.size():
		return
	var s: Dictionary = _slots[_hover]
	var n := (s["weapons"] as Array).size()
	if n < 2:
		return
	s["index"] = posmod(int(s["index"]) + dir, n)
	UiKit.sfx("ui_tab")
	_canvas.queue_redraw()


# --- data ------------------------------------------------------------------------------------------

func _inventory() -> Object:
	if not Game.has_player():
		return null
	var inv: Variant = Game.player.get(&"inventory")
	if inv is Object and is_instance_valid(inv):
		return inv
	return null


func _collect() -> void:
	_slots.clear()
	for s in SLOTS:
		_slots.append({"slot": s, "weapons": [], "index": 0})
	var inv := _inventory()
	if inv == null:
		return
	_current_id = UiKit.text_of(inv, &"current_id", "")
	var filled := false
	if inv.has_method("get_wheel_data"):
		var wd: Variant = inv.call("get_wheel_data")
		if wd is Array:
			for e in wd:
				if not (e is Dictionary):
					continue
				var idx := SLOTS.find(str((e as Dictionary).get("slot", "")))
				if idx < 0:
					continue
				var list: Variant = (e as Dictionary).get("weapons", [])
				if list is Array:
					var ids: Array = []
					for w in list:
						ids.append(str(w))
					_slots[idx]["weapons"] = ids
					_slots[idx]["index"] = maxi(ids.find(str((e as Dictionary).get("selected", ""))), 0)
					filled = true
	if not filled and inv.has_method("get_weapons"):
		var owned: Variant = inv.call("get_weapons")
		if owned is Array:
			for w in owned:
				var id := str(w)
				var idx2 := SLOTS.find(_slot_of(id))
				if idx2 >= 0:
					(_slots[idx2]["weapons"] as Array).append(id)
			for s2 in _slots:
				s2["index"] = maxi((s2["weapons"] as Array).find(_current_id), 0)


func _spec(id: String) -> Variant:
	var inv := _inventory()
	if inv != null and inv.has_method("get_spec"):
		var sp: Variant = inv.call("get_spec", id)
		if sp != null:
			return sp
	return Registry.get_def("weapons", id)


func _slot_of(id: String) -> String:
	return str(HudRoot._def_get(_spec(id), "slot", "melee" if id == "fists" else "handgun"))


func _name_of(id: String) -> String:
	if id == "":
		return ""
	var n := str(HudRoot._def_get(_spec(id), "display_name", ""))
	return (n if n != "" else id.capitalize()).to_upper()


func _ammo_text(id: String) -> String:
	var inv := _inventory()
	if inv == null or not inv.has_method("get_ammo"):
		return ""
	var a: Variant = inv.call("get_ammo", id)
	if not (a is Dictionary):
		return ""
	var in_mag := int((a as Dictionary).get("in_mag", -1))
	var reserve := int((a as Dictionary).get("reserve", -1))
	if in_mag < 0:
		return ""
	if int((a as Dictionary).get("mag_size", 0)) <= 0 and reserve <= 0:
		return "x%d" % in_mag
	return "%d / %d" % [in_mag, reserve]


# --- input -----------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_stick = (_stick + (event as InputEventMouseMotion).relative * 1.15).limit_length(STICK_MAX)
		_update_hover()
	elif event.is_action_pressed(&"weapon_next"):
		cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"weapon_prev"):
		cycle(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"fire"):
		get_viewport().set_input_as_handled()
		close_self()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var code := (event as InputEventKey).physical_keycode
		if code >= KEY_1 and code <= KEY_8:
			select_slot(int(code) - int(KEY_1))
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_time += delta / maxf(Engine.time_scale, 0.05)
	var pad := Vector2(Input.get_axis(&"look_left", &"look_right"), Input.get_axis(&"look_up", &"look_down"))
	if pad.length() > 0.55:
		_stick = pad.normalized() * (DEADZONE + 60.0)
		_update_hover()
	_canvas.queue_redraw()


func _update_hover() -> void:
	if _stick.length() < DEADZONE:
		return
	var ang := rad_to_deg(_stick.angle()) + 90.0 + 22.5      # 0 = slot 0 centre (up)
	var idx := posmod(int(floor(ang / 45.0)), 8)
	if idx != _hover:
		_hover = idx
		UiKit.sfx("ui_hover", -8.0)
		_canvas.queue_redraw()


# --- drawing ---------------------------------------------------------------------------------------

func _build_wedges() -> void:
	_wedges.clear()
	for i in 8:
		var a0 := deg_to_rad(-90.0 + i * 45.0 - 22.5 + WEDGE_GAP_DEG * 0.5)
		var a1 := deg_to_rad(-90.0 + i * 45.0 + 22.5 - WEDGE_GAP_DEG * 0.5)
		var pts := PackedVector2Array()
		for k in 13:
			var a := lerpf(a0, a1, k / 12.0)
			pts.append(Vector2(cos(a), sin(a)) * R_OUT)
		# inner arc: keep the same linear gap as the outer edge
		var gap_in := deg_to_rad(WEDGE_GAP_DEG * 0.5) * (R_OUT / R_IN - 1.0)
		for k in 13:
			var a2 := lerpf(a1 - gap_in, a0 + gap_in, k / 12.0)
			pts.append(Vector2(cos(a2), sin(a2)) * R_IN)
		_wedges.append(pts)


func _draw_wheel(c: UiCanvas) -> void:
	var ctr := (c.size * 0.5).round()
	var head := UiStyle.font(&"head")
	var num := UiStyle.font(&"num")
	c.draw_set_transform(ctr, 0.0, Vector2.ONE)
	c.draw_circle(Vector2.ZERO, R_OUT + 16.0, Color(0, 0, 0, 0.22), true, -1.0, true)
	for i in 8:
		var s: Dictionary = _slots[i] if i < _slots.size() else {"slot": SLOTS[i], "weapons": [], "index": 0}
		var list: Array = s["weapons"]
		var has_any := not list.is_empty()
		var hovered := i == _hover
		var in_hand := has_any and list.has(_current_id)
		var fill: Color = UiStyle.GLASS
		if hovered:
			fill = Color(UiStyle.CORAL, 0.92) if has_any else Color(UiStyle.NAVY_LIGHT, 0.9)
		elif not has_any:
			fill = Color(0.04, 0.08, 0.14, 0.62)
		c.draw_colored_polygon(_wedges[i], fill)
		var ring := _wedges[i].duplicate()
		ring.append(_wedges[i][0])
		var edge: Color = UiStyle.LINE
		if hovered:
			edge = UiStyle.CREAM
		elif in_hand:
			edge = UiStyle.TEAL_LIGHT
		c.draw_polyline(ring, edge, 3.0 if (hovered or in_hand) else 2.0, true)
		var a := deg_to_rad(-90.0 + i * 45.0)
		var dir := Vector2(cos(a), sin(a))
		var mid := dir * ((R_IN + R_OUT) * 0.5)
		var ink: Color = UiStyle.NAVY_DEEP if (hovered and has_any) else UiStyle.CREAM
		if not has_any:
			ink = Color(1, 1, 1, 0.22)
		UiIcons.draw(c, UiIcons.weapon_slot_icon(str(s["slot"])), mid + Vector2(0, -14.0), 76.0, ink)
		var label := str(SLOT_LABELS.get(str(s["slot"]), ""))
		var lw := UiStyle.text_width(head, label, UiStyle.FS_TINY)
		c.draw_string(head, mid + Vector2(-lw * 0.5, 44.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_TINY,
				ink if has_any else Color(1, 1, 1, 0.3))
		# slot number near the inner edge, pips for several weapons in the slot
		var np := dir * (R_IN + 24.0)
		var ns := str(i + 1)
		var nw := UiStyle.text_width(num, ns, UiStyle.FS_TINY)
		c.draw_string(num, np + Vector2(-nw * 0.5, 6.0), ns, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_TINY, Color(ink, 0.55 * ink.a))
		if list.size() > 1:
			var tangent := Vector2(-dir.y, dir.x)
			var base := dir * (R_OUT - 22.0)
			for k in list.size():
				var off := (k - (list.size() - 1) * 0.5) * 16.0
				c.draw_circle(base + tangent * off, 5.0 if k == int(s["index"]) else 3.5,
						ink if k == int(s["index"]) else Color(ink, 0.45 * ink.a), true, -1.0, true)
	# hub
	c.draw_circle(Vector2.ZERO, R_IN - 14.0, UiStyle.GLASS_SOLID, true, -1.0, true)
	c.draw_arc(Vector2.ZERO, R_IN - 14.0, 0.0, TAU, 72, UiStyle.LINE_STRONG, 2.0, true)
	if _stick.length() >= DEADZONE:
		var sa := _stick.angle()
		c.draw_arc(Vector2.ZERO, R_IN - 24.0, sa - 0.2, sa + 0.2, 12, UiStyle.SUN, 7.0, true)
	var id := get_hovered_weapon()
	if _hover >= 0 and _hover < _slots.size():
		var hs: Dictionary = _slots[_hover]
		var cap := str(SLOT_LABELS.get(str(hs["slot"]), ""))
		c.draw_string(head, Vector2(-150.0, -62.0), cap, HORIZONTAL_ALIGNMENT_CENTER, 300.0, UiStyle.FS_SMALL, UiStyle.TEAL_LIGHT)
		if id != "":
			var nm := _name_of(id)
			var fs := UiStyle.FS_H3 if UiStyle.text_width(head, nm, UiStyle.FS_H3) <= 290.0 else UiStyle.FS_BODY
			c.draw_string(head, Vector2(-150.0, -8.0), nm, HORIZONTAL_ALIGNMENT_CENTER, 300.0, fs, UiStyle.TEXT)
			var ammo := _ammo_text(id)
			if ammo != "":
				c.draw_string(num, Vector2(-150.0, 44.0), ammo, HORIZONTAL_ALIGNMENT_CENTER, 300.0, UiStyle.FS_H3, UiStyle.SUN)
			if id == _current_id:
				c.draw_string(head, Vector2(-150.0, 82.0), "IN HAND", HORIZONTAL_ALIGNMENT_CENTER, 300.0, UiStyle.FS_TINY, UiStyle.MUTED)
			elif (hs["weapons"] as Array).size() > 1:
				c.draw_string(head, Vector2(-150.0, 82.0), "SCROLL TO SWAP  %d/%d" % [int(hs["index"]) + 1, (hs["weapons"] as Array).size()],
						HORIZONTAL_ALIGNMENT_CENTER, 300.0, UiStyle.FS_TINY, UiStyle.MUTED)
		else:
			c.draw_string(head, Vector2(-150.0, 6.0), "EMPTY", HORIZONTAL_ALIGNMENT_CENTER, 300.0, UiStyle.FS_H3, UiStyle.DIM)
	else:
		c.draw_string(head, Vector2(-150.0, -6.0), "WEAPONS", HORIZONTAL_ALIGNMENT_CENTER, 300.0, UiStyle.FS_H3, UiStyle.TEXT)
		c.draw_string(UiStyle.font(&"body"), Vector2(-150.0, 34.0), "Move the mouse to choose", HORIZONTAL_ALIGNMENT_CENTER, 300.0, UiStyle.FS_TINY, UiStyle.MUTED)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# footer hint
	var hint_y := ctr.y + R_OUT + 58.0
	if hint_y < c.size.y - 10.0:
		UiStyle.text(c, UiStyle.font(&"body"), Vector2(0.0, hint_y), "Release to equip  -  Scroll swaps  -  Esc cancels",
				UiStyle.FS_SMALL, UiStyle.CREAM, HORIZONTAL_ALIGNMENT_CENTER, c.size.x)
