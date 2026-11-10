class_name HudActivity
extends Control
## Activity card (top-left): title, big timer, checkpoint / lap / score chips and a hint line,
## shown between EventBus.activity_started and activity_finished. HudRoot feeds it with
## set_info() from the activities system's polling hook get_hud_info() (10 Hz); the timer is
## advanced locally every frame between polls so it runs smoothly.
## Info keys (all optional): title, subtitle, time (seconds), time_mode ("up" | "down"),
## countdown (s, > 0 = pre-start countdown shown instead of the timer), checkpoint, checkpoints,
## lap, laps, position, racers, round, rounds, score, target, hits, shots, distance, min_distance,
## hint, color. In group "hud_activity_widget" (the activities system then skips its fallback HUD).

const SIZE := Vector2(400.0, 214.0)

var active: bool = false
var activity_id: String = ""
var info: Dictionary = {}

var _alpha: float = 0.0
var _time: float = 0.0
var _has_time: bool = false
var _count_down: bool = false
var _time_str: String = ""
var _shown_tenths: int = -999999
var _pulse: float = 0.0
var _last_cp: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	modulate.a = 0.0
	visible = false
	add_to_group(&"hud_activity_widget")


func start(id: String, title: String) -> void:
	activity_id = id
	active = true
	info = {"title": title}
	_time = 0.0
	_has_time = true
	_count_down = false
	_shown_tenths = -999999
	_last_cp = -1
	visible = true
	_update_time_str()
	queue_redraw()


func stop() -> void:
	active = false


## Merge a get_hud_info() snapshot. A "time" key re-syncs the local timer.
func set_info(d: Dictionary) -> void:
	for k: Variant in d:
		info[k] = d[k]
	if d.has("time"):
		_time = float(d["time"])
		_has_time = true
	if d.has("time_mode"):
		_count_down = str(d["time_mode"]) == "down"
	var cp := int(info.get("checkpoint", -1))
	if cp != _last_cp:
		if _last_cp >= 0 and cp > _last_cp:
			_pulse = 1.0
		_last_cp = cp
	_update_time_str()
	queue_redraw()


func get_time_text() -> String:
	return _time_str


func _process(delta: float) -> void:
	var target := 1.0 if active else 0.0
	if _alpha != target:
		_alpha = move_toward(_alpha, target, delta * 4.0)
		modulate.a = _alpha
		if _alpha <= 0.0:
			visible = false
			return
	if not active:
		return
	if _has_time:
		_time = maxf(_time + (-delta if _count_down else delta), 0.0)
		_update_time_str()
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 2.0, 0.0)
		queue_redraw()


func _update_time_str() -> void:
	var tenths := int(floor(_time * 10.0))
	if tenths == _shown_tenths:
		return
	_shown_tenths = tenths
	var m := tenths / 600
	var s := (tenths / 10) % 60
	_time_str = "%d:%02d.%d" % [m, s, tenths % 10]
	queue_redraw()


func _draw() -> void:
	var accent: Variant = info.get("color", UiStyle.SUN)
	var col: Color = accent if accent is Color else UiStyle.SUN
	var head := UiStyle.font(&"head")
	var num := UiStyle.font(&"num")
	var body := UiStyle.font(&"body")
	var card := Rect2(Vector2.ZERO, SIZE)
	draw_style_box(UiStyle.cached_box(&"glass"), card)
	draw_style_box(UiStyle._fill_box(col), Rect2(0.0, 18.0, 7.0, SIZE.y - 36.0))
	UiIcons.draw(self, &"flag", Vector2(34.0, 34.0), 26.0, col)
	var title := str(info.get("title", activity_id.capitalize())).to_upper()
	draw_string(head, Vector2(56.0, 44.0), title, HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 76.0, UiStyle.FS_SMALL, UiStyle.TEXT)
	var sub := str(info.get("subtitle", ""))
	# timer (or the pre-start countdown)
	var cd := float(info.get("countdown", 0.0))
	if cd > 0.0:
		UiIcons.draw(self, &"flag", Vector2(40.0, 98.0), 30.0, UiStyle.SUN)
		draw_string(num, Vector2(66.0, 118.0), str(int(ceil(cd))), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 58, UiStyle.SUN)
		draw_string(head, Vector2(120.0, 112.0), "GET READY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_SMALL, UiStyle.CREAM)
	else:
		var low := _count_down and _time < 10.0
		var tcol: Color = UiStyle.CORAL_HOT if low else UiStyle.CREAM
		UiIcons.draw(self, &"timer", Vector2(40.0, 98.0), 30.0, tcol)
		draw_string(num, Vector2(66.0, 118.0), _time_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 58, tcol)
	if sub != "":
		draw_string(body, Vector2(SIZE.x - 20.0 - 170.0, 112.0), sub, HORIZONTAL_ALIGNMENT_RIGHT, 170.0, UiStyle.FS_TINY, UiStyle.MUTED)
	# chips
	var chips: Array[String] = []
	if info.has("checkpoints") and int(info["checkpoints"]) > 0:
		chips.append("CP %d/%d" % [int(info.get("checkpoint", 0)), int(info["checkpoints"])])
	if info.has("laps") and int(info["laps"]) > 1:
		chips.append("LAP %d/%d" % [maxi(int(info.get("lap", 1)), 1), int(info["laps"])])
	if info.has("position") and int(info.get("racers", 0)) > 1:
		chips.append("POS %d/%d" % [int(info["position"]), int(info["racers"])])
	if int(info.get("rounds", 0)) > 1:
		chips.append("RND %d/%d" % [maxi(int(info.get("round", 1)), 1), int(info["rounds"])])
	if info.has("distance"):
		var dist_s := "DIST %d m" % int(float(info["distance"]))
		if float(info.get("min_distance", 0.0)) > 0.0:
			dist_s += " / %d" % int(float(info["min_distance"]))
		chips.append(dist_s)
	if info.has("score"):
		var sc := "%s" % str(int(float(info["score"])))
		if info.has("target"):
			sc += " / %s" % str(int(float(info["target"])))
		chips.append("SCORE " + sc)
	if info.has("shots") and int(info["shots"]) > 0:
		chips.append("HITS %d/%d" % [int(info.get("hits", 0)), int(info["shots"])])
	var x := 22.0
	for i in chips.size():
		var t := chips[i]
		var w := UiStyle.text_width(head, t, UiStyle.FS_TINY) + 24.0
		var r := Rect2(x, 142.0, w, 32.0)
		var hot := i == 0 and _pulse > 0.0
		draw_style_box(UiStyle.box(Color(col, 0.22 + 0.5 * _pulse) if hot else Color(1, 1, 1, 0.1), 8), r)
		UiStyle.text_in(self, head, r, t, UiStyle.FS_TINY, UiStyle.NAVY_DEEP if (hot and _pulse > 0.5) else UiStyle.TEXT,
				HORIZONTAL_ALIGNMENT_CENTER)
		x += w + 8.0
	var hint := str(info.get("hint", ""))
	if hint != "":
		draw_string(body, Vector2(22.0, SIZE.y - 14.0), hint, HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 44.0, UiStyle.FS_TINY, UiStyle.MUTED)
