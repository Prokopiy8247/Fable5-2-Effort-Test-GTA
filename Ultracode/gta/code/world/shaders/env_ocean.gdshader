// Halcyon Bay ocean (ENVIRONMENT module). Project-owned stylised low-poly water.
//  - gentle vertex waves (sum of four sines, total amplitude <= wave_amp <= 0.25 m). The SAME
//    function runs on the CPU in OceanSurface.get_height() (boats / swimmers) - keep in sync!
//  - flat "facet" normals rebuilt per fragment from the wave function on a world-space triangle
//    grid, so the faceted look is independent of the mesh tessellation and view distance
//  - depth based colour (shallow turquoise -> deep blue) and transparency from the depth texture
//  - animated foam line where the water meets the shore or anything floating in it
//  - fresnel sky tint, rain ripples (gta_rain), whitecap facets in strong wind
//  - readable underside when the camera is below the surface
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

global uniform float gta_time;
global uniform float gta_rain;

uniform float wave_amp = 0.12;              // metres, total amplitude of the vertex waves
uniform vec2 wave_center = vec2(0.0);       // camera xz; the geometry waves fade out around it
uniform float wave_fade_start = 58.0;
uniform float wave_fade_end = 76.0;
uniform float facet_size = 2.0;             // metres, must match the fine cell of the mesh
uniform float facet_strength = 3.6;         // normal exaggeration of the facets
uniform float facet_min_amp = 0.10;

uniform vec3 shallow_color : source_color = vec3(0.22, 0.80, 0.74);
uniform vec3 mid_color : source_color = vec3(0.05, 0.50, 0.66);
uniform vec3 deep_color : source_color = vec3(0.02, 0.20, 0.44);
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 1.0);
uniform vec3 sky_tint : source_color = vec3(0.62, 0.81, 0.95);
uniform float sky_tint_strength = 0.30;
uniform float whitecaps = 0.0;              // 0 calm .. 1 storm
uniform float foam_width = 0.45;
uniform float clarity = 1.0;                // < 1 = murkier water (storm)
uniform float roughness_base = 0.08;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

varying vec3 v_world;

const vec2 W_D1 = vec2(0.9397, 0.3420);
const vec2 W_D2 = vec2(0.6157, -0.7880);
const vec2 W_D3 = vec2(-0.3584, 0.9336);
const vec2 W_D4 = vec2(0.9848, -0.1736);
const float W_K1 = 0.27318;   // 2 pi / 23.0 m
const float W_K2 = 0.48332;   // 2 pi / 13.0 m
const float W_K3 = 0.86071;   // 2 pi / 7.3 m
const float W_K4 = 1.42800;   // 2 pi / 4.4 m
const float W_S1 = 0.95;
const float W_S2 = 1.28;
const float W_S3 = 1.72;
const float W_S4 = 2.25;

// Unit wave: result in [-1, 1].
float wave_unit(vec2 p, float t) {
	float h = 0.42 * sin(dot(p, W_D1) * W_K1 + t * W_S1);
	h += 0.28 * sin(dot(p, W_D2) * W_K2 + t * W_S2 + 1.3);
	h += 0.18 * sin(dot(p, W_D3) * W_K3 + t * W_S3 + 2.1);
	h += 0.12 * sin(dot(p, W_D4) * W_K4 + t * W_S4 + 4.2);
	return h;
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float fade = 1.0 - smoothstep(wave_fade_start, wave_fade_end, distance(wp.xz, wave_center));
	float h = wave_unit(wp.xz, gta_time) * wave_amp * fade;
	VERTEX.y += h;
	v_world = wp + vec3(0.0, h, 0.0);
}

void fragment() {
	vec2 p = v_world.xz;
	vec3 to_cam = CAMERA_POSITION_WORLD - v_world;
	float dist = length(to_cam);
	vec3 view_w = to_cam / max(dist, 0.001);

	// --- facet normal on a world-space triangle grid ---------------------------------------
	vec2 g = p / facet_size;
	vec2 gi = floor(g);
	vec2 gf = fract(g);
	vec2 ca;
	vec2 cb;
	vec2 cc;
	if (gf.x + gf.y < 1.0) {
		ca = gi;
		cb = gi + vec2(1.0, 0.0);
		cc = gi + vec2(0.0, 1.0);
	} else {
		ca = gi + vec2(1.0, 1.0);
		cb = gi + vec2(0.0, 1.0);
		cc = gi + vec2(1.0, 0.0);
	}
	ca *= facet_size;
	cb *= facet_size;
	cc *= facet_size;
	float ua = wave_unit(ca, gta_time);
	float ub = wave_unit(cb, gta_time);
	float uc = wave_unit(cc, gta_time);
	float n_amp = max(wave_amp, facet_min_amp) * facet_strength;
	vec3 pa = vec3(ca.x, ua * n_amp, ca.y);
	vec3 pb = vec3(cb.x, ub * n_amp, cb.y);
	vec3 pc = vec3(cc.x, uc * n_amp, cc.y);
	vec3 n = normalize(cross(pc - pa, pb - pa));
	if (n.y < 0.0) {
		n = -n;
	}
	float facet_h = (ua + ub + uc) / 3.0;       // -1..1 height of this facet
	float facet_id = hash21(ca + cb * 1.7 + cc * 0.31);
	// Far away the facets shrink below a pixel: flatten them to avoid shimmer.
	// Blend towards a normal that leans to the viewer: it stands in for the unresolved wave
	// slopes, so the far sea mirrors the higher (bluer) sky instead of the pale horizon.
	float far_flat = smoothstep(120.0, 600.0, dist);
	vec3 n_far = normalize(vec3(view_w.x, 0.0, view_w.z) * 0.22 + vec3(0.0, 1.0, 0.0));
	n = normalize(mix(n, n_far, far_flat * 0.92));

	// --- rain ripples (near the camera only) ------------------------------------------------
	float ripple = 0.0;
	if (gta_rain > 0.01 && dist < 70.0) {
		vec2 rp = p * 1.35;
		vec2 ri = floor(rp);
		vec2 rf = fract(rp) - 0.5;
		float rh = hash21(ri);
		float ph = fract(gta_time * (0.9 + rh * 0.8) + rh * 7.0);
		vec2 off = (vec2(hash21(ri + 3.1), hash21(ri + 8.7)) - 0.5) * 0.4;
		float rd = length(rf - off);
		ripple = smoothstep(0.07, 0.0, abs(rd - ph * 0.42)) * (1.0 - ph) * gta_rain;
		ripple *= 1.0 - smoothstep(40.0, 70.0, dist);
	}

	// --- depth below the surface -------------------------------------------------------------
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 scene_view = INV_PROJECTION_MATRIX * ndc;
	scene_view.xyz /= scene_view.w;
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(scene_view.xyz, 1.0)).xyz;
	float depth_v = 400.0;      // vertical water depth under this fragment
	float thickness = 400.0;    // water thickness along the view ray
	if (depth_raw > 0.0000001) {
		float thickness_raw = length(scene_view.xyz) - length(VERTEX);
		if (thickness_raw < -0.05) {
			// Anti-aliased silhouette of something in FRONT of the water: the depth sample
			// belongs to that object. Use a neutral depth instead of drawing a foam fringe.
			depth_v = 3.0;
			thickness = 3.0;
		} else {
			depth_v = clamp(v_world.y - scene_world.y, 0.0, 400.0);
			thickness = clamp(thickness_raw, 0.0, 400.0);
		}
	}

	if (FRONT_FACING) {
		float t1 = 1.0 - exp(-depth_v * 0.60 / clarity);
		float t2 = 1.0 - exp(-depth_v * 0.13 / clarity);
		vec3 body = mix(mix(shallow_color, mid_color, t1), deep_color, t2);
		// Large slow colour patches + a tiny per-facet tone step keep big areas alive.
		float patch_n = vnoise(p * 0.011 + vec2(gta_time * 0.006, 0.0));
		body *= 0.90 + 0.20 * patch_n;
		body *= 1.0 + (facet_id - 0.5) * 0.14 * (1.0 - far_flat);

		float fres = pow(1.0 - clamp(dot(n, view_w), 0.0, 1.0), 4.0);

		// Shore / object foam: a solid lapping band plus a broken lace band behind it.
		float lap = sin(gta_time * 0.85 + vnoise(p * 0.12) * 6.2831) * 0.5 + 0.5;
		float fw = foam_width * (0.55 + 0.65 * lap);
		float fnoise = vnoise(p * 1.9 + vec2(gta_time * 0.18, gta_time * -0.11));
		float foam = 1.0 - smoothstep(fw * 0.55, fw, depth_v + fnoise * 0.22);
		float lace = smoothstep(0.52, 0.70, vnoise(p * 2.7 - vec2(gta_time * 0.21, 0.0)));
		foam += lace * (1.0 - smoothstep(fw, fw * 3.2, depth_v)) * 0.75;
		// Whitecaps: whole facets turn white on the crests when the wind is up.
		float cap = smoothstep(0.52, 0.72, facet_h + (facet_id - 0.5) * 0.35) * whitecaps;
		foam += cap * (1.0 - smoothstep(60.0, 260.0, dist)) * 0.8;
		foam = clamp(foam, 0.0, 1.0);

		float alpha = mix(0.22, 0.97, 1.0 - exp(-max(thickness, depth_v) * 0.75 / clarity));
		alpha = max(alpha, fres);

		vec3 albedo = mix(body, foam_color, foam);
		albedo += vec3(0.5, 0.55, 0.6) * ripple * 0.5;
		ALBEDO = albedo;
		ROUGHNESS = mix(roughness_base, 0.85, foam);
		SPECULAR = 0.5;
		METALLIC = 0.0;
		EMISSION = sky_tint * fres * sky_tint_strength * (1.0 - foam);
		ALPHA = clamp(mix(alpha, 1.0, foam) + ripple * 0.2, 0.0, 1.0);
		vec3 n_out = normalize(n + vec3(ripple * 0.35, 0.0, ripple * 0.25));
		NORMAL = normalize((VIEW_MATRIX * vec4(n_out, 0.0)).xyz);
	} else {
		// Seen from below: bright "window" straight up, dark mirror towards the sides.
		float up = clamp(-view_w.y, 0.0, 1.0);
		float window = smoothstep(0.52, 0.80, up + (n.x + n.z) * 0.25);
		ALBEDO = mix(mid_color, shallow_color, window);
		EMISSION = mix(mid_color * 0.35, sky_tint * 0.9, window);
		ROUGHNESS = 0.4;
		SPECULAR = 0.2;
		ALPHA = mix(0.90, 0.70, window);
		NORMAL = normalize((VIEW_MATRIX * vec4(-n, 0.0)).xyz);
	}
}
