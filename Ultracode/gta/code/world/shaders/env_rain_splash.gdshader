// Halcyon Bay rain splash ring (ENVIRONMENT module). One MultiMesh of ground-aligned quads,
// placed by gta/code/world/env/env_rain.gd where rain hits the ground near the camera.
// INSTANCE_CUSTOM: r = birth time (gta_time seconds), g = lifetime, b = random 0..1.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

global uniform float gta_time;

uniform vec3 splash_color : source_color = vec3(0.82, 0.88, 0.95);
uniform float opacity = 0.8;

varying float v_age;
varying float v_rand;

void vertex() {
	float life = max(INSTANCE_CUSTOM.g, 0.01);
	v_age = clamp((gta_time - INSTANCE_CUSTOM.r) / life, 0.0, 1.0);
	v_rand = INSTANCE_CUSTOM.b;
	// The ring grows while it lives; a finished ring collapses to nothing (no fragments).
	float grow = mix(0.25, 1.0, sqrt(v_age));
	float alive = step(v_age, 0.999) * step(0.0, gta_time - INSTANCE_CUSTOM.r);
	VERTEX.xz *= grow * alive;
	VERTEX.y += 0.02;
}

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float ring = smoothstep(0.62, 0.82, r) * smoothstep(1.0, 0.86, r);
	// Tiny crown dot in the first third of the life.
	float crown = smoothstep(0.22, 0.0, r) * (1.0 - smoothstep(0.0, 0.35, v_age));
	float a = (ring * (1.0 - v_age) + crown) * opacity * (0.6 + 0.4 * v_rand);
	ALBEDO = splash_color;
	ALPHA = clamp(a, 0.0, 1.0);
}
