class_name VehicleDB
extends RefCounted
## Data-driven vehicle definitions. Handling numbers are tuned for an arcade-realistic feel.
## `dims` (length, width, height) is only used for the generated stand-in when a model has
## not been exported yet; real geometry (wheels, seats, colliders) comes from the GLB.

const PAINTS := ["c9302a", "2f6fd0", "f2f0ea", "17181b", "8b8e93", "f2c230", "2aa59a", "3fa55a", "ef7f2d", "7a48c2",
	"22407f", "8f2a25", "c9a97f", "55585e", "d0409a", "3ec3e0", "6b7a3a", "e3dfd4", "7a5236", "1c2748"]

const V := {
	# ------------------------------------------------------------------ cars
	"car_sedan": {"name": "Meridian", "kind": &"car", "cls": "sedan", "dims": Vector3(4.7, 1.86, 1.46), "mass": 1450.0,
		"power": 9200.0, "top": 46.0, "brake": 16000.0, "grip": 1.9, "steer": 34.0, "drive": "fwd", "susp": 0.26, "stiff": 1.0,
		"health": 1000.0, "sound": &"engine_sedan_loop", "price": 18000, "traffic": 10, "cam": 6.2},
	"car_compact": {"name": "Pico", "kind": &"car", "cls": "compact", "dims": Vector3(3.75, 1.68, 1.5), "mass": 1050.0,
		"power": 6400.0, "top": 40.0, "brake": 12500.0, "grip": 1.85, "steer": 37.0, "drive": "fwd", "susp": 0.24, "stiff": 1.0,
		"health": 850.0, "sound": &"engine_small_loop", "price": 9000, "traffic": 9, "cam": 5.6},
	"car_sports": {"name": "Vanta GT", "kind": &"car", "cls": "sports", "dims": Vector3(4.45, 1.96, 1.22), "mass": 1350.0,
		"power": 15500.0, "top": 68.0, "brake": 21000.0, "grip": 2.35, "steer": 32.0, "drive": "rwd", "susp": 0.2, "stiff": 1.35,
		"health": 900.0, "sound": &"engine_sport_loop", "price": 95000, "traffic": 2, "cam": 6.0, "downforce": 2.2},
	"car_muscle": {"name": "Brawler", "kind": &"car", "cls": "muscle", "dims": Vector3(4.95, 1.96, 1.36), "mass": 1650.0,
		"power": 16500.0, "top": 60.0, "brake": 17500.0, "grip": 1.95, "steer": 32.0, "drive": "rwd", "susp": 0.25, "stiff": 1.05,
		"health": 1100.0, "sound": &"engine_muscle_loop", "price": 52000, "traffic": 3, "cam": 6.4},
	"car_suv": {"name": "Ridgeback", "kind": &"car", "cls": "suv", "dims": Vector3(4.85, 2.02, 1.86), "mass": 2100.0,
		"power": 12500.0, "top": 46.0, "brake": 20000.0, "grip": 1.8, "steer": 33.0, "drive": "awd", "susp": 0.34, "stiff": 0.9,
		"health": 1350.0, "sound": &"engine_sedan_loop", "price": 42000, "traffic": 6, "cam": 6.8},
	"car_pickup": {"name": "Mule", "kind": &"car", "cls": "pickup", "dims": Vector3(5.4, 2.02, 1.86), "mass": 2000.0,
		"power": 11500.0, "top": 44.0, "brake": 19000.0, "grip": 1.75, "steer": 33.0, "drive": "rwd", "susp": 0.36, "stiff": 0.9,
		"health": 1300.0, "sound": &"engine_truck_loop", "price": 30000, "traffic": 5, "cam": 7.0},
	"car_van": {"name": "Hauler", "kind": &"car", "cls": "van", "dims": Vector3(5.2, 2.04, 2.25), "mass": 2300.0,
		"power": 10500.0, "top": 38.0, "brake": 19000.0, "grip": 1.65, "steer": 33.0, "drive": "rwd", "susp": 0.3, "stiff": 1.0,
		"health": 1400.0, "sound": &"engine_truck_loop", "price": 26000, "traffic": 4, "cam": 7.4},
	"car_police": {"name": "Interceptor", "kind": &"car", "cls": "police", "dims": Vector3(4.95, 1.92, 1.5), "mass": 1700.0,
		"power": 16000.0, "top": 60.0, "brake": 22000.0, "grip": 2.15, "steer": 33.0, "drive": "rwd", "susp": 0.25, "stiff": 1.15,
		"health": 1500.0, "sound": &"engine_muscle_loop", "price": 0, "traffic": 0, "cam": 6.4, "siren": &"siren_police_loop",
		"paint": ["17181b", "f2f0ea"], "emergency": true},
	"car_taxi": {"name": "ZipCab", "kind": &"car", "cls": "taxi", "dims": Vector3(4.6, 1.84, 1.62), "mass": 1500.0,
		"power": 9000.0, "top": 44.0, "brake": 16000.0, "grip": 1.9, "steer": 35.0, "drive": "fwd", "susp": 0.26, "stiff": 1.0,
		"health": 1000.0, "sound": &"engine_sedan_loop", "price": 0, "traffic": 3, "cam": 6.2, "paint": ["f5c518", "17181b"]},
	"car_ambulance": {"name": "Lifeline", "kind": &"car", "cls": "ambulance", "dims": Vector3(6.2, 2.2, 2.75), "mass": 3200.0,
		"power": 15000.0, "top": 42.0, "brake": 26000.0, "grip": 1.7, "steer": 32.0, "drive": "rwd", "susp": 0.32, "stiff": 1.0,
		"health": 1700.0, "sound": &"engine_truck_loop", "price": 0, "traffic": 0, "cam": 8.4, "siren": &"siren_ambulance_loop",
		"paint": ["f4f4f2", "ef7f2d"], "emergency": true},
	"car_firetruck": {"name": "Blazeguard", "kind": &"car", "cls": "firetruck", "dims": Vector3(8.6, 2.5, 3.2), "mass": 7500.0,
		"power": 30000.0, "top": 34.0, "brake": 52000.0, "grip": 1.6, "steer": 30.0, "drive": "rwd", "susp": 0.34, "stiff": 1.1,
		"health": 2600.0, "sound": &"engine_truck_loop", "price": 0, "traffic": 0, "cam": 11.0, "siren": &"siren_fire_loop",
		"paint": ["c81e1e", "f2f0ea"], "emergency": true},
	"car_truck": {"name": "Packmaster", "kind": &"car", "cls": "truck", "dims": Vector3(7.4, 2.4, 3.3), "mass": 5200.0,
		"power": 20000.0, "top": 32.0, "brake": 38000.0, "grip": 1.6, "steer": 30.0, "drive": "rwd", "susp": 0.34, "stiff": 1.1,
		"health": 2200.0, "sound": &"engine_truck_loop", "price": 38000, "traffic": 2, "cam": 10.0},
	"car_swat": {"name": "Bulwark", "kind": &"car", "cls": "swat", "dims": Vector3(6.4, 2.4, 2.7), "mass": 5600.0,
		"power": 27000.0, "top": 40.0, "brake": 42000.0, "grip": 1.75, "steer": 30.0, "drive": "awd", "susp": 0.34, "stiff": 1.15,
		"health": 3600.0, "sound": &"engine_truck_loop", "price": 0, "traffic": 0, "cam": 9.0, "siren": &"siren_police_yelp_loop",
		"paint": ["1c2748", "17181b"], "emergency": true, "bulletproof_tires": true},
	# ------------------------------------------------------------------ two wheels
	"bike_sport": {"name": "Wasp 600", "kind": &"bike", "cls": "motorcycle", "dims": Vector3(2.05, 0.75, 1.2), "mass": 260.0,
		"power": 2900.0, "top": 62.0, "brake": 5200.0, "grip": 2.3, "steer": 32.0, "drive": "rwd", "susp": 0.2, "stiff": 1.2,
		"health": 500.0, "sound": &"engine_bike_loop", "price": 14000, "traffic": 2, "cam": 4.6},
	"bicycle": {"name": "BMX", "kind": &"bike", "cls": "bicycle", "dims": Vector3(1.7, 0.6, 1.05), "mass": 150.0,
		"power": 900.0, "top": 13.0, "brake": 2600.0, "grip": 2.0, "steer": 38.0, "drive": "rwd", "susp": 0.16, "stiff": 1.2,
		"health": 260.0, "sound": &"", "price": 400, "traffic": 0, "cam": 4.2, "pedal": true},
	# ------------------------------------------------------------------ water
	"boat_speed": {"name": "Marlin", "kind": &"boat", "cls": "boat", "dims": Vector3(7.4, 2.5, 1.9), "mass": 1500.0,
		"power": 21000.0, "top": 30.0, "health": 1000.0, "sound": &"engine_boat_loop", "price": 60000, "cam": 9.0},
	"boat_dinghy": {"name": "Skiff", "kind": &"boat", "cls": "boat", "dims": Vector3(3.4, 1.6, 0.9), "mass": 420.0,
		"power": 5200.0, "top": 19.0, "health": 500.0, "sound": &"engine_boat_loop", "price": 8000, "cam": 6.0},
	"boat_police": {"name": "Harbor Patrol", "kind": &"boat", "cls": "boat", "dims": Vector3(8.2, 2.8, 2.6), "mass": 2400.0,
		"power": 30000.0, "top": 28.0, "health": 1600.0, "sound": &"engine_boat_loop", "price": 0, "cam": 10.0,
		"siren": &"siren_police_loop", "paint": ["f2f0ea", "1f3f8f"], "emergency": true},
	# ------------------------------------------------------------------ air
	"heli_civil": {"name": "Dragonfly", "kind": &"heli", "cls": "heli", "dims": Vector3(9.6, 1.7, 3.1), "mass": 1300.0,
		"power": 1.0, "top": 52.0, "health": 1000.0, "sound": &"heli_rotor_loop", "price": 220000, "cam": 13.0},
	"heli_police": {"name": "Skywatch", "kind": &"heli", "cls": "heli", "dims": Vector3(11.2, 1.9, 3.4), "mass": 1900.0,
		"power": 1.1, "top": 56.0, "health": 1500.0, "sound": &"heli_rotor_loop", "price": 0, "cam": 14.5,
		"paint": ["17181b", "f2f0ea"], "emergency": true},
	"plane_prop": {"name": "Kestrel", "kind": &"plane", "cls": "plane", "dims": Vector3(8.3, 10.8, 2.9), "mass": 1100.0,
		"power": 9500.0, "top": 62.0, "stall": 21.0, "health": 800.0, "sound": &"plane_prop_loop", "price": 180000, "cam": 14.0},
	"plane_jet": {"name": "Arrow", "kind": &"plane", "cls": "plane", "dims": Vector3(12.2, 10.4, 3.6), "mass": 3800.0,
		"power": 52000.0, "top": 115.0, "stall": 34.0, "health": 1100.0, "sound": &"jet_loop", "price": 900000, "cam": 19.0},
}

## Spawn groups used by the admin menu / garages.
const GROUPS := {
	"Cars": ["car_compact", "car_sedan", "car_sports", "car_muscle", "car_suv", "car_pickup", "car_van", "car_taxi"],
	"Service": ["car_police", "car_ambulance", "car_firetruck", "car_truck", "car_swat"],
	"Bikes": ["bike_sport", "bicycle"],
	"Boats": ["boat_speed", "boat_dinghy", "boat_police"],
	"Aircraft": ["heli_civil", "heli_police", "plane_prop", "plane_jet"],
}

static func get_v(id: String) -> Dictionary:
	return V.get(id, {})

static func exists(id: String) -> bool:
	return V.has(id)

static func has_model(id: String) -> bool:
	return Assets.has_model("vehicles/" + id)

## Vehicles that may appear in civilian traffic, weighted, only if their model exists
## (falls back to any defined car so traffic never disappears).
static func traffic_pool() -> Array:
	var out: Array = []
	for id in V.keys():
		var d: Dictionary = V[id]
		if int(d.get("traffic", 0)) > 0 and d.get("kind", &"car") == &"car" and has_model(id):
			for i in int(d["traffic"]):
				out.append(id)
	if out.is_empty():
		out = ["car_sedan"]
	return out

static func random_paint(rng: RandomNumberGenerator) -> Color:
	return Color.html(PAINTS[rng.randi() % PAINTS.size()])
