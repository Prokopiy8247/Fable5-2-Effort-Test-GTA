"""chr_bodies - human_male / human_female low-poly bodies (rigid "action figure" skinning).

    import chr_bodies as B; importlib.reload(B)
    B.build("human_male")          # root + rig (kept if present) + `<id>__body`
    B.build_all()                  # both characters

One skinned mesh per character, material `Character`, coloured by region ("@C<n>", see SPEC_CHARACTERS.md).
The body is made of overlapping CLOSED shells, each weighted 100 % to one bone, with rounded ends centred on
the joints so that posing never opens gaps.  All profile tables live in SHAPES so that chr_accessories can
fit hair / hats / vests to exactly the same surfaces.
"""
import bpy
import math
from mathutils import Vector
import gta_kit as K
import chr_rig as R
from chr_rig import J, sring, oring, limb, shell

# character colour regions
SKIN, TORSO, UARM, LARM, HAND, PELVIS, ULEG, LLEG, FOOT = ("@C0", "@C1", "@C2", "@C3", "@C4", "@C5", "@C6",
                                                           "@C7", "@C8")
HAIR, EYE, HEADWEAR, EYEWEAR, OVERLAY, DET_A, DET_B = "@C9", "@C10", "@C11", "@C12", "@C13", "@C14", "@C15"

CHARACTERS = ("human_male", "human_female")


# --------------------------------------------------------------------------- profiles
def rrect(row, grow=0.0, z=None):
    """12-point rounded rectangle ring from a profile row (z, rx, ryf, ryb, cf, cb, cy). CCW from above.
    grow offsets the outline outward (accessory shells)."""
    zz, rx, ryf, ryb, cf, cb, cy = row
    if z is not None:
        zz = z
    rx += grow
    ryf += grow
    ryb += grow
    cf = max(0.004, min(cf + grow * 0.5, rx * 0.9, ryf * 0.9))
    cb = max(0.004, min(cb + grow * 0.5, rx * 0.9, ryb * 0.9))
    k = 0.7071
    pts = [
        (rx, -(ryb - cb)), (rx, ryf - cf),
        (rx - cf + cf * k, ryf - cf + cf * k),
        (rx - cf, ryf), (-(rx - cf), ryf),
        (-(rx - cf + cf * k), ryf - cf + cf * k),
        (-rx, ryf - cf), (-rx, -(ryb - cb)),
        (-(rx - cb + cb * k), -(ryb - cb + cb * k)),
        (-(rx - cb), -ryb), (rx - cb, -ryb),
        (rx - cb + cb * k, -(ryb - cb + cb * k)),
    ]
    return [(x, cy + y, zz) for x, y in pts]


def row_at(rows, z):
    """Linear interpolation of a profile table at height z (clamped)."""
    if z <= rows[0][0]:
        return (z,) + tuple(rows[0][1:])
    if z >= rows[-1][0]:
        return (z,) + tuple(rows[-1][1:])
    for a, b in zip(rows, rows[1:]):
        if a[0] <= z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0]) if b[0] > a[0] else 0.0
            return (z,) + tuple(a[i] + (b[i] - a[i]) * t for i in range(1, 7))
    return (z,) + tuple(rows[-1][1:])


def torso_row(shape, z, keys=("pelvis", "abdomen", "chest")):
    """Outer envelope of pelvis / abdomen / chest at height z -> profile row (for belts, vests, skirts)."""
    best = None
    for key in keys:
        rows = shape[key][1:-1]           # visible rows (first / last are the hidden end caps)
        if rows[0][0] - 1e-6 <= z <= rows[-1][0] + 1e-6:
            r = row_at(rows, z)
            if best is None:
                best = list(r)
            else:
                for i in (1, 2, 3):
                    best[i] = max(best[i], r[i])
    if best is None:
        allrows = []
        for key in keys:
            allrows += shape[key][1:-1]
        allrows = sorted(allrows, key=lambda r: r[0])
        best = list(row_at(allrows, z))
    return tuple(best)


def head_row(shape, z):
    return row_at(shape["head"], z)


# rows: (z, rx, ryf, ryb, corner_front, corner_back, centre_y)
HEAD_TOP = [
    (1.685, 0.094, 0.108, 0.108, 0.034, 0.060, 0.003),
    (1.748, 0.094, 0.106, 0.110, 0.038, 0.060, 0.001),
    (1.786, 0.078, 0.086, 0.092, 0.048, 0.054, -0.002),
    (1.800, 0.044, 0.048, 0.054, 0.030, 0.032, -0.002),
]

MALE = dict(
    pelvis=[
        (0.832, 0.070, 0.056, 0.074, 0.036, 0.045, 0.0),
        (0.872, 0.140, 0.080, 0.116, 0.050, 0.072, 0.0),
        (0.950, 0.180, 0.112, 0.126, 0.062, 0.080, 0.0),
        (1.040, 0.166, 0.110, 0.110, 0.062, 0.072, 0.0),
        (1.090, 0.158, 0.106, 0.101, 0.060, 0.066, 0.0),
        (1.104, 0.110, 0.074, 0.070, 0.045, 0.045, 0.0),
    ],
    abdomen=[
        (1.030, 0.105, 0.070, 0.066, 0.045, 0.045, 0.002),
        (1.064, 0.153, 0.104, 0.098, 0.060, 0.064, 0.002),
        (1.150, 0.154, 0.106, 0.098, 0.060, 0.064, 0.003),
        (1.262, 0.166, 0.112, 0.103, 0.060, 0.066, 0.005),
        (1.300, 0.122, 0.078, 0.074, 0.045, 0.045, 0.005),
    ],
    chest=[
        (1.200, 0.124, 0.082, 0.078, 0.050, 0.050, 0.004),
        (1.236, 0.168, 0.118, 0.106, 0.062, 0.068, 0.005),
        (1.312, 0.176, 0.130, 0.112, 0.064, 0.070, 0.006),
        (1.392, 0.190, 0.134, 0.116, 0.066, 0.072, 0.006),
        (1.464, 0.186, 0.112, 0.110, 0.060, 0.068, 0.004),
        (1.494, 0.112, 0.080, 0.086, 0.050, 0.054, 0.0),
        (1.508, 0.064, 0.058, 0.062, 0.035, 0.035, 0.0),
    ],
    head=[
        (1.543, 0.032, 0.038, 0.038, 0.020, 0.020, 0.050),
        (1.568, 0.060, 0.070, 0.060, 0.036, 0.042, 0.034),
        (1.618, 0.084, 0.100, 0.094, 0.038, 0.054, 0.010),
    ] + HEAD_TOP,
    neck=dict(p0=(0.0, -0.004, 1.455), p1=(0.0, 0.004, 1.60),
              st=[(0.0, 0.058, 0.060, 0.060), (1.0, 0.056, 0.058, 0.060)]),
    collar=dict(z0=1.474, z1=1.515, r0=(0.090, 0.084), r1=(0.071, 0.069)),
    belt=dict(z0=1.046, z1=1.090, grow=0.008, buckle=(0.040, 0.012, 0.034)),
    # limb stations (t, side radius, front radius, back radius[, side offset, front offset])
    upper_arm=[(0.0, 0.054, 0.058, 0.056), (0.38, 0.051, 0.059, 0.057, 0.004, 0.0), (1.0, 0.045, 0.048, 0.048)],
    lower_arm=[(0.0, 0.045, 0.048, 0.048), (0.28, 0.047, 0.051, 0.049), (1.0, 0.033, 0.037, 0.035)],
    hand=dict(tip=(0.283, 0.014, 0.700),
              st=[(0.0, 0.028, 0.034, 0.032), (0.30, 0.023, 0.048, 0.042), (0.66, 0.022, 0.050, 0.044, -0.004, 0.0),
                  (1.0, 0.014, 0.034, 0.032, -0.016, 0.0)],
              thumb=((0.262, 0.040, 0.850), (0.254, 0.076, 0.782), 0.016, 0.012)),
    thigh=[(0.0, 0.092, 0.102, 0.102), (0.45, 0.083, 0.090, 0.088), (1.0, 0.065, 0.069, 0.067)],
    shin=[(0.0, 0.065, 0.069, 0.067), (0.26, 0.064, 0.064, 0.077), (0.72, 0.051, 0.054, 0.058),
          (1.0, 0.047, 0.051, 0.051)],
    # shoe: rings along Y (y, z0, z1, half width, top chamfer), sole outline (x rel. to the leg axis, y)
    shoe=dict(rings=[(-0.088, 0.032, 0.090, 0.030, 0.012), (-0.066, 0.022, 0.126, 0.047, 0.016),
                     (-0.004, 0.022, 0.132, 0.053, 0.018), (0.070, 0.022, 0.098, 0.056, 0.020),
                     (0.150, 0.022, 0.070, 0.057, 0.020), (0.205, 0.024, 0.052, 0.040, 0.012)],
              sole=[(-0.034, -0.096), (0.034, -0.096), (0.054, -0.068), (0.061, 0.110), (0.055, 0.190),
                    (0.034, 0.216), (-0.034, 0.216), (-0.055, 0.190), (-0.061, 0.110), (-0.054, -0.068)],
              sole_h=0.030),
    face=dict(eye=((0.040, 0.1105, 1.688), (0.028, 0.012, 0.018)),
              brow=((0.041, 0.1120, 1.7110), (0.040, 0.016, 0.010), -8.0),
              nose=[(0.108, 1.702), (0.108, 1.640), (0.130, 1.640), (0.141, 1.654)], nose_w=0.028,
              mouth=((0.0, 0.1085, 1.602), (0.044, 0.008, 0.008)),
              ear=((0.0975, -0.006, 1.667), (0.014, 0.030, 0.046))),
)

FEMALE = dict(
    pelvis=[
        (0.832, 0.068, 0.054, 0.072, 0.036, 0.045, 0.0),
        (0.872, 0.142, 0.078, 0.116, 0.050, 0.074, 0.0),
        (0.950, 0.184, 0.110, 0.128, 0.060, 0.082, 0.0),
        (1.040, 0.160, 0.100, 0.108, 0.058, 0.070, 0.0),
        (1.090, 0.138, 0.092, 0.092, 0.054, 0.060, 0.0),
        (1.104, 0.098, 0.064, 0.062, 0.040, 0.040, 0.0),
    ],
    abdomen=[
        (1.030, 0.094, 0.062, 0.058, 0.040, 0.040, 0.0),
        (1.064, 0.132, 0.090, 0.086, 0.052, 0.056, 0.0),
        (1.150, 0.126, 0.090, 0.082, 0.052, 0.054, 0.0),
        (1.262, 0.144, 0.100, 0.090, 0.054, 0.058, 0.0),
        (1.300, 0.108, 0.070, 0.066, 0.040, 0.040, 0.0),
    ],
    chest=[
        (1.200, 0.110, 0.074, 0.070, 0.045, 0.045, 0.0),
        (1.236, 0.148, 0.104, 0.092, 0.054, 0.060, 0.0),
        (1.300, 0.154, 0.130, 0.098, 0.060, 0.062, 0.0),
        (1.372, 0.162, 0.136, 0.102, 0.066, 0.064, 0.0),
        (1.458, 0.166, 0.100, 0.098, 0.056, 0.060, 0.0),
        (1.492, 0.098, 0.070, 0.076, 0.045, 0.048, 0.0),
        (1.508, 0.054, 0.050, 0.052, 0.030, 0.030, 0.0),
    ],
    head=[
        (1.543, 0.028, 0.034, 0.036, 0.018, 0.018, 0.050),
        (1.568, 0.054, 0.068, 0.058, 0.036, 0.040, 0.034),
        (1.618, 0.080, 0.099, 0.093, 0.042, 0.054, 0.010),
    ] + HEAD_TOP,
    neck=dict(p0=(0.0, -0.004, 1.455), p1=(0.0, 0.004, 1.60),
              st=[(0.0, 0.048, 0.050, 0.050), (1.0, 0.046, 0.048, 0.050)]),
    collar=dict(z0=1.474, z1=1.512, r0=(0.078, 0.073), r1=(0.060, 0.059)),
    belt=dict(z0=1.050, z1=1.090, grow=0.007, buckle=(0.032, 0.011, 0.030)),
    upper_arm=[(0.0, 0.053, 0.055, 0.053, -0.004, 0.0), (0.38, 0.044, 0.049, 0.048), (1.0, 0.038, 0.040, 0.040)],
    lower_arm=[(0.0, 0.038, 0.040, 0.040), (0.28, 0.039, 0.042, 0.041), (1.0, 0.027, 0.030, 0.029)],
    hand=dict(tip=(0.281, 0.012, 0.715),
              st=[(0.0, 0.024, 0.029, 0.027), (0.30, 0.019, 0.041, 0.036), (0.66, 0.018, 0.043, 0.038, -0.004, 0.0),
                  (1.0, 0.012, 0.029, 0.027, -0.014, 0.0)],
              thumb=((0.262, 0.034, 0.854), (0.255, 0.064, 0.794), 0.013, 0.010)),
    thigh=[(0.0, 0.092, 0.099, 0.103), (0.45, 0.077, 0.083, 0.081), (1.0, 0.057, 0.061, 0.059)],
    shin=[(0.0, 0.057, 0.061, 0.059), (0.26, 0.055, 0.056, 0.067), (0.72, 0.043, 0.045, 0.049),
          (1.0, 0.040, 0.043, 0.043)],
    shoe=dict(rings=[(-0.078, 0.032, 0.086, 0.027, 0.011), (-0.058, 0.022, 0.116, 0.041, 0.014),
                     (-0.004, 0.022, 0.122, 0.046, 0.016), (0.062, 0.022, 0.090, 0.049, 0.018),
                     (0.132, 0.022, 0.064, 0.050, 0.018), (0.180, 0.024, 0.048, 0.035, 0.011)],
              sole=[(-0.030, -0.085), (0.030, -0.085), (0.047, -0.060), (0.053, 0.096), (0.048, 0.166),
                    (0.030, 0.190), (-0.030, 0.190), (-0.048, 0.166), (-0.053, 0.096), (-0.047, -0.060)],
              sole_h=0.028),
    face=dict(eye=((0.040, 0.1105, 1.688), (0.029, 0.012, 0.020)),
              brow=((0.041, 0.1110, 1.7125), (0.038, 0.014, 0.007), -6.0),
              nose=[(0.108, 1.698), (0.108, 1.642), (0.125, 1.642), (0.134, 1.654)], nose_w=0.022,
              mouth=((0.0, 0.1080, 1.603), (0.036, 0.008, 0.010)),
              ear=((0.0965, -0.006, 1.667), (0.013, 0.028, 0.042))),
)

SHAPES = {"human_male": MALE, "human_female": FEMALE}


# --------------------------------------------------------------------------- pieces
def xz_ring(cx, y, z0, z1, w, ct, cb=0.008):
    """8-point chamfered rectangle in the XZ plane (shoe cross-section)."""
    ct = min(ct, w * 0.8, (z1 - z0) * 0.45)
    cb = min(cb, w * 0.8, (z1 - z0) * 0.45)
    return [(cx - w + cb, y, z0), (cx + w - cb, y, z0), (cx + w, y, z0 + cb), (cx + w, y, z1 - ct),
            (cx + w - ct, y, z1), (cx - w + ct, y, z1), (cx - w, y, z1 - ct), (cx - w, y, z0 + cb)]


def scalp_pred(c):
    """Head-shell faces that are the scalp cap (region 9). c = face centre."""
    return (c.z > 1.748) or (c.z > 1.685 and c.y < 0.03) or (c.z > 1.618 and c.y < -0.05)


def build_right_side(mb, sh):
    """Everything on the character's right (+X); mirrored afterwards."""
    S, E, W = J("UpperArm_R"), J("LowerArm_R"), J("Hand_R")
    H, Kn, A = J("UpperLeg_R"), J("LowerLeg_R"), J("Foot_R")

    mb.bone("UpperArm_R")
    limb(mb, S, E, sh["upper_arm"], UARM, n=8, ball0=2, ball1=1)
    mb.bone("LowerArm_R")
    limb(mb, E, W, sh["lower_arm"], LARM, n=8, ball0=1, ball1=1)
    mb.bone("Hand_R")
    hd = sh["hand"]
    limb(mb, W, hd["tip"], hd["st"], HAND, n=8, p=3.0, ball0=1, ball1=1)
    t0, t1, r0, r1 = hd["thumb"]
    limb(mb, t0, t1, [(0.0, r0, r0, r0), (1.0, r1, r1, r1)], HAND, n=6, ball0=0, ball1=1)

    mb.bone("UpperLeg_R")
    limb(mb, H, Kn, sh["thigh"], ULEG, n=8, ball0=1, ball1=1)
    mb.bone("LowerLeg_R")
    limb(mb, Kn, A, sh["shin"], LLEG, n=8, ball0=2, ball1=1)

    mb.bone("Foot_R")
    so = sh["shoe"]
    rings = [xz_ring(A.x, y, z0, z1, w, ct) for (y, z0, z1, w, ct) in so["rings"]]
    mb.loft(rings, FOOT, closed=True, cap_start=True, cap_end=True)
    mb.prism([(A.x + x, y) for x, y in so["sole"]], so["sole_h"], DET_B, plane="XY", center=False,
             caps=(True, False))

    mb.bone("Head")
    f = sh["face"]
    (ex, ey, ez), es = f["eye"]
    mb.box(es, (ex, ey, ez), EYE)
    (bx, by, bz), bs, brot = f["brow"]
    mb.box(bs, (bx, by, bz), HAIR, rot=(0.0, brot, 0.0))
    (rx, ry, rz), rs = f["ear"]
    mb.box(rs, (rx, ry, rz), SKIN, rot=(0.0, 0.0, -14.0), taper=(1.0, 0.8))


def build_centre(mb, sh):
    mb.bone("Hips")
    pv = sh["pelvis"]
    b = sh["belt"]
    g = b["grow"]
    vis = pv[1:-1]
    rings = [rrect(r) for r in pv[:3]]
    rings.append(rrect(row_at(vis, b["z0"] - 0.004)))
    rings.append(rrect(row_at(vis, b["z0"]), grow=g))
    rings.append(rrect(row_at(vis, b["z1"]), grow=g))
    rings.append(rrect(pv[-1]))
    shell(mb, rings, PELVIS, ring_colors=[PELVIS, PELVIS, PELVIS, DET_A, DET_A, DET_A])
    row = row_at(vis, (b["z0"] + b["z1"]) * 0.5)
    bw, bd, bh = b["buckle"]
    mb.box((bw, bd, bh), (0.0, row[6] + row[2] + g + bd * 0.5 - 0.005, (b["z0"] + b["z1"]) * 0.5), DET_B)

    mb.bone("Spine")
    shell(mb, [rrect(r) for r in sh["abdomen"]], TORSO)

    mb.bone("Chest")
    shell(mb, [rrect(r) for r in sh["chest"]], TORSO)
    c = sh["collar"]
    rings = [sring(0.0, 0.0, c["z0"], c["r0"][0], c["r0"][1], n=8),
             sring(0.0, 0.0, c["z1"], c["r1"][0], c["r1"][1], n=8),
             sring(0.0, 0.0, c["z1"] - 0.006, c["r1"][0] - 0.022, c["r1"][1] - 0.022, n=8)]
    mb.loft(rings, DET_A, closed=True, cap_start=False, cap_end=True)

    mb.bone("Neck")
    nk = sh["neck"]
    limb(mb, nk["p0"], nk["p1"], nk["st"], SKIN, n=8, ball0=0, ball1=1)

    mb.bone("Head")
    faces = shell(mb, [rrect(r) for r in sh["head"]], SKIN)
    mb.repaint(faces, HAIR, scalp_pred)
    f = sh["face"]
    mb.prism(f["nose"], f["nose_w"], SKIN, plane="YZ")
    mp, ms = f["mouth"]
    mb.box(ms, mp, SKIN, taper=(0.8, 1.0))


def tune_preview():
    """Blender-preview only: the kit's 16x1 `GTA_CharRegions` strip shows region 10 (eyes) off-white, while the
    spec defines eyes as DARK insets.  Darken that single cell so QA renders match the game look.
    (Godot assigns the real region colours per character.)"""
    K.get_material("Character")
    img = bpy.data.images.get("GTA_CharRegions")
    if img is None:
        return False
    px = list(img.pixels)
    i = 10 * 4
    want = (0.030, 0.022, 0.018, 1.0)
    if all(abs(px[i + k] - want[k]) < 1e-4 for k in range(4)):
        return True
    px[i:i + 4] = want
    img.pixels = px
    img.update()
    try:
        img.pack()
    except Exception:
        pass
    return True


def build_body(asset_id):
    """(Re)build `<asset_id>__body` on the existing rig."""
    sh = SHAPES[asset_id]
    root, rig = R.ensure_character(asset_id)
    R.remove_part(asset_id, "body")
    mb = R.SkinMB()
    build_right_side(mb, sh)
    mb.mirror_skin()
    build_centre(mb, sh)
    tris = mb.tri_count()
    obj = mb.to_skinned(root, rig, "body", sharp_angle=50.0)
    obj["gta_tris"] = tris
    tune_preview()
    return obj


def build(asset_id, rebuild=False):
    root, rig = R.ensure_character(asset_id, rebuild=rebuild)
    body = build_body(asset_id)
    st = K.asset_stats(root)
    return {"id": asset_id, "body_tris": body["gta_tris"], "stats": st}


def build_all(rebuild=False):
    return [build(a, rebuild=rebuild) for a in CHARACTERS]
