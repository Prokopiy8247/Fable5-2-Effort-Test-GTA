shader_type spatial;
// Checkpoint column for activity races (activities module). Applied to the Blender-authored
// unit cylinder wall `vfx_checkpoint_ring` (UV.y = height 0..1), scaled per checkpoint.
// Additive, unshaded, two-sided; bright base band that fades upward with slow rising stripes.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.25, 1.0);
uniform float intensity = 1.0;
uniform float stripe_speed = 0.35;

void fragment() {
	float h = clamp(UV.y, 0.0, 1.0);
	float fade = pow(1.0 - h, 1.6);
	float base = smoothstep(0.12, 0.0, h) * 0.9;
	float stripes = 0.5 + 0.5 * sin((h * 7.0 - TIME * stripe_speed * 6.2832) * 3.1416);
	float a = clamp(fade * (0.32 + 0.38 * stripes) + base, 0.0, 1.0) * intensity;
	ALBEDO = color.rgb * a * 1.6;
	ALPHA = 1.0;
}
