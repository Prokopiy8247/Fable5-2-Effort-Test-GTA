"""weapons.py - Halcyon Bay weapon, projectile and pickup-prop pipeline (Blender 5.2, run via MCP).

Module of the WEAPON ARTIST: toolkit + registry. The builders live in the sibling files
weapons_melee.py, weapons_handguns.py, weapons_long.py, weapons_heavy.py, weapons_pickups.py
(loaded automatically at the bottom of this file). Everything is re-runnable:

    import sys, importlib
    P = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Ultracode\\tools\\blender"
    for p in (P, P + r"\\assets"):
        if p not in sys.path: sys.path.append(p)
    import gta_bl as G; importlib.reload(G)
    import weapons as W; importlib.reload(W)
    G.assert_master()
    W.build("pistol"); W.shots("pistol"); W.export("pistol"); G.save()
    # everything:  W.build_all(); W.export_all(); W.write_manifests(); G.save()

Contract (docs/ARCHITECTURE.md 8.3): one root Empty per asset (named like the id) in collection
'Weapons', slot region 'weapons'. Weapon origin = right-hand grip, barrel along +Y, up +Z, real
scale. Children: 'Body' (mesh), markers 'Muzzle', 'Eject', 'Grip_L', separate 'Mag' mesh where
visible, attachments 'Att_Suppressor', 'Att_Scope', 'Att_Flashlight', 'Att_Grip', 'Att_ExtMag'
(authored in place; the game hides them by default). Material 'M_Weapon_Finish' = tintable finish.
Extra helper markers: 'Muzzle_Suppressed' (muzzle point with Att_Suppressor fitted), 'Flashlight'
(lens of Att_Flashlight), 'Exhaust' on projectiles. All markers keep the weapon's orientation.
Pickup props: origin at the bottom centre, single mesh child 'Body'.

Blender object names are global, so a child called 'Body' is stored as 'Body.003' when another
asset already owns that name. export() therefore post-processes the GLB and strips the numeric
suffixes from node / mesh names, so the exported files always carry the clean contract names.
"""
import bpy
import bmesh
import math
import os
import json
import struct
import re
import importlib
from mathutils import Vector, Matrix, Euler

import gta_bl as G

COLL = "Weapons"
REGION = "weapons"
AUTHOR = "weapons"
PI = math.pi
VIEWS = ("three_quarter", "side", "rear_quarter", "top")

WEAPON_IDS = ["knife", "bat", "crowbar", "pistol", "heavy_pistol", "smg", "pump_shotgun", "auto_shotgun",
              "assault_rifle", "carbine", "marksman_rifle", "sniper_rifle", "grenade", "molotov",
              "rocket_launcher", "grenade_launcher", "rocket", "grenade_round"]
PICKUP_IDS = ["ammo_box", "medkit", "armor_vest", "cash_stack", "cash_bag", "parachute_pack", "scuba_tank",
              "weapon_crate"]
SLOTS = {n: i for i, n in enumerate(WEAPON_IDS)}
SLOTS.update({n: 24 + i for i, n in enumerate(PICKUP_IDS)})
TRI_LIMIT = {n: 1800 for n in WEAPON_IDS}
TRI_LIMIT.update({n: 900 for n in PICKUP_IDS})

# ------------------------------------------------------------------------------------------------
# materials
# ------------------------------------------------------------------------------------------------
# palette key -> (roughness, metallic)
_MAT = {
    "GunMetal": (0.45, 0.30), "GunMetalDark": (0.50, 0.30), "GunPolymer": (0.82, 0.0),
    "GunWood": (0.62, 0.0), "GunTan": (0.78, 0.0), "Brass": (0.35, 0.50), "OliveDrab": (0.72, 0.0),
    "Steel": (0.35, 0.45), "SteelDark": (0.45, 0.40), "Chrome": (0.22, 0.6), "Black": (0.85, 0.0),
    "Charcoal": (0.8, 0.0), "Window": (0.15, 0.2), "White": (0.5, 0.0), "Wood": (0.65, 0.0),
    "WoodDark": (0.7, 0.0), "Leather": (0.75, 0.0),
}
# materials that belong to the weapon set: this module keeps their settings authoritative
_OWNED = ("GunMetal", "GunMetalDark", "GunPolymer", "GunWood", "GunTan", "Brass")
_mat_synced = set()


def M(key):
    """Material for a short key: 'Finish' = contract material M_Weapon_Finish, else palette P_<key>."""
    if key == "Finish":
        up = "Finish" not in _mat_synced
        _mat_synced.add("Finish")
        # default finish = palette SteelDark: a lighter gun-grey so the tintable receiver / slide reads
        # against the near-black polymer and GunMetalDark parts (the game recolours it per finish)
        return G.mat("M_Weapon_Finish", G.pal("SteelDark"), rough=0.42, metal=0.35, update=up)
    r, m = _MAT.get(key, (0.7, 0.0))
    if key in _OWNED and key not in _mat_synced:
        _mat_synced.add(key)
        return G.mat("P_" + key, G.pal(key), rough=r, metal=m, update=True)
    return G.pmat(key, rough=r, metal=m)


# ------------------------------------------------------------------------------------------------
# geometry toolkit
# ------------------------------------------------------------------------------------------------
def sh(pts, dy=0.0, dz=0.0, s=1.0):
    """Shift / scale a 2D (y, z) profile."""
    return [(p[0] * s + dy, p[1] * s + dz) for p in pts]


RZ90 = Matrix.Rotation(PI / 2.0, 4, 'Z')        # (x, y, z) -> (-y, x, z): turns a YZ profile into XZ


class Part:
    """One chunk of geometry that shares bevel / shading settings. Several Parts are joined into
    one mesh object by assemble(). Coordinates: x = width (right +), y = barrel, z = up."""

    def __init__(self, bevel=0.0, smooth=None, angle=30.0):
        self.bm = G.bm_new()
        self.keys = []
        self.bevel = bevel
        self.smooth = smooth
        self.angle = angle

    def mi(self, key):
        if key not in self.keys:
            self.keys.append(key)
        return self.keys.index(key)

    @staticmethod
    def xform(verts, matrix):
        return G.transform(verts, matrix)

    # -- prisms / boxes ---------------------------------------------------------------------
    def prism(self, pts, w, mat, x=0.0):
        """Side profile [(y, z)...] extruded across X (width w centred at x)."""
        return G.add_prism(self.bm, pts, x - w / 2.0, x + w / 2.0, 'X', self.mi(mat))

    def prism_y(self, pts, y0, y1, mat):
        """Cross-section [(x, z)...] extruded along Y."""
        return G.add_prism(self.bm, pts, y0, y1, 'Y', self.mi(mat))

    def prism_z(self, pts, z0, z1, mat):
        """Plan profile [(x, y)...] extruded along Z."""
        return G.add_prism(self.bm, pts, z0, z1, 'Z', self.mi(mat))

    def box(self, y0, y1, z0, z1, w, mat, x=0.0, rot=None):
        return G.add_box(self.bm, (w, abs(y1 - y0), abs(z1 - z0)),
                         (x, (y0 + y1) / 2.0, (z0 + z1) / 2.0), rot, self.mi(mat))

    def boxc(self, size, center, mat, rot=None):
        return G.add_box(self.bm, size, center, rot, self.mi(mat))

    def tbox(self, bottom, top, height, center, mat, top_offset=(0, 0)):
        return G.add_tapered_box(self.bm, bottom, top, height, center, top_offset, self.mi(mat))

    def plate(self, y0, y1, z0, z1, half_w, mat, side=1, out=0.0007, depth=0.0015):
        """Thin inset-looking plate sitting on the side face x = side*half_w (ports, levers)."""
        x0 = side * (half_w - depth)
        x1 = side * (half_w + out)
        return self.box(y0, y1, z0, z1, abs(x1 - x0), mat, x=(x0 + x1) / 2.0)

    def seg_xz(self, p0, p1, y0, y1, t, mat):
        """Bar between two (x, z) points, spanning y0..y1 (emblems, zig-zags)."""
        dx, dz = p1[0] - p0[0], p1[1] - p0[1]
        L = math.hypot(dx, dz)
        a = math.atan2(dx, dz)                  # rotation about +Y taking local z to the segment
        return G.add_box(self.bm, (t, abs(y1 - y0), L + t * 0.6),
                         ((p0[0] + p1[0]) / 2.0, (y0 + y1) / 2.0, (p0[1] + p1[1]) / 2.0), (0, a, 0), self.mi(mat))

    # -- round things -----------------------------------------------------------------------
    def cyl(self, r, y0, y1, z, mat, segs=10, x=0.0, r2=None, spin=0.0):
        """Cylinder / frustum along Y (r at y0, r2 at y1)."""
        return G.add_cylinder(self.bm, r, y1 - y0, (x, (y0 + y1) / 2.0, z), 'Y', segs, self.mi(mat),
                              radius2=r2, rot=(0, spin, 0) if spin else None)

    def cylz(self, r, z0, z1, mat, segs=10, x=0.0, y=0.0, r2=None, spin=0.0):
        return G.add_cylinder(self.bm, r, z1 - z0, (x, y, (z0 + z1) / 2.0), 'Z', segs, self.mi(mat),
                              radius2=r2, rot=(0, 0, spin) if spin else None)

    def cylx(self, r, x0, x1, y, z, mat, segs=10, r2=None, spin=0.0):
        return G.add_cylinder(self.bm, r, x1 - x0, ((x0 + x1) / 2.0, y, z), 'X', segs, self.mi(mat),
                              radius2=r2, rot=(spin, 0, 0) if spin else None)

    def cyl_rot(self, r, depth, center, rot, mat, segs=10, r2=None):
        """Cylinder along local Z, rotated by euler `rot`, centred at `center`."""
        return G.add_cylinder(self.bm, r, depth, center, 'Z', segs, self.mi(mat), radius2=r2, rot=rot)

    def sphere(self, r, center, mat, segs=10, rings=6, scale=(1, 1, 1), rot=None):
        return G.add_sphere(self.bm, r, center, segs, rings, self.mi(mat), scale, rot)

    def lathe(self, profile, mat, axis='Y', origin=(0, 0, 0), segs=10, spin=0.0, scale=(1.0, 1.0)):
        """Surface of revolution. profile = [(radius, t)...] along `axis` starting at `origin`.
        scale = (a, b) squashes the two radial directions (oval sections)."""
        ox, oy, oz = origin
        secs = []
        for r, t in profile:
            ring = []
            rr = max(r, 0.0)
            for k in range(segs):
                a = spin + 2.0 * PI * k / segs
                ca, sa = math.cos(a) * rr * scale[0], math.sin(a) * rr * scale[1]
                if axis == 'Y':
                    ring.append((ox + ca, oy + t, oz + sa))
                elif axis == 'Z':
                    ring.append((ox + ca, oy + sa, oz + t))
                else:
                    ring.append((ox + t, oy + ca, oz + sa))
            secs.append(ring)
        cap0 = profile[0][0] > 1e-6
        cap1 = profile[-1][0] > 1e-6
        return G.add_loft(self.bm, secs, self.mi(mat), cap_start=cap0, cap_end=cap1)

    # -- swept shapes -----------------------------------------------------------------------
    def strip(self, pts, t, w, mat, x=0.0, closed=False):
        """Rectangular bar (thickness t in the YZ plane, width w across X) swept along a (y, z)
        polyline with mitred corners. closed=True makes a loop (frames, skeleton stocks...)."""
        P = [Vector((p[0], p[1])) for p in pts]
        n = len(P)
        L, R = [], []
        for i in range(n):
            a = P[i - 1] if (closed or i > 0) else None
            b = P[(i + 1) % n] if (closed or i < n - 1) else None
            d1 = (P[i] - a).normalized() if a is not None else None
            d2 = (b - P[i]).normalized() if b is not None else None
            if d1 is None:
                nrm, s = Vector((-d2.y, d2.x)), 1.0
            elif d2 is None:
                nrm, s = Vector((-d1.y, d1.x)), 1.0
            else:
                n1 = Vector((-d1.y, d1.x))
                n2 = Vector((-d2.y, d2.x))
                m = n1 + n2
                if m.length < 1e-6:
                    nrm, s = n1, 1.0
                else:
                    nrm = m.normalized()
                    s = 1.0 / max(0.35, nrm.dot(n1))
            L.append(P[i] + nrm * (t / 2.0 * s))
            R.append(P[i] - nrm * (t / 2.0 * s))
        x0, x1 = x - w / 2.0, x + w / 2.0
        secs = [[(x0, L[i].x, L[i].y), (x1, L[i].x, L[i].y), (x1, R[i].x, R[i].y), (x0, R[i].x, R[i].y)]
                for i in range(n)]
        if closed:
            secs.append(secs[0])
            return G.add_loft(self.bm, secs, self.mi(mat), cap_start=False, cap_end=False)
        return G.add_loft(self.bm, secs, self.mi(mat))

    def pipe(self, pts, r, mat, segs=6, closed=False, spin=0.0):
        """Tube along a 3D path. r = float, or per-point float, or per-point (ru, rv) for
        flattened sections (ru across the first frame axis, which starts as world X)."""
        P = [Vector(p) for p in pts]
        n = len(P)
        secs = []
        prev_u = None
        for i in range(n):
            if closed:
                t = (P[(i + 1) % n] - P[i - 1]).normalized()
            else:
                t = (P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized()
            if prev_u is None:
                ref = Vector((1, 0, 0)) if abs(t.x) < 0.9 else Vector((0, 0, 1))
                u = (ref - t * ref.dot(t)).normalized()
            else:
                u = prev_u - t * prev_u.dot(t)
                u = u.normalized() if u.length > 1e-6 else prev_u
            v = t.cross(u)
            prev_u = u
            rr = r[i] if isinstance(r, (list, tuple)) else r
            ru, rv = rr if isinstance(rr, (list, tuple)) else (rr, rr)
            ring = []
            for k in range(segs):
                a = spin + 2.0 * PI * k / segs
                ring.append(tuple(P[i] + u * (math.cos(a) * ru) + v * (math.sin(a) * rv)))
            secs.append(ring)
        if closed:
            secs.append(secs[0])
            return G.add_loft(self.bm, secs, self.mi(mat), cap_start=False, cap_end=False)
        return G.add_loft(self.bm, secs, self.mi(mat))

    def loft(self, sections, mat, cap_start=True, cap_end=True):
        return G.add_loft(self.bm, sections, self.mi(mat), cap_start=cap_start, cap_end=cap_end)

    # -- repeated details -------------------------------------------------------------------
    def ribs_y(self, y0, y1, n, z0, z1, w, t, mat, x=0.0, slant=0.0):
        """n thin slabs spread along Y (slide serrations, vents, cooling fins)."""
        for i in range(n):
            y = y0 + (y1 - y0) * (i / (n - 1) if n > 1 else 0.5)
            self.box(y - t / 2.0, y + t / 2.0, z0, z1, w, mat, x=x, rot=(slant, 0, 0) if slant else None)

    def ribs_z(self, z0, z1, n, y0, y1, w, t, mat, x=0.0, rake=0.0):
        """n thin slabs spread along Z (grip grooves). rake shifts y per unit z."""
        for i in range(n):
            z = z0 + (z1 - z0) * (i / (n - 1) if n > 1 else 0.5)
            dy = rake * z
            self.box(y0 + dy, y1 + dy, z - t / 2.0, z + t / 2.0, w, mat, x=x)

    def rail(self, y0, y1, z, mat="GunMetalDark", w=0.021, pitch=0.022, h=0.0045, base=0.004):
        """Accessory rail: base bar + teeth. Top surface at z + base + h (see rail_top())."""
        self.box(y0, y1, z, z + base, w * 0.78, mat)
        n = max(2, int(round((y1 - y0) / pitch)))
        for i in range(n):
            y = y0 + (y1 - y0) * (i + 0.5) / n
            self.box(y - (y1 - y0) / n * 0.31, y + (y1 - y0) / n * 0.31, z + base, z + base + h, w, mat)


def rail_top(z, h=0.0045, base=0.004):
    return z + base + h


def grip_profile(z_top, z_bot, front_top, back_top, rake=0.30, flare=0.004, heel=0.006):
    """Pistol-grip side profile [(y, z)]. front_top / back_top = y of the front / back strap at
    z_top; rake = y shift per unit z (grip leans back towards the bottom)."""
    dz = z_bot - z_top
    fb = front_top + rake * dz
    bb = back_top + rake * dz
    zm = z_top + dz * 0.55
    return [
        (front_top, z_top), (front_top + rake * (zm - z_top) + 0.002, zm), (fb + flare, z_bot),
        (bb - flare, z_bot - heel), (back_top + rake * (zm - z_top) - 0.003, zm), (back_top, z_top),
    ]


def add_trigger(D, y, zt, mat="GunMetalDark", w=0.007):
    """Curved trigger blade hanging from (y, zt)."""
    D.prism([(y, zt), (y + 0.008, zt), (y + 0.007, zt - 0.012), (y + 0.011, zt - 0.026),
             (y + 0.006, zt - 0.027), (y + 0.001, zt - 0.013)], w, mat)


# ------------------------------------------------------------------------------------------------
# asset plumbing
# ------------------------------------------------------------------------------------------------
_SHIFT = Vector((0.0, 0.0, 0.0))


def begin(name, shift=(0.0, 0.0, 0.0), collection=COLL):
    """Create (or rebuild) the root Empty of one of OUR assets at its slot. `shift` is added to
    all geometry and markers of this asset (lets a builder work in a convenient frame and still
    put the origin on the grip). Refuses to replace a same-named object this module did not make."""
    global _SHIFT
    old = bpy.data.objects.get(name)
    if old is not None and old.get("gta_author") != AUTHOR:
        raise RuntimeError("name collision: object %r exists and is not ours - not touching it" % name)
    root = G.asset_root(name, collection, G.slot(REGION, SLOTS[name]), rebuild=True)
    root["gta_author"] = AUTHOR
    root.empty_display_size = 0.08
    _SHIFT = Vector(shift)
    return root


def assemble(root, name, parts, origin=None):
    """Turn Parts into ONE mesh object `name` under root (bevels applied per part)."""
    objs = []
    for i, p in enumerate(parts):
        if len(p.bm.faces) == 0:
            p.bm.free()
            continue
        if _SHIFT.length > 0:
            bmesh.ops.translate(p.bm, verts=p.bm.verts[:], vec=_SHIFT)
        ob = G.new_object("_wtmp_%s_%s_%d" % (root.name, name, i), p.bm, parent=root,
                          materials=[M(k) for k in p.keys], smooth_angle=p.smooth, uv=False)
        if p.bevel > 0:
            G.bevel(ob, p.bevel, 1, p.angle)
        objs.append(ob)
    bpy.context.view_layer.update()
    ob = G.join(objs, name)
    if origin is not None:
        G.set_origin(ob, Vector(origin) + _SHIFT)
    return ob


def marker(root, name, loc, size=0.03):
    return G.empty(name, root, Vector(loc) + _SHIFT, size=size, display='ARROWS')


def base_name(n):
    return re.sub(r'\.\d{3,}$', '', n)


def child(root, name):
    for o in root.children_recursive:
        if base_name(o.name) == name:
            return o
    return None


def tri_count(root):
    n = 0
    for o in G.children_of(root):
        if o.type == 'MESH':
            o.data.calc_loop_triangles()
            n += len(o.data.loop_triangles)
    return n


def part_tris(root_name):
    root = bpy.data.objects[root_name]
    out = {}
    for o in root.children_recursive:
        if o.type == 'MESH':
            o.data.calc_loop_triangles()
            out[base_name(o.name)] = len(o.data.loop_triangles)
    return out


def check_normals(root_name):
    """Report closed mesh islands whose signed volume is negative (= inside-out)."""
    root = bpy.data.objects[root_name]
    bad = 0
    open_islands = 0
    for o in G.children_of(root):
        if o.type != 'MESH':
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        seen = set()
        for f0 in bm.faces:
            if f0.index in seen:
                continue
            stack = [f0]
            seen.add(f0.index)
            isl = []
            while stack:
                f = stack.pop()
                isl.append(f)
                for e in f.edges:
                    for g in e.link_faces:
                        if g.index not in seen:
                            seen.add(g.index)
                            stack.append(g)
            closed = all(len(e.link_faces) == 2 for f in isl for e in f.edges)
            vol = 0.0
            for f in isl:
                vs = [v.co for v in f.verts]
                for k in range(1, len(vs) - 1):
                    vol += vs[0].dot(vs[k].cross(vs[k + 1])) / 6.0
            if not closed:
                open_islands += 1
            elif vol < 0:
                bad += 1
        bm.free()
    print("NORMALS %s: inverted_islands=%d non_manifold_islands=%d" % (root_name, bad, open_islands))
    return bad, open_islands


def shots(name, res=512, views=VIEWS, att=True):
    """Contact sheets: qa/blender_previews/wpn_<name>.png (attachments hidden) and
    wpn_<name>_att.png (all attachments shown, Mag swapped for Att_ExtMag)."""
    root = bpy.data.objects[name]
    atts = [o for o in root.children_recursive if base_name(o.name).startswith("Att_")]
    for o in atts:
        o.hide_render = True
    try:
        G.preview(name, "wpn_" + name, views=views, res=res)
    finally:
        for o in atts:
            o.hide_render = False
    if atts and att:
        mag = child(root, "Mag")
        ext = child(root, "Att_ExtMag")
        swap = mag is not None and ext is not None
        if swap:
            mag.hide_render = True
        try:
            G.preview(name, "wpn_" + name + "_att", views=("side", "rear_quarter"), res=res)
        finally:
            if swap:
                mag.hide_render = False


def group_shot(names, out_name, spacing=0.26, res=1000, view="side", cols=1, col_step=1.4, atts=False):
    """Scale-comparison sheet: temporarily racks OUR roots above each other, renders, restores."""
    roots = [bpy.data.objects[n] for n in names]
    for r in roots:
        if r.get("gta_author") != AUTHOR:
            raise RuntimeError("group_shot: %s is not ours" % r.name)
    saved = [r.location.copy() for r in roots]
    base = G.slot(REGION, 36) + Vector((0, 0, 20.0))      # empty space above our own region
    hidden = []
    try:
        per = (len(roots) + cols - 1) // cols
        for i, r in enumerate(roots):
            c, k = i // per, i % per
            sp = spacing[i] if isinstance(spacing, (list, tuple)) else spacing * k
            r.location = base + Vector((0, c * col_step, -sp))
        bpy.context.view_layer.update()
        if not atts:
            for r in roots:
                for o in r.children_recursive:
                    if base_name(o.name).startswith("Att_") and not o.hide_render:
                        o.hide_render = True
                        hidden.append(o)
        many = isinstance(view, (list, tuple)) and len(view) > 0 and isinstance(view[0], (str, list, tuple))
        G.preview(names, out_name, views=tuple(view) if many else (view,), res=res)
    finally:
        for o in hidden:
            o.hide_render = False
        for r, l in zip(roots, saved):
            r.location = l
        bpy.context.view_layer.update()


def fix_glb_names(path):
    """Strip Blender's '.001' suffixes from node / mesh names inside a GLB (see module docstring)."""
    with open(path, 'rb') as f:
        data = f.read()
    magic, ver, total = struct.unpack_from('<4sII', data, 0)
    if magic != b'glTF':
        raise RuntimeError("not a GLB: " + path)
    clen, ctype = struct.unpack_from('<I4s', data, 12)
    js = json.loads(data[20:20 + clen].decode('utf-8'))
    rest = data[20 + clen:]
    changed = 0
    for key in ('nodes', 'meshes'):
        for n in js.get(key, []):
            nm = n.get('name')
            if nm:
                new = base_name(nm)
                if new != nm:
                    n['name'] = new
                    changed += 1
    if not changed:
        return 0
    out = json.dumps(js, separators=(',', ':')).encode('utf-8')
    out += b' ' * ((4 - len(out) % 4) % 4)
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(out) + len(rest)))
        f.write(struct.pack('<I4s', len(out), b'JSON'))
        f.write(out)
        f.write(rest)
    return changed


def glb_names(path):
    with open(path, 'rb') as f:
        data = f.read()
    clen, ctype = struct.unpack_from('<I4s', data, 12)
    js = json.loads(data[20:20 + clen].decode('utf-8'))
    return [n.get('name') for n in js.get('nodes', [])], [m.get('name') for m in js.get('materials', [])]


def rel_path(name):
    return ("props/pickups/%s.glb" if name in PICKUP_IDS else "weapons/%s.glb") % name


def export(name):
    """validate -> export GLB -> strip name suffixes. Returns the validate() dict (+ 'path')."""
    info = G.validate(name, TRI_LIMIT.get(name))
    bad, _ = check_normals(name)
    if bad:
        raise RuntimeError("%s has %d inside-out islands - fix before export" % (name, bad))
    path = G.export_glb(name, rel_path(name))
    n = fix_glb_names(path)
    nodes, mats = glb_names(path)
    print("GLB %s: renamed=%d nodes=%s materials=%s" % (name, n, nodes, mats))
    info["path"] = path
    return info


def describe(name):
    """Manifest entry (coordinates converted to Godot space: Blender (x, y, z) -> (x, z, -y))."""
    root = bpy.data.objects[name]
    bpy.context.view_layer.update()
    inv = root.matrix_world.inverted()
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    parts, markers, mats = [], {}, []
    for o in root.children_recursive:
        bn = base_name(o.name)
        if o.type == 'MESH':
            parts.append(bn)
            for m in o.data.materials:
                if m is not None and m.name not in mats:
                    mats.append(m.name)
            if bn.startswith("Att_"):
                continue
            for c in o.bound_box:
                w = inv @ (o.matrix_world @ Vector(c))
                mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
                mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
        else:
            p = inv @ o.matrix_world.translation
            markers[bn] = [round(p.x, 4), round(p.z, 4), round(-p.y, 4)]
    size = mx - mn
    return {
        "id": name, "file": name + ".glb", "tris": tri_count(root),
        "size": [round(size.x, 3), round(size.z, 3), round(size.y, 3)],
        "aabb_min": [round(mn.x, 4), round(mn.z, 4), round(-mx.y, 4)],
        "aabb_max": [round(mx.x, 4), round(mx.z, 4), round(-mn.y, 4)],
        "meshes": sorted(parts),
        "attachments": sorted(p for p in parts if p.startswith("Att_")),
        "has_mag": "Mag" in parts,
        "tintable": "M_Weapon_Finish" in mats,
        "materials": sorted(mats),
        "markers": markers,
    }


def write_manifests():
    """models/weapons/manifest.json (+ props/pickups/manifest_pickups.json) for the game code."""
    weapons = [describe(n) for n in WEAPON_IDS if bpy.data.objects.get(n) is not None]
    p1 = os.path.join(G.MODELS_DIR, "weapons", "manifest.json")
    os.makedirs(os.path.dirname(p1), exist_ok=True)
    with open(p1, "w", encoding="utf-8") as f:
        json.dump({
            "about": "Halcyon Bay weapon models. Godot space: -Z = barrel, +Y = up, +X = right, origin = right-hand "
                     "grip. Att_* meshes are authored in place (hide by default); hide Mag while Att_ExtMag is shown.",
            "finish_material": "M_Weapon_Finish",
            "weapons": weapons}, f, indent=1)
    props = []
    for n in PICKUP_IDS:
        if bpy.data.objects.get(n) is None:
            continue
        d = describe(n)
        props.append({"id": n, "file": d["file"], "category": "pickup", "size": d["size"], "physics": "static",
                      "mass": 0.0, "surface": "metal", "tris": d["tris"], "meshes": d["meshes"],
                      "materials": d["materials"], "aabb_min": d["aabb_min"], "aabb_max": d["aabb_max"]})
    p2 = os.path.join(G.MODELS_DIR, "props", "pickups", "manifest_pickups.json")
    os.makedirs(os.path.dirname(p2), exist_ok=True)
    with open(p2, "w", encoding="utf-8") as f:
        json.dump({"about": "Pickup props (origin bottom centre, single mesh 'Body').", "props": props}, f, indent=1)
    print("MANIFESTS:", p1, p2)
    return p1, p2


# ------------------------------------------------------------------------------------------------
# shared attachment builders
# ------------------------------------------------------------------------------------------------
def att_suppressor(root, y0, z, r=0.019, length=0.16, x=0.0):
    S = Part(smooth=40)
    S.lathe([(r * 0.60, y0), (r, y0 + 0.005), (r, y0 + length - 0.006), (r * 0.82, y0 + length),
             (r * 0.34, y0 + length)], "GunMetalDark", origin=(x, 0, z), segs=10)
    S.lathe([(r * 1.07, y0 + 0.014), (r * 1.07, y0 + 0.030)], "GunMetal", origin=(x, 0, z), segs=10)
    ob = assemble(root, "Att_Suppressor", [S])
    marker(root, "Muzzle_Suppressed", (x, y0 + length, z))      # muzzle point while the suppressor is fitted
    return ob


def att_flashlight(root, y0, z, x=0.0, r=0.011, length=0.07, mount=None):
    """Tactical light along +Y. mount = (cx, cz, sx, sz): clamp block centre / size in XZ."""
    F = Part(smooth=40)
    F.lathe([(r * 0.85, y0), (r * 0.85, y0 + length * 0.60), (r * 1.18, y0 + length * 0.72),
             (r * 1.18, y0 + length)], "GunMetalDark", origin=(x, 0, z), segs=10)
    F.cyl(r * 0.95, y0 + length - 0.001, y0 + length + 0.0015, z, "White", segs=10, x=x)
    parts = [F]
    if mount is not None:
        Mt = Part()
        cx, cz, sx, sz = mount
        Mt.boxc((sx, length * 0.42, sz), (cx, y0 + length * 0.32, cz), "GunMetal")
        parts.append(Mt)
    ob = assemble(root, "Att_Flashlight", parts)
    marker(root, "Flashlight", (x, y0 + length + 0.002, z))    # lens centre (spot light origin, shines +Y)
    return ob


def att_reflex(root, y, z, w=0.030, name="Att_Scope"):
    """Open reflex / red-dot sight sitting on a rail whose top is at z, centred at y."""
    R = Part(bevel=0.0015)
    R.box(y - 0.028, y + 0.024, z, z + 0.011, w, "GunMetalDark")
    R2 = Part()
    for s in (-1, 1):
        R2.box(y + 0.006, y + 0.022, z + 0.010, z + 0.041, 0.0042, "GunMetalDark", x=s * (w / 2.0 - 0.0021))
    R2.box(y + 0.006, y + 0.022, z + 0.040, z + 0.044, w, "GunMetalDark")
    R2.box(y + 0.0125, y + 0.0142, z + 0.011, z + 0.040, w - 0.007, "Window")
    R2.box(y - 0.024, y - 0.012, z + 0.011, z + 0.018, 0.012, "GunMetal")
    return assemble(root, name, [R, R2])


def scope_parts(y0, y1, z, r_tube=0.013, r_obj=0.019, r_eye=0.0165, mount_z=None, ring_ys=(), mat="GunMetalDark",
                segs=10):
    """Telescopic sight along +Y (eyepiece at y0). Returns [Part, Part] to pass to assemble()."""
    L = y1 - y0
    Sc = Part(smooth=40)
    Sc.lathe([(r_eye, y0), (r_eye, y0 + L * 0.15), (r_tube, y0 + L * 0.21), (r_tube, y0 + L * 0.66),
              (r_obj, y0 + L * 0.78), (r_obj, y1)], mat, origin=(0, 0, z), segs=segs)
    Sc.cyl(r_obj * 0.84, y1 - 0.0015, y1 + 0.0012, z, "Window", segs=segs)
    Sc.cyl(r_eye * 0.82, y0 - 0.0012, y0 + 0.0015, z, "Window", segs=segs)
    ty = y0 + L * 0.44
    Sc.cylz(r_tube * 0.60, z + r_tube * 0.8, z + r_tube * 1.95, "GunMetal", segs=8, y=ty)
    Sc.cylx(r_tube * 0.60, r_tube * 0.8, r_tube * 1.95, ty, z, "GunMetal", segs=8)
    Sm = Part(bevel=0.0015)
    if mount_z is not None:
        for ry in ring_ys:
            Sm.box(ry - 0.008, ry + 0.008, mount_z, z + r_tube + 0.003, 2.0 * r_tube + 0.007, "GunMetal")
    return [Sc, Sm]


def att_foregrip(root, y, z_top, length=0.090, w=0.027):
    Gp = Part(bevel=0.003)
    Gp.box(y - 0.024, y + 0.024, z_top - 0.011, z_top + 0.001, w + 0.004, "GunMetalDark")
    Gp.prism([(y - 0.014, z_top - 0.010), (y + 0.015, z_top - 0.010), (y + 0.011, z_top - length),
              (y - 0.018, z_top - length)], w, "GunPolymer")
    D = Part()
    for i in range(4):
        z = z_top - 0.026 - i * (length - 0.040) / 3.0
        dy = -0.004 * (z_top - z) / length
        D.box(y - 0.0165 + dy, y + 0.0155 + dy, z - 0.0022, z + 0.0022, w + 0.0022, "GunMetalDark")
    return assemble(root, "Att_Grip", [Gp, D])


# ------------------------------------------------------------------------------------------------
# registry
# ------------------------------------------------------------------------------------------------
BUILDERS = {}


def builder(name):
    def deco(fn):
        BUILDERS[name] = fn
        return fn
    return deco


def build(name):
    """(Re)build one asset by id. Returns the root object."""
    G.object_mode()
    root = BUILDERS[name]()
    bpy.context.view_layer.update()
    print("BUILT %s tris=%d %s" % (name, tri_count(root), part_tris(name)))
    return root


def build_all(names=None):
    for n in (names or (WEAPON_IDS + PICKUP_IDS)):
        build(n)


def export_all(names=None):
    out = {}
    for n in (names or (WEAPON_IDS + PICKUP_IDS)):
        out[n] = export(n)
    return out


def qa(names):
    """build -> normals -> validate -> contact sheets for a list of ids (the authoring loop)."""
    for n in names:
        build(n)
        check_normals(n)
        G.validate(n, TRI_LIMIT.get(n))
        shots(n)


# builder files (each registers its assets through @builder)
_SUBMODULES = ("weapons_melee", "weapons_handguns", "weapons_long", "weapons_heavy", "weapons_pickups")
for _m in _SUBMODULES:
    try:
        _mod = importlib.import_module(_m)
    except ModuleNotFoundError as _e:
        if _e.name != _m:
            raise
        continue
    importlib.reload(_mod)
