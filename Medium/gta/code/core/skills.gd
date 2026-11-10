extends Node3D
## Use-based character stats (0..1). Improve by doing the related activity.

const NAMES := {"stamina": "Stamina", "shooting": "Shooting", "strength": "Strength", "stealth": "Stealth", "driving": "Driving", "flying": "Flying", "lung": "Lung Capacity"}
var v := {"stamina": 0.2, "shooting": 0.2, "strength": 0.2, "stealth": 0.2, "driving": 0.3, "flying": 0.15, "lung": 0.2}


func level(n: String) -> float:
	return v.get(n, 0.0)


func gain(n: String, amount: float) -> void:
	var before: float = v[n]
	v[n] = clamp(before + amount, 0.0, 1.0)
	if int(v[n] * 10.0) > int(before * 10.0):
		G.notify("%s skill increased (%d%%)" % [NAMES[n], int(v[n] * 100.0)], 3.0)
		if G.audio:
			G.audio.play("pickup", -10.0)


func set_all(x: float) -> void:
	for k in v:
		v[k] = x
