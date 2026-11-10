extends "res://gta/code/world/shops/shop_appearance_base.gd"
## Wardrobe (ECONOMY A, spec 23A): the clothes you own, any colour, free.
##   UI.open_screen("wardrobe", {"tab": 0..4})
## Opened from the changing booth at Tide Threads and the safehouse wardrobe. Only items of the
## owned set (SaveSystem provider "wardrobe", seeded with what the player wears) are listed.

const SLOTS := ["top", "bottom", "shoes", "hat", "glasses"]
const NAMES := ["Tops", "Bottoms", "Shoes", "Hats", "Glasses"]


func _ready() -> void:
	_build_appearance("Wardrobe", "Your clothes - changing is free", NAMES, SLOTS, "full")


func open(args: Dictionary) -> void:
	super.open(args)
	_title_text = "Wardrobe"
	_subtitle_text = "Your clothes - pick a colour, changing is free"
	_refresh_header()


func _verb() -> String:
	return "Wear"


func _section_title(slot: String, rows: Array) -> String:
	return "%s - %d owned" % [slot.capitalize() + ("s" if not slot.ends_with("s") else ""), rows.size()]


func _rows_for(slot: String) -> Array:
	var a := Catalog.player_appearance()
	var out: Array = []
	for def: Dictionary in _defs_for(slot):
		var id := str(def["id"])
		if not Catalog.owns_clothing(id):
			continue
		var n := (def.get("colors", []) as Array).size()
		var row := {"kind": "clothing", "id": id, "def": def, "text": str(def.get("display_name", id)),
			"sub": "%d colours" % n if n > 1 else "One style", "icon": SLOT_ICONS.get(slot, &"shirt")}
		if Catalog.is_wearing(def, a):
			row["badge"] = "WEARING"
		out.append(row)
	return out


func _describe(def: Dictionary) -> String:
	var n := (def.get("colors", []) as Array).size()
	return "%d colours to choose from" % n if n > 1 else "One style"


func _update_status() -> void:
	if _status_label == null or _cur_def.is_empty():
		return
	var look := _preview_look()
	var cur := Catalog.player_appearance()
	var same := true
	for k: Variant in Catalog.appearance_partial(_cur_def, _selected_color()).keys():
		if str(cur.get(k, "")) != str(look[k]):
			same = false
	_status_label.text = "Wearing this now" if same else "Free to wear"
	_status_label.add_theme_color_override("font_color", UiStyle.TEAL_LIGHT)
	if _primary_btn != null:
		_primary_btn.text = "Wearing" if same else "Wear"
		_primary_btn.disabled = same


func _activate(item: Dictionary) -> Dictionary:
	if str(item.get("kind", "")) != "clothing":
		return {"ok": false, "message": ""}
	var res := _report(Catalog.wear_clothing(str(item["id"]), _selected_color()), false)
	if bool(res.get("ok", false)):
		_refill()
	return res
