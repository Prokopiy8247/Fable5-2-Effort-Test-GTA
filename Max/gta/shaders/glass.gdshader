// Transparent glass for vehicles, storefronts and interiors. Tint/opacity per instance
// (window-tint upgrades in the mod shop), plus a simple "cracked" state.
shader_type spatial;
// per-instance slots are allocated project-wide (see DEVELOPMENT.md): 0-3 palette, 4-8 paint, 9-10 glass, 11-12 lamps, 13 window, 14 signal
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.32, 0.44, 0.5);
instance uniform vec4 glass_tint : instance_index(9) = vec4(0.05, 0.09, 0.12, 0.42);
instance uniform float crack : instance_index(10) = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = glass_tint.rgb;
	float a = glass_tint.a;
	if (crack > 0.01) {
		// cheap shatter pattern in object space
		vec2 g = UV * 14.0 + vec2(hash12(floor(UV * 5.0)) * 3.0);
		vec2 f = abs(fract(g) - 0.5);
		float lines = smoothstep(0.46, 0.5, max(f.x, f.y));
		col = mix(col, vec3(0.85, 0.9, 0.92), lines * crack);
		a = mix(a, 0.85, lines * crack);
	}
	ALBEDO = col;
	ALPHA = clamp(a + fres * 0.35, 0.0, 1.0);
	ROUGHNESS = 0.06;
	METALLIC = 0.3;
	SPECULAR = 0.7;
}
