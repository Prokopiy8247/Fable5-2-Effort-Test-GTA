extends Node
## Windowed screenshot run for the vehicle framework (short: about 12 s of real time).
## Uses the real GLBs: the sedan as the hero car plus every other car whose GLB exists.
##
##   veh_side / veh_34 / veh_wheel   at rest: wheels in the arches, body neither floating nor sunk
##   veh_rear_brake                  rear three-quarter, running + brake lights
##   veh_door                        driver door swinging on occupant_enter
##   veh_corner / veh_slide          cornering under power, handbrake slide (roll, steer, travel)
##   veh_door                        ... with hood and trunk open (hinged lids)
##   veh_lineup / _rear / _lod       paint variants + mods on the hero car, near and Body_LOD1
##   veh_fleet + veh_car_<id>        every other car whose GLB exists (overview + one close shot each)
##   veh_night / veh_night_rear      emissive lamps + pooled SpotLight3D headlights
##   veh_rear_open_pickup / _van     pickup Tailgate folded down, van rear doors open
##   veh_night_siren                 light bar + pooled siren OmniLight (if an emergency GLB exists)
##   veh_night_taxi                  taxi roof sign lit (for hire)
##   veh_wreck                       burnt wreck after explode()
##
## Run: tools\godot.ps1 -Mode window -Frames 700 -UserArgs '--test=veh_shots','--no_player',
##      '--disable=world,environment,city,interactions,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Then LOOK at qa/screenshots/veh_*.png.

const Bed := preload("res://gta/tests/veh_testbed.gd")

const OCCUPANT_SRC := "extends Node3D
func on_vehicle_ejected(_v: Node, _xf: Transform3D, _impulse: Vector3) -> void:
	pass
"

var mgr: Node = null
var cam: Camera3D = null
var follow: Node3D = null
var follow_offset: Vector3 = Vector3.ZERO      ## in the car's yaw frame: x right, y up, z back
var follow_look: Vector3 = Vector3(0.0, 0.7, 0.0)
var hero_id: String = "sedan"


func _ready() -> void:
	await _run()


func _process(_delta: float) -> void:
	if follow != null and is_instance_valid(follow) and cam != null:
		var yaw := Basis(Vector3.UP, follow.global_transform.basis.get_euler().y)
		var p := follow.global_position
		cam.global_position = p + yaw * follow_offset
		cam.look_at(p + yaw * follow_look)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _aim(from: Vector3, to: Vector3, fov: float = 42.0) -> void:
	follow = null
	cam.fov = fov
	cam.global_position = from
	cam.look_at(to)


func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await TestHarness.shot(shot_name)


func _spawn(id: String, pos: Vector3, opts: Dictionary = {}, yaw: float = 0.0) -> Variant:
	return Game.spawn_vehicle(id, Transform3D(Basis(Vector3.UP, yaw), pos), opts)


func _run() -> void:
	mgr = Game.get_system("vehicles")
	if not TestHarness.check(mgr != null, "vehicles system is registered"):
		TestHarness.finish(false, "no vehicles system")
		return
	Bed.build_proving_ground(self, 90.0, -320.0, 120.0)
	if UI.has_method("set_hud_visible"):
		UI.call("set_hud_visible", false)       # clean frames: the HUD belongs to the UI module
	Bed.add_light_rig(self, false)
	cam = Bed.make_camera(self)
	var cars: Array[String] = []
	for id: String in Bed.ids_with_models():
		var spec := Registry.get_def("vehicles", id) as VehicleSpec
		if spec != null and spec.vehicle_class == "car":
			cars.append(id)
	if not cars.has(hero_id) and not cars.is_empty():
		hero_id = cars[0]
	if not TestHarness.check(cars.has(hero_id), "a car GLB is available (%s)" % hero_id):
		TestHarness.finish(false, "no models")
		return
	print("VEH_SHOTS: hero = %s, cars with GLB = %s" % [hero_id, str(cars)])

	# ---------------------------------------------------------------- at rest
	var v: Variant = _spawn(hero_id, Vector3.ZERO, {"color": Color("#1FA7A0")})
	await _frames(40)
	var a: AABB = v.body_aabb
	var mid := Vector3(0.0, a.position.y + a.size.y * 0.42, a.get_center().z)
	var span: float = maxf(a.size.z, 3.5)
	_aim(Vector3(-span * 1.55, 1.05, mid.z), mid, 40.0)
	await _shot("veh_side")
	_aim(Vector3(-span * 0.95, 1.9, mid.z - span * 1.2), mid, 42.0)
	await _shot("veh_34")
	var wp: Vector3 = v.get_wheel_position(0)
	_aim(wp + Vector3(-1.9, 0.25, -1.3), wp + Vector3(0.2, 0.05, 0.1), 40.0)
	await _shot("veh_wheel")
	TestHarness.check(absf(v.global_position.y) < 0.03 and v.global_transform.basis.y.y > 0.9995,
			"%s rests level at its modelled ride height (y %.3f)" % [hero_id, v.global_position.y])

	v.set_headlights(1)
	v.set_inputs(0.0, 0.0, 1.0)
	_aim(Vector3(span * 0.85, 1.7, mid.z + span * 1.25), mid, 42.0)
	await _frames(4)
	await _shot("veh_rear_brake")
	v.set_inputs(0.0, 0.0, 0.0)
	v.set_headlights(0)

	# ---------------------------------------------------------------- door swing
	var src := GDScript.new()
	src.source_code = OCCUPANT_SRC
	src.reload()
	var occ: Node3D = src.new()
	occ.name = "ShotOccupant"
	add_child(occ)
	v.occupant_enter(occ, 0)
	v.set_lid_open("hood", 1.0)
	v.set_lid_open("trunk", 1.0)
	_aim(Vector3(-span * 1.0, 1.9, mid.z - span * 0.75), mid, 42.0)
	await _frames(16)
	await _frames(14)
	await _shot("veh_door")
	v.set_lid_open("hood", 0.0)
	v.set_lid_open("trunk", 0.0)
	await _frames(36)

	# ---------------------------------------------------------------- cornering + handbrake slide
	cam.fov = 48.0
	follow_offset = Vector3(-2.7, 1.05, -5.3)
	follow_look = Vector3(0.0, 0.6, 0.0)
	follow = v
	v.set_inputs(1.0, 0.0, 0.0)
	await _frames(130)
	v.set_inputs(0.7, 1.0, 0.0)
	await _frames(36)
	var roll: float = v.global_transform.basis.x.y
	var lean: Vector2 = v.get_body_lean_degrees()
	print("VEH_SHOTS: cornering right at %.1f m/s, steer %.2f, physical roll %.1f deg + visual lean %.1f deg (pitch %.1f)" % [
			v.linear_velocity.length(), float(v.steer_norm), rad_to_deg(asin(clampf(roll, -1.0, 1.0))), lean.x, lean.y])
	await _shot("veh_corner")
	v.set_inputs(1.0, 0.0, 0.0)
	await _frames(45)
	follow_offset = Vector3(4.2, 1.5, 6.4)
	v.set_inputs(0.0, 1.0, 0.0, true)
	await _frames(30)
	print("VEH_SHOTS: handbrake slide at %.1f m/s, skid %.2f" % [v.linear_velocity.length(), float(v.get_skid_amount())])
	await _shot("veh_slide")
	follow = null
	v.occupant_exit(0)
	occ.queue_free()
	mgr.despawn_vehicle(v)

	# ---------------------------------------------------------------- line-up: paint, mods, other cars
	var row: Array = []
	var x := 0.0
	var z0 := 30.0
	var looks: Array[Dictionary] = [
		{"color": Color("#D8342C")},
		{"color": Color("#17181C"), "mods": {"spoiler": "spoiler_b", "bumper_f": "bumper_f_a", "skirts": "skirts_a", "hood": "hood_a",
				"wheels": "wheels_sport", "wheel_color": "wheelcol_gold", "paint_finish": "finish_matte", "tint": "tint_limo",
				"lights": "lights_ice"}},
		{"color": Color("#F2C331"), "color2": Color("#17181C"), "mods": {"spoiler": "spoiler_a", "roof": "roof_a", "exhaust": "exhaust_a",
				"grille": "grille_a", "bumper_r": "bumper_r_a", "wheels": "wheels_deep", "wheel_color": "wheelcol_red",
				"suspension": "suspension_4", "paint_finish": "finish_metallic"}},
	]
	for look: Dictionary in looks:
		var c: Variant = _spawn(hero_id, Vector3(x, 0.0, z0), look, PI)
		if c != null:
			row.append(c)
			x += c.body_aabb.size.x + 1.5
	await _frames(40)
	var cx := (x - 3.0) * 0.5
	var dist := maxf(7.5, x * 0.62)
	_aim(Vector3(cx - dist * 0.55, 2.3, z0 + dist), Vector3(cx, 0.6, z0), 46.0)
	await _shot("veh_lineup")
	_aim(Vector3(cx + dist * 0.5, 2.6, z0 - dist * 0.95), Vector3(cx, 0.6, z0), 46.0)
	await _shot("veh_lineup_rear")
	# far away with a long lens: Body_LOD1 replaces the detailed body beyond VehicleBase.LOD_DISTANCE
	_aim(Vector3(cx - 30.0, 9.0, z0 + 100.0), Vector3(cx, 0.6, z0), 7.5 + x * 0.35)
	await _shot("veh_lineup_lod")

	# ---------------------------------------------------------------- every other car with a GLB
	var fleet: Array = []
	var fx := -28.0
	var fz := 2.0
	for id: String in cars:
		if id == hero_id:
			continue
		var c2: Variant = _spawn(id, Vector3(fx, 0.0, fz), {"roof_open": true}, PI)
		if c2 != null:
			fleet.append(c2)
			fx += c2.body_aabb.size.x + 2.6
	if not fleet.is_empty():
		await _frames(40)
		var fcx := (-28.0 + fx - 2.6) * 0.5
		var fdist := maxf(9.0, (fx + 28.0) * 0.74)
		_aim(Vector3(fcx - fdist * 0.22, 3.0 + fdist * 0.14, fz + fdist), Vector3(fcx, 0.8, fz), 50.0)
		await _shot("veh_fleet")
		for c4: Variant in fleet:
			var fa: AABB = c4.body_aabb
			var flen: float = maxf(fa.size.z, 3.2)
			var fp: Vector3 = c4.global_position
			var target := fp + Vector3(0.0, fa.position.y + fa.size.y * 0.42, 0.0)
			_aim(fp + Vector3(flen * 0.8, 1.1 + fa.size.y * 0.35, flen * 0.95), target, 44.0)
			await _shot("veh_car_" + str(c4.spec_id))
			TestHarness.check(absf(fp.y) < 0.03 and c4.global_transform.basis.y.y > 0.9995,
					"%s rests level at its modelled ride height (y %.3f)" % [c4.spec_id, fp.y])

	# ---------------------------------------------------------------- extra lids / doors: pickup Tailgate, van rear doors
	for c6: Variant in fleet:
		var sid := str(c6.spec_id)
		if sid != "pickup" and sid != "van":
			continue
		if sid == "pickup":
			c6.set_lid_open("trunk", 1.0, true)
		else:
			c6.open_door("Door_RearL", 4.0)
			c6.open_door("Door_RearR", 4.0)
		await _frames(24)
		var rp: Vector3 = c6.global_position
		var rl: float = maxf(c6.body_aabb.size.z, 3.2)
		# fleet cars face +Z (yaw PI): the camera stands behind them, at -Z
		_aim(rp + Vector3(rl * 0.55, 1.5 + c6.body_aabb.size.y * 0.3, -rl * 1.05), rp + Vector3(0.0, c6.body_aabb.size.y * 0.4, 0.0), 44.0)
		await _shot("veh_rear_open_" + sid)
		if sid == "pickup":
			c6.set_lid_open("trunk", 0.0, true)

	# ---------------------------------------------------------------- night: lamps + pooled lights
	Bed.set_rig_night(self, true)
	for i in row.size():
		var c3: Variant = row[i]
		c3.set_headlights(2 if i == 0 else 1)
		if i == 1:
			c3.set_inputs(0.0, 0.0, 1.0)
		if i == 2:
			c3.set_indicator(2)
	_aim(Vector3(cx - dist * 0.5, 1.6, z0 + dist * 1.05), Vector3(cx, 0.5, z0 + 2.0), 46.0)
	await _frames(16)
	await _shot("veh_night")
	_aim(Vector3(cx + dist * 0.5, 2.0, z0 - dist * 0.95), Vector3(cx, 0.6, z0), 46.0)
	await _shot("veh_night_rear")
	for c5: Variant in fleet:
		if c5.has_siren():
			c5.set_siren(true)
			c5.set_headlights(1)
			var sp: Vector3 = c5.global_position
			var sl: float = maxf(c5.body_aabb.size.z, 3.2)
			_aim(sp + Vector3(sl * 0.75, 1.6, sl * 1.2), sp + Vector3(0.0, c5.body_aabb.size.y * 0.5, 0.0), 46.0)
			await _frames(14)
			await _shot("veh_night_siren")
			c5.set_siren(false)
			break
	for c7: Variant in fleet:
		if str(c7.spec_id) != "taxi":
			continue
		c7.start_engine()
		c7.set_headlights(1)
		var tp: Vector3 = c7.global_position
		var tl: float = maxf(c7.body_aabb.size.z, 3.2)
		_aim(tp + Vector3(tl * 0.8, 2.3, tl * 1.05), tp + Vector3(0.0, c7.body_aabb.size.y * 0.62, 0.0), 44.0)
		await _frames(12)
		await _shot("veh_night_taxi")
		TestHarness.check(c7.lights != null and c7.lights.is_taxi_sign_lit(), "taxi: roof sign lit at night while for hire")
		break
	Bed.set_rig_night(self, false)

	# ---------------------------------------------------------------- wreck
	var w: Variant = row[0]
	var wpos: Vector3 = w.global_position
	w.explode(null)
	await _frames(75)
	var wnow: Vector3 = w.global_position
	_aim(wnow + Vector3(-5.5, 2.4, 6.5), wnow + Vector3(0.0, 0.5, 0.0), 46.0)
	await _shot("veh_wreck")
	TestHarness.check(w.destroyed, "explode() produced a wreck (moved %.1f m)" % wnow.distance_to(wpos))
	TestHarness.finish()
