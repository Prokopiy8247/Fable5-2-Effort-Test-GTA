// Halcyon Bay sky (ENVIRONMENT module). Project-owned, fully procedural, no textures.
// Gradient sky + sun / moon discs + stars + one wind-driven procedural cloud layer.
// Every colour is supplied by SkyController (gta/code/world/env/sky_controller.gd), which derives
// it from WorldClock (time of day) and Weather (cloud cover, rain, storm, lightning).
// The radiance (cubemap) pass skips discs, stars and the cloud noise: it is cheap on purpose.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.13, 0.38, 0.84);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.81, 0.95);
uniform vec3 ground_color : source_color = vec3(0.20, 0.38, 0.52);
uniform float gradient_curve = 3.2;

uniform vec3 sun_dir = vec3(0.3, 0.8, 0.5);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.82);
uniform float sun_energy = 9.0;
uniform float sun_radius = 0.042;           // radians
uniform float sun_disc_alpha = 1.0;         // < 1 hides the disc behind a closed cloud deck
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.85, 0.6);
uniform float sun_glow = 0.35;

uniform vec3 moon_dir = vec3(-0.3, 0.7, -0.4);
uniform vec3 moon_color : source_color = vec3(0.86, 0.92, 1.0);
uniform float moon_energy = 0.0;
uniform float moon_radius = 0.034;

uniform float star_intensity = 0.0;
uniform float time_s = 0.0;

uniform float cloud_cover = 0.15;           // 0 clear .. 1 closed deck
uniform vec2 cloud_offset = vec2(0.0);      // wind-integrated scroll
uniform vec3 cloud_lit : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_dark : source_color = vec3(0.62, 0.68, 0.78);
uniform vec3 cloud_light_dir = vec3(0.3, 0.8, 0.5);
uniform float cloud_scale = 1.45;
uniform float flash = 0.0;                  // lightning 0..1

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = rot * p * 2.03 + vec2(17.1, 5.3);
		a *= 0.5;
	}
	return v / 0.9375;
}

vec3 base_gradient(vec3 dir) {
	float t = clamp(dir.y, 0.0, 1.0);
	float f = 1.0 - exp(-t * gradient_curve);
	vec3 col = mix(horizon_color, top_color, f);
	// Below the horizon: sea haze colour (matches the fogged far ocean).
	float below = smoothstep(0.0, -0.18, dir.y);
	col = mix(col, ground_color, below);
	return col;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 col = base_gradient(dir);

	float sun_cos = dot(dir, normalize(sun_dir));
	float horizon_band = pow(1.0 - clamp(abs(dir.y), 0.0, 1.0), 6.0);

	// Wide warm glow around the sun, hugging the horizon at sunrise / sunset.
	float glow_wide = pow(max(sun_cos, 0.0), 6.0);
	float glow_tight = pow(max(sun_cos, 0.0), 90.0);
	float sun_up = smoothstep(-0.14, 0.02, sun_dir.y);
	col += sun_glow_color * sun_glow * sun_up * (glow_wide * (0.22 + 0.55 * horizon_band) + glow_tight * 0.55);

	float overcast = smoothstep(0.55, 0.98, cloud_cover);

	if (AT_CUBEMAP_PASS) {
		// Cheap stand-in for the cloud layer: tint the upper hemisphere by the cover.
		float up = smoothstep(-0.02, 0.25, dir.y);
		vec3 cloud_avg = mix(cloud_dark, cloud_lit, 0.55);
		col = mix(col, cloud_avg, up * clamp(cloud_cover * 0.75, 0.0, 0.9));
		col += vec3(0.55, 0.62, 0.8) * flash * up * 0.8;
		COLOR = col;
	} else {
		float cloud_alpha = 0.0;
		vec3 cloud_col = cloud_lit;
		if (dir.y > -0.03) {
			float inv = 1.0 / (max(dir.y, 0.0) + 0.16);
			vec2 uv = dir.xz * inv * cloud_scale + cloud_offset;
			float base = fbm(uv);
			// Second, larger octave set drifting a little slower breaks the tiling feel.
			float large = vnoise(uv * 0.31 - cloud_offset * 0.35 + vec2(4.7, 9.1));
			float shape = base * 0.72 + large * 0.28;
			float threshold = mix(0.74, 0.20, cloud_cover);
			float dens = smoothstep(threshold, threshold + mix(0.06, 0.16, overcast), shape);
			// Pseudo lighting: compare with the density a step towards the light.
			vec2 ld = normalize(cloud_light_dir.xz + vec2(0.0001, 0.0));
			float toward = fbm(uv + ld * 0.16) * 0.72 + large * 0.28;
			float lit = clamp((shape - toward) * 3.4 + 0.58, 0.0, 1.0);
			// Stylised two-and-a-half tone shading.
			lit = mix(lit, floor(lit * 3.0 + 0.5) / 3.0, 0.55);
			float core = smoothstep(threshold + 0.10, threshold + 0.42, shape);
			cloud_col = mix(cloud_dark, cloud_lit, lit * (1.0 - 0.45 * core * overcast));
			// Sun shining through thin cloud edges.
			cloud_col += sun_glow_color * glow_tight * (1.0 - dens) * 0.6 * sun_up;
			float horizon_fade = smoothstep(-0.01, 0.13, dir.y);
			cloud_alpha = dens * horizon_fade * mix(0.92, 1.0, overcast);
			cloud_col = cloud_col * (1.0 + flash * 2.5) + vec3(0.30, 0.34, 0.46) * flash * (0.25 + 0.75 * shape);
		}

		// Stars (hidden by clouds and daylight).
		if (star_intensity > 0.002 && dir.y > -0.02) {
			vec3 sp = dir * 150.0;
			vec3 ip = floor(sp);
			vec3 fp = fract(sp) - 0.5;
			float h = hash31(ip);
			float present = step(0.9955, h);
			vec3 jitter = vec3(hash31(ip + 11.0), hash31(ip + 23.0), hash31(ip + 37.0)) - 0.5;
			float d = length(fp - jitter * 0.5);
			float tw = 0.72 + 0.28 * sin(time_s * (1.5 + h * 3.0) + h * 80.0);
			float star = present * smoothstep(0.26, 0.0, d) * tw;
			vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.92, 0.78), hash31(ip + 5.0));
			col += tint * star * star_intensity * smoothstep(0.0, 0.22, dir.y) * 2.2;
		}

		// Moon: soft halo + disc with a darker limb for a stylised phase.
		if (moon_energy > 0.002) {
			vec3 md = normalize(moon_dir);
			float mc = dot(dir, md);
			col += moon_color * moon_energy * (pow(max(mc, 0.0), 220.0) * 0.20 + pow(max(mc, 0.0), 28.0) * 0.035);
			if (mc > cos(moon_radius * 1.05)) {
				vec3 right = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
				vec3 up = cross(right, md);
				vec2 lp = vec2(dot(dir, right), dot(dir, up)) / moon_radius;
				float disc = 1.0 - smoothstep(0.92, 1.0, length(lp));
				float shadow = 1.0 - smoothstep(0.86, 0.98, length(lp - vec2(0.42, 0.20)));
				float spots = vnoise(lp * 2.3 + 3.0);
				vec3 mcol = moon_color * mix(1.0, 0.82, smoothstep(0.45, 0.75, spots));
				mcol *= mix(1.0, 0.26, shadow);
				col = mix(col, mcol * moon_energy * 2.4, disc);
			}
		}

		// Sun disc (crisp, HDR so it blooms a little).
		float disc_edge = cos(sun_radius);
		float sun_disc = smoothstep(disc_edge, mix(disc_edge, 1.0, 0.12), sun_cos);
		col = mix(col, sun_color * sun_energy, sun_disc * sun_up * sun_disc_alpha);

		// Cloud layer over everything celestial.
		col = mix(col, cloud_col, cloud_alpha);
		// Lightning also lifts the clear parts of the sky a little.
		col += vec3(0.5, 0.56, 0.75) * flash * 0.30 * smoothstep(-0.15, 0.1, dir.y);
		COLOR = col;
	}
}
