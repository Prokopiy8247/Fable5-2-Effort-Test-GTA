class_name WeaponDef
extends Resource
## Data asset describing one weapon.

@export var id := ""
@export var name := ""
@export var slot := 0
@export var kind := "hitscan"     # melee | hitscan | projectile | thrown
@export var hold := "pistol"      # fist | melee | pistol | rifle | launcher | thrown
@export var proj := ""
@export var damage := 10.0
@export var pellets := 1
@export var rate := 2.0            # attacks per second
@export var mag := 0
@export var max_ammo := 0
@export var reload := 1.5
@export var spread := 1.0          # degrees
@export var recoil := 1.0          # degrees of camera kick
@export var reach := 100.0
@export var auto := false
@export var zoom_fov := 0.0
@export var scoped := false
@export var model := ""
@export var price := 0
@export var ammo_price := 0
@export var ammo_pack := 0         # rounds per ammo purchase (0 => two magazines)
@export var driveby := false
@export var noise := 50.0
@export var knock := 1.0
@export var mods: Array = []
@export var sound := ""


func ammo_per_buy() -> int:
	return ammo_pack if ammo_pack > 0 else mag * 2
