# Shared Blender helper library for the Fable 5.2 GTA (Low) asset pipeline.
# Executed inside Blender through the MCP connection (localhost:9877).
# Convention: assets face +Y in Blender (= -Z forward in Godot), Z up, origin on the ground.
import bpy, bmesh, math, os
from mathutils import Vector, Euler

PROJ = os.path.dirname(bpy.data.filepath)
OUT = os.path.join(PROJ, 'gta', 'generated', 'models')
ROOT = 'GTA_GODOT'

# name: (hex sRGB, roughness, metallic, emission)
PAL = {
    'Paint': (0xd8dadd, 0.35, 0.3, 0), 'Paint2': (0x2a2c31, 0.4, 0.3, 0),
    'Glass': (0x18242f, 0.08, 0.4, 0), 'Chrome': (0xc9cdd2, 0.25, 0.9, 0),
    'Dark': (0x1b1c20, 0.7, 0.1, 0), 'Tire': (0x101012, 0.95, 0, 0), 'Rim': (0xb9bdc4, 0.3, 0.85, 0),
    'HeadLight': (0xfff3cf, 0.3, 0, 2.5), 'TailLight': (0xc81616, 0.4, 0, 1.2),
    'Amber': (0xf59a1b, 0.4, 0, 0.6), 'Plate': (0xe9e6da, 0.6, 0, 0), 'Interior': (0x3a332d, 0.9, 0, 0),
    'SirenRed': (0xe0181c, 0.3, 0, 1.5), 'SirenBlue': (0x1c46e8, 0.3, 0, 1.5),
    'White': (0xeeeeea, 0.6, 0, 0), 'Red': (0xc8302a, 0.6, 0, 0), 'Yellow': (0xf2c230, 0.6, 0, 0),
    'Blue': (0x2d5fb4, 0.6, 0, 0), 'Green': (0x3d8f4a, 0.7, 0, 0), 'Orange': (0xe8702a, 0.6, 0, 0),
    'Black': (0x151517, 0.6, 0, 0), 'Grey': (0x7d8087, 0.75, 0, 0), 'LightGrey': (0xb4b6ba, 0.8, 0, 0),
    'Steel': (0x8a9098, 0.4, 0.8, 0), 'GunMetal': (0x33363b, 0.45, 0.7, 0), 'WeaponFinish': (0x2a2c30, 0.45, 0.6, 0),
    'Wood': (0x8a5a34, 0.8, 0, 0), 'WoodDark': (0x5b3b22, 0.85, 0, 0),
    'Concrete': (0xa9a69e, 0.9, 0, 0), 'ConcreteDark': (0x77756f, 0.9, 0, 0), 'Brick': (0xa5553f, 0.9, 0, 0),
    'PlasterCream': (0xe6d6b4, 0.9, 0, 0), 'PlasterBlue': (0x8fb3c9, 0.9, 0, 0), 'PlasterPink': (0xe0a79a, 0.9, 0, 0),
    'PlasterMint': (0xa6d1b5, 0.9, 0, 0), 'PlasterSand': (0xd2b48a, 0.9, 0, 0), 'OfficeBlue': (0x4e6f8f, 0.5, 0.2, 0),
    'OfficeTeal': (0x3f7f82, 0.5, 0.2, 0), 'OfficeGrey': (0x5c626b, 0.5, 0.2, 0), 'Roof': (0x4a4744, 0.9, 0, 0),
    'RoofRed': (0x9a4033, 0.85, 0, 0), 'RoofBlue': (0x3c5068, 0.85, 0, 0), 'Metal': (0x8e959c, 0.5, 0.6, 0),
    'MetalRust': (0x8a5b40, 0.8, 0.3, 0), 'Corrugated': (0x6f8493, 0.6, 0.5, 0), 'CorrugatedGreen': (0x5f7d68, 0.6, 0.5, 0),
    'WinLit': (0x9fc4dd, 0.15, 0.3, 0), 'WinDark': (0x32475a, 0.12, 0.4, 0), 'Door': (0x4a3526, 0.7, 0, 0),
    'AwningRed': (0xc0392b, 0.8, 0, 0), 'AwningGreen': (0x2e8b57, 0.8, 0, 0), 'AwningBlue': (0x2a6fb0, 0.8, 0, 0),
    'AwningYellow': (0xe2a82c, 0.8, 0, 0), 'SignWhite': (0xf6f4ea, 0.5, 0, 0.9), 'SignRed': (0xe8322c, 0.5, 0, 1.2),
    'SignBlue': (0x2f7fe8, 0.5, 0, 1.2), 'SignGreen': (0x35c46a, 0.5, 0, 1.2), 'SignYellow': (0xf6c62c, 0.5, 0, 1.2),
    'SignOrange': (0xf07a22, 0.5, 0, 1.2), 'SignPurple': (0x9a4fe0, 0.5, 0, 1.2),
    'LampGlow': (0xffe2a0, 0.4, 0, 0.3), 'LightRed': (0x5a1512, 0.4, 0, 0), 'LightYellow': (0x5a4a12, 0.4, 0, 0),
    'LightGreen': (0x12471f, 0.4, 0, 0),
    'Skin': (0xd9a47a, 0.8, 0, 0), 'Shirt': (0xd9d9d9, 0.9, 0, 0), 'Pants': (0x3b4a66, 0.9, 0, 0),
    'Shoes': (0x2a2320, 0.8, 0, 0), 'Hair': (0x3a2a1e, 0.9, 0, 0), 'Eye': (0x16161a, 0.4, 0, 0),
    'Leaf': (0x4f9a45, 0.9, 0, 0), 'LeafDark': (0x2f6e3b, 0.9, 0, 0), 'LeafLight': (0x86b84a, 0.9, 0, 0),
    'Trunk': (0x6a4a30, 0.9, 0, 0), 'Rock': (0x86837c, 0.95, 0, 0), 'RockDark': (0x5f5d58, 0.95, 0, 0),
    'Sand': (0xe0cf9c, 0.95, 0, 0), 'Fur': (0x9a6b43, 0.9, 0, 0), 'FurLight': (0xd9c3a0, 0.9, 0, 0),
    'SharkGrey': (0x6c7b88, 0.6, 0, 0), 'FishOrange': (0xf08a2c, 0.6, 0, 0), 'Canvas': (0xe8643c, 0.9, 0, 0),
    'Rubber': (0x222226, 0.9, 0, 0), 'Cash': (0x4fae5c, 0.7, 0, 0.3), 'Health': (0xe84a4a, 0.6, 0, 0.3),
    'ArmorBlue': (0x3a6fd8, 0.6, 0, 0.3),
}


def lin(h):
    return tuple((((h >> s) & 255) / 255.0) ** 2.2 for s in (16, 8, 0))


def M(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    h, rough, metal, emit = PAL[name]
    c = lin(h)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (*c, 1)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if emit:
        b.inputs['Emission Color'].default_value = (*c, 1)
        b.inputs['Emission Strength'].default_value = emit
    m.diffuse_color = (*c, 1)
    return m


def coll(path):
    cur = bpy.data.collections.get(ROOT)
    if not cur:
        cur = bpy.data.collections.new(ROOT)
        bpy.context.scene.collection.children.link(cur)
    for n in path.split('/'):
        if not n:
            continue
        c = next((k for k in cur.children if k.name.split('.')[0] == n), None)
        if not c:
            c = bpy.data.collections.new(n)
            cur.children.link(c)
        cur = c
    return cur


def purge(name):
    o = bpy.data.objects.get(name)
    if not o:
        return
    todo = [o]
    i = 0
    while i < len(todo):
        todo.extend(todo[i].children)
        i += 1
    for x in todo:
        d = x.data
        bpy.data.objects.remove(x, do_unlink=True)
        if d and d.users == 0:
            try:
                (bpy.data.meshes if isinstance(d, bpy.types.Mesh) else bpy.data.armatures).remove(d)
            except Exception:
                pass


def root(name, collection, loc=(0, 0, 0)):
    purge(name)
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.3
    collection.objects.link(e)
    e.location = loc
    return e


def empty(name, parent, loc):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.1
    parent.users_collection[0].objects.link(e)
    e.parent = parent
    e.location = loc
    return e


class B:
    """Accumulates low-poly geometry with material slots (and optional vertex groups)."""

    def __init__(s):
        s.bm = bmesh.new()
        s.mats = []
        s.grp = s.bm.verts.layers.int.new('grp')
        s.groups = []

    def add(s, verts, faces, m, g=None):
        if m not in s.mats:
            s.mats.append(m)
        mi = s.mats.index(m)
        gi = -1
        if g is not None:
            if g not in s.groups:
                s.groups.append(g)
            gi = s.groups.index(g)
        vs = []
        for v in verts:
            bv = s.bm.verts.new(v)
            bv[s.grp] = gi
            vs.append(bv)
        for f in faces:
            try:
                bf = s.bm.faces.new([vs[i] for i in f])
                bf.material_index = mi
            except ValueError:
                pass

    def _xf(s, v, loc, rot):
        mt = Euler([math.radians(a) for a in rot]).to_matrix() if rot else None
        L = Vector(loc)
        return [((mt @ Vector(p)) if mt else Vector(p)) + L for p in v]

    def box(s, size, loc, m, rot=None, taper=(1, 1), shift=(0, 0), g=None):
        sx, sy, sz = [a / 2 for a in size]
        tx, ty = taper
        hx, hy = shift
        v = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
             (-sx * tx + hx, -sy * ty + hy, sz), (sx * tx + hx, -sy * ty + hy, sz),
             (sx * tx + hx, sy * ty + hy, sz), (-sx * tx + hx, sy * ty + hy, sz)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        s.add(s._xf(v, loc, rot), f, m, g)

    def tube(s, p1, p2, r, m, n=8, r2=None, g=None):
        p1, p2 = Vector(p1), Vector(p2)
        d = p2 - p1
        h = d.length
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        r2 = r if r2 is None else r2
        v = []
        for rr, z in ((r, 0), (r2, h)):
            for i in range(n):
                a = 2 * math.pi * i / n
                v.append(q @ Vector((rr * math.cos(a), rr * math.sin(a), z)) + p1)
        f = [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
        f.append(tuple(range(n))[::-1])
        if r2 > 0:
            f.append(tuple(range(n, 2 * n)))
        s.add(v, f, m, g)

    def cyl(s, r, h, loc, m, axis='z', n=12, r2=None, g=None):
        d = {'x': Vector((h / 2, 0, 0)), 'y': Vector((0, h / 2, 0)), 'z': Vector((0, 0, h / 2))}[axis]
        L = Vector(loc)
        s.tube(L - d, L + d, r, m, n, r2, g)

    def prof(s, pts, w, m, x=0.0, nar=None, g=None):
        """Extrude a side profile [(y,z)] across X. nar=(z0,z1,f): width factor 1 at z0 -> f at z1."""
        def wf(z):
            if not nar:
                return 1.0
            z0, z1, f = nar
            t = min(1.0, max(0.0, (z - z0) / (z1 - z0)))
            return 1 + (f - 1) * t
        n = len(pts)
        v = [(x - w / 2 * wf(z), y, z) for y, z in pts] + [(x + w / 2 * wf(z), y, z) for y, z in pts]
        f = [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
        f.append(tuple(range(n))[::-1])
        f.append(tuple(range(n, 2 * n)))
        s.add(v, f, m, g)

    def loft(s, rings, m, g=None):
        """rings: [(y, [(x,z),...])] same point count; capped at both ends."""
        n = len(rings[0][1])
        v = []
        for y, r in rings:
            v += [(x, y, z) for x, z in r]
        f = []
        for k in range(len(rings) - 1):
            a, b = k * n, (k + 1) * n
            f += [(a + i, a + (i + 1) % n, b + (i + 1) % n, b + i) for i in range(n)]
        f.append(tuple(range(n))[::-1])
        f.append(tuple(range((len(rings) - 1) * n, len(rings) * n)))
        s.add(v, f, m, g)

    def obj(s, name, collection, parent=None, loc=(0, 0, 0)):
        bmesh.ops.remove_doubles(s.bm, verts=s.bm.verts, dist=0.00001) if False else None
        bmesh.ops.recalc_face_normals(s.bm, faces=s.bm.faces)
        uv = s.bm.loops.layers.uv.new('UVMap')
        for f in s.bm.faces:
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            a, b = [i for i in range(3) if i != ax]
            for l in f.loops:
                l[uv].uv = (l.vert.co[a] * 0.25, l.vert.co[b] * 0.25)
        gl = [v[s.grp] for v in s.bm.verts]
        me = bpy.data.meshes.new(name)
        s.bm.to_mesh(me)
        s.bm.free()
        for m in s.mats:
            me.materials.append(M(m))
        o = bpy.data.objects.new(name, me)
        collection.objects.link(o)
        o.location = loc
        if parent:
            o.parent = parent
        for gi, gn in enumerate(s.groups):
            vg = o.vertex_groups.new(name=gn)
            vg.add([i for i, x in enumerate(gl) if x == gi], 1.0, 'REPLACE')
        return o


def ell(w, h, zc, n=8, xc=0.0):
    return [(xc + w / 2 * math.cos(2 * math.pi * i / n + math.pi / n), zc + h / 2 * math.sin(2 * math.pi * i / n + math.pi / n)) for i in range(n)]


def export(r, sub):
    path = os.path.join(OUT, sub, r.name + '.glb')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    old = r.location.copy()
    r.location = (0, 0, 0)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)

    def sel(o):
        o.select_set(True)
        for c in o.children:
            sel(c)
    sel(r)
    bpy.context.view_layer.objects.active = r
    import io, contextlib, logging
    logging.disable(logging.WARNING)
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                                  export_yup=True, export_animations=False)
    logging.disable(logging.NOTSET)
    r.location = old
    return path


_slots = {}


def slot(row, step=8.0):
    """Layout position for asset previews inside the .blend: one row per category."""
    i = _slots.get(row, 0)
    _slots[row] = i + 1
    return (12 + i * step, row * 40.0, 0)
