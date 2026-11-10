extends RefCounted
## Data-driven registries: weapons, vehicles, upgrades, clothing, shops.

const WEAPONS := {
	"fists": {"name": "Fists", "cls": "melee", "dmg": 14, "rate": 2.4, "range": 1.7, "price": 0, "model": ""},
	"knife": {"name": "Combat Knife", "cls": "melee", "dmg": 38, "rate": 2.2, "range": 1.8, "price": 120, "model": "knife"},
	"bat": {"name": "Ash Bat", "cls": "melee", "dmg": 30, "rate": 1.5, "range": 2.1, "price": 80, "model": "bat", "knock": true},
	"crowbar": {"name": "Crowbar", "cls": "melee", "dmg": 34, "rate": 1.4, "range": 2.1, "price": 90, "model": "crowbar", "knock": true},
	"pistol": {"name": "K9 Pistol", "cls": "handgun", "dmg": 24, "rate": 5.0, "clip": 12, "max": 240, "spread": 1.2, "recoil": 1.0, "range": 90, "price": 350, "ammo": 40,
		"model": "pistol", "driveby": true, "noise": 70, "mods": ["Suppressor", "ExtMag", "Flashlight"]},
	"revolver": {"name": "Brute .44", "cls": "handgun", "dmg": 62, "rate": 1.6, "clip": 6, "max": 96, "spread": 0.8, "recoil": 3.2, "range": 110, "price": 900, "ammo": 70,
		"model": "revolver", "driveby": true, "noise": 90, "mods": []},
	"smg": {"name": "Wasp SMG", "cls": "smg", "dmg": 17, "rate": 13.0, "clip": 30, "max": 480, "spread": 2.4, "recoil": 0.7, "range": 70, "price": 1200, "ammo": 60, "auto": true,
		"model": "smg", "driveby": true, "noise": 75, "mods": ["Suppressor", "ExtMag", "Flashlight", "Scope", "Grip"]},
	"shotgun": {"name": "Gatekeeper Pump", "cls": "shotgun", "dmg": 16, "pellets": 8, "rate": 1.2, "clip": 6, "max": 96, "spread": 5.5, "recoil": 4.0, "range": 35, "price": 1100, "ammo": 60,
		"model": "shotgun", "two": true, "noise": 95, "mods": ["Flashlight", "ExtMag"]},
	"autoshotgun": {"name": "Riot Auto-12", "cls": "shotgun", "dmg": 13, "pellets": 8, "rate": 3.6, "clip": 8, "max": 120, "spread": 6.5, "recoil": 3.0, "range": 30, "price": 2600, "ammo": 80,
		"auto": true, "model": "autoshotgun", "two": true, "noise": 95, "mods": ["Suppressor", "ExtMag", "Flashlight", "Grip"]},
	"rifle": {"name": "AR-Vanta", "cls": "rifle", "dmg": 28, "rate": 9.5, "clip": 30, "max": 480, "spread": 1.5, "recoil": 1.1, "range": 140, "price": 2800, "ammo": 90, "auto": true,
		"model": "rifle", "two": true, "noise": 95, "mods": ["Suppressor", "ExtMag", "Flashlight", "Scope", "Grip"]},
	"carbine": {"name": "Courier Carbine", "cls": "rifle", "dmg": 24, "rate": 11.0, "clip": 30, "max": 480, "spread": 1.2, "recoil": 0.9, "range": 130, "price": 3400, "ammo": 90, "auto": true,
		"model": "carbine", "two": true, "noise": 90, "mods": ["Suppressor", "ExtMag", "Flashlight", "Scope", "Grip"]},
	"marksman": {"name": "Longview DMR", "cls": "rifle", "dmg": 70, "rate": 2.6, "clip": 10, "max": 120, "spread": 0.35, "recoil": 2.6, "range": 260, "price": 4800, "ammo": 110,
		"model": "marksman", "two": true, "zoom": 28.0, "noise": 100, "mods": ["Suppressor", "ExtMag", "Flashlight", "Grip"]},
	"sniper": {"name": "Hush-90 Sniper", "cls": "sniper", "dmg": 190, "rate": 0.8, "clip": 5, "max": 60, "spread": 0.05, "recoil": 5.0, "range": 600, "price": 7500, "ammo": 150,
		"model": "sniper", "two": true, "zoom": 9.0, "scope": true, "noise": 120, "mods": ["Suppressor"]},
	"grenadelauncher": {"name": "Thumper GL", "cls": "heavy", "dmg": 160, "rate": 1.1, "clip": 6, "max": 36, "spread": 1.0, "recoil": 3.0, "range": 120, "price": 9000, "ammo": 300,
		"model": "grenadelauncher", "two": true, "proj": "gl", "noise": 80, "mods": []},
	"rpg": {"name": "Ram-7 Launcher", "cls": "heavy", "dmg": 260, "rate": 0.5, "clip": 1, "max": 12, "spread": 0.4, "recoil": 6.0, "range": 300, "price": 12000, "ammo": 500,
		"model": "rpg", "two": true, "proj": "rocket", "noise": 110, "mods": []},
	"grenade": {"name": "Frag Grenade", "cls": "thrown", "dmg": 220, "rate": 0.9, "clip": 1, "max": 20, "price": 250, "ammo": 250, "model": "grenade", "proj": "grenade", "driveby": true, "noise": 0},
}
const WEAPON_ORDER := ["fists", "knife", "bat", "crowbar", "pistol", "revolver", "smg", "shotgun", "autoshotgun", "rifle", "carbine", "marksman", "sniper", "grenadelauncher", "rpg", "grenade"]
const WHEEL_CLASSES := ["melee", "handgun", "smg", "shotgun", "rifle", "sniper", "heavy", "thrown"]
const MOD_INFO := {
	"Suppressor": {"name": "Suppressor", "price": 600, "desc": "Noise radius -75%, damage -8%"},
	"ExtMag": {"name": "Extended magazine", "price": 450, "desc": "Magazine capacity +50%"},
	"Flashlight": {"name": "Flashlight", "price": 200, "desc": "Lights the target while aiming"},
	"Scope": {"name": "Optic", "price": 800, "desc": "Tighter aim zoom"},
	"Grip": {"name": "Foregrip", "price": 500, "desc": "Recoil and spread -30%"},
}
const TINTS := {"Factory": null, "Desert": Color(0.72, 0.62, 0.42), "Arctic": Color(0.86, 0.88, 0.9), "Crimson": Color(0.6, 0.1, 0.1), "Jade": Color(0.1, 0.45, 0.3), "Gold": Color(0.85, 0.68, 0.2)}

# engine = peak drive force (N), top = m/s, grip = lateral friction coefficient
const VEHICLES := {
	"sedan": {"name": "Halcyon Sedan", "cat": "land", "mass": 1350, "engine": 7200, "top": 44, "brake": 14000, "grip": 1.9, "hp": 1000, "price": 9000, "traffic": 10},
	"compact": {"name": "Pip Hatch", "cat": "land", "mass": 1050, "engine": 5600, "top": 40, "brake": 12000, "grip": 2.0, "hp": 850, "price": 6000, "traffic": 9},
	"sports": {"name": "Vireo GT", "cat": "land", "mass": 1250, "engine": 12500, "top": 68, "brake": 20000, "grip": 2.6, "hp": 900, "price": 60000, "traffic": 2, "roof": true},
	"muscle": {"name": "Brawler 427", "cat": "land", "mass": 1500, "engine": 11500, "top": 58, "brake": 15000, "grip": 1.8, "hp": 1100, "price": 35000, "traffic": 3, "rwd": true},
	"suv": {"name": "Ridgeback SUV", "cat": "land", "mass": 1900, "engine": 8600, "top": 44, "brake": 16000, "grip": 1.9, "hp": 1400, "price": 28000, "traffic": 6, "sus": 1.3},
	"pickup": {"name": "Dusty Hauler", "cat": "land", "mass": 1800, "engine": 8000, "top": 42, "brake": 15000, "grip": 1.8, "hp": 1350, "price": 18000, "traffic": 5, "sus": 1.3, "rwd": true},
	"van": {"name": "Courier Van", "cat": "land", "mass": 2000, "engine": 7000, "top": 36, "brake": 14000, "grip": 1.7, "hp": 1300, "price": 15000, "traffic": 5},
	"taxi": {"name": "Cinder Cab", "cat": "land", "mass": 1400, "engine": 7200, "top": 44, "brake": 14000, "grip": 1.9, "hp": 1050, "price": 12000, "traffic": 4, "color": Color(0.93, 0.74, 0.1)},
	"police": {"name": "Police Cruiser", "cat": "land", "mass": 1500, "engine": 10500, "top": 58, "brake": 19000, "grip": 2.3, "hp": 1300, "price": 0, "siren": true, "color": Color(0.08, 0.09, 0.11)},
	"ambulance": {"name": "Ambulance", "cat": "land", "mass": 2600, "engine": 9000, "top": 40, "brake": 17000, "grip": 1.8, "hp": 1500, "price": 0, "siren": true, "color": Color(0.93, 0.93, 0.9)},
	"firetruck": {"name": "Fire Engine", "cat": "land", "mass": 6500, "engine": 16000, "top": 32, "brake": 30000, "grip": 1.7, "hp": 2600, "price": 0, "siren": true, "color": Color(0.75, 0.12, 0.1)},
	"swat": {"name": "Tactical Carrier", "cat": "land", "mass": 4200, "engine": 15000, "top": 40, "brake": 26000, "grip": 1.9, "hp": 3200, "price": 0, "siren": true, "color": Color(0.1, 0.13, 0.2), "armor": 0.5},
	"truck": {"name": "Box Truck", "cat": "land", "mass": 4500, "engine": 11000, "top": 30, "brake": 24000, "grip": 1.6, "hp": 2000, "price": 22000, "traffic": 3, "color": Color(0.9, 0.9, 0.88)},
	"motorcycle": {"name": "Hornet 650", "cat": "land", "mass": 260, "engine": 3300, "top": 62, "brake": 5200, "grip": 2.4, "hp": 450, "price": 11000, "traffic": 2, "bike": true},
	"bicycle": {"name": "Commuter Bike", "cat": "land", "mass": 90, "engine": 420, "top": 13, "brake": 1500, "grip": 2.2, "hp": 200, "price": 400, "bike": true, "silent": true},
	"speedboat": {"name": "Marlin Speedboat", "cat": "water", "mass": 1400, "engine": 15000, "top": 30, "hp": 900, "price": 30000},
	"dinghy": {"name": "Patrol Dinghy", "cat": "water", "mass": 500, "engine": 5000, "top": 22, "hp": 500, "price": 8000},
	"helicopter": {"name": "Skylark Helicopter", "cat": "air", "mass": 1600, "engine": 0, "top": 55, "hp": 900, "price": 120000},
	"police_heli": {"name": "Police Helicopter", "cat": "air", "mass": 1700, "engine": 0, "top": 58, "hp": 1100, "price": 0, "color": Color(0.08, 0.1, 0.16)},
	"plane": {"name": "Sparrow Prop Plane", "cat": "air", "mass": 1100, "engine": 9000, "top": 62, "hp": 700, "price": 90000, "stall": 22.0},
	"jet": {"name": "Kestrel Jet", "cat": "air", "mass": 4500, "engine": 70000, "top": 150, "hp": 1200, "price": 400000, "stall": 42.0},
}
const TRAFFIC_COLORS := [Color(0.75, 0.16, 0.13), Color(0.12, 0.3, 0.6), Color(0.85, 0.85, 0.83), Color(0.1, 0.1, 0.12), Color(0.45, 0.47, 0.5), Color(0.15, 0.42, 0.3),
	Color(0.9, 0.6, 0.12), Color(0.5, 0.75, 0.85), Color(0.42, 0.12, 0.4), Color(0.72, 0.7, 0.55), Color(0.9, 0.9, 0.2), Color(0.3, 0.16, 0.1)]

const PAINTS := {"Signal Red": Color(0.75, 0.1, 0.08), "Deep Blue": Color(0.08, 0.2, 0.55), "Pearl White": Color(0.92, 0.92, 0.9), "Jet Black": Color(0.03, 0.03, 0.04),
	"Gunmetal": Color(0.3, 0.32, 0.35), "Racing Green": Color(0.05, 0.3, 0.16), "Sunburst": Color(0.95, 0.55, 0.05), "Lemon": Color(0.92, 0.85, 0.15),
	"Violet": Color(0.4, 0.12, 0.55), "Hot Pink": Color(0.92, 0.25, 0.55), "Teal": Color(0.1, 0.55, 0.55), "Bronze": Color(0.5, 0.33, 0.18)}
const FINISHES := {"Gloss": [0.25, 0.3], "Matte": [0.85, 0.0], "Metallic": [0.2, 0.85], "Chrome": [0.05, 1.0]}
# category -> options: [id, label, price, effect dictionary]
const UPGRADES := {
	"engine": [["stock", "Stock engine", 0, {}], ["street", "Street tune", 1500, {"engine": 1.15, "top": 1.06}], ["race", "Race tune", 4500, {"engine": 1.32, "top": 1.14}]],
	"turbo": [["none", "No turbo", 0, {}], ["turbo", "Twin-scroll turbo", 5000, {"engine": 1.2, "top": 1.08}]],
	"transmission": [["stock", "Stock gearbox", 0, {}], ["sport", "Close-ratio gearbox", 2500, {"engine": 1.1}]],
	"brakes": [["stock", "Stock brakes", 0, {}], ["sport", "Sport brakes", 1200, {"brake": 1.3}], ["race", "Race brakes", 3000, {"brake": 1.6}]],
	"suspension": [["stock", "Stock suspension", 0, {}], ["lowered", "Lowered sport", 1500, {"grip": 1.1, "ride": -0.06}], ["rally", "Raised rally", 1500, {"sus": 1.3, "ride": 0.1}]],
	"armor": [["none", "No armour", 0, {}], ["half", "Armour plating 50%", 4000, {"armor": 0.5, "mass": 1.08}], ["full", "Armour plating 100%", 9000, {"armor": 0.25, "mass": 1.15}]],
	"tires": [["stock", "Street tyres", 0, {}], ["sport", "Sport compound", 1500, {"grip": 1.12}], ["bulletproof", "Bullet-resistant tyres", 5000, {"bp_tires": true}]],
	"spoiler": [["none", "No spoiler", 0, {}], ["lip", "Lip spoiler", 600, {"part": "Mod_Spoiler1", "down": 0.4}], ["wing", "GT wing", 1600, {"part": "Mod_Spoiler2", "down": 1.0}]],
	"skirts": [["none", "No skirts", 0, {}], ["skirts", "Side skirts", 700, {"part": "Mod_Skirts"}]],
	"hood": [["stock", "Stock hood", 0, {}], ["scoop", "Hood scoop", 900, {"part": "Mod_Scoop"}]],
	"bumper": [["stock", "Stock bumper", 0, {}], ["bullbar", "Bull bar", 800, {"part": "Mod_Bullbar", "ram": 0.6}]],
	"exhaust": [["stock", "Stock exhaust", 0, {}], ["dual", "Dual sport exhaust", 700, {"part": "Mod_Exhaust", "pitch": 0.85}]],
	"wheels": [["std", "Standard", 0, {"wheel": "std"}], ["sport", "Multi-spoke sport", 900, {"wheel": "sport"}], ["classic", "Classic four-spoke", 700, {"wheel": "classic"}], ["offroad", "Off-road", 900, {"wheel": "offroad"}]],
	"horn": [["stock", "Stock horn", 0, {"horn": 1.0}], ["truck", "Truck horn", 300, {"horn": 0.6}], ["shrill", "Shrill horn", 300, {"horn": 1.5}]],
	"lights": [["stock", "Halogen", 0, {"light": Color(1, 0.93, 0.78)}], ["xenon", "Xenon white", 800, {"light": Color(0.82, 0.9, 1.0)}], ["amber", "Rally amber", 600, {"light": Color(1.0, 0.72, 0.25)}]],
	"tint": [["none", "No tint", 0, {"tint": 0.0}], ["dark", "Dark smoke", 400, {"tint": 0.6}], ["limo", "Limo black", 700, {"tint": 1.0}]],
	"plate": [["white", "White plate", 0, {"plate": Color(0.92, 0.9, 0.8)}], ["yellow", "Yellow plate", 150, {"plate": Color(0.95, 0.8, 0.15)}], ["black", "Black plate", 150, {"plate": Color(0.06, 0.06, 0.07)}]],
	"stripe": [["none", "No livery", 0, {}], ["twin", "Twin stripes", 500, {"stripe": true}]],
}

const SKIN_TONES := [Color(0.95, 0.8, 0.68), Color(0.85, 0.64, 0.49), Color(0.72, 0.5, 0.36), Color(0.55, 0.37, 0.26), Color(0.38, 0.25, 0.18)]
const HAIR_COLORS := [Color(0.1, 0.08, 0.07), Color(0.23, 0.15, 0.09), Color(0.5, 0.32, 0.16), Color(0.8, 0.66, 0.36), Color(0.55, 0.55, 0.55), Color(0.6, 0.15, 0.1)]
const CLOTH_COLORS := {"White": Color(0.92, 0.92, 0.9), "Black": Color(0.07, 0.07, 0.08), "Navy": Color(0.12, 0.17, 0.33), "Red": Color(0.7, 0.14, 0.12), "Olive": Color(0.33, 0.38, 0.2),
	"Sky": Color(0.4, 0.62, 0.85), "Mustard": Color(0.82, 0.65, 0.18), "Grey": Color(0.45, 0.46, 0.5), "Teal": Color(0.12, 0.5, 0.5), "Pink": Color(0.9, 0.5, 0.62),
	"Denim": Color(0.2, 0.3, 0.5), "Khaki": Color(0.68, 0.6, 0.42), "Brown": Color(0.35, 0.22, 0.14), "Purple": Color(0.4, 0.2, 0.55)}
const HAIR_STYLES := ["Hair_Short", "Hair_Long", "Hair_Bun", "Hair_Mohawk", "Bald"]
const HATS := ["None", "Cap", "Beanie"]

const SHOP_ITEMS := {
	"food": [["Pita wrap", 12, "heal", 40], ["Full platter", 30, "heal", 100]],
	"market": [["Energy bar", 6, "heal", 20], ["First-aid kit", 60, "heal", 100], ["Parachute", 300, "chute", 1], ["Scuba set", 500, "scuba", 1]],
	"hospital": [["Treatment (full health)", 150, "heal", 200]],
	"gas": [["Patch tyres", 80, "tires", 1], ["Quick body repair (+30%)", 200, "repair", 0.3]],
}
