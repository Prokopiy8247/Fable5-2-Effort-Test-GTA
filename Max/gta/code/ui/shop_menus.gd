class_name ShopMenus
extends RefCounted
## Row builders for every store / service menu: Bulwark Arms (weapons, ammo, armour, gear)
## and its gunsmith workbench, Threadline (clothing) and the safehouse wardrobe, Fade Factory
## (barber), QuikNook 24 (snacks), Torque House Customs (repair / performance / cosmetics)
## and the safehouse itself. Previews are live; anything not paid for is reverted on leave.

const SHOPS := {
	"guns": {"title": "Bulwark Arms", "subtitle": "Firearms - ammunition - armour - outdoor gear", "accent": Color(1.0, 0.55, 0.15)},
	"workbench": {"title": "Bulwark Workbench", "subtitle": "Attachments and finishes", "accent": Color(1.0, 0.55, 0.15)},
	"clothes": {"title": "Threadline", "subtitle": "Clothing - try anything on, pay for what you keep", "accent": Color(0.2, 0.85, 0.95)},
	"wardrobe": {"title": "Wardrobe", "subtitle": "The Hideout", "accent": Color(0.45, 0.9, 0.6)},
	"barber": {"title": "Fade Factory", "subtitle": "Cuts, colour and beards", "accent": Color(1.0, 0.3, 0.3)},
	"market": {"title": "QuikNook 24", "subtitle": "Open all night", "accent": Color(0.3, 0.9, 0.45)},
	"mods": {"title": "Torque House Customs", "subtitle": "Repair - performance - looks", "accent": Color(1.0, 0.85, 0.2)},
	"safehouse": {"title": "The Hideout", "subtitle": "Safehouse", "accent": Color(0.45, 0.9, 0.6)},
}

const CLOTH_PRICES := {"shirt": 60, "sleeves": 25, "pants": 55, "legs": 35, "shoes": 75, "hat": 45, "hat_color": 15,
	"glasses": 90, "glasses_color": 15, "vest": 120, "extras": 40, "body": 0}
const HAIR_PRICES := {"hair": 35, "hair_color": 25, "beard": 20}
const MARKET := [
	["Gull Chips", 5, 10.0, "A salty bag of crisps. +10 health."],
	["Tide Cola", 6, 15.0, "Ice-cold and very sweet. +15 health, full stamina."],
	["Harbour Sandwich", 18, 35.0, "Tuna and pickles. +35 health."],
	["Night-shift Coffee", 4, 5.0, "Keeps you going. +5 health, full stamina."],
	["First-aid Kit", 120, 100.0, "Patches you up completely."],
]

static func describe(kind: String) -> Dictionary:
	return SHOPS.get(kind, {})

static func rows(kind: String, ui: UIManager, ctx: Dictionary) -> Array:
	match kind:
		"guns": return _guns(ui)
		"workbench": return _workbench_list(ui)
		"clothes": return _clothes(ui, ctx, false)
		"wardrobe": return _clothes(ui, ctx, true)
		"barber": return _barber(ui, ctx)
		"market": return _market(ui)
		"mods": return _mods(ui, ctx)
		"safehouse": return _safehouse(ui, ctx)
	return []

## Called by the UI manager when a shop menu closes (reverts unpaid previews).
static func on_close(kind: String, ctx: Dictionary) -> void:
	var p: Player = Game.player
	if p == null:
		return
	match kind:
		"clothes", "barber", "wardrobe":
			if ctx.has("orig") and not bool(ctx.get("paid", false)):
				p.set_appearance((ctx["orig"] as Dictionary).duplicate(true))
		"mods":
			var v: Vehicle = ctx.get("vehicle")
			if v != null and is_instance_valid(v) and ctx.has("installed"):
				_restore_vehicle(v, ctx)

static func _money(n: int) -> String:
	return "FREE" if n <= 0 or Game.cheats["free_shopping"] else "$" + HUD._commas(n)

static func _pay(n: int) -> bool:
	if n <= 0:
		return true
	if Game.spend(n):
		Audio.play_ui(&"ui_buy", -6.0)
		return true
	return false

# ---------------------------------------------------------------- Bulwark Arms
static func _guns(ui: UIManager) -> Array:
	var rows: Array = [{"text": "Weapons", "header": true}]
	for slot in range(0, 8):
		var ids: Array = []
		for id in WeaponDB.ORDER:
			if id != &"unarmed" and int(WeaponDB.get_w(id)["slot"]) == slot:
				ids.append(id)
		if ids.is_empty():
			continue
		rows.append({"text": String(WeaponDB.SLOT_NAMES[slot]), "right": "%d" % ids.size(), "page": func() -> Array: return _gun_page(ui, ids)})
	rows.append({"text": "Supplies", "header": true})
	rows.append({"text": "Ammunition", "desc": "Refill every weapon you own, one box at a time or all at once.", "page": func() -> Array: return _ammo_page(ui)})
	rows.append({"text": "Body armour", "page": func() -> Array: return _armour_page(ui)})
	rows.append({"text": "Outdoor gear", "desc": "Parachute and diving equipment.", "page": func() -> Array: return _gear_page(ui)})
	rows.append({"text": "Gunsmith workbench", "desc": "Suppressors, optics, grips, extended magazines and finishes for the guns you own.",
		"page": func() -> Array: return _workbench_list(ui)})
	rows.append({"text": "Leave", "fn": func() -> void: ui.menu.close()})
	return rows

static func _stat_line(id: StringName) -> String:
	var w := WeaponDB.get_w(id)
	if not WeaponDB.is_gun(id):
		if w["cls"] == &"thrown":
			return "Thrown explosive. Hold G (or fire with it selected) to cook and throw."
		return "Damage %d, heavy attack %d. Melee weapons never need ammo." % [int(w["dmg"]), int(w.get("heavy", 0))]
	var dmg := float(w["dmg"])
	if w.has("projectile"):
		return "Explosive launcher. Magazine %d, carries up to %d." % [int(w["mag"]), int(w["reserve"])]
	return "Damage %d   Rate %d rpm   Magazine %d   Range %d m%s" % [int(dmg) * int(w.get("pellets", 1)), int(w.get("rpm", 0)),
		int(w["mag"]), int(w["range"]), ("   Fully automatic" if bool(w.get("auto", false)) else "")]

static func _gun_page(ui: UIManager, ids: Array) -> Array:
	var p: Player = Game.player
	var rows: Array = []
	for id: StringName in ids:
		var w := WeaponDB.get_w(id)
		var owned := p.inventory.has(id)
		var price := int(w.get("price", 0))
		if owned:
			rows.append({"text": String(w["name"]), "right": "Owned", "right_color": Color(0.6, 0.9, 1.0), "desc": _stat_line(id) + "\nSelect to equip it.",
				"fn": func() -> void:
					p.gunner.equip(id)
					Game.notify("%s equipped" % String(w["name"]), "info")})
		else:
			rows.append({"text": String(w["name"]), "right": _money(price), "desc": _stat_line(id),
				"fn": func() -> void:
					if _pay(price):
						p.inventory.give(id)
						p.gunner.equip(id)
						Events.shop_purchase.emit("guns", String(id), price)
						Game.notify("Bought %s" % String(w["name"]), "money")})
	rows.append({"text": "Back", "fn": func() -> void: ui.menu.back()})
	return rows

static func _ammo_pack(id: StringName) -> int:
	var w := WeaponDB.get_w(id)
	if w["cls"] == &"thrown":
		return 1
	return maxi(int(w.get("mag", 1)) * 2, 1)

static func _ammo_page(ui: UIManager) -> Array:
	var p: Player = Game.player
	var rows: Array = []
	var total := 0
	for id in p.inventory.owned():
		var w := WeaponDB.get_w(id)
		if not (WeaponDB.is_gun(id) or w["cls"] == &"thrown"):
			continue
		var cap := int(w.get("reserve", 0))
		var have := p.inventory.reserve(id)
		var pack := mini(_ammo_pack(id), cap - have)
		var price := int(w.get("ammo_price", 50))
		var full := have >= cap
		if not full:
			var packs_needed := int(ceil(float(cap - have) / float(_ammo_pack(id))))
			total += packs_needed * price
		rows.append({"text": "%s  +%d" % [String(w["name"]), maxi(pack, 0)], "right": "Full" if full else _money(price),
			"off": full, "desc": "%d / %d rounds carried." % [have, cap],
			"fn": func() -> void:
				if _pay(price):
					p.inventory.add_ammo(id, _ammo_pack(id))
					p.inventory.changed.emit()
					Audio.play_ui(&"ui_ammo", -6.0)})
	if rows.is_empty():
		rows.append({"text": "You do not own any guns yet", "info": true})
	else:
		rows.push_front({"text": "Fill everything", "right": _money(total), "off": total <= 0,
			"fn": func() -> void:
				if _pay(total):
					for id2 in p.inventory.owned():
						var w2 := WeaponDB.get_w(id2)
						if WeaponDB.is_gun(id2) or w2["cls"] == &"thrown":
							p.inventory.add_ammo(id2, int(w2.get("reserve", 0)))
					p.inventory.changed.emit()
					Audio.play_ui(&"ui_ammo", -6.0)})
	rows.append({"text": "Back", "fn": func() -> void: ui.menu.back()})
	return rows

static func _armour_page(ui: UIManager) -> Array:
	var p: Player = Game.player
	var rows: Array = []
	for e in [["Light vest", 50.0, 450], ["Heavy plate carrier", 100.0, 1100]]:
		var amount: float = e[1]
		var price: int = e[2]
		var useful := p.armor < amount - 0.5
		rows.append({"text": String(e[0]), "right": _money(price) if useful else "Already wearing", "off": not useful,
			"desc": "Armour soaks most bullet, blast and melee damage until it is used up (%d points)." % int(amount),
			"fn": func() -> void:
				if _pay(price):
					p.armor = maxf(p.armor, amount)
					Audio.play_ui(&"ui_armor", -4.0)})
	rows.append({"text": "Back", "fn": func() -> void: ui.menu.back()})
	return rows

static func _gear_page(ui: UIManager) -> Array:
	var p: Player = Game.player
	return [
		{"text": "Parachute", "right": "Owned" if p.inventory.has_parachute else _money(300), "off": p.inventory.has_parachute,
			"desc": "Jump from a height or bail out of an aircraft, then press Space to deploy.",
			"fn": func() -> void:
				if _pay(300):
					p.inventory.has_parachute = true
					Game.notify("Parachute packed", "money")},
		{"text": "Scuba kit", "right": "Owned" if p.inventory.has_scuba else _money(1200), "off": p.inventory.has_scuba,
			"desc": "Mask and tank: stay under water without running out of breath.",
			"fn": func() -> void:
				if _pay(1200):
					p.inventory.has_scuba = true
					p.scuba = true
					Game.notify("Scuba kit bought - it is used automatically when you dive", "money")},
		{"text": "Back", "fn": func() -> void: ui.menu.back()},
	]

static func _workbench_list(ui: UIManager) -> Array:
	var p: Player = Game.player
	var rows: Array = []
	for id in p.inventory.owned():
		if not WeaponDB.is_gun(id):
			continue
		var w := WeaponDB.get_w(id)
		var n_att := (p.inventory.atts(id)).size()
		rows.append({"text": String(w["name"]), "right": ("%d fitted" % n_att) if n_att > 0 else "",
			"page": func() -> Array: return _workbench_page(ui, id)})
	if rows.is_empty():
		rows.append({"text": "Buy a gun first", "info": true})
	rows.append({"text": "Back", "fn": func() -> void: ui.menu.back()})
	return rows

static func _workbench_page(ui: UIManager, id: StringName) -> Array:
	var p: Player = Game.player
	var w := WeaponDB.get_w(id)
	var rows: Array = [{"text": "Attachments", "header": true}]
	var allowed: Array = w.get("atts", [])
	if allowed.is_empty():
		rows.append({"text": "No attachments fit this weapon", "info": true})
	for att: String in allowed:
		var a: Dictionary = WeaponDB.ATT[att]
		var fitted := p.inventory.has_att(att, id)
		var price := int(a["price"])
		rows.append({"text": String(a["name"]), "right": "Fitted - remove" if fitted else _money(price),
			"right_color": Color(0.6, 0.9, 1.0) if fitted else Color(0.6, 0.95, 0.65), "desc": _att_desc(att),
			"fn": func() -> void:
				if fitted:
					p.inventory.remove_att(id, att)
				elif _pay(price):
					p.inventory.add_att(id, att)
					Events.shop_purchase.emit("workbench", att, price)
				if p.gunner.weapon_id == id:
					p.gunner.refresh_model()})
	rows.append({"text": "Finish", "header": true})
	var cur := int(p.inventory.items[id]["tint"]) if p.inventory.items.has(id) else 0
	for i in WeaponDB.TINTS.size():
		var t: Dictionary = WeaponDB.TINTS[i]
		var price2 := int(t["price"])
		rows.append({"text": String(t["name"]), "swatch": Color.html(String(t["metal"])), "right": "Current" if i == cur else _money(price2),
			"fn": func() -> void:
				if i != cur and _pay(price2):
					p.inventory.set_tint(id, i)
					if p.gunner.weapon_id == id:
						p.gunner.refresh_model()})
	rows.append({"text": "Back", "fn": func() -> void: ui.menu.back()})
	return rows

static func _att_desc(att: String) -> String:
	match att:
		"suppressor": return "Much quieter shots: nearby people may not even notice. Slightly less damage and range."
		"extmag": return "50% more rounds per magazine."
		"reddot": return "Reflex sight: tighter aimed spread and a little zoom."
		"scope": return "4x magnified optic for long shots."
		"grip": return "Foregrip: less recoil and spread."
		"flashlight": return "Under-barrel light, switched on while aiming in the dark."
	return ""

# ---------------------------------------------------------------- Threadline / wardrobe
static func _ensure_draft(ctx: Dictionary) -> Dictionary:
	var p: Player = Game.player
	if not ctx.has("orig"):
		ctx["orig"] = p.appearance.duplicate(true)
		ctx["draft"] = p.appearance.duplicate(true)
		ctx["paid"] = false
	return ctx["draft"]

static func _cost(ctx: Dictionary, prices: Dictionary) -> int:
	var o: Dictionary = ctx["orig"]
	var d: Dictionary = ctx["draft"]
	var total := 0
	for k in prices.keys():
		if str(o.get(k, "")) != str(d.get(k, "")):
			total += int(prices[k])
	return total

static func _opt_row(ui: UIManager, ctx: Dictionary, label: String, key: String, values: Array, names: Array, swatches := false) -> Dictionary:
	var d: Dictionary = ctx["draft"]
	var cur := values.find(d.get(key, values[0]))
	var row := {"text": label, "opts": names, "idx": maxi(cur, 0),
		"on_opt": func(i: int) -> void:
			d[key] = values[i]
			Game.player.set_appearance(d.duplicate(true))
			ui.menu.refresh()}
	if swatches:
		row["swatch"] = Color.html(String(values[maxi(cur, 0)]))
	return row

static func _numbered(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append("%d / %d" % [i + 1, n])
	return out

static func _clothes(ui: UIManager, ctx: Dictionary, free: bool) -> Array:
	var d := _ensure_draft(ctx)
	var female := String(d.get("body", "male")) == "female"
	var rows: Array = []
	if free:
		rows.append({"text": "Body", "header": true})
		rows.append(_opt_row(ui, ctx, "Body type", "body", ["male", "female"], ["Masculine", "Feminine"]))
		rows.append(_opt_row(ui, ctx, "Skin tone", "skin", Appearance.SKINS, _numbered(Appearance.SKINS.size()), true))
	rows.append({"text": "Tops", "header": true})
	rows.append(_opt_row(ui, ctx, "Shirt / jacket colour", "shirt", Appearance.SHIRTS, _numbered(Appearance.SHIRTS.size()), true))
	rows.append(_opt_row(ui, ctx, "Sleeves", "sleeves", ["short", "long"], ["Short", "Long"]))
	rows.append(_opt_row(ui, ctx, "Vest", "vest", ["", "vest_safety"], ["None", "Hi-vis"]))
	rows.append({"text": "Bottoms", "header": true})
	rows.append(_opt_row(ui, ctx, "Trousers colour", "pants", Appearance.PANTS, _numbered(Appearance.PANTS.size()), true))
	rows.append(_opt_row(ui, ctx, "Length", "legs", ["long", "short"], ["Full length", "Shorts"]))
	if female:
		rows.append({"text": "Skirt", "opts": ["No", "Yes"], "idx": 1 if (d.get("extras", []) as Array).has("skirt") else 0,
			"on_opt": func(i: int) -> void:
				var ex: Array = (d.get("extras", []) as Array).duplicate()
				ex.erase("skirt")
				if i == 1:
					ex.append("skirt")
				d["extras"] = ex
				Game.player.set_appearance(d.duplicate(true))
				ui.menu.refresh()})
	rows.append(_opt_row(ui, ctx, "Shoes", "shoes", Appearance.SHOES, _numbered(Appearance.SHOES.size()), true))
	rows.append({"text": "Accessories", "header": true})
	rows.append(_opt_row(ui, ctx, "Hat", "hat", ["", "cap", "beanie", "hat_brim"], ["None", "Cap", "Beanie", "Wide brim"]))
	rows.append(_opt_row(ui, ctx, "Hat colour", "hat_color", Appearance.SHIRTS, _numbered(Appearance.SHIRTS.size()), true))
	rows.append(_opt_row(ui, ctx, "Glasses", "glasses", ["", "glasses", "sunglasses"], ["None", "Glasses", "Sunglasses"]))
	rows.append(_opt_row(ui, ctx, "Frame colour", "glasses_color", ["17181b", "c9a24a", "f2f0ea", "d43d33", "2f6fd0"], _numbered(5), true))
	rows.append({"text": "Checkout", "header": true})
	var cost := 0 if free else _cost(ctx, CLOTH_PRICES)
	if free:
		rows.append({"text": "Keep this outfit", "fn": func() -> void:
			ctx["paid"] = true
			ctx["orig"] = d.duplicate(true)
			Game.notify("Outfit changed", "good")
			ui.menu.close()})
	else:
		rows.append({"text": "Pay and wear", "right": _money(cost), "off": cost <= 0, "desc": "Only the pieces you changed are charged.",
			"fn": func() -> void:
				if _pay(cost):
					ctx["paid"] = true
					ctx["orig"] = d.duplicate(true)
					Events.shop_purchase.emit("clothes", "outfit", cost)
					Game.notify("Looking sharp", "money")
					ui.menu.close()})
	rows.append({"text": "Cancel", "desc": "Put everything back.", "fn": func() -> void: ui.menu.close()})
	return rows

# ---------------------------------------------------------------- Fade Factory
static func _barber(ui: UIManager, ctx: Dictionary) -> Array:
	var d := _ensure_draft(ctx)
	var female := String(d.get("body", "male")) == "female"
	var styles: Array = (Appearance.HAIR_STYLES_F if female else Appearance.HAIR_STYLES_M).duplicate()
	if not styles.has(String(d.get("hair", ""))):
		styles.append(String(d.get("hair", "")))
	var names: Array = []
	for st: String in styles:
		names.append("Shaved" if st == "" else st.trim_prefix("hair_").capitalize())
	var rows: Array = [{"text": "Hair", "header": true}]
	rows.append(_opt_row(ui, ctx, "Style", "hair", styles, names))
	rows.append(_opt_row(ui, ctx, "Colour", "hair_color", Appearance.HAIRS, _numbered(Appearance.HAIRS.size()), true))
	if not female:
		rows.append({"text": "Face", "header": true})
		rows.append(_opt_row(ui, ctx, "Facial hair", "beard", Appearance.BEARDS, ["Clean shaven", "Beard", "Moustache"]))
	var cost := _cost(ctx, HAIR_PRICES)
	rows.append({"text": "Checkout", "header": true})
	rows.append({"text": "Pay", "right": _money(cost), "off": cost <= 0,
		"fn": func() -> void:
			if _pay(cost):
				ctx["paid"] = true
				ctx["orig"] = d.duplicate(true)
				Events.shop_purchase.emit("barber", "cut", cost)
				Game.notify("Fresh cut", "money")
				ui.menu.close()})
	rows.append({"text": "Cancel", "fn": func() -> void: ui.menu.close()})
	return rows

# ---------------------------------------------------------------- QuikNook 24
static func _market(ui: UIManager) -> Array:
	var p: Player = Game.player
	var rows: Array = []
	for item in MARKET:
		var price: int = item[1]
		var heal: float = item[2]
		rows.append({"text": String(item[0]), "right": _money(price), "desc": String(item[3]),
			"fn": func() -> void:
				if _pay(price):
					p.heal(heal)
					if heal <= 15.0:
						p.stamina = p.max_stamina()
					Audio.play_ui(&"ui_eat", -4.0)})
	rows.append({"text": "Scratch card", "right": _money(10), "desc": "Win up to $2,500. Probably not.",
		"fn": func() -> void:
			if _pay(10):
				var r := randf()
				var win := 2500 if r < 0.004 else (250 if r < 0.03 else (40 if r < 0.12 else (10 if r < 0.3 else 0)))
				if win > 0:
					Game.add_cash(win)
					Game.notify("Scratch card: you won $%d!" % win, "money")
				else:
					Game.notify("Scratch card: no luck", "info")})
	rows.append({"text": "Leave", "fn": func() -> void: ui.menu.close()})
	return rows

# ---------------------------------------------------------------- Torque House Customs
static func _snapshot_vehicle(v: Vehicle, ctx: Dictionary) -> void:
	if ctx.has("installed"):
		return
	ctx["installed"] = v.mods.duplicate(true)
	ctx["paint"] = [v.paint_a, v.paint_b, v.finish]

static func _restore_one(v: Vehicle, ctx: Dictionary, cat: String) -> void:
	var inst: Dictionary = ctx["installed"]
	if inst.has(cat):
		VehicleMods.apply(v, cat, inst[cat])
		return
	var c: Dictionary = VehicleMods.CATS[cat]
	match String(c["type"]):
		"level":
			VehicleMods.apply(v, cat, 0)
		"part":
			VehicleMods.apply(v, cat, "")
		_:
			var pa: Array = ctx["paint"]
			match cat:
				"paint", "paint2", "finish":
					v.set_paint(pa[0], pa[1], pa[2])
				"neon":
					VehicleMods.apply(v, cat, "off")
				"lights":
					VehicleMods.apply(v, cat, "stock")
				"wheel_color":
					VehicleMods.apply(v, cat, "c3c7cb")
				_:
					pass
			v.mods.erase(cat)

static func _restore_vehicle(v: Vehicle, ctx: Dictionary) -> void:
	for cat in VehicleMods.ORDER:
		var inst: Dictionary = ctx["installed"]
		if str(v.mods.get(cat, "<none>")) != str(inst.get(cat, "<none>")):
			_restore_one(v, ctx, cat)

static func repair_price(v: Vehicle) -> int:
	var dmg := 1.0 - clampf(v.health / v.max_health, 0.0, 1.0)
	var glass := 1.0 - clampf(v.glass_health / 100.0, 0.0, 1.0)
	var tyres := 0
	if v is Car:
		for w in (v as Car).wheels:
			if w["punctured"]:
				tyres += 1
	return int(ceil(dmg * 1800.0 + glass * 250.0 + float(tyres) * 120.0)) + (40 if v.dirt > 0.2 else 0)

static func _mods(ui: UIManager, ctx: Dictionary) -> Array:
	var v: Vehicle = ctx.get("vehicle")
	if v == null or not is_instance_valid(v) or v.destroyed:
		return [{"text": "Drive a vehicle into the bay", "info": true}, {"text": "Leave", "fn": func() -> void: ui.menu.close()}]
	_snapshot_vehicle(v, ctx)
	var rows: Array = [{"text": String(v.def.get("name", v.vid)), "header": true}]
	var rp := repair_price(v)
	rows.append({"text": "Repair and wash", "right": "Like new" if rp <= 0 else _money(rp), "off": rp <= 0,
		"desc": "Body, glass, tyres and paint restored.",
		"fn": func() -> void:
			if _pay(rp):
				v.repair()
				v.dirt = 0.0
				Audio.play_ui(&"ui_repair", -4.0)
				Game.notify("Repaired", "money")})
	if not VehicleMods.compatible(v):
		rows.append({"text": "This vehicle cannot be modified here", "info": true})
		rows.append({"text": "Leave", "fn": func() -> void: ui.menu.close()})
		return rows
	var group := ""
	for cat: String in VehicleMods.ORDER:
		var c: Dictionary = VehicleMods.CATS[cat]
		var g := String(c.get("group", ""))
		if g != group:
			group = g
			rows.append({"text": g, "header": true})
		var cur: Variant = (ctx["installed"] as Dictionary).get(cat, null)
		rows.append({"text": String(c["name"]), "right": _mod_label(cat, cur), "right_color": Color(0.7, 0.76, 0.84),
			"page": func() -> Array: return _mod_page(ui, v, ctx, cat),
			"on_leave": func() -> void: _restore_one(v, ctx, cat)})
	rows.append({"text": "Done", "fn": func() -> void: ui.menu.close()})
	return rows

static func _mod_label(cat: String, value: Variant) -> String:
	var c: Dictionary = VehicleMods.CATS[cat]
	if value == null:
		return "Stock"
	match String(c["type"]):
		"level":
			return "Stock" if int(value) <= 0 else "Level %d" % int(value)
		"part":
			return "Stock" if String(value) == "" else String(value).replace("_", " ").capitalize()
	if cat in ["paint", "paint2", "wheel_color"]:
		return "#" + String(value)
	return String(value).capitalize()

static func _mod_page(ui: UIManager, v: Vehicle, ctx: Dictionary, cat: String) -> Array:
	var c: Dictionary = VehicleMods.CATS[cat]
	var rows: Array = []
	var values: Array = []
	match String(c["type"]):
		"level":
			for i in (c["prices"] as Array).size():
				values.append(i)
		_:
			values = (c["options"] as Array).duplicate()
	var installed: Variant = (ctx["installed"] as Dictionary).get(cat, null)
	for val: Variant in values:
		var is_cur := str(installed) == str(val) or (installed == null and (str(val) == "0" or str(val) == "" or str(val) == "stock" or str(val) == "off"))
		var ok := VehicleMods.available(v, cat, val)
		var price := VehicleMods.price(cat, val)
		var row := {"text": _mod_label(cat, val), "right": "Installed" if is_cur else (_money(price) if ok else "Not available"),
			"off": not ok, "right_color": Color(0.6, 0.9, 1.0) if is_cur else Color(0.6, 0.95, 0.65),
			"hover": func() -> void: VehicleMods.apply(v, cat, val),
			"fn": func() -> void:
				if is_cur:
					return
				if _pay(price):
					VehicleMods.apply(v, cat, val)
					(ctx["installed"] as Dictionary)[cat] = val
					v.personal = true
					if v.owner_tag != "player":
						v.owner_tag = "player"
					Events.shop_purchase.emit("mods", cat, price)
					Audio.play_ui(&"ui_repair", -6.0)
					if cat in ["paint", "paint2", "finish"] and Game.wanted != null and Game.wanted.can_lose_by_disguise():
						Game.wanted.clear()
						Game.notify("New paint job - the police lost your description", "good")
					ui.menu.back()}
		if cat in ["paint", "paint2", "wheel_color"]:
			row["swatch"] = Color.html(String(val))
		elif cat == "neon":
			row["swatch"] = VehicleMods.NEON.get(String(val), Color.BLACK)
		if String(c["group"]) == "Performance":
			row["desc"] = _perf_desc(cat)
		rows.append(row)
	rows.append({"text": "Back", "fn": func() -> void: ui.menu.back()})
	return rows

static func _perf_desc(cat: String) -> String:
	match cat:
		"engine": return "More power at every speed."
		"transmission": return "Quicker shifts: better acceleration."
		"turbo": return "A big boost to acceleration and top speed."
		"brakes": return "Shorter stopping distances."
		"suspension": return "Lower, stiffer and grippier."
		"armor": return "Reinforced body: takes more punishment before catching fire."
		"bp_tires": return "Tyres that survive bullets and spike strips."
	return ""

# ---------------------------------------------------------------- safehouse
static func _safehouse(ui: UIManager, ctx: Dictionary) -> Array:
	var p: Player = Game.player
	var rows: Array = [
		{"text": "Sleep", "desc": "Skip ahead 6 hours, wake up fully healed. The game is saved to the quick slot.", "fn": func() -> void:
			ui.menu.close()
			sleep(6.0)},
		{"text": "Save game", "page": func() -> Array: return ui._slot_rows(true)},
		{"text": "Wardrobe", "desc": "Change clothes and body type for free.", "fn": func() -> void:
			ui.menu.close()
			ui.open_shop.call_deferred("wardrobe")},
	]
	if Game.garage != null and Game.garage.has_method("menu_rows"):
		rows.append({"text": "Garage", "page": func() -> Array: return Game.garage.menu_rows(ui)})
	rows.append({"text": "Leave", "fn": func() -> void: ui.menu.close()})
	return rows

static func sleep(hours: float) -> void:
	var p: Player = Game.player
	if Game.hud != null:
		Game.hud.fade_to(1.0, 0.8)
	await Game.get_tree().create_timer(0.9, true, false, true).timeout
	if Game.time != null:
		Game.time.advance_hours(hours)
	p.heal(p.max_health)
	p.stamina = p.max_stamina()
	if Game.wanted == null or Game.wanted.level == 0:
		SaveSystem.save_game("quick")
	if Game.hud != null:
		Game.hud.fade_to(0.0, 1.2)
	Game.notify("You slept until %s" % (Game.time.clock_text() if Game.time else "later"), "good")
