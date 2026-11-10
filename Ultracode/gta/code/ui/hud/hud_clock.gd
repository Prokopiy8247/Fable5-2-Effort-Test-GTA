class_name HudClock
extends Control
## Clock + weather pill with the current district name next to it (sits above the minimap).

var time_text: String = "12:00"
var weather_icon: StringName = &"sun"
var district: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(520.0, 46.0)
	size = custom_minimum_size


func set_time(t: String) -> void:
	if t != time_text:
		time_text = t
		queue_redraw()


func set_weather(icon: StringName) -> void:
	if icon != weather_icon:
		weather_icon = icon
		queue_redraw()


func set_district(d: String) -> void:
	var up := d.to_upper()
	if up != district:
		district = up
		queue_redraw()


func _draw() -> void:
	var num := UiStyle.font(&"num")
	var tw := UiStyle.text_width(num, time_text, UiStyle.FS_BODY)
	var pill := Rect2(0.0, 0.0, tw + 74.0, size.y)
	draw_style_box(UiStyle.cached_box(&"pill"), pill)
	var ic: Color = UiStyle.SUN
	if weather_icon == &"moon" or weather_icon == &"cloud" or weather_icon == &"fog":
		ic = UiStyle.CREAM
	elif weather_icon == &"rain" or weather_icon == &"storm":
		ic = Color(0.56, 0.79, 0.91)
	UiIcons.draw(self, weather_icon, Vector2(30.0, size.y * 0.5), 24.0, ic)
	UiStyle.text_in(self, num, Rect2(52.0, 0.0, tw + 4.0, size.y), time_text, UiStyle.FS_BODY, UiStyle.TEXT)
	if district != "":
		UiStyle.text_in(self, UiStyle.font(&"head"), Rect2(pill.end.x + 14.0, 0.0, size.x - pill.end.x - 14.0, size.y), district,
				UiStyle.FS_SMALL, UiStyle.CREAM, HORIZONTAL_ALIGNMENT_LEFT, true)
