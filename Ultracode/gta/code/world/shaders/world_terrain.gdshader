shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// HALCYON BAY terrain: faceted low-poly ground blended from vertex masks, height and slope.
// Vertex colour: R = sand mask, G = dirt mask (tracks / pads), B = 1 on the flat city plateau.
// No image textures - procedural value noise only.

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

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// flat (faceted) normal from screen-space derivatives of the view-space position
	vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(fn, VIEW) < 0.0) {
		fn = -fn;
	}
	NORMAL = fn;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(fn, 0.0)).xyz);
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);

	float n_big = fbm(wpos.xz * 0.035);
	float n_mid = fbm(wpos.xz * 0.21 + 9.0);
	float n_fine = vnoise(wpos.xz * 1.7);

	float sand_m = COLOR.r;
	float dirt_m = COLOR.g;
	float city_m = COLOR.b;
	float h = wpos.y;

	// grass: lush on the hill, a little drier and trimmed on the city plateau
	vec3 g_wild = mix(vec3(0.27, 0.47, 0.19), vec3(0.47, 0.61, 0.25), n_big);
	g_wild = mix(g_wild, vec3(0.60, 0.63, 0.30), smoothstep(0.55, 0.9, n_mid) * 0.35);
	vec3 g_city = mix(vec3(0.40, 0.58, 0.25), vec3(0.50, 0.64, 0.29), n_mid);
	vec3 grass = mix(g_wild, g_city, city_m);
	grass *= 0.93 + 0.14 * n_fine;

	vec3 sand = mix(vec3(0.90, 0.80, 0.58), vec3(0.83, 0.72, 0.50), n_mid);
	sand *= 0.95 + 0.10 * n_fine;
	vec3 dirt = mix(vec3(0.56, 0.43, 0.29), vec3(0.47, 0.36, 0.25), n_mid);
	dirt *= 0.90 + 0.20 * n_fine;
	vec3 rock = mix(vec3(0.55, 0.51, 0.46), vec3(0.43, 0.41, 0.39), n_mid);

	vec3 col = grass;
	// upper hill gets drier / rockier
	col = mix(col, mix(grass, vec3(0.62, 0.60, 0.36), 0.45), smoothstep(22.0, 36.0, h) * (1.0 - city_m));
	col = mix(col, sand, clamp(sand_m * 1.25 + (n_mid - 0.5) * 0.3 * step(0.02, sand_m), 0.0, 1.0));
	col = mix(col, dirt, clamp(dirt_m * 1.3 - 0.1 + (n_fine - 0.5) * 0.35 * step(0.02, dirt_m), 0.0, 1.0));
	float rock_m = smoothstep(0.30, 0.48, slope + (n_mid - 0.5) * 0.12) * (1.0 - city_m);
	col = mix(col, rock, rock_m * (1.0 - dirt_m));
	// shoreline: wet sand band just above the water, seabed below
	float shore = 1.0 - smoothstep(0.15, 0.9, h);
	col = mix(col, mix(sand, vec3(0.66, 0.58, 0.42), 0.6), shore * (1.0 - rock_m * 0.6));
	float depth = clamp(-h / 13.0, 0.0, 1.0);
	vec3 seabed = mix(vec3(0.74, 0.69, 0.50), vec3(0.20, 0.33, 0.34), smoothstep(0.0, 0.85, depth));
	seabed *= 0.9 + 0.2 * n_mid;
	col = mix(col, seabed, smoothstep(0.05, -0.6, h));

	float wet = gta_wetness * step(0.0, h);
	col *= mix(1.0, 0.72, wet);
	ALBEDO = srgb(col);
	ROUGHNESS = mix(0.96, 0.62, wet);
	SPECULAR = 0.25;
	METALLIC = 0.0;
}
