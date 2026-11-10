shader_type spatial;
// Procedural asphalt with lane markings, crosswalks, wear, cracks, oil stains and rain wetness.
// COLOR.r = lanes per direction / 4, COLOR.g = surface type / 8, COLOR.b = half width / 16
// UV.x = lateral metres from the centre line, UV.y = metres along the road.
// types: 0 road, 1 plain asphalt, 2 crosswalk, 3 solid paint, 4 runway, 6 dirt track, 7 parking bays
global uniform float wetness;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 asphalt : source_color = vec3(0.20, 0.205, 0.22);
uniform vec3 line_white : source_color = vec3(0.86, 0.86, 0.80);
uniform vec3 line_yellow : source_color = vec3(0.93, 0.70, 0.14);
uniform vec3 dirt : source_color = vec3(0.50, 0.40, 0.27);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float band(float x, float c, float w) {
	float aa = fwidth(x) * 0.75 + 0.002;
	return 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, abs(x - c));
}

void fragment() {
	float lanes = round(COLOR.r * 4.0);
	float type = round(COLOR.g * 8.0);
	float hw = COLOR.b * 16.0;
	float n = texture(noise_tex, wpos.xz * 0.05).r;
	float n2 = texture(noise_tex, wpos.xz * 0.61 + 3.7).r;
	vec3 col = asphalt * (0.80 + 0.36 * n) * (0.90 + 0.2 * n2);
	float stain = smoothstep(0.66, 0.78, texture(noise_tex, wpos.xz * 0.019 + 7.3).r);
	col *= 1.0 - 0.32 * stain;
	float cr = abs(texture(noise_tex, wpos.xz * 0.11 + 1.9).r - 0.5);
	col *= mix(0.62, 1.0, smoothstep(0.0, 0.010, cr));
	float mark = 0.0;
	vec3 mcol = line_white;
	float x = UV.x;
	float y = UV.y;
	if (type < 0.5) {
		mark = band(abs(x), hw - 0.45, 0.14);
		if (lanes > 1.5) {
			float dash = step(0.5, fract(y / 9.0));
			mark = max(mark, band(abs(x), 3.5, 0.14) * dash);
			float cy = max(band(x, 0.17, 0.12), band(x, -0.17, 0.12));
			mark = max(mark, cy);
			mcol = mix(mcol, line_yellow, cy);
		} else {
			float cy = band(x, 0.0, 0.14) * step(0.42, fract(y / 8.0));
			mark = max(mark, cy);
			mcol = mix(mcol, line_yellow, cy);
		}
	} else if (type > 1.5 && type < 2.5) {
		mark = step(0.5, fract(x / 1.1 + 0.25));
	} else if (type > 2.5 && type < 3.5) {
		mark = 1.0;
	} else if (type > 3.5 && type < 4.5) {
		col *= 0.9;
		mark = band(x, 0.0, 0.5) * step(0.5, fract(y / 24.0));
		mark = max(mark, band(abs(x), hw - 1.0, 0.4));
		float thr = step(y, 26.0) * step(6.0, y) * step(0.5, fract(x / 3.2)) * step(abs(x), hw - 2.0);
		mark = max(mark, thr);
	} else if (type > 5.5 && type < 6.5) {
		col = dirt * (0.75 + 0.5 * n) * (0.9 + 0.2 * n2);
	} else if (type > 6.5) {
		col *= 1.12;
		mark = band(fract(y / 2.7), 0.5, 0.045) * step(abs(x), hw) * 0.9;
	}
	mark *= 0.72 + 0.28 * n2;
	col = mix(col, mcol, clamp(mark, 0.0, 1.0) * 0.92);
	float wet = wetness * (0.55 + 0.45 * n);
	float puddle = smoothstep(0.58, 0.66, n) * wetness;
	ALBEDO = col * mix(1.0, 0.62, wet);
	ROUGHNESS = mix(0.92, 0.28, wet) * (1.0 - 0.8 * puddle);
	METALLIC = 0.0;
	SPECULAR = mix(0.4, 0.7, wet);
}
