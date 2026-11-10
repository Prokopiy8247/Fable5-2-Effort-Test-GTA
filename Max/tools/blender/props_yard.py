"""props_yard - P2 yard / industrial props for NEON TIDE (SPEC_PROPS_NATURE.md).

    import props_common as P, props_shapes as S, props_yard as M
    print(S.run(M.IDS)); M.do_layout()

Front = +Y.  Container: long axis along Y (2.44 x 6.06 x 2.59), doors on the +Y end.
Ramps and stairs rise toward +Y, origin at the centre of the footprint.
"""
import math
import random

import bmesh
from mathutils import Vector

import gta_kit as K
import props_common as P
import props_shapes as S
from props_common import asset, cyl_col, box_col

V = Vector
POLE = "steel_dark"


# =========================================================================== pallets, crates
@asset("prop_pallet", dynamic=True, mass=15)
def prop_pallet(root):
    mb = K.MB()
    top = ["wood_light", "wood_light", "plank_gray", "wood_light", "wood_mid"]
    for i in range(5):
        P.xbox(mb, (1.2, 0.14, 0.022), (0, -0.43 + 0.215 * i, 0.128), top[i], base=True)
    for sx in (-0.55, 0.0, 0.55):
        P.xbox(mb, (0.1, 1.0, 0.106), (sx, 0, 0.022), "wood_mid", skip=("-z", "+z"), base=True)
    for sy in (-0.45, 0.0, 0.45):
        P.xbox(mb, (1.2, 0.1, 0.022), (0, sy, 0.0), "plank_gray", base=True)
    mb.to_object(root, "mesh")


def _crate(mb, s, f, brace=True, lines=2, plank="wood_light", fr="wood_mid", groove="wood_dark"):
    h = s * 0.5
    rec = 0.012
    mb.box((s - 2 * rec, s - 2 * rec, s - 2 * rec), (0, 0, h), plank)
    e = h - f * 0.5
    for sy in (-e, e):                                   # 12 edge battens
        for z in (f * 0.5, s - f * 0.5):
            mb.box((s, f, f), (0, sy, z), fr)
    for sx in (-e, e):
        for z in (f * 0.5, s - f * 0.5):
            P.xbox(mb, (f, s - 2 * f, f), (sx, 0, z), fr, skip=("+y", "-y"))
        for sy in (-e, e):
            P.xbox(mb, (f, f, s - 2 * f), (sx, sy, h), fr, skip=("+z", "-z"))
    a, b = -h + f, h - f
    face = h - rec
    if brace:
        yb = h - rec * 0.5
        P.beam(mb, (a, yb, f), (b, yb, s - f), (0.085, rec), fr, up=(0, 1, 0))
        P.beam(mb, (b, -yb, f), (a, -yb, s - f), (0.085, rec), fr, up=(0, 1, 0))
        P.beam(mb, (yb, b, f), (yb, a, s - f), (0.085, rec), fr, up=(1, 0, 0))
        P.beam(mb, (-yb, a, f), (-yb, b, s - f), (0.085, rec), fr, up=(1, 0, 0))
    for k in range(lines):                               # plank joints
        z = f + (s - 2 * f) * (k + 1) / (lines + 1)
        for sgn in (1, -1):
            P.qy(mb, a, b, z - 0.006, z + 0.006, sgn * (face + 0.004), groove, facing=sgn)
            P.qx(mb, a, b, z - 0.006, z + 0.006, sgn * (face + 0.004), groove, facing=sgn)
        y = a + (b - a) * (k + 1) / (lines + 1)
        P.qz(mb, a, b, y - 0.006, y + 0.006, s - rec + 0.004, groove)


@asset("prop_crate", dynamic=True, mass=30, notes="1.0 m framed plank crate")
def prop_crate(root):
    mb = K.MB()
    _crate(mb, 1.0, 0.075)
    for sx in (-0.2, 0.0):                               # "this side up" arrows on the +Y face
        zb = 0.72
        P.fpoly(mb, [(sx - 0.05, 0.4935, zb), (sx + 0.05, 0.4935, zb), (sx, 0.4935, zb + 0.09)], "black", (0, 1, 0))
        P.qy(mb, sx - 0.018, sx + 0.018, zb - 0.07, zb, 0.4935, "black")
    mb.to_object(root, "mesh")


@asset("prop_crate_small", dynamic=True, mass=12, notes="0.6 m crate")
def prop_crate_small(root):
    mb = K.MB()
    _crate(mb, 0.6, 0.05, brace=False, lines=1, plank="wood_mid", fr="wood_dark", groove="wood_dark")
    mb.to_object(root, "mesh")


# =========================================================================== drums and gas
DRUM = [(0.3, 0.0), (0.29, 0.045), (0.29, 0.285), (0.303, 0.31), (0.29, 0.335), (0.29, 0.565), (0.303, 0.59),
        (0.29, 0.615), (0.29, 0.855), (0.3, 0.88), (0.29, 0.9), (0.268, 0.9), (0.268, 0.878), (0.0, 0.878)]


def _drum(mb, body, rib, mid, lid, bung="steel"):
    cols = [rib, body, rib, rib, mid, rib, rib, body, rib, rib, lid, lid, lid]
    P.lathe(mb, DRUM, body, segs=10, colors=cols, cap0=True, cap_colors=(body, lid))
    mb.cyl(0.03, 0.02, (0.16, 0.0, 0.878), bung, segs=6, base=True)
    mb.cyl(0.018, 0.015, (-0.17, 0.06, 0.878), bung, segs=5, base=True)


FLAME = [(0.0, -0.07), (0.035, -0.045), (0.04, -0.005), (0.02, 0.035), (0.016, 0.0), (0.0, 0.078), (-0.014, 0.02),
         (-0.03, 0.04), (-0.04, -0.01), (-0.03, -0.05)]


def facet(r, segs):
    """Distance from the axis to the flat facet a lathe of `segs` (phase 0) shows toward +-Y (segs = 10)."""
    return r * math.cos(math.pi / segs)


def _flame_diamond(mb, y_face, zc, half=0.085, facing=1, plate="white", flame="red", x=0.0):
    """Flat hazard diamond + flame pictogram lying on a flat facet at |y| = y_face (facing +Y or -Y)."""
    s = facing
    y1, y2 = s * (y_face + 0.004), s * (y_face + 0.009)
    P.fpoly(mb, [(x, y1, zc - half), (x + half, y1, zc), (x, y1, zc + half), (x - half, y1, zc)], plate, (0, s, 0))
    k = half / 0.13
    P.fpoly(mb, [(x + px * k, y2, zc + pz * k) for px, pz in FLAME], flame, (0, s, 0))


@asset("prop_barrel", dynamic=True, mass=20, col=cyl_col(0.3, 0.9), notes="200 l drum, whole body = tint_a_metal")
def prop_barrel(root):
    mb = K.MB()
    t = "tint_a_metal"
    _drum(mb, t, t, t, t)
    mb.to_object(root, "mesh")


@asset("prop_barrel_explosive", dynamic=True, mass=25, col=cyl_col(0.3, 0.9),
       notes="red drum, yellow hazard band, flame diamonds on +Y and -Y")
def prop_barrel_explosive(root):
    mb = K.MB()
    _drum(mb, "red", "black", "hazard_yellow", "red_dark", bung="black")
    for s in (1, -1):
        _flame_diamond(mb, facet(0.29, 10), 0.45, half=0.085, facing=s, plate="white", flame="red")
    mb.to_object(root, "mesh")


@asset("prop_gas_tank", dynamic=True, mass=18, col=cyl_col(0.2, 1.2), notes="propane bottle 0.4 x 1.2")
def prop_gas_tank(root):
    mb = K.MB()
    w, r = "offwhite", "red"
    prof = [(0.16, 0.0), (0.172, 0.012), (0.172, 0.065), (0.2, 0.09), (0.2, 0.52), (0.2, 0.66), (0.2, 0.8),
            (0.172, 0.93), (0.1, 1.0), (0.05, 1.02)]
    P.lathe(mb, prof, w, segs=10, colors=["gray_dark", "gray_dark", w, w, r, w, w, w, w], cap0=True, cap1=True,
            cap_colors=("gray_dark", w))
    P.lathe(mb, [(0.128, 0.985), (0.128, 1.2), (0.112, 1.2), (0.112, 0.985)], "gray_light", segs=8, cap0=False,
            cap1=False, smooth=True)                                                       # guard collar
    mb.cyl(0.03, 0.09, (0, 0, 1.02), "brass", segs=6, base=True)                             # valve
    mb.cyl(0.05, 0.022, (0, 0, 1.11), "red", segs=6, base=True)                              # hand wheel
    mb.cyl(0.018, 0.07, (0.045, 0, 1.065), "brass", axis="X", segs=5)
    _flame_diamond(mb, facet(0.2, 10), 0.33, half=0.058, facing=1, plate="red", flame="white")
    mb.to_object(root, "mesh")


@asset("prop_gas_tank_large", notes="horizontal LPG tank 3.5 m along X on two saddles")
def prop_gas_tank_large(root):
    mb = K.MB()
    w = "offwhite"
    zc, r = 0.9, 0.6
    prof = [(0.0, -1.75), (0.36, -1.69), (0.55, -1.53), (0.6, -1.33), (0.6, -0.2), (0.6, 0.2), (0.6, 1.33),
            (0.55, 1.53), (0.36, 1.69), (0.0, 1.75)]
    with mb.at((0, 0, zc), rot=(0, 90, 0)):          # phase 15 deg -> a flat 30 deg facet faces +Y (|z| < 0.155)
        P.lathe(mb, prof, w, segs=12, colors=[w, w, w, w, "red", w, w, w, w], phase=math.radians(15))
    yf = r * math.cos(math.radians(15))
    for sx in (-1.0, 1.0):                                                                 # concrete cradles
        cradle = [(-0.52, 0.0), (0.52, 0.0), (0.52, 0.56)]
        for a in (-40, -20, 0, 20, 40):
            t = math.radians(a)
            cradle.append((-math.sin(t) * 0.585, zc - math.cos(t) * 0.585))
        cradle.append((-0.52, 0.56))
        cradle = [cradle[0], cradle[1], cradle[2]] + sorted(cradle[3:-1], key=lambda p: -p[0]) + [cradle[-1]]
        mb.prism(cradle, 0.3, "concrete", plane="YZ", pos=(sx, 0, 0))
        mb.box((0.36, 1.12, 0.06), (sx, 0, 0.0), "concrete_dark", base=True)
    mb.cyl(0.19, 0.1, (0.0, 0, zc + r - 0.03), "gray_light", segs=10, base=True)             # manway
    mb.cyl(0.215, 0.03, (0.0, 0, zc + r + 0.07), "gray_dark", segs=10, base=True)
    mb.cyl(0.035, 0.16, (-0.9, 0, zc + r - 0.03), "brass", segs=6, base=True)                # relief valve
    mb.cyl(0.05, 0.03, (-0.9, 0, zc + r + 0.13), "red", segs=6, base=True)
    mb.tube([(0.9, 0, zc + r - 0.04), (0.9, 0, zc + r + 0.12), (0.9, 0.55, zc + r + 0.12), (0.9, 0.7, zc + r - 0.02),
             (0.9, 0.7, 0.05)], 0.03, "steel", segs=5)                                       # fill line
    mb.cyl(0.05, 0.05, (0.9, 0.7, 0.42), "red", axis="Y", segs=6)
    _flame_diamond(mb, yf, zc, half=0.14, plate="red", flame="white", x=-0.55)
    mb.box((0.5, 0.012, 0.12), (0.4, yf + 0.007, zc), "white")                               # name plate
    mb.box((0.4, 0.012, 0.03), (0.4, yf + 0.012, zc + 0.025), "black")
    mb.box((0.28, 0.012, 0.022), (0.34, yf + 0.012, zc - 0.025), "gray_dark")
    mb.to_object(root, "mesh")


# =========================================================================== shipping containers
def _corrugated(mb, y0, y1, z0, z1, periods, depth, color):
    """Trapezoid-corrugated wall in the local YZ plane (ridges at x = 0, valleys at x = -depth), facing +X."""
    p = (y1 - y0) / periods
    pts = []
    for i in range(periods):
        ya = y0 + p * i
        pts += [(ya, 0.0), (ya + p * 0.36, 0.0), (ya + p * 0.5, depth), (ya + p * 0.86, depth)]
    pts.append((y1, 0.0))
    for a, b in zip(pts[:-1], pts[1:]):
        P.fpoly(mb, [(-a[1], a[0], z0), (-b[1], b[0], z0), (-b[1], b[0], z1), (-a[1], a[0], z1)], color, (1, 0, 0))


def _container(root, open_end):
    mb = K.MB()
    t, dk = "tint_a_metal", "gunmetal"
    hx, hy, H = 1.22, 3.03, 2.59
    c = 0.125                                            # casting / rail height
    px, py = hx - 0.066, hy - 0.066                      # frame centre lines (6 mm inside the casting envelope)
    for sx in (-1, 1):
        for sy in (-1, 1):
            inner = ("-x" if sx > 0 else "+x", "-y" if sy > 0 else "+y")       # hidden by rails / walls
            P.xbox(mb, (0.12, 0.12, H - 2 * c), (sx * px, sy * py, c), t, skip=("-z", "+z"), base=True)
            P.xbox(mb, (0.132, 0.132, c), (sx * (hx - 0.066), sy * (hy - 0.066), 0.0), dk, skip=("+z",) + inner,
                   base=True)
            P.xbox(mb, (0.132, 0.132, c), (sx * (hx - 0.066), sy * (hy - 0.066), H - c), dk, skip=("-z",) + inner,
                   base=True)
        for z in (0.0, H - c):                           # side rails
            P.xbox(mb, (0.1, 2 * py - 0.12, c), (sx * (hx - 0.056), 0, z), t, skip=("+y", "-y"), base=True)
    for sy in (-1, 1):                                   # end sills / headers
        for z in (0.0, H - c):
            P.xbox(mb, (2 * px - 0.12, 0.1, c), (0, sy * (hy - 0.056), z), t, skip=("+x", "-x"), base=True)
    P.qz(mb, -px, px, -py, py, H - 0.045, t)                                              # roof (recessed)
    P.qz(mb, -px, px, -py, py, 0.03, dk, facing=-1)                                       # underside
    for sx, rz in ((1, 0), (-1, 180)):                   # corrugated side walls
        with mb.at((sx * (hx - 0.008), 0, 0), rot=(0, 0, rz)):
            _corrugated(mb, -(py - 0.06), py - 0.06, c, H - c, 12, 0.036, t)
    with mb.at((0, -(hy - 0.008), 0), rot=(0, 0, -90)):  # corrugated back wall (-Y)
        _corrugated(mb, -(px - 0.06), px - 0.06, c, H - c, 5, 0.036, t)
    yf = hy - 0.05                                       # plane of the door faces
    if not open_end:
        P.qy(mb, -px, px, c, H - c, yf - 0.03, dk)                                        # backing behind the seam
        for sx in (-1, 1):
            P.xbox(mb, (1.08, 0.03, H - 2 * c - 0.02), (sx * 0.548, yf - 0.015, c + 0.01), t, skip=("-y",), base=True)
            for rx in (0.18, 0.86):                      # lock rods
                P.xbox(mb, (0.034, 0.034, H - 2 * c + 0.1), (sx * rx, yf + 0.017, c - 0.05), "steel",
                       skip=("-y", "-z", "+z"), base=True)
            P.xbox(mb, (0.26, 0.022, 0.05), (sx * 0.31, yf + 0.011, 1.12), dk, skip=("-y",))   # handles
            P.xbox(mb, (0.26, 0.022, 0.05), (sx * 0.73, yf + 0.011, 1.3), dk, skip=("-y",))
        P.qy(mb, 0.36, 0.76, 1.9, 2.1, yf + 0.004, "white")                               # ID plate
        P.qy(mb, 0.39, 0.73, 2.02, 2.07, yf + 0.008, "black")
        P.qy(mb, 0.39, 0.62, 1.93, 1.97, yf + 0.008, "gray_dark")
    else:
        wi = "@D:tint_a_metal"
        xi, yi, z0, z1 = px - 0.07, py - 0.07, c + 0.03, H - c - 0.02
        P.qz(mb, -xi, xi, -yi, hy - 0.1, z0, "@D:wood_mid")                              # plywood floor
        P.qy(mb, -xi, xi, c, z0, hy - 0.1, "@D:wood_dark")                               # floor edge at the sill
        P.qz(mb, -xi, xi, -yi, hy - 0.1, z1, wi, facing=-1)                              # ceiling
        P.qy(mb, -xi, xi, z0, z1, -yi, wi)                                                # back wall
        for sx in (-1, 1):
            P.qx(mb, -yi, hy - 0.1, z0, z1, sx * xi, wi, facing=-sx)                     # side walls
            # door leaf folded back 270 degrees against the side wall
            P.xbox(mb, (0.04, 1.1, H - 2 * c - 0.02), (sx * (hx + 0.032), hy - 0.62, c + 0.01), t, base=True)
            for ry in (0.2, 0.86):
                P.xbox(mb, (0.03, 0.034, H - 2 * c + 0.06), (sx * (hx + 0.064), hy - 0.07 - ry, c - 0.03), "steel",
                       skip=("-x" if sx > 0 else "+x", "-z", "+z"), base=True)
            P.xbox(mb, (0.05, 0.07, 0.16), (sx * (hx + 0.012), hy - 0.045, 0.6), dk)       # hinge blocks
            P.xbox(mb, (0.05, 0.07, 0.16), (sx * (hx + 0.012), hy - 0.045, 2.0), dk)
    mb.to_object(root, "mesh")

    lod = K.MB()
    lod.box((2 * hx, 2 * hy, H), (0, 0, 0), t, base=True)
    lod_tris = lod.tri_count()
    lod.to_object(root, "lod1")

    if open_end:
        def col(cm):
            cm.box((2 * hx, 2 * hy, c + 0.03), (0, 0, 0), "gray_mid", base=True)
            cm.box((2 * hx, 2 * hy, 0.1), (0, 0, H - 0.1), "gray_mid", base=True)
            cm.box((2 * hx, 0.1, H), (0, -(hy - 0.05), 0), "gray_mid", base=True)
            for sx in (-1, 1):
                cm.box((0.1, 2 * hy, H), (sx * (hx - 0.05), 0, 0), "gray_mid", base=True)
        P.col_part(root, col)
    return {"lod1_tris": lod_tris}


@asset("prop_container", notes="20 ft container 2.44 (X) x 6.06 (Y) x 2.59, doors on the +Y end, stackable at "
       "+2.59; tint_a_metal body; `lod1` = 12-tri box")
def prop_container(root):
    return _container(root, False)


@asset("prop_container_open", col="mesh", notes="as prop_container but the +Y end is open (doors folded back along "
       "the sides, width 2.57), hollow interior on PaletteDry; `col` = floor / walls / roof boxes; `lod1` box")
def prop_container_open(root):
    return _container(root, True)


# =========================================================================== spool, tyres, pipes
@asset("prop_cable_spool", notes="1.6 m cable drum standing on its flanges, axis along X, wedged by two chocks")
def prop_cable_spool(root):
    mb = K.MB()
    wl, wm = "wood_light", "wood_mid"
    prof = [(0.13, -0.5), (0.8, -0.5), (0.8, -0.44), (0.5, -0.44), (0.5, 0.44), (0.8, 0.44), (0.8, 0.5), (0.13, 0.5)]
    with mb.at((0, 0, 0.8), rot=(0, 90, 0)):
        P.lathe(mb, prof, wl, segs=12, colors=[wl, wm, wm, "charcoal", wm, wm, wl], cap0=True, cap1=True,
                cap_colors=(POLE, POLE))
        for z, s in ((-0.5, -1), (0.5, 1)):
            for k in range(4):
                a = math.radians(45 + 90 * k)
                mb.cyl(0.03, 0.02, (math.cos(a) * 0.3, math.sin(a) * 0.3, z + s * 0.008), POLE, segs=5)
    for sy in (-1, 1):                                   # wedges touching the flange rims
        for sx in (-0.47, 0.47):
            mb.prism([(sy * 0.22, 0.0), (sy * 0.64, 0.0), (sy * 0.64, 0.12), (sy * 0.56, 0.2)], 0.14, "wood_dark",
                     plane="YZ", pos=(sx, 0, 0))
    mb.to_object(root, "mesh")


TYRE = [(0.2, 0.0), (0.3, 0.0), (0.33, 0.04), (0.33, 0.18), (0.3, 0.22), (0.2, 0.22)]
TYRE_COLS = ["rubber", "charcoal", "tire", "charcoal", "rubber", "black"]


@asset("prop_tire", dynamic=True, mass=9, col=cyl_col(0.33, 0.22), notes="single tyre lying flat")
def prop_tire(root):
    mb = K.MB()
    P.lathe(mb, TYRE, "tire", segs=10, colors=TYRE_COLS, closed=True)
    mb.to_object(root, "mesh")


@asset("prop_tire_stack", col=cyl_col(0.35, 0.88), notes="four stacked tyres")
def prop_tire_stack(root):
    mb = K.MB()
    offs = [(0.0, 0.0), (0.025, -0.015), (-0.02, 0.02), (0.015, 0.03)]
    for i, (ox, oy) in enumerate(offs):
        with mb.at((ox, oy, 0.22 * i), rot=(0, 0, 13 * i)):
            if i < 3:
                P.lathe(mb, TYRE[1:], "tire", segs=10, colors=TYRE_COLS[1:5], cap0=False, cap1=False)
            else:
                P.lathe(mb, TYRE[1:] + [(0.2, -0.64)], "tire", segs=10, colors=TYRE_COLS[1:], cap0=False, cap1=False)
    mb.to_object(root, "mesh")


@asset("prop_pipe_stack", col="mesh", notes="pyramid of 6 concrete pipes (0.9 x 2.4) along Y; `col` = 3 stepped boxes")
def prop_pipe_stack(root):
    mb = K.MB()
    ro, ri, ln = 0.45, 0.37, 2.4
    rows = [(0.45, (-0.9, 0.0, 0.9)), (0.45 + 0.7794, (-0.45, 0.45)), (0.45 + 1.5588, (0.0,))]
    rnd = random.Random(5)
    for z, xs in rows:
        for x in xs:
            oy = rnd.uniform(-0.07, 0.07)
            with mb.at((x, -ln * 0.5 + oy, z), rot=(-90, 0, 0)):
                P.lathe(mb, [(ri, 0.0), (ro, 0.0), (ro, ln), (ri, ln)], "concrete", segs=8, closed=True,
                        colors=["concrete_light", "concrete", "concrete_light", "concrete_dark"], smooth=True)
    for sx in (-1, 1):
        for sy in (-0.75, 0.75):
            mb.prism([(sx * 1.27, 0.0), (sx * 1.5, 0.0), (sx * 1.3, 0.17)], 0.3, "wood_mid", plane="XZ",
                     pos=(0, sy, 0))

    def col(c):
        c.box((2.7, ln, 0.9), (0, 0, 0), "gray_mid", base=True)
        c.box((1.8, ln, 0.78), (0, 0, 0.9), "gray_mid", base=True)
        c.box((0.9, ln, 0.78), (0, 0, 1.68), "gray_mid", base=True)
    P.col_part(root, col)
    mb.to_object(root, "mesh")


# =========================================================================== scaffold, ladder, stairs
@asset("prop_scaffold", col="mesh", notes="2.5 x 1.2 x 4.0, walkable plank decks at z 1.98 and 3.93; -X end left "
       "free for a prop_ladder; `col` = two deck slabs + four posts")
def prop_scaffold(root):
    mb = K.MB()
    tube = "steel"
    sx, sy = 1.2, 0.55
    for x in (-sx, sx):
        for y in (-sy, sy):
            mb.cyl(0.027, 4.0, (x, y, 0), tube, segs=5, base=True)
            P.xbox(mb, (0.16, 0.16, 0.012), (x, y, 0.0), POLE, skip=("-z",), base=True)
    for z in (1.92, 3.87):
        for y in (-sy, sy):
            mb.cyl(0.024, 2.4, (0, y, z), tube, axis="X", segs=5, caps=False)
        for x in (-sx, 0.0, sx):
            mb.cyl(0.024, 1.1, (x, 0, z), tube, axis="Y", segs=5, caps=False)
    for y in (-sy, sy):                                                                    # guard rails, level 1
        for z in (2.47, 2.95):
            mb.cyl(0.022, 2.4, (0, y, z), tube, axis="X", segs=5, caps=False)
    P.beam(mb, (-sx, -sy, 0.2), (sx, -sy, 1.85), (0.03, 0.03), POLE, up=(0, 1, 0))            # bracing
    P.beam(mb, (sx, -sy, 2.1), (-sx, -sy, 3.8), (0.03, 0.03), POLE, up=(0, 1, 0))
    P.beam(mb, (sx, -sy, 0.2), (sx, sy, 1.85), (0.03, 0.03), POLE, up=(1, 0, 0))
    P.beam(mb, (sx, sy, 2.1), (sx, -sy, 3.8), (0.03, 0.03), POLE, up=(1, 0, 0))
    cols = ["wood_light", "wood_mid", "wood_light", "plank_gray"]
    for lv, z in enumerate((1.944, 3.894)):                                                # planks rest on the ledgers
        for i in range(4):
            mb.box((2.5, 0.25, 0.04), (0, -0.39 + 0.26 * i, z + 0.02), cols[(i + lv) % 4])
    for y in (-sy + 0.03, sy - 0.03):
        P.xbox(mb, (2.34, 0.02, 0.13), (0, y, 1.984), "wood_mid", skip=("-z",), base=True)      # toe boards

    def col(c):
        c.box((2.5, 1.2, 0.1), (0, 0, 1.884), "gray_mid", base=True)
        c.box((2.5, 1.2, 0.1), (0, 0, 3.834), "gray_mid", base=True)
        for x in (-sx, sx):
            for y in (-sy, sy):
                c.box((0.08, 0.08, 4.0), (x, y, 0), "gray_mid", base=True)
    P.col_part(root, col)
    mb.to_object(root, "mesh")


@asset("prop_ladder", col="none", notes="wall ladder module 0.5 x 3.0: origin on the WALL plane (y 0) at the bottom "
       "centre, rungs 0.16 in front of the wall (+Y) every 0.3 from z 0.15; stack modules at +3.0")
def prop_ladder(root):
    mb = K.MB()
    y = 0.16
    for sx in (-0.23, 0.23):
        P.xbox(mb, (0.014, 0.05, 3.0), (sx, y, 0.0), "steel", base=True)
        for z in (0.45, 2.55):
            P.xbox(mb, (0.014, y - 0.02, 0.04), (sx, (y - 0.02) * 0.5, z), POLE, skip=("+y", "-y"))
            P.xbox(mb, (0.09, 0.008, 0.1), (sx, 0.004, z), POLE, skip=("-y",))
    for i in range(10):
        P.xbox(mb, (0.446, 0.024, 0.024), (0, y, 0.15 + 0.3 * i), "steel", skip=("+x", "-x"))
    mb.to_object(root, "mesh")


@asset("prop_stairs_metal", col="mesh", notes="fire-escape flight rising toward +Y: 16 risers of 0.2, 15 treads "
       "(run 4.0, y -2.5 .. 1.5), 1 x 1 landing at z 3.2 (y 1.5 .. 2.5, open toward +Y, two support posts), railings "
       "0.95 both sides; origin = centre of the 5 m footprint; `col` = sloped slab + landing + rail walls")
def prop_stairs_metal(root):
    mb = K.MB()
    st, tr = "steel_dark", "steel"
    n, rise, y0, yt = 16, 0.2, -2.5, 1.5
    run = (yt - y0) / (n - 1)
    zt = n * rise

    def nosing(y):                                       # line through the tread front edges
        return min(zt, (y - y0) / run * rise + rise)

    for k in range(1, n):
        P.xbox(mb, (0.92, run + 0.02, 0.03), (0, y0 + (k - 0.5) * run, k * rise - 0.03), tr, skip=("+x", "-x"),
               base=True)
    ys = y0 - 0.013                                      # stringer start: lower edge just touches the ground
    for sx in (-0.48, 0.48):
        P.beam(mb, (sx, ys, nosing(ys) - 0.1), (sx, yt, zt - 0.1), (0.04, 0.22), st, up=(0, 0, 1), skip=())
        P.beam(mb, (sx, yt - 0.02, zt - 0.13), (sx, yt + 1.0, zt - 0.13), (0.04, 0.18), st, up=(0, 0, 1), skip=())
        P.xbox(mb, (0.07, 0.07, zt - 0.2), (sx * 0.96, yt + 0.94, 0.0), st, skip=("-z", "+z"), base=True)
        P.xbox(mb, (0.16, 0.16, 0.012), (sx * 0.96, yt + 0.94, 0.0), st, skip=("-z",), base=True)
        for y in (y0 + 0.12, y0 + 1.4, y0 + 2.7, yt + 0.02, yt + 0.97):                      # rail posts
            zb = nosing(y) + 0.005 if y < yt else zt
            P.xbox(mb, (0.035, 0.035, 0.95), (sx, y, zb), st, skip=("-z", "+z"), base=True)
        for dz, sec in ((0.95, 0.045), (0.5, 0.03)):                                          # hand + mid rail
            P.beam(mb, (sx, y0 + 0.12, nosing(y0 + 0.12) + dz), (sx, yt, zt + dz), (sec, sec), st, up=(0, 0, 1),
                   skip=())
            P.beam(mb, (sx, yt, zt + dz), (sx, yt + 1.0, zt + dz), (sec, sec), st, up=(0, 0, 1), skip=())
    mb.box((1.0, 1.0, 0.04), (0, yt + 0.5, zt - 0.02), tr)                                   # landing plate
    for y in (yt + 0.02, yt + 0.98):
        P.beam(mb, (-0.46, y, zt - 0.12), (0.46, y, zt - 0.12), (0.04, 0.16), st, up=(0, 0, 1))
    P.beam(mb, (-0.46, yt + 0.94, 0.3), (0.46, yt + 0.94, zt - 0.5), (0.03, 0.03), st, up=(0, 1, 0))   # X brace
    P.beam(mb, (0.46, yt + 0.94, 0.3), (-0.46, yt + 0.94, zt - 0.5), (0.03, 0.03), st, up=(0, 1, 0))

    def col(c):                                          # walking slope through the tread centres
        c.prism([(y0 - 0.13, 0.0), (yt - 0.13, zt - 0.1), (yt, zt), (yt, zt - 0.25), (y0 + 0.2, 0.0)], 1.0,
                "gray_mid", plane="YZ")
        c.box((1.0, 1.0, 0.2), (0, yt + 0.5, zt - 0.2), "gray_mid", base=True)
        for sx in (-0.5, 0.5):
            c.prism([(y0, 0.0), (yt, zt - 0.2), (yt, zt + 0.95), (y0, 1.15)], 0.06, "gray_mid", plane="YZ",
                    pos=(sx, 0, 0))
            c.box((0.06, 1.0, 0.95), (sx, yt + 0.5, zt), "gray_mid", base=True)
    P.col_part(root, col)
    mb.to_object(root, "mesh")


# =========================================================================== machines
@asset("prop_generator", notes="skid-mounted diesel generator 1.7 x 0.85 x 1.3, control panel on +Y")
def prop_generator(root):
    mb = K.MB()
    body, dk = "yellow", "charcoal"
    for sy in (-0.33, 0.33):
        mb.box((1.7, 0.1, 0.1), (0, sy, 0.0), dk, base=True)
    for sx in (-0.6, 0.6):
        P.xbox(mb, (0.1, 0.56, 0.08), (sx, 0, 0.01), dk, skip=("+y", "-y"), base=True)
        for sy in (-1, 1):
            P.qy(mb, sx - 0.16, sx + 0.16, 0.02, 0.08, sy * 0.386, "black", facing=sy)           # fork pockets
    mb.box((1.56, 0.76, 0.9), (0, 0, 0.1), body, base=True, bevel=0.03)
    mb.box((1.6, 0.8, 0.04), (0, 0, 0.99), dk, base=True)                                     # roof lip
    yf = 0.38
    # +X end: radiator grille
    P.qx(mb, -0.3, 0.3, 0.2, 0.9, 0.786, dk)
    for i in range(5):
        P.xbox(mb, (0.02, 0.6, 0.035), (0.795, 0, 0.27 + i * 0.14), "gray_dark", skip=("-x",))
    # +Y side: control panel + service door
    mb.box((0.44, 0.02, 0.36), (-0.46, yf + 0.006, 0.72), dk)
    P.qy(mb, -0.62, -0.42, 0.76, 0.86, yf + 0.02, "screen_blue")
    for i, cn in enumerate(("led_green", "emis_always_amber", "led_red")):
        P.qy(mb, -0.38 + i * 0.045, -0.35 + i * 0.045, 0.82, 0.85, yf + 0.02, cn)
    mb.cyl(0.035, 0.03, (-0.33, yf + 0.025, 0.63), "red", axis="Y", segs=8)                    # emergency stop
    for i in range(3):
        mb.box((0.035, 0.02, 0.05), (-0.6 + i * 0.07, yf + 0.02, 0.62), "gray_light")
    for s, x in ((1, 0.28), (-1, 0.0)):                                                       # service doors
        mb.box((0.74 if s > 0 else 1.4, 0.012, 0.66), (x, s * (yf + 0.004), 0.5), "yellow_dark")
        mb.box((0.035, 0.02, 0.12), (x + (0.3 if s > 0 else 0.6), s * (yf + 0.016), 0.5), dk)
    mb.prism([(-0.07, 0.0), (0.07, 0.0), (0.0, 0.12)], 0.006, "black", plane="XZ", pos=(0.28, yf + 0.014, 0.6))
    mb.prism([(-0.045, 0.015), (0.045, 0.015), (0.0, 0.092)], 0.006, "hazard_yellow", plane="XZ",
             pos=(0.28, yf + 0.018, 0.6))
    # top: exhaust, filler, lifting eye
    mb.cyl(0.045, 0.26, (0.55, -0.2, 1.03), POLE, segs=6, base=True)
    mb.cyl(0.062, 0.05, (0.55, -0.2, 1.25), POLE, segs=6, base=True, rot=(0, 25, 0))
    mb.cyl(0.05, 0.03, (-0.55, 0.22, 1.03), "black", segs=6, base=True)
    mb.tube(P.arc3((0, 0, 1.03), 0.09, 0, 180, 4, "XZ"), 0.016, dk, segs=4)
    mb.to_object(root, "mesh")


@asset("prop_floodlight", col=box_col((0.5, 0.5, 2.6), (0, 0, 1.3)), notes="tripod work light 2.6 m, two LED heads "
       "facing +Y tilted 20 deg down; marker `light` is pitched so a spot pointing along its -Z (Godot -Y) shines "
       "forward and down")
def prop_floodlight(root):
    mb = K.MB()
    c, y = "charcoal", "hazard_yellow"
    for k in range(3):
        a = math.radians(90 + 120 * k)
        d = V((math.cos(a), math.sin(a), 0))
        P.beam(mb, d * 0.03 + V((0, 0, 0.82)), d * 0.72, (0.03, 0.03), y, up=(0, 0, 1), skip=("-y",))
        P.beam(mb, V((0, 0, 0.3)), d * 0.38 + V((0, 0, 0.39)), (0.02, 0.02), c, up=(0, 0, 1))
        mb.box((0.07, 0.07, 0.02), (d.x * 0.72, d.y * 0.72, 0.0), "rubber", base=True)
    mb.cyl(0.03, 1.3, (0, 0, 0.25), c, segs=6, base=True)
    mb.cyl(0.045, 0.09, (0, 0, 0.78), y, segs=6, base=True)
    mb.cyl(0.022, 1.0, (0, 0, 1.5), "steel", segs=6, base=True)
    mb.cyl(0.04, 0.06, (0, 0, 1.52), y, segs=6, base=True)
    mb.box((0.86, 0.04, 0.04), (0, 0, 2.43), c)                                              # T-bar
    for sx in (-0.26, 0.26):
        mb.box((0.03, 0.03, 0.14), (sx, 0, 2.5), c)
        with mb.at((sx, 0.03, 2.5), rot=(-20, 0, 0)):
            mb.box((0.34, 0.09, 0.24), (0, 0.02, 0), y, bevel=0.012)
            P.qy(mb, -0.15, 0.15, -0.1, 0.1, 0.071, "emis_lamp")
            for i in range(4):
                P.xbox(mb, (0.012, 0.035, 0.2), (-0.12 + 0.08 * i, -0.04, 0), c, skip=("+y",))    # heat sink
    S.limb(mb, [(0, -0.035, 2.4), (0.04, -0.06, 1.9), (0, -0.05, 1.45)], 0.01, "black", segs=3, cap1=False)
    K.marker(root, "light", (0, 0.12, 2.45), rot=(55, 0, 0))
    mb.to_object(root, "mesh")


@asset("prop_ac_wall", notes="wall-mounted AC condenser 0.88 x 0.36 x 0.7: origin on the WALL plane (y 0) under the "
       "brackets, unit hangs toward +Y; mount with z = height of the bracket feet")
def prop_ac_wall(root):
    mb = K.MB()
    w, dk = "offwhite", "charcoal"
    mb.box((0.84, 0.3, 0.56), (0, 0.19, 0.1), w, base=True, bevel=0.015)
    mb.box((0.88, 0.33, 0.025), (0, 0.19, 0.66), "gray_light", base=True)
    yf = 0.34
    P.disc(mb, 0.215, (-0.14, yf + 0.004, 0.38), dk, segs=10)                                 # fan opening
    P.disc(mb, 0.06, (-0.14, yf + 0.012, 0.38), "gray_mid", segs=6)
    for a in (0, 60, 120):
        with mb.at((-0.14, yf + 0.008, 0.38), rot=(0, a, 0)):
            P.qy(mb, -0.215, 0.215, -0.012, 0.012, 0.0, "gray_mid")
    for i in range(5):
        P.qy(mb, 0.16, 0.38, 0.2 + i * 0.085, 0.24 + i * 0.085, yf + 0.004, "gray_dark")       # side louvres
    P.qy(mb, 0.2, 0.34, 0.6, 0.635, yf + 0.004, "blue")
    for sx in (-0.3, 0.3):                                                                    # wall brackets
        P.xbox(mb, (0.04, 0.36, 0.03), (sx, 0.18, 0.085), POLE)
        P.beam(mb, (sx, 0.01, 0.0), (sx, 0.32, 0.075), (0.03, 0.025), POLE, up=(1, 0, 0))
        P.xbox(mb, (0.05, 0.01, 0.26), (sx, 0.005, 0.0), POLE, skip=("-y",), base=True)
    mb.tube([(0.42, 0.22, 0.2), (0.48, 0.22, 0.2), (0.48, 0.03, 0.26), (0.48, 0.0, 0.26)], 0.018, "gray_dark", segs=4)
    mb.to_object(root, "mesh")


# =========================================================================== ramps
def _kicker(root, W, L, H, n_planks, frames, col_segs, power=2.0, stations=(0.42, 0.62, 0.81, 0.985)):
    mb = K.MB()
    y0, y1 = -L * 0.5, L * 0.5

    def z_at(y):
        return H * ((y - y0) / L) ** power

    ys = [y0 + L * i / n_planks for i in range(n_planks + 1)]
    cols = ["wood_light", "wood_mid", "wood_light", "plank_gray", "wood_light", "wood_mid", "plank_gray"]
    for i in range(n_planks):
        a = V((0, ys[i], z_at(ys[i])))
        b = V((0, ys[i + 1], z_at(ys[i + 1])))
        d = (b - a).normalized()
        nrm = V((0, -d.z, d.y))
        P.beam(mb, a - nrm * 0.025 + d * 0.004, b - nrm * 0.025 - d * 0.004, (W, 0.05), cols[i % len(cols)],
               up=(0, 0, 1), skip=())
    st = "steel_dark"
    xs = [-(W * 0.5 - 0.14), W * 0.5 - 0.14] + ([0.0] if frames == 3 else [])
    stations = [y0 + L * t for t in stations]
    for x in xs:
        P.beam(mb, (x, stations[0] - 0.5, 0.035), (x, y1 - 0.02, 0.035), (0.06, 0.06), st, up=(0, 0, 1), skip=())
        prev = None
        for y in stations:
            top = z_at(y) - 0.055
            P.beam(mb, (x, y, 0.06), (x, y, top), (0.06, 0.06), st, up=(0, 1, 0))
            if prev is not None:
                P.beam(mb, (x, prev, 0.07), (x, y, top - 0.04), (0.04, 0.04), st, up=(1, 0, 0))
            prev = y
    yb = stations[-1]
    for z in (0.035, H - 0.16):
        P.beam(mb, (xs[0], yb, z), (xs[1], yb, z), (0.06, 0.06), st, up=(0, 0, 1))
    bays = [(xs[0], xs[2]), (xs[2], xs[1])] if frames == 3 else [(xs[0], xs[1])]
    for i, (xa, xb) in enumerate(bays):
        za, zb = (0.1, H - 0.22) if i % 2 == 0 else (H - 0.22, 0.1)
        P.beam(mb, (xa, yb, za), (xb, yb, zb), (0.035, 0.035), st, up=(0, 1, 0))
    P.striped_board(mb, W - 0.1, 0.22, 0.02, pos=(0, y1 - 0.012, H - 0.36), colors=("white", "red"), stripe=0.22,
                    slant=0.18, sides=("+y",))

    def col(c):
        cy = [y0 + L * i / col_segs for i in range(col_segs + 1)]
        for i in range(col_segs):
            ya, yb2 = cy[i], cy[i + 1]
            pts = [(ya, 0.0), (yb2, 0.0), (yb2, z_at(yb2))]
            if z_at(ya) > 1e-4:
                pts.append((ya, z_at(ya)))
            c.prism(pts, W, "gray_mid", plane="YZ")
    P.col_part(root, col)
    mb.to_object(root, "mesh")


@asset("prop_ramp_stunt", col="mesh", notes="4.0 x 7.0 x 1.8 curved plank kicker rising toward +Y (z = 1.8 t^2, "
       "27 deg at the lip), origin = centre of the footprint; `col` = 5 wedge segments")
def prop_ramp_stunt(root):
    _kicker(root, 4.0, 7.0, 1.8, 10, 3, 5)


@asset("prop_ramp_small", col="mesh", notes="2.5 x 3.5 x 0.8 curved plank kicker rising toward +Y (25 deg at the "
       "lip), origin = centre of the footprint; `col` = 4 wedge segments")
def prop_ramp_small(root):
    _kicker(root, 2.5, 3.5, 0.8, 6, 2, 4, stations=(0.55, 0.78, 0.985))


@asset("prop_ramp_dirt", col="mesh", notes="6 x 8 x 1.6 dirt kicker rising toward +Y with a steep back; skirt "
       "reaches 0.3 m below z = 0; the mesh itself is the collider")
def prop_ramp_dirt(root):
    mb = K.MB()
    nx, ny = 8, 10
    W, L, H = 6.0, 8.0, 1.6
    rnd = random.Random(6)

    def height(u, v):
        ramp = (v / 0.8) ** 1.7 if v < 0.8 else max(0.0, 1.0 - ((v - 0.8) / 0.2) ** 1.4)
        side = max(0.0, 1.0 - abs(u) ** 3.2)
        return H * ramp * side

    grid = {}
    for i in range(nx + 1):
        for j in range(ny + 1):
            u = i / nx * 2.0 - 1.0
            v = j / ny
            edge = i in (0, nx) or j in (0, ny)
            x, y = u * W * 0.5, (v - 0.5) * L
            z = height(u, v)
            if not edge:
                x += rnd.uniform(-0.1, 0.1)
                y += rnd.uniform(-0.1, 0.1)
                z = max(0.03, z + rnd.uniform(-0.035, 0.035))
            else:
                z = 0.0
            grid[(i, j)] = mb.bm.verts.new(V((x, y, z)))
    faces = []
    for i in range(nx):
        for j in range(ny):
            faces.append(mb.bm.faces.new([grid[(i, j)], grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)]]))
    # skirt going into the ground
    ring = [(i, 0) for i in range(nx)] + [(nx, j) for j in range(ny)] + [(i, ny) for i in range(nx, 0, -1)] + \
           [(0, j) for j in range(ny, 0, -1)]
    low = [mb.bm.verts.new(V((grid[k].co.x * 1.03, grid[k].co.y * 1.03, -0.3))) for k in ring]
    n = len(ring)
    for k in range(n):
        k2 = (k + 1) % n
        faces.append(mb.bm.faces.new([grid[ring[k2]], grid[ring[k]], low[k], low[k2]]))
    bmesh.ops.triangulate(mb.bm, faces=faces)
    mb.paint(list(mb.bm.faces), "dirt")

    def tone(f):
        c = f.calc_center_median()
        if f.normal.z < 0.72:
            return "mud"
        if abs(c.x) < 1.2 and c.y < 2.4:
            return "sand_wet" if rnd.random() < 0.35 else None
        return "mud" if rnd.random() < 0.22 else None
    S.repaint(mb, list(mb.bm.faces), tone)
    S.fit_box(mb, (W, L, H + 0.3), zmin=-0.3)
    mb.to_object(root, "mesh")


# =========================================================================== registry of this module
IDS = ["prop_pallet", "prop_crate", "prop_crate_small", "prop_barrel", "prop_barrel_explosive", "prop_gas_tank",
       "prop_gas_tank_large", "prop_container", "prop_container_open", "prop_cable_spool", "prop_tire",
       "prop_tire_stack", "prop_pipe_stack", "prop_scaffold", "prop_generator", "prop_floodlight", "prop_ac_wall",
       "prop_ladder", "prop_stairs_metal", "prop_ramp_stunt", "prop_ramp_small", "prop_ramp_dirt"]

BUDGET = {"prop_container": 500, "prop_container_open": 500}

ROW_Y = K.CATEGORIES["StreetProps"][1]
X0 = 150.0
SHEETS = [
    ("yard_small", ["prop_pallet", "prop_crate", "prop_crate_small", "prop_barrel", "prop_barrel_explosive",
                    "prop_gas_tank", "prop_tire", "prop_tire_stack", "prop_ac_wall", "prop_ladder"], 2.0, 2.4, 5),
    ("yard_mid", ["prop_cable_spool", "prop_generator", "prop_floodlight", "prop_gas_tank_large", "prop_pipe_stack",
                  "prop_scaffold"], 4.6, 4.0, 3),
    ("containers", ["prop_container", "prop_container_open"], 4.0, 8.0, 2),
    ("ramps", ["prop_stairs_metal", "prop_ramp_small", "prop_ramp_stunt", "prop_ramp_dirt"], 7.5, 9.0, 4),
]


def do_layout():
    return P.layout(SHEETS, ROW_Y, X0)
