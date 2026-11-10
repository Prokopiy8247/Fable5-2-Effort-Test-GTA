# -*- coding: utf-8 -*-
"""wpn_firearms - NEON TIDE: Vesper Bay firearms (tools/blender/SPEC_WEAPONS.md, P1 firearms)
plus the shared weapon-building helpers used by wpn_melee_misc.py and wpn_pickups.py.

Executed INSIDE the live Blender through the Blender MCP:

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K; importlib.reload(K)
    import wpn_firearms as F; importlib.reload(F)
    print(F.build(export=True))            # every registered asset: build, export GLB, update the manifest
    print(F.build(["pistol"], preview=True))   # QA build with stand-in colours for the tint cells

Contract (see the spec): origin at the firing-hand grip (palm centre), barrel toward +Y, top +Z, left -X.
Main metal = palette cell `tint_a_metal`, polymer furniture = `tint_b`.
Sliding parts (slide / pump / bolt) keep an identity rest transform (object origin == asset origin) so Godot can
animate `position` directly; rotating parts (cylinder, sniper bolt) have their origin on the rotation axis;
magazines have their origin at the top-centre of the magazine (the end that enters the well).
All designs are original generic shapes - no real-world brand replicas.
"""
import json
import math
import os

import bpy
from mathutils import Vector

import gta_kit as K

A = "tint_a_metal"   # main metal - recoloured by weapon finishes in Godot
B = "tint_b"         # polymer furniture - default near-black in Godot

# QA: the tint cells are pure white in the palette atlas, which hides the two-tone design in Blender.
# build(..., preview=True) swaps them for stand-in colours.  NEVER export a preview build (build() refuses to).
PREVIEW = False
PREVIEW_MAP = {"tint_a_metal": "steel_dark", "tint_b": "charcoal", "tint_a": "orange", "tint_a_gloss": "orange",
               "tint_b_gloss": "charcoal", "tint_b_metal": "charcoal"}

MANIFEST = os.path.join(K.PROJECT, "gta", "resources", "data", "manifests", "weapons.json")
ROW_Y = K.CATEGORIES["Weapons"][1]
ROW_SPACING = 2.0
# master-scene row order (x = index * 2 m) for everything in the Weapons collection
ROW_ORDER = [
    "pistol", "revolver", "smg", "shotgun_pump", "shotgun_auto", "rifle_assault", "rifle_carbine", "rifle_marksman",
    "rifle_sniper", "launcher_rocket", "launcher_grenade",
    "knife", "bat", "crowbar", "nightstick", "grenade", "rocket", "grenade_40mm",
    "att_suppressor", "att_suppressor_large", "att_scope_reddot", "att_scope_4x", "att_scope_sniper",
    "att_flashlight", "att_grip", "att_laser",
    "pickup_health", "pickup_armor", "pickup_ammo", "pickup_cash", "pickup_cash_big", "pickup_parachute",
    "pickup_scuba", "pickup_snack", "pickup_wrench", "pickup_bribe", "pickup_weapon_crate",
    "phone", "parachute_canopy",
]
PART_ORDER = ["body", "mesh", "slide", "bolt", "pump", "cylinder", "mag", "mag_ext", "rocket_loaded"]

REG = {}   # asset id -> dict(id, glb, category, length, notes, build)


# --------------------------------------------------------------------------- registry / scene helpers
def asset(name, path, category="Weapons", length=None, notes=""):
    def deco(fn):
        REG[name] = dict(id=name, glb=path, category=category, length=length, notes=notes, build=fn)
        return fn
    return deco


def row_pos(name):
    i = ROW_ORDER.index(name)
    x = i * ROW_SPACING
    if name == "parachute_canopy":
        x += 6.0
    return (x, ROW_Y, 0.0)


def begin(name, category="Weapons"):
    root = K.begin_asset(name, category)
    if category == "Weapons" and name in ROW_ORDER:
        root.location = row_pos(name)
    return root


def mk(root, name, pos, rot=(0.0, 0.0, 0.0)):
    return K.marker(root, name, pos, rot, size=0.03)


def std_markers(root, muzzle, eject, hand_l, scope, under):
    """The six standard firearm markers (identity rotation: marker +Y == weapon forward)."""
    mk(root, "muzzle", muzzle)
    mk(root, "suppressor", muzzle)
    mk(root, "eject", eject)
    mk(root, "hand_l", hand_l)
    mk(root, "scope", scope)
    mk(root, "under", under)


# --------------------------------------------------------------------------- geometry helpers
def _area(pts):
    a = 0.0
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        a += x0 * y1 - x1 * y0
    return a * 0.5


def _inset(pts, d):
    """Inset a CCW 2D polygon by d (mitre joins, clamped at very sharp corners)."""
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
        den = max(0.3, 1.0 + n1.dot(n2))
        off = (n1 + n2) * (d / den)
        out.append((p1.x + off.x, p1.y + off.y))
    return out


def arc_pts(cy, cz, r, a0, a1, n):
    """n+1 points (y, z) on an arc, angles in degrees measured from +Y toward +Z."""
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        out.append((cy + math.cos(a) * r, cz + math.sin(a) * r))
    return out


class GB(K.MB):
    """gta_kit.MB + gun-smithing primitives. Profiles are (y, z) side views, extruded along X."""

    def paint(self, faces, color):
        if PREVIEW:
            color = PREVIEW_MAP.get(color, color)
        K.MB.paint(self, faces, color)

    # ---- profile plate: side-view polygon extruded to width w with chamfered outline
    def plate(self, pts, w, color, x=0.0, ch=0.0):
        pts = [(float(p[0]), float(p[1])) for p in pts]
        if _area(pts) < 0.0:
            pts.reverse()
        hw = w * 0.5
        if ch > 0.0:
            ins = _inset(pts, ch)
            rings = [[(x - hw, p[0], p[1]) for p in ins], [(x - hw + ch, p[0], p[1]) for p in pts],
                     [(x + hw - ch, p[0], p[1]) for p in pts], [(x + hw, p[0], p[1]) for p in ins]]
        else:
            rings = [[(x - hw, p[0], p[1]) for p in pts], [(x + hw, p[0], p[1]) for p in pts]]
        return self.loft(rings, color)

    # ---- hull: chamfered-rectangle cross-sections (XZ) lofted along Y
    def hull(self, st, color, cap_start=True, cap_end=True, ring_colors=None):
        """st = [(y, z_centre, half_w, half_h, chamfer | (ch_top, ch_bottom), x_centre=0), ...]"""
        flat = all((len(s) < 5 or s[4] == 0) for s in st)
        rings = []
        for s in st:
            y, zc, hw, hh = s[0], s[1], s[2], s[3]
            ch = s[4] if len(s) > 4 else 0.0
            xc = s[5] if len(s) > 5 else 0.0
            if flat:
                rings.append([(xc + hw, y, zc - hh), (xc + hw, y, zc + hh), (xc - hw, y, zc + hh), (xc - hw, y, zc - hh)])
                continue
            ct, cb = ch if isinstance(ch, (tuple, list)) else (ch, ch)
            lim = min(hw, hh) * 0.95
            ct = max(0.0004, min(ct, lim))
            cb = max(0.0004, min(cb, lim))
            rings.append([(xc + hw - cb, y, zc - hh), (xc + hw, y, zc - hh + cb), (xc + hw, y, zc + hh - ct),
                          (xc + hw - ct, y, zc + hh), (xc - hw + ct, y, zc + hh), (xc - hw, y, zc + hh - ct),
                          (xc - hw, y, zc - hh + cb), (xc - hw + cb, y, zc - hh)])
        return self.loft(rings, color, cap_start=cap_start, cap_end=cap_end, ring_colors=ring_colors)

    # ---- strap: band of width w (X) and thickness t following an open (y, z) polyline
    def strap(self, pts, w, t, color, x=0.0):
        n = len(pts)
        left, right = [], []
        for i in range(n):
            p = Vector(pts[i])
            if i == 0:
                d = (Vector(pts[1]) - p).normalized()
                k = 1.0
            elif i == n - 1:
                d = (p - Vector(pts[-2])).normalized()
                k = 1.0
            else:
                e1 = (p - Vector(pts[i - 1])).normalized()
                e2 = (Vector(pts[i + 1]) - p).normalized()
                d = (e1 + e2).normalized()
                k = 1.0 / max(0.5, d.dot(e1))
            nrm = Vector((-d.y, d.x)) * (t * 0.5 * k)
            left.append((p.x + nrm.x, p.y + nrm.y))
            right.append((p.x - nrm.x, p.y - nrm.y))
        return self.prism(left + right[::-1], w, color, plane="YZ", pos=(x, 0.0, 0.0))

    # ---- cylinders along Y / X between two coordinates
    def ycyl(self, r, y0, y1, z, color, x=0.0, segs=8, r2=None, flat=False, **kw):
        rot = (0.0, 180.0 / segs, 0.0) if flat else None
        return self.cyl(r, y1 - y0, (x, (y0 + y1) * 0.5, z), color, axis="Y", segs=segs, r2=r2, rot=rot, **kw)

    def xcyl(self, r, x0, x1, y, z, color, segs=8, r2=None, **kw):
        return self.cyl(r, x1 - x0, ((x0 + x1) * 0.5, y, z), color, axis="X", segs=segs, r2=r2, **kw)

    def zcyl(self, r, z0, z1, x, y, color, segs=8, r2=None, **kw):
        return self.cyl(r, z1 - z0, (x, y, (z0 + z1) * 0.5), color, axis="Z", segs=segs, r2=r2, **kw)

    # ---- single n-gon disc facing +axis (flip -> -axis)
    def disc(self, r, pos, color, axis="Y", segs=6, flip=False, rot=0.0):
        pts = []
        for k in range(segs):
            a = 2.0 * math.pi * k / segs + math.radians(rot)
            c, s = math.cos(a) * r, math.sin(a) * r
            if axis == "Y":
                pts.append((pos[0] - c, pos[1], pos[2] + s))
            elif axis == "X":
                pts.append((pos[0], pos[1] + c, pos[2] + s))
            else:
                pts.append((pos[0] + c, pos[1] + s, pos[2]))
        return self.poly(pts, color, flip=flip)

    # ---- accessory rail: a row of teeth standing on z (down=True hangs them under z)
    def rail(self, y0, y1, z, color=A, w=0.020, h=0.008, n=6, fill=0.56, x=0.0, down=False, base=True):
        s = -1.0 if down else 1.0
        L = y1 - y0
        if base:
            bh = h * 0.5
            self.box((w * 0.7, L, bh + 0.001), (x, (y0 + y1) * 0.5, z + s * (bh - 0.001) * 0.5), color)
        p = L / n
        for i in range(n):
            yc = y0 + p * (i + 0.5)
            self.box((w, p * fill, h + 0.001), (x, yc, z + s * (h - 0.001) * 0.5), color)

    # ---- row of identical boxes between two centres (vents, ribs, serrations)
    def row(self, n, p0, p1, size, color="black", rot=None):
        for i in range(n):
            t = 0.5 if n == 1 else i / (n - 1.0)
            pos = tuple(p0[k] + (p1[k] - p0[k]) * t for k in range(3))
            self.box(size, pos, color, rot=rot)

    # ---- lathe: surface of revolution about an axis parallel to Y (axis="Y") or Z (axis="Z")
    def lathe(self, st, color, segs=8, ring_colors=None, c=(0.0, 0.0), axis="Y", smooth=True, caps=True,
              cap_colors=None, rot=0.0, sharp=32.0, scale=(1.0, 1.0)):
        """st = [(t, r), ...] along the axis; c = (x, z) of the axis for axis Y, (x, y) for axis Z.
        Smooth shaded around the axis; profile kinks sharper than `sharp` degrees stay hard.
        scale = (s1, s2) squashes the cross-section (elliptic bodies)."""
        rings = []
        for (t, r) in st:
            ring = []
            for k in range(segs):
                a = 2.0 * math.pi * k / segs + math.radians(rot)
                u, v = math.cos(a) * r * scale[0], math.sin(a) * r * scale[1]
                if axis == "Y":
                    ring.append((c[0] + u, t, c[1] + v))
                else:
                    ring.append((c[0] + u, c[1] + v, t))
            rings.append(ring)
        faces = self.loft(rings, color, closed=True, cap_start=caps, cap_end=caps, smooth=smooth,
                          ring_colors=ring_colors)
        ncap = 2 if caps else 0
        if caps and cap_colors:
            if cap_colors[0]:
                self.paint([faces[-2]], cap_colors[0])
            if cap_colors[1]:
                self.paint([faces[-1]], cap_colors[1])
        if smooth:
            lim = math.radians(sharp)
            ai = 1 if axis == "Y" else 2
            seen = set()
            side = faces[:len(faces) - ncap] if ncap else faces
            for f in side:
                for e in f.edges:
                    if e in seen:
                        continue
                    seen.add(e)
                    if abs(e.verts[0].co[ai] - e.verts[1].co[ai]) > 1e-7 or len(e.link_faces) != 2:
                        continue
                    try:
                        if e.calc_face_angle() > lim:
                            e.smooth = False
                    except ValueError:
                        pass
        return faces

    # ---- bent bar in the YZ plane with per-point radius / flattening and per-segment colours
    def bar_yz(self, pts, r, color, segs=6, x=0.0, colors=None, smooth=False):
        """pts = [(y, z) or (y, z, r_scale, w_x, w_n)]: r_scale scales the radius, w_x / w_n scale the section
        across X / along the in-plane normal (flattened chisel and claw ends)."""
        n = len(pts)
        rings = []
        for i in range(n):
            p = Vector((pts[i][0], pts[i][1]))
            if i == 0:
                d = Vector((pts[1][0], pts[1][1])) - p
            elif i == n - 1:
                d = p - Vector((pts[-2][0], pts[-2][1]))
            else:
                d = (Vector((pts[i + 1][0], pts[i + 1][1])) - p).normalized() + \
                    (p - Vector((pts[i - 1][0], pts[i - 1][1]))).normalized()
            d.normalize()
            nrm = Vector((-d.y, d.x))
            rs = pts[i][2] if len(pts[i]) > 2 else 1.0
            wx = pts[i][3] if len(pts[i]) > 3 else 1.0
            wn = pts[i][4] if len(pts[i]) > 4 else 1.0
            ring = []
            for k in range(segs):
                a = 2.0 * math.pi * k / segs
                cx = math.cos(a) * r * rs * wx
                cn = math.sin(a) * r * rs * wn
                ring.append((x + cx, p.x + nrm.x * cn, p.y + nrm.y * cn))
            rings.append(ring)
        return self.loft(rings, color, closed=True, smooth=smooth, ring_colors=colors)

    # ---- curved trigger blade hanging from (y, z)
    def trigger(self, y, z, h=0.022, w=0.006, color="steel_dark"):
        self.plate([(y - 0.003, z), (y + 0.004, z), (y + 0.0015, z - h * 0.55), (y + 0.005, z - h),
                    (y + 0.001, z - h), (y - 0.004, z - h * 0.5)], w, color)


# --------------------------------------------------------------------------- build / export / manifest
def describe(name):
    root = bpy.data.objects.get(name)
    if root is None or name not in REG:
        return None
    info = REG[name]
    st = K.asset_stats(root)
    parts, origins, markers = [], {}, {}
    kids = sorted(root.children, key=lambda o: o.name)
    for o in kids:
        short = o.name.split("__", 1)[1] if "__" in o.name else o.name
        loc = [round(v, 4) for v in o.location]
        if o.type == "MESH":
            parts.append(short)
            origins[short] = loc
        elif o.type == "EMPTY":
            markers[short] = loc
    parts.sort(key=lambda p: (PART_ORDER.index(p) if p in PART_ORDER else 99, p))
    e = {"id": name, "glb": info["glb"], "category": info["category"], "size": [round(v, 3) for v in st["size"]],
         "tris": st["tris"]}
    if info.get("length") is not None:
        e["length"] = round(st["size"][1], 3)
    e["parts"] = parts
    e["part_origins"] = {p: origins[p] for p in parts}
    e["markers"] = markers
    e["notes"] = info.get("notes", "")
    return e


def write_manifest(path=None, order=None, comment=None):
    """Merge every registered asset that exists in the scene AND has an exported GLB into the manifest."""
    path = path or MANIFEST
    order = order or ROW_ORDER
    data = {"assets": []}
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {"assets": []}
    by_id = {e["id"]: e for e in data.get("assets", [])}
    for name, info in REG.items():
        glb = os.path.join(K.MODELS, info["glb"].replace("/", os.sep) + ".glb")
        if not os.path.exists(glb):
            continue
        e = describe(name)
        if e is not None:
            by_id[name] = e
    ids = sorted(by_id, key=lambda i: (order.index(i) if i in order else 999, i))
    out = {"_comment": comment or (
        "NEON TIDE weapons / attachments / projectiles / pickups / held items. Positions are Blender asset-space "
        "metres (x right, y forward = barrel, z up); Godot = (x, z, -y). Origin = firing-hand grip (palm centre) "
        "unless the notes say otherwise. 'markers' maps marker name -> position, 'part_origins' maps part -> pivot. "
        "GLB node names are '<id>__<part|marker>'. tint_a_metal = main metal, tint_b = furniture."),
        "assets": [by_id[i] for i in ids]}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    return len(ids)


def palette_usage(root):
    """{palette colour name / material: face count} of an asset - verifies the tint contract after a build."""
    if isinstance(root, str):
        root = bpy.data.objects[root]
    pal = K.palette()
    n = pal["size"]
    names = [c[0] for c in pal["colors"]]
    out = {}
    for o in K.asset_objects(root):
        if o.type != "MESH":
            continue
        uv = o.data.uv_layers.active.data if o.data.uv_layers.active else None
        for poly in o.data.polygons:
            mat = o.data.materials[poly.material_index].name if o.data.materials else "?"
            key = mat
            if mat in ("Palette", "PaletteDry", "Foliage") and uv is not None:
                u, v = uv[poly.loop_start].uv
                idx = int((1.0 - v) * n) * n + int(u * n)
                key = names[idx] if idx < len(names) else "?%d" % idx
            out[key] = out.get(key, 0) + 1
    return out


def export_glb(root, rel_path, **kw):
    """K.export_asset with a workaround: Blender 5.2's glTF exporter raises KeyError('loglevel') when
    export_loglevel >= 0 is passed (the kit passes 40), so force the default (-1)."""
    extra = dict(kw.pop("extra", None) or {})
    extra.setdefault("export_loglevel", -1)
    return K.export_asset(root, rel_path, extra=extra, **kw)


PREVIEW_HIDE = ("mag_ext",)   # parts hidden in preview builds so silhouettes read (final builds show everything)


def build(names=None, export=False, preview=False):
    """Build (and optionally export) registered assets. Returns a printable report."""
    global PREVIEW
    do_export = bool(export) and not preview
    if names is None:
        names = list(REG)
    elif isinstance(names, str):
        names = [names]
    PREVIEW = bool(preview)
    out = []
    try:
        for n in names:
            root = REG[n]["build"]()
            if preview:
                for o in root.children:
                    if o.name.split("__", 1)[-1] in PREVIEW_HIDE:
                        o.hide_set(True)
            st = K.asset_stats(root)
            line = "%-22s tris=%4d size=%s min=%s max=%s" % (n, st["tris"], st["size"], st["min"], st["max"])
            if do_export:
                path, size = export_glb(root, REG[n]["glb"])
                line += " -> %s (%d B)" % (REG[n]["glb"], size)
            out.append(line)
    finally:
        PREVIEW = False
    if do_export:
        out.append("manifest entries: %d" % write_manifest())
    return "\n".join(out)


def info(names):
    """Numeric contract check: parts (origin) and markers (position) of each asset."""
    if isinstance(names, str):
        names = [names]
    out = []
    for n in names:
        e = describe(n)
        if e is None:
            out.append("%s: MISSING" % n)
            continue
        out.append("%s tris=%d size=%s" % (n, e["tris"], e["size"]))
        out.append("   parts  : " + ", ".join("%s%s" % (p, tuple(e["part_origins"][p])) for p in e["parts"]))
        out.append("   markers: " + ", ".join("%s%s" % (m, tuple(v)) for m, v in e["markers"].items()))
    return "\n".join(out)


def rack(names, x=-8.0, y=None, dz=0.34, dy=0.0):
    """QA helper: stack assets vertically (same X) so several fit in one side view. unrack() restores the row."""
    y = ROW_Y if y is None else y
    for i, n in enumerate(names):
        o = bpy.data.objects.get(n)
        if o is not None:
            o.location = (x, y + dy * i, 1.0 + dz * (len(names) - 1 - i))


def unrack(names=None):
    for n in (names or ROW_ORDER):
        o = bpy.data.objects.get(n)
        if o is not None and n in ROW_ORDER and o.get("gta_category") == "Weapons":
            o.location = row_pos(n)


def glb_nodes(name):
    """Parse the exported GLB JSON chunk -> {node name: translation} (Y-up glTF space)."""
    import struct
    path = os.path.join(K.MODELS, REG[name]["glb"].replace("/", os.sep) + ".glb")
    with open(path, "rb") as f:
        f.read(12)
        ln, _typ = struct.unpack("<II", f.read(8))
        js = json.loads(f.read(ln).decode("utf-8"))
    return {nd.get("name"): [round(v, 4) for v in nd.get("translation", [0, 0, 0])] for nd in js.get("nodes", [])}


# =========================================================================== FIREARMS
@asset("pistol", "weapons/pistol", length=0.20,
       notes="Compact semi-auto. slide: identity origin, travels -Y ~0.03. mag/mag_ext origin = magazine top inside "
             "the grip (raked ~14 deg, drops along (0,-0.25,-1)).")
def build_pistol():
    root = begin("pistol")
    mb = GB()
    # polymer grip, raked ~14 deg; palm centre = origin
    mb.plate([(0.036, 0.031), (0.013, -0.060), (-0.038, -0.060), (-0.030, -0.025), (-0.024, 0.010), (-0.036, 0.031)],
             0.030, B, ch=0.004)
    for i in range(5):
        z = -0.046 + i * 0.0115
        mb.box((0.0316, 0.028, 0.0035), (0.0, 0.0012 + 0.225 * z, z), "black", rot=(-13.0, 0, 0))
    # frame: beavertail, rails, dust cover
    mb.plate([(-0.046, 0.046), (-0.052, 0.037), (-0.046, 0.030), (-0.024, 0.024), (0.036, 0.024), (0.040, 0.030),
              (0.131, 0.030), (0.138, 0.038), (0.138, 0.046)], 0.026, A, ch=0.003)
    with mb.at((0, 0, 0.030), scale=(1, 1, -1)):
        mb.rail(0.097, 0.134, 0.0, A, w=0.017, h=0.006, n=3, base=False)
    # trigger guard + trigger
    mb.strap([(0.094, 0.031), (0.091, 0.008), (0.083, 0.000), (0.040, 0.000), (0.027, 0.005)], 0.012, 0.0035, A)
    mb.trigger(0.058, 0.031, h=0.022)
    # fixed barrel + recoil-spring guide (mostly hidden inside the slide)
    mb.ycyl(0.0065, 0.030, 0.150, 0.063, "steel_dark", segs=8, cap_color="black")
    mb.ycyl(0.0038, 0.030, 0.1462, 0.0525, "steel", segs=6)
    # controls (left side): slide stop, safety + red dot, magazine release
    mb.box((0.0025, 0.024, 0.0045), (-0.0138, 0.045, 0.040), "steel_dark")
    mb.box((0.003, 0.012, 0.006), (-0.0138, -0.030, 0.040), "steel_dark")
    mb.box((0.0012, 0.004, 0.004), (-0.0134, -0.016, 0.041), "red")
    mb.xcyl(0.004, -0.0172, -0.014, 0.030, 0.012, "steel_dark", segs=6)
    mb.to_object(root, "body")

    sl = GB()
    sl.plate([(-0.050, 0.046), (0.141, 0.046), (0.145, 0.052), (0.145, 0.076), (-0.046, 0.076)], 0.026, A, ch=0.0045)
    sl.box((0.004, 0.007, 0.007), (0.0, 0.134, 0.079), "black", colors={"-y": "led_green"})          # front sight
    sl.box((0.020, 0.010, 0.0025), (0.0, -0.038, 0.0767), "black")                                   # rear sight
    for sx in (-1, 1):
        sl.box((0.005, 0.008, 0.005), (sx * 0.0065, -0.038, 0.080), "black", colors={"-y": "white"})
    sl.box((0.007, 0.036, 0.011), (0.0103, 0.052, 0.0713), "steel")                                  # ejection port
    sl.row(4, (0, -0.040, 0.0612), (0, -0.019, 0.0612), (0.0275, 0.0026, 0.019), "black", rot=(-12.0, 0, 0))
    sl.row(3, (0, 0.104, 0.0612), (0, 0.118, 0.0612), (0.0275, 0.0026, 0.019), "black", rot=(-12.0, 0, 0))
    sl.to_object(root, "slide")

    rake = 0.2527
    top = (0.0, 0.012, 0.030)
    for part, zb in (("mag", -0.058), ("mag_ext", -0.093)):
        mg = GB()
        L = top[2] - zb
        dy = rake * L
        mg.box((0.020, 0.030, L), (0.0, top[1] - dy, (top[2] + zb) * 0.5), "steel_dark", shear=(0.0, dy))
        mg.ycyl(0.0042, top[1] - 0.010, top[1] + 0.012, top[2] + 0.001, "brass", segs=6)
        yb = top[1] - dy
        if part == "mag_ext":   # exposed sleeve below the grip
            mg.box((0.027, 0.036, 0.032), (0.0, yb + 0.001, zb + 0.016), "black", shear=(0.0, rake * 0.032))
        mg.plate([(yb + 0.030, zb - 0.001), (yb + 0.032, zb - 0.008), (yb - 0.028, zb - 0.008), (yb - 0.028, zb - 0.001)],
                 0.031, "black", ch=0.0015)
        mg.to_object(root, part, origin=top)

    std_markers(root, muzzle=(0, 0.150, 0.063), eject=(0.014, 0.052, 0.072), hand_l=(-0.022, 0.012, -0.020),
                scope=(0, 0.010, 0.076), under=(0, 0.1155, 0.024))
    return root


@asset("rifle_assault", "weapons/rifle_assault", length=0.90,
       notes="Assault rifle. bolt (charging handle + carrier, right side): identity origin, travels -Y ~0.05. "
             "mag = 30-rd curved, mag_ext = 45-rd curved; origin = magazine top inside the well.")
def build_rifle_assault():
    root = begin("rifle_assault")
    mb = GB()
    # lower receiver with magazine well
    mb.plate([(-0.085, 0.034), (-0.085, 0.064), (0.205, 0.064), (0.205, 0.036), (0.196, 0.030), (0.140, 0.030),
              (0.136, 0.012), (0.074, 0.012), (0.070, 0.030), (-0.078, 0.030)], 0.040, A, ch=0.004)
    # top cover + rail
    mb.hull([(-0.083, 0.076, 0.017, 0.013, (0.007, 0.001)), (0.200, 0.076, 0.017, 0.013, (0.007, 0.001))], A)
    mb.rail(-0.058, 0.166, 0.089, A, w=0.020, h=0.008, n=7, base=False)
    # rear sight (two posts) behind the rail
    for sx in (-1, 1):
        mb.box((0.005, 0.010, 0.019), (sx * 0.0065, -0.072, 0.098), "steel_dark", colors={"-y": "white"})
    # handguard with vents
    mb.hull([(0.203, 0.066, 0.023, 0.033, 0.009), (0.368, 0.066, 0.023, 0.032, 0.009),
             (0.396, 0.068, 0.019, 0.027, 0.008)], B)
    mb.row(3, (0, 0.238, 0.052), (0, 0.338, 0.052), (0.048, 0.032, 0.007), "black")
    mb.row(3, (0, 0.232, 0.082), (0, 0.332, 0.082), (0.048, 0.018, 0.006), "black")
    mb.box((0.0475, 0.150, 0.002), (0, 0.286, 0.0675), "black")
    # barrel, gas block, front sight, muzzle brake
    mb.ycyl(0.009, 0.390, 0.560, 0.068, "gunmetal", segs=8, caps=False)
    mb.hull([(0.404, 0.076, 0.012, 0.020, 0.005), (0.432, 0.076, 0.012, 0.020, 0.005)], A)
    for sx in (-1, 1):
        mb.plate([(0.406, 0.094), (0.430, 0.094), (0.426, 0.119), (0.418, 0.122), (0.410, 0.119)], 0.003, A,
                 x=sx * 0.0075)
    mb.box((0.003, 0.003, 0.022), (0, 0.418, 0.105), "black", colors={"+z": "led_green", "-y": "led_green"})
    mb.ycyl(0.0125, 0.553, 0.590, 0.068, "steel_dark", segs=8, cap_color="black")
    mb.box((0.0262, 0.008, 0.005), (0, 0.572, 0.068), "black")
    # skeleton stock + butt pad
    mb.plate([(-0.070, 0.086), (-0.297, 0.080), (-0.297, -0.028), (-0.280, -0.034), (-0.070, 0.030), (-0.070, 0.046),
              (-0.262, -0.004), (-0.268, 0.056), (-0.070, 0.064)], 0.034, B, ch=0.005)
    mb.box((0.036, 0.013, 0.112), (0, -0.3035, 0.025), "rubber")
    # pistol grip + ribs
    mb.plate([(0.030, 0.034), (0.002, -0.066), (-0.040, -0.062), (-0.024, -0.005), (-0.016, 0.034)], 0.030, B, ch=0.005)
    for z in (-0.045, -0.026):
        mb.box((0.0316, 0.026, 0.004), (0, -0.001 + 0.282 * z, z), "black", rot=(-16.0, 0, 0))
    # trigger group
    mb.strap([(0.072, 0.014), (0.068, 0.002), (0.036, 0.000), (0.022, 0.008)], 0.012, 0.003, A)
    mb.trigger(0.048, 0.031, h=0.022)
    # ejection port / charging-handle track (right), selector (left), sling plates
    mb.box((0.002, 0.110, 0.015), (0.0172, 0.080, 0.074), "black")
    mb.box((0.003, 0.018, 0.005), (-0.0205, 0.012, 0.046), "steel_dark", rot=(20.0, 0, 0))
    mb.box((0.001, 0.004, 0.004), (-0.0203, 0.030, 0.050), "red")
    mb.box((0.004, 0.014, 0.010), (-0.0185, -0.283, 0.066), "steel_dark")
    mb.to_object(root, "body")

    bt = GB()
    bt.box((0.0035, 0.060, 0.013), (0.01775, 0.105, 0.074), "steel")
    bt.xcyl(0.0045, 0.0185, 0.036, 0.128, 0.074, "steel_dark", segs=6)
    bt.to_object(root, "bolt")

    top = (0.0, 0.105, 0.028)
    R = 0.30
    for part, theta, n in (("mag", 33.4, 3), ("mag_ext", 46.0, 4)):
        mg = GB()
        cy, cz = top[1] + R, top[2]
        rear = arc_pts(cy, cz, R + 0.028, 180.0, 180.0 + theta, n)
        front = arc_pts(cy, cz, R - 0.028, 180.0, 180.0 + theta, n)
        mg.plate(rear + front[::-1], 0.024, "steel_dark", ch=0.003)
        a = math.radians(180.0 + theta)
        mg.box((0.027, 0.062, 0.006), (0, cy + math.cos(a) * R, cz + math.sin(a) * R), "black", rot=(theta, 0, 0))
        mg.to_object(root, part, origin=top)

    std_markers(root, muzzle=(0, 0.590, 0.068), eject=(0.019, 0.105, 0.074), hand_l=(0, 0.300, 0.033),
                scope=(0, 0.054, 0.097), under=(0, 0.300, 0.033))
    return root


@asset("revolver", "weapons/revolver", length=0.27,
       notes="Heavy 6-shot revolver, 0.15 m barrel with full under-lug, wood grip. cylinder: origin on its axis "
             "(parallel to Y), spins about Y, 60 deg per shot. No real ejection port: 'eject' sits at the cylinder.")
def build_revolver():
    root = begin("revolver")
    mb = GB()
    # frame: U around the cylinder window (recoil shield, bottom strap, front post)
    mb.plate([(0.022, 0.094), (0.004, 0.090), (-0.010, 0.076), (-0.016, 0.056), (-0.012, 0.036), (0.000, 0.022),
              (0.030, 0.024), (0.080, 0.028), (0.088, 0.036), (0.088, 0.094), (0.077, 0.094), (0.077, 0.040),
              (0.033, 0.040), (0.033, 0.094)], 0.020, A, ch=0.003)
    mb.hull([(0.020, 0.0905, 0.007, 0.0065, 0.002), (0.090, 0.0905, 0.007, 0.0065, 0.002)], A)       # top strap
    for sx in (-1, 1):                                                                             # rear sight
        mb.box((0.004, 0.008, 0.005), (sx * 0.005, 0.026, 0.099), "black", colors={"-y": "white"})
    # barrel, under-lug, top rib, ramp front sight
    mb.ycyl(0.0115, 0.086, 0.226, 0.0745, A, segs=8, flat=True, cap_color="black")
    mb.hull([(0.086, 0.054, 0.008, 0.011, 0.003), (0.212, 0.054, 0.008, 0.011, 0.003),
             (0.223, 0.057, 0.006, 0.007, 0.003)], A)
    mb.hull([(0.088, 0.088, 0.004, 0.004, 0.001), (0.224, 0.088, 0.004, 0.004, 0.001)], A)
    mb.plate([(0.194, 0.0915), (0.223, 0.0915), (0.223, 0.1015), (0.216, 0.1015)], 0.0045, "black")
    mb.box((0.005, 0.004, 0.003), (0, 0.2165, 0.1008), "led_green")
    # trigger group, hammer
    mb.strap([(0.080, 0.030), (0.078, 0.006), (0.068, -0.004), (0.040, -0.004), (0.026, 0.006)], 0.010, 0.0035, A)
    mb.trigger(0.052, 0.029, h=0.024)
    mb.plate([(0.016, 0.084), (0.018, 0.100), (0.004, 0.110), (-0.008, 0.108), (-0.004, 0.102), (0.006, 0.098),
              (0.004, 0.084)], 0.007, "steel_dark")
    # wood grip with brass screw; cylinder latch (left)
    mb.plate([(0.030, 0.026), (0.020, 0.000), (0.011, -0.040), (0.010, -0.070), (-0.044, -0.066), (-0.036, -0.030),
              (-0.027, 0.000), (-0.020, 0.030), (-0.018, 0.048), (-0.004, 0.040)], 0.028, "wood_mid", ch=0.007)
    mb.xcyl(0.0032, -0.0148, 0.0148, -0.010, -0.014, "brass", segs=6)
    mb.box((0.003, 0.012, 0.008), (-0.0105, 0.022, 0.060), "steel_dark")
    mb.to_object(root, "body")

    cy = GB()
    y0, y1, zc, rc = 0.0345, 0.0755, 0.062, 0.021
    rings = []
    for (y, rin) in ((y0, rc), (y0 + 0.014, rc), (y1, 0.0165)):
        ring = []
        for k in range(12):
            a = math.radians(90.0 + 30.0 * k)
            r = rc if k % 2 == 0 else rin
            ring.append((math.cos(a) * r, y, zc + math.sin(a) * r))
        rings.append(ring)
    cy.loft(rings, A)
    for k in range(6):
        a = math.radians(90.0 + 60.0 * k)
        cy.disc(0.0046, (math.cos(a) * 0.0125, y1 + 0.0007, zc + math.sin(a) * 0.0125), "black", axis="Y", segs=6)
    cy.to_object(root, "cylinder", origin=(0.0, (y0 + y1) * 0.5, zc), sharp_angle=40)

    std_markers(root, muzzle=(0, 0.226, 0.0745), eject=(0.022, 0.055, 0.062), hand_l=(-0.020, 0.006, -0.024),
                scope=(0, 0.055, 0.097), under=(0, 0.150, 0.043))
    return root


@asset("smg", "weapons/smg", length=0.46,
       notes="Compact SMG, telescoping wire stock modelled retracted. bolt (cocking handle + carrier, right side): "
             "identity origin, travels -Y ~0.05. mag = stick, mag_ext = long stick; origin = magazine top in the well.")
def build_smg():
    root = begin("smg")
    mb = GB()
    # boxy upper receiver
    mb.plate([(-0.115, 0.042), (0.200, 0.042), (0.200, 0.088), (0.192, 0.096), (-0.107, 0.096), (-0.115, 0.088)],
             0.042, A, ch=0.005)
    # polymer lower with magazine well
    mb.plate([(-0.050, 0.044), (-0.046, 0.030), (-0.020, 0.024), (0.030, 0.024), (0.036, 0.030), (0.080, 0.030),
              (0.084, -0.012), (0.136, -0.006), (0.140, 0.030), (0.190, 0.034), (0.196, 0.044)], 0.036, B, ch=0.004)
    # pistol grip + ribs
    mb.plate([(0.030, 0.028), (0.006, -0.066), (-0.036, -0.062), (-0.022, -0.004), (-0.016, 0.028)], 0.030, B, ch=0.005)
    for z in (-0.044, -0.026):
        mb.box((0.0316, 0.026, 0.004), (0, 0.001 + 0.25 * z, z), "black", rot=(-14.0, 0, 0))
    mb.strap([(0.085, 0.002), (0.040, 0.000), (0.026, 0.008)], 0.012, 0.003, B)
    mb.trigger(0.054, 0.031, h=0.022)
    # stubby handguard with vents + short under-rail
    mb.hull([(0.198, 0.062, 0.019, 0.022, 0.007), (0.250, 0.062, 0.019, 0.021, 0.007),
             (0.272, 0.064, 0.015, 0.016, 0.006)], B)
    mb.row(2, (0, 0.216, 0.068), (0, 0.240, 0.068), (0.040, 0.014, 0.007), "black")
    with mb.at((0, 0, 0.0405), scale=(1, 1, -1)):
        mb.rail(0.204, 0.262, 0.0, B, w=0.018, h=0.006, n=3, base=False)
    # barrel + muzzle ring
    mb.ycyl(0.008, 0.262, 0.310, 0.066, "gunmetal", segs=8, cap_color="black")
    mb.ycyl(0.0105, 0.292, 0.3085, 0.066, "steel_dark", segs=8)
    # top rail + sights
    mb.rail(-0.085, 0.178, 0.096, A, w=0.020, h=0.008, n=8, base=False)
    mb.plate([(0.183, 0.096), (0.197, 0.096), (0.194, 0.118), (0.186, 0.118)], 0.004, "steel_dark")
    for sx in (-1, 1):
        mb.plate([(0.183, 0.096), (0.197, 0.096), (0.196, 0.113), (0.190, 0.120), (0.184, 0.113)], 0.0025, A,
                 x=sx * 0.0075)
        mb.box((0.005, 0.010, 0.018), (sx * 0.0065, -0.098, 0.105), "steel_dark", colors={"-y": "white"})
    # retracted wire stock: rods along the receiver, guide brackets, butt plate
    for sx in (-1, 1):
        mb.ycyl(0.003, -0.142, 0.060, 0.062, "steel", x=sx * 0.0245, segs=6)
        mb.box((0.008, 0.014, 0.012), (sx * 0.0235, -0.085, 0.062), A)
        mb.box((0.008, 0.014, 0.012), (sx * 0.0235, 0.040, 0.062), A)
    mb.plate([(-0.140, 0.100), (-0.150, 0.096), (-0.150, 0.016), (-0.140, 0.010)], 0.058, "steel_dark", ch=0.003)
    mb.box((0.050, 0.004, 0.070), (0, -0.1505, 0.056), "rubber")
    # ejection port / handle track (right), selector (left)
    mb.box((0.002, 0.100, 0.016), (0.0212, 0.075, 0.078), "black")
    mb.box((0.003, 0.016, 0.005), (-0.0185, 0.010, 0.036), "steel_dark", rot=(25.0, 0, 0))
    mb.box((0.001, 0.004, 0.004), (-0.0183, 0.026, 0.038), "red")
    mb.to_object(root, "body")

    bt = GB()
    bt.box((0.0035, 0.050, 0.013), (0.0218, 0.100, 0.078), "steel")
    bt.xcyl(0.0045, 0.0225, 0.040, 0.118, 0.078, "steel_dark", segs=6)
    bt.to_object(root, "bolt")

    top = (0.0, 0.110, 0.012)
    for part, L in (("mag", 0.150), ("mag_ext", 0.215)):
        mg = GB()
        dy = 0.06 * L
        mg.box((0.022, 0.034, L), (0, top[1] + dy, top[2] - L * 0.5), "steel_dark", shear=(0.0, -dy))
        mg.box((0.026, 0.040, 0.006), (0, top[1] + dy, top[2] - L - 0.002), "black")
        mg.ycyl(0.0045, top[1] - 0.012, top[1] + 0.012, top[2] + 0.001, "brass", segs=6)
        mg.to_object(root, part, origin=top)

    std_markers(root, muzzle=(0, 0.310, 0.066), eject=(0.022, 0.100, 0.078), hand_l=(0, 0.233, 0.034),
                scope=(0, 0.0465, 0.104), under=(0, 0.233, 0.0345))
    return root


@asset("shotgun_pump", "weapons/shotgun_pump", length=1.00,
       notes="Pump shotgun, wood furniture; origin at the wrist of the stock (semi-pistol grip). pump: identity origin, "
             "racks along -Y by 0.085 and returns. hand_l is under the pump.")
def build_shotgun_pump():
    root = begin("shotgun_pump")
    mb = GB()
    # receiver + sighting rib
    mb.plate([(0.262, 0.010), (0.262, 0.074), (0.256, 0.080), (0.062, 0.080), (0.038, 0.066), (0.030, 0.040),
              (0.040, 0.010)], 0.040, A, ch=0.005)
    mb.hull([(0.070, 0.0815, 0.006, 0.0025, 0.001), (0.250, 0.0815, 0.006, 0.0025, 0.001)], A)
    # barrel, magazine tube + cap, barrel band, bead sight
    mb.ycyl(0.0105, 0.255, 0.720, 0.062, "gunmetal", segs=8, cap_color="black")
    mb.ycyl(0.0110, 0.255, 0.602, 0.036, "gunmetal", segs=8)
    mb.ycyl(0.0125, 0.598, 0.614, 0.036, "steel_dark", segs=8)
    mb.hull([(0.576, 0.049, 0.013, 0.027, 0.006), (0.590, 0.049, 0.013, 0.027, 0.006)], A)
    mb.box((0.0035, 0.005, 0.005), (0, 0.712, 0.0735), "brass")
    # wood stock with semi-pistol grip + rubber recoil pad
    mb.plate([(0.060, 0.052), (0.030, 0.040), (0.000, 0.022), (-0.045, 0.018), (-0.070, 0.030), (-0.268, 0.014),
              (-0.268, -0.112), (-0.090, -0.040), (-0.040, -0.040), (-0.012, -0.046), (0.010, -0.020), (0.040, 0.004),
              (0.060, 0.010)], 0.038, "wood_mid", ch=0.008)
    mb.plate([(-0.268, 0.016), (-0.280, 0.014), (-0.280, -0.112), (-0.268, -0.114)], 0.040, "rubber", ch=0.004)
    # trigger group
    mb.strap([(0.128, 0.011), (0.125, -0.012), (0.114, -0.020), (0.074, -0.020), (0.056, -0.004), (0.050, 0.010)],
             0.012, 0.0035, A)
    mb.trigger(0.090, 0.011, h=0.024)
    # ejection port with bolt (right), loading port (bottom), sling studs
    mb.box((0.002, 0.075, 0.024), (0.0202, 0.170, 0.055), "black")
    mb.box((0.002, 0.050, 0.016), (0.0208, 0.178, 0.055), "steel")
    mb.box((0.024, 0.075, 0.002), (0, 0.205, 0.0098), "black")
    mb.box((0.005, 0.010, 0.010), (0, -0.200, -0.088), "steel_dark")
    mb.box((0.005, 0.010, 0.008), (0, 0.606, 0.021), "steel_dark")
    mb.to_object(root, "body")

    pm = GB()
    pm.hull([(0.345, 0.032, 0.021, 0.016, 0.007), (0.360, 0.032, 0.024, 0.019, 0.008),
             (0.500, 0.032, 0.024, 0.019, 0.008), (0.515, 0.032, 0.021, 0.016, 0.007)], "wood_mid")
    pm.row(5, (0, 0.385, 0.032), (0, 0.475, 0.032), (0.0492, 0.005, 0.020), "wood_dark")
    for sx in (-1, 1):
        pm.box((0.003, 0.100, 0.007), (sx * 0.0135, 0.300, 0.040), "steel")
    pm.to_object(root, "pump")

    std_markers(root, muzzle=(0, 0.720, 0.062), eject=(0.021, 0.170, 0.055), hand_l=(0, 0.430, 0.013),
                scope=(0, 0.160, 0.084), under=(0, 0.555, 0.025))
    return root


@asset("shotgun_auto", "weapons/shotgun_auto", length=0.95,
       notes="Semi-auto combat shotgun, polymer stock + pistol grip, perforated heat shield. mag = 8-rd box, "
             "mag_ext = drum (axis along Y); origin = magazine top in the well. Charging handle is static (body).")
def build_shotgun_auto():
    root = begin("shotgun_auto")
    mb = GB()
    # receiver with big magazine well + top rail
    mb.plate([(-0.062, 0.034), (-0.062, 0.097), (0.204, 0.097), (0.204, 0.036),
              (0.196, 0.030), (0.170, 0.030), (0.166, 0.002), (0.078, 0.002), (0.074, 0.030), (-0.056, 0.030)],
             0.044, A, ch=0.005)
    mb.rail(-0.038, 0.182, 0.097, A, w=0.021, h=0.008, n=6, base=False)
    # fixed polymer stock, cheek riser, recoil pad, sling slot
    mb.plate([(-0.050, 0.090), (-0.286, 0.086), (-0.286, -0.022), (-0.262, -0.030), (-0.130, 0.018), (-0.050, 0.032)],
             0.038, B, ch=0.007)
    mb.hull([(-0.250, 0.094, 0.013, 0.007, 0.004), (-0.120, 0.095, 0.013, 0.007, 0.004)], B)
    mb.box((0.040, 0.014, 0.112), (0, -0.293, 0.031), "rubber")
    mb.box((0.040, 0.030, 0.008), (0, -0.252, 0.060), "black")
    # pistol grip + trigger group
    mb.plate([(0.030, 0.034), (0.002, -0.068), (-0.040, -0.064), (-0.024, -0.005), (-0.016, 0.034)], 0.030, B, ch=0.005)
    for z in (-0.046, -0.027):
        mb.box((0.0316, 0.026, 0.004), (0, -0.001 + 0.282 * z, z), "black", rot=(-16.0, 0, 0))
    mb.strap([(0.077, 0.006), (0.040, 0.000), (0.024, 0.008)], 0.012, 0.003, A)
    mb.trigger(0.050, 0.031, h=0.022)
    # handguard with grip grooves + under rail
    mb.hull([(0.202, 0.058, 0.024, 0.027, 0.008), (0.400, 0.058, 0.024, 0.026, 0.008),
             (0.440, 0.060, 0.020, 0.021, 0.007)], B)
    mb.row(3, (0, 0.242, 0.052), (0, 0.372, 0.052), (0.050, 0.034, 0.006), "black")
    with mb.at((0, 0, 0.0315), scale=(1, 1, -1)):
        mb.rail(0.296, 0.386, 0.0, B, w=0.020, h=0.007, n=3, base=False)
    # barrel, perforated heat shield, gas cylinder, barrel band, muzzle device
    mb.ycyl(0.0115, 0.200, 0.640, 0.072, "gunmetal", segs=8, caps=False)
    mb.hull([(0.206, 0.086, 0.017, 0.008, (0.006, 0.001)), (0.560, 0.086, 0.017, 0.008, (0.006, 0.001))], A)
    mb.row(5, (0, 0.262, 0.0887), (0, 0.522, 0.0887), (0.036, 0.022, 0.012), "black")
    mb.ycyl(0.008, 0.438, 0.530, 0.050, "gunmetal", segs=6, caps=False)
    mb.hull([(0.524, 0.062, 0.010, 0.023, 0.004), (0.540, 0.062, 0.010, 0.023, 0.004)], A)
    mb.ycyl(0.0155, 0.612, 0.650, 0.072, "steel_dark", segs=8, cap_color="black")
    # sights: front blade on the shield, rear posts behind the rail
    mb.plate([(0.540, 0.093), (0.558, 0.093), (0.554, 0.116), (0.546, 0.116)], 0.005, "steel_dark")
    mb.box((0.0055, 0.003, 0.004), (0, 0.5475, 0.1145), "led_green")
    for sx in (-1, 1):
        mb.box((0.004, 0.008, 0.016), (sx * 0.007, -0.050, 0.105), "steel_dark", colors={"-y": "white"})
    # ejection port + charging handle (right), bolt release + safety dot (left)
    mb.box((0.002, 0.090, 0.020), (0.0222, 0.120, 0.070), "black")
    mb.box((0.003, 0.055, 0.014), (0.0228, 0.135, 0.070), "steel")
    mb.xcyl(0.0045, 0.022, 0.038, 0.150, 0.070, "steel_dark", segs=6)
    mb.box((0.001, 0.004, 0.004), (-0.0223, 0.030, 0.050), "red")
    mb.to_object(root, "body")

    top = (0.0, 0.122, 0.018)
    mg = GB()
    L = 0.135
    dy = 0.10 * L
    mg.box((0.038, 0.078, L), (0, top[1] + dy, top[2] - L * 0.5), "charcoal", shear=(0.0, -dy), bevel=0.004)
    for i in range(2):
        z = top[2] - 0.055 - i * 0.040
        mg.box((0.040, 0.060, 0.004), (0, top[1] + dy * (top[2] - z) / L, z), "black")
    mg.to_object(root, "mag", origin=top)

    dm = GB()
    dm.box((0.036, 0.074, 0.050), (0, top[1], top[2] - 0.025), "charcoal")
    zc = top[2] - 0.088
    dm.ycyl(0.062, top[1] - 0.044, top[1] + 0.044, zc, "charcoal", segs=12)
    dm.ycyl(0.022, top[1] + 0.040, top[1] + 0.049, zc, "steel_dark", segs=6)
    dm.to_object(root, "mag_ext", origin=top)

    std_markers(root, muzzle=(0, 0.650, 0.072), eject=(0.023, 0.120, 0.070), hand_l=(0, 0.320, 0.031),
                scope=(0, 0.072, 0.105), under=(0, 0.341, 0.0245))
    return root


@asset("rifle_carbine", "weapons/rifle_carbine", length=0.80,
       notes="Bullpup carbine: magazine BEHIND the pistol grip, full-hand guard loop, long flat-top rail. bolt = "
             "carrier in the rear ejection port (right) + forward charging knob (left): identity origin, travels -Y "
             "~0.05. mag/mag_ext origin = magazine top in the well.")
def build_rifle_carbine():
    root = begin("rifle_carbine")
    mb = GB()
    # one-piece polymer shell: butt, magazine well, fore-end
    mb.plate([(-0.348, 0.102), (-0.348, -0.030), (-0.230, -0.018), (-0.118, -0.010), (-0.112, 0.026), (0.096, 0.026),
              (0.104, 0.010), (0.230, 0.020), (0.262, 0.044), (0.262, 0.088), (0.244, 0.102)], 0.046, B, ch=0.006)
    mb.plate([(-0.348, 0.104), (-0.360, 0.100), (-0.360, -0.030), (-0.348, -0.032)], 0.048, "rubber", ch=0.004)
    # metal: top spine + rail, receiver side panels showing through the shell
    mb.hull([(-0.300, 0.106, 0.014, 0.008, 0.004), (0.250, 0.106, 0.014, 0.008, 0.004)], A)
    mb.rail(-0.108, 0.200, 0.114, A, w=0.020, h=0.008, n=8, base=False)
    mb.plate([(-0.292, 0.048), (-0.140, 0.048), (-0.132, 0.058), (-0.132, 0.088), (-0.292, 0.088)], 0.0495, A, ch=0.002)
    mb.hull([(-0.290, 0.1155, 0.012, 0.0035, 0.002), (-0.165, 0.1155, 0.012, 0.0035, 0.002)], "rubber")   # cheek pad
    # pistol grip, hand loop, trigger
    mb.plate([(0.030, 0.030), (0.006, -0.068), (-0.038, -0.064), (-0.024, -0.004), (-0.018, 0.030)], 0.030, B, ch=0.005)
    for z in (-0.046, -0.028):
        mb.box((0.0316, 0.026, 0.004), (0, 0.003 + 0.25 * z, z), "black", rot=(-14.0, 0, 0))
    mb.strap([(0.004, -0.0650), (0.074, -0.060), (0.098, -0.038), (0.106, 0.012)], 0.016, 0.007, B)
    mb.trigger(0.052, 0.027, h=0.022)
    # fore-end vents + angled under rail
    mb.row(3, (0, 0.150, 0.066), (0, 0.222, 0.066), (0.048, 0.022, 0.007), "black", rot=(24.0, 0, 0))
    with mb.at((0, 0.1725, 0.0152), rot=(4.5, 0, 0), scale=(1, 1, -1)):
        mb.rail(-0.040, 0.040, 0.0, B, w=0.019, h=0.007, n=3, base=False)
    # barrel + flash hider
    mb.ycyl(0.0085, 0.255, 0.418, 0.070, "gunmetal", segs=8, caps=False)
    mb.ycyl(0.0115, 0.404, 0.440, 0.070, "steel_dark", segs=8, cap_color="black")
    mb.box((0.0242, 0.009, 0.005), (0, 0.423, 0.070), "black")
    # flip-up sights on the spine
    mb.plate([(0.208, 0.114), (0.224, 0.114), (0.221, 0.136), (0.212, 0.136)], 0.005, "steel_dark")
    mb.box((0.0055, 0.003, 0.004), (0, 0.2135, 0.1345), "led_green")
    for sx in (-1, 1):
        mb.box((0.004, 0.008, 0.020), (sx * 0.0065, -0.122, 0.124), "steel_dark", colors={"-y": "white"})
    # ejection port (right rear), charging-handle track (left front), selector, sling slot
    mb.box((0.002, 0.070, 0.018), (0.0252, -0.190, 0.074), "black")
    mb.box((0.002, 0.100, 0.006), (-0.0143, 0.110, 0.106), "black")
    mb.box((0.003, 0.016, 0.005), (-0.0235, 0.010, 0.040), "steel_dark", rot=(25.0, 0, 0))
    mb.box((0.001, 0.004, 0.004), (-0.0233, 0.028, 0.042), "red")
    mb.box((0.048, 0.008, 0.026), (0, -0.322, 0.066), "black")
    mb.to_object(root, "body")

    bt = GB()
    bt.box((0.003, 0.040, 0.014), (0.0258, -0.174, 0.074), "steel")
    bt.xcyl(0.005, -0.031, -0.0135, 0.152, 0.106, "steel_dark", segs=6)
    bt.to_object(root, "bolt")

    top = (0.0, -0.155, 0.020)
    R = 0.50
    for part, L, n in (("mag", 0.165, 3), ("mag_ext", 0.230, 4)):
        mg = GB()
        theta = math.degrees(L / R)
        cy_, cz_ = top[1] + R, top[2]
        rear = arc_pts(cy_, cz_, R + 0.029, 180.0, 180.0 + theta, n)
        front = arc_pts(cy_, cz_, R - 0.029, 180.0, 180.0 + theta, n)
        mg.plate(rear + front[::-1], 0.024, "steel_dark", ch=0.003)
        a = math.radians(180.0 + theta)
        mg.box((0.027, 0.064, 0.006), (0, cy_ + math.cos(a) * R, cz_ + math.sin(a) * R), "black", rot=(theta, 0, 0))
        mg.to_object(root, part, origin=top)

    std_markers(root, muzzle=(0, 0.440, 0.070), eject=(0.027, -0.185, 0.074), hand_l=(0, 0.172, 0.010),
                scope=(0, 0.046, 0.122), under=(0, 0.1725, 0.0082))
    return root


@asset("rifle_marksman", "weapons/rifle_marksman", length=1.10,
       notes="Semi-auto marksman rifle, wood thumbhole stock, ventilated upper handguard, folded bipod stubs. bolt "
             "(handle + carrier, right side): identity origin, travels -Y ~0.05. mag = 10-rd, mag_ext = 20-rd.")
def build_rifle_marksman():
    root = begin("rifle_marksman")
    mb = GB()
    W = "wood_mid"
    # receiver + rail
    mb.plate([(-0.062, 0.038), (-0.062, 0.084), (-0.054, 0.092), (0.212, 0.092), (0.222, 0.084), (0.222, 0.038),
              (0.214, 0.032), (0.150, 0.032), (0.146, 0.016), (0.078, 0.016), (0.074, 0.032), (-0.056, 0.032)],
             0.040, A, ch=0.004)
    mb.rail(-0.040, 0.200, 0.092, A, w=0.020, h=0.008, n=8, base=False)
    for sx in (-1, 1):
        mb.box((0.004, 0.007, 0.016), (sx * 0.0065, -0.049, 0.100), "steel_dark", colors={"-y": "white"})
    # wood thumbhole stock (C-shape closed by the grip), cheek riser, recoil pad
    mb.plate([(-0.050, 0.090), (-0.345, 0.084), (-0.345, -0.046), (-0.305, -0.056), (-0.040, -0.068), (-0.034, -0.046),
              (-0.292, -0.026), (-0.308, 0.000), (-0.308, 0.040), (-0.292, 0.054), (-0.050, 0.056)], 0.034, W, ch=0.006)
    mb.hull([(-0.270, 0.095, 0.012, 0.006, 0.004), (-0.120, 0.096, 0.012, 0.006, 0.004)], "wood_dark")
    mb.plate([(-0.345, 0.086), (-0.357, 0.083), (-0.357, -0.046), (-0.345, -0.050)], 0.036, "rubber", ch=0.003)
    mb.plate([(0.028, 0.034), (0.004, -0.068), (-0.040, -0.066), (-0.026, -0.006), (-0.022, 0.034)], 0.036, W, ch=0.007)
    # trigger group
    mb.strap([(0.076, 0.018), (0.072, 0.004), (0.036, 0.002), (0.024, 0.010)], 0.012, 0.003, A)
    mb.trigger(0.050, 0.033, h=0.022)
    # wood lower handguard, ventilated metal upper
    mb.hull([(0.220, 0.052, 0.022, 0.021, 0.008), (0.440, 0.052, 0.021, 0.019, 0.008),
             (0.500, 0.054, 0.017, 0.014, 0.006)], W)
    mb.hull([(0.222, 0.082, 0.014, 0.010, (0.006, 0.001)), (0.400, 0.082, 0.014, 0.010, (0.006, 0.001))], A)
    mb.row(4, (0, 0.250, 0.084), (0, 0.372, 0.084), (0.030, 0.022, 0.006), "black")
    # barrel, gas block + front sight, muzzle brake
    mb.ycyl(0.009, 0.395, 0.705, 0.070, "gunmetal", segs=8, caps=False)
    mb.hull([(0.545, 0.074, 0.011, 0.016, 0.004), (0.570, 0.074, 0.011, 0.016, 0.004)], A)
    for sx in (-1, 1):
        mb.plate([(0.546, 0.089), (0.569, 0.089), (0.566, 0.113), (0.5575, 0.117), (0.549, 0.113)], 0.003, A,
                 x=sx * 0.007)
    mb.box((0.003, 0.003, 0.022), (0, 0.5575, 0.100), "black", colors={"+z": "led_green", "-y": "led_green"})
    mb.ycyl(0.012, 0.695, 0.743, 0.070, "steel_dark", segs=8, cap_color="black")
    mb.row(2, (0, 0.710, 0.070), (0, 0.726, 0.070), (0.0252, 0.007, 0.005), "black")
    # folded bipod stubs
    mb.box((0.034, 0.016, 0.012), (0, 0.488, 0.035), "steel_dark")
    for sx in (-1, 1):
        mb.ycyl(0.0055, 0.376, 0.492, 0.026, "steel_dark", x=sx * 0.012, segs=6, cap_color="rubber")
    # ejection port / handle track (right), safety (left), sling studs
    mb.box((0.002, 0.100, 0.016), (0.0202, 0.085, 0.074), "black")
    mb.box((0.003, 0.016, 0.005), (-0.0205, 0.012, 0.046), "steel_dark", rot=(20.0, 0, 0))
    mb.box((0.001, 0.004, 0.004), (-0.0203, 0.030, 0.050), "red")
    mb.box((0.005, 0.010, 0.008), (0, -0.300, -0.060), "steel_dark")
    mb.to_object(root, "body")

    bt = GB()
    bt.box((0.003, 0.052, 0.013), (0.0208, 0.109, 0.074), "steel")
    bt.xcyl(0.0045, 0.021, 0.038, 0.128, 0.074, "steel_dark", segs=6)
    bt.to_object(root, "bolt")

    top = (0.0, 0.112, 0.030)
    for part, L in (("mag", 0.082), ("mag_ext", 0.150)):
        mg = GB()
        dy = 0.12 * L
        mg.box((0.026, 0.062, L), (0, top[1] + dy, top[2] - L * 0.5), "steel_dark", shear=(0.0, -dy))
        mg.box((0.029, 0.066, 0.006), (0, top[1] + dy, top[2] - L - 0.001), "black")
        mg.to_object(root, part, origin=top)

    std_markers(root, muzzle=(0, 0.743, 0.070), eject=(0.021, 0.100, 0.074), hand_l=(0, 0.330, 0.031),
                scope=(0, 0.080, 0.100), under=(0, 0.300, 0.031))
    return root


@asset("rifle_sniper", "weapons/rifle_sniper", length=1.25,
       notes="Bolt-action sniper rifle, chassis stock with adjustable cheek rest + butt hook, fluted heavy barrel, "
             "muzzle brake. bolt: origin ON the bolt axis (0,0,0.075): rotate about Y to lift the handle, translate "
             "-Y up to 0.09 to cycle. mag origin = magazine top in the well. Scope is an attachment (scope marker).")
def build_rifle_sniper():
    root = begin("rifle_sniper")
    mb = GB()
    zb = 0.075
    # tubular receiver + rail
    mb.hull([(-0.085, zb, 0.018, 0.018, 0.008), (0.200, zb, 0.018, 0.018, 0.008)], A)
    mb.rail(-0.062, 0.194, 0.093, A, w=0.020, h=0.008, n=8, base=False)
    # chassis fore-end with slots + under rail
    mb.hull([(-0.070, 0.040, 0.021, 0.018, 0.006), (0.440, 0.040, 0.021, 0.016, 0.006),
             (0.472, 0.043, 0.017, 0.011, 0.005)], B)
    mb.row(4, (0, 0.250, 0.041), (0, 0.415, 0.041), (0.044, 0.032, 0.006), "black")
    with mb.at((0, 0, 0.0245), scale=(1, 1, -1)):
        mb.rail(0.350, 0.435, 0.0, B, w=0.019, h=0.007, n=3, base=False)
    # heavy fluted barrel + muzzle brake
    mb.ycyl(0.0135, 0.195, 0.805, zb, "gunmetal", segs=8, flat=True, caps=False)
    d = 0.0125
    for phi in (45.0, 135.0, 225.0, 315.0):
        a = math.radians(phi)
        mb.box((0.0045, 0.460, 0.0016), (math.cos(a) * d, 0.500, zb + math.sin(a) * d), "black",
               rot=(0, 90.0 - phi, 0))
    mb.hull([(0.795, zb, 0.016, 0.0125, 0.004), (0.850, zb, 0.016, 0.0125, 0.004)], "steel_dark")
    mb.row(2, (0, 0.812, zb), (0, 0.832, zb), (0.034, 0.008, 0.012), "black")
    mb.disc(0.0065, (0, 0.8508, zb), "black", axis="Y", segs=8)
    # skeleton stock: spine, cheek rest on posts, adjustable butt plate on rods, butt hook
    mb.hull([(-0.350, 0.046, 0.014, 0.014, 0.005), (-0.070, 0.046, 0.016, 0.016, 0.005)], B)
    mb.hull([(-0.290, 0.090, 0.016, 0.011, (0.007, 0.002)), (-0.140, 0.090, 0.016, 0.011, (0.007, 0.002))], B)
    for y in (-0.255, -0.175):
        mb.zcyl(0.004, 0.058, 0.082, 0.0, y, "steel", segs=6)
    for z in (0.039, 0.053):
        mb.ycyl(0.004, -0.380, -0.340, z, "steel", segs=6)
    mb.plate([(-0.376, 0.090), (-0.387, 0.090), (-0.387, -0.032), (-0.376, -0.028)], 0.036, B)
    mb.plate([(-0.386, 0.092), (-0.400, 0.088), (-0.400, -0.030), (-0.386, -0.034)], 0.040, "rubber", ch=0.004)
    mb.plate([(-0.290, 0.034), (-0.352, 0.034), (-0.352, -0.036), (-0.334, -0.036), (-0.318, 0.004)], 0.026, B, ch=0.004)
    # pistol grip + trigger group
    mb.plate([(0.028, 0.026), (0.004, -0.070), (-0.038, -0.066), (-0.024, -0.006), (-0.018, 0.026)], 0.030, B, ch=0.005)
    for z in (-0.048, -0.030):
        mb.box((0.0316, 0.026, 0.004), (0, 0.002 + 0.25 * z, z), "black", rot=(-14.0, 0, 0))
    mb.strap([(0.076, 0.023), (0.072, 0.004), (0.036, 0.000), (0.024, 0.008)], 0.012, 0.003, B)
    mb.trigger(0.050, 0.024, h=0.020)
    # ejection port (right), safety dot (left), sling stud
    mb.box((0.002, 0.085, 0.016), (0.0176, 0.048, zb), "black")
    mb.box((0.001, 0.004, 0.004), (-0.0183, -0.050, zb), "red")
    mb.box((0.005, 0.010, 0.008), (0, 0.455, 0.028), "steel_dark")
    mb.to_object(root, "body")

    bt = GB()
    bt.ycyl(0.007, -0.108, -0.080, zb, "steel", segs=8)
    bt.box((0.003, 0.070, 0.012), (0.0183, 0.050, zb), "steel")
    bt.tube([(0.015, -0.040, zb), (0.034, -0.042, zb - 0.006), (0.046, -0.046, zb - 0.022)], 0.0035, "steel", segs=5)
    bt.sphere(0.009, (0.048, -0.047, zb - 0.028), "black", segs=6, rings=4)
    bt.to_object(root, "bolt", origin=(0.0, 0.0, zb))

    top = (0.0, 0.108, 0.030)
    mg = GB()
    L = 0.054
    mg.box((0.026, 0.058, L), (0, top[1], top[2] - L * 0.5), "steel_dark", bevel=0.003)
    mg.box((0.029, 0.062, 0.005), (0, top[1], top[2] - L - 0.001), "black")
    mg.to_object(root, "mag", origin=top)

    std_markers(root, muzzle=(0, 0.850, zb), eject=(0.019, 0.048, zb), hand_l=(0, 0.300, 0.022),
                scope=(0, 0.066, 0.101), under=(0, 0.3925, 0.0175))
    return root


@asset("launcher_rocket", "weapons/launcher_rocket", length=1.10,
       notes="Shoulder rocket launcher. Markers: muzzle = tube front (+Y forward); back = tube rear, rotated 180 deg "
             "about Z so its +Y points REARWARD (back-blast direction). hand_l = forward grip. rocket_loaded: "
             "identity origin, hide after firing (overall length 1.10 includes the warhead; tube alone 1.04).")
def build_launcher_rocket():
    root = begin("launcher_rocket")
    mb = GB()
    zt, rt, SEG = 0.105, 0.046, 10
    top = zt + rt * math.cos(math.pi / SEG)
    # launch tube, muzzle bell, rear venturi
    mb.ycyl(rt, -0.445, 0.475, zt, A, segs=SEG, caps=False)
    mb.ycyl(rt, 0.470, 0.520, zt, A, segs=SEG, r2=0.058, cap_color="black")
    mb.ycyl(0.066, -0.520, -0.440, zt, A, segs=SEG, r2=rt, cap_color="black")
    # furniture sleeve around the middle + clamp bands
    mb.ycyl(rt + 0.005, -0.200, 0.150, zt, B, segs=SEG)
    for y in (-0.395, 0.330):
        mb.ycyl(rt + 0.004, y - 0.009, y + 0.009, zt, "steel_dark", segs=SEG)
    # trigger housing, pistol grip, trigger group
    mb.plate([(-0.040, 0.066), (0.110, 0.066), (0.110, 0.040), (0.100, 0.030), (-0.030, 0.030), (-0.040, 0.040)],
             0.034, A, ch=0.004)
    mb.plate([(0.030, 0.034), (0.004, -0.066), (-0.038, -0.062), (-0.024, -0.004), (-0.016, 0.034)], 0.030, B, ch=0.005)
    for z in (-0.044, -0.026):
        mb.box((0.0316, 0.026, 0.004), (0, 0.001 + 0.25 * z, z), "black", rot=(-14.0, 0, 0))
    mb.strap([(0.080, 0.031), (0.076, 0.004), (0.040, 0.000), (0.024, 0.008)], 0.012, 0.003, A)
    mb.trigger(0.052, 0.031, h=0.022)
    # forward grip for the support hand
    mb.plate([(0.194, 0.066), (0.238, 0.066), (0.232, 0.040), (0.226, -0.030), (0.198, -0.030), (0.202, 0.040)],
             0.028, B, ch=0.005)
    # shoulder rest
    mb.plate([(-0.150, 0.066), (-0.330, 0.066), (-0.342, 0.036), (-0.322, 0.020), (-0.172, 0.038)], 0.050, "rubber",
             ch=0.006)
    # optics rail on top + iron sight bar with two leaves on the upper-left
    mb.rail(0.020, 0.140, top - 0.001, A, w=0.020, h=0.008, n=4)
    mb.box((0.008, 0.200, 0.008), (-0.034, 0.090, 0.142), A)
    mb.box((0.004, 0.005, 0.040), (-0.034, -0.004, 0.164), "steel_dark", colors={"-y": "white"})
    mb.plate([(0.176, 0.146), (0.190, 0.146), (0.187, 0.184), (0.179, 0.184)], 0.004, "steel_dark", x=-0.034)
    mb.box((0.0045, 0.003, 0.004), (-0.034, 0.1805, 0.1825), "led_green")
    mb.to_object(root, "body")

    rk = GB()
    rk.ycyl(0.040, 0.500, 0.536, zt, "military_green", segs=SEG, caps=False)
    rk.ycyl(0.0415, 0.522, 0.531, zt, "hazard_yellow", segs=SEG)
    rk.ycyl(0.040, 0.536, 0.574, zt, "military_green", segs=SEG, r2=0.012, caps=False)
    rk.ycyl(0.012, 0.573, 0.580, zt, "steel", segs=6, r2=0.006)
    rk.to_object(root, "rocket_loaded")

    std_markers(root, muzzle=(0, 0.520, zt), eject=(0, -0.520, zt), hand_l=(0, 0.214, 0.000),
                scope=(0, 0.080, round(top + 0.007, 4)), under=(0, 0.150, round(zt - rt * math.cos(math.pi / SEG), 4)))
    mk(root, "back", (0, -0.520, zt), rot=(0, 0, 180.0))
    return root


@asset("launcher_grenade", "weapons/launcher_grenade", length=0.72,
       notes="Revolver-style 6-shot 40 mm launcher, skeleton stock, vertical foregrip (hand_l). cylinder: origin on "
             "its axis (parallel to Y), spins about Y, 60 deg per shot. 'eject' sits at the cylinder (right side).")
def build_launcher_grenade():
    root = begin("launcher_grenade")
    mb = GB()
    zc, rc = 0.078, 0.056
    zbore = zc + 0.033
    # rear frame, top strap + rail, bottom strut, front frame
    mb.plate([(-0.045, 0.034), (-0.045, 0.112), (-0.028, 0.138), (0.040, 0.138), (0.040, 0.026), (-0.036, 0.026)],
             0.046, A, ch=0.005)
    mb.hull([(0.030, 0.142, 0.012, 0.006, 0.003), (0.200, 0.142, 0.012, 0.006, 0.003)], A)
    mb.rail(0.036, 0.194, 0.148, A, w=0.020, h=0.008, n=5, base=False)
    mb.hull([(0.030, 0.014, 0.010, 0.006, 0.003), (0.200, 0.014, 0.010, 0.006, 0.003)], A)
    mb.plate([(0.156, 0.008), (0.190, 0.008), (0.198, 0.060), (0.198, 0.148), (0.156, 0.148)], 0.040, A, ch=0.004)
    # short fat barrel, muzzle ring, front sight
    mb.ycyl(0.028, 0.190, 0.380, zbore, A, segs=10, caps=False)
    mb.ycyl(0.031, 0.362, 0.385, zbore, "steel_dark", segs=10, cap_color="black")
    mb.plate([(0.366, 0.139), (0.384, 0.139), (0.380, 0.156), (0.372, 0.156)], 0.004, "steel_dark")
    # under-barrel bar + vertical foregrip
    mb.hull([(0.196, 0.078, 0.010, 0.007, 0.003), (0.312, 0.078, 0.010, 0.007, 0.003)], A)
    mb.plate([(0.240, 0.076), (0.280, 0.076), (0.275, 0.030), (0.269, -0.024), (0.241, -0.024), (0.245, 0.030)],
             0.030, B, ch=0.005)
    for z in (-0.008, 0.012):
        mb.box((0.0316, 0.022, 0.004), (0, 0.257, z), "black")
    # pistol grip + trigger group (under the cylinder)
    mb.plate([(0.030, 0.030), (0.004, -0.068), (-0.038, -0.064), (-0.024, -0.004), (-0.018, 0.030)], 0.030, B, ch=0.005)
    for z in (-0.046, -0.028):
        mb.box((0.0316, 0.026, 0.004), (0, 0.002 + 0.25 * z, z), "black", rot=(-14.0, 0, 0))
    mb.strap([(0.086, 0.010), (0.082, -0.012), (0.040, -0.014), (0.022, -0.004)], 0.012, 0.003, A)
    mb.trigger(0.052, 0.009, h=0.018)
    # skeleton stock: two struts, cheek piece, butt + pad
    mb.tube([(0, -0.040, 0.118), (0, -0.302, 0.104)], 0.007, "steel_dark", segs=6)
    mb.tube([(0, -0.040, 0.050), (0, -0.302, 0.026)], 0.006, "steel_dark", segs=6)
    mb.hull([(-0.235, 0.112, 0.012, 0.010, 0.004), (-0.105, 0.119, 0.012, 0.010, 0.004)], B)
    mb.plate([(-0.298, 0.124), (-0.322, 0.120), (-0.322, 0.000), (-0.298, 0.004)], 0.034, B, ch=0.004)
    mb.plate([(-0.322, 0.122), (-0.335, 0.118), (-0.335, 0.000), (-0.322, -0.002)], 0.036, "rubber", ch=0.003)
    mb.box((0.001, 0.004, 0.004), (-0.0233, -0.020, 0.060), "red")
    mb.to_object(root, "body")

    cy = GB()
    y0, y1 = 0.044, 0.152
    rings = []
    for (y, rin) in ((y0, rc), (y0 + 0.040, rc), (y1, rc - 0.011)):
        ring = []
        for k in range(12):
            a = math.radians(90.0 + 30.0 * k)
            r = rc if k % 2 == 0 else rin
            ring.append((math.cos(a) * r, y, zc + math.sin(a) * r))
        rings.append(ring)
    cy.loft(rings, A)
    for k in range(6):
        a = math.radians(90.0 + 60.0 * k)
        cy.disc(0.0205, (math.cos(a) * 0.033, y1 + 0.0008, zc + math.sin(a) * 0.033), "black", axis="Y", segs=8)
    cy.to_object(root, "cylinder", origin=(0.0, (y0 + y1) * 0.5, zc), sharp_angle=40)

    std_markers(root, muzzle=(0, 0.385, zbore), eject=(0.057, 0.098, zc), hand_l=(0, 0.258, 0.022),
                scope=(0, 0.115, 0.156), under=(0, 0.336, round(zbore - 0.028 * math.cos(math.pi / 10), 4)))
    return root
