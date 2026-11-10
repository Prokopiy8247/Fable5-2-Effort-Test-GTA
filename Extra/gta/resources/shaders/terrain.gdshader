shader_type spatial;
// Faceted low-poly terrain: grass / sand / rock / seabed chosen from height, slope and vertex masks.
// COLOR.r = sand mask, COLOR.g = dirt path mask
global uniform float wetness;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 fn = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(fn, 0.0)).xyz);
	float n = texture(noise_tex, wpos.xz * 0.02).r;
	float n2 = texture(noise_tex, wpos.xz * 0.19).r;
	vec3 grass = mix(vec3(0.30, 0.50, 0.22), vec3(0.45, 0.62, 0.27), n) * (0.9 + 0.2 * n2);
	vec3 sand = vec3(0.86, 0.77, 0.55) * (0.88 + 0.22 * n2);
	vec3 rock = vec3(0.50, 0.48, 0.45) * (0.75 + 0.45 * n2);
	vec3 seabed = vec3(0.33, 0.42, 0.36) * (0.8 + 0.4 * n);
	vec3 pathc = vec3(0.52, 0.42, 0.29) * (0.85 + 0.3 * n2);
	float slope = 1.0 - wn.y;
	vec3 c = grass;
	c = mix(c, sand, COLOR.r);
	c = mix(c, rock, smoothstep(0.22, 0.42, slope) * (1.0 - COLOR.r * 0.7));
	c = mix(c, pathc, COLOR.g);
	c = mix(c, seabed, smoothstep(-2.5, -6.5, wpos.y));
	NORMAL = fn;
	ALBEDO = c * mix(1.0, 0.8, wetness);
	ROUGHNESS = mix(0.95, 0.6, wetness);
}
