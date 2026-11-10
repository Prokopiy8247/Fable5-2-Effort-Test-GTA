class_name WeaponInventory
extends Node
## Weapons a character carries + everything that happens when the trigger is pulled.
##
## Owner-agnostic and input-agnostic: the holder (the Player, a test dummy, in principle an NPC)
## adds this node as a child named "Inventory", calls setup(holder) and then forwards intent:
##     trigger_pressed() / trigger_released(), reload(), set_aiming(on), equip_slot(n),
##     next_weapon() / prev_weapon(), holster(), melee_attack(heavy), throw_grenade().
## The inventory talks back to its holder only through (all optional, checked defensively):
##     get_aim_ray() -> {"origin": Vector3, "direction": Vector3}     crosshair ray (camera)
##     add_recoil(pitch: float, yaw: float)                            DEGREES, pitch > 0 = muzzle up
##     get_target_position() -> Vector3                                chest point (used in vehicles)
##     get_shoot_origin() -> Vector3                                   where shots / throws start (INF = default)
##     visual (CharacterVisual), current_vehicle, is_crouching, velocity
##     play_weapon_action(name, duration)  or  animator.play_action(name, duration)
## HUD-facing EventBus signals (weapon_equipped, ammo_changed, weapon_reload_started,
## weapon_inventory_changed) are emitted only when the holder is the player.
## Full API and tuning notes: docs/WEAPONS.md.

signal fired(weapon_id: String, result: Dictionary)        ## after every shot (result of Combat.fire_hitscan / {"projectile"})
signal dry_fired(weapon_id: String)
signal reload_started(weapon_id: String, duration: float)
signal reload_finished(weapon_id: String)
signal melee_started(weapon_id: String, heavy: bool, combo_step: int)
signal melee_landed(weapon_id: String, hits: Array)
signal throw_started(weapon_id: String)
signal thrown(weapon_id: String, projectile: Node3D)
signal equipped(weapon_id: String)
signal aiming_changed(on: bool)
signal recoil_kicked(pitch: float, yaw: float)             ## degrees, same values as holder.add_recoil
signal changed()                                           ## ownership / ammo / attachments changed

const UNARMED := "fists"
## Canonical order inside the wheel (slot by slot).
const ORDER: Array[String] = ["fists", "knife", "bat", "crowbar", "pistol", "heavy_pistol", "smg",
		"pump_shotgun", "auto_shotgun", "assault_rifle", "carbine", "marksman_rifle", "sniper_rifle",
		"rocket_launcher", "grenade_launcher", "grenade", "molotov"]
const DEFAULT_LOADOUT := {"pistol": 48}       ## plus fists
const DRIVE_BY_SPREAD_MULT := 1.6
const CROUCH_SPREAD_MULT := 0.8
const RUN_SPEED := 6.0                        ## planar speed that counts as "full run" for spread
const AUTO_RELOAD_DELAY := 0.3
const SHOT_BUFFER := 0.14                     ## a semi-auto pull this early still fires
const COMBO_WINDOW := 0.55
const COMBO_STEPS := 3
const COMBO_FINISHER_MULT := 1.4
const BASH_DAMAGE := 18.0                     ## melee with a firearm in hand
const BASH_RANGE := 1.5
const THROW_UP_BIAS := 0.22
const QUICK_THROW_WINDUP := 0.18
const THROW_COOLDOWN := 0.9
const MAX_COOK := 2.6                         ## a cooked grenade leaves the hand at the latest now
const DROP_SPEED_SCALE := 0.12                ## a live grenade dropped by a dying holder barely moves
const EYE_HEIGHT := 1.55
const EYE_HEIGHT_CROUCHED := 1.05
const SAVE_KEY := "weapons"                   ## SaveSystem provider key of the player's inventory

var current_id: String = ""                   ## equipped weapon id ("fists" = unarmed / holstered)
var holder: Node = null
var model: WeaponModel = null
var is_aiming: bool = false
var is_reloading: bool = false
var trigger_held: bool = false
var flashlight_on: bool = false
var infinite_ammo: bool = false               ## admin toggle: magazines never run dry
var emit_global_events: int = -1              ## -1 auto (holder is the player), 0 never, 1 always
var handle_flashlight_input: bool = true      ## the inventory reads the "weapon_flashlight" action itself

var _owned: Dictionary = {}                   ## id -> {"in_mag": int, "attachments": Array}
var _ammo: Dictionary = {}                    ## ammo type -> reserve rounds
var _spec_cache: Dictionary = {}              ## id -> effective WeaponSpec (attachments applied)
var _slot_memory: Dictionary = {}             ## slot -> last weapon used in that slot
var _last_weapon: String = ""
var _pre_vehicle_weapon: String = ""
var _was_in_vehicle: bool = false
var _default_checked: bool = false
var _default_frames: int = 0
var _save_registered: bool = false
var _loaded_from_save: bool = false

var _cooldown: float = 0.0
var _equip_left: float = 0.0
var _reload_left: float = 0.0
var _reload_total: float = 0.0
var _auto_reload_in: float = 0.0
var _shot_buffer: float = 0.0
var _dry_cd: float = 0.0
var _bloom: float = 0.0
var _bloom_hold: float = 0.0
var _burst: int = 0
var _burst_reset: float = 0.0
var _recoil_phase: float = 0.0

var _melee_left: float = 0.0
var _melee_hit_in: float = 0.0
var _melee_pending: bool = false
var _melee_heavy: bool = false
var _melee_queued: int = 0                    ## 0 none, 1 light, 2 heavy
var _combo_step: int = 0
var _combo_timer: float = 0.0

var _cooking: bool = false
var _cook_t: float = 0.0
var _throw_cd: float = 0.0
var _quick_throw_in: float = 0.0
var _quick_throw_id: String = ""

var _holder_was_dead: bool = false

var _light_state: int = -1
var _last_light_toggle_msec: int = -100000
var _attach_retry: int = 0


# =================================================================================================
# setup
# =================================================================================================

func _ready() -> void:
	if holder == null:
		setup(get_parent())


func _exit_tree() -> void:
	# Only when the inventory itself is removed for good. A holder that is merely re-parented
	# (the Player moves under a vehicle seat node) keeps its weapon model: the model lives under
	# the holder's hand socket and travels with it.
	if is_queued_for_deletion() and model != null and is_instance_valid(model):
		model.queue_free()
		model = null


## Bind the inventory to its holder. Safe to call more than once.
func setup(p_holder: Node = null) -> void:
	holder = p_holder if p_holder != null else get_parent()
	if not _owned.has(UNARMED) and Registry.has_def("weapons", UNARMED):
		_owned[UNARMED] = {"in_mag": 0, "attachments": []}
	_check_default_loadout()
	if current_id == "" and _owned.has(UNARMED):
		current_id = UNARMED
	_refresh_model()
	if _is_player():
		_announce.call_deferred()


## Fists + pistol with 48 rounds (only adds what is missing).
func give_default_loadout() -> void:
	_default_checked = true
	for id: String in DEFAULT_LOADOUT:
		if not has_weapon(id):
			give_weapon(id, int(DEFAULT_LOADOUT[id]))


func _check_default_loadout() -> void:
	if _default_checked:
		return
	if _is_player():
		_default_checked = true
		_register_save_provider()
		if _owned.size() <= 1 and not _loaded_from_save:
			give_default_loadout()


## The player's inventory persists itself: SaveSystem provider "weapons" (get_save_data /
## load_save_data below). A save that was loaded before the player existed is applied right here.
func _register_save_provider() -> void:
	if _save_registered:
		return
	_save_registered = true
	SaveSystem.register_provider(SAVE_KEY, self)


func _announce() -> void:
	if not is_inside_tree():
		return
	EventBus.weapon_inventory_changed.emit()
	EventBus.weapon_equipped.emit(current_id)
	_emit_ammo()


# =================================================================================================
# ownership / ammo
# =================================================================================================

## Add a weapon (or, when already owned, its ammo). ammo < 0 grants the spec's default amount.
## Total rounds are split into a full magazine (new weapons only) and the reserve pool.
func give_weapon(id: String, ammo: int = -1) -> bool:
	var base := _base_spec(id)
	if base == null:
		push_warning("WeaponInventory.give_weapon: unknown weapon '%s'" % id)
		return false
	var is_new := not _owned.has(id)
	if is_new:
		_owned[id] = {"in_mag": 0, "attachments": []}
	var rounds := base.default_ammo if ammo < 0 else ammo
	if base.uses_ammo() and rounds > 0:
		if is_new and base.uses_magazine():
			var loaded := mini(rounds, get_spec(id).mag_size)
			_owned[id]["in_mag"] = loaded
			rounds -= loaded
		_ammo[base.ammo_type] = mini(int(_ammo.get(base.ammo_type, 0)) + rounds, base.get_ammo_max())
	_emit_changed()
	return true


func remove_weapon(id: String) -> bool:
	if id == UNARMED or not _owned.has(id):
		return false
	if current_id == id:
		equip(UNARMED)
	_owned.erase(id)
	_spec_cache.erase(id)
	if _last_weapon == id:
		_last_weapon = ""
	for slot: String in _slot_memory.keys():
		if _slot_memory[slot] == id:
			_slot_memory.erase(slot)
	_emit_changed()
	return true


## Drop everything except the fists (keep_ammo = false also empties the reserve pools).
func clear(keep_ammo: bool = false) -> void:
	equip(UNARMED)
	for id: String in _owned.keys():
		if id != UNARMED:
			_owned.erase(id)
	_spec_cache.clear()
	_slot_memory.clear()
	_last_weapon = ""
	if not keep_ammo:
		_ammo.clear()
	_emit_changed()


func has_weapon(id: String) -> bool:
	return _owned.has(id)


## Owned weapon ids in wheel order.
func get_weapons() -> Array:
	var out: Array = _owned.keys()
	out.sort_custom(_order_less)
	return out


## Owned weapons of one wheel slot (name or index 1..8), in wheel order.
func get_slot_weapons(slot: Variant) -> Array:
	var slot_name := _slot_name(slot)
	var out: Array = []
	for id: String in get_weapons():
		var s := _base_spec(id)
		if s != null and s.slot == slot_name:
			out.append(id)
	return out


## For the weapon wheel UI: 8 entries {slot, index, weapons: Array, selected: String}.
func get_wheel_data() -> Array:
	var out: Array = []
	var cur := _base_spec(current_id)
	for i in WeaponSpec.SLOTS.size():
		var slot_name: String = WeaponSpec.SLOTS[i]
		var list := get_slot_weapons(slot_name)
		var selected := ""
		if cur != null and cur.slot == slot_name:
			selected = current_id
		elif list.has(str(_slot_memory.get(slot_name, ""))):
			selected = str(_slot_memory[slot_name])
		elif not list.is_empty():
			selected = str(list[0])
		out.append({"slot": slot_name, "index": i + 1, "weapons": list, "selected": selected})
	return out


## Add reserve ammo. Accepts an ammo type or a weapon id. Returns how many rounds were added.
func add_ammo(ammo_type: String, n: int) -> int:
	var type := ammo_type
	if not WeaponSpec.AMMO_MAX.has(type):
		var s := _base_spec(ammo_type)
		if s == null or not s.uses_ammo():
			return 0
		type = s.ammo_type
	var before := int(_ammo.get(type, 0))
	var after := clampi(before + n, 0, int(WeaponSpec.AMMO_MAX[type]))
	if after == before:
		return 0
	_ammo[type] = after
	_emit_changed()
	return after - before


func get_reserve(ammo_type: String) -> int:
	return int(_ammo.get(ammo_type, 0))


## True when the reserve pool of that ammo type (or of that weapon's type) is at its cap.
func is_ammo_full(ammo_type: String) -> bool:
	var type := ammo_type
	if not WeaponSpec.AMMO_MAX.has(type):
		var s := _base_spec(ammo_type)
		if s == null or not s.uses_ammo():
			return true
		type = s.ammo_type
	return int(_ammo.get(type, 0)) >= int(WeaponSpec.AMMO_MAX[type])


## {in_mag, reserve, mag_size, ammo_type}. Melee: in_mag = reserve = -1 (HUD hides the counter).
## Thrown weapons have no magazine: in_mag = pieces left, reserve = 0.
func get_ammo(id: String) -> Dictionary:
	var spec := get_spec(id)
	if spec == null or not spec.uses_ammo():
		return {"in_mag": -1, "reserve": -1, "mag_size": 0, "ammo_type": ""}
	var pool := int(_ammo.get(spec.ammo_type, 0))
	if not spec.uses_magazine():
		return {"in_mag": pool, "reserve": 0, "mag_size": 0, "ammo_type": spec.ammo_type}
	var in_mag := int(_owned[id]["in_mag"]) if _owned.has(id) else 0
	return {"in_mag": in_mag, "reserve": pool, "mag_size": spec.mag_size, "ammo_type": spec.ammo_type}


## Full magazines and full reserve pools for everything that is owned.
func refill_all() -> void:
	for id: String in _owned:
		var spec := get_spec(id)
		if spec == null or not spec.uses_ammo():
			continue
		if spec.uses_magazine():
			_owned[id]["in_mag"] = spec.mag_size
		_ammo[spec.ammo_type] = spec.get_ammo_max()
	_emit_changed()


## Admin helper: every registered weapon with full ammo.
func give_all_weapons() -> void:
	for id: Variant in Registry.ids("weapons"):
		give_weapon(str(id))
	refill_all()


# =================================================================================================
# selection
# =================================================================================================

## Effective spec (attachments applied) of the equipped weapon, or null.
func get_current_spec() -> WeaponSpec:
	if current_id == "":
		return null
	return get_spec(current_id)


## Effective spec of an owned weapon; the registry spec for anything else; null if unknown.
func get_spec(id: String) -> WeaponSpec:
	if _spec_cache.has(id):
		return _spec_cache[id]
	var base := _base_spec(id)
	if base == null:
		return null
	if not _owned.has(id):
		return base
	var eff := base.with_attachments(_owned[id]["attachments"])
	_spec_cache[id] = eff
	return eff


func is_armed() -> bool:
	return current_id != "" and current_id != UNARMED


## Animator pose for the equipped weapon ("none" when unarmed).
func get_weapon_pose() -> String:
	var spec := get_current_spec()
	return spec.weapon_pose if spec != null else "none"


func equip(id: String) -> bool:
	if not _owned.has(id):
		return false
	var spec := get_spec(id)
	if spec == null:
		return false
	if id == current_id:
		return true
	if spec.is_thrown() and get_reserve(spec.ammo_type) <= 0:
		return false
	if id != UNARMED and _vehicle() != null and not spec.drive_by:
		return false
	_cancel_actions()
	if current_id != "" and current_id != UNARMED:
		_last_weapon = current_id
	current_id = id
	_slot_memory[spec.slot] = id
	_equip_left = spec.equip_time
	_cooldown = 0.0
	_bloom = 0.0
	_burst = 0
	_refresh_model()
	if _is_player() and is_inside_tree():
		Audio.play("weapon_switch", -6.0, 1.0, "SFX")
	equipped.emit(id)
	if _is_player():
		EventBus.weapon_equipped.emit(id)
	_emit_ammo()
	return true


## Select a wheel slot (index 1..8 or slot name). Selecting the current slot again cycles
## through the weapons of that slot.
func equip_slot(slot: Variant) -> bool:
	var slot_name := _slot_name(slot)
	var list: Array = []
	for id: String in get_slot_weapons(slot_name):
		if _selectable(id):
			list.append(id)
	if list.is_empty():
		return false
	var cur := _base_spec(current_id)
	if cur != null and cur.slot == slot_name:
		var i := list.find(current_id)
		return equip(str(list[(i + 1) % list.size()]))
	var remembered := str(_slot_memory.get(slot_name, ""))
	if list.has(remembered):
		return equip(remembered)
	return equip(str(list[0]))


func next_weapon() -> bool:
	return _cycle(1)


func prev_weapon() -> bool:
	return _cycle(-1)


## Put the weapon away (fists). Called again while unarmed it draws the last weapon.
func holster() -> bool:
	if current_id != UNARMED:
		return equip(UNARMED)
	if _last_weapon != "" and _owned.has(_last_weapon):
		return equip(_last_weapon)
	return false


## Drive-by rule: handguns, the compact SMG and thrown weapons may be used from a seat.
## "fists" (= unarmed / holstered) is always allowed in a seat, it just cannot attack there.
func can_use_in_vehicle(id: String) -> bool:
	if id == UNARMED:
		return true
	var spec := _base_spec(id)
	return spec != null and spec.drive_by


# =================================================================================================
# trigger / firing
# =================================================================================================

func trigger_pressed() -> void:
	if _holder_dead():
		return
	trigger_held = true
	var spec := get_current_spec()
	if spec == null:
		return
	match spec.fire_mode:
		"melee":
			melee_attack(false)
		"thrown":
			_start_cook()
		_:
			if not _try_fire():
				_shot_buffer = SHOT_BUFFER


func trigger_released() -> void:
	trigger_held = false
	# the shot buffer is NOT cleared here: a quick tap that came a moment too early (still
	# cycling / drawing) must fire as soon as the weapon is ready, even if the finger is already
	# off the trigger. It runs out by itself after SHOT_BUFFER seconds.
	if _cooking:
		_release_throw()


func set_aiming(on: bool) -> void:
	if is_aiming == on:
		return
	is_aiming = on
	aiming_changed.emit(on)


## Camera FOV to use while aiming with the equipped weapon (scope attachment included).
func get_aim_fov() -> float:
	var spec := get_current_spec()
	return spec.aim_fov if spec != null else 60.0


## True while the full scope overlay should be shown.
func is_scoped() -> bool:
	var spec := get_current_spec()
	return spec != null and spec.scoped and is_aiming and not is_reloading and _equip_left <= 0.0


## Current cone half-angle in degrees (crosshair size / the value used for the next shot).
func get_current_spread() -> float:
	var spec := get_current_spec()
	if spec == null or not spec.is_firearm():
		return 0.0
	var s := spec.spread_base + _bloom + spec.spread_moving * _move_factor()
	if is_aiming:
		s *= spec.spread_aim_mult
	if _crouching():
		s *= CROUCH_SPREAD_MULT
	if _vehicle() != null:
		s *= DRIVE_BY_SPREAD_MULT
	return s


## True when a trigger pull would fire right now.
func can_fire() -> bool:
	var spec := get_current_spec()
	if spec == null or not spec.is_firearm() or not _owned.has(current_id):
		return false
	if _equip_left > 0.0 or _cooldown > 0.0 or is_reloading or _melee_left > 0.0:
		return false
	if _vehicle() != null and not spec.drive_by:
		return false
	return int(_owned[current_id]["in_mag"]) > 0


func reload() -> bool:
	var spec := get_current_spec()
	if spec == null or not spec.uses_magazine() or is_reloading or not _owned.has(current_id):
		return false
	if _melee_left > 0.0 or _equip_left > 0.0:
		return false
	if int(_owned[current_id]["in_mag"]) >= spec.mag_size or get_reserve(spec.ammo_type) <= 0:
		return false
	var duration := spec.reload_time
	if _is_player():
		duration *= Skills.get_multiplier("shooting", 1.08, 0.8)
	is_reloading = true
	_reload_left = duration
	_reload_total = duration
	_auto_reload_in = 0.0
	_shot_buffer = 0.0
	if is_inside_tree():
		Audio.play_at(spec.sound_reload, _sound_position(), -3.0, 1.0, 30.0, "Weapons")
	_owner_action("reload", duration)
	reload_started.emit(current_id, duration)
	if _is_player():
		EventBus.weapon_reload_started.emit(current_id, duration)
	return true


## 0..1 while reloading, 1 otherwise.
func get_reload_progress() -> float:
	if not is_reloading or _reload_total <= 0.0:
		return 1.0
	return clampf(1.0 - _reload_left / _reload_total, 0.0, 1.0)


func is_busy() -> bool:
	return is_reloading or _equip_left > 0.0 or _melee_left > 0.0 or _cooking or _quick_throw_in > 0.0


# =================================================================================================
# melee
# =================================================================================================

## Light attack (chains into a 3-hit combo; the finisher hits harder and can knock down) or a
## slow heavy attack. With a firearm in hand it becomes a weapon bash. Returns true if started.
func melee_attack(heavy: bool = false) -> bool:
	if _melee_left > 0.0:
		_melee_queued = 2 if heavy else 1
		return false
	if _vehicle() != null or _cooking or current_id == "" or _holder_dead():
		return false
	var spec := get_current_spec()
	if spec == null or spec.is_thrown():
		return false
	if is_reloading:
		_cancel_reload()
	var rpm := spec.rpm if spec.is_melee() else 95.0
	var duration := 60.0 / maxf(rpm, 1.0) * (1.7 if heavy else 1.0)
	if heavy or _combo_timer <= 0.0:
		_combo_step = 1
	else:
		_combo_step = (_combo_step % COMBO_STEPS) + 1
	_melee_heavy = heavy
	_melee_left = duration
	_melee_hit_in = duration * (0.5 if heavy else 0.35)
	_melee_pending = true
	_melee_queued = 0
	_combo_timer = 0.0
	if is_inside_tree():
		Audio.play_at("melee_swing", _sound_position(), -5.0, 0.85 if heavy else randf_range(0.95, 1.1), 25.0, "SFX")
	var action := "heavy"
	if not heavy:
		action = "punch_l" if _combo_step == 2 else ("kick" if (_combo_step == COMBO_STEPS and current_id == UNARMED) else "punch_r")
	_owner_action(action, duration)
	melee_started.emit(current_id, heavy, _combo_step)
	return true


func get_combo_step() -> int:
	return _combo_step


func _do_melee_hit() -> void:
	var spec := get_current_spec()
	if spec == null or not (holder is Node3D) or not is_instance_valid(holder) or _holder_dead():
		return
	var is_melee := spec.is_melee()
	var dmg := spec.damage if is_melee else BASH_DAMAGE
	var reach := spec.melee_range if is_melee else BASH_RANGE
	var finisher := not _melee_heavy and _combo_step == COMBO_STEPS
	var knock_chance := spec.melee_knockdown if is_melee else 0.25
	if _melee_heavy:
		dmg *= spec.melee_heavy_mult if is_melee else 1.6
		knock_chance = minf(knock_chance + 0.3, 1.0)
	elif finisher:
		dmg *= COMBO_FINISHER_MULT
	if _is_player():
		dmg *= Skills.get_multiplier("strength", 0.9, 1.35)
	var knock := (_melee_heavy or finisher) and randf() < knock_chance
	var origin := (holder as Node3D).global_position + Vector3.UP * (0.9 if _crouching() else 1.25)
	var hits := Combat.melee_sweep(holder, origin, _facing_dir(), reach, dmg, {
		"weapon_id": current_id, "impulse": (spec.impulse if is_melee else 3.0) * (1.8 if _melee_heavy else 1.0),
		"knockdown": knock, "heavy": _melee_heavy, "max_targets": 2 if _melee_heavy else 1,
		"sound_hit": spec.melee_sound_hit if is_melee else "melee_hit",
		"vehicle_mult": spec.vehicle_damage_mult if is_melee else 0.5,
	})
	if not hits.is_empty() and _is_player():
		Fx.shake_camera(0.08 if _melee_heavy else 0.04)
	melee_landed.emit(current_id, hits)


# =================================================================================================
# thrown weapons
# =================================================================================================

## Quick throw without switching weapons: a grenade if there is one, otherwise a fire bottle.
func throw_grenade() -> bool:
	if _throw_cd > 0.0 or _cooking or _quick_throw_in > 0.0 or _melee_left > 0.0 or _holder_dead():
		return false
	var pick := ""
	for id: String in ["grenade", "molotov"]:
		var s := _base_spec(id)
		if s != null and _owned.has(id) and get_reserve(s.ammo_type) > 0:
			if _vehicle() == null or s.drive_by:
				pick = id
				break
	if pick == "":
		return false
	_quick_throw_id = pick
	_quick_throw_in = QUICK_THROW_WINDUP
	_throw_cd = THROW_COOLDOWN
	_owner_action("throw", 0.55)
	throw_started.emit(pick)
	return true


func is_cooking() -> bool:
	return _cooking


## Lets the held throwable (grenade / fire bottle) fall instead of throwing it: a cooking one keeps its
## remaining fuse, otherwise a fresh one (full fuse) is taken from the reserve. It leaves from the
## holder's shoot origin along `dir` (ZERO = straight down) at DROP_SPEED_SCALE of the throw speed plus
## the holder's velocity. Used for drive-by drops out of a window; also usable by AI / blind fire.
## Returns true when something left the hand.
func drop_throwable(dir: Vector3 = Vector3.ZERO) -> bool:
	var spec := get_current_spec()
	if spec == null or not spec.is_thrown() or _holder_dead() or _equip_left > 0.0:
		return false
	if not _cooking and _throw_cd > 0.0:
		return false
	if get_reserve(spec.ammo_type) <= 0:
		_cooking = false
		return false
	if _vehicle() != null and not spec.drive_by:
		return false
	var fuse := -1.0
	if spec.projectile_kind == "grenade":
		fuse = maxf(float(Projectile.KINDS["grenade"]["fuse"]) - (_cook_t if _cooking else 0.0), 0.25)
	_cooking = false
	_throw_cd = 60.0 / maxf(spec.rpm, 1.0)
	throw_started.emit(current_id)
	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.DOWN
	_do_throw(current_id, fuse, DROP_SPEED_SCALE, d)
	return true


func _start_cook() -> void:
	var spec := get_current_spec()
	if spec == null or not spec.is_thrown() or _cooking or _throw_cd > 0.0 or _equip_left > 0.0 or _holder_dead():
		return
	if get_reserve(spec.ammo_type) <= 0:
		return
	if _vehicle() != null and not spec.drive_by:
		return
	_cooking = true
	_cook_t = 0.0
	if spec.projectile_kind == "grenade" and is_inside_tree():
		Audio.play_at("pin_pull", _sound_position(), -4.0, 1.0, 15.0, "SFX")
	throw_started.emit(current_id)


## `drop` = the holder went down with a live one in the hand: it falls at the feet instead.
func _release_throw(drop: bool = false) -> void:
	if not _cooking:
		return
	_cooking = false
	var spec := get_current_spec()
	if spec == null or not spec.is_thrown():
		return
	var fuse := -1.0
	if spec.projectile_kind == "grenade":
		fuse = maxf(float(Projectile.KINDS["grenade"]["fuse"]) - _cook_t, 0.25)
	_throw_cd = 60.0 / maxf(spec.rpm, 1.0)
	if not drop:
		_owner_action("throw", 0.5)
	_do_throw(current_id, fuse, DROP_SPEED_SCALE if drop else 1.0)


## `dir_override` (drop_throwable): leave along this direction from the shoot origin, no lob.
func _do_throw(id: String, fuse: float, speed_scale: float = 1.0, dir_override: Vector3 = Vector3.ZERO) -> void:
	var spec := get_spec(id)
	if spec == null or get_reserve(spec.ammo_type) <= 0:
		return
	var ray := _aim_ray()
	var dir: Vector3 = ray["direction"]
	var throw_dir := (dir + Vector3.UP * THROW_UP_BIAS).normalized()
	var from := _shoot_origin()
	var side := dir.cross(Vector3.UP)
	if side.length_squared() > 0.001:
		side = side.normalized()
	var origin := _clear_point(from, from + side * 0.25 + dir * 0.55 + Vector3.UP * 0.05)
	if dir_override != Vector3.ZERO:
		throw_dir = dir_override
		origin = _clear_point(from, from + dir_override * 0.25)
	var opts := {"inherit_velocity": _holder_velocity() * 0.6, "muzzle": origin}
	if fuse > 0.0:
		opts["fuse"] = fuse
	if speed_scale != 1.0:
		opts["speed"] = spec.projectile_speed * speed_scale
	var node := Combat.launch(spec, origin, throw_dir, holder, opts)
	if not infinite_ammo:
		_ammo[spec.ammo_type] = maxi(get_reserve(spec.ammo_type) - 1, 0)
	thrown.emit(id, node)
	_emit_changed()
	# out of throwables: go back to what was in hand before
	if current_id == id and get_reserve(spec.ammo_type) <= 0:
		if _last_weapon != "" and _owned.has(_last_weapon) and _last_weapon != id and _selectable(_last_weapon):
			equip(_last_weapon)
		else:
			equip(UNARMED)


# =================================================================================================
# attachments
# =================================================================================================

func can_attach(weapon_id: String, att_id: String) -> bool:
	var base := _base_spec(weapon_id)
	return base != null and base.attachments.has(att_id) and Registry.has_def("attachments", att_id)


## Install an attachment on an owned weapon. One per kind: a new one replaces the old one.
func add_attachment(weapon_id: String, att_id: String) -> bool:
	if not _owned.has(weapon_id) or not can_attach(weapon_id, att_id):
		return false
	var list: Array = _owned[weapon_id]["attachments"]
	if list.has(att_id):
		return true
	var def := Registry.get_def("attachments", att_id) as AttachmentSpec
	for other: Variant in list.duplicate():
		var od := Registry.get_def("attachments", str(other)) as AttachmentSpec
		if od != null and def != null and od.kind == def.kind:
			list.erase(other)
	list.append(att_id)
	_attachments_changed(weapon_id)
	return true


func remove_attachment(weapon_id: String, att_id: String) -> bool:
	if not _owned.has(weapon_id):
		return false
	var list: Array = _owned[weapon_id]["attachments"]
	if not list.has(att_id):
		return false
	list.erase(att_id)
	_attachments_changed(weapon_id)
	return true


func has_attachment(weapon_id: String, att_id: String) -> bool:
	return _owned.has(weapon_id) and (_owned[weapon_id]["attachments"] as Array).has(att_id)


func get_attachments(weapon_id: String) -> Array:
	if not _owned.has(weapon_id):
		return []
	return (_owned[weapon_id]["attachments"] as Array).duplicate()


## Attachment ids the weapon accepts (from its spec), whether owned or not.
func get_compatible_attachments(weapon_id: String) -> Array:
	var base := _base_spec(weapon_id)
	return base.attachments.duplicate() if base != null else []


func has_flashlight() -> bool:
	for att_id: Variant in get_attachments(current_id):
		var def := Registry.get_def("attachments", str(att_id)) as AttachmentSpec
		if def != null and def.is_light:
			return true
	return false


## Toggle the weapon light (needs the flashlight attachment on the equipped weapon).
func toggle_flashlight() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_light_toggle_msec < 150:
		return flashlight_on
	_last_light_toggle_msec = now
	if not has_flashlight():
		return false
	set_flashlight(not flashlight_on)
	return flashlight_on


func set_flashlight(on: bool) -> void:
	flashlight_on = on
	_light_state = -1
	if is_inside_tree() and _is_player():
		Audio.play("ui_click", -8.0, 1.3, "SFX")


func _attachments_changed(weapon_id: String) -> void:
	_spec_cache.erase(weapon_id)
	var spec := get_spec(weapon_id)
	# a smaller magazine hands the surplus back to the reserve
	if spec != null and spec.uses_magazine():
		var in_mag := int(_owned[weapon_id]["in_mag"])
		if in_mag > spec.mag_size:
			_owned[weapon_id]["in_mag"] = spec.mag_size
			_ammo[spec.ammo_type] = mini(get_reserve(spec.ammo_type) + in_mag - spec.mag_size, spec.get_ammo_max())
	if weapon_id == current_id:
		if model != null and is_instance_valid(model):
			model.spec = spec
			model.set_attachments(get_attachments(weapon_id))
		_light_state = -1
	_emit_changed()


# =================================================================================================
# persistence
# =================================================================================================

func get_save_data() -> Dictionary:
	var weapons: Dictionary = {}
	for id: String in _owned:
		weapons[id] = {"in_mag": int(_owned[id]["in_mag"]), "attachments": (_owned[id]["attachments"] as Array).duplicate()}
	return {"weapons": weapons, "ammo": _ammo.duplicate(), "current": current_id, "version": 1}


func load_save_data(d: Dictionary) -> void:
	_loaded_from_save = true
	_cancel_actions()
	_owned.clear()
	_ammo.clear()
	_spec_cache.clear()
	_slot_memory.clear()
	_last_weapon = ""
	var weapons: Variant = d.get("weapons", {})
	if weapons is Dictionary:
		for id: Variant in weapons:
			var sid := str(id)
			if _base_spec(sid) == null or not (weapons[id] is Dictionary):
				continue
			var entry: Dictionary = weapons[id]
			var atts: Array = []
			var saved_atts: Variant = entry.get("attachments", [])
			if saved_atts is Array:
				for a: Variant in saved_atts:
					if can_attach(sid, str(a)) and not atts.has(str(a)):
						atts.append(str(a))
			_owned[sid] = {"in_mag": 0, "attachments": atts}
			var spec := get_spec(sid)
			_owned[sid]["in_mag"] = clampi(int(entry.get("in_mag", 0)), 0, spec.mag_size if spec.uses_magazine() else 0)
	if not _owned.has(UNARMED) and _base_spec(UNARMED) != null:
		_owned[UNARMED] = {"in_mag": 0, "attachments": []}
	var ammo: Variant = d.get("ammo", {})
	if ammo is Dictionary:
		for type: Variant in ammo:
			if WeaponSpec.AMMO_MAX.has(str(type)):
				_ammo[str(type)] = clampi(int(ammo[type]), 0, int(WeaponSpec.AMMO_MAX[str(type)]))
	var want := str(d.get("current", UNARMED))
	current_id = ""
	if not (_owned.has(want) and equip(want)):
		if _owned.has(UNARMED):
			current_id = UNARMED
			_refresh_model()
			equipped.emit(current_id)
			if _is_player():
				EventBus.weapon_equipped.emit(current_id)
	_equip_left = 0.0
	_emit_changed()


## After death / arrest: stop everything, put the weapon away. keep_weapons = false strips the
## inventory down to the default loadout.
func reset_for_respawn(keep_weapons: bool = true) -> void:
	_cancel_actions()
	trigger_held = false
	set_aiming(false)
	if not keep_weapons:
		clear()
		give_default_loadout()
	equip(UNARMED)


# =================================================================================================
# frame update
# =================================================================================================

func _unhandled_input(event: InputEvent) -> void:
	if handle_flashlight_input and event.is_action_pressed("weapon_flashlight") and _is_player() \
			and not Game.is_input_locked():
		toggle_flashlight()


func _physics_process(delta: float) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	if not _default_checked:
		_default_frames += 1
		_check_default_loadout()
		if _default_frames > 180:
			_default_checked = true
	# a dead holder does nothing: no shots, no swings, no reloads until it is alive again
	var dead := _holder_dead()
	if dead != _holder_was_dead:
		_holder_was_dead = dead
		if dead:
			_on_holder_died()
	if dead:
		return
	_update_vehicle_state()

	_cooldown = maxf(_cooldown - delta, -delta)
	if _equip_left > 0.0:
		_equip_left -= delta
	if _dry_cd > 0.0:
		_dry_cd -= delta
	if _throw_cd > 0.0:
		_throw_cd -= delta

	var spec := get_current_spec()
	if _bloom_hold > 0.0:
		_bloom_hold -= delta
	elif _bloom > 0.0 and spec != null:
		_bloom = maxf(_bloom - spec.spread_recovery * delta, 0.0)
	if _burst_reset > 0.0:
		_burst_reset -= delta
		if _burst_reset <= 0.0:
			_burst = 0

	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	elif _auto_reload_in > 0.0:
		_auto_reload_in -= delta
		if _auto_reload_in <= 0.0:
			reload()

	if _melee_left > 0.0:
		_melee_left -= delta
		if _melee_pending:
			_melee_hit_in -= delta
			if _melee_hit_in <= 0.0:
				_melee_pending = false
				_do_melee_hit()
		if _melee_left <= 0.0:
			_combo_timer = COMBO_WINDOW
			if _melee_queued != 0:
				var heavy := _melee_queued == 2
				_melee_queued = 0
				melee_attack(heavy)
	elif _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_step = 0

	if _quick_throw_in > 0.0:
		_quick_throw_in -= delta
		if _quick_throw_in <= 0.0:
			_do_throw(_quick_throw_id, -1.0)
	if _cooking:
		_cook_t += delta
		if spec != null and spec.projectile_kind == "grenade" and _cook_t >= MAX_COOK:
			_release_throw()

	spec = get_current_spec()
	if spec != null:
		if spec.is_firearm():
			if trigger_held and spec.fire_mode == "auto":
				_shot_buffer = 0.0      # held automatic fire needs no buffer (and must not keep a stale one)
				_try_fire()
			elif _shot_buffer > 0.0:
				_shot_buffer -= delta
				if _try_fire():
					_shot_buffer = 0.0
		elif spec.is_melee() and trigger_held and _melee_left <= 0.0:
			melee_attack(false)

	_update_light()
	_attach_retry += 1
	if _attach_retry >= 30:
		_attach_retry = 0
		if model != null and is_instance_valid(model) and not model.attached_to_hand:
			model.attach_to_holder(holder)


# =================================================================================================
# internals
# =================================================================================================

func _try_fire() -> bool:
	var spec := get_current_spec()
	if spec == null or not spec.is_firearm() or not _owned.has(current_id):
		return false
	if _equip_left > 0.0 or _cooldown > 0.0 or is_reloading or _melee_left > 0.0 or _holder_dead():
		return false
	if _vehicle() != null and not spec.drive_by:
		return false
	var state: Dictionary = _owned[current_id]
	if int(state["in_mag"]) <= 0:
		_dry_fire(spec)
		return true
	_fire(spec, state)
	return true


func _dry_fire(spec: WeaponSpec) -> void:
	if _dry_cd <= 0.0:
		_dry_cd = 0.3
		if is_inside_tree():
			Audio.play_at("dry_fire", _sound_position(), -4.0, 1.0, 20.0, "Weapons")
		dry_fired.emit(current_id)
	if get_reserve(spec.ammo_type) > 0 and not is_reloading and _auto_reload_in <= 0.0:
		_auto_reload_in = 0.12


func _fire(spec: WeaponSpec, state: Dictionary) -> void:
	var aim := _aim_solution(spec)
	var origin: Vector3 = aim["origin"]
	var dir: Vector3 = aim["direction"]
	var muzzle_pos := origin + dir * 0.6
	var muzzle_node: Node3D = null
	var eject_node: Node3D = null
	if model != null and is_instance_valid(model) and model.is_inside_tree():
		muzzle_node = model.muzzle
		eject_node = model.eject
		if model.attached_to_hand or model.has_model():
			muzzle_pos = model.get_muzzle_position()
	var result: Dictionary
	if spec.is_launcher():
		var start := _clear_point(origin, origin + dir * 0.9)
		var node := Combat.launch(spec, start, dir, holder, {
			"spread_deg": get_current_spread(), "muzzle": muzzle_pos, "muzzle_node": muzzle_node,
			"eject_node": eject_node,
		})
		result = {"hit": false, "hits": [], "projectile": node}
	else:
		result = Combat.fire_hitscan(origin, dir, spec, holder, {
			"spread_deg": get_current_spread(), "muzzle": muzzle_pos, "muzzle_node": muzzle_node,
			"eject_node": eject_node,
		})
	if not infinite_ammo:
		state["in_mag"] = int(state["in_mag"]) - 1
	_cooldown += spec.get_fire_interval()
	_bloom = minf(_bloom + spec.spread_bloom, maxf(spec.spread_max - spec.spread_base, 0.0))
	_bloom_hold = minf(spec.get_fire_interval() + 0.06, 0.25)
	_burst += 1
	_burst_reset = spec.get_fire_interval() + 0.28
	_apply_recoil(spec)
	_owner_action("fire", 0.0)
	_update_model_mag()
	fired.emit(current_id, result)
	_emit_ammo()
	if int(state["in_mag"]) <= 0 and get_reserve(spec.ammo_type) > 0:
		_auto_reload_in = AUTO_RELOAD_DELAY + minf(spec.get_fire_interval() * 0.5, 0.35)


func _apply_recoil(spec: WeaponSpec) -> void:
	var k := 1.0
	if _is_player():
		k *= Skills.get_multiplier("shooting", 1.1, 0.75)
	if is_aiming:
		k *= 0.8
	if _crouching():
		k *= 0.85
	if _vehicle() != null:
		k *= 1.25
	if _burst <= 1:
		_recoil_phase = randf() * TAU
	var climb := 1.0 + minf(float(_burst - 1), 8.0) * 0.05
	# degrees, like WeaponSpec.recoil_pitch / recoil_yaw (the Player's camera rig expects degrees)
	var pitch := spec.recoil_pitch * climb * k
	var yaw := (sin(float(_burst) * 1.3 + _recoil_phase) * 0.6 + randf_range(-0.4, 0.4)) * spec.recoil_yaw * k
	if holder != null and is_instance_valid(holder) and holder.has_method("add_recoil"):
		holder.call("add_recoil", pitch, yaw)
	recoil_kicked.emit(pitch, yaw)


func _finish_reload() -> void:
	is_reloading = false
	_reload_left = 0.0
	var spec := get_current_spec()
	if spec == null or not _owned.has(current_id) or not spec.uses_magazine():
		return
	var state: Dictionary = _owned[current_id]
	var need := spec.mag_size - int(state["in_mag"])
	var take := mini(need, get_reserve(spec.ammo_type))
	if infinite_ammo:
		take = need
	else:
		_ammo[spec.ammo_type] = get_reserve(spec.ammo_type) - take
	state["in_mag"] = int(state["in_mag"]) + take
	_update_model_mag()
	reload_finished.emit(current_id)
	_emit_changed()


func _cancel_reload() -> void:
	is_reloading = false
	_reload_left = 0.0
	_auto_reload_in = 0.0


func _cancel_actions() -> void:
	_cancel_reload()
	_cooking = false
	_cook_t = 0.0
	_shot_buffer = 0.0
	_melee_left = 0.0
	_melee_pending = false
	_melee_queued = 0
	_combo_step = 0
	_combo_timer = 0.0
	_quick_throw_in = 0.0


func _cycle(step: int) -> bool:
	var list: Array = []
	for id: String in get_weapons():
		if _selectable(id):
			list.append(id)
	if list.size() <= 1:
		return false
	var i := list.find(current_id)
	if i < 0:
		i = 0
	return equip(str(list[posmod(i + step, list.size())]))


func _selectable(id: String) -> bool:
	var spec := _base_spec(id)
	if spec == null or not _owned.has(id):
		return false
	if spec.is_thrown() and get_reserve(spec.ammo_type) <= 0:
		return false
	if id != UNARMED and _vehicle() != null and not spec.drive_by:
		return false
	return true


func _update_vehicle_state() -> void:
	var inside := _vehicle() != null
	if inside == _was_in_vehicle:
		return
	_was_in_vehicle = inside
	if inside:
		_cancel_actions()
		if current_id != UNARMED and not can_use_in_vehicle(current_id):
			_pre_vehicle_weapon = current_id
			var alt := _best_drive_by()
			_force_equip(alt if alt != "" else UNARMED)
	else:
		if _pre_vehicle_weapon != "" and _owned.has(_pre_vehicle_weapon):
			equip(_pre_vehicle_weapon)
		_pre_vehicle_weapon = ""


func _force_equip(id: String) -> void:
	if not equip(id):
		equip(UNARMED)


func _best_drive_by() -> String:
	var best := ""
	var best_dps := -1.0
	for id: String in _owned:
		var spec := get_spec(id)
		if spec == null or not spec.drive_by or not spec.is_firearm():
			continue
		var a := get_ammo(id)
		if int(a["in_mag"]) + int(a["reserve"]) <= 0:
			continue
		if spec.get_dps() > best_dps:
			best_dps = spec.get_dps()
			best = id
	return best


func _refresh_model() -> void:
	if model != null and is_instance_valid(model):
		model.queue_free()
	model = null
	_light_state = -1
	var spec := get_current_spec()
	if spec == null or spec.model_path == "" or not (holder is Node3D) or not is_instance_valid(holder):
		return
	if not (holder as Node3D).is_inside_tree():
		return
	model = WeaponModel.create(spec, get_attachments(current_id))
	model.attach_to_holder(holder)
	_update_model_mag()


func _update_model_mag() -> void:
	if model == null or not is_instance_valid(model) or model.spec == null or not model.spec.hide_mag_when_empty:
		return
	model.set_mag_loaded(_owned.has(current_id) and int(_owned[current_id]["in_mag"]) > 0)


func _update_light() -> void:
	if model == null or not is_instance_valid(model) or not model.has_light():
		return
	var state := 0
	if flashlight_on:
		state = 2 if is_aiming else 1
	if state == _light_state:
		return
	_light_state = state
	model.set_light_on(state > 0, 1.0 if state == 2 else 0.6)


## Crosshair ray from the holder (camera). Falls back to the holder's forward at eye height.
func _aim_ray() -> Dictionary:
	if holder != null and is_instance_valid(holder) and holder.has_method("get_aim_ray"):
		var r: Variant = holder.call("get_aim_ray")
		if r is Dictionary and (r as Dictionary).has("origin") and (r as Dictionary).has("direction"):
			var d: Vector3 = r["direction"]
			if d.length_squared() > 0.0001:
				return {"origin": r["origin"], "direction": d.normalized()}
	if holder is Node3D:
		var h := holder as Node3D
		return {"origin": h.global_position + Vector3.UP * EYE_HEIGHT, "direction": _facing_dir()}
	return {"origin": Vector3.ZERO, "direction": Vector3.FORWARD}


## Where bullets leave from: the holder's own answer (get_shoot_origin hook: drive-by window, blind fire
## over cover ...) or the holder's head height (inside its own, excluded, collider).
func _shoot_origin() -> Vector3:
	if not (holder is Node3D) or not is_instance_valid(holder):
		return _aim_ray()["origin"]
	var h := holder as Node3D
	if h.has_method("get_shoot_origin"):
		var so: Variant = h.call("get_shoot_origin")
		if so is Vector3 and (so as Vector3).is_finite():
			return so as Vector3
	if _vehicle() != null and h.has_method("get_target_position"):
		var v: Variant = h.call("get_target_position")
		if v is Vector3:
			return (v as Vector3) + Vector3.UP * 0.3
	return h.global_position + Vector3.UP * (EYE_HEIGHT_CROUCHED if _crouching() else EYE_HEIGHT)


## Third-person aim: find the point under the crosshair, then shoot from the body towards it.
func _aim_solution(spec: WeaponSpec) -> Dictionary:
	var ray := _aim_ray()
	var cam_origin: Vector3 = ray["origin"]
	var cam_dir: Vector3 = ray["direction"]
	if not (holder is Node3D):
		return {"origin": cam_origin, "direction": cam_dir, "aim_point": cam_origin + cam_dir * spec.max_range}
	var from := _shoot_origin()
	var skip := maxf((from - cam_origin).dot(cam_dir), 0.0)
	var start := cam_origin + cam_dir * skip
	var far := start + cam_dir * spec.max_range
	var exclude: Array = [holder]
	var vehicle := _vehicle()
	if vehicle != null:
		exclude.append(vehicle)
	var hit := Combat.raycast(start, far, Layers.BULLET_MASK, exclude)
	var aim_point: Vector3 = far if hit.is_empty() else (hit["position"] as Vector3)
	var to := aim_point - from
	var dir := cam_dir
	if to.length() > 1.2 and to.normalized().dot(cam_dir) > 0.5:
		dir = to.normalized()
	return {"origin": from, "direction": dir, "aim_point": aim_point}


## `wanted` if nothing solid lies between `from` and it, otherwise a point just short of the obstacle.
func _clear_point(from: Vector3, wanted: Vector3) -> Vector3:
	var hit := Combat.raycast(from, wanted, Layers.WORLD | Layers.VEHICLE | Layers.PROP | Layers.GLASS, [holder, _vehicle()])
	if hit.is_empty():
		return wanted
	var pos: Vector3 = hit["position"]
	return from.lerp(pos, 0.5)


func _facing_dir() -> Vector3:
	var node: Node3D = null
	if holder != null and is_instance_valid(holder):
		var visual: Variant = holder.get("visual")
		if visual != null and is_instance_valid(visual) and visual is Node3D and (visual as Node3D).is_inside_tree():
			node = visual as Node3D
		elif holder is Node3D:
			node = holder as Node3D
	if node == null:
		return Vector3.FORWARD
	var f := -node.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


func _vehicle() -> Node3D:
	if holder == null or not is_instance_valid(holder):
		return null
	var v: Variant = holder.get("current_vehicle")
	if v != null and is_instance_valid(v) and v is Node3D:
		return v as Node3D
	return null


## True while the holder reports `is_dead` (Player, NpcBase). Holders without that member never do.
func _holder_dead() -> bool:
	return holder != null and is_instance_valid(holder) and holder.get("is_dead") == true


## The holder just died: let go of everything. A grenade that was being cooked falls at the feet
## with whatever fuse it has left (it was live); a fire bottle breaks there.
func _on_holder_died() -> void:
	trigger_held = false
	if _cooking:
		_release_throw(true)
	_cancel_actions()
	set_aiming(false)


func _crouching() -> bool:
	return holder != null and is_instance_valid(holder) and holder.get("is_crouching") == true


func _holder_velocity() -> Vector3:
	var vehicle := _vehicle()
	if vehicle is RigidBody3D:
		return (vehicle as RigidBody3D).linear_velocity
	if holder != null and is_instance_valid(holder):
		var v: Variant = holder.get("velocity")
		if v is Vector3:
			return v
	return Vector3.ZERO


func _move_factor() -> float:
	var v := _holder_velocity()
	if _vehicle() != null:
		return clampf(v.length() / 25.0, 0.0, 1.0)
	v.y = 0.0
	return clampf(v.length() / RUN_SPEED, 0.0, 1.0)


func _sound_position() -> Vector3:
	if holder is Node3D and is_instance_valid(holder) and (holder as Node3D).is_inside_tree():
		return (holder as Node3D).global_position + Vector3.UP * 1.3
	return Vector3.ZERO


func _owner_action(action: String, duration: float) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	if holder.has_method("play_weapon_action"):
		holder.call("play_weapon_action", action, duration)
		return
	var anim: Variant = holder.get("animator")
	if anim != null and is_instance_valid(anim) and anim is Object and (anim as Object).has_method("play_action"):
		(anim as Object).call("play_action", action, duration)


func _is_player() -> bool:
	if emit_global_events >= 0:
		return emit_global_events == 1
	if holder == null or not is_instance_valid(holder):
		return false
	return holder.is_in_group("player") or holder == Game.player


func _base_spec(id: String) -> WeaponSpec:
	if id == "":
		return null
	return Registry.get_def("weapons", id) as WeaponSpec


func _slot_name(slot: Variant) -> String:
	if slot is int or slot is float:
		var i := int(slot) - 1
		if i >= 0 and i < WeaponSpec.SLOTS.size():
			return WeaponSpec.SLOTS[i]
		return ""
	return str(slot)


func _order_less(a: Variant, b: Variant) -> bool:
	return _order_key(str(a)) < _order_key(str(b))


func _order_key(id: String) -> int:
	var spec := _base_spec(id)
	var slot_i := spec.get_slot_index() if spec != null else 9
	var i := ORDER.find(id)
	return slot_i * 1000 + (i if i >= 0 else 500 + (hash(id) % 400))


func _emit_ammo() -> void:
	if not _is_player() or current_id == "":
		return
	var a := get_ammo(current_id)
	EventBus.ammo_changed.emit(current_id, int(a["in_mag"]), int(a["reserve"]))


func _emit_changed() -> void:
	changed.emit()
	if _is_player():
		EventBus.weapon_inventory_changed.emit()
		_emit_ammo()
