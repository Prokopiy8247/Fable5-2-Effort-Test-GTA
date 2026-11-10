// Halcyon Bay lamp lens / neon tube (ENVIRONMENT module night-light hook).
// One shader, two uses (materials are created by EnvironmentSystem.get_lamp_material() /
// get_neon_material(color), see docs/ENVIRONMENT.md):
//   - "M_LampGlow" street lamp lens: off (pale plastic) by day, emissive at night
//   - "P_Neon*" signage: always emissive, clearly stronger at night
// Driven only by the global uniform gta_night - no per-node scripts.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

global uniform float gta_night;
global uniform float gta_time;

uniform vec3 glow_color : source_color = vec3(1.0, 0.80, 0.50);
uniform vec3 off_color : source_color = vec3(0.86, 0.85, 0.80);
uniform float day_energy = 0.0;
uniform float night_energy = 4.5;
uniform float switch_start : hint_range(0.0, 1.0) = 0.28;   // gta_night where the lamp starts to glow
uniform float switch_end : hint_range(0.0, 1.0) = 0.50;
uniform float shimmer : hint_range(0.0, 1.0) = 0.0;         // subtle neon buzz

varying float v_phase;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_phase = fract(dot(origin, vec3(0.137, 0.291, 0.173))) * 6.2831;
}

void fragment() {
	float on = smoothstep(switch_start, switch_end, gta_night);
	float e = mix(day_energy, night_energy, on);
	float buzz = 1.0 - shimmer * (0.5 + 0.5 * sin(gta_time * 23.0 + v_phase) * sin(gta_time * 3.1 + v_phase * 2.0)) * 0.22;
	float lit = clamp(e, 0.0, 1.0);
	ALBEDO = mix(off_color, glow_color * 0.6, lit);
	ROUGHNESS = 0.35;
	SPECULAR = 0.4;
	EMISSION = glow_color * e * buzz;
}
