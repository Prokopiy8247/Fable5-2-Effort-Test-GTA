// Shared "palette atlas" surface used by almost every authored prop/building/vehicle part.
// Blender assigns each face a palette cell through its UVs (see tools/blender/gta_kit.py).
// One material => huge batching potential and a globally consistent art direction.
shader_type spatial;
// per-instance slots are allocated project-wide (see DEVELOPMENT.md): 0-3 palette, 4-8 paint, 9-10 glass, 11-12 lamps, 13 window, 14 signal
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D pal_albedo : source_color, filter_nearest, repeat_disable;
uniform sampler2D pal_orm : filter_nearest, repeat_disable;    // r=roughness g=metallic b=emission/4
uniform sampler2D pal_flags : filter_nearest, repeat_disable;  // r=tint A g=tint B b=night-only a=neon
uniform float wet_response = 1.0;

instance uniform vec4 tint_a : instance_index(0) = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec4 tint_b : instance_index(1) = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float emission_scale : instance_index(2) = 1.0;
instance uniform float damage : instance_index(3) = 0.0;

global uniform float night_factor;
global uniform float wetness;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = texture(pal_albedo, UV).rgb;
	vec4 orm = texture(pal_orm, UV);
	vec4 fl = texture(pal_flags, UV);
	vec3 col = base * mix(vec3(1.0), tint_a.rgb * COLOR.rgb, fl.r);
	col *= mix(vec3(1.0), tint_b.rgb, fl.g);
	// soot/damage darkening (burnt-out wrecks, damaged props)
	col = mix(col, col * 0.18 + vec3(0.02), clamp(damage, 0.0, 1.0));
	float rough = orm.r;
	float wet = wetness * wet_response * smoothstep(0.35, 0.9, world_normal.y);
	rough = mix(rough, 0.22, wet * 0.75);
	col *= mix(1.0, 0.72, wet);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = orm.g;
	float e = orm.b * 4.0;
	float gate = mix(1.0, night_factor, fl.b) * mix(1.0, 0.3 + 0.7 * night_factor, fl.a);
	EMISSION = col * e * gate * emission_scale * (1.0 - clamp(damage, 0.0, 1.0));
}
