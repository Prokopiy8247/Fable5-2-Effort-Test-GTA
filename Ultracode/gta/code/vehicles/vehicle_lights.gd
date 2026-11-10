class_name VehicleLights
extends RefCounted
## Per-vehicle light state: emissive head / tail / brake / reverse / indicator / siren materials.
## Only the light materials are duplicated per instance. Real light sources (SpotLight3D
## headlights, siren OmniLights) are pooled by VehicleManager and positioned from the
## transforms exposed here.

const HEAD_ENERGY: Array[float] = [0.0, 2.6, 5.0]
const TAIL_RUNNING := 1.1
const TAIL_BRAKE := 4.5
const REVERSE_ENERGY := 3.0
const INDICATOR_ENERGY := 4.0
const SIREN_ENERGY := 7.0
const BLINK_HZ := 1.5
const SIREN_HZ := 3.2

const INDICATOR_SHADER := "
shader_type spatial;
uniform vec4 albedo : source_color = vec4(1.0, 0.62, 0.1, 1.0);
uniform vec3 emission_color : source_color = vec3(1.0, 0.62, 0.1);
uniform float left_on = 0.0;
uniform float right_on = 0.0;
uniform float energy = 4.0;
varying float side;
void vertex() {
	side = VERTEX.x;
}
void fragment() {
	ALBEDO = albedo.rgb * 0.85;
	ROUGHNESS = 0.35;
	float on = side < 0.0 ? left_on : right_on;
	EMISSION = emission_color * energy * on;
}
"

static var _indicator_shader: Shader = null


static func clear_static_caches() -> void:
	_indicator_shader = null

var v: VehicleBase = null
var head_mat: BaseMaterial3D = null
var tail_mat: BaseMaterial3D = null
var reverse_mat: BaseMaterial3D = null
var siren_red_mat: BaseMaterial3D = null
var siren_blue_mat: BaseMaterial3D = null
var indicator_mat: ShaderMaterial = null
var taxi_mat: BaseMaterial3D = null        ## per-instance P_NeonYellow of the taxi roof sign (TaxiSign + LOD)
var head_local: Array[Vector3] = []        ## headlight positions in body space (L, R)
var siren_local: Vector3 = Vector3.ZERO    ## light bar centre in body space
var has_siren_marker: bool = false
var head_color: Color = Color(1.0, 0.95, 0.84)   ## headlamp colour (emissive + pooled SpotLight3D)
var head_broken: bool = false
var tail_broken: bool = false
var siren_phase: int = -1                  ## -1 off, 0 = red side lit, 1 = blue side lit

var _blink_t: float = 0.0
var _siren_t: float = 0.0
var _key: int = -1
var _head_base: Color = Color(1.0, 0.95, 0.84)
var _taxi_energy: float = 3.0


func setup(vehicle: VehicleBase) -> void:
	v = vehicle
	head_mat = _emissive("M_Headlight", Color(1.0, 0.96, 0.86))
	if head_mat != null:
		_head_base = head_mat.emission
		head_color = Color(1.0, 0.95, 0.84).lerp(_head_base, 0.5)
	tail_mat = _emissive("M_Taillight", Color(0.9, 0.08, 0.05))
	reverse_mat = _emissive("M_ReverseLight", Color(1.0, 1.0, 0.95))
	siren_red_mat = _emissive("M_Siren_Red", Color(1.0, 0.1, 0.1))
	siren_blue_mat = _emissive("M_Siren_Blue", Color(0.12, 0.35, 1.0))
	var ind := v.get_original_material("M_Indicator") as BaseMaterial3D
	if ind != null:
		if _indicator_shader == null:
			_indicator_shader = Shader.new()
			_indicator_shader.code = INDICATOR_SHADER
		indicator_mat = ShaderMaterial.new()
		indicator_mat.shader = _indicator_shader
		indicator_mat.resource_name = "M_Indicator"
		indicator_mat.set_shader_parameter("albedo", ind.albedo_color)
		var ec := ind.emission if ind.emission_enabled else ind.albedo_color
		indicator_mat.set_shader_parameter("emission_color", Color(ec.r, ec.g, ec.b))
		indicator_mat.set_shader_parameter("energy", INDICATOR_ENERGY)
		v.set_instance_material("M_Indicator", indicator_mat)
	var a := v.body_aabb
	var c := a.get_center()
	var front_z := a.position.z + 0.08
	var hy := a.position.y + a.size.y * 0.42
	head_local = [
		v.marker_local("Light_Head_L", Vector3(c.x - a.size.x * 0.33, hy, front_z)),
		v.marker_local("Light_Head_R", Vector3(c.x + a.size.x * 0.33, hy, front_z)),
	]
	if v.has_part("TaxiSign") and v.has_material("P_NeonYellow"):
		taxi_mat = v.get_instance_material("P_NeonYellow") as BaseMaterial3D
		if taxi_mat != null:
			_taxi_energy = maxf(taxi_mat.emission_energy_multiplier, 2.0) if taxi_mat.emission_enabled else 3.0
			if not taxi_mat.emission_enabled:
				taxi_mat.emission_enabled = true
				taxi_mat.emission = taxi_mat.albedo_color
	has_siren_marker = v.has_part("Siren")
	siren_local = v.marker_local("Siren", Vector3(c.x, a.position.y + a.size.y + 0.08, c.z))
	refresh()
	_apply(0, false, false, 0, 0, -1)


func _emissive(mat_name: String, fallback: Color) -> BaseMaterial3D:
	var m := v.get_instance_material(mat_name) as BaseMaterial3D
	if m == null:
		return null
	var col := fallback
	if m.emission_enabled and (m.emission.r + m.emission.g + m.emission.b) > 0.05:
		col = m.emission
	elif (m.albedo_color.r + m.albedo_color.g + m.albedo_color.b) > 0.3:
		col = m.albedo_color
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.0
	return m


## Force the next update() to re-apply every material value.
func refresh() -> void:
	_key = -1


func update(delta: float) -> void:
	if v.destroyed:
		if _key != -2:
			_key = -2
			_apply(0, false, false, 0, 0, -1)
		return
	var head := 0 if head_broken else v.headlight_mode
	var brake := v.is_braking() and not tail_broken
	var rev := v.is_reversing()
	var ind := v.indicator
	var blink := 0
	if ind != 0:
		_blink_t += delta
		blink = 1 if fmod(_blink_t * BLINK_HZ, 1.0) < 0.5 else 0
	else:
		_blink_t = 0.0
	if v.siren_on:
		_siren_t += delta
		siren_phase = 0 if fmod(_siren_t * SIREN_HZ, 1.0) < 0.5 else 1
	else:
		_siren_t = 0.0
		siren_phase = -1
	var taxi := 1 if is_taxi_sign_lit() else 0
	var key := head | (int(brake) << 2) | (int(rev) << 3) | ((ind + 1) << 4) | (blink << 7) | ((siren_phase + 1) << 8) | (taxi << 10)
	if key == _key:
		return
	_key = key
	_apply(head, brake, rev, ind, blink, siren_phase, taxi)


## Taxi roof sign: lit while the cab is for hire (VehicleBase.taxi_for_hire), has no fare aboard and
## is running or waiting on the rank (owner_tag "taxi").
func is_taxi_sign_lit() -> bool:
	if taxi_mat == null or not v.taxi_for_hire or v.destroyed or v.has_fare():
		return false
	return v.engine_on or v.owner_tag == "taxi"


func _apply(head: int, brake: bool, rev: bool, ind: int, blink: int, siren: int, taxi: int = 0) -> void:
	if head_mat != null:
		head_mat.emission_energy_multiplier = HEAD_ENERGY[clampi(head, 0, 2)]
	if tail_mat != null:
		tail_mat.emission_energy_multiplier = TAIL_BRAKE if brake else (TAIL_RUNNING if head > 0 else 0.0)
	if reverse_mat != null:
		reverse_mat.emission_energy_multiplier = REVERSE_ENERGY if rev else 0.0
	if indicator_mat != null:
		var on := float(blink)
		indicator_mat.set_shader_parameter("left_on", on if (ind == -1 or ind == 2) else 0.0)
		indicator_mat.set_shader_parameter("right_on", on if (ind == 1 or ind == 2) else 0.0)
	if siren_red_mat != null:
		siren_red_mat.emission_energy_multiplier = SIREN_ENERGY if siren == 0 else 0.0
	if siren_blue_mat != null:
		siren_blue_mat.emission_energy_multiplier = SIREN_ENERGY if siren == 1 else 0.0
	if taxi_mat != null:
		taxi_mat.emission_energy_multiplier = _taxi_energy if taxi > 0 else 0.0


## Headlamp colour from the "lights" mod slot; null restores the authored colour.
func set_head_color(color: Variant) -> void:
	var c := (color as Color) if color is Color else _head_base
	head_color = c if color is Color else Color(1.0, 0.95, 0.84).lerp(_head_base, 0.5)
	if head_mat != null:
		head_mat.emission = c
		if color is Color:
			head_mat.albedo_color = Color(c.r, c.g, c.b, head_mat.albedo_color.a)
		else:
			var orig := v.get_original_material("M_Headlight") as BaseMaterial3D
			if orig != null:
				head_mat.albedo_color = orig.albedo_color
	refresh()


func is_headlight_on() -> bool:
	return v.headlight_mode > 0 and not head_broken and not v.destroyed


## World transform for a pooled SpotLight3D. side: 0 left, 1 right, 2 centre.
func get_headlight_transform(side: int) -> Transform3D:
	var p := head_local[0].lerp(head_local[1], 0.5) if side == 2 else head_local[clampi(side, 0, 1)]
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-4.0))
	return v.global_transform * Transform3D(tilt, p + Vector3(0.0, 0.0, -0.12))


## World position for the pooled siren OmniLight of the given colour (0 red, 1 blue).
func get_siren_light_position(which: int) -> Vector3:
	var off := -0.32 if which == 0 else 0.32
	return v.global_transform * (siren_local + Vector3(off, 0.18, 0.0))


func set_broken(head: bool, tail: bool) -> void:
	head_broken = head
	tail_broken = tail
	refresh()
