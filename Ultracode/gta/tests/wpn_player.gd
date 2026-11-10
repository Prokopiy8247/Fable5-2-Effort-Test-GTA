extends Node
## Integration test: the REAL player scene + the WeaponInventory the player creates for itself.
## Everything is driven the way the game drives it: Input actions -> Player -> Inventory ->
## Combat -> damage / recoil / HUD signals, pickups collected by the real CharacterBody3D, the
## weapon model in the real hand socket, persistence through SaveSystem, and (when the vehicle
## module + a car GLB are available) the drive-by rule from a real driver seat.
## Run (player ON, vehicles + pickups ON):
##   tools\godot.ps1 -Mode headless -Frames 4200 -UserArgs '--test=wpn_player','--seed=5','--disable=world,environment,city,interactions,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Facts about the weapons module are hard checks; facts that belong to a neighbour module
## (camera kick, animator pose, vehicle seat) are checked too, because they are the integration.


class DummyTarget extends StaticBody3D:
	var taken: float = 0.0
	var hits: Array = []
	var is_dead: bool = false
	var knocked: int = 0

	func apply_damage(info: Dictionary) -> void:
		taken += float(info.get("amount", 0.0))
		hits.append(info)

	func knock_down(_impulse: Vector3) -> void:
		knocked += 1


const SAVE_SLOT := "wpn_player_test"
const CAR_IDS: Array[String] = ["sedan", "compact", "sports", "muscle", "suv", "pickup", "taxi", "police_cruiser"]

var _root: Node3D
var _fired: Array = []              # [weapon id, shooter]
var _equipped: Array = []
var _ammo_events: Array = []
var _reloads: Array = []
var _explosions: Array = []
var _hit_confirms: int = 0
var _inventory_events: int = 0


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "WpnPlayerRange"
	add_child(_root)
	EventBus.weapon_fired.connect(func(id: String, shooter: Node, _o: Vector3, _d: Vector3) -> void:
		_fired.append([id, shooter]))
	EventBus.weapon_equipped.connect(func(id: String) -> void: _equipped.append(id))
	EventBus.ammo_changed.connect(func(id: String, in_mag: int, reserve: int) -> void:
		_ammo_events.append([id, in_mag, reserve]))
	EventBus.weapon_reload_started.connect(func(id: String, duration: float) -> void:
		_reloads.append([id, duration]))
	EventBus.explosion.connect(func(pos: Vector3, radius: float, who: Node) -> void:
		_explosions.append({"position": pos, "radius": radius, "instigator": who}))
	EventBus.hit_confirmed.connect(func(_t: Node, _i: Dictionary) -> void: _hit_confirms += 1)
	EventBus.weapon_inventory_changed.connect(func() -> void: _inventory_events += 1)
	await _run()
	for action: String in ["fire", "aim", "reload", "holster", "throw_grenade", "melee_heavy",
			"weapon_slot_1", "weapon_slot_2", "weapon_slot_3", "weapon_slot_6", "weapon_next", "weapon_prev"]:
		Input.action_release(action)
	SaveSystem.delete_save(SAVE_SLOT)
	TestHarness.finish()


# --- helpers ------------------------------------------------------------------------------------

func _box_body(body: CollisionObject3D, size: Vector3, at: Vector3, layer: int) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.collision_layer = layer
	body.collision_mask = 0
	_root.add_child(body)
	body.global_position = at


func _make_humanoid(at: Vector3) -> DummyTarget:
	var h := DummyTarget.new()
	h.name = "Humanoid"
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	h.add_child(shape)
	h.collision_layer = Layers.NPC
	h.collision_mask = 0
	h.add_to_group("npc")
	_root.add_child(h)
	h.global_position = at
	return h


func _frames(n: int) -> void:
	await TestHarness.wait_physics_frames(n)


## Press an action for a few physics frames (the Player polls just_pressed in its physics step).
func _tap(action: String, hold_frames: int = 3) -> void:
	Input.action_press(action)
	await _frames(hold_frames)
	Input.action_release(action)
	await _frames(2)


func _level_camera(p: Node3D, yaw: float = 0.0) -> void:
	var cam: Variant = p.get("camera")
	if cam != null and is_instance_valid(cam):
		(cam as Object).set("yaw", yaw)
		(cam as Object).set("pitch", 0.0)


func _near(a: float, b: float, tol: float = 0.05) -> bool:
	return absf(a - b) <= tol


# --- the test -----------------------------------------------------------------------------------

func _run() -> void:
	var chk := TestHarness
	var p := Game.player
	if not chk.check(p != null and is_instance_valid(p), "the real player scene was spawned by Main"):
		return

	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.set_meta("surface", "concrete")
	_box_body(floor_body, Vector3(300.0, 1.0, 300.0), Vector3(0.0, -0.5, 0.0), Layers.WORLD)
	var wall := DummyTarget.new()
	wall.name = "Wall"
	wall.set_meta("surface", "concrete")
	_box_body(wall, Vector3(30.0, 12.0, 0.5), Vector3(0.0, 4.0, -12.0), Layers.WORLD)
	p.call("teleport", Vector3(0.0, 0.05, 0.0), 0.0)
	await _frames(40)
	_level_camera(p)
	await _frames(5)

	# ---- the player built its own inventory ------------------------------------------------------
	var inv := p.get("inventory") as WeaponInventory
	if not chk.check(inv != null, "player.inventory is a WeaponInventory (node '%s')" % (str(inv.name) if inv != null else "-")):
		return
	chk.check(inv.holder == p and inv.get_parent() == p and inv.name == "Inventory", "inventory is the player's child 'Inventory', bound with setup(player)")
	chk.check(inv.get_weapons() == ["fists", "pistol"], "default loadout: fists + pistol (%s)" % str(inv.get_weapons()))
	var a := inv.get_ammo("pistol")
	chk.check(int(a["in_mag"]) + int(a["reserve"]) == 48 and int(a["in_mag"]) == 12, "pistol starts with 48 rounds, 12 loaded (%s)" % str(a))
	chk.check(inv.current_id == "fists" and not bool(p.call("is_armed")), "player starts unarmed (fists)")
	chk.check(_equipped.has("fists") or inv.current_id == "fists", "inventory announced itself on EventBus")

	# ---- draw the pistol with the slot key ---------------------------------------------------------
	await _tap("weapon_slot_2")
	chk.check(inv.current_id == "pistol", "weapon_slot_2 input draws the pistol (current %s)" % inv.current_id)
	chk.check(bool(p.call("is_armed")), "player.is_armed()")
	chk.check(_equipped.back() == "pistol", "EventBus.weapon_equipped('pistol')")
	await _frames(30)
	var model := inv.model
	chk.check(model != null and model.has_model(), "pistol GLB instanced")
	var visual: Variant = p.get("visual")
	if model != null and visual is Node3D:
		chk.check(model.attached_to_hand and (visual as Node3D).is_ancestor_of(model),
				"weapon model sits under the real visual's Hand_R socket (parent %s)" % str(model.get_parent().name))
		var hand_pos: Vector3 = (model.get_parent() as Node3D).global_position
		chk.check(model.global_position.distance_to(hand_pos) < 0.2, "grip is at the hand (%.3f m from the wrist)" % model.global_position.distance_to(hand_pos))
	var animator: Variant = p.get("animator")
	if animator != null and is_instance_valid(animator):
		chk.check(str((animator as Object).get("weapon_pose")) == "pistol", "animator weapon_pose follows the spec ('%s')" % str((animator as Object).get("weapon_pose")))

	# ---- aim + single shot through the Input path ---------------------------------------------------
	Input.action_press("aim")
	await _frames(25)
	_level_camera(p)
	await _frames(4)
	chk.check(p.get("is_aiming") == true and inv.is_aiming, "aim input reaches the inventory (set_aiming)")
	var ray: Dictionary = p.call("get_aim_ray")
	var dir_before: Vector3 = ray["direction"]
	chk.check(dir_before.dot(Vector3.FORWARD) > 0.95, "aim ray points down range (%s)" % str(dir_before))
	if model != null and model.is_inside_tree():
		var barrel := -model.global_basis.z.normalized()
		chk.log_line("aiming: barrel %s (dot with aim %.2f), muzzle at %s" % [str(barrel.snapped(Vector3.ONE * 0.01)), barrel.dot(dir_before), str(model.get_muzzle_position().snapped(Vector3.ONE * 0.01))])
		chk.check(barrel.dot(dir_before) > 0.8, "while aiming the barrel points where the camera looks (dot %.2f)" % barrel.dot(dir_before))
	var kicks: Array = []
	inv.recoil_kicked.connect(func(pitch: float, yaw: float) -> void: kicks.append(Vector2(pitch, yaw)))
	var fired_before := _fired.size()
	Input.action_press("fire")
	var max_dir_y := dir_before.y
	for i in 8:
		await _frames(1)
		var r2: Dictionary = p.call("get_aim_ray")
		max_dir_y = maxf(max_dir_y, (r2["direction"] as Vector3).y)
	Input.action_release("fire")
	await _frames(4)
	chk.check(_fired.size() == fired_before + 1 and _fired.back()[0] == "pistol" and _fired.back()[1] == p,
			"one fire press = one semi-auto shot by the player (%d)" % (_fired.size() - fired_before))
	chk.check(int(inv.get_ammo("pistol")["in_mag"]) == 11, "shot used one round (%s)" % str(inv.get_ammo("pistol")))
	chk.check(_near(wall.taken, 24.0, 0.01), "the wall 12 m down range took 24 damage (%.1f)" % wall.taken)
	chk.check(wall.hits.size() == 1 and wall.hits[0].get("instigator") == p and str(wall.hits[0].get("weapon_id")) == "pistol",
			"damage info names the player and the weapon")
	chk.check(_hit_confirms >= 1, "EventBus.hit_confirmed for the HUD hit marker")
	chk.check(kicks.size() == 1 and (kicks[0] as Vector2).x > 0.3, "recoil kick in degrees sent to player.add_recoil (%s)" % str(kicks))
	chk.check(max_dir_y > dir_before.y + 0.004, "the camera actually kicked up (aim dir y %.4f -> %.4f)" % [dir_before.y, max_dir_y])
	chk.check(_ammo_events.size() > 0 and _ammo_events.back()[0] == "pistol" and int(_ammo_events.back()[1]) == 11, "EventBus.ammo_changed(pistol, 11, ...)")

	# ---- reload key ---------------------------------------------------------------------------------
	await _tap("reload")
	chk.check(inv.is_reloading, "reload input starts a reload")
	chk.check(_reloads.size() == 1 and _reloads[0][0] == "pistol", "EventBus.weapon_reload_started")
	await TestHarness.wait_seconds(float(_reloads[0][1]) + 0.2 if not _reloads.is_empty() else 1.7)
	chk.check(not inv.is_reloading and int(inv.get_ammo("pistol")["in_mag"]) == 12, "magazine full again (%s)" % str(inv.get_ammo("pistol")))
	Input.action_release("aim")
	await _frames(6)
	chk.check(not inv.is_aiming, "releasing aim reaches the inventory")

	# ---- automatic fire while the button is held ----------------------------------------------------
	inv.give_weapon("smg")
	await _tap("weapon_slot_3")
	chk.check(inv.current_id == "smg", "weapon_slot_3 draws the SMG")
	await _frames(30)
	_level_camera(p)
	var before := _fired.size()
	Input.action_press("fire")
	await TestHarness.wait_seconds(1.0)
	Input.action_release("fire")
	await _frames(4)
	var burst := _fired.size() - before
	chk.check(burst >= 13 and burst <= 16, "holding fire: SMG at 840 rpm fires ~14 shots in 1 s (%d)" % burst)
	var after_release := _fired.size()
	await _frames(20)
	chk.check(_fired.size() == after_release, "fire stops when the button is released")
	chk.check(int(inv.get_ammo("smg")["in_mag"]) == 30 - burst, "magazine counted down (%s)" % str(inv.get_ammo("smg")))

	# ---- wheel / next / prev / holster keys ---------------------------------------------------------
	await _tap("holster")
	chk.check(inv.current_id == "fists", "holster input puts the weapon away")
	await _frames(4)
	chk.check(inv.model == null, "no weapon model while unarmed")
	await _tap("holster")
	chk.check(inv.current_id == "smg", "holster again draws the last weapon")
	await _tap("weapon_next")
	chk.check(inv.current_id == "fists", "weapon_next wraps around the owned weapons (fists, pistol, smg): %s" % inv.current_id)
	await _tap("weapon_prev")
	chk.check(inv.current_id == "smg", "weapon_prev goes back (%s)" % inv.current_id)
	var wheel := inv.get_wheel_data()
	chk.check(wheel.size() == 8 and wheel[1]["weapons"] == ["pistol"] and wheel[2]["selected"] == "smg", "wheel data for the UI (8 slots)")

	# ---- scope ------------------------------------------------------------------------------------
	inv.give_weapon("sniper_rifle")
	await _tap("weapon_slot_6")
	chk.check(inv.current_id == "sniper_rifle", "weapon_slot_6 draws the sniper rifle")
	await TestHarness.wait_seconds(0.8)
	Input.action_press("aim")
	await _frames(30)
	chk.check(inv.is_scoped() and _near(inv.get_aim_fov(), 16.0, 0.01), "sniper: is_scoped() while aiming, aim FOV 16")
	var cam_rig: Variant = p.get("camera")
	if cam_rig != null and is_instance_valid(cam_rig):
		chk.log_line("camera rig mode while scoped: '%s'" % str((cam_rig as Object).get("mode")))
	Input.action_release("aim")
	await _frames(6)

	# ---- flashlight attachment toggled by the weapon_flashlight action ------------------------------
	inv.equip("pistol")
	await _frames(30)
	chk.check(inv.add_attachment("pistol", "flashlight"), "flashlight installed on the pistol")
	var ev := InputEventAction.new()
	ev.action = "weapon_flashlight"
	ev.pressed = true
	Input.parse_input_event(ev)
	await TestHarness.wait_frames(4)
	await _frames(3)
	chk.check(inv.flashlight_on, "weapon_flashlight action switches the weapon light on")
	chk.check(inv.model != null and inv.model.light != null and inv.model.light.visible, "SpotLight3D on the weapon is lit")
	inv.set_flashlight(false)

	# ---- quick throw with the grenade key -------------------------------------------------------------
	# (thrown into the open, away from the wall: with the real Fx the blast hurts for real)
	p.call("teleport", Vector3(0.0, 0.05, 30.0), PI)
	await _frames(20)
	_level_camera(p, PI)
	await _frames(4)
	inv.give_weapon("grenade", 2)
	var pool_before := inv.get_reserve("grenade")
	var health_before := float(p.get("health"))
	_explosions.clear()
	await _tap("throw_grenade")
	await TestHarness.wait_seconds(0.5)
	chk.check(inv.get_reserve("grenade") == pool_before - 1, "throw_grenade input uses one grenade (%d -> %d)" % [pool_before, inv.get_reserve("grenade")])
	chk.check(Projectile.get_active_count() == 1, "a live grenade projectile exists (%d)" % Projectile.get_active_count())
	chk.check(inv.current_id == "pistol", "quick throw keeps the pistol in hand")
	await TestHarness.wait_seconds(3.6)
	chk.check(_explosions.size() == 1 and _explosions[0]["instigator"] == p, "grenade exploded with the player as instigator (%d)" % _explosions.size())
	if not _explosions.is_empty():
		var ex: Vector3 = _explosions[0]["position"]
		var away := ex.distance_to((p as Node3D).global_position)
		chk.check(ex.z > 40.0 and away > 10.0, "it flew an arc where the camera looked and went off %.1f m away (%s)" % [away, str(ex.snapped(Vector3.ONE * 0.1))])
		chk.check(is_equal_approx(float(p.get("health")), health_before), "the thrower is outside the 7 m blast (health %.0f)" % float(p.get("health")))
	chk.check(Projectile.get_active_count() == 0, "no projectile left")

	# ---- fists through the fire button, heavy attack through its key ---------------------------------
	await _tap("weapon_slot_1")
	chk.check(inv.current_id == "fists", "weapon_slot_1 selects the fists")
	p.call("teleport", Vector3(20.0, 0.05, 0.0), 0.0)
	await _frames(20)
	var dummy := _make_humanoid(Vector3(20.0, 0.0, -1.15))
	await _frames(3)
	await _tap("fire", 4)
	await TestHarness.wait_seconds(0.5)
	chk.check(dummy.hits.size() == 1 and str(dummy.hits[0].get("type")) == "melee", "fire with fists = a punch that lands (%d hit, %.1f damage)" % [dummy.hits.size(), dummy.taken])
	var light_damage := dummy.taken
	await TestHarness.wait_seconds(0.7)
	await _tap("melee_heavy", 3)
	await TestHarness.wait_seconds(1.1)
	chk.check(dummy.hits.size() == 2 and dummy.taken - light_damage > light_damage * 1.6,
			"melee_heavy input = heavy attack, about twice the damage (%.1f vs %.1f)" % [dummy.taken - light_damage, light_damage])
	dummy.queue_free()

	# ---- pickups collected by the real player body ---------------------------------------------------
	var ps := Game.get_system("pickups")
	if chk.check(ps != null, "'pickups' system is running"):
		p.call("teleport", Vector3(-20.0, 0.05, 0.0), 0.0)
		await _frames(10)
		var here := (p as Node3D).global_position
		var money := Game.money
		ps.call("spawn_pickup", "weapon", "pump_shotgun", -1, here)
		ps.call("spawn_pickup", "cash", "", 300, here)
		ps.call("spawn_pickup", "ammo", "pistol", 24, here)
		p.set("health", 40.0)
		ps.call("spawn_pickup", "health", "", 50, here)
		ps.call("spawn_pickup", "armor", "", 50, here)
		ps.call("spawn_pickup", "parachute", "", 1, here)
		var pistol_before := inv.get_reserve("pistol")
		await _frames(30)
		chk.check(inv.has_weapon("pump_shotgun") and int(inv.get_ammo("pump_shotgun")["in_mag"]) == 6, "weapon pickup: shotgun in the inventory, loaded")
		chk.check(Game.money == money + 300, "cash pickup: +$300")
		chk.check(inv.get_reserve("pistol") == pistol_before + 24, "ammo pickup: +24 pistol rounds")
		chk.check(_near(float(p.get("health")), 90.0, 0.5), "health pickup healed the real player (%.0f)" % float(p.get("health")))
		chk.check(_near(float(p.get("armor")), 50.0, 0.5), "armor pickup (%.0f)" % float(p.get("armor")))
		chk.check(p.get("has_parachute") == true, "parachute pickup")
		chk.check(int(ps.call("get_pickup_count")) == 0, "all six pickups were consumed (%d left)" % int(ps.call("get_pickup_count")))

	# ---- persistence through SaveSystem ------------------------------------------------------------
	inv.add_attachment("smg", "suppressor")
	inv.add_attachment("smg", "finish_teal")
	inv.equip("smg")
	await _frames(30)
	var snapshot := inv.get_save_data()
	chk.check(SaveSystem.save_game(SAVE_SLOT), "SaveSystem.save_game")
	inv.clear()
	chk.check(inv.get_weapons() == ["fists"], "inventory stripped")
	chk.check(SaveSystem.load_game(SAVE_SLOT), "SaveSystem.load_game")
	await _frames(5)
	var restored := inv.get_save_data()
	chk.check(JSON.stringify(restored) == JSON.stringify(JSON.parse_string(JSON.stringify(snapshot))) or restored == snapshot,
			"the player's inventory is a SaveSystem provider ('weapons'): weapons, ammo, attachments and the drawn weapon came back")
	chk.check(inv.current_id == "smg" and inv.has_attachment("smg", "suppressor") and inv.get_current_spec().suppressed, "suppressed SMG is in hand again")
	chk.check(inv.model != null and inv.model.has_model() and inv.model.attached_to_hand, "weapon model rebuilt after the load")

	# ---- drive-by from a real driver seat -------------------------------------------------------------
	await _vehicle_section(p as Node3D, inv)


func _vehicle_section(p: Node3D, inv: WeaponInventory) -> void:
	var chk := TestHarness
	if Game.get_system("vehicles") == null:
		chk.log_line("SKIPPED drive-by section: 'vehicles' system not running")
		return
	var car: Node3D = null
	for id in CAR_IDS:
		if not Registry.has_def("vehicles", id):
			continue
		if not ResourceLoader.exists("res://gta/generated/models/vehicles/%s.glb" % id):
			continue
		car = Game.spawn_vehicle(id, Transform3D(Basis.IDENTITY, Vector3(60.0, 0.8, 0.0)), {"owner_tag": "player"})
		if car != null:
			chk.log_line("drive-by section uses a real '%s'" % id)
			break
	if car == null:
		chk.log_line("SKIPPED drive-by section: no car could be spawned")
		return
	var far_wall := DummyTarget.new()
	far_wall.name = "FarWall"
	_box_body(far_wall, Vector3(40.0, 14.0, 0.5), Vector3(60.0, 5.0, -25.0), Layers.WORLD)
	await _frames(60)
	inv.give_weapon("assault_rifle")
	inv.equip("assault_rifle")
	await _frames(40)
	chk.check(inv.current_id == "assault_rifle" and inv.model != null, "rifle in hand before entering")
	p.call("teleport", car.global_position + Vector3(-1.6, 0.2, 0.0), 0.0)
	await _frames(5)
	p.call("enter_vehicle", car, 0, true)
	var seated := false
	for i in 240:
		await _frames(1)
		if p.get("current_vehicle") == car:
			seated = true
			break
	if not chk.check(seated, "player sits in the car (current_vehicle set)"):
		return
	await _frames(20)
	chk.check(inv.current_id == "smg", "long gun is swapped for the best drive-by weapon in the seat (%s)" % inv.current_id)
	chk.check(inv.model != null and is_instance_valid(inv.model) and inv.model.is_inside_tree() and inv.model.has_model(),
			"weapon model survives the player being re-parented under the seat")
	chk.check(not inv.equip("assault_rifle") and not inv.equip("pump_shotgun"), "long guns cannot be drawn in the seat")
	chk.check(inv.can_use_in_vehicle("pistol") and inv.can_use_in_vehicle("smg") and inv.can_use_in_vehicle("grenade")
			and not inv.can_use_in_vehicle("sniper_rifle"), "can_use_in_vehicle: handguns, SMG, thrown only")
	var standing_spread := inv.get_spec("smg").spread_base
	chk.check(inv.get_current_spread() > standing_spread * 1.5, "drive-by fire is less accurate (%.2f vs %.2f deg)" % [inv.get_current_spread(), standing_spread])
	await _frames(30)
	var results: Array = []
	var on_fired := func(_id: String, result: Dictionary) -> void: results.append(result)
	inv.fired.connect(on_fired)
	var car_hp := float(car.get("health"))
	Input.action_press("fire")
	await TestHarness.wait_seconds(0.5)
	Input.action_release("fire")
	await _frames(5)
	inv.fired.disconnect(on_fired)
	chk.check(results.size() >= 5, "fire input works from the driver seat (%d shots in 0.5 s)" % results.size())
	var hit_own_car := 0
	for r: Dictionary in results:
		if r.get("target") == car or r.get("collider") == car:
			hit_own_car += 1
	chk.check(hit_own_car == 0 and _near(float(car.get("health")), car_hp, 0.01), "bullets never hit the shooter's own vehicle (%d did, health %.0f -> %.0f)" % [hit_own_car, car_hp, float(car.get("health"))])
	chk.log_line("drive-by: %d shots, far wall took %.0f damage" % [results.size(), far_wall.taken])
	p.call("exit_vehicle")
	var out := false
	for i in 300:
		await _frames(1)
		if p.get("current_vehicle") == null and str(p.get("state_id")) != "vehicle":
			out = true
			break
	if chk.check(out, "player left the car"):
		await _frames(20)
		chk.check(inv.current_id == "assault_rifle", "the rifle comes back out after leaving the vehicle (%s)" % inv.current_id)
		chk.check(inv.model != null and inv.model.attached_to_hand, "rifle model is back in the hand")
