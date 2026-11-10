class_name WeaponWheel
extends Control
## Radial weapon selection (hold Tab). Eight class segments; the mouse direction picks a
## segment, the scroll wheel cycles the weapons owned in it. Time slows while it is open.

var font: Font
var stick := Vector2.ZERO           # virtual pointer driven by relative mouse motion
var slot := 0
var choice: Dictionary = {}         # slot -> weapon id currently shown in that segment

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	visible = false

func open() -> void:
	var p: Player = Game.player
	if p == null:
		return
	stick = Vector2.ZERO
	choice.clear()
	for s in 8:
		var list := p.inventory.owned_in_slot(s)
		if list.has(p.gunner.weapon_id):
			choice[s] = p.gunner.weapon_id
		elif not list.is_empty():
			choice[s] = list[0]
	slot = int(WeaponDB.get_w(p.gunner.weapon_id).get("slot", 0))
	visible = true
	Game.set_slowmo("wheel", 0.18)
	Audio.play_ui(&"ui_wheel_open", -10.0)
	queue_redraw()

## Closes the wheel and equips the highlighted weapon.
func close(apply := true) -> void:
	if not visible:
		return
	visible = false
	Game.set_slowmo("wheel", 1.0)
	var p: Player = Game.player
	if apply and p != null and choice.has(slot):
		var id: StringName = choice[slot]
		if p.vehicle == null or id == &"unarmed" or bool(WeaponDB.get_w(id).get("driveby", false)):
			p.gunner.equip(id)
		else:
			Game.notify("%s cannot be used from a vehicle" % String(WeaponDB.get_w(id)["name"]), "info")

func handle_input(event: InputEvent) -> bool:
	if not visible:
		return false
	if event is InputEventMouseMotion:
		stick = (stick + (event as InputEventMouseMotion).relative * 0.9).limit_length(120.0)
		if stick.length() > 34.0:
			var ang := fposmod(atan2(stick.x, -stick.y), TAU)
			var s := int(round(ang / (TAU / 8.0))) % 8
			if s != slot:
				slot = s
				Audio.play_ui(&"ui_move", -12.0)
		queue_redraw()
		return true
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var p: Player = Game.player
		if p != null and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var list := p.inventory.owned_in_slot(slot)
			if list.size() > 1:
				var i := list.find(choice.get(slot, list[0]))
				choice[slot] = list[posmod(i + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), list.size())]
				Audio.play_ui(&"ui_move", -12.0)
				queue_redraw()
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			close(true)
			return true
	return false

func _draw() -> void:
	var p: Player = Game.player
	if p == null:
		return
	var c := size * 0.5
	var r_out := minf(size.y * 0.36, 300.0)
	var r_in := r_out * 0.44
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.01, 0.03, 0.45))
	var seg := TAU / 8.0
	for s in 8:
		var a0 := float(s) * seg - seg * 0.5 - PI * 0.5
		var a1 := a0 + seg
		var pts := PackedVector2Array()
		var steps := 10
		for k in steps + 1:
			var a := lerpf(a0 + 0.02, a1 - 0.02, float(k) / float(steps))
			pts.append(c + Vector2(cos(a), sin(a)) * r_out)
		for k in steps + 1:
			var a2 := lerpf(a1 - 0.02, a0 + 0.02, float(k) / float(steps))
			pts.append(c + Vector2(cos(a2), sin(a2)) * r_in)
		var has: bool = choice.has(s)
		var selected := s == slot
		var col := Color(0.05, 0.065, 0.09, 0.9)
		if selected:
			col = Color(0.1, 0.5, 0.6, 0.92) if has else Color(0.16, 0.18, 0.22, 0.92)
		draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, HUD.ACCENT if selected else Color(1, 1, 1, 0.16), 2.0 if selected else 1.0, true)
		var mid := (a0 + a1) * 0.5
		var tc := c + Vector2(cos(mid), sin(mid)) * (r_in + r_out) * 0.5
		var label := String(WeaponDB.SLOT_NAMES[s]).to_upper()
		var ls := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(font, tc + Vector2(-ls.x * 0.5, -12.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HUD.ACCENT if has else Color(1, 1, 1, 0.3))
		if has:
			var id: StringName = choice[s]
			var d := WeaponDB.get_w(id)
			var nm := String(d["name"])
			var ns := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
			draw_string(font, tc + Vector2(-ns.x * 0.5, 8.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
			var ammo := ""
			if WeaponDB.is_gun(id):
				ammo = "%d / %d" % [p.inventory.mag(id), p.inventory.reserve(id)]
			elif String(d.get("cls", "")) == "thrown":
				ammo = "x%d" % p.inventory.reserve(id)
			var n_owned := p.inventory.owned_in_slot(s).size()
			if n_owned > 1:
				ammo += "   (%d)" % n_owned
			var as2 := font.get_string_size(ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			draw_string(font, tc + Vector2(-as2.x * 0.5, 26.0), ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.82, 0.9))
	# centre: selected weapon details
	draw_circle(c, r_in - 8.0, Color(0.03, 0.04, 0.06, 0.92))
	draw_arc(c, r_in - 8.0, 0.0, TAU, 48, Color(1, 1, 1, 0.15), 1.0)
	if choice.has(slot):
		var sid: StringName = choice[slot]
		var sd := WeaponDB.get_w(sid)
		var title := String(sd["name"])
		var tsz := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		draw_string(font, c + Vector2(-tsz.x * 0.5, -8.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		var info := String(WeaponDB.SLOT_NAMES[slot])
		var atts: Array = p.inventory.atts(sid)
		if not atts.is_empty():
			info += "  +" + ", ".join(PackedStringArray(atts))
		var isz := font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(font, c + Vector2(-isz.x * 0.5, 14.0), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HUD.ACCENT)
	else:
		var e := "EMPTY"
		var esz := font.get_string_size(e, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(font, c + Vector2(-esz.x * 0.5, 6.0), e, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.4))
	var hint := "Move mouse  select      Wheel  cycle within class      Release Tab  equip"
	var hs := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(c.x - hs.x * 0.5, c.y + r_out + 34.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.8, 0.86))
	# pointer
	draw_circle(c + stick.limit_length(r_in - 14.0), 5.0, HUD.PINK)
