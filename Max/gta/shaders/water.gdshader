// Stylised sea. Wave function must match world.gd::wave_height() (buoyancy, swimming).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.13, 0.62, 0.66);
uniform vec3 deep_color : source_color = vec3(0.03, 0.2, 0.33);
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 0.98);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

global uniform float water_time;
global uniform float wave_amp;
global uniform float night_factor;

varying vec3 wpos;

float wave(vec2 p, float t) {
	return sin(p.x * 0.105 + p.y * 0.062 + t * 0.95) * 0.5
		+ sin(p.y * 0.171 - p.x * 0.043 + t * 1.25) * 0.3
		+ sin((p.x + p.y) * 0.31 + t * 1.9) * 0.12;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = water_time;
	float h = wave(wpos.xz, t) * wave_amp;
	VERTEX.y += h;
	float e = 1.5;
	float hx = (wave(wpos.xz + vec2(e, 0.0), t) - wave(wpos.xz - vec2(e, 0.0), t)) * wave_amp;
	float hz = (wave(wpos.xz + vec2(0.0, e), t) - wave(wpos.xz - vec2(0.0, e), t)) * wave_amp;
	NORMAL = normalize(vec3(-hx, 2.0 * e, -hz));
}

void fragment() {
	float t = water_time;
	// small ripples from two scrolling noise samples
	vec2 uv1 = wpos.xz * 0.045 + vec2(t * 0.012, t * 0.008);
	vec2 uv2 = wpos.xz * 0.11 - vec2(t * 0.016, -t * 0.011);
	float r1 = texture(noise_tex, uv1).r;
	float r2 = texture(noise_tex, uv2).r;
	float e = 0.004;
	float rx = (texture(noise_tex, uv1 + vec2(e, 0.0)).r - r1) + (texture(noise_tex, uv2 + vec2(e, 0.0)).r - r2);
	float rz = (texture(noise_tex, uv1 + vec2(0.0, e)).r - r1) + (texture(noise_tex, uv2 + vec2(0.0, e)).r - r2);
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz + vec3(-rx, 0.0, -rz) * 9.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	// scene depth behind the surface
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	behind.xyz /= behind.w;
	float thickness = max(VERTEX.z - behind.z, 0.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float deepness = smoothstep(0.0, 7.0, thickness);
	vec3 col = mix(shallow_color, deep_color, deepness);
	col = mix(col, deep_color * 0.6, fres * 0.5);
	// refraction-ish: show the sea bed through shallow water
	vec2 ruv = SCREEN_UV + vec2(rx, rz) * 0.6 * (1.0 - deepness);
	vec3 bed = texture(screen_tex, ruv).rgb;
	float clarity = (1.0 - smoothstep(0.0, 3.2, thickness)) * 0.75 * (FRONT_FACING ? 1.0 : 0.0);
	col = mix(col, bed * mix(vec3(1.0), shallow_color * 1.6, 0.5), clarity);
	// shoreline foam + sparse whitecaps
	float foam = (1.0 - smoothstep(0.0, 0.55, thickness)) * smoothstep(0.25, 0.7, r1 + 0.25 * sin(t * 1.3 + wpos.x * 0.4));
	foam += smoothstep(0.78, 0.9, r1 * r2 * 2.2) * 0.35 * clamp(wave_amp * 2.5, 0.0, 1.5);
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0));
	col *= mix(1.0, 0.45, night_factor);
	ALBEDO = col;
	ROUGHNESS = mix(0.07, 0.35, clamp(foam, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.65;
	if (!FRONT_FACING) {
		// seen from below: brighter, softer surface
		ALBEDO = mix(shallow_color, vec3(0.75, 0.95, 1.0), 0.35) * mix(1.0, 0.4, night_factor);
		ROUGHNESS = 0.3;
	}
}
