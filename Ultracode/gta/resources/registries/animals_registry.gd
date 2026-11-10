extends RefCounted
## Registry registrar of the WILDLIFE module (kind "animals", one Dictionary per species).
##
## The art facts (parts, pivots, size, shoulder height, leg length, bird poses) come from
## res://gta/generated/models/animals/manifest_animals.json and are merged in at runtime by
## AnimalAssets.species_def(id); this file holds the GAMEPLAY tuning only:
##
##   id, model (GLB path), kind ("land" | "bird" | "fish"), category ("land" | "bird" | "water" - the
##   spawn budget it counts against), temperament:
##       timid     flees from the player / vehicles / noise (deer, rabbit, cat)
##       docile    only moves away from loud things (cow)
##       predator  skittish by day, hunts a person on foot at night or when provoked (coyote)
##       pet       barks at people, bites when provoked or (strays) at night (dog)
##       charger   charges when cornered or provoked (boar)
##       bird      perches, flies away from people and noise (seagull, pigeon)
##       school    fish school (one MultiMesh node per school)
##       shark     circles swimmers / divers, bites now and then
##   health, walk_speed / trot_speed / run_speed (m/s), turn_rate (deg/s), flee_radius (m, from a
##   walking player; sprinting x1.6, crouched / stealth x0.5), hearing (multiplier on noise radii),
##   bite_damage, bite_range, bite_cooldown (s), stride_walk / stride_trot / stride_run (m per gait
##   cycle), gait_style ("quad" | "hop"), graze ("graze" | "sniff" | "" - head-down idle),
##   wander_radius (m around home), group (min, max per spawn), cap (max alive),
##   day / night (spawn weight multipliers), sounds {alarm, call, attack, hurt} (Audio ids) with
##   pitch, crime_victim (true: harming it in front of a civilian is an "assault" report),
##   mass (kg, knock-back), corpse_time (s).
##   birds: cruise_speed, flap_hz, glide (0..1 share of gliding), perch ("coast" | "urban"),
##          alt_min / alt_max (m above ground or water)
##   fish:  school_size [min, max], swim_speed, burst_speed, min_depth (m of water needed)

const MODEL_DIR := "res://gta/generated/models/animals/"

const SPECIES := [
	{
		"id": "deer", "kind": "land", "category": "land", "temperament": "timid",
		"health": 70.0, "walk_speed": 1.4, "trot_speed": 4.2, "run_speed": 11.0, "turn_rate": 220.0,
		"flee_radius": 24.0, "hearing": 2.2, "stride_walk": 1.35, "stride_trot": 2.3, "stride_run": 4.6,
		"gait_style": "quad", "graze": "graze", "wander_radius": 34.0, "group": [1, 3], "cap": 5,
		"day": 1.0, "night": 0.8, "mass": 70.0, "corpse_time": 45.0,
		"sounds": {"alarm": "animal_deer", "hurt": "animal_deer", "call": "animal_deer"},
		"pitch": 1.0, "crime_victim": false,
	},
	{
		"id": "boar", "kind": "land", "category": "land", "temperament": "charger",
		"health": 110.0, "walk_speed": 1.2, "trot_speed": 3.4, "run_speed": 8.0, "turn_rate": 200.0,
		"flee_radius": 14.0, "hearing": 1.5, "stride_walk": 0.9, "stride_trot": 1.6, "stride_run": 2.7,
		"gait_style": "quad", "graze": "sniff", "wander_radius": 26.0, "group": [1, 2], "cap": 3,
		"day": 1.0, "night": 1.2, "mass": 90.0, "corpse_time": 45.0,
		"bite_damage": 14.0, "bite_range": 1.05, "bite_cooldown": 1.6, "charge_chance": 0.45,
		"sounds": {"alarm": "animal_growl", "attack": "animal_growl", "hurt": "animal_growl"},
		"pitch": 0.75, "crime_victim": false,
	},
	{
		"id": "coyote", "kind": "land", "category": "land", "temperament": "predator",
		"health": 50.0, "walk_speed": 1.6, "trot_speed": 4.0, "run_speed": 10.0, "turn_rate": 300.0,
		"flee_radius": 26.0, "hearing": 2.0, "stride_walk": 1.0, "stride_trot": 1.8, "stride_run": 3.2,
		"gait_style": "quad", "graze": "sniff", "wander_radius": 40.0, "group": [1, 2], "cap": 3,
		"day": 0.5, "night": 3.0, "mass": 15.0, "corpse_time": 40.0,
		"bite_damage": 9.0, "bite_range": 0.95, "bite_cooldown": 1.25, "hunt_radius": 20.0,
		"sounds": {"alarm": "animal_growl", "attack": "animal_growl", "hurt": "animal_dog_bark", "call": "animal_dog_bark"},
		"pitch": 1.25, "crime_victim": false,
	},
	{
		"id": "dog", "kind": "land", "category": "land", "temperament": "pet",
		"health": 45.0, "walk_speed": 1.5, "trot_speed": 3.6, "run_speed": 8.5, "turn_rate": 320.0,
		"flee_radius": 7.0, "hearing": 1.8, "stride_walk": 0.8, "stride_trot": 1.4, "stride_run": 2.4,
		"gait_style": "quad", "graze": "sniff", "wander_radius": 30.0, "group": [1, 1], "cap": 3,
		"day": 1.0, "night": 0.6, "mass": 25.0, "corpse_time": 40.0,
		"bite_damage": 8.0, "bite_range": 0.9, "bite_cooldown": 1.1, "bark_radius": 9.0, "stray_chance": 0.15,
		"sounds": {"alarm": "animal_dog_bark", "attack": "animal_growl", "hurt": "animal_dog_bark", "call": "animal_dog_bark"},
		"pitch": 1.0, "crime_victim": true,
	},
	{
		"id": "cat", "kind": "land", "category": "land", "temperament": "timid",
		"health": 20.0, "walk_speed": 1.0, "trot_speed": 2.6, "run_speed": 7.0, "turn_rate": 360.0,
		"flee_radius": 6.0, "hearing": 1.6, "stride_walk": 0.45, "stride_trot": 0.85, "stride_run": 1.6,
		"gait_style": "quad", "graze": "", "wander_radius": 20.0, "group": [1, 1], "cap": 2,
		"day": 1.0, "night": 1.3, "mass": 4.0, "corpse_time": 35.0,
		"sounds": {"alarm": "animal_growl", "hurt": "animal_growl"},
		"pitch": 2.1, "crime_victim": true,
	},
	{
		"id": "rabbit", "kind": "land", "category": "land", "temperament": "timid",
		"health": 15.0, "walk_speed": 0.8, "trot_speed": 2.5, "run_speed": 8.0, "turn_rate": 420.0,
		"flee_radius": 12.0, "hearing": 2.4, "stride_walk": 0.35, "stride_trot": 0.9, "stride_run": 2.0,
		"gait_style": "hop", "graze": "graze", "wander_radius": 18.0, "group": [1, 2], "cap": 4,
		"day": 1.0, "night": 0.7, "mass": 2.0, "corpse_time": 30.0,
		"sounds": {},
		"pitch": 1.0, "crime_victim": false,
	},
	{
		"id": "cow", "kind": "land", "category": "land", "temperament": "docile",
		"health": 150.0, "walk_speed": 1.0, "trot_speed": 2.4, "run_speed": 4.5, "turn_rate": 120.0,
		"flee_radius": 0.0, "hearing": 0.8, "stride_walk": 1.5, "stride_trot": 2.0, "stride_run": 2.6,
		"gait_style": "quad", "graze": "graze", "wander_radius": 22.0, "group": [2, 3], "cap": 3,
		"day": 1.0, "night": 1.0, "mass": 500.0, "corpse_time": 60.0,
		"sounds": {"alarm": "animal_growl", "hurt": "animal_growl"},
		"pitch": 0.55, "crime_victim": false,
	},
	{
		"id": "seagull", "kind": "bird", "category": "bird", "temperament": "bird",
		"health": 8.0, "walk_speed": 0.5, "run_speed": 9.0, "cruise_speed": 8.5, "turn_rate": 160.0,
		"flee_radius": 7.0, "hearing": 1.4, "flap_hz": 3.6, "glide": 0.7, "perch": "coast",
		"alt_min": 9.0, "alt_max": 24.0, "group": [2, 4], "cap": 6, "day": 1.0, "night": 0.45,
		"mass": 1.0, "corpse_time": 30.0,
		"sounds": {"alarm": "animal_gull", "call": "animal_gull", "hurt": "animal_gull"},
		"pitch": 1.0, "crime_victim": false,
	},
	{
		"id": "pigeon", "kind": "bird", "category": "bird", "temperament": "bird",
		"health": 6.0, "walk_speed": 0.4, "run_speed": 8.0, "cruise_speed": 7.5, "turn_rate": 220.0,
		"flee_radius": 5.0, "hearing": 1.2, "flap_hz": 7.0, "glide": 0.25, "perch": "urban",
		"alt_min": 6.0, "alt_max": 14.0, "group": [3, 5], "cap": 6, "day": 1.0, "night": 0.0,
		"mass": 0.35, "corpse_time": 25.0,
		"sounds": {"alarm": "animal_bird", "call": "animal_bird", "hurt": "animal_bird"},
		"pitch": 1.0, "crime_victim": false,
	},
	{
		"id": "fish_small", "kind": "fish", "category": "water", "temperament": "school",
		"health": 1.0, "swim_speed": 0.9, "burst_speed": 3.2, "school_size": [12, 18], "min_depth": 3.0,
		"group": [1, 1], "cap": 3, "day": 1.0, "night": 1.0, "mass": 0.3, "corpse_time": 20.0,
		"sounds": {}, "pitch": 1.0, "crime_victim": false,
	},
	{
		"id": "shark", "kind": "fish", "category": "water", "temperament": "shark",
		"health": 360.0, "swim_speed": 1.6, "run_speed": 7.0, "turn_rate": 70.0, "min_depth": 6.0,
		"hearing": 1.0, "bite_damage": 34.0, "bite_range": 2.3, "bite_cooldown": 9.0, "hunt_radius": 46.0,
		"stride_run": 3.0, "group": [1, 1], "cap": 1, "day": 1.0, "night": 1.0, "mass": 300.0,
		"corpse_time": 40.0,
		"sounds": {"attack": "animal_growl", "hurt": "animal_growl"},
		"pitch": 0.5, "crime_victim": false,
	},
]


static func register_all(registry: Node) -> void:
	for s: Dictionary in SPECIES:
		var d := s.duplicate(true)
		d["model"] = MODEL_DIR + String(d["id"]) + ".glb"
		registry.register("animals", d)
