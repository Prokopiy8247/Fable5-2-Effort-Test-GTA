class_name PedManager
extends Node
## Ambient population. Spawns / despawns pedestrians around the player on the sidewalk
## graph and in free-roam areas (parks, beach, plaza, pier), assigns simulation tiers by
## distance, routes sounds to NPC ears and answers population queries (witnesses, crowds).

const SPAWN_MIN := 38.0
const SPAWN_MAX := 96.0
const DESPAWN := 128.0
const TIER0 := 52.0
const TIER1 := 104.0
const MAX_BODIES := 10
const DISTRICT_DENSITY := {
	"Downtown": 1.0, "Midtown": 1.0, "Palm Row": 0.6, "Coral Beach": 0.9, "Ironworks": 0.4,
	"Saltline Docks": 0.4, "Vesper Airfield": 0.06, "Lookout Hill": 0.3, "Vesper Bay": 0.0, "Outskirts": 0.0,
}

var graph: PedGraph = null
var rng := RandomNumberGenerator.new()
var root: Node3D = null
var base_count := 30
var ambient_count := 0
var _spawn_cd := 0.5
var _slice := 0
var _serial := 0
var _gunshot_gate := 0.0
var _gang_done := false
var _initial := true

func _ready() -> void:
	rng.seed = 90210
	root = Game.main.get_node("Entities/NPCs") as Node3D
	graph = PedGraph.new()
	if Game.world != null:
		graph.build(Game.world.layout)
	Events.noise.connect(_on_noise)
	print("[Peds] sidewalk graph: ", graph.pts.size(), " points")

# ---------------------------------------------------------------- creation
func spawn(role: StringName, pos: Vector3, yaw := 0.0, ap: Dictionary = {}) -> NPC:
	_serial += 1
	var r := RandomNumberGenerator.new()
	r.seed = hash(_serial * 7919 + 17)
	if ap.is_empty():
		match role:
			&"police": ap = Appearance.police(r, false)
			&"swat": ap = Appearance.police(r, true)
			&"gang": ap = Appearance.gang(r)
			_: ap = Appearance.random_civilian(r)
	var n := NPC.new()
	n.name = "%s_%d" % [role, _serial]
	root.add_child(n)
	n.init_npc(role, ap, int(r.seed))
	n.global_position = pos
	n.set_face_yaw(yaw)
	return n

## A driver (or passenger) created directly in a vehicle seat.
func seat_in(veh: Vehicle, seat_index: int, role: StringName = &"driver", ap: Dictionary = {}) -> NPC:
	if seat_index < 0 or seat_index >= veh.seat_count() or veh.seats[seat_index]["occupant"] != null:
		return null
	var n := spawn(role, veh.global_position + Vector3(0, 1.0, 0), 0.0, ap)
	veh.seat_character(seat_index, n)
	n.state = NPC.S.SEATED
	return n

func count() -> int:
	return get_tree().get_nodes_in_group(&"npcs").size()

func clear(all := false) -> void:
	for n in get_tree().get_nodes_in_group(&"npcs"):
		var npc := n as NPC
		if all or npc.ambient:
			if npc.vehicle != null and is_instance_valid(npc.vehicle):
				(npc.vehicle as Vehicle).eject(npc)
			npc.queue_free()
	ambient_count = 0

func in_radius(pos: Vector3, radius: float, alive_only := true) -> Array[NPC]:
	var out: Array[NPC] = []
	var r2 := radius * radius
	for n in get_tree().get_nodes_in_group(&"npcs"):
		var npc := n as NPC
		if alive_only and not npc.alive:
			continue
		if npc.global_position.distance_squared_to(pos) <= r2:
			out.append(npc)
	return out

## Civilians (and officers) with a clear view of `pos`.
func witnesses(pos: Vector3, radius: float) -> Dictionary:
	var civil: Array[NPC] = []
	var cops: Array[NPC] = []
	var at := pos + Vector3(0, 1.2, 0)
	for npc in in_radius(pos, radius):
		if npc.tier >= 2 or npc.down:
			continue
		var d := npc.global_position.distance_to(pos)
		# behind their back only counts when very close
		var to := (pos - npc.global_position)
		to.y = 0.0
		if d > 6.0 and to.normalized().dot(npc.forward()) < -0.2 and not npc.is_alerted():
			continue
		var ex: Array[RID] = [npc.get_rid()]
		if npc.vehicle != null and is_instance_valid(npc.vehicle):
			ex.append((npc.vehicle as CollisionObject3D).get_rid())
		var pv: Node3D = Game.player_target()
		if pv is CollisionObject3D:
			ex.append((pv as CollisionObject3D).get_rid())
		if Game.player != null:
			ex.append(Game.player.get_rid())
		if not Game.ray(npc.eye_position(), at, Phys.SIGHT_BLOCK, ex).is_empty():
			continue
		if npc.is_cop():
			cops.append(npc)
		elif npc.role != &"gang":
			civil.append(npc)
	return {"civil": civil, "police": cops}

# ---------------------------------------------------------------- hearing
func _on_noise(pos: Vector3, radius: float, kind: StringName, source: Node) -> void:
	if kind == &"footstep" or kind == &"siren":
		return
	if kind == &"gunshot":
		# automatic fire: one routing pass every 0.2 s is plenty
		var now := Game.clock
		if now < _gunshot_gate:
			return
		_gunshot_gate = now + 0.2
	var r2 := radius * radius
	for n in get_tree().get_nodes_in_group(&"npcs"):
		var npc := n as NPC
		if npc == source or not npc.alive or npc.tier >= 2:
			continue
		if npc.global_position.distance_squared_to(pos) <= r2:
			npc.hear(pos, kind, source)

# ---------------------------------------------------------------- population
func target_count() -> int:
	if not Game.flags["pedestrians"]:
		return 0
	var f := float(Settings.get_v("ped_density", 1.0))
	var env: WorldEnv = Game.time
	if env != null:
		f *= lerpf(1.0, 0.4, env.night)
		f *= lerpf(1.0, 0.45, clampf(env.rain * 1.4, 0.0, 1.0))
	return int(round(base_count * f))

func _physics_process(delta: float) -> void:
	NPC.scream_gate = maxf(0.0, NPC.scream_gate - delta)
	if Game.player == null:
		return
	var centre := Game.player_pos()
	var list := get_tree().get_nodes_in_group(&"npcs")
	# --- tiers + despawn, a slice per frame
	var cam: Camera3D = Game.cam.cam if Game.cam != null else null
	var n_total := list.size()
	var bodies: Array[NPC] = []
	var amb := 0
	for i in n_total:
		var npc := list[i] as NPC
		if npc.ambient and npc.alive:
			amb += 1
		if not npc.alive:
			bodies.append(npc)
	ambient_count = amb
	var per_frame := mini(n_total, 10)
	for k in per_frame:
		_slice = (_slice + 1) % maxi(n_total, 1)
		var npc := list[_slice] as NPC
		if npc.is_queued_for_deletion():
			continue
		var d := npc.global_position.distance_to(centre)
		npc.set_tier(0 if d < TIER0 else (1 if d < TIER1 else 2))
		if npc.vehicle != null:
			continue
		var seen := cam != null and d < 150.0 and cam.is_position_in_frustum(npc.global_position + Vector3(0, 1.0, 0))
		if not npc.alive:
			if (npc._dead_t > 70.0 and (not seen or d > 70.0)) or npc._dead_t > 150.0 or d > DESPAWN:
				npc.queue_free()
		elif npc.ambient:
			if d > DESPAWN or (d > 75.0 and not seen and amb > target_count() + 3):
				npc.queue_free()
				amb -= 1
	# never keep more than a handful of corpses around
	if bodies.size() > MAX_BODIES:
		var oldest: NPC = bodies[0]
		for b in bodies:
			if b._dead_t > oldest._dead_t:
				oldest = b
		oldest.queue_free()
	# --- spawning
	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		var want := target_count()
		_spawn_cd = 0.12 if (_initial and amb < want) else 0.35
		if amb < want:
			for attempt in 4:
				if _try_spawn(centre, cam):
					break
		else:
			_initial = false
	if not _gang_done and Game.world != null and Game.world.city != null:
		_gang_done = true
		_spawn_fixed()

func _try_spawn(centre: Vector3, cam: Camera3D) -> bool:
	var pos := Vector3.ZERO
	var area: Dictionary = {}
	var e_from := -1
	var e_to := -1
	var e_type := 0
	var areas: Array = Game.world.city.ped_areas if Game.world != null and Game.world.city != null else []
	var lo := 14.0 if _initial else SPAWN_MIN
	if rng.randf() < 0.3 and not areas.is_empty():
		area = areas[rng.randi() % areas.size()]
		var r: Rect2 = area["rect"]
		pos = Vector3(rng.randf_range(r.position.x, r.end.x), float(area.get("y", 0.15)), rng.randf_range(r.position.y, r.end.y))
	else:
		if graph.pts.is_empty():
			return false
		e_from = rng.randi() % graph.pts.size()
		var links: Array = graph.adj[e_from]
		if links.is_empty():
			return false
		var e: Array = links[rng.randi() % links.size()]
		if int(e[1]) == PedGraph.T_CROSS:
			return false
		e_to = int(e[0])
		e_type = int(e[1])
		pos = graph.pts[e_from].lerp(graph.pts[e_to], rng.randf())
	var d := pos.distance_to(centre)
	if d < lo or d > SPAWN_MAX:
		return false
	if rng.randf() > float(DISTRICT_DENSITY.get(Game.district_at(pos), 0.5)):
		return false
	if not _initial and cam != null and d < 82.0 and cam.is_position_in_frustum(pos + Vector3(0, 1.0, 0)):
		return false
	# real surface under the point (kerbs, pier decks, sand)
	var hit := Game.ray(pos + Vector3(0, 2.5, 0), pos - Vector3(0, 3.0, 0), Phys.WORLD)
	if hit.is_empty():
		return false
	pos = hit["position"]
	if Game.water_depth(pos + Vector3(0, 0.3, 0)) > 0.25:
		return false
	if not in_radius(pos, 1.6, false).is_empty():
		return false
	var npc := spawn(&"civil", pos + Vector3(0, 0.05, 0), rng.randf() * TAU, _ambient_look(pos))
	npc.ambient = true
	if e_from >= 0:
		npc.walk_edge(e_from, e_to, e_type, graph.pts)
	else:
		npc.wander_area(area)
	npc.set_tier(0 if d < TIER0 else 1)
	return true

## District flavour: beachwear on the sand, work clothes in the industrial quarter.
func _ambient_look(pos: Vector3) -> Dictionary:
	var ap := Appearance.random_civilian(rng)
	var district := Game.district_at(pos)
	if district == "Coral Beach" and pos.z > 205.0:
		ap["legs"] = "short"
		ap["sleeves"] = "short"
		ap["shoes"] = ap["skin"]
		if String(ap["body"]) == "male" and rng.randf() < 0.6:
			ap["shirt"] = ap["skin"]
		if rng.randf() < 0.4:
			ap["glasses"] = "sunglasses"
	elif district == "Ironworks" or district == "Saltline Docks":
		if rng.randf() < 0.55:
			ap["shirt"] = ["ef7f2d", "f2c230", "55585e", "22407f"][rng.randi() % 4]
			ap["pants"] = ["3d5a80", "2e3035", "55585e"][rng.randi() % 3]
			ap["legs"] = "long"
			ap["hat"] = "cap" if rng.randf() < 0.5 else ""
			ap["hat_color"] = "f2c230"
			ap["extras"] = []
	elif district == "Downtown":
		if rng.randf() < 0.4:
			ap["shirt"] = ["f2f0ea", "17181b", "22407f", "8b8e93"][rng.randi() % 4]
			ap["sleeves"] = "long"
			ap["legs"] = "long"
			ap["pants"] = ["17181b", "2e3035", "55585e"][rng.randi() % 3]
	return ap

## Fixed groups that give the map some character: a gang hanging out in the scrapyard.
func _spawn_fixed() -> void:
	var city: CityBuilder = Game.world.city
	var loc: Dictionary = city.locations.get("gang_turf", {})
	# default turf: the scrapyard behind Torque House in Ironworks
	var c: Vector3 = loc.get("pos", Vector3(186.0, CityLayout.CURB_H, 86.0))
	var rect := Rect2(c.x - 7.0, c.z - 6.0, 14.0, 12.0)
	for i in 4:
		var p := Vector3(rng.randf_range(rect.position.x, rect.end.x), c.y + 0.1, rng.randf_range(rect.position.y, rect.end.y))
		var g := spawn(&"gang", p, rng.randf() * TAU)
		g.wander_area({"rect": rect, "y": c.y})
