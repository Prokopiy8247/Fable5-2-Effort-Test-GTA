"""props_nature - P1 nature for NEON TIDE (SPEC_PROPS_NATURE.md): trees, palms, bushes, hedge, rocks,
grass / flowers / reeds / fern, log, stump, driftwood.   Category `Nature`, GLB path `nature/<id>`.

    import props_common as P, props_shapes as S, props_nature as M
    print(S.run(M.IDS)); M.do_layout()

Conventions of this module
  * every tree is ONE mesh part `mesh` (MultiMesh instancing); trunk / branches use the Palette material,
    everything that should sway uses "@F:<palette>" (material `Foliage`);
  * trunks continue ~0.35 m below z = 0 and rocks ~18 % of their height, so they stay closed on sloped ground;
  * colliders: trunk cylinder for trees, a tightened box for rocks (manifest `col`).
"""
import math
import random

from mathutils import Vector, Matrix

import gta_kit as K
import props_common as P
import props_shapes as S
from props_common import asset, cyl_col, box_col

NAT = {"category": "Nature", "folder": "nature"}
V = Vector
LG, LD, LL = "@F:leaf_green", "@F:leaf_dark", "@F:leaf_light"


# =========================================================================== broadleaf trees
@asset("tree_oak_a", col=cyl_col(0.34, 4.4), notes="h 9 m, crown about 6.5 m; trunk plug to z -0.35", **NAT)
def tree_oak_a(root):
    mb = K.MB()
    b, bd = "bark", "bark_dark"
    S.limb(mb, [(0, 0, -0.35), (0, 0, 0.06), (0.04, 0.01, 0.6), (0.16, 0.03, 1.75), (0.30, 0.05, 2.9),
                (0.36, 0.04, 3.75)], [0.62, 0.5, 0.36, 0.31, 0.28, 0.24], b, segs=7,
           ring_colors=[bd, bd, b, b, b])
    S.limb(mb, [(0.36, 0.04, 3.55), (0.95, 0.2, 4.5), (1.5, 0.3, 5.2)], [0.2, 0.15, 0.1], b, segs=5)
    S.limb(mb, [(0.34, 0.04, 3.55), (-0.25, -0.12, 4.6), (-0.95, -0.3, 5.5)], [0.2, 0.15, 0.1], b, segs=5)
    S.limb(mb, [(0.36, 0.04, 3.65), (0.3, 0.15, 4.9), (0.2, 0.1, 6.0)], [0.19, 0.14, 0.09], b, segs=5)
    S.limb(mb, [(0.2, 0.03, 2.3), (-0.3, 0.22, 2.85), (-0.52, 0.34, 3.0)], [0.12, 0.1, 0.09], bd, segs=5,
           cap_color="wood_light")                                                        # sawn-off stub
    S.limb(mb, [(0.3, 0.02, 2.95), (0.62, -0.38, 3.9), (0.7, -0.5, 4.9)], [0.12, 0.09, 0.06], bd, segs=5)
    S.canopy(mb, [
        {"r": 2.25, "pos": (0.25, 0.1, 6.15), "scale": (1.12, 1.05, 0.86), "seed": 11},
        {"r": 1.7, "pos": (1.6, 0.35, 5.3), "scale": (1.05, 1.0, 0.84), "seed": 12},
        {"r": 1.8, "pos": (-1.15, -0.4, 5.55), "scale": (1.0, 1.05, 0.85), "seed": 13},
        {"r": 1.5, "pos": (-0.1, 0.3, 7.6), "scale": (1.1, 1.05, 0.86), "seed": 14},
    ], color=LG, dark=LD, speckle=0.12)
    S.fit_height(mb, 9.0)
    mb.to_object(root, "mesh")


@asset("tree_oak_b", col=cyl_col(0.42, 4.0), notes="h 11 m, crown about 7.5 m, forked trunk; plug to z -0.4", **NAT)
def tree_oak_b(root):
    mb = K.MB()
    b, bd = "bark", "bark_dark"
    S.limb(mb, [(0, 0, -0.4), (0, 0, 0.08), (-0.03, 0, 0.7), (-0.1, 0.02, 1.9), (-0.12, 0.04, 2.95)],
           [0.75, 0.6, 0.44, 0.4, 0.37], b, segs=7, ring_colors=[bd, bd, b, b])
    S.limb(mb, [(-0.14, 0.04, 2.7), (-0.75, 0.0, 4.2), (-1.15, 0.0, 5.8), (-1.05, 0.05, 7.2)],
           [0.31, 0.27, 0.2, 0.13], b, segs=6)
    S.limb(mb, [(-0.08, 0.04, 2.7), (0.7, 0.15, 3.9), (1.4, 0.3, 5.3), (1.55, 0.3, 6.4)],
           [0.3, 0.25, 0.18, 0.11], b, segs=6)
    S.limb(mb, [(-0.75, 0.0, 4.1), (-1.75, -0.2, 4.9), (-2.3, -0.3, 5.6)], [0.16, 0.12, 0.08], b, segs=5)
    S.limb(mb, [(0.7, 0.15, 3.8), (0.75, -0.8, 4.7), (0.62, -1.3, 5.4)], [0.15, 0.11, 0.08], b, segs=5)
    S.limb(mb, [(-0.1, 0.02, 1.85), (0.5, 0.35, 2.4), (0.75, 0.5, 2.5)], [0.14, 0.12, 0.11], bd, segs=5,
           cap_color="wood_light")
    S.canopy(mb, [
        {"r": 2.3, "pos": (-0.95, 0.0, 7.5), "scale": (1.1, 1.0, 0.88), "seed": 21},
        {"r": 2.0, "pos": (1.45, 0.3, 6.75), "scale": (1.1, 1.05, 0.85), "seed": 22},
        {"r": 1.8, "pos": (-0.4, 0.25, 9.5), "scale": (1.1, 1.1, 0.85), "seed": 23},
        {"r": 1.4, "pos": (-2.4, -0.3, 5.9), "scale": (1.05, 1.0, 0.8), "seed": 24},
        {"r": 1.45, "pos": (0.62, -1.5, 5.75), "scale": (1.05, 1.0, 0.8), "seed": 25},
    ], color=LG, dark=LD, light=LL, speckle=0.1)
    S.fit_height(mb, 11.0)
    mb.to_object(root, "mesh")


@asset("tree_round", col=cyl_col(0.16, 3.0), notes="tidy street tree, h 6 m, crown 3.2 m; plug to z -0.3", **NAT)
def tree_round(root):
    mb = K.MB()
    b = "bark"
    S.limb(mb, [(0, 0, -0.3), (0, 0, 0.05), (0.0, 0, 1.3), (0.02, 0, 2.6), (0.02, 0, 3.4)],
           [0.22, 0.17, 0.125, 0.11, 0.08], b, segs=6, ring_colors=["bark_dark", b, b, b])
    S.limb(mb, [(0.02, 0, 2.3), (0.42, 0.2, 2.95), (0.62, 0.3, 3.5)], [0.07, 0.055, 0.04], b, segs=4)
    S.limb(mb, [(0.0, 0, 2.45), (-0.36, -0.25, 3.05), (-0.5, -0.4, 3.55)], [0.07, 0.055, 0.04], b, segs=4)
    S.canopy(mb, [
        {"r": 1.56, "pos": (0, 0, 4.3), "scale": (1.02, 1.02, 0.98), "seed": 31},
        {"r": 1.12, "pos": (0.12, -0.08, 5.02), "scale": (1.0, 1.0, 0.9), "seed": 32},
    ], color=LG, dark=LD, light=LL, speckle=0.05, jitter=0.11)
    S.fit_height(mb, 6.0)
    mb.to_object(root, "mesh")


# =========================================================================== pines
def _pine(mb, h, tiers, r0, z0, trunk_r, seed, shrink=0.78, light_p=0.2):
    rnd = random.Random(seed)
    S.limb(mb, [(0, 0, -0.35), (0, 0, 0.05), (0, 0, z0 * 0.55), (0, 0, z0 + (h - z0) * 0.3)],
           [trunk_r * 1.6, trunk_r * 1.25, trunk_r, trunk_r * 0.7], "bark_dark", segs=6, cap1=False,
           ring_colors=["bark_dark", "bark", "bark"])
    span = h - z0
    step = span / tiers
    for i in range(tiers):
        zb = z0 + step * i
        R = r0 * (1.0 - shrink * i / tiers)
        last = i == tiers - 1
        zt = h if last else zb + step * 1.5
        rt = R * 0.3
        ph = math.radians(30.0 * (i % 2)) + rnd.uniform(-0.2, 0.2)
        rim, top = [], []
        for k in range(6):
            a = ph + math.radians(60.0 * k) + rnd.uniform(-0.1, 0.1)
            out = k % 2 == 0
            rr = R * (1.08 if out else 0.9) * rnd.uniform(0.95, 1.05)
            zz = zb + R * (-0.11 if out else 0.07) + rnd.uniform(-0.04, 0.04)
            rim.append(V((math.cos(a) * rr, math.sin(a) * rr, zz)))
            top.append(V((math.cos(a) * rt, math.sin(a) * rt, zt)))
        hub = V((0, 0, zb + (zt - zb) * 0.2))
        apex = V((rnd.uniform(-0.05, 0.05), rnd.uniform(-0.05, 0.05), zt))
        for k in range(6):
            k2 = (k + 1) % 6
            c = LG if rnd.random() < light_p else LD
            if last:
                mb.poly([rim[k], rim[k2], apex], c)
            else:
                mb.poly([rim[k], rim[k2], top[k]], c)
                mb.poly([rim[k2], top[k2], top[k]], c)
            P.fpoly(mb, [rim[k2], rim[k], hub], LD, (0, 0, -1))


@asset("tree_pine_a", col=cyl_col(0.26, 3.2), notes="h 12 m, 5 hexagonal tiers; trunk plug to z -0.35", **NAT)
def tree_pine_a(root):
    mb = K.MB()
    _pine(mb, 12.0, 5, 2.45, 2.3, 0.24, seed=41)
    mb.to_object(root, "mesh")


@asset("tree_pine_b", col=cyl_col(0.2, 2.2), notes="h 8 m, 4 hexagonal tiers; trunk plug to z -0.35", **NAT)
def tree_pine_b(root):
    mb = K.MB()
    _pine(mb, 8.0, 4, 1.95, 1.5, 0.185, seed=47, shrink=0.74)
    mb.to_object(root, "mesh")


# =========================================================================== palms
def _palm(mb, h, path, nseg, r0, r1, fronds, seed, nuts=3):
    """path(t) -> trunk centre line; fronds: [(azimuth_deg, elev_deg, length, droop, top_colour)]"""
    rnd = random.Random(seed)
    pp, bk = "bark_palm", "bark"
    p0 = path(0.0)
    length = sum((path((i + 1) / 24.0) - path(i / 24.0)).length for i in range(24))
    eps = 0.05 / length
    pts = [p0 + V((0, 0, -0.35)), p0.copy()]
    rad = [r0 * 1.2, r0 * 1.14]
    cols = [bk]
    for k in range(nseg):
        tb = (k + 1) / nseg
        rb = r0 + (r1 - r0) * tb
        pts.append(path(tb - eps))                    # wide rim of this segment
        rad.append(rb * 1.13)
        cols.append(pp)
        if k < nseg - 1:
            pts.append(path(tb))                      # narrow start of the next one
            rad.append(rb * 0.9)
            cols.append(bk)
    S.limb(mb, pts, rad, pp, segs=6, cap1=True, ring_colors=cols)
    # crown frame: local Z along the end of the trunk
    c = path(1.0)
    t = (c - path(0.96)).normalized()
    x = t.cross(V((0, 1, 0)))
    if x.length < 1e-4:
        x = V((1, 0, 0))
    x.normalize()
    y = t.cross(x).normalized()
    m = Matrix(((x.x, y.x, t.x, c.x), (x.y, y.y, t.y, c.y), (x.z, y.z, t.z, c.z), (0, 0, 0, 1)))
    mb.stack.append(mb.stack[-1] @ m)
    try:
        mb.ico(0.34, (0, 0, 0.1), "leaf_dark", subdiv=1, scale=(1, 1, 0.9), jitter=0.06, seed=seed)
        for i in range(nuts):
            a = math.radians(25 + 360.0 * i / nuts + rnd.uniform(-20, 20))
            mb.ico(rnd.uniform(0.13, 0.16), (math.cos(a) * 0.27, math.sin(a) * 0.27, -0.2 + rnd.uniform(-0.05, 0.03)),
                   "brown", subdiv=1, seed=i)
        for az, el, ln, droop, col in fronds:
            a = math.radians(az)
            base = (math.cos(a) * 0.12, math.sin(a) * 0.12, 0.16)
            spine, lat = S.arc_spine(base, a, math.radians(el), ln, droop, nseg=4)
            w = ln * 0.3
            S.frond(mb, spine, [w * 0.22, w, w * 0.92, w * 0.58, 0.0], lat, top=col, bot=LD, fold=0.28)
    finally:
        mb.stack.pop()
    S.fit_height(mb, h)


def _frond_set(rnd, n, lmax, start=0.0):
    """Phyllotaxis: frond i sits 137.5 deg further round and lower than the previous one (0 = young spear leaf,
    n - 1 = oldest frond hanging down along the trunk)."""
    out = []
    for i in range(n):
        u = i / (n - 1.0)
        az = start + 137.5 * i + rnd.uniform(-9, 9)
        el = 80.0 + (-24.0 - 80.0) * (u ** 0.9) + rnd.uniform(-4, 4)
        k = min(1.0, u / 0.38)
        ln = lmax * (0.58 + 0.42 * k * k * (3 - 2 * k)) * rnd.uniform(0.95, 1.05)
        droop = 0.85 + 0.65 * u
        col = LL if i == 0 else ("@F:palm_green" if i % 2 else LG)
        out.append((az, el, ln, droop, col))
    return out


@asset("tree_palm_a", col=cyl_col(0.45, 1.9, x=0.33), notes="h 9 m, trunk leans 1.5 m toward +X (crown centre at "
       "x 1.4); collider = offset cylinder around the lower 1.9 m of the leaning trunk; 11 fronds, crown about 6 m; "
       "fronds = Foliage, trunk / crown core / coconuts = Palette; plug to z -0.35", **NAT)
def tree_palm_a(root):
    mb = K.MB()
    rnd = random.Random(61)

    def path(t):
        return V((1.5 * (2 * t - t * t), 0.25 * t * t, 7.1 * t))
    _palm(mb, 9.0, path, 7, 0.27, 0.165, _frond_set(rnd, 11, 3.6, start=20.0), seed=61)
    mb.to_object(root, "mesh")


@asset("tree_palm_b", col=cyl_col(0.36, 1.9, x=-0.1, y=0.08), notes="h 6.5 m, wind-bent toward -X (crown centre "
       "at x -1.1); collider = offset cylinder around the lower 1.9 m of the trunk; 9 fronds, crown about 5 m; plug to "
       "z -0.35", **NAT)
def tree_palm_b(root):
    mb = K.MB()
    rnd = random.Random(67)

    def path(t):
        return V((-(0.15 * t + 0.95 * t * t), 0.18 * math.sin(math.pi * t), 4.95 * t))
    _palm(mb, 6.5, path, 5, 0.245, 0.155, _frond_set(rnd, 9, 3.0, start=75.0), seed=67, nuts=4)
    mb.to_object(root, "mesh")


# =========================================================================== dead tree
@asset("tree_dead", col=cyl_col(0.22, 3.0), notes="bare branching tree, h 6 m; trunk plug to z -0.3", **NAT)
def tree_dead(root):
    mb = K.MB()
    bd, b, g = "bark_dark", "bark", "plank_gray"
    S.limb(mb, [(0, 0, -0.3), (0, 0, 0.05), (0.05, 0, 0.9), (0.12, 0.03, 2.0), (0.05, 0.0, 3.1), (0.15, -0.05, 4.1),
                (0.05, 0.02, 5.2), (0.2, 0.05, 6.0)], [0.36, 0.29, 0.2, 0.17, 0.14, 0.1, 0.06, 0.0], bd, segs=6,
           tip=True, ring_colors=[bd, bd, bd, b, b, b, g])
    S.limb(mb, [(0.1, 0.02, 1.8), (0.9, 0.2, 2.6), (1.5, 0.25, 3.6), (1.7, 0.1, 4.5)], [0.11, 0.1, 0.065, 0], b,
           segs=5, tip=True, ring_colors=[b, b, g])
    S.limb(mb, [(0.9, 0.2, 2.55), (1.4, 0.6, 2.9), (1.9, 0.9, 3.5)], [0.06, 0.05, 0], g, segs=4, tip=True)
    S.limb(mb, [(0.08, 0, 2.7), (-0.7, -0.3, 3.5), (-1.3, -0.35, 4.5), (-1.4, -0.6, 5.3)], [0.1, 0.09, 0.055, 0], b,
           segs=5, tip=True, ring_colors=[b, b, g])
    S.limb(mb, [(-0.7, -0.3, 3.45), (-1.2, -0.9, 3.8), (-1.7, -1.2, 4.4)], [0.055, 0.045, 0], g, segs=4, tip=True)
    S.limb(mb, [(0.1, -0.03, 3.6), (0.5, -0.6, 4.3), (0.9, -1.1, 5.2)], [0.075, 0.065, 0], b, segs=4, tip=True,
           ring_colors=[b, g])
    S.limb(mb, [(0.12, -0.02, 4.3), (-0.3, 0.5, 4.9), (-0.5, 0.9, 5.6)], [0.06, 0.05, 0], g, segs=4, tip=True)
    S.limb(mb, [(0.05, 0, 1.15), (-0.4, 0.28, 1.5), (-0.52, 0.36, 1.56)], [0.09, 0.08, 0.07], bd, segs=5,
           cap_color="wood_light")                                                        # snapped stub
    S.fit_height(mb, 6.0)
    mb.to_object(root, "mesh")


# =========================================================================== bushes, hedge
def _bush(mb, blobs, jitter, size):
    faces = S.canopy(mb, blobs, color=LG, dark=LD, light=LL, speckle=0.1, jitter=jitter, floor=-0.2)
    lo, hi = S.bbox(mb)
    s = size / max(hi.x - lo.x, hi.y - lo.y)
    for v in mb.bm.verts:
        v.co *= s
    S.recenter_xy(mb)
    return faces


@asset("bush_a", col="none", notes="blob bush 1.6 m, reaches 0.2 m below z = 0", **NAT)
def bush_a(root):
    mb = K.MB()
    _bush(mb, [
        {"r": 0.64, "pos": (0.0, 0.0, 0.42), "scale": (1.12, 1.0, 0.95), "seed": 71},
        {"r": 0.47, "pos": (0.4, 0.2, 0.3), "scale": (1.0, 1.0, 0.95), "seed": 72},
        {"r": 0.44, "pos": (-0.38, -0.2, 0.28), "scale": (1.05, 1.0, 0.95), "seed": 73},
    ], 0.16, 1.6)
    mb.to_object(root, "mesh")


@asset("bush_b", col="none", notes="flowering bush 1.6 m (flower heads sway with the foliage)", **NAT)
def bush_b(root):
    mb = K.MB()
    faces = _bush(mb, [
        {"r": 0.58, "pos": (0.08, 0.05, 0.34), "scale": (1.2, 1.05, 0.88), "seed": 75},
        {"r": 0.45, "pos": (-0.4, 0.15, 0.28), "scale": (1.1, 1.0, 0.92), "seed": 76},
        {"r": 0.4, "pos": (0.3, -0.35, 0.25), "scale": (1.0, 1.1, 0.92), "seed": 77},
    ], 0.12, 1.6)
    rnd = random.Random(9)
    cand = []
    for f in faces:
        f.normal_update()
        if f.normal.z > 0.25 and f.calc_center_median().z > 0.3:
            cand.append((f.calc_center_median(), f.normal.copy()))
    rnd.shuffle(cand)
    chosen = []
    for c, n in cand:
        if all((c - d).length > 0.33 for d, _n in chosen):
            chosen.append((c, n))
        if len(chosen) >= 10:
            break
    cols = ["@F:flower_red", "@F:flower_white", "@F:flower_red", "@F:flower_yellow"]
    for i, (c, n) in enumerate(chosen):
        P.octa(mb, 0.07 if i % 3 else 0.085, c + n * 0.035, cols[i % len(cols)], scale=(1, 1, 0.75))
    mb.to_object(root, "mesh")


@asset("hedge", notes="clipped box hedge; tiles end to end along X (both end profiles are identical)", **NAT)
def hedge(root):
    mb = K.MB()
    L, W, H = 2.0, 0.8, 1.2
    nx, ny, nz = 5, 2, 3
    zl = [0.0, 0.28, 0.72, 1.0]
    taper = [0.93, 1.0, 1.0, 0.88]
    rnd = random.Random(12)
    jit = {}
    for i in range(nx):
        for j in range(ny + 1):
            for k in range(nz + 1):
                dx = rnd.uniform(-0.06, 0.06) if i > 0 else 0.0
                dy = rnd.uniform(-0.045, 0.045) if k > 0 else 0.0
                dz = (rnd.uniform(-0.06, 0.05) if k == nz else rnd.uniform(-0.04, 0.04)) if k > 0 else 0.0
                jit[(i, j, k)] = (dx, dy, dz)
    vm = {}

    def vert(i, j, k):
        key = (i, j, k)
        v = vm.get(key)
        if v is None:
            dx, dy, dz = jit[(i % nx, j, k)]
            v = mb.bm.verts.new(V(((i / nx - 0.5) * L + dx, (j / ny - 0.5) * W * taper[k] + dy, zl[k] * H + dz)))
            vm[key] = v
        return v

    def face(vs, color):
        f = mb.bm.faces.new(vs)
        mb.paint([f], color)

    for i in range(nx):
        for j in range(ny):
            face([vert(i, j, nz), vert(i + 1, j, nz), vert(i + 1, j + 1, nz), vert(i, j + 1, nz)],
                 LL if rnd.random() < 0.4 else LG)
        for k in range(nz):
            cs = LD if (k == 0 or rnd.random() < 0.18) else LG
            face([vert(i, 0, k), vert(i + 1, 0, k), vert(i + 1, 0, k + 1), vert(i, 0, k + 1)], cs)
            cs = LD if (k == 0 or rnd.random() < 0.18) else LG
            face([vert(i + 1, ny, k), vert(i, ny, k), vert(i, ny, k + 1), vert(i + 1, ny, k + 1)], cs)
    for j in range(ny):
        for k in range(nz):
            cs = LD if k == 0 else LG
            face([vert(0, j + 1, k), vert(0, j, k), vert(0, j, k + 1), vert(0, j + 1, k + 1)], cs)
            face([vert(nx, j, k), vert(nx, j + 1, k), vert(nx, j + 1, k + 1), vert(nx, j, k + 1)], cs)
    S.fit_box(mb, (0, W, H))
    mb.to_object(root, "mesh")


# =========================================================================== rocks
def _rocks(mb, chunks, nominal, sink=0.18, speckle=0.14):
    """chunks: (pos, rx, ry, h, seed, n, top, tilt, rot) crags; each starts h * sink below its pos.
    Returns the tightened collider box."""
    for pos, rx, ry, h, seed, n, top, tilt, rot in chunks:
        _crag(mb, (pos[0], pos[1], pos[2] - h * sink), rx, ry, h, seed, n=n, top=top, tilt=tilt, rot=rot,
              speckle=speckle)
    lo, hi = S.bbox(mb)
    s = nominal / max(hi.x - lo.x, hi.y - lo.y)
    for v in mb.bm.verts:
        v.co *= s
    S.recenter_xy(mb)
    lo, hi = S.bbox(mb)
    return {"col": box_col(((hi.x - lo.x) * 0.84, (hi.y - lo.y) * 0.84, hi.z * 0.94), (0, 0, hi.z * 0.47))}


@asset("rock_a", notes="about 1 m boulder; sits 0.15 m into the ground", **NAT)
def rock_a(root):
    mb = K.MB()
    out = _rocks(mb, [((0, 0, 0), 0.52, 0.43, 0.86, 5, 6, 0.62, (0.14, 0.06), None)], 1.05)
    mb.to_object(root, "mesh")
    return out


@asset("rock_b", notes="about 2 m boulder group; sits 0.25 m into the ground", **NAT)
def rock_b(root):
    mb = K.MB()
    out = _rocks(mb, [((0, 0, 0), 0.95, 0.78, 1.6, 12, 7, 0.6, (-0.12, 0.07), (0, 0, 20)),
                      ((0.82, -0.5, 0), 0.56, 0.5, 0.98, 4, 6, 0.6, (0.1, -0.1), (0, 0, 50)),
                      ((-0.78, 0.5, 0), 0.4, 0.36, 0.62, 7, 5, 0.6, (0.0, 0.12), None)], 2.1)
    mb.to_object(root, "mesh")
    return out


@asset("rock_c", notes="flat 2.5 m slab (walkable top about 0.55 m); sits 0.12 m into the ground", **NAT)
def rock_c(root):
    mb = K.MB()
    out = _rocks(mb, [((0, 0, 0), 1.25, 0.95, 0.64, 9, 8, 0.86, (0.03, -0.03), None),
                      ((-1.0, 0.8, 0), 0.45, 0.38, 0.5, 3, 5, 0.66, (0.1, 0.0), (0, 0, 35))], 2.5, sink=0.2)
    mb.to_object(root, "mesh")
    return out


def _crag(mb, pos, rx, ry, h, seed, n=7, top=0.78, tilt=(0.0, 0.0), rot=None, speckle=0.14):
    """Blocky faceted crag: convex hull of a base ring, a bulging mid ring and a smaller tilted top ring."""
    rnd = random.Random(seed)
    pts = []
    for ring, (zf, rf) in enumerate(((0.0, 1.0), (0.5, 1.04), (1.0, top))):
        for k in range(n):
            a = 2.0 * math.pi * (k + 0.5 * (ring % 2)) / n + rnd.uniform(-0.18, 0.18)
            r = rf * rnd.uniform(0.84, 1.06)
            x, y = math.cos(a) * rx * r, math.sin(a) * ry * r
            z = zf * h
            if ring == 2:
                z += tilt[0] * x + tilt[1] * y + rnd.uniform(-0.05, 0.05) * h
            elif ring == 1:
                z += rnd.uniform(-0.14, 0.14) * h
            pts.append((x, y, z))
    return P.rock(mb, (1, 1, 1), pos, seed=seed, color="rock", dark="rock_dark", light="rock_light", rot=rot,
                  cut=0.0, points=pts, speckle=speckle)


@asset("rock_cliff", col="mesh", notes="8 x 4 x 5 outcrop (plus 0.8 m below z = 0 for sloped ground); steep face "
       "toward +Y; the mesh itself is the collider (spawn through PropFactory, Scatter ignores col 'mesh')", **NAT)
def rock_cliff(root):
    mb = K.MB()
    # stepped stack of blocky crags: every block stands inside the footprint of the one below
    _crag(mb, (0.0, -0.2, -0.8), 3.95, 1.9, 3.0, 31, n=9, top=0.86, tilt=(0.03, -0.05))
    _crag(mb, (-1.5, -0.35, 1.3), 2.35, 1.55, 2.7, 32, n=8, top=0.8, tilt=(-0.06, 0.04))
    _crag(mb, (-2.0, -0.55, 3.3), 1.35, 1.05, 1.75, 33, n=7, top=0.7, tilt=(0.1, 0.0))
    _crag(mb, (2.05, -0.15, 1.2), 1.8, 1.45, 2.2, 34, n=7, top=0.76, tilt=(0.08, 0.05))
    _crag(mb, (0.9, 1.05, -0.8), 1.7, 0.95, 1.9, 35, n=7, top=0.8, tilt=(0.0, 0.08))
    _crag(mb, (-3.05, 0.75, -0.8), 0.95, 0.9, 2.5, 36, n=6, top=0.72, tilt=(-0.1, 0.1))
    _crag(mb, (3.2, 0.9, -0.8), 0.8, 0.75, 1.5, 37, n=6, top=0.7)
    S.fit_box(mb, (8.0, 4.0, 5.8), zmin=-0.8)
    rnd = random.Random(3)

    def moss(f):
        if f.normal.z > 0.86 and rnd.random() < 0.4:
            return "moss"
        return None
    S.repaint(mb, list(mb.bm.faces), moss)
    mb.to_object(root, "mesh")


# =========================================================================== ground cover
def _blades(mb, rnd, n, height, spread, width, cols, bent=0, r_base=0.05, lean=0.45):
    """n tapered blades radiating from the origin; the first `bent` ones get a drooping mid joint."""
    for i in range(n):
        a = 2.0 * math.pi * i / n + rnd.uniform(-0.3, 0.3)
        d = V((math.cos(a), math.sin(a), 0.0))
        s = V((-d.y, d.x, 0.0))
        hgt = height * (1.0 if i == 0 else rnd.uniform(0.62, 0.95))
        r0 = rnd.uniform(0.2, 1.0) * r_base
        out = spread * rnd.uniform(0.5, 1.0)
        base = d * r0 + V((0, 0, -0.02))
        col = cols[i % len(cols)]
        if i < bent:
            mid = d * (r0 + out * 0.55) + V((0, 0, hgt * 0.72))
            tip = d * (r0 + out * (1.0 + lean)) + V((0, 0, hgt * 0.98))
            P.blade(mb, base, tip, width, col, normal=s, mid=mid, mid_w=width * 0.7)
        else:
            tip = d * (r0 + out * 0.6) + V((0, 0, hgt))
            P.blade(mb, base, tip, width, col, normal=s)


@asset("grass_tuft", col="none", notes="0.35 m tuft, 24 tris", **NAT)
def grass_tuft(root):
    mb = K.MB()
    _blades(mb, random.Random(5), 8, 0.35, 0.16, 0.065, ["@F:grass", "@F:grass_dark"], bent=2)
    mb.to_object(root, "mesh")


@asset("grass_tall", col="none", notes="0.8 m tuft, 32 tris", **NAT)
def grass_tall(root):
    mb = K.MB()
    _blades(mb, random.Random(8), 8, 0.8, 0.26, 0.085, ["@F:grass", "@F:grass_dry", "@F:grass_dark", "@F:grass"],
            bent=4, r_base=0.07)
    mb.to_object(root, "mesh")


@asset("flower_patch", col="none", notes="0.6 m patch, 6 flower heads on the Foliage material", **NAT)
def flower_patch(root):
    mb = K.MB()
    rnd = random.Random(21)
    _blades(mb, rnd, 7, 0.24, 0.22, 0.11, [LG, LD, "@F:grass"], bent=7, r_base=0.08, lean=0.3)
    heads = ["@F:flower_red", "@F:flower_yellow", "@F:flower_white", "@F:flower_purple", "@F:flower_yellow",
             "@F:flower_red"]
    for i in range(6):
        a = 2.0 * math.pi * i / 6 + rnd.uniform(-0.35, 0.35) + 0.5
        r = rnd.uniform(0.05, 0.2)
        hgt = rnd.uniform(0.27, 0.43)
        base = V((math.cos(a) * r * 0.5, math.sin(a) * r * 0.5, -0.02))
        tip = V((math.cos(a) * r, math.sin(a) * r, hgt))
        P.blade(mb, base, tip + V((0, 0, 0.02)), 0.022, "@F:grass_dark", normal=(-math.sin(a), math.cos(a), 0))
        P.octa(mb, 0.055, tip + V((0, 0, 0.03)), heads[i], scale=(1, 1, 0.62), rot=(rnd.uniform(-20, 20), rnd.uniform(-20, 20), rnd.uniform(0, 90)))
    mb.to_object(root, "mesh")


@asset("reeds", col="none", notes="1.4 m waterside reeds with 3 cattails", **NAT)
def reeds(root):
    mb = K.MB()
    rnd = random.Random(33)
    cols = ["@F:grass_dark", "@F:grass", "@F:grass_dark", "@F:grass_dry"]
    spots = [(0.0, 0.0), (0.2, 0.1), (-0.18, 0.12), (0.08, -0.2), (-0.12, -0.14)]
    k = 0
    for cx, cy in spots:
        for _i in range(2):
            a = rnd.uniform(0, 2 * math.pi)
            d = V((math.cos(a), math.sin(a), 0))
            hgt = 1.4 if k == 0 else rnd.uniform(0.85, 1.32)
            base = V((cx, cy, -0.03)) + d * 0.03
            mid = base + d * rnd.uniform(0.04, 0.1) + V((0, 0, hgt * 0.62))
            tip = base + d * rnd.uniform(0.14, 0.34) + V((0, 0, hgt))
            P.blade(mb, base, tip, 0.06, cols[k % 4], normal=(-d.y, d.x, 0), mid=mid, mid_w=0.045)
            k += 1
    for cx, cy, hgt in ((0.06, 0.05, 1.22), (-0.1, 0.0, 1.05), (0.12, -0.1, 0.92)):
        lean = V((rnd.uniform(-0.06, 0.06), rnd.uniform(-0.06, 0.06), 0))
        top = V((cx, cy, hgt)) + lean
        P.blade(mb, (cx, cy, -0.03), top, 0.03, "@F:grass_dark", normal=(1, 0, 0))
        P.blade(mb, (cx, cy, -0.03), top, 0.03, "@F:grass_dark", normal=(0, 1, 0))
        S.limb(mb, [top - V((0, 0, 0.2)), top + V((0, 0, 0.01))], [0.034, 0.038], "@F:bark_dark", segs=4,
               cap0=True, cap1=True)
        P.blade(mb, top, top + V((0, 0, 0.14)), 0.014, "@F:grass_dry", normal=(1, 0, 0))
    mb.to_object(root, "mesh")


@asset("fern", col="none", notes="0.5 m high fern, about 1.1 m across, 7 folded fronds", **NAT)
def fern(root):
    mb = K.MB()
    rnd = random.Random(14)
    n = 7
    for i in range(n):
        a = 2.0 * math.pi * i / n + rnd.uniform(-0.2, 0.2)
        ln = rnd.uniform(0.74, 0.92)
        el = math.radians(rnd.uniform(66, 80))
        base = (math.cos(a) * 0.04, math.sin(a) * 0.04, -0.02)
        spine, lat = S.arc_spine(base, a, el, ln, 1.3, nseg=3)
        w = ln * 0.36
        S.frond(mb, spine, [w * 0.4, w, w * 0.66, 0.0], lat, top=LG if i % 2 else LL, bot=LD, fold=0.22)
    mb.to_object(root, "mesh")


# =========================================================================== dead wood
@asset("log", col=box_col((3.0, 0.58, 0.54), (0, 0, 0.27)), notes="3 m fallen trunk along X", **NAT)
def log(root):
    mb = K.MB()
    b, bd = "bark", "bark_dark"
    faces = S.limb(mb, [(-1.5, 0.0, 0.27), (-0.5, 0.04, 0.265), (0.6, -0.03, 0.25), (1.5, 0.03, 0.235)],
                   [0.3, 0.285, 0.265, 0.24], b, segs=8, cap0=True, cap1=True, cap_color="wood_light",
                   ring_colors=[b, bd, b])
    rnd = random.Random(2)

    def moss(f):
        if f.normal.z > 0.6 and abs(f.normal.x) < 0.5 and rnd.random() < 0.7:
            return "moss"
        return None
    S.repaint(mb, faces, moss)
    P.disc(mb, 0.17, (-1.505, 0.0, 0.27), "wood_mid", segs=7, toward=(-1, 0, 0))
    P.disc(mb, 0.13, (1.505, 0.03, 0.235), "wood_mid", segs=7, toward=(1, 0, 0))
    S.limb(mb, [(-0.35, 0.05, 0.4), (-0.15, 0.3, 0.72), (-0.08, 0.38, 0.8)], [0.1, 0.085, 0.075], bd, segs=5,
           cap_color="wood_light")
    S.limb(mb, [(0.75, -0.08, 0.36), (0.95, -0.42, 0.47), (1.0, -0.52, 0.5)], [0.085, 0.07, 0.06], bd, segs=5,
           cap_color="wood_light")
    mb.to_object(root, "mesh")


@asset("stump", col=cyl_col(0.31, 0.55), notes="0.55 m stump, roots reach 0.12 m below z = 0", **NAT)
def stump(root):
    mb = K.MB()
    b, bd = "bark", "bark_dark"
    P.lathe(mb, [(0.43, -0.12), (0.36, 0.06), (0.3, 0.27), (0.285, 0.55)], b, segs=8, colors=[bd, b, b],
            cap0=False, cap1=True, smooth=False, cap_colors=(bd, "wood_light"))
    P.disc(mb, 0.19, (0.01, 0.0, 0.556), "wood_mid", segs=7, toward=(0, 0, 1))
    P.disc(mb, 0.085, (0.02, 0.01, 0.562), "wood_light", segs=6, toward=(0, 0, 1))
    for i, a in enumerate((25, 115, 200, 300)):
        r = math.radians(a)
        d = V((math.cos(r), math.sin(r), 0))
        S.limb(mb, [d * 0.2 + V((0, 0, 0.26)), d * 0.5 + V((0, 0, 0.03)), d * (0.72 + 0.06 * (i % 2)) + V((0, 0, -0.12))],
               [0.12, 0.085, 0.0], bd, segs=4, tip=True, cap0=False)
    mb.to_object(root, "mesh")


@asset("driftwood", dynamic=True, mass=14, notes="1.8 m bleached branch lying along X", **NAT)
def driftwood(root):
    mb = K.MB()
    g, e = "plank_gray", "beige"
    S.limb(mb, [(-0.9, 0.05, 0.07), (-0.72, 0.03, 0.09), (-0.3, -0.05, 0.12), (0.25, 0.03, 0.16), (0.62, 0.0, 0.24),
                (0.9, -0.06, 0.36)], [0.075, 0.1, 0.085, 0.07, 0.05, 0.0], g, segs=6, cap0=True, tip=True,
           cap_color=e)
    S.limb(mb, [(0.2, 0.03, 0.15), (0.5, 0.26, 0.3), (0.66, 0.44, 0.46), (0.72, 0.55, 0.6)], [0.055, 0.045, 0.03, 0.0],
           g, segs=5, tip=True)
    S.limb(mb, [(-0.4, -0.04, 0.12), (-0.56, -0.26, 0.19), (-0.6, -0.33, 0.21)], [0.05, 0.04, 0.035], g, segs=5,
           cap_color=e)
    S.limb(mb, [(-0.8, 0.04, 0.09), (-0.9, 0.2, 0.2), (-0.93, 0.27, 0.27)], [0.045, 0.035, 0.03], g, segs=4,
           cap_color=e)
    S.recenter_xy(mb)
    mb.to_object(root, "mesh")


# =========================================================================== registry of this module
IDS_TREES = ["tree_oak_a", "tree_oak_b", "tree_round", "tree_pine_a", "tree_pine_b", "tree_palm_a", "tree_palm_b",
             "tree_dead"]
IDS_PLANTS = ["bush_a", "bush_b", "hedge", "grass_tuft", "grass_tall", "flower_patch", "reeds", "fern"]
IDS_ROCKS = ["rock_a", "rock_b", "rock_c", "rock_cliff", "log", "stump", "driftwood"]
IDS = IDS_TREES + IDS_PLANTS + IDS_ROCKS

BUDGET = {"grass_tuft": 24, "grass_tall": 32, "tree_oak_a": 900, "tree_oak_b": 900, "tree_palm_a": 900,
          "tree_palm_b": 900, "rock_cliff": 900}

ROW_Y = K.CATEGORIES["Nature"][1]
X0 = 0.0
SHEETS = [
    ("broadleaf", ["tree_oak_a", "tree_oak_b", "tree_round", "tree_dead"], 9.5, 9.0, 4),
    ("conifer_palm", ["tree_pine_a", "tree_pine_b", "tree_palm_a", "tree_palm_b"], 8.5, 9.0, 4),
    ("plants", ["bush_a", "bush_b", "hedge", "fern", "flower_patch", "grass_tuft", "grass_tall", "reeds"], 2.6, 2.6, 4),
    ("rocks", ["rock_a", "rock_b", "rock_c", "log", "stump", "driftwood"], 3.6, 3.4, 3),
    ("cliff", ["rock_cliff"], 10.0, 6.0, 1),
]


def do_layout():
    return P.layout(SHEETS, ROW_Y, X0)
