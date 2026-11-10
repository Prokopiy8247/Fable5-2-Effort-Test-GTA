class_name Defs
# Data-driven registries: vehicles, weapons, upgrades, clothing, buildings, locations.

const ROADS := [-200.0, -120.0, -40.0, 40.0, 120.0]

static func road_w(k: int) -> float:
	return 18.0 if (k == 0 or k == 4) else 12.0

# kind: car / bike / boat / heli / plane.  Dimensions match the Blender sources (tools/blender/*.py).
const VEHICLES := {
	"compact": {"name": "Pip Compact", "model": "car_compact", "kind": "car", "L": 3.7, "W": 1.66, "H": 1.5, "wr": 0.3, "ww": 0.24, "axf": 1.15, "axr": -1.15, "mass": 950.0, "accel": 6.5, "top": 36.0, "grip": 1.0, "health": 700.0, "price": 4000},
	"sedan": {"name": "Meridian Sedan", "model": "car_sedan", "kind": "car", "L": 4.6, "W": 1.8, "H": 1.42, "wr": 0.33, "ww": 0.24, "axf": 1.42, "axr": -1.35, "mass": 1300.0, "accel": 7.0, "top": 42.0, "grip": 1.0, "health": 800.0, "price": 8000},
	"sports": {"name": "Vanta GT", "model": "car_sports", "kind": "car", "L": 4.4, "W": 1.92, "H": 1.14, "wr": 0.34, "ww": 0.3, "axf": 1.42, "axr": -1.32, "mass": 1250.0, "accel": 11.5, "top": 62.0, "grip": 1.25, "health": 750.0, "price": 45000},
	"muscle": {"name": "Brawler 440", "model": "car_muscle", "kind": "car", "L": 4.95, "W": 1.92, "H": 1.32, "wr": 0.36, "ww": 0.3, "axf": 1.6, "axr": -1.42, "mass": 1500.0, "accel": 10.0, "top": 54.0, "grip": 0.95, "health": 900.0, "price": 28000},
	"suv": {"name": "Ridgeback SUV", "model": "car_suv", "kind": "car", "L": 4.7, "W": 1.95, "H": 1.82, "wr": 0.4, "ww": 0.28, "axf": 1.47, "axr": -1.42, "mass": 1900.0, "accel": 6.5, "top": 42.0, "grip": 1.0, "health": 1100.0, "price": 18000},
	"pickup": {"name": "Hauler Pickup", "model": "car_pickup", "kind": "car", "L": 5.3, "W": 1.96, "H": 1.82, "wr": 0.42, "ww": 0.28, "axf": 1.72, "axr": -1.62, "mass": 2000.0, "accel": 6.0, "top": 40.0, "grip": 0.95, "health": 1100.0, "price": 14000},
	"van": {"name": "Cargo Van", "model": "car_van", "kind": "car", "L": 5.0, "W": 1.95, "H": 2.1, "wr": 0.36, "ww": 0.24, "axf": 1.6, "axr": -1.5, "mass": 2100.0, "accel": 5.0, "top": 34.0, "grip": 0.9, "health": 1000.0, "price": 9000},
	"police": {"name": "Police Cruiser", "model": "car_police", "kind": "car", "L": 4.7, "W": 1.84, "H": 1.44, "wr": 0.34, "ww": 0.24, "axf": 1.45, "axr": -1.38, "mass": 1500.0, "accel": 9.5, "top": 54.0, "grip": 1.15, "health": 1000.0, "siren": true, "paint": [0.92, 0.92, 0.94], "paint2": [0.06, 0.06, 0.08], "price": 0},
	"taxi": {"name": "City Taxi", "model": "car_taxi", "kind": "car", "L": 4.6, "W": 1.8, "H": 1.44, "wr": 0.33, "ww": 0.24, "axf": 1.42, "axr": -1.35, "mass": 1350.0, "accel": 7.0, "top": 42.0, "grip": 1.0, "health": 850.0, "paint": [0.95, 0.75, 0.1], "paint2": [0.08, 0.08, 0.08], "price": 0},
	"ambulance": {"name": "Ambulance", "model": "car_ambulance", "kind": "car", "L": 5.8, "W": 2.1, "H": 2.55, "wr": 0.4, "ww": 0.24, "axf": 1.9, "axr": -1.8, "mass": 2600.0, "accel": 6.0, "top": 40.0, "grip": 0.95, "health": 1200.0, "siren": true, "paint": [0.95, 0.95, 0.95], "price": 0},
	"swat": {"name": "Tactical Van", "model": "car_swat", "kind": "car", "L": 5.6, "W": 2.2, "H": 2.4, "wr": 0.48, "ww": 0.34, "axf": 1.8, "axr": -1.7, "mass": 3600.0, "accel": 6.5, "top": 40.0, "grip": 1.0, "health": 2500.0, "siren": true, "paint": [0.08, 0.1, 0.16], "paint2": [0.9, 0.9, 0.9], "price": 0},
	"truck": {"name": "Box Truck", "model": "car_truck", "kind": "car", "L": 7.0, "W": 2.3, "H": 3.3, "wr": 0.5, "ww": 0.34, "axf": 2.6, "axr": -2.2, "mass": 4500.0, "accel": 3.8, "top": 30.0, "grip": 0.9, "health": 1600.0, "price": 0},
	"firetruck": {"name": "Fire Engine", "model": "car_firetruck", "kind": "car", "L": 7.6, "W": 2.4, "H": 2.9, "wr": 0.52, "ww": 0.36, "axf": 2.8, "axr": -2.5, "mass": 6000.0, "accel": 4.5, "top": 34.0, "grip": 0.9, "health": 2200.0, "siren": true, "paint": [0.8, 0.08, 0.06], "price": 0},
	"motorcycle": {"name": "Wraith 600", "model": "bike_motorcycle", "kind": "bike", "L": 2.1, "W": 0.7, "H": 1.1, "wr": 0.32, "ww": 0.14, "axf": 0.74, "axr": -0.72, "mass": 260.0, "accel": 12.0, "top": 58.0, "grip": 1.15, "health": 400.0, "open": true, "price": 12000},
	"bicycle": {"name": "Street Bicycle", "model": "bike_bicycle", "kind": "bike", "L": 1.7, "W": 0.5, "H": 1.0, "wr": 0.34, "ww": 0.05, "axf": 0.54, "axr": -0.52, "mass": 90.0, "accel": 4.0, "top": 12.0, "grip": 1.0, "health": 200.0, "open": true, "pedal": true, "price": 300},
	"speedboat": {"name": "Marlin Speedboat", "model": "boat_speedboat", "kind": "boat", "L": 6.5, "W": 2.3, "H": 1.0, "mass": 1400.0, "accel": 9.0, "top": 30.0, "health": 900.0, "open": true, "price": 20000},
	"heli": {"name": "Skylark Helicopter", "model": "heli_civil", "kind": "heli", "L": 7.6, "W": 1.9, "H": 2.6, "mass": 1400.0, "accel": 10.0, "top": 50.0, "health": 900.0, "paint": [0.85, 0.2, 0.15], "price": 80000},
	"heli_police": {"name": "Police Helicopter", "model": "heli_police", "kind": "heli", "L": 7.8, "W": 2.1, "H": 2.6, "mass": 1500.0, "accel": 10.0, "top": 52.0, "health": 1200.0, "siren": true, "paint": [0.1, 0.12, 0.2], "paint2": [0.9, 0.9, 0.9], "price": 0},
	"plane": {"name": "Finch 170 Prop", "model": "plane_prop", "kind": "plane", "L": 6.6, "W": 2.6, "H": 1.7, "wr": 0.26, "mass": 900.0, "accel": 12.0, "top": 60.0, "stall": 22.0, "health": 700.0, "gear": [[-1.2, 0.3], [1.2, 0.3], [0.0, 2.2]], "body_y": 0.75, "price": 60000},
	"jet": {"name": "Arrow Jet", "model": "plane_jet", "kind": "plane", "L": 9.6, "W": 2.6, "H": 1.5, "wr": 0.26, "mass": 3000.0, "accel": 22.0, "top": 130.0, "stall": 38.0, "health": 1000.0, "gear": [[-1.45, -0.6], [1.45, -0.6], [0.0, 3.2]], "body_y": 0.75, "price": 0},
}
const TRAFFIC_POOL := ["compact", "sedan", "sedan", "suv", "pickup", "van", "muscle", "sports", "taxi", "compact", "truck", "motorcycle"]
const CAR_COLORS := [[0.8, 0.1, 0.1], [0.1, 0.25, 0.7], [0.9, 0.9, 0.9], [0.08, 0.08, 0.09], [0.55, 0.57, 0.6], [0.95, 0.75, 0.1], [0.1, 0.5, 0.25], [0.9, 0.4, 0.05], [0.4, 0.1, 0.5], [0.3, 0.6, 0.75], [0.5, 0.3, 0.15], [0.85, 0.8, 0.65]]
const PAINT_NAMES := ["Red", "Blue", "White", "Black", "Silver", "Yellow", "Green", "Orange", "Purple", "Sky", "Bronze", "Cream"]

# slot = weapon wheel sector. proj: "" hitscan / "grenade" / "rocket". onehand => usable in drive-by.
const WEAPONS := {
	"fists": {"name": "Fists", "model": "", "slot": 0, "melee": true, "dmg": 14.0, "rate": 2.2, "range": 1.7, "price": 0},
	"knife": {"name": "Combat Knife", "model": "wpn_knife", "slot": 0, "melee": true, "dmg": 45.0, "rate": 2.5, "range": 1.8, "price": 150},
	"bat": {"name": "Ash Bat", "model": "wpn_bat", "slot": 0, "melee": true, "dmg": 38.0, "rate": 1.5, "range": 2.2, "price": 100, "knock": true},
	"pistol": {"name": "P9 Pistol", "model": "wpn_pistol", "slot": 1, "dmg": 24.0, "rate": 5.0, "mag": 12, "max": 240, "reload": 1.2, "spread": 1.2, "recoil": 0.9, "range": 90.0, "onehand": true, "snd": "shot_pistol", "price": 400, "ammo": 40, "atts": ["suppressor", "flashlight", "extmag", "scope"]},
	"revolver": {"name": "Ridge .44 Revolver", "model": "wpn_revolver", "slot": 1, "dmg": 62.0, "rate": 1.8, "mag": 6, "max": 96, "reload": 2.0, "spread": 0.8, "recoil": 2.6, "range": 110.0, "onehand": true, "snd": "shot_heavy", "price": 1200, "ammo": 80, "atts": []},
	"smg": {"name": "Hornet SMG", "model": "wpn_smg", "slot": 2, "dmg": 17.0, "rate": 13.0, "mag": 30, "max": 600, "reload": 1.6, "spread": 2.2, "recoil": 0.7, "range": 70.0, "auto": true, "onehand": true, "snd": "shot_smg", "price": 1800, "ammo": 60, "atts": ["suppressor", "flashlight", "extmag", "scope", "grip"]},
	"shotgun": {"name": "Pump Shotgun", "model": "wpn_shotgun", "slot": 3, "dmg": 14.0, "pellets": 9, "rate": 1.3, "mag": 8, "max": 120, "reload": 2.4, "spread": 5.5, "recoil": 3.2, "range": 35.0, "snd": "shot_shotgun", "price": 1500, "ammo": 60, "atts": ["flashlight", "suppressor"]},
	"rifle": {"name": "AR-7 Assault Rifle", "model": "wpn_rifle", "slot": 4, "dmg": 28.0, "rate": 10.0, "mag": 30, "max": 600, "reload": 1.9, "spread": 1.3, "recoil": 1.0, "range": 140.0, "auto": true, "snd": "shot_rifle", "price": 3500, "ammo": 90, "atts": ["suppressor", "flashlight", "extmag", "scope", "grip"]},
	"carbine": {"name": "Kestrel Carbine", "model": "wpn_carbine", "slot": 4, "dmg": 25.0, "rate": 11.5, "mag": 30, "max": 600, "reload": 1.7, "spread": 1.5, "recoil": 0.85, "range": 120.0, "auto": true, "snd": "shot_rifle", "price": 4200, "ammo": 90, "atts": ["suppressor", "flashlight", "extmag", "scope", "grip"]},
	"marksman": {"name": "Longfield Marksman", "model": "wpn_marksman", "slot": 5, "dmg": 70.0, "rate": 2.5, "mag": 10, "max": 120, "reload": 2.2, "spread": 0.25, "recoil": 2.4, "range": 300.0, "zoom": 22.0, "snd": "shot_heavy", "price": 6000, "ammo": 120, "atts": ["extmag"]},
	"sniper": {"name": "Hawkeye Sniper", "model": "wpn_sniper", "slot": 5, "dmg": 160.0, "rate": 0.8, "mag": 5, "max": 60, "reload": 2.8, "spread": 0.05, "recoil": 4.0, "range": 600.0, "zoom": 9.0, "scoped": true, "snd": "shot_sniper", "price": 9000, "ammo": 200, "atts": []},
	"grenade": {"name": "Frag Grenade", "model": "wpn_grenade", "slot": 6, "proj": "grenade", "dmg": 220.0, "rate": 0.9, "mag": 1, "max": 20, "reload": 0.1, "spread": 0.0, "recoil": 0.0, "range": 40.0, "onehand": true, "snd": "throw", "price": 300, "ammo": 300, "atts": []},
	"rocket": {"name": "Ramrod Launcher", "model": "wpn_rocket", "slot": 7, "proj": "rocket", "dmg": 400.0, "rate": 0.5, "mag": 1, "max": 20, "reload": 2.6, "spread": 0.2, "recoil": 5.0, "range": 400.0, "snd": "shot_rocket", "price": 15000, "ammo": 1500, "atts": []},
}
const WEAPON_ORDER := ["fists", "knife", "bat", "pistol", "revolver", "smg", "shotgun", "rifle", "carbine", "marksman", "sniper", "grenade", "rocket"]
const SLOT_NAMES := ["Melee", "Handguns", "SMG", "Shotguns", "Rifles", "Sniper", "Thrown", "Heavy"]
const ATTACHMENTS := {
	"suppressor": {"name": "Suppressor", "price": 800, "desc": "Quieter shots, -8% damage"},
	"flashlight": {"name": "Flashlight", "price": 250, "desc": "Lights up the dark while aiming"},
	"extmag": {"name": "Extended Magazine", "price": 600, "desc": "+50% magazine capacity"},
	"scope": {"name": "Optic", "price": 900, "desc": "Tighter zoom when aiming"},
	"grip": {"name": "Fore Grip", "price": 500, "desc": "-30% recoil and spread"},
}
const FINISHES := [["Factory", [0.16, 0.17, 0.19]], ["Desert", [0.6, 0.5, 0.3]], ["Olive", [0.25, 0.32, 0.18]], ["Chrome", [0.8, 0.82, 0.85]], ["Gold", [0.85, 0.65, 0.15]], ["Crimson", [0.6, 0.08, 0.08]]]

# Mod garage: levels with price and effect multipliers (applied in vehicle.gd apply_mods()).
const UPGRADES := {
	"engine": {"name": "Engine Tune", "levels": 3, "price": 2500, "desc": "+10% acceleration and top speed per level"},
	"turbo": {"name": "Turbo Kit", "levels": 1, "price": 6000, "desc": "+20% acceleration"},
	"transmission": {"name": "Transmission", "levels": 2, "price": 2000, "desc": "+8% acceleration per level"},
	"brakes": {"name": "Brakes", "levels": 2, "price": 1500, "desc": "+25% braking per level"},
	"suspension": {"name": "Suspension", "levels": 2, "price": 1500, "desc": "Lower, stiffer, +6% grip per level"},
	"armor": {"name": "Armor Plating", "levels": 3, "price": 3000, "desc": "-18% damage taken per level"},
	"tires": {"name": "Bullet-Resistant Tires", "levels": 1, "price": 4000, "desc": "Tires cannot be punctured"},
	"downforce": {"name": "Aero Tuning", "levels": 1, "price": 1800, "desc": "More high-speed grip (best with spoiler)"},
}
const MOD_PARTS := {"spoiler": ["Spoiler", 900], "skirts": ["Side Skirts", 700], "bumper": ["Front Splitter", 800], "hood": ["Hood Scoop", 750], "exhaust": ["Sport Exhaust", 600], "roof": ["Roof Scoop", 650]}
const TINTS := [["Stock", [0.09, 0.14, 0.18]], ["Smoke", [0.04, 0.05, 0.06]], ["Limo Black", [0.01, 0.01, 0.01]], ["Blue", [0.05, 0.15, 0.35]], ["Amber", [0.35, 0.2, 0.05]]]
const FINISH_TYPES := [["Gloss", 0.3, 0.3], ["Matte", 0.85, 0.0], ["Metallic", 0.22, 0.85], ["Chrome", 0.05, 1.0]]
const WHEEL_COLORS := [["Alloy", [0.72, 0.74, 0.77]], ["Black", [0.05, 0.05, 0.05]], ["Gold", [0.85, 0.65, 0.15]], ["Red", [0.75, 0.08, 0.08]], ["White", [0.92, 0.92, 0.92]]]
const HORNS := [["Stock", 1.0], ["Truck", 0.6], ["Clown", 1.7], ["Sport", 1.3]]
const LIGHT_COLORS := [["Warm", [1.0, 0.95, 0.8]], ["Xenon", [0.75, 0.85, 1.0]], ["Yellow", [1.0, 0.85, 0.3]], ["Purple", [0.75, 0.5, 1.0]]]
const PLATES := [["White", [0.9, 0.9, 0.85]], ["Yellow", [0.95, 0.8, 0.2]], ["Black", [0.06, 0.06, 0.06]], ["Blue", [0.2, 0.35, 0.8]]]

const CLOTH_COLORS := [["White", [0.9, 0.9, 0.9]], ["Black", [0.07, 0.07, 0.08]], ["Red", [0.75, 0.12, 0.12]], ["Navy", [0.12, 0.18, 0.4]], ["Olive", [0.3, 0.36, 0.2]], ["Mustard", [0.85, 0.65, 0.15]], ["Teal", [0.1, 0.5, 0.5]], ["Pink", [0.9, 0.5, 0.6]], ["Grey", [0.45, 0.46, 0.5]], ["Denim", [0.22, 0.3, 0.45]], ["Khaki", [0.7, 0.62, 0.45]], ["Brown", [0.35, 0.22, 0.14]]]
const HAIRS := ["none", "acc_hair_short", "acc_hair_long", "acc_hair_mohawk", "acc_hair_pony"]
const HAIR_NAMES := ["Shaved", "Short", "Long", "Mohawk", "Ponytail"]
const HAIR_COLORS := [["Dark Brown", [0.2, 0.13, 0.08]], ["Black", [0.04, 0.04, 0.05]], ["Blond", [0.85, 0.7, 0.35]], ["Ginger", [0.7, 0.3, 0.1]], ["Grey", [0.6, 0.6, 0.62]], ["Blue", [0.15, 0.4, 0.85]], ["Pink", [0.9, 0.35, 0.6]]]
const SKINS := [[0.85, 0.64, 0.48], [0.72, 0.5, 0.36], [0.5, 0.34, 0.24], [0.93, 0.76, 0.62], [0.36, 0.24, 0.17]]

# Footprints (w along X, d along Z, h) of Blender buildings; front faces -Z.
const BUILDINGS := {
	"bld_office_a": [26, 26, 56], "bld_office_b": [22, 30, 42], "bld_office_c": [30, 22, 30], "bld_office_d": [22, 22, 69],
	"bld_apart_a": [24, 18, 20], "bld_apart_b": [20, 20, 26.5], "bld_apart_c": [22, 14, 13.3],
	"bld_house_a": [10.8, 9.8, 6], "bld_house_b": [12.8, 8.8, 9], "bld_house_c": [11.8, 9.8, 6], "bld_house_d": [9.8, 9.8, 9],
	"bld_shop_a": [14, 12, 8], "bld_shop_b": [12, 12, 7], "bld_shop_c": [16, 12, 9], "bld_shop_d": [12, 12, 6.6],
	"bld_gunshop": [14, 12, 6.6], "bld_clothes": [14, 12, 7], "bld_barber": [10, 10, 5], "bld_police": [28, 26, 10], "bld_hospital": [30, 34, 19.8],
	"bld_warehouse_a": [36, 24, 12], "bld_warehouse_b": [28, 20, 10], "bld_factory": [40, 28, 30], "bld_range": [16, 10, 6],
	"bld_modshop": [18, 16, 7], "bld_gas": [18, 21, 8], "bld_hangar": [30, 28, 13.5], "bld_tower": [12, 12, 27], "bld_parking": [30, 30, 12], "bld_safehouse": [24, 12, 9.6],
}
const POOLS := {
	"downtown": ["bld_office_a", "bld_office_b", "bld_office_c", "bld_office_d", "bld_office_c", "bld_apart_b", "bld_shop_c"],
	"mixed": ["bld_apart_a", "bld_apart_b", "bld_apart_c", "bld_shop_a", "bld_shop_b", "bld_shop_c", "bld_shop_d"],
	"residential": ["bld_house_a", "bld_house_b", "bld_house_c", "bld_house_d", "bld_house_a", "bld_apart_c"],
	"industrial": ["bld_warehouse_a", "bld_warehouse_b", "bld_warehouse_b"],
	"commercial": ["bld_shop_a", "bld_shop_b", "bld_shop_c", "bld_shop_d", "bld_apart_c"],
}
# district per block [col][row]
const DISTRICTS := [
	["industrial", "residential", "residential", "residential"],
	["industrial", "mixed", "park", "mixed"],
	["industrial", "downtown", "downtown", "commercial"],
	["industrial", "downtown", "downtown", "mixed"],
]
const TELEPORTS := {
	"Safehouse": Vector3(-162, 0.3, 6), "Downtown": Vector3(0, 0.3, -34), "Police Station": Vector3(86, 0.3, -84),
	"Hospital": Vector3(84, 0.3, 34), "Weapon Shop": Vector3(-2, 0.3, 46), "Mod Garage": Vector3(-12, 0.3, -132),
	"Clothing Store": Vector3(22, 0.3, 46), "Industrial": Vector3(-160, 0.3, -206), "Park": Vector3(-80, 0.3, 0),
	"Beach": Vector3(-60, 0.4, 196), "Docks": Vector3(96, 0.4, 176), "Airport": Vector3(180, 0.3, -40),
	"Runway": Vector3(236, 0.3, 150), "Hill Viewpoint": Vector3(-60, 22, -256), "Gas Station": Vector3(20, 0.3, -134),
	"Shooting Range": Vector3(96, 0.3, -134), "Dive Wreck": Vector3(-150, -0.8, 262),
}
const SKILLS := ["stamina", "shooting", "strength", "stealth", "driving", "flying", "lung"]
