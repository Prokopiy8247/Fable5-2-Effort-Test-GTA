extends RefCounted
## Static pricing / purchase helpers of the ECONOMY module (shops), shared by the `shops` world
## system and the shop screens. Preload it: `const Catalog := preload("res://gta/code/world/shops/shop_catalog.gd")`.
##
## Rules (ARCHITECTURE_WAVE2 W2.6):
##   * every purchase goes through charge(): Game.spend(price) + EventBus.item_purchased(kind, id, price)
##   * Game.flags["free_shopping"] (admin "unlock all") makes every price 0
##   * nothing is charged when the purchase would have no effect (full health, ammo full, owned ...)
## Every buy_* / install_* function returns {"ok": bool, "message": String, "price": int}.
## Cross-module objects are reached softly: Registry definitions are read as Variants, the player and
## its WeaponInventory through Game.player with has_method checks.

const COLOUR_FEE := 12                 ## barber: new colour without a new cut
const SLOTS := ["melee", "handgun", "smg", "shotgun", "rifle", "sniper", "heavy", "thrown"]
const CLOTHING_SLOTS := ["top", "bottom", "shoes", "hat", "glasses"]
const ATTACHMENT_KINDS := ["suppressor", "scope", "flashlight", "grip", "ext_mag", "finish"]
const WARDROBE_SCRIPT := "res://gta/code/world/shops/shop_wardrobe.gd"

static var _fallback_wardrobe: RefCounted = null
static var _fallback_unlocked: Dictionary = {}     ## weapon id -> {att id: true} (no shops system)


# --- pricing ---------------------------------------------------------------------------------

static func is_free() -> bool:
	return bool(Game.flags.get("free_shopping", false))


static func price(base_price: int) -> int:
	return 0 if is_free() else maxi(base_price, 0)


static func can_afford(base_price: int) -> bool:
	return price(base_price) <= Game.money


## The one place money leaves the player in a shop.
static func charge(kind: String, id: String, base_price: int) -> bool:
	var p := price(base_price)
	if not Game.spend(p):
		return false
	EventBus.item_purchased.emit(kind, id, p)
	return true


static func result(ok: bool, message: String, paid: int = 0) -> Dictionary:
	return {"ok": ok, "message": message, "price": paid}


# --- soft accessors --------------------------------------------------------------------------

static func player() -> Node3D:
	return Game.player if Game.has_player() else null


static func inventory() -> Node:
	var p := player()
	if p == null:
		return null
	var inv: Variant = p.get("inventory")
	if inv is Node and is_instance_valid(inv):
		return inv as Node
	return p.get_node_or_null("Inventory")


static func shops_system() -> Node:
	return Game.get_system("shops")


static func obj_get(o: Variant, prop: String, fallback: Variant = null) -> Variant:
	if o == null:
		return fallback
	if o is Dictionary:
		return (o as Dictionary).get(prop, fallback)
	if o is Object and is_instance_valid(o):
		var v: Variant = (o as Object).get(prop)
		return fallback if v == null else v
	return fallback


static func shop_def(id: String) -> Dictionary:
	var d: Variant = Registry.get_def("shops", id)
	return d as Dictionary if d is Dictionary else {}


static func item_def(id: String) -> Dictionary:
	var d: Variant = Registry.get_def("shop_items", id)
	return d as Dictionary if d is Dictionary else {}


static func weapon_def(id: String) -> Object:
	var d: Variant = Registry.get_def("weapons", id)
	return d as Object if d is Object else null


static func attachment_def(id: String) -> Object:
	var d: Variant = Registry.get_def("attachments", id)
	return d as Object if d is Object else null


static func display_name(def: Variant, fallback: String = "") -> String:
	var n := str(obj_get(def, "display_name", ""))
	return n if n != "" else fallback


static func call_bool(o: Object, method: String, args: Array = [], fallback: bool = false) -> bool:
	if o == null or not is_instance_valid(o) or not o.has_method(method):
		return fallback
	return bool(o.callv(method, args))


## Stock ids of a shop: weapons for "weapons", "*" expands to every def of the matching kind.
static func shop_stock(shop_id: String, kind_for_star: String = "") -> Array:
	var def := shop_def(shop_id)
	var stock: Array = def.get("stock", []) as Array
	if stock.has("*") and kind_for_star != "":
		return Registry.ids(kind_for_star)
	return stock.duplicate()


# --- weapons ---------------------------------------------------------------------------------

static func weapon_slot(id: String) -> String:
	return str(obj_get(weapon_def(id), "slot", ""))


static func weapon_price(id: String) -> int:
	return int(obj_get(weapon_def(id), "price", 0))


static func owns_weapon(id: String) -> bool:
	return call_bool(inventory(), "has_weapon", [id])


static func is_firearm(spec: Object) -> bool:
	return call_bool(spec, "is_firearm")


## {type, name, pack, unit_price, reserve, max, full, uses_ammo}
static func ammo_info(id: String) -> Dictionary:
	var spec := weapon_def(id)
	var type := str(obj_get(spec, "ammo_type", ""))
	var out := {"type": type, "name": type, "pack": int(obj_get(spec, "ammo_pack", 0)),
		"unit_price": int(obj_get(spec, "ammo_price", 0)), "reserve": 0, "max": 0, "full": false,
		"uses_ammo": type != "" and int(obj_get(spec, "ammo_pack", 0)) > 0}
	if type == "" or spec == null:
		return out
	var scr := spec.get_script() as Script
	var names: Variant = scr.get_script_constant_map().get("AMMO_NAMES", {}) if scr != null else {}
	if names is Dictionary:
		out["name"] = str((names as Dictionary).get(type, type))
	if spec.has_method("get_ammo_max"):
		out["max"] = int(spec.call("get_ammo_max"))
	var inv := inventory()
	if inv != null and inv.has_method("get_reserve"):
		out["reserve"] = int(inv.call("get_reserve", type))
	if inv != null and inv.has_method("is_ammo_full"):
		out["full"] = bool(inv.call("is_ammo_full", type))
	return out


static func buy_weapon(id: String) -> Dictionary:
	var inv := inventory()
	var spec := weapon_def(id)
	if inv == null or spec == null:
		return result(false, "Nothing to carry it in")
	if owns_weapon(id):
		return result(false, "You already own the %s" % display_name(spec, id))
	var p := weapon_price(id)
	if not charge("weapon", id, p):
		return result(false, "Not enough money")
	inv.call("give_weapon", id, -1)
	return result(true, "Bought the %s" % display_name(spec, id), price(p))


## packs < 0 = fill the reserve (as many packs as needed and affordable).
static func buy_ammo(id: String, packs: int = 1) -> Dictionary:
	var inv := inventory()
	var spec := weapon_def(id)
	if inv == null or spec == null:
		return result(false, "Nothing to carry it in")
	if not owns_weapon(id):
		return result(false, "Buy the weapon first")
	var info := ammo_info(id)
	if not bool(info["uses_ammo"]):
		return result(false, "This weapon needs no ammunition")
	if bool(info["full"]):
		return result(false, "%s full" % str(info["name"]))
	var pack := int(info["pack"])
	var unit := int(info["unit_price"])
	if packs < 0:
		var room := maxi(int(info["max"]) - int(info["reserve"]), pack)
		packs = int(ceil(float(room) / float(pack)))
		if not is_free() and unit > 0:
			packs = mini(packs, Game.money / unit)
		if packs <= 0:
			return result(false, "Not enough money")
	var total := unit * packs
	if not charge("ammo", id, total):
		return result(false, "Not enough money")
	var added := int(inv.call("add_ammo", str(info["type"]), pack * packs))
	return result(true, "+%d %s" % [added, str(info["name"]).to_lower()], price(total))


# --- items (armour, food, first aid, gear) ---------------------------------------------------

## "" when the item would do something right now, else the reason it would be wasted.
static func item_block_reason(item_id: String) -> String:
	var def := item_def(item_id)
	if def.is_empty():
		return "Unknown item"
	var p := player()
	if p == null:
		return "Nobody to use it"
	var fx: Dictionary = def.get("effects", {}) as Dictionary
	var useful := false
	var reasons: PackedStringArray = []
	if fx.has("heal"):
		if float(obj_get(p, "health", 0.0)) < float(obj_get(p, "max_health", 100.0)) - 0.5:
			useful = true
		else:
			reasons.append("Already at full health")
	if fx.has("armor"):
		if float(obj_get(p, "armor", 0.0)) < float(obj_get(p, "max_armor", 100.0)) - 0.5:
			useful = true
		else:
			reasons.append("Armour already full")
	if bool(fx.get("stamina", false)):
		if float(obj_get(p, "stamina", 1.0)) < 0.98:
			useful = true
	if bool(fx.get("parachute", false)):
		if not bool(obj_get(p, "has_parachute", false)):
			useful = true
		else:
			reasons.append("You already carry a parachute")
	if bool(fx.get("scuba", false)):
		if not bool(obj_get(p, "has_scuba", false)):
			useful = true
		else:
			reasons.append("You already own scuba gear")
	if useful:
		return ""
	return reasons[0] if not reasons.is_empty() else "You don't need that right now"


static func buy_item(item_id: String) -> Dictionary:
	var def := item_def(item_id)
	var reason := item_block_reason(item_id)
	if reason != "":
		return result(false, reason)
	var p := player()
	var cost := int(def.get("price", 0))
	if not charge("item", item_id, cost):
		return result(false, "Not enough money")
	var fx: Dictionary = def.get("effects", {}) as Dictionary
	var parts: PackedStringArray = []
	if fx.has("heal") and p.has_method("heal"):
		var before := float(obj_get(p, "health", 0.0))
		p.call("heal", float(fx["heal"]))
		parts.append("+%d health" % int(round(float(obj_get(p, "health", 0.0)) - before)))
	if fx.has("armor") and p.has_method("add_armor"):
		var a0 := float(obj_get(p, "armor", 0.0))
		p.call("add_armor", float(fx["armor"]))
		parts.append("+%d armour" % int(round(float(obj_get(p, "armor", 0.0)) - a0)))
	if bool(fx.get("stamina", false)) and "stamina" in p:
		p.set("stamina", 1.0)
		parts.append("stamina restored")
	if bool(fx.get("parachute", false)):
		if p.has_method("give_parachute"):
			p.call("give_parachute")
		else:
			p.set("has_parachute", true)
		parts.append("parachute packed")
	if bool(fx.get("scuba", false)):
		if p.has_method("give_scuba"):
			p.call("give_scuba")
		elif "has_scuba" in p:
			p.set("has_scuba", true)
		parts.append("scuba gear ready")
	var msg := str(def.get("display_name", item_id))
	if not parts.is_empty():
		msg += ": " + ", ".join(parts)
	return result(true, msg, price(cost))


# --- attachments (workbench) -----------------------------------------------------------------

static func attachment_kind(att_id: String) -> String:
	return str(obj_get(attachment_def(att_id), "kind", ""))


static func attachment_price(att_id: String) -> int:
	return int(obj_get(attachment_def(att_id), "price", 0))


static func compatible_attachments(weapon_id: String) -> Array:
	var spec := weapon_def(weapon_id)
	var list: Variant = obj_get(spec, "attachments", [])
	var out: Array = []
	if not (list is Array):
		return out
	for kind: String in ATTACHMENT_KINDS:
		for att: Variant in list:
			if attachment_kind(str(att)) == kind and Registry.has_def("attachments", str(att)):
				out.append(str(att))
	return out


static func fitted_attachments(weapon_id: String) -> Array:
	var inv := inventory()
	if inv == null or not inv.has_method("get_attachments"):
		return []
	return inv.call("get_attachments", weapon_id) as Array


static func is_attachment_unlocked(weapon_id: String, att_id: String) -> bool:
	var sys := shops_system()
	if sys != null and sys.has_method("is_attachment_unlocked"):
		return bool(sys.call("is_attachment_unlocked", weapon_id, att_id))
	return (_fallback_unlocked.get(weapon_id, {}) as Dictionary).has(att_id)


static func unlock_attachment(weapon_id: String, att_id: String) -> void:
	var sys := shops_system()
	if sys != null and sys.has_method("unlock_attachment"):
		sys.call("unlock_attachment", weapon_id, att_id)
		return
	if not _fallback_unlocked.has(weapon_id):
		_fallback_unlocked[weapon_id] = {}
	(_fallback_unlocked[weapon_id] as Dictionary)[att_id] = true


## "fitted" | "owned" (bought before, free to refit) | "buy" | "incompatible"
static func attachment_state(weapon_id: String, att_id: String) -> String:
	if not compatible_attachments(weapon_id).has(att_id):
		return "incompatible"
	if fitted_attachments(weapon_id).has(att_id):
		return "fitted"
	if is_attachment_unlocked(weapon_id, att_id):
		return "owned"
	return "buy"


## Attachment list after fitting `att_id` (same kind replaced) or removing it (`remove`).
static func preview_attachments(weapon_id: String, att_id: String, remove: bool = false) -> Array:
	var list := fitted_attachments(weapon_id).duplicate()
	if att_id == "":
		return list
	var kind := attachment_kind(att_id)
	if remove:
		list.erase(att_id)
		return list
	for other: Variant in list.duplicate():
		if attachment_kind(str(other)) == kind:
			list.erase(other)
	if not list.has(att_id):
		list.append(att_id)
	return list


static func install_attachment(weapon_id: String, att_id: String) -> Dictionary:
	var inv := inventory()
	if inv == null:
		return result(false, "No weapons")
	if not owns_weapon(weapon_id):
		return result(false, "You do not own that weapon")
	var state := attachment_state(weapon_id, att_id)
	var att := attachment_def(att_id)
	var att_name := display_name(att, att_id)
	if state == "incompatible":
		return result(false, "%s does not fit" % att_name)
	if state == "fitted":
		return result(false, "%s already fitted" % att_name)
	var paid := 0
	if state == "buy":
		var cost := attachment_price(att_id)
		if not charge("attachment", "%s:%s" % [weapon_id, att_id], cost):
			return result(false, "Not enough money")
		paid = price(cost)
	if not bool(inv.call("add_attachment", weapon_id, att_id)):
		if paid > 0:
			Game.add_money(paid)        # refund: the inventory refused it
		return result(false, "%s could not be fitted" % att_name)
	unlock_attachment(weapon_id, att_id)
	return result(true, ("Fitted %s" if paid > 0 or state == "buy" else "Refitted %s") % att_name, paid)


static func remove_attachment(weapon_id: String, att_id: String) -> Dictionary:
	var inv := inventory()
	if inv == null or not inv.has_method("remove_attachment"):
		return result(false, "No weapons")
	if not bool(inv.call("remove_attachment", weapon_id, att_id)):
		return result(false, "Nothing to remove")
	unlock_attachment(weapon_id, att_id)
	return result(true, "Removed %s (kept on the bench)" % display_name(attachment_def(att_id), att_id))


## Removes any installed finish (factory colour).
static func clear_finish(weapon_id: String) -> Dictionary:
	for att: Variant in fitted_attachments(weapon_id):
		if attachment_kind(str(att)) == "finish":
			return remove_attachment(weapon_id, str(att))
	return result(false, "Already the factory finish")


## Effective spec of an owned weapon with `attachments` applied (base spec when not owned).
static func spec_with(weapon_id: String, attachments: Array) -> Object:
	var base := weapon_def(weapon_id)
	if base == null:
		return null
	if attachments.is_empty() or not base.has_method("with_attachments"):
		return base
	return base.call("with_attachments", attachments) as Object


# --- appearance (clothing, wardrobe, barber) -------------------------------------------------

static func wardrobe() -> RefCounted:
	var sys := shops_system()
	if sys != null:
		var w: Variant = sys.get("wardrobe")
		if w is RefCounted:
			return w as RefCounted
	if _fallback_wardrobe == null and ResourceLoader.exists(WARDROBE_SCRIPT):
		_fallback_wardrobe = (load(WARDROBE_SCRIPT) as Script).new() as RefCounted
	return _fallback_wardrobe


static func player_appearance() -> Dictionary:
	var p := player()
	if p != null and p.has_method("get_appearance"):
		var a: Variant = p.call("get_appearance")
		if a is Dictionary:
			return (a as Dictionary).duplicate()
	return {}


static func player_body() -> String:
	return str(player_appearance().get("body", "m"))


## Part options of the character model (slot -> ids); {} when no visual is around.
static func part_options() -> Dictionary:
	var p := player()
	var v: Variant = obj_get(p, "visual", null)
	if v is Object and (v as Object).has_method("get_part_options"):
		var o: Variant = (v as Object).call("get_part_options")
		if o is Dictionary:
			return o as Dictionary
	return {}


static func _part_exists(slot: String, part: String, options: Dictionary) -> bool:
	if part == "" or (slot == "hair" and part == "bald"):
		return true
	if options.is_empty() or not options.has(slot):
		return true
	return (options[slot] as Array).has(part)


## Clothing defs of a slot that fit `body` and exist on the model (registry order).
static func clothing_defs(slot: String, body: String) -> Array:
	var options := part_options()
	var out: Array = []
	for d: Variant in Registry.all("clothing"):
		if not (d is Dictionary):
			continue
		var def := d as Dictionary
		if str(def.get("slot", "")) != slot:
			continue
		var b := str(def.get("body", ""))
		if b != "" and b != body:
			continue
		if not _part_exists(slot, str(def.get("part", "")), options):
			continue
		out.append(def)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return int(x.get("price", 0)) < int(y.get("price", 0)) or (int(x.get("price", 0)) == int(y.get("price", 0)) and str(x["id"]) < str(y["id"])))
	return out


## Hair / beard defs that exist on the model and fit the body.
static func hair_defs(slot: String, body: String) -> Array:
	var options := part_options()
	var out: Array = []
	for d: Variant in Registry.all("hair"):
		if not (d is Dictionary):
			continue
		var def := d as Dictionary
		if str(def.get("slot", "")) != slot:
			continue
		var b := str(def.get("body", ""))
		if b != "" and b != body:
			continue
		if not _part_exists(slot, str(def.get("part", "")), options):
			continue
		out.append(def)
	return out


static func owns_clothing(def_id: String) -> bool:
	var w := wardrobe()
	if w == null:
		return false
	w.call("ensure_seeded", player_appearance())
	return bool(w.call("owns", def_id))


## Appearance keys a clothing / hair def changes with `color` ("" keeps the current colour).
static func appearance_partial(def: Dictionary, color: String) -> Dictionary:
	var out := {str(def.get("slot", "")): str(def.get("part", ""))}
	var key := str(def.get("color_key", ""))
	if key != "" and color != "":
		out[key] = color
	var slot := str(def.get("slot", ""))
	if slot == "top" or slot == "bottom":
		out["outfit"] = ""          # a garment replaces any full outfit
	return out


static func is_wearing(def: Dictionary, a: Dictionary) -> bool:
	var slot := str(def.get("slot", ""))
	if (slot == "top" or slot == "bottom") and str(a.get("outfit", "")) != "":
		return false
	return str(a.get(slot, "")) == str(def.get("part", ""))


## Applies appearance keys to the player: CharacterVisual.apply_appearance (through
## Player.set_appearance, which emits EventBus.player_appearance_changed) and tells Wanted.
static func apply_player_appearance(partial: Dictionary) -> bool:
	var p := player()
	if p == null:
		return false
	var a := player_appearance()
	for k: Variant in partial.keys():
		a[k] = partial[k]
	if p.has_method("set_appearance"):
		p.call("set_appearance", a)
	else:
		var v: Variant = obj_get(p, "visual", null)
		if not (v is Object and (v as Object).has_method("apply_appearance")):
			return false
		(v as Object).call("apply_appearance", a)
		EventBus.player_appearance_changed.emit(a)
	if Wanted.has_method("note_appearance_change"):
		Wanted.call("note_appearance_change")
	return true


static func buy_clothing(def_id: String, color: String) -> Dictionary:
	var d: Variant = Registry.get_def("clothing", def_id)
	if not (d is Dictionary):
		return result(false, "Unknown item")
	var def := d as Dictionary
	var item_name := str(def.get("display_name", def_id))
	if owns_clothing(def_id):
		return wear_clothing(def_id, color)
	var cost := int(def.get("price", 0))
	if not charge("clothing", def_id, cost):
		return result(false, "Not enough money")
	var w := wardrobe()
	if w != null:
		w.call("add", def_id)
	apply_player_appearance(appearance_partial(def, color))
	return result(true, "Bought %s" % item_name, price(cost))


static func wear_clothing(def_id: String, color: String) -> Dictionary:
	var d: Variant = Registry.get_def("clothing", def_id)
	if not (d is Dictionary):
		return result(false, "Unknown item")
	var def := d as Dictionary
	if not owns_clothing(def_id):
		return result(false, "You do not own that")
	var a := player_appearance()
	var partial := appearance_partial(def, color)
	var same := true
	for k: Variant in partial.keys():
		if str(a.get(k, "")) != str(partial[k]):
			same = false
	if same:
		return result(false, "Already wearing it")
	apply_player_appearance(partial)
	return result(true, "Wearing %s" % str(def.get("display_name", def_id)))


static func haircut_price(def: Dictionary, color: String) -> int:
	var a := player_appearance()
	var slot := str(def.get("slot", "hair"))
	var cost := 0
	if str(a.get(slot, "")) != str(def.get("part", "")):
		cost += int(def.get("price", 0))
	var key := str(def.get("color_key", ""))
	if key != "" and color != "" and str(a.get(key, "")).to_lower() != color.to_lower():
		cost += COLOUR_FEE
	return cost


static func buy_haircut(def_id: String, color: String) -> Dictionary:
	var d: Variant = Registry.get_def("hair", def_id)
	if not (d is Dictionary):
		return result(false, "Unknown style")
	var def := d as Dictionary
	var cost := haircut_price(def, color)
	var a := player_appearance()
	var partial := appearance_partial(def, color)
	var same := true
	for k: Variant in partial.keys():
		if str(a.get(k, "")).to_lower() != str(partial[k]).to_lower():
			same = false
	if same:
		return result(false, "That is your current look")
	if not charge("haircut", def_id, cost):
		return result(false, "Not enough money")
	apply_player_appearance(partial)
	return result(true, "Fresh look: %s" % str(def.get("display_name", def_id)), price(cost))
