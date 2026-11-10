shader_type canvas_item;
// HALCYON BAY HUD: sniper scope overlay (black mask with a round window and a fine reticle).
uniform float aspect = 1.7778;                       // viewport width / height
uniform float radius = 0.43;                         // window radius in screen heights
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float d = length(p);
	float mask = smoothstep(radius - 0.003, radius + 0.003, d);            // 1 outside the window
	float rim = smoothstep(radius - 0.07, radius, d) * (1.0 - mask);       // soft inner shadow
	float inside = 1.0 - mask;
	float thin = 0.0011;
	float lx = step(abs(p.y), thin) * step(0.014, abs(p.x));
	float ly = step(abs(p.x), thin) * step(0.014, abs(p.y));
	float post_x = step(abs(p.y), 0.0042) * step(radius * 0.52, abs(p.x));
	float post_y = step(abs(p.x), 0.0042) * step(radius * 0.52, p.y);
	float ticks = 0.0;
	for (int i = 1; i <= 4; i++) {
		float off = float(i) * 0.045;
		ticks += step(abs(p.y - off), thin) * step(abs(p.x), 0.012 - float(i) * 0.0015);
	}
	float reticle = clamp(lx + ly + post_x + post_y + ticks, 0.0, 1.0) * inside;
	float centre = (1.0 - smoothstep(0.0016, 0.003, d)) * inside;
	vec3 col = mix(vec3(0.0), vec3(0.9, 0.14, 0.1), centre);
	float a = max(max(mask, reticle * 0.92), max(rim * 0.6, centre));
	COLOR = vec4(col, a * amount);
}
