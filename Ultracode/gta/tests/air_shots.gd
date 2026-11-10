extends Node
## Windowed screenshots of the flying aircraft (short run, <= 20 s):
##   tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 120 -Tag air_shots -UserArgs '--test=air_shots','--test-timeout=100','--flag=no_parked_aircraft','--disable=traffic,peds,police,props,respawn,emergency,wildlife,shops,garage,transit,taxi,activities,debug,pickups'
## qa/screenshots/air_fly_heli_bay.png        heli_civil hovering over the marina water (rotor blur, spray)
## qa/screenshots/air_fly_plane_runway.png    plane_prop on the runway, engine running (prop blur, gear on the ground)
## qa/screenshots/air_fly_plane_turn.png      plane_prop in a climbing left turn
## qa/screenshots/air_fly_jet_turn.png        plane_jet in a climbing right turn
## qa/screenshots/air_fly_police_night.png    heli_police at night with the searchlight on a target
## With --flag=air_chase instead: the PLAYER flies, gameplay chase camera + HUD:
## qa/screenshots/air_fly_chase_heli.png      heli_civil climbing away from the runway
## qa/screenshots/air_fly_chase_plane.png     plane_prop on its take-off roll

var cam: Camera3D = null
var _follow: Node3D = null
var _follow_off: Vector3 = Vector3.ZERO      ## in the aircraft's heading frame (x right, y up, z back)
var _look_off: Vector3 = Vector3.ZERO
var _steer: Node3D = null
var _steer_bank: float = 0.0
var _steer_gamma: float = 0.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if Game.flags.has("air_chase"):
		await _run_chase()
		return
	UI.set_hud_visible(false)
	WorldClock.set_hour(10.5)
	if Weather.has_method("snap_weather"):
		Weather.snap_weather("clear")
	cam = Camera3D.new()
	cam.name = "AirShotCam"
	cam.fov = 60.0
	cam.far = 3000.0
	Game.get_entities_root().add_child(cam)
	cam.make_current()
	await TestHarness.wait_frames(5)

	# --- helicopter hovering over the marina water ------------------------------------------
	var hp := Vector3(-120.0, 11.0, 300.0)
	var heli := Game.spawn_vehicle("heli_civil", Transform3D(Basis(Vector3.UP, deg_to_rad(150.0)), hp), {"color": Color("#F0802F"), "color2": Color("#F1F1EE")})
	if heli != null:
		heli.call("start_engine")
		heli.set("rotor_rpm", 1.0)
		heli.call("hover_at", hp, hp.y)
		heli.call("set_autopilot_heading", deg_to_rad(150.0))
		_place(Vector3(-101.0, 6.5, 318.0), hp + Vector3(0.0, 1.2, 0.0))
		await TestHarness.wait_seconds(1.5)
		_place(Vector3(-101.0, 6.5, 318.0), heli.global_position + Vector3(0.0, 1.2, 0.0))
		await TestHarness.shot("air_fly_heli_bay")
		TestHarness.check(bool(heli.get("on_ground")) == false and float(heli.get("altitude_agl")) > 6.0, "heli hovering over the water for the shot")

	# --- plane on the runway ------------------------------------------------------------------
	var rs := Game.get_location("airport_runway_start")
	var gy := _ground_y(rs.origin.x, rs.origin.z)
	var plane := Game.spawn_vehicle("plane_prop", Transform3D(rs.basis, Vector3(rs.origin.x, gy, rs.origin.z)), {"color": Color("#F1F1EE"), "color2": Color("#D8342C")})
	if plane != null:
		plane.call("set_throttle", 0.3)
		plane.call("set_brakes", 1.0)
		var pp: Vector3 = plane.global_position
		_place(pp + Vector3(9.0, 2.2, -8.5), pp + Vector3(0.5, 1.2, 0.0))
		await TestHarness.wait_seconds(1.6)
		await TestHarness.shot("air_fly_plane_runway")
		TestHarness.check(int(plane.get("gear_contacts")) == 3, "plane on its three wheels for the runway shot")

		# --- climbing left turn over the airfield -------------------------------------------
		var start := Vector3(-60.0, 80.0, -230.0)
		plane.call("set_brakes", 0.0)
		plane.call("teleport", Transform3D(Basis(Vector3.UP, -PI * 0.5), start))
		plane.set("linear_velocity", Vector3(40.0, 2.0, 0.0))
		plane.set("throttle", 1.0)
		_steer = plane
		_steer_bank = deg_to_rad(-30.0)
		_steer_gamma = 0.09
		_follow = plane
		_follow_off = Vector3(-11.0, -2.5, 20.0)
		_look_off = Vector3(0.0, 0.8, -2.0)
		await TestHarness.wait_seconds(1.8)
		await TestHarness.shot("air_fly_plane_turn")
		TestHarness.check(not bool(plane.get("on_ground")), "plane airborne for the turn shot")
		_steer = null
		_follow = null
		plane.queue_free()

	# --- jet in a climbing right turn ---------------------------------------------------------
	var jet := Game.spawn_vehicle("plane_jet", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(150.0, 110.0, -200.0)), {"color": Color("#F1F1EE"), "color2": Color("#27405F")})
	if jet != null:
		jet.set("linear_velocity", Vector3(-70.0, 3.0, 0.0))
		jet.call("set_throttle", 1.0)
		_steer = jet
		_steer_bank = deg_to_rad(35.0)
		_steer_gamma = 0.08
		_follow = jet
		_follow_off = Vector3(12.0, 3.0, 22.0)
		_look_off = Vector3(0.0, 1.0, -3.0)
		await TestHarness.wait_seconds(1.5)
		await TestHarness.shot("air_fly_jet_turn")
		_steer = null
		_follow = null
		jet.queue_free()

	# --- police helicopter, night, searchlight ------------------------------------------------
	WorldClock.set_hour(22.5)
	var plaza := Game.get_location("downtown_plaza").origin
	var pol_pos := plaza + Vector3(-6.0, 34.0, 8.0)
	var pol := Game.spawn_vehicle("heli_police", Transform3D(Basis(Vector3.UP, deg_to_rad(200.0)), pol_pos), {})
	if pol != null:
		pol.call("start_engine")
		pol.set("rotor_rpm", 1.0)
		pol.call("hover_at", pol_pos, pol_pos.y)
		pol.call("set_autopilot_heading", deg_to_rad(200.0))
		var tgt := plaza + Vector3(4.0, 0.2, -6.0)
		pol.call("set_headlights", 1)
		pol.call("set_searchlight", true, tgt)
		_place(pol_pos + Vector3(-17.0, -12.0, 22.0), pol_pos + Vector3(2.0, -4.0, -2.0))
		await TestHarness.wait_seconds(1.8)
		await TestHarness.shot("air_fly_police_night")
		TestHarness.check(bool(pol.get("searchlight_on")), "police searchlight on for the night shot")
	TestHarness.finish(true, "aircraft shots")


func _physics_process(_delta: float) -> void:
	if _steer != null and is_instance_valid(_steer):
		var b := _steer.global_transform.basis.orthonormalized()
		var bank := asin(clampf(-b.x.y, -1.0, 1.0))
		var v: Vector3 = _steer.get("linear_velocity")
		var g := asin(clampf(v.y / maxf(v.length(), 1.0), -1.0, 1.0))
		var av: Vector3 = _steer.get("angular_velocity")
		var wl: Vector3 = b.inverse() * av
		var p_in := clampf((_steer_gamma - g) * 4.0 - wl.x * 0.35 + absf(sin(bank)) * 0.35, -1.0, 1.0)
		var r_in := clampf((_steer_bank - bank) * 2.5, -1.0, 1.0)
		_steer.call("set_flight_inputs", p_in, r_in, 0.0, 1.0)


func _process(_delta: float) -> void:
	if _follow != null and is_instance_valid(_follow) and cam != null:
		var f := -_follow.global_transform.basis.z
		f.y = 0.0
		var hb := Basis(Vector3.UP, atan2(-f.x, -f.z)) if f.length() > 0.05 else Basis.IDENTITY
		var target := _follow.global_position + hb * _look_off
		_place(_follow.global_position + hb * _follow_off, target)
	if cam != null and not cam.current:
		cam.make_current()


func _place(pos: Vector3, look: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)


func _ground_y(x: float, z: float) -> float:
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -20.0, z), Layers.WORLD)
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else Game.ground_height(x, z)


## Gameplay camera (player camera rig in "aircraft" mode) with the HUD, player at the controls.
func _run_chase() -> void:
	WorldClock.set_hour(16.0)
	if Weather.has_method("snap_weather"):
		Weather.snap_weather("clear")
	var p := Game.player
	if p == null:
		TestHarness.finish(false, "no player")
		return
	var gy := _ground_y(120.0, -264.0)
	var heli := Game.spawn_vehicle("heli_civil", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(120.0, gy, -264.0)), {"color": Color("#2C6FD9"), "color2": Color("#F1F1EE")})
	if heli != null:
		p.call("enter_vehicle", heli, 0, true)
		await TestHarness.wait_physics_frames(3)
		heli.set("rotor_rpm", 1.0)
		Input.action_press("air_throttle_up")
		await TestHarness.wait_seconds(2.6)
		Input.action_press("air_pitch_down")
		Input.action_press("air_yaw_left")
		await TestHarness.wait_seconds(1.4)
		Input.action_release("air_yaw_left")
		await TestHarness.wait_seconds(0.8)
		await TestHarness.shot("air_fly_chase_heli")
		Input.action_release("air_pitch_down")
		Input.action_release("air_throttle_up")
		TestHarness.check(float(heli.get("altitude_agl")) > 8.0, "player heli climbing for the chase shot")
		p.call("exit_vehicle")
		await TestHarness.wait_physics_frames(2)
		heli.queue_free()
	var rs := Game.get_location("airport_runway_start")
	gy = _ground_y(rs.origin.x, rs.origin.z)
	var plane := Game.spawn_vehicle("plane_prop", Transform3D(rs.basis, Vector3(rs.origin.x, gy, rs.origin.z)), {"color": Color("#F2C331"), "color2": Color("#27405F")})
	if plane != null:
		p.call("enter_vehicle", plane, 0, true)
		await TestHarness.wait_physics_frames(3)
		Input.action_press("air_throttle_up")
		await TestHarness.wait_seconds(3.6)
		await TestHarness.shot("air_fly_chase_plane")
		Input.action_release("air_throttle_up")
		TestHarness.check(float(plane.get("airspeed")) > 5.0, "player plane rolling for the chase shot")
	TestHarness.finish(true, "aircraft chase shots")
