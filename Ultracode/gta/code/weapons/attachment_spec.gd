class_name AttachmentSpec
extends Resource
## Data definition of one weapon attachment (Registry kind "attachments").
##
## An attachment changes the stats of the weapon it is installed on (see apply_to) and may show
## a child mesh of the weapon model (`node_name`, e.g. "Att_Suppressor"; hidden by default).
## Only one attachment per `kind` can be installed on a weapon (a new finish replaces the old).

const KINDS: Array[String] = ["suppressor", "scope", "flashlight", "grip", "ext_mag", "finish"]
## Material of the weapon models that finishes recolour.
const FINISH_MATERIAL := "M_Weapon_Finish"

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var kind: String = ""                   ## one of KINDS
@export var price: int = 0
@export var node_name: String = ""              ## child mesh of the weapon GLB shown when installed

# --- stat effects (multipliers; 1.0 = no change) -------------------------------------------------
@export var damage_mult: float = 1.0
@export var range_mult: float = 1.0
@export var noise_mult: float = 1.0
@export var spread_mult: float = 1.0            ## base spread
@export var bloom_mult: float = 1.0             ## spread added per shot and its cap
@export var moving_spread_mult: float = 1.0
@export var aim_spread_mult: float = 1.0        ## multiplies the weapon's aim multiplier
@export var recoil_mult: float = 1.0
@export var mag_mult: float = 1.0
@export var reload_mult: float = 1.0
@export var equip_mult: float = 1.0
@export var aim_fov_mult: float = 1.0
@export var suppresses: bool = false            ## shots use the suppressed sound / noise kind
@export var is_light: bool = false              ## flashlight: toggled SpotLight3D on the weapon
@export var color: Color = Color(0, 0, 0, 0)    ## finish tint (alpha 0 = not a finish)
@export var finish_metallic: float = -1.0       ## finish: >= 0 overrides the material metallic
@export var finish_roughness: float = -1.0      ## finish: >= 0 overrides the material roughness


func apply_to(spec: WeaponSpec) -> void:
	spec.damage *= damage_mult
	spec.max_range *= range_mult
	spec.falloff_start *= range_mult
	spec.falloff_end *= range_mult
	spec.noise_radius *= noise_mult
	var bloom_room := maxf(spec.spread_max - spec.spread_base, 0.0)
	spec.spread_base *= spread_mult
	spec.spread_bloom *= bloom_mult
	spec.spread_max = spec.spread_base + bloom_room * bloom_mult
	spec.spread_moving *= moving_spread_mult
	spec.spread_aim_mult *= aim_spread_mult
	spec.recoil_pitch *= recoil_mult
	spec.recoil_yaw *= recoil_mult
	if mag_mult != 1.0 and spec.mag_size > 1:
		spec.mag_size = maxi(spec.mag_size + 1, int(round(float(spec.mag_size) * mag_mult)))
	spec.reload_time *= reload_mult
	spec.equip_time *= equip_mult
	spec.aim_fov *= lerpf(1.0, aim_fov_mult, clampf(spec.optic_strength, 0.0, 1.0))
	if suppresses:
		spec.suppressed = true
		spec.sound_fire = "suppressed_shot"
	if kind == "scope" and spec.scope_overlay_with_scope:
		spec.scoped = true


func is_finish() -> bool:
	return kind == "finish"


## Short human readable summary of the gameplay effect (shop UI).
func effect_text() -> String:
	var parts: PackedStringArray = []
	if suppresses:
		parts.append("noise %d%%" % int(round(noise_mult * 100.0)))
	if damage_mult != 1.0:
		parts.append("damage %+d%%" % int(round((damage_mult - 1.0) * 100.0)))
	if range_mult != 1.0:
		parts.append("range %+d%%" % int(round((range_mult - 1.0) * 100.0)))
	if recoil_mult != 1.0:
		parts.append("recoil %+d%%" % int(round((recoil_mult - 1.0) * 100.0)))
	if bloom_mult != 1.0:
		parts.append("bloom %+d%%" % int(round((bloom_mult - 1.0) * 100.0)))
	if aim_spread_mult != 1.0:
		parts.append("aimed spread %+d%%" % int(round((aim_spread_mult - 1.0) * 100.0)))
	if mag_mult != 1.0:
		parts.append("magazine %+d%%" % int(round((mag_mult - 1.0) * 100.0)))
	if reload_mult != 1.0:
		parts.append("reload %+d%%" % int(round((reload_mult - 1.0) * 100.0)))
	if aim_fov_mult != 1.0:
		parts.append("zoom x%.1f" % (1.0 / aim_fov_mult))
	if is_light:
		parts.append("weapon light")
	if is_finish():
		parts.append("cosmetic")
	return ", ".join(parts)
