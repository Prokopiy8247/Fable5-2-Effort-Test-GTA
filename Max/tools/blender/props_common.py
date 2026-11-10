"""props_common - shared helpers, asset registry, QA and manifest writer for the
props / nature / vfx generators (props_street.py, props_yard.py, props_coast.py,
props_misc.py, nature.py, vfx_meshes.py).

Runs INSIDE Blender through the Blender MCP (see tools/blender/SPEC_COMMON.md):

    import sys, importlib
    p = r"<project>/tools/blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K; importlib.reload(K)
    import props_common as P; importlib.reload(P)
    import props_street as M; importlib.reload(M)
    print(P.run(M.IDS))                 # build + export + manifest for every asset of the module

Only builds on gta_kit (never edits it).  Everything here is re-runnable.
"""
import bpy
import bmesh
import json
import math
import os
import random
from mathutils import Vector, Matrix

import gta_kit as K

MANIFEST_PATH = os.path.join(K.PROJECT, "gta", "resources", "data", "manifests", "props.json")

# spec order (SPEC_PROPS_NATURE.md) - the manifest is written in this order
SPEC_ORDER = [
    # P1 traffic, lighting, signage
    "traffic_light", "street_lamp", "street_lamp_double", "lamp_park", "sign_stop", "sign_speed", "sign_oneway",
    "sign_parking", "sign_street", "sign_hospital", "sign_airport", "barrier_jersey", "barrier_plastic",
    "barrier_police", "barrier_construction", "spike_strip", "prop_cone", "prop_bollard", "prop_bollard_light",
    "prop_boom_gate",
    # P1 street furniture
    "prop_bench", "prop_bin", "prop_dumpster", "prop_hydrant", "prop_bus_stop", "prop_mailbox", "prop_newsbox",
    "prop_vending", "prop_parking_meter", "prop_bike_rack", "prop_planter", "prop_planter_round",
    "prop_utility_box", "prop_transformer", "prop_manhole", "prop_atm", "prop_flagpole", "prop_picnic_table",
    # P1 fences and walls
    "fence_wood", "fence_picket", "fence_chain", "fence_metal", "wall_brick", "wall_concrete", "gate_chain",
    # P1 nature
    "tree_oak_a", "tree_oak_b", "tree_round", "tree_pine_a", "tree_pine_b", "tree_palm_a", "tree_palm_b",
    "tree_dead", "bush_a", "bush_b", "hedge", "rock_a", "rock_b", "rock_c", "rock_cliff", "grass_tuft",
    "grass_tall", "flower_patch", "reeds", "fern", "log", "stump", "driftwood",
    # P2 yard / industrial
    "prop_pallet", "prop_crate", "prop_crate_small", "prop_barrel", "prop_barrel_explosive", "prop_gas_tank",
    "prop_gas_tank_large", "prop_container", "prop_container_open", "prop_cable_spool", "prop_tire",
    "prop_tire_stack", "prop_pipe_stack", "prop_scaffold", "prop_generator", "prop_floodlight", "prop_ac_wall",
    "prop_ladder", "prop_stairs_metal", "prop_ramp_stunt", "prop_ramp_small", "prop_ramp_dirt",
    # P2 beach, park, pier
    "prop_umbrella", "prop_beach_chair", "prop_towel", "prop_surfboard", "prop_volleyball_net",
    "prop_lifebuoy_stand", "prop_lifeguard_tower", "prop_buoy", "prop_dock_cleat", "prop_pier_deck",
    "prop_pier_rail", "prop_dock_float", "prop_dock_ladder", "prop_kayak", "prop_windsock", "prop_runway_light",
    "prop_helipad_light",
    # P3 underwater
    "coral_a", "coral_b", "seaweed_a", "prop_anchor", "prop_treasure_chest", "wreck_boat", "wreck_car",
    # P3 activities
    "prop_target_round", "prop_target_man", "prop_checkpoint_ring", "prop_start_banner",
    # P3 vfx helper meshes
    "fx_debris_a", "fx_debris_b", "fx_debris_c", "fx_debris_metal", "fx_glass_shard", "fx_shell_casing",
    "fx_rock_chunk", "fx_plank",
]

REG = {}


# --------------------------------------------------------------------------- registry
def asset(aid, category="StreetProps", folder="props", col="bbox", dynamic=False, mass=0, notes=""):
    """Decorator: register a builder `fn(root)`.  The builder may return a dict overriding col / notes."""
    def deco(fn):
        REG[aid] = {"id": aid, "fn": fn, "category": category, "glb": "%s/%s" % (folder, aid),
                    "col": col, "dynamic": bool(dynamic), "mass": mass, "notes": notes}
        return fn
    return deco


def cyl_col(r, h, z0=0.0, x=0.0, y=0.0):
    return {"shape": "cyl", "r": round(r, 3), "h": round(h, 3), "center": [round(x, 3), round(y, 3), round(z0 + h * 0.5, 3)]}


def box_col(size, center):
    return {"shape": "box", "size": [round(v, 3) for v in size], "center": [round(v, 3) for v in center]}


HIDDEN_PARTS = ("col", "lod1", "lod2")


def _part(o, root):
    pre = root.name + "__"
    return o.name[len(pre):] if o.name.startswith(pre) else o.name


def finalize(root):
    """Hide collision / LOD helper parts in the viewport (K.export_asset un-hides them while exporting)."""
    for o in root.children_recursive:
        if o.type == "MESH" and _part(o, root) in HIDDEN_PARTS:
            if _part(o, root) == "col":
                o.display_type = "WIRE"
            try:
                o.hide_set(True)
            except RuntimeError:
                pass


def build(aid):
    spec = REG[aid]
    root = K.begin_asset(aid, spec["category"])
    extra = spec["fn"](root)
    spec["extra"] = extra if isinstance(extra, dict) else {}
    finalize(root)
    return root


def shell_report(me):
    """-> (closed shells, open shells, inside-out closed shells, zero-area faces)"""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.index_update()
    seen = set()
    closed = opened = bad = 0
    degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-9)
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        isl = []
        while stack:
            g = stack.pop()
            isl.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        if all(len(e.link_faces) == 2 for g in isl for e in g.edges):
            closed += 1
            vol = 0.0
            for g in isl:
                vs = [v.co for v in g.verts]
                for i in range(1, len(vs) - 1):
                    vol += vs[0].dot(vs[i].cross(vs[i + 1]))
            if vol < 0.0:
                bad += 1
        else:
            opened += 1
    bm.free()
    return closed, opened, bad, degenerate


def stats(root):
    if isinstance(root, str):
        root = bpy.data.objects[root]
    bpy.context.view_layer.update()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    tris = helper_tris = 0
    parts, markers = [], []
    bad = deg = 0
    origin = root.matrix_world.translation
    for o in root.children_recursive:
        part = _part(o, root)
        if o.type == "MESH":
            parts.append(part)
            o.data.calc_loop_triangles()
            n = len(o.data.loop_triangles)
            c, op, b, d = shell_report(o.data)
            bad += b
            deg += d
            if part in HIDDEN_PARTS:
                helper_tris += n
                continue
            tris += n
            mw = o.matrix_world
            for v in o.data.vertices:
                w = mw @ v.co - origin
                for i in range(3):
                    lo[i] = min(lo[i], w[i])
                    hi[i] = max(hi[i], w[i])
        elif o.type == "EMPTY":
            markers.append(part)
    return {"tris": tris, "helper_tris": helper_tris, "size": [round(hi[i] - lo[i], 3) for i in range(3)],
            "min": [round(v, 3) for v in lo], "max": [round(v, 3) for v in hi],
            "parts": parts, "markers": markers, "inverted": bad, "degenerate": deg}


def manifest_entry(aid):
    spec = REG[aid]
    st = stats(aid)
    extra = spec.get("extra") or {}
    col = extra.get("col", spec["col"])
    notes = extra.get("notes", spec["notes"])
    e = {"id": aid, "glb": spec["glb"], "category": spec["category"], "size": st["size"], "tris": st["tris"],
         "parts": st["parts"], "markers": st["markers"], "notes": notes,
         "col": col, "dynamic": spec["dynamic"], "mass": spec["mass"],
         "bbox_min": st["min"], "bbox_max": st["max"]}
    for k, v in extra.items():
        if k not in ("col", "notes"):
            e[k] = v
    return e


def update_manifest(ids):
    """Merge fresh entries for `ids` into props.json (other entries are kept), spec order."""
    data = {"assets": []}
    if os.path.exists(MANIFEST_PATH):
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    by_id = {e["id"]: e for e in data.get("assets", [])}
    for aid in ids:
        by_id[aid] = manifest_entry(aid)
    order = {a: i for i, a in enumerate(SPEC_ORDER)}
    entries = sorted(by_id.values(), key=lambda e: order.get(e["id"], 10 ** 6))
    os.makedirs(os.path.dirname(MANIFEST_PATH), exist_ok=True)
    lines = ["  " + json.dumps(e, ensure_ascii=False) for e in entries]
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        f.write('{ "assets": [\n' + ",\n".join(lines) + "\n] }\n")
    return len(entries)


def export(ids):
    out = []
    for aid in ids:
        path, size = K.export_asset(bpy.data.objects[aid], REG[aid]["glb"])
        out.append((aid, size))
    return out


def report(ids):
    lines = []
    for aid in ids:
        st = stats(aid)
        flag = ""
        if st["inverted"]:
            flag += "  !! %d inside-out shells" % st["inverted"]
        if st["degenerate"]:
            flag += "  !! %d zero-area faces" % st["degenerate"]
        lines.append("%-22s tris %4d (+%d helper)  size %s  min %s max %s  parts %s markers %s%s" % (
            aid, st["tris"], st["helper_tris"], st["size"], st["min"], st["max"], st["parts"], st["markers"], flag))
    return "\n".join(lines)


def run(ids, do_export=True, save=True):
    """Build -> (export -> manifest -> save).  Returns the stats report."""
    for aid in ids:
        build(aid)
    if do_export:
        export(ids)
        update_manifest(ids)
        if save:
            K.save_master()
    return report(ids)


def layout(sheets, row_y, x0, gap=3.0):
    """Arrange roots as contact sheets.  sheets: [(name, ids, cell_x, cell_y, cols)].
    Reading order (seen from +Y, the asset front): left -> right, front row first."""
    x = x0
    for _name, ids, cx, cy, cols in sheets:
        rows = (len(ids) + cols - 1) // cols
        for i, aid in enumerate(ids):
            o = bpy.data.objects.get(aid)
            if o is None:
                continue
            c, r = i % cols, i // cols
            o.location = (x + (cols - 1 - c) * cx, row_y + (rows - 1) * cy * 0.5 - r * cy, 0.0)
        x += cols * cx + gap
    return x


FOCUS_NAME = "zz_props_qa_focus"


def focus(asset_id=None, center=(0, 0, 0), size=(1, 1, 1), name=FOCUS_NAME):
    """QA helper: an (invisible) loose-vertex box used as a `look` target to frame a detail.
    center is relative to the asset root when asset_id is given.  Remove with unfocus()."""
    base = Vector((0, 0, 0))
    if asset_id is not None:
        base = bpy.data.objects[asset_id].matrix_world.translation.copy()
    c = base + Vector(center)
    old = bpy.data.objects.get(name)
    if old is not None:
        me_old = old.data
        bpy.data.objects.remove(old, do_unlink=True)
        if me_old is not None and me_old.users == 0:
            bpy.data.meshes.remove(me_old)
    me = bpy.data.meshes.new(name)
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    me.from_pydata([(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], [], [])
    o = bpy.data.objects.new(name, me)
    K.ensure_collection(K.CATEGORIES["VFX"][0]).objects.link(o)
    o.location = c
    return o


def unfocus(prefix=FOCUS_NAME):
    for o in list(bpy.data.objects):
        if o.name.startswith(prefix):
            me = o.data if o.type == "MESH" else None
            bpy.data.objects.remove(o, do_unlink=True)
            if me is not None and me.users == 0:
                bpy.data.meshes.remove(me)


def sheet_ids(sheets, name):
    for s in sheets:
        if s[0] == name:
            return list(s[1])
    raise KeyError(name)


# --------------------------------------------------------------------------- geometry helpers
def fpoly(mb, pts, color, toward):
    """Polygon whose normal is forced to point along `toward` (given in the current local frame of mb)."""
    f = mb.poly(pts, color)
    f.normal_update()
    t = mb.M.to_3x3() @ Vector(toward)
    if f.normal.dot(t) < 0.0:
        f.normal_flip()
    return f


def xbox(mb, size, pos=(0, 0, 0), color="gray_mid", skip=(), rot=None, base=False, colors=None):
    """Box with selectable faces (skip=('-z', '+y', ...)) - saves triangles on hidden sides."""
    sx, sy, sz = size
    hx, hy = sx * 0.5, sy * 0.5
    z0 = 0.0 if base else -sz * 0.5
    z1 = z0 + sz
    faces = {
        "+x": [(hx, -hy, z0), (hx, hy, z0), (hx, hy, z1), (hx, -hy, z1)],
        "-x": [(-hx, hy, z0), (-hx, -hy, z0), (-hx, -hy, z1), (-hx, hy, z1)],
        "+y": [(hx, hy, z0), (-hx, hy, z0), (-hx, hy, z1), (hx, hy, z1)],
        "-y": [(-hx, -hy, z0), (hx, -hy, z0), (hx, -hy, z1), (-hx, -hy, z1)],
        "+z": [(-hx, -hy, z1), (hx, -hy, z1), (hx, hy, z1), (-hx, hy, z1)],
        "-z": [(-hx, hy, z0), (hx, hy, z0), (hx, -hy, z0), (-hx, -hy, z0)],
    }
    out = []
    with mb.at(pos, rot):
        for key, pts in faces.items():
            if key in skip:
                continue
            out.append(mb.poly(pts, (colors or {}).get(key, color)))
    return out


def beam(mb, a, b, size, color, up=(0, 0, 1), skip=("+y", "-y"), extend=0.0):
    """Box-section beam from point a to point b. size=(width, height) of the section; `up` orients the height."""
    a = Vector(a)
    b = Vector(b)
    d = b - a
    ln = d.length
    if ln < 1e-6:
        return []
    yv = d / ln
    upv = Vector(up)
    xv = yv.cross(upv)
    if xv.length < 1e-5:
        xv = yv.cross(Vector((1, 0, 0)))
    xv.normalize()
    zv = xv.cross(yv).normalized()
    m = Matrix((
        (xv.x, yv.x, zv.x, (a.x + b.x) * 0.5),
        (xv.y, yv.y, zv.y, (a.y + b.y) * 0.5),
        (xv.z, yv.z, zv.z, (a.z + b.z) * 0.5),
        (0, 0, 0, 1)))
    mb.stack.append(mb.stack[-1] @ m)
    try:
        out = xbox(mb, (size[0], ln + extend * 2.0, size[1]), (0, 0, 0), color, skip=skip)
    finally:
        mb.stack.pop()
    return out


def ttube(mb, pts, radii, color="gray_mid", segs=6, smooth=False, caps=True, ring_colors=None, spin=0.0):
    """Tapered tube along a polyline (one radius per point) with a twist-free frame."""
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
    return mb.loft(rings, color, closed=True, cap_start=caps, cap_end=caps, smooth=smooth, ring_colors=ring_colors)


def lathe(mb, prof, color="gray_mid", segs=10, colors=None, color_fn=None, closed=False,
          cap0=True, cap1=True, smooth=True, break_angle=30.0, phase=0.0, cap_colors=None):
    """Revolve a (r, z) profile around the local Z axis.
    The profile must run counter-clockwise around the cross-section (bottom -> outside -> top) so the
    faces get outward normals.  colors: one per band; color_fn(band, seg) overrides.
    closed=True joins the last point to the first (torus-like).  r == 0 ends become fans, r > 0 ends n-gon caps.
    Bands meeting at more than break_angle get a hard edge."""
    m = mb.M
    flip = mb._flipped(m)
    n = len(prof)
    nb = n if closed else n - 1

    def ring(i):
        r, z = prof[i]
        if r <= 1e-6:
            return [mb.bm.verts.new(m @ Vector((0.0, 0.0, z)))]
        return [mb.bm.verts.new(m @ Vector((math.cos(phase + 2.0 * math.pi * k / segs) * r,
                                              math.sin(phase + 2.0 * math.pi * k / segs) * r, z)))
                for k in range(segs)]

    def bdir(b):
        r0, z0 = prof[b % n]
        r1, z1 = prof[(b + 1) % n]
        v = Vector((r1 - r0, z1 - z0))
        return v.normalized() if v.length > 1e-9 else Vector((0.0, 1.0))

    def soft(b0, b1):
        return smooth and math.degrees(bdir(b0).angle(bdir(b1))) < break_angle

    out = []
    prev_top = None
    first_bottom = None
    last_top = None
    for b in range(nb):
        i0, i1 = b % n, (b + 1) % n
        v0 = prev_top if (b > 0 and soft(b - 1, b)) else ring(i0)
        if closed and b == nb - 1 and soft(b, 0):
            v1 = first_bottom
        else:
            v1 = ring(i1)
        if b == 0:
            first_bottom = v0
        prev_top = v1
        last_top = v1
        band = []
        for k in range(segs):
            k2 = (k + 1) % segs
            if len(v0) == 1 and len(v1) == 1:
                continue
            if len(v0) == 1:
                vs = [v0[0], v1[k2], v1[k]]
            elif len(v1) == 1:
                vs = [v0[k], v0[k2], v1[0]]
            else:
                vs = [v0[k], v0[k2], v1[k2], v1[k]]
            if flip:
                vs.reverse()
            try:
                f = mb.bm.faces.new(vs)
            except ValueError:
                continue
            f.smooth = smooth
            if color_fn is not None:
                mb.paint([f], color_fn(b, k))
            band.append(f)
        if color_fn is None:
            mb.paint(band, colors[b] if colors and b < len(colors) and colors[b] else color)
        out += band
    if not closed:
        if cap0 and prof[0][0] > 1e-6:
            vs = list(reversed(first_bottom))
            if flip:
                vs.reverse()
            f = mb.bm.faces.new(vs)
            mb.paint([f], cap_colors[0] if cap_colors else (colors[0] if colors and colors[0] else color))
            out.append(f)
        if cap1 and prof[-1][0] > 1e-6:
            vs = list(last_top)
            if flip:
                vs.reverse()
            f = mb.bm.faces.new(vs)
            mb.paint([f], cap_colors[1] if cap_colors else (colors[nb - 1] if colors and colors[nb - 1] else color))
            out.append(f)
    return out


def disc(mb, r, pos, color, segs=10, toward=(0, 1, 0), phase=0.0, rx=None):
    """Flat n-gon facing `toward` (axis-aligned: +-X, +-Y or +-Z)."""
    t = Vector(toward)
    ax = max(range(3), key=lambda i: abs(t[i]))
    pts = []
    rx = r if rx is None else rx
    for k in range(segs):
        a = phase + 2.0 * math.pi * k / segs
        u, v = math.cos(a) * rx, math.sin(a) * r
        if ax == 1:
            p = (pos[0] + u, pos[1], pos[2] + v)
        elif ax == 0:
            p = (pos[0], pos[1] + u, pos[2] + v)
        else:
            p = (pos[0] + u, pos[1] + v, pos[2])
        pts.append(p)
    return fpoly(mb, pts, color, toward)


def qy(mb, x0, x1, z0, z1, y, color, facing=1):
    """Axis-aligned quad in the XZ plane at depth y, facing +Y (facing=1) or -Y (-1)."""
    return fpoly(mb, [(x1, y, z0), (x0, y, z0), (x0, y, z1), (x1, y, z1)], color, (0, facing, 0))


def qx(mb, y0, y1, z0, z1, x, color, facing=1):
    return fpoly(mb, [(x, y0, z0), (x, y1, z0), (x, y1, z1), (x, y0, z1)], color, (facing, 0, 0))


def qz(mb, x0, x1, y0, y1, z, color, facing=1):
    return fpoly(mb, [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], color, (0, 0, facing))


def strip2(mb, a_pts, b_pts, color, colors=None):
    """Double-sided strip of quads between two polylines."""
    out = []
    for i in range(len(a_pts) - 1):
        c = colors[i] if colors else color
        out += mb.quad(a_pts[i], a_pts[i + 1], b_pts[i + 1], b_pts[i], c, double=True)
    return out


def ribbon(mb, p0, p1, width, color, normal=(0, 1, 0), w1=None):
    """Flat double-sided ribbon from p0 to p1 lying perpendicular to `normal` (w1 = end width)."""
    p0 = Vector(p0)
    p1 = Vector(p1)
    d = p1 - p0
    if d.length < 1e-6:
        return []
    s = d.cross(Vector(normal))
    if s.length < 1e-6:
        return []
    s.normalize()
    a = s * (width * 0.5)
    b = s * ((width if w1 is None else w1) * 0.5)
    return mb.quad(p0 - a, p1 - b, p1 + b, p0 + a, color, double=True)


def blade(mb, base, tip, width, color, normal=None, mid=None, mid_w=None, color2=None):
    """Double-sided tapered grass blade (1 triangle) or, with `mid`, a bent blade (quad + tip triangle)."""
    base = Vector(base)
    tip = Vector(tip)
    d = tip - base
    if normal is None:
        s = d.cross(Vector((0, 0, 1)))
        if s.length < 1e-6:
            s = Vector((1, 0, 0))
    else:
        s = Vector(normal)
    s.normalize()
    a = s * (width * 0.5)
    out = []
    if mid is None:
        out.append(mb.poly([base - a, base + a, tip], color))
        out.append(mb.poly([tip, base + a, base - a], color))
    else:
        mid = Vector(mid)
        b = s * ((width * 0.6 if mid_w is None else mid_w) * 0.5)
        out += mb.quad(base - a, base + a, mid + b, mid - b, color, double=True)
        c2 = color2 or color
        out.append(mb.poly([mid - b, mid + b, tip], c2))
        out.append(mb.poly([tip, mid + b, mid - b], c2))
    return out


def octa(mb, r, pos, color, scale=(1, 1, 1), rot=None):
    """Octahedron 'gem' (8 tris) - flower heads, studs, small knobs."""
    out = []
    with mb.at(pos, rot, scale):
        ring = [(r, 0, 0), (0, r, 0), (-r, 0, 0), (0, -r, 0)]
        for k in range(4):
            a, b = ring[k], ring[(k + 1) % 4]
            out.append(mb.poly([a, b, (0, 0, r)], color))
            out.append(mb.poly([b, a, (0, 0, -r)], color))
    return out


def pyramid(mb, size, h, pos, color, base=False):
    """4-sided pyramid cap sitting on pos (post caps)."""
    sx, sy = size[0] * 0.5, size[1] * 0.5
    x, y, z = pos
    c = [(x - sx, y - sy, z), (x + sx, y - sy, z), (x + sx, y + sy, z), (x - sx, y + sy, z)]
    top = (x, y, z + h)
    out = [mb.poly([c[k], c[(k + 1) % 4], top], color) for k in range(4)]
    if base:
        out.append(mb.poly(list(reversed(c)), color))
    return out


def blob(mb, r, pos, color, dark=None, light=None, subdiv=2, jitter=0.18, seed=0, scale=None, rot=None,
         dark_z=-0.3, light_z=0.6, speckle=0.0):
    """Jittered ico foliage blob; faces pointing down get `dark`, faces pointing up get `light`."""
    faces = mb.ico(r, pos, color, subdiv=subdiv, jitter=jitter, seed=seed, scale=scale, rot=rot)
    rnd = random.Random(seed * 7 + 3)
    for f in faces:
        f.normal_update()
        nz = f.normal.z
        if dark and (nz < dark_z or rnd.random() < speckle):
            mb.paint([f], dark)
        elif light and nz > light_z:
            mb.paint([f], light)
    return faces


def hull_bm(points):
    tmp = bmesh.new()
    for p in points:
        tmp.verts.new(p)
    res = bmesh.ops.convex_hull(tmp, input=list(tmp.verts))
    junk = list({g for g in list(res.get("geom_interior", [])) + list(res.get("geom_unused", []))
                 if isinstance(g, bmesh.types.BMVert)})          # a vert can be listed in both -> de-duplicate
    if junk:
        bmesh.ops.delete(tmp, geom=junk, context="VERTS")
    return tmp


def _cut(tmp, co, no):
    """Cut away everything on the `no` side of the plane and cap the hole."""
    geom = list(tmp.verts) + list(tmp.edges) + list(tmp.faces)
    r = bmesh.ops.bisect_plane(tmp, geom=geom, dist=1e-5, plane_co=co, plane_no=no, clear_outer=True)
    edges = [g for g in r["geom_cut"] if isinstance(g, bmesh.types.BMEdge)]
    if edges:
        bmesh.ops.edgeloop_fill(tmp, edges=edges)


def rock(mb, size, pos=(0, 0, 0), seed=0, n=14, color="rock", dark="rock_dark", light=None, rot=None,
         cut=0.12, top_cut=0.0, lo=0.72, speckle=0.18, centered=False, points=None):
    """Faceted convex-hull rock.  size = rough bbox; cut = fraction sliced off the bottom (flat base at pos.z),
    top_cut = fraction sliced off the top (slabs).  centered=True keeps the centre at pos (debris)."""
    rnd = random.Random(seed)
    if points is None:
        points = []
        for _i in range(n):
            v = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1)))
            if v.length < 1e-6:
                v = Vector((1, 0, 0))
            v.normalize()
            rr = rnd.uniform(lo, 1.0)
            points.append((v.x * rr * size[0] * 0.5, v.y * rr * size[1] * 0.5, v.z * rr * size[2] * 0.5))
    tmp = hull_bm(points)
    zs = [v.co.z for v in tmp.verts]
    zmin, zmax = min(zs), max(zs)
    zc = zmin
    if cut > 0.0 and not centered:
        zc = zmin + (zmax - zmin) * cut
        _cut(tmp, (0, 0, zc), (0, 0, -1))
    if top_cut > 0.0:
        _cut(tmp, (0, 0, zmax - (zmax - zmin) * top_cut), (0, 0, 1))
    if not centered:
        for v in tmp.verts:
            v.co.z -= zc
    bmesh.ops.recalc_face_normals(tmp, faces=list(tmp.faces))
    m = mb.M @ Matrix.Translation(Vector(pos)) @ K._rot_matrix(rot)
    merged = mb._merge(tmp, m)
    faces = [f for f, _n in merged]
    mb.paint(faces, color)
    for f in faces:
        f.normal_update()
        nz = f.normal.z
        if light and nz > 0.7:
            mb.paint([f], light)
        elif dark and (nz < -0.15 or rnd.random() < speckle):
            mb.paint([f], dark)
    return faces


def grid_box(mb, size, pos=(0, 0, 0), color="@F:leaf_green", dark=None, light=None, segs=(4, 2, 2),
             jitter=0.05, seed=0, speckle=0.15, tri=True, top_jitter=None):
    """Subdivided, jittered box sitting on pos (clipped hedges, soil, cushions)."""
    nx, ny, nz = segs
    rnd = random.Random(seed)
    tmp = bmesh.new()
    vm = {}

    def V(i, j, k):
        key = (i, j, k)
        v = vm.get(key)
        if v is None:
            p = Vector(((i / nx - 0.5) * size[0], (j / ny - 0.5) * size[1], (k / nz) * size[2]))
            if k > 0:
                jz = jitter if top_jitter is None or k < nz else top_jitter
                p += Vector((rnd.uniform(-jitter, jitter), rnd.uniform(-jitter, jitter), rnd.uniform(-jz, jz)))
            v = tmp.verts.new(p)
            vm[key] = v
        return v

    for i in range(nx):
        for j in range(ny):
            tmp.faces.new([V(i, j, 0), V(i, j + 1, 0), V(i + 1, j + 1, 0), V(i + 1, j, 0)])
            tmp.faces.new([V(i, j, nz), V(i + 1, j, nz), V(i + 1, j + 1, nz), V(i, j + 1, nz)])
    for i in range(nx):
        for k in range(nz):
            tmp.faces.new([V(i, 0, k), V(i + 1, 0, k), V(i + 1, 0, k + 1), V(i, 0, k + 1)])
            tmp.faces.new([V(i, ny, k), V(i, ny, k + 1), V(i + 1, ny, k + 1), V(i + 1, ny, k)])
    for j in range(ny):
        for k in range(nz):
            tmp.faces.new([V(0, j, k), V(0, j, k + 1), V(0, j + 1, k + 1), V(0, j + 1, k)])
            tmp.faces.new([V(nx, j, k), V(nx, j + 1, k), V(nx, j + 1, k + 1), V(nx, j, k + 1)])
    if tri:
        bmesh.ops.triangulate(tmp, faces=list(tmp.faces))
    bmesh.ops.recalc_face_normals(tmp, faces=list(tmp.faces))
    merged = mb._merge(tmp, mb.M @ Matrix.Translation(Vector(pos)))
    faces = [f for f, _n in merged]
    mb.paint(faces, color)
    for f in faces:
        f.normal_update()
        nzv = f.normal.z
        if light and nzv > 0.6:
            mb.paint([f], light)
        elif dark and (nzv < -0.5 or rnd.random() < speckle):
            mb.paint([f], dark)
    return faces


def _clip_x(poly, xmin, xmax):
    def clip(pts, edge, keep_greater):
        out = []
        for i in range(len(pts)):
            a = pts[i]
            b = pts[(i + 1) % len(pts)]
            ia = (a[0] >= edge) if keep_greater else (a[0] <= edge)
            ib = (b[0] >= edge) if keep_greater else (b[0] <= edge)
            if ia:
                out.append(a)
            if ia != ib:
                t = (edge - a[0]) / (b[0] - a[0])
                out.append((edge, a[1] + (b[1] - a[1]) * t))
        return out
    p = clip(list(poly), xmin, True)
    if len(p) >= 3:
        p = clip(p, xmax, False)
    return p


def _area2(poly):
    s = 0.0
    for i in range(len(poly)):
        a = poly[i]
        b = poly[(i + 1) % len(poly)]
        s += a[0] * b[1] - b[0] * a[1]
    return abs(s) * 0.5


def _signed_area(poly):
    s = 0.0
    for i in range(len(poly)):
        a = poly[i]
        b = poly[(i + 1) % len(poly)]
        s += a[0] * b[1] - b[0] * a[1]
    return s * 0.5


def striped_board(mb, length, height, thick, pos=(0, 0, 0), colors=("white", "orange"), stripe=0.2, slant=0.15,
                  rot=None, phase=0.0, solid=False, sides=("+y", "-y"), lift=0.006):
    """Board in the local XZ plane (thickness along Y) with diagonal colour stripes.
    solid=True : every stripe is its own prism (12 tris per stripe).
    solid=False: one box in colors[0] + flat colors[1] stripe polygons floating `lift` above the listed
                 faces (2 tris per stripe and side) - the cheap default."""
    x0, x1 = -length * 0.5, length * 0.5
    z0, z1 = -height * 0.5, height * 0.5
    out = []
    with mb.at(pos, rot):
        if not solid:
            mb.box((length, thick, height), (0, 0, 0), colors[0])
        a = x0 - abs(slant) - stripe * 2.0 + phase
        k = 0
        while a < x1 + abs(slant) + stripe:
            poly = [(a, z0), (a + stripe, z0), (a + stripe + slant, z1), (a + slant, z1)]
            poly = _clip_x(poly, x0, x1)
            clean = []
            for p in poly:
                if not clean or (abs(p[0] - clean[-1][0]) + abs(p[1] - clean[-1][1])) > 1e-6:
                    clean.append(p)
            if len(clean) > 2 and (abs(clean[0][0] - clean[-1][0]) + abs(clean[0][1] - clean[-1][1])) < 1e-6:
                clean.pop()
            if len(clean) >= 3 and _area2(clean) > 1e-6:
                if solid:
                    out.append(mb.prism(clean, thick, colors[k % len(colors)], plane="XZ"))
                elif k % 2 == 1:
                    if _signed_area(clean) < 0.0:
                        clean.reverse()
                    # counter-clockwise in (x, z) faces -Y; reversed faces +Y
                    if "+y" in sides:
                        y = thick * 0.5 + lift
                        out.append(mb.poly([(p[0], y, p[1]) for p in reversed(clean)], colors[1]))
                    if "-y" in sides:
                        y = -thick * 0.5 - lift
                        out.append(mb.poly([(p[0], y, p[1]) for p in clean], colors[1]))
            a += stripe
            k += 1
    return out


_TEXT_BB = {}


def text_bounds(s, spacing=1.0):
    key = (s, spacing)
    if key not in _TEXT_BB:
        t = K.MB()
        K.add_text(t, s, size=1.0, depth=0.0, color="white", res=1, spacing=spacing)
        xs = [v.co.x for v in t.bm.verts]
        zs = [v.co.z for v in t.bm.verts]
        _TEXT_BB[key] = (min(xs), max(xs), min(zs), max(zs))
        t.bm.free()
    return _TEXT_BB[key]


def text(mb, s, pos, width=None, height=None, color="white", depth=0.01, res=1, rot=None, spacing=1.0):
    """3D lettering centred on `pos` (x and z), readable from +Y (use rot=(0,0,180) for -Y, (0,0,-90) for +X).
    Fits the string into width and/or height.  depth=0 -> flat single-sided glyphs."""
    x0, x1, z0, z1 = text_bounds(s, spacing)
    w, h = x1 - x0, z1 - z0
    if width is not None and height is not None:
        size = min(width / w, height / h)
    elif width is not None:
        size = width / w
    else:
        size = height / h
    with mb.at(pos, rot):
        return K.add_text(mb, s, size=size, depth=depth, color=color, res=res, spacing=spacing,
                          pos=(-(x0 + x1) * 0.5 * size, 0.0, -(z0 + z1) * 0.5 * size))


def arc3(center, r, a0, a1, n, plane="XZ"):
    """3D arc points (degrees) in a principal plane through `center`."""
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        u, v = math.cos(a) * r, math.sin(a) * r
        if plane == "XZ":
            out.append((center[0] + u, center[1], center[2] + v))
        elif plane == "YZ":
            out.append((center[0], center[1] + u, center[2] + v))
        else:
            out.append((center[0] + u, center[1] + v, center[2]))
    return out


def visor(mb, cx, y0, cz, r, depth, color, segs=5, a0=-10.0, a1=190.0, droop=0.0):
    """Open half-pipe hood over a signal lens (double-sided), opening toward +Y."""
    back = arc3((cx, y0, cz), r, a0, a1, segs, "XZ")
    front = []
    for i, p in enumerate(back):
        t = abs(i / segs - 0.5) * 2.0                 # 0 at the crown, 1 at the lower ends
        front.append((p[0], y0 + depth * (1.0 - 0.55 * t), p[2] - droop))
    return strip2(mb, back, front, color)


def rrect(w, h, c, cx=0.0, cy=0.0):
    """Rectangle outline with chamfered corners (8 points, counter-clockwise)."""
    x, y = w * 0.5, h * 0.5
    return [(cx + x - c, cy - y), (cx + x, cy - y + c), (cx + x, cy + y - c), (cx + x - c, cy + y),
            (cx - x + c, cy + y), (cx - x, cy + y - c), (cx - x, cy - y + c), (cx - x + c, cy - y)]


def ngon(r, n, cx=0.0, cy=0.0, phase=0.0, ry=None):
    ry = r if ry is None else ry
    return [(cx + math.cos(phase + 2.0 * math.pi * k / n) * r, cy + math.sin(phase + 2.0 * math.pi * k / n) * ry)
            for k in range(n)]


def plate(mb, pts2d, y0, thick, color, back=None, plane="XZ"):
    """Flat plate from a 2D outline: spans y0 .. y0+thick (plane XZ), front (+Y) = color, back = `back`."""
    pos = (0, y0, 0) if plane == "XZ" else ((y0, 0, 0) if plane == "YZ" else (0, 0, y0))
    return mb.prism(pts2d, thick, color, plane=plane, pos=pos, center=False, cap_colors=(back or color, color))


def col_part(root, builder):
    """Create the hidden `col` part (simple triangle-mesh collider) from builder(mb)."""
    mb = K.MB()
    builder(mb)
    o = mb.to_object(root, "col")
    return o
