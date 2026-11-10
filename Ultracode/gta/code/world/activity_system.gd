extends Node3D
## World system "activities" (ACTIVITIES module; spec 47 / 47A / 46A; docs/ACTIVITIES.md).
##
## Optional free-roam hobbies - never missions: no story, no dialogue, no unlock chains, no
## objective markers. An activity starts only when the player deliberately uses its activity point
## (an Interactable at the range counter / race flag) or - for stunt jumps - drives off a ramp
## fast enough. Each gives a simple score or time, a medal against fixed thresholds, a small cash
## reward and skill XP, and keeps personal bests (SaveSystem provider "activities").
##
## Definitions: Registry kind "activities" (res://gta/resources/registries/activities_registry.gd).
## Controllers (one instance each, ticked from this node's single _physics_process):
##   activities/activity_range.gd   Ironsight Range courses (pop-up / turning / moving targets)
##   activities/activity_race.gd    checkpoint races: street (Coral Loop), sea (Harbor Sprint),
##                                  off-road trail (Signal Hill Climb)
##   activities/activity_stunts.gd  stunt jumps at stunt_ramp_1..3
## Public API (soft-used by UI, admin, tests):
##   start_activity(id) -> bool (coroutine), abort_activity(reason), retry_last(), is_active(),
##   get_active_id(), get_hud_info() -> Dictionary, get_activity_list() -> Array,
##   get_record(id) -> Dictionary, get_stunt_progress() -> Vector2i, reset_records(),
##   get_save_data() / load_save_data(d), set_enabled(on), reset_for_respawn().
## Signals used: EventBus.activity_started(id), EventBus.activity_finished(id, result).
## Result screen: UI.open_screen("activity_result", args) (args contract in docs/ACTIVITIES.md);
## when that screen does not exist the result is shown with UI.banner + UI.notify.

const RangeCtl := preload("res://gta/code/world/activities/activity_range.gd")
const RaceCtl := preload("res://gta/code/world/activities/activity_race.gd")
const StuntCtl := preload("res://gta/code/world/activities/activity_stunts.gd")
const HudFallback := preload("res://gta/code/world/activities/activity_hud.gd")

const SAVE_KEY := "activities"
const SAVE_VERSION := 1
const USE_RADIUS := 1.9
const RACE_USE_RADIUS := 3.0
const USE_HEIGHT := 0.9
const USE_PRIORITY := 3
const RESULT_SCREEN := "activity_result"
const MEDAL_RANK := {"none": 0, "bronze": 1, "silver": 2, "gold": 3}
const MEDAL_COLORS := {
	"gold": Color(0.969, 0.788, 0.282), "silver": Color(0.8, 0.84, 0.9), "bronze": Color(0.86, 0.55, 0.33),
	"none": Color(0.655, 0.722, 0.8),
}
const WIDGET_GROUP := "hud_activity_widget"

var enabled: bool = true
var defs: Dictionary = {}                 ## id -> definition (Dictionary)
var order: Array[String] = []             ## registry order
var records: Dictionary = {}              ## id -> personal record (see _blank_record)
var range_ctl = null                      ## activity_range.gd instance (untyped: coroutine calls)
var race_ctl = null                       ## activity_race.gd instance
var stunts = null                         ## activity_stunts.gd instance
var active_id: String = ""
var active_kind: String = ""              ## "shooting_range" | "race" | ""
var starting: bool = false
var last_id: String = ""
var last_result: Dictionary = {}
var points: Array[Dictionary] = []        ## {id, interactable, flag, blip, xform}
var hud_fallback: CanvasLayer = null
var stats: Dictionary = {"started": 0, "finished": 0, "aborted": 0, "stunts": 0}
var last_refusal: String = ""             ## why the last start_activity() failed (UI toast text)
var setup_ms: float = 0.0
var show_results: bool = true             ## tests may switch the result screen off

var _hud: Dictionary = {}
var _set_up: bool = false


# =================================================================================================
# setup
# =================================================================================================

func setup() -> void:
	if _set_up:
		return
	_set_up = true
	var t0 := Time.get_ticks_usec()
	range_ctl = RangeCtl.new(self)
	race_ctl = RaceCtl.new(self)
	stunts = StuntCtl.new(self)
	_load_defs()
	var stunt_defs: Array = []
	for id: String in order:
		if str(defs[id].get("kind", "")) == "stunt_jump":
			stunt_defs.append(defs[id])
	stunts.call("setup", stunt_defs)
	_build_points()
	SaveSystem.register_provider(SAVE_KEY, self)
	if not EventBus.weapon_fired.is_connected(_on_weapon_fired):
		EventBus.weapon_fired.connect(_on_weapon_fired)
	if not EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.connect(_on_player_died)
	if not EventBus.player_busted.is_connected(_on_player_busted):
		EventBus.player_busted.connect(_on_player_busted)
	_refresh_prompts()
	setup_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	print("[Activities] %d activities (%d points, %d stunt ramps) set up in %.1f ms" % [order.size(), points.size(),
			(stunts.get("ramps") as Array).size(), setup_ms])


func _load_defs() -> void:
	defs.clear()
	order.clear()
	for d: Variant in Registry.all("activities"):
		if d is Dictionary and (d as Dictionary).has("id"):
			var id := str((d as Dictionary)["id"])
			defs[id] = d
			order.append(id)
	if order.is_empty():
		push_warning("Activities: Registry kind 'activities' is empty")


func _build_points() -> void:
	for p: Dictionary in points:
		for k: String in ["interactable", "flag", "blip"]:
			var n: Variant = p.get(k, null)
			if n is Node and is_instance_valid(n):
				(n as Node).queue_free()
	points.clear()
	var props: Node = Game.get_system("props")
	for id: String in order:
		var d: Dictionary = defs[id]
		match str(d.get("kind", "")):
			"shooting_range":
				if range_ctl.call("resolve_geometry", d) != "":
					push_warning("Activities: %s unavailable (%s)" % [id, range_ctl.call("resolve_geometry", d)])
					continue
				var xf: Transform3D = range_ctl.call("get_use_transform", d)
				_add_point(id, xf, USE_RADIUS, true, null, false)
			"race":
				var r: Dictionary = race_ctl.call("get_route", d)
				if not bool(r.get("ok", false)):
					push_warning("Activities: race %s has no route (%s)" % [id, str(r.get("why", ""))])
					continue
				var xf: Transform3D = r["point"]
				var flag: Node3D = null
				if props != null and props.has_method("spawn_prop"):
					var fxf := Transform3D(xf.basis, xf.origin + xf.basis.z * 0.9)
					var n: Variant = props.call("spawn_prop", "race_flag", fxf)
					if n is Node3D:
						flag = n as Node3D
						flag.name = "RaceFlag_" + id
				# the street race point is already drawn by the map (race_start); others get a blip
				_add_point(id, xf, RACE_USE_RADIUS, false, flag, str(d.get("point", "")) != "race_start")


func _add_point(id: String, xf: Transform3D, radius: float, foot_only: bool, flag: Node3D, blip: bool) -> void:
	var d: Dictionary = defs[id]
	var it := Interactable.create(str(d.get("prompt", d.get("display_name", id))), radius)
	it.name = "Use_" + id
	it.use_priority = USE_PRIORITY
	it.on_foot_only = foot_only
	it.set_meta(&"activity_id", id)
	add_child(it)
	it.global_position = xf.origin + Vector3.UP * USE_HEIGHT
	it.condition = func(_p: Node) -> bool: return can_start(id)
	it.interacted.connect(func(_p: Node3D) -> void: start_activity(id))
	var b: Node3D = null
	if blip:
		b = Node3D.new()
		b.name = "Blip_" + id
		b.set_meta(&"blip_icon", StringName(str(d.get("map_icon", "flag"))))
		b.set_meta(&"blip_color", Color(0.965, 0.937, 0.878))
		b.set_meta(&"blip_clamp", false)
		add_child(b)
		b.global_position = xf.origin
		b.add_to_group("minimap_blip")
	points.append({"id": id, "interactable": it, "flag": flag, "blip": b, "xform": xf})


# =================================================================================================
# loop
# =================================================================================================

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if range_ctl != null:
		range_ctl.call("tick", delta)
	if active_kind == "race" and race_ctl != null:
		race_ctl.call("tick", delta)
	if stunts != null:
		stunts.call("tick", delta)


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if not on:
		abort_activity("disabled")
		if stunts != null:
			stunts.call("abort")
	for p: Dictionary in points:
		var it: Variant = p.get("interactable", null)
		if it is Interactable and is_instance_valid(it):
			(it as Interactable).enabled = on
		var f: Variant = p.get("flag", null)
		if f is Node3D and is_instance_valid(f):
			(f as Node3D).visible = on
	if stunts != null:
		stunts.set("enabled", on)


func reset_for_respawn() -> void:
	abort_activity("down")
	if stunts != null:
		stunts.call("abort")


func _on_player_died(_cause: String) -> void:
	abort_activity("down")


func _on_player_busted() -> void:
	abort_activity("arrested")


func _on_weapon_fired(weapon_id: String, shooter: Node, _origin: Vector3, _direction: Vector3) -> void:
	if active_kind == "shooting_range" and range_ctl != null:
		range_ctl.call("on_weapon_fired", weapon_id, shooter)


# =================================================================================================
# start / stop
# =================================================================================================

## True when the activity could start right now (used as the Interactable condition, so the
## prompt is hidden while another activity runs).
func can_start(id: String) -> bool:
	if not enabled or starting or active_id != "" or not defs.has(id):
		return false
	var kind := str((defs[id] as Dictionary).get("kind", ""))
	if kind != "shooting_range" and kind != "race":
		return false
	if not Game.has_player() or Game.player.get("is_dead") == true:
		return false
	var v := Game.get_player_vehicle()
	if kind == "shooting_range" and v != null:
		return false
	if v != null and ["heli", "plane"].has(str(v.get("vehicle_class"))):
		return false
	return true


## Starts an activity (coroutine: fades / spawns). Returns true when it is running.
func start_activity(id: String) -> bool:
	if not can_start(id):
		return false
	var d: Dictionary = defs[id]
	var kind := str(d.get("kind", ""))
	starting = true
	active_id = id
	active_kind = kind
	var why: String = ""
	if kind == "shooting_range":
		why = await range_ctl.begin(d)
	else:
		why = await race_ctl.begin(d)
	starting = false
	last_refusal = why
	if why != "" or active_id != id:

		if active_id == id:
			active_id = ""
			active_kind = ""
		if why != "" and why != "cancelled":
			UI.notify(why, "warn")
			Audio.play("ui_error", -6.0, 1.0, "UI")
		return false
	last_id = id
	stats["started"] = int(stats["started"]) + 1
	EventBus.activity_started.emit(id)
	_ensure_fallback_hud()
	return true


## Restarts the last finished / aborted activity (result screen "retry").
func retry_last() -> bool:
	if last_id == "":
		return false
	return await start_activity(last_id)


func abort_activity(reason: String = "cancelled") -> void:
	if active_id == "":
		return
	var id := active_id
	var kind := active_kind
	active_id = ""
	active_kind = ""
	if kind == "shooting_range":
		range_ctl.call("abort", reason)
	elif kind == "race":
		race_ctl.call("abort", reason)
	if starting:
		return              # start_activity() sees the cleared id and reports nothing
	last_id = id
	stats["aborted"] = int(stats["aborted"]) + 1
	var d: Dictionary = defs.get(id, {})
	var result := {"id": id, "kind": kind, "aborted": true, "reason": reason, "passed": false, "medal": "",
			"medal_id": "none", "title": str(d.get("display_name", id)), "result_screen": false}
	last_result = result
	EventBus.activity_finished.emit(id, result)
	if reason != "disabled":
		UI.notify("%s cancelled: %s" % [str(d.get("display_name", id)), reason], "warn")


func is_active() -> bool:
	return active_id != ""


func get_active_id() -> String:
	return active_id


# =================================================================================================
# results
# =================================================================================================

func _blank_record() -> Dictionary:
	return {"plays": 0, "completions": 0, "best_score": -1, "best_time": -1.0, "best_medal": "none",
			"best_accuracy": 0.0, "done": false, "best_distance": 0.0, "best_airtime": 0.0, "attempts": 0}


func get_record(id: String) -> Dictionary:
	var r: Dictionary = records.get(id, {})
	var out := _blank_record()
	for k: String in r:
		out[k] = r[k]
	return out


func _better_medal(a: String, b: String) -> String:
	return a if int(MEDAL_RANK.get(a, 0)) >= int(MEDAL_RANK.get(b, 0)) else b


## Called by the range controller when a course is complete.
func _on_range_complete(d: Dictionary, res: Dictionary) -> void:
	var id := str(d.get("id", ""))
	var rec := get_record(id)
	var score := int(res.get("score", 0))
	var medal := str(res.get("medal", "none"))
	var prev_best := int(rec["best_score"])
	var new_record := score > prev_best
	rec["plays"] = int(rec["plays"]) + 1
	rec["completions"] = int(rec["completions"]) + 1
	if new_record:
		rec["best_score"] = score
	rec["best_accuracy"] = maxf(float(rec["best_accuracy"]), float(res.get("accuracy", 0.0)))
	rec["best_medal"] = _better_medal(medal, str(rec["best_medal"]))
	records[id] = rec
	var reward := int((d.get("rewards", {}) as Dictionary).get(medal, 0))
	if reward > 0:
		Game.add_money(reward)
	var xpd: Dictionary = d.get("xp", {})
	var xp := float(xpd.get("per_hit", 0.05)) * float(res.get("hits", 0)) + float(xpd.get(medal, 0.0))
	if xp > 0.0:
		Skills.add_xp("shooting", xp)
	var acc := float(res.get("accuracy", 0.0))
	var best_acc := float(rec["best_accuracy"])       # already includes this run
	var lines: Array = [
		{"label": "Score", "value": str(score), "best": new_record},
		{"label": "Best score", "value": str(maxi(prev_best, score))},
		{"label": "Targets hit", "value": "%d / %d" % [int(res.get("targets_hit", 0)), int(res.get("exposures", 0))]},
		{"label": "Accuracy", "value": "%d%%  (%d shots)" % [int(round(acc * 100.0)), int(res.get("shots", 0))],
			"best": acc > 0.0 and acc >= best_acc - 0.0001},

		{"label": "Accuracy bonus", "value": "+%d" % int(res.get("accuracy_bonus", 0))},
		{"label": "Time", "value": _fmt_time(float(res.get("time", 0.0)))},
	]
	var args := {
		"id": id, "kind": "shooting_range", "title": str(d.get("display_name", "Shooting Range")),
		"subtitle": str(d.get("subtitle", "")), "passed": medal != "none", "medal": medal if medal != "none" else "",
		"medal_id": medal, "fail_reason": "No medal this time", "lines": lines,
		"reward": reward, "xp": {"shooting": snappedf(xp, 0.01)}, "new_record": new_record, "can_retry": true,
		"retry": Callable(self, "retry_last"), "score": score, "max_score": int(res.get("max_score", 0)),
		"accuracy": acc, "hits": int(res.get("hits", 0)), "shots": int(res.get("shots", 0)),
		"time": float(res.get("time", 0.0)), "best_score": int(rec["best_score"]),
	}
	_finish(id, args)


## Called by the race controller at the finish line.
func _on_race_complete(d: Dictionary, res: Dictionary) -> void:
	var id := str(d.get("id", ""))
	var rec := get_record(id)
	var t := float(res.get("time", 0.0))
	var medal := str(res.get("medal", "none"))
	var prev := float(rec["best_time"])
	var new_record := prev < 0.0 or t < prev
	rec["plays"] = int(rec["plays"]) + 1
	rec["completions"] = int(rec["completions"]) + 1
	if new_record:
		rec["best_time"] = t
	rec["best_medal"] = _better_medal(medal, str(rec["best_medal"]))
	records[id] = rec
	var reward := int((d.get("rewards", {}) as Dictionary).get(medal, 0))
	if reward > 0:
		Game.add_money(reward)
	var xp := float((d.get("xp", {}) as Dictionary).get(medal, 0.05))
	if xp > 0.0:
		Skills.add_xp("driving", xp)
	var par: Dictionary = res.get("par", {})
	var lines: Array = [
		{"label": "Time", "value": _fmt_time(t), "best": new_record},
		{"label": "Best time", "value": _fmt_time(float(rec["best_time"]))},
		{"label": "Checkpoints", "value": "%d / %d" % [int(res.get("checkpoints", 0)), int(res.get("checkpoints", 0))]},
		{"label": "Top speed", "value": "%d km/h" % int(round(float(res.get("top_speed_kmh", 0.0))))},
		{"label": "Route", "value": "%.2f km" % (float(res.get("length", 0.0)) / 1000.0)},
		{"label": "Gold / silver / bronze", "value": "%s / %s / %s" % [_fmt_time(float(par.get("gold", 0.0))),
				_fmt_time(float(par.get("silver", 0.0))), _fmt_time(float(par.get("bronze", 0.0)))]},
	]
	var args := {
		"id": id, "kind": "race", "title": str(d.get("display_name", "Race")), "subtitle": str(d.get("subtitle", "")),
		"passed": medal != "none", "medal": medal if medal != "none" else "", "medal_id": medal,
		"fail_reason": "Slower than the bronze time", "lines": lines, "reward": reward, "xp": {"driving": snappedf(xp, 0.01)},
		"new_record": new_record, "can_retry": true, "retry": Callable(self, "retry_last"), "time": t,
		"best_time": float(rec["best_time"]), "par": par, "top_speed_kmh": float(res.get("top_speed_kmh", 0.0)),
	}
	_finish(id, args)


## Called by the stunt watcher after every jump attempt from a ramp.
func _on_stunt_result(d: Dictionary, res: Dictionary) -> void:
	var id := str(d.get("id", ""))
	var rec := get_record(id)
	rec["attempts"] = int(rec["attempts"]) + 1
	var success := bool(res.get("success", false))
	var first := success and not bool(rec["done"])
	var dist := float(res.get("distance", 0.0))
	var at := float(res.get("airtime", 0.0))
	var pb := success and dist > float(rec["best_distance"])
	if success:
		rec["done"] = true
		rec["completions"] = int(rec["completions"]) + 1
		rec["best_distance"] = maxf(float(rec["best_distance"]), dist)
		rec["best_airtime"] = maxf(float(rec["best_airtime"]), at)
	records[id] = rec
	stats["stunts"] = int(stats["stunts"]) + 1
	var reward := 0
	var prog := get_stunt_progress()
	if first:
		reward = int(d.get("reward", 300))
		Game.add_money(reward)
		Skills.add_xp("driving", float(d.get("xp", 0.3)))
		UI.banner("STUNT JUMP", "%.1f m  -  %.2f s airtime" % [dist, at], Color(0.969, 0.788, 0.282), 3.0)
		UI.notify("Stunt jump complete (%d / %d)  +$%d" % [prog.x, prog.y, reward], "money")
		Audio.play("activity_win", -3.0, 1.0, "UI")
	elif success:
		Skills.add_xp("driving", 0.05)
		UI.notify("%s: %.1f m, %.2f s%s" % [str(d.get("display_name", "Stunt jump")), dist, at,
				"  - new best" if pb else ""], "good")
	else:
		var why := str(res.get("reason", ""))
		if why == "too short":
			UI.notify("Stunt jump too short: %.1f m (needs %.0f m)" % [dist, float(d.get("min_distance", 0.0))], "info")
		else:
			UI.notify("Stunt jump failed: %s" % why, "warn")
	var result := res.duplicate()
	result["kind"] = "stunt_jump"
	result["result_screen"] = false          # banner / toast only: no pausing panel after a jump
	result["title"] = str(d.get("display_name", "Stunt Jump"))
	result["passed"] = success
	result["first_time"] = first
	result["reward"] = reward
	result["best_distance"] = float(rec["best_distance"])
	result["completed"] = prog.x
	result["total"] = prog.y
	last_result = result
	EventBus.activity_finished.emit(id, result)


func _finish(id: String, args: Dictionary) -> void:
	active_id = ""
	active_kind = ""
	last_id = id
	last_result = args
	stats["finished"] = int(stats["finished"]) + 1
	args["result_screen"] = show_results
	EventBus.activity_finished.emit(id, args)
	_refresh_prompts()
	if show_results:
		_show_result(args)


func _show_result(args: Dictionary) -> void:
	var scr: Control = null
	if UI.has_method("open_screen"):
		var path := str(UI.SCREENS.get(RESULT_SCREEN, ""))
		if path != "" and ResourceLoader.exists(path):
			scr = UI.open_screen(RESULT_SCREEN, args)
	if scr != null:
		return
	# fallback when the UI module has no result screen yet
	Audio.play("activity_win", -3.0, 1.0, "UI")
	var medal := str(args.get("medal_id", "none"))

	var main := ""
	if str(args.get("kind", "")) == "race":
		main = _fmt_time(float(args.get("time", 0.0)))
	else:
		main = "%d points" % int(args.get("score", 0))
	var sub := "%s  -  %s" % [main, medal.to_upper() if medal != "none" else "NO MEDAL"]
	if bool(args.get("new_record", false)):
		sub += "  -  NEW BEST"
	UI.banner(str(args.get("title", "")).to_upper(), sub, MEDAL_COLORS.get(medal, Color.WHITE), 4.5)
	if int(args.get("reward", 0)) > 0:
		UI.notify("%s reward  +$%d" % [medal.capitalize(), int(args.get("reward", 0))], "money")


static func _fmt_time(t: float) -> String:
	if t < 0.0:
		return "-"
	var m := int(t / 60.0)
	return "%d:%04.1f" % [m, t - m * 60.0]


func _refresh_prompts() -> void:
	for p: Dictionary in points:
		var it: Variant = p.get("interactable", null)
		if not (it is Interactable) or not is_instance_valid(it):
			continue
		var id := str(p["id"])
		var d: Dictionary = defs.get(id, {})
		var rec := get_record(id)
		var txt := str(d.get("prompt", d.get("display_name", id)))
		if str(d.get("kind", "")) == "race" and float(rec["best_time"]) > 0.0:
			txt += "  (best %s)" % _fmt_time(float(rec["best_time"]))
		elif str(d.get("kind", "")) == "shooting_range" and int(rec["best_score"]) >= 0:
			txt += "  (best %d)" % int(rec["best_score"])
		(it as Interactable).prompt = txt


# =================================================================================================
# HUD
# =================================================================================================

## Polled by the HUD widget (UI HudActivity card). Always: active, id, kind, title, timer, checkpoint,
## total, phase. Plus per kind (only keys that mean something, the card shows a chip per key):
##   shooting_range: subtitle ("Round n/m  name"), time, time_mode, score, round, rounds, hits,
##                   shots, hint, countdown, color
##   race:           subtitle, time, time_mode, checkpoint (= passed), checkpoints, lap, laps,
##                   par_gold, distance_to_checkpoint, hint, countdown, color
##   stunt_jump:     subtitle, time (= airtime), distance, airtime, min_distance, hint, color
## The same Dictionary is reused between calls (read it, do not keep it).
func get_hud_info() -> Dictionary:
	_hud.clear()
	_hud["active"] = false
	_hud["id"] = ""
	_hud["kind"] = ""
	_hud["title"] = ""
	_hud["timer"] = 0.0
	_hud["checkpoint"] = 0
	_hud["total"] = 0
	_hud["phase"] = "idle"
	if active_id != "":

		_hud["active"] = true
		_hud["id"] = active_id
		_hud["kind"] = active_kind
		if active_kind == "shooting_range":
			range_ctl.call("fill_hud", _hud)
		elif active_kind == "race":
			race_ctl.call("fill_hud", _hud)
	elif stunts != null and bool(stunts.call("is_busy")):
		_hud["active"] = true
		_hud["kind"] = "stunt_jump"
		stunts.call("fill_hud", _hud)
	return _hud


func _ensure_fallback_hud() -> void:
	if _has_external_widget():
		if hud_fallback != null and is_instance_valid(hud_fallback):
			hud_fallback.queue_free()
			hud_fallback = null
		return
	if hud_fallback != null and is_instance_valid(hud_fallback):
		return
	hud_fallback = HudFallback.new()
	hud_fallback.name = "ActivityHudFallback"
	hud_fallback.set("sys", self)
	add_child(hud_fallback)


## True when the UI module ships its own activity widget (group "hud_activity_widget", or a HUD
## node whose script path mentions "activit").
func _has_external_widget() -> bool:
	if not get_tree().get_nodes_in_group(WIDGET_GROUP).is_empty():
		return true
	var hud: Node = UI.get_hud() if UI.has_method("get_hud") else null
	if hud == null:
		return false
	var stack: Array[Node] = [hud]
	var guard := 0
	while not stack.is_empty() and guard < 4000:
		guard += 1
		var n: Node = stack.pop_back()
		var s: Variant = n.get_script()
		if s is Script and (s as Script).resource_path.to_lower().contains("activit"):
			return true
		for c in n.get_children():
			stack.append(c)
	return false


# =================================================================================================
# queries
# =================================================================================================

## Every activity with its activity point (stunts: the ramp lip) and record - map legends, admin.
func get_activity_list() -> Array:
	var out: Array = []
	for id: String in order:
		var d: Dictionary = defs[id]
		var pos := Vector3.INF
		for p: Dictionary in points:
			if str(p["id"]) == id:
				pos = (p["xform"] as Transform3D).origin
		if str(d.get("kind", "")) == "stunt_jump":
			var r: Dictionary = stunts.call("get_ramp", id)
			if not r.is_empty():
				pos = r["lip_world"]
		out.append({"id": id, "kind": str(d.get("kind", "")), "display_name": str(d.get("display_name", id)),
				"subtitle": str(d.get("subtitle", "")), "position": pos, "record": get_record(id)})
	return out


func get_stunt_progress() -> Vector2i:
	var done := 0
	var total := 0
	for id: String in order:
		if str((defs[id] as Dictionary).get("kind", "")) == "stunt_jump":
			total += 1
			if bool(get_record(id)["done"]):
				done += 1
	return Vector2i(done, total)


func get_point(id: String) -> Dictionary:
	for p: Dictionary in points:
		if str(p["id"]) == id:
			return p
	return {}


func reset_records() -> void:
	records.clear()
	_refresh_prompts()


# =================================================================================================
# persistence (SaveSystem provider "activities")
# =================================================================================================

func get_save_data() -> Dictionary:
	return {"version": SAVE_VERSION, "records": records.duplicate(true)}


func load_save_data(d: Dictionary) -> void:
	records.clear()
	var recs: Variant = d.get("records", {})
	if recs is Dictionary:
		for id: Variant in recs:
			var r: Variant = (recs as Dictionary)[id]
			if not (r is Dictionary):
				continue
			var clean := _blank_record()
			for k: String in clean:
				if (r as Dictionary).has(k):
					var v: Variant = (r as Dictionary)[k]
					match typeof(clean[k]):
						TYPE_INT:
							clean[k] = int(v)
						TYPE_FLOAT:
							clean[k] = float(v)
						TYPE_BOOL:
							clean[k] = bool(v)
						_:
							clean[k] = str(v)
			records[str(id)] = clean
	_refresh_prompts()
