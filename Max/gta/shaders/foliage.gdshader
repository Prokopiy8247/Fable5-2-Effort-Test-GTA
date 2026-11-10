// Leaves, palm fronds, grass, reeds, kelp ("Foliage" material from Blender, palette-coloured).
// Double-sided, wind sway that grows with height above the asset origin and with the global
// wind strength, soft back-lighting, darker and glossier when the weather is wet.
shader_type spatial;
// per-instance slots are allocated project-wide (see DEVELOPMENT.md): 0-3 palette, 4-8 paint, 9-10 glass, 11-12 lamps, 13 window, 14 signal
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D pal_albedo : source_color, filter_nearest, repeat_disable;
uniform float sway = 0.05;
uniform float flutter = 0.025;

instance uniform vec4 tint_a : instance_index(0) = vec4(1.0, 1.0, 1.0, 1.0);

global uniform float wind_strength;
global uniform float wetness;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float w = 0.35 + wind_strength;
	float t = TIME * (1.1 + wind_strength * 1.3);
	float ph = t + wp.x * 0.21 + wp.z * 0.17;
	// whole-plant bend (quadratic with height) + small per-vertex leaf flutter
	vec3 bend = vec3(sin(ph), 0.0, cos(ph * 0.83 + 1.7)) * sway * w * h * h * 0.12;
	vec3 vp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 leaf = vec3(sin(t * 3.7 + vp.x * 1.9 + vp.y * 2.3), sin(t * 2.9 + vp.z * 2.1) * 0.5, cos(t * 3.3 + vp.z * 1.7)) * flutter * w * min(h, 3.0);
	vec3 off_world = bend + leaf;
	// world offset -> object space (ignores non-uniform scale, fine for vegetation)
	mat3 inv = inverse(mat3(MODEL_MATRIX));
	VERTEX += inv * off_world;
}

void fragment() {
	vec3 col = texture(pal_albedo, UV).rgb * tint_a.rgb;
	float wet = wetness * 0.6;
	col *= mix(1.0, 0.8, wet);
	ALBEDO = col;
	ROUGHNESS = mix(0.82, 0.45, wet);
	SPECULAR = 0.3;
	BACKLIGHT = col * 0.35;
}
