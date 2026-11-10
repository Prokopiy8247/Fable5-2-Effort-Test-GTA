# Cinder Bay asset library - executed inside Blender through the MCP connection (localhost:9880).
# Provides collection/material helpers, a bmesh based MeshBuilder and the GLB export routine.
import bpy, bmesh, math, os
from mathutils import Vector, Matrix, Euler

ROOT = "GTA_GODOT"
PROJECT = os.path.dirname(bpy.data.filepath)
EXPORT = os.path.join(PROJECT, "gta", "generated", "models")


def srgb(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexc(h):
    h = h.lstrip('#')
    return tuple(srgb(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def col(path=""):
    scene = bpy.context.scene
    parent = None
    for ch in scene.collection.children:
        if ch.name == ROOT:
            parent = ch
    if parent is None:
        parent = bpy.data.collections.new(ROOT)
        scene.collection.children.link(parent)
    if not path:
        return parent
    for part in path.split('/'):
        c = None
        for ch in parent.children:
            if ch.name == part:
                c = ch
                break
        if c is None:
            c = bpy.data.collections.new(part)
            parent.children.link(c)
        parent = c
    return parent


def _sock(node, ident):
    for s in node.inputs:
        if s.identifier == ident:
            return s
    return None


def mat(name, color="#808080", rough=0.7, metal=0.0, emit=None, estr=1.0, alpha=1.0):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    try:
        if not m.use_nodes:
            m.use_nodes = True
    except Exception:
        pass
    bsdf = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    c = hexc(color) if isinstance(color, str) else tuple(color)
    if bsdf:
        _sock(bsdf, 'Base Color').default_value = (c[0], c[1], c[2], 1.0)
        _sock(bsdf, 'Roughness').default_value = rough
        _sock(bsdf, 'Metallic').default_value = metal
        _sock(bsdf, 'Alpha').default_value = alpha
        if emit is not None:
            e = hexc(emit) if isinstance(emit, str) else tuple(emit)
            s = _sock(bsdf, 'Emission Color')
            if s:
                s.default_value = (e[0], e[1], e[2], 1.0)
            s = _sock(bsdf, 'Emission Strength')
            if s:
                s.default_value = estr
    m.diffuse_color = (c[0], c[1], c[2], alpha)
    m.roughness = rough
    m.metallic = metal
    if alpha < 1.0:
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
    return m


def M(name):
    return bpy.data.materials[name]


def kill(name):
    o = bpy.data.objects.get(name)
    if o is None:
        return
    for c in list(o.children):
        kill(c.name)
    me = o.data if o.type == 'MESH' else None
    arm = o.data if o.type == 'ARMATURE' else None
    bpy.data.objects.remove(o, do_unlink=True)
    if me is not None and me.users == 0:
        bpy.data.meshes.remove(me)
    if arm is not None and arm.users == 0:
        bpy.data.armatures.remove(arm)


def empty(name, coll, loc=(0, 0, 0), parent=None, size=0.25, rot=None):
    kill(name)
    o = bpy.data.objects.new(name, None)
    o.empty_display_size = size
    o.empty_display_type = 'PLAIN_AXES'
    coll.objects.link(o)
    o.location = loc
    if rot:
        o.rotation_euler = rot
    if parent is not None:
        o.parent = parent
    return o


def box_uv(bm, scale=1.0):
    bm.normal_update()
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            co = l.vert.co
            if ax == 0:
                u, v = co.y, co.z
            elif ax == 1:
                u, v = co.x, co.z
            else:
                u, v = co.x, co.y
            l[uv].uv = (u * scale, v * scale)


def newell(pts):
    n = Vector((0, 0, 0))
    for i in range(len(pts)):
        a = pts[i]
        b = pts[(i + 1) % len(pts)]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n


def dedupe(pts, eps=1e-4):
    out = []
    for p in pts:
        p = Vector(p)
        if not out or (out[-1] - p).length > eps:
            out.append(p)
    if len(out) > 1 and (out[0] - out[-1]).length <= eps:
        out.pop()
    return out


def inset_poly(pts, d):
    """Inset a (roughly planar, convex) polygon by distance d. Returns list of Vector or None."""
    pts = [Vector(p) for p in pts]
    n = newell(pts)
    if n.length < 1e-9:
        return None
    n.normalize()
    k = len(pts)
    out = []
    for i in range(k):
        p0 = pts[(i - 1) % k]
        p1 = pts[i]
        p2 = pts[(i + 1) % k]
        e1 = (p1 - p0).normalized()
        e2 = (p2 - p1).normalized()
        n1 = n.cross(e1)
        n2 = n.cross(e2)
        b = n1 + n2
        if b.length < 1e-6:
            return None
        b.normalize()
        c = max(0.25, b.dot(n1))
        out.append(p1 + b * (d / c))
    # sanity: inset polygon must keep orientation and have positive area
    n2 = newell(out)
    if n2.length < 1e-6 or n2.normalized().dot(n) < 0.5:
        return None
    # reject if any point crossed over (edge direction flipped)
    for i in range(k):
        if (out[(i + 1) % k] - out[i]).dot(pts[(i + 1) % k] - pts[i]) <= 0:
            return None
    return out


class MB:
    """bmesh based mesh builder with per-face materials."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def mi(self, m):
        if m is None:
            m = mat("Default")
        if isinstance(m, str):
            m = bpy.data.materials[m]
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _faces_of(self, verts):
        s = set()
        for v in verts:
            for f in v.link_faces:
                s.add(f)
        return list(s)

    def _tag(self, faces, m):
        i = self.mi(m)
        for f in faces:
            f.material_index = i

    @staticmethod
    def _mx(loc, rot):
        mx = Matrix.Translation(Vector(loc))
        if rot is not None:
            mx = mx @ Euler(rot).to_matrix().to_4x4()
        return mx

    def box(self, size, loc=(0, 0, 0), m=None, rot=None, bevel=0.0, taper=None, shear=None):
        """taper=(tx,ty): scale of the +Z face in x/y. shear=(sx,sy): offset of +Z face."""
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = r['verts']
        for v in verts:
            v.co.x *= size[0]
            v.co.y *= size[1]
            v.co.z *= size[2]
            if v.co.z > 0:
                if taper:
                    v.co.x *= taper[0]
                    v.co.y *= taper[1]
                if shear:
                    v.co.x += shear[0]
                    v.co.y += shear[1]
        faces = self._faces_of(verts)
        self._tag(faces, m)
        if bevel > 0:
            edges = list({e for v in verts for e in v.link_edges})
            rb = bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, offset_type='OFFSET',
                                 segments=1, profile=0.5, affect='EDGES')
            self._tag(rb['faces'], m)
            verts = list({v for f in rb['faces'] for v in f.verts} | {v for v in verts if v.is_valid})
        bmesh.ops.transform(self.bm, matrix=self._mx(loc, rot), verts=[v for v in verts if v.is_valid])
        return verts

    def cyl(self, r, depth, loc=(0, 0, 0), axis='Z', segs=12, m=None, r2=None, rot=None, caps=True):
        mx = self._mx(loc, rot)
        if axis == 'X':
            mx = mx @ Euler((0, math.radians(90), 0)).to_matrix().to_4x4()
        elif axis == 'Y':
            mx = mx @ Euler((math.radians(-90), 0, 0)).to_matrix().to_4x4()
        res = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=segs,
                                    radius1=r, radius2=(r if r2 is None else r2), depth=depth, matrix=mx)
        self._tag(self._faces_of(res['verts']), m)
        return res['verts']

    def tube(self, p1, p2, r, m=None, segs=6, r2=None):
        p1 = Vector(p1)
        p2 = Vector(p2)
        d = p2 - p1
        L = d.length
        if L < 1e-6:
            return []
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        mx = Matrix.Translation((p1 + p2) / 2) @ q.to_matrix().to_4x4()
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs,
                                    radius1=r, radius2=(r if r2 is None else r2), depth=L, matrix=mx)
        self._tag(self._faces_of(res['verts']), m)
        return res['verts']

    def sphere(self, r, loc=(0, 0, 0), m=None, segs=8, rings=6, scale=(1, 1, 1), rot=None, ico=0):
        mx = self._mx(loc, rot) @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
        if ico > 0:
            res = bmesh.ops.create_icosphere(self.bm, subdivisions=ico, radius=r, matrix=mx)
        else:
            res = bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings, radius=r, matrix=mx)
        self._tag(self._faces_of(res['verts']), m)
        return res['verts']

    def poly(self, pts, m=None, outward=None):
        pts = dedupe(pts)
        if len(pts) < 3:
            return None
        if outward is not None and newell(pts).dot(Vector(outward)) < 0:
            pts = list(reversed(pts))
        vs = [self.bm.verts.new(p) for p in pts]
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return None
        f.material_index = self.mi(m)
        return f

    def framed(self, pts, m_frame, m_inner, margin, outward=None):
        """Polygon with an inset border: frame gets m_frame, inner face m_inner."""
        pts = dedupe(pts)
        if len(pts) < 3:
            return
        if outward is not None and newell(pts).dot(Vector(outward)) < 0:
            pts = list(reversed(pts))
        inner = inset_poly(pts, margin) if margin > 0 else None
        if inner is None:
            self.poly(pts, m_frame)
            return
        k = len(pts)
        for i in range(k):
            self.poly([pts[i], pts[(i + 1) % k], inner[(i + 1) % k], inner[i]], m_frame)
        self.poly(inner, m_inner)

    def loft(self, sections, m=None, cap_start=True, cap_end=True, closed=True, wrap=False, recalc=True):
        """sections: list of equally sized point lists. m may be a material or fn(i, j)->material."""
        n = len(sections[0])
        rows = [[self.bm.verts.new(Vector(p)) for p in s] for s in sections]
        faces = []
        ni = len(rows)
        irange = range(ni) if wrap else range(ni - 1)
        jrange = range(n) if closed else range(n - 1)
        for i in irange:
            a = rows[i]
            b = rows[(i + 1) % ni]
            for j in jrange:
                j2 = (j + 1) % n
                vs = [a[j], a[j2], b[j2], b[j]]
                try:
                    f = self.bm.faces.new(vs)
                except ValueError:
                    continue
                mm = m(i, j) if callable(m) else m
                f.material_index = self.mi(mm)
                faces.append(f)
        if not wrap and closed:
            mm0 = m(-1, 0) if callable(m) else m
            if cap_start:
                try:
                    f = self.bm.faces.new(list(reversed(rows[0])))
                    f.material_index = self.mi(mm0)
                    faces.append(f)
                except ValueError:
                    pass
            if cap_end:
                try:
                    f = self.bm.faces.new(rows[-1])
                    f.material_index = self.mi(m(ni - 1, 0) if callable(m) else m)
                    faces.append(f)
                except ValueError:
                    pass
        verts = [v for r in rows for v in r]
        bmesh.ops.remove_doubles(self.bm, verts=verts, dist=0.0004)
        faces = [f for f in faces if f.is_valid]
        bmesh.ops.dissolve_degenerate(self.bm, dist=0.0002, edges=list({e for f in faces for e in f.edges}))
        faces = [f for f in faces if f.is_valid]
        if recalc and faces:
            bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        return faces

    def lathe(self, profile, axis='Z', segs=12, m=None, loc=(0, 0, 0), rot=None, arc=360.0, ring=False):
        """profile: list of (axial, radius). m may be material or fn(k)->material for profile segment k."""
        secs = []
        full = abs(arc - 360.0) < 1e-3
        cnt = segs if full else segs + 1
        for i in range(cnt):
            a = math.radians(arc) * i / segs
            ca, sa = math.cos(a), math.sin(a)
            ring = []
            for (h, r) in profile:
                if axis == 'Z':
                    ring.append(Vector((r * ca, r * sa, h)))
                elif axis == 'X':
                    ring.append(Vector((h, r * ca, r * sa)))
                else:
                    ring.append(Vector((r * sa, h, r * ca)))
            secs.append(ring)
        mf = (lambda i, j: m(j)) if callable(m) else m
        faces = self.loft(secs, mf, cap_start=False, cap_end=False, closed=ring, wrap=full, recalc=True)
        vs = list({v for f in faces if f.is_valid for v in f.verts})
        if vs and (rot is not None or Vector(loc).length > 0):
            bmesh.ops.transform(self.bm, matrix=self._mx(loc, rot), verts=vs)
        return faces

    def ellipse_loft(self, stations, segs=10, m=None, axis='Y', cap=True, squareness=0.0):
        """stations: list of (pos, cx, cz, rx, rz) -> lofted tube along axis. m may be fn(i,j)."""
        secs = []
        for (p, cx, cz, rx, rz) in stations:
            ring = []
            for j in range(segs):
                a = 2 * math.pi * j / segs
                ca, sa = math.cos(a), math.sin(a)
                if squareness > 0:
                    e = 1.0 - squareness * 0.5
                    ca = math.copysign(abs(ca) ** e, ca)
                    sa = math.copysign(abs(sa) ** e, sa)
                x = cx + rx * ca
                z = cz + rz * sa
                if axis == 'Y':
                    ring.append(Vector((x, p, z)))
                elif axis == 'Z':
                    ring.append(Vector((x, z, p)))
                else:
                    ring.append(Vector((p, x, z)))
            secs.append(ring)
        return self.loft(secs, m, cap_start=cap, cap_end=cap, closed=True)

    def extrude_poly(self, pts, vec, m=None, m_side=None):
        pts = dedupe(pts)
        vec = Vector(vec)
        a = [Vector(p) for p in pts]
        b = [p + vec for p in a]
        return self.loft([a, b], (lambda i, j: (m if i != 0 else (m_side or m))), closed=True)

    def transform(self, verts, loc=(0, 0, 0), rot=None, scale=None):
        mx = self._mx(loc, rot)
        if scale:
            mx = mx @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
        bmesh.ops.transform(self.bm, matrix=mx, verts=[v for v in verts if v.is_valid])

    def mirror_x(self):
        """Duplicate everything mirrored across X=0."""
        geom = list(self.bm.verts) + list(self.bm.edges) + list(self.bm.faces)
        r = bmesh.ops.duplicate(self.bm, geom=geom)
        nv = [g for g in r['geom'] if isinstance(g, bmesh.types.BMVert)]
        nf = [g for g in r['geom'] if isinstance(g, bmesh.types.BMFace)]
        for v in nv:
            v.co.x = -v.co.x
        bmesh.ops.reverse_faces(self.bm, faces=nf)

    def add_inner_shell(self, m_inner, skip=(), eps=0.006):
        """Duplicate faces flipped (for interiors visible through glass). Skips faces using materials in skip."""
        skip_idx = {self.mi(s) for s in skip}
        faces = [f for f in self.bm.faces if f.material_index not in skip_idx]
        if not faces:
            return
        self.bm.normal_update()
        r = bmesh.ops.duplicate(self.bm, geom=faces)
        nf = [g for g in r['geom'] if isinstance(g, bmesh.types.BMFace)]
        nv = [g for g in r['geom'] if isinstance(g, bmesh.types.BMVert)]
        self.bm.normal_update()
        for v in nv:
            v.co -= v.normal * eps
        bmesh.ops.reverse_faces(self.bm, faces=nf)
        self._tag(nf, m_inner)

    def finish(self, name, coll, smooth=None, loc=(0, 0, 0), parent=None, uv_scale=1.0, origin=None, rot=None):
        bm = self.bm
        bm.normal_update()
        if origin is not None:
            o = Vector(origin)
            for v in bm.verts:
                v.co -= o
            loc = Vector(loc) + o
        if smooth is None:
            for f in bm.faces:
                f.smooth = False
        else:
            ang = math.radians(smooth)
            for f in bm.faces:
                f.smooth = True
            for e in bm.edges:
                if len(e.link_faces) == 2:
                    fa, fb = e.link_faces
                    e.smooth = (e.calc_face_angle(0.0) < ang) and fa.material_index == fb.material_index
                else:
                    e.smooth = False
        box_uv(bm, uv_scale)
        kill(name)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for m in self.mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        coll.objects.link(ob)
        ob.location = loc
        if rot:
            ob.rotation_euler = rot
        if parent is not None:
            ob.parent = parent
        return ob


def tree(o):
    out = [o]
    for c in o.children:
        out.extend(tree(c))
    return out


def export(roots, relpath, anim=False, center=True):
    """Export root objects (with children) as GLB into the Godot project."""
    if not isinstance(roots, (list, tuple)):
        roots = [roots]
    roots = [bpy.data.objects[r] if isinstance(r, str) else r for r in roots]
    objs = []
    for r in roots:
        objs.extend(tree(r))
    vl = bpy.context.view_layer
    for o in vl.objects:
        o.select_set(False)
    hidden = [o for o in objs if o.hide_get()]
    for o in objs:
        o.hide_set(False)
        o.hide_viewport = False
        o.select_set(True)
    saved = [(r, r.location.copy()) for r in roots]
    if center and len(roots) == 1:
        roots[0].location = (0, 0, 0)
    vl.objects.active = objs[0]
    vl.update()
    path = os.path.join(EXPORT, relpath)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    import io, contextlib, logging
    logging.disable(logging.CRITICAL)
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                                      export_yup=True, export_animations=anim, export_skins=True,
                                      export_cameras=False, export_lights=False, export_extras=True,
                                      export_tangents=False, export_materials='EXPORT')
    finally:
        logging.disable(logging.NOTSET)
    for r, l in saved:
        r.location = l
    for o in objs:
        o.select_set(False)
    for o in hidden:
        o.hide_set(True)
    return path


def stats(root):
    root = bpy.data.objects[root] if isinstance(root, str) else root
    tris = 0
    n = 0
    for o in tree(root):
        if o.type == 'MESH':
            n += 1
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
    return "%s: %d meshes, %d tris" % (root.name, n, tris)


def save():
    bpy.ops.wm.save_mainfile()
    return bpy.data.filepath
