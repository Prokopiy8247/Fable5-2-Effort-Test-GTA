extends Node3D
## World interaction points (shops, safehouse, garage, elevator, hospital, ATM...), pickups / loot drops
## and all shop menus (weapons, weapon workbench, clothing, barber, convenience store, vehicle mod shop).

var menu: MenuPanel
var pickups: Array = []
var current := {}
var garage: Array = []
var atm_day := -1
var shop_cam_t := 0.0
var preview_backup := {}


func _ready() -> void:
	menu = MenuPanel.new()
	add_child(menu)
	if G.world:
		for p in G.world.pickups:
			drop(p.kind, p.pos, p, true)


# ------------------------------------------------------------------ pickups
func drop(kind: String, pos: Vector3, data: Dictionary = {}, permanent: bool = false) -> void:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	match kind:
		"cash": mi.mesh = Assets.mesh("props/vfx_kit", "pickup_money")
		"health": mi.mesh = Assets.mesh("props/vfx_kit", "pickup_health")
		"armor": mi.mesh = Assets.mesh("props/vfx_kit", "pickup_armor")
		"ammo": mi.mesh = Assets.mesh("props/vfx_kit", "pickup_ammo")
		"parachute": mi.mesh = Assets.mesh("characters/char_parts", "Parachute_Pack")
		"scuba": mi.mesh = Assets.mesh("characters/char_parts", "Scuba_Tank")
		"weapon":
			var wm := Weapons.make_model(String(data.get("weapon", "pistol")))
			if wm:
				n.add_child(wm)
				wm.rotation.z = PI * 0.5
			mi.free()
			mi = null
	if mi:
		n.add_child(mi)
		if kind in ["parachute", "scuba"]:
			mi.position = Vector3(0, -0.1, 0.2)
	add_child(n)
	var h := G.ray(pos + Vector3(0, 0.8, 0), pos - Vector3(0, 6.0, 0), G.L_WORLD) if not permanent and pos.y > G.WATER_LEVEL else {}
	n.global_position = (h.position + Vector3(0, 0.55, 0)) if not h.is_empty() else pos
	pickups.append({"node": n, "kind": kind, "data": data, "t": randf() * 6.0, "life": 9999.0 if permanent else 75.0, "permanent": permanent, "respawn": 0.0, "base_y": n.global_position.y})


func _collect(pk: Dictionary) -> bool:
	var p: Player = G.player
	var d: Dictionary = pk.data
	match String(pk.kind):
		"cash":
			var amt := int(d.get("amount", 50))
			p.add_money(amt)
			G.say("+%s" % G.fmt_money(amt), Color(0.6, 1.0, 0.6))
		"health":
			if p.health >= p.max_health:
				return false
			p.heal(60.0)
			G.say("Health restored", Color(0.6, 1.0, 0.6))
		"armor":
			if p.armor >= 100.0:
				return false
			p.armor = 100.0
			G.say("Body armor equipped", Color(0.5, 0.75, 1.0))
		"ammo":
			for at in p.inv.ammo.keys():
				p.inv.add_ammo(at, int(Defs.AMMO[at].box))
			G.say("Ammunition picked up", UIKit.GOLD)
		"parachute":
			if p.has_parachute:
				return false
			p.give_parachute()
			G.say("Parachute equipped  -  jump from height and press SPACE", Color(0.8, 0.95, 1.0))
		"scuba":
			if p.has_scuba:
				return false
			p.give_scuba(true)
			G.say("Scuba set equipped  -  much longer dives", Color(0.6, 0.9, 1.0))
		"weapon":
			var wid := String(d.get("weapon", "pistol"))
			var is_new: bool = p.inv.give(wid, true)
			G.say(("Picked up %s" if is_new else "%s ammo") % Defs.WEAPONS[wid].name, UIKit.GOLD)
			if is_new and p.inv.current == "fists":
				p.equip(wid)
	Sfx.play("pickup", p.global_position)
	return true


# ------------------------------------------------------------------ per-frame proximity
func _process(delta: float) -> void:
	var p: Player = G.player
	if p == null or G.world == null:
		return
	var pp := p.global_position_now()
	var i := pickups.size() - 1
	while i >= 0:
		var pk: Dictionary = pickups[i]
		var n: Node3D = pk.node
		if float(pk.respawn) > 0.0:
			pk.respawn = float(pk.respawn) - delta
			if float(pk.respawn) <= 0.0:
				n.visible = true
			i -= 1
			continue
		pk.t = float(pk.t) + delta
		pk.life = float(pk.life) - delta
		n.rotation.y = float(pk.t) * 1.6
		n.global_position.y = float(pk.base_y) + sin(float(pk.t) * 2.2) * 0.08
		if n.global_position.distance_to(pp + Vector3(0, 0.7, 0)) < (1.5 if p.vehicle == null else 2.6) and not p.dead:
			if _collect(pk):
				if pk.permanent:
					n.visible = false
					pk.respawn = 180.0
				else:
					n.queue_free()
					pickups.remove_at(i)
		elif float(pk.life) <= 0.0:
			n.queue_free()
			pickups.remove_at(i)
		i -= 1
	# interaction prompt
	current = {}
	if G.ui_blocking == 0 and not p.dead and p.st in [p.St.FOOT, p.St.VEHICLE]:
		var best := 1e9
		for it in G.world.interacts:
			var need_vehicle: bool = it.data.get("vehicle", false)
			if need_vehicle != (p.vehicle != null):
				continue
			var d: float = pp.distance_to(it.pos)
			if it.kind == "range" and G.main.has_node("Activities") and G.main.get_node("Activities").range_on:
				continue
			if d < float(it.radius) and d < best and absf(pp.y - (it.pos as Vector3).y) < 2.5:
				best = d
				current = it
		if current.is_empty() and p.vehicle == null:
			var v := p.nearest_vehicle(3.6)
			if v != null and G.hud:
				G.hud.prompt_text = "[F]  %s %s" % ["Steal" if v.driver != null else "Enter", v.def.name]
			elif G.hud:
				G.hud.prompt_text = ""
		elif G.hud:
			G.hud.prompt_text = ("[E]  " + String(current.prompt)) if not current.is_empty() else ""
	elif G.hud:
		G.hud.prompt_text = ""


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("interact") and not current.is_empty() and G.ui_blocking == 0:
		activate(String(current.kind))
		get_viewport().set_input_as_handled()


func activate(kind: String) -> void:
	var p: Player = G.player
	match kind:
		"gunshop": open_gunshop()
		"gunbench": open_gunbench()
		"clothes": open_clothes(false)
		"wardrobe": open_clothes(true)
		"barber": open_barber()
		"store": open_store()
		"modshop": open_modshop()
		"garage": open_garage()
		"range":
			if G.main.has_node("Activities"):
				G.main.get_node("Activities").start_range()
		"bed":
			if G.wanted and G.wanted.level > 0:
				G.say("You can't rest while wanted", Color(1, 0.5, 0.4))
				return
			await G.hud.fade(true, 0.6)
			if G.timew:
				G.timew.set_time(G.timew.time + 8.0)
			p.health = p.max_health
			Save.save_game()
			G.hud.fade(false, 0.8)
			G.say("Game saved  -  you slept 8 hours", Color(0.6, 1.0, 0.6))
		"hospital":
			if p.health >= p.max_health:
				G.say("You are in perfect health", UIKit.DIM)
			elif p.spend(150):
				p.health = p.max_health
				G.say("Patched up", Color(0.6, 1.0, 0.6))
		"atm":
			var day := int(G.timew.time / 24.0) if G.timew else 0
			var stamp := Time.get_ticks_msec() / 600000
			if atm_day != stamp:
				atm_day = stamp
				p.add_money(500)
				G.say("ATM: collected $500 odd-jobs payout (every 10 minutes)", Color(0.6, 1.0, 0.6))
				Sfx.ui("buy")
			else:
				G.say("ATM: balance %s  -  next payout soon" % G.fmt_money(p.money), UIKit.DIM)
			if day < 0:
				pass
		"elevator_up", "elevator_down":
			await G.hud.fade(true, 0.35)
			var poi: Dictionary = G.world.pois["tower"]
			p.teleport(poi.roof if kind == "elevator_up" else poi.pos + Vector3(-1.5, 0.2, 0), 0.0)
			Sfx.ui("select")
			G.hud.fade(false, 0.4)


# ------------------------------------------------------------------ weapon shop
func open_gunshop() -> void:
	menu.open("Brass Lantern Arms", func(m: MenuPanel):
		var items: Array = []
		for slot in Defs.SLOTS:
			items.append({"text": Defs.SLOT_NAMES[slot], "right": ">", "fn": _gun_cat.bind(slot), "no_refresh": true})
		items.append({"text": "Ammunition", "right": ">", "fn": _ammo_menu, "no_refresh": true})
		items.append({"text": "Body armor", "right": "$800", "fn": func():
			if G.player.armor >= 100.0:
				G.say("Armor already full", UIKit.DIM)
			elif G.player.spend(800):
				G.player.armor = 100.0})
		items.append({"text": "Weapon workbench", "right": ">", "fn": open_gunbench, "no_refresh": true})
		m.set_items(items), {"sub": "Cash %s" % G.fmt_money(G.player.money)})


func _gun_cat(slot: String) -> void:
	menu.open(Defs.SLOT_NAMES[slot], func(m: MenuPanel):
		var items: Array = []
		var p: Player = G.player
		for wid in Defs.WEAPON_ORDER:
			var d: Dictionary = Defs.WEAPONS[wid]
			if d.slot != slot or wid == "fists":
				continue
			var owned: bool = p.inv.owned.has(wid)
			var desc := "Damage %d   Rate %.0f/min   Mag %d" % [int(d.dmg) * int(d.get("pellets", 1)), 60.0 / float(d.rate), int(d.get("mag", 0))]
			if owned and d.has("ammo"):
				var a: Dictionary = Defs.AMMO[d.ammo]
				items.append({"text": d.name + "  (owned)", "right": "ammo $%d" % int(a.price), "desc": desc, "fn": func():
					if p.spend(int(a.price)):
						p.inv.add_ammo(d.ammo, int(a.box))})
			elif owned:
				items.append({"text": d.name, "right": "OWNED", "disabled": true})
			else:
				items.append({"text": d.name, "right": "$%d" % int(d.price), "desc": desc, "fn": func():
					if p.spend(int(d.price)):
						p.inv.give(wid, true)
						p.equip(wid)
						G.say("Purchased %s" % d.name, UIKit.GOLD)})
		m.set_items(items), {"sub": "Cash %s" % G.fmt_money(G.player.money)})


func _ammo_menu() -> void:
	menu.open("Ammunition", func(m: MenuPanel):
		var items: Array = []
		var p: Player = G.player
		for at in Defs.AMMO.keys():
			var a: Dictionary = Defs.AMMO[at]
			items.append({"text": "%s  x%d" % [a.name, int(a.box)], "right": "$%d   (have %d)" % [int(a.price), int(p.inv.ammo.get(at, 0))], "fn": func():
				if int(p.inv.ammo.get(at, 0)) >= int(a.max):
					G.say("Ammo full", UIKit.DIM)
				elif p.spend(int(a.price)):
					p.inv.add_ammo(at, int(a.box))
					if at in ["grenade", "molotov"]:
						p.inv.owned[at] = true})
		items.append({"text": "Fill everything", "right": "$1500", "fn": func():
			if p.spend(1500):
				p.inv.refill_all()})
		m.set_items(items), {})


func open_gunbench() -> void:
	menu.open("Weapon Workbench", func(m: MenuPanel):
		var items: Array = []
		var p: Player = G.player
		for wid in Defs.WEAPON_ORDER:
			var d: Dictionary = Defs.WEAPONS[wid]
			if p.inv.owned.has(wid) and d.has("mods"):
				items.append({"text": d.name, "right": "%d mods >" % p.inv.mods_of(wid).size(), "fn": _bench_weapon.bind(wid), "no_refresh": true})
		if items.is_empty():
			items.append({"text": "No compatible firearms owned", "disabled": true})
		m.set_items(items), {"sub": "Attachments change handling: suppressors are quiet, grips tame recoil, optics tighten aim."})


func _bench_weapon(wid: String) -> void:
	var p: Player = G.player
	p.equip(wid)
	menu.open(Defs.WEAPONS[wid].name, func(m: MenuPanel):
		var items: Array = []
		for mod in Defs.WEAPONS[wid].mods:
			var md: Dictionary = Defs.WEAPON_MODS[mod]
			if p.inv.has_mod(wid, mod):
				items.append({"text": md.name, "right": "FITTED", "desc": md.desc, "right_color": UIKit.TEAL, "fn": func():
					p.inv.wmods[wid].erase(mod)
					p.equip(wid)})
			else:
				items.append({"text": md.name, "right": "$%d" % int(md.price), "desc": md.desc, "fn": func():
					if p.spend(int(md.price)):
						p.inv.add_mod(wid, mod)
						if mod == "extmag":
							p.inv.clip[wid] = p.inv.mag_size(wid)
						p.equip(wid)})
		items.append({"header": "Finish"})
		for tn in Defs.WEAPON_TINTS.keys():
			var c: Color = Defs.WEAPON_TINTS[tn]
			items.append({"text": tn, "right": "$150" if p.inv.tints.get(wid, "Factory") != tn else "APPLIED", "swatch": c if c.a > 0 else Color("2a2c30"), "fn": func():
				if p.inv.tints.get(wid, "Factory") != tn and p.spend(150 if tn != "Factory" else 0):
					p.inv.tints[wid] = tn
					p.equip(wid)})
		m.set_items(items), {})


# ------------------------------------------------------------------ clothing / barber / store
func open_clothes(free: bool) -> void:
	var p: Player = G.player
	menu.open("Wardrobe" if free else "Thread & Tide", func(m: MenuPanel):
		var items: Array = []
		for cat in ["shirt", "pants", "shoes"]:
			var cd: Dictionary = Defs.CLOTHES[cat]
			items.append({"header": cd.name})
			for hex in cd.colors:
				var c := Color(hex)
				var worn: bool = (p.look.get(cat, Color.BLACK) as Color).is_equal_approx(c)
				items.append({"text": "#" + String(hex).to_upper(), "swatch": c, "right": "WORN" if worn else ("free" if free else "$%d" % int(cd.price)), "fn": func():
					if worn:
						return
					if free or p.spend(int(cd.price)):
						p.look[cat] = c
						p.apply_look()})
		items.append({"header": "Style"})
		items.append({"text": "Sleeves", "right": "Long" if p.look.get("long_sleeve", true) else "Short", "fn": func():
			p.look["long_sleeve"] = not p.look.get("long_sleeve", true)
			p.apply_look()})
		items.append({"text": "Legs", "right": "Shorts" if p.look.get("shorts", false) else "Trousers", "fn": func():
			p.look["shorts"] = not p.look.get("shorts", false)
			p.apply_look()})
		for cat2 in ["hat", "glasses"]:
			var cd2: Dictionary = Defs.CLOTHES[cat2]
			var idx: int = maxi((cd2.parts as Array).find(p.look.get(cat2, "")), 0)
			items.append({"text": cd2.name, "right": "< %s >" % cd2.labels[idx], "adjust": func(dir: int):
				p.look[cat2] = cd2.parts[posmod(idx + dir, (cd2.parts as Array).size())]
				p.apply_look()})
		var hc: Array = Defs.CLOTHES.shirt.colors
		var hidx: int = maxi(hc.find((p.look.get("hat_color", Color("c9302a")) as Color).to_html(false)), 0)
		items.append({"text": "Hat colour", "right": "< >", "swatch": p.look.get("hat_color", Color("c9302a")), "adjust": func(dir: int):
			p.look["hat_color"] = Color(hc[posmod(hidx + dir, hc.size())])
			p.apply_look()})
		items.append({"text": "Body type", "right": "Masculine" if p.look.get("sex", "m") == "m" else "Feminine", "fn": func():
			p.look["sex"] = "f" if p.look.get("sex", "m") == "m" else "m"
			_rebuild_player_visual()})
		m.set_items(items), {"sub": "Changing your look while the police are searching helps you slip away.", "side": "left"})


func _rebuild_player_visual() -> void:
	var p: Player = G.player
	var old := p.vis
	p.vis = CharVisual.new()
	p.vis.name = "Visual2"
	p.add_child(p.vis)
	p.vis.setup(p.look)
	old.queue_free()
	p.apply_look()


func open_barber() -> void:
	var p: Player = G.player
	menu.open("Fade Factory", func(m: MenuPanel):
		var items: Array = []
		var H: Dictionary = Defs.HAIR
		items.append({"header": "Cut  ($%d)" % int(H.price)})
		for i in (H.parts as Array).size():
			var part: String = H.parts[i]
			items.append({"text": H.labels[i], "right": "CURRENT" if p.look.get("hair", "") == part else "", "fn": func():
				if p.look.get("hair", "") != part and p.spend(int(H.price)):
					p.look["hair"] = part
					p.apply_look()})
		items.append({"header": "Facial hair"})
		for i in (H.beards as Array).size():
			var b: String = H.beards[i]
			items.append({"text": H.beard_labels[i], "right": "CURRENT" if p.look.get("beard", "") == b else "", "fn": func():
				if p.look.get("beard", "") != b and p.spend(int(H.price)):
					p.look["beard"] = b
					p.apply_look()})
		items.append({"header": "Colour"})
		for hex in H.colors:
			items.append({"text": "#" + String(hex).to_upper(), "swatch": Color(hex), "fn": func():
				if p.spend(int(H.price)):
					p.look["hair_color"] = Color(hex)
					p.apply_look()})
		m.set_items(items), {})


func open_store() -> void:
	var p: Player = G.player
	menu.open("Sunny Mart", func(m: MenuPanel):
		var items: Array = []
		for it in Defs.STORE:
			items.append({"text": it.name, "right": "$%d" % int(it.price), "fn": _buy_store.bind(String(it.id), int(it.price))})
		m.set_items(items), {"sub": "Aim a gun at the clerk if you are feeling reckless."})


func _buy_store(id: String, price: int) -> void:
	var p: Player = G.player
	match id:
		"snack":
			if p.health < p.max_health and p.spend(price):
				p.heal(30.0)
		"soda":
			if p.health < p.max_health and p.spend(price):
				p.heal(15.0)
		"medkit":
			if p.health < p.max_health and p.spend(price):
				p.heal(100.0)
		"armor":
			if p.armor < 100.0 and p.spend(price):
				p.armor = 100.0
		"parachute":
			if not p.has_parachute and p.spend(price):
				p.give_parachute()
		"scuba":
			if not p.has_scuba and p.spend(price):
				p.give_scuba(true)


# ------------------------------------------------------------------ vehicle mod shop
func open_modshop(remote: bool = false) -> void:
	var p: Player = G.player
	var v := p.vehicle
	if v == null:
		G.say("Drive a vehicle into the bay", UIKit.DIM)
		return
	if v.kind not in ["car", "bike"]:
		G.say("Torque Bay only works on road vehicles", UIKit.DIM)
		return
	if not remote and G.world.pois.has("modshop"):
		var bay: Vector3 = G.world.pois["modshop"].bay
		v.linear_velocity = Vector3.ZERO
		v.angular_velocity = Vector3.ZERO
		v.global_transform = Transform3D(Basis(Vector3.UP, PI), bay + Vector3(0, 0.3, 0))
	v.owned = true
	var free := func() -> bool: return bool(G.flags.all_mods)
	menu.open("Torque Bay Customs", func(m: MenuPanel):
		var items: Array = []
		var cost := int((1.0 - v.health / v.max_health) * 1200.0) + (150 if true in v.tires_popped else 0)
		items.append({"text": "Repair", "right": "$%d" % cost if cost > 0 else "OK", "fn": func():
			if cost > 0 and (free.call() or p.spend(cost)):
				v.repair()
				Sfx.play("wrench", v.global_position)})
		items.append({"text": "Primary paint", "right": ">", "swatch": v.paint_color, "fn": _paint_menu.bind(v, true), "no_refresh": true})
		items.append({"text": "Secondary paint", "right": ">", "swatch": v.paint2_color, "fn": _paint_menu.bind(v, false), "no_refresh": true})
		var fins: Array = Defs.FINISHES.keys()
		var fi: int = maxi(fins.find(v.finish), 0)
		items.append({"text": "Finish", "right": "< %s >  $%d" % [v.finish, int(Defs.FINISHES[fins[posmod(fi + 1, fins.size())]].price)], "adjust": func(dir: int):
			var nf: String = fins[posmod(fi + dir, fins.size())]
			if free.call() or p.spend(int(Defs.FINISHES[nf].price)):
				v.set_paint(v.paint_color, null, nf)})
		items.append({"header": "Body"})
		for slot in Defs.CAR_MOD_ORDER:
			var md: Dictionary = Defs.CAR_MODS[slot]
			if md.get("perf", false) and slot == "engine":
				items.append({"header": "Performance"})
			if not v.can_mod(slot):
				continue
			var opts: Array = md.options
			var cur: int = int(v.mods.get(slot, 0))
			items.append({"text": md.name, "right": "%s >" % opts[cur].name, "fn": _mod_slot_menu.bind(v, slot), "no_refresh": true})
		if v.parts.has("Roof"):
			items.append({"text": "Convertible roof", "right": "Down" if v.roof_down else "Up", "fn": func(): v.set_roof(not v.roof_down)})
		m.set_items(items), {"sub": "%s   -   cash %s%s" % [v.def.name, G.fmt_money(p.money), "   (all mods unlocked)" if G.flags.all_mods else ""],
			"on_close": func():
				if not remote and G.world.pois.has("modshop"):
					v.global_transform = Transform3D(Basis(Vector3.UP, 0.0), (G.world.pois["modshop"].exit as Vector3) + Vector3(0, 0.3, 0))
					v.linear_velocity = Vector3.ZERO})


func _paint_menu(v: Vehicle, primary: bool) -> void:
	var p: Player = G.player
	menu.open("Primary paint" if primary else "Secondary paint", func(m: MenuPanel):
		var items: Array = []
		for hex in Defs.PAINTS:
			var c := Color(hex)
			var cur: bool = (v.paint_color if primary else v.paint2_color).is_equal_approx(c)
			items.append({"text": "#" + String(hex).to_upper(), "swatch": c, "right": "APPLIED" if cur else "$350", "fn": func():
				if not cur and (G.flags.all_mods or p.spend(350)):
					if primary:
						v.set_paint(c)
					else:
						v.set_paint(v.paint_color, c)
					Sfx.play("spray", v.global_position)})
		m.set_items(items), {})


func _mod_slot_menu(v: Vehicle, slot: String) -> void:
	var p: Player = G.player
	var md: Dictionary = Defs.CAR_MODS[slot]
	if not v.has_meta("mods_owned"):
		v.set_meta("mods_owned", {})
	menu.open(md.name, func(m: MenuPanel):
		var items: Array = []
		var opts: Array = md.options
		var owned: Dictionary = v.get_meta("mods_owned")
		for i in opts.size():
			var o: Dictionary = opts[i]
			var cur: bool = int(v.mods.get(slot, 0)) == i
			var have: bool = i == 0 or owned.has("%s_%d" % [slot, i]) or G.flags.all_mods
			var info := ""
			for k in ["accel", "top", "brake", "grip"]:
				if o.has(k):
					info += "%s +%d%%  " % [k, int((float(o[k]) - 1.0) * 100.0)]
			if o.has("armor"):
				info += "damage taken -%d%%  " % int((1.0 - float(o.armor)) * 100.0)
			if o.has("downforce"):
				info += "downforce +%d%%  " % int(float(o.downforce) * 100.0)
			if o.has("bulletproof"):
				info += "tires cannot be shot out"
			items.append({"text": o.name, "right": "INSTALLED" if cur else ("owned" if have else "$%d" % int(o.price)), "desc": info if info != "" else "Cosmetic",
				"right_color": UIKit.TEAL if cur else UIKit.GOLD, "fn": func():
					if cur:
						return
					if have or p.spend(int(o.price)):
						owned["%s_%d" % [slot, i]] = true
						v.set_mod(slot, i)
						Sfx.play("wrench", v.global_position)})
		m.set_items(items), {})


# ------------------------------------------------------------------ personal garage
func open_garage() -> void:
	var p: Player = G.player
	menu.open("Personal Garage", func(m: MenuPanel):
		var items: Array = []
		var v: Vehicle = p.last_vehicle if (p.last_vehicle != null and is_instance_valid(p.last_vehicle) and not p.last_vehicle.dead and p.last_vehicle.global_position.distance_to(p.global_position) < 30.0) else null
		if v != null and garage.size() < 4:
			items.append({"text": "Store %s" % v.def.name, "right": "%d / 4" % garage.size(), "fn": func():
				garage.append(v.export_state())
				for o in v.occupants():
					if not G.is_player(o):
						o.queue_free()
				v.queue_free()
				p.last_vehicle = null
				G.say("Vehicle stored", Color(0.6, 1.0, 0.6))
				Save.save_game()})
		elif v == null:
			items.append({"text": "Park a vehicle nearby to store it", "disabled": true})
		items.append({"header": "Stored vehicles"})
		for i in garage.size():
			var st: Dictionary = garage[i]
			items.append({"text": Defs.VEHICLES[st.vid].name, "swatch": Color(st.get("paint", "ffffff")), "right": "Retrieve", "fn": func():
				_retrieve(i)})
		if garage.is_empty():
			items.append({"text": "Garage is empty", "disabled": true})
		m.set_items(items), {"sub": "Stored vehicles keep their paint and upgrades and survive saving / loading."})


func _retrieve(i: int, near_player: bool = false) -> Vehicle:
	if i < 0 or i >= garage.size():
		return null
	var st: Dictionary = garage[i]
	var pos: Vector3 = G.world.pois["garage"].slots[i % 2] if G.world.pois.has("garage") else G.player.global_position + Vector3(4, 0.5, 0)
	var yaw := 0.0
	if near_player:
		var v2 := VehicleFactory.spawn_near_player(String(st.vid))
		v2.import_state(st)
		v2.owned = true
		garage.remove_at(i)
		return v2
	var v := VehicleFactory.spawn(String(st.vid), pos + Vector3(0, 0.4, 0), yaw)
	v.import_state(st)
	v.owned = true
	garage.remove_at(i)
	menu.close()
	G.say("%s is ready on the pad" % v.def.name, Color(0.6, 1.0, 0.6))
	return v
