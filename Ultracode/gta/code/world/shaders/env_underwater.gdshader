// Halcyon Bay underwater screen treatment (ENVIRONMENT module). A full-screen ColorRect on a
// low CanvasLayer (below the HUD), visible only while the active camera is under the sea surface.
// Gentle refraction wobble + blue-green absorption tint + vignette + drifting light shimmer.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform vec3 tint : source_color = vec3(0.50, 0.86, 0.94);
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float depth_factor : hint_range(0.0, 1.0) = 0.0;   // 0 just below the surface .. 1 deep
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float time_s = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 wob = vec2(sin(uv.y * 21.0 + time_s * 1.6) + sin(uv.y * 47.0 - time_s * 2.3) * 0.4,
			cos(uv.x * 17.0 + time_s * 1.2)) * 0.0032 * strength;
	vec3 c = texture(screen_tex, clamp(uv + wob, vec2(0.001), vec2(0.999))).rgb;

	// Absorption: red goes first, more so with depth.
	vec3 absorb = mix(vec3(1.0), tint, (0.55 + 0.35 * depth_factor) * strength);
	c *= absorb;
	c = mix(c, c * vec3(0.55, 0.8, 0.95), depth_factor * 0.5 * strength);

	// Soft light shimmer coming from above (stronger near the surface and by day).
	// Slanted, slowly drifting shafts of unequal width - kept faint on purpose.
	float sx = uv.x * 5.0 + uv.y * 1.6;
	float sh = sin(sx * 3.1 + time_s * 0.35) * 0.5 + sin(sx * 7.3 - time_s * 0.22 + 1.7) * 0.3
			+ sin(sx * 13.7 + time_s * 0.5 + 4.1) * 0.2;
	sh = smoothstep(0.25, 0.95, sh) * smoothstep(0.85, 0.0, uv.y);
	c += vec3(0.05, 0.085, 0.08) * sh * (1.0 - depth_factor) * daylight * strength;

	float vig = smoothstep(0.30, 0.95, length((uv - 0.5) * vec2(1.15, 1.0)) * 1.25);
	c *= 1.0 - vig * (0.42 + 0.25 * depth_factor) * strength;
	COLOR = vec4(c, 1.0);
}
