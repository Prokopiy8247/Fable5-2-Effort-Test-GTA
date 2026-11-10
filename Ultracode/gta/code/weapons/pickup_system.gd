class_name PickupSystem
extends Node3D
## World system "pickups": creates, animates, collects and respawns every Pickup.
##
##   var ps := Game.get_system("pickups")
##   ps.spawn_pickup("weapon", "smg", 60, position)        # one-shot (dropped) pickup
##   ps.spawn_pickup("cash", "", 250, position)
##   ps.spawn_world_pickup("health", "", 50, position, 90.0)   # respawns after 90 s
##   ps.drop_from_npc(npc)                                  # cash + sometimes the NPC's weapon
##
## Kinds: weapon (id = weapon id, amount = rounds, <= 0 = spec default), ammo (id = ammo type or
## weapon id, amount = rounds), health / armor (amount = points), cash (amount = dollars),
## parachute, scuba. `position` is the ground point; dropped pickups snap to the ground.
##
## World pickups are placed in setup() at Game.world.get_spawn_points("pickup_weapon" /
## "pickup_health" / "pickup_armor" / "pickup_cash" / "parachute") and respawn on timers.
## A kind for which the world offers no spawn point falls back to a few named locations
## (FALLBACK_LOCATIONS), so the island never ends up without pickups.
## NPC deaths (EventBus.npc_died) drop loot automatically; drop_from_npc() is idempotent per NPC.
## Feedback: Audio "pickup_*", Fx.pickup_sparkle, UI.notify.  See docs/WEAPONS.md.

signal pickup_collected(pickup: Node3D, collector: Node)

const MAX_DROPPED := 40
const DROP_LIFETIME := 150.0
const ANIM_RANGE := 80.0
const RETRY_INTERVAL := 0.3
## Weapons handed out round-robin over the world's "pickup_weapon" points.
const WORLD_WEAPONS: Array[String] = ["pistol", "bat", "smg", "pump_shotgun", "knife", "assault_rifle",
		"grenade", "heavy_pistol", "carbine", "molotov", "crowbar", "marksman_rifle", "auto_shotgun",
		"sniper_rifle", "grenade_launcher", "rocket_launcher"]
const RESPAWN := {"weapon": 180.0, "health": 90.0, "armor": 150.0, "cash": 240.0, "parachute": 45.0, "scuba": 60.0}
## Named locations that get a scuba set (there is no dedicated spawn-point kind for it).
const SCUBA_LOCATIONS: Array[String] = ["marina_dock", "beach"]
## Used per spawn-point kind ONLY when the world returns no points of that kind: named locations
## (docs/ARCHITECTURE.md 6.1) and an offset in the location's own frame (x right, -z facing).
const FALLBACK_LOCATIONS := {
	"pickup_weapon": ["industrial_yard", "marina_dock", "hill_viewpoint", "airport_hangar", "parking_garage",
			"lighthouse", "residential_park", "stunt_ramp_1"],
	"pickup_health": ["hospital", "beach", "residential_park", "gas_station", "hill_viewpoint"],
	"pickup_armor": ["police_station", "industrial_yard", "airport_hangar"],
	"pickup_cash": ["downtown_plaza", "marina_dock", "beach", "lighthouse", "parking_garage", "taxi_stand"],
	"parachute": ["hill_top", "rooftop_helipad", "airport_helipad", "lighthouse"],
}
const FALLBACK_OFFSETS := {
	"pickup_weapon": Vector3(3.0, 0.0, 2.5), "pickup_health": Vector3(-3.0, 0.0, 2.5),
	"pickup_armor": Vector3(3.0, 0.0, 4.5), "pickup_cash": Vector3(-2.0, 0.0, 4.5),
	"parachute": Vector3(0.0, 0.0, 3.0),
}

var enabled: bool = true
var world_pickups_placed: int = 0
var fallback_points_used: int = 0   ## world pickups that had to use FALLBACK_LOCATIONS

var _pickups: Array = []            ## every live Pickup (world + dropped)
var _dropped: Array = []            ## dropped ones, oldest first
var _touching: Dictionary = {}      ## pickup instance id -> Pickup (touched but not collectable yet)
var _expired: Array = []            ## scratch list of _process (dropped pickups whose lifetime ran out)
var _time: float = 0.0
var _retry_t: float = 0.0


func setup() -> void:
	if not EventBus.npc_died.is_connected(_on_npc_died):
		EventBus.npc_died.connect(_on_npc_died)
	_place_world_pickups()


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	for item: Variant in _pickups:
		if is_instance_valid(item):
			(item as Pickup).set_deferred("monitoring", on and (item as Pickup).available)


# --- public API ---------------------------------------------------------------------------------

## One-shot pickup (disappears when collected, or after DROP_LIFETIME seconds).
## opts: {"lifetime": float (0 = never expires), "snap": bool (default true)}
func spawn_pickup(kind: String, id: String, amount: int, at: Vector3, opts: Dictionary = {}) -> Node3D:
	var p := _create(kind, id, amount, _snap_to_ground(at) if bool(opts.get("snap", true)) else at)
	if p == null:
		return null
	p.dropped = true
	p.lifetime = float(opts.get("lifetime", DROP_LIFETIME))
	_dropped.append(p)
	while _dropped.size() > MAX_DROPPED:
		_remove(_dropped[0])
	return p


## Permanent pickup that respawns `respawn_time` seconds after it was collected.
func spawn_world_pickup(kind: String, id: String, amount: int, at: Vector3, respawn_time: float = -1.0) -> Node3D:
	var p := _create(kind, id, amount, at)
	if p == null:
		return null
	p.respawn_time = respawn_time if respawn_time > 0.0 else float(RESPAWN.get(kind, 120.0))
	return p


## Loot of a dead NPC: cash by faction and, sometimes, the weapon it carried (with a little ammo).
## Safe to call more than once per NPC. Returns the created pickups.
func drop_from_npc(npc: Node) -> Array:
	var out: Array = []
	if npc == null or not is_instance_valid(npc) or not (npc is Node3D) or not enabled:
		return out
	if npc.has_meta("pickup_drops_done") or npc.is_in_group("animal"):
		return out
	npc.set_meta("pickup_drops_done", true)
	var rng := Game.rng
	var pos := (npc as Node3D).global_position
	var faction := ""
	var f: Variant = npc.get("faction")
	if f is String or f is StringName:
		faction = str(f)
	var cash := 0
	var carried: Variant = npc.get("cash_carried")
	if carried is int or carried is float:
		cash = int(carried)
	else:
		match faction:
			"gang": cash = rng.randi_range(60, 260)
			"police": cash = rng.randi_range(20, 90)
			"medic", "fire", "staff": cash = rng.randi_range(15, 70)
			_: cash = rng.randi_range(12, 140) if rng.randf() < 0.75 else 0
	if cash > 0:
		var c := spawn_pickup("cash", "", cash, pos + _scatter(rng, 0.5))
		if c != null:
			out.append(c)
	var w: Variant = npc.get("weapon_id")
	if (w is String or w is StringName) and str(w) != "" and str(w) != "fists":
		var spec := WeaponSpec.resolve(str(w))
		if spec != null and rng.randf() < 0.65:
			var rounds := -1
			if spec.uses_magazine():
				rounds = rng.randi_range(maxi(spec.mag_size / 2, 1), spec.mag_size * 2)
			elif spec.is_thrown():
				rounds = 1
			var wp := spawn_pickup("weapon", spec.id, rounds, pos + _scatter(rng, 0.7))
			if wp != null:
				out.append(wp)
	return out


## Try to give `pickup` to `collector` (the player). Returns true when it was consumed.
func collect(pickup: Node3D, collector: Node) -> bool:
	var p := pickup as Pickup
	if p == null or not is_instance_valid(p) or not p.available or not enabled:
		return false
	if collector == null or not is_instance_valid(collector):
		return false
	var text := ""
	var note_kind := "good"
	var sound := "pickup_weapon"
	var inv := _inventory_of(collector)
	match p.kind:
		"weapon":
			var spec := WeaponSpec.resolve(p.item_id)
			if inv == null or spec == null:
				return false
			if inv.call("has_weapon", spec.id):
				if not spec.uses_ammo() or bool(inv.call("is_ammo_full", spec.ammo_type)):
					return false
				var rounds := p.amount if p.amount > 0 else (spec.mag_size if spec.uses_magazine() else 1)
				var added := int(inv.call("add_ammo", spec.ammo_type, rounds))
				text = "+%d %s" % [added, str(WeaponSpec.AMMO_NAMES.get(spec.ammo_type, "ammo"))]
			else:
				inv.call("give_weapon", spec.id, p.amount if p.amount > 0 else -1)
				text = spec.display_name
				# draw it when the hands are empty (never forces a switch away from a drawn weapon)
				if not bool(inv.call("is_armed")) and collector.get("current_vehicle") == null and not spec.is_thrown():
					inv.call("equip", spec.id)
		"ammo":
			if inv == null:
				return false
			var type := p.item_id
			if not WeaponSpec.AMMO_MAX.has(type):
				var wspec := WeaponSpec.resolve(type)
				if wspec == null or not wspec.uses_ammo():
					return false
				type = wspec.ammo_type
			if bool(inv.call("is_ammo_full", type)):
				return false
			var added := int(inv.call("add_ammo", type, maxi(p.amount, 1)))
			text = "+%d %s" % [added, str(WeaponSpec.AMMO_NAMES.get(type, "ammo"))]
		"health":
			if not collector.has_method("heal") or _stat_full(collector, "health", "max_health"):
				return false
			collector.call("heal", float(maxi(p.amount, 1)))
			text = "Health +%d" % maxi(p.amount, 1)
			sound = "pickup_health"
		"armor":
			if not collector.has_method("add_armor") or _stat_full(collector, "armor", "max_armor"):
				return false
			collector.call("add_armor", float(maxi(p.amount, 1)))
			text = "Armor +%d" % maxi(p.amount, 1)
			sound = "pickup_health"
		"cash":
			Game.add_money(maxi(p.amount, 0))
			text = "+$%d" % maxi(p.amount, 0)
			note_kind = "money"
			sound = "pickup_cash"
		"parachute":
			if collector.get("has_parachute") == true:
				return false
			if collector.has_method("give_parachute"):
				collector.call("give_parachute")
			else:
				collector.set("has_parachute", true)
			text = "Parachute"
		"scuba":
			if _has_scuba(collector):
				return false
			if collector.has_method("give_scuba"):
				collector.call("give_scuba")
			elif "has_scuba" in collector:
				collector.set("has_scuba", true)
			else:
				collector.set_meta("has_scuba", true)
			Game.flags["scuba_gear"] = true
			text = "Scuba gear"
		_:
			return false
	var at := p.get_item_position()
	Audio.play(sound, -2.0, 1.0, "SFX")
	Fx.pickup_sparkle(at, p.get_color())
	if text != "":
		UI.notify(text, note_kind)
	pickup_collected.emit(p, collector)
	_touching.erase(p.get_instance_id())
	if p.respawn_time > 0.0:
		p.set_available(false)
		p.respawn_left = p.respawn_time
	else:
		_remove(p)
	return true


func get_pickups() -> Array:
	_prune()
	return _pickups.duplicate()


func get_pickup_count() -> int:
	_prune()
	return _pickups.size()


## Remove every dropped (non-respawning) pickup.
func clear_dropped() -> void:
	for p: Variant in _dropped.duplicate():
		_remove(p)


## Remove every pickup, world pickups included (call setup() again to place those anew).
func clear_all() -> void:
	for p: Variant in _pickups.duplicate():
		_remove(p)
	world_pickups_placed = 0
	fallback_points_used = 0


## Number of permanent (respawning) pickups, collected ones included.
func get_world_pickup_count() -> int:
	var n := 0
	for item: Variant in _pickups:
		if is_instance_valid(item) and (item as Pickup).respawn_time > 0.0:
			n += 1
	return n


## Make every collected world pickup available again right now (admin helper).
func respawn_all() -> void:
	for item: Variant in _pickups:
		if is_instance_valid(item) and not (item as Pickup).available:
			(item as Pickup).respawn_left = 0.0
			(item as Pickup).set_available(true)


# --- frame update (one loop for all pickups) ----------------------------------------------------

func _process(delta: float) -> void:
	if not enabled:
		return
	_time += delta
	var ref := Vector3.INF
	if Game.has_player():
		ref = Game.get_player_position()
	else:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			ref = cam.global_position
	var range_sq := ANIM_RANGE * ANIM_RANGE
	var expired := _expired             # reused: no per-frame allocation
	expired.clear()
	var stale := false
	for item: Variant in _pickups:
		# a pickup that somebody else freed (scene clean-up) must not break the loop
		if not is_instance_valid(item):
			stale = true
			continue
		var p := item as Pickup
		if not p.available:
			p.respawn_left -= delta
			if p.respawn_left <= 0.0:
				p.set_available(true)
			continue
		if p.lifetime > 0.0:
			p.age += delta
			if p.age >= p.lifetime:
				expired.append(p)
				continue
		if ref == Vector3.INF or p.global_position.distance_squared_to(ref) < range_sq:
			p.visual.rotation.y = _time * 1.5 + p.phase
			p.visual.position.y = Pickup.HOVER + sin(_time * 2.2 + p.phase) * 0.07
	if not expired.is_empty():
		for old: Pickup in expired:
			_remove(old)
		expired.clear()
	if stale:
		_prune()
	# pickups the player stands in but could not take yet (full health, full ammo ...)
	if not _touching.is_empty():
		_retry_t -= delta
		if _retry_t <= 0.0:
			_retry_t = RETRY_INTERVAL
			for key: int in _touching.keys():
				var touched: Variant = _touching[key]
				if not is_instance_valid(touched) or not (touched as Pickup).available:
					_touching.erase(key)
					continue
				var collector := _collector_in(touched as Pickup)
				if collector == null:
					_touching.erase(key)
				else:
					collect(touched as Pickup, collector)


# --- internals ----------------------------------------------------------------------------------

func _create(kind: String, id: String, amount: int, at: Vector3) -> Pickup:
	if not Pickup.KINDS.has(kind):
		push_warning("PickupSystem: unknown pickup kind '%s'" % kind)
		return null
	if kind == "weapon" and WeaponSpec.resolve(id) == null:
		push_warning("PickupSystem: unknown weapon '%s'" % id)
		return null
	var p := Pickup.new()
	p.configure(kind, id, amount)
	add_child(p)
	p.global_position = at
	p.body_entered.connect(_on_body_entered.bind(p))
	if not enabled:
		p.set_deferred("monitoring", false)
	_pickups.append(p)
	return p


func _remove(pickup: Variant) -> void:
	_pickups.erase(pickup)
	_dropped.erase(pickup)
	if pickup != null and is_instance_valid(pickup):
		_touching.erase((pickup as Node).get_instance_id())
		(pickup as Node).queue_free()


## Forget entries whose node was freed behind the system's back.
func _prune() -> void:
	for i in range(_pickups.size() - 1, -1, -1):
		if not is_instance_valid(_pickups[i]):
			_pickups.remove_at(i)
	for i in range(_dropped.size() - 1, -1, -1):
		if not is_instance_valid(_dropped[i]):
			_dropped.remove_at(i)


func _on_body_entered(body: Node, pickup: Pickup) -> void:
	if not is_instance_valid(pickup) or not pickup.available:
		return
	var collector := _collector_from(body)
	if collector == null:
		return
	if not collect(pickup, collector):
		_touching[pickup.get_instance_id()] = pickup


## The player behind a touching body: the player itself or the vehicle the player drives.
func _collector_from(body: Node) -> Node:
	if body == null or not is_instance_valid(body):
		return null
	if body.is_in_group("player"):
		return body
	if body.is_in_group("vehicle") and body.get("is_player_driven") == true and Game.has_player():
		return Game.player
	return null


func _collector_in(pickup: Pickup) -> Node:
	for body in pickup.get_overlapping_bodies():
		var c := _collector_from(body)
		if c != null:
			return c
	return null


func _inventory_of(collector: Node) -> Node:
	var inv: Variant = collector.get("inventory")
	if inv != null and is_instance_valid(inv) and inv is Node and (inv as Node).has_method("give_weapon"):
		return inv as Node
	var child := collector.get_node_or_null("Inventory")
	if child != null and child.has_method("give_weapon"):
		return child
	return null


func _stat_full(collector: Node, stat: String, max_stat: String) -> bool:
	var v: Variant = collector.get(stat)
	var m: Variant = collector.get(max_stat)
	if (v is float or v is int) and (m is float or m is int):
		return float(v) >= float(m) - 0.01
	return false


func _has_scuba(collector: Node) -> bool:
	if collector.get("has_scuba") == true:
		return true
	return collector.has_meta("has_scuba") and bool(collector.get_meta("has_scuba"))


func _scatter(rng: RandomNumberGenerator, r: float) -> Vector3:
	var a := rng.randf() * TAU
	var d := rng.randf_range(0.25, 1.0) * r
	return Vector3(cos(a) * d, 0.0, sin(a) * d)


## Ground point under `position` (ray on the world; falls back to the terrain height).
func _snap_to_ground(at: Vector3) -> Vector3:
	var hit := Combat.raycast(at + Vector3.UP * 1.2, at + Vector3.DOWN * 6.0, Layers.WORLD)
	if not hit.is_empty():
		return hit["position"]
	if Game.world != null and Game.world.has_method("get_height"):
		var h := float(Game.world.call("get_height", at.x, at.z))
		if at.y < h or at.y - h < 3.0:
			return Vector3(at.x, maxf(h, Game.WATER_LEVEL), at.z)
	return at


func _on_npc_died(npc: Node3D, _killer: Node, _info: Dictionary) -> void:
	drop_from_npc(npc)


func _place_world_pickups() -> void:
	var world := Game.world
	if world == null or not is_instance_valid(world) or not world.has_method("get_spawn_points"):
		return
	var count := 0
	var index := 0
	for xf: Variant in _points(world, "pickup_weapon"):
		var id: String = WORLD_WEAPONS[index % WORLD_WEAPONS.size()]
		index += 1
		if WeaponSpec.resolve(id) != null and spawn_world_pickup("weapon", id, -1, _ground((xf as Transform3D).origin)) != null:
			count += 1
	for xf: Variant in _points(world, "pickup_health"):
		if spawn_world_pickup("health", "", 50, _ground((xf as Transform3D).origin)) != null:
			count += 1
	for xf: Variant in _points(world, "pickup_armor"):
		if spawn_world_pickup("armor", "", 50, _ground((xf as Transform3D).origin)) != null:
			count += 1
	index = 0
	for xf: Variant in _points(world, "pickup_cash"):
		if spawn_world_pickup("cash", "", 120 + (index * 137) % 480, _ground((xf as Transform3D).origin)) != null:
			count += 1
		index += 1
	for xf: Variant in _points(world, "parachute"):
		if spawn_world_pickup("parachute", "", 1, _ground((xf as Transform3D).origin)) != null:
			count += 1
	if world.has_method("get_locations"):
		var locations: Variant = world.call("get_locations")
		if locations is Dictionary:
			for loc_name in SCUBA_LOCATIONS:
				if (locations as Dictionary).has(loc_name) and (locations as Dictionary)[loc_name] is Transform3D:
					var xf: Transform3D = (locations as Dictionary)[loc_name]
					if spawn_world_pickup("scuba", "", 1, _ground(xf.origin + xf.basis * Vector3(2.5, 0.0, 1.5))) != null:
						count += 1
	world_pickups_placed = count
	print("[Pickups] placed %d world pickups" % count)


func _points(world: Node, kind: String) -> Array:
	var out: Array = []
	var pts: Variant = world.call("get_spawn_points", kind)
	if pts is Array:
		for p: Variant in pts:
			if p is Transform3D:
				out.append(p)
	if out.is_empty():
		out = _fallback_points(world, kind)
	return out


## Named-location stand-ins for a spawn-point kind the world does not provide.
func _fallback_points(world: Node, kind: String) -> Array:
	var out: Array = []
	if not FALLBACK_LOCATIONS.has(kind) or not world.has_method("get_locations"):
		return out
	var locations: Variant = world.call("get_locations")
	if not (locations is Dictionary):
		return out
	var offset: Vector3 = FALLBACK_OFFSETS.get(kind, Vector3.ZERO)
	for loc_name: String in FALLBACK_LOCATIONS[kind]:
		var xf: Variant = (locations as Dictionary).get(loc_name, null)
		if not (xf is Transform3D):
			continue
		var at: Vector3 = (xf as Transform3D).origin + (xf as Transform3D).basis.orthonormalized() * offset
		if world.has_method("get_height"):
			at.y = float(world.call("get_height", at.x, at.z))
		if at.y < Game.WATER_LEVEL + 0.2:
			continue                    # never under water
		out.append(Transform3D(Basis.IDENTITY, at))
	if not out.is_empty():
		fallback_points_used += out.size()
		print("[Pickups] world has no '%s' spawn points: using %d named-location fallbacks" % [kind, out.size()])
	return out


## World spawn points are trusted, but never left below the terrain.
func _ground(at: Vector3) -> Vector3:
	if Game.world != null and Game.world.has_method("get_height"):
		var h := float(Game.world.call("get_height", at.x, at.z))
		if at.y < h:
			return Vector3(at.x, h, at.z)
	return at
