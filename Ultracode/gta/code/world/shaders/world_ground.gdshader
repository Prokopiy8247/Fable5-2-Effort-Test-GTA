shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// HALCYON BAY paved ground (sidewalks, kerbs, block slabs, plazas, decks, piers, lawns).
// Vertex colour rgb = base colour (sRGB), alpha = pattern id:
//   0.0 plain concrete   0.2 sidewalk slabs (1.5 m joints)   0.4 pavers (herringbone-ish bricks)
//   0.6 plaza tiles (1.2 m, two tones)   0.8 planks with joints at constant z   0.9 planks at constant x
//   1.0 lawn
// Procedural only; joints are anti-aliased and fade with distance.

global uniform float gta_wetness;

varying vec3 wpos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 17.0) * 0.3 + vnoise(p * 4.7 + 41.0) * 0.15;
}

// 1 on the joint lines of a grid with the given cell size (x and y), anti-aliased.
float joints(vec2 p, vec2 cell, float w) {
	vec2 g = abs(fract(p / cell - 0.5) - 0.5) * cell;
	vec2 fw = fwidth(p) * 1.2 + 0.0005;
	vec2 a = 1.0 - smoothstep(vec2(w), vec2(w) + fw, g);
	vec2 fade = 1.0 - clamp(fw / (cell * 0.16), 0.0, 1.0);
	return max(a.x * fade.x, a.y * fade.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float id = COLOR.a;
	vec2 p = wpos.xz;
	float big = fbm(p * 0.05);
	float mid = fbm(p * 0.5 + 19.0);
	float dist = length(VERTEX);
	float detail = 1.0 - smoothstep(30.0, 110.0, dist);
	float px = max(fwidth(p.x), fwidth(p.y));               // world size of one pixel: fades sub-pixel patterns
	vec3 col = base * (0.90 + 0.14 * big);
	float rough = 0.9;
	float wet = gta_wetness;
	if (id < 0.1) {
		col *= 0.96 + 0.08 * mid;
	} else if (id < 0.3) {
		float j = joints(p, vec2(1.5), 0.018);
		float tone = hash21(floor(p / 1.5));
		float lod = 1.0 - clamp(px / 0.6, 0.0, 1.0);
		col *= 0.95 + 0.07 * tone * lod + 0.035 * (1.0 - lod);
		col = mix(col, col * 0.62, j);
	} else if (id < 0.5) {
		vec2 q = p;
		q.x += step(1.0, mod(floor(p.y / 0.3), 2.0)) * 0.3;
		float j = joints(q, vec2(0.6, 0.3), 0.012);
		float tone = hash21(floor(q / vec2(0.6, 0.3)));
		float lod = 1.0 - clamp(px / 0.12, 0.0, 1.0);
		col *= 0.88 + 0.22 * tone * lod + 0.11 * (1.0 - lod);
		col = mix(col, col * 0.6, j);
	} else if (id < 0.7) {
		float j = joints(p, vec2(1.2), 0.02);
		vec2 c = floor(p / 1.2);
		float chk = mod(c.x + c.y, 2.0);
		float lod = 1.0 - clamp(px / 0.5, 0.0, 1.0);
		col *= mix(0.93, 1.05, chk * lod + 0.5 * (1.0 - lod));
		col = mix(col, col * 0.6, j);
	} else if (id < 0.95) {
		float axis_x = step(0.85, id);
		float u = mix(p.y, p.x, axis_x);
		float v = mix(p.x, p.y, axis_x);
		float board = floor(u / 0.24);
		float j = joints(vec2(u, v + hash21(vec2(board, 3.0)) * 3.0), vec2(0.24, 3.4), 0.012);
		float tone = hash21(vec2(board, 7.0));
		float lod = 1.0 - clamp(px / 0.10, 0.0, 1.0);
		col *= 0.84 + 0.26 * tone * lod + 0.13 * (1.0 - lod);
		col = mix(col, col * 0.45, j);
		rough = 0.85;
	} else {
		vec3 g2 = base * vec3(1.18, 1.08, 0.95);
		col = mix(base * 0.86, g2, fbm(p * 0.35 + 3.0));
		col *= 0.93 + 0.14 * vnoise(p * 2.3);
		rough = 0.96;
	}
	col *= mix(1.0, 0.70, wet);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.35, wet * 0.8);
	SPECULAR = 0.4;
	METALLIC = 0.0;
}
