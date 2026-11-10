class_name WorldLayout
extends RefCounted
## HALCYON BAY - deterministic layout data of the island (single source for every WORLD generator).
## Map axes: +X east, +Z south. All coordinates in metres. See docs/WORLD.md for the map description.

const SEED := 520017
const PLATEAU_Y := 2.5            ## road level of the whole city / airport / quays
const CURB_H := 0.15              ## sidewalks and block slabs are raised by this
const CURB_RUN := 0.25            ## horizontal run of the sloped kerb (keeps it mountable)
const SIDEWALK_W := 3.0
const ROAD_LIFT := 0.03           ## asphalt render/collision offset above the terrain plateau
const MARK_LIFT := 0.055          ## painted markings
const DECK_LIFT := 0.02           ## flat concrete decks (quay, apron lots)
const STOP_SETBACK := 4.2         ## lane ends this far before the intersection box (crosswalk zone)
const MAP_HALF := 300.0

const KINDS := {
	"arterial": {"hw": 8.0, "lanes": 2, "speed": 22.0, "offs": [2.0, 5.5], "sw": true, "rank": 3},
	"street": {"hw": 5.5, "lanes": 1, "speed": 14.0, "offs": [1.75], "sw": true, "rank": 2},
	"alley": {"hw": 3.0, "lanes": 1, "speed": 7.0, "offs": [1.4], "sw": false, "rank": 1},
	"dirt": {"hw": 3.0, "lanes": 1, "speed": 9.0, "offs": [1.4], "sw": false, "rank": 1},
	"runway": {"hw": 12.0, "lanes": 0, "speed": 0.0, "offs": [], "sw": false, "rank": 0},
	"taxiway": {"hw": 5.0, "lanes": 0, "speed": 0.0, "offs": [], "sw": false, "rank": 0},
}

const CORNER_R := 1.5             ## kerb radius of sidewalk corners at intersections
const CROSSWALK_NEAR := 1.0       ## zebra band (measured from the intersection box edge)
const CROSSWALK_FAR := 3.5

## Hill road way points (Catmull-Rom). Also used by Terrain to carve the road bed.
const HILL_ROAD: Array = [168, -20, 168, -40, 160.7, -74, 158.4, -106.4, 165.6, -136.4, 175.2, -151.2,
		196.9, -168.1, 225, -171, 246.2, -158.3, 254.1, -138.6, 249.1, -121.5, 235.3, -113.3, 223.3, -118.2, 221, -124]

## Dirt lane from the Shore Road to the lighthouse knoll.
const LIGHTHOUSE_ROAD: Array = [0, 225, 0, 244, 4, 262]
## Tracks that Terrain carves / paints as dirt (no asphalt mesh on them).
const DIRT_TRACKS: Array = [HILL_ROAD, LIGHTHOUSE_ROAD]

## Drivable roads. pts = x,z pairs. Roads are split automatically wherever they meet.
## Optional keys: closed, round (corner radius), smooth, hw, parking, sw_l / sw_r (sidewalk on the
## left / right of the drawing direction), speed.
const ROADS: Array = [
	{"name": "Coral Ring", "kind": "arterial", "closed": true, "round": 26.0,
		"pts": [-215, -190, 120, -190, 120, -20, 215, -20, 215, 160, -215, 160]},
	{"name": "Marlin Avenue", "kind": "street", "parking": true, "pts": [-120, -190, -120, 225]},
	{"name": "Meridian Avenue", "kind": "street", "parking": true, "pts": [0, -190, 0, 225]},
	{"name": "Sandpiper Avenue", "kind": "street", "parking": true, "pts": [120, -20, 120, 225]},
	{"name": "Foundry Street", "kind": "street", "parking": true, "pts": [-215, -105, 120, -105]},
	{"name": "Cannery Street", "kind": "street", "parking": true, "pts": [-215, -20, 120, -20]},
	{"name": "Tideline Street", "kind": "street", "parking": true, "pts": [-215, 70, 215, 70]},
	{"name": "Lantern Street", "kind": "street", "hw": 4.5, "pts": [-120, 115, 215, 115]},
	{"name": "Shore Road", "kind": "street", "hw": 4.5, "round": 18.0,
		"pts": [-215, -105, -262, -105, -262, 225, 255, 225, 255, 70, 215, 70]},
	{"name": "Airfield Road", "kind": "street", "hw": 4.5, "round": 12.0, "sw_l": false,
		"pts": [-215, -190, -215, -222, -120, -222, -120, -190]},
	{"name": "Pelican Alley", "kind": "alley", "pts": [-60, -190, -60, 70]},
	{"name": "Gull Alley", "kind": "alley", "pts": [60, -190, 60, 70]},
	{"name": "Rivet Lane", "kind": "alley", "pts": [-168, -105, -168, 70]},
	{"name": "Juniper Lane", "kind": "street", "hw": 4.5, "pts": [168, -20, 168, 70]},
	{"name": "Signal Hill Road", "kind": "dirt", "smooth": true, "pts": HILL_ROAD},
	{"name": "Lighthouse Lane", "kind": "dirt", "smooth": true, "pts": LIGHTHOUSE_ROAD},
]

## Airfield strips (segments without traffic lanes).
const AIRFIELD: Array = [
	{"name": "Runway 09-27", "kind": "runway", "pts": [-170, -264, 210, -264]},
	{"name": "Taxiway A", "kind": "taxiway", "pts": [-150, -240, 120, -240]},
	{"name": "Taxiway B", "kind": "taxiway", "pts": [-130, -240, -130, -252]},
	{"name": "Taxiway C", "kind": "taxiway", "pts": [110, -240, 110, -252]},
]
const APRON := Rect2(-240.0, -266.0, 90.0, 37.0)          ## x, z, width, depth (flat concrete)
const AIRPORT_HELIPAD := Vector2(95.0, -217.0)
const HELIPAD_RADIUS := 9.0
const HARBOR_HELIPAD := Vector2(-262.0, 240.0)             ## painted on the marina quay corner deck
const HARBOR_HELIPAD_RADIUS := 6.0
const APRON_DRIVEWAY := Rect2(-200.0, -229.0, 14.0, 2.5)  ## paved link Airfield Road -> apron

## Quay walls (on the 3 m terrain lattice). The port water is west of QUAY_X and south of QUAY_Z.
const QUAY_X := -279.0
const QUAY_Z := 252.0
const QUAY_NORTH := -96.0
const QUAY_EAST := -30.0
const QUAY_DECK_W := 9.5          ## concrete deck width behind the west (docks) quay wall
const QUAY_DECK_S := 4.5          ## deck width behind the south (marina) quay wall
const PIER_X: Array = [-210.0, -150.0, -90.0]   ## marina finger piers (centre x), 4 m wide
const PIER_HALF_W := 2.0
const PIER_END_Z := 284.0
const PIER_RAMP_Z := 260.0
const PIER_DECK_Y := 1.15

## Tram loop (clockwise, on the inner lane of the streets it follows), corner radius.
const TRAM_LOOP: Array = [-118.25, -103.25, 118.0, -103.25, 118.0, 68.25, -118.25, 68.25]
const TRAM_RADIUS := 14.0

## Hill / headland features.
const HILL_CENTRE := Vector2(225.0, -128.0)
const HILL_RADIUS := 92.0
const HILL_HEIGHT := 35.5
const VIEWPOINT := Vector2(166.5, -147.0)
const LIGHTHOUSE := Vector2(8.0, 274.0)
const SHIPWRECK := Vector2(148.0, 298.0)

const DISTRICTS: Array[String] = ["downtown", "midtown", "residential", "industrial", "waterfront", "beach", "hill", "airport", "ocean"]
const DISTRICT_LABELS := {
	"downtown": [0.0, -105.0, "Downtown"], "midtown": [0.0, 70.0, "Midtown"], "residential": [185.0, 60.0, "Sandpiper Heights"],
	"industrial": [-190.0, -30.0, "Foundry Row"], "waterfront": [-110.0, 240.0, "Marina"], "beach": [165.0, 246.0, "Halcyon Beach"],
	"hill": [215.0, -100.0, "Signal Hill"], "airport": [20.0, -250.0, "Halcyon Airfield"],
}

## Generic lot width target and minimum per zone.
const LOT_WIDTH := {"office": 25.0, "apartment": 26.0, "house": 15.0, "storefront": 16.0, "warehouse": 30.0,
		"hangar": 28.0, "parking": 60.0, "park": 40.0, "plaza": 40.0, "landmark": 20.0}
const GROUND_OF_ZONE := {"office": "tiles", "apartment": "pavers", "house": "grass", "storefront": "pavers",
		"warehouse": "concrete", "hangar": "concrete", "parking": "tarmac", "park": "grass", "plaza": "tiles", "landmark": "pavers"}

## City blocks: [id, x0, z0, x1, z1 (bounding road centre lines), district, zone, rows, opts].
## rows: [side N/S/E/W, depth, items]. Items run west->east (N/S rows) or north->south (E/W rows):
## "*" generic lots (block zone), "*zone" generic lots of another zone, "gap:W", "name:WxD" landmark.
## Row side "R" = the remaining interior as one lot of the given zone.
## opts: inner [x0,z0,x1,z1] explicit interior, ground (slab finish), flat (no kerb, for aircraft).
const BLOCKS: Array = [
	["D1", -120, -190, -60, -105, "downtown", "office", [["N", 32, ["*"]], ["S", 32, ["*"]]], {}],
	["D2", -60, -190, 0, -105, "downtown", "office", [["N", 32, ["*"]], ["S", 32, ["*"]]], {}],
	["D3", 0, -190, 60, -105, "downtown", "office", [["N", 32, ["*"]], ["S", 32, ["*"]]], {}],
	["D4", 60, -190, 120, -105, "downtown", "office", [["S", 31, ["parking_garage:34x30"]], ["N", 32, ["*"]]], {}],
	["D5", -120, -105, -60, -20, "downtown", "office", [["N", 33, ["*"]], ["S", 33, ["*"]]], {}],
	["D6", -60, -105, 0, -20, "downtown", "office", [["N", 33, ["*"]], ["S", 33, ["*storefront"]]], {}],
	["D7", 0, -105, 60, -20, "downtown", "plaza", [["N", 6, ["gap:17", "tram_stop_1:14x6"]], ["R", 0, ["plaza"]]], {"ground": "tiles"}],
	["D8", 60, -105, 120, -20, "downtown", "office", [["N", 33, ["*"]], ["S", 33, ["*apartment"]]], {}],
	["M1", -120, -20, -60, 70, "midtown", "storefront", [["N", 32, ["hospital:34x30", "*"]], ["S", 32, ["*", "tram_stop_3:14x6"]]], {}],
	["M2", -60, -20, 0, 70, "midtown", "storefront", [["N", 32, ["*"]], ["S", 32, ["gun_shop:18x16", "*"]]], {}],
	["M3", 0, -20, 60, 70, "midtown", "storefront", [["N", 32, ["clothing_store:18x16", "barber:14x14", "*"]], ["S", 32, ["*"]]], {}],
	["M4", 60, -20, 120, 70, "midtown", "apartment", [["N", 24, ["*"]], ["S", 24, ["*"]], ["E", 8, ["gap:4", "tram_stop_2:14x6"]]], {}],
	["M5", -120, 70, 0, 115, "midtown", "storefront", [["N", 29, ["*", "police_station:30x26", "*"]]], {}],
	["M6", 0, 70, 120, 115, "midtown", "storefront", [["N", 29, ["*"]]], {}],
	["M7", -120, 115, 0, 160, "midtown", "storefront", [["S", 26, ["gas_station:30x24", "*"]]], {}],
	["M8", 0, 115, 120, 160, "midtown", "storefront", [["S", 26, ["*"]]], {}],
	["I1", -215, -190, -120, -105, "industrial", "warehouse", [["N", 32, ["*"]], ["S", 32, ["*"]]], {}],
	["I2", -215, -105, -168, -20, "industrial", "warehouse", [["W", 32, ["*"]]], {}],
	["I3", -168, -105, -120, -20, "industrial", "warehouse", [["E", 34, ["*"]]], {}],
	["I4", -215, -20, -168, 70, "industrial", "warehouse", [["W", 32, ["*"]]], {}],
	["I5", -168, -20, -120, 70, "industrial", "warehouse", [["E", 20, ["mod_garage:24x20", "shooting_range:32x14", "*"]]], {}],
	["I6", -215, 70, -120, 160, "industrial", "warehouse", [["N", 30, ["*"]], ["R", 0, ["plaza"]]], {"ground": "concrete"}],
	["R1", 120, -20, 168, 70, "residential", "house", [["W", 16, ["*"]], ["E", 16, ["*"]]], {}],
	["R2", 168, -20, 215, 70, "residential", "park", [["R", 0, ["park"]]], {}],
	["R3", 120, 70, 215, 115, "residential", "apartment", [["N", 29, ["*"]]], {}],
	["R4", 120, 115, 215, 160, "residential", "house", [["N", 26, ["*"]]], {}],
	["E1", 215, 70, 255, 160, "residential", "house", [["E", 21, ["*"]]], {"inner": [226.0, 77.5, 247.5, 171.0]}],
	["E2", 120, 160, 255, 225, "beach", "storefront", [["S", 22, ["*"]], ["N", 22, ["*parking", "*apartment"]]], {}],
	["W3", 0, 160, 120, 225, "waterfront", "storefront", [["N", 22, ["*apartment"]], ["S", 23, ["general_store:18x16", "*", "gap:8", "safehouse:20x18"]]], {}],
	["W2", -120, 160, 0, 225, "waterfront", "storefront", [["N", 22, ["*"]], ["S", 23, ["*"]]], {}],
	["W1", -262, 160, -120, 225, "waterfront", "warehouse", [["N", 22, ["*"]], ["S", 23, ["*storefront"]]], {"inner": [-254.5, 171.0, -128.5, 217.5]}],
	["K1", -262, -105, -215, 160, "industrial", "warehouse", [["E", 28, ["*"]]], {"inner": [-254.5, -97.5, -226.0, 171.0]}],
	["K0", -262, -190, -215, -105, "industrial", "warehouse", [["E", 30, ["*"]]], {"inner": [-262.0, -186.0, -226.0, -112.5]}],
	["A1", -215, -222, -120, -190, "airport", "parking", [["R", 0, ["parking"]]], {}],
	["A2", -112, -234, 80, -202, "airport", "hangar", [["N", 32, ["airport_tower:14x14", "airport_hangar:32x32", "*"]]],
		{"inner": [-112.0, -234.0, 80.0, -202.0], "flat": true}],
	["MQ", -254, 232, -34, 247, "waterfront", "plaza", [["R", 0, ["plaza"]]], {"inner": [-254.5, 232.5, -34.5, 247.5], "ground": "planks"}],
	["BW", 45, 232, 244, 236, "beach", "plaza", [], {"inner": [45.0, 232.5, 244.0, 236.0], "ground": "planks"}],
]

## Lots that are not part of a block: [landmark, zone, district, x, z, width, depth, yaw].
const EXTRA_LOTS: Array = [
	["lighthouse", "landmark", "waterfront", 8.0, 274.0, 10.0, 10.0, 0.0],
	["radio_mast", "landmark", "hill", 229.0, -131.5, 8.0, 8.0, 0.0],
]

## Residential park paths and the east shore dune trail (also rendered as visible footpaths).
const PARK_LOOP: Array = [178, -5, 201, -5, 201, 58, 178, 58, 178, -5]
const PARK_CROSS: Array = [178, 26, 201, 26]
const DUNE_PATH: Array = [266, 82, 268, 150, 263, 215]
## Walk paths that get a visible ribbon: [points, width m, "slab" (on a block slab) | "terrain" (follows the ground)].
const FOOTPATHS: Array = [[PARK_LOOP, 2.4, "slab"], [PARK_CROSS, 2.0, "slab"], [DUNE_PATH, 1.8, "terrain"]]

## Extra pedestrian paths (x,z pairs); end points are linked to the nearest sidewalk automatically.
const WALK_PATHS: Array = [
	[10, -95, 30, -62, 56, -30], [56, -95, 30, -62, 10, -30],                       # downtown plaza diagonals
	PARK_LOOP, PARK_CROSS,                                                          # residential park
	[-252, 240, -210, 240, -150, 240, -90, 240, -36, 240],                         # marina promenade
	[-210, 231, -210, 240, -210, 256, -210, 282], [-150, 231, -150, 240, -150, 256, -150, 282],
	[-90, 231, -90, 240, -90, 256, -90, 282],                                       # piers
	[-274, -90, -274, 60, -274, 245, -252, 240],                                    # docks quay
	[50, 234, 50, 244, 100, 247, 150, 248, 200, 246, 246, 240],                     # beach
	[100, 234, 100, 247], [200, 234, 200, 246], [150, 234, 150, 248],
	[4, 236, 6, 255, 8, 266],                                                       # lighthouse headland
	DUNE_PATH,                                                                      # east shore dunes
	[175.2, -151.2, 166.5, -147],                                                   # viewpoint spur
]


static func pts2(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		out.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return out


## District of a land position (the caller decides about "ocean").
static func district_at(x: float, z: float) -> String:
	if z < -203.0:
		return "airport"
	if x > 128.0 and z < -30.0:
		return "hill"
	if z > 160.0:
		# blocks east of Sandpiper Avenue and the sand south of the Shore Road belong to the beach
		return "beach" if (x >= 120.0 or (x >= 45.0 and z > 229.5)) else "waterfront"
	if x < -120.0:
		return "industrial"
	if x > 120.0:
		return "beach" if (x > 262.0 and z > 120.0) else "residential"
	return "downtown" if z < -20.0 else "midtown"
