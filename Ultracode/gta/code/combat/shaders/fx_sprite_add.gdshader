shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// Fx: soft additive billboard (explosion flash, muzzle glow). The texture is a procedural radial
// GradientTexture2D; colour and fade are per-instance so one material serves every pooled sprite.

uniform sampler2D tex : source_color, filter_linear, repeat_disable;
instance uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);
instance uniform float fade = 1.0;

void vertex() {
	// spherical billboard that keeps the node scale
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s.x, INV_VIEW_MATRIX[1] * s.y,
			INV_VIEW_MATRIX[2] * s.z, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float a = texture(tex, UV).r;
	ALBEDO = glow_color.rgb * 2.2;
	ALPHA = clamp(a * fade * glow_color.a, 0.0, 1.0);
}
