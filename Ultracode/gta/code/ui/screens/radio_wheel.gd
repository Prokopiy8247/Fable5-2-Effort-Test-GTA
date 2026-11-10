extends UiScreen
## Radio wheel: hold the radio key (action "radio_wheel", Y) in a vehicle with a radio. The radio
## system's stations (plus "Radio Off") sit on a ring clockwise from the top; time slows to 0.15
## like the weapon wheel. Point with the mouse / right stick, press 1-9, or scroll (also the
## radio_next / radio_prev keys) to move the highlight; release the key (or click) to tune in;
## Esc cancels. Data: Game.get_system("radio").get_stations(true) / get_station() / set_station(id)
## (docs/AUDIO.md). Without a radio system the wheel shows nothing and tunes nothing.
## Original look: navy glass ring, every wedge carries its station colour on the rim.

const PAUSES_GAME := false
const TIME_SCALE := 0.15
const LOCKS_INPUT := true
const SHOWS_MOUSE := false
const HIDES_HUD := false

const R_IN := 170.0
const R_OUT := 350.0
const GAP_DEG := 2.2
const DEADZONE := 34.0
const STICK_MAX := 150.0

var _stations: Array[Dictionary] = []   ## {id, name, genre, frequency, tagline, color}
var _hover: int = -1
var _current: String = "off"
var _stick: Vector2 = Vector2.ZERO
var _cancelled: bool = false
var _tuned: String = ""                ## id handed to the radio on close ("" = nothing)
var _canvas: UiCanvas
var _time: float = 0.0
var _wedges: Array[PackedVector2Array] = []
var _rims: Array[PackedVector2Array] = []


func _init() -> void:
	super()
	backdrop_alpha = 0.38
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_canvas = UiCanvas.new(_draw_wheel)
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_collect()


func open(_args: Dictionary) -> void:
	_collect()
	_cancelled = false
	_tuned = ""
	_stick = Vector2.ZERO
	_hover = maxi(get_station_ids().find(_current), 0) if not _stations.is_empty() else -1
	_canvas.queue_redraw()


## Tune in on release (called by the UI manager just before the wheel is freed).
func close() -> void:
	if _cancelled:
		return
	var id := get_hovered_station()
	var radio := _radio()
	if id == "" or radio == null or id == _current:
		return
	radio.call("set_station", id)
	_tuned = id


func handle_back() -> bool:
	_cancelled = true
	return false


# --- public helpers (tests, gamepad glue) ------------------------------------------------------------

func get_station_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s in _stations:
		out.append(str(s["id"]))
	return out


func get_hovered_station() -> String:
	if _hover < 0 or _hover >= _stations.size():
		return ""
	return str(_stations[_hover]["id"])


func get_hovered_index() -> int:
	return _hover


func select_index(index: int) -> void:
	if index < 0 or index >= _stations.size():
		return
	if index != _hover:
		UiKit.sfx("ui_hover", -8.0)
	_hover = index
	var a := _angle_of(index)
	_stick = Vector2(cos(a), sin(a)) * (DEADZONE + 40.0)
	_canvas.queue_redraw()


func select_station(station_id: String) -> void:
	select_index(get_station_ids().find(station_id))


## Point the selector: any direction longer than the dead zone highlights that wedge.
func set_pointer(direction: Vector2) -> void:
	_stick = direction.limit_length(STICK_MAX)
	_update_hover()


func cycle(dir: int) -> void:
	if _stations.is_empty():
		return
	select_index(posmod(maxi(_hover, 0) + dir, _stations.size()))


func is_cancelled() -> bool:
	return _cancelled


# --- data ------------------------------------------------------------------------------------------

func _radio() -> Node:
	var r := Game.get_system("radio")
	if r != null and r.has_method("get_stations") and r.has_method("set_station"):
		return r
	return null


func _collect() -> void:
	_stations.clear()
	var radio := _radio()
	if radio == null:
		_build_wedges()
		return
	var list: Variant = radio.call("get_stations", true) if radio.get_method_argument_count("get_stations") > 0 else radio.call("get_stations")
	var has_off := false
	if list is Array:
		for e: Variant in list:
			if not (e is Dictionary):
				continue
			var d: Dictionary = e
			var id := str(d.get("id", ""))
			if id == "":
				continue
			if id == "off":
				has_off = true
			var col: Variant = d.get("color", UiStyle.CORAL)
			_stations.append({
				"id": id,
				"name": str(d.get("display_name", d.get("name", id.capitalize()))) if id != "off" else "Radio Off",
				"genre": str(d.get("genre", "")),
				"frequency": str(d.get("frequency", "")),
				"tagline": str(d.get("tagline", "")),
				"color": col if col is Color else UiStyle.CORAL,
			})
	if not has_off:
		_stations.push_front({"id": "off", "name": "Radio Off", "genre": "", "frequency": "", "tagline": "Silence, and the sound of the city.",
				"color": UiStyle.MUTED})
	for s in _stations:
		if str(s["id"]) == "off":
			s["color"] = UiStyle.MUTED
			if str(s["tagline"]) == "":
				s["tagline"] = "Silence, and the sound of the city."
	_current = str(radio.call("get_station")) if radio.has_method("get_station") else "off"
	if _current == "":
		_current = "off"
	_build_wedges()


func _listening() -> bool:
	var radio := _radio()
	return radio != null and radio.has_method("is_listening") and bool(radio.call("is_listening"))


# --- input -----------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_stick = (_stick + (event as InputEventMouseMotion).relative * 1.15).limit_length(STICK_MAX)
		_update_hover()
	elif event.is_action_pressed(&"weapon_next") or event.is_action_pressed(&"radio_next"):
		cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"weapon_prev") or event.is_action_pressed(&"radio_prev"):
		cycle(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"fire"):
		get_viewport().set_input_as_handled()
		close_self()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var code := (event as InputEventKey).physical_keycode
		if code >= KEY_1 and code <= KEY_9:
			select_index(int(code) - int(KEY_1))
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_time += delta / maxf(Engine.time_scale, 0.05)
	var pad := Vector2(Input.get_axis(&"look_left", &"look_right"), Input.get_axis(&"look_up", &"look_down"))
	if pad.length() > 0.55:
		_stick = pad.normalized() * (DEADZONE + 60.0)
		_update_hover()
	_canvas.queue_redraw()


func _angle_of(index: int) -> float:
	var n := maxi(_stations.size(), 1)
	return deg_to_rad(-90.0 + float(index) * 360.0 / float(n))


func _update_hover() -> void:
	if _stick.length() < DEADZONE or _stations.is_empty():
		return
	var step := 360.0 / float(_stations.size())
	var ang := rad_to_deg(_stick.angle()) + 90.0 + step * 0.5
	var idx := posmod(int(floor(ang / step)), _stations.size())
	if idx != _hover:
		_hover = idx
		UiKit.sfx("ui_hover", -8.0)
		_canvas.queue_redraw()


# --- drawing ---------------------------------------------------------------------------------------

func _build_wedges() -> void:
	_wedges.clear()
	_rims.clear()
	var n := _stations.size()
	if n == 0:
		return
	var step := 360.0 / float(n)
	for i in n:
		var a0 := deg_to_rad(-90.0 + i * step - step * 0.5 + GAP_DEG * 0.5)
		var a1 := deg_to_rad(-90.0 + i * step + step * 0.5 - GAP_DEG * 0.5)
		var pts := PackedVector2Array()
		var rim := PackedVector2Array()
		var seg := 18
		for k in seg + 1:
			var a := lerpf(a0, a1, float(k) / float(seg))
			pts.append(Vector2(cos(a), sin(a)) * R_OUT)
			rim.append(Vector2(cos(a), sin(a)) * (R_OUT - 7.0))
		var gap_in := deg_to_rad(GAP_DEG * 0.5) * (R_OUT / R_IN - 1.0)
		for k in seg + 1:
			var a2 := lerpf(a1 - gap_in, a0 + gap_in, float(k) / float(seg))
			pts.append(Vector2(cos(a2), sin(a2)) * R_IN)
		_wedges.append(pts)
		_rims.append(rim)


func _draw_wheel(c: UiCanvas) -> void:
	var ctr := (c.size * 0.5).round()
	var head := UiStyle.font(&"head")
	var num := UiStyle.font(&"num")
	var body := UiStyle.font(&"body")
	c.draw_set_transform(ctr, 0.0, Vector2.ONE)
	c.draw_circle(Vector2.ZERO, R_OUT + 16.0, Color(0, 0, 0, 0.22), true, -1.0, true)
	var n := _stations.size()
	for i in n:
		if i >= _wedges.size():
			break
		var s: Dictionary = _stations[i]
		var col: Color = s["color"]
		var hovered := i == _hover
		var on_air := str(s["id"]) == _current
		var fill: Color = UiStyle.GLASS
		if hovered:
			fill = Color(col.lerp(UiStyle.CREAM, 0.12), 0.94)
		c.draw_colored_polygon(_wedges[i], fill)
		# station colour on the rim
		c.draw_polyline(_rims[i], Color(col, 1.0 if hovered else 0.85), 10.0 if hovered else 7.0, true)
		var ring := _wedges[i].duplicate()
		ring.append(_wedges[i][0])
		var edge: Color = UiStyle.LINE
		if hovered:
			edge = UiStyle.CREAM
		elif on_air:
			edge = UiStyle.TEAL_LIGHT
		c.draw_polyline(ring, edge, 3.0 if (hovered or on_air) else 2.0, true)
		var a := _angle_of(i)
		var dir := Vector2(cos(a), sin(a))
		var mid := dir * ((R_IN + R_OUT) * 0.5)
		var ink: Color = UiStyle.NAVY_DEEP if hovered else UiStyle.CREAM
		var icon_col: Color = UiStyle.NAVY_DEEP if hovered else col
		var is_off := str(s["id"]) == "off"
		UiIcons.draw(c, &"power" if is_off else &"note", mid + Vector2(0, -34.0), 50.0, icon_col)
		var label := str(s["name"]).to_upper()
		var fs := UiStyle.FS_SMALL
		var max_w := (R_OUT - R_IN) * 0.92
		var lines := PackedStringArray([label])
		if UiStyle.text_width(head, label, fs) > max_w:
			fs = UiStyle.FS_TINY
			if UiStyle.text_width(head, label, fs) > max_w:
				lines = _split_two(label)
		var ly := 16.0 - (11.0 if lines.size() > 1 else 0.0)
		for ln in lines:
			c.draw_string(head, mid + Vector2(-max_w * 0.5, ly), ln, HORIZONTAL_ALIGNMENT_CENTER, max_w, fs, ink)
			ly += fs + 4.0
		var freq := str(s["frequency"])
		if freq != "":
			c.draw_string(num, mid + Vector2(-max_w * 0.5, ly + 10.0), freq + " FM", HORIZONTAL_ALIGNMENT_CENTER, max_w, UiStyle.FS_TINY,
					Color(ink, 0.7))
		if on_air:
			var pip := mid + Vector2(0, 66.0)
			c.draw_circle(pip, 6.0, UiStyle.CORAL_HOT if not hovered else UiStyle.NAVY_DEEP, true, -1.0, true)
		# number key near the inner edge
		if i < 9:
			var np := dir * (R_IN + 20.0)
			var ns := str(i + 1)
			var nw := UiStyle.text_width(num, ns, UiStyle.FS_TINY)
			c.draw_string(num, np + Vector2(-nw * 0.5, 6.0), ns, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_TINY, Color(ink, 0.5))
	# hub
	c.draw_circle(Vector2.ZERO, R_IN - 14.0, UiStyle.GLASS_SOLID, true, -1.0, true)
	c.draw_arc(Vector2.ZERO, R_IN - 14.0, 0.0, TAU, 72, UiStyle.LINE_STRONG, 2.0, true)
	if _stick.length() >= DEADZONE:
		var sa := _stick.angle()
		c.draw_arc(Vector2.ZERO, R_IN - 24.0, sa - 0.2, sa + 0.2, 12, UiStyle.SUN, 7.0, true)
	if n == 0:
		c.draw_string(head, Vector2(-140.0, -4.0), "NO RADIO", HORIZONTAL_ALIGNMENT_CENTER, 280.0, UiStyle.FS_H3, UiStyle.DIM)
		c.draw_string(body, Vector2(-140.0, 32.0), "Radio service unavailable", HORIZONTAL_ALIGNMENT_CENTER, 280.0, UiStyle.FS_TINY, UiStyle.MUTED)
	elif _hover >= 0 and _hover < n:
		var hs: Dictionary = _stations[_hover]
		var hcol: Color = hs["color"]
		var on := str(hs["id"]) == _current
		c.draw_string(head, Vector2(-140.0, -70.0), "ON AIR" if on else ("RADIO" if str(hs["id"]) != "off" else "SWITCH OFF"),
				HORIZONTAL_ALIGNMENT_CENTER, 280.0, UiStyle.FS_TINY, UiStyle.CORAL_HOT if on else UiStyle.TEAL_LIGHT)
		var nm := str(hs["name"]).to_upper()
		var fs2 := UiStyle.FS_H3 if UiStyle.text_width(head, nm, UiStyle.FS_H3) <= 270.0 else UiStyle.FS_BODY
		c.draw_string(head, Vector2(-140.0, -24.0), nm, HORIZONTAL_ALIGNMENT_CENTER, 280.0, fs2, UiStyle.TEXT)
		var g := str(hs["genre"])
		if g != "":
			c.draw_string(body, Vector2(-140.0, 8.0), g, HORIZONTAL_ALIGNMENT_CENTER, 280.0, UiStyle.FS_SMALL, hcol)
		var tl := str(hs["tagline"])
		if tl != "":
			_wrapped(c, body, tl, Vector2(-118.0, 38.0), 236.0, UiStyle.FS_TINY, UiStyle.MUTED)
		if on and _listening() and str(hs["id"]) != "off":
			_equalizer(c, Vector2(0.0, 108.0), hcol)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var hint_y := ctr.y + R_OUT + 58.0
	if hint_y < c.size.y - 10.0:
		var hint := "Release to tune in  -  Scroll to browse  -  Esc cancels"
		if n > 0 and not _listening():
			hint = "Radio plays in vehicles  -  Release to choose  -  Esc cancels"
		UiStyle.text(c, body, Vector2(0.0, hint_y), hint, UiStyle.FS_SMALL, UiStyle.CREAM, HORIZONTAL_ALIGNMENT_CENTER, c.size.x)


## Split a caption into two balanced lines at a space.
static func _split_two(txt: String) -> PackedStringArray:
	var words := txt.split(" ", false)
	if words.size() < 2:
		return PackedStringArray([txt])
	var best := 1
	var best_d := 1.0e9
	for i in range(1, words.size()):
		var a := " ".join(words.slice(0, i))
		var b := " ".join(words.slice(i))
		var d := absf(float(a.length() - b.length()))
		if d < best_d:
			best_d = d
			best = i
	return PackedStringArray([" ".join(words.slice(0, best)), " ".join(words.slice(best))])


## Up to two centred lines of small text.
func _wrapped(c: CanvasItem, f: Font, txt: String, pos: Vector2, width: float, fs: int, col: Color) -> void:
	var words := txt.split(" ", false)
	var line := ""
	var y := pos.y
	var lines := 0
	for w in words:
		var trial := w if line == "" else line + " " + w
		if UiStyle.text_width(f, trial, fs) > width and line != "":
			c.draw_string(f, Vector2(pos.x, y), line, HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)
			y += fs + 6.0
			lines += 1
			line = w
			if lines >= 2:
				return
		else:
			line = trial
	if line != "":
		c.draw_string(f, Vector2(pos.x, y), line, HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)


## Tiny animated level meter under the hub text while the hovered station is on air.
func _equalizer(c: CanvasItem, base: Vector2, col: Color) -> void:
	for k in 7:
		var hgt := 6.0 + 16.0 * absf(sin(_time * (3.1 + k * 0.7) + k * 1.3))
		c.draw_rect(Rect2(base + Vector2(-42.0 + k * 12.0, -hgt), Vector2(7.0, hgt)), Color(col, 0.9))
