extends RefCounted
## Registry registrar of the ACTIVITIES module: kind "activities" (spec 47 / 47A, docs/ACTIVITIES.md).
##
## Free-roam hobbies only - no missions, no unlock chains, no story. Every definition is a
## Dictionary with an `id` and a `kind`, read by res://gta/code/world/activity_system.gd:
##
## kind "shooting_range" (Ironsight Range, landmark `shooting_range`)
##   landmark, use_marker (city marker of the start point) or use_local [x, y, z] (building-local
##   point, Godot coordinates), prompt, weapon (WeaponSpec id handed out for the course), ammo,
##   lane (1..5 firing position), rounds: [{name, type: "turner" | "popup" | "mover", rows (yard
##   rows = building-local x, down-range), exposures, window (s a target stays up), gap (s between
##   volleys), together (targets per volley), speed [min, max] (movers, m/s)}],
##   medals {gold, silver, bronze} = fraction of the maximum score, rewards {medal: $},
##   xp {per_hit, gold, silver, bronze} (Skills "shooting").
## kind "stunt_jump" (no start point: driving off the ramp fast enough IS the deliberate act)
##   location (named World location of the ramp, as placed by the dressing), ramp (props id ->
##   manifest markers Entry / Lip), min_speed (m/s on the ramp), min_distance (m), min_airtime (s),
##   reward ($, first successful jump only), xp (Skills "driving").
## kind "race" (checkpoint race / time trial against par times)
##   mode "road": via = [location name | [x, z], ...] joined with RoadGraph.find_route;
##   mode "trail": trail_road = RoadGraph segment name (driven bottom -> top, trail_return: and back down);
##   mode "water": points = [[x, z], ...] on open water (pushed off the shore at runtime).
##   point (where the activity point stands: location name, or [x, z]), point_offset (m to the
##   right of the route start, road races), vehicle (spawned when the player has nothing suitable),
##   classes (vehicle_class values accepted), spacing (m between checkpoints), radius (m),
##   arch (spawn checkpoint_arch at the start line while the race runs), par_speed {medal: average
##   m/s} -> par times from the real route length, rewards {medal: $}, xp (Skills "driving").

const DEFS: Array[Dictionary] = [
	# ------------------------------------------------------------------ shooting range -------------
	{
		"id": "range_handgun", "kind": "shooting_range", "display_name": "Ironsight Challenge",
		"subtitle": "Handgun course", "landmark": "shooting_range", "use_marker": "Use_Start",
		"prompt": "Shooting range: handgun course", "weapon": "pistol", "ammo": 150, "lane": 3,
		"map_icon": "target",
		"rounds": [
			{"name": "Turners", "type": "turner", "rows": [-1.0], "exposures": 6, "window": 2.4, "gap": 0.7, "together": 1},
			{"name": "Pop-ups", "type": "popup", "rows": [-3.5, 5.0, 9.0], "exposures": 10, "window": 2.0, "gap": 0.5, "together": 2},
			{"name": "Movers", "type": "mover", "rows": [-4.5, 8.0], "exposures": 4, "window": 4.5, "gap": 0.7, "together": 2, "speed": [1.5, 2.3]},
		],
		"medals": {"gold": 0.78, "silver": 0.58, "bronze": 0.38},
		"rewards": {"gold": 300, "silver": 150, "bronze": 60},
		"xp": {"per_hit": 0.05, "gold": 0.8, "silver": 0.5, "bronze": 0.25},
	},
	{
		"id": "range_carbine", "kind": "shooting_range", "display_name": "Ironsight Challenge",
		"subtitle": "Carbine course", "landmark": "shooting_range", "use_local": [-12.3, 0.06, 2.3],
		"prompt": "Shooting range: carbine course", "weapon": "carbine", "ammo": 240, "lane": 3,
		"map_icon": "target",
		"rounds": [
			{"name": "Turners", "type": "turner", "rows": [-1.0], "exposures": 7, "window": 1.8, "gap": 0.5, "together": 1},
			{"name": "Pop-ups", "type": "popup", "rows": [5.0, 9.0, -3.5], "exposures": 12, "window": 1.6, "gap": 0.4, "together": 3},
			{"name": "Movers", "type": "mover", "rows": [8.0, -4.5], "exposures": 6, "window": 3.4, "gap": 0.5, "together": 2, "speed": [2.2, 3.2]},
		],
		"medals": {"gold": 0.8, "silver": 0.6, "bronze": 0.4},
		"rewards": {"gold": 400, "silver": 200, "bronze": 80},
		"xp": {"per_hit": 0.04, "gold": 1.0, "silver": 0.6, "bronze": 0.3},
	},
	# ------------------------------------------------------------------ stunt jumps -----------------
	{
		"id": "stunt_foundry", "kind": "stunt_jump", "display_name": "Foundry Yard Jump",
		"location": "stunt_ramp_1", "ramp": "stunt_ramp_big",
		"min_speed": 13.0, "min_distance": 16.0, "min_airtime": 0.9, "reward": 500, "xp": 0.4,
	},
	{
		"id": "stunt_docks", "kind": "stunt_jump", "display_name": "Quay End Kicker",
		"location": "stunt_ramp_2", "ramp": "stunt_ramp_small",
		"min_speed": 11.0, "min_distance": 9.0, "min_airtime": 0.45, "reward": 300, "xp": 0.3,
	},
	{
		"id": "stunt_apron", "kind": "stunt_jump", "display_name": "Apron Launch",
		"location": "stunt_ramp_3", "ramp": "stunt_ramp_big",
		"min_speed": 13.0, "min_distance": 16.0, "min_airtime": 0.9, "reward": 500, "xp": 0.4,
	},
	# ------------------------------------------------------------------ races -----------------------
	{
		"id": "race_coral_loop", "kind": "race", "mode": "road", "display_name": "Coral Loop",
		"subtitle": "Street race", "prompt": "Street race: Coral Loop", "point": "race_start", "point_offset": 6.4,
		# race_start lies between the two westbound lanes; RoadGraph routes are lane-strict (2 -> 2 lanes
		# keep their lane through junctions), so the loop starts and ends on the kerb-side lane
		"via": [[60.0, 154.6], "gas_station", [-120.0, 95.0], "hospital", [0.0, -62.0], [90.0, -105.0],
				"tram_stop_2", [60.0, 154.6]],
		"vehicle": "sports", "classes": ["car", "bike"], "spacing": 115.0, "radius": 9.0, "arch": true,
		"par_speed": {"gold": 19.0, "silver": 15.0, "bronze": 11.0},
		"rewards": {"gold": 500, "silver": 250, "bronze": 100}, "xp": {"gold": 0.6, "silver": 0.4, "bronze": 0.2},
		"map_icon": "flag",
	},
	{
		"id": "race_harbor_sprint", "kind": "race", "mode": "water", "display_name": "Harbor Sprint",
		"subtitle": "Sea race", "prompt": "Sea race: Harbor Sprint", "point": "marina_dock", "grid": "boat_spawn",
		"points": [[-140.0, 318.0], [-60.0, 336.0], [40.0, 334.0], [140.0, 334.0], [222.0, 322.0], [232.0, 352.0],
				[140.0, 362.0], [30.0, 360.0], [-80.0, 350.0], [-128.0, 312.0]],
		"vehicle": "speedboat", "classes": ["boat"], "radius": 11.0, "arch": false,
		"par_speed": {"gold": 16.0, "silver": 13.0, "bronze": 9.5},
		"rewards": {"gold": 450, "silver": 220, "bronze": 90}, "xp": {"gold": 0.5, "silver": 0.3, "bronze": 0.15},
		"map_icon": "flag",
	},
	{
		"id": "race_hill_trail", "kind": "race", "mode": "trail", "display_name": "Signal Hill Climb",
		"subtitle": "Off-road trail - up and back", "prompt": "Trail race: Signal Hill Climb", "trail_road": "Signal Hill Road",
		"point_offset": 5.5, "trail_skip": 14.0, "trail_stop": 6.0, "trail_return": true,

		"vehicle": "motorcycle", "classes": ["bike", "car"], "spacing": 55.0, "radius": 7.0, "arch": true,
		"par_speed": {"gold": 14.0, "silver": 10.5, "bronze": 7.5},
		"rewards": {"gold": 400, "silver": 200, "bronze": 80}, "xp": {"gold": 0.5, "silver": 0.3, "bronze": 0.15},
		"map_icon": "flag",
	},
]


static func register_all(registry: Node) -> void:
	if registry == null or not registry.has_method("register"):
		return
	for d: Dictionary in DEFS:
		registry.call("register", "activities", d.duplicate(true))
