class_name WeaponSpec
extends Resource
## Data definition of one weapon (Registry kind "weapons").
##
## Every number that shapes how a weapon feels lives here, so balancing never touches logic.
## Specs are built in code by res://gta/resources/registries/weapons_registry.gd; a `.tres` in
## res://gta/resources/data/weapons/ with the same id would override the code definition.
##
## Units: metres, seconds, degrees (spread and recoil are HALF-angles / per-shot kicks in
## degrees), hit points (characters have 100 hp, cars about 1000 hp).
## See docs/WEAPONS.md for the balance table and for "how to add a weapon".

## Wheel slots in order (index 1..8).
const SLOTS: Array[String] = ["melee", "handgun", "smg", "shotgun", "rifle", "sniper", "heavy", "thrown"]
## semi   one shot per trigger pull            auto      fires while the trigger is held
## pump   one shot per pull, slow cycle        bolt      one shot per pull, very slow cycle
## melee  light attack on trigger              thrown    hold to cook, release to throw
## launcher  one projectile per pull
const FIRE_MODES: Array[String] = ["semi", "auto", "pump", "bolt", "melee", "thrown", "launcher"]
const AMMO_TYPES: Array[String] = ["pistol", "smg", "shotgun", "rifle", "sniper", "rocket",
		"grenade_round", "grenade", "molotov"]
## Reserve pool caps per ammo type.
const AMMO_MAX := {
	"pistol": 240, "smg": 480, "shotgun": 96, "rifle": 480, "sniper": 60, "rocket": 12,
	"grenade_round": 24, "grenade": 10, "molotov": 10,
}
const AMMO_NAMES := {
	"pistol": "Pistol rounds", "smg": "SMG rounds", "shotgun": "Shells", "rifle": "Rifle rounds",
	"sniper": "Sniper rounds", "rocket": "Rockets", "grenade_round": "Launcher grenades",
	"grenade": "Grenades", "molotov": "Fire bottles",
}
const MODEL_DIR := "res://gta/generated/models/weapons"

# --- identity ---------------------------------------------------------------------------------
@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var slot: String = "handgun"            ## one of SLOTS
@export var fire_mode: String = "semi"          ## one of FIRE_MODES

# --- damage / cadence -------------------------------------------------------------------------
@export var damage: float = 20.0                ## per pellet / per melee hit / explosion centre damage
@export var rpm: float = 300.0                  ## shots (or melee swings / throws) per minute
@export var pellets: int = 1
@export var headshot_mult: float = 2.0
@export var limb_mult: float = 0.8
@export var vehicle_damage_mult: float = 1.0    ## bullets against vehicles
@export var impulse: float = 2.0                ## physical push per hit (N*s)

# --- ammunition -------------------------------------------------------------------------------
@export var mag_size: int = 0                   ## 0 = no magazine (melee, thrown)
@export var ammo_type: String = ""              ## one of AMMO_TYPES, "" for melee
@export var default_ammo: int = 0               ## total rounds granted by give_weapon(id, -1)
@export var reload_time: float = 1.5
@export var equip_time: float = 0.35            ## draw time before the first shot

# --- spread (degrees, half-angle of the cone) ---------------------------------------------------
@export var spread_base: float = 1.0            ## standing still, hip fire
@export var spread_moving: float = 1.5          ## added at full run speed
@export var spread_bloom: float = 0.4           ## added per shot
@export var spread_max: float = 5.0             ## cap for base + bloom
@export var spread_recovery: float = 6.0        ## bloom removed per second
@export var spread_aim_mult: float = 0.55       ## multiplier while aiming

# --- recoil (degrees per shot) ----------------------------------------------------------------
@export var recoil_pitch: float = 1.0           ## upward kick
@export var recoil_yaw: float = 0.4             ## horizontal wander (+-)
@export var recoil_recovery: float = 8.0        ## deg/s the view settles back (advice for the camera rig)

# --- range --------------------------------------------------------------------------------------
@export var max_range: float = 80.0
@export var falloff_start: float = 20.0         ## full damage up to here
@export var falloff_end: float = 60.0           ## falloff_min from here on
@export var falloff_min: float = 0.5            ## damage multiplier at / beyond falloff_end
@export var penetration: float = 0.0            ## > 0: passes glass, light props and "thin" tagged colliders

# --- projectiles / thrown -----------------------------------------------------------------------
@export var projectile_kind: String = ""        ## "", "grenade", "rocket", "grenade_round", "molotov"
@export var projectile_speed: float = 0.0       ## m/s at launch
@export var blast_radius: float = 0.0

# --- melee --------------------------------------------------------------------------------------
@export var melee_range: float = 0.0
@export var melee_heavy_mult: float = 1.8       ## heavy attack damage multiplier
@export var melee_knockdown: float = 0.0        ## 0..1 chance that a combo finisher / heavy hit knocks down
@export var melee_sound_hit: String = "melee_hit"

# --- perception / presentation ------------------------------------------------------------------
@export var noise_radius: float = 70.0          ## metres AI can hear a shot
@export var suppressed: bool = false            ## set by the suppressor attachment
@export var weapon_pose: String = "pistol"      ## HumanoidAnimator.weapon_pose: none, pistol, rifle, melee, rpg, throw
@export var aim_fov: float = 50.0               ## camera FOV while aiming
@export var scoped: bool = false                ## full scope overlay while aiming
@export var scope_overlay_with_scope: bool = false  ## the "scope" attachment turns `scoped` on
@export var drive_by: bool = false              ## usable from a vehicle seat
@export var shake: float = 0.05                 ## camera trauma per shot (player only)
@export var tracer: bool = true
@export var eject_shells: bool = true           ## false: the cases stay in the weapon (revolver)
@export var sound_fire: String = ""
@export var sound_reload: String = "reload"

# --- economy ------------------------------------------------------------------------------------
@export var price: int = 0
@export var ammo_price: int = 0                 ## price of one ammo pack
@export var ammo_pack: int = 0                  ## rounds per pack

# --- model / hand ---------------------------------------------------------------------------------
@export var attachments: Array[String] = []     ## compatible AttachmentSpec ids
@export var builtin_nodes: Array[String] = []   ## Att_* meshes of the GLB that are always shown (sniper scope)
@export var optic_strength: float = 1.0         ## 0..1: how much of the "scope" attachment's zoom this weapon gets
@export var hide_mag_when_empty: bool = false   ## the Mag mesh is the loaded round (rocket): hidden while empty
@export var model_path: String = ""             ## GLB; "" = no model (fists)
## Fine tuning of the grip in the hand, in the weapon's own frame (x right, y up, -z barrel).
## See docs/WEAPONS.md "Hold-offset tuning".
@export var hold_offset: Vector3 = Vector3.ZERO
@export var hold_rotation: Vector3 = Vector3.ZERO   ## degrees (pitch x, yaw y, roll z)


## Accepts a WeaponSpec or a weapon id; returns the spec or null.
static func resolve(spec_or_id: Variant) -> WeaponSpec:
	if spec_or_id is WeaponSpec:
		return spec_or_id as WeaponSpec
	if spec_or_id is String or spec_or_id is StringName:
		var def: Variant = Registry.get_def("weapons", str(spec_or_id))
		if def is WeaponSpec:
			return def as WeaponSpec
	return null


static func slot_index_of(slot_name: String) -> int:
	return SLOTS.find(slot_name) + 1


func get_slot_index() -> int:
	return SLOTS.find(slot) + 1


func get_fire_interval() -> float:
	return 60.0 / maxf(rpm, 1.0)


func is_melee() -> bool:
	return fire_mode == "melee"


func is_thrown() -> bool:
	return fire_mode == "thrown"


func is_launcher() -> bool:
	return fire_mode == "launcher"


## Hitscan gun (semi / auto / pump / bolt).
func is_hitscan() -> bool:
	return fire_mode == "semi" or fire_mode == "auto" or fire_mode == "pump" or fire_mode == "bolt"


## Anything that is fired from a magazine (hitscan guns and launchers).
func is_firearm() -> bool:
	return is_hitscan() or is_launcher()


func uses_ammo() -> bool:
	return ammo_type != ""


func uses_magazine() -> bool:
	return mag_size > 0 and is_firearm()


func get_ammo_max() -> int:
	return int(AMMO_MAX.get(ammo_type, 0))


## Damage multiplier at a distance (range falloff).
func falloff_at(distance: float) -> float:
	if distance <= falloff_start or falloff_end <= falloff_start:
		return 1.0
	if distance >= falloff_end:
		return falloff_min
	return lerpf(1.0, falloff_min, (distance - falloff_start) / (falloff_end - falloff_start))


## Damage of one full shot (all pellets) to the torso at point blank.
func get_shot_damage() -> float:
	return damage * float(maxi(pellets, 1))


## Burst damage per second while the magazine lasts (torso, no falloff).
func get_dps() -> float:
	return get_shot_damage() * rpm / 60.0


## Damage per second including reloads (firearms only; equals get_dps() otherwise).
func get_sustained_dps() -> float:
	if not uses_magazine():
		return get_dps()
	var mag_time := float(mag_size - 1) * get_fire_interval() + reload_time
	return get_shot_damage() * float(mag_size) / maxf(mag_time, 0.01)


## Seconds to bring down a target with `hp` hit points (torso hits, every shot lands).
func get_time_to_kill(hp: float = 100.0) -> float:
	var shots := int(ceil(hp / maxf(get_shot_damage(), 0.01)))
	var t := float(shots - 1) * get_fire_interval()
	if uses_magazine() and shots > mag_size:
		t += floorf(float(shots - 1) / float(mag_size)) * reload_time
	return t


func get_shots_to_kill(hp: float = 100.0) -> int:
	return int(ceil(hp / maxf(get_shot_damage(), 0.01)))


## Returns a copy of this spec with the stat effects of the given attachments applied.
## `attachment_ids` may contain ids that are unknown or incompatible; those are ignored.
func with_attachments(attachment_ids: Array) -> WeaponSpec:
	if attachment_ids.is_empty():
		return self
	var out := duplicate() as WeaponSpec
	for att_id: Variant in attachment_ids:
		var def: Variant = Registry.get_def("attachments", str(att_id))
		if def is AttachmentSpec and attachments.has(str(att_id)):
			(def as AttachmentSpec).apply_to(out)
	return out


func describe() -> String:
	return "%s [%s/%s] dmg %.0fx%d rpm %.0f mag %d" % [id, slot, fire_mode, damage, pellets, rpm, mag_size]
