// Traffic signal lenses. `which`: 0 red, 1 amber, 2 green. The SignalController sets the
// per-instance `signal_state` (r, a, g intensities) on each traffic light mesh.
shader_type spatial;
// per-instance slots are allocated project-wide (see DEVELOPMENT.md): 0-3 palette, 4-8 paint, 9-10 glass, 11-12 lamps, 13 window, 14 signal
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform int which = 0;
uniform vec3 lens_color : source_color = vec3(1.0, 0.1, 0.05);
uniform float energy = 5.0;

instance uniform vec3 signal_state : instance_index(14) = vec3(1.0, 0.0, 0.0);

void fragment() {
	float v = which == 0 ? signal_state.x : (which == 1 ? signal_state.y : signal_state.z);
	ALBEDO = lens_color * mix(0.12, 0.9, v);
	ROUGHNESS = 0.2;
	EMISSION = lens_color * energy * v;
}
