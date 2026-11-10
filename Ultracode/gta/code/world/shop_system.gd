extends Node3D
## World system "shops" (ECONOMY, economy programmer A) - ARCHITECTURE_WAVE2 W2.6.
##
## For every Registry "shops" definition that has a "uses" list (shops_registry.gd):
##   * finds the landmark markers through the city system (W2.4 get_landmark_marker), falling back
##     to Game.get_location(landmark) when the city has no such landmark (re-checked for 30 s, so a
##     city that finishes late still moves everything onto the real counters);
##   * creates one Interactable per use point (counter, workbench, changing booth, barber chair)
##     that opens the shop screen with {"shop_id": id, ...};
##   * spawns the persistent staff NPC (archetype "shop_staff") at the `Staff` marker when the peds
##     system exists - only while the player is within STAFF_SPAWN_DIST (freed beyond
##     STAFF_DESPAWN_DIST), so idle shops cost nothing;
##   * runs the robbery hook: aiming a firearm at the clerk from <= ROB_RANGE for ROB_SECONDS makes
##     them surrender, then hand over a cash pickup; Wanted.report_crime("robbery") is called and the
##     shop closes for `closed_hours` in-game hours (also when the clerk is killed);
##   * exposes get_shop_locations() for map legends.
## Also owns the wardrobe store (SaveSystem provider "wardrobe") and the workbench unlocks
## (provider "shops"), and a wardrobe use point at the safehouse (removed again when another module
## already put an Interactable on that spot).
## Purchases themselves live in res://gta/code/world/shops/shop_catalog.gd (used by the screens).
## One manager, two low-rate loops (10 Hz robbery check near shops, 2 Hz staff / reopen tier); no
## per-shop scripts.

signal shop_robbed(shop_id: String, cash: int)
signal shop_closed(shop_id: String, reason: String)
signal shop_reopened(shop_id: String)

const Catalog := preload("res://gta/code/world/shops/shop_catalog.gd")
const WardrobeStore := preload("res://gta/code/world/shops/shop_wardrobe.gd")

const USE_RADIUS := 1.9                ## Interactable reach (sphere, centred USE_HEIGHT above the marker)
const USE_HEIGHT := 0.9
const USE_PRIORITY := 2
const STAFF_ARCHETYPE := "shop_staff"
const STAFF_SPAWN_DIST := 90.0
const STAFF_DESPAWN_DIST := 130.0
const STAFF_MAX_FAILS := 4
const ROB_RANGE := 10.0                ## metres between the player and the clerk
const ROB_SECONDS := 3.0               ## aiming time needed
const ROB_DECAY := 0.75                ## threat lost per second while not aiming
const ROB_TICK := 0.1
const SLOW_TICK := 0.5
const RESOLVE_WINDOW := 30.0           ## seconds after boot in which positions are re-resolved
const FALLBACK_USE_SPACING := 2.2
const DEDUPE_RADIUS := 1.0
## Wardrobe use points that are not shops (the safehouse wardrobe).
const WARDROBE_POINTS := [
	{"id": "safehouse_wardrobe", "landmark": "safehouse", "marker": "Use_Wardrobe", "prompt": "Open wardrobe",
		"fallback_offset": 1.6},
]

var wardrobe: RefCounted = WardrobeStore.new()     ## owned clothing (provider "wardrobe")
var enabled: bool = true
var unlocked_attachments: Dictionary = {}         ## weapon id -> {attachment id: true}
var debug_force_threat: Dictionary = {}           ## shop id -> true: robbery check passes (tests)
var robbery_count: int = 0

var _states: Array[Dictionary] = []
var _by_id: Dictionary = {}
var _wardrobe_points: Array[Dictionary] = []
var _rob_timer: float = 0.0
var _slow_timer: float = 0.0
var _resolve_timer: float = 0.0
var _age: float = 0.0
var _set_up: bool = false


func setup() -> void:
	if _set_up:
		return
	_set_up = true
	SaveSystem.register_provider("wardrobe", wardrobe)
	SaveSystem.register_provider("shops", self)
	if not EventBus.npc_died.is_connected(_on_npc_died):
		EventBus.npc_died.connect(_on_npc_died)
	if not EventBus.game_ready.is_connected(_on_game_ready):
		EventBus.game_ready.connect(_on_game_ready, CONNECT_ONE_SHOT)
	_build_states()
	_build_wardrobe_points()
	_resolve_all()
	var managed := 0
	for st: Dictionary in _states:
		if st["managed"]:
			managed += 1
	print("[Shops] %d shops (%d managed), %d use points, source: %s" % [_states.size(), managed,
			get_interactables().size(), _sources_text()])


func _ready() -> void:
	# Also works when instanced outside the boot manifest (isolated test scenes).
	if not _set_up:
		call_deferred("setup")


# =================================================================================================
# public API
# =================================================================================================

func get_shop_ids() -> Array:
	var out: Array = []
	for st: Dictionary in _states:
		out.append(st["id"])
	return out


## For map legends: [{id, display_name, kind, landmark, position, icon, open, screen, source}].
func get_shop_locations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for st: Dictionary in _states:
		var def: Dictionary = st["def"]
		var pos: Vector3 = st["anchor"]
		if st["managed"] and not (st["uses"] as Array).is_empty():
			pos = ((st["uses"] as Array)[0] as Dictionary)["xform"].origin
		out.append({
			"id": st["id"], "display_name": str(def.get("display_name", st["id"])), "kind": str(def.get("kind", "")),
			"landmark": str(def.get("landmark", "")), "position": pos, "icon": str(def.get("map_icon", "bag")),
			"open": not _is_closed(st), "screen": str(def.get("screen", "")), "source": st["source"],
		})
	return out


## Snapshot of one shop for UIs / tests.
func get_shop_state(shop_id: String) -> Dictionary:
	var st: Dictionary = _by_id.get(shop_id, {})
	if st.is_empty():
		return {}
	var staff: Variant = st["staff"]
	var uses: Array = []
	for u: Dictionary in st["uses"]:
		uses.append({"marker": u["marker"], "position": (u["xform"] as Transform3D).origin, "screen": u["screen"]})
	return {
		"id": shop_id, "open": not _is_closed(st), "closed_until": st["closed_until"], "close_reason": st["close_reason"],
		"threat": st["threat"], "robbery_progress": get_robbery_progress(shop_id), "source": st["source"],
		"has_staff": staff != null and is_instance_valid(staff), "staff_position": (st["staff_xform"] as Transform3D).origin,
		"uses": uses, "managed": st["managed"],
	}


## Interactables of one shop ("" = all shops and wardrobe points).
func get_interactables(shop_id: String = "") -> Array:
	var out: Array = []
	for st: Dictionary in _states:
		if shop_id != "" and st["id"] != shop_id:
			continue
		for u: Dictionary in st["uses"]:
			var n: Variant = u.get("node")
			if n != null and is_instance_valid(n):
				out.append(n)
	if shop_id == "":
		for w: Dictionary in _wardrobe_points:
			var n2: Variant = w.get("node")
			if n2 != null and is_instance_valid(n2):
				out.append(n2)
	return out


func is_open(shop_id: String) -> bool:
	var st: Dictionary = _by_id.get(shop_id, {})
	return not st.is_empty() and not _is_closed(st)


## Closes a shop for `hours` in-game hours (robbery, clerk killed, admin).
func close_shop(shop_id: String, hours: float = 6.0, reason: String = "closed") -> void:
	var st: Dictionary = _by_id.get(shop_id, {})
	if not st.is_empty():
		_close(st, hours, reason)


func reopen_shop(shop_id: String) -> void:
	var st: Dictionary = _by_id.get(shop_id, {})
	if not st.is_empty() and _is_closed(st):
		_reopen(st)


## Opens the shop's screen as if its use point `use_index` had been used.
func open_shop(shop_id: String, use_index: int = 0) -> Control:
	var st: Dictionary = _by_id.get(shop_id, {})
	if st.is_empty() or (st["uses"] as Array).is_empty():
		return null
	return _on_use(shop_id, clampi(use_index, 0, (st["uses"] as Array).size() - 1), Game.player)


func get_staff(shop_id: String) -> Node3D:
	var st: Dictionary = _by_id.get(shop_id, {})
	if st.is_empty():
		return null
	var s: Variant = st["staff"]
	return s as Node3D if s != null and is_instance_valid(s) else null


## Use any node as the clerk of a shop (tests, other modules). It is never despawned by the tier logic.
func register_staff(shop_id: String, node: Node3D) -> bool:
	var st: Dictionary = _by_id.get(shop_id, {})
	if st.is_empty() or node == null:
		return false
	if st["staff"] != null and is_instance_valid(st["staff"]) and st["staff"] != node and not st["staff_external"]:
		(st["staff"] as Node).queue_free()
	st["staff"] = node
	st["staff_external"] = true
	st["staff_dead"] = false
	st["threat"] = 0.0
	st["threat_started"] = false
	node.set_meta("shop_id", shop_id)
	return true


func unregister_staff(shop_id: String) -> void:
	var st: Dictionary = _by_id.get(shop_id, {})
	if not st.is_empty() and st["staff_external"]:
		st["staff"] = null
		st["staff_external"] = false


## 0..1 while the player is holding up the clerk.
func get_robbery_progress(shop_id: String) -> float:
	var st: Dictionary = _by_id.get(shop_id, {})
	return 0.0 if st.is_empty() else clampf(float(st["threat"]) / ROB_SECONDS, 0.0, 1.0)


func is_attachment_unlocked(weapon_id: String, att_id: String) -> bool:
	return (unlocked_attachments.get(weapon_id, {}) as Dictionary).has(att_id)


func unlock_attachment(weapon_id: String, att_id: String) -> void:
	if not unlocked_attachments.has(weapon_id):
		unlocked_attachments[weapon_id] = {}
	(unlocked_attachments[weapon_id] as Dictionary)[att_id] = true


func set_enabled(on: bool) -> void:
	enabled = on
	for n: Variant in get_interactables():
		(n as Interactable).enabled = on
	if not on:
		for st: Dictionary in _states:
			if not st["staff_external"]:
				_free_staff(st)


func reset_for_respawn() -> void:
	debug_force_threat.clear()
	for st: Dictionary in _states:
		st["threat"] = 0.0
		st["threat_started"] = false


func get_save_data() -> Dictionary:
	var closed: Dictionary = {}
	var now := _now_hours()
	for st: Dictionary in _states:
		if _is_closed(st):
			closed[st["id"]] = {"hours_left": maxf(float(st["closed_until"]) - now, 0.0), "reason": st["close_reason"]}
	var unlocked: Dictionary = {}
	for w: String in unlocked_attachments:
		unlocked[w] = (unlocked_attachments[w] as Dictionary).keys()
	return {"closed": closed, "unlocked": unlocked, "robberies": robbery_count}


func load_save_data(d: Dictionary) -> void:
	unlocked_attachments.clear()
	var unlocked: Variant = d.get("unlocked", {})
	if unlocked is Dictionary:
		for w: Variant in (unlocked as Dictionary).keys():
			var list: Variant = unlocked[w]
			if list is Array:
				for a: Variant in list:
					unlock_attachment(str(w), str(a))
	robbery_count = int(d.get("robberies", robbery_count))
	var closed: Variant = d.get("closed", {})
	for st: Dictionary in _states:
		var c: Variant = (closed as Dictionary).get(st["id"], null) if closed is Dictionary else null
		if c is Dictionary:
			_close(st, float((c as Dictionary).get("hours_left", 0.0)), str((c as Dictionary).get("reason", "closed")), false)
		elif _is_closed(st):
			_reopen(st, false)


# =================================================================================================
# building
# =================================================================================================

func _build_states() -> void:
	for d: Variant in Registry.all("shops"):
		if not (d is Dictionary) or str((d as Dictionary).get("id", "")) == "":
			continue
		var def := d as Dictionary
		var managed: bool = def.get("uses", null) is Array
		var st := {
			"id": str(def["id"]), "def": def, "managed": managed, "source": "none", "anchor": Vector3.ZERO,
			"uses": [], "staff": null, "staff_external": false, "staff_dead": false, "staff_fails": 0,
			"staff_xform": Transform3D.IDENTITY, "cash_pos": Vector3.ZERO,
			"closed_until": -1.0, "close_reason": "", "threat": 0.0, "threat_started": false,
		}
		if managed:
			var i := 0
			for u: Variant in def["uses"]:
				if not (u is Dictionary):
					continue
				var ud := u as Dictionary
				var it := Interactable.create(str(ud.get("prompt", "Shop")), USE_RADIUS)
				it.name = "Use_%s_%d" % [str(def["id"]), i]
				it.use_priority = USE_PRIORITY
				it.set_meta("shop_id", str(def["id"]))
				add_child(it)
				it.interacted.connect(_on_interacted.bind(str(def["id"]), i))
				(st["uses"] as Array).append({"marker": str(ud.get("marker", "")), "prompt": str(ud.get("prompt", "Shop")),
					"screen": str(ud.get("screen", def.get("screen", ""))), "args": (ud.get("args", {}) as Dictionary).duplicate(),
					"node": it, "xform": Transform3D.IDENTITY})
				i += 1
		_states.append(st)
		_by_id[st["id"]] = st


func _build_wardrobe_points() -> void:
	for wp: Dictionary in WARDROBE_POINTS:
		var it := Interactable.create(str(wp["prompt"]), USE_RADIUS)
		it.name = "Use_%s" % str(wp["id"])
		it.use_priority = USE_PRIORITY
		it.set_meta("shop_id", str(wp["id"]))
		add_child(it)
		it.interacted.connect(func(_p: Node3D) -> void: UI.open_screen("wardrobe", {"shop_id": str(wp["id"])}))
		var entry := wp.duplicate()
		entry["node"] = it
		entry["source"] = "none"
		_wardrobe_points.append(entry)


## (Re)computes every position; moves interactables and staff when a better source appeared.
func _resolve_all() -> void:
	for st: Dictionary in _states:
		if st["managed"]:
			_resolve_shop(st)
	for wp: Dictionary in _wardrobe_points:
		var m := _marker(str(wp["landmark"]), str(wp["marker"]))
		var x: Transform3D
		if not m.is_empty():
			x = m["xform"]
			wp["source"] = "city"
		else:
			var loc := Game.get_location(str(wp["landmark"]))
			x = Transform3D(loc.basis, loc.origin + loc.basis.x * float(wp.get("fallback_offset", 1.5)))
			wp["source"] = "location"
		var n: Variant = wp["node"]
		if n != null and is_instance_valid(n):
			(n as Node3D).position = x.origin + Vector3(0.0, USE_HEIGHT, 0.0)


func _resolve_shop(st: Dictionary) -> void:
	var def: Dictionary = st["def"]
	var landmark := str(def.get("landmark", ""))
	var city := Game.get_system("city")
	var loc := Game.get_location(landmark)
	var anchor := loc.origin
	if city != null and city.has_method("has_landmark") and bool(city.call("has_landmark", landmark)) \
			and city.has_method("get_landmark_transform"):
		var bx: Variant = city.call("get_landmark_transform", landmark)
		if bx is Transform3D:
			anchor = (bx as Transform3D).origin
	st["anchor"] = anchor
	var uses: Array = st["uses"]
	var all_city := true
	for i in uses.size():
		var u: Dictionary = uses[i]
		var m := _marker(landmark, str(u["marker"]))
		var x: Transform3D
		if not m.is_empty():
			x = m["xform"]
		else:
			all_city = false
			var off := (float(i) - float(uses.size() - 1) * 0.5) * FALLBACK_USE_SPACING
			x = Transform3D(loc.basis, loc.origin + loc.basis.x * off)
		u["xform"] = x
		var n: Variant = u["node"]
		if n != null and is_instance_valid(n):
			(n as Node3D).position = x.origin + Vector3(0.0, USE_HEIGHT, 0.0)
	var source := "city" if all_city and not uses.is_empty() else "location"
	# staff spot
	var old_staff: Transform3D = st["staff_xform"]
	var sm := _marker(landmark, str(def.get("staff_marker", "Staff")))
	if not sm.is_empty():
		st["staff_xform"] = sm["xform"]
	else:
		# no building: the clerk stands just inside the lot, facing the customer on the pavement
		var fwd := -loc.basis.z
		var pos := loc.origin + fwd * 2.0
		st["staff_xform"] = Transform3D(Basis(Vector3.UP, loc.basis.get_euler().y + PI), pos)
	# where the till money lands: the first use point (counter), on the customer side
	st["cash_pos"] = (uses[0]["xform"] as Transform3D).origin if not uses.is_empty() else anchor
	if source != st["source"]:
		st["source"] = source
		# moved: respawn our own clerk at the new place
		if (old_staff.origin - (st["staff_xform"] as Transform3D).origin).length() > 0.5 and not st["staff_external"]:
			_free_staff(st)


## {"xform": Transform3D} from the city system, {} when it has no such marker.
func _marker(landmark: String, marker: String) -> Dictionary:
	if landmark == "" or marker == "":
		return {}
	var city := Game.get_system("city")
	if city == null or not city.has_method("has_landmark_marker") or not city.has_method("get_landmark_marker"):
		return {}
	if not bool(city.call("has_landmark_marker", landmark, marker)):
		return {}
	var x: Variant = city.call("get_landmark_marker", landmark, marker)
	if not (x is Transform3D):
		return {}
	var xf := x as Transform3D
	if not xf.origin.is_finite():
		return {}
	return {"xform": xf}


func _needs_resolve() -> bool:
	if Game.get_system("city") == null:
		return false
	for st: Dictionary in _states:
		if st["managed"] and st["source"] != "city":
			return true
	for wp: Dictionary in _wardrobe_points:
		if wp["source"] != "city":
			return true
	return false


func _sources_text() -> String:
	var counts := {}
	for st: Dictionary in _states:
		if st["managed"]:
			counts[st["source"]] = int(counts.get(st["source"], 0)) + 1
	return str(counts)


func _on_game_ready() -> void:
	_resolve_all()
	get_tree().create_timer(1.5, false).timeout.connect(_dedupe_wardrobe_points)


## Another module (safehouse) may own a wardrobe use point on the same spot: drop ours then.
func _dedupe_wardrobe_points() -> void:
	for wp: Dictionary in _wardrobe_points:
		var mine: Variant = wp["node"]
		if mine == null or not is_instance_valid(mine):
			continue
		var p := (mine as Node3D).global_position
		for n: Node in get_tree().get_nodes_in_group("interactable"):
			if n == mine or not (n is Node3D) or n.get_parent() == self:
				continue
			if (n as Node3D).global_position.distance_to(p) <= DEDUPE_RADIUS + USE_HEIGHT:
				print("[Shops] wardrobe point '%s' left to %s" % [wp["id"], n.get_path()])
				(mine as Node).queue_free()
				wp["node"] = null
				break


# =================================================================================================
# runtime
# =================================================================================================

func _physics_process(delta: float) -> void:
	if not enabled or not _set_up:
		return
	_age += delta
	_rob_timer += delta
	if _rob_timer >= ROB_TICK:
		var dt := _rob_timer
		_rob_timer = 0.0
		_robbery_tick(dt)
	_slow_timer += delta
	if _slow_timer >= SLOW_TICK:
		_slow_timer = 0.0
		_slow_tick()
	if _age < RESOLVE_WINDOW:
		_resolve_timer += delta
		if _resolve_timer >= 1.0:
			_resolve_timer = 0.0
			if _needs_resolve():
				_resolve_all()


func _slow_tick() -> void:
	var now := _now_hours()
	var ppos := Game.get_player_position()
	var peds := Game.get_system("peds")
	for st: Dictionary in _states:
		if not st["managed"]:
			continue
		if _is_closed(st) and now >= float(st["closed_until"]):
			_reopen(st)
		if not bool((st["def"] as Dictionary).get("staff", false)):
			continue
		var staff: Variant = st["staff"]
		if staff != null and not is_instance_valid(staff):
			st["staff"] = null
			staff = null
			st["staff_external"] = false
		var d := ppos.distance_to((st["staff_xform"] as Transform3D).origin)
		if staff != null:
			if not st["staff_external"] and d > STAFF_DESPAWN_DIST and float(st["threat"]) <= 0.0:
				_free_staff(st)
		elif peds != null and d < STAFF_SPAWN_DIST and not st["staff_dead"] and int(st["staff_fails"]) < STAFF_MAX_FAILS:
			_spawn_staff(st)


func _spawn_staff(st: Dictionary) -> void:
	var x: Transform3D = st["staff_xform"]
	var def: Dictionary = st["def"]
	var opts := {"yaw": x.basis.get_euler().y, "persistent": true, "role": "shop_staff", "shop_id": st["id"]}
	var look: Variant = def.get("staff_look", {})
	if look is Dictionary and not (look as Dictionary).is_empty():
		opts["appearance"] = (look as Dictionary).duplicate()
	var npc := Game.spawn_npc(STAFF_ARCHETYPE, x.origin, opts)
	if npc == null or not is_instance_valid(npc):
		st["staff_fails"] = int(st["staff_fails"]) + 1
		return
	npc.set_meta("shop_id", st["id"])
	npc.add_to_group("shop_staff")
	st["staff"] = npc
	st["staff_external"] = false


func _free_staff(st: Dictionary) -> void:
	var s: Variant = st["staff"]
	if s != null and is_instance_valid(s) and not st["staff_external"]:
		(s as Node).queue_free()
	if not st["staff_external"]:
		st["staff"] = null
	st["threat"] = 0.0
	st["threat_started"] = false


func _on_interacted(player: Node3D, shop_id: String, use_index: int) -> void:
	_on_use(shop_id, use_index, player)


func _on_use(shop_id: String, use_index: int, player: Node3D) -> Control:
	var st: Dictionary = _by_id.get(shop_id, {})
	if st.is_empty() or not enabled:
		return null
	var def: Dictionary = st["def"]
	if _is_closed(st):
		UI.notify("%s is closed until %s" % [str(def.get("display_name", shop_id)), _hours_to_clock(float(st["closed_until"]))], "warn")
		Audio.play("ui_error", -4.0, 1.0, "UI")
		return null
	if bool(st["threat_started"]) and float(st["threat"]) > 0.0:
		return null
	var u: Dictionary = (st["uses"] as Array)[use_index]
	var staff := get_staff(shop_id)
	if staff != null and player != null and staff.has_method("face_position"):
		staff.call("face_position", player.global_position)
	var args: Dictionary = (u["args"] as Dictionary).duplicate()
	args["shop_id"] = shop_id
	return UI.open_screen(str(u["screen"]), args)


# --- robbery ---------------------------------------------------------------------------------

func _robbery_tick(dt: float) -> void:
	if not Game.has_player():
		return
	var ppos := Game.player.global_position
	var reach := (ROB_RANGE + 4.0) * (ROB_RANGE + 4.0)
	for st: Dictionary in _states:
		if not st["managed"] or not bool((st["def"] as Dictionary).get("robbable", false)):
			continue
		var staff: Variant = st["staff"]
		var forced := debug_force_threat.has(st["id"])
		if staff == null or not is_instance_valid(staff) or _is_dead(staff as Node) or _is_closed(st):
			st["threat"] = 0.0
			continue
		if not forced and ppos.distance_squared_to((staff as Node3D).global_position) > reach:
			if float(st["threat"]) > 0.0:
				st["threat"] = maxf(0.0, float(st["threat"]) - dt * ROB_DECAY)
			continue
		if forced or _is_player_threatening(staff as Node3D):
			if not st["threat_started"]:
				_start_threat(st)
			st["threat"] = float(st["threat"]) + dt
			if float(st["threat"]) >= ROB_SECONDS:
				_complete_robbery(st)
		else:
			st["threat"] = maxf(0.0, float(st["threat"]) - dt * ROB_DECAY)
			if float(st["threat"]) <= 0.0:
				st["threat_started"] = false


## The player aims a firearm (on foot) at the clerk's chest from within ROB_RANGE.
func _is_player_threatening(staff: Node3D) -> bool:
	var p := Game.player
	if p == null or bool(p.get("is_dead")) or p.get("current_vehicle") != null:
		return false
	if not bool(p.get("is_aiming")):
		return false
	var inv := Catalog.inventory()
	if inv == null or not inv.has_method("get_current_spec"):
		return false
	var spec: Variant = inv.call("get_current_spec")
	if not (spec is Object) or not Catalog.is_firearm(spec as Object):
		return false
	var target := staff.global_position + Vector3(0.0, 1.25, 0.0)
	if staff.has_method("get_target_position"):
		var t: Variant = staff.call("get_target_position")
		if t is Vector3:
			target = t
	if p.global_position.distance_to(target) > ROB_RANGE:
		return false
	var o := p.global_position + Vector3(0.0, 1.5, 0.0)
	var d := -p.global_basis.z
	if p.has_method("get_aim_ray"):
		var ray: Variant = p.call("get_aim_ray")
		if ray is Dictionary:
			o = (ray as Dictionary).get("origin", o)
			d = (ray as Dictionary).get("direction", d)
	d = d.normalized()
	var to := target - o
	var along := to.dot(d)
	if along <= 0.2:
		return false
	var perp := (to - d * along).length()
	return perp <= maxf(0.85, along * 0.2)


func _start_threat(st: Dictionary) -> void:
	st["threat_started"] = true
	var staff: Node = st["staff"]
	# AI clerks (W2.2) react through their brain (hands up, later cower / flee); plain nodes directly
	var brain: Variant = staff.get("brain")
	if brain is Object and is_instance_valid(brain) and (brain as Object).has_method("on_event"):
		(brain as Object).call("on_event", staff, "threatened", {"by": Game.player, "shop_id": st["id"]})
	elif staff.has_method("surrender"):
		staff.call("surrender")
	UI.notify("The clerk raises their hands - keep them covered", "warn", 2.5)


func _complete_robbery(st: Dictionary) -> void:
	var def: Dictionary = st["def"]
	var staff: Node3D = st["staff"]
	var range_v: Variant = def.get("robbery_cash", [200, 500])
	var lo := 200
	var hi := 500
	if range_v is Array and (range_v as Array).size() >= 2:
		lo = int(range_v[0])
		hi = maxi(int(range_v[1]), lo)
	var cash := Game.rng.randi_range(lo, hi)
	var pos: Vector3 = st["cash_pos"] + Vector3(0.0, 0.45, 0.0)
	var spawned := false
	var pickups := Game.get_system("pickups")
	if pickups != null and pickups.has_method("spawn_pickup"):
		var pk: Variant = pickups.call("spawn_pickup", "cash", "", cash, pos)
		spawned = pk != null
	if not spawned:
		Game.add_money(cash)
	Wanted.report_crime("robbery", staff.global_position, {"instigator": Game.player, "victim": staff})
	if staff.has_method("cower"):
		staff.call("cower")
	Audio.play_at("cash_register", pos, 0.0, 1.0, 30.0, "SFX")
	robbery_count += 1
	var shop_name := str(def.get("display_name", st["id"]))
	UI.notify("%s robbed: %s %s" % [shop_name, UiStyleMoney.fmt(cash), "on the counter" if spawned else "taken"], "money", 4.0)
	_close(st, float(def.get("closed_hours", 6.0)), "robbed")
	st["threat"] = 0.0
	st["threat_started"] = false
	shop_robbed.emit(st["id"], cash)


func _on_npc_died(npc: Node3D, _killer: Node, _info: Dictionary) -> void:
	for st: Dictionary in _states:
		if st["staff"] == npc:
			st["staff_dead"] = true
			st["threat"] = 0.0
			if not _is_closed(st):
				var def: Dictionary = st["def"]
				_close(st, float(def.get("closed_hours", 6.0)), "staff_killed")
				UI.notify("%s is closed - the clerk is down" % str(def.get("display_name", st["id"])), "bad")
			return


# --- open / closed ---------------------------------------------------------------------------

func _is_closed(st: Dictionary) -> bool:
	return float(st["closed_until"]) >= 0.0


func _close(st: Dictionary, hours: float, reason: String, emit: bool = true) -> void:
	st["closed_until"] = _now_hours() + maxf(hours, 0.0)
	st["close_reason"] = reason
	var shop_name := str((st["def"] as Dictionary).get("display_name", st["id"]))
	for u: Dictionary in st["uses"]:
		var n: Variant = u.get("node")
		if n != null and is_instance_valid(n):
			(n as Interactable).prompt = "%s (closed)" % shop_name
	if emit:
		shop_closed.emit(st["id"], reason)


func _reopen(st: Dictionary, emit: bool = true) -> void:
	st["closed_until"] = -1.0
	st["close_reason"] = ""
	st["staff_dead"] = false
	st["staff_fails"] = 0
	var s: Variant = st["staff"]
	if s != null and is_instance_valid(s) and not st["staff_external"]:
		_free_staff(st)       # the next tier tick brings a fresh clerk
	for u: Dictionary in st["uses"]:
		var n: Variant = u.get("node")
		if n != null and is_instance_valid(n):
			(n as Interactable).prompt = str(u["prompt"])
	if emit:
		shop_reopened.emit(st["id"])


## Monotonic in-game hours (WorldClock day * 24 + hour).
func _now_hours() -> float:
	var day: Variant = WorldClock.get("day")
	var hour: Variant = WorldClock.get("hour")
	return float(day if day != null else 0) * 24.0 + float(hour if hour != null else 0.0)


func _hours_to_clock(abs_hours: float) -> String:
	var h := fposmod(abs_hours, 24.0)
	return "%02d:%02d" % [int(h), int(fposmod(h * 60.0, 60.0))]


static func _is_dead(n: Node) -> bool:
	return bool(n.get("is_dead")) if "is_dead" in n else false


## Tiny formatting helper (no dependency on the UI module's classes from the world module).
class UiStyleMoney:
	static func fmt(n: int) -> String:
		var s := str(absi(n))
		var out := ""
		var c := 0
		for i in range(s.length() - 1, -1, -1):
			out = s[i] + out
			c += 1
			if c % 3 == 0 and i > 0:
				out = "," + out
		return "$" + out
