// Vehicle body paint. Two paint channels (primary/secondary) share this shader; the
// material picks its channel with `slot`, the vehicle sets colours/finish per instance.
shader_type spatial;
// per-instance slots are allocated project-wide (see DEVELOPMENT.md): 0-3 palette, 4-8 paint, 9-10 glass, 11-12 lamps, 13 window, 14 signal
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform int slot = 0;

instance uniform vec4 paint_a : instance_index(4) = vec4(0.6, 0.01, 0.01, 1.0);
instance uniform vec4 paint_b : instance_index(5) = vec4(0.01, 0.01, 0.01, 1.0);
// x = roughness, y = metallic, z = clearcoat, w = pearl/flake amount
instance uniform vec4 finish_a : instance_index(6) = vec4(0.32, 0.35, 0.6, 0.0);
instance uniform vec4 finish_b : instance_index(7) = vec4(0.32, 0.35, 0.6, 0.0);
instance uniform float damage : instance_index(3) = 0.0;   // 0..1 scratches -> burnt
instance uniform float dirt : instance_index(8) = 0.0;

global uniform float wetness;

varying vec3 obj_pos;
varying vec3 world_normal;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	obj_pos = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 pc = slot == 0 ? paint_a : paint_b;
	vec4 fin = slot == 0 ? finish_a : finish_b;
	vec3 col = pc.rgb;
	// pearl: slight hue shift toward lighter tone at grazing angles
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	col = mix(col, col * 1.35 + vec3(0.06), fres * fin.w);
	float n = vnoise(obj_pos * 7.0) * 0.6 + vnoise(obj_pos * 23.0) * 0.4;
	// scratches / dents appear progressively, burnt shell at damage ~1
	float scratch = smoothstep(1.0 - damage * 0.9, 1.0 - damage * 0.9 + 0.12, n) * step(0.02, damage);
	col = mix(col, vec3(0.16, 0.15, 0.14), scratch * 0.85);
	float burnt = smoothstep(0.82, 1.0, damage);
	col = mix(col, vec3(0.035, 0.03, 0.03) + 0.03 * n, burnt);
	float d = clamp(dirt, 0.0, 1.0) * smoothstep(0.35, 0.7, vnoise(obj_pos * 4.0 + vec3(3.1)) + (0.6 - obj_pos.y) * 0.45);
	col = mix(col, vec3(0.33, 0.27, 0.2), d * 0.7);
	float rough = mix(fin.x, 0.9, max(max(scratch * 0.8, burnt), d));
	float wet = wetness * smoothstep(0.2, 0.9, world_normal.y) * (1.0 - burnt);
	rough = mix(rough, 0.12, wet * 0.6);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = fin.y * (1.0 - burnt) * (1.0 - scratch * 0.5);
	CLEARCOAT = fin.z * (1.0 - max(scratch, burnt)) * (1.0 - d);
	CLEARCOAT_ROUGHNESS = 0.08;
}
