extends RefCounted
## Shared numbers of the garage system (Economy B): stat bars recomputed from VehicleSpec + mods,
## vehicle condition, repair / service prices, the paint palette and rental fees.
## Pure functions over plain data; vehicles and specs are read by duck typing (no class types of
## the vehicle module). Loaded by path:
##     const Stats := preload("res://gta/code/world/shops/garage_stats.gd")

const STAT_KEYS: Array[String] = ["top_speed", "acceleration", "braking", "handling", "durability"]
const STAT_NAMES := {
	"top_speed": "Top speed", "acceleration": "Acceleration", "braking": "Braking",
	"handling": "Handling", "durability": "Durability",
}
## Same baseline / accumulation rule as VehicleMods.DEFAULT_STATS (multipliers except ADDITIVE).
const DEFAULT_STATS := {
	"power": 1.0, "drive": 1.0, "top_speed": 1.0, "brake": 1.0, "grip": 1.0, "stiffness": 1.0,
	"anti_roll": 1.0, "shift_time": 1.0, "damage_taken": 1.0,
	"ride_drop": 0.0, "mass_add": 0.0, "downforce_add": 0.0, "bulletproof_tires": false,
}
const ADDITIVE: Array[String] = ["ride_drop", "mass_add", "downforce_add"]
## Bar scales (value that fills a bar): m/s, kW per tonne, g, g, effective hp.
const SCALE := {"top_speed": 64.0, "acceleration": 440.0, "braking": 1.45, "handling": 1.9, "durability": 4600.0}

const PRIMARY_PRICE := 450
const SECONDARY_PRICE := 300
const PALETTE: Array[Dictionary] = [
	{"name": "Coral Red", "color": Color("#D8342C")},
	{"name": "Harbor Blue", "color": Color("#2C6FD9")},
	{"name": "Sun Yellow", "color": Color("#F2C331")},
	{"name": "Pearl White", "color": Color("#F1F1EE")},
	{"name": "Midnight Black", "color": Color("#1B1D22")},
	{"name": "Silver", "color": Color("#BFC5CC")},
	{"name": "Graphite", "color": Color("#4A4F57")},
	{"name": "Palm Green", "color": Color("#2F9E5C")},
	{"name": "Lime", "color": Color("#9BD13A")},
	{"name": "Sunset Orange", "color": Color("#F0802F")},
	{"name": "Lagoon Teal", "color": Color("#1FA7A0")},
	{"name": "Deep Navy", "color": Color("#27405F")},
	{"name": "Violet", "color": Color("#7A50D0")},
	{"name": "Bubblegum", "color": Color("#E86FA8")},
	{"name": "Burgundy", "color": Color("#7A1F2B")},
	{"name": "Dune Sand", "color": Color("#D9C39A")},
]


## "$12,400" (own formatter so non-UI code needs no UI class).
static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-$" if n < 0 else "$") + s + out


static func is_free() -> bool:
	return bool(Game.flags.get("free_shopping", false))


## Price after the admin "unlock all" flag.
static func price(p: int) -> int:
	return 0 if is_free() else maxi(p, 0)


static func mod_def(mod_id: String) -> Dictionary:
	var d: Variant = Registry.get_def("vehicle_mods", mod_id)
	return d if d is Dictionary else {}


static func mod_price(mod_id: String) -> int:
	return price(int(mod_def(mod_id).get("price", 0)))


## Accumulated mod effects of a slot -> mod id dictionary (same rule as the vehicle module).
static func accumulate(mods: Dictionary) -> Dictionary:
	var st := DEFAULT_STATS.duplicate()
	for slot: Variant in mods:
		var def := mod_def(str(mods[slot]))
		var fx: Variant = def.get("effects", {})
		if not (fx is Dictionary):
			continue
		for k: String in fx:
			if not st.has(k):
				continue
			if st[k] is bool:
				st[k] = bool(fx[k])
			elif ADDITIVE.has(k):
				st[k] = float(st[k]) + float(fx[k])
			else:
				st[k] = float(st[k]) * float(fx[k])
	return st


## Safe bool property read across module boundaries (missing / null -> false).
static func flag(obj: Object, prop: String) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	var v: Variant = obj.get(prop)
	return v is bool and v


static func text(obj: Object, prop: String, fallback: String = "") -> String:
	if obj == null or not is_instance_valid(obj):
		return fallback
	var v: Variant = obj.get(prop)
	return str(v) if (v is String or v is StringName) else fallback


static func _f(obj: Object, prop: String, fallback: float) -> float:
	if obj == null:
		return fallback
	var v: Variant = obj.get(prop)
	if v is float or v is int:
		return float(v)
	return fallback


## Stat bars for a spec (VehicleSpec or anything with its fields) with `mods` installed.
## Returns key -> {"value": float, "frac": 0..1, "text": String} for STAT_KEYS, plus "flags".
static func stats_for(spec: Object, mods: Dictionary) -> Dictionary:
	var a := accumulate(mods)
	var out := {}
	var power := float(a["power"])
	var mass := _f(spec, "mass", 1400.0) + float(a["mass_add"])
	var top := _f(spec, "top_speed", 45.0) * float(a["top_speed"]) * pow(power, 0.33)
	out["top_speed"] = {"value": top, "frac": clampf(top / float(SCALE["top_speed"]), 0.0, 1.0), "text": "%d km/h" % roundi(top * 3.6)}
	# power to weight; quicker shifts add a little (less time without drive)
	var pw := _f(spec, "engine_power", 130.0) * power * float(a["drive"]) / maxf(mass / 1000.0, 0.2)
	pw *= 1.0 + 0.18 * (1.0 - float(a["shift_time"]))
	out["acceleration"] = {"value": pw, "frac": clampf(pw / float(SCALE["acceleration"]), 0.0, 1.0), "text": "%d kW/t" % roundi(pw)}
	var grip := (_f(spec, "grip_front", 1.08) + _f(spec, "grip_rear", 1.08)) * 0.5 * float(a["grip"])
	var brake_g := minf(_f(spec, "brake_force", 11000.0) * float(a["brake"]) / maxf(mass, 100.0) / 9.81, grip * 1.05)
	out["braking"] = {"value": brake_g, "frac": clampf(brake_g / float(SCALE["braking"]), 0.0, 1.0), "text": "%.2f g" % brake_g}
	var df := (_f(spec, "downforce", 0.25) + float(a["downforce_add"])) * 900.0 / maxf(mass * 9.81, 1.0)
	var lat := grip * (1.0 + df) * (1.0 + 0.05 * (float(a["anti_roll"]) - 1.0))
	out["handling"] = {"value": lat, "frac": clampf(lat / float(SCALE["handling"]), 0.0, 1.0), "text": "%.2f g" % lat}
	var hp := _f(spec, "max_health", 1000.0) / maxf(float(a["damage_taken"]), 0.05)
	out["durability"] = {"value": hp, "frac": clampf(hp / float(SCALE["durability"]), 0.0, 1.0), "text": "%d hp" % roundi(hp)}
	out["flags"] = {"bulletproof_tires": bool(a["bulletproof_tires"]), "ride_drop": float(a["ride_drop"])}
	return out


static func spec_of(vehicle: Object) -> Object:
	if vehicle == null or not is_instance_valid(vehicle):
		return null
	var s: Variant = vehicle.get("spec")
	if s is Object:
		return s
	var id: Variant = vehicle.get("spec_id")
	if id is String:
		var d: Variant = Registry.get_def("vehicles", id)
		if d is Object:
			return d
	return null


static func display_name(spec_id: String) -> String:
	var d: Variant = Registry.get_def("vehicles", spec_id)
	if d is Object:
		var n: Variant = (d as Object).get("display_name")
		if n is String and n != "":
			return n
	return spec_id.capitalize()


static func vehicle_name(vehicle: Object) -> String:
	if vehicle == null or not is_instance_valid(vehicle):
		return "Vehicle"
	return display_name(str(vehicle.get("spec_id")))


# ---------------------------------------------------------------------------------------------
# condition + repair prices
# ---------------------------------------------------------------------------------------------

## {"health": 0..1, "hp": float, "max_hp": float, "glass_total", "glass_broken", "tyres_total",
##  "tyres_flat", "power": 0..1 (engine output from damage), "pull": steering pull, "destroyed"}
static func condition(vehicle: Object) -> Dictionary:
	var c := {"health": 1.0, "hp": 0.0, "max_hp": 1.0, "glass_total": 0, "glass_broken": 0, "tyres_total": 0,
			"tyres_flat": 0, "power": 1.0, "pull": 0.0, "destroyed": false}
	if vehicle == null or not is_instance_valid(vehicle):
		return c
	var hp := _f(vehicle, "health", 1000.0)
	var mx := maxf(_f(vehicle, "max_health", 1000.0), 1.0)
	c["hp"] = hp
	c["max_hp"] = mx
	c["health"] = clampf(hp / mx, 0.0, 1.0)
	c["destroyed"] = bool(vehicle.get("destroyed")) if vehicle.get("destroyed") != null else false
	if vehicle.has_method("get_power_factor"):
		c["power"] = float(vehicle.call("get_power_factor"))
	var dmg: Variant = vehicle.get("damage")
	if dmg is Object and is_instance_valid(dmg):
		var panes: Variant = (dmg as Object).get("panes")
		if panes is Array:
			c["glass_total"] = (panes as Array).size()
		if (dmg as Object).has_method("get_broken_glass_count"):
			c["glass_broken"] = int((dmg as Object).call("get_broken_glass_count"))
		c["pull"] = absf(_f(dmg as Object, "steer_pull", 0.0))
	if vehicle.has_method("get_wheel_count"):
		var n := int(vehicle.call("get_wheel_count"))
		c["tyres_total"] = n
		var flat := 0
		if vehicle.has_method("is_tire_flat"):
			for i in n:
				if bool(vehicle.call("is_tire_flat", i)):
					flat += 1
		c["tyres_flat"] = flat
	return c


static func needs_repair(c: Dictionary) -> bool:
	return float(c["health"]) < 0.999 or int(c["glass_broken"]) > 0 or int(c["tyres_flat"]) > 0


## Full repair at Torque Garage: by missing health, broken panes and flat tyres.
static func repair_cost(vehicle: Object) -> int:
	var c := condition(vehicle)
	if not needs_repair(c):
		return 0
	var cost := (float(c["max_hp"]) - float(c["hp"])) * 0.8 + float(c["glass_broken"]) * 90.0 + float(c["tyres_flat"]) * 140.0
	return price(maxi(60, int(roundf(cost / 10.0)) * 10))


const SERVICE_HEALTH := 0.75      ## gas-station quick service patches the engine up to this


static func needs_service(c: Dictionary) -> bool:
	return float(c["health"]) < SERVICE_HEALTH - 0.005 or int(c["tyres_flat"]) > 0


## Gas-station quick service: tyres + patch to SERVICE_HEALTH, much cheaper than a full repair.
static func service_cost(vehicle: Object) -> int:
	var c := condition(vehicle)
	if not needs_service(c):
		return 0
	var missing := maxf(float(c["max_hp"]) * SERVICE_HEALTH - float(c["hp"]), 0.0)
	var cost := 35.0 + missing * 0.35 + float(c["tyres_flat"]) * 45.0
	return price(int(roundf(cost / 5.0)) * 5)


## Rental fee of the vehicle access terminals (free with "free_shopping").
static func rental_fee(spec_id: String) -> int:
	var d: Variant = Registry.get_def("vehicles", spec_id)
	var p := 0
	if d is Object:
		p = int(_f(d as Object, "price", 0.0))
	var fee := 400 if p <= 0 else clampi(int(roundf(float(p) * 0.015 / 10.0)) * 10, 150, 2500)
	return price(fee)


static func palette_name(c: Color) -> String:
	for e: Dictionary in PALETTE:
		if (e["color"] as Color).is_equal_approx(Color(c.r, c.g, c.b, 1.0)):
			return str(e["name"])
	return "Custom"


static func same_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
