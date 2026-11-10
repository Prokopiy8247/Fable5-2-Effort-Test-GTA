extends Node
## Data-driven registries: weapons, weapon mods, vehicles, vehicle upgrades, clothing, NPC looks (autoload "Data").

var weapons: Dictionary = {}       # id -> WeaponDef
var weapon_order: Array[String] = []
var vehicles: Dictionary = {}      # id -> VehicleDef
var vehicle_order: Array[String] = []

const SLOT_NAMES := ["Melee", "Handguns", "SMG", "Shotguns", "Rifles", "Precision", "Heavy", "Thrown"]

const WEAPON_MODS := {
	"suppressor": {"name": "Suppressor", "price": 450, "desc": "Much quieter shots, -8% damage"},
	"extmag": {"name": "Extended Magazine", "price": 350, "desc": "+50% magazine capacity"},
	"flashlight": {"name": "Flashlight", "price": 150, "desc": "Lights up dark areas while aiming"},
	"scope": {"name": "Optic", "price": 600, "desc": "Tighter zoom while aiming"},
	"grip": {"name": "Foregrip", "price": 300, "desc": "-30% recoil and spread"},
}
const WEAPON_TINTS := [["Factory", Color(0.16, 0.17, 0.19)], ["Desert", Color(0.72, 0.6, 0.42)], ["Olive", Color(0.36, 0.4, 0.25)],
	["Gold", Color(0.9, 0.7, 0.25)], ["Coral", Color(0.9, 0.36, 0.3)], ["Arctic", Color(0.9, 0.92, 0.94)], ["Teal", Color(0.18, 0.6, 0.58)]]

const PAINTS := [["Coral Red", Color("d8402f")], ["Sunset Orange", Color("e9822b")], ["Taxi Yellow", Color("f0c330")], ["Mint", Color("7fd1ae")],
	["Lagoon Teal", Color("2f9c95")], ["Bay Blue", Color("2f6fba")], ["Midnight", Color("1b2440")], ["Violet", Color("7a4a9c")],
	["Flamingo", Color("e27a8c")], ["Pearl White", Color("f1eee6")], ["Silver", Color("b9bec6")], ["Graphite", Color("3a3d44")],
	["Jet Black", Color("111215")], ["Forest", Color("2f6b3c")], ["Burgundy", Color("7c1f2c")], ["Sand", Color("d7c08f")]]
const FINISHES := {"gloss": [0.25, 0.35], "matte": [0.85, 0.0], "metallic": [0.2, 0.85], "chrome": [0.05, 1.0]}
const TINTS := [["None", 0.42], ["Light", 0.6], ["Dark", 0.8], ["Limo", 0.95]]
const RIMS := [["Stock", "wheel_std"], ["Sport", "wheel_sport"], ["Off-road", "wheel_offroad"], ["Classic", "wheel_classic"]]
const RIM_COLORS := [["Alloy", Color("c9ccd2")], ["Black", Color("17181b")], ["Gold", Color("d8a93a")], ["Red", Color("c8382b")], ["White", Color("f1eee6")]]
const LIGHT_COLORS := [["Halogen", Color(1.0, 0.93, 0.75)], ["Xenon", Color(0.75, 0.86, 1.0)], ["Amber", Color(1.0, 0.75, 0.3)], ["Violet", Color(0.8, 0.6, 1.0)]]
const PLATES := [["White", Color("f4f1e4")], ["Yellow", Color("f0c330")], ["Black", Color("17181b")], ["Blue", Color("2f6fba")]]
const HORNS := ["Standard", "Truck", "Musical"]

## Vehicle upgrade catalogue. kind: choice (list), toggle (mesh part), level (performance tiers)
const UPGRADES := [
	{"id": "paint", "name": "Primary Paint", "cat": "Cosmetic", "kind": "paint", "price": 200},
	{"id": "paint2", "name": "Secondary Paint", "cat": "Cosmetic", "kind": "paint", "price": 150},
	{"id": "finish", "name": "Paint Finish", "cat": "Cosmetic", "kind": "choice", "options": ["gloss", "matte", "metallic", "chrome"], "price": 300},
	{"id": "rims", "name": "Wheels", "cat": "Cosmetic", "kind": "index", "count": 4, "labels": ["Stock", "Sport", "Off-road", "Classic"], "price": 600},
	{"id": "rim_color", "name": "Wheel Colour", "cat": "Cosmetic", "kind": "index", "count": 5, "labels": ["Alloy", "Black", "Gold", "Red", "White"], "price": 150},
	{"id": "tint", "name": "Window Tint", "cat": "Cosmetic", "kind": "index", "count": 4, "labels": ["None", "Light", "Dark", "Limo"], "price": 250},
	{"id": "spoiler", "name": "Spoiler", "cat": "Body", "kind": "index", "count": 3, "labels": ["None", "Lip", "GT Wing"], "price": 900, "part": "spoiler"},
	{"id": "bumper_f", "name": "Front Bumper", "cat": "Body", "kind": "index", "count": 2, "labels": ["Stock", "Splitter"], "price": 500, "part": "bumper_f"},
	{"id": "bumper_r", "name": "Rear Bumper", "cat": "Body", "kind": "index", "count": 2, "labels": ["Stock", "Diffuser"], "price": 500, "part": "bumper_r"},
	{"id": "skirts", "name": "Side Skirts", "cat": "Body", "kind": "index", "count": 2, "labels": ["Stock", "Sport"], "price": 400, "part": "skirts"},
	{"id": "hood", "name": "Hood", "cat": "Body", "kind": "index", "count": 2, "labels": ["Stock", "Scoop"], "price": 650, "part": "hood"},
	{"id": "roof", "name": "Roof", "cat": "Body", "kind": "index", "count": 2, "labels": ["Stock", "Rack"], "price": 350, "part": "roof"},
	{"id": "exhaust", "name": "Exhaust", "cat": "Body", "kind": "index", "count": 2, "labels": ["Stock", "Quad Tips"], "price": 450, "part": "exhaust"},
	{"id": "lights", "name": "Headlights", "cat": "Cosmetic", "kind": "index", "count": 4, "labels": ["Halogen", "Xenon", "Amber", "Violet"], "price": 300},
	{"id": "neon", "name": "Underglow", "cat": "Cosmetic", "kind": "index", "count": 4, "labels": ["Off", "Teal", "Pink", "Gold"], "price": 800},
	{"id": "horn", "name": "Horn", "cat": "Cosmetic", "kind": "index", "count": 3, "labels": ["Standard", "Truck", "Musical"], "price": 120},
	{"id": "plate", "name": "Plate Style", "cat": "Cosmetic", "kind": "index", "count": 4, "labels": ["White", "Yellow", "Black", "Blue"], "price": 80},
	{"id": "engine", "name": "Engine Tune", "cat": "Performance", "kind": "level", "count": 4, "price": 1500, "desc": "+9% engine force per level"},
	{"id": "brakes", "name": "Brakes", "cat": "Performance", "kind": "level", "count": 4, "price": 800, "desc": "+15% braking per level"},
	{"id": "suspension", "name": "Suspension", "cat": "Performance", "kind": "index", "count": 3, "labels": ["Stock", "Sport", "Lowered"], "price": 900, "desc": "Stiffer, lower, less body roll"},
	{"id": "transmission", "name": "Transmission", "cat": "Performance", "kind": "level", "count": 4, "price": 1200, "desc": "+5% top speed, quicker shifts"},
	{"id": "turbo", "name": "Turbo", "cat": "Performance", "kind": "level", "count": 2, "price": 3500, "desc": "+18% power at mid/high revs"},
	{"id": "armor", "name": "Armor", "cat": "Performance", "kind": "level", "count": 5, "price": 1400, "desc": "-15% damage taken per level"},
	{"id": "tires", "name": "Tires", "cat": "Performance", "kind": "index", "count": 2, "labels": ["Standard", "Bullet-resistant"], "price": 2000, "desc": "Cannot be punctured"},
]

const SKIN_TONES := [Color("f1c9a5"), Color("d9a27e"), Color("b97d56"), Color("8a5a3c"), Color("5f3d2b")]
const HAIR_COLORS := [["Dark Brown", Color("3a2a1e")], ["Black", Color("17181b")], ["Blonde", Color("d8b563")], ["Auburn", Color("8c3f25")],
	["Grey", Color("9a9a9a")], ["Teal", Color("2f9c95")], ["Pink", Color("e27a8c")]]
const HAIR_STYLES := ["none", "hair_short", "hair_long", "hair_bun", "hair_mohawk", "hair_afro"]
const BEARDS := ["none", "beard", "moustache"]
const CLOTH_COLORS := [["White", Color("f1eee6")], ["Black", Color("1c1d21")], ["Navy", Color("1f2d4d")], ["Denim", Color("3f6aa0")],
	["Coral", Color("d8503c")], ["Teal", Color("2f9c95")], ["Mustard", Color("e0a62c")], ["Olive", Color("5b6340")], ["Pink", Color("e27a8c")],
	["Grey", Color("8c8f96")], ["Purple", Color("7a4a9c")], ["Khaki", Color("c3ad7c")], ["Brown", Color("6e4a33")], ["Green", Color("4f9a4b")]]
const HATS := ["none", "cap", "beanie", "fedora"]
const GLASSES := ["none", "sunglasses", "glasses"]
const WARDROBE := [
	{"id": "shirt", "name": "Top Colour", "price": 60}, {"id": "sleeves", "name": "Sleeves", "price": 30, "labels": ["Short", "Long"]},
	{"id": "jacket", "name": "Jacket", "price": 220, "labels": ["None", "Open Jacket"]}, {"id": "jacket_color", "name": "Jacket Colour", "price": 40},
	{"id": "pants", "name": "Legwear Colour", "price": 60}, {"id": "shorts", "name": "Leg Length", "price": 30, "labels": ["Trousers", "Shorts"]},
	{"id": "shoes", "name": "Shoes", "price": 80}, {"id": "hat", "name": "Hat", "price": 90, "labels": ["None", "Cap", "Beanie", "Fedora"]},
	{"id": "hat_color", "name": "Hat Colour", "price": 30}, {"id": "glasses", "name": "Eyewear", "price": 120, "labels": ["None", "Sunglasses", "Glasses"]},
]


func _enter_tree() -> void:
	_weapons()
	_vehicles()


func _w(d: Dictionary) -> void:
	var w := WeaponDef.new()
	for k in d:
		w.set(k, d[k])
	weapons[w.id] = w
	weapon_order.append(w.id)


func _weapons() -> void:
	_w({"id": "fists", "name": "Fists", "slot": 0, "kind": "melee", "hold": "fist", "damage": 12.0, "rate": 2.4, "reach": 1.7, "noise": 4.0})
	_w({"id": "knife", "name": "Knife", "slot": 0, "kind": "melee", "hold": "melee", "damage": 34.0, "rate": 2.8, "reach": 1.8, "model": "w_knife", "price": 120, "noise": 3.0})
	_w({"id": "bat", "name": "Baseball Bat", "slot": 0, "kind": "melee", "hold": "melee", "damage": 26.0, "rate": 1.7, "reach": 2.2, "model": "w_bat", "price": 90, "knock": 1.6, "noise": 6.0})
	_w({"id": "crowbar", "name": "Crowbar", "slot": 0, "kind": "melee", "hold": "melee", "damage": 30.0, "rate": 1.9, "reach": 2.0, "model": "w_crowbar", "price": 110, "knock": 1.3, "noise": 6.0})
	_w({"id": "pistol", "name": "P9 Pistol", "slot": 1, "kind": "hitscan", "hold": "pistol", "damage": 22.0, "rate": 5.0, "mag": 12, "max_ammo": 180, "reload": 1.3,
		"spread": 1.5, "recoil": 1.1, "reach": 90.0, "model": "w_pistol", "price": 350, "ammo_price": 40, "driveby": true, "noise": 55.0,
		"mods": ["suppressor", "extmag", "flashlight"], "sound": "shot_pistol"})
	_w({"id": "heavy_pistol", "name": "Bulldog .50", "slot": 1, "kind": "hitscan", "hold": "pistol", "damage": 52.0, "rate": 2.2, "mag": 6, "max_ammo": 96, "reload": 1.9,
		"spread": 1.1, "recoil": 3.4, "reach": 110.0, "model": "w_heavy_pistol", "price": 950, "ammo_price": 60, "driveby": true, "noise": 70.0,
		"mods": ["scope", "flashlight"], "sound": "shot_heavy"})
	_w({"id": "smg", "name": "Viper SMG", "slot": 2, "kind": "hitscan", "hold": "pistol", "damage": 16.0, "rate": 13.0, "mag": 30, "max_ammo": 360, "reload": 1.8,
		"spread": 2.6, "recoil": 0.7, "reach": 70.0, "auto": true, "model": "w_smg", "price": 1400, "ammo_price": 70, "driveby": true, "noise": 55.0,
		"mods": ["suppressor", "extmag", "flashlight", "scope", "grip"], "sound": "shot_smg"})
	_w({"id": "shotgun", "name": "Pump Shotgun", "slot": 3, "kind": "hitscan", "hold": "rifle", "damage": 13.0, "pellets": 8, "rate": 1.15, "mag": 6, "max_ammo": 72,
		"reload": 2.6, "spread": 6.0, "recoil": 5.0, "reach": 40.0, "model": "w_shotgun", "price": 1600, "ammo_price": 60, "noise": 75.0,
		"mods": ["extmag", "flashlight", "scope"], "sound": "shot_shotgun"})
	_w({"id": "auto_shotgun", "name": "Riot Auto-12", "slot": 3, "kind": "hitscan", "hold": "rifle", "damage": 10.0, "pellets": 8, "rate": 3.4, "mag": 8, "max_ammo": 96,
		"reload": 2.8, "spread": 7.0, "recoil": 3.6, "reach": 36.0, "auto": true, "model": "w_auto_shotgun", "price": 3200, "ammo_price": 90, "noise": 75.0,
		"mods": ["suppressor", "extmag", "flashlight", "scope", "grip"], "sound": "shot_shotgun"})
	_w({"id": "assault_rifle", "name": "AR-7 Rifle", "slot": 4, "kind": "hitscan", "hold": "rifle", "damage": 28.0, "rate": 9.0, "mag": 30, "max_ammo": 360, "reload": 2.2,
		"spread": 1.5, "recoil": 1.2, "reach": 150.0, "auto": true, "model": "w_assault_rifle", "price": 2800, "ammo_price": 90, "noise": 80.0,
		"mods": ["suppressor", "extmag", "flashlight", "scope", "grip"], "sound": "shot_rifle"})
	_w({"id": "carbine", "name": "Tactical Carbine", "slot": 4, "kind": "hitscan", "hold": "rifle", "damage": 24.0, "rate": 11.0, "mag": 30, "max_ammo": 360, "reload": 2.0,
		"spread": 1.1, "recoil": 0.9, "reach": 150.0, "auto": true, "model": "w_carbine", "price": 3400, "ammo_price": 90, "noise": 80.0,
		"mods": ["suppressor", "extmag", "flashlight", "scope", "grip"], "sound": "shot_rifle"})
	_w({"id": "marksman", "name": "Marksman Rifle", "slot": 5, "kind": "hitscan", "hold": "rifle", "damage": 64.0, "rate": 2.6, "mag": 10, "max_ammo": 120, "reload": 2.4,
		"spread": 0.3, "recoil": 2.4, "reach": 300.0, "zoom_fov": 26.0, "model": "w_marksman", "price": 4200, "ammo_price": 120, "noise": 90.0,
		"mods": ["suppressor", "extmag", "flashlight", "grip"], "sound": "shot_rifle"})
	_w({"id": "sniper", "name": "Longshot Sniper", "slot": 5, "kind": "hitscan", "hold": "rifle", "damage": 150.0, "rate": 0.8, "mag": 5, "max_ammo": 60, "reload": 3.0,
		"spread": 0.03, "recoil": 4.0, "reach": 600.0, "zoom_fov": 11.0, "scoped": true, "model": "w_sniper", "price": 6500, "ammo_price": 160, "noise": 110.0,
		"mods": ["suppressor", "extmag"], "sound": "shot_sniper"})
	_w({"id": "rocket_launcher", "name": "Rocket Launcher", "slot": 6, "kind": "projectile", "proj": "rocket", "hold": "launcher", "damage": 260.0, "rate": 0.5, "mag": 1,
		"max_ammo": 12, "reload": 2.6, "spread": 0.3, "recoil": 4.0, "reach": 400.0, "model": "w_rocket_launcher", "price": 9000, "ammo_price": 500,
		"ammo_pack": 2, "noise": 120.0, "sound": "shot_rocket"})
	_w({"id": "grenade_launcher", "name": "Thumper GL", "slot": 6, "kind": "projectile", "proj": "grenade", "hold": "rifle", "damage": 170.0, "rate": 1.6, "mag": 6,
		"max_ammo": 30, "reload": 3.2, "spread": 0.6, "recoil": 3.0, "reach": 200.0, "model": "w_grenade_launcher", "price": 7000, "ammo_price": 420,
		"ammo_pack": 6, "noise": 80.0, "mods": ["scope", "grip"], "sound": "shot_gl"})
	_w({"id": "grenade", "name": "Frag Grenade", "slot": 7, "kind": "thrown", "proj": "grenade", "hold": "thrown", "damage": 180.0, "rate": 0.9, "mag": 1, "max_ammo": 12,
		"reload": 0.0, "reach": 40.0, "model": "w_grenade", "price": 180, "ammo_price": 180, "ammo_pack": 1, "driveby": true, "noise": 10.0})
	_w({"id": "molotov", "name": "Fire Bottle", "slot": 7, "kind": "thrown", "proj": "molotov", "hold": "thrown", "damage": 40.0, "rate": 0.9, "mag": 1, "max_ammo": 12,
		"reload": 0.0, "reach": 40.0, "model": "w_molotov", "price": 150, "ammo_price": 150, "ammo_pack": 1, "driveby": true, "noise": 10.0})


func _v(d: Dictionary) -> void:
	var v := VehicleDef.new()
	for k in d:
		v.set(k, d[k])
	vehicles[v.id] = v
	vehicle_order.append(v.id)


func _vehicles() -> void:
	_v({"id": "compact", "name": "Pico", "kind": "car", "mass": 1050.0, "engine": 5600.0, "max_speed": 34.0, "brake": 11000.0, "steer": 34.0, "grip": 1.05,
		"drive": "fwd", "seats": 4, "health": 800.0, "price": 6000, "traffic": 3.0, "engine_pitch": 1.2})
	_v({"id": "sedan", "name": "Marlow", "kind": "car", "mass": 1400.0, "engine": 7600.0, "max_speed": 40.0, "brake": 14000.0, "steer": 32.0, "grip": 1.0,
		"drive": "rwd", "seats": 4, "health": 1000.0, "price": 12000, "traffic": 4.0})
	_v({"id": "sports", "name": "Vanta GT", "kind": "car", "mass": 1300.0, "engine": 13500.0, "max_speed": 62.0, "brake": 20000.0, "steer": 30.0, "grip": 1.3,
		"drive": "rwd", "seats": 2, "health": 900.0, "price": 85000, "traffic": 0.8, "engine_pitch": 1.35, "susp_rest": 0.22})
	_v({"id": "muscle", "name": "Brawler", "kind": "car", "mass": 1650.0, "engine": 13000.0, "max_speed": 54.0, "brake": 16000.0, "steer": 31.0, "grip": 0.95,
		"drive": "rwd", "seats": 2, "health": 1100.0, "price": 38000, "traffic": 1.2, "engine_pitch": 0.8})
	_v({"id": "suv", "name": "Ridgeback", "kind": "car", "mass": 2100.0, "engine": 11000.0, "max_speed": 42.0, "brake": 19000.0, "steer": 30.0, "grip": 1.0,
		"drive": "awd", "seats": 4, "health": 1400.0, "price": 30000, "traffic": 2.5, "susp_rest": 0.42, "engine_pitch": 0.9})
	_v({"id": "pickup", "name": "Drover", "kind": "car", "mass": 2000.0, "engine": 10500.0, "max_speed": 40.0, "brake": 18000.0, "steer": 30.0, "grip": 0.95,
		"drive": "awd", "seats": 2, "health": 1400.0, "price": 22000, "traffic": 2.0, "susp_rest": 0.42, "engine_pitch": 0.85})
	_v({"id": "van", "name": "Hauler", "kind": "car", "mass": 2300.0, "engine": 9500.0, "max_speed": 34.0, "brake": 18000.0, "steer": 31.0, "grip": 0.9,
		"drive": "rwd", "seats": 2, "health": 1500.0, "price": 18000, "traffic": 1.6, "engine_pitch": 0.8})
	_v({"id": "taxi", "name": "Cabbie", "kind": "car", "mass": 1500.0, "engine": 8200.0, "max_speed": 40.0, "brake": 15000.0, "steer": 33.0, "grip": 1.0,
		"drive": "rwd", "seats": 4, "health": 1100.0, "price": 15000, "traffic": 1.4, "fixed_color": Color("f0c330"), "tag": "taxi"})
	_v({"id": "police", "name": "Interceptor", "kind": "car", "mass": 1600.0, "engine": 13500.0, "max_speed": 56.0, "brake": 20000.0, "steer": 33.0, "grip": 1.25,
		"drive": "awd", "seats": 4, "health": 1500.0, "price": 0, "traffic": 0.0, "fixed_color": Color("15181f"), "fixed_color2": Color("f1eee6"),
		"tag": "police", "siren": true})
	_v({"id": "swat", "name": "Bulwark", "kind": "car", "mass": 4200.0, "engine": 21000.0, "max_speed": 40.0, "brake": 36000.0, "steer": 28.0, "grip": 1.0,
		"drive": "awd", "seats": 4, "health": 4000.0, "price": 0, "traffic": 0.0, "fixed_color": Color("1b2233"), "tag": "police", "siren": true,
		"susp_rest": 0.45, "engine_pitch": 0.65})
	_v({"id": "ambulance", "name": "Lifeline", "kind": "car", "mass": 2800.0, "engine": 13000.0, "max_speed": 40.0, "brake": 24000.0, "steer": 30.0, "grip": 0.95,
		"drive": "rwd", "seats": 2, "health": 1800.0, "price": 0, "traffic": 0.0, "fixed_color": Color("f1eee6"), "tag": "ems", "siren": true, "engine_pitch": 0.8})
	_v({"id": "firetruck", "name": "Blaze Engine", "kind": "car", "mass": 7500.0, "engine": 30000.0, "max_speed": 32.0, "brake": 60000.0, "steer": 28.0, "grip": 0.95,
		"drive": "rwd", "seats": 2, "health": 4000.0, "price": 0, "traffic": 0.0, "fixed_color": Color("c8382b"), "tag": "fire", "siren": true,
		"susp_rest": 0.5, "engine_pitch": 0.55})
	_v({"id": "boxtruck", "name": "Freightliner", "kind": "car", "mass": 5200.0, "engine": 19000.0, "max_speed": 30.0, "brake": 42000.0, "steer": 28.0, "grip": 0.9,
		"drive": "rwd", "seats": 2, "health": 3000.0, "price": 26000, "traffic": 1.0, "susp_rest": 0.48, "engine_pitch": 0.6})
	_v({"id": "motorcycle", "name": "Wasp 600", "kind": "bike", "mass": 260.0, "engine": 4300.0, "max_speed": 58.0, "brake": 4200.0, "steer": 30.0, "grip": 1.25,
		"drive": "rwd", "seats": 2, "health": 450.0, "price": 14000, "traffic": 0.9, "engine_pitch": 1.6, "susp_rest": 0.26})
	_v({"id": "bicycle", "name": "City Bike", "kind": "bicycle", "mass": 90.0, "engine": 520.0, "max_speed": 13.0, "brake": 900.0, "steer": 34.0, "grip": 1.1,
		"drive": "rwd", "seats": 1, "health": 200.0, "price": 400, "traffic": 0.0, "susp_rest": 0.2, "silent": true})
	_v({"id": "speedboat", "name": "Skimmer", "kind": "boat", "mass": 1300.0, "engine": 16000.0, "max_speed": 30.0, "seats": 4, "health": 1000.0, "price": 40000,
		"engine_pitch": 1.1})
	_v({"id": "policeboat", "name": "Harbor Patrol", "kind": "boat", "mass": 1400.0, "engine": 18000.0, "max_speed": 32.0, "seats": 4, "health": 1400.0, "price": 0,
		"fixed_color": Color("1f2d4d"), "tag": "police", "siren": true})
	_v({"id": "heli", "name": "Dragonfly", "kind": "heli", "mass": 1400.0, "engine": 1.0, "max_speed": 55.0, "seats": 4, "health": 1200.0, "price": 180000})
	_v({"id": "heli_police", "name": "Skywatch", "kind": "heli", "mass": 1900.0, "engine": 1.0, "max_speed": 60.0, "seats": 4, "health": 1800.0, "price": 0,
		"fixed_color": Color("15181f"), "fixed_color2": Color("f1eee6"), "tag": "police"})
	_v({"id": "plane", "name": "Kestrel", "kind": "plane", "mass": 1100.0, "engine": 13000.0, "max_speed": 62.0, "seats": 4, "health": 900.0, "price": 150000,
		"takeoff_speed": 26.0, "brake": 6000.0})
	_v({"id": "jet", "name": "Arrow J1", "kind": "plane", "mass": 3200.0, "engine": 42000.0, "max_speed": 115.0, "seats": 4, "health": 1300.0, "price": 600000,
		"takeoff_speed": 38.0, "brake": 20000.0, "jet": true})


# ------------------------------------------------------------------ appearance presets
func random_civilian(r: RandomNumberGenerator) -> Dictionary:
	var female := r.randf() < 0.5
	var look := {"gender": "female" if female else "male", "skin": SKIN_TONES[r.randi() % SKIN_TONES.size()],
		"shirt": CLOTH_COLORS[r.randi() % CLOTH_COLORS.size()][1], "sleeves": r.randi() % 2, "pants": CLOTH_COLORS[r.randi() % CLOTH_COLORS.size()][1],
		"shorts": 1 if r.randf() < 0.3 else 0, "shoes": [Color("26221f"), Color("f1eee6"), Color("6e4a33"), Color("c8382b")][r.randi() % 4],
		"hair": HAIR_STYLES[1 + r.randi() % (HAIR_STYLES.size() - 1)], "hair_color": HAIR_COLORS[r.randi() % 5][1],
		"hat": "none", "hat_color": CLOTH_COLORS[r.randi() % CLOTH_COLORS.size()][1], "glasses": "none", "beard": "none", "extras": []}
	if female:
		look.hair = ["hair_long", "hair_bun", "hair_short", "hair_afro", "hair_long"][r.randi() % 5]
	else:
		look.hair = ["hair_short", "hair_short", "none", "hair_mohawk", "hair_afro", "hair_short"][r.randi() % 6]
		if r.randf() < 0.3:
			look.beard = BEARDS[1 + r.randi() % 2]
	if r.randf() < 0.22:
		look.hat = HATS[1 + r.randi() % 3]
	if r.randf() < 0.25:
		look.glasses = GLASSES[1 + r.randi() % 2]
	if r.randf() < 0.2:
		look.extras = ["jacket"]
	look.scale = r.randf_range(0.94, 1.06)
	return look


func look_cop(r: RandomNumberGenerator, swat: bool = false) -> Dictionary:
	var l := random_civilian(r)
	l.shirt = Color("1f2d4d") if not swat else Color("20242b")
	l.sleeves = 1 if swat else 0
	l.pants = Color("161c2e") if not swat else Color("20242b")
	l.shorts = 0
	l.shoes = Color("121214")
	l.glasses = "sunglasses" if r.randf() < 0.4 and not swat else "none"
	l.hat = "helmet" if swat else "police_cap"
	l.hat_color = Color("161c2e")
	l.extras = ["vest", "belt"] if swat else ["belt", "badge"]
	if l.hair == "hair_afro" or l.hair == "hair_mohawk" or l.hair == "hair_long":
		l.hair = "hair_short" if l.gender == "male" else "hair_bun"
	l.scale = 1.02
	return l


func look_gang(r: RandomNumberGenerator) -> Dictionary:
	var l := random_civilian(r)
	l.gender = "male" if r.randf() < 0.8 else "female"
	l.shirt = Color("7a4a9c")
	l.pants = Color("1c1d21")
	l.shorts = 0
	l.hat = ["beanie", "cap", "none"][r.randi() % 3]
	l.hat_color = Color("1c1d21")
	l.glasses = "sunglasses" if r.randf() < 0.5 else "none"
	l.extras = ["jacket"] if r.randf() < 0.5 else []
	return l


func look_clerk(r: RandomNumberGenerator) -> Dictionary:
	var l := random_civilian(r)
	l.shirt = Color("f1eee6")
	l.sleeves = 1
	l.shorts = 0
	l.hat = "none"
	l.extras = ["apron"]
	return l


func look_medic(r: RandomNumberGenerator) -> Dictionary:
	var l := random_civilian(r)
	l.shirt = Color("2f9c95")
	l.pants = Color("2f9c95")
	l.shorts = 0
	l.sleeves = 0
	l.hat = "none"
	l.extras = []
	return l


func default_player_look() -> Dictionary:
	return {"gender": "male", "skin": SKIN_TONES[1], "shirt": Color("f1eee6"), "sleeves": 0, "pants": Color("3f6aa0"), "shorts": 0,
		"shoes": Color("f1eee6"), "hair": "hair_short", "hair_color": HAIR_COLORS[0][1], "hat": "none", "hat_color": Color("d8503c"),
		"glasses": "none", "beard": "none", "extras": ["jacket"], "jacket_color": Color("d8503c"), "scale": 1.0}
