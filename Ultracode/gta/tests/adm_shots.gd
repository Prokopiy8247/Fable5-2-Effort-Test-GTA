extends Node
## Admin menu + performance overlay screenshots (windowed, about 12 s at 30 fps).
##   tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 120 -UserArgs '--test=adm_shots'
## -> qa/screenshots/adm_<tab>.png for the 8 tabs, adm_overlay.png, adm_menu_overlay.png.
## '--adm_only=world,debug,overlay' limits the shots (tab ids, "overlay", "menu_overlay").

const TABS := ["teleport", "vehicles", "weapons", "player", "wanted", "world", "services", "debug"]

var T: Node = null
var _only: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	T = TestHarness
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--adm_only="):
			_only = a.substr(11).split(",", false)
	await T.wait_frames(20)
	var dbg := Game.get_system("debug")
	if dbg == null:
		T.finish(false, "no debug system")
		return
	Game.invulnerable = true
	dbg.call("teleport_player", "downtown_plaza", false)
	dbg.call("set_time", 10.5)
	dbg.call("set_weather", "clear", true)
	dbg.call("give_weapon", "pistol", false)
	dbg.call("give_weapon", "assault_rifle", true)
	dbg.call("set_money", 48250)
	dbg.call("set_wanted", 2)
	await T.wait_frames(45)
	var scr: Control = UI.open_screen("admin", {"tab": "teleport"})
	T.check(scr != null, "admin menu opens")
	if scr == null:
		T.finish(false, "admin screen missing")
		return
	for id: String in TABS:
		if not _want(id):
			continue
		scr.call("select_tab", id)
		await T.wait_frames(10)
		await T.shot("adm_" + id)
		T.check(scr.call("get_tab_id") == id, "tab %s shown" % id)
		if id == "world":
			var page: Variant = scr.call("get_page", "world")
			if page is ScrollContainer:
				(page as ScrollContainer).scroll_vertical = 100000
				await T.wait_frames(6)
				await T.shot("adm_world_sim")
	UI.close_screen("admin")
	dbg.call("set_wanted", 0)
	if _want("overlay") or _want("menu_overlay"):
		dbg.call("set_overlay_visible", true)
		await T.wait_frames(50)
		if _want("overlay"):
			await T.shot("adm_overlay")
		if _want("menu_overlay"):
			UI.open_screen("admin", {"tab": "debug"})
			await T.wait_frames(20)
			await T.shot("adm_menu_overlay")
			UI.close_screen("admin")
		dbg.call("set_overlay_visible", false)
	T.finish()


func _want(id: String) -> bool:
	return _only.is_empty() or _only.has(id)
