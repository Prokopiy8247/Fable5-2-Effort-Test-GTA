// Halcyon Bay wet ground (ENVIRONMENT module). Reference implementation of the wetness hook
// env_wet.gdshaderinc: a flat-colour (optionally vertex-colour) ground / road surface that
// darkens, turns glossy and collects puddles with rain rings as gta_wetness rises, and dries
// again afterwards. No textures, no per-node scripts - driven only by the global uniforms.
// Use it as is (EnvironmentSystem.make_wet_surface_material) or copy the four marked lines into
// your own ground / road shader. See docs/ENVIRONMENT.md.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

global uniform float gta_wetness;
global uniform float gta_rain;
global uniform float gta_time;

#include "res://gta/code/world/shaders/env_wet.gdshaderinc"

uniform vec3 tint : source_color = vec3(1.0);
uniform bool use_vertex_color = false;
uniform bool vertex_color_is_srgb = true;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.92;
uniform float base_specular : hint_range(0.0, 1.0) = 0.4;
uniform float puddle_amount : hint_range(0.0, 1.0) = 1.0;    // 0 = never any standing water
uniform float porosity : hint_range(0.0, 1.0) = 0.8;         // how much the surface darkens
uniform float wet_gloss : hint_range(0.0, 1.0) = 1.0;        // how shiny it gets when damp

varying vec3 v_world;
varying vec3 v_world_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 albedo = tint;
	if (use_vertex_color) {
		vec3 vc = COLOR.rgb;
		if (vertex_color_is_srgb) {
			vc = pow(vc, vec3(2.2));
		}
		albedo *= vc;
	}
	float rough = base_roughness;
	float spec = base_specular;
	// --- wetness hook --------------------------------------------------------------------
	vec3 wn = normalize(v_world_normal);
	float puddle = env_puddle_mask(v_world.xz, wn.y, gta_wetness, puddle_amount);
	env_wet_surface(albedo, rough, spec, gta_wetness, puddle, porosity, wet_gloss);
	vec3 n = env_wet_normal(wn, v_world.xz, puddle, gta_rain, gta_time);
	// -------------------------------------------------------------------------------------
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = spec;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
