"""props_shapes - extra geometry + QA helpers shared by the second batch of prop generators
(props_nature.py, props_fences.py, props_yard.py, props_beach.py, props_misc.py).

Builds only on gta_kit + props_common (never edits them).  Runs inside Blender:

    import props_common as P, props_shapes as S, props_nature as N
    print(S.run(N.IDS))        # build + export + manifest + save, returns the QA report
"""
import contextlib
import io
import math
import random

import bpy
import bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

import gta_kit as K
import props_common as P


# --------------------------------------------------------------------------- tubes / limbs
def tube_rings(pts, radii, segs=6, spin=0.0):
    """Rings (counter-clockwise around the travel direction) along a polyline, twist-free frame."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    if isinstance(radii, (int, float)):
        radii = [radii] * n
    tans = []
    for i in range(n):
        if i == 0:
            d = pts[1] - pts[0]
        elif i == n - 1:
            d = pts[-1] - pts[-2]
        else:
            d = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
        if d.length < 1e-7:
            d = Vector((0, 0, 1))
        tans.append(d.normalized())
    t0 = tans[0]
    ref = Vector((1, 0, 0)) if abs(t0.x) < 0.9 else Vector((0, 1, 0))
    side = t0.cross(ref).normalized()
    rings = []
    for i in range(n):
        t = tans[i]
        side = side - t * side.dot(t)
        if side.length < 1e-6:
            side = t.cross(Vector((0, 0, 1)))
            if side.length < 1e-6:
                side = t.cross(Vector((1, 0, 0)))
        side.normalize()
        up = t.cross(side).normalized()
        ring = []
        for k in range(segs):
            a = spin + 2.0 * math.pi * k / segs
            ring.append(pts[i] + (side * math.cos(a) + up * math.sin(a)) * radii[i])
        rings.append(ring)
    return rings


def limb(mb, pts, radii, color="bark", segs=6, cap0=False, cap1=True, ring_colors=None, spin=0.0, tip=False,
         cap_color=None, smooth=False):
    """Tapered tube with explicit outward winding (no normal recalculation, safe for open ends).
    tip=True: the last point is a pointed apex (fan) instead of a ring."""
    rings = tube_rings(pts, radii, segs, spin)
    if mb._flipped(mb.M):                       # mirrored local frame: keep the winding outward
        rings = [list(reversed(r)) for r in rings]
    body = rings[:-1] if tip else rings
    faces = []
    if len(body) >= 2:
        faces = mb.loft(body, color, closed=True, cap_start=cap0, cap_end=(cap1 and not tip), smooth=smooth,
                        ring_colors=ring_colors, fix_normals=False)
        ncap = (1 if cap0 else 0) + (1 if (cap1 and not tip) else 0)
        if cap_color and ncap:
            mb.paint(faces[-ncap:], cap_color)
    if tip:
        last = body[-1]
        apex = Vector(pts[-1])
        c = ring_colors[len(body) - 1] if ring_colors and len(ring_colors) >= len(body) and ring_colors[len(body) - 1] else color
        for k in range(segs):
            f = mb.poly([last[k], last[(k + 1) % segs], apex], c)
            f.smooth = smooth
            faces.append(f)
    return faces


# --------------------------------------------------------------------------- leaves
def frond(mb, spine, widths, lat, top="@F:palm_green", bot="@F:leaf_dark", fold=0.3, colors=None):
    """V-folded double-sided leaf along `spine`; widths per point (0 = pointed end), lat = lateral unit vector.
    The fold drops both edges by width*fold below the spine.  colors: optional top colour per segment."""
    spine = [Vector(p) for p in spine]
    lat = Vector(lat).normalized()
    n = len(spine)
    L, R, N = [], [], []
    for i in range(n):
        if i == 0:
            t = spine[1] - spine[0]
        elif i == n - 1:
            t = spine[-1] - spine[-2]
        else:
            t = spine[i + 1] - spine[i - 1]
        t.normalize()
        nrm = t.cross(lat)
        if nrm.length < 1e-6:
            nrm = Vector((0, 0, 1))
        nrm.normalize()
        w = widths[i]
        L.append(spine[i] - lat * (w * 0.5) - nrm * (w * fold))
        R.append(spine[i] + lat * (w * 0.5) - nrm * (w * fold))
        N.append(nrm)
    out = []
    for i in range(n - 1):
        up = N[i] + N[i + 1]
        ct = colors[i] if colors else top
        for quad in ((spine[i], spine[i + 1], L[i + 1], L[i]), (spine[i], R[i], R[i + 1], spine[i + 1])):
            pts = []
            for p in quad:
                if not pts or (p - pts[-1]).length > 1e-5:
                    pts.append(p)
            if len(pts) > 2 and (pts[0] - pts[-1]).length < 1e-5:
                pts.pop()
            if len(pts) < 3:
                continue
            out.append(P.fpoly(mb, pts, ct, up))
            out.append(P.fpoly(mb, list(reversed(pts)), bot, -up))
    return out


def arc_spine(base, azim, elev, length, droop, nseg=4, power=1.3):
    """Points of a leaf spine leaving `base` at azimuth/elevation (radians) and bending down by `droop` rad."""
    p = Vector(base)
    dh = Vector((math.cos(azim), math.sin(azim), 0.0))
    pts = [p.copy()]
    step = length / nseg
    for i in range(nseg):
        s = (i + 0.5) / nseg
        e = elev - droop * (s ** power)
        p = p + (dh * math.cos(e) + Vector((0, 0, 1)) * math.sin(e)) * step
        pts.append(p.copy())
    return pts, Vector((-math.sin(azim), math.cos(azim), 0.0))


# --------------------------------------------------------------------------- foliage blobs
_INNER = {1: 0.74, 2: 0.9, 3: 0.96}


def canopy(mb, blobs, color="@F:leaf_green", dark="@F:leaf_dark", light=None, speckle=0.1, jitter=0.18, cull=True,
           floor=None):
    """Jittered ico foliage blobs; faces completely hidden inside another blob are removed.
    blobs: dicts with r, pos and optional scale, seed, subdiv, color, dark, light, jitter, speckle, dark_z, light_z.
    floor: faces completely below this z are removed too (bushes)."""
    groups = []
    for i, b in enumerate(blobs):
        sc = b.get("scale", (1.0, 1.0, 1.0))
        sub = b.get("subdiv", 2)
        jit = b.get("jitter", jitter)
        faces = P.blob(mb, b["r"], b["pos"], b.get("color", color), dark=b.get("dark", dark),
                       light=b.get("light", light), subdiv=sub, jitter=jit, seed=b.get("seed", i + 1), scale=sc,
                       speckle=b.get("speckle", speckle), dark_z=b.get("dark_z", -0.3), light_z=b.get("light_z", 0.6))
        k = (1.0 - jit) * _INNER.get(sub, 0.9) - 0.02
        groups.append((faces, Vector(b["pos"]), Vector((b["r"] * sc[0] * k, b["r"] * sc[1] * k, b["r"] * sc[2] * k))))
    kill = set()
    if cull:
        for i, (faces, _c, _r) in enumerate(groups):
            for f in faces:
                for j, (_f2, c2, r2) in enumerate(groups):
                    if i == j:
                        continue
                    if all(((v.co.x - c2.x) / r2.x) ** 2 + ((v.co.y - c2.y) / r2.y) ** 2 +
                           ((v.co.z - c2.z) / r2.z) ** 2 < 1.0 for v in f.verts):
                        kill.add(f)
                        break
    if floor is not None:
        for faces, _c, _r in groups:
            for f in faces:
                if all(v.co.z < floor for v in f.verts):
                    kill.add(f)
    if kill:
        bmesh.ops.delete(mb.bm, geom=list(kill), context="FACES")
    return [f for g in groups for f in g[0] if f.is_valid]


# --------------------------------------------------------------------------- whole-mesh transforms
def bbox(mb):
    xs = [v.co.x for v in mb.bm.verts]
    ys = [v.co.y for v in mb.bm.verts]
    zs = [v.co.z for v in mb.bm.verts]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def move(mb, off):
    off = Vector(off)
    for v in mb.bm.verts:
        v.co += off


def recenter_xy(mb):
    lo, hi = bbox(mb)
    move(mb, (-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, 0.0))


def fit_height(mb, h):
    """Uniform scale about the origin so the highest point sits at z = h."""
    lo, hi = bbox(mb)
    s = h / hi.z
    for v in mb.bm.verts:
        v.co *= s
    return s


def fit_box(mb, size, zmin=None):
    """Non-uniform scale so the bbox becomes `size` (None = keep that axis), centred in XY; the z = 0 plane is
    kept unless zmin is given (then the bbox bottom lands on zmin and the top on zmin + size z)."""
    lo, hi = bbox(mb)
    cx, cy = (lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5
    sx = size[0] / (hi.x - lo.x) if size[0] else 1.0
    sy = size[1] / (hi.y - lo.y) if size[1] else 1.0
    if size[2]:
        sz = size[2] / (hi.z - lo.z) if zmin is not None else size[2] / hi.z
    else:
        sz = 1.0
    for v in mb.bm.verts:
        z = (v.co.z - lo.z) * sz + zmin if (zmin is not None and size[2]) else v.co.z * sz
        v.co = Vector(((v.co.x - cx) * sx, (v.co.y - cy) * sy, z))


def repaint(mb, faces, fn):
    """fn(face) -> colour or None; faces must have fresh normals."""
    for f in faces:
        if not f.is_valid:
            continue
        f.normal_update()
        c = fn(f)
        if c:
            mb.paint([f], c)


# --------------------------------------------------------------------------- QA
def open_shell_check(me):
    """Number of open shells (>= 4 faces) whose normals mostly look INTO the shell (likely inside-out)."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bm.faces.index_update()
    bm.normal_update()
    isl_of = {}
    islands = []
    for f in bm.faces:
        if f.index in isl_of:
            continue
        idx = len(islands)
        stack = [f]
        isl_of[f.index] = idx
        cur = []
        while stack:
            g = stack.pop()
            cur.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in isl_of:
                        isl_of[h.index] = idx
                        stack.append(h)
        islands.append(cur)
    tree = BVHTree.FromBMesh(bm)
    bad = []
    for idx, isl in enumerate(islands):
        if len(isl) < 4:
            continue
        if all(len(e.link_faces) == 2 for g in isl for e in g.edges):
            continue
        hits = 0
        solid_behind = 0
        for f in isl:
            c = f.calc_center_median()
            n = f.normal
            _loc, _nrm, fi, _dist = tree.ray_cast(c + n * 1e-3, n, 60.0)
            if fi is not None and isl_of.get(fi) == idx:
                hits += 1
            # bores / recesses face inward legitimately: behind such a face there is material, i.e. a ray going
            # backwards leaves the solid through a back face (its normal points along the ray)
            _l2, n2, f2, _d2 = tree.ray_cast(c - n * 1e-3, -n, 5.0)
            if f2 is not None and n2.dot(-n) > 0.0:
                solid_behind += 1
        if hits > len(isl) * 0.5 and solid_behind < len(isl) * 0.5:
            c = sum((f.calc_center_median() for f in isl), Vector()) / len(isl)
            bad.append((len(isl), tuple(round(x, 2) for x in c)))
    bm.free()
    return bad


def qa(ids, budget=None):
    """Short stats line per asset (+ flags)."""
    lines = []
    for aid in ids:
        st = P.stats(aid)
        root = bpy.data.objects[aid]
        flag = ""
        if st["inverted"]:
            flag += " !!INVERTED %d" % st["inverted"]
        if st["degenerate"]:
            flag += " !!ZERO-AREA %d" % st["degenerate"]
        sus = []
        for o in root.children_recursive:
            if o.type == "MESH":
                for n, c in open_shell_check(o.data):
                    sus.append("%s:%df@%s" % (P._part(o, root), n, c))
        if sus:
            flag += " ??inward-open-shells " + " ".join(sus[:4])
        if budget and st["tris"] > budget.get(aid, 10 ** 9):
            flag += " !!OVER BUDGET %d" % budget[aid]
        lines.append("%-22s tris %4d +%-3d size %-22s z %5.2f..%5.2f parts %s%s%s" % (
            aid, st["tris"], st["helper_tris"], st["size"], st["min"][2], st["max"][2], ",".join(st["parts"]),
            (" markers " + ",".join(st["markers"])) if st["markers"] else "", flag))
    return "\n".join(lines)


STAGE = (-150.0, -400.0, 0.0)          # empty corner of the master scene used for QA pictures


def stage(ids, gap=0.6, origin=STAGE, rows=1):
    """Line the assets up (left -> right as seen from +Y, the asset front) on the empty QA stage.
    Call the module's do_layout() afterwards to send them back to their contact sheets."""
    bpy.context.view_layer.update()
    per_row = (len(ids) + rows - 1) // rows
    y = origin[1]
    for r in range(rows):
        chunk = ids[r * per_row:(r + 1) * per_row]
        boxes = [P.stats(a) for a in chunk]
        total = sum(b["size"][0] for b in boxes) + gap * (len(chunk) - 1)
        x = origin[0] + total * 0.5
        depth = 0.0
        for a, b in zip(chunk, boxes):
            o = bpy.data.objects[a]
            o.location = (x - b["max"][0], y - (b["min"][1] + b["max"][1]) * 0.5, origin[2])
            x -= b["size"][0] + gap
            depth = max(depth, b["size"][1])
        y -= depth + gap * 2.0
    bpy.context.view_layer.update()
    return list(ids)


def build(ids):
    for aid in ids:
        P.build(aid)
    return qa(ids)


def run(ids, save=True):
    """Build + export + manifest (+ save) with the noisy glTF exporter silenced.  Returns the QA report."""
    for aid in ids:
        P.build(aid)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        P.export(ids)
    n = P.update_manifest(ids)
    if save:
        K.save_master()
    return qa(ids) + "\nmanifest entries: %d" % n


def export_only(ids, save=True):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        P.export(ids)
    n = P.update_manifest(ids)
    if save:
        K.save_master()
    return "exported %d, manifest entries: %d" % (len(ids), n)
