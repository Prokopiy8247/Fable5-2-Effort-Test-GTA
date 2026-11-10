shader_type spatial;
// Building glass: random warm-lit windows at night (driven by the global night_factor).
global uniform float night_factor;
uniform vec3 glass_color : source_color = vec3(0.2, 0.33, 0.42);
uniform vec3 lit_color : source_color = vec3(1.0, 0.80, 0.48);
uniform float lit_ratio = 0.42;
varying float inst_rand;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	inst_rand = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(UV * vec2(0.75, 1.0));
	float r = hash(cell + inst_rand * 57.0);
	float r2 = hash(cell * 1.7 + inst_rand * 13.0);
	float lit = step(1.0 - lit_ratio, r) * night_factor;
	vec3 warm = mix(lit_color, vec3(0.72, 0.88, 1.0), step(0.82, r2));
	ALBEDO = mix(glass_color, glass_color * 0.35, night_factor * 0.7);
	METALLIC = 0.55;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	EMISSION = warm * lit * (0.7 + r2 * 0.9);
}
