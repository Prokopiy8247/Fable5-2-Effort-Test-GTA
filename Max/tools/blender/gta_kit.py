"""gta_kit - procedural low-poly modelling helpers for the NEON TIDE asset pipeline.

This module is executed INSIDE the user's live Blender through the Blender MCP
(`execute_blender_code`):

    import sys, importlib
    sys.path.append(r"<project>/tools/blender")
    import gta_kit as K; importlib.reload(K)

Conventions (see DEVELOPMENT.md):
  * 1 unit = 1 m, Z up, assets face +Y (which becomes -Z / forward in Godot).
  * Faces are coloured by pointing their UVs at a cell of the shared palette atlas
    (gta/resources/data/palette.json).  `color` arguments are palette names, or
    "@Material" to use one of the special shared materials (Glass, Window, Paint1, ...),
    or "@C<n>" for character region n.
  * Every asset is a root Empty `<asset>` with children named `<asset>__<part>`.
"""
import bpy
import bmesh
import json
import math
import os
from contextlib import contextmanager
from mathutils import Vector, Matrix, Euler

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODELS = os.path.join(PROJECT, "gta", "generated", "models")
PALETTE_JSON = os.path.join(PROJECT, "gta", "resources", "data", "palette.json")
ROOT_COLL = "GTA_GODOT"
CHAR_REGIONS = 16

# category -> (collection path, row Y in the master scene, default spacing)
CATEGORIES = {
    "Characters": ("Characters", 0.0, 2.5),
    "NPCs": ("NPCs", -8.0, 2.5),
    "Animals": ("NPCs/Animals", -16.0, 4.0),
    "Cars": ("Vehicles/Cars", -30.0, 8.0),
    "Motorcycles": ("Vehicles/Motorcycles", -42.0, 5.0),
    "Boats": ("Vehicles/Boats", -56.0, 14.0),
    "Helicopters": ("Vehicles/Helicopters", -76.0, 18.0),
    "Airplanes": ("Vehicles/Airplanes", -100.0, 22.0),
    "Trains": ("Vehicles/Trains", -122.0, 26.0),
    "VehicleParts": ("Vehicles/Parts", -136.0, 4.0),
    "Weapons": ("Weapons", -146.0, 2.0),
    "Buildings": ("Buildings", -165.0, 10.0),
    "Landmarks": ("Buildings/Landmarks", -210.0, 40.0),
    "StreetProps": ("StreetProps", -260.0, 4.0),
    "Interiors": ("Interiors", -275.0, 5.0),
    "Nature": ("Nature", -292.0, 8.0),
    "VFX": ("VFX_HelperMeshes", -310.0, 4.0),
    "Collision": ("CollisionHelpers", -320.0, 6.0),
}

_palette = None


# --------------------------------------------------------------------------- palette
def palette():
    global _palette
    if _palette is None:
        with open(PALETTE_JSON, "r", encoding="utf-8") as f:
            data = json.load(f)
        n = data["size"]
        idx = {}
        for i, e in enumerate(data["colors"]):
            idx[e[0]] = (i, e[1])
        _palette = {"size": n, "index": idx, "colors": data["colors"]}
    return _palette


def reload_palette():
    global _palette
    _palette = None
    ensure_palette_image()


def pal_uv(name):
    p = palette()
    if name not in p["index"]:
        raise KeyError("unknown palette colour: %s" % name)
    i = p["index"][name][0]
    n = p["size"]
    return ((i % n + 0.5) / n, 1.0 - (i // n + 0.5) / n)


def _hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def ensure_palette_image():
    p = palette()
    n = p["size"]
    img = bpy.data.images.get("GTA_Palette")
    if img is None or img.size[0] != n:
        if img is not None:
            bpy.data.images.remove(img)
        img = bpy.data.images.new("GTA_Palette", n, n, alpha=False)
    px = [1.0, 0.0, 1.0, 1.0] * (n * n)
    for i, e in enumerate(p["colors"]):
        r, g, b = _hex(e[1])
        col, row = i % n, i // n
        k = ((n - 1 - row) * n + col) * 4
        px[k:k + 4] = [r, g, b, 1.0]
    img.pixels = px
    path = os.path.join(PROJECT, "tools", "blender", "palette_preview.png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    try:
        img.pack()
    except Exception:
        pass
    return img


def ensure_char_image():
    """16x1 preview strip for the Character material (region colours are set per character in Godot)."""
    defaults = ["#e9b98f", "#3b6fb5", "#3b6fb5", "#e9b98f", "#e9b98f", "#2d3340", "#2d3340", "#1e1e22",
                "#2a2018", "#151515", "#f2f0ea", "#8a5a36", "#c9c9c9", "#d43d33", "#f2c230", "#3fa55a"]
    img = bpy.data.images.get("GTA_CharRegions")
    if img is None:
        img = bpy.data.images.new("GTA_CharRegions", CHAR_REGIONS, 1, alpha=False)
    px = []
    for h in defaults:
        r, g, b = _hex(h)
        px += [r, g, b, 1.0]
    img.pixels = px
    try:
        img.pack()
    except Exception:
        pass
    return img


# --------------------------------------------------------------------------- materials
def _principled(mat):
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    for n in nt.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    return None


def _sock(node, ident):
    for s in node.inputs:
        if s.identifier == ident or s.name == ident:
            return s
    return None


def _set(node, ident, value):
    s = _sock(node, ident)
    if s is not None:
        try:
            s.default_value = value
        except Exception:
            pass


SPECIAL_MATERIALS = {
    # name: (base rgba, metallic, roughness, emission rgb or None, alpha)
    "Window": ((0.07, 0.11, 0.16, 1.0), 0.5, 0.1, None, 1.0),
    "Glass": ((0.30, 0.42, 0.48, 1.0), 0.2, 0.08, None, 0.4),
    "Paint1": ((0.72, 0.09, 0.08, 1.0), 0.35, 0.3, None, 1.0),
    "Paint2": ((0.08, 0.08, 0.09, 1.0), 0.35, 0.3, None, 1.0),
    "LightHead": ((1.0, 0.96, 0.86, 1.0), 0.0, 0.2, (1.0, 0.96, 0.86), 1.0),
    "LightTail": ((0.8, 0.05, 0.04, 1.0), 0.0, 0.2, (1.0, 0.08, 0.05), 1.0),
    "LightReverse": ((0.9, 0.9, 0.9, 1.0), 0.0, 0.2, (0.6, 0.6, 0.6), 1.0),
    "LightIndL": ((1.0, 0.55, 0.08, 1.0), 0.0, 0.2, (1.0, 0.6, 0.08), 1.0),
    "LightIndR": ((1.0, 0.55, 0.08, 1.0), 0.0, 0.2, (1.0, 0.6, 0.08), 1.0),
    "LightSirenA": ((1.0, 0.1, 0.08, 1.0), 0.0, 0.2, (1.0, 0.1, 0.08), 1.0),
    "LightSirenB": ((0.12, 0.3, 1.0, 1.0), 0.0, 0.2, (0.12, 0.3, 1.0), 1.0),
    "LightAux": ((1.0, 0.9, 0.5, 1.0), 0.0, 0.2, (1.0, 0.9, 0.5), 1.0),
    # traffic signal lenses (driven per instance in Godot)
    "SignalR": ((1.0, 0.12, 0.08, 1.0), 0.0, 0.2, (1.0, 0.12, 0.08), 1.0),
    "SignalA": ((1.0, 0.65, 0.08, 1.0), 0.0, 0.2, (1.0, 0.65, 0.08), 1.0),
    "SignalG": ((0.1, 1.0, 0.45, 1.0), 0.0, 0.2, (0.1, 1.0, 0.45), 1.0),
}


def get_material(name):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    m = bpy.data.materials.new(name)
    bsdf = _principled(m)
    nt = m.node_tree
    if name in ("Palette", "Foliage", "PaletteDry"):
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = ensure_palette_image()
        tex.interpolation = "Closest"
        nt.links.new(tex.outputs[0], _sock(bsdf, "Base Color"))
        _set(bsdf, "Roughness", 0.8)
    elif name == "Character":
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = ensure_char_image()
        tex.interpolation = "Closest"
        nt.links.new(tex.outputs[0], _sock(bsdf, "Base Color"))
        _set(bsdf, "Roughness", 0.8)
    elif name in SPECIAL_MATERIALS:
        base, metal, rough, emis, alpha = SPECIAL_MATERIALS[name]
        _set(bsdf, "Base Color", base)
        _set(bsdf, "Metallic", metal)
        _set(bsdf, "Roughness", rough)
        if emis is not None:
            _set(bsdf, "Emission Color", (emis[0], emis[1], emis[2], 1.0))
            _set(bsdf, "Emission Strength", 1.5)
        if alpha < 1.0:
            _set(bsdf, "Alpha", alpha)
            try:
                m.blend_method = "BLEND"
            except Exception:
                pass
            try:
                m.surface_render_method = "BLENDED"
            except Exception:
                pass
        m.diffuse_color = (base[0], base[1], base[2], alpha)
    else:
        raise KeyError("unknown material " + name)
    return m


def resolve(color):
    """-> (material name, uv or None, uv_mode)"""
    if color.startswith("@C"):
        region = int(color[2:])
        return ("Character", ((region + 0.5) / CHAR_REGIONS, 0.5), "flat")
    if color.startswith("@F:"):
        return ("Foliage", pal_uv(color[3:]), "flat")
    if color.startswith("@D:"):
        return ("PaletteDry", pal_uv(color[3:]), "flat")
    if color.startswith("@"):
        name = color[1:]
        return (name, None, "unit")
    return ("Palette", pal_uv(color), "flat")


# --------------------------------------------------------------------------- collections / assets
def ensure_collection(path):
    scene = bpy.context.scene
    parent = bpy.data.collections.get(ROOT_COLL)
    if parent is None:
        parent = bpy.data.collections.new(ROOT_COLL)
        scene.collection.children.link(parent)
    for part in path.split("/"):
        if not part:
            continue
        name = part
        child = None
        for c in parent.children:
            if c.name == name:
                child = c
                break
        if child is None:
            child = bpy.data.collections.get(name)
            if child is None:
                child = bpy.data.collections.new(name)
            if child.name not in [c.name for c in parent.children]:
                parent.children.link(child)
        parent = child
    return parent


def setup_collections():
    for key, (path, _y, _s) in CATEGORIES.items():
        ensure_collection(path)
    return [c.name for c in bpy.data.collections]


def remove_asset(name):
    root = bpy.data.objects.get(name)
    if root is None:
        return None
    loc = root.location.copy()
    objs = [root] + list(root.children_recursive)
    meshes = set()
    for o in objs:
        if o.type == "MESH" and o.data is not None:
            meshes.add(o.data)
        if o.type == "ARMATURE" and o.data is not None:
            meshes.add(o.data)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    for d in meshes:
        if d.users == 0:
            if isinstance(d, bpy.types.Mesh):
                bpy.data.meshes.remove(d)
            elif isinstance(d, bpy.types.Armature):
                bpy.data.armatures.remove(d)
    return loc


def begin_asset(name, category, spacing=None):
    """Create (or recreate in place) the root Empty of an asset. Idempotent."""
    path, row_y, default_spacing = CATEGORIES[category]
    coll = ensure_collection(path)
    old_loc = remove_asset(name)
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.3
    coll.objects.link(root)
    if old_loc is not None:
        root.location = old_loc
    else:
        sp = spacing if spacing is not None else default_spacing
        max_x = None
        for o in coll.objects:
            if o is not root and o.parent is None:
                max_x = o.location.x if max_x is None else max(max_x, o.location.x)
        root.location = (0.0 if max_x is None else max_x + sp, row_y, 0.0)
    root["gta_category"] = category
    return root


def marker(root, name, pos, rot=(0.0, 0.0, 0.0), size=0.12):
    """Named Empty child (seat, muzzle, light, door point...). Becomes a Node3D in Godot."""
    o = bpy.data.objects.new("%s__%s" % (root.name, name), None)
    o.empty_display_type = "ARROWS"
    o.empty_display_size = size
    for c in root.users_collection:
        c.objects.link(o)
    o.parent = root
    o.location = pos
    o.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    return o


# --------------------------------------------------------------------------- mesh builder
def _rot_matrix(rot):
    if rot is None:
        return Matrix.Identity(4)
    return Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()


class MB:
    """Accumulates geometry in a bmesh. One MB == one Blender object."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uvl = self.bm.loops.layers.uv.new("UVMap")
        self.slots = []
        self.stack = [Matrix.Identity(4)]

    # ---- transform stack
    @contextmanager
    def at(self, pos=(0, 0, 0), rot=None, scale=None):
        m = Matrix.Translation(Vector(pos)) @ _rot_matrix(rot)
        if scale is not None:
            if isinstance(scale, (int, float)):
                scale = (scale, scale, scale)
            m = m @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
        self.stack.append(self.stack[-1] @ m)
        try:
            yield self
        finally:
            self.stack.pop()

    @property
    def M(self):
        return self.stack[-1]

    def _flipped(self, m):
        return m.to_3x3().determinant() < 0.0

    # ---- colouring
    def _slot(self, mat):
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat)

    def paint(self, faces, color):
        mat, uv, mode = resolve(color)
        si = self._slot(mat)
        for f in faces:
            if not f.is_valid:
                continue
            f.material_index = si
            if mode == "flat":
                for l in f.loops:
                    l[self.uvl].uv = uv
            else:
                # unit mapping 0..1 for quads (window blinds etc.), simple planar otherwise
                loops = list(f.loops)
                if len(loops) == 4:
                    for l, c in zip(loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
                        l[self.uvl].uv = c
                else:
                    for l in loops:
                        l[self.uvl].uv = (0.5, 0.5)

    @staticmethod
    def _faces_of(verts):
        s = set()
        for v in verts:
            for f in v.link_faces:
                s.add(f)
        return list(s)

    # ---- primitives (built in a temp bmesh, then merged with the current transform)
    def _merge(self, tmp, m):
        """Copy all faces of `tmp` into the main bmesh. Returns [(face, local_normal)]."""
        tmp.normal_update()
        tmp.verts.index_update()
        vmap = {}
        out = []
        flip = self._flipped(m)
        for f in tmp.faces:
            vs = []
            for v in f.verts:
                nv = vmap.get(v.index)
                if nv is None:
                    nv = self.bm.verts.new(m @ v.co)
                    vmap[v.index] = nv
                vs.append(nv)
            if flip:
                vs.reverse()
            try:
                nf = self.bm.faces.new(vs)
            except ValueError:
                continue
            nf.smooth = f.smooth
            out.append((nf, f.normal.copy()))
        tmp.free()
        return out

    def box(self, size, pos=(0, 0, 0), color="gray_mid", rot=None, bevel=0.0, taper=None,
            base=False, colors=None, smooth=False, shear=None):
        """Box centred at pos (or sitting on pos when base=True).
        taper=(tx,ty): scale of the top face. shear=(dx,dy): top face offset in metres.
        colors={'+z': 'name', ...} per-side overrides (axis-aligned faces in box space)."""
        sx, sy, sz = size
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        for v in tmp.verts:
            x, y, z = v.co
            top = z > 0
            x *= sx
            y *= sy
            if top and taper is not None:
                x *= taper[0]
                y *= taper[1]
            if top and shear is not None:
                x += shear[0]
                y += shear[1]
            v.co = Vector((x, y, z * sz + (sz * 0.5 if base else 0.0)))
        if bevel > 0.0:
            bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=bevel, offset_type="OFFSET", segments=1,
                            profile=0.5, affect="EDGES", clamp_overlap=True)
        m = self.M @ Matrix.Translation(Vector(pos)) @ _rot_matrix(rot)
        merged = self._merge(tmp, m)
        faces = [f for f, _n in merged]
        self.paint(faces, color)
        if colors:
            for f, n in merged:
                ax = max(range(3), key=lambda i: abs(n[i]))
                if abs(n[ax]) > 0.95:
                    key = ("+" if n[ax] > 0 else "-") + "xyz"[ax]
                    if key in colors:
                        self.paint([f], colors[key])
        if smooth:
            for f in faces:
                f.smooth = True
        return faces

    def cyl(self, r, h, pos=(0, 0, 0), color="gray_mid", axis="Z", segs=12, r2=None, caps=True,
            rot=None, base=False, smooth=True, cap_color=None):
        """Cylinder / cone frustum along `axis`, centred at pos (base=True: starts at pos)."""
        tmp = bmesh.new()
        bmesh.ops.create_cone(tmp, cap_ends=caps, cap_tris=False, segments=segs,
                              radius1=r, radius2=(r if r2 is None else r2), depth=h)
        am = Matrix.Identity(4)
        if axis == "X":
            am = Matrix.Rotation(math.radians(90.0), 4, "Y")
        elif axis == "Y":
            am = Matrix.Rotation(math.radians(-90.0), 4, "X")
        off = Matrix.Translation(Vector((0, 0, h * 0.5))) if base else Matrix.Identity(4)
        m = self.M @ Matrix.Translation(Vector(pos)) @ _rot_matrix(rot) @ am @ off
        merged = self._merge(tmp, m)
        faces = [f for f, _n in merged]
        self.paint(faces, color)
        for f, n in merged:
            if abs(n.z) > 0.99:
                f.smooth = False
                if cap_color:
                    self.paint([f], cap_color)
            elif smooth:
                f.smooth = True
        return faces

    def sphere(self, r, pos=(0, 0, 0), color="gray_mid", segs=10, rings=6, scale=None, smooth=True, rot=None):
        tmp = bmesh.new()
        bmesh.ops.create_uvsphere(tmp, u_segments=segs, v_segments=rings, radius=r)
        m = self.M @ Matrix.Translation(Vector(pos)) @ _rot_matrix(rot)
        if scale is not None:
            m = m @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
        faces = [f for f, _n in self._merge(tmp, m)]
        self.paint(faces, color)
        if smooth:
            for f in faces:
                f.smooth = True
        return faces

    def ico(self, r, pos=(0, 0, 0), color="gray_mid", subdiv=1, scale=None, smooth=False, rot=None, jitter=0.0, seed=0):
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=subdiv, radius=r)
        if jitter > 0.0:
            import random
            rnd = random.Random(seed)
            for v in tmp.verts:
                v.co *= 1.0 + rnd.uniform(-jitter, jitter)
        m = self.M @ Matrix.Translation(Vector(pos)) @ _rot_matrix(rot)
        if scale is not None:
            m = m @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
        faces = [f for f, _n in self._merge(tmp, m)]
        self.paint(faces, color)
        if smooth:
            for f in faces:
                f.smooth = True
        return faces

    def poly(self, pts, color="gray_mid", flip=False, smooth=False):
        """Single n-gon from 3D points (counter-clockwise seen from the front)."""
        m = self.M
        vs = [self.bm.verts.new(m @ Vector(p)) for p in pts]
        if flip != self._flipped(m):
            vs.reverse()
        f = self.bm.faces.new(vs)
        self.paint([f], color)
        if smooth:
            f.smooth = True
        return f

    def quad(self, a, b, c, d, color="gray_mid", flip=False, double=False):
        f = self.poly([a, b, c, d], color, flip)
        out = [f]
        if double:
            out.append(self.poly([d, c, b, a], color, flip))
        return out

    def prism(self, pts2d, depth, color="gray_mid", plane="YZ", pos=(0, 0, 0), center=True,
              side_colors=None, cap_colors=None, caps=(True, True), smooth_sides=False):
        """Extrude a 2D polygon. plane 'YZ' -> extruded along X, 'XZ' -> along Y, 'XY' -> along Z.
        Returns dict(cap0, cap1, sides[list per edge]). side_colors: list per polygon edge."""
        n = len(pts2d)
        area = 0.0
        for i in range(n):
            a = pts2d[i]
            b = pts2d[(i + 1) % n]
            area += a[0] * b[1] - b[0] * a[1]
        pts = list(pts2d)
        # orig_edge[k] = index of the caller's edge that new edge k corresponds to
        orig_edge = list(range(n))
        if area < 0:
            pts.reverse()
            orig_edge = [(n - 2 - k) % n for k in range(n)]
        d0 = -depth * 0.5 if center else 0.0
        d1 = depth * 0.5 if center else depth

        def to3(p, d):
            if plane == "YZ":
                return Vector((d, p[0], p[1]))
            if plane == "XZ":
                return Vector((p[0], d, p[1]))
            return Vector((p[0], p[1], d))

        m = self.M @ Matrix.Translation(Vector(pos))
        v0 = [self.bm.verts.new(m @ to3(p, d0)) for p in pts]
        v1 = [self.bm.verts.new(m @ to3(p, d1)) for p in pts]
        out = {"cap0": None, "cap1": None, "sides": [None] * n}
        # (X, Z, +Y) is a left-handed frame -> flip winding; mirrored matrices flip again
        flip = self._flipped(m) != (plane == "XZ")
        sides = []
        for i in range(n):
            j = (i + 1) % n
            quad = [v0[i], v0[j], v1[j], v1[i]]
            if flip:
                quad.reverse()
            f = self.bm.faces.new(quad)
            if smooth_sides:
                f.smooth = True
            sides.append(f)
            out["sides"][orig_edge[i]] = f
        self.paint(sides, color)
        if side_colors:
            for src, f in enumerate(out["sides"]):
                if src < len(side_colors) and side_colors[src]:
                    self.paint([f], side_colors[src])
        if caps[0]:
            c0 = list(reversed(v0))
            if flip:
                c0.reverse()
            f0 = self.bm.faces.new(c0)
            self.paint([f0], (cap_colors[0] if cap_colors else color))
            out["cap0"] = f0
        if caps[1]:
            c1 = list(v1)
            if flip:
                c1.reverse()
            f1 = self.bm.faces.new(c1)
            self.paint([f1], (cap_colors[1] if cap_colors else color))
            out["cap1"] = f1
        return out

    def loft(self, rings, color="gray_mid", closed=True, cap_start=True, cap_end=True, smooth=False,
             ring_colors=None, fix_normals=True):
        """Skin between consecutive rings (lists of 3D points, equal length)."""
        m = self.M
        vr = [[self.bm.verts.new(m @ Vector(p)) for p in ring] for ring in rings]
        n = len(vr[0])
        faces = []
        for i in range(len(vr) - 1):
            a, b = vr[i], vr[i + 1]
            last = n if closed else n - 1
            seg = []
            for k in range(last):
                k2 = (k + 1) % n
                try:
                    f = self.bm.faces.new([a[k], a[k2], b[k2], b[k]])
                except ValueError:
                    continue
                seg.append(f)
            self.paint(seg, ring_colors[i] if ring_colors and i < len(ring_colors) and ring_colors[i] else color)
            faces += seg
        caps = []
        if closed and cap_start and n >= 3:
            try:
                f = self.bm.faces.new(list(reversed(vr[0])))
                caps.append(f)
            except ValueError:
                pass
        if closed and cap_end and n >= 3:
            try:
                f = self.bm.faces.new(list(vr[-1]))
                caps.append(f)
            except ValueError:
                pass
        self.paint(caps, color)
        allf = faces + caps
        if fix_normals:
            bmesh.ops.recalc_face_normals(self.bm, faces=allf)
        if smooth:
            for f in faces:
                f.smooth = True
        return allf

    def tube(self, pts, r, color="gray_mid", segs=6, smooth=True, caps=True):
        """Round tube along a polyline (mitre-less: one ring per point, oriented by the bisector)."""
        pts = [Vector(p) for p in pts]
        rings = []
        up_hint = Vector((0, 0, 1))
        for i, p in enumerate(pts):
            if i == 0:
                d = (pts[1] - pts[0])
            elif i == len(pts) - 1:
                d = (pts[-1] - pts[-2])
            else:
                d = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
            d.normalize()
            side = d.cross(up_hint)
            if side.length < 1e-4:
                side = d.cross(Vector((1, 0, 0)))
            side.normalize()
            up = side.cross(d).normalized()
            ring = []
            for k in range(segs):
                a = 2.0 * math.pi * k / segs
                ring.append(p + side * math.cos(a) * r + up * math.sin(a) * r)
            rings.append(ring)
        return self.loft(rings, color, closed=True, cap_start=caps, cap_end=caps, smooth=smooth)

    def ring_xy(self, cx, cy, z, rx, ry, n, rot=0.0):
        """Helper: n-gon ring in the XY plane (for lofts)."""
        out = []
        for k in range(n):
            a = 2.0 * math.pi * k / n + rot
            out.append((cx + math.cos(a) * rx, cy + math.sin(a) * ry, z))
        return out

    # ---- global ops
    def bevel_edges(self, edges, offset, segments=1):
        edges = [e for e in edges if e.is_valid]
        if not edges:
            return {"faces": [], "edges": [], "verts": []}
        return bmesh.ops.bevel(self.bm, geom=edges, offset=offset, offset_type="OFFSET", segments=segments,
                               profile=0.5, affect="EDGES", clamp_overlap=True, material=-1)

    def weld(self, dist=0.0005):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=dist)

    def mirror_x(self):
        """Duplicate everything mirrored across the YZ plane."""
        geom = list(self.bm.verts) + list(self.bm.edges) + list(self.bm.faces)
        ret = bmesh.ops.duplicate(self.bm, geom=geom)
        new_verts = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
        new_faces = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMFace)]
        for v in new_verts:
            v.co.x = -v.co.x
        bmesh.ops.reverse_faces(self.bm, faces=new_faces)
        return new_faces

    def auto_sharp(self, angle_deg=40.0):
        """Smooth-shade everything, keeping edges sharper than angle hard."""
        lim = math.radians(angle_deg)
        self.bm.normal_update()
        for f in self.bm.faces:
            f.smooth = True
        for e in self.bm.edges:
            if len(e.link_faces) == 2:
                try:
                    a = e.calc_face_angle()
                except ValueError:
                    a = 0.0
                e.smooth = a < lim
            else:
                e.smooth = False

    def tri_count(self):
        return sum(max(1, len(f.verts) - 2) for f in self.bm.faces)

    # ---- output
    def to_object(self, root, part, origin=None, weld=False, sharp_angle=None, name=None):
        """Create the Blender object `<root>__<part>` parented to root. origin = pivot in asset space."""
        if weld:
            self.weld()
        if sharp_angle is not None:
            self.auto_sharp(sharp_angle)
        self.bm.normal_update()
        oname = name if name else ("%s__%s" % (root.name, part) if root is not None else part)
        mesh = bpy.data.meshes.new(oname)
        if origin is not None:
            ov = Vector(origin)
            for v in self.bm.verts:
                v.co -= ov
        self.bm.to_mesh(mesh)
        self.bm.free()
        for s in self.slots:
            mesh.materials.append(get_material(s))
        obj = bpy.data.objects.new(oname, mesh)
        if root is not None:
            for c in root.users_collection:
                c.objects.link(obj)
            obj.parent = root
        else:
            bpy.context.scene.collection.objects.link(obj)
        if origin is not None:
            obj.location = origin
        return obj


def add_text(mb, text, size=1.0, depth=0.06, color="neon_pink", pos=(0, 0, 0), rot=None,
             align="CENTER", res=2, spacing=1.0, keep_back=False):
    """Low-poly extruded 3D lettering (Blender's built-in font) merged into `mb`.
    The text stands upright in the XZ plane and is readable from +Y (the asset's front);
    `pos` is the bottom-centre (align CENTER) of the text block, depth extrudes toward +Y."""
    cu = bpy.data.curves.new("gta_tmp_text", "FONT")
    cu.body = text
    cu.size = size
    cu.extrude = depth * 0.5
    cu.resolution_u = res
    cu.align_x = align
    cu.space_character = spacing
    ob = bpy.data.objects.new("gta_tmp_text", cu)
    bpy.context.scene.collection.objects.link(ob)
    try:
        dg = bpy.context.evaluated_depsgraph_get()
        dg.update()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        tmp = bmesh.new()
        tmp.from_mesh(me)
        bpy.data.meshes.remove(me)
    finally:
        bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.curves.remove(cu)
    if not keep_back and depth > 0.0:
        tmp.normal_update()
        back = [f for f in tmp.faces if f.normal.z < -0.5]
        bmesh.ops.delete(tmp, geom=back, context="FACES")
    # text local: reading dir +X, up +Y, normal +Z  ->  reading dir -X, up +Z, normal +Y
    fix = Matrix.Rotation(math.radians(180.0), 4, "Z") @ Matrix.Rotation(math.radians(90.0), 4, "X")
    m = mb.M @ Matrix.Translation(Vector(pos)) @ _rot_matrix(rot) @ fix @ Matrix.Translation(Vector((0, 0, depth * 0.5)))
    faces = [f for f, _n in mb._merge(tmp, m)]
    mb.paint(faces, color)
    return faces


def link_copy(obj, root, part, pos, rot=None, scale=None):
    """Linked duplicate (shares mesh data) - e.g. the 4 wheels of a car."""
    o = bpy.data.objects.new("%s__%s" % (root.name, part), obj.data)
    for c in root.users_collection:
        c.objects.link(o)
    o.parent = root
    o.location = pos
    if rot is not None:
        o.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    if scale is not None:
        o.scale = scale
    return o


def arc(cx, cy, r, a0, a1, n):
    """2D arc points from angle a0 to a1 (degrees), inclusive."""
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        out.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return out


# --------------------------------------------------------------------------- export
def asset_objects(root):
    return [root] + list(root.children_recursive)


def export_asset(root, rel_path, animations=False, extra=None):
    """Export one asset hierarchy as GLB into res://gta/generated/models/<rel_path>.glb"""
    if isinstance(root, str):
        root = bpy.data.objects[root]
    path = os.path.join(MODELS, rel_path.replace("/", os.sep) + ".glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    view_layer = bpy.context.view_layer
    for o in view_layer.objects:
        o.select_set(False)
    objs = asset_objects(root)
    hidden = []
    for o in objs:
        if o.hide_get():
            hidden.append(o)
            o.hide_set(False)
        o.select_set(True)
    view_layer.objects.active = root
    old_loc = root.location.copy()
    root.location = (0.0, 0.0, 0.0)
    view_layer.update()
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
              export_texcoords=True, export_normals=True, export_tangents=False, export_materials="EXPORT",
              export_vertex_color="NONE", export_cameras=False, export_lights=False, export_extras=False,
              export_animations=animations, export_skins=True, export_morph=False)
    if animations:
        kw.update(dict(export_animation_mode="ACTIONS", export_force_sampling=True, export_frame_step=2,
                       export_optimize_animation_size=True, export_anim_single_armature=True,
                       export_reset_pose_bones=True, export_def_bones=False, export_leaf_bone=False,
                       export_optimize_animation_keep_anim_armature=True, export_bake_animation=False))
    if extra:
        kw.update(extra)
    valid = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    kw = {k: v for k, v in kw.items() if k in valid}
    try:
        bpy.ops.export_scene.gltf(**kw)
    finally:
        root.location = old_loc
        for o in hidden:
            o.hide_set(True)
        for o in objs:
            o.select_set(False)
        view_layer.update()
    size = os.path.getsize(path) if os.path.exists(path) else -1
    return path, size


def asset_stats(root):
    if isinstance(root, str):
        root = bpy.data.objects[root]
    bpy.context.view_layer.update()
    tris = 0
    objs = 0
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in asset_objects(root):
        if o.type != "MESH":
            continue
        objs += 1
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
        mw = o.matrix_world
        for v in o.data.vertices:
            w = mw @ v.co
            w = w - root.matrix_world.translation
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return {"objects": objs, "tris": tris, "size": tuple(round(hi[i] - lo[i], 3) for i in range(3)),
            "min": tuple(round(v, 3) for v in lo), "max": tuple(round(v, 3) for v in hi)}


def save_master():
    bpy.ops.wm.save_mainfile()
    return bpy.data.filepath
