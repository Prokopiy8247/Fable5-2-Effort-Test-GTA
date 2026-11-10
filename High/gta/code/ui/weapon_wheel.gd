class_name WeaponWheel
extends Control
## Radial weapon selector (hold Tab). Eight class sectors, mouse direction picks, wheel scroll cycles within a class.

var sel := 0
var pick: Array = ["", "", "", "", "", "", "", ""]
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font


func open() -> void:
	var p = Game.player
	if p == null or visible:
		return
	for s in range(8):
		var ws: Array = p.inv.slot_weapons(s)
		if ws.is_empty():
			pick[s] = ""
		elif ws.has(p.inv.current):
			pick[s] = p.inv.current
		elif pick[s] == "" or not ws.has(pick[s]):
			pick[s] = ws[0]
	sel = p.inv.def().slot
	visible = true
	Game.ui_open("wheel")
	Engine.time_scale = 0.2
	Input.warp_mouse(get_viewport_rect().size * 0.5)


func close(apply: bool = true) -> void:
	if not visible:
		return
	visible = false
	Engine.time_scale = 1.0
	Game.ui_close("wheel")
	if apply and pick[sel] != "" and Game.player:
		Game.player.equip(pick[sel])


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		var p = Game.player
		var ws: Array = p.inv.slot_weapons(sel)
		if ws.size() > 1 and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var i := ws.find(pick[sel])
			pick[sel] = ws[posmod(i + (1 if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), ws.size())]
			Sfx.ui("move")
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			close(true)


func _process(_delta: float) -> void:
	if not visible:
		return
	var c := size * 0.5
	var m := get_local_mouse_position() - c
	if m.length() > 40.0:
		var a := fposmod(atan2(m.y, m.x) + PI * 0.5 + PI / 8.0, TAU)
		var ns := int(a / (TAU / 8.0)) % 8
		if ns != sel:
			sel = ns
			Sfx.ui("move")
	queue_redraw()


func _draw() -> void:
	var p = Game.player
	if p == null:
		return
	var c := size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.45))
	var r0 := 95.0
	var r1 := 255.0
	for s in range(8):
		var a0 := -PI * 0.5 - PI / 8.0 + s * TAU / 8.0 + 0.02
		var a1 := a0 + TAU / 8.0 - 0.04
		var pts := PackedVector2Array()
		for k in range(9):
			var a := lerpf(a0, a1, k / 8.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r1)
		for k in range(9):
			var a2 := lerpf(a1, a0, k / 8.0)
			pts.append(c + Vector2(cos(a2), sin(a2)) * r0)
		var has: bool = pick[s] != ""
		var col := Color(0.1, 0.12, 0.16, 0.88)
		if s == sel:
			col = Color(1.0, 0.56, 0.3, 0.95) if has else Color(0.4, 0.3, 0.26, 0.9)
		draw_colored_polygon(pts, col)
		var mid := (a0 + a1) * 0.5
		var lp := c + Vector2(cos(mid), sin(mid)) * (r0 + r1) * 0.5
		var tc := Color(0.06, 0.07, 0.09) if (s == sel and has) else Color(0.9, 0.92, 0.95, 1.0 if has else 0.35)
		draw_string(_font, lp + Vector2(-70, -8), Data.SLOT_NAMES[s], HORIZONTAL_ALIGNMENT_CENTER, 140, 15, tc)
		if has:
			var d: WeaponDef = Data.weapons[pick[s]]
			draw_string(_font, lp + Vector2(-80, 12), d.name, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, tc)
			if d.kind != "melee":
				draw_string(_font, lp + Vector2(-70, 30), str(p.inv.total_ammo(pick[s])), HORIZONTAL_ALIGNMENT_CENTER, 140, 13, tc)
			var n: int = p.inv.slot_weapons(s).size()
			if n > 1:
				draw_string(_font, lp + Vector2(-70, 46), "scroll: %d more" % (n - 1), HORIZONTAL_ALIGNMENT_CENTER, 140, 11, tc)
	draw_circle(c, r0 - 8.0, Color(0.05, 0.06, 0.08, 0.92))
	if pick[sel] != "":
		var d2: WeaponDef = Data.weapons[pick[sel]]
		draw_string(_font, c + Vector2(-85, -6), d2.name, HORIZONTAL_ALIGNMENT_CENTER, 170, 17, Color(1.0, 0.8, 0.55))
		var info := "DMG %d" % int(d2.damage * d2.pellets)
		if d2.kind != "melee":
			info += "   RPM %d" % int(d2.rate * 60.0)
		draw_string(_font, c + Vector2(-85, 16), info, HORIZONTAL_ALIGNMENT_CENTER, 170, 13, Color(0.8, 0.84, 0.9))
	else:
		draw_string(_font, c + Vector2(-85, 4), "Empty", HORIZONTAL_ALIGNMENT_CENTER, 170, 16, Color(0.6, 0.62, 0.66))
