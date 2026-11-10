"""characters.py - Halcyon Bay modular rigged humanoid (builder for characters/humanoid.glb).

Run inside the master .blend through the Blender MCP:

    import sys, importlib
    P = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Ultracode\\tools\\blender"
    for p in (P, P + r"\\assets"):
        if p not in sys.path: sys.path.append(p)
    import gta_bl as G; importlib.reload(G); G.assert_master()
    import characters as C; importlib.reload(C)
    C.build_all()            # armature (if missing) + every part
    C.export()               # -> gta/generated/models/characters/humanoid.glb

Design (see docs/CHARACTERS.md):
  * ONE armature 'Armature' (20 bones, T-pose, facing +Y, 1.80 m) under the root Empty 'humanoid'.
  * The body is made of REPLACEMENT parts (object name = <Slot>_<Id>[_M|_F]); the visible torso+arms
    IS the top, the legs ARE the bottom. Nothing is layered, so nothing z-fights.
  * Limb segments are rigid "ball joint" solids: every child segment starts with a dome centred on
    its joint and the parent segment ends on the joint plane with the same radius, so elbows, knees,
    shoulders and hips stay closed and keep their volume at any angle (no candy-wrapper joints).
    Spine / neck / skirt / apron / long hair use smooth weights.
  * Colours: contract materials M_* are recoloured per instance by the game, P_* are fixed palette.
"""
import bpy
import bmesh
import math
from mathutils import Vector, Matrix, Euler, Quaternion
import gta_bl as G

ROOT = "humanoid"
ARM = "Armature"
COLL = "Characters"
COLL_NPC = "NPCs"
SIDES = ((-1, "_L"), (1, "_R"))

# ------------------------------------------------------------------------------------------------
# skeleton
# ------------------------------------------------------------------------------------------------
SH_X, SH_Z = 0.185, 1.405    # shoulder joint
EL_X = 0.45                  # elbow
WR_X = 0.69                  # wrist
HIP_X, HIP_Z = 0.10, 0.92    # hip joint
KNEE_Z = 0.50
ANK_Z = 0.09

_UP = (0.0, -1.0, 0.0)       # roll hint: bone Z axis -> Blender -Y (= Godot +Z), see docs


def _bone_defs():
    d = [
        ("Root", None, (0, 0, 0), (0, 0, 0.15), _UP),
        ("Hips", "Root", (0, 0, 0.94), (0, 0, 1.06), _UP),
        ("Spine", "Hips", (0, 0, 1.06), (0, 0, 1.22), _UP),
        ("Chest", "Spine", (0, 0, 1.22), (0, 0, 1.455), _UP),
        ("Neck", "Chest", (0, 0, 1.455), (0, 0, 1.53), _UP),
        ("Head", "Neck", (0, 0, 1.53), (0, 0, 1.80), _UP),
    ]
    for s, suf in SIDES:
        d += [
            ("Shoulder" + suf, "Chest", (0.025 * s, 0, SH_Z), (SH_X * s, 0, SH_Z), _UP),
            ("UpperArm" + suf, "Shoulder" + suf, (SH_X * s, 0, SH_Z), (EL_X * s, 0, SH_Z), _UP),
            ("LowerArm" + suf, "UpperArm" + suf, (EL_X * s, 0, SH_Z), (WR_X * s, 0, SH_Z), _UP),
            ("Hand" + suf, "LowerArm" + suf, (WR_X * s, 0, SH_Z), ((WR_X + 0.10) * s, 0, SH_Z), _UP),
        ]
    for s, suf in SIDES:
        d += [
            ("UpperLeg" + suf, "Hips", (HIP_X * s, 0, HIP_Z), (HIP_X * s, 0, KNEE_Z), _UP),
            ("LowerLeg" + suf, "UpperLeg" + suf, (HIP_X * s, 0, KNEE_Z), (HIP_X * s, 0, ANK_Z), _UP),
            ("Foot" + suf, "LowerLeg" + suf, (HIP_X * s, 0, ANK_Z), (HIP_X * s, 0.18, 0.018), (0, 0, -1.0)),
        ]
    return d


BONE_DEFS = _bone_defs()
BONE_NAMES = [b[0] for b in BONE_DEFS]
BIDX = {n: i for i, n in enumerate(BONE_NAMES)}


def ensure_root():
    root = bpy.data.objects.get(ROOT)
    if root is None:
        root = G.asset_root(ROOT, COLL, G.slot("characters", 0), rebuild=False)
    return root


def build_armature(force=False):
    """Create the contract armature (only if missing; bones are never renamed afterwards)."""
    G.object_mode()
    root = ensure_root()
    arm = bpy.data.objects.get(ARM)
    if arm is not None and arm.parent != root:
        raise RuntimeError("an object named 'Armature' exists that is not ours - report to lead")
    if arm is not None and not force:
        return arm
    kids = []
    if arm is not None:
        kids = list(arm.children)
        data = arm.data
        bpy.data.objects.remove(arm, do_unlink=True)
        if data.users == 0:
            bpy.data.armatures.remove(data)
    ad = bpy.data.armatures.new(ARM)
    arm = bpy.data.objects.new(ARM, ad)
    root.users_collection[0].objects.link(arm)
    arm.parent = root
    vl = bpy.context.view_layer
    prev = vl.objects.active
    vl.objects.active = arm
    try:
        bpy.ops.object.mode_set(mode='EDIT')
        ebs = {}
        for name, parent, head, tail, zhint in BONE_DEFS:
            eb = ad.edit_bones.new(name)
            eb.head = Vector(head)
            eb.tail = Vector(tail)
            eb.use_connect = False
            if parent:
                eb.parent = ebs[parent]
            eb.align_roll(Vector(zhint))
            eb.use_deform = True
            ebs[name] = eb
    finally:
        bpy.ops.object.mode_set(mode='OBJECT')
        try:
            vl.objects.active = prev
        except Exception:
            pass
    ad.display_type = 'STICK'
    for k in kids:
        k.parent = arm
        for m in k.modifiers:
            if m.type == 'ARMATURE':
                m.object = arm
    return arm


# ------------------------------------------------------------------------------------------------
# materials
# ------------------------------------------------------------------------------------------------
CONTRACT_MATS = {
    "M_Skin": ("#DDA77B", 0.78),
    "M_Hair": ("#5A3A25", 0.62),
    "M_Top": ("#3F7FC8", 0.82),
    "M_Top_Accent": ("#EFEDE6", 0.82),
    "M_Bottom": ("#3F5F8F", 0.85),
    "M_Shoes": ("#2A2A2E", 0.7),
    "M_Hat": ("#C8443A", 0.8),
    "M_Eyes": ("#2A1C14", 0.35),
    "M_Mouth": ("#9E5246", 0.7),
}


def get_mat(name):
    if name in CONTRACT_MATS:
        hx, rough = CONTRACT_MATS[name]
        return G.mat(name, G.hexc(hx), rough=rough)
    if name.startswith("P_"):
        key = name[2:]
        if key in ("Chrome", "BadgeGold", "Steel"):
            return G.pmat(key, rough=0.4, metal=0.6)
        if key in ("Black", "WindowDark"):
            return G.pmat(key, rough=0.35)
        return G.pmat(key)
    raise KeyError(name)


# ------------------------------------------------------------------------------------------------
# small maths
# ------------------------------------------------------------------------------------------------
def clamp01(t):
    return 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)


def sstep(a, b, x):
    t = clamp01((x - a) / (b - a))
    return t * t * (3.0 - 2.0 * t)


def spow(v, p):
    return math.copysign(abs(v) ** p, v)


def lerp(a, b, t):
    return a + (b - a) * t


def _hash(seed, i):
    v = math.sin(seed * 12.9898 + i * 78.233) * 43758.5453
    return (v - math.floor(v)) * 2.0 - 1.0


def _flat(verts):
    out = []
    for v in verts:
        if isinstance(v, (list, tuple)):
            out.extend(_flat(v))
        else:
            out.append(v)
    return out


def _fn(v):
    return v if callable(v) else (lambda z, _v=v: _v)


# ------------------------------------------------------------------------------------------------
# skin weight profiles (position in the rest pose -> {bone: weight})
# ------------------------------------------------------------------------------------------------
def w_spine(co):
    """Hips / Spine / Chest / Neck / Head by height."""
    z = co[2]
    t1 = sstep(1.00, 1.10, z)
    t2 = sstep(1.17, 1.27, z)
    t3 = sstep(1.44, 1.485, z)
    t4 = sstep(1.515, 1.555, z)
    return {"Hips": 1 - t1, "Spine": t1 * (1 - t2), "Chest": t2 * (1 - t3), "Neck": t3 * (1 - t4), "Head": t4}


def w_torso(co):
    """Torso shell: spine chain + a little clavicle influence around the shoulders."""
    x, z = co[0], co[2]
    u = abs(x)
    suf = "_R" if x >= 0 else "_L"
    w = w_spine(co)
    w.pop("Head", None)
    c = sstep(0.06, 0.17, u) * sstep(1.33, 1.42, z) * 0.6
    if c > 0.0:
        for k in list(w.keys()):
            w[k] *= (1 - c)
        w["Shoulder" + suf] = c
    return w


def w_neck(co):
    z = co[2]
    if z < 1.46:
        return {"Chest": 1.0}
    if z < 1.535:
        return {"Neck": 1.0}
    return {"Head": 1.0}


def w_hair_long(co):
    """Long hair: follows the head; the part hanging below the jaw follows neck/chest partially."""
    z = co[2]
    t = sstep(1.44, 1.56, z)
    return {"Head": 0.35 + 0.65 * t, "Neck": 0.35 * (1 - t), "Chest": 0.30 * (1 - t)}


def w_skirt(co):
    x, z = co[0], co[2]
    suf = "_R" if x >= 0 else "_L"
    t = (1 - sstep(0.66, 0.93, z)) * 0.7 * sstep(0.0, 0.05, abs(x))
    return {"Hips": 1 - t, "UpperLeg" + suf: t}


def w_apron(co):
    x, z = co[0], co[2]
    suf = "_R" if x >= 0 else "_L"
    if z >= 1.0:
        return w_torso(co)
    t = (1 - sstep(0.84, 0.95, z)) * 0.6 * sstep(0.0, 0.05, abs(x))
    return {"Hips": 1 - t, "UpperLeg" + suf: t}


# ------------------------------------------------------------------------------------------------
# part builder
# ------------------------------------------------------------------------------------------------
class Part:
    """One skinned mesh object under the armature."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.dl = self.bm.verts.layers.deform.verify()
        self.mats = []

    # -- materials / skin -------------------------------------------------------------------
    def m(self, mat_name):
        if mat_name not in self.mats:
            self.mats.append(mat_name)
        return self.mats.index(mat_name)

    def skin(self, verts, spec, at=None):
        """spec: bone name (rigid), dict, or callable(co)->weights (per vertex, or once at `at`)."""
        fixed = None
        if isinstance(spec, str):
            fixed = {spec: 1.0}
        elif isinstance(spec, dict):
            fixed = spec
        elif at is not None:
            fixed = spec(Vector(at))
        for v in _flat(verts):
            w = fixed if fixed is not None else spec(v.co)
            items = sorted(((val, b) for b, val in w.items() if val > 0.0), reverse=True)[:4]
            tot = sum(val for val, _ in items)
            items = [(val, b) for val, b in items if val / tot > 0.004]
            tot = sum(val for val, _ in items)          # renormalise after dropping negligible influences
            d = v[self.dl]
            d.clear()
            for val, b in items:
                d[BIDX[b]] = val / tot

    def skin_rest(self, spec):
        """Weight every vertex that has no weights yet."""
        todo = [v for v in self.bm.verts if len(v[self.dl].keys()) == 0]
        if todo:
            self.skin(todo, spec)

    def set_mat(self, verts, fn):
        """Assign materials per face: fn(face_center) -> material name (or None to keep)."""
        faces = set()
        for v in _flat(verts):
            for f in v.link_faces:
                faces.add(f)
        for f in faces:
            mname = fn(f.calc_center_median())
            if mname:
                f.material_index = self.m(mname)

    # -- geometry ---------------------------------------------------------------------------
    def loft(self, sections, mat, bone=None, cap0=True, cap1=True, at=None):
        rings = G.add_loft(self.bm, sections, mat_index=self.m(mat), cap_start=cap0, cap_end=cap1)
        if bone is not None:
            self.skin(rings, bone, at)
        return rings

    def tube(self, origin, axis, ua, ub, stations, mat, bone=None, n=8, off=0.5, p=1.0,
             cap0=True, cap1=True, at=None):
        """Loft along `axis` from `origin`. stations: (t, ra, rb[, shift_a, shift_b]); ra along ua."""
        o, ax, a, b = Vector(origin), Vector(axis), Vector(ua), Vector(ub)
        secs = []
        for st in stations:
            t, ra, rb = st[0], st[1], st[2]
            sa = st[3] if len(st) > 3 else 0.0
            sb = st[4] if len(st) > 4 else 0.0
            c = o + ax * t + a * sa + b * sb
            ring = []
            for k in range(n):
                ang = 2 * math.pi * (k + off) / n
                ring.append(c + a * (ra * spow(math.cos(ang), p)) + b * (rb * spow(math.sin(ang), p)))
            secs.append(ring)
        return self.loft(secs, mat, bone, cap0, cap1, at)

    def path_tube(self, pts, radii, mat, bone=None, n=6, side=(1, 0, 0), flat=1.0, at=None):
        """Tube along a polyline. radii: per point radius; `side` = reference axis of the section;
        flat = thickness ratio perpendicular to `side`."""
        secs = []
        P = [Vector(q) for q in pts]
        for i, pt in enumerate(P):
            if i == 0:
                tan = P[1] - pt
            elif i == len(P) - 1:
                tan = pt - P[i - 1]
            else:
                tan = P[i + 1] - P[i - 1]
            tan.normalize()
            a = Vector(side)
            a = (a - tan * a.dot(tan)).normalized()
            b = tan.cross(a).normalized()
            r = radii[i] if isinstance(radii, (list, tuple)) else radii
            secs.append([pt + a * (r * math.cos(2 * math.pi * (k + 0.5) / n)) + b * (r * flat * math.sin(2 * math.pi * (k + 0.5) / n))
                         for k in range(n)])
        return self.loft(secs, mat, bone, True, True, at)

    def arc_sweep(self, samples, mat, bone=None, n=6, center=(0.0, 0.004), closed=False, at=None):
        """Sweep a small n-gon section around the vertical axis through `center`.
        samples: (angle_deg, radius, z, r_radial, r_vertical); angle 0 = front, + toward +X."""
        secs = []
        for (a_deg, rc, zc, rr, rz) in samples:
            a = math.radians(a_deg)
            dirv = Vector((math.sin(a), math.cos(a), 0.0))
            c = Vector((center[0], center[1], zc)) + dirv * rc
            secs.append([c + dirv * (rr * math.cos(2 * math.pi * (k + 0.5) / n)) + Vector((0, 0, rz * math.sin(2 * math.pi * (k + 0.5) / n)))
                         for k in range(n)])
        if closed:
            secs.append(list(secs[0]))
        return self.loft(secs, mat, bone, not closed, not closed, at)

    def box(self, size, center, mat, bone=None, rot=None, at=None, taper=None):
        vs = G.add_box(self.bm, size, center, rot=rot, mat_index=self.m(mat))
        if taper is not None:
            # taper = (axis index, scale): shrink the +axis face of the box
            ax, sc = taper[0], taper[1]
            sign = taper[2] if len(taper) > 2 else 1
            c = Vector(center)
            R = G._rot_matrix(rot).to_3x3()
            Ri = R.inverted()
            for v in vs:
                l = Ri @ (v.co - c)
                if l[ax] * sign > 0:
                    for j in range(3):
                        if j != ax:
                            l[j] *= sc
                    v.co = c + R @ l
        if bone is not None:
            self.skin(vs, bone, at if at is not None else (center if callable(bone) else None))
        return vs

    def cyl(self, radius, depth, center, mat, bone=None, axis='Z', segments=8, radius2=None, rot=None, at=None):
        vs = G.add_cylinder(self.bm, radius, depth, center, axis=axis, segments=segments,
                            mat_index=self.m(mat), radius2=radius2, rot=rot)
        if bone is not None:
            self.skin(vs, bone, at if at is not None else (center if callable(bone) else None))
        return vs

    def prism(self, profile, lo, hi, axis, mat, bone=None, at=None):
        rings = G.add_prism(self.bm, profile, lo, hi, axis=axis, mat_index=self.m(mat))
        if bone is not None:
            self.skin(rings, bone, at)
        return rings

    def cut(self, co, no, keep_above=True, fill_mat=None):
        """Cut everything built so far with a plane and close the hole."""
        bm = self.bm
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        ret = bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=Vector(co), plane_no=Vector(no).normalized(),
                                     clear_inner=keep_above, clear_outer=not keep_above)
        edges = [e for e in ret['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            r2 = bmesh.ops.edgeloop_fill(bm, edges=edges, mat_nr=0 if fill_mat is None else self.m(fill_mat), use_smooth=False)
            if fill_mat is None:
                for f in r2.get('faces', []):
                    for e2 in f.edges:
                        others = [o for o in e2.link_faces if o is not f]
                        if others:
                            f.material_index = others[0].material_index
                            break

    # -- finish -----------------------------------------------------------------------------
    def finish(self, npc=False, smooth=None):
        arm = bpy.data.objects.get(ARM)
        if arm is None:
            arm = build_armature()
        remove_part(self.name)
        dl = self.dl
        for v in self.bm.verts:
            if len(v[dl].keys()) == 0:
                raise RuntimeError("part %s has unweighted vertices near %r" % (self.name, tuple(round(c, 3) for c in v.co)))
        mats = [get_mat(n) for n in self.mats]
        ob = G.new_object(self.name, self.bm, parent=arm, materials=mats, smooth_angle=smooth)
        if npc:
            G.link(ob, G.col(COLL_NPC))
        for b in BONE_NAMES:
            ob.vertex_groups.new(name=b)
        mod = ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm
        ob.data.calc_loop_triangles()
        return ob


def remove_part(name):
    ob = bpy.data.objects.get(name)
    if ob is None:
        return
    arm = bpy.data.objects.get(ARM)
    if ob.parent != arm:
        raise RuntimeError("object %r exists and is not a humanoid part - not touching it" % name)
    data = ob.data
    bpy.data.objects.remove(ob, do_unlink=True)
    if data is not None and data.users == 0:
        bpy.data.meshes.remove(data)


# ------------------------------------------------------------------------------------------------
# body shape tables
# ------------------------------------------------------------------------------------------------
# rings: (z, half width, depth front, depth back)
BODY = {
    "M": {
        "torso": [(0.955, 0.166, 0.108, 0.110), (1.05, 0.160, 0.106, 0.100), (1.15, 0.168, 0.112, 0.102),
                  (1.25, 0.184, 0.124, 0.108), (1.34, 0.200, 0.130, 0.112), (1.405, 0.210, 0.118, 0.108),
                  (1.455, 0.192, 0.090, 0.092), (1.478, 0.080, 0.064, 0.070)],   # square shoulder shelf: the arm ball sits flush
        "pelvis": [(0.835, 0.160, 0.094, 0.100), (0.89, 0.190, 0.110, 0.118), (0.97, 0.184, 0.108, 0.114),
                   (1.025, 0.166, 0.104, 0.103)],
        "arm": {"delt": 0.061, "up": 0.058, "el": 0.051, "fore": 0.054, "wr": (0.039, 0.032)},
        "leg": {"th": (0.088, 0.096), "mid": (0.080, 0.087), "kn": (0.066, 0.070), "calf": (0.064, 0.071),
                "an": (0.046, 0.050)},
        "neck": 0.052,
    },
    "F": {
        "torso": [(0.955, 0.166, 0.104, 0.110), (1.05, 0.134, 0.090, 0.088), (1.15, 0.140, 0.098, 0.090),
                  (1.25, 0.162, 0.128, 0.097), (1.33, 0.181, 0.130, 0.100), (1.405, 0.196, 0.104, 0.098),
                  (1.455, 0.178, 0.080, 0.083), (1.478, 0.070, 0.058, 0.063)],
        "pelvis": [(0.835, 0.160, 0.092, 0.102), (0.89, 0.196, 0.108, 0.122), (0.97, 0.186, 0.104, 0.116),
                   (1.025, 0.143, 0.092, 0.093)],
        "arm": {"delt": 0.053, "up": 0.048, "el": 0.043, "fore": 0.044, "wr": (0.033, 0.027)},
        "leg": {"th": (0.088, 0.096), "mid": (0.078, 0.085), "kn": (0.061, 0.065), "calf": (0.064, 0.071),
                "an": (0.046, 0.050)},   # calf / ankle identical to M: shoes and boots are shared
        "neck": 0.044,
    },
}
SEC_N = 12
SEC_P = 0.78


def sec(z, hw, df, db, cy=0.0, n=SEC_N, p=SEC_P, off=0.5):
    """Horizontal super-ellipse ring. Angle 0 = front (+Y), increasing toward +X."""
    pts = []
    for k in range(n):
        a = 2 * math.pi * (k + off) / n
        s, c = math.sin(a), math.cos(a)
        pts.append((hw * spow(s, p), cy + (df if c >= 0 else db) * spow(c, p), z))
    return pts


def poly_pt(dims, a_deg):
    """Point (x, y) on the faceted ring of dims=(hw, df, db) at angle a_deg (0 front, + toward +X)."""
    hw, df, db = dims
    step = 360.0 / SEC_N
    k = math.floor((a_deg - step / 2) / step)
    t = (a_deg - (k + 0.5) * step) / step

    def v(kk):
        ang = math.radians((kk + 0.5) * step)
        s, c = math.sin(ang), math.cos(ang)
        return Vector((hw * spow(s, SEC_P), (df if c >= 0 else db) * spow(c, SEC_P)))
    return v(k).lerp(v(k + 1), t)


def poly_y(dims, x, front=True):
    """Y of the faceted ring surface at lateral position x (front or back side)."""
    hw, df, db = dims
    pts = sec(0.0, hw, df, db)
    best = None
    n = len(pts)
    for i in range(n):
        x0, y0, _ = pts[i]
        x1, y1, _ = pts[(i + 1) % n]
        if (x0 - x) * (x1 - x) <= 0 and abs(x1 - x0) > 1e-9:
            t = (x - x0) / (x1 - x0)
            y = y0 + (y1 - y0) * t
            if best is None or (front and y > best) or ((not front) and y < best):
                best = y
    return 0.0 if best is None else best


def prof_at(prof, z, grow=0.0):
    """Interpolated (hw, df, db) of a ring table at height z."""
    if z <= prof[0][0]:
        r = prof[0]
        return (r[1] + grow, r[2] + grow, r[3] + grow)
    for a, b in zip(prof[:-1], prof[1:]):
        if z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0])
            return (lerp(a[1], b[1], t) + grow, lerp(a[2], b[2], t) + grow, lerp(a[3], b[3], t) + grow)
    r = prof[-1]
    return (r[1] + grow, r[2] + grow, r[3] + grow)


def body_prof(body):
    """Bare body ring table (pelvis + torso)."""
    return BODY[body]["pelvis"][:-1] + BODY[body]["torso"][1:]


def front_y(prof, x, z, grow=0.0):
    return poly_y(prof_at(prof, z, grow), x, True)


def back_y(prof, x, z, grow=0.0):
    return poly_y(prof_at(prof, z, grow), x, False)


def ang_of_x(prof, z, x, grow=0.0, back=False):
    """Angle (degrees, strip_a convention) of the faceted garment ring at height z where the
    front (or back) surface has lateral position x."""
    hw = prof_at(prof, z, grow)[0]
    xs = [(a, hw * spow(math.sin(math.radians(a)), SEC_P)) for a in (-75, -45, -15, 15, 45, 75)]
    x = max(xs[0][1], min(xs[-1][1], x))
    a = 0.0
    for (a0, x0), (a1, x1) in zip(xs[:-1], xs[1:]):
        if x0 <= x <= x1:
            a = a0 + (a1 - a0) * (x - x0) / (x1 - x0)
            break
    return 180.0 - a if back else a


def _levels(prof, z0, z1, extra=()):
    zs = [z0, z1] + [r[0] for r in prof if z0 + 0.004 < r[0] < z1 - 0.004] + [z for z in extra if z0 < z < z1]
    return sorted(set(zs))


def strip_x(p, prof, z0, z1, x0, x1, thick=0.006, mat="M_Top", bone=w_torso, back=False, inset=0.006, grow=0.0, at=None):
    """Slab hugging the front (or back) of a garment between heights z0..z1 and lateral x0..x1
    (constants or functions of z). Use for plackets, ties, lapels, pockets, stripes."""
    f0, f1 = _fn(x0), _fn(x1)
    sg = -1.0 if back else 1.0
    secs = []
    for z in _levels(prof, z0, z1):
        a, b = f0(z), f1(z)
        dims = prof_at(prof, z, grow)
        ya, yb = poly_y(dims, a, not back), poly_y(dims, b, not back)
        secs.append([(a, ya - sg * inset, z), (b, yb - sg * inset, z), (b, yb + sg * thick, z), (a, ya + sg * thick, z)])
    return p.loft(secs, mat, bone, at=at)


def strip_a(p, prof, z0, z1, a0, a1, thick=0.008, mat="M_Top", bone=w_torso, inset=0.006, grow=0.0, at=None):
    """Slab wrapping around a garment between angles a0..a1 (degrees, constants or functions of z;
    0 = front, + toward +X, 180 = back). Follows the facets, so it can be wide."""
    f0, f1 = _fn(a0), _fn(a1)
    step = 360.0 / SEC_N
    secs = []
    amin = min(f0(z0), f0(z1))
    amax = max(f1(z0), f1(z1))
    inner_angles = [(k + 0.5) * step for k in range(-SEC_N, 2 * SEC_N) if amin + 1.0 < (k + 0.5) * step < amax - 1.0]
    for z in _levels(prof, z0, z1):
        a_lo, a_hi = f0(z), f1(z)
        angs = [a_lo] + [min(max(a, a_lo), a_hi) for a in inner_angles] + [a_hi]
        din = prof_at(prof, z, grow - inset)
        dout = prof_at(prof, z, grow + thick)
        inner = [poly_pt(din, a) for a in angs]
        outer = [poly_pt(dout, a) for a in angs]
        ring = [(q.x, q.y, z) for q in inner] + [(q.x, q.y, z) for q in reversed(outer)]
        secs.append(ring)
    return p.loft(secs, mat, bone, at=at)


def ring_band(p, prof, z0, z1, grow, mat, bone=w_torso, taper=0.0, at=None):
    """Full band around a garment (closed solid through the body)."""
    secs = []
    zs = _levels(prof, z0, z1)
    for i, z in enumerate(zs):
        g = grow - (taper if i in (0, len(zs) - 1) else 0.0)
        hw, df, db = prof_at(prof, z, g)
        secs.append(sec(z, hw, df, db))
    return p.loft(secs, mat, bone, at=at)


# ------------------------------------------------------------------------------------------------
# generic body pieces
# ------------------------------------------------------------------------------------------------
def add_torso(part, body, mat="M_Top", grow=0.0, tucked=False, hem_z=0.955, hem_extra=0.012, ease=0.012,
              mat_fn=None, shoulder=1.0):
    """Torso shell. Returns the ring table actually used (for strips / bands on top of it)."""
    src = BODY[body]["torso"]
    n_r = len(src)
    prof = []
    for i, (z, hw, df, db) in enumerate(src):
        g = grow if i < n_r - 1 else grow * 0.4
        if i == 0:
            if tucked:
                z = 1.018
                _z, hw, df, db = BODY[body]["pelvis"][-1]
                g = -0.005
            else:
                z = hem_z
                hw, df, db = prof_at(body_prof(body), z)
                g = grow + hem_extra
        elif i == 1 and not tucked:
            g = grow + ease
        if i in (n_r - 3, n_r - 2):
            hw *= shoulder
        prof.append((z, hw + g, df + g, db + g))
    vs = part.loft([sec(*r) for r in prof], mat, w_torso)
    if mat_fn is not None:
        part.set_mat(vs, mat_fn)
    return prof


def arm_stations(body, grow=0.0):
    A = BODY[body]["arm"]
    L1 = EL_X - SH_X
    L2 = WR_X - EL_X
    d, u, e, f = A["delt"] + grow, A["up"] + grow, A["el"] + grow, A["fore"] + grow
    wa, wb = A["wr"][0] + grow, A["wr"][1] + grow
    upper = [(-0.046, d * 0.56, d * 0.56), (-0.020, d * 0.91, d * 0.91), (0.02, d, d), (0.10, u, u), (L1, e, e)]
    fore = [(-0.036, e * 0.62, e * 0.62), (0.0, e, e), (0.075, f, f), (L2, wa, wb)]
    return upper, fore


def _cut(stations, t0, t1):
    """Sub-range of a station list with interpolated end stations."""
    def at(t):
        for a, b in zip(stations[:-1], stations[1:]):
            if a[0] <= t <= b[0]:
                k = (t - a[0]) / (b[0] - a[0]) if b[0] > a[0] else 0.0
                extra = ()
                if len(a) > 3 or len(b) > 3:
                    a3 = a[3] if len(a) > 3 else 0.0
                    b3 = b[3] if len(b) > 3 else 0.0
                    a4 = a[4] if len(a) > 4 else 0.0
                    b4 = b[4] if len(b) > 4 else 0.0
                    extra = (lerp(a3, b3, k), lerp(a4, b4, k))
                return (t, lerp(a[1], b[1], k), lerp(a[2], b[2], k)) + extra
        s = stations[0] if t < stations[0][0] else stations[-1]
        return (t, s[1], s[2]) + tuple(s[3:])
    out = [at(t0)]
    for s in stations:
        if t0 + 1e-6 < s[0] < t1 - 1e-6:
            out.append(s)
    out.append(at(t1))
    return out


def _grow(stations, g):
    return [(s[0], s[1] + g, s[2] + g) + tuple(s[3:]) for s in stations]


def arm_piece(p, body, seg, t0, t1, grow, mat, sides=SIDES):
    """A sleeve band / pad ring on the upper ('upper') or lower ('fore') arm."""
    upper, fore = arm_stations(body)
    for s, suf in sides:
        if seg == "upper":
            p.tube((SH_X * s, 0, SH_Z), (s, 0, 0), (0, 1, 0), (0, 0, 1), _grow(_cut(upper, t0, t1), grow), mat, "UpperArm" + suf)
        else:
            p.tube((EL_X * s, 0, SH_Z), (s, 0, 0), (0, 1, 0), (0, 0, 1), _grow(_cut(fore, t0, t1), grow), mat, "LowerArm" + suf)


def add_arms(part, body, sleeve="short", mat="M_Top", grow=0.008, cuff_mat=None, skin_mat="M_Skin", sleeve_len=0.15):
    """sleeve: 'none' | 'short' | 'long'. The arms are rigid ball-joint segments."""
    upper, fore = arm_stations(body, 0.0)
    L1 = EL_X - SH_X
    L2 = WR_X - EL_X
    for s, suf in SIDES:
        ax = (s, 0, 0)
        ua, ub = (0, 1, 0), (0, 0, 1)
        o1 = (SH_X * s, 0, SH_Z)
        o2 = (EL_X * s, 0, SH_Z)
        if sleeve == "none":
            part.tube(o1, ax, ua, ub, upper, skin_mat, "UpperArm" + suf)
            part.tube(o2, ax, ua, ub, fore, skin_mat, "LowerArm" + suf)
        elif sleeve == "short":
            sl = _grow(_cut(upper, upper[0][0], sleeve_len), grow)
            sl[-1] = (sl[-1][0], sl[-1][1] + 0.004, sl[-1][2] + 0.004)
            part.tube(o1, ax, ua, ub, sl, mat, "UpperArm" + suf)
            if cuff_mat:
                part.tube(o1, ax, ua, ub, _grow(_cut(upper, sleeve_len - 0.024, sleeve_len + 0.004), grow + 0.0075), cuff_mat, "UpperArm" + suf)
            part.tube(o1, ax, ua, ub, _cut(upper, sleeve_len - 0.03, L1), skin_mat, "UpperArm" + suf)
            part.tube(o2, ax, ua, ub, fore, skin_mat, "LowerArm" + suf)
        else:
            part.tube(o1, ax, ua, ub, _grow(upper, grow), mat, "UpperArm" + suf)
            end = L2 - 0.012
            part.tube(o2, ax, ua, ub, _grow(_cut(fore, -0.036, end), grow), mat, "LowerArm" + suf)
            if cuff_mat:
                part.tube(o2, ax, ua, ub, _grow(_cut(fore, end - 0.038, end + 0.004), grow + 0.006), cuff_mat, "LowerArm" + suf)


def leg_stations(body, grow=0.0, straight=0.0):
    Lg = BODY[body]["leg"]
    L1 = HIP_Z - KNEE_Z
    L2 = KNEE_Z - ANK_Z
    th, mid, kn, calf, an = [(a + grow, b + grow) for a, b in (Lg["th"], Lg["mid"], Lg["kn"], Lg["calf"], Lg["an"])]
    if straight > 0.0:
        kn = (lerp(kn[0], mid[0], straight), lerp(kn[1], mid[1], straight))
        calf = (lerp(calf[0], kn[0], straight), lerp(calf[1], kn[1], straight))
        an = (lerp(an[0], kn[0], straight * 0.8), lerp(an[1], kn[1], straight * 0.8))
    upper = [(-0.068, th[0] * 0.62, th[1] * 0.62), (-0.03, th[0] * 0.94, th[1] * 0.94), (0.03, th[0], th[1]),
             (0.21, mid[0], mid[1]), (L1, kn[0], kn[1])]
    lower = [(-0.044, kn[0] * 0.62, kn[1] * 0.62), (0.0, kn[0], kn[1]), (0.11, calf[0], calf[1], 0.0, -0.007),
             (L2, an[0], an[1])]
    return upper, lower


def leg_piece(p, body, seg, t0, t1, grow, mat, straight=0.0, sides=SIDES):
    """A band / cuff ring on the upper ('upper') or lower ('lower') leg."""
    upper, lower = leg_stations(body, 0.0, straight)
    for s, suf in sides:
        if seg == "upper":
            p.tube((HIP_X * s, 0, HIP_Z), (0, 0, -1), (1, 0, 0), (0, 1, 0), _grow(_cut(upper, t0, t1), grow), mat, "UpperLeg" + suf)
        else:
            p.tube((HIP_X * s, 0, KNEE_Z), (0, 0, -1), (1, 0, 0), (0, 1, 0), _grow(_cut(lower, t0, t1), grow), mat, "LowerLeg" + suf)


def add_pelvis(part, body, mat="M_Bottom", grow=0.0):
    prof = [(z, hw + grow, df + grow, db + grow) for (z, hw, df, db) in BODY[body]["pelvis"]]
    part.loft([sec(*r) for r in prof], mat, "Hips")
    return prof


def add_legs(part, body, mat="M_Bottom", grow=0.006, length="long", skin_mat="M_Skin", straight=0.0,
             cuff_z=0.105, short_z=0.57, hem_mat=None):
    """length: 'long' (to the ankle) | 'short' (shorts, skin below) | 'skin' (bare legs, for skirts)."""
    L1 = HIP_Z - KNEE_Z
    for s, suf in SIDES:
        ax = (0, 0, -1)
        ua, ub = (1, 0, 0), (0, 1, 0)
        o1 = (HIP_X * s, 0, HIP_Z)
        o2 = (HIP_X * s, 0, KNEE_Z)
        if length == "long":
            upper, lower = leg_stations(body, grow, straight)
            part.tube(o1, ax, ua, ub, upper, mat, "UpperLeg" + suf)
            end = KNEE_Z - cuff_z
            part.tube(o2, ax, ua, ub, _cut(lower, -0.044, end), mat, "LowerLeg" + suf)
            if hem_mat:
                part.tube(o2, ax, ua, ub, _grow(_cut(lower, end - 0.03, end + 0.003), 0.005), hem_mat, "LowerLeg" + suf)
        elif length == "short":
            upper, _lower = leg_stations(body, grow, straight)
            end = HIP_Z - short_z
            sl = _cut(upper, -0.068, end)
            sl[-1] = (sl[-1][0], sl[-1][1] + 0.006, sl[-1][2] + 0.006)
            part.tube(o1, ax, ua, ub, sl, mat, "UpperLeg" + suf)
            if hem_mat:
                part.tube(o1, ax, ua, ub, _grow(_cut(upper, end - 0.028, end + 0.003), 0.011), hem_mat, "UpperLeg" + suf)
            su, slo = leg_stations(body, 0.0)
            part.tube(o1, ax, ua, ub, _cut(su, end - 0.04, L1), skin_mat, "UpperLeg" + suf)
            part.tube(o2, ax, ua, ub, _cut(slo, -0.044, KNEE_Z - 0.10), skin_mat, "LowerLeg" + suf)
        else:
            su, slo = leg_stations(body, 0.0)
            part.tube(o1, ax, ua, ub, su, skin_mat, "UpperLeg" + suf)
            part.tube(o2, ax, ua, ub, _cut(slo, -0.044, KNEE_Z - 0.10), skin_mat, "LowerLeg" + suf)


def leg_outer_x(body, z, grow=0.0, straight=0.0):
    """Outer |x| of the leg surface at height z (for stripes / pockets)."""
    upper, lower = leg_stations(body, grow, straight)
    if z >= KNEE_Z:
        st = _cut(upper, HIP_Z - z, HIP_Z - z + 1e-4)[0]
    else:
        st = _cut(lower, KNEE_Z - z, KNEE_Z - z + 1e-4)[0]
    return HIP_X + st[1] * math.cos(math.pi / 8)


def side_stripe(p, body, grow, straight, mat, width=0.022, thick=0.006):
    """Trouser side stripe (two rigid slabs per leg)."""
    for s, suf in SIDES:
        for seg, zt, zb in (("UpperLeg", 0.90, KNEE_Z + 0.004), ("LowerLeg", KNEE_Z - 0.004, 0.125)):
            xt = leg_outer_x(body, zt, grow, straight)
            xb = leg_outer_x(body, zb, grow, straight)
            ang = math.atan2(xt - xb, zt - zb)
            L = math.hypot(xt - xb, zt - zb)
            p.box((thick * 2, width, L), (s * ((xt + xb) / 2), 0.0, (zt + zb) / 2), mat, seg + suf, rot=(0, s * ang, 0))


# ------------------------------------------------------------------------------------------------
# head
# ------------------------------------------------------------------------------------------------
# source rings: (z, centre y, half width, front, back) for a 0.262 m head, enlarged below
_HEAD_SRC = {
    "M": [(1.538, 0.030, 0.050, 0.057, 0.036), (1.565, 0.022, 0.082, 0.089, 0.068), (1.600, 0.014, 0.095, 0.102, 0.088),
          (1.640, 0.010, 0.099, 0.106, 0.102), (1.690, 0.008, 0.101, 0.107, 0.110), (1.735, 0.008, 0.099, 0.103, 0.111),
          (1.770, 0.006, 0.086, 0.086, 0.100), (1.792, 0.004, 0.058, 0.056, 0.068), (1.800, 0.002, 0.022, 0.022, 0.026)],
    "F": [(1.545, 0.030, 0.030, 0.044, 0.030), (1.568, 0.022, 0.063, 0.079, 0.060), (1.600, 0.014, 0.085, 0.096, 0.086),
          (1.640, 0.010, 0.094, 0.103, 0.100), (1.690, 0.008, 0.098, 0.105, 0.108), (1.735, 0.008, 0.096, 0.101, 0.109),
          (1.770, 0.006, 0.083, 0.084, 0.098), (1.792, 0.004, 0.056, 0.054, 0.066), (1.800, 0.002, 0.021, 0.021, 0.025)],
}
_HEAD_SC = {"M": (1.088, 1.07), "F": (1.088, 1.065)}   # (vertical, horizontal) enlargement: "slightly large heads"


def HZ(z_src, kind="M"):
    """Map a height of the source head table to the enlarged head."""
    return 1.80 - (1.80 - z_src) * _HEAD_SC[kind][0]


HEAD = {k: [(HZ(z, k), cy * _HEAD_SC[k][1], hw * _HEAD_SC[k][1], yf * _HEAD_SC[k][1], yb * _HEAD_SC[k][1])
            for (z, cy, hw, yf, yb) in rows] for k, rows in _HEAD_SRC.items()}
HEAD_P = 0.86
HEAD_N = 12
EYE_Z = HZ(1.686)
EAR_Z = HZ(1.668)


def head_at(z, kind="M"):
    rings = HEAD[kind]
    if z <= rings[0][0]:
        return rings[0][1:]
    for a, b in zip(rings[:-1], rings[1:]):
        if z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0])
            return tuple(lerp(a[i], b[i], t) for i in range(1, 5))
    return rings[-1][1:]


def head_pt(a, z, off=0.0, kind="M"):
    """Point on the (analytic) skull at angle a (radians, 0 = face, + toward +X) and height z,
    pushed outward by off."""
    cy, hw, yf, yb = head_at(z, kind)
    s, c = math.sin(a), math.cos(a)
    x = (hw + off) * spow(s, HEAD_P)
    y = cy + ((yf if c >= 0 else yb) + off) * spow(c, HEAD_P)
    return Vector((x, y, z))


def face_y(x, z, kind="M"):
    """Y of the face surface at (x, z) and the surface yaw there (rotation about Z for decals)."""
    cy, hw, yf, yb = head_at(z, kind)
    s = clamp01(abs(x) / hw) ** (1.0 / HEAD_P)
    a = math.asin(min(1.0, s))
    y = cy + yf * (math.cos(a) ** HEAD_P)
    dx = 0.004
    s2 = clamp01((abs(x) + dx) / hw) ** (1.0 / HEAD_P)
    y2 = cy + yf * (math.cos(math.asin(min(1.0, s2))) ** HEAD_P)
    yaw = math.atan2(y2 - y, dx)            # negative: the surface falls back toward the side
    return y, (yaw if x >= 0 else -yaw)


def head_ring(z, off=0.0, kind="M", n=HEAD_N):
    return [tuple(head_pt(2 * math.pi * (k + 0.5) / n, z, off, kind)) for k in range(n)]


def shell_ring(z_src, a0_deg, off, lift=0.0, n=12, boost=None, jit=0.0, seed=0.0, kind="M"):
    """Ring of a hair / hat shell around the skull. a0_deg = half-angle of the open front
    (0 = full ring). boost(a_rad, z_src) adds to the offset."""
    z = HZ(z_src, kind)
    a0 = math.radians(a0_deg)
    pts = []
    for i in range(n):
        if a0_deg <= 0.0:
            a = 2 * math.pi * (i + 0.5) / n
        else:
            a = a0 + (2 * math.pi - 2 * a0) * i / (n - 1)
        o = off + (boost(a, z_src) if boost else 0.0)
        if jit:
            o += jit * _hash(seed + z_src * 31.0, i)
        pt = head_pt(a, z, o, kind)
        pt.z += lift
        pts.append(tuple(pt))
    return pts


def ell_arc(z, a0_deg, cy, hw, yb, n=12):
    """Free ring below the skull (long hair): arc around the back, a0 = half-angle of the open front."""
    a0 = math.radians(a0_deg)
    pts = []
    for i in range(n):
        a = a0 + (2 * math.pi - 2 * a0) * i / (n - 1)
        pts.append((hw * spow(math.sin(a), HEAD_P), cy + yb * spow(math.cos(a), HEAD_P), z))
    return pts


def head_poly(a_deg, z, off=0.0, kind="M"):
    """Point on the FACETED head (the 12-gon ring at height z, i.e. the real mesh surface rather
    than the analytic skull) at angle a_deg (0 = face centre, + toward +X), pushed out by off."""
    step = 360.0 / HEAD_N
    k = math.floor((a_deg - step / 2) / step)
    t = (a_deg - (k + 0.5) * step) / step
    p0 = head_pt(math.radians((k + 0.5) * step), z, off, kind)
    p1 = head_pt(math.radians((k + 1.5) * step), z, off, kind)
    return p0.lerp(p1, t)


def _head_ang(x, z, kind="M"):
    """Angle (degrees, >= 0) at which the faceted face has lateral position |x| at height z."""
    cy, hw, yf, yb = head_at(z, kind)
    x = abs(x)
    x15 = hw * (math.sin(math.radians(15.0)) ** HEAD_P)
    x45 = hw * (math.sin(math.radians(45.0)) ** HEAD_P)
    if x <= x15:
        return 15.0 * x / x15
    return 15.0 + 30.0 * min(1.0, (x - x15) / (x45 - x15))


def _face_slab(p, kind, s, xa, xb, zc, h, off, mat, dza=0.0, dzb=0.0, inset=0.004):
    """Slab hugging the faceted face on side s (+1 / -1) between |x| = xa..xb, centred at height zc
    (shifted by dza at xa .. dzb at xb), h tall, standing `off` proud of the surface. It bends with
    the facet creases, so nothing is buried or floating."""
    aa, ab = _head_ang(xa, zc, kind), _head_ang(xb, zc, kind)
    angs = [aa] + [c for c in (15.0, 45.0) if aa + 0.5 < c < ab - 0.5] + [ab]
    secs = []
    for a in angs:
        u = (a - aa) / (ab - aa)
        z = zc + lerp(dza, dzb, u)
        lo, hi = z - h / 2, z + h / 2
        secs.append([tuple(head_poly(s * a, lo, -inset, kind)), tuple(head_poly(s * a, lo, off, kind)),
                     tuple(head_poly(s * a, hi, off, kind)), tuple(head_poly(s * a, hi, -inset, kind))])
    return p.loft(secs, mat, "Head")


def build_head(kind="M"):
    """Head + neck + ears + face. The face is layered so that it has depth in flat shading: eye
    whites lowest, iris, then the upper lid (M: skin, F: dark lash line) and the brows on top, which
    work as a brow ridge and shade the eyes. M: heavier straight brows (inner ends lower), wider
    mouth, chin block. F: larger eyes with lashes, thin arched brows, two-part lips."""
    p = Part("Head_" + kind)
    rings = [head_ring(z, 0.0, kind) for (z, _cy, _hw, _yf, _yb) in HEAD[kind]]
    p.loft(rings, "M_Skin", "Head")
    # neck
    rn = BODY[kind]["neck"]
    p.tube((0, 0.004, 1.415), (0, 0, 1), (1, 0, 0), (0, 1, 0),
           [(0.0, rn + 0.006, rn + 0.006), (0.075, rn, rn), (0.15, rn, rn)], "M_Skin", w_neck)
    female = kind == "F"
    # ears
    ear_z = HZ(1.668, kind)
    for s in (-1, 1):
        cy, hw, yf, yb = head_at(ear_z, kind)
        p.box((0.022, 0.032, 0.060), (s * (hw + 0.004), cy - 0.014, ear_z), "M_Skin", "Head",
              rot=(0, 0, s * -0.35), taper=(2, 0.75))
    # eyes + lids + brows: slabs that follow the facets of the face
    ez = HZ(1.686, kind)
    ex = 0.044 if not female else 0.043
    eh = 0.026 if not female else 0.030
    ew = 0.038 if not female else 0.040
    iw = 0.019 if not female else 0.021
    for s in (-1, 1):
        _face_slab(p, kind, s, ex - ew / 2, ex + ew / 2, ez, eh, 0.0015, "P_White")
        _face_slab(p, kind, s, ex - 0.001 - iw / 2, ex - 0.001 + iw / 2, ez - 0.001, eh - 0.002, 0.0032, "M_Eyes")
        if female:
            # lash line, longer on the outside
            _face_slab(p, kind, s, ex - ew / 2 - 0.002, ex + ew / 2 + 0.006, ez + eh / 2 + 0.0010, 0.0048, 0.0050, "M_Eyes", dzb=0.0015)
            _face_slab(p, kind, s, ex - 0.022, ex + 0.024, ez + 0.0350, 0.0060, 0.0040, "M_Hair", dza=-0.0020, dzb=0.0015)
        else:
            # upper lid (relaxed eyes instead of a stare) and a heavy brow, inner end a little lower
            _face_slab(p, kind, s, ex - ew / 2 - 0.003, ex + ew / 2 + 0.003, ez + eh / 2, 0.0060, 0.0052, "M_Skin")
            _face_slab(p, kind, s, ex - 0.025, ex + 0.027, ez + 0.0305, 0.0105, 0.0075, "M_Hair", dza=-0.0020, dzb=0.0015)
    # nose: wedge with a wider base
    nz = HZ(1.648, kind)
    ny = head_poly(0.0, nz, 0.0, kind).y
    nw = 0.032 if not female else 0.024
    pr = 0.028 if not female else 0.021
    G.add_loft(p.bm, [[(-nw / 2, ny - 0.004, nz - 0.022), (nw / 2, ny - 0.004, nz - 0.022), (nw * 0.26, ny - 0.004, nz + 0.040), (-nw * 0.26, ny - 0.004, nz + 0.040)],
                      [(-nw * 0.38, ny + pr, nz - 0.016), (nw * 0.38, ny + pr, nz - 0.016), (nw * 0.2, ny + pr * 0.42, nz + 0.030), (-nw * 0.2, ny + pr * 0.42, nz + 0.030)]],
               mat_index=p.m("M_Skin"))
    # mouth (flat on the front facet)
    mz = HZ(1.598, kind)
    my = head_poly(0.0, mz, 0.0, kind).y
    if female:
        p.box((0.038, 0.012, 0.0115), (0, my - 0.0035, mz), "M_Mouth", "Head")
        p.box((0.024, 0.012, 0.0065), (0, my - 0.0025, mz + 0.0065), "M_Mouth", "Head")
    else:
        p.box((0.050, 0.012, 0.0085), (0, my - 0.0040, mz), "M_Mouth", "Head")
    p.skin_rest("Head")
    return p.finish()


# ------------------------------------------------------------------------------------------------
# hair
# ------------------------------------------------------------------------------------------------
# The hat rim plane: everything of a hair style above it is removed for the "<Hair>_Hat" variant and
# every hat covers the skull above it.
HAT_A = Vector((0.0, 0.119, HZ(1.742)))      # forehead point
HAT_B = Vector((0.0, -0.104, HZ(1.665)))     # back-of-head point
HAT_TILT = math.atan2(HAT_A.z - HAT_B.z, HAT_A.y - HAT_B.y)
HAT_N = Vector((0.0, -math.sin(HAT_TILT), math.cos(HAT_TILT)))
HAT_O = (HAT_A + HAT_B) / 2


def hat_frame(drop=0.0):
    """Matrix of the tilted hat frame (origin on the rim plane, local Y to the front, Z = plane normal)."""
    return Matrix.Translation(HAT_O - HAT_N * drop) @ Matrix.Rotation(HAT_TILT, 4, 'X')


def _hair_shell(p, levels, boost=None, jit=0.0, seed=1.0, n=12, bone="Head"):
    secs = []
    for lv in levels:
        if lv[0] == "abs":
            _t, z, a0, cy, hw, yb = lv
            secs.append(ell_arc(z, a0, cy, hw, yb, n))
        else:
            z_src, a0, off = lv[0], lv[1], lv[2]
            lift = lv[3] if len(lv) > 3 else 0.0
            secs.append(shell_ring(z_src, a0, off, lift, n, boost, jit, seed))
    return p.loft(secs, "M_Hair", bone)


HAIR_STYLES = ("Short", "Buzz", "Long", "Ponytail", "Curly", "Slick", "Bob", "Mohawk", "Bun")


def _sideburns(p, length):
    z1 = HZ(1.712)
    for s in (-1, 1):
        cy, hw, yf, yb = head_at(z1 - length / 2)
        p.box((0.010, 0.024, length), (s * (hw - 0.001), cy + 0.016, z1 - length / 2 + 0.004), "M_Hair", "Head", taper=(2, 1.5))


def _fringe(p, a0, a1, steps, z_lo, z_hi, off, lift=0.0):
    """Hair slab across the forehead between the angles a0..a1 (degrees, 0 = face centre).
    z_lo / z_hi / off: constants or functions of u (0..1 along the sweep) = lower edge and upper
    edge (SOURCE head heights) and thickness. The top is tucked under the hair shell."""
    f_lo, f_hi, f_off = _fn(z_lo), _fn(z_hi), _fn(off)
    secs = []
    for i in range(steps + 1):
        u = i / steps
        a = math.radians(lerp(a0, a1, u))
        zl, zh, o = f_lo(u), f_hi(u), f_off(u)

        def pt(z_src, oo, dz=0.0):
            q = head_pt(a, HZ(z_src), oo)
            q.z += dz
            return tuple(q)
        secs.append([pt(zl, 0.000), pt(zl, o), pt(zh, o + 0.003, lift), pt(zh, 0.004, lift)])
    return p.loft(secs, "M_Hair", "Head")


def _cap_levels(off=1.0):
    """Close-fitting pulled-back hair (ponytail / bun base)."""
    return [(1.612, 130, 0.008 * off), (1.645, 120, 0.012 * off), (1.680, 113, 0.013 * off), (1.710, 97, 0.014 * off),
            (1.748, 68, 0.015 * off, 0.002), (1.770, 38, 0.017 * off, 0.006), (1.787, 0, 0.017 * off, 0.011),
            (1.798, 0, 0.009 * off, 0.018)]


def _hair_geometry(p, style, hat=False):
    if style == "Short":
        # textured crop with a side-swept fringe (lower and thicker on the character's right)
        def boost(a, z):
            front = max(0.0, math.cos(a)) ** 2
            return 0.016 * front * sstep(1.74, 1.79, z)
        _hair_shell(p, [(1.606, 130, 0.010), (1.640, 120, 0.014), (1.675, 113, 0.016), (1.708, 97, 0.018),
                        (1.745, 68, 0.021, 0.003), (1.768, 38, 0.024, 0.010), (1.786, 0, 0.024, 0.017),
                        (1.798, 0, 0.012, 0.027)], boost)
        _fringe(p, -66, 66, 6, (lambda u: lerp(1.756, 1.726, u)), 1.778, (lambda u: lerp(0.015, 0.030, u)), lift=0.012)
        _sideburns(p, 0.048)
    elif style == "Buzz":
        _hair_shell(p, [(1.612, 130, 0.004), (1.645, 120, 0.006), (1.680, 113, 0.007), (1.710, 97, 0.007),
                        (1.748, 70, 0.007, 0.001), (1.770, 42, 0.007, 0.003), (1.787, 0, 0.007, 0.005),
                        (1.798, 0, 0.004, 0.007)])
    elif style == "Slick":
        # pompadour: high hairline, volume rising at the front and swept to the back
        def boost(a, z):
            back = max(0.0, -math.cos(a)) ** 2
            front = max(0.0, math.cos(a)) ** 2
            return (0.020 * back * sstep(1.69, 1.75, z) * (1 - sstep(1.775, 1.80, z))
                    + 0.026 * front * sstep(1.755, 1.785, z) * (1 - 0.55 * sstep(1.790, 1.80, z)))
        _hair_shell(p, [(1.590, 132, 0.011), (1.630, 121, 0.015), (1.675, 113, 0.015), (1.708, 100, 0.015),
                        (1.745, 76, 0.018, 0.004), (1.768, 50, 0.026, 0.013), (1.786, 0, 0.027, 0.023),
                        (1.798, 0, 0.014, 0.034)], boost)
        _sideburns(p, 0.062)
    elif style == "Curly":
        _hair_shell(p, [(1.600, 122, 0.022), (1.640, 108, 0.044), (1.685, 95, 0.054), (1.725, 78, 0.058, 0.006),
                        (1.758, 54, 0.058, 0.022), (1.782, 0, 0.052, 0.042), (1.797, 0, 0.024, 0.062)],
                    jit=0.009, seed=3.0, n=13)
    elif style == "Long":
        # over the ears (they stay covered), curtain fringe from a centre parting
        _hair_shell(p, [("abs", 1.385, 112, -0.022, 0.112, 0.104), ("abs", 1.46, 106, -0.014, 0.124, 0.116),
                        ("abs", 1.535, 99, -0.004, 0.126, 0.126), (1.606, 88, 0.025), (1.640, 82, 0.026),
                        (1.675, 80, 0.026), (1.712, 76, 0.025), (1.745, 60, 0.023, 0.003), (1.768, 34, 0.024, 0.010),
                        (1.786, 0, 0.024, 0.017), (1.798, 0, 0.012, 0.027)], bone=w_hair_long)
        for s in (-1, 1):
            _fringe(p, s * 3, s * 80, 5, (lambda u: lerp(1.774, 1.688, u ** 1.3)), 1.782, (lambda u: lerp(0.017, 0.028, u)), lift=0.012)
    elif style == "Ponytail":
        _hair_shell(p, _cap_levels())
        for s in (-1, 1):
            _fringe(p, s * 3, s * 72, 4, (lambda u: lerp(1.772, 1.728, u)), 1.780, (lambda u: lerp(0.011, 0.017, u)), lift=0.007)
        if not hat:     # (the hat variant gets a low ponytail after the cut, see build_hair)
            zt = HZ(1.752)
            p.path_tube([(0, -0.118, zt), (0, -0.168, zt - 0.010), (0, -0.205, zt - 0.075), (0, -0.205, zt - 0.175),
                         (0, -0.185, zt - 0.265)], [0.026, 0.036, 0.040, 0.032, 0.012], "M_Hair", "Head", n=7)
            p.path_tube([(0, -0.125, zt + 0.002), (0, -0.160, zt - 0.006)], [0.034, 0.039], "P_Coral", "Head", n=7)
    elif style == "Bob":
        # chin-length bob that curves in under the jaw, straight fringe down to the brows
        _hair_shell(p, [(1.572, 100, 0.034), (1.600, 90, 0.037), (1.640, 84, 0.034), (1.675, 82, 0.031), (1.712, 78, 0.029),
                        (1.745, 62, 0.027, 0.003), (1.768, 36, 0.027, 0.010), (1.786, 0, 0.026, 0.017),
                        (1.798, 0, 0.013, 0.027)])
        _fringe(p, -82, 82, 8, 1.724, 1.782, 0.027, lift=0.012)
    elif style == "Mohawk":
        # shaved sides + a tall crest from the forehead over the crown to the nape
        _hair_shell(p, [(1.612, 130, 0.003), (1.645, 120, 0.004), (1.680, 113, 0.005), (1.710, 97, 0.005),
                        (1.748, 70, 0.005, 0.001), (1.770, 42, 0.005, 0.002), (1.787, 0, 0.005, 0.003),
                        (1.798, 0, 0.003, 0.004)])
        ctr = Vector((0.0, 0.008, HZ(1.700)))
        path = [(0.0, 1.742, 0.022), (0.0, 1.768, 0.062), (0.0, 1.788, 0.080), (0.0, 1.799, 0.086),
                (math.pi, 1.796, 0.086), (math.pi, 1.782, 0.078), (math.pi, 1.755, 0.064), (math.pi, 1.715, 0.046),
                (math.pi, 1.672, 0.028), (math.pi, 1.632, 0.010)]
        secs = []
        for (a, z_src, h) in path:
            c = head_pt(a, HZ(z_src), 0.0)
            nrm = (c - ctr).normalized()
            w = 0.026
            b0 = c - nrm * 0.008
            tip = c + nrm * h * 0.88
            secs.append([tuple(b0 + Vector((-w, 0, 0))), tuple(b0 + Vector((w, 0, 0))),
                         tuple(tip + Vector((w * 0.55, 0, 0))), tuple(tip + Vector((-w * 0.55, 0, 0)))])
        p.loft(secs, "M_Hair", "Head")
    elif style == "Bun":
        # pulled back into a bun on the crown, with a tie
        _hair_shell(p, _cap_levels(1.05))
        for s in (-1, 1):
            _fringe(p, s * 3, s * 70, 4, (lambda u: lerp(1.776, 1.740, u)), 1.782, (lambda u: lerp(0.010, 0.015, u)), lift=0.007)
        if not hat:
            c = Vector((0.0, -0.072, HZ(1.792) + 0.034))
            vs = G.add_sphere(p.bm, 0.050, tuple(c), segments=8, rings=5, mat_index=p.m("M_Hair"), scale=(1.0, 1.0, 0.86), rot=(-0.5, 0, 0))
            p.skin(vs, "Head")
            p.cyl(0.034, 0.016, (0.0, -0.058, HZ(1.792) + 0.012), "P_Coral", "Head", segments=8, rot=(-0.5, 0, 0))
    else:
        raise KeyError(style)


def build_hair(style, hat=False):
    p = Part("Hair_" + style + ("_Hat" if hat else ""))
    _hair_geometry(p, style, hat)
    if hat:
        p.cut(HAT_A - HAT_N * 0.004, HAT_N, keep_above=False)
        p.skin_rest("Head")
        if style == "Ponytail":
            zb = HAT_B.z - 0.022
            p.path_tube([(0, -0.098, zb), (0, -0.150, zb - 0.012), (0, -0.176, zb - 0.085), (0, -0.166, zb - 0.185)],
                        [0.022, 0.032, 0.032, 0.011], "M_Hair", "Head", n=7)
            p.path_tube([(0, -0.106, zb + 0.002), (0, -0.138, zb - 0.006)], [0.028, 0.034], "P_Coral", "Head", n=7)
        if style == "Bun":
            zb = HAT_B.z - 0.040
            vs = G.add_sphere(p.bm, 0.040, (0.0, -0.128, zb), segments=8, rings=5, mat_index=p.m("M_Hair"), scale=(1.0, 0.9, 0.9))
            p.skin(vs, "Head")
        if len(p.bm.faces) == 0:
            p.bm.free()
            return None
    return p.finish()


# ------------------------------------------------------------------------------------------------
# beards
# ------------------------------------------------------------------------------------------------
def _jaw_sweep(p, a0, a1, steps, zbot, ztop, off, mat="M_Hair"):
    """Closed slab wrapped around the jaw between angles a0..a1 (deg). zbot/ztop: functions of |a| (deg)
    returning SOURCE head heights."""
    secs = []
    chin = _HEAD_SRC["M"][0][0]
    for i in range(steps + 1):
        a_deg = lerp(a0, a1, i / steps)
        a = math.radians(a_deg)
        zb, zt = zbot(abs(a_deg)), ztop(abs(a_deg))
        zm = (zb + zt) / 2

        def pt(z_src, o):
            q = head_pt(a, HZ(max(z_src, chin)), o)
            q.z = HZ(z_src)
            return tuple(q)
        secs.append([pt(zb, -0.006), pt(zb, off), pt(zm, off + 0.002), pt(zt, off * 0.7), pt(zt, -0.006)])
    return p.loft(secs, mat, "Head")


def build_beard(style):
    p = Part("Beard_" + style)
    if style == "Full":
        _jaw_sweep(p, -112, 112, 14,
                   lambda a: lerp(1.524, 1.585, sstep(40, 112, a)),
                   lambda a: lerp(1.5885, 1.662, sstep(22, 80, a)), 0.012)
        _jaw_sweep(p, -30, 30, 4, lambda a: 1.6065, lambda a: lerp(1.626, 1.618, a / 30.0), 0.011)
        for s in (-1, 1):   # link moustache to beard beside the mouth
            y, yaw = face_y(s * 0.031, HZ(1.598))
            p.box((0.012, 0.016, 0.026), (s * 0.031, y, HZ(1.598)), "M_Hair", "Head", rot=(0, 0, yaw))
    elif style == "Goatee":
        _jaw_sweep(p, -30, 30, 4, lambda a: 1.520, lambda a: 1.5885, 0.013)
        _jaw_sweep(p, -30, 30, 4, lambda a: 1.6065, lambda a: lerp(1.626, 1.618, a / 30.0), 0.011)
        for s in (-1, 1):
            y, yaw = face_y(s * 0.031, HZ(1.598))
            p.box((0.012, 0.016, 0.026), (s * 0.031, y, HZ(1.598)), "M_Hair", "Head", rot=(0, 0, yaw))
    elif style == "Mustache":
        _jaw_sweep(p, -31, 31, 6, lambda a: lerp(1.6055, 1.596, sstep(14, 31, a)),
                   lambda a: lerp(1.629, 1.613, sstep(8, 31, a)), 0.011)
    else:
        raise KeyError(style)
    return p.finish()


# ------------------------------------------------------------------------------------------------
# hats
# ------------------------------------------------------------------------------------------------
def _dome(p, off, lift, mat, drop=0.0, top_scale=1.0, hi_drop=None, n=12):
    """Skull-following shell above the hat plane (lowered by `drop`); optional upper cut plane."""
    lv = [(1.630, 0, off), (1.675, 0, off), (1.715, 0, off, lift * 0.15), (1.748, 0, off, lift * 0.4),
          (1.772, 0, off * top_scale, lift * 0.7), (1.790, 0, off * 0.85 * top_scale, lift * 0.95), (1.799, 0, off * 0.45, lift * 1.1)]
    secs = [shell_ring(l[0], 0, l[2], l[3] if len(l) > 3 else 0.0, n) for l in lv]
    q = Part("_tmp")
    q.mats = p.mats
    q.loft(secs, mat, "Head")
    q.cut(HAT_A - HAT_N * drop, HAT_N, keep_above=True)
    if hi_drop is not None:
        q.cut(HAT_A - HAT_N * hi_drop, HAT_N, keep_above=False)
    # merge q into p
    me = bpy.data.meshes.new("_tmp_dome")
    q.bm.to_mesh(me)
    q.bm.free()
    p.bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    p.dl = p.bm.verts.layers.deform.verify()


def _dome_front(z_src, off, lift):
    """(y, z) of the flat front facet of a _dome() shell at source height z_src."""
    z = HZ(z_src)
    cy, hw, yf, yb = head_at(z)
    return cy + (yf + off) * (math.cos(math.radians(15.0)) ** HEAD_P), z + lift


def _hat_ring(M, z, hw, df, db, n=12, yshift=0.0):
    pts = []
    for k in range(n):
        a = 2 * math.pi * (k + 0.5) / n
        s, c = math.sin(a), math.cos(a)
        pts.append(tuple(M @ Vector((hw * s, yshift + (df if c >= 0 else db) * c, z))))
    return pts


def _visor(p, mat, y0, z0, length=0.10, half_w=0.090, pitch=-0.14, thick=0.009):
    """Cap bill starting at (y0, z0), pointing forward and slightly down."""
    outline = [(-half_w, 0.0), (half_w, 0.0), (half_w * 0.97, length * 0.55), (half_w * 0.66, length * 0.90),
               (0.0, length), (-half_w * 0.66, length * 0.90), (-half_w * 0.97, length * 0.55)]
    rings = G.add_prism(p.bm, outline, 0.0, thick, axis='Z', mat_index=p.m(mat))
    M = Matrix.Translation((0, y0, z0)) @ Matrix.Rotation(pitch, 4, 'X')
    G.transform(rings, M)
    p.skin(rings, "Head")
    return rings


def build_hat(kind):
    p = Part("Hat_" + kind)
    npc = False
    front_y_rim = HAT_A.y
    if kind == "Cap":
        _dome(p, 0.024, 0.020, "M_Hat")
        _visor(p, "M_Hat", front_y_rim - 0.004, HAT_A.z + 0.004, length=0.105)
        p.cyl(0.013, 0.012, (0, 0.004, HZ(1.799) + 0.020 * 1.1 + 0.004), "M_Hat", "Head", segments=6)
        # front patch, lying on the flat front facet of the crown
        (y0, z0), (y1, z1) = _dome_front(1.748, 0.024, 0.020 * 0.4), _dome_front(1.772, 0.024, 0.020 * 0.7)
        lean = math.atan2(y0 - y1, z1 - z0)
        p.box((0.052, 0.008, 0.026), (0, (y0 + y1) / 2 + 0.002, (z0 + z1) / 2 + 0.002), "P_White", "Head", rot=(lean, 0, 0))
    elif kind == "Beanie":
        _dome(p, 0.022, 0.034, "M_Hat", drop=0.014, top_scale=1.25)
        _dome(p, 0.034, 0.0, "M_Hat", drop=0.018, hi_drop=-0.030)
    elif kind == "Brim":
        M = hat_frame(0.004)
        secs = [_hat_ring(M, -0.004, 0.114, 0.128, 0.128), (_hat_ring(M, 0.060, 0.110, 0.122, 0.124)),
                _hat_ring(M, 0.104, 0.100, 0.108, 0.114), _hat_ring(M, 0.118, 0.070, 0.070, 0.082, yshift=-0.004)]
        p.loft(secs, "M_Hat", "Head")
        p.loft([_hat_ring(M, 0.004, 0.118, 0.132, 0.132), _hat_ring(M, 0.032, 0.116, 0.129, 0.130)], "P_Charcoal", "Head")
        p.loft([_hat_ring(M, -0.006, 0.196, 0.214, 0.208), _hat_ring(M, 0.000, 0.200, 0.218, 0.212),
                _hat_ring(M, 0.008, 0.150, 0.165, 0.160)], "M_Hat", "Head")
    elif kind == "Bandana":
        _dome(p, 0.009, 0.008, "M_Hat", drop=0.006)
        _dome(p, 0.014, 0.0, "M_Hat", drop=0.008, hi_drop=-0.026)
        zb = HAT_B.z + 0.006
        ky = HAT_B.y - 0.022                      # knot, pressed against the band
        p.box((0.046, 0.032, 0.036), (0, ky, zb), "M_Hat", "Head", taper=(1, 0.8, -1))
        for s in (-1, 1):                         # two tails hanging from the knot down the nape
            p.box((0.028, 0.010, 0.100), (s * 0.024, ky - 0.012, zb - 0.056), "M_Hat", "Head", rot=(-0.16, s * 0.30, 0), taper=(2, 0.6))
    elif kind == "Police":
        npc = True
        M = hat_frame(0.004)
        p.loft([_hat_ring(M, -0.006, 0.114, 0.128, 0.128), _hat_ring(M, 0.046, 0.116, 0.130, 0.130)], "P_UniformNavy", "Head")
        p.loft([_hat_ring(M, 0.000, 0.118, 0.132, 0.132), _hat_ring(M, 0.020, 0.118, 0.132, 0.132)], "P_Black", "Head")
        p.loft([_hat_ring(M, 0.044, 0.116, 0.130, 0.130), _hat_ring(M, 0.090, 0.150, 0.172, 0.156, yshift=0.004),
                _hat_ring(M, 0.112, 0.146, 0.166, 0.150, yshift=0.004), _hat_ring(M, 0.126, 0.100, 0.112, 0.104, yshift=0.004)],
               "P_UniformNavy", "Head")
        _visor(p, "P_Black", front_y_rim - 0.002, HAT_A.z + 0.004, length=0.082, half_w=0.092, pitch=-0.30, thick=0.008)
        fb = M @ Vector((0, 0.140, 0.064))
        p.box((0.038, 0.014, 0.046), tuple(fb), "P_BadgeGold", "Head", rot=(HAT_TILT + 0.10 + math.pi, 0, 0), taper=(2, 0.5))
    elif kind == "Helmet":
        npc = True
        BK, CH = "P_TacticalBlack", "P_Charcoal"
        _dome(p, 0.032, 0.026, BK, drop=0.022)
        _dome(p, 0.039, 0.0, CH, drop=0.024, hi_drop=-0.004)
        cy, hw, yf, yb = head_at(EAR_Z)
        for s in (-1, 1):
            p.box((0.032, 0.074, 0.086), (s * (hw + 0.022), cy - 0.014, EAR_Z + 0.006), BK, "Head", taper=(2, 0.82))
            p.box((0.010, 0.086, 0.018), (s * (hw + 0.040), cy + 0.004, EAR_Z + 0.062), CH, "Head")
            # chin strap: follows the cheek from the ear cup to the chin cup
            pts = [tuple(head_pt(s * math.radians(a), HZ(zs), 0.005)) for (a, zs) in ((82, 1.668), (64, 1.625), (44, 1.588), (22, 1.558))]
            p.path_tube(pts, 0.009, CH, "Head", n=4, side=(0, 1, 0), flat=0.5)
        p.box((0.046, 0.022, 0.040), (0, HAT_A.y + 0.030, HAT_A.z + 0.034), CH, "Head", rot=(0.3, 0, 0))
        my, _ = face_y(0.0, HZ(1.552))
        p.box((0.060, 0.022, 0.028), (0, my + 0.006, HZ(1.552)), CH, "Head")
    elif kind == "FireHelmet":
        npc = True
        RED = "P_FireRed"
        _dome(p, 0.030, 0.030, RED, drop=0.010)
        M = hat_frame(0.012)
        p.loft([_hat_ring(M, -0.006, 0.150, 0.160, 0.215), _hat_ring(M, 0.002, 0.156, 0.166, 0.224),
                _hat_ring(M, 0.014, 0.128, 0.140, 0.150)], RED, "Head")
        # crest ridge following the dome from front to back
        path = []
        for zs, lf, osc in ((1.748, 0.4, 1.0), (1.772, 0.7, 1.0), (1.790, 0.95, 0.85), (1.799, 1.1, 0.45)):
            cy, hw, yf, yb = head_at(HZ(zs))
            path.append((cy + (yf + 0.030 * osc) * 0.97, HZ(zs) + 0.030 * lf))
        for zs, lf, osc in ((1.799, 1.1, 0.45), (1.790, 0.95, 0.85), (1.772, 0.7, 1.0), (1.748, 0.4, 1.0), (1.715, 0.15, 1.0)):
            cy, hw, yf, yb = head_at(HZ(zs))
            path.append((cy - (yb + 0.030 * osc) * 0.97, HZ(zs) + 0.030 * lf))
        secs = []
        for i, (y, z) in enumerate(path):
            h = 0.024 if 0 < i < len(path) - 1 else 0.008
            w = 0.014
            secs.append([(-w, y, z - 0.008), (w, y, z - 0.008), (w * 0.5, y * 1.03, z + h), (-w * 0.5, y * 1.03, z + h)])
        p.loft(secs, RED, "Head")
        (y0, z0), (y1, z1) = path[0], path[1]
        lean = math.atan2(y0 - y1, z1 - z0)
        p.box((0.052, 0.012, 0.056), (0, (y0 + y1) / 2 + 0.006, (z0 + z1) / 2 + 0.002), "P_BadgeGold", "Head",
              rot=(lean, 0, 0), taper=(2, 0.6))
    else:
        raise KeyError(kind)
    p.skin_rest("Head")
    return p.finish(npc=npc)


# ------------------------------------------------------------------------------------------------
# glasses
# ------------------------------------------------------------------------------------------------
def _temples(p, mat, x_front, y_front, z, thick=0.006, h=0.008):
    cy, hw, yf, yb = head_at(EAR_Z)
    for s in (-1, 1):
        a = Vector((s * x_front, y_front, z))
        b = Vector((s * (hw + 0.010), cy - 0.012, z + 0.002))
        d = b - a
        L = d.length
        yaw = -math.atan2(d.x, d.y)
        p.box((thick, L, h), tuple((a + b) / 2), mat, "Head", rot=(0, 0, yaw))


def build_glasses(kind):
    p = Part("Glasses_" + kind)
    ez = EYE_Z
    ex = 0.044
    npc = False
    if kind == "Shades":
        for s in (-1, 1):
            y, yaw = face_y(s * ex, ez)
            p.box((0.054, 0.008, 0.036), (s * (ex + 0.002), y + 0.011, ez - 0.002), "P_WindowDark", "Head", rot=(0, 0, yaw), taper=(2, 1.12))
            p.box((0.060, 0.010, 0.008), (s * (ex + 0.002), y + 0.011, ez + 0.017), "P_Black", "Head", rot=(0, 0, yaw))
        y0, _ = face_y(0.0, ez)
        p.box((0.030, 0.008, 0.008), (0, y0 + 0.010, ez + 0.012), "P_Black", "Head")
        y, _ = face_y(ex + 0.028, ez)
        _temples(p, "P_Black", ex + 0.030, y + 0.008, ez + 0.012)
    elif kind == "Round":
        FR = "P_BadgeGold"
        for s in (-1, 1):
            y, yaw = face_y(s * ex, ez)
            R = Matrix.Rotation(yaw, 3, 'Z')
            c = Vector((s * (ex + 0.001), y + 0.011, ez - 0.001))
            for (ox, oz, sx, sz) in ((0, 0.021, 0.056, 0.006), (0, -0.021, 0.056, 0.006), (-0.026, 0, 0.006, 0.042), (0.026, 0, 0.006, 0.042)):
                p.box((sx, 0.006, sz), tuple(c + R @ Vector((ox, 0, 0)) + Vector((0, 0, oz))), FR, "Head", rot=(0, 0, yaw))
        y0, _ = face_y(0.0, ez)
        p.box((0.026, 0.006, 0.006), (0, y0 + 0.009, ez + 0.008), FR, "Head")
        y, _ = face_y(ex + 0.028, ez)
        _temples(p, FR, ex + 0.029, y + 0.008, ez + 0.010, thick=0.004, h=0.005)
    elif kind == "Goggles":
        npc = True
        BK = "P_TacticalBlack"
        samples = []
        for i in range(12):
            a = 2 * math.pi * (i + 0.5) / 12
            q = head_pt(a, ez + 0.006, 0.004)
            r = math.hypot(q.x, q.y - 0.004)
            samples.append((math.degrees(math.atan2(q.x, q.y - 0.004)), r, ez + 0.006, 0.006, 0.017))
        p.arc_sweep(samples, BK, "Head", n=4, closed=True)
        for s in (-1, 1):
            y, yaw = face_y(s * ex, ez)
            p.box((0.072, 0.030, 0.056), (s * (ex - 0.003), y + 0.008, ez), BK, "Head", rot=(0, 0, yaw), taper=(1, 0.86))
            p.box((0.056, 0.012, 0.040), (s * (ex - 0.003), y + 0.021, ez), "P_Mustard", "Head", rot=(0, 0, yaw))
        y0, _ = face_y(0.0, ez)
        p.box((0.030, 0.024, 0.030), (0, y0 + 0.006, ez + 0.006), BK, "Head")
    else:
        raise KeyError(kind)
    return p.finish(npc=npc)


# ------------------------------------------------------------------------------------------------
# hands
# ------------------------------------------------------------------------------------------------
def build_hands():
    """Hands with four separate fingers and a thumb (all rigid on the Hand bone). Rest pose: palms
    down, fingers half curled, thumb opposing - a relaxed hand at the side of the body, a fist-like
    shape when punching and a believable grip around anything parented to the hand
    (CharacterVisual.get_grip_transform: origin 0.075 m along the hand, 0.03 m below its axis)."""
    p = Part("Hands")
    FINGERS = ((0.0385, 0.95), (0.0150, 1.00), (-0.0085, 0.94), (-0.0320, 0.78))   # (y offset, length factor): index .. pinky
    for s, suf in SIDES:
        z = SH_Z
        bone = "Hand" + suf

        def ring(dx, cy, cz, ry, rz, n=8):
            pts = []
            for k in range(n):
                a = 2 * math.pi * (k + 0.5) / n
                pts.append((s * (WR_X + dx), cy + ry * spow(math.cos(a), 0.8), z + cz + rz * spow(math.sin(a), 0.8)))
            return pts
        # wrist ball (inside the sleeve / forearm end) + palm up to the knuckle line
        secs = [ring(-0.030, 0.0, 0.0, 0.021, 0.017), ring(-0.010, 0.0, 0.0, 0.031, 0.025), ring(0.022, 0.002, 0.0, 0.043, 0.026),
                ring(0.052, 0.003, -0.001, 0.049, 0.025), ring(0.082, 0.003, -0.002, 0.049, 0.023), ring(0.096, 0.003, -0.004, 0.045, 0.019)]
        p.loft(secs, "M_Skin", bone)
        # fingers: knuckle -> two bends -> tip, curling down toward the palm
        for (fy, fl) in FINGERS:
            kx, kz = WR_X + 0.086, z - 0.003
            pts = [(kx - 0.014, kz)]
            cx_, cz_ = kx, kz
            for (ln, deg) in ((0.042, -26.0), (0.028, -78.0), (0.021, -124.0)):
                cx_ += ln * fl * math.cos(math.radians(deg))
                cz_ += ln * fl * math.sin(math.radians(deg))
                pts.append((cx_, cz_))
            p.path_tube([(s * x, 0.003 + fy, zz) for (x, zz) in pts], [0.0146, 0.0146, 0.0132, 0.0108], "M_Skin", bone,
                        n=4, side=(0, 1, 0))
        # thumb: from the side of the palm forward and down, opposing the fingers
        tp = [(0.024, 0.030, -0.004), (0.050, 0.060, -0.012), (0.078, 0.070, -0.027), (0.097, 0.064, -0.043)]
        p.path_tube([(s * (WR_X + x), y, z + zz) for (x, y, zz) in tp], [0.0175, 0.0165, 0.0145, 0.0115], "M_Skin", bone,
                    n=4, side=(0, 0, 1))
    return p.finish()


# ------------------------------------------------------------------------------------------------
# shoes
# ------------------------------------------------------------------------------------------------
SHOE_L = 1.10     # slightly large feet
SHOE_W = 1.14


def _shoe_upper(part, s, rows, mat, bone, zs):
    """rows: (y, half width, z mid, z top) sections from heel to toe."""
    secs = []
    cx = HIP_X * s
    for (y, w, zm, zt) in rows:
        y *= SHOE_L
        w *= SHOE_W
        secs.append([(cx - w, y, zs), (cx + w, y, zs), (cx + w, y, zm), (cx + w * 0.58, y, zt), (cx - w * 0.58, y, zt), (cx - w, y, zm)])
    return part.loft(secs, mat, bone)


def _sole(part, s, zs, mat, bone, grow=0.004):
    cx = HIP_X * s
    out = [(-0.030, -0.082), (0.030, -0.082), (0.046, -0.046), (0.052, 0.07), (0.049, 0.150), (0.031, 0.192),
           (-0.031, 0.192), (-0.049, 0.150), (-0.052, 0.07), (-0.046, -0.046)]
    prof = [(cx + x * SHOE_W * (1 + grow / 0.05), y * SHOE_L + (grow if y > 0 else -grow)) for x, y in out]
    return part.prism(prof, 0.0, zs, 'Z', mat, bone)


def _sbox(p, s, size, center, mat, bone, rot=None):
    """Shoe detail box in un-scaled shoe coordinates (x relative to the foot centre line)."""
    cx = HIP_X * s
    return p.box((size[0] * SHOE_W, size[1] * SHOE_L, size[2]), (cx + center[0] * SHOE_W * s, center[1] * SHOE_L, center[2]), mat, bone, rot=rot)


def build_shoes(kind):
    p = Part("Shoes_" + kind)
    _upper_st, lower_st = leg_stations("M")
    for s, suf in SIDES:
        foot = "Foot" + suf
        shin = "LowerLeg" + suf
        cx = HIP_X * s
        ax, ua, ub = (0, 0, -1), (1, 0, 0), (0, 1, 0)
        if kind == "Sneakers":
            _sole(p, s, 0.032, "P_ShoeWhite", foot)
            _shoe_upper(p, s, [(-0.078, 0.030, 0.078, 0.112), (-0.040, 0.044, 0.084, 0.124), (0.034, 0.046, 0.080, 0.118),
                               (0.086, 0.049, 0.060, 0.082), (0.150, 0.046, 0.048, 0.060), (0.186, 0.030, 0.040, 0.046)],
                        "M_Shoes", foot, 0.028)
            _sbox(p, s, (0.066, 0.040, 0.016), (0, 0.172, 0.048), "P_ShoeWhite", foot, rot=(-0.20, 0, 0))
            for i in range(3):
                _sbox(p, s, (0.046, 0.009, 0.008), (0, 0.062 + i * 0.026, 0.099 - i * 0.011), "P_ShoeWhite", foot, rot=(-0.38, 0, 0))
            p.tube((cx, 0, KNEE_Z), ax, ua, ub, _grow(_cut(lower_st, KNEE_Z - 0.200, KNEE_Z - 0.055), 0.004), "P_ShoeWhite", shin)
        elif kind == "Boots":
            _sole(p, s, 0.038, "P_Trim", foot, grow=0.006)
            _shoe_upper(p, s, [(-0.080, 0.034, 0.092, 0.128), (-0.040, 0.048, 0.098, 0.138), (0.036, 0.050, 0.092, 0.132),
                               (0.088, 0.052, 0.072, 0.092), (0.152, 0.050, 0.060, 0.074), (0.190, 0.034, 0.052, 0.060)],
                        "M_Shoes", foot, 0.034)
            p.tube((cx, 0, KNEE_Z), ax, ua, ub, _grow(_cut(lower_st, KNEE_Z - 0.262, KNEE_Z - 0.070), 0.0045), "M_Shoes", shin)
            p.tube((cx, 0, KNEE_Z), ax, ua, ub, _grow(_cut(lower_st, KNEE_Z - 0.268, KNEE_Z - 0.244), 0.0065), "P_Trim", shin)
            for i in range(3):
                _sbox(p, s, (0.050, 0.010, 0.008), (0, 0.060 + i * 0.024, 0.116 - i * 0.013), "P_Trim", foot, rot=(-0.45, 0, 0))
        else:  # Dress
            _sole(p, s, 0.016, "P_Black", foot, grow=0.002)
            _sbox(p, s, (0.070, 0.062, 0.022), (0, -0.048, 0.011), "P_Black", foot)
            _shoe_upper(p, s, [(-0.078, 0.029, 0.064, 0.096), (-0.040, 0.042, 0.068, 0.104), (0.030, 0.044, 0.064, 0.098),
                               (0.084, 0.046, 0.048, 0.062), (0.156, 0.040, 0.034, 0.042), (0.198, 0.022, 0.026, 0.030)],
                        "M_Shoes", foot, 0.014)
            _sbox(p, s, (0.050, 0.050, 0.008), (0, 0.150, 0.041), "M_Shoes", foot, rot=(-0.12, 0, 0))
            p.tube((cx, 0, KNEE_Z), ax, ua, ub, _grow(_cut(lower_st, KNEE_Z - 0.150, KNEE_Z - 0.055), 0.003), "P_Charcoal", shin)
    return p.finish()


# ------------------------------------------------------------------------------------------------
# tops
# ------------------------------------------------------------------------------------------------
def _collar_band(p, body, mat, z0=1.462, z1=1.494, extra=0.012):
    rn = BODY[body]["neck"]
    p.tube((0, 0.004, z0), (0, 0, 1), (1, 0, 0), (0, 1, 0),
           [(0.0, rn + extra + 0.008, rn + extra + 0.008), (z1 - z0, rn + extra, rn + extra)], mat, "Chest", n=8)


def _collar_wings(p, body, mat, spread=1.0):
    """Shirt collar: stand + two pointed wings at the front."""
    rn = BODY[body]["neck"]
    _collar_band(p, body, mat, 1.462, 1.502, 0.010)
    for s in (-1, 1):
        p.box((0.062, 0.014, 0.040), (s * 0.040 * spread, 0.004 + rn + 0.020, 1.474), mat, "Chest",
              rot=(0.35, s * 0.42, s * -0.52), taper=(0, 0.35, s))


def _strap_over_shoulder(p, body, prof, x, z_low, mat, width=0.046, thick=0.016, back_low=None, follow=False):
    """Flat strap from the front, over the shoulder, to the back (tank tops, vests, aprons).
    follow=True adds points on the shoulder shelf ring so that thin straps hug the body."""
    tors = BODY[body]["torso"]
    top_z = None
    for a, b in zip(tors[:-1], tors[1:]):
        if a[1] >= abs(x) >= b[1] and a[0] >= SH_Z:
            top_z = lerp(a[0], b[0], (a[1] - abs(x)) / (a[1] - b[1]))
    if top_z is None:
        top_z = tors[-2][0]
    zb = back_low if back_low is not None else z_low
    zs = tors[-2][0]
    for s in (-1, 1):
        xx = s * x
        pts = [(xx, front_y(prof, xx, z_low) - 0.002, z_low), (xx, front_y(prof, xx, SH_Z) + 0.001, SH_Z)]
        if follow:
            pts.append((xx, front_y(prof, xx, zs) + 0.001, zs))
        pts.append((xx, 0.0, top_z + 0.004))
        if follow:
            pts.append((xx, back_y(prof, xx, zs) - 0.001, zs))
        pts += [(xx, back_y(prof, xx, SH_Z) - 0.001, SH_Z), (xx, back_y(prof, xx, zb) + 0.002, zb)]
        p.path_tube(pts, width / 2 / 0.707, mat, w_torso, n=4, side=(1, 0, 0), flat=thick / width)


def _buttons(p, prof, zs, mat="P_White", size=0.012, x=0.0, out=0.006):
    for z in zs:
        y = front_y(prof, x, z)
        p.box((size, 0.008, size), (x, y + out, z), mat, w_torso)


def build_top(kind, body):
    p = Part("Top_%s_%s" % (kind, body))
    rn = BODY[body]["neck"]
    fem = body == "F"
    if kind == "Tee":
        prof = add_torso(p, body, "M_Top", grow=0.004)
        add_arms(p, body, "short", "M_Top", grow=0.009, cuff_mat="M_Top_Accent")
        _collar_band(p, body, "M_Top_Accent")
    elif kind == "Shirt":
        prof = add_torso(p, body, "M_Top", grow=0.005, tucked=True)
        add_arms(p, body, "long", "M_Top", grow=0.008, cuff_mat="M_Top_Accent")
        _collar_wings(p, body, "M_Top_Accent")
        strip_x(p, prof, 1.025, 1.452, -0.017, 0.017, thick=0.005, mat="M_Top_Accent")
        _buttons(p, prof, (1.09, 1.18, 1.27, 1.36), "P_White", 0.011, out=0.007)
        strip_x(p, prof, 1.27, 1.345, -0.128, -0.068, thick=0.006, mat="M_Top")
        strip_a(p, prof, 1.372, 1.436, 112, 248, thick=0.004, mat="M_Top")          # back yoke
    elif kind == "Hoodie":
        prof = add_torso(p, body, "M_Top", grow=0.016, ease=0.016)
        ring_band(p, prof, 0.955, 0.995, 0.007, "M_Top")
        add_arms(p, body, "long", "M_Top", grow=0.016, cuff_mat="M_Top")
        _collar_band(p, body, "M_Top_Accent")
        # hood resting on the upper back
        p.arc_sweep([(62, rn + 0.030, 1.474, 0.024, 0.022), (100, rn + 0.040, 1.470, 0.032, 0.030), (140, rn + 0.052, 1.462, 0.040, 0.040),
                     (180, rn + 0.062, 1.452, 0.046, 0.050), (220, rn + 0.052, 1.462, 0.040, 0.040), (260, rn + 0.040, 1.470, 0.032, 0.030),
                     (298, rn + 0.030, 1.474, 0.024, 0.022)], "M_Top", "Chest", n=6)
        strip_a(p, prof, 1.015, 1.135, -40, 40, thick=0.013, mat="M_Top")
        for s in (-1, 1):
            y = front_y(prof, s * 0.030, 1.38)
            p.box((0.009, 0.008, 0.095), (s * 0.030, y + 0.004, 1.385), "M_Top_Accent", w_torso)
    elif kind == "Jacket":
        # Open bomber (the player's default top, seen from behind most of the time): the inner tee
        # shows in a V, collar / hem / cuffs are ribbing in the accent colour and an accent stripe
        # runs around the chest, the back and both sleeves.
        def fn(c):
            return "M_Top_Accent" if (c.y > 0 and abs(c.x) < 0.02 and c.z < 1.45) else None
        prof = add_torso(p, body, "M_Top", grow=0.014, ease=0.014, mat_fn=fn)
        add_arms(p, body, "long", "M_Top", grow=0.014, cuff_mat="M_Top_Accent")
        _collar_band(p, body, "M_Top_Accent")
        inner = (lambda z: lerp(0.020, 0.058, clamp01((z - 0.957) / 0.49)))
        neg = (lambda z: -inner(z))
        for s in (-1, 1):
            if s > 0:
                strip_x(p, prof, 0.990, 1.448, inner, 0.100, thick=0.011, mat="M_Top")
                strip_x(p, prof, 1.292, 1.326, inner, 0.100, thick=0.0135, mat="M_Top_Accent")
            else:
                strip_x(p, prof, 0.990, 1.448, -0.100, neg, thick=0.011, mat="M_Top")
                strip_x(p, prof, 1.292, 1.326, -0.100, neg, thick=0.0135, mat="M_Top_Accent")
            y = front_y(prof, s * 0.125, 1.07)
            p.box((0.070, 0.010, 0.014), (s * 0.122, y + 0.002, 1.075), "P_Charcoal", w_torso, rot=(0, s * 0.45, s * -0.42))
        strip_a(p, prof, 0.957, 0.997, 5, 355, thick=0.012, mat="M_Top_Accent")       # ribbed hem
        strip_a(p, prof, 1.292, 1.326, 27, 333, thick=0.005, mat="M_Top_Accent")      # chest / back stripe
        arm_piece(p, body, "upper", 0.085, 0.118, 0.019, "M_Top_Accent")              # ... continues on the sleeves
        p.arc_sweep([(38, rn + 0.030, 1.476, 0.018, 0.018), (80, rn + 0.034, 1.478, 0.022, 0.018), (130, rn + 0.036, 1.478, 0.024, 0.018),
                     (180, rn + 0.038, 1.478, 0.024, 0.018), (230, rn + 0.036, 1.478, 0.024, 0.018), (280, rn + 0.034, 1.478, 0.022, 0.018),
                     (322, rn + 0.030, 1.476, 0.018, 0.018)], "M_Top", "Chest", n=6)
    elif kind == "Tank":
        # Bare shoulders: the torso above the chest line is skin. The V neck, the arm holes and the
        # straps are real geometry: two panels per side that narrow from the full chest width
        # (under the arm) to the strap width, then a strap over the shoulder.
        zc = BODY[body]["torso"][4][0]

        def fn(c):
            return "M_Skin" if c.z > zc else None
        prof = add_torso(p, body, "M_Top", grow=0.003, mat_fn=fn)
        add_arms(p, body, "none")
        sx = 0.094 if not fem else 0.084            # strap centre line
        sw = 0.052 if not fem else 0.036            # strap width
        ztop = 1.396 if not fem else 1.386          # where the panels become straps
        zb0 = zc - 0.014
        a_in = ang_of_x(prof, ztop, sx - sw / 2)
        a_out = ang_of_x(prof, ztop, sx + sw / 2)
        k = (lambda z: clamp01((z - zb0) / (ztop - zb0)))
        lo = (lambda z: lerp(0.0, a_in, k(z) ** 0.7))          # neckline (V)
        hi = (lambda z: lerp(80.0, a_out, k(z) ** 0.55))       # arm hole
        for base, sg in ((0.0, 1.0), (0.0, -1.0), (180.0, 1.0), (180.0, -1.0)):
            if sg > 0:
                f0, f1 = (lambda z, b=base: b + lo(z)), (lambda z, b=base: b + hi(z))
            else:
                f0, f1 = (lambda z, b=base: b - hi(z)), (lambda z, b=base: b - lo(z))
            strip_a(p, prof, zb0, ztop, f0, f1, thick=0.004, mat="M_Top", inset=0.005)
        _strap_over_shoulder(p, body, prof, sx, ztop - 0.010, "M_Top", width=sw, thick=0.013, follow=True)
    elif kind == "Suit":
        def fn(c):
            return "M_Top_Accent" if (c.y > 0 and abs(c.x) < 0.02 and 1.15 < c.z < 1.46) else None
        prof = add_torso(p, body, "M_Top", grow=0.012, hem_z=0.895, hem_extra=0.015, ease=0.014, mat_fn=fn, shoulder=1.04)
        add_arms(p, body, "long", "M_Top", grow=0.012, cuff_mat="M_Top_Accent")
        _collar_wings(p, body, "M_Top_Accent", spread=0.9)
        for s in (-1, 1):
            inner = (lambda z: lerp(0.001, 0.050, clamp01((z - 1.15) / 0.30)))
            if s > 0:
                strip_x(p, prof, 1.15, 1.450, inner, 0.092, thick=0.009, mat="M_Top")
            else:
                strip_x(p, prof, 1.15, 1.450, -0.092, (lambda z, f=inner: -f(z)), thick=0.009, mat="M_Top")
            strip_x(p, prof, 0.975, 0.997, min(s * 0.085, s * 0.150), max(s * 0.085, s * 0.150), thick=0.008, mat="M_Top")
        hw_t = (lambda z: lerp(0.021, 0.011, clamp01((z - 1.17) / 0.27)))
        strip_x(p, prof, 1.165, 1.440, (lambda z: -hw_t(z)), hw_t, thick=0.007, mat="P_Terracotta")
        y = front_y(prof, 0.0, 1.447)
        p.box((0.030, 0.016, 0.026), (0, y + 0.004, 1.447), "P_Terracotta", "Chest", taper=(2, 1.3))
        _buttons(p, prof, (1.03, 1.105), "P_Charcoal", 0.014, out=0.008)
        y = front_y(prof, -0.105, 1.32)
        p.box((0.040, 0.008, 0.012), (-0.105, y + 0.004, 1.322), "M_Top_Accent", w_torso, rot=(0, 0, 0.30))
        p.arc_sweep([(70, rn + 0.030, 1.480, 0.016, 0.016), (120, rn + 0.034, 1.482, 0.020, 0.016), (180, rn + 0.036, 1.482, 0.022, 0.016),
                     (240, rn + 0.034, 1.482, 0.020, 0.016), (290, rn + 0.030, 1.480, 0.016, 0.016)], "M_Top", "Chest", n=6)
    elif kind == "Vest":
        def fn(c):
            return "M_Top_Accent" if (c.y > 0 and abs(c.x) < 0.02 and c.z < 1.45) else None
        prof = add_torso(p, body, "M_Top", grow=0.011, ease=0.013, mat_fn=fn)
        add_arms(p, body, "short", "M_Top_Accent", grow=0.008, sleeve_len=0.13)
        arm_piece(p, body, "upper", -0.030, 0.034, 0.017, "M_Top")
        _collar_band(p, body, "M_Top_Accent")
        for s in (-1, 1):
            x0, x1 = (0.034, 0.084) if s > 0 else (-0.084, -0.034)
            strip_x(p, prof, 0.957, 1.448, x0, x1, thick=0.010, mat="M_Top")
            y = front_y(prof, s * 0.118, 1.30)
            p.box((0.060, 0.010, 0.050), (s * 0.118, y + 0.003, 1.300), "M_Top", w_torso, rot=(0, 0, s * -0.36))
            p.box((0.066, 0.012, 0.014), (s * 0.118, y + 0.005, 1.330), "P_Charcoal", w_torso, rot=(0, 0, s * -0.36))
        # back emblem: plain diamond patch
        yb = back_y(prof, 0.0, 1.28)
        p.box((0.085, 0.010, 0.085), (0, yb - 0.003, 1.285), "M_Top_Accent", w_torso, rot=(0, math.pi / 4, 0))
        p.box((0.045, 0.012, 0.045), (0, yb - 0.004, 1.285), "M_Top", w_torso, rot=(0, math.pi / 4, 0))
    else:
        raise KeyError(kind)
    return p.finish()


# ------------------------------------------------------------------------------------------------
# bottoms
# ------------------------------------------------------------------------------------------------
def _belt(p, prof, mat="P_Leather", buckle="P_BadgeGold", z=1.008, h=0.036, grow=0.004, bw=0.044):
    hw, df, db = prof_at(prof, z, grow)
    p.loft([sec(z - h / 2, hw, df, db), sec(z + h / 2, hw - 0.001, df - 0.001, db - 0.001)], mat, "Hips")
    if buckle:
        p.box((bw, 0.010, h + 0.004), (0, poly_y((hw, df, db), 0.0) + 0.001, z), buckle, "Hips")


def _hip_box(p, prof, a_deg, z, size, mat, grow=0.0, out=None, bone="Hips", taper=None, tilt=0.0):
    """Box sitting on the belt / hip at angle a_deg, facing outward. size = (width, depth, height)."""
    q = poly_pt(prof_at(prof, z, grow), a_deg)
    q2 = poly_pt(prof_at(prof, z, grow), a_deg + 2.0)
    q1 = poly_pt(prof_at(prof, z, grow), a_deg - 2.0)
    tang = (q2 - q1).normalized()
    nrm = Vector((tang.y, -tang.x))
    if nrm.dot(q) < 0:
        nrm = -nrm
    yaw = math.atan2(-nrm.x, nrm.y)
    o = size[1] / 2 - 0.004 if out is None else out
    c = (q.x + nrm.x * o, q.y + nrm.y * o, z)
    return p.box(size, c, mat, bone, rot=(tilt, 0, yaw), taper=taper)


def build_bottom(kind, body):
    p = Part("Bottom_%s_%s" % (kind, body))
    if kind == "Jeans":
        prof = add_pelvis(p, body, "M_Bottom", grow=0.002)
        add_legs(p, body, "M_Bottom", grow=0.009, length="long", straight=0.25, hem_mat="M_Bottom")
        _belt(p, prof)
        for s in (-1, 1):
            y = back_y(prof, s * 0.092, 0.92)
            p.box((0.076, 0.010, 0.080), (s * 0.092, y - 0.001, 0.92), "M_Bottom", "Hips", rot=(0, 0, s * 0.30))
            _hip_box(p, prof, s * 38, 0.948, (0.064, 0.008, 0.012), "M_Bottom", grow=0.0, out=0.001)    # front pocket welt
        y = front_y(prof, 0.0, 0.94)
        p.box((0.012, 0.008, 0.085), (0.014, y, 0.945), "M_Bottom", "Hips")
    elif kind == "Shorts":
        prof = add_pelvis(p, body, "M_Bottom", grow=0.004)
        add_legs(p, body, "M_Bottom", grow=0.014, length="short", short_z=0.585, hem_mat="M_Bottom")
        ring_band(p, prof, 0.995, 1.030, 0.004, "M_Bottom", "Hips")
        for s in (-1, 1):
            y = front_y(prof, s * 0.020, 0.925)
            p.box((0.008, 0.008, 0.046), (s * 0.020, y + 0.003, 0.922), "P_White", "Hips")
            # side pocket slabs
            p.box((0.012, 0.085, 0.100), (s * (leg_outer_x(body, 0.78, 0.014) + 0.002), -0.004, 0.790), "M_Bottom", "UpperLeg" + ("_R" if s > 0 else "_L"))
    elif kind == "Cargo":
        prof = add_pelvis(p, body, "M_Bottom", grow=0.006)
        add_legs(p, body, "M_Bottom", grow=0.015, length="long", straight=0.55)
        _belt(p, prof, mat="P_Charcoal", buckle="P_Steel", grow=0.004)
        for s, suf in SIDES:
            xo = leg_outer_x(body, 0.70, 0.015, 0.55)
            p.box((0.030, 0.105, 0.130), (s * (xo + 0.004), 0.0, 0.700), "M_Bottom", "UpperLeg" + suf)
            p.box((0.034, 0.112, 0.036), (s * (xo + 0.005), 0.0, 0.762), "M_Bottom", "UpperLeg" + suf)
            y = back_y(prof, s * 0.092, 0.92)
            p.box((0.076, 0.012, 0.070), (s * 0.092, y - 0.002, 0.925), "M_Bottom", "Hips", rot=(0, 0, s * 0.30))
            leg_piece(p, body, "lower", 0.012, 0.050, 0.019, "M_Bottom", straight=0.55, sides=((s, suf),))
    elif kind == "Slacks":
        prof = add_pelvis(p, body, "M_Bottom", grow=0.002)
        add_legs(p, body, "M_Bottom", grow=0.010, length="long", straight=0.60, cuff_z=0.095)
        _belt(p, prof, mat="P_Black", buckle="P_Chrome", h=0.028, bw=0.034)
        for s, suf in SIDES:
            # pressed crease
            p.box((0.008, 0.008, 0.36), (s * HIP_X, leg_stations(body, 0.010, 0.6)[0][3][2] - 0.001, 0.70), "M_Bottom", "UpperLeg" + suf)
    elif kind == "Skirt":
        prof = add_pelvis(p, body, "M_Bottom", grow=0.003)
        pel = BODY[body]["pelvis"]
        rings = [(1.030, pel[3][1] + 0.006, pel[3][2] + 0.006, pel[3][3] + 0.006), (0.970, pel[2][1] + 0.010, pel[2][2] + 0.012, pel[2][3] + 0.012),
                 (0.890, pel[1][1] + 0.014, pel[1][2] + 0.020, pel[1][3] + 0.018), (0.770, 0.222, 0.146, 0.150), (0.650, 0.238, 0.160, 0.164)]
        p.loft([sec(*r) for r in reversed(rings)], "M_Bottom", w_skirt)
        ring_band(p, [tuple(r) for r in reversed(rings)], 0.650, 0.676, 0.004, "M_Bottom", w_skirt)
        add_legs(p, body, length="skin")
        ring_band(p, prof, 0.995, 1.032, 0.009, "M_Top_Accent", "Hips")
    else:
        raise KeyError(kind)
    return p.finish()


# ------------------------------------------------------------------------------------------------
# full outfits (torso + arms + legs in one mesh; headgear / shoes are separate slot parts)
# ------------------------------------------------------------------------------------------------
def _knee_pads(p, mat, y, size=(0.112, 0.036, 0.130)):
    """y = front surface of the trouser knee."""
    for s, suf in SIDES:
        p.box(size, (s * HIP_X, y - 0.004, KNEE_Z - 0.018), mat, "LowerLeg" + suf, taper=(2, 0.8))
        p.box((size[0] * 0.8, 0.02, 0.05), (s * HIP_X, y + 0.004, KNEE_Z - 0.018), mat, "LowerLeg" + suf)


# block letters (unit glyph: 0.6 wide, 1.0 tall) as rectangles (x0, z0, x1, z1) - service markings
# are geometry like the lettering on the emergency vehicles ("HBPD", "HBFD" = Halcyon Bay Police /
# Fire Dept.)
_GLYPHS = {
    "H": ((0.0, 0.0, 0.18, 1.0), (0.42, 0.0, 0.60, 1.0), (0.18, 0.41, 0.42, 0.59)),
    "B": ((0.0, 0.0, 0.18, 1.0), (0.18, 0.82, 0.50, 1.0), (0.18, 0.41, 0.50, 0.59), (0.18, 0.0, 0.50, 0.18),
          (0.42, 0.59, 0.60, 0.82), (0.42, 0.18, 0.60, 0.41)),
    "P": ((0.0, 0.0, 0.18, 1.0), (0.18, 0.82, 0.50, 1.0), (0.18, 0.41, 0.50, 0.59), (0.42, 0.59, 0.60, 0.82)),
    "D": ((0.0, 0.0, 0.18, 1.0), (0.18, 0.82, 0.45, 1.0), (0.18, 0.0, 0.45, 0.18), (0.42, 0.18, 0.60, 0.82)),
    "F": ((0.0, 0.0, 0.18, 1.0), (0.18, 0.82, 0.60, 1.0), (0.18, 0.41, 0.50, 0.59)),
}


def _text(p, text, y, cz, h, mat, bone, back=True, depth=0.006):
    """Raised block lettering centred on x = 0 at height cz. y = centre plane of the letters.
    back=True: read from behind the character, otherwise from the front."""
    gw, gap = 0.6 * h, 0.24 * h
    total = len(text) * gw + (len(text) - 1) * gap
    sx = 1.0 if back else -1.0
    for i, ch in enumerate(text):
        gx = -total / 2 + i * (gw + gap)
        for (ax, az, bx, bz) in _GLYPHS[ch]:
            xc = sx * (gx + (ax + bx) / 2 * h)
            p.box(((bx - ax) * h, depth, (bz - az) * h), (xc, y, cz - h / 2 + (az + bz) / 2 * h), mat, bone)


def build_outfit(kind, body):
    p = Part("Outfit_%s_%s" % (kind, body))
    rn = BODY[body]["neck"]
    fem = body == "F"
    if kind == "Police":
        SH, TR, BK, GOLD = "P_PoliceBlue", "P_UniformNavy", "P_Black", "P_BadgeGold"
        prof = add_torso(p, body, SH, grow=0.006, tucked=True)
        add_arms(p, body, "short", SH, grow=0.010, cuff_mat=TR, sleeve_len=0.165)
        _collar_wings(p, body, SH)
        strip_x(p, prof, 1.03, 1.452, -0.017, 0.017, thick=0.005, mat=SH)
        _buttons(p, prof, (1.10, 1.20, 1.30), BK, 0.010, out=0.007)
        for s in (-1, 1):
            x0, x1 = (0.066, 0.128) if s > 0 else (-0.128, -0.066)
            strip_x(p, prof, 1.245, 1.322, x0, x1, thick=0.006, mat=SH)
            strip_x(p, prof, 1.316, 1.342, x0 - 0.003, x1 + 0.003, thick=0.010, mat=TR)
            # epaulettes
            p.box((0.082, 0.050, 0.012), (s * 0.128, 0.0, 1.472), TR, w_torso, rot=(0, s * 0.30, 0))
            p.box((0.012, 0.052, 0.014), (s * 0.150, 0.0, 1.466), GOLD, w_torso, rot=(0, s * 0.30, 0))
        y = front_y(prof, -0.097, 1.378)
        p.box((0.038, 0.010, 0.046), (-0.097, y + 0.005, 1.380), GOLD, w_torso, rot=(math.pi, 0, 0.30), taper=(2, 0.45))
        y = front_y(prof, 0.097, 1.368)
        p.box((0.052, 0.008, 0.014), (0.097, y + 0.005, 1.368), "P_White", w_torso, rot=(0, 0, -0.30))
        y = front_y(prof, -0.118, 1.418)
        p.box((0.034, 0.026, 0.050), (-0.122, y + 0.006, 1.425), BK, w_torso, rot=(0.25, 0, 0.5))
        for s, suf in SIDES:                        # department patches on the sleeves
            rr = BODY[body]["arm"]["up"] + 0.012
            p.box((0.046, 0.040, 0.008), (s * (SH_X + 0.092), 0.0, SH_Z + rr), GOLD, "UpperArm" + suf, taper=(0, 0.55, s))
            p.box((0.022, 0.020, 0.010), (s * (SH_X + 0.086), 0.0, SH_Z + rr), TR, "UpperArm" + suf)
        # trousers + duty belt
        pel = add_pelvis(p, body, TR, grow=0.002)
        add_legs(p, body, TR, grow=0.010, length="long", straight=0.45)
        side_stripe(p, body, 0.010, 0.45, GOLD)
        _belt(p, pel, mat=BK, buckle="P_Chrome", z=1.006, h=0.050, grow=0.008, bw=0.046)
        _hip_box(p, pel, -32, 1.004, (0.050, 0.030, 0.072), BK, grow=0.008, taper=(2, 0.9))
        _hip_box(p, pel, 32, 1.004, (0.050, 0.030, 0.072), BK, grow=0.008, taper=(2, 0.9))
        _hip_box(p, pel, 160, 1.004, (0.066, 0.030, 0.056), BK, grow=0.008)
        _hip_box(p, pel, 200, 1.004, (0.050, 0.028, 0.060), BK, grow=0.008)
        _hip_box(p, pel, -92, 1.010, (0.046, 0.034, 0.090), "P_Charcoal", grow=0.008)
        q = poly_pt(prof_at(pel, 1.01, 0.008), -92)
        p.cyl(0.005, 0.070, (q.x - 0.020, q.y - 0.006, 1.085), BK, "Hips", segments=5)
        _hip_box(p, pel, 92, 0.950, (0.060, 0.040, 0.160), BK, grow=0.006, taper=(2, 1.15))
        q = poly_pt(prof_at(pel, 1.0, 0.008), 92)
        p.box((0.030, 0.050, 0.060), (q.x + 0.024, q.y - 0.022, 1.050), "P_GunMetal", "Hips", rot=(0.35, 0, 0))
    elif kind == "Tactical":
        BK, CH = "P_TacticalBlack", "P_Charcoal"
        prof = add_torso(p, body, BK, grow=0.006, tucked=True)
        add_arms(p, body, "long", BK, grow=0.010, cuff_mat=CH)
        _collar_band(p, body, BK, 1.462, 1.512, 0.012)
        # plate carrier
        vest = [(1.040, ) + prof_at(prof, 1.040, 0.020), (1.070, ) + prof_at(prof, 1.070, 0.030), (1.25, ) + prof_at(prof, 1.25, 0.030),
                (1.365, ) + prof_at(prof, 1.365, 0.026), (1.398, ) + prof_at(prof, 1.398, 0.010)]
        p.loft([sec(*r) for r in vest], CH, w_torso)
        _strap_over_shoulder(p, body, prof, 0.098 if not fem else 0.086, 1.37, CH, width=0.056, thick=0.022)
        for a in (-24, 0, 24):
            q = poly_pt(prof_at(vest, 1.115), a)
            yaw = math.radians(-a) * 0.8
            p.box((0.050, 0.034, 0.100), (q.x, q.y + 0.010, 1.118), BK, w_torso, rot=(0, 0, yaw))
            p.box((0.054, 0.038, 0.026), (q.x, q.y + 0.012, 1.162), CH, w_torso, rot=(0, 0, yaw))
        y = front_y(vest, 0.0, 1.31)
        p.box((0.150, 0.010, 0.040), (0, y + 0.002, 1.315), "P_PoliceWhite", w_torso)
        _text(p, "HBPD", y + 0.0075, 1.315, 0.026, BK, w_torso, back=False, depth=0.005)
        p.box((0.110, 0.026, 0.050), (0, y + 0.008, 1.250), BK, w_torso)
        yb = back_y(vest, 0.0, 1.30)
        p.box((0.200, 0.010, 0.052), (0, yb - 0.002, 1.305), "P_PoliceWhite", w_torso)
        _text(p, "HBPD", yb - 0.0075, 1.305, 0.036, BK, w_torso, back=True, depth=0.005)
        p.box((0.150, 0.030, 0.110), (0, yb - 0.010, 1.165), BK, w_torso)
        y = front_y(vest, -0.105, 1.37)
        p.box((0.036, 0.030, 0.064), (-0.108, y + 0.006, 1.385), BK, w_torso, rot=(0.2, 0, 0.3))
        for s, suf in SIDES:
            p.box((0.094, 0.110, 0.030), (s * (SH_X + 0.034), 0.0, SH_Z + (0.064 if not fem else 0.056)), CH, "UpperArm" + suf,
                  rot=(0, s * 0.30, 0), taper=(0, 0.8, s))
            p.box((0.080, 0.032, 0.076), (s * (EL_X + 0.012), -(BODY[body]["arm"]["el"] + 0.014), SH_Z), CH, "LowerArm" + suf)
        # trousers
        pel = add_pelvis(p, body, BK, grow=0.006)
        add_legs(p, body, BK, grow=0.014, length="long", straight=0.50)
        _belt(p, pel, mat=CH, buckle="P_Steel", z=1.004, h=0.046, grow=0.006, bw=0.040)
        _hip_box(p, pel, -90, 1.000, (0.060, 0.032, 0.080), CH, grow=0.006)
        _hip_box(p, pel, 180, 1.000, (0.110, 0.034, 0.060), CH, grow=0.006)
        _knee_pads(p, CH, BODY[body]["leg"]["kn"][1] + 0.014 + 0.012)
        for s, suf in SIDES:
            xo = leg_outer_x(body, 0.70, 0.014, 0.5)
            if s < 0:
                p.box((0.030, 0.105, 0.125), (s * (xo + 0.004), 0.0, 0.700), BK, "UpperLeg" + suf)
                p.box((0.034, 0.112, 0.034), (s * (xo + 0.005), 0.0, 0.760), CH, "UpperLeg" + suf)
            else:
                # thigh holster
                p.box((0.036, 0.074, 0.170), (s * (xo + 0.012), 0.004, 0.720), CH, "UpperLeg" + suf, taper=(2, 1.12))
                p.box((0.030, 0.050, 0.060), (s * (xo + 0.014), -0.016, 0.826), "P_GunMetal", "UpperLeg" + suf, rot=(0.35, 0, 0))
                leg_piece(p, body, "upper", 0.150, 0.172, 0.020, CH, straight=0.5, sides=((s, suf),))
                leg_piece(p, body, "upper", 0.235, 0.257, 0.020, CH, straight=0.5, sides=((s, suf),))
    elif kind == "Medic":
        TOP, TR, W = "P_Teal", "P_Charcoal", "P_White"
        prof = add_torso(p, body, TOP, grow=0.006, tucked=True)
        add_arms(p, body, "short", TOP, grow=0.010, cuff_mat=W, sleeve_len=0.16)
        _collar_wings(p, body, W)
        strip_x(p, prof, 1.03, 1.452, -0.012, 0.012, thick=0.005, mat=W)
        ring_band(p, prof, 1.268, 1.300, 0.004, W)
        # emblem (original: white octagon with a coral diamond)
        y = front_y(prof, -0.098, 1.365)
        p.cyl(0.027, 0.010, (-0.098, y + 0.003, 1.368), W, w_torso, axis='Y', segments=8, rot=(0, 0, 0.30))
        p.box((0.022, 0.012, 0.022), (-0.098, y + 0.005, 1.368), "P_Coral", w_torso, rot=(0, math.pi / 4, 0.30))
        yb = back_y(prof, 0.0, 1.365)               # ... and large on the back
        p.cyl(0.056, 0.010, (0, yb - 0.001, 1.368), W, w_torso, axis='Y', segments=8, rot=(0, math.pi / 8, 0))
        p.box((0.046, 0.012, 0.046), (0, yb - 0.003, 1.368), "P_Coral", w_torso, rot=(0, math.pi / 4, 0))
        for s in (-1, 1):
            p.box((0.050, 0.060, 0.012), (s * 0.132, 0.0, 1.470), "P_SafetyOrange", w_torso, rot=(0, s * 0.30, 0))
        # stethoscope
        ST = "P_Charcoal"
        p.arc_sweep([(40, rn + 0.020, 1.474, 0.007, 0.007), (90, rn + 0.022, 1.480, 0.007, 0.007), (180, rn + 0.024, 1.482, 0.007, 0.007),
                     (270, rn + 0.022, 1.480, 0.007, 0.007), (320, rn + 0.020, 1.474, 0.007, 0.007)], ST, "Chest", n=4)
        for s in (-1, 1):
            xa = s * math.sin(math.radians(40)) * (rn + 0.020)
            pts = [(xa, front_y(prof, xa, 1.45) + 0.012, 1.468), (s * 0.040, front_y(prof, s * 0.04, 1.39) + 0.008, 1.390),
                   (s * 0.022, front_y(prof, s * 0.022, 1.31) + 0.008, 1.320), (0.0, front_y(prof, 0.0, 1.25) + 0.008, 1.262)]
            p.path_tube(pts, 0.006, ST, w_torso, n=4)
        y = front_y(prof, 0.0, 1.24)
        p.cyl(0.018, 0.012, (0, y + 0.010, 1.245), "P_Chrome", w_torso, axis='Y', segments=8)
        pel = add_pelvis(p, body, TR, grow=0.002)
        add_legs(p, body, TR, grow=0.010, length="long", straight=0.45)
        leg_piece(p, body, "lower", 0.225, 0.262, 0.015, W, straight=0.45)
        _belt(p, pel, mat="P_Black", buckle="P_Chrome", h=0.032, grow=0.006, bw=0.036)
        _hip_box(p, pel, 88, 0.985, (0.074, 0.040, 0.084), "P_Coral", grow=0.006)
        _hip_box(p, pel, 88, 1.012, (0.078, 0.044, 0.024), W, grow=0.006)
        _hip_box(p, pel, -40, 1.004, (0.044, 0.028, 0.060), "P_Black", grow=0.006)
    elif kind == "Firefighter":
        KH, HY, ST = "P_Khaki", "P_HazardYellow", "P_Steel"
        prof = add_torso(p, body, KH, grow=0.022, hem_z=0.872, hem_extra=0.018, ease=0.022, shoulder=1.03)
        ring_band(p, prof, 1.250, 1.292, 0.005, HY)
        ring_band(p, prof, 1.262, 1.280, 0.007, ST)
        ring_band(p, prof, 0.885, 0.930, 0.005, HY)
        ring_band(p, prof, 0.899, 0.916, 0.007, ST)
        strip_x(p, prof, 0.878, 1.450, -0.034, 0.034, thick=0.011, mat=KH)
        for z in (0.98, 1.09, 1.20, 1.36):
            y = front_y(prof, 0.0, z)
            p.box((0.056, 0.012, 0.020), (0.006, y + 0.012, z), ST, w_torso)
        p.tube((0, 0.004, 1.456), (0, 0, 1), (1, 0, 0), (0, 1, 0),
               [(0.0, rn + 0.034, rn + 0.034), (0.050, rn + 0.026, rn + 0.026), (0.062, rn + 0.018, rn + 0.018)], KH, "Chest", n=8)
        add_arms(p, body, "long", KH, grow=0.020, cuff_mat=KH)
        arm_piece(p, body, "upper", 0.120, 0.160, 0.025, HY)
        arm_piece(p, body, "fore", 0.130, 0.170, 0.025, HY)
        pel = add_pelvis(p, body, KH, grow=0.008)
        add_legs(p, body, KH, grow=0.017, length="long", straight=0.65)
        leg_piece(p, body, "lower", 0.215, 0.262, 0.022, HY, straight=0.65)
        leg_piece(p, body, "lower", 0.230, 0.247, 0.024, ST, straight=0.65)
        _knee_pads(p, KH, BODY[body]["leg"]["kn"][1] + 0.017 + 0.012, size=(0.120, 0.030, 0.120))
        # department panel on the back of the coat
        yb = back_y(prof, 0.0, 1.365)
        p.box((0.200, 0.010, 0.058), (0, yb - 0.002, 1.368), HY, w_torso)
        _text(p, "HBFD", yb - 0.0075, 1.368, 0.036, "P_Charcoal", w_torso, back=True, depth=0.005)
        # radio pocket on the chest
        y = front_y(prof, 0.105, 1.36)
        p.box((0.046, 0.030, 0.090), (0.108, y + 0.006, 1.360), "P_Charcoal", w_torso, rot=(0, 0, -0.3))
    elif kind == "Staff":
        prof = add_torso(p, body, "M_Top", grow=0.005, tucked=True)
        add_arms(p, body, "short", "M_Top", grow=0.009, cuff_mat="M_Top")
        _collar_wings(p, body, "M_Top")
        strip_x(p, prof, 1.33, 1.452, -0.012, 0.012, thick=0.004, mat="M_Top")
        pel = add_pelvis(p, body, "M_Bottom", grow=0.002)
        add_legs(p, body, "M_Bottom", grow=0.010, length="long", straight=0.55)
        AP = "M_Top_Accent"
        # apron: bib + skirt + waist tie + neck straps
        bib_top = 1.345 if not fem else 1.335
        strip_a(p, prof, 1.020, bib_top, (lambda z: -lerp(46, 30, clamp01((z - 1.02) / 0.32))),
                (lambda z: lerp(46, 30, clamp01((z - 1.02) / 0.32))), thick=0.008, mat=AP, bone=w_torso)
        allp = [(0.800, pel[1][1] + 0.004, pel[1][2] + 0.006, pel[1][3] + 0.004), pel[1], pel[2], (1.03, ) + prof_at(prof, 1.03)]
        strip_a(p, allp, 0.800, 1.028, -78, 78, thick=0.010, mat=AP, bone=w_apron, grow=0.004)
        ring_band(p, pel, 0.995, 1.030, 0.011, AP, "Hips")
        strip_a(p, allp, 0.900, 0.985, -26, 26, thick=0.018, mat=AP, bone=w_apron, grow=0.004)
        dims = prof_at(prof, bib_top - 0.01)
        for s in (-1, 1):
            q = poly_pt(dims, s * 28)
            pts = [(q.x, q.y + 0.002, bib_top - 0.012), (s * 0.070, front_y(prof, s * 0.07, 1.42) + 0.004, 1.420),
                   (s * (rn + 0.022), 0.030, 1.478), (s * (rn + 0.012), -0.040, 1.486)]
            p.path_tube(pts, 0.016, AP, w_torso, n=4, side=(1, 0, 0), flat=0.45)
        p.arc_sweep([(100, rn + 0.016, 1.486, 0.010, 0.012), (180, rn + 0.020, 1.486, 0.010, 0.012), (260, rn + 0.016, 1.486, 0.010, 0.012)],
                    AP, "Chest", n=4)
        y = front_y(prof, -0.062, 1.30)
        p.box((0.050, 0.008, 0.018), (-0.062, y + 0.010, 1.300), "P_White", w_torso, rot=(0, 0, 0.12))
    else:
        raise KeyError(kind)
    p.skin_rest(w_torso)
    return p.finish(npc=True)


# ------------------------------------------------------------------------------------------------
# registry of builders
# ------------------------------------------------------------------------------------------------
TOPS = ("Tee", "Shirt", "Hoodie", "Jacket", "Tank", "Suit", "Vest")
BOTTOMS = ("Jeans", "Shorts", "Cargo", "Slacks")
SHOES = ("Sneakers", "Boots", "Dress")
HATS = ("Cap", "Beanie", "Brim", "Bandana", "Police", "Helmet", "FireHelmet")
GLASSES = ("Shades", "Round", "Goggles")
BEARDS = ("Full", "Goatee", "Mustache")
OUTFITS = ("Police", "Tactical", "Medic", "Firefighter", "Staff")


def part_builders():
    b = {}
    b["Head_M"] = lambda: build_head("M")
    b["Head_F"] = lambda: build_head("F")
    b["Hands"] = build_hands
    for k in HAIR_STYLES:
        b["Hair_" + k] = (lambda k=k: build_hair(k))
        b["Hair_" + k + "_Hat"] = (lambda k=k: build_hair(k, True))
    for k in BEARDS:
        b["Beard_" + k] = (lambda k=k: build_beard(k))
    for k in SHOES:
        b["Shoes_" + k] = (lambda k=k: build_shoes(k))
    for k in HATS:
        b["Hat_" + k] = (lambda k=k: build_hat(k))
    for k in GLASSES:
        b["Glasses_" + k] = (lambda k=k: build_glasses(k))
    for body in ("M", "F"):
        for k in TOPS:
            b["Top_%s_%s" % (k, body)] = (lambda k=k, body=body: build_top(k, body))
        for k in BOTTOMS:
            b["Bottom_%s_%s" % (k, body)] = (lambda k=k, body=body: build_bottom(k, body))
        for k in OUTFITS:
            b["Outfit_%s_%s" % (k, body)] = (lambda k=k, body=body: build_outfit(k, body))
    b["Bottom_Skirt_F"] = lambda: build_bottom("Skirt", "F")
    return b


def build(names=None, prefix=None):
    """Build (or rebuild) the named parts; None = everything; prefix = all parts starting with it."""
    G.object_mode()
    build_armature()
    b = part_builders()
    if names is None:
        names = [n for n in b.keys() if prefix is None or n.startswith(prefix)]
    out = []
    for n in names:
        ob = b[n]()
        if ob is not None:
            out.append((n, len(ob.data.loop_triangles)))
    return out


def build_all():
    return build(None)


def part_names():
    arm = bpy.data.objects.get(ARM)
    return sorted(o.name for o in arm.children if o.type == 'MESH')


def tri_report():
    arm = bpy.data.objects.get(ARM)
    rep = {}
    for o in arm.children:
        if o.type == 'MESH':
            o.data.calc_loop_triangles()
            rep[o.name] = len(o.data.loop_triangles)
    return rep


# ------------------------------------------------------------------------------------------------
# posing + previews
# ------------------------------------------------------------------------------------------------
def _axis_rot(axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, axis)


POSES = {
    "tpose": {},
    "arms_down": {"UpperArm_R": [('Y', 76)], "UpperArm_L": [('Y', -76)], "LowerArm_R": [('Z', 12)], "LowerArm_L": [('Z', -12)]},
    "walk": {"UpperArm_R": [('Y', 76), ('X', 28)], "UpperArm_L": [('Y', -76), ('X', -28)],
             "LowerArm_R": [('Z', 20)], "LowerArm_L": [('Z', -38)],
             "UpperLeg_R": [('X', -24)], "LowerLeg_R": [('X', -30)], "UpperLeg_L": [('X', 30)], "LowerLeg_L": [('X', -12)],
             "Foot_L": [('X', 10)], "Foot_R": [('X', -20)], "Spine": [('X', 4)]},
    "seated": {"UpperLeg_R": [('X', 88)], "UpperLeg_L": [('X', 88)], "LowerLeg_R": [('X', -86)], "LowerLeg_L": [('X', -86)],
               "UpperArm_R": [('Y', 50), ('Z', 40)], "UpperArm_L": [('Y', -50), ('Z', -40)],
               "LowerArm_R": [('Z', 45)], "LowerArm_L": [('Z', -45)], "Spine": [('X', -4)]},
    "aim": {"UpperArm_R": [('Z', 82), ('Y', 4)], "UpperArm_L": [('Z', -62), ('Y', -6)],
            "LowerArm_R": [('Z', 8)], "LowerArm_L": [('Z', -48)], "Head": [('X', 3)], "Chest": [('Z', -8)]},
    "crouch": {"UpperLeg_R": [('X', 70)], "UpperLeg_L": [('X', 40)], "LowerLeg_R": [('X', -110)], "LowerLeg_L": [('X', -100)],
               "Spine": [('X', 18)], "UpperArm_R": [('Y', 70)], "UpperArm_L": [('Y', -70)]},
}


def set_pose(pose):
    """pose: {bone: [(model axis 'X'|'Y'|'Z', degrees), ...]} applied in order, in rest model axes."""
    arm = bpy.data.objects[ARM]
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Quaternion()
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
    if isinstance(pose, str):
        pose = POSES[pose]
    for name, rots in (pose or {}).items():
        pb = arm.pose.bones[name]
        R = pb.bone.matrix_local.to_3x3()
        Q = Matrix.Identity(3)
        for axis, deg in rots:
            Q = _axis_rot(axis, deg) @ Q
        pb.rotation_quaternion = (R.inverted() @ Q @ R).to_quaternion()
    bpy.context.view_layer.update()


def look_preview(out_name, parts, views=("front", "three_quarter", "side", "back"), pose=None, res=512, cull=True, margin=1.12):
    """Contact sheet of one complete look (list of part names), optionally posed."""
    arm = bpy.data.objects[ARM]
    missing = [n for n in parts if bpy.data.objects.get(n) is None]
    if missing:
        print("look_preview: missing parts", missing)
    changed = []
    for o in arm.children:
        want_hidden = o.name not in parts
        if o.hide_render != want_hidden:
            changed.append((o, o.hide_render))
            o.hide_render = want_hidden
    sh = bpy.context.scene.display.shading
    old_cull = sh.show_backface_culling
    sh.show_backface_culling = cull
    try:
        if pose:
            set_pose(pose)
        return G.preview(ROOT, out_name, views=views, res=res, margin=margin)
    finally:
        set_pose(None)
        sh.show_backface_culling = old_cull
        for o, h in changed:
            o.hide_render = h


def multi_preview(out_name, combos, views=("front", "three_quarter", "side", "rear_quarter"), res=300, pose=None,
                  margin=1.12, per_row=2):
    """Several looks (lists of part names) in ONE png: each look is a 2x2 contact sheet."""
    import numpy as np
    import os
    tiles = []
    for i, parts in enumerate(combos):
        path = look_preview("_tmp_multi_%s_%d" % (out_name, i), parts, views=views, pose=pose, res=res, margin=margin)
        img = bpy.data.images.load(path, check_existing=False)
        w, h = img.size
        arr = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(arr)
        tiles.append(arr.reshape(h, w, 4))
        bpy.data.images.remove(img)
        try:
            os.remove(path)
        except Exception:
            pass
    th, tw = tiles[0].shape[0], tiles[0].shape[1]
    rows = (len(tiles) + per_row - 1) // per_row
    sheet = np.zeros((rows * th, per_row * tw, 4), dtype=np.float32)
    sheet[..., 3] = 1.0
    for i, t in enumerate(tiles):
        rr = rows - 1 - (i // per_row)
        cc = i % per_row
        sheet[rr * th:(rr + 1) * th, cc * tw:(cc + 1) * tw, :] = t
    out = bpy.data.images.new("_chr_multi", per_row * tw, rows * th, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    out_path = os.path.join(G.PREVIEW_DIR, out_name + ".png")
    out.filepath_raw = out_path
    out.file_format = 'PNG'
    out.save()
    bpy.data.images.remove(out)
    print("PREVIEW_SAVED:", out_path)
    return out_path


LOOKS = {
    "player": ["Head_M", "Hair_Short", "Hands", "Top_Jacket_M", "Bottom_Jeans_M", "Shoes_Sneakers"],
    "civ_m": ["Head_M", "Hair_Slick", "Beard_Full", "Hands", "Top_Tee_M", "Bottom_Cargo_M", "Shoes_Boots", "Glasses_Shades"],
    "civ_f": ["Head_F", "Hair_Long", "Hands", "Top_Tank_F", "Bottom_Skirt_F", "Shoes_Sneakers"],
    "police": ["Head_M", "Hair_Short_Hat", "Hands", "Outfit_Police_M", "Hat_Police", "Shoes_Boots"],
    "tactical": ["Head_M", "Hands", "Outfit_Tactical_M", "Hat_Helmet", "Glasses_Goggles", "Shoes_Boots"],
    "medic": ["Head_F", "Hair_Ponytail", "Hands", "Outfit_Medic_F", "Shoes_Sneakers"],
    "firefighter": ["Head_M", "Beard_Mustache", "Hands", "Outfit_Firefighter_M", "Hat_FireHelmet", "Shoes_Boots"],
    "staff": ["Head_F", "Hair_Curly", "Hands", "Outfit_Staff_F", "Shoes_Sneakers", "Glasses_Round"],
    "gang": ["Head_M", "Hair_Buzz_Hat", "Beard_Goatee", "Hands", "Top_Vest_M", "Bottom_Jeans_M", "Shoes_Boots", "Hat_Bandana"],
    "suit": ["Head_M", "Hair_Slick", "Hands", "Top_Suit_M", "Bottom_Slacks_M", "Shoes_Dress"],
}


# ------------------------------------------------------------------------------------------------
# Blender-authored loops (bonus - the game's main animation is the procedural HumanoidAnimator)
# ------------------------------------------------------------------------------------------------
# Actions are named "Humanoid_<Clip>" (unique in the shared .blend) and stashed in muted NLA tracks
# of OUR armature, so they never drive the rest pose and survive in the file. CharacterVisual
# strips the prefix: the clips are called "Idle", "Walk", "Run" in the game.
CLIP_PREFIX = "Humanoid_"
CLIPS = (("Idle", 3.0), ("Walk", 1.0), ("Run", 0.6667))      # (name, loop length in seconds)
_SOLE_PTS = ((-0.085, 0.0), (0.0, 0.0), (0.140, 0.0), (0.205, 0.012))   # (y, z) under each foot: heel .. toe tip
# Wanted world pitch of the foot (degrees, + = toes up) over one step; u = 0 when the leg is fully
# forward. set_clip_pose() then clamps it against the ground, so a foot that carries weight stays
# planted (heel strike -> flat -> heel rises and the toe peels off) without any hand tuning.
_FOOT_WALK = ((0.0, 12.0), (0.08, 0.0), (0.30, 0.0), (0.50, -38.0), (0.62, -45.0), (0.85, -5.0), (1.0, 12.0))
_FOOT_RUN = ((0.0, -2.0), (0.15, 4.0), (0.21, 0.0), (0.27, -8.0), (0.34, -40.0), (0.42, -58.0), (0.60, -62.0), (0.85, -15.0),
             (1.0, -2.0))


def _key_curve(keys, u):
    """Smooth-stepped periodic curve through (u, value) keys, u in 0..1."""
    u = u % 1.0
    for (u0, v0), (u1, v1) in zip(keys[:-1], keys[1:]):
        if u0 <= u <= u1:
            t = (u - u0) / (u1 - u0)
            return v0 + (v1 - v0) * t * t * (3.0 - 2.0 * t)
    return keys[0][1]


def clip_pose(name, p):
    """Pose of clip `name` at phase p (0..1): {bone: [(model axis, degrees), ...]} (see set_pose).
    Conventions (rest model axes): legs +X = forward, knees flex with -X, feet +X = toes up,
    spine / head -X = lean forward, R arm ('Y', +) = down, arms ('X', +) = swing forward,
    forearm R ('Z', +) / L ('Z', -) = flex, +Z = turn left."""
    ph = 2.0 * math.pi * p
    s = math.sin(ph)
    pose = {}
    if name == "Idle":
        b = s                              # breathing
        w = math.sin(ph + 1.1)             # slow drift of head / arms
        pose["Hips"] = [('Z', 0.8 * w)]
        pose["Spine"] = [('X', -1.0 + 0.5 * b), ('Z', -0.5 * w)]
        pose["Chest"] = [('X', 0.9 * b)]
        pose["Neck"] = [('X', -0.4 * b)]
        pose["Head"] = [('X', -0.3 * b + 0.6 * w), ('Z', 2.5 * w)]
        pose["Shoulder_R"] = [('Y', -1.6 * b)]
        pose["Shoulder_L"] = [('Y', 1.6 * b)]
        pose["UpperArm_R"] = [('Y', 77.0 + 1.0 * b), ('X', 3.0 + 1.5 * w)]
        pose["UpperArm_L"] = [('Y', -77.0 - 1.0 * b), ('X', 3.0 - 1.5 * w)]
        pose["LowerArm_R"] = [('Z', 14.0 + 2.0 * b)]
        pose["LowerArm_L"] = [('Z', -14.0 - 2.0 * b)]
        for suf in ("_L", "_R"):
            pose["UpperLeg" + suf] = [('X', 2.5)]
            pose["LowerLeg" + suf] = [('X', -5.0)]
            pose["Foot" + suf] = [('X', 2.5)]
        return pose
    run = name == "Run"
    if name not in ("Walk", "Run"):
        raise KeyError(name)
    for sgn, suf, th in ((1.0, "_R", ph), (-1.0, "_L", ph + math.pi)):
        st = math.sin(th)                         # +1: this leg is fully forward
        # knee flexion peaks in early swing: it starts before toe-off, so the trailing toe does not
        # dig into the ground and the hips sink (instead of rising) while both feet are down
        swing = max(0.0, math.cos(th + (0.40 if run else 0.50)))
        u = (th - math.pi / 2.0) / (2.0 * math.pi)     # 0 = this foot strikes the ground
        if run:
            thigh = 12.0 + 40.0 * st
            push = max(0.0, math.sin(3.0 * (th % (2.0 * math.pi) - math.radians(190.0))))
            if not (math.radians(190.0) < th % (2.0 * math.pi) < math.radians(250.0)):
                push = 0.0                        # the knee extends while the foot pushes off
            knee = -(32.0 - 12.0 * push + 72.0 * swing ** 1.2)
            foot = _key_curve(_FOOT_RUN, u) - thigh - knee
            arm = 6.0 - 44.0 * st                 # arms counter-swing the legs
            fore = 78.0 + 12.0 * max(0.0, -st)
            down = 74.0
        else:
            thigh = 2.0 + 23.0 * st
            knee = -(5.0 + 55.0 * swing ** 1.3)
            foot = _key_curve(_FOOT_WALK, u) - thigh - knee
            arm = 1.0 - 23.0 * st
            fore = 16.0 + 14.0 * max(0.0, -st)
            down = 77.0
        pose["UpperLeg" + suf] = [('X', thigh)]
        pose["LowerLeg" + suf] = [('X', knee)]
        pose["Foot" + suf] = [('X', max(-55.0, min(40.0, foot)))]
        pose["UpperArm" + suf] = [('Y', sgn * down), ('X', arm)]
        pose["LowerArm" + suf] = [('Z', sgn * fore)]
    tw = 8.0 if run else 5.0                       # pelvis follows the leading leg, chest counters
    pose["Hips"] = [('Z', tw * s)]
    pose["Spine"] = [('X', -9.0 if run else -2.5), ('Z', -0.8 * tw * s)]
    pose["Chest"] = [('X', -4.0 if run else -0.5), ('Z', -1.0 * tw * s)]
    pose["Neck"] = [('X', 4.0 if run else 0.5)]
    pose["Head"] = [('X', 7.0 if run else 2.0), ('Z', 0.8 * tw * s)]
    return pose


def clip_hips_dz(name, p):
    """Analytic vertical bob of the hips (metres, relative to the rest height)."""
    ph = 2.0 * math.pi * p
    if name == "Walk":
        return -0.045 * math.sin(ph) ** 2                 # lowest when both feet are down
    if name == "Run":
        return -0.0165 + 0.0165 * math.cos(2.0 * (ph - math.radians(95.0)))  # lowest in stance, peak in flight
    return 0.0


def _sole_limits(h):
    """For an ankle at height h: (lowest pitch, highest pitch, penetration). Pitches in degrees
    (+ = toes up) between which no sole point is below the ground; penetration > 0 when even the
    flat foot is too low."""
    pts = [(y * SHOE_L, z - ANK_Z) for (y, z) in _SOLE_PTS]

    def low(a_deg):
        a = math.radians(a_deg)
        return h + min(y * math.sin(a) + z * math.cos(a) for y, z in pts)
    if low(0.0) < 0.0:
        return 0.0, 0.0, -low(0.0)
    a_hi = 0.0
    while a_hi < 45.0 and low(a_hi + 0.5) >= 0.0:
        a_hi += 0.5
    a_lo = 0.0
    while a_lo > -75.0 and low(a_lo - 0.5) >= 0.0:
        a_lo -= 0.5
    return a_lo, a_hi, 0.0


def set_clip_pose(name, p):
    """Pose the armature like phase `p` (0..1) of a clip and resolve the feet against the ground.
    Returns the hips offset that was applied."""
    arm = bpy.data.objects[ARM]
    hips = arm.pose.bones["Hips"]
    to_local = hips.bone.matrix_local.to_3x3().inverted()
    pose = clip_pose(name, p)
    dz = clip_hips_dz(name, p)
    for it in range(3):
        set_pose(pose)
        hips.location = to_local @ Vector((0.0, 0.0, dz))
        bpy.context.view_layer.update()
        if name == "Idle" or it == 2:      # the last pass only applies what the first two solved
            break
        pen = 0.0
        for _sgn, suf in SIDES:
            pb = arm.pose.bones["Foot" + suf]
            M = pb.matrix @ pb.bone.matrix_local.inverted()
            fwd = M.to_3x3() @ Vector((0.0, 1.0, 0.0))
            a_now = math.degrees(math.atan2(fwd.z, math.hypot(fwd.x, fwd.y)))
            a_lo, a_hi, pn = _sole_limits(pb.matrix.translation.z)
            pen = max(pen, pn)
            a_new = min(max(a_now, a_lo), a_hi)
            if abs(a_new - a_now) > 1e-3:
                cur = pose["Foot" + suf][0][1]
                pose["Foot" + suf] = [('X', cur + (a_new - a_now))]
        dz += pen
    return dz


def remove_clips():
    """Remove OUR actions / NLA tracks (names starting with CLIP_PREFIX) from our armature."""
    arm = bpy.data.objects.get(ARM)
    if arm is None or arm.parent is None or arm.parent.name != ROOT:
        return 0
    ad = arm.animation_data
    if ad is not None:
        ad.action = None
        for tr in [t for t in ad.nla_tracks if t.name.startswith(CLIP_PREFIX)]:
            ad.nla_tracks.remove(tr)
    n = 0
    for act in [a for a in bpy.data.actions if a.name.startswith(CLIP_PREFIX)]:
        bpy.data.actions.remove(act)
        n += 1
    return n


def clip_names():
    return sorted(a.name[len(CLIP_PREFIX):] for a in bpy.data.actions if a.name.startswith(CLIP_PREFIX))


def build_clips():
    """Key the loops with pose_bone.keyframe_insert (one key per frame, every bone) and stash each
    action in a muted NLA track. Re-runnable. Returns [(clip, frames)]."""
    G.object_mode()
    arm = build_armature()
    remove_clips()
    scene = bpy.context.scene
    fps = scene.render.fps / scene.render.fps_base
    ad = arm.animation_data_create()
    out = []
    hips = arm.pose.bones["Hips"]
    for name, seconds in CLIPS:
        n = max(8, int(round(seconds * fps)))
        # 1) compute every frame while NO action is assigned (nothing can re-evaluate the pose)
        ad.action = None
        frames = []
        prev = {}
        for f in range(n + 1):
            set_clip_pose(name, (f % n) / float(n))
            quats = {}
            for pb in arm.pose.bones:
                q = pb.rotation_quaternion.copy()
                if pb.name in prev and prev[pb.name].dot(q) < 0.0:
                    q.negate()                     # keep the quaternion sign continuous between keys
                prev[pb.name] = q
                quats[pb.name] = q
            frames.append((quats, hips.location.copy()))
        # 2) key them (values are written and keyed without any depsgraph update in between)
        act = bpy.data.actions.new(CLIP_PREFIX + name)
        act.use_fake_user = True
        ad.action = act
        for f, (quats, loc) in enumerate(frames):
            for pb in arm.pose.bones:
                pb.rotation_quaternion = quats[pb.name]
                pb.keyframe_insert("rotation_quaternion", frame=f)
            hips.location = loc
            hips.keyframe_insert("location", frame=f)
        for attr, val in (("use_frame_range", True), ("frame_start", 0), ("frame_end", n), ("use_cyclic", True)):
            try:
                setattr(act, attr, val)
            except Exception as e:
                print("clip %s: could not set %s (%s)" % (name, attr, e))
        slot = getattr(ad, "action_slot", None)
        ad.action = None
        tr = ad.nla_tracks.new()
        tr.name = act.name
        strip = tr.strips.new(act.name, 0, act)
        try:
            if getattr(strip, "action_slot", None) is None:
                strip.action_slot = slot if slot is not None else act.slots[0]
        except Exception as e:
            print("clip %s: NLA slot not assigned (%s)" % (name, e))
        tr.mute = True                             # the exporter looks at strip.mute, not track.mute
        out.append((name, n))
    set_pose(None)
    return out


def clip_preview(out_name, clip, phases=(0.0, 0.25, 0.5, 0.75), look="player", views=("side", "three_quarter"), res=300):
    """Contact sheet of one clip: one tile row per phase (pose computed by the same code that keys it)."""
    import numpy as np
    import os
    tiles = []
    for i, p in enumerate(phases):
        arm = bpy.data.objects[ARM]
        parts = LOOKS[look]
        changed = []
        for o in arm.children:
            want_hidden = o.name not in parts
            if o.hide_render != want_hidden:
                changed.append((o, o.hide_render))
                o.hide_render = want_hidden
        try:
            set_clip_pose(clip, p)
            path = G.preview(ROOT, "_tmp_clip_%s_%d" % (out_name, i), views=views, res=res, margin=1.1)
        finally:
            set_pose(None)
            for o, h in changed:
                o.hide_render = h
        img = bpy.data.images.load(path, check_existing=False)
        w, h = img.size
        arr = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(arr)
        tiles.append(arr.reshape(h, w, 4))
        bpy.data.images.remove(img)
        try:
            os.remove(path)
        except Exception:
            pass
    th, tw = tiles[0].shape[0], tiles[0].shape[1]
    per_row = 2
    rows = (len(tiles) + per_row - 1) // per_row
    sheet = np.zeros((rows * th, per_row * tw, 4), dtype=np.float32)
    sheet[..., 3] = 1.0
    for i, t in enumerate(tiles):
        rr = rows - 1 - (i // per_row)
        cc = i % per_row
        sheet[rr * th:(rr + 1) * th, cc * tw:(cc + 1) * tw, :] = t
    out = bpy.data.images.new("_chr_clip", per_row * tw, rows * th, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    out_path = os.path.join(G.PREVIEW_DIR, out_name + ".png")
    out.filepath_raw = out_path
    out.file_format = 'PNG'
    out.save()
    bpy.data.images.remove(out)
    print("PREVIEW_SAVED:", out_path)
    return out_path


def _export_with_clips(rel_path):
    """Same as G.export_glb(..., animations=True) but WITHOUT the exporter's "single armature"
    rule (which would also pull every other armature action of the shared .blend into our GLB):
    only the actions stashed in the NLA tracks of our armature are exported."""
    import os
    G.object_mode()
    root = bpy.data.objects[ROOT]
    path = os.path.join(G.MODELS_DIR, rel_path.replace("/", os.sep))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    vl = bpy.context.view_layer
    objs = G.children_of(root)
    prev_sel = [o for o in vl.objects if o.select_get()]
    prev_active = vl.objects.active
    saved_loc = root.location.copy()
    saved_rot = root.rotation_euler.copy()
    unhid = []
    try:
        for o in prev_sel:
            o.select_set(False)
        root.location = (0.0, 0.0, 0.0)
        root.rotation_euler = (0.0, 0.0, 0.0)
        for o in objs:
            state = (o, o.hide_viewport, o.hide_get() if o.name in vl.objects else False)
            if state[1] or state[2]:
                unhid.append(state)
                o.hide_viewport = False
                try:
                    o.hide_set(False)
                except Exception:
                    pass
            if o.name in vl.objects:
                o.select_set(True)
        vl.objects.active = root
        vl.update()
        props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
        wanted = {
            "filepath": path, "export_format": 'GLB', "use_selection": True, "export_apply": True,
            "export_yup": True, "export_animations": True, "export_cameras": False, "export_lights": False,
            "export_extras": True, "export_texcoords": True, "export_normals": True,
            "export_materials": 'EXPORT', "export_skins": True, "export_morph": False,
            "use_visible": False, "check_existing": False,
            "export_animation_mode": 'ACTIONS', "export_force_sampling": True, "export_bake_animation": False,
            "export_anim_single_armature": False, "export_reset_pose_bones": True,
            "export_optimize_animation_size": False, "export_nla_strips": True,
        }
        res = bpy.ops.export_scene.gltf(**{k: v for k, v in wanted.items() if k in props})
        if 'FINISHED' not in res:
            raise RuntimeError("glTF export returned %r" % (res,))
    finally:
        root.location = saved_loc
        root.rotation_euler = saved_rot
        for o, hv, hs in unhid:
            try:
                o.hide_viewport = hv
                o.hide_set(hs)
            except Exception:
                pass
        for o in objs:
            try:
                o.select_set(False)
            except Exception:
                pass
        for o in prev_sel:
            try:
                o.select_set(True)
            except Exception:
                pass
        try:
            vl.objects.active = prev_active
        except Exception:
            pass
    return path


def export(animations=None, quiet=True):
    """Export characters/humanoid.glb. animations=None: include the clips when they exist
    (build_clips()); True / False force it."""
    import io
    import os
    import contextlib
    import logging
    set_pose(None)
    if animations is None:
        animations = len(clip_names()) > 0
    rel = "characters/humanoid.glb"

    def run():
        if animations:
            return _export_with_clips(rel)
        return G.export_glb(ROOT, rel, animations=False)
    if quiet:
        logging.disable(logging.INFO)
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                path = run()
        finally:
            logging.disable(logging.NOTSET)
    else:
        path = run()
    set_pose(None)
    print("EXPORTED:", path, "bytes=%d" % os.path.getsize(path), "clips=%s" % (clip_names() if animations else []))
    return path


def final_previews():
    """The QA sheets referenced by docs/CHARACTERS.md (looks, posed deformation checks, clips)."""
    out = []
    out.append(multi_preview("chr_final_looks_a", [LOOKS["player"], LOOKS["civ_m"], LOOKS["civ_f"], LOOKS["police"]], pose="arms_down"))
    out.append(multi_preview("chr_final_looks_b", [LOOKS["tactical"], LOOKS["medic"], LOOKS["firefighter"], LOOKS["staff"]], pose="arms_down"))
    out.append(multi_preview("chr_final_looks_c", [LOOKS["gang"], LOOKS["suit"]], pose="arms_down", per_row=2))
    for pose in ("walk", "seated", "aim", "crouch"):
        out.append(multi_preview("chr_final_pose_" + pose, [LOOKS["player"], LOOKS["civ_f"], LOOKS["police"], LOOKS["tactical"]], pose=pose))
    return out
