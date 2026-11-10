// Stylised dynamic sky: gradient, sun + moon discs, stars, two drifting cloud layers.
// Driven by day_night.gd / weather.gd.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.16, 0.38, 0.72);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.78, 0.92);
uniform vec3 ground_color : source_color = vec3(0.2, 0.24, 0.27);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.75);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.6, 0.3);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.55, 0.6, 0.7);
uniform vec3 moon_dir = vec3(0.0, 0.5, 0.5);
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.5);
uniform float sun_visible = 1.0;
uniform float cloud_cover = 0.35;
uniform float cloud_density = 0.9;
uniform float star_amount = 0.0;
uniform float glow_amount = 0.5;
uniform float cloud_time = 0.0;
uniform float exposure = 1.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;
	float t = pow(clamp(up, 0.0, 1.0), 0.55);
	vec3 col = mix(horizon_color, top_color, t);
	col = mix(col, ground_color, smoothstep(0.0, -0.18, up));
	vec3 sdir = normalize(sun_dir);
	float sun_d = max(dot(dir, sdir), 0.0);
	float sun_vis = smoothstep(-0.08, 0.02, sdir.y) * sun_visible;
	// wide warm glow around the sun near the horizon
	col += sun_glow * pow(sun_d, 6.0) * glow_amount * sun_vis * (1.0 - cloud_cover * 0.6);
	col += sun_color * pow(sun_d, 64.0) * 0.6 * sun_vis;
	// stars
	if (star_amount > 0.001 && up > 0.0) {
		vec2 suv = dir.xz / (up + 0.35) * 42.0;
		vec2 cell = floor(suv);
		float h = hash21(cell);
		vec2 f = fract(suv) - 0.5 - (vec2(hash21(cell + 3.7), hash21(cell + 9.1)) - 0.5) * 0.6;
		float star = smoothstep(0.09, 0.0, length(f)) * step(0.93, h);
		col += vec3(star) * star_amount * (0.5 + 0.5 * hash21(cell + 1.3)) * smoothstep(0.0, 0.2, up);
	}
	// moon
	vec3 mdir = normalize(moon_dir);
	float md = dot(dir, mdir);
	float moon = smoothstep(0.9993, 0.9996, md) * smoothstep(-0.05, 0.05, mdir.y);
	col = mix(col, vec3(0.95, 0.96, 1.0) * 1.4, moon * clamp(star_amount * 1.5 + 0.15, 0.0, 1.0));
	col += vec3(0.4, 0.5, 0.7) * pow(max(md, 0.0), 40.0) * 0.25 * star_amount;
	// sun disc (after stars so it stays crisp)
	float disc = smoothstep(0.9990, 0.9995, dot(dir, sdir)) * sun_vis;
	col = mix(col, sun_color * 4.0, disc * (1.0 - cloud_cover * 0.5));
	// clouds: projected planar noise, two octaves, lit toward the sun
	if (up > 0.01) {
		vec2 cuv = dir.xz / (up + 0.12);
		float c1 = texture(noise_tex, cuv * 0.11 + vec2(cloud_time * 0.004, cloud_time * 0.0015)).r;
		float c2 = texture(noise_tex, cuv * 0.31 - vec2(cloud_time * 0.006, 0.0)).r;
		float c = c1 * 0.7 + c2 * 0.3;
		float thresh = 1.0 - cloud_cover;
		float mask = smoothstep(thresh - 0.12, thresh + 0.2, c) * cloud_density;
		mask *= smoothstep(0.01, 0.16, up);
		float lit = 0.55 + 0.45 * smoothstep(thresh, thresh + 0.35, c1);
		vec3 ccol = mix(cloud_shadow, cloud_color, lit);
		ccol += sun_glow * pow(sun_d, 5.0) * 0.5 * sun_vis;
		col = mix(col, ccol, clamp(mask, 0.0, 1.0));
	}
	COLOR = col * exposure;
}
