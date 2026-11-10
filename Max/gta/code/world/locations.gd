class_name Locations
extends Node
## Use-points of the city: shop counters and their clerks (robbable), the safehouse, the
## Torque House bay (drive in -> customisation menu, animated roll-up door), the hospital desk
## and the shooting range. Works with the Blender landmarks or their procedural stand-ins.

const SHOPS := {
	"shop_guns": {"kind": "guns", "prompt": "Browse Bulwark Arms", "shirt": "2e3035", "robbable": false},
	"shop_clothes": {"kind": "clothes", "prompt": "Browse Threadline", "shirt": "3ec3e0", "robbable": true},
	"shop_barber": {"kind": "barber", "prompt": "Get a haircut at Fade Factory", "shirt": "f2f0ea", "robbable": true},
	"shop_market": {"kind": "market", "prompt": "Shop at QuikNook 24", "shirt": "3fa55a", "robbable": true},
}
const ROB_COOLDOWN := 240.0

var city: CityBuilder
var rng := RandomNumberGenerator.new()
var clerks: Dictionary = {}           # location id -> NPC
var _bay: Variant = null              # Transform3D of the Torque House bay
var _door: Node3D = null
var _door_rest := Vector3.ZERO
var _door_open := 0.0
var _in_bay := false
var _tick := 0.0

func _ready() -> void:
	rng.seed = 777
	city = Game.world.city
	for id: String in SHOPS.keys():
		_setup_shop(id)
	_setup_safehouse()
	_setup_garage()
	_setup_hospital()
	_setup_range()
	_setup_ladders()
	var anim := LandmarkAnim.new()
	anim.name = "LandmarkAnim"
	add_child(anim)
	print("[Locations] %d use-points, %d clerks" % [Interactable.all.size(), clerks.size()])

func _pt(loc_id: String, marker: String, fallback: Vector3) -> Vector3:
	var m: Variant = city.marker(loc_id, marker)
	if m == null:
		return fallback
	return (m as Transform3D).origin

func _yaw_of(loc_id: String, marker: String) -> float:
	var m: Variant = city.marker(loc_id, marker)
	if m == null:
		return 0.0
	var f := -(m as Transform3D).basis.z
	return atan2(-f.x, -f.z)

## Shops refuse service while officers can see you, or right after a robbery.
func _shop_open(id: String) -> bool:
	if Game.wanted != null and Game.wanted.level > 0 and Game.wanted.seen_now:
		return false
	var clerk: NPC = clerks.get(id)
	if clerk != null:
		if not is_instance_valid(clerk) or not clerk.alive:
			return false
		if Game.clock < float(clerk.get_meta("robbed_at", -1000.0)) + ROB_COOLDOWN:
			return false
		if clerk.state != NPC.S.STAFF:
			return false
	return true

func _setup_shop(id: String) -> void:
	if not city.locations.has(id):
		return
	var cfg: Dictionary = SHOPS[id]
	var loc: Dictionary = city.locations[id]
	var stand_in := bool(loc.get("stand_in", false))
	var entrance := _pt(id, "entrance", loc["pos"])
	var counter := _pt(id, "counter", entrance)
	var kind := String(cfg["kind"])
	var it := Interactable.create(self, counter + Vector3(0, 0.9, 0), String(cfg["prompt"]), 2.2 if not stand_in else 2.8,
		func(_by: Node) -> void:
			if not _shop_open(id):
				Game.notify("The shop will not serve you right now", "bad")
				return
			Game.menus.open_shop(kind), id)
	it.condition = func() -> bool: return Game.menus != null and not Game.menus.is_open()
	if stand_in:
		return
	# clerk behind the counter
	var staff_t: Variant = city.marker(id, "staff")
	if staff_t != null and Game.peds != null:
		var sp := (staff_t as Transform3D).origin
		var yaw := _yaw_of(id, "staff")
		var npc: NPC = Game.peds.spawn(&"staff", sp + Vector3(0, 0.05, 0), yaw, Appearance.staff(rng, String(cfg["shirt"])))
		npc.make_staff(yaw)
		if bool(cfg["robbable"]):
			npc.set_meta("shop", id)
		clerks[id] = npc
	# second use-points inside the bigger shops
	match id:
		"shop_guns":
			var wb: Variant = city.marker(id, "workbench")
			if wb != null:
				var it2 := Interactable.create(self, (wb as Transform3D).origin + Vector3(0, 0.9, 0), "Use the gunsmith workbench", 1.8,
					func(_by: Node) -> void:
						if _shop_open(id):
							Game.menus.open_shop("workbench"), id)
				it2.condition = func() -> bool: return Game.menus != null and not Game.menus.is_open()
		"shop_clothes":
			var wr: Variant = city.marker(id, "wardrobe")
			if wr != null:
				var it3 := Interactable.create(self, (wr as Transform3D).origin + Vector3(0, 0.9, 0), "Try clothes on", 1.8,
					func(_by: Node) -> void:
						if _shop_open(id):
							Game.menus.open_shop("clothes"), id)
				it3.condition = func() -> bool: return Game.menus != null and not Game.menus.is_open()

# ---------------------------------------------------------------- safehouse
func _setup_safehouse() -> void:
	if not city.locations.has("safehouse"):
		return
	var loc: Dictionary = city.locations["safehouse"]
	var stand_in := bool(loc.get("stand_in", false)) or loc.get("root") == null
	var entrance := _pt("safehouse", "entrance", loc["pos"])
	var cond := func() -> bool: return Game.menus != null and not Game.menus.is_open()
	if stand_in:
		var it := Interactable.create(self, entrance + Vector3(0, 0.9, 0), "Enter the Hideout (safehouse)", 2.6,
			func(_by: Node) -> void: Game.menus.open_shop("safehouse"), "safehouse")
		it.condition = cond
		return
	var it_save := Interactable.create(self, _pt("safehouse", "save", entrance) + Vector3(0, 0.9, 0), "Use the laptop (save game)", 1.6,
		func(_by: Node) -> void: Game.menus.open_shop("safehouse"), "safehouse")
	it_save.condition = cond
	var it_bed := Interactable.create(self, _pt("safehouse", "bed", entrance) + Vector3(0, 0.6, 0), "Sleep (6 hours, saves)", 1.8,
		func(_by: Node) -> void:
			if Game.wanted != null and Game.wanted.level > 0:
				Game.notify("You cannot sleep while the police are looking for you", "bad")
				return
			ShopMenus.sleep(6.0), "safehouse")
	it_bed.condition = cond
	var it_wr := Interactable.create(self, _pt("safehouse", "wardrobe", entrance) + Vector3(0, 0.9, 0), "Open the wardrobe", 1.6,
		func(_by: Node) -> void: Game.menus.open_shop("wardrobe"), "safehouse")
	it_wr.condition = cond

# ---------------------------------------------------------------- Torque House
func _setup_garage() -> void:
	if not city.locations.has("shop_garage"):
		return
	var loc: Dictionary = city.locations["shop_garage"]
	_bay = city.marker("shop_garage", "bay")
	var root: Node3D = loc.get("root")
	if root != null:
		_door = PropFactory.part(root, "door")
		if _door != null:
			_door_rest = _door.position
	var staff_t: Variant = city.marker("shop_garage", "staff")
	if staff_t != null and Game.peds != null:
		var yaw := _yaw_of("shop_garage", "staff")
		var mech: NPC = Game.peds.spawn(&"staff", (staff_t as Transform3D).origin + Vector3(0, 0.05, 0), yaw, Appearance.staff(rng, "ef7f2d"))
		mech.make_staff(yaw)
		clerks["shop_garage"] = mech
	var counter := _pt("shop_garage", "counter", loc["pos"])
	var it := Interactable.create(self, counter + Vector3(0, 0.9, 0), "Talk to the mechanic", 2.0,
		func(_by: Node) -> void:
			var v: Vehicle = Game.player.last_vehicle
			if v != null and is_instance_valid(v) and not v.destroyed and _bay != null and v.global_position.distance_to((_bay as Transform3D).origin) < 7.0:
				Game.menus.open_shop("mods", {"vehicle": v})
			else:
				Game.notify("Drive the vehicle you want to work on into the bay", "info"), "shop_garage")
	it.condition = func() -> bool: return Game.menus != null and not Game.menus.is_open()

func _bay_check() -> void:
	if _bay == null:
		return
	var p: Player = Game.player
	var bay: Transform3D = _bay
	var v: Vehicle = p.vehicle as Vehicle if (p.vehicle != null and is_instance_valid(p.vehicle) and p.seat == 0) else null
	var near_door := false
	if v != null:
		var local := bay.affine_inverse() * v.global_position
		near_door = local.length() < 18.0
		var inside := absf(local.x) < 3.2 and absf(local.z) < 5.0 and absf(local.y) < 2.5
		if inside and not _in_bay and absf(v.speed) < 2.5 and Game.menus != null and not Game.menus.is_open():
			_in_bay = true
			if Game.wanted != null and Game.wanted.level > 0 and Game.wanted.seen_now:
				Game.notify("Torque House will not open up with the police on your tail", "bad")
			elif not VehicleMods.compatible(v):
				Game.notify("Torque House only works on cars and bikes", "info")
			else:
				v.in_throttle = 0.0
				v.in_handbrake = true
				v.linear_velocity = Vector3.ZERO
				Game.menus.open_shop("mods", {"vehicle": v})
		elif not inside:
			_in_bay = false
	else:
		_in_bay = false
		near_door = p.global_position.distance_to(bay.origin) < 12.0
	_door_target = 1.0 if near_door else 0.0

var _door_target := 0.0

func _process(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.2
		if Game.player != null:
			_bay_check()
	if _door != null and absf(_door_open - _door_target) > 0.001:
		_door_open = move_toward(_door_open, _door_target, delta * 0.8)
		_door.position = _door_rest + Vector3(0, 4.1 * _door_open, 0)
		if absf(_door_open - _door_target) < 0.02 and _door_open > 0.5:
			pass

# ---------------------------------------------------------------- hospital, range
func _setup_hospital() -> void:
	if not city.locations.has("hospital"):
		return
	var loc: Dictionary = city.locations["hospital"]
	var at: Vector3 = loc.get("respawn", loc["pos"])
	var it := Interactable.create(self, at + Vector3(0, 0.9, -1.0), "Get treated at Vesper General ($150)", 2.4,
		func(_by: Node) -> void:
			var p: Player = Game.player
			if p.health >= p.max_health - 0.5:
				Game.notify("You are perfectly healthy", "info")
				return
			if Game.spend(150):
				p.heal(p.max_health)
				Audio.play_ui(&"ui_heal", -4.0)
				Game.notify("Treated and discharged", "good"), "hospital")
	it.condition = func() -> bool: return Game.menus != null and not Game.menus.is_open()

func _setup_range() -> void:
	if not city.locations.has("range"):
		return
	var loc: Dictionary = city.locations["range"]
	var at: Vector3 = loc.get("lane_from", loc["pos"])
	var it := Interactable.create(self, at + Vector3(0, 0.9, 0), "Start a shooting range challenge", 2.4,
		func(_by: Node) -> void:
			if Game.activities != null and Game.activities.has_method("open_range"):
				Game.activities.open_range()
			else:
				Game.notify("The range is closed", "info"), "range")
	it.condition = func() -> bool:
		return Game.menus != null and not Game.menus.is_open() and (Game.activities == null or not Game.activities.busy())

# ---------------------------------------------------------------- ladders
## Climbable ladders from landmark markers (radio tower on Lookout Hill: a 70 m drop for base jumps).
func _setup_ladders() -> void:
	PlayerMoves.ladders.clear()
	for key in city.locations.keys():
		var loc: Dictionary = city.locations[key]
		var root: Node3D = loc.get("root")
		if root == null:
			continue
		var b: Variant = city.marker(String(key), "ladder_bottom")
		var t: Variant = city.marker(String(key), "ladder_top")
		if b == null or t == null:
			continue
		var bp := (b as Transform3D).origin
		var tp := (t as Transform3D).origin
		var out := bp - root.global_position
		out.y = 0.0
		if out.length() < 0.05:
			out = -(b as Transform3D).basis.z
			out.y = 0.0
		PlayerMoves.add_ladder(bp, tp, out.normalized())
	if not PlayerMoves.ladders.is_empty():
		print("[Locations] %d climbable ladders" % PlayerMoves.ladders.size())
