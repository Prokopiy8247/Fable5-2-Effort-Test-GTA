shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// Fx: additive mesh glow (tracer streak, muzzle-flash star). Vertex colours carry the
// core -> tip gradient (alpha 0 at the tips), `fade` is animated per instance by the Fx autoload.

uniform vec4 color : source_color = vec4(1.0, 0.82, 0.45, 1.0);
instance uniform float fade = 1.0;

void fragment() {
	ALBEDO = color.rgb * COLOR.rgb;
	ALPHA = clamp(color.a * COLOR.a * fade, 0.0, 1.0);
}
