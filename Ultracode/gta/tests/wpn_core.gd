extends Node
## Headless test of the weapons / combat module.
## Run:
##   tools\godot.ps1 -Mode headless -Frames 5000 -UserArgs '--test=wpn_core','--no_player','--disable=world,environment,city,interactions,vehicles,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Builds its own little range: floor, a damageable wall, humanoid-sized dummies, a dummy
## vehicle, a glass pane. Prints the balance table as lines starting with "BALANCE|".


class DummyOwner extends Node3D:
	var aim_target: Vector3 = Vector3(0.0, 1.2, -5.0)
	var recoil_pitch_total: float = 0.0
	var recoil_yaw_abs_total: float = 0.0
	var recoil_calls: int = 0
	var current_vehicle: Node3D = null
	var is_crouching: bool = false
	var velocity: Vector3 = Vector3.ZERO
	var actions: Array = []
	var is_dead: bool = false

	func get_aim_ray() -> Dictionary:
		var o := global_position + Vector3.UP * 1.55
		return {"origin": o, "direction": (aim_target - o).normalized()}

	func add_recoil(pitch: float, yaw: float) -> void:
		recoil_pitch_total += pitch
		recoil_yaw_abs_total += absf(yaw)
		recoil_calls += 1

	func play_weapon_action(action: String, _duration: float) -> void:
		actions.append(action)


class DummyTarget extends StaticBody3D:
	var taken: float = 0.0
	var hits: Array = []
	var is_dead: bool = false
	var knocked: int = 0
	var dies_at: float = 0.0            ## > 0: is_dead once this much damage was taken

	func apply_damage(info: Dictionary) -> void:
		taken += float(info.get("amount", 0.0))
		hits.append(info)
		if dies_at > 0.0 and taken >= dies_at:
			is_dead = true

	func knock_down(_impulse: Vector3) -> void:
		knocked += 1

	func reset() -> void:
		taken = 0.0
		hits.clear()
		knocked = 0


class DummyVehicle extends RigidBody3D:
	var taken: float = 0.0
	var popped: Array = []
	var is_player_driven: bool = false

	func apply_damage(info: Dictionary) -> void:
		taken += float(info.get("amount", 0.0))

	func pop_tire(index: int) -> void:
		popped.append(index)


const FIREARMS: Array[String] = ["pistol", "heavy_pistol", "smg", "pump_shotgun", "auto_shotgun",
		"assault_rifle", "carbine", "marksman_rifle", "sniper_rifle"]
const ALL_IDS: Array[String] = ["fists", "knife", "bat", "crowbar", "pistol", "heavy_pistol", "smg",
		"pump_shotgun", "auto_shotgun", "assault_rifle", "carbine", "marksman_rifle", "sniper_rifle",
		"grenade", "rocket_launcher", "grenade_launcher", "molotov"]

var _root: Node3D
var _fired_count: int = 0
var _fired_ids: Array = []
var _explosions: Array = []         # {position, radius, instigator}
var _noises: Array = []             # {position, radius, kind}
var _fires: Array = []
var _equipped_events: Array = []
var _ammo_events: Array = []
var _reload_events: Array = []
var _inventory_events: int = 0
var _hit_confirms: int = 0
var _crimes: Array = []


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "WpnRange"
	add_child(_root)
	EventBus.weapon_fired.connect(func(id: String, _s: Node, _o: Vector3, _d: Vector3) -> void:
		_fired_count += 1
		_fired_ids.append(id))
	EventBus.explosion.connect(func(pos: Vector3, radius: float, who: Node) -> void:
		_explosions.append({"position": pos, "radius": radius, "instigator": who}))
	EventBus.noise_emitted.connect(func(pos: Vector3, radius: float, kind: String, _who: Node) -> void:
		_noises.append({"position": pos, "radius": radius, "kind": kind}))
	EventBus.fire_started.connect(func(pos: Vector3, _src: Node) -> void: _fires.append(pos))
	EventBus.weapon_equipped.connect(func(id: String) -> void: _equipped_events.append(id))
	EventBus.ammo_changed.connect(func(id: String, in_mag: int, reserve: int) -> void:
		_ammo_events.append([id, in_mag, reserve]))
	EventBus.weapon_reload_started.connect(func(id: String, duration: float) -> void:
		_reload_events.append([id, duration]))
	EventBus.weapon_inventory_changed.connect(func() -> void: _inventory_events += 1)
	EventBus.hit_confirmed.connect(func(_t: Node, _i: Dictionary) -> void: _hit_confirms += 1)
	EventBus.crime_committed.connect(func(id: String, _p: Vector3, _w: Node) -> void: _crimes.append(id))
	await _run()
	TestHarness.finish()


# --- scene helpers ------------------------------------------------------------------------------

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


func _make_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.set_meta("surface", "concrete")
	_box_body(floor_body, Vector3(400.0, 1.0, 400.0), Vector3(0.0, -0.5, 0.0), Layers.WORLD)


func _make_wall(at: Vector3, size: Vector3 = Vector3(12.0, 6.0, 0.5)) -> DummyTarget:
	var wall := DummyTarget.new()
	wall.name = "Wall"
	wall.set_meta("surface", "concrete")
	_box_body(wall, size, at, Layers.WORLD)
	return wall


func _make_humanoid(at: Vector3, group: String = "npc") -> DummyTarget:
	var h := DummyTarget.new()
	h.name = "Humanoid"
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	h.add_child(shape)
	h.collision_layer = Layers.NPC if group == "npc" else Layers.PLAYER
	h.collision_mask = 0
	h.add_to_group(group)
	_root.add_child(h)
	h.global_position = at
	return h


func _make_owner(at: Vector3, as_player: bool = false) -> DummyOwner:
	var o := DummyOwner.new()
	o.name = "DummyOwner"
	if as_player:
		o.add_to_group("player")
	_root.add_child(o)
	o.global_position = at
	o.aim_target = at + Vector3(0.0, 1.2, -5.0)
	return o


func _make_inventory(holder: Node) -> WeaponInventory:
	var inv := WeaponInventory.new()
	inv.name = "Inventory"
	holder.add_child(inv)
	inv.setup(holder)
	return inv


func _frames(n: int) -> void:
	await TestHarness.wait_physics_frames(n)


func _near(a: float, b: float, tol: float = 0.05) -> bool:
	return absf(a - b) <= tol


func _equip_ready(inv: WeaponInventory, id: String) -> void:
	inv.equip(id)
	var spec := inv.get_current_spec()
	await _frames(int(ceil(spec.equip_time * 60.0)) + 3)


# --- the test -----------------------------------------------------------------------------------

func _run() -> void:
	var chk := TestHarness
	_make_floor()
	var humanoid := _make_humanoid(Vector3(0.0, 0.0, -5.0))
	var wall := _make_wall(Vector3(0.0, 3.0, -30.0))
	var owner_a := _make_owner(Vector3.ZERO)
	await _frames(4)

	# ---- registry ---------------------------------------------------------------------------
	var missing: Array = []
	for id in ALL_IDS:
		if not (Registry.get_def("weapons", id) is WeaponSpec):
			missing.append(id)
	chk.check(missing.is_empty(), "all 17 weapon specs registered (missing: %s)" % str(missing))
	chk.check(Registry.count("weapons") >= 17, "registry holds >= 17 weapons (%d)" % Registry.count("weapons"))
	chk.check(Registry.count("attachments") >= 10, "attachments registered (%d)" % Registry.count("attachments"))
	var slots_used: Dictionary = {}
	for id in ALL_IDS:
		var s := WeaponSpec.resolve(id)
		if s != null:
			slots_used[s.slot] = true
			if not WeaponSpec.SLOTS.has(s.slot) or not WeaponSpec.FIRE_MODES.has(s.fire_mode):
				chk.check(false, "spec %s has a valid slot / fire mode" % id)
			if s.uses_ammo() and not WeaponSpec.AMMO_MAX.has(s.ammo_type):
				chk.check(false, "spec %s has a valid ammo type" % id)
	chk.check(slots_used.size() == 8, "all 8 wheel slots are populated (%d)" % slots_used.size())
	if not missing.is_empty():
		return

	# ---- Combat.fire_hitscan: damage numbers, zones, pellets, falloff ---------------------------
	var eye := Vector3(0.0, 1.5, 0.0)
	for id in FIREARMS:
		var spec := WeaponSpec.resolve(id)
		var full := spec.damage * float(spec.pellets)
		humanoid.reset()
		var r := Combat.fire_hitscan(eye, Vector3(0.0, 1.2, -5.0) - eye, id, owner_a, {"spread_deg": 0.0})
		var ok_torso: bool = bool(r["hit"]) and r["target"] == humanoid and _near(humanoid.taken, full) and str(r["zone"]) == "torso"
		chk.check(ok_torso, "%s torso hit = %.1f (got %.1f, zone %s)" % [id, full, humanoid.taken, str(r["zone"])])
		humanoid.reset()
		r = Combat.fire_hitscan(eye, Vector3(0.0, 1.66, -5.0) - eye, id, owner_a, {"spread_deg": 0.0})
		chk.check(bool(r["headshot"]) and _near(humanoid.taken, full * spec.headshot_mult),
				"%s head shot = %.1f x%.2f (got %.1f)" % [id, full, spec.headshot_mult, humanoid.taken])
		humanoid.reset()
		r = Combat.fire_hitscan(eye, Vector3(0.0, 0.4, -5.0) - eye, id, owner_a, {"spread_deg": 0.0})
		chk.check(str(r["zone"]) == "limb" and _near(humanoid.taken, full * spec.limb_mult),
				"%s limb hit = %.1f (got %.1f)" % [id, full * spec.limb_mult, humanoid.taken])
		if spec.pellets > 1:
			chk.check(int((humanoid.hits[0] as Dictionary).get("pellets", 0)) == spec.pellets and humanoid.hits.size() == 1,
					"%s delivers %d pellets in one apply_damage" % [id, spec.pellets])
		# wall at 30 m: range falloff, no zones
		if spec.max_range > 31.0:
			wall.reset()
			var wall_eye := Vector3(3.0, 1.5, 0.0)
			r = Combat.fire_hitscan(wall_eye, Vector3(3.0, 1.5, -29.75) - wall_eye, id, owner_a, {"spread_deg": 0.0})
			var expect := full * spec.falloff_at(29.75)
			chk.check(r["target"] == wall and _near(wall.taken, expect, 0.1),
					"%s wall hit at 30 m with falloff = %.1f (got %.1f)" % [id, expect, wall.taken])
	# spread actually spreads pellets
	var distinct: Dictionary = {}
	var rs := Combat.fire_hitscan(eye, Vector3(3.0, 1.5, -29.0) - eye, "pump_shotgun", owner_a, {})
	for h: Dictionary in rs["hits"]:
		distinct[(h["position"] as Vector3).snapped(Vector3.ONE * 0.01)] = true
	chk.check(distinct.size() >= 4, "shotgun pellets land on distinct points (%d)" % distinct.size())
	# out of range
	wall.reset()
	var far_eye := Vector3(3.0, 1.5, 40.0)
	Combat.fire_hitscan(far_eye, Vector3(0.0, 0.0, -1.0), "pump_shotgun", owner_a, {"spread_deg": 0.0})
	chk.check(wall.taken == 0.0, "shotgun does not reach a wall 70 m away")

	# ---- penetration: sniper goes through a body, pistol does not -----------------------------
	humanoid.reset()
	wall.reset()
	var level_eye := Vector3(0.0, 1.2, 0.0)
	var pr := Combat.fire_hitscan(level_eye, Vector3(0.0, 0.0, -1.0), "sniper_rifle", owner_a, {"spread_deg": 0.0})
	var sniper := WeaponSpec.resolve("sniper_rifle")
	chk.check(_near(humanoid.taken, sniper.damage) and _near(wall.taken, sniper.damage * 0.65 * sniper.falloff_at(29.75), 0.2) and (pr["hits"] as Array).size() == 2,
			"sniper round passes through a body into the wall behind at 65%% power (%.1f / %.1f)" % [humanoid.taken, wall.taken])
	humanoid.reset()
	wall.reset()
	Combat.fire_hitscan(level_eye, Vector3(0.0, 0.0, -1.0), "pistol", owner_a, {"spread_deg": 0.0})
	chk.check(humanoid.taken > 0.0 and wall.taken == 0.0, "pistol round stops in the body")

	# ---- glass + thin-surface penetration -----------------------------------------------------
	var glass := DummyTarget.new()
	glass.name = "GlassPane"
	glass.set_meta("surface", "glass")
	_box_body(glass, Vector3(2.0, 2.0, 0.05), Vector3(20.0, 1.5, -3.0), Layers.GLASS)
	var behind := _make_humanoid(Vector3(20.0, 0.0, -6.0))
	await _frames(3)
	var g_eye := Vector3(20.0, 1.5, 0.0)
	Combat.fire_hitscan(g_eye, Vector3(0.0, -0.05, -1.0), "assault_rifle", owner_a, {"spread_deg": 0.0})
	var ar := WeaponSpec.resolve("assault_rifle")
	chk.check(glass.taken > 0.0 and _near(behind.taken, ar.damage * 0.9, 0.2),
			"rifle round breaks glass (Dmg contract) and hits behind it at 90%% (glass %.1f, behind %.1f)" % [glass.taken, behind.taken])
	glass.reset()
	behind.reset()
	Combat.fire_hitscan(g_eye, Vector3(0.0, -0.05, -1.0), "pistol", owner_a, {"spread_deg": 0.0})
	chk.check(glass.taken > 0.0 and behind.taken == 0.0, "pistol round damages the glass but does not penetrate")

	# ---- vehicle: tyre pop + shooter's own vehicle is ignored ---------------------------------
	var car := DummyVehicle.new()
	car.name = "DummyCar"
	car.freeze = true
	car.add_to_group("vehicle")
	var wheel := Node3D.new()
	wheel.name = "Wheel_FL"
	car.add_child(wheel)
	wheel.position = Vector3(-0.9, -0.35, 0.0)
	var wheel2 := Node3D.new()
	wheel2.name = "Wheel_FR"
	car.add_child(wheel2)
	wheel2.position = Vector3(0.9, -0.35, 0.0)
	_box_body(car, Vector3(1.8, 1.4, 4.0), Vector3(40.0, 0.7, -8.0), Layers.VEHICLE)
	var behind_car := _make_humanoid(Vector3(40.0, 0.0, -14.0))
	await _frames(3)
	var c_eye := Vector3(40.0, 1.0, 0.0)
	Combat.fire_hitscan(Vector3(44.0, 0.5, -8.0), Vector3(-1.0, 0.0, 0.0), "pistol", owner_a, {"spread_deg": 0.0})
	chk.check(car.taken > 0.0 and car.popped == [1], "bullet next to Wheel_FR pops tyre index 1 (%s)" % str(car.popped))
	car.popped.clear()
	Combat.fire_hitscan(Vector3(44.0, 1.2, -6.5), Vector3(-1.0, 0.0, 0.0), "pistol", owner_a, {"spread_deg": 0.0})
	chk.check(car.popped.is_empty(), "a body hit away from the wheels pops nothing")
	chk.check(Fx.surface_of(car) == "metal", "vehicle surface resolves to metal")
	owner_a.current_vehicle = car
	car.taken = 0.0
	Combat.fire_hitscan(c_eye, Vector3(40.0, 1.0, -14.0) - c_eye, "pistol", owner_a, {"spread_deg": 0.0})
	chk.check(car.taken == 0.0 and behind_car.taken > 0.0, "the shooter's own vehicle is excluded from the ray")
	owner_a.current_vehicle = null

	# ---- line of sight ------------------------------------------------------------------------
	chk.check(Combat.has_line_of_sight(Vector3(60.0, 1.5, 0.0), Vector3(60.0, 1.5, -20.0)), "line of sight in the open")
	chk.check(not Combat.has_line_of_sight(Vector3(0.0, 1.5, -20.0), Vector3(0.0, 1.5, -40.0)), "wall blocks line of sight")
	chk.check(Combat.has_line_of_sight(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -20.0)), "characters do not block line of sight")
	chk.check(Combat.has_line_of_sight(Vector3(40.0, 1.0, 0.0), Vector3(40.0, 1.0, -14.0), [car]), "exclude list is honoured")

	# ---- inventory basics ---------------------------------------------------------------------
	var inv := _make_inventory(owner_a)
	chk.check(inv.has_weapon("fists") and inv.current_id == "fists" and not inv.is_armed(), "fresh inventory: fists only, unarmed")
	chk.check(inv.get_weapons().size() == 1, "non-player holder gets no automatic loadout")
	inv.give_default_loadout()
	var a := inv.get_ammo("pistol")
	chk.check(inv.has_weapon("pistol") and int(a["in_mag"]) == 12 and int(a["reserve"]) == 36,
			"default loadout: pistol with 48 rounds as 12 + 36 (%s)" % str(a))
	chk.check(not inv.equip("smg"), "cannot equip a weapon that is not owned")
	var equip_signals: Array = []
	inv.equipped.connect(func(id: String) -> void: equip_signals.append(id))
	chk.check(inv.equip("pistol") and inv.current_id == "pistol" and inv.is_armed(), "equip pistol")
	chk.check(equip_signals == ["pistol"], "equipped signal emitted")
	chk.check(inv.model != null and inv.model.muzzle != null, "weapon model node with a muzzle marker exists")
	chk.check(inv.get_weapon_pose() == "pistol" and _near(inv.get_aim_fov(), 52.0), "pose / aim FOV exposed for the equipped weapon")
	# no shot during the draw time
	var before := _fired_count
	inv.trigger_pressed()
	inv.trigger_released()
	chk.check(_fired_count == before, "no shot during the equip time")
	await _frames(22)

	# single shot through the full path (aim ray -> hitscan -> ammo / recoil / signals)
	humanoid.reset()
	var local_fired: Array = []
	inv.fired.connect(func(id: String, res: Dictionary) -> void: local_fired.append([id, res]))
	before = _fired_count
	inv.trigger_pressed()
	inv.trigger_released()
	await _frames(2)
	chk.check(_fired_count == before + 1 and local_fired.size() == 1, "one trigger pull = one shot (semi)")
	chk.check(int(inv.get_ammo("pistol")["in_mag"]) == 11, "shot consumed one round")
	chk.check(_near(humanoid.taken, 24.0, 0.1), "inventory shot damaged the dummy for 24 (got %.1f)" % humanoid.taken)
	chk.check(owner_a.recoil_calls == 1 and _near(owner_a.recoil_pitch_total, 1.2, 0.001), "recoil sent to the holder in degrees (pitch %.2f)" % owner_a.recoil_pitch_total)
	chk.check(_noises.size() > 0 and _near(float((_noises.back() as Dictionary)["radius"]), 65.0, 0.1) and str((_noises.back() as Dictionary)["kind"]) == "gunshot",
			"gunshot noise emitted with the weapon's radius")
	chk.check(_equipped_events.is_empty() and _ammo_events.is_empty(), "HUD EventBus signals stay silent for a non-player holder")

	# semi-auto cadence: hammering the trigger for 1 s is capped by the fire rate (400 rpm)
	inv.refill_all()
	await _frames(30)
	before = _fired_count
	for i in 60:
		inv.trigger_pressed()
		await _frames(1)
		inv.trigger_released()
	var semi_shots := _fired_count - before
	chk.check(semi_shots >= 6 and semi_shots <= 8, "pistol fire rate capped at ~6.7 shots/s (%d in 1 s)" % semi_shots)
	# spread bloom and recovery
	var pistol := inv.get_current_spec()
	chk.check(inv.get_current_spread() > pistol.spread_base + 0.3, "spread grew while firing (%.2f > %.2f)" % [inv.get_current_spread(), pistol.spread_base])
	await _frames(90)
	chk.check(_near(inv.get_current_spread(), pistol.spread_base, 0.01), "spread recovered after 1.5 s")
	inv.set_aiming(true)
	chk.check(_near(inv.get_current_spread(), pistol.spread_base * pistol.spread_aim_mult, 0.01), "aiming tightens the spread")
	inv.set_aiming(false)
	owner_a.velocity = Vector3(6.0, 0.0, 0.0)
	chk.check(_near(inv.get_current_spread(), pistol.spread_base + pistol.spread_moving, 0.01), "moving widens the spread")
	owner_a.velocity = Vector3.ZERO
	owner_a.is_crouching = true
	chk.check(inv.get_current_spread() < pistol.spread_base, "crouching tightens the spread")
	owner_a.is_crouching = false

	# empty magazine -> dry fire -> automatic reload with the right timing
	var guard := 0
	while int(inv.get_ammo("pistol")["in_mag"]) > 0 and guard < 400:
		inv.trigger_pressed()
		inv.trigger_released()
		await _frames(1)
		guard += 1
	chk.check(int(inv.get_ammo("pistol")["in_mag"]) == 0, "magazine emptied")
	var reserve_before := int(inv.get_ammo("pistol")["reserve"])
	var reload_info: Array = []
	inv.reload_started.connect(func(id: String, d: float) -> void: reload_info.append([id, d]))
	guard = 0
	while not inv.is_reloading and guard < 60:
		await _frames(1)
		guard += 1
	chk.check(inv.is_reloading and reload_info.size() == 1 and _near(float(reload_info[0][1]), pistol.reload_time, 0.001),
			"automatic reload started with the spec duration (%s)" % str(reload_info))
	before = _fired_count
	inv.trigger_pressed()
	inv.trigger_released()
	chk.check(_fired_count == before, "cannot fire while reloading")
	await _frames(int(pistol.reload_time * 60.0) - 6)
	chk.check(inv.is_reloading, "still reloading shortly before the end")
	await _frames(12)
	a = inv.get_ammo("pistol")
	chk.check(not inv.is_reloading and int(a["in_mag"]) == 12 and int(a["reserve"]) == reserve_before - 12,
			"reload moved 12 rounds from the reserve into the magazine (%s)" % str(a))
	chk.check(owner_a.actions.has("reload"), "holder was asked to play the reload action")
	chk.check(not inv.reload(), "reload() refuses with a full magazine")

	# ---- automatic fire: SMG ------------------------------------------------------------------
	inv.give_weapon("smg")
	a = inv.get_ammo("smg")
	chk.check(int(a["in_mag"]) == 30 and int(a["reserve"]) == 90, "give_weapon(smg) = 120 rounds as 30 + 90")
	await _equip_ready(inv, "smg")
	var smg := inv.get_current_spec()
	owner_a.recoil_calls = 0
	owner_a.recoil_pitch_total = 0.0
	before = _fired_count
	inv.trigger_pressed()
	await _frames(60)
	inv.trigger_released()
	var auto_shots := _fired_count - before
	chk.check(auto_shots >= 13 and auto_shots <= 16, "SMG holds ~14 shots/s (840 rpm): %d in 1 s" % auto_shots)
	chk.check(int(inv.get_ammo("smg")["in_mag"]) == 30 - auto_shots, "automatic fire consumed %d rounds" % auto_shots)
	chk.check(owner_a.recoil_calls == auto_shots, "one recoil kick per shot")
	chk.check(inv.get_current_spread() > smg.spread_base + 1.0, "SMG spread bloomed (%.2f)" % inv.get_current_spread())
	await _frames(4)
	before = _fired_count
	await _frames(20)
	chk.check(_fired_count == before, "fire stops when the trigger is released")

	# ---- attachments --------------------------------------------------------------------------
	inv.refill_all()
	chk.check(not inv.add_attachment("pistol", "grip"), "incompatible attachment is refused")
	chk.check(not inv.add_attachment("carbine", "scope"), "attachment for a weapon that is not owned is refused")
	chk.check(inv.add_attachment("smg", "ext_mag") and inv.get_spec("smg").mag_size == 45, "extended magazine: 30 -> 45")
	inv.refill_all()
	chk.check(int(inv.get_ammo("smg")["in_mag"]) == 45, "refill fills the extended magazine")
	var base_smg := WeaponSpec.resolve("smg")
	chk.check(inv.add_attachment("smg", "grip") and _near(inv.get_spec("smg").recoil_pitch, base_smg.recoil_pitch * 0.75, 0.001),
			"grip reduces recoil by 25%")
	chk.check(inv.add_attachment("smg", "scope") and _near(inv.get_aim_fov(), base_smg.aim_fov * 0.62, 0.01),
			"scope narrows the aim FOV (%.1f)" % inv.get_aim_fov())
	chk.check(inv.add_attachment("smg", "suppressor") and inv.get_spec("smg").suppressed
			and _near(inv.get_spec("smg").noise_radius, base_smg.noise_radius * 0.17, 0.01)
			and inv.get_spec("smg").damage < base_smg.damage, "suppressor: quiet, slightly weaker")
	await _frames(12)
	_noises.clear()
	inv.trigger_pressed()
	inv.trigger_released()
	await _frames(2)
	var last_noise: Dictionary = _noises.back() if not _noises.is_empty() else {}
	chk.check(str(last_noise.get("kind", "")) == "suppressed_gunshot" and float(last_noise.get("radius", 99.0)) < 12.0,
			"suppressed shot emits a small 'suppressed_gunshot' noise (%s)" % str(last_noise))
	inv.add_attachment("smg", "finish_teal")
	inv.add_attachment("smg", "finish_coral")
	chk.check(inv.has_attachment("smg", "finish_coral") and not inv.has_attachment("smg", "finish_teal"), "a new finish replaces the old one")
	chk.check(inv.add_attachment("smg", "flashlight") and inv.has_flashlight(), "flashlight attachment installed")
	inv.set_flashlight(true)
	await _frames(2)
	chk.check(inv.model != null and inv.model.light != null and inv.model.light.visible, "flashlight SpotLight3D is on")
	inv.set_flashlight(false)
	await _frames(2)
	chk.check(inv.model.light != null and not inv.model.light.visible, "flashlight toggles off")
	inv.refill_all()
	var reserve_smg := int(inv.get_ammo("smg")["reserve"])
	inv.add_ammo("smg", -30)
	chk.check(inv.remove_attachment("smg", "ext_mag") and int(inv.get_ammo("smg")["in_mag"]) == 30
			and int(inv.get_ammo("smg")["reserve"]) == reserve_smg - 30 + 15, "removing the extended magazine returns the surplus rounds")
	chk.check(inv.get_attachments("smg").size() == 5, "attachment list: %s" % str(inv.get_attachments("smg")))

	# ---- slow cadences: pump and bolt ---------------------------------------------------------
	inv.give_weapon("pump_shotgun")
	await _equip_ready(inv, "pump_shotgun")
	before = _fired_count
	for i in 120:
		inv.trigger_pressed()
		await _frames(1)
		inv.trigger_released()
	var pump_shots := _fired_count - before
	chk.check(pump_shots == 3, "pump shotgun: 3 shots in 2 s at 64 rpm (%d)" % pump_shots)
	inv.give_weapon("sniper_rifle")
	await _equip_ready(inv, "sniper_rifle")
	chk.check(not inv.is_scoped(), "sniper is not scoped from the hip")
	inv.set_aiming(true)
	chk.check(inv.is_scoped() and _near(inv.get_aim_fov(), 16.0) and inv.get_current_spread() < 0.1, "sniper: scoped while aiming, FOV 16, pin-point")
	before = _fired_count
	for i in 120:
		inv.trigger_pressed()
		await _frames(1)
		inv.trigger_released()
	chk.check(_fired_count - before == 2, "bolt action: 2 shots in 2 s at 42 rpm (%d)" % (_fired_count - before))
	inv.set_aiming(false)

	# ---- selection ----------------------------------------------------------------------------
	inv.give_weapon("heavy_pistol")
	inv.give_weapon("knife")
	chk.check(inv.equip_slot(2) and inv.current_id == "pistol", "slot 2 selects the last used handgun")
	chk.check(inv.equip_slot("handgun") and inv.current_id == "heavy_pistol", "selecting the same slot cycles inside it")
	chk.check(inv.equip_slot(2) and inv.current_id == "pistol", "slot cycling wraps around")
	chk.check(not inv.equip_slot(7), "empty slot cannot be selected")
	var order: Array = inv.get_weapons()
	chk.check(order == ["fists", "knife", "pistol", "heavy_pistol", "smg", "pump_shotgun", "sniper_rifle"], "weapons listed in wheel order: %s" % str(order))
	inv.next_weapon()
	chk.check(inv.current_id == "heavy_pistol", "next_weapon")
	inv.prev_weapon()
	inv.prev_weapon()
	chk.check(inv.current_id == "knife", "prev_weapon")
	chk.check(inv.holster() and inv.current_id == "fists", "holster puts the weapon away")
	chk.check(inv.holster() and inv.current_id == "knife", "holster again draws the last weapon")
	var wheel_data: Array = inv.get_wheel_data()
	chk.check(wheel_data.size() == 8 and (wheel_data[1]["weapons"] as Array).size() == 2, "wheel data lists 8 slots")

	# ---- drive-by rule ------------------------------------------------------------------------
	chk.check(inv.can_use_in_vehicle("pistol") and inv.can_use_in_vehicle("heavy_pistol") and inv.can_use_in_vehicle("smg")
			and inv.can_use_in_vehicle("grenade") and inv.can_use_in_vehicle("molotov"), "handguns, SMG and thrown weapons are drive-by capable")
	var blocked: Array = []
	for id in ALL_IDS:
		if not inv.can_use_in_vehicle(id):
			blocked.append(id)
	chk.check(blocked.size() == 11 and blocked.has("assault_rifle") and blocked.has("rocket_launcher") and blocked.has("bat")
			and inv.can_use_in_vehicle("fists"),
			"long guns, launchers and melee weapons are not usable from a seat (%d blocked); being unarmed is" % blocked.size())
	inv.equip("sniper_rifle")
	await _frames(2)
	owner_a.current_vehicle = car
	await _frames(2)
	chk.check(inv.current_id == "smg", "entering a vehicle with a long gun switches to the best drive-by weapon (%s)" % inv.current_id)
	chk.check(not inv.equip("sniper_rifle"), "long gun cannot be drawn inside a vehicle")
	var foot_spread := inv.get_spec("smg").spread_base
	chk.check(inv.get_current_spread() > foot_spread * 1.5, "drive-by fire is less accurate")
	inv.equip("fists")
	before = _fired_count
	inv.trigger_pressed()
	await _frames(40)
	inv.trigger_released()
	chk.check(owner_a.actions.count("punch_r") == 0 and inv.equip_slot(2) and inv.current_id == "pistol",
			"unarmed in a seat: no punching, but a handgun can be drawn")
	owner_a.current_vehicle = null
	await _frames(2)
	chk.check(inv.current_id == "sniper_rifle", "leaving the vehicle restores the previous weapon")

	# ---- save / load round trip ---------------------------------------------------------------
	inv.equip("smg")
	var saved := inv.get_save_data()
	var json := JSON.stringify(saved)
	var parsed: Variant = JSON.parse_string(json)
	var owner_b := _make_owner(Vector3(-20.0, 0.0, 20.0))
	var inv_b := _make_inventory(owner_b)
	inv_b.load_save_data(parsed as Dictionary)
	var same := inv_b.get_weapons() == inv.get_weapons() and inv_b.current_id == "smg"
	for id: String in inv.get_weapons():
		var x := inv.get_ammo(id)
		var y := inv_b.get_ammo(id)
		if int(x["in_mag"]) != int(y["in_mag"]) or int(x["reserve"]) != int(y["reserve"]):
			same = false
		var att_a: Array = inv.get_attachments(id)
		var att_b: Array = inv_b.get_attachments(id)
		att_a.sort()
		att_b.sort()
		if att_a != att_b:
			same = false
	chk.check(same, "save -> JSON -> load round trip keeps weapons, ammo, attachments and the equipped weapon")
	inv_b.load_save_data({"weapons": {"nonsense": {"in_mag": 5}, "pistol": {"in_mag": 999, "attachments": ["grip", "suppressor"]}}, "ammo": {"pistol": 100000}})
	chk.check(inv_b.get_weapons() == ["fists", "pistol"] and int(inv_b.get_ammo("pistol")["in_mag"]) == 12
			and int(inv_b.get_ammo("pistol")["reserve"]) == 240 and inv_b.get_attachments("pistol") == ["suppressor"],
			"loading sanitises unknown weapons, bad attachments and out-of-range ammo")

	# ---- melee --------------------------------------------------------------------------------
	var owner_m := _make_owner(Vector3(60.0, 0.0, 40.0))
	var brawl := _make_humanoid(Vector3(60.0, 0.0, 38.7))
	var bystander := _make_humanoid(Vector3(60.0, 0.0, 35.5))
	var inv_m := _make_inventory(owner_m)
	await _frames(4)
	var landed: Array = []
	inv_m.melee_landed.connect(func(_id: String, hits: Array) -> void: landed.append(hits.size()))
	var steps: Array = []
	inv_m.melee_started.connect(func(_id: String, _h: bool, step: int) -> void: steps.append(step))
	for i in 3:
		inv_m.melee_attack(false)
		await _frames(int(60.0 / 115.0 * 60.0) + 4)
	var fists := WeaponSpec.resolve("fists")
	var combo_total := fists.damage * 2.0 + fists.damage * 1.4
	chk.check(steps == [1, 2, 3], "three light attacks chain into a combo (%s)" % str(steps))
	chk.check(landed == [1, 1, 1] and _near(brawl.taken, combo_total, 0.1), "fist combo damage 14 + 14 + 19.6 = %.1f (got %.1f)" % [combo_total, brawl.taken])
	chk.check(bystander.taken == 0.0, "melee does not reach a target 4.5 m away")
	chk.check(owner_m.actions.has("punch_r") and owner_m.actions.has("punch_l") and owner_m.actions.has("kick"), "combo asks for punch / kick actions (%s)" % str(owner_m.actions))
	await _frames(50)
	inv_m.give_weapon("bat")
	await _equip_ready(inv_m, "bat")
	brawl.reset()
	inv_m.melee_attack(true)
	await _frames(int(60.0 / 85.0 * 1.7 * 60.0) + 6)
	var bat := WeaponSpec.resolve("bat")
	chk.check(_near(brawl.taken, bat.damage * bat.melee_heavy_mult, 0.1) and brawl.knocked == 1,
			"heavy bat swing = %.1f and knocks the target down (got %.1f, knocked %d)" % [bat.damage * bat.melee_heavy_mult, brawl.taken, brawl.knocked])
	chk.check((brawl.hits.back() as Dictionary).get("type", "") == "melee" and (brawl.hits.back() as Dictionary).get("weapon_id", "") == "bat", "melee damage info carries type and weapon id")
	brawl.reset()
	inv_m.trigger_pressed()
	await _frames(int(60.0 / 85.0 * 60.0) + 6)
	inv_m.trigger_released()
	chk.check(brawl.taken >= bat.damage - 0.1, "trigger with a melee weapon performs a light attack")
	await _frames(60)
	# weapon bash with a firearm in hand
	inv_m.give_weapon("pistol")
	await _equip_ready(inv_m, "pistol")
	brawl.reset()
	inv_m.melee_attack(false)
	await _frames(50)
	chk.check(_near(brawl.taken, 18.0, 0.1), "melee with a firearm in hand is a weapon bash (%.1f)" % brawl.taken)
	# direct sweep API
	brawl.reset()
	var sweep := Combat.melee_sweep(owner_m, owner_m.global_position + Vector3.UP * 1.25, Vector3(0.0, 0.0, -1.0), 2.0, 40.0, {"knockdown": true})
	chk.check(sweep.size() == 1 and _near(brawl.taken, 40.0) and brawl.knocked == 1, "Combat.melee_sweep hits and knocks down")
	brawl.reset()
	sweep = Combat.melee_sweep(owner_m, owner_m.global_position + Vector3.UP * 1.25, Vector3(0.0, 0.0, 1.0), 2.0, 40.0, {})
	chk.check(sweep.is_empty() and brawl.taken == 0.0, "melee sweep misses a target behind the attacker")

	# ---- grenades -----------------------------------------------------------------------------
	var owner_g := _make_owner(Vector3(-60.0, 0.0, 60.0))
	owner_g.aim_target = owner_g.global_position + Vector3(0.0, 1.55, -20.0)
	var inv_g := _make_inventory(owner_g)
	inv_g.give_weapon("grenade", 3)
	chk.check(int(inv_g.get_ammo("grenade")["in_mag"]) == 3, "three grenades in the pool")
	var thrown_nodes: Array = []
	inv_g.thrown.connect(func(_id: String, node: Node3D) -> void: thrown_nodes.append(node))
	_explosions.clear()
	chk.check(inv_g.throw_grenade(), "quick throw starts")
	await _frames(16)
	chk.check(thrown_nodes.size() == 1 and thrown_nodes[0] is Projectile and int(inv_g.get_ammo("grenade")["in_mag"]) == 2,
			"quick throw released a grenade projectile and used one grenade")
	chk.check(Projectile.get_active_count() == 1, "one live projectile")
	await _frames(100)
	var gpos: Vector3 = (thrown_nodes[0] as Node3D).global_position if is_instance_valid(thrown_nodes[0]) else Vector3.ZERO
	chk.check(is_instance_valid(thrown_nodes[0]) and gpos.z < owner_g.global_position.z - 6.0 and gpos.y < 1.5 and gpos.y > -0.2,
			"grenade flew an arc forward and came to rest on the ground (%s)" % str(gpos))
	await _frames(120)
	var gz: float = (_explosions[0]["position"] as Vector3).z - owner_g.global_position.z if not _explosions.is_empty() else 0.0
	chk.check(_explosions.size() == 1 and gz < -8.0 and gz > -55.0 and (_explosions[0]["position"] as Vector3).y < 1.0,
			"grenade exploded on the ground down range when its fuse ran out (%d explosion(s), %.1f m ahead)" % [_explosions.size(), -gz])
	chk.check(not is_instance_valid(thrown_nodes[0]) or (thrown_nodes[0] as Node).is_queued_for_deletion(), "exploded grenade is removed")
	# equipped throwable: hold to cook, release to throw
	await _equip_ready(inv_g, "grenade")
	_explosions.clear()
	inv_g.trigger_pressed()
	await _frames(90)
	chk.check(inv_g.is_cooking(), "holding the trigger cooks the grenade")
	inv_g.trigger_released()
	await _frames(3)
	chk.check(thrown_nodes.size() == 2 and not inv_g.is_cooking(), "releasing throws it")
	await _frames(int((3.2 - 1.5) * 60.0) + 12)
	chk.check(_explosions.size() == 1, "cooked grenade explodes earlier (fuse shortened by the cook time)")
	# explosion damage (only when the real Fx module is present)
	var blast_dummy := _make_humanoid(Vector3(-60.0, 0.0, 90.0))
	await _frames(3)
	_explosions.clear()
	Combat.spawn_projectile("grenade", Vector3(-58.5, 0.3, 90.0), Vector3.ZERO, owner_g, {"fuse": 0.4})
	await _frames(40)
	chk.check(_explosions.size() == 1 and (_explosions[0]["position"] as Vector3).distance_to(Vector3(-58.5, 0.1, 90.0)) < 1.0
			and _explosions[0]["instigator"] == owner_g, "Combat.spawn_projectile grenade explodes in place with the instigator")
	if blast_dummy.taken > 0.0:
		TestHarness.log_line("real Fx present: grenade dealt %.1f damage at 1.5 m" % blast_dummy.taken)
		chk.check(blast_dummy.taken > 60.0, "explosion damage applied through Fx.explosion")
	else:
		TestHarness.log_line("Fx stub active: explosion emitted EventBus.explosion but applied no damage")

	# ---- rocket launcher ------------------------------------------------------------------------
	var owner_r := _make_owner(Vector3(100.0, 0.0, 0.0))
	var wall_r := _make_wall(Vector3(100.0, 3.0, -25.0))
	owner_r.aim_target = Vector3(100.0, 2.0, -25.0)
	var inv_r := _make_inventory(owner_r)
	inv_r.give_weapon("rocket_launcher")
	a = inv_r.get_ammo("rocket_launcher")
	chk.check(int(a["in_mag"]) == 1 and int(a["reserve"]) == 3, "rocket launcher: 1 loaded + 3 spare")
	await _equip_ready(inv_r, "rocket_launcher")
	_explosions.clear()
	var rocket_fired: Array = []
	inv_r.fired.connect(func(_id: String, res: Dictionary) -> void: rocket_fired.append(res))
	inv_r.trigger_pressed()
	inv_r.trigger_released()
	await _frames(3)
	chk.check(rocket_fired.size() == 1 and rocket_fired[0].get("projectile") is Projectile, "rocket launcher fires a rocket projectile")
	chk.check(_explosions.is_empty(), "rocket is still flying after 3 frames")
	await _frames(45)
	chk.check(_explosions.size() == 1 and absf((_explosions[0]["position"] as Vector3).z - (-24.75)) < 0.6
			and absf((_explosions[0]["position"] as Vector3).x - 100.0) < 1.0,
			"rocket exploded on contact with the wall 25 m away (%s)" % (str(_explosions[0]["position"]) if not _explosions.is_empty() else "none"))
	chk.check(_near(float(_explosions[0]["radius"]), 8.5) if not _explosions.is_empty() else false, "rocket blast radius comes from the spec")
	chk.check(inv_r.is_reloading or int(inv_r.get_ammo("rocket_launcher")["in_mag"]) == 1, "launcher reloads itself after the shot")
	if wall_r.taken > 0.0:
		TestHarness.log_line("real Fx present: rocket dealt %.1f damage to the wall" % wall_r.taken)

	# ---- grenade launcher: impact fuse + arming distance ----------------------------------------
	var owner_l := _make_owner(Vector3(140.0, 0.0, 0.0))
	_make_wall(Vector3(140.0, 3.0, -25.0))
	owner_l.aim_target = Vector3(140.0, 3.5, -25.0)
	var inv_l := _make_inventory(owner_l)
	inv_l.give_weapon("grenade_launcher")
	await _equip_ready(inv_l, "grenade_launcher")
	_explosions.clear()
	inv_l.trigger_pressed()
	inv_l.trigger_released()
	await _frames(70)
	chk.check(_explosions.size() == 1 and (_explosions[0]["position"] as Vector3).z < -20.0,
			"launcher grenade explodes on impact down range (%s)" % (str(_explosions[0]["position"]) if not _explosions.is_empty() else "none"))
	_make_wall(Vector3(140.0, 3.0, 2.5))
	await _frames(3)
	owner_l.aim_target = Vector3(140.0, 1.55, 2.5)
	_explosions.clear()
	await _frames(40)
	inv_l.trigger_pressed()
	inv_l.trigger_released()
	await _frames(30)
	chk.check(_explosions.is_empty(), "a launcher grenade that hits before its arming distance does not explode on impact")
	await _frames(130)
	chk.check(_explosions.size() == 1, "... it goes off as a dud after a short fuse")

	# ---- molotov --------------------------------------------------------------------------------
	var burn_dummy := _make_humanoid(Vector3(-100.0, 0.0, 0.0))
	await _frames(3)
	_fires.clear()
	Combat.spawn_projectile("molotov", Vector3(-101.5, 2.0, 0.0), Vector3(0.0, -6.0, 0.0), owner_g, {})
	await _frames(40)
	chk.check(_fires.size() == 1 and (_fires[0] as Vector3).y < 0.3, "fire bottle breaks on impact and starts a fire (EventBus.fire_started)")
	await _frames(100)
	chk.check(Projectile.get_active_count() > 0, "burning pool is alive")
	# the same numbers on both paths: Fx fire handle (real Fx) or the projectile's own ticks (stub)
	chk.check(burn_dummy.taken >= 23.9 and burn_dummy.taken <= 60.1,
			"fire pool burns a body 1.5 m from the impact at ~24 hp/s (%.1f after about 2 s)" % burn_dummy.taken)
	if not burn_dummy.hits.is_empty():
		var burn_hit: Dictionary = burn_dummy.hits[0]
		chk.check(burn_hit.get("type", "") == "fire" and burn_hit.get("instigator") == owner_g and str(burn_hit.get("weapon_id", "")) == "molotov",
				"burn ticks are 'fire' damage blamed on the thrower and the fire bottle")
	Projectile.clear_all()
	await _frames(2)
	chk.check(Projectile.get_active_count() == 0, "Projectile.clear_all removes live projectiles")
	# bounded count
	for i in Projectile.MAX_ACTIVE + 6:
		Combat.spawn_projectile("grenade", Vector3(-140.0 + float(i) * 0.4, 0.3, 40.0), Vector3.ZERO, null, {"fuse": 30.0})
	chk.check(Projectile.get_active_count() <= Projectile.MAX_ACTIVE, "live projectiles are capped at %d (%d)" % [Projectile.MAX_ACTIVE, Projectile.get_active_count()])
	Projectile.clear_all()

	# ---- AI convenience -------------------------------------------------------------------------
	var npc := Node3D.new()
	npc.name = "DummyNpc"
	npc.add_to_group("npc")
	_root.add_child(npc)
	npc.global_position = Vector3(-140.0, 0.0, 0.0)
	var victim := _make_humanoid(Vector3(-140.0, 0.0, -10.0), "player")
	await _frames(3)
	var total := 0.0
	var shots := 0
	for i in 10:
		var nr := Combat.npc_fire(npc, "pistol", victim.global_position + Vector3.UP * 1.2, 1.0)
		if nr["target"] == victim:
			shots += 1
	total = victim.taken
	chk.check(shots >= 8 and _near(total / float(maxi(shots, 1)), 24.0 * Combat.npc_damage_scale, 2.5),
			"npc_fire: accurate NPC hits the player dummy, damage scaled by npc_damage_scale (%d hits, %.1f avg)" % [shots, total / float(maxi(shots, 1))])
	victim.reset()
	var wild := 0
	for i in 30:
		var nr2 := Combat.npc_fire(npc, "pistol", victim.global_position + Vector3.UP * 1.2, 0.0)
		if nr2["target"] == victim:
			wild += 1
	chk.check(wild < 20, "npc_fire: accuracy 0 misses a lot at 10 m (%d / 30 hits)" % wild)
	victim.reset()
	Combat.fire_hitscan(npc.global_position + Vector3.UP * 1.5, Vector3(0.0, 0.16, -10.0), "sniper_rifle", npc, {"spread_deg": 0.0})
	var sn := WeaponSpec.resolve("sniper_rifle")
	chk.check(_near(victim.taken, sn.damage * Combat.PLAYER_HEADSHOT_CAP * Combat.npc_damage_scale, 0.5),
			"head shots against the player are capped (%.1f)" % victim.taken)

	# ---- player-only side effects: HUD signals, hit confirm, gunfire crime ----------------------
	var owner_p := _make_owner(Vector3(180.0, 0.0, 0.0), true)
	var target_p := _make_humanoid(Vector3(180.0, 0.0, -5.0))
	await _frames(3)
	_equipped_events.clear()
	_ammo_events.clear()
	_inventory_events = 0
	var inv_p := _make_inventory(owner_p)
	await _frames(2)
	chk.check(inv_p.has_weapon("pistol") and int(inv_p.get_ammo("pistol")["in_mag"]) + int(inv_p.get_ammo("pistol")["reserve"]) == 48,
			"a holder in group 'player' gets the default loadout (fists + pistol, 48 rounds)")
	chk.check(_inventory_events > 0 and _equipped_events.has("fists"), "player inventory announces itself on EventBus")
	inv_p.give_weapon("smg")
	await _equip_ready(inv_p, "smg")
	chk.check(_equipped_events.back() == "smg", "EventBus.weapon_equipped for the player")
	Combat.reset_rate_limits()
	var reports_before := Combat.gunfire_reports
	_hit_confirms = 0
	_ammo_events.clear()
	_reload_events.clear()
	inv_p.trigger_pressed()
	await _frames(45)
	inv_p.trigger_released()
	chk.check(Combat.gunfire_reports - reports_before == 1, "player gunfire is reported to Wanted once per burst (rate limited): %d" % (Combat.gunfire_reports - reports_before))
	chk.check(_crimes.has("gunfire") or Combat.gunfire_reports > reports_before, "Wanted.report_crime('gunfire') was called")
	chk.check(_hit_confirms >= 5 and target_p.taken > 50.0, "EventBus.hit_confirmed for player hits (%d)" % _hit_confirms)
	chk.check(_ammo_events.size() >= 8 and int((_ammo_events.back() as Array)[1]) < 30, "EventBus.ammo_changed follows the magazine")
	chk.check(Skills.get_level("shooting") > Skills.START_LEVEL or Skills.get_level("shooting") >= 99.0, "hits award shooting XP")
	await _frames(120)
	inv_p.reload()
	chk.check(_reload_events.size() == 1 and float((_reload_events[0] as Array)[1]) < WeaponSpec.resolve("smg").reload_time * 1.09,
			"EventBus.weapon_reload_started for the player, duration scaled by the shooting skill (%s)" % str(_reload_events))
	await _frames(140)
	# suppressed: no crime while nobody is hit, crime once somebody is hit
	inv_p.add_attachment("smg", "suppressor")
	owner_p.aim_target = Vector3(230.0, 30.0, -5.0)
	Combat.reset_rate_limits()
	reports_before = Combat.gunfire_reports
	inv_p.trigger_pressed()
	await _frames(20)
	inv_p.trigger_released()
	chk.check(Combat.gunfire_reports == reports_before, "suppressed shots into the air are not reported")
	owner_p.aim_target = Vector3(180.0, 1.2, -5.0)
	await _frames(30)
	inv_p.trigger_pressed()
	await _frames(20)
	inv_p.trigger_released()
	chk.check(Combat.gunfire_reports == reports_before + 1, "a suppressed shot that hits somebody is reported")

	await _review_checks()
	_print_balance_table()


# --- review additions: kill attribution, NPC marksmen, dead holders, tap buffer -------------------

func _review_checks() -> void:
	var chk := TestHarness

	# ---- "killed" is reported exactly once: by the hit that did it ------------------------------
	var shooter := _make_owner(Vector3(0.0, 0.0, 150.0), true)
	var mortal := _make_humanoid(Vector3(0.0, 0.0, 145.0))
	mortal.dies_at = 100.0
	await _frames(3)
	var kill_flags: Array = []
	var on_hit := func(_t: Node, info: Dictionary) -> void: kill_flags.append(bool(info.get("killed", false)))
	EventBus.hit_confirmed.connect(on_hit)
	var k_eye := Vector3(0.0, 1.5, 150.0)
	var k_dir := Vector3(0.0, 1.2, 145.0) - k_eye
	var k_opts := {"spread_deg": 0.0, "no_crime": true, "no_noise": true}
	var r1 := Combat.fire_hitscan(k_eye, k_dir, "heavy_pistol", shooter, k_opts)      # 48
	var r2 := Combat.fire_hitscan(k_eye, k_dir, "heavy_pistol", shooter, k_opts)      # 96
	var r3 := Combat.fire_hitscan(k_eye, k_dir, "heavy_pistol", shooter, k_opts)      # 144: dead
	var xp_before := Skills.get_level("shooting")
	var r4 := Combat.fire_hitscan(k_eye, k_dir, "heavy_pistol", shooter, k_opts)      # into the corpse
	chk.check(not bool(r1["killed"]) and not bool(r2["killed"]) and bool(r3["killed"]) and mortal.is_dead,
			"the third heavy-pistol round kills the 100 hp dummy and reports killed")
	chk.check(bool(r4["hit"]) and r4["target"] == mortal and not bool(r4["killed"]),
			"a round into the corpse still hits but is not another kill")
	chk.check(kill_flags == [false, false, true, false], "hit_confirmed carries killed only for the lethal hit (%s)" % str(kill_flags))
	chk.check(is_equal_approx(Skills.get_level("shooting"), xp_before), "shooting a corpse awards no shooting XP")
	var mortal_m := _make_humanoid(Vector3(30.0, 0.0, 148.8))
	mortal_m.dies_at = 30.0
	var brawler := _make_owner(Vector3(30.0, 0.0, 150.0), true)
	await _frames(3)
	kill_flags.clear()
	var m_origin := brawler.global_position + Vector3.UP * 1.25
	var s1 := Combat.melee_sweep(brawler, m_origin, Vector3(0.0, 0.0, -1.0), 2.0, 40.0, {"knockdown": true, "no_fx": true})
	var s2 := Combat.melee_sweep(brawler, m_origin, Vector3(0.0, 0.0, -1.0), 2.0, 40.0, {"knockdown": true, "no_fx": true})
	chk.check(s1.size() == 1 and bool(s1[0]["killed"]) and s2.size() == 1 and not bool(s2[0]["killed"]) and kill_flags == [true, false],
			"melee: the lethal blow is the kill, hitting the body again is not (%s)" % str(kill_flags))
	chk.check(mortal_m.knocked == 0, "a target that died from the blow is not knocked down as well")
	EventBus.hit_confirmed.disconnect(on_hit)

	# ---- NPC marksman: a scoped rifle in NPC hands is driven by `accuracy`, not by the hip cone ---
	var marksman := Node3D.new()
	marksman.name = "DummyMarksman"
	marksman.add_to_group("npc")
	_root.add_child(marksman)
	marksman.global_position = Vector3(-180.0, 0.0, 190.0)
	var far_target := _make_humanoid(Vector3(-180.0, 0.0, 150.0))
	await _frames(3)
	var sniper_hits := 0
	for i in 10:
		var sr := Combat.npc_fire(marksman, "sniper_rifle", far_target.global_position + Vector3.UP * 1.2, 1.0)
		if sr["target"] == far_target:
			sniper_hits += 1
	chk.check(sniper_hits >= 9, "npc_fire with a sniper rifle at accuracy 1.0 hits a target 40 m away (%d / 10)" % sniper_hits)
	far_target.reset()
	var sloppy := 0
	for i in 20:
		var sr2 := Combat.npc_fire(marksman, "sniper_rifle", far_target.global_position + Vector3.UP * 1.2, 0.0)
		if sr2["target"] == far_target:
			sloppy += 1
	chk.check(sloppy < 10, "... and misses most shots at accuracy 0 (%d / 20)" % sloppy)

	# ---- a dead holder does nothing -------------------------------------------------------------
	var owner_d := _make_owner(Vector3(120.0, 0.0, 150.0))
	owner_d.aim_target = Vector3(120.0, 1.2, 100.0)
	var inv_d := _make_inventory(owner_d)
	inv_d.give_weapon("smg")
	inv_d.give_weapon("grenade", 2)
	await _equip_ready(inv_d, "smg")
	var before := _fired_count
	inv_d.trigger_pressed()
	await _frames(12)
	chk.check(_fired_count - before >= 2, "holder alive: automatic fire runs (%d shots)" % (_fired_count - before))
	owner_d.is_dead = true
	before = _fired_count
	await _frames(20)
	chk.check(_fired_count == before and not inv_d.trigger_held, "the holder died with the trigger held: fire stops at once")
	inv_d.trigger_pressed()
	inv_d.trigger_released()
	chk.check(_fired_count == before and not inv_d.melee_attack(false) and not inv_d.throw_grenade(),
			"a dead holder cannot fire, swing or throw")
	owner_d.is_dead = false
	await _frames(10)
	inv_d.trigger_pressed()
	inv_d.trigger_released()
	await _frames(6)
	chk.check(_fired_count == before + 1, "alive again: the weapon works")
	# dying with a cooked grenade in the hand drops it at the feet, fuse still running
	await _equip_ready(inv_d, "grenade")
	var dropped: Array = []
	inv_d.thrown.connect(func(_id: String, node: Node3D) -> void: dropped.append(node))
	_explosions.clear()
	inv_d.trigger_pressed()
	await _frames(30)
	chk.check(inv_d.is_cooking(), "cooking a grenade")
	owner_d.is_dead = true
	await _frames(3)
	chk.check(dropped.size() == 1 and not inv_d.is_cooking() and inv_d.get_reserve("grenade") == 1,
			"the dying holder drops the live grenade (%d dropped, %d left)" % [dropped.size(), inv_d.get_reserve("grenade")])
	await _frames(50)
	if not dropped.is_empty() and is_instance_valid(dropped[0]):
		var flat := (dropped[0] as Node3D).global_position - owner_d.global_position
		flat.y = 0.0
		chk.check(flat.length() < 3.5, "it lands at the holder's feet (%.1f m away)" % flat.length())
	await _frames(130)
	chk.check(_explosions.size() == 1 and (_explosions[0]["position"] as Vector3).distance_to(owner_d.global_position) < 6.0,
			"... and goes off there when the remaining fuse runs out (%d explosion(s))" % _explosions.size())
	owner_d.is_dead = false

	# ---- semi-auto tap buffer -------------------------------------------------------------------
	var owner_t := _make_owner(Vector3(-120.0, 0.0, 150.0))
	owner_t.aim_target = Vector3(-120.0, 1.2, 100.0)
	var inv_t := _make_inventory(owner_t)
	inv_t.give_weapon("pump_shotgun")
	await _equip_ready(inv_t, "pump_shotgun")
	before = _fired_count
	inv_t.trigger_pressed()
	inv_t.trigger_released()
	await _frames(51)                       # 0.85 s into the 0.94 s pump cycle
	inv_t.trigger_pressed()
	inv_t.trigger_released()                # a quick tap, a moment too early
	chk.check(_fired_count == before + 1, "pump shotgun is still cycling 0.85 s after the shot")
	await _frames(12)
	chk.check(_fired_count == before + 2, "a quick tap just before the weapon is ready still fires (shot buffer survives the release)")
	await _frames(20)
	inv_t.trigger_pressed()
	inv_t.trigger_released()                # half a second too early: not kept
	await _frames(45)
	chk.check(_fired_count == before + 2, "a tap that comes far too early is dropped (%d shots)" % (_fired_count - before))
	inv_t.give_weapon("smg")
	inv_t.equip("smg")
	inv_t.trigger_pressed()                 # pulled during the draw: lands in the buffer
	await _frames(40)
	inv_t.trigger_released()
	var after_release := _fired_count
	await _frames(15)
	chk.check(after_release > before + 2 and _fired_count == after_release,
			"automatic fire that started from a buffered pull leaves no stray shot after the release")


func _print_balance_table() -> void:
	print("BALANCE| id | name | slot | mode | damage | rpm | mag | reload s | DPS | sustained DPS | shots to kill | TTK 100 hp (s) | range m (falloff) | head x | noise m | price |")
	for id in ALL_IDS:
		var s := WeaponSpec.resolve(id)
		if s == null:
			continue
		var dmg_text := "%.0f" % s.damage if s.pellets == 1 else "%.1f x %d" % [s.damage, s.pellets]
		if s.is_melee():
			print("BALANCE| %s | %s | %s | melee | %s (heavy x%.1f) | %.0f | - | - | %.0f | %.0f | %d | %.2f | %.1f | - | %.0f | %d |" % [
				s.id, s.display_name, s.slot, dmg_text, s.melee_heavy_mult, s.rpm, s.get_dps(), s.get_dps(),
				s.get_shots_to_kill(), s.get_time_to_kill(), s.melee_range, s.noise_radius, s.price])
		elif s.projectile_kind != "":
			print("BALANCE| %s | %s | %s | %s | %s blast, r %.1f m | %.0f | %s | %s | - | - | 1 (in blast) | - | %.0f m/s | - | %.0f | %d |" % [
				s.id, s.display_name, s.slot, s.fire_mode, dmg_text, s.blast_radius, s.rpm,
				str(s.mag_size) if s.mag_size > 0 else "-", ("%.1f" % s.reload_time) if s.mag_size > 0 else "-",
				s.projectile_speed, s.noise_radius, s.price])
		else:
			print("BALANCE| %s | %s | %s | %s | %s | %.0f | %d | %.2f | %.0f | %.0f | %d | %.2f | %.0f (%.0f-%.0f, x%.2f) | %.2f | %.0f | %d |" % [
				s.id, s.display_name, s.slot, s.fire_mode, dmg_text, s.rpm, s.mag_size, s.reload_time, s.get_dps(),
				s.get_sustained_dps(), s.get_shots_to_kill(), s.get_time_to_kill(), s.max_range, s.falloff_start,
				s.falloff_end, s.falloff_min, s.headshot_mult, s.noise_radius, s.price])
