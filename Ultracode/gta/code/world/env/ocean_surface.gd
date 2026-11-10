class_name OceanSurface
extends Node3D
## ENVIRONMENT module helper: the sea around Halcyon Bay.
##
## One camera-following mesh (one draw call, 70,688 triangles): a tensor-product grid whose cells
## are FINE_CELL (2 m) wide inside +-FINE_HALF and grow geometrically out to +-FAR_EXTENT, so the
## surface is finely tessellated where the waves are and a plain plane out to the horizon, with
## no T-junctions and no cracks. The mesh snaps to the fine cell, shading is in world space.
##
## The vertex waves are a sum of four sines (total amplitude = wave_amp <= MAX_WAVE_AMP 0.25 m).
## `get_height(x, z)` evaluates the SAME vertices and the same triangles on the CPU for boats and
## swimmers; the constants below must stay identical to gta/code/world/shaders/env_ocean.gdshader
## (the env_cycle test parses the shader source and compares them).
## Created and driven by EnvironmentSystem (use Game.get_system("environment").get_wave_height).

const OCEAN_SHADER: Shader = preload("res://gta/code/world/shaders/env_ocean.gdshader")

const FINE_CELL := 2.0
const FINE_HALF := 80.0            ## half extent of the uniform 2 m region
const FAR_EXTENT := 12000.0        ## the plane reaches this far from the camera
const GROWTH := 1.13               ## cell growth factor outside the fine region
const WAVE_FADE_START := 58.0      ## geometry waves fade out between these camera distances
const WAVE_FADE_END := 76.0
const MAX_WAVE_AMP := 0.25
const CALM_WAVE_AMP := 0.10

# Wave set - keep identical to the shader (W_D*, W_K*, W_S*, weights, phases).
const WAVE_DIR: Array[Vector2] = [Vector2(0.9397, 0.3420), Vector2(0.6157, -0.7880),
		Vector2(-0.3584, 0.9336), Vector2(0.9848, -0.1736)]
const WAVE_K: Array[float] = [0.27318, 0.48332, 0.86071, 1.42800]
const WAVE_SPEED: Array[float] = [0.95, 1.28, 1.72, 2.25]
const WAVE_WEIGHT: Array[float] = [0.42, 0.28, 0.18, 0.12]
const WAVE_PHASE: Array[float] = [0.0, 1.3, 2.1, 4.2]

var water_level: float = 0.0
var wave_amp: float = CALM_WAVE_AMP          ## current total amplitude in metres
var wave_time: float = 0.0                   ## same clock as the global uniform gta_time
var wave_center := Vector2.ZERO              ## camera xz (geometry waves fade around it)
var material: ShaderMaterial
var mesh_instance: MeshInstance3D


func _ready() -> void:
	_build()


func _build() -> void:
	if mesh_instance != null:
		return
	water_level = Game.WATER_LEVEL
	material = ShaderMaterial.new()
	material.shader = OCEAN_SHADER
	# Draw before every other transparent thing (glass, particles) so they sort over the water.
	material.render_priority = -20
	material.set_shader_parameter(&"facet_size", FINE_CELL)
	material.set_shader_parameter(&"wave_fade_start", WAVE_FADE_START)
	material.set_shader_parameter(&"wave_fade_end", WAVE_FADE_END)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "OceanMesh"
	mesh_instance.mesh = _build_mesh()
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mesh_instance.extra_cull_margin = 2.0
	mesh_instance.add_to_group(&"water_surface")
	add_child(mesh_instance)
	position = Vector3(0.0, water_level, 0.0)


## 1D vertex coordinates: uniform FINE_CELL steps inside the fine region, then growing steps.
static func _axis_coords() -> PackedFloat32Array:
	var half: Array[float] = []
	var x := 0.0
	while x < FINE_HALF - 0.001:
		x += FINE_CELL
		half.append(x)
	var step := FINE_CELL
	while x < FAR_EXTENT:
		step *= GROWTH
		x += step
		half.append(x)
	var out := PackedFloat32Array()
	for i in range(half.size() - 1, -1, -1):
		out.append(-half[i])
	out.append(0.0)
	for v in half:
		out.append(v)
	return out


static func _build_mesh() -> ArrayMesh:
	var axis := _axis_coords()
	var n := axis.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(n * n)
	normals.resize(n * n)
	for j in n:
		for i in n:
			verts[j * n + i] = Vector3(axis[i], 0.0, axis[j])
			normals[j * n + i] = Vector3.UP
	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i           # (i, j)
			var b := a + 1               # (i+1, j)
			var c := a + n               # (i, j+1)
			var d := c + 1               # (i+1, j+1)
			# Split along the (i+1, j)-(i, j+1) diagonal: matches the facet grid of the shader.
			# Winding is clockwise seen from above (+Y) = front faces up in Godot.
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = d
			indices[k + 4] = c
			indices[k + 5] = b
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-FAR_EXTENT * 1.2, -2.0, -FAR_EXTENT * 1.2),
			Vector3(FAR_EXTENT * 2.4, 4.0, FAR_EXTENT * 2.4))
	return mesh


## Follows the camera (snapped to the fine cell so vertices never swim) and refreshes uniforms.
## `amp` is the total wave amplitude in metres (clamped to MAX_WAVE_AMP); `time_s` must be the
## value written to the global uniform gta_time in the same frame.
func update_surface(cam_pos: Vector3, time_s: float, amp: float) -> void:
	wave_time = time_s
	wave_amp = clampf(amp, 0.0, MAX_WAVE_AMP)
	wave_center = Vector2(cam_pos.x, cam_pos.z)
	if mesh_instance == null:
		return
	# World-space snap: get_height() relies on the vertices sitting on the world lattice.
	var snapped_pos := Vector3(snappedf(cam_pos.x, FINE_CELL), water_level, snappedf(cam_pos.z, FINE_CELL))
	if is_inside_tree():
		global_transform = Transform3D(Basis.IDENTITY, snapped_pos)
	else:
		position = snapped_pos
	material.set_shader_parameter(&"wave_amp", wave_amp)
	material.set_shader_parameter(&"wave_center", wave_center)


func set_colors(shallow: Color, mid: Color, deep: Color, foam: Color, sky_tint: Color,
		tint_strength: float, whitecaps: float, clarity: float) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"shallow_color", shallow)
	material.set_shader_parameter(&"mid_color", mid)
	material.set_shader_parameter(&"deep_color", deep)
	material.set_shader_parameter(&"foam_color", foam)
	material.set_shader_parameter(&"sky_tint", sky_tint)
	material.set_shader_parameter(&"sky_tint_strength", tint_strength)
	material.set_shader_parameter(&"whitecaps", whitecaps)
	material.set_shader_parameter(&"clarity", clarity)


## Unit wave in [-1, 1] - mirror of wave_unit() in the shader.
func wave_unit(x: float, z: float, t: float) -> float:
	var h := 0.0
	for i in 4:
		var d := WAVE_DIR[i]
		h += WAVE_WEIGHT[i] * sin((x * d.x + z * d.y) * WAVE_K[i] + t * WAVE_SPEED[i] + WAVE_PHASE[i])
	return h


## Wave offset (metres) of the mesh vertex at world (x, z) - mirror of vertex() in the shader.
## Only meaningful on the FINE_CELL lattice, where the mesh really has vertices.
func vertex_offset(x: float, z: float) -> float:
	var dx := x - wave_center.x
	var dz := z - wave_center.y
	var d2 := dx * dx + dz * dz
	if d2 >= WAVE_FADE_END * WAVE_FADE_END:
		return 0.0
	var fade := 1.0 - smoothstep(WAVE_FADE_START, WAVE_FADE_END, sqrt(d2))
	return wave_unit(x, z, wave_time) * wave_amp * fade


## World Y of the water surface at (x, z) including the waves.
## This is the RENDERED surface, not the ideal sine sum: the mesh has a vertex every FINE_CELL
## metres (always on the world lattice, because the mesh snaps to it) and flat triangles in
## between, split along the (x+1, z)-(x, z+1) diagonal. The shortest wave (4.4 m) is only just
## resolved by that grid, so the sine sum itself would be up to ~5 cm off the pixels in a storm;
## interpolating the same three vertices keeps boats and swimmers exactly on the visible water.
## Verified against the GPU by the env_waves test.
func get_height(x: float, z: float) -> float:
	var dx := x - wave_center.x
	var dz := z - wave_center.y
	var reach := WAVE_FADE_END + FINE_CELL * 1.5
	if dx * dx + dz * dz >= reach * reach:
		return water_level
	var gx := x / FINE_CELL
	var gz := z / FINE_CELL
	var ix := floorf(gx)
	var iz := floorf(gz)
	var fx := gx - ix
	var fz := gz - iz
	var x0 := ix * FINE_CELL
	var z0 := iz * FINE_CELL
	var x1 := x0 + FINE_CELL
	var z1 := z0 + FINE_CELL
	var hb := vertex_offset(x1, z0)
	var hc := vertex_offset(x0, z1)
	if fx + fz < 1.0:
		var ha := vertex_offset(x0, z0)
		return water_level + ha + (hb - ha) * fx + (hc - ha) * fz
	var hd := vertex_offset(x1, z1)
	return water_level + hd + (hc - hd) * (1.0 - fx) + (hb - hd) * (1.0 - fz)


## The ideal (unfaceted) wave height at (x, z): the sine sum the mesh samples. Differs from
## get_height() by a few centimetres at most; use get_height() for anything that must touch
## the visible surface.
func get_smooth_height(x: float, z: float) -> float:
	var dx := x - wave_center.x
	var dz := z - wave_center.y
	var dist := sqrt(dx * dx + dz * dz)
	if dist >= WAVE_FADE_END:
		return water_level
	var fade := 1.0 - smoothstep(WAVE_FADE_START, WAVE_FADE_END, dist)
	return water_level + wave_unit(x, z, wave_time) * wave_amp * fade


## Approximate surface normal at (x, z) (for aligning boats to the swell).
func get_normal(x: float, z: float) -> Vector3:
	var e := 1.0
	var hx := get_height(x + e, z) - get_height(x - e, z)
	var hz := get_height(x, z + e) - get_height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()
