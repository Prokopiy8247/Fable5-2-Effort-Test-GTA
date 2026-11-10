shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// Fx: expanding ring on a flat quad (explosion shockwave, water ripple). The ring is a 14-gon
// instead of a circle so it matches the faceted art style. Everything is per-instance.

instance uniform vec4 ring_color : source_color = vec4(1.0);
instance uniform float progress = 0.5;   // outer radius, 0..1 of the quad half size
instance uniform float width = 0.3;      // band thickness relative to the outer radius
instance uniform float fade = 1.0;

const float SIDES = 14.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float seg = TAU / SIDES;
	float ang = atan(p.y, p.x);
	// distance in "polygon radius" units: 1.0 on the edge of a regular polygon with circumradius 1
	float d = length(p) * cos(mod(ang, seg) - seg * 0.5) / cos(seg * 0.5);
	float outer = clamp(progress, 0.001, 1.0);
	float inner = outer * (1.0 - clamp(width, 0.02, 1.0));
	float aa = 0.012 + fwidth(d);
	float band = smoothstep(inner - aa, inner, d) * (1.0 - smoothstep(outer - aa, outer, d));
	ALBEDO = ring_color.rgb;
	ALPHA = clamp(band * fade * ring_color.a, 0.0, 1.0);
}
