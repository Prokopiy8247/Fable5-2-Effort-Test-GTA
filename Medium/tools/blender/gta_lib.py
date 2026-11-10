# Shared Blender helper library for the Fable 5.2 Godot GTA benchmark.
# Executed inside Blender through the Blender MCP connection (localhost:9878):
#   exec(open(<project>/tools/blender/gta_lib.py).read())
# Conventions: Blender Z up, asset "forward" = Blender +Y (-> Godot -Z). Buildings face Blender -Y (-> Godot +Z).
import bpy, bmesh, math, json, os
from mathutils import Vector, Matrix, Euler

PROJECT = os.path.dirname(bpy.data.filepath)
OUT = os.path.join(PROJECT, 'gta', 'generated', 'models')
ROOT = 'GTA_GODOT'
MANIFEST_PATH = os.path.join(OUT, 'manifest.json')
os.makedirs(OUT, exist_ok=True)
try:
    MAN = json.load(open(MANIFEST_PATH))
except Exception:
    MAN = {}


def save_manifest():
    json.dump(MAN, open(MANIFEST_PATH, 'w'), indent=0, sort_keys=True)


def coll(path):
    parent = bpy.context.scene.collection
    for part in [ROOT] + [p for p in path.split('/') if p]:
        c = bpy.data.collections.get(part)
        if c is None:
            c = bpy.data.collections.new(part)
            parent.children.link(c)
        parent = c
    return parent


def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h):
    h = h.lstrip('#')
    return tuple(_lin(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def mat(name, col=None, rough=0.75, metal=0.0, emit=0.0, alpha=1.0):
    m = bpy.data.materials.get(name)
    new = m is None
    if new:
        m = bpy.data.materials.new(name)
        try:
            m.use_nodes = True
        except Exception:
            pass
    if col is not None:
        if isinstance(col, str):
            col = hexcol(col)
        b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        b.inputs['Base Color'].default_value = (col[0], col[1], col[2], 1.0)
        b.inputs['Roughness'].default_value = rough
        b.inputs['Metallic'].default_value = metal
        if emit > 0:
            for k in ('Emission Color', 'Emission'):
                if k in b.inputs:
                    b.inputs[k].default_value = (col[0], col[1], col[2], 1.0)
                    break
            if 'Emission Strength' in b.inputs:
                b.inputs['Emission Strength'].default_value = emit
        if alpha < 1.0:
            b.inputs['Alpha'].default_value = alpha
            try:
                m.blend_method = 'BLEND'
            except Exception:
                pass
        m.diffuse_color = (col[0], col[1], col[2], alpha)
    return m


def wipe(root_name):
    o = bpy.data.objects.get(root_name)
    if o is None:
        return
    for c in list(o.children_recursive) + [o]:
        d = c.data
        bpy.data.objects.remove(c, do_unlink=True)
        if d is not None and d.users == 0:
            if isinstance(d, bpy.types.Mesh):
                bpy.data.meshes.remove(d)
            elif isinstance(d, bpy.types.Armature):
                bpy.data.armatures.remove(d)


def root(name, collection, place=(0, 0, 0)):
    wipe(name)
    o = bpy.data.objects.new(name, None)
    o.empty_display_size = 0.3
    collection.objects.link(o)
    o.location = place
    return o


class B:
    """Small bmesh builder with per-face material names."""

    def __init__(s):
        s.bm = bmesh.new()
        s.mats = []

    def mi(s, m):
        if m not in s.mats:
            s.mats.append(m)
        return s.mats.index(m)

    def _add(s, verts, faces, m, M=None):
        vs = [s.bm.verts.new((M @ Vector(v)) if M is not None else v) for v in verts]
        idx = s.mi(m)
        out = []
        for f in faces:
            try:
                face = s.bm.faces.new([vs[i] for i in f])
                face.material_index = idx
                out.append(face)
            except ValueError:
                pass
        return out

    def box(s, m, c, size, rot=(0, 0, 0), top=(1, 1), shift=(0, 0)):
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        tx, ty = top
        sx, sy = shift
        v = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
             (-hx * tx + sx, -hy * ty + sy, hz), (hx * tx + sx, -hy * ty + sy, hz),
             (hx * tx + sx, hy * ty + sy, hz), (-hx * tx + sx, hy * ty + sy, hz)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        M = Matrix.Translation(c) @ Euler(rot).to_matrix().to_4x4()
        return s._add(v, f, m, M)

    def cyl(s, m, c, r, h, axis='Z', seg=12, r2=None, rot=None, cap=True):
        r2 = r if r2 is None else r2
        v = []
        f = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            v.append((r * math.cos(a), r * math.sin(a), -h / 2))
        for i in range(seg):
            a = 2 * math.pi * i / seg
            v.append((r2 * math.cos(a), r2 * math.sin(a), h / 2))
        for i in range(seg):
            j = (i + 1) % seg
            f.append((i, j, seg + j, seg + i))
        if cap:
            f.append(tuple(reversed(range(seg))))
            f.append(tuple(range(seg, 2 * seg)))
        R = {'Z': Matrix.Identity(4), 'X': Matrix.Rotation(math.pi / 2, 4, 'Y'),
             'Y': Matrix.Rotation(-math.pi / 2, 4, 'X')}[axis]
        if rot is not None:
            R = Euler(rot).to_matrix().to_4x4() @ R
        return s._add(v, f, m, Matrix.Translation(c) @ R)

    def loft(s, m, rings, cap=True):
        n = len(rings[0])
        v = [p for r in rings for p in r]
        f = []
        for k in range(len(rings) - 1):
            for i in range(n):
                j = (i + 1) % n
                f.append((k * n + i, k * n + j, (k + 1) * n + j, (k + 1) * n + i))
        if cap:
            f.append(tuple(reversed(range(n))))
            f.append(tuple(range((len(rings) - 1) * n, len(rings) * n)))
        return s._add(v, f, m)

    def sphere(s, m, c, r, seg=8, rings=5, scale=(1, 1, 1)):
        rr = []
        for k in range(rings + 1):
            t = math.pi * k / rings
            z = math.cos(t) * r
            rad = max(math.sin(t) * r, 0.0005)
            rr.append([(c[0] + math.cos(2 * math.pi * i / seg) * rad * scale[0],
                        c[1] + math.sin(2 * math.pi * i / seg) * rad * scale[1],
                        c[2] + z * scale[2]) for i in range(seg)])
        return s.loft(m, rr, cap=False)

    def poly(s, m, pts, thick, axis='X', c=0.0):
        """Extrude a 2D polygon (list of (a,b)) along an axis, centred at c."""
        n = len(pts)

        def P(a, b, t):
            if axis == 'X':
                return (t, a, b)
            if axis == 'Y':
                return (a, t, b)
            return (a, b, t)
        v = [P(a, b, c - thick / 2) for a, b in pts] + [P(a, b, c + thick / 2) for a, b in pts]
        f = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
        f.append(tuple(reversed(range(n))))
        f.append(tuple(range(n, 2 * n)))
        return s._add(v, f, m)

    def obj(s, name, collection, parent=None, loc=(0, 0, 0), rot=(0, 0, 0), smooth=False, weld=True):
        if weld:
            bmesh.ops.remove_doubles(s.bm, verts=s.bm.verts, dist=0.0001)
        bmesh.ops.recalc_face_normals(s.bm, faces=s.bm.faces)
        uv = s.bm.loops.layers.uv.new('UVMap')
        for f in s.bm.faces:
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            for l in f.loops:
                co = l.vert.co
                l[uv].uv = [(co.y, co.z), (co.x, co.z), (co.x, co.y)][ax]
            f.smooth = smooth
        me = bpy.data.meshes.new(name)
        s.bm.to_mesh(me)
        s.bm.free()
        for m in s.mats:
            me.materials.append(mat(m))
        o = bpy.data.objects.new(name, me)
        collection.objects.link(o)
        o.location = loc
        o.rotation_euler = rot
        o.parent = parent
        return o


def boolean_cut(o, cutter_builder, collection):
    """Subtract geometry of another builder from object o (exact boolean), keeps o."""
    c = cutter_builder.obj(o.name + '_cut', collection)
    md = o.modifiers.new('cut', 'BOOLEAN')
    md.operation = 'DIFFERENCE'
    md.object = c
    try:
        md.solver = 'EXACT'
    except Exception:
        pass
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    old = o.data
    o.modifiers.clear()
    o.data = me
    me.name = old.name
    bpy.data.meshes.remove(old)
    cd = c.data
    bpy.data.objects.remove(c, do_unlink=True)
    bpy.data.meshes.remove(cd)


def text(name, body, size, collection, parent, loc, m, rot=(math.pi / 2, 0, 0), extrude=0.03):
    cu = bpy.data.curves.new(name + '_cu', 'FONT')
    cu.body = body
    cu.size = size
    cu.extrude = extrude
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    cu.resolution_u = 2
    t = bpy.data.objects.new(name + '_tmp', cu)
    collection.objects.link(t)
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    me = bpy.data.meshes.new_from_object(t.evaluated_get(dg))
    me.name = name
    bpy.data.objects.remove(t, do_unlink=True)
    bpy.data.curves.remove(cu)
    me.materials.clear()
    me.materials.append(mat(m))
    o = bpy.data.objects.new(name, me)
    collection.objects.link(o)
    o.location = loc
    o.rotation_euler = rot
    o.parent = parent
    return o


def g(v):
    """Blender position -> Godot position."""
    return [round(v[0], 3), round(v[2], 3), round(-v[1], 3)]


def gs(v):
    return [round(abs(v[0]), 3), round(abs(v[2]), 3), round(abs(v[1]), 3)]


def register(root_name, cols=None, **extra):
    """Record bounds + collision boxes (Blender coords: (cx,cy,cz),(sx,sy,sz)) into the manifest (Godot coords)."""
    r = bpy.data.objects[root_name]
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    inv = r.matrix_world.inverted()
    bpy.context.view_layer.update()
    inv = r.matrix_world.inverted()
    for o in r.children_recursive:
        if o.type != 'MESH' or '_Mod_' in o.name or '_Att_' in o.name:
            continue
        for v in o.data.vertices:
            p = inv @ (o.matrix_world @ v.co)
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    e = {'min': g((lo.x, hi.y, lo.z)), 'max': g((hi.x, lo.y, hi.z))}
    if cols is not None:
        e['col'] = [g(c) + gs(sz) for c, sz in cols]
    e.update(extra)
    MAN[root_name] = e


def export(root_name, subdir):
    r = bpy.data.objects[root_name]
    objs = [r] + list(r.children_recursive)
    saved = r.location.copy()
    r.location = (0, 0, 0)
    bpy.context.view_layer.update()
    for o in bpy.context.scene.objects:
        if o is not None and o.name in bpy.context.view_layer.objects:
            o.select_set(False)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = r
    d = os.path.join(OUT, subdir)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, root_name + '.glb')
    import contextlib, io, logging
    logging.disable(logging.CRITICAL)
    with contextlib.redirect_stdout(io.StringIO()):
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                                  export_apply=True, export_yup=True, export_animations=False)
    logging.disable(logging.NOTSET)
    r.location = saved
    for o in objs:
        o.select_set(False)
    return path


def export_all(names, subdir):
    for n in names:
        export(n, subdir)
    save_manifest()


# ---------- shared palette / materials ----------
def base_materials():
    mat('Paint', '#c8382e', rough=0.35, metal=0.35)
    mat('Paint2', '#22252b', rough=0.4, metal=0.3)
    mat('Glass', '#1c2a36', rough=0.08, metal=0.6)
    mat('Dark', '#17181c', rough=0.8)
    mat('Tire', '#101012', rough=0.95)
    mat('Rim', '#b9bec6', rough=0.3, metal=0.8)
    mat('Chrome', '#d5d9de', rough=0.2, metal=0.9)
    mat('LightHead', '#fff3d0', rough=0.3, emit=1.5)
    mat('LightTail', '#c01a1a', rough=0.3, emit=0.6)
    mat('LightRev', '#e8e8e8', rough=0.3)
    mat('LightBlue', '#2a5cff', rough=0.3, emit=0.8)
    mat('LightRed', '#ff2a2a', rough=0.3, emit=0.8)
    mat('LightAmber', '#ffa020', rough=0.3, emit=0.6)
    mat('Plate', '#e9e4c8', rough=0.6)
    mat('Seat', '#3a3230', rough=0.9)
    mat('White', '#e9e9e4', rough=0.6)
    mat('Black', '#0d0d0f', rough=0.6)
    mat('Steel', '#7d848c', rough=0.45, metal=0.7)
    mat('Gunmetal', '#2b2e33', rough=0.45, metal=0.6)
    mat('Wood', '#7a5233', rough=0.8)
    mat('Polymer', '#1b1c1f', rough=0.7)
    mat('Olive', '#4f5a36', rough=0.8)
    mat('Red', '#c5362c', rough=0.6)
    mat('Yellow', '#e8b81e', rough=0.6)
    mat('Orange', '#e0762a', rough=0.6)
    mat('Blue', '#2f5fa8', rough=0.6)
    mat('Green', '#3f8a4a', rough=0.7)
    mat('Concrete', '#a7a59c', rough=0.9)
    mat('ConcreteDark', '#77766f', rough=0.9)
    mat('Brick', '#a5553f', rough=0.9)
    mat('Window', '#27394a', rough=0.15, metal=0.5)
    mat('Skin', '#d9a47c', rough=0.8)
    mat('Shirt', '#3d6fb3', rough=0.85)
    mat('Sleeve', '#d9a47c', rough=0.85)
    mat('Pants', '#2e3440', rough=0.85)
    mat('Leg', '#2e3440', rough=0.85)
    mat('Shoes', '#1d1b1a', rough=0.8)
    mat('Hair', '#3a2616', rough=0.9)
    mat('Eye', '#111111', rough=0.4)
    mat('Leaf', '#4f9a45', rough=0.9)
    mat('LeafDark', '#356f3a', rough=0.9)
    mat('Bark', '#6a4a32', rough=0.95)
    mat('Rock', '#8b8b86', rough=0.95)
    mat('Sand', '#e2cf9c', rough=0.95)
    mat('Lamp', '#ffe2a8', rough=0.4, emit=1.0)
    mat('SigRed', '#e02a20', rough=0.4, emit=0.4)
    mat('SigYellow', '#f0b820', rough=0.4, emit=0.4)
    mat('SigGreen', '#28c850', rough=0.4, emit=0.4)
    mat('Neon', '#ff4fa0', rough=0.4, emit=1.2)
    mat('NeonCyan', '#38e0e0', rough=0.4, emit=1.2)
    mat('Fur', '#9a7448', rough=0.95)
    mat('FurDark', '#5a4630', rough=0.95)
    mat('Feather', '#e8e8ea', rough=0.9)
    mat('Fish', '#f08a32', rough=0.5)
    mat('Shark', '#6d7d8c', rough=0.6)
    mat('Fabric', '#e85a2a', rough=0.9)


base_materials()
for _p in ('Characters', 'NPCs', 'Vehicles/Cars', 'Vehicles/Motorcycles', 'Vehicles/Boats', 'Vehicles/Helicopters',
           'Vehicles/Airplanes', 'Weapons', 'Buildings', 'StreetProps', 'Interiors', 'Nature', 'VFX_HelperMeshes',
           'CollisionHelpers'):
    coll(_p)
print('gta_lib loaded; project', PROJECT)
