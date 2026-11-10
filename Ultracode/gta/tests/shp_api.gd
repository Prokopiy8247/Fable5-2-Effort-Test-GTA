extends Node
## ECONOMY A (shops) API + behaviour test, headless, against the REAL player, inventory, world, city,
## pickups, peds (when enabled) and UI screens.
##   tools\godot.ps1 -Mode headless -Frames 4000 -TimeoutSec 260 -UserArgs '--test=shp_api','--test-timeout=220','--disable=traffic,police,emergency,wildlife,vehicles,props,radio,ambience,garage,transit,taxi,activities,respawn,debug'
##   add '--shp_real_only' to run only the real-clerk hold-up (needs the peds system)
## Covers: shop defs + interactables at valid positions, the interactable -> screen path, weapon /
## ammo / armour / attachment purchases (money, inventory, stats), the workbench screen, clothing /
## wardrobe / barber purchases (appearance + owned set), a SaveSystem round trip, healing items,
## parachute / scuba, real keyboard events on a screen (E tab, ui_down, Enter, Esc), free_shopping,
## the robbery flow with a dummy clerk (real aim path first, forced threat as a logged fallback) and,
## with peds enabled, a real "shop_staff" clerk at the Staff marker robbed through the real aim path.

const Catalog := preload("res://gta/code/world/shops/shop_catalog.gd")
const SAVE_SLOT := "shp_api_test"


class DummyStaff:
	extends Node3D
	var is_dead: bool = false
	var surrendered: int = 0
	var cowered: int = 0

	func surrender() -> void:
		surrendered += 1

	func cower() -> void:
		cowered += 1

	func get_target_position() -> Vector3:
		return global_position + Vector3(0.0, 1.25, 0.0)


var _purchases: Array = []
var _crimes: Array = []
var _appearance_events: int = 0
var T = TestHarness


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.item_purchased.connect(func(k: String, id: String, p: int) -> void: _purchases.append([k, id, p]))
	EventBus.crime_committed.connect(func(c: String, _pos: Vector3, _i: Node) -> void: _crimes.append(c))
	EventBus.player_appearance_changed.connect(func(_a: Dictionary) -> void: _appearance_events += 1)
	await T.wait_frames(30)
	await _run()
	SaveSystem.delete_save(SAVE_SLOT)
	T.finish()


func _run() -> void:
	var shops := Game.get_system("shops")
	T.check(shops != null, "shops system registered")
	if shops == null or not Game.has_player():
		T.log_line("SKIP: no shops system or no player")
		return
	var pl := Game.player
	var inv := Catalog.inventory()
	T.check(inv != null, "player has a WeaponInventory")
	if inv == null:
		return
	if OS.get_cmdline_user_args().has("--shp_real_only"):
		inv.call("give_weapon", "pistol", 48)
		await _check_real_staff(shops, inv, pl)
		return
	await _check_layout(shops)
	await _check_interactable_path(shops)
	Game.set_money(60000)
	await _check_weapons(inv)
	await _check_weapon_screen(inv)
	await _check_clothing()
	await _check_barber()
	await _check_save_load(shops, inv)
	await _check_items(pl)
	await _check_keyboard(pl)
	await _check_free_shopping(inv)
	await _check_robbery(shops, inv, pl)


# --- layout ----------------------------------------------------------------------------------

func _check_layout(shops: Node) -> void:
	for id: String in ["bay_arms", "tide_threads", "harbor_cuts", "corner_24"]:
		T.check(Registry.has_def("shops", id), "Registry shops has %s" % id)
	T.check(Registry.count("shop_items") >= 12, "Registry shop_items: %d items" % Registry.count("shop_items"))
	var its: Array = shops.call("get_interactables")
	T.check(its.size() >= 7, "%d shop / wardrobe interactables" % its.size())
	var bad := 0
	for it: Variant in its:
		var n := it as Interactable
		if n == null or not n.is_inside_tree() or not n.is_in_group("interactable"):
			bad += 1
			continue
		var p := n.global_position
		var ground := Game.ground_height(p.x, p.z)
		if not p.is_finite() or absf(p.x) > 300.0 or absf(p.z) > 300.0 or absf(p.y - ground) > 3.5:
			bad += 1
			T.log_line("bad interactable %s at %s (ground %.2f)" % [n.name, str(p), ground])
	T.check(bad == 0, "every interactable is in the tree, in group 'interactable', on the island near the ground")
	for id: String in ["bay_arms", "tide_threads", "harbor_cuts", "corner_24"]:
		var st: Dictionary = shops.call("get_shop_state", id)
		var def := Catalog.shop_def(id)
		var loc := Game.get_location(str(def.get("landmark", "")))
		var far := 0.0
		for u: Dictionary in st.get("uses", []):
			far = maxf(far, (u["position"] as Vector3).distance_to(loc.origin))
		T.check(not st.is_empty() and far < 30.0, "%s: %d use points within %.1f m of '%s' (source %s)" % [id,
				(st.get("uses", []) as Array).size(), far, str(def.get("landmark", "")), str(st.get("source", "?"))])
	var locs: Array = shops.call("get_shop_locations")
	var ok := locs.size() >= 4
	for l: Dictionary in locs:
		ok = ok and (l["position"] as Vector3).is_finite() and str(l["display_name"]) != ""
	T.check(ok, "get_shop_locations(): %d entries with names and positions" % locs.size())


func _check_interactable_path(shops: Node) -> void:
	var its: Array = shops.call("get_interactables", "corner_24")
	if its.is_empty():
		T.check(false, "corner_24 has an interactable")
		return
	var it := its[0] as Interactable
	Game.player.call("teleport", it.global_position - Vector3(0.0, 0.9, 0.0), 0.0)
	await T.wait_frames(6)
	T.check(it.can_interact(Game.player), "player standing at the Corner 24 counter can interact ('%s')" % it.prompt)
	it.interact(Game.player)
	await T.wait_frames(4)
	T.check(UI.is_screen_open("shop_general"), "interacting opens the general store screen")
	T.check(Game.is_input_locked(), "the shop screen locks gameplay input")
	UI.close_screen("shop_general")
	await T.wait_frames(4)
	T.check(not Game.is_input_locked(), "closing the screen unlocks input")


# --- weapons ---------------------------------------------------------------------------------

func _check_weapons(inv: Node) -> void:
	if inv.call("has_weapon", "smg"):
		inv.call("remove_weapon", "smg")
	var m0 := Game.money
	var r := Catalog.buy_weapon("smg")
	T.check(bool(r["ok"]) and bool(inv.call("has_weapon", "smg")) and Game.money == m0 - Catalog.weapon_price("smg"),
			"buy SMG: owned, money -%d (%s)" % [Catalog.weapon_price("smg"), r["message"]])
	T.check(not _purchases.is_empty() and _purchases.back()[0] == "weapon" and _purchases.back()[1] == "smg",
			"EventBus.item_purchased(weapon, smg, price) emitted")
	m0 = Game.money
	r = Catalog.buy_weapon("smg")
	T.check(not bool(r["ok"]) and Game.money == m0, "buying an owned weapon is refused without charge")
	# ammo
	var info := Catalog.ammo_info("smg")
	inv.call("add_ammo", "smg", -10000)
	var res0 := int(inv.call("get_reserve", "smg"))
	m0 = Game.money
	r = Catalog.buy_ammo("smg", 1)
	T.check(bool(r["ok"]) and int(inv.call("get_reserve", "smg")) == res0 + int(info["pack"]) and Game.money == m0 - int(info["unit_price"]),
			"ammo pack: reserve %d -> %d, money -%d" % [res0, int(inv.call("get_reserve", "smg")), int(info["unit_price"])])
	r = Catalog.buy_ammo("smg", -1)
	T.check(bool(r["ok"]) and bool(inv.call("is_ammo_full", "smg")), "fill ammo: reserve full (%s)" % r["message"])
	m0 = Game.money
	r = Catalog.buy_ammo("smg", 1)
	T.check(not bool(r["ok"]) and Game.money == m0, "ammo refused when full, nothing charged ('%s')" % r["message"])
	# armour
	var pl := Game.player
	pl.set("armor", 0.0)
	m0 = Game.money
	r = Catalog.buy_item("armor_light")
	T.check(bool(r["ok"]) and absf(float(pl.get("armor")) - 50.0) < 0.1 and Game.money == m0 - 500,
			"Patrol Vest: armour 0 -> %d, money -500" % int(pl.get("armor")))
	pl.set("armor", float(pl.get("max_armor")))
	m0 = Game.money
	r = Catalog.buy_item("armor_heavy")
	T.check(not bool(r["ok"]) and Game.money == m0, "armour refused when full ('%s')" % r["message"])
	# attachments
	var noise0 := float((inv.call("get_spec", "smg") as Object).get("noise_radius"))
	m0 = Game.money
	r = Catalog.install_attachment("smg", "suppressor")
	var noise1 := float((inv.call("get_spec", "smg") as Object).get("noise_radius"))
	T.check(bool(r["ok"]) and bool(inv.call("has_attachment", "smg", "suppressor")) and Game.money == m0 - Catalog.attachment_price("suppressor"),
			"workbench: suppressor fitted, money -%d" % Catalog.attachment_price("suppressor"))
	T.check(noise1 < noise0 * 0.5, "suppressor changes the stats: noise radius %.0f -> %.0f m" % [noise0, noise1])
	var mag0 := int((inv.call("get_spec", "smg") as Object).get("mag_size"))
	Catalog.install_attachment("smg", "ext_mag")
	T.check(int((inv.call("get_spec", "smg") as Object).get("mag_size")) > mag0, "extended magazine: %d -> %d rounds" % [mag0, int((inv.call("get_spec", "smg") as Object).get("mag_size"))])
	r = Catalog.remove_attachment("smg", "suppressor")
	T.check(bool(r["ok"]) and not bool(inv.call("has_attachment", "smg", "suppressor")), "suppressor removed")
	m0 = Game.money
	r = Catalog.install_attachment("smg", "suppressor")
	T.check(bool(r["ok"]) and Game.money == m0, "refitting a bought attachment is free")
	Catalog.install_attachment("smg", "finish_teal")
	Catalog.install_attachment("smg", "finish_coral")
	var fitted := Catalog.fitted_attachments("smg")
	T.check(fitted.has("finish_coral") and not fitted.has("finish_teal"), "a new finish replaces the old one: %s" % str(fitted))
	r = Catalog.clear_finish("smg")
	T.check(bool(r["ok"]) and not Catalog.fitted_attachments("smg").has("finish_coral"), "factory finish restored")
	var after := Catalog.spec_with("smg", Catalog.preview_attachments("smg", "grip"))
	T.check(after != null and float(after.get("recoil_pitch")) < float((inv.call("get_spec", "smg") as Object).get("recoil_pitch")),
			"before/after preview spec: grip lowers recoil")


func _check_weapon_screen(inv: Node) -> void:
	var scr := UI.open_screen("shop_weapons", {"shop_id": "bay_arms"})
	T.check(scr != null, "weapon shop screen opens")
	if scr == null:
		return
	await T.wait_frames(3)
	var items: Array = scr.call("get_items")
	T.check(items.size() >= 2, "handgun tab lists %d rows" % items.size())
	if inv.call("has_weapon", "heavy_pistol"):
		inv.call("remove_weapon", "heavy_pistol")
	scr.call("_refill")
	var i := int(scr.call("find_index", "id", "heavy_pistol"))
	var m0 := Game.money
	var r: Dictionary = scr.call("activate_index", i) if i >= 0 else {}
	T.check(i >= 0 and bool(r.get("ok", false)) and bool(inv.call("has_weapon", "heavy_pistol")) and Game.money == m0 - Catalog.weapon_price("heavy_pistol"),
			"screen row 'Brimstone .50' buys the weapon (%s)" % str(r.get("message", "")))
	i = int(scr.call("find_index", "id", "heavy_pistol"))
	T.check(i >= 0 and str((scr.call("get_items")[i] as Dictionary).get("kind")) == "ammo", "the owned weapon's row now sells ammunition")
	UI.close_screen("shop_weapons")
	await T.wait_frames(3)
	scr = UI.open_screen("shop_weapons", {"shop_id": "bay_arms", "page": "workbench"})
	await T.wait_frames(3)
	items = scr.call("get_items")
	i = int(scr.call("find_index", "id", "smg"))
	T.check(i >= 0, "workbench lists the owned SMG (%d firearms)" % items.size())
	if i >= 0:
		scr.call("activate_index", i)
		await T.wait_frames(3)
		var parts: Array = scr.call("get_items")
		var g := int(scr.call("find_index", "id", "grip"))
		T.check(parts.size() >= 6 and g >= 0, "SMG parts list: %d rows incl. grip" % parts.size())
		if g >= 0:
			scr.call("select_index", g)
			await T.wait_frames(2)
			var pv: Variant = scr.get("_preview")
			if pv != null:
				T.check(bool((pv as Object).call("has_content")), "workbench 3D preview shows the weapon model")
			m0 = Game.money
			var rr: Dictionary = scr.call("activate_index", g)
			T.check(bool(rr.get("ok", false)) and bool(inv.call("has_attachment", "smg", "grip")) and Game.money == m0 - Catalog.attachment_price("grip"),
					"workbench screen fits the grip (%s)" % str(rr.get("message", "")))
		T.check(bool(scr.call("handle_back")), "Esc on the parts list goes back to the weapon list")
	UI.close_screen("shop_weapons")
	await T.wait_frames(3)


# --- clothing / barber -----------------------------------------------------------------------

func _check_clothing() -> void:
	var w := Catalog.wardrobe()
	T.check(w != null, "wardrobe store exists")
	var a0 := Catalog.player_appearance()
	T.check(Catalog.owns_clothing("top_" + str(a0.get("top", "tee"))) or str(a0.get("outfit", "")) != "",
			"wardrobe seeded with the worn top (%s)" % str(a0.get("top", "")))
	var def: Dictionary = Registry.get_def("clothing", "top_hoodie")
	var col := str((def["colors"] as Array)[4])
	var m0 := Game.money
	var ev0 := _appearance_events
	var r := Catalog.buy_clothing("top_hoodie", col)
	var a1 := Catalog.player_appearance()
	T.check(bool(r["ok"]) and str(a1.get("top")) == "hoodie" and str(a1.get("top_color")).to_lower() == col.to_lower()
			and Game.money == m0 - int(def["price"]), "buy Bay Hoodie in %s: worn, money -%d" % [col, int(def["price"])])
	T.check(_appearance_events > ev0, "EventBus.player_appearance_changed emitted")
	T.check(Catalog.owns_clothing("top_hoodie"), "the hoodie is in the wardrobe")
	# clothing screen path
	var scr := UI.open_screen("shop_clothing", {"shop_id": "tide_threads"})
	await T.wait_frames(3)
	var i := int(scr.call("find_index", "id", "top_shirt"))
	if i >= 0:
		scr.call("select_index", i)
		scr.call("select_color", 2)
		await T.wait_frames(2)
		var c := str(scr.call("get_color"))
		m0 = Game.money
		var rr: Dictionary = scr.call("activate_index", i)
		var a2 := Catalog.player_appearance()
		T.check(bool(rr.get("ok", false)) and str(a2.get("top")) == "shirt" and str(a2.get("top_color")).to_lower() == c.to_lower(),
				"clothing screen: Button-Up Shirt bought in colour %s" % c)
		var pv: Variant = scr.get("_preview")
		T.check(pv != null and bool((pv as Object).call("has_content")), "clothing store preview clone exists")
	else:
		T.check(false, "clothing screen lists top_shirt")
	UI.close_screen("shop_clothing")
	await T.wait_frames(2)
	# wardrobe: only owned, wearing is free
	scr = UI.open_screen("wardrobe", {})
	await T.wait_frames(3)
	var rows: Array = scr.call("get_items")
	var only_owned := not rows.is_empty()
	for row: Dictionary in rows:
		only_owned = only_owned and Catalog.owns_clothing(str(row["id"]))
	T.check(only_owned, "wardrobe lists only owned tops (%d)" % rows.size())
	i = int(scr.call("find_index", "id", "top_hoodie"))
	m0 = Game.money
	var rw: Dictionary = scr.call("activate_index", i) if i >= 0 else {}
	T.check(bool(rw.get("ok", false)) and str(Catalog.player_appearance().get("top")) == "hoodie" and Game.money == m0,
			"wardrobe: hoodie worn again for free")
	UI.close_screen("wardrobe")
	await T.wait_frames(2)


func _check_barber() -> void:
	var m0 := Game.money
	var r := Catalog.buy_haircut("hair_buzz", "#d9b56a")
	var a := Catalog.player_appearance()
	var expected := Catalog.price(int((Registry.get_def("hair", "hair_buzz") as Dictionary)["price"])) + Catalog.COLOUR_FEE
	T.check(bool(r["ok"]) and str(a.get("hair")) == "buzz" and str(a.get("hair_color")).to_lower() == "#d9b56a",
			"barber: buzz cut, blond (%s)" % r["message"])
	T.check(Game.money == m0 - expected, "haircut + colour cost %d" % expected)
	r = Catalog.buy_haircut("hair_buzz", "#d9b56a")
	T.check(not bool(r["ok"]), "same look again is refused ('%s')" % r["message"])
	var scr := UI.open_screen("shop_barber", {"shop_id": "harbor_cuts"})
	await T.wait_frames(3)
	var i := int(scr.call("find_index", "id", "hair_curly"))
	var rr: Dictionary = scr.call("activate_index", i) if i >= 0 else {}
	T.check(bool(rr.get("ok", false)) and str(Catalog.player_appearance().get("hair")) == "curly", "barber screen: curls cut")
	scr.call("select_tab", 1)
	await T.wait_frames(2)
	T.check((scr.call("get_items") as Array).size() >= 1, "beard tab lists %d rows" % (scr.call("get_items") as Array).size())
	UI.close_screen("shop_barber")
	await T.wait_frames(2)


# --- save / load -----------------------------------------------------------------------------

func _check_save_load(shops: Node, _inv: Node) -> void:
	var look := Catalog.player_appearance()
	var owned: Array = Catalog.wardrobe().call("get_owned")
	T.check(SaveSystem.save_game(SAVE_SLOT), "save game written")
	Catalog.apply_player_appearance({"top": "tank", "hair": "long", "hair_color": "#e6e2d8"})
	Catalog.wardrobe().call("clear")
	shops.set("unlocked_attachments", {})
	T.check(str(Catalog.player_appearance().get("top")) == "tank", "appearance changed before loading")
	T.check(SaveSystem.load_game(SAVE_SLOT), "save game loaded")
	await T.wait_frames(5)
	var a := Catalog.player_appearance()
	T.check(str(a.get("top")) == str(look.get("top")) and str(a.get("hair")) == str(look.get("hair"))
			and str(a.get("hair_color")).to_lower() == str(look.get("hair_color")).to_lower(),
			"appearance restored by load (top %s, hair %s)" % [str(a.get("top")), str(a.get("hair"))])
	var owned2: Array = Catalog.wardrobe().call("get_owned")
	owned.sort()
	owned2.sort()
	T.check(owned2 == owned and owned2.has("top_hoodie"), "wardrobe owned set restored (%d items)" % owned2.size())
	T.check(bool(shops.call("is_attachment_unlocked", "smg", "suppressor")), "workbench unlocks restored")


# --- general store ---------------------------------------------------------------------------

func _check_items(pl: Node3D) -> void:
	pl.set("health", 40.0)
	var m0 := Game.money
	var r := Catalog.buy_item("medkit")
	T.check(bool(r["ok"]) and float(pl.get("health")) >= float(pl.get("max_health")) - 0.5 and Game.money == m0 - 120,
			"First Aid Kit heals 40 -> %d, money -120" % int(pl.get("health")))
	m0 = Game.money
	r = Catalog.buy_item("snack_chips")
	T.check(not bool(r["ok"]) and Game.money == m0, "food refused at full health ('%s')" % r["message"])
	pl.set("health", 50.0)
	r = Catalog.buy_item("snack_burrito")
	T.check(bool(r["ok"]) and absf(float(pl.get("health")) - 85.0) < 0.6, "burrito heals 50 -> %d" % int(pl.get("health")))
	pl.set("has_parachute", false)
	r = Catalog.buy_item("parachute")
	T.check(bool(r["ok"]) and bool(pl.get("has_parachute")), "Glide Pack sets player.has_parachute")
	r = Catalog.buy_item("parachute")
	T.check(not bool(r["ok"]), "second parachute refused")
	if "has_scuba" in pl:
		pl.set("has_scuba", false)
	r = Catalog.buy_item("scuba_kit")
	T.check(bool(r["ok"]) and bool(pl.get("has_scuba")), "Scuba Kit sets the scuba flag")
	# screen path
	pl.set("health", 30.0)
	var scr := UI.open_screen("shop_general", {"shop_id": "corner_24", "tab": 2})
	await T.wait_frames(3)
	var i := int(scr.call("find_index", "id", "bandage"))
	m0 = Game.money
	var rr: Dictionary = scr.call("activate_index", i) if i >= 0 else {}
	T.check(bool(rr.get("ok", false)) and absf(float(pl.get("health")) - 70.0) < 0.6 and Game.money == m0 - 45,
			"general store screen: bandage heals 30 -> %d" % int(pl.get("health")))
	UI.close_screen("shop_general")
	await T.wait_frames(2)


func _send_action(action: String) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await T.wait_frames(2)


func _send_key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await T.wait_frames(2)


## Real input events: E switches the tab, ui_down moves, ui_accept buys, Esc closes.
func _check_keyboard(pl: Node3D) -> void:
	pl.set("health", 30.0)
	var scr := UI.open_screen("shop_general", {"shop_id": "corner_24", "tab": 0})
	await T.wait_frames(4)
	await _send_key(KEY_E)
	T.check(int(scr.call("get_tab")) == 1, "key E switches to the DRINKS tab")
	var row0 := scr.call("get_selected_item") as Dictionary
	await _send_action("ui_down")
	var row1 := scr.call("get_selected_item") as Dictionary
	T.check(str(row1.get("id", "")) != str(row0.get("id", "")), "ui_down moves the selection (%s -> %s)" % [row0.get("id"), row1.get("id")])
	var m0 := Game.money
	var price := Catalog.price(int(Catalog.item_def(str(row1.get("id", ""))).get("price", 0)))
	await _send_action("ui_accept")
	T.check(Game.money == m0 - price and price > 0, "ui_accept (Enter) buys %s for %d" % [row1.get("id"), price])
	await _send_action("pause")
	await T.wait_frames(3)
	T.check(not UI.is_screen_open("shop_general"), "Esc closes the shop screen")


func _check_free_shopping(inv: Node) -> void:
	Game.flags["free_shopping"] = true
	if inv.call("has_weapon", "carbine"):
		inv.call("remove_weapon", "carbine")
	var m0 := Game.money
	var r := Catalog.buy_weapon("carbine")
	T.check(bool(r["ok"]) and bool(inv.call("has_weapon", "carbine")) and Game.money == m0, "free_shopping: carbine for $0")
	T.check(_purchases.back()[2] == 0, "item_purchased reports price 0")
	r = Catalog.install_attachment("carbine", "scope")
	T.check(bool(r["ok"]) and Game.money == m0, "free_shopping: optic fitted for $0")
	var scr := UI.open_screen("shop_weapons", {"shop_id": "bay_arms"})
	await T.wait_frames(2)
	var any_paid := false
	for row: Dictionary in scr.call("get_items"):
		if int(row.get("price", 0)) > 0:
			any_paid = true
	T.check(not any_paid, "free_shopping: every listed price is 0")
	UI.close_screen("shop_weapons")
	Game.flags.erase("free_shopping")
	await T.wait_frames(2)


# --- robbery ---------------------------------------------------------------------------------

## Turns the gameplay camera so the player's aim ray passes through `target` (what a player does
## with the mouse). Camera yaw 0 looks along -Z, + = left; pitch + = up.
func _aim_at(pl: Node3D, target: Vector3) -> void:
	var rig := Game.camera_rig
	if rig == null or not pl.has_method("get_aim_ray"):
		return
	var ray: Dictionary = pl.call("get_aim_ray")
	var w := (target - (ray["origin"] as Vector3)).normalized()
	var d := (ray["direction"] as Vector3).normalized()
	var want_yaw := atan2(-w.x, -w.z)
	var have_yaw := atan2(-d.x, -d.z)
	rig.set("yaw", float(rig.get("yaw")) + wrapf(want_yaw - have_yaw, -PI, PI))
	rig.set("pitch", float(rig.get("pitch")) + (asin(clampf(w.y, -1.0, 1.0)) - asin(clampf(d.y, -1.0, 1.0))))


func _check_robbery(shops: Node, inv: Node, pl: Node3D) -> void:
	var st: Dictionary = shops.call("get_shop_state", "corner_24")
	var dummy := DummyStaff.new()
	dummy.name = "DummyClerk"
	Game.get_entities_root().add_child(dummy)
	dummy.global_position = st["staff_position"]
	T.check(bool(shops.call("register_staff", "corner_24", dummy)), "dummy clerk registered for Corner 24")
	var counter: Vector3 = ((st["uses"] as Array)[0] as Dictionary)["position"]
	var to := dummy.global_position - counter
	to.y = 0.0
	var stand := dummy.global_position - to.normalized() * clampf(to.length(), 2.0, 4.0)
	stand.y = counter.y - 0.9
	var yaw := atan2(-to.x, -to.z)
	pl.call("teleport", stand, yaw)
	await T.wait_frames(4)
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		Game.camera_rig.call("snap_to", yaw)
		Game.camera_rig.set("pitch", 0.0)
	inv.call("give_weapon", "pistol", 48)
	inv.call("equip", "pistol")
	var money0 := Game.money
	var pickups0 := 0
	var pk := Game.get_system("pickups")
	if pk != null and pk.has_method("get_pickup_count"):
		pickups0 = int(pk.call("get_pickup_count"))
	var crimes0 := _crimes.count("robbery")
	await T.wait_seconds(0.8)
	Input.action_press("aim")
	var real_path := false
	for k in 70:
		await T.wait_seconds(0.1)
		_aim_at(pl, dummy.get_target_position())
		if not bool(shops.call("is_open", "corner_24")):
			real_path = true
			break
	Input.action_release("aim")
	if real_path:
		T.check(true, "robbery through the REAL aim path: aiming the pistol at the clerk for ~3 s")
	else:
		T.log_line("real aim path did not trigger (aiming=%s, progress %.2f) - forcing the threat" % [str(pl.get("is_aiming")),
				float(shops.call("get_robbery_progress", "corner_24"))])
		(shops.get("debug_force_threat") as Dictionary)["corner_24"] = true
		await T.wait_seconds(3.6)
		(shops.get("debug_force_threat") as Dictionary).erase("corner_24")
		T.log_line("NOTE: robbery completed via forced threat - the real aim path is NOT verified in this run")
	await T.wait_frames(4)
	T.check(dummy.surrendered > 0, "the clerk surrendered while threatened")
	T.check(dummy.cowered > 0, "the clerk cowers after handing over the till")
	T.check(not bool(shops.call("is_open", "corner_24")), "Corner 24 closed after the robbery")
	T.check(_crimes.count("robbery") > crimes0, "Wanted.report_crime('robbery') reached EventBus.crime_committed")
	var pickups1 := int(pk.call("get_pickup_count")) if pk != null and pk.has_method("get_pickup_count") else 0
	T.check(pickups1 > pickups0 or Game.money > money0, "cash handed over (pickups %d -> %d, money %d -> %d)" % [pickups0, pickups1, money0, Game.money])
	var scr: Variant = shops.call("open_shop", "corner_24", 0)
	await T.wait_frames(2)
	T.check(scr == null and not UI.is_screen_open("shop_general"), "a closed shop does not open its screen")
	shops.call("reopen_shop", "corner_24")
	T.check(bool(shops.call("is_open", "corner_24")), "reopen_shop() opens it again")
	shops.call("unregister_staff", "corner_24")
	dummy.queue_free()
	await T.wait_frames(2)
	await _check_real_staff(shops, inv, pl)


## Only when the AI module's peds system runs: the real "shop_staff" clerk and a real hold-up.
func _check_real_staff(shops: Node, inv: Node, pl: Node3D) -> void:
	if Game.get_system("peds") == null:
		T.log_line("SKIP real clerk: no peds system in this run (run again without --disable=peds)")
		return
	var st: Dictionary = shops.call("get_shop_state", "bay_arms")
	var staff_pos: Vector3 = st["staff_position"]
	var counter: Vector3 = ((st["uses"] as Array)[0] as Dictionary)["position"] - Vector3(0.0, 0.9, 0.0)
	var to := staff_pos - counter
	to.y = 0.0
	var yaw := atan2(-to.x, -to.z)
	pl.call("teleport", counter - to.normalized() * 0.4, yaw)
	var clerk: Node3D = null
	for k in 40:
		await T.wait_seconds(0.1)
		clerk = shops.call("get_staff", "bay_arms")
		if clerk != null:
			break
	T.check(clerk != null, "a real clerk spawned at Bay Arms when the player came close")
	if clerk == null:
		return
	T.check(clerk.is_in_group("shop_staff") and str(clerk.get("faction")) == "staff",
			"clerk: group shop_staff, faction '%s', archetype '%s'" % [str(clerk.get("faction")), str(clerk.get("archetype_id"))])
	T.check(clerk.global_position.distance_to(staff_pos) < 1.5, "clerk stands at the Staff marker (%.2f m)" % clerk.global_position.distance_to(staff_pos))
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		Game.camera_rig.call("snap_to", yaw)
	inv.call("equip", "pistol")
	var crimes0 := _crimes.count("robbery")
	await T.wait_seconds(0.6)
	Input.action_press("aim")
	var robbed := false
	var tags: Dictionary = {}
	for k in 80:
		await T.wait_seconds(0.1)
		if is_instance_valid(clerk):
			_aim_at(pl, clerk.call("get_target_position") if clerk.has_method("get_target_position") else clerk.global_position + Vector3(0, 1.25, 0))
		if is_instance_valid(clerk):
			tags[str(clerk.get("state_tag"))] = true
			if k % 5 == 0:
				var ray: Dictionary = pl.call("get_aim_ray")
				var tp: Vector3 = clerk.call("get_target_position") if clerk.has_method("get_target_position") else clerk.global_position
				var d: Vector3 = (ray["direction"] as Vector3).normalized()
				var rel: Vector3 = tp - (ray["origin"] as Vector3)
				T.log_line("t=%.1f aiming=%s progress=%.2f dist=%.2f perp=%.2f tag=%s" % [k * 0.1, str(pl.get("is_aiming")),
						float(shops.call("get_robbery_progress", "bay_arms")), pl.global_position.distance_to(tp),
						(rel - d * rel.dot(d)).length(), str(clerk.get("state_tag"))])
		if not bool(shops.call("is_open", "bay_arms")):
			robbed = true
			break
	Input.action_release("aim")
	T.check(robbed, "real hold-up: aiming at the real clerk robs Bay Arms (clerk states seen: %s)" % str(tags.keys()))
	T.check(_crimes.count("robbery") > crimes0, "real hold-up reported as 'robbery'")
	shops.call("reopen_shop", "bay_arms")
