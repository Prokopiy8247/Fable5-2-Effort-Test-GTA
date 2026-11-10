# SPEC — Weapons, attachments, projectiles, pickups, held items

Read `tools/blender/SPEC_COMMON.md` first. Manifest: `gta/resources/data/manifests/weapons.json`.
Suggested modules: `tools/blender/wpn_firearms.py`, `wpn_melee_misc.py`, `wpn_pickups.py`.
Category for `K.begin_asset`: `"Weapons"` (row spacing 2 m). Original generic designs only — no real-world brand
replicas, no GTA designs. They must read as proper game weapons, never as boxes.

## Contract

- **Origin at the firing-hand grip** (centre of the palm on the pistol grip / handle). Barrel / blade / business end
  points **+Y**, top is +Z, left side −X. Real-world scale.
- Colours: main metal (receiver, slide, barrel shroud) = **`tint_a_metal`** (Godot tints it: default gunmetal; weapon
  finishes recolour it). Polymer furniture (grips, handguards, stocks) = **`tint_b`** (default near-black) unless it is
  wood (`wood_mid`/`wood_dark`). Small fixed details: `black`, `steel`, `steel_dark`, `brass`, `rubber`,
  sights tips `led_green`/`white`, safety markings `red`.
- Parts (objects `<id>__<part>`; omit those that do not apply):
  - `body` — everything that does not move.
  - `mag` — detachable magazine, origin at its top (where it enters the well). `mag_ext` — longer/extended (or drum)
    variant at the same origin (Godot hides one of them).
  - `slide` (pistols; moves along −Y when firing), `pump` (pump-action fore-end; slides along Y), `bolt` (charging
    handle / bolt on rifles), `cylinder` (revolver; origin on its axis, spins about Y), `rocket_loaded` (warhead
    visible in the launcher muzzle).
- Markers: `muzzle` (barrel end, +Y forward), `eject` (ejection port), `hand_l` (support-hand palm position; for
  one-handed weapons put it where a two-handed grip would support), `scope` (top-rail mount point, centre of the
  rail), `under` (under-barrel mount point), `suppressor` (= muzzle thread position).
- Budget ≤ 900 tris per firearm (attachments ≤ 250). Chamfer the big shapes; add trigger guard, sights, ejection
  port, rail, controls, sling loops, vents — the secondary shapes are what make them look finished.
- QA views: `views: ["right", "three_quarter", "top"]`, `max_size` 512, 3–4 weapons per shot.

## P1 — Firearms (path `weapons/<id>`)

| id | overall length | description |
|---|---|---|
| `pistol` | 0.20 | Compact semi-auto: slide, frame, grip with texture ribs, mag in the grip, small rail. Parts body, slide, mag, mag_ext. |
| `revolver` | 0.27 | Heavy 6-shot revolver, 0.15 barrel with under-lug, wood grip. Parts body, cylinder. |
| `smg` | 0.46 | Compact SMG: boxy receiver, short barrel, mag in front of the trigger guard, folding wire stock (folded/extended is fine), top rail. Parts body, mag, mag_ext, bolt. |
| `shotgun_pump` | 1.00 | Pump shotgun: long barrel + tube magazine, wood stock and pump. Parts body, pump. |
| `shotgun_auto` | 0.95 | Semi-auto combat shotgun: polymer stock with pistol grip, heat shield, box/drum mag. Parts body, mag, mag_ext. |
| `rifle_assault` | 0.90 | Assault rifle: receiver, handguard with vents, curved mag, stock, front post + rear sight, top rail. Parts body, mag, mag_ext, bolt. |
| `rifle_carbine` | 0.80 | Modern carbine, DIFFERENT silhouette (bullpup or straight-mag flat-top with skeleton stock). Parts body, mag, mag_ext, bolt. |
| `rifle_marksman` | 1.10 | Semi-auto marksman rifle: long barrel, wood or tan furniture, short mag, bipod stubs. Parts body, mag, mag_ext, bolt. |
| `rifle_sniper` | 1.25 | Bolt-action sniper: heavy fluted barrel with muzzle brake, adjustable stock with cheek rest, bolt handle, small box mag. Parts body, mag, bolt. (Scope is an attachment.) |
| `launcher_rocket` | 1.10 | Shoulder launcher tube with flared ends, grip + trigger group under the tube, sight bracket, shoulder rest. Parts body, rocket_loaded. Marker `muzzle` at the front of the tube, `back` at the rear (back-blast). |
| `launcher_grenade` | 0.72 | Revolver-style 6-shot grenade launcher: big cylinder, short fat barrel, folding stock, foregrip. Parts body, cylinder. |

## P1 — Melee and throwables

| id | size | description |
|---|---|---|
| `knife` | 0.30 | Combat knife: blade (`steel`) with clip point + fuller, guard, wrapped handle. Blade toward +Y. |
| `bat` | 0.85 | Baseball bat (`wood_light`), grip tape at the handle; origin near the knob, bat extends +Y. |
| `crowbar` | 0.65 | Hex bar with hooked claw end (`red` paint worn to `steel` at the tips). |
| `nightstick` | 0.60 | Police baton with side handle (`black`). |
| `grenade` | 0.10 | Frag grenade: segmented body (`military_green`), lever, pin ring. Origin centre. |
| `rocket` | 0.55 | Rocket projectile: warhead, body, 4 fins, nozzle. Origin centre, flies toward +Y. |
| `grenade_40mm` | 0.10 | Launcher round (`brass` case, `gold`-ish nose). Origin centre. |

## P1 — Attachments (origin at the mount point; path `weapons/att/<id>`)

`att_suppressor` (⌀0.04 × 0.16, origin rear-face centre, extends +Y), `att_suppressor_large` (⌀0.05 × 0.22),
`att_scope_reddot` (compact reflex sight, origin bottom centre), `att_scope_4x` (0.20 tube scope on a mount),
`att_scope_sniper` (0.36 long, large objective, turrets), `att_flashlight` (origin TOP centre — hangs under the
barrel; lens `emis_always_white`; marker `light` at the lens, +Y forward), `att_grip` (vertical foregrip, origin top
centre), `att_laser` (small box with `led_red` emitter; marker `light`).

## P2 — Pickups (path `pickups/<id>`; origin centre; they float and spin in game, so make them readable from all sides, ≈ 0.4–0.6 m)

`pickup_health` (white med-kit with a GREEN plus — no red cross), `pickup_armor` (ballistic vest, `police_blue`/dark),
`pickup_ammo` (olive ammo can with brass rounds visible), `pickup_cash` (banded stack of green banknotes),
`pickup_cash_big` (open briefcase full of stacks), `pickup_parachute` (packed rig with straps), `pickup_scuba`
(tank + regulator), `pickup_snack` (burger + soda cup combo), `pickup_wrench` (crossed wrench + toolbox, repair),
`pickup_bribe` (gold police-style star token), `pickup_weapon_crate` (small military crate, generic).

## P2 — Held / special items

`phone` (smartphone 0.075 × 0.009 × 0.15 standing upright in the XZ plane, screen `screen_blue` facing −Y (toward the
holder), camera bump on the back; origin centre; path `weapons/phone`).
`parachute_canopy` (path `weapons/parachute_canopy`): ram-air canopy, span 7.5 (X) × chord 3.0 (Y), 7–9 cells, gentle
arc, open leading edge, `tint_a` with `tint_b` centre stripe and stabiliser panels, double-sided; ~16 thin suspension
lines converging to two riser points ±0.2 on X at the ORIGIN (origin = the jumper's shoulders); canopy centre ≈ 5.5 m
above the origin and slightly behind (−Y 0.6). Single part `mesh`, ≤ 900 tris.
`fx_muzzle_flash` (path `vfx/fx_muzzle_flash`): 3 crossed tapered quads + a short star cone, `emis_always_amber` core
with `emis_always_white` centre, origin at the base, extends +Y 0.35, double-sided.
`fx_tracer` (path `vfx/fx_tracer`): thin elongated diamond 1.0 long on Y, ⌀0.02, `emis_always_white`.

In the manifest add per weapon: `"length"`, `"parts"`, `"markers"` with their positions (x, y, z).
Order: pistol → rifle_assault → shotgun_pump → smg → rest of firearms → melee/throwables → attachments → pickups → held items.
