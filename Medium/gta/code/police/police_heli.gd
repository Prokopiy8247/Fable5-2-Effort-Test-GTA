extends Node3D
## Police air support: orbits the suspect, keeps visual contact, searchlight at night, gunfire at 4+ stars.

var model: Node3D
var rotor: Node3D
var tail: Node3D
var health := 520.0
var dead := false
var leaving := false
var light: SpotLight3D
var _spin := 0.0
var _orbit := 0.0
var _fire_t := 3.0
var _burst := 0
var _snd: AudioStreamPlayer3D
var vel := Vector3.ZERO
var body: StaticBody3D


func _ready() -> void:
	model = G.model("vehicles/police_heli")
	add_child(model)
	G.remat(model, {"Paint": G.cmat("pheli", Color(0.07, 0.09, 0.15), 0.4, 0.4), "Paint2": G.cmat("pheli2", Color(0.9, 0.9, 0.9), 0.5)})
	rotor = G.part(model, "_Rotor_Main")
	tail = G.part(model, "_Rotor_Tail")
	body = StaticBody3D.new()
	body.collision_layer = G.L_VEH
	body.collision_mask = 0
	var cs = CollisionShape3D.new()
	var bs = BoxShape3D.new()
	bs.size = Vector3(2.2, 2.6, 7.5)
	cs.shape = bs
	cs.position = Vector3(0, 1.4, 1.0)
	body.add_child(cs)
	add_child(body)
	light = SpotLight3D.new()
	light.spot_range = 170.0
	light.spot_angle = 9.0
	light.light_energy = 0.0
	light.light_color = Color(0.9, 0.95, 1.0)
	light.position = Vector3(0, 0.5, -1.5)
	add_child(light)


func damage(amount: float, from = null, _pos := Vector3.ZERO, kind := "bullet") -> void:
	if dead:
		return
	health -= amount * (0.6 if kind == "bullet" else 1.0)
	if from == G.player and G.wanted:
		G.wanted.crime("assault_cop", global_position, 0.6, true)
	if health <= 0.0:
		dead = true
		G.fx.explode(global_position, 9.0, 150.0, from)
		if from == G.player and G.wanted:
			G.wanted.crime("destroy_police", global_position, 1.5, true)
		# falling wreck
		var w = G.traffic.create("police_heli", global_position, rotation.y)
		w.linear_velocity = vel
		w.owner_tag = "abandoned"
		w.health = 1.0
		w.explode()
		queue_free()


func leave() -> void:
	leaving = true
	get_tree().create_timer(14.0).timeout.connect(func(): if is_instance_valid(self): queue_free())


func _physics_process(dt: float) -> void:
	_spin += dt * 30.0
	if rotor:
		rotor.rotation.y = _spin
	if tail:
		tail.rotation.x = _spin * 1.7
	if _snd == null and G.audio:
		_snd = G.audio.loop3d("heli", self, 2.0, 26.0)
	var W = G.wanted
	var tp: Vector3 = G.player_pos()
	if W and W.state == "search":
		tp = W.last_known + Vector3(sin(_orbit * 0.7), 0, cos(_orbit * 0.9)) * W.search_radius * 0.6
	_orbit += dt * 0.28
	var want = tp + Vector3(cos(_orbit) * 42.0, 0, sin(_orbit) * 42.0)
	want.y = max(95.0, G.player_pos().y + 45.0)
	if leaving:
		want = global_position + Vector3(global_position.x, 0, global_position.z).normalized() * 200.0 + Vector3(0, 60, 0)
	var to = want - global_position
	vel = vel.lerp(to.limit_length(1.0) * min(to.length() * 0.8, 34.0), clamp(dt * 1.2, 0.0, 1.0))
	global_position += vel * dt
	var look = G.flat(tp - global_position) if not leaving else G.flat(vel)
	if look.length() > 1.0:
		rotation.y = lerp_angle(rotation.y, atan2(-look.x, -look.z), clamp(dt * 2.0, 0.0, 1.0))
	model.rotation.x = lerpf(model.rotation.x, clamp(-vel.length() * 0.01, -0.3, 0.0), dt * 2.0)
	model.rotation.z = lerpf(model.rotation.z, clamp(vel.cross(Vector3.UP).dot(-global_basis.z) * 0.012, -0.3, 0.3), dt * 2.0)
	if leaving or W == null:
		light.light_energy = 0.0
		return
	light.look_at(tp + Vector3(0, 1, 0), Vector3.UP)
	light.light_energy = 18.0 if G.is_night() else 0.0
	# gunship behaviour at high wanted levels
	if W.stars >= 4 and W.seen and G.player.state not in ["dead", "busted"]:
		_fire_t -= dt
		if _fire_t <= 0.0:
			_burst += 1
			_fire_t = 0.14 if _burst < 5 else G.rng.randf_range(2.2, 4.0)
			if _burst >= 5:
				_burst = 0
			var from = global_position + Vector3(0, 0.6, 0) - global_basis.z * 1.5
			var aim = G.player_pos() + Vector3(G.rng.randf_range(-3.5, 3.5), 1.0, G.rng.randf_range(-3.5, 3.5))
			var dir = (aim - from).normalized()
			var h = G.ray(from, from + dir * 220.0, G.L_SHOT, [body.get_rid()])
			G.fx.tracer(from, h.position if h else from + dir * 220.0)
			G.audio.play3d("shot_rifle", from, 4.0, 0.9)
			if h:
				var n: Node = h.collider
				for i in 3:
					if n == null:
						break
					if n.has_method("damage"):
						n.damage(8.0, self, h.position, "bullet")
						break
					n = n.get_parent()
				G.fx.impact(h.position, h.normal, "concrete")
