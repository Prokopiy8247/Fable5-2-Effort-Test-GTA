extends Node
## POLICE debug helper (no checks that matter): the 2-star on-foot response at the downtown plaza,
## logging every police car 4x per second (position, speed, pedals, mode, tactic, obstacle, contacts)
## so slow / wedged approaches can be diagnosed. Not part of the regular suite.
##   tools\godot.ps1 -Mode headless -Frames 3600 -TimeoutSec 300 -UserArgs '--test=pol_route_debug','--test-timeout=280','--seed=21','--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'

var T: Node


func _ready() -> void:
	T = TestHarness
	await T.wait_seconds(1.0)
	var pol := Game.get_system("police")
	var p := Game.player
	if not T.check(pol != null and p != null, "police + player"):
		T.finish()
		return
	var level := 2
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pol_level="):
			level = int(a.substr(12))
		if a == "--pol_dump":
			# gang hangouts vs named locations (where police tests can stand without a gang next door)
			var gangs: Array = Game.world.call("get_spawn_points", "gang")
			for g: Transform3D in gangs:
				T.log_line("GANGSPOT %s" % str(g.origin.round()))
			var locs: Dictionary = Game.world.call("get_locations")
			for k: String in locs.keys():
				var o: Vector3 = (locs[k] as Transform3D).origin
				var best := INF
				for g: Transform3D in gangs:
					best = minf(best, Vector2(g.origin.x - o.x, g.origin.z - o.z).length())
				T.log_line("LOC %s %s nearest_gang=%.0f" % [k, str(o.round()), best])
			T.finish()
			return
	pol.call("reset_for_respawn")
	var xf := Game.get_location("downtown_plaza")
	p.call("teleport", xf.origin, xf.basis.get_euler().y)
	T.log_line("player at %s" % str(xf.origin.round()))
	await T.wait_seconds(1.0)
	_dump_statics(Vector3(57.8, 3.2, -79.0), 7.0)
	Wanted.set_level(level)
	var t := 0.0
	while t < 40.0:
		await T.wait_seconds(0.25)
		t += 0.25
		for u: Variant in pol.get("units"):
			var o := u as Object
			var v: RigidBody3D = o.get("vehicle")
			if v == null or not is_instance_valid(v):
				continue
			var di: Dictionary = o.call("get_debug_info")
			var cont := []
			for b in v.get_colliding_bodies():
				cont.append(str(b.name).left(24))
			if absf(t - 12.0) < 0.01 or absf(t - 6.0) < 0.01:
				var rt: PackedVector3Array = o.get("route")
				var vm: PackedFloat32Array = o.get("route_vmax")
				var parts := []
				for i in rt.size():
					parts.append("%s@%.0f" % [str(rt[i].snapped(Vector3(0.1, 0.1, 0.1))), vm[i] if i < vm.size() else -1.0])
				T.log_line("ROUTE u%d %s" % [v.get_instance_id() % 1000, " ".join(parts)])
			T.log_line("t=%.2f u%d pos=%s d=%.0f spd=%.1f m=%s tac=%s thr=%.2f brk=%.2f st=%.2f blk=%s rs=%.1f/%d c=%s" % [t,
					v.get_instance_id() % 1000, str(v.global_position.snapped(Vector3(0.1, 0.1, 0.1))),
					v.global_position.distance_to(p.global_position), float(di["speed"]), str(di["mode"]), str(di["tactic"]),
					float(di["thr"]), float(di["brk"]), float(di["steer"]), str(di["block"]), float(di["route_s"]),
					int(di["route_pts"]), str(cont)])
	Wanted.clear("cheat")
	T.finish()


## Static (WORLD / PROP) collision shapes around `c`: name, shape kind, world position.
func _dump_statics(c: Vector3, r: float) -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = r
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, c)
	q.collision_mask = Layers.WORLD | Layers.PROP
	var hits := get_viewport().get_world_3d().direct_space_state.intersect_shape(q, 32)
	for h: Dictionary in hits:
		var col: Object = h.get("collider")
		var si := int(h.get("shape", 0))
		var pos := Vector3.INF
		var kind := "?"
		if col is CollisionObject3D:
			var co := col as CollisionObject3D
			var owner_id := co.shape_find_owner(si)
			var sh := co.shape_owner_get_shape(owner_id, 0)
			kind = sh.get_class() if sh != null else "?"
			if sh is BoxShape3D:
				kind += str((sh as BoxShape3D).size.snapped(Vector3(0.01, 0.01, 0.01)))
			elif sh is CylinderShape3D:
				kind += "r%.2f h%.2f" % [(sh as CylinderShape3D).radius, (sh as CylinderShape3D).height]
			pos = (co.global_transform * co.shape_owner_get_transform(owner_id)).origin
		T.log_line("STATIC %s %s at %s" % [str((col as Node).name) if col is Node else "?", kind, str(pos.snapped(Vector3(0.1, 0.1, 0.1)))])
