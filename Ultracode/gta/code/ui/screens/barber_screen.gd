extends "res://gta/code/world/shops/shop_appearance_base.gd"
## Harbor Cuts - barber (ECONOMY A, spec 23A "Hair / appearance").
##   UI.open_screen("shop_barber", {"shop_id": "harbor_cuts", "tab": 0 hair | 1 beard})
## Hair styles with hair colours (Registry "hair", only styles that exist on the character model)
## and beards (cut for the M body). Close-up live preview on a clone. Price = the style's price when
## the cut changes + Catalog.COLOUR_FEE when only the colour changes.

const SLOTS := ["hair", "beard"]
const NAMES := ["Hair", "Beard"]


func _init() -> void:
	super()
	default_shop_id = "harbor_cuts"
	_registry_kind = "hair"


func _ready() -> void:
	_build_appearance("Harbor Cuts", "Cuts, colours and beard trims", NAMES, SLOTS, "head", Vector2i(400, 380))


func _verb() -> String:
	return "Cut"


func _wearing_badge() -> String:
	return "CURRENT"


func _section_title(slot: String, rows: Array) -> String:
	if slot == "beard" and rows.size() <= 1:
		return "Beards - cut for the M body only"
	return "Hair styles" if slot == "hair" else "Beards and moustaches"


func _rows_for(slot: String) -> Array:
	var a := Catalog.player_appearance()
	var out: Array = []
	for def: Dictionary in _defs_for(slot):
		var id := str(def["id"])
		var row := {"kind": "hair", "id": id, "def": def, "text": str(def.get("display_name", id)),
			"sub": _describe(def), "icon": &"scissors", "price": Catalog.price(int(def.get("price", 0)))}
		if str(a.get(slot, "")) == str(def.get("part", "")):
			row["badge"] = "CURRENT"
			row["icon_color"] = UiStyle.TEAL_LIGHT
		out.append(row)
	return out


func _describe(def: Dictionary) -> String:
	var n := (def.get("colors", []) as Array).size()
	if str(def.get("slot", "")) == "beard":
		return "Matches your hair colour"
	return "%d colours" % n if n > 1 else "No colour"


func _no_colour_note() -> String:
	return "Beards take your hair colour" if str(_cur_def.get("slot", "")) == "beard" else "Nothing to colour"


func _update_status() -> void:
	if _status_label == null or _cur_def.is_empty():
		return
	var cost := Catalog.price(Catalog.haircut_price(_cur_def, _selected_color()))
	var look := _preview_look()
	var cur := Catalog.player_appearance()
	var same := true
	for k: Variant in Catalog.appearance_partial(_cur_def, _selected_color()).keys():
		if str(cur.get(k, "")).to_lower() != str(look[k]).to_lower():
			same = false
	if same:
		_status_label.text = "Your current look"
		_status_label.add_theme_color_override("font_color", UiStyle.TEAL_LIGHT)
	else:
		var colour_only := str(cur.get(str(_cur_def.get("slot", "")), "")) == str(_cur_def.get("part", ""))
		var parts: PackedStringArray = []
		if not colour_only:
			parts.append("New cut %s" % UiStyle.money(Catalog.price(int(_cur_def.get("price", 0)))))
		var key := str(_cur_def.get("color_key", ""))
		if key != "" and _selected_color() != "" and str(cur.get(key, "")).to_lower() != _selected_color().to_lower():
			parts.append(("colour %s" if not parts.is_empty() else "Colour %s") % UiStyle.money(Catalog.price(Catalog.COLOUR_FEE)))
		_status_label.text = (" + ".join(parts) if not parts.is_empty() else "Price") + ("   =   FREE" if cost <= 0 else "   =   " + UiStyle.money(cost))
		_status_label.add_theme_color_override("font_color", UiStyle.SUN if Game.money >= cost else UiStyle.BAD)
	if _primary_btn != null:
		_primary_btn.text = "Current" if same else "Cut  " + ("FREE" if cost <= 0 else UiStyle.money(cost))
		_primary_btn.disabled = same


func _activate(item: Dictionary) -> Dictionary:
	if str(item.get("kind", "")) != "hair":
		return {"ok": false, "message": ""}
	var res := _report(Catalog.buy_haircut(str(item["id"]), _selected_color()))
	if bool(res.get("ok", false)):
		_refill()
	return res
