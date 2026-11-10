"""lm_common - shared helpers for the NEON TIDE landmark generators (lm_*.py).

Executed INSIDE the user's live Blender through the Blender MCP.  Only uses the public
gta_kit API (the kit itself is never edited).  Everything here is re-runnable.

    import sys, importlib
    p = r"<project>/tools/blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K, lm_common as C
    importlib.reload(K); importlib.reload(C)

Conventions used by all lm_* modules
  * asset space: metres, Z up, front = +Y, origin on the ground at the footprint centre
  * `sh`  = K.MB()   exterior / structure  -> part `shell`
  * `fx`  = C.DMB()  interior fixtures     -> part `fixtures`  (all colours forced to PaletteDry "@D:")
  * `col` = C.Col()  simplified collision  -> part `col` (boxes / convex prisms only, hidden in Blender)
  * markers: K.marker(root, name, pos, rot)  (+Y of the marker = forward; rot (0,0,180) looks toward -Y)
"""
import bpy
import json
import math
import os
import re
from contextlib import contextmanager, ExitStack
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import gta_kit as K

CAT = "Landmarks"
MANIFEST = os.path.join(K.PROJECT, "gta", "resources", "data", "manifests", "landmarks.json")
ORDER = ["shop_garage", "shop_guns", "safehouse", "shop_clothes", "shop_market", "shop_barber",
         "lm_gas_station", "lm_hangar", "lm_control_tower", "lm_terminal",
         "lm_radio_tower", "lm_water_tower", "lm_lighthouse", "lm_crane", "lm_parking_garage",
         "lm_fountain", "lm_statue", "lm_viewpoint", "lm_gazebo", "lm_boathouse",
         "rail_beam_8", "rail_pier", "rail_station", "lm_ferris_wheel", "lm_basketball"]

# Debug switch: build enterable buildings without roof / ceiling so the layout can be inspected from above.
OPEN_TOP = False
EPS = 1e-4


# --------------------------------------------------------------------------- builders
class DMB(K.MB):
    """Mesh builder for interiors: plain palette colours are painted with PaletteDry ("@D:<name>")."""

    def paint(self, faces, color):
        if not color.startswith("@"):
            color = "@D:" + color
        K.MB.paint(self, faces, color)


def bx(mb, lo, hi, color="gray_mid", **kw):
    """Box given by its min / max corners."""
    size = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
    pos = ((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, (lo[2] + hi[2]) * 0.5)
    return mb.box(size, pos, color, **kw)


def obox(mb, lo, hi, color="gray_mid", faces="+x-x+y-y+z"):
    """Open box: only the listed faces are created (2 tris each) - for stock on shelves, things on the floor."""
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    q = {"+x": ((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)),
         "-x": ((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)),
         "+y": ((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)),
         "-y": ((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)),
         "+z": ((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)),
         "-z": ((x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0))}
    out = []
    for k, p in q.items():
        if k in faces:
            out += mb.quad(p[0], p[1], p[2], p[3], color)
    return out


def room_occluders(x0, x1, y0, y1, z0, z1):
    """Virtual occluder rectangles (inner faces of a room) for cull_hidden(): (axis, coord, sign, u0, u1, v0, v1)."""
    return [(2, z0, 1, x0, x1, y0, y1), (2, z1, -1, x0, x1, y0, y1),
            (0, x0, 1, y0, y1, z0, z1), (0, x1, -1, y0, y1, z0, z1),
            (1, y0, 1, x0, x1, z0, z1), (1, y1, -1, x0, x1, z0, z1)]


def cull_hidden(mb, extra=(), tol=1.5e-3):
    """Delete axis-aligned rectangular faces that lie on the same plane as - and completely inside - an
    opposite-facing opaque rectangle (box bottoms on floors, backs against walls, stacked boxes, lintel ends...).
    Such faces look into solid matter and can never be seen.  Returns the number of faces removed."""
    bm = mb.bm
    bm.normal_update()
    opaque = set(i for i, s in enumerate(mb.slots) if s in ("Palette", "PaletteDry"))
    buckets = {}

    def key(ax, c):
        return (ax, int(round(c / 0.002)))

    recs = []
    for f in bm.faces:
        if len(f.verts) != 4:
            continue
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        if abs(n[ax]) < 0.9999:
            continue
        co = [v.co for v in f.verts]
        c = co[0][ax]
        u, v = [i for i in range(3) if i != ax]
        us = [p[u] for p in co]
        vs = [p[v] for p in co]
        u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
        if any(min(abs(p[u] - u0), abs(p[u] - u1)) > tol or min(abs(p[v] - v0), abs(p[v] - v1)) > tol for p in co):
            continue
        s = 1 if n[ax] > 0 else -1
        rec = (f, ax, c, s, u0, u1, v0, v1, f.material_index in opaque)
        recs.append(rec)
        if rec[8]:
            buckets.setdefault(key(ax, c), []).append(rec)
    for (ax, c, s, u0, u1, v0, v1) in extra:
        buckets.setdefault(key(ax, c), []).append((None, ax, c, s, u0, u1, v0, v1, True))
    dead = []
    for (f, ax, c, s, u0, u1, v0, v1, _op) in recs:
        k = key(ax, c)
        hit = False
        for dk in (-1, 0, 1):
            for b in buckets.get((k[0], k[1] + dk), ()):
                if b[0] is f or b[3] != -s or abs(b[2] - c) > tol:
                    continue
                if b[4] <= u0 + tol and b[5] >= u1 - tol and b[6] <= v0 + tol and b[7] >= v1 - tol:
                    hit = True
                    break
            if hit:
                break
        if hit:
            dead.append(f)
    if dead:
        import bmesh as _bmesh
        _bmesh.ops.delete(bm, geom=dead, context="FACES")
    return len(dead)


class Col:
    """Collects the simple convex solids of the `col` part."""
    COLOR = "hazard_yellow"

    def __init__(self):
        self.mb = K.MB()
        self.count = 0

    def box(self, lo, hi):
        if min(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]) < EPS:
            return
        bx(self.mb, lo, hi, self.COLOR)
        self.count += 1

    def cbox(self, size, pos, rot=None, base=False):
        self.mb.box(size, pos, self.COLOR, rot=rot, base=base)
        self.count += 1

    def cyl(self, r, h, pos, segs=8, axis="Z", base=True, r2=None):
        self.mb.cyl(r, h, pos, self.COLOR, axis=axis, segs=segs, r2=r2, base=base, smooth=False)
        self.count += 1

    def prism(self, pts2d, depth, plane="YZ", pos=(0, 0, 0), center=True):
        self.mb.prism(pts2d, depth, self.COLOR, plane=plane, pos=pos, center=center)
        self.count += 1

    def slope_x(self, x0, z0, x1, z1, y0, y1, thick=0.3):
        """Sloped slab running along X: top surface from (x0, z0) to (x1, z1), between y0..y1."""
        self.prism([(x0, z0), (x1, z1), (x1, z1 - thick), (x0, z0 - thick)], y1 - y0, plane="XZ",
                   pos=(0, (y0 + y1) * 0.5, 0))

    def slope_y(self, y0, z0, y1, z1, x0, x1, thick=0.3):
        """Sloped slab running along Y: top surface from (y0, z0) to (y1, z1), between x0..x1."""
        self.prism([(y0, z0), (y1, z1), (y1, z1 - thick), (y0, z0 - thick)], x1 - x0, plane="YZ",
                   pos=((x0 + x1) * 0.5, 0, 0))

    def hip(self, x0, x1, y0, y1, z, rise):
        """Closed convex hip-roof solid over the rectangle x0..x1 / y0..y1 standing on z."""
        w, d = x1 - x0, y1 - y0
        zr = z + rise
        A, B, C_, D = (x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)
        if w >= d:
            r0, r1 = (x0 + d * 0.5, (y0 + y1) * 0.5, zr), (x1 - d * 0.5, (y0 + y1) * 0.5, zr)
            faces = [[A, B, r1, r0], [C_, D, r0, r1], [B, C_, r1], [D, A, r0]]
        else:
            r0, r1 = ((x0 + x1) * 0.5, y0 + w * 0.5, zr), ((x0 + x1) * 0.5, y1 - w * 0.5, zr)
            faces = [[A, B, r0], [C_, D, r1], [B, C_, r1, r0], [D, A, r0, r1]]
        for f in faces:
            poly_up(self.mb, f, self.COLOR)
        self.mb.poly([D, C_, B, A], self.COLOR)
        self.count += 1

    def to_object(self, root, hide=True):
        obj = self.mb.to_object(root, "col")
        obj.display_type = "WIRE"
        if hide:
            try:
                bpy.context.view_layer.update()
                obj.hide_set(True)
            except Exception:
                pass
        return obj


@contextmanager
def at(pos, rz=0.0, *targets, scale=None):
    """Push the same local transform on several builders (MB / DMB / Col)."""
    with ExitStack() as st:
        for t in targets:
            if t is None:
                continue
            m = t.mb if isinstance(t, Col) else t
            st.enter_context(m.at(pos, rot=(0.0, 0.0, rz), scale=scale))
        yield


def facing(rz):
    """Unit vector (x, y) of local +Y after a Z rotation of rz degrees."""
    a = math.radians(rz)
    return (-math.sin(a), math.cos(a))


# --------------------------------------------------------------------------- walls / openings
def wall(mb, col, axis, a0, a1, c, z0, z1, ext, inn, out=1, t=0.25, openings=(), body=None):
    """Straight wall running along `axis` ('X' | 'Y') from a0 to a1; c = wall centre on the other axis.
    out = +1 / -1: the exterior is toward +/- of the other axis.  ext / inn = face colours.
    openings: (o0, o1, oz0, oz1[, kind]); kind 'open' (default) stays open in `col`, anything else
    ('glass') is cut in the visual wall only and stays solid in `col`."""
    body = body or ext
    side = "y" if axis == "X" else "x"
    colors = {("+" if out > 0 else "-") + side: ext, ("-" if out > 0 else "+") + side: inn}

    def corners(s0, s1, za, zb):
        if axis == "X":
            return (s0, c - t * 0.5, za), (s1, c + t * 0.5, zb)
        return (c - t * 0.5, s0, za), (c + t * 0.5, s1, zb)

    def run(ops, emit):
        cur = a0
        for o in ops:
            o0, o1 = max(o[0], a0), min(o[1], a1)
            oz0, oz1 = max(o[2], z0), min(o[3], z1)
            if o1 - o0 < EPS or oz1 - oz0 < EPS:
                continue
            emit(cur, o0, z0, z1)
            emit(o0, o1, oz1, z1)
            emit(o0, o1, z0, oz0)
            cur = o1
        emit(cur, a1, z0, z1)

    def vis(s0, s1, za, zb):
        if s1 - s0 > EPS and zb - za > EPS:
            lo, hi = corners(s0, s1, za, zb)
            bx(mb, lo, hi, body, colors=colors)

    def phys(s0, s1, za, zb):
        if s1 - s0 > EPS and zb - za > EPS:
            lo, hi = corners(s0, s1, za, zb)
            col.box(lo, hi)

    ops = sorted(openings, key=lambda o: o[0])
    if mb is not None:
        run(ops, vis)
    if col is not None:
        run([o for o in ops if (o[4] if len(o) > 4 else "open") == "open"], phys)


def pane(mb, axis, a0, a1, z0, z1, c, color="@Glass", out=1):
    """Flat quad in a wall plane.  axis 'X': the quad lies at y = c and faces out*Y; 'Y': x = c, faces out*X."""
    if axis == "X":
        p = [(a1, c, z0), (a0, c, z0), (a0, c, z1), (a1, c, z1)]
    else:
        p = [(c, a0, z0), (c, a1, z0), (c, a1, z1), (c, a0, z1)]
    if out < 0:
        p.reverse()
    return mb.quad(p[0], p[1], p[2], p[3], color)


def glazing(mb, axis, a0, a1, z0, z1, c, frame="steel_dark", every=1.6, fw=0.06, fd=0.10, hbars=(),
            glass="@Glass", out=1, n=None):
    """Framed glass filling the opening a0..a1 x z0..z1 of a wall along `axis` (frame centre plane = c).
    One pane quad (the @Glass shader is double sided), perimeter frame, mullions every ~`every` metres,
    optional horizontal bars at the heights in `hbars`."""
    def fb(s0, s1, za, zb, d=fd):
        if axis == "X":
            bx(mb, (s0, c - d * 0.5, za), (s1, c + d * 0.5, zb), frame)
        else:
            bx(mb, (c - d * 0.5, s0, za), (c + d * 0.5, s1, zb), frame)

    fb(a0, a1, z0, z0 + fw)
    fb(a0, a1, z1 - fw, z1)
    fb(a0, a0 + fw, z0 + fw, z1 - fw)
    fb(a1 - fw, a1, z0 + fw, z1 - fw)
    if n is None:
        n = max(1, int(round((a1 - a0) / every)))
    for i in range(1, n):
        s = a0 + (a1 - a0) * i / n
        fb(s - fw * 0.5, s + fw * 0.5, z0 + fw, z1 - fw)
    for hz in hbars:
        fb(a0 + fw, a1 - fw, hz - fw * 0.4, hz + fw * 0.4, fd * 0.8)
    if glass:
        pane(mb, axis, a0 + fw, a1 - fw, z0 + fw, z1 - fw, c, glass, out)


def band(mb, x0, x1, y0, y1, z0, z1, proud, color, gaps=None, sides="NSEW", flat=False, **kw):
    """Horizontal band wrapped around a rectangular building whose outer faces are x0..x1 / y0..y1,
    standing `proud` metres out of the wall.  gaps = {"N": [(a0, a1), ...]} leaves holes (doors).
    N = +Y face, S = -Y, E = +X, W = -X.  flat=True: painted stripe (quads `proud` in front of the wall)."""
    gaps = gaps or {}
    p = proud
    if flat:
        for sd, ax, c, o, a0, a1 in (("N", "X", y1 + p, 1, x0, x1), ("S", "X", y0 - p, -1, x0, x1),
                                     ("E", "Y", x1 + p, 1, y0, y1), ("W", "Y", x0 - p, -1, y0, y1)):
            if sd not in sides:
                continue
            cur = a0
            for g0, g1 in sorted(gaps.get(sd, [])) + [(a1, a1)]:
                if g0 - cur > EPS:
                    pane(mb, ax, cur, g0, z0, z1, c, color, o)
                cur = max(cur, g1)
        return

    def runs(a0, a1, gs):
        cur, out = a0, []
        for g0, g1 in sorted(gs):
            if g0 - cur > EPS:
                out.append((cur, g0))
            cur = max(cur, g1)
        if a1 - cur > EPS:
            out.append((cur, a1))
        return out

    if "N" in sides:
        for s0, s1 in runs(x0 - p, x1 + p, gaps.get("N", [])):
            bx(mb, (s0, y1, z0), (s1, y1 + p, z1), color, **kw)
    if "S" in sides:
        for s0, s1 in runs(x0 - p, x1 + p, gaps.get("S", [])):
            bx(mb, (s0, y0 - p, z0), (s1, y0, z1), color, **kw)
    if "E" in sides:
        for s0, s1 in runs(y0, y1, gaps.get("E", [])):
            bx(mb, (x1, s0, z0), (x1 + p, s1, z1), color, **kw)
    if "W" in sides:
        for s0, s1 in runs(y0, y1, gaps.get("W", [])):
            bx(mb, (x0 - p, s0, z0), (x0, s1, z1), color, **kw)


def band_in(mb, x0, x1, y0, y1, z0, z1, proud, color, gaps=None, sides="NSEW"):
    """Like band() but on the INSIDE faces of a room (x0..x1 / y0..y1 = interior faces)."""
    gaps = gaps or {}
    p = proud

    def runs(a0, a1, gs):
        cur, out = a0, []
        for g0, g1 in sorted(gs):
            if g0 - cur > EPS:
                out.append((cur, g0))
            cur = max(cur, g1)
        if a1 - cur > EPS:
            out.append((cur, a1))
        return out

    # painted bands: flat quads `proud` (>= 5 mm) in front of the wall faces
    if "N" in sides:
        for s0, s1 in runs(x0, x1, gaps.get("N", [])):
            pane(mb, "X", s0, s1, z0, z1, y1 - p, color, -1)
    if "S" in sides:
        for s0, s1 in runs(x0, x1, gaps.get("S", [])):
            pane(mb, "X", s0, s1, z0, z1, y0 + p, color, 1)
    if "E" in sides:
        for s0, s1 in runs(y0, y1, gaps.get("E", [])):
            pane(mb, "Y", s0, s1, z0, z1, x1 - p, color, -1)
    if "W" in sides:
        for s0, s1 in runs(y0, y1, gaps.get("W", [])):
            pane(mb, "Y", s0, s1, z0, z1, x0 + p, color, 1)


def parapet(mb, col, x0, x1, y0, y1, z0, h, color, cope="concrete_light", t=0.25, cope_h=0.08, over=0.04,
            sides="NSEW", inner=None):
    """Parapet walls on top of a flat roof (outer faces x0..x1 / y0..y1) with a proud coping."""
    z1 = z0 + h
    inner = inner or color
    segs = []
    if "N" in sides:
        segs.append(((x0, y1 - t, z0), (x1, y1, z1), {"-y": inner}))
    if "S" in sides:
        segs.append(((x0, y0, z0), (x1, y0 + t, z1), {"+y": inner}))
    if "E" in sides:
        segs.append(((x1 - t, y0 + t, z0), (x1, y1 - t, z1), {"-x": inner}))
    if "W" in sides:
        segs.append(((x0, y0 + t, z0), (x0 + t, y1 - t, z1), {"+x": inner}))
    for lo, hi, cs in segs:
        bx(mb, lo, hi, color, colors=cs)
        if col is not None:
            col.box(lo, (hi[0], hi[1], hi[2] + cope_h))
        if cope:
            bx(mb, (lo[0] - over, lo[1] - over, z1), (hi[0] + over, hi[1] + over, z1 + cope_h), cope)


def flat_roof(mb, col, x0, x1, y0, y1, zc, zr, ceil="@D:ceiling", top="roof_gravel", t=0.25):
    """Roof slab between the walls: underside (ceiling) at zc, top at zr.  x0..y1 = OUTER faces."""
    if not OPEN_TOP:
        bx(mb, (x0 + t, y0 + t, zc), (x1 - t, y1 - t, zr), top, colors={"-z": ceil})
    if col is not None:
        col.box((x0, y0, zc), (x1, y1, zr))


def floor_slab(mb, col, x0, x1, y0, y1, color, z=0.02, t=0.25, colfull=True):
    """Interior floor (top at z) inside the walls; col slab covers the whole footprint."""
    mb.quad((x0 + t, y0 + t, z), (x1 - t, y0 + t, z), (x1 - t, y1 - t, z), (x0 + t, y1 - t, z), color)
    if col is not None:
        col.box((x0, y0, 0.0), (x1, y1, z))


def threshold(mb, col, a0, a1, y_in, y_out, color="steel_dark", z=0.02, lip=0.3, axis="X"):
    """Floor piece through a door opening in a wall along X (from the interior face y_in to the exterior
    face y_out) plus a small sloped lip outside so there is no step."""
    s = 1.0 if y_out > y_in else -1.0
    lo_y, hi_y = min(y_in, y_out), max(y_in, y_out)
    mb.quad((a0, lo_y, z), (a1, lo_y, z), (a1, hi_y, z), (a0, hi_y, z), color)
    # lip: sloped quad + two side triangles
    yo, ye = y_out, y_out + s * lip
    pts = [(a0, yo, z), (a1, yo, z), (a1, ye, 0.0), (a0, ye, 0.0)]
    if s < 0:
        pts.reverse()
    mb.quad(pts[0], pts[1], pts[2], pts[3], color)
    t1 = [(a1, yo, z), (a1, yo, 0.0), (a1, ye, 0.0)]
    t2 = [(a0, yo, z), (a0, ye, 0.0), (a0, yo, 0.0)]
    if s < 0:
        t1.reverse()
        t2.reverse()
    mb.poly(t1, color)
    mb.poly(t2, color)
    if col is not None:
        col.prism([(yo, z), (ye, 0.0), (yo, 0.0)], a1 - a0, plane="YZ", pos=((a0 + a1) * 0.5, 0, 0))


# --------------------------------------------------------------------------- doors
def sliding_doors(root, sh, cx, y_in, into=-1, z0=0.02, w=1.6, h=2.4, frame="steel_dark", accent="white",
                  track="steel_dark"):
    """Two sliding glass leaves `door_l` / `door_r` (closed pose) hung on the INSIDE face of a wall along X.
    y_in = interior wall face, into = -1 when the room lies toward -Y.  Each leaf is w/2 wide, origin at its
    bottom centre, and slides w/2 along X away from the door centre.  Adds the head track to `sh`."""
    lw = w * 0.5
    yl = y_in + into * 0.05            # leaf centre plane (leaf 0.04 thick: 3..7 cm off the wall)
    zt = z0 + h
    # head track + floor guide (shell)
    bx(sh, (cx - w - 0.1, min(y_in, y_in + into * 0.11), zt + 0.005), (cx + w + 0.1, max(y_in, y_in + into * 0.11), zt + 0.13),
       "@D:" + track)
    out = []
    for name, sx in (("door_l", -1.0), ("door_r", 1.0)):
        mb = K.MB()
        xa, xb = (cx - lw, cx) if sx < 0 else (cx, cx + lw)
        fw = 0.05
        bx(mb, (xa, yl - 0.02, z0 + 0.005), (xa + fw, yl + 0.02, zt), frame)
        bx(mb, (xb - fw, yl - 0.02, z0 + 0.005), (xb, yl + 0.02, zt), frame)
        bx(mb, (xa + fw, yl - 0.02, zt - 0.07), (xb - fw, yl + 0.02, zt), frame)
        bx(mb, (xa + fw, yl - 0.02, z0 + 0.005), (xb - fw, yl + 0.02, z0 + 0.14), frame)
        pane(mb, "X", xa + fw, xb - fw, z0 + 0.14, zt - 0.07, yl, "@Glass", 1)
        # safety strip + pull handle on the meeting stile
        bx(mb, (xa + fw, yl - 0.026, z0 + 1.48), (xb - fw, yl + 0.026, z0 + 1.53), accent)
        hx = (xb - fw - 0.05) if sx < 0 else (xa + fw + 0.05)
        bx(mb, (hx - 0.015, yl - 0.05, z0 + 0.85), (hx + 0.015, yl + 0.05, z0 + 1.3), "chrome")
        obj = mb.to_object(root, name, origin=((xa + xb) * 0.5, yl, z0))
        out.append(obj)
    return out


def roll_door(root, part, x0, x1, yc, z0, z1, color="steel", bar="hazard_yellow", slat=0.25, depth=0.03,
              axis="X"):
    """Slatted roll-up door filling x0..x1 (wall along X, centre plane yc), z0..z1.  Origin at the centre of
    its TOP edge (Godot scales / slides it upward).  Returns the object."""
    mb = K.MB()
    n = max(2, int(round((z1 - z0 - 0.16) / slat)))
    pts_f, pts_b = [], []
    zb = z0 + 0.16
    step = (z1 - zb) / n
    for i in range(n):
        za = zb + i * step
        pts_f += [(yc + depth, za + 0.02), (yc + depth, za + step * 0.62), (yc + depth * 0.25, za + step * 0.80),
                  (yc + depth * 0.25, za + step)]
    pts_b = [(yc - depth, z1), (yc - depth, zb)]
    prof = pts_f + pts_b
    mb.prism(prof, x1 - x0, color, plane="YZ", pos=((x0 + x1) * 0.5, 0, 0), caps=(False, False))
    # bottom bar with rubber seal
    bx(mb, (x0, yc - depth - 0.01, z0 + 0.03), (x1, yc + depth + 0.02, z0 + 0.16), bar)
    bx(mb, (x0, yc - depth * 0.6, z0), (x1, yc + depth * 0.6, z0 + 0.03), "rubber")
    nst = max(3, int((x1 - x0) / 0.5))
    wst = (x1 - x0) / nst
    yf = yc + depth + 0.026
    for i in range(0, nst, 2):
        xa = x0 + i * wst
        mb.quad((xa + wst, yf, z0 + 0.04), (xa, yf, z0 + 0.04), (min(x1, xa + wst * 0.5), yf, z0 + 0.15),
                (min(x1, xa + wst * 1.5), yf, z0 + 0.15), "black")
    # lift handle
    xm = (x0 + x1) * 0.5
    bx(mb, (xm - 0.18, yc + depth, z0 + 0.5), (xm + 0.18, yc + depth + 0.045, z0 + 0.55), "steel_dark")
    return mb.to_object(root, part, origin=((x0 + x1) * 0.5, yc, z1))


# --------------------------------------------------------------------------- roofs
def poly_up(mb, pts, color, up=(0, 0, 1)):
    """n-gon whose normal is forced to point along `up` (roof faces)."""
    a, b, c = Vector(pts[0]), Vector(pts[1]), Vector(pts[2])
    n = (b - a).cross(c - b)
    if n.dot(Vector(up)) < 0:
        pts = list(reversed(pts))
    return mb.poly(pts, color)


def hip_roof(mb, x0, x1, y0, y1, z_eave, rise, color, fascia="white", soffit="white", eave_t=0.16):
    """Low hip roof over the rectangle x0..x1 / y0..y1 (eave line incl. overhang).  Ridge along the long axis."""
    w, d = x1 - x0, y1 - y0
    zb = z_eave - eave_t
    bx(mb, (x0, y0, zb), (x1, y1, z_eave), fascia, colors={"-z": soffit})
    zr = z_eave + rise
    A, B, C_, D = (x0, y0, z_eave), (x1, y0, z_eave), (x1, y1, z_eave), (x0, y1, z_eave)
    if w >= d:
        r0, r1 = (x0 + d * 0.5, (y0 + y1) * 0.5, zr), (x1 - d * 0.5, (y0 + y1) * 0.5, zr)
        poly_up(mb, [A, B, r1, r0], color)
        poly_up(mb, [C_, D, r0, r1], color)
        poly_up(mb, [B, C_, r1], color)
        poly_up(mb, [D, A, r0], color)
    else:
        r0, r1 = ((x0 + x1) * 0.5, y0 + w * 0.5, zr), ((x0 + x1) * 0.5, y1 - w * 0.5, zr)
        poly_up(mb, [A, B, r0], color)
        poly_up(mb, [C_, D, r1], color)
        poly_up(mb, [B, C_, r1, r0], color)
        poly_up(mb, [D, A, r0, r1], color)
    return r0, r1


# --------------------------------------------------------------------------- text / signs
_tm = {}


def text_metrics(text, spacing=1.0):
    """(xmin, xmax, zmin, zmax) of `text` at size 1.0 (K.add_text layout)."""
    key = (text, spacing)
    if key not in _tm:
        mb = K.MB()
        K.add_text(mb, text, size=1.0, depth=0.0, color="white", spacing=spacing)
        xs = [v.co.x for v in mb.bm.verts]
        zs = [v.co.z for v in mb.bm.verts]
        mb.bm.free()
        _tm[key] = (min(xs), max(xs), min(zs), max(zs))
    return _tm[key]


CAP_H = 0.69   # cap height of the kit font at size 1.0


def sign(mb, text, pos, max_w, max_h=None, color="neon_pink", depth=0.08, rot=None, res=2, spacing=1.0,
         valign="base"):
    """3D text fitted into max_w (and max_h = cap height limit).  pos = (centre x, y of the back plane,
    baseline z) - or the vertical centre of the capitals when valign='center'.  Returns (width, cap_h, size)."""
    xmin, xmax, zmin, zmax = text_metrics(text, spacing)
    w1 = xmax - xmin
    size = max_w / w1
    if max_h is not None:
        size = min(size, max_h / CAP_H)
    x, y, z = pos
    if valign == "center":
        z -= CAP_H * size * 0.5
    if rot is None:
        x -= (xmin + xmax) * 0.5 * size
    K.add_text(mb, text, size=size, depth=depth, color=color, pos=(x, y, z), rot=rot, res=res, spacing=spacing)
    return (w1 * size, CAP_H * size, size)


def disc(mb, c, r, color, axis="Y", segs=12, out=1, rot0=0.0):
    """Flat n-gon disc centred at c facing out*axis."""
    pts = []
    for k in range(segs):
        a = 2.0 * math.pi * k / segs + rot0
        u, v = math.cos(a) * r, math.sin(a) * r
        if axis == "Y":
            pts.append((c[0] - u, c[1], c[2] + v))
        elif axis == "X":
            pts.append((c[0], c[1] + u, c[2] + v))
        else:
            pts.append((c[0] + u, c[1] + v, c[2]))
    if out < 0:
        pts.reverse()
    return mb.poly(pts, color)


# --------------------------------------------------------------------------- lights
def ceiling_lights(root, fx, pts, zc, size=(1.2, 0.28), drop=0.0, emis="emis_warm_always", housing="steel_dark",
                   first=1):
    """Flat ceiling fixtures (housing + emissive diffuser) + markers light_<n> just below them."""
    for i, p in enumerate(pts):
        x, y = p[0], p[1]
        sx, sy = size if len(p) < 3 or p[2] == 0 else (size[1], size[0])
        zt = zc - drop
        if drop > 0.0:
            for d in ((-0.35, 0.35) if max(sx, sy) > 1.0 else (0.0,)):
                ox, oy = (d * sx, 0.0) if sx >= sy else (0.0, d * sy)
                obox(fx, (x + ox - 0.012, y + oy - 0.012, zt), (x + ox + 0.012, y + oy + 0.012, zc), housing,
                     "+x-x+y-y")
        bx(fx, (x - sx * 0.5, y - sy * 0.5, zt - 0.05), (x + sx * 0.5, y + sy * 0.5, zt), housing)
        obox(fx, (x - sx * 0.5 + 0.03, y - sy * 0.5 + 0.03, zt - 0.075), (x + sx * 0.5 - 0.03, y + sy * 0.5 - 0.03, zt - 0.05),
             emis, "+x-x+y-y-z")
        K.marker(root, "light_%d" % (first + i), (x, y, zt - 0.25))


# --------------------------------------------------------------------------- stats / manifest / export
def _nat(s):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", s)]


def stats(root):
    """-> (tris per part, bbox min, bbox max)  bbox = visual parts only (col excluded), asset space."""
    if isinstance(root, str):
        root = bpy.data.objects[root]
    bpy.context.view_layer.update()
    pre = root.name + "__"
    per = {}
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    rinv = root.matrix_world.inverted()
    for o in root.children_recursive:
        if o.type != "MESH":
            continue
        nm = o.name[len(pre):] if o.name.startswith(pre) else o.name
        o.data.calc_loop_triangles()
        per[nm] = len(o.data.loop_triangles)
        if nm == "col":
            continue
        m = rinv @ o.matrix_world
        for v in o.data.vertices:
            w = m @ v.co
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return per, lo, hi


def collect(root):
    pre = root.name + "__"
    parts, markers, origins = [], [], {}
    for o in root.children:
        nm = o.name[len(pre):] if o.name.startswith(pre) else o.name
        loc = [round(v, 4) for v in o.location]
        rot = [round(math.degrees(a), 3) for a in o.rotation_euler]
        if o.type == "MESH":
            parts.append(nm)
            if any(abs(v) > 1e-6 for v in loc) or any(abs(v) > 1e-6 for v in rot):
                origins[nm] = loc if not any(abs(v) > 1e-6 for v in rot) else {"pos": loc, "rot": rot}
        elif o.type == "EMPTY":
            markers.append({"name": nm, "pos": loc, "rot": rot,
                            "godot_pos": [loc[0], loc[2], round(-loc[1], 4)], "godot_yaw": rot[2]})
    rank = {"shell": 0, "mesh": 0, "base": 0, "fixtures": 1, "col": 99}
    parts.sort(key=lambda n: (rank.get(n, 50), _nat(n)))
    markers.sort(key=lambda m: _nat(m["name"]))
    return parts, markers, {k: origins[k] for k in sorted(origins, key=_nat)}


def _fmt_asset(a):
    out = ["  {"]
    for k, v in a.items():
        if k == "markers" and v:
            out.append('   "markers": [')
            for i, m in enumerate(v):
                out.append("    " + json.dumps(m) + ("," if i < len(v) - 1 else ""))
            out.append("   ],")
        else:
            out.append("   %s: %s," % (json.dumps(k), json.dumps(v)))
    out[-1] = out[-1].rstrip(",")
    out.append("  }")
    return "\n".join(out)


def update_manifest(entry):
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    data = {"assets": []}
    if os.path.exists(MANIFEST):
        try:
            with open(MANIFEST, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {"assets": []}
    assets = [a for a in data.get("assets", []) if a.get("id") != entry["id"]]
    assets.append(entry)
    assets.sort(key=lambda a: ORDER.index(a["id"]) if a["id"] in ORDER else 999)
    comment = ("Landmarks built by tools/blender/lm_*.py (see SPEC_LANDMARKS.md). size / bbox / marker pos+rot are in "
               "Blender asset space (metres, Z up, front = +Y, rot = XYZ euler degrees; a marker's +Y is its forward). "
               "godot_pos = (x, z, -y), godot_yaw = rotation about Godot +Y in degrees (marker forward = -Z rotated by "
               "yaw). part_origins = pivots of moving parts. tris includes the hidden `col` part (tris_col).")
    txt = "{\n \"_comment\": %s,\n \"assets\": [\n" % json.dumps(comment)
    txt += ",\n".join(_fmt_asset(a) for a in assets)
    txt += "\n ]\n}\n"
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(txt)
    return len(assets)


def finish(root, notes="", export=True, save=True):
    """Stats + export + manifest entry.  Returns a one-line summary."""
    if isinstance(root, str):
        root = bpy.data.objects[root]
    per, lo, hi = stats(root)
    parts, markers, origins = collect(root)
    tris = sum(per.values())
    entry = {"id": root.name, "glb": "landmarks/" + root.name, "category": CAT,
             "size": [round(hi[i] - lo[i], 3) for i in range(3)],
             "bbox_min": [round(v, 3) for v in lo], "bbox_max": [round(v, 3) for v in hi],
             "tris": tris, "tris_col": per.get("col", 0),
             "parts": parts}
    if origins:
        entry["part_origins"] = origins
    entry["markers"] = markers
    entry["notes"] = notes
    size = -1
    if export:
        # kit work-around: gta_kit passes export_loglevel=40, which makes Blender 5.2's glTF exporter raise
        # KeyError('loglevel') (it only fills export_settings['loglevel'] when the property is < 0).
        _path, size = K.export_asset(root, "landmarks/" + root.name, extra={"export_loglevel": -1})
        update_manifest(entry)
        if save:
            K.save_master()
    return "%s tris=%d %s size=%s min=%s max=%s parts=%d markers=%d glb=%d bytes" % (
        root.name, tris, per, entry["size"], entry["bbox_min"], entry["bbox_max"], len(parts), len(markers), size)


# --------------------------------------------------------------------------- numeric QA on the col mesh
def col_bvh(root):
    if isinstance(root, str):
        root = bpy.data.objects[root]
    obj = bpy.data.objects[root.name + "__col"]
    me = obj.data
    verts = [obj.matrix_local @ v.co for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    return BVHTree.FromPolygons(verts, polys)


_DIRS = [Vector(d) for d in ((0, 0, 1), (0, 0, -1), (1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0))]


def _inside(bvh, p):
    """True when p is inside one of the closed col solids (a ray leaving p exits through a back face first)."""
    for d in _DIRS:
        loc, nrm, _i, _d = bvh.ray_cast(p, d, 200.0)
        if loc is not None and nrm.dot(d) > 0.0:
            return True
    return False


def plan(root, x0, x1, y0, y1, z=2.0, zmin=0.06, cell=0.25, marks=True):
    """ASCII plan of the col mesh at walking height.  '#' solid up to z, '=' obstacle top >= 0.9 m,
    '-' low obstacle, '.' free floor.  Markers are drawn with the first letter of their name."""
    if isinstance(root, str):
        root = bpy.data.objects[root]
    bvh = col_bvh(root)
    nx = int(round((x1 - x0) / cell))
    ny = int(round((y1 - y0) / cell))
    grid = []
    down = Vector((0, 0, -1))
    for j in range(ny):
        y = y1 - (j + 0.5) * cell
        row = []
        for i in range(nx):
            x = x0 + (i + 0.5) * cell
            p = Vector((x, y, z))
            ch = "."
            if _inside(bvh, p):
                ch = "#"
            else:
                loc, _n, _i, _d = bvh.ray_cast(p, down, z - zmin)
                if loc is not None:
                    ch = "=" if loc.z >= 0.9 else "-"
            row.append(ch)
        grid.append(row)
    if marks:
        pre = root.name + "__"
        for o in root.children:
            if o.type != "EMPTY":
                continue
            nm = o.name[len(pre):]
            i = int((o.location.x - x0) / cell)
            j = int((y1 - o.location.y) / cell)
            if 0 <= i < nx and 0 <= j < ny:
                grid[j][i] = nm[-1] if nm.startswith("light_") else nm[0].upper()
    return "\n".join("".join(r) for r in grid)


def probe(root, names=None, radius=3.0):
    """For each marker: floor height under it, headroom above it and the nearest col surface at hip height."""
    if isinstance(root, str):
        root = bpy.data.objects[root]
    bvh = col_bvh(root)
    pre = root.name + "__"
    out = []
    for o in sorted(root.children, key=lambda o: _nat(o.name)):
        if o.type != "EMPTY":
            continue
        nm = o.name[len(pre):]
        if names is not None and nm not in names:
            continue
        p = Vector(o.location)
        f = bvh.ray_cast(p + Vector((0, 0, 0.5)), Vector((0, 0, -1)), 30.0)
        u = bvh.ray_cast(p + Vector((0, 0, 0.05)), Vector((0, 0, 1)), 60.0)
        near = radius
        for k in range(16):
            a = math.pi * 2.0 * k / 16
            h = bvh.ray_cast(p + Vector((0, 0, 0.9)), Vector((math.cos(a), math.sin(a), 0)), radius)
            if h[0] is not None:
                near = min(near, h[3])
        fw = facing(math.degrees(o.rotation_euler.z))
        out.append("%-12s pos=(%.2f, %.2f, %.2f) rz=%.0f fwd=(%.0f,%.0f) floor=%s head=%s clear=%.2f" % (
            nm, p.x, p.y, p.z, math.degrees(o.rotation_euler.z), fw[0], fw[1],
            ("%.3f" % f[0].z) if f[0] is not None else "none",
            ("%.2f" % u[3]) if u[0] is not None else "open", near))
    return "\n".join(out)


def ray(root, origin, direction, dist=50.0):
    """Single ray against the col mesh -> hit distance or None."""
    bvh = col_bvh(root)
    d = Vector(direction).normalized()
    h = bvh.ray_cast(Vector(origin), d, dist)
    return None if h[0] is None else round(h[3], 3)


def opening_clear(root, axis, a0, a1, z0, z1, c, depth=1.0, n=5):
    """Shoot rays through an opening (wall along `axis` at coordinate c) -> True when nothing blocks it."""
    bvh = col_bvh(root)
    ok = True
    for i in range(n):
        a = a0 + (a1 - a0) * (i + 0.5) / n
        for k in range(n):
            zz = z0 + (z1 - z0) * (k + 0.5) / n
            if axis == "X":
                o, d = Vector((a, c + depth, zz)), Vector((0, -1, 0))
            else:
                o, d = Vector((c + depth, a, zz)), Vector((-1, 0, 0))
            if bvh.ray_cast(o, d, depth * 2.0)[0] is not None:
                ok = False
    return ok


def show(root, col=False, shell=True, fixtures=True):
    """Toggle viewport visibility of the main parts for QA looks (export is unaffected)."""
    if isinstance(root, str):
        root = bpy.data.objects[root]
    bpy.context.view_layer.update()
    for nm, vis in (("col", col), ("shell", shell), ("fixtures", fixtures)):
        o = bpy.data.objects.get(root.name + "__" + nm)
        if o is not None:
            o.hide_set(not vis)


# =========================================================================== shell helpers (P1 shops, airfield ...)
def ground_occ(x0, x1, y0, y1, z=0.0):
    """cull_hidden() occluder for the ground plane under a footprint (removes faces lying on z looking down)."""
    return [(2, z, 1, x0, x1, y0, y1)]


def box_shell(sh, fx, col, X0, X1, Y0, Y1, T=0.25, ZF=0.02, ZC=3.2, ZR=3.45, ZP=4.0, ext="white",
              inn="@D:wall_interior", floor="@D:concrete", ceil="@D:ceiling", roof="roof_gravel",
              cope="concrete_light", front=(), back=(), left=(), right=(), parapet_sides="NSEW", body=None,
              parapet_color=None, parapet_inner=None):
    """Enterable box building: four T-thick walls (front = +Y wall) with openings in the wall() format
    (front / back run along X, left (-X) / right (+X) along Y between the front and back walls), the interior
    floor quad at ZF (into `fx`), the roof slab (ceiling ZC, top ZR) and a parapet up to ZP."""
    yn, ys, xe, xw = Y1 - T * 0.5, Y0 + T * 0.5, X1 - T * 0.5, X0 + T * 0.5
    yi0, yi1 = Y0 + T, Y1 - T
    wall(sh, col, "X", X0, X1, yn, 0.0, ZR, ext, inn, 1, T, front, body)
    wall(sh, col, "X", X0, X1, ys, 0.0, ZR, ext, inn, -1, T, back, body)
    wall(sh, col, "Y", yi0, yi1, xe, 0.0, ZR, ext, inn, 1, T, right, body)
    wall(sh, col, "Y", yi0, yi1, xw, 0.0, ZR, ext, inn, -1, T, left, body)
    if fx is not None:
        floor_slab(fx, col, X0, X1, Y0, Y1, floor, ZF, T)
    flat_roof(sh, col, X0, X1, Y0, Y1, ZC, ZR, ceil, roof, T)
    if ZP > ZR + 0.1:
        parapet(sh, col, X0, X1, Y0, Y1, ZR, ZP - ZR - 0.08, parapet_color or ext, cope, T, sides=parapet_sides,
                inner=parapet_inner)


def door_surround(mb, x0, x1, z1, y, w=0.08, proud=0.04, color="steel_dark", out=1, z0=0.0):
    """Proud frame around a door opening x0..x1 x z0..z1 on a wall face at y (that face looks out*Y)."""
    ya, yb = (y, y + proud) if out > 0 else (y - proud, y)
    bx(mb, (x0 - w, ya, z0), (x0, yb, z1 + w), color)
    bx(mb, (x1, ya, z0), (x1 + w, yb, z1 + w), color)
    bx(mb, (x0, ya, z1), (x1, yb, z1 + w), color)


def bars(mb, a0, a1, z0, z1, y, step=0.3, s=0.032, color="steel", rails=True):
    """Security grille in a window reveal on a wall facing +Y: vertical square bars between y and y + s,
    flat rails near the top and bottom."""
    n = max(2, int(round((a1 - a0) / step)))
    for i in range(1, n):
        x = a0 + (a1 - a0) * i / n
        bx(mb, (x - s * 0.5, y, z0), (x + s * 0.5, y + s, z1), color)
    if rails:
        for z in (z0 + 0.1, z1 - 0.1):
            bx(mb, (a0, y + s, z - 0.03), (a1, y + s + 0.012, z + 0.03), color)


def neon_path(mb, pts, y, w=0.05, d=0.035, color="neon_orange", out=1):
    """Neon tube along a polyline of (x, z) points on a wall plane at y facing out*Y (axis aligned segments)."""
    ya, yb = (y, y + d) if out > 0 else (y - d, y)
    for a, b in zip(pts, pts[1:]):
        bx(mb, (min(a[0], b[0]) - w * 0.5, ya, min(a[1], b[1]) - w * 0.5),
           (max(a[0], b[0]) + w * 0.5, yb, max(a[1], b[1]) + w * 0.5), color)


def roof_ac(sh, col, x, y, z, w=1.6, d=1.1, h=0.8, color="gray_light", rz=0.0):
    """Rooftop AC unit on a steel skid."""
    with sh.at((x, y, z), rot=(0, 0, rz)):
        bx(sh, (-w * 0.5 - 0.08, -d * 0.5 - 0.08, 0.0), (w * 0.5 + 0.08, d * 0.5 + 0.08, 0.1), "steel_dark")
        bx(sh, (-w * 0.5, -d * 0.5, 0.1), (w * 0.5, d * 0.5, h), color, bevel=0.03)
        disc(sh, (w * 0.2, 0.0, h + 0.005), min(w, d) * 0.32, "charcoal", axis="Z", segs=10)
        for k in range(3):
            pane(sh, "X", -w * 0.45, -w * 0.05, 0.25 + k * 0.15, 0.32 + k * 0.15, d * 0.5 + 0.006, "gray_dark", 1)
    if col is not None:
        c, s_ = math.cos(math.radians(rz)), math.sin(math.radians(rz))
        ex = abs(c) * w * 0.5 + abs(s_) * d * 0.5
        ey = abs(s_) * w * 0.5 + abs(c) * d * 0.5
        col.box((x - ex, y - ey, z), (x + ex, y + ey, z + h))


def wall_lamp(mb, x, y, z, out=1, color="steel_dark", axis="X", w=0.36):
    """Small box wall lamp (lit underside) on a wall at y (axis 'X') / x (axis 'Y') looking out."""
    if axis == "X":
        ya, yb = (y, y + 0.22 * out) if out > 0 else (y + 0.22 * out, y)
        bx(mb, (x - w * 0.5, ya, z), (x + w * 0.5, yb, z + 0.1), color, colors={"-z": "emis_lamp"})
    else:
        xa, xb = (x, x + 0.22 * out) if out > 0 else (x + 0.22 * out, x)
        bx(mb, (xa, y - w * 0.5, z), (xb, y + w * 0.5, z + 0.1), color, colors={"-z": "emis_lamp"})


QA_TARGET = "zz_lm_qa_target"


def qa_target(root, pos=None, remove=False):
    """Temporary Empty (owned by the landmark tooling) used as a `look` target at an asset-space point, e.g. to
    stand inside a room.  qa_target(root, remove=True) deletes it again."""
    o = bpy.data.objects.get(QA_TARGET)
    if remove:
        if o is not None:
            bpy.data.objects.remove(o, do_unlink=True)
        return None
    if isinstance(root, str):
        root = bpy.data.objects[root]
    if o is None:
        o = bpy.data.objects.new(QA_TARGET, None)
        o.empty_display_size = 0.05
        for c in root.users_collection:
            c.objects.link(o)
    o.location = root.matrix_world @ Vector(pos)
    return o.name


def qa(root, zf=0.02, ground=("entrance",), skip_z=()):
    """One-line stats + marker sanity: tris visual / col, bbox, parts, markers with z.  Flags markers whose z is
    neither the interior floor (zf) nor the ground (0) unless listed in skip_z."""
    if isinstance(root, str):
        root = bpy.data.objects[root]
    per, lo, hi = stats(root)
    vis = sum(v for k, v in per.items() if k != "col")
    parts, markers, origins = collect(root)
    bad = []
    for m in markers:
        z = m["pos"][2]
        if m["name"].startswith("light_") or m["name"] in skip_z:
            continue
        want = 0.0 if m["name"] in ground else zf
        if abs(z - want) > 1e-3:
            bad.append("%s z=%.3f" % (m["name"], z))
    ctr = ((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5)
    return ("%s vis=%d col=%d parts=%s size=(%.2f, %.2f, %.2f) min=(%.2f, %.2f, %.2f) bbox_ctr=(%.2f, %.2f) markers=%s%s"
            % (root.name, vis, per.get("col", 0), {k: v for k, v in per.items()},
               hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2], lo[0], lo[1], lo[2], ctr[0], ctr[1],
               ",".join(m["name"] for m in markers), (" BAD: " + "; ".join(bad)) if bad else ""))
