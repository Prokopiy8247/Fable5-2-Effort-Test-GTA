// Procedural asphalt + road markings. Meshes come from road_builder.gd:
//   UV  = (lateral metres from the centre line, metres along the segment)
//   UV2 = (road type, segment length)      COLOR.rgb = (crosswalk at start, crosswalk at end, half width / 16)
// types: 0 plain  1 street  2 arterial  3 hill road  4 runway  5 taxiway  6 apron/lot
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 asphalt : source_color = vec3(0.19, 0.2, 0.225);
uniform vec3 paint_white : source_color = vec3(0.86, 0.86, 0.82);
uniform vec3 paint_yellow : source_color = vec3(0.9, 0.7, 0.16);

global uniform float wetness;

varying vec3 wpos;
varying float rtype;
varying float rlen;
varying vec3 flags;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	rtype = UV2.x;
	rlen = UV2.y;
	flags = COLOR.rgb;
}

float stripe(float x, float center, float halfw) {
	float d = abs(x - center);
	float aa = fwidth(x) * 0.75 + 0.002;
	return 1.0 - smoothstep(halfw - aa, halfw + aa, d);
}

float band(float v, float a, float b) {
	float aa = fwidth(v) * 0.75 + 0.002;
	return smoothstep(a - aa, a + aa, v) * (1.0 - smoothstep(b - aa, b + aa, v));
}

float dash(float y, float period, float duty) {
	float f = fract(y / period);
	float aa = fwidth(y / period) * 0.75 + 0.0005;
	return smoothstep(0.0, aa, f) * (1.0 - smoothstep(duty - aa, duty + aa, f));
}

void fragment() {
	float x = UV.x;
	float y = UV.y;
	float hw = flags.b * 16.0;
	float n = texture(noise_tex, wpos.xz * 0.021).r;
	float n2 = texture(noise_tex, wpos.xz * 0.17).r;
	float cells = texture(detail_tex, wpos.xz * 0.09).r;
	vec3 col = asphalt * (0.78 + 0.5 * n) * (0.9 + 0.2 * n2);
	// cracks / patch repairs
	float crack = smoothstep(0.06, 0.0, abs(cells - 0.5)) * smoothstep(0.45, 0.75, n2);
	col *= 1.0 - 0.35 * crack;
	float white = 0.0;
	float yellow = 0.0;
	int t = int(rtype + 0.5);
	float d_start = y;
	float d_end = rlen - y;
	float d_min = min(d_start, d_end);
	float has_cw = (d_start < d_end) ? flags.r : flags.g;
	float clear_zone = mix(1.0, smoothstep(5.2, 5.6, d_min), has_cw);   // no lane lines over crossings
	if (t == 1) {
		yellow = max(stripe(x, -0.15, 0.055), stripe(x, 0.15, 0.055)) * clear_zone;
		white = max(stripe(x, -3.55, 0.05), stripe(x, 3.55, 0.05)) * dash(y, 7.0, 0.45) * clear_zone;
		// tyre-worn lane centres are slightly darker/glossier
		col *= 1.0 - 0.1 * max(stripe(x, -1.85, 0.9), stripe(x, 1.85, 0.9));
	} else if (t == 2) {
		yellow = max(stripe(x, -0.45, 0.07), stripe(x, 0.45, 0.07)) * clear_zone;
		yellow = max(yellow, band(abs(x), 0.0, 0.38) * dash(y + x * 1.2, 2.4, 0.35) * 0.9 * clear_zone);
		white = max(stripe(x, -4.5, 0.06), stripe(x, 4.5, 0.06)) * dash(y, 9.0, 0.4) * clear_zone;
		white = max(white, max(stripe(x, -8.2, 0.07), stripe(x, 8.2, 0.07)) * clear_zone);
		col *= 1.0 - 0.1 * max(max(stripe(x, -2.6, 0.8), stripe(x, 2.6, 0.8)), max(stripe(x, -6.3, 0.8), stripe(x, 6.3, 0.8)));
	} else if (t == 3) {
		yellow = stripe(x, 0.0, 0.06) * dash(y, 8.0, 0.5);
		white = max(stripe(x, -(hw - 0.5), 0.05), stripe(x, hw - 0.5, 0.05));
	} else if (t == 4) {
		white = max(stripe(x, -(hw - 0.9), 0.22), stripe(x, hw - 0.9, 0.22));
		white = max(white, stripe(x, 0.0, 0.3) * dash(y + 4.0, 24.0, 0.55) * smoothstep(34.0, 36.0, d_min));
		// threshold "piano keys" and aiming-point blocks
		float keys = band(d_min, 6.0, 26.0) * dash(x + 0.9, 1.8, 0.5) * band(abs(x), 0.0, hw - 2.0);
		float aim = band(d_min, 70.0, 92.0) * band(abs(x), 3.0, 6.4);
		white = max(white, max(keys, aim));
	} else if (t == 5) {
		yellow = stripe(x, 0.0, 0.09);
		yellow = max(yellow, max(stripe(x, -(hw - 0.5), 0.07), stripe(x, hw - 0.5, 0.07)) * dash(y, 3.0, 0.5));
	}
	if (t == 1 || t == 2) {
		// zebra crossing + stop line for the approaching lanes
		float zebra = band(d_min, 0.7, 3.7) * dash(x + 0.25, 1.0, 0.5) * band(abs(x), 0.0, hw - 0.3);
		float approach = (d_start < d_end) ? step(x, -0.2) : step(0.2, x);
		float stopl = band(d_min, 4.4, 4.85) * approach * band(abs(x), 0.2, hw - (t == 1 ? 2.1 : 0.9));
		white = max(white, max(zebra, stopl) * has_cw);
	}
	float wear = 0.72 + 0.28 * smoothstep(0.25, 0.7, cells);
	white *= wear;
	yellow *= wear;
	col = mix(col, paint_white, clamp(white, 0.0, 1.0));
	col = mix(col, paint_yellow, clamp(yellow, 0.0, 1.0));
	float paint = clamp(max(white, yellow), 0.0, 1.0);
	// rain: general gloss + puddles in the low-frequency noise valleys
	float puddle = smoothstep(0.52, 0.66, n * 0.65 + n2 * 0.35) * wetness;
	float rough = mix(0.93, 0.62, paint);
	rough = mix(rough, 0.38, wetness * 0.8);
	rough = mix(rough, 0.04, puddle);
	col *= mix(1.0, 0.62, wetness * 0.8);
	col = mix(col, col * 0.55, puddle);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.4, 0.7, puddle);
}
