extends RefCounted
## Registrar for Registry kind "vehicle_mods": data-driven upgrade definitions for the mod shop.
## Each definition is a Dictionary:
##   id, slot, display_name, price, level (ordering inside the slot), category ("performance" /
##   "visual"), description, effects (see VehicleMods.DEFAULT_STATS: multipliers unless additive),
##   and for visual mods one of: node (Mod_* part to show), wheel_model (shared wheel GLB),
##   color (wheel_color / plate / lights), finish, tint, horn_sound / horn_pitch.
## Applied by res://gta/code/vehicles/vehicle_mods.gd; effects change the real physics.

const PARTS := "res://gta/generated/models/vehicles/parts/"


static func register_all(registry: Node) -> void:
	for def: Dictionary in _build():
		registry.register("vehicle_mods", def)


static func _perf(id: String, slot: String, level: int, mod_name: String, price: int, effects: Dictionary, text: String) -> Dictionary:
	return {"id": id, "slot": slot, "level": level, "display_name": mod_name, "price": price,
			"category": "performance", "effects": effects, "description": text}


static func _vis(id: String, slot: String, level: int, mod_name: String, price: int, extra: Dictionary, text: String = "") -> Dictionary:
	var d := {"id": id, "slot": slot, "level": level, "display_name": mod_name, "price": price,
			"category": "visual", "effects": {}, "description": text}
	for k: String in extra:
		d[k] = extra[k]
	return d


static func _build() -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	# ------------------------------------------------------------------ performance
	out.append(_perf("engine_1", "engine", 1, "Street Tune", 1800, {"power": 1.08}, "+8 % power"))
	out.append(_perf("engine_2", "engine", 2, "Sport Cams", 4200, {"power": 1.16}, "+16 % power"))
	out.append(_perf("engine_3", "engine", 3, "Race Internals", 8500, {"power": 1.25}, "+25 % power"))
	out.append(_perf("engine_4", "engine", 4, "Bay Outlaw Build", 15000, {"power": 1.35}, "+35 % power"))

	out.append(_perf("brakes_1", "brakes", 1, "Street Pads", 900, {"brake": 1.14}, "+14 % brake force"))
	out.append(_perf("brakes_2", "brakes", 2, "Sport Discs", 2400, {"brake": 1.28}, "+28 % brake force"))
	out.append(_perf("brakes_3", "brakes", 3, "Race Calipers", 5200, {"brake": 1.45}, "+45 % brake force"))

	out.append(_perf("suspension_1", "suspension", 1, "Lowered Springs", 1200,
			{"ride_drop": 0.02, "stiffness": 1.1, "anti_roll": 1.15, "grip": 1.01}, "Lower, a little firmer"))
	out.append(_perf("suspension_2", "suspension", 2, "Street Coilovers", 2800,
			{"ride_drop": 0.035, "stiffness": 1.2, "anti_roll": 1.3, "grip": 1.02}, "Lower and firmer, less roll"))
	out.append(_perf("suspension_3", "suspension", 3, "Sport Coilovers", 5200,
			{"ride_drop": 0.05, "stiffness": 1.3, "anti_roll": 1.5, "grip": 1.035}, "Track stance"))
	out.append(_perf("suspension_4", "suspension", 4, "Competition Kit", 8800,
			{"ride_drop": 0.065, "stiffness": 1.42, "anti_roll": 1.75, "grip": 1.05}, "As low and flat as it gets"))

	out.append(_perf("transmission_1", "transmission", 1, "Short Shifter", 1500, {"shift_time": 0.72, "drive": 1.03}, "Faster shifts"))
	out.append(_perf("transmission_2", "transmission", 2, "Close-Ratio Box", 3800, {"shift_time": 0.5, "drive": 1.06}, "Quicker shifts, shorter gearing"))
	out.append(_perf("transmission_3", "transmission", 3, "Race Sequential", 7600, {"shift_time": 0.3, "drive": 1.1}, "Near-instant shifts"))

	out.append(_perf("turbo_1", "turbo", 1, "Low-Boost Turbo", 3500, {"power": 1.1, "top_speed": 1.03}, "+10 % power, higher top speed"))
	out.append(_perf("turbo_2", "turbo", 2, "Twin-Scroll Turbo", 7500, {"power": 1.18, "top_speed": 1.06}, "+18 % power"))
	out.append(_perf("turbo_3", "turbo", 3, "Big Single Turbo", 13500, {"power": 1.27, "top_speed": 1.09}, "+27 % power"))

	out.append(_perf("armor_1", "armor", 1, "Reinforced Panels", 2500, {"damage_taken": 0.85, "mass_add": 40.0}, "-15 % damage taken"))
	out.append(_perf("armor_2", "armor", 2, "Steel Plating", 6000, {"damage_taken": 0.7, "mass_add": 80.0}, "-30 % damage taken"))
	out.append(_perf("armor_3", "armor", 3, "Composite Armor", 11000, {"damage_taken": 0.55, "mass_add": 120.0}, "-45 % damage taken"))
	out.append(_perf("armor_4", "armor", 4, "Full Ballistic Kit", 18000, {"damage_taken": 0.4, "mass_add": 170.0}, "-60 % damage taken"))

	out.append(_perf("tires_1", "tires", 1, "Sport Compound", 1400, {"grip": 1.05}, "+5 % grip"))
	out.append(_perf("tires_2", "tires", 2, "Semi-Slick", 3600, {"grip": 1.1}, "+10 % grip"))
	out.append(_perf("tires_3", "tires", 3, "Run-Flat Bullet-Resistant", 9000, {"grip": 1.06, "bulletproof_tires": true}, "Cannot be shot out"))

	# ------------------------------------------------------------------ body parts (Blender Mod_* meshes)
	out.append(_vis("spoiler_a", "spoiler", 1, "Ducktail Spoiler", 1600, {"node": "Mod_Spoiler_A", "effects": {"downforce_add": 0.5}}, "A little rear downforce"))
	out.append(_vis("spoiler_b", "spoiler", 2, "GT Wing", 3400, {"node": "Mod_Spoiler_B", "effects": {"downforce_add": 1.0, "grip": 1.02}}, "Real rear downforce"))
	out.append(_vis("bumper_f_a", "bumper_f", 1, "Sport Front Bumper", 1900, {"node": "Mod_BumperF_A"}))
	out.append(_vis("bumper_r_a", "bumper_r", 1, "Sport Rear Bumper", 1700, {"node": "Mod_BumperR_A"}))
	out.append(_vis("hood_a", "hood", 1, "Vented Hood", 2200, {"node": "Mod_Hood_A"}))
	out.append(_vis("skirts_a", "skirts", 1, "Side Skirts", 1500, {"node": "Mod_Skirts_A"}))
	out.append(_vis("roof_a", "roof", 1, "Roof Accessory", 1300, {"node": "Mod_Roof_A"}))
	out.append(_vis("exhaust_a", "exhaust", 1, "Sport Exhaust", 1400, {"node": "Mod_Exhaust_A", "effects": {"power": 1.02}}, "+2 % power"))
	out.append(_vis("grille_a", "grille", 1, "Mesh Grille", 1100, {"node": "Mod_Grille_A"}))

	# ------------------------------------------------------------------ wheels (shared GLBs)
	out.append(_vis("wheels_sport", "wheels", 1, "Sport Five-Spoke", 2400, {"wheel_model": PARTS + "wheel_sport.glb"}))
	out.append(_vis("wheels_classic", "wheels", 2, "Classic Steelies", 1800, {"wheel_model": PARTS + "wheel_classic.glb"}))
	out.append(_vis("wheels_offroad", "wheels", 3, "Off-Road Beadlock", 2800, {"wheel_model": PARTS + "wheel_offroad.glb"}))
	out.append(_vis("wheels_deep", "wheels", 4, "Deep Dish", 3200, {"wheel_model": PARTS + "wheel_deep.glb"}))

	out.append(_vis("wheelcol_black", "wheel_color", 1, "Gloss Black", 400, {"color": Color("#1C1E23")}))
	out.append(_vis("wheelcol_white", "wheel_color", 2, "White", 400, {"color": Color("#F1F1EE")}))
	out.append(_vis("wheelcol_gold", "wheel_color", 3, "Gold", 600, {"color": Color("#D9B34A")}))
	out.append(_vis("wheelcol_red", "wheel_color", 4, "Red", 500, {"color": Color("#D8342C")}))
	out.append(_vis("wheelcol_teal", "wheel_color", 5, "Teal", 500, {"color": Color("#1FA7A0")}))
	out.append(_vis("wheelcol_bronze", "wheel_color", 6, "Bronze", 600, {"color": Color("#A8562F")}))

	# ------------------------------------------------------------------ paint finish / glass / plate / horn
	out.append(_vis("finish_gloss", "paint_finish", 1, "High Gloss", 800, {"finish": "gloss"}))
	out.append(_vis("finish_matte", "paint_finish", 2, "Matte", 1200, {"finish": "matte"}))
	out.append(_vis("finish_metallic", "paint_finish", 3, "Metallic", 1800, {"finish": "metallic"}))

	out.append(_vis("tint_light", "tint", 1, "Light Smoke", 500, {"tint": 0.35}))
	out.append(_vis("tint_medium", "tint", 2, "Dark Smoke", 900, {"tint": 0.65}))
	out.append(_vis("tint_limo", "tint", 3, "Limo Black", 1500, {"tint": 0.95}))

	out.append(_vis("lights_xenon", "lights", 1, "Xenon White", 900, {"color": Color(0.82, 0.9, 1.0)}))
	out.append(_vis("lights_ice", "lights", 2, "Ice Blue", 1300, {"color": Color(0.5, 0.72, 1.0)}))
	out.append(_vis("lights_amber", "lights", 3, "Rally Amber", 1000, {"color": Color(1.0, 0.76, 0.3)}))

	out.append(_vis("plate_yellow", "plate", 1, "Yellow Plate", 200, {"color": Color("#F2C331")}))
	out.append(_vis("plate_black", "plate", 2, "Black Plate", 250, {"color": Color("#1C1E23")}))
	out.append(_vis("plate_blue", "plate", 3, "Bay Blue Plate", 250, {"color": Color("#2C6FD9")}))

	out.append(_vis("horn_high", "horn", 1, "Bright Horn", 300, {"horn_sound": "horn_car", "horn_pitch": 1.35}))
	out.append(_vis("horn_low", "horn", 2, "Deep Horn", 300, {"horn_sound": "horn_car", "horn_pitch": 0.72}))
	out.append(_vis("horn_truck", "horn", 3, "Truck Air Horn", 700, {"horn_sound": "horn_truck", "horn_pitch": 1.0}))
	out.append(_vis("horn_scooter", "horn", 4, "Scooter Beep", 250, {"horn_sound": "horn_bike", "horn_pitch": 1.1}))
	return out
