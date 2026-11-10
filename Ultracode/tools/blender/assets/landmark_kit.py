"""landmark_kit - helpers for the walk-in landmark buildings of Halcyon Bay (Blender 5.2, bmesh only).

Sits on top of building_kit (K) and gta_bl (G); used by buildings_landmarks*.py.

What it adds to the building kit
--------------------------------
* LB(K.Builder)   landmark builder: region "landmarks", collection "Buildings/Landmarks", plus
                    - an extra part "interior" -> mesh node `Building_Interior` (furniture, fit-out)
                    - b.sub("Pump_1", origin)   separate mesh objects with their own origin / hinge
                    - b.marker("Use_Counter", x, y, z, yaw)   marker Empties + manifest "markers"
* twall() / Room  walls with REAL thickness (outer face + inner face + reveals), open doorways,
                  double-sided glazing (one pane facing out, one facing in) - for trimesh collision.
* Fr              local frame (position + yaw) so furniture is written once with "front = +Y".
* furniture       counter, register, shelf, gondola, fridge, clothes_rack, display_case, workbench,
                  tool_chest, tyres, sofa, bed, wardrobe, desk, kitchen, barber_chair, lockers ...
* QA              cutaway() (roof clipped away: plan / dollhouse views of the interior), shot()
                  (perspective camera inside the building), export() (clean node names for ALL
                  children incl. markers), manifest helpers.

Conventions: Blender coordinates, front = +Y, origin = footprint centre on the ground, interior floor
at z = FLOOR (6 cm above the lot). Marker yaw: 0 = facing +Y (Godot -Z), counter-clockwise from above.
"""
import bpy
import bmesh
import json
import math
import os
import re
from mathutils import Vector

import gta_bl as G
import building_kit as K

T = 0.3            # exterior wall thickness
TP = 0.16          # partition thickness
FLOOR = 0.06       # interior floor level above the lot ground
EPS = 1e-4
PI = math.pi
FACE_YAW = {"+y": 0.0, "-y": PI, "+x": -PI / 2, "-x": PI / 2}
GOODS = ("CarRed", "Mustard", "Teal", "White", "CarBlue", "Coral", "Leaf", "Lavender", "SafetyOrange", "Navy")
CLOTHES = ("Coral", "Teal", "Mustard", "White", "Navy", "Rose", "Lavender", "Denim", "ShirtGreen", "Charcoal", "Sky")


import contextlib


@contextlib.contextmanager
def at_floor(z):
    """Temporarily move the furniture base level (mezzanines): `with LK.at_floor(3.3): LK.bed(...)`.
    Helpers that take an explicit z (rug, plant, register, vending ...) need it passed."""
    global FLOOR
    old = FLOOR
    FLOOR = z
    try:
        yield
    finally:
        FLOOR = old


def hgraphic(b, pts, z, mat, part="detail"):
    """Flat graphic on a horizontal surface (ground markings); pts = plan polygon (any winding)."""
    return b.poly_dir([(p[0], p[1], z) for p in pts], (0, 0, 1), mat, part)


def hdisc(b, x, y, r, z, mat, n=12, part="detail"):
    return hgraphic(b, [(x + r * math.cos(2 * PI * i / n), y + r * math.sin(2 * PI * i / n)) for i in range(n)], z, mat, part)


def hring(b, x, y, r0, r1, z, mat, n=16, part="detail"):
    for i in range(n):
        a0, a1 = 2 * PI * i / n, 2 * PI * (i + 1) / n
        hgraphic(b, [(x + r0 * math.cos(a0), y + r0 * math.sin(a0)), (x + r1 * math.cos(a0), y + r1 * math.sin(a0)),
                     (x + r1 * math.cos(a1), y + r1 * math.sin(a1)), (x + r0 * math.cos(a1), y + r0 * math.sin(a1))], z, mat, part)


def hrect(b, x0, x1, y0, y1, z, mat, part="detail", down=False):
    """Flat rectangle facing up (ground marking) or down (light panel under a canopy / ceiling)."""
    pts = ((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z))
    return b.poly(pts[::-1] if down else pts, mat, part)


def smat(key, fallback):
    """Name of an existing shared contract material, or a palette fallback."""
    return key if bpy.data.materials.get(key) is not None else fallback


def glow():
    """Emissive lamp material required by the brief (M_LampGlow); created if it does not exist yet."""
    if bpy.data.materials.get("M_LampGlow") is None:
        c = G.pal("LampWarm")
        G.mat("M_LampGlow", c, rough=0.4, emit=c, emit_strength=6.0)
    return "M_LampGlow"


def beacon():
    """Red emissive obstruction light (palette SirenRed) - shared by mast, tower, hangar."""
    if bpy.data.materials.get("M_Beacon_Red") is None:
        c = G.pal("SirenRed")
        G.mat("M_Beacon_Red", c, rough=0.4, emit=c, emit_strength=5.0)
    return "M_Beacon_Red"


class Rnd(object):
    """Tiny deterministic generator (assets must rebuild identically)."""

    def __init__(self, seed=1):
        self.s = (seed * 2654435761 + 12345) % 2147483647 or 1

    def __call__(self):
        self.s = (1103515245 * self.s + 12345) % 2147483648
        return self.s / 2147483648.0

    def rng(self, a, b):
        return a + (b - a) * self()

    def pick(self, seq):
        return seq[int(self() * len(seq)) % len(seq)]


# ------------------------------------------------------------------------------------------------
# builder
# ------------------------------------------------------------------------------------------------
class LB(K.Builder):
    """Landmark builder (see module docstring)."""

    def __init__(self, name, slot, scheme=None):
        K.Builder.__init__(self, name, slot=slot, scheme=scheme, region="landmarks", collection="Buildings/Landmarks")
        self.parts["interior"] = K._Part()
        self._subs = []
        self._markers = []
        self.sub_markers = {}

    def sub(self, key, origin=(0.0, 0.0, 0.0), rot_z=0.0, marker=False):
        """Separate mesh object `key` (use part=key). Geometry is authored in building space; the
        object origin is moved to `origin` (hinge / base) and then rotated by rot_z about it.
        marker=True lists the origin in the manifest "markers" (the object itself is the marker)."""
        self.parts[key] = K._Part()
        self._subs.append((key, Vector(origin), rot_z))
        if marker:
            self.sub_markers[key] = tuple(origin)
        return key

    def marker(self, name, x, y, z=0.0, yaw=None):
        self._markers.append((name, (x, y, z), yaw))

    def finish(self, tags=(), landmark="", collision="trimesh", category="landmark", extra=None, collide=None):
        ex = {}
        mk = {}
        yaws = {}
        for n, p, yaw in self._markers:
            mk[n] = [round(p[0], 3), round(p[2], 3), round(-p[1], 3)]
            if yaw is not None:
                yaws[n] = round(yaw, 4)
        for n, p in self.sub_markers.items():
            mk[n] = [round(p[0], 3), round(p[2], 3), round(-p[1], 3)]
        ex["markers"] = mk
        if yaws:
            ex["marker_yaw"] = yaws
        if collision == "trimesh":
            nodes = ["Building"]
            if len(self.parts["interior"].bm.faces):
                nodes.append("Building_Interior")
            if len(self.parts["glass"].bm.faces):
                nodes.append("Building_Glass")
            ex["collision_nodes"] = collide or nodes
        if self._subs:
            ex["separate_objects"] = [k for k, _, _ in self._subs]
        if extra:
            ex.update(extra)
        root = K.Builder.finish(self, category, tags, collision, landmark, ex)
        p = self.parts["interior"]
        if len(p.bm.faces):
            G.new_object("%s_Building_Interior" % self.name, p.bm, parent=root, materials=p.mats, recalc=False)
        else:
            p.bm.free()
        for key, origin, rz in self._subs:
            p = self.parts[key]
            ob = G.new_object("%s_%s" % (self.name, key), p.bm, parent=root, materials=p.mats, recalc=False)
            G.set_origin(ob, origin)
            if rz:
                ob.rotation_euler = (0.0, 0.0, rz)
        for n, pos, yaw in self._markers:
            G.empty("%s_%s" % (self.name, n), root, pos, (0.0, 0.0, yaw or 0.0), size=0.5)
        return root


# ------------------------------------------------------------------------------------------------
# thick walls / rooms
# ------------------------------------------------------------------------------------------------
def door(a, c, h=2.5, **kw):
    """Open doorway between world coordinates a..c along the wall."""
    return dict(kind="door", a=a, c=c, v0=FLOOR, v1=h, **kw)


def gap(a, c, v0=FLOOR, v1=3.5, **kw):
    """Plain opening (garage bay, hatch) - no trim frame."""
    return dict(kind="open", a=a, c=c, v0=v0, v1=v1, **kw)


def win(a, c, sill=1.0, head=2.5, **kw):
    """Glazed window (double sided)."""
    return dict(kind="win", a=a, c=c, v0=sill, v1=head, **kw)


def shopwin(a, c, sill=0.5, head=3.0, **kw):
    """Storefront glazing (double sided, mullions every ~1.7 m)."""
    return dict(kind="shop", a=a, c=c, v0=sill, v1=head, **kw)


def face_span(f, a, c):
    """World coordinates a..c along an axis-aligned face -> (u0, u1)."""
    if abs(f.U.x) > 0.5:
        ua, uc = (a - f.o.x) * f.U.x, (c - f.o.x) * f.U.x
    else:
        ua, uc = (a - f.o.y) * f.U.y, (c - f.o.y) * f.U.y
    return (min(ua, uc), max(ua, uc))


def face_u(f, a):
    """World coordinate along an axis-aligned face -> u."""
    return (a - f.o.x) * f.U.x if abs(f.U.x) > 0.5 else (a - f.o.y) * f.U.y


def twall(face, v0, v1, ops=(), T=T, mat="wall", imat="wall2", inner=None, iv=None, trim="trim", part="body"):
    """Wall with real thickness. `face` = OUTER K.Face; the wall occupies d = -T .. 0.
    ops = dicts made by door() / gap() / win() / shopwin() with u0, u1 (outer-face coords) or a, c
    (world coords along the face). inner = (ua, uc) outer-u range covered by the inner face (default
    T .. w - T, i.e. a room corner at both ends); iv = (v0, v1) of the inner face (floor .. ceiling).
    Returns the inner Face (u runs opposite to the outer one, d points into the room)."""
    b = face.b
    ia, ic = inner if inner is not None else (T, face.w - T)
    v0i, v1i = iv if iv is not None else (v0, v1)
    pa = face.P(ic, 0.0, -T)
    pc = face.P(ia, 0.0, -T)
    fin = K.Face(b, (pa.x, pa.y), (pc.x, pc.y), face.z0)
    g = T / 2.0 - 0.012
    oo = []
    io = []
    cv = []
    for o in ops:
        o = dict(o)
        if "u0" not in o:
            o["u0"], o["u1"] = face_span(face, o["a"], o["c"])
        cv.append(o)
        k = o["kind"]
        if k in ("door", "open"):
            oo.append(K.Op(o["u0"], o["u1"], o["v0"], o["v1"], rec=T, rmat=o.get("reveal")))
            io.append(K.Op(ic - o["u1"], ic - o["u0"], o["v0"], o["v1"], rec=0.0))
        else:
            oo.append(K.Op(o["u0"], o["u1"], o["v0"], o["v1"], rec=g, rmat=o.get("reveal", trim)))
            io.append(K.Op(ic - o["u1"], ic - o["u0"], o["v0"], o["v1"], rec=g, rmat=o.get("reveal", trim)))
    face.wall(0.0, face.w, v0, v1, mat, oo, part=part)
    if ic - ia > EPS:
        fin.wall(0.0, fin.w, v0i, v1i, imat, io, part=part)
    for o in cv:
        k = o["kind"]
        u0, u1, b0, b1 = o["u0"], o["u1"], o["v0"], o["v1"]
        if k == "door":
            if o.get("frame", True):
                face.frame(u0, u1, b0, b1, w=0.14, proud=0.07, back=0.0, mat=o.get("frame_mat", trim), part=part)
        elif k in ("win", "shop"):
            nx = o.get("nx") or max(1, int(round((u1 - u0) / o.get("pane", 1.7))))
            face.pane(u0, u1, b0, b1, -g, nx, 1)
            fin.pane(ic - u1, ic - u0, b0, b1, -g, nx, 1)
            bw = 0.07
            for i in range(1, nx):
                u = u0 + (u1 - u0) * i / nx
                face.box(u - bw / 2, u + bw / 2, b0, b1, -g, -g + 0.07, trim, part, "k t b")
                ui = ic - u
                fin.box(ui - bw / 2, ui + bw / 2, b0, b1, -g, -g + 0.07, trim, part, "k t b")
            tr = o.get("transom")
            if tr:
                vt = b1 - tr
                face.box(u0, u1, vt - 0.04, vt + 0.04, -g, -g + 0.07, trim, part, "k l r")
                fin.box(ic - u1, ic - u0, vt - 0.04, vt + 0.04, -g, -g + 0.07, trim, part, "k l r")
            if o.get("sill_bar", k == "win"):
                face.box(u0 - 0.08, u1 + 0.08, b0 - 0.1, b0, 0.0, 0.08, o.get("sill_mat", trim), part, "k")
            if o.get("frame"):
                face.frame(u0, u1, b0, b1, w=0.12, proud=0.06, back=0.0, mat=o["frame"], bottom=not o.get("sill_bar", k == "win"),
                           part=part)
            nb = o.get("bars")
            if nb:
                for i in range(nb):
                    u = u0 + (u1 - u0) * (i + 0.5) / nb
                    face.box(u - 0.025, u + 0.025, b0, b1, 0.0, 0.05, "SteelDark", "detail", "k t b")
                for vv in (b0 + 0.25, b1 - 0.25):
                    face.box(u0, u1, vv - 0.025, vv + 0.025, 0.0, 0.04, "SteelDark", "detail", "k l r")
    return fin


class Room(object):
    """Rectangular walk-in volume: K.Mass (outer faces, foundation skirt) + thick walls + floor + ceiling."""

    def __init__(self, b, x0, x1, y0, y1, h=4.0, ceil=3.4, T=T, z0=0.0, wall="wall", inner="wall2", skirt=True):
        self.b = b
        self.x0, self.x1, self.y0, self.y1 = x0, x1, y0, y1
        self.h, self.ceil, self.T, self.z0 = h, ceil, T, z0
        self.wall_mat, self.inner_mat = wall, inner
        self.m = b.mass(x0, x1, y0, y1, z0, skirt=skirt, solid=False)
        self.ix0, self.ix1, self.iy0, self.iy1 = x0 + T, x1 - T, y0 + T, y1 - T
        self.inner = {}

    @property
    def pts(self):
        return self.m.pts

    def face(self, side):
        return self.m.side(side)

    def wall(self, side, ops=(), h=None, v0=0.0, **kw):
        kw.setdefault("mat", self.wall_mat)
        kw.setdefault("imat", self.inner_mat)
        kw.setdefault("T", self.T)
        kw.setdefault("iv", (FLOOR, self.ceil))
        fin = twall(self.m.side(side), v0, h or self.h, ops, **kw)
        self.inner[side] = fin
        return fin

    def walls(self, front=(), back=(), left=(), right=(), **kw):
        for side, ops in (("front", front), ("right", right), ("back", back), ("left", left)):
            self.wall(side, ops, **kw)
        return self.inner

    def inner_pts(self, z):
        return [(self.ix0, self.iy0, z), (self.ix1, self.iy0, z), (self.ix1, self.iy1, z), (self.ix0, self.iy1, z)]

    def floor(self, mat="Wood", z=FLOOR):
        self.b.poly(self.inner_pts(self.z0 + z), mat)

    def ceiling(self, mat="White", z=None):
        self.b.poly(list(reversed(self.inner_pts(self.z0 + (self.ceil if z is None else z)))), mat)

    def tiles(self, mats=("White", "Charcoal"), size=1.0, z=FLOOR):
        """Checkerboard floor."""
        nx = max(1, int(round((self.ix1 - self.ix0) / size)))
        ny = max(1, int(round((self.iy1 - self.iy0) / size)))
        dx = (self.ix1 - self.ix0) / nx
        dy = (self.iy1 - self.iy0) / ny
        zz = self.z0 + z
        for i in range(nx):
            for j in range(ny):
                xa, ya = self.ix0 + i * dx, self.iy0 + j * dy
                self.b.poly(((xa, ya, zz), (xa + dx, ya, zz), (xa + dx, ya + dy, zz), (xa, ya + dy, zz)), mats[(i + j) % len(mats)])

    def lights(self, nx=2, ny=2, w=1.4, d=0.35):
        for i in range(nx):
            for j in range(ny):
                x = self.ix0 + (self.ix1 - self.ix0) * (i + 0.5) / nx
                y = self.iy0 + (self.iy1 - self.iy0) * (j + 0.5) / ny
                ceiling_light(self.b, x, y, self.z0 + self.ceil, w, d)


def partition(b, p0, p1, z0, z1, ops=(), T=TP, mat="wall2", mat2=None, ends=(True, True), top=False, trim="trim", part="body"):
    """Free-standing interior wall (both faces visible) from plan point p0 to p1. Side A looks to the
    right-hand side of p0 -> p1... i.e. A = K.Face(p0, p1). Openings in A's u coords (or a/c world)."""
    fa = K.Face(b, p0, p1, 0.0)
    cv = []
    for o in ops:
        o = dict(o)
        if "u0" not in o:
            o["u0"], o["u1"] = face_span(fa, o["a"], o["c"])
        cv.append(o)
    fb = twall(fa, z0, z1, cv, T=T, mat=mat, imat=mat2 or mat, inner=(0.0, fa.w), trim=trim, part=part)
    P = fa.P
    if ends[0]:
        b.poly((P(0, z0, -T), P(0, z0, 0), P(0, z1, 0), P(0, z1, -T)), mat, part)
    if ends[1]:
        b.poly((P(fa.w, z0, 0), P(fa.w, z0, -T), P(fa.w, z1, -T), P(fa.w, z1, 0)), mat, part)
    if top:
        b.poly((P(0, z1, 0), P(fa.w, z1, 0), P(fa.w, z1, -T), P(0, z1, -T)), mat, part)
    return fa, fb


# ------------------------------------------------------------------------------------------------
# local frame
# ------------------------------------------------------------------------------------------------
class Fr(object):
    """Local frame: origin + yaw about Z. Local +Y is the FRONT of the furniture piece."""

    def __init__(self, b, x, y, z=FLOOR, yaw=0.0, part="interior"):
        self.b = b
        self.o = (x, y, z)
        self.yaw = yaw
        self.cs, self.sn = math.cos(yaw), math.sin(yaw)
        self.part = part

    def P(self, a, c, e):
        return (self.o[0] + a * self.cs - c * self.sn, self.o[1] + a * self.sn + c * self.cs, self.o[2] + e)

    def at(self, a, c, e=0.0, yaw=0.0, part=None):
        p = self.P(a, c, e)
        return Fr(self.b, p[0], p[1], p[2], self.yaw + yaw, part or self.part)

    def box(self, x0, x1, y0, y1, z0, z1, mat, skip="", part=None):
        sk = set(K._WORLD_SKIP[t] for t in skip.split())
        self.b._box(self.P, x0, x1, y0, y1, z0, z1, mat, part or self.part, sk)

    def poly(self, pts, mat, part=None):
        return self.b.poly([self.P(*p) for p in pts], mat, part or self.part)

    def tube(self, p0, p1, r, mat, seg=6, caps="both", r1=None, part=None):
        self.b.tube(self.P(*p0), self.P(*p1), r, r1, seg, mat, part or self.part, caps)

    def cyl(self, x, y, z0, z1, r, mat, seg=8, caps="top", r2=None, part=None):
        self.b.tube(self.P(x, y, z0), self.P(x, y, z1), r, r2, seg, mat, part or self.part, caps)

    def taper(self, bottom, top, z0, z1, mat, cap=True, part=None):
        a = [(bottom[0], bottom[2], z0), (bottom[1], bottom[2], z0), (bottom[1], bottom[3], z0), (bottom[0], bottom[3], z0)]
        c = [(top[0], top[2], z1), (top[1], top[2], z1), (top[1], top[3], z1), (top[0], top[3], z1)]
        for i in range(4):
            j = (i + 1) % 4
            self.poly((a[i], a[j], c[j], c[i]), mat, part)
        if cap:
            self.poly(c, mat, part)


# ------------------------------------------------------------------------------------------------
# emblems / flat graphics on a K.Face (u right, v up; polygons counter-clockwise)
# ------------------------------------------------------------------------------------------------
def fpoly(face, uv, mat, d=0.03, part="detail"):
    return face.b.poly([face.P(u, v, d) for u, v in uv], mat, part)


def fdisc(face, uc, vc, r, mat, n=8, d=0.03, part="detail", rot=None):
    rot = PI / n if rot is None else rot
    return fpoly(face, [(uc + r * math.cos(rot + 2 * PI * i / n), vc + r * math.sin(rot + 2 * PI * i / n)) for i in range(n)], mat, d, part)


def _shield_pts(uc, vc, s):
    base = [(-0.5, 0.5), (-0.5, -0.05), (-0.32, -0.38), (0.0, -0.62), (0.32, -0.38), (0.5, -0.05), (0.5, 0.5),
            (0.18, 0.5), (0.0, 0.6), (-0.18, 0.5)]
    return [(uc + x * s, vc + y * s) for x, y in base]


def emblem_shield(face, uc, vc, s=1.6, d=0.04, part="detail", gold="BadgeGold", field="PoliceBlue"):
    """Original HBPD badge: gold-rimmed shield, rising sun over two waves."""
    fpoly(face, _shield_pts(uc, vc, s), gold, d, part)
    fpoly(face, _shield_pts(uc, vc - 0.01 * s, s * 0.86), field, d + 0.015, part)
    r = 0.21 * s
    sun = [(uc + r * math.cos(PI * i / 6), vc + 0.02 * s + r * math.sin(PI * i / 6)) for i in range(7)]
    fpoly(face, sun, gold, d + 0.03, part)
    for k, (w, v) in enumerate(((0.62, -0.06), (0.46, -0.2))):
        fpoly(face, [(uc - w * s / 2, vc + (v - 0.035) * s), (uc + w * s / 2, vc + (v - 0.035) * s),
                     (uc + w * s / 2, vc + (v + 0.035) * s), (uc - w * s / 2, vc + (v + 0.035) * s)], "White", d + 0.03, part)
    for i in (-1, 0, 1):                      # three sun rays
        a = PI / 2 + i * PI / 4
        c0 = (uc + 0.27 * s * math.cos(a), vc + 0.02 * s + 0.27 * s * math.sin(a))
        c1 = (uc + 0.36 * s * math.cos(a), vc + 0.02 * s + 0.36 * s * math.sin(a))
        px, py = -math.sin(a) * 0.022 * s, math.cos(a) * 0.022 * s
        fpoly(face, [(c0[0] - px, c0[1] - py), (c1[0] - px, c1[1] - py), (c1[0] + px, c1[1] + py), (c0[0] + px, c0[1] + py)],
              gold, d + 0.03, part)


def emblem_heart(face, uc, vc, r=1.2, d=0.04, part="detail", field="Teal", heart="White", pulse="Coral"):
    """Original hospital emblem: teal octagon, white heart, coral pulse line (not a cross)."""
    fdisc(face, uc, vc, r, field, 8, d, part)
    fdisc(face, uc, vc, r * 0.9, "White", 8, d + 0.012, part)
    fdisc(face, uc, vc, r * 0.82, field, 8, d + 0.024, part)
    pts = []
    n = 18
    for i in range(n):
        t = -2 * PI * i / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((uc + x * r * 0.034, vc + (y + 2.5) * r * 0.034))
    fpoly(face, pts, heart, d + 0.036, part)
    zz = [(-0.62, 0.0), (-0.22, 0.0), (-0.1, 0.2), (0.04, -0.24), (0.16, 0.08), (0.24, 0.0), (0.62, 0.0)]
    hw = 0.035 * r
    for (xa, ya), (xb, yb) in zip(zz[:-1], zz[1:]):
        a = Vector((uc + xa * r, vc + ya * r + 0.04 * r))
        c = Vector((uc + xb * r, vc + yb * r + 0.04 * r))
        t = (c - a).normalized()
        nrm = Vector((-t.y, t.x)) * hw
        fpoly(face, [tuple(a - nrm - t * hw * 0.5), tuple(c - nrm + t * hw * 0.5), tuple(c + nrm + t * hw * 0.5),
                     tuple(a + nrm - t * hw * 0.5)], pulse, d + 0.048, part)


def emblem_gear(face, uc, vc, r=1.0, d=0.04, part="detail", mat="Mustard", hub="Charcoal", teeth=8):
    """Cog wheel with a hub (Torque Garage)."""
    pts = []
    for k in range(teeth):
        a0 = 2 * PI * k / teeth
        da = 2 * PI / teeth
        for (f, rr) in ((0.0, 0.78), (0.14, 1.0), (0.36, 1.0), (0.5, 0.78)):
            a = a0 + da * f
            pts.append((uc + r * rr * math.cos(a), vc + r * rr * math.sin(a)))
    fpoly(face, pts, mat, d, part)
    fdisc(face, uc, vc, r * 0.42, hub, 8, d + 0.012, part)
    fdisc(face, uc, vc, r * 0.16, mat, 6, d + 0.024, part)


# ------------------------------------------------------------------------------------------------
# furniture (all: b, x, y = centre on the floor, yaw; local +Y = front / customer side)
# ------------------------------------------------------------------------------------------------
def ceiling_light(b, x, y, z, w=1.4, d=0.35, part="detail"):
    b.box(x - w / 2, x + w / 2, y - d / 2, y + d / 2, z - 0.07, z, "LampWarm", part, "+z")


def counter(b, x, y, yaw, w, d=0.7, h=1.02, body="WoodDark", top="Cream", kick="Charcoal", stripe=None, part="interior"):
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.box(-w / 2 + 0.04, w / 2 - 0.04, -d / 2 + 0.04, d / 2 - 0.06, 0.0, 0.1, kick, "-z +z")
    f.box(-w / 2, w / 2, -d / 2, d / 2, 0.1, h - 0.06, body, "+z")
    f.box(-w / 2 - 0.03, w / 2 + 0.03, -d / 2 - 0.03, d / 2 + 0.05, h - 0.06, h, top)
    if stripe:
        f.box(-w / 2 + 0.12, w / 2 - 0.12, d / 2, d / 2 + 0.015, 0.36, 0.72, stripe, "-y")
    return f


def register(b, x, y, yaw, z=FLOOR + 1.02, part="interior"):
    """Till; the screen faces local -Y (staff side)."""
    f = Fr(b, x, y, z, yaw, part)
    f.box(-0.22, 0.22, -0.2, 0.2, 0.0, 0.11, "Charcoal", "-z")
    f.box(-0.19, 0.19, -0.18, -0.02, 0.11, 0.16, "SteelDark", "-z")
    f.box(-0.03, 0.03, 0.08, 0.14, 0.11, 0.26, "Charcoal", "-z")
    f.box(-0.17, 0.17, 0.07, 0.12, 0.24, 0.47, "Charcoal")
    f.box(-0.15, 0.15, 0.062, 0.07, 0.26, 0.45, smat("M_ScreenGlow", "Sky"), "+y")
    f.box(0.26, 0.38, -0.08, 0.04, 0.0, 0.16, "White", "-z")          # card reader
    return f


def shelf(b, x, y, yaw, w, d=0.45, h=2.0, n=4, frame="White", goods=GOODS, seed=1, back=True, fill=0.88, part="interior"):
    """Shelf unit with goods; open toward local +Y."""
    f = Fr(b, x, y, FLOOR, yaw, part)
    r = Rnd(seed)
    if back:
        f.box(-w / 2 + 0.04, w / 2 - 0.04, -d / 2, -d / 2 + 0.03, 0.1, h - 0.03, frame, "-z +z -x +x")
    f.box(-w / 2, -w / 2 + 0.04, -d / 2, d / 2, 0.0, h, frame, "-z")
    f.box(w / 2 - 0.04, w / 2, -d / 2, d / 2, 0.0, h, frame, "-z")
    f.box(-w / 2 + 0.04, w / 2 - 0.04, -d / 2, d / 2, 0.0, 0.1, frame, "-z -x +x")
    f.box(-w / 2 + 0.04, w / 2 - 0.04, -d / 2, d / 2, h - 0.03, h, frame, "-x +x")
    sp = (h - 0.13) / n
    for i in range(n):
        z = 0.1 + i * sp
        if i > 0:
            f.box(-w / 2 + 0.04, w / 2 - 0.04, -d / 2 + 0.03, d / 2, z - 0.03, z, frame, "-x +x -y")
        xx = -w / 2 + 0.08
        while xx < w / 2 - 0.22:
            gw = min(r.rng(0.16, 0.42), w / 2 - 0.08 - xx)
            if r() < fill and gw > 0.1:
                gh = sp * r.rng(0.42, 0.8)
                gd = d * r.rng(0.5, 0.8)
                f.box(xx, xx + gw - 0.03, d / 2 - 0.04 - gd, d / 2 - 0.04, z, z + gh, r.pick(goods), "-z -y")
            xx += gw
    return f


def gondola(b, x, y, yaw, w, d=0.9, h=1.55, n=3, seed=1, **kw):
    """Double-sided aisle shelving."""
    f = Fr(b, x, y, FLOOR, yaw)
    p = f.P(0, d / 4, 0)
    q = f.P(0, -d / 4, 0)
    shelf(b, p[0], p[1], yaw, w, d / 2, h, n, seed=seed, **kw)
    shelf(b, q[0], q[1], yaw + PI, w, d / 2, h, n, seed=seed + 7, **kw)


def fridge(b, x, y, yaw, w, d=0.75, h=2.15, doors=3, body="White", band="Navy", seed=3, part="interior"):
    """Glass-door cooler wall: lit interior panels with drinks, steel door frames."""
    f = Fr(b, x, y, FLOOR, yaw, part)
    r = Rnd(seed)
    yf = d / 2 - 0.05
    f.box(-w / 2, w / 2, -d / 2, yf, 0.0, h, body, "-z")
    f.box(-w / 2, w / 2, yf, d / 2, h - 0.26, h, band, "-y")
    f.box(-w / 2, w / 2, yf, d / 2, 0.0, 0.2, "Charcoal", "-y -z")
    dw = w / doors
    z0, z1 = 0.2, h - 0.26
    for i in range(doors):
        a = -w / 2 + i * dw
        f.poly(((a + 0.05, yf + 0.002, z0), (a + dw - 0.05, yf + 0.002, z0), (a + dw - 0.05, yf + 0.002, z1), (a + 0.05, yf + 0.002, z1))[::-1], "Sky")
        rows = 4
        rs = (z1 - z0) / rows
        for j in range(rows):
            zz = z0 + j * rs
            f.box(a + 0.05, a + dw - 0.05, yf, yf + 0.03, zz, zz + 0.03, "Steel", "-y -x +x -z")
            k = 4
            cw = (dw - 0.16) / k
            col = r.pick(GOODS)
            for q in range(k):
                if r() < 0.5:
                    col = r.pick(GOODS)
                xa = a + 0.08 + q * cw
                f.box(xa + 0.02, xa + cw - 0.02, yf, yf + 0.03, zz + 0.03, zz + rs * r.rng(0.55, 0.78), col, "-y -z")
        f.box(a, a + 0.05, yf, d / 2, z0, z1, "Steel", "-y -z +z")
        f.box(a + dw - 0.05, a + dw, yf, d / 2, z0, z1, "Steel", "-y -z +z")
        f.box(a + dw - 0.13, a + dw - 0.09, d / 2, d / 2 + 0.04, 0.9, 1.4, "Charcoal", "-y")
    return f


def clothes_rack(b, x, y, yaw, w=2.0, h=1.55, colors=CLOTHES, seed=5, part="interior"):
    f = Fr(b, x, y, FLOOR, yaw, part)
    r = Rnd(seed)
    for sx in (-w / 2, w / 2):
        f.box(sx - 0.025, sx + 0.025, -0.025, 0.025, 0.05, h, "Chrome", "-z")
        f.box(sx - 0.04, sx + 0.04, -0.3, 0.3, 0.0, 0.05, "Charcoal", "-z")
    f.box(-w / 2, w / 2, -0.02, 0.02, h - 0.04, h, "Chrome", "-x +x")
    n = max(2, int((w - 0.2) / 0.14))
    for i in range(n):
        gx = -w / 2 + 0.12 + i * (w - 0.24) / (n - 1)
        L = r.rng(0.55, 0.95)
        hw = r.rng(0.2, 0.25)
        f.box(gx - 0.04, gx + 0.04, -hw, hw, h - 0.1 - L, h - 0.1, r.pick(colors))
    return f


def table(b, x, y, yaw, w=1.4, d=0.8, h=0.8, top="Wood", leg="Charcoal", th=0.06, part="interior"):
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.box(-w / 2, w / 2, -d / 2, d / 2, h - th, h, top)
    for sx in (-w / 2 + 0.08, w / 2 - 0.08):
        for sy in (-d / 2 + 0.08, d / 2 - 0.08):
            f.box(sx - 0.03, sx + 0.03, sy - 0.03, sy + 0.03, 0.0, h - th, leg, "-z +z")
    return f


def folded_stacks(f, w, d, z, n=4, seed=9, colors=CLOTHES):
    """Stacks of folded clothes on a table frame `f` (top at z)."""
    r = Rnd(seed)
    cw = w / n
    for i in range(n):
        for j in range(2):
            cx = -w / 2 + (i + 0.5) * cw
            cy = (-0.25 + 0.5 * j) * d
            zz = z
            for k in range(1 + int(r() * 3.9)):
                f.box(cx - cw * 0.36, cx + cw * 0.36, cy - d * 0.17, cy + d * 0.17, zz, zz + 0.05, r.pick(colors), "-z")
                zz += 0.05


def long_gun(f, x, z, L=1.0, y0=0.0, stock="GunWood", metal="GunMetal", scope=False, mag=True):
    """Rifle silhouette lying along local +X at height z, proud of the plane y = y0."""
    y1 = y0 + 0.04
    f.box(x, x + 0.3 * L, y0, y1, z - 0.05, z + 0.05, stock, "-y")
    f.box(x + 0.3 * L, x + 0.58 * L, y0, y1, z - 0.03, z + 0.06, metal, "-y")
    f.box(x + 0.58 * L, x + L, y0, y1 - 0.01, z + 0.015, z + 0.05, metal, "-y")
    f.box(x + 0.58 * L, x + 0.8 * L, y0, y1, z - 0.02, z + 0.015, stock, "-y")
    if mag:
        f.box(x + 0.4 * L, x + 0.47 * L, y0, y1, z - 0.16, z - 0.03, metal, "-y")
    if scope:
        f.box(x + 0.34 * L, x + 0.6 * L, y0, y1, z + 0.08, z + 0.13, "GunMetalDark", "-y")


def pistol(f, x, z, y0=0.0, metal="GunMetal", flat=False):
    if flat:      # lying on a horizontal surface (z = surface), barrel along +X
        f.box(x, x + 0.2, y0 - 0.02, y0 + 0.02, z, z + 0.03, metal, "-z")
        f.box(x, x + 0.05, y0 - 0.1, y0 - 0.02, z, z + 0.028, "GunPolymer", "-z")
    else:
        f.box(x, x + 0.2, y0, y0 + 0.03, z, z + 0.045, metal, "-y")
        f.box(x, x + 0.055, y0, y0 + 0.03, z - 0.1, z, "GunPolymer", "-y")


def gun_wall(b, x, y, yaw, w, z0=1.15, z1=2.7, rows=3, per=3, board="WoodDark", seed=4, part="interior"):
    """Slat-wall panel with long guns; mount against a wall (local -Y is the wall)."""
    f = Fr(b, x, y, FLOOR, yaw, part)
    r = Rnd(seed)
    f.box(-w / 2, w / 2, 0.0, 0.05, z0, z1, board, "-y")
    f.box(-w / 2 - 0.05, w / 2 + 0.05, 0.0, 0.07, z1, z1 + 0.07, "Charcoal", "-y")
    f.box(-w / 2 - 0.05, w / 2 + 0.05, 0.0, 0.07, z0 - 0.07, z0, "Charcoal", "-y")
    rs = (z1 - z0) / rows
    cw = w / per
    for j in range(rows):
        for i in range(per):
            L = min(cw - 0.18, r.rng(0.85, 1.15))
            long_gun(f, -w / 2 + i * cw + (cw - L) / 2, z0 + (j + 0.5) * rs, L, 0.05,
                     stock=r.pick(("GunWood", "GunPolymer", "GunTan", "OliveDrab")), scope=r() < 0.4, mag=r() < 0.7)
    return f


def display_case(b, x, y, yaw, w=1.8, d=0.7, h=1.0, base="WoodDark", seed=6, part="interior"):
    """Counter-height showcase: lined tray with handguns under an open metal frame."""
    f = Fr(b, x, y, FLOOR, yaw, part)
    r = Rnd(seed)
    f.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, h - 0.28, base, "-z +z")
    f.box(-w / 2, w / 2, -d / 2, d / 2, h - 0.28, h - 0.24, "Navy", "-z")
    for sx in (-w / 2 + 0.02, w / 2 - 0.02):
        for sy in (-d / 2 + 0.02, d / 2 - 0.02):
            f.box(sx - 0.02, sx + 0.02, sy - 0.02, sy + 0.02, h - 0.24, h, "Chrome", "-z +z")
    f.box(-w / 2, w / 2, -d / 2, -d / 2 + 0.04, h - 0.03, h, "Chrome")
    f.box(-w / 2, w / 2, d / 2 - 0.04, d / 2, h - 0.03, h, "Chrome")
    f.box(-w / 2, -w / 2 + 0.04, -d / 2 + 0.04, d / 2 - 0.04, h - 0.03, h, "Chrome", "-y +y")
    f.box(w / 2 - 0.04, w / 2, -d / 2 + 0.04, d / 2 - 0.04, h - 0.03, h, "Chrome", "-y +y")
    n = max(2, int(w / 0.45))
    for i in range(n):
        px = -w / 2 + (i + 0.5) * w / n - 0.1
        pistol(f, px, h - 0.24, 0.08, metal=r.pick(("GunMetal", "GunMetalDark", "Chrome")), flat=True)
        f.box(px + 0.02, px + 0.2, -0.24, -0.12, h - 0.24, h - 0.2, r.pick(("Brass", "CarRed", "OliveDrab")), "-z")
    return f


def workbench(b, x, y, yaw, w=2.4, d=0.8, h=0.92, peg=True, top="Wood", part="interior"):
    """Workbench with a tool board at the back (local -Y) and a vise; the user stands at +Y."""
    f = Fr(b, x, y, FLOOR, yaw, part)
    for sx in (-w / 2 + 0.06, w / 2 - 0.06):
        for sy in (-d / 2 + 0.06, d / 2 - 0.06):
            f.box(sx - 0.035, sx + 0.035, sy - 0.035, sy + 0.035, 0.0, h - 0.07, "Steel", "-z +z")
    f.box(-w / 2 + 0.05, w / 2 - 0.05, -d / 2 + 0.05, d / 2 - 0.05, 0.22, 0.26, "Steel")
    f.box(-w / 2, w / 2, -d / 2, d / 2, h - 0.07, h, top)
    f.box(-w / 2 + 0.2, -w / 2 + 0.75, -d / 2 + 0.15, d / 2 - 0.2, 0.26, 0.5, "FireRed", "-z")       # toolbox on the shelf
    f.box(w / 2 - 0.8, w / 2 - 0.2, -d / 2 + 0.15, d / 2 - 0.2, 0.26, 0.44, "OliveDrab", "-z")
    f.box(w / 2 - 0.42, w / 2 - 0.2, d / 2 - 0.3, d / 2 + 0.02, h, h + 0.14, "SteelDark", "-z")      # vise
    f.box(w / 2 - 0.37, w / 2 - 0.25, d / 2 - 0.2, d / 2 - 0.1, h + 0.14, h + 0.24, "SteelDark", "-z")
    f.box(-0.3, 0.25, -0.1, 0.2, h, h + 0.04, "GunMetal", "-z")                                       # work piece
    if peg:
        f.box(-w / 2, w / 2, -d / 2, -d / 2 + 0.04, h, h + 1.0, "WarmGrey", "-z")
        yb = -d / 2 + 0.04
        f.box(-w / 2 + 0.2, -w / 2 + 0.26, yb, yb + 0.03, h + 0.35, h + 0.8, "Wood", "-y")            # hammer
        f.box(-w / 2 + 0.13, -w / 2 + 0.33, yb, yb + 0.05, h + 0.8, h + 0.88, "SteelDark", "-y")
        f.box(-w / 2 + 0.5, -w / 2 + 0.56, yb, yb + 0.02, h + 0.3, h + 0.85, "Chrome", "-y")          # wrenches
        f.box(-w / 2 + 0.65, -w / 2 + 0.7, yb, yb + 0.02, h + 0.4, h + 0.85, "Chrome", "-y")
        f.box(-w / 2 + 0.79, -w / 2 + 0.83, yb, yb + 0.02, h + 0.5, h + 0.85, "Chrome", "-y")
        f.box(-0.25, 0.45, yb, yb + 0.02, h + 0.55, h + 0.75, "Steel", "-y")                          # saw blade
        f.box(0.45, 0.62, yb, yb + 0.04, h + 0.55, h + 0.78, "SafetyOrange", "-y")
        for i in range(4):                                                                             # parts bins
            xa = w / 2 - 1.0 + i * 0.22
            f.box(xa, xa + 0.18, yb, yb + 0.14, h + 0.25, h + 0.4, ("Mustard", "CarBlue", "CarRed", "Mustard")[i], "-y")
    return f


def tool_chest(b, x, y, yaw, w=1.1, d=0.55, h=1.0, mat="FireRed", part="interior"):
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.box(-w / 2, w / 2, -d / 2, d / 2, 0.12, h, mat, "-z")
    f.box(-w / 2 - 0.02, w / 2 + 0.02, -d / 2 - 0.02, d / 2 + 0.02, h, h + 0.04, "Charcoal")
    n = 5
    dh = (h - 0.2) / n
    for i in range(n):
        z = 0.16 + i * dh
        f.box(-w / 2 + 0.04, w / 2 - 0.04, d / 2, d / 2 + 0.015, z, z + dh - 0.03, mat, "-y")
        f.box(-w / 2 + 0.15, w / 2 - 0.15, d / 2 + 0.015, d / 2 + 0.035, z + dh - 0.09, z + dh - 0.06, "Chrome", "-y")
    for sx in (-w / 2 + 0.1, w / 2 - 0.1):
        for sy in (-d / 2 + 0.1, d / 2 - 0.1):
            f.box(sx - 0.05, sx + 0.05, sy - 0.03, sy + 0.03, 0.0, 0.12, "Black", "-z +z")
    return f


def tyre(f, p0, p1, r=0.33, caps="both", rim=True):
    """Tyre between two local points on its axis."""
    f.tube(p0, p1, r, "Tire", 8, caps)
    if rim and caps != "none":
        a = Vector(p0)
        c = Vector(p1)
        t = (c - a).normalized() * 0.008
        f.tube(tuple(a - t), tuple(c + t), r * 0.56, "Rim", 6, caps)


def tyre_stack(b, x, y, n=4, r=0.33, wd=0.23, part="interior"):
    f = Fr(b, x, y, FLOOR, 0.0, part)
    for i in range(n):
        tyre(f, (0, 0, i * wd), (0, 0, (i + 1) * wd - 0.01), r, "top" if i == n - 1 else "none", rim=(i == n - 1))
    return f


def tyre_rack(b, x, y, yaw, w=2.6, h=2.1, rows=2, part="interior"):
    """Steel rack with rows of tyres (axis along the rack)."""
    f = Fr(b, x, y, FLOOR, yaw, part)
    d = 0.5
    for sx in (-w / 2, w / 2):
        for sy in (-d / 2, d / 2):
            f.box(sx - 0.03, sx + 0.03, sy - 0.03, sy + 0.03, 0.0, h, "SteelDark", "-z")
    rs = (h - 0.25) / rows
    for j in range(rows):
        z = 0.25 + j * rs
        for sy in (-d / 2 + 0.08, d / 2 - 0.08):
            f.box(-w / 2, w / 2, sy - 0.025, sy + 0.025, z - 0.05, z, "SteelDark", "-x +x")
        n = int((w - 0.1) / 0.26)
        for i in range(n):
            xa = -w / 2 + 0.06 + i * (w - 0.12) / n
            tyre(f, (xa, 0, z + 0.33), (xa + 0.23, 0, z + 0.33), 0.33,
                 "bottom" if i == 0 else ("top" if i == n - 1 else "none"), rim=(i in (0, n - 1)))
    return f


def barrel(b, x, y, mat="CarBlue", h=0.9, r=0.3, z=FLOOR, part="interior"):
    b.cyl(x, y, z, z + h, r, mat, part, 8)
    b.cyl(x, y, z + h * 0.32, z + h * 0.36, r + 0.015, "SteelDark", part, 8, caps="none")
    b.cyl(x, y, z + h * 0.66, z + h * 0.7, r + 0.015, "SteelDark", part, 8, caps="none")


def crate(b, x, y, s=0.8, z=FLOOR, mat="Wood", yaw=0.0, part="interior"):
    f = Fr(b, x, y, z, yaw, part)
    f.box(-s / 2, s / 2, -s / 2, s / 2, 0.0, s, mat, "-z")
    for sx in (-s / 2 - 0.015, s / 2 - 0.045):
        f.box(sx, sx + 0.06, -s / 2 - 0.015, s / 2 + 0.015, 0.0, s + 0.015, "WoodDark", "-z")
    return f


def sofa(b, x, y, yaw, w=2.1, d=0.92, mat="Teal", cushion="Mint", part="interior"):
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.box(-w / 2, w / 2, -d / 2, d / 2, 0.08, 0.4, mat, "-z")
    f.box(-w / 2, w / 2, -d / 2, -d / 2 + 0.24, 0.4, 0.86, mat, "-z")
    for sx in (-w / 2, w / 2 - 0.2):
        f.box(sx, sx + 0.2, -d / 2 + 0.24, d / 2, 0.4, 0.64, mat, "-z -y")
    n = max(1, int(round((w - 0.4) / 0.8)))
    cw = (w - 0.4) / n
    for i in range(n):
        xa = -w / 2 + 0.2 + i * cw
        f.box(xa + 0.02, xa + cw - 0.02, -d / 2 + 0.24, d / 2 - 0.02, 0.4, 0.52, cushion, "-z")
        f.box(xa + 0.04, xa + cw - 0.04, -d / 2 + 0.24, -d / 2 + 0.36, 0.52, 0.8, cushion, "-z -y")
    for sx in (-w / 2 + 0.08, w / 2 - 0.08):
        for sy in (-d / 2 + 0.08, d / 2 - 0.08):
            f.box(sx - 0.03, sx + 0.03, sy - 0.03, sy + 0.03, 0.0, 0.08, "WoodDark", "-z +z")
    return f


def bed(b, x, y, yaw, w=1.6, L=2.1, frame="Wood", blanket="Teal", part="interior"):
    """Bed: head at local -Y."""
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.box(-w / 2 - 0.04, w / 2 + 0.04, -L / 2 - 0.04, L / 2 + 0.04, 0.1, 0.34, frame, "-z")
    f.box(-w / 2 - 0.04, w / 2 + 0.04, -L / 2 - 0.1, -L / 2 - 0.04, 0.0, 1.1, frame, "-z")
    f.box(-w / 2, w / 2, -L / 2, L / 2, 0.34, 0.54, "White", "-z")
    f.box(-w / 2 - 0.02, w / 2 + 0.02, -L / 2 + 0.7, L / 2 + 0.02, 0.36, 0.59, blanket, "-z")
    f.box(-w / 2, w / 2, -L / 2 + 0.62, -L / 2 + 0.74, 0.54, 0.6, "White", "-z")
    for sx in (-w / 4, w / 4):
        f.box(sx - w * 0.2, sx + w * 0.2, -L / 2 + 0.08, -L / 2 + 0.5, 0.54, 0.66, "Cream", "-z")
    for sx in (-w / 2, w / 2):
        for sy in (-L / 2, L / 2):
            f.box(sx - 0.04, sx + 0.04, sy - 0.04, sy + 0.04, 0.0, 0.1, "WoodDark", "-z +z")
    return f


def wardrobe(b, x, y, yaw, w=1.8, d=0.6, h=2.2, mat="Wood", door="Cream", doors=3, part="interior"):
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, h, mat, "-z")
    f.box(-w / 2 - 0.03, w / 2 + 0.03, -d / 2, d / 2 + 0.03, h, h + 0.06, mat)
    dw = w / doors
    for i in range(doors):
        a = -w / 2 + i * dw
        f.box(a + 0.03, a + dw - 0.03, d / 2, d / 2 + 0.025, 0.12, h - 0.04, door, "-y")
        hx = a + dw - 0.12 if i % 2 == 0 else a + 0.08
        hz = min(0.95, h * 0.45)
        f.box(hx, hx + 0.04, d / 2 + 0.025, d / 2 + 0.06, hz, hz + min(0.3, h * 0.25), "Chrome", "-y")
    return f


def office_chair(b, x, y, yaw, mat="Charcoal", part="interior"):
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.box(-0.3, 0.3, -0.04, 0.04, 0.0, 0.06, "Black", "-z")
    f.box(-0.04, 0.04, -0.3, 0.3, 0.0, 0.06, "Black", "-z")
    f.box(-0.035, 0.035, -0.035, 0.035, 0.06, 0.44, "Chrome", "-z +z")
    f.box(-0.24, 0.24, -0.24, 0.24, 0.44, 0.52, mat)
    f.box(-0.22, 0.22, -0.27, -0.2, 0.52, 1.0, mat, "-z")
    return f


def stool(b, x, y, h=0.72, mat="Coral", part="interior"):
    b.cyl(x, y, FLOOR, FLOOR + 0.04, 0.2, "Chrome", part, 8)
    b.cyl(x, y, FLOOR + 0.04, FLOOR + h - 0.07, 0.03, "Chrome", part, 6, caps="none")
    b.cyl(x, y, FLOOR + h - 0.07, FLOOR + h, 0.19, mat, part, 8)


def desk(b, x, y, yaw, w=1.5, d=0.72, h=0.76, top="Wood", body="White", computer=True, part="interior"):
    """Desk; the user sits at local +Y, the screen faces +Y."""
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.box(-w / 2, w / 2, -d / 2, d / 2, h - 0.05, h, top)
    f.box(-w / 2 + 0.03, -w / 2 + 0.08, -d / 2 + 0.04, d / 2 - 0.04, 0.0, h - 0.05, body, "-z +z")
    f.box(w / 2 - 0.5, w / 2 - 0.03, -d / 2 + 0.04, d / 2 - 0.04, 0.0, h - 0.05, body, "-z +z")
    for i in range(3):
        z = 0.06 + i * 0.22
        f.box(w / 2 - 0.47, w / 2 - 0.06, d / 2 - 0.04, d / 2 - 0.025, z, z + 0.19, top, "-y")
    if computer:
        f.box(-0.12, 0.12, -d / 2 + 0.1, -d / 2 + 0.26, h, h + 0.02, "Charcoal", "-z")
        f.box(-0.03, 0.03, -d / 2 + 0.16, -d / 2 + 0.2, h + 0.02, h + 0.18, "Charcoal", "-z +z")
        f.box(-0.36, 0.36, -d / 2 + 0.15, -d / 2 + 0.2, h + 0.16, h + 0.6, "Black")
        f.box(-0.33, 0.33, -d / 2 + 0.2, -d / 2 + 0.207, h + 0.19, h + 0.57, smat("M_ScreenGlow", "Sky"), "-y")
        f.box(-0.24, 0.24, 0.02, 0.18, h, h + 0.02, "Charcoal", "-z")
        f.box(0.32, 0.39, 0.04, 0.15, h, h + 0.03, "Charcoal", "-z")
    return f


def kitchen_run(b, x, y, yaw, w=3.0, d=0.62, sink=True, stove=True, uppers=True, body="White", top="Charcoal", part="interior"):
    """Kitchen units against a wall (local -Y is the wall)."""
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.box(-w / 2, w / 2, -d / 2, d / 2 - 0.04, 0.0, 0.1, "Charcoal", "-z +z")
    f.box(-w / 2, w / 2, -d / 2, d / 2, 0.1, 0.86, body, "-z +z")
    f.box(-w / 2, w / 2, -d / 2, d / 2 + 0.03, 0.86, 0.91, top)
    n = max(2, int(round(w / 0.6)))
    dw = w / n
    for i in range(n):
        a = -w / 2 + i * dw
        f.box(a + 0.025, a + dw - 0.025, d / 2, d / 2 + 0.018, 0.14, 0.82, body, "-y")
        f.box(a + dw / 2 - 0.1, a + dw / 2 + 0.1, d / 2 + 0.018, d / 2 + 0.04, 0.74, 0.77, "Chrome", "-y")
    if sink:
        sx = -w / 2 + 0.75
        f.box(sx - 0.3, sx + 0.3, -0.2, 0.2, 0.91, 0.925, "Chrome", "-z")
        f.box(sx - 0.24, sx + 0.24, -0.15, 0.15, 0.925, 0.93, "SteelDark", "-z -x +x -y +y")
        f.box(sx - 0.02, sx + 0.02, -0.27, -0.23, 0.91, 1.15, "Chrome", "-z")
        f.box(sx - 0.02, sx + 0.02, -0.27, -0.08, 1.13, 1.17, "Chrome")
    if stove:
        sx = w / 2 - 0.75
        f.box(sx - 0.3, sx + 0.3, -0.24, 0.24, 0.91, 0.925, "Black", "-z")
        for dx in (-0.15, 0.15):
            for dy in (-0.11, 0.11):
                f.cyl(sx + dx, dy, 0.925, 0.935, 0.085, "SteelDark", 8)
        f.box(sx - 0.27, sx + 0.27, d / 2 + 0.018, d / 2 + 0.03, 0.2, 0.7, "Black", "-y")
    if uppers:
        f.box(-w / 2, w / 2, -d / 2, -d / 2 + 0.35, 1.5, 2.2, body)
        for i in range(n):
            a = -w / 2 + i * dw
            f.box(a + 0.025, a + dw - 0.025, -d / 2 + 0.35, -d / 2 + 0.368, 1.53, 2.17, body, "-y")
            f.box(a + dw - 0.09, a + dw - 0.06, -d / 2 + 0.368, -d / 2 + 0.39, 1.56, 1.76, "Chrome", "-y")
        if stove:
            f.taper((sx - 0.32, sx + 0.32, -d / 2, d / 2 - 0.1), (sx - 0.18, sx + 0.18, -d / 2, -d / 2 + 0.3), 1.32, 1.5, "Steel", cap=False)
    return f


def tall_fridge(b, x, y, yaw, w=0.75, d=0.72, h=1.85, mat="Chrome", part="interior"):
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.box(-w / 2, w / 2, -d / 2, d / 2 - 0.03, 0.03, h, mat, "-z")
    f.box(-w / 2 + 0.01, w / 2 - 0.01, d / 2 - 0.03, d / 2, 0.06, 1.15, mat, "-y")
    f.box(-w / 2 + 0.01, w / 2 - 0.01, d / 2 - 0.03, d / 2, 1.18, h - 0.01, mat, "-y")
    for z0, z1 in ((0.7, 1.08), (1.25, 1.6)):
        f.box(-w / 2 + 0.06, -w / 2 + 0.1, d / 2, d / 2 + 0.05, z0, z1, "Charcoal", "-y")
    return f


def tv_unit(b, x, y, yaw, w=1.9, part="interior"):
    """Media console + flat screen facing local +Y."""
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.box(-w / 2, w / 2, -0.22, 0.22, 0.06, 0.48, "WoodDark", "-z")
    f.box(-w / 2 + 0.05, -0.03, 0.22, 0.235, 0.1, 0.44, "Wood", "-y")
    f.box(0.03, w / 2 - 0.05, 0.22, 0.235, 0.1, 0.44, "Wood", "-y")
    f.box(-0.2, 0.2, -0.1, 0.1, 0.48, 0.52, "Charcoal", "-z")
    f.box(-0.04, 0.04, -0.03, 0.03, 0.52, 0.66, "Charcoal", "-z +z")
    f.box(-0.72, 0.72, -0.035, 0.035, 0.64, 1.48, "Black")
    f.box(-0.68, 0.68, 0.035, 0.04, 0.68, 1.44, smat("M_ScreenGlow", "Navy"), "-y")
    return f


def rug(b, x, y, w, d, mat="Coral", border="Cream", z=FLOOR, yaw=0.0):
    f = Fr(b, x, y, z, yaw, "detail")
    f.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, 0.012, border, "-z")
    f.box(-w / 2 + 0.15, w / 2 - 0.15, -d / 2 + 0.15, d / 2 - 0.15, 0.012, 0.02, mat, "-z")
    return f


def plant(b, x, y, h=1.3, pot="Terracotta", z=FLOOR, part="interior"):
    b.tube((x, y, z), (x, y, z + 0.42), 0.17, 0.24, 6, pot, part, "top")
    b.tube((x, y, z + 0.4), (x, y, z + 0.42 + (h - 0.42) * 0.45), 0.1, 0.4, 6, "LeafDark", part, "none")
    b.tube((x, y, z + 0.42 + (h - 0.42) * 0.45), (x, y, z + h), 0.4, 0.03, 6, "Leaf", part, "top")


def barber_chair(b, x, y, yaw, mat="Terracotta", part="interior"):
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.cyl(0, 0, 0.0, 0.05, 0.33, "Chrome", 8)
    f.cyl(0, 0, 0.05, 0.46, 0.07, "Chrome", 6, caps="none")
    f.box(-0.3, 0.3, -0.3, 0.3, 0.46, 0.6, mat)
    f.box(-0.28, 0.28, -0.36, -0.25, 0.6, 1.2, mat, "-z")
    f.box(-0.15, 0.15, -0.38, -0.3, 1.2, 1.42, mat, "-z")
    for sx in (-0.36, 0.3):
        f.box(sx, sx + 0.06, -0.26, 0.22, 0.6, 0.66, "Chrome", "-z")
        f.box(sx, sx + 0.06, -0.26, 0.2, 0.74, 0.8, "Charcoal")
        f.box(sx + 0.01, sx + 0.05, 0.14, 0.2, 0.66, 0.74, "Chrome", "-z +z")
    f.box(-0.2, 0.2, 0.3, 0.36, 0.2, 0.5, "Chrome", "-z")
    f.box(-0.22, 0.22, 0.34, 0.6, 0.18, 0.22, "Chrome")
    return f


def mirror_station(b, x, y, yaw, w=1.3, part="interior"):
    """Wall mirror + shelf + bulbs; local -Y is the wall (origin on the wall plane)."""
    f = Fr(b, x, y, FLOOR, yaw, part)
    f.box(-w / 2, w / 2, 0.0, 0.05, 1.0, 2.3, "White", "-y")
    f.box(-w / 2 + 0.07, w / 2 - 0.07, 0.05, 0.056, 1.07, 2.23, "Window", "-y")
    f.box(-w / 2, w / 2, 0.0, 0.34, 0.86, 0.92, "WoodDark", "-y")
    f.box(-w / 2 + 0.05, w / 2 - 0.05, 0.0, 0.3, 0.0, 0.86, "Navy", "-y -z +z")
    for i, c in enumerate(("Coral", "Teal", "Mustard", "White")):
        f.box(-w / 2 + 0.12 + i * 0.16, -w / 2 + 0.2 + i * 0.16, 0.1, 0.18, 0.92, 1.04 + 0.04 * (i % 2), c, "-z")
    for i in range(4):
        cx = -w / 2 + (i + 0.5) * w / 4
        f.box(cx - 0.06, cx + 0.06, 0.0, 0.1, 2.36, 2.48, "LampWarm", "-y")
    return f


def seat_row(b, x, y, yaw, n=3, mat="Teal", part="interior"):
    """Row of waiting-room seats on a beam (backs toward local -Y)."""
    f = Fr(b, x, y, FLOOR, yaw, part)
    w = n * 0.56
    f.box(-w / 2, w / 2, -0.05, 0.05, 0.32, 0.4, "SteelDark")
    for sx in (-w / 2 + 0.15, w / 2 - 0.15):
        f.box(sx - 0.03, sx + 0.03, -0.25, 0.25, 0.0, 0.04, "SteelDark", "-z")
        f.box(sx - 0.03, sx + 0.03, -0.03, 0.03, 0.04, 0.32, "SteelDark", "-z +z")
    for i in range(n):
        cx = -w / 2 + (i + 0.5) * 0.56
        f.box(cx - 0.24, cx + 0.24, -0.2, 0.26, 0.4, 0.46, mat)
        f.box(cx - 0.24, cx + 0.24, -0.26, -0.2, 0.46, 0.9, mat, "-z")
    return f


def lockers(b, x, y, yaw, n=4, w=0.42, d=0.5, h=1.9, mat="PoliceBlue", part="interior"):
    f = Fr(b, x, y, FLOOR, yaw, part)
    tw = n * w
    f.box(-tw / 2, tw / 2, -d / 2, d / 2, 0.0, h, mat, "-z")
    for i in range(n):
        a = -tw / 2 + i * w
        f.box(a + 0.02, a + w - 0.02, d / 2, d / 2 + 0.015, 0.08, h - 0.04, mat, "-y")
        f.box(a + 0.1, a + w - 0.1, d / 2 + 0.015, d / 2 + 0.022, h - 0.34, h - 0.2, "Charcoal", "-y")
        f.box(a + w - 0.09, a + w - 0.06, d / 2 + 0.015, d / 2 + 0.04, 0.95, 1.1, "Chrome", "-y")
    return f


def vending(b, x, y, yaw, mat="CarRed", seed=11, z=FLOOR, part="interior"):
    f = Fr(b, x, y, z, yaw, part)
    r = Rnd(seed)
    w, d, h = 1.0, 0.8, 1.95
    f.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, h, mat, "-z")
    f.box(-w / 2 + 0.06, w / 2 - 0.3, d / 2, d / 2 + 0.012, 0.55, h - 0.25, "Sky", "-y")
    for j in range(4):
        for i in range(3):
            xa = -w / 2 + 0.1 + i * 0.2
            zz = 0.6 + j * 0.28
            f.box(xa, xa + 0.15, d / 2 + 0.012, d / 2 + 0.03, zz, zz + 0.2, r.pick(GOODS), "-y")
    f.box(w / 2 - 0.24, w / 2 - 0.06, d / 2, d / 2 + 0.015, 0.9, 1.5, "Charcoal", "-y")
    f.box(w / 2 - 0.2, w / 2 - 0.1, d / 2 + 0.015, d / 2 + 0.025, 1.3, 1.42, "LampWarm", "-y")
    f.box(-w / 2 + 0.1, w / 2 - 0.3, d / 2, d / 2 + 0.02, 0.18, 0.4, "Black", "-y")
    f.box(-w / 2 + 0.04, w / 2 - 0.04, d / 2, d / 2 + 0.015, h - 0.2, h - 0.04, "White", "-y")
    return f


def notice_board(face, u0, u1, v0, v1, d=0.0, part="interior", seed=2):
    """Pin board with papers on a K.Face (e.g. an inner wall face)."""
    r = Rnd(seed)
    face.box(u0, u1, v0, v1, d, d + 0.04, "Wood", part, "k")
    face.box(u0 + 0.06, u1 - 0.06, v0 + 0.06, v1 - 0.06, d + 0.04, d + 0.05, "TrunkLight", part, "k")
    n = max(2, int((u1 - u0) / 0.35))
    for i in range(n):
        ua = u0 + 0.12 + i * (u1 - u0 - 0.24) / n
        hh = r.rng(0.25, min(0.45, v1 - v0 - 0.3))
        vb = r.rng(v0 + 0.12, v1 - 0.12 - hh)
        face.rect(ua, ua + 0.24, vb, vb + hh, r.pick(("White", "Cream", "Mustard", "Sky", "Rose")), d + 0.055, part)


def bollard(b, x, y, h=0.95, r=0.11, mat="HazardYellow", part="body", z=0.0):
    b.cyl(x, y, z, z + h, r, mat, part, 8)
    b.cyl(x, y, z + h - 0.3, z + h - 0.2, r + 0.006, "Charcoal", part, 8, caps="none")


# ------------------------------------------------------------------------------------------------
# QA renders
# ------------------------------------------------------------------------------------------------
def _bounds(names):
    objs = set()
    for n in names:
        r = bpy.data.objects.get(n)
        if r is None:
            raise RuntimeError("no object named %r" % n)
        objs.update(G.children_of(r))
    bpy.context.view_layer.update()
    pts = []
    for o in objs:
        if o.type == 'MESH' and not o.hide_render:
            pts.extend(o.matrix_world @ Vector(c) for c in o.bound_box)
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return objs, mn, mx


def render_tiles(names, out_name, cams, res=520, cull=True, background=(0.20, 0.22, 0.26)):
    """Workbench contact sheet from explicit cameras. cams = [dict(eye, look, ortho=None | scale,
    lens=18, clip=(start, end))] in WORLD space. Everything else is hidden for the render only and all
    settings are restored (same approach as gta_bl.preview)."""
    import numpy as np
    G.object_mode()
    if isinstance(names, str):
        names = [names]
    scene = bpy.context.scene
    objs, mn, mx = _bounds(names)
    r = scene.render
    sh = scene.display.shading
    saved = {"engine": r.engine, "rx": r.resolution_x, "ry": r.resolution_y, "pct": r.resolution_percentage,
             "path": r.filepath, "fmt": r.image_settings.file_format, "cam": scene.camera, "transparent": r.film_transparent}
    saved_sh = {}
    for k in ("light", "color_type", "show_cavity", "show_shadows", "show_object_outline", "background_type",
              "background_color", "cavity_type", "show_backface_culling"):
        try:
            v = getattr(sh, k)
            saved_sh[k] = tuple(v) if k == "background_color" else v
        except Exception:
            pass
    hidden = []
    for o in scene.objects:
        if o not in objs and not o.hide_render:
            o.hide_render = True
            hidden.append(o)
    cam_data = bpy.data.cameras.new("_lm_preview_cam")
    cam = bpy.data.objects.new("_lm_preview_cam", cam_data)
    scene.collection.objects.link(cam)
    tmp_paths = []
    out_path = os.path.join(G.PREVIEW_DIR, out_name + ".png")
    try:
        r.engine = 'BLENDER_WORKBENCH'
        for k, v in (("light", 'STUDIO'), ("color_type", 'MATERIAL'), ("show_cavity", True), ("cavity_type", 'BOTH'),
                     ("show_shadows", False), ("show_object_outline", True), ("background_type", 'VIEWPORT'),
                     ("background_color", background), ("show_backface_culling", bool(cull))):
            try:
                setattr(sh, k, v)
            except Exception:
                pass
        r.resolution_x = res
        r.resolution_y = res
        r.resolution_percentage = 100
        r.film_transparent = False
        r.image_settings.file_format = 'PNG'
        scene.camera = cam
        os.makedirs(G.PREVIEW_DIR, exist_ok=True)
        tiles = []
        for i, c in enumerate(cams):
            eye = Vector(c["eye"])
            look = Vector(c["look"])
            d = (eye - look).normalized()
            if c.get("ortho"):
                cam_data.type = 'ORTHO'
                cam_data.ortho_scale = c["ortho"]
            else:
                cam_data.type = 'PERSP'
                cam_data.lens = c.get("lens", 18)
            clip = c.get("clip", (0.05, 2000.0))
            cam_data.clip_start, cam_data.clip_end = clip
            cam.location = eye
            cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
            tmp = os.path.join(G.PREVIEW_DIR, "_tmp_%s_%d.png" % (re.sub(r'[^A-Za-z0-9_]', '_', out_name), i))
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
        out = bpy.data.images.new("_lm_preview_sheet", cols * res, rows * res, alpha=False)
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
        scene.camera = saved["cam"]
        try:
            r.engine = saved["engine"]
        except Exception:
            pass
        r.resolution_x = saved["rx"]
        r.resolution_y = saved["ry"]
        r.resolution_percentage = saved["pct"]
        r.filepath = saved["path"]
        r.film_transparent = saved["transparent"]
        try:
            r.image_settings.file_format = saved["fmt"]
        except Exception:
            pass
        for k, v in saved_sh.items():
            try:
                setattr(sh, k, v)
            except Exception:
                pass
        for t in tmp_paths:
            try:
                os.remove(t)
            except Exception:
                pass
    print("PREVIEW_SAVED:", out_path)
    return out_path


def cutaway(name, out_name=None, cut=2.7, views=((0.0, -0.001, 1.0), (0.8, 1.0, 1.25), (-0.8, -1.0, 1.25), (-0.8, 1.0, 1.25)),
            res=560, box=None):
    """Interior QA ("dollhouse"): renders temporary copies of the meshes that are sliced off at height
    `cut` (asset space), so the roof and ceilings are gone and the rooms can be inspected from above.
    The temporary objects (`_lm_cut_*`) are removed again. box = (x0, x1, y0, y1) region to frame."""
    root = bpy.data.objects[name]
    scene = bpy.context.scene
    bpy.context.view_layer.update()
    Mi = root.matrix_world.inverted()
    troot = bpy.data.objects.new("_lm_cut_root", None)
    scene.collection.objects.link(troot)
    troot.matrix_world = root.matrix_world.copy()
    temps = []
    try:
        for ch in root.children_recursive:
            if ch.type != 'MESH':
                continue
            bm = bmesh.new()
            bm.from_mesh(ch.data)
            bmesh.ops.transform(bm, matrix=Mi @ ch.matrix_world, verts=bm.verts[:])
            if box:
                for co, no in (((box[0], 0, 0), (-1, 0, 0)), ((box[1], 0, 0), (1, 0, 0)), ((0, box[2], 0), (0, -1, 0)), ((0, box[3], 0), (0, 1, 0))):
                    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5, plane_co=co, plane_no=no, clear_outer=True)
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5, plane_co=(0, 0, cut),
                                   plane_no=(0, 0, 1), clear_outer=True)
            if len(bm.faces) == 0:
                bm.free()
                continue
            me = bpy.data.meshes.new("_lm_cut_mesh")
            bm.to_mesh(me)
            bm.free()
            for m in ch.data.materials:
                me.materials.append(m)
            ob = bpy.data.objects.new("_lm_cut_part", me)
            scene.collection.objects.link(ob)
            ob.parent = troot
            temps.append(ob)
        _, mn, mx = _bounds(["_lm_cut_root"])
        c = (mn + mx) / 2
        radius = (mx - mn).length / 2
        cams = []
        for v in views:
            d = Vector(v).normalized()
            top = d.z > 0.98
            ext = max(mx.x - mn.x, mx.y - mn.y) * 1.08 if top else radius * 2 * 1.02
            cams.append(dict(eye=c + d * (radius * 4 + 20.0), look=c, ortho=ext, clip=(0.1, radius * 9 + 80.0)))
        return render_tiles("_lm_cut_root", out_name or ("lm_%s_cut" % name), cams, res)
    finally:
        for ob in temps:
            me = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if me.users == 0:
                bpy.data.meshes.remove(me)
        bpy.data.objects.remove(troot, do_unlink=True)


def shot(name, views, out_name=None, lens=15, res=560):
    """Perspective camera shots from inside / around the asset. views = [(eye, look)] in asset space."""
    root = bpy.data.objects[name]
    M = root.matrix_world
    cams = [dict(eye=M @ Vector(e), look=M @ Vector(l), lens=lens, clip=(0.05, 800.0)) for e, l in views]
    return render_tiles(name, out_name or ("lm_%s_in" % name), cams, res, cull=True)


# ------------------------------------------------------------------------------------------------
# export / manifest
# ------------------------------------------------------------------------------------------------
def export(name, rel=None):
    """Export with clean node names for ALL descendants (meshes, markers, sub objects): the
    `<name>_` prefix only exists inside Blender, where object names are global."""
    root = bpy.data.objects.get(name)
    if root is None:
        raise RuntimeError("no asset root %r" % name)
    mine = []
    others = []
    try:
        for ch in list(root.children_recursive):
            if not ch.name.startswith(name + "_"):
                continue
            clean = ch.name[len(name) + 1:]
            other = bpy.data.objects.get(clean)
            if other is not None and other is not ch:
                others.append((other, clean))
                other.name = "__lm_tmp_%d" % len(others)
            mine.append((ch, ch.name))
            ch.name = clean
        return G.export_glb(name, rel or ("buildings/%s.glb" % name))
    finally:
        for ch, old in mine:
            ch.name = old
        for other, clean in others:
            other.name = clean


def check_markers(name):
    """Marker Empties of an asset -> {clean name: (x, y, z) asset space}."""
    root = bpy.data.objects[name]
    out = {}
    for ch in root.children_recursive:
        if ch.type == 'EMPTY' and ch.name.startswith(name + "_"):
            out[ch.name[len(name) + 1:]] = tuple(round(c, 3) for c in ch.location)
    return out
