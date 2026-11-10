class_name WeaponWheel
extends Control
## Radial weapon selection: eight class sectors, mouse direction picks the class, mouse wheel / click
## cycles weapons inside it. Time slows while open.

var sel_slot := 0
var picks := {}
var virt := Vector2.ZERO


func open() -> void:
	var p: Node = G.player
	if p == null:
		return
	visible = true
	G.ui_blocking += 1
	G.time_scale_target = 0.2
	virt = Vector2.ZERO
	picks.clear()
	for s in Defs.SLOTS:
		var ws: Array = p.inv.slot_weapons(s)
		if not ws.is_empty():
			picks[s] = ws[0]
			if p.inv.current in ws:
				picks[s] = p.inv.current
	sel_slot = Defs.SLOTS.find(Defs.WEAPONS[p.inv.current].slot)
	Sfx.ui("open")
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	G.ui_blocking = maxi(G.ui_blocking - 1, 0)
	G.time_scale_target = 1.0
	var s: String = Defs.SLOTS[sel_slot]
	if picks.has(s) and G.player:
		G.player.equip(picks[s])


func _input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventMouseMotion:
		virt = (virt + ev.relative).limit_length(160.0)
		if virt.length() > 40.0:
			var a := fposmod(atan2(virt.x, -virt.y), TAU)
			var s := int(round(a / (TAU / 8.0))) % 8
			if s != sel_slot:
				sel_slot = s
				Sfx.ui("tick")
		queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed:
		var dir := 0
		if ev.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_LEFT]:
			dir = 1
		elif ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_RIGHT]:
			dir = -1
		if dir != 0 and G.player:
			var sn: String = Defs.SLOTS[sel_slot]
			var ws: Array = G.player.inv.slot_weapons(sn)
			if ws.size() > 1:
				picks[sn] = ws[posmod(ws.find(picks[sn]) + dir, ws.size())]
				Sfx.ui("tick")
				queue_redraw()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var p: Node = G.player
	if p == null:
		return
	var c := size * 0.5
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	draw_arc(c, 235.0, 0, TAU, 96, Color(0.04, 0.05, 0.08, 0.82), 150.0)
	for i in 8:
		var a := i * TAU / 8.0
		var dir := Vector2(sin(a), -cos(a))
		var sn: String = Defs.SLOTS[i]
		var has: bool = picks.has(sn)
		if i == sel_slot:
			draw_arc(c, 235.0, a - PI * 0.5 - TAU / 16.0 + 0.02, a - PI * 0.5 + TAU / 16.0 - 0.02, 24, Color(UIKit.CORAL.r, UIKit.CORAL.g, UIKit.CORAL.b, 0.75), 146.0)
		var sep := Vector2(sin(a + TAU / 16.0), -cos(a + TAU / 16.0))
		draw_line(c + sep * 162.0, c + sep * 308.0, Color(1, 1, 1, 0.18), 2.0)
		var pos := c + dir * 235.0
		var title: String = Defs.SLOT_NAMES[sn]
		draw_string(font, pos + Vector2(-70, -18), title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 140, 13, UIKit.TEAL if has else Color(1, 1, 1, 0.3))
		if has:
			var wid: String = picks[sn]
			var d: Dictionary = Defs.WEAPONS[wid]
			draw_string(font, pos + Vector2(-80, 6), d.name, HORIZONTAL_ALIGNMENT_CENTER, 160, 17, Color.WHITE)
			var am := ""
			if d.has("ammo"):
				am = "%d" % p.inv.in_clip(wid) if d.type == "throw" else "%d / %d" % [p.inv.in_clip(wid), p.inv.reserve(wid)]
			var n: int = p.inv.slot_weapons(sn).size()
			if n > 1:
				am += "   (%d)" % n
			draw_string(font, pos + Vector2(-80, 28), am, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, UIKit.GOLD)
	var cs: String = Defs.SLOTS[sel_slot]
	var ct: String = Defs.WEAPONS[picks[cs]].name if picks.has(cs) else "Empty"
	draw_string(font, c + Vector2(-150, 4), ct, HORIZONTAL_ALIGNMENT_CENTER, 300, 24, Color.WHITE)
	draw_string(font, c + Vector2(-150, 30), "release TAB to equip  -  wheel/click to cycle", HORIZONTAL_ALIGNMENT_CENTER, 300, 12, UIKit.DIM)
