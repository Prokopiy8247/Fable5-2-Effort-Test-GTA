// Halcyon Bay wet-surface hook (ENVIRONMENT module). Shader include for any SPATIAL shader that
// should look wet in the rain (roads, pavements, roofs, sand ...). It declares NO uniforms, so it
// can never clash with the including shader: pass the global uniforms in as arguments.
//
//   shader_type spatial;
//   global uniform float gta_wetness;      // 0 dry .. 1 soaked (Weather.wetness)
//   global uniform float gta_rain;         // 0..1 current rain intensity
//   global uniform float gta_time;         // seconds
//   #include "res://gta/code/world/shaders/env_wet.gdshaderinc"
//
//   void fragment() {
//       vec3 albedo = my_colour;  float rough = 0.9;  float spec = 0.5;
//       vec3 wn = normalize(v_world_normal);                    // WORLD space normal
//       float puddle = env_puddle_mask(v_world.xz, wn.y, gta_wetness, 1.0);
//       env_wet_surface(albedo, rough, spec, gta_wetness, puddle, 0.8, 1.0);
//       vec3 n = env_wet_normal(wn, v_world.xz, puddle, gta_rain, gta_time);
//       ALBEDO = albedo;  ROUGHNESS = rough;  SPECULAR = spec;
//       NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
//   }
//
// Reference implementation: env_wet_ground.gdshader (see docs/ENVIRONMENT.md).
// Cost: two value-noise lookups per fragment, plus one hashed ripple cell while it rains.

float envw_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float envw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(envw_hash(i), envw_hash(i + vec2(1.0, 0.0)), u.x),
			mix(envw_hash(i + vec2(0.0, 1.0)), envw_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Standing-water mask 0..1 at a world position.
//   up_facing : world normal Y (puddles only form on nearly level faces)
//   wetness   : gta_wetness
//   puddles   : how much water this material collects (0 none: grass / sand, 1 asphalt)
// Puddles grow out of fixed low spots as the wetness rises and shrink back while it dries.
float env_puddle_mask(vec2 world_xz, float up_facing, float wetness, float puddles) {
	float level = clamp(wetness * puddles, 0.0, 1.0);
	if (level < 0.02) {
		return 0.0;
	}
	float n = envw_noise(world_xz * 0.21) * 0.62 + envw_noise(world_xz * 0.67 + vec2(17.3, 5.1)) * 0.38;
	float th = mix(1.02, 0.52, level);
	return smoothstep(th, th + 0.06, n) * smoothstep(0.90, 0.985, up_facing);
}

// Expanding rain rings (for puddles): returns a small XZ normal offset, zero when it is dry.
vec2 env_rain_ripple(vec2 world_xz, float rain, float time_s) {
	if (rain < 0.02) {
		return vec2(0.0);
	}
	vec2 rp = world_xz * 2.3;
	vec2 ri = floor(rp);
	vec2 rf = fract(rp) - 0.5;
	float rh = envw_hash(ri);
	float ph = fract(time_s * (0.9 + rh * 0.8) + rh * 7.0);
	vec2 off = (vec2(envw_hash(ri + 3.1), envw_hash(ri + 8.7)) - 0.5) * 0.4;
	vec2 d = rf - off;
	float rd = length(d);
	float ring = smoothstep(0.06, 0.0, abs(rd - ph * 0.40)) * (1.0 - ph);
	return (d / max(rd, 0.0001)) * ring * rain;
}

// Darkens / glosses a surface by wetness and turns the puddle mask into standing water.
//   porosity : 0 = sealed (painted metal, glass: hardly darkens), 1 = porous (concrete, sand)
//   gloss    : how shiny the damp surface gets (asphalt / stone 1, pavement 0.7, sand / grass 0.2)
// The darkening is deliberately moderate: a rainy night must stay readable.
void env_wet_surface(inout vec3 albedo, inout float roughness, inout float specular,
		float wetness, float puddle, float porosity, float gloss) {
	float w = clamp(wetness, 0.0, 1.0);
	float damp = smoothstep(0.0, 0.55, w);
	float shine = damp * clamp(gloss, 0.0, 1.0);
	albedo *= mix(1.0, mix(0.92, 0.72, clamp(porosity, 0.0, 1.0)), damp);
	roughness = mix(roughness, min(roughness, mix(0.60, 0.36, w)), shine);
	specular = mix(specular, max(specular, 0.55), shine);
	albedo = mix(albedo, albedo * 0.72, puddle);
	roughness = mix(roughness, 0.04, puddle);
	specular = mix(specular, 0.80, puddle);
}

// World-space normal of the wet surface: puddles are level water with rain rings.
vec3 env_wet_normal(vec3 world_normal, vec2 world_xz, float puddle, float rain, float time_s) {
	if (puddle < 0.001) {
		return world_normal;
	}
	vec2 rip = env_rain_ripple(world_xz, rain, time_s) * 0.30;
	vec3 level_n = normalize(vec3(rip.x, 1.0, rip.y));
	return normalize(mix(world_normal, level_n, puddle));
}
