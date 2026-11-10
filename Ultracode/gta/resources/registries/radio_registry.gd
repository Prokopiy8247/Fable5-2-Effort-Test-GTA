extends RefCounted
## Registry kind "radio_stations": the five original Halcyon Bay stations.
## Music is composed procedurally by tools/audio/music.py (station ids must match its STATIONS
## table); every station has two seamless loops radio_<id>_1 / radio_<id>_2.
## Definition keys: id, name, display_name (HUD caption, frequency shown separately), genre, frequency, tagline, color, tracks, volume_db, order.

const STATIONS: Array[Dictionary] = [
	{
		"id": "neon_tide", "name": "Neon Tide FM", "display_name": "Neon Tide FM", "genre": "Synthwave", "frequency": "101.5",
		"tagline": "Night drives, chrome skies.",
		"color": Color(1.0, 0.36, 0.62), "order": 0, "volume_db": -1.0,
		"tracks": ["radio_neon_tide_1", "radio_neon_tide_2"],
	},
	{
		"id": "low_tide", "name": "Low Tide Lounge", "display_name": "Low Tide Lounge", "genre": "Lo-fi Hip-Hop", "frequency": "88.3",
		"tagline": "Slow beats for slow traffic.",
		"color": Color(0.98, 0.78, 0.36), "order": 1, "volume_db": 0.0,
		"tracks": ["radio_low_tide_1", "radio_low_tide_2"],
	},
	{
		"id": "boogie_bay", "name": "Boogie Bay 98.7", "display_name": "Boogie Bay", "genre": "Funk / Disco", "frequency": "98.7",
		"tagline": "Four on the floor since sunrise.",
		"color": Color(1.0, 0.55, 0.2), "order": 2, "volume_db": -1.0,
		"tracks": ["radio_boogie_bay_1", "radio_boogie_bay_2"],
	},
	{
		"id": "breakwater", "name": "Breakwater", "display_name": "Breakwater", "genre": "Drum & Bass", "frequency": "107.9",
		"tagline": "172 beats per minute of pier pressure.",
		"color": Color(0.25, 0.85, 0.8), "order": 3, "volume_db": -1.5,
		"tracks": ["radio_breakwater_1", "radio_breakwater_2"],
	},
	{
		"id": "drift", "name": "Halcyon Drift", "display_name": "Halcyon Drift", "genre": "Ambient / Chill", "frequency": "93.1",
		"tagline": "Let the bay breathe.",
		"color": Color(0.55, 0.7, 1.0), "order": 4, "volume_db": 0.0,
		"tracks": ["radio_drift_1", "radio_drift_2"],
	},
]


static func register_all(registry: Node) -> void:
	for def: Dictionary in STATIONS:
		registry.register("radio_stations", def.duplicate(true))
