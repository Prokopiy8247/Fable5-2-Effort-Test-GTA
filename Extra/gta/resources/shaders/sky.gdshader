shader_type sky;
// Gradient sky with sun/moon disc, stars and animated noise clouds.
uniform vec3 top_color : source_color = vec3(0.16, 0.42, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.65, 0.80, 0.95);
uniform vec3 ground_color : source_color = vec3(0.30, 0.32, 0.30);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_dark : source_color = vec3(0.6, 0.65, 0.75);
uniform float cloud_cover = 0.35;
uniform float star_vis = 0.0;
uniform float sun_size = 0.04;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.45));
	col = mix(col, ground_color, smoothstep(0.0, -0.06, h));
	float sd = distance(d, LIGHT0_DIRECTION);
	float disc = smoothstep(sun_size, sun_size * 0.82, sd);
	float halo = pow(max(0.0, 1.0 - sd * 0.5), 10.0);
	col += sun_color * (disc * 3.0 + halo * 0.45) * step(-0.1, LIGHT0_DIRECTION.y);
	if (star_vis > 0.01 && h > 0.0) {
		vec2 sp = d.xz / (h + 0.25) * 42.0;
		float st = step(0.985, hash(floor(sp))) * hash(floor(sp) + 7.0);
		col += vec3(st) * star_vis * smoothstep(0.0, 0.25, h);
	}
	if (h > 0.005) {
		vec2 p = d.xz / (h + 0.14) * 0.11 + TIME * 0.0022;
		float n = texture(noise_tex, p).r * 0.62 + texture(noise_tex, p * 2.7 + 0.3).r * 0.38;
		float c = smoothstep(0.93 - cloud_cover * 0.8, 1.03 - cloud_cover * 0.62, n + 0.18);
		vec3 cc = mix(cloud_dark, cloud_light, clamp(n * 1.3 - cloud_cover * 0.45, 0.0, 1.0));
		col = mix(col, cc, c * smoothstep(0.005, 0.14, h));
	}
	COLOR = col;
}
