shader_type canvas_item;
// HALCYON BAY HUD: low-health vignette + damage flash. One full-screen quad, no screen reads.
uniform float low : hint_range(0.0, 1.0) = 0.0;      // low-health intensity
uniform float flash : hint_range(0.0, 1.0) = 0.0;    // damage flash intensity
uniform vec4 low_color : source_color = vec4(0.72, 0.07, 0.09, 1.0);
uniform vec4 flash_color : source_color = vec4(1.0, 0.22, 0.16, 1.0);
uniform float pulse_speed = 5.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p * vec2(0.92, 1.0));
	float pulse = 0.72 + 0.28 * sin(TIME * pulse_speed);
	// keep the centre of the screen readable: the tint lives in the outer ring
	float a_low = smoothstep(0.55, 1.4, d) * low * pulse * 0.9;
	float a_flash = smoothstep(0.4, 1.35, d) * flash * 0.75 + flash * 0.03;
	float total = a_low + a_flash;
	vec3 col = mix(low_color.rgb, flash_color.rgb, clamp(a_flash / max(total, 0.0001), 0.0, 1.0));
	COLOR = vec4(col, clamp(total, 0.0, 0.92));
}
