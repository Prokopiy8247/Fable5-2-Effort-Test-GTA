extends RefCounted
## Registrar for Registry kinds "weapons" (WeaponSpec) and "attachments" (AttachmentSpec).
## Called once at startup by the Registry autoload: register_all(Registry).
##
## All balance numbers live in this file. docs/WEAPONS.md holds the resulting balance table
## (printed by the test `wpn_core`). Names are original, generic designs for Halcyon Bay.

const FINISHES: Array[String] = ["finish_sand", "finish_olive", "finish_teal", "finish_coral", "finish_gold"]


static func register_all(registry: Node) -> void:
	for a in _attachments():
		registry.register("attachments", a)
	for w in _weapons():
		registry.register("weapons", w)


# --- attachments ----------------------------------------------------------------------------------

static func _att(id: String, display_name: String, kind: String, price: int, node_name: String,
		description: String, props: Dictionary = {}) -> AttachmentSpec:
	var a := AttachmentSpec.new()
	a.id = id
	a.display_name = display_name
	a.kind = kind
	a.price = price
	a.node_name = node_name
	a.description = description
	for k: String in props:
		a.set(k, props[k])
	return a


static func _attachments() -> Array:
	return [
		_att("suppressor", "Suppressor", "suppressor", 450, "Att_Suppressor",
			"Cuts the report to a cough. Slightly less punch and reach.",
			{"noise_mult": 0.17, "damage_mult": 0.94, "range_mult": 0.9, "recoil_mult": 0.95, "suppresses": true}),
		_att("scope", "Optic", "scope", 600, "Att_Scope",
			"Magnified sight: tighter zoom and steadier aimed fire.",
			{"aim_fov_mult": 0.62, "aim_spread_mult": 0.8, "equip_mult": 1.1}),
		_att("flashlight", "Weapon Light", "flashlight", 200, "Att_Flashlight",
			"Barrel-mounted lamp for dark corners. Toggle while the weapon is drawn.",
			{"is_light": true}),
		_att("grip", "Foregrip", "grip", 380, "Att_Grip",
			"Tames climb and keeps bursts together.",
			{"recoil_mult": 0.75, "bloom_mult": 0.8, "moving_spread_mult": 0.8}),
		_att("ext_mag", "Extended Magazine", "ext_mag", 420, "Att_ExtMag",
			"Half again as many rounds; a touch slower to swap.",
			{"mag_mult": 1.5, "reload_mult": 1.1}),
		_att("finish_sand", "Dune Finish", "finish", 150, "", "Sun-bleached sand coat.",
			{"color": Color(0.80, 0.69, 0.50)}),
		_att("finish_olive", "Palm Finish", "finish", 150, "", "Matte olive coat.",
			{"color": Color(0.36, 0.43, 0.26)}),
		_att("finish_teal", "Lagoon Finish", "finish", 250, "", "Halcyon Bay teal.",
			{"color": Color(0.10, 0.62, 0.60)}),
		_att("finish_coral", "Coral Finish", "finish", 250, "", "Loud coral coat.",
			{"color": Color(0.95, 0.42, 0.36)}),
		_att("finish_gold", "Sunburst Finish", "finish", 900, "", "Polished sun-yellow plating.",
			{"color": Color(0.98, 0.78, 0.22), "finish_metallic": 0.85, "finish_roughness": 0.28}),
	]


# --- weapons --------------------------------------------------------------------------------------

static func _weapon(id: String, display_name: String, slot: String, fire_mode: String,
		description: String, props: Dictionary) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = id
	w.display_name = display_name
	w.slot = slot
	w.fire_mode = fire_mode
	w.description = description
	w.model_path = "" if id == "fists" else "%s/%s.glb" % [WeaponSpec.MODEL_DIR, id]
	for k: String in props:
		if k == "attachments" or k == "builtin_nodes":
			var list: Array[String] = []
			for a: Variant in props[k]:
				list.append(str(a))
			w.set(k, list)
		else:
			w.set(k, props[k])
	return w


static func _with_finishes(list: Array) -> Array:
	var out := list.duplicate()
	out.append_array(FINISHES)
	return out


static func _weapons() -> Array:
	var out: Array = []

	# ---- melee -------------------------------------------------------------------------------
	out.append(_weapon("fists", "Fists", "melee", "melee", "Always with you.", {
		"damage": 14.0, "rpm": 115.0, "melee_range": 1.5, "melee_heavy_mult": 2.0, "melee_knockdown": 0.55,
		"melee_sound_hit": "punch_hit", "impulse": 3.0, "noise_radius": 5.0, "weapon_pose": "none",
		"aim_fov": 60.0, "equip_time": 0.15, "tracer": false, "shake": 0.03, "headshot_mult": 1.0,
		"limb_mult": 1.0, "price": 0,
	}))
	out.append(_weapon("knife", "Dockside Knife", "melee", "melee", "Fast, quiet, close.", {
		"damage": 36.0, "rpm": 125.0, "melee_range": 1.6, "melee_heavy_mult": 1.7, "melee_knockdown": 0.15,
		"melee_sound_hit": "knife_hit", "impulse": 1.5, "noise_radius": 3.0, "weapon_pose": "melee",
		"aim_fov": 60.0, "equip_time": 0.25, "tracer": false, "shake": 0.03, "headshot_mult": 1.0,
		"limb_mult": 1.0, "price": 180, "vehicle_damage_mult": 0.3,
	}))
	out.append(_weapon("bat", "Ballpark Bat", "melee", "melee", "Long reach, puts people on the ground.", {
		"damage": 30.0, "rpm": 85.0, "melee_range": 2.0, "melee_heavy_mult": 1.9, "melee_knockdown": 0.85,
		"melee_sound_hit": "melee_hit", "impulse": 7.0, "noise_radius": 7.0, "weapon_pose": "melee",
		"aim_fov": 60.0, "equip_time": 0.3, "tracer": false, "shake": 0.05, "headshot_mult": 1.0,
		"limb_mult": 1.0, "price": 240, "vehicle_damage_mult": 1.5,
	}))
	out.append(_weapon("crowbar", "Wrecking Bar", "melee", "melee", "Heavy steel. Glass and panels hate it.", {
		"damage": 34.0, "rpm": 78.0, "melee_range": 1.9, "melee_heavy_mult": 1.8, "melee_knockdown": 0.6,
		"melee_sound_hit": "melee_hit", "impulse": 6.0, "noise_radius": 7.0, "weapon_pose": "melee",
		"aim_fov": 60.0, "equip_time": 0.3, "tracer": false, "shake": 0.05, "headshot_mult": 1.0,
		"limb_mult": 1.0, "price": 300, "vehicle_damage_mult": 2.5,
	}))

	# ---- handguns ----------------------------------------------------------------------------
	out.append(_weapon("pistol", "Kestrel 9", "handgun", "semi", "Reliable sidearm. Usable from a vehicle.", {
		"damage": 24.0, "rpm": 400.0, "mag_size": 12, "ammo_type": "pistol", "default_ammo": 48,
		"reload_time": 1.35, "equip_time": 0.3,
		"spread_base": 0.8, "spread_moving": 1.3, "spread_bloom": 0.55, "spread_max": 3.8,
		"spread_recovery": 7.0, "spread_aim_mult": 0.5,
		"recoil_pitch": 1.2, "recoil_yaw": 0.5, "recoil_recovery": 9.0,
		"max_range": 70.0, "falloff_start": 18.0, "falloff_end": 50.0, "falloff_min": 0.55,
		"headshot_mult": 2.2, "impulse": 2.0, "noise_radius": 65.0, "weapon_pose": "pistol",
		"aim_fov": 52.0, "drive_by": true, "shake": 0.05, "sound_fire": "pistol_shot",
		"price": 550, "ammo_price": 60, "ammo_pack": 24, "optic_strength": 0.4,
		"attachments": _with_finishes(["suppressor", "scope", "flashlight", "ext_mag"]),
	}))
	out.append(_weapon("heavy_pistol", "Brimstone .50", "handgun", "semi", "Hand cannon. Slow, loud, decisive.", {
		"damage": 48.0, "rpm": 165.0, "mag_size": 7, "ammo_type": "pistol", "default_ammo": 28,
		"reload_time": 1.75, "equip_time": 0.4,
		"spread_base": 0.6, "spread_moving": 1.6, "spread_bloom": 1.4, "spread_max": 5.0,
		"spread_recovery": 5.0, "spread_aim_mult": 0.45,
		"recoil_pitch": 3.0, "recoil_yaw": 1.0, "recoil_recovery": 7.0,
		"max_range": 85.0, "falloff_start": 25.0, "falloff_end": 65.0, "falloff_min": 0.6,
		"headshot_mult": 2.4, "penetration": 0.15, "impulse": 4.0, "noise_radius": 78.0,
		"weapon_pose": "pistol", "aim_fov": 50.0, "drive_by": true, "shake": 0.1,
		"sound_fire": "heavy_pistol_shot", "price": 1450, "ammo_price": 60, "ammo_pack": 24,
		"eject_shells": false,      # the model is a revolver: the cases stay in the cylinder
		"optic_strength": 0.4, "attachments": _with_finishes(["scope", "flashlight"]),
	}))

	# ---- smg ---------------------------------------------------------------------------------
	out.append(_weapon("smg", "Wasp Compact", "smg", "auto", "Sprays fast at short range. Usable from a vehicle.", {
		"damage": 16.0, "rpm": 840.0, "mag_size": 30, "ammo_type": "smg", "default_ammo": 120,
		"reload_time": 1.9, "equip_time": 0.35,
		"spread_base": 1.5, "spread_moving": 1.2, "spread_bloom": 0.3, "spread_max": 5.2,
		"spread_recovery": 9.0, "spread_aim_mult": 0.62,
		"recoil_pitch": 0.6, "recoil_yaw": 0.55, "recoil_recovery": 10.0,
		"max_range": 60.0, "falloff_start": 14.0, "falloff_end": 42.0, "falloff_min": 0.5,
		"headshot_mult": 1.8, "impulse": 1.5, "noise_radius": 62.0, "weapon_pose": "rifle",
		"aim_fov": 50.0, "drive_by": true, "shake": 0.04, "sound_fire": "smg_shot",
		"price": 1900, "ammo_price": 90, "ammo_pack": 60,
		"attachments": _with_finishes(["suppressor", "scope", "flashlight", "grip", "ext_mag"]),
	}))

	# ---- shotguns ----------------------------------------------------------------------------
	out.append(_weapon("pump_shotgun", "Harbor 12 Pump", "shotgun", "pump", "Eight pellets, one decision.", {
		"damage": 13.0, "pellets": 8, "rpm": 64.0, "mag_size": 6, "ammo_type": "shotgun", "default_ammo": 24,
		"reload_time": 2.8, "equip_time": 0.45,
		"spread_base": 3.4, "spread_moving": 1.0, "spread_bloom": 0.0, "spread_max": 3.4,
		"spread_recovery": 6.0, "spread_aim_mult": 0.8,
		"recoil_pitch": 4.2, "recoil_yaw": 1.2, "recoil_recovery": 6.0,
		"max_range": 32.0, "falloff_start": 7.0, "falloff_end": 24.0, "falloff_min": 0.25,
		"headshot_mult": 1.35, "impulse": 6.0, "vehicle_damage_mult": 0.8, "noise_radius": 82.0,
		"weapon_pose": "rifle", "aim_fov": 55.0, "shake": 0.16, "sound_fire": "shotgun_shot",
		"price": 1600, "ammo_price": 80, "ammo_pack": 12, "optic_strength": 0.5,
		"attachments": _with_finishes(["suppressor", "scope", "flashlight", "ext_mag"]),
	}))
	out.append(_weapon("auto_shotgun", "Riptide Auto 12", "shotgun", "semi", "Semi-automatic room clearer.", {
		"damage": 9.5, "pellets": 8, "rpm": 220.0, "mag_size": 8, "ammo_type": "shotgun", "default_ammo": 32,
		"reload_time": 2.6, "equip_time": 0.45,
		"spread_base": 4.4, "spread_moving": 1.2, "spread_bloom": 0.5, "spread_max": 6.0,
		"spread_recovery": 5.0, "spread_aim_mult": 0.8,
		"recoil_pitch": 2.8, "recoil_yaw": 1.4, "recoil_recovery": 6.0,
		"max_range": 26.0, "falloff_start": 6.0, "falloff_end": 20.0, "falloff_min": 0.25,
		"headshot_mult": 1.35, "impulse": 4.5, "vehicle_damage_mult": 0.8, "noise_radius": 82.0,
		"weapon_pose": "rifle", "aim_fov": 55.0, "shake": 0.12, "sound_fire": "shotgun_shot",
		"price": 3300, "ammo_price": 80, "ammo_pack": 12, "optic_strength": 0.5,
		"attachments": _with_finishes(["suppressor", "scope", "flashlight", "grip", "ext_mag"]),
	}))

	# ---- rifles ------------------------------------------------------------------------------
	out.append(_weapon("assault_rifle", "Vanguard AR", "rifle", "auto", "All-round automatic rifle with reach.", {
		"damage": 28.0, "rpm": 580.0, "mag_size": 30, "ammo_type": "rifle", "default_ammo": 120,
		"reload_time": 2.3, "equip_time": 0.45,
		"spread_base": 0.7, "spread_moving": 2.0, "spread_bloom": 0.3, "spread_max": 4.4,
		"spread_recovery": 7.0, "spread_aim_mult": 0.45,
		"recoil_pitch": 0.9, "recoil_yaw": 0.45, "recoil_recovery": 8.0,
		"max_range": 130.0, "falloff_start": 40.0, "falloff_end": 100.0, "falloff_min": 0.65,
		"headshot_mult": 2.0, "penetration": 0.25, "impulse": 3.0, "noise_radius": 82.0,
		"weapon_pose": "rifle", "aim_fov": 46.0, "shake": 0.06, "sound_fire": "rifle_shot",
		"price": 3600, "ammo_price": 120, "ammo_pack": 60,
		"attachments": _with_finishes(["suppressor", "scope", "flashlight", "grip", "ext_mag"]),
	}))
	out.append(_weapon("carbine", "Courier Carbine", "rifle", "auto", "Short, quick-handling rifle. Lighter hits, faster fire.", {
		"damage": 21.0, "rpm": 720.0, "mag_size": 25, "ammo_type": "rifle", "default_ammo": 100,
		"reload_time": 1.95, "equip_time": 0.35,
		"spread_base": 0.9, "spread_moving": 1.4, "spread_bloom": 0.26, "spread_max": 4.0,
		"spread_recovery": 8.5, "spread_aim_mult": 0.5,
		"recoil_pitch": 0.7, "recoil_yaw": 0.4, "recoil_recovery": 9.0,
		"max_range": 100.0, "falloff_start": 30.0, "falloff_end": 80.0, "falloff_min": 0.6,
		"headshot_mult": 2.0, "penetration": 0.2, "impulse": 2.5, "noise_radius": 76.0,
		"weapon_pose": "rifle", "aim_fov": 48.0, "shake": 0.05, "sound_fire": "rifle_shot",
		"price": 2900, "ammo_price": 120, "ammo_pack": 60,
		"attachments": _with_finishes(["suppressor", "scope", "flashlight", "grip", "ext_mag"]),
	}))
	out.append(_weapon("marksman_rifle", "Longview DMR", "rifle", "semi", "Semi-automatic precision rifle.", {
		"damage": 62.0, "rpm": 150.0, "mag_size": 10, "ammo_type": "rifle", "default_ammo": 40,
		"reload_time": 2.6, "equip_time": 0.5,
		"spread_base": 0.3, "spread_moving": 2.8, "spread_bloom": 1.0, "spread_max": 3.6,
		"spread_recovery": 4.0, "spread_aim_mult": 0.25,
		"recoil_pitch": 2.4, "recoil_yaw": 0.6, "recoil_recovery": 6.0,
		"max_range": 240.0, "falloff_start": 90.0, "falloff_end": 200.0, "falloff_min": 0.8,
		"headshot_mult": 2.5, "penetration": 0.4, "impulse": 4.0, "noise_radius": 88.0,
		"weapon_pose": "rifle", "aim_fov": 34.0, "scope_overlay_with_scope": true, "shake": 0.1,
		"sound_fire": "sniper_shot", "price": 5200, "ammo_price": 120, "ammo_pack": 60,
		"attachments": _with_finishes(["suppressor", "scope", "flashlight", "grip", "ext_mag"]),
	}))

	# ---- sniper ------------------------------------------------------------------------------
	out.append(_weapon("sniper_rifle", "Pinnacle 700", "sniper", "bolt", "Bolt-action, scoped. One round, one problem.", {
		"damage": 135.0, "rpm": 42.0, "mag_size": 5, "ammo_type": "sniper", "default_ammo": 20,
		"reload_time": 3.3, "equip_time": 0.6,
		"spread_base": 3.2, "spread_moving": 3.0, "spread_bloom": 0.0, "spread_max": 3.2,
		"spread_recovery": 4.0, "spread_aim_mult": 0.012,
		"recoil_pitch": 5.0, "recoil_yaw": 1.0, "recoil_recovery": 5.0,
		"max_range": 450.0, "falloff_start": 220.0, "falloff_end": 420.0, "falloff_min": 0.85,
		"headshot_mult": 3.0, "penetration": 0.6, "impulse": 7.0, "vehicle_damage_mult": 1.5,
		"noise_radius": 95.0, "weapon_pose": "rifle", "aim_fov": 16.0, "scoped": true, "shake": 0.2,
		"sound_fire": "sniper_shot", "price": 7500, "ammo_price": 150, "ammo_pack": 10,
		"builtin_nodes": ["Att_Scope"], "attachments": _with_finishes(["suppressor", "ext_mag"]),
	}))

	# ---- heavy -------------------------------------------------------------------------------
	out.append(_weapon("rocket_launcher", "Hammerhead RL", "heavy", "launcher", "Shoulder-fired rocket. Clear the backblast.", {
		"damage": 480.0, "blast_radius": 8.5, "rpm": 30.0, "mag_size": 1, "ammo_type": "rocket", "default_ammo": 4,
		"reload_time": 3.0, "equip_time": 0.7,
		"spread_base": 0.6, "spread_moving": 2.0, "spread_bloom": 0.0, "spread_max": 0.6,
		"spread_recovery": 4.0, "spread_aim_mult": 0.4,
		"recoil_pitch": 5.0, "recoil_yaw": 1.5, "recoil_recovery": 5.0,
		"max_range": 300.0, "projectile_kind": "rocket", "projectile_speed": 48.0,
		"noise_radius": 95.0, "weapon_pose": "rpg", "aim_fov": 48.0, "shake": 0.35, "tracer": false,
		"sound_fire": "rocket_launch", "price": 9500, "ammo_price": 600, "ammo_pack": 2,
		"hide_mag_when_empty": true, "attachments": _with_finishes([]),
	}))
	out.append(_weapon("grenade_launcher", "Thumper GL", "heavy", "launcher", "Lobs impact grenades in an arc. Arms after a few metres.", {
		"damage": 230.0, "blast_radius": 6.0, "rpm": 75.0, "mag_size": 6, "ammo_type": "grenade_round", "default_ammo": 12,
		"reload_time": 3.6, "equip_time": 0.55,
		"spread_base": 1.0, "spread_moving": 1.5, "spread_bloom": 0.0, "spread_max": 1.0,
		"spread_recovery": 4.0, "spread_aim_mult": 0.5,
		"recoil_pitch": 3.2, "recoil_yaw": 0.8, "recoil_recovery": 6.0,
		"max_range": 150.0, "projectile_kind": "grenade_round", "projectile_speed": 38.0,
		"noise_radius": 70.0, "weapon_pose": "rifle", "aim_fov": 52.0, "shake": 0.18, "tracer": false,
		"sound_fire": "grenade_launcher_shot", "price": 7200, "ammo_price": 480, "ammo_pack": 6,
		"optic_strength": 0.5, "attachments": _with_finishes(["scope", "flashlight"]),
	}))

	# ---- thrown ------------------------------------------------------------------------------
	out.append(_weapon("grenade", "Frag Grenade", "thrown", "thrown", "Hold to cook, release to throw. Bounces.", {
		"damage": 220.0, "blast_radius": 7.0, "rpm": 50.0, "ammo_type": "grenade", "default_ammo": 3,
		"equip_time": 0.25, "projectile_kind": "grenade", "projectile_speed": 17.0,
		"noise_radius": 8.0, "weapon_pose": "throw", "aim_fov": 56.0, "drive_by": true, "shake": 0.0,
		"tracer": false, "sound_fire": "melee_swing", "price": 300, "ammo_price": 300, "ammo_pack": 1,
	}))
	out.append(_weapon("molotov", "Fire Bottle", "thrown", "thrown", "Breaks on impact and leaves a burning pool.", {
		"damage": 12.0, "blast_radius": 3.0, "rpm": 45.0, "ammo_type": "molotov", "default_ammo": 3,
		"equip_time": 0.25, "projectile_kind": "molotov", "projectile_speed": 15.0,
		"noise_radius": 8.0, "weapon_pose": "throw", "aim_fov": 56.0, "drive_by": true, "shake": 0.0,
		"tracer": false, "sound_fire": "melee_swing", "price": 200, "ammo_price": 200, "ammo_pack": 1,
	}))
	return out
