extends Node3D
## Optional free-roam activities (never missions): the Ironworks shooting range challenge,
## stunt jumps tracked from real vehicle airtime, and a quick time-trial lap of the ring road.

var range_on := false
var range_t := 0.0
var range_score := 0
var range_hits := 0
var range_shots0 := 0
var target: Node3D = null
var target_t := 0.0
var best_range := 0
var stunts_done := {}
var trial_on := false
var trial_t := 0.0
var trial_cp := 0
var trial_best := 0.0
var trial_marker: MeshInstance3D
const TRIAL := [Vector2i(3, 2), Vector2i(3, 4), Vector2i(6, 4), Vector2i(6, 0), Vector2i(3, 0), Vector2i(3, 2)]


class RangeTarget:
	extends StaticBody3D
	var owner_act: Node
	var dead := false

	func take_damage(_a: float, instigator: Node = null, pos: Vector3 = Vector3.ZERO, _k: String = "") -> void:
		if dead or not G.is_player(instigator):
			return
		dead = true
		owner_act.target_hit(self, pos)


func _ready() -> void:
	if G.world:
		G.world.interact("trial", Vector3(-6.0, 0.16, 12.0), 2.4, "Start ring-road time trial (bring a vehicle)", {})
		G.world.interact("trial", Vector3(2.0, 0.0, 14.0), 4.0, "Start ring-road time trial", {"vehicle": true})
		G.world.poi("trial", "Time Trial Start", Vector3(-6.0, 0.16, 12.0), "target")
	var it: Node = G.main.get_node_or_null("Interactions")
	set_process_unhandled_input(true)
	if it == null:
		pass


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("interact") and G.ui_blocking == 0 and G.main.has_node("Interactions"):
		var cur: Dictionary = G.main.get_node("Interactions").current
		if not cur.is_empty() and cur.kind == "trial":
			start_trial()


# ------------------------------------------------------------------ shooting range
func start_range() -> void:
	var p: Player = G.player
	if range_on:
		return
	if p.melee_equipped():
		var gun := ""
		for wid in ["pistol", "smg", "rifle", "carbine", "revolver"]:
			if p.inv.owned.has(wid):
				gun = wid
				break
		if gun == "":
			G.say("Bring a firearm to use the range", Color(1, 0.6, 0.4))
			return
		p.equip(gun)
	range_on = true
	range_t = 45.0
	range_score = 0
	range_hits = 0
	range_shots0 = int(p.stats.shots)
	target_t = 0.5
	G.say("Shooting range: hit as many targets as you can in 45 seconds", UIKit.TEAL)
	Sfx.play("wanted_up")


func _spawn_target() -> void:
	if target != null and is_instance_valid(target):
		target.queue_free()
	var poi: Dictionary = G.world.pois["range"]
	var spots: Array = poi.targets
	var t := RangeTarget.new()
	t.owner_act = self
	t.collision_layer = G.L_WORLD
	t.collision_mask = 0
	var mi := MeshInstance3D.new()
	mi.mesh = Assets.mesh("props/kit_props", "prop_target")
	mi.rotation.y = PI * 0.5
	t.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.12, 0.74, 0.74)
	cs.shape = bs
	t.add_child(cs)
	add_child(t)
	t.global_position = spots[randi() % spots.size()]
	t.scale = Vector3(0.1, 0.1, 0.1)
	create_tween().tween_property(t, "scale", Vector3.ONE, 0.12)
	target = t
	target_t = 2.4


func target_hit(t: Node3D, pos: Vector3) -> void:
	var centre := t.global_position
	var d := pos.distance_to(centre)
	var pts := 100 if d > 0.2 else (200 if d > 0.09 else 300)
	range_score += pts
	range_hits += 1
	G.player.skill_gain("shooting", 0.006)
	Sfx.play("hit_metal", pos, 0.0, 1.4)
	if G.fx:
		G.fx.sparks(pos, 8)
	t.queue_free()
	target = null
	target_t = 0.35


func _end_range() -> void:
	range_on = false
	if target != null and is_instance_valid(target):
		target.queue_free()
	var p: Player = G.player
	var shots: int = maxi(int(p.stats.shots) - range_shots0, 1)
	var acc := clampf(float(range_hits) / shots, 0.0, 1.0)
	var reward := mini(int(range_score * 0.12 * (0.5 + acc)), 600)
	p.add_money(reward)
	best_range = maxi(best_range, range_score)
	G.say("Range complete: %d pts, %d hits, %d%% accuracy  -  reward %s  (best %d)" % [range_score, range_hits, int(acc * 100.0), G.fmt_money(reward), best_range], UIKit.GOLD)
	Sfx.play("pickup")
	if G.hud:
		G.hud.alt_text = ""


# ------------------------------------------------------------------ stunt jumps
func on_jump_landed(veh: Vehicle, airtime: float, start: Vector3, peak: float) -> void:
	if airtime < 1.1 or veh.dead:
		return
	var land := veh.global_position
	var dist := G.dist2(start, land)
	var height := peak - minf(start.y, land.y)
	var upright := veh.global_transform.basis.y.y > (0.5 if not veh.flooded else -0.3)
	var p: Player = G.player
	p.skill_gain("driving", 0.006)
	var named := ""
	if G.world:
		for s in G.world.stunts:
			if G.dist2(s.pos, start) < 30.0 and dist > 14.0:
				named = s.name
	if named != "" and upright:
		var first := not stunts_done.has(named)
		stunts_done[named] = maxf(float(stunts_done.get(named, 0.0)), dist)
		p.stats.stunts += 1
		var reward := 300 if first else 50
		p.add_money(reward)
		G.say("STUNT JUMP  \"%s\"  -  %.0f m, %.1f s air, %.0f m high  +%s" % [named, dist, airtime, height, G.fmt_money(reward)], UIKit.GOLD)
		Sfx.play("pickup")
	elif airtime > 1.5 and dist > 12.0:
		G.say("%s  -  %.0f m, %.1f s air%s" % ["Big air" if upright else "Crash landing", dist, airtime, "" if upright else "  (not clean)"], UIKit.TEAL if upright else Color(1, 0.6, 0.4))


# ------------------------------------------------------------------ time trial
func start_trial() -> void:
	if trial_on:
		return
	var p: Player = G.player
	if p.vehicle == null or p.vehicle.kind not in ["car", "bike"]:
		G.say("Get in a car or on a bike to start the time trial", UIKit.DIM)
		return
	trial_on = true
	trial_t = 0.0
	trial_cp = 1
	if trial_marker == null:
		trial_marker = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 5.0
		cm.bottom_radius = 5.0
		cm.height = 12.0
		cm.cap_top = false
		cm.cap_bottom = false
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.25, 0.9, 0.8, 0.28)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		cm.material = m
		trial_marker.mesh = cm
		trial_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(trial_marker)
	trial_marker.visible = true
	_trial_next()
	G.say("Time trial started: follow the teal gates around the ring road", UIKit.TEAL)
	Sfx.play("wanted_up")


func _trial_next() -> void:
	var c := WorldLayout.inter_pos(TRIAL[trial_cp])
	trial_marker.global_position = c + Vector3(0, 6.0, 0)
	if G.hud:
		G.hud.set_waypoint(c)


func _end_trial(done: bool) -> void:
	trial_on = false
	trial_marker.visible = false
	if G.hud:
		G.hud.set_waypoint(null)
		G.hud.alt_text = ""
	if done:
		var first := trial_best <= 0.0
		var better := first or trial_t < trial_best
		if better:
			trial_best = trial_t
		var reward := 400 if trial_t < 75.0 else (200 if trial_t < 100.0 else 80)
		G.player.add_money(reward)
		G.player.skill_gain("driving", 0.03)
		G.say("Time trial: %.1f s%s  +%s" % [trial_t, "  NEW BEST" if better else "  (best %.1f)" % trial_best, G.fmt_money(reward)], UIKit.GOLD)
		Sfx.play("pickup")
	else:
		G.say("Time trial abandoned", UIKit.DIM)


func _process(delta: float) -> void:
	if range_on:
		range_t -= delta
		target_t -= delta
		if target_t <= 0.0:
			_spawn_target()
		if G.hud:
			var shots: int = maxi(int(G.player.stats.shots) - range_shots0, 1)
			G.hud.alt_text = "RANGE  %ds   score %d   accuracy %d%%" % [int(range_t), range_score, int(float(range_hits) / shots * 100.0)]
		var poi: Dictionary = G.world.pois["range"]
		if range_t <= 0.0 or G.player.global_position_now().distance_to(poi.pos) > 14.0 or G.player.dead:
			_end_range()
	if trial_on:
		trial_t += delta
		var p: Player = G.player
		if p.vehicle == null or p.dead:
			_end_trial(false)
			return
		var c := WorldLayout.inter_pos(TRIAL[trial_cp])
		if G.hud:
			G.hud.alt_text = "TIME TRIAL  %.1f s   gate %d / %d" % [trial_t, trial_cp, TRIAL.size() - 1]
		if G.dist2(p.global_position_now(), c) < 13.0:
			trial_cp += 1
			Sfx.play("pickup")
			if trial_cp >= TRIAL.size():
				_end_trial(true)
			else:
				_trial_next()
