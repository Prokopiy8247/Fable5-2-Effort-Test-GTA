# SPEC — Humanoid characters (rig, bodies, accessories, animation library) and animals

Read `tools/blender/SPEC_COMMON.md` first. Manifest: `gta/resources/data/manifests/characters.json`.
Suggested modules: `tools/blender/chr_rig.py` (rig + skin helpers), `chr_bodies.py`, `chr_accessories.py`,
`chr_anims.py` (pose DSL + clips), `animals.py`.

One shared skeleton drives the player, every pedestrian, police officer and tactical unit. Godot recolours body
regions per character and toggles accessory meshes, so region ids and names below are a hard contract.

## 1. Skeleton (armature object `<id>__rig`, identical for male and female)

Character faces **+Y**, left side is **−X**, feet on z = 0, total height **1.80**. Rest pose = relaxed standing,
arms hanging slightly away from the body (positions below).

| bone | head position (x, y, z) | parent |
|---|---|---|
| `Hips` | (0, 0, 0.96) | — |
| `Spine` | (0, 0, 1.08) | Hips |
| `Chest` | (0, 0, 1.26) | Spine |
| `Neck` | (0, 0, 1.48) | Chest |
| `Head` | (0, 0, 1.56) | Neck |
| `UpperArm_L` / `_R` | (∓0.20, 0, 1.43) | Chest |
| `LowerArm_L` / `_R` | (∓0.235, 0, 1.15) | UpperArm |
| `Hand_L` / `_R` | (∓0.265, 0, 0.89) | LowerArm |
| `Prop_L` / `Prop_R` | (∓0.275, 0.03, 0.80) | Hand (non-deforming attachment bone at the palm) |
| `UpperLeg_L` / `_R` | (∓0.095, 0, 0.93) | Hips |
| `LowerLeg_L` / `_R` | (∓0.095, 0, 0.51) | UpperLeg |
| `Foot_L` / `_R` | (∓0.095, 0, 0.09) | LowerLeg |

**Every bone points straight up**: tail = head + (0, 0, 0.1), no connect, and roll set so that
`bone.matrix_local.to_3x3()` has columns X=(1,0,0), Y=(0,0,1), Z=(0,−1,0) (use `edit_bone.align_roll((0,-1,0))` and
verify by printing). This makes every joint's rest rotation the identity in glTF/Godot, so pose rotations mean the
same thing everywhere. Bone-local axes are therefore: **X = character's right, Y = up, Z = back.**
Sign conventions (verify one empirically with `look` before authoring clips):
- +X rotation swings a hanging limb FORWARD (hip/shoulder flexion, elbow bend); −X on `LowerLeg` bends the knee;
  −X on `Spine`/`Chest`/`Neck`/`Head` leans/nods forward.
- +Y rotation turns to the character's left (yaw/twist).
- +Z rotation swings a hanging limb toward the character's right (+X): right-arm raise sideways = +Z, left = −Z.
After export, parse the GLB JSON chunk and confirm every joint node has rotation [0,0,0,1] (or none) and scale 1.

## 2. Bodies (`human_male`, `human_female`; category `Characters`; path `characters/<id>`)

Part `body`: ONE skinned mesh, material `Character`, coloured by region with `"@C<n>"`:

| n | region | n | region |
|---|---|---|---|
| 0 | skin: face, neck, ears | 8 | feet / shoes |
| 1 | torso (shirt) | 9 | hair: scalp cap faces + brows (+ all hair meshes) |
| 2 | upper arms (sleeves) | 10 | eyes (dark insets) |
| 3 | lower arms | 11 | headwear |
| 4 | hands | 12 | eyewear / face accessories |
| 5 | pelvis (belt line / shorts top) | 13 | torso overlay (vests, straps, packs) |
| 6 | upper legs | 14 | detail A: belt, collar, cuffs, badge, tie |
| 7 | lower legs | 15 | detail B: shoe soles, buckles, gear metal |

Style: stylised low-poly figure with believable proportions (≈ 7 heads), a little chunky: defined chest/waist/hips,
neck, head as a rounded box with jaw taper, small nose wedge, ears, inset eye quads (10), brows (9), mitten hands with
a thumb, blocky shoes with soles (15), belt (14), collar hint (14). 1200–2000 tris.
**Rigid "action figure" skinning**: build the body from overlapping closed segments (pelvis, abdomen, chest, neck,
head, upper arm, forearm, hand, thigh, shin, foot), each weighted 100 % to its bone, with rounded/ball ends at the
joints so bending never opens gaps or stretches. Smooth shade with `sharp_angle≈50`.
`human_female`: same skeleton and SAME head position/size (so accessories fit both) but narrower shoulders and
waist, wider hips, slimmer limbs, smaller hands/feet, softer jaw, chest shaping. Godot scales her to ≈ 0.94.
Create vertex groups named like the bones, add an Armature modifier, parent the mesh to the rig.

## 3. Accessories (objects `<id>__acc_<name>`, skinned 100 % to one bone, included in BOTH character GLBs, hidden by Godot unless equipped)

Head (bone `Head`): `acc_hair_short`, `acc_hair_side` (side part), `acc_hair_long`, `acc_hair_pony`, `acc_hair_afro`,
`acc_hair_mohawk`, `acc_hair_bun`, `acc_hair_bob` (all region 9), `acc_beard`, `acc_mustache` (9), `acc_cap`
(baseball cap, 11), `acc_beanie` (11), `acc_hat_brim` (sun hat, 11), `acc_cap_police` (peaked cap, 11 with 14 badge),
`acc_helmet_tactical` (11, goggles 12), `acc_helmet_moto` (full-face, 11, visor 12), `acc_glasses` (12),
`acc_sunglasses` (12), `acc_bandana` (lower-face mask, 12), `acc_scuba_mask` (12).
Torso (bone `Chest`): `acc_vest_tactical` (plate carrier with pouches, 13 + 15), `acc_vest_safety` (hi-vis vest, 13),
`acc_tie` (14), `acc_badge` (14), `acc_backpack_chute` (parachute pack + straps, 13 + 15), `acc_scuba_tank` (13 + 15).
Hips (bone `Hips`): `acc_holster` (14), `acc_skirt` (short skirt shell, 6).
Hair/hat meshes must fully cover the scalp cap they replace and must not intersect the face.

## 4. Animation library (Actions on the `human_male` rig, 30 fps, exported with `K.export_asset(root, "characters/human_male", animations=True)`)

Write a small pose DSL: `clip(name, length, {frame: {bone: (rx, ry, rz) degrees, "Hips@loc": (dx, dy, dz)}}, loop=True)`
that keys `rotation_euler` (set `rotation_mode='XYZ'`) and Hips location, makes looping clips seamless (first key ==
last key, cyclic), and supports mirroring L/R poses. All clips are **in place** (no horizontal travel of Hips beyond
small sway); vertical Hips motion is fine and expected. Keep feet planted believably: when Hips drops, legs bend.
Stash each Action so it exports (fake user + NLA track or `export_animation_mode="ACTIONS"`), and confirm the exported
GLB contains every clip by listing `animations[].name` from the GLB JSON.
`human_female` is exported WITHOUT animations (Godot shares the library).

Exact clip names (L = looping):

Locomotion: `Idle` (L, 60 f, breathing + tiny weight shift), `Walk` (L, 32 f, relaxed arm swing), `Run` (L, 20 f,
jog, elbows bent), `Sprint` (L, 16 f, forward lean, big stride), `CrouchIdle` (L, 60 f, knees bent, torso low),
`CrouchWalk` (L, 32 f), `Jump` (10 f, crouch → extended take-off pose, holds last frame), `Fall` (L, 30 f, airborne,
arms out, slight flail), `Land` (10 f, absorb and recover), `Roll` (20 f, tucked forward combat roll returning to
crouch).
Water / climbing: `SwimIdle` (L, 40 f, treading water upright), `Swim` (L, 30 f, body horizontal face-down, crawl
stroke + flutter kick), `Dive` (L, 36 f, horizontal underwater breast stroke), `ClimbLadder` (L, 24 f, alternating
hands/feet, body upright facing +Y), `Vault` (18 f, hands plant forward, legs swing over), `Mantle` (24 f, arms
reach up, pull, knee up, stand).
Vehicles: `SitCar` (L, 60 f, seated, knees ~90°, both hands forward on a wheel at chest height), `SitPassenger`
(L, 60 f, hands on thighs), `SitBike` (L, 60 f, forward lean, arms extended to bars, feet back on pegs), `Carjack`
(20 f, reach in with both arms and yank back/to the side).
Combat (full body unless noted): `AimPistol` (L, 60 f, two-handed pistol stance: both arms extended forward at eye
level, slight crouch), `AimRifle` (L, 60 f, rifle shouldered: right hand at the grip near the right chest, left arm
forward supporting), `HoldRifle` (L, 60 f, low-ready across the body), `Reload` (30 f, left hand drops to the belt
and comes back up to the weapon), `Punch_L`, `Punch_R` (12 f each, jab from guard), `Kick` (18 f, front push kick),
`SwingBat` (16 f, two-handed horizontal swing from the right shoulder), `Stab` (12 f, right-hand thrust), `Throw`
(20 f, overarm throw with the right arm), `Block` (L, 30 f, forearms raised guard), `HitReact_F` (10 f, flinch
backward), `HitReact_B` (10 f, stumble forward), `Knockdown` (20 f, falls onto the back, ends lying), `GetUp` (30 f,
from lying on the back to standing), `Death_Back` (24 f, collapse backward, hold), `Death_Front` (24 f, collapse
forward, hold), `Takedown` (24 f, attacker: grab from behind and strike), `TakedownVictim` (24 f, stiffen then slump
to the ground).
Cover / stealth: `CoverLow` (L, 60 f, crouched with the BACK to a wall, weapon held up at the chest), `CoverHigh`
(L, 60 f, standing with the back to a wall).
Misc: `HandsUp` (L, 40 f, both hands raised), `Cower` (L, 30 f, crouched, hands over the head, trembling),
`Surrender` (L, 40 f, kneeling, hands behind the head), `PhoneCall` (L, 60 f, right hand at the ear), `PhoneUse`
(L, 60 f, right hand holding a phone in front of the chest, head tilted down), `Talk` (L, 80 f, casual hand
gestures), `Sit` (L, 60 f, seated on a bench, relaxed), `Wave` (30 f, right arm raised hailing), `Parachute` (L,
40 f, hanging under a canopy, arms up holding toggles, legs slightly forward), `Freefall` (L, 30 f, belly-to-earth
arch, arms and legs spread and bent).

QA: for each family use `look` with `mode: "frames"`, `target: ["human_male"]`, `frame_count` 4–6,
`view: [0.9, -0.5, 0.25]` (set the rig's active action and scene frame range first). Fix poses that intersect the
body badly, feet that float/sink, broken silhouettes. Readable, intentional, slightly stylised motion beats realism.

## 5. Animals (category `Animals`; path `animals/<id>`; NO armature — rigid parts animated by code in Godot)

Front = +Y, feet on z = 0, origin under the body centre. Parts (exact names, each a separate object whose ORIGIN is at
its joint so Godot can rotate it): quadrupeds `body`, `head` (head + neck, origin at the neck base), `leg_fl`,
`leg_fr`, `leg_rl`, `leg_rr` (origins at shoulder/hip, legs hang down), `tail` (origin at its base).

| id | size | notes |
|---|---|---|
| `deer` | length 1.7, shoulder 1.05 | slender, antlers on the head, `fur_deer` + `fur_light` belly/tail |
| `rabbit` | length 0.38 | long ears (part of `head`), `fur_gray`/`fur_light` |
| `coyote` | length 1.15, shoulder 0.55 | lean, bushy tail, `fur_gray` + `fur_light` |
| `dog` | length 0.95, shoulder 0.55 | medium mixed-breed dog, floppy ears, collar (`red`), `fur_dark`/`fur_light` |
| `cat` | length 0.5 | upright tail, `fur_gray` or `orange`-ish |
| `seagull` | wingspan 1.25 | parts `body`, `head`, `wing_l`, `wing_r` (origin at the wing root, wing extends toward ∓X, flat spread), `tail`; `feather_white`, grey wing tops, `beak_orange` |
| `fish` | length 0.35 | parts `body`, `tail` (origin at the tail base); `fish_silver`; plus `fish_b` in `fish_orange` with a different shape |
| `shark` | length 3.3 | parts `body` (with dorsal + pectoral fins), `tail` (origin at the tail base, swings about Z), `shark_gray`/`shark_belly`; origin at the body centre |

Animals: flat-shaded or `sharp_angle=40`, 200–600 tris each, expressive readable silhouettes.

Order: rig + `human_male` body → verify skinning by posing → core clips (Idle, Walk, Run, Sprint, Jump, Fall, Land,
SitCar, AimPistol, AimRifle, Punch_L/R, Death_Back) → export + manifest → `human_female` → accessories → remaining
clips → animals. In the manifest list `"bones"`, `"accessories"`, `"animations"` (name, length in frames, loop).
