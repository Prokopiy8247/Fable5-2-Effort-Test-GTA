"""props_fences - P1 fences and walls for NEON TIDE (SPEC_PROPS_NATURE.md).

    import props_common as P, props_shapes as S, props_fences as M
    print(S.run(M.IDS)); M.do_layout()

All modules run along X with the origin at the base centre and tile end to end.  The "public" face is +Y
(boards / pickets in front, rails and posts behind).
"""
import math
import random

from mathutils import Vector

import gta_kit as K
import props_common as P
import props_shapes as S
from props_common import asset, cyl_col, box_col

V = Vector
GALV = "steel"
WIRE = "gray_mid"


# --------------------------------------------------------------------------- timber
@asset("fence_wood", dynamic=True, mass=25,
       notes="2.0 x 1.8 board fence; boards face +Y, rails + one centre post on -Y; tiles along X")
def fence_wood(root):
    mb = K.MB()
    rnd = random.Random(4)
    cols = ["wood_mid", "wood_mid", "wood_light", "wood_mid", "wood_mid", "wood_light", "wood_mid", "wood_mid",
            "wood_light", "wood_mid"]
    drops = [0.0, 0.02, 0.008, 0.03, 0.0, 0.015, 0.035, 0.005, 0.022, 0.012]
    for i in range(10):
        x = -0.9 + 0.2 * i
        P.xbox(mb, (0.192, 0.022, 1.8 - drops[i]), (x, 0.065, 0.0), cols[i], skip=("-z",), base=True)
    for z in (0.42, 1.38):
        mb.box((2.0, 0.04, 0.09), (0, 0.034, z), "wood_dark")
    P.xbox(mb, (0.09, 0.09, 1.7), (0, -0.031, 0.0), "wood_dark", skip=("-z",), base=True)
    for i in (1, 4, 8):                                                                   # nail-head plates
        x = -0.9 + 0.2 * i
        for z in (0.42, 1.38):
            P.qy(mb, x - 0.012, x + 0.012, z - 0.012, z + 0.012, 0.0815, "steel_dark")
    mb.to_object(root, "mesh")


@asset("fence_picket", dynamic=True, mass=12,
       notes="2.0 x 1.0 white picket fence; pickets face +Y, one centre post behind; tiles along X (0.2 pitch)")
def fence_picket(root):
    mb = K.MB()
    w = 0.09
    pk = [(-w / 2, 0.04), (w / 2, 0.04), (w / 2, 0.87), (0.0, 0.96), (-w / 2, 0.87)]
    for i in range(10):
        x = -0.9 + 0.2 * i
        mb.prism(pk, 0.02, "white", plane="XZ", pos=(x, 0.06, 0.0))
    for z in (0.26, 0.68):
        mb.box((2.0, 0.03, 0.07), (0, 0.035, z), "offwhite")
    P.xbox(mb, (0.09, 0.09, 0.93), (0, -0.025, 0.0), "white", skip=("-z", "+z"), base=True)
    P.pyramid(mb, (0.11, 0.11), 0.07, (0, -0.025, 0.93), "white", base=True)
    mb.to_object(root, "mesh")


# --------------------------------------------------------------------------- chain link
def _diamond(mb, x0, x1, z0, z1, pitch, width, color, y=0.0, ref=None):
    """Sparse chain-link pattern: two families of 45 degree double-sided ribbons inside the rectangle."""
    ref = x0 if ref is None else ref
    h = z1 - z0
    k0 = int(math.floor((x0 - h - ref) / pitch)) - 1
    k1 = int(math.ceil((x1 + h - ref) / pitch)) + 1
    n = 0
    for k in range(k0, k1 + 1):
        c = ref + k * pitch
        xs, xe = max(x0, c), min(x1, c + h)                       # rising  '/'
        if xe - xs > 0.05:
            P.ribbon(mb, (xs, y, z0 + xs - c), (xe, y, z0 + xe - c), width, color, normal=(0, 1, 0))
            n += 1
        xs, xe = max(x0, c - h), min(x1, c)                       # falling '\'
        if xe - xs > 0.05:
            P.ribbon(mb, (xs, y, z0 + c - xs), (xe, y, z0 + c - xe), width, color, normal=(0, 1, 0))
            n += 1
    return n


@asset("fence_chain", col=box_col((3.0, 0.1, 2.2), (0, 0, 1.1)),
       notes="3.0 x 2.2 chain-link panel; posts sit exactly on both ends (x +-1.5) so neighbours share them; "
             "mesh = flat double-sided ribbons (0.25 pitch, continuous across modules)")
def fence_chain(root):
    mb = K.MB()
    for sx in (-1.5, 1.5):
        mb.cyl(0.036, 2.2, (sx, 0, 0), GALV, segs=6, base=True, caps=False)
        P.pyramid(mb, (0.062, 0.062), 0.035, (sx, 0, 2.2), "steel_dark")
        mb.box((0.11, 0.11, 0.03), (sx, 0, 0.0), "concrete", base=True)
    mb.cyl(0.022, 3.0, (0, 0, 2.14), GALV, axis="X", segs=5, caps=False)                 # top rail
    P.xbox(mb, (3.0, 0.016, 0.016), (0, 0, 0.1), GALV, skip=("-x", "+x"))                # bottom tension wire
    _diamond(mb, -1.47, 1.47, 0.1, 2.14, 0.25, 0.022, WIRE, ref=-1.5)
    mb.to_object(root, "mesh")


def _gate_leaf(mb, sgn):
    """One 2 m leaf in closed position; sgn = -1 left leaf (hinge at x -2), +1 right leaf (mirrored)."""
    with mb.at((0, 0, 0), scale=(-sgn, 1, 1)):       # authored as the LEFT leaf: hinge x = -2 -> free end x = 0
        fr = "steel_dark"
        xa, xb, za, zb = -1.93, -0.035, 0.14, 2.1
        for a, b in (((xa, 0, za), (xb, 0, za)), ((xa, 0, zb), (xb, 0, zb))):
            P.beam(mb, a, b, (0.045, 0.045), fr, up=(0, 0, 1), skip=(), extend=0.0225)
        for x in (xa, xb):
            P.beam(mb, (x, 0, za), (x, 0, zb), (0.045, 0.045), fr, up=(0, 1, 0))
        P.beam(mb, (xa, 0, za), (xb, 0, zb), (0.03, 0.03), fr, up=(0, 1, 0))               # diagonal brace
        _diamond(mb, xa, xb, za, zb, 0.25, 0.022, WIRE, y=0.012, ref=-2.0)
        for z in (0.45, 1.8):                                                              # hinge straps
            mb.box((0.1, 0.03, 0.06), (-1.96, 0, z), "charcoal")
        mb.box((0.035, 0.05, 0.22), (-0.035, 0.035, 1.05), "charcoal")                     # latch body
        if sgn < 0:
            P.beam(mb, (-0.075, 0.035, 0.02), (-0.075, 0.035, 0.75), (0.018, 0.018), "charcoal", up=(0, 1, 0),
                   skip=())                                                                # drop rod
            mb.box((0.14, 0.03, 0.03), (-0.01, 0.035, 1.12), "charcoal")                   # latch bar
        else:
            mb.box((0.34, 0.012, 0.24), (-1.0, 0.03, 1.45), "hazard_yellow")               # warning plate
            mb.box((0.28, 0.014, 0.05), (-1.0, 0.032, 1.45), "black")


@asset("gate_chain", notes="4 m double chain-link gate: `mesh` = hinge posts at x +-2.0, `leaf_l` (origin = hinge "
       "at x -2) and `leaf_r` (origin = hinge at x +2) rotate about Z; bbox collider = closed gate")
def gate_chain(root):
    mb = K.MB()
    for sx in (-2.0, 2.0):
        mb.cyl(0.05, 2.3, (sx, 0, 0), GALV, segs=6, base=True, caps=False)
        P.pyramid(mb, (0.087, 0.087), 0.05, (sx, 0, 2.3), "steel_dark")
        mb.box((0.18, 0.18, 0.04), (sx, 0, 0.0), "concrete", base=True)
    mb.to_object(root, "mesh")
    for sgn, name in ((-1, "leaf_l"), (1, "leaf_r")):
        leaf = K.MB()
        _gate_leaf(leaf, sgn)
        leaf.to_object(root, name, origin=(2.0 * sgn, 0, 0))


@asset("fence_metal", notes="2.0 x 1.1 steel railing; posts sit exactly on both ends (x +-1.0); tiles along X")
def fence_metal(root):
    mb = K.MB()
    c, r = "gunmetal", "charcoal"
    for sx in (-1.0, 1.0):
        P.xbox(mb, (0.05, 0.05, 1.06), (sx, 0, 0.0), c, skip=("-z",), base=True)
        mb.box((0.11, 0.11, 0.015), (sx, 0, 0.0), r, base=True)
    mb.box((2.0, 0.07, 0.04), (0, 0, 1.08), c, bevel=0.008)                                # hand rail
    P.xbox(mb, (1.95, 0.03, 0.03), (0, 0, 0.9), c, skip=("-x", "+x"))
    P.xbox(mb, (1.95, 0.03, 0.03), (0, 0, 0.14), c, skip=("-x", "+x"))
    for i in range(9):
        x = -0.8 + 0.2 * i
        P.xbox(mb, (0.018, 0.018, 0.74), (x, 0, 0.155), r, skip=("-z", "+z"), base=True)
    mb.to_object(root, "mesh")


# --------------------------------------------------------------------------- masonry
@asset("wall_brick", notes="2.0 x 0.3 x 1.0 brick wall with concrete coping; flush ends, tiles along X")
def wall_brick(root):
    mb = K.MB()
    P.xbox(mb, (2.0, 0.3, 0.12), (0, 0, 0.0), "brick_dark", skip=("-z",), base=True)       # plinth course
    P.xbox(mb, (2.0, 0.26, 0.79), (0, 0, 0.12), "brick_red", skip=("-z", "+z"), base=True)
    cap = [(-0.15, 0.91), (0.15, 0.91), (0.15, 0.965), (0.105, 1.0), (-0.105, 1.0), (-0.15, 0.965)]
    mb.prism(cap, 2.0, "concrete_light", plane="YZ")
    rnd = random.Random(7)
    used = set()
    n = 0
    while n < 20:
        j = rnd.randrange(0, 10)
        i = rnd.randrange(0, 8)
        side = 1 if n % 2 == 0 else -1
        if (i, j, side) in used or (i - 1, j, side) in used or (i + 1, j, side) in used:
            continue
        used.add((i, j, side))
        x0 = -0.97 + 0.235 * i + (0.117 if j % 2 else 0.0)
        if x0 + 0.21 > 0.985:
            continue
        z0 = 0.128 + 0.078 * j
        P.qy(mb, x0, x0 + 0.21, z0, z0 + 0.066, side * 0.136, "brick_dark" if rnd.random() < 0.6 else "brick_tan",
             facing=side)
        n += 1
    mb.to_object(root, "mesh")


@asset("wall_concrete", notes="2.0 x 0.25 x 2.2 precast wall, pier in the middle of the module; flush ends, tiles along X")
def wall_concrete(root):
    mb = K.MB()
    c, d, l = "concrete", "concrete_dark", "concrete_light"
    P.xbox(mb, (2.0, 0.2, 0.2), (0, 0, 0.0), d, skip=("-z",), base=True)                   # kicker
    P.xbox(mb, (2.0, 0.15, 1.88), (0, 0, 0.2), c, skip=("-z", "+z"), base=True)            # panel
    P.xbox(mb, (2.0, 0.21, 0.07), (0, 0, 2.08), l, skip=("-z",), base=True)                # coping
    P.xbox(mb, (0.34, 0.25, 2.14), (0, 0, 0.0), c, skip=("-z", "+z"), base=True)           # pier
    mb.box((0.38, 0.25, 0.06), (0, 0, 2.14), l, base=True, taper=(0.86, 0.8))
    for side in (1, -1):
        for z in (0.82, 1.45):                                                             # formwork joints
            for x0, x1 in ((-0.99, -0.19), (0.19, 0.99)):
                P.qy(mb, x0, x1, z - 0.012, z + 0.012, side * 0.081, d, facing=side)
        for sx in (-0.6, 0.6):                                                             # tie holes
            for z in (0.5, 1.14, 1.76):
                P.qy(mb, sx - 0.022, sx + 0.022, z - 0.022, z + 0.022, side * 0.081, d, facing=side)
    mb.to_object(root, "mesh")


# =========================================================================== registry of this module
IDS = ["fence_wood", "fence_picket", "fence_chain", "fence_metal", "wall_brick", "wall_concrete", "gate_chain"]

ROW_Y = K.CATEGORIES["StreetProps"][1]
X0 = 125.0
SHEETS = [
    ("fences", ["fence_wood", "fence_picket", "fence_metal", "wall_brick", "wall_concrete", "fence_chain"], 3.6, 2.5, 3),
    ("gate", ["gate_chain"], 5.0, 2.5, 1),
]


def do_layout():
    return P.layout(SHEETS, ROW_Y, X0)
