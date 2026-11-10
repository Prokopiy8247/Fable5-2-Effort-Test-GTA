// Building window panes. By day: dark reflective glass. By night a stable per-window hash
// decides which windows are lit, with warm/cool variation and simple blinds.
shader_type spatial;
// per-instance slots are allocated project-wide (see DEVELOPMENT.md): 0-3 palette, 4-8 paint, 9-10 glass, 11-12 lamps, 13 window, 14 signal
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 glass_color : source_color = vec3(0.07, 0.11, 0.16);
uniform vec3 warm : source_color = vec3(1.0, 0.82, 0.55);
uniform vec3 cool : source_color = vec3(0.75, 0.88, 1.0);
uniform float lit_bias = 0.0;
// x = module width (x/z cell), y = storey height, z = height of the first storey boundary offset
instance uniform vec3 win_cell : instance_index(13) = vec3(4.0, 3.5, 1.0);

global uniform float night_factor;
global uniform float window_lit_ratio;

varying vec3 cell_pos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	// World-space cell position (buildings are snapped to the module grid). Pull the sample
	// point half a metre inside the facade so floor() is stable on wall planes.
	cell_pos = (MODEL_MATRIX * vec4(VERTEX - NORMAL * 0.5, 1.0)).xyz;
}

void fragment() {
	float yc = max(cell_pos.y - win_cell.z, 0.0);
	vec3 id = vec3(floor(cell_pos.x / win_cell.x), floor(yc / win_cell.y), floor(cell_pos.z / win_cell.x));
	float h = hash13(id + vec3(17.0, 3.0, 5.0));
	float h2 = hash13(id.zxy + vec3(1.7, 9.2, 4.4));
	float lit = step(1.0 - clamp(window_lit_ratio + lit_bias, 0.0, 1.0), h) * night_factor;
	// blinds: some windows have the top part covered
	float blind = step(UV.y, 0.25 + 0.5 * h2) * step(0.6, h2);
	vec3 light_col = mix(warm, cool, step(0.72, h2));
	// faint interior gradient so lit windows are not flat cards
	float grad = mix(0.75, 1.15, UV.y) * mix(1.0, 0.55, blind);
	ALBEDO = mix(glass_color, glass_color * 0.4, lit);
	ROUGHNESS = 0.08;
	METALLIC = 0.55;
	SPECULAR = 0.6;
	EMISSION = light_col * lit * grad * (1.3 + 0.8 * h);
}
