extends Node
## Stealth layer of the player (spec 10A "Stealth mode", 46A Stealth skill). Child "Stealth" of the
## Player; player.gd preloads this script (no class_name: the module's reserved names are Player,
## PlayerCamera, PlayerInteraction and PlayerState*).
##
##   visibility     Player.visibility_factor 0.1..1, read by AiSenses (it multiplies the awareness
##                  rate): posture (crouched, sneaking - better with the Stealth skill - hunkered in
##                  cover) x light (daylight, else the street lamps of group "street_light" / the
##                  world's "street_light" spawn points, the weapon flashlight). Every VIS_INTERVAL.
##   takedown       Player.takedown_target: the NPC (group "npc") a takedown would hit right now -
##                  sneaking, on foot / in the melee stance, PlayerStateTakedown.can_take_down().
##                  Every SCAN_INTERVAL.
##   skill          Stealth XP while sneaking and moving with unaware NPCs within XP_RANGE.
##   loud gunfire   EventBus.noise_emitted of kind "gunshot" / "explosion" by the player ends
##                  stealth ("suppressed_gunshot" does not).
## Noise radii live in Player.get_stealth_noise_radius() (NOISE_STEALTH x the Stealth skill).

const SCAN_INTERVAL := 0.1
const VIS_INTERVAL := 0.2
const XP_INTERVAL := 0.5
const XP_RANGE := 14.0
const XP_PER_SEC := 0.035               ## skill points per second per unaware NPC near (max 2 count)
const LAMP_RANGE := 11.0                ## planar reach of a street lamp's pool of light
const LAMP_REFRESH := 4.0
const LOUD_KINDS: PackedStringArray = ["gunshot", "explosion"]
const DARK_VISIBILITY := 0.5            ## light factor in full darkness (1.0 in full light)
const CROUCH_MULT := 0.78
const STEALTH_MULT_LOW := 0.72          ## sneaking posture at Stealth skill 0 ...
const STEALTH_MULT_HIGH := 0.58         ## ... and at 100
const COVER_MULT := 0.7                 ## hunkered in cover

var player: Player = null
var light_level: float = 1.0            ## 0 dark .. 1 lit (last evaluation)
var xp_awarded: float = 0.0             ## total Stealth XP given for sneaking (tests / debug)

var _scan_t: float = 0.0
var _vis_t: float = 0.0
var _xp_t: float = 0.0
var _lamp_t: float = 0.0
var _lamps: PackedVector3Array = PackedVector3Array()
var _world_lamps: PackedVector3Array = PackedVector3Array()
var _world_lamps_done: bool = false


func setup(p: Player) -> void:
	player = p
	if not EventBus.noise_emitted.is_connected(_on_noise):
		EventBus.noise_emitted.connect(_on_noise)


func _physics_process(delta: float) -> void:
	var p := player
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_INTERVAL
		_scan_takedown()
	_vis_t -= delta
	if _vis_t <= 0.0:
		_vis_t = VIS_INTERVAL
		update_visibility()
	_xp_t -= delta
	if _xp_t <= 0.0:
		_xp_t = XP_INTERVAL
		_award_xp(XP_INTERVAL)


# =================================================================================================
# takedown target
# =================================================================================================

func _scan_takedown() -> void:
	var p := player
	var best: Node3D = null
	if p.in_stealth and not p.is_dead and p.current_vehicle == null and p.grounded \
			and (p.state_id == "on_foot" or p.state_id == "melee") and p.states.has("takedown"):
		var best_d := INF
		var pos := p.global_position
		var r2 := PlayerStateTakedown.RANGE * PlayerStateTakedown.RANGE
		for n: Node in get_tree().get_nodes_in_group("npc"):
			var n3 := n as Node3D
			if n3 == null or not n3.is_inside_tree():
				continue
			var dx := n3.global_position.x - pos.x
			var dz := n3.global_position.z - pos.z
			var d2 := dx * dx + dz * dz
			if d2 > r2 or d2 >= best_d:
				continue
			if PlayerStateTakedown.can_take_down(p, n3):
				best_d = d2
				best = n3
	if p.state_id != "takedown":
		p.takedown_target = best


# =================================================================================================
# visibility
# =================================================================================================

## Recomputes Player.visibility_factor now (also called every VIS_INTERVAL).
func update_visibility() -> float:
	var p := player
	if p == null or not is_instance_valid(p):
		return 1.0
	var day := 1.0
	if WorldClock.has_method("get_daylight"):
		day = clampf(float(WorldClock.get_daylight()), 0.0, 1.0)
	var lamp := 0.0
	if day < 0.98 and p.is_inside_tree():
		lamp = _lamp_light(p.global_position)
	var light := day + lamp * (1.0 - day)
	var inv := p.inventory
	if inv != null and is_instance_valid(inv) and inv.get("flashlight_on") == true:
		light = maxf(light, 0.8)
	light_level = clampf(light, 0.0, 1.0)
	var posture := 1.0
	if p.is_crouching:
		posture *= CROUCH_MULT
	if p.in_stealth:
		posture *= lerpf(STEALTH_MULT_LOW, STEALTH_MULT_HIGH, Skills.get_factor("stealth"))
	if p.in_cover and p.state != null and p.state.has_method("is_exposed") and not bool(p.state.call("is_exposed")):
		posture *= COVER_MULT
	if p.is_sprinting or p.current_vehicle != null:
		posture = 1.0
	var vf := posture * lerpf(DARK_VISIBILITY, 1.0, light_level)
	p.visibility_factor = clampf(vf, 0.1, 1.0)
	return p.visibility_factor


## 0..1 light of the nearest street lamp at `pos` (0 beyond LAMP_RANGE).
func _lamp_light(pos: Vector3) -> float:
	_lamp_t -= VIS_INTERVAL
	if _lamp_t <= 0.0:
		refresh_lamps()
	var r2 := LAMP_RANGE * LAMP_RANGE
	var best := 0.0
	for l: Vector3 in _lamps:
		var dx := l.x - pos.x
		var dz := l.z - pos.z
		var d2 := dx * dx + dz * dz
		if d2 >= r2 or absf(l.y - pos.y) > 14.0:
			continue
		var k := 1.0 - sqrt(d2) / LAMP_RANGE
		best = maxf(best, k * (2.0 - k))    # ease-out: bright under the lamp, soft rim
	return best


## Re-reads the lamp positions (group "street_light" now, the world's spawn points once).
func refresh_lamps() -> void:
	_lamp_t = LAMP_REFRESH
	if not _world_lamps_done and Game.world != null and is_instance_valid(Game.world) \
			and Game.world.has_method("get_spawn_points"):
		_world_lamps_done = true
		var pts: Variant = Game.world.call("get_spawn_points", "street_light")
		if pts is Array:
			for x: Variant in pts:
				if x is Transform3D:
					_world_lamps.append((x as Transform3D).origin)
	_lamps = _world_lamps.duplicate()
	if is_inside_tree():
		for n: Node in get_tree().get_nodes_in_group("street_light"):
			if n is Node3D and (n as Node3D).is_inside_tree():
				_lamps.append((n as Node3D).global_position)


# =================================================================================================
# skill + loud noises
# =================================================================================================

func _award_xp(dt: float) -> void:
	var p := player
	if not p.in_stealth or p.state_id != "on_foot" or not p.grounded or p.is_dead:
		return
	if Vector2(p.velocity.x, p.velocity.z).length() < 0.4:
		return
	var pos := p.global_position
	var count := 0
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var n3 := n as Node3D
		if n3 == null or not n3.is_inside_tree() or n3.get("is_dead") == true:
			continue
		if n3.global_position.distance_squared_to(pos) > XP_RANGE * XP_RANGE:
			continue
		if PlayerStateTakedown.is_aware(n3):
			continue
		count += 1
		if count >= 2:
			break
	if count > 0:
		var xp := XP_PER_SEC * dt * float(count)
		Skills.add_xp("stealth", xp)
		xp_awarded += xp


func _on_noise(_pos: Vector3, _radius: float, kind: String, instigator: Node) -> void:
	var p := player
	if p == null or instigator != p or not p.in_stealth:
		return
	if LOUD_KINDS.has(kind):
		p.set_stealth(false)
