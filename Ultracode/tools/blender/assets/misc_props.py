"""misc_props - set pieces and gameplay props for Halcyon Bay (SET-PIECE ARTIST).

Builds every asset of the 'Misc' Blender collection and exports it to
gta/generated/models/misc/<id>.glb (+ manifest_misc.json).

Run inside the live master .blend through the Blender MCP:

    import sys, importlib
    P = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Ultracode\\tools\\blender"
    if P not in sys.path: sys.path.append(P)
    if P + r"\\assets" not in sys.path: sys.path.append(P + r"\\assets")
    import gta_bl as G; importlib.reload(G)
    G.assert_master()
    import misc_props as M; importlib.reload(M)
    M.build("tram")            # (re)build one asset at its slot
    M.export("tram")           # validate + export GLB (+ strip the Blender name prefix)
    M.build_all(); M.export_all(); M.write_manifest(); G.save()    # full reproducible pipeline

Naming: Blender object names are global, so every child is named "<asset>.<Part>" in the .blend
(e.g. "tram.Body") and never collides with another author's "Body". export() rewrites the node
names inside the written GLB to the clean contract names ("Body", "Door_1" ...).

Conventions: 1 unit = 1 m, Z up, assets face +Y, origin bottom centre unless stated otherwise.
"""
import bpy
import bmesh
import math
import os
import json
import struct
import random
from mathutils import Vector, Matrix, Euler

import gta_bl as G

AUTHOR = "misc_props"
COLLECTION = "Misc"
REGION = "misc"
EXPORT_DIR = "misc"
SEP = "."

# ------------------------------------------------------------------------------------------------
# materials
# ------------------------------------------------------------------------------------------------
EMIT = {
    "NeonMagenta": 3.0, "NeonCyan": 3.0, "NeonYellow": 3.0, "NeonOrange": 3.0, "NeonGreen": 3.0, "NeonBlue": 3.0,
    "LampWarm": 3.0, "HeadlightWhite": 4.0, "TailRed": 2.5, "IndicatorAmber": 2.5, "SirenRed": 4.0, "SirenBlue": 4.0,
}
ROUGH = {"Chrome": 0.25, "Rim": 0.35, "Steel": 0.45, "SteelDark": 0.5, "Tire": 0.9, "Brass": 0.35, "CarWhite": 0.45,
         "CarRed": 0.45, "CarBlue": 0.45, "CarYellow": 0.45, "CarTeal": 0.45, "CarOrange": 0.45, "CarGreen": 0.45,
         "CarSilver": 0.4}
METAL = {"Chrome": 0.9, "Rim": 0.8, "Steel": 0.6, "SteelDark": 0.6, "Brass": 0.8, "CarSilver": 0.6}


def material(key):
    """'Coral' -> shared palette material P_Coral ; 'M_Glass' etc. -> contract material."""
    if key == "M_Glass":
        return G.mat("M_Glass", G.hexc("#5E9DB8"), rough=0.08, metal=0.0, alpha=0.45)
    if key == "M_Headlight":
        c = G.pal("HeadlightWhite")
        return G.mat("M_Headlight", c, rough=0.2, emit=c, emit_strength=4.0)
    if key == "M_Taillight":
        c = G.pal("TailRed")
        return G.mat("M_Taillight", c, rough=0.3, emit=c, emit_strength=2.5)
    if key == "M_Indicator":
        c = G.pal("IndicatorAmber")
        return G.mat("M_Indicator", c, rough=0.3, emit=c, emit_strength=2.5)
    if key == "M_Tire":
        return G.mat("M_Tire", G.pal("Tire"), rough=0.9)
    if key == "M_Rim":
        return G.mat("M_Rim", G.pal("Rim"), rough=0.35, metal=0.8)
    if key == "M_Chrome":
        return G.mat("M_Chrome", G.pal("Chrome"), rough=0.25, metal=0.9)
    if key == "M_Trim":
        return G.mat("M_Trim", G.pal("Trim"), rough=0.6)
    if key == "M_Window":
        return G.mat("M_Window", G.pal("WindowDark"), rough=0.15)
    if key == "M_Siren_Red":
        c = G.pal("SirenRed")
        return G.mat("M_Siren_Red", c, rough=0.3, emit=c, emit_strength=4.0)
    if key == "M_Siren_Blue":
        c = G.pal("SirenBlue")
        return G.mat("M_Siren_Blue", c, rough=0.3, emit=c, emit_strength=4.0)
    if key.startswith("M_") or key.startswith("P_"):
        m = bpy.data.materials.get(key)
        if m is None:
            raise KeyError("unknown contract material " + key)
        return m
    return G.pmat(key, rough=ROUGH.get(key, 0.7), metal=METAL.get(key, 0.0), emit_strength=EMIT.get(key, 0.0))


# ------------------------------------------------------------------------------------------------
# build context + geometry helper
# ------------------------------------------------------------------------------------------------
class _Ctx:
    aid = ""
    prefix = ""
    root = None
    markers = None


CTX = _Ctx()


def _nm(name):
    return CTX.prefix + SEP + name


def marker(name, loc, yaw_deg=0.0, size=0.25):
    """Marker Empty under the asset root. Local +Y of the marker = facing (Godot -Z)."""
    ob = G.empty(_nm(name), CTX.root, loc, (0.0, 0.0, math.radians(yaw_deg)), size=size)
    CTX.markers[name] = (tuple(loc), yaw_deg)
    return ob


def group(name, loc=(0, 0, 0), parent=None):
    """Plain grouping Empty (e.g. 'Doors_R') that mesh children hang under."""
    ob = G.empty(_nm(name), parent or CTX.root, loc, size=0.3, display='PLAIN_AXES')
    return ob


def _flat(verts):
    out = []
    for v in verts:
        if isinstance(v, (list, tuple)):
            out.extend(_flat(v))
        else:
            out.append(v)
    return out


def _frame(a, b, roll=0.0):
    a = Vector(a)
    b = Vector(b)
    d = b - a
    q = d.to_track_quat('Z', 'Y')
    M = Matrix.Translation((a + b) / 2) @ q.to_matrix().to_4x4() @ Matrix.Rotation(roll, 4, 'Z')
    return M, d.length


class Part:
    """A bmesh under construction with its own material slot table."""

    def __init__(self, name):
        self.name = name
        self.bm = G.bm_new()
        self.mats = []
        self._idx = {}

    # -- materials
    def m(self, key):
        if key not in self._idx:
            self._idx[key] = len(self.mats)
            self.mats.append(material(key))
        return self._idx[key]

    # -- symmetry helpers
    def _sym(self, verts, sym):
        verts = _flat(verts)
        if not sym:
            return verts
        return verts + self.mirrored(verts, 0)

    def mirrored(self, verts, axis=0, about=0.0):
        """Duplicate the geometry of `verts` mirrored across axis (0=X, 1=Y, 2=Z)."""
        vs = set(verts)
        faces = set()
        edges = set()
        for v in vs:
            for f in v.link_faces:
                if all(fv in vs for fv in f.verts):
                    faces.add(f)
            for e in v.link_edges:
                if e.verts[0] in vs and e.verts[1] in vs:
                    edges.add(e)
        ret = bmesh.ops.duplicate(self.bm, geom=list(vs) + list(edges) + list(faces))
        nv = [g for g in ret['geom'] if isinstance(g, bmesh.types.BMVert)]
        nf = [g for g in ret['geom'] if isinstance(g, bmesh.types.BMFace)]
        for v in nv:
            v.co[axis] = 2 * about - v.co[axis]
        if nf:
            bmesh.ops.reverse_faces(self.bm, faces=nf)
        return nv

    def mirror_all(self, axis=1, about=0.0):
        return self.mirrored(self.bm.verts[:], axis, about)

    def move(self, verts, offset=(0, 0, 0), rot=None, pivot=(0, 0, 0)):
        """Rigid transform of some verts: rotate (euler XYZ) about pivot, then translate."""
        M = Matrix.Translation(Vector(offset)) @ Matrix.Translation(Vector(pivot)) @ \
            (Euler(rot, 'XYZ').to_matrix().to_4x4() if rot else Matrix.Identity(4)) @ \
            Matrix.Translation(-Vector(pivot))
        for v in _flat(verts):
            v.co = M @ v.co
        return verts

    # -- primitives
    def box(self, size, center, mat, rot=None, sym=False):
        return self._sym(G.add_box(self.bm, size, center, rot, self.m(mat)), sym)

    def bx(self, x0, x1, y0, y1, z0, z1, mat, sym=False):
        return self.box((abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)),
                        ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), mat, sym=sym)

    def cyl(self, r, depth, center, mat, axis='Z', seg=12, r2=None, rot=None, cap=True, sym=False):
        return self._sym(G.add_cylinder(self.bm, r, depth, center, axis, seg, self.m(mat), r2, rot, cap), sym)

    def sphere(self, r, center, mat, seg=10, rings=6, scale=(1, 1, 1), rot=None, sym=False):
        return self._sym(G.add_sphere(self.bm, r, center, seg, rings, self.m(mat), scale, rot), sym)

    def poly(self, pts, mat, sym=False):
        return self._sym(G.add_poly(self.bm, pts, self.m(mat)), sym)

    def loft(self, sections, mat, cap_start=True, cap_end=True, close=True, sym=False):
        return self._sym(G.add_loft(self.bm, sections, self.m(mat), cap_start, cap_end, close), sym)

    def prism(self, profile, lo, hi, mat, axis='X', sym=False):
        return self._sym(G.add_prism(self.bm, profile, lo, hi, axis, self.m(mat)), sym)

    def tbox(self, bottom, top, height, center, mat, top_offset=(0, 0), sym=False):
        return self._sym(G.add_tapered_box(self.bm, bottom, top, height, center, top_offset, self.m(mat)), sym)

    def beam(self, a, b, w, mat, h=None, roll=0.0, sym=False):
        """Rectangular bar from point a to point b (w x h cross-section)."""
        M, L = _frame(a, b, roll)
        ret = bmesh.ops.create_cube(self.bm, size=1.0, matrix=M @ Matrix.Diagonal((w, h if h else w, L, 1.0)))
        G._assign(ret['verts'], self.m(mat))
        return self._sym(ret['verts'], sym)

    def tube(self, a, b, r, mat, seg=8, r2=None, cap=True, sym=False):
        """Round bar from point a to point b."""
        M, L = _frame(a, b)
        ret = bmesh.ops.create_cone(self.bm, cap_ends=cap, cap_tris=False, segments=seg,
                                    radius1=r, radius2=r if r2 is None else r2, depth=L, matrix=M)
        G._assign(ret['verts'], self.m(mat))
        return self._sym(ret['verts'], sym)

    def path(self, pts, r, mat, seg=6, cap=True, sym=False):
        """Chain of tubes through the points (pipes, rails, cables)."""
        out = []
        for a, b in zip(pts[:-1], pts[1:]):
            out += self.tube(a, b, r, mat, seg=seg, cap=cap, sym=sym)
        return out

    def ribbon(self, pts, wdir, w, th, mat, sym=False):
        """Flat strap through the points; wdir = direction across the strap (constant)."""
        P = [Vector(q) for q in pts]
        wv = Vector(wdir).normalized() * (w / 2)
        secs = []
        for i, q in enumerate(P):
            if i == 0:
                t = P[1] - P[0]
            elif i == len(P) - 1:
                t = P[-1] - P[-2]
            else:
                t = P[i + 1] - P[i - 1]
            n = t.cross(wv)
            if n.length < 1e-9:
                n = Vector((0, 0, 1))
            n = n.normalized() * (th / 2)
            secs.append([tuple(q + wv + n), tuple(q - wv + n), tuple(q - wv - n), tuple(q + wv - n)])
        return self._sym(G.add_loft(self.bm, secs, self.m(mat), True, True, True), sym)

    def quad(self, a, b, c, d, mat, sym=False):
        return self.poly([a, b, c, d], mat, sym=sym)

    def ring(self, r_out, r_in, z0, z1, center, mat, seg=16, sym=False):
        """Flat-walled ring / pipe section (annulus extruded along Z)."""
        cx, cy = center[0], center[1]
        secs = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            c, s = math.cos(a), math.sin(a)
            secs.append([(cx + r_out * c, cy + r_out * s, z0), (cx + r_out * c, cy + r_out * s, z1),
                         (cx + r_in * c, cy + r_in * s, z1), (cx + r_in * c, cy + r_in * s, z0)])
        secs.append(secs[0])
        return self._sym(G.add_loft(self.bm, secs, self.m(mat), False, False, True), sym)

    def torus(self, R, r, center, mat, axis='Z', seg=12, rseg=6, rot=None, sym=False, arc=360.0):
        """Torus (or arc of one) around `axis`."""
        secs = []
        full = arc >= 359.9
        for i in range(seg + 1):
            a = math.radians(arc) * i / seg
            ring_pts = []
            for j in range(rseg):
                b = 2 * math.pi * j / rseg
                ring_pts.append(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)))
            secs.append(ring_pts)
        rings = G.add_loft(self.bm, secs, self.m(mat), not full, not full, True)
        A = Matrix.Identity(4)
        if axis == 'X':
            A = Matrix.Rotation(math.pi / 2, 4, 'Y')
        elif axis == 'Y':
            A = Matrix.Rotation(-math.pi / 2, 4, 'X')
        M = Matrix.Translation(Vector(center)) @ G._rot_matrix(rot) @ A
        verts = G.transform(rings, M)
        return self._sym(verts, sym)

    def ladder(self, base, top, width, mat, rungs=None, side_axis=(1, 0, 0), bar=0.05):
        b = Vector(base)
        t = Vector(top)
        d = t - b
        n = rungs or max(2, int(d.length / 0.36))
        s = Vector(side_axis).normalized() * (width / 2)
        out = self.beam(b - s, t - s, bar, mat) + self.beam(b + s, t + s, bar, mat)
        for i in range(1, n):
            c = b + d * (i / n)
            out += self.beam(c - s, c + s, bar * 0.7, mat)
        return out

    def railing(self, pts, h, mat, mid=True, bar=0.045):
        out = []
        P = [Vector(q) for q in pts]
        up = Vector((0, 0, h))
        for a in P:
            out += self.beam(a, a + up, bar, mat)
        for a, b in zip(P[:-1], P[1:]):
            out += self.beam(a + up, b + up, bar, mat)
            if mid:
                out += self.beam(a + up * 0.5, b + up * 0.5, bar * 0.8, mat)
        return out

    def lathe(self, profile, center, mat, seg=12, cap_start=True, cap_end=True, phase=0.0, sym=False):
        """Surface of revolution around Z through `center`. profile = [(radius, z), ...] bottom -> top."""
        cx, cy, cz = center
        secs = []
        for (r, z) in profile:
            r = max(r, 0.002)
            secs.append([(cx + r * math.cos(math.radians(phase) + 2 * math.pi * i / seg),
                          cy + r * math.sin(math.radians(phase) + 2 * math.pi * i / seg), cz + z) for i in range(seg)])
        return self._sym(G.add_loft(self.bm, secs, self.m(mat), cap_start, cap_end, True), sym)

    def slab(self, pts, th, mat, sym=False):
        """Closed plate: polygon `pts` (top face) extruded down by `th` - robust normals for decks / panels."""
        top = [tuple(q) for q in pts]
        bot = [(q[0], q[1], q[2] - th) for q in top]
        return self._sym(G.add_loft(self.bm, [bot, top], self.m(mat), True, True, True), sym)

    def plate(self, pts, th, mat, sym=False):
        """Closed plate extruded along the polygon normal (both sides visible), for arbitrary orientation."""
        P = [Vector(q) for q in pts]
        n = Vector((0, 0, 0))
        for i in range(len(P)):
            a, b = P[i], P[(i + 1) % len(P)]
            n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
        n.normalize()
        top = [tuple(q + n * (th / 2)) for q in P]
        bot = [tuple(q - n * (th / 2)) for q in P]
        return self._sym(G.add_loft(self.bm, [bot, top], self.m(mat), True, True, True), sym)

    def new_verts(self, start):
        return list(self.bm.verts)[start:]

    def count(self):
        return len(self.bm.verts)

    def empty(self):
        return len(self.bm.verts) == 0

    # -- finish
    def obj(self, name=None, parent=None, bevel=None, bevel_angle=30.0, smooth=None, loc=(0, 0, 0),
            rot=(0, 0, 0), solidify=None, solid_mat_offset=0, recalc=True, weld=0.0001, origin=None):
        if not self.mats:
            self.m("Steel")
        ob = G.new_object(_nm(name or self.name), self.bm, parent=parent or CTX.root, materials=self.mats,
                          location=loc, rotation=rot, recalc=recalc, weld=weld)
        if solidify:
            mod = ob.modifiers.new("Solidify", 'SOLIDIFY')
            mod.thickness = solidify
            mod.offset = -1.0
            try:
                mod.use_even_offset = True
                mod.material_offset = solid_mat_offset
                mod.material_offset_rim = solid_mat_offset
            except Exception:
                pass
            G.apply_modifiers(ob)
            _recalc(ob)
            G.box_uv(ob)
        if bevel:
            G.bevel(ob, width=bevel, angle_deg=bevel_angle)
        if smooth is not None:
            G.shade_smooth(ob, smooth)
        if origin is not None:
            G.set_origin(ob, origin)
        return ob


def _recalc(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if len(objs) == 1:
        objs[0].name = _nm(name)
        objs[0].data.name = _nm(name)
        return objs[0]
    ob = G.join(objs, _nm(name))
    return ob


def arc(cx, cy, r, a0, a1, n):
    """n+1 points on a circle arc (degrees), counter-clockwise from a0 to a1."""
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def lerp(a, b, t):
    return a + (b - a) * t


def vlerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))


# ------------------------------------------------------------------------------------------------
# registry / pipeline
# ------------------------------------------------------------------------------------------------
ASSETS = {}
FAMILIES = ["transit", "wreck", "harbour", "park", "airport", "activities", "police", "parachute", "service", "vfx"]


def asset(aid, slot, family, category=None, collision="box", max_tris=2500, root=None, collection=None, **extra):
    """root: Blender name of the root Empty when the plain id is already taken by another author's asset
    (the exported GLB root node is still named like the id)."""
    def deco(fn):
        ASSETS[aid] = dict(id=aid, fn=fn, slot=slot, family=family, category=category or family,
                           collision=collision, max_tris=max_tris, root=root or aid,
                           collection=collection or COLLECTION, extra=extra)
        return fn
    return deco


def rn(aid):
    """Blender root object name of an asset id."""
    a = ASSETS.get(aid)
    return a["root"] if a else aid


def slot_pos(aid):
    idx, dx, dy = ASSETS[aid]["slot"]
    return G.slot(REGION, idx) + Vector((dx, dy, 0.0))


def build(aid):
    a = ASSETS[aid]
    rname = a["root"]
    ex = bpy.data.objects.get(rname)
    if ex is not None and ex.get("gta_author") != AUTHOR:
        raise RuntimeError("object %r exists and is not owned by %s - refusing to rebuild" % (rname, AUTHOR))
    G.object_mode()
    root = G.asset_root(rname, a["collection"], slot_pos(aid), rebuild=True)
    root["gta_author"] = AUTHOR
    CTX.aid = aid
    CTX.prefix = rname
    CTX.root = root
    CTX.markers = {}
    random.seed(sum(ord(c) * (i + 1) for i, c in enumerate(aid)))
    a["fn"](root)
    bpy.context.view_layer.update()
    clash = [o.name for o in root.children_recursive
             if len(o.name) > 4 and o.name[-4] == "." and o.name[-3:].isdigit()]
    if clash:
        raise RuntimeError("%s: duplicate child names (Blender added a numeric suffix): %s" % (aid, clash))
    return root


def build_many(ids):
    for i in ids:
        build(i)


def build_all():
    for i in ASSETS:
        build(i)


def family(name):
    return [i for i, a in ASSETS.items() if a["family"] == name]


def _strip_glb_names(path, prefix, root_from=None, root_to=None):
    """Rewrite node / mesh names inside a GLB: drop the '<asset>.' Blender namespace prefix
    (and rename an aliased root node back to the asset id)."""
    with open(path, "rb") as f:
        data = f.read()
    magic, version, total = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise RuntimeError("not a GLB: " + path)
    jlen, jtype = struct.unpack_from("<II", data, 12)
    js = json.loads(data[20:20 + jlen].decode("utf-8"))
    rest = data[20 + jlen:]
    n = 0
    for key in ("nodes", "meshes"):
        for it in js.get(key, []):
            nm = it.get("name", "")
            if nm.startswith(prefix):
                it["name"] = nm[len(prefix):]
                n += 1
            elif root_from and nm == root_from:
                it["name"] = root_to
                n += 1
    out = json.dumps(js, separators=(",", ":")).encode("utf-8")
    out += b" " * ((4 - len(out) % 4) % 4)
    blob = struct.pack("<4sII", b"glTF", version, 12 + 8 + len(out) + len(rest)) + \
        struct.pack("<II", len(out), jtype) + out + rest
    with open(path, "wb") as f:
        f.write(blob)
    return n


def glb_node_names(aid):
    path = os.path.join(G.MODELS_DIR, EXPORT_DIR, aid + ".glb")
    with open(path, "rb") as f:
        data = f.read()
    jlen, jtype = struct.unpack_from("<II", data, 12)
    js = json.loads(data[20:20 + jlen].decode("utf-8"))
    return [n.get("name", "") for n in js.get("nodes", [])], [m.get("name", "") for m in js.get("materials", [])]


def export(aid):
    a = ASSETS[aid]
    rname = a["root"]
    res = G.validate(rname, a["max_tris"])
    path = G.export_glb(rname, "%s/%s.glb" % (EXPORT_DIR, aid))
    n = _strip_glb_names(path, rname + SEP, rname if rname != aid else None, aid)
    print("GLB_NAMES_FIXED %s: %d" % (aid, n))
    return res


def export_all(ids=None):
    for i in (ids or ASSETS):
        if bpy.data.objects.get(rn(i)) is not None:
            export(i)


def info(aid):
    """Manifest entry for a built asset (sizes / markers converted to Godot axes: (x, z, -y))."""
    a = ASSETS[aid]
    rname = a["root"]
    root = bpy.data.objects.get(rname)
    if root is None:
        return None
    res = G.validate(rname, a["max_tris"])
    # exact bounds from the vertices (validate() uses bounding boxes, too large for rotated children)
    inv = root.matrix_world.inverted()
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for o in root.children_recursive:
        if o.type != 'MESH':
            continue
        Mw = inv @ o.matrix_world
        for v in o.data.vertices:
            w = Mw @ v.co
            for k in range(3):
                mn[k] = min(mn[k], w[k])
                mx[k] = max(mx[k], w[k])
    markers = {}
    yaws = {}
    for o in root.children_recursive:
        if o.type == 'EMPTY' and o.get("gta_group") is None and len(o.children) == 0:
            nm = o.name[len(rname) + len(SEP):] if o.name.startswith(rname + SEP) else o.name
            w = root.matrix_world.inverted() @ o.matrix_world.translation
            markers[nm] = [round(w.x, 3), round(w.z, 3), round(-w.y, 3)]
            yaw = math.degrees(o.matrix_world.to_euler('XYZ').z - root.matrix_world.to_euler('XYZ').z)
            if abs(yaw) > 0.01:
                yaws[nm] = round(yaw, 2)
    e = {
        "id": aid, "file": aid + ".glb", "category": a["category"], "family": a["family"],
        "size": [round(mx[0] - mn[0], 3), round(mx[2] - mn[2], 3), round(mx[1] - mn[1], 3)],
        "aabb_min": [round(mn[0], 3), round(mn[2], 3), round(-mx[1], 3)],
        "aabb_max": [round(mx[0], 3), round(mx[2], 3), round(-mn[1], 3)],
        "collision": a["collision"], "tris": res["tris"], "markers": markers,
    }
    if yaws:
        e["marker_yaw_deg"] = yaws
    nodes = sorted(set(o.name[len(rname) + len(SEP):] for o in root.children_recursive
                       if o.type == 'MESH' and o.name.startswith(rname + SEP)))
    e["nodes"] = nodes
    groups = sorted(set(o.name[len(rname) + len(SEP):] for o in root.children_recursive
                        if o.type == 'EMPTY' and len(o.children) > 0 and o.name.startswith(rname + SEP)))
    if groups:
        e["groups"] = groups
    for k, v in a["extra"].items():
        e[k] = v
    return e


def write_manifest():
    items = []
    for aid in ASSETS:
        e = info(aid)
        if e is not None and os.path.exists(os.path.join(G.MODELS_DIR, EXPORT_DIR, aid + ".glb")):
            items.append(e)
    path = os.path.join(G.MODELS_DIR, EXPORT_DIR, "manifest_misc.json")
    doc = {
        "author": AUTHOR,
        "axes": "Godot: +X right, +Y up, -Z front. size = [x, y, z]; markers = local positions (also present as Node3D children in the GLB).",
        "misc": items,
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1)
    print("MANIFEST_WRITTEN:", path, len(items))
    return path


def sheet(ids, out_name, views=("three_quarter", "side"), res=320, cols=4):
    """Contact sheet with one tile per (asset, view) - used for family previews."""
    import numpy as np
    tiles = []
    tmp_name = "_tile_" + out_name
    for aid in ids:
        for v in views:
            with _Cull():
                p = G.preview(rn(aid), tmp_name, views=(v,), res=res)
            img = bpy.data.images.load(p, check_existing=False)
            arr = np.empty(res * res * 4, dtype=np.float32)
            img.pixels.foreach_get(arr)
            bpy.data.images.remove(img)
            tiles.append(arr.reshape(res, res, 4))
    rows = (len(tiles) + cols - 1) // cols
    sh = np.zeros((rows * res, cols * res, 4), dtype=np.float32)
    sh[..., 3] = 1.0
    for i, t in enumerate(tiles):
        rr = rows - 1 - (i // cols)
        cc = i % cols
        sh[rr * res:(rr + 1) * res, cc * res:(cc + 1) * res, :] = t
    out_path = os.path.join(G.PREVIEW_DIR, out_name + ".png")
    out = bpy.data.images.new("_misc_sheet", cols * res, rows * res, alpha=False)
    out.pixels.foreach_set(sh.ravel())
    out.filepath_raw = out_path
    out.file_format = 'PNG'
    out.save()
    bpy.data.images.remove(out)
    try:
        os.remove(os.path.join(G.PREVIEW_DIR, tmp_name + ".png"))
    except Exception:
        pass
    print("SHEET_SAVED:", out_path)
    return out_path


class _Cull:
    """Render previews with backface culling so flipped faces show up as holes (like in Godot)."""

    def __enter__(self):
        sh = bpy.context.scene.display.shading
        self.prev = getattr(sh, "show_backface_culling", None)
        try:
            sh.show_backface_culling = True
        except Exception:
            pass

    def __exit__(self, *a):
        if self.prev is not None:
            try:
                bpy.context.scene.display.shading.show_backface_culling = self.prev
            except Exception:
                pass


def preview(names, out_name, views=("three_quarter", "side", "front", "top"), res=420, **kw):
    names = [rn(n) for n in ([names] if isinstance(names, str) else names)]
    with _Cull():
        return G.preview(names, out_name, views=views, res=res, **kw)


def closeup(aid, center, radius, out_name, views=("three_quarter", "side"), res=512, perspective=False):
    """Preview of a region of one asset: frames a sphere (root-local center, radius). Other objects are
    hidden for the render only (same thing G.preview does) and restored afterwards."""
    root = bpy.data.objects[rn(aid)]
    mine = set(G.children_of(root))
    me = bpy.data.meshes.new("_misc_focus")
    c = Vector(center)
    k = radius / math.sqrt(3.0)
    me.from_pydata([tuple(c - Vector((k, k, k))), tuple(c + Vector((k, k, k)))], [], [])
    ob = bpy.data.objects.new("_misc_focus", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = root
    hidden = []
    try:
        for o in bpy.context.scene.objects:
            if o not in mine and o is not ob and not o.hide_render:
                o.hide_render = True
                hidden.append(o)
        bpy.context.view_layer.update()
        with _Cull():
            return G.preview("_misc_focus", out_name, views=views, res=res, isolate=False, perspective=perspective)
    finally:
        for o in hidden:
            try:
                o.hide_render = False
            except Exception:
                pass
        bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.meshes.remove(me)


# ================================================================================================
# TRANSIT : tram, rail_straight, rail_post
# ================================================================================================
TRAM_FLOOR = 0.35
TRAM_WIRE_Z = 4.62

_TRAM_ROWS_Z = [0.18, 0.62, 0.95, 1.05, 2.30, 2.64, 2.80]
_TRAM_PLAN = [   # per row : (x, y) at sections S0, S1a, S1b, S2, S3(centre line)
    [(1.25, 7.40), (1.17, 8.30), (1.09, 8.50), (0.58, 8.95), (0.0, 9.05)],
    [(1.25, 7.40), (1.21, 8.35), (1.13, 8.55), (0.62, 9.05), (0.0, 9.17)],
    [(1.25, 7.40), (1.202, 8.312), (1.122, 8.512), (0.605, 8.996), (0.0, 9.116)],
    [(1.25, 7.40), (1.20, 8.30), (1.12, 8.50), (0.60, 8.98), (0.0, 9.10)],
    [(1.25, 7.40), (1.14, 7.86), (1.06, 7.99), (0.55, 8.23), (0.0, 8.31)],
    [(1.25, 7.40), (1.09, 7.74), (1.01, 7.85), (0.52, 8.06), (0.0, 8.13)],
    [(1.03, 7.40), (0.91, 7.62), (0.85, 7.70), (0.45, 7.88), (0.0, 7.94)],
]


def _tram_nose(shell, glass, sy):
    """One cab end. sy = +1 front, -1 rear. Adds shell faces to `shell`, glazing to `glass`."""
    P = [[(x, y * sy, z) for (x, y) in row] for row, z in zip(_TRAM_PLAN, _TRAM_ROWS_Z)]
    band_mat = ["Teal", "CarWhite", "Coral", "Trim", "Trim", "RoofGrey"]
    for r in range(6):
        for s in range(4):
            q = [P[r][s], P[r][s + 1], P[r + 1][s + 1], P[r + 1][s]]
            if sy < 0:
                q.reverse()
            if r == 3 and s != 1:
                glass.poly(q, "M_Glass", sym=True)
            else:
                shell.poly(q, band_mat[r], sym=True)
    shell.poly([P[6][0], P[6][1], P[6][2], P[6][3], P[6][4], (0.0, 7.40 * sy, 2.80)], "RoofGrey", sym=True)
    shell.poly([P[0][0], P[0][1], P[0][2], P[0][3], P[0][4], (0.0, 7.40 * sy, 0.18)], "Trim", sym=True)


def _tram_seat(p, y_edge, facing, x=0.83, z=0.72):
    """Podium seat on a wheel box; facing = +1 looks toward +Y. y_edge = box edge the legs hang over."""
    f = facing
    yc = y_edge - f * 0.225
    p.box((0.60, 0.45, 0.10), (x, yc, z + 0.05), "Teal", sym=True)
    p.box((0.60, 0.09, 0.62), (x, y_edge - f * 0.49, z + 0.40), "Teal", rot=(math.radians(-8 * f), 0, 0), sym=True)
    p.box((0.05, 0.11, 0.12), (x - 0.30, y_edge - f * 0.52, z + 0.72), "HazardYellow", sym=True)


@asset("tram", slot=(0, 0.0, 0.0), family="transit", category="transit", collision="trimesh", max_tris=7000,
       note="front = -Z. Doors_R / Doors_L are Node3D groups, each with four sliding leaf meshes Door_<side><n>_<A|B> "
            "(slide a leaf 0.7 m along Z away from its partner, or hide the group). Door_1 / Door_2 = boarding points on the "
            "right side at floor level (marker -Z looks into the tram). Seat_n = hip points facing forward, Stand_n = floor points",
       floor_height=TRAM_FLOOR, interior_clear_height=2.21, wire_height=TRAM_WIRE_Z, track_gauge=1.435,
       bogie_centres_z=[-5.9, -1.8, 1.8, 5.9],
       collision_boxes=[  # optional cheap compound collider, Godot axes: [cx, cy, cz, sx, sy, sz]
           [0.0, 0.30, 0.0, 2.36, 0.10, 17.6],      # floor
           [0.0, 2.70, 0.0, 2.44, 0.20, 17.2],      # roof
           [1.215, 1.475, -6.2, 0.07, 2.25, 3.4], [-1.215, 1.475, -6.2, 0.07, 2.25, 3.4],
           [1.215, 1.475, 0.0, 0.07, 2.25, 6.2], [-1.215, 1.475, 0.0, 0.07, 2.25, 6.2],
           [1.215, 1.475, 6.2, 0.07, 2.25, 3.4], [-1.215, 1.475, 6.2, 0.07, 2.25, 3.4],
           [0.0, 1.45, -7.28, 2.36, 2.2, 0.06], [0.0, 1.45, 7.28, 2.36, 2.2, 0.06],      # cab bulkheads
           [0.0, 1.40, -8.2, 1.9, 2.4, 1.7], [0.0, 1.40, 8.2, 1.9, 2.4, 1.7],            # cab noses
       ])
def build_tram(root):
    FL = TRAM_FLOOR
    HW = 1.25          # half width
    XI = 1.18          # inner wall face
    XW = 1.215         # wall centre
    WT = 0.07
    ZA, ZB, _zs, ZC, ZD, ZE, ZF = _TRAM_ROWS_Z
    Y0, Y1 = 0.40, 7.40
    D0, D1 = 3.10, 4.50          # doorway
    BOG = (1.8, 5.9)             # bogie centres (per car, mirrored for the rear car)

    # ---------------- car shell (front car, both sides), later mirrored to the rear car
    sh = Part("shell")
    # teal skirt band
    for (a, b, z0) in [(Y0, 0.8, ZA), (0.8, 2.8, 0.47), (2.8, D0, ZA), (D1, 4.9, ZA), (4.9, 6.9, 0.47), (6.9, Y1, ZA)]:
        sh.bx(XI, HW, a, b, z0, ZB, "Teal", sym=True)
    sh.bx(XI, HW, D0, D1, ZA, FL, "Teal", sym=True)                    # door sill
    sh.bx(XI - 0.10, HW + 0.004, D0, D1, FL - 0.012, FL + 0.012, "HazardYellow", sym=True)   # yellow threshold
    # white band + coral stripe
    for (a, b) in [(Y0, D0), (D1, Y1)]:
        sh.bx(XI, HW, a, b, ZB, 0.95, "CarWhite", sym=True)
        sh.bx(XI, HW, a, b, 0.95, ZC, "Coral", sym=True)
    # window pillars (black ribbon)
    for (a, b) in [(Y0, 0.70), (1.75, 1.87), (2.90, D0), (D1, 4.70), (5.85, 5.97), (7.12, Y1)]:
        sh.bx(XI, HW, a, b, ZC, ZD, "Trim", sym=True)
    # upper band
    sh.bx(XI, HW, Y0, Y1, ZD, 2.60, "CarWhite", sym=True)
    # roof (chamfered) + ceiling
    sh.prism([(-HW, 2.60), (HW, 2.60), (HW, ZE), (1.03, ZF), (-1.03, ZF), (-HW, ZE)], Y0, Y1, "RoofGrey", axis='Y')
    sh.bx(-XI, XI, Y0, 7.25, 2.56, 2.60, "Cream")
    # floor + underframe
    sh.bx(-XI, XI, Y0, 7.31, 0.25, FL, "SteelDark")
    sh.bx(-0.55, 0.55, Y0, 7.30, 0.13, 0.25, "Trim")
    # gangway portal (articulation end)
    sh.bx(0.58, XI, Y0, Y0 + 0.12, FL, 2.56, "Cream", sym=True)
    sh.bx(-0.58, 0.58, Y0, Y0 + 0.12, 2.32, 2.56, "Cream")
    # cab bulkhead with door panel
    sh.bx(-XI, XI, 7.25, 7.31, FL, 2.56, "Navy")
    sh.bx(-0.33, 0.33, 7.235, 7.25, FL + 0.02, 2.25, "Steel")
    sh.bx(0.20, 0.25, 7.215, 7.235, 1.25, 1.42, "HazardYellow")
    # interior wheel boxes + seats
    for c in BOG:
        sh.bx(0.50, XI, c - 0.95, c + 0.95, FL, 0.72, "WarmGrey", sym=True)
        _tram_seat(sh, c + 0.95, +1)
        _tram_seat(sh, c - 0.95, -1)
        sh.bx(0.56, XI, c - 0.40, c + 0.40, 0.72, 1.02, "Navy", sym=True)     # equipment locker between seat backs
    # grab poles + ceiling rails
    for y in (D0 - 0.12, D1 + 0.12):
        sh.cyl(0.022, 2.56 - FL, (0.50, y, (2.56 + FL) / 2), "HazardYellow", seg=6, cap=False, sym=True)
    sh.beam((0.50, 0.9, 2.36), (0.50, 6.9, 2.36), 0.035, "HazardYellow", sym=True)
    for y in (1.2, 5.2, 6.6):
        sh.beam((0.50, y, 2.36), (0.50, y, 2.56), 0.03, "HazardYellow", sym=True)
    # door buttons (emissive)
    sh.bx(HW, HW + 0.012, D1 + 0.06, D1 + 0.14, 1.15, 1.27, "NeonGreen", sym=True)
    # bogies
    for c in BOG:
        sh.bx(-0.62, 0.62, c - 0.80, c + 0.80, 0.16, 0.34, "Trim")
        sh.bx(0.80, 0.92, c - 0.70, c + 0.70, 0.22, 0.40, "Charcoal", sym=True)
        for dy in (-0.45, 0.45):
            sh.cyl(0.30, 0.11, (0.72, c + dy, 0.33), "Steel", axis='X', seg=12, sym=True)
            sh.cyl(0.12, 0.03, (0.79, c + dy, 0.33), "SteelDark", axis='X', seg=8, sym=True)
    # roof cable duct
    sh.bx(-0.16, 0.16, 0.7, 7.2, ZF, ZF + 0.07, "SteelDark")
    # cab side mirrors
    sh.beam((1.22, 7.72, 2.05), (1.40, 7.80, 2.05), 0.035, "Trim", sym=True)
    sh.box((0.05, 0.12, 0.30), (1.41, 7.80, 1.95), "Trim", sym=True)
    # cab interior: floor, console, driver seat
    cabf = [(1.17, 7.31), (1.13, 8.30), (1.05, 8.50), (0.56, 8.95), (0.0, 9.06), (-0.56, 8.95), (-1.05, 8.50), (-1.13, 8.30), (-1.17, 7.31)]
    sh.prism(cabf, 0.24, FL + 0.03, "SteelDark", axis='Z')
    sh.box((1.5, 0.42, 0.62), (0.0, 8.42, FL + 0.34), "Charcoal")
    sh.box((1.3, 0.30, 0.10), (0.0, 8.30, FL + 0.70), "Trim", rot=(math.radians(-22), 0, 0))
    sh.box((0.48, 0.46, 0.12), (0.0, 7.78, FL + 0.50), "Navy")
    sh.box((0.48, 0.10, 0.62), (0.0, 7.55, FL + 0.82), "Navy")
    sh.box((0.16, 0.16, 0.44), (0.0, 7.78, FL + 0.22), "Trim")
    sh.mirror_all(1)

    # ---------------- nose shells (solidified so the cab has an inside)
    ns = Part("nose")
    gF = Part("Glass_Front")
    gB = Part("Glass_Rear")
    _tram_nose(ns, gF, +1)
    _tram_nose(ns, gB, -1)
    ns.m("Interior")

    # ---------------- details that differ front / rear
    dt = Part("detail")
    lamp_c = (0.875, 8.795, 0.845)
    for sy, lm in ((1, "M_Headlight"), (-1, "M_Taillight")):
        yaw = math.radians(-44.0) * sy
        dt.box((0.36, 0.07, 0.17), (lamp_c[0], lamp_c[1] * sy, lamp_c[2]), lm, rot=(0, 0, yaw), sym=True)
        dt.box((0.42, 0.05, 0.23), (lamp_c[0] - 0.012, (lamp_c[1] - 0.012) * sy, lamp_c[2]), "Trim", rot=(0, 0, yaw), sym=True)
        # coupler hatch / bumper
        dt.box((0.80, 0.10, 0.26), (0.0, 9.10 * sy, 0.42), "Charcoal")
        dt.box((0.30, 0.08, 0.12), (0.0, 9.15 * sy, 0.42), "Steel")
    # front: indicators + destination board ; rear: route board
    dt.box((0.12, 0.07, 0.17), (1.18, 8.435, 0.845), "M_Indicator", rot=(0, 0, math.radians(-68)), sym=True)
    dt.box((0.12, 0.07, 0.17), (1.18, -8.435, 0.845), "M_Indicator", rot=(0, 0, math.radians(68)), sym=True)
    tilt = math.atan2(0.18, 0.34)
    dt.box((0.95, 0.05, 0.20), (0.0, 8.232, 2.476), "NeonOrange", rot=(tilt, 0, 0))
    dt.box((0.50, 0.05, 0.20), (0.0, -8.232, 2.476), "NeonOrange", rot=(-tilt, 0, 0))

    # ---------------- articulation (bellows + turntable)
    bl = Part("bellows")
    secs = []
    n = 8
    for i in range(n + 1):
        y = -0.42 + 0.84 * i / n
        k = 1.0 if i % 2 == 0 else 0.93
        w, z0, z1 = 1.20 * k, 0.22 + (1 - k) * 1.2, 2.70 * (0.97 + 0.03 * k) - (1 - k) * 0.6
        c = 0.14
        secs.append([(-w, y, z0 + c), (-w + c, y, z0), (w - c, y, z0), (w, y, z0 + c),
                     (w, y, z1 - c), (w - c, y, z1), (-w + c, y, z1), (-w, y, z1 - c)])
    bl.loft(secs, "Trim", cap_start=False, cap_end=False)
    tt = Part("turntable")
    tt.bx(-1.02, 1.02, -0.44, 0.44, 0.27, FL, "Steel")
    tt.cyl(0.78, 0.012, (0, 0, FL + 0.004), "SteelDark", seg=14)

    # ---------------- roof equipment (beveled)
    rk = Part("roofkit")
    for sy in (1, -1):
        rk.box((1.70, 2.50, 0.30), (0.0, 5.75 * sy, ZF + 0.15), "Steel")
        rk.box((1.30, 0.90, 0.22), (0.0, 1.20 * sy, ZF + 0.11), "WarmGrey")
        for dy in (-0.7, 0.0, 0.7):
            rk.box((1.2, 0.10, 0.03), (0.0, (5.75 + dy) * sy, ZF + 0.31), "SteelDark")
    rk.box((1.50, 1.60, 0.20), (0.0, -3.4, ZF + 0.10), "Steel")
    rk.box((1.10, 0.50, 0.26), (0.0, -3.4, ZF + 0.13), "SteelDark")

    objs = [
        sh.obj("~shell"),
        ns.obj("~nose", solidify=0.05, solid_mat_offset=99),
        dt.obj("~detail"),
        bl.obj("~bellows", solidify=0.05),
        tt.obj("~turntable"),
        rk.obj("~roofkit", bevel=0.035),
    ]
    join(objs, "Body")

    # ---------------- glazing
    gF.obj("Glass_Front")
    gB.obj("Glass_Rear")
    for sx, nm in ((1, "Glass_R"), (-1, "Glass_L")):
        g = Part(nm)
        for sy in (1, -1):
            for (a, b) in [(0.66, 2.94), (4.66, 7.16)]:
                g.bx(sx * 1.205, sx * 1.225, a * sy, b * sy, ZC - 0.02, ZD + 0.02, "M_Glass")
        g.obj(nm)

    # ---------------- doors: Doors_R / Doors_L groups with four sliding leaves each
    for sx, side in ((1, "R"), (-1, "L")):
        grp = group("Doors_" + side)
        for n_door, yc in ((1, (D0 + D1) / 2), (2, -(D0 + D1) / 2)):
            for leaf, off in (("A", 0.35), ("B", -0.35)):
                d = Part("Door_%s%d_%s" % (side, n_door, leaf))
                x0, x1 = -0.055 * sx, -0.005 * sx          # leaf origin = outer face, leaf centre, floor level
                d.bx(x0, x1, -0.345, 0.345, 0.0, 0.62, "Coral")
                d.bx(x0, x1, -0.345, -0.275, 0.62, 1.93, "Coral")
                d.bx(x0, x1, 0.275, 0.345, 0.62, 1.93, "Coral")
                d.bx(x0, x1, -0.345, 0.345, 1.83, 1.93, "Coral")
                d.bx(-0.04 * sx, -0.02 * sx, -0.275, 0.275, 0.62, 1.83, "M_Glass")
                hy = -0.30 if leaf == "A" else 0.30         # handle near the meeting edge
                d.bx(-0.005 * sx, 0.02 * sx, hy - 0.02, hy + 0.02, 0.80, 1.25, "HazardYellow")
                d.obj(parent=grp, loc=(sx * HW, yc + off, FL + 0.01))

    # ---------------- pantograph (front car)
    pg = Part("Pantograph")
    by, bz = 3.4, ZF
    pg.box((1.10, 1.50, 0.05), (0, 0, 0.115), "SteelDark")
    for (x, y) in ((-0.45, -0.6), (0.45, -0.6), (-0.45, 0.6), (0.45, 0.6)):
        pg.cyl(0.05, 0.09, (x, y, 0.045), "Terracotta", seg=6)
    knee = (0.0, -1.05, 0.95)
    head_z = TRAM_WIRE_Z - bz - 0.03
    pg.tube((0.28, 0.55, 0.16), (0.10, knee[1], knee[2]), 0.035, "Coral", seg=6, sym=True)
    pg.tube((0.0, 0.62, 0.16), (0.0, knee[1] + 0.25, knee[2] - 0.20), 0.02, "Steel", seg=5)
    pg.box((0.34, 0.10, 0.10), knee, "SteelDark")
    pg.tube((0.10, knee[1], knee[2]), (0.26, -0.20, head_z - 0.08), 0.028, "Coral", seg=6, sym=True)
    pg.box((0.62, 0.06, 0.06), (0.0, -0.20, head_z - 0.08), "SteelDark")
    for dy in (-0.16, 0.16):
        pg.box((1.20, 0.05, 0.035), (0.0, -0.20 + dy, head_z + 0.012), "Charcoal")
        pg.beam((0.60, -0.20 + dy, head_z + 0.012), (0.86, -0.20 + dy, head_z - 0.15), 0.035, "Charcoal", sym=True)
        pg.beam((0.0, -0.20 + dy, head_z), (0.0, -0.20, head_z - 0.08), 0.03, "SteelDark")
    pg.box((0.05, 0.36, 0.03), (0.30, -0.20, head_z - 0.01), "SteelDark", sym=True)
    pg.obj("Pantograph", loc=(0.0, by, bz))

    # ---------------- markers
    marker("Door_1", (1.45, (D0 + D1) / 2, FL), yaw_deg=90.0)
    marker("Door_2", (1.45, -(D0 + D1) / 2, FL), yaw_deg=90.0)
    marker("Seat_1", (0.83, BOG[1] + 0.725, 0.82))
    marker("Seat_2", (-0.83, BOG[1] + 0.725, 0.82))
    marker("Seat_3", (0.83, BOG[0] + 0.725, 0.82))
    marker("Seat_4", (-0.83, BOG[0] + 0.725, 0.82))
    marker("Stand_1", (0.0, 3.45, FL))
    marker("Stand_2", (0.0, 4.15, FL))
    marker("Stand_3", (0.0, -3.45, FL))
    marker("Stand_4", (0.0, -4.15, FL))
    marker("Light_Head_L", (-0.9, 8.9, 0.85))
    marker("Light_Head_R", (0.9, 8.9, 0.85))
    marker("Light_Tail_L", (-0.9, -8.9, 0.85))
    marker("Light_Tail_R", (0.9, -8.9, 0.85))
    marker("Pantograph_Top", (0.0, by - 0.20, TRAM_WIRE_Z))


@asset("rail_straight", slot=(1, -5.0, -6.0), family="transit", category="transit", collision="none", max_tris=400,
       length=4.0, track_gauge=1.435)
def build_rail_straight(root):
    p = Part("Track")
    # concrete track bed with chamfered shoulders
    p.prism([(-1.25, 0.0), (1.25, 0.0), (1.25, 0.012), (1.20, 0.03), (-1.20, 0.03), (-1.25, 0.012)], -2.0, 2.0, "ConcreteDark", axis='Y')
    # paved infill between and beside the rails
    p.bx(-0.62, 0.62, -2.0, 2.0, 0.03, 0.036, "AsphaltLight")
    p.bx(0.82, 1.14, -2.0, 2.0, 0.03, 0.036, "AsphaltLight", sym=True)
    # grooved rails
    g = 0.7175
    p.bx(g - 0.015, g + 0.05, -2.0, 2.0, 0.03, 0.05, "Steel", sym=True)
    p.bx(g - 0.085, g - 0.055, -2.0, 2.0, 0.03, 0.046, "Steel", sym=True)
    p.bx(g - 0.055, g - 0.015, -2.0, 2.0, 0.03, 0.034, "Trim", sym=True)
    # expansion joints
    for y in (-1.0, 1.0):
        p.bx(-0.62, 0.62, y - 0.012, y + 0.012, 0.03, 0.0375, "Asphalt")
    p.obj("Track")


@asset("rail_post", slot=(1, 5.0, -6.0), family="transit", category="transit", collision="box", max_tris=600,
       wire_height=TRAM_WIRE_Z, note="pole stands 2.4 m left of the track centre; the arm reaches toward +X")
def build_rail_post(root):
    p = Part("Post")
    p.box((0.56, 0.56, 0.08), (0, 0, 0.04), "ConcreteDark")
    p.cyl(0.17, 0.5, (0, 0, 0.33), "Teal", seg=8, r2=0.14)
    p.cyl(0.115, 6.2, (0, 0, 3.68), "SteelDark", seg=8, r2=0.085)
    p.cyl(0.10, 0.10, (0, 0, 6.83), "Teal", seg=8, r2=0.03)
    # cantilever + stay
    p.tube((0, 0, 5.55), (2.75, 0, 5.75), 0.045, "SteelDark", seg=6)
    p.tube((0, 0, 6.6), (2.2, 0, 5.74), 0.022, "Steel", seg=5)
    p.cyl(0.13, 0.12, (0, 0, 5.55), "Teal", seg=8)
    p.cyl(0.13, 0.08, (0, 0, 6.6), "Teal", seg=8)
    # insulators + dropper + steady arm
    for x in (1.2, 2.4):
        zt = 5.55 + 0.2 * x / 2.75
        p.cyl(0.055, 0.22, (x, 0, zt - 0.15), "Terracotta", seg=6)
        p.cyl(0.075, 0.03, (x, 0, zt - 0.12), "Terracotta", seg=6)
        p.cyl(0.075, 0.03, (x, 0, zt - 0.19), "Terracotta", seg=6)
    p.tube((1.2, 0, 5.36), (2.4, 0, TRAM_WIRE_Z + 0.05), 0.02, "Steel", seg=5)
    p.tube((2.4, 0, 5.44), (2.4, 0, TRAM_WIRE_Z), 0.015, "Steel", seg=5)
    p.box((0.10, 0.22, 0.05), (2.4, 0, TRAM_WIRE_Z + 0.01), "Brass")
    p.obj("Post")
    marker("Wire", (2.4, 0.0, TRAM_WIRE_Z))


# ================================================================================================
# WRECK : shipwreck (sunken coastal trawler, broken in two)
# ================================================================================================
_SHIP_ST = [   # (y, half breadth, keel z, deck z) - intact ship, bow toward +Y, keel on z = 0
    (-11.0, 2.05, 1.30, 3.30), (-10.0, 2.45, 0.60, 3.25), (-8.5, 2.70, 0.15, 3.18), (-7.0, 2.80, 0.0, 3.12),
    (-5.5, 2.80, 0.0, 3.08), (-4.0, 2.80, 0.0, 3.05), (-2.5, 2.80, 0.0, 3.03), (-1.0, 2.80, 0.0, 3.02),
    (0.5, 2.80, 0.0, 3.02), (2.0, 2.80, 0.0, 3.03), (3.5, 2.78, 0.0, 3.06), (5.0, 2.68, 0.0, 3.12),
    (6.5, 2.45, 0.0, 3.22), (8.0, 2.00, 0.05, 3.38), (9.2, 1.40, 0.25, 3.56), (10.2, 0.70, 0.80, 3.76),
    (11.0, 0.06, 1.90, 3.95),
]


def _ship_ring(st, jit=None):
    """Open-top hull section: 11 points, port rail -> keel -> starboard rail."""
    y, B, k, d = st
    h = d - k
    bw = 0.75 if y < 7.5 else 0.95
    fl = 0.0 if y < 6.0 else 0.22 * min(1.0, (y - 6.0) / 3.0)
    half = [(0.0, k), (0.45 * B, k + 0.03 * h), (0.80 * B, k + 0.16 * h), (0.97 * B, k + 0.42 * h), (B, d), (B + fl, d + bw)]
    ring = [(-x, z) for (x, z) in reversed(half[1:])] + half
    return [(x, y + (jit[j] if jit else 0.0), z) for j, (x, z) in enumerate(ring)]


def _holed_quad(part, corners, mat, rnd, lo=0.30, hi=0.78):
    """A plate with an irregular torn hole: 4 corner points -> 4 pentagons around an 8 point hole."""
    C = [Vector(p) for p in corners]
    ctr = (C[0] + C[1] + C[2] + C[3]) / 4
    targets = []
    for k in range(4):
        targets.append(C[k])
        targets.append((C[k] + C[(k + 1) % 4]) / 2)
    inner = [ctr.lerp(t, rnd.uniform(lo, hi)) for t in targets]
    for k in range(4):
        part.poly([C[k], C[(k + 1) % 4], inner[(2 * k + 2) % 8], inner[2 * k + 1], inner[2 * k]], mat)


def _ship_hull(name, stations, break_end, holes, rnd):
    """Hull plating of one half. break_end: 0 = first station is the torn end, -1 = last one."""
    p = Part(name)
    rings = []
    n = len(stations)
    for i, st in enumerate(stations):
        torn = (i == 0 and break_end == 0) or (i == n - 1 and break_end == -1)
        jit = [rnd.uniform(-0.9, 0.6) * (1 if break_end == -1 else -1) for _ in range(11)] if torn else None
        rings.append(_ship_ring(st, jit))
    for i in range(n - 1):
        streak = (rnd.random() < 0.38, rnd.random() < 0.38)     # rust running down from the deck (port, starboard)
        for j in range(10):
            row = min(j, 9 - j)          # 0 = bulwark, 1 = upper side, 2 = lower side, 3/4 = bottom
            st = streak[0 if j < 5 else 1]
            r = rnd.random()
            if row == 0:
                m = "Rust" if (st and r < 0.7) else "WarmGrey"
            elif row == 1:
                m = "Rust" if st else ("Trunk" if r < 0.1 else "SteelDark")
            elif row == 2:
                m = "Rust" if (st and r < 0.5) else ("Trunk" if r < 0.12 else "SteelDark")
            else:
                m = "Brick" if r > 0.3 else ("Rust" if r > 0.12 else "WoodDark")
            q = [rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j]]
            if (i, j) in holes:
                _holed_quad(p, q, m, rnd)
            else:
                p.poly(q, m)
    return p, rings


def _ship_deck(p, stations, rnd, hatch=(None, None), torn_first=False, torn_last=False, y_min=None):
    n = len(stations)
    rows = []
    for i, (y, B, k, d) in enumerate(stations):
        xs = [-0.985 * B, -0.5 * B, 0.5 * B, 0.985 * B]
        torn = (i == 0 and torn_first) or (i == n - 1 and torn_last)
        row = []
        for x in xs:
            if torn:
                s = 1 if torn_last else -1
                row.append((x, y + s * rnd.uniform(-1.2, 0.3), d - rnd.uniform(0.0, 0.45)))
            else:
                row.append((x, y, d))
        rows.append(row)
    for i in range(n - 1):
        ya, yb = stations[i][0], stations[i + 1][0]
        for c in range(3):
            if c == 1 and hatch[0] is not None and ya >= hatch[0] - 0.01 and yb <= hatch[1] + 0.01:
                continue
            m = "Trunk" if rnd.random() > 0.3 else ("Rust" if rnd.random() > 0.4 else "WoodDark")
            p.poly([rows[i][c], rows[i][c + 1], rows[i + 1][c + 1], rows[i + 1][c]], m)


def _ship_break_frames(p, st, direction, rnd):
    """Exposed ribs, deck beam and bent stringers at the torn end."""
    y, B, k, d = st
    ring = _ship_ring((y, B * 0.955, k + 0.06, d - 0.05))
    for j in range(1, 9):
        if rnd.random() < 0.2:
            continue
        p.beam(ring[j], ring[j + 1], 0.13, "Rust", h=0.22)
    p.beam((-B * 0.95, y, d - 0.16), (B * 0.95, y, d - 0.16), 0.16, "WoodDark", h=0.2)
    for j in (1, 2, 3, 5, 7, 8, 9):
        a = Vector(ring[j])
        L = rnd.uniform(0.5, 1.7)
        b = a + Vector((rnd.uniform(-0.25, 0.25), direction * L, -rnd.uniform(0.05, 0.6)))
        p.beam(a - Vector((0, direction * 0.8, 0)), b, 0.11, "Rust" if rnd.random() > 0.4 else "WoodDark", h=0.14)
    for x in (-1.4, 0.0, 1.4):
        a = Vector((x * B / 2.8, y - direction * 0.6, d - 0.14))
        b = a + Vector((rnd.uniform(-0.2, 0.2), direction * rnd.uniform(1.0, 2.0), -rnd.uniform(0.2, 0.9)))
        p.beam(a, b, 0.12, "WoodDark", h=0.16)


def _algae(p, pos, r, rnd):
    p.sphere(r, pos, "Olive" if rnd.random() > 0.5 else "GrassDark", seg=6, rings=4,
             scale=(1.0, rnd.uniform(0.7, 1.3), rnd.uniform(0.35, 0.55)), rot=(0, 0, rnd.uniform(0, 3.1)))


def _kelp(p, base, height, rnd):
    """Upright wavy seaweed blade (3 tapered segments)."""
    b = Vector(base)
    pts = [b]
    for i in range(1, 4):
        pts.append(b + Vector((rnd.uniform(-0.28, 0.28), rnd.uniform(-0.28, 0.28), height * i / 3.0)))
    m = rnd.choice(["GrassDark", "Olive", "LeafDark"])
    rr = [0.09, 0.075, 0.05, 0.012]
    for i in range(3):
        p.tube(pts[i], pts[i + 1], rr[i], m, seg=4, r2=rr[i + 1], cap=(i == 0))


@asset("shipwreck", slot=(2, 0.0, 0.0), family="wreck", category="set_piece", collision="trimesh", max_tris=6000,
       note="origin = seabed level at the centre; the two hull halves are sunk up to ~1 m into the seabed by design")
def build_shipwreck(root):
    rnd = random.Random(4711)
    ST_S = _SHIP_ST[:8] + [(0.3, 2.80, 0.0, 3.02)]            # stern half: transom .. break
    ST_B = [(0.8, 2.80, 0.0, 3.03)] + _SHIP_ST[9:]            # bow half: break .. stem

    # =============================== STERN HALF (ship space) ===============================
    hull, rings = _ship_hull("~s_hull", ST_S, -1, {(3, 8), (5, 7), (6, 2), (1, 1)}, rnd)
    hull.poly(list(rings[0]), "SteelDark")                     # transom
    hull.m("WoodDark")
    deck = Part("~s_deck")
    _ship_deck(deck, ST_S, rnd, torn_last=True)
    deck.m("WoodDark")

    hs = Part("~s_house")                                      # beveled main volumes
    hs.bx(-2.05, 2.05, -9.8, -4.6, 3.0, 5.45, "Cream")
    hs.bx(-2.35, 2.35, -10.2, -4.3, 5.45, 5.57, "WarmGrey")
    hs.bx(-1.65, 1.65, -8.0, -4.9, 5.57, 7.75, "Cream")
    hs.bx(-1.92, 1.92, -8.25, -4.5, 7.75, 7.87, "WarmGrey")

    sd = Part("~s_detail")
    # wheelhouse windows (front + sides), rust streaks, doors, portholes
    for x in (-1.2, -0.4, 0.4, 1.2):
        sd.bx(x - 0.33, x + 0.33, -4.9, -4.87, 6.50, 7.30, "WindowDark")
    for y in (-7.3, -6.45, -5.6):
        sd.bx(1.65, 1.68, y - 0.34, y + 0.34, 6.50, 7.30, "WindowDark", sym=True)
    sd.bx(-0.4, 0.4, -8.03, -8.0, 5.65, 7.45, "WoodDark")                  # wheelhouse back door
    for y in (-9.0, -7.9, -6.8, -5.7):
        sd.cyl(0.24, 0.04, (2.06, y, 4.55), "Rust", axis='X', seg=8, sym=True)
        sd.cyl(0.17, 0.05, (2.065, y, 4.55), "WindowDark", axis='X', seg=8, sym=True)
    for x in (-1.25, 0.0, 1.25):
        sd.cyl(0.24, 0.04, (x, -4.59, 4.6), "Rust", axis='Y', seg=8)
        sd.cyl(0.17, 0.05, (x, -4.585, 4.6), "WindowDark", axis='Y', seg=8)
    sd.bx(2.05, 2.08, -5.55, -4.85, 3.12, 5.0, "WoodDark")                 # side doors (one open = dark)
    sd.bx(-2.08, -2.05, -5.55, -4.85, 3.12, 5.0, "Rust")
    for (x, y, w, hgt) in ((2.06, -8.4, 0.5, 1.3), (2.06, -6.3, 0.35, 0.9), (-2.06, -7.4, 0.6, 1.5), (-2.06, -9.3, 0.3, 0.8)):
        sd.bx(x - 0.012, x + 0.012, y - w / 2, y + w / 2, 5.45 - hgt, 5.45, "Rust")
    for (x, w, hgt) in ((-0.9, 0.5, 0.7), (1.3, 0.3, 1.0)):
        sd.bx(x - w / 2, x + w / 2, -4.912, -4.888, 5.6, 5.6 + hgt, "Rust")
    # funnel (raked) with mustard band
    f0 = Vector((0.0, -9.05, 5.5))
    rake = Vector((0.0, -0.18, 1.0)).normalized()
    sd.tube(f0, f0 + rake * 1.5, 0.58, "Navy", seg=10, r2=0.54)
    sd.tube(f0 + rake * 1.5, f0 + rake * 2.0, 0.54, "Mustard", seg=10, r2=0.52)
    sd.tube(f0 + rake * 2.0, f0 + rake * 2.5, 0.52, "Charcoal", seg=10, r2=0.50)
    sd.tube(f0 + rake * 2.35, f0 + rake * 2.75, 0.30, "Rust", seg=8, r2=0.30)
    # radar mast on the wheelhouse roof
    sd.tube((0, -6.8, 7.87), (0, -6.9, 10.1), 0.07, "Rust", seg=6, r2=0.05)
    sd.beam((-0.7, -6.87, 9.4), (0.7, -6.87, 9.4), 0.07, "SteelDark")
    sd.box((0.9, 0.16, 0.12), (0.0, -6.5, 8.35), "SteelDark", rot=(0, 0, 0.5))
    sd.tube((0, -6.5, 7.87), (0, -6.5, 8.3), 0.05, "SteelDark", seg=5)
    sd.box((0.14, 0.14, 0.18), (0.0, -6.9, 10.15), "Brick")
    # boat-deck railing (some sections missing / bent)
    posts = [(-2.3, y) for y in (-10.1, -9.0, -7.9, -6.8, -5.7, -4.4)] + [(2.3, y) for y in (-10.1, -9.0, -7.9)] + \
            [(x, -10.15) for x in (-1.15, 0.0, 1.15)]
    for (x, y) in posts:
        sd.beam((x, y, 5.57), (x, y, 6.5), 0.05, "Rust")
    sd.beam((-2.3, -10.1, 6.5), (-2.3, -4.4, 6.5), 0.05, "Rust")
    sd.beam((-2.3, -10.1, 6.05), (-2.3, -5.7, 6.05), 0.04, "Rust")
    sd.beam((2.3, -10.1, 6.5), (2.3, -7.9, 6.5), 0.05, "Rust")
    sd.beam((2.3, -7.9, 6.5), (2.75, -6.3, 5.9), 0.05, "Rust")                 # bent, hanging outboard
    sd.beam((-2.3, -10.15, 6.5), (2.3, -10.15, 6.5), 0.05, "Rust")
    # stern trawl gantry (A-frame) + net drum + bollards
    for s in (-1, 1):
        sd.beam((s * 1.9, -10.75, 3.3), (s * 0.9, -10.95, 6.9), 0.2, "Rust", h=0.2)
        sd.cyl(0.11, 0.42, (s * 1.55, -10.3, 3.5), "SteelDark", seg=6)
        sd.cyl(0.16, 0.07, (s * 1.55, -10.3, 3.72), "SteelDark", seg=6)
    sd.beam((-1.15, -10.93, 6.75), (1.15, -10.93, 6.75), 0.22, "Rust", h=0.26)
    sd.beam((0.0, -10.93, 6.75), (0.0, -10.2, 5.6), 0.07, "WoodDark")
    sd.cyl(0.38, 1.5, (0.0, -10.25, 3.72), "SteelDark", axis='X', seg=8)
    sd.cyl(0.5, 0.08, (0.72, -10.25, 3.72), "Rust", axis='X', seg=8, sym=True)
    # engine room: bulkhead with doorway + engine block (visible through the break)
    yb = -2.5
    Bk = 2.80 * 0.96
    for s in (-1, 1):
        prof = [(s * 0.5, 0.1), (s * 0.45 * Bk, 0.15), (s * 0.80 * Bk, 0.55), (s * 0.97 * Bk, 1.3), (s * Bk, 2.95), (s * 0.5, 2.95)]
        sd.loft([[(x, yb, z) for (x, z) in prof], [(x, yb + 0.08, z) for (x, z) in prof]], "Rust")
    sd.bx(-0.5, 0.5, yb, yb + 0.08, 2.1, 2.95, "Rust")
    sd.bx(-0.55, 0.55, -6.4, -3.6, 0.15, 1.25, "SteelDark")
    for y in (-6.0, -5.3, -4.6, -3.9):
        sd.bx(-0.32, 0.32, y - 0.22, y + 0.22, 1.25, 1.55, "Rust")
    sd.tube((0.3, -4.2, 1.5), (0.9, -4.2, 2.9), 0.1, "WoodDark", seg=6)
    # mid-deck skylight + vent cowls
    sd.bx(-0.7, 0.7, -3.9, -2.9, 3.0, 3.45, "SteelDark")
    sd.bx(-0.6, 0.6, -3.8, -3.0, 3.45, 3.5, "WindowDark")
    for s in (-1, 1):
        sd.tube((s * 1.9, -3.9, 3.0), (s * 1.9, -3.9, 4.1), 0.16, "Cream", seg=6)
        sd.tube((s * 1.9, -3.9, 4.1), (s * 1.9, -3.5, 4.3), 0.2, "Cream", seg=6, r2=0.26)
    _ship_break_frames(sd, ST_S[-1], +1, rnd)
    for (x, y, z, r) in ((2.8, -6.2, 3.85, 0.5), (-2.8, -3.3, 3.8, 0.45), (-2.0, -9.7, 5.62, 0.5), (1.2, -5.2, 7.9, 0.45),
                         (2.75, -1.2, 2.2, 0.55), (0.0, -8.9, 5.6, 0.4)):
        _algae(sd, (x, y, z), r, rnd)

    stern = join([hull.obj(solidify=0.10, solid_mat_offset=99), deck.obj(solidify=0.07, solid_mat_offset=99),
                  hs.obj(bevel=0.07), sd.obj()], "Hull_Stern")
    G.set_origin(stern, (0.0, -5.5, 0.0))
    stern.location = (-0.35, -5.3, -0.45)
    stern.rotation_euler = Euler((math.radians(4.0), math.radians(-13.0), math.radians(-6.0)), 'XYZ')

    # =============================== BOW HALF (ship space) ===============================
    hull, rings = _ship_hull("~b_hull", ST_B, 0, {(1, 1), (3, 2), (2, 7), (5, 8), (4, 1)}, rnd)
    hull.poly(list(rings[-1]), "SteelDark")                    # stem cap
    hull.m("WoodDark")
    deck = Part("~b_deck")
    _ship_deck(deck, ST_B[:6], rnd, hatch=(2.0, 6.5), torn_first=True)
    # forecastle deck (raised) + its aft bulkhead
    fo = [(y, B, d + 0.80) for (y, B, k, d) in ST_B[5:]]
    for a, b in zip(fo[:-1], fo[1:]):
        deck.poly([(-a[1] * 0.98, a[0], a[2]), (a[1] * 0.98, a[0], a[2]), (b[1] * 0.98, b[0], b[2]), (-b[1] * 0.98, b[0], b[2])], "Trunk")
    deck.m("WoodDark")

    bd = Part("~b_detail")
    yf = ST_B[5][0]
    bd.bx(-1.95, -0.45, yf - 0.05, yf + 0.05, 3.3, 4.2, "Cream")
    bd.bx(0.45, 1.95, yf - 0.05, yf + 0.05, 3.3, 4.2, "Cream")
    bd.bx(-0.45, 0.45, yf - 0.05, yf + 0.05, 3.95, 4.2, "Rust")
    # cargo hatch coaming
    hx = 1.40
    for s in (-1, 1):
        bd.bx(s * hx - 0.07, s * hx + 0.07, 2.0, 6.5, 2.9, 3.62, "SteelDark")
    bd.bx(-hx, hx, 1.93, 2.07, 2.9, 3.62, "Rust")
    bd.bx(-hx, hx, 6.43, 6.57, 2.9, 3.62, "SteelDark")
    # hatch covers: one in place, one slid off and leaning
    bd.box((2.95, 1.45, 0.12), (0.0, 5.75, 3.68), "WoodDark")
    bd.box((2.95, 1.45, 0.12), (1.25, 4.1, 3.55), "Trunk", rot=(0.0, math.radians(24), math.radians(9)))
    # cargo crates in the hold (slid to the low side)
    for (x, y, s, rz) in ((1.5, 3.0, 1.0, 0.2), (1.65, 4.3, 0.85, 0.5), (0.5, 3.6, 0.9, -0.3), (1.2, 5.4, 1.1, 0.1)):
        bd.box((s, s, s), (x, y, 0.45 + s / 2), "Wood", rot=(0, 0, rz))
        bd.box((s + 0.04, 0.12, s + 0.04), (x, y, 0.45 + s / 2), "WoodDark", rot=(0, 0, rz))
    # foremast with crosstree, crow's nest, fallen derrick boom, stays
    mf = Vector((0.0, 7.45, 3.2))
    mt = Vector((0.0, 7.2, 10.6))
    bd.tube(mf, mt, 0.19, "Rust", seg=8, r2=0.10)
    bd.cyl(0.3, 0.3, (0, 7.45, 3.5), "SteelDark", seg=8)
    bd.beam((-1.25, 7.27, 8.7), (1.25, 7.27, 8.7), 0.1, "WoodDark")
    bd.ring(0.5, 0.42, 7.25, 7.8, (0.0, 7.33), "Cream", seg=8)
    bd.cyl(0.5, 0.05, (0.0, 7.33, 7.25), "Rust", seg=8)
    bd.tube(mt, mt + Vector((0.5, -0.9, -1.5)), 0.07, "WoodDark", seg=5, r2=0.04)       # snapped topmast
    bd.tube((0.0, 7.3, 4.3), (-1.75, 2.6, 3.7), 0.11, "Rust", seg=6, r2=0.08)           # derrick boom fallen on the coaming
    bd.cyl(0.15, 0.2, (0, 7.3, 4.3), "SteelDark", seg=6)
    bd.tube((1.2, 7.27, 8.7), (2.35, 6.6, 4.0), 0.022, "WoodDark", seg=3, cap=False)
    bd.tube((-1.2, 7.27, 8.7), (-2.35, 6.6, 4.0), 0.022, "WoodDark", seg=3, cap=False)
    bd.tube((0.0, 7.22, 10.0), (0.0, 10.7, 4.75), 0.022, "WoodDark", seg=3, cap=False)
    # windlass + bollards on the forecastle, anchors in the hawse
    bd.bx(-0.7, 0.7, 8.9, 9.6, 4.25, 4.5, "SteelDark")
    bd.cyl(0.3, 1.5, (0.0, 9.25, 4.75), "Rust", axis='X', seg=8)
    bd.cyl(0.42, 0.08, (0.55, 9.25, 4.75), "SteelDark", axis='X', seg=8, sym=True)
    for s in (-1, 1):
        bd.cyl(0.1, 0.4, (s * 1.05, 8.5, 4.42), "SteelDark", seg=6)
        bd.cyl(0.15, 0.06, (s * 1.05, 8.5, 4.62), "SteelDark", seg=6)
        # anchor hanging at the bow flank
        ax, ay, az = s * 1.12, 9.75, 3.15
        bd.cyl(0.14, 0.1, (s * 1.02, ay, az + 0.75), "Charcoal", axis='X', seg=6)
        bd.beam((ax, ay, az + 0.7), (ax + s * 0.05, ay, az - 0.35), 0.1, "Charcoal")
        bd.beam((ax + s * 0.05, ay - 0.42, az - 0.1), (ax + s * 0.05, ay, az - 0.4), 0.09, "Charcoal")
        bd.beam((ax + s * 0.05, ay + 0.42, az - 0.1), (ax + s * 0.05, ay, az - 0.4), 0.09, "Charcoal")
    bd.path([(0.3, 9.6, 4.6), (0.6, 10.2, 4.75), (1.0, 10.1, 4.9)], 0.045, "Charcoal", seg=4)
    # bulwark rail remnants + forecastle rail
    for (x, y, z) in ((1.75, 8.6, 5.15), (1.15, 9.6, 5.3), (0.55, 10.4, 5.5), (-1.75, 8.6, 5.15), (-1.15, 9.6, 5.3)):
        bd.beam((x, y, z - 0.75), (x, y, z), 0.045, "Rust")
    bd.beam((1.75, 8.6, 5.15), (1.15, 9.6, 5.3), 0.045, "Rust")
    bd.beam((1.15, 9.6, 5.3), (0.55, 10.4, 5.5), 0.045, "Rust")
    bd.beam((-1.75, 8.6, 5.15), (-1.15, 9.6, 5.3), 0.045, "Rust")
    _ship_break_frames(bd, ST_B[0], -1, rnd)
    for (x, y, z, r) in ((-2.75, 3.2, 3.8, 0.5), (-2.5, 6.0, 4.0, 0.45), (0.0, 5.8, 3.78, 0.4), (-1.0, 9.0, 4.3, 0.4),
                         (-2.72, 4.6, 2.0, 0.5), (0.3, 7.3, 7.85, 0.3)):
        _algae(bd, (x, y, z), r, rnd)

    bow = join([hull.obj(solidify=0.10, solid_mat_offset=99), deck.obj(solidify=0.07, solid_mat_offset=99),
                bd.obj()], "Hull_Bow")
    G.set_origin(bow, (0.0, 6.0, 0.0))
    bow.location = (0.2, 7.3, -0.35)
    bow.rotation_euler = Euler((math.radians(5.0), math.radians(23.0), math.radians(13.0)), 'XYZ')

    # =============================== seabed debris + growth (root space) ===============================
    db = Part("Debris")
    db.box((2.95, 1.45, 0.12), (-3.6, 2.3, 0.12), "WoodDark", rot=(math.radians(6), math.radians(-5), 0.7))     # third hatch cover
    db.box((1.6, 1.1, 0.06), (2.6, 0.2, 0.08), "Rust", rot=(math.radians(-9), math.radians(4), -0.4))
    db.box((1.1, 0.8, 0.06), (-1.9, 0.6, 0.25), "SteelDark", rot=(math.radians(24), math.radians(10), 1.1))
    db.box((0.9, 1.4, 0.06), (4.6, 3.4, 0.07), "Brick", rot=(math.radians(5), math.radians(-7), 0.2))
    db.tube((-2.6, -1.2, 0.12), (-4.7, 0.6, 0.3), 0.11, "Rust", seg=6)
    db.tube((3.2, -2.4, 0.1), (5.1, -1.5, 0.1), 0.08, "WoodDark", seg=6)
    for (x, y, rz, mm) in ((1.9, 1.7, 0.3, "Teal"), (2.5, 2.2, 1.9, "Rust"), (-3.3, -0.4, 0.9, "Mustard")):
        db.cyl(0.3, 0.88, (x, y, 0.27), mm, axis='X', seg=8, rot=(0, 0, rz))
        db.cyl(0.315, 0.06, (x, y, 0.27), "WoodDark", axis='X', seg=8, rot=(0, 0, rz))
    db.cyl(0.3, 0.88, (-2.2, 2.9, 0.42), "Rust", seg=8)
    db.cyl(0.315, 0.06, (-2.2, 2.9, 0.5), "WoodDark", seg=8)
    # a few half-buried rocks to tie the wreck into the seabed
    for (x, y, r) in ((4.3, -4.6, 0.8), (-4.4, -7.5, 0.7), (-3.9, 6.1, 0.9), (5.0, 8.6, 0.6), (-1.0, 12.6, 0.55)):
        db.sphere(r, (x, y, r * 0.15), "RockDark", seg=6, rings=4, scale=(1.0, rnd.uniform(0.7, 1.2), 0.6), rot=(0, 0, rnd.uniform(0, 3)))
    db.obj("Debris")

    gr = Part("Seaweed")
    for (x, y, hgt) in ((3.9, -4.2, 2.4), (4.4, -5.1, 1.7), (-4.1, -7.0, 2.6), (-4.6, -7.9, 1.6), (-3.6, 5.6, 2.2),
                        (-4.3, 6.6, 2.9), (4.7, 8.2, 2.0), (-0.7, 12.3, 1.8), (2.2, -11.9, 2.3), (-2.9, -11.2, 1.5),
                        (-2.8, 1.6, 1.4), (3.4, 1.2, 1.9)):
        _kelp(gr, (x, y, 0.0), hgt, rnd)
    gr.obj("Seaweed")

    # treasure chest (separate so the game can hide it once collected)
    tc = Part("Treasure_Chest")
    tc.bx(-0.36, 0.36, -0.24, 0.24, 0.0, 0.34, "WoodDark")
    tc.bx(-0.38, 0.38, -0.26, 0.26, 0.10, 0.16, "Brass")
    for x in (-0.25, 0.25):
        tc.bx(x - 0.04, x + 0.04, -0.255, 0.255, 0.0, 0.345, "Brass")
    tc.bx(-0.32, 0.32, -0.20, 0.20, 0.30, 0.37, "NeonYellow")                            # gold glow
    lid = tc.prism([(-0.24, 0.0), (0.24, 0.0), (0.24, 0.08), (0.14, 0.17), (-0.14, 0.17), (-0.24, 0.08)], -0.36, 0.36, "WoodDark", axis='X')
    lid += tc.bx(-0.25 - 0.04, -0.25 + 0.04, -0.25, 0.25, 0.0, 0.10, "Brass") + tc.bx(0.25 - 0.04, 0.25 + 0.04, -0.25, 0.25, 0.0, 0.10, "Brass")
    tc.move(lid, offset=(0.0, 0.0, 0.34), rot=(math.radians(55), 0, 0), pivot=(0.0, -0.24, 0.0))
    tc.obj("Treasure_Chest", loc=(0.55, 1.15, 0.0), rot=(0.0, math.radians(-4), math.radians(28)))
    marker("Treasure", (0.55, 1.15, 0.35))


# ================================================================================================
# HARBOUR
# ================================================================================================
CONT_L, CONT_W, CONT_H = 6.06, 2.44, 2.59
CONT_COLOURS = {   # dark tone (panels / frame), light tone (corrugation ribs)
    "a": ("Terracotta", "Coral"), "b": ("Teal", "Mint"), "c": ("Mustard", "CarYellow"),
    "open": ("Navy", "CarBlue"), "d": ("GrassDark", "Leaf"), "e": ("Rust", "SafetyOrange"), "f": ("SteelDark", "Steel"),
}


def _container(p, tones, origin=(0, 0, 0), yaw=0.0, ribs=11, open_doors=False, detail=True):
    """ISO 20 ft container, doors at +Y. Geometry is appended to Part p, then moved to origin / yaw."""
    start = p.count()
    A, B = tones
    L, W, H = CONT_L, CONT_W, CONT_H
    hw, hl = W / 2, L / 2
    if open_doors:
        t = 0.05
        p.bx(-hw + 0.03, hw - 0.03, -hl + 0.03, hl - 0.03, 0.0, 0.17, "Wood")                 # plywood floor
        p.bx(-hw + 0.03, hw - 0.03, -hl + 0.03, hl - 0.03, H - 0.03 - t, H - 0.03, A)         # roof
        p.bx(hw - 0.03 - t, hw - 0.03, -hl + 0.03, hl - 0.03, 0.17, H - 0.03 - t, A, sym=True)
        p.bx(-hw + 0.03, hw - 0.03, -hl + 0.03, -hl + 0.03 + t, 0.17, H - 0.03 - t, A)        # back wall
    else:
        p.bx(-hw + 0.03, hw - 0.03, -hl + 0.03, hl - 0.03, 0.02, H - 0.03, A)
    # corrugation ribs: sides, back, roof
    step = (L - 0.5) / ribs
    for i in range(ribs):
        y = -hl + 0.25 + step * (i + 0.5)
        p.bx(hw - 0.032, hw, y - step * 0.27, y + step * 0.27, 0.22, H - 0.18, B, sym=True)
    nb = 5
    for i in range(nb):
        x = -hw + 0.2 + (W - 0.4) / nb * (i + 0.5)
        p.bx(x - 0.11, x + 0.11, -hl, -hl + 0.032, 0.22, H - 0.18, B)
    for i in range(3 if detail else 0):
        y = -hl + L * (i + 0.5) / 3
        p.bx(-hw + 0.16, hw - 0.16, y - 0.45, y + 0.45, H - 0.032, H, B)
    # frame: rails, posts
    p.bx(hw - 0.11, hw, -hl, hl, 0.0, 0.18, A, sym=True)
    p.bx(hw - 0.11, hw, -hl, hl, H - 0.14, H, A, sym=True)
    for sy in (-1, 1):
        p.bx(hw - 0.13, hw, sy * hl - sy * 0.13, sy * hl, 0.0, H, A, sym=True)
        p.bx(-hw, hw, sy * hl - sy * 0.11, sy * hl, 0.0, 0.18, A)
        p.bx(-hw, hw, sy * hl - sy * 0.11, sy * hl, H - 0.14, H, A)
        if detail:
            for z in (0.0, H - 0.13):
                p.bx(hw - 0.17, hw + 0.012, sy * hl - sy * 0.19, sy * hl + sy * 0.012, z - 0.005, z + 0.135, "SteelDark", sym=True)
    # doors
    dw = hw - 0.13
    for s in (1, -1):
        d0 = p.count()
        # door leaf built with the hinge at local origin, extending toward -s*X, outer face at +Y
        p.bx(0.0, -s * dw, -0.05, 0.0, 0.18, H - 0.14, B)
        for fx in (0.28, 0.78):
            p.bx(-s * (dw * fx - 0.025), -s * (dw * fx + 0.025), 0.0, 0.035, 0.10, H - 0.06, "Steel")
            if detail:
                p.bx(-s * (dw * fx - 0.16), -s * (dw * fx + 0.03), 0.035, 0.06, 1.05, 1.11, "SteelDark")
        if detail:
            for z in (0.5, H / 2, H - 0.5):
                p.bx(-s * 0.02, s * 0.05, -0.06, 0.03, z - 0.07, z + 0.07, "SteelDark")
        dv = p.new_verts(d0)
        ang = 0.0
        if open_doors:
            ang = math.radians(-262.0 if s == 1 else 104.0)
        hx = s * (hw + 0.03) if open_doors else s * (hw - 0.13)
        p.move(dv, offset=(hx, hl, 0.0), rot=(0, 0, ang))
    if open_doors:
        # steel loading ramp over the 18 cm door sill, so characters without step-up logic can walk in
        y0, y1 = hl - 0.01, hl + 0.82
        p.prism([(y0, 0.0), (y1, 0.0), (y1, 0.014), (y0 + 0.03, 0.181), (y0, 0.181)], -0.96, 0.96, "Steel", axis='X')
        p.beam((0.985, y0 + 0.03, 0.20), (0.985, y1, 0.035), 0.05, "HazardYellow", sym=True)
        zs = 0.014 + (0.181 - 0.014) * 0.12 / (y1 - y0 - 0.03)
        p.prism([(y1 - 0.12, 0.0), (y1 + 0.004, 0.0), (y1 + 0.004, 0.018), (y1 - 0.12, zs + 0.004)],
                -0.96, 0.96, "HazardYellow", axis='X')
    if detail and not open_doors:
        p.bx(hw, hw + 0.012, hl - 2.1, hl - 0.75, H - 1.05, H - 0.45, "CarWhite", sym=True)      # blank operator panel
        p.bx(hw, hw + 0.014, hl - 1.95, hl - 1.5, H - 0.93, H - 0.57, A, sym=True)
    p.move(p.new_verts(start), offset=origin, rot=(0, 0, yaw))


def _make_container(aid):
    key = aid.split("_")[1]
    p = Part("Container")
    _container(p, CONT_COLOURS[key], open_doors=(key == "open"))
    p.obj("Container")
    marker("Top", (0.0, 0.0, CONT_H))
    if key == "open":
        marker("Inside", (0.0, -1.5, 0.17))


@asset("container_a", slot=(4, -6.0, 0.0), family="harbour", collision="box", max_tris=1200)
def build_container_a(root):
    _make_container("container_a")


@asset("container_b", slot=(4, -2.0, 0.0), family="harbour", collision="box", max_tris=1200)
def build_container_b(root):
    _make_container("container_b")


@asset("container_c", slot=(4, 2.0, 0.0), family="harbour", collision="box", max_tris=1200)
def build_container_c(root):
    _make_container("container_c")


@asset("container_open", slot=(4, 6.5, 0.0), family="harbour", collision="trimesh", max_tris=1400,
       note="walk-in: doors open at the front (-Z), interior 2.28 x 5.9 x 2.34 m, floor 0.17 m above the ground, reached over a 0.8 m steel ramp plate (12 deg) at the doorway")
def build_container_open(root):
    _make_container("container_open")


@asset("cargo_stack", slot=(5, 0.0, 0.0), family="harbour", collision="trimesh", max_tris=2500,
       note="stepped 3-2-1 stack of six containers: climbable cover")
def build_cargo_stack(root):
    p = Part("Stack")
    H = CONT_H
    lay = [(-2.62, 0.0, 0, 0.0, "a"), (0.0, 0.0, 0, 0.0, "f"), (2.62, 0.12, 0, 0.0, "c"),
           (-2.62, 0.06, 1, 0.0, "b"), (0.04, -0.10, 1, 0.0, "e"),
           (-2.55, 0.0, 2, math.radians(3.0), "d")]
    for (x, y, lvl, yaw, key) in lay:
        _container(p, CONT_COLOURS[key], origin=(x, y, lvl * H), yaw=yaw, ribs=5, detail=False)
    p.obj("Stack")
    marker("Top_1", (2.62, 0.0, H))
    marker("Top_2", (0.0, 0.0, 2 * H))
    marker("Top_3", (-2.55, 0.0, 3 * H))


@asset("dock_crane", slot=(3, 0.0, 0.0), family="harbour", collision="trimesh", max_tris=2500,
       note="rail gantry crane; rails run along X (quay direction), the boom reaches forward (-Z) over the water; trucks pass under it along X (clear 4.4 m under the sill ties, 6.4 m wide)")
def build_dock_crane(root):
    OR = "Mustard"
    LX, LY = 5.0, 3.5
    p = Part("~frame")
    for sy in (1, -1):
        y = sy * LY
        p.bx(LX - 1.3, LX + 1.3, y - 0.38, y + 0.38, 0.30, 0.98, "Charcoal", sym=True)                  # bogie
        for dx in (-0.85, 0.0, 0.85):
            p.cyl(0.29, 0.5, (LX + dx, y, 0.29), "SteelDark", axis='Y', seg=8, sym=True)
        for ex in (LX + 1.3, LX - 1.42):
            p.bx(ex, ex + 0.12, y - 0.38, y, 0.36, 0.92, "HazardYellow", sym=True)
            p.bx(ex, ex + 0.12, y, y + 0.38, 0.36, 0.92, "Trim", sym=True)
        p.tbox((0.95, 0.95), (0.62, 0.62), 9.7, (LX, y, 0.98), OR, sym=True)                           # legs
        p.bx(-LX, LX, y - 0.3, y + 0.3, 1.05, 1.75, OR)                                                # sill beam
        p.bx(-LX - 0.31, LX + 0.31, y - 0.31, y + 0.31, 10.6, 11.4, OR)                                # top beam along the rail
        p.beam((LX, y, 8.3), (LX - 2.3, y, 10.75), 0.3, OR, sym=True)                                  # knee braces along the rail
        for (a, b) in ((-3.2, -2.2), (-1.0, 0.0), (1.2, 2.2)):
            p.bx(a, b, y - 0.31, y + 0.31, 1.3, 1.5, "Trim")                                           # hazard marks on the sill
    p.bx(LX - 0.3, LX + 0.3, -LY, LY, 10.62, 11.38, OR, sym=True)                                      # portal beams
    p.bx(LX - 0.22, LX + 0.22, -LY, LY, 5.4, 5.85, OR, sym=True)                                       # mid tie
    p.beam((LX, -LY, 5.85), (LX, LY, 10.62), 0.26, OR, sym=True)                                       # X bracing above truck height
    p.beam((LX, LY, 5.85), (LX, -LY, 10.62), 0.26, OR, sym=True)
    # main girders / boom + ties
    p.bx(1.05, 1.55, -8.6, 13.5, 11.4, 12.4, OR, sym=True)
    for y in (-8.45, -4.6, -1.2, 3.5, 7.0, 10.4, 13.35):
        p.bx(-1.55, 1.55, y - 0.15, y + 0.15, 12.4, 12.62, OR)
    p.bx(-1.6, 1.6, 13.5, 13.62, 11.5, 12.3, "HazardYellow")
    for x in (-1.2, -0.4, 0.4, 1.2):
        p.bx(x - 0.2, x + 0.2, 13.62, 13.63, 11.5, 12.3, "Trim" if int((x + 1.2) / 0.8 + 0.5) % 2 == 0 else "HazardYellow")
    # A-frame + stays
    apex = 18.0
    for (yb) in (-1.2, 3.5):
        p.beam((1.3, yb, 12.4), (0.55, 1.15, apex), 0.34, OR, sym=True)
    p.bx(-0.75, 0.75, 0.95, 1.35, apex - 0.2, apex + 0.2, OR)
    p.beam((0.55, 1.2, apex), (1.3, 12.6, 12.5), 0.14, "Charcoal", sym=True)
    p.beam((1.3, -8.3, 12.4), (1.3, -8.3, 15.75), 0.3, OR, sym=True)                                   # rear tie posts (clear the house)
    p.bx(-1.45, 1.45, -8.45, -8.15, 15.6, 15.9, OR)
    p.beam((1.3, -8.3, 15.6), (1.3, -7.3, 12.5), 0.16, OR, sym=True)
    p.beam((0.55, 1.1, apex), (1.3, -8.3, 15.75), 0.14, "Charcoal", sym=True)
    p.cyl(0.14, 0.22, (0.0, 1.15, apex + 0.31), "M_Taillight", seg=6)
    p.cyl(0.11, 0.18, (0.0, 13.3, 12.72), "M_Taillight", seg=6)
    # counterweight
    p.bx(-1.5, 1.5, -8.5, -6.9, 10.15, 11.4, "ConcreteDark")
    # trolley + hoist cables + spreader
    ty = 8.5
    p.bx(-1.75, 1.75, ty - 1.0, ty + 1.0, 11.02, 11.4, "Charcoal")
    p.bx(-0.9, 0.9, ty - 0.6, ty + 0.6, 10.7, 11.02, "SteelDark")
    for y in (ty - 0.8, ty + 0.8):
        p.cyl(0.16, 0.2, (1.3, y, 11.5), "SteelDark", axis='X', seg=6, sym=True)
    sz = 7.6
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.tube((sx * 0.8, ty + sy * 0.5, 10.7), (sx * 2.4, ty + sy * 1.0, sz + 0.3), 0.03, "Trim", seg=4, cap=False)
    p.bx(-3.03, 3.03, ty - 1.22, ty - 0.98, sz, sz + 0.3, "HazardYellow")
    p.bx(-3.03, 3.03, ty + 0.98, ty + 1.22, sz, sz + 0.3, "HazardYellow")
    for x in (-2.9, -1.0, 1.0, 2.9):
        p.bx(x - 0.13, x + 0.13, ty - 1.0, ty + 1.0, sz + 0.04, sz + 0.26, "HazardYellow")
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.bx(sx * 3.03 - 0.1, sx * 3.03 + 0.1, ty + sy * 1.1 - 0.12, ty + sy * 1.1 + 0.12, sz - 0.22, sz + 0.02, "Charcoal")
    # operator cab hanging beside the boom
    cx, cy0, cy1, cz0, cz1 = 2.55, 4.2, 6.1, 9.45, 11.3
    p.bx(1.55, cx + 0.75, cy0 + 0.4, cy0 + 0.7, 11.3, 11.6, OR)
    p.bx(1.55, cx + 0.75, cy1 - 0.7, cy1 - 0.4, 11.3, 11.6, OR)
    # boom walkway railing (left side) + ladder on a landside leg
    p.railing([(-2.2, y, 12.4) for y in (-2.2, 0.6, 3.4, 6.2, 9.0, 11.8, 13.4)], 1.0, "Charcoal", mid=False)
    p.bx(-2.25, -1.55, -2.2, 13.4, 12.34, 12.42, "SteelDark")
    p.ladder((-LX - 0.45, -LY, 1.75), (-LX - 0.42, -LY, 10.6), 0.5, "Charcoal", rungs=18, side_axis=(0, 1, 0))
    p.bx(-LX - 0.9, -LX - 0.3, -LY - 0.5, -LY + 0.5, 10.52, 10.6, "SteelDark")
    # floodlights under the boom
    for y in (2.0, 6.0, 11.5):
        p.bx(1.0, 1.4, y - 0.12, y + 0.12, 11.28, 11.4, "LampWarm", sym=True)
    frame = p.obj("~frame")

    hs = Part("~house")
    hs.bx(-2.15, 2.15, -7.1, -2.3, 12.62, 15.0, "Navy")
    hs.bx(-2.35, 2.35, -7.3, -2.1, 15.0, 15.16, "WarmGrey")
    hs.bx(cx - 0.7, cx + 0.7, cy0, cy1, cz0, cz1, "CarWhite")
    hs.bx(cx - 0.8, cx + 0.8, cy0 - 0.1, cy1 + 0.25, cz1, cz1 + 0.12, "Coral")
    house = hs.obj("~house", bevel=0.07)

    dt = Part("~detail")
    for y in (-6.2, -4.7, -3.2):
        dt.bx(2.15, 2.18, y - 0.45, y + 0.45, 13.7, 14.5, "Window", sym=True)
    dt.bx(-0.5, 0.5, -2.3, -2.27, 12.7, 14.6, "SteelDark")
    for z in (13.2, 13.5, 13.8):
        dt.bx(-1.6, -0.9, -7.13, -7.1, z, z + 0.14, "SteelDark")
        dt.bx(0.9, 1.6, -7.13, -7.1, z, z + 0.14, "SteelDark")
    dt.bx(cx - 0.62, cx + 0.62, cy1, cy1 + 0.03, cz0 + 0.55, cz1 - 0.2, "Window")                       # cab front glass
    dt.bx(cx - 0.62, cx + 0.62, cy1 - 0.02, cy1 + 0.03, cz0 + 0.08, cz0 + 0.5, "WindowDark")
    for s in (-1, 1):
        dt.bx(cx + s * 0.70, cx + s * 0.73, cy0 + 0.25, cy1 - 0.2, cz0 + 0.75, cz1 - 0.2, "Window")
    detail = dt.obj("~detail")
    join([frame, house, detail], "Crane")
    marker("Hook", (0.0, ty, sz - 0.22))
    marker("Cab", (cx, (cy0 + cy1) / 2, cz0 + 0.1))
    marker("Boom_Tip", (0.0, 13.5, 12.4))


@asset("buoy", slot=(8, -5.0, -6.0), family="harbour", collision="box", max_tris=900,
       note="origin at the WATERLINE (float body spans y -0.65..0.75, tail down to -1.9): place it at the wave height")
def build_buoy(root):
    p = Part("Buoy")
    R = 0.95
    p.cyl(R, 0.5, (0, 0, 0.1), "CarRed", seg=10)
    p.cyl(0.5, 0.5, (0, 0, -0.4), "CarRed", seg=10, r2=R)
    p.cyl(R, 0.4, (0, 0, 0.55), "CarRed", seg=10, r2=0.55)
    p.cyl(R + 0.02, 0.16, (0, 0, 0.1), "CarWhite", seg=10)
    p.cyl(0.24, 1.1, (0, 0, -1.15), "Charcoal", seg=8, r2=0.3)
    p.torus(0.14, 0.035, (0, 0, -1.74), "SteelDark", axis='X', seg=8, rseg=4)
    # lattice tower
    top = 2.55
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.tube((sx * 0.38, sy * 0.38, 0.72), (sx * 0.15, sy * 0.15, top), 0.035, "CarRed", seg=5)
    for z, k in ((1.3, 0.305), (1.95, 0.225)):
        for (a, b) in (((k, k), (k, -k)), ((k, -k), (-k, -k)), ((-k, -k), (-k, k)), ((-k, k), (k, k))):
            p.beam((a[0], a[1], z), (b[0], b[1], z), 0.035, "CarRed")
    p.cyl(0.3, 0.06, (0, 0, top), "CarRed", seg=8)
    # radar reflector (crossed plates) + solar panel + number board
    p.box((0.5, 0.02, 0.5), (0, 0, 1.62), "Steel", rot=(0, math.radians(45), 0))
    p.box((0.02, 0.5, 0.5), (0, 0, 1.62), "Steel", rot=(math.radians(45), 0, 0))
    p.box((0.42, 0.3, 0.03), (0.0, -0.36, 2.25), "Navy", rot=(math.radians(-50), 0, 0))
    p.box((0.5, 0.03, 0.34), (0.0, 0.33, 1.0), "CarWhite", rot=(math.radians(-8), 0, 0))
    # lantern
    p.cyl(0.13, 0.1, (0, 0, top + 0.08), "Charcoal", seg=8)
    p.cyl(0.11, 0.24, (0, 0, top + 0.25), "SirenRed", seg=8)
    p.cyl(0.15, 0.05, (0, 0, top + 0.395), "Charcoal", seg=8, r2=0.05)
    p.sphere(0.13, (0, 0, top + 0.62), "CarRed", seg=6, rings=4)
    p.tube((0, 0, top + 0.4), (0, 0, top + 0.55), 0.02, "Charcoal", seg=4)
    p.obj("Buoy")
    marker("Light", (0.0, 0.0, top + 0.25))


@asset("mooring_bollard", slot=(8, 5.0, -6.0), family="harbour", collision="box", max_tris=600)
def build_mooring_bollard(root):
    p = Part("Bollard")
    p.cyl(0.34, 0.06, (0, 0, 0.03), "SteelDark", seg=8)
    for i in range(4):
        a = math.radians(45 + 90 * i)
        p.cyl(0.04, 0.035, (0.26 * math.cos(a), 0.26 * math.sin(a), 0.075), "Steel", seg=6)
    p.cyl(0.2, 0.12, (0, 0, 0.12), "Charcoal", seg=10, r2=0.16)
    p.cyl(0.16, 0.3, (0, 0, 0.33), "Charcoal", seg=10, r2=0.14)
    p.cyl(0.14, 0.1, (0, 0, 0.53), "Charcoal", seg=10, r2=0.27)
    p.cyl(0.27, 0.07, (0, 0, 0.615), "Charcoal", seg=10)
    p.cyl(0.27, 0.07, (0, 0, 0.685), "HazardYellow", seg=10, r2=0.16)
    # mooring line looped around the stem, trailing off toward the water (+Y)
    p.torus(0.2, 0.04, (0, 0.02, 0.3), "Khaki", seg=10, rseg=5, rot=(math.radians(8), 0, 0))
    p.torus(0.2, 0.04, (0, 0.02, 0.38), "Khaki", seg=10, rseg=5, rot=(math.radians(-6), math.radians(5), 0))
    p.path([(0.0, 0.2, 0.34), (0.05, 0.6, 0.1), (0.0, 0.95, 0.045)], 0.04, "Khaki", seg=5)
    p.obj("Bollard", smooth=40)


@asset("boat_ramp", slot=(7, 0.0, 0.0), family="harbour", collision="trimesh", max_tris=900,
       note="origin = centre at SEA LEVEL; flat landing at +1.5 m at the back (z +5.5..+7), slopes down to -1.5 m at the front (z -7 = water end); solid body down to -2.6 m",
       top_height=1.5, slope_deg=13.5)
def build_boat_ramp(root):
    p = Part("Ramp")
    W = 3.0
    p.prism([(-7.0, 1.5), (-5.5, 1.5), (7.0, -1.5), (7.0, -2.6), (-7.0, -2.6)], -W, W, "Concrete", axis='X')
    slope = math.atan2(3.0, 12.5)

    def on(y, lift=0.0):
        t = (y + 5.5) / 12.5
        return 1.5 - 3.0 * t + lift
    # traction grooves
    for i in range(11):
        y = -4.6 + i * 1.08
        p.box((2 * W - 0.9, 0.14, 0.03), (0.0, y, on(y, 0.006)), "ConcreteDark", rot=(-slope, 0, 0))
    # kerbs with hazard blocks
    p.beam((W - 0.17, -5.5, 1.5 + 0.1), (W - 0.17, 7.0, -1.5 + 0.1), 0.34, "ConcreteDark", h=0.3, sym=True)
    p.bx(W - 0.34, W, -7.0, -5.5, 1.45, 1.75, "ConcreteDark", sym=True)
    for i in range(4):
        y = -5.2 + i * 1.5
        p.box((0.36, 0.7, 0.05), (W - 0.17, y, on(y, 0.27)), "HazardYellow", rot=(-slope, 0, 0), sym=True)
    # timber guide piles + rubber fenders
    for y in (2.4, 6.3):
        p.cyl(0.17, 4.3, (W + 0.22, y, -0.45), "WoodDark", seg=8, sym=True)
        p.cyl(0.18, 0.22, (W + 0.22, y, 1.72), "CarWhite", seg=8, sym=True)
        p.cyl(0.19, 0.5, (W + 0.22, y, on(y) + 0.75), "Trim", seg=8, sym=True)
    # winch post on the landing
    p.bx(-0.2, 0.2, -6.7, -6.3, 1.5, 2.15, "SteelDark")
    p.cyl(0.19, 0.5, (0.0, -6.5, 2.2), "Mustard", axis='X', seg=8)
    p.cyl(0.25, 0.04, (0.27, -6.5, 2.2), "SteelDark", axis='X', seg=8, sym=True)
    p.beam((0.31, -6.5, 2.2), (0.31, -6.25, 2.45), 0.04, "Trim")
    p.tube((0.0, -6.45, 2.36), (0.0, -1.5, on(-1.5, 0.05)), 0.015, "Trim", seg=4, cap=False)
    p.obj("Ramp")
    marker("Top", (0.0, -6.2, 1.5))
    marker("Water_End", (0.0, 7.0, -1.5))


@asset("lifebuoy_stand", slot=(8, -5.0, 6.0), family="harbour", collision="box", max_tris=900)
def build_lifebuoy_stand(root):
    p = Part("Stand")
    p.box((0.44, 0.34, 0.05), (0, 0, 0.025), "ConcreteDark")
    p.box((0.09, 0.09, 1.02), (0, 0, 0.56), "CarWhite")
    p.box((0.86, 0.07, 0.96), (0, 0, 1.52), "FireRed")
    p.box((0.74, 0.012, 0.84), (0, 0.04, 1.52), "CarWhite")
    p.prism([(-0.5, 2.0), (0.5, 2.0), (0.0, 2.2)], -0.1, 0.22, "FireRed", axis='Y')
    # ring buoy with white wraps
    p.torus(0.29, 0.068, (0, 0.115, 1.55), "SafetyOrange", axis='Y', seg=12, rseg=6)
    for i in range(4):
        a = math.radians(45 + 90 * i)
        c = (0.29 * math.cos(a), 0.115, 1.55 + 0.29 * math.sin(a))
        p.box((0.16, 0.16, 0.1), c, "CarWhite", rot=(0, -a, 0))
    p.box((0.05, 0.1, 0.05), (0, 0.09, 1.86), "SteelDark")
    # throw line coil
    p.torus(0.11, 0.03, (0.0, 0.09, 1.16), "Khaki", axis='Y', seg=8, rseg=4)
    p.torus(0.085, 0.03, (0.0, 0.11, 1.16), "Khaki", axis='Y', seg=8, rseg=4)
    p.obj("Stand")


def _boat_ring(st, bw):
    y, B, k, d = st
    h = d - k
    half = [(0.0, k), (0.5 * B, k + 0.10 * h), (0.9 * B, k + 0.48 * h), (B, d), (B * 1.02, d + bw)]
    ring = [(-x, z) for (x, z) in reversed(half[1:])] + half
    return [(x, y, z) for (x, z) in ring]


@asset("fishing_boat_static", slot=(6, 0.0, 0.0), family="harbour", collision="trimesh", max_tris=2500,
       note="origin at the WATERLINE; draft 0.6 m, deck 0.55 m above the water")
def build_fishing_boat_static(root):
    ST = [(-4.2, 1.12, -0.22, 0.64), (-3.0, 1.38, -0.50, 0.58), (-1.5, 1.52, -0.60, 0.55), (0.0, 1.52, -0.60, 0.55),
          (1.5, 1.42, -0.58, 0.60), (2.7, 1.12, -0.50, 0.72), (3.6, 0.64, -0.30, 0.90), (4.25, 0.05, 0.12, 1.08)]
    BW = 0.36
    hull = Part("~hull")
    rings = [_boat_ring(s, BW) for s in ST]
    row_mat = ["CarWhite", "CarBlue", "Brick", "Brick"]
    for i in range(len(rings) - 1):
        for j in range(8):
            row = min(j, 7 - j)
            hull.poly([rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j]], row_mat[row])
    hull.poly(list(rings[0]), "CarBlue")
    hull.poly(list(rings[-1]), "CarBlue")
    hull.m("Cream")
    hull_ob = hull.obj("~hull", solidify=0.045, solid_mat_offset=99)

    p = Part("~deck")
    for a, b in zip(ST[:-1], ST[1:]):
        p.slab([(-a[1] * 0.97, a[0], a[3]), (a[1] * 0.97, a[0], a[3]), (b[1] * 0.97, b[0], b[3]), (-b[1] * 0.97, b[0], b[3])], 0.05, "Wood")
    # rub rail cap on the bulwark
    for a, b in zip(ST[:-1], ST[1:]):
        p.beam((a[1] * 1.02, a[0], a[3] + BW), (b[1] * 1.02, b[0], b[3] + BW), 0.09, "Navy", h=0.05, sym=True)
    # wheelhouse
    y0, y1, wz = 0.5, 2.25, 0.58
    p.bx(-0.85, 0.85, y0, y1, wz, wz + 1.85, "Cream")
    p.bx(-1.02, 1.02, y0 - 0.25, y1 + 0.3, wz + 1.85, wz + 1.95, "Coral")
    for x in (-0.42, 0.42):
        p.bx(x - 0.32, x + 0.32, y1, y1 + 0.02, wz + 1.0, wz + 1.6, "WindowDark")
    for y in (0.95, 1.75):
        p.bx(0.85, 0.87, y - 0.3, y + 0.3, wz + 1.0, wz + 1.6, "WindowDark", sym=True)
    p.bx(-0.3, 0.3, y0 - 0.02, y0, wz + 0.05, wz + 1.6, "WoodDark")
    p.cyl(0.14, 0.16, (0.45, 1.9, wz + 2.03), "Steel", seg=6)
    p.box((0.1, 0.1, 0.12), (-0.5, 1.3, wz + 2.01), "M_Taillight")
    p.torus(0.2, 0.05, (0.88, 1.35, wz + 0.55), "SafetyOrange", axis='X', seg=8, rseg=4)
    # mast + boom + stays
    my = 0.25
    p.tube((0, my, 0.55), (0, my, 4.3), 0.07, "Wood", seg=6, r2=0.045)
    p.tube((0, my - 0.05, 1.6), (0, -3.3, 2.5), 0.05, "Wood", seg=5, r2=0.035)
    p.tube((0, my, 4.2), (0, -3.3, 2.5), 0.012, "Trim", seg=3, cap=False)
    p.tube((0, my, 4.25), (0.0, 4.0, 1.4), 0.012, "Trim", seg=3, cap=False)
    p.tube((0, my, 3.5), (1.5, my - 0.4, 0.92), 0.012, "Trim", seg=3, cap=False, sym=True)
    p.box((0.3, 0.02, 0.2), (0.0, my - 0.2, 4.15), "Coral")                                   # pennant
    # aft working deck: net drum, crates, net pile with floats, rope coil
    p.cyl(0.26, 1.2, (0.0, -3.3, 1.15), "SteelDark", axis='X', seg=8)
    p.cyl(0.4, 0.05, (0.6, -3.3, 1.15), "Mustard", axis='X', seg=8, sym=True)
    p.bx(0.56, 0.66, -3.4, -3.2, 0.6, 1.15, "SteelDark", sym=True)
    for (x, y, m) in ((-0.85, -1.2, "Mustard"), (-0.85, -0.55, "CarTeal"), (-0.8, -0.87, "Coral")):
        z = 0.56 if m != "Coral" else 0.84
        p.bx(x - 0.35, x + 0.35, y - 0.26, y + 0.26, z, z + 0.28, m)
        p.bx(x - 0.3, x + 0.3, y - 0.21, y + 0.21, z + 0.28, z + 0.285, "Trim")
    p.sphere(0.6, (0.6, -1.6, 0.68), "Teal", seg=7, rings=4, scale=(1.0, 1.25, 0.42))
    for (x, y, z) in ((0.35, -1.3, 0.92), (0.8, -1.75, 0.95), (0.55, -2.15, 0.84), (0.95, -1.2, 0.82)):
        p.sphere(0.1, (x, y, z), "SafetyOrange", seg=6, rings=4)
    p.torus(0.2, 0.05, (0.0, 3.0, 0.8), "Khaki", seg=8, rseg=4)
    p.torus(0.14, 0.05, (0.0, 3.0, 0.87), "Khaki", seg=8, rseg=4)
    # bow post, cleats, name boards, tyre fenders
    p.bx(-0.07, 0.07, 3.95, 4.12, 1.0, 1.75, "Wood")
    for (x, y, z) in ((0.75, -3.8, 0.66), (0.5, 3.3, 0.9)):
        p.bx(x - 0.05, x + 0.05, y - 0.16, y + 0.16, z, z + 0.1, "SteelDark", sym=True)
    p.box((0.03, 1.0, 0.15), (1.2, 2.3, 0.5), "Mustard", rot=(0, math.radians(-5), math.radians(16)), sym=True)
    for y in (-2.4, -0.4, 1.4):
        Bx = 1.52 if y < 1.0 else 1.44
        p.cyl(0.27, 0.13, (Bx + 0.1, y, 0.42), "Tire", axis='X', seg=8, sym=True)
        p.cyl(0.13, 0.14, (Bx + 0.1, y, 0.42), "Charcoal", axis='X', seg=8, sym=True)
        p.tube((Bx + 0.1, y, 0.66), (Bx + 0.04, y, 0.95), 0.015, "Khaki", seg=3, cap=False, sym=True)
    deck_ob = p.obj("~deck")
    join([hull_ob, deck_ob], "Boat")
    marker("Deck", (0.0, -2.2, 0.56))
    marker("Mooring_Bow", (0.0, 4.0, 1.0))
    marker("Mooring_Stern", (0.0, -4.1, 0.9))


# ================================================================================================
# BEACH + PARK
# ================================================================================================
def _canopy(p, apex, R, drop, mats, n=8, valance=0.14, thick=0.035, phase=0.0):
    """Closed thin umbrella canopy with alternating coloured gores and a valance."""
    ax, ay, az = apex

    def ring(r, z):
        return [(ax + r * math.cos(math.radians(phase) + 2 * math.pi * i / n),
                 ay + r * math.sin(math.radians(phase) + 2 * math.pi * i / n), z) for i in range(n)]
    rim = ring(R, az - drop)
    val = ring(R * 1.01, az - drop - valance)
    val_in = ring(R * 0.985, az - drop - valance)
    rim_in = ring(R * 0.97, az - drop - thick)
    top_c = (ax, ay, az)
    bot_c = (ax, ay, az - thick * 1.6)
    out = []
    for i in range(n):
        j = (i + 1) % n
        m = mats[i % len(mats)]
        out += p.poly([top_c, rim[i], rim[j]], m)
        out += p.poly([rim[i], val[i], val[j], rim[j]], m)
        out += p.poly([val[i], val_in[i], val_in[j], val[j]], m)
        out += p.poly([val_in[i], rim_in[i], rim_in[j], val_in[j]], m)
        out += p.poly([rim_in[i], bot_c, rim_in[j]], m)
    return out, rim_in


@asset("beach_umbrella", slot=(9, -5.0, -6.0), family="park", category="beach", collision="none", max_tris=600,
       note="decorative; add a thin pole collider (r 0.04) if needed")
def build_beach_umbrella(root):
    p = Part("Umbrella")
    az = 2.32
    cv, rim_in = _canopy(p, (0, 0, az), 1.42, 0.5, ["Coral", "CarWhite"], n=8, phase=22.5)
    for q in rim_in:
        cv += p.beam((0, 0, az - 0.1), q, 0.022, "Steel")
    cv += p.cyl(0.024, 2.3, (0, 0, 1.15), "Wood", seg=6)
    cv += p.cyl(0.05, 0.08, (0, 0, az - 0.12), "Steel", seg=6)
    cv += p.sphere(0.055, (0, 0, az + 0.04), "CarWhite", seg=6, rings=4)
    cv += p.cyl(0.035, 0.12, (0, 0, 1.2), "Steel", seg=6)
    p.move(cv, rot=(math.radians(7), math.radians(-4), 0))
    p.cyl(0.2, 0.07, (0, 0, 0.035), "Sand", seg=8, r2=0.08)
    p.obj("Umbrella")
    marker("Shade", (0.0, 0.25, 0.0))


@asset("lounger", slot=(9, 5.0, -6.0), family="park", category="beach", collision="box", max_tris=500,
       note="head end at the back (+Z), feet toward the front (-Z)")
def build_lounger(root):
    p = Part("Lounger")
    a = math.radians(38)
    hx = 0.31
    yb, zb = -0.1 - 0.78 * math.cos(a), 0.33 + 0.78 * math.sin(a)
    p.beam((hx, -0.1, 0.33), (hx, 1.14, 0.33), 0.05, "CarWhite", sym=True)
    p.beam((hx, -0.1, 0.33), (hx, yb, zb), 0.05, "CarWhite", sym=True)
    for y in (0.02, 0.98):
        p.beam((hx, y, 0.0), (hx, y, 0.33), 0.05, "CarWhite", sym=True)
        p.beam((-hx, y, 0.12), (hx, y, 0.12), 0.035, "CarWhite")
    p.beam((hx, -0.62, 0.0), (hx, -0.5, 0.33 + 0.4 * math.tan(a) * 0.98), 0.04, "CarWhite", sym=True)
    p.beam((-hx, -0.62, 0.02), (hx, -0.62, 0.02), 0.035, "CarWhite")
    for i in range(7):
        y = 0.0 + i * 0.172
        p.box((0.6, 0.15, 0.03), (0, y, 0.365), "Teal" if i % 2 == 0 else "CarWhite")
    for i in range(5):
        t = 0.09 + i * 0.158
        y, z = -0.1 - t * math.cos(a), 0.33 + t * math.sin(a)
        p.box((0.6, 0.14, 0.03), (0, y - 0.02, z + 0.03), "Teal" if i % 2 == 1 else "CarWhite", rot=(-a, 0, 0))
    p.cyl(0.075, 0.5, (0, yb + 0.14, zb - 0.03), "CarYellow", axis='X', seg=8)
    p.obj("Lounger")
    marker("Lie", (0.0, 0.3, 0.38))


@asset("lifeguard_tower", slot=(10, -5.0, 0.0), family="park", category="beach", collision="trimesh", max_tris=2000,
       platform_height=2.5, note="walk-up ramp (32 deg) at the front (-Z), hollow hut with a door on the platform")
def build_lifeguard_tower(root):
    PH = 2.5
    W = "CarWhite"
    p = Part("Tower")
    # splayed legs + bracing
    for sy in (-1, 1):
        p.beam((1.75, sy * 1.75, 0.0), (1.42, sy * 1.42, PH - 0.1), 0.17, "Wood", sym=True)
        p.beam((1.72, sy * 1.72, 0.25), (-1.47, sy * 1.47, PH - 0.35), 0.08, "WoodDark")
        p.beam((-1.72, sy * 1.72, 0.25), (1.47, sy * 1.47, PH - 0.35), 0.08, "WoodDark")
    p.beam((1.72, -1.72, 0.25), (1.47, 1.47, PH - 0.35), 0.08, "WoodDark", sym=True)
    p.beam((1.72, 1.72, 0.25), (1.47, -1.47, PH - 0.35), 0.08, "WoodDark", sym=True)
    # platform deck + joists
    p.bx(-1.72, 1.72, -1.72, 1.72, PH - 0.1, PH, "Wood")
    for y in (-1.5, 0.0, 1.5):
        p.bx(-1.66, 1.66, y - 0.06, y + 0.06, PH - 0.26, PH - 0.1, "WoodDark")
    # hut walls (hollow): back, sides with windows, front with door + window
    z0, zs, zh, z1 = PH, PH + 0.95, PH + 1.75, PH + 2.0
    hx, yb, yf = 1.3, -1.6, 0.4
    p.bx(-hx, hx, yb, yb + 0.06, z0, z1, W)
    p.bx(hx - 0.06, hx, yb, yf, z0, zs, W, sym=True)
    p.bx(hx - 0.06, hx, yb, yf, zh, z1, W, sym=True)
    p.bx(hx - 0.06, hx, yb, yb + 0.3, zs, zh, W, sym=True)
    p.bx(hx - 0.06, hx, yf - 0.3, yf, zs, zh, W, sym=True)
    p.bx(-hx, 0.25, yf - 0.06, yf, z0, zs, W)
    p.bx(-hx, hx, yf - 0.06, yf, zh, z1, W)
    p.bx(-hx, -hx + 0.14, yf - 0.06, yf, zs, zh, W)
    p.bx(0.25, 0.37, yf - 0.06, yf, z0, zh, W)
    p.bx(hx - 0.12, hx, yf - 0.06, yf, z0, zh, W)
    # teal trim band + corner trims
    p.bx(hx, hx + 0.015, yb, yf, zs - 0.12, zs, "Teal", sym=True)
    p.bx(-hx, 0.25, yf, yf + 0.015, zs - 0.12, zs, "Teal")
    p.bx(-hx, hx, yb - 0.015, yb, zs - 0.12, zs, "Teal")
    # propped shutters over the side windows + front window
    sh = math.radians(62)
    for s in (1, -1):
        v = p.bx(0.0, 0.03, yb + 0.3, yf - 0.3, -0.78, 0.0, "Teal")
        p.move(v, offset=(s * (hx + 0.01), 0, zh), rot=(0, -s * sh, 0))
        p.beam((s * (hx + 0.02), yf - 0.4, zs), (s * (hx + 0.02 + 0.78 * math.sin(sh) * 0.9), yf - 0.4, zh - 0.78 * math.cos(sh) * 0.9), 0.03, "WoodDark")
    v = p.bx(-hx + 0.14, 0.25, 0.0, 0.03, -0.78, 0.0, "Teal")
    p.move(v, offset=(0, yf + 0.01, zh), rot=(sh, 0, 0))
    # interior: bench + desk
    p.bx(-1.2, -0.2, yb + 0.06, yb + 0.5, z0 + 0.4, z0 + 0.46, "Wood")
    p.bx(-1.2, -1.14, yb + 0.06, yb + 0.5, z0, z0 + 0.4, "WoodDark")
    p.bx(-0.26, -0.2, yb + 0.06, yb + 0.5, z0, z0 + 0.4, "WoodDark")
    # slanted roof with overhang + gable infill
    p.prism([(-1.95, z1), (1.15, z1 + 0.5), (1.15, z1 + 0.62), (-1.95, z1 + 0.12)], -1.62, 1.62, "Coral", axis='X')
    p.prism([(yb, z1), (yf, z1), (yf, z1 + 0.37), (yb, z1 + 0.05)], hx - 0.06, hx, W, axis='X', sym=True)
    p.prism([(-hx, z1), (hx, z1), (hx, z1 + 0.37), (-hx, z1 + 0.37)], yf - 0.06, yf, W, axis='Y')
    # tower number board (no text): navy plate with white disc
    p.bx(-0.85, -0.25, yf, yf + 0.03, zh + 0.02, z1 + 0.3, "Navy")
    p.cyl(0.17, 0.02, (-0.55, yf + 0.035, zh + 0.28), W, axis='Y', seg=8)
    # rescue can on the front wall
    p.sphere(0.13, (-0.9, yf + 0.14, z0 + 0.55), "SafetyOrange", seg=6, rings=5, scale=(1, 1, 2.6))
    p.tube((-0.9, yf + 0.02, z0 + 0.93), (-0.9, yf + 0.14, z0 + 0.86), 0.015, "Trim", seg=3)
    # porch railing (gap for the ramp at the front centre)
    rz = PH
    p.railing([(1.66, 0.4, rz), (1.66, 1.66, rz), (0.62, 1.66, rz)], 0.95, W)
    p.railing([(-1.66, 0.4, rz), (-1.66, 1.66, rz), (-0.62, 1.66, rz)], 0.95, W)
    p.railing([(1.66, -1.66, rz), (1.66, 0.4, rz)], 0.95, W)
    p.railing([(-1.66, -1.66, rz), (-1.66, 0.4, rz)], 0.95, W)
    # ramp with cleats and handrails
    r0 = Vector((0.0, 1.68, PH - 0.04))
    r1 = Vector((0.0, 5.65, -0.04))
    p.beam(r0, r1, 1.12, "Wood", h=0.08)
    d = r1 - r0
    sl = math.atan2(-d.z, d.y)
    for i in range(1, 10):
        c = r0 + d * (i / 10.0)
        p.box((1.12, 0.06, 0.035), (c.x, c.y, c.z + 0.055), "WoodDark", rot=(-sl, 0, 0))
    for s in (-1, 1):
        pts = [r0 + d * t + Vector((s * 0.58, 0, 0.04)) for t in (0.0, 0.33, 0.66, 0.98)]
        p.railing(pts, 0.9, W, mid=False)
        p.beam((s * 0.58, 5.4, 0.0), (s * 0.58, 4.3, 0.75), 0.06, "WoodDark")
    p.beam((0.0, 3.6, 0.0), (0.0, 3.6, 1.2), 0.12, "Wood")
    p.bx(-0.55, 0.55, 3.54, 3.66, 1.12, 1.24, "Wood")
    # flag pole with red / yellow flag
    p.tube((-1.55, -1.55, PH), (-1.55, -1.55, PH + 4.3), 0.035, W, seg=6)
    p.box((0.75, 0.02, 0.24), (-1.15, -1.55, PH + 4.1), "CarRed")
    p.box((0.75, 0.02, 0.24), (-1.15, -1.55, PH + 3.86), "CarYellow")
    p.obj("Tower")
    marker("Ramp_Bottom", (0.0, 6.0, 0.0))
    marker("Platform", (0.0, 1.05, PH))
    marker("Lookout", (0.4, -0.6, PH))


@asset("volleyball_net", slot=(11, 0.0, 0.0), family="park", category="beach", collision="none", max_tris=900,
       note="net spans X (9.5 m), top tape at 2.43 m; posts at x = +-5.0")
def build_volleyball_net(root):
    p = Part("Net")
    for s in (1,):
        p.cyl(0.05, 2.6, (5.0, 0, 1.3), "Steel", seg=8, sym=True)
        p.cyl(0.1, 1.7, (5.0, 0, 0.88), "CarBlue", seg=8, sym=True)
        p.cyl(0.06, 0.04, (5.0, 0, 2.62), "CarYellow", seg=8, sym=True)
    zt, zb = 2.43, 1.43
    p.box((9.5, 0.025, 0.07), (0, 0, zt - 0.035), "CarWhite")
    p.box((9.5, 0.02, 0.04), (0, 0, zb + 0.02), "CarWhite")
    p.box((0.05, 0.022, 1.0), (4.725, 0, (zt + zb) / 2), "CarWhite", sym=True)
    for i in range(1, 5):
        p.box((9.4, 0.008, 0.012), (0, 0, zb + i * 0.19), "WarmGrey")
    for i in range(-9, 10):
        p.box((0.012, 0.008, 0.93), (i * 0.47, 0, (zt + zb) / 2), "WarmGrey")
    # tension cables, antennas, guy lines
    p.tube((4.75, 0, zt - 0.03), (5.0, 0, zt + 0.1), 0.01, "Trim", seg=3, cap=False, sym=True)
    p.tube((4.75, 0, zb + 0.02), (5.0, 0, zb - 0.1), 0.01, "Trim", seg=3, cap=False, sym=True)
    for k in range(4):
        p.box((0.02, 0.03, 0.2), (4.5, 0.0, zt + 0.1 + k * 0.2), "CarRed" if k % 2 == 0 else "CarWhite", sym=True)
    for sy in (-1, 1):
        p.tube((5.0, 0, 2.55), (6.1, sy * 1.0, 0.02), 0.009, "Trim", seg=3, cap=False, sym=True)
        p.box((0.08, 0.08, 0.1), (6.1, sy * 1.0, 0.03), "Wood", sym=True)
    # a ball left in the sand
    p.sphere(0.107, (3.3, 1.5, 0.107), "CarYellow", seg=8, rings=6)
    p.cyl(0.109, 0.05, (3.3, 1.5, 0.107), "CarBlue", seg=8, rot=(0.6, 0.4, 0))
    p.obj("Net")
    marker("Court_A", (0.0, 4.5, 0.0))
    marker("Court_B", (0.0, -4.5, 0.0))


@asset("picnic_table", slot=(9, -5.0, 6.0), family="park", category="park", collision="box", max_tris=600,
       note="table runs along X, benches on the +Z and -Z sides")
def build_picnic_table(root):
    t = Part("~planks")
    for y in (-0.255, 0.0, 0.255):
        t.box((1.85, 0.24, 0.045), (0, y, 0.755), "Wood")
    for s in (-1, 1):
        for y in (0.66, 0.9):
            t.box((1.85, 0.22, 0.045), (0, s * y, 0.455), "Wood")
    planks = t.obj("~planks", bevel=0.012)
    f = Part("~frame")
    for x in (-0.66, 0.66):
        for s in (-1, 1):
            f.beam((x, s * 0.7, 0.0), (x, s * 0.2, 0.73), 0.09, "WoodDark", h=0.045, roll=math.pi / 2)
        f.beam((x, -1.0, 0.41), (x, 1.0, 0.41), 0.09, "WoodDark", h=0.045, roll=math.pi / 2)
        f.beam((x, -0.37, 0.71), (x, 0.37, 0.71), 0.09, "WoodDark", h=0.045, roll=math.pi / 2)
        f.beam((x, 0.0, 0.41), (x * 0.15, 0.0, 0.71), 0.07, "WoodDark", h=0.04)
    frame = f.obj("~frame")
    join([planks, frame], "Table")
    marker("Seat_1", (-0.45, 0.78, 0.48), yaw_deg=180.0)
    marker("Seat_2", (0.45, 0.78, 0.48), yaw_deg=180.0)
    marker("Seat_3", (-0.45, -0.78, 0.48))
    marker("Seat_4", (0.45, -0.78, 0.48))


@asset("fountain", slot=(12, 0.0, 0.0), family="park", category="park", collision="trimesh", max_tris=2500,
       note="child 'Water' (P_Sky) holds every water surface / stream so the game can swap in a water material or hide it")
def build_fountain(root):
    SEG = 16
    p = Part("~stone")
    p.cyl(3.4, 0.14, (0, 0, 0.07), "Sidewalk", seg=SEG)
    p.ring(3.0, 2.6, 0.14, 0.62, (0, 0), "Cream", seg=SEG)
    p.ring(3.1, 2.52, 0.62, 0.73, (0, 0), "WarmGrey", seg=SEG)
    p.cyl(2.6, 0.06, (0, 0, 0.17), "Teal", seg=SEG)
    for i in range(SEG):
        a = 2 * math.pi * (i + 0.5) / SEG
        rr = 3.0 * math.cos(math.pi / SEG) + 0.012
        p.box((0.72, 0.03, 0.22), (rr * math.cos(a), rr * math.sin(a), 0.38), "Teal" if i % 2 == 0 else "Coral",
              rot=(0, 0, a - math.pi / 2))
    # pedestal, two bowls, finial
    p.lathe([(0.62, 0.14), (0.62, 0.34), (0.46, 0.46), (0.36, 1.12), (0.5, 1.2)], (0, 0, 0), "Cream", seg=12, cap_start=False)
    p.lathe([(0.34, 1.16), (0.85, 1.26), (1.34, 1.5), (1.44, 1.72), (1.3, 1.72), (1.2, 1.58), (0.3, 1.44)], (0, 0, 0), "WarmGrey", seg=12, cap_start=False)
    p.lathe([(0.3, 1.44), (0.22, 1.6), (0.2, 2.16), (0.3, 2.24)], (0, 0, 0), "Cream", seg=10, cap_start=False)
    p.lathe([(0.22, 2.2), (0.5, 2.3), (0.78, 2.48), (0.84, 2.64), (0.74, 2.64), (0.66, 2.54), (0.15, 2.44)], (0, 0, 0), "WarmGrey", seg=12, cap_start=False)
    p.lathe([(0.15, 2.44), (0.1, 2.62), (0.1, 2.86)], (0, 0, 0), "Cream", seg=8, cap_start=False)
    p.sphere(0.24, (0, 0, 3.08), "Brass", seg=10, rings=6)
    p.cyl(0.16, 0.05, (0, 0, 2.86), "Brass", seg=8)
    # four brass spouts on the rim
    for i in range(4):
        a = math.radians(45 + 90 * i)
        c, s = math.cos(a), math.sin(a)
        p.tube((2.75 * c, 2.75 * s, 0.73), (2.6 * c, 2.6 * s, 1.02), 0.05, "Brass", seg=6)
        p.sphere(0.08, (2.58 * c, 2.58 * s, 1.05), "Brass", seg=6, rings=4)
    stone = p.obj("~stone", smooth=30)
    stone.name = _nm("Fountain")
    stone.data.name = _nm("Fountain")

    w = Part("Water")
    w.cyl(2.6, 0.02, (0, 0, 0.5), "Sky", seg=SEG)
    w.cyl(1.24, 0.02, (0, 0, 1.65), "Sky", seg=12)
    w.cyl(0.7, 0.02, (0, 0, 2.58), "Sky", seg=12)
    for i in range(8):
        a = 2 * math.pi * (i + 0.5) / 8
        c, s = math.cos(a), math.sin(a)
        w.beam((1.4 * c, 1.4 * s, 1.72), (1.62 * c, 1.62 * s, 1.5), 0.16, "Sky", h=0.03)
        w.beam((1.62 * c, 1.62 * s, 1.5), (1.78 * c, 1.78 * s, 0.5), 0.13, "Sky", h=0.03)
    for i in range(6):
        a = 2 * math.pi * i / 6
        c, s = math.cos(a), math.sin(a)
        w.beam((0.8 * c, 0.8 * s, 2.63), (0.95 * c, 0.95 * s, 2.46), 0.1, "Sky", h=0.025)
        w.beam((0.95 * c, 0.95 * s, 2.46), (1.02 * c, 1.02 * s, 1.65), 0.08, "Sky", h=0.025)
    for i in range(4):
        a = math.radians(45 + 90 * i)
        c, s = math.cos(a), math.sin(a)
        pts = [(2.55 * c, 2.55 * s, 1.08), (2.2 * c, 2.2 * s, 1.5), (1.85 * c, 1.85 * s, 1.52), (1.6 * c, 1.6 * s, 1.1), (1.5 * c, 1.5 * s, 0.5)]
        w.path(pts, 0.035, "Sky", seg=4, cap=False)
    w.obj("Water")
    marker("Jet_Top", (0.0, 0.0, 3.35))
    marker("Seat_1", (0.0, 3.25, 0.73))
    marker("Seat_2", (3.25, 0.0, 0.73), yaw_deg=-90.0)


@asset("playground_slide", slot=(10, 5.0, 0.0), family="park", category="park", collision="trimesh", max_tris=1200,
       note="ladder at the back (+Z), chute runs toward the front (-Z)")
def build_playground_slide(root):
    PH = 1.5
    p = Part("Slide")
    for sx in (1,):
        for sy in (-1, 1):
            p.bx(0.56, 0.66, sy * 0.61 - 0.05, sy * 0.61 + 0.05, 0.0, 2.65, "CarRed", sym=True)
    p.bx(-0.66, 0.66, -0.66, 0.66, PH - 0.08, PH, "CarBlue")
    p.tbox((1.7, 1.7), (0.16, 0.16), 0.6, (0, 0, 2.65), "Teal")
    p.sphere(0.09, (0, 0, 3.3), "CarYellow", seg=6, rings=4)
    # side guard panels with round ports
    p.bx(0.58, 0.62, -0.56, 0.56, PH + 0.12, PH + 0.85, "CarYellow", sym=True)
    p.cyl(0.2, 0.05, (0.6, 0, PH + 0.5), "CarBlue", axis='X', seg=8, sym=True)
    p.beam((0.61, -0.61, PH + 0.95), (0.61, 0.61, PH + 0.95), 0.05, "CarRed", sym=True)
    # ladder + grab rails
    p.ladder((0, -1.32, 0.0), (0, -0.68, PH), 0.62, "CarRed", rungs=6, bar=0.055)
    p.path([(0.31, -0.68, PH), (0.31, -0.74, PH + 0.9), (0.31, -0.61, PH + 0.95)], 0.025, "CarYellow", seg=5, sym=True)
    # chute
    path = [(0.62, PH + 0.0), (0.95, PH - 0.03), (3.35, 0.44), (4.15, 0.3), (4.75, 0.3)]
    secs = []
    for (y, zb) in path:
        zb -= 0.04
        secs.append([(-0.36, y, zb), (0.36, y, zb), (0.36, y, zb + 0.28), (0.31, y, zb + 0.28), (0.31, y, zb + 0.04),
                     (-0.31, y, zb + 0.04), (-0.31, y, zb + 0.28), (-0.36, y, zb + 0.28)])
    p.loft(secs, "CarYellow")
    p.bx(-0.36, 0.36, 0.66, 0.7, PH, PH + 0.26, "CarYellow")
    for (y, z) in ((2.2, 0.95), (4.3, 0.26)):
        p.bx(0.3, 0.38, y - 0.04, y + 0.04, 0.0, z, "CarRed", sym=True)
        p.bx(-0.38, 0.38, y - 0.04, y + 0.04, z - 0.08, z, "CarRed")
    # entry hoop over the chute
    p.path([(0.61, 0.61, PH + 0.95), (0.4, 0.66, PH + 1.25), (0.0, 0.66, PH + 1.34)], 0.03, "CarRed", seg=5, sym=True)
    p.obj("Slide")
    marker("Top", (0.0, 0.0, PH))
    marker("Exit", (0.0, 5.0, 0.0))


@asset("gazebo", slot=(13, 0.0, 0.0), family="park", category="park", collision="trimesh", max_tris=2500,
       note="octagonal, entrance (steps) at the front (-Z), floor 0.3 m high, clear height 2.4 m")
def build_gazebo(root):
    p = Part("Gazebo")
    FZ = 0.3
    R = 2.5
    W = "CarWhite"
    ang = [math.radians(22.5 + 45 * i) for i in range(8)]
    P = [(R * math.cos(a), R * math.sin(a)) for a in ang]
    p.lathe([(2.86, 0.0), (2.86, FZ - 0.04)], (0, 0, 0), "WoodDark", seg=8, phase=22.5)
    p.lathe([(2.92, FZ - 0.04), (2.92, FZ)], (0, 0, 0), "Wood", seg=8, phase=22.5)
    p.bx(-0.95, 0.95, 2.55, 2.98, 0.0, 0.2, "Concrete")
    p.bx(-0.95, 0.95, 2.55, 3.34, 0.0, 0.1, "Concrete")
    for i, (x, y) in enumerate(P):
        p.box((0.15, 0.15, 2.45), (x, y, FZ + 1.225), W, rot=(0, 0, ang[i]))
        p.box((0.24, 0.24, 0.12), (x, y, FZ + 0.06), W, rot=(0, 0, ang[i]))
    for i in range(8):
        a, b = Vector((P[i][0], P[i][1], 0)), Vector((P[(i + 1) % 8][0], P[(i + 1) % 8][1], 0))
        up = Vector((0, 0, 1))
        p.beam(a + up * (FZ + 2.38), b + up * (FZ + 2.38), 0.12, W, h=0.2, roll=0)
        p.beam(a * 1.01 + up * (FZ + 2.2), b * 1.01 + up * (FZ + 2.2), 0.05, "Teal", h=0.16)
        # corner brackets
        d = (b - a).normalized()
        p.beam(a + up * (FZ + 1.9), a + d * 0.42 + up * (FZ + 2.3), 0.05, W)
        p.beam(b + up * (FZ + 1.9), b - d * 0.42 + up * (FZ + 2.3), 0.05, W)
        if i == 1:          # the +Y side is the entrance
            continue
        p.beam(a + up * (FZ + 0.92), b + up * (FZ + 0.92), 0.07, W)
        p.beam(a + up * (FZ + 0.16), b + up * (FZ + 0.16), 0.05, W)
        for t in (0.2, 0.4, 0.6, 0.8):
            c = a.lerp(b, t)
            p.beam(c + up * (FZ + 0.16), c + up * (FZ + 0.92), 0.035, W)
    # benches along the three back sides
    for i in (4, 5, 6):
        a, b = Vector((P[i][0], P[i][1], 0)), Vector((P[(i + 1) % 8][0], P[(i + 1) % 8][1], 0))
        mid = (a + b) / 2
        n = -mid.normalized()
        d = (b - a).normalized()
        c = mid + n * 0.32
        yaw = math.atan2(d.y, d.x)
        p.box((1.55, 0.42, 0.06), (c.x, c.y, FZ + 0.45), "Wood", rot=(0, 0, yaw))
        for s in (-0.6, 0.6):
            q = c + d * s
            p.box((0.07, 0.36, 0.42), (q.x, q.y, FZ + 0.21), "WoodDark", rot=(0, 0, yaw))
    # roof: lower tier, lantern, upper tier, finial ; cream ceiling
    p.lathe([(3.25, FZ + 2.5), (3.25, FZ + 2.6), (0.62, FZ + 3.75)], (0, 0, 0), "Teal", seg=8, phase=22.5)
    p.lathe([(3.1, FZ + 2.47), (3.1, FZ + 2.5)], (0, 0, 0), "Cream", seg=8, phase=22.5)
    p.lathe([(0.55, FZ + 3.7), (0.55, FZ + 4.0)], (0, 0, 0), W, seg=8, phase=22.5, cap_start=False, cap_end=False)
    p.lathe([(0.95, FZ + 4.0), (0.95, FZ + 4.06), (0.08, FZ + 4.62)], (0, 0, 0), "Teal", seg=8, phase=22.5)
    p.cyl(0.035, 0.4, (0, 0, FZ + 4.78), "Brass", seg=6)
    p.sphere(0.12, (0, 0, FZ + 5.0), "Brass", seg=8, rings=5)
    # hip ridges
    for a in ang:
        p.beam((3.25 * math.cos(a), 3.25 * math.sin(a), FZ + 2.62), (0.62 * math.cos(a), 0.62 * math.sin(a), FZ + 3.77), 0.07, "Navy", h=0.05)
    p.obj("Gazebo")
    marker("Center", (0.0, 0.0, FZ))
    marker("Entrance", (0.0, 3.6, 0.0), yaw_deg=180.0)


@asset("viewpoint_binoculars", slot=(9, 5.0, 6.0), family="park", category="park", collision="box", max_tris=900,
       note="looks toward the front (-Z); the user stands behind it (marker 'Use')")
def build_viewpoint_binoculars(root):
    p = Part("~viewer")
    p.cyl(0.3, 0.05, (0, 0, 0.025), "SteelDark", seg=12)
    p.box((0.52, 0.3, 0.2), (0, -0.48, 0.1), "SteelDark")
    p.box((0.46, 0.24, 0.012), (0, -0.48, 0.206), "HazardYellow")
    p.lathe([(0.2, 0.05), (0.13, 0.16), (0.1, 0.3), (0.085, 1.16), (0.12, 1.2), (0.12, 1.24)], (0, 0, 0), "Teal", seg=12, cap_start=False)
    p.cyl(0.125, 0.03, (0, 0, 0.32), "Chrome", seg=12)
    p.box((0.42, 0.1, 0.045), (0, 0, 1.262), "SteelDark")
    p.box((0.04, 0.1, 0.24), (0.19, 0, 1.38), "SteelDark", sym=True)
    p.cyl(0.035, 0.03, (0.215, 0, 1.44), "Chrome", axis='X', seg=8, sym=True)
    # objective tubes + lenses, eyepieces
    p.cyl(0.082, 0.2, (0.085, 0.28, 1.45), "CarSilver", axis='Y', seg=10, sym=True)
    p.cyl(0.092, 0.035, (0.085, 0.385, 1.45), "Chrome", axis='Y', seg=10, sym=True)
    p.cyl(0.07, 0.01, (0.085, 0.404, 1.45), "Window", axis='Y', seg=10, sym=True)
    p.cyl(0.042, 0.1, (0.085, -0.25, 1.46), "Trim", axis='Y', seg=8, sym=True)
    p.cyl(0.052, 0.03, (0.085, -0.305, 1.46), "Trim", axis='Y', seg=8, sym=True)
    # coin box + slot + handles
    p.box((0.09, 0.14, 0.17), (0.0, -0.1, 1.32), "Mustard")
    p.box((0.012, 0.06, 0.012), (0.0, -0.172, 1.36), "Trim")
    p.tube((0.16, -0.16, 1.4), (0.26, -0.3, 1.36), 0.016, "Trim", seg=5, sym=True)
    body = p.obj("~viewer", smooth=40)
    h = Part("~head")
    h.box((0.34, 0.42, 0.21), (0, 0, 1.45), "CarSilver")
    head = h.obj("~head", bevel=0.045)
    join([body, head], "Viewer")
    marker("Use", (0.0, -0.75, 0.0))
    marker("Eye", (0.0, -0.32, 1.46))


@asset("park_statue", slot=(14, -5.0, 0.0), family="park", category="park", collision="box", max_tris=1500,
       note="original abstract sculpture 'Sun over the Bay': brass ring, teal wave ribbon, coral sun")
def build_park_statue(root):
    b = Part("~plinth")
    b.tbox((2.5, 2.5), (2.2, 2.2), 0.22, (0, 0, 0.0), "ConcreteDark")
    b.box((1.7, 1.7, 0.95), (0, 0, 0.695), "Concrete")
    plinth = b.obj("~plinth", bevel=0.05)
    p = Part("~art")
    p.box((0.7, 0.02, 0.3), (0, 0.86, 0.75), "Brass")
    cz = 2.78
    p.torus(1.45, 0.17, (0, 0, cz), "Brass", axis='Y', seg=16, rseg=6, rot=(0, 0, math.radians(14)))
    p.box((0.5, 0.5, 0.3), (0, 0, 1.27), "Brass")
    # wave ribbon through the ring
    secs = []
    n = 14
    for i in range(n + 1):
        t = i / n
        x = -2.1 + 4.2 * t
        z = cz - 0.25 + 0.62 * math.sin(t * math.pi * 2.0 - 0.6) + 0.5 * t * t
        yv = 0.28 * math.sin(t * math.pi * 1.5)
        w = 0.34 * (0.45 + math.sin(t * math.pi) * 0.75)
        th = 0.07
        secs.append([(x, yv - w, z - th), (x, yv + w, z - th), (x, yv + w, z + th), (x, yv - w, z + th)])
    p.loft(secs, "Teal")
    secs = []
    for i in range(n + 1):
        t = i / n
        x = -1.6 + 3.2 * t
        z = cz - 0.75 + 0.4 * math.sin(t * math.pi * 2.0 + 0.5) + 0.25 * t
        yv = -0.2 * math.sin(t * math.pi * 1.5)
        w = 0.2 * (0.4 + math.sin(t * math.pi) * 0.8)
        secs.append([(x, yv - w, z - 0.05), (x, yv + w, z - 0.05), (x, yv + w, z + 0.05), (x, yv - w, z + 0.05)])
    p.loft(secs, "CarWhite")
    p.sphere(0.46, (0.45, 0.0, cz + 0.55), "Coral", seg=10, rings=6)
    art = p.obj("~art", smooth=35)
    join([plinth, art], "Statue")


# ================================================================================================
# AIRPORT
# ================================================================================================
@asset("windsock", slot=(15, -5.0, -6.0), family="airport", collision="box", max_tris=700,
       note="child 'Sock' has its origin on the mast axis and points toward -Z (downwind) at rest: rotate it around Y with the wind")
def build_windsock(root):
    p = Part("Mast")
    H = 6.0
    p.box((0.7, 0.7, 0.1), (0, 0, 0.05), "ConcreteDark")
    p.cyl(0.12, 0.3, (0, 0, 0.25), "SteelDark", seg=8, r2=0.08)
    for i in range(6):
        z0 = 0.4 + i * (H - 0.4) / 6
        z1 = 0.4 + (i + 1) * (H - 0.4) / 6
        p.cyl(0.06 - i * 0.004, z1 - z0, (0, 0, (z0 + z1) / 2), "SafetyOrange" if i % 2 == 0 else "CarWhite", seg=8, r2=0.06 - (i + 1) * 0.004)
    p.cyl(0.05, 0.12, (0, 0, H + 0.06), "SteelDark", seg=8)
    p.cyl(0.05, 0.1, (0, 0, H + 0.32), "M_Taillight", seg=6)
    p.tube((0, 0, H + 0.12), (0, 0, H + 0.27), 0.015, "SteelDark", seg=4)
    p.obj("Mast")
    s = Part("Sock")
    # swivel frame: hoop + spokes
    s.torus(0.46, 0.02, (0, 0.34, 0.0), "SteelDark", axis='Y', seg=10, rseg=4)
    for a in (0, 90, 180, 270):
        c, sn = math.cos(math.radians(a)), math.sin(math.radians(a))
        s.tube((0, 0.0, 0.0), (0.46 * c, 0.34, 0.46 * sn), 0.014, "SteelDark", seg=4, cap=False)
    n = 5
    rad = [0.45, 0.40, 0.35, 0.30, 0.25, 0.20]
    ys = [0.34 + i * 0.5 for i in range(n + 1)]
    zs = [0.0, -0.02, -0.07, -0.16, -0.30, -0.48]
    for i in range(n):
        secs = []
        for k in (i, i + 1):
            secs.append([(rad[k] * math.cos(2 * math.pi * j / 10), ys[k], zs[k] + rad[k] * math.sin(2 * math.pi * j / 10)) for j in range(10)])
        s.loft(secs, "SafetyOrange" if i % 2 == 0 else "CarWhite", cap_start=(i == 0), cap_end=(i == n - 1))
    s.cyl(0.41, 0.012, (0, 0.335, 0.0), "Trim", axis='Y', seg=10)
    s.cyl(0.17, 0.012, (0, ys[-1] + 0.004, zs[-1]), "Trim", axis='Y', seg=10)
    s.obj("Sock", loc=(0.0, 0.0, H - 0.25))
    marker("Light", (0.0, 0.0, H + 0.32))


@asset("runway_light", slot=(15, 5.0, -6.0), family="airport", collision="none", max_tris=300,
       note="lens material P_LampWarm (emissive); the game may tint it per use (edge white, threshold green/red, taxiway blue)")
def build_runway_light(root):
    p = Part("Body")
    p.cyl(0.16, 0.03, (0, 0, 0.015), "ConcreteDark", seg=8)
    p.cyl(0.07, 0.05, (0, 0, 0.055), "HazardYellow", seg=8)
    p.cyl(0.03, 0.2, (0, 0, 0.18), "SteelDark", seg=6)
    p.cyl(0.075, 0.045, (0, 0, 0.3), "SteelDark", seg=8, r2=0.095)
    p.lathe([(0.085, 0.32), (0.085, 0.4), (0.06, 0.45), (0.02, 0.47)], (0, 0, 0), "LampWarm", seg=8)
    p.cyl(0.1, 0.014, (0, 0, 0.325), "Chrome", seg=8)
    p.obj("Body")
    marker("Light", (0.0, 0.0, 0.4))


@asset("runway_sign", slot=(15, -5.0, 6.0), family="airport", collision="box", max_tris=500,
       note="taxiway guidance board, readable from both sides (+Z / -Z); glyphs are abstract (arrow / bars), no lettering")
def build_runway_sign(root):
    p = Part("Sign")
    W, H0, H1 = 1.9, 0.32, 0.98
    for x in (-0.6, 0.6):
        p.box((0.24, 0.3, 0.04), (x, 0, 0.02), "ConcreteDark")
        p.cyl(0.035, H0, (x, 0, 0.04 + H0 / 2), "SteelDark", seg=6)
        p.cyl(0.05, 0.05, (x, 0, 0.15), "HazardYellow", seg=6)
    p.box((W, 0.22, H1 - H0), (0, 0, (H0 + H1) / 2), "Charcoal")
    for sy in (1, -1):
        y = sy * 0.112
        p.box((0.74, 0.012, H1 - H0 - 0.1), (-0.52 * sy, y, (H0 + H1) / 2), "FireRed")
        p.box((0.98, 0.012, H1 - H0 - 0.1), (0.38 * sy, y, (H0 + H1) / 2), "NeonYellow")
        zc = (H0 + H1) / 2
        # red panel: two white bars ; yellow panel: black arrow
        for dz in (-0.1, 0.1):
            p.box((0.46, 0.012, 0.09), (-0.52 * sy, y + sy * 0.006, zc + dz), "CarWhite")
        p.box((0.46, 0.012, 0.09), ((0.38 - 0.08) * sy, y + sy * 0.006, zc), "Trim")
        p.box((0.3, 0.012, 0.09), ((0.38 + 0.2) * sy, y + sy * 0.006, zc + 0.085), "Trim", rot=(0, math.radians(40) * sy, 0))
        p.box((0.3, 0.012, 0.09), ((0.38 + 0.2) * sy, y + sy * 0.006, zc - 0.085), "Trim", rot=(0, math.radians(-40) * sy, 0))
    p.box((W + 0.06, 0.26, 0.04), (0, 0, H1 + 0.02), "SteelDark")
    p.obj("Sign")


@asset("helipad_beacon", slot=(15, 5.0, 6.0), family="airport", collision="box", max_tris=700,
       note="child 'Lamp' (origin on the vertical axis) carries a green and a white lens on opposite sides: spin it around the vertical axis")
def build_helipad_beacon(root):
    p = Part("Base")
    p.cyl(0.32, 0.06, (0, 0, 0.03), "ConcreteDark", seg=8)
    p.box((0.34, 0.26, 0.42), (0, -0.02, 0.27), "HazardYellow")
    p.box((0.345, 0.2, 0.05), (0, -0.02, 0.3), "Trim")
    p.box((0.2, 0.012, 0.16), (0, 0.116, 0.3), "SteelDark")
    p.cyl(0.055, 0.9, (0, 0, 0.93), "SteelDark", seg=8)
    p.cyl(0.09, 0.05, (0, 0, 1.38), "SteelDark", seg=8)
    p.box((0.4, 0.3, 0.025), (0.0, -0.26, 1.05), "Navy", rot=(math.radians(35), 0, 0))
    p.beam((0, -0.05, 1.0), (0, -0.24, 1.03), 0.03, "SteelDark")
    # guard cage
    for a in (45, 135, 225, 315):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        p.tube((0.09 * c, 0.09 * s, 1.4), (0.24 * c, 0.24 * s, 1.5), 0.012, "Steel", seg=4, cap=False)
        p.tube((0.24 * c, 0.24 * s, 1.5), (0.24 * c, 0.24 * s, 1.84), 0.012, "Steel", seg=4, cap=False)
        p.tube((0.24 * c, 0.24 * s, 1.84), (0.0, 0.0, 1.98), 0.012, "Steel", seg=4, cap=False)
    p.sphere(0.035, (0, 0, 1.99), "M_Taillight", seg=6, rings=4)
    p.obj("Base")
    l = Part("Lamp")
    l.cyl(0.15, 0.3, (0, 0, 0.17), "Charcoal", seg=10)
    l.cyl(0.16, 0.04, (0, 0, 0.34), "Chrome", seg=10, r2=0.1)
    l.cyl(0.12, 0.03, (0, 0, 0.015), "Chrome", seg=10)
    l.cyl(0.1, 0.05, (0, 0.14, 0.17), "NeonGreen", axis='Y', seg=8)
    l.cyl(0.1, 0.05, (0, -0.14, 0.17), "HeadlightWhite", axis='Y', seg=8)
    l.obj("Lamp", loc=(0.0, 0.0, 1.41))
    marker("Light", (0.0, 0.0, 1.58))


@asset("aircraft_stairs", slot=(19, -5.0, 0.0), family="airport", collision="trimesh", max_tris=2000,
       note="mobile airstairs; climb from the back (+Z) up to the platform at the front (-Z, aircraft side, 2.6 m). Steps: rise 0.2 m / run 0.3 m - use markers "
            "Stairs_Bottom / Stairs_Top for a ramp collider if the character controller cannot step")
def build_aircraft_stairs(root):
    p = Part("Stairs")
    N, RISE, RUN = 13, 0.2, 0.3
    y0 = -2.6
    HW = 0.62
    top = N * RISE
    # chassis + wheels + tow bar + jacks
    p.bx(-0.7, 0.7, -1.95, 2.5, 0.28, 0.46, "Charcoal")
    for y in (-1.45, 2.0):
        p.cyl(0.24, 0.16, (0.8, y, 0.24), "Tire", axis='X', seg=10, sym=True)
        p.cyl(0.11, 0.17, (0.8, y, 0.24), "Rim", axis='X', seg=8, sym=True)
    p.beam((0.0, -1.95, 0.36), (0.0, -3.3, 0.3), 0.07, "HazardYellow")
    p.torus(0.08, 0.02, (0, -3.36, 0.3), "SteelDark", seg=8, rseg=4)
    for y in (-1.8, 2.3):
        p.bx(0.5, 0.62, y - 0.06, y + 0.06, 0.03, 0.3, "Steel", sym=True)
        p.bx(0.44, 0.68, y - 0.12, y + 0.12, 0.0, 0.03, "Steel", sym=True)
    # steps with yellow nosings
    for i in range(N):
        y = y0 + i * RUN
        z = (i + 1) * RISE
        p.bx(-HW + 0.03, HW - 0.03, y, y + RUN + 0.02, z - 0.045, z, "Steel")
        p.bx(-HW + 0.03, HW - 0.03, y, y + 0.05, z - 0.05, z + 0.004, "HazardYellow")
        p.bx(-HW + 0.03, HW - 0.03, y + RUN - 0.01, y + RUN + 0.02, z, z + RISE - 0.045, "SteelDark")
    ys_top = y0 + N * RUN
    y_end = ys_top + 1.35
    # platform + bumper
    p.bx(-HW - 0.05, HW + 0.05, ys_top, y_end, top - 0.07, top, "Steel")
    p.bx(-HW - 0.05, HW + 0.05, y_end, y_end + 0.09, top - 0.16, top + 0.02, "Trim")
    # side panels (white with teal stripe) along the flight and the platform
    for s in (1, -1):
        x = s * (HW + 0.02)
        lo0, lo1 = (y0 - 0.1, 0.05), (ys_top, top - 0.12)
        p.plate([(x, lo0[0], lo0[1]), (x, lo1[0], lo1[1]), (x, lo1[0], lo1[1] + 1.12), (x, lo0[0], lo0[1] + 1.12)], 0.04, "CarWhite")
        p.plate([(x, ys_top, top - 0.12), (x, y_end, top - 0.12), (x, y_end, top + 1.0), (x, ys_top, top + 1.0)], 0.04, "CarWhite")
        xs = s * (HW + 0.045)
        p.plate([(xs, lo0[0], lo0[1] + 0.5), (xs, lo1[0], lo1[1] + 0.5), (xs, lo1[0], lo1[1] + 0.72), (xs, lo0[0], lo0[1] + 0.72)], 0.012, "Teal")
        p.plate([(xs, ys_top, top + 0.38), (xs, y_end, top + 0.38), (xs, y_end, top + 0.6), (xs, ys_top, top + 0.6)], 0.012, "Teal")
        # handrail tube on top of the panels
        p.path([(x, lo0[0], lo0[1] + 1.14), (x, lo1[0], lo1[1] + 1.14), (x, y_end, top + 1.02)], 0.035, "Chrome", seg=6)
        # support frame
        xi = s * 0.55
        p.beam((xi, ys_top + 0.2, 0.46), (xi, ys_top + 0.2, top - 0.07), 0.08, "Steel")
        p.beam((xi, y_end - 0.15, 0.46), (xi, y_end - 0.15, top - 0.07), 0.08, "Steel")
        p.beam((xi, ys_top + 0.2, 0.5), (xi, y_end - 0.15, top - 0.15), 0.06, "Steel")
        p.beam((xi, -0.6, 0.46), (xi, -0.6, 6.5 * RISE), 0.07, "Steel")
        p.beam((xi, -0.6, 0.5), (xi, ys_top + 0.2, top - 0.3), 0.05, "Steel")
        p.beam((xi, y0 + 0.1, 0.12), (xi, ys_top, top - 0.12), 0.1, "Steel", h=0.14)
    p.obj("Stairs")
    marker("Stairs_Bottom", (0.0, y0 - 0.3, 0.0))
    marker("Stairs_Top", (0.0, ys_top + 0.1, top))
    marker("Platform", (0.0, ys_top + 0.75, top))


@asset("fuel_truck_static", slot=(19, 5.0, 0.0), family="airport", collision="box", max_tris=2500,
       note="decorative aviation fuel bowser (not a driveable vehicle)")
def build_fuel_truck_static(root):
    WR = 0.5          # wheel radius
    p = Part("~body")
    # chassis rails + axles
    p.bx(-0.45, 0.45, -3.6, 3.3, 0.62, 0.86, "Trim")
    for y in (2.35, -1.7, -2.85):
        p.cyl(0.07, 2.2, (0, y, WR), "Trim", axis='X', seg=6)
    # tank: elliptical shell with dished ends, coral + teal waistline, top walkway, manholes
    secs = []
    ty0, ty1, tz = -3.55, 1.05, 1.98
    for (y, k) in ((ty0, 0.55), (ty0 + 0.12, 0.86), (ty0 + 0.4, 1.0), (ty1 - 0.4, 1.0), (ty1 - 0.12, 0.86), (ty1, 0.55)):
        secs.append([(1.18 * k * math.cos(2 * math.pi * j / 12), y, tz + 0.98 * k * math.sin(2 * math.pi * j / 12)) for j in range(12)])
    p.loft(secs, "CarWhite")
    p.bx(-1.2, 1.2, ty0 + 0.45, ty1 - 0.45, tz - 0.2, tz + 0.0, "Teal")
    p.bx(-1.195, 1.195, ty0 + 0.45, ty1 - 0.45, tz + 0.0, tz + 0.09, "Coral")
    p.bx(-0.4, 0.4, ty0 + 0.5, ty1 - 0.5, tz + 0.95, tz + 1.03, "Steel")
    for y in (-2.6, -1.25, 0.1):
        p.cyl(0.26, 0.1, (0, y, tz + 1.07), "SteelDark", seg=8)
        p.cyl(0.2, 0.04, (0, y, tz + 1.13), "Steel", seg=8)
    p.railing([(0.42, y, tz + 1.0) for y in (ty0 + 0.6, -1.25, ty1 - 0.6)], 0.45, "Steel", mid=False, bar=0.03)
    # tank saddles, side lockers, mudguards
    for y in (-3.0, -1.2, 0.6):
        p.bx(-0.85, 0.85, y - 0.1, y + 0.1, 0.86, 1.2, "Trim")
    p.bx(0.75, 1.22, -1.05, 0.9, 0.62, 1.1, "CarWhite", sym=True)
    p.bx(1.22, 1.235, -0.9, -0.05, 0.68, 1.04, "SteelDark", sym=True)
    p.bx(1.22, 1.235, 0.05, 0.75, 0.68, 1.04, "SteelDark", sym=True)
    p.bx(0.72, 1.24, -3.45, -1.12, 1.06, 1.12, "Trim", sym=True)
    # rear pump cabinet with hose reel + meter
    p.bx(-1.15, 1.15, -4.0, -3.5, 0.66, 1.9, "CarWhite")
    p.bx(-1.0, 1.0, -4.012, -4.0, 0.8, 1.76, "SteelDark")
    p.torus(0.3, 0.085, (-0.5, -4.06, 1.3), "Trim", axis='Y', seg=10, rseg=5)
    p.cyl(0.18, 0.12, (-0.5, -4.06, 1.3), "SafetyOrange", axis='Y', seg=8)
    p.box((0.5, 0.05, 0.36), (0.5, -4.03, 1.42), "Charcoal")
    p.cyl(0.1, 0.03, (0.36, -4.065, 1.44), "CarWhite", axis='Y', seg=8)
    p.cyl(0.1, 0.03, (0.64, -4.065, 1.44), "CarWhite", axis='Y', seg=8)
    p.path([(-0.5, -4.1, 1.0), (-0.2, -4.14, 0.86), (0.4, -4.12, 0.9)], 0.04, "Trim", seg=5)
    p.bx(-1.2, 1.2, -4.1, -3.98, 0.5, 0.64, "Trim")
    for x in (0.95,):
        p.box((0.22, 0.03, 0.12), (x, -4.115, 0.57), "M_Taillight", sym=True)
        p.box((0.12, 0.03, 0.12), (x - 0.2, -4.115, 0.57), "M_Indicator", sym=True)
    # hazard placards (orange diamonds) + rear ladder
    for s in (1, -1):
        p.box((0.012, 0.42, 0.42), (s * 1.19, -2.4, tz + 0.42), "SafetyOrange", rot=(math.radians(45), 0, 0))
        p.box((0.014, 0.2, 0.2), (s * 1.195, -2.4, tz + 0.42), "CarWhite", rot=(math.radians(45), 0, 0))
    p.ladder((0.75, -3.62, 0.9), (0.75, -3.62, tz + 1.0), 0.36, "Steel", rungs=7, bar=0.035)
    # wheels (rear tandem + front)
    for y in (2.35, -1.7, -2.85):
        dual = y < 0
        w = 0.5 if dual else 0.3
        xc = 1.22 - w / 2
        p.cyl(WR, w, (xc, y, WR), "Tire", axis='X', seg=12, sym=True)
        p.cyl(0.28, w + 0.02, (xc, y, WR), "Rim", axis='X', seg=8, sym=True)
        p.cyl(0.1, w + 0.06, (xc, y, WR), "SteelDark", axis='X', seg=6, sym=True)
    body = p.obj("~body", smooth=35)

    c = Part("~cab")
    c.bx(-1.15, 1.15, 1.25, 3.55, 0.75, 1.75, "CarWhite")
    c.prism([(1.25, 1.75), (3.5, 1.75), (3.12, 2.72), (1.25, 2.72)], -1.12, 1.12, "CarWhite", axis='X')
    c.bx(-1.2, 1.2, 3.45, 3.72, 0.5, 0.8, "Trim")
    cab = c.obj("~cab", bevel=0.05)

    d = Part("~cabdetail")
    sl = math.atan2(0.38, 0.97)
    d.box((2.0, 0.03, 0.86), (0, 3.325, 2.24), "WindowDark", rot=(sl, 0, 0))
    d.bx(1.12, 1.135, 1.95, 3.0, 1.85, 2.55, "WindowDark", sym=True)
    d.bx(1.15, 1.165, 1.5, 3.0, 1.72, 1.78, "Teal", sym=True)
    d.bx(1.15, 1.162, 1.9, 2.95, 0.95, 1.7, "SteelDark", sym=True)
    d.bx(-0.7, 0.7, 3.55, 3.57, 1.0, 1.4, "Trim")
    for z in (1.08, 1.2, 1.32):
        d.bx(-0.62, 0.62, 3.57, 3.58, z - 0.03, z + 0.03, "Steel")
    d.box((0.3, 0.04, 0.18), (0.88, 3.56, 1.2), "M_Headlight", sym=True)
    d.box((0.14, 0.04, 0.1), (0.95, 3.735, 0.65), "M_Indicator", sym=True)
    d.box((0.5, 0.02, 0.14), (0.0, 3.73, 0.65), "CarWhite")
    d.beam((1.15, 3.2, 2.1), (1.42, 3.3, 2.1), 0.04, "Trim", sym=True)
    d.box((0.06, 0.16, 0.36), (1.44, 3.3, 2.05), "Trim", sym=True)
    d.box((0.5, 0.2, 0.1), (0, 2.2, 2.77), "IndicatorAmber")
    d.box((0.56, 0.24, 0.03), (0, 2.2, 2.735), "Trim")
    d.bx(0.6, 1.2, 1.3, 1.75, 0.5, 0.75, "Trim", sym=True)
    d.bx(1.15, 1.168, 1.78, 2.92, 0.75, 1.14, "Trim", sym=True)
    d.cyl(0.07, 1.1, (-0.95, 1.12, 2.4), "Chrome", seg=6)
    detail = d.obj("~cabdetail")
    join([body, cab, detail], "Truck")
    marker("Hose", (-0.5, -4.2, 1.0))
    marker("Driver_Door", (-1.6, 2.4, 0.0))


@asset("radar_dish", slot=(14, 5.0, 0.0), family="airport", collision="box", max_tris=1800,
       note="child 'Dish' (origin on the vertical axis at the turntable) is the rotating antenna: spin it around the vertical axis")
def build_radar_dish(root):
    p = Part("Tower")
    TH = 4.6
    p.lathe([(1.5, 0.0), (1.5, 0.25), (1.2, 0.4)], (0, 0, 0), "ConcreteDark", seg=8, phase=22.5)
    p.lathe([(0.62, 0.4), (0.5, 0.6), (0.42, TH - 0.5), (0.6, TH - 0.2)], (0, 0, 0), "CarWhite", seg=8, phase=22.5, cap_start=False)
    for z in (1.6, 2.9):
        p.lathe([(0.46, z), (0.46, z + 0.2)], (0, 0, 0), "SafetyOrange", seg=8, phase=22.5, cap_start=False, cap_end=False)
    # service platform + railing + ladder + equipment box
    p.lathe([(1.5, TH - 0.2), (1.5, TH - 0.1)], (0, 0, 0), "Steel", seg=8, phase=22.5)
    ring = [(1.42 * math.cos(math.radians(22.5 + 45 * i)), 1.42 * math.sin(math.radians(22.5 + 45 * i)), TH - 0.1) for i in range(9)]
    p.railing(ring, 0.95, "HazardYellow", mid=True, bar=0.04)
    p.ladder((0.0, -1.5, 0.3), (0.0, -1.45, TH - 0.1), 0.45, "Steel", rungs=12, bar=0.04)
    p.bx(-0.45, 0.45, 0.95, 1.4, 0.4, 1.5, "SteelDark")
    p.bx(-0.38, 0.38, 1.4, 1.415, 0.5, 1.4, "Steel")
    p.cyl(0.42, 0.3, (0, 0, TH + 0.05), "SteelDark", seg=10)
    p.obj("Tower")

    d = Part("~reflector")
    # parabolic-cylinder reflector: 4.6 m wide, 2.3 m tall, curved in plan, tilted back
    nx, nz = 8, 3
    Wd, Hd = 4.6, 2.3
    grid = []
    for iz in range(nz + 1):
        row = []
        v = iz / nz
        for ix in range(nx + 1):
            u = ix / nx * 2 - 1
            x = u * Wd / 2
            y = 0.5 * u * u + 0.22 * (2 * (v - 0.5)) ** 2 - (v - 0.5) * 0.25 - 0.3
            z = 0.75 + v * Hd - 0.25 * u * u * (v - 0.2)
            row.append((x, y, z))
        grid.append(row)
    for iz in range(nz):
        for ix in range(nx):
            m = "CarWhite" if (ix + iz) % 2 == 0 else "SafetyOrange"
            d.poly([grid[iz][ix + 1], grid[iz][ix], grid[iz + 1][ix], grid[iz + 1][ix + 1]], m)     # normals toward +Y (feed side)
    d.m("Steel")
    refl = d.obj("~reflector", solidify=0.05, solid_mat_offset=99, recalc=False)
    b = Part("~dishframe")
    b.cyl(0.36, 0.3, (0, 0, 0.15), "Charcoal", seg=10)
    b.bx(-0.3, 0.3, -0.75, -0.1, 0.3, 1.0, "SteelDark")
    b.beam((0, -0.4, 0.9), (0, -0.2, 2.4), 0.14, "SteelDark")
    for s in (-1, 1):
        b.beam((0, -0.36, 1.9), (s * 2.0, 0.1, 1.9), 0.08, "SteelDark")
        b.beam((0, -0.36, 1.0), (s * 1.5, -0.12, 1.02), 0.08, "SteelDark")
        b.beam((s * 1.5, -0.12, 1.02), (s * 1.95, 0.02, 2.75), 0.06, "SteelDark")
        b.beam((0, -0.3, 2.4), (s * 1.0, -0.2, 2.9), 0.06, "SteelDark")
    # feed horn on a boom in front of the reflector
    b.beam((0, 0.0, 0.5), (0, 1.7, 1.25), 0.09, "SteelDark")
    b.beam((0, 0.9, 0.9), (0, 0.1, 1.3), 0.05, "SteelDark")
    b.tbox((0.2, 0.2), (0.46, 0.4), 0.42, (0, 1.72, 1.2), "Charcoal")
    hv = b.new_verts(b.count() - 8)
    b.move(hv, rot=(math.radians(115), 0, 0), pivot=(0, 1.72, 1.2))
    b.sphere(0.07, (0, -0.2, 2.5), "M_Taillight", seg=6, rings=4)
    frame = b.obj("~dishframe")
    dish = join([refl, frame], "Dish")
    dish.location = (0.0, 0.0, TH + 0.2)
    marker("Light", (0.0, -0.2, TH + 2.75))


# ================================================================================================
# ACTIVITIES
# ================================================================================================
@asset("target_round", slot=(20, -5.0, -6.0), family="activities", collision="box", max_tris=900,
       note="child 'Target' = ring face (origin at the bullseye, faces the front (-Z), radius 0.45, leans back 6 deg); child 'Stand' = easel",
       target_radius=0.45, ring_radii=[0.45, 0.36, 0.27, 0.18, 0.09])
def build_target_round(root):
    s = Part("Stand")
    cz = 1.3
    s.beam((0.42, 0.12, 0.0), (0.2, -0.06, 1.95), 0.055, "Wood", sym=True)
    s.beam((0.0, -0.95, 0.0), (0.0, -0.08, 1.9), 0.055, "Wood")
    s.beam((-0.24, -0.06, 1.9), (0.24, -0.06, 1.9), 0.06, "WoodDark")
    s.beam((-0.37, 0.07, 0.5), (0.37, 0.07, 0.5), 0.05, "WoodDark")
    s.beam((0.0, 0.07, 0.5), (0.0, -0.62, 0.68), 0.04, "WoodDark")
    s.box((0.5, 0.1, 0.05), (0, 0.08, cz - 0.52), "WoodDark")
    s.obj("Stand")
    t = Part("Target")
    t.cyl(0.5, 0.07, (0, -0.045, 0), "Khaki", axis='Y', seg=14)                     # straw boss
    cols = ["CarWhite", "Trim", "CarBlue", "CarRed", "CarYellow"]
    for i, c in enumerate(cols):
        r = 0.45 - i * 0.09
        t.cyl(r, 0.012, (0, -0.006 + i * 0.006, 0), c, axis='Y', seg=14)
    t.obj("Target", loc=(0.0, 0.12, cz), rot=(math.radians(6), 0, 0))
    marker("Bullseye", (0.0, 0.15, cz))


def _bottle_profile(sc=1.0):
    pts = [(-0.17, 0.0), (0.17, 0.0), (0.17, 0.5), (0.14, 0.6), (0.06, 0.7), (0.06, 0.9), (0.075, 0.91), (0.075, 0.96),
           (-0.075, 0.96), (-0.075, 0.91), (-0.06, 0.9), (-0.06, 0.7), (-0.14, 0.6), (-0.17, 0.5)]
    return [(x * sc, z * sc) for (x, z) in pts]


@asset("target_silhouette", slot=(20, 5.0, -6.0), family="activities", collision="box", max_tris=700,
       note="knock-down steel target shaped like a BOTTLE (abstract, not a figure). Child 'Target' has its origin on the "
            "hinge axis (local X) and faces the front (-Z): set rotation.x = +PI/2 to lay it down backward.")
def build_target_silhouette(root):
    b = Part("Base")
    b.bx(-0.45, 0.45, -0.3, 0.3, 0.0, 0.03, "SteelDark")
    b.bx(-0.4, 0.4, -0.05, 0.05, 0.03, 0.2, "Charcoal")
    for x in (-0.3, 0.3):
        b.bx(x - 0.04, x + 0.04, -0.07, 0.07, 0.03, 0.32, "Charcoal")
    b.cyl(0.03, 0.72, (0, 0, 0.3), "Steel", axis='X', seg=6)
    b.bx(-0.45, 0.45, -0.3, -0.24, 0.03, 0.09, "HazardYellow")
    b.bx(-0.45, 0.45, 0.24, 0.3, 0.03, 0.09, "HazardYellow")
    b.beam((0.0, -0.04, 0.2), (0.0, -0.27, 0.05), 0.05, "Charcoal")
    b.obj("Base")
    t = Part("Target")
    t.bx(-0.05, 0.05, -0.012, 0.012, 0.0, 0.45, "SteelDark")
    prof = _bottle_profile(1.0)
    t.prism(prof, -0.012, 0.012, "CarWhite", axis='Y')
    v = t.new_verts(t.count() - len(prof) * 2)
    t.move(v, offset=(0, 0, 0.4))
    # label band + bullseye disc on the front face, cap
    t.bx(-0.171, 0.171, 0.0, 0.019, 0.56, 0.78, "CarRed")
    t.cyl(0.085, 0.012, (0, 0.022, 0.67), "CarYellow", axis='Y', seg=10)
    t.bx(-0.076, 0.076, -0.013, 0.02, 1.31, 1.362, "Mustard")
    t.obj("Target", loc=(0.0, 0.0, 0.3))
    marker("Hit_Center", (0.0, 0.02, 0.97))


def _ramp_deck(p, prof, hw, th, mat, edge_mat=None):
    """Closed deck plates along a (y, z) profile, width 2*hw."""
    for (a, b) in zip(prof[:-1], prof[1:]):
        p.plate([(-hw, a[0], a[1]), (hw, a[0], a[1]), (hw, b[0], b[1]), (-hw, b[0], b[1])], th, mat)


@asset("stunt_ramp_small", slot=(21, -5.0, 0.0), family="activities", collision="trimesh", max_tris=600,
       note="kicker: drive toward the model's front (-Z); 3 m long, 1 m lip, 2.4 m wide", lip_height=1.0, lip_angle_deg=26.0)
def build_stunt_ramp_small(root):
    p = Part("Ramp")
    prof = [(-1.5, 0.0), (-0.6, 0.2), (0.45, 0.54), (1.5, 1.0)]
    HW = 1.2
    body = prof + [(1.5, 0.0)]
    p.prism(body, -HW + 0.03, HW - 0.03, "HazardYellow", axis='X')
    for (a, b) in zip(prof[:-1], prof[1:]):
        p.slab([(-HW, a[0], a[1] + 0.035), (HW, a[0], a[1] + 0.035), (HW, b[0], b[1] + 0.035), (-HW, b[0], b[1] + 0.035)], 0.035, "Wood")
    # plank seams
    for i in range(1, 9):
        t = i / 9.0
        y = -1.5 + 3.0 * t
        k = max(j for j in range(3) if prof[j][0] <= y + 1e-6)
        a, b = prof[k], prof[k + 1]
        z = a[1] + (b[1] - a[1]) * (y - a[0]) / (b[0] - a[0])
        sl = math.atan2(b[1] - a[1], b[0] - a[0])
        p.box((2 * HW - 0.1, 0.03, 0.012), (0, y, z + 0.037), "WoodDark", rot=(sl, 0, 0))
    # black chevrons on the yellow sides
    for s in (1, -1):
        x = s * (HW - 0.024)
        for (y, h) in ((-0.2, 0.22), (0.4, 0.42), (0.95, 0.62)):
            p.plate([(x, y, 0.05), (x, y + 0.22, 0.05), (x, y + 0.22 + h * 0.45, 0.05 + h), (x, y + h * 0.45, 0.05 + h)], 0.014, "Trim")
    p.bx(-HW, HW, 1.5, 1.53, 0.0, 0.98, "Charcoal")
    p.bx(-HW, HW, -1.56, -1.44, 0.0, 0.025, "Steel")
    p.obj("Ramp")
    marker("Entry", (0.0, -1.8, 0.0))
    marker("Lip", (0.0, 1.5, 1.0))


@asset("stunt_ramp_big", slot=(21, 4.0, 0.0), family="activities", collision="trimesh", max_tris=1800,
       note="scaffold stunt ramp: drive toward the model's front (-Z); 8 m long, 5 m wide, lip 2.6 m", lip_height=2.6, lip_angle_deg=31.0)
def build_stunt_ramp_big(root):
    p = Part("Ramp")
    prof = [(-4.0, 0.0), (-2.6, 0.2), (-1.1, 0.58), (0.4, 1.12), (1.9, 1.82), (3.3, 2.6)]
    HW = 2.5
    _ramp_deck(p, prof, HW, 0.12, "SteelDark")
    # yellow edge lines + white chevrons on the deck
    for (a, b) in zip(prof[:-1], prof[1:]):
        sl = math.atan2(b[1] - a[1], b[0] - a[0])
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        cy, cz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        nz, ny = math.cos(sl), -math.sin(sl)
        p.box((0.16, L, 0.012), (HW - 0.2, cy + ny * 0.064, cz + nz * 0.064), "HazardYellow", rot=(sl, 0, 0), sym=True)
        for s in (1, -1):
            R = Matrix.Rotation(sl, 3, 'X') @ Matrix.Rotation(math.radians(32) * s, 3, 'Z')
            p.box((1.0, 0.2, 0.012), (0.42 * s, cy + ny * 0.064, cz + nz * 0.064), "CarWhite", rot=R)
    # low side rails
    for (a, b) in zip(prof[1:-1], prof[2:]):
        p.beam((HW - 0.05, a[0], a[1] + 0.28), (HW - 0.05, b[0], b[1] + 0.28), 0.08, "HazardYellow", sym=True)
    for a in prof[1:]:
        p.beam((HW - 0.05, a[0], a[1]), (HW - 0.05, a[0], a[1] + 0.28), 0.07, "HazardYellow", sym=True)
    # scaffold bents under the deck
    for (y, z) in prof[2:]:
        zt = z - 0.08
        for x in (-2.3, 0.0, 2.3):
            p.beam((x, y, 0.0), (x, y, zt), 0.09, "SafetyOrange")
            p.box((0.26, 0.26, 0.03), (x, y, 0.015), "Steel")
        p.beam((-2.3, y, zt - 0.06), (2.3, y, zt - 0.06), 0.09, "SafetyOrange")
        if zt > 0.9:
            p.beam((-2.3, y, 0.12), (0.0, y, zt - 0.15), 0.05, "Steel")
            p.beam((2.3, y, 0.12), (0.0, y, zt - 0.15), 0.05, "Steel")
    for (a, b) in zip(prof[2:-1], prof[3:]):
        for x in (-2.3, 2.3):
            p.beam((x, a[0], 0.15), (x, b[0], b[1] - 0.25), 0.05, "Steel")
            p.beam((x, a[0], a[1] - 0.2), (x, b[0], b[1] - 0.2), 0.07, "SafetyOrange")
    # rear tower legs + lip plate + coral side banners
    yl, zl = prof[-1]
    p.bx(-HW, HW, yl, yl + 0.06, zl - 0.5, zl + 0.02, "HazardYellow")
    for s in (1, -1):
        x = s * (HW + 0.02)
        p.plate([(x, prof[3][0], prof[3][1] - 0.75), (x, yl, zl - 1.05), (x, yl, zl - 0.15), (x, prof[3][0], prof[3][1] - 0.15)], 0.03, "Coral")
        p.plate([(s * (HW + 0.04), prof[3][0] + 0.3, prof[3][1] - 0.38), (s * (HW + 0.04), yl - 0.2, zl - 0.6),
                 (s * (HW + 0.04), yl - 0.2, zl - 0.42), (s * (HW + 0.04), prof[3][0] + 0.3, prof[3][1] - 0.24)], 0.012, "CarWhite")
    # approach flap
    p.plate([(-HW, -4.35, 0.0), (HW, -4.35, 0.0), (HW, -4.0, 0.03), (-HW, -4.0, 0.03)], 0.03, "Steel")
    p.obj("Ramp")
    marker("Entry", (0.0, -4.6, 0.0))
    marker("Lip", (0.0, yl, zl))


def _sweep_xz(p, pts, r, mats, seg=8, squash=1.0):
    """Tube swept along a path in the XZ plane (y = 0); mitred joints; one material per segment."""
    P = [Vector((q[0], 0.0, q[1])) for q in pts]
    rings = []
    n = len(P)
    for i in range(n):
        if i == 0:
            t = (P[1] - P[0]).normalized()
        elif i == n - 1:
            t = (P[-1] - P[-2]).normalized()
        else:
            t = ((P[i] - P[i - 1]).normalized() + (P[i + 1] - P[i]).normalized()).normalized()
        nrm = Vector((-t.z, 0.0, t.x))
        k = 1.0
        if 0 < i < n - 1:
            c = (P[i] - P[i - 1]).normalized().dot(t)
            k = 1.0 / max(c, 0.5)
        ring_pts = []
        for j in range(seg):
            a = 2 * math.pi * j / seg
            ring_pts.append(tuple(P[i] + nrm * (r * k * math.cos(a)) + Vector((0, r * squash * math.sin(a), 0))))
        rings.append(ring_pts)
    out = []
    for i in range(n - 1):
        out += p.loft([rings[i], rings[i + 1]], mats[i % len(mats)], cap_start=(i == 0), cap_end=(i == n - 2))
    return out


@asset("checkpoint_arch", slot=(22, 0.0, 0.0), family="activities", collision="trimesh", max_tris=1500,
       note="inflatable start/finish arch; drive through along Z. Clear opening 8.1 m wide (between the feet) x 3.65 m (under the banner)",
       opening_width=8.1, opening_height=3.65)
def build_checkpoint_arch(root):
    p = Part("Arch")
    R = 0.55
    X = 5.0
    Z = 5.0
    path = [(-X, 0.0), (-X, 1.3), (-X, 2.6), (-X, 3.7)]
    for a in (150, 120):
        path.append((-X + 1.3 + 1.3 * math.cos(math.radians(a)) * 1.0, 3.7 + 1.3 * math.sin(math.radians(a))))
    path += [(-X + 1.3, Z), (-2.2, Z), (0.0, Z), (2.2, Z), (X - 1.3, Z)]
    for a in (60, 30):
        path.append((X - 1.3 + 1.3 * math.cos(math.radians(a)), 3.7 + 1.3 * math.sin(math.radians(a))))
    path += [(X, 3.7), (X, 2.6), (X, 1.3), (X, 0.0)]
    mats = ["Coral", "CarWhite", "Teal", "Coral", "Coral", "CarWhite", "Teal", "CarWhite", "Teal", "CarWhite", "Coral", "Coral", "Teal", "CarWhite", "Coral"]
    _sweep_xz(p, path, R, mats, seg=8)
    # fat feet, sandbags, blower, tie-downs
    for s in (1, -1):
        p.lathe([(0.95, 0.0), (0.95, 0.3), (0.7, 0.55)], (s * X, 0, 0), "Navy", seg=8, phase=22.5)
        for (dx, dy, rz) in ((0.9, 0.75, 0.3), (-0.2, 1.05, 1.2), (0.6, -0.95, -0.4)):
            p.sphere(0.3, (s * (X + dx * 0.6), dy, 0.12), "Khaki", seg=6, rings=4, scale=(1.3, 0.8, 0.42), rot=(0, 0, rz))
        for sy in (1, -1):
            p.tube((s * (X - 0.2), sy * 0.35, 3.6), (s * (X + 1.6), sy * 2.6, 0.02), 0.012, "Trim", seg=3, cap=False)
            p.box((0.1, 0.1, 0.12), (s * (X + 1.6), sy * 2.6, 0.05), "SteelDark")
    p.box((0.6, 0.5, 0.5), (X + 0.4, -1.5, 0.25), "Mustard")
    p.cyl(0.17, 0.2, (X + 0.4, -1.2, 0.27), "Trim", axis='Y', seg=8)
    p.tube((X + 0.4, -1.1, 0.27), (X, -0.5, 0.3), 0.14, "CarWhite", seg=6)
    # chequered banner under the top beam (both faces)
    bw, bh = 6.4, 0.8
    z0 = Z - R - bh + 0.1
    p.box((bw + 0.12, 0.05, bh + 0.12), (0, 0, z0 + bh / 2), "Navy")
    nx, nz = 16, 2
    for ix in range(nx):
        for iz in range(nz):
            m = "CarWhite" if (ix + iz) % 2 == 0 else "Trim"
            x = -bw / 2 + (ix + 0.5) * bw / nx
            z = z0 + (iz + 0.5) * bh / nz
            p.box((bw / nx, 0.07, bh / nz), (x, 0, z), m)
    p.obj("Arch")
    marker("Gate", (0.0, 0.0, 0.0))
    marker("Post_L", (-X, 0.0, 0.0))
    marker("Post_R", (X, 0.0, 0.0))


@asset("race_flag", slot=(20, -5.0, 6.0), family="activities", collision="none", max_tris=600,
       note="chequered marker flag in a weighted tyre base; flag flies toward +X")
def build_race_flag(root):
    p = Part("Flag")
    p.torus(0.27, 0.11, (0, 0, 0.11), "Tire", seg=10, rseg=5)
    p.cyl(0.2, 0.14, (0, 0, 0.09), "Concrete", seg=8)
    p.cyl(0.022, 2.7, (0, 0, 1.45), "CarWhite", seg=6)
    p.sphere(0.04, (0, 0, 2.82), "CarYellow", seg=6, rings=4)
    nx, nz = 5, 4
    fw, fh = 1.0, 0.68
    for ix in range(nx):
        for iz in range(nz):
            m = "Trim" if (ix + iz) % 2 == 0 else "CarWhite"
            x0 = 0.03 + ix * fw / nx
            x1 = x0 + fw / nx
            y0 = 0.09 * math.sin(ix * 1.25)
            y1 = 0.09 * math.sin((ix + 1) * 1.25)
            z0 = 2.75 - fh + iz * fh / nz - 0.02 * ix
            z1 = z0 + fh / nz
            p.plate([(x0, y0, z0), (x1, y1, z0 - 0.02), (x1, y1, z1 - 0.02), (x0, y0, z1)], 0.014, m)
    p.obj("Flag")


# ================================================================================================
# POLICE
# ================================================================================================
@asset("spike_strip", slot=(1, 5.0, 6.0), family="police", collision="none", max_tris=1000,
       note="lies across the road along X (4 m); vehicles cross it along Z. Spikes 14 cm high", length=4.0)
def build_spike_strip(root):
    p = Part("Strip")
    n = 8
    L = 4.0
    cell = L / n
    for i in range(n):
        x0 = -L / 2 + i * cell
        p.beam((x0, -0.14, 0.02), (x0 + cell, 0.14, 0.02), 0.045, "Charcoal", h=0.025)
        p.beam((x0, 0.14, 0.035), (x0 + cell, -0.14, 0.035), 0.045, "Charcoal", h=0.025)
        p.box((0.05, 0.05, 0.05), (x0 + cell / 2, 0, 0.03), "Steel", rot=(0, 0, 0.785))
    for i in range(n + 1):
        x = -L / 2 + i * cell
        for y in (-0.14, 0.14):
            p.box((0.05, 0.05, 0.045), (x, y, 0.03), "Steel", rot=(0, 0, 0.785))
            p.cyl(0.012, 0.085, (x, y, 0.09), "Chrome", seg=4, r2=0.001)
    for i in range(n):
        x = -L / 2 + (i + 0.5) * cell
        p.cyl(0.012, 0.085, (x, 0, 0.095), "Chrome", seg=4, r2=0.001)
    # handle + pull cord at one end, hi-vis end caps
    for s in (1, -1):
        p.box((0.06, 0.4, 0.04), (s * (L / 2 + 0.03), 0, 0.03), "HazardYellow")
    p.path([(L / 2 + 0.06, 0, 0.03), (L / 2 + 0.5, 0.1, 0.012), (L / 2 + 0.9, -0.08, 0.012), (L / 2 + 1.2, 0.05, 0.012)], 0.012, "Trim", seg=4)
    p.torus(0.07, 0.014, (L / 2 + 1.27, 0.05, 0.016), "SafetyOrange", seg=8, rseg=4)
    p.obj("Strip")


@asset("police_light_stand", slot=(8, 5.0, 6.0), family="police", collision="box", max_tris=900,
       note="portable scene light: red / blue lamps use M_Siren_Red / M_Siren_Blue, floods P_HeadlightWhite")
def build_police_light_stand(root):
    p = Part("Stand")
    # generator base
    p.box((0.62, 0.46, 0.4), (0, 0, 0.3), "PoliceBlue")
    p.box((0.63, 0.47, 0.07), (0, 0, 0.36), "PoliceWhite")
    p.box((0.3, 0.012, 0.16), (0, 0.236, 0.22), "Trim")
    for x in (-0.24, 0.24):
        for y in (-0.16, 0.16):
            p.cyl(0.035, 0.1, (x, y, 0.05), "Trim", seg=6)
    p.box((0.4, 0.05, 0.03), (0, 0, 0.56), "Trim")
    p.beam((-0.2, 0, 0.5), (-0.2, 0, 0.56), 0.03, "Trim")
    p.beam((0.2, 0, 0.5), (0.2, 0, 0.56), 0.03, "Trim")
    # outriggers
    for a in (30, 150, 270):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        p.beam((0.2 * c, 0.2 * s, 0.14), (0.85 * c, 0.85 * s, 0.03), 0.04, "Steel")
        p.cyl(0.06, 0.03, (0.85 * c, 0.85 * s, 0.015), "Trim", seg=6)
    # telescopic mast
    p.cyl(0.045, 1.0, (0, -0.12, 1.0), "Steel", seg=8)
    p.cyl(0.035, 0.9, (0, -0.12, 1.9), "Chrome", seg=8)
    p.cyl(0.055, 0.06, (0, -0.12, 1.5), "Trim", seg=8)
    # light bar: red + blue beacons
    zb = 2.28
    p.box((0.9, 0.08, 0.06), (0, -0.12, zb), "Trim")
    p.box((0.34, 0.14, 0.1), (-0.26, -0.12, zb + 0.08), "M_Siren_Red")
    p.box((0.34, 0.14, 0.1), (0.26, -0.12, zb + 0.08), "M_Siren_Blue")
    p.box((0.14, 0.15, 0.11), (0, -0.12, zb + 0.08), "PoliceWhite")
    # two flood heads above
    p.cyl(0.03, 0.3, (0, -0.12, zb + 0.24), "Chrome", seg=6)
    p.box((0.8, 0.05, 0.05), (0, -0.12, zb + 0.4), "Trim")
    for x in (-0.3, 0.3):
        v = p.box((0.34, 0.14, 0.24), (x, -0.08, zb + 0.4), "Charcoal")
        v += p.box((0.29, 0.02, 0.19), (x, 0.0, zb + 0.4), "HeadlightWhite")
        p.move(v, rot=(math.radians(-14), 0, 0), pivot=(x, -0.12, zb + 0.4))
    p.obj("Stand")
    marker("Light_Red", (-0.26, -0.12, zb + 0.08))
    marker("Light_Blue", (0.26, -0.12, zb + 0.08))
    marker("Light_Flood", (0.0, 0.05, zb + 0.4))


# ================================================================================================
# PARACHUTE
# ================================================================================================
@asset("parachute_canopy", slot=(23, 0.0, 0.0), family="parachute", collision="none", max_tris=1500,
       note="ram-air canopy, 7 m span; ORIGIN = harness point (pilot's shoulders), canopy 4.6 m above; leading edge toward the front (-Z)",
       span=7.0, chord=2.9)
def build_parachute_canopy(root):
    p = Part("Canopy")
    NC = 9
    TH0, TH1 = math.radians(-36), math.radians(36)
    RA = 3.5 / math.sin(TH1) * 1.0          # arc radius so the projected span is 7 m
    ZT = 4.75
    cols = ["Coral", "CarWhite", "Teal", "CarWhite", "CarYellow", "CarWhite", "Teal", "CarWhite", "Coral"]
    # chord stations: (y, top thickness, bottom offset)
    CH = [(1.45, 0.16, 0.02), (0.95, 0.36, 0.0), (0.1, 0.32, 0.0), (-1.45, 0.03, 0.0)]

    def rib(th, bulge=0.0):
        cx, cz = RA * math.sin(th), ZT - RA * (1 - math.cos(th))
        nx, nz = math.sin(th), math.cos(th)
        topp = [(cx + nx * (t + bulge * (0.6 if i in (1, 2) else 0.25)), y, cz + nz * (t + bulge * (0.6 if i in (1, 2) else 0.25))) for i, (y, t, b) in enumerate(CH)]
        botp = [(cx - nx * b, y, cz - nz * b) for (y, t, b) in CH]
        return topp, botp
    ribs = []
    for i in range(NC + 1):
        th = TH0 + (TH1 - TH0) * i / NC
        ribs.append((th, rib(th)))
    for i in range(NC):
        m = cols[i]
        thm = (ribs[i][0] + ribs[i + 1][0]) / 2
        ta, ba = ribs[i][1]
        tb, bb = ribs[i + 1][1]
        tm, bm_ = rib(thm, 0.16)
        for k in range(3):
            p.poly([ta[k], tm[k], tm[k + 1], ta[k + 1]], m)
            p.poly([tm[k], tb[k], tb[k + 1], tm[k + 1]], m)
            p.poly([ba[k], ba[k + 1], bb[k + 1], bb[k]], m)
        # open cell mouth (dark) + trailing edge
        p.poly([ta[0], ba[0], bb[0], tb[0], tm[0]], "Navy")
        p.poly([ta[3], tm[3], tb[3], bb[3], ba[3]], m)
    # wing tips + stabiliser panels
    for (th, (tp, bp)), sgn in ((ribs[0], -1), (ribs[-1], 1)):
        p.poly(tp + list(reversed(bp)), "Navy")
        nx, nz = math.sin(th), math.cos(th)
        a, b = Vector(bp[1]), Vector(bp[3])
        drop = Vector((-nx * 0.0 + sgn * 0.0, 0, 0)) + Vector((-nx, 0, -nz)) * 0.75
        p.plate([tuple(a), tuple(b), tuple(a.lerp(b, 0.45) + drop)], 0.02, "Navy")
    canopy = p.obj("Canopy")

    l = Part("Lines")
    riser_top = {-1: Vector((-0.24, 0.05, 0.95)), 1: Vector((0.24, 0.05, 0.95))}
    riser_top_r = {-1: Vector((-0.24, -0.1, 0.95)), 1: Vector((0.24, -0.1, 0.95))}
    for i in range(NC + 1):
        th, (tp, bp) = ribs[i]
        side = -1 if i < (NC + 1) / 2 else 1
        l.tube(riser_top[side], bp[0], 0.011, "Trim", seg=3, cap=False)
        l.tube(riser_top[side], bp[1], 0.011, "Trim", seg=3, cap=False)
        l.tube(riser_top_r[side], bp[2], 0.011, "Trim", seg=3, cap=False)
        if i % 3 == 0 or i == NC:
            l.tube(riser_top_r[side], Vector(bp[3]) + Vector((0, 0.3, 0)), 0.011, "Trim", seg=3, cap=False)
    for s in (-1, 1):
        # risers (webbing), toggles + steering lines to the trailing edge
        l.beam((s * 0.2, 0.0, 0.0), riser_top[s], 0.05, "Charcoal", h=0.014)
        l.beam((s * 0.2, -0.04, 0.0), riser_top_r[s], 0.05, "Charcoal", h=0.014)
        tg = Vector((s * 0.33, -0.12, 0.62))
        l.box((0.04, 0.03, 0.14), tuple(tg), "CarYellow")
        tip = ribs[0][1][1][3] if s == -1 else ribs[-1][1][1][3]
        mid = ribs[2][1][1][3] if s == -1 else ribs[-3][1][1][3]
        l.tube(tg + Vector((0, 0, 0.07)), mid, 0.011, "CarYellow", seg=3, cap=False)
        l.tube(tg + Vector((0, 0, 0.07)), tip, 0.011, "CarYellow", seg=3, cap=False)
    # slider
    l.box((0.62, 0.36, 0.012), (0, -0.02, 1.1), "Coral")
    l.obj("Lines")
    marker("Harness", (0.0, 0.0, 0.0))
    marker("Toggle_L", (-0.33, -0.12, 0.62))
    marker("Toggle_R", (0.33, -0.12, 0.62))
    marker("Canopy_Center", (0.0, 0.0, ZT))


@asset("parachute_pack", slot=(20, 5.0, 6.0), family="parachute", collision="none", max_tris=900, root="misc_parachute_pack",
       note="worn rig: ORIGIN = centre of the wearer's back (pack surface that touches the back); the pack extends backward (+Z). "
            "Child 'Straps' (harness webbing sized for the 1.8 m humanoid) can be hidden if it clips an outfit")
def build_parachute_pack(root):
    b = Part("~pack")
    b.tbox((0.36, 0.17), (0.3, 0.13), 0.5, (0, -0.095, -0.27), "Navy", top_offset=(0, 0.01))
    pack = b.obj("~pack", bevel=0.03)
    d = Part("~packdetail")
    # main flap, reserve flap, pin cover, side stripes, ripcord handle, pilot-chute pouch
    d.box((0.26, 0.02, 0.22), (0, -0.182, -0.12), "Coral", rot=(math.radians(-3), 0, 0))
    d.box((0.22, 0.02, 0.14), (0, -0.168, 0.1), "Charcoal", rot=(math.radians(-5), 0, 0))
    d.box((0.06, 0.025, 0.1), (0, -0.185, -0.02), "Trim")
    d.box((0.012, 0.13, 0.36), (0.172, -0.095, -0.05), "CarWhite", sym=True)
    d.cyl(0.03, 0.14, (0, -0.1, -0.29), "Coral", axis='X', seg=6)
    d.sphere(0.028, (0.085, -0.1, -0.29), "HazardYellow", seg=6, rings=4)
    d.box((0.05, 0.018, 0.09), (-0.2, 0.01, 0.02), "HazardYellow")
    d.box((0.05, 0.018, 0.09), (0.2, 0.01, 0.02), "Chrome")
    detail = d.obj("~packdetail")
    join([pack, detail], "Pack")
    s = Part("Straps")
    T = "Trim"
    # shoulder straps: from the pack top, over the shoulder, down the chest to the hip ring
    s.ribbon([(0.12, -0.03, 0.2), (0.125, 0.02, 0.275), (0.13, 0.11, 0.29), (0.135, 0.19, 0.225), (0.14, 0.225, 0.06), (0.15, 0.22, -0.19)],
             (1, 0, 0), 0.05, 0.014, T, sym=True)
    # lateral straps from the hip ring back to the pack
    s.ribbon([(0.15, 0.215, -0.19), (0.19, 0.1, -0.215), (0.172, -0.03, -0.2)], (0, 0, 1), 0.045, 0.014, T, sym=True)
    # leg loops
    s.ribbon([(0.15, 0.21, -0.2), (0.165, 0.17, -0.34), (0.13, 0.03, -0.42), (0.1, -0.09, -0.36), (0.13, -0.07, -0.24)],
             (1, 0, 0.25), 0.045, 0.014, T, sym=True)
    # chest strap + buckles + hip rings
    s.ribbon([(-0.14, 0.232, 0.06), (0.0, 0.245, 0.06), (0.14, 0.232, 0.06)], (0, 0, 1), 0.04, 0.012, T)
    s.box((0.05, 0.02, 0.05), (0.0, 0.252, 0.06), "Chrome")
    s.box((0.045, 0.02, 0.045), (0.15, 0.228, -0.19), "Chrome", sym=True)
    s.obj("Straps")
    marker("Deploy", (0.0, -0.1, 0.2))


# ================================================================================================
# SERVICE
# ================================================================================================
@asset("traffic_barrier_arm", slot=(1, -5.0, 6.0), family="service", collision="box", max_tris=900,
       note="boom gate across X; child 'Arm' pivots at the housing (origin on the hinge, hinge axis = local Y / Godot Z): "
            "rotate it by +80 deg around Godot Z to open. Origin = lane centre",
       arm_length=4.2)
def build_traffic_barrier_arm(root):
    px = -2.2
    b = Part("~housing")
    b.box((0.42, 0.42, 1.05), (px, 0, 0.575), "Mustard")
    b.box((0.5, 0.5, 0.06), (px, 0, 1.13), "Charcoal")
    housing = b.obj("~housing", bevel=0.03)
    d = Part("~base")
    d.box((0.6, 0.6, 0.05), (px, 0, 0.025), "ConcreteDark")
    d.box((0.3, 0.012, 0.6), (px, 0.216, 0.55), "SteelDark")
    d.cyl(0.03, 0.03, (px + 0.1, 0.23, 0.6), "Chrome", axis='Y', seg=6)
    d.box((0.425, 0.425, 0.1), (px, 0, 0.2), "Trim")
    d.cyl(0.07, 0.1, (px, 0, 1.21), "M_Taillight", seg=8)
    d.cyl(0.08, 0.02, (px, 0, 1.27), "Charcoal", seg=8)
    d.cyl(0.1, 0.08, (px, 0.25, 0.95), "Charcoal", axis='Y', seg=8)
    # catch post at the free end
    ex = 2.15
    d.box((0.3, 0.3, 0.04), (ex, 0.3, 0.02), "ConcreteDark")
    d.box((0.08, 0.08, 0.84), (ex, 0.3, 0.46), "Mustard")
    d.box((0.05, 0.24, 0.04), (ex, 0.3, 0.87), "Charcoal")
    d.box((0.05, 0.04, 0.16), (ex, 0.4, 0.95), "Charcoal")
    d.box((0.05, 0.04, 0.16), (ex, 0.2, 0.95), "Charcoal")
    base = d.obj("~base")
    join([housing, base], "Housing")
    a = Part("Arm")
    # built relative to the hinge: arm along +X
    a.box((0.5, 0.1, 0.16), (-0.2, 0.0, 0.0), "Charcoal")
    a.box((0.28, 0.14, 0.22), (-0.42, 0.0, 0.0), "SteelDark")
    nseg = 8
    L = 4.2
    for i in range(nseg):
        x0 = 0.05 + i * L / nseg
        a.bx(x0, x0 + L / nseg, -0.035, 0.035, -0.055, 0.055, "CarRed" if i % 2 == 0 else "CarWhite")
    a.box((0.06, 0.09, 0.13), (L + 0.08, 0, 0), "Trim")
    for x in (1.5, 3.0):
        a.cyl(0.035, 0.03, (x, 0.05, 0.0), "M_Taillight", axis='Y', seg=6)
        a.cyl(0.035, 0.03, (x, -0.05, 0.0), "M_Taillight", axis='Y', seg=6)
    a.obj("Arm", loc=(px, 0.3, 0.95))
    marker("Lane", (0.0, 0.0, 0.0))


# ================================================================================================
# VFX HELPER MESHES (collection VFX_HelperMeshes) - unit sized, meant to carry a game shader
# ================================================================================================
def _set_uvs(ob, fn):
    me = ob.data
    uvl = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uvl.data[li].uv = fn(co, poly)


@asset("vfx_checkpoint_ring", slot=(22, -6.0, -8.0), family="vfx", category="vfx", collision="none", max_tris=200,
       collection="VFX_HelperMeshes",
       note="open cylinder wall, radius 1, height 1, origin at the base centre. UV: u = around (0..1), v = height (0..1). "
            "Single-sided (outside): scale it in game (e.g. 4 x 6 x 4) and give it an additive fading shader with cull_disabled")
def build_vfx_checkpoint_ring(root):
    p = Part("Ring")
    seg = 24
    for i in range(seg):
        a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        q = [(math.cos(a0), math.sin(a0), 0.0), (math.cos(a1), math.sin(a1), 0.0),
             (math.cos(a1), math.sin(a1), 1.0), (math.cos(a0), math.sin(a0), 1.0)]
        p.poly(q, "NeonCyan")
    ob = p.obj("Ring", recalc=False)

    def uv(co, poly):
        c = poly.center
        base = (math.atan2(c.y, c.x) % (2 * math.pi)) / (2 * math.pi)
        u = (math.atan2(co.y, co.x) % (2 * math.pi)) / (2 * math.pi)
        if u - base > 0.5:
            u -= 1.0
        elif base - u > 0.5:
            u += 1.0
        return (u, co.z)
    _set_uvs(ob, uv)


@asset("vfx_light_cone", slot=(22, 6.0, -8.0), family="vfx", category="vfx", collision="none", max_tris=200,
       collection="VFX_HelperMeshes",
       note="search-light / beacon beam cone: apex at the origin, axis toward +Y in Blender (= -Z in Godot, like SpotLight3D), "
            "length 1, end radius 0.35. UV: u = around, v = 0 at the apex .. 1 at the far end. Single-sided (outside): scale in game, "
            "use an additive unshaded shader with cull_disabled")
def build_vfx_light_cone(root):
    p = Part("Cone")
    seg = 16
    r0, r1 = 0.02, 0.35
    for i in range(seg):
        a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        q = [(r0 * math.cos(a0), 0.0, r0 * math.sin(a0)), (r1 * math.cos(a0), 1.0, r1 * math.sin(a0)),
             (r1 * math.cos(a1), 1.0, r1 * math.sin(a1)), (r0 * math.cos(a1), 0.0, r0 * math.sin(a1))]
        p.poly(q, "HeadlightWhite")
    ob = p.obj("Cone", recalc=False)

    def uv(co, poly):
        c = poly.center
        base = (math.atan2(c.z, c.x) % (2 * math.pi)) / (2 * math.pi)
        u = (math.atan2(co.z, co.x) % (2 * math.pi)) / (2 * math.pi)
        if u - base > 0.5:
            u -= 1.0
        elif base - u > 0.5:
            u += 1.0
        return (u, co.y)
    _set_uvs(ob, uv)


# ### END MISC ###
