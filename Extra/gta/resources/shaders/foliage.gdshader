shader_type spatial;
render_mode cull_disabled;
// Low-poly foliage with a cheap wind sway.
global uniform float wind_time;
uniform vec3 albedo : source_color = vec3(0.3, 0.6, 0.3);
uniform float sway = 0.05;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = max(VERTEX.y - 0.4, 0.0) * sway;
	VERTEX.x += sin(wind_time * 1.3 + w.x * 0.35 + w.z * 0.2) * k;
	VERTEX.z += cos(wind_time * 1.1 + w.z * 0.3) * k * 0.6;
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.9;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
