extends Node
## ECONOMY A (shops) screenshots, windowed, short: every shop screen open over the real world.
##   tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 120 -UserArgs '--test=shp_shots','--disable=traffic,peds,police,emergency,wildlife,vehicles,props,radio,ambience,garage,transit,taxi,activities,respawn,debug'
## Optional '--shp_only=weapons,workbench,armour,clothing,wardrobe,barber,general,counter' to take some shots.
## Output: qa/screenshots/shp_<name>.png

const Catalog := preload("res://gta/code/world/shops/shop_catalog.gd")

var _only: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shp_only="):
			_only = a.substr(11).split(",", false)
	await TestHarness.wait_frames(45)
	await _run()
	TestHarness.finish()


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _run() -> void:
	var T := TestHarness
	var shops := Game.get_system("shops")
	var inv := Catalog.inventory()
	T.check(shops != null and Game.has_player() and inv != null, "shops, player and inventory present")
	if shops == null or inv == null:
		return
	Game.set_money(18450)
	for w: String in ["pistol", "smg", "assault_rifle", "pump_shotgun", "bat"]:
		inv.call("give_weapon", w, -1)
	Game.flags["free_shopping"] = true
	Catalog.install_attachment("assault_rifle", "suppressor")
	Catalog.install_attachment("assault_rifle", "grip")
	Catalog.install_attachment("assault_rifle", "finish_sand")
	Catalog.install_attachment("smg", "ext_mag")
	Game.flags.erase("free_shopping")
	Game.player.set("armor", 35.0)
	Game.player.set("health", 62.0)

	if _want("counter"):
		var st: Dictionary = shops.call("get_shop_state", "bay_arms")
		var uses: Array = st.get("uses", [])
		if not uses.is_empty():
			var p: Vector3 = (uses[0] as Dictionary)["position"]
			var staff: Vector3 = st["staff_position"]
			var to := staff - p
			var yaw := atan2(-to.x, -to.z)
			Game.player.call("teleport", p - Vector3(0.0, 0.9, 0.0) - Vector3(to.x, 0.0, to.z).normalized() * 0.8, yaw)
			if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
				Game.camera_rig.call("snap_to", yaw + 0.35)
			await T.wait_seconds(1.2)
			await T.shot("shp_counter")

	if _want("weapons"):
		var scr := UI.open_screen("shop_weapons", {"shop_id": "bay_arms", "tab": 4})
		await T.wait_seconds(0.3)
		var i := int(scr.call("find_index", "id", "carbine"))
		if i >= 0:
			scr.call("select_index", i)
		await T.wait_seconds(0.7)
		await T.shot("shp_weapons")
		if _want("armour"):
			scr.call("select_tab", 8)
			await T.wait_seconds(0.8)
			await T.shot("shp_armour")
		UI.close_screen("shop_weapons")
		await T.wait_frames(3)

	if _want("workbench"):
		var scr2 := UI.open_screen("shop_weapons", {"shop_id": "bay_arms", "page": "workbench"})
		await T.wait_seconds(0.2)
		var i2 := int(scr2.call("find_index", "id", "assault_rifle"))
		if i2 >= 0:
			scr2.call("activate_index", i2)
			await T.wait_seconds(0.2)
			var s := int(scr2.call("find_index", "id", "scope"))
			if s >= 0:
				scr2.call("select_index", s)
		await T.wait_seconds(0.8)
		await T.shot("shp_workbench")
		UI.close_screen("shop_weapons")
		await T.wait_frames(3)

	if _want("clothing"):
		var scr3 := UI.open_screen("shop_clothing", {"shop_id": "tide_threads"})
		await T.wait_seconds(0.2)
		var i3 := int(scr3.call("find_index", "id", "top_hoodie"))
		if i3 >= 0:
			scr3.call("select_index", i3)
			scr3.call("select_color", 5)
		await T.wait_seconds(0.9)
		await T.shot("shp_clothing")
		UI.close_screen("shop_clothing")
		await T.wait_frames(3)

	if _want("wardrobe"):
		var scr4 := UI.open_screen("wardrobe", {"tab": 3})
		await T.wait_seconds(0.9)
		await T.shot("shp_wardrobe")
		UI.close_screen("wardrobe")
		await T.wait_frames(3)

	if _want("barber"):
		var scr5 := UI.open_screen("shop_barber", {"shop_id": "harbor_cuts"})
		await T.wait_seconds(0.2)
		var i5 := int(scr5.call("find_index", "id", "hair_curly"))
		if i5 >= 0:
			scr5.call("select_index", i5)
			scr5.call("select_color", 9)
		await T.wait_seconds(0.9)
		await T.shot("shp_barber")
		UI.close_screen("shop_barber")
		await T.wait_frames(3)

	if _want("general"):
		var scr6 := UI.open_screen("shop_general", {"shop_id": "corner_24", "tab": 3})
		await T.wait_seconds(0.2)
		var i6 := int(scr6.call("find_index", "id", "parachute"))
		if i6 >= 0:
			scr6.call("select_index", i6)
		await T.wait_seconds(0.9)
		await T.shot("shp_general")
		scr6.call("select_tab", 0)
		await T.wait_seconds(0.6)
		await T.shot("shp_general_food")
		UI.close_screen("shop_general")
		await T.wait_frames(3)
