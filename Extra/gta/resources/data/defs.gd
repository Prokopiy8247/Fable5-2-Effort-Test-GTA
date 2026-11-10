class_name Defs
## Data-driven registries: vehicles, weapons, ammo, weapon mods, vehicle mods, clothing, shop stock.

const VEHICLES := {
	"compact": {"name": "Pico", "kind": "car", "mass": 1050.0, "accel": 6.8, "top": 37.0, "grip": 1.05, "brake": 11.0, "steer": 0.62, "health": 800.0, "price": 9000, "traffic": 1.4, "roll": 0.9,
		"colors": ["e0563a", "3d7ea6", "f2efe8", "6fb2ad", "f2b705", "8a94a0"]},
	"sedan": {"name": "Meridian", "kind": "car", "mass": 1380.0, "accel": 6.4, "top": 42.0, "grip": 1.0, "brake": 10.5, "steer": 0.58, "health": 950.0, "price": 16000, "traffic": 1.6, "roll": 1.0,
		"colors": ["3d7ea6", "1b1d21", "e9e4d8", "8a94a0", "7a1f1f", "2f6b4f", "c9b28a"]},
	"sports": {"name": "Vanta GT", "kind": "car", "mass": 1250.0, "accel": 10.5, "top": 64.0, "grip": 1.3, "brake": 14.0, "steer": 0.52, "health": 850.0, "price": 95000, "traffic": 0.35, "roll": 0.7,
		"colors": ["f2b705", "c9302a", "1b1d21", "f2efe8", "2a67c9", "e9792a"], "convertible": true, "rwd": true},
	"muscle": {"name": "Brawler 440", "kind": "car", "mass": 1560.0, "accel": 9.2, "top": 56.0, "grip": 1.05, "brake": 10.5, "steer": 0.55, "health": 1050.0, "price": 42000, "traffic": 0.5, "roll": 0.95,
		"colors": ["7d2a8c", "c9302a", "1b1d21", "e9792a", "2f62b3", "f0c21c"], "rwd": true},
	"suv": {"name": "Ridgeline", "kind": "car", "mass": 2050.0, "accel": 6.0, "top": 43.0, "grip": 0.98, "brake": 9.5, "steer": 0.55, "health": 1300.0, "price": 38000, "traffic": 0.9, "roll": 1.25,
		"colors": ["2f6b4f", "1b1d21", "e9e4d8", "5d6f7d", "7a1f1f", "c9b28a"]},
	"pickup": {"name": "Dustcutter", "kind": "car", "mass": 2150.0, "accel": 5.8, "top": 40.0, "grip": 0.95, "brake": 9.0, "steer": 0.55, "health": 1350.0, "price": 28000, "traffic": 0.8, "roll": 1.3,
		"colors": ["c9772a", "e9e4d8", "2a67c9", "7a1f1f", "3a3f2c", "8a94a0"], "rwd": true},
	"van": {"name": "Hauler", "kind": "car", "mass": 2300.0, "accel": 4.9, "top": 36.0, "grip": 0.92, "brake": 8.5, "steer": 0.55, "health": 1400.0, "price": 24000, "traffic": 0.7, "roll": 1.45,
		"colors": ["e9e4d8", "8a94a0", "3d7ea6", "c9b28a", "f2b705"]},
	"police": {"name": "Enforcer Cruiser", "kind": "car", "mass": 1650.0, "accel": 8.8, "top": 54.0, "grip": 1.18, "brake": 13.0, "steer": 0.58, "health": 1300.0, "price": 0, "traffic": 0.0, "roll": 0.95,
		"siren": true, "emergency": "police"},
	"taxi": {"name": "Cabbie", "kind": "car", "mass": 1420.0, "accel": 6.4, "top": 42.0, "grip": 1.0, "brake": 10.5, "steer": 0.58, "health": 1000.0, "price": 0, "traffic": 0.55, "roll": 1.0},
	"ambulance": {"name": "Lifeline Ambulance", "kind": "car", "mass": 3200.0, "accel": 5.4, "top": 40.0, "grip": 0.95, "brake": 9.0, "steer": 0.52, "health": 1700.0, "price": 0, "traffic": 0.0, "roll": 1.5,
		"siren": true, "emergency": "medic"},
	"truck": {"name": "Mule Box Truck", "kind": "car", "mass": 5200.0, "accel": 3.8, "top": 31.0, "grip": 0.9, "brake": 7.5, "steer": 0.50, "health": 2200.0, "price": 45000, "traffic": 0.45, "roll": 1.7,
		"colors": ["2a67c9", "c9302a", "3d8f4f", "e9792a", "8a94a0"], "rwd": true},
	"firetruck": {"name": "Blaze Engine", "kind": "car", "mass": 9000.0, "accel": 3.6, "top": 31.0, "grip": 0.9, "brake": 7.0, "steer": 0.48, "health": 3200.0, "price": 0, "traffic": 0.0, "roll": 1.6,
		"siren": true, "emergency": "fire", "rwd": true},
	"swat": {"name": "Bulwark Tactical", "kind": "car", "mass": 4800.0, "accel": 5.0, "top": 38.0, "grip": 0.98, "brake": 9.0, "steer": 0.50, "health": 3400.0, "price": 0, "traffic": 0.0, "roll": 1.5,
		"siren": true, "emergency": "police", "armored": true},
	"motorcycle": {"name": "Wasp 600", "kind": "bike", "mass": 240.0, "accel": 11.5, "top": 58.0, "grip": 1.15, "brake": 13.0, "steer": 0.50, "health": 450.0, "price": 14000, "traffic": 0.35, "roll": 0.6,
		"colors": ["c9302a", "1b1d21", "2a67c9", "f2b705", "3d8f4f"]},
	"bicycle": {"name": "Cruiser Bike", "kind": "bike", "mass": 90.0, "accel": 3.4, "top": 11.5, "grip": 1.0, "brake": 9.0, "steer": 0.55, "health": 200.0, "price": 600, "traffic": 0.0, "roll": 0.6,
		"colors": ["2f9c95", "c9302a", "f2b705", "e9e4d8"], "pedal": true},
	"speedboat": {"name": "Marlin 21", "kind": "boat", "mass": 1400.0, "accel": 8.5, "top": 30.0, "health": 900.0, "price": 60000, "colors": ["2a67c9", "c9302a", "2f9c95", "f2b705", "1b1d21"]},
	"policeboat": {"name": "Harbor Patrol", "kind": "boat", "mass": 1500.0, "accel": 9.0, "top": 31.0, "health": 1100.0, "price": 0, "siren": true, "emergency": "police"},
	"helicopter": {"name": "Kestrel Utility", "kind": "heli", "mass": 1500.0, "accel": 12.0, "top": 48.0, "health": 1000.0, "price": 250000, "colors": ["e9792a", "2a67c9", "c9302a", "f2efe8", "1b1d21"]},
	"policeheli": {"name": "Skywatch", "kind": "heli", "mass": 1550.0, "accel": 12.5, "top": 50.0, "health": 1200.0, "price": 0, "emergency": "police"},
	"plane": {"name": "Skylark 172", "kind": "plane", "mass": 1100.0, "accel": 12.5, "top": 66.0, "takeoff": 27.0, "health": 800.0, "price": 180000, "colors": ["d63a2f", "2a67c9", "2f9c95", "f2b705"]},
	"jet": {"name": "Stiletto", "kind": "plane", "mass": 3600.0, "accel": 19.0, "top": 118.0, "takeoff": 42.0, "health": 1200.0, "price": 900000, "colors": ["8d9399", "1b1d21", "2f62b3", "c9302a"], "jet": true},
}
const VEHICLE_ORDER := ["compact", "sedan", "sports", "muscle", "suv", "pickup", "van", "taxi", "truck", "police", "ambulance", "firetruck", "swat",
	"motorcycle", "bicycle", "speedboat", "policeboat", "helicopter", "policeheli", "plane", "jet"]

const WEAPONS := {
	"fists": {"name": "Fists", "slot": "melee", "type": "melee", "dmg": 14.0, "range": 1.5, "rate": 0.42, "model": "", "price": 0},
	"knife": {"name": "Field Knife", "slot": "melee", "type": "melee", "dmg": 46.0, "range": 1.5, "rate": 0.36, "model": "w_knife", "price": 120},
	"bat": {"name": "Ash Bat", "slot": "melee", "type": "melee", "dmg": 36.0, "range": 1.9, "rate": 0.62, "model": "w_bat", "price": 90},
	"crowbar": {"name": "Crowbar", "slot": "melee", "type": "melee", "dmg": 40.0, "range": 1.8, "rate": 0.60, "model": "w_crowbar", "price": 110},
	"nightstick": {"name": "Nightstick", "slot": "melee", "type": "melee", "dmg": 28.0, "range": 1.7, "rate": 0.5, "model": "w_nightstick", "price": 150},
	"pistol": {"name": "P9 Sidearm", "slot": "handgun", "type": "pistol", "model": "w_pistol", "dmg": 24.0, "rate": 0.19, "auto": false, "mag": 12, "ammo": "pistol", "spread": 1.1,
		"recoil": 1.5, "range": 110.0, "reload": 1.3, "noise": 75.0, "price": 450, "driveby": true, "mods": ["suppressor", "flashlight", "extmag"], "snd": "shot_pistol"},
	"revolver": {"name": "Magnus .44", "slot": "handgun", "type": "pistol", "model": "w_revolver", "dmg": 60.0, "rate": 0.52, "auto": false, "mag": 6, "ammo": "pistol", "spread": 0.9,
		"recoil": 4.6, "range": 130.0, "reload": 2.2, "noise": 95.0, "price": 1500, "driveby": true, "mods": ["scope"], "snd": "shot_heavy"},
	"smg": {"name": "Stinger SMG", "slot": "smg", "type": "smg", "model": "w_smg", "dmg": 17.0, "rate": 0.075, "auto": true, "mag": 30, "ammo": "smg", "spread": 2.3,
		"recoil": 0.85, "range": 90.0, "reload": 1.7, "noise": 80.0, "price": 1900, "driveby": true, "mods": ["suppressor", "flashlight", "scope", "grip", "extmag"], "snd": "shot_smg"},
	"shotgun": {"name": "Breacher 12", "slot": "shotgun", "type": "rifle", "model": "w_shotgun", "dmg": 13.0, "pellets": 8, "rate": 0.85, "auto": false, "mag": 6, "ammo": "shotgun", "spread": 5.2,
		"recoil": 6.0, "range": 45.0, "reload": 2.6, "noise": 100.0, "price": 1500, "mods": ["flashlight", "extmag"], "snd": "shot_shotgun"},
	"autoshotgun": {"name": "Sweeper A12", "slot": "shotgun", "type": "rifle", "model": "w_autoshotgun", "dmg": 11.0, "pellets": 7, "rate": 0.28, "auto": true, "mag": 8, "ammo": "shotgun", "spread": 6.0,
		"recoil": 4.2, "range": 40.0, "reload": 2.8, "noise": 100.0, "price": 4200, "mods": ["flashlight", "scope", "grip", "extmag"], "snd": "shot_shotgun"},
	"rifle": {"name": "AR-7 Vandal", "slot": "rifle", "type": "rifle", "model": "w_rifle", "dmg": 30.0, "rate": 0.1, "auto": true, "mag": 30, "ammo": "rifle", "spread": 1.25,
		"recoil": 1.2, "range": 220.0, "reload": 2.0, "noise": 95.0, "price": 3500, "mods": ["suppressor", "flashlight", "scope", "grip", "extmag"], "snd": "shot_rifle"},
	"carbine": {"name": "Kestrel C Bullpup", "slot": "rifle", "type": "rifle", "model": "w_carbine", "dmg": 26.0, "rate": 0.085, "auto": true, "mag": 30, "ammo": "rifle", "spread": 1.6,
		"recoil": 1.0, "range": 180.0, "reload": 1.9, "noise": 95.0, "price": 3000, "mods": ["suppressor", "flashlight", "scope", "grip", "extmag"], "snd": "shot_rifle"},
	"marksman": {"name": "Longbow DMR", "slot": "rifle", "type": "rifle", "model": "w_marksman", "dmg": 64.0, "rate": 0.36, "auto": false, "mag": 10, "ammo": "sniper", "spread": 0.3,
		"recoil": 3.0, "range": 350.0, "reload": 2.3, "noise": 105.0, "price": 5200, "zoom": 24.0, "mods": ["suppressor", "grip", "extmag"], "snd": "shot_heavy"},
	"sniper": {"name": "Widow LR", "slot": "sniper", "type": "rifle", "model": "w_sniper", "dmg": 160.0, "rate": 1.25, "auto": false, "mag": 5, "ammo": "sniper", "spread": 0.04,
		"recoil": 6.5, "range": 600.0, "reload": 2.8, "noise": 120.0, "price": 8500, "zoom": 9.0, "scoped": true, "mods": ["suppressor", "extmag"], "snd": "shot_sniper"},
	"rpg": {"name": "Hornet Launcher", "slot": "heavy", "type": "rpg", "model": "w_rpg", "dmg": 420.0, "radius": 7.5, "rate": 1.4, "auto": false, "mag": 1, "ammo": "rocket", "spread": 0.2,
		"recoil": 7.0, "range": 300.0, "reload": 2.4, "noise": 120.0, "price": 12000, "projectile": "rocket", "snd": "shot_rocket"},
	"glauncher": {"name": "Thumper GL", "slot": "heavy", "type": "rifle", "model": "w_glauncher", "dmg": 260.0, "radius": 6.0, "rate": 0.7, "auto": false, "mag": 6, "ammo": "grenade40", "spread": 0.6,
		"recoil": 5.0, "range": 150.0, "reload": 3.0, "noise": 90.0, "price": 9000, "projectile": "grenade40", "snd": "shot_thump"},
	"grenade": {"name": "Frag Grenade", "slot": "throwable", "type": "throw", "model": "w_grenade", "dmg": 300.0, "radius": 7.0, "rate": 1.0, "mag": 1, "ammo": "grenade", "price": 250,
		"projectile": "grenade", "driveby": true, "snd": "throw"},
	"molotov": {"name": "Firebottle", "slot": "throwable", "type": "throw", "model": "w_molotov", "dmg": 60.0, "radius": 4.5, "rate": 1.0, "mag": 1, "ammo": "molotov", "price": 150,
		"projectile": "molotov", "driveby": true, "snd": "throw"},
}
const WEAPON_ORDER := ["fists", "knife", "bat", "crowbar", "nightstick", "pistol", "revolver", "smg", "shotgun", "autoshotgun", "rifle", "carbine", "marksman", "sniper", "rpg", "glauncher", "grenade", "molotov"]
const SLOTS := ["melee", "handgun", "smg", "shotgun", "rifle", "sniper", "heavy", "throwable"]
const SLOT_NAMES := {"melee": "Melee", "handgun": "Handguns", "smg": "SMG", "shotgun": "Shotguns", "rifle": "Rifles", "sniper": "Sniper", "heavy": "Heavy", "throwable": "Thrown"}
const AMMO := {"pistol": {"name": "Pistol rounds", "box": 24, "price": 40, "max": 240}, "smg": {"name": "SMG rounds", "box": 60, "price": 70, "max": 480},
	"shotgun": {"name": "Shells", "box": 12, "price": 60, "max": 96}, "rifle": {"name": "Rifle rounds", "box": 60, "price": 110, "max": 480},
	"sniper": {"name": "Long rounds", "box": 10, "price": 150, "max": 80}, "rocket": {"name": "Rockets", "box": 2, "price": 900, "max": 12},
	"grenade40": {"name": "40mm grenades", "box": 6, "price": 800, "max": 24}, "grenade": {"name": "Frag grenades", "box": 1, "price": 250, "max": 12},
	"molotov": {"name": "Firebottles", "box": 1, "price": 150, "max": 12}}
const WEAPON_MODS := {
	"suppressor": {"name": "Suppressor", "price": 650, "node": "Att_Suppressor", "desc": "Much quieter shots, slightly less damage"},
	"flashlight": {"name": "Flashlight", "price": 200, "node": "Att_Flashlight", "desc": "Lights up dark places while aiming"},
	"scope": {"name": "Optic", "price": 900, "node": "Att_Scope", "desc": "Tighter zoom and spread when aiming"},
	"grip": {"name": "Foregrip", "price": 500, "node": "Att_Grip", "desc": "Less recoil and spread"},
	"extmag": {"name": "Extended magazine", "price": 450, "node": "Att_ExtMag", "desc": "+60% magazine capacity"},
}
const WEAPON_TINTS := {"Factory": Color(0, 0, 0, 0), "Desert": Color("b89a6a"), "Olive": Color("4c5a36"), "Crimson": Color("8a1f1f"), "Gold": Color("d9b648"), "Arctic": Color("dfe6ea"), "Violet": Color("6a3a9a")}

# Vehicle customisation (Torque Bay Customs). "node" = Blender-authored part toggled on, "hide" = stock part hidden.
const CAR_MODS := {
	"spoiler": {"name": "Spoiler", "options": [{"name": "None", "price": 0}, {"name": "Ducktail", "price": 900, "node": "Mod_Spoiler_1", "downforce": 0.25},
		{"name": "GT Wing", "price": 2400, "node": "Mod_Spoiler_2", "downforce": 0.6}]},
	"bumper_f": {"name": "Front bumper", "options": [{"name": "Stock", "price": 0}, {"name": "Splitter", "price": 1400, "node": "Mod_Bumper_F_1", "hide": "Bumper_F"}]},
	"bumper_r": {"name": "Rear bumper", "options": [{"name": "Stock", "price": 0}, {"name": "Diffuser", "price": 1300, "node": "Mod_Bumper_R_1", "hide": "Bumper_R"}]},
	"hood": {"name": "Hood", "options": [{"name": "Stock", "price": 0}, {"name": "Ram scoop", "price": 1100, "node": "Mod_Hood_1"}, {"name": "Vented", "price": 950, "node": "Mod_Hood_2"}]},
	"roof": {"name": "Roof", "options": [{"name": "Stock", "price": 0}, {"name": "Roof scoop", "price": 800, "node": "Mod_Roof_1"}]},
	"grille": {"name": "Grille", "options": [{"name": "Stock", "price": 0}, {"name": "Chrome bars", "price": 600, "node": "Mod_Grille_1", "hide": "Grille"}]},
	"skirts": {"name": "Side skirts", "options": [{"name": "None", "price": 0}, {"name": "Street skirts", "price": 850, "node": "Mod_Skirts_1"}]},
	"exhaust": {"name": "Exhaust", "options": [{"name": "Stock", "price": 0}, {"name": "Quad tips", "price": 750, "node": "Mod_Exhaust_1", "hide": "Exhaust", "sound": 0.85}]},
	"livery": {"name": "Livery", "options": [{"name": "None", "price": 0}, {"name": "Twin stripes", "price": 700, "node": "Mod_Stripe_1"}, {"name": "Center band", "price": 700, "node": "Mod_Stripe_2"}]},
	"wheels": {"name": "Wheels", "options": [{"name": "Stock", "price": 0}, {"name": "Five spoke", "price": 1200, "rim": 0}, {"name": "Split six", "price": 1400, "rim": 1},
		{"name": "Steelies", "price": 500, "rim": 2}, {"name": "Deep dish", "price": 1800, "rim": 3}, {"name": "Bruiser", "price": 1600, "rim": 4}]},
	"engine": {"name": "Engine tune", "perf": true, "options": [{"name": "Stock", "price": 0}, {"name": "Stage 1", "price": 3000, "accel": 1.12, "top": 1.05},
		{"name": "Stage 2", "price": 7000, "accel": 1.25, "top": 1.1}, {"name": "Stage 3", "price": 14000, "accel": 1.4, "top": 1.16}]},
	"turbo": {"name": "Turbo", "perf": true, "options": [{"name": "None", "price": 0}, {"name": "Turbocharger", "price": 12000, "accel": 1.22, "top": 1.06}]},
	"transmission": {"name": "Transmission", "perf": true, "options": [{"name": "Stock", "price": 0}, {"name": "Street", "price": 2500, "accel": 1.07}, {"name": "Race", "price": 6000, "accel": 1.15}]},
	"brakes": {"name": "Brakes", "perf": true, "options": [{"name": "Stock", "price": 0}, {"name": "Sport", "price": 1800, "brake": 1.2}, {"name": "Race", "price": 4200, "brake": 1.45}]},
	"suspension": {"name": "Suspension", "perf": true, "options": [{"name": "Stock", "price": 0}, {"name": "Lowered", "price": 2000, "drop": 0.04, "grip": 1.06, "rollk": 0.8},
		{"name": "Competition", "price": 4500, "drop": 0.07, "grip": 1.12, "rollk": 0.6}]},
	"armor": {"name": "Armor", "perf": true, "options": [{"name": "None", "price": 0}, {"name": "40%", "price": 5000, "armor": 0.75, "mass": 1.05}, {"name": "80%", "price": 12000, "armor": 0.5, "mass": 1.1},
		{"name": "100%", "price": 22000, "armor": 0.35, "mass": 1.15}]},
	"tires": {"name": "Tires", "perf": true, "options": [{"name": "Stock", "price": 0}, {"name": "Sport compound", "price": 2200, "grip": 1.08}, {"name": "Bullet-resistant", "price": 9000, "bulletproof": true}]},
	"tint": {"name": "Window tint", "options": [{"name": "None", "price": 0, "alpha": 0.5}, {"name": "Light smoke", "price": 300, "alpha": 0.7}, {"name": "Dark smoke", "price": 500, "alpha": 0.86}, {"name": "Limo", "price": 800, "alpha": 0.96}]},
	"lights": {"name": "Headlights", "options": [{"name": "Stock", "price": 0, "color": "fff0cc"}, {"name": "Xenon", "price": 700, "color": "cfe4ff"}, {"name": "Amber", "price": 500, "color": "ffb84a"}, {"name": "Violet", "price": 900, "color": "c08aff"}]},
	"horn": {"name": "Horn", "options": [{"name": "Stock", "price": 0, "snd": "horn"}, {"name": "Truck horn", "price": 400, "snd": "horn_truck"}, {"name": "Melody", "price": 900, "snd": "horn_melody"}]},
	"plate": {"name": "Plate", "options": [{"name": "White", "price": 0, "color": "e9e6da"}, {"name": "Yellow", "price": 150, "color": "f0c21c"}, {"name": "Black", "price": 250, "color": "1b1d21"}, {"name": "Blue", "price": 250, "color": "2a67c9"}]},
}
const CAR_MOD_ORDER := ["spoiler", "bumper_f", "bumper_r", "hood", "roof", "grille", "skirts", "exhaust", "livery", "wheels", "tint", "lights", "horn", "plate",
	"engine", "turbo", "transmission", "brakes", "suspension", "armor", "tires"]
const PAINTS := ["c9302a", "e0563a", "e9792a", "f2b705", "f0e04a", "8fbf4f", "3d8f4f", "2f6b4f", "2f9c95", "3fb8d8", "3d7ea6", "2a67c9", "1f2f6b", "7d2a8c", "c04f9a", "ff8fb8",
	"f2efe8", "c9ccd0", "8a94a0", "4a4f57", "1b1d21", "5d3f26", "c9b28a", "7a1f1f"]
const FINISHES := {"Gloss": {"rough": 0.22, "metal": 0.3, "price": 400}, "Metallic": {"rough": 0.28, "metal": 0.75, "price": 900}, "Matte": {"rough": 0.85, "metal": 0.1, "price": 700},
	"Chrome": {"rough": 0.06, "metal": 1.0, "price": 4000}, "Pearl": {"rough": 0.18, "metal": 0.55, "price": 1500}}

const CLOTHES := {
	"shirt": {"name": "Tops", "price": 60, "colors": ["3d7ea6", "b03a2e", "2f6b4f", "f2b705", "e9e4d8", "1b1d21", "7d2a8c", "e9792a", "4c5a36", "2f9c95", "ff8fb8", "c9b28a"]},
	"pants": {"name": "Trousers", "price": 80, "colors": ["2d3142", "1b1d21", "4a5a7a", "6b5a45", "8a8f96", "3a3f2c", "c9b28a", "7a1f1f"]},
	"shoes": {"name": "Shoes", "price": 90, "colors": ["1d1b1a", "e8e4da", "5a3a22", "b03a2e", "2d3142", "f2b705"]},
	"hat": {"name": "Hats", "price": 70, "parts": ["", "Hat_Cap", "Hat_Beanie", "Hat_Fedora", "Hat_Hard", "Hat_Mask"], "labels": ["None", "Ball cap", "Beanie", "Fedora", "Hard hat", "Ski mask"]},
	"glasses": {"name": "Eyewear", "price": 50, "parts": ["", "Glasses", "Shades"], "labels": ["None", "Glasses", "Shades"]},
}
const HAIR := {"labels": ["Bald", "Short", "Quiff", "Long", "Ponytail", "Mohawk", "Afro", "Bun"], "parts": ["", "Hair_Short", "Hair_Quiff", "Hair_Long", "Hair_Pony", "Hair_Mohawk", "Hair_Afro", "Hair_Bun"],
	"beard_labels": ["Clean", "Beard", "Mustache"], "beards": ["", "Beard", "Mustache"], "colors": ["2b1d14", "111111", "5a3a22", "8a5a2b", "c9a25a", "7a7a7a", "a83a2a", "e8e0d0", "3fb8d8", "ff4fa3"], "price": 40}
const STORE := [{"id": "snack", "name": "Meat pie (+30 health)", "price": 12}, {"id": "soda", "name": "Fizz cola (+15 health)", "price": 5},
	{"id": "medkit", "name": "First aid kit (full health)", "price": 120}, {"id": "armor", "name": "Body armor", "price": 800}, {"id": "parachute", "name": "Parachute", "price": 500},
	{"id": "scuba", "name": "Scuba set", "price": 1500}]
