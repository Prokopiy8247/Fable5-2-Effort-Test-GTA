// Region-coloured characters. Blender stores a region id in UV.x (cell = floor(u * 16));
// each character owns a copy of this material with its own 16 colours (skin, shirt, hair...).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 colors[16] : source_color;
uniform float flash = 0.0;        // hit feedback
uniform float wetness_local = 0.0;

void fragment() {
	int idx = clamp(int(floor(UV.x * 16.0)), 0, 15);
	vec3 c = colors[idx].rgb;
	c = mix(c, c * 0.72, wetness_local);
	ALBEDO = mix(c, vec3(1.0, 0.3, 0.22), clamp(flash, 0.0, 1.0));
	ROUGHNESS = mix(0.84, 0.45, wetness_local);
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
