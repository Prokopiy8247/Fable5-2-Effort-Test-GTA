class_name UiStats
extends Node
## Free-roam statistics shown on the status screen (child of the UI autoload: UI.stats).
## Pure bookkeeping from EventBus signals + a 1 Hz position sample; saved through SaveSystem
## (provider key "ui_stats"). No objectives, no unlocks - just numbers.

const LABELS := {
	"distance_foot": "Distance on foot", "distance_vehicle": "Distance by vehicle", "top_speed": "Top speed",
	"shots_fired": "Shots fired", "kills": "Takedowns", "vehicles_stolen": "Vehicles stolen",
	"vehicles_destroyed": "Vehicles destroyed", "max_wanted": "Highest wanted level",
	"wanted_escapes": "Wanted levels escaped", "times_down": "Times down", "times_arrested": "Times arrested",
	"money_earned": "Money earned", "money_spent": "Money spent", "purchases": "Items purchased",
}
const ORDER: Array[String] = ["distance_foot", "distance_vehicle", "top_speed", "shots_fired", "kills",
		"vehicles_stolen", "vehicles_destroyed", "max_wanted", "wanted_escapes", "times_down", "times_arrested",
		"money_earned", "money_spent", "purchases"]

var values: Dictionary = {}
var _last_pos: Vector3 = Vector3.INF
var _timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	reset()
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.npc_died.connect(_on_npc_died)
	EventBus.vehicle_stolen.connect(_on_vehicle_stolen)
	EventBus.vehicle_destroyed.connect(_on_vehicle_destroyed)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.wanted_level_changed.connect(_on_wanted_level)
	EventBus.wanted_cleared.connect(_on_wanted_cleared)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_busted.connect(_on_player_busted)
	EventBus.item_purchased.connect(_on_item_purchased)
	SaveSystem.register_provider("ui_stats", self)


func reset() -> void:
	values = {}
	for k in ORDER:
		values[k] = 0.0


func get_value(key: String) -> float:
	return float(values.get(key, 0.0))


## Formatted value for the status screen.
func format(key: String) -> String:
	var v := get_value(key)
	match key:
		"distance_foot", "distance_vehicle":
			return "%.2f km" % (v / 1000.0) if v >= 1000.0 else "%d m" % int(v)
		"top_speed":
			return "%d km/h" % int(v)
		"money_earned", "money_spent":
			return UiStyle.money(int(v))
		"max_wanted":
			return "%d / 5" % int(v)
	return str(int(v))


func add(key: String, amount: float = 1.0) -> void:
	values[key] = get_value(key) + amount


func get_save_data() -> Dictionary:
	return values.duplicate()


func load_save_data(d: Dictionary) -> void:
	reset()
	for k in ORDER:
		if d.has(k) and (d[k] is float or d[k] is int):
			values[k] = float(d[k])
	_last_pos = Vector3.INF


func _process(delta: float) -> void:
	_timer += delta
	if _timer < 1.0:
		return
	_timer = 0.0
	if not Game.is_ready or not Game.has_player():
		return
	var p := Game.get_player_position()
	if _last_pos != Vector3.INF:
		var d := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
		if d > 0.05 and d < 120.0:
			var veh := Game.get_player_vehicle()
			if veh != null:
				add("distance_vehicle", d)
				var sp := absf(UiKit.num(veh, &"speed_kmh"))
				if sp > get_value("top_speed"):
					values["top_speed"] = sp
			else:
				add("distance_foot", d)
	_last_pos = p


func _is_player(n: Variant) -> bool:
	if n == null or not (n is Object) or not is_instance_valid(n) or not Game.has_player():
		return false
	return n == Game.player or n == Game.get_player_vehicle()


func _on_weapon_fired(_weapon_id: String, shooter: Node, _origin: Vector3, _direction: Vector3) -> void:
	if _is_player(shooter):
		add("shots_fired")


func _on_npc_died(_npc: Node3D, killer: Node, _info: Dictionary) -> void:
	if _is_player(killer):
		add("kills")


func _on_vehicle_stolen(_vehicle: Node3D, thief: Node, _had_driver: bool) -> void:
	if _is_player(thief):
		add("vehicles_stolen")


func _on_vehicle_destroyed(_vehicle: Node3D, instigator: Node) -> void:
	if _is_player(instigator):
		add("vehicles_destroyed")


func _on_money_changed(_amount: int, delta_amount: int) -> void:
	if not Game.is_ready:
		return
	if delta_amount > 0:
		add("money_earned", float(delta_amount))
	elif delta_amount < 0:
		add("money_spent", float(-delta_amount))


func _on_wanted_level(level: int, _previous: int) -> void:
	if float(level) > get_value("max_wanted"):
		values["max_wanted"] = float(level)


func _on_wanted_cleared(reason: String) -> void:
	if reason == "escaped":
		add("wanted_escapes")


func _on_player_died(_cause: String) -> void:
	add("times_down")


func _on_player_busted() -> void:
	add("times_arrested")


func _on_item_purchased(_kind: String, _id: String, _price: int) -> void:
	add("purchases")
