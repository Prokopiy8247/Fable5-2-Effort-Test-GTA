"""building_kit - reusable "Sunlit Low-Poly" building kit for Halcyon Bay (Blender 5.2, bmesh only).

USAGE GUIDE (read this first - full reference in docs/BUILDING_KIT.md)
=====================================================================
Inside an MCP `execute_blender_code` call:

    import sys, importlib
    P = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Ultracode\\tools\\blender"
    for p in (P, P + r"\\assets"):
        if p not in sys.path: sys.path.append(p)
    import gta_bl as G; importlib.reload(G)
    import building_kit as K; importlib.reload(K)
    G.assert_master()

    b = K.Builder("my_shop", slot=40, scheme=dict(wall="Peach", base="Terracotta", trim="White"))
    m = b.mass(-8, 8, -6, 6)                       # rectangular mass (x0, x1, y0, y1), front = +Y
    W = K.win(1.6, 1.5, frame="trim", sill_bar="trim")
    m.front.row(0.0, 4.0, [K.shop(door="center"), K.shop(door="none")], mat="base")
    m.front.row(4.0, 3.2, [W] * 4)                 # one row of 4 window bays
    for f in (m.right, m.back, m.left):
        f.stack(0.0, [(4.0, None, "base"), (3.2, [W] * f.nb)])
    m.front.awning(0.5, 15.5, 3.4, stripes=8)
    m.front.sign(4.0, 12.0, 3.45, 4.0, "CAFE", color="NeonMagenta")   # block-letter neon sign
    b.belt(m.pts, 4.0)                              # string course around the mass
    b.flat_roof(m.pts, 7.2, parapet=0.7)
    b.ac_unit(2.0, 0.0, 7.2)
    b.entrance = (0.0, 6.0)
    b.finish(category="storefront", tags=["midtown"])
    K.preview("my_shop")                            # contact sheet with BACKFACE CULLING (flipped faces show as holes)
    K.audit("my_shop")                              # flipped-normal / duplicate-face heuristics
    K.export("my_shop")                             # -> gta/generated/models/buildings/my_shop.glb
    G.save()

Concepts
--------
* Builder     one building = one root Empty + up to four joined mesh objects:
                <id>_Building        opaque shell, always inside the footprint (box collider)
                <id>_Building_Glass  every M_Window pane (the game swaps in a lit-window shader)
                <id>_Building_Detail small parts / overhangs: awnings, sign boards, rails, AC units ...
                <id>_Building_Neon   emissive P_Neon* strips and block letters
              K.export() writes them as nodes `Building`, `Building_Glass`, `Building_Detail`,
              `Building_Neon` (the id prefix only exists inside Blender, where names are global).
* Mass        axis-aligned box volume with four Face objects: .front (+Y) .back (-Y) .left (-X) .right (+X).
              Non-rectangular plans: b.faces(points_ccw, z0) gives one Face per edge.
* Face        a facade plane with its own (u, v, d) frame: u = to the RIGHT as seen from outside,
              v = up, d = outward (negative = recessed). Everything facade-related is a Face method:
              row() / stack() (bays with openings), wall(), corrugated(), pilaster(), fin(), awning(),
              sign(), text(), blade_sign(), balcony(), fire_escape(), canopy(), steps(), porch(), dock() ...
              ... dado() (proud base course), dress_shop() (fascia sign + awning for one shop bay),
              applied_window(), bay_window().
* Builder     also owns everything that is not tied to one facade: belt() cornice() plinth(), the roofs
              (flat_roof, slab_roof, gable_roof, hip_roof, shed_roof, sawtooth_roof, barrel_roof, roof_lights),
              rooftop / yard props (ac_unit, water_tank, antenna, dish, stair_box, skylight, chimney, stack,
              vent, tank_h, silo, solar, planter, roof_sign, lamp_post) and the drivable pieces deck() + ramp().
* Bay specs   small dicts made by K.win() K.door() K.shop() K.rollup() K.garage_door() K.louvre(); None = blank bay.
* Materials   every `mat` argument is a scheme role ("wall", "trim", "base", "roof", "door", "metal",
              "awning", "sign", "neon", "accent", ...) or a gta_bl.PALETTE key ("Coral", "NeonCyan") or
              "M_Window". Window glass always lands in the Glass object, P_Neon* in the Neon object.
* Grid        MODULE 4 m bays, GROUND_H 4.0 m ground floor, FLOOR_H 3.2 m upper floors.
* Windings    all faces are created with explicit outward windings (no recalc) so open shells are safe.

Everything is re-runnable: Builder(name) deletes the previous version of that asset first.
"""
import bpy
import bmesh
import json
import math
import os
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import gta_bl as G

MODULE = 4.0
GROUND_H = 4.0
FLOOR_H = 3.2
SKIRT = 0.8            # foundation skirt below z = 0 (hides gaps on uneven ground)
NEON_STRENGTH = 4.0
WINDOW_MAT = "M_Window"
EPS = 1e-4
UP = Vector((0.0, 0.0, 1.0))

PARTS = (("body", "Building"), ("glass", "Building_Glass"), ("detail", "Building_Detail"), ("neon", "Building_Neon"))

DEFAULT_SCHEME = dict(
    wall="Cream", wall2="Peach", base="WarmGrey", trim="White", roof="RoofGrey", door="WoodDark",
    metal="Charcoal", awning="Awning", awning2="White", sign="Charcoal", neon="NeonCyan",
    accent="Teal", concrete="Concrete", glass=WINDOW_MAT,
)

_METALS = {"Steel": (0.45, 0.55), "SteelDark": (0.45, 0.55), "Chrome": (0.25, 0.9), "Rim": (0.3, 0.8)}


def material(key):
    """Resolve a palette key / contract material name to a shared bpy material."""
    if not isinstance(key, str):
        return key
    if key == WINDOW_MAT:
        return G.mat(WINDOW_MAT, G.pal("WindowDark"), rough=0.18, metal=0.25)
    if key.startswith("M_") or key.startswith("P_"):
        m = bpy.data.materials.get(key)
        if m is None:
            raise KeyError("unknown material %r" % key)
        return m
    if key.startswith("Neon") or key == "LampWarm":
        return G.pmat(key, rough=0.4, emit_strength=NEON_STRENGTH)
    if key in _METALS:
        r, mt = _METALS[key]
        return G.pmat(key, rough=r, metal=mt)
    return G.pmat(key)


# ------------------------------------------------------------------------------------------------
# bay specs
# ------------------------------------------------------------------------------------------------
def win(w=1.6, h=1.5, sill=0.95, **kw):
    """Window bay. Options: recess (0.18), frame=<mat> (proud trim frame), frame_w, proud, sill_bar=<mat>,
    bars=(nx, ny) muntins, bar_mat, panes=(nx, ny) separate lit cells, shutters=<mat>, lintel=<mat>,
    planter=True, awning=<mat or (mat, mat)>, count (windows in the bay), gap, off (u offset),
    balcony=dict(depth, w, style, mat ...), reveal=<mat>."""
    d = dict(k="win", w=w, h=h, sill=sill)
    d.update(kw)
    return d


def door(w=1.1, h=2.2, **kw):
    """Door bay. Options: recess (0.3), mat ("door"), glass (0..1 glazed fraction from the top),
    double, frame=<mat>, transom (height of a glazed transom above), align (0..1 inside the bay),
    canopy=dict(depth, mat, extra), handle (True)."""
    d = dict(k="door", w=w, h=h)
    d.update(kw)
    return d


def shop(**kw):
    """Storefront glazing bay. Options: margin (0.3 pier each side), head (3.0), riser (0.5), recess (0.25),
    door "center" | "left" | "right" | "none", door_w, pane (target pane width 1.8), frame, riser_mat,
    door_mat."""
    d = dict(k="shop")
    d.update(kw)
    return d


def rollup(w=3.2, h=3.4, **kw):
    """Roll-up / sectional door bay. Options: recess (0.2), mat ("Steel"), slat (0.3), sill (0),
    lights=True (row of small panes), frame=<mat>."""
    d = dict(k="rollup", w=w, h=h)
    d.update(kw)
    return d


def garage_door(w=2.6, h=2.2, **kw):
    """Domestic sectional garage door (a rollup() with house-style defaults: white, wide slats, trim frame)."""
    d = dict(mat="White", slat=0.55, frame="trim")
    d.update(kw)
    return rollup(w, h, **d)


def louvre(w=1.2, h=0.8, sill=1.6, **kw):
    """Ventilation louvre (dark slatted opening). Options: recess, mat."""
    d = dict(k="louvre", w=w, h=h, sill=sill)
    d.update(kw)
    return d


class Op(object):
    """One rectangular opening in a wall, in face coordinates."""
    __slots__ = ("a0", "a1", "b0", "b1", "rec", "rmat", "proud")

    def __init__(self, a0, a1, b0, b1, rec=0.18, rmat=None, proud=0.0):
        self.a0, self.a1, self.b0, self.b1 = a0, a1, b0, b1
        self.rec, self.rmat, self.proud = rec, rmat, proud


# ------------------------------------------------------------------------------------------------
# block-letter font (5 px tall) for geometry signage
# ------------------------------------------------------------------------------------------------
FONT = {
    "A": (".#.", "#.#", "###", "#.#", "#.#"), "B": ("##.", "#.#", "##.", "#.#", "##."),
    "C": ("###", "#..", "#..", "#..", "###"), "D": ("##.", "#.#", "#.#", "#.#", "##."),
    "E": ("###", "#..", "##.", "#..", "###"), "F": ("###", "#..", "##.", "#..", "#.."),
    "G": ("###", "#..", "#.#", "#.#", "###"), "H": ("#.#", "#.#", "###", "#.#", "#.#"),
    "I": ("###", ".#.", ".#.", ".#.", "###"), "J": ("..#", "..#", "..#", "#.#", ".#."),
    "K": ("#.#", "#.#", "##.", "#.#", "#.#"), "L": ("#..", "#..", "#..", "#..", "###"),
    "M": ("#...#", "##.##", "#.#.#", "#...#", "#...#"), "N": ("#..#", "##.#", "#.##", "#..#", "#..#"),
    "O": ("###", "#.#", "#.#", "#.#", "###"), "P": ("##.", "#.#", "##.", "#..", "#.."),
    "Q": ("###", "#.#", "#.#", "###", "..#"), "R": ("##.", "#.#", "##.", "#.#", "#.#"),
    "S": ("###", "#..", "###", "..#", "###"), "T": ("###", ".#.", ".#.", ".#.", ".#."),
    "U": ("#.#", "#.#", "#.#", "#.#", "###"), "V": ("#.#", "#.#", "#.#", "#.#", ".#."),
    "W": ("#...#", "#...#", "#.#.#", "##.##", "#...#"), "X": ("#.#", "#.#", ".#.", "#.#", "#.#"),
    "Y": ("#.#", "#.#", ".#.", ".#.", ".#."), "Z": ("###", "..#", ".#.", "#..", "###"),
    "0": (".#.", "#.#", "#.#", "#.#", ".#."), "1": (".#.", "##.", ".#.", ".#.", "###"),
    "2": ("##.", "..#", ".#.", "#..", "###"), "3": ("##.", "..#", ".#.", "..#", "##."),
    "4": ("#.#", "#.#", "###", "..#", "..#"), "5": ("###", "#..", "##.", "..#", "##."),
    "6": (".##", "#..", "###", "#.#", "###"), "7": ("###", "..#", ".#.", ".#.", ".#."),
    "8": ("###", "#.#", "###", "#.#", "###"), "9": ("###", "#.#", "###", "..#", "##."),
    "&": (".#..", "#.#.", ".#.#", "#.#.", ".#.#"), "-": ("...", "...", "###", "...", "..."),
    "+": ("...", ".#.", "###", ".#.", "..."), ".": (".", ".", ".", ".", "#"), "!": ("#", "#", "#", ".", "#"),
    "'": ("#", "#", ".", ".", "."), ":": (".", "#", ".", "#", "."), "/": ("..#", "..#", ".#.", "#..", "#.."),
    "*": ("...", "#.#", ".#.", "#.#", "..."),
}


def _glyph_rects(rows):
    h = len(rows)
    w = len(rows[0])
    used = [[False] * w for _ in range(h)]
    rects = []
    for r in range(h):
        for c in range(w):
            if rows[r][c] != "#" or used[r][c]:
                continue
            c1 = c
            while c1 + 1 < w and rows[r][c1 + 1] == "#" and not used[r][c1 + 1]:
                c1 += 1
            r1 = r
            while r1 + 1 < h and all(rows[r1 + 1][k] == "#" and not used[r1 + 1][k] for k in range(c, c1 + 1)):
                r1 += 1
            for rr in range(r, r1 + 1):
                for cc in range(c, c1 + 1):
                    used[rr][cc] = True
            rects.append((c, r, c1 + 1, r1 + 1))
    return rects


def text_rects(text):
    """-> (rects [(c0, r0, c1, r1)] in pixel units, total columns). Rows count from the top."""
    rects = []
    col = 0
    for ch in text.upper():
        if ch == " ":
            col += 2
            continue
        g = FONT.get(ch)
        if g is None:
            col += 2
            continue
        for (c0, r0, c1, r1) in _glyph_rects(g):
            rects.append((col + c0, r0, col + c1, r1))
        col += len(g[0]) + 1
    return rects, max(col - 1, 1)


def text_width(text, px):
    return text_rects(text)[1] * px


# ------------------------------------------------------------------------------------------------
# small geometry helpers
# ------------------------------------------------------------------------------------------------
def _newell(pts):
    n = Vector((0.0, 0.0, 0.0))
    c = len(pts)
    for i in range(c):
        a = pts[i]
        b = pts[(i + 1) % c]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n


def _out_normal(a, b):
    t = Vector((b[0] - a[0], b[1] - a[1]))
    t.normalize()
    return Vector((t.y, -t.x))


def offset_poly(pts, d):
    """Offset a CCW plan polygon outward by d (negative = inward) with mitred corners."""
    out = []
    n = len(pts)
    for k in range(n):
        p = Vector((pts[k][0], pts[k][1]))
        n1 = _out_normal(pts[k - 1], pts[k])
        n2 = _out_normal(pts[k], pts[(k + 1) % n])
        m = (n1 + n2) / (1.0 + n1.dot(n2))
        out.append((p.x + m.x * d, p.y + m.y * d))
    return out


def rect_pts(x0, x1, y0, y1):
    """CCW plan rectangle; edge order = back (-Y), right (+X), front (+Y), left (-X)."""
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


_BOX_FACES = {
    "+d": ((0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)),
    "-d": ((1, 0, 0), (0, 0, 0), (0, 1, 0), (1, 1, 0)),
    "+u": ((1, 0, 1), (1, 0, 0), (1, 1, 0), (1, 1, 1)),
    "-u": ((0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)),
    "+v": ((0, 1, 1), (1, 1, 1), (1, 1, 0), (0, 1, 0)),
    "-v": ((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)),
}
_WORLD_SKIP = {"-x": "-u", "+x": "+u", "-y": "-v", "+y": "+v", "-z": "-d", "+z": "+d"}
_FACE_SKIP = {"l": "-u", "r": "+u", "b": "-v", "t": "+v", "k": "-d", "f": "+d"}


class _Part(object):
    def __init__(self, with_cells=False):
        self.bm = bmesh.new()
        self.mats = []
        self.index = {}
        self.uv = self.bm.loops.layers.uv.new("UVMap") if with_cells else None

    def mi(self, m):
        i = self.index.get(m.name)
        if i is None:
            i = len(self.mats)
            self.mats.append(m)
            self.index[m.name] = i
        return i


# ------------------------------------------------------------------------------------------------
# Builder
# ------------------------------------------------------------------------------------------------
class Builder(object):
    """Accumulates the geometry of one building. See the module docstring."""

    def __init__(self, name, slot=0, scheme=None, region="buildings", collection="Buildings", location=None):
        G.assert_master()
        G.object_mode()
        self.name = name
        loc = location if location is not None else G.slot(region, slot)
        self.root = G.asset_root(name, collection, loc, rebuild=True)
        self.parts = dict((k, _Part(k == "glass")) for k, _ in PARTS)
        self.S = dict(DEFAULT_SCHEME)
        if scheme:
            self.S.update(scheme)
        self.masses = []
        self.solids = []          # extra collision boxes (x0, x1, y0, y1, z0, z1)
        self.cells = 0            # running window-cell counter (UV cell id of M_Window panes)
        self.entrance = None      # (x, y) Blender coords of the main door on the footprint edge
        self.roof_z = 0.0         # main roof deck height (for the manifest)
        self.floors = 0

    # ---- core ---------------------------------------------------------------------------------
    def _target(self, mat, part):
        key = self.S.get(mat, mat) if isinstance(mat, str) else mat
        if isinstance(key, str):
            if key == WINDOW_MAT:
                part = "glass"
            elif key.startswith("Neon"):
                part = "neon"
        p = self.parts[part]
        return p, p.mi(material(key))

    def poly(self, pts, mat, part="body"):
        """n-gon from points given counter-clockwise as seen from OUTSIDE."""
        p, mi = self._target(mat, part)
        vs = [p.bm.verts.new((q[0], q[1], q[2])) for q in pts]
        f = p.bm.faces.new(vs)
        f.material_index = mi
        if p.uv is not None:
            k = self.cells
            self.cells += 1
            cu, cv = float(k % 64), float(k // 64)
            n = len(vs)
            if n == 4:
                uvs = ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))
            elif n == 3:
                uvs = ((0.0, 0.0), (1.0, 0.0), (0.5, 1.0))
            else:
                uvs = [(0.5 + 0.5 * math.cos(2 * math.pi * i / n), 0.5 + 0.5 * math.sin(2 * math.pi * i / n)) for i in range(n)]
            for lp, uv in zip(f.loops, uvs):
                lp[p.uv].uv = (cu + uv[0], cv + uv[1])
        return f

    def quad(self, a, b, c, d, mat, part="body"):
        return self.poly((a, b, c, d), mat, part)

    def poly_dir(self, pts, direction, mat, part="body"):
        """n-gon whose normal is forced to point along `direction` (winding fixed automatically)."""
        pts = [Vector(p) for p in pts]
        if _newell(pts).dot(Vector(direction)) < 0:
            pts.reverse()
        return self.poly(pts, mat, part)

    def _box(self, P, a0, a1, b0, b1, c0, c1, mat, part, skip):
        if a1 < a0:
            a0, a1 = a1, a0
        if b1 < b0:
            b0, b1 = b1, b0
        if c1 < c0:
            c0, c1 = c1, c0
        if a1 - a0 < EPS or b1 - b0 < EPS or c1 - c0 < EPS:
            return
        A = (a0, a1)
        B = (b0, b1)
        C = (c0, c1)
        for name, idx in _BOX_FACES.items():
            if name in skip:
                continue
            self.poly([P(A[i], B[j], C[k]) for (i, j, k) in idx], mat, part)

    def box(self, x0, x1, y0, y1, z0, z1, mat, part="body", skip=""):
        """World-axis box. skip: space separated faces to omit, e.g. "-z" or "-z +y"."""
        sk = set(_WORLD_SKIP[t] for t in skip.split())
        self._box(lambda a, b, c: (a, b, c), x0, x1, y0, y1, z0, z1, mat, part, sk)

    def extrude(self, pts, vec, mat, part="body", caps=True, closed=True, cap_mat=None):
        """Extrude a planar polygon (3D points) along vec. Orientation is detected automatically.
        closed=False treats pts as an open profile: the implied closing edge (last -> first point)
        gets no side face - use it for the edge that sits against a wall. caps still close the ends."""
        pts = [Vector(p) for p in pts]
        vec = Vector(vec)
        n = len(pts)
        flip = _newell(pts).dot(vec) < 0
        last = n if closed else n - 1
        for i in range(last):
            a = pts[i]
            b = pts[(i + 1) % n]
            if (a - b).length < EPS:
                continue
            if flip:
                self.poly((b, a, a + vec, b + vec), mat, part)
            else:
                self.poly((a, b, b + vec, a + vec), mat, part)
        if caps:
            cm = cap_mat or mat
            c = caps if isinstance(caps, (tuple, list)) else (True, True)
            if c[0]:
                self.poly(pts if flip else list(reversed(pts)), cm, part)
            if c[1]:
                self.poly([p + vec for p in (reversed(pts) if flip else pts)], cm, part)

    def prism(self, profile, lo, hi, axis, mat, part="body", caps=True, closed=True, cap_mat=None):
        """Extrude a 2D profile between lo..hi along a world axis.
        axis "x": profile points are (y, z); "y": (x, z); "z": (x, y)."""
        if axis == "x":
            pts = [(lo, p[0], p[1]) for p in profile]
            vec = (hi - lo, 0, 0)
        elif axis == "y":
            pts = [(p[0], lo, p[1]) for p in profile]
            vec = (0, hi - lo, 0)
        else:
            pts = [(p[0], p[1], lo) for p in profile]
            vec = (0, 0, hi - lo)
        self.extrude(pts, vec, mat, part, caps, closed, cap_mat)

    def tube(self, p0, p1, r0, r1=None, seg=10, mat="metal", part="detail", caps="both", phase=0.0):
        """Faceted cylinder / frustum / cone between two points. caps: "both" | "top" | "bottom" | "none"."""
        p0 = Vector(p0)
        p1 = Vector(p1)
        r1 = r0 if r1 is None else r1
        ax = (p1 - p0)
        if ax.length < EPS:
            return
        ax.normalize()
        a = ax.orthogonal().normalized()
        if abs(ax.z) > 0.999:
            a = Vector((1.0, 0.0, 0.0))
        b = ax.cross(a)
        ring0 = []
        ring1 = []
        for i in range(seg):
            t = phase + 2 * math.pi * i / seg
            dirv = a * math.cos(t) + b * math.sin(t)
            ring0.append(p0 + dirv * r0)
            ring1.append(p1 + dirv * r1)
        for i in range(seg):
            j = (i + 1) % seg
            if r1 < EPS:
                self.poly((ring0[i], ring0[j], p1), mat, part)
            elif r0 < EPS:
                self.poly((p0, ring1[j], ring1[i]), mat, part)
            else:
                self.poly((ring0[i], ring0[j], ring1[j], ring1[i]), mat, part)
        if caps in ("both", "top") and r1 >= EPS:
            self.poly(ring1, mat, part)
        if caps in ("both", "bottom") and r0 >= EPS:
            self.poly(list(reversed(ring0)), mat, part)

    def cyl(self, x, y, z0, z1, r, mat="metal", part="detail", seg=10, r2=None, caps="top", phase=0.0):
        """Vertical faceted cylinder (r2 = top radius)."""
        self.tube((x, y, z0), (x, y, z1), r, r2, seg, mat, part, caps, phase)

    def taper(self, bottom, top, z0, z1, mat, part="body", cap=True, cap_mat=None):
        """Frustum between two plan rectangles (x0, x1, y0, y1) at z0 and z1."""
        a = [(bottom[0], bottom[2], z0), (bottom[1], bottom[2], z0), (bottom[1], bottom[3], z0), (bottom[0], bottom[3], z0)]
        c = [(top[0], top[2], z1), (top[1], top[2], z1), (top[1], top[3], z1), (top[0], top[3], z1)]
        for i in range(4):
            j = (i + 1) % 4
            self.poly((a[i], a[j], c[j], c[i]), mat, part)
        if cap:
            self.poly(c, cap_mat or mat, part)

    def ring(self, pts, profile, mat, part="body", closed=False, edges=None):
        """Sweep a profile [(d, z)] around a CCW plan polygon with mitred corners (cornices, belts,
        copings, plinths, parapets). d = outward offset. The profile runs counter-clockwise in a
        (d right, z up) section drawing: up the outer side, inward across the top."""
        n = len(pts)
        secs = []
        for k in range(n):
            p = Vector((pts[k][0], pts[k][1]))
            n1 = _out_normal(pts[k - 1], pts[k])
            n2 = _out_normal(pts[k], pts[(k + 1) % n])
            m = (n1 + n2) / (1.0 + n1.dot(n2))
            secs.append([Vector((p.x + m.x * d, p.y + m.y * d, z)) for d, z in profile])
        cnt = len(profile)
        last = cnt if closed else cnt - 1
        for k in range(n):
            if edges is not None and k not in edges:
                continue
            A = secs[k]
            B = secs[(k + 1) % n]
            for i in range(last):
                j = (i + 1) % cnt
                if (A[i] - A[j]).length < EPS:
                    continue
                self.poly((A[i], B[i], B[j], A[j]), mat, part)

    # ---- masses -------------------------------------------------------------------------------
    def mass(self, x0, x1, y0, y1, z0=0.0, skirt=True, solid=True):
        """Rectangular volume; returns a Mass with .front/.back/.left/.right faces."""
        m = Mass(self, x0, x1, y0, y1, z0, solid)
        self.masses.append(m)
        if skirt and z0 < EPS:
            self.ring(m.pts, [(0.0, -SKIRT), (0.0, 0.0)], "base")
        return m

    def faces(self, pts, z0=0.0, skirt=True):
        """One Face per edge of a CCW plan polygon (for cut corners, L shapes ...)."""
        fs = [Face(self, pts[i], pts[(i + 1) % len(pts)], z0) for i in range(len(pts))]
        if skirt and z0 < EPS:
            self.ring(pts, [(0.0, -SKIRT), (0.0, 0.0)], "base")
        return fs

    def face(self, p0, p1, z0=0.0):
        """Free-standing facade frame from plan point p0 to p1 (left -> right as seen from outside)."""
        return Face(self, p0, p1, z0)

    def solid(self, x0, x1, y0, y1, z0, z1):
        """Register an extra collision-hint box (porch slab, dock, podium ...)."""
        self.solids.append((x0, x1, y0, y1, z0, z1))

    # ---- horizontal trims ---------------------------------------------------------------------
    def belt(self, pts, z, h=0.25, proud=0.08, mat="trim", edges=None):
        """String course / belt band around a plan polygon."""
        self.ring(pts, [(0.0, z), (proud, z), (proud, z + h), (0.0, z + h)], mat, edges=edges)

    def cornice(self, pts, z, h=0.6, proud=0.4, mat="trim", edges=None, step=0.5):
        """Projecting cornice with a chamfered underside; top is closed back to the wall."""
        self.ring(pts, [(0.0, z), (proud * step, z), (proud, z + h * 0.5), (proud, z + h), (0.0, z + h)], mat, edges=edges)

    def plinth(self, pts, h=0.5, proud=0.1, mat="base", z=0.0):
        """Base course with a sloped top."""
        self.ring(pts, [(proud, z - SKIRT if z < EPS else z), (proud, z + h - proud), (0.0, z + h)], mat)

    # ---- roofs --------------------------------------------------------------------------------
    def flat_roof(self, pts, z, parapet=0.6, t=0.3, roof="roof", wall="wall", cap="trim", cap_h=0.12, cap_over=0.06, inner=None):
        """Flat roof deck with a parapet (outer face continues the facade) and a coping cap.
        Returns the top height."""
        top = z
        if parapet > 0:
            self.ring(pts, [(0.0, z), (0.0, z + parapet)], wall)
            self.ring(pts, [(-t, z + parapet), (-t, z)], inner or wall)
            if cap:
                self.ring(pts, [(cap_over, z + parapet), (cap_over, z + parapet + cap_h),
                                (-t - cap_over, z + parapet + cap_h), (-t - cap_over, z + parapet)], cap, closed=True)
                top = z + parapet + cap_h
            else:
                self.ring(pts, [(0.0, z + parapet), (-t, z + parapet)], wall)
                top = z + parapet
            deck = offset_poly(pts, -t)
        else:
            deck = pts
        self.poly([(x, y, z) for x, y in deck], roof)
        self.roof_z = max(self.roof_z, z)
        return top

    def slab_roof(self, pts, z, th=0.3, over=0.4, mat="trim", roof="roof"):
        """Modern flat slab with an overhang (no parapet)."""
        o = offset_poly(pts, over)
        self.ring(pts, [(over, z), (over, z + th)], mat)
        self.poly([(x, y, z + th) for x, y in o], roof)
        self.poly_dir([(x, y, z) for x, y in o], (0, 0, -1), mat)
        self.roof_z = max(self.roof_z, z + th)
        return z + th

    def gable_roof(self, x0, x1, y0, y1, z, rise, axis="x", over=0.4, gover=0.3, th=0.2, mat="roof", gable="wall",
                   ends=(True, True)):
        """Pitched roof. axis = direction of the ridge ("x" or "y"). `rise` = ridge height above z.
        ends = which gable walls to close (low end, high end of the ridge axis)."""
        if axis == "x":
            c = (y0 + y1) / 2.0
            half = (y1 - y0) / 2.0
            s = rise / half
            ze = z - over * s
            prof = [(y0 - over, ze), (c, z + rise), (y1 + over, ze), (y1 + over, ze - th), (c, z + rise - th), (y0 - over, ze - th)]
            self.prism(prof, x0 - gover, x1 + gover, "x", mat)
            if gable:
                k = th / s
                if ends[0]:
                    self.poly_dir([(x0, y0 + k, z), (x0, y1 - k, z), (x0, c, z + rise - th)], (-1, 0, 0), gable)
                if ends[1]:
                    self.poly_dir([(x1, y0 + k, z), (x1, y1 - k, z), (x1, c, z + rise - th)], (1, 0, 0), gable)
        else:
            c = (x0 + x1) / 2.0
            half = (x1 - x0) / 2.0
            s = rise / half
            ze = z - over * s
            prof = [(x0 - over, ze), (c, z + rise), (x1 + over, ze), (x1 + over, ze - th), (c, z + rise - th), (x0 - over, ze - th)]
            self.prism(prof, y0 - gover, y1 + gover, "y", mat)
            if gable:
                k = th / s
                if ends[0]:
                    self.poly_dir([(x0 + k, y0, z), (x1 - k, y0, z), (c, y0, z + rise - th)], (0, -1, 0), gable)
                if ends[1]:
                    self.poly_dir([(x0 + k, y1, z), (x1 - k, y1, z), (c, y1, z + rise - th)], (0, 1, 0), gable)
        self.roof_z = max(self.roof_z, z)
        return z + rise

    def hip_roof(self, x0, x1, y0, y1, z, rise, over=0.4, th=0.18, mat="roof", fascia="trim"):
        """Hipped roof (pyramid when the plan is square)."""
        X0, X1, Y0, Y1 = x0 - over, x1 + over, y0 - over, y1 + over
        w = X1 - X0
        d = Y1 - Y0
        half = min(w, d) / 2.0
        s = rise / (min(x1 - x0, y1 - y0) / 2.0)
        ze = z - over * s
        zt = ze + half * s
        A, B, C, D = (X0, Y0, ze), (X1, Y0, ze), (X1, Y1, ze), (X0, Y1, ze)
        if abs(w - d) < 1e-3:
            T = ((X0 + X1) / 2, (Y0 + Y1) / 2, zt)
            for p, q in ((A, B), (B, C), (C, D), (D, A)):
                self.poly((p, q, T), mat)
        elif w > d:
            yc = (Y0 + Y1) / 2
            R0 = (X0 + half, yc, zt)
            R1 = (X1 - half, yc, zt)
            self.poly((A, B, R1, R0), mat)
            self.poly((B, C, R1), mat)
            self.poly((C, D, R0, R1), mat)
            self.poly((D, A, R0), mat)
        else:
            xc = (X0 + X1) / 2
            R0 = (xc, Y0 + half, zt)
            R1 = (xc, Y1 - half, zt)
            self.poly((A, B, R0), mat)
            self.poly((B, C, R1, R0), mat)
            self.poly((C, D, R1), mat)
            self.poly((D, A, R0, R1), mat)
        e = rect_pts(X0, X1, Y0, Y1)
        self.ring(e, [(0.0, ze - th), (0.0, ze)], fascia)
        self.poly_dir([(x, y, ze - th) for x, y in e], (0, 0, -1), fascia)
        self.roof_z = max(self.roof_z, z)
        return zt

    def shed_roof(self, x0, x1, y0, y1, z_low, z_high, high="back", over=0.3, th=0.2, mat="roof", fill="wall"):
        """Mono-pitch roof. high = side of the high eave: "back" (-Y), "front" (+Y), "left" (-X), "right" (+X).
        Also closes the wall wedges between z_low and the roof underside."""
        along_y = high in ("back", "front")
        a0, a1 = (y0, y1) if along_y else (x0, x1)
        b0, b1 = (x0, x1) if along_y else (y0, y1)
        hi_first = high in ("back", "left")
        s = (z_high - z_low) / (a1 - a0)
        if hi_first:
            zA, zB = z_high + over * s, z_low - over * s
        else:
            zA, zB = z_low - over * s, z_high + over * s
        prof = [(a0 - over, zA), (a1 + over, zB), (a1 + over, zB - th), (a0 - over, zA - th)]
        self.prism(prof, b0 - over, b1 + over, "x" if along_y else "y", mat)
        if fill and z_high - th > z_low + EPS:
            zh = z_high - th
            k = (zh - z_low) / s            # run where the underside is above z_low
            if hi_first:
                tri = [(a0, z_low), (a0 + k, z_low), (a0, zh)]
                hi_a = a0
            else:
                tri = [(a1 - k, z_low), (a1, z_low), (a1, zh)]
                hi_a = a1
            for bb, sgn in ((b0, -1), (b1, 1)):
                if along_y:
                    self.poly_dir([(bb, p[0], p[1]) for p in tri], (sgn, 0, 0), fill)
                else:
                    self.poly_dir([(p[0], bb, p[1]) for p in tri], (0, sgn, 0), fill)
            sg = -1 if hi_first else 1
            if along_y:
                self.poly_dir([(b0, hi_a, z_low), (b1, hi_a, z_low), (b1, hi_a, zh), (b0, hi_a, zh)], (0, sg, 0), fill)
            else:
                self.poly_dir([(hi_a, b0, z_low), (hi_a, b1, z_low), (hi_a, b1, zh), (hi_a, b0, zh)], (sg, 0, 0), fill)
        self.roof_z = max(self.roof_z, z_low)
        return z_high

    def sawtooth_roof(self, x0, x1, y0, y1, z, teeth=4, rise=2.2, mat="roof", end="wall", frame="trim", panes=None):
        """Factory north-light roof: teeth along X, vertical glazed faces look toward -X."""
        w = (x1 - x0) / teeth
        for i in range(teeth):
            xa = x0 + i * w
            xb = xa + w
            f = Face(self, (xa, y1), (xa, y0), z)
            n = panes or max(1, int(round(f.w / 3.0)))
            f.rect(0, f.w, 0.0, 0.3, frame)
            f.rect(0, f.w, rise - 0.15, rise, frame)
            pw = f.w / n
            for k in range(n):
                f.rect(k * pw, k * pw + 0.12, 0.3, rise - 0.15, frame)
                f.pane(k * pw + 0.12, (k + 1) * pw, 0.3, rise - 0.15, 0.0)
            self.poly(((xa, y0, z + rise), (xb, y0, z), (xb, y1, z), (xa, y1, z + rise)), mat)
            if end:
                self.poly(((xa, y0, z), (xb, y0, z), (xa, y0, z + rise)), end)
                self.poly(((xb, y1, z), (xa, y1, z), (xa, y1, z + rise)), end)
        self.roof_z = max(self.roof_z, z)
        return z + rise

    def barrel_roof(self, x0, x1, y0, y1, z, rise, seg=8, axis="x", over=0.3, th=0.2, mat="roof", end="wall"):
        """Arched (segmented barrel) roof; axis = direction of the crown line."""
        a0, a1 = (y0, y1) if axis == "x" else (x0, x1)
        b0, b1 = (x0, x1) if axis == "x" else (y0, y1)
        c = (a0 + a1) / 2.0
        half = (a1 - a0) / 2.0
        top = []
        for i in range(seg + 1):
            t = math.pi * (1.0 - i / float(seg))
            top.append((c + half * math.cos(t), z + rise * math.sin(t)))
        prof = top + [(p[0], p[1] - th) for p in reversed(top)]
        self.prism(prof, b0 - over, b1 + over, axis, mat)
        if end:
            inner = [(p[0], p[1] - th) for p in top[1:-1] if p[1] - th > z + 0.01]
            shape = [(a0, z), (a1, z)] + list(reversed(inner))
            for bb, sgn in ((b0, -1), (b1, 1)):
                if axis == "x":
                    self.poly_dir([(bb, p[0], p[1]) for p in shape], (sgn, 0, 0), end)
                else:
                    self.poly_dir([(p[0], bb, p[1]) for p in shape], (0, sgn, 0), end)
        self.roof_z = max(self.roof_z, z)
        return z + rise

    # ---- rooftop / yard props -----------------------------------------------------------------
    def ac_unit(self, x, y, z, w=1.5, d=1.0, h=0.85, mat="Steel", turn=False):
        """Rooftop condenser unit with a fan disc and a louvre panel."""
        if turn:
            w, d = d, w
        self.box(x - w / 2 + 0.1, x - w / 2 + 0.25, y - d / 2, y + d / 2, z, z + 0.1, "metal", "detail", "-z +z")
        self.box(x + w / 2 - 0.25, x + w / 2 - 0.1, y - d / 2, y + d / 2, z, z + 0.1, "metal", "detail", "-z +z")
        self.box(x - w / 2, x + w / 2, y - d / 2, y + d / 2, z + 0.1, z + 0.1 + h, mat, "detail", "-z")
        self.cyl(x, y, z + 0.1 + h, z + 0.16 + h, min(w, d) * 0.36, "metal", "detail", 8)
        self.poly(((x + w / 2 - 0.12, y + d / 2 + 0.02, z + 0.25), (x - w / 2 + 0.12, y + d / 2 + 0.02, z + 0.25),
                   (x - w / 2 + 0.12, y + d / 2 + 0.02, z + h - 0.05), (x + w / 2 - 0.12, y + d / 2 + 0.02, z + h - 0.05)), "metal", "detail")

    def water_tank(self, x, y, z, r=1.2, h=2.0, legs=1.1, mat="Wood", roof="RoofGrey", hoop="metal"):
        """Classic rooftop water tank on a steel stand."""
        k = r * 0.62
        for sx in (-1, 1):
            for sy in (-1, 1):
                self.cyl(x + sx * k, y + sy * k, z, z + legs, 0.07, hoop, "detail", 4, caps="none", phase=math.pi / 4)
        self.cyl(x, y, z + legs, z + legs + 0.1, r + 0.08, hoop, "detail", 10, caps="both")
        self.cyl(x, y, z + legs + 0.1, z + legs + 0.1 + h, r, mat, "detail", 10, caps="none")
        for t in (0.25, 0.75):
            zz = z + legs + 0.1 + h * t
            self.cyl(x, y, zz, zz + 0.08, r + 0.03, hoop, "detail", 10, caps="none")
        self.cyl(x, y, z + legs + 0.1 + h, z + legs + 0.1 + h + r * 0.55, r + 0.12, roof, "detail", 10, r2=0.0, caps="bottom")
        return z + legs + 0.1 + h + r * 0.55

    def antenna(self, x, y, z, h=6.0, mat="Steel", tip="FireRed"):
        """Lattice-style radio mast (tapered square pole with cross arms and a beacon block)."""
        self.cyl(x, y, z, z + h, 0.1, mat, "detail", 4, r2=0.035, caps="none", phase=math.pi / 4)
        for t, l in ((0.55, 0.7), (0.72, 0.5), (0.88, 0.32)):
            zz = z + h * t
            self.box(x - l, x + l, y - 0.025, y + 0.025, zz, zz + 0.05, mat, "detail")
            self.box(x - 0.025, x + 0.025, y - l * 0.7, y + l * 0.7, zz + 0.12, zz + 0.17, mat, "detail")
        self.box(x - 0.07, x + 0.07, y - 0.07, y + 0.07, z + h, z + h + 0.16, tip, "detail", "-z")
        return z + h + 0.16

    def dish(self, x, y, z, r=0.55, mat="White", aim=(0.6, 0.5, 0.7)):
        """Small satellite dish on a post."""
        self.cyl(x, y, z, z + 0.7, 0.05, "metal", "detail", 4, caps="none")
        a = Vector(aim).normalized()
        c = Vector((x, y, z + 0.8))
        self.tube(c, c + a * 0.25, 0.08, r, 8, mat, "detail", "none")
        self.tube(c + a * 0.25, c + a * 0.2, r, 0.0, 8, "metal", "detail", "none")

    def stair_box(self, x0, x1, y0, y1, z, h=2.6, door="front", wall="wall", roof="trim", door_mat="door", over=0.15):
        """Rooftop stair / lift bulkhead with a door."""
        self.box(x0, x1, y0, y1, z, z + h, wall, "body", "-z +z")
        self.box(x0 - over, x1 + over, y0 - over, y1 + over, z + h, z + h + 0.18, roof, "body")
        f = Mass(self, x0, x1, y0, y1, z, False).side(door)
        c = f.w / 2.0
        f.rect(c - 0.5, c + 0.5, 0.0, 2.1, door_mat, 0.03, "detail")
        return z + h + 0.18

    def skylight(self, x0, x1, y0, y1, z, h=0.5, curb=0.2, frame="trim"):
        """Ridge skylight: curb + two glazed slopes (M_Window) + glazed gable ends."""
        self.box(x0, x1, y0, y1, z, z + curb, frame, "body", "-z +z")
        zc = z + curb
        if (x1 - x0) >= (y1 - y0):
            c = (y0 + y1) / 2
            self.poly(((x0, y0, zc), (x1, y0, zc), (x1, c, zc + h), (x0, c, zc + h)), WINDOW_MAT)
            self.poly(((x1, y1, zc), (x0, y1, zc), (x0, c, zc + h), (x1, c, zc + h)), WINDOW_MAT)
            self.poly(((x0, y1, zc), (x0, y0, zc), (x0, c, zc + h)), frame)
            self.poly(((x1, y0, zc), (x1, y1, zc), (x1, c, zc + h)), frame)
        else:
            c = (x0 + x1) / 2
            self.poly(((x0, y1, zc), (x0, y0, zc), (c, y0, zc + h), (c, y1, zc + h)), WINDOW_MAT)
            self.poly(((x1, y0, zc), (x1, y1, zc), (c, y1, zc + h), (c, y0, zc + h)), WINDOW_MAT)
            self.poly(((x0, y0, zc), (x1, y0, zc), (c, y0, zc + h)), frame)
            self.poly(((x1, y1, zc), (x0, y1, zc), (c, y1, zc + h)), frame)

    def chimney(self, x, y, z0, z1, w=0.7, d=0.7, mat="Brick", cap="Concrete", pot="Charcoal"):
        """House chimney: shaft, cap slab and a flue pot."""
        self.box(x - w / 2, x + w / 2, y - d / 2, y + d / 2, z0, z1, mat, "body", "-z +z")
        self.box(x - w / 2 - 0.08, x + w / 2 + 0.08, y - d / 2 - 0.08, y + d / 2 + 0.08, z1, z1 + 0.12, cap, "body")
        self.box(x - w / 4, x + w / 4, y - d / 4, y + d / 4, z1 + 0.12, z1 + 0.4, pot, "body", "-z")
        return z1 + 0.4

    def stack(self, x, y, z0, z1, r0=1.3, r1=0.85, seg=10, mat="Brick", bands=("White", "FireRed"), nb=3, band_h=1.0, lip="Charcoal"):
        """Industrial chimney stack with warning bands near the top."""
        zb = z1 - nb * band_h
        rr = lambda z: r0 + (r1 - r0) * (z - z0) / (z1 - z0)
        self.cyl(x, y, z0, zb, r0, mat, "body", seg, r2=rr(zb), caps="none")
        for i in range(nb):
            za = zb + i * band_h
            self.cyl(x, y, za, za + band_h, rr(za), bands[i % len(bands)], "body", seg, r2=rr(za + band_h), caps="none")
        self.cyl(x, y, z1, z1 + 0.35, r1 + 0.12, lip, "body", seg, caps="both")
        return z1 + 0.35

    def vent(self, x, y, z, r=0.22, h=0.55, mat="Steel"):
        """Mushroom roof vent."""
        self.cyl(x, y, z, z + h, r, mat, "detail", 8, caps="none")
        self.cyl(x, y, z + h, z + h + r * 0.8, r * 1.7, mat, "detail", 8, r2=0.0, caps="bottom")

    def tank_h(self, x0, x1, y, z, r=1.0, mat="White", seg=10, saddle="concrete"):
        """Horizontal storage tank on two saddles (axis along X)."""
        self.tube((x0, y, z + r + 0.4), (x1, y, z + r + 0.4), r, None, seg, mat, "body", "both")
        for xs in (x0 + (x1 - x0) * 0.2, x0 + (x1 - x0) * 0.8):
            self.box(xs - 0.2, xs + 0.2, y - r * 0.8, y + r * 0.8, z, z + 0.7, saddle, "body", "-z")

    def silo(self, x, y, z0, z1, r=1.6, mat="Steel", seg=10, cone=1.0, roof=None):
        """Vertical silo / tank with a conical top."""
        self.cyl(x, y, z0, z1, r, mat, "body", seg, caps="none")
        self.cyl(x, y, z1, z1 + cone, r + 0.05, roof or mat, "body", seg, r2=0.25, caps="top")
        return z1 + cone

    def solar(self, x0, x1, y0, y1, z, tilt=0.5, mat="Navy", frame="Steel"):
        """Tilted solar panel array (high edge toward -Y)."""
        h = (y1 - y0) * tilt
        self.poly_dir([(x0, y1, z + 0.15), (x1, y1, z + 0.15), (x1, y0, z + 0.15 + h), (x0, y0, z + 0.15 + h)], (0, 0, 1), mat, "detail")
        self.poly_dir([(x0, y1, z + 0.1), (x1, y1, z + 0.1), (x1, y0, z + 0.1 + h), (x0, y0, z + 0.1 + h)], (0, 0, -1), frame, "detail")
        for xs in (x0 + 0.15, x1 - 0.15):
            self.box(xs - 0.04, xs + 0.04, y0, y0 + 0.08, z, z + 0.12 + h, frame, "detail", "-z +z")

    def planter(self, x0, x1, y0, y1, z, h=0.5, mat="concrete", plant="Leaf"):
        """Planter box with a block of greenery."""
        self.box(x0, x1, y0, y1, z, z + h, mat, "body", "-z")
        self.box(x0 + 0.12, x1 - 0.12, y0 + 0.12, y1 - 0.12, z + h, z + h + 0.35, plant, "detail", "-z")

    def roof_sign(self, text, xc, y, z, px=0.3, facing="front", color="neon", board="sign", frame="metal", lift=0.8):
        """Free-standing rooftop sign: posts + dark board + block letters facing `facing`."""
        w = text_width(text, px) + px * 2
        h = px * 7
        x0, x1 = xc - w / 2, xc + w / 2
        if facing == "front":
            f = Face(self, (x1, y), (x0, y), z)
        elif facing == "back":
            f = Face(self, (x0, y), (x1, y), z)
        elif facing == "right":      # sign runs along Y, centred on y = xc, standing at x = y
            f = Face(self, (y, x0), (y, x1), z)
        else:
            f = Face(self, (y, x1), (y, x0), z)
        f.box(0.0, w, lift, lift + h, -0.1, 0.0, board, "detail", "")
        for u in (w * 0.15, w * 0.85):
            f.box(u - 0.06, u + 0.06, 0.0, lift, -0.11, -0.01, frame, "detail", "b")
        f.text(text, w / 2, lift + h / 2, px, color, 0.03)
        return z + lift + h

    def roof_lights(self, x0, x1, y0, y1, z, rise, n=5, w=2.0, t0=0.28, t1=0.72, axis="x", frame="trim"):
        """Glazed roof-light panels (M_Window in a trim frame) on both slopes of a gable roof built with
        gable_roof(x0, x1, y0, y1, z, rise, axis). n panels per slope between t0..t1 of the slope."""
        along_x = axis == "x"
        a0, a1 = (y0, y1) if along_x else (x0, x1)
        b0, b1 = (x0, x1) if along_x else (y0, y1)
        c = (a0 + a1) / 2.0
        half = (a1 - a0) / 2.0

        def pt(a, bb, e):
            zz = z + rise * (1.0 - abs(a - c) / half) + e
            return (bb, a, zz) if along_x else (a, bb, zz)

        for i in range(n):
            bc = b0 + (b1 - b0) * (i + 0.5) / n
            for sg in (-1.0, 1.0):
                for (e, g, m) in ((0.04, 0.12, frame), (0.08, 0.0, WINDOW_MAT)):
                    aa = c + sg * half * t0 - sg * g
                    ab = c + sg * half * t1 + sg * g
                    ba, bb = bc - w / 2.0 - g, bc + w / 2.0 + g
                    self.poly_dir([pt(aa, ba, e), pt(aa, bb, e), pt(ab, bb, e), pt(ab, ba, e)], (0, 0, 1), m)

    def seam(self, p0, p1, w=0.1, h=0.07, mat="trim", part="body", ends=True):
        """Raised strip lying ON a (sloped) surface from 3D point p0 to p1: standing seams on metal roofs,
        ridge caps, kerbs, expansion joints. Open underneath (the surface it lies on closes it)."""
        p0 = Vector(p0)
        p1 = Vector(p1)
        d = p1 - p0
        if d.length < EPS:
            return
        s = UP.cross(d)
        if s.length < EPS:
            return
        s = s.normalized() * (w / 2.0)
        u = UP * h
        a, c, e, g = p0 - s, p0 + s, p1 + s, p1 - s
        self.poly_dir([a + u, c + u, e + u, g + u], UP, mat, part)
        self.poly_dir([a, g, g + u, a + u], -s, mat, part)
        self.poly_dir([c, e, e + u, c + u], s, mat, part)
        if ends:
            self.poly_dir([a, c, c + u, a + u], -d, mat, part)
            self.poly_dir([g, e, e + u, g + u], d, mat, part)

    def seams(self, x0, x1, y0, y1, zfn, n=6, along="y", inset=0.0, **kw):
        """n evenly spaced seam() strips over a rectangular roof area; zfn(x, y) = roof surface height.
        along = direction the strips run ("y" or "x")."""
        for i in range(n):
            t = (i + 0.5) / n
            if along == "y":
                x = x0 + (x1 - x0) * t
                self.seam((x, y0 + inset, zfn(x, y0 + inset)), (x, y1 - inset, zfn(x, y1 - inset)), **kw)
            else:
                y = y0 + (y1 - y0) * t
                self.seam((x0 + inset, y, zfn(x0 + inset, y)), (x1 - inset, y, zfn(x1 - inset, y)), **kw)

    def deck(self, x0, x1, y0, y1, z, th=0.3, top="roof", mat="concrete", skip=""):
        """Closed structural slab (parking deck, mezzanine, walkway): top surface at z in `top`
        material, edges + underside in `mat`. skip = world faces to omit ("-y +x" ...)."""
        self.box(x0, x1, y0, y1, z - th, z, mat, "body", (skip + " +z").strip())
        self.poly(((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)), top)

    def ramp(self, a0, a1, za, zb, b0, b1, axis="x", top="roof", mat="concrete", ease=2.0):
        """Solid drivable ramp wedge. Runs along `axis` from a0 (height za) to a1 (height zb); b0..b1 is
        its width on the other axis. The first / last `ease` metres use half the slope so cars do
        not bottom out on the kinks. No bottom face: stand it on a deck or on the ground."""
        sg = 1.0 if a1 > a0 else -1.0
        ease = min(ease, abs(a1 - a0) / 4.0)
        s = (zb - za) / (abs(a1 - a0) - ease)
        pr = [(a0, za), (a0 + sg * ease, za + s * ease / 2.0), (a1 - sg * ease, zb - s * ease / 2.0), (a1, zb)]
        if axis == "x":
            P = lambda a, bb, zz: (a, bb, zz)
            A = lambda v: (v, 0.0, 0.0)
            B = lambda v: (0.0, v, 0.0)
        else:
            P = lambda a, bb, zz: (bb, a, zz)
            A = lambda v: (0.0, v, 0.0)
            B = lambda v: (v, 0.0, 0.0)
        for (p, q) in zip(pr[:-1], pr[1:]):
            self.poly_dir([P(p[0], b0, p[1]), P(q[0], b0, q[1]), P(q[0], b1, q[1]), P(p[0], b1, p[1])], (0, 0, 1), top)
        self.poly_dir([P(a1, b0, za), P(a1, b1, za), P(a1, b1, zb), P(a1, b0, zb)], A(sg), mat)
        side = pr + [(a1, za)]
        self.poly_dir([P(a, b0, zz) for a, zz in side], B(-1.0), mat)
        self.poly_dir([P(a, b1, zz) for a, zz in side], B(1.0), mat)
        return s

    def lamp_post(self, x, y, z, h=4.2, arm=0.9, mat="metal", lamp="LampWarm", axis="x"):
        """Twin-arm area light (roof decks, yards): pole, cross arm, two emissive lamp heads."""
        self.cyl(x, y, z, z + h, 0.09, mat, "detail", 6, caps="none")
        dx, dy = (arm, 0.12) if axis == "x" else (0.12, arm)
        self.box(x - dx, x + dx, y - dy, y + dy, z + h, z + h + 0.12, mat, "detail")
        for sg in (-1.0, 1.0):
            cx = x + (sg * arm if axis == "x" else 0.0)
            cy = y + (sg * arm if axis != "x" else 0.0)
            ex, ey = (0.3, 0.16) if axis == "x" else (0.16, 0.3)
            self.box(cx - ex, cx + ex, cy - ey, cy + ey, z + h - 0.1, z + h, lamp, "detail", "+z")
        return z + h + 0.12

    # ---- finish -------------------------------------------------------------------------------
    def finish(self, category="misc", tags=(), collision="box", landmark="", extra=None):
        """Create the mesh objects, store manifest metadata on the root, return the root object."""
        objs = []
        for key, suffix in PARTS:
            p = self.parts[key]
            if len(p.bm.faces) == 0:
                p.bm.free()
                continue
            ob = G.new_object("%s_%s" % (self.name, suffix), p.bm, parent=self.root, materials=p.mats,
                              uv=(p.uv is None), recalc=False)
            objs.append(ob)
        boxes = [m.box_hint() for m in self.masses if m.is_solid and m.top > m.z0 + EPS]
        boxes += [list(s) for s in self.solids]
        meta = {
            "id": self.name, "category": category, "tags": list(tags), "collision": collision, "landmark": landmark,
            "entrance": list(self.entrance) if self.entrance else None,
            "roof_z": round(self.roof_z, 3), "floors": self.floors, "window_cells": self.cells,
            "boxes": [[round(c, 3) for c in bx] for bx in boxes],
        }
        if extra:
            meta.update(extra)
        self.root["gta_building"] = json.dumps(meta)
        self.meta = meta
        return self.root


# ------------------------------------------------------------------------------------------------
# Mass
# ------------------------------------------------------------------------------------------------
class Mass(object):
    """Rectangular volume. Faces: front (+Y), back (-Y), left (-X), right (+X)."""

    def __init__(self, b, x0, x1, y0, y1, z0=0.0, solid=True):
        self.b = b
        self.x0, self.x1, self.y0, self.y1, self.z0 = x0, x1, y0, y1, z0
        self.pts = rect_pts(x0, x1, y0, y1)
        self.back = Face(b, self.pts[0], self.pts[1], z0)
        self.right = Face(b, self.pts[1], self.pts[2], z0)
        self.front = Face(b, self.pts[2], self.pts[3], z0)
        self.left = Face(b, self.pts[3], self.pts[0], z0)
        self.all = [self.front, self.right, self.back, self.left]
        self.is_solid = solid
        self.h = None             # set to override the height used for the collision-hint box

    def side(self, name):
        return getattr(self, name)

    @property
    def top(self):
        return self.z0 + (self.h if self.h is not None else max(f.top for f in self.all))

    def stack(self, v0, levels, mat="wall", faces=None):
        """Same levels on several faces (default all four). Returns the top height (world z)."""
        v = v0
        for f in (faces or self.all):
            v = f.stack(v0, levels, mat)
        return self.z0 + v

    def box_hint(self):
        return [self.x0, self.x1, self.y0, self.y1, self.z0, self.top]


# ------------------------------------------------------------------------------------------------
# Face
# ------------------------------------------------------------------------------------------------
class Face(object):
    """Facade frame: u = right (seen from outside), v = up, d = outward."""

    def __init__(self, b, p0, p1, z0=0.0):
        self.b = b
        a = Vector((p0[0], p0[1], 0.0))
        c = Vector((p1[0], p1[1], 0.0))
        self.w = (c - a).length
        self.U = (c - a).normalized()
        self.N = Vector((self.U.y, -self.U.x, 0.0))
        self.o = Vector((a.x, a.y, z0))
        self.z0 = z0
        self.m0 = 0.0          # left / right margins that row() keeps free of bays (corner piers)
        self.m1 = 0.0
        self.module = MODULE
        self.top = 0.0

    # -- frame ------------------------------------------------------------------------------------
    def P(self, u, v, d=0.0):
        return self.o + self.U * u + UP * v + self.N * d

    def plan(self, u, d=0.0):
        p = self.o + self.U * u + self.N * d
        return (p.x, p.y)

    @property
    def nb(self):
        """Number of MODULE-wide bays that fit between the margins."""
        return max(1, int(round((self.w - self.m0 - self.m1) / self.module)))

    def n(self, module):
        return max(1, int(round((self.w - self.m0 - self.m1) / module)))

    def margins(self, m0, m1=None):
        self.m0 = m0
        self.m1 = m0 if m1 is None else m1
        return self

    def sub(self, u0, u1, d=0.0, v=0.0):
        """Coplanar sub-face (offset outward by d, raised by v)."""
        a = self.o + self.U * u0 + self.N * d
        c = self.o + self.U * u1 + self.N * d
        return Face(self.b, (a.x, a.y), (c.x, c.y), self.z0 + v)

    def side_face(self, u, d0, d1, toward="+u"):
        """Perpendicular face at u spanning d0..d1, looking toward +u or -u (blade signs, fins)."""
        a = self.o + self.U * u + self.N * d0
        c = self.o + self.U * u + self.N * d1
        if toward == "+u":
            return Face(self.b, (c.x, c.y), (a.x, a.y), self.z0)
        return Face(self.b, (a.x, a.y), (c.x, c.y), self.z0)

    # -- primitives -------------------------------------------------------------------------------
    def rect(self, u0, u1, v0, v1, mat="wall", d=0.0, part="body"):
        if u1 - u0 < EPS or v1 - v0 < EPS:
            return None
        P = self.P
        return self.b.poly((P(u0, v0, d), P(u1, v0, d), P(u1, v1, d), P(u0, v1, d)), mat, part)

    def pane(self, u0, u1, v0, v1, d=-0.18, nx=1, ny=1, mat=WINDOW_MAT):
        """Glass (one lit-window UV cell per pane)."""
        du = (u1 - u0) / nx
        dv = (v1 - v0) / ny
        for i in range(nx):
            for j in range(ny):
                self.rect(u0 + i * du, u0 + (i + 1) * du, v0 + j * dv, v0 + (j + 1) * dv, mat, d)

    def box(self, u0, u1, v0, v1, d0, d1, mat="trim", part="body", skip="k"):
        """Box in face space. skip letters: l r (left/right) b t (bottom/top) k (back) f (front)."""
        sk = set(_FACE_SKIP[c] for c in skip if c in _FACE_SKIP)
        self.b._box(self.P, u0, u1, v0, v1, d0, d1, mat, part, sk)

    def prism(self, profile, u0, u1, mat="trim", part="body", caps=True, closed=True):
        """Extrude a section profile [(d, v)] along the facade from u0 to u1."""
        pts = [self.P(u0, v, d) for d, v in profile]
        self.b.extrude(pts, self.U * (u1 - u0), mat, part, caps, closed)

    # -- walls ------------------------------------------------------------------------------------
    def wall(self, u0, u1, v0, v1, mat="wall", openings=(), d=0.0, part="body"):
        """Flat wall rectangle with rectangular openings (Op). Builds the wall as quads around the
        openings plus the reveal quads; no hidden faces."""
        ops = sorted(openings, key=lambda o: o.a0)

        def R(a, c, e, g):
            self.rect(a, c, e, g, mat, d, part)

        if not ops:
            R(u0, u1, v0, v1)
            return
        same = len(ops) >= 2 and all(abs(o.b0 - ops[0].b0) < EPS and abs(o.b1 - ops[0].b1) < EPS for o in ops)
        if same:
            b0, b1 = ops[0].b0, ops[0].b1
            R(u0, u1, v0, b0)
            R(u0, u1, b1, v1)
            cur = u0
            for o in ops:
                R(cur, o.a0, b0, b1)
                cur = o.a1
            R(cur, u1, b0, b1)
        else:
            cur = u0
            for o in ops:
                R(cur, o.a0, v0, v1)
                R(o.a0, o.a1, v0, o.b0)
                R(o.a0, o.a1, o.b1, v1)
                cur = o.a1
            R(cur, u1, v0, v1)
        uniform = same and len(ops) >= 3 and all(
            o.proud == 0 and abs(o.rec - ops[0].rec) < EPS and o.rmat == ops[0].rmat for o in ops)
        P = self.P
        poly = self.b.poly
        for o in ops:
            rm = o.rmat or mat
            r = d - o.rec
            p = d + o.proud
            if p - r < EPS:                 # Op(rec=0): a plain hole without reveals (inner side of a doorway)
                continue
            poly((P(o.a0, o.b0, p), P(o.a0, o.b0, r), P(o.a0, o.b1, r), P(o.a0, o.b1, p)), rm, part)
            poly((P(o.a1, o.b0, r), P(o.a1, o.b0, p), P(o.a1, o.b1, p), P(o.a1, o.b1, r)), rm, part)
            if not uniform:
                poly((P(o.a0, o.b0, p), P(o.a1, o.b0, p), P(o.a1, o.b0, r), P(o.a0, o.b0, r)), rm, part)
                poly((P(o.a0, o.b1, r), P(o.a1, o.b1, r), P(o.a1, o.b1, p), P(o.a0, o.b1, p)), rm, part)
        if uniform and ops[0].rec > EPS:
            o = ops[0]
            rm = o.rmat or mat
            r = d - o.rec
            a0, a1 = ops[0].a0, ops[-1].a1
            poly((P(a0, o.b0, d), P(a1, o.b0, d), P(a1, o.b0, r), P(a0, o.b0, r)), rm, part)
            poly((P(a0, o.b1, r), P(a1, o.b1, r), P(a1, o.b1, d), P(a0, o.b1, d)), rm, part)

    def corrugated(self, u0, u1, v0, v1, mat="wall", pitch=1.0, depth=0.12, openings=(), d=0.0, part="body"):
        """Wall with vertical zig-zag ribs (metal cladding). Openings are cut out cleanly; give them a
        trim with frame()."""
        n = max(1, int(round((u1 - u0) / pitch)))
        p = (u1 - u0) / n

        def dep(u):
            t = ((u - u0) / p) % 1.0
            return d + depth * (1.0 - abs(2.0 * t - 1.0))

        cuts = set(round(u0 + k * p / 2.0, 5) for k in range(2 * n + 1))
        for o in openings:
            for e in (o.a0, o.a1):
                if u0 < e < u1:
                    cuts.add(round(e, 5))
        cuts = sorted(cuts)
        P = self.P
        for ua, ub in zip(cuts[:-1], cuts[1:]):
            if ub - ua < EPS:
                continue
            mid = (ua + ub) / 2.0
            spans = [(v0, v1)]
            for o in openings:
                if o.a0 - EPS < mid < o.a1 + EPS:
                    nxt = []
                    for (a, c) in spans:
                        if o.b0 > a + EPS:
                            nxt.append((a, min(c, o.b0)))
                        if o.b1 < c - EPS:
                            nxt.append((max(a, o.b1), c))
                    spans = nxt
            da = dep(ua)
            db = dep(ub)
            for (a, c) in spans:
                if c - a < EPS:
                    continue
                self.b.poly((P(ua, a, da), P(ub, a, db), P(ub, c, db), P(ua, c, da)), mat, part)

    def zigzag_h(self, u0, u1, v0, v1, d=0.0, pitch=0.3, depth=0.05, mat="Steel", part="body"):
        """Horizontal ribs (roll-up door slats, louvres, siding)."""
        n = max(1, int(round((v1 - v0) / pitch)))
        p = (v1 - v0) / n
        P = self.P
        for i in range(n):
            a = v0 + i * p
            m = a + p * 0.5
            c = a + p
            self.b.poly((P(u0, a, d), P(u1, a, d), P(u1, m, d + depth), P(u0, m, d + depth)), mat, part)
            self.b.poly((P(u0, m, d + depth), P(u1, m, d + depth), P(u1, c, d), P(u0, c, d)), mat, part)

    def frame(self, a0, a1, b0, b1, w=0.15, proud=0.15, back=-0.2, mat="trim", bottom=False, part="body"):
        """Chunky trim frame around an opening (covers the reveal from `back` to `proud`)."""
        lo = b0 - w if bottom else b0
        self.box(a0 - w, a0, lo, b1 + w, back, proud, mat, part, "k" if bottom else "k b")
        self.box(a1, a1 + w, lo, b1 + w, back, proud, mat, part, "k" if bottom else "k b")
        self.box(a0, a1, b1, b1 + w, back, proud, mat, part, "k l r")
        if bottom:
            self.box(a0, a1, b0 - w, b0, back, proud, mat, part, "k l r")

    # -- bays -------------------------------------------------------------------------------------
    def _ops(self, s, a, c, v0, h):
        k = s["k"]
        bw = c - a
        mid = (a + c) / 2.0 + s.get("off", 0.0)
        if k in ("win", "louvre"):
            cnt = s.get("count", 1)
            gap = s.get("gap", 0.3)
            w = s["w"]
            tot = cnt * w + (cnt - 1) * gap
            if tot > bw - 0.3:
                w = (bw - 0.3 - (cnt - 1) * gap) / cnt
                tot = cnt * w + (cnt - 1) * gap
            b0 = v0 + s["sill"]
            b1 = min(b0 + s["h"], v0 + h - 0.1)
            fm = s.get("frame")
            out = []
            for i in range(cnt):
                a0 = mid - tot / 2.0 + i * (w + gap)
                out.append(Op(a0, a0 + w, b0, b1, s.get("recess", 0.18), fm or s.get("reveal"),
                              s.get("proud", 0.05) if fm else 0.0))
            return out
        if k == "door":
            w = min(s["w"], bw - 0.2)
            cx = a + bw * s.get("align", 0.5)
            b1 = min(v0 + s["h"] + s.get("transom", 0.0), v0 + h - 0.05)
            fm = s.get("frame")
            return [Op(cx - w / 2.0, cx + w / 2.0, v0, b1, s.get("recess", 0.3), fm or s.get("reveal"),
                       s.get("proud", 0.05) if fm else 0.0)]
        if k == "shop":
            mg = s.get("margin", 0.3)
            b1 = v0 + min(s.get("head", 3.0), h - 0.3)
            return [Op(a + mg, c - mg, v0, b1, s.get("recess", 0.25), s.get("frame", "trim"), 0.0)]
        if k == "rollup":
            w = min(s["w"], bw - 0.3)
            b0 = v0 + s.get("sill", 0.0)
            b1 = min(b0 + s["h"], v0 + h - 0.15)
            return [Op(mid - w / 2.0, mid + w / 2.0, b0, b1, s.get("recess", 0.2), s.get("frame"), 0.0)]
        raise ValueError("unknown bay kind %r" % k)

    def row(self, v0, h, bays, mat="wall", widths=None, u0=None, u1=None, corr=None):
        """One storey: wall from v0 to v0 + h across the whole face, with `bays` (list of bay specs /
        None) spread between the margins. widths = optional relative bay widths.
        corr = dict(pitch, depth) for corrugated cladding. Returns the bay spans [(u0, u1)]."""
        ua = self.m0 if u0 is None else u0
        ub = self.w - self.m1 if u1 is None else u1
        n = len(bays)
        widths = widths or [1.0] * n
        tot = float(sum(widths))
        spans = []
        cur = ua
        for wg in widths:
            bw = (ub - ua) * wg / tot
            spans.append((cur, cur + bw))
            cur += bw
        ops = []
        fills = []
        for s, (a, c) in zip(bays, spans):
            if not s:
                continue
            for o in self._ops(s, a, c, v0, h):
                ops.append(o)
                fills.append((s, o, a, c))
        if corr:
            fw = 0.14
            cut = [Op(o.a0 - fw, o.a1 + fw, o.b0 - (fw if o.b0 > v0 + EPS else 0.0), o.b1 + fw) for o in ops]
            self.corrugated(0.0, self.w, v0, v0 + h, mat, openings=cut, **corr)
            for o in ops:
                self.frame(o.a0, o.a1, o.b0, o.b1, fw, corr.get("depth", 0.12) + 0.04, -o.rec, o.rmat or "trim",
                           bottom=o.b0 > v0 + EPS)
        else:
            self.wall(0.0, self.w, v0, v0 + h, mat, ops)
        for s, o, a, c in fills:
            self._fill(s, o, a, c)
        self.top = max(self.top, v0 + h)
        return spans

    def stack(self, v0, levels, mat="wall"):
        """Several storeys. levels = [(height, bays[, mat[, row kwargs]])]; bays may be a list, a single
        spec (repeated self.nb times), a callable(face) -> list, or None (blank wall). Returns top v."""
        v = v0
        for lv in levels:
            h = lv[0]
            bays = lv[1] if len(lv) > 1 else None
            m = lv[2] if len(lv) > 2 and lv[2] else mat
            kw = lv[3] if len(lv) > 3 else {}
            if callable(bays):
                bays = bays(self)
            if isinstance(bays, dict):
                bays = [bays] * self.nb
            if not bays:
                if kw.get("corr"):
                    self.corrugated(0.0, self.w, v, v + h, m, **kw["corr"])
                else:
                    self.rect(0.0, self.w, v, v + h, m)
                self.top = max(self.top, v + h)
            else:
                self.row(v, h, bays, m, **kw)
            v += h
        return v

    def _fill(self, s, o, a, c):
        k = s["k"]
        if k == "win":
            self._fill_win(s, o)
        elif k == "door":
            self._fill_door(s, o)
        elif k == "shop":
            self._fill_shop(s, o)
        elif k == "rollup":
            self._fill_rollup(s, o)
        elif k == "louvre":
            self.zigzag_h(o.a0, o.a1, o.b0, o.b1, -o.rec, 0.16, 0.08, s.get("mat", "metal"))

    def _fill_win(self, s, o):
        a0, a1, b0, b1 = o.a0, o.a1, o.b0, o.b1
        r = -o.rec
        nx, ny = s.get("panes", (1, 1))
        self.pane(a0, a1, b0, b1, r, nx, ny)
        fm = s.get("frame")
        bars = s.get("bars")
        if bars:
            bm_ = s.get("bar_mat", fm or "trim")
            bw = 0.07
            for i in range(1, bars[0]):            # muntins: front quads only (4 cm proud of the glass)
                u = a0 + (a1 - a0) * i / bars[0]
                self.rect(u - bw / 2, u + bw / 2, b0, b1, bm_, r + 0.04)
            for j in range(1, bars[1]):
                v = b0 + (b1 - b0) * j / bars[1]
                self.rect(a0, a1, v - bw / 2, v + bw / 2, bm_, r + 0.045)
        fw = s.get("frame_w", 0.1)
        fp = o.proud
        sb = s.get("sill_bar")
        if fm:
            # thin frames (<= 6 cm proud) are front quads only; chunkier ones get their outer sides too
            thin = fp <= 0.06 and not s.get("frame_sides")
            self.box(a0 - fw, a1 + fw, b1, b1 + fw, 0.0, fp, fm, "body", "k b t l r" if thin else "k b")
            self.box(a0 - fw, a0, b0, b1, 0.0, fp, fm, "body", "k t b r l" if thin else "k t b r")
            self.box(a1, a1 + fw, b0, b1, 0.0, fp, fm, "body", "k t b l r" if thin else "k t b l")
            if not sb:
                self.box(a0 - fw, a1 + fw, b0 - fw, b0, 0.0, fp, fm, "body", "k t b l r" if thin else "k t")
        else:
            fw = 0.0
        if sb:
            self.box(a0 - fw - 0.06, a1 + fw + 0.06, b0 - 0.12, b0 - 0.01, 0.0, fp + 0.09, sb, "body", "k")
        lt = s.get("lintel")
        if lt:
            self.box(a0 - fw - 0.1, a1 + fw + 0.1, b1 + fw, b1 + fw + 0.18, 0.0, 0.07, lt, "body", "k")
        sh = s.get("shutters")
        if sh:
            sw = s.get("shutter_w", 0.42)
            self.box(a0 - fw - sw, a0 - fw - 0.02, b0, b1, 0.0, 0.05, sh, "body", "k")
            self.box(a1 + fw + 0.02, a1 + fw + sw, b0, b1, 0.0, 0.05, sh, "body", "k")
        if s.get("planter"):
            self.box(a0, a1, b0 - 0.38, b0 - 0.13, 0.0, 0.26, s.get("planter_mat", "WoodDark"), "detail", "k")
            self.box(a0 + 0.05, a1 - 0.05, b0 - 0.13, b0 + 0.08, 0.04, 0.22, s.get("plant", "Leaf"), "detail", "k b")
        aw = s.get("awning")
        if aw:
            mats = aw if isinstance(aw, (tuple, list)) else (aw,)
            self.awning(a0 - 0.12, a1 + 0.12, b1 + 0.4, depth=0.7, drop=0.38, valance=0.12, mats=mats,
                        stripes=0 if len(mats) == 1 else 4)
        bal = s.get("balcony")
        if bal:
            bw_ = bal.get("w", (a1 - a0) + 1.0)
            cx = (a0 + a1) / 2.0
            self.balcony(cx - bw_ / 2, cx + bw_ / 2, b0 - bal.get("drop", 0.05), bal.get("depth", 1.0), bal.get("h", 1.0),
                         bal.get("style", "solid"), bal.get("mat", "trim"), bal.get("slab", "concrete"), bal.get("rail", "metal"))

    def _fill_door(self, s, o):
        a0, a1, b0, b1 = o.a0, o.a1, o.b0, o.b1
        r = -o.rec
        dm = s.get("mat", "door")
        top = min(b0 + s["h"], b1)
        self.rect(a0, a1, b0, top, dm, r)
        g = s.get("glass", 0.0)
        m = 0.13
        if g > 0:
            gb = max(b0 + 0.25, top - m - (top - b0 - 2 * m) * g)
            if s.get("double"):
                cx = (a0 + a1) / 2
                self.pane(a0 + m, cx - m / 2, gb, top - m, r + 0.02)
                self.pane(cx + m / 2, a1 - m, gb, top - m, r + 0.02)
            else:
                self.pane(a0 + m, a1 - m, gb, top - m, r + 0.02)
        elif s.get("double"):
            cx = (a0 + a1) / 2
            self.box(cx - 0.02, cx + 0.02, b0, top, r, r + 0.03, s.get("frame") or "metal", "body", "k t b")
        if b1 - top > 0.1:
            self.box(a0, a1, top, top + 0.08, r, r + 0.07, s.get("frame") or "trim", "body", "k l r")
            self.pane(a0, a1, top + 0.08, b1, r)
        if s.get("handle", True):
            hx = (a0 + a1) / 2 - 0.12 if s.get("double") else a1 - 0.22
            self.box(hx, hx + 0.06, b0 + 0.95, b0 + 1.2, r, r + 0.07, "metal", "detail", "k")
        fm = s.get("frame")
        if fm:
            fw = s.get("frame_w", 0.1)
            fp = o.proud
            self.box(a0 - fw, a1 + fw, b1, b1 + fw, 0.0, fp, fm, "body", "k b")
            self.box(a0 - fw, a0, b0, b1, 0.0, fp, fm, "body", "k t b r")
            self.box(a1, a1 + fw, b0, b1, 0.0, fp, fm, "body", "k t b l")
        cn = s.get("canopy")
        if cn:
            ex = cn.get("extra", 0.4)
            self.canopy(a0 - ex, a1 + ex, b1 + cn.get("lift", 0.25), cn.get("depth", 1.0), cn.get("th", 0.14), cn.get("mat", "trim"),
                        part=cn.get("part", "detail"))

    def _fill_shop(self, s, o):
        a0, a1, b0, b1 = o.a0, o.a1, o.b0, o.b1
        r = -o.rec
        fm = s.get("frame", "trim")
        rm = s.get("riser_mat", "base")
        riser = s.get("riser", 0.5)
        dpos = s.get("door", "center")
        dw = min(s.get("door_w", 1.1), (a1 - a0) - 0.4)
        if dpos == "left":
            d0 = a0 + 0.08
        elif dpos == "right":
            d0 = a1 - 0.08 - dw
        elif dpos == "center":
            d0 = (a0 + a1) / 2 - dw / 2
        else:
            d0 = None
        spans = []
        if d0 is None:
            spans.append((a0, a1))
        else:
            if d0 - a0 > 0.3:
                spans.append((a0, d0))
            if a1 - (d0 + dw) > 0.3:
                spans.append((d0 + dw, a1))
        for (g0, g1) in spans:
            sk = "k b" + (" l" if g0 - a0 < EPS else "") + (" r" if a1 - g1 < EPS else "")
            self.box(g0, g1, b0, b0 + riser, r, r + 0.13, rm, "body", sk)
            n = max(1, int(round((g1 - g0) / s.get("pane", 1.8))))
            pw = (g1 - g0) / n
            for i in range(n):
                self.pane(g0 + i * pw, g0 + (i + 1) * pw, b0 + riser, b1, r)
            for i in range(1, n):
                u = g0 + i * pw
                self.box(u - 0.04, u + 0.04, b0 + riser, b1, r, r + 0.07, fm, "body", "k t b")
        if d0 is not None:
            dh = min(2.25, b1 - b0 - 0.05)
            dm = s.get("door_mat", "door")
            self.rect(d0, d0 + dw, b0, b0 + 0.28, dm, r)
            self.pane(d0, d0 + dw, b0 + 0.28, b0 + dh, r)
            self.box(d0 - 0.04, d0 + 0.04, b0, b1, r, r + 0.08, fm, "body", "k t b")
            self.box(d0 + dw - 0.04, d0 + dw + 0.04, b0, b1, r, r + 0.08, fm, "body", "k t b")
            if b1 - (b0 + dh) > 0.2:
                self.box(d0, d0 + dw, b0 + dh, b0 + dh + 0.08, r, r + 0.08, fm, "body", "k l r")
                self.pane(d0, d0 + dw, b0 + dh + 0.08, b1, r)
            self.box(d0 + dw - 0.2, d0 + dw - 0.14, b0 + 0.9, b0 + 1.3, r, r + 0.09, "metal", "detail", "k")

    def _fill_rollup(self, s, o):
        a0, a1, b0, b1 = o.a0, o.a1, o.b0, o.b1
        r = -o.rec
        m = s.get("mat", "Steel")
        top = b1
        if s.get("lights"):
            top = b1 - 0.55
            n = max(2, int(round((a1 - a0) / 0.9)))
            pw = (a1 - a0) / n
            self.rect(a0, a1, top, b1, m, r + 0.02)
            for i in range(n):
                self.pane(a0 + i * pw + 0.12, a0 + (i + 1) * pw - 0.12, top + 0.12, b1 - 0.12, r + 0.04)
        self.box(a0, a1, b0, b0 + 0.14, r, r + 0.05, s.get("bar", "metal"), "body", "k b l r")
        self.zigzag_h(a0, a1, b0 + 0.14, top, r, s.get("slat", 0.3), 0.05, m)

    # -- vertical elements ------------------------------------------------------------------------
    def pilaster(self, u, v0, v1, w=0.5, proud=0.18, mat="trim", cap=True):
        """Pilaster / pier centred on u (front + sides + top)."""
        self.box(u - w / 2, u + w / 2, v0, v1, 0.0, proud, mat, "body", "k b")
        if cap:
            self.box(u - w / 2 - 0.06, u + w / 2 + 0.06, v1 - 0.22, v1, 0.0, proud + 0.06, mat, "body", "k")

    def pilasters(self, v0, v1, n=None, w=0.5, proud=0.18, mat="trim", cap=False, ends=True):
        """Pilasters on the bay lines (n bays, default self.nb); ends=True adds one at each corner."""
        n = n or self.nb
        ua = self.m0
        ub = self.w - self.m1
        us = [ua + (ub - ua) * i / n for i in range(1, n)]
        if ends:
            us = [w / 2.0] + us + [self.w - w / 2.0]
        for u in us:
            self.pilaster(u, v0, v1, w, proud, mat, cap)
        return us

    def fin(self, u, v0, v1, w=0.12, proud=0.3, mat="trim"):
        """Thin vertical fin / mullion."""
        self.box(u - w / 2, u + w / 2, v0, v1, 0.0, proud, mat, "body", "k b")

    def band(self, v, h=0.25, proud=0.08, mat="trim", u0=0.0, u1=None):
        """Horizontal band on this face only (use Builder.belt for a full ring)."""
        self.box(u0, self.w if u1 is None else u1, v, v + h, 0.0, proud, mat, "body", "k")

    def curtain(self, v0, floors, floor_h=FLOOR_H, bay=2.0, spandrel=0.9, spandrel_mat="accent", mull="trim",
                mull_w=0.1, mull_proud=0.14, rec=0.06, u0=None, u1=None, hbar=True):
        """Curtain wall: per floor an opaque spandrel band + one glass pane per bay, with full-height
        mullion fins. Cheap enough for 20-storey towers."""
        ua = self.m0 if u0 is None else u0
        ub = self.w - self.m1 if u1 is None else u1
        n = max(1, int(round((ub - ua) / bay)))
        pw = (ub - ua) / n
        P = self.P
        for f in range(floors):
            a = v0 + f * floor_h
            self.rect(ua, ub, a, a + spandrel, spandrel_mat)
            self.b.poly((P(ua, a + spandrel, 0.0), P(ub, a + spandrel, 0.0), P(ub, a + spandrel, -rec), P(ua, a + spandrel, -rec)), spandrel_mat)
            self.b.poly((P(ua, a + floor_h, -rec), P(ub, a + floor_h, -rec), P(ub, a + floor_h, 0.0), P(ua, a + floor_h, 0.0)), spandrel_mat)
            for i in range(n):
                self.rect(ua + i * pw, ua + (i + 1) * pw, a + spandrel, a + floor_h, WINDOW_MAT, -rec)
            if hbar:
                self.box(ua, ub, a + spandrel - 0.06, a + spandrel + 0.06, 0.0, mull_proud * 0.6, mull, "body", "k l r")
        top = v0 + floors * floor_h
        for i in range(n + 1):
            u = ua + i * pw
            self.box(u - mull_w / 2, u + mull_w / 2, v0, top, -rec, mull_proud, mull, "body", "k b")
        if ua > EPS:
            self.rect(0.0, ua, v0, top, "wall")
        if self.w - ub > EPS:
            self.rect(ub, self.w, v0, top, "wall")
        self.top = max(self.top, top)
        return top

    # -- attachments ------------------------------------------------------------------------------
    def awning(self, u0, u1, v, depth=1.2, drop=0.5, valance=0.22, mats=("awning", "awning2"), stripes=0, th=0.1,
               part="detail", d0=0.0):
        """Fabric awning (sloped top + valance). stripes = number of alternating colour segments."""
        n = max(1, stripes)
        du = (u1 - u0) / n
        P = self.P
        A = (d0, v)
        B = (d0 + depth, v - drop)
        C = (d0 + depth, v - drop - valance)
        D = (d0, v - th)
        for i in range(n):
            m = mats[i % len(mats)] if stripes else mats[0]
            a = u0 + i * du
            c = a + du
            self.b.poly((P(a, B[1], B[0]), P(c, B[1], B[0]), P(c, A[1], A[0]), P(a, A[1], A[0])), m, part)
            self.rect(a, c, C[1], B[1], m, C[0], part)
        self.b.poly_dir([P(u0, D[1], D[0]), P(u1, D[1], D[0]), P(u1, C[1], C[0]), P(u0, C[1], C[0])], (0, 0, -1), mats[0], part)
        self.b.poly_dir([P(u0, d_v[1], d_v[0]) for d_v in (A, B, C, D)], -self.U, mats[0], part)
        self.b.poly_dir([P(u1, d_v[1], d_v[0]) for d_v in (A, B, C, D)], self.U, mats[(n - 1) % len(mats)] if stripes else mats[0], part)

    def canopy(self, u0, u1, v, depth=1.2, th=0.16, mat="trim", part="detail", rods=False):
        """Flat entrance canopy slab."""
        self.box(u0, u1, v, v + th, 0.0, depth, mat, part, "k")
        if rods:
            for u in (u0 + 0.15, u1 - 0.15):
                a = self.P(u, v + th, depth - 0.15)
                c = self.P(u, v + th + depth * 0.8, 0.02)
                self.b.tube(a, c, 0.025, None, 4, "metal", "detail", "none")

    def text(self, text, uc, vc, px=0.1, mat="neon", d=0.2, part="detail"):
        """Block letters (5 px tall) centred on (uc, vc). Returns the text width."""
        rects, cols = text_rects(text)
        w = cols * px
        us = uc - w / 2.0
        vt = vc + 2.5 * px
        for (c0, r0, c1, r1) in rects:
            self.rect(us + c0 * px, us + c1 * px, vt - r1 * px, vt - r0 * px, mat, d, part)
        return w

    def sign(self, u0, u1, v0, v1, text="", board="sign", color="neon", border=None, proud=0.12, d0=0.0, pad=0.14, px=None):
        """Fascia sign board with block letters; border = material of a thin (neon) outline."""
        self.box(u0, u1, v0, v1, d0, d0 + proud, board, "detail", "k")
        d = d0 + proud + 0.02
        if border:
            bw = 0.05
            g = 0.06
            self.rect(u0 + g, u1 - g, v0 + g, v0 + g + bw, border, d, "detail")
            self.rect(u0 + g, u1 - g, v1 - g - bw, v1 - g, border, d, "detail")
            self.rect(u0 + g, u0 + g + bw, v0 + g + bw, v1 - g - bw, border, d, "detail")
            self.rect(u1 - g - bw, u1 - g, v0 + g + bw, v1 - g - bw, border, d, "detail")
        if text:
            cols = text_rects(text)[1]
            if px is None:
                px = min((v1 - v0 - 2 * pad) / 5.0, (u1 - u0 - 2 * pad) / cols)
            self.text(text, (u0 + u1) / 2.0, (v0 + v1) / 2.0, px, color, d, "detail")

    def blade_sign(self, u, v0, v1, depth=0.9, text="", board="sign", color="neon", th=0.12, px=None, gap=0.12):
        """Projecting vertical sign, readable from both directions along the street."""
        self.box(u - th / 2, u + th / 2, v0, v1, gap, gap + depth, board, "detail", "")
        self.box(u - 0.03, u + 0.03, v0 + 0.15, v0 + 0.21, 0.0, gap, "metal", "detail", "k f")
        self.box(u - 0.03, u + 0.03, v1 - 0.21, v1 - 0.15, 0.0, gap, "metal", "detail", "k f")
        chars = [ch for ch in text.upper() if ch != " "]
        if not chars:
            return
        if px is None:
            px = min((depth - 0.2) / 5.0, (v1 - v0 - 0.2) / (len(chars) * 6.0))
        for sf in (self.side_face(u + th / 2 + 0.015, gap, gap + depth, "+u"),
                   self.side_face(u - th / 2 - 0.015, gap, gap + depth, "-u")):
            tot = len(chars) * 6 * px - px
            vt = (v0 + v1) / 2.0 + tot / 2.0
            for i, ch in enumerate(chars):
                sf.text(ch, depth / 2.0, vt - 2.5 * px - i * 6 * px, px, color, 0.0, "detail")

    def neon_line(self, u0, u1, v, h=0.06, mat="neon", d=0.03):
        """Horizontal neon strip."""
        self.rect(u0, u1, v, v + h, mat, d, "detail")

    def balcony(self, u0, u1, v, depth=1.1, rail_h=1.0, style="solid", mat="trim", slab="concrete", rail="metal",
                th=0.14, part="body", sides=True):
        """Balcony: slab + balustrade. style "solid" (colour-block panel), "rail" (metal bars) or
        "panel" (solid panel with a metal top rail). sides=False for loggias between fin walls."""
        self.box(u0, u1, v - th, v, 0.0, depth, slab, part, "k" if sides else "k l r")
        t = 0.07
        if style == "solid":
            self.box(u0, u1, v, v + rail_h, depth - t, depth, mat, part, "b" if sides else "b l r")
            if sides:
                self.box(u0, u0 + t, v, v + rail_h, 0.0, depth - t, mat, part, "b k f")
                self.box(u1 - t, u1, v, v + rail_h, 0.0, depth - t, mat, part, "b k f")
        elif style == "panel":
            self.box(u0, u1, v + 0.08, v + rail_h - 0.12, depth - t, depth, mat, part, "")
            self.box(u0, u1, v + rail_h - 0.05, v + rail_h, depth - t, depth, rail, part, "")
            if sides:
                self.box(u0, u0 + t, v + 0.08, v + rail_h - 0.12, 0.0, depth - t, mat, part, "k f")
                self.box(u1 - t, u1, v + 0.08, v + rail_h - 0.12, 0.0, depth - t, mat, part, "k f")
                self.box(u0, u0 + t, v + rail_h - 0.05, v + rail_h, 0.0, depth - t, rail, part, "k f")
                self.box(u1 - t, u1, v + rail_h - 0.05, v + rail_h, 0.0, depth - t, rail, part, "k f")
        else:
            r = 0.05
            self.box(u0, u1, v + rail_h - r, v + rail_h, depth - r, depth, rail, part, "")
            self.box(u0, u0 + r, v + rail_h - r, v + rail_h, 0.0, depth - r, rail, part, "k f")
            self.box(u1 - r, u1, v + rail_h - r, v + rail_h, 0.0, depth - r, rail, part, "k f")
            n = max(1, int(round((u1 - u0) / 0.9)))
            for i in range(n + 1):
                u = u0 + (u1 - u0 - r) * i / n
                self.box(u, u + r, v, v + rail_h - r, depth - r, depth, rail, part, "t b")
            self.box(u0 + r, u1 - r, v + 0.15, v + 0.19, depth - r + 0.01, depth - 0.01, rail, part, "l r")

    def fire_escape(self, u0, u1, levels, depth=1.0, mat="metal", ladder_to=2.9, part="detail"):
        """Steel fire escape: one platform per level (v values) with rails, zig-zag stairs between
        them and a drop ladder under the lowest platform."""
        r = 0.05
        for i, v in enumerate(levels):
            self.box(u0, u1, v - 0.07, v, 0.03, depth, mat, part, "")
            self.box(u0, u1, v + 0.95, v + 1.0, depth - r, depth, mat, part, "")
            self.box(u0, u0 + r, v + 0.95, v + 1.0, 0.03, depth - r, mat, part, "k f")
            self.box(u1 - r, u1, v + 0.95, v + 1.0, 0.03, depth - r, mat, part, "k f")
            n = max(2, int(round((u1 - u0) / 1.2)))
            for k in range(n + 1):
                u = u0 + (u1 - u0 - r) * k / n
                self.box(u, u + r, v, v + 0.95, depth - r, depth, mat, part, "t b")
            self.box(u0 + r, u1 - r, v + 0.45, v + 0.5, depth - r + 0.01, depth - 0.01, mat, part, "l r")
            if i + 1 < len(levels):
                vn = levels[i + 1]
                if i % 2 == 0:
                    ua, ub = u0 + 0.35, u1 - 0.75
                else:
                    ua, ub = u1 - 0.35, u0 + 0.75
                sg = 1 if ub > ua else -1
                pts = [self.P(ua, v, 0.12), self.P(ua + sg * 0.4, v, 0.12), self.P(ub + sg * 0.4, vn - 0.07, 0.12), self.P(ub, vn - 0.07, 0.12)]
                self.b.extrude(pts, self.N * 0.55, mat, part)
        v = levels[0]
        ul = u1 - 0.3
        for du in (-0.22, 0.22):
            self.box(ul + du - 0.025, ul + du + 0.025, ladder_to, v - 0.07, depth - 0.2, depth - 0.15, mat, part, "t")
        zz = ladder_to + 0.15
        while zz < v - 0.2:
            self.box(ul - 0.22, ul + 0.22, zz, zz + 0.04, depth - 0.2, depth - 0.16, mat, part, "l r")
            zz += 0.4

    def steps(self, u0, u1, v_top, n=3, tread=0.3, rise=None, d0=0.0, mat="concrete", bottom=-0.4, part="body"):
        """Stair running down and outward from the wall (top step level v_top at d0)."""
        rise = rise or v_top / (n + 1.0)
        for i in range(n):
            top = v_top - rise * (i + 1)
            self.box(u0, u1, bottom, top, d0 + tread * i, d0 + tread * (i + 1), mat, part, "k b f")
            self.rect(u0, u1, bottom if i == n - 1 else top - rise, top, mat, d0 + tread * (i + 1), part)
        return d0 + tread * n

    def porch(self, u0, u1, depth=1.8, floor=0.4, post_h=2.4, posts=3, roof="roof", post="trim", deck="Wood",
              rail=True, step_u=None, step_w=1.4, drop=0.35, roof_over=0.25):
        """Covered porch: deck slab, posts, beam, lean-to roof, optional rails and front steps.
        step_u = u of the step centre (None = centre)."""
        self.box(u0, u1, -SKIRT, floor, 0.0, depth, deck, "body", "k b")
        top = floor + post_h
        pw = 0.14
        su = (u0 + u1) / 2.0 if step_u is None else step_u
        us = [u0 + (u1 - u0 - pw) * i / max(1, posts - 1) for i in range(posts)]
        for u in us:
            self.box(u, u + pw, floor, top, depth - pw - 0.04, depth - 0.04, post, "body", "t b")
        self.box(u0, u1, top, top + 0.2, depth - pw - 0.06, depth - 0.02, post, "body", "")
        self.prism([(0.0, top + 0.2 + drop), (depth + roof_over, top + 0.2), (depth + roof_over, top + 0.08), (0.0, top + 0.08 + drop)],
                   u0 - roof_over, u1 + roof_over, roof, closed=False)
        if rail:
            for ua, ub in zip(us[:-1], us[1:]):
                a, c = ua + pw, ub
                if a < su + step_w / 2 and c > su - step_w / 2:
                    continue
                self.box(a, c, floor + 0.8, floor + 0.86, depth - pw, depth - pw + 0.06, post, "body", "l r")
                self.box(a, c, floor + 0.15, floor + 0.2, depth - pw, depth - pw + 0.06, post, "body", "l r")
                k = max(1, int(round((c - a) / 0.5)))
                for i in range(1, k):
                    u = a + (c - a) * i / k
                    self.box(u - 0.025, u + 0.025, floor + 0.2, floor + 0.8, depth - pw + 0.005, depth - pw + 0.055, post, "body", "t b")
        nst = max(1, int(round(floor / 0.18)) - 1)
        return self.steps(su - step_w / 2, su + step_w / 2, floor, nst, 0.3, None, depth, "concrete")

    def dock(self, u0, u1, h=1.2, depth=2.4, mat="concrete", bumper="HazardYellow", steps="left", edge="HazardYellow"):
        """Raised loading dock platform with bumpers, a hazard edge strip and side steps."""
        self.box(u0, u1, -SKIRT, h, 0.0, depth, mat, "body", "k b")
        if edge:
            self.rect(u0, u1, h - 0.14, h - 0.02, edge, depth + 0.01, "detail")
        n = max(2, int(round((u1 - u0) / 4.0)) + 1)
        for i in range(n):
            u = u0 + 0.5 + (u1 - u0 - 1.0) * i / (n - 1)
            self.box(u - 0.15, u + 0.15, h - 0.75, h - 0.2, depth, depth + 0.1, "Black", "detail", "k")
        if steps:
            nst = max(2, int(round(h / 0.2)) - 1)
            tread = 0.3
            if steps == "left":
                f = self.side_face(u0, 0.0, depth, "-u")
            else:
                f = self.side_face(u1, 0.0, depth, "+u")
            f.steps(0.0 if steps == "right" else max(0.0, depth - 1.1), 1.1 if steps == "right" else depth, h, nst, tread, None, 0.0, mat)

    def dado(self, spans=None, h=1.2, proud=0.15, mat="base"):
        """Proud base course overlaid on the given (u0, u1) spans (default: the whole face). Use it on
        corrugated walls, and wherever a `base` level cannot be a separate storey because ground-level
        doors cut through it (leave the door spans out)."""
        lo = -SKIRT if self.z0 < EPS else 0.0
        for (u0, u1) in (spans or [(0.0, self.w)]):
            self.box(u0, u1, lo, h, 0.0, proud, mat, "body", "k b")

    def dress_shop(self, span, text, neon="neon", mats=("awning", "awning2"), stripes=6, v=3.15, inset=0.3, depth=1.1,
                   sign_h=0.72, board="sign", border=None, awning=True):
        """Fascia sign board with block-letter neon + a fabric awning over one shop bay.
        span = (u0, u1) as returned by row(); v = awning top (just above the shop head, default 3.15
        for K.shop(head=3.0)). mats = awning colours (one colour: pass stripes=0)."""
        a, c = span[0] + inset, span[1] - inset
        self.sign(a, c, v + 0.08, v + 0.08 + sign_h, text, board=board, color=neon, border=border)
        if awning:
            self.awning(a, c, v, depth=depth, drop=0.45, valance=0.2, mats=mats, stripes=stripes)

    def applied_window(self, uc, vc, w=0.8, h=0.8, mat="trim"):
        """Small framed window applied ON a wall without cutting it (gables, dormers, attics)."""
        self.box(uc - w / 2 - 0.09, uc + w / 2 + 0.09, vc - h / 2 - 0.09, vc + h / 2 + 0.09, 0.0, 0.05, mat, "body", "k")
        self.pane(uc - w / 2, uc + w / 2, vc - h / 2, vc + h / 2, 0.06)

    def bay_window(self, u0, u1, v0, v1, depth=0.5, mat="trim", roof="roof"):
        """Box bay window: glass on three sides, lean-to roof, splayed apron underneath."""
        self.box(u0, u1, v0, v1, 0.0, depth, mat, "body", "k")
        m = 0.12
        self.pane(u0 + m, u1 - m, v0 + 0.3, v1 - m, depth + 0.012, 3, 1)
        for sf in (self.side_face(u1 + 0.012, 0.0, depth, "+u"), self.side_face(u0 - 0.012, 0.0, depth, "-u")):
            sf.pane(0.08, depth - 0.08, v0 + 0.3, v1 - m, 0.0)
        self.prism([(0.0, v1 + 0.4), (depth + 0.14, v1), (depth + 0.14, v1 - 0.07), (0.0, v1 - 0.07)], u0 - 0.14, u1 + 0.14, roof,
                   closed=False)
        self.prism([(0.0, v0 - 0.3), (depth, v0), (0.0, v0)], u0, u1, mat, closed=False)

    # -- service-side dressing (side / rear walls) -------------------------------------------------------
    def wall_ladder(self, u, v0, v1, w=0.46, depth=0.16, mat="metal", part="body", step=0.42, hoops=0):
        """Fixed steel access ladder on a wall: two stringers + rungs, optional safety hoops near the top."""
        t = 0.045
        for uu in (u - w / 2, u + w / 2 - t):
            self.box(uu, uu + t, v0, v1, 0.0, depth, mat, part, "k b")
        n = max(1, int((v1 - v0 - 0.3) / step))
        for i in range(n):
            v = v0 + 0.3 + i * step
            self.box(u - w / 2 + t, u + w / 2 - t, v, v + 0.035, depth - 0.05, depth - 0.01, mat, part, "l r k b")
        for k in range(hoops):
            v = v1 - 0.35 - k * 0.9
            self.box(u - w / 2 - 0.12, u + w / 2 + 0.12, v, v + 0.05, depth, depth + 0.5, mat, part, "k t b")

    def downpipe(self, u, v0, v1, w=0.13, depth=0.13, mat="metal", part="body", head=True):
        """Square rainwater pipe with a hopper head at the top."""
        self.box(u - w / 2, u + w / 2, v0, v1, 0.0, depth, mat, part, "k b t")
        if head:
            self.box(u - w, u + w, v1 - 0.32, v1, 0.0, depth + 0.1, mat, part, "k")

    def poster(self, u0, u1, v0, v1, colors=("Coral", "Cream"), frame="trim", proud=0.06, part="body", split=0.28):
        """Framed poster / display case applied on a wall: trim frame + two colour blocks (palette keys)."""
        self.box(u0, u1, v0, v1, 0.0, proud, frame, part, "k")
        m = 0.09
        vs = v0 + m + (v1 - v0 - 2 * m) * split
        self.rect(u0 + m, u1 - m, vs, v1 - m, colors[0], proud + 0.012, part)
        self.rect(u0 + m, u1 - m, v0 + m, vs, colors[1 % len(colors)], proud + 0.012, part)

    def wall_light(self, u, v, mat="metal", lamp="LampWarm", part="detail", arm=0.3):
        """Small bulkhead / goose-neck light above a door (emissive lamp block)."""
        self.box(u - 0.14, u + 0.14, v, v + 0.08, 0.0, arm + 0.1, mat, part, "k")
        self.box(u - 0.1, u + 0.1, v - 0.07, v, arm - 0.12, arm + 0.06, lamp, part, "t")

    def vent_duct(self, u, v0, v1, w=0.6, depth=0.42, mat="Steel", part="body", cap=True):
        """Boxy exhaust duct running up a wall, with a splayed cowl on top."""
        self.box(u - w / 2, u + w / 2, v0, v1, 0.0, depth, mat, part, "k")
        n = max(1, int((v1 - v0) / 1.6))
        for i in range(1, n + 1):
            v = v0 + (v1 - v0) * i / (n + 1.0)
            self.box(u - w / 2 - 0.03, u + w / 2 + 0.03, v, v + 0.07, 0.0, depth + 0.03, mat, part, "k t b")
        if cap:
            self.box(u - w / 2 - 0.1, u + w / 2 + 0.1, v1, v1 + 0.3, 0.0, depth + 0.1, mat, part, "")


# ------------------------------------------------------------------------------------------------
# QA / export helpers (module level)
# ------------------------------------------------------------------------------------------------
def _children(name):
    root = bpy.data.objects.get(name)
    if root is None:
        raise RuntimeError("no asset root %r" % name)
    return root, [o for o in root.children_recursive if o.type == 'MESH']


def preview(names, out_name=None, views=("three_quarter", "front", "side", "top"), res=420, cull=True, **kw):
    """G.preview with backface culling switched on, so flipped faces show up as holes."""
    if isinstance(names, str):
        names = [names]
    out_name = out_name or ("bld_" + names[0])
    sh = bpy.context.scene.display.shading
    old = None
    try:
        old = sh.show_backface_culling
        sh.show_backface_culling = bool(cull)
    except Exception:
        pass
    try:
        return G.preview(names, out_name, views=views, res=res, **kw)
    finally:
        if old is not None:
            try:
                sh.show_backface_culling = old
            except Exception:
                pass


def closeup(name, lo, hi, out_name=None, views=("three_quarter", "front"), res=512):
    """Preview of a REGION of an asset (asset-local box lo..hi), e.g. the street level of a tower.
    Renders without isolation (neighbouring assets inside the frame stay visible)."""
    root = bpy.data.objects[name]
    bm = bmesh.new()
    for c in (lo, hi):
        G.add_box(bm, (0.02, 0.02, 0.02), c)
    fr = G.new_object("zz_closeup_frame", bm, parent=root, materials=[material("Charcoal")], uv=False)
    try:
        return preview(["zz_closeup_frame"], out_name or ("close_" + name), views=views, res=res, isolate=False, margin=1.0)
    finally:
        me = fr.data
        bpy.data.objects.remove(fr, do_unlink=True)
        bpy.data.meshes.remove(me)


def audit(name, verbose=True):
    """Heuristic mesh audit (informational). A face is "suspect" when the ray along its normal hits the
    BACK of another face more than 2 cm away while the ray behind it does not hit a back face, i.e.
    the solid seems to be in front of the face instead of behind it. Faces buried inside open-backed
    solids (step stacks, trims) are reported too, so read the list before worrying; flipped roof
    decks are caught by the top view of K.preview (backface culling). Also counts exact duplicate
    and degenerate faces."""
    root, meshes = _children(name)
    verts = []
    polys = []
    info = []
    inv = root.matrix_world.inverted()
    for ob in meshes:
        M = inv @ ob.matrix_world
        base = len(verts)
        verts.extend(M @ v.co for v in ob.data.vertices)
        for p in ob.data.polygons:
            polys.append([base + i for i in p.vertices])
            info.append(ob.name)
    bvh = BVHTree.FromPolygons(verts, polys, all_triangles=False)
    suspects = []
    dup = 0
    degenerate = 0
    seen = set()
    for pi, pl in enumerate(polys):
        pts = [verts[i] for i in pl]
        n = _newell(pts)
        if n.length / 2.0 < 1e-6:
            degenerate += 1
            continue
        n.normalize()
        key = tuple(sorted((round(p.x, 3), round(p.y, 3), round(p.z, 3)) for p in pts))
        if key in seen:
            dup += 1
        seen.add(key)
        c = sum(pts, Vector((0, 0, 0))) / len(pts)
        c = c + (pts[0] - c) * 0.137 + (pts[1] - c) * 0.071      # off-centre: avoid grazing shared edges
        hit = bvh.ray_cast(c + n * 0.01, n, 400.0)
        if hit[0] is None or hit[1].dot(n) <= 0.3 or hit[3] < 0.02:
            continue
        back = bvh.ray_cast(c - n * 0.01, -n, 400.0)
        if back[0] is not None and back[1].dot(-n) > 0.3:
            continue
        suspects.append((info[pi], tuple(round(x, 2) for x in c), tuple(round(x, 2) for x in n), round(hit[3], 2)))
    res = {"faces": len(polys), "suspect": len(suspects), "duplicates": dup, "degenerate": degenerate}
    if verbose:
        print("AUDIT %s: %s" % (name, res))
        for f in suspects[:10]:
            print("   suspect:", f)
    return res


def measure(name):
    """G.validate() plus the real footprint of the solid shell (`*_Building` object only)."""
    r = G.validate(name)
    root, meshes = _children(name)
    inv = root.matrix_world.inverted()
    body = next((o for o in meshes if o.name == name + "_Building"), None)
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    if body is not None:
        M = inv @ body.matrix_world
        for v in body.data.vertices:
            w = M @ v.co
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    mats = sorted(set(m.name for o in meshes for m in o.data.materials if m is not None))
    out = {
        "tris": r.get("tris", 0), "issues": r.get("issues", []),
        "footprint": [round(mx.x - mn.x, 2), round(mx.y - mn.y, 2)],
        "center": [round((mx.x + mn.x) / 2, 3), round((mx.y + mn.y) / 2, 3)],
        "height": round(r["max"][2], 2), "body_height": round(mx.z, 2),
        "full_min": [round(c, 2) for c in r["min"]], "full_max": [round(c, 2) for c in r["max"]],
        "surfaces": sum(len(o.data.materials) for o in meshes), "materials": mats,
        "objects": [o.name for o in meshes],
    }
    if body is not None:
        # how far Detail / Neon parts (awnings, marquees, signs) reach beyond the solid footprint, per side
        out["overhang"] = {
            "front": round(max(0.0, r["max"][1] - mx.y), 2), "back": round(max(0.0, mn.y - r["min"][1]), 2),
            "left": round(max(0.0, mn.x - r["min"][0]), 2), "right": round(max(0.0, r["max"][0] - mx.x), 2),
        }
    print("MEASURE %s: %s" % (name, json.dumps(out)))
    return out


def export(name, rel=None):
    """Export to gta/generated/models/buildings/<name>.glb with clean node names (`Building`,
    `Building_Glass`, ...). The `<name>_` prefix is stripped only for the duration of the export."""
    root, meshes = _children(name)
    mine = []
    others = []
    try:
        for ch in meshes:
            if not ch.name.startswith(name + "_"):
                continue
            clean = ch.name[len(name) + 1:]
            other = bpy.data.objects.get(clean)
            if other is not None and other is not ch:
                others.append((other, clean))
                other.name = "__kit_tmp_%d" % len(others)
            mine.append((ch, ch.name))
            ch.name = clean
        return G.export_glb(name, rel or ("buildings/%s.glb" % name))
    finally:
        for ch, old in mine:
            ch.name = old
        for other, clean in others:
            other.name = clean


def manifest_entry(name):
    """Build the manifest dict of a finished building from its stored metadata + real measurements."""
    root, _ = _children(name)
    meta = json.loads(root.get("gta_building", "{}"))
    ms = measure(name)
    fx, fy = ms["footprint"]
    ent = meta.get("entrance") or [0.0, fy / 2.0]
    boxes = []
    for (x0, x1, y0, y1, z0, z1) in meta.get("boxes", []):
        # Godot local space: (x, y, z) = (blender x, blender z, -blender y); [cx, cy, cz, sx, sy, sz]
        boxes.append([round((x0 + x1) / 2, 2), round((z0 + z1) / 2, 2), round(-(y0 + y1) / 2, 2),
                      round(x1 - x0, 2), round(z1 - z0, 2), round(y1 - y0, 2)])
    entry = {
        "id": name, "file": name + ".glb", "category": meta.get("category", "misc"),
        "footprint": [fx, fy], "height": ms["height"], "landmark": meta.get("landmark", ""),
        "collision": meta.get("collision", "box"), "entrance": [round(ent[0], 2), round(-ent[1], 2)],
        "tags": meta.get("tags", []),
        "roof_height": meta.get("roof_z", 0.0), "floors": meta.get("floors", 0), "tris": ms["tris"],
        "center_offset": [ms["center"][0], round(-ms["center"][1], 3)],
        "collision_boxes": boxes,
        "nodes": [o[len(name) + 1:] for o in ms["objects"]],
        # metres that non-solid parts (Building_Detail / Building_Neon) stick out of the footprint box;
        # front = street side (-Z in Godot), left = -X, right = +X, back = +Z
        "overhang": ms.get("overhang", {"front": 0.0, "back": 0.0, "left": 0.0, "right": 0.0}),
    }
    known = ("id", "category", "tags", "collision", "landmark", "entrance", "roof_z", "floors", "window_cells", "boxes")
    for k, v in meta.items():            # anything passed as finish(extra={...}) goes straight through
        if k not in known and k not in entry:
            entry[k] = v
    return entry


def write_manifest(path, names, extra=None):
    """Write {"buildings": [...]} for the given asset names (measured live from the scene)."""
    def clean(v):
        if isinstance(v, float):
            v = round(v, 3)
            return 0.0 if v == 0 else v
        if isinstance(v, (list, tuple)):
            return [clean(x) for x in v]
        if isinstance(v, dict):
            return dict((k, clean(x)) for k, x in v.items())
        return v

    entries = [clean(manifest_entry(n)) for n in names]
    data = {"buildings": entries}
    if extra:
        data.update(extra)
    folder = os.path.dirname(path)
    if folder and not os.path.isdir(folder):
        os.makedirs(folder)
    with open(path, "w") as fh:                     # one building per line: easy to read and to diff
        fh.write('{"buildings": [\n')
        fh.write(",\n".join("  " + json.dumps(e) for e in entries))
        fh.write("\n ]")
        for k, v in (extra or {}).items():
            fh.write(",\n " + json.dumps(k) + ": " + json.dumps(v))
        fh.write("\n}\n")
    print("MANIFEST:", path, len(entries))
    return data
