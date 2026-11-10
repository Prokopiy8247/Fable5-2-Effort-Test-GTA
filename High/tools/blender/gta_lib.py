"""Shared helpers for the Fable 5.2 GTA Blender asset pipeline.
Executed inside Blender through the blender-gta-high MCP connection (localhost:9879).
Conventions: +Y = front, +X = right, +Z = up (so glTF/Godot gets -Z forward, +X right).
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix, Euler, Quaternion

PROJECT = r"G:\YouTube\Fable 5.2 Effort Test GTA\High"
EXPORT = os.path.join(PROJECT, "gta", "generated", "models")
ROOT = "GTA_GODOT"


# ---------------------------------------------------------------- collections
def coll(path):
    """Get/create nested collection 'Vehicles/Cars' under GTA_GODOT."""
    scene = bpy.context.scene
    root = bpy.data.collections.get(ROOT)
    if root is None:
        root = bpy.data.collections.new(ROOT)
        scene.collection.children.link(root)
    cur = root
    if path:
        for part in path.split("/"):
            nxt = None
            for c in cur.children:
                if c.name == part:
                    nxt = c
            if nxt is None:
                nxt = bpy.data.collections.new(part)
                cur.children.link(nxt)
            cur = nxt
    return cur


def wipe(prefix_or_names, collection=None):
    """Delete the named root objects together with their whole child hierarchy."""
    names = [prefix_or_names] if isinstance(prefix_or_names, str) else prefix_or_names
    dead = []
    for n in names:
        o = bpy.data.objects.get(n)
        if o is not None:
            for h in hierarchy(o):
                if h not in dead:
                    dead.append(h)
    for o in dead:
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data is not None and data.users == 0:
            try:
                if isinstance(data, bpy.types.Mesh):
                    bpy.data.meshes.remove(data)
                elif isinstance(data, bpy.types.Armature):
                    bpy.data.armatures.remove(data)
            except Exception:
                pass


def wipe_collection(path):
    c = coll(path)
    for o in list(c.all_objects):
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data is not None and data.users == 0:
            try:
                if isinstance(data, bpy.types.Mesh):
                    bpy.data.meshes.remove(data)
                elif isinstance(data, bpy.types.Armature):
                    bpy.data.armatures.remove(data)
            except Exception:
                pass


# ---------------------------------------------------------------- materials
def srgb(h):
    """'#rrggbb' -> linear rgba tuple"""
    h = h.lstrip('#')
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def mat(name, color="#808080", rough=0.7, metal=0.0, emit=None, emit_strength=0.0, alpha=1.0, double=False):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    col = srgb(color) if isinstance(color, str) else tuple(color)
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = col
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if emit is not None:
            e = srgb(emit) if isinstance(emit, str) else tuple(emit)
            bsdf.inputs["Emission Color"].default_value = e
            bsdf.inputs["Emission Strength"].default_value = emit_strength
        bsdf.inputs["Alpha"].default_value = alpha
    m.diffuse_color = (col[0], col[1], col[2], alpha)
    m.roughness = rough
    m.metallic = metal
    m.use_backface_culling = not double
    if alpha < 1.0:
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
    return m


# ---------------------------------------------------------------- mesh builder
class MB:
    """Accumulates low-poly geometry with per-face materials and rigid vertex groups."""

    def __init__(self):
        self.v = []
        self.f = []
        self.fm = []
        self.mats = []
        self.vg = []          # per-vertex group name (or None)
        self.cur_group = None
        self.xf = [Matrix.Identity(4)]

    # transforms
    def push(self, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
        M = Matrix.Translation(Vector(loc)) @ Euler(rot, 'XYZ').to_matrix().to_4x4() @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
        self.xf.append(self.xf[-1] @ M)

    def pop(self):
        self.xf.pop()

    def group(self, name):
        self.cur_group = name

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def add(self, verts, faces, m):
        base = len(self.v)
        M = self.xf[-1]
        for p in verts:
            self.v.append(tuple(M @ Vector(p)))
            self.vg.append(self.cur_group)
        if isinstance(m, (list, tuple)):
            for fc, mm in zip(faces, m):
                self.f.append(tuple(base + i for i in fc))
                self.fm.append(self.mi(mm))
        else:
            idx = self.mi(m)
            for fc in faces:
                self.f.append(tuple(base + i for i in fc))
                self.fm.append(idx)

    # primitives
    def box(self, c, s, m, rot=None, top=None, top_off=(0, 0)):
        """Box centred at c with size s. top=(sx,sy) tapers the top face; top_off shifts it."""
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        tx, ty = (top[0] / 2, top[1] / 2) if top else (hx, hy)
        ox, oy = top_off
        vs = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
              (-tx + ox, -ty + oy, hz), (tx + ox, -ty + oy, hz), (tx + ox, ty + oy, hz), (-tx + ox, ty + oy, hz)]
        fs = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        self.push(c, rot or (0, 0, 0))
        self.add(vs, fs, m)
        self.pop()

    def cyl(self, c, r, h, m, axis='Z', seg=12, r2=None, cap_m=None, phase=0.0):
        """Cylinder/cone centred at c along axis."""
        r2 = r if r2 is None else r2
        vs = []
        for i in range(seg):
            a = 2 * math.pi * i / seg + phase
            vs.append((math.cos(a) * r, math.sin(a) * r, -h / 2))
        for i in range(seg):
            a = 2 * math.pi * i / seg + phase
            vs.append((math.cos(a) * r2, math.sin(a) * r2, h / 2))
        fs = []
        ms = []
        for i in range(seg):
            j = (i + 1) % seg
            fs.append((i, j, seg + j, seg + i))
            ms.append(m)
        if r > 1e-5:
            fs.append(tuple(reversed(range(seg))))
            ms.append(cap_m or m)
        if r2 > 1e-5:
            fs.append(tuple(range(seg, 2 * seg)))
            ms.append(cap_m or m)
        rot = {'Z': (0, 0, 0), 'X': (0, math.pi / 2, 0), 'Y': (-math.pi / 2, 0, 0)}[axis]
        self.push(c, rot)
        self.add(vs, fs, ms)
        self.pop()

    def limb(self, p0, p1, r0, r1, m, seg=6, squash=1.0, up=(0, 1, 0)):
        """Tapered prism from p0 to p1 (radius r0->r1). squash scales the cross-section along 'up'."""
        p0 = Vector(p0)
        p1 = Vector(p1)
        d = (p1 - p0)
        L = d.length
        if L < 1e-6:
            return
        d.normalize()
        u = Vector(up)
        if abs(d.dot(u)) > 0.95:
            u = Vector((1, 0, 0))
        a = d.cross(u).normalized()
        b = a.cross(d).normalized()
        vs = []
        for (p, r) in ((p0, r0), (p1, r1)):
            for i in range(seg):
                t = 2 * math.pi * (i + 0.5) / seg
                vs.append(tuple(p + a * math.cos(t) * r + b * math.sin(t) * r * squash))
        fs = []
        for i in range(seg):
            j = (i + 1) % seg
            fs.append((i, j, seg + j, seg + i))
        fs.append(tuple(reversed(range(seg))))
        fs.append(tuple(range(seg, 2 * seg)))
        self.add(vs, fs, m)

    def ball(self, c, r, m, scale=(1, 1, 1), sub=1):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
        vs = [(v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]) for v in bm.verts]
        fs = [tuple(v.index for v in f.verts) for f in bm.faces]
        bm.free()
        self.push(c)
        self.add(vs, fs, m)
        self.pop()

    def poly(self, pts, m):
        self.add(pts, [tuple(range(len(pts)))], m)

    def prism(self, pts2d, depth, m, plane='YZ', c=(0, 0, 0), cap_m=None):
        """Extrude a 2D polygon. plane 'YZ': pts are (y,z) extruded along X (centred).
        plane 'XZ': (x,z) extruded along Y. plane 'XY': (x,y) extruded along Z."""
        n = len(pts2d)
        vs = []
        for s in (-depth / 2, depth / 2):
            for (a, b) in pts2d:
                if plane == 'YZ':
                    vs.append((s, a, b))
                elif plane == 'XZ':
                    vs.append((a, s, b))
                else:
                    vs.append((a, b, s))
        fs = []
        ms = []
        for i in range(n):
            j = (i + 1) % n
            fs.append((i, j, n + j, n + i))
            ms.append(m)
        fs.append(tuple(reversed(range(n))))
        ms.append(cap_m or m)
        fs.append(tuple(range(n, 2 * n)))
        ms.append(cap_m or m)
        self.push(c)
        self.add(vs, fs, ms)
        self.pop()

    def loft(self, rings, mat_fn, cap0=None, cap1=None):
        """rings: list of lists of 3D points (same count, closed loops).
        mat_fn(ring_index, seg_index) -> material name. cap0/cap1: material for end caps."""
        n = len(rings[0])
        vs = []
        for r in rings:
            vs.extend(r)
        fs = []
        ms = []
        for i in range(len(rings) - 1):
            for k in range(n):
                k2 = (k + 1) % n
                fs.append((i * n + k, i * n + k2, (i + 1) * n + k2, (i + 1) * n + k))
                ms.append(mat_fn(i, k))
        if cap0:
            fs.append(tuple(reversed(range(n))))
            ms.append(cap0)
        if cap1:
            b = (len(rings) - 1) * n
            fs.append(tuple(range(b, b + n)))
            ms.append(cap1)
        self.add(vs, fs, ms)

    # build
    def build(self, name, collection, loc=(0, 0, 0), parent=None, smooth=False, weld=True):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.v, [], self.f)
        for mname in self.mats:
            m = bpy.data.materials.get(mname)
            if m is None:
                m = mat(mname)
            me.materials.append(m)
        for poly, mi in zip(me.polygons, self.fm):
            poly.material_index = mi
            poly.use_smooth = smooth
        me.update()
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        me.update()
        ob = bpy.data.objects.new(name, me)
        (collection if not isinstance(collection, str) else coll(collection)).objects.link(ob)
        ob.location = loc
        if parent is not None:
            ob.parent = parent
        groups = sorted(set(g for g in self.vg if g))
        for g in groups:
            vg = ob.vertex_groups.new(name=g)
            vg.add([i for i, n in enumerate(self.vg) if n == g], 1.0, 'REPLACE')
        return ob


def empty(name, collection, loc=(0, 0, 0), parent=None, size=0.2, rot=(0, 0, 0)):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = size
    ob.empty_display_type = 'PLAIN_AXES'
    (collection if not isinstance(collection, str) else coll(collection)).objects.link(ob)
    ob.location = loc
    ob.rotation_euler = rot
    if parent is not None:
        ob.parent = parent
    return ob


def hierarchy(ob):
    out = [ob]
    for c in ob.children:
        out.extend(hierarchy(c))
    return out


def export_glb(root, relpath, skins=False):
    """Export a root object's hierarchy as GLB with the root temporarily at the origin."""
    path = os.path.join(EXPORT, relpath)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    keep_loc = root.location.copy()
    keep_rot = root.rotation_euler.copy()
    root.location = (0, 0, 0)
    root.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    objs = hierarchy(root)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
              export_yup=True, export_extras=True, export_animations=False,
              export_skins=skins, export_cameras=False, export_lights=False)
    import io, contextlib, logging
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            try:
                bpy.ops.export_scene.gltf(loglevel=logging.ERROR, **kw)
            except TypeError:
                bpy.ops.export_scene.gltf(**kw)
    finally:
        root.location = keep_loc
        root.rotation_euler = keep_rot
        for o in objs:
            o.select_set(False)
    return path


def save():
    bpy.ops.wm.save_mainfile()


def tri_count(root):
    n = 0
    for o in hierarchy(root):
        if o.type == 'MESH':
            n += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return n
