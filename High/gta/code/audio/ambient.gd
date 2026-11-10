class_name AmbientAudio
extends Node
## World ambience mixer: city hum, ocean, wind, rain, birds, crowd murmur, industrial drone, underwater.

var loops: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	for n in ["amb_city", "amb_ocean", "wind_loop", "amb_rain", "amb_birds", "amb_crowd", "amb_industrial", "amb_underwater"]:
		loops[n] = Sfx.loop2d(n, "Ambient", -60.0)


func _vol(n: String, vol: float, delta: float) -> void:
	var p: AudioStreamPlayer = loops[n]
	var db := linear_to_db(clampf(vol, 0.0001, 1.0))
	p.volume_db = lerpf(p.volume_db, db, clampf(delta * 2.0, 0.0, 1.0))


func _process(delta: float) -> void:
	var p = Game.player
	if p == null:
		return
	var pos: Vector3 = p.global_position
	var dn: DayNight = Game.daynight
	var night := dn.night if dn else 0.0
	var rain: float = dn._w.rain if dn else 0.0
	var wind: float = dn._w.wind if dn else 0.2
	var district := City.district_name(pos)
	var shore := clampf(1.0 - absf(pos.z - 200.0) / 70.0, 0.0, 1.0)
	if district == "Marlow Bay":
		shore = 1.0
	var urban := 0.0
	if district in ["Downtown", "Midtown Market", "Ironworks", "Bayfront", "Port Marlow"]:
		urban = 1.0
	elif district in ["Palm Court", "Founders Park", "Marlow Airfield"]:
		urban = 0.45
	var alt := clampf((pos.y - 20.0) / 60.0, 0.0, 1.0)
	var uw := 1.0 if (Game.cam and Game.cam.underwater) else 0.0
	_vol("amb_city", urban * (0.55 - 0.25 * night) * (1.0 - alt * 0.7) * (1.0 - uw), delta)
	_vol("amb_crowd", urban * 0.3 * (1.0 - night) * (1.0 - rain) * (1.0 - alt) * (1.0 - uw) * (1.0 if district in ["Downtown", "Midtown Market", "Bayfront"] else 0.3), delta)
	_vol("amb_ocean", shore * 0.6 * (1.0 - uw), delta)
	_vol("wind_loop", (0.1 + wind * 0.4 + alt * 0.5) * (1.0 - uw), delta)
	_vol("amb_rain", rain * 0.7 * (1.0 - uw), delta)
	_vol("amb_birds", (1.0 - night) * (1.0 - rain) * (0.5 if district in ["Signal Hill", "Founders Park", "Palm Court"] else 0.08) * (1.0 - uw), delta)
	_vol("amb_industrial", (0.35 if district in ["Ironworks", "Port Marlow"] else 0.0) * (1.0 - uw), delta)
	_vol("amb_underwater", uw * 0.8, delta)
