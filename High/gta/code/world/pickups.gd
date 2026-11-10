class_name Pickups
extends Node3D
## World pickups: cash, health, armour, ammo, weapons, parachutes and scuba gear. Proximity based (no physics areas).

var items: Array = []    # {node, kind, amount, weapon, respawn, t, home, expire}


func place(kind: String, pos: Vector3, amount: int = 0, weapon: String = "", respawn: float = 120.0) -> void:
	items.append({"node": _make(kind, pos), "kind": kind, "amount": amount, "weapon": weapon, "respawn": respawn, "t": 0.0, "home": pos, "expire": -1.0})


func drop(kind: String, pos: Vector3, amount: int = 0, weapon: String = "") -> void:
	if items.size() > 70:
		for it in items:
			if it.expire > 0.0:
				it.expire = 0.01
				break
	var gy := Game.ground_y(pos.x, pos.z)
	pos.y = maxf(gy, Game.WATER_Y) + 0.35
	items.append({"node": _make(kind, pos), "kind": kind, "amount": amount, "weapon": weapon, "respawn": -1.0, "t": 0.0, "home": pos, "expire": 60.0})


func _make(kind: String, pos: Vector3) -> Node3D:
	var n := Assets.inst("pk_" + kind)
	add_child(n)
	n.global_position = pos
	n.scale = Vector3.ONE * 1.5
	return n


func _physics_process(delta: float) -> void:
	var p = Game.player
	if p == null:
		return
	var ppos: Vector3 = p.center()
	var t := Time.get_ticks_msec() * 0.001
	var i := 0
	while i < items.size():
		var it: Dictionary = items[i]
		var node: Node3D = it.node
		if it.t > 0.0:
			it.t -= delta
			if it.t <= 0.0:
				node.visible = true
			i += 1
			continue
		if it.expire > 0.0:
			it.expire -= delta
			if it.expire <= 0.0:
				node.queue_free()
				items.remove_at(i)
				continue
		var d: float = (it.home as Vector3).distance_to(ppos)
		if d < 60.0:
			node.rotation.y = t * 1.6
			node.position.y = it.home.y + sin(t * 2.2 + it.home.x) * 0.1
		if d < 1.7 and p.alive() and _collect(p, it):
			if it.respawn > 0.0:
				it.t = it.respawn
				node.visible = false
			else:
				node.queue_free()
				items.remove_at(i)
				continue
		i += 1


func _collect(p, it: Dictionary) -> bool:
	match it.kind:
		"cash":
			Game.add_money(it.amount)
			Game.say("+$%d" % it.amount, Color(0.5, 1.0, 0.5))
		"health":
			if p.health >= p.max_health:
				return false
			p.health = minf(p.max_health, p.health + 60.0)
			Game.say("Health restored", Color(1.0, 0.5, 0.5))
		"armor":
			if p.armor >= 100.0:
				return false
			p.armor = 100.0
			Game.say("Body armour equipped", Color(0.5, 0.7, 1.0))
		"ammo":
			var id: String = it.weapon
			if id == "" or not p.inv.has(id):
				id = p.inv.current
			var d: WeaponDef = Data.weapons[id]
			if d.kind == "melee":
				Game.add_money(25)
				Game.say("+$25", Color(0.5, 1.0, 0.5))
			else:
				p.inv.add_ammo(id, d.ammo_per_buy())
				Game.say("%s ammo" % d.name, Color(1.0, 0.9, 0.5))
		"weapon":
			var wid: String = it.weapon
			var had: bool = p.inv.has(wid)
			p.inv.give(wid, Data.weapons[wid].ammo_per_buy())
			Game.say(("%s ammo" if had else "Picked up %s") % Data.weapons[wid].name, Color(1.0, 0.9, 0.5))
			if not had:
				p.equip(wid)
		"parachute":
			if p.has_parachute:
				return false
			p.give_parachute()
			Game.say("Parachute equipped", Color(1.0, 0.8, 0.5))
		"scuba":
			p.scuba = true
			p.rig.set_extra("tank", true)
			p.rig.set_extra("scuba_mask", true)
			Game.say("Scuba gear equipped - long dives enabled", Color(0.5, 0.9, 1.0))
	Sfx.play("pickup", -6.0)
	if Game.hud:
		Game.hud.refresh_weapon()
	return true
