// Halcyon Bay rain streak (ENVIRONMENT module). Drawn by the camera-following GPUParticles3D
// in gta/code/world/env/env_rain.gd. The particle system billboards the quad around the
// velocity axis (TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY); this shader only shapes the streak.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 streak_color : source_color = vec3(0.78, 0.84, 0.92);
uniform float opacity = 0.42;
uniform float flash = 0.0;                  // lightning brightens the drops for an instant

varying float v_fade;

void vertex() {
	// Per-particle variation from the particle seed (stored in INSTANCE_CUSTOM by the engine).
	v_fade = 0.55 + 0.45 * fract(INSTANCE_CUSTOM.w * 37.13 + float(INSTANCE_ID) * 0.6180339);
}

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.55, UV.y);
	float a = across * across * along * opacity * v_fade;
	// Fade drops that are very close to the lens so they never pop as fat lines.
	a *= smoothstep(0.35, 1.6, -VERTEX.z);
	ALBEDO = streak_color * (1.0 + flash * 2.5);
	ALPHA = clamp(a, 0.0, 1.0);
}
