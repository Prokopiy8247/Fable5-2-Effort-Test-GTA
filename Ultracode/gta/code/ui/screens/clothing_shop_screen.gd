extends "res://gta/code/world/shops/shop_appearance_base.gd"
## Tide Threads - clothing store (ECONOMY A, spec 23A "Clothing").
##   UI.open_screen("shop_clothing", {"shop_id": "tide_threads", "tab": 0..4})
## Tabs TOPS / BOTTOMS / SHOES / HATS / GLASSES, items from Registry "clothing"
## (appearance_registry.gd) that fit the player's body and exist on the character model, colour
## swatches per item, live preview on a dressed clone. Enter buys the item in the chosen colour and
## puts it on (Game.spend, EventBus.item_purchased); items you own are worn for free and move to the
## wardrobe (SaveSystem provider "wardrobe").

const SLOTS := ["top", "bottom", "shoes", "hat", "glasses"]
const NAMES := ["Tops", "Bottoms", "Shoes", "Hats", "Glasses"]
const SLOT_TITLES := {"top": "Shirts and jackets", "bottom": "Trousers, shorts and skirts", "shoes": "Shoes",
	"hat": "Hats and caps", "glasses": "Glasses"}


func _init() -> void:
	super()
	default_shop_id = "tide_threads"


func _ready() -> void:
	_build_appearance("Tide Threads", "Coastal clothing", NAMES, SLOTS, "full")


func _verb() -> String:
	return "Buy / Wear"


func _section_title(slot: String, _rows: Array) -> String:
	return str(SLOT_TITLES.get(slot, slot))


func _rows_for(slot: String) -> Array:
	var a := Catalog.player_appearance()
	var out: Array = []
	for def: Dictionary in _defs_for(slot):
		var id := str(def["id"])
		var owned := Catalog.owns_clothing(id)
		var n := (def.get("colors", []) as Array).size()
		var row := {"kind": "clothing", "id": id, "def": def, "text": str(def.get("display_name", id)),
			"sub": ("%d colours" % n if n > 1 else "One style") + ("   |   in your wardrobe" if owned else ""),
			"icon": SLOT_ICONS.get(slot, &"shirt"), "price": Catalog.price(int(def.get("price", 0))), "owned": owned}
		if owned:
			row["icon_color"] = UiStyle.TEAL_LIGHT
		if Catalog.is_wearing(def, a):
			row["badge"] = "WEARING"
		out.append(row)
	return out


func _describe(def: Dictionary) -> String:
	var owned := Catalog.owns_clothing(str(def.get("id", "")))
	var n := (def.get("colors", []) as Array).size()
	var colours := "%d colours" % n if n > 1 else "One style"
	if owned:
		return "%s - you own this, changing colour is free" % colours
	return "%s - %s" % [colours, UiStyle.money(Catalog.price(int(def.get("price", 0))))]


func _update_status() -> void:
	if _status_label == null or _cur_def.is_empty():
		return
	var id := str(_cur_def.get("id", ""))
	var owned := Catalog.owns_clothing(id)
	var look := _preview_look()
	var same := true
	for k: Variant in Catalog.appearance_partial(_cur_def, _selected_color()).keys():
		if str(Catalog.player_appearance().get(k, "")) != str(look[k]):
			same = false
	var p := Catalog.price(int(_cur_def.get("price", 0)))
	if same:
		_status_label.text = "Wearing this now"
		_status_label.add_theme_color_override("font_color", UiStyle.TEAL_LIGHT)
	elif owned:
		_status_label.text = "Owned - wear it for free"
		_status_label.add_theme_color_override("font_color", UiStyle.TEAL_LIGHT)
	else:
		_status_label.text = "Price  " + ("FREE" if p <= 0 else UiStyle.money(p))
		_status_label.add_theme_color_override("font_color", UiStyle.SUN if Game.money >= p else UiStyle.BAD)
	if _primary_btn != null:
		_primary_btn.text = "Wearing" if same else ("Wear" if owned else "Buy  " + ("FREE" if p <= 0 else UiStyle.money(p)))
		_primary_btn.disabled = same


func _activate(item: Dictionary) -> Dictionary:
	if str(item.get("kind", "")) != "clothing":
		return {"ok": false, "message": ""}
	var res := _report(Catalog.buy_clothing(str(item["id"]), _selected_color()))
	if bool(res.get("ok", false)):
		_refill()
	return res
