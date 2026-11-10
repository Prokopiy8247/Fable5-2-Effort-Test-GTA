shader_type spatial;
// PropSystem: traffic-signal lens on a MultiMesh. INSTANCE_CUSTOM.r = 1 lit, 0 dark.
// One material per lens colour; the manager only rewrites instance custom data (<= 4 Hz).
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float gta_night;

uniform vec3 lens_color : source_color = vec3(1.0, 0.1, 0.05);
uniform float day_energy = 3.2;
uniform float night_energy = 7.0;

varying float v_on;

void vertex() {
	v_on = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 dark = lens_color * 0.10 + vec3(0.015);
	ALBEDO = mix(dark, lens_color * 0.85, v_on);
	ROUGHNESS = 0.25;
	SPECULAR = 0.6;
	EMISSION = lens_color * v_on * mix(day_energy, night_energy, clamp(gta_night, 0.0, 1.0));
}
