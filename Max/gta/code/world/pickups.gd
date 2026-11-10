class_name Pickups
extends Node
## Collectable items: cash dropped by people and robbed tills, weapons dropped by armed NPCs,
## fixed world pickups (health, armour, weapons, cash stashes - they respawn) and underwater
## treasure. Blender models from `pickups/<id>` are used when exported, otherwise a simple
## procedural shape with the same colours.

const WORLD := [
	# [kind, id, position, amount]
	["health", "", Vector3(-112.0, 0.3, 74.0), 50],
	["health", "", Vector3(70.0, 0.3, -282.0), 50],
	["health", "", Vector3(150.0, 0.3, -40.0), 50],
	["armor", "", Vector3(190.0, 0.3, 112.0), 50],
	["armor", "", Vector3(-30.0, 0.3, -282.0), 100],
	["weapon", "pistol", Vector3(-128.0, 0.3, -66.0), 24],
	["weapon", "bat", Vector3(-210.0, 0.3, 190.0), 0],
	["weapon", "shotgun_pump", Vector3(188.0, 0.3, 78.0), 16],
	["weapon", "rifle_sniper", Vector3(-200.0, 30.8, -182.0), 10],
	["weapon", "smg", Vector3(52.0, 0.3, 230.0), 60],
	["weapon", "launcher_rocket", Vector3(262.0, 0.3, 214.0), 2],
	["weapon", "grenade", Vector3(244.0, 0.3, -96.0), 4],
	["cash", "", Vector3(-58.0, 0.3, 214.0), 300],
	["cash", "", Vector3(118.0, 0.3, -148.0), 300],
	["parachute", "", Vector3(-6.0, 0.3, -260.0), 1],
]
const RESPAWN := 300.0
const COLORS := {"health": Color(0.25, 0.85, 0.45), "armor": Color(0.25, 0.5, 1.0), "cash": Color(0.45, 0.85, 0.3),
	"weapon": Color(1.0, 0.65, 0.2), "treasure": Color(1.0, 0.82, 0.25), "parachute": Color(0.9, 0.3, 0.6)}

class Item:
	extends RefCounted
	var kind := ""
	var id := ""
	var amount := 0
	var node: Node3D = null
	var home := Vector3.ZERO
	var fixed := false
	var gone_until := 0.0
	var expires := 0.0
	var spin := 0.0

var items: Array[Item] = []
var root: Node3D
var _cash_mat: StandardMaterial3D

func _ready() -> void:
	root = Game.main.get_node("Entities/Pickups") as Node3D
	for e in WORLD:
		var it := _make(String(e[0]), String(e[1]), e[2], int(e[3]), true)
		it.fixed = true
	if Game.world != null and Game.world.city != null:
		for sp in Game.world.city.pickup_spots:
			var kind2 := String(sp["kind"])
			var it2 := _make(kind2, "", sp["pos"], 500 if kind2 == "treasure" else 100, kind2 != "treasure")

# ---------------------------------------------------------------- creation
func _visual(kind: String, id: String) -> Node3D:
	var holder := Node3D.new()
	var rel := "pickups/pickup_" + kind
	if kind == "weapon" and Assets.has_model("weapons/" + id):
		var w := Assets.instance("weapons/" + id)
		holder.add_child(w)
		w.rotation = Vector3(0, PI * 0.5, 0)
	elif Assets.has_model(rel):
		holder.add_child(Assets.instance(rel))
	else:
		var mi := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COLORS.get(kind, Color.WHITE)
		mat.roughness = 0.45
		mat.emission_enabled = true
		mat.emission = (COLORS.get(kind, Color.WHITE) as Color) * 0.35
		match kind:
			"cash":
				var bm := BoxMesh.new()
				bm.size = Vector3(0.32, 0.12, 0.16)
				mi.mesh = bm
			"health":
				var bm2 := BoxMesh.new()
				bm2.size = Vector3(0.38, 0.28, 0.2)
				mi.mesh = bm2
				mat.albedo_color = Color(0.95, 0.95, 0.93)
				var band := MeshInstance3D.new()
				var bb := BoxMesh.new()
				bb.size = Vector3(0.39, 0.08, 0.21)
				band.mesh = bb
				var bmat := StandardMaterial3D.new()
				bmat.albedo_color = COLORS["health"]
				bmat.emission_enabled = true
				bmat.emission = COLORS["health"] * 0.5
				band.material_override = bmat
				holder.add_child(band)
			"armor":
				var cm := CylinderMesh.new()
				cm.top_radius = 0.2
				cm.bottom_radius = 0.24
				cm.height = 0.42
				cm.radial_segments = 8
				mi.mesh = cm
			"treasure":
				var bm3 := BoxMesh.new()
				bm3.size = Vector3(0.5, 0.34, 0.34)
				mi.mesh = bm3
				mat.metallic = 0.8
			_:
				var sm := SphereMesh.new()
				sm.radius = 0.2
				sm.height = 0.4
				mi.mesh = sm
		mi.material_override = mat
		holder.add_child(mi)
	# soft glow so pickups read at night
	var light := OmniLight3D.new()
	light.light_color = COLORS.get(kind, Color.WHITE)
	light.light_energy = 0.6
	light.omni_range = 2.2
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 10.0
	holder.add_child(light)
	return holder

func _make(kind: String, id: String, pos: Vector3, amount: int, fixed := false) -> Item:
	var it := Item.new()
	it.kind = kind
	it.id = id
	it.amount = amount
	it.home = pos
	it.fixed = fixed
	it.node = _visual(kind, id)
	it.node.name = "Pickup_%s_%s" % [kind, id]
	root.add_child(it.node)
	it.node.global_position = pos + Vector3(0, 0.45, 0)
	it.spin = randf() * TAU
	items.append(it)
	return it

func drop_cash(amount: int, pos: Vector3) -> void:
	if amount <= 0:
		return
	var it := _make("cash", "", _ground(pos), amount)
	it.expires = Game.clock + 90.0

func drop_weapon(id: StringName, ammo: int, pos: Vector3) -> void:
	if id == &"unarmed" or id == &"":
		return
	var it := _make("weapon", String(id), _ground(pos), ammo)
	it.expires = Game.clock + 60.0

func _ground(pos: Vector3) -> Vector3:
	var hit := Game.ray(pos + Vector3(0, 0.5, 0), pos - Vector3(0, 6.0, 0), Phys.WORLD)
	if not hit.is_empty():
		return hit["position"]
	return pos

# ---------------------------------------------------------------- per-frame
func _process(delta: float) -> void:
	var p: Player = Game.player
	if p == null:
		return
	var pp := p.global_position + Vector3(0, 0.6, 0)
	var t := Game.clock
	for i in range(items.size() - 1, -1, -1):
		var it := items[i]
		if it.gone_until > 0.0:
			if t >= it.gone_until and it.home.distance_to(pp) > 40.0:
				it.gone_until = 0.0
				it.node.visible = true
			continue
		if it.expires > 0.0 and t > it.expires:
			it.node.queue_free()
			items.remove_at(i)
			continue
		it.spin += delta * 1.8
		it.node.rotation.y = it.spin
		it.node.position.y = it.home.y + 0.45 + sin(it.spin * 1.3) * 0.08
		if not p.alive or p.state == Player.St.DEAD:
			continue
		var reach := 1.4 if p.vehicle == null else 2.6
		if it.node.global_position.distance_squared_to(pp) < reach * reach:
			if _collect(it, p):
				if it.fixed:
					it.gone_until = t + RESPAWN
					it.node.visible = false
				else:
					it.node.queue_free()
					items.remove_at(i)

func _collect(it: Item, p: Player) -> bool:
	match it.kind:
		"cash":
			Game.add_cash(it.amount)
			Game.notify("+$%d" % it.amount, "money")
		"treasure":
			Game.add_cash(it.amount)
			Game.notify("Sunken treasure! +$%d" % it.amount, "money")
			Audio.play_ui(&"ui_treasure", -4.0)
		"health":
			if p.health >= p.max_health - 0.5:
				return false
			p.heal(float(it.amount))
			Audio.play_ui(&"ui_heal", -6.0)
		"armor":
			if p.armor >= float(it.amount) - 0.5:
				return false
			p.armor = maxf(p.armor, float(it.amount))
			Audio.play_ui(&"ui_armor", -6.0)
		"parachute":
			if p.inventory.has_parachute:
				return false
			p.inventory.has_parachute = true
			Game.notify("Parachute picked up", "good")
		"weapon":
			var wid := StringName(it.id)
			var had := p.inventory.has(wid)
			if had and p.inventory.reserve(wid) >= int(WeaponDB.get_w(wid).get("reserve", 0)) and WeaponDB.is_gun(wid):
				return false
			if had and not WeaponDB.is_gun(wid) and WeaponDB.get_w(wid)["cls"] != &"thrown":
				return false
			p.inventory.give(wid, it.amount if it.amount > 0 else -1)
			Game.notify(("%s ammo" if had else "Picked up %s") % String(WeaponDB.get_w(wid)["name"]), "good")
			Audio.play_ui(&"ui_ammo", -6.0)
	return true

func count() -> int:
	return items.size()
