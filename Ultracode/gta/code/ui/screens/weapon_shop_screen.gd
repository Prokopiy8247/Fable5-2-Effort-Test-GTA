extends "res://gta/code/world/shops/shop_screen_base.gd"
## Bay Arms - weapon shop + workbench (ECONOMY A, spec 17A / 25, ARCHITECTURE_WAVE2 W2.6).
##   UI.open_screen("shop_weapons", {"shop_id": "bay_arms", "page": "shop" | "workbench", "tab": int})
##
## SHOP: categories by weapon-wheel slot (+ ARMOUR, WORKBENCH). A weapon you do not own is bought
## (Enter); an owned weapon offers its ammunition: Enter = one pack, R = fill the reserve. Armour
## vests come from Registry "shop_items". Stats of the highlighted weapon as bars, 3D preview of the
## Blender model with the attachments you have fitted.
## WORKBENCH: owned firearms -> their compatible attachments (suppressor, optic, light, grip,
## extended magazine) and finish tints. The highlighted part is previewed on the model and in the
## stat bars (before -> after). Enter fits it (paid once - removed parts stay unlocked on the bench),
## Enter on a fitted part removes it. Prices: WeaponSpec / AttachmentSpec (weapons_registry.gd).

const TABS := [
	["melee", "Melee"], ["handgun", "Pistol"], ["smg", "SMG"], ["shotgun", "Shotgun"], ["rifle", "Rifle"],
	["sniper", "Sniper"], ["heavy", "Heavy"], ["thrown", "Thrown"], ["armour", "Armour"], ["workbench", "Workbench"],
]
const SLOT_ICONS := {"melee": &"bat", "handgun": &"handgun", "smg": &"smg", "shotgun": &"shotgun", "rifle": &"rifle",
	"sniper": &"sniper", "heavy": &"heavy", "thrown": &"grenade"}
const LIST_TITLES := {"melee": "Melee weapons", "handgun": "Pistols", "smg": "Submachine guns", "shotgun": "Shotguns",
	"rifle": "Rifles", "sniper": "Sniper rifles", "heavy": "Heavy weapons", "thrown": "Throwables"}
const KIND_NAMES := {"suppressor": "Suppressor", "scope": "Optic", "flashlight": "Weapon light", "grip": "Foregrip",
	"ext_mag": "Extended magazine", "finish": "Finish"}

var _tab_keys: Array = []
var _page: String = "shop"                 ## "shop" | "bench_weapons" | "bench_parts"
var _bench_weapon: String = ""
var _bench_from_tab: bool = false
var _bars: Control = null
var _primary_btn: Button = null


func _init() -> void:
	super()
	default_shop_id = "bay_arms"


func _ready() -> void:
	var names: Array = []
	for t: Array in TABS:
		_tab_keys.append(t[0])
		names.append(t[1])
	_build_layout("Bay Arms", "Firearms, ammunition, armour and a workbench", names, Vector2i(512, 250))


func open(args: Dictionary) -> void:
	_resolve_shop(args)
	_filter_tabs()
	if str(args.get("page", "shop")) == "workbench":
		_bench_from_tab = false
		_enter_bench()
	else:
		var start := int(args.get("tab", _first_stock_tab()))
		_tabs.select(clampi(start, 0, _tab_keys.size() - 1), false)
		_show_tab(_tabs.current)
	_list.grab()


func _hint_list() -> Array:
	match _page:
		"bench_weapons":
			return [{"keys": ["W", "S"], "text": "Navigate"}, {"key": "Enter", "text": "Choose weapon"},
				{"keys": ["Q", "E"], "text": "Category"}, {"action": "pause", "text": "Back"}]
		"bench_parts":
			return [{"keys": ["W", "S"], "text": "Navigate"}, {"key": "Enter", "text": "Fit / remove"},
				{"action": "pause", "text": "Weapons"}]
	return [{"keys": ["W", "S"], "text": "Navigate"}, {"key": "Enter", "text": "Buy"}, {"key": "R", "text": "Fill ammo"},
		{"keys": ["Q", "E"], "text": "Category"}, {"action": "pause", "text": "Back"}]


## Hide slot tabs this shop has nothing for (keeps ARMOUR / WORKBENCH).
func _filter_tabs() -> void:
	var stock := Catalog.shop_stock(shop_id)
	var keys: Array = []
	var names: Array = []
	for t: Array in TABS:
		var key: String = t[0]
		var keep := key == "workbench" or (key == "armour" and not (shop_def.get("items", []) as Array).is_empty())
		if not keep:
			for id: Variant in stock:
				if Catalog.weapon_slot(str(id)) == key:
					keep = true
					break
		if keep:
			keys.append(key)
			names.append(t[1])
	_tab_keys = keys
	_tabs.set_tabs(names, 0)


func _first_stock_tab() -> int:
	var i := _tab_keys.find("handgun")
	return maxi(i, 0)


func _show_tab(index: int) -> void:
	var key: String = _tab_keys[clampi(index, 0, _tab_keys.size() - 1)]
	if key == "workbench":
		_bench_from_tab = true
		_enter_bench()
		return
	_page = "shop"
	_hints.set_hints(_hint_list())
	_subtitle_text = str(shop_def.get("tagline", "Firearms, ammunition, armour and a workbench"))
	_refresh_header()
	if key == "armour":
		_set_items(_armour_items(), "Body armour")
	else:
		_set_items(_weapon_items(key), str(LIST_TITLES.get(key, _tab_name(key))))


func _tab_name(key: String) -> String:
	for t: Array in TABS:
		if t[0] == key:
			return str(t[1])
	return key


func _weapon_items(slot: String) -> Array:
	var out: Array = []
	for id_v: Variant in Catalog.shop_stock(shop_id):
		var id := str(id_v)
		if Catalog.weapon_slot(id) != slot:
			continue
		var spec := Catalog.weapon_def(id)
		var name := Catalog.display_name(spec, id)
		var icon: StringName = SLOT_ICONS.get(slot, &"handgun")
		if not Catalog.owns_weapon(id):
			out.append({"kind": "weapon", "id": id, "text": name, "sub": str(Catalog.obj_get(spec, "description", "")),
				"icon": icon, "price": Catalog.price(Catalog.weapon_price(id))})
			continue
		var ammo := Catalog.ammo_info(id)
		if not bool(ammo["uses_ammo"]):
			out.append({"kind": "owned", "id": id, "text": name, "sub": str(Catalog.obj_get(spec, "description", "")),
				"icon": icon, "price": 0, "owned": true, "icon_color": UiStyle.TEAL_LIGHT})
			continue
		var sub := "%s x%d   |   %d / %d" % [str(ammo["name"]), int(ammo["pack"]), int(ammo["reserve"]), int(ammo["max"])]
		var row := {"kind": "ammo", "id": id, "text": name, "sub": sub, "icon": icon, "badge": "OWNED",
			"icon_color": UiStyle.TEAL_LIGHT}
		if bool(ammo["full"]):
			row["right"] = "AMMO FULL"
			row["right_color"] = UiStyle.TEAL_LIGHT
		else:
			row["price"] = Catalog.price(int(ammo["unit_price"]))
		out.append(row)
	return out


func _armour_items() -> Array:
	var out: Array = []
	var p := Catalog.player()
	var full := p != null and float(Catalog.obj_get(p, "armor", 0.0)) >= float(Catalog.obj_get(p, "max_armor", 100.0)) - 0.5
	for id_v: Variant in shop_def.get("items", []):
		var def := Catalog.item_def(str(id_v))
		if def.is_empty():
			continue
		var row := {"kind": "item", "id": str(id_v), "text": str(def.get("display_name", id_v)),
			"sub": str(def.get("description", "")), "icon": StringName(str(def.get("icon", "shield")))}
		if full:
			row["right"] = "ARMOUR FULL"
			row["right_color"] = UiStyle.TEAL_LIGHT
		else:
			row["price"] = Catalog.price(int(def.get("price", 0)))
		out.append(row)
	return out


# --- workbench -------------------------------------------------------------------------------

func _enter_bench() -> void:
	_page = "bench_weapons"
	_bench_weapon = ""
	_hints.set_hints(_hint_list())
	var wb := _tab_keys.find("workbench")
	if wb >= 0 and _tabs.current != wb:
		_tabs.select(wb, false)
	_subtitle_text = "Workbench - attachments and finishes for the firearms you own"
	_refresh_header()
	var out: Array = []
	var inv := Catalog.inventory()
	if inv != null:
		for id_v: Variant in inv.call("get_weapons"):
			var id := str(id_v)
			var compat := Catalog.compatible_attachments(id)
			if compat.is_empty():
				continue
			var fitted := Catalog.fitted_attachments(id)
			var slot := Catalog.weapon_slot(id)
			out.append({"kind": "bench_weapon", "id": id, "text": Catalog.display_name(Catalog.weapon_def(id), id),
				"sub": "%d of %d parts fitted" % [fitted.size(), compat.size()], "icon": SLOT_ICONS.get(slot, &"handgun"),
				"right": "%d / %d" % [fitted.size(), compat.size()]})
	_set_items(out, "Your firearms" if not out.is_empty() else "No firearms to modify - buy one first")


func _enter_parts(weapon_id: String) -> void:
	_page = "bench_parts"
	_bench_weapon = weapon_id
	_hints.set_hints(_hint_list())
	_fill_parts(false)


func _fill_parts(keep: bool) -> void:
	var out: Array = []
	var has_finish := false
	for att_v: Variant in Catalog.compatible_attachments(_bench_weapon):
		var att := str(att_v)
		var def := Catalog.attachment_def(att)
		var kind := Catalog.attachment_kind(att)
		var state := Catalog.attachment_state(_bench_weapon, att)
		var row := {"kind": "part", "id": att, "text": Catalog.display_name(def, att), "sub": _effect_line(def, kind),
			"icon": &"gear"}
		if kind == "finish":
			has_finish = true
			row["icon"] = &"circle"
			var col: Variant = Catalog.obj_get(def, "color", Color.WHITE)
			row["icon_color"] = col if col is Color else Color.WHITE
		match state:
			"fitted":
				row["badge"] = "FITTED"
				row["right"] = "REMOVE" if kind != "finish" else "APPLIED"
				row["right_color"] = UiStyle.TEAL_LIGHT
			"owned":
				row["right"] = "OWNED"
				row["right_color"] = UiStyle.TEAL_LIGHT
			_:
				row["price"] = Catalog.price(Catalog.attachment_price(att))
		out.append(row)
	if has_finish:
		var fitted_finish := false
		for f: Variant in Catalog.fitted_attachments(_bench_weapon):
			if Catalog.attachment_kind(str(f)) == "finish":
				fitted_finish = true
		out.append({"kind": "factory", "id": "", "text": "Factory Finish", "sub": "Finish - original colours, free",
			"icon": &"circle", "icon_color": Color(0.32, 0.34, 0.36), "right": "APPLIED" if not fitted_finish else "FREE",
			"right_color": UiStyle.TEAL_LIGHT, "badge": "FITTED" if not fitted_finish else ""})
	_set_items(out, "Workbench - " + Catalog.display_name(Catalog.weapon_def(_bench_weapon), _bench_weapon), keep)


## One short line of what a part does (the shop sub-line).
func _effect_line(def: Object, kind: String) -> String:
	if kind == "finish":
		return "Cosmetic tint"
	if kind == "flashlight":
		return "Lights up dark places while aiming"
	var t := str(def.call("effect_text")) if def != null and def.has_method("effect_text") else ""
	return t.substr(0, 1).to_upper() + t.substr(1)


func handle_back() -> bool:
	if super.handle_back():
		return true
	if _page == "bench_parts":
		var w := _bench_weapon
		_enter_bench()
		var i := find_index("id", w)
		if i >= 0:
			_list.select(i, true)
		return true
	if _page == "bench_weapons" and _bench_from_tab:
		_tabs.select(_first_stock_tab())
		return true
	return false


# --- selection / details ---------------------------------------------------------------------

func _on_item_selected(_index: int, item: Dictionary) -> void:
	_clear_detail()
	_bars = null
	_primary_btn = null
	if item.is_empty():
		_preview_none("")
		return
	match str(item.get("kind", "")):
		"weapon", "ammo", "owned":
			_detail_weapon(item)
		"item":
			_detail_item(item)
		"bench_weapon":
			_detail_bench_weapon(item)
		"part", "factory":
			_detail_part(item)


func _show_weapon_preview(id: String, attachments: Array) -> void:
	if _preview == null:
		return
	if bool(_preview.call("show_weapon", id, attachments)):
		_preview_shown()
	else:
		_preview_none("No model for this weapon")


func _detail_weapon(item: Dictionary) -> void:
	var id := str(item["id"])
	var owned := Catalog.owns_weapon(id)
	_show_weapon_preview(id, Catalog.fitted_attachments(id) if owned else [])
	var spec := Catalog.spec_with(id, Catalog.fitted_attachments(id) if owned else [])
	_detail_title(str(item["text"]), str(Catalog.obj_get(spec, "description", "")))
	_bars = StatBarsScript.new()
	_bars.call("set_rows", _stat_rows(spec, null))
	_detail.add_child(_bars)
	var buttons: Array = []
	match str(item["kind"]):
		"weapon":
			_primary_btn = UiKit.button("Buy  %s" % _price_text(Catalog.weapon_price(id)), _on_primary, &"AccentButton")
			buttons.append(_primary_btn)
		"ammo":
			var ammo := Catalog.ammo_info(id)
			_primary_btn = UiKit.button("Ammo x%d  %s" % [int(ammo["pack"]), _price_text(int(ammo["unit_price"]))], _on_primary, &"AccentButton")
			_primary_btn.disabled = bool(ammo["full"])
			buttons.append(_primary_btn)
			var fill := UiKit.button("Fill ammo", _on_fill)
			fill.disabled = bool(ammo["full"])
			buttons.append(fill)
			buttons.append(UiKit.button("Equip", _on_equip, &"GhostButton"))
		"owned":
			buttons.append(UiKit.button("Equip", _on_equip, &"GhostButton"))
	_detail_button_row(buttons)


func _detail_item(item: Dictionary) -> void:
	var def := Catalog.item_def(str(item["id"]))
	if _preview != null:
		if bool(_preview.call("show_model", str(def.get("model", "")))):
			_preview_shown()
		else:
			_preview_none("")
	_detail_title(str(item["text"]), str(def.get("description", "")))
	var p := Catalog.player()
	var armor := float(Catalog.obj_get(p, "armor", 0.0))
	var max_armor := maxf(float(Catalog.obj_get(p, "max_armor", 100.0)), 1.0)
	var gain := float((def.get("effects", {}) as Dictionary).get("armor", 0.0))
	_bars = StatBarsScript.new()
	_bars.call("set_rows", [{"label": "Armour", "value": armor / max_armor, "after": minf(armor + gain, max_armor) / max_armor,
		"text": "%d" % int(armor), "after_text": "%d" % int(minf(armor + gain, max_armor))}])
	_detail.add_child(_bars)
	_primary_btn = UiKit.button("Buy  %s" % _price_text(int(def.get("price", 0))), _on_primary, &"AccentButton")
	_primary_btn.disabled = armor >= max_armor - 0.5
	_detail_button_row([_primary_btn])


func _detail_bench_weapon(item: Dictionary) -> void:
	var id := str(item["id"])
	_show_weapon_preview(id, Catalog.fitted_attachments(id))
	var spec := Catalog.spec_with(id, Catalog.fitted_attachments(id))
	var fitted: PackedStringArray = []
	for a: Variant in Catalog.fitted_attachments(id):
		fitted.append(Catalog.display_name(Catalog.attachment_def(str(a)), str(a)))
	_detail_title(str(item["text"]), "Fitted: " + (", ".join(fitted) if not fitted.is_empty() else "nothing yet"))
	_bars = StatBarsScript.new()
	_bars.call("set_rows", _stat_rows(spec, null, true))
	_detail.add_child(_bars)
	_detail_button_row([UiKit.button("Modify", _on_primary, &"AccentButton")])


func _detail_part(item: Dictionary) -> void:
	var att := str(item["id"])
	var before_atts := Catalog.fitted_attachments(_bench_weapon)
	var after_atts: Array
	var state := "factory"
	if str(item["kind"]) == "factory":
		after_atts = before_atts.filter(func(a: Variant) -> bool: return Catalog.attachment_kind(str(a)) != "finish")
	else:
		state = Catalog.attachment_state(_bench_weapon, att)
		after_atts = Catalog.preview_attachments(_bench_weapon, att, state == "fitted" and Catalog.attachment_kind(att) != "finish")
	_show_weapon_preview(_bench_weapon, after_atts)
	var before := Catalog.spec_with(_bench_weapon, before_atts)
	var after := Catalog.spec_with(_bench_weapon, after_atts)
	var def := Catalog.attachment_def(att)
	var desc := str(Catalog.obj_get(def, "description", "Original colours of the weapon."))
	_detail_title(str(item["text"]), desc)
	_bars = StatBarsScript.new()
	_bars.call("set_rows", _stat_rows(before, after, true))
	_detail.add_child(_bars)
	var label := "Fit  %s" % _price_text(Catalog.attachment_price(att))
	match state:
		"fitted":
			label = "Remove" if Catalog.attachment_kind(att) != "finish" else "Applied"
		"owned":
			label = "Refit (owned)"
		"factory":
			label = "Restore factory finish"
	_primary_btn = UiKit.button(label, _on_primary, &"AccentButton")
	_primary_btn.disabled = state == "fitted" and Catalog.attachment_kind(att) == "finish"
	_detail_button_row([_primary_btn, UiKit.button("Back", func() -> void: handle_back(), &"GhostButton")])


func _price_text(base_price: int) -> String:
	var p := Catalog.price(base_price)
	return "FREE" if p <= 0 else UiStyle.money(p)


## Normalised stat rows of a spec (and of `after` for a before / after comparison).
func _stat_rows(spec: Object, after: Object, bench: bool = false) -> Array:
	if spec == null:
		return []
	var rows: Array = []
	var melee := str(Catalog.obj_get(spec, "fire_mode", "")) == "melee"
	var defs: Array = [
		["Damage", "_v_damage", "_t_damage"], ["Fire rate", "_v_rate", "_t_rate"], ["Range", "_v_range", "_t_range"],
	]
	if not melee:
		defs.append(["Accuracy", "_v_accuracy", "_t_accuracy"])
		defs.append(["Control", "_v_control", "_t_control"])
		if int(Catalog.obj_get(spec, "mag_size", 0)) > 0:
			defs.append(["Magazine", "_v_mag", "_t_mag"])
		if bench:
			defs.append(["Stealth", "_v_stealth", "_t_stealth"])
			defs.append(["Zoom", "_v_zoom", "_t_zoom"])
	for d: Array in defs:
		var row := {"label": d[0], "value": call(d[1], spec), "text": call(d[2], spec)}
		if after != null:
			row["after"] = call(d[1], after)
			row["after_text"] = call(d[2], after)
		rows.append(row)
	return rows


func _shot_damage(s: Object) -> float:
	return float(Catalog.obj_get(s, "damage", 0.0)) * float(maxi(int(Catalog.obj_get(s, "pellets", 1)), 1))


func _v_damage(s: Object) -> float:
	return clampf(sqrt(_shot_damage(s) / 140.0), 0.04, 1.0)


func _t_damage(s: Object) -> String:
	var p := int(Catalog.obj_get(s, "pellets", 1))
	if p > 1:
		return "%d x%d" % [int(round(float(Catalog.obj_get(s, "damage", 0.0)))), p]
	return "%d" % int(round(_shot_damage(s)))


func _v_rate(s: Object) -> float:
	return clampf(float(Catalog.obj_get(s, "rpm", 0.0)) / 900.0, 0.04, 1.0)


func _t_rate(s: Object) -> String:
	return "%d rpm" % int(Catalog.obj_get(s, "rpm", 0.0))


func _v_range(s: Object) -> float:
	var melee := str(Catalog.obj_get(s, "fire_mode", "")) == "melee"
	var r := float(Catalog.obj_get(s, "melee_range" if melee else "max_range", 0.0))
	return clampf(sqrt(r / (3.0 if melee else 450.0)), 0.04, 1.0)


func _t_range(s: Object) -> String:
	var melee := str(Catalog.obj_get(s, "fire_mode", "")) == "melee"
	return "%.1f m" % float(Catalog.obj_get(s, "melee_range", 0.0)) if melee else "%d m" % int(Catalog.obj_get(s, "max_range", 0.0))


func _aimed_spread(s: Object) -> float:
	return float(Catalog.obj_get(s, "spread_base", 1.0)) * float(Catalog.obj_get(s, "spread_aim_mult", 1.0))


func _v_accuracy(s: Object) -> float:
	return clampf(1.0 - _aimed_spread(s) / 2.2, 0.05, 1.0)


func _t_accuracy(s: Object) -> String:
	return "%.2f deg" % _aimed_spread(s)


func _v_control(s: Object) -> float:
	return clampf(1.0 - float(Catalog.obj_get(s, "recoil_pitch", 1.0)) / 7.0, 0.05, 1.0)


func _t_control(s: Object) -> String:
	return "kick %.1f" % float(Catalog.obj_get(s, "recoil_pitch", 0.0))


func _v_mag(s: Object) -> float:
	return clampf(float(Catalog.obj_get(s, "mag_size", 0)) / 45.0, 0.04, 1.0)


func _t_mag(s: Object) -> String:
	return "%d rds" % int(Catalog.obj_get(s, "mag_size", 0))


func _v_stealth(s: Object) -> float:
	return clampf(1.0 - float(Catalog.obj_get(s, "noise_radius", 70.0)) / 100.0, 0.04, 1.0)


func _t_stealth(s: Object) -> String:
	return "heard %d m" % int(Catalog.obj_get(s, "noise_radius", 0.0))


func _v_zoom(s: Object) -> float:
	return clampf((70.0 - float(Catalog.obj_get(s, "aim_fov", 50.0))) / 55.0, 0.04, 1.0)


func _t_zoom(s: Object) -> String:
	return "x%.1f" % (70.0 / maxf(float(Catalog.obj_get(s, "aim_fov", 50.0)), 1.0))


# --- actions ---------------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == KEY_R and _page == "shop":
		_on_fill()
		get_viewport().set_input_as_handled()


func _on_primary() -> void:
	var item := get_selected_item()
	if not item.is_empty():
		_activate(item)


func _on_fill() -> void:
	var item := get_selected_item()
	if str(item.get("kind", "")) != "ammo":
		UiKit.sfx("ui_error")
		return
	_report(Catalog.buy_ammo(str(item["id"]), -1))
	_refill()


func _on_equip() -> void:
	var item := get_selected_item()
	var inv := Catalog.inventory()
	if inv != null and inv.has_method("equip") and bool(inv.call("equip", str(item.get("id", "")))):
		_set_feedback("%s in hand" % str(item.get("text", "")), true)
		UiKit.sfx("ui_click")
	else:
		UiKit.sfx("ui_error")


func _activate(item: Dictionary) -> Dictionary:
	var res := {"ok": false, "message": ""}
	match str(item.get("kind", "")):
		"weapon":
			res = _report(Catalog.buy_weapon(str(item["id"])))
			_refill()
		"ammo":
			res = _report(Catalog.buy_ammo(str(item["id"]), 1))
			_refill()
		"owned":
			res = _report({"ok": false, "message": "Already in your collection"})
		"item":
			res = _report(Catalog.buy_item(str(item["id"])))
			_refill()
		"bench_weapon":
			_enter_parts(str(item["id"]))
			res = {"ok": true, "message": ""}
		"part":
			var att := str(item["id"])
			var state := Catalog.attachment_state(_bench_weapon, att)
			if state == "fitted":
				if Catalog.attachment_kind(att) == "finish":
					res = _report({"ok": false, "message": "Finish already applied"})
				else:
					res = _report(Catalog.remove_attachment(_bench_weapon, att), false)
			else:
				res = _report(Catalog.install_attachment(_bench_weapon, att))
			_fill_parts(true)
		"factory":
			res = _report(Catalog.clear_finish(_bench_weapon), false)
			_fill_parts(true)
	return res
