class_name VehicleDef
extends Resource
## Data asset describing one vehicle type and its handling profile.

@export var id := ""
@export var name := ""
@export var kind := "car"          # car | bike | bicycle | boat | heli | plane
@export var mass := 1200.0
@export var engine := 7000.0       # peak drive force (N)
@export var max_speed := 40.0      # m/s
@export var brake := 14000.0
@export var steer := 32.0          # max steer angle (deg)
@export var grip := 1.0
@export var drive := "rwd"
@export var seats := 2
@export var health := 1000.0
@export var price := 0
@export var traffic := 0.0         # ambient spawn weight
@export var susp_rest := 0.30
@export var engine_pitch := 1.0
@export var fixed_color := Color(0, 0, 0, 0)
@export var fixed_color2 := Color(0, 0, 0, 0)
@export var tag := ""
@export var siren := false
@export var silent := false
@export var takeoff_speed := 25.0
@export var jet := false
