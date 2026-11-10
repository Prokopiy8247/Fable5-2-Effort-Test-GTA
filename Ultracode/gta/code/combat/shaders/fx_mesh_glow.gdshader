shader_type spatial;
render_mode unshaded, cull_back;
// Fx: faceted EMISSIVE mesh particle (fireball blobs, flames, sparks, sparkles).
// Unshaded so it reads at night, with a cheap fake facet shading term so the low-poly facets stay
// visible instead of turning into a flat blob. Colour = particle COLOR (fire ramp) * tint.

uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 1.4;  // > 1 feeds the environment glow
uniform float tumble = 1.0;
instance uniform float size_mul = 1.0;   // per emitter: the Fx autoload sets it on every trigger
uniform float facet = 0.4;     // 0 = flat colour, 1 = strong facet contrast

varying vec3 v_color;

mat3 rot_axis(vec3 a, float ang) {
	float s = sin(ang);
	float c = cos(ang);
	float oc = 1.0 - c;
	return mat3(
		vec3(oc * a.x * a.x + c, oc * a.x * a.y + a.z * s, oc * a.z * a.x - a.y * s),
		vec3(oc * a.x * a.y - a.z * s, oc * a.y * a.y + c, oc * a.y * a.z + a.x * s),
		vec3(oc * a.z * a.x + a.y * s, oc * a.y * a.z - a.x * s, oc * a.z * a.z + c));
}

void vertex() {
	if (tumble > 0.0) {
		float id = float(INSTANCE_ID);
		vec3 axis = normalize(vec3(fract(id * 0.754877) - 0.5, fract(id * 0.569840) - 0.5,
				fract(id * 0.343190) - 0.5) + vec3(0.013, 0.021, 0.007));
		mat3 r = rot_axis(axis, INSTANCE_CUSTOM.x * tumble + id * 1.7);
		VERTEX = r * VERTEX;
		NORMAL = r * NORMAL;
	}
	VERTEX *= size_mul;
	// view-space facet term: facets that look up / towards the camera are brighter
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float f = clamp(n.y * 0.5 + 0.5, 0.0, 1.0) * 0.65 + clamp(n.z, 0.0, 1.0) * 0.35;
	// particle colours come from ramp textures sampled raw (sRGB numbers) -> decode to linear
	v_color = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2)) * tint.rgb * strength * mix(1.0 - facet, 1.0, f);
}

void fragment() {
	ALBEDO = v_color;
}
