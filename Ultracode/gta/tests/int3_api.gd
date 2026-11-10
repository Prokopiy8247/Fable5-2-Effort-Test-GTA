extends Node
## int3_api (interactions system, Wave 3): every kind of use point through the real player path
## (pooled Interactable -> PlayerInteraction scanner -> "interact" key press):
##   seat (bench sit / stand up / leave by moving), binoculars (scope camera + zoom + mask + HUD),
##   vending (purchase, heal, not enough cash), ATM (panel keys: deposit / withdraw / cooldown /
##   daily limit / close, money conserved), ATM robbery (crowbar, crime report, cash, out of
##   service), hospital lift lobby <-> roof, lighthouse door <-> gallery, pool size / caps.
## Windowed runs also take screenshots (qa/screenshots/int3_*.png).
##
## tools\godot.ps1 -Mode headless -Frames 7200 -TimeoutSec 400 -UserArgs '--test=int3_api','--disable=traffic,police','--test-timeout=360'
## tools\godot.ps1 -Mode window   -Frames 1200 -TimeoutSec 300 -UserArgs '--test=int3_api','--disable=traffic,police','--shots-only','--test-timeout=280'

var T: Node
var ix: Node
var p: Node3D
var _crimes: Array = []
var _shots_only := false


func _ready() -> void:
	T = TestHarness
	_shots_only = OS.get_cmdline_user_args().has("--shots-only")
	await T.wait_frames(90)
	ix = Game.get_system("interactions")
	p = Game.player
	if ix == null or p == null:
		T.check(false, "interactions system and player exist")
		T.finish()
		return
	EventBus.crime_committed.connect(func(id: String, _pos: Vector3, _who: Node) -> void: _crimes.append(id))
	if _shots_only:
		WorldClock.set_hour(10.5)
		Weather.snap_weather("clear")
	var counts: Dictionary = ix.call("get_counts")
	T.log_line("points: %s  debug: %s" % [str(counts), str(ix.call("get_debug_info"))])
	if not _shots_only:
		for k: String in ["seat", "vending", "atm", "binoculars", "lift"]:
			T.check(int(counts.get(k, 0)) > 0, "has %s points (%d)" % [k, int(counts.get(k, 0))])
		T.check(int(counts.get("lift", 0)) == 4, "two lifts with two ends each")
	await _seat()
	await _binoculars()
	if not _shots_only:
		await _vending()
	await _atm()
	if not _shots_only:
		await _robbery()
	await _lifts()
	if not _shots_only:
		_pool_caps()
	T.finish()


# --- helpers ---------------------------------------------------------------------------------------

func _go(pi: int, back: float = 0.0) -> void:
	var pt: Dictionary = (ix.get("points") as Array)[pi]
	var st: Transform3D = pt["stand"]
	var f := -st.basis.z
	f.y = 0.0
	var pos := st.origin - f.normalized() * back + Vector3.UP * 0.1
	if str(pt["kind"]) == "seat":
		pos = (pt.get("stand_up", st.origin) as Vector3) + Vector3.UP * 0.1
	p.call("teleport", pos, atan2(-f.x, -f.z))
	await T.wait_physics_frames(30)
	await _real_wait(0.5)


## Interactable cooldowns run on real milliseconds; headless runs simulate faster than real time.
func _real_wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _press(action: String) -> void:
	await _real_wait(0.7)
	Input.action_press(action)
	await T.wait_physics_frames(2)
	Input.action_release(action)
	await T.wait_physics_frames(3)


func _key_event(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await T.wait_frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await T.wait_frames(2)


func _focus_prompt() -> String:
	var inter: Variant = p.get("interaction")
	if inter is Object and (inter as Object).has_method("get_prompt_text"):
		return str((inter as Object).call("get_prompt_text"))
	return ""


func _state() -> String:
	return str(p.get("state_id"))


func _first(kind: String, src: String = "") -> int:
	var pts: Array = ix.get("points")
	for i in pts.size():
		var d: Dictionary = pts[i]
		if d["kind"] == kind and (src == "" or str(d.get("src", "")) == src):
			return i
	return -1


# --- seat ------------------------------------------------------------------------------------------

func _seat() -> void:
	# a free street bench (an NPC may sit on some of them)
	var pi := -1
	var pts: Array = ix.get("points")
	for src: String in ["bench", "bench_park", ""]:
		for i in pts.size():
			if pts[i]["kind"] == "seat" and (src == "" or str(pts[i].get("src", "")) == src) and bool(ix.call("can_use_point", i)):
				pi = i
				break
		if pi >= 0:
			break
	await _go(pi)
	await T.wait_seconds(0.4)
	T.check(_focus_prompt() == "Sit down", "prompt 'Sit down' at a bench (got '%s')" % _focus_prompt())
	await _press("interact")
	await T.wait_physics_frames(10)
	var pt: Dictionary = (ix.get("points") as Array)[pi]
	var seat: Transform3D = pt["stand"]
	T.check(_state() == "int_sit", "E sits down (state %s)" % _state())
	T.check(absf(p.global_position.y - (seat.origin.y + float(pt.get("height", 0.41)))) < 0.05, "body at hip height on the seat")
	T.check(not bool(p.call("is_collision_enabled")), "collision off while seated")
	var anim: Variant = p.get("animator")
	T.check(anim is Object and str((anim as Object).get("state")) == "seated_car", "seated pose")
	await T.wait_seconds(0.5)
	await _real_wait(0.5)
	T.check(_focus_prompt() == "Stand up", "prompt 'Stand up' while seated (got '%s')" % _focus_prompt())
	if _shots_only:
		# look at the sitter from the front-left
		var cam: Variant = p.get("camera")
		if cam is Object:
			(cam as Object).set("yaw", wrapf(p.global_rotation.y + PI * 0.78, -PI, PI))
			(cam as Object).set("pitch", -0.12)
		await T.wait_seconds(0.6)
	await T.shot("int3_bench_sit")
	await _press("interact")
	await T.wait_physics_frames(10)
	T.check(_state() == "on_foot", "E stands up (state %s)" % _state())
	T.check(bool(p.call("is_collision_enabled")), "collision back on")
	T.check(p.global_position.distance_to(pt.get("stand_up", seat.origin)) < 0.3, "standing in front of the seat")
	# leave by walking away
	if _shots_only:
		return
	T.check(bool(ix.call("use_point", pi)), "use_point sits again")
	await T.wait_seconds(0.6)
	Input.action_press("move_forward")
	await T.wait_seconds(0.6)
	Input.action_release("move_forward")
	await T.wait_physics_frames(5)
	T.check(_state() == "on_foot", "moving stands up (state %s)" % _state())
	# a seat taken by an NPC is not offered
	var npc_ok := true
	if Game.get_system("peds") != null:
		var npc: Node3D = Game.spawn_npc("civilian_m", seat.origin, {"persistent": true})
		if npc != null:
			await T.wait_physics_frames(3)
			npc.global_position = seat.origin
			npc_ok = not bool(ix.call("can_use_point", pi))
			npc.queue_free()
	T.check(npc_ok, "occupied seat is not offered")


# --- binoculars ------------------------------------------------------------------------------------

func _binoculars() -> void:
	var pi := _first("binoculars")
	if pi < 0:
		T.check(false, "binoculars point exists")
		return
	await _go(pi)
	await T.wait_seconds(0.4)
	T.check(_focus_prompt() == "Use binoculars", "prompt 'Use binoculars' (got '%s')" % _focus_prompt())
	await _press("interact")
	await T.wait_seconds(0.8)
	T.check(_state() == "int_view", "viewing (state %s)" % _state())
	var cam: Variant = p.get("camera")
	T.check(cam is Object and str((cam as Object).get("mode")) == "scope", "camera in scope mode")
	var c3d := get_viewport().get_camera_3d()
	T.check(c3d != null and absf(c3d.fov - 20.0) < 2.0, "zoomed FOV ~20 (%.1f)" % (c3d.fov if c3d != null else -1.0))
	var st: Variant = p.get("state")
	(st as Object).call("set_zoom", 3)
	await T.wait_seconds(0.8)
	T.check(c3d != null and absf(c3d.fov - 6.5) < 1.0, "max zoom FOV ~6.5 (%.1f)" % (c3d.fov if c3d != null else -1.0))
	var ov: Variant = (ix.get("_overlay"))
	T.check(ov is Control and (ov as Control).visible, "binocular mask visible")
	(st as Object).call("set_zoom", 1)
	await T.wait_seconds(0.5)
	await T.shot("int3_binoculars")
	await _press("interact")
	await T.wait_seconds(0.4)
	T.check(_state() == "on_foot", "step away (state %s)" % _state())
	T.check(cam is Object and str((cam as Object).get("mode")) != "scope", "camera back to normal")
	T.check(not ((ov as Control).visible), "mask hidden")


# --- vending ---------------------------------------------------------------------------------------

func _vending() -> void:
	var pi := _first("vending")
	await _go(pi)
	Game.set_money(100)
	p.set("health", 50.0)
	p.set("stamina", 0.2)
	await T.wait_seconds(0.4)
	T.check(str(_focus_prompt()).begins_with("Buy a Bay Fizz"), "vending prompt (got '%s')" % _focus_prompt())
	await _press("interact")
	await T.wait_physics_frames(5)
	T.check(Game.money == 96, "drink cost $4 (money %d)" % Game.money)
	T.check(absf(float(p.get("health")) - 62.0) < 0.6, "drink healed 12 (%.1f)" % float(p.get("health")))
	T.check(float(p.get("stamina")) > 0.95, "stamina refilled")
	Game.set_money(2)
	await T.wait_seconds(0.8)
	T.check(not bool(ix.call("use_point", pi)), "no purchase without cash")
	T.check(Game.money == 2, "money untouched")


# --- ATM -------------------------------------------------------------------------------------------

func _atm() -> void:
	var pi := _first("atm", "spawned")
	if pi < 0:
		pi = _first("atm")
	await _go(pi)
	var inv: Variant = p.get("inventory")
	if inv is Object:
		(inv as Object).call("equip", "fists")
	Game.set_money(1000)
	ix.set("bank_balance", 0)
	await T.wait_seconds(0.4)
	T.check(str(_focus_prompt()).begins_with("Use ATM"), "ATM prompt (got '%s')" % _focus_prompt())
	await _press("interact")
	await T.wait_frames(3)
	T.check(int(ix.get("atm_open_point")) == pi and Game.is_input_locked(), "ATM panel open, input locked")
	await _key_event("weapon_slot_3")
	T.check(int(ix.get("bank_balance")) == 100 and Game.money == 900, "deposit $100 (bank %d cash %d)" % [int(ix.get("bank_balance")), Game.money])
	await _key_event("weapon_slot_1")
	T.check(int(ix.get("bank_balance")) == 100, "second transaction within the cooldown is refused")
	await T.wait_seconds(1.2)
	await T.shot("int3_atm")
	await _key_event("weapon_slot_1")
	T.check(int(ix.get("bank_balance")) == 0 and Game.money == 1000, "withdraw $100 (cash %d)" % Game.money)
	await T.wait_seconds(1.2)
	await _key_event("weapon_slot_4")
	T.check(int(ix.get("bank_balance")) == 1000 and Game.money == 0, "deposit all cash")
	await T.wait_seconds(1.2)
	await _key_event("weapon_slot_2")
	T.check(Game.money == 500 and int(ix.get("bank_balance")) == 500, "withdraw $500")
	T.check(Game.money + int(ix.get("bank_balance")) == 1000, "money is conserved (nothing for free)")
	await _key_event("interact")
	T.check(int(ix.get("atm_open_point")) < 0 and not Game.is_input_locked(), "E closes the ATM, input unlocked")
	if _shots_only:
		return
	# daily limit (API level)
	ix.set("bank_balance", 10000)
	var rem := int(ix.call("get_withdraw_remaining"))
	var got := int(ix.call("withdraw", 5000))
	T.check(got == rem and int(ix.call("get_withdraw_remaining")) == 0, "daily withdrawal limit (%d of 5000, %d were left)" % [got, rem])
	T.check(int(ix.call("withdraw", 100)) == 0, "nothing more today")
	WorldClock.set("day", int(WorldClock.get("day")) + 1)
	T.check(int(ix.call("get_withdraw_remaining")) == 2000, "limit resets the next day")
	ix.set("bank_balance", 0)


# --- robbery ---------------------------------------------------------------------------------------

func _robbery() -> void:
	var pi := _first("atm", "spawned")
	if pi < 0:
		pi = _first("atm")
	await _go(pi)
	var inv: Variant = p.get("inventory")
	(inv as Object).call("give_weapon", "crowbar", -1)
	(inv as Object).call("equip", "crowbar")
	await T.wait_seconds(0.6)
	T.check(_focus_prompt() == "Break open the ATM", "crowbar prompt (got '%s')" % _focus_prompt())
	var money0 := Game.money
	var n_pick0 := get_tree().get_nodes_in_group("pickup").size()
	_crimes.clear()
	await _press("interact")
	await T.wait_seconds(3.2)
	T.check(_crimes.has("robbery"), "robbery reported to Wanted (%s)" % str(_crimes))
	var amount := int(ix.get_meta(&"last_robbery_amount", 0))
	var n_pick := get_tree().get_nodes_in_group("pickup").size()
	T.check(amount >= 160 and (n_pick > n_pick0 or Game.money > money0), "cash dropped ($%d)" % amount)
	T.check(bool(ix.call("is_atm_out_of_service", pi)), "ATM out of service")
	await T.wait_seconds(0.4)
	(inv as Object).call("equip", "fists")
	await T.wait_seconds(0.4)
	await _real_wait(0.5)
	T.check(_focus_prompt() == "ATM out of service", "out-of-service prompt (got '%s')" % _focus_prompt())
	T.check(bool(p.call("has_control")), "control back after the robbery")
	Wanted.clear("cheat")


# --- lifts -----------------------------------------------------------------------------------------

func _lifts() -> void:
	var pts: Array = ix.get("points")
	for src: String in ["hospital", "lighthouse"]:
		var a := -1
		for i in pts.size():
			if pts[i]["kind"] == "lift" and str(pts[i].get("src", "")) == src:
				a = i
				break
		if a < 0:
			T.check(false, "%s lift exists" % src)
			continue
		var b := int(pts[a]["dest"])
		await _go(a)
		await T.wait_seconds(0.4)
		T.check(_focus_prompt() == str(pts[a]["label"]), "%s prompt (got '%s')" % [src, _focus_prompt()])
		if src == "hospital":
			await T.shot("int3_lift_lobby")
		await _press("interact")
		await T.wait_seconds(2.4)
		var top: Vector3 = (pts[b]["stand"] as Transform3D).origin
		T.check(p.global_position.distance_to(top) < 1.0, "%s ride up arrives (%s vs %s)" % [src, str(p.global_position), str(top)])
		var y0 := p.global_position.y
		await T.wait_seconds(1.0)
		T.check(absf(p.global_position.y - y0) < 0.3 and p.global_position.y > top.y - 0.3, "%s: standing on the upper floor (y %.2f)" % [src, p.global_position.y])
		T.check(not Game.is_input_locked(), "input unlocked after the ride")
		await T.shot("int3_lift_top_" + src)
		await T.wait_seconds(0.6)
		await _real_wait(0.5)
		T.check(_focus_prompt() == str(pts[b]["label"]), "%s down prompt (got '%s')" % [src, _focus_prompt()])
		await _press("interact")
		await T.wait_seconds(2.4)
		var bottom: Vector3 = (pts[a]["stand"] as Transform3D).origin
		T.check(p.global_position.distance_to(bottom) < 1.0, "%s ride down arrives" % src)


func _pool_caps() -> void:
	var dbg: Dictionary = ix.call("get_debug_info")
	T.check(int(dbg.get("pool_assigned", 99)) <= 8, "pool never exceeds 8 interactables")
	var n := 0
	for it: Node in get_tree().get_nodes_in_group("interactable"):
		if it.get_parent() == ix:
			n += 1
	T.check(n == 8, "exactly 8 pooled Interactable nodes (%d)" % n)
