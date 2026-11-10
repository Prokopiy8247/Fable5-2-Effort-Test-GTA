class_name WeaponDB
extends RefCounted
## Data-driven weapon + attachment definitions (original generic designs).
## Everything gameplay code needs about a weapon comes from these tables.

const SLOT_NAMES := ["Melee", "Handguns", "SMG", "Shotguns", "Rifles", "Sniper", "Heavy", "Thrown"]

const W := {
	&"unarmed": {"name": "Fists", "cls": &"melee", "slot": 0, "model": "", "hold": &"fist", "dmg": 12.0, "heavy": 26.0,
		"rate": 2.4, "range": 1.5, "price": 0, "noise": 3.0},
	&"knife": {"name": "Combat Knife", "cls": &"melee", "slot": 0, "model": "weapons/knife", "hold": &"melee", "dmg": 34.0,
		"heavy": 60.0, "rate": 2.6, "range": 1.6, "price": 120, "noise": 2.0, "silent_kill": true},
	&"bat": {"name": "Baseball Bat", "cls": &"melee", "slot": 0, "model": "weapons/bat", "hold": &"melee", "dmg": 30.0,
		"heavy": 58.0, "rate": 1.6, "range": 2.0, "price": 90, "noise": 5.0, "knock": true},
	&"crowbar": {"name": "Crowbar", "cls": &"melee", "slot": 0, "model": "weapons/crowbar", "hold": &"melee", "dmg": 36.0,
		"heavy": 62.0, "rate": 1.7, "range": 1.8, "price": 110, "noise": 5.0, "knock": true},
	&"nightstick": {"name": "Nightstick", "cls": &"melee", "slot": 0, "model": "weapons/nightstick", "hold": &"melee",
		"dmg": 26.0, "heavy": 48.0, "rate": 2.0, "range": 1.7, "price": 150, "noise": 4.0, "knock": true},
	&"pistol": {"name": "P9 Pistol", "cls": &"pistol", "slot": 1, "model": "weapons/pistol", "hold": &"pistol", "dmg": 24.0,
		"rpm": 380.0, "mag": 12, "reserve": 144, "reload": 1.3, "auto": false, "spread_hip": 2.2, "spread_aim": 0.7,
		"recoil": 1.6, "range": 70.0, "sound": &"shot_pistol", "noise": 70.0, "price": 450, "ammo_price": 40, "zoom": 52.0,
		"driveby": true, "atts": ["suppressor", "extmag", "reddot", "flashlight"]},
	&"revolver": {"name": ".44 Longhorn", "cls": &"pistol", "slot": 1, "model": "weapons/revolver", "hold": &"pistol", "dmg": 62.0,
		"rpm": 110.0, "mag": 6, "reserve": 72, "reload": 2.2, "auto": false, "spread_hip": 2.6, "spread_aim": 0.5,
		"recoil": 5.0, "range": 90.0, "sound": &"shot_revolver", "noise": 85.0, "price": 1400, "ammo_price": 70, "zoom": 50.0,
		"driveby": true, "atts": ["reddot"]},
	&"smg": {"name": "Wasp SMG", "cls": &"smg", "slot": 2, "model": "weapons/smg", "hold": &"pistol", "dmg": 17.0,
		"rpm": 780.0, "mag": 30, "reserve": 300, "reload": 1.7, "auto": true, "spread_hip": 3.0, "spread_aim": 1.2,
		"recoil": 1.0, "range": 55.0, "sound": &"shot_smg", "noise": 65.0, "price": 1250, "ammo_price": 60, "zoom": 52.0,
		"driveby": true, "atts": ["suppressor", "extmag", "reddot", "flashlight", "grip"]},
	&"shotgun_pump": {"name": "Pump Shotgun", "cls": &"shotgun", "slot": 3, "model": "weapons/shotgun_pump", "hold": &"rifle",
		"dmg": 13.0, "pellets": 8, "rpm": 65.0, "mag": 8, "reserve": 64, "reload": 2.6, "auto": false, "spread_hip": 6.0,
		"spread_aim": 4.4, "recoil": 6.0, "range": 32.0, "sound": &"shot_shotgun", "noise": 90.0, "price": 1600,
		"ammo_price": 70, "zoom": 54.0, "atts": ["flashlight", "extmag"]},
	&"shotgun_auto": {"name": "Riot Auto-12", "cls": &"shotgun", "slot": 3, "model": "weapons/shotgun_auto", "hold": &"rifle",
		"dmg": 10.0, "pellets": 8, "rpm": 240.0, "mag": 8, "reserve": 80, "reload": 2.2, "auto": true, "spread_hip": 6.5,
		"spread_aim": 5.0, "recoil": 4.0, "range": 28.0, "sound": &"shot_shotgun", "noise": 90.0, "price": 3200,
		"ammo_price": 90, "zoom": 54.0, "atts": ["flashlight", "extmag", "grip", "reddot"]},
	&"rifle_assault": {"name": "AR-7 Assault Rifle", "cls": &"rifle", "slot": 4, "model": "weapons/rifle_assault", "hold": &"rifle",
		"dmg": 27.0, "rpm": 600.0, "mag": 30, "reserve": 270, "reload": 2.0, "auto": true, "spread_hip": 2.4, "spread_aim": 0.6,
		"recoil": 1.3, "range": 120.0, "sound": &"shot_rifle", "noise": 100.0, "price": 3500, "ammo_price": 90, "zoom": 46.0,
		"atts": ["suppressor", "extmag", "scope", "flashlight", "grip"]},
	&"rifle_carbine": {"name": "Vector Carbine", "cls": &"rifle", "slot": 4, "model": "weapons/rifle_carbine", "hold": &"rifle",
		"dmg": 24.0, "rpm": 720.0, "mag": 30, "reserve": 270, "reload": 1.8, "auto": true, "spread_hip": 2.0, "spread_aim": 0.5,
		"recoil": 1.0, "range": 110.0, "sound": &"shot_rifle", "noise": 95.0, "price": 4200, "ammo_price": 90, "zoom": 46.0,
		"atts": ["suppressor", "extmag", "scope", "flashlight", "grip"]},
	&"rifle_marksman": {"name": "Ranger DMR", "cls": &"sniper", "slot": 5, "model": "weapons/rifle_marksman", "hold": &"rifle",
		"dmg": 55.0, "rpm": 220.0, "mag": 10, "reserve": 80, "reload": 2.3, "auto": false, "spread_hip": 2.8, "spread_aim": 0.15,
		"recoil": 3.0, "range": 220.0, "sound": &"shot_rifle", "noise": 110.0, "price": 5200, "ammo_price": 120, "zoom": 26.0,
		"builtin_scope": "att_scope_4x", "atts": ["suppressor", "extmag", "flashlight"]},
	&"rifle_sniper": {"name": "Longbow Sniper", "cls": &"sniper", "slot": 5, "model": "weapons/rifle_sniper", "hold": &"rifle",
		"dmg": 130.0, "rpm": 45.0, "mag": 5, "reserve": 40, "reload": 2.8, "auto": false, "spread_hip": 4.0, "spread_aim": 0.02,
		"recoil": 7.0, "range": 450.0, "sound": &"shot_sniper", "noise": 130.0, "price": 7500, "ammo_price": 160, "zoom": 11.0,
		"scoped": true, "builtin_scope": "att_scope_sniper", "atts": ["suppressor"]},
	&"launcher_rocket": {"name": "Rocket Launcher", "cls": &"heavy", "slot": 6, "model": "weapons/launcher_rocket", "hold": &"launcher",
		"dmg": 0.0, "rpm": 28.0, "mag": 1, "reserve": 10, "reload": 2.8, "auto": false, "spread_hip": 1.5, "spread_aim": 0.3,
		"recoil": 6.0, "range": 300.0, "sound": &"shot_rocket", "noise": 110.0, "price": 9000, "ammo_price": 600, "zoom": 44.0,
		"projectile": "rocket", "atts": []},
	&"launcher_grenade": {"name": "Thumper GL", "cls": &"heavy", "slot": 6, "model": "weapons/launcher_grenade", "hold": &"rifle",
		"dmg": 0.0, "rpm": 85.0, "mag": 6, "reserve": 24, "reload": 3.0, "auto": false, "spread_hip": 2.0, "spread_aim": 0.6,
		"recoil": 4.0, "range": 120.0, "sound": &"shot_launcher", "noise": 80.0, "price": 8000, "ammo_price": 500, "zoom": 46.0,
		"projectile": "grenade40", "atts": []},
	&"grenade": {"name": "Frag Grenade", "cls": &"thrown", "slot": 7, "model": "weapons/grenade", "hold": &"thrown", "dmg": 0.0,
		"rpm": 40.0, "mag": 1, "reserve": 10, "reload": 0.0, "auto": false, "range": 30.0, "sound": &"grenade_pin", "noise": 6.0,
		"price": 250, "ammo_price": 250, "projectile": "grenade", "driveby": true},
}

const ORDER: Array[StringName] = [&"unarmed", &"knife", &"bat", &"crowbar", &"nightstick", &"pistol", &"revolver", &"smg",
	&"shotgun_pump", &"shotgun_auto", &"rifle_assault", &"rifle_carbine", &"rifle_marksman", &"rifle_sniper",
	&"launcher_rocket", &"launcher_grenade", &"grenade"]

## Attachments: gameplay modifiers + the model mounted on the weapon.
const ATT := {
	"suppressor": {"name": "Suppressor", "price": 600, "model": "weapons/att/att_suppressor", "marker": "suppressor",
		"noise": 0.16, "dmg": 0.93, "range": 0.9},
	"extmag": {"name": "Extended Magazine", "price": 450, "mag": 1.5},
	"reddot": {"name": "Reflex Sight", "price": 500, "model": "weapons/att/att_scope_reddot", "marker": "scope", "spread_aim": 0.8, "zoom": -5.0},
	"scope": {"name": "4x Scope", "price": 900, "model": "weapons/att/att_scope_4x", "marker": "scope", "spread_aim": 0.7, "zoom_to": 26.0},
	"grip": {"name": "Foregrip", "price": 400, "model": "weapons/att/att_grip", "marker": "under", "recoil": 0.68, "spread": 0.85},
	"flashlight": {"name": "Flashlight", "price": 250, "model": "weapons/att/att_flashlight", "marker": "under", "light": true},
}

const TINTS := [
	{"name": "Gunmetal", "metal": "3a3d42", "furn": "1c1d20", "price": 0},
	{"name": "Blackout", "metal": "17181b", "furn": "121316", "price": 200},
	{"name": "Desert Tan", "metal": "a8956b", "furn": "6b5a3a", "price": 350},
	{"name": "Olive", "metal": "4c5a3a", "furn": "2e3528", "price": 350},
	{"name": "Chrome", "metal": "d5d9de", "furn": "2e3035", "price": 900},
	{"name": "Gold", "metal": "d9a520", "furn": "3a2a14", "price": 2500},
	{"name": "Neon Pink", "metal": "f08ab8", "furn": "2e3035", "price": 800},
	{"name": "Tide Blue", "metal": "2f6fd0", "furn": "f2f0ea", "price": 800},
	{"name": "Crimson", "metal": "8f2a25", "furn": "17181b", "price": 800},
]

static func get_w(id: StringName) -> Dictionary:
	return W.get(id, W[&"unarmed"])

static func is_gun(id: StringName) -> bool:
	var c: StringName = get_w(id)["cls"]
	return c != &"melee" and c != &"thrown"

static func att_for(id: StringName, att: String) -> String:
	## model path of an attachment as mounted on a given weapon (bigger suppressor on long guns)
	var a: Dictionary = ATT.get(att, {})
	var m := String(a.get("model", ""))
	if att == "suppressor" and get_w(id)["hold"] == &"rifle":
		m = "weapons/att/att_suppressor_large"
	return m
