// Vehicle lamp lenses. Each lamp material selects a `channel`; the owning vehicle drives
// channel intensities through two per-instance vectors.
//   lights_a = (head, tail/brake, reverse, indicator-left)
//   lights_b = (indicator-right, siren A, siren B, aux/roof sign)
shader_type spatial;
// per-instance slots are allocated project-wide (see DEVELOPMENT.md): 0-3 palette, 4-8 paint, 9-10 glass, 11-12 lamps, 13 window, 14 signal
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform int channel = 0;
uniform vec3 lens_color : source_color = vec3(1.0, 0.96, 0.85);
uniform float energy = 4.0;

instance uniform vec4 lights_a : instance_index(11) = vec4(0.0);
instance uniform vec4 lights_b : instance_index(12) = vec4(0.0);

void fragment() {
	float v = 0.0;
	if (channel == 0) { v = lights_a.x; }
	else if (channel == 1) { v = lights_a.y; }
	else if (channel == 2) { v = lights_a.z; }
	else if (channel == 3) { v = lights_a.w; }
	else if (channel == 4) { v = lights_b.x; }
	else if (channel == 5) { v = lights_b.y; }
	else if (channel == 6) { v = lights_b.z; }
	else { v = lights_b.w; }
	v = max(v, 0.0);
	ALBEDO = lens_color * mix(0.28, 0.9, clamp(v, 0.0, 1.0));
	ROUGHNESS = 0.15;
	METALLIC = 0.2;
	EMISSION = lens_color * energy * v;
}
