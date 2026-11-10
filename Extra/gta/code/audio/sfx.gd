extends Node
## Sfx - fully procedural audio (autoload): every sound is synthesised at runtime into AudioStreamWAV
## buffers (no external or copyrighted audio). One-shots, vehicle engine / siren / rotor loops,
## ambience beds (city, ocean, rain, wind, industry) and original procedural radio stations.

const RATE := 22050

# layer: ["n", offset, dur, attack, decay, lowpass 0..1, gain]  |  ["t", offset, f0, f1, dur, decay, gain, wave]
const DEFS := {
	"shot_pistol": [["n", 0, 0.22, 0.0, 18, 0.6, 1.0], ["t", 0, 180, 60, 0.12, 25, 0.7, 0]],
	"shot_heavy": [["n", 0, 0.36, 0.0, 12, 0.5, 1.0], ["t", 0, 140, 45, 0.2, 14, 0.9, 0]],
	"shot_smg": [["n", 0, 0.14, 0.0, 28, 0.75, 0.9], ["t", 0, 220, 90, 0.08, 30, 0.6, 0]],
	"shot_rifle": [["n", 0, 0.3, 0.0, 15, 0.7, 1.0], ["t", 0, 200, 55, 0.14, 20, 0.7, 0]],
	"shot_shotgun": [["n", 0, 0.46, 0.0, 9, 0.45, 1.0], ["t", 0, 120, 40, 0.25, 12, 0.9, 0]],
	"shot_sniper": [["n", 0, 0.75, 0.0, 6, 0.55, 1.0], ["t", 0, 150, 35, 0.35, 9, 1.0, 0]],
	"shot_rocket": [["n", 0, 1.0, 0.05, 3.2, 0.35, 0.9], ["t", 0, 300, 80, 0.8, 4, 0.4, 2]],
	"shot_thump": [["t", 0, 160, 70, 0.16, 18, 1.0, 0], ["n", 0, 0.1, 0.0, 30, 0.3, 0.6]],
	"shot_silenced": [["n", 0, 0.08, 0.0, 45, 0.25, 0.5], ["t", 0, 400, 200, 0.04, 60, 0.3, 0]],
	"explosion": [["n", 0, 1.7, 0.0, 2.6, 0.16, 1.0], ["t", 0, 90, 28, 0.9, 4, 1.0, 0], ["n", 0, 0.3, 0.0, 14, 0.8, 0.8]],
	"thunder": [["n", 0, 2.6, 0.02, 1.3, 0.07, 1.0], ["n", 0, 0.4, 0.0, 6, 0.3, 0.6]],
	"crash": [["n", 0, 0.35, 0.0, 10, 0.5, 1.0], ["t", 0, 300, 120, 0.1, 20, 0.4, 1], ["n", 0.02, 0.15, 0.0, 30, 0.9, 0.6]],
	"hit_metal": [["t", 0, 1800, 1400, 0.12, 30, 0.3, 1], ["n", 0, 0.05, 0.0, 60, 0.9, 0.4]],
	"hit_concrete": [["n", 0, 0.09, 0.0, 40, 0.5, 0.6]],
	"hit_flesh": [["n", 0, 0.1, 0.0, 35, 0.2, 0.8], ["t", 0, 120, 80, 0.06, 40, 0.5, 0]],
	"glass": [["n", 0, 0.36, 0.0, 9, 1.0, 0.5], ["t", 0, 3200, 2400, 0.2, 12, 0.22, 0], ["t", 0.03, 4100, 3300, 0.2, 14, 0.18, 0]],
	"splash": [["n", 0, 0.6, 0.05, 5, 0.35, 0.8]],
	"tire_pop": [["n", 0, 0.2, 0.0, 20, 0.6, 0.9], ["t", 0, 600, 100, 0.12, 25, 0.5, 0]],
	"horn": [["t", 0, 440, 440, 0.42, 0.6, 0.4, 1], ["t", 0, 554, 554, 0.42, 0.6, 0.4, 1]],
	"horn_truck": [["t", 0, 220, 220, 0.6, 0.5, 0.5, 2], ["t", 0, 277, 277, 0.6, 0.5, 0.5, 2]],
	"horn_melody": [["t", 0, 523, 523, 0.14, 3, 0.4, 1], ["t", 0.15, 659, 659, 0.14, 3, 0.4, 1], ["t", 0.3, 784, 784, 0.14, 3, 0.4, 1], ["t", 0.45, 1046, 1046, 0.3, 3, 0.4, 1]],
	"step": [["n", 0, 0.06, 0.0, 50, 0.25, 0.5]],
	"jump": [["n", 0, 0.1, 0.02, 30, 0.2, 0.4]],
	"land": [["n", 0, 0.12, 0.0, 28, 0.18, 0.7], ["t", 0, 100, 60, 0.08, 30, 0.5, 0]],
	"swing": [["n", 0, 0.2, 0.08, 12, 0.5, 0.4]],
	"punch": [["n", 0, 0.08, 0.0, 40, 0.2, 0.9], ["t", 0, 150, 70, 0.07, 35, 0.7, 0]],
	"whack": [["n", 0, 0.1, 0.0, 35, 0.4, 0.9], ["t", 0, 250, 90, 0.08, 30, 0.7, 0]],
	"thud": [["n", 0, 0.12, 0.0, 25, 0.15, 0.9], ["t", 0, 90, 50, 0.1, 25, 0.8, 0]],
	"equip": [["t", 0, 900, 700, 0.04, 40, 0.25, 1], ["n", 0, 0.03, 0.0, 80, 0.8, 0.3]],
	"reload": [["n", 0, 0.03, 0.0, 90, 0.9, 0.5], ["t", 0, 1200, 1100, 0.02, 80, 0.2, 1], ["n", 0.28, 0.04, 0.0, 80, 0.7, 0.6], ["t", 0.46, 800, 600, 0.03, 60, 0.3, 1]],
	"dry": [["t", 0, 1500, 1500, 0.02, 90, 0.3, 1]],
	"hurt": [["t", 0, 190, 120, 0.16, 12, 0.6, 2], ["n", 0, 0.1, 0.0, 30, 0.3, 0.2]],
	"grunt": [["t", 0, 170, 110, 0.14, 14, 0.6, 2], ["n", 0, 0.08, 0.0, 30, 0.3, 0.2]],
	"scream": [["t", 0, 760, 520, 0.5, 3, 0.45, 2], ["t", 0, 1150, 800, 0.5, 4, 0.15, 0]],
	"death": [["t", 0, 210, 70, 0.6, 5, 0.6, 2], ["n", 0, 0.3, 0.0, 8, 0.2, 0.2]],
	"busted": [["t", 0, 660, 660, 0.14, 4, 0.4, 1], ["t", 0.16, 520, 520, 0.14, 4, 0.4, 1], ["t", 0.32, 390, 390, 0.3, 3, 0.4, 1]],
	"wanted_up": [["t", 0, 700, 700, 0.09, 6, 0.4, 1], ["t", 0.11, 1050, 1050, 0.14, 6, 0.4, 1]],
	"wanted_clear": [["t", 0, 880, 880, 0.1, 6, 0.3, 0], ["t", 0.11, 660, 660, 0.1, 6, 0.3, 0], ["t", 0.22, 440, 440, 0.22, 5, 0.3, 0]],
	"radio_blip": [["n", 0, 0.05, 0.0, 50, 0.9, 0.3], ["t", 0.03, 1000, 1000, 0.08, 20, 0.25, 1]],
	"chute": [["n", 0, 0.55, 0.1, 6, 0.4, 0.9]],
	"fire_whoosh": [["n", 0, 0.8, 0.2, 4, 0.3, 0.8]],
	"pickup": [["t", 0, 880, 880, 0.06, 20, 0.35, 0], ["t", 0.06, 1320, 1320, 0.12, 14, 0.35, 0]],
	"wrench": [["n", 0, 0.03, 0.0, 90, 0.9, 0.5], ["n", 0.09, 0.03, 0.0, 90, 0.9, 0.5], ["n", 0.18, 0.03, 0.0, 90, 0.9, 0.5], ["t", 0.27, 500, 900, 0.1, 15, 0.3, 1]],
	"spray": [["n", 0, 0.5, 0.05, 5, 0.95, 0.3]],
	"throw": [["n", 0, 0.18, 0.07, 14, 0.45, 0.4]],
	"ui_open": [["t", 0, 600, 900, 0.06, 25, 0.25, 0]],
	"ui_select": [["t", 0, 900, 900, 0.05, 30, 0.25, 0]],
	"ui_back": [["t", 0, 500, 350, 0.06, 25, 0.25, 0]],
	"ui_tick": [["t", 0, 1200, 1200, 0.02, 80, 0.2, 0]],
	"ui_deny": [["t", 0, 200, 180, 0.13, 10, 0.3, 1]],
	"ui_buy": [["t", 0, 1000, 1000, 0.06, 25, 0.25, 0], ["t", 0.06, 1500, 1500, 0.1, 18, 0.25, 0]],
}
const RANGES := {"shot": [20.0, 280.0], "explosion": [34.0, 520.0], "thunder": [60.0, 900.0], "crash": [10.0, 120.0], "horn": [10.0, 140.0], "scream": [7.0, 70.0]}
const STATIONS := ["Radio off", "Ember FM", "Low Tide", "Radio Ferro", "Sunny 98", "Nocturne"]

var streams := {}
var pool3d: Array = []
var pool2d: Array = []
var i3 := 0
var i2 := 0
var engines := {}
var sirens := {}
var amb := {}
var station := 1
var radio: AudioStreamPlayer
var radio_streams := {}
var radio_pending := {}
var skid_player: AudioStreamPlayer
var _amb_t := 0.0
var _warm: Array = []
var _lp: AudioEffectLowPassFilter
var _radio_on := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in ["SFX", "Music", "Ambient"]:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -9.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), -10.0)
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = 600.0
	AudioServer.add_bus_effect(0, _lp)
	AudioServer.set_bus_effect_enabled(0, 0, false)
	var lim := AudioEffectLimiter.new()
	AudioServer.add_bus_effect(0, lim)
	for i in 22:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		pool3d.append(p)
	for i in 6:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "SFX"
		add_child(p2)
		pool2d.append(p2)
	radio = AudioStreamPlayer.new()
	radio.bus = "Music"
	add_child(radio)
	skid_player = AudioStreamPlayer.new()
	skid_player.bus = "SFX"
	add_child(skid_player)
	_warm = ["step", "shot_pistol", "hit_concrete", "crash", "explosion", "horn", "shot_rifle", "shot_smg", "ui_open", "ui_select", "punch", "grunt"]
	apply_volume()


func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(G.settings.master_volume), 0.0001, 1.0)))


# ------------------------------------------------------------------ synthesis
func _render(layers: Array) -> PackedFloat32Array:
	var total := 0.0
	for l in layers:
		total = maxf(total, float(l[1]) + float(l[2] if l[0] == "n" else l[4]))
	var n := int(total * RATE) + 64
	var buf := PackedFloat32Array()
	buf.resize(n)
	var seed_v := 12345
	for l in layers:
		var off := int(float(l[1]) * RATE)
		if l[0] == "n":
			var dur := float(l[2])
			var att := float(l[3])
			var dec := float(l[4])
			var lp := float(l[5])
			var gain := float(l[6])
			var cnt := int(dur * RATE)
			var y := 0.0
			var a := clampf(lp * lp, 0.002, 1.0)
			for i in cnt:
				seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
				var w := float(seed_v) / 1073741824.0 - 1.0
				y += (w - y) * a
				var t := float(i) / RATE
				var env := exp(-dec * t) * (minf(t / att, 1.0) if att > 0.0 else 1.0) * minf((dur - t) * 60.0, 1.0)
				buf[off + i] += y * env * gain * (1.0 + (1.0 - lp) * 1.5)
		else:
			var f0 := float(l[2])
			var f1 := float(l[3])
			var dur2 := float(l[4])
			var dec2 := float(l[5])
			var gain2 := float(l[6])
			var wave := int(l[7])
			var cnt2 := int(dur2 * RATE)
			var ph := 0.0
			for i in cnt2:
				var t2 := float(i) / RATE
				var f := lerpf(f0, f1, t2 / dur2)
				ph += f / RATE
				var s := sin(ph * TAU)
				if wave == 1:
					s = 0.6 if s > 0.0 else -0.6
				elif wave == 2:
					s = (fposmod(ph, 1.0) * 2.0 - 1.0) * 0.7
				var env2 := exp(-dec2 * t2) * minf(t2 * 400.0, 1.0) * minf((dur2 - t2) * 80.0, 1.0)
				buf[off + i] += s * env2 * gain2
	return buf


func _to_wav(buf: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


func stream(nm: String) -> AudioStreamWAV:
	if streams.has(nm):
		return streams[nm]
	var s: AudioStreamWAV = null
	if DEFS.has(nm):
		s = _to_wav(_render(DEFS[nm]))
	elif nm.begins_with("loop_"):
		s = _to_wav(_loop(nm), true)
	streams[nm] = s
	return s


func _loop(nm: String) -> PackedFloat32Array:
	var dur := 1.0
	match nm:
		"loop_siren": dur = 1.6
		"loop_ocean": dur = 6.0
		"loop_city": dur = 4.0
		"loop_rain": dur = 2.0
		"loop_wind": dur = 5.0
		"loop_industry": dur = 3.0
		"loop_skid": dur = 0.6
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var seed_v := 777
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var t := float(i) / RATE
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var w := float(seed_v) / 1073741824.0 - 1.0
		var s := 0.0
		match nm:
			"loop_engine":
				var ph := t * 60.0 * TAU
				for h in range(1, 7):
					s += sin(ph * h + h * 0.7) / h
				s *= 0.32 * (1.0 + 0.35 * sin(t * 30.0 * TAU))
				y += (w - y) * 0.08
				s += y * 0.25
			"loop_bike":
				var ph2 := t * 90.0 * TAU
				s = (sin(ph2) + sin(ph2 * 3.0) * 0.5 + sin(ph2 * 5.0) * 0.3 + sin(ph2 * 2.0) * 0.3) * 0.3 * (1.0 + 0.4 * sin(t * 45.0 * TAU))
			"loop_heli":
				y += (w - y) * 0.12
				var chop := pow(maxf(sin(t * 13.0 * TAU), 0.0), 3.0)
				s = y * (0.5 + 1.6 * chop) + sin(t * 78.0 * TAU) * 0.18 + sin(t * 26.0 * TAU) * 0.25 * chop
			"loop_plane":
				var ph3 := t * 110.0 * TAU
				s = (fposmod(t * 110.0, 1.0) - 0.5) * 0.5 * (1.0 + 0.5 * sin(t * 44.0 * TAU)) + sin(ph3 * 0.5) * 0.2
			"loop_jet":
				y += (w - y) * 0.35
				y2 += (y - y2) * 0.05
				s = (y - y2) * 0.9 + sin(t * 700.0 * TAU) * 0.05 + y2 * 1.2
			"loop_boat":
				y += (w - y) * 0.03
				s = sin(t * 50.0 * TAU) * 0.3 * (1.0 + 0.5 * sin(t * 25.0 * TAU)) + y * 2.2
			"loop_siren":
				var f := 900.0 + 350.0 * sin(t / dur * TAU)
				y += f / RATE
				s = (0.35 if sin(y * TAU) > 0.0 else -0.35) + sin(y * TAU) * 0.2
			"loop_ocean":
				y += (w - y) * 0.06
				s = y * 3.0 * (0.45 + 0.55 * pow(0.5 + 0.5 * sin(t / dur * TAU), 2.0))
			"loop_city":
				y += (w - y) * 0.012
				y2 += (w - y2) * 0.2
				s = y * 9.0 + y2 * 0.05 * (0.5 + 0.5 * sin(t / dur * TAU * 2.0))
			"loop_rain":
				y += (w - y) * 0.55
				y2 += (y - y2) * 0.2
				s = (y - y2) * 1.1
			"loop_wind":
				y += (w - y) * (0.02 + 0.012 * sin(t / dur * TAU))
				s = y * 7.0 * (0.6 + 0.4 * sin(t / dur * TAU * 2.0 + 1.0))
			"loop_industry":
				y += (w - y) * 0.02
				s = sin(t * 50.0 * TAU) * 0.2 + sin(t * 100.0 * TAU) * 0.12 + y * 3.0
			"loop_skid":
				y += (w - y) * 0.5
				y2 += (y - y2) * 0.12
				s = (y - y2) * 1.4 * (0.8 + 0.2 * sin(t * 40.0 * TAU))
		buf[i] = s
	# crossfade the ends so noise based loops are seamless
	var xf := int(n * 0.08)
	for i in xf:
		var k := float(i) / xf
		buf[i] = buf[i] * k + buf[n - xf + i] * (1.0 - k)
	buf.resize(n - xf)
	return buf


# ------------------------------------------------------------------ one-shots
func play(nm: String, pos = null, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := stream(nm)
	if s == null:
		return
	if pos == null:
		var p2: AudioStreamPlayer = pool2d[i2]
		i2 = (i2 + 1) % pool2d.size()
		p2.stream = s
		p2.volume_db = vol_db - 4.0
		p2.pitch_scale = pitch
		p2.play()
		return
	var cam := get_viewport().get_camera_3d()
	var rng: Array = [7.0, 70.0]
	for k in RANGES.keys():
		if nm.begins_with(k):
			rng = RANGES[k]
	if cam != null and cam.global_position.distance_to(pos) > float(rng[1]):
		return
	var p: AudioStreamPlayer3D = pool3d[i3]
	i3 = (i3 + 1) % pool3d.size()
	p.stream = s
	p.global_position = pos
	p.unit_size = float(rng[0])
	p.max_distance = float(rng[1])
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func ui(nm: String) -> void:
	play("ui_" + nm, null, -6.0)


# ------------------------------------------------------------------ vehicle loops
func engine_update(veh: Vehicle, rpm: float, load_v: float) -> void:
	var p: AudioStreamPlayer3D = engines.get(veh)
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(veh.global_position) < 70.0
	var running := veh.engine_on and not veh.dead and (veh.driver != null or veh.ai != null) and rpm > 0.01
	if not near or not running:
		if p != null:
			p.stop()
			p.queue_free()
			engines.erase(veh)
		return
	if p == null:
		if engines.size() >= 9 and not veh.has_player():
			return
		p = AudioStreamPlayer3D.new()
		p.bus = "SFX"
		var ln := "loop_engine"
		match veh.kind:
			"bike": ln = "loop_bike" if not veh.def.get("pedal", false) else ""
			"heli": ln = "loop_heli"
			"plane": ln = "loop_jet" if veh.def.get("jet", false) else "loop_plane"
			"boat": ln = "loop_boat"
		if ln == "":
			return
		p.stream = stream(ln)
		p.unit_size = 9.0 if veh.kind in ["car", "bike", "boat"] else 30.0
		p.max_distance = 90.0 if veh.kind in ["car", "bike", "boat"] else 400.0
		veh.add_child(p)
		p.play()
		engines[veh] = p
	var base := 0.75 if veh.mass < 2500.0 else 0.55
	if veh.kind == "heli":
		p.pitch_scale = 0.55 + rpm * 0.5
		p.volume_db = -22.0 + rpm * 22.0
	elif veh.kind == "plane":
		p.pitch_scale = 0.6 + rpm * 0.8
		p.volume_db = -14.0 + rpm * 12.0
	else:
		p.pitch_scale = base + rpm * 1.3 * float(veh.mod_opt("exhaust").get("sound", 1.0))
		p.volume_db = -13.0 + load_v * 7.0 + (3.0 if veh.has_player() else 0.0)
	if veh.has_player() and veh is Car:
		var sk: float = (veh as Car).skid
		if sk > 0.35 and veh.speed > 5.0:
			if not skid_player.playing:
				skid_player.stream = stream("loop_skid")
				skid_player.play()
			skid_player.volume_db = -16.0 + sk * 8.0
			if G.fx:
				for w in (veh as Car).wheels:
					if float(w.skid) > 0.35 and bool(w.grounded):
						G.fx.tire_smoke(w.contact, float(w.skid))
		elif skid_player.playing:
			skid_player.stop()


func stop_engine(veh: Vehicle) -> void:
	if engines.has(veh):
		var p: AudioStreamPlayer3D = engines[veh]
		if is_instance_valid(p):
			p.queue_free()
		engines.erase(veh)
	siren(veh, false)


func siren(veh: Vehicle, on: bool) -> void:
	if on:
		if sirens.has(veh) or sirens.size() >= 3:
			return
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.stream = stream("loop_siren")
		p.unit_size = 16.0
		p.max_distance = 230.0
		p.volume_db = -9.0
		p.pitch_scale = randf_range(0.94, 1.06)
		veh.add_child(p)
		p.play()
		sirens[veh] = p
	elif sirens.has(veh):
		var p2: AudioStreamPlayer3D = sirens[veh]
		if is_instance_valid(p2):
			p2.queue_free()
		sirens.erase(veh)


# ------------------------------------------------------------------ ambience + radio
func _amb_player(nm: String) -> AudioStreamPlayer:
	if not amb.has(nm):
		var p := AudioStreamPlayer.new()
		p.bus = "Ambient"
		p.stream = stream("loop_" + nm)
		p.volume_db = -60.0
		add_child(p)
		p.play()
		amb[nm] = p
	return amb[nm]


func _set_amb(nm: String, level: float, delta: float) -> void:
	if level <= 0.01 and not amb.has(nm):
		return
	var p := _amb_player(nm)
	var target := linear_to_db(clampf(level, 0.0001, 1.0))
	p.volume_db = lerpf(p.volume_db, target, clampf(delta * 2.0, 0.0, 1.0))


func _process(delta: float) -> void:
	if not _warm.is_empty():
		stream(_warm.pop_back())
	for k in engines.keys():
		if not is_instance_valid(k):
			engines.erase(k)
	for k in sirens.keys():
		if not is_instance_valid(k):
			sirens.erase(k)
	var pl: Node = G.player
	if pl == null:
		return
	_amb_t -= delta
	if _amb_t <= 0.0:
		_amb_t = 0.2
		var pp: Vector3 = pl.global_position_now()
		var under: bool = G.timew != null and G.timew.underwater
		AudioServer.set_bus_effect_enabled(0, 0, under)
		var coast := clampf(1.0 - absf(pp.z - 205.0) / 110.0, 0.0, 1.0)
		var dn := WorldLayout.district_at(pp)
		var urban := 0.0 if dn in ["Ember Hill", "Coral Beach", "City Limits"] else 1.0
		var night: float = G.timew.night if G.timew else 0.0
		var rain: float = clampf(G.timew.cur.rain, 0.0, 1.0) if G.timew else 0.0
		var storm: float = G.timew.cur.storm if G.timew else 0.0
		var high := clampf((pp.y - 12.0) / 60.0, 0.0, 1.0)
		_set_amb("city", urban * lerpf(0.5, 0.25, night) * (1.0 - high * 0.6), 0.2)
		_set_amb("ocean", coast * 0.55, 0.2)
		_set_amb("rain", rain * 0.6, 0.2)
		_set_amb("wind", clampf(high * 0.6 + storm * 0.45 + (0.25 if dn == "Ember Hill" else 0.0), 0.0, 0.8), 0.2)
		_set_amb("industry", 0.3 if dn in ["Ironworks", "Harbor Docks"] else 0.0, 0.2)
		_update_radio(pl)


func radio_label() -> String:
	if station == 0:
		return "Radio off  [N]"
	return "%s  [N]%s" % [STATIONS[station], "" if radio_streams.has(station) else "  (tuning...)"]


func _update_radio(pl: Node) -> void:
	var veh: Vehicle = pl.vehicle
	var want: bool = veh != null and veh.engine_on and station > 0 and not veh.def.get("pedal", false)
	if Input.is_action_just_pressed("radio") and veh != null and G.ui_blocking == 0:
		pass
	if want:
		if radio_streams.has(station):
			if radio.stream != radio_streams[station] or not radio.playing:
				radio.stream = radio_streams[station]
				radio.play()
		elif not radio_pending.has(station):
			radio_pending[station] = true
			var st := station
			WorkerThreadPool.add_task(func(): _make_station(st))
			radio.stop()
	elif radio.playing:
		radio.stop()


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("radio") and G.player != null and G.player.vehicle != null and G.ui_blocking == 0:
		station = (station + 1) % STATIONS.size()
		ui("tick")
		radio.stop()
		G.say("Radio: " + STATIONS[station], Color(1.0, 0.85, 0.4))


func _make_station(st: int) -> void:
	## Original generative music: bass, chords, lead and drums from seeded patterns (runs in a worker thread).
	var bpm: float = [0.0, 118.0, 84.0, 132.0, 106.0, 68.0][st]
	var root: float = [0.0, 110.0, 98.0, 82.4, 130.8, 87.3][st]
	var scale: Array = [[], [0, 3, 5, 7, 10], [0, 2, 4, 7, 9], [0, 1, 5, 7, 8], [0, 2, 4, 5, 7, 9, 10], [0, 3, 7, 10, 14]][st]
	var bars := 8
	var beat := 60.0 / bpm
	var total := beat * 4.0 * bars
	var n := int(total * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var seed_v := 1000 + st * 7919
	var prog: Array = [[0, 5, 3, 4], [0, 3, 4, 3], [0, 0, 1, 4], [0, 4, 5, 3], [0, 2, 0, 3]][st - 1]
	var steps := bars * 16
	var step_len := beat / 4.0
	var step_n := int(step_len * RATE)
	var lead_note := 0
	for sidx in steps:
		var bar := sidx / 16
		var pos := sidx % 16
		var ch: int = prog[bar % prog.size()]
		var base_f := root * pow(2.0, float(scale[ch % scale.size()]) / 12.0)
		var off := sidx * step_n
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var r := float(seed_v % 1000) / 1000.0
		# drums
		var kick := pos % 8 == 0 or (st == 3 and pos % 4 == 0) or (st == 4 and pos == 10)
		var snare := pos % 8 == 4 and st != 5
		var hat := pos % 2 == 0 and st != 5 and st != 2 or (st == 2 and pos % 4 == 2)
		# bass
		var bass_on := (pos % 4 == 0) or (st in [1, 4] and pos % 4 == 3 and r > 0.4) or (st == 3 and pos % 2 == 0)
		var bass_f := base_f * (0.5 if st != 3 else 0.5)
		# lead
		var lead_on := st != 3 and ((pos % 4 == 2 and r > 0.35) or (pos % 8 == 6) or (st == 5 and pos == 0))
		if lead_on:
			lead_note = (lead_note + 1 + int(r * 3.0)) % scale.size()
		var lead_f := base_f * 2.0 * pow(2.0, float(scale[lead_note]) / 12.0) / pow(2.0, float(scale[ch % scale.size()]) / 12.0)
		var seed2 := seed_v
		for i in step_n * 2:
			var idx := off + i
			if idx >= n:
				break
			var t := float(i) / RATE
			var s := 0.0
			if kick and i < step_n * 2:
				s += sin((55.0 + 90.0 * exp(-t * 28.0)) * t * TAU) * exp(-t * 9.0) * 0.8
			if snare:
				seed2 = (seed2 * 1103515245 + 12345) & 0x7fffffff
				s += (float(seed2) / 1073741824.0 - 1.0) * exp(-t * 22.0) * 0.35 + sin(190.0 * t * TAU) * exp(-t * 30.0) * 0.2
			if hat and i < step_n:
				seed2 = (seed2 * 1103515245 + 12345) & 0x7fffffff
				s += (float(seed2) / 1073741824.0 - 1.0) * exp(-t * 70.0) * 0.1
			if bass_on:
				var bp := bass_f * t
				s += ((fposmod(bp, 1.0) - 0.5) * 0.5 + sin(bp * TAU) * 0.5) * exp(-t * (4.0 if st != 5 else 1.0)) * 0.4
			if lead_on:
				var lp := lead_f * t
				var lw := sin(lp * TAU) + (0.3 * sin(lp * 2.0 * TAU) if st != 2 else 0.0)
				if st == 1:
					lw = (0.5 if sin(lp * TAU) > 0.0 else -0.5) + sin(lp * 0.5 * TAU) * 0.3
				s += lw * exp(-t * (5.0 if st != 5 else 1.2)) * 0.2 * minf(t * 200.0, 1.0)
			buf[idx] += s
		# pad chord once per bar
		if pos == 0 and st in [1, 2, 4, 5]:
			var bar_n := step_n * 16
			for i in bar_n:
				var idx2 := off + i
				if idx2 >= n:
					break
				var t2 := float(i) / RATE
				var env := minf(t2 * 3.0, 1.0) * minf((bar_n - i) / float(RATE) * 4.0, 1.0)
				var c := 0.0
				for iv in [0, 2, 4]:
					var ff := root * pow(2.0, float(scale[(ch + iv) % scale.size()] + (12 if (ch + iv) >= scale.size() else 0)) / 12.0)
					c += sin(ff * t2 * TAU) + 0.4 * sin(ff * 2.01 * t2 * TAU)
				buf[idx2] += c * 0.05 * env
	var peak := 0.001
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	for i in n:
		buf[i] = buf[i] / peak * 0.85
	var w := _to_wav(buf, true)
	call_deferred("_station_ready", st, w)


func _station_ready(st: int, w: AudioStreamWAV) -> void:
	radio_streams[st] = w
