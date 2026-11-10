extends "res://gta/code/world/shops/shop_screen_base.gd"
## Corner 24 - general store (ECONOMY A, spec 23 / 24: food / health / armour purchases).
##   UI.open_screen("shop_general", {"shop_id": "corner_24", "tab": 0..3})
## Tabs FOOD / DRINKS / HEALTH / GEAR from Registry "shop_items" (shops_registry.gd): snacks and
## drinks heal a little (drinks refill stamina), bandage / first aid kit heal more, light armour,
## parachute (sets player.has_parachute through give_parachute()) and scuba kit (give_scuba() /
## has_scuba). Nothing is charged when the item would be wasted (full health, already owned ...).
## Works for any shop def with a "stock" of shop_items ids (e.g. a gas station kiosk).

const CATEGORIES := [["food", "Food"], ["drinks", "Drinks"], ["health", "Health"], ["gear", "Gear"]]

var _cats: Array = []
var _bars: Control = null
var _primary_btn: Button = null
var _icon_rect: Control = null


func _init() -> void:
	super()
	default_shop_id = "corner_24"


func _ready() -> void:
	var names: Array = []
	for c: Array in CATEGORIES:
		_cats.append(c[0])
		names.append(c[1])
	_build_layout("Corner 24", "Snacks, drinks, first aid and beach gear", names, Vector2i(400, 300))


func open(args: Dictionary) -> void:
	_resolve_shop(args)
	# keep only categories this shop stocks
	var keys: Array = []
	var names: Array = []
	for c: Array in CATEGORIES:
		for id: Variant in _stock():
			if str(Catalog.item_def(str(id)).get("category", "")) == c[0]:
				keys.append(c[0])
				names.append(c[1])
				break
	if not keys.is_empty():
		_cats = keys
		_tabs.set_tabs(names, 0)
	var start := clampi(int(args.get("tab", 0)), 0, _cats.size() - 1)
	_tabs.select(start, false)
	_show_tab(start)
	_list.grab()


func _stock() -> Array:
	var out: Array = Catalog.shop_stock(shop_id, "shop_items")
	for extra: Variant in shop_def.get("items", []):
		if not out.has(extra):
			out.append(extra)
	return out


func _show_tab(index: int) -> void:
	var cat: String = _cats[clampi(index, 0, _cats.size() - 1)]
	var out: Array = []
	for id_v: Variant in _stock():
		var id := str(id_v)
		var def := Catalog.item_def(id)
		if def.is_empty() or str(def.get("category", "")) != cat:
			continue
		var row := {"kind": "item", "id": id, "text": str(def.get("display_name", id)), "sub": _effect_text(def),
			"icon": StringName(str(def.get("icon", "bag")))}
		var reason := Catalog.item_block_reason(id)
		var fx: Dictionary = def.get("effects", {}) as Dictionary
		if reason != "" and (bool(fx.get("parachute", false)) or bool(fx.get("scuba", false))):
			row["owned"] = true
			row["price"] = 0
			row["icon_color"] = UiStyle.TEAL_LIGHT
		else:
			row["price"] = Catalog.price(int(def.get("price", 0)))
		out.append(row)
	var title := "Food" if cat == "food" else ("Drinks" if cat == "drinks" else ("First aid" if cat == "health" else "Gear"))
	_set_items(out, title)


func _effect_text(def: Dictionary) -> String:
	var fx: Dictionary = def.get("effects", {}) as Dictionary
	var parts: PackedStringArray = []
	if fx.has("heal"):
		parts.append("+%d health" % int(fx["heal"]) if int(fx["heal"]) < 100 else "full health")
	if fx.has("armor"):
		parts.append("+%d armour" % int(fx["armor"]))
	if bool(fx.get("stamina", false)):
		parts.append("stamina refill")
	if bool(fx.get("parachute", false)):
		parts.append("parachute")
	if bool(fx.get("scuba", false)):
		parts.append("long dives")
	var t := ", ".join(parts)
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else t


func _on_item_selected(_index: int, item: Dictionary) -> void:
	_clear_detail()
	_bars = null
	_primary_btn = null
	if item.is_empty():
		_preview_none("")
		return
	var id := str(item["id"])
	var def := Catalog.item_def(id)
	var model := str(def.get("model", ""))
	if _preview != null and model != "" and bool(_preview.call("show_model", model)):
		_preview_shown()
	else:
		_preview_none("")
	_show_icon_if_needed(model == "", StringName(str(def.get("icon", "bag"))))
	_detail_title(str(item["text"]), str(def.get("description", "")))
	_bars = StatBarsScript.new()
	_bars.call("set_rows", _status_rows(def))
	_detail.add_child(_bars)
	var reason := Catalog.item_block_reason(id)
	var label := "Buy  " + ("FREE" if Catalog.price(int(def.get("price", 0))) <= 0 else UiStyle.money(Catalog.price(int(def.get("price", 0)))))
	_primary_btn = UiKit.button(label if reason == "" else reason, _on_primary, &"AccentButton")
	_primary_btn.disabled = reason != ""
	_detail_button_row([_primary_btn])


## Food and drinks have no 3D model: a large code-drawn glyph stands in the preview stage (UI art,
## not a 3D placeholder).
func _show_icon_if_needed(show: bool, icon: StringName) -> void:
	if _icon_rect == null and _preview_note != null:
		_icon_rect = UiKit.icon(icon, 150.0, Color(UiStyle.CREAM, 0.92))
		_icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var host := _preview_note.get_parent()
		var center := CenterContainer.new()
		UiKit.fill(center)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(center)
		center.add_child(_icon_rect)
	if _icon_rect != null:
		_icon_rect.visible = show
		_icon_rect.set("icon", icon)


func _status_rows(def: Dictionary) -> Array:
	var p := Catalog.player()
	var fx: Dictionary = def.get("effects", {}) as Dictionary
	var rows: Array = []
	var hp := float(Catalog.obj_get(p, "health", 0.0))
	var hp_max := maxf(float(Catalog.obj_get(p, "max_health", 100.0)), 1.0)
	var ar := float(Catalog.obj_get(p, "armor", 0.0))
	var ar_max := maxf(float(Catalog.obj_get(p, "max_armor", 100.0)), 1.0)
	var heal := float(fx.get("heal", 0.0))
	var arm := float(fx.get("armor", 0.0))
	var r1 := {"label": "Health", "value": hp / hp_max, "text": "%d" % int(hp)}
	if heal > 0.0:
		r1["after"] = minf(hp + heal, hp_max) / hp_max
		r1["after_text"] = "%d" % int(minf(hp + heal, hp_max))
	rows.append(r1)
	var r2 := {"label": "Armour", "value": ar / ar_max, "text": "%d" % int(ar)}
	if arm > 0.0:
		r2["after"] = minf(ar + arm, ar_max) / ar_max
		r2["after_text"] = "%d" % int(minf(ar + arm, ar_max))
	rows.append(r2)
	if bool(fx.get("stamina", false)):
		var st := float(Catalog.obj_get(p, "stamina", 1.0))
		rows.append({"label": "Stamina", "value": st, "after": 1.0, "text": "%d%%" % int(st * 100.0), "after_text": "100%"})
	if bool(fx.get("parachute", false)):
		var has := bool(Catalog.obj_get(p, "has_parachute", false))
		rows.append({"label": "Parachute", "value": 1.0 if has else 0.0, "after": 1.0, "text": "packed" if has else "none",
			"after_text": "packed"})
	if bool(fx.get("scuba", false)):
		var has_s := bool(Catalog.obj_get(p, "has_scuba", false))
		rows.append({"label": "Scuba", "value": 1.0 if has_s else 0.0, "after": 1.0, "text": "owned" if has_s else "none",
			"after_text": "owned"})
	return rows


func _on_primary() -> void:
	var item := get_selected_item()
	if not item.is_empty():
		_activate(item)


func _activate(item: Dictionary) -> Dictionary:
	if str(item.get("kind", "")) != "item":
		return {"ok": false, "message": ""}
	var res := _report(Catalog.buy_item(str(item["id"])))
	_refill()
	return res
