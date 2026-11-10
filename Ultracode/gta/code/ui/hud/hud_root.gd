class_name HudRoot
extends Control
## The in-game HUD (root of res://gta/scenes/ui/hud.tscn, child of the UI autoload).
## Builds every HUD piece in code, anchors them to the screen corners / edges and feeds them from
## EventBus signals plus a few cheap polls. Every data source may be missing (no player, no
## world, stub autoloads) - nothing here assumes a neighbour module exists.
##
## Layout (logical 1920x1080, anchored so it holds from 16:10 to ultra-wide):
##   bottom-left   minimap, clock / weather / district above it, health + armor card beside it
##   top-centre    wanted strip, district / radio caption under it
##   top-right     money (toasts are drawn by the UI autoload right below it)
##   bottom-right  weapon card, vehicle cluster above it
##   bottom-centre interaction prompt        centre: crosshair + hit marker, stealth eye under it
##   top-left      activity card (timer / checkpoints), taxi fare meter under it
##   right-centre  skydiving altimeter or the breath / scuba gauge (situational)
##   full screen   low-health vignette / damage flash (shader), sniper scope overlay (shader)

const VIGNETTE_SHADER := "res://gta/code/ui/shaders/hud_vignette.gdshader"
const SCOPE_SHADER := "res://gta/code/ui/shaders/hud_scope.gdshader"
const M := UiStyle.MARGIN

var minimap: Minimap
var clock: HudClock
var vitals: HudVitals
var money: HudMoney
var wanted: HudWanted
var weapon: HudWeapon
var crosshair: HudCrosshair
var vehicle: HudVehicle
var caption: HudCaption
var prompt: HudPrompt
var activity: HudActivity
var taxi_meter: HudTaxiMeter
var altimeter: HudAltimeter
var dive: HudDive
var stealth: HudStealth

const AIR_STATES: Array[String] = ["parachute", "freefall"]

var _vignette: ColorRect
var _vig_mat: ShaderMaterial
var _scope: ColorRect
var _scope_mat: ShaderMaterial
var _flash: float = 0.0
var _low: float = 0.0
var _vig_low_sent: float = -1.0
var _vig_flash_sent: float = -1.0
var _scoped: bool = false
var _vehicle: Node3D = null
var _district: String = ""
var _poll: float = 0.0
var _poll_slow: float = 0.0
var _skill_known: Dictionary = {}
var _skill_pending: Dictionary = {}
var _skill_flush_queued: bool = false
var _built: bool = false
var _veh_lift: float = 0.0
var _public_state: String = ""          ## last EventBus.player_state_changed value
var _air_mode: String = ""              ## "parachute" | "freefall" | ""
var _activity_poll: float = 0.0
var _left_stack: VBoxContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_connect()
	sync_all()


# --- construction ----------------------------------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	_vignette = _overlay_rect(VIGNETTE_SHADER)
	_vig_mat = _vignette.material as ShaderMaterial
	_scope = _overlay_rect(SCOPE_SHADER)
	_scope_mat = _scope.material as ShaderMaterial

	crosshair = HudCrosshair.new()
	add_child(crosshair)

	minimap = Minimap.new()
	_pin(minimap, 0.0, 1.0, Vector2(M, -M - Minimap.DIAMETER), Vector2(Minimap.DIAMETER, Minimap.DIAMETER))
	clock = HudClock.new()
	_pin(clock, 0.0, 1.0, Vector2(M + 8.0, -M - Minimap.DIAMETER - 58.0), clock.custom_minimum_size)
	vitals = HudVitals.new()
	_pin(vitals, 0.0, 1.0, Vector2(M + Minimap.DIAMETER + 22.0, -M - vitals.custom_minimum_size.y), vitals.custom_minimum_size)

	money = HudMoney.new()
	_pin(money, 1.0, 0.0, Vector2(-M - money.custom_minimum_size.x, M), money.custom_minimum_size)

	wanted = HudWanted.new()
	_pin(wanted, 0.5, 0.0, Vector2(-wanted.custom_minimum_size.x * 0.5, 30.0), wanted.custom_minimum_size)
	caption = HudCaption.new()
	_pin(caption, 0.5, 0.0, Vector2(-caption.custom_minimum_size.x * 0.5, 168.0), caption.custom_minimum_size)

	weapon = HudWeapon.new()
	_pin(weapon, 1.0, 1.0, Vector2(-M - HudWeapon.CARD.x, -M - HudWeapon.CARD.y), HudWeapon.CARD)
	vehicle = HudVehicle.new()
	_pin(vehicle, 1.0, 1.0, Vector2(-M - HudVehicle.SIZE.x, -M - HudVehicle.SIZE.y), HudVehicle.SIZE)

	prompt = HudPrompt.new()
	_pin(prompt, 0.5, 1.0, Vector2(-prompt.custom_minimum_size.x * 0.5, -190.0), prompt.custom_minimum_size)

	stealth = HudStealth.new()
	_pin(stealth, 0.5, 0.5, Vector2(-HudStealth.SIZE.x * 0.5, 64.0), HudStealth.SIZE)
	altimeter = HudAltimeter.new()
	altimeter.deploy_key = InputSetup.label("jump")      # PlayerStateFreefall deploys on "jump"
	_pin(altimeter, 1.0, 0.5, Vector2(-M - HudAltimeter.SIZE.x, -HudAltimeter.SIZE.y * 0.5 - 40.0), HudAltimeter.SIZE)
	dive = HudDive.new()
	_pin(dive, 1.0, 0.5, Vector2(-M - HudDive.SIZE.x, -HudDive.SIZE.y * 0.5 - 40.0), HudDive.SIZE)
	_left_stack = VBoxContainer.new()
	_left_stack.name = "LeftStack"
	_left_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_stack.add_theme_constant_override("separation", 14)
	_pin(_left_stack, 0.0, 0.0, Vector2(M, M), Vector2(HudActivity.SIZE.x, HudActivity.SIZE.y + HudTaxiMeter.SIZE.y + 14.0))
	activity = HudActivity.new()
	_left_stack.add_child(activity)
	taxi_meter = HudTaxiMeter.new()
	_left_stack.add_child(taxi_meter)

	var ui := _ui()
	if ui != null:
		minimap.set_sources(ui.get("map_data"), ui.get("nav"))


func _overlay_rect(shader_path: String) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.visible = false
	if ResourceLoader.exists(shader_path):
		var sh := load(shader_path) as Shader
		if sh != null:
			var m := ShaderMaterial.new()
			m.shader = sh
			r.material = m
	add_child(r)
	return r


## Anchor `c` to a point of the screen (ax, ay in 0..1) with a fixed size and offset.
func _pin(c: Control, ax: float, ay: float, offset: Vector2, p_size: Vector2) -> void:
	add_child(c)
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + p_size.x
	c.offset_bottom = offset.y + p_size.y


func _ui() -> Node:
	var p := get_parent()
	while p != null:
		if p.has_method("open_screen"):
			return p
		p = p.get_parent()
	return get_tree().root.get_node_or_null("UI") if is_inside_tree() else null


func _connect() -> void:
	EventBus.game_ready.connect(sync_all)
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.player_respawned.connect(_on_player_respawned)
	EventBus.player_health_changed.connect(_on_health)
	EventBus.player_damaged.connect(_on_damaged)
	EventBus.money_changed.connect(_on_money)
	EventBus.weapon_equipped.connect(_on_weapon_equipped)
	EventBus.ammo_changed.connect(_on_ammo)
	EventBus.weapon_reload_started.connect(_on_reload)
	EventBus.hit_confirmed.connect(_on_hit)
	EventBus.camera_mode_changed.connect(_on_camera_mode)
	EventBus.player_entered_vehicle.connect(_on_entered_vehicle)
	EventBus.player_exited_vehicle.connect(_on_exited_vehicle)
	EventBus.player_district_changed.connect(_on_district)
	EventBus.time_changed.connect(_on_time)
	EventBus.weather_changed.connect(_on_weather)
	EventBus.day_phase_changed.connect(_on_phase)
	EventBus.radio_station_changed.connect(_on_radio)
	EventBus.skill_changed.connect(_on_skill)
	EventBus.player_state_changed.connect(_on_player_state)
	EventBus.activity_started.connect(_on_activity_started)
	EventBus.activity_finished.connect(_on_activity_finished)


# --- state for tests / debugging -------------------------------------------------------------------

func get_state() -> Dictionary:
	return {
		"health": vitals.health, "armor": vitals.armor, "money": money.amount,
		"wanted_level": wanted.level, "wanted_state": wanted.state,
		"weapon_id": weapon.weapon_id, "in_mag": weapon.in_mag, "reserve": weapon.reserve,
		"weapon_shown": weapon.is_shown(), "in_vehicle": vehicle.active, "speed": vehicle.speed,
		"district": _district, "scoped": _scoped, "crosshair_style": crosshair.style,
		"prompt": prompt.text if prompt.is_showing() else "", "caption": caption.get_title(),
		"flash": _flash, "low": _low, "time": clock.time_text,
		"activity": activity.activity_id if activity.active else "", "activity_time": activity.get_time_text(),
		"taxi_fare": taxi_meter.fare if taxi_meter.active else -1, "altimeter": altimeter.active,
		"altitude": altimeter.altitude, "pull_warning": altimeter.is_pull_warning(), "dive": dive.active,
		"breath": dive.breath, "scuba": dive.scuba, "stealth": stealth.active, "drive_by_blocked": crosshair.blocked,
	}


## Pull the current state from every source (called on game_ready / spawn / respawn).
func sync_all() -> void:
	if not _built:
		return
	money.set_money(Game.money, 0, false)
	var pl := _player()
	if pl != null:
		vitals.set_vitals(UiKit.num(pl, &"health", 100.0), UiKit.num(pl, &"max_health", 100.0),
				UiKit.num(pl, &"armor", 0.0), UiKit.num(pl, &"max_armor", 100.0))
	vitals.snap()
	wanted.set_wanted(Wanted.level, Wanted.state, Wanted.escape_progress)
	clock.set_time(WorldClock.get_time_string())
	_refresh_weather()
	_sync_weapon_from_inventory()
	_sync_vehicle(Game.get_player_vehicle())
	for s: String in Skills.SKILLS:
		_skill_known[s] = int(Skills.get_level(s))
	_poll_district()
	# the HUD caption announces radio stations: switch off the radio system's own toast
	var radio := Game.get_system("radio")
	if radio != null and "announce" in radio:
		radio.set("announce", false)


func _player() -> Node3D:
	if Game.has_player():
		return Game.player
	return null


# --- frame update ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _built or not visible:
		return
	# low-health vignette + damage flash
	var hf := vitals.health / vitals.max_health
	var low_target := 0.0
	if vitals.health <= 0.0:
		low_target = 1.0
	elif hf < 0.35:
		low_target = clampf((0.35 - hf) / 0.25, 0.0, 1.0)
	_low = move_toward(_low, low_target, delta * 2.0)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.4, 0.0)
	var show_vig := _low > 0.004 or _flash > 0.004
	if show_vig != _vignette.visible:
		_vignette.visible = show_vig
	if show_vig and _vig_mat != null:
		if absf(_low - _vig_low_sent) > 0.003:
			_vig_low_sent = _low
			_vig_mat.set_shader_parameter(&"low", _low)
		if absf(_flash - _vig_flash_sent) > 0.003:
			_vig_flash_sent = _flash
			_vig_mat.set_shader_parameter(&"flash", _flash)

	var pl := _player()
	var in_vehicle := _vehicle != null and is_instance_valid(_vehicle)
	# crosshair + thin bars
	var style := 0
	if pl != null:
		vitals.set_extra(UiKit.num(pl, &"stamina", 1.0), UiKit.num(pl, &"breath", 1.0))
		# in a vehicle the reticle only appears while aiming (drive-by); on foot a dot or the
		# spread reticle of the weapon in hand
		var drive_by := in_vehicle and UiKit.flag(pl, &"is_aiming")
		crosshair.blocked = drive_by and _drive_by_out_of_arc(pl)
		if not _scoped and vitals.health > 0.0 and (not in_vehicle or drive_by):
			style = 1
			var inv: Variant = pl.get(&"inventory")
			if inv is Object and is_instance_valid(inv):
				var spread := 0.0
				if (inv as Object).has_method(&"get_current_spread"):
					spread = float((inv as Object).call(&"get_current_spread"))
				elif (inv as Object).has_method(&"get_spread"):
					spread = float((inv as Object).call(&"get_spread"))
				if spread > 0.0:
					style = 2
					crosshair.set_spread(spread)
	crosshair.style = style
	if pl == null or not in_vehicle:
		crosshair.blocked = false
	_update_situational(pl, in_vehicle)

	if in_vehicle:
		var mh := maxf(UiKit.num(_vehicle, &"max_health", 1000.0), 1.0)
		vehicle.update_values(UiKit.num(_vehicle, &"speed_kmh"), UiKit.num(_vehicle, &"health", mh) / mh,
				UiKit.num(_vehicle, &"altitude_agl", _vehicle.global_position.y - Game.WATER_LEVEL))
	elif _vehicle != null:
		_sync_vehicle(null)

	# the vehicle cluster sits right above the weapon card, or in its place while unarmed
	var lift := (HudWeapon.CARD.y + 16.0) if weapon.is_shown() else 0.0
	if absf(lift - _veh_lift) > 0.5:
		_veh_lift = lerpf(_veh_lift, lift, 1.0 - exp(-10.0 * delta))
		vehicle.offset_top = -M - HudVehicle.SIZE.y - _veh_lift
		vehicle.offset_bottom = -M - _veh_lift

	if Wanted.level > 0 or wanted.level > 0:
		wanted.set_wanted(Wanted.level, Wanted.state, Wanted.escape_progress)

	_poll += delta
	if _poll >= 0.25:
		_poll = 0.0
		_quarter_poll(pl)
		_poll_taxi()
	_activity_poll += delta
	if _activity_poll >= (0.1 if activity.active else 0.5):
		_activity_poll = 0.0
		_poll_activity()
	_poll_slow += delta
	if _poll_slow >= 0.5:
		_poll_slow = 0.0
		_poll_district()


## Safety net for anything that changed without a signal (stub modules, direct assignments).
func _quarter_poll(pl: Node3D) -> void:
	if pl != null:
		var h := UiKit.num(pl, &"health", vitals.health)
		var a := UiKit.num(pl, &"armor", vitals.armor)
		if absf(h - vitals.health) > 0.01 or absf(a - vitals.armor) > 0.01:
			vitals.set_vitals(h, UiKit.num(pl, &"max_health", vitals.max_health), a, UiKit.num(pl, &"max_armor", vitals.max_armor))
	if Game.money != money.amount:
		money.set_money(Game.money, 0, true)
	var veh := Game.get_player_vehicle()
	if veh != _vehicle and (veh != null or (_vehicle != null and pl != null)):
		_sync_vehicle(veh)
	if pl != null:
		var inv: Variant = pl.get(&"inventory")
		if inv is Object and is_instance_valid(inv):
			var cur := UiKit.text_of(inv as Object, &"current_id", weapon.weapon_id)
			if cur != weapon.weapon_id:
				_sync_weapon_from_inventory()


func _poll_district() -> void:
	var w := Game.world
	if w == null or not is_instance_valid(w) or not w.has_method("get_district") or not Game.has_player():
		return
	var d: Variant = w.call("get_district", Game.get_player_position())
	if d is String or d is StringName:
		_on_district(str(d))


# --- signal handlers -------------------------------------------------------------------------------

func _on_player_spawned(_p: Node3D) -> void:
	sync_all.call_deferred()


func _on_player_respawned(_pos: Vector3) -> void:
	_flash = 0.0
	sync_all()


func _on_health(health: float, armor: float) -> void:
	var pl := _player()
	vitals.set_vitals(health, UiKit.num(pl, &"max_health", vitals.max_health), armor, UiKit.num(pl, &"max_armor", vitals.max_armor))


func _on_damaged(amount: float, _info: Dictionary) -> void:
	_flash = clampf(maxf(_flash, 0.35 + amount / 60.0), 0.0, 1.0)


func _on_money(amount: int, delta_amount: int) -> void:
	money.set_money(amount, delta_amount, true)


func _on_weapon_equipped(weapon_id: String) -> void:
	var def: Variant = Registry.get_def("weapons", weapon_id)
	var display := str(_def_get(def, "display_name", weapon_id.capitalize()))
	if display == "":
		display = weapon_id.capitalize()
	var slot := str(_def_get(def, "slot", "melee" if weapon_id == "fists" else "handgun"))
	var mag := int(_def_get(def, "mag_size", 0))
	weapon.set_weapon(weapon_id, display, slot, mag)
	var inv := _inventory()
	if inv != null and inv.has_method("get_ammo"):
		var a: Variant = inv.call("get_ammo", weapon_id)
		if a is Dictionary:
			weapon.mag_size = int((a as Dictionary).get("mag_size", mag))
			weapon.set_ammo(int((a as Dictionary).get("in_mag", -1)), int((a as Dictionary).get("reserve", -1)))
			return
	if def == null:
		weapon.set_ammo(-1, -1)


func _on_ammo(weapon_id: String, in_mag: int, reserve: int) -> void:
	if weapon_id != weapon.weapon_id:
		_on_weapon_equipped(weapon_id)
	weapon.set_ammo(in_mag, reserve)


func _on_reload(weapon_id: String, duration: float) -> void:
	if weapon_id == weapon.weapon_id:
		weapon.start_reload(duration)


func _on_hit(_target: Node, info: Dictionary) -> void:
	crosshair.hit(bool(info.get("killed", info.get("kill", info.get("lethal", false)))))


func _on_camera_mode(mode: String) -> void:
	_scoped = mode == "scope"
	_scope.visible = _scoped
	if _scoped and _scope_mat != null:
		_scope_mat.set_shader_parameter(&"aspect", size.x / maxf(size.y, 1.0))


func _on_entered_vehicle(v: Node3D, _seat: int) -> void:
	_sync_vehicle(v)


func _on_exited_vehicle(_v: Node3D) -> void:
	_sync_vehicle(null)


func _sync_vehicle(v: Node3D) -> void:
	if v != null and not is_instance_valid(v):
		v = null
	_vehicle = v
	if v == null:
		vehicle.set_vehicle(false)
		return
	var spec_id := UiKit.text_of(v, &"spec_id", "")
	var title := spec_id.capitalize()
	var def: Variant = Registry.get_def("vehicles", spec_id) if spec_id != "" else null
	var dn := str(_def_get(def, "display_name", ""))
	if dn != "":
		title = dn
	vehicle.set_vehicle(true, title, UiKit.text_of(v, &"vehicle_class", "car"))


func _on_district(d: String) -> void:
	if d == _district or d == "":
		return
	_district = d
	var nice := UiMapData.district_name(d)
	clock.set_district(nice)
	if Game.is_ready:
		caption.show_caption(nice, "Halcyon Bay", &"pin", UiStyle.TEAL_LIGHT, 3.6)


func _on_time(_hour: float) -> void:
	clock.set_time(WorldClock.get_time_string())


func _on_weather(_id: String, _prev: String) -> void:
	_refresh_weather()


func _on_phase(_phase: String) -> void:
	_refresh_weather()


func _refresh_weather() -> void:
	clock.set_weather(UiIcons.weather_icon(str(Weather.current), WorldClock.is_night()))


func _on_radio(station_id: String) -> void:
	if not Game.is_ready:
		return
	if station_id == "" or station_id == "off":
		if caption.get_title() != "" or _vehicle != null:
			caption.show_caption("Radio Off", "", &"radio", UiStyle.MUTED, 2.2)
		return
	var radio := Game.get_system("radio")
	if radio != null:
		if "announce" in radio:
			radio.set("announce", false)        # the HUD caption replaces the radio system's own toast
		if radio.has_method("is_listening") and not bool(radio.call("is_listening")):
			return
	var def: Variant = Registry.get_def("radio_stations", station_id)
	var station := str(_def_get(def, "display_name", _def_get(def, "name", station_id.capitalize())))
	var genre := str(_def_get(def, "genre", _def_get(def, "description", "Radio")))
	var freq := str(_def_get(def, "frequency", ""))
	if freq != "":
		genre = "%s  -  %s FM" % [genre, freq]
	var col: Variant = _def_get(def, "color", UiStyle.CORAL)
	caption.show_caption(station, genre, &"radio", col if col is Color else UiStyle.CORAL, 3.2)


func _on_skill(skill: String, value: float) -> void:
	_skill_pending[skill] = value
	if not _skill_flush_queued:
		_skill_flush_queued = true
		_flush_skills.call_deferred()


## Bulk changes in one frame (load / reset / admin "max all") update silently; single skill
## level-ups get a toast.
func _flush_skills() -> void:
	_skill_flush_queued = false
	var bulk := _skill_pending.size() > 2 or not Game.is_ready
	for skill: String in _skill_pending:
		var lvl := int(float(_skill_pending[skill]))
		var known := int(_skill_known.get(skill, lvl))
		_skill_known[skill] = lvl
		if not bulk and lvl > known:
			var ui := _ui()
			if ui != null:
				var nice := str(Skills.DISPLAY_NAMES.get(skill, skill.capitalize()))
				ui.call("notify", "%s skill up  -  %d" % [nice, lvl], "skill", 3.5)
	_skill_pending.clear()


# --- wave 3: situational widgets -------------------------------------------------------------------

## Altimeter (parachute / freefall), dive gauge (under water), stealth eye. Plain property reads.
func _update_situational(pl: Node3D, in_vehicle: bool) -> void:
	if pl == null or vitals.health <= 0.0:
		minimap.air_mode = false
		altimeter.set_active(false)
		dive.set_active(false)
		stealth.set_active(false)
		vitals.show_breath = true
		return
	# skydiving
	_air_mode = "" if in_vehicle else _detect_air_mode(pl)
	var air := _air_mode != ""
	minimap.air_mode = air
	altimeter.set_active(air)
	if air:
		var vel: Variant = pl.get(&"velocity")
		var vy: float = (vel as Vector3).y if vel is Vector3 else 0.0
		altimeter.set_values(_altitude_of(pl), vy, _air_mode == "parachute")
	# under water
	var under := not in_vehicle and UiKit.flag(pl, &"is_underwater")
	dive.set_active(under)
	vitals.show_breath = not under
	if under:
		var surf := UiKit.num(pl, &"water_surface_y", Game.WATER_LEVEL)
		dive.set_values(UiKit.num(pl, &"breath", 1.0), surf - pl.global_position.y - 0.9, UiKit.flag(pl, &"has_scuba"))
	# stealth
	var sneaking := not in_vehicle and not air and (UiKit.flag(pl, &"in_stealth") or _public_state == "stealth")
	stealth.set_active(sneaking)
	if sneaking:
		stealth.set_visibility(UiKit.num(pl, &"visibility_factor", 0.5))


## "parachute" / "freefall" from the last player_state_changed, the active state's public name or
## the animator state (whichever the player module provides).
func _detect_air_mode(pl: Node3D) -> String:
	if _public_state in AIR_STATES:
		return _public_state
	var st: Variant = pl.get(&"state")
	if st is Object and is_instance_valid(st):
		var pn := UiKit.text_of(st as Object, &"public_name", "")
		if pn in AIR_STATES:
			return pn
	var anim: Variant = pl.get(&"animator")
	if anim is Object and is_instance_valid(anim):
		var an := UiKit.text_of(anim as Object, &"state", "")
		if an in AIR_STATES:
			return an
	return ""


## Height above ground / water: player.altitude_agl when the player module provides it, else the
## terrain height (or sea level) under the player.
func _altitude_of(pl: Node3D) -> float:
	var agl: Variant = pl.get(&"altitude_agl")
	if agl is float or agl is int:
		return float(agl)
	var p := pl.global_position
	return p.y - maxf(Game.ground_height(p.x, p.z), Game.WATER_LEVEL)


## Drive-by: the player state exposes drive_by_in_arc (PlayerStateVehicle); false = no shot.
func _drive_by_out_of_arc(pl: Node3D) -> bool:
	var st: Variant = pl.get(&"state")
	if st is Object and is_instance_valid(st):
		var v: Variant = (st as Object).get(&"drive_by_in_arc")
		if v is bool:
			return not v
	return false


func _on_player_state(state: String) -> void:
	_public_state = state


func _on_activity_started(activity_id: String) -> void:
	var def: Variant = Registry.get_def("activities", activity_id)
	var title := str(_def_get(def, "display_name", _def_get(def, "name", activity_id.capitalize())))
	activity.start(activity_id, title if title != "" else activity_id.capitalize())
	_activity_poll = 0.0
	_poll_activity()


func _on_activity_finished(activity_id: String, _result: Dictionary) -> void:
	if activity_id == activity.activity_id or activity_id == "":
		activity.stop()


## The activities system's polling hook get_hud_info() -> Dictionary (see HudActivity for keys).
## {"active": false} stops the card; {"active": true, ...} while no card is shown starts it
## (normally the card starts on EventBus.activity_started).
func _poll_activity() -> void:
	var acts := Game.get_system("activities")
	if acts == null or not acts.has_method("get_hud_info"):
		return
	var d: Variant = acts.call("get_hud_info")
	if not (d is Dictionary) or (d as Dictionary).is_empty():
		return
	var info: Dictionary = d
	if not bool(info.get("active", true)):
		if activity.active:
			activity.stop()
		return
	if not activity.active:
		if not bool(info.get("active", false)):
			return
		var id := str(info.get("id", "activity"))
		activity.start(id, str(info.get("title", id.capitalize())))
	activity.set_info(info)


## Taxi fare meter: Game.get_system("taxi").get_fare() while the player rides a taxi
## (is_player_riding() / is_riding() when offered, else: sitting in a taxi someone else drives).
## The traffic module's taxi system exposes is_player_in_taxi() + get_job_info() {fare (quote),
## ride_m, destination, distance_to_target} + estimate_fare(m): the meter then runs with the
## distance driven (capped at the quote) and appears once a destination is chosen.
func _poll_taxi() -> void:
	var taxi := Game.get_system("taxi")
	var riding := false
	var fare: Variant = null
	if taxi != null and not taxi.has_method("get_fare") and taxi.has_method("is_player_in_taxi") and taxi.has_method("get_job_info"):
		riding = bool(taxi.call("is_player_in_taxi"))
		if riding:
			var job: Variant = taxi.call("get_job_info")
			var quote := 0
			var dest := ""
			if job is Dictionary:
				quote = int((job as Dictionary).get("fare", 0))
				dest = str((job as Dictionary).get("destination", ""))
			riding = quote > 0 or dest != ""
			if riding:
				var run := quote
				if taxi.has_method("estimate_fare"):
					run = int(taxi.call("estimate_fare", float((job as Dictionary).get("ride_m", 0.0))))
					if quote > 0:
						run = mini(run, quote)
				fare = {"fare": run, "quote": quote, "destination": dest,
						"distance": float((job as Dictionary).get("distance_to_target", -1.0))}
	elif taxi != null and taxi.has_method("get_fare"):
		if taxi.has_method("is_player_riding"):
			riding = bool(taxi.call("is_player_riding"))
		elif taxi.has_method("is_riding"):
			riding = bool(taxi.call("is_riding"))
		else:
			var v := Game.get_player_vehicle()
			riding = v != null and (UiKit.text_of(v, &"spec_id", "") == "taxi" or UiKit.text_of(v, &"owner_tag", "") == "taxi") \
					and not UiKit.flag(v, &"is_player_driven")
		if riding:
			fare = taxi.call("get_fare")
			if fare is Dictionary and (fare as Dictionary).has("active"):
				riding = bool((fare as Dictionary)["active"])
			elif fare == null or ((fare is float or fare is int) and float(fare) < 0.0):
				riding = false
	taxi_meter.set_active(riding)
	if riding:
		taxi_meter.set_fare(fare)


# --- helpers ---------------------------------------------------------------------------------------

func _inventory() -> Object:
	var pl := _player()
	if pl == null:
		return null
	var inv: Variant = pl.get(&"inventory")
	if inv is Object and is_instance_valid(inv):
		return inv
	return null


func _sync_weapon_from_inventory() -> void:
	var inv := _inventory()
	if inv == null:
		return
	var cur := UiKit.text_of(inv, &"current_id", "")
	if cur != "":
		_on_weapon_equipped(cur)


## Read a field from a registry definition that may be a Resource, a Dictionary or null.
static func _def_get(def: Variant, key: String, fallback: Variant) -> Variant:
	if def is Dictionary:
		return (def as Dictionary).get(key, fallback)
	if def is Object and is_instance_valid(def):
		var v: Variant = (def as Object).get(key)
		if v != null:
			return v
	return fallback
