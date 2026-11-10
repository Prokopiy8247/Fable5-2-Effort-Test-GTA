shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
// Fx: faceted LIT mesh particle (smoke / dust puffs, chips, debris, shells).
// The mesh has flat normals, so every facet catches the sun on its own - the "Sunlit Low-Poly"
// look. Colour = particle COLOR (ramp from the process material) * tint. Particles disappear by
// shrinking (scale curve), never by alpha, so this stays in the cheap opaque pass (no overdraw).

uniform vec4 tint : source_color = vec4(1.0);
uniform float glow = 0.0;      // emission multiplier (0 = purely lit)
uniform float tumble = 1.0;
instance uniform float size_mul = 1.0;   // per emitter: the Fx autoload sets it on every trigger    // 0 = keep the particle basis, 1 = spin about a per-particle axis

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
		// INSTANCE_CUSTOM.x = particle angle in radians (ParticleProcessMaterial angle + angular velocity)
		float id = float(INSTANCE_ID);
		vec3 axis = normalize(vec3(fract(id * 0.754877) - 0.5, fract(id * 0.569840) - 0.5,
				fract(id * 0.343190) - 0.5) + vec3(0.013, 0.021, 0.007));
		mat3 r = rot_axis(axis, INSTANCE_CUSTOM.x * tumble + id * 1.7);
		VERTEX = r * VERTEX;
		NORMAL = r * NORMAL;
	}
	VERTEX *= size_mul;
	// particle colours come from ramp textures sampled raw (sRGB numbers) -> decode to linear
	v_color = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2)) * tint.rgb;
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = v_color * glow;
}
