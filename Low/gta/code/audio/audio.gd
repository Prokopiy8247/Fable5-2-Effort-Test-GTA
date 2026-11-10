class_name GameAudio
extends Node
# All audio is synthesized at startup (project-owned, no external samples).

const RATE := 22050
var streams: Dictionary = {}
var pool: Array = []
var pool_i := 0
var ui_player: AudioStreamPlayer
var amb: Dictionary = {}
var radio: AudioStreamPlayer
var station := 0
var stations: Array = ["Radio Off", "Neon FM", "Low Tide", "Brass Tacks"]
var skid_p: AudioStreamPlayer
var skid_t := 0.0
var lowpass: AudioEffectLowPassFilter
var step_t := 0.0


func _ready() -> void:
	AudioServer.add_bus()
	AudioServer.set_bus_name(1, "SFX")
	AudioServer.add_bus()
	AudioServer.set_bus_name(2, "Music")
	AudioServer.set_bus_volume_db(2, -8.0)
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 600.0
	AudioServer.add_bus_effect(1, lowpass)
	AudioServer.set_bus_effect_enabled(1, 0, false)
	_build()
	for i in 20:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 9.0
		p.max_distance = 160.0
		add_child(p)
		pool.append(p)
	ui_player = AudioStreamPlayer.new()
	ui_player.bus = "SFX"
	add_child(ui_player)
	skid_p = AudioStreamPlayer.new()
	skid_p.bus = "SFX"
	skid_p.stream = streams["skid"]
	skid_p.volume_db = -60.0
	add_child(skid_p)
	skid_p.play()
	for a in ["city", "ocean", "rain", "wind", "industrial"]:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "SFX"
		p2.stream = streams["amb_" + a]
		p2.volume_db = -60.0
		add_child(p2)
		p2.play()
		amb[a] = p2
	radio = AudioStreamPlayer.new()
	radio.bus = "Music"
	add_child(radio)


# layer: [type(0 noise,1 sine,2 saw,3 square), amp, decay, f0, f1, lowpass(0..1), delay]
func synth(dur: float, layers: Array, loop := false, rate := RATE) -> AudioStreamWAV:
	var n := int(dur * rate)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for L in layers:
		var typ: int = L[0]
		var amp: float = L[1]
		var dec: float = L[2]
		var f0: float = L[3]
		var f1: float = L[4]
		var lp: float = L[5] if L.size() > 5 else 1.0
		var delay: float = L[6] if L.size() > 6 else 0.0
		var ph := 0.0
		var y := 0.0
		var i0 := int(delay * rate)
		for i in range(i0, n):
			var t := float(i - i0) / rate
			var s := 0.0
			if typ == 0:
				s = randf() * 2.0 - 1.0
			else:
				ph += lerp(f0, f1, t / dur) / rate
				var fr := ph - floorf(ph)
				if typ == 1:
					s = sin(TAU * fr)
				elif typ == 2:
					s = fr * 2.0 - 1.0
				else:
					s = 1.0 if fr < 0.5 else -1.0
			y += (s - y) * lp
			buf[i] += y * amp * (exp(-t * dec) if dec > 0.0 else 1.0)
	return _wav(buf, loop, rate)


func _wav(buf: PackedFloat32Array, loop: bool, rate: int) -> AudioStreamWAV:
	var n := buf.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clamp(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = n
	return w


func _music(notes: Array, bpm: float, wave: int, bass: Array, lp: float) -> AudioStreamWAV:
	var rate := 16000
	var beat := 60.0 / bpm
	var total := int(notes.size() * beat * 0.5 * rate)
	var buf := PackedFloat32Array()
	buf.resize(total)
	for layer in [[notes, 0.5, 0.22, wave, 5.0], [bass, 2.0, 0.3, 2, 2.0]]:
		var seq: Array = layer[0]
		var steplen: float = beat * layer[1]
		for k in seq.size():
			var semi = seq[k]
			if semi == null:
				continue
			var f: float = 110.0 * pow(2.0, semi / 12.0)
			var i0 := int(k * steplen * rate)
			var cnt := int(steplen * rate * 0.95)
			var ph := 0.0
			var y := 0.0
			for i in cnt:
				if i0 + i >= total:
					break
				ph += f / rate
				var fr := ph - floorf(ph)
				var s: float = sin(TAU * fr) if layer[3] == 1 else ((fr * 2.0 - 1.0) if layer[3] == 2 else (1.0 if fr < 0.5 else -1.0))
				y += (s - y) * lp
				var t := float(i) / rate
				buf[i0 + i] += y * layer[2] * exp(-t * layer[4]) * min(1.0, t * 200.0)
	# simple hat on every half beat
	var hl := int(beat * 0.5 * rate)
	var q := 0
	while q * hl < total:
		for i in min(400, total - q * hl):
			buf[q * hl + i] += (randf() - 0.5) * 0.12 * exp(-i / 90.0)
		q += 1
	return _wav(buf, true, rate)


func _build() -> void:
	var s := streams
	s["shot_pistol"] = synth(0.28, [[0, 0.9, 28.0, 0, 0, 0.7], [1, 0.6, 22.0, 190, 60]])
	s["shot_smg"] = synth(0.2, [[0, 0.8, 38.0, 0, 0, 0.85], [1, 0.4, 30.0, 240, 90]])
	s["shot_rifle"] = synth(0.32, [[0, 0.95, 24.0, 0, 0, 0.6], [1, 0.6, 18.0, 150, 50], [0, 0.2, 8.0, 0, 0, 0.15]])
	s["shot_heavy"] = synth(0.45, [[0, 1.0, 16.0, 0, 0, 0.5], [1, 0.8, 12.0, 120, 40]])
	s["shot_shotgun"] = synth(0.5, [[0, 1.0, 12.0, 0, 0, 0.4], [1, 0.7, 14.0, 110, 40], [0, 0.4, 30.0, 0, 0, 0.9]])
	s["shot_sniper"] = synth(0.9, [[0, 1.0, 10.0, 0, 0, 0.45], [1, 0.8, 9.0, 100, 35], [0, 0.25, 3.0, 0, 0, 0.1, 0.12]])
	s["shot_rocket"] = synth(0.9, [[0, 0.8, 3.0, 0, 0, 0.25], [2, 0.3, 4.0, 90, 300, 0.4]])
	s["shot_silenced"] = synth(0.12, [[0, 0.35, 45.0, 0, 0, 0.3], [1, 0.2, 40.0, 300, 150]])
	s["explosion"] = synth(1.8, [[0, 1.0, 3.2, 0, 0, 0.12], [1, 0.9, 4.0, 85, 28], [0, 0.6, 14.0, 0, 0, 0.7]])
	s["reload"] = synth(0.5, [[0, 0.5, 60.0, 0, 0, 0.9], [0, 0.6, 50.0, 0, 0, 0.6, 0.3], [3, 0.2, 70.0, 900, 700, 1.0, 0.3]])
	s["click"] = synth(0.08, [[0, 0.4, 90.0, 0, 0, 0.9], [3, 0.2, 80.0, 1200, 900]])
	s["punch"] = synth(0.2, [[0, 0.7, 30.0, 0, 0, 0.2], [1, 0.8, 28.0, 120, 50]])
	s["swing"] = synth(0.22, [[0, 0.35, 12.0, 0, 0, 0.5]])
	s["crash"] = synth(0.6, [[0, 0.9, 9.0, 0, 0, 0.5], [3, 0.25, 12.0, 320, 180, 0.6], [1, 0.5, 14.0, 90, 50]])
	s["pop"] = synth(0.35, [[0, 0.8, 14.0, 0, 0, 0.35], [1, 0.4, 20.0, 300, 80]])
	s["horn"] = synth(0.45, [[3, 0.3, 0.0, 420, 420, 0.35], [3, 0.3, 0.0, 525, 525, 0.35]])
	s["siren"] = synth(1.4, [[2, 0.3, 0.0, 650, 1250, 0.3], [1, 0.25, 0.0, 650, 1250]], true)
	s["engine"] = synth(0.5, [[2, 0.35, 0.0, 80, 80, 0.25], [3, 0.2, 0.0, 40, 40, 0.2], [0, 0.08, 0.0, 0, 0, 0.3]], true)
	s["boat"] = synth(0.5, [[2, 0.35, 0.0, 60, 60, 0.2], [0, 0.2, 0.0, 0, 0, 0.2]], true)
	s["prop"] = synth(0.5, [[2, 0.4, 0.0, 110, 110, 0.3], [3, 0.2, 0.0, 55, 55, 0.3], [0, 0.12, 0.0, 0, 0, 0.4]], true)
	var hb := PackedFloat32Array()
	hb.resize(int(0.5 * RATE))
	var yy := 0.0
	for i in hb.size():
		var t := float(i) / RATE
		yy += ((randf() * 2.0 - 1.0) - yy) * 0.25
		hb[i] = yy * (0.35 + 0.65 * pow(abs(sin(TAU * 6.0 * t)), 3.0)) * 0.9 + sin(TAU * 48.0 * t) * 0.15
	s["heli"] = _wav(hb, true, RATE)
	s["step"] = synth(0.09, [[0, 0.3, 50.0, 0, 0, 0.25]])
	s["pickup"] = synth(0.22, [[1, 0.4, 10.0, 600, 1300], [1, 0.2, 10.0, 900, 1900]])
	s["ui_click"] = synth(0.06, [[1, 0.35, 50.0, 880, 880]])
	s["ui_buy"] = synth(0.25, [[1, 0.35, 12.0, 660, 990], [1, 0.25, 12.0, 990, 1320, 1.0, 0.08]])
	s["ui_deny"] = synth(0.2, [[3, 0.2, 14.0, 180, 140, 0.4]])
	s["star"] = synth(0.3, [[3, 0.25, 9.0, 740, 740, 0.4], [3, 0.2, 9.0, 1108, 1108, 0.4, 0.1]])
	s["splash"] = synth(0.6, [[0, 0.6, 7.0, 0, 0, 0.3]])
	s["impact"] = synth(0.1, [[0, 0.5, 50.0, 0, 0, 0.5]])
	s["impact_metal"] = synth(0.16, [[0, 0.3, 50.0, 0, 0, 0.9], [1, 0.35, 28.0, 2100, 1700]])
	s["skid"] = synth(0.6, [[0, 0.5, 0.0, 0, 0, 0.5], [2, 0.12, 0.0, 900, 950, 0.5]], true)
	s["chute"] = synth(0.5, [[0, 0.7, 6.0, 0, 0, 0.15]])
	s["thunder"] = synth(2.2, [[0, 1.0, 1.6, 0, 0, 0.05], [1, 0.5, 2.0, 50, 30]])
	s["amb_city"] = synth(3.0, [[0, 0.5, 0.0, 0, 0, 0.02], [1, 0.05, 0.0, 60, 60]], true)
	s["amb_ocean"] = _ocean()
	s["amb_rain"] = synth(2.0, [[0, 0.5, 0.0, 0, 0, 0.6]], true)
	s["amb_wind"] = synth(3.0, [[0, 0.6, 0.0, 0, 0, 0.04]], true)
	s["amb_industrial"] = synth(2.0, [[2, 0.12, 0.0, 50, 50, 0.1], [0, 0.2, 0.0, 0, 0, 0.03], [3, 0.03, 0.0, 100, 100, 0.1]], true)
	s["radio1"] = _music([0, 7, 12, 7, 3, 7, 15, 7, 5, 8, 12, 8, 7, 10, 14, 10, 0, 7, 12, 7, 3, 7, 15, 7, 5, 8, 17, 8, 7, 10, 19, 14], 120.0, 2, [-12, -9, -7, -5, -12, -9, -7, -5], 0.3)
	s["radio2"] = _music([12, null, 15, null, 19, null, 17, null, 12, null, 14, null, 15, null, 10, null, 8, null, 12, null, 15, null, 14, null], 76.0, 1, [-12, -16, -17, -14, -16, -19], 0.6)
	s["radio3"] = _music([0, null, 0, 3, null, 5, 0, null, 7, null, 5, 3, null, 0, 10, null, 0, null, 0, 3, null, 5, 6, 7, 12, null, 10, 7, null, 5, 3, null], 104.0, 3, [-12, -12, -7, -9, -12, -12, -5, -7], 0.22)


func _ocean() -> AudioStreamWAV:
	var n := int(4.0 * RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += ((randf() * 2.0 - 1.0) - y) * 0.08
		b[i] = y * (0.35 + 0.65 * pow(0.5 + 0.5 * sin(TAU * t / 4.0), 2.0)) * 1.4
	return _wav(b, true, RATE)


func play3d(sname: String, pos: Vector3, vol := 1.0, pitch := 1.0) -> void:
	if not streams.has(sname):
		return
	if G.cam and G.cam.global_position.distance_squared_to(pos) > 170.0 * 170.0:
		return
	var p: AudioStreamPlayer3D = pool[pool_i]
	pool_i = (pool_i + 1) % pool.size()
	p.stream = streams[sname]
	p.global_position = pos
	p.volume_db = linear_to_db(max(vol, 0.01))
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.unit_size = 22.0 if (sname.begins_with("shot") or sname == "explosion") else 8.0
	p.play()


func ui(sname: String) -> void:
	var k := "ui_" + sname if streams.has("ui_" + sname) else sname
	if streams.has(k):
		ui_player.stream = streams[k]
		ui_player.play()


func skid(dur: float) -> void:
	skid_t = dur


func set_station(i: int) -> void:
	station = wrapi(i, 0, stations.size())
	radio.stop()
	if station > 0:
		radio.stream = streams["radio%d" % station]


func _process(dt: float) -> void:
	skid_t -= dt
	skid_p.volume_db = lerp(skid_p.volume_db, -8.0 if skid_t > 0.0 else -60.0, dt * 12.0)
	var pl = G.player
	if pl == null or G.cam == null:
		return
	var cp: Vector3 = G.cam.global_position
	var under: bool = cp.y < G.WATER_Y
	AudioServer.set_bus_effect_enabled(1, 0, under)
	var coast: float = clamp(1.0 - abs(cp.z - 215.0) / 90.0, 0.0, 1.0)
	coast = max(coast, clamp((abs(cp.x) - 230.0) / 60.0, 0.0, 1.0))
	var cityf: float = clamp(1.0 - Vector2(cp.x + 40.0, cp.z + 40.0).length() / 260.0, 0.0, 1.0)
	var ind: float = clamp(1.0 - Vector2(cp.x + 60.0, cp.z + 160.0).length() / 110.0, 0.0, 1.0)
	var high: float = clamp((cp.y - 12.0) / 40.0, 0.0, 1.0)
	var rain: float = G.sky.rain_amount if G.sky else 0.0
	_amb("city", cityf * 0.5 * (1.0 - high * 0.6), dt)
	_amb("ocean", coast * 0.55, dt)
	_amb("rain", rain * 0.6, dt)
	_amb("wind", max(high * 0.6, 0.12 + (G.sky.wind if G.sky else 0.0) * 0.4), dt)
	_amb("industrial", ind * 0.35, dt)
	# radio only inside motor vehicles
	var in_veh: bool = pl.vehicle != null and not pl.vehicle.def.get("pedal", false) and not pl.dead
	if in_veh and station > 0:
		if not radio.playing:
			radio.play()
	elif radio.playing:
		radio.stop()
	# footsteps
	if pl.state == "normal" and pl.is_on_floor():
		var sp := Vector2(pl.velocity.x, pl.velocity.z).length()
		if sp > 1.0:
			step_t -= dt * sp
			if step_t <= 0.0:
				step_t = 1.9
				play3d("step", pl.global_position, 0.25 if pl.crouching else 0.6)


func _amb(aname: String, vol: float, dt: float) -> void:
	var p: AudioStreamPlayer = amb[aname]
	p.volume_db = lerp(p.volume_db, linear_to_db(max(vol, 0.001)), dt * 3.0)
