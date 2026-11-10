shader_type spatial;
// Awnings / shop signs on MultiMesh facade modules: colour comes from INSTANCE_CUSTOM.
global uniform float night_factor;
uniform float glow = 0.0;
varying vec3 tint;

void vertex() {
	tint = mix(INSTANCE_CUSTOM.rgb, mix(vec3(1.0), INSTANCE_CUSTOM.rgb, 0.4), step(0.5, glow));
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.75;
	EMISSION = tint * glow * (0.25 + night_factor * 1.6);
}
