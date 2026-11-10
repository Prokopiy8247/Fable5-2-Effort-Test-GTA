class_name VehicleWheel
extends RefCounted
## One raycast wheel: static setup + per-step simulation state. Plain data on purpose - the
## owning vehicle (Car, later Bike / aircraft gear) runs the maths so the hot loop stays in one
## function. See docs/VEHICLES.md.

# --- setup (body space = the RigidBody3D's local space) ---------------------------------------
var wheel_name: String = ""
var node: Node3D = null                 ## visual wheel node (Wheel_FL ...), may be null
var rest_pos: Vector3 = Vector3.ZERO    ## wheel centre in body space, modelled (loaded) pose
var rest_basis: Basis = Basis.IDENTITY  ## visual basis in body space at rest
var parent_inv: Transform3D = Transform3D.IDENTITY   ## inverse of the visual parent's body-space transform
var radius: float = 0.33
var width: float = 0.22
var is_front: bool = false
var is_left: bool = false
var steers: bool = false
var steer_ratio: float = 0.0            ## share of the steering angle this wheel turns by (1 front, 0 rear, small +/- on tandem axles)
var driven: bool = false
var handbraked: bool = false
var drive_share: float = 0.0            ## share of the total drive force (sums to 1 over driven wheels)
var brake_share: float = 0.25           ## share of the total brake force
var partner_index: int = -1             ## index (in the owner's wheel list) of the other wheel on this axle; an index, not a reference, so wheels never form a RefCounted cycle
var grip: float = 1.05                  ## peak friction coefficient
var static_load: float = 3500.0         ## N carried at rest
var stiffness: float = 45000.0          ## N/m
var damping_bump: float = 2800.0        ## N per m/s
var damping_rebound: float = 3800.0
var anti_roll: float = 20000.0          ## N/m of compression difference
var bump: float = 0.15                  ## travel above the modelled pose
var droop: float = 0.13                 ## travel below the modelled pose

# --- state ---------------------------------------------------------------------------------
var grounded: bool = false
var compression: float = 0.0            ## metres above (+) / below (-) the modelled pose
var normal_force: float = 0.0           ## normal force this step (N)
var contact_point: Vector3 = Vector3.ZERO
var contact_normal: Vector3 = Vector3.UP
var collider: Object = null
var collider_id: int = 0
var surface: String = "asphalt"
var surface_grip: float = 1.0
var surface_timer: float = 0.0
var steer: float = 0.0                  ## radians, + = right
var ang_vel: float = 0.0                ## visual spin (rad/s), + = rolling forward
var spin_angle: float = 0.0
var visual_offset: float = 0.0          ## smoothed suspension offset for the mesh
var skid: float = 0.0                   ## 0..1 audible / visible slip
var slip_angle: float = 0.0
var long_force: float = 0.0
var lat_force: float = 0.0
var spinning: bool = false              ## driven wheel over the traction limit
var locked: bool = false                ## handbrake lock
var flat: bool = false
var detached: bool = false
var anchor: Vector3 = Vector3.ZERO      ## static-friction anchor (world) while holding
var anchor_valid: bool = false

const SURFACE_GRIP := {
	"asphalt": 1.0, "concrete": 1.0, "metal": 0.9, "wood": 0.9, "glass": 0.85, "rubber": 1.0,
	"dirt": 0.82, "grass": 0.74, "sand": 0.62, "foliage": 0.7, "water": 0.5, "flesh": 0.8,
}


## Normalised lateral force (0..1) for a slip ratio s = |slip angle| / peak angle.
## Rises smoothly to 1 at s = 1 and then decays towards `slide` (arcade: grippy but slidable).
static func slip_curve(s: float, slide: float) -> float:
	if s <= 1.0:
		return s * (1.5 - 0.5 * s * s)
	return slide + (1.0 - slide) * exp(-(s - 1.0) * 0.9)


func reset_state() -> void:
	grounded = false
	compression = 0.0
	normal_force = 0.0
	ang_vel = 0.0
	skid = 0.0
	spinning = false
	locked = false
	anchor_valid = false
	collider = null
	collider_id = 0


func set_surface(surface_name: String) -> void:
	surface = surface_name
	surface_grip = float(SURFACE_GRIP.get(surface_name, 1.0))
