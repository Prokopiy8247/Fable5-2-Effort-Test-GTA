// Halcyon Bay window glass (ENVIRONMENT module night-light hook).
// Assign to every surface whose Blender material is "M_Window" (see docs/ENVIRONMENT.md):
//     var env := Game.get_system("environment")
//     env.apply_night_materials(building_root)          # or get_window_material() by hand
// By day: reflective glass that mirrors the sky. At night a pseudo-random subset of panes glows
// warm, driven only by the global uniform gta_night - no per-building scripts, no lights.
//
// What is a "pane" (cell_mode):
//   1  UV cells   - the building kit (tools/blender/assets/building_kit.py) gives every M_Window
//                   face its own integer UV cell: uv = (k % 64 + u, k / 64 + v). floor(UV) is the
//                   pane id, fract(UV) the position inside the pane. Exact, any window size.
//   2  object grid - meshes without UVs: cells of the 4 m module grid in OBJECT space
//                   (x/z: pane_size.x, floors: ground_floor_height then pane_size.y each).
//                   Fine for windows up to ~2 m wide that sit in the middle of a module.
//   3  world grid  - like 2 but in world space, for geometry that was merged in world space.
//   0  auto        - 1 when the mesh has UVs (non-zero UV derivatives), otherwise 2.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

global uniform float gta_night;
global uniform float gta_time;

uniform int cell_mode : hint_range(0, 3) = 0;

uniform vec3 glass_color : source_color = vec3(0.42, 0.56, 0.70);
uniform vec3 glass_color_low : source_color = vec3(0.30, 0.42, 0.56);
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.14;
uniform float glass_specular : hint_range(0.0, 1.0) = 0.7;
uniform float glass_metallic : hint_range(0.0, 1.0) = 0.82;

uniform float lit_fraction : hint_range(0.0, 1.0) = 0.46;         // share of panes lit at full night
uniform float ground_lit_fraction : hint_range(0.0, 1.0) = 0.78;  // shop fronts stay lit more often
uniform float emission_energy = 2.1;
uniform vec3 warm_a : source_color = vec3(1.0, 0.80, 0.48);
uniform vec3 warm_b : source_color = vec3(1.0, 0.63, 0.30);
uniform vec3 cool_a : source_color = vec3(0.60, 0.80, 1.0);
uniform vec3 tv_color : source_color = vec3(0.45, 0.62, 1.0);

uniform vec2 pane_size = vec2(4.0, 3.2);        // grid modes: module width (m), upper floor height (m)
uniform float ground_floor_height = 4.0;
uniform float grid_offset = 1.0;                // grid modes: shifts cell borders off window centres
uniform float flicker_share : hint_range(0.0, 1.0) = 0.18;   // panes that switch on/off over time

varying vec3 v_local_pos;
varying vec3 v_world_pos;
varying flat vec3 v_seed;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	// Sample a little behind the glass so facade planes on a cell border stay stable.
	v_local_pos = VERTEX - NORMAL * 0.45;
	vec3 wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - wn * 0.45;
	v_seed = floor(origin * 0.5);
}

void fragment() {
	vec2 du = fwidth(UV);
	bool use_uv = (cell_mode == 1) || (cell_mode == 0 && (du.x + du.y) > 0.0000001);
	vec3 gp = (cell_mode == 3) ? v_world_pos : v_local_pos;
	bool ground = v_local_pos.y < ground_floor_height;

	vec3 cell;
	float fy;       // 0 at the bottom of the pane .. 1 at the top
	if (use_uv) {
		vec2 uc = floor(UV);
		cell = vec3(uc.x, uc.y, 57.0);
		fy = 1.0 - fract(UV.y);            // glTF stores v flipped
	} else {
		float fl;
		if (gp.y < ground_floor_height) {
			fl = 0.0;
			fy = clamp(gp.y / ground_floor_height, 0.0, 1.0);
		} else {
			float u = (gp.y - ground_floor_height) / pane_size.y;
			fl = 1.0 + floor(u);
			fy = fract(u);
		}
		vec2 cxz = floor((gp.xz + grid_offset) / pane_size.x);
		cell = vec3(cxz.x, fl, cxz.y);
		if (cell_mode == 3) {
			ground = false;
		}
	}
	// Integer lattice coordinates: rounding removes any interpolation noise before hashing, so
	// every pixel of a pane gets exactly the same random numbers.
	cell = round(cell + ((cell_mode == 3) ? vec3(0.0) : v_seed * vec3(1.0, 3.0, 1.0)));

	float h_on = hash31(cell);
	float h_th = hash31(cell + 17.0);
	float h_col = hash31(cell + 41.0);
	float h_bri = hash31(cell + 73.0);
	float h_fx = hash31(cell + 5.0);

	float fraction = ground ? ground_lit_fraction : lit_fraction;
	float lit = step(h_on, fraction);
	// Staggered switch-on through dusk: every pane has its own gta_night threshold.
	float th = 0.22 + 0.50 * h_th;
	float on = lit * smoothstep(th, th + 0.07, gta_night);
	// A few rooms go dark / come back every minute or two - the city feels inhabited.
	if (h_fx < flicker_share) {
		float period = 50.0 + 110.0 * h_bri;
		float phase = floor(gta_time / period + h_col * 9.0);
		on *= step(0.38, hash31(cell + vec3(phase * 3.0, 0.0, phase)));
	}

	vec3 lamp = mix(warm_a, warm_b, smoothstep(0.0, 0.62, h_col));
	lamp = mix(lamp, cool_a, step(0.78, h_col));
	lamp = mix(lamp, tv_color, step(0.94, h_col));
	// Interior hint: brighter towards the floor, a darker blind band at the top of some panes.
	float shade = mix(1.0, 0.74, smoothstep(0.30, 0.95, fy));
	float blind = step(0.55, h_bri) * smoothstep(0.66, 0.70, fy) * 0.42;
	float tv_pulse = 1.0;
	if (h_col > 0.94) {
		tv_pulse = 0.7 + 0.3 * sin(gta_time * 5.0 + h_bri * 40.0) * sin(gta_time * 1.7 + h_th * 20.0);
	}
	float bright = (0.62 + 0.5 * h_bri) * shade * (1.0 - blind) * tv_pulse;

	vec3 glass = mix(glass_color_low, glass_color, smoothstep(0.0, 1.0, fy));
	ALBEDO = mix(glass, lamp * 0.35, on * 0.8);
	ROUGHNESS = mix(glass_roughness, 0.55, on);
	METALLIC = glass_metallic * (1.0 - on);
	SPECULAR = glass_specular;
	EMISSION = lamp * bright * emission_energy * on;
}
