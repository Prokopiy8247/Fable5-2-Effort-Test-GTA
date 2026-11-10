class_name Combat
extends RefCounted
## Static combat utilities shared by the player's WeaponInventory AND by AI.
##
##   Combat.fire_hitscan(origin, direction, spec_or_id, instigator, opts) -> Dictionary
##   Combat.launch(spec_or_id, origin, direction, instigator, opts)        -> Node3D (projectile)
##   Combat.melee_sweep(attacker, origin, direction, reach, damage, opts)   -> Array
##   Combat.spawn_projectile(kind, origin, velocity, instigator, opts)      -> Node3D
##   Combat.has_line_of_sight(from, to, exclude)                            -> bool
##   Combat.npc_fire(npc, weapon_id, target_position, accuracy)             -> Dictionary
##
## Everything a shot causes happens here exactly once: ray(s), damage through the Dmg contract,
## impact FX, tracer, sound, EventBus.weapon_fired, AI noise, the player's "gunfire" crime report
## and EventBus.hit_confirmed for the HUD hit marker. See docs/WEAPONS.md.

## Physics frames (60 Hz) between two "gunfire" crime reports of the player.
const GUNFIRE_REPORT_FRAMES := 90
## Physics frames between two noise events of the same instigator and kind.
const NOISE_MIN_FRAMES := 9
const MAX_TRACERS_PER_SHOT := 4
const MAX_PENETRATIONS := 2
## Head shots against the PLAYER never multiply by more than this (survivability).
const PLAYER_HEADSHOT_CAP := 1.5
## Colliders on these layers are thin by convention: bullets with penetration pass through.
const THIN_LAYERS := Layers.GLASS | Layers.PROP
const MELEE_MASK := Layers.WORLD | Layers.PLAYER | Layers.NPC | Layers.VEHICLE | Layers.PROP | Layers.GLASS
## Fallback wheel order (same as the vehicle module) for vehicles without the wheel query API.
const WHEEL_NAMES: Array[String] = ["Wheel_FL", "Wheel_FR", "Wheel_ML", "Wheel_MR", "Wheel_RL", "Wheel_RR",
		"Wheel_F", "Wheel_R"]

## Bullets fired by NPCs are scaled by this before they reach the player (difficulty knob).
static var npc_damage_scale: float = 0.55
## How many "gunfire" crimes were reported to Wanted so far (debug / tests).
static var gunfire_reports: int = 0

static var _last_gunfire_frame: int = -100000
static var _noise_frames: Dictionary = {}      ## "<instance id>:<kind>" -> physics frame


# --- hitscan ------------------------------------------------------------------------------------

## Fire one shot (all pellets) of a hitscan weapon.
## opts (all optional):
##   spread_deg: float      cone half-angle; default spec.spread_base
##   pellets: int           default spec.pellets
##   max_range: float       default spec.max_range
##   damage_mult: float     default 1.0
##   exclude: Array         extra Nodes / RIDs the ray ignores (shooter + its vehicle are automatic)
##   muzzle: Vector3        where tracers and the shot sound start (default: origin)
##   muzzle_node: Node3D    Fx.muzzle_flash target;  eject_node: Node3D  Fx.shell_eject target
##                          (not for specs with eject_shells = false; rocket launcher: back-blast puff)
##   suppressed: bool       force suppressed behaviour
##   no_fx / no_sound / no_noise / no_crime: bool
## Returns {hit, position, normal, collider, target, damage, zone, headshot, distance, killed,
##          end (Vector3 where the first pellet stopped), hits: Array[Dictionary] per pellet hit}.
static func fire_hitscan(origin: Vector3, direction: Vector3, spec_or_id: Variant, instigator: Node = null,
		opts: Dictionary = {}) -> Dictionary:
	var result := {
		"hit": false, "position": origin, "normal": Vector3.UP, "collider": null, "target": null,
		"damage": 0.0, "zone": "", "headshot": false, "distance": 0.0, "killed": false,
		"end": origin, "hits": [],
	}
	var spec := WeaponSpec.resolve(spec_or_id)
	if spec == null:
		push_warning("Combat.fire_hitscan: unknown weapon %s" % str(spec_or_id))
		return result
	var space := _space(instigator)
	if space == null or direction.length_squared() < 0.000001:
		return result
	var dir := direction.normalized()
	var spread := float(opts.get("spread_deg", spec.spread_base))
	var pellets := maxi(int(opts.get("pellets", spec.pellets)), 1)
	var max_range := float(opts.get("max_range", spec.max_range))
	var damage_mult := float(opts.get("damage_mult", 1.0))
	var exclude := _build_exclude(instigator, opts.get("exclude", []))
	var muzzle: Vector3 = opts.get("muzzle", origin)
	var by_player := Dmg.is_player(instigator)
	var by_npc := instigator != null and is_instance_valid(instigator) and instigator.is_in_group("npc")
	var silent := spec.suppressed or bool(opts.get("suppressed", false))
	var no_fx := bool(opts.get("no_fx", false))
	var own_vehicle := _vehicle_of(instigator)
	var per_target: Dictionary = {}     # instance id -> accumulated hit
	var character_hit := false
	var hits: Array = result["hits"]
	result["end"] = origin + dir * max_range

	for p in pellets:
		var pdir := spread_direction(dir, spread)
		var from := origin
		var travelled := 0.0
		var power := 1.0
		var pen_left := MAX_PENETRATIONS if spec.penetration > 0.0 else 0
		var pellet_exclude := exclude
		var end_point := origin + pdir * max_range
		var own_skips := 0
		while true:
			var remaining := max_range - travelled
			if remaining <= 0.05:
				break
			var to := from + pdir * remaining
			var query := PhysicsRayQueryParameters3D.create(from, to, Layers.BULLET_MASK, pellet_exclude)
			var hit := space.intersect_ray(query)
			var water_point := _water_crossing(from, to if hit.is_empty() else (hit["position"] as Vector3))
			if water_point != Vector3.INF:
				end_point = water_point
				if not no_fx:
					Fx.splash(water_point, 0.5)
				break
			if hit.is_empty():
				end_point = to
				break
			var pos: Vector3 = hit["position"]
			var normal: Vector3 = hit["normal"]
			var collider: Object = hit["collider"]
			var dist := travelled + from.distance_to(pos)
			end_point = pos
			var surface := Fx.surface_of(collider)
			var target := Dmg.find_damageable(collider)
			# a separate collider that belongs to the shooter or to the shooter's own vehicle
			# (seat helpers, door / glass bodies ...) is never a target: the bullet passes
			if target != null and (target == instigator or target == own_vehicle) and own_skips < 8:
				own_skips += 1
				pellet_exclude = pellet_exclude.duplicate()
				pellet_exclude.append(hit["rid"])
				travelled = dist
				from = pos
				continue
			var zone := ""
			var amount := 0.0
			if target != null:
				var mult := spec.falloff_at(dist) * power * damage_mult
				if _is_humanoid(target):
					zone = Dmg.zone_for_humanoid(target as Node3D, pos, _height_of(target))
					if zone == "head":
						mult *= minf(spec.headshot_mult, PLAYER_HEADSHOT_CAP) if Dmg.is_player(target) else spec.headshot_mult
					elif zone == "limb":
						mult *= spec.limb_mult
				elif target.is_in_group("vehicle"):
					mult *= spec.vehicle_damage_mult
					_try_pop_tire(target, pos)
				if by_npc and Dmg.is_player(target):
					mult *= npc_damage_scale
				amount = spec.damage * mult
				if _is_character(target):
					character_hit = true
				_accumulate(per_target, target, amount, pos, normal, zone, collider, int(hit.get("shape", 0)), dist)
			hits.append({"position": pos, "normal": normal, "collider": collider, "target": target,
					"damage": amount, "zone": zone, "surface": surface, "distance": dist})
			if not no_fx:
				Fx.impact(pos, normal, surface, 1.0 if pellets == 1 else 0.7)
			# thin-surface penetration (glass, light props, colliders tagged with meta "thin")
			if pen_left > 0 and _is_thin(collider, target, spec):
				pen_left -= 1
				power *= 0.9 if surface == "glass" else 0.65
				pellet_exclude = pellet_exclude.duplicate()
				pellet_exclude.append(hit["rid"])
				travelled = dist + 0.02
				from = pos + pdir * 0.02
				end_point = from + pdir * (max_range - travelled)
				continue
			break
		if p == 0:
			result["end"] = end_point
		if spec.tracer and not no_fx and p < MAX_TRACERS_PER_SHOT and muzzle.distance_squared_to(end_point) > 4.0:
			Fx.tracer(muzzle, end_point)

	# main result = the pellet hit that did the most damage (or simply the first hit)
	var best: Dictionary = {}
	for h: Dictionary in hits:
		if best.is_empty() or float(h["damage"]) > float(best["damage"]):
			best = h
	if not best.is_empty():
		result["hit"] = true
		result["position"] = best["position"]
		result["normal"] = best["normal"]
		result["collider"] = best["collider"]
		result["distance"] = best["distance"]

	_shot_side_effects(spec, origin, dir, instigator, opts, silent, character_hit, muzzle)

	# deliver the accumulated damage: one apply_damage per target and shot
	var total := 0.0
	for key: int in per_target:
		var acc: Dictionary = per_target[key]
		var target: Node = acc["target"]
		if not is_instance_valid(target):
			continue
		var info := Dmg.make(float(acc["amount"]), "bullet", instigator, acc["position"], dir, {
			"normal": acc["normal"], "impulse": spec.impulse * float(acc["pellets"]), "weapon_id": spec.id,
			"headshot": acc["zone"] == "head", "zone": acc["zone"], "silent": silent,
			"collider": acc["collider"], "shape": acc["shape"], "distance": acc["distance"],
			"pellets": acc["pellets"],
		})
		# "killed" means THIS shot did it: a target that was already down (a corpse, a wreck)
		# never reports a kill again, and shooting it trains nothing
		var was_dead := _is_dead(target)
		var is_character := _is_character(target)
		target.apply_damage(info)
		total += float(acc["amount"])
		var killed := not was_dead and _is_dead(target)
		info["killed"] = killed
		if result["target"] == null or float(acc["amount"]) > float(result["damage"]):
			result["target"] = target
			result["zone"] = acc["zone"]
			result["headshot"] = acc["zone"] == "head"
			result["killed"] = killed
			result["damage"] = float(acc["amount"])
		if by_player:
			EventBus.hit_confirmed.emit(target if is_instance_valid(target) else null, info)
			if is_character and not was_dead:
				Skills.add_xp("shooting", 0.12 if acc["zone"] == "head" else 0.05)
	result["damage"] = total
	return result


# --- projectile weapons -------------------------------------------------------------------------

## Launch the projectile of a launcher / thrown weapon (rocket, launcher grenade, hand grenade,
## fire bottle) with all side effects of a shot. `direction` is the launch direction.
## opts: speed (default spec.projectile_speed), inherit_velocity: Vector3, fuse: float,
##       spread_deg, muzzle_node, eject_node (rocket back-blast), no_sound / no_noise / no_crime,
##       muzzle (sound position).
static func launch(spec_or_id: Variant, origin: Vector3, direction: Vector3, instigator: Node = null,
		opts: Dictionary = {}) -> Node3D:
	var spec := WeaponSpec.resolve(spec_or_id)
	if spec == null or spec.projectile_kind == "" or direction.length_squared() < 0.000001:
		return null
	var dir := spread_direction(direction.normalized(), float(opts.get("spread_deg", 0.0)))
	var speed := float(opts.get("speed", spec.projectile_speed))
	var velocity: Vector3 = dir * speed + (opts.get("inherit_velocity", Vector3.ZERO) as Vector3)
	var popts := {"damage": spec.damage, "radius": spec.blast_radius, "weapon_id": spec.id}
	if opts.has("fuse"):
		popts["fuse"] = opts["fuse"]
	var node := spawn_projectile(spec.projectile_kind, origin, velocity, instigator, popts)
	_shot_side_effects(spec, origin, dir, instigator, opts, spec.is_thrown(), false, opts.get("muzzle", origin))
	return node


## Spawn a projectile: kind "grenade", "rocket", "grenade_round" or "molotov".
## opts: damage, radius, fuse, weapon_id (see Projectile.KINDS for the defaults).
static func spawn_projectile(kind: String, origin: Vector3, velocity: Vector3, instigator: Node = null,
		opts: Dictionary = {}) -> Node3D:
	return Projectile.launch(kind, origin, velocity, instigator, opts)


## Launch velocity that lands a ballistic projectile on `target` (low arc). When the target is
## out of reach for `speed` a 45 degree lob in its direction is returned.
static func ballistic_velocity(origin: Vector3, target: Vector3, speed: float, gravity: float = 9.8) -> Vector3:
	var delta := target - origin
	var flat := Vector3(delta.x, 0.0, delta.z)
	var x := flat.length()
	if x < 0.01:
		return Vector3.UP * speed
	var flat_dir := flat / x
	var v2 := speed * speed
	var disc := v2 * v2 - gravity * (gravity * x * x + 2.0 * delta.y * v2)
	var angle := PI * 0.25
	if disc >= 0.0:
		angle = atan2(v2 - sqrt(disc), gravity * x)
	return (flat_dir * cos(angle) + Vector3.UP * sin(angle)) * speed


# --- melee --------------------------------------------------------------------------------------

## Close combat hit test: a straight ray along `direction` plus a forgiving cone for characters.
## opts: weapon_id, arc_deg (full cone, default 110), max_targets (default 1), impulse (default 4),
##       knockdown: bool, heavy: bool, sound_hit (default "melee_hit"), vehicle_mult (default 1),
##       exclude: Array, no_fx: bool
## Returns an Array of {target, collider, position, damage, killed, surface}.
static func melee_sweep(attacker: Node, origin: Vector3, direction: Vector3, reach: float, damage: float,
		opts: Dictionary = {}) -> Array:
	var out: Array = []
	var space := _space(attacker)
	if space == null or direction.length_squared() < 0.000001:
		return out
	var dir := direction.normalized()
	var exclude := _build_exclude(attacker, opts.get("exclude", []))
	var max_targets := maxi(int(opts.get("max_targets", 1)), 1)
	var cos_half := cos(deg_to_rad(float(opts.get("arc_deg", 110.0)) * 0.5))
	var by_player := Dmg.is_player(attacker)
	var candidates: Array = []          # {collider, target, position, normal, distance}
	var seen: Dictionary = {}

	# 1) whatever is straight ahead (walls, vehicles, glass, people)
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach, MELEE_MASK, exclude)
	var front := space.intersect_ray(ray)
	if not front.is_empty():
		var collider: Object = front["collider"]
		var target := Dmg.find_damageable(collider)
		seen[_key_of(target, collider)] = true
		candidates.append({"collider": collider, "target": target, "position": front["position"],
				"normal": front["normal"], "distance": origin.distance_to(front["position"])})

	# 2) characters and props inside the swing cone
	var sphere := SphereShape3D.new()
	sphere.radius = reach * 0.5 + 0.3
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = sphere
	shape_query.transform = Transform3D(Basis.IDENTITY, origin + dir * reach * 0.5)
	shape_query.collision_mask = Layers.PLAYER | Layers.NPC | Layers.PROP | Layers.GLASS
	shape_query.exclude = exclude
	for res: Dictionary in space.intersect_shape(shape_query, 16):
		var collider: Object = res["collider"]
		var target := Dmg.find_damageable(collider)
		var key := _key_of(target, collider)
		if seen.has(key) or not (collider is Node3D):
			continue
		var centre := _aim_point_of(target if target is Node3D else collider)
		var to_c := centre - origin
		to_c.y = clampf(to_c.y, -0.4, 0.4)      # height differences inside one swing do not matter
		var d := to_c.length()
		if d > reach + 0.35:
			continue
		if d > 0.3 and to_c.normalized().dot(dir) < cos_half:
			continue
		seen[key] = true
		candidates.append({"collider": collider, "target": target,
				"position": centre - to_c.normalized() * 0.25 if d > 0.3 else centre,
				"normal": -dir, "distance": d})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
	var impulse := float(opts.get("impulse", 4.0))
	var knockdown := bool(opts.get("knockdown", false))
	var landed := 0
	for c: Dictionary in candidates:
		if landed >= max_targets:
			break
		var collider: Object = c["collider"]
		var target: Node = c["target"]
		var pos: Vector3 = c["position"]
		var surface := Fx.surface_of(collider)
		var amount := 0.0
		var killed := false
		if target != null and is_instance_valid(target):
			amount = damage
			if target.is_in_group("vehicle"):
				amount *= float(opts.get("vehicle_mult", 1.0))
			var info := Dmg.make(amount, "melee", attacker, pos, dir, {
				"normal": c["normal"], "impulse": impulse, "weapon_id": str(opts.get("weapon_id", "")),
				"zone": "torso", "silent": true, "knockdown": knockdown, "heavy": bool(opts.get("heavy", false)),
				"collider": collider,
			})
			var was_dead := _is_dead(target)
			var is_character := _is_character(target)
			target.apply_damage(info)
			var dead_now := _is_dead(target)
			killed = dead_now and not was_dead       # only the blow that did it counts as the kill
			info["killed"] = killed
			if knockdown and not dead_now and is_instance_valid(target) and target.has_method("knock_down"):
				target.call("knock_down", (dir + Vector3.UP * 0.35).normalized() * impulse)
			if by_player:
				EventBus.hit_confirmed.emit(target if is_instance_valid(target) else null, info)
				if is_character and not was_dead:
					Skills.add_xp("strength", 0.08)
		elif collider is RigidBody3D:
			(collider as RigidBody3D).apply_impulse(dir * impulse * 4.0, pos - (collider as RigidBody3D).global_position)
		if not bool(opts.get("no_fx", false)):
			Fx.impact(pos, c["normal"], surface, 0.8)
			Audio.play_at(str(opts.get("sound_hit", "melee_hit")), pos, -2.0, randf_range(0.92, 1.08), 30.0, "SFX")
		out.append({"target": target, "collider": collider, "position": pos, "damage": amount,
				"killed": killed, "surface": surface})
		landed += 1
	if landed > 0:
		emit_noise(origin, 8.0, "melee", attacker)
	return out


# --- sight --------------------------------------------------------------------------------------

## True when nothing opaque (Layers.SIGHT_MASK) lies between `from` and `to`.
## `exclude` may hold Nodes (CollisionObject3D) or RIDs, e.g. the observer's own vehicle.
static func has_line_of_sight(from: Vector3, to: Vector3, exclude: Array = []) -> bool:
	var space := _space(null)
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.SIGHT_MASK, _build_exclude(null, exclude))
	return space.intersect_ray(query).is_empty()


## Generic ray helper on any mask. Returns the intersect_ray dictionary ({} when clear).
static func raycast(from: Vector3, to: Vector3, mask: int = Layers.BULLET_MASK, exclude: Array = []) -> Dictionary:
	var space := _space(null)
	if space == null:
		return {}
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask, _build_exclude(null, exclude)))


# --- AI convenience -----------------------------------------------------------------------------

## One trigger pull by an NPC (any weapon kind). `accuracy` 0..1 widens the cone for poor shots.
## The caller keeps its own cadence (see WeaponSpec.get_fire_interval()) and magazine count.
## Returns the fire_hitscan dictionary; for melee {"hits": Array}; for projectiles {"projectile"}.
static func npc_fire(npc: Node3D, weapon_id: Variant, target_position: Vector3, accuracy: float = 0.6) -> Dictionary:
	var spec := WeaponSpec.resolve(weapon_id)
	if spec == null or npc == null or not is_instance_valid(npc):
		return {"hit": false, "hits": []}
	var origin := _npc_muzzle(npc)
	var to := target_position - origin
	var dist := to.length()
	if dist < 0.01:
		return {"hit": false, "hits": []}
	var dir := to / dist
	var acc := clampf(accuracy, 0.0, 1.0)
	var opts := {}
	if npc.has_method("get_muzzle_node"):
		var mn: Variant = npc.call("get_muzzle_node")
		if mn is Node3D and is_instance_valid(mn):
			opts["muzzle_node"] = mn
			opts["muzzle"] = (mn as Node3D).global_position
	if spec.is_melee():
		var hits := melee_sweep(npc, origin, dir, spec.melee_range, spec.damage,
				{"weapon_id": spec.id, "sound_hit": spec.melee_sound_hit, "impulse": spec.impulse})
		return {"hit": not hits.is_empty(), "hits": hits}
	if spec.projectile_kind != "":
		var launch_dir := dir
		if spec.projectile_kind != "rocket":
			launch_dir = ballistic_velocity(origin, target_position, spec.projectile_speed).normalized()
		opts["spread_deg"] = (1.0 - acc) * 5.0
		var node := launch(spec, origin + launch_dir * 0.5, launch_dir, npc, opts)
		return {"hit": false, "hits": [], "projectile": node}
	# scoped weapons carry a deliberately wide hip-fire cone (the player is meant to aim them);
	# an NPC marksman shoots aimed, so only `accuracy` decides how well it shoots
	var base_spread := spec.spread_base * (spec.spread_aim_mult if spec.scoped else 1.0)
	opts["spread_deg"] = base_spread + (1.0 - acc) * 7.0
	return fire_hitscan(origin, dir, spec, npc, opts)


# --- shared helpers (public) --------------------------------------------------------------------

## Random direction inside a cone of half-angle `spread_deg` around `dir` (uniform over the disc).
static func spread_direction(dir: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.0001:
		return dir
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(dir).normalized()
	var r := sqrt(randf()) * tan(deg_to_rad(minf(spread_deg, 80.0)))
	var a := randf() * TAU
	return (dir + side * cos(a) * r + up * sin(a) * r).normalized()


## AI-audible noise with a per-instigator rate limit (automatic fire does not flood listeners).
static func emit_noise(position: Vector3, radius: float, kind: String, instigator: Node = null) -> void:
	if radius <= 0.0:
		return
	var key := "%d:%s" % [instigator.get_instance_id() if instigator != null and is_instance_valid(instigator) else 0, kind]
	var frame := Engine.get_physics_frames()
	if frame - int(_noise_frames.get(key, -100000)) < NOISE_MIN_FRAMES:
		return
	if _noise_frames.size() > 96:
		_noise_frames.clear()
	_noise_frames[key] = frame
	EventBus.noise_emitted.emit(position, radius, kind, instigator)


## Forget rate-limit state (tests; also safe to call after a load).
static func reset_rate_limits() -> void:
	_last_gunfire_frame = -100000
	_noise_frames.clear()


# --- internals ----------------------------------------------------------------------------------

static func _shot_side_effects(spec: WeaponSpec, origin: Vector3, dir: Vector3, instigator: Node, opts: Dictionary,
		silent: bool, character_hit: bool, sound_position: Vector3) -> void:
	var by_player := Dmg.is_player(instigator)
	if not bool(opts.get("no_fx", false)):
		var mn: Variant = opts.get("muzzle_node", null)
		if mn is Node3D and is_instance_valid(mn) and spec.is_firearm():
			Fx.muzzle_flash(mn as Node3D, 0.5 if silent else (1.4 if spec.pellets > 1 or spec.is_launcher() else 1.0))
		var en: Variant = opts.get("eject_node", null)
		if en is Node3D and is_instance_valid(en) and (en as Node3D).is_inside_tree():
			if spec.is_hitscan():
				if spec.eject_shells:
					Fx.shell_eject(en as Node3D)
			elif spec.projectile_kind == "rocket":
				# the launcher's Eject marker is its rear end: back-blast
				Fx.smoke_puff((en as Node3D).global_position, "light", 1.3)
		if by_player and spec.shake > 0.0:
			Fx.shake_camera(spec.shake * (0.6 if silent else 1.0))
	if not bool(opts.get("no_sound", false)) and spec.sound_fire != "":
		var sound := "suppressed_shot" if (silent and spec.is_hitscan()) else spec.sound_fire
		Audio.play_at(sound, sound_position, 0.0 if by_player else -3.0, randf_range(0.96, 1.04),
				45.0 if silent else 140.0, "Weapons")
	EventBus.weapon_fired.emit(spec.id, instigator, origin, dir)
	if not bool(opts.get("no_noise", false)):
		var kind := "suppressed_gunshot" if silent else "gunshot"
		if spec.is_thrown():
			kind = "footstep"
		emit_noise(origin, spec.noise_radius, kind, instigator)
	# the player's gunfire in public is a crime; suppressed shots only once somebody is hit
	if by_player and spec.is_firearm() and not bool(opts.get("no_crime", false)) and (not silent or character_hit):
		var frame := Engine.get_physics_frames()
		if frame - _last_gunfire_frame >= GUNFIRE_REPORT_FRAMES:
			_last_gunfire_frame = frame
			gunfire_reports += 1
			Wanted.report_crime("gunfire", origin, {"instigator": instigator})


static func _space(ctx: Node) -> PhysicsDirectSpaceState3D:
	var world: World3D = null
	if ctx is Node3D and is_instance_valid(ctx) and (ctx as Node3D).is_inside_tree():
		world = (ctx as Node3D).get_world_3d()
	if world == null:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			world = tree.root.find_world_3d()
	return world.direct_space_state if world != null else null


## The vehicle a shooter sits in (member `current_vehicle`), or null.
static func _vehicle_of(who: Node) -> Node:
	if who == null or not is_instance_valid(who):
		return null
	var vehicle: Variant = who.get("current_vehicle")
	if vehicle != null and is_instance_valid(vehicle) and vehicle is Node:
		return vehicle as Node
	return null


static func _build_exclude(instigator: Node, extra: Variant) -> Array[RID]:
	var out: Array[RID] = []
	if instigator != null and is_instance_valid(instigator):
		if instigator is CollisionObject3D:
			out.append((instigator as CollisionObject3D).get_rid())
		var vehicle := _vehicle_of(instigator)
		if vehicle is CollisionObject3D:
			out.append((vehicle as CollisionObject3D).get_rid())
	if extra is Array:
		for e: Variant in extra:
			if e is RID:
				out.append(e)
			elif e != null and is_instance_valid(e) and e is CollisionObject3D:
				out.append((e as CollisionObject3D).get_rid())
	return out


static func _accumulate(per_target: Dictionary, target: Node, amount: float, pos: Vector3, normal: Vector3,
		zone: String, collider: Object, shape: int, dist: float) -> void:
	var key := target.get_instance_id()
	if not per_target.has(key):
		per_target[key] = {"target": target, "amount": amount, "position": pos, "normal": normal, "zone": zone,
				"collider": collider, "shape": shape, "distance": dist, "pellets": 1}
		return
	var acc: Dictionary = per_target[key]
	acc["amount"] = float(acc["amount"]) + amount
	acc["pellets"] = int(acc["pellets"]) + 1
	if _zone_rank(zone) > _zone_rank(str(acc["zone"])):
		acc["zone"] = zone
		acc["position"] = pos
		acc["normal"] = normal


static func _key_of(target: Node, collider: Object) -> int:
	if target != null:
		return target.get_instance_id()
	return collider.get_instance_id() if collider != null else 0


static func _zone_rank(zone: String) -> int:
	match zone:
		"head": return 3
		"torso": return 2
		"limb": return 1
	return 0


static func _is_character(target: Node) -> bool:
	return target.is_in_group("npc") or target.is_in_group("player") or target.is_in_group("animal")


## Humanoids get head / torso / limb zones. Anything can opt in with set_meta("humanoid", true).
static func _is_humanoid(target: Node) -> bool:
	if not (target is Node3D):
		return false
	if target.has_meta("humanoid"):
		return bool(target.get_meta("humanoid"))
	if target.is_in_group("animal") or target.is_in_group("vehicle"):
		return false
	return target.is_in_group("npc") or target.is_in_group("player")


static func _height_of(target: Node) -> float:
	var h: Variant = target.get("height")
	if h is float and float(h) > 0.3:
		return float(h)
	if target.get("is_crouching") == true:
		return 1.25
	return 1.8


static func _is_dead(target: Node) -> bool:
	if not is_instance_valid(target):
		return true
	if target.get("is_dead") == true or target.get("destroyed") == true:
		return true
	return false


static func _is_thin(collider: Object, target: Node, spec: WeaponSpec) -> bool:
	if not (collider is CollisionObject3D):
		return false
	var co := collider as CollisionObject3D
	if co.has_meta("thin"):
		return bool(co.get_meta("thin"))
	if co.is_in_group("vehicle"):
		return false
	if (co.collision_layer & THIN_LAYERS) != 0:
		return true
	# high-power rounds go through a body and can hit whoever stands behind
	if target != null and _is_character(target) and spec.penetration >= 0.4:
		return true
	return false


## A bullet that lands on a wheel pops that tyre. Uses the vehicle's wheel query API
## (get_wheel_count / get_wheel_position / get_wheel_radius) when it has one, otherwise the
## Wheel_* nodes by name. pop_tire is idempotent, so a vehicle that also pops its own tyres from
## the bullet damage info is not affected. Bulletproof tyres (mod_stats) are respected.
static func _try_pop_tire(vehicle: Node, hit_pos: Vector3) -> bool:
	if not vehicle.has_method("pop_tire"):
		return false
	var mods: Variant = vehicle.get("mod_stats")
	if mods is Dictionary and bool((mods as Dictionary).get("bulletproof_tires", false)):
		return false
	if vehicle.has_method("get_wheel_count") and vehicle.has_method("get_wheel_position"):
		var has_radius := vehicle.has_method("get_wheel_radius")
		for i in int(vehicle.call("get_wheel_count")):
			var wp: Variant = vehicle.call("get_wheel_position", i)
			var radius := float(vehicle.call("get_wheel_radius", i)) if has_radius else 0.36
			if wp is Vector3 and (wp as Vector3).distance_to(hit_pos) < radius * 1.1:
				vehicle.call("pop_tire", i)
				return true
		return false
	var index := 0
	for wheel_name in WHEEL_NAMES:
		var w := vehicle.find_child(wheel_name, true, false) as Node3D
		if w == null:
			continue
		if w.global_position.distance_to(hit_pos) < 0.42:
			vehicle.call("pop_tire", index)
			return true
		index += 1
	return false


## Point where the segment a->b dives into the sea, or Vector3.INF.
static func _water_crossing(a: Vector3, b: Vector3) -> Vector3:
	var level := Game.WATER_LEVEL
	if a.y <= level or b.y >= level:
		return Vector3.INF
	var t := (a.y - level) / (a.y - b.y)
	var p := a.lerp(b, t)
	if Game.is_in_water(Vector3(p.x, level - 0.05, p.z)):
		return p
	return Vector3.INF


static func _aim_point_of(node: Object) -> Vector3:
	if node is Node3D:
		var n := node as Node3D
		if n.has_method("get_target_position"):
			var v: Variant = n.call("get_target_position")
			if v is Vector3:
				return v
		if _is_character(n):
			return n.global_position + Vector3.UP * 1.1
		return n.global_position
	return Vector3.ZERO


static func _npc_muzzle(npc: Node3D) -> Vector3:
	if npc.has_method("get_muzzle_position"):
		var v: Variant = npc.call("get_muzzle_position")
		if v is Vector3:
			return v
	return npc.global_position + Vector3.UP * 1.45
