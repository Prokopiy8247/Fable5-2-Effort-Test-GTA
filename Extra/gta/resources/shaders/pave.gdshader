shader_type spatial;
// Tiled pavement / concrete / roof surfaces generated in code (world-space tiling, rain wetness).
global uniform float wetness;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 color : source_color = vec3(0.72, 0.70, 0.66);
uniform float tile = 2.0;
uniform float line_strength = 0.18;
uniform float rough = 0.9;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(noise_tex, wpos.xz * 0.045).r;
	float n2 = texture(noise_tex, wpos.xz * 0.5 + 1.3).r;
	vec2 g = abs(fract(wpos.xz / tile) - 0.5);
	float aa = fwidth(wpos.x / tile) * 1.5 + 0.004;
	float ln = (1.0 - smoothstep(0.5 - 0.018 - aa, 0.5 - 0.018, max(g.x, g.y))) ;
	float seam = 1.0 - ln;
	vec3 c = color * (0.86 + 0.24 * n) * (0.94 + 0.12 * n2);
	c *= 1.0 - seam * line_strength * step(0.01, line_strength);
	float wet = wetness * (0.5 + 0.5 * n);
	ALBEDO = c * mix(1.0, 0.68, wet);
	ROUGHNESS = mix(rough, 0.3, wet);
	SPECULAR = 0.4;
}
