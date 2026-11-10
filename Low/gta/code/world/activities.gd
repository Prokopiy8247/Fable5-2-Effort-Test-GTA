class_name Activities
extends Node
# Optional free-roam activities (never missions): shooting range, stunt jumps, street time trial.

var best_trial := 0.0
var best_stunt := 0.0
var best_range := 0
# shooting range
var range_on := false
var range_t := 0.0
var range_score := 0
var range_hits := 0
var range_shots0 := 0
var targets: Array = []
# time trial
var trial_on := false
var trial_t := 0.0
var trial_i := 0
var trial_pts: Array = []
var beacon: MeshInstance3D


func _ready() -> void:
	for p in [[-200, 120], [-200, -40], [-200, -200], [-40, -200], [120, -200], [120, -40], [120, 120], [-40, 120]]:
		trial_pts.append(Vector3(p[0], 0.5, p[1]))
	beacon = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 5.0
	cm.bottom_radius = 5.0
	cm.height = 40.0
	beacon.mesh = cm
	var m := G.flat_mat(Color(1.0, 0.85, 0.2, 0.25), 0.5, 0.0, 1.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	beacon.material_override = m
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.visible = false
	add_child(beacon)


func start_range() -> void:
	if range_on:
		return
	var p = G.player
	if p.wdef().get("melee", false):
		for w in ["rifle", "carbine", "smg", "pistol", "revolver", "shotgun"]:
			if w in p.owned:
				p.equip(w)
				break
	if p.wdef().get("melee", false):
		G.notify("You need a firearm for the range")
		return
	range_on = true
	range_t = 45.0
	range_score = 0
	range_hits = 0
	range_shots0 = shots
	G.notify("Shooting range: hit as many targets as you can in 45 seconds", 5.0)
	for k in 4:
		_new_target()


var shots := 0


func _new_target() -> void:
	var pos := Vector3(randf_range(51, 75), WorldBuilder.SLAB_Y, randf_range(-181, -152))
	var t: Prop = G.world.add_prop("prop_target", pos, PI)
	t.on_hit = _target_hit
	t.min_speed = 99.0
	targets.append(t)


func _target_hit(t: Prop, pos: Vector3) -> void:
	if not range_on or not t in targets:
		return
	targets.erase(t)
	var dist: float = G.player.global_position.distance_to(pos)
	range_score += 10 + int(dist * 0.5)
	range_hits += 1
	G.audio.ui("pickup")
	G.skill_gain("shooting", 0.6)
	t.on_hit = Callable()
	t.wake(Vector3(0, 60, -80))
	_new_target()


func stunt_landed(v, air: float, dist: float) -> void:
	if dist < 14.0 or v.wrecked:
		return
	best_stunt = max(best_stunt, dist)
	var reward := int(dist * 6.0)
	G.add_money(reward)
	G.skill_gain("driving", 2.0)
	G.hud.big_text("STUNT JUMP", Color(1.0, 0.85, 0.2))
	G.notify("Stunt jump: %d m, %.1f s airtime, landed safely. +$%d" % [int(dist), air, reward], 5.0)


func start_trial() -> void:
	var p = G.player
	if p.vehicle == null:
		G.notify("Get in a vehicle to start the street time trial")
		return
	trial_on = true
	trial_t = 0.0
	trial_i = 0
	# start with the nearest checkpoint
	var bd := 1e9
	for i in trial_pts.size():
		var d: float = trial_pts[i].distance_to(p.global_position)
		if d < bd:
			bd = d
			trial_i = i
	set_meta("left", trial_pts.size() + 1)
	G.notify("Time trial: lap the ring road through all checkpoints", 5.0)


func _process(dt: float) -> void:
	var p = G.player
	if p == null:
		return
	if range_on:
		range_t -= dt
		var fired: int = shots - range_shots0
		G.hud.activity_text = "RANGE  %ds   score %d   hits %d" % [int(range_t), range_score, range_hits]
		if range_t <= 0.0 or p.dead or p.global_position.distance_to(G.locations["Shooting Range"]) > 60.0:
			range_on = false
			for t in targets:
				if is_instance_valid(t):
					t.on_hit = Callable()
					t.wake()
			targets.clear()
			best_range = max(best_range, range_score)
			var reward := range_score
			G.add_money(reward)
			G.hud.activity_text = ""
			G.notify("Range finished: score %d, %d hits. Reward $%d. Best %d" % [range_score, range_hits, reward, best_range], 6.0)
	elif trial_on:
		trial_t += dt
		var cp: Vector3 = trial_pts[trial_i]
		beacon.visible = true
		beacon.global_position = cp + Vector3.UP * 20.0
		G.hud.checkpoint = cp
		var left: int = get_meta("left", 0)
		G.hud.activity_text = "TIME TRIAL  %.1fs   checkpoints left %d" % [trial_t, left]
		if p.vehicle == null or p.dead:
			_end_trial(false)
		elif Vector2(cp.x - p.global_position.x, cp.z - p.global_position.z).length() < 14.0:
			left -= 1
			set_meta("left", left)
			G.audio.ui("pickup")
			trial_i = (trial_i + 1) % trial_pts.size()
			if left <= 0:
				_end_trial(true)
	else:
		if G.hud.activity_text != "":
			G.hud.activity_text = ""


func _end_trial(done: bool) -> void:
	trial_on = false
	beacon.visible = false
	G.hud.checkpoint = null
	G.hud.activity_text = ""
	if done:
		var rec := best_trial == 0.0 or trial_t < best_trial
		if rec:
			best_trial = trial_t
		var reward := int(clamp(3000.0 - trial_t * 15.0, 200.0, 3000.0))
		G.add_money(reward)
		G.skill_gain("driving", 4.0)
		G.notify("Time trial finished in %.1f s%s. +$%d" % [trial_t, " (new record)" if rec else "", reward], 6.0)
	else:
		G.notify("Time trial cancelled")
