shader_type spatial;
render_mode cull_disabled;
// Stylised sea: depth tinted, shoreline foam, animated normals.
global uniform float wind_time;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform vec3 shallow : source_color = vec3(0.18, 0.66, 0.68);
uniform vec3 deep : source_color = vec3(0.03, 0.22, 0.38);
uniform float storm = 0.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float amp = 0.05 + storm * 0.22;
	VERTEX.y += (sin(wpos.x * 0.21 + wind_time * 1.3) + cos(wpos.z * 0.17 + wind_time * 1.1)) * amp;
}

float hgt(vec2 uv) {
	return texture(noise_tex, uv + wind_time * vec2(0.012, 0.008)).r * 0.6 + texture(noise_tex, uv * 2.3 - wind_time * vec2(0.01, 0.016)).r * 0.4;
}

void fragment() {
	vec2 uv = wpos.xz * 0.045;
	float e = 0.012;
	float h0 = hgt(uv);
	float hx = hgt(uv + vec2(e, 0.0)) - hgt(uv - vec2(e, 0.0));
	float hz = hgt(uv + vec2(0.0, e)) - hgt(uv - vec2(0.0, e));
	vec3 wn = normalize(vec3(-hx * (2.2 + storm * 3.0), 1.0, -hz * (2.2 + storm * 3.0)));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	v.xyz /= v.w;
	float wd = max(VERTEX.z - v.z, 0.0);
	float d = clamp(wd / 7.0, 0.0, 1.0);
	vec3 col = mix(shallow, deep, d);
	float foam = (1.0 - smoothstep(0.0, 0.55, wd + (h0 - 0.5) * 0.5)) * step(0.001, wd);
	foam = max(foam, smoothstep(0.80 - storm * 0.2, 0.9, h0) * 0.35);
	ALBEDO = mix(col, vec3(1.0), clamp(foam, 0.0, 1.0) * 0.85);
	ALPHA = clamp(mix(0.5, 0.94, d) + foam, 0.0, 1.0);
	ROUGHNESS = 0.07;
	SPECULAR = 0.65;
	if (!FRONT_FACING) {
		ALBEDO = shallow * 0.8;
		ALPHA = 0.75;
	}
}
