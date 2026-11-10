extends Node
## Headless test of the "pickups" world system.
## Run:
##   tools\godot.ps1 -Mode headless -Frames 2500 -UserArgs '--test=wpn_pickups','--no_player','--seed=7','--disable=world,environment,city,interactions,vehicles,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## A dummy CharacterBody3D in group "player" (with a real WeaponInventory child) walks over
## pickups of every kind and must receive the right items.


class DummyPlayer extends CharacterBody3D:
	var health: float = 60.0
	var max_health: float = 100.0
	var armor: float = 0.0
	var max_armor: float = 100.0
	var has_parachute: bool = false
	var current_vehicle: Node3D = null
	var inventory: Node = null

	func heal(amount: float) -> void:
		health = minf(health + amount, max_health)

	func add_armor(amount: float) -> void:
		armor = minf(armor + amount, max_armor)

	func get_aim_ray() -> Dictionary:
		return {"origin": global_position + Vector3.UP * 1.55, "direction": -global_basis.z}

	func add_recoil(_pitch: float, _yaw: float) -> void:
		pass


class DummyNpc extends CharacterBody3D:
	var faction: String = "gang"
	var weapon_id: String = "pistol"
	var is_dead: bool = true


class DummyVehicle extends RigidBody3D:
	var is_player_driven: bool = true


## Stand-in for the World system: spawn points for some kinds, named locations, flat terrain.
class FakeWorld extends Node3D:
	var points: Dictionary = {}
	var locations: Dictionary = {}
	var ground: float = 0.5

	func get_spawn_points(kind: String) -> Array[Transform3D]:
		var out: Array[Transform3D] = []
		for xf: Transform3D in points.get(kind, []):
			out.append(xf)
		return out

	func get_height(_x: float, _z: float) -> float:
		return ground

	func get_locations() -> Dictionary:
		return locations


var _root: Node3D
var _collected: Array = []
var _notes: Array = []


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "PickupRange"
	add_child(_root)
	EventBus.notification.connect(func(text: String, kind: String) -> void: _notes.append([text, kind]))
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	await _run()
	Game.player = null
	await _frames(90)       # let one-shot FX of the last collections finish before quitting
	var orphans_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	TestHarness.log_line("orphan nodes: %d before the test, %d after" % [orphans_before, orphans_after])
	if orphans_after > orphans_before:
		Node.print_orphan_nodes()
	TestHarness.finish()


func _frames(n: int) -> void:
	await TestHarness.wait_physics_frames(n)


func _capsule(body: CollisionObject3D, layer: int) -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(shape)
	body.collision_layer = layer
	body.collision_mask = 0


func _run() -> void:
	var chk := TestHarness
	# floor
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.collision_layer = Layers.WORLD
	floor_body.collision_mask = 0
	_root.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)

	# dummy player with a real inventory
	var player := DummyPlayer.new()
	player.name = "DummyPlayer"
	player.add_to_group("player")
	_capsule(player, Layers.PLAYER)
	_root.add_child(player)
	player.global_position = Vector3(0.0, 0.0, 30.0)
	var inv := WeaponInventory.new()
	inv.name = "Inventory"
	player.add_child(inv)
	inv.setup(player)
	player.inventory = inv
	Game.player = player

	var ps: Node = Game.get_system("pickups")
	chk.check(ps != null, "the 'pickups' system was booted from BootManifest")
	if ps == null:
		ps = PickupSystem.new()
		ps.name = "Pickups"
		_root.add_child(ps)
		ps.call("setup")
	ps.connect("pickup_collected", func(p: Node3D, _who: Node) -> void: _collected.append(str(p.get("kind"))))
	await _frames(4)
	chk.check(inv.has_weapon("pistol") and inv.current_id == "fists", "dummy player starts with the default loadout, unarmed")
	var base_count: int = ps.call("get_pickup_count")

	# ---- cash -----------------------------------------------------------------------------------
	var money := Game.money
	var cash: Node3D = ps.call("spawn_pickup", "cash", "", 250, Vector3(5.0, 0.0, 0.0))
	chk.check(cash is Pickup and cash.is_in_group("pickup") and (cash as Area3D).collision_layer == Layers.PICKUP,
			"spawn_pickup returns an Area3D on Layers.PICKUP in group 'pickup'")
	chk.check(cash.get("halo") != null and cash.get("visual") != null, "pickup has its hovering visual and ground halo")
	await _frames(4)
	var rot0: float = (cash.get("visual") as Node3D).rotation.y
	await _frames(6)
	chk.check(absf((cash.get("visual") as Node3D).rotation.y - rot0) > 0.05, "pickup visual rotates")
	chk.check(Game.money == money, "nothing collected while the player is elsewhere")
	player.global_position = Vector3(5.0, 0.0, 0.0)
	await _frames(5)
	chk.check(Game.money == money + 250, "cash pickup adds $250 (%d -> %d)" % [money, Game.money])
	chk.check(not is_instance_valid(cash) or cash.is_queued_for_deletion(), "one-shot pickup is removed after collection")
	chk.check(int(ps.call("get_pickup_count")) == base_count, "pickup count back to the baseline")

	# ---- weapons --------------------------------------------------------------------------------
	ps.call("spawn_pickup", "weapon", "smg", 60, Vector3(10.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(10.0, 0.0, 0.0)
	await _frames(5)
	var a: Dictionary = inv.get_ammo("smg")
	chk.check(inv.has_weapon("smg") and int(a["in_mag"]) == 30 and int(a["reserve"]) == 30, "weapon pickup gives the SMG with 60 rounds (%s)" % str(a))
	chk.check(inv.current_id == "smg", "a weapon picked up with empty hands is drawn")
	ps.call("spawn_pickup", "weapon", "smg", 45, Vector3(15.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(15.0, 0.0, 0.0)
	await _frames(5)
	chk.check(int(inv.get_ammo("smg")["reserve"]) == 75, "picking up an owned weapon gives its ammo (+45)")
	ps.call("spawn_pickup", "weapon", "pump_shotgun", -1, Vector3(20.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(20.0, 0.0, 0.0)
	await _frames(5)
	a = inv.get_ammo("pump_shotgun")
	chk.check(inv.has_weapon("pump_shotgun") and int(a["in_mag"]) + int(a["reserve"]) == 24, "amount <= 0 grants the weapon's default ammo (%s)" % str(a))
	chk.check(inv.current_id == "smg", "a pickup never switches away from a drawn weapon")
	inv.give_weapon("bat")
	var bat_pickup: Node3D = ps.call("spawn_pickup", "weapon", "bat", -1, Vector3(25.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(25.0, 0.0, 0.0)
	await _frames(5)
	chk.check(is_instance_valid(bat_pickup) and not bat_pickup.is_queued_for_deletion(), "an owned melee weapon is left on the ground")
	ps.call("spawn_pickup", "weapon", "grenade", 2, Vector3(28.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(28.0, 0.0, 0.0)
	await _frames(5)
	chk.check(inv.has_weapon("grenade") and int(inv.get_ammo("grenade")["in_mag"]) == 2, "grenade pickup adds 2 grenades")

	# ---- ammo -----------------------------------------------------------------------------------
	var pistol_reserve := int(inv.get_ammo("pistol")["reserve"])
	ps.call("spawn_pickup", "ammo", "pistol", 24, Vector3(30.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(30.0, 0.0, 0.0)
	await _frames(5)
	chk.check(int(inv.get_ammo("pistol")["reserve"]) == pistol_reserve + 24, "ammo pickup by ammo type (+24 pistol)")
	var shell_reserve := int(inv.get_ammo("pump_shotgun")["reserve"])
	ps.call("spawn_pickup", "ammo", "pump_shotgun", 12, Vector3(35.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(35.0, 0.0, 0.0)
	await _frames(5)
	chk.check(int(inv.get_ammo("pump_shotgun")["reserve"]) == shell_reserve + 12, "ammo pickup addressed by weapon id (+12 shells)")
	inv.refill_all()
	var full_ammo: Node3D = ps.call("spawn_pickup", "ammo", "pistol", 24, Vector3(40.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(40.0, 0.0, 0.0)
	await _frames(5)
	chk.check(is_instance_valid(full_ammo) and not full_ammo.is_queued_for_deletion(), "ammo is left behind when the reserve is full")

	# ---- health / armor -------------------------------------------------------------------------
	player.health = 60.0
	ps.call("spawn_pickup", "health", "", 50, Vector3(45.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(45.0, 0.0, 0.0)
	await _frames(5)
	chk.check(is_equal_approx(player.health, 100.0), "health pickup heals (60 -> %.0f, capped at max)" % player.health)
	var spare_health: Node3D = ps.call("spawn_pickup", "health", "", 50, Vector3(50.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(50.0, 0.0, 0.0)
	await _frames(8)
	chk.check(is_instance_valid(spare_health) and is_equal_approx(player.health, 100.0), "health pickup is not wasted at full health")
	player.health = 40.0
	await _frames(30)
	chk.check(is_equal_approx(player.health, 90.0) and (not is_instance_valid(spare_health) or spare_health.is_queued_for_deletion()),
			"... and is taken as soon as the player standing on it is hurt (health %.0f)" % player.health)
	ps.call("spawn_pickup", "armor", "", 50, Vector3(55.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(55.0, 0.0, 0.0)
	await _frames(5)
	chk.check(is_equal_approx(player.armor, 50.0), "armor pickup adds 50 armor")

	# ---- parachute / scuba ----------------------------------------------------------------------
	ps.call("spawn_pickup", "parachute", "", 1, Vector3(60.0, 0.0, 0.0))
	var second_chute: Node3D = ps.call("spawn_pickup", "parachute", "", 1, Vector3(63.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(60.0, 0.0, 0.0)
	await _frames(5)
	chk.check(player.has_parachute, "parachute pickup sets has_parachute")
	player.global_position = Vector3(63.0, 0.0, 0.0)
	await _frames(5)
	chk.check(is_instance_valid(second_chute) and not second_chute.is_queued_for_deletion(), "a second parachute is left behind")
	ps.call("spawn_pickup", "scuba", "", 1, Vector3(66.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(66.0, 0.0, 0.0)
	await _frames(5)
	chk.check(player.has_meta("has_scuba") and Game.flags.has("scuba_gear"), "scuba pickup marks the player as equipped")

	# ---- who can collect ------------------------------------------------------------------------
	money = Game.money
	var npc_cash: Node3D = ps.call("spawn_pickup", "cash", "", 100, Vector3(70.0, 0.0, 0.0))
	var walker := CharacterBody3D.new()
	walker.add_to_group("npc")
	_capsule(walker, Layers.NPC)
	_root.add_child(walker)
	walker.global_position = Vector3(70.0, 0.0, 0.0)
	await _frames(6)
	chk.check(is_instance_valid(npc_cash) and Game.money == money, "NPCs do not collect pickups")
	walker.queue_free()
	var veh := DummyVehicle.new()
	veh.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	veh.freeze = true
	veh.add_to_group("vehicle")
	var veh_shape := CollisionShape3D.new()
	var veh_box := BoxShape3D.new()
	veh_box.size = Vector3(1.8, 1.4, 4.0)
	veh_shape.shape = veh_box
	veh.add_child(veh_shape)
	veh.collision_layer = Layers.VEHICLE
	veh.collision_mask = 0
	_root.add_child(veh)
	veh.global_position = Vector3(70.0, 0.7, 0.0)
	await _frames(6)
	chk.check(Game.money == money + 100, "a vehicle driven by the player collects for the player")
	veh.queue_free()
	ps.call("set_enabled", false)
	ps.call("spawn_pickup", "cash", "", 100, Vector3(75.0, 0.0, 0.0))
	await _frames(3)
	player.global_position = Vector3(75.0, 0.0, 0.0)
	await _frames(6)
	chk.check(Game.money == money + 100, "a disabled pickup system gives nothing")
	player.global_position = Vector3(0.0, 0.0, 30.0)
	await _frames(3)
	ps.call("set_enabled", true)
	await _frames(3)
	player.global_position = Vector3(75.0, 0.0, 0.0)
	await _frames(6)
	chk.check(Game.money == money + 200, "... and works again once re-enabled")

	# ---- respawn / lifetime / cap ---------------------------------------------------------------
	player.global_position = Vector3(0.0, 0.0, 30.0)
	player.armor = 0.0
	var world_armor: Node3D = ps.call("spawn_world_pickup", "armor", "", 50, Vector3(80.0, 0.0, 0.0), 1.0)
	await _frames(3)
	player.global_position = Vector3(80.0, 0.0, 0.0)
	await _frames(5)
	chk.check(is_equal_approx(player.armor, 50.0) and is_instance_valid(world_armor) and not world_armor.visible
			and world_armor.get("available") == false, "world pickup is hidden (not freed) after collection")
	player.global_position = Vector3(0.0, 0.0, 30.0)
	await _frames(75)
	chk.check(world_armor.visible and world_armor.get("available") == true, "world pickup respawns after its timer")
	player.global_position = Vector3(80.0, 0.0, 0.0)
	await _frames(5)
	chk.check(is_equal_approx(player.armor, 100.0), "respawned pickup can be collected again")
	player.global_position = Vector3(0.0, 0.0, 30.0)
	var short_lived: Node3D = ps.call("spawn_pickup", "cash", "", 10, Vector3(85.0, 0.0, 0.0), {"lifetime": 0.5})
	await _frames(45)
	chk.check(not is_instance_valid(short_lived) or short_lived.is_queued_for_deletion(), "dropped pickups expire after their lifetime")
	var air: Node3D = ps.call("spawn_pickup", "cash", "", 10, Vector3(90.0, 3.0, 0.0))
	chk.check(absf(air.global_position.y) < 0.05, "dropped pickups snap to the ground (y %.2f)" % air.global_position.y)
	var before_cap: int = ps.call("get_pickup_count")
	for i in 50:
		ps.call("spawn_pickup", "cash", "", 5, Vector3(100.0 + float(i) * 2.0, 0.0, 20.0))
	await _frames(2)
	var dropped_now: int = int(ps.call("get_pickup_count"))
	chk.check(dropped_now <= before_cap + 50 and dropped_now <= 40 + 3, "dropped pickups are capped at 40 (%d live)" % dropped_now)
	ps.call("clear_dropped")
	await _frames(2)
	chk.check(int(ps.call("get_pickup_count")) == 1, "clear_dropped keeps only the world pickup (%d)" % int(ps.call("get_pickup_count")))

	# ---- NPC drops ------------------------------------------------------------------------------
	var cash_drops := 0
	var weapon_drops := 0
	var first_npc: DummyNpc = null
	for i in 12:
		var npc := DummyNpc.new()
		npc.add_to_group("npc")
		_root.add_child(npc)
		npc.global_position = Vector3(-20.0 - float(i) * 3.0, 0.0, 0.0)
		if first_npc == null:
			first_npc = npc
		var drops: Array = ps.call("drop_from_npc", npc)
		for d: Node3D in drops:
			if str(d.get("kind")) == "cash":
				cash_drops += 1
				if int(d.get("amount")) < 60 or int(d.get("amount")) > 260:
					chk.check(false, "gang cash drop within 60..260 (%d)" % int(d.get("amount")))
			elif str(d.get("kind")) == "weapon" and str(d.get("item_id")) == "pistol":
				weapon_drops += 1
	chk.check(cash_drops == 12, "every dead gang NPC drops cash (%d / 12)" % cash_drops)
	chk.check(weapon_drops >= 3 and weapon_drops <= 12, "armed NPCs sometimes drop their weapon (%d / 12)" % weapon_drops)
	chk.check((ps.call("drop_from_npc", first_npc) as Array).is_empty(), "drop_from_npc is idempotent per NPC")
	var count_before: int = ps.call("get_pickup_count")
	var late_npc := DummyNpc.new()
	late_npc.weapon_id = ""
	late_npc.add_to_group("npc")
	_root.add_child(late_npc)
	late_npc.global_position = Vector3(-90.0, 0.0, 0.0)
	EventBus.npc_died.emit(late_npc, null, {})
	chk.check(int(ps.call("get_pickup_count")) == count_before + 1, "EventBus.npc_died drops loot automatically")
	var animal := DummyNpc.new()
	animal.add_to_group("animal")
	_root.add_child(animal)
	chk.check((ps.call("drop_from_npc", animal) as Array).is_empty(), "animals drop nothing")
	money = Game.money
	player.global_position = late_npc.global_position
	await _frames(8)
	chk.check(Game.money > money, "dropped cash can be collected (+$%d)" % (Game.money - money))

	# ---- feedback -------------------------------------------------------------------------------
	chk.check(_collected.size() >= 14, "pickup_collected signal fired for every collection (%d)" % _collected.size())
	TestHarness.log_line("collected kinds: %s" % str(_collected))
	TestHarness.log_line("notifications seen on EventBus: %d (e.g. %s)" % [_notes.size(), str(_notes.slice(0, 4))])
	var with_model := 0
	var kinds_checked := 0
	for kind in Pickup.KINDS:
		kinds_checked += 1
		if Pickup.find_model(kind, "pistol" if kind == "weapon" else "") != null:
			with_model += 1
	TestHarness.log_line("pickup kinds with a Blender model available right now: %d / %d" % [with_model, kinds_checked])
	ps.call("clear_dropped")

	# ---- robustness: a pickup freed behind the system's back ---------------------------------------
	player.global_position = Vector3(0.0, 0.0, 30.0)
	await _frames(3)
	var keeper: Node3D = ps.call("spawn_pickup", "cash", "", 5, Vector3(120.0, 0.0, -40.0))
	var doomed: Node3D = ps.call("spawn_pickup", "cash", "", 5, Vector3(124.0, 0.0, -40.0))
	var count_with := int(ps.call("get_pickup_count"))
	doomed.free()
	await _frames(4)
	chk.check(int(ps.call("get_pickup_count")) == count_with - 1 and is_instance_valid(keeper),
			"a pickup freed by somebody else is forgotten, the frame loop keeps running (%d -> %d)" % [count_with, int(ps.call("get_pickup_count"))])
	money = Game.money
	player.global_position = keeper.global_position
	await _frames(8)
	chk.check(Game.money == money + 5, "... and the other pickups still work")
	ps.call("clear_dropped")

	# ---- world placement: spawn points from Game.world, named-location fallbacks ---------------------
	ps.call("clear_all")
	chk.check(int(ps.call("get_pickup_count")) == 0, "clear_all removes world pickups too")
	var fake := FakeWorld.new()
	fake.name = "FakeWorld"
	_root.add_child(fake)
	var weapon_points: Array = []
	for i in 20:
		weapon_points.append(Transform3D(Basis.IDENTITY, Vector3(200.0 + float(i) * 4.0, 0.5 if i != 3 else -3.0, 200.0)))
	fake.points = {
		"pickup_weapon": weapon_points,
		"pickup_health": [Transform3D(Basis.IDENTITY, Vector3(200.0, 0.5, 220.0)), Transform3D(Basis.IDENTITY, Vector3(204.0, 0.5, 220.0)),
				Transform3D(Basis.IDENTITY, Vector3(208.0, 0.5, 220.0))],
		"pickup_cash": [Transform3D(Basis.IDENTITY, Vector3(200.0, 0.5, 240.0)), Transform3D(Basis.IDENTITY, Vector3(204.0, 0.5, 240.0)),
				Transform3D(Basis.IDENTITY, Vector3(208.0, 0.5, 240.0)), Transform3D(Basis.IDENTITY, Vector3(212.0, 0.5, 240.0))],
		# no "pickup_armor" and no "parachute" points: those kinds must fall back to named locations
	}
	fake.locations = {
		"police_station": Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(260.0, 0.5, 200.0)),
		"industrial_yard": Transform3D(Basis.IDENTITY, Vector3(280.0, 0.5, 200.0)),
		"hill_top": Transform3D(Basis.IDENTITY, Vector3(260.0, 0.5, 240.0)),
		"rooftop_helipad": Transform3D(Basis.IDENTITY, Vector3(280.0, 0.5, 240.0)),
		"marina_dock": Transform3D(Basis.IDENTITY, Vector3(260.0, 0.5, 280.0)),
		"beach": Transform3D(Basis.IDENTITY, Vector3(280.0, 0.5, 280.0)),
	}
	var real_world := Game.world
	Game.world = fake
	ps.call("setup")
	Game.world = real_world
	await _frames(2)
	var by_kind := {}
	var weapon_ids := {}
	var all_respawn := true
	var lifted := true
	for wp: Node3D in ps.call("get_pickups"):
		var k := str(wp.get("kind"))
		by_kind[k] = int(by_kind.get(k, 0)) + 1
		if k == "weapon":
			weapon_ids[str(wp.get("item_id"))] = true
		if float(wp.get("respawn_time")) <= 0.0:
			all_respawn = false
		if wp.global_position.y < 0.49:
			lifted = false
	chk.check(int(by_kind.get("weapon", 0)) == 20 and weapon_ids.size() == 16,
			"world weapon pickups: one per 'pickup_weapon' point, all 16 pick-up-able weapons in rotation (%d pickups, %d ids)" % [int(by_kind.get("weapon", 0)), weapon_ids.size()])
	chk.check(int(by_kind.get("health", 0)) == 3 and int(by_kind.get("cash", 0)) == 4, "health and cash pickups at their spawn points (%s)" % str(by_kind))
	chk.check(int(by_kind.get("armor", 0)) == 2 and int(by_kind.get("parachute", 0)) == 2 and int(ps.get("fallback_points_used")) == 4,
			"kinds without spawn points fall back to named locations (armor %d, parachute %d, fallbacks %d)" % [int(by_kind.get("armor", 0)), int(by_kind.get("parachute", 0)), int(ps.get("fallback_points_used"))])
	chk.check(int(by_kind.get("scuba", 0)) == 2, "scuba sets at the marina and the beach (%d)" % int(by_kind.get("scuba", 0)))
	chk.check(int(ps.get("world_pickups_placed")) == 33 and int(ps.call("get_world_pickup_count")) == 33, "33 world pickups placed (%d)" % int(ps.get("world_pickups_placed")))
	chk.check(all_respawn, "every world pickup has a respawn timer")
	chk.check(lifted, "a spawn point below the terrain is lifted onto it")
	var first_world: Node3D = null
	for wp: Node3D in ps.call("get_pickups"):
		if str(wp.get("kind")) == "cash":
			first_world = wp
			break
	money = Game.money
	player.global_position = first_world.global_position
	await _frames(8)
	chk.check(Game.money > money and not bool(first_world.get("available")) and is_instance_valid(first_world), "a placed world pickup is collected and waits for its respawn")
	player.global_position = Vector3(150.0, 0.5, 150.0)
	await _frames(4)
	ps.call("respawn_all")
	await _frames(3)
	chk.check(bool(first_world.get("available")), "respawn_all brings it back at once")
	player.global_position = first_world.global_position
	await _frames(8)
	chk.check(Game.money >= money + 2 * int(first_world.get("amount")), "... and it can be collected again (+$%d in total)" % (Game.money - money))
	ps.call("clear_all")
	chk.check(int(ps.call("get_pickup_count")) == 0, "world pickups cleared")
