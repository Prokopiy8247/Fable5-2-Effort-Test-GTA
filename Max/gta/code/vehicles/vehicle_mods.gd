class_name VehicleMods
extends RefCounted
## Data-driven vehicle upgrades (Torque House Customs). Performance parts change the real
## handling numbers; body parts are Blender-authored meshes mounted on the car's mod markers.

const FINISHES := {
	"gloss": Vector4(0.3, 0.3, 0.7, 0.0), "matte": Vector4(0.88, 0.05, 0.0, 0.0), "metallic": Vector4(0.22, 0.85, 0.8, 0.0),
	"pearl": Vector4(0.25, 0.5, 0.95, 1.0), "chrome": Vector4(0.05, 1.0, 1.0, 0.0),
}
const NEON := {"off": Color(0, 0, 0), "cyan": Color(0.1, 0.9, 1.0), "pink": Color(1.0, 0.2, 0.7), "green": Color(0.2, 1.0, 0.4),
	"purple": Color(0.6, 0.3, 1.0), "orange": Color(1.0, 0.5, 0.1), "white": Color(1, 1, 1)}
const HEADLIGHTS := {"stock": Color(1.0, 0.95, 0.85), "xenon": Color(0.8, 0.9, 1.0), "amber": Color(1.0, 0.75, 0.35), "blue": Color(0.5, 0.65, 1.0)}

## category -> {name, type ("level" | "part" | "choice"), prices / options, marker}
const CATS := {
	"engine": {"name": "Engine Tune", "type": "level", "prices": [0, 2500, 6000, 12000, 20000], "group": "Performance"},
	"transmission": {"name": "Transmission", "type": "level", "prices": [0, 2000, 5500, 10000], "group": "Performance"},
	"turbo": {"name": "Turbo", "type": "level", "prices": [0, 15000], "group": "Performance"},
	"brakes": {"name": "Brakes", "type": "level", "prices": [0, 1500, 4000, 8000], "group": "Performance"},
	"suspension": {"name": "Suspension", "type": "level", "prices": [0, 1200, 3000, 6500], "group": "Performance"},
	"armor": {"name": "Armor", "type": "level", "prices": [0, 3000, 7500, 14000, 22000, 32000], "group": "Performance"},
	"bp_tires": {"name": "Bullet-resistant Tyres", "type": "level", "prices": [0, 9000], "group": "Performance"},
	"spoiler": {"name": "Spoiler", "type": "part", "options": ["", "spoiler_lip", "spoiler_wing", "spoiler_gt"], "prices": [0, 1800, 3500, 6000], "marker": "mod_spoiler", "group": "Body"},
	"hood": {"name": "Hood", "type": "part", "options": ["", "hood_scoop", "hood_vents"], "prices": [0, 1500, 1900], "marker": "mod_hood", "group": "Body"},
	"roof": {"name": "Roof", "type": "part", "options": ["", "roof_scoop", "roof_rack"], "prices": [0, 1400, 1100], "marker": "mod_roof", "group": "Body"},
	"front": {"name": "Front Bumper", "type": "part", "options": ["", "bumper_splitter", "bumper_bullbar"], "prices": [0, 2200, 2600], "marker": "mod_front", "group": "Body"},
	"rear": {"name": "Rear Bumper", "type": "part", "options": ["", "bumper_diffuser"], "prices": [0, 2400], "marker": "mod_rear", "group": "Body"},
	"skirts": {"name": "Skirts", "type": "part", "options": ["", "skirt_sport"], "prices": [0, 1700], "marker": "mod_skirt_l", "group": "Body"},
	"exhaust": {"name": "Exhaust", "type": "part", "options": ["", "exhaust_dual", "exhaust_big"], "prices": [0, 900, 1300], "marker": "exhaust", "group": "Body"},
	"wheels": {"name": "Wheels", "type": "part", "options": ["", "rim_steel", "rim_sport5", "rim_deep", "rim_offroad", "rim_classic"], "prices": [0, 800, 2500, 3600, 2800, 3200], "marker": "", "group": "Wheels"},
	"wheel_color": {"name": "Wheel Colour", "type": "choice", "options": ["c3c7cb", "17181b", "d9a520", "c9302a", "2f6fd0", "f2f0ea", "f08ab8"], "price": 600, "group": "Wheels"},
	"paint": {"name": "Primary Paint", "type": "choice", "options": VehicleDB.PAINTS, "price": 900, "group": "Paint"},
	"paint2": {"name": "Secondary Paint", "type": "choice", "options": VehicleDB.PAINTS, "price": 600, "group": "Paint"},
	"finish": {"name": "Finish", "type": "choice", "options": ["gloss", "matte", "metallic", "pearl", "chrome"], "price": 1500, "group": "Paint"},
	"tint": {"name": "Window Tint", "type": "level", "prices": [0, 500, 900, 1500], "group": "Paint"},
	"neon": {"name": "Underglow", "type": "choice", "options": ["off", "cyan", "pink", "green", "purple", "orange", "white"], "price": 2200, "group": "Lights"},
	"lights": {"name": "Headlights", "type": "choice", "options": ["stock", "xenon", "amber", "blue"], "price": 700, "group": "Lights"},
	"horn": {"name": "Horn", "type": "choice", "options": ["stock", "truck", "bike", "bell"], "price": 300, "group": "Lights"},
	"plate": {"name": "Plate Style", "type": "choice", "options": ["white", "yellow", "black", "blue"], "price": 200, "group": "Lights"},
}
const ORDER := ["engine", "transmission", "turbo", "brakes", "suspension", "armor", "bp_tires", "spoiler", "hood", "roof", "front",
	"rear", "skirts", "exhaust", "wheels", "wheel_color", "paint", "paint2", "finish", "tint", "neon", "lights", "horn", "plate"]

static func compatible(v: Vehicle) -> bool:
	return v is Car and not (v is Airplane) and not v.destroyed

static func price(cat: String, value: Variant) -> int:
	var c: Dictionary = CATS[cat]
	if Game.cheats["unlock_all_mods"] or Game.cheats["free_shopping"]:
		return 0
	match String(c["type"]):
		"level":
			return int((c["prices"] as Array)[clampi(int(value), 0, (c["prices"] as Array).size() - 1)])
		"part":
			var i := (c["options"] as Array).find(String(value))
			return int((c["prices"] as Array)[maxi(i, 0)])
	return int(c.get("price", 0))

static func available(v: Vehicle, cat: String, value: Variant) -> bool:
	var c: Dictionary = CATS[cat]
	if String(c["type"]) == "part" and String(value) != "":
		if not Assets.has_model("vehicles/parts/" + String(value)):
			return false
		if cat != "wheels" and v.part(String(c["marker"])) == null:
			return false
		if (v as Car).two_wheel and cat != "exhaust":
			return false
	return true

static func apply_all(v: Vehicle, mods: Dictionary) -> void:
	for cat in ORDER:
		if mods.has(cat):
			apply(v, cat, mods[cat])

static func apply(v: Vehicle, cat: String, value: Variant) -> void:
	if not CATS.has(cat) or not (v is Car):
		return
	var car := v as Car
	car.mods[cat] = value
	match cat:
		"engine", "turbo", "transmission":
			car.power_scale = 1.0 + 0.085 * float(car.mods.get("engine", 0)) + 0.2 * float(car.mods.get("turbo", 0)) + 0.045 * float(car.mods.get("transmission", 0))
		"brakes":
			car.brake_scale = 1.0 + 0.17 * float(value)
		"suspension":
			var lvl := float(value)
			car._rest = float(car.def.get("susp", 0.26)) * (1.0 - 0.1 * lvl)
			var per := car.mass * 9.8 / float(car.wheels.size())
			car._k = per / (car._rest * 0.42) * float(car.def.get("stiff", 1.0)) * (1.0 + 0.12 * lvl)
			car._c = 2.0 * 0.46 * sqrt(car._k * car.mass / float(car.wheels.size()))
			car.grip_scale_mod = 1.0 + 0.03 * lvl
			for w in car.wheels:
				w["attach"] = (w["pos"] as Vector3) + Vector3(0, car._rest * 0.58, 0)
		"armor":
			var ratio := car.health / car.max_health
			car.max_health = float(car.def.get("health", 1000.0)) * (1.0 + 0.22 * float(value))
			car.health = car.max_health * ratio
		"bp_tires":
			pass
		"paint":
			car.set_paint(Color.html(String(value)), car.paint_b)
		"paint2":
			car.set_paint(car.paint_a, Color.html(String(value)))
		"finish":
			car.set_paint(car.paint_a, car.paint_b, FINISHES.get(String(value), FINISHES["gloss"]))
		"tint":
			if car.glass_health > 0.0:
				car.set_glass_tint(car._tint_color())
		"neon":
			_neon(car, NEON.get(String(value), Color(0, 0, 0)))
		"lights":
			for sp in car._headlights:
				sp.light_color = HEADLIGHTS.get(String(value), HEADLIGHTS["stock"])
		"wheel_color":
			for w in car.wheels:
				if w["node"] is MeshInstance3D:
					(w["node"] as MeshInstance3D).set_instance_shader_parameter(&"tint_a", Color.html(String(value)).srgb_to_linear())
		"wheels":
			_wheels(car, String(value))
		"spoiler", "hood", "roof", "front", "rear", "exhaust":
			_mount(car, cat, String(value), false)
			if cat == "spoiler":
				car.mods["spoiler_level"] = (CATS["spoiler"]["options"] as Array).find(String(value))
		"skirts":
			_mount(car, cat, String(value), true)

static func _mount(car: Car, cat: String, part_id: String, mirror: bool) -> void:
	var holder_name := "Mod_" + cat
	var old := car.model.get_node_or_null(holder_name)
	if old:
		old.name = holder_name + "_old"
		old.queue_free()
	if part_id == "" or not Assets.has_model("vehicles/parts/" + part_id):
		return
	var marker := car.part(String(CATS[cat]["marker"]))
	if marker == null:
		return
	var holder := Node3D.new()
	holder.name = holder_name
	car.model.add_child(holder)
	var base := car._rel_xform(marker)
	var width_scale := clampf(car.half_width * 2.0 / 1.8, 0.75, 1.5)
	var sides := [1.0, -1.0] if mirror else [1.0]
	for sgn in sides:
		var inst := Assets.instance("vehicles/parts/" + part_id)
		holder.add_child(inst)
		var t := base
		if mirror and sgn < 0.0:
			t.origin.x = -t.origin.x
			t.basis = t.basis * Basis.from_scale(Vector3(-1, 1, 1))
		elif not mirror:
			t.basis = t.basis * Basis.from_scale(Vector3(width_scale, 1, 1))
		inst.transform = t
		for mi in Assets.find_meshes(inst):
			car.meshes.append(mi)
	car.meshes = car.meshes.filter(func(m: MeshInstance3D) -> bool: return is_instance_valid(m) and not m.is_queued_for_deletion())
	car.set_paint(car.paint_a, car.paint_b)

static func _wheels(car: Car, rim_id: String) -> void:
	for w in car.wheels:
		var n: Node3D = w["node"]
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if not mi.has_meta("stock_mesh"):
			mi.set_meta("stock_mesh", mi.mesh)
			mi.set_meta("stock_rest", w["rest"])
		if rim_id == "" or not Assets.has_model("vehicles/parts/" + rim_id):
			mi.mesh = mi.get_meta("stock_mesh")
			w["rest"] = mi.get_meta("stock_rest")
			continue
		var m := Assets.mesh("vehicles/parts/" + rim_id)
		if m == null:
			continue
		mi.mesh = m
		var stock: Transform3D = mi.get_meta("stock_rest")
		var s := float(w["radius"]) / 0.5
		w["rest"] = Transform3D(stock.basis.orthonormalized() * Basis.from_scale(Vector3(s, s, s)), stock.origin)

static func _neon(car: Car, col: Color) -> void:
	var old := car.get_node_or_null("Neon")
	if old:
		old.queue_free()
	if col.r + col.g + col.b < 0.05:
		return
	var l := OmniLight3D.new()
	l.name = "Neon"
	l.light_color = col
	l.light_energy = 2.4
	l.omni_range = 4.2
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 50.0
	l.position = Vector3(0, 0.12, 0)
	car.add_child(l)

## Remaining value of installed mods (used when selling / for the garage display).
static func describe(mods: Dictionary) -> String:
	var parts: Array = []
	for cat in ORDER:
		if mods.has(cat) and String(mods[cat]) != "" and String(mods[cat]) != "0" and String(mods[cat]) != "off" and String(mods[cat]) != "stock":
			parts.append(String(CATS[cat]["name"]))
	return ", ".join(parts)
