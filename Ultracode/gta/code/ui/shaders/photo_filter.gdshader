shader_type canvas_item;
// Photo mode look: a full-screen grade over the rendered frame (UI module, photo_mode.gd).
// Every filter preset is a set of these uniforms; "Natural" leaves the frame untouched.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float brightness = 0.0;
uniform float lift = 0.0;                  // raises the blacks (faded print look)
uniform vec3 tint = vec3(1.0);             // multiplies the colour
uniform vec3 shadow_tint = vec3(0.0);      // added in the shadows (split toning)
uniform vec3 highlight_tint = vec3(0.0);   // added in the highlights
uniform float mono = 0.0;                  // 0 colour .. 1 monochrome
uniform vec3 mono_tint = vec3(1.0);
uniform float vignette = 0.0;
uniform float grain = 0.0;
uniform float grain_seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5 + brightness;
	c *= tint;
	float l2 = clamp(dot(c, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	c += shadow_tint * (1.0 - l2) * (1.0 - l2) + highlight_tint * l2 * l2;
	c = mix(c, vec3(l2) * mono_tint, mono);
	c = vec3(lift) + c * (1.0 - lift);
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.2, 1.0);
	float v = 1.0 - smoothstep(0.32, 0.86, length(d));
	c *= mix(1.0, v, vignette);
	float n = hash(floor(FRAGCOORD.xy) + vec2(grain_seed * 13.0, grain_seed * 7.0)) - 0.5;
	c += n * grain;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
