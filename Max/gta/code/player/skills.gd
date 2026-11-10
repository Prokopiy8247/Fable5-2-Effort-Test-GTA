class_name Skills
extends Node
## Use-based character stats (0..1). They improve by doing the activity and give modest,
## noticeable bonuses; nothing in the sandbox is gated behind them.

const LIST: Array[StringName] = [&"stamina", &"shooting", &"strength", &"stealth", &"driving", &"flying", &"lung"]
const NAMES := {&"stamina": "Stamina", &"shooting": "Shooting", &"strength": "Strength", &"stealth": "Stealth",
	&"driving": "Driving", &"flying": "Flying", &"lung": "Lung Capacity"}
const DESC := {&"stamina": "Longer sprints, faster swimming", &"shooting": "Tighter spread, less recoil, quicker reloads",
	&"strength": "Harder melee hits, tougher in falls", &"stealth": "Quieter steps, harder to notice",
	&"driving": "More grip and control in vehicles", &"flying": "Steadier aircraft handling",
	&"lung": "More time under water"}

var values: Dictionary = {}

func _ready() -> void:
	for s in LIST:
		if not values.has(s):
			values[s] = 0.2

func level(s: StringName) -> float:
	return float(values.get(s, 0.0))

func add(s: StringName, amount: float) -> void:
	if not values.has(s) or amount <= 0.0:
		return
	var before := float(values[s])
	if before >= 1.0:
		return
	var after := minf(1.0, before + amount)
	values[s] = after
	if int(after * 10.0) > int(before * 10.0):
		Game.notify("%s increased to %d%%" % [NAMES[s], int(round(after * 100.0))], "good")
		Audio.play_ui(&"ui_skill_up", -8.0)
		Events.skill_changed.emit(s, after)

func set_all(v: float) -> void:
	for s in LIST:
		values[s] = clampf(v, 0.0, 1.0)
	Events.skill_changed.emit(&"all", v)

func save_state() -> Dictionary:
	var out := {}
	for s in LIST:
		out[String(s)] = values[s]
	return out

func load_state(d: Dictionary) -> void:
	for s in LIST:
		if d.has(String(s)):
			values[s] = clampf(float(d[String(s)]), 0.0, 1.0)
