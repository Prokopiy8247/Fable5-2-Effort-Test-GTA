extends Node3D
## Root of the free-roam world: builds Marlow Bay from Blender assets + City data, spawns systems and the player.

var ground: Ground
var props: PropManager
var pickups: Pickups
var activities: Activities
var emergency: Services
var train: SkylineTrain
var npc_root: Node3D
var buildings: Node3D
var sim_time := 0.0
var interactables: Array = []     # {anchor, offset, r, text, cb, cond, vehicle_ok}
var ladders: Array = []
var pois: Array = []
var teleports: Dictionary = {}
var teleport_yaw: Dictionary = {}
var hospital_spawn := Vector3(-70, 0.5, -100)
var police_spawn := Vector3(27, 0.5, 12)
var safehouse_spawn := Vector3(-123, 0.5, 96)
var safehouse_garage := Vector3(-110, 0.5, 96)
var garage_yaw := 0.0
var mod_bay := Vector3.ZERO
var mod_bay_yaw := 0.0
var _signals: Array = []          # {node, axis, lamps:[r,y,g]}
var _sig_t := 0.0
var _rng := RandomNumberGenerator.new()
var _interact_t := 0.0
var stored_vehicles: Array = []   # saved vehicle states (garage)
var ready_done := false


func _ready() -> void:
	Game.world = self
	_rng.seed = 5252
	City.build()
	teleports = City.teleports()
	for p in City.POI:
		pois.append(p.duplicate())
	ground = Ground.new()
	ground.name = "Ground"
	add_child(ground)
	ground.build()
	var dn := DayNight.new()
	dn.name = "DayNight"
	add_child(dn)
	Game.daynight = dn
	Fx.attach(self)
	npc_root = Node3D.new()
	npc_root.name = "NPCs"
	add_child(npc_root)
	props = PropManager.new()
	props.name = "Props"
	add_child(props)
	pickups = Pickups.new()
	pickups.name = "Pickups"
	add_child(pickups)
	buildings = Node3D.new()
	buildings.name = "Buildings"
	add_child(buildings)
	var traffic := Traffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	var peds := PedManager.new()
	peds.name = "Peds"
	add_child(peds)
	var wl := Wildlife.new()
	wl.name = "Wildlife"
	add_child(wl)
	activities = Activities.new()
	activities.name = "Activities"
	add_child(activities)
	var sv := Services.new()
	sv.name = "Services"
	add_child(sv)
	_place_buildings()
	_decorate()
	props.finalize()
	dn.lamp_bulbs = props.lamp_bulbs
	_traffic_lights()
	_vehicles_and_pickups()
	activities.setup()
	train = SkylineTrain.new()
	train.name = "Skyline"
	add_child(train)
	_navigation()
	var amb := AmbientAudio.new()
	amb.name = "Ambient"
	add_child(amb)
	# player + camera + HUD
	var player := Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = safehouse_spawn
	var cam := CameraRig.new()
	cam.name = "CameraRig"
	add_child(cam)
	var hud = load("res://gta/code/ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)
	if Game.autotest == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().physics_frame
	await get_tree().physics_frame
	_late_init()
	ready_done = true
	if Game.autotest != "":
		var at = load("res://gta/code/debug/autotest.gd").new()
		at.name = "AutoTest"
		add_child(at)
	else:
		Game.banner("MARLOW BAY", "Free roam  -  F1 benchmark menu  -  ESC pause / controls", Color(1.0, 0.85, 0.5))
		if SaveGame.exists():
			Game.say("Save found - F9 to load it", Color(0.6, 0.9, 1.0))


func _late_init() -> void:
	# things that need physics queries against the freshly built city
	for b in buildings.get_children():
		if String(b.name).begins_with("off_e"):
			var top := Game.ray(b.global_position + Vector3(11, 300, 11), b.global_position + Vector3(11, 0, 11), Game.L_WORLD)
			if not top.is_empty():
				teleports["Tower rooftop (base jump)"] = top.position + Vector3.UP * 0.6
				pickups.place("parachute", top.position + Vector3(1.5, 0.6, 0), 0, "", 20.0)
	var hill_y := Game.ground_y(-250, -90)
	teleports["Signal Hill viewpoint"] = Vector3(-250, hill_y + 0.6, -90)
	pickups.place("parachute", Vector3(-252, hill_y + 0.6, -96), 0, "", 30.0)


# ------------------------------------------------------------------ buildings
func _place_buildings() -> void:
	var list := City.placements()
	var idx := 0
	for pl in list:
		if not pl.has("asset"):
			continue
		var asset: String = pl.asset
		var n := Assets.inst(asset)
		n.name = "%s_%d" % [asset, idx]
		idx += 1
		buildings.add_child(n)
		n.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(pl.rot)), pl.pos)
		_set_layers(n)
		_register_special(asset, n)


func _set_layers(n: Node) -> void:
	if n is StaticBody3D:
		n.collision_layer = Game.L_WORLD
		n.collision_mask = 0
	elif n is MeshInstance3D:
		n.visibility_range_end = 900.0
	for c in n.get_children():
		_set_layers(c)


func _marker(n: Node3D, suffix: String) -> Vector3:
	var m := Assets.find(n, suffix)
	if m is Node3D:
		return m.global_position
	return n.global_position


func _front(n: Node3D, dist: float, side: float = 0.0, up: float = 0.3) -> Vector3:
	return n.global_transform * Vector3(side, up, dist)


func set_poi(id: String, pos: Vector3) -> void:
	for p in pois:
		if p.id == id:
			p.pos = pos


func _register_special(asset: String, n: Node3D) -> void:
	var yaw := n.global_rotation.y
	match asset:
		"shop_gun":
			var counter := _marker(n, "_counter")
			add_interact(null, counter, 2.6, "E  Brass & Bolt - buy weapons, ammo, armour, attachments", func(): Game.hud.open_shop("gun"))
			Game.peds.add_post("clerk", _marker(n, "_clerk"), yaw)
			set_poi("gunshop", _front(n, 8.0))
			teleports["Gun shop"] = _front(n, 9.0)
			teleport_yaw["Gun shop"] = yaw
		"garage_mod":
			mod_bay = _marker(n, "_bay")
			mod_bay_yaw = yaw + PI
			add_interact(null, mod_bay, 4.5, "E  Torque House - customise / repair this vehicle", func(): Game.hud.open_shop("mod"),
				func(): return Game.player.in_vehicle() and Game.player.vehicle.def.kind in ["car", "bike"], true)
			add_interact(null, _front(n, 10.5, 5.0), 2.2, "Drive a car or bike into the bay to customise it", func(): Game.say("Bring a vehicle inside"), Callable(), false)
			set_poi("modshop", _front(n, 12.0))
			teleports["Torque House garage"] = _front(n, 16.0)
			teleport_yaw["Torque House garage"] = yaw
		"safehouse":
			safehouse_spawn = n.global_transform * Vector3(-2.5, 0.3, 3.7)
			safehouse_garage = _marker(n, "_garage")
			garage_yaw = yaw + PI
			add_interact(null, _marker(n, "_bed"), 2.0, "E  Sleep (save game + advance 8 hours)", func(): Game.hud.sleep())
			add_interact(null, _marker(n, "_wardrobe"), 2.0, "E  Wardrobe", func(): Game.hud.open_shop("wardrobe"))
			add_interact(null, _marker(n, "_laptop"), 1.8, "E  Laptop - quick save", func(): SaveGame.save_game())
			add_interact(null, safehouse_garage, 4.0, "E  Garage - store / retrieve vehicles", func(): Game.hud.open_shop("garage"), Callable(), true)
			set_poi("safehouse", _front(n, 8.0, -2.5))
			teleports["Safehouse"] = _front(n, 9.0, -2.5)
			teleport_yaw["Safehouse"] = yaw
		"police_station":
			police_spawn = _front(n, 16.0)
			set_poi("police", _front(n, 12.0))
			teleports["Police station"] = _front(n, 18.0)
			teleport_yaw["Police station"] = yaw
			Game.peds.add_post("cop", _front(n, 13.5, 3.0), yaw)
			Game.peds.add_post("cop", _front(n, 13.5, -3.0), yaw)
			Game.traffic.add_parked(_front(n, 17.0, -11.0), yaw + PI * 0.5, "police")
			Game.traffic.add_parked(_front(n, 17.0, 11.0), yaw + PI * 0.5, "police")
		"hospital":
			hospital_spawn = _front(n, 22.0)
			set_poi("hospital", _front(n, 14.0))
			teleports["Hospital"] = _front(n, 22.0)
			teleport_yaw["Hospital"] = yaw
			add_interact(null, _front(n, 13.0), 2.5, "E  Treatment - full health ($150)", _heal)
			Game.traffic.add_parked(_front(n, 17.0, 13.0), yaw + PI * 0.5, "ambulance")
			var pad := _marker(n, "_helipad")
			teleports["Hospital helipad"] = pad + Vector3.UP * 0.5
		"gas_station":
			set_poi("gas", _front(n, 0.0))
			add_interact(null, _marker(n, "_shop"), 2.6, "E  Fuelio kiosk - snacks, repair kit", func(): Game.hud.open_shop("food"))
			add_interact(null, _front(n, 0.0, 3.5), 3.4, "E  Quick repair ($250)", _quick_repair, func(): return Game.player.in_vehicle(), true)
		"shop_clothing":
			add_interact(null, _front(n, 8.2), 2.4, "E  Threadline - clothing", func(): Game.hud.open_shop("clothes"))
			set_poi("clothes", _front(n, 9.0))
		"shop_barber":
			add_interact(null, _front(n, 8.2), 2.4, "E  Fade Room - hair and beard", func(): Game.hud.open_shop("barber"))
			set_poi("barber", _front(n, 9.0))
		"shop_food":
			add_interact(null, _front(n, 8.2), 2.4, "E  Bite Box - food and drinks", func(): Game.hud.open_shop("food"))
			set_poi("food", _front(n, 9.0))
		"hangar":
			pass
		"terminal":
			set_poi("airport", _front(n, -16.0))
		"wh_d", "shop_a", "shop_c", "shop_d":
			# roof ladders on low buildings
			var bb := Assets.size_of(asset)
			if ladders.size() < 14:
				var out := n.global_basis * Vector3(1, 0, 0)
				var base := n.global_transform * Vector3(bb.end.x + 0.12, 0.0, bb.position.z + bb.size.z * 0.3)
				var roof_y := n.global_position.y + (4.4 if asset != "wh_d" else 6.0) + (0.9 if asset != "wh_d" else 1.6)
				if asset == "shop_d":
					roof_y = n.global_position.y + 7.8 + 0.9
				_add_ladder(base, out, roof_y)


func _heal() -> void:
	if Game.player.health < Game.player.max_health and Game.spend(150):
		Game.player.health = Game.player.max_health
		Game.say("Patched up", Color(0.6, 1.0, 0.6))


func _quick_repair() -> void:
	var v = Game.player.vehicle
	if v != null and Game.spend(250):
		v.repair()
		Game.say("Vehicle repaired", Color(0.6, 1.0, 0.6))


func _add_ladder(base: Vector3, out: Vector3, top_y: float) -> void:
	var l := {"pos": base, "out": out.normalized(), "top": top_y}
	ladders.append(l)
	var node := Assets.inst("ladder")
	add_child(node)
	var h := top_y - base.y + 1.0
	node.global_transform = Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)).scaled(Vector3(1, h / 8.0, 1)), base + out * 0.08)
	add_interact(null, base + out * 0.5 + Vector3.UP * 0.3, 1.5, "E  Climb ladder", func(): Game.player.grab_ladder(l))
	add_interact(null, Vector3(base.x - out.x * 0.9, top_y + 0.3, base.z - out.z * 0.9), 1.5, "E  Climb down", func(): Game.player.grab_ladder(l))


# ------------------------------------------------------------------ interactables
func add_interact(anchor, offset: Vector3, radius: float, text: String, cb: Callable, cond: Callable = Callable(), vehicle_ok: bool = false) -> void:
	interactables.append({"anchor": anchor, "offset": offset, "r": radius, "text": text, "cb": cb, "cond": cond, "vehicle_ok": vehicle_ok})


func _update_interact() -> void:
	var p = Game.player
	if p == null:
		return
	var best := {}
	var bd := 1e9
	var ppos: Vector3 = p.global_position
	var i := 0
	while i < interactables.size():
		var it: Dictionary = interactables[i]
		var pos: Vector3 = it.offset
		if it.anchor != null:
			if not is_instance_valid(it.anchor):
				interactables.remove_at(i)
				continue
			pos = it.anchor.global_transform * it.offset
		i += 1
		var d := pos.distance_to(ppos)
		if d < it.r and d < bd:
			if p.in_vehicle() and not it.vehicle_ok:
				continue
			var cond: Callable = it.cond
			if cond.is_valid() and not cond.call():
				continue
			bd = d
			best = it
	p.interact_target = best
	if Game.hud:
		var prompt := ""
		if not best.is_empty():
			prompt = best.text
		elif p.state == Player.St.FOOT or p.state == Player.St.SWIM:
			var v = p.nearest_vehicle()
			if v != null:
				prompt = "F  %s %s" % ["Hijack" if v.driver_rig != null else "Enter", v.def.name]
			if p._chute_prompt:
				prompt = "SPACE  Open parachute"
		Game.hud.set_prompt(prompt)


# ------------------------------------------------------------------ decoration
func _decorate() -> void:
	var r := _rng
	# streets: lamps, trees, furniture along every traffic segment
	for s in City.segs:
		var d: Vector3 = s.dir
		var right := Vector3(-d.z, 0, d.x)
		var length: float = s.len
		var mid: Vector3 = (s.p0 + s.p1) * 0.5
		var district := City.district_name(mid + right * 20.0)
		var n_lamp := int(length / 30.0)
		for i in range(n_lamp):
			var t := (float(i) + 0.5) / float(n_lamp)
			var side := 1.0 if i % 2 == 0 else -1.0
			var base: Vector3 = s.p0.lerp(s.p1, t) + right * side * (s.half + 0.9)
			var w := -right * side
			props.add("street_lamp", base + Vector3.UP * City.CURB, atan2(w.x, w.z))
		var n_tree := int(length / 16.0)
		for i in range(n_tree):
			var t2 := (float(i) + 0.25) / float(n_tree)
			for side2 in [-1.0, 1.0]:
				var dist2 := City.district_name(s.p0.lerp(s.p1, t2) + right * side2 * 16.0)
				if dist2 in ["Ironworks", "Marlow Airfield", "Port Marlow"] and r.randf() < 0.75:
					continue
				if r.randf() < 0.35:
					continue
				var tp: Vector3 = s.p0.lerp(s.p1, t2) + right * side2 * (s.half + 1.2) + Vector3.UP * City.CURB
				var kind: String = "palm" if (dist2 in ["Bayfront", "Port Marlow"] or r.randf() < 0.15) else ["tree_a", "tree_b", "tree_c"][r.randi() % 3]
				props.add(kind, tp, r.randf() * TAU, r.randf_range(0.85, 1.15))
		var furniture := ["bench", "bin", "hydrant", "newsbox", "mailbox", "parking_meter", "planter", "bin", "bollard", "vending"]
		for i in range(int(length / 14.0)):
			if r.randf() < 0.45:
				continue
			var side3 := 1.0 if r.randf() < 0.5 else -1.0
			var t3 := r.randf_range(0.06, 0.94)
			var kind3: String = furniture[r.randi() % furniture.size()]
			if district in ["Ironworks", "Port Marlow"] and kind3 in ["bench", "planter", "newsbox"]:
				kind3 = ["barrier_plastic", "cone", "utility_box"][r.randi() % 3]
			var off: float = s.half + (0.75 if kind3 in ["hydrant", "parking_meter", "bollard", "cone", "barrier_plastic"] else 2.5)
			var fp: Vector3 = s.p0.lerp(s.p1, t3) + right * side3 * off + Vector3.UP * City.CURB
			var w3 := -right * side3
			props.add(kind3, fp, atan2(w3.x, w3.z) + PI)
		if s.id % 5 == 1:
			var bp: Vector3 = s.p0.lerp(s.p1, 0.3) + right * (s.half + 2.0) + Vector3.UP * City.CURB
			props.add("bus_stop", bp, atan2(-right.x, -right.z) + PI)
		# signs near the ends
		var sp: Vector3 = s.p1 - d * 2.5 + right * (s.half + 0.6) + Vector3.UP * City.CURB
		props.add("sign_speed" if City.nodes[s.b].signal else "sign_stop", sp, atan2(d.x, d.z))
		if s.lanes == 2 and s.id % 2 == 0:
			props.add("billboard", s.p0.lerp(s.p1, 0.5) - right * (s.half + 5.0) + Vector3.UP * City.CURB, atan2(right.x, right.z) + PI)
	# areas
	for pl in City.placements():
		if not pl.has("tag") or pl.has("asset"):
			continue
		var rect: Rect2 = pl.rect
		match pl.tag:
			"park":
				_park(rect)
			"yard":
				_yard(rect)
			"lot":
				_parking_lot(rect, pl.get("north", false))
			"garden":
				_garden(rect, pl.get("north", false))
	_hill()
	_coast()
	_airport()
	_industrial_extras()
	_monorail()
	_stunt_ramps()


func _scatter(kind: String, rect: Rect2, count: int, smin: float = 0.85, smax: float = 1.2, y: float = City.CURB) -> void:
	for i in range(count):
		var p := Vector3(rect.position.x + _rng.randf() * rect.size.x, y, rect.position.y + _rng.randf() * rect.size.y)
		props.add(kind, p, _rng.randf() * TAU, _rng.randf_range(smin, smax))


func _park(rect: Rect2) -> void:
	var c := Vector3(rect.position.x + rect.size.x * 0.5, City.CURB, rect.position.y + rect.size.y * 0.5)
	props.add("fountain", c, 0.0)
	props.add("gazebo", c + Vector3(-22, 0, -20), 0.0)
	props.add("statue", c + Vector3(22, 0, 20), 0.6)
	for i in range(8):
		var a := i * TAU / 8.0
		props.add("bench", c + Vector3(cos(a), 0, sin(a)) * 8.0, atan2(cos(a), sin(a)))
	for i in range(4):
		props.add("picnic_table", c + Vector3(-24 + i * 5.0, 0, 22), 0.3 * i)
		props.add("stall", c + Vector3(16 + (i % 2) * 6.0, 0, -24 + (i / 2) * 6.0), PI)
	var inner := rect.grow(-4.0)
	for i in range(34):
		var p := Vector3(inner.position.x + _rng.randf() * inner.size.x, City.CURB, inner.position.y + _rng.randf() * inner.size.y)
		if p.distance_to(c) < 11.0:
			continue
		props.add(["tree_a", "tree_b", "tree_c", "tree_a", "pine"][_rng.randi() % 5], p, _rng.randf() * TAU, _rng.randf_range(0.9, 1.3))
	_scatter("bush", inner, 26)
	_scatter("flower", inner, 90, 1.0, 1.8)
	_scatter("grass_tuft", inner, 240, 0.8, 1.6)
	_scatter("rock_c", inner, 8)
	Game.peds.add_post("civ", c + Vector3(5, 0.1, 9))
	pickups.place("health", c + Vector3(-22, 0.8, -20))


func _yard(rect: Rect2) -> void:
	var cols := [Color("c8382b"), Color("2f6fba"), Color("e9a23b"), Color("2f9c95"), Color("8c8f96"), Color("4f9a4b")]
	var x0 := rect.position.x + 4.0
	var z0 := rect.position.y + 5.0
	var k := 0
	for ix in range(int((rect.size.x - 8.0) / 9.0)):
		for iz in range(int((rect.size.y - 8.0) / 7.5)):
			if _rng.randf() < 0.35:
				continue
			var stack := 1 + (_rng.randi() % 2)
			for sy in range(stack):
				_container(Vector3(x0 + ix * 9.0 + 1.3, City.CURB + sy * 2.62, z0 + iz * 7.5 + 3.0), 0.0, cols[(k + sy) % cols.size()])
			k += 1
	for i in range(6):
		var p := Vector3(rect.position.x + _rng.randf() * rect.size.x, City.CURB, rect.position.y + _rng.randf() * 3.0)
		props.add(["barrel_red", "barrel_blue", "crate", "pallet", "crate"][_rng.randi() % 5], p, _rng.randf() * TAU)
	props.add("dumpster", Vector3(rect.end.x - 2.0, City.CURB, rect.end.y - 2.0), 0.0)
	Game.peds.add_post("gang", Vector3(rect.position.x + rect.size.x * 0.5, 0.3, rect.end.y - 2.5))
	Game.peds.add_post("gang", Vector3(rect.position.x + rect.size.x * 0.5 + 2.0, 0.3, rect.end.y - 3.5))


func _container(pos: Vector3, yaw: float, col: Color) -> void:
	var n := Assets.inst("container")
	buildings.add_child(n)
	n.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	var mi := Assets._first_mesh(n)
	if mi:
		for si in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(si)
			if m and m.resource_name == "M_Paint":
				mi.set_surface_override_material(si, CharRig.color_mat(col, 0.7))
		mi.visibility_range_end = 500.0
	var sb := StaticBody3D.new()
	sb.collision_layer = Game.L_WORLD
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.44, 2.6, 6.06)
	cs.shape = bs
	cs.position.y = 1.3
	sb.add_child(cs)
	n.add_child(sb)


func _parking_lot(rect: Rect2, north: bool) -> void:
	var z_row := rect.position.y + 8.0 if not north else rect.end.y - 8.0
	var n := int((rect.size.x - 6.0) / 3.4)
	for i in range(n):
		var x := rect.position.x + 4.0 + i * 3.4
		if _rng.randf() < 0.55:
			Game.traffic.add_parked(Vector3(x, City.CURB, z_row), 0.0 if _rng.randf() < 0.5 else PI)
		if _rng.randf() < 0.3:
			Game.traffic.add_parked(Vector3(x, City.CURB, z_row + (14.0 if not north else -14.0)), 0.0 if _rng.randf() < 0.5 else PI)
		props.add("bollard", Vector3(x - 1.7, City.CURB, z_row - 3.4), 0.0)
	props.add("sign_parking", Vector3(rect.position.x + 1.0, City.CURB, z_row), 0.0)
	props.add("atm", Vector3(rect.end.x - 1.5, City.CURB, z_row + 4.0), -PI * 0.5)
	Game.traffic.add_parked(Vector3(rect.position.x + 6.0, City.CURB, z_row + (22.0 if not north else -22.0)), PI * 0.5, "motorcycle")


func _garden(rect: Rect2, north: bool) -> void:
	var back := rect.end.y - 3.0 if north else rect.position.y + 3.0
	for i in range(int(rect.size.x / 3.0)):
		props.add("fence_wood", Vector3(rect.position.x + 1.5 + i * 3.0, City.CURB, back), 0.0)
	_scatter("bush", rect, 6)
	_scatter("tree_c", Rect2(rect.position.x, back - 6.0 if north else back, rect.size.x, 6.0), 3)
	_scatter("flower", rect, 16, 1.0, 1.6)
	props.add("mailbox", Vector3(rect.position.x + 2.0, City.CURB, rect.position.y + 0.6 if north else rect.end.y - 0.6), 0.0)
	Game.traffic.add_parked(Vector3(rect.position.x + rect.size.x * 0.75, City.CURB, rect.position.y + 3.2 if north else rect.end.y - 3.2), PI * 0.5 if north else -PI * 0.5)


func _hill() -> void:
	var n := 0
	var guard := 0
	while n < 110 and guard < 900:
		guard += 1
		var x := _rng.randf_range(-298.0, -208.0)
		var z := _rng.randf_range(-190.0, 8.0)
		var h := City.terrain_height(x, z)
		if h < 0.4 and _rng.randf() < 0.6:
			continue
		if Vector2(x + 254.0, z + 92.0).length() < 9.0:
			continue
		var kind: String = ["pine", "pine", "tree_b", "tree_a", "rock_a", "rock_b", "bush", "bush", "rock_c"][_rng.randi() % 9]
		props.add(kind, Vector3(x, h - 0.1, z), _rng.randf() * TAU, _rng.randf_range(0.85, 1.4))
		n += 1
	for i in range(420):
		var x2 := _rng.randf_range(-298.0, -208.0)
		var z2 := _rng.randf_range(-190.0, 180.0)
		var h2 := City.terrain_height(x2, z2)
		if h2 < -0.1:
			continue
		props.add("grass_tuft" if _rng.randf() < 0.85 else "flower", Vector3(x2, h2, z2), _rng.randf() * TAU, _rng.randf_range(0.9, 1.9))
	# viewpoint on the summit
	var top := Vector3(-254, City.terrain_height(-254, -92), -92)
	props.add("radio_tower", Vector3(-262, City.terrain_height(-262, -100) - 0.2, -100), 0.0)
	props.add("statue", top + Vector3(4, -0.1, 3), 1.0)
	for i in range(3):
		var bp := Vector3(-247.0, 0, -98.0 + i * 5.0)
		bp.y = City.terrain_height(bp.x, bp.z)
		props.add("bench", bp, -PI * 0.5)
	props.add("picnic_table", Vector3(-250, City.terrain_height(-250, -84), -84), 0.4)
	# cow paddock at the foot of the hill
	for i in range(8):
		props.add("fence_wood", Vector3(-274 + i * 3.0, City.terrain_height(-274 + i * 3.0, 4.0), 4.0), 0.0)
		props.add("fence_wood", Vector3(-274 + i * 3.0, City.terrain_height(-274 + i * 3.0, 28.0), 28.0), 0.0)
	for i in range(8):
		props.add("fence_wood", Vector3(-275.5, 0, 5.5 + i * 3.0), PI * 0.5)
	props.add("water_tower", Vector3(-286, City.terrain_height(-286, 60), 60), 0.0)


func _coast() -> void:
	# beach
	for i in range(13):
		var x := -196.0 + i * 22.0 + _rng.randf_range(-3, 3)
		props.add("palm", Vector3(x, City.terrain_height(x, 190.5), 190.5), _rng.randf() * TAU, _rng.randf_range(0.9, 1.2))
		if i % 2 == 0:
			props.add("beach_set", Vector3(x + 7.0, City.terrain_height(x + 7.0, 195.0), 195.0), _rng.randf() * TAU)
		if i % 4 == 1:
			props.add("rock_a", Vector3(x + 3.0, City.terrain_height(x + 3.0, 199.0) - 0.2, 199.0), _rng.randf() * TAU)
	props.add("lifeguard", Vector3(-100, City.terrain_height(-100, 194.0), 194.0), PI)
	props.add("lifeguard", Vector3(20, City.terrain_height(20, 194.0), 194.0), PI)
	for i in range(8):
		props.add("bench", Vector3(-180.0 + i * 46.0, City.CURB, 187.6), PI)
	props.add("helipad", activities.chute_target + Vector3(0, -0.2, 0), 0.0, 0.6)
	# marina pier (walkable, boats moored)
	for i in range(8):
		props.add("pier", Vector3(60, -0.83, 193.0 + i * 8.0), 0.0)
	Game.traffic.add_showcase("speedboat", Vector3(67, Game.WATER_Y + 0.4, 226), PI)
	Game.traffic.add_showcase("speedboat", Vector3(53, Game.WATER_Y + 0.4, 244), PI)
	Game.traffic.add_showcase("policeboat", Vector3(150, Game.WATER_Y + 0.4, 216), PI * 0.5)
	Game.traffic.add_showcase("speedboat", Vector3(210, Game.WATER_Y + 0.4, 216), PI * 0.5)
	props.add("buoy", Vector3(60, Game.WATER_Y - 0.1, 268), 0.0)
	props.add("buoy", Vector3(-120, Game.WATER_Y - 0.1, 250), 0.0)
	props.add("buoy", Vector3(160, Game.WATER_Y - 0.1, 250), 0.0)
	# docks
	var crane := Assets.inst("dock_crane")
	buildings.add_child(crane)
	crane.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(196, 0.1, 198))
	var crane_body := StaticBody3D.new()
	crane_body.collision_layer = Game.L_WORLD
	for sx in [-6.0, 6.0]:
		for sz in [-4.0, 4.0]:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.9, 18, 0.9)
			cs.shape = bs
			cs.position = Vector3(sx, 9, sz)
			crane_body.add_child(cs)
	crane.add_child(crane_body)
	var cols := [Color("c8382b"), Color("2f6fba"), Color("e9a23b"), Color("2f9c95")]
	for i in range(9):
		_container(Vector3(120.0 + i * 8.5, 0.15, 191.0), PI * 0.5, cols[i % 4])
		if i % 2 == 0:
			_container(Vector3(120.0 + i * 8.5, 0.15 + 2.62, 191.0), PI * 0.5, cols[(i + 1) % 4])
	for i in range(5):
		props.add("barrel_red" if i % 2 == 0 else "crate", Vector3(214.0 + i * 2.2, 0.15, 200.0), _rng.randf() * TAU)
	# underwater: wreck, coral, seaweed
	var wy := City.terrain_height(-170, 258)
	props.add("wreck", Vector3(-170, wy - 0.3, 258), 0.7)
	pickups.place("cash", Vector3(-173, wy + 0.8, 256), 2500, "", 600.0)
	pickups.place("scuba", Vector3(64, 0.6, 250), 0, "", 60.0)
	for i in range(60):
		var x2 := _rng.randf_range(-290.0, 290.0)
		var z2 := _rng.randf_range(214.0, 296.0)
		var h := City.terrain_height(x2, z2)
		if h > -2.0:
			continue
		props.add(["seaweed", "seaweed", "coral", "rock_c", "rock_a"][_rng.randi() % 5], Vector3(x2, h - 0.05, z2), _rng.randf() * TAU, _rng.randf_range(0.8, 1.6))
	# lighthouse rock dressing
	for i in range(6):
		var a := i * TAU / 6.0
		var rp := Vector3(-40 + cos(a) * 9.0, 0, 262 + sin(a) * 9.0)
		props.add("rock_b", Vector3(rp.x, City.terrain_height(rp.x, rp.z) - 0.4, rp.z), a)


func _airport() -> void:
	# perimeter fence along the expressway side with a gate gap at x=100
	for i in range(-66, 96):
		var x := i * 3.0 + 1.5
		if absf(x - 100.0) < 9.0 or x < -200.0 or x > 284.0:
			continue
		props.add("fence_chain", Vector3(x, 0.0, -203.0), 0.0)
	props.add("windsock", Vector3(-120, 0, -250), 0.0)
	props.add("windsock", Vector3(262, 0, -250), 0.0)
	props.add("helipad", Vector3(232, 0.02, -226), 0.0)
	props.add("helipad", Vector3(256, 0.02, -246), 0.0)
	props.add("radio_tower", Vector3(-150, 0, -214), 0.0)
	for i in range(6):
		props.add("barrel_red" if i < 3 else "barrel_blue", Vector3(118.0 + i * 1.2, 0.0, -207.0), 0.0)
		props.add("cone", Vector3(20.0 + i * 12.0, 0.03, -219.5), 0.0)
	Game.traffic.add_showcase("heli", Vector3(232, 0.4, -226), PI * 0.5)
	Game.traffic.add_showcase("heli_police", Vector3(256, 0.4, -246), PI * 0.5)
	Game.traffic.add_showcase("plane", Vector3(60, 0.5, -244), -PI * 0.5)
	Game.traffic.add_showcase("jet", Vector3(10, 0.5, -246), -PI * 0.5)
	Game.traffic.add_showcase("plane", Vector3(150, 0.5, -226), 0.0)
	pickups.place("parachute", Vector3(92, 0.6, -222), 0, "", 30.0)
	Game.traffic.add_parked(Vector3(70, 0.2, -203.5), PI * 0.5)
	Game.traffic.add_parked(Vector3(78, 0.2, -203.5), PI * 0.5, "taxi")


func _industrial_extras() -> void:
	props.add("water_tower", Vector3(246, 0.15, 30), 0.0)
	for i in range(10):
		props.add("barrier_jersey", Vector3(212.0 + i * 3.05, 0.15, 44.0), 0.0)
	for i in range(8):
		props.add(["crate", "pallet", "barrel_blue", "barrel_red"][i % 4], Vector3(214.0 + _rng.randf() * 50.0, 0.15, 74.0 + _rng.randf() * 20.0), _rng.randf() * TAU)
	props.add("dumpster", Vector3(214, 0.15, -100), 0.0)
	Game.traffic.add_parked(Vector3(232, 0.2, 96), 0.0, "boxtruck")
	Game.traffic.add_parked(Vector3(244, 0.2, -96), PI * 0.5, "van")
	pickups.place("armor", Vector3(250, 0.8, 52))
	pickups.place("weapon", Vector3(236, 0.8, 52), 0, "smg", 240.0)
	pickups.place("weapon", Vector3(-262, City.terrain_height(-262, -104) + 0.8, -104), 0, "marksman", 300.0)
	pickups.place("weapon", Vector3(150, 0.9, -230), 0, "grenade", 180.0)
	pickups.place("health", Vector3(-70, 0.8, -104))
	pickups.place("armor", Vector3(40, 0.8, 4))
	pickups.place("cash", Vector3(-40, 2.8, 262), 800, "", 400.0)
	pickups.place("ammo", Vector3(8, 0.8, 100))
	pickups.place("cash", Vector3(70, 0.8, 84), 150, "", 300.0)


func _monorail() -> void:
	var z := SkylineTrain.RAIL_Z
	for i in range(29):
		var x := -190.0 + i * 10.0
		props.add("rail_beam", Vector3(x + 5.0, SkylineTrain.RAIL_Y, z), PI * 0.5)
		if i % 2 == 0:
			props.add("rail_pillar", Vector3(x, City.terrain_height(x, z) - 0.3, z), 0.0)
	for sx in SkylineTrain.STATIONS:
		var st := Assets.inst("station")
		buildings.add_child(st)
		st.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(sx, City.terrain_height(sx, z + 4.2) - 0.1, z + 4.2))
		_set_layers(st)
	pois.append({"id": "skyline", "name": "Skyline Station", "pos": Vector3(-50, 0.3, 190), "icon": "train"})


func _stunt_ramps() -> void:
	var defs := [[Vector3(-150, 0.03, -186), PI * 0.5], [Vector3(150, 0.15, 196), -PI * 0.5], [Vector3(-120, 0.0, -272), -PI * 0.5],
		[Vector3(240, 0.15, 120), 0.0], [Vector3(-2, 0.03, 150), 0.0]]
	for d in defs:
		var pos: Vector3 = d[0]
		var yaw: float = d[1]
		var n := Assets.inst("ramp")
		buildings.add_child(n)
		n.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
		var mi := Assets._first_mesh(n)
		if mi:
			var sb := StaticBody3D.new()
			sb.collision_layer = Game.L_WORLD
			var cs := CollisionShape3D.new()
			cs.shape = mi.mesh.create_convex_shape()
			sb.add_child(cs)
			mi.add_child(sb)
		activities.add_ramp(pos + Basis(Vector3.UP, yaw) * Vector3(0, 1.6, -3.0), yaw)


# ------------------------------------------------------------------ traffic lights
func _traffic_lights() -> void:
	for n in City.nodes:
		if not n.signal:
			continue
		for sid in n.segs:
			var s: Dictionary = City.segs[sid]
			var into: Vector3 = s.dir if s.b == n.id else -s.dir     # direction of travel into the node
			var right := Vector3(-into.z, 0, into.x)
			var cross: float = n.hz if s.axis == "z" else n.hx
			var pos: Vector3 = n.pos - into * (cross + 2.2) + right * (s.half + 1.0) + Vector3.UP * City.CURB
			var tl := Assets.inst("traffic_light")
			add_child(tl)
			tl.global_transform = Transform3D(Basis(Vector3.UP, atan2(-into.x, -into.z)), pos)
			var lamps := [Assets.find(tl, "_red"), Assets.find(tl, "_yellow"), Assets.find(tl, "_green")]
			_signals.append({"node": n.id, "axis": s.axis, "lamps": lamps})
			var mi := Assets._first_mesh(tl)
			if mi:
				mi.visibility_range_end = 220.0
			for l in lamps:
				if l is MeshInstance3D:
					l.visibility_range_end = 260.0
			var sb := StaticBody3D.new()
			sb.collision_layer = Game.L_SOFT
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.14
			cyl.height = 5.5
			cs.shape = cyl
			cs.position.y = 2.75
			sb.add_child(cs)
			tl.add_child(sb)


func _update_signals() -> void:
	for sg in _signals:
		var st := City.signal_state(sg.node, sg.axis, sim_time)
		var lamps: Array = sg.lamps
		if lamps[0]:
			lamps[0].visible = st == 2
		if lamps[1]:
			lamps[1].visible = st == 1
		if lamps[2]:
			lamps[2].visible = st == 0


# ------------------------------------------------------------------ vehicles / pickups
func _vehicles_and_pickups() -> void:
	var t: Traffic = Game.traffic
	t.add_showcase("sports", safehouse_garage + Vector3(0, 0.4, 0), garage_yaw)
	t.add_showcase("motorcycle", safehouse_garage + Basis(Vector3.UP, garage_yaw) * Vector3(4.0, 0.4, 0.5), garage_yaw)
	t.add_showcase("bicycle", safehouse_garage + Basis(Vector3.UP, garage_yaw) * Vector3(-4.0, 0.4, 0.5), garage_yaw)
	t.add_showcase("bicycle", Vector3(-150, 0.5, -84), 0.0)
	t.add_showcase("muscle", Vector3(-104.5, 0.5, 150), 0.0)
	t.add_showcase("suv", Vector3(104.5, 0.5, 150), PI)
	t.add_showcase("pickup", Vector3(-224, 0.5, 106.5), PI * 0.5)
	t.add_showcase("motorcycle", Vector3(-12, 0.5, 174), PI * 0.5)
	# kerbside parking on quieter streets
	for s in City.segs:
		if s.lanes == 2 or s.id % 3 != 0:
			continue
		var d: Vector3 = s.dir
		var right := Vector3(-d.z, 0, d.x)
		for k in range(2):
			var tt := _rng.randf_range(0.2, 0.8)
			var pos: Vector3 = s.p0.lerp(s.p1, tt) + right * (s.half - 1.1) * (1.0 if k == 0 else -1.0)
			var yaw := atan2(-d.x, -d.z) + (0.0 if k == 0 else PI)
			t.add_parked(pos + Vector3.UP * 0.1, yaw)
	pickups.place("weapon", safehouse_spawn + Vector3(1.5, 0.6, 0.5), 0, "smg", 600.0)
	pickups.place("armor", safehouse_spawn + Vector3(2.5, 0.6, 1.5), 0, "", 300.0)


# ------------------------------------------------------------------ navigation
func _navigation() -> void:
	var path := "res://gta/generated/nav/city_navmesh.res"
	if not ResourceLoader.exists(path):
		push_warning("No baked navmesh (run tools: bake_nav.gd); NPCs use direct steering.")
		return
	var nm = load(path)
	if nm is NavigationMesh:
		var region := NavigationRegion3D.new()
		region.name = "NavRegion"
		region.navigation_mesh = nm
		add_child(region)
		Npc.nav_map = get_world_3d().navigation_map
		NavigationServer3D.map_set_cell_size(Npc.nav_map, nm.cell_size)
		NavigationServer3D.map_set_cell_height(Npc.nav_map, nm.cell_height)
		Npc.nav_ready = true


func _physics_process(delta: float) -> void:
	sim_time += delta
	_sig_t -= delta
	if _sig_t <= 0.0:
		_sig_t = 0.25
		_update_signals()
	_interact_t -= delta
	if _interact_t <= 0.0:
		_interact_t = 0.1
		_update_interact()


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("quicksave"):
		SaveGame.save_game()
	elif ev.is_action_pressed("quickload"):
		SaveGame.load_game()
