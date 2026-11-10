"""props_misc - P3 underwater set, activity props and VFX helper meshes for NEON TIDE (SPEC_PROPS_NATURE.md).

    import props_common as P, props_shapes as S, props_misc as M
    print(S.run(M.IDS)); M.do_layout()

Underwater ids export to props/<id> (corals / seaweed are listed in the Nature collection), VFX helpers to vfx/<id>
(category VFX, origin at the centre, col none).
"""
import math
import random

from mathutils import Vector, Matrix

import gta_kit as K
import props_common as P
import props_shapes as S
from props_common import asset, cyl_col, box_col

V = Vector
POLE = "steel_dark"
REEF = {"category": "Nature", "folder": "props"}
FX = {"category": "VFX", "folder": "vfx", "col": "none"}


def _frame(mb, origin, xa, ya):
    """Push a local frame (x axis xa, y axis ya, z = xa x ya) at origin onto the builder stack (pop it yourself)."""
    xa = V(xa).normalized()
    za = xa.cross(V(ya)).normalized()
    ya = za.cross(xa).normalized()
    o = V(origin)
    m = Matrix(((xa.x, ya.x, za.x, o.x), (xa.y, ya.y, za.y, o.y), (xa.z, ya.z, za.z, o.z), (0, 0, 0, 1)))
    mb.stack.append(mb.stack[-1] @ m)


# =========================================================================== reef
def _coral_branch(mb, rnd, base, d, length, r, depth, col, tip):
    d = d.normalized()
    side = d.cross(V((0, 0, 1)))
    if side.length < 1e-3:
        side = V((1, 0, 0))
    side.normalize()
    end = base + d * length
    mid = base + d * (length * 0.5) + side * rnd.uniform(-0.12, 0.12) * length
    start = base - d * r * 0.6
    if depth == 0:
        S.limb(mb, [start, mid, end], [r, r * 0.82, 0.0], col, segs=4, tip=True, ring_colors=[col, tip])
        return
    S.limb(mb, [start, mid, end], [r, r * 0.9, r * 0.78], col, segs=5, cap1=True)
    k = 2 if rnd.random() < 0.75 else 3
    for i in range(k):
        ang = math.radians(rnd.uniform(24, 42))
        az = 2 * math.pi * i / k + rnd.uniform(-0.6, 0.6)
        perp = side * math.cos(az) + d.cross(side) * math.sin(az)
        nd = (d * math.cos(ang) + perp * math.sin(ang) + V((0, 0, 0.3))).normalized()
        _coral_branch(mb, rnd, end - d * r * 0.3, nd, length * rnd.uniform(0.62, 0.78), r * 0.72, depth - 1, col, tip)


@asset("coral_a", col="none", notes="branching staghorn coral about 1.0 m high on a small rock; pale tips", **REEF)
def coral_a(root):
    mb = K.MB()
    rnd = random.Random(7)
    P.rock(mb, (0.62, 0.52, 0.3), (0, 0, -0.08), seed=3, n=9, color="rock_dark", dark="mud", light="moss", cut=0.15)
    trunks = [(20, 0.42, 0.085, 2), (140, 0.38, 0.08, 2), (250, 0.32, 0.072, 1), (320, 0.28, 0.068, 1),
              (80, 0.24, 0.065, 1)]
    for az, ln, r, depth in trunks:
        a = math.radians(az)
        d = V((math.cos(a) * 0.45, math.sin(a) * 0.45, 1.0))
        base = V((math.cos(a) * 0.08, math.sin(a) * 0.08, 0.1))
        _coral_branch(mb, rnd, base, d, ln, r, depth, "coral_pink", "flower_white")
    mb.to_object(root, "mesh")


def _fan(mb, base, az, w, h, cols, seed, cup=0.06):
    """Cupped double-sided sea fan standing at `base`, facing azimuth az (deg)."""
    rnd = random.Random(seed)
    a = math.radians(az)
    nrm = V((math.cos(a), math.sin(a), 0.0))
    u = V((-nrm.y, nrm.x, 0.0))
    up = V((0, 0, 1))
    base = V(base)
    top = base + up * 0.12
    S.limb(mb, [base - up * 0.05, top], [0.035, 0.028], cols[0], segs=4)
    n = 7
    arc = []
    for i in range(n + 1):
        t = math.radians(12 + 156 * i / n)
        rr = rnd.uniform(0.86, 1.0)
        c = math.cos(t)
        arc.append(top + u * (c * w * 0.5 * rr) + up * (math.sin(t) * h * rr) - nrm * (cup * (1.0 - abs(c))))
    for i in range(n):
        tri = [top, arc[i], arc[i + 1]]
        col = cols[i % len(cols)]
        P.fpoly(mb, tri, col, nrm)
        P.fpoly(mb, list(reversed(tri)), col, -nrm)


def _sponge(mb, pos, r, h, col="purple"):
    with mb.at(pos):
        P.lathe(mb, [(r, -0.04), (r * 1.12, h), (r * 0.78, h), (r * 0.72, h * 0.45), (0.0, h * 0.45)], col, segs=6,
                colors=[col, col, "navy", "navy"], cap0=False, smooth=False)


@asset("coral_b", col="none", notes="reef cluster about 1.2 x 1.0 x 0.8: brain coral dome + two sea fans + two tube "
       "sponges", **REEF)
def coral_b(root):
    mb = K.MB()
    P.rock(mb, (0.7, 0.5, 0.22), (-0.3, 0.25, -0.06), seed=8, n=8, color="rock_dark", dark="mud", light="moss", cut=0.2)
    S.canopy(mb, [{"r": 0.42, "pos": (0.2, -0.12, 0.04), "scale": (1.15, 1.0, 0.62), "subdiv": 2, "jitter": 0.06,
                   "seed": 5}], color="coral_orange", dark="orange", light=None, speckle=0.35, floor=0.0)
    _fan(mb, (-0.38, 0.28, 0.08), 75, 0.8, 0.78, ["coral_orange", "orange"], 2)
    _fan(mb, (-0.05, 0.42, 0.05), 105, 0.5, 0.56, ["coral_pink", "pink"], 3, cup=0.05)
    _sponge(mb, (-0.36, -0.3, 0.0), 0.075, 0.42)
    _sponge(mb, (-0.16, -0.44, 0.0), 0.06, 0.28, "magenta")
    mb.to_object(root, "mesh")


@asset("seaweed_a", col="none", notes="2.5 m kelp clump: 5 twisting double-sided strands + blades on the Foliage "
       "material (sways), small holdfast rock", **REEF)
def seaweed_a(root):
    mb = K.MB()
    rnd = random.Random(12)
    cols = ["@F:seaweed", "@F:seaweed", "@F:moss", "@F:seaweed", "@F:olive"]
    P.rock(mb, (0.36, 0.3, 0.18), (0, 0, -0.06), seed=4, n=8, color="rock_dark", dark="mud", cut=0.1)
    widths = [0.07, 0.17, 0.22, 0.23, 0.2, 0.15, 0.05]
    for s in range(5):
        a = 2 * math.pi * s / 5 + rnd.uniform(-0.3, 0.3)
        r0 = rnd.uniform(0.08, 0.2)
        base = V((math.cos(a) * r0, math.sin(a) * r0, -0.02))
        hgt = 2.5 if s == 0 else 2.5 * rnd.uniform(0.62, 0.95)
        lean = V((math.cos(a), math.sin(a), 0)) * rnd.uniform(0.35, 0.7)
        ph = rnd.uniform(0, 6.28)
        spine = []
        for i in range(7):
            t = i / 6
            wob = V((math.sin(ph + t * 4.0), math.cos(ph + t * 3.3), 0)) * (0.12 * t)
            spine.append(base + lean * (t * t) + wob + V((0, 0, hgt * t)))
        A, B = [], []
        for i, p in enumerate(spine):
            tw = ph + i * 0.55
            lat = V((math.cos(tw), math.sin(tw), 0))
            A.append(p - lat * widths[i] * 0.5)
            B.append(p + lat * widths[i] * 0.5)
        P.strip2(mb, A, B, cols[s])
        for i in (2, 3, 4, 5):
            if rnd.random() < 0.7:
                p = spine[i]
                o = ph + i * 1.9
                out = V((math.cos(o), math.sin(o), 0))
                P.blade(mb, p, p + out * 0.38 + V((0, 0, 0.3)), 0.11, cols[s])
    mb.to_object(root, "mesh")


# =========================================================================== seabed props
@asset("prop_anchor", notes="1.6 m admiralty anchor lying on the seabed: shank along X, stock flat on the ground "
       "(along Y), one arm up, the other buried to z -0.5", **{"category": "StreetProps", "folder": "props"})
def prop_anchor(root):
    mb = K.MB()
    rs, br = "rust", "brown"
    with mb.at((-0.8, 0.0, 0.055), rot=(0, 90, 0)):          # anchor frame: shank along local Z, arms in local XZ
        S.limb(mb, [(0, 0, 0.04), (0, 0, 0.8), (0, 0, 1.52)], [0.058, 0.052, 0.045], rs, segs=6, cap0=True,
               ring_colors=[rs, br])
        mb.ico(0.095, (0, 0, 0), rs, subdiv=1)                                              # crown
        for s in (-1, 1):
            arm = [(0, 0, 0.02), (s * 0.3, 0, 0.07), (s * 0.5, 0, 0.24), (s * 0.58, 0, 0.42)]
            S.limb(mb, arm, [0.055, 0.05, 0.042, 0.035], rs, segs=5, cap1=True)
            e = V(arm[-1])
            t = (e - V(arm[-2])).normalized()
            _frame(mb, e - t * 0.06, t, (0, 1, 0))
            try:
                mb.prism([(-0.24, 0.0), (-0.03, -0.16), (0.1, -0.06), (0.15, 0.0), (0.1, 0.06), (-0.03, 0.16)], 0.035,
                         rs, plane="XY")
            finally:
                mb.stack.pop()
        S.limb(mb, [(0, -0.62, 1.36), (0, 0, 1.36), (0, 0.62, 1.36)], [0.032, 0.042, 0.032], rs, segs=6, cap0=True)
        for s in (-1, 1):
            mb.ico(0.055, (0, s * 0.64, 1.36), rs, subdiv=1)                                 # stock balls
        loop = [(0.13 * math.cos(2 * math.pi * k / 10), 0.0, 1.66 + 0.13 * math.sin(2 * math.pi * k / 10))
                for k in range(10)]
        S.limb(mb, loop + [loop[0]], 0.022, rs, segs=4, cap1=False)                          # ring
    rnd = random.Random(5)

    def grime(f):
        if f.normal.z > 0.65 and rnd.random() < 0.4:
            return "moss"
        return br if rnd.random() < 0.18 else None
    S.repaint(mb, list(mb.bm.faces), grime)
    mb.to_object(root, "mesh")


@asset("prop_treasure_chest", notes="0.9 x 0.55 x 0.53 chest, hollow body filled with gold; `lid` part hinged at the "
       "back top edge: origin (0, -0.275, 0.36), rotate about its local X (negative X rotation opens it toward -Y)",
       **{"category": "StreetProps", "folder": "props"})
def prop_treasure_chest(root):
    mb = K.MB()
    wd, bd, gd = "wood_dark", "brass", "gold"
    hx, hy, H, t = 0.45, 0.275, 0.36, 0.04
    P.xbox(mb, (2 * hx, 2 * hy, H), (0, 0, 0), wd, skip=("+z",), base=True)                 # outer shell
    ix, iy, fz = hx - t, hy - t, 0.08
    P.qz(mb, -ix, ix, -iy, iy, fz, wd)                                                        # inner floor
    P.qx(mb, -iy, iy, fz, H, ix, wd, facing=-1)
    P.qx(mb, -iy, iy, fz, H, -ix, wd, facing=1)
    P.qy(mb, -ix, ix, fz, H, iy, wd, facing=-1)
    P.qy(mb, -ix, ix, fz, H, -iy, wd, facing=1)
    for a, b, c, d in (((-hx, -hy), (hx, -hy), (ix, -iy), (-ix, -iy)), ((hx, -hy), (hx, hy), (ix, iy), (ix, -iy)),
                       ((hx, hy), (-hx, hy), (-ix, iy), (ix, iy)), ((-hx, hy), (-hx, -hy), (-ix, -iy), (-ix, iy))):
        P.fpoly(mb, [(a[0], a[1], H), (b[0], b[1], H), (c[0], c[1], H), (d[0], d[1], H)], "wood_mid", (0, 0, 1))
    for x in (-0.27, 0.27):                                                                   # brass straps
        P.xbox(mb, (0.06, 2 * hy + 0.012, H - 0.02), (x, 0, 0.0), bd, skip=("+z", "-z", "+x", "-x"), base=True)
    for sx in (-1, 1):
        P.xbox(mb, (0.012, 0.12, H - 0.02), (sx * (hx + 0.006), 0, 0.0), bd, skip=("+z", "-z", "+y", "-y"), base=True)
    mb.box((0.14, 0.012, 0.12), (0, hy + 0.006, 0.27), gd)                                   # lock plate
    P.qy(mb, -0.012, 0.012, 0.222, 0.25, hy + 0.017, "black")
    S.canopy(mb, [{"r": 0.3, "pos": (0, 0, 0.19), "scale": (1.3, 0.72, 0.5), "subdiv": 2, "jitter": 0.08, "seed": 9}],
             color=gd, dark="yellow_dark", light="yellow", speckle=0.25, cull=False, floor=fz + 0.02)
    rnd = random.Random(2)
    for i in range(4):
        x, y = rnd.uniform(-0.28, 0.28), rnd.uniform(-0.12, 0.12)
        mb.cyl(0.035, 0.008, (x, y, 0.33 + rnd.uniform(-0.01, 0.01)), gd, segs=6,
               rot=(rnd.uniform(-25, 25), rnd.uniform(-25, 25), 0))
    P.octa(mb, 0.035, (0.12, 0.05, 0.345), "red", scale=(1, 1, 1.3))                        # gem
    mb.to_object(root, "mesh")

    lid = K.MB()
    arc = [(hy * math.cos(math.radians(a)), H + 0.17 * math.sin(math.radians(a))) for a in range(0, 181, 30)]
    lid.prism(arc, 2 * hx, wd, plane="YZ", cap_colors=("wood_mid", "wood_mid"))
    big = [(y * 1.05, H + 0.004 + (z - H) * 1.1) for y, z in arc]
    for x in (-0.27, 0.27):
        lid.prism(big, 0.06, bd, plane="YZ", pos=(x, 0, 0))
    lid.box((0.08, 0.02, 0.1), (0, hy + 0.012, 0.33), gd)                                    # hasp
    lid.to_object(root, "lid", origin=(0, -hy, H))


# --------------------------------------------------------------------------- wreck boat
HULL = [  # x, half width, depth to gunwale, sheer, keel rise
    (0.0, 1.45, 1.7, 0.0, 0.0), (1.5, 1.8, 1.75, 0.0, 0.0), (3.5, 1.95, 1.8, 0.05, 0.0), (5.0, 1.95, 1.8, 0.1, 0.0),
    (6.2, 1.9, 1.8, 0.15, 0.0), (8.0, 1.75, 1.8, 0.25, 0.0), (9.8, 1.35, 1.8, 0.4, 0.1), (11.2, 0.75, 1.85, 0.6, 0.35),
    (12.0, 0.1, 1.9, 0.75, 0.8)]


def _section(x, W, D, sh, kz, t=0.0, jag=None):
    """Open U hull section (port gunwale -> keel -> starboard gunwale); t > 0 -> inner skin."""
    g = D + sh
    rel = [(-1.0, 1.0), (-0.93, 0.55), (-0.62, 0.16), (0.0, 0.0), (0.62, 0.16), (0.93, 0.55), (1.0, 1.0)]
    out = []
    for i, (fy, fz) in enumerate(rel):
        z = kz + fz * (g - kz)
        y = fy * W
        if t > 0.0:
            y = fy * max(W - t, 0.02)
            z = z + t * (1.0 - fz)
        xx = x + (jag[i] if jag else 0.0)
        out.append(V((xx, y, z)))
    return out


def _lerp_station(xq):
    for a, b in zip(HULL[:-1], HULL[1:]):
        if a[0] <= xq <= b[0]:
            f = (xq - a[0]) / (b[0] - a[0])
            return tuple(a[i] + (b[i] - a[i]) * f for i in range(5))
    return HULL[-1]


def _hull_piece(mb, stations, x0, end0, end1, rnd, t=0.09):
    """Outer + inner skin, gunwale rims and end closures of one hull piece; stations = list of x.
    end0 / end1: 'transom', 'break' or 'stem'.  Geometry is shifted by -x0 (piece centre)."""
    jag0 = [rnd.uniform(-0.25, 0.25) for _ in range(7)] if end0 == "break" else None
    jag1 = [rnd.uniform(-0.25, 0.25) for _ in range(7)] if end1 == "break" else None
    outer, inner = [], []
    for i, xq in enumerate(stations):
        x, W, D, sh, kz = _lerp_station(xq)
        jag = jag0 if i == 0 else (jag1 if i == len(stations) - 1 else None)
        outer.append([p - V((x0, 0, 0)) for p in _section(x, W, D, sh, kz, 0.0, jag)])
        inner.append([p - V((x0, 0, 0)) for p in _section(x, W, D, sh, kz, t, jag)])
    faces = mb.loft(outer, "corrugated_red", closed=False, cap_start=False, cap_end=False, fix_normals=False)
    mb.loft([list(reversed(r)) for r in inner], "wood_dark", closed=False, cap_start=False, cap_end=False,
            fix_normals=False)
    for i in range(len(stations) - 1):                                                       # gunwale rims
        for k in (0, 6):
            P.fpoly(mb, [outer[i][k], outer[i + 1][k], inner[i + 1][k], inner[i][k]], "rust", (0, 0, 1))
    for idx, kind, sgn in ((0, end0, -1), (len(stations) - 1, end1, 1)):
        o, n = outer[idx], inner[idx]
        if kind == "break":
            for k in range(6):
                P.fpoly(mb, [o[k], o[k + 1], n[k + 1], n[k]], "rust", (sgn, 0, 0))
        else:
            P.fpoly(mb, list(o), "corrugated_red" if kind == "transom" else "rust", (sgn, 0, 0))
            P.fpoly(mb, list(n), "wood_dark", (-sgn, 0, 0))
    for f in faces:                                                                          # weathering
        f.normal_update()
        c = f.calc_center_median()
        if f.normal.z < -0.55:
            mb.paint([f], "mud")
        elif rnd.random() < 0.3:
            mb.paint([f], "rust" if rnd.random() < 0.6 else "moss")
    return outer, faces


def _hole(mb, face, rnd, r=0.35, color="black"):
    """Dark jagged patch on an existing (already transformed) face; mapped back into the builder's local frame."""
    face.normal_update()
    inv = mb.M.inverted()
    c = face.calc_center_median()
    n = face.normal.copy()
    u = (face.verts[1].co - face.verts[0].co).normalized()
    v = n.cross(u).normalized()
    pts = []
    for k in range(7):
        a = 2 * math.pi * k / 7
        rr = r * rnd.uniform(0.55, 1.0)
        pts.append(inv @ (c + n * 0.015 + u * math.cos(a) * rr + v * math.sin(a) * rr * 0.8))
    P.fpoly(mb, pts, color, inv.to_3x3() @ n)


WRECK_STERN = ((-3.4, 0.6, -0.4), (16, -3, -8))       # piece centre position, rotation (deg)
WRECK_BOW = ((3.1, -0.25, -0.3), (-11, -4, 12))


@asset("wreck_boat", col="mesh", notes="sunken 12 m fishing boat broken in two: stern half with wheelhouse rolled 16 "
       "deg, bow half (tilted mast) yawed 12 deg, 1.2 m gap; keels sit 0.4 m into the seabed; `col` = per-half floor "
       "+ side walls + ends (open on top so divers can enter) + wheelhouse box", **{"category": "StreetProps",
                                                                                     "folder": "props"})
def wreck_boat(root):
    mb = K.MB()
    rnd = random.Random(21)
    with mb.at(WRECK_STERN[0], rot=WRECK_STERN[1]):
        x0 = 2.6
        outer, faces = _hull_piece(mb, [0.0, 1.5, 3.5, 5.2], x0, "transom", "break", rnd)
        _hole(mb, faces[6 + 1], rnd, 0.32)
        half = [(xq - x0, 0.93 * (_lerp_station(xq)[1] - 0.09)) for xq in (0.1, 1.5, 3.5, 4.9)]
        deck = [(x, -w) for x, w in half] + [(x, w) for x, w in reversed(half)]
        mb.prism(deck, 0.08, "wood_dark", plane="XY", pos=(0, 0, 1.4))
        wx, wz = 2.3 - x0, 1.44                                                              # wheelhouse
        P.xbox(mb, (2.0, 2.1, 1.7), (wx, 0, wz), "offwhite", skip=("-z",), base=True)
        with mb.at((wx, 0, wz + 1.7), rot=(0, 6, -4)):
            mb.box((2.3, 2.5, 0.1), (0, 0, 0.05), "rust", base=True)
        P.qx(mb, -0.8, 0.8, wz + 0.95, wz + 1.45, wx + 1.006, "black")                         # bridge windows
        for s in (-1, 1):
            P.qy(mb, wx - 0.6, wx + 0.6, wz + 0.95, wz + 1.45, s * 1.056, "black", facing=s)
            P.qy(mb, wx - 0.9, wx + 0.9, wz + 0.2, wz + 0.5, s * 1.056, "rust", facing=s)     # rust streak
        P.qx(mb, -0.35, 0.35, wz, wz + 1.5, wx - 1.006, "black", facing=-1)                    # door hole
        S.limb(mb, [(wx - 0.5, 0.6, wz + 1.78), (wx - 0.7, 0.75, wz + 2.6), (wx - 1.2, 0.8, wz + 2.9)], 0.03, "rust",
               segs=4)                                                                       # bent antenna mast
    with mb.at(WRECK_BOW[0], rot=WRECK_BOW[1]):
        x0 = 9.0
        outer, faces = _hull_piece(mb, [6.0, 8.0, 9.8, 11.2, 12.0], x0, "break", "stem", rnd)
        _hole(mb, faces[1], rnd, 0.4)
        _hole(mb, faces[6 + 4], rnd, 0.3)
        fd = []
        for xq in (9.4, 10.4, 11.3):
            x, W, D, sh, kz = _lerp_station(xq)
            fd.append((xq - x0, W - 0.12, D + sh - 0.22))
        pts = [(fd[0][0], -fd[0][1]), (fd[1][0], -fd[1][1]), (fd[2][0], -fd[2][1]), (fd[2][0], fd[2][1]),
               (fd[1][0], fd[1][1]), (fd[0][0], fd[0][1])]
        mb.prism(pts, 0.08, "wood_dark", plane="XY", pos=(0, 0, fd[0][2] + 0.1))             # foredeck
        mb.prism([(6.3 - x0, -1.7), (7.4 - x0, -1.65), (7.4 - x0, -0.4), (6.3 - x0, -0.7)], 0.08, "wood_dark", plane="XY",
                 pos=(0, 0, 1.5))                                                            # deck remnant
        mb_base = V((8.3 - x0, 0.0, 1.6))
        top = mb_base + V((0.9, 1.8, 4.4))
        S.limb(mb, [mb_base, mb_base + (top - mb_base) * 0.5, top], [0.1, 0.08, 0.06], "wood_dark", segs=6)   # mast
        yard = mb_base + (top - mb_base) * 0.72
        S.limb(mb, [yard + V((-0.9, 0.35, 0.1)), yard + V((0.9, -0.35, -0.1))], 0.045, "wood_dark", segs=4, cap0=True)
        S.limb(mb, [top, V((11.9 - x0, 0.0, 2.6))], 0.014, "rope", segs=3)                    # stay
        S.limb(mb, [yard + V((0.9, -0.35, -0.1)), yard + V((1.0, -0.6, -1.6))], 0.012, "rope", segs=3)
    rnd2 = random.Random(4)
    for i in range(3):                                                                       # planks on the seabed
        x, y = rnd2.uniform(-0.6, 0.8), rnd2.uniform(-2.4, 2.4)
        mb.box((1.6, 0.18, 0.05), (x, y, 0.03), "wood_dark", rot=(0, rnd2.uniform(-6, 6), rnd2.uniform(0, 180)))
    mb.to_object(root, "mesh")

    def col(c):
        for (pos, rot), (xa, xb) in ((WRECK_STERN, (0.0, 5.2)), (WRECK_BOW, (6.0, 11.6))):
            x0 = 2.6 if xa < 1.0 else 9.0
            L = xb - xa
            xc = (xa + xb) * 0.5 - x0
            with c.at(pos, rot=rot):
                c.box((L, 3.2, 0.3), (xc, 0, 0.0), "gray_mid", base=True)
                for s in (-1, 1):
                    c.box((L, 0.2, 1.8), (xc, s * 1.75, 0.0), "gray_mid", base=True)
                for xe in (xa - x0, xb - x0):
                    c.box((0.2, 3.6, 1.8), (xe, 0, 0.0), "gray_mid", base=True)
                if xa < 1.0:
                    c.box((2.0, 2.1, 1.8), (2.3 - x0, 0, 1.44), "gray_mid", base=True)
    P.col_part(root, col)


# --------------------------------------------------------------------------- wreck car
@asset("wreck_car", notes="rusted car shell 4.4 x 1.8 x 1.35 (front +Y), no wheels, empty windows",
       **{"category": "StreetProps", "folder": "props"})
def wreck_car(root):
    mb = K.MB()
    rs, pb = "rust", "corrugated_blue"
    prof = [(2.18, 0.0), (2.24, 0.48), (2.08, 0.66), (1.05, 0.8), (-1.55, 0.84), (-2.15, 0.78), (-2.22, 0.42),
            (-2.1, 0.0)]
    mb.prism(prof, 1.76, pb, plane="YZ", side_colors=["rust", "rust", "rust", rs, pb, "rust", "rust", "mud"],
             cap_colors=(pb, pb))
    cy, cz = -0.35, 0.81
    mb.box((1.5, 2.1, 0.52), (0, cy, cz), rs, base=True, taper=(0.82, 0.62))                # cabin
    bx, by, tx, ty, z0, z1 = 0.75, 1.05, 0.615, 0.65, cz, cz + 0.52

    centre = V((0, cy, (z0 + z1) * 0.5))

    def inset(q, k=0.14, off=0.008):
        c = sum(q, V()) / 4.0
        n = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
        if n.dot(c - centre) < 0.0:
            n = -n
        return [c + (p - c) * (1.0 - k) + n * off for p in q], n

    faces = {
        "front": [V((-bx, cy + by, z0)), V((bx, cy + by, z0)), V((tx, cy + ty, z1)), V((-tx, cy + ty, z1))],
        "back": [V((bx, cy - by, z0)), V((-bx, cy - by, z0)), V((-tx, cy - ty, z1)), V((tx, cy - ty, z1))],
    }
    for key, q in faces.items():
        pts, n = inset(q, 0.16)
        P.fpoly(mb, pts, "black", n)
    for s in (-1, 1):                                                                         # side windows, B pillar
        q0 = [V((s * bx, cy - by, z0)), V((s * bx, cy + by, z0)), V((s * tx, cy + ty, z1)), V((s * tx, cy - ty, z1))]
        if s < 0:
            q0 = [V((s * bx, cy + by, z0)), V((s * bx, cy - by, z0)), V((s * tx, cy - ty, z1)), V((s * tx, cy + ty, z1))]
        c = sum(q0, V()) / 4.0
        n = V((s, 0, 0.25)).normalized()
        for f0, f1 in ((0.08, 0.47), (0.53, 0.92)):
            ya = cy - by + 2 * by * f0
            yb = cy - by + 2 * by * f1
            za, zb = z0 + 0.06, z1 - 0.06

            def xat(z):
                return s * (bx + (tx - bx) * (z - z0) / (z1 - z0)) + s * 0.008
            pa = [V((xat(za), ya + (ty - by) * 0.0, za)), V((xat(za), yb, za)),
                  V((xat(zb), cy + (yb - cy) * (ty / by), zb)), V((xat(zb), cy + (ya - cy) * (ty / by), zb))]
            P.fpoly(mb, pa, "black", n)
        for yw in (1.35, -1.3):                                                              # wheel arches
            arc = [(s * 0.884, yw + math.cos(math.radians(a)) * 0.38, 0.02 + math.sin(math.radians(a)) * 0.38)
                   for a in range(0, 181, 30)]
            P.fpoly(mb, arc, "black", (s, 0, 0))
    for y, sgn in ((2.24, 1), (-2.24, -1)):                                                  # bumpers + lamps
        mb.box((1.7, 0.08, 0.14), (0, y - sgn * 0.02, 0.3), "rust")
    for x in (-0.6, 0.6):
        P.qy(mb, x - 0.17, x + 0.17, 0.4, 0.5, 2.255, "black")
        P.qy(mb, x - 0.15, x + 0.15, 0.44, 0.52, -2.24, "red_dark", facing=-1)
    mb.to_object(root, "mesh")


# =========================================================================== activities
def _target_stand(mb, hinge_z, width=0.5):
    g = "gunmetal"
    mb.box((width + 0.1, 0.45, 0.04), (0, -0.05, 0), g, base=True)
    for sx in (-width * 0.5, width * 0.5):
        P.xbox(mb, (0.05, 0.05, hinge_z - 0.04), (sx, -0.04, 0.04), g, skip=("-z",), base=True)
        P.beam(mb, (sx, -0.25, 0.04), (sx, -0.04, hinge_z * 0.6), (0.035, 0.035), g, up=(1, 0, 0))
    mb.cyl(0.022, width + 0.06, (0, -0.02, hinge_z), "steel", axis="X", segs=6)


@asset("prop_target_round", col=box_col((0.6, 0.5, 1.5), (0, -0.05, 0.75)), notes="knock-down plate target: `mesh` = "
       "stand, `target` = 0.6 bullseye disc facing +Y, origin at its bottom edge on the hinge (0, 0, 0.9); rotate the "
       "target about local X (negative = falls back)")
def prop_target_round(root):
    mb = K.MB()
    _target_stand(mb, 0.9)
    mb.to_object(root, "mesh")
    tg = K.MB()
    prof = [(0.0, 0.0), (0.3, 0.0), (0.3, 0.025), (0.24, 0.025), (0.18, 0.025), (0.12, 0.025), (0.06, 0.025),
            (0.0, 0.025)]
    with tg.at((0, 0.0, 1.2), rot=(-90, 0, 0)):
        P.lathe(tg, prof, "white", segs=16, colors=["gunmetal", "black", "white", "red", "white", "red", "yellow"],
                smooth=False)
    tg.box((0.06, 0.04, 0.06), (0, -0.015, 0.92), "steel")                                    # hinge lug
    tg.to_object(root, "target", origin=(0, 0, 0.9))


@asset("prop_target_man", col=box_col((0.7, 0.5, 1.95), (0, -0.05, 0.98)), notes="abstract silhouette target (rounded "
       "torso board + head disc with scoring rings, not a realistic person): `mesh` = stand, `target` = board facing "
       "+Y, origin at its bottom edge on the hinge (0, 0, 0.9)")
def prop_target_man(root):
    mb = K.MB()
    _target_stand(mb, 0.9, 0.56)
    mb.to_object(root, "mesh")
    tg = K.MB()
    z0, y0, th = 0.9, 0.0, 0.02
    body = [(-0.3, z0), (0.3, z0), (0.3, z0 + 0.52), (0.26, z0 + 0.62), (0.16, z0 + 0.68), (0.07, z0 + 0.7),
            (-0.07, z0 + 0.7), (-0.16, z0 + 0.68), (-0.26, z0 + 0.62), (-0.3, z0 + 0.52)]
    P.plate(tg, body, y0, th, "khaki", back="cardboard")
    head = P.ngon(0.12, 10, 0.0, z0 + 0.84)
    P.plate(tg, head, y0, th, "khaki", back="cardboard")
    tg.box((0.06, th, 0.06), (0, y0 + th * 0.5, z0 + 0.715), "khaki")                        # neck
    yf = y0 + th + 0.004

    def ring(cx, cz, rx, rz, w, col, n=12):
        for k in range(n):
            a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
            o0 = (cx + math.cos(a0) * rx, cz + math.sin(a0) * rz)
            o1 = (cx + math.cos(a1) * rx, cz + math.sin(a1) * rz)
            i0 = (cx + math.cos(a0) * (rx - w), cz + math.sin(a0) * (rz - w))
            i1 = (cx + math.cos(a1) * (rx - w), cz + math.sin(a1) * (rz - w))
            P.fpoly(tg, [(o0[0], yf, o0[1]), (i0[0], yf, i0[1]), (i1[0], yf, i1[1]), (o1[0], yf, o1[1])], col, (0, 1, 0))
    for rx, rz in ((0.22, 0.25), (0.14, 0.16)):
        ring(0.0, z0 + 0.4, rx, rz, 0.014, "black")
    P.fpoly(tg, [(math.cos(2 * math.pi * k / 8) * 0.06, yf, z0 + 0.4 + math.sin(2 * math.pi * k / 8) * 0.065)
                 for k in range(8)], "red", (0, 1, 0))
    ring(0.0, z0 + 0.84, 0.07, 0.07, 0.012, "black", n=8)
    tg.to_object(root, "target", origin=(0, 0, z0))


@asset("prop_checkpoint_ring", col="none", notes="6 m glowing checkpoint arch (half ring, inner span 5.6, top z 3.2) "
       "standing across X: drive / fly through along Y; neon_yellow tube on two dark feet")
def prop_checkpoint_ring(root):
    mb = K.MB()
    R, n = 3.0, 18
    pts = [(R * math.cos(math.pi * i / n), 0.0, R * math.sin(math.pi * i / n)) for i in range(n + 1)]
    pts[0] = (R, 0.0, -0.05)
    pts[-1] = (-R, 0.0, -0.05)
    S.limb(mb, pts, 0.2, "neon_yellow", segs=6, cap0=True, cap1=True,
           ring_colors=["neon_yellow" if (i // 2) % 2 == 0 else "neon_orange" for i in range(n)])
    for s in (-1, 1):
        mb.box((0.7, 0.7, 0.16), (s * R, 0, 0), "charcoal", base=True, bevel=0.03)
    mb.to_object(root, "mesh")


@asset("prop_start_banner", col="mesh", notes="10 m race start gantry: two posts (x +-5.0), top beam, checkered band "
       "z 3.9..4.9 (clearance 3.9), START lettering both sides; `col` = the two post boxes")
def prop_start_banner(root):
    mb = K.MB()
    for s in (-1, 1):
        mb.box((0.7, 0.7, 0.1), (s * 5.0, 0, 0), "concrete", base=True)
        P.xbox(mb, (0.42, 0.42, 5.5), (s * 5.0, 0, 0.1), "gray_light", skip=("-z",), base=True)
        for z in (0.6, 1.2):
            P.xbox(mb, (0.44, 0.44, 0.25), (s * 5.0, 0, z), "red", skip=("-z", "+z"), base=True)
    mb.box((10.42, 0.45, 0.5), (0, 0, 5.1), "red", base=True)
    mb.box((9.58, 0.04, 1.0), (0, 0, 3.9), "white", base=True)
    cols, rows = 16, 2
    w = 9.58 / cols
    for r in range(rows):
        for c in range(cols):
            if (r + c) % 2 == 0:
                continue
            x0 = -4.79 + c * w
            for sgn in (1, -1):
                P.qy(mb, x0, x0 + w, 3.9 + r * 0.5, 3.9 + (r + 1) * 0.5, sgn * 0.026, "black", facing=sgn)
    for rz, yoff in ((0, 0.231), (180, -0.231)):
        P.text(mb, "START", (0, yoff, 5.35), height=0.34, color="white", depth=0.012, rot=(0, 0, rz))
    mb.to_object(root, "mesh")

    def col(c):
        for s in (-1, 1):
            c.box((0.45, 0.45, 5.6), (s * 5.0, 0, 0), "gray_mid", base=True)
    P.col_part(root, col)


# =========================================================================== VFX helper meshes
def _shard(mb, size, seed, color, dark, n=7):
    """Faceted chunk scaled to exactly `size`, centred on the origin."""
    P.rock(mb, (1.0, 1.0, 1.0), (0, 0, 0), seed=seed, n=n, color=color, dark=dark, light=None, centered=True,
           lo=0.45, speckle=0.3)
    S.fit_box(mb, size, zmin=-size[2] * 0.5)


@asset("fx_debris_a", notes="concrete shard about 0.25", **FX)
def fx_debris_a(root):
    mb = K.MB()
    _shard(mb, (0.26, 0.18, 0.1), 11, "concrete", "concrete_dark")
    mb.to_object(root, "mesh")


@asset("fx_debris_b", notes="concrete chunk about 0.2", **FX)
def fx_debris_b(root):
    mb = K.MB()
    _shard(mb, (0.2, 0.16, 0.14), 12, "concrete_light", "concrete", n=8)
    mb.to_object(root, "mesh")


@asset("fx_debris_c", notes="long concrete splinter about 0.3", **FX)
def fx_debris_c(root):
    mb = K.MB()
    _shard(mb, (0.3, 0.09, 0.07), 13, "concrete_dark", "asphalt", n=6)
    mb.to_object(root, "mesh")


@asset("fx_debris_metal", notes="bent sheet-metal scrap about 0.25 (double-sided)", **FX)
def fx_debris_metal(root):
    mb = K.MB()
    a = [V((-0.12, -0.06, -0.01)), V((0.0, -0.08, 0.02)), V((0.13, -0.05, -0.02))]
    b = [V((-0.11, 0.07, 0.03)), V((0.01, 0.06, -0.01)), V((0.12, 0.08, 0.04))]
    P.strip2(mb, a, b, "steel_dark", colors=["steel_dark", "rust"])
    mb.to_object(root, "mesh")


@asset("fx_glass_shard", notes="triangular glass shard about 0.12, 6 mm thick", **FX)
def fx_glass_shard(root):
    mb = K.MB()
    mb.prism([(-0.05, -0.04), (0.07, -0.02), (-0.01, 0.07)], 0.006, "ice_blue", plane="XY")
    mb.to_object(root, "mesh")


@asset("fx_shell_casing", notes="spent brass casing 0.03 long, 0.01 diameter, axis X", **FX)
def fx_shell_casing(root):
    mb = K.MB()
    with mb.at((-0.015, 0, 0), rot=(0, 90, 0)):
        P.lathe(mb, [(0.0, 0.0), (0.0055, 0.0), (0.0055, 0.003), (0.005, 0.004), (0.005, 0.03), (0.0035, 0.03),
                     (0.0035, 0.026)], "brass", segs=6, cap0=False, cap1=False, smooth=True)
    mb.to_object(root, "mesh")


@asset("fx_rock_chunk", notes="rock chunk about 0.2", **FX)
def fx_rock_chunk(root):
    mb = K.MB()
    _shard(mb, (0.2, 0.17, 0.15), 21, "rock", "rock_dark", n=8)
    mb.to_object(root, "mesh")


@asset("fx_plank", notes="broken plank 0.6 x 0.1 x 0.025 with a splintered end", **FX)
def fx_plank(root):
    mb = K.MB()
    prof = [(-0.3, -0.05), (0.2, -0.05), (0.3, -0.02), (0.24, 0.0), (0.29, 0.03), (0.22, 0.05), (-0.3, 0.05)]
    mb.prism(prof, 0.025, "wood_mid", plane="XY", cap_colors=("wood_dark", "wood_mid"))
    mb.to_object(root, "mesh")


# =========================================================================== registry of this module
IDS_UNDERWATER = ["coral_a", "coral_b", "seaweed_a", "prop_anchor", "prop_treasure_chest", "wreck_boat", "wreck_car"]
IDS_ACTIVITIES = ["prop_target_round", "prop_target_man", "prop_checkpoint_ring", "prop_start_banner"]
IDS_VFX = ["fx_debris_a", "fx_debris_b", "fx_debris_c", "fx_debris_metal", "fx_glass_shard", "fx_shell_casing",
           "fx_rock_chunk", "fx_plank"]
IDS = IDS_UNDERWATER + IDS_ACTIVITIES + IDS_VFX

SHEETS_NATURE = [("reef", ["coral_a", "coral_b", "seaweed_a"], 2.4, 3.0, 3)]
SHEETS_PROPS = [
    ("seabed", ["prop_anchor", "prop_treasure_chest", "wreck_car"], 5.0, 4.0, 3),
    ("wreck", ["wreck_boat"], 15.0, 9.0, 1),
    ("activities", ["prop_target_round", "prop_target_man", "prop_checkpoint_ring", "prop_start_banner"], 11.0, 4.0, 4),
]
SHEETS_VFX = [("fx", IDS_VFX, 0.6, 0.6, 8)]


def do_layout():
    P.layout(SHEETS_NATURE, K.CATEGORIES["Nature"][1], 120.0)
    P.layout(SHEETS_PROPS, K.CATEGORIES["StreetProps"][1], 268.0)
    return P.layout(SHEETS_VFX, K.CATEGORIES["VFX"][1], 40.0)
