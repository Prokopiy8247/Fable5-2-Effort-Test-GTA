class_name Wildlife
extends Node
## Region-based wildlife spawning (hill, park, coast, sea). Keeps counts small and only near the player.

const REGIONS := [
	{"species": "deer", "home": Vector3(-252, 0, -120), "r": 30.0, "n": 3},
	{"species": "deer", "home": Vector3(-262, 0, -50), "r": 22.0, "n": 2},
	{"species": "boar", "home": Vector3(-240, 0, -165), "r": 16.0, "n": 2},
	{"species": "cow", "home": Vector3(-262, 0, 16), "r": 12.0, "n": 3},
	{"species": "dog", "home": Vector3(-150, 0.2, -40), "r": 28.0, "n": 2},
	{"species": "dog", "home": Vector3(-150, 0.2, 60), "r": 30.0, "n": 1},
	{"species": "seagull", "home": Vector3(-80, 0, 205), "r": 40.0, "n": 4},
	{"species": "seagull", "home": Vector3(170, 0, 205), "r": 35.0, "n": 3},
	{"species": "seagull", "home": Vector3(-40, 0, 262), "r": 20.0, "n": 2},
	{"species": "fish", "home": Vector3(-170, -6, 258), "r": 6.0, "n": 5},
	{"species": "fish", "home": Vector3(-60, -4, 236), "r": 5.0, "n": 4},
	{"species": "fish", "home": Vector3(60, -4, 240), "r": 5.0, "n": 4},
	{"species": "shark", "home": Vector3(-110, -4, 285), "r": 34.0, "n": 1},
	{"species": "shark", "home": Vector3(140, -4, 262), "r": 26.0, "n": 1},
]

var active: Array = []   # per region: Array of animals
var _t := 0.0


func _ready() -> void:
	Game.wildlife = self
	for r in REGIONS:
		active.append([])


func clear_all() -> void:
	for arr in active:
		for a in arr:
			if is_instance_valid(a):
				a.queue_free()
		arr.clear()


func _physics_process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	var p = Game.player
	if p == null:
		return
	for i in range(REGIONS.size()):
		var r: Dictionary = REGIONS[i]
		var arr: Array = active[i]
		var d: float = (r.home as Vector3).distance_to(p.global_position)
		var j := 0
		while j < arr.size():
			if not is_instance_valid(arr[j]):
				arr.remove_at(j)
			else:
				j += 1
		if not Game.flags.wildlife or d > 240.0:
			for a in arr:
				a.queue_free()
			arr.clear()
			continue
		if d < 170.0 and arr.size() < int(r.n):
			var ang := Game.rng.randf() * TAU
			var pos: Vector3 = r.home + Vector3(cos(ang), 0, sin(ang)) * Game.rng.randf_range(1.0, r.r)
			if r.species in ["fish", "shark"]:
				pos.y = r.home.y
			elif r.species == "seagull":
				pos.y = 16.0
			else:
				pos.y = maxf(City.terrain_height(pos.x, pos.z), 0.0) + 0.2
				if City.terrain_height(pos.x, pos.z) < Game.WATER_Y:
					continue
			arr.append(Animal.spawn(r.species, pos, r.home, r.r))
