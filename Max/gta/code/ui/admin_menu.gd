class_name AdminMenu
extends RefCounted
## The admin / benchmark menu (F1): every testing shortcut from the spec in one place.
## It is a testing tool only - nothing here is a mission or objective.

const TIMES := [["Dawn 05:30", 5.5], ["Morning 08:00", 8.0], ["Noon 12:00", 12.0], ["Afternoon 16:00", 16.0],
	["Sunset 18:45", 18.75], ["Night 22:00", 22.0], ["Midnight 00:00", 0.0]]

static func rows(ui: UIManager) -> Array:
	return [
		{"text": "Teleport", "page": func() -> Array: return _teleport(ui), "desc": "Districts, landmarks and your GPS waypoint."},
		{"text": "Spawn vehicle", "page": func() -> Array: return _vehicles(ui), "desc": "Every vehicle with an exported model. Aircraft and boats are placed where they can be used."},
		{"text": "Weapons and gear", "page": func() -> Array: return _weapons(ui)},
		{"text": "Player", "page": func() -> Array: return _player(ui), "desc": "Health, armour, money, invulnerability, skills."},
		{"text": "Wanted level and police", "page": func() -> Array: return _wanted(ui)},
		{"text": "Time and weather", "page": func() -> Array: return _world(ui)},
		{"text": "Population toggles", "page": func() -> Array: return _population(ui), "desc": "Traffic, pedestrians, wildlife, police."},
		{"text": "Vehicle tools", "page": func() -> Array: return _vehicle_tools(ui), "desc": "Repair, customisation test, unlock all modifications."},
		{"text": "Services", "page": func() -> Array: return _services(ui), "desc": "Taxi, ambulance, fire truck."},
		{"text": "Display", "page": func() -> Array: return _display(ui), "desc": "FPS counter, coordinates and sector, HUD."},
		{"text": "Benchmark", "page": func() -> Array: return _bench(ui), "desc": "Scripted camera tour with frame-time statistics and stress tests."},
		{"text": "Close", "fn": func() -> void: ui.menu.close()},
	]

static func _toggle(label: String, getter: Callable, setter: Callable, desc := "") -> Dictionary:
	return {"text": label, "desc": desc, "opts": ["Off", "On"], "idx": 1 if bool(getter.call()) else 0,
		"on_opt": func(i: int) -> void: setter.call(i == 1)}

static func _back(ui: UIManager) -> Dictionary:
	return {"text": "Back", "fn": func() -> void: ui.menu.back()}

# ---------------------------------------------------------------- teleport
static func _surface(p: Vector3) -> Vector3:
	var hit := Game.ray(p + Vector3(0, 4.0, 0), p - Vector3(0, 12.0, 0), Phys.WORLD)
	if not hit.is_empty():
		return (hit["position"] as Vector3) + Vector3(0, 0.1, 0)
	return Vector3(p.x, maxf(Game.ground_y(p.x, p.z), p.y), p.z) + Vector3(0, 0.2, 0)

## A sidewalk corner of the junction closest to the centre of a district.
static func district_point(zone_name: String) -> Variant:
	var layout: CityLayout = Game.world.layout
	for zn in layout.zones:
		if String(zn["name"]) != zone_name:
			continue
		var c: Vector2 = (zn["rect"] as Rect2).get_center()
		c = c.clamp(Vector2(-280, -280), Vector2(280, 200))
		var best: Dictionary = {}
		var bd := 1.0e9
		for id in layout.nodes.keys():
			var nd: Dictionary = layout.nodes[id]
			var np: Vector3 = nd["pos"]
			var d := Vector2(np.x, np.z).distance_to(c)
			if d < bd:
				bd = d
				best = nd
		if best.is_empty():
			return null
		var bp: Vector3 = best["pos"]
		return bp + Vector3(float(best["hx"]) + 2.0, CityLayout.CURB_H, float(best["hz"]) + 2.0)
	return null

static func go(where: Vector3, yaw := 0.0) -> void:
	var p: Player = Game.player
	if p == null:
		return
	var at := _surface(where)
	p.teleport(at, yaw)
	Game.notify("Teleported to %s (%s)" % [Game.district_at(at), Game.sector_of(at)], "info")

static func _teleport(ui: UIManager) -> Array:
	var rows: Array = [{"text": "Districts", "header": true}]
	var layout: CityLayout = Game.world.layout
	var specials := {"Lookout Hill": Vector3(-195.0, 30.6, -195.0), "Coral Beach": Vector3(-150.0, 0.0, 229.0),
		"Vesper Airfield": Vector3(236.0, 0.2, -150.0), "Saltline Docks": Vector3(240.0, 0.2, 190.0)}
	for zn in layout.zones:
		var nm := String(zn["name"])
		var pt: Variant = specials.get(nm, district_point(nm))
		if pt == null:
			continue
		var target: Vector3 = pt
		rows.append({"text": nm, "fn": func() -> void:
			ui.menu.close()
			go(target)})
	rows.append({"text": "Places", "header": true})
	var city: CityBuilder = Game.world.city
	var seen := {}
	for key in city.locations.keys():
		var loc: Dictionary = city.locations[key]
		var lid := String(loc.get("id", key))
		if not MapDraw.ICON_NAMES.has(lid) or seen.has(lid):
			continue
		seen[lid] = true
		var pos: Vector3 = loc["pos"]
		var m: Variant = city.marker(key, "entrance")
		if m != null:
			pos = (m as Transform3D).origin
		elif loc.has("respawn"):
			pos = loc["respawn"]
		elif loc.has("release"):
			pos = loc["release"]
		var target2 := pos
		rows.append({"text": String(MapDraw.ICON_NAMES[lid]), "fn": func() -> void:
			ui.menu.close()
			go(target2)})
	var hud: HUD = Game.hud
	rows.append({"text": "GPS waypoint", "off": hud == null or hud.waypoint == null, "desc": "Set one on the map (M) first.",
		"fn": func() -> void:
			var wp: Vector3 = hud.waypoint
			ui.menu.close()
			go(wp)})
	rows.append(_back(ui))
	return rows

# ---------------------------------------------------------------- vehicles
static func _vehicles(ui: UIManager) -> Array:
	var rows: Array = []
	for group: String in VehicleDB.GROUPS.keys():
		rows.append({"text": group, "header": true})
		for id: String in VehicleDB.GROUPS[group]:
			var d := VehicleDB.get_v(id)
			var ok := VehicleDB.has_model(id)
			rows.append({"text": String(d.get("name", id)), "right": String(d.get("cls", "")) if ok else "model not exported yet", "off": not ok,
				"fn": func() -> void:
					ui.menu.close()
					spawn_vehicle(id, true)})
	rows.append(_back(ui))
	return rows

static func _free_box(pos: Vector3, half: Vector3, yaw: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = half * 2.0
	q.shape = box
	q.collision_mask = Phys.WORLD | Phys.VEHICLE | Phys.PROP
	q.transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, half.y + 0.25, 0))
	return Game.space().intersect_shape(q, 1).is_empty()

## Spawns `id` where it can actually be used and optionally seats the player in it.
static func spawn_vehicle(id: String, enter := true) -> Vehicle:
	var p: Player = Game.player
	var d := VehicleDB.get_v(id)
	var kind: StringName = d.get("kind", &"car")
	var dims: Vector3 = d.get("dims", Vector3(4.6, 1.9, 1.5))
	var fwd := p.forward()
	if p.vehicle != null and is_instance_valid(p.vehicle):
		fwd = -(p.vehicle as Node3D).global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
	var yaw := atan2(-fwd.x, -fwd.z)
	var pos := p.global_position + fwd * (dims.x * 0.5 + 3.5)
	var airfield: Dictionary = Game.world.city.locations.get("airfield", {})
	match kind:
		&"plane":
			pos = airfield.get("runway_start", Vector3(279.0, 0.2, 92.0))
			yaw = 0.0
		&"boat":
			var w: Variant = _water_spot(p.global_position, maxf(dims.x, 4.0) + 3.0)
			if w == null:
				w = Vector3(86.0, Terrain.SEA, 250.0)
			pos = w
			yaw = PI          # bow toward the open sea (south)
		&"heli":
			if not _free_box(pos, Vector3(dims.y * 2.6, dims.z * 0.5, dims.x * 0.55), yaw) or Game.water_depth(pos) > 0.0:
				pos = airfield.get("helipad", Vector3(240.0, 0.2, -170.0)) + Vector3(0, 0.15, 0)
		_:
			if Game.water_depth(pos + Vector3(0, 0.5, 0)) > 0.0 or not _free_box(_surface(pos), Vector3(dims.y * 0.5, dims.z * 0.5, dims.x * 0.5), yaw):
				# try beside / behind the player before giving up
				var found := false
				for a in [PI * 0.5, -PI * 0.5, PI, PI * 0.25, -PI * 0.25]:
					var alt := p.global_position + fwd.rotated(Vector3.UP, a) * (dims.x * 0.5 + 3.5)
					if Game.water_depth(alt + Vector3(0, 0.5, 0)) <= 0.0 and _free_box(_surface(alt), Vector3(dims.y * 0.5, dims.z * 0.5, dims.x * 0.5), yaw):
						pos = alt
						found = true
						break
				if not found:
					var near := Game.world.graph.nearest(p.global_position, 120.0)
					if not near.is_empty():
						pos = Game.world.graph.sample(int(near["lane"]), float(near["s"]))
						var dirv := Game.world.graph.direction(int(near["lane"]), float(near["s"]))
						yaw = atan2(-dirv.x, -dirv.z)
			pos = _surface(pos)
	var v := VehicleFactory.spawn(id, pos, yaw, {"tag": "player"})
	if v == null:
		return null
	v.set_meta("admin", true)
	if enter:
		p.warp_into.call_deferred(v, 0)
	Game.notify("Spawned %s" % String(d.get("name", id)), "info")
	return v

static func _water_spot(around: Vector3, clearance: float) -> Variant:
	for ring in range(1, 14):
		var r := float(ring) * 12.0
		for k in 16:
			var a := float(k) / 16.0 * TAU
			var pp := around + Vector3(cos(a), 0.0, sin(a)) * r
			if Game.water_depth(Vector3(pp.x, Terrain.SEA - 1.6, pp.z)) > 0.0 and Terrain.sample(pp.x, pp.z) < Terrain.SEA - 2.5 and pp.z > 228.0:
				# keep away from piers and hulls
				if _free_box(Vector3(pp.x, Terrain.SEA - 0.4, pp.z), Vector3(clearance * 0.5, 0.8, clearance * 0.5), 0.0):
					return Vector3(pp.x, Terrain.SEA, pp.z)
	return null

# ---------------------------------------------------------------- weapons
static func _weapons(ui: UIManager) -> Array:
	var p: Player = Game.player
	var rows: Array = [
		{"text": "Give every weapon", "fn": func() -> void:
			for id in WeaponDB.ORDER:
				p.inventory.give(id, -1, true)
			p.inventory.refill_all()
			Game.notify("All weapons given", "info")},
		{"text": "Refill all ammo", "fn": func() -> void:
			p.inventory.refill_all()
			Game.notify("Ammo refilled", "info")},
		_toggle("Infinite ammo", func() -> bool: return Game.cheats["infinite_ammo"], func(on: bool) -> void: Game.cheats["infinite_ammo"] = on),
		{"text": "Give parachute", "right": "owned" if p.inventory.has_parachute else "", "fn": func() -> void:
			p.inventory.has_parachute = true
			Game.notify("Parachute added", "info")},
		_toggle("Scuba gear", func() -> bool: return p.scuba, func(on: bool) -> void:
			p.scuba = on
			p.inventory.has_scuba = on, "Seven times longer air under water while on."),
		{"text": "Refill lung capacity", "fn": func() -> void:
			p.breath = 1.0
			Game.notify("Breath refilled", "info")},
		{"text": "Single weapons", "header": true},
	]
	for id in WeaponDB.ORDER:
		if id == &"unarmed":
			continue
		var w := WeaponDB.get_w(id)
		rows.append({"text": String(w["name"]), "right": "owned" if p.inventory.has(id) else String(WeaponDB.SLOT_NAMES[int(w["slot"])]),
			"fn": func() -> void:
				p.inventory.give(id)
				p.gunner.equip(id)})
	rows.append(_back(ui))
	return rows

# ---------------------------------------------------------------- player
static func _player(ui: UIManager) -> Array:
	var p: Player = Game.player
	var money := [0, 1000, 10000, 100000, 1000000]
	var hp := [10.0, 25.0, 50.0, 100.0]
	var ar := [0.0, 50.0, 100.0]
	return [
		_toggle("Invulnerable", func() -> bool: return Game.cheats["invulnerable"], func(on: bool) -> void: Game.cheats["invulnerable"] = on),
		{"text": "Set health", "opts": ["10%", "25%", "50%", "100%"], "idx": 3, "on_opt": func(i: int) -> void:
			p.health = p.max_health * float(hp[i]) / 100.0},
		{"text": "Set armour", "opts": ["0", "50", "100"], "idx": 2 if p.armor > 75.0 else (1 if p.armor > 25.0 else 0), "on_opt": func(i: int) -> void:
			p.armor = float(ar[i])},
		{"text": "Heal fully", "fn": func() -> void:
			p.heal(p.max_health)
			p.armor = 100.0
			p.stamina = p.max_stamina()},
		{"text": "Money", "header": true},
		{"text": "Add $10,000", "fn": func() -> void: Game.add_cash(10000)},
		{"text": "Set money", "opts": ["$0", "$1,000", "$10,000", "$100,000", "$1,000,000"], "idx": 0, "on_opt": func(i: int) -> void:
			Game.add_cash(int(money[i]) - Game.cash, false)},
		_toggle("Free shopping", func() -> bool: return Game.cheats["free_shopping"], func(on: bool) -> void: Game.cheats["free_shopping"] = on),
		{"text": "Skills", "header": true},
		{"text": "Max all skills", "fn": func() -> void:
			Game.skills.set_all(1.0)
			Game.notify("All skills maxed", "info")},
		{"text": "Reset all skills", "fn": func() -> void:
			Game.skills.set_all(0.0)
			Game.notify("Skills reset", "info")},
		_back(ui),
	]

# ---------------------------------------------------------------- wanted
static func _wanted(ui: UIManager) -> Array:
	var w: WantedSystem = Game.wanted
	if w == null:
		return [{"text": "Wanted system not loaded", "info": true}, _back(ui)]
	return [
		{"text": "Wanted level", "opts": ["0", "1", "2", "3", "4", "5"], "idx": w.level, "on_opt": func(i: int) -> void:
			Game.cheats["never_wanted"] = false
			w.set_level(i)},
		{"text": "Clear wanted level", "fn": func() -> void: w.clear()},
		_toggle("Never wanted", func() -> bool: return Game.cheats["never_wanted"], func(on: bool) -> void:
			Game.cheats["never_wanted"] = on
			if on:
				w.clear(true)),
		{"text": "Spawn police patrol nearby", "desc": "A patrol car drives to you. It only gets involved if you are wanted.",
			"fn": func() -> void:
				var pd: PoliceDispatch = Game.police
				if pd == null:
					return
				var spot := pd._find_spawn(Game.player_pos(), 45.0, 110.0)
				if spot.is_empty():
					Game.notify("No road nearby for a patrol car", "bad")
					return
				var u := pd.spawn_unit(&"patrol", int(spot[0]), float(spot[1]), 1)
				if u != null:
					u.ai.drive_to(Game.player_pos(), false)
					Game.notify("Police patrol dispatched", "info")},
		{"text": "Spawn police officers on foot", "fn": func() -> void:
			var pm: PedManager = Game.peds
			for i in 2:
				var a := randf() * TAU
				var at := _surface(Game.player_pos() + Vector3(cos(a), 0.0, sin(a)) * 9.0)
				var cop := pm.spawn(&"police", at, a)
				cop.wander_area({"rect": Rect2(at.x - 6.0, at.z - 6.0, 12.0, 12.0), "y": at.y})},
		_back(ui),
	]

# ---------------------------------------------------------------- world
static func _world(ui: UIManager) -> Array:
	var env: WorldEnv = Game.time
	var tnames: Array = []
	for t in TIMES:
		tnames.append(t[0])
	var wnames: Array = []
	for wk in WorldEnv.WEATHER_ORDER:
		wnames.append(String(wk).capitalize())
	var speeds := [0.0, 1.0, 10.0, 60.0]
	return [
		{"text": "Time of day", "opts": tnames, "idx": 2, "desc": "Clock: %s" % env.clock_text(), "on_opt": func(i: int) -> void:
			env.set_hour(float(TIMES[i][1]))},
		{"text": "Hour", "slider": {"min": 0.0, "max": 23.5, "step": 0.5, "value": env.hour, "fmt": "%.1f h",
			"on_change": func(v: float) -> void: env.set_hour(v)}},
		{"text": "Clock speed", "opts": ["Paused", "Normal", "10x", "60x"], "idx": 1 if env.time_running else 0, "on_opt": func(i: int) -> void:
			env.time_running = i > 0
			env.time_scale = float(speeds[i])},
		{"text": "Weather", "opts": wnames, "idx": maxi(WorldEnv.WEATHER_ORDER.find(env.weather), 0), "on_opt": func(i: int) -> void:
			env.auto_weather = false
			env.set_weather(WorldEnv.WEATHER_ORDER[i], true)},
		_toggle("Automatic weather changes", func() -> bool: return env.auto_weather, func(on: bool) -> void: env.auto_weather = on),
		_back(ui),
	]

static func _population(ui: UIManager) -> Array:
	return [
		_toggle("Traffic", func() -> bool: return Game.flags["traffic"], func(on: bool) -> void:
			Game.flags["traffic"] = on
			if not on and Game.traffic != null:
				Game.traffic.clear_traffic()),
		_toggle("Pedestrians", func() -> bool: return Game.flags["pedestrians"], func(on: bool) -> void:
			Game.flags["pedestrians"] = on
			if not on and Game.peds != null:
				Game.peds.clear()),
		_toggle("Wildlife", func() -> bool: return Game.flags["wildlife"], func(on: bool) -> void:
			Game.flags["wildlife"] = on
			if not on and Game.wildlife != null and Game.wildlife.has_method("clear"):
				Game.wildlife.clear()),
		_toggle("Police", func() -> bool: return Game.flags["police"], func(on: bool) -> void:
			Game.flags["police"] = on),
		{"text": "Traffic density", "slider": {"min": 0.0, "max": 1.5, "step": 0.1, "value": float(Settings.get_v("traffic_density", 1.0)), "fmt": "%.1f",
			"on_change": func(v: float) -> void: Settings.set_v("traffic_density", v)}},
		{"text": "Pedestrian density", "slider": {"min": 0.0, "max": 1.5, "step": 0.1, "value": float(Settings.get_v("ped_density", 1.0)), "fmt": "%.1f",
			"on_change": func(v: float) -> void: Settings.set_v("ped_density", v)}},
		_back(ui),
	]

# ---------------------------------------------------------------- vehicle tools
static func _vehicle_tools(ui: UIManager) -> Array:
	var p: Player = Game.player
	var v: Vehicle = p.vehicle as Vehicle if p.vehicle != null and is_instance_valid(p.vehicle) else p.last_vehicle
	var has_v := v != null and is_instance_valid(v) and not v.destroyed
	return [
		{"text": "Repair current vehicle", "off": not has_v, "fn": func() -> void:
			v.repair()
			Game.notify("Vehicle repaired", "info")},
		{"text": "Flip upright", "off": not has_v, "fn": func() -> void:
			v.global_transform = Transform3D(Basis(Vector3.UP, v.global_rotation.y), v.global_position + Vector3(0, 1.2, 0))
			v.linear_velocity = Vector3.ZERO
			v.angular_velocity = Vector3.ZERO},
		{"text": "Open customisation menu here", "off": not has_v or not VehicleMods.compatible(v),
			"desc": "The full Torque House menu for your current vehicle, without driving to the garage.",
			"fn": func() -> void:
				ui.menu.close()
				ui.open_shop.call_deferred("mods", {"vehicle": v})},
		_toggle("Unlock all modifications", func() -> bool: return Game.cheats["unlock_all_mods"], func(on: bool) -> void:
			Game.cheats["unlock_all_mods"] = on, "Every upgrade costs nothing."),
		{"text": "Make it my personal vehicle", "off": not has_v, "desc": "Personal vehicles can be stored in the safehouse garage.",
			"fn": func() -> void:
				v.personal = true
				v.owner_tag = "player"
				Game.notify("%s is now yours" % String(v.def.get("name", "")), "info")},
		_back(ui),
	]

static func _services(ui: UIManager) -> Array:
	return [
		{"text": "Call taxi", "fn": func() -> void:
			ui.menu.close()
			if Game.transit != null and Game.transit.has_method("call_taxi"):
				Game.transit.call_taxi()},
		{"text": "Call ambulance", "fn": func() -> void:
			ui.menu.close()
			if Game.services != null:
				Game.services.request("ambulance", Game.player_pos(), true)},
		{"text": "Call fire truck", "fn": func() -> void:
			ui.menu.close()
			if Game.services != null:
				Game.services.request("fire", Game.player_pos(), true)},
		_back(ui),
	]

static func _display(ui: UIManager) -> Array:
	return [
		_toggle("Show FPS", func() -> bool: return Game.flags["show_fps"], func(on: bool) -> void: Game.flags["show_fps"] = on),
		_toggle("Show coordinates and sector", func() -> bool: return Game.flags["show_coords"], func(on: bool) -> void: Game.flags["show_coords"] = on),
		_toggle("Show HUD", func() -> bool: return Game.hud.show_hud, func(on: bool) -> void: Game.hud.show_hud = on),
		_back(ui),
	]

static func _bench(ui: UIManager) -> Array:
	return [
		{"text": "Run benchmark tour (about 60 s)", "desc": "Flies a camera through every district and reports average FPS, 1% low and frame times. The result is also written to user://benchmark.txt.",
			"fn": func() -> void:
				ui.menu.close()
				Benchmark.start()},
		{"text": "Stress: 12 cars around me", "fn": func() -> void:
			var tm: TrafficManager = Game.traffic
			var made := 0
			for i in 40:
				if made >= 12:
					break
				var near := Game.world.graph.nearest(Game.player_pos() + Vector3(randf_range(-60, 60), 0, randf_range(-60, 60)), 30.0)
				if near.is_empty():
					continue
				if tm.spawn_on_lane(int(near["lane"]), float(near["s"])) != null:
					made += 1
			Game.notify("%d extra cars" % made, "info")},
		{"text": "Stress: 15 pedestrians around me", "fn": func() -> void:
			var pm: PedManager = Game.peds
			for i in 15:
				var a := randf() * TAU
				var at := _surface(Game.player_pos() + Vector3(cos(a), 0.0, sin(a)) * randf_range(6.0, 20.0))
				var n := pm.spawn(&"civil", at, randf() * TAU)
				n.ambient = true
				n.wander_area({"rect": Rect2(at.x - 8.0, at.z - 8.0, 16.0, 16.0), "y": at.y})},
		_back(ui),
	]
