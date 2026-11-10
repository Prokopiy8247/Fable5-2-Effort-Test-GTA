class_name NpcArchetype
extends Resource
## One NPC archetype (Registry kind "npc_archetypes", registered by
## res://gta/resources/registries/npc_registry.gd). Pure data: the body (NpcBase) and the
## PedSystem read it when an NPC is spawned. See docs/AI.md.

@export var id: String = ""
@export var display_name: String = ""
## "civilian", "police", "gang", "staff", "medic", "fire"
@export var faction: String = "civilian"
## Extra groups the NPC joins besides "npc" ("ped" for civilians, "police", "gang" ...).
@export var groups: PackedStringArray = PackedStringArray()
## CharacterVisual archetypes to pick the look from (weighted by visual_weights; same length).
@export var visuals: PackedStringArray = PackedStringArray(["civilian"])
@export var visual_weights: PackedFloat32Array = PackedFloat32Array()
## Required body cut ("m" / "f"), "" = whatever the visual archetype rolls.
@export var body: String = ""
## Appearance keys forced on top of the random look (e.g. {"top": "vest"}), "" values ignored.
@export var appearance_overrides: Dictionary = {}
## Optional per-key random choices applied on top of the look: key -> Array of values.
@export var appearance_choices: Dictionary = {}
## Default brain script (res:// path). "" = the spawner must pass opts.brain (police) - the
## body then falls back to FALLBACK_BRAIN so it never stands brain-dead.
@export var brain_path: String = ""

@export var max_health: float = 100.0
@export var armor: float = 0.0
## 0..1 base aim quality (W2.2 `accuracy`)
@export var accuracy: float = 0.4
@export var walk_speed: float = 1.45
@export var run_speed: float = 4.2
@export var sprint_speed: float = 6.0
## Sight in metres before weather / daylight scaling, full cone angle in degrees.
@export var sight_range: float = 40.0
@export var sight_fov_deg: float = 150.0
@export var hearing_mult: float = 1.0
## 0 = timid (flees from everything) .. 1 = never panics
@export var bravery: float = 0.2
## true = fights back (fists or its weapon) when attacked
@export var fights_back: bool = false
## weapon id -> chance (0..1), evaluated in order; first hit wins. Empty = unarmed.
@export var weapons: Dictionary = {}
@export var cash_min: int = 0
@export var cash_max: int = 0
## Stealth: how fast the awareness meter of this NPC fills (1 = normal, police / gang higher).
@export var alertness: float = 1.0
## true: tracks the player continuously with the awareness meter (police, gang, staff).
@export var tracks_player: bool = false
## Ambient population weight per district (PedSystem); 0 = never spawned as ambient pedestrian.
@export var ambient_weight: float = 0.0
@export var tags: PackedStringArray = PackedStringArray()

const FALLBACK_BRAIN := "res://gta/code/ai/brains/ai_brain_civilian.gd"


static func from_dict(d: Dictionary) -> NpcArchetype:
	var a := NpcArchetype.new()
	for k: String in d.keys():
		if k in a:
			var v: Variant = d[k]
			match k:
				"groups", "visuals", "tags":
					a.set(k, PackedStringArray(v))
				"visual_weights":
					a.set(k, PackedFloat32Array(v))
				_:
					a.set(k, v)
	return a


## Picks one CharacterVisual archetype id with the given RNG.
func pick_visual(rng: RandomNumberGenerator) -> String:
	if visuals.is_empty():
		return "civilian"
	if visual_weights.size() != visuals.size():
		return visuals[rng.randi() % visuals.size()]
	var total := 0.0
	for w in visual_weights:
		total += w
	var r := rng.randf() * total
	for i in visuals.size():
		r -= visual_weights[i]
		if r <= 0.0:
			return visuals[i]
	return visuals[visuals.size() - 1]


## Picks the starting weapon ("" = unarmed).
func pick_weapon(rng: RandomNumberGenerator) -> String:
	for wid: String in weapons.keys():
		if rng.randf() < float(weapons[wid]):
			return wid
	return ""


## Random look for this archetype: CharacterVisual.make_appearance (looked up softly by the body)
## plus overrides / choices. `base` is the generated dictionary.
func decorate_appearance(base: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var a := base.duplicate()
	for k: String in appearance_choices.keys():
		var opts: Variant = appearance_choices[k]
		if opts is Array and not (opts as Array).is_empty():
			a[k] = (opts as Array)[rng.randi() % (opts as Array).size()]
	for k: String in appearance_overrides.keys():
		var v: Variant = appearance_overrides[k]
		if not (v is String and str(v) == ""):
			a[k] = v
	return a
