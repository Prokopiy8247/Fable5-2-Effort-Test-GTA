# -*- coding: utf-8 -*-
"""animals - NEON TIDE: Vesper Bay wildlife (tools/blender/SPEC_CHARACTERS.md, section 5 "Animals").

Rigid-part animals (no armature): Godot (gta/code/ai/wildlife_manager.gd) rotates the parts about their origins.
Run inside Blender through the MCP:

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K; importlib.reload(K)
    import props_common as P; importlib.reload(P)
    import animals as A; importlib.reload(A)
    print(A.run())                      # build + export every animal, write animals.json, save the .blend
    print(A.build(["dog"]))             # rebuild one while iterating (no export)
    A.pose("dog"); A.pose("dog", False) # QA: bend head / legs / tail about their pivots, then reset

Contract: front = +Y, feet on z = 0, origin under the body centre (fish + shark: origin at the body centre).
Parts are separate objects `<id>__<part>` parented to the root with identity rotation, origin at the joint:
  head  = head + neck, origin at the neck base        -> Godot rotates about X (nod / graze)
  leg_* = origin at shoulder / hip, legs hang down    -> about X (swing fore / aft)
  tail  = origin at the tail base                     -> about Godot Y = Blender Z (wag / swim)
  wing_l / wing_r = origin at the wing root, flat spread toward -X / +X -> about Godot Z (flap)
Only builds on gta_kit / props_common (never edits them). Re-runnable.
"""
import contextlib
import io
import json
import math
import os

import bpy
import bmesh
from mathutils import Vector

import gta_kit as K
import props_common as P

IDS = ["seagull", "fish", "fish_b", "dog", "cat", "deer", "rabbit", "coyote", "shark"]
CATEGORY = "Animals"
MANIFEST = os.path.join(K.PROJECT, "gta", "resources", "data", "manifests", "animals.json")
PART_ORDER = ["body", "head", "leg_fl", "leg_fr", "leg_rl", "leg_rr", "tail", "wing_l", "wing_r"]
# palette cells this module needs that the shared palette did not have yet (append-only)
NEW_COLORS = [
    ["fur_ginger", "#d8843c", 0.95, 0.0, 0.0, ""],
    ["fur_ginger_dark", "#a2562a", 0.95, 0.0, 0.0, ""],
]
REG = {}


def animal(aid, notes="", spec=None):
    def deco(fn):
        REG[aid] = {"id": aid, "fn": fn, "glb": "animals/" + aid, "notes": notes, "spec": spec or {}}
        return fn
    return deco


# =========================================================================== palette
def ensure_palette():
    """Append NEW_COLORS to palette.json if missing (keeps the file's one-entry-per-line format)."""
    with open(K.PALETTE_JSON, "r", encoding="utf-8") as f:
        data = json.load(f)
    have = {c[0] for c in data["colors"]}
    add = [c for c in NEW_COLORS if c[0] not in have]
    if add:
        data["colors"] += add
        lines = ['{', '  "_comment": %s,' % json.dumps(data["_comment"], ensure_ascii=False),
                 '  "size": %d,' % data["size"], '  "colors": [']
        lines.append(",\n".join("    " + json.dumps(c, ensure_ascii=False) for c in data["colors"]))
        lines += ['  ]', '}']
        with open(K.PALETTE_JSON, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    if add or any(c[0] not in K.palette()["index"] for c in NEW_COLORS):
        K.reload_palette()
    return [c[0] for c in add]


# =========================================================================== geometry helpers
def _v3(p, x):
    return Vector((x, p[0], p[1])) if len(p) == 2 else Vector(p)


def _apply_colors(mb, faces, color, band_of=None, bands=None, rules=None):
    mb.paint(faces, color)
    for f in faces:
        if not f.is_valid:
            continue
        b = band_of.get(f, -1) if band_of else -1
        col = None
        if bands and 0 <= b < len(bands) and bands[b]:
            col = bands[b]
        elif rules:
            f.normal_update()
            c = f.calc_center_median()
            for pred, rc in rules:
                if pred(c, f.normal, b):
                    col = rc
                    break
        if col:
            mb.paint([f], col)


def sweep(mb, pts, secs, color, segs=8, phase=0.0, start="flat", end="flat", tips=(0.0, 0.0), bands=None,
          rules=None, x=0.0):
    """Loft elliptical sections along a polyline lying in a plane parallel to YZ (bodies, necks, legs, tails).
    pts : [(y, z)] at x=`x`, or [(x, y, z)].
    secs: per point (rx, rn) | (rx, rn_up, rn_dn) | (rx, rn_up, rn_dn, offset); rx = half width along X,
          rn_up / rn_dn = extent along +n / -n where n = path tangent turned +90 deg about X (path toward +Y ->
          n = +Z, path going down -> n = +Y); offset shifts the section centre along n.
    start / end: 'flat' n-gon cap, 'point' fan to a tip `tips[i]` metres beyond the end point, None = open.
    bands: colour per band (len(pts) - 1, None = keep); rules: [(pred(centre, normal, band), colour)].
    Faces are built with outward winding (no normal recalculation needed, works for open shells too)."""
    V = [_v3(p, x) for p in pts]
    n_pts = len(V)
    tans = []
    for i in range(n_pts):
        if i == 0:
            d = V[1] - V[0]
        elif i == n_pts - 1:
            d = V[-1] - V[-2]
        else:
            a = V[i + 1] - V[i]
            b = V[i] - V[i - 1]
            a.x = b.x = 0.0
            d = a.normalized() + b.normalized()
        d.x = 0.0
        if d.length < 1e-9:
            d = Vector((0.0, 1.0, 0.0))
        tans.append(d.normalized())
    m = mb.M
    flip = mb._flipped(m)
    X = Vector((1.0, 0.0, 0.0))
    rings, centres = [], []
    for i in range(n_pts):
        t = tans[i]
        nv = Vector((0.0, -t.z, t.y))
        s = secs[i]
        rx, ru = s[0], s[1]
        rd = s[2] if len(s) > 2 else s[1]
        off = s[3] if len(s) > 3 else 0.0
        k = 1.0
        if 0 < i < n_pts - 1:
            e1 = V[i] - V[i - 1]
            e1.x = 0.0
            if e1.length > 1e-9:
                k = 1.0 / max(0.6, t.dot(e1.normalized()))
        c0 = V[i] + nv * off
        centres.append((c0, t, nv))
        ring = []
        for j in range(segs):
            a = phase + 2.0 * math.pi * j / segs
            u, v = math.cos(a), math.sin(a)
            p = c0 + X * (u * rx) + nv * (v * (ru if v >= 0.0 else rd) * k)
            ring.append(mb.bm.verts.new(m @ p))
        rings.append(ring)
    faces = []
    band_of = {}

    def face(vs, band):
        if flip:
            vs = list(reversed(vs))
        try:
            f = mb.bm.faces.new(vs)
        except ValueError:
            return None
        faces.append(f)
        band_of[f] = band
        return f

    for i in range(n_pts - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(segs):
            j2 = (j + 1) % segs
            face([a[j], b[j], b[j2], a[j2]], i)
    # caps: ring order has normal -t (start); reversed = +t (end)
    if start == "flat":
        face(list(rings[0]), -1)
    elif start == "point":
        c0, t, _nv = centres[0]
        q = mb.bm.verts.new(m @ (c0 - t * tips[0]))
        r = rings[0]
        for j in range(segs):
            face([q, r[j], r[(j + 1) % segs]], -1)
    if end == "flat":
        face(list(reversed(rings[-1])), -1)
    elif end == "point":
        c0, t, _nv = centres[-1]
        q = mb.bm.verts.new(m @ (c0 + t * tips[1]))
        r = rings[-1]
        for j in range(segs):
            face([q, r[(j + 1) % segs], r[j]], -1)
    _apply_colors(mb, faces, color, band_of, bands, rules)
    return faces


def _area2(pts):
    a = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        a += x0 * y1 - x1 * y0
    return a * 0.5


def _inset(pts, d):
    """Inset a CCW 2D polygon by d (mitre joins, clamped)."""
    n = len(pts)
    out = []
    for i in range(n):
        p0 = Vector(pts[i - 1])
        p1 = Vector(pts[i])
        p2 = Vector(pts[(i + 1) % n])
        e1 = (p1 - p0).normalized()
        e2 = (p2 - p1).normalized()
        n1 = Vector((-e1.y, e1.x))
        n2 = Vector((-e2.y, e2.x))
        den = max(0.35, 1.0 + n1.dot(n2))
        off = (n1 + n2) * (d / den)
        out.append((p1.x + off.x, p1.y + off.y))
    return out


def _to3(plane, u, v, d):
    if plane == "YZ":
        return (d, u, v)
    if plane == "XZ":
        return (u, d, v)
    return (u, v, d)


def fin(mb, pts, thick, color, plane="YZ", pos=(0, 0, 0), rot=None, inset=None, side_colors=None, rules=None):
    """Lens-section plate (sharp outline edge, `thick` in the middle): fins, ears, beaks, wings.
    pts = 2D outline in `plane` (YZ -> (y, z) thickness along X, XZ -> (x, z) along Y, XY -> (x, y) along Z).
    side_colors = (colour of the -d face, colour of the +d face)."""
    pts = [(float(p[0]), float(p[1])) for p in pts]
    if _area2(pts) < 0.0:
        pts.reverse()
    h = thick * 0.5
    ins = _inset(pts, inset if inset is not None else h * 1.2)
    with mb.at(pos, rot):
        rings = [[_to3(plane, p[0], p[1], -h) for p in ins], [_to3(plane, p[0], p[1], 0.0) for p in pts],
                 [_to3(plane, p[0], p[1], h) for p in ins]]
        faces = mb.loft(rings, color, closed=True, cap_start=True, cap_end=True)
        if side_colors:
            cap0, cap1 = faces[-2], faces[-1]
            # faces[-2] = start cap (-d side), faces[-1] = end cap (+d side); bands: first half -d, second +d
            n = len(pts)
            for f in faces[:n] + [cap0]:
                if side_colors[0]:
                    mb.paint([f], side_colors[0])
            for f in faces[n:2 * n] + [cap1]:
                if side_colors[1]:
                    mb.paint([f], side_colors[1])
    if rules:
        for f in faces:
            f.normal_update()
            c = f.calc_center_median()
            for pred, rc in rules:
                if pred(c, f.normal, -1):
                    mb.paint([f], rc)
                    break
    return faces


def hull(mb, pts, color, rules=None):
    """Convex hull of points (paws, hooves, beaks, noses)."""
    tmp = P.hull_bm([Vector(p) for p in pts])
    bmesh.ops.recalc_face_normals(tmp, faces=list(tmp.faces))
    faces = [f for f, _n in mb._merge(tmp, mb.M)]
    _apply_colors(mb, faces, color, rules=rules)
    return faces


def eye(mb, r, pos, color="black", scale=(1.0, 1.0, 1.0)):
    return P.octa(mb, r, pos, color, scale=scale)


def paw(mb, x, y, w, l, h, color, z=0.0):
    """Chunky paw block standing on z (12 tris)."""
    return mb.box((w, l, h), (x, y, z), color, base=True, taper=(0.82, 0.72))


# colour rules (pred(centre, normal, band))
def down(lim=-0.45):
    return lambda c, n, b: n.z < lim


def up(lim=0.45):
    return lambda c, n, b: n.z > lim


# =========================================================================== registry / build / QA
def _part_origin(o):
    return [round(v, 4) for v in o.location]


def build(ids=None):
    ensure_palette()
    ids = IDS if ids is None else ([ids] if isinstance(ids, str) else ids)
    out = []
    for aid in ids:
        root = K.begin_asset(aid, CATEGORY)
        REG[aid]["fn"](root)
        out.append(stats_line(aid))
    return "\n".join(out)


def parts_of(aid):
    root = bpy.data.objects[aid]
    res = {}
    for o in root.children:
        short = o.name.split("__", 1)[1] if "__" in o.name else o.name
        res[short] = o
    return res


def stats_line(aid):
    st = P.stats(aid)
    parts = parts_of(aid)
    body = parts.get("body")
    flag = ""
    if st["inverted"]:
        flag += " !!inverted=%d" % st["inverted"]
    if st["degenerate"]:
        flag += " !!degenerate=%d" % st["degenerate"]
    names = sorted(parts, key=lambda p: PART_ORDER.index(p) if p in PART_ORDER else 99)
    po = " ".join("%s%s" % (p, tuple(round(v, 3) for v in parts[p].location)) for p in names)
    bz = ""
    if body is not None and body.type == "MESH":
        zs = [v.co.z for v in body.data.vertices]
        bz = " body_top=%.3f" % max(zs)
    return "%-8s tris=%4d size=%s%s%s | %s" % (aid, st["tris"], st["size"], bz, flag, po)


POSE = {
    # part: Blender euler (x, y, z) in radians for the QA pose (Godot X = Blender X, Godot Y = Blender Z,
    # Godot Z = Blender -Y)
    "head": (-0.6, 0.0, 0.35),
    "leg_fl": (0.6, 0.0, 0.0), "leg_fr": (-0.6, 0.0, 0.0), "leg_rl": (-0.6, 0.0, 0.0), "leg_rr": (0.6, 0.0, 0.0),
    "tail": (0.0, 0.0, 0.45),
    "wing_l": (0.0, 0.6, 0.0), "wing_r": (0.0, -0.6, 0.0),
}


def pose(aid, on=True):
    for name, o in parts_of(aid).items():
        if name in POSE:
            o.rotation_euler = POSE[name] if on else (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    return aid + (" posed" if on else " reset")


# =========================================================================== export / manifest
def export(ids=None):
    ids = IDS if ids is None else ([ids] if isinstance(ids, str) else ids)
    out = []
    for aid in ids:
        with contextlib.redirect_stdout(io.StringIO()):
            path, size = K.export_asset(bpy.data.objects[aid], REG[aid]["glb"], extra={"export_loglevel": -1})
        out.append("%s %d B" % (aid, size))
    return ", ".join(out)


def describe(aid):
    root = bpy.data.objects[aid]
    st = P.stats(aid)
    parts = parts_of(aid)
    names = sorted([p for p, o in parts.items() if o.type == "MESH"],
                   key=lambda p: PART_ORDER.index(p) if p in PART_ORDER else 99)
    info = REG[aid]
    e = {"id": aid, "glb": info["glb"], "category": CATEGORY, "size": st["size"], "tris": st["tris"],
         "parts": names, "part_origins": {p: _part_origin(parts[p]) for p in names}}
    # measured key dimensions (spec targets in "spec")
    e["length"] = st["size"][1]
    if "shoulder" in info["spec"]:
        e["shoulder"] = round(max(v.co.z for v in parts["body"].data.vertices), 3)
    if "wingspan" in info["spec"]:
        e["wingspan"] = st["size"][0]
    e["spec"] = dict(info["spec"])
    e["bbox_min"] = st["min"]
    e["bbox_max"] = st["max"]
    e["notes"] = info["notes"]
    return e


def write_manifest(ids=None):
    ids = IDS if ids is None else ids
    data = {"assets": []}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, "r", encoding="utf-8") as f:
            data = json.load(f)
    by_id = {e["id"]: e for e in data.get("assets", [])}
    for aid in ids:
        glb = os.path.join(K.MODELS, REG[aid]["glb"].replace("/", os.sep) + ".glb")
        if os.path.exists(glb) and aid in bpy.data.objects:
            by_id[aid] = describe(aid)
    order = {a: i for i, a in enumerate(IDS)}
    out = {"_comment": (
        "NEON TIDE animals (rigid parts, no armature). Positions are Blender asset-space metres (x right, y forward, "
        "z up); Godot = (x, z, -y). GLB node names are '<id>__<part>'. Every part has identity rest rotation and its "
        "origin at the joint ('part_origins'): head = head + neck pivoting at the neck base (rotate about X: negative "
        "= nose down), leg_* pivot at shoulder / hip (about X: positive = foot forward), tail pivots at its base "
        "(about Godot Y = wag / swim), wing_l / wing_r pivot at the wing root, rest = flat spread (about Godot Z: "
        "wing_l +angle = tip down, wing_r -angle = tip down). Quadrupeds / seagull: origin on the ground under the "
        "body centre; fish, fish_b, shark: origin at the body centre."),
        "assets": sorted(by_id.values(), key=lambda e: order.get(e["id"], 99))}
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    return len(out["assets"])


def run(ids=None, save=True):
    rep = build(ids)
    ex = export(ids)
    n = write_manifest()
    if save:
        K.save_master()
    return rep + "\nexported: " + ex + "\nmanifest entries: %d" % n


# =========================================================================== QUADRUPEDS
def _quad_legs(root, front, hind, color, bands_f=None, bands_h=None, paw_size=None, paw_color=None, segs=6,
               hoof=False):
    """front / hind = dict(x, pivot=(y, z), pts=[(y, z)...], secs=[...], paw=(y)) -> leg_fl, leg_fr, leg_rl, leg_rr."""
    for spec, names, bands in ((front, ("leg_fl", "leg_fr"), bands_f), (hind, ("leg_rl", "leg_rr"), bands_h)):
        for side, name in ((-1.0, names[0]), (1.0, names[1])):
            x = side * spec["x"]
            mb = K.MB()
            # the top ring sits deep inside the body, so the leg is left open there (saves the hidden cap)
            sweep(mb, spec["pts"], spec["secs"], color, segs=segs, phase=math.pi / 2, start=None,
                  end="flat", bands=bands, x=x)
            if paw_size is not None:
                w, l, h = paw_size
                paw(mb, x, spec["paw"], w, l, h, paw_color or color)
            py, pz = spec["pivot"]
            mb.to_object(root, name, origin=(x, py, pz))


@animal("dog", spec={"length": 0.95, "shoulder": 0.55},
        notes="Medium mixed-breed dog: dark coat, light chest / muzzle / socks / tail tip, floppy ears, red collar "
              "with a tag (collar + ears belong to head). Tail held up, wags about Z.")
def build_dog(root):
    D, L = "fur_dark", "fur_light"
    # ---- body
    mb = K.MB()
    sweep(mb, [(-0.315, 0.47), (-0.27, 0.47), (-0.15, 0.47), (0.0, 0.46), (0.13, 0.455), (0.24, 0.455),
               (0.30, 0.46)],
          [(0.05, 0.045, 0.05), (0.105, 0.068, 0.085), (0.115, 0.07, 0.105), (0.12, 0.078, 0.12),
           (0.125, 0.09, 0.15), (0.11, 0.085, 0.135), (0.07, 0.06, 0.08)],
          D, segs=8, start="point", end="flat", tips=(0.03, 0.0),
          rules=[(down(-0.55), L), (lambda c, n, b: c.y > 0.17 and n.y > 0.35 and c.z < 0.47, L)])
    mb.to_object(root, "body")
    # ---- head (neck + skull + muzzle + ears + collar), pivot at the neck base
    mb = K.MB()
    sweep(mb, [(0.17, 0.44), (0.24, 0.53), (0.257, 0.553), (0.315, 0.625)],
          [(0.078, 0.09, 0.09), (0.083, 0.09, 0.093), (0.083, 0.09, 0.093), (0.062, 0.068, 0.072)],
          D, segs=8, start=None, end="flat", bands=[None, "red", None],
          rules=[(lambda c, n, b: n.y > 0.55 and n.z < 0.35, L)])
    sweep(mb, [(0.272, 0.665), (0.33, 0.68), (0.398, 0.668), (0.452, 0.64), (0.508, 0.627)],
          [(0.06, 0.056, 0.056), (0.08, 0.071, 0.066), (0.068, 0.056, 0.06), (0.05, 0.04, 0.045),
           (0.04, 0.033, 0.037)],
          D, segs=8, start="point", end="flat", tips=(0.022, 0.0),
          rules=[(lambda c, n, b: c.y > 0.425, L), (lambda c, n, b: n.z < -0.5 and c.y > 0.36, L),
                 (lambda c, n, b: c.y > 0.37 and n.z > 0.6 and abs(c.x) < 0.012, L)])
    hull(mb, [(sx * w, y, z) for sx in (-1, 1) for (w, y, z) in
              ((0.023, 0.5, 0.622), (0.023, 0.5, 0.66), (0.014, 0.527, 0.628), (0.016, 0.524, 0.656))], "black")
    for s in (-1.0, 1.0):
        eye(mb, 0.012, (s * 0.045, 0.394, 0.688))
        # floppy ear hanging from the top of the skull down along the cheek
        fin(mb, [(-0.028, 0.004), (0.026, 0.006), (0.05, -0.06), (0.03, -0.13), (-0.005, -0.12), (-0.025, -0.05)],
            0.014, D, plane="YZ", pos=(s * 0.072, 0.325, 0.728), rot=(0, s * 22.0, 0))
    # collar tag (hangs at the throat side of the collar)
    P.octa(mb, 0.013, (0, 0.322, 0.468), "gold", scale=(0.6, 0.35, 1.0))
    mb.to_object(root, "head", origin=(0.0, 0.2, 0.47))
    # ---- legs
    front = dict(x=0.072, pivot=(0.17, 0.42), paw=0.183,
                 pts=[(0.17, 0.47), (0.155, 0.32), (0.163, 0.17), (0.17, 0.03)],
                 secs=[(0.045, 0.055, 0.06), (0.037, 0.04, 0.045), (0.026, 0.028, 0.028), (0.024, 0.025, 0.025)])
    hind = dict(x=0.078, pivot=(-0.21, 0.44), paw=-0.215,
                pts=[(-0.21, 0.48), (-0.168, 0.33), (-0.25, 0.17), (-0.235, 0.03)],
                secs=[(0.055, 0.085, 0.08), (0.045, 0.06, 0.06), (0.026, 0.03, 0.03), (0.023, 0.025, 0.025)])
    _quad_legs(root, front, hind, D, bands_f=[None, None, L], bands_h=[None, None, L],
               paw_size=(0.048, 0.064, 0.042), paw_color=L)
    # ---- tail, held up
    mb = K.MB()
    sweep(mb, [(-0.27, 0.50), (-0.335, 0.548), (-0.385, 0.615), (-0.405, 0.69)],
          [(0.028, 0.03, 0.03), (0.027, 0.03, 0.03), (0.023, 0.025, 0.025), (0.016, 0.017, 0.017)],
          D, segs=6, start=None, end="point", tips=(0.0, 0.03), bands=[None, None, L])
    mb.to_object(root, "tail", origin=(0.0, -0.29, 0.50))


@animal("coyote", spec={"length": 1.15, "shoulder": 0.55},
        notes="Lean coyote: grey coat, light throat / belly / muzzle, rusty ears and lower legs, big erect ears, "
              "bushy tail hanging back with a dark tip (wags about Z).")
def build_coyote(root):
    G, L, R, Dk = "fur_gray", "fur_light", "fur_deer", "fur_dark"
    mb = K.MB()
    sweep(mb, [(-0.31, 0.47), (-0.27, 0.47), (-0.14, 0.465), (0.0, 0.465), (0.13, 0.46), (0.24, 0.462),
               (0.30, 0.466)],
          [(0.045, 0.045, 0.045), (0.092, 0.065, 0.08), (0.098, 0.065, 0.085), (0.103, 0.07, 0.098),
           (0.108, 0.085, 0.128), (0.094, 0.08, 0.118), (0.06, 0.055, 0.07)],
          G, segs=8, start="point", end="flat", tips=(0.03, 0.0),
          rules=[(down(-0.5), L), (lambda c, n, b: c.y > 0.18 and n.y > 0.35 and c.z < 0.46, L),
                 (lambda c, n, b: n.z > 0.8 and c.y > -0.2, Dk)])
    mb.to_object(root, "body")
    # head
    mb = K.MB()
    sweep(mb, [(0.17, 0.45), (0.25, 0.555), (0.31, 0.625)],
          [(0.064, 0.08, 0.08), (0.062, 0.07, 0.072), (0.052, 0.058, 0.06)],
          G, segs=8, start=None, end="flat", rules=[(lambda c, n, b: n.y > 0.5 and n.z < 0.4, L)])
    sweep(mb, [(0.27, 0.66), (0.32, 0.668), (0.38, 0.652), (0.45, 0.626), (0.515, 0.61)],
          [(0.05, 0.05, 0.05), (0.064, 0.058, 0.05), (0.048, 0.042, 0.044), (0.03, 0.028, 0.03),
           (0.019, 0.02, 0.022)],
          G, segs=8, start="point", end="point", tips=(0.02, 0.012),
          rules=[(lambda c, n, b: n.z < -0.35 and c.y > 0.3, L), (lambda c, n, b: c.y > 0.43 and n.z < 0.2, L)])
    hull(mb, [(sx * w, y, z) for sx in (-1, 1) for (w, y, z) in
              ((0.014, 0.505, 0.603), (0.014, 0.505, 0.628), (0.009, 0.53, 0.607), (0.01, 0.527, 0.626))], "black")
    for s in (-1.0, 1.0):
        eye(mb, 0.01, (s * 0.037, 0.385, 0.672))
        fin(mb, [(-0.031, 0.0), (0.031, 0.0), (s * 0.006, 0.102)], 0.016, R, plane="XZ",
            pos=(s * 0.037, 0.318, 0.695), rot=(10.0, s * 16.0, s * -10.0), side_colors=(G, L))
    mb.to_object(root, "head", origin=(0.0, 0.2, 0.47))
    front = dict(x=0.064, pivot=(0.17, 0.42), paw=0.18,
                 pts=[(0.17, 0.47), (0.155, 0.32), (0.163, 0.15), (0.17, 0.04)],
                 secs=[(0.04, 0.05, 0.055), (0.031, 0.035, 0.04), (0.02, 0.022, 0.022), (0.018, 0.02, 0.02)])
    hind = dict(x=0.07, pivot=(-0.21, 0.44), paw=-0.22,
                pts=[(-0.21, 0.48), (-0.165, 0.32), (-0.255, 0.16), (-0.242, 0.04)],
                secs=[(0.05, 0.08, 0.075), (0.038, 0.05, 0.05), (0.022, 0.026, 0.026), (0.018, 0.02, 0.02)])
    _quad_legs(root, front, hind, G, bands_f=[None, None, R], bands_h=[None, None, R],
               paw_size=(0.04, 0.056, 0.036), paw_color=R)
    mb = K.MB()
    sweep(mb, [(-0.27, 0.495), (-0.35, 0.462), (-0.45, 0.385), (-0.54, 0.30), (-0.585, 0.25)],
          [(0.028, 0.03, 0.03), (0.048, 0.052, 0.052), (0.054, 0.058, 0.058), (0.042, 0.045, 0.045),
           (0.025, 0.026, 0.026)],
          G, segs=6, start=None, end="point", tips=(0.0, 0.04), bands=[None, None, None, Dk],
          rules=[(lambda c, n, b: n.z < -0.6 and b < 2, L)])
    mb.to_object(root, "tail", origin=(0.0, -0.29, 0.49))


@animal("cat", spec={"length": 0.5},
        notes="Ginger tabby cat: fur_ginger coat with fur_ginger_dark stripes, light chest / muzzle, pointed ears, "
              "upright tail curling forward at the tip (tail wags about Z).")
def build_cat(root):
    C, Cd, L = "fur_ginger", "fur_ginger_dark", "fur_light"
    mb = K.MB()
    sweep(mb, [(-0.17, 0.205), (-0.145, 0.205), (-0.06, 0.205), (0.03, 0.2), (0.10, 0.205), (0.145, 0.21)],
          [(0.03, 0.03, 0.03), (0.054, 0.045, 0.05), (0.058, 0.046, 0.055), (0.06, 0.048, 0.06),
           (0.055, 0.05, 0.06), (0.035, 0.035, 0.04)],
          C, segs=8, start="point", end="flat", tips=(0.015, 0.0),
          rules=[(down(-0.5), L), (lambda c, n, b: c.y > 0.11 and n.y > 0.4 and c.z < 0.21, L),
                 (lambda c, n, b: n.z > 0.25 and b in (1, 3), Cd)])
    mb.to_object(root, "body")
    mb = K.MB()
    sweep(mb, [(0.10, 0.205), (0.138, 0.248), (0.155, 0.268)],
          [(0.037, 0.042, 0.042), (0.036, 0.04, 0.04), (0.034, 0.036, 0.036)],
          C, segs=8, start=None, end="flat", rules=[(lambda c, n, b: n.y > 0.45, L)])
    sweep(mb, [(0.124, 0.292), (0.16, 0.299), (0.205, 0.291), (0.236, 0.279), (0.252, 0.275)],
          [(0.036, 0.036, 0.036), (0.058, 0.054, 0.05), (0.05, 0.044, 0.043), (0.03, 0.027, 0.029),
           (0.02, 0.019, 0.021)],
          C, segs=8, start="point", end="flat", tips=(0.012, 0.0),
          rules=[(lambda c, n, b: c.y > 0.222 and n.z < 0.5, L), (lambda c, n, b: n.z < -0.5, L),
                 (lambda c, n, b: n.z > 0.6 and b == 1, Cd)])
    hull(mb, [(sx * w, y, z) for sx in (-1, 1) for (w, y, z) in
              ((0.009, 0.249, 0.283), (0.004, 0.257, 0.276), (0.007, 0.247, 0.272))] + [(0, 0.259, 0.281)],
         "coral_pink")
    for s in (-1.0, 1.0):
        eye(mb, 0.0095, (s * 0.031, 0.222, 0.301), "lime", scale=(1.0, 0.8, 1.0))
        fin(mb, [(-0.025, 0.0), (0.025, 0.0), (s * 0.004, 0.056)], 0.012, C, plane="XZ",
            pos=(s * 0.031, 0.162, 0.33), rot=(6.0, s * 16.0, s * -10.0), side_colors=(C, "coral_pink"))
        # whiskers
        for k, (dz, dx) in enumerate(((0.0, 0.0), (-0.009, 0.004))):
            P.blade(mb, (s * 0.019, 0.248, 0.273 + dz), (s * (0.065 + dx), 0.238, 0.279 + dz * 1.6), 0.0025,
                    "white", normal=(0, 0, 1))
    mb.to_object(root, "head", origin=(0.0, 0.1, 0.205))
    front = dict(x=0.034, pivot=(0.10, 0.19), paw=0.108,
                 pts=[(0.10, 0.215), (0.094, 0.12), (0.1, 0.022)],
                 secs=[(0.022, 0.027, 0.03), (0.017, 0.02, 0.02), (0.013, 0.015, 0.015)])
    hind = dict(x=0.04, pivot=(-0.12, 0.20), paw=-0.132,
                pts=[(-0.12, 0.225), (-0.095, 0.13), (-0.15, 0.06), (-0.14, 0.022)],
                secs=[(0.03, 0.045, 0.045), (0.024, 0.03, 0.03), (0.014, 0.016, 0.016), (0.013, 0.014, 0.014)])
    _quad_legs(root, front, hind, C, bands_f=[None, None], bands_h=[None, None, None],
               paw_size=(0.03, 0.036, 0.022), paw_color=L)
    mb = K.MB()
    sweep(mb, [(-0.15, 0.225), (-0.195, 0.262), (-0.222, 0.33), (-0.226, 0.408), (-0.208, 0.452)],
          [(0.015, 0.015, 0.015), (0.0145, 0.015, 0.015), (0.013, 0.014, 0.014), (0.012, 0.013, 0.013),
           (0.011, 0.012, 0.012)],
          C, segs=6, start=None, end="point", tips=(0.0, 0.02), bands=[None, Cd, None, Cd])
    mb.to_object(root, "tail", origin=(0.0, -0.165, 0.225))


@animal("rabbit", spec={"length": 0.38},
        notes="Crouching grey rabbit: big haunches (leg_rl / leg_rr include the long hind feet), long ears with "
              "pink insides (part of head), cotton tail = part tail (fur_light ball).")
def build_rabbit(root):
    G, L = "fur_gray", "fur_light"
    mb = K.MB()
    sweep(mb, [(-0.165, 0.112), (-0.14, 0.115), (-0.08, 0.12), (-0.01, 0.12), (0.05, 0.116), (0.082, 0.12)],
          [(0.035, 0.035, 0.035), (0.068, 0.07, 0.075), (0.076, 0.08, 0.084), (0.066, 0.073, 0.077),
           (0.05, 0.06, 0.065), (0.03, 0.04, 0.045)],
          G, segs=8, start="point", end="flat", tips=(0.018, 0.0),
          rules=[(down(-0.5), L), (lambda c, n, b: c.y > 0.04 and n.y > 0.4 and c.z < 0.12, L)])
    mb.to_object(root, "body")
    mb = K.MB()
    sweep(mb, [(0.035, 0.125), (0.075, 0.168), (0.088, 0.182)],
          [(0.034, 0.04, 0.04), (0.032, 0.035, 0.035), (0.03, 0.03, 0.03)],
          G, segs=8, start="flat", end="flat", rules=[(lambda c, n, b: n.y > 0.45, L)])
    sweep(mb, [(0.062, 0.19), (0.092, 0.192), (0.13, 0.182), (0.163, 0.167), (0.183, 0.161)],
          [(0.03, 0.03, 0.03), (0.042, 0.042, 0.04), (0.038, 0.036, 0.036), (0.024, 0.024, 0.026),
           (0.016, 0.015, 0.016)],
          G, segs=8, start="point", end="flat", tips=(0.01, 0.0),
          rules=[(lambda c, n, b: c.y > 0.15 and n.z < 0.3, L), (lambda c, n, b: n.z < -0.55, L)])
    hull(mb, [(sx * w, y, z) for sx in (-1, 1) for (w, y, z) in
              ((0.007, 0.181, 0.166), (0.004, 0.188, 0.16), (0.006, 0.18, 0.158))] + [(0, 0.189, 0.167)],
         "coral_pink")
    for s in (-1.0, 1.0):
        eye(mb, 0.0085, (s * 0.034, 0.128, 0.198))
        fin(mb, [(-0.016, 0.0), (0.016, 0.0), (0.019, 0.05), (0.012, 0.1), (0.0, 0.122), (-0.012, 0.1),
                 (-0.019, 0.05)], 0.008, G, plane="XZ", pos=(s * 0.02, 0.085, 0.212),
            rot=(24.0, s * 12.0, s * -8.0), side_colors=(G, "coral_pink"))
    mb.to_object(root, "head", origin=(0.0, 0.05, 0.125))
    # front legs (small) + big hind legs with the long feet
    for side, name in ((-1.0, "leg_fl"), (1.0, "leg_fr")):
        x = side * 0.03
        mb = K.MB()
        sweep(mb, [(0.05, 0.085), (0.055, 0.04), (0.06, 0.016)],
              [(0.017, 0.02, 0.02), (0.013, 0.015, 0.015), (0.012, 0.014, 0.014)],
              G, segs=6, phase=math.pi / 6, x=x, bands=[None, L])
        paw(mb, x, 0.069, 0.022, 0.034, 0.018, L)
        mb.to_object(root, name, origin=(x, 0.05, 0.075))
    for side, name in ((-1.0, "leg_rl"), (1.0, "leg_rr")):
        x = side * 0.056
        mb = K.MB()
        sweep(mb, [(-0.085, 0.145), (-0.055, 0.085), (-0.075, 0.035), (-0.105, 0.018)],
              [(0.024, 0.05, 0.05), (0.026, 0.05, 0.048), (0.018, 0.028, 0.028), (0.014, 0.016, 0.016)],
              G, segs=6, phase=math.pi / 6, x=x)
        mb.box((0.026, 0.1, 0.022), (x, -0.06, 0.0), L, base=True, taper=(0.85, 0.85))
        mb.to_object(root, name, origin=(x, -0.08, 0.1))
    mb = K.MB()
    mb.ico(0.03, (0, -0.178, 0.128), L, subdiv=1, jitter=0.12, seed=3, scale=(1.0, 0.85, 1.0))
    mb.to_object(root, "tail", origin=(0.0, -0.16, 0.128))


@animal("deer", spec={"length": 1.7, "shoulder": 1.05},
        notes="Slender deer (fur_deer, fur_light belly / throat / muzzle band / tail flag / rump), antlers (cream) "
              "and big ears on the head part. Head graze = rotate head about X ~ -0.7 rad.")
def build_deer(root):
    D, L = "fur_deer", "fur_light"
    mb = K.MB()
    sweep(mb, [(-0.665, 0.90), (-0.585, 0.90), (-0.37, 0.886), (-0.07, 0.872), (0.21, 0.876), (0.44, 0.89)],
          [(0.07, 0.06, 0.06), (0.128, 0.108, 0.128), (0.152, 0.122, 0.152), (0.16, 0.124, 0.172),
           (0.16, 0.166, 0.205), (0.1, 0.112, 0.122)],
          D, segs=8, start="point", end="flat", tips=(0.04, 0.0),
          rules=[(down(-0.5), L), (lambda c, n, b: c.y < -0.52 and n.y < -0.45 and c.z < 0.95, L),
                 (lambda c, n, b: c.y > 0.3 and n.y > 0.4 and c.z < 0.86, L)])
    mb.to_object(root, "body")
    # head: neck + skull + muzzle + ears + antlers (pivot at the neck base, inside the chest)
    mb = K.MB()
    sweep(mb, [(0.29, 0.85), (0.44, 1.06), (0.575, 1.235), (0.625, 1.30)],
          [(0.105, 0.135, 0.13), (0.085, 0.102, 0.108), (0.068, 0.076, 0.08), (0.062, 0.066, 0.07)],
          D, segs=8, start=None, end="flat", rules=[(lambda c, n, b: n.y > 0.55 and c.z > 1.12, L)])
    with mb.at((0.0, 0.045, -0.045)):
        sweep(mb, [(0.555, 1.42), (0.615, 1.432), (0.695, 1.405), (0.79, 1.362), (0.87, 1.333)],
              [(0.058, 0.06, 0.06), (0.074, 0.07, 0.065), (0.06, 0.055, 0.055), (0.04, 0.04, 0.042),
               (0.031, 0.032, 0.035)],
              D, segs=8, start="point", end="flat", tips=(0.02, 0.0), bands=[None, None, L, None],
              rules=[(lambda c, n, b: n.z < -0.5 and c.y > 0.64, L)])
        hull(mb, [(sx * w, y, z) for sx in (-1, 1) for (w, y, z) in
                  ((0.024, 0.865, 1.312), (0.024, 0.865, 1.352), (0.016, 0.888, 1.318), (0.018, 0.885, 1.35))],
             "black")
        A = "cream"
        for s in (-1.0, 1.0):
            eye(mb, 0.015, (s * 0.057, 0.69, 1.435))
            with mb.at((s * 0.055, 0.6, 1.47), rot=(-10.0, -s * 32.0, -s * 15.0), scale=(s, 1.0, 1.0)):
                fin(mb, [(0.0, -0.028), (0.08, -0.044), (0.158, 0.0), (0.08, 0.04), (0.0, 0.026)], 0.014, D,
                    plane="XZ", side_colors=(D, L))
            # antlers: main beam sweeping up / out / back then forward, two tines
            P.ttube(mb, [(s * 0.035, 0.61, 1.47), (s * 0.11, 0.572, 1.6), (s * 0.2, 0.6, 1.72),
                         (s * 0.172, 0.755, 1.8)], [0.017, 0.013, 0.01, 0.005], A, segs=4)
            P.ttube(mb, [(s * 0.108, 0.575, 1.592), (s * 0.115, 0.625, 1.735)], [0.009, 0.004], A, segs=3)
            P.ttube(mb, [(s * 0.196, 0.615, 1.728), (s * 0.222, 0.64, 1.86)], [0.0085, 0.004], A, segs=3)
    mb.to_object(root, "head", origin=(0.0, 0.33, 0.9))
    front = dict(x=0.098, pivot=(0.3, 0.8), paw=0.0,
                 pts=[(0.3, 0.86), (0.282, 0.66), (0.3, 0.36), (0.31, 0.07), (0.312, 0.0)],
                 secs=[(0.058, 0.078, 0.08), (0.04, 0.05, 0.05), (0.023, 0.027, 0.027), (0.019, 0.023, 0.022),
                       (0.022, 0.03, 0.022)])
    hind = dict(x=0.108, pivot=(-0.42, 0.84), paw=0.0,
                pts=[(-0.42, 0.9), (-0.32, 0.62), (-0.465, 0.38), (-0.436, 0.07), (-0.43, 0.0)],
                secs=[(0.075, 0.13, 0.12), (0.05, 0.07, 0.065), (0.025, 0.034, 0.03), (0.019, 0.023, 0.022),
                      (0.022, 0.03, 0.022)])
    hoof = [None, None, None, "fur_dark"]
    _quad_legs(root, front, hind, D, bands_f=hoof, bands_h=hoof, segs=5)
    mb = K.MB()
    sweep(mb, [(-0.64, 0.96), (-0.695, 0.935), (-0.74, 0.865)],
          [(0.03, 0.02, 0.02), (0.05, 0.022, 0.018), (0.032, 0.015, 0.012)],
          D, segs=5, phase=math.pi / 2, start=None, end="point", tips=(0.0, 0.042),
          rules=[(lambda c, n, b: n.y < -0.3 or n.z < -0.3, L)])
    mb.to_object(root, "tail", origin=(0.0, -0.64, 0.95))


# =========================================================================== SEAGULL
def _gull_wing(mb, s):
    """Flat-spread gull wing toward s*X (s = -1 left, +1 right): 6 airfoil stations, grey top, white underside,
    black tip."""
    st = [  # (span from centre line, y leading edge, y trailing edge, thickness, z offset)
        (0.035, 0.085, -0.075, 0.024, 0.0),
        (0.18, 0.10, -0.088, 0.018, 0.004),
        (0.30, 0.094, -0.072, 0.014, 0.007),
        (0.42, 0.052, -0.074, 0.010, 0.008),
        (0.53, -0.004, -0.092, 0.007, 0.007),
        (0.625, -0.082, -0.104, 0.003, 0.005),
    ]
    z0 = 0.205
    rings = []
    for d, yl, yt, th, dz in st:
        yq = yl - 0.32 * (yl - yt)
        z = z0 + dz
        rings.append([(s * d, yl, z), (s * d, yq, z + th * 0.55), (s * d, yt, z), (s * d, yq, z - th * 0.35)])
    faces = mb.loft(rings, "gray_light", closed=True, cap_start=True, cap_end=True)
    for f in faces:
        f.normal_update()
        c = f.calc_center_median()
        if abs(c.x) > 0.47:
            mb.paint([f], "black")
        elif f.normal.z < -0.05:
            mb.paint([f], "feather_white")
    return faces


@animal("seagull", spec={"wingspan": 1.25},
        notes="Seagull, wings flat spread at rest (wing_l toward -X, wing_r toward +X, pivots at the wing roots). "
              "Godot flap: wing_l rot.z = +a / wing_r rot.z = -a (a > 0 = tips down). Perch fold suggestion: "
              "wing_l rot.y = +1.45, wing_r rot.y = -1.45 (wings swing back along the body). Head turns about Y. "
              "Legs are part of the body (feet on z = 0).")
def build_seagull(root):
    W = "feather_white"
    mb = K.MB()
    sweep(mb, [(-0.14, 0.182), (-0.10, 0.182), (-0.02, 0.177), (0.06, 0.18), (0.11, 0.19), (0.14, 0.2)],
          [(0.03, 0.025, 0.025), (0.05, 0.045, 0.045), (0.065, 0.058, 0.065), (0.062, 0.056, 0.065),
           (0.045, 0.045, 0.05), (0.03, 0.03, 0.035)],
          W, segs=8, start="point", end="flat", tips=(0.02, 0.0),
          rules=[(lambda c, n, b: n.z > 0.55 and c.y < 0.06, "gray_light")])
    # legs + webbed feet (part of the body)
    for s in (-1.0, 1.0):
        P.ttube(mb, [(s * 0.024, -0.012, 0.13), (s * 0.027, -0.004, 0.07), (s * 0.03, 0.006, 0.004)],
                [0.0075, 0.0055, 0.005], "coral_pink", segs=4)
        fin(mb, [(s * 0.03 - 0.006, -0.004), (s * 0.03 + 0.006, -0.004), (s * 0.03 + 0.03, 0.05),
                 (s * 0.03, 0.04), (s * 0.03 - 0.03, 0.05)], 0.007, "coral_pink", plane="XY", pos=(0, 0, 0.0035))
    mb.to_object(root, "body")
    # head: neck + round head + hooked beak, pivot at the neck base
    mb = K.MB()
    sweep(mb, [(0.095, 0.19), (0.135, 0.238)], [(0.036, 0.04, 0.04), (0.032, 0.034, 0.034)], W, segs=8)
    sweep(mb, [(0.118, 0.262), (0.15, 0.268), (0.185, 0.26), (0.202, 0.253)],
          [(0.028, 0.028, 0.028), (0.038, 0.037, 0.035), (0.03, 0.03, 0.03), (0.02, 0.019, 0.02)],
          W, segs=8, start="point", end="flat", tips=(0.012, 0.0))
    hull(mb, [(sx * w, y, z) for sx in (-1, 1) for (w, y, z) in
              ((0.012, 0.196, 0.262), (0.012, 0.196, 0.242), (0.006, 0.235, 0.25), (0.005, 0.232, 0.236))] +
         [(0, 0.258, 0.246), (0, 0.255, 0.236), (0, 0.24, 0.234)], "beak_orange",
         rules=[(lambda c, n, b: c.y > 0.232 and c.z < 0.242, "red")])
    for s in (-1.0, 1.0):
        eye(mb, 0.0075, (s * 0.03, 0.168, 0.274))
    mb.to_object(root, "head", origin=(0.0, 0.1, 0.2))
    # wings
    for s, name in ((-1.0, "wing_l"), (1.0, "wing_r")):
        mb = K.MB()
        _gull_wing(mb, s)
        mb.to_object(root, name, origin=(s * 0.045, 0.005, 0.205))
    # tail fan
    mb = K.MB()
    fin(mb, [(-0.028, -0.105), (0.028, -0.105), (0.066, -0.235), (0.03, -0.258), (0.0, -0.25), (-0.03, -0.258),
             (-0.066, -0.235)], 0.012, W, plane="XY", pos=(0, 0, 0.186),
        rules=[(lambda c, n, b: n.z > 0.3, "gray_light")])
    mb.to_object(root, "tail", origin=(0.0, -0.115, 0.186))


# =========================================================================== FISH
@animal("fish", spec={"length": 0.35},
        notes="Streamlined silver fish (blue-grey back, light belly). Origin at the body centre. Part tail = "
              "peduncle + forked caudal fin, pivot at the tail base, swims by rotating about Z.")
def build_fish(root):
    S, Bk, Bl = "fish_silver", "denim", "shark_belly"
    mb = K.MB()
    sweep(mb, [(-0.1, 0.0), (-0.06, 0.0), (0.0, 0.0), (0.07, 0.001), (0.128, 0.0), (0.16, -0.002)],
          [(0.0075, 0.012, 0.011), (0.02, 0.032, 0.028), (0.028, 0.046, 0.04), (0.028, 0.044, 0.038),
           (0.02, 0.03, 0.026), (0.011, 0.015, 0.014)],
          S, segs=8, start="flat", end="point", tips=(0.0, 0.016),
          rules=[(up(0.5), Bk), (down(-0.55), Bl)])
    for s in (-1.0, 1.0):
        eye(mb, 0.0085, (s * 0.021, 0.12, 0.01))
        fin(mb, [(0.0, 0.0), (0.012, 0.0), (-0.035, 0.012), (-0.03, -0.004)], 0.003, S, plane="XY",
            pos=(s * 0.024, 0.088, -0.016), rot=(0, s * 30.0, 0), inset=0.002)
    fin(mb, [(0.035, 0.03), (-0.035, 0.03), (-0.03, 0.062), (0.0, 0.07)], 0.004, Bk, plane="YZ", inset=0.003)
    fin(mb, [(-0.035, -0.025), (-0.075, -0.012), (-0.07, -0.042), (-0.055, -0.046)], 0.003, S, plane="YZ",
        inset=0.0025)
    mb.to_object(root, "body")
    mb = K.MB()
    sweep(mb, [(-0.085, 0.0), (-0.128, 0.0)], [(0.01, 0.016, 0.015), (0.006, 0.011, 0.011)], S, segs=6,
          rules=[(up(0.5), Bk)])
    fin(mb, [(-0.118, 0.007), (-0.152, 0.03), (-0.176, 0.058), (-0.168, 0.026), (-0.158, 0.0), (-0.168, -0.024),
             (-0.176, -0.052), (-0.152, -0.028), (-0.118, -0.007)], 0.004, S, plane="YZ", inset=0.003)
    mb.to_object(root, "tail", origin=(0.0, -0.095, 0.0))


@animal("fish_b", spec={"length": 0.32},
        notes="Deep-bodied reef fish, fish_orange with white bands and dark fin edges. Origin at the body centre. "
              "Part tail = peduncle + rounded fan, pivot at the tail base, swims about Z.")
def build_fish_b(root):
    O, W, Bk = "fish_orange", "white", "black"
    mb = K.MB()
    sweep(mb, [(-0.088, 0.0), (-0.066, 0.0), (-0.046, 0.0), (0.0, 0.0), (0.03, 0.002), (0.05, 0.002),
               (0.1, 0.0), (0.132, -0.006)],
          [(0.01, 0.02, 0.02), (0.015, 0.045, 0.044), (0.019, 0.062, 0.06), (0.024, 0.085, 0.08),
           (0.024, 0.083, 0.077), (0.023, 0.078, 0.072), (0.015, 0.042, 0.038), (0.008, 0.016, 0.016)],
          O, segs=8, start="flat", end="point", tips=(0.0, 0.012), bands=[None, W, None, None, W, None, None])
    for s in (-1.0, 1.0):
        eye(mb, 0.011, (s * 0.017, 0.09, 0.018))
        fin(mb, [(0.0, 0.0), (0.012, 0.0), (-0.03, 0.016), (-0.028, -0.006)], 0.003, O, plane="XY",
            pos=(s * 0.022, 0.06, -0.012), rot=(0, s * 30.0, 0), inset=0.002)
    fin(mb, [(0.07, 0.065), (-0.065, 0.045), (-0.085, 0.07), (-0.05, 0.115), (0.02, 0.135), (0.05, 0.105)], 0.005,
        O, plane="YZ", inset=0.004, rules=[(lambda c, n, b: c.z > 0.112 or (c.y < -0.05 and c.z > 0.08), Bk)])
    fin(mb, [(0.03, -0.065), (-0.065, -0.045), (-0.08, -0.07), (-0.045, -0.105), (0.0, -0.1)], 0.005, O,
        plane="YZ", inset=0.004, rules=[(lambda c, n, b: c.z < -0.092, Bk)])
    mb.to_object(root, "body")
    mb = K.MB()
    sweep(mb, [(-0.075, 0.0), (-0.112, 0.0)], [(0.01, 0.02, 0.02), (0.007, 0.016, 0.016)], O, segs=6, bands=[W])
    fin(mb, [(-0.105, 0.012), (-0.135, 0.045), (-0.16, 0.058), (-0.172, 0.03), (-0.175, 0.0), (-0.172, -0.03),
             (-0.16, -0.058), (-0.135, -0.045), (-0.105, -0.012)], 0.005, O, plane="YZ", inset=0.004,
        rules=[(lambda c, n, b: c.y < -0.162, Bk)])
    mb.to_object(root, "tail", origin=(0.0, -0.085, 0.0))


@animal("shark", spec={"length": 3.3},
        notes="Shark, origin at the body centre. Part body = torso + head + dorsal / pectoral / pelvic fins; part "
              "tail = rear body (from the pivot at y=-0.72) + second dorsal + anal fin + caudal fin, swings about Z "
              "(swim). Countershaded shark_gray / shark_belly.")
def build_shark(root):
    G, B = "shark_gray", "shark_belly"
    secs = [(0.17, 0.2, 0.17), (0.22, 0.26, 0.22), (0.29, 0.33, 0.29), (0.32, 0.36, 0.31), (0.29, 0.31, 0.27),
            (0.235, 0.235, 0.2), (0.2, 0.19, 0.16), (0.2, 0.188, 0.158), (0.13, 0.12, 0.1), (0.05, 0.05, 0.04)]
    ys = [-0.85, -0.6, -0.25, 0.15, 0.6, 1.0, 1.15, 1.2, 1.4, 1.6]
    zs = [0.02, 0.02, 0.01, 0.0, -0.01, -0.02, -0.025, -0.027, -0.04, -0.06]
    bands = [None] * (len(ys) - 1)
    mb = K.MB()
    sweep(mb, list(zip(ys, zs)), secs, G, segs=10, phase=math.pi / 10, start="flat", end="point",
          tips=(0.0, 0.065),
          rules=[(lambda c, n, b: b == 6 and n.z < -0.6, "charcoal"), (down(-0.28), B)])
    # gill slits: thin dark quads 6 mm off the flat side face (side faces sit at 0.951 * rx)
    def rx_at(y):
        for i in range(len(ys) - 1):
            if ys[i] <= y <= ys[i + 1]:
                t = (y - ys[i]) / (ys[i + 1] - ys[i])
                return secs[i][0] + (secs[i + 1][0] - secs[i][0]) * t
        return secs[-1][0]
    for s in (-1.0, 1.0):
        for k in range(3):
            y = 0.66 + k * 0.075
            x = s * (math.cos(math.radians(18.0)) * rx_at(y) + 0.006)
            P.fpoly(mb, [(x, y - 0.008, -0.075), (x, y + 0.008, -0.075), (x, y + 0.014, 0.075),
                         (x, y - 0.002, 0.075)], "charcoal", (s, 0, 0))
        xe = s * (math.cos(math.radians(18.0)) * rx_at(1.25) - 0.004)
        eye(mb, 0.028, (xe, 1.25, 0.045), scale=(0.7, 1.0, 1.0))
        # pectoral fin (swept back, anhedral)
        with mb.at((s * 0.2, 0.62, -0.17), rot=(0.0, s * 24.0, 0.0), scale=(s, 1.0, 1.0)):
            fin(mb, [(0.0, 0.16), (0.0, -0.16), (0.42, -0.42), (0.6, -0.5), (0.5, -0.3)], 0.045, G, plane="XY",
                rules=[(down(-0.3), B)])
        with mb.at((s * 0.12, -0.42, -0.2), rot=(0.0, s * 30.0, 0.0), scale=(s, 1.0, 1.0)):
            fin(mb, [(0.0, 0.08), (0.0, -0.08), (0.16, -0.2), (0.18, -0.1)], 0.03, G, plane="XY",
                rules=[(down(-0.3), B)])
    # dorsal fin (falcate)
    fin(mb, [(0.32, 0.3), (-0.28, 0.3), (-0.36, 0.38), (-0.25, 0.42), (-0.2, 0.62), (-0.24, 0.86), (-0.08, 0.66),
             (0.12, 0.44)], 0.05, G, plane="YZ", inset=0.022)
    mb.to_object(root, "body")
    # tail section
    mb = K.MB()
    sweep(mb, [(-0.62, 0.02), (-0.95, 0.04), (-1.28, 0.07), (-1.4, 0.085)],
          [(0.19, 0.225, 0.19), (0.13, 0.152, 0.122), (0.062, 0.072, 0.06), (0.045, 0.05, 0.045)],
          G, segs=10, phase=math.pi / 10, start="flat", end="flat", rules=[(down(-0.28), B)])
    fin(mb, [(-0.8, 0.15), (-0.98, 0.12), (-1.03, 0.25), (-0.92, 0.3)], 0.03, G, plane="YZ", inset=0.012)
    fin(mb, [(-0.85, -0.1), (-1.02, -0.08), (-1.06, -0.2), (-0.96, -0.2)], 0.03, G, plane="YZ", inset=0.012,
        rules=[(down(-0.3), B)])
    fin(mb, [(-1.26, 0.13), (-1.42, 0.38), (-1.62, 0.7), (-1.6, 0.55), (-1.52, 0.3), (-1.46, 0.09), (-1.52, -0.04),
             (-1.58, -0.26), (-1.47, -0.22), (-1.36, -0.08), (-1.26, 0.0)], 0.05, G, plane="YZ", inset=0.02,
        rules=[(lambda c, n, b: c.z < -0.05 and n.z < -0.2, B)])
    mb.to_object(root, "tail", origin=(0.0, -0.72, 0.03))
