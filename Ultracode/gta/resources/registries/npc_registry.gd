extends RefCounted
## Registers the NPC archetypes (Registry kind "npc_archetypes"). AI module, see docs/AI.md.
## Required ids (ARCHITECTURE_WAVE2 W2.2): civilian_m, civilian_f, civilian_tough, gang_member,
## shop_staff, taxi_driver, police_officer, police_swat, medic, firefighter.

const CIVILIAN_BRAIN := "res://gta/code/ai/brains/ai_brain_civilian.gd"
const STAFF_BRAIN := "res://gta/code/ai/brains/ai_brain_staff.gd"
const GANG_BRAIN := "res://gta/code/ai/brains/ai_brain_gang.gd"
const ARCHETYPE_SCRIPT := "res://gta/code/ai/npc_archetype.gd"


static func register_all(registry: Node) -> void:
	var script: Script = load(ARCHETYPE_SCRIPT)
	if script == null:
		push_warning("npc_registry: npc_archetype.gd missing")
		return
	for d: Dictionary in _defs():
		registry.register("npc_archetypes", script.call("from_dict", d))


static func _defs() -> Array:
	return [
		{
			"id": "civilian_m", "display_name": "Pedestrian", "faction": "civilian", "groups": ["ped"],
			"visuals": ["civilian_m", "business", "beach"], "visual_weights": [0.74, 0.16, 0.10],
			"body": "m",
			"brain_path": CIVILIAN_BRAIN, "max_health": 100.0, "accuracy": 0.25,
			"walk_speed": 1.45, "run_speed": 4.1, "sprint_speed": 5.9,
			"sight_range": 38.0, "sight_fov_deg": 150.0, "bravery": 0.2,
			"cash_min": 10, "cash_max": 140, "ambient_weight": 1.0, "tags": ["ambient"],
		},
		{
			"id": "civilian_f", "display_name": "Pedestrian", "faction": "civilian", "groups": ["ped"],
			"visuals": ["civilian_f", "business", "beach"], "visual_weights": [0.74, 0.16, 0.10],
			"body": "f",
			"brain_path": CIVILIAN_BRAIN, "max_health": 100.0, "accuracy": 0.25,
			"walk_speed": 1.38, "run_speed": 4.0, "sprint_speed": 5.7,
			"sight_range": 38.0, "sight_fov_deg": 150.0, "bravery": 0.15,
			"cash_min": 10, "cash_max": 140, "ambient_weight": 1.0, "tags": ["ambient"],
		},
		{
			"id": "civilian_tough", "display_name": "Tough Local", "faction": "civilian", "groups": ["ped"],
			"visuals": ["civilian_m"],
			"body": "m", "appearance_overrides": {"shoes": "boots"},
			"appearance_choices": {"top": ["tank", "vest", "hoodie", "jacket", "tee"],
				"bottom": ["jeans", "cargo"], "hair": ["buzz", "short", "bald", "slick"],
				"beard": ["full", "goatee", "", "mustache"], "hat": ["", "", "beanie", "cap"]},
			"brain_path": CIVILIAN_BRAIN, "max_health": 130.0, "accuracy": 0.35,
			"walk_speed": 1.5, "run_speed": 4.4, "sprint_speed": 6.1,
			"sight_range": 40.0, "sight_fov_deg": 150.0, "bravery": 0.75, "fights_back": true,
			"weapons": {"fists": 1.0}, "cash_min": 20, "cash_max": 180, "ambient_weight": 0.18,
			"tags": ["ambient", "tough"],
		},
		{
			"id": "gang_member", "display_name": "Gang Member", "faction": "gang", "groups": ["gang"],
			"visuals": ["gang", "gang_b"], "visual_weights": [0.5, 0.5],
			"brain_path": GANG_BRAIN, "max_health": 115.0, "accuracy": 0.42,
			"walk_speed": 1.4, "run_speed": 4.4, "sprint_speed": 6.2,
			"sight_range": 45.0, "sight_fov_deg": 160.0, "bravery": 0.85, "fights_back": true,
			"weapons": {"smg": 0.25, "pistol": 0.75, "bat": 1.0},
			"cash_min": 60, "cash_max": 260, "alertness": 1.4, "tracks_player": true,
			"tags": ["hostile_capable"],
		},
		{
			"id": "shop_staff", "display_name": "Shop Staff", "faction": "staff", "groups": ["staff"],
			"visuals": ["staff"], "brain_path": STAFF_BRAIN, "max_health": 100.0, "accuracy": 0.2,
			"walk_speed": 1.3, "run_speed": 4.0, "sprint_speed": 5.6,
			"sight_range": 25.0, "sight_fov_deg": 170.0, "bravery": 0.1,
			"cash_min": 15, "cash_max": 70, "tracks_player": true,
		},
		{
			"id": "taxi_driver", "display_name": "Cab Driver", "faction": "civilian", "groups": ["ped"],
			"visuals": ["civilian_m", "civilian_f"], "visual_weights": [0.7, 0.3],
			"appearance_choices": {"top": ["shirt", "jacket", "tee", "vest"], "hat": ["cap", "", ""]},
			"brain_path": CIVILIAN_BRAIN, "max_health": 100.0, "accuracy": 0.25,
			"walk_speed": 1.4, "run_speed": 4.0, "sprint_speed": 5.8,
			"sight_range": 38.0, "sight_fov_deg": 150.0, "bravery": 0.3,
			"cash_min": 40, "cash_max": 220, "tags": ["driver"],
		},
		{
			"id": "police_officer", "display_name": "Officer", "faction": "police", "groups": ["police"],
			"visuals": ["police"], "brain_path": "", "max_health": 100.0, "armor": 50.0, "accuracy": 0.58,
			"walk_speed": 1.5, "run_speed": 4.6, "sprint_speed": 6.4,
			"sight_range": 55.0, "sight_fov_deg": 160.0, "bravery": 1.0, "fights_back": true,
			"weapons": {"pistol": 1.0}, "cash_min": 20, "cash_max": 90,
			"alertness": 1.6, "tracks_player": true, "tags": ["law"],
		},
		{
			"id": "police_swat", "display_name": "Tactical Officer", "faction": "police", "groups": ["police"],
			"visuals": ["tactical"], "brain_path": "", "max_health": 100.0, "armor": 100.0, "accuracy": 0.7,
			"walk_speed": 1.5, "run_speed": 4.5, "sprint_speed": 6.2,
			"sight_range": 60.0, "sight_fov_deg": 160.0, "bravery": 1.0, "fights_back": true,
			"weapons": {"carbine": 0.6, "assault_rifle": 1.0}, "cash_min": 20, "cash_max": 90,
			"alertness": 1.8, "tracks_player": true, "tags": ["law"],
		},
		{
			"id": "medic", "display_name": "Paramedic", "faction": "medic", "groups": ["medic"],
			"visuals": ["medic"], "brain_path": CIVILIAN_BRAIN, "max_health": 100.0, "accuracy": 0.2,
			"walk_speed": 1.5, "run_speed": 4.4, "sprint_speed": 6.0,
			"sight_range": 40.0, "sight_fov_deg": 150.0, "bravery": 0.6,
			"cash_min": 15, "cash_max": 70, "tags": ["service"],
		},
		{
			"id": "firefighter", "display_name": "Firefighter", "faction": "fire", "groups": ["fire"],
			"visuals": ["firefighter"], "brain_path": CIVILIAN_BRAIN, "max_health": 120.0, "accuracy": 0.2,
			"walk_speed": 1.45, "run_speed": 4.3, "sprint_speed": 5.9,
			"sight_range": 40.0, "sight_fov_deg": 150.0, "bravery": 0.7,
			"cash_min": 15, "cash_max": 70, "tags": ["service"],
		},
	]
