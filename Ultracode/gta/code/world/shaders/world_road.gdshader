shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// HALCYON BAY asphalt + road paint. Vertex colour = base colour (authored in sRGB).
// paint = 0: asphalt (grain, patches, tar seams, rain puddles), paint = 1: markings (worn paint).
// Darkens and turns glossy with the global wetness uniform.

uniform float paint = 0.0;
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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float dist = length(VERTEX);
	float detail = 1.0 - smoothstep(25.0, 90.0, dist);          // fade fine grain with distance (no shimmer)
	float patches = fbm(wpos.xz * 0.06);
	float mid = fbm(wpos.xz * 0.45 + 31.0);
	float grain = vnoise(wpos.xz * 9.0);
	float wet = gta_wetness;
	vec3 col;
	float rough;
	if (paint < 0.5) {
		col = base * (0.84 + 0.22 * patches + 0.10 * (mid - 0.5));
		col *= 1.0 + (grain - 0.5) * 0.22 * detail;
		// repaired patches: slightly darker, soft-edged blotches
		float patch_m = smoothstep(0.66, 0.70, fbm(wpos.xz * 0.11 + 73.0));
		col *= mix(1.0, 0.86, patch_m);
		float puddle = smoothstep(0.52, 0.66, fbm(wpos.xz * 0.16 + 5.0)) * wet;
		col *= mix(1.0, 0.62, wet);
		rough = mix(0.93, mix(0.42, 0.06, puddle), wet);
	} else {
		float wear = smoothstep(0.55, 0.85, fbm(wpos.xz * 1.3 + 11.0)) * 0.45;
		col = mix(base, base * 0.45, wear * detail);
		col *= 0.93 + 0.10 * mid;
		col *= mix(1.0, 0.78, wet);
		rough = mix(0.80, 0.30, wet);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
