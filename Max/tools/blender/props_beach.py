"""props_beach - P2 beach, park and pier props for NEON TIDE (SPEC_PROPS_NATURE.md).

    import props_common as P, props_shapes as S, props_beach as M
    print(S.run(M.IDS)); M.do_layout()

Front = +Y unless noted.  Coast facts used here (gta/code/world): promenade / pier deck top = 0.15, sea level = -1.0,
so the pier waterline sits 1.15 m below the deck top.  The game places the lifeguard tower with yaw 0 on a beach whose
sea lies toward Blender -Y, so the tower's lookout faces -Y and its ramp comes down toward +Y.
"""
import math
import random

from mathutils import Vector

import gta_kit as K
import props_common as P
import props_shapes as S
from props_common import asset, cyl_col, box_col

V = Vector
POLE = "steel_dark"


def _torus(mb, R, r, pos, rot, segs=12, prof=5, color_fn=None, color="orange"):
    """Ring (lifebuoy) around the local Z axis, cross-section with `prof` points."""
    pts = [(R + r * math.cos(math.radians(-90 + 360.0 * k / prof)), r * math.sin(math.radians(-90 + 360.0 * k / prof)))
           for k in range(prof)]
    with mb.at(pos, rot=rot):
        return P.lathe(mb, pts, color, segs=segs, closed=True, color_fn=color_fn, smooth=True)


def _buoy_colors(segs):
    q = segs // 4
    return lambda b, k: "orange" if (k // q) % 2 == 0 else "white"


def _ellipse(cx, cy, z, rx, ry, n):
    return [(cx + rx * math.cos(2 * math.pi * k / n), cy + ry * math.sin(2 * math.pi * k / n), z) for k in range(n)]


# =========================================================================== beach
@asset("prop_umbrella", col=cyl_col(0.06, 2.4), notes="beach umbrella, canopy 2.2 m (8 panels alternating tint_a / "
       "white, rim at z 1.97); the pole goes 0.25 m into the sand")
def prop_umbrella(root):
    mb = K.MB()
    n = 8
    R, zr, rm, zm, zt = 1.1, 1.97, 0.6, 2.25, 2.4
    mb.cyl(0.021, 2.62, (0, 0, -0.25), "white", segs=6, base=True)                      # pole
    mb.cyl(0.032, 0.14, (0, 0, 1.0), "gray_mid", segs=6, base=True)                     # tilt joint
    mb.cyl(0.03, 0.08, (0, 0, 1.76), "gray_mid", segs=6, base=True)                     # runner
    apex = V((0, 0, zt))
    T = [V((R * math.cos(2 * math.pi * k / n), R * math.sin(2 * math.pi * k / n), zr)) for k in range(n)]
    M = [V((rm * math.cos(2 * math.pi * k / n), rm * math.sin(2 * math.pi * k / n), zm)) for k in range(n)]
    for k in range(n):
        k2 = (k + 1) % n
        col = "tint_a" if k % 2 == 0 else "white"
        am = 2 * math.pi * (k + 0.5) / n
        up = V((math.cos(am) * 0.45, math.sin(am) * 0.45, 1.0))
        out = V((math.cos(am), math.sin(am), 0.0))
        for pts in ([apex, M[k], M[k2]], [M[k], T[k], T[k2], M[k2]]):
            P.fpoly(mb, pts, col, up)
            P.fpoly(mb, list(reversed(pts)), col, -up)
        tip = (T[k] + T[k2]) * 0.5 - V((0, 0, 0.11))                                    # scalloped valance
        P.fpoly(mb, [T[k], T[k2], tip], col, out)
        P.fpoly(mb, [T[k2], T[k], tip], col, -out)
        S.limb(mb, [(0, 0, 1.82), (M[k].x * 0.92, M[k].y * 0.92, M[k].z - 0.03)], 0.008, "gray_light", segs=3)
    P.lathe(mb, [(0.035, zt - 0.01), (0.0, zt + 0.08)], "white", segs=6, cap0=False)       # finial
    mb.to_object(root, "mesh")


def _sling(mb, A, B, hw, sag, sag_dir, cols):
    """Striped double-sided fabric between edge A and edge B (given at x = 0); stripes run from A to B."""
    A, B = V(A), V(B)
    Mid = (A + B) * 0.5 + V(sag_dir).normalized() * sag
    n = len(cols)
    for i in range(n):
        x0 = V((-hw + 2 * hw * i / n, 0, 0))
        x1 = V((-hw + 2 * hw * (i + 1) / n, 0, 0))
        for P0, P1 in ((A, Mid), (Mid, B)):
            mb.quad(P0 + x0, P0 + x1, P1 + x1, P1 + x0, cols[i], double=True)


@asset("prop_beach_chair", dynamic=True, mass=6, notes="low folding beach chair, sitter faces +Y; blue / white striped "
       "sling, aluminium frame, wooden armrests")
def prop_beach_chair(root):
    mb = K.MB()
    fr, wd = "aluminum", "wood_light"
    hw = 0.27
    sf, sb, bt = V((0, 0.24, 0.33)), V((0, -0.2, 0.25)), V((0, -0.47, 0.86))
    for sx in (-1, 1):
        x = V((sx * hw, 0, 0))
        S.limb(mb, [sf + x, sb + x, bt + x], 0.016, fr, segs=4, cap0=True)                # seat + back rail
        S.limb(mb, [sf + x, V((sx * hw, 0.31, 0.0))], 0.016, fr, segs=4)                   # front leg
        S.limb(mb, [sb + x + V((0, 0.03, 0.0)), V((sx * hw, -0.37, 0.0))], 0.016, fr, segs=4)   # back leg
        S.limb(mb, [sf + x + V((sx * 0.01, -0.02, 0.0)), V((sx * (hw + 0.025), 0.18, 0.47))], 0.013, fr, segs=4)
        mb.box((0.065, 0.52, 0.022), (sx * (hw + 0.025), -0.05, 0.48), wd)                   # armrest
    for p in (sf, bt, sb):                                                                # cross tubes
        S.limb(mb, [p + V((-hw, 0, 0)), p + V((hw, 0, 0))], 0.014, fr, segs=4, cap0=True)
    cols = ["fabric_blue", "white", "fabric_blue", "white", "fabric_blue"]
    w = hw - 0.018
    _sling(mb, sf + V((0, -0.02, 0.0)), sb + V((0, 0.015, 0.0)), w, 0.04, (0, 0, -1), cols)
    _sling(mb, sb + V((0, -0.012, 0.025)), bt + V((0, 0.015, -0.03)), w, 0.035, (0, -1, -0.4), cols)
    mb.to_object(root, "mesh")


@asset("prop_towel", col="none", notes="0.9 x 1.8 beach towel lying on the ground (tint_a, white end bands, 2 cm "
       "wrinkles) with a rolled pillow at -Y")
def prop_towel(root):
    mb = K.MB()
    xs = [-0.45, 0.0, 0.45]
    ys = [-0.9, -0.74, -0.66, -0.3, 0.15, 0.6, 0.66, 0.74, 0.9]
    rnd = random.Random(3)
    T = 0.012
    grid = {}
    for i, x in enumerate(xs):
        for j, y in enumerate(ys):
            z = T + (rnd.uniform(0.0, 0.02) if i == 1 or rnd.random() < 0.5 else 0.002)
            grid[(i, j)] = V((x, y, z))

    def band(j):
        return "white" if j in (1, 6) else "tint_a"

    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            P.fpoly(mb, [grid[(i, j)], grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)]], band(j), (0, 0, 1))
    ring = [(i, 0) for i in range(len(xs) - 1)] + [(len(xs) - 1, j) for j in range(len(ys) - 1)] + \
           [(i, len(ys) - 1) for i in range(len(xs) - 1, 0, -1)] + [(0, j) for j in range(len(ys) - 1, 0, -1)]
    for k in range(len(ring)):
        a, b = grid[ring[k]], grid[ring[(k + 1) % len(ring)]]
        mid = (a + b) * 0.5
        out = V((mid.x, mid.y * 0.5, 0.0))
        j = min(ring[k][1], ring[(k + 1) % len(ring)][1])
        P.fpoly(mb, [V((a.x, a.y, 0.0)), V((b.x, b.y, 0.0)), b, a], band(j), out)
    mb.cyl(0.065, 0.82, (0, -0.79, 0.075), "tint_a", axis="X", segs=7, cap_color="white")  # rolled pillow
    mb.to_object(root, "mesh")


@asset("prop_surfboard", notes="2.15 m board stuck tail-first 0.3 m into the sand, nose up, deck faces +Y and leans "
       "back 8 deg; tint_a with a white band and a wooden stringer; static (stuck)")
def prop_surfboard(root):
    mb = K.MB()
    L = 2.15
    st = [(0.0, 0.30, 0.03), (0.07, 0.40, 0.045), (0.25, 0.51, 0.06), (0.5, 0.55, 0.068), (0.7, 0.51, 0.062),
          (0.8, 0.44, 0.055), (0.9, 0.3, 0.042)]

    def ring(t, w, th):
        z = -0.3 + t * L
        return [(w * 0.5, 0, z), (w * 0.33, th * 0.5, z), (-w * 0.33, th * 0.5, z), (-w * 0.5, 0, z),
                (-w * 0.33, -th * 0.5, z), (w * 0.33, -th * 0.5, z)]

    with mb.at((0, 0, 0), rot=(8, 0, 0)):
        rings = [ring(*s) for s in st]
        mb.loft(rings, "tint_a", closed=True, cap_start=True, cap_end=False,
                ring_colors=["tint_a", "tint_a", "tint_a", "tint_a", "white", "tint_a"], fix_normals=False)
        apex = (0.0, 0.004, -0.3 + L)
        last = rings[-1]
        for k in range(6):
            mb.poly([last[k], last[(k + 1) % 6], apex], "tint_a")
        for a, b in zip(st[1:-1], st[2:]):                                                # stringer
            za, zb = -0.3 + a[0] * L, -0.3 + b[0] * L
            ya, yb = a[2] * 0.5 + 0.002, b[2] * 0.5 + 0.002
            P.fpoly(mb, [(0.006, ya, za), (0.006, yb, zb), (-0.006, yb, zb), (-0.006, ya, za)], "wood_light", (0, 1, 0))
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for v in mb.bm.verts:
        if v.co.z >= 0.0:
            for i in range(3):
                lo[i] = min(lo[i], v.co[i])
                hi[i] = max(hi[i], v.co[i])
    mb.to_object(root, "mesh")
    size = [hi[i] - lo[i] for i in range(2)] + [hi[2]]
    return {"col": box_col(size, ((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, hi[2] * 0.5))}


@asset("prop_volleyball_net", col="mesh", notes="beach volleyball net along X: posts at x +-4.6 (0.3 m into the "
       "sand), net 8.5 x 1.0 with its top at z 2.43, red/white antennas, guy lines to x +-5.7; `col` = posts + net panel")
def prop_volleyball_net(root):
    mb = K.MB()
    xp, ztop, zbot, xn = 4.6, 2.43, 1.43, 4.25
    for s in (-1, 1):
        mb.cyl(0.045, 2.95, (s * xp, 0, -0.3), "white", segs=8, base=True)
        mb.cyl(0.055, 0.04, (s * xp, 0, 2.62), "gray_mid", segs=8, base=True)
        mb.cyl(0.056, 0.5, (s * xp, 0, 0.0), "fabric_blue", segs=8, base=True, caps=False)   # pole pad
        S.limb(mb, [(s * xp, 0, 2.6), (s * 5.7, 0, 0.02)], 0.006, "rope", segs=3)          # guy line
        mb.box((0.1, 0.1, 0.04), (s * 5.7, 0, 0.0), "gray_dark", base=True)
        for z0, z1 in ((ztop - 0.035, ztop - 0.02), (zbot + 0.025, zbot + 0.05)):          # net cords to the post
            S.limb(mb, [(s * xn, 0, z0), (s * (xp - 0.045), 0, z1)], 0.006, "rope", segs=3)
        pts = [(s * xn, 0.012, zbot + 1.8 * i / 7) for i in range(8)]                        # antenna
        S.limb(mb, pts, 0.009, "white", segs=3, cap0=True,
               ring_colors=["red" if i % 2 == 0 else "white" for i in range(7)])
    for z0, z1 in ((ztop - 0.07, ztop), (zbot, zbot + 0.05)):                               # top / bottom bands
        mb.quad((-xn, 0, z0), (xn, 0, z0), (xn, 0, z1), (-xn, 0, z1), "white", double=True)
    for s in (-1, 1):                                                                       # side bands
        xa, xb = sorted((s * xn, s * (xn - 0.05)))
        mb.quad((xa, 0, zbot + 0.05), (xb, 0, zbot + 0.05), (xb, 0, ztop - 0.07), (xa, 0, ztop - 0.07), "white",
                double=True)
    nv = 34
    for i in range(1, nv):                                                                  # mesh
        x = -xn + 2 * xn * i / nv
        if abs(x) < xn - 0.06:
            P.ribbon(mb, (x, 0, zbot + 0.05), (x, 0, ztop - 0.07), 0.012, "charcoal", normal=(0, 1, 0))
    for k in range(1, 5):
        z = zbot + 0.05 + (ztop - zbot - 0.12) * k / 5
        P.ribbon(mb, (-(xn - 0.05), 0, z), (xn - 0.05, 0, z), 0.012, "charcoal", normal=(0, 1, 0))
    mb.to_object(root, "mesh")

    def col(c):
        for s in (-1, 1):
            c.box((0.12, 0.12, 2.66), (s * xp, 0, 0), "gray_mid", base=True)
        c.box((2 * xn, 0.06, ztop - zbot), (0, 0, zbot), "gray_mid", base=True)
    P.col_part(root, col)


@asset("prop_lifebuoy_stand", col=box_col((0.32, 0.3, 1.8), (0, 0, 0.9)), notes="red post with a white backboard "
       "holding an orange / white lifebuoy that faces +Y (ring centre z 1.2)")
def prop_lifebuoy_stand(root):
    mb = K.MB()
    mb.box((0.2, 0.2, 0.015), (0, -0.06, 0), POLE, base=True)
    P.xbox(mb, (0.1, 0.1, 1.72), (0, -0.06, 0.015), "red", skip=("-z", "+z"), base=True)
    P.pyramid(mb, (0.12, 0.12), 0.06, (0, -0.06, 1.735), "white", base=True)
    mb.box((0.68, 0.02, 0.7), (0, 0.0, 1.22), "red")                                       # board + red border
    mb.box((0.6, 0.02, 0.62), (0, 0.012, 1.22), "white")
    mb.box((0.04, 0.09, 0.04), (0, 0.06, 1.5), POLE)                                        # hook
    _torus(mb, 0.27, 0.06, (0, 0.085, 1.2), (90, 0, 0), segs=12, prof=5, color_fn=_buoy_colors(12))
    mb.to_object(root, "mesh")


@asset("prop_lifeguard_tower", col="mesh", notes="raised lifeguard hut: 3 x 3 deck at z 2.0 on stilts, hut 2.2 x 2.0, "
       "lookout porch + railing face -Y (the sea when placed with yaw 0), ramp descends toward +Y to y 5.9; tint_b roof "
       "/ trims / top rails, red-yellow flag; `col` = stilts, deck, hut, railings, ramp slab + rails")
def prop_lifeguard_tower(root):
    mb = K.MB()
    tb, wh, ow = "tint_b", "white", "offwhite"
    zd, hh = 2.0, 1.95
    hy0, hy1 = -0.5, 1.5
    run = 3.9
    # stilts + bracing
    for x in (-1.3, 1.3):
        for y in (-1.3, 1.3):
            P.xbox(mb, (0.16, 0.16, zd - 0.12 + 0.3), (x, y, -0.3), ow, skip=("-z", "+z"), base=True)
    for x in (-1.3, 1.3):
        P.beam(mb, (x, -1.22, 0.3), (x, 1.22, zd - 0.4), (0.1, 0.06), ow, up=(1, 0, 0))
        P.beam(mb, (x, 1.22, 0.3), (x, -1.22, zd - 0.4), (0.1, 0.06), ow, up=(1, 0, 0))
    P.beam(mb, (-1.22, -1.3, 0.3), (1.22, -1.3, zd - 0.4), (0.1, 0.06), ow, up=(0, 1, 0))
    P.beam(mb, (1.22, -1.3, 0.3), (-1.22, -1.3, zd - 0.4), (0.1, 0.06), ow, up=(0, 1, 0))
    # deck
    mb.box((3.0, 3.0, 0.12), (0, 0, zd - 0.12), "plank_gray", base=True)
    for i in range(1, 6):
        y = -1.5 + 0.5 * i
        P.qz(mb, -1.5, 1.5, y - 0.01, y + 0.01, zd + 0.004, "wood_dark")
    # hut
    P.xbox(mb, (2.2, hy1 - hy0, hh), (0, (hy0 + hy1) * 0.5, zd), wh, skip=("-z",), base=True)
    for x in (-1.1, 1.1):
        for y in (hy0, hy1):
            P.xbox(mb, (0.1, 0.1, hh), (x, y, zd), tb, skip=("-z", "+z"), base=True)      # corner boards
    zw0, zw1 = zd + 0.95, zd + 1.65
    P.qy(mb, -0.95, 0.95, zw0, zw1, hy0 - 0.006, "glass_dark", facing=-1)                # sea window
    mb.box((2.0, 0.1, 0.05), (0, hy0 - 0.03, zw0 - 0.025), tb)
    mb.box((2.0, 0.05, 0.05), (0, hy0 - 0.02, zw1 + 0.025), tb)
    for x in (-0.32, 0.32):
        mb.box((0.05, 0.03, zw1 - zw0), (x, hy0 - 0.012, (zw0 + zw1) * 0.5), tb)
    for s in (-1, 1):                                                                       # side windows
        P.qx(mb, -0.25, 1.0, zd + 1.0, zd + 1.6, s * (1.1 + 0.006), "glass_dark", facing=s)
        mb.box((0.1, 1.35, 0.05), (s * 1.13, 0.375, zd + 0.975), tb)
        mb.box((0.05, 1.35, 0.05), (s * 1.12, 0.375, zd + 1.625), tb)
    P.qy(mb, -0.42, 0.42, zd + 0.01, zd + 1.86, hy1 + 0.006, tb)                           # door (+Y)
    P.qy(mb, -0.28, 0.28, zd + 1.15, zd + 1.65, hy1 + 0.011, "glass_dark")
    mb.box((0.04, 0.03, 0.12), (0.3, hy1 + 0.02, zd + 0.95), "steel")
    # roof
    mb.box((2.8, 2.6, 0.06), (0, 0.5, zd + hh - 0.04), wh, base=True)                      # fascia / soffit
    E = [(-1.4, -0.8), (1.4, -0.8), (1.4, 1.8), (-1.4, 1.8)]
    ze, apex = zd + hh + 0.02, V((0, 0.5, 4.36))
    for k in range(4):
        a, b = E[k], E[(k + 1) % 4]
        P.fpoly(mb, [(a[0], a[1], ze), (b[0], b[1], ze), apex], tb, (0, 0, 1))
    # porch railing (open where the hut stands on the +Y side)
    c = 1.45
    posts = [(-c, -c), (0.0, -c), (c, -c), (-c, 0.0), (c, 0.0), (-c, c), (c, c)]
    for x, y in posts:
        P.xbox(mb, (0.07, 0.07, 1.0), (x, y, zd), wh, skip=("-z",), base=True)
    runs = [((-c, -c), (c, -c)), ((-c, -c), (-c, c)), ((c, -c), (c, c)), ((-c, c), (-1.1, c)), ((c, c), (1.1, c))]
    for (xa, ya), (xb, yb) in runs:
        P.beam(mb, (xa, ya, zd + 1.0), (xb, yb, zd + 1.0), (0.08, 0.05), tb, up=(0, 0, 1), skip=(), extend=0.04)
        P.beam(mb, (xa, ya, zd + 0.52), (xb, yb, zd + 0.52), (0.04, 0.05), wh, up=(0, 0, 1))
    _torus(mb, 0.22, 0.05, (-0.75, -c - 0.07, zd + 0.72), (90, 0, 0), segs=10, prof=4,
           color_fn=_buoy_colors(8))                                                        # lifebuoy on the rail
    # ramp
    d = V((0, run, -zd)).normalized()
    nrm = V((0, zd, run)).normalized()
    top0, top1 = V((0, hy1, zd)), V((0, hy1 + run, 0.0))
    P.beam(mb, top0 - nrm * 0.04, top1 - nrm * 0.04, (1.0, 0.08), "plank_gray", up=(0, 0, 1), skip=())
    for i in range(8):
        p = top0 + d * (0.35 + i * 0.5) + nrm * 0.0125
        P.beam(mb, p + V((-0.44, 0, 0)), p + V((0.44, 0, 0)), (0.05, 0.025), "wood_dark", up=nrm,
               skip=("-z", "+y", "-y"))
    for s in (-1, 1):
        x = s * 0.52
        for t in (0.0, 0.33, 0.66, 0.93):
            p = top0 + d * (t * (run ** 2 + zd ** 2) ** 0.5)
            P.xbox(mb, (0.05, 0.05, 0.92), (x, p.y, p.z - 0.04), wh, skip=("-z",), base=True)
        P.beam(mb, top0 + V((x, 0, 0.9)), top0 + d * ((run ** 2 + zd ** 2) ** 0.5 * 0.93) + V((x, 0, 0.9)),
               (0.06, 0.05), tb, up=(0, 0, 1), skip=())
        for y in (hy1 + 1.0, hy1 + 2.2):                                                    # ramp supports
            ztop = zd * (1.0 - (y - hy1) / run) - 0.1
            P.xbox(mb, (0.1, 0.1, ztop + 0.3), (s * 0.4, y, -0.3), ow, skip=("-z", "+z"), base=True)
    # flag
    fx, fy = c + 0.05, -c - 0.05
    mb.cyl(0.025, 4.5 - zd + 0.12, (fx, fy, zd - 0.12), wh, segs=6, base=True)
    mb.sphere(0.04, (fx, fy, 4.5), "gold", segs=6, rings=4)
    for z0, z1, colr in ((4.12, 4.28, "yellow"), (4.28, 4.44, "red")):
        mb.quad((fx + 0.02, fy, z0), (fx + 0.6, fy, z0), (fx + 0.6, fy, z1), (fx + 0.02, fy, z1), colr, double=True)
    mb.to_object(root, "mesh")

    def col(cm):
        for x in (-1.3, 1.3):
            for y in (-1.3, 1.3):
                cm.box((0.16, 0.16, zd), (x, y, 0), "gray_mid", base=True)
        cm.box((3.0, 3.0, 0.12), (0, 0, zd - 0.12), "gray_mid", base=True)
        cm.box((2.2, hy1 - hy0, 2.4), (0, (hy0 + hy1) * 0.5, zd), "gray_mid", base=True)
        cm.box((3.0, 0.08, 1.0), (0, -c, zd), "gray_mid", base=True)
        for s in (-1, 1):
            cm.box((0.08, 3.0, 1.0), (s * c, 0, zd), "gray_mid", base=True)
            cm.box((0.4, 0.08, 1.0), (s * 1.28, c, zd), "gray_mid", base=True)
            cm.prism([(hy1, zd), (hy1 + run, 0.0), (hy1 + run, 0.9), (hy1, zd + 0.9)], 0.06, "gray_mid", plane="YZ",
                     pos=(s * 0.52, 0, 0))
        cm.prism([(hy1, zd), (hy1 + run, 0.0), (hy1 + run - 0.4, 0.0), (hy1, zd - 0.25)], 1.0, "gray_mid", plane="YZ")
    P.col_part(root, col)


# =========================================================================== water / pier
@asset("prop_buoy", col=cyl_col(0.5, 2.2, z0=-0.6), notes="channel buoy, origin at the WATERLINE: hull z -0.6..0.33 "
       "(black below the waterline, white boot stripe), tint_a hull + tower, emis_always_white lamp at z 1.22..1.38, "
       "radar reflector on top (z 1.6)")
def prop_buoy(root):
    mb = K.MB()
    t = "tint_a"
    hull = [(0.0, -0.6), (0.22, -0.6), (0.38, -0.48), (0.48, -0.25), (0.5, -0.04), (0.5, 0.04), (0.5, 0.2),
            (0.46, 0.3), (0.28, 0.33), (0.0, 0.33)]
    P.lathe(mb, hull, t, segs=10, colors=["black", "black", "black", "black", "white", t, t, t, t])
    P.lathe(mb, [(0.5, 0.07), (0.535, 0.08), (0.535, 0.13), (0.5, 0.14)], "rubber", segs=10, cap0=False, cap1=False)
    S.limb(mb, [(0, 0, 0.3), (0, 0, 0.62), (0, 0, 0.7), (0, 0, 0.92), (0, 0, 1.0), (0, 0, 1.18)],
           [0.27, 0.23, 0.22, 0.19, 0.18, 0.16], t, segs=6, ring_colors=[t, "white", t, "white", t])
    mb.cyl(0.24, 0.04, (0, 0, 1.18), "charcoal", segs=10, base=True)                          # lamp platform
    mb.cyl(0.075, 0.16, (0, 0, 1.22), "emis_always_white", segs=8, base=True)               # lamp lens
    P.lathe(mb, [(0.09, 1.38), (0.09, 1.41), (0.03, 1.45), (0.0, 1.45)], "charcoal", segs=8, cap0=True)
    mb.cyl(0.012, 0.09, (0, 0, 1.45), "steel", segs=4, base=True)
    P.octa(mb, 0.075, (0, 0, 1.53), "steel", scale=(1, 1, 0.95), rot=(0, 0, 45))           # radar reflector
    mb.to_object(root, "mesh")


@asset("prop_dock_cleat", notes="galvanised mooring cleat 0.36 x 0.1 x 0.11, horns along X, origin at the base centre")
def prop_dock_cleat(root):
    mb = K.MB()
    g = "steel"
    mb.box((0.22, 0.09, 0.015), (0, 0, 0), POLE, base=True)
    for sx in (-0.055, 0.055):
        mb.box((0.05, 0.05, 0.065), (sx, 0, 0.012), g, base=True, taper=(0.75, 0.75))
    horn = [(-0.18, 0.075), (-0.12, 0.068), (0.0, 0.072), (0.12, 0.068), (0.18, 0.075), (0.15, 0.093), (0.06, 0.102),
            (-0.06, 0.102), (-0.15, 0.093)]
    mb.prism(horn, 0.05, g, plane="XZ")
    for sx in (-0.09, 0.09):
        mb.cyl(0.012, 0.008, (sx, 0, 0.015), "gray_dark", segs=6, base=True)
    mb.to_object(root, "mesh")


@asset("prop_pier_deck", col=box_col((4.0, 4.0, 0.25), (0, 0, -0.125)),
       notes="4 x 4 pier deck tile, TOP AT z = 0 (origin on the walking surface), deck 0.25 thick (planks across X on "
             "4 joists), pile caps + 4 piles (x, y = +-1.6) reaching z -4.75 with X braces; tidal band on the piles "
             "around z -1.15 (sea level 1.15 below the promenade)")
def prop_pier_deck(root):
    mb = K.MB()
    pg, wd = "plank_gray", "wood_dark"
    rnd = random.Random(4)
    n = 16
    for i in range(n):
        y = -2.0 + 4.0 * (i + 0.5) / n
        col = "beige" if rnd.random() < 0.18 else pg
        P.xbox(mb, (4.0, 4.0 / n - 0.022, 0.06), (0, y, -0.06), col, skip=("-z",), base=True)
    for x in (-1.5, -0.5, 0.5, 1.5):
        P.xbox(mb, (0.08, 4.0, 0.19), (x, 0, -0.25), wd, skip=("+y", "-y"), base=True)
    for y in (-1.6, 1.6):
        P.xbox(mb, (4.0, 0.22, 0.2), (0, y, -0.45), wd, base=True)
        P.beam(mb, (-1.6, y, -0.6), (1.6, y, -2.6), (0.12, 0.06), wd, up=(0, 1, 0))
        P.beam(mb, (1.6, y, -0.6), (-1.6, y, -2.6), (0.12, 0.06), wd, up=(0, 1, 0))
        for x in (-1.6, 1.6):
            S.limb(mb, [(x, y, -0.45), (x, y, -0.95), (x, y, -1.4), (x, y, -4.75)], [0.14, 0.14, 0.145, 0.15], wd,
                   segs=6, cap1=True, ring_colors=[wd, "moss", "mud"])
    mb.to_object(root, "mesh")


@asset("prop_pier_rail", notes="4 m wooden railing module, 1.1 high, along X: posts at x +-1.0 (2 m spacing when tiled), "
       "pickets every 0.4, rails run to x +-2.0; symmetric front / back")
def prop_pier_rail(root):
    mb = K.MB()
    pg, wd = "plank_gray", "wood_dark"
    for sx in (-1.0, 1.0):
        P.xbox(mb, (0.11, 0.11, 1.05), (sx, 0, 0), wd, skip=("-z", "+z"), base=True)
    mb.box((4.0, 0.16, 0.05), (0, 0, 1.05), pg, base=True)                                  # cap rail
    for z in (0.62, 0.22):
        P.xbox(mb, (4.0, 0.07, 0.09), (0, 0, z), pg, skip=("+x", "-x"))
    for i in range(10):
        x = -1.8 + 0.4 * i
        if abs(abs(x) - 1.0) < 0.01:
            continue
        P.xbox(mb, (0.05, 0.035, 0.81), (x, 0, 0.24), pg, skip=("-z", "+z"), base=True)
    mb.to_object(root, "mesh")


@asset("prop_dock_float", col=box_col((6.0, 2.0, 0.5), (0, 0, 0.1)), notes="6 x 2 floating dock section (long axis X), "
       "origin at the WATERLINE, deck top z 0.35, floats down to z -0.15; tiles end to end along X")
def prop_dock_float(root):
    mb = K.MB()
    mb.box((6.0, 1.84, 0.06), (0, 0, 0.29), "plank_gray", base=True)                        # deck
    for i in range(1, 12):
        x = -3.0 + 0.5 * i
        P.qz(mb, x - 0.01, x + 0.01, -0.92, 0.92, 0.354, "wood_dark")
    for s in (-1, 1):
        mb.box((6.0, 0.08, 0.28), (0, s * 0.96, 0.07), "wood_dark", base=True)               # walers
        mb.box((5.6, 0.05, 0.1), (0, s * 1.025, 0.13), "rubber", base=True)                   # fender strip
        P.xbox(mb, (0.08, 1.84, 0.28), (s * 2.96, 0, 0.07), "wood_dark", base=True, skip=(("-x",) if s > 0 else ("+x",)))
    for x in (-2.0, 0.0, 2.0):
        mb.box((1.8, 1.7, 0.3), (x, 0, -0.15), "gray_dark", base=True, bevel=0.03)          # float drums
    mb.to_object(root, "mesh")


@asset("prop_dock_ladder", col="none", notes="swim ladder hung on a dock edge: origin = top of the dock edge (y 0, "
       "z 0), dock toward -Y, rungs over the water at y 0.14 from z -0.25 to -1.75, grab rails 0.93 above the deck")
def prop_dock_ladder(root):
    mb = K.MB()
    for sx in (-0.24, 0.24):
        pts = [(sx, -0.32, 0.0), (sx, -0.32, 0.7), (sx, -0.25, 0.87), (sx, -0.08, 0.93), (sx, 0.07, 0.86),
               (sx, 0.13, 0.66), (sx, 0.13, -1.95)]
        S.limb(mb, pts, 0.022, "chrome", segs=5, cap1=True)
        mb.box((0.1, 0.1, 0.012), (sx, -0.32, 0.0), POLE, base=True)
        for z in (-0.12, -1.2):                                                               # wall stand-offs
            P.beam(mb, (sx, 0.12, z), (sx, 0.0, z), (0.035, 0.035), POLE, up=(0, 0, 1), skip=("-y",))
            mb.box((0.08, 0.012, 0.1), (sx, 0.006, z), POLE)
    for i in range(6):
        z = -0.25 - 0.3 * i
        P.xbox(mb, (0.44, 0.075, 0.025), (0, 0.14, z), "aluminum", skip=("+x", "-x"))
    mb.to_object(root, "mesh")


@asset("prop_kayak", dynamic=True, mass=22, notes="3.2 m sit-in kayak along X (bow toward +X), tint_a hull, black "
       "cockpit + coaming, deck bungees")
def prop_kayak(root):
    mb = K.MB()
    t = "tint_a"
    st = [(-1.45, 0.12, 0.25, 0.12, 0.29), (-1.05, 0.25, 0.21, 0.04, 0.28), (-0.5, 0.33, 0.19, 0.0, 0.27),
          (0.05, 0.34, 0.19, 0.0, 0.265), (0.6, 0.32, 0.19, 0.0, 0.27), (1.1, 0.23, 0.21, 0.04, 0.28),
          (1.45, 0.11, 0.25, 0.12, 0.29)]

    def ring(x, w, zs, zk, zt):
        zc = zk + (zs - zk) * 0.35
        return [(x, 0.0, zk), (x, w * 0.8, zc), (x, w, zs), (x, w * 0.55, zt - 0.012), (x, 0.0, zt),
                (x, -w * 0.55, zt - 0.012), (x, -w, zs), (x, -w * 0.8, zc)]

    rings = [ring(*s) for s in st]
    faces = mb.loft(rings, t, closed=True, cap_start=False, cap_end=False, fix_normals=False)
    for band in (2, 3):                                                                       # open cockpit
        mb.paint([faces[band * 8 + 3], faces[band * 8 + 4]], "black")
    stern, bow = V((-1.62, 0.0, 0.27)), V((1.63, 0.0, 0.29))
    r0, rn = rings[0], rings[-1]
    for k in range(8):
        k2 = (k + 1) % 8
        mb.poly([r0[k2], r0[k], stern], t)
        mb.poly([rn[k], rn[k2], bow], t)
    loop = _ellipse(0.05, 0.0, 0.282, 0.5, 0.205, 12)
    S.limb(mb, loop + [loop[0]], 0.02, "plastic_black", segs=4, cap1=False)                 # coaming
    for a, b in (((0.78, -0.13), (1.15, 0.11)), ((0.78, 0.13), (1.15, -0.11))):             # bungees
        P.ribbon(mb, (a[0], a[1], 0.284), (b[0], b[1], 0.284), 0.014, "black", normal=(0, 0, 1))
    P.fpoly(mb, _ellipse(-0.85, 0.0, 0.283, 0.1, 0.075, 8), "black", (0, 0, 1))             # rear hatch
    mb.to_object(root, "mesh")


# =========================================================================== airfield
@asset("prop_windsock", col=cyl_col(0.1, 6.0), notes="6 m windsock: `mesh` = red/white banded pole with a red "
       "obstruction light on top; `sock` = swivel collar + hoop + orange/white sock pointing +X, origin on the pole axis "
       "at z 5.86 - rotate the sock part about Z to follow the wind")
def prop_windsock(root):
    mb = K.MB()
    mb.box((0.6, 0.6, 0.15), (0, 0, 0), "concrete", base=True)
    mb.cyl(0.12, 0.04, (0, 0, 0.15), POLE, segs=8, base=True)
    pts = [(0, 0, 0.19 + i * 0.95) for i in range(7)]
    S.limb(mb, pts, [0.065, 0.06, 0.056, 0.052, 0.048, 0.045, 0.042], "white", segs=6, cap1=True,
           ring_colors=["red", "white", "red", "white", "red", "white"])
    P.lathe(mb, [(0.05, 5.89), (0.05, 5.92), (0.045, 5.96), (0.025, 5.99), (0.0, 6.0)], "emis_always_red", segs=6,
            colors=[POLE, "emis_always_red", "emis_always_red", "emis_always_red"], cap0=True)
    mb.to_object(root, "mesh")

    sk = K.MB()
    zp = 5.86
    sk.cyl(0.06, 0.08, (0, 0, zp - 0.12), "gray_dark", segs=8, base=True)                   # swivel collar
    S.limb(sk, [(0.05, 0, zp - 0.08), (0.3, 0, zp - 0.08)], 0.014, "gray_dark", segs=4)
    hoop = [(0.32, 0.3 * math.cos(2 * math.pi * k / 10), zp - 0.08 + 0.3 * math.sin(2 * math.pi * k / 10))
            for k in range(10)]
    S.limb(sk, hoop + [hoop[0]], 0.014, "gray_dark", segs=3, cap1=False)
    nb = 5
    rings = []
    for i in range(nb + 1):
        u = i / nb
        x = 0.32 + 2.4 * u
        r = 0.3 - 0.18 * u
        zc = zp - 0.08 - 0.32 * u ** 1.6
        rings.append([(x, r * math.cos(2 * math.pi * k / 8), zc + r * math.sin(2 * math.pi * k / 8)) for k in range(8)])
    cols = ["safety_orange", "white", "safety_orange", "white", "safety_orange"]
    sk.loft(rings, "safety_orange", closed=True, cap_start=False, cap_end=False, ring_colors=cols, fix_normals=False)
    sk.loft([list(reversed(r)) for r in rings], "safety_orange", closed=True, cap_start=False, cap_end=False,
            ring_colors=cols, fix_normals=False)                                             # inside of the cloth
    sk.to_object(root, "sock", origin=(0, 0, zp))


@asset("prop_runway_light", col="none", notes="0.25 m elevated runway edge light: frangible post + emis_always_white dome")
def prop_runway_light(root):
    mb = K.MB()
    g, e = "gray_dark", "emis_always_white"
    prof = [(0.11, 0.0), (0.11, 0.022), (0.035, 0.032), (0.03, 0.155), (0.07, 0.165), (0.072, 0.198), (0.064, 0.2),
            (0.058, 0.228), (0.034, 0.246), (0.0, 0.25)]
    P.lathe(mb, prof, g, segs=8, colors=[g, g, "hazard_yellow", g, g, g, e, e, e], cap0=False)
    mb.to_object(root, "mesh")


@asset("prop_helipad_light", col="none", notes="0.09 m flush-style helipad perimeter light, led_green dome")
def prop_helipad_light(root):
    mb = K.MB()
    c, e = "charcoal", "led_green"
    prof = [(0.12, 0.0), (0.12, 0.02), (0.09, 0.035), (0.075, 0.04), (0.07, 0.06), (0.045, 0.082), (0.0, 0.09)]
    P.lathe(mb, prof, c, segs=8, colors=[c, c, c, e, e, e], cap0=False)
    mb.to_object(root, "mesh")


# =========================================================================== registry of this module
IDS = ["prop_umbrella", "prop_beach_chair", "prop_towel", "prop_surfboard", "prop_volleyball_net",
       "prop_lifebuoy_stand", "prop_lifeguard_tower", "prop_buoy", "prop_dock_cleat", "prop_pier_deck",
       "prop_pier_rail", "prop_dock_float", "prop_dock_ladder", "prop_kayak", "prop_windsock", "prop_runway_light",
       "prop_helipad_light"]

ROW_Y = K.CATEGORIES["StreetProps"][1]
X0 = 230.0
SHEETS = [
    ("beach_small", ["prop_umbrella", "prop_beach_chair", "prop_towel", "prop_surfboard", "prop_lifebuoy_stand",
                     "prop_dock_cleat", "prop_runway_light", "prop_helipad_light"], 2.6, 2.6, 4),
    ("beach_mid", ["prop_kayak", "prop_buoy", "prop_dock_ladder", "prop_pier_rail", "prop_windsock",
                   "prop_dock_float"], 6.5, 4.0, 3),
    ("beach_big", ["prop_pier_deck", "prop_lifeguard_tower", "prop_volleyball_net"], 12.0, 8.0, 3),
]


def do_layout():
    return P.layout(SHEETS, ROW_Y, X0)
