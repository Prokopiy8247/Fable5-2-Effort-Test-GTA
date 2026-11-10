class_name BootManifest
extends RefCounted
## Ordered list of world systems that Main instantiates at boot.
## A system is a Script (extends Node/Node3D) or a PackedScene at a FIXED path.
## Missing files are skipped silently, so modules can be developed independently:
## to add a system you only create the file at the agreed path - no shared edits.
##
## Optional methods on a system node:
##   func setup() -> void            called once after add_child (may be a coroutine / use await)
##   func set_enabled(on: bool)      admin-menu toggle
##   func get_save_data() -> Dictionary / func load_save_data(d: Dictionary)   persistence hooks
##   func reset_for_respawn()        called after death / busted

const PLAYER_SCENE := "res://gta/scenes/characters/player.tscn"

const SYSTEMS: Array[Dictionary] = [
	{"name": "world", "path": "res://gta/code/world/world.gd"},
	{"name": "environment", "path": "res://gta/code/world/environment_system.gd"},
	{"name": "city", "path": "res://gta/code/world/city_builder.gd"},
	{"name": "interactions", "path": "res://gta/code/world/interaction_system.gd"},
	{"name": "vehicles", "path": "res://gta/code/vehicles/vehicle_manager.gd"},
	{"name": "pickups", "path": "res://gta/code/weapons/pickup_system.gd"},
	{"name": "props", "path": "res://gta/code/world/prop_system.gd"},
	{"name": "traffic", "path": "res://gta/code/traffic/traffic_system.gd"},
	{"name": "peds", "path": "res://gta/code/ai/ped_system.gd"},
	{"name": "police", "path": "res://gta/code/police/police_system.gd"},
	{"name": "emergency", "path": "res://gta/code/ai/emergency_system.gd"},
	{"name": "wildlife", "path": "res://gta/code/ai/wildlife_system.gd"},
	{"name": "shops", "path": "res://gta/code/world/shop_system.gd"},
	{"name": "garage", "path": "res://gta/code/vehicles/garage_system.gd"},
	{"name": "transit", "path": "res://gta/code/traffic/transit_system.gd"},
	{"name": "taxi", "path": "res://gta/code/traffic/taxi_system.gd"},
	{"name": "activities", "path": "res://gta/code/world/activity_system.gd"},
	{"name": "radio", "path": "res://gta/code/audio/radio_system.gd"},
	{"name": "ambience", "path": "res://gta/code/audio/ambience_system.gd"},
	{"name": "respawn", "path": "res://gta/code/player/respawn_system.gd"},
	{"name": "debug", "path": "res://gta/code/debug/debug_system.gd"},
]
