extends Node
## UI integration test against the REAL player, inventory and world (no fakes).
##   tools\godot.ps1 -Mode headless -Frames 900 -UserArgs '--test=ui_live','--disable=traffic,peds,police'
##   tools\godot.ps1 -Mode window  -Frames 420 -UserArgs '--test=ui_live','--disable=traffic,peds,police'   (adds 4 PNGs)
## Skips (with a log line) whatever module is not there yet instead of failing on it.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await TestHarness.wait_frames(40)
	await _run()
	TestHarness.finish()


func _action(action: String, pressed: bool = true) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await TestHarness.wait_frames(3)


func _run() -> void:
	var T := TestHarness
	var hud := UI.hud as HudRoot
	T.check(hud != null and hud.visible, "HUD visible in a real session")
	if hud == null:
		return
	if not Game.has_player():
		T.log_line("SKIP: no player in this run")
		return
	var pl := Game.player
	var st := hud.get_state()
	T.check(is_equal_approx(float(st["health"]), UiKit.num(pl, &"health", -1.0)), "HUD health equals player.health (%.0f)" % float(st["health"]))
	T.check(int(st["money"]) == Game.money, "HUD money equals Game.money")
	T.check(str(st["time"]) == WorldClock.get_time_string() or str(st["time"]) != "", "HUD clock shows %s" % str(st["time"]))

	# --- world: minimap data, district, places, GPS route --------------------------------------
	if Game.world != null:
		var md := UI.map_data
		T.check(md.source == "world" and md.roads.size() > 10, "minimap uses World.get_minimap_data() (%d roads, %d lots, %d places)" % [md.roads.size(), md.lots.size(), md.places.size()])
		T.check(not md.coast.is_empty() and md.places.size() > 5, "coast polygon and named places present")
		await T.wait_frames(40)
		T.check(str(hud.get_state()["district"]) != "", "district shown: '%s'" % str(hud.get_state()["district"]))
		var layer := hud.minimap.get_node("Clip").get_child(0) as MinimapWorldLayer
		if not T.is_headless():
			T.check(layer.get_triangle_count() > 1000, "minimap mesh baked (%d triangles, 1 draw call)" % layer.get_triangle_count())
		var target: Vector3 = Game.get_location("gun_shop").origin
		UI.set_waypoint(target)
		T.check(UI.has_waypoint() and UI.nav.route.size() >= 2, "waypoint to the gun shop: route of %d points, %d m" % [UI.nav.route.size(), int(UI.nav.route_length)])
		var straight := Vector2(target.x - pl.global_position.x, target.z - pl.global_position.z).length()
		T.check(UI.nav.route_length >= straight * 0.95, "route length (%d m) is at least the straight distance (%d m)" % [int(UI.nav.route_length), int(straight)])
	else:
		T.log_line("SKIP: no world system in this run")

	# --- real inventory: weapon card, wheel data, equip on release ---------------------------------
	var inv: Variant = pl.get(&"inventory")
	if inv is Object and is_instance_valid(inv) and (inv as Object).has_method("give_weapon"):
		var io := inv as Object
		io.call("give_weapon", "pistol")
		io.call("give_weapon", "assault_rifle")
		io.call("give_weapon", "pump_shotgun")
		io.call("give_weapon", "grenade")
		io.call("equip", "pistol")
		await T.wait_frames(40)
		st = hud.get_state()
		T.check(str(st["weapon_id"]) == "pistol" and bool(st["weapon_shown"]) and int(st["in_mag"]) >= 0,
				"weapon card shows the real pistol '%s' %d / %d" % [hud.weapon.weapon_name, int(st["in_mag"]), int(st["reserve"])])
		T.check(int(st["crosshair_style"]) == 2, "spread crosshair with a firearm (spread %.2f deg)" % hud.crosshair.spread_deg)
		await T.shot("ui_live_hud")
		await _action("weapon_wheel", true)
		var wheel := UI.get_screen("weapon_wheel")
		T.check(wheel != null and is_equal_approx(Engine.time_scale, 0.15), "Tab opens the wheel in slow motion")
		if wheel != null:
			T.check(int(wheel.call("get_hovered_slot")) == 1, "wheel starts on the slot of the weapon in hand (handgun)")
			var rifles: Array = wheel.call("get_slot_weapons", 4)
			T.check(rifles.has("assault_rifle"), "wheel lists the real inventory (rifle slot: %s)" % str(rifles))
			wheel.call("set_pointer", Vector2(0, 120))
			T.check(str(wheel.call("get_hovered_weapon")) == "assault_rifle", "pointing down highlights the assault rifle")
			await T.wait_frames(6)
			await T.shot("ui_live_wheel")
		await _action("weapon_wheel", false)
		await T.wait_frames(50)
		T.check(not UI.is_screen_open("weapon_wheel") and is_equal_approx(Engine.time_scale, 1.0), "releasing Tab closes the wheel")
		T.check(UiKit.text_of(io, &"current_id") == "assault_rifle", "the inventory equipped the highlighted weapon (%s)" % UiKit.text_of(io, &"current_id"))
		T.check(str(hud.get_state()["weapon_id"]) == "assault_rifle", "weapon card follows the real equip (%s)" % hud.weapon.weapon_name)
	else:
		T.log_line("SKIP: player has no WeaponInventory in this run")

	# --- menus on top of a live session --------------------------------------------------------------
	var lock0 := Game.input_locked
	await _action("pause")
	T.check(UI.is_screen_open("pause") and get_tree().paused, "Esc pauses the live game")
	await T.wait_frames(8)
	await T.shot("ui_live_pause")
	await _action("map")
	await T.wait_frames(8)
	await T.shot("ui_live_map")
	await _action("pause")
	await _action("pause")
	T.check(not UI.is_screen_open("") and not get_tree().paused and Game.input_locked == lock0, "back out: unpaused, input lock restored (%d)" % Game.input_locked)
	UI.clear_waypoint()
