class_name VehicleFactory
## Creates fully configured vehicles from their definition id.


static func spawn(vid: String, pos: Vector3, yaw: float = 0.0, parent: Node = null) -> Vehicle:
	if not Defs.VEHICLES.has(vid):
		push_error("Unknown vehicle " + vid)
		return null
	var v: Vehicle
	match String(Defs.VEHICLES[vid].kind):
		"boat": v = Boat.new()
		"heli": v = Heli.new()
		"plane": v = Airplane.new()
		_: v = Car.new()
	v.setup(vid)
	(parent if parent != null else G.main).add_child(v)
	v.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	return v


static func spawn_near_player(vid: String, dist: float = 6.0) -> Vehicle:
	var p: Node3D = G.player
	var fwd := Basis(Vector3.UP, G.cam.yaw if G.cam else 0.0) * Vector3(0, 0, -1)
	var pos: Vector3 = G.player.global_position_now() + fwd * (dist + (4.0 if Defs.VEHICLES[vid].kind in ["plane", "heli"] else 0.0))
	var kind: String = Defs.VEHICLES[vid].kind
	if kind == "boat":
		if pos.y > G.WATER_LEVEL + 0.5:
			var best := Vector3(170, G.WATER_LEVEL + 0.3, 215)
			if G.world:
				for b in G.world.spawns.get("boats", []):
					if (b.pos as Vector3).distance_to(pos) < best.distance_to(pos) or best == Vector3(170, G.WATER_LEVEL + 0.3, 215):
						best = b.pos + Vector3(0, 0, 9)
			pos = best
			G.say("Boat delivered to the marina", Color(0.7, 0.9, 1))
		else:
			pos.y = G.WATER_LEVEL + 0.3
	else:
		var h := G.ray(pos + Vector3(0, 30, 0), pos - Vector3(0, 60, 0), G.L_WORLD)
		pos.y = (h.position.y if not h.is_empty() else p.global_position.y) + 0.6
	return spawn(vid, pos, (G.cam.yaw if G.cam else 0.0))
