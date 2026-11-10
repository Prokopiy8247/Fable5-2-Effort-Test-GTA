"""bld_common - shared helpers for the NEON TIDE modular building kits (bld_*.py modules).

Facade contract (SPEC_BUILDINGS.md): module spans X [-W/2, W/2], Z [0, H], wall plane Y = 0, outside = +Y.
All helpers below emit ONLY outward/visible faces (no backs, no hidden caps) with explicit winding.
"""
import bpy
import bmesh
import json
import os
from mathutils import Vector
import gta_kit as K

CAT = "Buildings"
MANIFEST = os.path.join(K.PROJECT, "gta", "resources", "data", "manifests", "buildings.json")
GD = -0.12          # glass plane (recess depth)


# ----------------------------------------------------------------------------- asset bookkeeping
def begin(aid, W=None, H=None, glb=None, notes="", spacing=None):
    sp = spacing if spacing is not None else ((W or 4.0) + 2.5)
    root = K.begin_asset(aid, CAT, sp)
    root["gta_glb"] = glb or ("buildings/" + aid)
    root["gta_notes"] = notes
    if W is not None:
        root["gta_w"] = float(W)
    if H is not None:
        root["gta_h"] = float(H)
    return root


def lod_obj(mb, root):
    """Create the `lod1` part; hidden in the viewport so it never z-fights with `mesh` in previews
    (K.export_asset un-hides it for the export)."""
    o = mb.to_object(root, "lod1")
    try:
        o.hide_set(True)
    except Exception:
        pass
    return o


def show_lod(ids, lod=True):
    """Preview toggle: show lod1 (hide mesh) or the reverse."""
    for aid in ids:
        for o in bpy.data.objects[aid].children:
            if o.type == "MESH":
                is_lod = o.name.endswith("__lod1")
                try:
                    o.hide_set(is_lod != lod if (is_lod or o.name.endswith("__mesh")) else False)
                except Exception:
                    pass


def part_tris(root):
    out = {}
    for o in root.children:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            out[o.name.split("__", 1)[1]] = len(o.data.loop_triangles)
    return out


def stats(ids):
    lines = []
    for aid in ids:
        root = bpy.data.objects[aid]
        st = K.asset_stats(root)
        lines.append("%-20s %s size=%s min=%s max=%s" % (aid, part_tris(root), st["size"], st["min"], st["max"]))
    return "\n".join(lines)


def check(ids, max_tris=350, max_lod=12):
    """Facade contract check: bounds, tri budgets, @Window quads facing +Y."""
    warn = []
    for aid in ids:
        root = bpy.data.objects[aid]
        W = root.get("gta_w")
        H = root.get("gta_h")
        pt = part_tris(root)
        if pt.get("mesh", 0) > max_tris:
            warn.append("%s mesh tris %d > %d" % (aid, pt["mesh"], max_tris))
        if "lod1" in pt and pt["lod1"] > max_lod:
            warn.append("%s lod1 tris %d > %d" % (aid, pt["lod1"], max_lod))
        for o in root.children:
            if o.type != "MESH":
                continue
            me = o.data
            for v in me.vertices:
                c = v.co + o.location
                if W is not None and abs(c.x) > W / 2 + 1e-4:
                    warn.append("%s %s x out of module: %.3f" % (aid, o.name, c.x))
                    break
                if H is not None and (c.z < -1e-4 or c.z > H + 1e-4):
                    warn.append("%s %s z out of module: %.3f" % (aid, o.name, c.z))
                    break
            wi = [i for i, m in enumerate(me.materials) if m and m.name == "Window"]
            for p in me.polygons:
                if p.material_index in wi:
                    if len(p.vertices) != 4:
                        warn.append("%s window face is not a quad" % aid)
                    if o.name.endswith("__lod1") and abs(p.center.y) > 1e-4:
                        warn.append("%s lod1 window not at Y=0" % aid)
            for p in me.polygons:
                if p.area < 1e-7:
                    warn.append("%s %s zero-area face" % (aid, o.name))
                    break
    return warn or ["contract OK (%d assets)" % len(ids)]


def manifest_update(entries):
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    data = {"assets": []}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, "r", encoding="utf-8") as f:
            data = json.load(f)
    idx = {a["id"]: i for i, a in enumerate(data["assets"])}
    for e in entries:
        if e["id"] in idx:
            data["assets"][idx[e["id"]]] = e
        else:
            idx[e["id"]] = len(data["assets"])
            data["assets"].append(e)
    body = ",\n".join("    " + json.dumps(a) for a in data["assets"])
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write('{\n  "assets": [\n' + body + '\n  ]\n}\n')
    return len(data["assets"])


def export(ids, save=True):
    """Export every asset as GLB, update the manifest, optionally save the master file."""
    entries, lines = [], []
    for aid in ids:
        root = bpy.data.objects[aid]
        st = K.asset_stats(root)
        pt = part_tris(root)
        # kit workaround: Blender 5.2's glTF exporter raises KeyError('loglevel') when export_loglevel >= 0
        import io
        import contextlib
        with contextlib.redirect_stdout(io.StringIO()):      # the exporter logs at INFO level with -1
            path, size = K.export_asset(root, root["gta_glb"], extra={"export_loglevel": -1})
        e = {"id": aid, "glb": root["gta_glb"], "category": CAT, "size": [round(v, 3) for v in st["size"]],
             "tris": pt.get("mesh", st["tris"]),
             "parts": [o.name.split("__", 1)[1] for o in root.children if o.type == "MESH"],
             "markers": [o.name.split("__", 1)[1] for o in root.children if o.type == "EMPTY"],
             "notes": root.get("gta_notes", "")}
        if "lod1" in pt:
            e["lod1_tris"] = pt["lod1"]
        if root.get("gta_w") is not None:
            e["module"] = [root["gta_w"], root.get("gta_h", 0.0)]
        entries.append(e)
        lines.append("%-20s tris=%s size=%s glb=%dB" % (aid, pt, e["size"], size))
    n = manifest_update(entries)
    if save:
        K.save_master()
    lines.append("manifest: %d assets" % n)
    return "\n".join(lines)


# ----------------------------------------------------------------------------- face helpers
def _newell(pts):
    n = Vector((0.0, 0.0, 0.0))
    for i in range(len(pts)):
        a = Vector(pts[i])
        b = Vector(pts[(i + 1) % len(pts)])
        n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
    return n


def fq(mb, pts, color, n):
    """Polygon from 3D points, wound so its normal points along n. Degenerate faces are skipped."""
    out = []
    for p in pts:
        if not out or (Vector(p) - Vector(out[-1])).length > 1e-6:
            out.append(tuple(p))
    if len(out) > 1 and (Vector(out[0]) - Vector(out[-1])).length < 1e-6:
        out.pop()
    if len(out) < 3:
        return None
    nn = _newell(out)
    if nn.length < 1e-7:
        return None
    if nn.dot(Vector(n)) < 0:
        out.reverse()
    return mb.poly(out, color)


def q(mb, x0, x1, z0, z1, color, y=0.0):
    """Flat quad facing +Y. Vertex order BL, BR, TR, TL as seen from outside (UV 0..1 for @Window)."""
    if x1 < x0:
        x0, x1 = x1, x0
    return mb.quad((x1, y, z0), (x0, y, z0), (x0, y, z1), (x1, y, z1), color)


def pane(mb, x0, x1, z0, z1, y=GD):
    return q(mb, x0, x1, z0, z1, "@Window", y)


def wall(mb, x0, x1, z0, z1, hole=None, color="tint_a", y=0.0):
    """Wall rectangle facing +Y; with hole=(hx0,hx1,hz0,hz1) -> 4 mitred quads (no T-junctions)."""
    if hole is None:
        return q(mb, x0, x1, z0, z1, color, y)
    a, b, c, d = hole
    N = (0, 1, 0)
    fq(mb, [(x1, y, z0), (x0, y, z0), (a, y, c), (b, y, c)], color, N)
    fq(mb, [(x0, y, z0), (x0, y, z1), (a, y, d), (a, y, c)], color, N)
    fq(mb, [(x0, y, z1), (x1, y, z1), (b, y, d), (a, y, d)], color, N)
    fq(mb, [(x1, y, z1), (x1, y, z0), (b, y, c), (b, y, d)], color, N)


def reveal(mb, a, b, c, d, color="tint_a", y0=0.0, y1=GD, sides="lrtb", colors=None):
    """Inward-facing faces of an opening x a..b, z c..d running from y0 (front) back to y1."""
    col = lambda k: (colors or {}).get(k, color)
    if "b" in sides:
        fq(mb, [(a, y0, c), (b, y0, c), (b, y1, c), (a, y1, c)], col("b"), (0, 0, 1))
    if "t" in sides:
        fq(mb, [(a, y0, d), (b, y0, d), (b, y1, d), (a, y1, d)], col("t"), (0, 0, -1))
    if "r" in sides:
        fq(mb, [(a, y0, c), (a, y1, c), (a, y1, d), (a, y0, d)], col("r"), (1, 0, 0))
    if "l" in sides:
        fq(mb, [(b, y0, c), (b, y1, c), (b, y1, d), (b, y0, d)], col("l"), (-1, 0, 0))


def fbox(mb, x0, x1, y0, y1, z0, z1, color, skip="-y", colors=None):
    """Axis-aligned box from explicit extents; faces named in `skip` are omitted (default: back)."""
    F = {"+x": ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0)),
         "-x": ([(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)], (-1, 0, 0)),
         "+y": ([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0)),
         "-y": ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0)),
         "+z": ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1)),
         "-z": ([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], (0, 0, -1))}
    sk = skip.split()
    for k, (pts, n) in F.items():
        if k not in sk:
            fq(mb, pts, (colors or {}).get(k, color), n)


def cbox(mb, x0, x1, y0, y1, z0, z1, color, c=0.02, ends=True, skip=("back",), cap_color=None):
    """Box (long axis X) with chamfered front-top and front-bottom edges. skip: back/bottom/top."""
    c = max(0.001, min(c, (z1 - z0) * 0.5 - 0.001, (y1 - y0) - 0.001))
    pts = [(y0, z0), (y1 - c, z0), (y1, z0 + c), (y1, z1 - c), (y1 - c, z1), (y0, z1)]
    out = mb.prism(pts, x1 - x0, color, plane="YZ", pos=((x0 + x1) * 0.5, 0, 0), caps=(ends, ends),
                   cap_colors=((cap_color, cap_color) if cap_color else None))
    idx = {"bottom": 0, "top": 4, "back": 5}
    dead = [out["sides"][idx[s]] for s in skip]
    if dead:
        bmesh.ops.delete(mb.bm, geom=dead, context="FACES")
    return out


def panel(mb, x0, x1, z0, z1, color="tint_a", t=0.03, c=0.04, y=0.0):
    """Raised 'pillow' panel: front face at y+t and 4 chamfer faces down to y (reads as V-joints)."""
    a, b, cc, d = x0 + c, x1 - c, z0 + c, z1 - c
    fq(mb, [(x1, y, z0), (x0, y, z0), (a, y + t, cc), (b, y + t, cc)], color, (0, 1, -1))
    fq(mb, [(x0, y, z0), (x0, y, z1), (a, y + t, d), (a, y + t, cc)], color, (-1, 1, 0))
    fq(mb, [(x0, y, z1), (x1, y, z1), (b, y + t, d), (a, y + t, d)], color, (0, 1, 1))
    fq(mb, [(x1, y, z1), (x1, y, z0), (b, y + t, cc), (b, y + t, d)], color, (1, 1, 0))
    q(mb, a, b, cc, d, color, y + t)
