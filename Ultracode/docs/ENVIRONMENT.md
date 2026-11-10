# HALCYON BAY - Environment module

Time of day, weather, sky, lighting, post-processing, rain, the ocean, the underwater treatment,
pooled night street lights and the shared night-light / wetness shader hooks.
Contract: `docs/ARCHITECTURE.md` section 6.2. Everything here is project-authored code and
shaders: no textures, no external assets, no engine plug-ins.

Contents: 1 architecture - 2 autoload APIs - 3 environment system API - 4 shader hooks for other
modules - 5 tunables - 6 GPU cost and safety - 7 tests - 8 decisions, limits, open points.

---------------------------------------------------------------------------------------------------

## 1. Architecture

```
WorldClock (autoload)  ---- hour, phases, daylight, sun / moon direction, save data
Weather    (autoload)  ---- 5 types, blended parameters, wetness, auto cycle, lightning timing
        |  read every frame (pure view: no state of its own that could drift)
        v
EnvironmentSystem  ("environment" world system, gta/code/world/environment_system.gd)
  |- Sky              env/sky_controller.gd      DirectionalLight3D sun/moon + WorldEnvironment
  |                                              (sky shader, ambient, tonemap, glow, SSAO, fog)
  |- Ocean            env/ocean_surface.gd       camera-following water mesh + CPU wave function
  |- Rain             env/env_rain.gd            GPUParticles3D streaks, roof height field, splash rings
  |- StreetLightPool  env/env_light_pool.gd      <= 14 pooled OmniLight3D on registered lamp points
  |- UnderwaterLayer  env/env_underwater.gd      CanvasLayer -10 with the screen-space treatment
  |- (RefCounted)     env/env_night_materials.gd factory + cache of the window / lamp / neon materials
  `- writes the 8 global shader uniforms (nobody else does)
```

Shaders (`gta/code/world/shaders/`):

| file | type | used for |
|---|---|---|
| `env_sky.gdshader` | sky | gradient, sun / moon discs, stars, procedural cloud layer, lightning |
| `env_ocean.gdshader` | spatial | the sea (depth colour, facets, foam, fresnel, ripples, underside) |
| `env_rain.gdshader` | spatial | one rain streak quad |
| `env_rain_splash.gdshader` | spatial | splash ring MultiMesh |
| `env_lit_window.gdshader` | spatial | hook: `M_Window` glass, lit panes at night |
| `env_lamp_glow.gdshader` | spatial | hook: `M_LampGlow` lamp lens and `P_Neon*` signage |
| `env_underwater.gdshader` | canvas_item | underwater screen treatment |
| `env_wet.gdshaderinc` | include | hook: wet-surface functions for any ground / road shader |
| `env_wet_ground.gdshader` | spatial | reference ground / road material built on the include |

Design rules:

- **The look is a pure function** of `(WorldClock.hour, Weather.*, underwater state)`. It is
  recomputed every frame in `EnvironmentSystem._update()`, so `WorldClock.set_hour()` and
  `Weather.set_weather()` (admin menu) show up in the same frame; `refresh()` forces it at once.
  The only thing that lags is the sky radiance cube map (incremental, a handful of frames).
- **Colour keys are indexed by the sine of the sun elevation** (`SkyController.KEYS`), not by the
  hour: dawn and dusk are symmetric and nothing has to be retuned when sunrise / sunset move.
- **No per-object scripts.** Windows, lamps, neon and wet ground are shared ShaderMaterials driven
  by global uniforms. Only the pooled lights, the rain emitter and the ocean follow the camera.
- **Works without neighbours and in `--headless`.** The world, player, audio and UI are reached
  through `Game.*`, `has_method()` and null checks. With no camera the system still updates the
  uniforms; with no world the underwater test simply uses the wave height.
- The system runs with `PROCESS_MODE_ALWAYS` (so a paused admin menu still shows changes) but
  freezes its own animation clock (`gta_time`) while the tree is paused.

Boot: `BootManifest` instantiates `environment_system.gd`, `Game.register_system("environment")`,
then `setup()`. The helpers are built in `_ready()`; lamp registrations that arrive earlier are
queued and replayed.

---------------------------------------------------------------------------------------------------

## 2. Autoload APIs

### 2.1 WorldClock (`gta/code/world/world_clock.gd`)

Frozen contract members are unchanged (`hour, day, rate, paused, get_hour(), set_hour(),
advance_hours(), get_phase(), is_night(), get_daylight(), get_time_string(), get_save_data(),
load_save_data()`). Time follows the scene tree: it stops while the tree is paused and scales with
`Engine.time_scale`. It only runs after `Game.is_ready`.

| member | meaning |
|---|---|
| `rate` | game seconds per real second. Default 60 = **24 game hours in 24 real minutes** |
| `get_phase()` | `"dawn"` 5-7, `"day"` 7-18.5, `"dusk"` 18.5-20.5, `"night"` otherwise |
| `get_daylight()` | smooth 0..1 (0 before 05:00 and after 20:30, 1 from 07:00 to 18:45) |
| `is_night()` | `hour < 5.5 or hour >= 20` |
| `set_hour(h)` | jump inside the current day; emits `EventBus.time_changed`, `day_phase_changed` if needed, and `time_jumped` |
| `advance_hours(h)` | skip forward, rolls `day`, adds to `total_hours` (weather dries / soaks for the skipped time) |

Additions: signals `time_jumped(hour)`, `day_changed(day)`; `total_hours` (monotonic, not touched
by `set_hour`); `phase_at(h)`, `daylight_at(h)`, `get_night_factor()`, `is_day()`, `get_minute()`,
`get_day()`, `get_day_fraction()`, `get_day_length_minutes()`, `set_day_length_minutes(min)`,
`set_rate(r)`, `set_paused(on)`, `get_sun_direction()`, `sun_direction_at(h)`,
`get_sun_elevation()`, `get_moon_direction()`, `moon_direction_at(h)`.
The sun rises in the east (+X) at 05:36, culminates in the south (+Z, 28 degrees tilt) and sets
in the west (-X) at 19:54. The moon is up from 19:18 to 06:12.

`EventBus.time_changed(hour)` fires once per game minute, `EventBus.day_phase_changed(phase)` on
each phase change.

Command line (after `--`): `--hour=13.5`, `--clock-rate=600`, `--freeze-time`.
Save data: `{hour, day, total_hours}`.

### 2.2 Weather (`gta/code/world/weather.gd`)

Frozen contract members are unchanged (`TYPES, current, previous, auto_cycle, transition,
cloud_cover, rain_intensity, fog_amount, wetness, wind_strength, lightning_flash, wind_direction,
get_weather(), set_weather(), get_grip_multiplier(), get_visibility(), is_raining(),
get_save_data(), load_save_data()`).

Presets (targets of the blended parameters):

| type | cloud_cover | rain_intensity | fog_amount | wind_strength | storminess |
|---|---|---|---|---|---|
| clear | 0.14 | 0 | 0 | 0.20 | 0 |
| cloudy | 0.66 | 0 | 0.06 | 0.36 | 0 |
| rain | 0.93 | 0.62 | 0.24 | 0.52 | 0 |
| fog | 0.50 | 0 | 1.0 | 0.08 | 0 |
| storm | 1.0 | 1.0 | 0.36 | 1.0 | 1.0 |

- `set_weather(id, sec = 8.0)` blends from the **current values** (no pop even when a blend is
  interrupted) with a smoothstep; rain starts only after the clouds have closed (last 75 % of the
  blend) and stops in the first 70 %. `sec <= 0` is instant. Emits `EventBus.weather_changed`.
- `snap_weather(id, wetness = -1)` (addition): instant including the ground state (soaked for
  rain / storm, damp for fog, dry otherwise, or the given wetness). Used by loading, tests, photo.
- **Wetness** rises in rain (soaked after about 24 s of full rain) and dries afterwards (about
  2 minutes; faster in sun and wind, slower on an overcast night). Dense fog keeps the ground
  damp (0.22). Both follow the clock rate loosely; `advance_hours()` applies the skipped time.
- **Automatic cycle** (`auto_cycle`): every 0.8-5.5 game hours (per type) the next type is rolled
  from a transition table. From clear weather 88 % of the rolls stay clear / cloudy (measured:
  3524 of 4000); storms only follow cloud or rain; fog is 3.2x more likely between 03:30 and
  08:30 and rare otherwise. Automatic changes blend over 40 real seconds.
- **Lightning**: while `storminess >= 0.35` a bolt strikes every 5-15 s. `lightning_flash` pulses
  (main flash + one or two after-flashes, exponential decay) and `lightning_strike(distance,
  delay)` fires; the environment system plays `thunder_1` / `thunder_2` after `distance / 343` s,
  quieter and duller with distance, and adds a small camera shake for close strikes.
- `get_grip_multiplier()` = 1.0 dry .. 0.75 soaked. `get_visibility()` = 160 m clear .. 45 m in
  dense fog (rain preset 117 m, storm 91 m).

Additions: signals `lightning_strike`, `transition_finished(id)`; `storminess`, `PRESETS`,
`DISPLAY_NAMES`, `get_display_name(id)`, `get_wind_vector()`, `get_storminess()`,
`is_transitioning()`, `get_hours_until_change()`, `set_auto_cycle(on)`,
`trigger_lightning(distance = -1)`, `roll_next_weather()`.

Command line: `--weather=storm` (also switches the cycle off), `--no-weather-cycle`.
Save data: `{current, wetness, auto_cycle, hours_until_change}`.

---------------------------------------------------------------------------------------------------

## 3. Environment system API

Always go through the soft dependency:

```gdscript
var env := Game.get_system("environment")
if env != null and env.has_method("get_wave_height"):
    y = env.get_wave_height(x, z)
```

| method | purpose |
|---|---|
| `get_wave_height(x, z) -> float` | world Y of the sea surface including the rendered waves (boats, swimming). Fallback for callers: `Game.WATER_LEVEL` |
| `get_water_normal(x, z) -> Vector3` | approximate surface normal (boat pitch / roll) |
| `get_water_level() -> float` | `Game.WATER_LEVEL` |
| `register_light_points(points, color, light_range, energy)` | lamp positions for the pooled night lights; entries may be `Vector3`, `Transform3D` or `Node3D`. Defaults: warm white, 15 m, 3.0 |
| `clear_light_points()` / `get_light_point_count()` / `get_active_light_count()` | pool management / debug |
| `get_window_material()` | shared window glass (auto pane mode) |
| `get_window_material_mode(mode)` / `get_window_material_world()` | explicit pane mode (see 4.1) |
| `get_lamp_material(color = warm)` | lamp lens: off by day, emissive at night (cached per colour) |
| `get_neon_material(color)` | signage: always emissive, stronger at night (cached per colour) |
| `get_night_material_for(name, source)` | hook material for a Blender material name, or `null` |
| `apply_night_materials(root) -> int` | swaps every `M_Window` / `M_LampGlow` / `P_LampWarm` / `P_Neon*` surface under `root`; returns the number of swapped surfaces |
| `make_wet_surface_material(color, puddles, roughness, use_vertex_color)` | new material on the reference wet-ground shader |
| `is_camera_underwater()` + signal `underwater_changed(on)` | underwater state of the ACTIVE CAMERA |
| `get_sun_direction()` / `get_light_direction()` / `get_sun_light()` / `get_environment()` | for effects that need the key light or the Environment resource |
| `refresh()` | re-apply the whole look now |
| `set_enabled(on)` | BootManifest hook: off freezes the last look |
| `get_debug_info() -> Dictionary` | time, phase, weather, night, wetness, underwater, light counts, wave amplitude |

Public state: `night_factor` (the value of `gta_night`), `time_seconds` (`gta_time`),
`is_underwater`, `underwater_depth`, and the helper nodes `sky`, `ocean`, `rain`, `light_pool`.

### 3.1 Global shader uniforms

Declared in `project.godot`; written every frame by `EnvironmentSystem._push_globals()` only.

| uniform | type | value |
|---|---|---|
| `gta_daylight` | float | `1 - gta_night` |
| `gta_night` | float | 0 day .. 1 night. **Not just the clock:** gloomy weather lifts it (up to 0.55 in a storm, 0.30 in dense fog) so lamps and windows come on under a dark sky |
| `gta_wetness` | float | `Weather.wetness` |
| `gta_rain` | float | `Weather.rain_intensity` |
| `gta_time` | float | seconds of unpaused play (animation clock; also the wave clock) |
| `gta_wind` | vec3 | wind direction * strength |
| `gta_underwater` | float | 1 while the active camera is below the sea surface |
| `gta_player_pos` | vec3 | player position (camera position when there is no player) |

Gameplay code that needs "is it dark" should use `WorldClock.get_daylight()` /
`WorldClock.is_night()`; shaders use `gta_night`.

### 3.2 Underwater

The active camera is underwater when it is more than 3 cm below `get_wave_height()` at its
position (and, when the world exists, `world.is_water_at()` agrees - a camera clipped under the
terrain is not "in the sea"). Then: `gta_underwater = 1`, depth fog switches to a dense blue-green
(density 0.042, visibility roughly 25-40 m, darker with depth and at night), the key light and
ambient are tinted and dimmed with depth, the rain stops, the screen overlay adds refraction
wobble, absorption tint, vignette and faint light shafts, the ocean shows a readable underside,
and `Audio.set_underwater(on)` is called if the audio manager has that method.

### 3.3 Ocean

One mesh, one draw call: a grid with 2 m cells within 80 m of the camera that grows geometrically
out to about 12.8 km (the horizon), snapped to the 2 m cell so vertices never swim. Vertex waves
are a sum of four sines with a total amplitude of 0.10 m (calm) to 0.25 m (storm, driven by
`Weather.wind_strength`); they fade out between 58 m and 76 m from the camera, where the facets
are sub-pixel anyway. `OceanSurface.get_height()` evaluates **the same function with the same
constants and the same clock** on the CPU; the constants at the top of `ocean_surface.gd` and
`env_ocean.gdshader` must stay identical.

Shading: depth-based colour from the depth texture (shallow turquoise -> mid -> deep blue),
transparency by water thickness, flat facet normals rebuilt per fragment on a world-space
triangle grid, animated foam where the water meets the shore or anything standing in it,
whitecap facets in strong wind, rain ripples near the camera, fresnel sky tint. Palettes for
clear / storm / night are blended in `EnvironmentSystem`. The mesh is in group `water_surface`.
It has no collider: the sea is a height (`Game.WATER_LEVEL` / `get_wave_height`), not a body.

---------------------------------------------------------------------------------------------------

## 4. Shader hooks for other modules

### 4.1 Night lights on imported meshes (city builder, props, landmarks)

Blender material name -> hook:

| Blender material | hook | look |
|---|---|---|
| `M_Window` (prefix match, so `M_Window.001` works) | `get_window_material()` | reflective glass by day; at night a pseudo-random 46 % of the panes (78 % on the ground floor) glow warm / cool / TV-blue, switching on one by one through dusk, a few rooms toggling every minute or two |
| `M_LampGlow`, `P_LampWarm` | `get_lamp_material()` | pale lens by day, emissive from `gta_night` 0.28 to 0.50 |
| `P_Neon*` | `get_neon_material(color)` | always emissive (1.15), 3.8 at night, subtle buzz; the colour is taken from the imported material's emission or albedo |

One call does it for a whole building or prop:

```gdscript
var env := Game.get_system("environment")
if env != null and env.has_method("apply_night_materials"):
    env.apply_night_materials(building_root)     # surface overrides; mesh resources untouched
```

For MultiMesh or merged geometry assign the material yourself (`get_window_material()` ...).
All of them are shared instances: thousands of windows cost no script time and no extra
materials.

What is a "pane" (`cell_mode` of `env_lit_window.gdshader`):

| mode | name | when |
|---|---|---|
| 1 | UV cells | the building kit gives every `M_Window` face its own integer UV cell (`uv = (k % 64 + u, k / 64 + v)`): `floor(UV)` is the pane id. Exact for any window size |
| 2 | object grid | meshes without UVs: the 4 m module grid in object space (ground floor 4.0 m, upper floors 3.2 m) |
| 3 | world grid | geometry that was merged in world space |
| 0 | auto | 1 when the mesh has UVs, otherwise 2 |

`apply_night_materials()` picks 1 or 2 per surface from the mesh format. Each building gets its
own pattern from its origin, so two copies of one asset do not light up identically.

### 4.2 Pooled street lights

Register the lamp **lens** positions once (world space):

```gdscript
env.register_light_points(lamp_positions, Color(1.0, 0.82, 0.56), 15.0, 3.0)
```

At night (`gta_night` 0.30 -> 0.55) at most **14** real `OmniLight3D` without shadows sit on the
registered points nearest to a focus 14 m in front of the camera (max 95 m away) and fade in and
out over about 0.4 s as the camera moves; every other lamp is emissive-only. By day the pool is
off. Lookup is a 48 m grid, re-scanned five times per second, so thousands of points are cheap.
The lights use a soft falloff (`omni_attenuation` 0.55): energy 2-4 at 5-6 m height gives a clearly
readable pool on the street. Vehicle headlights, police lights and muzzle flashes are NOT part of
this pool - their owners must keep to the shared budget (16 positional lights near the player).

### 4.3 Wet surfaces (roads, pavements, ground)

`gta_wetness` is global, so any shader can react to rain. The include does the work and declares
no uniforms of its own:

```glsl
shader_type spatial;
global uniform float gta_wetness;
global uniform float gta_rain;
global uniform float gta_time;
#include "res://gta/code/world/shaders/env_wet.gdshaderinc"

void fragment() {
    vec3 albedo = my_colour;  float rough = 0.9;  float spec = 0.5;
    vec3 wn = normalize(v_world_normal);                      // WORLD-space normal (varying)
    float puddle = env_puddle_mask(v_world.xz, wn.y, gta_wetness, 1.0);
    env_wet_surface(albedo, rough, spec, gta_wetness, puddle, 0.8, 1.0);
    vec3 n = env_wet_normal(wn, v_world.xz, puddle, gta_rain, gta_time);
    ALBEDO = albedo;  ROUGHNESS = rough;  SPECULAR = spec;
    NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
```

| function | parameters |
|---|---|
| `env_puddle_mask(world_xz, up_facing, wetness, puddles)` | `puddles` 0..1 = how much standing water the material collects (asphalt 1, pavement 0.5, sand / grass 0.1-0.2). Puddles grow out of fixed low spots as the wetness rises and shrink while it dries; only on nearly level faces |
| `env_wet_surface(albedo, roughness, specular, wetness, puddle, porosity, gloss)` | `porosity` = darkening (concrete / sand 0.8, paint / metal 0.1); `gloss` = shine when damp (asphalt 1, pavement 0.7, sand / grass 0.2) |
| `env_wet_normal(world_normal, world_xz, puddle, rain, time)` | level water with rain rings inside puddles |
| `env_rain_ripple(world_xz, rain, time)` | the ring normal offset alone |

`env_wet_ground.gdshader` is the reference implementation (flat tint or vertex colour);
`env.make_wet_surface_material(color, puddles, roughness, use_vertex_color)` returns a material
on it. Puddles mirror the sky radiance and the pooled street lights - there are no screen-space
reflections. The darkening is deliberately moderate so a rainy night stays readable.

### 4.4 Other hooks

- Rain is blocked by roofs through a camera-following `GPUParticlesCollisionHeightField3D`
  (40 x 48 x 40 m, 256 px, updated only when it moves 4 m). Anything that renders on the default
  layers occludes it - nothing to do for interiors, canopies or vehicles. Start the game with
  the flag `no_rain_collision` in `Game.flags` to switch it off.
- Splash rings need static colliders on `Layers.WORLD` / `Layers.VEHICLE` (8 rays per physics
  tick at most).
- `Audio.set_underwater(bool)` is called when the camera crosses the surface, if it exists.
- Sounds played by this module: `thunder_1`, `thunder_2` (bus `Ambience`). Rain / wind / ocean
  loops belong to the ambience system, which can read `Weather.rain_intensity`,
  `Weather.wind_strength` and `is_camera_underwater()`.

---------------------------------------------------------------------------------------------------

## 5. Tunables

| where | constant | default | effect |
|---|---|---|---|
| `world_clock.gd` | `GAME_SECONDS_PER_REAL_SECOND` | 60 | length of the day (24 real minutes) |
| | `DAWN_START, DAY_START, DUSK_START, NIGHT_START` | 5, 7, 18.5, 20.5 | phase boundaries |
| | `SUNRISE_HOUR, SUNSET_HOUR, SUN_TILT_DEG` | 5.6, 19.9, 28 | sun path |
| `weather.gd` | `PRESETS` | table in 2.2 | per-type targets |
| | `AUTO_WEIGHTS, AUTO_DURATION` | - | automatic cycle |
| | `AUTO_TRANSITION_SEC` | 40 | blend time of automatic changes |
| | `WET_SECONDS, DRY_SECONDS, FOG_DAMPNESS` | 24, 120, 0.22 | ground wetness |
| | `LIGHTNING_MIN_GAP, LIGHTNING_MAX_GAP` | 5, 15 | seconds between strikes |
| `sky_controller.gd` | `KEYS` + colour tables | - | sky top / horizon, sun light, ambient, clouds per sun elevation |
| | `MOON_LIGHT_ENERGY, MOON_LIGHT_COLOR` | 0.30, cool blue | night key light |
| | `BASE_FOG_DENSITY, FOG_WEATHER_DENSITY` | 0.00022, 0.0105 | clear-day haze, extra at full fog |
| | `UNDERWATER_FOG_DENSITY` | 0.042 | underwater visibility |
| | `apply_shadow_quality()` | level 2 | 0 off, 1: 2 splits 110 m, 2: 4 splits 170 m, 3: 4 splits 200 m blended (`Settings` key `shadows`) |
| | Environment block in `_build()` | - | filmic tonemap (white 6), glow (threshold 1.05, intensity 0.5 day / 0.8 night), SSAO (radius 1.4, intensity 1.6), saturation 1.20, contrast 1.06 |
| `ocean_surface.gd` | `FINE_CELL, FINE_HALF, FAR_EXTENT, GROWTH` | 2, 80, 12000, 1.13 | mesh density / reach |
| | `CALM_WAVE_AMP, MAX_WAVE_AMP` | 0.10, 0.25 | wave amplitude range |
| | `WAVE_*` arrays | - | wave set (**mirror in the shader**) |
| `environment_system.gd` | `WATER_*` palettes, `FOAM_COLOR` | - | sea colours clear / storm / night |
| `env_rain.gd` | `MAX_DROPS` | 1400 | particle budget (<= 1500); `amount_ratio` = 0.12 + 0.95 * intensity |
| | `MAX_SPLASHES, SPLASHES_PER_SECOND, MAX_RAYS_PER_TICK` | 128, 240, 8 | splash rings |
| `env_light_pool.gd` | `POOL_SIZE` | 14 | real street lights (budget 16) |
| | `MAX_DISTANCE, FOCUS_AHEAD, FADE_SPEED` | 95, 14, 2.6 | selection and fading |
| | `NIGHT_START, NIGHT_FULL, LIGHT_ATTENUATION` | 0.30, 0.55, 0.55 | switch-on range, falloff |
| `env_lit_window.gdshader` | `lit_fraction, ground_lit_fraction, emission_energy, flicker_share` | 0.46, 0.78, 2.1, 0.18 | night windows |
| `env_night_materials.gd` | lamp `night_energy` 4.5; neon `day_energy` 1.15, `night_energy` 3.8 | | emissive strength |

---------------------------------------------------------------------------------------------------

## 6. GPU cost and safety

Measured in `env_shots` on the shared RTX 5070 at 1280x720, 30 fps cap, look-dev stage (not the
real city): **0.44-0.73 ms GPU per frame** for the whole view in all 17 situations
(`RenderingServer.viewport_get_measured_render_time_gpu`); the sky + ocean alone take 6 draw
calls. These numbers are for the test stage only - they show that the environment itself is
cheap, not what the finished city will cost.

| feature | cost | bound |
|---|---|---|
| sun / moon | 1 `DirectionalLight3D`, the only shadow caster of this module | 4 PSSM splits, 170 m (200 m on "high"), default atlas size |
| sky | 1 full-screen pass: 9 value-noise lookups (two 4-octave fbm + 1) + stars; the radiance cube map skips clouds, discs and stars | radiance 128 px, incremental updates |
| ocean | 1 draw call, 70,688 triangles, 1 depth-texture read, 3 wave evaluations and about 20 hash lookups per fragment | amplitude <= 0.25 m |
| rain | 1 `GPUParticles3D`, off (not drawn) in dry weather | <= 1400 quads of 3 x 78 cm; 1 height field 256 px; 128 splash instances; <= 8 rays per physics tick |
| street lights | `OmniLight3D` without shadows | <= 14, off by day |
| windows / lamps / neon | emissive only, shared materials | 0 lights, 0 scripts |
| glow | 4 mip levels, HDR threshold 1.05 | moderate; only real emitters bloom |
| SSAO | engine default quality | moderate (intensity 1.6) |
| fog | depth fog only | - |
| underwater | 1 full-screen quad with one screen-texture read | only while submerged |

Deliberately **not** used: SDFGI, volumetric fog, SSR, SSIL, ReflectionProbes, shadowed
positional lights, screen-space refraction on the water, any render-target feedback.
No shader has an unbounded loop (the largest is the 4-octave fbm).

---------------------------------------------------------------------------------------------------

## 7. Tests

Both tests are independent of every neighbour module (long `--disable` list in the file headers).

```powershell
# logic (headless, about 49 simulated seconds; 3400 frames leave a margin) - 63 checks
tools\godot.ps1 -Mode headless -Frames 3400 -UserArgs '--test=env_cycle','--no_player','--seed=7','--disable=world,city,interactions,vehicles,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'

# look (windowed, about 17 s at the 30 fps cap) - 17 screenshots, 24 checks
tools\godot.ps1 -Mode window -Frames 520 -UserArgs '--test=env_shots','--no_player','--disable=world,city,interactions,vehicles,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
```

`env_cycle` covers: clock flow at the default rate, pause, a full day with the phases in order,
day roll-over, daylight / sun / moon functions, `set_hour` / `advance_hours`, weather blending
from the current values, rain onset, wetness up / down / time skip, grip and visibility,
lightning (manual, automatic, none in clear weather), the automatic cycle and its bias towards
fair weather, JSON-safe save data and a `SaveSystem` file round trip, wave bounds / motion /
storm amplitude, hook materials and `apply_night_materials`, the wet-surface material, the light
pool (off at noon, <= 14 at night, fades when the camera leaves), the underwater switch.

`env_shots` writes `qa/screenshots/env_01 .. env_17`: noon, sunset 19:30, night 23:00, rain
14:00, fog 09:00, storm 21:00, lightning flash, underwater, cloudy 16:30, dawn 06:10, water
close-up, street at night, street in rain at dusk, storm seen from under a canopy (no rain
below it), moon, wet road at night, drying road by day. `--env-only=<text>` keeps the shots
whose name contains the text. When there is no world it builds a **throw-away look-dev stage
from primitives** (beach, pier, four blocks, road, lamps) - that stage is test scaffolding and
never game content. With the world loaded the camera goes to the `beach`, `shipwreck` and
`downtown_plaza` locations instead.

---------------------------------------------------------------------------------------------------

## 8. Decisions, limits, open points

- **`gta_night` follows the gloom, not only the clock** (storm 0.55, dense fog 0.30), so lamps
  and windows switch on under a dark daytime sky. Use `WorldClock` for gameplay "night" checks.
- **Night is readable on purpose**: cool moon key light 0.30 plus a blue ambient of 0.72; a
  closed deck at night keeps a faint city glow and a slightly higher ambient.
- **Waves exist only within 76 m of the active camera** (render and CPU agree). A boat that is
  simulated far from the camera floats on a flat sea - invisible, but worth knowing.
- **No real reflections on the water or in puddles**: sky radiance plus specular highlights only.
- **The sun / moon is one light.** The sun light reaches zero just after sunset (about 19:58)
  and the moon light ramps in from about 20:11 to 20:41 (mirrored before sunrise: moon out by
  about 05:19, sun in from about 05:32). In the short gap the ambient alone carries the scene.
- **Sky radiance is incremental**: after a time jump the ambient / reflection cube map needs a
  few frames to catch up; direct light, fog and the visible sky change in the same frame.
- **Rain occlusion** is a top-down height field: rain does not fall under roofs, but it can be
  seen through a window from inside.
- The wet look only appears on surfaces whose shader uses the hook of 4.3. Imported
  `StandardMaterial3D` assets (buildings, props, vehicles) do not change in the rain.
- Not verified against the real island yet (the world system did not exist when this was
  written): the `env_shots` world-location camera path, foam on the real coast line, the
  underwater `is_water_at()` gate, `Audio.set_underwater` (no such method in the audio manager
  at the time of writing), and `apply_night_materials` on real building GLBs.
