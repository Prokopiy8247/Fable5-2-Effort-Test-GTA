"""veh_oth - shared helpers for the NON-CAR vehicle modules of NEON TIDE
(veh_bikes / veh_boats / veh_air / veh_train / veh_parts).

Runs inside the user's live Blender through the MCP, on top of gta_kit (never modified):

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K; importlib.reload(K)
    import veh_oth as U; importlib.reload(U)

Everything here only adds geometry to a K.MB or touches objects of the asset that is passed in.
"""
import bpy
import bmesh
import json
import math
import os
from mathutils import Vector, Matrix, Euler
from mathutils.bvhtree import BVHTree
import gta_kit as K

MANIFEST = os.path.join(K.PROJECT, "gta", "resources", "data", "manifests", "vehicles_other.json")
SEAT_HIP = 0.25          # hip point above the seat cushion (same rule as the cars)
HIDDEN_PARTS = ("lod1", "col_")


def rad(a):
    return math.radians(a)


def vadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vlerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def lerp(a, b, t):
    return a + (b - a) * t


# --------------------------------------------------------------------------- cross-sections
def sring(y, cz, w, ht, hb=None, n=16, p=2.0, pb=None, cx=0.0):
    """Superellipse ring in the XZ plane at station y (fuselages / pods running along Y).
    w = half width, ht / hb = extent above / below cz, p / pb = exponent of the upper / lower half
    (2 = ellipse, bigger = boxier).  Point 0 = bottom centre, n/4 = right side (+X), n/2 = top centre."""
    hb = ht if hb is None else hb
    pb = p if pb is None else pb
    out = []
    for k in range(n):
        a = -0.5 * math.pi + 2.0 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        if abs(c) < 1e-9:
            c = 0.0
        if abs(s) < 1e-9:
            s = 0.0
        e = p if s >= 0 else pb
        x = w * math.copysign(abs(c) ** (2.0 / e), c)
        z = (ht if s >= 0 else hb) * math.copysign(abs(s) ** (2.0 / e), s)
        out.append((cx + x, y, cz + z))
    return out


def hring(y, half):
    """Ring in the XZ plane at station y from a half profile [(x, z), ...] running from the bottom
    (centre line or +X side) up to the top; the -X side is mirrored automatically."""
    r = [(x, y, z) for x, z in half]
    l = [(-x, y, z) for x, z in reversed(half) if abs(x) > 1e-6]
    return r + l


def zring(cx, cy, z, rx, ry, n=12, p=2.6, rot=0.0):
    """Superellipse ring in the XY plane at height z (cowls, pods standing upright)."""
    out = []
    for k in range(n):
        a = 2.0 * math.pi * k / n + rot
        c, s = math.cos(a), math.sin(a)
        if abs(c) < 1e-9:
            c = 0.0
        if abs(s) < 1e-9:
            s = 0.0
        out.append((cx + rx * math.copysign(abs(c) ** (2.0 / p), c),
                    cy + ry * math.copysign(abs(s) ** (2.0 / p), s), z))
    return out


def xring(x, cy, cz, ry, rz, n=12, p=2.0):
    """Superellipse ring in the YZ plane at station x (pods / nacelles running along X)."""
    out = []
    for k in range(n):
        a = 2.0 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        if abs(c) < 1e-9:
            c = 0.0
        if abs(s) < 1e-9:
            s = 0.0
        out.append((x, cy + ry * math.copysign(abs(c) ** (2.0 / p), c),
                    cz + rz * math.copysign(abs(s) ** (2.0 / p), s)))
    return out


def face(mb, pts, color, toward=None):
    """Single n-gon whose normal is forced to point along `toward` (direction in the current local frame)."""
    f = mb.poly(pts, color)
    f.normal_update()
    if toward is not None and f.normal.dot(mb.M.to_3x3() @ Vector(toward)) < 0.0:
        f.normal_flip()
    return f


def ring_map(ring, fn):
    return [fn(p) for p in ring]


def lerp_ring(a, b, t):
    return [vlerp(p, q, t) for p, q in zip(a, b)]


# --------------------------------------------------------------------------- lofting
class Grid(object):
    __slots__ = ("faces", "caps", "tips", "vr", "all")


def _mark(e, lim):
    if e is None:
        return
    if lim is None:
        e.smooth = True
        return
    try:
        e.smooth = e.calc_face_angle() < lim
    except ValueError:
        pass


def loft(mb, rings, color="gray_mid", closed=True, cap_start=True, cap_end=True, smooth=True, sharp=35.0,
         sharp_k=-1, tip_start=None, tip_end=None, flip=False, cap_color=None, outward=None):
    """Skin consecutive rings (lists of 3D points, equal length) with deterministic outward normals.

    color      palette name, or f(i, k) -> name | None  (i = segment between ring i and i+1, k = sector between
               point k and k+1; None leaves a hole; tips call it with i = -1 / len(rings)-1)
    sharp      rings edges (creases between consecutive segments) sharper than this stay hard; sharp_k does the
               same for the lengthwise edges (-1 = same as sharp, None = always smooth)
    tip_*      apex point: closes that end with a triangle fan instead of an n-gon cap
    outward    optional reference direction for the normals (needed for nearly flat open strips)
    Returns a Grid (faces[i][k], caps, tips, vr)."""
    bm = mb.bm
    m = mb.M
    vr = [[bm.verts.new(m @ Vector(p)) for p in ring] for ring in rings]
    nr = len(vr)
    n = len(vr[0])
    last = n if closed else n - 1
    cf = color if callable(color) else (lambda i, k: color)
    cens = [sum((v.co for v in ring), Vector()) / n for ring in vr]
    ow = None if outward is None else (m.to_3x3() @ Vector(outward))
    grid = []
    allf = []
    vote = 0.0
    for i in range(nr - 1):
        a, b = vr[i], vr[i + 1]
        axis_c = (cens[i] + cens[i + 1]) * 0.5
        row = []
        for k in range(last):
            k2 = (k + 1) % n
            c = cf(i, k)
            f = None
            if c is not None:
                try:
                    f = bm.faces.new([a[k], a[k2], b[k2], b[k]])
                except ValueError:
                    f = None
            if f is not None:
                mb.paint([f], c)
                f.normal_update()
                ref = ow if ow is not None else (f.calc_center_median() - axis_c)
                vote += f.normal.dot(ref) * f.calc_area()
                allf.append(f)
            row.append(f)
        grid.append(row)
    tips = []
    if tip_start is not None:
        tv = bm.verts.new(m @ Vector(tip_start))
        a = vr[0]
        for k in range(last):
            k2 = (k + 1) % n
            c = cf(-1, k)
            if c is None:
                continue
            try:
                f = bm.faces.new([tv, a[k2], a[k]])
            except ValueError:
                continue
            mb.paint([f], c)
            f.normal_update()
            if ow is None:
                vote += f.normal.dot(f.calc_center_median() - cens[0]) * f.calc_area() * 0.25
            tips.append(f)
    if tip_end is not None:
        tv = bm.verts.new(m @ Vector(tip_end))
        b = vr[-1]
        for k in range(last):
            k2 = (k + 1) % n
            c = cf(nr - 1, k)
            if c is None:
                continue
            try:
                f = bm.faces.new([b[k], b[k2], tv])
            except ValueError:
                continue
            mb.paint([f], c)
            f.normal_update()
            if ow is None:
                vote += f.normal.dot(f.calc_center_median() - cens[-1]) * f.calc_area() * 0.25
            tips.append(f)
    caps = [None, None]
    if isinstance(cap_color, (list, tuple)):
        cc0, cc1 = cap_color
    else:
        cc0 = cc1 = cap_color if cap_color else (color if isinstance(color, str) else "plastic_black")
    if closed and cap_start and tip_start is None and n >= 3:
        try:
            f = bm.faces.new(list(reversed(vr[0])))
            mb.paint([f], cc0)
            caps[0] = f
        except ValueError:
            pass
    if closed and cap_end and tip_end is None and n >= 3:
        try:
            f = bm.faces.new(list(vr[-1]))
            mb.paint([f], cc1)
            caps[1] = f
        except ValueError:
            pass
    everything = allf + tips + [c for c in caps if c is not None]
    if (vote < 0.0) != bool(flip):
        bmesh.ops.reverse_faces(bm, faces=everything)
    for f in everything:
        f.normal_update()
    for f in allf + tips:
        f.smooth = bool(smooth)
    if smooth:
        lim_r = None if sharp is None else math.radians(sharp)
        sk = sharp if sharp_k == -1 else sharp_k
        lim_k = None if sk is None else math.radians(sk)
        for i in range(nr - 1):
            for k in range(last):
                if grid[i][k] is None:
                    continue
                k2 = (k + 1) % n
                if i + 1 < nr - 1 and grid[i + 1][k] is not None:
                    _mark(bm.edges.get((vr[i + 1][k], vr[i + 1][k2])), lim_r)
                kn = k + 1
                if closed:
                    kn %= n
                if kn < last and grid[i][kn] is not None:
                    _mark(bm.edges.get((vr[i][k2], vr[i + 1][k2])), lim_k)
    g = Grid()
    g.faces = grid
    g.caps = caps
    g.tips = tips
    g.vr = vr
    g.all = everything
    return g


def lathe(mb, profile, color="gray_mid", axis="X", segs=12, pos=(0, 0, 0), colors=None, smooth=True,
          sharp=35.0, flip=False, phase=0.0):
    """Revolve a profile [(a, r), ...] (a along the axis, r = radius) around `axis` through pos.
    colors: one entry per profile segment (None = `color`, "-" = leave open).  Ends with r == 0 become fans.
    A closed cross-section (first point repeated at the end) gives a ring / torus-like solid.
    flip=True turns the surface inside out (e.g. the inner barrel of a rim, seen from the axis)."""
    def pt(a, r, t):
        c, s = math.cos(t) * r, math.sin(t) * r
        if axis == "X":
            return (pos[0] + a, pos[1] + c, pos[2] + s)
        if axis == "Y":
            return (pos[0] + s, pos[1] + a, pos[2] + c)
        return (pos[0] + c, pos[1] + s, pos[2] + a)

    prof = list(profile)
    tip_s = tip_e = None
    off = 0
    if prof[0][1] <= 1e-6:
        tip_s = pt(prof[0][0], 0.0, 0.0)
        prof = prof[1:]
        off = 1
    if prof[-1][1] <= 1e-6:
        tip_e = pt(prof[-1][0], 0.0, 0.0)
        prof = prof[:-1]
    rings = [[pt(a, r, phase + 2.0 * math.pi * k / segs) for k in range(segs)] for a, r in prof]

    def cf(i, k):
        if colors is None:
            return color
        j = max(0, min(len(colors) - 1, i + off))
        c = colors[j]
        if c is None:
            return color
        if c == "-":
            return None
        return c

    return loft(mb, rings, cf, closed=True, cap_start=False, cap_end=False, smooth=smooth, sharp=sharp,
                sharp_k=None, tip_start=tip_s, tip_end=tip_e, flip=flip)


def shell(mb, rings, cell, thickness=0.035, inner="@D:plastic_gray", strip=None, closed=True, smooth=True,
          sharp=35.0, open_ends=True, liner=True):
    """Thick skin over a ring grid with glazing and openings (cabins, doors).

    cell(i, k) -> None (opening / not part of this object), '@Glass' (single pane) or a colour (outer skin +
    inner liner `thickness` further in).  Sills / jambs are generated wherever a lined cell meets glass or an
    opening, so a door built from the same rings with the complementary cell function fits its hole exactly.
    liner: bool or f(i, k) -> bool; cells without liner are plain skin (nose cones, tail booms).
    Returns dict(outer=grid of outer faces, P=outer points, Q=liner points)."""
    bm = mb.bm
    m = mb.M
    P = [[m @ Vector(p) for p in ring] for ring in rings]
    nr, n = len(P), len(P[0])
    nk = n if closed else n - 1
    cen = [sum(r, Vector()) / n for r in P]
    CN = {}
    vote = 0.0
    for i in range(nr - 1):
        for k in range(nk):
            k2 = (k + 1) % n
            a, b, c, d = P[i][k], P[i][k2], P[i + 1][k2], P[i + 1][k]
            nrm = (c - a).cross(d - b)
            CN[(i, k)] = nrm
            vote += nrm.dot((a + b + c + d) * 0.25 - (cen[i] + cen[i + 1]) * 0.5)
    sgn = 1.0 if vote >= 0.0 else -1.0
    VN = [[Vector() for _k in range(n)] for _i in range(nr)]
    for (i, k), nrm in CN.items():
        k2 = (k + 1) % n
        for vi, vk in ((i, k), (i, k2), (i + 1, k2), (i + 1, k)):
            VN[vi][vk] += nrm * sgn
    Q = []
    for i in range(nr):
        row = []
        for k in range(n):
            v = VN[i][k]
            row.append(P[i][k] - (v.normalized() * thickness if v.length > 1e-12 else Vector()))
        Q.append(row)
    kind = {}
    col = {}
    for i in range(nr - 1):
        for k in range(nk):
            c = cell(i, k)
            col[(i, k)] = c
            if c is None:
                kind[(i, k)] = 0
            elif c.startswith("@Glass"):
                kind[(i, k)] = 1
            elif callable(liner):
                kind[(i, k)] = 2 if liner(i, k) else 3          # 3 = skin only (no liner, no jambs)
            else:
                kind[(i, k)] = 2 if liner else 3
    pv, qv = {}, {}

    def pvert(i, k):
        key = (i, k % n)
        v = pv.get(key)
        if v is None:
            v = bm.verts.new(P[key[0]][key[1]])
            pv[key] = v
        return v

    def qvert(i, k):
        key = (i, k % n)
        v = qv.get(key)
        if v is None:
            v = bm.verts.new(Q[key[0]][key[1]])
            qv[key] = v
        return v

    outer = [[None] * nk for _i in range(nr - 1)]
    of, inf, sf = [], [], []
    scol = strip if strip else inner
    for i in range(nr - 1):
        for k in range(nk):
            kd = kind[(i, k)]
            if kd == 0:
                continue
            vs = [pvert(i, k), pvert(i, k + 1), pvert(i + 1, k + 1), pvert(i + 1, k)]
            if sgn < 0:
                vs.reverse()
            f = bm.faces.new(vs)
            mb.paint([f], col[(i, k)])
            outer[i][k] = f
            of.append(f)
            if kd != 2:
                continue
            vs = [qvert(i, k), qvert(i + 1, k), qvert(i + 1, k + 1), qvert(i, k + 1)]
            if sgn < 0:
                vs.reverse()
            g = bm.faces.new(vs)
            mb.paint([g], inner)
            inf.append(g)
            # jambs / sills toward non-solid neighbours
            k2 = (k + 1) % n
            ctr = (P[i][k] + P[i][k2] + P[i + 1][k2] + P[i + 1][k]) * 0.25
            edges = (
                ((i, k), (i, k2), (i - 1, k), "i"),
                ((i + 1, k), (i + 1, k2), (i + 1, k), "i"),
                ((i, k), (i + 1, k), (i, k - 1), "k"),
                ((i, k2), (i + 1, k2), (i, k + 1), "k"),
            )
            for (ai, ak), (bi, bk), (ni, nk_), direction in edges:
                if direction == "i":
                    if ni < 0 or ni > nr - 2:
                        if open_ends:
                            continue
                        nkind = 0
                    else:
                        nkind = kind[(ni, nk_)]
                else:
                    if closed:
                        nkind = kind[(ni, nk_ % n)]
                    elif nk_ < 0 or nk_ > nk - 1:
                        if open_ends:
                            continue
                        nkind = 0
                    else:
                        nkind = kind[(ni, nk_)]
                if nkind >= 2:
                    continue
                p1, p2 = P[ai][ak], P[bi][bk]
                q1, q2 = Q[ai][ak], Q[bi][bk]
                vs = [bm.verts.new(p1), bm.verts.new(p2), bm.verts.new(q2), bm.verts.new(q1)]
                s = bm.faces.new(vs)
                s.normal_update()
                if s.normal.dot((p1 + p2) * 0.5 - ctr) < 0.0:
                    s.normal_flip()
                mb.paint([s], scol)
                s.smooth = False
                sf.append(s)
    for f in of + inf:
        f.normal_update()
        f.smooth = bool(smooth)
    if smooth:
        lim = math.radians(sharp)
        for group in (of, inf):
            gs = set(group)
            seen = set()
            for f in group:
                for e in f.edges:
                    if e in seen:
                        continue
                    seen.add(e)
                    lf = e.link_faces
                    if len(lf) == 2 and lf[0] in gs and lf[1] in gs:
                        try:
                            e.smooth = e.calc_face_angle() < lim
                        except ValueError:
                            pass
    return {"outer": outer, "P": P, "Q": Q, "faces": of + inf + sf}


def grid_point(rings, i, k, out=0.0):
    """Point k of ring i pushed `out` metres away from the ring centre (for frames / trims on a loft)."""
    ring = rings[i]
    n = len(ring)
    p = Vector(ring[k % n])
    if out == 0.0:
        return tuple(p)
    c = sum((Vector(q) for q in ring), Vector()) / n
    d = p - c
    if d.length < 1e-9:
        return tuple(p)
    return tuple(p + d.normalized() * out)


def grid_line(rings, pts, out=0.0):
    return [grid_point(rings, i, k, out) for i, k in pts]


# --------------------------------------------------------------------------- aerofoils
AF_S = (1.0, 0.68, 0.38, 0.16, 0.04)       # chord stations of the low-poly section (TE -> LE)


def af_half(s, t):
    """NACA-style half thickness (fraction of chord) at chord fraction s for a section of thickness t."""
    return 5.0 * t * (0.2969 * math.sqrt(s) - 0.1260 * s - 0.3516 * s * s + 0.2843 * s ** 3 - 0.1036 * s ** 4)


def af_points(t=0.12, camber=0.02, s0=0.0, s1=1.0, stations=AF_S):
    """2D section [(s, z)] (s = chord fraction from the leading edge, z up, both / chord) as a closed ring:
    upper surface from s1 to s0, then the lower surface back to s1.  s0 > 0 / s1 < 1 cut the section
    (wing box in front of a control surface, or the control surface wedge itself)."""
    def cam(s):
        return camber * 4.0 * s * (1.0 - s)
    ss = [s for s in stations if s0 < s < s1]
    up = [(s1, cam(s1) + af_half(s1, t))] + [(s, cam(s) + af_half(s, t)) for s in ss]
    lo = [(s, cam(s) - af_half(s, t)) for s in reversed(ss)] + [(s1, cam(s1) - af_half(s1, t))]
    if s0 <= 0.0:
        mid = [(0.0, 0.0)]
    else:
        mid = [(s0, cam(s0) + af_half(s0, t)), (s0, cam(s0) - af_half(s0, t))]
    pts = up + mid + lo
    if s1 >= 1.0:
        pts = pts[:-1]                      # single trailing-edge point
    return pts


def wing_ring(x, y_le, z, chord, t=0.12, camber=0.02, s0=0.0, s1=1.0, twist=0.0, vertical=False,
              stations=AF_S):
    """3D aerofoil ring at span station x (wings, tailplanes), leading edge at (x, y_le, z), chord toward -Y.
    vertical=True builds a fin section instead: span along Z (x is then the height z, z the sideways x)."""
    out = []
    ct, st = math.cos(math.radians(twist)), math.sin(math.radians(twist))
    for s, zz in af_points(t, camber, s0, s1, stations):
        dy = -s * chord
        dz = zz * chord
        dy, dz = dy * ct - dz * st, dy * st + dz * ct
        if vertical:
            out.append((z + dz, y_le + dy, x))
        else:
            out.append((x, y_le + dy, z + dz))
    return out


# --------------------------------------------------------------------------- small builders
def tube_ring(mb, cx, cy, cz, r, tr, color, plane="XY", segs=16, tsegs=6, a0=0.0, a1=360.0):
    """Torus / torus arc of major radius r and tube radius tr around (cx, cy, cz)."""
    full = abs(a1 - a0) >= 359.9
    cnt = segs if full else segs + 1
    rings = []
    for i in range(cnt):
        a = math.radians(a0 + (a1 - a0) * i / segs)
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for j in range(tsegs):
            b = 2.0 * math.pi * j / tsegs
            rr = r + tr * math.cos(b)
            h = tr * math.sin(b)
            if plane == "XY":
                ring.append((cx + ca * rr, cy + sa * rr, cz + h))
            elif plane == "YZ":
                ring.append((cx + h, cy + ca * rr, cz + sa * rr))
            else:
                ring.append((cx + ca * rr, cy + h, cz + sa * rr))
        rings.append(ring)
    if full:
        rings.append(rings[0])
    return loft(mb, rings, color, closed=True, cap_start=not full, cap_end=not full, smooth=True, sharp=None)


def seat(mb, pos, w=0.5, d=0.5, back_h=0.62, color="leather_black", trim=None, recline=12.0, base_h=0.14,
         headrest=True, yaw=0.0):
    """Bucket seat.  pos = top centre of the cushion.  Faces +Y (yaw rotates about Z)."""
    trim = trim or color
    with mb.at(pos, rot=(0, 0, yaw)):
        mb.box((w, d, base_h), (0, 0, -base_h * 0.5), color, bevel=0.03)
        mb.box((w * 0.86, d * 0.9, 0.05), (0, 0.01, 0.012), trim, bevel=0.02)
        with mb.at((0, -d * 0.5 + 0.04, -0.02), rot=(recline, 0, 0)):
            mb.box((w, 0.11, back_h), (0, 0, back_h * 0.5), color, bevel=0.03)
            mb.box((w * 0.8, 0.05, back_h * 0.74), (0, 0.045, back_h * 0.5), trim, bevel=0.015)
            if headrest:
                mb.box((w * 0.5, 0.09, 0.17), (0, 0.0, back_h + 0.11), color, bevel=0.03)
                mb.box((0.05, 0.03, 0.06), (0, 0, back_h + 0.01), "steel_dark")
    return (pos[0], pos[1], pos[2] + SEAT_HIP)


def bench(mb, pos, w=1.0, d=0.45, back_h=0.55, color="leather_black", trim=None, recline=10.0, base_h=0.14):
    """Bench seat (rear row).  pos = top centre of the cushion."""
    trim = trim or color
    with mb.at(pos):
        mb.box((w, d, base_h), (0, 0, -base_h * 0.5), color, bevel=0.03)
        with mb.at((0, -d * 0.5 + 0.04, -0.02), rot=(recline, 0, 0)):
            mb.box((w, 0.10, back_h), (0, 0, back_h * 0.5), color, bevel=0.03)
            for sx in (-0.25, 0.25):
                mb.box((w * 0.42, 0.04, back_h * 0.7), (sx * w, 0.045, back_h * 0.5), trim, bevel=0.015)


def steering_wheel(mb, r=0.17, color="plastic_black", hub="steel_dark", spokes=3, tr=0.016):
    """Steering wheel in the XZ plane (axis = +Y), hub at the origin of the current transform."""
    tube_ring(mb, 0, 0, 0, r, tr, color, plane="XZ", segs=14, tsegs=5)
    mb.cyl(r * 0.26, 0.04, (0, -0.005, 0), hub, axis="Y", segs=8)
    for i in range(spokes):
        a = 90.0 + 360.0 * i / spokes if spokes != 3 else (0.0, 180.0, 270.0)[i]
        with mb.at((0, 0, 0), rot=(0, -a, 0)):
            mb.box((r - 0.01, 0.014, 0.03), (r * 0.5, 0, 0), hub)


# --------------------------------------------------------------------------- objects
def repivot(obj, origin, rot=None):
    """Give the object a new origin (and orientation, Euler XYZ degrees) without moving its geometry."""
    m = Matrix.Translation(Vector(origin)) @ K._rot_matrix(rot)
    obj.data.transform(m.inverted())
    obj.location = origin
    if rot is not None:
        obj.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    return obj


def hide(obj, state=True):
    try:
        obj.hide_set(state)
    except Exception:
        pass


def col_hull(root, part, pts, color="gray_dark"):
    """Convex collision hull from a point cloud (keep it <= 24 points)."""
    mb = K.MB()
    vs = [mb.bm.verts.new(Vector(p)) for p in pts]
    res = bmesh.ops.convex_hull(mb.bm, input=vs, use_existing_faces=False)
    junk = set()
    for key in ("geom_interior", "geom_unused"):
        for g in res.get(key, []):
            if isinstance(g, bmesh.types.BMVert) and g.is_valid:
                junk.add(g)
    if junk:
        bmesh.ops.delete(mb.bm, geom=list(junk), context="VERTS")
    loose = [v for v in mb.bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(mb.bm, geom=loose, context="VERTS")
    faces = list(mb.bm.faces)
    bmesh.ops.recalc_face_normals(mb.bm, faces=faces)
    mb.paint(faces, color)
    nv = len(mb.bm.verts)
    obj = mb.to_object(root, part)
    obj["col_verts"] = nv
    hide(obj)
    return obj


def box_pts(x0, x1, y0, y1, z0, z1):
    return [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]


def show(root, mode="detail"):
    """Viewport helper for QA: 'detail' (hide lod1 + col), 'lod' (only lod1), 'col' (only col_*), 'all'."""
    if isinstance(root, str):
        root = bpy.data.objects[root]
    for o in root.children_recursive:
        part = o.name.split("__", 1)[-1]
        special = part == "lod1" or part.startswith("col_")
        if mode == "all":
            hide(o, False)
        elif mode == "detail":
            hide(o, special)
        elif mode == "lod":
            hide(o, part != "lod1")
        elif mode == "col":
            hide(o, not part.startswith("col_"))
    return mode


def part_tris(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def describe(root):
    """Text dump: parts (origin / rotation / tris) and markers (position / rotation)."""
    if isinstance(root, str):
        root = bpy.data.objects[root]
    lines = []
    for o in sorted(root.children, key=lambda o: o.name):
        part = o.name.split("__", 1)[-1]
        loc = tuple(round(v, 3) for v in o.location)
        rot = tuple(round(math.degrees(v), 1) for v in o.rotation_euler)
        if o.type == "MESH":
            extra = ""
            if "col_verts" in o:
                extra = " hull_verts=%d" % o["col_verts"]
            lines.append("part   %-14s origin=%s rot=%s tris=%d mats=%s%s" % (
                part, loc, rot, part_tris(o), [m.name for m in o.data.materials], extra))
        else:
            lines.append("marker %-14s pos=%s rot=%s" % (part, loc, rot))
    return "\n".join(lines)


# --------------------------------------------------------------------------- QA
def check(root, limit=12):
    """Normal / winding sanity check for every mesh part.  Returns a list of problem strings."""
    if isinstance(root, str):
        root = bpy.data.objects[root]
    problems = []
    for o in root.children:
        if o.type != "MESH":
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.normal_update()
        bm.faces.ensure_lookup_table()
        bm.verts.ensure_lookup_table()
        seen = set()
        zero = 0
        for f in bm.faces:
            if f.calc_area() < 1e-9:
                zero += 1
        if zero:
            problems.append("%s: %d zero-area faces" % (o.name, zero))
        for f0 in bm.faces:
            if f0.index in seen:
                continue
            stack = [f0]
            seen.add(f0.index)
            isl = []
            while stack:
                g = stack.pop()
                isl.append(g)
                for e in g.edges:
                    for h in e.link_faces:
                        if h.index not in seen:
                            seen.add(h.index)
                            stack.append(h)
            closed = True
            bad_wind = 0
            edges = set()
            for f in isl:
                for e in f.edges:
                    edges.add(e)
            for e in edges:
                lf = len(e.link_faces)
                if lf != 2:
                    closed = False
                elif not e.is_contiguous:
                    bad_wind += 1
            vol = sum(f.calc_center_median().dot(f.normal) * f.calc_area() for f in isl) / 3.0
            lo = Vector((1e9, 1e9, 1e9))
            hi = Vector((-1e9, -1e9, -1e9))
            vids = {}
            for f in isl:
                for v in f.verts:
                    vids[v.index] = v
                    for a in range(3):
                        lo[a] = min(lo[a], v.co[a])
                        hi[a] = max(hi[a], v.co[a])
            ctr = o.matrix_local @ ((lo + hi) * 0.5)
            where = "(%.2f, %.2f, %.2f) size (%.2f, %.2f, %.2f) %d faces" % (
                ctr.x, ctr.y, ctr.z, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, len(isl))
            if bad_wind:
                problems.append("%s: inconsistent winding (%d edges) island at %s" % (o.name, bad_wind, where))
                continue
            if closed:
                # local offset origin so the volume sign does not depend on where the island sits
                c0 = (lo + hi) * 0.5
                vol = sum((f.calc_center_median() - c0).dot(f.normal) * f.calc_area() for f in isl) / 3.0
                if vol < -1e-9:
                    problems.append("%s: INVERTED closed island at %s" % (o.name, where))
                continue
            # open island: ray parity test against itself
            order = sorted(vids)
            remap = {vi: j for j, vi in enumerate(order)}
            tree = BVHTree.FromPolygons([vids[vi].co.copy() for vi in order],
                                        [[remap[v.index] for v in f.verts] for f in isl])
            odd = 0
            for f in isl:
                org = f.calc_center_median() + f.normal * 1e-4
                hits = 0
                for _ in range(8):
                    loc, _n, _i, dist = tree.ray_cast(org, f.normal)
                    if loc is None:
                        break
                    hits += 1
                    org = loc + f.normal * 1e-4
                if hits % 2 == 1:
                    odd += 1
            if odd > 0.5 * len(isl) and len(isl) >= 2:
                problems.append("%s: open island probably inside-out (%d/%d faces) at %s" % (
                    o.name, odd, len(isl), where))
        bm.free()
    return problems[:limit] + (["... %d more" % (len(problems) - limit)] if len(problems) > limit else [])


# --------------------------------------------------------------------------- manifest / export
def manifest_update(root, glb, category, notes="", extra=None):
    if isinstance(root, str):
        root = bpy.data.objects[root]
    stats = K.asset_stats(root)
    parts, markers = [], []
    tris_detail = 0
    tris_lod = 0
    for o in root.children:
        part = o.name.split("__", 1)[-1]
        if o.type == "MESH":
            parts.append(part)
            t = part_tris(o)
            if part == "lod1":
                tris_lod = t
            elif not part.startswith("col_"):
                tris_detail += t
        else:
            markers.append(part)
    entry = {"id": root.name, "glb": glb, "category": category, "size": [round(v, 3) for v in stats["size"]],
             "tris": tris_detail, "parts": sorted(parts), "markers": sorted(markers), "notes": notes}
    if tris_lod:
        entry["tris_lod1"] = tris_lod
    entry["bbox_min"] = [round(v, 3) for v in stats["min"]]
    entry["bbox_max"] = [round(v, 3) for v in stats["max"]]
    if extra:
        entry.update(extra)
    data = {"assets": []}
    if os.path.exists(MANIFEST):
        try:
            with open(MANIFEST, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {"assets": []}
    assets = [a for a in data.get("assets", []) if a.get("id") != root.name]
    assets.append(entry)
    data["assets"] = assets
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write("{ \"assets\": [\n")
        f.write(",\n".join("  " + json.dumps(a) for a in assets))
        f.write("\n] }\n")
    return entry


def finish(root, glb, category, notes="", extra=None, export=True):
    """Hide helper parts, export the GLB and update the manifest.  Returns a one-line summary."""
    if isinstance(root, str):
        root = bpy.data.objects[root]
    show(root, "detail")
    size = -1
    if export:
        # Blender 5.2's glTF exporter raises KeyError('loglevel') for any export_loglevel >= 0 (the kit passes
        # 40), so force the default (-1) through the kit's `extra` hook.
        _path, size = K.export_asset(root, glb, extra={"export_loglevel": -1})
    show(root, "detail")
    e = manifest_update(root, glb, category, notes, extra)
    return "%s: tris=%d lod1=%s size=%s parts=%d markers=%d glb=%dB" % (
        root.name, e["tris"], e.get("tris_lod1", "-"), e["size"], len(e["parts"]), len(e["markers"]), size)


def glb_nodes(rel_path):
    """Names of the nodes stored in an exported GLB (sanity check of the export)."""
    import struct
    path = os.path.join(K.MODELS, rel_path.replace("/", os.sep) + ".glb")
    with open(path, "rb") as f:
        f.read(12)
        ln, _typ = struct.unpack("<II", f.read(8))
        js = json.loads(f.read(ln).decode("utf-8"))
    return {"nodes": [nd.get("name") for nd in js.get("nodes", [])],
            "materials": [mt.get("name") for mt in js.get("materials", [])],
            "meshes": len(js.get("meshes", []))}
