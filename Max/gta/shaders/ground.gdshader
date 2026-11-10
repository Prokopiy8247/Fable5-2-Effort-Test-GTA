// Generated ground surfaces (terrain, sidewalks, lots, plazas, boardwalk).
// Vertex COLOR = linear base colour. UV.x = pattern id, UV.y = rain response.
//   0 plain   1 paving tiles   2 planks   3 grass   4 sand   5 concrete slabs   6 asphalt lot
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;

global uniform float wetness;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid_line(vec2 p, vec2 cell, float w) {
	vec2 g = abs(fract(p / cell) - 0.5) * cell;
	vec2 aa = fwidth(p) * 0.75 + 0.001;
	vec2 l = 1.0 - smoothstep(vec2(w) - aa, vec2(w) + aa, (cell * 0.5) - g);
	return max(l.x, l.y);
}

void fragment() {
	vec3 col = COLOR.rgb;
	float n = texture(noise_tex, wpos.xz * 0.023).r;
	float n2 = texture(noise_tex, wpos.xz * 0.19).r;
	float cells = texture(detail_tex, wpos.xz * 0.11).r;
	int pat = int(UV.x + 0.5);
	float rough = 0.93;
	float fade = 1.0 - smoothstep(60.0, 140.0, length(wpos - CAMERA_POSITION_WORLD));
	if (pat == 1) {
		col *= 0.9 + 0.2 * n2;
		col *= 1.0 - 0.22 * grid_line(wpos.xz, vec2(1.5, 1.5), 0.02) * fade;
		col *= 0.93 + 0.14 * step(0.5, fract(floor(wpos.x / 1.5) * 0.37 + floor(wpos.z / 1.5) * 0.61));
	} else if (pat == 2) {
		float board = floor(wpos.x / 0.28);
		col *= 0.82 + 0.3 * fract(sin(board * 12.9898) * 43758.5453);
		col *= 1.0 - 0.3 * grid_line(wpos.xz, vec2(0.28, 3.4), 0.012) * fade;
		rough = 0.85;
	} else if (pat == 3) {
		col *= 0.8 + 0.42 * n;
		col *= 0.9 + 0.2 * n2;
		col = mix(col, col * vec3(1.12, 1.1, 0.8), smoothstep(0.55, 0.8, cells) * 0.35);
		rough = 0.97;
	} else if (pat == 4) {
		col *= 0.9 + 0.16 * n;
		col *= 0.95 + 0.1 * sin(wpos.z * 2.2 + n2 * 9.0) * fade;
		rough = 0.95;
	} else if (pat == 5) {
		col *= 0.9 + 0.2 * n;
		col *= 1.0 - 0.2 * grid_line(wpos.xz, vec2(4.0, 4.0), 0.03) * fade;
		col *= 0.95 + 0.1 * n2;
	} else if (pat == 6) {
		col *= 0.8 + 0.4 * n;
		col *= 1.0 - 0.3 * smoothstep(0.06, 0.0, abs(cells - 0.5)) * smoothstep(0.4, 0.7, n2);
	} else {
		col *= 0.9 + 0.2 * n;
	}
	float wet = wetness * UV.y * smoothstep(0.4, 0.9, wnrm.y);
	float puddle = smoothstep(0.56, 0.7, n * 0.6 + n2 * 0.4) * wet * ((pat == 3 || pat == 4) ? 0.0 : 1.0);
	col *= mix(1.0, 0.68, wet * 0.8);
	rough = mix(rough, 0.45, wet * 0.7);
	rough = mix(rough, 0.05, puddle);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
