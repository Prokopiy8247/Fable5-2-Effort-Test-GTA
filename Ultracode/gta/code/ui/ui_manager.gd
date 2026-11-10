extends CanvasLayer
## Autoload "UI": HUD + screen manager + mouse-mode owner.   Docs: docs/UI.md
##
## Screens are Controls created on demand from SCREENS (fixed paths, missing files are skipped,
## so any module can add a screen by creating the file at the agreed path).
## A screen script `extends Control` (or UiScreen) and may define:
##     const PAUSES_GAME := false     # pause the tree while open
##     const TIME_SCALE := 1.0        # slow motion while open (weapon wheel: 0.15)
##     const LOCKS_INPUT := true      # Game.lock_input() while open
##     const SHOWS_MOUSE := true      # release the mouse cursor while open
##     const HIDES_HUD := false       # hide the HUD while open (full-screen menus)
##     var screen_id: String          # filled in by the manager
##     func open(args: Dictionary) -> void
##     func close() -> void
##     func handle_back() -> bool     # Esc: return true if the screen consumed it
##     func regain_focus() -> void    # called when a screen above this one closed
## Gameplay code never touches Input.mouse_mode directly: UI owns it (captured during play when a
## focused window exists; never captured while headless or under the TestHarness).
##
## Tree:  UI (CanvasLayer 10) -> Root (Control with the game Theme) -> Hud, Screens, Overlay
## (toasts, banner, subtitle), Fade, Veil (loading), Debug.

const HUD_SCENE := "res://gta/scenes/ui/hud.tscn"
const THEME_PATH := "res://gta/resources/themes/game_theme.tres"

const SCREENS := {
	"pause": "res://gta/code/ui/screens/pause_screen.gd",
	"status": "res://gta/code/ui/screens/status_screen.gd",
	"map": "res://gta/code/ui/screens/map_screen.gd",
	"weapon_wheel": "res://gta/code/ui/screens/weapon_wheel.gd",
	"radio_wheel": "res://gta/code/ui/screens/radio_wheel.gd",
	"admin": "res://gta/code/ui/screens/admin_menu.gd",
	"phone": "res://gta/code/ui/screens/phone_screen.gd",
	"shop_weapons": "res://gta/code/ui/screens/weapon_shop_screen.gd",
	"shop_clothing": "res://gta/code/ui/screens/clothing_shop_screen.gd",
	"shop_barber": "res://gta/code/ui/screens/barber_screen.gd",
	"shop_general": "res://gta/code/ui/screens/general_shop_screen.gd",
	"mod_garage": "res://gta/code/ui/screens/mod_garage_screen.gd",
	"garage": "res://gta/code/ui/screens/garage_screen.gd",
	"wardrobe": "res://gta/code/ui/screens/wardrobe_screen.gd",
	"taxi": "res://gta/code/ui/screens/taxi_screen.gd",
	"safehouse": "res://gta/code/ui/screens/safehouse_screen.gd",
	"activity_result": "res://gta/code/ui/screens/activity_result_screen.gd",
	"photo": "res://gta/code/ui/screens/photo_mode.gd",
}

const QUICK_SLOT := "quick"
## screens the M key may open the map on top of
const MAP_OVER := ["", "pause"]

var hud: Control = null
var game_theme: Theme = null            ## the one Theme (built by UiThemeBuilder)
var map_data: UiMapData = null          ## shared minimap / full map data
var nav: UiNav = null                   ## waypoint + GPS route
var stats: UiStats = null               ## free-roam statistics (status screen)
var toasts: UiToasts = null
var debug_overlay_visible: bool = false
var mouse_capture_enabled: bool = true  ## set false to keep the cursor free during gameplay

var _open_screens: Dictionary = {}      ## id -> Control (insertion order = stack order)
var _screen_flags: Dictionary = {}      ## id -> {pause, scale, lock, mouse, hide_hud}
var _prompt_text: String = ""
var _root: Control = null
var _screen_host: Control = null
var _overlay: Control = null
var _banner: UiBanner = null
var _subtitle: Label = null
var _subtitle_box: PanelContainer = null
var _subtitle_left: float = 0.0
var _fade: ColorRect = null
var _fade_token: int = 0
var _veil: UiCanvas = null
var _veil_alpha: float = 1.0
var _veil_done: bool = false
var _veil_spin: float = 0.0
var _debug_box: PanelContainer = null
var _debug_label: Label = null
var _debug_timer: float = 0.0
var _hud_user_visible: bool = true
var _session: bool = true               ## false when no bootstrap Main exists (isolated test scenes)
var _pause_count: int = 0
var _wheel_hold: bool = false
var _radio_hold: bool = false
var _radio_hint_t: int = -100000        ## msec of the last "no radio" toast (rate limit)
var _notifying: bool = false
var _real_dt: float = 1.0 / 60.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_extend_ui_actions()
	game_theme = UiThemeBuilder.build()
	map_data = UiMapData.new()
	nav = UiNav.new()
	nav.name = "Nav"
	add_child(nav)
	stats = UiStats.new()
	stats.name = "Stats"
	add_child(stats)
	_build_tree()
	debug_overlay_visible = bool(Settings.get_value("show_fps"))
	_debug_box.visible = debug_overlay_visible
	EventBus.game_ready.connect(_on_game_ready)
	EventBus.notification.connect(_on_notification)
	EventBus.activity_finished.connect(_on_activity_finished)
	if Game.is_ready:
		_on_game_ready()
	else:
		_check_session.call_deferred()


# =================================================================================================
# public API (frozen contract)
# =================================================================================================

func get_hud() -> Control:
	return hud


func set_hud_visible(on: bool) -> void:
	_hud_user_visible = on
	if on and not _session:
		_session = true         # an isolated test scene asked for the HUD explicitly
	_update_hud_visibility()


## Toast-style message. kind: "info","good","warn","bad","money" (+ "skill", "radio").
func notify(text: String, kind: String = "info", duration: float = 3.5) -> void:
	if toasts != null:
		toasts.push(text, kind, duration)
	_notifying = true
	EventBus.notification.emit(text, kind)
	_notifying = false


## Context prompt near the bottom of the screen, e.g. show_prompt("Enter vehicle", "enter_vehicle").
func show_prompt(text: String, action: String = "interact") -> void:
	_prompt_text = text
	var hr := hud as HudRoot
	if hr != null and hr.prompt != null:
		hr.prompt.show_prompt(text, InputSetup.label(action) if action != "" else "")


func hide_prompt() -> void:
	_prompt_text = ""
	var hr := hud as HudRoot
	if hr != null and hr.prompt != null:
		hr.prompt.hide_prompt()


## Big centre banner (e.g. death / arrest overlay). Original wording and styling only.
func banner(text: String, sub: String = "", color: Color = Color.WHITE, duration: float = 4.0) -> void:
	if _banner != null:
		_banner.show_banner(text, sub, color, duration)


func subtitle(text: String, duration: float = 3.0) -> void:
	if _subtitle == null:
		return
	if text == "" or not bool(Settings.get_value("subtitles")):
		_subtitle_left = 0.0
		_subtitle_box.visible = false
		return
	_subtitle.text = text
	_subtitle.custom_minimum_size.x = minf(UiStyle.text_width(UiStyle.font(&"body"), text, UiStyle.FS_LARGE) + 16.0, 1200.0)
	_subtitle_left = maxf(duration, 0.5)
	_subtitle_box.visible = true


## Full-screen fades (awaitable; run on real time, also while paused or in slow motion).
func fade_out(duration: float = 0.6) -> void:
	await _fade_to(1.0, duration)


func fade_in(duration: float = 0.6) -> void:
	await _fade_to(0.0, duration)


func open_screen(id: String, args: Dictionary = {}) -> Control:
	if _open_screens.has(id):
		return _open_screens[id]
	var path: String = SCREENS.get(id, "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	var node: Control = null
	if res is PackedScene:
		node = (res as PackedScene).instantiate() as Control
	elif res is Script and (res as Script).can_instantiate():
		node = (res as Script).new() as Control
	if node == null:
		push_warning("UI: screen '%s' could not be created from %s" % [id, path])
		return null
	node.name = id.to_pascal_case()
	if "screen_id" in node:
		node.set("screen_id", id)
	var flags := {
		"pause": bool(_screen_const(node, "PAUSES_GAME", false)),
		"scale": float(_screen_const(node, "TIME_SCALE", 1.0)),
		"lock": bool(_screen_const(node, "LOCKS_INPUT", true)),
		"mouse": bool(_screen_const(node, "SHOWS_MOUSE", true)),
		"hide_hud": bool(_screen_const(node, "HIDES_HUD", false)),
	}
	_open_screens[id] = node
	_screen_flags[id] = flags
	_screen_host.add_child(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if flags["lock"]:
		Game.lock_input()
	if float(flags["scale"]) < 0.999:
		Game.request_time_scale("ui_" + id, float(flags["scale"]))
	if flags["pause"]:
		_pause_count += 1
		if _pause_count == 1:
			Game.set_paused(true)
	_update_mouse_mode()
	_update_hud_visibility()
	if node.has_method("open"):
		node.call("open", args)
	sfx("ui_open")
	EventBus.ui_screen_opened.emit(id)
	return node


## Close one screen, or the top-most one when id is "".
func close_screen(id: String = "") -> void:
	if id == "":
		if _open_screens.is_empty():
			return
		id = _open_screens.keys().back()
	if not _open_screens.has(id):
		return
	var node: Control = _open_screens[id]
	var flags: Dictionary = _screen_flags.get(id, {})
	_open_screens.erase(id)
	_screen_flags.erase(id)
	if id == "weapon_wheel":
		_wheel_hold = false
	elif id == "radio_wheel":
		_radio_hold = false
	if is_instance_valid(node):
		if node.has_method("close"):
			node.call("close")
		node.visible = false
		node.queue_free()
	if flags.get("lock", true):
		Game.unlock_input()
	if float(flags.get("scale", 1.0)) < 0.999:
		Game.release_time_scale("ui_" + id)
	if flags.get("pause", false):
		_pause_count = maxi(_pause_count - 1, 0)
		if _pause_count == 0:
			Game.set_paused(false)
	_update_mouse_mode()
	_update_hud_visibility()
	sfx("ui_close")
	EventBus.ui_screen_closed.emit(id)
	var top := get_top_screen()
	if top != "":
		var below: Control = _open_screens[top]
		if is_instance_valid(below) and below.has_method("regain_focus"):
			below.call("regain_focus")


func toggle_screen(id: String, args: Dictionary = {}) -> void:
	if _open_screens.has(id):
		close_screen(id)
	else:
		open_screen(id, args)


func close_all_screens() -> void:
	var ids := _open_screens.keys()
	ids.reverse()
	for id: String in ids:
		close_screen(id)


## True if `id` is open; with "" true if ANY screen is open.
func is_screen_open(id: String = "") -> bool:
	if id == "":
		return not _open_screens.is_empty()
	return _open_screens.has(id)


# =================================================================================================
# public API (additions)
# =================================================================================================

## Id of the top-most open screen ("" if none).
func get_top_screen() -> String:
	if _open_screens.is_empty():
		return ""
	return str(_open_screens.keys().back())


## The open screen node for `id` (null if not open).
func get_screen(id: String) -> Control:
	return _open_screens.get(id, null)


func get_game_theme() -> Theme:
	return game_theme


## Player waypoint (also drives the GPS route on the minimap / map). Emits EventBus.waypoint_changed.
func set_waypoint(pos: Vector3) -> void:
	nav.set_waypoint(pos)


func clear_waypoint() -> void:
	nav.clear_waypoint()


func has_waypoint() -> bool:
	return nav.has_waypoint


func get_fade_alpha() -> float:
	return _fade.color.a if _fade != null else 0.0


func is_banner_showing() -> bool:
	return _banner != null and _banner.is_showing()


func get_prompt_text() -> String:
	return _prompt_text


## Show / hide the full-screen loading veil (it is shown automatically from boot until
## EventBus.game_ready; other modules may reuse it for long loads). Hiding fades it out.
func set_loading_veil(on: bool) -> void:
	if _veil == null:
		return
	if on:
		_veil_done = false
		_veil_alpha = 1.0
		_veil.modulate.a = 1.0
		_veil.visible = true
	else:
		_veil_done = true
	_update_mouse_mode()


func is_loading_veil_visible() -> bool:
	return _veil != null and _veil.visible


func set_debug_overlay(on: bool) -> void:
	debug_overlay_visible = on
	if _debug_box != null:
		_debug_box.visible = on and not has_rich_debug_overlay()
		_debug_timer = 1.0


## True when the debug system draws its own (richer) performance overlay on the same flag; the
## basic text box of the UI then stays hidden (UI.debug_overlay_visible is still the one switch).
func has_rich_debug_overlay() -> bool:
	var d := Game.get_system("debug")
	return d != null and d.has_method("is_overlay_visible")


func toggle_debug_overlay() -> void:
	set_debug_overlay(not debug_overlay_visible)


## UI sound through the Audio autoload (unknown ids are silent).
func sfx(id: String, volume_db: float = -4.0) -> void:
	UiKit.sfx(id, volume_db)


func quick_save() -> bool:
	var ok: bool = SaveSystem.save_game(QUICK_SLOT)
	notify("Game saved" if ok else "Save failed", "good" if ok else "bad")
	return ok


func quick_load() -> bool:
	if not SaveSystem.has_save(QUICK_SLOT):
		notify("No quick save found", "warn")
		return false
	var ok: bool = SaveSystem.load_game(QUICK_SLOT)
	notify("Game loaded" if ok else "Load failed", "good" if ok else "bad")
	return ok


## Run one of the global UI actions (the same entry point _unhandled_input uses; handy for
## tests, gamepad glue and other modules). Returns true when the action was consumed.
func handle_action(action: String, pressed: bool = true) -> bool:
	if not pressed:
		if action == "weapon_wheel" and _wheel_hold:
			_wheel_hold = false
			close_screen("weapon_wheel")
			return true
		if action == "radio_wheel" and _radio_hold:
			_radio_hold = false
			close_screen("radio_wheel")
			return true
		return false
	match action:
		"pause", "ui_cancel":
			if action == "ui_cancel" and _open_screens.is_empty():
				return false
			_back_or_pause()
		"map":
			if _open_screens.has("map"):
				close_screen("map")
			elif get_top_screen() in MAP_OVER:
				open_screen("map")
			else:
				return false
		"weapon_wheel":
			if not _open_screens.is_empty() or Game.is_input_locked() or not Game.is_ready:
				return false
			if open_screen("weapon_wheel") == null:
				return false
			_wheel_hold = true
		"radio_wheel":
			if not _open_screens.is_empty() or Game.is_input_locked() or not Game.is_ready:
				return false
			if not radio_wheel_available():
				return false
			if open_screen("radio_wheel") == null:
				return false
			_radio_hold = true
		"admin_menu":
			return _toggle_exclusive("admin")
		"phone":
			return _toggle_exclusive("phone")
		"photo_mode":
			return _toggle_exclusive("photo")
		"quick_save":
			if _pause_count > 0 and get_top_screen() != "pause":
				return false
			quick_save()
		"quick_load":
			if not _open_screens.is_empty():
				return false
			quick_load()
		"debug_overlay":
			toggle_debug_overlay()
		_:
			return false
	return true


# =================================================================================================
# input / frame
# =================================================================================================

const _GLOBAL_ACTIONS: Array[StringName] = [&"pause", &"map", &"weapon_wheel", &"radio_wheel", &"admin_menu", &"phone",
		&"photo_mode", &"quick_save", &"quick_load", &"debug_overlay", &"ui_cancel"]
const _HOLD_ACTIONS: Array[StringName] = [&"weapon_wheel", &"radio_wheel"]


func _unhandled_input(event: InputEvent) -> void:
	if not _session or not Game.is_ready:
		return
	if event is InputEventMouseMotion:
		return
	for hold in _HOLD_ACTIONS:
		if event.is_action_released(hold):
			if handle_action(String(hold), false):
				get_viewport().set_input_as_handled()
			return
	for action in _GLOBAL_ACTIONS:
		if event.is_action_pressed(action):
			if handle_action(String(action), true):
				get_viewport().set_input_as_handled()
			return


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_update_mouse_mode()


func _process(delta: float) -> void:
	_real_dt = delta / maxf(Engine.time_scale, 0.05)
	# weapon wheel safety: the key went up while the window had no focus
	if _wheel_hold and _open_screens.has("weapon_wheel") and not Input.is_action_pressed(&"weapon_wheel"):
		handle_action("weapon_wheel", false)
	if _radio_hold and _open_screens.has("radio_wheel") and not Input.is_action_pressed(&"radio_wheel"):
		handle_action("radio_wheel", false)
	if _subtitle_left > 0.0:
		_subtitle_left -= _real_dt
		if _subtitle_left <= 0.0:
			_subtitle_box.visible = false
	if _veil != null and _veil.visible:
		_veil_spin += _real_dt
		if _veil_done:
			_veil_alpha = maxf(_veil_alpha - _real_dt * 2.5, 0.0)
			_veil.modulate.a = _veil_alpha
			if _veil_alpha <= 0.0:
				_veil.visible = false
		_veil.queue_redraw()
	if debug_overlay_visible and _debug_box.visible:
		_debug_timer += _real_dt
		if _debug_timer >= 0.25:
			_debug_timer = 0.0
			_update_debug()


func _back_or_pause() -> void:
	if _open_screens.has("weapon_wheel"):
		var wheel: Control = _open_screens["weapon_wheel"]
		if is_instance_valid(wheel) and wheel.has_method("handle_back"):
			wheel.call("handle_back")       # marks the selection as cancelled
		close_screen("weapon_wheel")
		return
	var top := get_top_screen()
	if top == "":
		open_screen("pause")
		return
	var node: Control = _open_screens[top]
	if is_instance_valid(node) and node.has_method("handle_back") and bool(node.call("handle_back")):
		return
	close_screen(top)


func _toggle_exclusive(id: String) -> bool:
	if _open_screens.has(id):
		close_screen(id)
		return true
	if not _open_screens.is_empty():
		return false
	return open_screen(id) != null


# =================================================================================================
# internals
# =================================================================================================

## W / A / S / D also drive menu focus (ui_up / ui_left / ui_down / ui_right).
func _extend_ui_actions() -> void:
	var extra := {"ui_up": KEY_W, "ui_down": KEY_S, "ui_left": KEY_A, "ui_right": KEY_D}
	for action: String in extra:
		if not InputMap.has_action(action):
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = extra[action]
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


func _build_tree() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = game_theme
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if ResourceLoader.exists(HUD_SCENE):
		var ps := load(HUD_SCENE) as PackedScene
		if ps != null:
			hud = ps.instantiate() as Control
	if hud == null:
		hud = HudRoot.new()
	hud.name = "Hud"
	_root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_screen_host = _layer("Screens")
	_overlay = _layer("Overlay")

	toasts = UiToasts.new()
	toasts.name = "Toasts"
	_overlay.add_child(toasts)
	toasts.anchor_left = 1.0
	toasts.anchor_right = 1.0
	toasts.offset_left = -UiStyle.MARGIN - toasts.custom_minimum_size.x
	toasts.offset_right = -UiStyle.MARGIN
	toasts.offset_top = UiStyle.MARGIN + 74.0
	toasts.offset_bottom = UiStyle.MARGIN + 74.0 + toasts.custom_minimum_size.y

	_banner = UiBanner.new()
	_banner.name = "Banner"
	_overlay.add_child(_banner)

	var sub_holder := CenterContainer.new()
	sub_holder.name = "SubtitleHolder"
	sub_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(sub_holder)
	sub_holder.anchor_left = 0.1
	sub_holder.anchor_right = 0.9
	sub_holder.anchor_top = 1.0
	sub_holder.anchor_bottom = 1.0
	sub_holder.offset_top = -360.0
	sub_holder.offset_bottom = -262.0
	_subtitle_box = PanelContainer.new()
	_subtitle_box.name = "Subtitle"
	_subtitle_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_box.add_theme_stylebox_override("panel", UiStyle.box(Color(0.01, 0.03, 0.07, 0.62), 12, UiStyle.CLEAR, 0, 0, 26, 12))
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_font_size_override("font_size", UiStyle.FS_LARGE)
	_subtitle.add_theme_color_override("font_color", UiStyle.CREAM)
	_subtitle_box.add_child(_subtitle)
	sub_holder.add_child(_subtitle_box)
	_subtitle_box.visible = false

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	_root.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_veil = UiCanvas.new(_draw_veil)
	_veil.name = "Veil"
	_root.add_child(_veil)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_debug_box = PanelContainer.new()
	_debug_box.name = "Debug"
	_debug_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_box.add_theme_stylebox_override("panel", UiStyle.box(Color(0.01, 0.03, 0.07, 0.7), 10, UiStyle.LINE, 2, 0, 16, 10))
	_debug_label = Label.new()
	_debug_label.add_theme_font_override("font", UiStyle.font(&"num"))
	_debug_label.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
	_debug_label.add_theme_color_override("font_color", UiStyle.TEAL_LIGHT)
	_debug_box.add_child(_debug_label)
	_root.add_child(_debug_box)
	_debug_box.position = Vector2(UiStyle.MARGIN, UiStyle.MARGIN)
	_debug_box.visible = false


func _layer(layer_name: String) -> Control:
	var c := Control.new()
	c.name = layer_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## Per-screen constant lookup (walks base scripts).
func _screen_const(node: Object, const_name: String, fallback: Variant) -> Variant:
	var scr := node.get_script() as Script
	while scr != null:
		var map := scr.get_script_constant_map()
		if map.has(const_name):
			return map[const_name]
		scr = scr.get_base_script()
	return fallback


func _on_game_ready() -> void:
	_session = true
	_veil_done = true
	map_data.refresh()
	_update_mouse_mode()
	_update_hud_visibility()
	set_debug_overlay(debug_overlay_visible)      # the debug system may own the overlay now


## The radio wheel needs the radio system and a vehicle with a radio (or a forced listening state).
## On foot the key does nothing; in a vehicle without a radio a short toast explains why.
func radio_wheel_available() -> bool:
	var radio := Game.get_system("radio")
	if radio == null or not radio.has_method("get_stations") or not radio.has_method("set_station"):
		return false
	if radio.has_method("is_listening"):
		if bool(radio.call("is_listening")):
			return true
		if Game.get_player_vehicle() != null and Time.get_ticks_msec() - _radio_hint_t > 4000:
			_radio_hint_t = Time.get_ticks_msec()
			notify("No radio in this vehicle", "radio", 2.2)
		return false
	return Game.get_player_vehicle() != null


## Activities report a finished run on EventBus.activity_finished(id, result); the result panel
## opens deferred (an activity system that opens "activity_result" itself in the same frame wins).
## result["result_screen"] = false opts out.
func _on_activity_finished(activity_id: String, result: Dictionary) -> void:
	if not bool(result.get("result_screen", true)):
		return
	_open_activity_result.call_deferred(activity_id, result)


func _open_activity_result(activity_id: String, result: Dictionary) -> void:
	if not Game.is_ready or _open_screens.has("activity_result"):
		return
	var args := result.duplicate()
	if not args.has("id"):
		args["id"] = activity_id
	open_screen("activity_result", args)


## Runs one frame after boot: without the bootstrap Main (isolated test scenes) there is no
## session, so the loading veil and the HUD stay out of the way.
func _check_session() -> void:
	if Game.main == null and not Game.is_ready:
		_session = false
		_veil.visible = false
		_update_hud_visibility()


func _on_notification(text: String, kind: String) -> void:
	if _notifying or toasts == null:
		return
	toasts.push(text, kind, 3.5)


func _update_hud_visibility() -> void:
	# a full-screen (HIDES_HUD) screen also hides the screens stacked below it while it is on top
	var covered := false
	var ids := _open_screens.keys()
	for i in range(ids.size() - 1, -1, -1):
		var node: Control = _open_screens[ids[i]]
		if is_instance_valid(node) and node.visible == covered:
			node.visible = not covered
		if _screen_flags.get(ids[i], {}).get("hide_hud", false):
			covered = true
	if hud == null:
		return
	var show_hud := _hud_user_visible and (_session or Game.is_ready)
	if show_hud:
		for id: String in _screen_flags:
			if _screen_flags[id].get("hide_hud", false):
				show_hud = false
				break
	hud.visible = show_hud


func _update_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want_visible := not Game.is_ready or not _session or not mouse_capture_enabled or TestHarness.active \
			or (_veil != null and _veil.visible and not _veil_done)
	if not want_visible:
		for id: String in _screen_flags:
			if _screen_flags[id].get("mouse", true):
				want_visible = true
				break
	if not want_visible:
		var win := get_window()
		if win != null and not win.has_focus():
			want_visible = true
	var mode := Input.MOUSE_MODE_VISIBLE if want_visible else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode
		if Game.flags.has("ui_debug"):
			print("[UI] mouse mode -> ", "visible" if want_visible else "captured", "  (screens: ", _open_screens.keys(), ")")


func _fade_to(target: float, duration: float) -> void:
	_fade_token += 1
	var token := _fade_token
	var from := _fade.color.a
	_fade.visible = true
	if duration > 0.0:
		var t := 0.0
		while t < duration and token == _fade_token:
			await get_tree().process_frame
			t += _real_dt
			if token == _fade_token:
				_fade.color.a = lerpf(from, target, clampf(t / duration, 0.0, 1.0))
	if token == _fade_token:
		_fade.color.a = target
		_fade.visible = target > 0.001


func _draw_veil(c: UiCanvas) -> void:
	var sz := c.size
	c.draw_rect(Rect2(Vector2.ZERO, sz), UiStyle.NAVY_DEEP)
	c.draw_rect(Rect2(0.0, sz.y * 0.62, sz.x, sz.y * 0.38), Color(UiStyle.NAVY, 0.6))
	var head := UiStyle.font(&"head")
	var cy := sz.y * 0.44
	var title := "HALCYON BAY"
	var tw := UiStyle.text_width(head, title, UiStyle.FS_HUGE)
	c.draw_string(head, Vector2((sz.x - tw) * 0.5, cy), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_HUGE, UiStyle.CREAM)
	var bar_w := minf(tw, sz.x * 0.8)
	c.draw_rect(Rect2((sz.x - bar_w) * 0.5, cy + 22.0, bar_w * 0.34, 6.0), UiStyle.CORAL)
	c.draw_rect(Rect2((sz.x - bar_w) * 0.5 + bar_w * 0.34, cy + 22.0, bar_w * 0.33, 6.0), UiStyle.SUN)
	c.draw_rect(Rect2((sz.x - bar_w) * 0.5 + bar_w * 0.67, cy + 22.0, bar_w * 0.33, 6.0), UiStyle.TEAL)
	UiStyle.text(c, head, Vector2(0.0, cy + 78.0), "FREE ROAM", UiStyle.FS_LARGE, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER, sz.x, false)
	var sc := Vector2(sz.x * 0.5, sz.y * 0.78)
	c.draw_arc(sc, 26.0, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 6.0, true)
	var a0 := _veil_spin * 4.0
	c.draw_arc(sc, 26.0, a0, a0 + 1.9, 20, UiStyle.TEAL_LIGHT, 6.0, true)
	UiStyle.text(c, head, Vector2(0.0, sc.y + 66.0), "LOADING", UiStyle.FS_SMALL, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER, sz.x, false)


func _update_debug() -> void:
	var p := Game.get_player_position()
	var district := ""
	var w := Game.world
	if w != null and is_instance_valid(w) and w.has_method("get_district"):
		district = str(w.call("get_district", p))
	var tree := get_tree()
	var txt := "FPS %d   %.1f ms\n" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)]
	txt += "POS %.1f  %.1f  %.1f   %s\n" % [p.x, p.y, p.z, district]
	txt += "DRAW %d   OBJ %d   PRIM %dk\n" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)]
	txt += "VEH %d   NPC %d   POLICE %d   NODES %d\n" % [tree.get_nodes_in_group("vehicle").size(),
			tree.get_nodes_in_group("npc").size(), tree.get_nodes_in_group("police").size(),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))]
	txt += "TIME %s   %s   WANTED %d   x%.2f" % [WorldClock.get_time_string(), str(Weather.current), Wanted.level, Engine.time_scale]
	_debug_label.text = txt
