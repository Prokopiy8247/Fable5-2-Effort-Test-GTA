"""nature_animals - Halcyon Bay nature + wildlife asset builders (Blender 5.2, driven through MCP).

Author: NATURE AND WILDLIFE ARTIST. Everything in the 'Nature' and 'Animals' collections of the
master .blend is produced by this module and can be rebuilt at any time:

    import sys, importlib
    P = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Ultracode\\tools\\blender"
    for p in (P, P + r"\\assets"):
        if p not in sys.path: sys.path.append(p)
    import gta_bl as G; importlib.reload(G); G.assert_master()
    import nature_animals as NA; importlib.reload(NA)
    NA.build_all()        # builds every nature asset (+ tree LOD1s) and every animal
    NA.export_all()       # exports nature/<id>.glb, animals/<id>.glb and writes both manifests
    G.save()

Conventions
  * Nature asset   = root Empty '<id>' + ONE mesh child. Blender object names are unique per file,
    so the child is called '<id>_Mesh' in Blender; export_asset() strips the '<id>_' prefix inside
    the written GLB so the Godot node is called exactly 'Mesh'.
  * Animal         = root Empty '<id>' + rigid part objects '<id>_Body', '<id>_Head', '<id>_Leg_FL' ...
    (origins at the joints); exported node names are 'Body', 'Head', 'Leg_FL' ...
  * Every piece of geometry is a closed, outward-facing solid (no single-sided leaf cards), so the
    assets render correctly with back-face culling and with any replacement material.
  * Colours: shared palette materials only (G.pmat). No textures.
  * Origin at the base (ground). Geometry continues a little below z = 0 ("skirt") so assets can
    stand on slopes without gaps. Animals: feet on z = 0 (fish: centred on the origin), facing +Y.
"""
import bpy
import bmesh
import math
import random
import json
import os
import struct
from mathutils import Vector, Matrix, Euler

import gta_bl as G

NATURE_COL = "Nature"
ANIMAL_COL = "Animals"
LOD_SLOT_BASE = 40          # nature slots 40.. hold the tree LOD1 variants
TAU = math.pi * 2.0
SUN = Vector((0.30, -0.20, 0.93)).normalized()      # fake key-light used to pick facet tones
SUN_SIDE = Vector((0.62, -0.38, 0.68)).normalized()


# =================================================================================================
# generic helpers
# =================================================================================================
class MB:
    """Mesh builder: one bmesh + palette-key -> material-index bookkeeping."""

    def __init__(self):
        self.bm = bmesh.new()
        self.keys = []
        self.bevel = None       # (width, angle_deg) -> G.bevel() after the object is created

    def m(self, key):
        if key not in self.keys:
            self.keys.append(key)
        return self.keys.index(key)

    def materials(self):
        return [G.pmat(k) for k in self.keys]

    def mark(self):
        return len(self.bm.verts)

    def since(self, mark):
        return list(self.bm.verts)[mark:]


def _v(p):
    return p.copy() if isinstance(p, Vector) else Vector(p)


def faces_of(verts):
    fs = set()
    for v in verts:
        for f in v.link_faces:
            fs.add(f)
    return fs


def xform(verts, matrix):
    for v in verts:
        v.co = matrix @ v.co
    return verts


def rot_about(verts, pivot, rot3):
    """Rotate verts about `pivot` with a 3x3 rotation (Matrix / Euler tuple)."""
    if not isinstance(rot3, Matrix):
        rot3 = Euler(rot3, 'XYZ').to_matrix()
    p = Vector(pivot)
    for v in verts:
        v.co = p + rot3 @ (v.co - p)
    return verts


def loft(bm, sections, mat=0, col_mats=None, row_mats=None, cap_start=True, cap_end=True,
         tip_start=None, tip_end=None, closed=True, cap_mat=None, cyclic=False):
    """Skin cross-sections (lists of points with identical counts). Faces are wound so that the
    result faces outward when every ring runs counter-clockwise seen from the END of the path.
    col_mats: material per ring column; row_mats: material per interval; tip_*: close with a fan."""
    rings = [[bm.verts.new(_v(p)) for p in sec] for sec in sections]
    n = len(rings[0])
    last = n if closed else n - 1
    for r in range(len(rings) - 1):
        a, c = rings[r], rings[r + 1]
        for i in range(last):
            j = (i + 1) % n
            mi = mat
            if row_mats is not None:
                mi = row_mats[min(r, len(row_mats) - 1)]
            if col_mats is not None:
                mi = col_mats[i]
            try:
                f = bm.faces.new((a[i], a[j], c[j], c[i]))
                f.material_index = mi
            except ValueError:
                pass
    m0 = cap_mat if cap_mat is not None else (row_mats[0] if row_mats else mat)
    m1 = cap_mat if cap_mat is not None else (row_mats[-1] if row_mats else mat)
    if cyclic:
        a, c = rings[-1], rings[0]
        for i in range(last):
            j = (i + 1) % n
            try:
                f = bm.faces.new((a[i], a[j], c[j], c[i]))
                f.material_index = col_mats[i] if col_mats is not None else mat
            except ValueError:
                pass
        return rings
    if tip_start is not None:
        tv = bm.verts.new(_v(tip_start))
        r0 = rings[0]
        for i in range(last):
            j = (i + 1) % n
            f = bm.faces.new((tv, r0[j], r0[i]))
            f.material_index = col_mats[i] if col_mats is not None else m0
    elif cap_start and closed and n >= 3:
        try:
            f = bm.faces.new(list(reversed(rings[0])))
            f.material_index = m0
        except ValueError:
            pass
    if tip_end is not None:
        tv = bm.verts.new(_v(tip_end))
        rl = rings[-1]
        for i in range(last):
            j = (i + 1) % n
            f = bm.faces.new((rl[i], rl[j], tv))
            f.material_index = col_mats[i] if col_mats is not None else m1
    elif cap_end and closed and n >= 3:
        try:
            f = bm.faces.new(rings[-1])
            f.material_index = m1
        except ValueError:
            pass
    return rings


def tube(bm, pts, radii, n=6, mat=0, ref=(1, 0, 0), phase=0.0, star=0.0, **kw):
    """Loft rings along a path. radii: float or (ra, rb) per point - ra along `ref` (projected on
    the ring plane), rb along tangent x ra. star > 0 pulls every second ring vertex inward (ribs)."""
    pts = [_v(p) for p in pts]
    m = len(pts)
    cyc = bool(kw.get('cyclic'))
    tans = []
    for i in range(m):
        if cyc:
            t = pts[(i + 1) % m] - pts[(i - 1) % m]
        elif i == 0:
            t = pts[1] - pts[0]
        elif i == m - 1:
            t = pts[m - 1] - pts[m - 2]
        else:
            t = pts[i + 1] - pts[i - 1]
        if t.length < 1e-9:
            t = Vector((0, 0, 1))
        tans.append(t.normalized())
    u = Vector(ref)
    u = u - tans[0] * u.dot(tans[0])
    if u.length < 1e-4:
        u = Vector((0, 1, 0))
        u = u - tans[0] * u.dot(tans[0])
    u.normalize()
    secs = []
    prev = tans[0]
    for i in range(m):
        t = tans[i]
        ax = prev.cross(t)
        if ax.length > 1e-7:
            u = Matrix.Rotation(prev.angle(t), 3, ax.normalized()) @ u
        u = (u - t * u.dot(t)).normalized()
        v = t.cross(u)
        r = radii[i]
        ra, rb = (r if isinstance(r, (tuple, list)) else (r, r))
        sec = []
        for k in range(n):
            a = TAU * (k + phase) / n
            s = (1.0 - star) if (star and k % 2 == 1) else 1.0
            sec.append(pts[i] + u * (math.cos(a) * ra * s) + v * (math.sin(a) * rb * s))
        secs.append(sec)
        prev = t
    return loft(bm, secs, mat=mat, **kw)


def tone(faces, mats, hi=0.62, lo=-0.15, sun=SUN):
    """Pick light / mid / dark material per facet from its orientation (baked 'sunlit' look)."""
    ml, mm, md = mats
    for f in faces:
        f.normal_update()
        d = f.normal.dot(sun)
        f.material_index = ml if d > hi else (md if d < lo else mm)


def _tones(b, tones):
    if isinstance(tones, str):
        i = b.m(tones)
        return (i, i, i)
    if len(tones) == 2:
        return (b.m(tones[0]), b.m(tones[1]), b.m(tones[1]))
    return tuple(b.m(t) for t in tones)


def blob(b, center, r, scale=(1, 1, 1), sub=2, jitter=0.14, seed=1, tones=("LeafLight", "Leaf", "LeafDark"),
         rot_z=0.0, hi=0.62, lo=-0.15, flat_z=None, sun=SUN):
    """Faceted lump (jittered icosphere): foliage crowns, bushes, moss, corals."""
    bm = b.bm
    ret = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    verts = ret['verts']
    rng = random.Random(seed)
    M = Matrix.Translation(Vector(center)) @ Matrix.Rotation(rot_z, 4, 'Z') @ Matrix.Diagonal(
        (r * scale[0], r * scale[1], r * scale[2], 1.0))
    for v in verts:
        d = v.co.normalized() * (1.0 + rng.uniform(-jitter, jitter))
        v.co = M @ d
        if flat_z is not None and v.co.z < flat_z:
            v.co.z = flat_z
    tone(faces_of(verts), _tones(b, tones), hi, lo, sun)
    return verts


def hull(b, pts, tones=("WarmGrey", "Rock", "RockDark"), hi=0.80, lo=0.05, sun=SUN):
    """Convex hull of points -> chunky faceted rock piece."""
    bm = b.bm
    vs = [bm.verts.new(_v(p)) for p in pts]
    c = Vector((0, 0, 0))
    for v in vs:
        c += v.co
    c /= len(vs)
    ret = bmesh.ops.convex_hull(bm, input=vs, use_existing_faces=False)
    faces = [g for g in ret['geom'] if isinstance(g, bmesh.types.BMFace)]
    for v in vs:
        if v.is_valid and not v.link_faces:
            bm.verts.remove(v)
    for f in faces:
        f.normal_update()
        if f.normal.dot(f.calc_center_median() - c) < 0:
            f.normal_flip()
    tone(faces, _tones(b, tones), hi, lo, sun)
    return faces


def rock_pts(rng, size, n=18, sink=0.08, kmin=0.74):
    """Jittered fibonacci points on an ellipsoid that sits on the ground (flat, slightly sunk base)."""
    sx, sy, sz = size
    pts = []
    ga = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(n):
        z = 1.0 - 2.0 * (i + 0.5) / n
        rr = math.sqrt(max(0.0, 1.0 - z * z))
        a = ga * i + rng.uniform(-0.35, 0.35)
        k = rng.uniform(kmin, 1.0)
        p = Vector((rr * math.cos(a) * sx * 0.5 * k, rr * math.sin(a) * sy * 0.5 * k, z * sz * 0.62 * k + sz * 0.38))
        if p.z < -sink * sz:
            p.z = -sink * sz
        pts.append(p)
    return pts


def rock(b, center, size, seed, n=18, rot_z=0.0, tones=("WarmGrey", "Rock", "RockDark"), hi=0.80, lo=0.05, sink=0.08):
    rng = random.Random(seed)
    M = Matrix.Translation(Vector(center)) @ Matrix.Rotation(rot_z, 4, 'Z')
    return hull(b, [M @ p for p in rock_pts(rng, size, n, sink)], tones, hi, lo)


def block(b, rng, lo, hi, jit=0.12, bulge=0.25, extra=4, tones=("WarmGrey", "Rock", "RockDark"), t_hi=0.80, t_lo=0.05):
    """Chunky quarried block between two corners; the +Y face gets extra bulge points."""
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    pts = []
    for cx in (0, 1):
        for cy in (0, 1):
            for cz in (0, 1):
                px = (x0 + rng.uniform(0, jit) * dx) if cx == 0 else (x1 - rng.uniform(0, jit) * dx)
                py = y0 if cy == 0 else (y1 - rng.uniform(0, jit * 1.5) * dy)
                pz = (z0 + rng.uniform(0, jit * 0.4) * dz) if cz == 0 else (z1 - rng.uniform(0, jit * 0.6) * dz)
                pts.append((px, py, pz))
    for k in range(extra):
        pts.append((rng.uniform(x0 + 0.15 * dx, x1 - 0.15 * dx), y1 + rng.uniform(0.0, bulge) * dy,
                    rng.uniform(z0 + 0.2 * dz, z1 - 0.2 * dz)))
    return hull(b, pts, tones, t_hi, t_lo)


def frond(b, base, yaw, length, elev0, elev1, half_w, segs=6, top="Palm", bot="LeafDark", thick=0.03,
          edge_drop=0.35, serrate=0.0, stem=0.25, curve_pow=1.3, peak=0.35):
    """Arching leaf with a chevron cross-section (closed solid): palm fronds, ferns, kelp blades."""
    bm = b.bm
    d = Vector((math.cos(yaw), math.sin(yaw), 0.0))
    side = Vector((-d.y, d.x, 0.0))
    Z = Vector((0, 0, 1))
    spine = [Vector(base)]
    p = Vector(base)
    step = length / segs
    for i in range(segs):
        t = (i + 0.5) / segs
        el = elev0 + (elev1 - elev0) * (t ** curve_pow)
        p = p + (d * math.cos(el) + Z * math.sin(el)) * step
        spine.append(p.copy())
    secs = []
    for i in range(segs):
        t = i / segs
        tg = (spine[i + 1] - spine[max(i - 1, 0)]).normalized()
        nrm = tg.cross(side).normalized()
        if t < peak:
            w = stem + (1.0 - stem) * (t / peak)
        else:
            w = 1.0 - 0.80 * ((t - peak) / (1.0 - peak)) ** 1.5
        w *= half_w
        if serrate and i > 0 and i % 2 == 0:
            w *= (1.0 - serrate)
        sp = spine[i]
        secs.append([sp + nrm * thick, sp - side * w - nrm * (w * edge_drop),
                     sp - nrm * (thick * 0.5), sp + side * w - nrm * (w * edge_drop)])
    mt, mb = b.m(top), b.m(bot)
    return loft(bm, secs, col_mats=[mt, mb, mb, mt], tip_end=spine[-1], cap_start=True, cap_mat=mb)


def spike(b, base, tip, r, key, n=3, bend=None, r_mid=0.6):
    """Thin pointed blade / stalk. bend: optional mid point offset (vector) from the straight line."""
    base = Vector(base)
    tip = Vector(tip)
    mid = base.lerp(tip, 0.55) + (Vector(bend) if bend is not None else Vector((0, 0, 0)))
    return tube(b.bm, [base, mid], [r, r * r_mid], n=n, mat=b.m(key), tip_end=tip)


def ring_path(center, radius, n, axis='Y', a0=0.0, a1=TAU):
    """Points on a circle arc around `center` in the plane perpendicular to `axis`."""
    c = Vector(center)
    pts = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        if axis == 'Y':
            pts.append(c + Vector((math.cos(a) * radius, 0, math.sin(a) * radius)))
        elif axis == 'X':
            pts.append(c + Vector((0, math.cos(a) * radius, math.sin(a) * radius)))
        else:
            pts.append(c + Vector((math.cos(a) * radius, math.sin(a) * radius, 0)))
    return pts


# =================================================================================================
# registry
# =================================================================================================
_NATURE = {}
_NATURE_ORDER = []
_ANIMALS = {}
_ANIMAL_ORDER = []


def nature(aid, slot, category, collision_radius=0.0, collision="none", lod=False, **extra):
    def deco(fn):
        d = dict(id=aid, slot=slot, fn=fn, category=category, collision_radius=collision_radius,
                 collision=collision, lod=lod)
        d.update(extra)
        _NATURE[aid] = d
        _NATURE_ORDER.append(aid)
        return fn
    return deco


def animal(aid, slot, kind, **extra):
    def deco(fn):
        d = dict(id=aid, slot=slot, fn=fn, kind=kind)
        d.update(extra)
        _ANIMALS[aid] = d
        _ANIMAL_ORDER.append(aid)
        return fn
    return deco


def build_nature(aid, lod=0):
    spec = _NATURE[aid]
    name = aid if lod == 0 else "%s_lod%d" % (aid, lod)
    if lod == 0:
        slot_i = spec['slot']
    else:
        slot_i = LOD_SLOT_BASE + [a for a in _NATURE_ORDER if _NATURE[a]['lod']].index(aid)
    root = G.asset_root(name, NATURE_COL, G.slot("nature", slot_i))
    b = MB()
    spec['fn'](b, lod)
    ob = G.new_object(name + "_Mesh", b.bm, parent=root, materials=b.materials())
    if b.bevel:
        G.bevel(ob, b.bevel[0], 1, b.bevel[1])
    return root


# =================================================================================================
# TREES
# =================================================================================================
def _palm(b, lod, H, lean, sway, fr_len, n_fr, seed, r0=0.25, r1=0.14):
    rng = random.Random(seed)
    bm = b.bm
    K = 9 if lod == 0 else 4
    n = 6 if lod == 0 else 4
    m_side, m_step = b.m("TrunkLight"), b.m("Trunk")

    def P(t):
        return Vector((lean * (t ** 1.7) + sway * math.sin(t * math.pi), sway * 0.5 * math.sin(t * TAU * 0.6), H * t))

    def R(t):
        return r0 + (r1 - r0) * t + 0.11 * max(0.0, 1.0 - t * 8.0)

    pts = [Vector((0, 0, -0.4))]
    radii = [R(0) * 1.08]
    rows = [m_side]
    g = 0.012 if lod == 0 else 0.02
    for i in range(K):
        t0, t1 = i / K, (i + 1) / K
        pts.append(P(t0 + (g if i else 0.0)))
        radii.append(R(t0) * 0.90)
        pts.append(P(t1 - g))
        radii.append(R(t1) * 1.10)
        rows.append(m_side)
        rows.append(m_step)
    tube(bm, pts, radii, n=n, row_mats=rows, cap_mat=m_step)
    C = P(1.0)
    axis = (P(1.0) - P(0.93)).normalized()
    tilt = Vector((0, 0, 1)).rotation_difference(axis.lerp(Vector((0, 0, 1)), 0.35).normalized()).to_matrix()
    mk = b.mark()
    # crown heart
    blob(b, C + Vector((0, 0, 0.12)), 0.30, (1, 1, 1.25), sub=1, jitter=0.08, seed=seed + 5, tones=("Palm", "LeafDark"), hi=0.2)
    segs = 6 if lod == 0 else 3
    nf = n_fr if lod == 0 else max(6, n_fr - 4)
    for k in range(nf):
        tier = k % 3
        yaw = TAU * k / nf + rng.uniform(-0.16, 0.16)
        e0 = (1.08, 0.66, 0.24)[tier] + rng.uniform(-0.08, 0.08)
        e1 = (-0.42, -0.86, -1.22)[tier] + rng.uniform(-0.1, 0.1)
        ln = fr_len * (0.86, 1.0, 0.94)[tier] * rng.uniform(0.93, 1.07)
        base = C + Vector((math.cos(yaw) * 0.12, math.sin(yaw) * 0.12, 0.10 + 0.08 * (2 - tier)))
        frond(b, base, yaw, ln, e0, e1, 0.40, segs=segs, top=("Palm" if tier != 2 else "Leaf"), bot="LeafDark",
              thick=0.035, edge_drop=0.50, serrate=(0.36 if lod == 0 else 0.0), peak=0.30)
    if lod == 0:
        for k in range(3):
            a = TAU * k / 3 + 0.5
            blob(b, C + Vector((math.cos(a) * 0.24, math.sin(a) * 0.24, -0.20)), 0.15, sub=1, jitter=0.06,
                 seed=seed + 20 + k, tones=("Trunk", "WoodDark"), hi=0.35)
    rot_about(b.since(mk), C, tilt)


@nature("palm_a", 0, "tree", collision_radius=0.26, collision="trunk", lod=True, tags=["palm", "coast", "beach"])
def palm_a(b, lod):
    _palm(b, lod, H=8.3, lean=1.35, sway=0.0, fr_len=3.9, n_fr=12, seed=11)


@nature("palm_b", 1, "tree", collision_radius=0.24, collision="trunk", lod=True, tags=["palm", "coast", "street"])
def palm_b(b, lod):
    _palm(b, lod, H=5.9, lean=-0.75, sway=0.32, fr_len=3.2, n_fr=11, seed=23, r0=0.23, r1=0.13)


def _limb(bm, pts, radii, n, mi, tip=False):
    if tip:
        return tube(bm, pts[:-1], radii[:-1], n=n, mat=mi, tip_end=pts[-1])
    return tube(bm, pts, radii, n=n, mat=mi)


@nature("tree_broadleaf_a", 2, "tree", collision_radius=0.30, collision="trunk", lod=True, tags=["broadleaf", "park", "hill"])
def tree_broadleaf_a(b, lod):
    bm = b.bm
    mt = b.m("Trunk")
    n = 7 if lod == 0 else 4
    nb = 5 if lod == 0 else 3
    sub = 2 if lod == 0 else 1
    tube(bm, [(0, 0, -0.4), (0, 0, 0.05), (0.04, 0, 1.2), (0.12, 0.04, 2.6), (0.10, 0.05, 3.7), (0.05, 0, 5.2)],
         [0.54, 0.39, 0.29, 0.25, 0.20, 0.10], n=n, mat=mt)
    if lod == 0:
        _limb(bm, [(0.12, 0.04, 2.45), (0.95, 0.30, 3.55), (1.55, 0.50, 4.5)], [0.13, 0.10, 0.06], nb, mt)
        _limb(bm, [(0.12, 0.04, 2.60), (-0.85, 0.50, 3.70), (-1.45, 0.90, 4.7)], [0.13, 0.10, 0.06], nb, mt)
        _limb(bm, [(0.10, 0.04, 2.80), (0.0, -0.90, 3.85), (-0.10, -1.50, 4.8)], [0.12, 0.09, 0.06], nb, mt)
    T = ("LeafLight", "Leaf", "LeafDark")
    blob(b, (0.0, 0.0, 5.85), 2.15, (1, 1, 0.86), sub, 0.15, 101, T)
    blob(b, (1.65, 0.55, 5.0), 1.50, (1, 1, 0.9), sub, 0.15, 102, T)
    blob(b, (-1.55, 0.95, 5.15), 1.45, (1, 1, 0.9), sub, 0.15, 103, T)
    blob(b, (-0.15, -1.65, 5.2), 1.50, (1, 1, 0.9), sub, 0.15, 104, T)
    blob(b, (0.45, -0.35, 7.0), 1.20, (1, 1, 0.9), sub, 0.16, 105, T)


@nature("tree_broadleaf_b", 3, "tree", collision_radius=0.45, collision="trunk", lod=True, tags=["broadleaf", "oak", "hill", "park"])
def tree_broadleaf_b(b, lod):
    bm = b.bm
    mt = b.m("Trunk")
    n = 8 if lod == 0 else 5
    nb = 6 if lod == 0 else 4
    sub = 2 if lod == 0 else 1
    tube(bm, [(0, 0, -0.5), (0, 0, 0.05), (-0.05, 0.02, 1.3), (-0.10, 0.05, 2.7), (0.0, 0.0, 3.5)],
         [0.72, 0.52, 0.40, 0.36, 0.33], n=n, mat=mt)
    _limb(bm, [(-0.05, 0.0, 3.1), (1.2, 0.5, 4.5), (2.4, 0.9, 5.8), (3.0, 1.1, 6.6)], [0.26, 0.20, 0.13, 0.07], nb, mt)
    _limb(bm, [(-0.10, 0.05, 3.1), (-1.3, 0.2, 4.6), (-2.5, 0.5, 5.9), (-3.1, 0.6, 6.7)], [0.26, 0.20, 0.13, 0.07], nb, mt)
    _limb(bm, [(0.0, 0.0, 3.2), (0.1, -1.1, 4.8), (0.3, -2.0, 6.2)], [0.24, 0.17, 0.08], nb, mt)
    _limb(bm, [(0.0, 0.0, 3.3), (-0.1, 0.5, 5.4), (0.0, 0.8, 7.6)], [0.28, 0.19, 0.08], nb, mt)
    T = ("LeafLight", "Leaf", "LeafDark")
    blob(b, (0.0, 0.3, 8.2), 2.9, (1.1, 1.05, 0.80), sub, 0.15, 201, T)
    blob(b, (3.1, 1.1, 7.0), 2.2, (1.05, 1, 0.82), sub, 0.15, 202, T)
    blob(b, (-3.2, 0.7, 7.1), 2.3, (1.05, 1, 0.82), sub, 0.15, 203, T)
    blob(b, (0.4, -2.5, 6.9), 2.2, (1, 1, 0.82), sub, 0.15, 204, T)
    blob(b, (-0.3, 2.6, 7.2), 2.0, (1, 1, 0.82), sub, 0.15, 205, T)
    blob(b, (1.2, -0.4, 9.7), 1.75, (1.1, 1, 0.78), sub, 0.16, 206, T)
    blob(b, (-1.6, 0.4, 9.4), 1.6, (1, 1, 0.8), sub, 0.16, 207, T)


@nature("tree_broadleaf_c", 4, "tree", collision_radius=0.20, collision="trunk", lod=True, tags=["broadleaf", "birch", "residential", "park"])
def tree_broadleaf_c(b, lod):
    bm = b.bm
    mw, mk = b.m("Cream"), b.m("HairBlack")
    n = 6 if lod == 0 else 4
    sub = 2 if lod == 0 else 1
    # pale banded trunk (birch-like): thin dark rings between long pale sections
    zs = [-0.35, 0.05, 0.70, 0.86, 1.55, 1.70, 2.35, 2.48, 3.2, 4.4]
    rs = [0.34, 0.23, 0.195, 0.195, 0.175, 0.175, 0.16, 0.16, 0.135, 0.06]
    pts = [(0.03 * math.sin(z * 1.3), 0.02 * math.cos(z * 1.7), z) for z in zs]
    rows = [mw, mw, mk, mw, mk, mw, mk, mw, mw]
    tube(bm, pts, rs, n=n, row_mats=rows, cap_mat=mw)
    T = ("LeafLight", "LeafLight", "Leaf")
    blob(b, (0.0, 0.0, 4.30), 1.45, (1.0, 1.0, 1.50), sub, 0.14, 301, T, hi=0.5, lo=0.0)
    blob(b, (0.80, -0.30, 3.35), 0.95, (1.0, 1.0, 1.10), sub, 0.15, 302, T, hi=0.5, lo=0.0)
    blob(b, (-0.85, 0.35, 3.70), 0.90, (1.0, 1.0, 1.15), sub, 0.15, 303, T, hi=0.5, lo=0.0)
    blob(b, (0.25, 0.75, 4.95), 0.82, (1, 1, 1.1), 1, 0.14, 304, T, hi=0.5, lo=0.0)
    blob(b, (-0.35, -0.65, 5.30), 0.80, (1, 1, 1.1), 1, 0.14, 305, T, hi=0.5, lo=0.0)
    blob(b, (0.08, 0.0, 6.25), 0.68, (1, 1, 1.25), 1, 0.12, 306, T, hi=0.5, lo=0.0)


def _pine(b, lod, H, base_r, tiers, clear, trunk_r, seed, lean=0.0):
    rng = random.Random(seed)
    bm = b.bm
    mt = b.m("Trunk")
    ml, md = b.m("Leaf"), b.m("LeafDark")
    n = 6 if lod == 0 else 4
    teeth = 8 if lod == 0 else 5
    tube(bm, [(0, 0, -0.4), (0, 0, 0.05), (lean * 0.3, 0, clear + 0.6), (lean, 0, H * 0.8)],
         [trunk_r * 1.5, trunk_r, trunk_r * 0.8, 0.05], n=n, mat=mt)
    span = H - clear
    for k in range(tiers):
        f = k / max(1, tiers - 1)
        z0 = clear + span * 0.80 * (f ** 0.92)
        R = base_r * (1.0 - 0.70 * f)
        if k == tiers - 1:
            zt = H
        else:
            zt = z0 + span / tiers * 1.75
        cx = lean * (z0 / (H * 0.8)) * 0.8
        rz = rng.uniform(0, TAU)
        tilt = Euler((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), 0)).to_matrix()
        skirt = []
        for i in range(teeth * 2):
            a = rz + TAU * i / (teeth * 2)
            outer = (i % 2 == 0)
            rr = R * (rng.uniform(0.94, 1.06) if outer else rng.uniform(0.66, 0.76))
            zz = (-0.10 * R if outer else 0.06 * R)
            skirt.append(Vector((cx, 0, z0)) + tilt @ Vector((math.cos(a) * rr, math.sin(a) * rr, zz)))
        apex = Vector((cx * 1.0 + lean * 0.05, 0, zt))
        under = Vector((cx, 0, z0 + 0.22 * R))
        ring = [bm.verts.new(p) for p in skirt]
        va = bm.verts.new(apex)
        vu = bm.verts.new(under)
        m2 = len(ring)
        side = []
        for i in range(m2):
            j = (i + 1) % m2
            side.append(bm.faces.new((ring[i], ring[j], va)))
            fu = bm.faces.new((ring[j], ring[i], vu))
            fu.material_index = md
        tone(side, (ml, md, md), hi=0.60, lo=0.0, sun=SUN_SIDE)


@nature("tree_pine_a", 5, "tree", collision_radius=0.30, collision="trunk", lod=True, tags=["pine", "hill"])
def tree_pine_a(b, lod):
    _pine(b, lod, H=12.6, base_r=2.7, tiers=5, clear=2.0, trunk_r=0.30, seed=41)


@nature("tree_pine_b", 6, "tree", collision_radius=0.26, collision="trunk", lod=True, tags=["pine", "hill"])
def tree_pine_b(b, lod):
    _pine(b, lod, H=8.6, base_r=2.35, tiers=4, clear=1.3, trunk_r=0.27, seed=57, lean=0.25)


@nature("tree_small_a", 7, "tree", collision_radius=0.14, collision="trunk", lod=True, tags=["street", "sidewalk", "plaza"])
def tree_small_a(b, lod):
    bm = b.bm
    mt = b.m("Trunk")
    n = 6 if lod == 0 else 4
    sub = 2 if lod == 0 else 1
    tube(bm, [(0, 0, -0.3), (0, 0, 0.04), (0.02, 0.0, 1.2), (0.0, 0.02, 2.3), (0.0, 0.0, 3.0)],
         [0.25, 0.16, 0.13, 0.115, 0.07], n=n, mat=mt)
    if lod == 0:
        _limb(bm, [(0.0, 0.02, 2.1), (0.45, 0.15, 2.6), (0.75, 0.25, 3.0)], [0.055, 0.045, 0.03], 4, mt)
        _limb(bm, [(0.0, 0.02, 2.2), (-0.42, -0.2, 2.7), (-0.7, -0.35, 3.05)], [0.055, 0.045, 0.03], 4, mt)
    T = ("LeafLight", "Leaf", "LeafDark")
    blob(b, (0.0, 0.0, 3.45), 1.22, (1, 1, 0.92), sub, 0.13, 401, T)
    blob(b, (0.8, 0.3, 3.05), 0.72, (1, 1, 0.9), 1 if lod else 2, 0.14, 402, T)
    blob(b, (-0.75, -0.4, 3.1), 0.74, (1, 1, 0.9), 1 if lod else 2, 0.14, 403, T)
    if lod == 0:
        blob(b, (0.1, -0.2, 4.2), 0.66, (1, 1, 0.9), 1, 0.12, 404, T)


def _dead_branch(b, rng, p0, d, length, r, depth, n, mi, mi_tip):
    bm = b.bm
    d = d.normalized()
    perp = d.orthogonal().normalized()
    perp = Matrix.Rotation(rng.uniform(0, TAU), 3, d) @ perp
    p1 = p0 + d * (length * 0.5) + perp * (length * rng.uniform(0.04, 0.10))
    p2 = p0 + d * length + perp * (length * rng.uniform(-0.12, 0.02)) + Vector((0, 0, length * 0.10))
    if depth == 0:
        tube(bm, [p0, p1], [r, r * 0.6], n=n, mat=mi, tip_end=p2)
        return
    tube(bm, [p0, p1, p2], [r, r * 0.78, r * 0.55], n=n, mat=mi, cap_mat=mi_tip)
    kids = 2 if depth > 1 or rng.random() < 0.75 else 1
    for k in range(kids):
        ang = rng.uniform(0.45, 0.85) * (1 if k == 0 else -1)
        ax = Matrix.Rotation(rng.uniform(0, TAU), 3, d) @ perp
        nd = Matrix.Rotation(ang, 3, ax) @ d
        nd = (nd + Vector((0, 0, 0.35))).normalized()
        start = p2 if k == 0 else p1.lerp(p2, rng.uniform(0.3, 0.9))
        _dead_branch(b, rng, start, nd, length * rng.uniform(0.55, 0.72), r * (0.56 if k == 0 else 0.46), depth - 1, n, mi, mi_tip)


@nature("tree_dead", 8, "tree", collision_radius=0.24, collision="trunk", lod=True, tags=["dead", "hill", "industrial"])
def tree_dead(b, lod):
    bm = b.bm
    rng = random.Random(77)
    mb, md = b.m("TrunkLight"), b.m("Trunk")
    n = 6 if lod == 0 else 4
    nb = 5 if lod == 0 else 3
    tube(bm, [(0, 0, -0.4), (0, 0, 0.05), (0.06, 0.0, 1.1), (0.16, 0.05, 2.2), (0.12, 0.0, 3.0)],
         [0.44, 0.30, 0.23, 0.20, 0.17], n=n, row_mats=[md, md, mb, mb], cap_mat=md)
    depth = 2 if lod == 0 else 1
    _dead_branch(b, rng, Vector((0.12, 0.0, 2.9)), Vector((0.55, 0.15, 1.0)), 2.3, 0.15, depth, nb, mb, md)
    _dead_branch(b, rng, Vector((0.14, 0.02, 2.8)), Vector((-0.65, 0.25, 1.0)), 2.5, 0.16, depth, nb, mb, md)
    _dead_branch(b, rng, Vector((0.14, 0.0, 2.3)), Vector((0.1, -0.9, 0.8)), 1.7, 0.11, depth - 1 if lod == 0 else 0, nb, mb, md)
    if lod == 0:
        # snapped stub + a hollow knot
        tube(bm, [(0.10, 0.03, 1.5), (-0.30, 0.42, 1.85)], [0.09, 0.07], n=5, mat=mb, cap_mat=md)


# =================================================================================================
# SHRUBS / GROUND COVER
# =================================================================================================
@nature("cactus_a", 9, "shrub", collision_radius=0.30, collision="trunk", tags=["cactus", "dry", "hill"])
def cactus_a(b, lod):
    bm = b.bm
    mg = b.m("LeafDark")
    ml = b.m("Leaf")
    cm = [mg, ml] * 5

    def column(pts, r):
        radii = [r] * (len(pts) - 2) + [r * 0.93, r * 0.62]
        last = Vector(pts[-1])
        prev = Vector(pts[-2])
        tip = last + (last - prev).normalized() * (r * 0.42)
        tube(bm, pts, radii, n=10, col_mats=cm, star=0.20, tip_end=tip, cap_mat=mg)
        return tip

    t0 = column([(0, 0, -0.3), (0, 0, 0.6), (0.0, 0, 1.8), (0, 0, 2.75), (0, 0, 3.05)], 0.27)
    t1 = column([(0.20, 0, 1.25), (0.62, 0.02, 1.32), (0.84, 0.03, 1.62), (0.86, 0.03, 2.25), (0.86, 0.03, 2.45)], 0.155)
    t2 = column([(-0.20, 0, 1.75), (-0.55, -0.02, 1.84), (-0.72, -0.03, 2.10), (-0.73, -0.03, 2.55), (-0.73, -0.03, 2.70)], 0.14)
    for i, t in enumerate((t0, t1, t2)):
        blob(b, t + Vector((0.03, 0.0, 0.02)), 0.085 if i == 0 else 0.065, (1, 1, 0.7), sub=1, jitter=0.1, seed=600 + i,
             tones=("Rose", "Rose", "Coral"), hi=0.0, lo=-0.5)


def _bush(b, parts, tones, seed, flat=-0.06, sub_main=2):
    for i, (c, r, s) in enumerate(parts):
        big = (i == 0 or r >= 0.42)
        blob(b, c, r, s, sub=(sub_main if big else 1), jitter=(0.15 if big else 0.09), seed=seed + i, tones=tones, flat_z=flat)


@nature("bush_a", 10, "shrub", collision_radius=0.0, tags=["bush", "park", "residential"])
def bush_a(b, lod):
    _bush(b, [((0, 0, 0.42), 0.62, (1, 1, 0.82)), ((0.52, 0.16, 0.30), 0.42, (1, 1, 0.85)),
              ((-0.46, 0.22, 0.30), 0.44, (1, 1, 0.85)), ((0.05, -0.48, 0.28), 0.40, (1, 1, 0.85))],
          ("LeafLight", "Leaf", "LeafDark"), 700)


@nature("bush_b", 11, "shrub", collision_radius=0.0, tags=["bush", "hill", "wild"])
def bush_b(b, lod):
    _bush(b, [((0.1, 0, 0.60), 0.85, (1.15, 1, 0.80)), ((-0.85, 0.2, 0.42), 0.58, (1, 1, 0.85)),
              ((0.95, -0.25, 0.40), 0.55, (1, 1, 0.85)), ((0.2, 0.75, 0.36), 0.50, (1, 1, 0.85)),
              ((-0.3, -0.7, 0.34), 0.48, (1, 1, 0.85))],
          ("Leaf", "LeafDark", "LeafDark"), 720)
    # a few woody stems poking out
    spike(b, (0.3, 0.1, 0.9), (0.55, 0.25, 1.55), 0.03, "Trunk", n=4)
    spike(b, (-0.5, 0.0, 0.7), (-0.8, -0.2, 1.25), 0.025, "Trunk", n=4)


@nature("bush_c", 12, "shrub", collision_radius=0.0, tags=["bush", "flowering", "residential", "park"])
def bush_c(b, lod):
    parts = [((0, 0, 0.40), 0.58, (1.1, 1, 0.80)), ((0.55, -0.1, 0.30), 0.40, (1, 1, 0.85)),
             ((-0.5, 0.15, 0.30), 0.42, (1, 1, 0.85))]
    _bush(b, parts, ("LeafLight", "Leaf", "LeafDark"), 740)
    rng = random.Random(741)
    mp = b.m("Rose")
    mc = b.m("White")
    for k in range(14):
        c, r, s = parts[k % 3]
        z = rng.uniform(0.15, 1.0)
        a = rng.uniform(0, TAU)
        rr = math.sqrt(max(0.0, 1.0 - z * z))
        p = Vector(c) + Vector((rr * math.cos(a) * r * s[0], rr * math.sin(a) * r * s[1], z * r * s[2])) * 0.93
        n3 = (p - Vector(c)).normalized()
        q = n3.orthogonal().normalized()
        w = n3.cross(q)
        hr = 0.085
        ring = [p + q * (math.cos(TAU * i / 5) * hr) + w * (math.sin(TAU * i / 5) * hr) for i in range(5)]
        loft(b.bm, [ring], mat=(mp if k % 4 else mc), tip_end=p + n3 * 0.075, tip_start=p - n3 * 0.12)


@nature("hedge_ball", 13, "shrub", collision_radius=0.45, collision="blob", tags=["hedge", "topiary", "residential", "plaza"])
def hedge_ball(b, lod):
    tube(b.bm, [(0, 0, -0.2), (0, 0, 0.05), (0, 0, 0.45)], [0.09, 0.065, 0.055], n=5, mat=b.m("Trunk"))
    blob(b, (0, 0, 0.70), 0.60, (1, 1, 0.93), sub=2, jitter=0.045, seed=760, tones=("LeafLight", "Leaf", "LeafDark"), hi=0.70)


@nature("fern", 14, "groundcover", tags=["fern", "hill", "forest"], multimesh=True)
def fern(b, lod):
    rng = random.Random(780)
    nf = 10
    for k in range(nf):
        yaw = TAU * k / nf + rng.uniform(-0.2, 0.2)
        big = (k % 2 == 0)
        frond(b, (math.cos(yaw) * 0.03, math.sin(yaw) * 0.03, 0.0), yaw, 0.88 if big else 0.62,
              (1.22 if big else 1.40) + rng.uniform(-0.08, 0.08), -0.55 + rng.uniform(-0.15, 0.15), 0.135 if big else 0.105,
              segs=4, top=("Leaf" if big else "LeafLight"), bot="LeafDark", thick=0.012, edge_drop=0.30,
              serrate=0.0, stem=0.18, peak=0.4, curve_pow=1.0)


def _tuft(b, rng, count, radius, h_lo, h_hi, w, keys):
    for k in range(count):
        a = TAU * k / count + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.0, radius) if k else 0.0
        base = Vector((math.cos(a) * d, math.sin(a) * d, -0.04))
        h = rng.uniform(h_lo, h_hi) * (1.0 if k else 1.1)
        lean = rng.uniform(0.12, 0.42) * h
        la = a + rng.uniform(-0.5, 0.5)
        tip = base + Vector((math.cos(la) * lean, math.sin(la) * lean, h))
        bend = Vector((-math.cos(la) * lean * 0.22, -math.sin(la) * lean * 0.22, 0.0))
        spike(b, base, tip, w * rng.uniform(0.8, 1.15), keys[k % len(keys)], n=3, bend=bend, r_mid=0.62)


@nature("grass_tuft_a", 15, "groundcover", tags=["grass"], multimesh=True)
def grass_tuft_a(b, lod):
    _tuft(b, random.Random(801), 6, 0.10, 0.30, 0.46, 0.028, ["Grass", "Grass", "LeafLight"])


@nature("grass_tuft_b", 16, "groundcover", tags=["grass"], multimesh=True)
def grass_tuft_b(b, lod):
    _tuft(b, random.Random(811), 10, 0.24, 0.16, 0.30, 0.034, ["GrassDark", "Grass", "GrassDark"])


def _flower_head(b, p, n3, r, petal, centre):
    bm = b.bm
    q = n3.orthogonal().normalized()
    w = n3.cross(q)
    ring = [p + q * (math.cos(TAU * i / 6) * r) + w * (math.sin(TAU * i / 6) * r) + n3 * (0.012 if i % 2 else 0.0) for i in range(6)]
    loft(bm, [ring], mat=b.m(petal), tip_end=p + n3 * 0.015, tip_start=p - n3 * (r * 0.55))
    ring2 = [p + n3 * 0.012 + q * (math.cos(TAU * i / 5) * r * 0.36) + w * (math.sin(TAU * i / 5) * r * 0.36) for i in range(5)]
    loft(bm, [ring2], mat=b.m(centre), tip_end=p + n3 * (0.012 + r * 0.42), cap_start=True)


def _tulip(b, p, n3, r, key, inner):
    bm = b.bm
    tube(bm, [p, p + n3 * (r * 1.3), p + n3 * (r * 2.6)], [r * 0.45, r, r * 0.72], n=5, mat=b.m(key), ref=n3.orthogonal(),
         cap_mat=b.m(inner))


@nature("flower_patch_a", 17, "groundcover", tags=["flowers", "park", "residential"], multimesh=True)
def flower_patch_a(b, lod):
    rng = random.Random(821)
    cols = [("Rose", "Mustard"), ("White", "Mustard"), ("Rose", "Mustard"), ("White", "Mustard"), ("Coral", "Cream")]
    for k in range(7):
        a = TAU * k / 7 + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.08, 0.36) if k else 0.0
        base = Vector((math.cos(a) * d, math.sin(a) * d, -0.03))
        h = rng.uniform(0.26, 0.44)
        top = base + Vector((math.cos(a) * 0.05, math.sin(a) * 0.05, h))
        tube(b.bm, [base, top], [0.012, 0.009], n=3, mat=b.m("GrassDark"))
        n3 = (Vector((math.cos(a) * 0.35, math.sin(a) * 0.35, 1.0))).normalized()
        pc, cc = cols[k % len(cols)]
        _flower_head(b, top, n3, rng.uniform(0.065, 0.085), pc, cc)
    _tuft(b, rng, 7, 0.34, 0.10, 0.20, 0.03, ["GrassDark", "Grass"])


@nature("flower_patch_b", 18, "groundcover", tags=["flowers", "park", "plaza"], multimesh=True)
def flower_patch_b(b, lod):
    rng = random.Random(831)
    cols = [("Lavender", "CarPurple"), ("CarYellow", "Mustard"), ("Coral", "Terracotta"), ("Lavender", "CarPurple"), ("CarYellow", "Mustard")]
    for k in range(8):
        a = TAU * k / 8 + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.10, 0.38) if k else 0.0
        base = Vector((math.cos(a) * d, math.sin(a) * d, -0.03))
        h = rng.uniform(0.24, 0.40)
        top = base + Vector((math.cos(a) * 0.03, math.sin(a) * 0.03, h))
        tube(b.bm, [base, top], [0.012, 0.009], n=3, mat=b.m("GrassDark"))
        n3 = (Vector((math.cos(a) * 0.18, math.sin(a) * 0.18, 1.0))).normalized()
        pc, cc = cols[k % len(cols)]
        _tulip(b, top - n3 * 0.01, n3, rng.uniform(0.034, 0.044), pc, cc)
        # one broad leaf per stem
        la = a + rng.uniform(1.0, 2.2)
        spike(b, base, base + Vector((math.cos(la) * 0.10, math.sin(la) * 0.10, h * 0.62)), 0.03, "Grass", n=3,
              bend=Vector((math.cos(la) * 0.03, math.sin(la) * 0.03, 0)))


@nature("reeds", 19, "groundcover", tags=["reeds", "water_edge", "marsh"], multimesh=True)
def reeds(b, lod):
    rng = random.Random(841)
    bm = b.bm
    for k in range(9):
        a = TAU * k / 9 + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.05, 0.32) if k else 0.0
        base = Vector((math.cos(a) * d, math.sin(a) * d, -0.08))
        h = rng.uniform(1.25, 1.95)
        lean = rng.uniform(0.02, 0.16) * h
        top = base + Vector((math.cos(a) * lean, math.sin(a) * lean, h))
        if k % 2 == 0:
            ax = (top - base).normalized()
            h0 = top - ax * 0.30
            tube(bm, [base, h0], [0.016, 0.011], n=4, mat=b.m("Olive"))
            tube(bm, [h0, h0 + ax * 0.03, h0 + ax * 0.20, h0 + ax * 0.23], [0.014, 0.034, 0.034, 0.014], n=5,
                 mat=b.m("WoodDark"), ref=ax.orthogonal())
            spike(b, h0 + ax * 0.22, top + ax * 0.06, 0.008, "Olive", n=3)
        else:
            bend = Vector((math.cos(a) * lean * 0.5, math.sin(a) * lean * 0.5, 0.05))
            tip = base + Vector((math.cos(a) * lean * 2.6, math.sin(a) * lean * 2.6, h * 0.86))
            spike(b, base, tip, 0.024, "GrassDark" if k % 4 == 1 else "Olive", n=3, bend=bend, r_mid=0.7)
    _tuft(b, rng, 6, 0.30, 0.25, 0.5, 0.03, ["GrassDark", "Olive"])


# =================================================================================================
# ROCKS / CLIFFS / LOG
# =================================================================================================
@nature("rock_a", 20, "rock", collision_radius=0.0, tags=["rock", "small"])
def rock_a(b, lod):
    rock(b, (0, 0, 0), (0.58, 0.46, 0.36), 901, n=12)


@nature("rock_b", 21, "rock", collision_radius=0.36, collision="blob", tags=["rock", "small"])
def rock_b(b, lod):
    rock(b, (0, 0, 0), (0.95, 0.78, 0.56), 912, n=15)
    rock(b, (0.42, -0.30, 0), (0.36, 0.30, 0.22), 913, n=10)


@nature("rock_c", 22, "rock", collision_radius=0.58, collision="blob", tags=["rock", "medium", "mossy"])
def rock_c(b, lod):
    rock(b, (0, 0, 0), (1.55, 1.25, 0.98), 923, n=18, tones=("GrassDark", "Rock", "RockDark"), hi=0.93)
    rock(b, (-0.70, 0.45, 0), (0.6, 0.5, 0.36), 924, n=11)


@nature("rock_d", 23, "rock", collision_radius=0.85, collision="blob", tags=["rock", "large"])
def rock_d(b, lod):
    rock(b, (0, 0, 0), (2.15, 1.75, 1.55), 934, n=22)
    rock(b, (1.0, 0.55, 0), (1.0, 0.85, 0.62), 935, n=14, rot_z=0.6)
    rock(b, (-0.95, -0.6, 0), (0.6, 0.5, 0.34), 936, n=10)


@nature("rock_e", 24, "rock", collision_radius=1.30, collision="blob", tags=["rock", "boulder", "coast", "hill"])
def rock_e(b, lod):
    rock(b, (0, 0, 0), (3.1, 2.6, 2.35), 945, n=26, sink=0.06)
    rock(b, (1.55, -0.75, 0), (1.7, 1.4, 1.15), 946, n=16, rot_z=0.9)
    rock(b, (-1.45, 0.85, 0), (1.25, 1.0, 0.75), 947, n=14, rot_z=2.0, tones=("GrassDark", "Rock", "RockDark"), hi=0.93)
    rock(b, (0.5, 1.6, 0), (0.7, 0.55, 0.4), 948, n=10)


def crag(b, seed, W, yb, Dy, levels, N=16, cx=0.0, dirt_rows=(), grass_z=None, col_amp=0.15, v_amp=0.07, x_keep=0.5):
    """Faceted cliff / crag: jagged contour rings stacked with ledges. Flat back at y = yb (to be
    buried in the hillside), cliff face towards +Y. levels = [(z, scale)], scale shrinks the contour
    towards the back-centre. Quads are split along random diagonals for an irregular faceted look."""
    rng = random.Random(seed)
    bm = b.bm
    M = N - 3                       # points on the front arc (incl. both back corners)
    colf = [rng.uniform(1.0 - col_amp, 1.0 + col_amp) for _ in range(M)]
    colf[0] = colf[-1] = 1.0
    rings = []
    for li, (z, sc) in enumerate(levels):
        ring = []
        sx = 1.0 - (1.0 - sc) * x_keep
        for i in range(M):
            a = math.pi * i / (M - 1)
            px = math.cos(a) * W * 0.5
            py = (max(0.0, math.sin(a)) ** 0.75) * Dy
            k = colf[i] * (1.0 + (rng.uniform(-v_amp, v_amp) if 0 < i < M - 1 else 0.0))
            zz = z + (rng.uniform(-0.16, 0.16) if (0 < li < len(levels) - 1 and 0 < i < M - 1) else 0.0)
            ring.append(bm.verts.new((cx + px * sx * (k if 0 < i < M - 1 else 1.0), yb + py * sc * k, zz)))
        for j in range(3):
            t = (j + 1) / 4.0
            ring.append(bm.verts.new((cx + (-W * 0.5 + W * t) * sx, yb, z)))
        rings.append(ring)
    faces = []
    rowof = {}
    for r in range(len(rings) - 1):
        lo_r, hi_r = rings[r], rings[r + 1]
        for i in range(N):
            j = (i + 1) % N
            a, c, d, e = lo_r[i], lo_r[j], hi_r[j], hi_r[i]
            if i >= M - 1:                      # back wall: plain quads
                fs = [bm.faces.new((a, c, d, e))]
            elif rng.random() < 0.5:
                fs = [bm.faces.new((a, c, d)), bm.faces.new((a, d, e))]
            else:
                fs = [bm.faces.new((a, c, e)), bm.faces.new((c, d, e))]
            for f in fs:
                rowof[f] = r
            faces.extend(fs)
    top = rings[-1]
    zt = levels[-1][0]
    ctr = bm.verts.new((cx, yb + Dy * levels[-1][1] * 0.42, zt + 0.10))
    caps = []
    for i in range(N):
        j = (i + 1) % N
        caps.append(bm.faces.new((top[i], top[j], ctr)))
    bm.faces.new(list(reversed(rings[0]))).material_index = b.m("RockDark")
    if grass_z is None:
        grass_z = zt - 0.6
    mg, mgd, ml, mm, md, mdirt = b.m("Grass"), b.m("GrassDark"), b.m("WarmGrey"), b.m("Rock"), b.m("RockDark"), b.m("Dirt")
    for f in faces + caps:
        f.normal_update()
        nz = f.normal.z
        zc = f.calc_center_median().z
        if nz > 0.70:
            f.material_index = (mg if nz > 0.9 else mgd) if zc > grass_z else ml
        elif rowof.get(f, -1) in dirt_rows:
            f.material_index = mdirt
        else:
            d = f.normal.dot(SUN_SIDE)
            f.material_index = ml if d > 0.62 else (md if d < 0.05 else mm)
    return rings


@nature("cliff_chunk_a", 25, "cliff", collision="trimesh", tags=["cliff", "hill", "coast"])
def cliff_chunk_a(b, lod):
    levels = [(-0.7, 1.0), (0.8, 0.98), (1.9, 0.94), (2.05, 0.83), (3.0, 0.82), (3.22, 0.80), (4.2, 0.77),
              (4.35, 0.66), (5.15, 0.63), (5.42, 0.52)]
    crag(b, 960, 6.6, -1.9, 3.7, levels, N=16, dirt_rows=(4,))
    for (x, y, sz, sd) in ((-2.1, 1.75, 2.1, 961), (1.9, 1.9, 1.5, 962), (0.2, 2.35, 0.9, 964)):
        rock(b, (x, y, 0), (sz, sz * 0.85, sz * 0.72), sd, n=14, rot_z=sd * 0.7)


@nature("cliff_chunk_b", 26, "cliff", collision="trimesh", tags=["cliff", "hill", "coast", "tall"])
def cliff_chunk_b(b, lod):
    levels = [(-0.8, 1.0), (1.0, 0.98), (2.3, 0.95), (2.5, 0.86), (3.6, 0.85), (3.85, 0.83), (4.9, 0.80), (5.05, 0.70),
              (6.1, 0.68), (6.3, 0.60), (7.25, 0.57), (7.55, 0.46)]
    crag(b, 970, 6.9, -2.1, 4.1, levels, N=17, cx=-0.55, dirt_rows=(4, 8))
    side = [(-0.8, 1.0), (0.9, 0.97), (2.0, 0.92), (2.15, 0.80), (3.3, 0.77), (3.45, 0.64), (4.3, 0.60), (4.6, 0.46)]
    crag(b, 976, 3.6, -2.1, 4.9, side, N=13, cx=2.25, dirt_rows=(), grass_z=3.9)
    for (x, y, sz, sd) in ((-2.9, 2.0, 2.2, 971), (0.0, 2.3, 1.3, 972), (3.2, 2.9, 1.5, 973)):
        rock(b, (x, y, 0), (sz, sz * 0.85, sz * 0.72), sd, n=14, rot_z=sd * 0.7)


@nature("log", 27, "log", collision_radius=0.0, collision="box", tags=["log", "wood", "hill", "beach"])
def log(b, lod):
    bm = b.bm
    mbk, mcut, mring = b.m("Trunk"), b.m("Wood"), b.m("WoodDark")
    z = 0.24
    pts = [(-1.30, 0.0, z + 0.02), (-0.45, 0.04, z), (0.45, 0.02, z - 0.01), (1.30, -0.05, z + 0.01)]
    tube(bm, pts, [0.285, 0.275, 0.265, 0.25], n=8, mat=mbk, ref=(0, 0, 1), cap_mat=mcut)
    # growth-ring discs on both cut faces
    tube(bm, [(-1.312, 0.0, z + 0.02), (-1.30, 0.0, z + 0.02)], [0.15, 0.15], n=8, mat=mring, ref=(0, 0, 1))
    tube(bm, [(1.30, -0.05, z + 0.01), (1.312, -0.05, z + 0.01)], [0.13, 0.13], n=8, mat=mring, ref=(0, 0, 1))
    # branch stubs
    tube(bm, [(-0.50, 0.03, z + 0.2), (-0.62, 0.20, z + 0.52)], [0.085, 0.07], n=5, mat=mbk, cap_mat=mcut)
    tube(bm, [(0.55, 0.0, z + 0.15), (0.70, -0.34, z + 0.32)], [0.075, 0.06], n=5, mat=mbk, cap_mat=mcut)
    # moss + shelf fungi
    blob(b, (0.05, 0.03, z + 0.24), 0.34, (1.5, 0.75, 0.22), sub=1, jitter=0.12, seed=981, tones=("Grass", "GrassDark", "GrassDark"), hi=0.7)
    for k, (x, s) in enumerate(((-0.95, 0.10), (-0.80, 0.075), (0.98, 0.085))):
        ring = [Vector((x + math.cos(TAU * i / 6) * s, 0.26 + (math.sin(TAU * i / 6) * s * 0.9 if math.sin(TAU * i / 6) > 0 else 0.0) - 0.02,
                        z + 0.02 + k * 0.05)) for i in range(6)]
        loft(bm, [ring], mat=b.m("Cream"), tip_end=ring[0].lerp(ring[3], 0.5) + Vector((0, 0.02, 0.05)),
             tip_start=ring[0].lerp(ring[3], 0.5) + Vector((0, 0, -0.03)), cap_mat=b.m("Peach"))


# =================================================================================================
# UNDERWATER
# =================================================================================================
def _coral_branch(b, rng, p0, d, length, r, depth, mi, mi_tip, n=5):
    bm = b.bm
    d = d.normalized()
    p1 = p0 + d * length
    if depth == 0:
        tube(bm, [p0, p1], [r, r * 0.8], n=n, row_mats=[mi_tip], tip_end=p1 + d * (r * 0.9), cap_mat=mi)
        return
    tube(bm, [p0, p1], [r, r * 0.82], n=n, mat=mi)
    perp = Matrix.Rotation(rng.uniform(0, TAU), 3, d) @ d.orthogonal().normalized()
    for k in range(2):
        ang = rng.uniform(0.38, 0.70) * (1 if k == 0 else -1)
        nd = Matrix.Rotation(ang, 3, perp) @ d
        nd = (nd + Vector((0, 0, 0.25))).normalized()
        _coral_branch(b, rng, p1 - d * (r * 0.3), nd, length * rng.uniform(0.62, 0.82), r * 0.74, depth - 1, mi, mi_tip, n)


@nature("coral_a", 30, "underwater", tags=["coral", "branching", "reef"])
def coral_a(b, lod):
    rng = random.Random(1001)
    rock(b, (0, 0, 0), (0.75, 0.62, 0.24), 1002, n=12, tones=("Rock", "RockDark", "RockDark"))
    mi, mt = b.m("Coral"), b.m("Peach")
    for k in range(4):
        a = TAU * k / 4 + rng.uniform(-0.3, 0.3)
        base = Vector((math.cos(a) * 0.14, math.sin(a) * 0.14, 0.10))
        d = Vector((math.cos(a) * 0.55, math.sin(a) * 0.55, 1.0))
        _coral_branch(b, rng, base, d, 0.36, 0.062, 2, mi, mt, n=5)
    _coral_branch(b, rng, Vector((0, 0, 0.12)), Vector((0.05, -0.05, 1.0)), 0.42, 0.07, 2, mi, mt, n=5)


def _sponge(b, base, top, r, keys, n=6):
    bm = b.bm
    base = Vector(base)
    top = Vector(top)
    ax = (top - base).normalized()
    u = ax.orthogonal().normalized()
    v = ax.cross(u)

    def ring(c, rr):
        return [c + u * (math.cos(TAU * i / n) * rr) + v * (math.sin(TAU * i / n) * rr) for i in range(n)]
    mo, mi, mc = b.m(keys[0]), b.m(keys[1]), b.m(keys[2])
    secs = [ring(base, r * 0.75), ring(base.lerp(top, 0.6), r * 0.95), ring(top, r * 1.1), ring(top, r * 0.72), ring(top - ax * (r * 1.3), r * 0.6)]
    loft(bm, secs, row_mats=[mo, mo, mo, mi], cap_mat=mc)


@nature("coral_b", 31, "underwater", tags=["coral", "dome", "sponge", "reef"])
def coral_b(b, lod):
    rock(b, (0.05, 0, 0), (1.05, 0.9, 0.22), 1011, n=12, tones=("Rock", "RockDark", "RockDark"))
    T = ("Lavender", "CarPurple", "CarPurple")
    blob(b, (-0.12, 0.05, 0.22), 0.36, (1.1, 1.0, 0.85), sub=2, jitter=0.10, seed=1012, tones=T, hi=0.45, flat_z=0.0)
    blob(b, (0.30, 0.28, 0.15), 0.22, (1, 1, 0.85), sub=1, jitter=0.10, seed=1013, tones=T, hi=0.45, flat_z=0.0)
    blob(b, (-0.42, -0.25, 0.12), 0.17, (1, 1, 0.85), sub=1, jitter=0.10, seed=1014, tones=("Rose", "CarPurple", "CarPurple"), hi=0.45, flat_z=0.0)
    K = ("CarYellow", "CarOrange", "Rust")
    _sponge(b, (0.36, -0.20, 0.05), (0.42, -0.26, 0.62), 0.085, K)
    _sponge(b, (0.24, -0.30, 0.05), (0.20, -0.42, 0.46), 0.07, K)
    _sponge(b, (0.48, -0.08, 0.05), (0.60, -0.04, 0.40), 0.06, K)
    _sponge(b, (0.30, -0.12, 0.05), (0.27, -0.10, 0.84), 0.075, K)


def _plate(b, c, R, stalk_h, tilt, seed, keys, n=10):
    bm = b.bm
    rng = random.Random(seed)
    mk = b.mark()
    ph = rng.uniform(0, TAU)

    def ring(rr, z, wav):
        return [Vector((math.cos(TAU * i / n) * rr * (1.0 + wav * math.sin(3 * TAU * i / n + ph)),
                        math.sin(TAU * i / n) * rr * (1.0 + wav * math.sin(3 * TAU * i / n + ph)),
                        z + wav * 0.6 * R * math.sin(2 * TAU * i / n + ph))) for i in range(n)]
    m_st, m_un, m_rim, m_top = b.m(keys[0]), b.m(keys[1]), b.m(keys[2]), b.m(keys[3])
    secs = [ring(R * 0.16, -0.05, 0.0), ring(R * 0.13, stalk_h * 0.8, 0.0), ring(R * 0.92, stalk_h, 0.10), ring(R, stalk_h + 0.035, 0.10),
            ring(R * 0.60, stalk_h + 0.015, 0.05)]
    loft(bm, secs, row_mats=[m_st, m_un, m_rim, m_top], tip_end=(0, 0, stalk_h - 0.03), cap_mat=m_st)
    vs = b.since(mk)
    rot_about(vs, (0, 0, 0), tilt)
    xform(vs, Matrix.Translation(Vector(c)))


@nature("coral_c", 32, "underwater", tags=["coral", "plate", "reef"])
def coral_c(b, lod):
    rock(b, (0, 0, 0), (0.95, 0.85, 0.22), 1021, n=12, tones=("Rock", "RockDark", "RockDark"))
    K = ("CarTeal", "Teal", "Mint", "Mint")
    _plate(b, (0.0, 0.0, 0.08), 0.52, 0.52, (0.10, 0.06, 0.0), 1022, K)
    _plate(b, (0.38, -0.22, 0.05), 0.34, 0.26, (-0.16, 0.20, 0.5), 1023, K)
    _plate(b, (-0.36, 0.26, 0.05), 0.30, 0.34, (0.22, -0.18, 1.1), 1024, K)
    _plate(b, (-0.10, -0.42, 0.04), 0.22, 0.15, (-0.25, -0.05, 2.0), 1025, ("CarOrange", "CarOrange", "CarYellow", "CarYellow"), n=8)


@nature("kelp_a", 33, "underwater", tags=["kelp", "tall", "sway"])
def kelp_a(b, lod):
    rng = random.Random(1031)
    bm = b.bm
    rock(b, (0, 0, 0), (0.7, 0.6, 0.22), 1032, n=10, tones=("Rock", "RockDark", "RockDark"))
    ms = b.m("OliveDrab")
    mbulb = b.m("Mustard")
    for s, (bx, by, H) in enumerate(((0.0, 0.0, 4.9), (0.22, -0.12, 3.7), (-0.20, 0.14, 2.6))):
        ph = rng.uniform(0, TAU)
        amp = 0.24 + 0.04 * s
        segs = 9 if s == 0 else (7 if s == 1 else 5)
        pts = []
        for i in range(segs + 1):
            t = i / segs
            z = 0.05 + H * t
            pts.append(Vector((bx + amp * math.sin(z * 1.5 + ph) * t ** 0.5, by + amp * 0.8 * math.cos(z * 1.2 + ph) * t ** 0.5, z)))
        radii = [0.05 - 0.028 * (i / segs) for i in range(segs + 1)]
        tube(bm, pts[:-1], radii[:-1], n=4, mat=ms, tip_end=pts[-1])
        for i in range(1, segs + 1):
            yaw = ph + i * 2.4
            L = (1.05 - 0.035 * i) * (1.0 if s == 0 else 0.85)
            base = pts[i] if i < segs else pts[i] - Vector((0, 0, 0.12))
            frond(b, base, yaw, L, 1.05 + rng.uniform(-0.15, 0.15), 0.35 + rng.uniform(-0.2, 0.2), 0.135, segs=3,
                  top=("Olive" if i % 2 else "GrassDark"), bot="Olive", thick=0.015, edge_drop=0.22, stem=0.22, peak=0.42, curve_pow=1.0)
            if i % 2 == 1 and i < segs:
                c = pts[i] + Vector((math.cos(yaw) * 0.07, math.sin(yaw) * 0.07, 0.03))
                ring = [c + Vector((math.cos(TAU * j / 4) * 0.055, math.sin(TAU * j / 4) * 0.055, 0)) for j in range(4)]
                loft(bm, [ring], mat=mbulb, tip_end=c + Vector((0, 0, 0.075)), tip_start=c - Vector((0, 0, 0.06)))


@nature("seashell", 34, "underwater", tags=["shell", "beach", "collectible_look"])
def seashell(b, lod):
    bm = b.bm
    mk = b.mark()
    m1, m2, mu = b.m("Cream"), b.m("Peach"), b.m("Sand")
    ribs = 9
    R = 0.15
    H = bm.verts.new((0, -0.02, 0.012))
    H0 = bm.verts.new((0, -0.02, 0.0))
    mids, outs, base = [], [], []
    for k in range(ribs):
        a = math.radians(-66 + 132 * k / (ribs - 1)) + math.pi / 2
        ridge = (k % 2 == 0)
        d = Vector((math.cos(a), math.sin(a), 0))
        mids.append(bm.verts.new(d * (R * 0.55) + Vector((0, -0.02, 0.055 if ridge else 0.040))))
        outs.append(bm.verts.new(d * (R * (1.0 if ridge else 0.94)) + Vector((0, -0.02, 0.018 if ridge else 0.008))))
        base.append(bm.verts.new(d * (R * (1.0 if ridge else 0.94)) + Vector((0, -0.02, 0.0))))
    for k in range(ribs - 1):
        mi = m1 if (k // 2) % 2 == 0 else m2
        for f in (bm.faces.new((H, mids[k], mids[k + 1])), bm.faces.new((mids[k], outs[k], outs[k + 1], mids[k + 1])),
                  bm.faces.new((outs[k], base[k], base[k + 1], outs[k + 1]))):
            f.material_index = mi
        f = bm.faces.new((H0, base[k + 1], base[k]))
        f.material_index = mu
    for (a, c, d2, e) in ((H, H0, base[0], outs[0]), (H, outs[-1], base[-1], H0)):
        f = bm.faces.new((a, c, d2, e))
        f.material_index = m1
    f = bm.faces.new((H, outs[0], mids[0]))
    f.material_index = m1
    f = bm.faces.new((H, mids[-1], outs[-1]))
    f.material_index = m1
    # hinge ears
    G.add_box(bm, (0.075, 0.03, 0.016), (0, -0.028, 0.008), mat_index=m2)
    vs = b.since(mk)
    rot_about(vs, (0, 0, 0), (math.radians(14), math.radians(-5), 0.3))
    xform(vs, Matrix.Translation((0.02, 0.0, 0.012)))
    # small turret shell next to it
    mk = b.mark()
    secs = []
    for i, (z, r) in enumerate(((0.0, 0.034), (0.03, 0.036), (0.032, 0.026), (0.058, 0.027), (0.06, 0.018), (0.082, 0.018), (0.084, 0.010))):
        secs.append([Vector((math.cos(TAU * j / 6 + i * 0.3) * r, math.sin(TAU * j / 6 + i * 0.3) * r, z)) for j in range(6)])
    mr, mc = b.m("Rose"), b.m("Cream")
    loft(bm, secs, row_mats=[mr, mc, mr, mc, mr, mc], tip_end=(0, 0, 0.108), cap_mat=mc)
    vs = b.since(mk)
    rot_about(vs, (0, 0, 0), (math.radians(78), 0, math.radians(-40)))
    xform(vs, Matrix.Translation((-0.13, 0.07, 0.03)))


@nature("starfish", 35, "underwater", tags=["starfish", "beach", "reef"])
def starfish(b, lod):
    bm = b.bm
    ma, mb2, mu = b.m("CarOrange"), b.m("Awning"), b.m("Peach")
    R, r, w = 0.20, 0.082, 0.036
    C = bm.verts.new((0, 0, 0.050))
    C0 = bm.verts.new((0, 0, 0.0))
    arms, inner = [], []
    for k in range(5):
        a = TAU * k / 5 + math.pi / 2 + (0.12 if k == 1 else (-0.10 if k == 3 else 0.0))
        Rk = R * (0.92 if k == 2 else (1.05 if k == 4 else 1.0))
        d = Vector((math.cos(a), math.sin(a), 0))
        sd = Vector((-d.y, d.x, 0))
        M = bm.verts.new(d * (Rk * 0.50) + Vector((0, 0, 0.036)))
        T = bm.verts.new(d * Rk + Vector((0, 0, 0.006 if k != 4 else 0.03)))
        TL = bm.verts.new(d * (Rk * 0.88) - sd * w)
        TR = bm.verts.new(d * (Rk * 0.88) + sd * w)
        arms.append((M, T, TL, TR))
        ai = TAU * (k + 0.5) / 5 + math.pi / 2
        inner.append(bm.verts.new((math.cos(ai) * r, math.sin(ai) * r, 0.0)))
    for k in range(5):
        M, T, TL, TR = arms[k]
        ip, ic = inner[(k - 1) % 5], inner[k]
        for vs, mi in (((C, ip, M), ma), ((C, M, ic), mb2), ((M, ip, TL, T), ma), ((M, T, TR, ic), mb2)):
            f = bm.faces.new(vs)
            f.material_index = mi
        for vs in ((C0, TL, ip), (C0, T, TL), (C0, TR, T), (C0, ic, TR)):
            f = bm.faces.new(vs)
            f.material_index = mu
    # little knobs along the arms
    for k in range(5):
        M = arms[k][0]
        c = M.co * 0.55 + Vector((0, 0, 0.022))
        ring = [c + Vector((math.cos(TAU * j / 4) * 0.012, math.sin(TAU * j / 4) * 0.012, 0)) for j in range(4)]
        loft(bm, [ring], mat=b.m("Cream"), tip_end=c + Vector((0, 0, 0.014)), cap_start=True)


@nature("anchor", 36, "underwater", collision_radius=0.0, collision="box", tags=["anchor", "wreck", "marina"])
def anchor(b, lod):
    bm = b.bm
    rng = random.Random(1061)
    mk = b.mark()
    ms, mr = b.m("SteelDark"), b.m("Rust")
    # shank (octagonal beam) with a flared crown
    tube(bm, [(0, 0, 0.02), (0, 0, 0.22), (0, 0, 1.55), (0, 0, 1.68)], [(0.10, 0.075), (0.075, 0.06), (0.058, 0.048), (0.07, 0.055)],
         n=8, phase=0.5, mat=ms)
    # curved arms
    arm = [(-0.66, 0, 0.60), (-0.60, 0, 0.36), (-0.40, 0, 0.14), (-0.14, 0, 0.03), (0.14, 0, 0.03), (0.40, 0, 0.14), (0.60, 0, 0.36), (0.66, 0, 0.60)]
    tube(bm, arm, [(0.03, 0.035), (0.045, 0.045), (0.055, 0.05), (0.065, 0.055), (0.065, 0.055), (0.055, 0.05), (0.045, 0.045), (0.03, 0.035)],
         n=6, mat=ms, ref=(0, 1, 0))
    # flukes (spade plates)
    for sx in (-1, 1):
        prof = [(sx * 0.70, 0.78), (sx * 0.43, 0.40), (sx * 0.60, 0.30), (sx * 0.80, 0.42)]
        if sx < 0:
            prof = list(reversed(prof))
        G.add_prism(bm, prof, -0.035, 0.035, axis='Y', mat_index=mr)
    # stock (cross bar) with knobs
    tube(bm, [(0, -0.50, 1.50), (0, -0.44, 1.50), (0, 0.44, 1.50), (0, 0.50, 1.50)], [0.05, 0.036, 0.036, 0.05], n=6, mat=ms)
    # ring
    tube(bm, ring_path((0, 0, 1.80), 0.12, 8, axis='Y'), [0.022] * 9, n=4, mat=mr, ref=(0, 1, 0))
    # rust speckle
    for f in faces_of(b.since(mk)):
        if f.material_index == ms and rng.random() < 0.30:
            f.material_index = mr
    vs = b.since(mk)
    rot_about(vs, (0, 0, 0), Euler((math.radians(18), math.radians(58), math.radians(20)), 'XYZ').to_matrix())
    zmin = min(v.co.z for v in vs)
    xs = [v.co.x for v in vs]
    ys = [v.co.y for v in vs]
    xform(vs, Matrix.Translation((-(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, -zmin - 0.16)))
    # chain: links trailing from the ring to the sea bed
    ringc = max(vs, key=lambda v: v.co.z + 0.0).co.copy()
    top = max(vs, key=lambda v: v.co.x * 0.0 + v.co.z).co.copy()
    p = top + Vector((0.05, 0.0, -0.06))
    dirs = [Vector((0.35, 0.25, -0.9)), Vector((0.45, 0.30, -0.8)), Vector((0.7, 0.4, -0.5)), Vector((0.9, 0.3, -0.1)), Vector((0.9, 0.1, 0.0))]
    for i, d in enumerate(dirs):
        d = d.normalized()
        c = p + d * 0.075
        if c.z < 0.03:
            c.z = 0.03
        side = d.cross(Vector((0, 0, 1)) if i % 2 == 0 else Vector((0, 1, 0.2))).normalized()
        up = d.cross(side).normalized()
        pts = [c + d * (math.cos(TAU * j / 6) * 0.085) + side * (math.sin(TAU * j / 6) * 0.05) for j in range(7)]
        tube(bm, pts, [0.016] * 7, n=4, mat=(ms if i % 2 else mr), ref=up)
        p = c + d * 0.06
    # algae on the sea-bed side
    blob(b, (0.0, 0.05, 0.02), 0.22, (1.4, 1.0, 0.25), sub=1, jitter=0.15, seed=1062, tones=("Olive", "OliveDrab", "OliveDrab"), hi=0.6, flat_z=-0.05)


@nature("sunken_crate", 37, "underwater", collision_radius=0.0, collision="box", tags=["crate", "wreck", "treasure_look"])
def sunken_crate(b, lod):
    bm = b.bm
    rng = random.Random(1071)
    mk = b.mark()
    mf, mp, mp2, mi = b.m("WoodDark"), b.m("Wood"), b.m("Trunk"), b.m("Black")
    S = 1.0
    h = S / 2
    t = 0.085
    # dark interior
    G.add_box(bm, (S - 0.10, S - 0.10, S - 0.10), (0, 0, h), mat_index=mi)
    # frame: 4 posts + 8 rails
    for sx in (-1, 1):
        for sy in (-1, 1):
            G.add_box(bm, (t, t, S), (sx * (h - t / 2), sy * (h - t / 2), h), mat_index=mf)
    for sz in (t / 2, S - t / 2):
        for s in (-1, 1):
            G.add_box(bm, (S - 2 * t, t, t), (0, s * (h - t / 2), sz), mat_index=mf)
            G.add_box(bm, (t, S - 2 * t, t), (s * (h - t / 2), 0, sz), mat_index=mf)
    # side planks (vertical), 4 per side; one missing, one snapped
    pw = (S - 2 * t) / 4
    for side in range(4):
        for k in range(4):
            if side == 0 and k == 1:
                continue
            u = -h + t + pw * (k + 0.5)
            ph, pz = S - 2 * t, h
            if side == 0 and k == 2:
                ph, pz = (S - 2 * t) * 0.45, t + (S - 2 * t) * 0.225
            mat_i = mp if (side + k) % 3 else mp2
            off = h - 0.035
            if side == 0:
                G.add_box(bm, (pw - 0.012, 0.03, ph), (u, off, pz), mat_index=mat_i)
            elif side == 1:
                G.add_box(bm, (pw - 0.012, 0.03, ph), (u, -off, pz), mat_index=mat_i)
            elif side == 2:
                G.add_box(bm, (0.03, pw - 0.012, ph), (off, u, pz), mat_index=mat_i)
            else:
                G.add_box(bm, (0.03, pw - 0.012, ph), (-off, u, pz), mat_index=mat_i)
    # lid: 4 planks, two slid open
    for k in range(4):
        u = -h + t + pw * (k + 0.5)
        if k == 0:
            G.add_box(bm, (pw - 0.012, S - 0.02, 0.03), (u - 0.10, 0.16, S + 0.03), rot=(0.0, -0.22, 0.25), mat_index=mp)
        elif k == 1:
            continue
        else:
            G.add_box(bm, (pw - 0.012, S - 0.02, 0.03), (u, 0.0, S + 0.015), mat_index=(mp2 if k == 2 else mp))
    # diagonal brace on the back
    G.add_box(bm, (0.09, 0.03, S * 1.05), (0, -(h + 0.005), h), rot=(0, math.radians(38), 0), mat_index=mf)
    # coins inside / spilling from the open side
    mg = b.m("BadgeGold")
    for k in range(7):
        if k < 4:
            c = Vector((rng.uniform(-0.28, 0.05), rng.uniform(-0.2, 0.25), S - 0.14 + 0.012 * k))
            tube(bm, [c, c + Vector((0.0, 0.0, 0.014))], [0.055, 0.055], n=7, mat=mg)
        else:
            c = Vector((-0.2 + 0.16 * (k - 4), h + 0.10 + 0.07 * (k - 4), 0.22))
            tube(bm, [c, c + Vector((0.004, 0.006, 0.014))], [0.055, 0.055], n=7, mat=mg)
    vs = b.since(mk)
    rot_about(vs, (0, 0, 0), Euler((math.radians(-13), math.radians(9), math.radians(12)), 'XYZ').to_matrix())
    zmin = min(v.co.z for v in vs)
    xform(vs, Matrix.Translation((0, 0, -zmin - 0.20)))
    # algae / barnacles
    blob(b, (0.30, -0.28, 0.80), 0.20, (1.2, 1.0, 0.35), sub=1, jitter=0.15, seed=1072, tones=("Olive", "OliveDrab", "OliveDrab"), hi=0.5)
    blob(b, (-0.52, 0.30, 0.10), 0.24, (1.0, 1.2, 0.5), sub=1, jitter=0.15, seed=1073, tones=("Olive", "OliveDrab", "OliveDrab"), hi=0.5, flat_z=-0.05)
    rock(b, (0.62, 0.50, 0.0), (0.42, 0.36, 0.26), 1074, n=10)


# =================================================================================================
# ANIMALS  (rigid parts for procedural animation; origins at the joints; facing +Y)
# =================================================================================================
class Parts:
    """Collects the rigid parts of one animal: [name, MB, pivot]."""

    def __init__(self):
        self.parts = []

    def part(self, name, pivot):
        b = MB()
        self.parts.append([name, b, Vector(pivot)])
        return b


def body_ring(y, zc, w, h, n=8, e=0.85):
    """Super-ellipse ring in the XZ plane (vertex on the spine and on the belly line)."""
    pts = []
    for i in range(n):
        a = TAU * i / n
        s, c = math.sin(a), math.cos(a)
        x = (abs(s) ** e) * (1 if s >= 0 else -1) * w * 0.5
        z = (abs(c) ** e) * (1 if c >= 0 else -1) * h * 0.5
        pts.append(Vector((x, y, zc + z)))
    return pts


def body_loft(b, secs, key, n=8, e=0.85):
    """Torso from (y, z_centre, width, height[, exponent]) sections ordered rear -> front."""
    rings = [body_ring(q[0], q[1], q[2], q[3], n, q[4] if len(q) > 4 else e) for q in secs]
    mk = b.mark()
    loft(b.bm, rings, mat=b.m(key))
    return b.since(mk)


def paint(b, verts, key, pred):
    mi = b.m(key)
    for f in faces_of(verts):
        f.normal_update()
        if pred(f.calc_center_median(), f.normal):
            f.material_index = mi


def limb(b, path, radii, key, sx=1, n=6, ref=(1, 0, 0), tip=None, **kw):
    """Tube along a path given for the +X side (sx = -1 mirrors it)."""
    pts = [Vector((q[0] * sx, q[1], q[2])) for q in path]
    mk = b.mark()
    if tip is not None:
        kw['tip_end'] = Vector((tip[0] * sx, tip[1], tip[2]))
    tube(b.bm, pts, radii, n=n, mat=b.m(key), ref=ref, **kw)
    return b.since(mk)


def ear(b, base, tip, width, depth, key_out, key_in, facing=(0, 1, 0), sx=1, bulge=0.6, at=0.4):
    base = Vector((base[0] * sx, base[1], base[2]))
    tip = Vector((tip[0] * sx, tip[1], tip[2]))
    fc = Vector((facing[0] * sx, facing[1], facing[2]))
    t = (tip - base).normalized()
    u = fc.cross(t)
    if u.length < 1e-5:
        u = t.orthogonal()
    u.normalize()
    v = t.cross(u).normalized()
    mid = base.lerp(tip, at)
    r0 = [base + u * (width * 0.5), base + v * (depth * 0.5), base - u * (width * 0.5), base - v * (depth * 0.5)]
    r1 = [mid + u * (width * bulge), mid + v * (depth * 0.5), mid - u * (width * bulge), mid - v * (depth * 0.5)]
    mo, mi = b.m(key_out), b.m(key_in)
    loft(b.bm, [r0, r1], col_mats=[mi, mi, mo, mo], tip_end=tip, cap_mat=mo)


def gem(b, c, r, key, axis=(1, 0, 0), n=4, flat=0.6):
    """Tiny bipyramid: eyes, noses, tags."""
    c = Vector(c)
    t = Vector(axis).normalized()
    u = t.orthogonal().normalized()
    v = t.cross(u)
    ring = [c + u * (math.cos(TAU * i / n) * r) + v * (math.sin(TAU * i / n) * r) for i in range(n)]
    loft(b.bm, [ring], mat=b.m(key), tip_end=c + t * (r * flat), tip_start=c - t * (r * flat))


def eyes(b, x, y, z, r, key="Black"):
    gem(b, (x, y, z), r, key, axis=(1, 0.25, 0.1))
    gem(b, (-x, y, z), r, key, axis=(-1, 0.25, 0.1))


def paw(b, x, y, w, l, h, key, sx=1):
    G.add_tapered_box(b.bm, (w, l), (w * 0.78, l * 0.62), h, center=(x * sx, y + l * 0.22, 0.0), top_offset=(0, -l * 0.14),
                      mat_index=b.m(key))


def spine_spike(b, c, w, l, h, lean, key):
    c = Vector(c)
    ring = [c + Vector((w * 0.5, 0, 0)), c + Vector((0, l * 0.5, 0)), c + Vector((-w * 0.5, 0, 0)), c + Vector((0, -l * 0.5, 0))]
    loft(b.bm, [ring], mat=b.m(key), tip_end=c + Vector((0, -lean, h)), cap_start=True)


def fin(b, le, te, tip, thick, key, mid=0.5, te_mid=None, sx=1):
    """Fin / wing lobe from a root chord (leading -> trailing edge) to a tip; diamond section."""
    le = Vector((le[0] * sx, le[1], le[2]))
    te = Vector((te[0] * sx, te[1], te[2]))
    tip = Vector((tip[0] * sx, tip[1], tip[2]))
    c0 = (le + te) * 0.5
    nrm = (te - le).cross(tip - c0).normalized()
    le1 = le.lerp(tip, mid)
    te1 = Vector((te_mid[0] * sx, te_mid[1], te_mid[2])) if te_mid is not None else te.lerp(tip, mid)
    c1 = (le1 + te1) * 0.5
    r0 = [le, c0 + nrm * (thick * 0.5), te, c0 - nrm * (thick * 0.5)]
    r1 = [le1, c1 + nrm * (thick * 0.28), te1, c1 - nrm * (thick * 0.28)]
    mk = b.mark()
    loft(b.bm, [r0, r1], mat=b.m(key), tip_end=tip)
    return b.since(mk)


def collar(b, c, axis, radius, r, key, seg=8, n=4):
    c = Vector(c)
    t = Vector(axis).normalized()
    u = Vector((1, 0, 0))
    v = t.cross(u).normalized()
    pts = [c + u * (math.cos(TAU * i / seg) * radius[0]) + v * (math.sin(TAU * i / seg) * radius[1]) for i in range(seg)]
    tube(b.bm, pts, [r] * seg, n=n, mat=b.m(key), ref=t, cyclic=True)


def leg_path(path, radii):
    """Add a tapered top above the hip so the leg blends into the body like a muscle (no flat cap)."""
    x, y, z = path[0]
    r = radii[0]
    ra, rb = r if isinstance(r, (tuple, list)) else (r, r)
    return [(x * 0.78, y, z + rb * 0.75)] + list(path), [(ra * 0.5, rb * 0.55)] + list(radii)


def _legs(A, front, front_r, hind, hind_r, key, foot_key, foot_h, n=6, paw_dims=None):
    """Four leg parts from the +X side paths. Hoofed animals: faces below foot_h get foot_key.
    paw_dims = (w, l, h): adds a paw block under the last path point."""
    for name, path0, radii0, sx in (("Leg_FL", front, front_r, -1), ("Leg_FR", front, front_r, 1),
                                    ("Leg_RL", hind, hind_r, -1), ("Leg_RR", hind, hind_r, 1)):
        b = A.part(name, (path0[0][0] * sx, path0[0][1], path0[0][2]))
        path, radii = leg_path(path0, radii0)
        vs = limb(b, path, radii, key, sx=sx, n=n)
        if paw_dims is not None:
            paw(b, path[-1][0], path[-1][1], paw_dims[0], paw_dims[1], paw_dims[2], foot_key, sx=sx)
            if foot_key != key and foot_h > 0:
                paint(b, vs, foot_key, lambda c, nn: c.z < foot_h)
        else:
            paint(b, vs, foot_key, lambda c, nn: c.z < foot_h)


# ---- deer ---------------------------------------------------------------------------------------
@animal("deer", 0, "land", shoulder_height=1.02, walk_speed=1.4, run_speed=11.0, tags=["hill", "grazer", "flees"])
def deer(A):
    CB, CL, CH = "TrunkLight", "Cream", "Black"
    b = A.part("Body", (0, -0.05, 0.80))
    vs = body_loft(b, [(-0.62, 0.86, 0.07, 0.10), (-0.55, 0.83, 0.28, 0.32), (-0.40, 0.80, 0.39, 0.46), (-0.14, 0.775, 0.37, 0.43),
                       (0.11, 0.765, 0.39, 0.48), (0.32, 0.785, 0.37, 0.51), (0.46, 0.83, 0.26, 0.41), (0.54, 0.88, 0.13, 0.23)], CB)
    paint(b, vs, CL, lambda c, n: (c.z < 0.69 and n.z < 0.1) or (c.y < -0.53 and c.z < 0.86))
    paint(b, vs, "Trunk", lambda c, n: n.z > 0.80 and c.y < 0.40)

    h = A.part("Head", (0, 0.44, 0.92))
    nk = limb(h, [(0, 0.42, 0.86), (0, 0.58, 1.10), (0, 0.69, 1.33)], [(0.125, 0.165), (0.095, 0.12), (0.075, 0.09)], CB, n=8)
    paint(h, nk, CL, lambda c, n: n.y > 0.45 and n.z < 0.2 and c.z > 1.05)
    hd = limb(h, [(0, 0.63, 1.42), (0, 0.74, 1.44), (0, 0.88, 1.385), (0, 0.985, 1.335)],
              [(0.062, 0.066), (0.086, 0.09), (0.060, 0.064), (0.040, 0.044)], CB, n=8)
    paint(h, hd, CL, lambda c, n: c.y > 0.80 and n.z < -0.2)
    paint(h, hd, CH, lambda c, n: c.y > 0.975)
    eyes(h, 0.079, 0.775, 1.458, 0.021)
    for sx in (-1, 1):
        ear(h, (0.065, 0.68, 1.49), (0.215, 0.62, 1.60), 0.085, 0.03, CB, CL, facing=(0.3, 1, 0.2), sx=sx)
        # antlers: main beam + three tines
        K = "Khaki"
        limb(h, [(0.045, 0.70, 1.50), (0.12, 0.655, 1.66), (0.225, 0.69, 1.80)], [0.024, 0.021, 0.016], K, sx=sx, n=4,
             tip=(0.215, 0.80, 1.92))
        limb(h, [(0.055, 0.70, 1.53), (0.05, 0.78, 1.60)], [0.017, 0.012], K, sx=sx, n=4, tip=(0.045, 0.83, 1.68))
        limb(h, [(0.12, 0.655, 1.66), (0.11, 0.62, 1.78)], [0.017, 0.012], K, sx=sx, n=4, tip=(0.10, 0.63, 1.90))
        limb(h, [(0.225, 0.69, 1.80), (0.29, 0.66, 1.90)], [0.015, 0.011], K, sx=sx, n=4, tip=(0.33, 0.67, 2.00))

    _legs(A,
          [(0.12, 0.34, 0.78), (0.13, 0.32, 0.56), (0.125, 0.34, 0.34), (0.125, 0.33, 0.10), (0.125, 0.35, 0.055), (0.125, 0.365, 0.0)],
          [(0.07, 0.10), (0.05, 0.065), (0.033, 0.036), (0.026, 0.030), (0.034, 0.042), (0.038, 0.05)],
          [(0.13, -0.38, 0.80), (0.14, -0.34, 0.56), (0.13, -0.45, 0.34), (0.13, -0.42, 0.10), (0.13, -0.40, 0.055), (0.13, -0.385, 0.0)],
          [(0.085, 0.14), (0.055, 0.085), (0.034, 0.04), (0.026, 0.03), (0.034, 0.042), (0.038, 0.05)],
          CB, CH, 0.062)

    t = A.part("Tail", (0, -0.59, 0.90))
    tv = limb(t, [(0, -0.58, 0.91), (0, -0.67, 0.82)], [(0.05, 0.03), (0.06, 0.034)], "Trunk", n=6, tip=(0, -0.71, 0.65))
    paint(t, tv, "White", lambda c, n: n.y > 0.1 or n.z < -0.5)


# ---- boar ---------------------------------------------------------------------------------------
@animal("boar", 1, "land", shoulder_height=0.84, walk_speed=1.2, run_speed=8.0, tags=["hill", "charges"])
def boar(A):
    CB, CD, CM = "Trunk", "HairBrown", "HairBlack"
    b = A.part("Body", (0, 0.0, 0.54))
    vs = body_loft(b, [(-0.60, 0.54, 0.08, 0.10), (-0.52, 0.53, 0.26, 0.32), (-0.34, 0.52, 0.34, 0.44), (-0.05, 0.51, 0.38, 0.50),
                       (0.22, 0.53, 0.40, 0.58), (0.40, 0.55, 0.38, 0.60), (0.52, 0.54, 0.30, 0.50), (0.60, 0.52, 0.18, 0.34)], CB)
    paint(b, vs, CD, lambda c, n: c.z < 0.42 and n.z < 0.1)
    for i, y in enumerate((0.50, 0.38, 0.26, 0.14, 0.02, -0.10, -0.22)):
        zt = 0.845 - 0.012 * i - (0.02 * max(0, i - 3))
        spine_spike(b, (0, y, zt - 0.03), 0.07, 0.15, 0.115 - 0.008 * i, 0.06, CM)

    h = A.part("Head", (0, 0.52, 0.56))
    hd = limb(h, [(0, 0.48, 0.58), (0, 0.66, 0.545), (0, 0.86, 0.44), (0, 1.02, 0.365), (0, 1.06, 0.35)],
              [(0.15, 0.20), (0.14, 0.18), (0.085, 0.10), (0.055, 0.06), (0.062, 0.064)], CB, n=8)
    paint(h, hd, CD, lambda c, n: c.y > 0.80 and n.z < -0.1)
    paint(h, hd, "HairBlack", lambda c, n: c.y > 1.035)
    eyes(h, 0.118, 0.71, 0.615, 0.02)
    spine_spike(h, (0, 0.62, 0.70), 0.07, 0.14, 0.10, 0.05, CM)
    spine_spike(h, (0, 0.74, 0.655), 0.06, 0.12, 0.07, 0.04, CM)
    for sx in (-1, 1):
        ear(h, (0.10, 0.57, 0.72), (0.175, 0.52, 0.87), 0.10, 0.03, CB, CD, facing=(0.4, 1, 0), sx=sx)
        limb(h, [(0.062, 0.90, 0.385), (0.095, 0.945, 0.42)], [0.017, 0.014], "Cream", sx=sx, n=4, tip=(0.105, 0.935, 0.50))

    _legs(A,
          [(0.13, 0.40, 0.54), (0.14, 0.39, 0.32), (0.135, 0.40, 0.13), (0.135, 0.41, 0.055), (0.135, 0.42, 0.0)],
          [(0.085, 0.115), (0.052, 0.062), (0.035, 0.04), (0.042, 0.05), (0.045, 0.056)],
          [(0.13, -0.38, 0.54), (0.145, -0.35, 0.34), (0.135, -0.43, 0.17), (0.135, -0.40, 0.055), (0.135, -0.39, 0.0)],
          [(0.095, 0.145), (0.058, 0.078), (0.035, 0.04), (0.042, 0.05), (0.045, 0.056)],
          CD, CM, 0.06)

    t = A.part("Tail", (0, -0.59, 0.58))
    limb(t, [(0, -0.58, 0.59), (0, -0.67, 0.52), (0, -0.69, 0.40)], [0.02, 0.014, 0.012], CD, n=4)
    blob(t, (0, -0.69, 0.365), 0.035, (1, 1, 1.6), sub=1, jitter=0.0, seed=1, tones=CM)


# ---- coyote -------------------------------------------------------------------------------------
@animal("coyote", 2, "land", shoulder_height=0.62, walk_speed=1.6, run_speed=10.0, tags=["hill", "predator", "skittish"])
def coyote(A):
    CB, CL = "Khaki", "Cream"
    b = A.part("Body", (0, -0.04, 0.50))
    vs = body_loft(b, [(-0.42, 0.52, 0.07, 0.09), (-0.35, 0.50, 0.19, 0.24), (-0.20, 0.49, 0.22, 0.27), (-0.02, 0.485, 0.215, 0.26),
                       (0.15, 0.47, 0.24, 0.32), (0.27, 0.48, 0.225, 0.31), (0.35, 0.51, 0.15, 0.22)], CB)
    paint(b, vs, CL, lambda c, n: n.z < -0.35)
    paint(b, vs, "HairGrey", lambda c, n: n.z > 0.72)

    h = A.part("Head", (0, 0.29, 0.56))
    nk = limb(h, [(0, 0.27, 0.53), (0, 0.40, 0.66), (0, 0.455, 0.735)], [(0.098, 0.122), (0.082, 0.096), (0.07, 0.078)], CB, n=8)
    paint(h, nk, CL, lambda c, n: n.y > 0.4 and n.z < 0.0)
    hd = limb(h, [(0, 0.41, 0.775), (0, 0.495, 0.792), (0, 0.60, 0.752), (0, 0.70, 0.724)],
              [(0.062, 0.062), (0.088, 0.08), (0.048, 0.047), (0.029, 0.030)], CB, n=8)
    paint(h, hd, CL, lambda c, n: c.y > 0.54 and n.z < 0.1)
    gem(h, (0, 0.706, 0.731), 0.025, "Black", axis=(0, 1, 0.1), n=5)
    eyes(h, 0.073, 0.535, 0.812, 0.015)
    for sx in (-1, 1):
        ear(h, (0.055, 0.455, 0.845), (0.098, 0.43, 0.985), 0.088, 0.028, "Rust", CL, facing=(0.25, 1, 0), sx=sx)
        # cheek ruff
        ear(h, (0.07, 0.47, 0.76), (0.115, 0.44, 0.715), 0.07, 0.03, CB, CL, facing=(0.3, 1, -0.3), sx=sx)

    _legs(A,
          [(0.078, 0.26, 0.47), (0.083, 0.25, 0.30), (0.078, 0.265, 0.16), (0.078, 0.26, 0.035)],
          [(0.052, 0.075), (0.035, 0.046), (0.026, 0.03), (0.023, 0.027)],
          [(0.083, -0.29, 0.49), (0.093, -0.25, 0.32), (0.083, -0.35, 0.18), (0.083, -0.32, 0.035)],
          [(0.058, 0.10), (0.039, 0.057), (0.026, 0.03), (0.023, 0.027)],
          CB, CL, 0.0, paw_dims=(0.058, 0.085, 0.042))

    t = A.part("Tail", (0, -0.41, 0.52))
    tv = limb(t, [(0, -0.40, 0.525), (0, -0.52, 0.43), (0, -0.60, 0.29)], [0.036, 0.078, 0.07], CB, n=6, tip=(0, -0.63, 0.09))
    paint(t, tv, "HairBlack", lambda c, n: c.z < 0.24)


# ---- dog ----------------------------------------------------------------------------------------
@animal("dog", 3, "land", shoulder_height=0.57, walk_speed=1.5, run_speed=8.5, tags=["city", "pet", "stray"])
def dog(A):
    CB, CL, CD = "Wood", "White", "WoodDark"
    b = A.part("Body", (0, -0.02, 0.43))
    vs = body_loft(b, [(-0.33, 0.445, 0.08, 0.10), (-0.27, 0.435, 0.20, 0.25), (-0.14, 0.425, 0.235, 0.28), (0.02, 0.42, 0.235, 0.28),
                       (0.16, 0.415, 0.255, 0.33), (0.25, 0.425, 0.235, 0.32), (0.32, 0.45, 0.16, 0.23)], CB)
    paint(b, vs, CL, lambda c, n: n.z < -0.35 or (c.y > 0.23 and n.z < 0.3))
    paint(b, vs, CD, lambda c, n: n.z > 0.5 and -0.28 < c.y < 0.05)

    h = A.part("Head", (0, 0.26, 0.50))
    nk = limb(h, [(0, 0.24, 0.48), (0, 0.35, 0.60), (0, 0.40, 0.67)], [(0.10, 0.115), (0.083, 0.094), (0.072, 0.078)], CB, n=8)
    paint(h, nk, CL, lambda c, n: n.y > 0.4 and n.z < 0.0)
    hd = limb(h, [(0, 0.355, 0.705), (0, 0.44, 0.722), (0, 0.53, 0.688), (0, 0.605, 0.665)],
              [(0.066, 0.066), (0.09, 0.084), (0.058, 0.054), (0.041, 0.04)], CB, n=8)
    paint(h, hd, CL, lambda c, n: c.y > 0.485)
    gem(h, (0, 0.612, 0.676), 0.029, "Black", axis=(0, 1, 0.15), n=5)
    eyes(h, 0.075, 0.475, 0.745, 0.016)
    # mongrel ears: right one flopped, left one half pricked
    ear(h, (0.07, 0.41, 0.785), (0.145, 0.455, 0.675), 0.085, 0.024, CD, CD, facing=(1, 0.2, 0.3), sx=1)
    ear(h, (0.066, 0.41, 0.785), (0.125, 0.405, 0.87), 0.075, 0.024, CD, CD, facing=(0.3, 1, 0), sx=-1)
    collar(h, (0, 0.315, 0.565), (0, 0.66, 0.75), (0.098, 0.106), 0.017, "CarRed")
    gem(h, (0, 0.392, 0.497), 0.024, "BadgeGold", axis=(0, 1, -0.4), n=6, flat=0.35)

    _legs(A,
          [(0.08, 0.24, 0.42), (0.085, 0.23, 0.27), (0.08, 0.245, 0.15), (0.08, 0.24, 0.035)],
          [(0.055, 0.075), (0.04, 0.05), (0.03, 0.034), (0.027, 0.03)],
          [(0.085, -0.24, 0.43), (0.095, -0.20, 0.29), (0.085, -0.29, 0.17), (0.085, -0.265, 0.035)],
          [(0.062, 0.10), (0.043, 0.06), (0.03, 0.034), (0.027, 0.03)],
          CB, CL, 0.13, paw_dims=(0.066, 0.09, 0.045))

    t = A.part("Tail", (0, -0.32, 0.46))
    tv = limb(t, [(0, -0.31, 0.455), (0, -0.40, 0.53), (0, -0.435, 0.63), (0, -0.39, 0.715)], [0.034, 0.032, 0.028, 0.024], CB, n=6,
              tip=(0, -0.30, 0.735))
    paint(t, tv, CL, lambda c, n: c.y > -0.38 and c.z > 0.66)


# ---- cat ----------------------------------------------------------------------------------------
@animal("cat", 4, "land", shoulder_height=0.265, walk_speed=1.0, run_speed=7.0, tags=["city", "pet", "stray"])
def cat(A):
    CB, CL = "Rust", "Cream"
    b = A.part("Body", (0, -0.01, 0.19))
    vs = body_loft(b, [(-0.20, 0.20, 0.045, 0.055), (-0.16, 0.195, 0.115, 0.135), (-0.07, 0.19, 0.135, 0.155), (0.04, 0.185, 0.135, 0.155),
                       (0.12, 0.188, 0.125, 0.155), (0.17, 0.20, 0.08, 0.11)], CB)
    paint(b, vs, CL, lambda c, n: n.z < -0.35 or (c.y > 0.13 and n.z < 0.3))

    h = A.part("Head", (0, 0.135, 0.225))
    limb(h, [(0, 0.125, 0.215), (0, 0.185, 0.265)], [(0.052, 0.056), (0.046, 0.048)], CB, n=6)
    hd = limb(h, [(0, 0.155, 0.29), (0, 0.21, 0.30), (0, 0.258, 0.287), (0, 0.288, 0.277)],
              [(0.042, 0.042), (0.068, 0.06), (0.05, 0.042), (0.026, 0.023)], CB, n=8)
    paint(h, hd, CL, lambda c, n: c.y > 0.245 and n.z < 0.3)
    gem(h, (0, 0.293, 0.281), 0.012, "Rose", axis=(0, 1, 0.1), n=4)
    eyes(h, 0.05, 0.248, 0.308, 0.013, "CarGreen")
    for sx in (-1, 1):
        ear(h, (0.04, 0.195, 0.345), (0.058, 0.19, 0.425), 0.055, 0.018, CB, "Rose", facing=(0.2, 1, 0), sx=sx)

    _legs(A,
          [(0.045, 0.13, 0.18), (0.047, 0.13, 0.10), (0.045, 0.135, 0.02)],
          [(0.03, 0.04), (0.021, 0.025), (0.019, 0.021)],
          [(0.05, -0.12, 0.185), (0.056, -0.10, 0.115), (0.048, -0.15, 0.062), (0.048, -0.135, 0.02)],
          [(0.036, 0.058), (0.025, 0.034), (0.018, 0.02), (0.018, 0.02)],
          CB, CL, 0.0, paw_dims=(0.042, 0.052, 0.026))

    t = A.part("Tail", (0, -0.195, 0.20))
    tv = limb(t, [(0, -0.19, 0.20), (0, -0.27, 0.215), (0, -0.325, 0.285), (0, -0.32, 0.38)], [0.022, 0.021, 0.019, 0.017], CB, n=5,
              tip=(0, -0.285, 0.44))
    paint(t, tv, CL, lambda c, n: c.z > 0.385)


# ---- rabbit -------------------------------------------------------------------------------------
@animal("rabbit", 5, "land", shoulder_height=0.17, walk_speed=0.8, run_speed=8.0, tags=["hill", "park", "flees"])
def rabbit(A):
    CB, CL = "WarmGrey", "White"
    b = A.part("Body", (0, -0.02, 0.105))
    vs = body_loft(b, [(-0.17, 0.10, 0.04, 0.05), (-0.13, 0.105, 0.11, 0.14), (-0.05, 0.112, 0.135, 0.175), (0.04, 0.10, 0.115, 0.14),
                       (0.10, 0.10, 0.09, 0.11), (0.14, 0.105, 0.05, 0.07)], CB)
    paint(b, vs, CL, lambda c, n: n.z < -0.4)

    h = A.part("Head", (0, 0.105, 0.125))
    limb(h, [(0, 0.095, 0.115), (0, 0.14, 0.165)], [(0.04, 0.045), (0.035, 0.036)], CB, n=6)
    hd = limb(h, [(0, 0.122, 0.185), (0, 0.16, 0.192), (0, 0.196, 0.18), (0, 0.216, 0.172)],
              [(0.03, 0.03), (0.043, 0.04), (0.031, 0.028), (0.017, 0.016)], CB, n=8)
    paint(h, hd, CL, lambda c, n: c.y > 0.19 and n.z < 0.2)
    gem(h, (0, 0.22, 0.175), 0.008, "Rose", axis=(0, 1, 0.1), n=4)
    eyes(h, 0.037, 0.176, 0.199, 0.009)
    for sx in (-1, 1):
        ear(h, (0.02, 0.142, 0.222), (0.032, 0.118, 0.34), 0.034, 0.014, CB, "Rose", facing=(0.5, 1, 0), sx=sx, bulge=0.62, at=0.55)

    for name, sx in (("Leg_FL", -1), ("Leg_FR", 1)):
        lb = A.part(name, (0.035 * sx, 0.09, 0.10))
        limb(lb, [(0.035, 0.09, 0.10), (0.036, 0.095, 0.05), (0.036, 0.10, 0.012)], [(0.02, 0.025), (0.014, 0.016), (0.013, 0.015)], CB, sx=sx, n=5)
        paw(lb, 0.036, 0.10, 0.028, 0.04, 0.018, CB, sx=sx)
    for name, sx in (("Leg_RL", -1), ("Leg_RR", 1)):
        lb = A.part(name, (0.055 * sx, -0.06, 0.12))
        limb(lb, [(0.055, -0.06, 0.125), (0.064, -0.04, 0.065), (0.058, -0.085, 0.022)], [(0.035, 0.062), (0.03, 0.046), (0.018, 0.02)], CB, sx=sx, n=6)
        G.add_tapered_box(lb.bm, (0.036, 0.115), (0.03, 0.09), 0.022, center=(0.058 * sx, -0.035, 0.0), mat_index=lb.m(CB))

    t = A.part("Tail", (0, -0.165, 0.11))
    blob(t, (0, -0.185, 0.118), 0.036, sub=1, jitter=0.06, seed=3, tones=CL)


# ---- cow ----------------------------------------------------------------------------------------
@animal("cow", 6, "land", shoulder_height=1.45, walk_speed=1.0, run_speed=4.5, tags=["farm", "grazer", "docile"])
def cow(A):
    CB, CK = "White", "Black"
    spots = [((0.30, -0.50, 1.32), 0.42), ((-0.33, 0.10, 1.28), 0.40), ((0.36, 0.48, 1.00), 0.32), ((-0.36, -0.78, 0.96), 0.32),
             ((0.0, 0.84, 1.40), 0.26), ((-0.1, -0.2, 0.62), 0.24)]

    def spotted(c, n):
        return any((c - Vector(sc)).length < sr for sc, sr in spots)

    b = A.part("Body", (0, -0.05, 1.08))
    vs = body_loft(b, [(-1.02, 1.22, 0.16, 0.20), (-0.92, 1.15, 0.52, 0.60), (-0.65, 1.08, 0.70, 0.80), (-0.25, 1.03, 0.76, 0.88),
                       (0.20, 1.04, 0.74, 0.86), (0.55, 1.08, 0.66, 0.80), (0.78, 1.13, 0.48, 0.64), (0.92, 1.16, 0.28, 0.42)],
                   CB, n=10, e=0.72)
    paint(b, vs, CK, spotted)
    blob(b, (0, -0.44, 0.63), 0.18, (1.0, 1.25, 0.8), sub=1, jitter=0.05, seed=5, tones="Rose")
    for sx in (-1, 1):
        for y in (-0.52, -0.36):
            spike(b, (0.07 * sx, y, 0.53), (0.075 * sx, y, 0.43), 0.022, "Rose", n=4)

    h = A.part("Head", (0, 0.80, 1.24))
    nk = limb(h, [(0, 0.76, 1.16), (0, 1.02, 1.29), (0, 1.15, 1.37)], [(0.21, 0.29), (0.16, 0.21), (0.13, 0.15)], CB, n=8)
    paint(h, nk, CK, lambda c, n: abs(c.x) > 0.05 and n.z > -0.2 and c.y < 1.0)
    hd = limb(h, [(0, 1.08, 1.44), (0, 1.20, 1.445), (0, 1.38, 1.335), (0, 1.52, 1.245), (0, 1.55, 1.225)],
              [(0.10, 0.11), (0.125, 0.12), (0.10, 0.095), (0.098, 0.082), (0.085, 0.07)], CB, n=8)
    paint(h, hd, CK, lambda c, n: abs(c.x) > 0.055 and c.y < 1.36)
    paint(h, hd, "Rose", lambda c, n: c.y > 1.47)
    eyes(h, 0.118, 1.255, 1.468, 0.022)
    gem(h, (0.04, 1.555, 1.25), 0.014, CK, axis=(0.2, 1, 0.2))
    gem(h, (-0.04, 1.555, 1.25), 0.014, CK, axis=(-0.2, 1, 0.2))
    for sx in (-1, 1):
        ear(h, (0.11, 1.12, 1.485), (0.31, 1.07, 1.455), 0.12, 0.03, CK, "Rose", facing=(0, 1, 0.3), sx=sx)
        limb(h, [(0.085, 1.15, 1.535), (0.19, 1.16, 1.60)], [0.032, 0.026], "Cream", sx=sx, n=5, tip=(0.235, 1.20, 1.71))
    G.add_box(h.bm, (0.012, 0.05, 0.06), (0.245, 1.105, 1.425), mat_index=h.m("CarYellow"))

    front = [(0.23, 0.60, 0.98), (0.24, 0.58, 0.70), (0.23, 0.60, 0.42), (0.23, 0.60, 0.14), (0.23, 0.61, 0.075), (0.23, 0.63, 0.0)]
    front_r = [(0.125, 0.17), (0.09, 0.115), (0.062, 0.068), (0.052, 0.058), (0.066, 0.08), (0.074, 0.096)]
    hind = [(0.24, -0.70, 1.03), (0.255, -0.64, 0.72), (0.24, -0.80, 0.45), (0.24, -0.76, 0.14), (0.24, -0.74, 0.075), (0.24, -0.72, 0.0)]
    hind_r = [(0.145, 0.22), (0.10, 0.145), (0.062, 0.072), (0.052, 0.058), (0.066, 0.08), (0.074, 0.096)]
    for name, path, radii, sx, dark in (("Leg_FL", front, front_r, -1, True), ("Leg_FR", front, front_r, 1, False),
                                        ("Leg_RL", hind, hind_r, -1, False), ("Leg_RR", hind, hind_r, 1, True)):
        lb = A.part(name, (path[0][0] * sx, path[0][1], path[0][2]))
        path, radii = leg_path(path, radii)
        lv = limb(lb, path, radii, CB, sx=sx, n=6)
        if dark:
            paint(lb, lv, CK, lambda c, n: c.z > 0.50)
        paint(lb, lv, "HairBlack", lambda c, n: c.z < 0.08)

    t = A.part("Tail", (0, -1.01, 1.30))
    limb(t, [(0, -1.00, 1.31), (0, -1.10, 1.12), (0, -1.125, 0.82), (0, -1.12, 0.60)], [0.036, 0.026, 0.02, 0.02], CB, n=5)
    blob(t, (0, -1.12, 0.52), 0.06, (1, 1, 1.9), sub=1, jitter=0.05, seed=7, tones=CK)


# ---- birds --------------------------------------------------------------------------------------
def _wing(b, sx, root, span, chord, sweep, rise, top, under, tipk, thick=0.014, tip_from=0.72):
    """Spread wing (rigid): diamond sections along the span, wrist kink forward, swept pointed tip."""
    rx, ry, rz = root
    st = [(0.0, 0.06, 0.0, 1.0), (0.22, 0.14, 0.45, 1.04), (0.44, 0.20, 1.0, 0.98), (0.70, 0.02, 0.85, 0.72), (0.90, -0.30, 0.55, 0.42)]
    secs = []
    for (f, fwd, up, cf) in st:
        x = rx + span * f
        yc = ry + sweep * fwd
        z = rz + rise * up
        c = chord * cf
        th = thick * (1.0 - 0.6 * f)
        secs.append([Vector((x * sx, yc + c * 0.5, z)), Vector((x * sx, yc + c * 0.1, z + th)),
                     Vector((x * sx, yc - c * 0.5, z)), Vector((x * sx, yc - c * 0.05, z - th * 0.6))])
    mt, mu = b.m(top), b.m(under)
    mk = b.mark()
    loft(b.bm, secs, col_mats=[mt, mt, mu, mu], tip_end=Vector(((rx + span) * sx, ry - sweep * 0.75, rz + rise * 0.30)), cap_mat=mu)
    vs = b.since(mk)
    lim = rx + span * tip_from
    paint(b, vs, tipk, lambda c, n: abs(c.x) > lim)
    return vs


def _bird(A, P):
    L = P['len']                     # body length (tail root -> breast)
    zb = P['body_z']                 # body centre height when standing
    W, Hh = P['body_w'], P['body_h']
    CB = P['body']
    b = A.part("Body", (0, 0, zb))
    vs = body_loft(b, [(-0.50 * L, zb - 0.02 * L, 0.10 * W, 0.12 * Hh), (-0.32 * L, zb - 0.01 * L, 0.62 * W, 0.58 * Hh),
                       (-0.05 * L, zb, 1.0 * W, 0.96 * Hh), (0.22 * L, zb + 0.02 * L, 0.96 * W, 1.0 * Hh),
                       (0.42 * L, zb + 0.06 * L, 0.60 * W, 0.72 * Hh), (0.50 * L, zb + 0.09 * L, 0.26 * W, 0.34 * Hh)], CB, n=8)
    if P.get('belly'):
        paint(b, vs, P['belly'], lambda c, n: n.z < -0.3)
    if P.get('back'):
        paint(b, vs, P['back'], lambda c, n: n.z > 0.45 and c.y < 0.30 * L)

    ny, nz = 0.40 * L, zb + 0.07 * L
    hy, hz = ny + P['neck_fwd'], nz + P['neck_up']
    h = A.part("Head", (0, ny, nz))
    nk = limb(h, [(0, ny - 0.02, nz - 0.02), (0, (ny + hy) * 0.5 + 0.01, (nz + hz) * 0.5), (0, hy, hz)],
              [P['neck_r'] * 1.25, P['neck_r'], P['neck_r'] * 0.92], P.get('neck', CB), n=6)
    if P.get('neck_ring'):
        paint(h, nk, P['neck_ring'], lambda c, n: c.z < (nz + hz) * 0.5 + 0.01)
    hr = P['head_r']
    limb(h, [(0, hy - hr * 0.8, hz + hr * 0.25), (0, hy + hr * 0.25, hz + hr * 0.5), (0, hy + hr * 1.15, hz + hr * 0.25)],
         [hr * 0.78, hr, hr * 0.62], P.get('head', CB), n=6)
    by0 = hy + hr * 1.05
    bz0 = hz + hr * 0.2
    bl = P['beak_len']
    limb(h, [(0, by0, bz0), (0, by0 + bl * 0.6, bz0 - bl * 0.05)], [(hr * 0.36, hr * 0.42), (hr * 0.27, hr * 0.32)], P['beak'], n=4,
         tip=(0, by0 + bl, bz0 - bl * P.get('hook', 0.25)))
    if P.get('cere'):
        gem(h, (0, by0 + 0.004, bz0 + hr * 0.34), hr * 0.3, P['cere'], axis=(0, 0.4, 1), n=4)
    eyes(h, hr * 0.86, hy + hr * 0.45, hz + hr * 0.62, hr * 0.2, P.get('eye', "Black"))

    wr = (W * 0.42, 0.10 * L, zb + 0.30 * Hh)
    for name, sx in (("Wing_L", -1), ("Wing_R", 1)):
        w = A.part(name, (wr[0] * sx, wr[1], wr[2]))
        _wing(w, sx, wr, P['span'], P['chord'], P['sweep'], P['rise'], P['wing_top'], P['wing_under'], P['wing_tip'],
              thick=P.get('wing_thick', 0.014))
        if P.get('wing_bar'):
            lo_x = wr[0] + P['span'] * 0.30
            hi_x = wr[0] + P['span'] * 0.46
            paint(w, list(w.bm.verts), P['wing_bar'], lambda c, n: n.z > 0 and lo_x < abs(c.x) < hi_x)

    ty = -0.44 * L
    t = A.part("Tail", (0, ty, zb - 0.01 * L))
    tl, tw = P['tail_len'], P['tail_w']
    secs = []
    for (f, wf, th) in ((0.0, 0.42, 0.030), (0.55, 0.85, 0.014), (1.0, 1.0, 0.005)):
        y = ty + 0.03 - tl * f
        z = zb - 0.01 * L - 0.02 * f
        secs.append([Vector((tw * wf * 0.5, y, z)), Vector((0, y, z - th)), Vector((-tw * wf * 0.5, y, z)), Vector((0, y, z + th))])
    mk = t.mark()
    loft(t.bm, secs, mat=t.m(P['tail']))
    if P.get('tail_band'):
        paint(t, t.since(mk), P['tail_band'], lambda c, n: c.y < ty - tl * 0.55)

    lg = A.part("Legs", (0, -0.02 * L, zb - 0.38 * Hh))
    lx = W * 0.26
    for sx in (-1, 1):
        limb(lg, [(lx, -0.02 * L, zb - 0.36 * Hh), (lx, 0.0, 0.012)], [P['leg_r'], P['leg_r'] * 0.85], P['legs'], sx=sx, n=4)
        fl = P['foot']
        prof = [(lx * sx - fl * 0.42, -fl * 0.15), (lx * sx + fl * 0.42, -fl * 0.15), (lx * sx + fl * 0.55, fl), (lx * sx, fl * 0.75),
                (lx * sx - fl * 0.55, fl)]
        G.add_prism(lg.bm, prof, 0.0, 0.010, axis='Z', mat_index=lg.m(P['legs']))


@animal("seagull", 7, "bird", shoulder_height=0.27, wing_span=1.32, walk_speed=0.5, run_speed=9.0, tags=["coast", "beach", "marina", "flock"])
def seagull(A):
    _bird(A, dict(len=0.36, body_z=0.20, body_w=0.135, body_h=0.135, body="White", back="HairGrey",
                  neck_fwd=0.05, neck_up=0.075, neck_r=0.038, head_r=0.041, beak_len=0.085, beak="CarYellow", hook=0.30,
                  span=0.60, chord=0.20, sweep=0.10, rise=0.05, wing_top="HairGrey", wing_under="White", wing_tip="Black",
                  tail_len=0.15, tail_w=0.14, tail="White", legs="Mustard", leg_r=0.009, foot=0.055))


@animal("pigeon", 8, "bird", shoulder_height=0.17, wing_span=0.68, walk_speed=0.4, run_speed=8.0, tags=["city", "plaza", "flock"])
def pigeon(A):
    _bird(A, dict(len=0.21, body_z=0.125, body_w=0.105, body_h=0.105, body="HairGrey", belly="WarmGrey",
                  neck_fwd=0.022, neck_up=0.05, neck_r=0.030, neck="Teal", neck_ring="Lavender", head_r=0.029, head="RoofGrey",
                  beak_len=0.03, beak="HairBlack", hook=0.15, cere="White", eye="CarOrange",
                  span=0.285, chord=0.125, sweep=0.045, rise=0.02, wing_top="WarmGrey", wing_under="HairGrey", wing_tip="HairBlack",
                  wing_bar="HairBlack", wing_thick=0.011,
                  tail_len=0.10, tail_w=0.085, tail="RoofGrey", tail_band="HairBlack", legs="Coral", leg_r=0.006, foot=0.032))


# ---- fish ---------------------------------------------------------------------------------------
@animal("fish_small", 9, "fish", shoulder_height=0.0, walk_speed=0.8, run_speed=3.0, tags=["reef", "school", "harmless"])
def fish_small(A):
    CT, CU, CF = "Teal", "CarYellow", "CarYellow"
    b = A.part("Body", (0, 0.03, 0))
    vs = body_loft(b, [(-0.12, 0.0, 0.014, 0.036), (-0.07, 0.0, 0.032, 0.085), (0.0, 0.003, 0.052, 0.135), (0.07, 0.003, 0.052, 0.125),
                       (0.13, 0.0, 0.036, 0.078), (0.178, -0.004, 0.012, 0.028)], CT, n=8, e=0.9)
    paint(b, vs, CU, lambda c, n: c.z < -0.012)
    paint(b, vs, "White", lambda c, n: -0.012 <= c.z < 0.02 and -0.06 < c.y < 0.10 and abs(n.x) > 0.6)
    fin(b, (0, 0.07, 0.058), (0, -0.065, 0.045), (0, -0.085, 0.125), 0.012, CF, mid=0.55, te_mid=(0, -0.07, 0.095))
    fin(b, (0, -0.01, -0.058), (0, -0.085, -0.036), (0, -0.09, -0.10), 0.010, CF)
    eyes(b, 0.0215, 0.128, 0.014, 0.013)

    t = A.part("Tail", (0, -0.115, 0))
    limb(t, [(0, -0.105, 0), (0, -0.14, 0)], [(0.008, 0.02), (0.006, 0.03)], CT, n=4)
    fin(t, (0, -0.125, 0.012), (0, -0.165, 0.0), (0, -0.225, 0.095), 0.010, CF, mid=0.5)
    fin(t, (0, -0.125, -0.012), (0, -0.165, 0.0), (0, -0.225, -0.095), 0.010, CF, mid=0.5)

    for name, sx in (("Fin_L", -1), ("Fin_R", 1)):
        f = A.part(name, (0.026 * sx, 0.075, -0.022))
        fin(f, (0.024, 0.09, -0.012), (0.024, 0.06, -0.034), (0.075, 0.015, -0.065), 0.008, CF, sx=sx)


@animal("shark", 10, "fish", shoulder_height=0.0, walk_speed=1.5, run_speed=7.0, tags=["deep_water", "predator", "dangerous"])
def shark(A):
    CT, CM, CU = "RoofGrey", "HairGrey", "White"
    # bulky torpedo body (great-white proportions: widest just behind the gills)
    secs = [(-1.12, 0.02, 0.08, 0.12), (-0.85, 0.01, 0.19, 0.22), (-0.45, 0.0, 0.36, 0.41), (0.05, 0.0, 0.53, 0.57),
            (0.50, 0.0, 0.58, 0.59), (0.90, 0.01, 0.50, 0.47), (1.20, 0.02, 0.38, 0.30), (1.42, 0.02, 0.22, 0.15), (1.56, 0.012, 0.06, 0.04)]
    b = A.part("Body", (0, 0.2, 0))
    vs = body_loft(b, secs, CT, n=10, e=0.9)
    paint(b, vs, CM, lambda c, n: n.z < 0.35)
    paint(b, vs, CU, lambda c, n: n.z < -0.25)
    # dorsal, second dorsal, pelvic and anal fins
    fin(b, (0, 0.38, 0.255), (0, -0.14, 0.245), (0, -0.30, 0.70), 0.06, CT, mid=0.55, te_mid=(0, -0.16, 0.45))
    fin(b, (0, -0.62, 0.14), (0, -0.80, 0.10), (0, -0.88, 0.25), 0.03, CT)
    fin(b, (0, -0.70, -0.08), (0, -0.86, -0.06), (0, -0.92, -0.20), 0.03, CM)
    for sx in (-1, 1):
        fin(b, (0.12, -0.30, -0.17), (0.11, -0.50, -0.14), (0.27, -0.58, -0.28), 0.03, CM, sx=sx)
        for k in range(4):
            y = 0.70 + 0.075 * k
            wy = 0.565 - 0.08 * (y - 0.5) / 0.4
            G.add_box(b.bm, (0.022, 0.018, 0.17 - 0.012 * k), ((wy * 0.5 - 0.004) * sx, y, 0.0), rot=(0.0, 0.0, -0.12 * sx),
                      mat_index=b.m("HairBlack"))
    eyes(b, 0.178, 1.24, 0.06, 0.03)
    # mouth + teeth under the snout
    G.add_box(b.bm, (0.28, 0.10, 0.03), (0, 1.13, -0.118), rot=(0.12, 0, 0), mat_index=b.m("Black"))
    for k in range(6):
        x = -0.11 + 0.044 * k
        spike(b, (x, 1.165 - abs(x) * 0.35, -0.118), (x, 1.17 - abs(x) * 0.35, -0.165), 0.014, CU, n=3)

    t = A.part("Tail", (0, -1.10, 0.02))
    limb(t, [(0, -1.06, 0.02), (0, -1.26, 0.03)], [(0.035, 0.058), (0.026, 0.05)], CT, n=6, tip=(0, -1.34, 0.04))
    fin(t, (0, -1.14, 0.06), (0, -1.34, 0.0), (0, -1.72, 0.66), 0.045, CT, mid=0.5, te_mid=(0, -1.50, 0.26))
    fin(t, (0, -1.14, -0.02), (0, -1.32, 0.02), (0, -1.52, -0.36), 0.04, CM, mid=0.5)

    for name, sx in (("Fin_L", -1), ("Fin_R", 1)):
        f = A.part(name, (0.25 * sx, 0.46, -0.13))
        fin(f, (0.24, 0.64, -0.10), (0.23, 0.30, -0.14), (0.86, 0.06, -0.36), 0.06, CM, sx=sx, mid=0.5, te_mid=(0.51, 0.16, -0.24))


def build_animal(aid):
    spec = _ANIMALS[aid]
    root = G.asset_root(aid, ANIMAL_COL, G.slot("animals", spec['slot']))
    A = Parts()
    spec['fn'](A)
    if spec['kind'] == 'fish':
        # fish are centred on the origin (length and height)
        ys, zs = [], []
        for _n, mb, _p in A.parts:
            for v in mb.bm.verts:
                ys.append(v.co.y)
                zs.append(v.co.z)
        sh = Vector((0.0, -(min(ys) + max(ys)) * 0.5, -(min(zs) + max(zs)) * 0.5))
        for part in A.parts:
            for v in part[1].bm.verts:
                v.co += sh
            part[2] = part[2] + sh
    for name, mb, pivot in A.parts:
        ob = G.new_object("%s_%s" % (aid, name), mb.bm, parent=root, materials=mb.materials())
        G.set_origin(ob, pivot)
    return root


def build_all_animals():
    for aid in _ANIMAL_ORDER:
        build_animal(aid)
    return list(_ANIMAL_ORDER)



# =================================================================================================
# batch / export / QA
# =================================================================================================
def build_all_nature(lods=True):
    out = []
    for aid in _NATURE_ORDER:
        build_nature(aid, 0)
        out.append(aid)
        if lods and _NATURE[aid]['lod']:
            build_nature(aid, 1)
            out.append(aid + "_lod1")
    return out


def glb_rename_nodes(path, rename):
    """Rewrite node names inside a .glb (JSON chunk) - used to strip the '<asset>_' prefix that
    Blender needs for unique object names, so Godot sees the contract names ('Mesh', 'Body' ...)."""
    with open(path, 'rb') as fh:
        data = fh.read()
    magic, version, _length = struct.unpack_from('<4sII', data, 0)
    if magic != b'glTF':
        raise RuntimeError("not a GLB: %s" % path)
    clen, ctype = struct.unpack_from('<II', data, 12)
    if ctype != 0x4E4F534A:
        raise RuntimeError("first GLB chunk is not JSON: %s" % path)
    js = json.loads(data[20:20 + clen].decode('utf-8'))
    rest = data[20 + clen:]
    changed = 0
    for item in js.get('nodes', []):
        nm = item.get('name')
        if nm:
            new = rename(nm)
            if new and new != nm:
                item['name'] = new
                changed += 1
    out = json.dumps(js, separators=(',', ':')).encode('utf-8')
    out += b' ' * ((4 - len(out) % 4) % 4)
    total = 12 + 8 + len(out) + len(rest)
    with open(path, 'wb') as fh:
        fh.write(struct.pack('<4sII', b'glTF', version, total))
        fh.write(struct.pack('<II', len(out), 0x4E4F534A))
        fh.write(out)
        fh.write(rest)
    return changed


# Suggested poses for the game-side procedural animator, in GODOT terms (node.rotation_degrees with
# the default YXZ euler order; x = pitch, y = yaw). Verified in Blender with the equivalent
# rotation (qa/blender_previews/animal_*_folded.png, animal_deer_posed.png).
BIRD_POSES = {
    # standing / perched: wings (authored spread) swung back against the flanks
    "folded": {"Wing_R": {"rotation_degrees": [-74.0, -94.0, 0.0], "scale": [0.66, 1.0, 1.0]},
               "Wing_L": {"rotation_degrees": [-74.0, 94.0, 0.0], "scale": [0.66, 1.0, 1.0]}},
    # flying: wings at rest pose (flap = rotate about local Z, the body axis), legs tucked back
    "flight": {"Legs": {"rotation_degrees": [-80.0, 0.0, 0.0]}},
}


def _g(v):
    """Blender (x, y, z) -> Godot (x, z, -y), rounded."""
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4) + 0.0]


def _mats_of(root):
    names = []
    for o in G.children_of(root):
        if o.type == 'MESH':
            for m in o.data.materials:
                if m is not None and m.name not in names:
                    names.append(m.name)
    return names


# Suggested draw distances per category (metres; 0 = never cull). Hints for the world builder,
# in line with ARCHITECTURE.md section 10 (props <= 120 m, grass <= 60 m).
VISIBILITY_END = {"tree": 0.0, "shrub": 140.0, "groundcover": 60.0, "rock": 120.0, "cliff": 0.0, "log": 120.0,
                  "underwater": 90.0}
LOD1_DISTANCE = 55.0        # trees: swap <id>.glb -> <id>_lod1.glb beyond this distance


def nature_entry(aid):
    spec = _NATURE[aid]
    v = G.validate(aid)
    mn, mx = v['min'], v['max']
    root = bpy.data.objects[aid]
    e = {"id": aid, "file": aid + ".glb", "category": spec['category'],
         "size": [round(mx[0] - mn[0], 3), round(mx[2] - mn[2], 3), round(mx[1] - mn[1], 3)],
         "collision_radius": spec['collision_radius'], "collision": spec['collision'],
         "height": round(mx[2], 3), "sink": round(-mn[2], 3),
         "aabb_min": _g((mn[0], mx[1], mn[2])), "aabb_max": _g((mx[0], mn[1], mx[2])),
         "tris": v['tris'], "multimesh": bool(spec.get('multimesh', False)),
         "tags": list(spec.get('tags', [])), "materials": _mats_of(root)}
    vis = VISIBILITY_END.get(spec['category'], 120.0)
    if spec['category'] == "rock" and max(e["size"]) >= 2.0:
        vis = 0.0                                   # boulders are landmarks: never culled
    e["visibility_end"] = vis
    if spec['lod'] and bpy.data.objects.get(aid + "_lod1") is not None:
        v1 = G.validate(aid + "_lod1")
        e["lod1"] = aid + "_lod1.glb"
        e["lod1_tris"] = v1['tris']
        e["lod1_distance"] = LOD1_DISTANCE
    return e


def animal_entry(aid):
    spec = _ANIMALS[aid]
    v = G.validate(aid)
    mn, mx = v['min'], v['max']
    root = bpy.data.objects[aid]
    pre = aid + "_"
    parts, pivots = [], {}
    for o in root.children:
        nm = o.name[len(pre):] if o.name.startswith(pre) else o.name
        parts.append(nm)
        pivots[nm] = _g(o.location)
    order = ["Body", "Head", "Leg_FL", "Leg_FR", "Leg_RL", "Leg_RR", "Wing_L", "Wing_R", "Fin_L", "Fin_R", "Tail", "Legs"]
    parts.sort(key=lambda n: order.index(n) if n in order else 99)
    e = {"id": aid, "file": aid + ".glb", "kind": spec['kind'],
         "size": [round(mx[0] - mn[0], 3), round(mx[2] - mn[2], 3), round(mx[1] - mn[1], 3)],
         "parts": parts, "shoulder_height": spec.get('shoulder_height', 0.0),
         "length": round(mx[1] - mn[1], 3), "pivots": pivots, "tris": v['tris'],
         "tags": list(spec.get('tags', [])), "materials": _mats_of(root)}
    if "Leg_FL" in pivots:
        e["leg_length"] = round(pivots["Leg_FL"][1], 3)
        e["graze_head_pitch_deg"] = -65.0
    # optional hints for the wildlife AI (real-world-ish values in m/s; not a contract)
    for k in ("walk_speed", "run_speed"):
        if k in spec:
            e[k] = spec[k]
    e["body_radius"] = round(max(mx[0] - mn[0], 0.5 * (mx[1] - mn[1])) * 0.5, 3)
    if spec['kind'] == 'bird':
        e["body_radius"] = round((mx[1] - mn[1]) * 0.5, 3)      # wings excluded
        e["wing_span"] = spec.get('wing_span', round(mx[0] - mn[0], 3))
        e["poses"] = BIRD_POSES
        e["flap_axis"] = "z"
    return e


def write_manifests():
    nat = {"_comment": "Generated by tools/blender/assets/nature_animals.py (NA.write_manifests). Sizes are [x, y, z] in Godot axes "
                       "(y = height). Origin at the base; 'sink' = how far the mesh continues below the origin.",
           "nature": [nature_entry(a) for a in _NATURE_ORDER if bpy.data.objects.get(a) is not None]}
    ani = {"_comment": "Generated by tools/blender/assets/nature_animals.py (NA.write_manifests). Rigid part nodes with origins at "
                       "the joints, facing -Z in Godot. 'pivots' = rest position of every part node in Godot axes.",
           "animals": [animal_entry(a) for a in _ANIMAL_ORDER if bpy.data.objects.get(a) is not None]}
    out = []
    for rel, data in (("nature/manifest_nature.json", nat), ("animals/manifest_animals.json", ani)):
        path = os.path.join(G.MODELS_DIR, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as fh:
            json.dump(data, fh, indent=1)
        out.append(path)
        print("MANIFEST:", path)
    return out


def export_all(nature_ids=None, animal_ids=None, manifests=True):
    done = []
    for aid in (nature_ids if nature_ids is not None else _NATURE_ORDER):
        if bpy.data.objects.get(aid) is None:
            print("EXPORT_SKIP (not built):", aid)
            continue
        export_asset(aid, "nature")
        done.append(aid)
        if _NATURE[aid]['lod'] and bpy.data.objects.get(aid + "_lod1") is not None:
            export_asset(aid + "_lod1", "nature")
            done.append(aid + "_lod1")
    for aid in (animal_ids if animal_ids is not None else _ANIMAL_ORDER):
        if bpy.data.objects.get(aid) is None:
            print("EXPORT_SKIP (not built):", aid)
            continue
        export_asset(aid, "animals")
        done.append(aid)
    if manifests:
        write_manifests()
    return done


def build_all(lods=True):
    return build_all_nature(lods) + build_all_animals()


def export_asset(name, category):
    """Export root `name` to <category>/<name>.glb with contract node names."""
    path = G.export_glb(name, "%s/%s.glb" % (category, name))
    pre = name + "_"
    n = glb_rename_nodes(path, lambda nm: nm[len(pre):] if nm.startswith(pre) else nm)
    print("RENAMED_NODES:", name, n)
    return path


def closeup(names, out_name, center, radius, views=("three_quarter", "side"), res=512, background=(0.20, 0.22, 0.26)):
    """Detail render of a region of an asset (G.preview always frames the whole bounding box, which
    is too coarse for palm crowns, heads ...). `center` is relative to the first root. Same safety
    rules as G.preview: Workbench only, others hidden only for the render, everything restored."""
    import numpy as np
    G.object_mode()
    if isinstance(names, str):
        names = [names]
    scene = bpy.context.scene
    objs = set()
    for nm in names:
        objs.update(G.children_of(bpy.data.objects[nm]))
    bpy.context.view_layer.update()
    ctr = bpy.data.objects[names[0]].matrix_world @ Vector(center)
    r = scene.render
    sh = scene.display.shading
    saved = (r.engine, r.resolution_x, r.resolution_y, r.resolution_percentage, r.filepath, r.image_settings.file_format,
             scene.camera, r.film_transparent)
    saved_sh = {}
    for k in ("light", "color_type", "show_cavity", "show_shadows", "show_object_outline", "background_type", "background_color", "cavity_type"):
        try:
            val = getattr(sh, k)
            saved_sh[k] = tuple(val) if k == "background_color" else val
        except Exception:
            pass
    hidden = []
    for o in scene.objects:
        if o not in objs and not o.hide_render:
            o.hide_render = True
            hidden.append(o)
    cam_data = bpy.data.cameras.new("_na_closeup_cam")
    cam = bpy.data.objects.new("_na_closeup_cam", cam_data)
    scene.collection.objects.link(cam)
    out_path = os.path.join(G.PREVIEW_DIR, out_name + ".png")
    tmp_paths = []
    try:
        r.engine = 'BLENDER_WORKBENCH'
        for k, val in (("light", 'STUDIO'), ("color_type", 'MATERIAL'), ("show_cavity", True), ("cavity_type", 'BOTH'),
                       ("show_shadows", False), ("show_object_outline", True), ("background_type", 'VIEWPORT'),
                       ("background_color", background)):
            try:
                setattr(sh, k, val)
            except Exception:
                pass
        res = min(int(res), 512)
        r.resolution_x = res
        r.resolution_y = res
        r.resolution_percentage = 100
        r.film_transparent = False
        r.image_settings.file_format = 'PNG'
        scene.camera = cam
        cam_data.type = 'ORTHO'
        cam_data.ortho_scale = radius * 2.0
        cam_data.clip_start = 0.01
        cam_data.clip_end = radius * 12 + 60
        tiles = []
        for i, vname in enumerate(views):
            d = Vector(G._VIEW_DIRS[vname] if isinstance(vname, str) else vname).normalized()
            cam.location = ctr + d * (radius * 4.0 + 20.0)
            cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
            tmp = os.path.join(G.PREVIEW_DIR, "_tmpc_%s_%d.png" % (out_name, i))
            r.filepath = tmp
            bpy.ops.render.render(write_still=True)
            tmp_paths.append(tmp)
            img = bpy.data.images.load(tmp, check_existing=False)
            arr = np.empty(res * res * 4, dtype=np.float32)
            img.pixels.foreach_get(arr)
            tiles.append(arr.reshape(res, res, 4))
            bpy.data.images.remove(img)
        cols = 2 if len(tiles) > 1 else 1
        rows = (len(tiles) + cols - 1) // cols
        sheet = np.zeros((rows * res, cols * res, 4), dtype=np.float32)
        sheet[..., 3] = 1.0
        for i, t in enumerate(tiles):
            rr = rows - 1 - (i // cols)
            cc = i % cols
            sheet[rr * res:(rr + 1) * res, cc * res:(cc + 1) * res, :] = t
        out = bpy.data.images.new("_na_closeup_sheet", cols * res, rows * res, alpha=False)
        out.pixels.foreach_set(sheet.ravel())
        out.filepath_raw = out_path
        out.file_format = 'PNG'
        out.save()
        bpy.data.images.remove(out)
    finally:
        for o in hidden:
            try:
                o.hide_render = False
            except Exception:
                pass
        bpy.data.objects.remove(cam, do_unlink=True)
        bpy.data.cameras.remove(cam_data)
        scene.camera = saved[6]
        try:
            r.engine = saved[0]
        except Exception:
            pass
        r.resolution_x, r.resolution_y, r.resolution_percentage, r.filepath = saved[1], saved[2], saved[3], saved[4]
        r.film_transparent = saved[7]
        try:
            r.image_settings.file_format = saved[5]
        except Exception:
            pass
        for k, val in saved_sh.items():
            try:
                setattr(sh, k, val)
            except Exception:
                pass
        for t in tmp_paths:
            try:
                os.remove(t)
            except Exception:
                pass
    print("CLOSEUP_SAVED:", out_path)
    return out_path


def group_preview(names, out_name, spacing=6.0, per_row=12, row_spacing=8.0, ref_box=True, views=("front",), res=1024,
                  region="nature"):
    """Temporarily line the given roots up next to a 1.8 m reference box and render them together."""
    roots = [bpy.data.objects[n] for n in names]
    saved = [(r, r.location.copy()) for r in roots]
    base = G.slot(region, 0)
    ref = None
    try:
        show = []
        if ref_box:
            ref = G.asset_root("na_scale_ref", NATURE_COL, base)
            bm = bmesh.new()
            G.add_box(bm, (0.5, 0.3, 1.8), (0, 0, 0.9))
            G.new_object("na_scale_ref_Mesh", bm, parent=ref, materials=[G.pmat("Coral")])
            show.append("na_scale_ref")
        off = 1 if ref_box else 0
        for i, r in enumerate(roots):
            k = i + off
            r.location = base + Vector(((k % per_row) * spacing, -(k // per_row) * row_spacing, 0))
            show.append(r.name)
        bpy.context.view_layer.update()
        return G.preview(show, out_name, views=views, res=res)
    finally:
        for r, loc in saved:
            r.location = loc
        if ref is not None:
            G.delete_hierarchy("na_scale_ref")
        bpy.context.view_layer.update()
